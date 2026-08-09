import BeforeIT as Bit

using Distributions
using LinearAlgebra
using Random
using Statistics
using Test

@testset "Diebold-Mariano reference formulas" begin
    errors1 = [1.0, 2.0, 1.5, 3.0, 2.5, 4.0]
    errors2 = [1.2, 1.5, 2.0, 2.5, 3.0, 3.5]
    horizon = 2
    differential = errors1 .^ 2 .- errors2 .^ 2
    centered = differential .- mean(differential)
    n = length(differential)
    gamma0 = dot(centered, centered) / n
    gamma1 = dot(centered[2:end], centered[1:(end - 1)]) / n
    bartlett_lrv = gamma0 + 2 * (1 - 1 / horizon) * gamma1
    uncorrected = mean(differential) / sqrt(bartlett_lrv / n)
    hln = sqrt((n + 1 - 2horizon + horizon * (horizon - 1) / n) / n)
    expected_statistic = hln * uncorrected
    expected_p_value = 2 * ccdf(TDist(n - 1), abs(expected_statistic))

    statistic, p_value = Bit.dmtest_modified(errors1, errors2, horizon)
    @test statistic ≈ expected_statistic atol = 1.0e-12
    @test p_value ≈ expected_p_value atol = 1.0e-12

    asymptotic_statistic, asymptotic_p_value = Bit.dmtest_modified(
        errors1,
        errors2,
        horizon;
        small_sample = :none,
        reference = :normal
    )
    @test asymptotic_statistic ≈ uncorrected atol = 1.0e-12
    @test asymptotic_p_value ≈
        2 * ccdf(Normal(), abs(uncorrected)) atol = 1.0e-12

    # Unit-weighted autocovariances are available explicitly, but this sample
    # demonstrates why a negative estimate must not trigger a silent fallback.
    @test_throws DomainError Bit.dmtest_modified(
        errors1,
        errors2,
        horizon;
        kernel = :uniform
    )
end

@testset "Diebold-Mariano input and degeneracy checks" begin
    @test_throws DimensionMismatch Bit.dmtest_modified([1.0, 2.0], [1.0])
    @test_throws ArgumentError Bit.dmtest_modified([1.0], [2.0])
    @test_throws ArgumentError Bit.dmtest_modified([1.0, NaN, 2.0], [1.0, 1.0, 1.0])
    @test_throws ArgumentError Bit.dmtest_modified([1.0, 2.0], [2.0, 1.0], 0)
    @test_throws ArgumentError Bit.dmtest_modified([1.0, 2.0], [2.0, 1.0], 2)
    @test_throws ArgumentError Bit.dmtest_modified(
        [1.0, 2.0],
        [2.0, 1.0];
        small_sample = :invalid
    )
    @test_throws ArgumentError Bit.dmtest_modified(
        [1.0, 2.0, 3.0],
        [2.0, 1.0, 2.0];
        kernel = :invalid
    )
    @test_throws DomainError Bit.dmtest_modified([1.0, 2.0, 3.0], [1.0, 2.0, 3.0])
end

@testset "Forecast-bias t-test reference formulas" begin
    errors = [1.2, -0.4, 0.8, 1.0, -0.2, 0.5]
    n = length(errors)
    textbook_statistic = mean(errors) / (std(errors) / sqrt(n))
    textbook_p_value = 2 * ccdf(TDist(n - 1), abs(textbook_statistic))

    statistic, p_value = Bit.bias_ttest(errors)
    @test statistic ≈ textbook_statistic atol = 1.0e-12
    @test p_value ≈ textbook_p_value atol = 1.0e-12

    centered = errors .- mean(errors)
    gamma0 = dot(centered, centered) / n
    gamma1 = dot(centered[2:end], centered[1:(end - 1)]) / n
    finite_sample_lrv = n / (n - 1) * (gamma0 + gamma1)
    expected_hac_statistic = mean(errors) / sqrt(finite_sample_lrv / n)
    hac_statistic, hac_p_value = Bit.bias_ttest(errors, 2)
    @test hac_statistic ≈ expected_hac_statistic atol = 1.0e-12
    @test hac_p_value ≈
        2 * ccdf(TDist(n - 1), abs(expected_hac_statistic)) atol = 1.0e-12

    asymptotic_statistic, asymptotic_p_value = Bit.bias_ttest(
        errors,
        2;
        small_sample = false,
        reference = :normal
    )
    asymptotic_lrv = gamma0 + gamma1
    @test asymptotic_statistic ≈ mean(errors) / sqrt(asymptotic_lrv / n)
    @test asymptotic_p_value ≈
        2 * ccdf(Normal(), abs(asymptotic_statistic))
end

@testset "Forecast-bias input and degeneracy checks" begin
    @test_throws ArgumentError Bit.bias_ttest([1.0])
    @test_throws ArgumentError Bit.bias_ttest([1.0, Inf, 2.0])
    @test_throws ArgumentError Bit.bias_ttest([1.0, -1.0], 2)
    @test_throws ArgumentError Bit.bias_ttest([1.0, -1.0], 0)
    @test_throws ArgumentError Bit.bias_ttest([1.0, -1.0]; kernel = :invalid)
    @test_throws ArgumentError Bit.bias_ttest([1.0, -1.0]; reference = :invalid)
    @test_throws DomainError Bit.bias_ttest(fill(1.0, 8))
end

function classical_mz_reference(actual, forecast; robust::Bool)
    n = length(actual)
    design = hcat(ones(n), forecast)
    coefficients = design \ actual
    residuals = actual - design * coefficients
    bread = (design' * design) \ Matrix{Float64}(I, 2, 2)
    coefficient_covariance = if robust
        scores = design .* residuals
        n / (n - 2) * bread * (scores' * scores) * bread
    else
        sum(abs2, residuals) / (n - 2) * bread
    end
    difference = coefficients .- [0.0, 1.0]
    wald = dot(difference, coefficient_covariance \ difference)
    return coefficients, ccdf(FDist(2, n - 2), wald / 2)
end

@testset "Mincer-Zarnowitz classical and robust reference formulas" begin
    forecast = collect(1.0:8.0)
    actual = [1.2, 1.8, 3.4, 3.7, 5.1, 6.3, 6.8, 8.4]

    classical_coefficients, classical_p_value =
        classical_mz_reference(actual, forecast; robust = false)
    intercept, slope, p_value = Bit.mztest(
        actual,
        forecast;
        covariance = :homoskedastic,
        reference = :f
    )
    @test [intercept, slope] ≈ classical_coefficients atol = 1.0e-12
    @test p_value ≈ classical_p_value atol = 1.0e-12

    robust_coefficients, robust_p_value =
        classical_mz_reference(actual, forecast; robust = true)
    robust_intercept, robust_slope, robust_result_p_value =
        Bit.mztest(actual, forecast)
    @test [robust_intercept, robust_slope] ≈ robust_coefficients atol = 1.0e-12
    @test robust_result_p_value ≈ robust_p_value atol = 1.0e-12

    _, _, legacy_reference_p_value = Bit.mztest(
        actual,
        forecast;
        covariance = :homoskedastic,
        reference = :chisq
    )
    @test 0 <= legacy_reference_p_value <= 1
    @test legacy_reference_p_value != p_value
end

@testset "Mincer-Zarnowitz HAC simulation fixture" begin
    rng = MersenneTwister(20260805)
    n = 80
    forecast = 100 .+ cumsum(randn(rng, n))
    innovations = (0.3 .+ 0.01 .* (1:n)) .* randn(rng, n)
    errors = zeros(n)
    for index in 2:n
        errors[index] = 0.65 * errors[index - 1] + innovations[index]
    end
    actual = forecast + errors

    intercept, slope, hac_p_value = Bit.mztest(actual, forecast; horizon = 4)
    _, _, hc1_p_value = Bit.mztest(actual, forecast; covariance = :hc1)
    reference_coefficients = hcat(ones(n), forecast) \ actual
    @test [intercept, slope] ≈ reference_coefficients atol = 1.0e-10
    @test slope ≈ 1.0 atol = 0.1
    @test 0 <= hac_p_value <= 1
    @test 0 <= hc1_p_value <= 1
    @test hac_p_value != hc1_p_value
end

@testset "Mincer-Zarnowitz stable solve and failure visibility" begin
    forecast = 1.0e9 .+ collect(1.0:12.0)
    noise = [0.2, -0.1, 0.3, -0.2, 0.1, -0.3, 0.4, -0.2, 0.2, -0.1, 0.1, -0.4]
    actual = 4.0 .+ 1.25 .* forecast .+ noise
    intercept, slope, p_value = Bit.mztest(actual, forecast)
    @test isfinite(intercept)
    @test slope ≈ 1.25 atol = 0.05
    @test 0 <= p_value <= 1

    @test_throws DimensionMismatch Bit.mztest([1.0, 2.0, 3.0], [1.0, 2.0])
    @test_throws ArgumentError Bit.mztest([1.0, 2.0], [1.0, 2.0])
    @test_throws ArgumentError Bit.mztest([1.0, NaN, 3.0], [1.0, 2.0, 3.0])
    @test_throws ArgumentError Bit.mztest([1.0, 2.0, 3.0], fill(1.0, 3))
    @test_throws ArgumentError Bit.mztest(
        [1.0, 2.0, 3.0, 4.0],
        [1.0, 2.0, 3.0, 4.0];
        covariance = :invalid
    )
    @test_throws ArgumentError Bit.mztest(
        [1.0, 2.0, 3.0, 4.0],
        [1.0, 2.0, 3.0, 4.0];
        covariance = :hc1,
        horizon = 2
    )
    @test_throws DomainError Bit.mztest(
        [1.0, 2.0, 3.0, 4.0],
        [1.0, 2.0, 3.0, 4.0]
    )
end
