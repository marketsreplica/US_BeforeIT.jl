"""
    forecast_k_steps_VAR(data, n_forecasts; intercept = false, lags = 1,
        stochastic = false)
    forecast_k_steps_VAR(rng::AbstractRNG, data, n_forecasts;
        intercept = false, lags = 1, stochastic = false)

Forecast the next `n_forecasts` observations from a fitted vector
autoregression (VAR). Rows of `data` are observations and columns are
variables. A vector is treated as a one-variable series.

When `stochastic = true`, innovations are drawn from the fitted joint
innovation covariance matrix. The explicit `rng` overload supports
reproducible simulation; the compatibility method uses `Random.default_rng()`.
The deterministic path does not consume random numbers.
"""
function forecast_k_steps_VAR(
        data,
        n_forecasts;
        intercept = false,
        lags = 1,
        stochastic = false
    )
    return forecast_k_steps_VAR(
        Random.default_rng(), data, n_forecasts;
        intercept = intercept, lags = lags, stochastic = stochastic
    )
end

function forecast_k_steps_VAR(
        rng::AbstractRNG,
        data,
        n_forecasts;
        intercept = false,
        lags = 1,
        stochastic = false
    )
    horizon = _validate_forecast_horizon(n_forecasts)
    current_data = _as_observation_matrix(data, "data")
    lag_count = _validate_lags(lags, size(current_data, 1))
    n_observations, n_vars = size(current_data)

    alpha, beta, sigma, _ = estimate_VAR(
        current_data; intercept = intercept, lags = lag_count
    )
    alpha = _prepare_alpha(alpha, n_vars, lag_count)
    innovation_factor =
        stochastic ? _innovation_factor(sigma, n_vars) : nothing

    history = Matrix{Float64}(undef, n_observations + horizon, n_vars)
    history[1:n_observations, :] .= current_data
    forecasted_values = Matrix{Float64}(undef, horizon, n_vars)

    for i in 1:horizon
        lagged_data = _get_lagged_data(
            @view(history[1:(n_observations + i - 1), :]), lag_count
        )
        epsilon = if stochastic
            innovation_factor * randn(rng, n_vars)
        else
            zeros(n_vars)
        end

        next_value = alpha * lagged_data .+ epsilon
        intercept && (next_value .+= vec(beta))

        forecasted_values[i, :] .= next_value
        history[n_observations + i, :] .= next_value
    end

    return forecasted_values
end

"""
    forecast_k_steps_VARX(data, exogenous, n_forecasts;
        intercept = false, lags = 1, stochastic = false)
    forecast_k_steps_VARX(rng::AbstractRNG, data, exogenous, n_forecasts;
        intercept = false, lags = 1, stochastic = false)

Forecast the next `n_forecasts` observations from a fitted vector
autoregression with exogenous predictors (VARX).

`exogenous` must have `size(data, 1) + n_forecasts` rows. Its first
`size(data, 1)` rows are aligned with the estimation sample and its remaining
rows are the known future predictor path. A vector is treated as a
one-predictor series.

When `stochastic = true`, innovations are drawn from the fitted joint
innovation covariance matrix. The explicit `rng` overload supports
reproducible simulation; the compatibility method uses `Random.default_rng()`.
The deterministic path does not consume random numbers.
"""
function forecast_k_steps_VARX(
        data,
        exogenous,
        n_forecasts;
        intercept = false,
        lags = 1,
        stochastic = false
    )
    return forecast_k_steps_VARX(
        Random.default_rng(), data, exogenous, n_forecasts;
        intercept = intercept, lags = lags, stochastic = stochastic
    )
end

function forecast_k_steps_VARX(
        rng::AbstractRNG,
        data,
        exogenous,
        n_forecasts;
        intercept = false,
        lags = 1,
        stochastic = false
    )
    horizon = _validate_forecast_horizon(n_forecasts)
    current_data = _as_observation_matrix(data, "data")
    exogenous_data = _as_observation_matrix(exogenous, "exogenous")
    lag_count = _validate_lags(lags, size(current_data, 1))
    n_observations, n_vars = size(current_data)

    expected_exogenous_rows = n_observations + horizon
    size(exogenous_data, 1) == expected_exogenous_rows ||
        throw(
        DimensionMismatch(
            "exogenous must have $expected_exogenous_rows rows " *
                "($n_observations historical plus $horizon forecast rows); " *
                "got $(size(exogenous_data, 1))"
        )
    )

    alpha, beta, gamma, sigma, _ = estimate_VARX(
        current_data, exogenous_data[1:n_observations, :];
        intercept = intercept, lags = lag_count
    )
    alpha = _prepare_alpha(alpha, n_vars, lag_count)
    innovation_factor =
        stochastic ? _innovation_factor(sigma, n_vars) : nothing

    history = Matrix{Float64}(undef, n_observations + horizon, n_vars)
    history[1:n_observations, :] .= current_data
    forecasted_values = Matrix{Float64}(undef, horizon, n_vars)

    for i in 1:horizon
        lagged_data = _get_lagged_data(
            @view(history[1:(n_observations + i - 1), :]), lag_count
        )
        exogenous_term =
            gamma * @view(exogenous_data[n_observations + i, :])
        epsilon = if stochastic
            innovation_factor * randn(rng, n_vars)
        else
            zeros(n_vars)
        end

        next_value = alpha * lagged_data .+ exogenous_term .+ epsilon
        intercept && (next_value .+= beta)

        forecasted_values[i, :] .= next_value
        history[n_observations + i, :] .= next_value
    end

    return forecasted_values
end

"""
    estimate_VAR(ydata; intercept = false, lags = 1)

Estimate a VAR by least squares. `beta` retains the historical return shape:
an `n_variables × 1` matrix when an intercept is requested and an empty vector
otherwise.
"""
function estimate_VAR(ydata; intercept = false, lags = 1)
    data = _as_observation_matrix(ydata, "ydata")
    lag_count = _validate_lags(lags, size(data, 1))

    var = if intercept
        rfvar3(data, lag_count, ones(size(data, 1), 1))
    else
        rfvar3(data, lag_count, Matrix{Float64}(undef, size(data, 1), 0))
    end

    alpha = var.By
    beta = var.Bx
    sigma = cov(var.u)

    return alpha, beta, sigma, var.u
end

"""
    estimate_VARX(ydata, xdata; intercept = false, lags = 1)

Estimate a VARX by least squares. Without an intercept, `beta` is empty and
every exogenous coefficient is returned in `gamma`. With an intercept, `beta`
is the intercept vector and `gamma` contains all exogenous coefficients.
"""
function estimate_VARX(ydata, xdata; intercept = false, lags = 1)
    data = _as_observation_matrix(ydata, "ydata")
    exogenous_data = _as_observation_matrix(xdata, "xdata")
    lag_count = _validate_lags(lags, size(data, 1))

    size(exogenous_data, 1) == size(data, 1) ||
        throw(
        DimensionMismatch(
            "xdata and ydata must have the same number of rows; got " *
                "$(size(exogenous_data, 1)) and $(size(data, 1))"
        )
    )

    regressors = if intercept
        hcat(ones(size(exogenous_data, 1), 1), exogenous_data)
    else
        exogenous_data
    end
    var = rfvar3(data, lag_count, regressors)

    alpha = var.By
    if intercept
        beta = var.Bx[:, 1]
        gamma = var.Bx[:, 2:end]
    else
        beta = Float64[]
        gamma = var.Bx
    end
    sigma = cov(var.u)

    return alpha, beta, gamma, sigma, var.u
end

function _as_observation_matrix(data, name)
    if data isa AbstractVector
        eltype(data) <: Real ||
            throw(ArgumentError("$name must contain real-valued observations"))
        matrix = reshape(Float64.(data), :, 1)
    elseif data isa AbstractMatrix
        eltype(data) <: Real ||
            throw(ArgumentError("$name must contain real-valued observations"))
        matrix = Matrix{Float64}(data)
    else
        throw(
            ArgumentError(
                "$name must be a vector or a two-dimensional matrix with " *
                    "observations in rows"
            )
        )
    end

    size(matrix, 1) > 0 ||
        throw(ArgumentError("$name must contain at least one observation"))
    size(matrix, 2) > 0 ||
        throw(ArgumentError("$name must contain at least one variable"))
    all(isfinite, matrix) ||
        throw(ArgumentError("$name must contain only finite observations"))
    return matrix
end

function _validate_lags(lags, n_observations)
    lags isa Integer && !(lags isa Bool) ||
        throw(ArgumentError("lags must be an integer"))
    lags >= 1 || throw(ArgumentError("lags must be at least 1"))
    lags < n_observations ||
        throw(
        ArgumentError(
            "lags must be smaller than the number of observations " *
                "($n_observations)"
        )
    )
    return Int(lags)
end

function _validate_forecast_horizon(n_forecasts)
    n_forecasts isa Integer && !(n_forecasts isa Bool) ||
        throw(ArgumentError("n_forecasts must be an integer"))
    n_forecasts >= 0 ||
        throw(ArgumentError("n_forecasts must be non-negative"))
    return Int(n_forecasts)
end

function _prepare_alpha(alpha, n_vars, lags)
    size(alpha) == (n_vars, n_vars, lags) ||
        throw(
        DimensionMismatch(
            "autoregressive coefficients must have size " *
                "($n_vars, $n_vars, $lags); got $(size(alpha))"
        )
    )
    return reshape(alpha, n_vars, n_vars * lags)
end

function _get_lagged_data(data, lags)
    size(data, 1) >= lags ||
        throw(
        DimensionMismatch(
            "at least $lags observations are required to construct lags"
        )
    )
    return vec(data[end:-1:(end - lags + 1), :]')
end

function _innovation_factor(sigma, n_vars)
    size(sigma) == (n_vars, n_vars) ||
        throw(
        DimensionMismatch(
            "innovation covariance must have size ($n_vars, $n_vars); " *
                "got $(size(sigma))"
        )
    )
    all(isfinite, sigma) ||
        throw(ArgumentError("innovation covariance must contain only finite values"))

    symmetric_sigma = Symmetric((Matrix{Float64}(sigma) + sigma') / 2)
    decomposition = eigen(symmetric_sigma)
    covariance_scale = max(maximum(abs, decomposition.values), 1.0)
    tolerance = 100 * n_vars * eps(Float64) * covariance_scale
    minimum(decomposition.values) >= -tolerance ||
        throw(ArgumentError("innovation covariance must be positive semidefinite"))

    standard_deviations = sqrt.(max.(decomposition.values, 0.0))
    return decomposition.vectors * Diagonal(standard_deviations)
end

function _generate_stochastic_epsilon(
        rng::AbstractRNG, n_vars, sigma
    )
    return _innovation_factor(sigma, n_vars) * randn(rng, n_vars)
end

function _generate_stochastic_epsilon(n_vars, sigma)
    return _generate_stochastic_epsilon(Random.default_rng(), n_vars, sigma)
end
