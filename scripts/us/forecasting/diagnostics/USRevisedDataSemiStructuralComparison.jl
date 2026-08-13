module USRevisedDataSemiStructuralComparison

using LinearAlgebra
using SHA
using TOML

if !isdefined(@__MODULE__, :USRevisedDataBenchmarkDiagnostic)
    include("USRevisedDataBenchmarkDiagnostic.jl")
end
using .USRevisedDataBenchmarkDiagnostic

if !isdefined(@__MODULE__, :USBenchmarkModelRegistry)
    include(
        joinpath(
            @__DIR__,
            "..",
            "benchmarks",
            "USBenchmarkModelRegistry.jl",
        ),
    )
end
using .USBenchmarkModelRegistry

const BASE = USRevisedDataBenchmarkDiagnostic
const BENCH = USRevisedDataBenchmarkDiagnostic.USForecastBenchmarks
const REGISTRY = USBenchmarkModelRegistry

export RevisedSemiStructuralComparisonResult,
    run_revised_semi_structural_comparison,
    write_revised_semi_structural_comparison

const CONTRACT_ID =
    "beforeit-us-revised-data-semi-structural-comparison.v1"
const CORE4_TARGET_IDS = [
    "real_gdp",
    "pce_price_index",
    "unemployment_rate",
    "effective_federal_funds_rate",
]
const CORE4_MODEL_TARGET_NAMES =
    collect(BENCH.SEMI_STRUCTURAL_TARGET_NAMES)
const CORE4_TARGET_WEIGHTS =
    Dict(target => 1.0 / length(CORE4_TARGET_IDS) for target in CORE4_TARGET_IDS)
const ALL_AVAILABLE_TRACK =
    "core4_all_available_common_cells_native_model_inputs"
const BALANCED_H12_TRACK =
    "core4_balanced_h12_common_cells_native_model_inputs"
const TRACKS = (ALL_AVAILABLE_TRACK, BALANCED_H12_TRACK)
const SEMI_STRUCTURAL_TARGET_PANEL_ID = "quarterly_core4_contract_v1"
const STATISTICAL_TARGET_PANEL_ID =
    "tier1_quarterly_primary_transformations_v1"
const CANONICAL_REGISTRY_CONTENT_SHA256 =
    "a6268e19fe217430eb3b9cbd267295e921a8da25d3c8291b53a5deca9b1d22ed"
const BENCHMARK_DIRECTORY =
    normpath(joinpath(@__DIR__, "..", "benchmarks"))
const SEMI_STRUCTURAL_SOURCE_PATH =
    joinpath(BENCHMARK_DIRECTORY, "semi_structural.jl")
const SEMI_STRUCTURAL_CARD_PATH =
    joinpath(BENCHMARK_DIRECTORY, "SEMI_STRUCTURAL_MODEL_CARD.md")
const BENCHMARK_REGISTRY_PATH =
    joinpath(BENCHMARK_DIRECTORY, "benchmark_model_registry.toml")
const BENCHMARK_REGISTRY_MODULE_PATH =
    joinpath(BENCHMARK_DIRECTORY, "USBenchmarkModelRegistry.jl")
const BASE_DIAGNOSTIC_PATH =
    joinpath(@__DIR__, "USRevisedDataBenchmarkDiagnostic.jl")

struct RevisedSemiStructuralComparisonResult
    contract_id::String
    panel_sha256::String
    panel_manifest_sha256::String
    panel_source_receipts_sha256::String
    information_track::String
    periods::Vector{String}
    target_ids::Vector{String}
    model_target_names::Vector{String}
    model_ids::Vector{String}
    horizons::Vector{Int}
    forecast_cells::Vector{ForecastCell}
    failures::Vector{DiagnosticFailure}
    model_origin_diagnostics::Vector{ModelOriginDiagnostic}
    summaries::Vector{ScoreSummary}
    relative_scores::Vector{RelativeScore}
    weighted_relative_scores::Vector{WeightedRelativeScore}
    benchmark_model_id::String
    semi_structural_model_id::String
    semi_structural_benchmark_included::Bool
    equilibrium_oriented_comparator_included::Bool
    dsge_benchmark_included::Bool
    abm_forecast_included::Bool
    origin_admissible::Bool
    promotion_eligible::Bool
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function core4_column_indices(panel::QuarterlyPanel)
    indices = Int[]
    for target in CORE4_TARGET_IDS
        matches = findall(==(target), panel.target_names)
        length(matches) == 1 ||
            throw(
            ArgumentError(
                "revised panel must contain core target $target exactly once",
            ),
        )
        push!(indices, only(matches))
    end
    return indices
end

function validate_model_registry(base_model_ids, semi_structural_model_id)
    registry = REGISTRY.load_model_registry(BENCHMARK_REGISTRY_PATH)
    REGISTRY.registry_content_sha256(registry) ==
        CANONICAL_REGISTRY_CONTENT_SHA256 ||
        throw(ArgumentError("benchmark registry semantic identity changed"))
    execution_scope = registry["execution_scope"]
    get(execution_scope, "empirical_forecast_execution_allowed", nothing) ===
        false ||
        throw(
        ArgumentError(
            "benchmark registry empirical-execution boundary changed",
        ),
    )

    for model in base_model_ids
        entry = REGISTRY.model_entry(registry, model)
        entry["support_status"] == "supported" ||
            throw(ArgumentError("statistical model $model is not supported"))
        entry["target_panel_id"] == STATISTICAL_TARGET_PANEL_ID ||
            throw(
            ArgumentError(
                "statistical model $model target-panel identity changed",
            ),
        )
    end

    semi_entry = REGISTRY.model_entry(registry, semi_structural_model_id)
    semi_entry["support_status"] == "supported" ||
        throw(ArgumentError("semi-structural model is not supported"))
    semi_entry["family"] == "compact_semi_structural" ||
        throw(ArgumentError("semi-structural model family changed"))
    semi_entry["target_panel_id"] == SEMI_STRUCTURAL_TARGET_PANEL_ID ||
        throw(ArgumentError("semi-structural target-panel identity changed"))
    parameters = semi_entry["specification"]["parameters"]
    get(parameters, "model_class", nothing) == "semi_structural_not_dsge" ||
        throw(ArgumentError("semi-structural model-class boundary changed"))
    get(parameters, "dsge_model", nothing) === false ||
        throw(ArgumentError("semi-structural DSGE boundary changed"))
    get(parameters, "origin_parameter_fitting", nothing) === false ||
        throw(
        ArgumentError(
            "semi-structural origin-parameter-fitting boundary changed",
        ),
    )
    return registry
end

function semi_structural_diagnostic(
        spec,
        run,
        training,
        origin_index,
        origin_period,
        forecast_horizon,
    )
    record_sha256 = BASE.model_record_sha256(spec)
    if run.status != :ok
        return ModelOriginDiagnostic(
            run.model_id,
            origin_index,
            origin_period,
            size(training, 1),
            forecast_horizon,
            "FAILED",
            "failed_run",
            record_sha256,
            "not_applicable",
            "not_applicable",
            "not_applicable",
            "not_available",
            -1,
            -1,
            -1,
            NaN,
            NaN,
            "not_available",
            NaN,
            "structured_benchmark_failure",
        )
    end

    forecast = something(run.forecast)
    diagnostics = forecast.diagnostics
    get(diagnostics, "dsge_model", nothing) === false ||
        throw(ArgumentError("semi-structural forecast claimed DSGE status"))
    get(diagnostics, "full_posterior_parameter_density", nothing) === false ||
        throw(
        ArgumentError(
            "semi-structural forecast claimed a full parameter posterior",
        ),
    )
    get(diagnostics, "origin_parameter_fitting", nothing) === false ||
        throw(
        ArgumentError(
            "semi-structural forecast claimed origin parameter fitting",
        ),
    )
    get(diagnostics, "target_names", nothing) == CORE4_MODEL_TARGET_NAMES ||
        throw(ArgumentError("semi-structural forecast target contract changed"))
    get(diagnostics, "n_draws", nothing) == 0 ||
        throw(ArgumentError("point-only comparison unexpectedly consumed draws"))
    spectral_radius =
        Float64(diagnostics["transition_spectral_radius"])
    spectral_radius < 1.0 ||
        throw(ArgumentError("semi-structural transition is not stable"))

    return ModelOriginDiagnostic(
        run.model_id,
        origin_index,
        origin_period,
        size(training, 1),
        forecast_horizon,
        "OK",
        "semi_structural_exact_kalman_fixed_parameters",
        record_sha256,
        "not_applicable",
        "not_applicable",
        "not_applicable",
        "not_applicable",
        -1,
        -1,
        -1,
        NaN,
        spectral_radius,
        "true",
        maximum(abs, forecast.point),
        "benchmark_api",
    )
end

function collect_semi_structural_origin!(
        forecast_cells,
        failures,
        diagnostics,
        panel,
        column_indices,
        spec,
        origin_index,
    )
    available_horizon =
        min(BASE.MAXIMUM_HORIZON, length(panel.periods) - origin_index)
    available_horizon >= 1 ||
        throw(ArgumentError("origin has no realized future target"))
    training = panel.values[1:origin_index, column_indices]
    scales = BASE.mase_scales(training)
    sample = BENCH.OriginData(
        origin_id = "revised-semi-structural-$(panel.periods[origin_index])",
        origin_key = panel.periods[origin_index],
        training_keys = panel.periods[1:origin_index],
        forecast_keys = panel.periods[
            (origin_index + 1):(origin_index + available_horizon),
        ],
        y_train = training,
        target_names = CORE4_MODEL_TARGET_NAMES,
    )
    run = BENCH.run_benchmark(spec, sample; n_draws = 0, seed = 0)
    push!(
        diagnostics,
        semi_structural_diagnostic(
            spec,
            run,
            training,
            origin_index,
            panel.periods[origin_index],
            available_horizon,
        ),
    )
    if run.status != :ok
        failure = something(run.failure)
        push!(
            failures,
            DiagnosticFailure(
                run.model_id,
                origin_index,
                panel.periods[origin_index],
                available_horizon,
                String(failure.code),
                failure.exception_type,
                failure.message,
            ),
        )
        return nothing
    end

    forecast = something(run.forecast)
    for horizon in BASE.HORIZONS
        horizon <= available_horizon || continue
        target_index = origin_index + horizon
        for (core_column, target_id) in enumerate(CORE4_TARGET_IDS)
            panel_column = column_indices[core_column]
            point = forecast.point[horizon, core_column]
            actual = panel.values[target_index, panel_column]
            error = point - actual
            push!(
                forecast_cells,
                ForecastCell(
                    run.model_id,
                    origin_index,
                    panel.periods[origin_index],
                    panel.periods[target_index],
                    target_id,
                    horizon,
                    point,
                    actual,
                    error,
                    abs(error),
                    error^2,
                    scales[core_column],
                    abs(error) / scales[core_column],
                ),
            )
        end
    end
    return nothing
end

function comparison_relative_scores(
        summaries,
        model_ids,
        benchmark_model_id,
    )
    by_key = Dict(
        (
                row.sample_track,
                row.model_id,
                row.target_id,
                row.horizon,
            ) => row for row in summaries
    )
    relative = RelativeScore[]
    for track in TRACKS
        for model in model_ids
            for target in CORE4_TARGET_IDS
                for horizon in BASE.HORIZONS
                    key = (track, model, target, horizon)
                    benchmark_key =
                        (track, benchmark_model_id, target, horizon)
                    haskey(by_key, key) && haskey(by_key, benchmark_key) ||
                        continue
                    row = by_key[key]
                    benchmark = by_key[benchmark_key]
                    row.observation_count == benchmark.observation_count ||
                        throw(
                        ArgumentError(
                            "semi-structural comparison samples are not matched",
                        ),
                    )
                    benchmark.rmse > 0.0 ||
                        throw(ArgumentError("benchmark RMSE must be positive"))
                    benchmark.mae > 0.0 ||
                        throw(ArgumentError("benchmark MAE must be positive"))
                    rmse_ratio = row.rmse / benchmark.rmse
                    push!(
                        relative,
                        RelativeScore(
                            track,
                            model,
                            benchmark_model_id,
                            target,
                            horizon,
                            row.observation_count,
                            rmse_ratio,
                            row.mae / benchmark.mae,
                            100.0 * (1.0 - rmse_ratio),
                        ),
                    )
                end
            end
        end
    end
    return relative
end

function comparison_weighted_scores(
        relative,
        model_ids,
        benchmark_model_id,
        failures,
    )
    expected_cells = length(CORE4_TARGET_IDS) * length(BASE.HORIZONS)
    all_model_failure_count = length(failures)
    output = WeightedRelativeScore[]
    for track in TRACKS
        for model in model_ids
            selected = filter(
                row ->
                row.sample_track == track &&
                    row.model_id == model,
                relative,
            )
            selected_cells =
                Set((row.target_id, row.horizon) for row in selected)
            complete =
                length(selected) == expected_cells &&
                length(selected_cells) == expected_cells
            total_weight = sum(
                CORE4_TARGET_WEIGHTS[row.target_id] *
                    BASE.HORIZON_WEIGHTS[row.horizon] for row in selected;
                init = 0.0,
            )
            observation_counts = getfield.(selected, :observation_count)
            minimum_count =
                isempty(observation_counts) ? -1 : minimum(observation_counts)
            maximum_count =
                isempty(observation_counts) ? -1 : maximum(observation_counts)
            model_failure_count =
                count(failure -> failure.model_id == model, failures)
            failure_free = all_model_failure_count == 0
            if complete && total_weight ≈ 1.0 && failure_free
                weighted_rmse = sum(
                    CORE4_TARGET_WEIGHTS[row.target_id] *
                        BASE.HORIZON_WEIGHTS[row.horizon] *
                        row.rmse_ratio for row in selected;
                    init = 0.0,
                )
                weighted_mae = sum(
                    CORE4_TARGET_WEIGHTS[row.target_id] *
                        BASE.HORIZON_WEIGHTS[row.horizon] *
                        row.mae_ratio for row in selected;
                    init = 0.0,
                )
                status = "COMPLETE_MATCHED"
            else
                weighted_rmse = NaN
                weighted_mae = NaN
                status = if complete && total_weight ≈ 1.0
                    "MATCHED_GRID_WITH_MODEL_FAILURES_NOT_RANKED"
                else
                    "INCOMPLETE_MATCHED_GRID_NOT_RANKED"
                end
            end
            push!(
                output,
                WeightedRelativeScore(
                    track,
                    model,
                    benchmark_model_id,
                    status,
                    length(selected),
                    expected_cells,
                    minimum_count,
                    maximum_count,
                    model_failure_count,
                    all_model_failure_count,
                    failure_free,
                    weighted_rmse,
                    weighted_mae,
                ),
            )
        end
    end
    return output
end

"""
    run_revised_semi_structural_comparison(panel)

Run the canonical ten-model statistical diagnostic and the registered
fixed-parameter semi-structural model at the same expanding-window cutoffs.
Statistical models retain their registered eight-target estimation panel; the
semi-structural model retains its registered core-four panel. Scores use only
the four target/horizon/origin cells common to all eleven models.

This is a revised/mixed-vintage research diagnostic. It is not a DSGE, ABM,
strict forecast origin, production score, or model-promotion artifact.
"""
function run_revised_semi_structural_comparison(panel::QuarterlyPanel)
    BASE.validate_panel(panel)
    base_result = BASE.run_revised_benchmark_diagnostic(panel)
    semi_spec = BENCH.SemiStructuralSpec()
    semi_id = BENCH.model_id(semi_spec)
    registry = validate_model_registry(base_result.model_ids, semi_id)
    REGISTRY.model_manifest_sha256(registry, semi_id)

    column_indices = core4_column_indices(panel)
    forecast_cells = filter(
        row -> row.target_id in CORE4_TARGET_IDS,
        base_result.forecast_cells,
    )
    failures = copy(base_result.failures)
    diagnostics = copy(base_result.model_origin_diagnostics)
    for origin_index in
        BASE.MINIMUM_TRAINING_QUARTERS:(length(panel.periods) - 1)
        collect_semi_structural_origin!(
            forecast_cells,
            failures,
            diagnostics,
            panel,
            column_indices,
            semi_spec,
            origin_index,
        )
    end

    model_ids = [base_result.model_ids; semi_id]
    common_keys = BASE.common_cell_keys(forecast_cells, model_ids)
    common_rows =
        filter(row -> BASE.cell_key(row) in common_keys, forecast_cells)
    balanced_last_origin = length(panel.periods) - BASE.MAXIMUM_HORIZON
    balanced_rows = filter(
        row -> row.origin_index <= balanced_last_origin,
        common_rows,
    )
    summaries = vcat(
        BASE.summarize_rows(
            ALL_AVAILABLE_TRACK,
            common_rows,
            model_ids,
            CORE4_TARGET_IDS,
        ),
        BASE.summarize_rows(
            BALANCED_H12_TRACK,
            balanced_rows,
            model_ids,
            CORE4_TARGET_IDS,
        ),
    )
    relative = comparison_relative_scores(
        summaries,
        model_ids,
        base_result.benchmark_model_id,
    )
    weighted = comparison_weighted_scores(
        relative,
        model_ids,
        base_result.benchmark_model_id,
        failures,
    )

    return RevisedSemiStructuralComparisonResult(
        CONTRACT_ID,
        panel.panel_sha256,
        panel.manifest_sha256,
        panel.source_receipts_sha256,
        panel.information_track,
        copy(panel.periods),
        copy(CORE4_TARGET_IDS),
        copy(CORE4_MODEL_TARGET_NAMES),
        model_ids,
        copy(BASE.HORIZONS),
        forecast_cells,
        failures,
        diagnostics,
        summaries,
        relative,
        weighted,
        base_result.benchmark_model_id,
        semi_id,
        true,
        true,
        false,
        false,
        false,
        false,
    )
end

toml_string(value) = repr(String(value))
toml_string_array(values) =
    "[" * join(toml_string.(values), ", ") * "]"

function track_observation_counts(result, track)
    counts = Int[]
    for horizon in result.horizons
        selected = filter(
            row ->
            row.sample_track == track &&
                row.target_id == first(result.target_ids) &&
                row.horizon == horizon,
            result.summaries,
        )
        observed = unique(getfield.(selected, :observation_count))
        length(observed) == 1 ||
            throw(ArgumentError("track observation counts are not common"))
        push!(counts, only(observed))
    end
    return counts
end

function semi_weighted_score(result, track)
    matches = filter(
        row ->
        row.sample_track == track &&
            row.model_id == result.semi_structural_model_id,
        result.weighted_relative_scores,
    )
    length(matches) == 1 ||
        throw(ArgumentError("semi-structural weighted score is not unique"))
    only(matches).status == "COMPLETE_MATCHED" ||
        throw(ArgumentError("semi-structural weighted score is incomplete"))
    return only(matches)
end

function write_manifest(path, result, output_hashes)
    base_specs = BASE.default_model_specs()
    semi_spec = BENCH.SemiStructuralSpec()
    specs = [base_specs; semi_spec]
    registry = validate_model_registry(
        BENCH.model_id.(base_specs),
        result.semi_structural_model_id,
    )
    semi_entry_manifest_sha256 =
        REGISTRY.model_manifest_sha256(
        registry,
        result.semi_structural_model_id,
    )
    model_record_sha256s = BASE.model_record_sha256.(specs)
    model_set_sha256 =
        BASE.ordered_string_list_sha256(BASE.canonical_model_record.(specs))
    model_id_set_sha256 = BASE.ordered_string_list_sha256(result.model_ids)
    all_available_counts =
        track_observation_counts(result, ALL_AVAILABLE_TRACK)
    balanced_counts = track_observation_counts(result, BALANCED_H12_TRACK)
    semi_all = semi_weighted_score(result, ALL_AVAILABLE_TRACK)
    semi_balanced = semi_weighted_score(result, BALANCED_H12_TRACK)
    lines = [
        "schema_version = \"beforeit-us-revised-data-semi-structural-comparison-result.v1\"",
        "contract_id = \"$(result.contract_id)\"",
        "information_track = \"$(result.information_track)\"",
        "panel_sha256 = \"$(result.panel_sha256)\"",
        "panel_manifest_sha256 = \"$(result.panel_manifest_sha256)\"",
        "panel_source_receipts_sha256 = \"$(result.panel_source_receipts_sha256)\"",
        "start_period = \"$(first(result.periods))\"",
        "end_period = \"$(last(result.periods))\"",
        "comparison_target_count = $(length(result.target_ids))",
        "comparison_target_ids = $(toml_string_array(result.target_ids))",
        "semi_structural_model_target_names = $(toml_string_array(result.model_target_names))",
        "model_count = $(length(result.model_ids))",
        "model_ids = $(toml_string_array(result.model_ids))",
        "model_id_set_canonicalization = \"ordered_utf8_lines_lf\"",
        "model_id_set_sha256 = \"$model_id_set_sha256\"",
        "model_record_canonicalization = \"$(BASE.MODEL_RECORD_CANONICALIZATION)\"",
        "model_record_sha256s = $(toml_string_array(model_record_sha256s))",
        "model_set_sha256 = \"$model_set_sha256\"",
        "benchmark_registry_file_sha256 = \"$(sha256_hex(read(BENCHMARK_REGISTRY_PATH)))\"",
        "benchmark_registry_content_sha256 = \"$(REGISTRY.registry_content_sha256(registry))\"",
        "benchmark_registry_module_sha256 = \"$(sha256_hex(read(BENCHMARK_REGISTRY_MODULE_PATH)))\"",
        "registry_empirical_forecast_execution_allowed = false",
        "diagnostic_execution_is_quarantined = true",
        "semi_structural_model_id = \"$(result.semi_structural_model_id)\"",
        "semi_structural_model_manifest_sha256 = \"$semi_entry_manifest_sha256\"",
        "semi_structural_benchmark_included = true",
        "equilibrium_oriented_comparator_included = true",
        "semi_structural_not_dsge = true",
        "dsge_benchmark_included = false",
        "abm_forecast_included = false",
        "semi_structural_origin_parameter_fitting = false",
        "semi_structural_parameter_uncertainty_included = false",
        "semi_structural_density_capability_includes_fixed_parameter_state_uncertainty = true",
        "predictive_draws_scored = false",
        "point_forecast_only = true",
        "statistical_model_estimation_panel = \"$STATISTICAL_TARGET_PANEL_ID\"",
        "semi_structural_estimation_panel = \"$SEMI_STRUCTURAL_TARGET_PANEL_ID\"",
        "comparison_score_panel = \"$SEMI_STRUCTURAL_TARGET_PANEL_ID\"",
        "identical_origin_cutoffs = true",
        "identical_realized_score_cells = true",
        "identical_estimation_target_panels = false",
        "native_input_panel_comparison = true",
        "forecast_cell_count = $(length(result.forecast_cells))",
        "failure_count = $(length(result.failures))",
        "failure_free = $(isempty(result.failures))",
        "model_origin_diagnostic_count = $(length(result.model_origin_diagnostics))",
        "score_summary_count = $(length(result.summaries))",
        "relative_score_count = $(length(result.relative_scores))",
        "weighted_relative_score_count = $(length(result.weighted_relative_scores))",
        "benchmark_model_id = \"$(result.benchmark_model_id)\"",
        "horizons = [$(join(result.horizons, ", "))]",
        "horizon_weights = [$(join((BASE.HORIZON_WEIGHTS[horizon] for horizon in result.horizons), ", "))]",
        "comparison_target_weights = [$(join((CORE4_TARGET_WEIGHTS[target] for target in result.target_ids), ", "))]",
        "all_available_track = \"$ALL_AVAILABLE_TRACK\"",
        "balanced_h12_track = \"$BALANCED_H12_TRACK\"",
        "all_available_common_observation_counts = [$(join(all_available_counts, ", "))]",
        "balanced_h12_common_observation_counts = [$(join(balanced_counts, ", "))]",
        "semi_structural_all_available_weighted_rmse_ratio = $(repr(semi_all.weighted_macro_average_cellwise_rmse_ratio))",
        "semi_structural_all_available_weighted_mae_ratio = $(repr(semi_all.weighted_macro_average_cellwise_mae_ratio))",
        "semi_structural_balanced_h12_weighted_rmse_ratio = $(repr(semi_balanced.weighted_macro_average_cellwise_rmse_ratio))",
        "semi_structural_balanced_h12_weighted_mae_ratio = $(repr(semi_balanced.weighted_macro_average_cellwise_mae_ratio))",
        "minimum_training_quarters = $(BASE.MINIMUM_TRAINING_QUARTERS)",
        "forecast_origin_admissible = false",
        "promotion_eligible = false",
        "production_accuracy_score = false",
        "paper_parity_claimed = false",
        "truth_vintage = \"revised_mixed_vintage_snapshot\"",
        "error_sign = \"$(BASE.ERROR_SIGN)\"",
        "sample_policy = \"common core-four target-horizon-origin score cells across eleven native-input models; all-available and balanced-h12 reported separately\"",
        "known_comparability_limit = \"statistical models use the registered eight-target panel while the semi-structural model uses its registered core-four panel\"",
        "pandemic_policy = \"pandemic retained in headline full sample; regime slices pending\"",
        "equilibrium_benchmark_status = \"SEMI_STRUCTURAL_EQUILIBRIUM_ORIENTED_SCORED_NOT_DSGE\"",
        "dsge_benchmark_status = \"MISSING_NOT_SCORED\"",
        "abm_benchmark_status = \"MISSING_NOT_SCORED\"",
        "comparison_code_sha256 = \"$(sha256_hex(read(abspath(@__FILE__))))\"",
        "base_diagnostic_code_sha256 = \"$(sha256_hex(read(BASE_DIAGNOSTIC_PATH)))\"",
        "benchmark_module_sha256 = \"$(sha256_hex(read(BASE.BENCHMARK_MODULE_PATH)))\"",
        "bvar_module_sha256 = \"$(sha256_hex(read(BASE.BVAR_MODULE_PATH)))\"",
        "var_utility_sha256 = \"$(sha256_hex(read(BASE.VAR_UTILITY_PATH)))\"",
        "protocol_sha256 = \"$(sha256_hex(read(BASE.PROTOCOL_PATH)))\"",
        "semi_structural_source_sha256 = \"$(sha256_hex(read(SEMI_STRUCTURAL_SOURCE_PATH)))\"",
        "semi_structural_model_card_sha256 = \"$(sha256_hex(read(SEMI_STRUCTURAL_CARD_PATH)))\"",
        "julia_project_sha256 = \"$(sha256_hex(read(BASE.PROJECT_PATH)))\"",
        "julia_manifest_sha256 = \"$(sha256_hex(read(BASE.JULIA_MANIFEST_PATH)))\"",
        "julia_version = \"$(VERSION)\"",
        "blas_vendor = \"$(BLAS.vendor())\"",
        "blas_threads = $(BLAS.get_num_threads())",
        "deterministic_execution_policy = \"Float64 point forecasts only; zero predictive draws; expanding windows; no stochastic RNG consumed\"",
    ]
    for (key, value) in sort!(collect(output_hashes); by = first)
        push!(lines, "$(key)_sha256 = \"$value\"")
    end
    write(path, join(lines, "\n") * "\n")
    return path
end

"""
    write_revised_semi_structural_comparison(result, output_directory)

Write the quarantined core-four comparison tables. The output is outside the
production registry and cannot mutate source, origin, or promotion state.
"""
function write_revised_semi_structural_comparison(
        result::RevisedSemiStructuralComparisonResult,
        output_directory::AbstractString,
    )
    mkpath(output_directory)
    paths = Dict(
        "forecast_cells" => joinpath(output_directory, "forecast_cells.csv"),
        "failures" => joinpath(output_directory, "failures.csv"),
        "model_origin_diagnostics" =>
            joinpath(output_directory, "model_origin_diagnostics.csv"),
        "score_summaries" =>
            joinpath(output_directory, "score_summaries.csv"),
        "relative_scores" =>
            joinpath(output_directory, "relative_scores.csv"),
        "weighted_relative_scores" =>
            joinpath(output_directory, "weighted_relative_scores.csv"),
    )
    BASE.write_struct_csv(
        paths["forecast_cells"],
        result.forecast_cells,
        ForecastCell,
    )
    BASE.write_struct_csv(paths["failures"], result.failures, DiagnosticFailure)
    BASE.write_struct_csv(
        paths["model_origin_diagnostics"],
        result.model_origin_diagnostics,
        ModelOriginDiagnostic,
    )
    BASE.write_struct_csv(
        paths["score_summaries"],
        result.summaries,
        ScoreSummary,
    )
    BASE.write_struct_csv(
        paths["relative_scores"],
        result.relative_scores,
        RelativeScore,
    )
    BASE.write_struct_csv(
        paths["weighted_relative_scores"],
        result.weighted_relative_scores,
        WeightedRelativeScore,
    )
    hashes = Dict(
        name => sha256_hex(read(path)) for (name, path) in paths
    )
    manifest_path = joinpath(output_directory, "manifest.toml")
    write_manifest(manifest_path, result, hashes)
    hashes["manifest"] = sha256_hex(read(manifest_path))
    return (; paths, manifest_path, hashes)
end

end
