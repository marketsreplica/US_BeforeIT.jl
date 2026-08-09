#!/usr/bin/env julia

using LinearAlgebra
using Test
using TOML

include("USRevisedDataSemiStructuralComparison.jl")
using .USRevisedDataSemiStructuralComparison

const M = USRevisedDataSemiStructuralComparison
const BASE = M.USRevisedDataBenchmarkDiagnostic
const BENCH = BASE.USForecastBenchmarks
const FIXTURE_DIRECTORY = joinpath(@__DIR__, "revised_data", "fixtures")

function canonical_panel()
    return BASE.load_revised_quarterly_panel(
        joinpath(FIXTURE_DIRECTORY, "quarterly_panel.csv"),
        joinpath(FIXTURE_DIRECTORY, "manifest.toml"),
    )
end

@testset "registered native-input core-four comparison" begin
    result = run_revised_semi_structural_comparison(canonical_panel())
    semi_id = BENCH.model_id(BENCH.SemiStructuralSpec())

    @test result.contract_id ==
        "beforeit-us-revised-data-semi-structural-comparison.v1"
    @test result.target_ids == [
        "real_gdp",
        "pce_price_index",
        "unemployment_rate",
        "effective_federal_funds_rate",
    ]
    @test result.model_target_names ==
        collect(BENCH.SEMI_STRUCTURAL_TARGET_NAMES)
    @test length(result.model_ids) == 11
    @test last(result.model_ids) == semi_id
    @test result.semi_structural_model_id == semi_id
    @test result.semi_structural_benchmark_included
    @test result.equilibrium_oriented_comparator_included
    @test !result.dsge_benchmark_included
    @test !result.abm_forecast_included
    @test !result.origin_admissible
    @test !result.promotion_eligible
    @test isempty(result.failures)

    @test length(result.forecast_cells) == 12_452
    @test length(result.model_origin_diagnostics) == 671
    @test length(result.summaries) == 440
    @test length(result.relative_scores) == 440
    @test length(result.weighted_relative_scores) == 22
    @test Set(getfield.(result.forecast_cells, :target_id)) ==
        Set(result.target_ids)
    @test all(isfinite, getfield.(result.forecast_cells, :point_forecast))
    @test all(isfinite, getfield.(result.forecast_cells, :actual))

    semi_cells = filter(
        row -> row.model_id == semi_id,
        result.forecast_cells,
    )
    @test length(semi_cells) == 1_132
    @test Set(getfield.(semi_cells, :target_id)) == Set(result.target_ids)
    @test Set(getfield.(semi_cells, :horizon)) == Set(BASE.HORIZONS)

    semi_diagnostics = filter(
        row -> row.model_id == semi_id,
        result.model_origin_diagnostics,
    )
    @test length(semi_diagnostics) == 61
    @test all(row -> row.run_status == "OK", semi_diagnostics)
    @test all(
        row ->
        row.diagnostic_class ==
            "semi_structural_exact_kalman_fixed_parameters",
        semi_diagnostics,
    )
    @test all(
        row -> row.stable_within_unit_circle == "true",
        semi_diagnostics,
    )
    @test all(
        row -> 0.0 <= row.companion_spectral_radius < 1.0,
        semi_diagnostics,
    )

    @test M.track_observation_counts(result, M.ALL_AVAILABLE_TRACK) ==
        [61, 60, 58, 54, 50]
    @test M.track_observation_counts(result, M.BALANCED_H12_TRACK) ==
        fill(50, 5)
    @test all(
        row ->
        row.status == "COMPLETE_MATCHED" &&
            row.target_horizon_cell_count == 20 &&
            row.expected_target_horizon_cell_count == 20 &&
            row.failure_free,
        result.weighted_relative_scores,
    )

    semi_all = M.semi_weighted_score(result, M.ALL_AVAILABLE_TRACK)
    semi_balanced = M.semi_weighted_score(result, M.BALANCED_H12_TRACK)
    @test semi_all.weighted_macro_average_cellwise_rmse_ratio ≈
        0.7488895447345775 rtol = 1.0e-12
    @test semi_all.weighted_macro_average_cellwise_mae_ratio ≈
        0.8856658629411573 rtol = 1.0e-12
    @test semi_balanced.weighted_macro_average_cellwise_rmse_ratio ≈
        0.7445969022111804 rtol = 1.0e-12
    @test semi_balanced.weighted_macro_average_cellwise_mae_ratio ≈
        0.8730449475542831 rtol = 1.0e-12

    for track in (M.ALL_AVAILABLE_TRACK, M.BALANCED_H12_TRACK)
        ranked = sort(
            filter(
                row -> row.sample_track == track,
                result.weighted_relative_scores,
            );
            by = row -> row.weighted_macro_average_cellwise_rmse_ratio,
        )
        @test first(ranked).model_id == semi_id
        @test ranked[2].model_id == BENCH.model_id(
            BENCH.ARSpec(candidate_lags = [1]),
        )
    end
end

@testset "comparison is deterministic and manifest fails no gate open" begin
    first_result = run_revised_semi_structural_comparison(canonical_panel())
    second_result = run_revised_semi_structural_comparison(canonical_panel())
    @test first_result.forecast_cells == second_result.forecast_cells
    @test first_result.failures == second_result.failures
    @test first_result.model_origin_diagnostics ==
        second_result.model_origin_diagnostics
    @test first_result.summaries == second_result.summaries
    @test first_result.relative_scores == second_result.relative_scores
    @test first_result.weighted_relative_scores ==
        second_result.weighted_relative_scores

    mktempdir() do first_directory
        mktempdir() do second_directory
            first_written = write_revised_semi_structural_comparison(
                first_result,
                first_directory,
            )
            second_written = write_revised_semi_structural_comparison(
                second_result,
                second_directory,
            )
            @test first_written.hashes == second_written.hashes
            @test Set(keys(first_written.paths)) == Set(
                [
                    "forecast_cells",
                    "failures",
                    "model_origin_diagnostics",
                    "score_summaries",
                    "relative_scores",
                    "weighted_relative_scores",
                ],
            )
            manifest = TOML.parsefile(first_written.manifest_path)
            @test manifest["comparison_target_count"] == 4
            @test manifest["model_count"] == 11
            @test manifest["semi_structural_benchmark_included"]
            @test manifest["equilibrium_oriented_comparator_included"]
            @test manifest["semi_structural_not_dsge"]
            @test !manifest["dsge_benchmark_included"]
            @test !manifest["abm_forecast_included"]
            @test manifest[
                "semi_structural_density_capability_includes_fixed_parameter_state_uncertainty",
            ]
            @test !manifest["predictive_draws_scored"]
            @test manifest["point_forecast_only"]
            @test !manifest["forecast_origin_admissible"]
            @test !manifest["promotion_eligible"]
            @test !manifest["production_accuracy_score"]
            @test !manifest["identical_estimation_target_panels"]
            @test manifest["identical_origin_cutoffs"]
            @test manifest["identical_realized_score_cells"]
            @test manifest["native_input_panel_comparison"]
            @test !manifest[
                "registry_empirical_forecast_execution_allowed",
            ]
            @test manifest["diagnostic_execution_is_quarantined"]
            @test manifest["failure_free"]
            @test manifest["forecast_cell_count"] == 12_452
            @test manifest["equilibrium_benchmark_status"] ==
                "SEMI_STRUCTURAL_EQUILIBRIUM_ORIENTED_SCORED_NOT_DSGE"
            @test manifest["dsge_benchmark_status"] ==
                "MISSING_NOT_SCORED"
            @test manifest["abm_benchmark_status"] ==
                "MISSING_NOT_SCORED"
            @test manifest["benchmark_registry_content_sha256"] ==
                M.CANONICAL_REGISTRY_CONTENT_SHA256
            @test manifest["benchmark_registry_module_sha256"] ==
                M.sha256_hex(read(M.BENCHMARK_REGISTRY_MODULE_PATH))
            @test manifest["benchmark_module_sha256"] ==
                M.sha256_hex(read(BASE.BENCHMARK_MODULE_PATH))
            @test manifest["bvar_module_sha256"] ==
                M.sha256_hex(read(BASE.BVAR_MODULE_PATH))
            @test manifest["var_utility_sha256"] ==
                M.sha256_hex(read(BASE.VAR_UTILITY_PATH))
            @test manifest["protocol_sha256"] ==
                M.sha256_hex(read(BASE.PROTOCOL_PATH))
            @test manifest["julia_project_sha256"] ==
                M.sha256_hex(read(BASE.PROJECT_PATH))
            @test manifest["julia_manifest_sha256"] ==
                M.sha256_hex(read(BASE.JULIA_MANIFEST_PATH))
        end
    end
end

@testset "registry and model limitations are independently enforced" begin
    base_ids = BENCH.model_id.(BASE.default_model_specs())
    semi_spec = BENCH.SemiStructuralSpec()
    semi_id = BENCH.model_id(semi_spec)
    registry = M.validate_model_registry(base_ids, semi_id)
    entry = M.REGISTRY.model_entry(registry, semi_id)
    @test entry["target_panel_id"] == M.SEMI_STRUCTURAL_TARGET_PANEL_ID
    @test entry["family"] == "compact_semi_structural"
    @test !entry["specification"]["parameters"]["dsge_model"]
    @test !entry["specification"]["parameters"][
        "origin_parameter_fitting",
    ]

    card = BENCH.model_card(semi_spec)
    @test !card["satisfies_dsge_requirement"]
    @test !card["full_posterior_parameter_density"]
    @test occursin("not a DSGE", card["known_limitations"])
end
