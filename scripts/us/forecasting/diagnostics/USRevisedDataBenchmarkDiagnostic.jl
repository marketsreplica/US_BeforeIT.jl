module USRevisedDataBenchmarkDiagnostic

using CSV
using LinearAlgebra
using SHA
using Statistics
using TOML

if !isdefined(@__MODULE__, :USForecastBenchmarks)
    include(
        joinpath(
            @__DIR__,
            "..",
            "benchmarks",
            "USForecastBenchmarks.jl",
        ),
    )
end
using .USForecastBenchmarks

export DiagnosticFailure,
    ForecastCell,
    ModelOriginDiagnostic,
    QuarterlyPanel,
    RelativeScore,
    RevisedBenchmarkResult,
    ScoreSummary,
    WeightedRelativeScore,
    default_model_specs,
    load_revised_quarterly_panel,
    run_revised_benchmark_diagnostic,
    write_revised_benchmark_diagnostic

const CONTRACT_ID =
    "beforeit-us-revised-data-benchmark-diagnostic.v2"
const INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
const ERROR_SIGN = "forecast_minus_truth"
const PANEL_SCHEMA_VERSION = "beforeit-us-revised-data-quarterly-panel.v1"
const PANEL_ARTIFACT_ID =
    "beforeit-us-revised-data-eight-target-panel-2026q2.v1"
const CANONICAL_PANEL_MANIFEST_SHA256 =
    "fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f"
const CANONICAL_PANEL_SHA256 =
    "f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe"
const CANONICAL_SOURCE_RECEIPTS_SHA256 =
    "14bab08bb573265e0affc878cedbbb8d4a0f8f5510fc59990f92d614f109d488"
const CANONICAL_PANEL_START = "2000Q3"
const CANONICAL_PANEL_END = "2025Q3"
const CANONICAL_PANEL_ROWS = 101
const HORIZONS = [1, 2, 4, 8, 12]
const HORIZON_WEIGHTS = Dict(1 => 0.3, 2 => 0.25, 4 => 0.2, 8 => 0.15, 12 => 0.1)
const TARGET_NAMES = [
    "real_gdp",
    "pce_price_index",
    "core_pce_price_index",
    "gdp_deflator",
    "unemployment_rate",
    "payroll_employment",
    "effective_federal_funds_rate",
    "nominal_gdp",
]
const TARGET_WEIGHTS = Dict(target => 0.125 for target in TARGET_NAMES)
const PANEL_COLUMNS = ["period"; TARGET_NAMES]
const MINIMUM_TRAINING_QUARTERS = 40
const MAXIMUM_HORIZON = 12
const COMMON_AVAILABLE_TRACK = "all_available_common_models"
const BALANCED_H12_TRACK = "balanced_h12_common_models"
const WEIGHTED_RATIO_FORMULA =
    "sum(target_weight[target] * horizon_weight[horizon] * cellwise_score_ratio[target,horizon])"
const WEIGHTED_RATIO_SEMANTICS =
    "macro_average_of_matched_target_horizon_cellwise_ratios_not_ratio_of_pooled_losses"
const MODEL_RECORD_CANONICALIZATION =
    "recursive_type_tagged_length_prefixed_spec_and_model_card.v1"
const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const US_PROJECT_ROOT =
    normpath(joinpath(@__DIR__, "..", ".."))
const BENCHMARK_MODULE_PATH = normpath(
    joinpath(@__DIR__, "..", "benchmarks", "USForecastBenchmarks.jl"),
)
const BVAR_MODULE_PATH =
    normpath(joinpath(@__DIR__, "..", "benchmarks", "bvar.jl"))
const VAR_UTILITY_PATH =
    normpath(joinpath(REPOSITORY_ROOT, "src", "utils", "varx.jl"))
const PROTOCOL_PATH =
    normpath(joinpath(@__DIR__, "..", "protocol.toml"))
const PROJECT_PATH = normpath(joinpath(US_PROJECT_ROOT, "Project.toml"))
const JULIA_MANIFEST_PATH =
    normpath(joinpath(US_PROJECT_ROOT, "Manifest.toml"))

struct QuarterlyPanel
    periods::Vector{String}
    target_names::Vector{String}
    values::Matrix{Float64}
    panel_sha256::String
    manifest_sha256::String
    source_receipts_sha256::String
    information_track::String
end

struct ForecastCell
    model_id::String
    origin_index::Int
    origin_period::String
    target_period::String
    target_id::String
    horizon::Int
    point_forecast::Float64
    actual::Float64
    error::Float64
    absolute_error::Float64
    squared_error::Float64
    mase_scale::Float64
    scaled_absolute_error::Float64
end

struct DiagnosticFailure
    model_id::String
    origin_index::Int
    origin_period::String
    attempted_horizon::Int
    code::String
    exception_type::String
    message::String
end

struct ModelOriginDiagnostic
    model_id::String
    origin_index::Int
    origin_period::String
    training_observation_count::Int
    forecast_horizon::Int
    run_status::String
    diagnostic_class::String
    model_record_sha256::String
    bvar_prior_family::String
    bvar_prior_version::String
    bvar_hyperparameter_identity::String
    selected_ar_lags::String
    design_rows::Int
    design_columns::Int
    design_rank::Int
    design_condition_number::Float64
    companion_spectral_radius::Float64
    stable_within_unit_circle::String
    max_abs_point_forecast::Float64
    diagnostic_source::String
end

struct ScoreSummary
    sample_track::String
    model_id::String
    target_id::String
    horizon::Int
    observation_count::Int
    origin_start::String
    origin_end::String
    rmse::Float64
    mae::Float64
    mase::Float64
    mean_error::Float64
end

struct RelativeScore
    sample_track::String
    model_id::String
    benchmark_model_id::String
    target_id::String
    horizon::Int
    observation_count::Int
    rmse_ratio::Float64
    mae_ratio::Float64
    rmse_gain_percent::Float64
end

struct WeightedRelativeScore
    sample_track::String
    model_id::String
    benchmark_model_id::String
    status::String
    target_horizon_cell_count::Int
    expected_target_horizon_cell_count::Int
    minimum_common_observation_count::Int
    maximum_common_observation_count::Int
    model_failure_count::Int
    all_model_failure_count::Int
    failure_free::Bool
    weighted_macro_average_cellwise_rmse_ratio::Float64
    weighted_macro_average_cellwise_mae_ratio::Float64
end

struct RevisedBenchmarkResult
    contract_id::String
    panel_sha256::String
    panel_manifest_sha256::String
    panel_source_receipts_sha256::String
    information_track::String
    periods::Vector{String}
    target_names::Vector{String}
    model_ids::Vector{String}
    horizons::Vector{Int}
    forecast_cells::Vector{ForecastCell}
    failures::Vector{DiagnosticFailure}
    model_origin_diagnostics::Vector{ModelOriginDiagnostic}
    summaries::Vector{ScoreSummary}
    relative_scores::Vector{RelativeScore}
    weighted_relative_scores::Vector{WeightedRelativeScore}
    benchmark_model_id::String
    promotion_eligible::Bool
    origin_admissible::Bool
    abm_forecast_included::Bool
    equilibrium_benchmark_included::Bool
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function quarter_ordinal(period)
    matched = match(r"^([1-9][0-9]{3})Q([1-4])$", String(period))
    matched === nothing &&
        throw(ArgumentError("invalid quarterly period $(repr(period))"))
    year = parse(Int, matched.captures[1])
    quarter = parse(Int, matched.captures[2])
    return 4year + quarter
end

function validate_periods(periods)
    isempty(periods) && throw(ArgumentError("quarterly panel is empty"))
    ordinals = quarter_ordinal.(periods)
    length(unique(periods)) == length(periods) ||
        throw(ArgumentError("quarterly panel contains duplicate periods"))
    all(diff(ordinals) .== 1) ||
        throw(ArgumentError("quarterly panel periods are not contiguous"))
    return periods
end

function required_false(manifest, key)
    get(manifest, key, nothing) === false ||
        throw(ArgumentError("panel manifest $key must be false"))
    return nothing
end

function required_true(manifest, key)
    get(manifest, key, nothing) === true ||
        throw(ArgumentError("panel manifest $key must be true"))
    return nothing
end

"""
    load_revised_quarterly_panel(panel_path, manifest_path)

Load the compact eight-target revised-data panel. The loader requires a
contiguous, finite panel and rejects any manifest that presents it as an
admissible origin, promotion artifact, or ABM accuracy result.
"""
function load_revised_quarterly_panel(
        panel_path::AbstractString,
        manifest_path::AbstractString,
    )
    panel_bytes = read(panel_path)
    manifest_bytes = read(manifest_path)
    manifest_sha256 = sha256_hex(manifest_bytes)
    manifest_sha256 == CANONICAL_PANEL_MANIFEST_SHA256 ||
        throw(ArgumentError("panel manifest is not the canonical fixture"))
    manifest = TOML.parse(String(manifest_bytes))
    get(manifest, "schema_version", nothing) == PANEL_SCHEMA_VERSION ||
        throw(ArgumentError("panel manifest schema version changed"))
    get(manifest, "artifact_id", nothing) == PANEL_ARTIFACT_ID ||
        throw(ArgumentError("panel artifact identity changed"))
    get(manifest, "information_track", nothing) == INFORMATION_TRACK ||
        throw(ArgumentError("panel information track changed"))
    required_false(manifest, "forecast_origin_admissible")
    required_false(manifest, "promotion_eligible")
    required_false(manifest, "abm_accuracy_claimed")
    required_false(manifest, "bitemporal")
    required_false(manifest, "real_time")
    required_true(manifest, "revised_current_release_snapshot")
    get(manifest, "target_order", nothing) == TARGET_NAMES ||
        throw(ArgumentError("panel manifest target order changed"))
    get(manifest, "panel_sha256", nothing) == CANONICAL_PANEL_SHA256 ||
        throw(ArgumentError("panel manifest canonical panel pin changed"))
    sha256_hex(panel_bytes) == CANONICAL_PANEL_SHA256 ||
        throw(ArgumentError("panel SHA-256 does not match its manifest"))
    get(manifest, "source_receipts_sha256", nothing) ==
        CANONICAL_SOURCE_RECEIPTS_SHA256 ||
        throw(ArgumentError("panel source-receipt pin changed"))
    receipt_file = get(manifest, "source_receipts_file", nothing)
    receipt_file == "source_receipts.json" ||
        throw(ArgumentError("panel source-receipt locator changed"))
    receipt_path = normpath(joinpath(dirname(manifest_path), receipt_file))
    dirname(receipt_path) == normpath(dirname(manifest_path)) ||
        throw(ArgumentError("panel source-receipt locator escaped fixture"))
    isfile(receipt_path) ||
        throw(ArgumentError("panel source-receipt artifact is missing"))
    receipt_sha256 = sha256_hex(read(receipt_path))
    receipt_sha256 == CANONICAL_SOURCE_RECEIPTS_SHA256 ||
        throw(ArgumentError("panel source-receipt SHA-256 changed"))
    quarantine = get(manifest, "quarantine", nothing)
    quarantine isa AbstractDict ||
        throw(ArgumentError("panel quarantine table is missing"))
    for key in (
            "historical_release_availability_verified",
            "first_release_truth",
            "near_mature_truth",
            "mature_truth",
            "inventory_registered",
        )
        required_false(quarantine, key)
    end
    get(quarantine, "origin_count_added", nothing) == 0 ||
        throw(ArgumentError("panel quarantine origin count changed"))
    get(quarantine, "abm_forecast_scores_added", nothing) == 0 ||
        throw(ArgumentError("panel quarantine ABM score count changed"))

    table = CSV.File(
        IOBuffer(panel_bytes);
        missingstring = nothing,
        types = Dict(
            Symbol(column) => column == "period" ? String : Float64 for
                column in PANEL_COLUMNS
        ),
    )
    String.(propertynames(table)) == PANEL_COLUMNS ||
        throw(ArgumentError("unexpected revised-panel columns"))
    rows = collect(table)
    get(manifest, "row_count", nothing) == CANONICAL_PANEL_ROWS ||
        throw(ArgumentError("panel manifest canonical row count changed"))
    length(rows) == CANONICAL_PANEL_ROWS ||
        throw(ArgumentError("revised-panel row count changed"))
    periods = String[getproperty(row, :period) for row in rows]
    validate_periods(periods)
    get(manifest, "start_period", nothing) == CANONICAL_PANEL_START ||
        throw(ArgumentError("panel manifest canonical start period changed"))
    get(manifest, "end_period", nothing) == CANONICAL_PANEL_END ||
        throw(ArgumentError("panel manifest canonical end period changed"))
    first(periods) == CANONICAL_PANEL_START ||
        throw(ArgumentError("revised-panel start period changed"))
    last(periods) == CANONICAL_PANEL_END ||
        throw(ArgumentError("revised-panel end period changed"))
    values = Matrix{Float64}(undef, length(rows), length(TARGET_NAMES))
    for (column, target) in enumerate(TARGET_NAMES)
        values[:, column] .=
            Float64[getproperty(row, Symbol(target)) for row in rows]
    end
    all(isfinite, values) ||
        throw(ArgumentError("revised-panel target values must be finite"))
    size(values, 1) >= MINIMUM_TRAINING_QUARTERS + 1 ||
        throw(ArgumentError("revised panel is too short for one forecast"))

    return QuarterlyPanel(
        periods,
        copy(TARGET_NAMES),
        values,
        sha256_hex(panel_bytes),
        manifest_sha256,
        receipt_sha256,
        INFORMATION_TRACK,
    )
end

function default_model_specs()
    return Any[
        NoChangeSpec(),
        DriftSpec(),
        HistoricalMeanSpec(),
        ARSpec(candidate_lags = [1]),
        ARSpec(candidate_lags = [4]),
        ARSpec(candidate_lags = 1:8),
        BeforeITVARSpec(lags = 1),
        BeforeITVARSpec(lags = 2),
        BeforeITVARSpec(lags = 3),
        BVARSpec(lags = 1, own_lag_mean = 0.0),
    ]
end

canonical_model_ids() = model_id.(default_model_specs())

function ordered_string_list_sha256(values)
    payload = join(String.(values), "\n") * "\n"
    return sha256_hex(Vector{UInt8}(codeunits(payload)))
end

function canonical_value(value)
    if value isa AbstractString
        text = String(value)
        return "string:$(ncodeunits(text)):$text"
    elseif value isa Bool
        return "bool:$(value)"
    elseif value isa Integer
        return "integer:$(typeof(value)):$(value)"
    elseif value isa AbstractFloat
        number = Float64(value)
        bits = string(reinterpret(UInt64, number); base = 16, pad = 16)
        return "float64:0x$bits"
    elseif value isa AbstractDict
        entries = Pair{String, Any}[]
        for (key, item) in pairs(value)
            key isa AbstractString ||
                throw(ArgumentError("model-card dictionary keys must be strings"))
            push!(entries, String(key) => item)
        end
        sort!(entries; by = first)
        encoded = (
            canonical_value(key) * "=>" * canonical_value(item) for
                (key, item) in entries
        )
        return "dict:$(length(entries)):{" * join(encoded, ",") * "}"
    elseif value isa AbstractArray
        dimensions = join(size(value), "x")
        encoded = (canonical_value(item) for item in value)
        return "array:$dimensions:[" * join(encoded, ",") * "]"
    elseif value isa Tuple
        encoded = (canonical_value(item) for item in value)
        return "tuple:$(length(value)):(" * join(encoded, ",") * ")"
    elseif value === nothing
        return "nothing"
    end
    throw(
        ArgumentError(
            "unsupported canonical model-record value type $(typeof(value))",
        ),
    )
end

function canonical_model_record(spec)
    spec_fields = Dict{String, Any}(
        String(field) => getfield(spec, field) for
            field in fieldnames(typeof(spec))
    )
    record = Dict{String, Any}(
        "spec_type" => String(nameof(typeof(spec))),
        "spec_fields" => spec_fields,
        "model_card" => model_card(spec),
    )
    return canonical_value(record)
end

function model_record_sha256(spec)
    record = canonical_model_record(spec)
    return sha256_hex(Vector{UInt8}(codeunits(record)))
end

function canonical_model_set_sha256(specs = default_model_specs())
    return ordered_string_list_sha256(canonical_model_record.(specs))
end

function validate_protocol_error_sign()
    protocol = TOML.parsefile(PROTOCOL_PATH)
    truth = get(protocol, "truth", nothing)
    truth isa AbstractDict ||
        throw(ArgumentError("forecast protocol is missing the truth table"))
    get(truth, "error_sign", nothing) == ERROR_SIGN ||
        throw(ArgumentError("forecast protocol error-sign convention changed"))
    return nothing
end

function validate_panel(panel::QuarterlyPanel)
    panel.target_names == TARGET_NAMES ||
        throw(ArgumentError("diagnostic requires the frozen eight-target order"))
    validate_periods(panel.periods)
    size(panel.values) == (length(panel.periods), length(TARGET_NAMES)) ||
        throw(DimensionMismatch("quarterly panel dimensions changed"))
    all(isfinite, panel.values) ||
        throw(ArgumentError("quarterly panel values must be finite"))
    panel.information_track == INFORMATION_TRACK ||
        throw(ArgumentError("quarterly panel information track changed"))
    return panel
end

function validate_specs(specs)
    isempty(specs) && throw(ArgumentError("model specification set is empty"))
    ids = model_id.(specs)
    length(unique(ids)) == length(ids) ||
        throw(ArgumentError("model identifiers must be unique"))
    expected_specs = default_model_specs()
    canonical_model_record.(specs) ==
        canonical_model_record.(expected_specs) ||
        throw(
        ArgumentError(
            "canonical revised diagnostic specs or model cards changed",
        ),
    )
    return ids
end

function mase_scales(training)
    scales = vec(mean(abs.(diff(training; dims = 1)); dims = 1))
    all(isfinite, scales) ||
        throw(ArgumentError("MASE training scales are non-finite"))
    all(>(0.0), scales) ||
        throw(ArgumentError("MASE training scales must be positive"))
    return scales
end

function var_design_matrix(training, lags, intercept)
    observations, _ = size(training)
    response_rows = observations - lags
    lag_blocks = [
        training[(lags + 1 - lag):(observations - lag), :] for
            lag in 1:lags
    ]
    design = hcat(lag_blocks...)
    size(design, 1) == response_rows ||
        throw(DimensionMismatch("VAR diagnostic design row count changed"))
    return intercept ? hcat(design, ones(response_rows)) : design
end

function var_companion_spectral_radius(training, spec::BeforeITVARSpec)
    alpha, _, _, _ = USForecastBenchmarks.BeforeIT.estimate_VAR(
        training;
        intercept = spec.intercept,
        lags = spec.lags,
    )
    variables = size(training, 2)
    companion = zeros(Float64, variables * spec.lags, variables * spec.lags)
    companion[1:variables, :] .=
        hcat((alpha[:, :, lag] for lag in 1:spec.lags)...)
    if spec.lags > 1
        companion[(variables + 1):end, 1:(end - variables)] .=
            Matrix{Float64}(I, variables * (spec.lags - 1), variables * (spec.lags - 1))
    end
    return maximum(abs, eigvals(companion))
end

function diagnostic_model_identity(spec)
    record_sha256 = model_record_sha256(spec)
    if !(spec isa BVARSpec)
        return (
            record_sha256 = record_sha256,
            prior_family = "not_applicable",
            prior_version = "not_applicable",
            hyperparameters = "not_applicable",
        )
    end
    card = model_card(spec)
    for key in ("prior_family", "prior_version", "hyperparameters")
        haskey(card, key) ||
            throw(ArgumentError("BVAR model card omitted $key"))
    end
    return (
        record_sha256 = record_sha256,
        prior_family = String(card["prior_family"]),
        prior_version = String(card["prior_version"]),
        hyperparameters = canonical_value(card["hyperparameters"]),
    )
end

function model_origin_diagnostic(
        spec,
        run,
        training,
        origin_index,
        origin_period,
        forecast_horizon,
    )
    identity = diagnostic_model_identity(spec)
    if run.status != :ok
        return ModelOriginDiagnostic(
            run.model_id,
            origin_index,
            origin_period,
            size(training, 1),
            forecast_horizon,
            "FAILED",
            "failed_run",
            identity.record_sha256,
            identity.prior_family,
            identity.prior_version,
            identity.hyperparameters,
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
    selected_ar_lags = "not_applicable"
    design_rows = -1
    design_columns = -1
    design_rank = -1
    design_condition_number = NaN
    companion_spectral_radius = NaN
    stable_within_unit_circle = "not_applicable"
    diagnostic_class = "point_only_no_fit_diagnostics"
    diagnostic_source = "benchmark_point_forecast_only"

    if spec isa ARSpec
        selected = get(forecast.diagnostics, "selected_lags", nothing)
        selected === nothing &&
            throw(ArgumentError("AR benchmark omitted selected-lag diagnostics"))
        selected_ar_lags = join(Int.(selected), ";")
        diagnostic_class = "univariate_ar_selected_lags"
        diagnostic_source = "benchmark_api"
    elseif spec isa BeforeITVARSpec
        design = var_design_matrix(training, spec.lags, spec.intercept)
        design_rows, design_columns = size(design)
        design_rank = rank(design)
        design_condition_number = cond(design)
        companion_spectral_radius =
            var_companion_spectral_radius(training, spec)
        stable_within_unit_circle =
            companion_spectral_radius < 1.0 ? "true" : "false"
        diagnostic_class = "var_design_and_companion"
        diagnostic_source =
            "recomputed_from_origin_training_and_frozen_spec"
    elseif spec isa BVARSpec
        design_rows =
            Int(forecast.diagnostics["training_response_rows"])
        design_columns = Int(forecast.diagnostics["design_columns"])
        design_rank =
            Int(forecast.diagnostics["likelihood_design_rank"])
        diagnostic_class = "bvar_fit_shape"
        diagnostic_source = "benchmark_api"
    end

    return ModelOriginDiagnostic(
        run.model_id,
        origin_index,
        origin_period,
        size(training, 1),
        forecast_horizon,
        "OK",
        diagnostic_class,
        identity.record_sha256,
        identity.prior_family,
        identity.prior_version,
        identity.hyperparameters,
        selected_ar_lags,
        design_rows,
        design_columns,
        design_rank,
        design_condition_number,
        companion_spectral_radius,
        stable_within_unit_circle,
        maximum(abs, forecast.point),
        diagnostic_source,
    )
end

function collect_origin!(
        forecast_cells,
        failures,
        model_origin_diagnostics,
        panel,
        specs,
        origin_index,
    )
    available_horizon =
        min(MAXIMUM_HORIZON, length(panel.periods) - origin_index)
    available_horizon >= 1 ||
        throw(ArgumentError("origin has no realized future target"))
    training = panel.values[1:origin_index, :]
    scales = mase_scales(training)
    sample = OriginData(
        origin_id = "revised-diagnostic-$(panel.periods[origin_index])",
        origin_key = panel.periods[origin_index],
        training_keys = panel.periods[1:origin_index],
        forecast_keys = panel.periods[
            (origin_index + 1):(origin_index + available_horizon),
        ],
        y_train = training,
        target_names = panel.target_names,
    )
    for spec in specs
        run = run_benchmark(spec, sample)
        push!(
            model_origin_diagnostics,
            model_origin_diagnostic(
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
            continue
        end
        forecast = something(run.forecast)
        for horizon in HORIZONS
            horizon <= available_horizon || continue
            target_index = origin_index + horizon
            for (column, target) in enumerate(panel.target_names)
                point = forecast.point[horizon, column]
                actual = panel.values[target_index, column]
                error = point - actual
                push!(
                    forecast_cells,
                    ForecastCell(
                        run.model_id,
                        origin_index,
                        panel.periods[origin_index],
                        panel.periods[target_index],
                        target,
                        horizon,
                        point,
                        actual,
                        error,
                        abs(error),
                        error^2,
                        scales[column],
                        abs(error) / scales[column],
                    ),
                )
            end
        end
    end
    return nothing
end

cell_key(row::ForecastCell) =
    (row.origin_index, row.target_id, row.horizon)

function common_cell_keys(forecast_cells, model_ids)
    observed_models = Dict{Tuple{Int, String, Int}, Set{String}}()
    for row in forecast_cells
        push!(
            get!(
                observed_models,
                cell_key(row),
                Set{String}(),
            ),
            row.model_id,
        )
    end
    required = Set(model_ids)
    return Set(
        key for (key, models) in observed_models if models == required
    )
end

function summarize_rows(track, rows, model_ids, target_names)
    summaries = ScoreSummary[]
    for model in model_ids
        for target in target_names
            for horizon in HORIZONS
                selected = filter(
                    row ->
                    row.model_id == model &&
                        row.target_id == target &&
                        row.horizon == horizon,
                    rows,
                )
                isempty(selected) && continue
                errors = getfield.(selected, :error)
                origins = getfield.(selected, :origin_period)
                push!(
                    summaries,
                    ScoreSummary(
                        track,
                        model,
                        target,
                        horizon,
                        length(selected),
                        minimum(origins),
                        maximum(origins),
                        sqrt(mean(getfield.(selected, :squared_error))),
                        mean(getfield.(selected, :absolute_error)),
                        mean(getfield.(selected, :scaled_absolute_error)),
                        mean(errors),
                    ),
                )
            end
        end
    end
    return summaries
end

function relative_scores(summaries, model_ids, target_names, benchmark_model_id)
    by_key = Dict(
        (
                row.sample_track,
                row.model_id,
                row.target_id,
                row.horizon,
            ) => row for row in summaries
    )
    tracks = [COMMON_AVAILABLE_TRACK, BALANCED_H12_TRACK]
    relative = RelativeScore[]
    for track in tracks
        for model in model_ids
            for target in target_names
                for horizon in HORIZONS
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
                            "relative score samples are not matched",
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

function weighted_relative_scores(
        relative,
        model_ids,
        benchmark_model_id,
        failures,
    )
    expected_cells = length(TARGET_NAMES) * length(HORIZONS)
    all_model_failure_count = length(failures)
    output = WeightedRelativeScore[]
    for track in (COMMON_AVAILABLE_TRACK, BALANCED_H12_TRACK)
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
                TARGET_WEIGHTS[row.target_id] *
                    HORIZON_WEIGHTS[row.horizon] for row in selected
                ;
                init = 0.0,
            )
            observation_counts = getfield.(selected, :observation_count)
            minimum_common_observation_count =
                isempty(observation_counts) ? -1 : minimum(observation_counts)
            maximum_common_observation_count =
                isempty(observation_counts) ? -1 : maximum(observation_counts)
            model_failure_count =
                count(failure -> failure.model_id == model, failures)
            failure_free = all_model_failure_count == 0
            if complete && total_weight ≈ 1.0 && failure_free
                weighted_rmse = sum(
                    TARGET_WEIGHTS[row.target_id] *
                        HORIZON_WEIGHTS[row.horizon] *
                        row.rmse_ratio for row in selected
                    ;
                    init = 0.0,
                )
                weighted_mae = sum(
                    TARGET_WEIGHTS[row.target_id] *
                        HORIZON_WEIGHTS[row.horizon] *
                        row.mae_ratio for row in selected
                    ;
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
                    minimum_common_observation_count,
                    maximum_common_observation_count,
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
    run_revised_benchmark_diagnostic(panel; specs = default_model_specs())

Run expanding-window, iterated point forecasts on the revised-data panel.
Every comparison uses cells common to every requested model. This function
does not register an origin, run the ABM, or provide promotion evidence.
"""
function run_revised_benchmark_diagnostic(
        panel::QuarterlyPanel;
        specs = default_model_specs(),
        minimum_training_quarters = MINIMUM_TRAINING_QUARTERS,
    )
    validate_protocol_error_sign()
    validate_panel(panel)
    minimum_training_quarters == MINIMUM_TRAINING_QUARTERS ||
        throw(
        ArgumentError(
            "minimum training window is frozen at $MINIMUM_TRAINING_QUARTERS",
        ),
    )
    model_ids = validate_specs(specs)
    benchmark_model_id = model_id(BeforeITVARSpec(lags = 1))
    benchmark_model_id in model_ids ||
        throw(ArgumentError("VAR(1) reference benchmark is required"))

    forecast_cells = ForecastCell[]
    failures = DiagnosticFailure[]
    model_origin_diagnostics = ModelOriginDiagnostic[]
    for origin_index in
        minimum_training_quarters:(length(panel.periods) - 1)
        collect_origin!(
            forecast_cells,
            failures,
            model_origin_diagnostics,
            panel,
            specs,
            origin_index,
        )
    end

    common_keys = common_cell_keys(forecast_cells, model_ids)
    common_rows =
        filter(row -> cell_key(row) in common_keys, forecast_cells)
    balanced_last_origin = length(panel.periods) - MAXIMUM_HORIZON
    balanced_rows = filter(
        row -> row.origin_index <= balanced_last_origin,
        common_rows,
    )
    summaries = vcat(
        summarize_rows(
            COMMON_AVAILABLE_TRACK,
            common_rows,
            model_ids,
            panel.target_names,
        ),
        summarize_rows(
            BALANCED_H12_TRACK,
            balanced_rows,
            model_ids,
            panel.target_names,
        ),
    )
    relative = relative_scores(
        summaries,
        model_ids,
        panel.target_names,
        benchmark_model_id,
    )
    weighted = weighted_relative_scores(
        relative,
        model_ids,
        benchmark_model_id,
        failures,
    )

    return RevisedBenchmarkResult(
        CONTRACT_ID,
        panel.panel_sha256,
        panel.manifest_sha256,
        panel.source_receipts_sha256,
        panel.information_track,
        copy(panel.periods),
        copy(panel.target_names),
        model_ids,
        copy(HORIZONS),
        forecast_cells,
        failures,
        model_origin_diagnostics,
        summaries,
        relative,
        weighted,
        benchmark_model_id,
        false,
        false,
        false,
        false,
    )
end

function csv_escape(value)
    text = if value isa AbstractFloat
        repr(Float64(value))
    else
        string(value)
    end
    return occursin(r"[\",\r\n]", text) ?
        "\"" * replace(text, "\"" => "\"\"") * "\"" : text
end

function write_struct_csv(path, rows, ::Type{T}) where {T}
    headers = fieldnames(T)
    open(path, "w") do io
        println(io, join(String.(headers), ","))
        for row in rows
            println(
                io,
                join(
                    (csv_escape(getfield(row, field)) for field in headers),
                    ",",
                ),
            )
        end
    end
    return path
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
                row.target_id == first(result.target_names) &&
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

function write_manifest(path, result, output_hashes)
    canonical_specs = default_model_specs()
    model_id_set_sha256 = ordered_string_list_sha256(result.model_ids)
    model_record_sha256s = model_record_sha256.(canonical_specs)
    model_set_sha256 = canonical_model_set_sha256(canonical_specs)
    bvar_spec = only(filter(spec -> spec isa BVARSpec, canonical_specs))
    bvar_card = model_card(bvar_spec)
    bvar_hyperparameter_identity =
        canonical_value(bvar_card["hyperparameters"])
    all_available_counts =
        track_observation_counts(result, COMMON_AVAILABLE_TRACK)
    balanced_counts =
        track_observation_counts(result, BALANCED_H12_TRACK)
    lines = [
        "schema_version = \"beforeit-us-revised-data-benchmark-result.v2\"",
        "contract_id = \"$(result.contract_id)\"",
        "information_track = \"$(result.information_track)\"",
        "panel_sha256 = \"$(result.panel_sha256)\"",
        "panel_manifest_sha256 = \"$(result.panel_manifest_sha256)\"",
        "panel_source_receipts_sha256 = \"$(result.panel_source_receipts_sha256)\"",
        "start_period = \"$(first(result.periods))\"",
        "end_period = \"$(last(result.periods))\"",
        "target_count = $(length(result.target_names))",
        "model_count = $(length(result.model_ids))",
        "target_ids = $(toml_string_array(result.target_names))",
        "model_ids = $(toml_string_array(result.model_ids))",
        "model_id_set_canonicalization = \"ordered_utf8_lines_lf\"",
        "model_id_set_sha256 = \"$model_id_set_sha256\"",
        "model_record_canonicalization = \"$MODEL_RECORD_CANONICALIZATION\"",
        "model_record_sha256s = $(toml_string_array(model_record_sha256s))",
        "model_set_sha256 = \"$model_set_sha256\"",
        "canonical_model_set_enforced = true",
        "bvar_model_id = \"$(model_id(bvar_spec))\"",
        "bvar_prior_family = \"$(bvar_card["prior_family"])\"",
        "bvar_prior_version = \"$(bvar_card["prior_version"])\"",
        "bvar_hyperparameter_selection = \"none\"",
        "bvar_hyperparameter_identity = $(toml_string(bvar_hyperparameter_identity))",
        "forecast_cell_count = $(length(result.forecast_cells))",
        "failure_count = $(length(result.failures))",
        "failure_free = $(isempty(result.failures))",
        "model_origin_diagnostic_count = $(length(result.model_origin_diagnostics))",
        "score_summary_count = $(length(result.summaries))",
        "relative_score_count = $(length(result.relative_scores))",
        "weighted_relative_score_count = $(length(result.weighted_relative_scores))",
        "benchmark_model_id = \"$(result.benchmark_model_id)\"",
        "horizons = [$(join(result.horizons, ", "))]",
        "horizon_weights = [$(join((HORIZON_WEIGHTS[horizon] for horizon in result.horizons), ", "))]",
        "target_weights = [$(join((TARGET_WEIGHTS[target] for target in result.target_names), ", "))]",
        "weighted_ratio_formula = \"$WEIGHTED_RATIO_FORMULA\"",
        "weighted_ratio_semantics = \"$WEIGHTED_RATIO_SEMANTICS\"",
        "weighted_status_complete = \"COMPLETE_MATCHED\"",
        "all_available_common_observation_counts = [$(join(all_available_counts, ", "))]",
        "balanced_h12_common_observation_counts = [$(join(balanced_counts, ", "))]",
        "minimum_training_quarters = $MINIMUM_TRAINING_QUARTERS",
        "forecast_origin_admissible = false",
        "promotion_eligible = false",
        "abm_forecast_included = false",
        "equilibrium_benchmark_included = false",
        "production_accuracy_score = false",
        "paper_parity_claimed = false",
        "truth_vintage = \"revised_mixed_vintage_snapshot\"",
        "error_sign = \"$ERROR_SIGN\"",
        "mean_error_definition = \"mean(point_forecast - actual)\"",
        "sample_policy = \"common successful cells across every requested model; all-available and balanced-h12 reported separately\"",
        "pandemic_policy = \"pandemic retained in headline full sample; regime slices pending\"",
        "equilibrium_benchmark_status = \"MISSING_NOT_SCORED\"",
        "abm_benchmark_status = \"MISSING_NOT_SCORED\"",
        "diagnostic_code_sha256 = \"$(sha256_hex(read(abspath(@__FILE__))))\"",
        "benchmark_module_sha256 = \"$(sha256_hex(read(BENCHMARK_MODULE_PATH)))\"",
        "bvar_module_sha256 = \"$(sha256_hex(read(BVAR_MODULE_PATH)))\"",
        "var_utility_sha256 = \"$(sha256_hex(read(VAR_UTILITY_PATH)))\"",
        "protocol_sha256 = \"$(sha256_hex(read(PROTOCOL_PATH)))\"",
        "julia_project_sha256 = \"$(sha256_hex(read(PROJECT_PATH)))\"",
        "julia_manifest_sha256 = \"$(sha256_hex(read(JULIA_MANIFEST_PATH)))\"",
        "julia_version = \"$(VERSION)\"",
        "blas_vendor = \"$(BLAS.vendor())\"",
        "blas_threads = $(BLAS.get_num_threads())",
        "deterministic_execution_policy = \"Float64 point forecasts only; zero predictive draws; expanding windows and model set frozen; no stochastic RNG consumed; CSV Float64 repr and ordered rows\"",
    ]
    for (key, value) in sort!(collect(output_hashes); by = first)
        push!(lines, "$(key)_sha256 = \"$(value)\"")
    end
    write(path, join(lines, "\n") * "\n")
    return path
end

"""
    write_revised_benchmark_diagnostic(result, output_directory)

Write deterministic research-only point forecasts and score tables. Output is
kept outside the sealed production forecast registry.
"""
function write_revised_benchmark_diagnostic(
        result::RevisedBenchmarkResult,
        output_directory::AbstractString,
    )
    mkpath(output_directory)
    paths = Dict(
        "forecast_cells" => joinpath(output_directory, "forecast_cells.csv"),
        "failures" => joinpath(output_directory, "failures.csv"),
        "model_origin_diagnostics" =>
            joinpath(output_directory, "model_origin_diagnostics.csv"),
        "score_summaries" => joinpath(output_directory, "score_summaries.csv"),
        "relative_scores" => joinpath(output_directory, "relative_scores.csv"),
        "weighted_relative_scores" =>
            joinpath(output_directory, "weighted_relative_scores.csv"),
    )
    write_struct_csv(
        paths["forecast_cells"],
        result.forecast_cells,
        ForecastCell,
    )
    write_struct_csv(paths["failures"], result.failures, DiagnosticFailure)
    write_struct_csv(
        paths["model_origin_diagnostics"],
        result.model_origin_diagnostics,
        ModelOriginDiagnostic,
    )
    write_struct_csv(
        paths["score_summaries"],
        result.summaries,
        ScoreSummary,
    )
    write_struct_csv(
        paths["relative_scores"],
        result.relative_scores,
        RelativeScore,
    )
    write_struct_csv(
        paths["weighted_relative_scores"],
        result.weighted_relative_scores,
        WeightedRelativeScore,
    )
    hashes = Dict(
        key => sha256_hex(read(path)) for (key, path) in paths
    )
    manifest_path = joinpath(output_directory, "manifest.toml")
    write_manifest(manifest_path, result, hashes)
    hashes["manifest"] = sha256_hex(read(manifest_path))
    return (; paths, manifest_path, hashes)
end

end
