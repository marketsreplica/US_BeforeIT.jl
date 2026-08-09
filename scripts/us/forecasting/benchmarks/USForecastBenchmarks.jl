module USForecastBenchmarks

import BeforeIT

using LinearAlgebra
using Random
using SHA
using Statistics

export ARSpec,
    BVARSpec,
    BeforeITVARSpec,
    BeforeITVARXSpec,
    BenchmarkFailure,
    BenchmarkForecast,
    BenchmarkRun,
    DirectARSpec,
    DriftSpec,
    HistoricalMeanSpec,
    NoChangeSpec,
    OriginData,
    SEMI_STRUCTURAL_GAP_ANNUALIZATION,
    SEMI_STRUCTURAL_STATE_NAMES,
    SEMI_STRUCTURAL_TARGET_NAMES,
    SEMI_STRUCTURAL_TARGET_UNITS,
    SemiStructuralSpec,
    SeasonalNaiveSpec,
    horizon,
    model_card,
    model_id,
    run_benchmark

const INTERFACE_VERSION = "0.1.0"

"""
    OriginData(; origin_id, origin_key, training_keys, forecast_keys, y_train,
        x_train = nothing, x_future = nothing, target_names = nothing,
        predictor_names = nothing)

Immutable information set supplied to a benchmark at one forecast origin.
Future target realizations are deliberately absent. Historical and
origin-eligible future exogenous values are stored separately so a model cannot
silently treat realized future predictors as estimation data.
"""
struct OriginData{T}
    origin_id::String
    origin_key::T
    training_keys::Vector{T}
    forecast_keys::Vector{T}
    y_train::Matrix{Float64}
    x_train::Union{Nothing, Matrix{Float64}}
    x_future::Union{Nothing, Matrix{Float64}}
    target_names::Vector{String}
    predictor_names::Vector{String}
end

function OriginData(;
        origin_id,
        origin_key::T,
        training_keys,
        forecast_keys,
        y_train,
        x_train = nothing,
        x_future = nothing,
        target_names = nothing,
        predictor_names = nothing
    ) where {T}
    id = strip(String(origin_id))
    isempty(id) &&
        throw(ArgumentError("origin_id must contain a non-whitespace value"))

    training_index = T[training_keys...]
    forecast_index = T[forecast_keys...]
    isempty(training_index) &&
        throw(ArgumentError("training_keys must contain at least one key"))
    isempty(forecast_index) &&
        throw(ArgumentError("forecast_keys must contain at least one key"))
    _require_strictly_increasing(training_index, "training_keys")
    _require_strictly_increasing(forecast_index, "forecast_keys")

    all(key -> !isless(origin_key, key), training_index) ||
        throw(ArgumentError("training_keys must not be later than origin_key"))
    all(key -> isless(origin_key, key), forecast_index) ||
        throw(ArgumentError("forecast_keys must be later than origin_key"))

    targets = _observation_matrix(y_train, "y_train")
    size(targets, 1) == length(training_index) ||
        throw(
        DimensionMismatch(
            "y_train has $(size(targets, 1)) rows but training_keys has " *
                "$(length(training_index)) entries"
        )
    )

    target_labels = _labels(target_names, size(targets, 2), "target")
    historical_predictors, future_predictors, predictor_labels =
        _validated_predictors(
        x_train,
        x_future,
        size(targets, 1),
        length(forecast_index),
        predictor_names
    )

    return OriginData{T}(
        id,
        origin_key,
        training_index,
        forecast_index,
        targets,
        historical_predictors,
        future_predictors,
        target_labels,
        predictor_labels
    )
end

horizon(sample::OriginData) = length(sample.forecast_keys)

abstract type AbstractBenchmarkSpec end

"""Random-walk/no-change benchmark."""
struct NoChangeSpec <: AbstractBenchmarkSpec end

"""Random walk with drift estimated only from the training differences."""
struct DriftSpec <: AbstractBenchmarkSpec end

"""Constant forecast equal to the training-sample historical mean."""
struct HistoricalMeanSpec <: AbstractBenchmarkSpec end

"""Seasonal random walk with a fixed, preregistered period."""
struct SeasonalNaiveSpec <: AbstractBenchmarkSpec
    period::Int
    function SeasonalNaiveSpec(period = 4)
        period isa Integer && !(period isa Bool) ||
            throw(ArgumentError("period must be an integer"))
        period >= 1 || throw(ArgumentError("period must be at least 1"))
        return new(Int(period))
    end
end

"""
    ARSpec(; candidate_lags = 1:8, intercept = true)

Iterated univariate AR benchmark. Each target chooses its lag independently by
BIC on a common, training-only comparison window. Supplying one candidate
produces a fixed-lag AR.
"""
struct ARSpec <: AbstractBenchmarkSpec
    candidate_lags::Vector{Int}
    intercept::Bool
    function ARSpec(; candidate_lags = 1:8, intercept = true)
        intercept isa Bool ||
            throw(ArgumentError("intercept must be Bool"))
        candidates = collect(candidate_lags)
        isempty(candidates) &&
            throw(ArgumentError("candidate_lags must not be empty"))
        all(lag -> lag isa Integer && !(lag isa Bool), candidates) ||
            throw(ArgumentError("candidate_lags must contain only integers"))
        integer_candidates = sort!(unique!(Int.(candidates)))
        all(>=(1), integer_candidates) ||
            throw(ArgumentError("candidate_lags must be at least 1"))
        return new(integer_candidates, intercept)
    end
end

"""Adapter for the repaired `BeforeIT` VAR utilities."""
struct BeforeITVARSpec <: AbstractBenchmarkSpec
    lags::Int
    intercept::Bool
    function BeforeITVARSpec(; lags = 1, intercept = true)
        return new(_fixed_lags(lags), _boolean(intercept, "intercept"))
    end
end

"""
Adapter for the repaired `BeforeIT` VARX utilities. The fit receives
`x_train`; only recursive forecasting receives `x_future`.
"""
struct BeforeITVARXSpec <: AbstractBenchmarkSpec
    lags::Int
    intercept::Bool
    function BeforeITVARXSpec(; lags = 1, intercept = true)
        return new(_fixed_lags(lags), _boolean(intercept, "intercept"))
    end
end

model_id(::NoChangeSpec) = "naive_no_change"
model_id(::DriftSpec) = "naive_drift"
model_id(::HistoricalMeanSpec) = "naive_historical_mean"
model_id(spec::SeasonalNaiveSpec) = "naive_seasonal_$(spec.period)"
function model_id(spec::ARSpec)
    lag_rule = if length(spec.candidate_lags) == 1
        "p$(only(spec.candidate_lags))"
    else
        "bic_p$(join(spec.candidate_lags, '-'))"
    end
    return "univariate_ar_$(lag_rule)_$(_intercept_suffix(spec.intercept))"
end
model_id(spec::BeforeITVARSpec) =
    "beforeit_var_p$(spec.lags)_$(_intercept_suffix(spec.intercept))"
model_id(spec::BeforeITVARXSpec) =
    "beforeit_varx_p$(spec.lags)_$(_intercept_suffix(spec.intercept))"

"""
Successful point and density output. `draws` has dimensions
`horizon × targets × draws`; a point-only run has a zero-length third axis.
"""
struct BenchmarkForecast{T}
    interface_version::String
    model_id::String
    origin_id::String
    origin_key::T
    forecast_keys::Vector{T}
    target_names::Vector{String}
    point::Matrix{Float64}
    draws::Array{Float64, 3}
    diagnostics::Dict{String, Any}
end

"""Serializable failure record retained instead of silently dropping a model."""
struct BenchmarkFailure
    code::Symbol
    exception_type::String
    message::String
end

"""Visible success/failure envelope for every attempted benchmark."""
struct BenchmarkRun{T}
    status::Symbol
    model_id::String
    origin_id::String
    forecast::Union{Nothing, BenchmarkForecast{T}}
    failure::Union{Nothing, BenchmarkFailure}
end

"""
    run_benchmark(spec, sample; n_draws = 0, seed = 0)

Run one benchmark against the origin-bounded information set. Estimation and
validation errors are returned as `status == :failed` with a structured
`BenchmarkFailure`; they are never converted into a forecast or silently
omitted.
"""
function run_benchmark(
        spec::AbstractBenchmarkSpec,
        sample::OriginData;
        n_draws = 0,
        seed = 0
    )
    result_type = typeof(sample.origin_key)
    try
        draw_count = _draw_count(n_draws)
        rng_seed = _rng_seed(seed)
        point, draws, diagnostics =
            _forecast(spec, sample, draw_count, rng_seed)
        _validate_output(point, draws, sample, draw_count)
        diagnostics["seed"] = rng_seed
        diagnostics["n_draws"] = draw_count
        diagnostics["training_rows"] = size(sample.y_train, 1)
        diagnostics["forecast_horizon"] = horizon(sample)
        diagnostics["information_set"] =
            "targets through origin; no future target field"

        forecast = BenchmarkForecast(
            INTERFACE_VERSION,
            model_id(spec),
            sample.origin_id,
            sample.origin_key,
            copy(sample.forecast_keys),
            copy(sample.target_names),
            point,
            draws,
            diagnostics
        )
        return BenchmarkRun{result_type}(
            :ok,
            model_id(spec),
            sample.origin_id,
            forecast,
            nothing
        )
    catch error
        failure = BenchmarkFailure(
            _failure_code(error),
            string(typeof(error)),
            sprint(showerror, error)
        )
        return BenchmarkRun{result_type}(
            :failed,
            model_id(spec),
            sample.origin_id,
            nothing,
            failure
        )
    end
end

function model_card(::NoChangeSpec)
    return _card(
        "naive_no_change",
        "Naive",
        "Last observed target at every horizon.",
        "Recursive Gaussian random-walk innovations estimated from training differences.",
        "No exogenous inputs."
    )
end

function model_card(::DriftSpec)
    return _card(
        "naive_drift",
        "Naive",
        "Last observation plus training-only mean change times horizon.",
        "Recursive Gaussian innovations around the training-only drift.",
        "No exogenous inputs."
    )
end

function model_card(::HistoricalMeanSpec)
    return _card(
        "naive_historical_mean",
        "Naive",
        "Training-sample mean at every horizon.",
        "Independent Gaussian residual draws around the training mean.",
        "No exogenous inputs; most suitable for stationary rates or growth."
    )
end

function model_card(spec::SeasonalNaiveSpec)
    return _card(
        model_id(spec),
        "Naive",
        "Recursive seasonal no-change path with period $(spec.period).",
        "Recursive Gaussian seasonal-difference innovations.",
        "No exogenous inputs."
    )
end

function model_card(spec::ARSpec)
    lag_rule = length(spec.candidate_lags) == 1 ?
        "Fixed lag $(only(spec.candidate_lags))." :
        "Target-specific BIC over $(spec.candidate_lags) on one common training-only window."
    return _card(
        model_id(spec),
        "Univariate autoregression",
        "Iterated AR forecast; $lag_rule",
        "Recursive independent Gaussian innovations from each selected AR fit.",
        "Exogenous inputs are ignored; direct multi-step AR is outside interface v$INTERFACE_VERSION."
    )
end

function model_card(spec::BeforeITVARSpec)
    return _card(
        model_id(spec),
        "VAR adapter",
        "Repaired BeforeIT VAR($(spec.lags)); fixed lag and intercept=$(spec.intercept).",
        "Recursive Gaussian draws using the fitted joint innovation covariance.",
        "No exogenous path is passed to the estimator or forecaster."
    )
end

function model_card(spec::BeforeITVARXSpec)
    return _card(
        model_id(spec),
        "VARX adapter",
        "Repaired BeforeIT VARX($(spec.lags)); fixed lag and intercept=$(spec.intercept).",
        "Recursive Gaussian draws using the fitted joint innovation covariance.",
        "Fit uses x_train only; forecast uses the separately supplied, origin-eligible x_future path."
    )
end

function _forecast(
        ::NoChangeSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    changes = diff(sample.y_train; dims = 1)
    point = repeat(sample.y_train[end:end, :], horizon(sample), 1)
    draws = _random_walk_draws(
        sample.y_train[end, :],
        zeros(size(sample.y_train, 2)),
        changes,
        horizon(sample),
        n_draws,
        seed
    )
    return point, draws, Dict{String, Any}(
            "point_rule" => "no_change",
            "density_residual_rows" => size(changes, 1)
        )
end

function _forecast(
        ::DriftSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    changes = diff(sample.y_train; dims = 1)
    isempty(changes) &&
        throw(ArgumentError("drift benchmark requires at least two observations"))
    drift = vec(mean(changes; dims = 1))
    point = Matrix{Float64}(undef, horizon(sample), size(sample.y_train, 2))
    for step in 1:horizon(sample)
        point[step, :] .= sample.y_train[end, :] .+ step .* drift
    end
    residuals = changes .- drift'
    draws = _random_walk_draws(
        sample.y_train[end, :],
        drift,
        residuals,
        horizon(sample),
        n_draws,
        seed
    )
    return point, draws, Dict{String, Any}(
            "point_rule" => "training_mean_drift",
            "drift" => drift,
            "density_residual_rows" => size(residuals, 1)
        )
end

function _forecast(
        ::HistoricalMeanSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    historical_mean = vec(mean(sample.y_train; dims = 1))
    point = repeat(historical_mean', horizon(sample), 1)
    residuals = sample.y_train .- historical_mean'
    draws = _location_draws(
        point,
        residuals,
        n_draws,
        seed
    )
    return point, draws, Dict{String, Any}(
            "point_rule" => "training_historical_mean",
            "historical_mean" => historical_mean,
            "density_residual_rows" => size(residuals, 1)
        )
end

function _forecast(
        spec::SeasonalNaiveSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    observations, variables = size(sample.y_train)
    observations > spec.period ||
        throw(
        ArgumentError(
            "seasonal naive period $(spec.period) requires at least " *
                "$(spec.period + 1) observations"
        )
    )
    residuals =
        sample.y_train[(spec.period + 1):end, :] .-
        sample.y_train[1:(end - spec.period), :]
    point = _seasonal_path(
        sample.y_train,
        spec.period,
        horizon(sample),
        nothing
    )
    draws = Array{Float64}(undef, horizon(sample), variables, n_draws)
    if n_draws > 0
        factor = _residual_factor(residuals)
        rng = MersenneTwister(seed)
        for draw in 1:n_draws
            innovations =
                (factor * randn(rng, variables, horizon(sample)))'
            draws[:, :, draw] .= _seasonal_path(
                sample.y_train,
                spec.period,
                horizon(sample),
                innovations
            )
        end
    end
    return point, draws, Dict{String, Any}(
            "point_rule" => "seasonal_no_change",
            "period" => spec.period,
            "density_residual_rows" => size(residuals, 1)
        )
end

function _forecast(
        spec::ARSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    observations, variables = size(sample.y_train)
    maximum_lag = maximum(spec.candidate_lags)
    common_start = maximum_lag + 1
    common_rows = observations - maximum_lag
    maximum_parameters = maximum_lag + Int(spec.intercept)
    common_rows > maximum_parameters ||
        throw(
        ArgumentError(
            "AR lag selection needs more than $maximum_parameters common " *
                "training rows; got $common_rows"
        )
    )

    selected_lags = Vector{Int}(undef, variables)
    coefficients = Vector{Vector{Float64}}(undef, variables)
    innovation_scales = Vector{Float64}(undef, variables)
    criteria = Vector{Dict{Int, Float64}}(undef, variables)

    for variable in 1:variables
        series = @view(sample.y_train[:, variable])
        selected_lag, scores = _select_ar_lag(
            series,
            spec.candidate_lags,
            spec.intercept,
            common_start
        )
        fit = _fit_ar(
            series,
            selected_lag,
            spec.intercept,
            selected_lag + 1
        )
        selected_lags[variable] = selected_lag
        coefficients[variable] = fit.coefficients
        innovation_scales[variable] = fit.innovation_scale
        criteria[variable] = scores
    end

    point = _ar_paths(
        sample.y_train,
        coefficients,
        selected_lags,
        spec.intercept,
        innovation_scales,
        horizon(sample),
        0,
        seed
    )[:, :, 1]
    draws = if n_draws == 0
        Array{Float64}(undef, horizon(sample), variables, 0)
    else
        _ar_paths(
            sample.y_train,
            coefficients,
            selected_lags,
            spec.intercept,
            innovation_scales,
            horizon(sample),
            n_draws,
            seed
        )
    end

    return point, draws, Dict{String, Any}(
            "point_rule" => "iterated_univariate_ar",
            "selection_rule" => "BIC_common_training_window",
            "candidate_lags" => copy(spec.candidate_lags),
            "selected_lags" => selected_lags,
            "bic_by_target" => criteria,
            "common_selection_first_row" => common_start,
            "future_exogenous_used" => false
        )
end

function _forecast(
        spec::BeforeITVARSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    _, _, covariance, residuals = BeforeIT.estimate_VAR(
        sample.y_train;
        intercept = spec.intercept,
        lags = spec.lags
    )
    point = BeforeIT.forecast_k_steps_VAR(
        sample.y_train,
        horizon(sample);
        intercept = spec.intercept,
        lags = spec.lags,
        stochastic = false
    )
    draws = _beforeit_var_draws(spec, sample, n_draws, seed)
    return point, draws, Dict{String, Any}(
            "adapter" => "BeforeIT.forecast_k_steps_VAR",
            "lags" => spec.lags,
            "intercept" => spec.intercept,
            "innovation_covariance" => covariance,
            "density_residual_rows" => size(residuals, 1),
            "future_exogenous_used" => false
        )
end

function _forecast(
        spec::BeforeITVARXSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    sample.x_train === nothing &&
        throw(ArgumentError("VARX requires x_train and x_future"))
    sample.x_future === nothing &&
        throw(ArgumentError("VARX requires x_train and x_future"))
    _, _, gamma, covariance, residuals = BeforeIT.estimate_VARX(
        sample.y_train,
        sample.x_train;
        intercept = spec.intercept,
        lags = spec.lags
    )
    exogenous = vcat(sample.x_train, sample.x_future)
    point = BeforeIT.forecast_k_steps_VARX(
        sample.y_train,
        exogenous,
        horizon(sample);
        intercept = spec.intercept,
        lags = spec.lags,
        stochastic = false
    )
    draws = _beforeit_varx_draws(
        spec,
        sample,
        exogenous,
        n_draws,
        seed
    )
    return point, draws, Dict{String, Any}(
            "adapter" => "BeforeIT.forecast_k_steps_VARX",
            "lags" => spec.lags,
            "intercept" => spec.intercept,
            "fitted_exogenous_coefficients" => gamma,
            "innovation_covariance" => covariance,
            "density_residual_rows" => size(residuals, 1),
            "future_exogenous_used" => true,
            "future_exogenous_rows" => size(sample.x_future, 1),
            "conditioning_semantics" =>
            "origin-eligible supplied path; not realized oracle data"
        )
end

function _beforeit_var_draws(
        spec::BeforeITVARSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    variables = size(sample.y_train, 2)
    draws = Array{Float64}(
        undef,
        horizon(sample),
        variables,
        n_draws
    )
    n_draws == 0 && return draws
    rng = MersenneTwister(seed)
    for draw in 1:n_draws
        draws[:, :, draw] .= BeforeIT.forecast_k_steps_VAR(
            rng,
            sample.y_train,
            horizon(sample);
            intercept = spec.intercept,
            lags = spec.lags,
            stochastic = true
        )
    end
    return draws
end

function _beforeit_varx_draws(
        spec::BeforeITVARXSpec,
        sample::OriginData,
        exogenous::Matrix{Float64},
        n_draws::Int,
        seed::Int
    )
    variables = size(sample.y_train, 2)
    draws = Array{Float64}(
        undef,
        horizon(sample),
        variables,
        n_draws
    )
    n_draws == 0 && return draws
    rng = MersenneTwister(seed)
    for draw in 1:n_draws
        draws[:, :, draw] .= BeforeIT.forecast_k_steps_VARX(
            rng,
            sample.y_train,
            exogenous,
            horizon(sample);
            intercept = spec.intercept,
            lags = spec.lags,
            stochastic = true
        )
    end
    return draws
end

function _random_walk_draws(
        initial_value,
        drift,
        residuals,
        forecast_horizon::Int,
        n_draws::Int,
        seed::Int
    )
    variables = length(initial_value)
    draws =
        Array{Float64}(undef, forecast_horizon, variables, n_draws)
    n_draws == 0 && return draws
    factor = _residual_factor(residuals)
    rng = MersenneTwister(seed)
    for draw in 1:n_draws
        current = Vector{Float64}(initial_value)
        for step in 1:forecast_horizon
            current .+= drift .+ factor * randn(rng, variables)
            draws[step, :, draw] .= current
        end
    end
    return draws
end

function _location_draws(point, residuals, n_draws::Int, seed::Int)
    forecast_horizon, variables = size(point)
    draws =
        Array{Float64}(undef, forecast_horizon, variables, n_draws)
    n_draws == 0 && return draws
    factor = _residual_factor(residuals)
    rng = MersenneTwister(seed)
    for draw in 1:n_draws
        for step in 1:forecast_horizon
            draws[step, :, draw] .=
                point[step, :] .+ factor * randn(rng, variables)
        end
    end
    return draws
end

function _seasonal_path(
        training,
        period::Int,
        forecast_horizon::Int,
        innovations
    )
    observations, variables = size(training)
    history =
        Matrix{Float64}(undef, observations + forecast_horizon, variables)
    history[1:observations, :] .= training
    for step in 1:forecast_horizon
        value = @view history[observations + step - period, :]
        history[observations + step, :] .= value
        innovations === nothing ||
            (history[observations + step, :] .+= innovations[step, :])
    end
    return history[(observations + 1):end, :]
end

function _select_ar_lag(
        series,
        candidates,
        intercept::Bool,
        common_start::Int
    )
    scores = Dict{Int, Float64}()
    for lag in candidates
        try
            fit = _fit_ar(series, lag, intercept, common_start)
            observations = length(fit.residuals)
            parameters = lag + Int(intercept)
            variance = max(
                sum(abs2, fit.residuals) / observations,
                eps(Float64)
            )
            scores[lag] =
                observations * log(variance) +
                parameters * log(observations)
        catch error
            if error isa ArgumentError || error isa LinearAlgebra.SingularException
                scores[lag] = Inf
            else
                rethrow()
            end
        end
    end
    finite_candidates = filter(lag -> isfinite(scores[lag]), candidates)
    isempty(finite_candidates) &&
        throw(ArgumentError("no AR candidate could be estimated"))
    selected = first(finite_candidates)
    for lag in Iterators.drop(finite_candidates, 1)
        if scores[lag] < scores[selected]
            selected = lag
        end
    end
    return selected, scores
end

function _fit_ar(series, lag::Int, intercept::Bool, first_row::Int)
    observations = length(series)
    first_row >= lag + 1 ||
        throw(ArgumentError("first AR response row must exceed its lag"))
    first_row <= observations ||
        throw(ArgumentError("AR fit has no response observations"))
    response_rows = first_row:observations
    parameters = lag + Int(intercept)
    length(response_rows) > parameters ||
        throw(ArgumentError("AR fit has no residual degrees of freedom"))

    design = Matrix{Float64}(
        undef,
        length(response_rows),
        parameters
    )
    response = Vector{Float64}(undef, length(response_rows))
    for (row, time) in enumerate(response_rows)
        column = 1
        if intercept
            design[row, column] = 1.0
            column += 1
        end
        for delay in 1:lag
            design[row, column] = series[time - delay]
            column += 1
        end
        response[row] = series[time]
    end
    rank(design) == parameters ||
        throw(ArgumentError("AR design matrix is rank deficient"))
    coefficients = design \ response
    residuals = response - design * coefficients
    degrees_of_freedom = length(response) - parameters
    innovation_scale =
        sqrt(max(sum(abs2, residuals) / degrees_of_freedom, 0.0))
    return (
        coefficients = coefficients,
        residuals = residuals,
        innovation_scale = innovation_scale,
    )
end

function _ar_paths(
        training,
        coefficients,
        selected_lags,
        intercept::Bool,
        innovation_scales,
        forecast_horizon::Int,
        n_draws::Int,
        seed::Int
    )
    observations, variables = size(training)
    path_count = max(n_draws, 1)
    paths =
        Array{Float64}(undef, forecast_horizon, variables, path_count)
    rng = MersenneTwister(seed)

    for path in 1:path_count
        history =
            Matrix{Float64}(undef, observations + forecast_horizon, variables)
        history[1:observations, :] .= training
        for step in 1:forecast_horizon
            for variable in 1:variables
                coefficients_for_target = coefficients[variable]
                coefficient_index = 1
                value = 0.0
                if intercept
                    value += coefficients_for_target[coefficient_index]
                    coefficient_index += 1
                end
                for delay in 1:selected_lags[variable]
                    value +=
                        coefficients_for_target[coefficient_index] *
                        history[observations + step - delay, variable]
                    coefficient_index += 1
                end
                if n_draws > 0
                    value += innovation_scales[variable] * randn(rng)
                end
                history[observations + step, variable] = value
                paths[step, variable, path] = value
            end
        end
    end
    return paths
end

function _residual_factor(residuals)
    observations, variables = size(residuals)
    observations >= 2 ||
        throw(
        ArgumentError(
            "density simulation requires at least two residual observations"
        )
    )
    covariance = if variables == 1
        reshape([var(vec(residuals); corrected = true)], 1, 1)
    else
        cov(residuals)
    end
    all(isfinite, covariance) ||
        throw(ArgumentError("residual covariance is not finite"))
    symmetric_covariance =
        Symmetric((Matrix{Float64}(covariance) + covariance') / 2)
    decomposition = eigen(symmetric_covariance)
    tolerance =
        100 * variables * eps(Float64) *
        max(maximum(abs, decomposition.values), 1.0)
    minimum(decomposition.values) >= -tolerance ||
        throw(ArgumentError("residual covariance is not positive semidefinite"))
    return decomposition.vectors *
        Diagonal(sqrt.(max.(decomposition.values, 0.0)))
end

function _validated_predictors(
        x_train,
        x_future,
        training_rows,
        forecast_rows,
        predictor_names
    )
    if x_train === nothing && x_future === nothing
        predictor_names === nothing ||
            throw(
            ArgumentError(
                "predictor_names requires x_train and x_future"
            )
        )
        return nothing, nothing, String[]
    elseif x_train === nothing || x_future === nothing
        throw(
            ArgumentError(
                "x_train and x_future must either both be supplied or both be nothing"
            )
        )
    end

    historical = _observation_matrix(x_train, "x_train")
    future = _observation_matrix(x_future, "x_future")
    size(historical, 1) == training_rows ||
        throw(
        DimensionMismatch(
            "x_train has $(size(historical, 1)) rows; expected $training_rows"
        )
    )
    size(future, 1) == forecast_rows ||
        throw(
        DimensionMismatch(
            "x_future has $(size(future, 1)) rows; expected $forecast_rows"
        )
    )
    size(historical, 2) == size(future, 2) ||
        throw(
        DimensionMismatch(
            "x_train and x_future must have the same number of columns"
        )
    )
    labels = _labels(predictor_names, size(historical, 2), "predictor")
    return historical, future, labels
end

function _observation_matrix(data, name)
    matrix = if data isa AbstractVector
        reshape(Float64.(data), :, 1)
    elseif data isa AbstractMatrix
        Matrix{Float64}(data)
    else
        throw(ArgumentError("$name must be a vector or matrix"))
    end
    size(matrix, 1) > 0 ||
        throw(ArgumentError("$name must have at least one row"))
    size(matrix, 2) > 0 ||
        throw(ArgumentError("$name must have at least one column"))
    all(isfinite, matrix) ||
        throw(ArgumentError("$name must contain only finite values"))
    return matrix
end

function _labels(labels, count::Int, prefix)
    values = labels === nothing ?
        ["$(prefix)_$index" for index in 1:count] : String.(labels)
    length(values) == count ||
        throw(
        DimensionMismatch(
            "$(prefix)_names has $(length(values)) entries; expected $count"
        )
    )
    all(label -> !isempty(strip(label)), values) ||
        throw(ArgumentError("$(prefix)_names must be nonempty"))
    length(unique(values)) == length(values) ||
        throw(ArgumentError("$(prefix)_names must be unique"))
    return values
end

function _require_strictly_increasing(values, name)
    for index in 2:length(values)
        isless(values[index - 1], values[index]) ||
            throw(ArgumentError("$name must be strictly increasing"))
    end
    return nothing
end

function _fixed_lags(lags)
    lags isa Integer && !(lags isa Bool) ||
        throw(ArgumentError("lags must be an integer"))
    lags >= 1 || throw(ArgumentError("lags must be at least 1"))
    return Int(lags)
end

function _boolean(value, name)
    value isa Bool || throw(ArgumentError("$name must be Bool"))
    return value
end

_intercept_suffix(intercept::Bool) = intercept ? "constant" : "no_constant"

function _draw_count(n_draws)
    n_draws isa Integer && !(n_draws isa Bool) ||
        throw(ArgumentError("n_draws must be an integer"))
    n_draws >= 0 || throw(ArgumentError("n_draws must be non-negative"))
    return Int(n_draws)
end

function _rng_seed(seed)
    seed isa Integer && !(seed isa Bool) ||
        throw(ArgumentError("seed must be an integer"))
    seed >= 0 ||
        throw(ArgumentError("seed must be non-negative"))
    typemin(Int) <= seed <= typemax(Int) ||
        throw(ArgumentError("seed must fit in Int"))
    return Int(seed)
end

function _validate_output(point, draws, sample, n_draws)
    expected_point = (horizon(sample), size(sample.y_train, 2))
    size(point) == expected_point ||
        throw(
        DimensionMismatch(
            "point forecast has size $(size(point)); expected $expected_point"
        )
    )
    expected_draws = (expected_point..., n_draws)
    size(draws) == expected_draws ||
        throw(
        DimensionMismatch(
            "density draws have size $(size(draws)); expected $expected_draws"
        )
    )
    all(isfinite, point) ||
        throw(ArgumentError("point forecast contains non-finite values"))
    all(isfinite, draws) ||
        throw(ArgumentError("density draws contain non-finite values"))
    return nothing
end

function _failure_code(error)
    if error isa DimensionMismatch
        return :dimension_mismatch
    elseif error isa ArgumentError
        return :invalid_input
    elseif error isa LinearAlgebra.LAPACKException ||
            error isa LinearAlgebra.SingularException ||
            error isa LinearAlgebra.PosDefException
        return :estimation_failure
    else
        return :execution_failure
    end
end

function _card(id, family, point_rule, density_rule, exogenous_rule)
    return Dict{String, Any}(
        "interface_version" => INTERFACE_VERSION,
        "model_id" => id,
        "family" => family,
        "estimation_information_set" =>
            "OriginData.y_train only; future target realizations cannot be supplied.",
        "point_rule" => point_rule,
        "density_rule" => density_rule,
        "exogenous_rule" => exogenous_rule,
        "failure_policy" =>
            "Retain a structured failed BenchmarkRun; never impute or omit silently.",
        "seed_policy" =>
            "Explicit integer seed; MersenneTwister; deterministic point path."
    )
end

include("bvar.jl")
include("semi_structural.jl")
include("direct_ar.jl")

end
