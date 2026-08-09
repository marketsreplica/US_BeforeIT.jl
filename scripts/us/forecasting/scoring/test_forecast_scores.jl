using Test

include(joinpath(@__DIR__, "USForecastScores.jl"))
using .USForecastScores

@testset "point scores and relative skill" begin
    actual = [1.0, 2.0, 4.0]
    forecast = [0.0, 3.0, 4.0]
    summary = point_scores(actual, forecast; mase_denominator = 0.5)

    @test summary.n == 3
    @test summary.mean_error == 0.0
    @test summary.rmse ≈ sqrt(2 / 3)
    @test summary.mae ≈ 2 / 3
    @test summary.median_absolute_error == 1.0
    @test summary.mase ≈ 4 / 3
    @test point_scores(actual, forecast).mase === nothing
    huge = point_scores([1.0e200, -1.0e200], [0.0, 0.0])
    @test huge.mean_error == 0.0
    @test huge.rmse ≈ 1.0e200
    @test huge.mae ≈ 1.0e200
    maximum_float = floatmax(Float64)
    sparse_extreme_actual = vcat(maximum_float, zeros(15))
    sparse_extreme_forecast = vcat(-maximum_float, zeros(15))
    sparse_extreme = point_scores(
        sparse_extreme_actual,
        sparse_extreme_forecast
    )
    sparse_extreme_reference = setprecision(8192) do
        error = BigFloat(2) * BigFloat(maximum_float)
        return (
            mean = Float64(error / 16),
            rmse = Float64(sqrt(error^2 / 16)),
            mae = Float64(error / 16),
        )
    end
    @test sparse_extreme.mean_error == sparse_extreme_reference.mean
    @test sparse_extreme.rmse == sparse_extreme_reference.rmse
    @test sparse_extreme.mae == sparse_extreme_reference.mae
    @test sparse_extreme.median_absolute_error == 0.0
    cancellation = point_scores(
        [maximum_float, 3.0, -maximum_float, 0.0],
        zeros(4),
    )
    @test cancellation.mean_error == 0.75
    cancellation_permuted = point_scores(
        [maximum_float, -maximum_float, 0.0, 3.0],
        zeros(4),
    )
    @test cancellation_permuted.mean_error == 0.75

    @test seasonal_naive_scale([1.0, 2.0, 4.0]) == 1.5
    @test seasonal_naive_scale([1.0, 2.0, 5.0, 8.0]; seasonality = 2) == 5.0
    @test seasonal_naive_scale(
        [-maximum_float, maximum_float, maximum_float, maximum_float, maximum_float]
    ) == maximum_float / 2
    boundary_training = [
        -maximum_float,
        2.0,
        prevfloat(maximum_float),
        0.0,
    ]
    boundary_scale = seasonal_naive_scale(
        boundary_training;
        seasonality = 2,
    )
    @test boundary_scale == maximum_float
    @test point_scores(
        [maximum_float],
        [0.0];
        mase_denominator = boundary_scale,
    ).mase == 1.0
    @test relative_skill(0.8, 1.0) ≈ 0.2
    @test relative_skill(0.8, 1.0; percentage = true) ≈ 20.0

    @test_throws DimensionMismatch point_scores([1.0], [1.0, 2.0])
    @test_throws ArgumentError point_scores(Float64[], Float64[])
    @test_throws ArgumentError point_scores([1.0, NaN], [1.0, 2.0])
    @test_throws DomainError point_scores([1.0], [1.0]; mase_denominator = 0.0)
    @test_throws DomainError point_scores([floatmax(Float64)], [-floatmax(Float64)])
    @test_throws ArgumentError seasonal_naive_scale([1.0]; seasonality = 1)
    @test_throws ArgumentError seasonal_naive_scale([1.0, 2.0]; seasonality = true)
    @test_throws ArgumentError seasonal_naive_scale(
        [1.0, 2.0];
        seasonality = typemax(Int)
    )
    @test_throws ArgumentError seasonal_naive_scale(
        [1.0, 2.0];
        seasonality = big(typemax(Int)) + 1
    )
    @test_throws DomainError seasonal_naive_scale(fill(1.0, 3))
    @test_throws DomainError relative_skill(-1.0, 1.0)
    @test_throws DomainError relative_skill(1.0, 0.0)
    @test_throws DomainError relative_skill(1.0e308, 1.0e-308)
end

@testset "quantile, interval, and WIS scores" begin
    @test quantile_score(2.0, 1.0, 0.5) == 1.0
    @test quantile_score(0.0, 1.0, 0.9) ≈ 0.2
    @test interval_score(0.0, -1.0, 1.0, 0.2) == 2.0
    @test interval_score(-2.0, -1.0, 1.0, 0.2) == 12.0
    @test interval_score(2.0, -1.0, 1.0, 0.2) == 12.0
    tiny_alpha = nextfloat(0.0)
    @test interval_score(0.0, tiny_alpha, 1.0, tiny_alpha) == 3.0

    alphas = [0.1, 0.5]
    lowers = [-2.0, -1.0]
    uppers = [2.0, 1.0]
    @test weighted_interval_score(0.0, 0.0, lowers, uppers, alphas) ≈ 0.28
    @test weighted_interval_score(3.0, 0.0, lowers, uppers, alphas) ≈ 2.08
    maximum_float = floatmax(Float64)
    @test weighted_interval_score(
        -maximum_float,
        0.0,
        [0.0],
        [0.0],
        [0.1]
    ) == maximum_float
    finite_extreme_wis = weighted_interval_score(
        -maximum_float,
        maximum_float,
        [-maximum_float, -maximum_float, maximum_float],
        [maximum_float, maximum_float, maximum_float],
        [0.01, 0.02, 0.5]
    )
    reference_extreme_wis = setprecision(8192) do
        Float64(
            (BigFloat(303) / 100) * BigFloat(maximum_float) /
                (BigFloat(7) / 2)
        )
    end
    @test isfinite(finite_extreme_wis)
    @test finite_extreme_wis ≈ reference_extreme_wis rtol = 8eps(Float64)
    minimum_float = nextfloat(0.0)
    tiny_weight_wis = weighted_interval_score(
        maximum_float,
        maximum_float,
        [prevfloat(maximum_float)],
        [maximum_float],
        [minimum_float]
    )
    tiny_weight_reference = setprecision(8192) do
        Float64(
            BigFloat(minimum_float) *
                (
                BigFloat(maximum_float) -
                    BigFloat(prevfloat(maximum_float))
            ) / 2 /
                (BigFloat(3) / 2)
        )
    end
    @test tiny_weight_wis == tiny_weight_reference
    @test tiny_weight_wis > 0
    @test weighted_interval_score(
        1.0,
        -maximum_float,
        [-maximum_float],
        [-prevfloat(maximum_float)],
        [0.5],
    ) == maximum_float

    @test_throws ArgumentError quantile_score(1.0, 1.0, 0.0)
    @test_throws ArgumentError interval_score(1.0, 2.0, 1.0, 0.1)
    @test_throws DimensionMismatch weighted_interval_score(
        0.0,
        0.0,
        [-1.0],
        [1.0, 2.0],
        [0.1]
    )
    @test_throws ArgumentError weighted_interval_score(
        0.0,
        0.0,
        [-1.0, -2.0],
        [1.0, 2.0],
        [0.1, 0.5]
    )
    @test_throws ArgumentError weighted_interval_score(
        0.0,
        0.0,
        [-2.0, -1.0],
        [2.0, 1.0],
        [0.5, 0.1]
    )
    @test_throws ArgumentError weighted_interval_score(
        0.0,
        10.0,
        [-2.0, -1.0],
        [2.0, 1.0],
        [0.1, 0.5]
    )
    @test_throws DomainError quantile_score(
        floatmax(Float64),
        -floatmax(Float64),
        0.5
    )
    @test_throws DomainError interval_score(
        0.0,
        -floatmax(Float64),
        floatmax(Float64),
        0.5
    )
end

@testset "CRPS and empirical PIT" begin
    @test ensemble_crps(1.0, [1.0]) == 0.0
    @test ensemble_crps(1.0, [0.0, 2.0]) ≈ 0.5
    @test ensemble_crps(3.0, [0.0, 2.0]) ≈ 1.5
    @test ensemble_crps(11.0, [10.0, 12.0]) ≈
        ensemble_crps(1.0, [0.0, 2.0])
    @test ensemble_crps(1.0e12 + 1, [1.0e12, 1.0e12 + 2]) ≈
        ensemble_crps(1.0, [0.0, 2.0])
    @test ensemble_crps(2.0, [0.0, 4.0]) ≈
        2 * ensemble_crps(1.0, [0.0, 2.0])

    pit = ensemble_pit_interval(1.0, [0.0, 1.0, 1.0, 2.0])
    @test pit.lower == 0.25
    @test pit.upper == 0.75
    @test pit.midpoint == 0.5

    @test_throws ArgumentError ensemble_crps(1.0, Float64[])
    @test_throws ArgumentError ensemble_crps(1.0, [0.0, Inf])
end

@testset "coverage and Brier scores" begin
    summary = coverage_summary(
        [0.0, -2.0, 2.0, 0.0],
        fill(-1.0, 4),
        fill(1.0, 4)
    )
    @test summary.n == 4
    @test summary.coverage == 0.5
    @test summary.mean_width == 2.0
    @test summary.below_rate == 0.25
    @test summary.above_rate == 0.25

    @test brier_score(true, 0.8) ≈ 0.04
    @test brier_score(0, 0.2) ≈ 0.04
    @test_throws ArgumentError brier_score(0.0, 0.2)
    @test_throws ArgumentError brier_score(1, 1.2)
    @test_throws DimensionMismatch coverage_summary([1.0], [0.0], [2.0, 3.0])
    @test_throws ArgumentError coverage_summary([1.0], [2.0], [0.0])
    @test_throws DomainError coverage_summary(
        [0.0],
        [-floatmax(Float64)],
        [floatmax(Float64)]
    )
end

@testset "energy score" begin
    draws = [
        0.0 0.0
        2.0 2.0
    ]
    score = energy_score([1.0, 1.0], draws; scales = [1.0, 1.0])
    @test score ≈ sqrt(2) / 2
    @test energy_score(
        [1.0],
        reshape([0.0, 2.0], :, 1);
        scales = [1.0]
    ) ≈ ensemble_crps(1.0, [0.0, 2.0])
    @test energy_score(
        [100.0, 1.0],
        [90.0 0.0; 110.0 2.0];
        scales = [10.0, 1.0]
    ) ≈ score

    @test_throws DimensionMismatch energy_score(
        [1.0, 2.0],
        reshape([1.0, 2.0], :, 1);
        scales = [1.0, 1.0]
    )
    @test_throws DimensionMismatch energy_score(
        [1.0, 2.0],
        reshape([1.0, 2.0], 1, :);
        scales = [1.0]
    )
    @test_throws DomainError energy_score(
        [1.0, 2.0],
        reshape([1.0, 2.0], 1, :);
        scales = [1.0, 0.0]
    )
end

@testset "variogram score" begin
    actual = [0.0, 2.0]
    draws = [
        0.0 0.0
        2.0 2.0
    ]
    weights = [0.0 1.0; 1.0 0.0]
    @test variogram_score(
        actual,
        draws;
        centers = [0.0, 0.0],
        scales = [1.0, 1.0],
        weights = weights,
        order = 1.0
    ) == 4.0
    @test variogram_score(
        reverse(actual),
        reverse(draws; dims = 2);
        centers = [0.0, 0.0],
        scales = [1.0, 1.0],
        weights = weights,
        order = 1.0
    ) == 4.0
    shifted_actual = actual .+ [100.0, -50.0]
    shifted_draws = draws .+ reshape([100.0, -50.0], 1, :)
    @test variogram_score(
        shifted_actual,
        shifted_draws;
        centers = [100.0, -50.0],
        scales = [1.0, 1.0],
        weights = weights,
        order = 1.0
    ) == 4.0
    @test variogram_score(
        actual,
        draws;
        centers = [0.0, 0.0],
        scales = [1.0, 1.0],
        weights = weights,
        order = 2.0
    ) == 16.0

    @test_throws ArgumentError variogram_score(
        [1.0],
        reshape([0.0, 2.0], :, 1);
        centers = [0.0],
        scales = [1.0],
        weights = zeros(1, 1)
    )
    @test_throws ArgumentError variogram_score(
        actual,
        draws;
        centers = [0.0, 0.0],
        scales = [1.0, 1.0],
        weights = [0.0 1.0; 0.0 0.0]
    )
    @test_throws ArgumentError variogram_score(
        actual,
        draws;
        centers = [0.0, 0.0],
        scales = [1.0, 1.0],
        weights = ones(2, 2)
    )
    @test_throws DomainError variogram_score(
        actual,
        draws;
        centers = [0.0, 0.0],
        scales = [1.0, 1.0],
        weights = zeros(2, 2)
    )
    @test_throws ArgumentError variogram_score(
        actual,
        draws;
        centers = [0.0, 0.0],
        scales = [1.0, 1.0],
        weights = weights,
        order = 0.0
    )
    @test_throws DimensionMismatch variogram_score(
        actual,
        draws;
        centers = [0.0],
        scales = [1.0, 1.0],
        weights = weights
    )
end
