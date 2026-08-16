# Numerical forecast kernel for the U.S. ABM comparison.
#
# Everything in this file determines the CONTENT of an ensemble cache: the model
# scale and horizon, the scored target list, the seed derivation, the calibration
# inputs at an origin, the simulation of a single path, and the ensemble
# statistics written per origin. A change to any of it can move a forecast
# number, so `numerical_kernel_sha256` seals this file and is compared on every
# run -- migrated identity or not -- alongside the model runtime tree and the
# package environment.
#
# What deliberately stays in USRevisedDataABMComparison.jl is the cache harness
# and the reporting layer: which origins to run, how rows are resumed, pruned and
# persisted, how scores and manifests are derived from an existing cache. Those
# cannot change a cached forecast, and they are the only things a migration
# attestation covers.
#
# The two numerical decisions the harness still makes are both expressed in terms
# defined here, so they are inside the seal: the per-path seed is
# `path_seed(seed_stream_name(variant), origin_period, path)`, and the number of
# quarters simulated is `SIMULATION_HORIZON + variant.burn_in_quarters`.
#
# This file was created by a PURE MOVE. Verify with:
#   git show --color-moved=zebra <extraction commit>


const MODEL_SCALE = 1.0e-5
const SIMULATION_HORIZON = 12
const EXOGENOUS_TRUNCATION_KEYS = ("C_G", "C_E", "Y_I")


const ABM_TARGET_IDS = [
    "real_gdp",
    "gdp_deflator",
    "nominal_gdp",
    "unemployment_rate",
    "effective_federal_funds_rate",
]


# Every origin writes exactly one row per (horizon, target). A cache holding a
# different count for an origin was interrupted between the ensemble append and
# the diagnostics append, and must not be resumed as if it were whole.
const ENSEMBLE_ROWS_PER_ORIGIN = SIMULATION_HORIZON * length(ABM_TARGET_IDS)

# The exact (target, horizon) grid every origin must carry.
const EXPECTED_FORECAST_GRID = Set(
    (target_id, horizon)
        for target_id in ABM_TARGET_IDS, horizon in 1:SIMULATION_HORIZON
)


# v2 draws the SAME seed stream as its v1 counterpart, so the v1 -> v2 delta is a
# matched-seed contrast and not a Monte-Carlo artifact. Only the cache key differs.
const SEED_STREAM_ALIASES =
    Dict("headline_v2" => "headline", "outlook_v2" => "outlook")
seed_stream_name(name::AbstractString) = get(SEED_STREAM_ALIASES, name, String(name))


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
    hash(
        (
            :beforeit_us_abm_revised_comparison_v1,
            variant_name,
            origin_period,
            path,
        )
    ) % 0x40000000,
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
                    quantile(values, 0.1),
                    quantile(values, 0.25),
                    quantile(values, 0.75),
                    quantile(values, 0.9),
                    quantile(values, 0.95),
                ),
            )
        end
    end
    return summaries
end

"""
    generate_origin_ensemble(variant, origin_index, origin_period, paths, calibration_path)

The COMPLETE per-origin numerical generation operation: origin date derivation,
calibration inputs, simulated-quarter selection, the path loop with its seed call
arguments, the path acceptance policy, and the ensemble summarisation. Returns
the summarised rows, the origin diagnostic, and any path-failure messages.

This lives in the sealed kernel because calling a sealed function does not seal
its arguments or the control flow around it: with the loop in the harness,
changing `path` to `path + 1` at the seed call site moved every forecast number
while only comparison_code_sha256 changed -- a field a migrated identity skips.
The boundary is now explicit: everything that can move a number lives in an
always-hashed file, and the harness may only validate, resume, repair, persist
and report.
"""
function generate_origin_ensemble(
        variant::ABMVariant,
        origin_index::Int,
        origin_period::AbstractString,
        paths::Int,
        calibration_path::AbstractString,
    )
    path_failures = String[]
    calibration_object = load_calibration_object(calibration_path)
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
    return (; summaries = origin_summaries, diagnostic, path_failures)
end

# ---------------------------------------------------------------------------
# Self-contained period arithmetic.
#
# The generator derives its calibration date from the origin identifier, so the
# arithmetic that does it must be sealed too: with these defined in the harness,
# changing `+ offset` to `+ offset + 1` handed the kernel a different calibration
# date -- every forecast number moved while the kernel digest did not.
#
# kernel_quarter_ordinal exists so the kernel has no dependency on the base
# diagnostic's quarter_ordinal, whose hash a migrated identity skips. It is the
# same function (4*year + quarter); duplicating four lines is the price of a
# closed seal, and the equivalence is asserted in the test suite.
# ---------------------------------------------------------------------------

function kernel_quarter_ordinal(period)
    matched = match(r"^([1-9][0-9]{3})Q([1-4])$", String(period))
    matched === nothing &&
        throw(ArgumentError("invalid quarterly period $(repr(period))"))
    year = parse(Int, matched.captures[1])
    quarter = parse(Int, matched.captures[2])
    return 4year + quarter
end

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
    ordinal = kernel_quarter_ordinal(period) + offset
    calendar_year = div(ordinal - 1, 4)
    quarter = ordinal - 4 * calendar_year
    return string(calendar_year, "Q", quarter)
end

"""
    load_calibration_object(path)

Load the calibration artifact the generator initialises from.

Sealed because selection and loading of the input data can change every forecast
number as surely as the simulation can. The generator takes a PATH, not a loaded
object, so the harness has no opportunity to transform the calibration between
loading it and handing it over. Repeated loads of the same path are memoised;
the cache is keyed by the absolute path and holds the object JLD2 returned.
"""
const CALIBRATION_OBJECT_CACHE = Dict{String, Any}()

function load_calibration_object(path::AbstractString)
    key = abspath(path)
    return get!(CALIBRATION_OBJECT_CACHE, key) do
        JLD2.load(key)["calibration_object"]
    end
end
