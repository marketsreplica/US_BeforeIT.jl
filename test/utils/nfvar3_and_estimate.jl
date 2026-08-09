import BeforeIT as Bit

using LinearAlgebra, MAT, Random, Statistics, Test

@testset "nfvar3" begin
    xxi = [[0.2, -0.5] [-0.5, 1.5]]
    u = [0, 0, 0, 0]

    y = Matrix{Float64}([1.0; 2.0; 3.0; 4.0; 5.0][:, :])
    var_ = Bit.rfvar3(y, 1, ones(size(y, 1), 1))

    @test isapprox(var_.Bx[1, 1], 1.0)
    @test isapprox(var_.By[1], 1.0)
    @test isapprox(var_.xxi, xxi)
    @test isapprox(var_.u, u; atol = 1.0e-14)
end

@testset "estimate" begin
    dir = @__DIR__

    init_conds = Bit.AUSTRIA2010Q1.initial_conditions #matopen(joinpath(dir, "../data/austria/initial_conditions/2010Q1.mat"))

    Y = init_conds["Y"]

    Random.seed!(123)
    alpha, beta, epsilon_ = Bit.estimate(log.(Y))

    @test isapprox(alpha, 0.971001709000414)
    @test isapprox(beta, 0.344659199612863)
    @test isapprox(epsilon_, -0.00415932810164292)

    Random.seed!(123)
    Yvec = vec(Y)
    alpha, beta, epsilon_ = Bit.estimate(log.(Yvec))
    @test isapprox(alpha, 0.971001709000414)
    @test isapprox(beta, 0.344659199612863)
    @test isapprox(epsilon_, -0.00415932810164292)

    dummy_series = [
        9.567778424837963
        9.574191416943812
        9.580605059126121
        9.588931171444848
        9.600311304740346
        9.604640931220233
        9.613107726219265
        9.618230372010803
        9.626726085704139
        9.642208926006326
        9.641763844732605
        9.649690917106851
    ]

    alpha_e = 0.984009645632709
    beta_e = 0.161039024858073
    sigma_e = 0.004012824377165
    epsilon_e = [
        -0.001633865231344
        -0.001530669138557
        0.000484357409141
        0.003671515872391
        -0.003197018579078
        0.001009382201758
        -0.002199379953346
        0.001255600869955
        0.008378576951367
        -0.007301768521497
        0.00106326811918
    ]

    alpha, beta, sigma, epsilon_ = Bit.estimate_for_calibration_script(dummy_series)

    @test isapprox(alpha, alpha_e)
    @test isapprox(beta, beta_e)
    @test isapprox(sigma, sigma_e)
    @test isapprox(epsilon_, epsilon_e)
end

@testset "VAR and VARX helpers" begin
    function generate_var1(alpha, intercept, initial_value, n_observations)
        data = zeros(n_observations, length(initial_value))
        data[1, :] .= initial_value
        for t in 2:n_observations
            data[t, :] .= alpha * data[t - 1, :] .+ intercept
        end
        return data
    end

    function generate_varx(
            alpha,
            gamma,
            intercept,
            exogenous,
            initial_value
        )
        data = zeros(size(exogenous, 1), length(initial_value))
        data[1, :] .= initial_value
        for t in 2:size(exogenous, 1)
            data[t, :] .=
                alpha * data[t - 1, :] +
                gamma * exogenous[t, :] +
                intercept
        end
        return data
    end

    @testset "textbook VAR coefficients and forecasts" begin
        alpha_no_intercept_1 = [0.35 0.1; -0.2 0.25]
        alpha_no_intercept_2 = [0.15 -0.05; 0.08 0.12]
        full_data = zeros(35, 2)
        full_data[1, :] .= [1.0, -0.2]
        full_data[2, :] .= [0.3, 0.8]
        for t in 3:size(full_data, 1)
            full_data[t, :] .=
                alpha_no_intercept_1 * full_data[t - 1, :] +
                alpha_no_intercept_2 * full_data[t - 2, :]
        end

        training_data = full_data[1:30, :]
        alpha, beta, sigma, residuals =
            Bit.estimate_VAR(training_data; lags = 2)
        @test alpha[:, :, 1] ≈ alpha_no_intercept_1 atol = 1.0e-12
        @test alpha[:, :, 2] ≈ alpha_no_intercept_2 atol = 1.0e-12
        @test isempty(beta)
        @test size(sigma) == (2, 2)
        @test size(residuals) == (28, 2)
        @test Bit.forecast_k_steps_VAR(training_data, 5; lags = 2) ≈
            full_data[31:35, :] atol = 1.0e-12

        alpha_with_intercept = [0.3 -0.4; 0.5 0.2]
        intercept = [1.0, -0.3]
        full_data_with_intercept = generate_var1(
            alpha_with_intercept, intercept, [-0.6, 0.8], 29
        )
        training_data_with_intercept = full_data_with_intercept[1:25, :]
        alpha, beta, _, _ = Bit.estimate_VAR(
            training_data_with_intercept; intercept = true
        )
        @test alpha[:, :, 1] ≈ alpha_with_intercept atol = 1.0e-12
        @test vec(beta) ≈ intercept atol = 1.0e-12
        @test Bit.forecast_k_steps_VAR(
            training_data_with_intercept, 4; intercept = true
        ) ≈ full_data_with_intercept[26:29, :] atol = 1.0e-12

        rng_after_forecast = MersenneTwister(404)
        untouched_rng = MersenneTwister(404)
        deterministic_forecast = Bit.forecast_k_steps_VAR(
            rng_after_forecast, training_data, 5; lags = 2
        )
        @test deterministic_forecast ==
            Bit.forecast_k_steps_VAR(training_data, 5; lags = 2)
        @test rand(rng_after_forecast) == rand(untouched_rng)
        @test size(Bit.forecast_k_steps_VAR(training_data, 0; lags = 2)) ==
            (0, 2)
    end

    @testset "textbook VARX coefficients and forecasts" begin
        n_observations = 70
        horizon = 5
        time = collect(1.0:(n_observations + horizon))
        alpha = [0.35 0.1; -0.2 0.25]

        exogenous_no_intercept = hcat(
            sin.(0.7 .* time),
            cos.(0.31 .* time) .+ 0.01 .* time
        )
        gamma_no_intercept = [0.8 -0.3; 0.2 0.6]
        full_data_no_intercept = generate_varx(
            alpha,
            gamma_no_intercept,
            zeros(2),
            exogenous_no_intercept,
            [0.2, -0.7]
        )
        training_data_no_intercept =
            full_data_no_intercept[1:n_observations, :]

        alpha_hat, beta_hat, gamma_hat, _, residuals =
            Bit.estimate_VARX(
            training_data_no_intercept,
            exogenous_no_intercept[1:n_observations, :]
        )
        @test alpha_hat[:, :, 1] ≈ alpha atol = 1.0e-12
        @test isempty(beta_hat)
        @test size(gamma_hat) == size(gamma_no_intercept)
        @test gamma_hat ≈ gamma_no_intercept atol = 1.0e-12
        @test size(residuals) == (n_observations - 1, 2)
        @test Bit.forecast_k_steps_VARX(
            training_data_no_intercept,
            exogenous_no_intercept,
            horizon
        ) ≈ full_data_no_intercept[
            (n_observations + 1):(n_observations + horizon), :,
        ] atol = 1.0e-12

        exogenous_with_intercept = reshape(
            sin.(0.37 .* time) .+ 0.003 .* time .^ 2, :, 1
        )
        gamma_with_intercept = reshape([0.75, -0.45], 2, 1)
        intercept = [0.4, -0.25]
        full_data_with_intercept = generate_varx(
            alpha,
            gamma_with_intercept,
            intercept,
            exogenous_with_intercept,
            [-0.1, 0.6]
        )
        training_data_with_intercept =
            full_data_with_intercept[1:n_observations, :]

        alpha_hat, beta_hat, gamma_hat, _, _ = Bit.estimate_VARX(
            training_data_with_intercept,
            exogenous_with_intercept[1:n_observations, :];
            intercept = true
        )
        @test alpha_hat[:, :, 1] ≈ alpha atol = 1.0e-11
        @test beta_hat ≈ intercept atol = 1.0e-11
        @test gamma_hat ≈ gamma_with_intercept atol = 1.0e-11
        @test Bit.forecast_k_steps_VARX(
            training_data_with_intercept,
            vec(exogenous_with_intercept),
            horizon;
            intercept = true
        ) ≈ full_data_with_intercept[
            (n_observations + 1):(n_observations + horizon), :,
        ] atol = 2.0e-11
    end

    @testset "joint stochastic innovation covariance" begin
        data_rng = MersenneTwister(20260805)
        alpha = [0.25 0.08; -0.12 0.3]
        target_covariance = [1.0 0.72; 0.72 1.4]
        innovation_factor = cholesky(Symmetric(target_covariance)).L
        training_data = zeros(800, 2)
        for t in 2:size(training_data, 1)
            training_data[t, :] .=
                alpha * training_data[t - 1, :] +
                innovation_factor * randn(data_rng, 2)
        end

        alpha_hat, _, fitted_covariance, _ =
            Bit.estimate_VAR(training_data)
        @test fitted_covariance[1, 2] > 0.5

        horizon = 12_000
        stochastic_forecast = Bit.forecast_k_steps_VAR(
            MersenneTwister(7788),
            training_data,
            horizon;
            stochastic = true
        )
        repeated_forecast = Bit.forecast_k_steps_VAR(
            MersenneTwister(7788),
            training_data,
            horizon;
            stochastic = true
        )
        @test stochastic_forecast == repeated_forecast

        innovations = zeros(horizon, 2)
        previous_value = copy(training_data[end, :])
        for t in 1:horizon
            innovations[t, :] .=
                stochastic_forecast[t, :] -
                alpha_hat[:, :, 1] * previous_value
            previous_value .= stochastic_forecast[t, :]
        end
        empirical_covariance = cov(innovations)
        @test empirical_covariance ≈ fitted_covariance rtol = 0.04 atol = 0.015
        @test empirical_covariance[1, 2] ≈ fitted_covariance[1, 2] rtol = 0.04
    end

    @testset "input validation" begin
        valid_data = [
            1.0 0.2
            0.7 0.1
            0.4 -0.1
            0.2 -0.2
        ]
        valid_exogenous = reshape(collect(1.0:6.0), :, 1)

        @test_throws ArgumentError Bit.estimate_VAR(valid_data; lags = 0)
        @test_throws ArgumentError Bit.estimate_VAR(valid_data; lags = 4)
        @test_throws ArgumentError Bit.estimate_VAR(valid_data; lags = 1.5)
        @test_throws ArgumentError Bit.forecast_k_steps_VAR(valid_data, -1)
        @test_throws ArgumentError Bit.forecast_k_steps_VAR(valid_data, 1.5)
        @test_throws ArgumentError Bit.forecast_k_steps_VAR(
            zeros(4, 2, 1), 1
        )
        @test_throws ArgumentError Bit.estimate_VAR(
            [
                1.0 NaN
                2.0 3.0
            ]
        )

        @test_throws DimensionMismatch Bit.estimate_VARX(
            valid_data, valid_exogenous[1:3, :]
        )
        @test_throws ArgumentError Bit.estimate_VARX(
            valid_data, zeros(4, 0)
        )
        @test_throws DimensionMismatch Bit.forecast_k_steps_VARX(
            valid_data, valid_exogenous[1:5, :], 2
        )
        @test_throws DimensionMismatch Bit.forecast_k_steps_VARX(
            valid_data, vcat(valid_exogenous, [7.0;;]), 2
        )
        @test size(
            Bit.forecast_k_steps_VARX(
                valid_data, valid_exogenous[1:4, :], 0
            )
        ) == (0, 2)
    end
end
