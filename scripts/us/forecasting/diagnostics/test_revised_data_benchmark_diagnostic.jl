using SHA
using Random
using Statistics
using Test
using TOML

include("USRevisedDataBenchmarkDiagnostic.jl")
using .USRevisedDataBenchmarkDiagnostic

struct SameIdentifierNoChangeSpec <:
    USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.AbstractBenchmarkSpec end

USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_id(
    ::SameIdentifierNoChangeSpec,
) = "naive_no_change"
USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_card(
    ::SameIdentifierNoChangeSpec,
) = USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_card(
    USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.NoChangeSpec(),
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

const FIXTURE_DIRECTORY = joinpath(@__DIR__, "revised_data", "fixtures")
const REAL_PANEL_PATH = joinpath(FIXTURE_DIRECTORY, "quarterly_panel.csv")
const REAL_MANIFEST_PATH = joinpath(FIXTURE_DIRECTORY, "manifest.toml")
const REAL_RECEIPT_PATH =
    joinpath(FIXTURE_DIRECTORY, "source_receipts.json")
const EXPECTED_PANEL_SHA256 =
    "f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe"
const EXPECTED_PANEL_MANIFEST_SHA256 =
    "fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f"
const EXPECTED_SOURCE_RECEIPTS_SHA256 =
    "14bab08bb573265e0affc878cedbbb8d4a0f8f5510fc59990f92d614f109d488"

function quarter_period(index)
    ordinal = 4 * 2000 + index
    year = (ordinal - 1) ÷ 4
    quarter = ordinal - 4year
    return "$(year)Q$(quarter)"
end

function target_names()
    return [
        "real_gdp",
        "pce_price_index",
        "core_pce_price_index",
        "gdp_deflator",
        "unemployment_rate",
        "payroll_employment",
        "effective_federal_funds_rate",
        "nominal_gdp",
    ]
end

function synthetic_panel(observations = 56)
    periods = quarter_period.(1:observations)
    values = Matrix{Float64}(undef, observations, 8)
    rng = MersenneTwister(8_104)
    centers = [2.0, 1.8, 1.6, 2.2, 5.0, 0.4, 2.0, 4.2]
    values[1, :] .= centers .+ 0.1randn(rng, 8)
    for time in 2:observations
        common_shock = 0.08randn(rng)
        for target in 1:8
            values[time, target] =
                centers[target] +
                0.55 * (values[time - 1, target] - centers[target]) +
                common_shock +
                0.12randn(rng)
        end
    end
    return QuarterlyPanel(
        periods,
        target_names(),
        values,
        repeat("1", 64),
        repeat("2", 64),
        repeat("3", 64),
        "revised_mixed_vintage_diagnostic",
    )
end

function copy_real_fixture()
    directory = mktempdir()
    panel_path = joinpath(directory, "quarterly_panel.csv")
    manifest_path = joinpath(directory, "manifest.toml")
    receipt_path = joinpath(directory, "source_receipts.json")
    cp(REAL_PANEL_PATH, panel_path)
    cp(REAL_MANIFEST_PATH, manifest_path)
    cp(REAL_RECEIPT_PATH, receipt_path)
    return (; directory, panel_path, manifest_path, receipt_path)
end

function summary_row(result, track, model, target, horizon)
    return only(
        filter(
            row ->
            row.sample_track == track &&
                row.model_id == model &&
                row.target_id == target &&
                row.horizon == horizon,
            result.summaries,
        ),
    )
end

@testset "quarantined revised-data benchmark diagnostic" begin
    @testset "canonical real-fixture loader and receipt-chain mutations" begin
        loaded =
            load_revised_quarterly_panel(REAL_PANEL_PATH, REAL_MANIFEST_PATH)
        @test length(loaded.periods) == 101
        @test first(loaded.periods) == "2000Q3"
        @test last(loaded.periods) == "2025Q3"
        @test loaded.target_names == target_names()
        @test loaded.panel_sha256 == EXPECTED_PANEL_SHA256
        @test loaded.manifest_sha256 == EXPECTED_PANEL_MANIFEST_SHA256
        @test loaded.source_receipts_sha256 ==
            EXPECTED_SOURCE_RECEIPTS_SHA256

        fixture = copy_real_fixture()
        write(
            fixture.receipt_path,
            read(fixture.receipt_path, String) * "\n",
        )
        @test_throws ArgumentError load_revised_quarterly_panel(
            fixture.panel_path,
            fixture.manifest_path,
        )

        cp(REAL_RECEIPT_PATH, fixture.receipt_path; force = true)
        write(
            fixture.panel_path,
            read(fixture.panel_path, String) * "\n",
        )
        @test_throws ArgumentError load_revised_quarterly_panel(
            fixture.panel_path,
            fixture.manifest_path,
        )

        cp(REAL_PANEL_PATH, fixture.panel_path; force = true)
        changed_schema = replace(
            read(fixture.manifest_path, String),
            "beforeit-us-revised-data-quarterly-panel.v1" =>
                "beforeit-us-revised-data-quarterly-panel.v999",
        )
        write(fixture.manifest_path, changed_schema)
        @test_throws ArgumentError load_revised_quarterly_panel(
            fixture.panel_path,
            fixture.manifest_path,
        )

        cp(REAL_MANIFEST_PATH, fixture.manifest_path; force = true)
        rm(fixture.receipt_path)
        @test_throws ArgumentError load_revised_quarterly_panel(
            fixture.panel_path,
            fixture.manifest_path,
        )

        @test_throws ArgumentError run_revised_benchmark_diagnostic(
            synthetic_panel();
            specs = default_model_specs()[1:(end - 1)],
        )

        same_id_specs = default_model_specs()
        same_id_specs[1] = SameIdentifierNoChangeSpec()
        @test USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_id.(
            same_id_specs,
        ) ==
            USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_id.(
            default_model_specs(),
        )
        @test_throws ArgumentError run_revised_benchmark_diagnostic(
            synthetic_panel();
            specs = same_id_specs,
        )

        gap = synthetic_panel()
        gap.periods[20] = "2099Q4"
        @test_throws ArgumentError run_revised_benchmark_diagnostic(gap)
    end

    @testset "expanding-window models, diagnostics, and common samples" begin
        panel = synthetic_panel()
        result = run_revised_benchmark_diagnostic(panel)
        @test result.contract_id ==
            "beforeit-us-revised-data-benchmark-diagnostic.v2"
        @test result.information_track ==
            "revised_mixed_vintage_diagnostic"
        @test length(result.model_ids) == 10
        @test length(unique(result.model_ids)) == 10
        @test result.horizons == [1, 2, 4, 8, 12]
        @test isempty(result.failures)
        @test length(result.forecast_cells) ==
            10 * 8 * (16 + 15 + 13 + 9 + 5)
        @test length(result.model_origin_diagnostics) == 10 * 16
        @test length(result.summaries) == 10 * 8 * 5 * 2
        @test length(result.relative_scores) == 10 * 8 * 5 * 2
        @test length(result.weighted_relative_scores) == 10 * 2
        @test !result.promotion_eligible
        @test !result.origin_admissible
        @test !result.abm_forecast_included
        @test !result.equilibrium_benchmark_included

        for horizon in (1, 2, 4, 8, 12)
            expected = 17 - horizon
            row = summary_row(
                result,
                "all_available_common_models",
                result.benchmark_model_id,
                "real_gdp",
                horizon,
            )
            @test row.observation_count == expected

            balanced = summary_row(
                result,
                "balanced_h12_common_models",
                result.benchmark_model_id,
                "real_gdp",
                horizon,
            )
            @test balanced.observation_count == 5
        end

        benchmark_relative = filter(
            row -> row.model_id == result.benchmark_model_id,
            result.relative_scores,
        )
        @test all(row -> row.rmse_ratio == 1.0, benchmark_relative)
        @test all(row -> row.mae_ratio == 1.0, benchmark_relative)
        @test all(row -> row.rmse_gain_percent == 0.0, benchmark_relative)
        @test all(
            row ->
            row.status == "COMPLETE_MATCHED" &&
                row.target_horizon_cell_count == 40 &&
                row.expected_target_horizon_cell_count == 40 &&
                row.model_failure_count == 0 &&
                row.all_model_failure_count == 0 &&
                row.failure_free &&
                isfinite(
                row.weighted_macro_average_cellwise_rmse_ratio,
            ) &&
                isfinite(
                row.weighted_macro_average_cellwise_mae_ratio,
            ),
            result.weighted_relative_scores,
        )
        all_available_weighted = filter(
            row ->
            row.sample_track == "all_available_common_models",
            result.weighted_relative_scores,
        )
        @test all(
            row ->
            row.minimum_common_observation_count == 5 &&
                row.maximum_common_observation_count == 16,
            all_available_weighted,
        )
        balanced_weighted = filter(
            row ->
            row.sample_track == "balanced_h12_common_models",
            result.weighted_relative_scores,
        )
        @test all(
            row ->
            row.minimum_common_observation_count == 5 &&
                row.maximum_common_observation_count == 5,
            balanced_weighted,
        )

        ar_diagnostics = filter(
            row -> row.diagnostic_class == "univariate_ar_selected_lags",
            result.model_origin_diagnostics,
        )
        @test length(ar_diagnostics) == 3 * 16
        @test all(
            row -> length(split(row.selected_ar_lags, ";")) == 8,
            ar_diagnostics,
        )
        var_diagnostics = filter(
            row -> row.diagnostic_class == "var_design_and_companion",
            result.model_origin_diagnostics,
        )
        @test length(var_diagnostics) == 3 * 16
        @test all(row -> row.design_rank > 0, var_diagnostics)
        @test all(
            row -> isfinite(row.design_condition_number),
            var_diagnostics,
        )
        @test all(
            row -> isfinite(row.companion_spectral_radius),
            var_diagnostics,
        )
        @test all(
            row -> row.stable_within_unit_circle in ("true", "false"),
            var_diagnostics,
        )
        bvar_spec = only(
            filter(
                spec ->
                spec isa
                    USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.BVARSpec,
                default_model_specs(),
            ),
        )
        bvar_diagnostics = filter(
            row -> row.model_id ==
                USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_id(
                bvar_spec,
            ),
            result.model_origin_diagnostics,
        )
        expected_bvar_hyperparameters =
            USRevisedDataBenchmarkDiagnostic.canonical_value(
            USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_card(
                bvar_spec,
            )["hyperparameters"],
        )
        @test length(bvar_diagnostics) == 16
        @test all(
            row ->
            row.bvar_prior_family == "matrix_normal_inverse_wishart" &&
                row.bvar_prior_version == "mniw_minnesota_style_v1" &&
                row.bvar_hyperparameter_identity ==
                expected_bvar_hyperparameters &&
                row.model_record_sha256 ==
                USRevisedDataBenchmarkDiagnostic.model_record_sha256(
                bvar_spec,
            ),
            bvar_diagnostics,
        )

        fake_failure = DiagnosticFailure(
            first(result.model_ids),
            40,
            panel.periods[40],
            12,
            "synthetic_failure",
            "SyntheticFailure",
            "failure-status test",
        )
        not_ranked =
            USRevisedDataBenchmarkDiagnostic.weighted_relative_scores(
            result.relative_scores,
            result.model_ids,
            result.benchmark_model_id,
            [fake_failure],
        )
        @test all(
            row ->
            row.status ==
                "MATCHED_GRID_WITH_MODEL_FAILURES_NOT_RANKED" &&
                !row.failure_free &&
                row.all_model_failure_count == 1 &&
                isnan(
                row.weighted_macro_average_cellwise_rmse_ratio,
            ) &&
                isnan(
                row.weighted_macro_average_cellwise_mae_ratio,
            ),
            not_ranked,
        )
        @test all(
            row ->
            row.model_failure_count ==
                (row.model_id == first(result.model_ids) ? 1 : 0),
            not_ranked,
        )
    end

    @testset "deterministic output and sealed provenance manifest" begin
        result = run_revised_benchmark_diagnostic(synthetic_panel())
        first_directory = mktempdir()
        second_directory = mktempdir()
        first_output =
            write_revised_benchmark_diagnostic(result, first_directory)
        independent_result =
            run_revised_benchmark_diagnostic(synthetic_panel())
        second_output = write_revised_benchmark_diagnostic(
            independent_result,
            second_directory,
        )
        @test first_output.hashes == second_output.hashes
        @test all(
            read(first_output.paths[key]) == read(second_output.paths[key]) for
                key in keys(first_output.paths)
        )
        @test read(first_output.manifest_path) ==
            read(second_output.manifest_path)

        manifest = TOML.parsefile(first_output.manifest_path)
        @test manifest["schema_version"] ==
            "beforeit-us-revised-data-benchmark-result.v2"
        @test manifest["forecast_origin_admissible"] === false
        @test manifest["promotion_eligible"] === false
        @test manifest["abm_forecast_included"] === false
        @test manifest["equilibrium_benchmark_status"] ==
            "MISSING_NOT_SCORED"
        @test manifest["production_accuracy_score"] === false
        @test manifest["truth_vintage"] ==
            "revised_mixed_vintage_snapshot"
        @test manifest["error_sign"] == "forecast_minus_truth"
        @test manifest["mean_error_definition"] ==
            "mean(point_forecast - actual)"
        @test manifest["target_ids"] == result.target_names
        @test manifest["model_ids"] == result.model_ids
        @test manifest["canonical_model_set_enforced"] === true
        @test manifest["model_id_set_sha256"] ==
            USRevisedDataBenchmarkDiagnostic.ordered_string_list_sha256(
            result.model_ids,
        )
        @test manifest["model_set_sha256"] ==
            USRevisedDataBenchmarkDiagnostic.canonical_model_set_sha256()
        @test manifest["model_record_sha256s"] ==
            USRevisedDataBenchmarkDiagnostic.model_record_sha256.(
            default_model_specs(),
        )
        @test manifest["model_record_canonicalization"] ==
            "recursive_type_tagged_length_prefixed_spec_and_model_card.v1"
        bvar_spec = last(default_model_specs())
        bvar_card =
            USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_card(
            bvar_spec,
        )
        @test manifest["bvar_model_id"] ==
            USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks.model_id(
            bvar_spec,
        )
        @test manifest["bvar_prior_family"] ==
            "matrix_normal_inverse_wishart"
        @test manifest["bvar_prior_version"] ==
            "mniw_minnesota_style_v1"
        @test manifest["bvar_hyperparameter_selection"] == "none"
        @test manifest["bvar_hyperparameter_identity"] ==
            USRevisedDataBenchmarkDiagnostic.canonical_value(
            bvar_card["hyperparameters"],
        )
        @test manifest["horizons"] == [1, 2, 4, 8, 12]
        @test manifest["horizon_weights"] ==
            [0.3, 0.25, 0.2, 0.15, 0.1]
        @test manifest["target_weights"] == fill(0.125, 8)
        @test manifest["weighted_ratio_semantics"] ==
            "macro_average_of_matched_target_horizon_cellwise_ratios_not_ratio_of_pooled_losses"
        @test manifest["weighted_status_complete"] ==
            "COMPLETE_MATCHED"
        @test manifest["failure_free"] === true
        @test manifest["model_origin_diagnostic_count"] ==
            length(result.model_origin_diagnostics)
        @test manifest["diagnostic_code_sha256"] ==
            sha256_hex(read(joinpath(@__DIR__, "USRevisedDataBenchmarkDiagnostic.jl")))
        @test manifest["benchmark_module_sha256"] ==
            sha256_hex(
            read(
                joinpath(
                    @__DIR__,
                    "..",
                    "benchmarks",
                    "USForecastBenchmarks.jl",
                ),
            ),
        )
        @test manifest["bvar_module_sha256"] ==
            sha256_hex(
            read(joinpath(@__DIR__, "..", "benchmarks", "bvar.jl")),
        )
        @test manifest["var_utility_sha256"] ==
            sha256_hex(
            read(joinpath(@__DIR__, "..", "..", "..", "..", "src", "utils", "varx.jl")),
        )
        @test manifest["protocol_sha256"] ==
            sha256_hex(read(joinpath(@__DIR__, "..", "protocol.toml")))
        @test manifest["julia_project_sha256"] ==
            sha256_hex(
            read(joinpath(@__DIR__, "..", "..", "Project.toml")),
        )
        @test manifest["julia_manifest_sha256"] ==
            sha256_hex(
            read(joinpath(@__DIR__, "..", "..", "Manifest.toml")),
        )
        @test haskey(first_output.paths, "model_origin_diagnostics")
        @test first_output.hashes["model_origin_diagnostics"] ==
            sha256_hex(read(first_output.paths["model_origin_diagnostics"]))
    end

    @testset "real fixture integration, alignment, and exposed instability" begin
        panel =
            load_revised_quarterly_panel(REAL_PANEL_PATH, REAL_MANIFEST_PATH)
        result = run_revised_benchmark_diagnostic(panel)
        @test result.panel_sha256 == EXPECTED_PANEL_SHA256
        @test result.panel_manifest_sha256 ==
            EXPECTED_PANEL_MANIFEST_SHA256
        @test result.panel_source_receipts_sha256 ==
            EXPECTED_SOURCE_RECEIPTS_SHA256
        @test length(result.forecast_cells) == 22_640
        @test length(result.model_origin_diagnostics) == 610
        @test isempty(result.failures)
        @test length(result.summaries) == 800
        @test length(result.relative_scores) == 800
        @test length(result.weighted_relative_scores) == 20

        first_cell = only(
            filter(
                row ->
                row.model_id == "naive_no_change" &&
                    row.origin_index == 40 &&
                    row.target_id == "real_gdp" &&
                    row.horizon == 1,
                result.forecast_cells,
            ),
        )
        expected_scale =
            mean(abs.(diff(panel.values[1:40, 1]; dims = 1)))
        @test first_cell.origin_period == panel.periods[40]
        @test first_cell.target_period == panel.periods[41]
        @test first_cell.actual == panel.values[41, 1]
        @test first_cell.error ==
            first_cell.point_forecast - first_cell.actual
        @test first_cell.mase_scale ≈ expected_scale
        @test first_cell.scaled_absolute_error ≈
            first_cell.absolute_error / expected_scale
        signed_cells = filter(
            row ->
            row.model_id == "naive_no_change" &&
                row.target_id == "real_gdp" &&
                row.horizon == 1,
            result.forecast_cells,
        )
        signed_summary = summary_row(
            result,
            "all_available_common_models",
            "naive_no_change",
            "real_gdp",
            1,
        )
        expected_signed_mean =
            mean(row.point_forecast - row.actual for row in signed_cells)
        @test !iszero(expected_signed_mean)
        @test signed_summary.mean_error ≈ expected_signed_mean
        @test signed_summary.mean_error ≈
            -mean(row.actual - row.point_forecast for row in signed_cells)

        expected_counts = Dict(1 => 61, 2 => 60, 4 => 58, 8 => 54, 12 => 50)
        for (horizon, expected) in expected_counts
            all_available = summary_row(
                result,
                "all_available_common_models",
                result.benchmark_model_id,
                "real_gdp",
                horizon,
            )
            balanced = summary_row(
                result,
                "balanced_h12_common_models",
                result.benchmark_model_id,
                "real_gdp",
                horizon,
            )
            @test all_available.observation_count == expected
            @test balanced.observation_count == 50
        end

        unstable_counts = Dict(
            "beforeit_var_p1_constant" => 1,
            "beforeit_var_p2_constant" => 3,
            "beforeit_var_p3_constant" => 9,
        )
        for (model, expected) in unstable_counts
            diagnostics = filter(
                row -> row.model_id == model,
                result.model_origin_diagnostics,
            )
            @test length(diagnostics) == 61
            @test count(
                row -> row.stable_within_unit_circle == "false",
                diagnostics,
            ) == expected
        end
        @test maximum(
            row.max_abs_point_forecast for
                row in result.model_origin_diagnostics if
                row.model_id == "beforeit_var_p3_constant"
        ) > 2_000
        @test maximum(
            row.max_abs_point_forecast for
                row in result.model_origin_diagnostics if
                row.model_id == "univariate_ar_p4_constant"
        ) > 300

        output = write_revised_benchmark_diagnostic(result, mktempdir())
        manifest = TOML.parsefile(output.manifest_path)
        @test manifest["panel_sha256"] == EXPECTED_PANEL_SHA256
        @test manifest["panel_manifest_sha256"] ==
            EXPECTED_PANEL_MANIFEST_SHA256
        @test manifest["panel_source_receipts_sha256"] ==
            EXPECTED_SOURCE_RECEIPTS_SHA256
        @test manifest["forecast_cell_count"] == 22_640
        @test manifest["model_origin_diagnostic_count"] == 610
        @test manifest["failure_count"] == 0
        @test manifest["failure_free"] === true
        @test manifest["all_available_common_observation_counts"] ==
            [61, 60, 58, 54, 50]
        @test manifest["balanced_h12_common_observation_counts"] ==
            fill(50, 5)
        @test all(
            output.hashes[key] == sha256_hex(read(path)) for
                (key, path) in output.paths
        )
    end
end
