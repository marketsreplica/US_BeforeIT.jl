"""
    bias_ttest(errors, h = 1;
        kernel = :bartlett,
        small_sample = true,
        reference = :t)

Test `H₀: E[errors] = 0` with a horizon-overlap HAC standard error. The
autocovariances use denominator `n`, Bartlett weights run through lag `h - 1`,
and the standard error of the mean is

`sqrt(long_run_variance / n)`.

With the default finite-sample factor `n / (n - 1)`, the `h = 1` statistic is
exactly the textbook one-sample t-statistic. `reference = :t` uses `t(n - 1)`;
set `reference = :normal` and/or `small_sample = false` for asymptotic
inference. Invalid, too-short, and degenerate samples throw explicit errors.
"""
function bias_ttest(
        errors::AbstractVector{<:Real},
        h::Integer = 1;
        kernel::Symbol = :bartlett,
        small_sample::Bool = true,
        reference::Symbol = :t
    )
    sample = _forecast_test_sample(errors, "errors"; minimum_length = 2)
    horizon = _forecast_test_horizon(h, length(sample); strict = true)
    reference in (:t, :normal) ||
        throw(ArgumentError("reference must be :t or :normal"))

    long_run_variance =
        _forecast_hac_long_run_variance(sample, horizon - 1; kernel)
    if small_sample
        long_run_variance *= length(sample) / (length(sample) - 1)
    end

    statistic = mean(sample) / sqrt(long_run_variance / length(sample))
    p_value = _forecast_two_sided_pvalue(statistic, reference, length(sample))
    return statistic, p_value
end
