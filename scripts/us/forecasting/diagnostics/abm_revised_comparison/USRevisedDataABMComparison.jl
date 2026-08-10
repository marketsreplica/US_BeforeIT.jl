module USRevisedDataABMComparison

using Dates
using JLD2
using LinearAlgebra
using Random
using SHA
using Statistics

import BeforeIT as Bit

if !isdefined(@__MODULE__, :USRevisedDataBenchmarkDiagnostic)
    include(joinpath(@__DIR__, "..", "USRevisedDataBenchmarkDiagnostic.jl"))
end
using .USRevisedDataBenchmarkDiagnostic

const BASE = USRevisedDataBenchmarkDiagnostic

export ABMVariant,
    ABMComparisonResult,
    ABMOriginDiagnostic,
    ABMWeightedScore,
    EnsembleSummary,
    MonteCarloError,
    HEADLINE_VARIANT,
    BURN_IN_VARIANT,
    OUTLOOK_VARIANT,
    HEADLINE_V2_VARIANT,
    OUTLOOK_V2_VARIANT,
    RECONCILED_CALIBRATION_OBJECT_PATH,
    ACTIVE_CALIBRATION_PATH,
    simulate_abm_ensembles,
    run_abm_comparison,
    write_abm_comparison,
    write_abm_outlook

const CONTRACT_ID = "beforeit-us-revised-data-abm-comparison.v1"
const INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
const MIXED_VINTAGE_STRUCTURAL_YEAR = 2024
const MODEL_SCALE = 1.0e-5
const SIMULATION_HORIZON = 12
const EXOGENOUS_TRUNCATION_KEYS = ("C_G", "C_E", "Y_I")
const PANEL_FIRST_PERIOD = "2000Q3"

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const CALIBRATION_OBJECT_PATH = joinpath(
    REPOSITORY_ROOT,
    "data",
    "us",
    "calibration",
    "US_2024_calibration_object.jld2",
)
const BASE_DIAGNOSTIC_PATH = normpath(
    joinpath(@__DIR__, "..", "USRevisedDataBenchmarkDiagnostic.jl"),
)

# v2 initialises the model from a commodity-balance-reconciled calibration artifact
# built by `scripts/us/calibration/reconcile_commodity_balance.jl`. The artifact -- not
# this module -- carries the reconciliation mode and the growth-expectation
# specification, so the selection is a single path.
const RECONCILED_CALIBRATION_OBJECT_PATH = joinpath(
    REPOSITORY_ROOT,
    "data",
    "us",
    "calibration",
    "US_2024_calibration_object_reconciled.jld2",
)

# Set by the runner before `simulate_abm_ensembles`; the manifests seal whatever was
# actually used, never the default.
const ACTIVE_CALIBRATION_PATH = Ref(CALIBRATION_OBJECT_PATH)

"""
    calibration_provenance_lines()

TOML lines describing the calibration artifact the run actually used, including the
reconciliation metadata when the artifact carries it. `lambda` is an explicit accounting
choice (the artifact's expenditure aggregates are scaled onto its production account) and
must survive into every manifest.
"""
function calibration_provenance_lines()
    path = ACTIVE_CALIBRATION_PATH[]
    lines = [
        "calibration_object_path = \"$(relpath(path, REPOSITORY_ROOT))\"",
        "calibration_object_sha256 = \"$(sha256_hex(read(path)))\"",
    ]
    stored = JLD2.load(path)
    metadata = get(stored, "metadata", nothing)
    reconciled = metadata isa AbstractDict && haskey(metadata, "method")
    push!(lines, "commodity_balance_reconciled = $reconciled")
    if reconciled
        push!(lines, "reconciliation_method = \"$(metadata["method"])\"")
        push!(lines, "reconciliation_mode = \"$(get(metadata, "mode", "unknown"))\"")
        push!(lines, "reconciliation_rho = $(get(metadata, "rho", NaN))")
        push!(lines, "reconciliation_lambda = $(get(metadata, "lambda", NaN))")
        push!(
            lines,
            "reconciliation_lambda_semantics = \"explicit accounting choice: the four " *
                "final-demand aggregates C, G, I and X (and capital_consumption and " *
                "gross_capitalformation_dwellings, which set the investment budget) are " *
                "scaled by lambda so the artifact's expenditure aggregates match its " *
                "production account and the opening commodity balance clears exactly. " *
                "lambda is fixed by the accounting identity alone and was not chosen with " *
                "reference to any forecast error.\"",
        )
        push!(
            lines,
            "growth_expectation_specification = \"$(get(metadata, "expectations", "legacy_ar1_log_level"))\"",
        )
        push!(lines, "opening_inventories_from_discrepancy = false")
        push!(lines, "measured_bea_imports_retained = true")
    else
        push!(lines, "growth_expectation_specification = \"legacy_ar1_log_level\"")
    end
    return lines
end

# The five targets the ABM serves with a native operator. `pce_price_index`,
# `core_pce_price_index` and `payroll_employment` need measurement bridges the
# model does not provide and are deliberately absent.
const ABM_TARGET_IDS = [
    "real_gdp",
    "gdp_deflator",
    "nominal_gdp",
    "unemployment_rate",
    "effective_federal_funds_rate",
]
const HEADLINE_TARGET_IDS = ["real_gdp", "gdp_deflator"]
const SECONDARY_TARGET_IDS = ["nominal_gdp", "effective_federal_funds_rate"]

# `unemployment_rate` is emitted and diagnosed but never enters a weighted
# score: the initial unemployed stock is a length-1 annual array frozen at
# 2024, so every historical origin opens at the 2024 labour market.
const UNSCORED_APPENDIX_TARGET_IDS = ["unemployment_rate"]
const SCORED_TARGET_SETS = [
    ("headline_real_gdp_gdp_deflator", HEADLINE_TARGET_IDS),
    (
        "secondary_nominal_gdp_effective_federal_funds_rate",
        SECONDARY_TARGET_IDS,
    ),
]

const ALL_AVAILABLE_TRACK = "abm_all_available_common_cells"
const BALANCED_H12_TRACK = "abm_balanced_h12_common_cells"
const PANDEMIC_MASKED_TRACK = "abm_pandemic_masked_common_cells"
const TRACKS = (ALL_AVAILABLE_TRACK, BALANCED_H12_TRACK, PANDEMIC_MASKED_TRACK)

# Frozen `PT_ACUTE` window from the project's regime matrix: the cut is on the
# TARGET date, not the origin date. The masked track keeps `PT_PRE` + `PT_POST`.
const ACUTE_PANDEMIC_FIRST_TARGET_PERIOD = "2020Q1"
const ACUTE_PANDEMIC_LAST_TARGET_PERIOD = "2021Q4"

struct ABMVariant
    name::String
    mean_model_id::String
    median_model_id::String
    burn_in_quarters::Int
    default_paths::Int
end

const HEADLINE_VARIANT = ABMVariant(
    "headline",
    "beforeit_abm_us_v1_mean",
    "beforeit_abm_us_v1_median",
    0,
    500,
)
const BURN_IN_VARIANT = ABMVariant(
    "burnin",
    "beforeit_abm_us_v1_mean_burnin",
    "beforeit_abm_us_v1_median_burnin",
    1,
    128,
)
const OUTLOOK_VARIANT = ABMVariant(
    "outlook",
    "beforeit_abm_us_v1_mean",
    "beforeit_abm_us_v1_median",
    0,
    500,
)
const HEADLINE_V2_VARIANT = ABMVariant(
    "headline_v2",
    "beforeit_abm_us_v2_mean",
    "beforeit_abm_us_v2_median",
    0,
    500,
)
const OUTLOOK_V2_VARIANT = ABMVariant(
    "outlook_v2",
    "beforeit_abm_us_v2_mean",
    "beforeit_abm_us_v2_median",
    0,
    500,
)

# v2 draws the SAME seed stream as its v1 counterpart, so the v1 -> v2 delta is a
# matched-seed contrast and not a Monte-Carlo artifact. Only the cache key differs.
const SEED_STREAM_ALIASES =
    Dict("headline_v2" => "headline", "outlook_v2" => "outlook")
seed_stream_name(name::AbstractString) = get(SEED_STREAM_ALIASES, name, String(name))

struct EnsembleSummary
    variant::String
    origin_index::Int
    origin_period::String
    target_period::String
    target_id::String
    horizon::Int
    paths_used::Int
    ensemble_mean::Float64
    ensemble_median::Float64
    ensemble_sd::Float64
    monte_carlo_standard_error::Float64
    percentile_05::Float64
    percentile_10::Float64
    percentile_25::Float64
    percentile_75::Float64
    percentile_90::Float64
    percentile_95::Float64
end

struct ABMOriginDiagnostic
    variant::String
    origin_index::Int
    origin_period::String
    build_period::String
    calibration_date::String
    burn_in_quarters::Int
    simulated_quarters::Int
    t_prime::Int
    t_max::Int
    paths_requested::Int
    paths_used::Int
    paths_failed::Int
    calibration_seconds::Float64
    simulation_seconds::Float64
end

struct ABMWeightedScore
    sample_track::String
    target_set::String
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

struct MonteCarloError
    model_family::String
    target_id::String
    horizon::Int
    origin_count::Int
    monte_carlo_paths::Int
    mean_ensemble_sd::Float64
    mean_monte_carlo_standard_error::Float64
    maximum_monte_carlo_standard_error::Float64
end

struct ABMComparisonResult
    contract_id::String
    variant::String
    information_track::String
    panel_sha256::String
    panel_manifest_sha256::String
    panel_source_receipts_sha256::String
    periods::Vector{String}
    target_ids::Vector{String}
    model_ids::Vector{String}
    horizons::Vector{Int}
    monte_carlo_paths::Int
    burn_in_quarters::Int
    simulated_quarters::Int
    forecast_cells::Vector{ForecastCell}
    failures::Vector{DiagnosticFailure}
    abm_origin_diagnostics::Vector{ABMOriginDiagnostic}
    ensemble_summaries::Vector{EnsembleSummary}
    summaries::Vector{ScoreSummary}
    relative_scores::Vector{RelativeScore}
    weighted_relative_scores::Vector{ABMWeightedScore}
    monte_carlo_errors::Vector{MonteCarloError}
    benchmark_model_id::String
    abm_mean_model_id::String
    abm_median_model_id::String
    abm_path_failure_count::Int
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

# ---------------------------------------------------------------------------
# period helpers
# ---------------------------------------------------------------------------

function period_to_quarter_end(period::AbstractString)
    matched = match(r"^([1-9][0-9]{3})Q([1-4])$", String(period))
    matched === nothing &&
        throw(ArgumentError("invalid quarterly period $(repr(period))"))
    calendar_year = parse(Int, matched.captures[1])
    quarter = parse(Int, matched.captures[2])
    return if quarter == 1
        DateTime(calendar_year, 3, 31)
    elseif quarter == 2
        DateTime(calendar_year, 6, 30)
    elseif quarter == 3
        DateTime(calendar_year, 9, 30)
    else
        DateTime(calendar_year, 12, 31)
    end
end

function shift_period(period::AbstractString, offset::Int)
    ordinal = BASE.quarter_ordinal(period) + offset
    calendar_year = div(ordinal - 1, 4)
    quarter = ordinal - 4 * calendar_year
    return string(calendar_year, "Q", quarter)
end

origin_index_for_period(period::AbstractString) =
    BASE.quarter_ordinal(period) - BASE.quarter_ordinal(PANEL_FIRST_PERIOD) + 1

function is_acute_pandemic_target(period::AbstractString)
    ordinal = BASE.quarter_ordinal(period)
    return ordinal >= BASE.quarter_ordinal(ACUTE_PANDEMIC_FIRST_TARGET_PERIOD) &&
        ordinal <= BASE.quarter_ordinal(ACUTE_PANDEMIC_LAST_TARGET_PERIOD)
end

function target_column(panel::QuarterlyPanel, target_id::AbstractString)
    matches = findall(==(target_id), panel.target_names)
    length(matches) == 1 ||
        throw(ArgumentError("panel must contain target $target_id exactly once"))
    return only(matches)
end

# ---------------------------------------------------------------------------
# ABM origin construction and simulation
# ---------------------------------------------------------------------------

"""
    historical_calibration_object(calibration_object, calibration_date)

Return a shallow copy of the shipped calibration object whose annual index
resolves at `calibration_date`. Every annual/structural array in the artifact
has length one (the 2024 vintage), so this only makes the single available
structural row addressable at historical dates; it does not invent data. The
resulting origin is therefore mixed-vintage by construction.
"""
function historical_calibration_object(calibration_object, calibration_date::DateTime)
    calibration = copy(calibration_object.calibration)
    structural_date = DateTime(year(calibration_date), 12, 31)
    calibration["years_num"] = [Bit.date2num(structural_date)]
    return Bit.CalibrationData(
        calibration,
        calibration_object.figaro,
        calibration_object.data,
        calibration_object.ea,
        structural_date,
        calibration_object.estimation_date,
    )
end

"""
    abm_origin_inputs(calibration_object, calibration_date)

Derive raw parameters and initial conditions at `calibration_date`, then
truncate the exogenous government/export/import arrays to `1:T_prime`. The
truncation is past-only hygiene: simulated paths are provably invariant to the
post-origin entries, which the model never reads.
"""
function abm_origin_inputs(calibration_object, calibration_date::DateTime)
    parameters, initial_conditions = Bit.get_params_and_initial_conditions(
        historical_calibration_object(calibration_object, calibration_date),
        calibration_date;
        scale = MODEL_SCALE,
        use_growth_rate_ar1 = false,
    )
    t_prime = Int(parameters["T_prime"])
    for key in EXOGENOUS_TRUNCATION_KEYS
        haskey(initial_conditions, key) || continue
        initial_conditions[key] =
            reshape(vec(initial_conditions[key])[1:t_prime], t_prime, 1)
    end
    return parameters, initial_conditions
end

struct SimulatedPath
    real_gdp::Vector{Float64}
    nominal_gdp::Vector{Float64}
    policy_rate::Vector{Float64}
    unemployment_rate::Vector{Float64}
end

path_seed(variant_name, origin_period, path) = Int(
    hash((
        :beforeit_us_abm_revised_comparison_v1,
        variant_name,
        origin_period,
        path,
    )) % 0x40000000,
)

"""
    simulate_path(parameters, initial_conditions, quarters, seed)

Construct a fresh model after seeding the global RNG and step it serially.
`Bit.Model` draws the initial microstate from the global RNG, so the seed must
be set immediately before construction. The unemployment rate has no `Data`
field and must be read off the worker state after every step, which is why this
loop does not use `Bit.run!`.
"""
function simulate_path(parameters, initial_conditions, quarters::Int, seed::Int)
    Random.seed!(seed)
    model = Bit.Model(parameters, initial_conditions)
    active_population = Int(model.prop.H_act)
    unemployment =
        Float64[100.0 * count(==(0), model.w_act.O_h) / active_population]
    for _ in 1:quarters
        Bit.step!(model; parallel = false)
        Bit.collect_data!(model)
        push!(
            unemployment,
            100.0 * count(==(0), model.w_act.O_h) / active_population,
        )
    end
    return SimulatedPath(
        copy(model.data.real_gdp),
        copy(model.data.nominal_gdp),
        100.0 .* ((1.0 .+ copy(model.data.euribor)) .^ 4 .- 1.0),
        unemployment,
    )
end

function path_is_usable(path::SimulatedPath)
    all(isfinite, path.real_gdp) || return false
    all(isfinite, path.nominal_gdp) || return false
    all(isfinite, path.policy_rate) || return false
    all(isfinite, path.unemployment_rate) || return false
    all(>(0.0), path.real_gdp) || return false
    all(>(0.0), path.nominal_gdp) || return false
    return true
end

annualized_log_growth(current, previous) =
    400.0 * (log(current) - log(previous))

"""
    pathwise_values(paths, target_id, current_row, previous_row)

Apply the target operator to each path separately. Ensemble statistics are
taken afterwards, so the reported mean is the mean of transformed paths and not
the transform of the mean path.
"""
function pathwise_values(paths, target_id, current_row::Int, previous_row::Int)
    if target_id == "real_gdp"
        return [
            annualized_log_growth(
                path.real_gdp[current_row],
                path.real_gdp[previous_row],
            ) for path in paths
        ]
    elseif target_id == "nominal_gdp"
        return [
            annualized_log_growth(
                path.nominal_gdp[current_row],
                path.nominal_gdp[previous_row],
            ) for path in paths
        ]
    elseif target_id == "gdp_deflator"
        return [
            400.0 * (
                (
                    log(path.nominal_gdp[current_row]) -
                        log(path.real_gdp[current_row])
                ) - (
                    log(path.nominal_gdp[previous_row]) -
                        log(path.real_gdp[previous_row])
                )
            ) for path in paths
        ]
    elseif target_id == "unemployment_rate"
        return [path.unemployment_rate[current_row] for path in paths]
    elseif target_id == "effective_federal_funds_rate"
        return [path.policy_rate[current_row] for path in paths]
    end
    throw(ArgumentError("no ABM operator for target $target_id"))
end

function summarize_ensemble(
        variant::ABMVariant,
        origin_index::Int,
        origin_period::AbstractString,
        paths::Vector{SimulatedPath},
    )
    summaries = EnsembleSummary[]
    origin_row = variant.burn_in_quarters + 1
    used = length(paths)
    for horizon in 1:SIMULATION_HORIZON
        current_row = origin_row + horizon
        previous_row = current_row - 1
        for target_id in ABM_TARGET_IDS
            values =
                pathwise_values(paths, target_id, current_row, previous_row)
            dispersion = used > 1 ? std(values) : NaN
            push!(
                summaries,
                EnsembleSummary(
                    variant.name,
                    origin_index,
                    String(origin_period),
                    shift_period(origin_period, horizon),
                    target_id,
                    horizon,
                    used,
                    mean(values),
                    median(values),
                    dispersion,
                    dispersion / sqrt(used),
                    quantile(values, 0.05),
                    quantile(values, 0.10),
                    quantile(values, 0.25),
                    quantile(values, 0.75),
                    quantile(values, 0.90),
                    quantile(values, 0.95),
                ),
            )
        end
    end
    return summaries
end

"""
    simulate_abm_ensembles(variant, origins; paths, ...)

Free-run `paths` independent ensembles at every origin and reduce them to
per-target/horizon ensemble statistics. Results are appended to `cache_path`
after each origin, and any origin already present in the cache is skipped, so
an interrupted run resumes instead of restarting. Failed paths are counted and
never resampled.
"""
function simulate_abm_ensembles(
        variant::ABMVariant,
        origins::Vector{Tuple{Int, String}};
        paths::Int,
        cache_path::AbstractString,
        diagnostics_path::AbstractString,
        calibration_path::AbstractString = CALIBRATION_OBJECT_PATH,
        path_failures_path::Union{Nothing, AbstractString} = nothing,
        progress::Bool = true,
    )
    summaries = read_struct_csv(cache_path, EnsembleSummary)
    diagnostics = read_struct_csv(diagnostics_path, ABMOriginDiagnostic)
    completed = Set(
        row.origin_index for row in diagnostics if row.variant == variant.name
    )
    summaries = filter(
        row -> row.variant == variant.name && row.origin_index in completed,
        summaries,
    )
    diagnostics =
        filter(row -> row.variant == variant.name, diagnostics)
    path_failures = String[]

    pending = [entry for entry in origins if !(entry[1] in completed)]
    if isempty(pending)
        progress && println(
            "  all $(length(origins)) origins already cached for variant $(variant.name)",
        )
        return (; summaries, diagnostics, path_failures)
    end
    progress && println(
        "  simulating $(length(pending)) of $(length(origins)) origins " *
            "($(length(completed)) resumed from cache), $(paths) paths each",
    )

    calibration_object =
        JLD2.load(calibration_path)["calibration_object"]
    started_all = time()
    for (origin_index, origin_period) in pending
        build_period = shift_period(origin_period, -variant.burn_in_quarters)
        calibration_date = period_to_quarter_end(build_period)
        started = time()
        parameters, initial_conditions =
            abm_origin_inputs(calibration_object, calibration_date)
        calibration_seconds = time() - started

        quarters = SIMULATION_HORIZON + variant.burn_in_quarters
        started = time()
        simulated = SimulatedPath[]
        failed = 0
        for path in 1:paths
            seed = path_seed(seed_stream_name(variant.name), origin_period, path)
            try
                candidate = simulate_path(
                    parameters,
                    initial_conditions,
                    quarters,
                    seed,
                )
                if path_is_usable(candidate)
                    push!(simulated, candidate)
                else
                    failed += 1
                    push!(
                        path_failures,
                        "$(variant.name) $origin_period path $path seed $seed: non_finite_or_nonpositive_path",
                    )
                end
            catch exception
                failed += 1
                push!(
                    path_failures,
                    "$(variant.name) $origin_period path $path seed $seed: " *
                        first(split(sprint(showerror, exception), "\n")),
                )
            end
        end
        simulation_seconds = time() - started

        diagnostic = ABMOriginDiagnostic(
            variant.name,
            origin_index,
            String(origin_period),
            build_period,
            string(Date(calibration_date)),
            variant.burn_in_quarters,
            quarters,
            Int(parameters["T_prime"]),
            Int(parameters["T_max"]),
            paths,
            length(simulated),
            failed,
            calibration_seconds,
            simulation_seconds,
        )
        origin_summaries = isempty(simulated) ? EnsembleSummary[] :
            summarize_ensemble(variant, origin_index, origin_period, simulated)

        append_struct_csv(cache_path, origin_summaries, EnsembleSummary)
        append_struct_csv(diagnostics_path, [diagnostic], ABMOriginDiagnostic)
        append!(summaries, origin_summaries)
        push!(diagnostics, diagnostic)
        if path_failures_path !== nothing && !isempty(path_failures)
            open(path_failures_path, "a") do io
                for message in path_failures
                    println(io, message)
                end
            end
            empty!(path_failures)
        end

        progress && println(
            "  origin $origin_period (index $origin_index): " *
                "calibration $(round(calibration_seconds, digits = 2))s " *
                "simulation $(round(simulation_seconds, digits = 2))s " *
                "paths $(length(simulated))/$paths " *
                "elapsed $(round(time() - started_all, digits = 1))s",
        )
    end
    sort!(diagnostics; by = row -> row.origin_index)
    sort!(
        summaries;
        by = row -> (row.origin_index, row.target_id, row.horizon),
    )
    return (; summaries, diagnostics, path_failures)
end

# ---------------------------------------------------------------------------
# cells, tracks and scores
# ---------------------------------------------------------------------------

"""
    abm_forecast_cells(panel, ensembles, variant)

Emit the thirteen-column `ForecastCell` schema for both ABM columns. The MASE
scale is recomputed from the panel exactly as the base diagnostic does, so the
scaled errors are comparable across models.
"""
function abm_forecast_cells(
        panel::QuarterlyPanel,
        ensembles::Vector{EnsembleSummary},
        variant::ABMVariant,
    )
    cells = ForecastCell[]
    scales_by_origin = Dict{Int, Vector{Float64}}()
    for row in ensembles
        row.horizon in BASE.HORIZONS || continue
        target_index = row.origin_index + row.horizon
        target_index <= length(panel.periods) || continue
        row.paths_used > 0 || continue
        column = target_column(panel, row.target_id)
        scales = get!(scales_by_origin, row.origin_index) do
            BASE.mase_scales(panel.values[1:(row.origin_index), :])
        end
        actual = panel.values[target_index, column]
        for (model_id, point) in (
                (variant.mean_model_id, row.ensemble_mean),
                (variant.median_model_id, row.ensemble_median),
            )
            error = point - actual
            push!(
                cells,
                ForecastCell(
                    model_id,
                    row.origin_index,
                    row.origin_period,
                    panel.periods[target_index],
                    row.target_id,
                    row.horizon,
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
    return cells
end

function comparison_relative_scores(summaries, model_ids, benchmark_model_id)
    by_key = Dict(
        (row.sample_track, row.model_id, row.target_id, row.horizon) => row
        for row in summaries
    )
    relative = RelativeScore[]
    for track in TRACKS
        for model in model_ids
            for target in ABM_TARGET_IDS
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
                            "ABM comparison samples are not matched for $key",
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
    all_model_failure_count = length(failures)
    output = ABMWeightedScore[]
    for track in TRACKS
        for (set_name, target_ids) in SCORED_TARGET_SETS
            target_weight = 1.0 / length(target_ids)
            expected_cells = length(target_ids) * length(BASE.HORIZONS)
            for model in model_ids
                selected = filter(
                    row ->
                    row.sample_track == track &&
                        row.model_id == model &&
                        row.target_id in target_ids,
                    relative,
                )
                selected_cells =
                    Set((row.target_id, row.horizon) for row in selected)
                complete =
                    length(selected) == expected_cells &&
                    length(selected_cells) == expected_cells
                total_weight = sum(
                    target_weight * BASE.HORIZON_WEIGHTS[row.horizon]
                    for row in selected;
                    init = 0.0,
                )
                observation_counts = getfield.(selected, :observation_count)
                minimum_count = isempty(observation_counts) ? -1 :
                    minimum(observation_counts)
                maximum_count = isempty(observation_counts) ? -1 :
                    maximum(observation_counts)
                model_failure_count =
                    count(failure -> failure.model_id == model, failures)
                failure_free = all_model_failure_count == 0
                if complete && total_weight ≈ 1.0 && failure_free
                    weighted_rmse = sum(
                        target_weight *
                            BASE.HORIZON_WEIGHTS[row.horizon] *
                            row.rmse_ratio for row in selected;
                        init = 0.0,
                    )
                    weighted_mae = sum(
                        target_weight *
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
                    ABMWeightedScore(
                        track,
                        set_name,
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
    end
    return output
end

function monte_carlo_errors(
        panel::QuarterlyPanel,
        ensembles::Vector{EnsembleSummary},
        paths::Int,
    )
    output = MonteCarloError[]
    for target_id in ABM_TARGET_IDS
        for horizon in BASE.HORIZONS
            selected = filter(
                row ->
                row.target_id == target_id &&
                    row.horizon == horizon &&
                    row.paths_used > 1 &&
                    row.origin_index + row.horizon <= length(panel.periods),
                ensembles,
            )
            isempty(selected) && continue
            dispersions = getfield.(selected, :ensemble_sd)
            standard_errors =
                getfield.(selected, :monte_carlo_standard_error)
            push!(
                output,
                MonteCarloError(
                    "beforeit_abm_us_v1",
                    target_id,
                    horizon,
                    length(selected),
                    paths,
                    mean(dispersions),
                    mean(standard_errors),
                    maximum(standard_errors),
                ),
            )
        end
    end
    return output
end

"""
    run_abm_comparison(panel, ensembles, diagnostics, variant; paths)

Merge the ABM ensemble columns into the ten-model statistical diagnostic and
score them on cells common to every model. This is a revised/mixed-vintage
research diagnostic: it is not a real-time forecast, an admitted origin, or
promotion evidence.
"""
function run_abm_comparison(
        panel::QuarterlyPanel,
        ensembles::Vector{EnsembleSummary},
        diagnostics::Vector{ABMOriginDiagnostic},
        variant::ABMVariant;
        paths::Int,
        extra_columns::Vector{Tuple{ABMVariant, Vector{EnsembleSummary}}} =
            Tuple{ABMVariant, Vector{EnsembleSummary}}[],
    )
    BASE.validate_panel(panel)
    base_result = BASE.run_revised_benchmark_diagnostic(panel)

    forecast_cells = filter(
        row -> row.target_id in ABM_TARGET_IDS,
        base_result.forecast_cells,
    )
    append!(forecast_cells, abm_forecast_cells(panel, ensembles, variant))
    # Additional ABM columns (e.g. the v1 baseline alongside v2) are scored on exactly
    # the same common cells, so the side-by-side delta cannot be a sample artifact.
    for (extra_variant, extra_ensembles) in extra_columns
        append!(
            forecast_cells,
            abm_forecast_cells(panel, extra_ensembles, extra_variant),
        )
    end

    failures = copy(base_result.failures)
    for diagnostic in diagnostics
        diagnostic.paths_used > 0 && continue
        for model_id in (variant.mean_model_id, variant.median_model_id)
            push!(
                failures,
                DiagnosticFailure(
                    model_id,
                    diagnostic.origin_index,
                    diagnostic.origin_period,
                    SIMULATION_HORIZON,
                    "abm_origin_without_usable_paths",
                    "ABMEnsembleFailure",
                    "every simulated path at this origin was unusable",
                ),
            )
        end
    end

    model_ids =
        [base_result.model_ids; variant.mean_model_id; variant.median_model_id]
    for (extra_variant, _) in extra_columns
        push!(model_ids, extra_variant.mean_model_id)
        push!(model_ids, extra_variant.median_model_id)
    end
    common_keys = BASE.common_cell_keys(forecast_cells, model_ids)
    common_rows =
        filter(row -> BASE.cell_key(row) in common_keys, forecast_cells)
    balanced_last_origin = length(panel.periods) - BASE.MAXIMUM_HORIZON
    balanced_rows =
        filter(row -> row.origin_index <= balanced_last_origin, common_rows)
    pandemic_masked_rows = filter(
        row -> !is_acute_pandemic_target(row.target_period),
        common_rows,
    )

    summaries = vcat(
        BASE.summarize_rows(
            ALL_AVAILABLE_TRACK,
            common_rows,
            model_ids,
            ABM_TARGET_IDS,
        ),
        BASE.summarize_rows(
            BALANCED_H12_TRACK,
            balanced_rows,
            model_ids,
            ABM_TARGET_IDS,
        ),
        BASE.summarize_rows(
            PANDEMIC_MASKED_TRACK,
            pandemic_masked_rows,
            model_ids,
            ABM_TARGET_IDS,
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

    return ABMComparisonResult(
        CONTRACT_ID,
        variant.name,
        panel.information_track,
        panel.panel_sha256,
        panel.manifest_sha256,
        panel.source_receipts_sha256,
        copy(panel.periods),
        copy(ABM_TARGET_IDS),
        model_ids,
        copy(BASE.HORIZONS),
        paths,
        variant.burn_in_quarters,
        SIMULATION_HORIZON + variant.burn_in_quarters,
        forecast_cells,
        failures,
        diagnostics,
        ensembles,
        summaries,
        relative,
        weighted,
        monte_carlo_errors(panel, ensembles, paths),
        base_result.benchmark_model_id,
        variant.mean_model_id,
        variant.median_model_id,
        sum(getfield.(diagnostics, :paths_failed); init = 0),
    )
end

# ---------------------------------------------------------------------------
# CSV helpers
# ---------------------------------------------------------------------------

function append_struct_csv(path, rows, ::Type{T}) where {T}
    headers = fieldnames(T)
    isfile(path) || open(path, "w") do io
        println(io, join(String.(headers), ","))
    end
    isempty(rows) && return path
    open(path, "a") do io
        for row in rows
            println(
                io,
                join(
                    (
                        BASE.csv_escape(getfield(row, field)) for
                            field in headers
                    ),
                    ",",
                ),
            )
        end
    end
    return path
end

parse_csv_field(::Type{String}, text) = String(text)
parse_csv_field(::Type{Int}, text) = parse(Int, text)
parse_csv_field(::Type{Float64}, text) = parse(Float64, text)
parse_csv_field(::Type{Bool}, text) = parse(Bool, text)

function read_struct_csv(path, ::Type{T}) where {T}
    rows = T[]
    isfile(path) || return rows
    lines = readlines(path)
    isempty(lines) && return rows
    headers = collect(String.(fieldnames(T)))
    String.(split(lines[1], ',')) == headers ||
        throw(ArgumentError("cache $path has an unexpected header"))
    types = fieldtypes(T)
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ',')
        length(fields) == length(headers) ||
            throw(ArgumentError("cache $path has a malformed row"))
        push!(
            rows,
            T(
                (
                    parse_csv_field(types[index], fields[index]) for
                        index in eachindex(headers)
                )...,
            ),
        )
    end
    return rows
end

# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------

toml_string(value) = repr(String(value))
toml_string_array(values) = "[" * join(toml_string.(values), ", ") * "]"

function repository_commit()
    try
        return readchomp(
            `git -C $(REPOSITORY_ROOT) rev-parse HEAD`,
        )
    catch
        return "unavailable"
    end
end

function repository_tree_clean()
    try
        return isempty(
            readchomp(`git -C $(REPOSITORY_ROOT) status --porcelain`),
        )
    catch
        return false
    end
end

function track_observation_counts(result::ABMComparisonResult, track)
    counts = Int[]
    for horizon in result.horizons
        selected = filter(
            row ->
            row.sample_track == track &&
                row.model_id == result.abm_mean_model_id &&
                row.target_id == first(result.target_ids) &&
                row.horizon == horizon,
            result.summaries,
        )
        push!(counts, isempty(selected) ? -1 : only(selected).observation_count)
    end
    return counts
end

function weighted_score(result::ABMComparisonResult, track, target_set, model_id)
    matches = filter(
        row ->
        row.sample_track == track &&
            row.target_set == target_set &&
            row.model_id == model_id,
        result.weighted_relative_scores,
    )
    return isempty(matches) ? nothing : only(matches)
end

function write_manifest(path, result::ABMComparisonResult, output_hashes)
    all_available_counts =
        track_observation_counts(result, ALL_AVAILABLE_TRACK)
    balanced_counts = track_observation_counts(result, BALANCED_H12_TRACK)
    pandemic_counts = track_observation_counts(result, PANDEMIC_MASKED_TRACK)
    lines = [
        "schema_version = \"beforeit-us-revised-data-abm-comparison-result.v1\"",
        "contract_id = \"$(result.contract_id)\"",
        "variant = \"$(result.variant)\"",
        "information_track = \"$(result.information_track)\"",
        "real_time = false",
        "origin_admissible = false",
        "promotion_eligible = false",
        "production_accuracy_score = false",
        "paper_parity_claimed = false",
        "abm_forecast_included = true",
        "mixed_vintage_structural_year = $MIXED_VINTAGE_STRUCTURAL_YEAR",
        "mixed_vintage_annual_structure_is_future_information_at_historical_origins = true",
        "h1_opening_row_transient = true",
        "monte_carlo_paths = $(result.monte_carlo_paths)",
        "mc_standard_error_reported = true",
        "burn_in_quarters = $(result.burn_in_quarters)",
        "simulated_quarters = $(result.simulated_quarters)",
        "model_scale = $(repr(MODEL_SCALE))",
        "ensemble_functional = \"pathwise_transform_then_ensemble_mean_and_median\"",
        "parallel_simulation = false",
        "resampling_of_failed_paths = false",
        "panel_sha256 = \"$(result.panel_sha256)\"",
        "panel_manifest_sha256 = \"$(result.panel_manifest_sha256)\"",
        "panel_source_receipts_sha256 = \"$(result.panel_source_receipts_sha256)\"",
        "start_period = \"$(first(result.periods))\"",
        "end_period = \"$(last(result.periods))\"",
        "comparison_target_count = $(length(result.target_ids))",
        "comparison_target_ids = $(toml_string_array(result.target_ids))",
        "headline_scored_target_ids = $(toml_string_array(HEADLINE_TARGET_IDS))",
        "secondary_scored_target_ids = $(toml_string_array(SECONDARY_TARGET_IDS))",
        "unscored_appendix_target_ids = $(toml_string_array(UNSCORED_APPENDIX_TARGET_IDS))",
        "unemployment_rate_excluded_from_weighted_scores = true",
        "unemployment_rate_exclusion_reason = \"initial unemployed stock is a length-one annual array frozen at 2024, so every historical origin opens at the 2024 labour market\"",
        "model_count = $(length(result.model_ids))",
        "model_ids = $(toml_string_array(result.model_ids))",
        "benchmark_model_id = \"$(result.benchmark_model_id)\"",
        "abm_mean_model_id = \"$(result.abm_mean_model_id)\"",
        "abm_median_model_id = \"$(result.abm_median_model_id)\"",
        "horizons = [$(join(result.horizons, ", "))]",
        "horizon_weights = [$(join((BASE.HORIZON_WEIGHTS[horizon] for horizon in result.horizons), ", "))]",
        "all_available_track = \"$ALL_AVAILABLE_TRACK\"",
        "balanced_h12_track = \"$BALANCED_H12_TRACK\"",
        "pandemic_masked_track = \"$PANDEMIC_MASKED_TRACK\"",
        "pandemic_mask_rule = \"exclude cells whose TARGET period falls in $ACUTE_PANDEMIC_FIRST_TARGET_PERIOD..$ACUTE_PANDEMIC_LAST_TARGET_PERIOD (frozen PT_ACUTE window); the masked track is PT_PRE plus PT_POST\"",
        "all_available_common_observation_counts = [$(join(all_available_counts, ", "))]",
        "balanced_h12_common_observation_counts = [$(join(balanced_counts, ", "))]",
        "pandemic_masked_common_observation_counts = [$(join(pandemic_counts, ", "))]",
        "forecast_cell_count = $(length(result.forecast_cells))",
        "failure_count = $(length(result.failures))",
        "failure_free = $(isempty(result.failures))",
        "abm_origin_count = $(length(result.abm_origin_diagnostics))",
        "abm_path_failure_count = $(result.abm_path_failure_count)",
        "abm_origin_indices = [$(join(getfield.(result.abm_origin_diagnostics, :origin_index), ", "))]",
        "abm_origin_failed_path_counts = [$(join(getfield.(result.abm_origin_diagnostics, :paths_failed), ", "))]",
        "abm_origin_used_path_counts = [$(join(getfield.(result.abm_origin_diagnostics, :paths_used), ", "))]",
        "score_summary_count = $(length(result.summaries))",
        "relative_score_count = $(length(result.relative_scores))",
        "weighted_relative_score_count = $(length(result.weighted_relative_scores))",
        "monte_carlo_error_row_count = $(length(result.monte_carlo_errors))",
        "minimum_training_quarters = $(BASE.MINIMUM_TRAINING_QUARTERS)",
        "error_sign = \"$(BASE.ERROR_SIGN)\"",
        "truth_vintage = \"revised_mixed_vintage_snapshot\"",
        "weighted_ratio_formula = \"$(BASE.WEIGHTED_RATIO_FORMULA)\"",
        "weighted_ratio_semantics = \"$(BASE.WEIGHTED_RATIO_SEMANTICS)\"",
        "sample_policy = \"common target-horizon-origin score cells across the ten statistical models and both ABM columns; all-available, balanced-h12 and pandemic-masked reported separately\"",
        "known_comparability_limit = \"statistical models use the registered eight-target panel; the ABM is a structural simulator initialised from its own calibration artifact and shares only the score panel\"",
        "code_commit_sha = \"$(repository_commit())\"",
        "code_working_tree_clean = $(repository_tree_clean())",
        "comparison_code_sha256 = \"$(sha256_hex(read(abspath(@__FILE__))))\"",
        "base_diagnostic_code_sha256 = \"$(sha256_hex(read(BASE_DIAGNOSTIC_PATH)))\"",
        calibration_provenance_lines()...,
        "julia_project_sha256 = \"$(sha256_hex(read(BASE.PROJECT_PATH)))\"",
        "julia_version = \"$(VERSION)\"",
        "blas_threads = $(BLAS.get_num_threads())",
        "julia_threads = $(Threads.nthreads())",
    ]
    for (track, label) in (
            (ALL_AVAILABLE_TRACK, "all_available"),
            (BALANCED_H12_TRACK, "balanced_h12"),
            (PANDEMIC_MASKED_TRACK, "pandemic_masked"),
        )
        for (set_name, _) in SCORED_TARGET_SETS
            for (model_id, model_label) in (
                    (result.abm_mean_model_id, "abm_mean"),
                    (result.abm_median_model_id, "abm_median"),
                )
                score = weighted_score(result, track, set_name, model_id)
                score === nothing && continue
                prefix = "$(model_label)_$(label)_$(set_name)"
                push!(lines, "$(prefix)_status = \"$(score.status)\"")
                push!(
                    lines,
                    "$(prefix)_weighted_rmse_ratio = $(repr(score.weighted_macro_average_cellwise_rmse_ratio))",
                )
                push!(
                    lines,
                    "$(prefix)_weighted_mae_ratio = $(repr(score.weighted_macro_average_cellwise_mae_ratio))",
                )
            end
        end
    end
    for (key, value) in sort!(collect(output_hashes); by = first)
        push!(lines, "$(key)_sha256 = \"$value\"")
    end
    write(path, join(lines, "\n") * "\n")
    return path
end

"""
    write_abm_comparison(result, output_directory)

Write the ABM comparison tables and manifest.
"""
function write_abm_comparison(
        result::ABMComparisonResult,
        output_directory::AbstractString,
    )
    mkpath(output_directory)
    paths = Dict(
        "forecast_cells" => joinpath(output_directory, "forecast_cells.csv"),
        "failures" => joinpath(output_directory, "failures.csv"),
        "abm_origin_diagnostics" =>
            joinpath(output_directory, "abm_origin_diagnostics.csv"),
        "abm_ensemble_summaries" =>
            joinpath(output_directory, "abm_ensemble_summaries.csv"),
        "score_summaries" =>
            joinpath(output_directory, "score_summaries.csv"),
        "relative_scores" =>
            joinpath(output_directory, "relative_scores.csv"),
        "weighted_relative_scores" =>
            joinpath(output_directory, "weighted_relative_scores.csv"),
        "monte_carlo_errors" =>
            joinpath(output_directory, "monte_carlo_errors.csv"),
    )
    BASE.write_struct_csv(
        paths["forecast_cells"],
        result.forecast_cells,
        ForecastCell,
    )
    BASE.write_struct_csv(paths["failures"], result.failures, DiagnosticFailure)
    BASE.write_struct_csv(
        paths["abm_origin_diagnostics"],
        result.abm_origin_diagnostics,
        ABMOriginDiagnostic,
    )
    BASE.write_struct_csv(
        paths["abm_ensemble_summaries"],
        result.ensemble_summaries,
        EnsembleSummary,
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
        ABMWeightedScore,
    )
    BASE.write_struct_csv(
        paths["monte_carlo_errors"],
        result.monte_carlo_errors,
        MonteCarloError,
    )
    hashes = Dict(name => sha256_hex(read(path)) for (name, path) in paths)
    manifest_path = joinpath(output_directory, "manifest.toml")
    write_manifest(manifest_path, result, hashes)
    hashes["manifest"] = sha256_hex(read(manifest_path))
    return (; paths, manifest_path, hashes)
end

"""
    write_abm_outlook(ensembles, diagnostics, output_directory; paths)

Write the unscored forward-looking ensemble table. These origins lie beyond the
end of the revised panel, so no realized truth exists and nothing here is
scored.
"""
function write_abm_outlook(
        ensembles::Vector{EnsembleSummary},
        diagnostics::Vector{ABMOriginDiagnostic},
        output_directory::AbstractString;
        paths::Int,
    )
    mkpath(output_directory)
    outlook_path = joinpath(output_directory, "current_outlook.csv")
    diagnostics_path =
        joinpath(output_directory, "abm_origin_diagnostics.csv")
    BASE.write_struct_csv(outlook_path, ensembles, EnsembleSummary)
    BASE.write_struct_csv(
        diagnostics_path,
        diagnostics,
        ABMOriginDiagnostic,
    )
    lines = [
        "schema_version = \"beforeit-us-revised-data-abm-outlook.v1\"",
        "contract_id = \"$CONTRACT_ID\"",
        "variant = \"outlook\"",
        "information_track = \"$INFORMATION_TRACK\"",
        "scored = false",
        "realized_truth_available = false",
        "real_time = false",
        "origin_admissible = false",
        "promotion_eligible = false",
        "abm_forecast_included = true",
        "mixed_vintage_structural_year = $MIXED_VINTAGE_STRUCTURAL_YEAR",
        "h1_opening_row_transient = true",
        "monte_carlo_paths = $paths",
        "mc_standard_error_reported = true",
        "model_scale = $(repr(MODEL_SCALE))",
        "ensemble_functional = \"pathwise_transform_then_ensemble_mean_and_median\"",
        "origin_periods = $(toml_string_array(unique(getfield.(diagnostics, :origin_period))))",
        "target_ids = $(toml_string_array(ABM_TARGET_IDS))",
        "horizons = [$(join(1:SIMULATION_HORIZON, ", "))]",
        "abm_origin_failed_path_counts = [$(join(getfield.(diagnostics, :paths_failed), ", "))]",
        "abm_origin_used_path_counts = [$(join(getfield.(diagnostics, :paths_used), ", "))]",
        "code_commit_sha = \"$(repository_commit())\"",
        "comparison_code_sha256 = \"$(sha256_hex(read(abspath(@__FILE__))))\"",
        calibration_provenance_lines()...,
        "julia_version = \"$(VERSION)\"",
        "current_outlook_sha256 = \"$(sha256_hex(read(outlook_path)))\"",
    ]
    manifest_path = joinpath(output_directory, "manifest.toml")
    write(manifest_path, join(lines, "\n") * "\n")
    return (; outlook_path, diagnostics_path, manifest_path)
end

end
