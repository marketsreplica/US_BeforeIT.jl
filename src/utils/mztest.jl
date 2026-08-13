"""
    mztest(y, forecast;
        covariance = :hac,
        horizon = 1,
        kernel = :bartlett,
        small_sample = true,
        reference = :f)

Run the Mincer-Zarnowitz regression

`yₜ = α + β forecastₜ + uₜ`

and jointly test `H₀: α = 0, β = 1`. The return value remains
`(intercept, slope, p_value)`.

The regression is solved on a centered and scaled forecast column rather than
by explicitly inverting `X'X`. The default covariance is a heteroskedasticity-
and-autocorrelation-consistent sandwich estimator with Bartlett weights through
lag `horizon - 1`; at `horizon = 1` this is HC1. Set `covariance = :hc0`,
`:hc1`, or `:homoskedastic` for those alternatives. `reference = :f` compares
the robust Wald statistic divided by two with `F(2, n - 2)`;
`reference = :chisq` provides the asymptotic Wald test used by the old
implementation.

Constant forecasts, invalid samples, and singular Wald covariance estimates
throw explicit errors.
"""
function mztest(
        y::AbstractVector{<:Real},
        forecast::AbstractVector{<:Real};
        covariance::Symbol = :hac,
        horizon::Integer = 1,
        kernel::Symbol = :bartlett,
        small_sample::Bool = true,
        reference::Symbol = :f
    )
    length(y) == length(forecast) ||
        throw(DimensionMismatch("actual and forecast vectors must have equal length"))
    actual = _forecast_test_sample(y, "y"; minimum_length = 3)
    predicted = _forecast_test_sample(forecast, "forecast"; minimum_length = 3)
    n = length(actual)
    k = 2

    covariance in (:hac, :hc0, :hc1, :homoskedastic) ||
        throw(ArgumentError("covariance must be :hac, :hc0, :hc1, or :homoskedastic"))
    reference in (:f, :chisq) ||
        throw(ArgumentError("reference must be :f or :chisq"))
    if covariance == :hac
        _forecast_test_horizon(horizon, n; strict = true)
        _forecast_kernel_weight(kernel, 0, horizon - 1)
    elseif horizon != 1
        throw(ArgumentError("horizon only applies when covariance = :hac"))
    end

    forecast_mean = mean(predicted)
    centered_forecast = predicted .- forecast_mean
    forecast_scale = sqrt(sum(abs2, centered_forecast) / n)
    isfinite(forecast_scale) && forecast_scale > 0 ||
        throw(
        ArgumentError(
            "forecast is constant or numerically unscalable, so the Mincer-Zarnowitz slope is unidentified"
        )
    )

    standardized_forecast = centered_forecast ./ forecast_scale
    design = hcat(ones(n), standardized_forecast)
    standardized_coefficients = design \ actual
    residuals = actual - design * standardized_coefficients
    residual_tolerance =
        100 * eps(Float64) * max(norm(actual), norm(design * standardized_coefficients))
    norm(residuals) > residual_tolerance || throw(
        DomainError(
            norm(residuals),
            "Mincer-Zarnowitz residual variance is numerically zero, so inference is undefined"
        )
    )

    covariance_standardized = _mz_coefficient_covariance(
        design,
        residuals,
        covariance,
        Int(horizon),
        kernel,
        small_sample
    )
    transformation = [
        1.0 -forecast_mean / forecast_scale
        0.0 1 / forecast_scale
    ]
    coefficients = transformation * standardized_coefficients

    # Under α = 0 and β = 1, the coefficients in the standardized regression
    # are (forecast_mean, forecast_scale). Evaluating the Wald statistic in this
    # well-conditioned parameterization avoids destroying precision when the
    # forecast level is large relative to its variation.
    difference =
        standardized_coefficients .- [forecast_mean, forecast_scale]
    eigenvalues = eigvals(covariance_standardized)
    covariance_scale = maximum(abs, eigenvalues)
    tolerance = 100 * eps(Float64) * covariance_scale
    minimum(eigenvalues) > tolerance || throw(
        DomainError(
            minimum(eigenvalues),
            "Mincer-Zarnowitz Wald covariance is singular or numerically degenerate"
        )
    )

    wald = dot(difference, covariance_standardized \ difference)
    wald >= -100 * eps(Float64) * max(abs(wald), 1.0) ||
        throw(DomainError(wald, "Mincer-Zarnowitz Wald statistic is negative"))
    wald = max(wald, 0.0)
    p_value = if reference == :f
        ccdf(FDist(2, n - k), wald / 2)
    else
        ccdf(Chisq(2), wald)
    end
    return coefficients[1], coefficients[2], p_value
end

function _mz_coefficient_covariance(
        design::Matrix{Float64},
        residuals::Vector{Float64},
        covariance::Symbol,
        horizon::Int,
        kernel::Symbol,
        small_sample::Bool
    )
    n, k = size(design)
    gram_factor = cholesky(Symmetric(design' * design))
    bread = gram_factor \ Matrix{Float64}(I, k, k)

    if covariance == :homoskedastic
        residual_variance = sum(abs2, residuals) / (n - k)
        return residual_variance * bread
    end

    scores = design .* residuals
    meat = scores' * scores
    if covariance == :hac
        maxlag = horizon - 1
        for lag in 1:maxlag
            weight = _forecast_kernel_weight(kernel, lag, maxlag)
            cross_product =
                view(scores, (lag + 1):n, :)' * view(scores, 1:(n - lag), :)
            meat += weight * (cross_product + cross_product')
        end
    end

    finite_sample_factor = if covariance == :hc1 || (covariance == :hac && small_sample)
        n / (n - k)
    else
        1.0
    end
    return Symmetric(finite_sample_factor * bread * meat * bread)
end
