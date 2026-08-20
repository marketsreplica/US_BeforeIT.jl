# ---------------------------------------------------------------------------
# Stage-2b DSGE scored columns (workstream 2b-1)
#
# Two equilibrium forecast columns for the revised-data comparison:
#
#   dsge_small_nk : the validated An–Schorfheide-type small NK gensys module,
#                   re-estimated at every origin by posterior mode (MAP) on the
#                   origin-bounded panel columns
#                   [real_gdp, gdp_deflator, effective_federal_funds_rate].
#   dsge_sw07     : the Smets–Wouters (AER 2007) medium-scale model,
#                   re-estimated at every origin by posterior mode on seven
#                   observables (output, consumption, investment and wage
#                   growth, hours, GDP-deflator inflation, federal funds rate)
#                   built from a fixed-provenance FRED retrieval spliced with
#                   the frozen panel where the panel covers the series.
#
# Estimation is Kalman-filter likelihood + frozen priors; the optimizer is the
# deterministic fixed-budget Nelder–Mead in estimation_kernel.jl. No forecast
# error enters any objective (calibration firewall). Predictive densities are
# simulated from the filtered terminal state plus future structural shocks at
# the mode; parameter uncertainty is NOT propagated, and that limitation is
# recorded in the model card.
#
# Per-origin estimation/solution status is recorded for every origin; on an
# estimation failure the previous origin's mode is carried forward and the
# carry is recorded. No origin is silently dropped.
#
# `unemployment_rate` cells come from an auxiliary per-origin Okun bridge
# (OLS of the quarterly unemployment change on annualized real growth),
# iterated over the simulated growth paths. This is a labeled auxiliary
# equation outside both DSGE cores, present so the equilibrium columns cover
# the same five-target cell grid as the ABM and statistical columns.
# ---------------------------------------------------------------------------

module USDSGEColumns

using LinearAlgebra
using Random
using SHA
using Statistics

export SMALL_NK_COLUMN, SW07_COLUMN, DSGEColumnResult, DSGEOriginStatus,
    DSGEEnsembleRow, generate_dsge_column, small_nk_estimate, sw07_estimate,
    sw07_load_panel, okun_bridge, quarter_add, SMALL_NK_SEED_BASE, SW07_SEED_BASE

const MODULE_DIR = @__DIR__
const SMALL_NK_MODULE_PATH = normpath(
    joinpath(MODULE_DIR, "..", "small_nk_dsge", "USSmallNKDSGEMechanics.jl"),
)
const SMALL_NK_MODULE_SHA256 =
    "2750a95581ba83bdac8578ccdc2cd290a265fa1968d74ddc3d10cfc56e26248a"

function _verified_read(path::AbstractString, expected_sha::AbstractString)
    content = read(path)
    digest = bytes2hex(SHA.sha256(content))
    digest == expected_sha || error(
        "hash mismatch for $path: expected $expected_sha observed $digest",
    )
    return path
end

include(_verified_read(SMALL_NK_MODULE_PATH, SMALL_NK_MODULE_SHA256))
const NK = USSmallNKDSGEMechanics

include(joinpath(MODULE_DIR, "estimation_kernel.jl"))
include(joinpath(MODULE_DIR, "sw07_model.jl"))

# --- column identities ------------------------------------------------------

const SMALL_NK_COLUMN = "dsge_small_nk"
const SW07_COLUMN = "dsge_sw07"
const DSGE_TARGET_IDS = [
    "real_gdp", "gdp_deflator", "nominal_gdp", "unemployment_rate",
    "effective_federal_funds_rate",
]
const FORECAST_HORIZON = 12
const PREDICTIVE_PATHS = 500
# Version-independent deterministic seed bases (documented in the model card;
# the sealed path RNG domain-separates from the seed by SHA-256).
const SMALL_NK_SEED_BASE = 7_000_000
const SW07_SEED_BASE = 8_000_000
const SW07_ESTIMATION_START = "1966Q1"     # Smets–Wouters sample convention
const EFFR_LOWER_BOUND = 0.0               # naive ZLB truncation, documented

# --- small structs mirrored on the comparison module's CSV schemas ----------

struct DSGEEnsembleRow
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

struct DSGEOriginStatus
    variant::String
    origin_index::Int
    origin_period::String
    training_observations::Int
    estimation_status::String   # converged | budget_exhausted | carried_forward | fixed_fallback
    determinate::Bool
    eu_existence::Int
    eu_uniqueness::Int
    loglikelihood::Float64
    log_posterior::Float64
    function_evaluations::Int
    okun_intercept::Float64
    okun_slope::Float64
    okun_sigma::Float64
    auxiliary_growth_projection::Float64   # SW07 population-growth add-back; 0 for small NK
    seconds::Float64
end

struct DSGEColumnResult
    column::String
    rows::Vector{DSGEEnsembleRow}
    statuses::Vector{DSGEOriginStatus}
    parameter_modes::Vector{Tuple{Int, String, Float64}}  # origin_index, name, value
    draws::Dict{Tuple{Int, String, Int}, Vector{Float64}} # (origin, target, horizon) -> draws
end

# --- quarter arithmetic -----------------------------------------------------

function quarter_add(period::AbstractString, quarters::Int)
    year = parse(Int, period[1:4])
    quarter = parse(Int, period[6:6])
    total = year * 4 + (quarter - 1) + quarters
    return string(div(total, 4), "Q", mod(total, 4) + 1)
end

# --- Okun bridge ------------------------------------------------------------

"""
    okun_bridge(growth, unemployment) -> (intercept, slope, sigma)

OLS of the quarterly change in the unemployment rate on annualized real GDP
growth over the training window. Auxiliary equation only; estimated fresh at
every origin from origin-bounded data.
"""
function okun_bridge(growth::Vector{Float64}, unemployment::Vector{Float64})
    n = length(growth)
    n == length(unemployment) || throw(ArgumentError("okun inputs must align"))
    n >= 20 || throw(ArgumentError("okun bridge needs at least 20 observations"))
    du = diff(unemployment)
    g = growth[2:end]
    X = hcat(ones(length(g)), g)
    beta = X \ du
    residuals = du - X * beta
    sigma = sqrt(sum(abs2, residuals) / max(length(du) - 2, 1))
    return beta[1], beta[2], sigma
end

function simulate_unemployment_paths(
        rng::AbstractRNG,
        growth_paths::Matrix{Float64},      # horizon x paths (annualized pp)
        u0::Float64,
        intercept::Float64,
        slope::Float64,
        sigma::Float64,
    )
    horizon, paths = size(growth_paths)
    u = Matrix{Float64}(undef, horizon, paths)
    for j in 1:paths
        level = u0
        for h in 1:horizon
            level = level + intercept + slope * growth_paths[h, j] +
                sigma * randn(rng)
            level = max(level, 0.0)
            u[h, j] = level
        end
    end
    return u
end

compose_nominal(real_ann::Float64, deflator_ann::Float64) =
    400.0 * ((1.0 + real_ann / 400.0) * (1.0 + deflator_ann / 400.0) - 1.0)

# --- small-NK estimation ----------------------------------------------------

# Parameter order matches the sealed SmallNKParameters fields.
const SMALL_NK_PARAMETER_NAMES = [
    "tau", "kappa", "psi1", "psi2", "r_annual", "pi_star", "gamma_quarterly",
    "rho_rate", "rho_g", "rho_z", "sigma_rate", "sigma_g", "sigma_z",
]

# Priors follow An–Schorfheide (2007, Table 2) with two documented
# modernizations: pi_star recentred to Gamma(4, 2) for the post-2000 panel
# (original Gamma(7, 2)), and psi1's prior support truncated above one by the
# determinacy region itself (indeterminate proposals are rejected by gensys).
const SMALL_NK_PRIORS = Dict(
    "tau" => PriorSpec(:gamma, 2.0, 0.5),
    "kappa" => PriorSpec(:gamma, 0.2, 0.1),
    "psi1" => PriorSpec(:gamma, 1.5, 0.25),
    "psi2" => PriorSpec(:gamma, 0.5, 0.25),
    "r_annual" => PriorSpec(:gamma, 0.5, 0.5),
    "pi_star" => PriorSpec(:gamma, 4.0, 2.0),
    "gamma_quarterly" => PriorSpec(:normal, 0.4, 0.2),
    "rho_rate" => PriorSpec(:beta, 0.5, 0.2),
    "rho_g" => PriorSpec(:beta, 0.8, 0.1),
    "rho_z" => PriorSpec(:beta, 0.66, 0.15),
    "sigma_rate" => PriorSpec(:invgamma1, 0.3, 4.0),
    "sigma_g" => PriorSpec(:invgamma1, 0.6, 4.0),
    "sigma_z" => PriorSpec(:invgamma1, 0.4, 4.0),
)

const SMALL_NK_TRANSFORMS = Dict(
    "tau" => ParameterTransform(:log, 0.0, 0.0),
    "kappa" => ParameterTransform(:logit, 1.0e-4, 0.9999),
    "psi1" => ParameterTransform(:log, 0.0, 0.0),
    "psi2" => ParameterTransform(:log, 0.0, 0.0),
    "r_annual" => ParameterTransform(:log, 0.0, 0.0),
    "pi_star" => ParameterTransform(:log, 0.0, 0.0),
    "gamma_quarterly" => ParameterTransform(:identity, 0.0, 0.0),
    "rho_rate" => ParameterTransform(:logit, 1.0e-4, 0.9999),
    "rho_g" => ParameterTransform(:logit, 1.0e-4, 0.9999),
    "rho_z" => ParameterTransform(:logit, 1.0e-4, 0.9999),
    "sigma_rate" => ParameterTransform(:log, 0.0, 0.0),
    "sigma_g" => ParameterTransform(:log, 0.0, 0.0),
    "sigma_z" => ParameterTransform(:log, 0.0, 0.0),
)

function small_nk_parameters_from_vector(values::Vector{Float64})
    return NK.SmallNKParameters(values...)
end

small_nk_vector(parameters) =
    Float64[getfield(parameters, Symbol(name)) for name in SMALL_NK_PARAMETER_NAMES]

function small_nk_log_posterior(observations::Matrix{Float64}, values::Vector{Float64})
    prior = 0.0
    for (i, name) in enumerate(SMALL_NK_PARAMETER_NAMES)
        contribution = log_prior_density(SMALL_NK_PRIORS[name], values[i])
        isfinite(contribution) || return -Inf
        prior += contribution
    end
    local loglik
    try
        parameters = small_nk_parameters_from_vector(values)
        system = NK.build_canonical_system(parameters)
        solution = NK.solve_gensys(system)
        measurement = NK.build_measurement_system(parameters)
        result = NK.filter_loglikelihood(observations, solution, measurement)
        loglik = result.loglikelihood
    catch
        return -Inf
    end
    return isfinite(loglik) ? loglik + prior : -Inf
end

"""
    small_nk_estimate(observations; start, max_evaluations) -> NamedTuple

Posterior-mode estimation of the 13 small-NK parameters on a T x 3 observation
matrix [real GDP growth, GDP-deflator inflation, EFFR], all in annualized
percent. Returns the mode, its likelihood/posterior values, convergence
information, and the solved system objects for forecasting.
"""
function small_nk_estimate(
        observations::Matrix{Float64};
        start::Union{Nothing, Vector{Float64}} = nothing,
        max_evaluations::Int = 3000,
    )
    start_values = isnothing(start) ?
        small_nk_vector(NK.adapted_mechanics_parameters()) : copy(start)
    transforms = [SMALL_NK_TRANSFORMS[name] for name in SMALL_NK_PARAMETER_NAMES]
    x0 = [to_unconstrained(transforms[i], start_values[i]) for i in 1:13]
    objective = x -> begin
        values = [to_domain(transforms[i], x[i]) for i in 1:13]
        small_nk_log_posterior(observations, values)
    end
    x_best, f_best, evaluations, converged =
        nelder_mead_maximize(objective, x0; max_evaluations = max_evaluations)
    mode = [to_domain(transforms[i], x_best[i]) for i in 1:13]
    isfinite(f_best) || return (;
        mode = start_values, log_posterior = -Inf, loglikelihood = -Inf,
        evaluations, converged = false, usable = false,
    )
    parameters = small_nk_parameters_from_vector(mode)
    system = NK.build_canonical_system(parameters)
    solution = NK.solve_gensys(system)
    measurement = NK.build_measurement_system(parameters)
    filtered = NK.filter_loglikelihood(observations, solution, measurement)
    return (;
        mode, log_posterior = f_best, loglikelihood = filtered.loglikelihood,
        evaluations, converged, usable = true,
        parameters, solution, measurement, filtered,
    )
end

# --- SW07 estimation --------------------------------------------------------

function sw07_theta(values::Vector{Float64})
    names = sw07_parameter_names()
    return Dict{String, Float64}(names[i] => values[i] for i in eachindex(names))
end

function sw07_transforms()
    transforms = ParameterTransform[]
    for row in SW07_ESTIMATED_PARAMETERS
        lower, upper = Float64(row[3]), Float64(row[4])
        push!(transforms, ParameterTransform(:logit, lower, upper))
    end
    return transforms
end

function sw07_log_prior(values::Vector{Float64})
    total = 0.0
    for (i, row) in enumerate(SW07_ESTIMATED_PARAMETERS)
        kind, a, b = row[5], Float64(row[6]), Float64(row[7])
        contribution = log_prior_density(PriorSpec(kind, a, b), values[i])
        isfinite(contribution) || return -Inf
        total += contribution
    end
    return total
end

function sw07_state_space(values::Vector{Float64})
    assembled = sw07_canonical(sw07_theta(values))
    solution = generic_gensys(
        assembled.gamma0, assembled.gamma1, assembled.constant,
        assembled.shock_loading, assembled.expectational_loading,
    )
    Q = Matrix(Diagonal(assembled.shock_sd .^ 2))
    return (
        solution = solution,
        Z = assembled.measurement_loading,
        d = assembled.measurement_intercept,
        Q = Q,
    )
end

function sw07_log_posterior(observations::Matrix{Float64}, values::Vector{Float64})
    prior = sw07_log_prior(values)
    isfinite(prior) || return -Inf
    local loglik
    try
        space = sw07_state_space(values)
        loglik, _, _ = kalman_loglikelihood(
            observations, space.solution.transition, space.solution.constant,
            space.solution.impact, space.Q, space.Z, space.d,
        )
    catch
        return -Inf
    end
    return isfinite(loglik) ? loglik + prior : -Inf
end

"""
    sw07_estimate(observations; start, max_evaluations) -> NamedTuple

Posterior-mode estimation of the 36 SW07 parameters on a T x 7 observation
matrix in `SW07_OBSERVABLE_NAMES` order.
"""
function sw07_estimate(
        observations::Matrix{Float64};
        start::Union{Nothing, Vector{Float64}} = nothing,
        max_evaluations::Int = 4000,
    )
    names = sw07_parameter_names()
    start_values = isnothing(start) ?
        Float64[sw07_mode_start()[name] for name in names] : copy(start)
    transforms = sw07_transforms()
    n = length(names)
    x0 = [to_unconstrained(transforms[i], start_values[i]) for i in 1:n]
    objective = x -> begin
        values = [to_domain(transforms[i], x[i]) for i in 1:n]
        sw07_log_posterior(observations, values)
    end
    x_best, f_best, evaluations, converged =
        nelder_mead_maximize(objective, x0; max_evaluations = max_evaluations)
    mode = [to_domain(transforms[i], x_best[i]) for i in 1:n]
    isfinite(f_best) || return (;
        mode = start_values, log_posterior = -Inf, loglikelihood = -Inf,
        evaluations, converged = false, usable = false,
    )
    space = sw07_state_space(mode)
    loglik, terminal_state, terminal_covariance = kalman_loglikelihood(
        observations, space.solution.transition, space.solution.constant,
        space.solution.impact, space.Q, space.Z, space.d,
    )
    return (;
        mode, log_posterior = f_best, loglikelihood = loglik,
        evaluations, converged, usable = true,
        space, terminal_state, terminal_covariance,
    )
end

function _psd_factor(P::Matrix{Float64})
    eigen_decomposition = eigen(Symmetric((P + P') / 2.0))
    values = map(v -> v > 0.0 ? sqrt(v) : 0.0, eigen_decomposition.values)
    return eigen_decomposition.vectors * Diagonal(values)
end

"""
    sw07_simulate_observables(space, terminal_state, terminal_covariance,
                              horizon, paths, rng) -> horizon x n_obs x paths

Joint predictive simulation from the filtered terminal state: terminal-state
uncertainty plus future structural shocks at the mode. No parameter
uncertainty (recorded limitation, matching the small-NK column convention).
"""
function sw07_simulate_observables(
        space, terminal_state::Vector{Float64}, terminal_covariance::Matrix{Float64},
        horizon::Int, paths::Int, rng::AbstractRNG,
    )
    T_mat = space.solution.transition
    c_vec = space.solution.constant
    R_mat = space.solution.impact
    shock_sd = sqrt.(diag(space.Q))
    Z, d = space.Z, space.d
    n_state = length(terminal_state)
    n_obs = length(d)
    n_shock = length(shock_sd)
    state_factor = _psd_factor(terminal_covariance)
    output = Array{Float64, 3}(undef, horizon, n_obs, paths)
    for j in 1:paths
        state = terminal_state + state_factor * randn(rng, n_state)
        for h in 1:horizon
            state = T_mat * state + c_vec + R_mat * (shock_sd .* randn(rng, n_shock))
            output[h, :, j] = Z * state + d
        end
    end
    return output
end

# --- SW07 data panel --------------------------------------------------------

"""
    sw07_load_panel(path) -> NamedTuple

Load the SW07 observable panel produced by `build_sw07_panel.jl`. Columns:
period, dy, dc, dinve, dw, labobs_raw, pinfobs, robs, dpop (all quarterly
percent; labobs_raw is 100*ln(hours per capita), demeaned per origin later).
"""
function sw07_load_panel(path::AbstractString)
    lines = readlines(path)
    header = split(strip(lines[1]), ',')
    expected = ["period", "dy", "dc", "dinve", "dw", "labobs_raw", "pinfobs", "robs", "dpop"]
    collect(header) == expected || error("unexpected sw07 panel header: $header")
    periods = String[]
    values = Vector{Vector{Float64}}()
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(strip(line), ',')
        push!(periods, String(fields[1]))
        push!(values, [parse(Float64, f) for f in fields[2:end]])
    end
    matrix = reduce(vcat, (v' for v in values))
    return (periods = periods, values = Matrix{Float64}(matrix))
end

# --- column generation ------------------------------------------------------

function _summaries_from_draws(
        column::String, origin_index::Int, origin_period::String,
        panel_periods::Vector{String},
        draws_by_target::Dict{String, Matrix{Float64}},  # target -> horizon x paths
    )
    rows = DSGEEnsembleRow[]
    stored = Dict{Tuple{Int, String, Int}, Vector{Float64}}()
    for target in DSGE_TARGET_IDS
        draw_matrix = draws_by_target[target]
        horizon_count, paths = size(draw_matrix)
        for h in 1:horizon_count
            target_index = origin_index + h
            target_period = target_index <= length(panel_periods) ?
                panel_periods[target_index] : quarter_add(origin_period, h)
            sample = vec(draw_matrix[h, :])
            sorted = sort(sample)
            quantile_at = q -> begin
                position = clamp(q * (paths - 1) + 1.0, 1.0, Float64(paths))
                lower = Int(floor(position))
                upper = Int(ceil(position))
                weight = position - lower
                (1.0 - weight) * sorted[lower] + weight * sorted[upper]
            end
            push!(
                rows,
                DSGEEnsembleRow(
                    column, origin_index, origin_period, target_period, target,
                    h, paths, mean(sample), quantile_at(0.5), std(sample),
                    std(sample) / sqrt(paths), quantile_at(0.05),
                    quantile_at(0.1), quantile_at(0.25), quantile_at(0.75),
                    quantile_at(0.9), quantile_at(0.95),
                ),
            )
            stored[(origin_index, target, h)] = sample
        end
    end
    return rows, stored
end

"""
    generate_dsge_column(column, panel_periods, panel_values, panel_targets;
                         origin_indices, sw07_panel, paths, verbose)

Generate one DSGE scored column over the requested origin indices. The panel
arguments are the frozen revised-data quarterly panel's periods, value matrix
and target-name vector. For `dsge_sw07`, `sw07_panel` must be the observable
panel from `sw07_load_panel`.
"""
function generate_dsge_column(
        column::String,
        panel_periods::Vector{String},
        panel_values::Matrix{Float64},
        panel_targets::Vector{String};
        origin_indices::Vector{Int},
        sw07_panel = nothing,
        paths::Int = PREDICTIVE_PATHS,
        verbose::Bool = true,
        first_origin_evaluations::Int = column == SW07_COLUMN ? 8000 : 6000,
        warm_evaluations::Int = column == SW07_COLUMN ? 2000 : 3000,
    )
    column in (SMALL_NK_COLUMN, SW07_COLUMN) ||
        throw(ArgumentError("unknown DSGE column $column"))
    target_column = Dict(name => i for (i, name) in enumerate(panel_targets))
    growth_column = target_column["real_gdp"]
    deflator_column = target_column["gdp_deflator"]
    effr_column = target_column["effective_federal_funds_rate"]
    unemployment_column = target_column["unemployment_rate"]

    rows = DSGEEnsembleRow[]
    statuses = DSGEOriginStatus[]
    parameter_modes = Tuple{Int, String, Float64}[]
    stored_draws = Dict{Tuple{Int, String, Int}, Vector{Float64}}()
    warm_start::Union{Nothing, Vector{Float64}} = nothing

    for origin_index in origin_indices
        start_time = time()
        origin_period = panel_periods[origin_index]
        training = panel_values[1:origin_index, :]
        growth_history = training[:, growth_column]
        unemployment_history = training[:, unemployment_column]
        okun_intercept, okun_slope, okun_sigma =
            okun_bridge(growth_history, unemployment_history)
        u0 = unemployment_history[end]

        estimation_status = "converged"
        determinate = true
        eu = (1, 1)
        loglik = NaN
        log_posterior = NaN
        evaluations = 0
        growth_projection = 0.0
        draws_by_target = Dict{String, Matrix{Float64}}()

        if column == SMALL_NK_COLUMN
            observations = hcat(
                training[:, growth_column],
                training[:, deflator_column],
                training[:, effr_column],
            )
            seed = SMALL_NK_SEED_BASE + origin_index
            budget = isnothing(warm_start) ? first_origin_evaluations : warm_evaluations
            result = small_nk_estimate(
                observations; start = warm_start, max_evaluations = budget,
            )
            if !result.usable
                estimation_status = isnothing(warm_start) ?
                    "fixed_fallback" : "carried_forward"
                fallback = isnothing(warm_start) ?
                    small_nk_vector(NK.adapted_mechanics_parameters()) : warm_start
                parameters = small_nk_parameters_from_vector(fallback)
                system = NK.build_canonical_system(parameters)
                solution = NK.solve_gensys(system)
                measurement = NK.build_measurement_system(parameters)
                filtered = NK.filter_loglikelihood(observations, solution, measurement)
                result = (;
                    mode = fallback, log_posterior = -Inf,
                    loglikelihood = filtered.loglikelihood,
                    evaluations = 0, converged = false, usable = true,
                    parameters, solution, measurement, filtered,
                )
            elseif !result.converged
                estimation_status = "budget_exhausted"
            end
            warm_start = copy(result.mode)
            loglik = result.loglikelihood
            log_posterior = result.log_posterior
            evaluations = result.evaluations
            eu = result.solution.eu
            determinate = eu == (1, 1)
            for (i, name) in enumerate(SMALL_NK_PARAMETER_NAMES)
                push!(parameter_modes, (origin_index, name, result.mode[i]))
            end
            predictive = NK.draw_joint_predictive_paths(
                result.filtered, result.solution, result.measurement,
                FORECAST_HORIZON, paths; seed = seed,
            )
            # observables: [real growth (ann pp), inflation (ann pp), EFFR (ann pp)]
            real_draws = predictive[:, 1, :]
            deflator_draws = predictive[:, 2, :]
            effr_draws = clamp.(predictive[:, 3, :], EFFR_LOWER_BOUND, Inf)
            nominal_draws = compose_nominal.(real_draws, deflator_draws)
            bridge_rng = MersenneTwister(seed + 500_000)
            unemployment_draws = simulate_unemployment_paths(
                bridge_rng, real_draws, u0, okun_intercept, okun_slope, okun_sigma,
            )
            draws_by_target["real_gdp"] = real_draws
            draws_by_target["gdp_deflator"] = deflator_draws
            draws_by_target["nominal_gdp"] = nominal_draws
            draws_by_target["effective_federal_funds_rate"] = effr_draws
            draws_by_target["unemployment_rate"] = unemployment_draws
        else
            sw07_panel === nothing &&
                throw(ArgumentError("dsge_sw07 requires the sw07 observable panel"))
            period_index = Dict(p => i for (i, p) in enumerate(sw07_panel.periods))
            haskey(period_index, origin_period) ||
                error("origin $origin_period missing from sw07 panel")
            start_row = period_index[SW07_ESTIMATION_START]
            end_row = period_index[origin_period]
            block = sw07_panel.values[start_row:end_row, :]
            # columns: dy dc dinve dw labobs_raw pinfobs robs dpop
            observations = block[:, 1:7]
            labobs_mean = mean(observations[:, 5])
            observations = copy(observations)
            observations[:, 5] .-= labobs_mean       # per-origin demeaning
            dpop_history = block[:, 8]
            growth_projection = mean(dpop_history[max(end - 7, 1):end])
            seed = SW07_SEED_BASE + origin_index
            budget = isnothing(warm_start) ? first_origin_evaluations : warm_evaluations
            result = sw07_estimate(
                observations; start = warm_start, max_evaluations = budget,
            )
            if !result.usable
                estimation_status = isnothing(warm_start) ?
                    "fixed_fallback" : "carried_forward"
                fallback = isnothing(warm_start) ?
                    Float64[sw07_mode_start()[n] for n in sw07_parameter_names()] :
                    warm_start
                space = sw07_state_space(fallback)
                loglik_fb, terminal_state, terminal_covariance = kalman_loglikelihood(
                    observations, space.solution.transition,
                    space.solution.constant, space.solution.impact, space.Q,
                    space.Z, space.d,
                )
                result = (;
                    mode = fallback, log_posterior = -Inf, loglikelihood = loglik_fb,
                    evaluations = 0, converged = false, usable = true,
                    space, terminal_state, terminal_covariance,
                )
            elseif !result.converged
                estimation_status = "budget_exhausted"
            end
            warm_start = copy(result.mode)
            loglik = result.loglikelihood
            log_posterior = result.log_posterior
            evaluations = result.evaluations
            eu = result.space.solution.eu
            determinate = eu == (1, 1)
            names = sw07_parameter_names()
            for (i, name) in enumerate(names)
                push!(parameter_modes, (origin_index, name, result.mode[i]))
            end
            rng = MersenneTwister(seed)
            simulated = sw07_simulate_observables(
                result.space, result.terminal_state, result.terminal_covariance,
                FORECAST_HORIZON, paths, rng,
            )
            # dy is per-capita quarterly percent growth; add the projected
            # population growth back and annualize to the aggregate target.
            real_draws = 4.0 .* (simulated[:, 1, :] .+ growth_projection)
            deflator_draws = 4.0 .* simulated[:, 6, :]
            effr_draws = clamp.(4.0 .* simulated[:, 7, :], EFFR_LOWER_BOUND, Inf)
            nominal_draws = compose_nominal.(real_draws, deflator_draws)
            bridge_rng = MersenneTwister(seed + 500_000)
            unemployment_draws = simulate_unemployment_paths(
                bridge_rng, real_draws, u0, okun_intercept, okun_slope, okun_sigma,
            )
            draws_by_target["real_gdp"] = real_draws
            draws_by_target["gdp_deflator"] = deflator_draws
            draws_by_target["nominal_gdp"] = nominal_draws
            draws_by_target["effective_federal_funds_rate"] = effr_draws
            draws_by_target["unemployment_rate"] = unemployment_draws
        end

        origin_rows, origin_draws = _summaries_from_draws(
            column, origin_index, origin_period, panel_periods, draws_by_target,
        )
        append!(rows, origin_rows)
        merge!(stored_draws, origin_draws)
        push!(
            statuses,
            DSGEOriginStatus(
                column, origin_index, origin_period, size(training, 1),
                estimation_status, determinate, eu[1], eu[2], loglik,
                log_posterior, evaluations, okun_intercept, okun_slope,
                okun_sigma, growth_projection, time() - start_time,
            ),
        )
        verbose && println(
            "[$column] origin $origin_period ($origin_index): " *
                "status=$estimation_status loglik=$(round(loglik; digits = 2)) " *
                "evals=$evaluations elapsed=$(round(time() - start_time; digits = 1))s",
        )
    end
    return DSGEColumnResult(column, rows, statuses, parameter_modes, stored_draws)
end

end # module
