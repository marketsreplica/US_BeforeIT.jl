"""
    dmtest_modified(e1, e2, h = 1;
        kernel = :bartlett,
        small_sample = :hln,
        reference = :auto)

Compute the two-sided Diebold-Mariano test of equal squared-error predictive
accuracy. The loss differential is `dₜ = e1ₜ² - e2ₜ²`, so a positive statistic
means that the second forecast has the smaller average squared error.

For an `h`-step forecast, the long-run variance estimate uses lags
`0:(h - 1)`. `kernel = :bartlett` applies Newey-West weights
`1 - lag / h`; `kernel = :uniform` applies unit weights. The statistic is

`mean(d) / sqrt(long_run_variance / n)`.

By default, the Harvey-Leybourne-Newbold (`small_sample = :hln`) multiplier is
applied and the p-value uses a Student `t(n - 1)` reference distribution.
Use `small_sample = :none` and/or `reference = :normal` for the corresponding
asymptotic versions.

The positional call and three-value argument convention of the previous
implementation are preserved. Invalid, non-finite, too-short, and degenerate
samples throw instead of silently changing the variance estimator.
"""
function dmtest_modified(
        e1::AbstractVector{<:Real},
        e2::AbstractVector{<:Real},
        h::Integer = 1;
        kernel::Symbol = :bartlett,
        small_sample::Symbol = :hln,
        reference::Symbol = :auto
    )
    length(e1) == length(e2) ||
        throw(DimensionMismatch("forecast-error vectors must have equal length"))
    errors1 = _forecast_test_sample(e1, "e1"; minimum_length = 2)
    errors2 = _forecast_test_sample(e2, "e2"; minimum_length = 2)
    horizon = _forecast_test_horizon(h, length(errors1); strict = small_sample == :hln)
    small_sample in (:hln, :none) ||
        throw(ArgumentError("small_sample must be :hln or :none"))

    differential = abs2.(errors1) .- abs2.(errors2)
    variance = _forecast_hac_long_run_variance(differential, horizon - 1; kernel)
    statistic = mean(differential) / sqrt(variance / length(differential))

    if small_sample == :hln
        n = length(differential)
        correction = sqrt((n + 1 - 2horizon + horizon * (horizon - 1) / n) / n)
        statistic *= correction
    end

    resolved_reference = reference == :auto ? (small_sample == :hln ? :t : :normal) : reference
    p_value = _forecast_two_sided_pvalue(statistic, resolved_reference, length(differential))
    return statistic, p_value
end

function _forecast_test_sample(
        values::AbstractVector{<:Real},
        name::AbstractString;
        minimum_length::Integer
    )
    length(values) >= minimum_length ||
        throw(ArgumentError("$name must contain at least $minimum_length observations"))
    sample = Float64.(values)
    all(isfinite, sample) || throw(ArgumentError("$name must contain only finite values"))
    return sample
end

function _forecast_test_horizon(h::Integer, n::Integer; strict::Bool)
    h isa Bool && throw(ArgumentError("forecast horizon must be an integer, not Bool"))
    h >= 1 || throw(ArgumentError("forecast horizon must be at least 1"))
    valid = strict ? h < n : h <= n
    relation = strict ? "smaller than" : "no greater than"
    valid || throw(ArgumentError("forecast horizon must be $relation the sample size ($n)"))
    return Int(h)
end

function _forecast_kernel_weight(kernel::Symbol, lag::Integer, maxlag::Integer)
    kernel == :bartlett && return 1 - lag / (maxlag + 1)
    kernel == :uniform && return 1.0
    throw(ArgumentError("kernel must be :bartlett or :uniform"))
end

function _forecast_hac_long_run_variance(
        values::AbstractVector{<:Real},
        maxlag::Integer;
        kernel::Symbol
    )
    n = length(values)
    0 <= maxlag < n ||
        throw(ArgumentError("HAC lag must be nonnegative and smaller than the sample size"))
    _forecast_kernel_weight(kernel, 0, maxlag)

    centered = Float64.(values) .- mean(values)
    autocovariance = Vector{Float64}(undef, maxlag + 1)
    for lag in 0:maxlag
        autocovariance[lag + 1] =
            dot(view(centered, (lag + 1):n), view(centered, 1:(n - lag))) / n
    end

    estimate = autocovariance[1]
    absolute_scale = abs(autocovariance[1])
    for lag in 1:maxlag
        weight = _forecast_kernel_weight(kernel, lag, maxlag)
        estimate += 2 * weight * autocovariance[lag + 1]
        absolute_scale += 2 * abs(weight * autocovariance[lag + 1])
    end

    isfinite(estimate) || throw(DomainError(estimate, "HAC long-run variance is not finite"))
    tolerance = 100 * eps(Float64) * absolute_scale
    estimate > tolerance || throw(
        DomainError(
            estimate,
            "HAC long-run variance is nonpositive or numerically degenerate; the test is undefined"
        )
    )
    return estimate
end

function _forecast_two_sided_pvalue(statistic::Real, reference::Symbol, n::Integer)
    reference == :normal && return 2 * ccdf(Normal(), abs(statistic))
    reference == :t && return 2 * ccdf(TDist(n - 1), abs(statistic))
    throw(ArgumentError("reference must be :auto, :normal, or :t"))
end
