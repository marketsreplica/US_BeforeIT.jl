using LinearAlgebra
using Random
using Statistics
using Test

if !isdefined(Main, :USForecastBenchmarks)
    include("USForecastBenchmarks.jl")
end
if !isdefined(USForecastBenchmarks, :DirectARSpec)
    Base.include(
        USForecastBenchmarks,
        joinpath(@__DIR__, "direct_ar.jl")
    )
end
using .USForecastBenchmarks

const DARB = USForecastBenchmarks

function direct_ar_sample(
        y_train;
        forecast_horizon = 4,
        x_train = nothing,
        x_future = nothing,
        origin_id = "direct-ar-fixture",
        forecast_offset = 0
    )
    observations = size(y_train, 1)
    return OriginData(
        origin_id = origin_id,
        origin_key = observations,
        training_keys = collect(1:observations),
        forecast_keys = collect(
            (observations + 1 + forecast_offset):
                (observations + forecast_horizon + forecast_offset)
        ),
        y_train = y_train,
        x_train = x_train,
        x_future = x_future
    )
end

@testset "DirectARSpec identity, constructor, and card" begin
    fixed_one = DARB.DirectARSpec(candidate_lags = 1)
    fixed_four = DARB.DirectARSpec(candidate_lags = [4])
    selected = DARB.DirectARSpec(
        candidate_lags = [8, 1, 4, 4],
        intercept = false
    )

    @test fixed_one.candidate_lags == [1]
    @test fixed_four.candidate_lags == [4]
    @test selected.candidate_lags == [1, 4, 8]
    @test model_id(fixed_one) ==
        "direct_univariate_ar_v1_fixed_p1_constant_joint_aligned_residual_gaussian_v1"
    @test model_id(fixed_one) != model_id(fixed_four)
    @test model_id(selected) ==
        "direct_univariate_ar_v1_bic_p1-4-8_no_constant_joint_aligned_residual_gaussian_v1"
    @test model_id(
        DARB.DirectARSpec(candidate_lags = [4, 1, 8], intercept = false)
    ) == model_id(selected)

    card = model_card(selected)
    @test card["model_id"] == model_id(selected)
    @test occursin("No dominance claim", card["comparative_claim"])
    @test occursin("horizon_major", card["density_vector_order"])
    @test length(card["literature"]) == 2
    @test occursin(
        "10.1016/j.jeconom.2005.07.020",
        first(card["literature"])
    )
    @test occursin(
        "10.1111/j.1467-6419.2007.00518.x",
        last(card["literature"])
    )

    @test_throws ArgumentError DARB.DirectARSpec(candidate_lags = Int[])
    @test_throws ArgumentError DARB.DirectARSpec(candidate_lags = [0, 1])
    @test_throws ArgumentError DARB.DirectARSpec(candidate_lags = [true])
    @test_throws ArgumentError DARB.DirectARSpec(candidate_lags = [1.0])
    @test_throws ArgumentError DARB.DirectARSpec(candidate_lags = 1.0)
    @test_throws ArgumentError DARB.DirectARSpec(candidate_lags = nothing)
    @test_throws ArgumentError DARB.DirectARSpec(intercept = 1)
end

@testset "known direct coefficients and point forecasts" begin
    intercept = 0.35
    persistence = -0.72
    observations = 48
    series = zeros(observations)
    series[1] = 2.4
    for time in 2:observations
        series[time] = intercept + persistence * series[time - 1]
    end

    for forecast_step in 1:4
        fit = DARB._fit_direct_ar(
            series,
            forecast_step,
            1,
            true,
            1
        )
        expected_intercept =
            intercept *
            sum(persistence^power for power in 0:(forecast_step - 1))
        @test fit.coefficients[1] ≈ expected_intercept atol = 1.0e-12
        @test fit.coefficients[2] ≈
            persistence^forecast_step atol = 1.0e-12
        @test maximum(abs, fit.residuals) < 1.0e-12
    end

    sample = direct_ar_sample(series; forecast_horizon = 4)
    run = run_benchmark(
        DARB.DirectARSpec(candidate_lags = 1),
        sample;
        n_draws = 0,
        seed = 19
    )
    @test run.status == :ok
    expected = zeros(4)
    current = series[end]
    for forecast_step in 1:4
        current = intercept + persistence * current
        expected[forecast_step] = current
    end
    @test vec(run.forecast.point) ≈ expected atol = 1.0e-12
    @test size(run.forecast.draws) == (4, 1, 0)
    @test run.forecast.diagnostics["selected_lags"] == ones(Int, 4, 1)
    @test run.forecast.diagnostics["density_covariance_status"] ==
        "not_requested"
end

@testset "horizon alignment and origin-information firewall" begin
    series = collect(1.0:10.0)
    design, response, origins = DARB._direct_training_matrices(
        series,
        3,
        2,
        false,
        4
    )
    @test origins == collect(4:7)
    @test design == [
        4.0 3.0
        5.0 4.0
        6.0 5.0
        7.0 6.0
    ]
    @test response == [7.0, 8.0, 9.0, 10.0]
    @test DARB._direct_regressor(series, 10, 3, true) ==
        [1.0, 10.0, 9.0, 8.0]

    rng = MersenneTwister(49)
    training = randn(rng, 100, 2)
    original = direct_ar_sample(
        training;
        forecast_horizon = 3,
        forecast_offset = 0
    )
    relabeled_future = direct_ar_sample(
        training;
        forecast_horizon = 3,
        forecast_offset = 100
    )
    spec = DARB.DirectARSpec(candidate_lags = 1)
    original_run = run_benchmark(spec, original; seed = 5)
    relabeled_run = run_benchmark(spec, relabeled_future; seed = 5)
    @test original_run.status == :ok
    @test relabeled_run.status == :ok
    @test original_run.forecast.point == relabeled_run.forecast.point
    @test !hasfield(OriginData, :y_future)
    @test original_run.forecast.diagnostics["future_exogenous_used"] ==
        false

    with_x = direct_ar_sample(
        training;
        forecast_horizon = 3,
        x_train = randn(rng, 100, 1),
        x_future = randn(rng, 3, 1)
    )
    rejected = run_benchmark(spec, with_x; seed = 5)
    @test rejected.status == :failed
    @test rejected.failure.code == :invalid_input
    @test occursin("rejects x_train", rejected.failure.message)
end

@testset "BIC uses a common candidate window within each horizon" begin
    rng = MersenneTwister(344)
    observations = 180
    series = zeros(observations)
    for time in 5:observations
        series[time] =
            0.45 * series[time - 1] -
            0.3 * series[time - 4] +
            0.2 * randn(rng)
    end
    forecast_step = 3
    candidates = [1, 4]
    selected, scores = DARB._direct_select_lag(
        series,
        forecast_step,
        candidates,
        true,
        maximum(candidates)
    )
    fit_one = DARB._fit_direct_ar(
        series,
        forecast_step,
        1,
        true,
        maximum(candidates)
    )
    fit_four = DARB._fit_direct_ar(
        series,
        forecast_step,
        4,
        true,
        maximum(candidates)
    )
    @test length(fit_one.response) == length(fit_four.response)
    @test first(fit_one.origins) == first(fit_four.origins) == 4
    @test last(fit_one.origins) ==
        last(fit_four.origins) ==
        observations - forecast_step
    for (lag, fit) in ((1, fit_one), (4, fit_four))
        rows = length(fit.residuals)
        parameters = lag + 1
        manual_bic =
            rows *
            log(max(sum(abs2, fit.residuals) / rows, eps(Float64))) +
            parameters * log(rows)
        @test scores[lag] ≈ manual_bic atol = 1.0e-12
    end
    @test selected == argmin(scores)

    sample = direct_ar_sample(series; forecast_horizon = 5)
    run = run_benchmark(
        DARB.DirectARSpec(candidate_lags = 1:4),
        sample;
        seed = 27
    )
    @test run.status == :ok
    expected_rows =
        reshape(
        [
            observations - forecast_step - 4 + 1
                for forecast_step in 1:5
        ],
        :,
        1
    )
    @test run.forecast.diagnostics["common_selection_rows"] ==
        expected_rows
    @test run.forecast.diagnostics[
        "common_selection_first_origin",
    ] == 4
end

@testset "joint residual covariance and reproducible coherent draws" begin
    rng = MersenneTwister(9201)
    observations = 220
    training = zeros(observations, 2)
    innovation_factor =
        cholesky(Symmetric([0.8 0.55; 0.55 0.65])).L
    for time in 2:observations
        innovation = innovation_factor * randn(rng, 2)
        training[time, 1] =
            0.62 * training[time - 1, 1] + innovation[1]
        training[time, 2] =
            0.25 * training[time - 1, 1] +
            0.48 * training[time - 1, 2] +
            innovation[2]
    end
    forecast_horizon = 3
    sample = direct_ar_sample(
        training;
        forecast_horizon = forecast_horizon
    )
    spec = DARB.DirectARSpec(candidate_lags = 1)
    baseline = run_benchmark(spec, sample; n_draws = 8_000, seed = 404)
    repeated =
        run_benchmark(spec, sample; n_draws = 8_000, seed = 404)
    changed_seed =
        run_benchmark(spec, sample; n_draws = 8_000, seed = 405)

    @test baseline.status == :ok
    @test baseline.forecast.point == repeated.forecast.point
    @test baseline.forecast.draws == repeated.forecast.draws
    @test baseline.forecast.point == changed_seed.forecast.point
    @test baseline.forecast.draws != changed_seed.forecast.draws
    @test size(baseline.forecast.draws) == (3, 2, 8_000)
    @test all(isfinite, baseline.forecast.draws)
    @test baseline.forecast.diagnostics["joint_residual_rank"] == 6
    @test baseline.forecast.diagnostics["joint_residual_dimensions"] == 6
    @test !baseline.forecast.diagnostics[
        "parameter_uncertainty_in_draws",
    ]

    draw_errors = Matrix{Float64}(undef, 8_000, 6)
    for draw in 1:8_000
        for forecast_step in 1:3
            for variable in 1:2
                column = (forecast_step - 1) * 2 + variable
                draw_errors[draw, column] =
                    baseline.forecast.draws[forecast_step, variable, draw] -
                    baseline.forecast.point[forecast_step, variable]
            end
        end
    end
    empirical_covariance = cov(draw_errors)
    fitted_covariance =
        baseline.forecast.diagnostics["joint_residual_covariance"]
    @test empirical_covariance ≈
        fitted_covariance rtol = 0.06 atol = 0.035
    @test abs(fitted_covariance[1, 3]) > 0.1
    @test abs(empirical_covariance[1, 3]) > 0.08

    residuals, origins = DARB._direct_joint_residuals(
        training,
        baseline.forecast.diagnostics["coefficients_by_horizon_target"],
        baseline.forecast.diagnostics["selected_lags"],
        true,
        forecast_horizon
    )
    @test first(origins) == 1
    @test last(origins) == observations - forecast_horizon
    @test size(residuals) == (observations - forecast_horizon, 6)
end

@testset "structured insufficient-sample and rank failures" begin
    too_short = direct_ar_sample(
        randn(MersenneTwister(1), 9, 1);
        forecast_horizon = 4
    )
    lag_four = run_benchmark(
        DARB.DirectARSpec(candidate_lags = 4),
        too_short
    )
    @test lag_four.status == :failed
    @test lag_four.failure.code == :invalid_input
    @test occursin("common lag-selection rows", lag_four.failure.message)

    rng = MersenneTwister(2)
    density_short_training = randn(rng, 9, 2)
    density_short_sample = direct_ar_sample(
        density_short_training;
        forecast_horizon = 3
    )
    spec = DARB.DirectARSpec(candidate_lags = 1)
    point_only = run_benchmark(spec, density_short_sample)
    density_run = run_benchmark(
        spec,
        density_short_sample;
        n_draws = 10,
        seed = 3
    )
    @test point_only.status == :ok
    @test density_run.status == :failed
    @test density_run.failure.code == :invalid_input
    @test occursin(
        "more aligned residual origins",
        density_run.failure.message
    )

    duplicated = randn(rng, 80)
    rank_deficient_sample = direct_ar_sample(
        hcat(duplicated, duplicated);
        forecast_horizon = 3
    )
    rank_failure = run_benchmark(
        spec,
        rank_deficient_sample;
        n_draws = 10,
        seed = 4
    )
    @test rank_failure.status == :failed
    @test rank_failure.failure.code == :invalid_input
    @test occursin("rank deficient", rank_failure.failure.message)

    constant_sample = direct_ar_sample(
        ones(40, 1);
        forecast_horizon = 2
    )
    singular_fit = run_benchmark(spec, constant_sample)
    @test singular_fit.status == :failed
    @test singular_fit.failure.code == :invalid_input
    @test occursin("no direct AR candidate", singular_fit.failure.message)
end
