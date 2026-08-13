using Dates
using LinearAlgebra
using Random
using Statistics
using Test

include("USForecastBenchmarks.jl")
using .USForecastBenchmarks

function sample_for(
        y_train;
        horizon = 4,
        x_train = nothing,
        x_future = nothing,
        origin_id = "fixture-origin"
    )
    observations = size(y_train, 1)
    return OriginData(
        origin_id = origin_id,
        origin_key = observations,
        training_keys = collect(1:observations),
        forecast_keys = collect((observations + 1):(observations + horizon)),
        y_train = y_train,
        x_train = x_train,
        x_future = x_future
    )
end

include("test_bvar.jl")
include("test_semi_structural.jl")
include("test_direct_ar.jl")

@testset "origin information-set contract" begin
    dates = Date(2020, 3, 31):Month(3):Date(2021, 6, 30)
    sample = OriginData(
        origin_id = "2021Q2",
        origin_key = Date(2021, 6, 30),
        training_keys = collect(dates),
        forecast_keys = [Date(2021, 9, 30), Date(2021, 12, 31)],
        y_train = collect(1.0:length(dates)),
        x_train = collect(11.0:(10.0 + length(dates))),
        x_future = [20.0, 21.0],
        target_names = ["gdp"],
        predictor_names = ["survey"]
    )
    @test horizon(sample) == 2
    @test size(sample.y_train) == (length(dates), 1)
    @test size(sample.x_train) == (length(dates), 1)
    @test sample.forecast_keys == [
        Date(2021, 9, 30),
        Date(2021, 12, 31),
    ]
    @test sample.target_names == ["gdp"]
    @test sample.predictor_names == ["survey"]

    @test_throws ArgumentError OriginData(
        origin_id = "bad",
        origin_key = 3,
        training_keys = [1, 3, 2],
        forecast_keys = [4],
        y_train = [1.0, 2.0, 3.0]
    )
    @test_throws ArgumentError OriginData(
        origin_id = "bad",
        origin_key = 3,
        training_keys = [1, 2, 4],
        forecast_keys = [5],
        y_train = [1.0, 2.0, 3.0]
    )
    @test_throws ArgumentError OriginData(
        origin_id = "bad",
        origin_key = 3,
        training_keys = [1, 2, 3],
        forecast_keys = [3, 4],
        y_train = [1.0, 2.0, 3.0]
    )
    @test_throws DimensionMismatch OriginData(
        origin_id = "bad",
        origin_key = 3,
        training_keys = [1, 2, 3],
        forecast_keys = [4, 5],
        y_train = [1.0, 2.0, 3.0],
        x_train = [1.0, 2.0, 3.0],
        x_future = [4.0]
    )
    @test_throws ArgumentError OriginData(
        origin_id = "bad",
        origin_key = 3,
        training_keys = [1, 2, 3],
        forecast_keys = [4],
        y_train = [1.0, 2.0, 3.0],
        x_train = [1.0, 2.0, 3.0]
    )
end

@testset "naive known cases and horizon alignment" begin
    training = [
        1.0 10.0
        2.0 8.0
        4.0 7.0
        7.0 7.0
        11.0 8.0
        16.0 10.0
    ]
    sample = sample_for(training; horizon = 3)

    no_change = run_benchmark(NoChangeSpec(), sample)
    @test no_change.status == :ok
    @test no_change.failure === nothing
    @test no_change.forecast.forecast_keys == [7, 8, 9]
    @test size(no_change.forecast.point) == (3, 2)
    @test no_change.forecast.point == repeat(training[end:end, :], 3, 1)
    @test size(no_change.forecast.draws) == (3, 2, 0)

    drift = run_benchmark(DriftSpec(), sample)
    expected_drift = vec(mean(diff(training; dims = 1); dims = 1))
    @test drift.status == :ok
    @test drift.forecast.point[1, :] ≈ training[end, :] + expected_drift
    @test drift.forecast.point[3, :] ≈ training[end, :] + 3expected_drift

    historical_mean = run_benchmark(HistoricalMeanSpec(), sample)
    @test historical_mean.status == :ok
    @test historical_mean.forecast.point ==
        repeat(mean(training; dims = 1), 3, 1)

    seasonal_training = reshape(collect(1.0:12.0), :, 1)
    seasonal = run_benchmark(
        SeasonalNaiveSpec(4),
        sample_for(seasonal_training; horizon = 6)
    )
    @test seasonal.status == :ok
    @test vec(seasonal.forecast.point) ==
        [9.0, 10.0, 11.0, 12.0, 9.0, 10.0]
    @test model_card(SeasonalNaiveSpec(4))["model_id"] ==
        "naive_seasonal_4"
end

@testset "univariate AR training-only selection and known recursion" begin
    exact_ar = zeros(50, 1)
    exact_ar[1] = 1.2
    for time in 2:size(exact_ar, 1)
        exact_ar[time] = 0.35 + 0.72exact_ar[time - 1]
    end
    exact_run = run_benchmark(
        ARSpec(candidate_lags = [1]),
        sample_for(exact_ar; horizon = 4)
    )
    @test exact_run.status == :ok
    expected = zeros(4)
    previous = exact_ar[end]
    for step in eachindex(expected)
        expected[step] = 0.35 + 0.72previous
        previous = expected[step]
    end
    @test vec(exact_run.forecast.point) ≈ expected atol = 1.0e-10
    @test exact_run.forecast.diagnostics["selected_lags"] == [1]

    data_rng = MersenneTwister(1203)
    ar2 = zeros(600, 1)
    ar2[1:2] .= [0.2, -0.1]
    for time in 3:size(ar2, 1)
        ar2[time] =
            0.75ar2[time - 1] -
            0.48ar2[time - 2] +
            0.15randn(data_rng)
    end
    selected = run_benchmark(
        ARSpec(candidate_lags = 1:5),
        sample_for(ar2; horizon = 5)
    )
    @test selected.status == :ok
    @test selected.forecast.diagnostics["selected_lags"] == [2]
    @test selected.forecast.diagnostics["selection_rule"] ==
        "BIC_common_training_window"

    future_a = zeros(5, 1)
    future_b = fill(1.0e12, 5, 1)
    training_x = reshape(collect(1.0:600.0), :, 1)
    sample_a = sample_for(
        ar2;
        horizon = 5,
        x_train = training_x,
        x_future = future_a
    )
    sample_b = sample_for(
        ar2;
        horizon = 5,
        x_train = training_x,
        x_future = future_b
    )
    ar_a = run_benchmark(ARSpec(candidate_lags = 1:5), sample_a)
    ar_b = run_benchmark(ARSpec(candidate_lags = 1:5), sample_b)
    @test ar_a.forecast.point == ar_b.forecast.point
    @test ar_a.forecast.diagnostics["selected_lags"] ==
        ar_b.forecast.diagnostics["selected_lags"]
    @test !ar_a.forecast.diagnostics["future_exogenous_used"]
end

@testset "seeded density reproducibility" begin
    rng = MersenneTwister(99)
    training = cumsum(randn(rng, 80, 2); dims = 1)
    sample = sample_for(training; horizon = 8)

    first_run = run_benchmark(
        NoChangeSpec(),
        sample;
        n_draws = 40,
        seed = 778
    )
    repeated_run = run_benchmark(
        NoChangeSpec(),
        sample;
        n_draws = 40,
        seed = 778
    )
    different_seed = run_benchmark(
        NoChangeSpec(),
        sample;
        n_draws = 40,
        seed = 779
    )
    @test first_run.status == :ok
    @test first_run.forecast.point == repeated_run.forecast.point
    @test first_run.forecast.draws == repeated_run.forecast.draws
    @test first_run.forecast.draws != different_seed.forecast.draws

    ar_first = run_benchmark(
        ARSpec(candidate_lags = 1:4),
        sample;
        n_draws = 25,
        seed = 34
    )
    ar_second = run_benchmark(
        ARSpec(candidate_lags = 1:4),
        sample;
        n_draws = 25,
        seed = 34
    )
    @test ar_first.forecast.draws == ar_second.forecast.draws
    @test size(ar_first.forecast.draws) == (8, 2, 25)
end

@testset "BeforeIT VAR adapter covariance and reproducibility" begin
    rng = MersenneTwister(902)
    alpha = [0.3 0.08; -0.12 0.22]
    target_covariance = [0.7 0.5; 0.5 1.1]
    factor = cholesky(Symmetric(target_covariance)).L
    training = zeros(1_000, 2)
    for time in 2:size(training, 1)
        training[time, :] .=
            alpha * training[time - 1, :] + factor * randn(rng, 2)
    end
    sample = sample_for(training; horizon = 1)
    spec = BeforeITVARSpec(lags = 1, intercept = false)
    run = run_benchmark(spec, sample; n_draws = 4_000, seed = 7001)
    repeat_run =
        run_benchmark(spec, sample; n_draws = 4_000, seed = 7001)

    @test run.status == :ok
    @test run.forecast.draws == repeat_run.forecast.draws
    @test size(run.forecast.point) == (1, 2)
    @test size(run.forecast.draws) == (1, 2, 4_000)
    @test run.forecast.diagnostics["adapter"] ==
        "BeforeIT.forecast_k_steps_VAR"
    innovations =
        dropdims(run.forecast.draws; dims = 1) .-
        repeat(vec(run.forecast.point), 1, 4_000)
    empirical_covariance = cov(innovations; dims = 2)
    fitted_covariance =
        run.forecast.diagnostics["innovation_covariance"]
    @test empirical_covariance ≈ fitted_covariance rtol = 0.08 atol = 0.04
    @test empirical_covariance[1, 2] > 0.35
    @test model_card(spec)["density_rule"] ==
        "Recursive Gaussian draws using the fitted joint innovation covariance."
end

@testset "BeforeIT VARX explicit future-exogenous path" begin
    observations = 90
    forecast_horizon = 5
    all_times = collect(1.0:(observations + forecast_horizon))
    exogenous = reshape(
        sin.(0.31 .* all_times) .+ 0.004 .* all_times .^ 2,
        :,
        1
    )
    alpha = 0.45
    gamma = 0.8
    intercept = -0.2
    full_data = zeros(observations + forecast_horizon, 1)
    full_data[1] = 0.7
    for time in 2:length(full_data)
        full_data[time] =
            intercept +
            alpha * full_data[time - 1] +
            gamma * exogenous[time]
    end

    baseline_sample = sample_for(
        full_data[1:observations, :];
        horizon = forecast_horizon,
        x_train = exogenous[1:observations, :],
        x_future = exogenous[(observations + 1):end, :]
    )
    spec = BeforeITVARXSpec(lags = 1, intercept = true)
    baseline = run_benchmark(spec, baseline_sample)
    @test baseline.status == :ok
    @test baseline.forecast.point ≈
        full_data[(observations + 1):end, :] atol = 1.0e-10
    @test baseline.forecast.diagnostics["future_exogenous_used"]
    @test baseline.forecast.diagnostics["future_exogenous_rows"] ==
        forecast_horizon
    @test baseline.forecast.diagnostics[
        "fitted_exogenous_coefficients",
    ] ≈ reshape([gamma], 1, 1) atol = 1.0e-10

    changed_future = copy(exogenous[(observations + 1):end, :])
    changed_future[1, 1] += 10
    changed_sample = sample_for(
        full_data[1:observations, :];
        horizon = forecast_horizon,
        x_train = exogenous[1:observations, :],
        x_future = changed_future
    )
    changed = run_benchmark(spec, changed_sample)
    @test changed.status == :ok
    @test changed.forecast.point[1, 1] - baseline.forecast.point[1, 1] ≈
        10gamma atol = 1.0e-9
    @test changed.forecast.diagnostics[
        "fitted_exogenous_coefficients",
    ] == baseline.forecast.diagnostics[
        "fitted_exogenous_coefficients",
    ]

    missing_exogenous = run_benchmark(
        spec,
        sample_for(full_data[1:observations, :]; horizon = forecast_horizon)
    )
    @test missing_exogenous.status == :failed
    @test missing_exogenous.forecast === nothing
    @test missing_exogenous.failure.code == :invalid_input
    @test occursin("requires x_train", missing_exogenous.failure.message)
end

@testset "failures remain visible and model cards are complete" begin
    too_short = sample_for(reshape(collect(1.0:8.0), :, 1); horizon = 2)
    failed = run_benchmark(ARSpec(candidate_lags = 1:4), too_short)
    @test failed.status == :failed
    @test failed.forecast === nothing
    @test failed.failure !== nothing
    @test failed.failure.code == :invalid_input
    @test !isempty(failed.failure.exception_type)
    @test occursin("training rows", failed.failure.message)

    invalid_draw_count =
        run_benchmark(NoChangeSpec(), too_short; n_draws = -1)
    @test invalid_draw_count.status == :failed
    @test invalid_draw_count.failure.code == :invalid_input

    invalid_seed = run_benchmark(NoChangeSpec(), too_short; seed = -1)
    @test invalid_seed.status == :failed
    @test invalid_seed.failure.code == :invalid_input

    @test_throws ArgumentError ARSpec(candidate_lags = Int[])
    @test_throws ArgumentError SeasonalNaiveSpec(0)
    @test_throws ArgumentError BeforeITVARSpec(lags = 0)

    @test model_id(ARSpec(candidate_lags = [1], intercept = true)) !=
        model_id(ARSpec(candidate_lags = [1], intercept = false))
    @test model_id(ARSpec(candidate_lags = 1:4)) !=
        model_id(ARSpec(candidate_lags = 1:8))
    @test model_id(BeforeITVARSpec(intercept = true)) !=
        model_id(BeforeITVARSpec(intercept = false))
    @test model_id(BeforeITVARXSpec(lags = 1)) !=
        model_id(BeforeITVARXSpec(lags = 2))

    for spec in (
            NoChangeSpec(),
            DriftSpec(),
            HistoricalMeanSpec(),
            SeasonalNaiveSpec(4),
            ARSpec(),
            BVARSpec(),
            BeforeITVARSpec(),
            BeforeITVARXSpec(),
        )
        card = model_card(spec)
        @test card["model_id"] == model_id(spec)
        @test haskey(card, "estimation_information_set")
        @test haskey(card, "density_rule")
        @test haskey(card, "failure_policy")
        @test haskey(card, "seed_policy")
    end
end
