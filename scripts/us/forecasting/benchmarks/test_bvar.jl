using LinearAlgebra
using Random
using Statistics
using Test

if !isdefined(Main, :USForecastBenchmarks)
    include("USForecastBenchmarks.jl")
end
using .USForecastBenchmarks

function bvar_sample(
        y_train;
        forecast_horizon = 4,
        x_train = nothing,
        x_future = nothing,
        origin_id = "bvar-fixture"
    )
    observations = size(y_train, 1)
    return OriginData(
        origin_id = origin_id,
        origin_key = observations,
        training_keys = collect(1:observations),
        forecast_keys =
            collect((observations + 1):(observations + forecast_horizon)),
        y_train = y_train,
        x_train = x_train,
        x_future = x_future
    )
end

@testset "MNIW analytic posterior and inverse-Wishart moments" begin
    design = [
        1.0 0.0
        1.0 1.0
        1.0 2.0
        1.0 3.0
        1.0 4.0
    ]
    response = [
        0.5 -0.2
        1.3 0.4
        1.8 0.1
        2.9 0.9
        3.7 1.1
    ]
    prior_mean = [0.1 -0.1; 0.8 0.0]
    prior_precision = [2.0 0.0; 0.0 3.0]
    prior_scale = [2.0 0.25; 0.25 1.5]
    prior_dof = 5

    posterior = USForecastBenchmarks._mniw_posterior(
        response,
        design,
        prior_mean,
        prior_precision,
        prior_scale,
        prior_dof
    )
    posterior_precision = prior_precision + design' * design
    expected_row_covariance =
        posterior_precision \ Matrix{Float64}(I, 2, 2)
    expected_mean =
        posterior_precision \
        (prior_precision * prior_mean + design' * response)
    residuals = response - design * expected_mean
    prior_distance = expected_mean - prior_mean
    expected_scale =
        prior_scale +
        residuals' * residuals +
        prior_distance' * prior_precision * prior_distance

    @test size(posterior.mean) == (2, 2)
    @test size(posterior.row_covariance) == (2, 2)
    @test size(posterior.scale) == (2, 2)
    @test posterior.mean ≈ expected_mean atol = 1.0e-12
    @test posterior.row_covariance ≈
        expected_row_covariance atol = 1.0e-12
    @test posterior.scale ≈ expected_scale atol = 1.0e-12
    @test posterior.dof == prior_dof + size(response, 1)
    @test ishermitian(posterior.row_covariance)
    @test ishermitian(posterior.scale)
    @test minimum(eigvals(Symmetric(posterior.row_covariance))) > 0
    @test minimum(eigvals(Symmetric(posterior.scale))) > 0

    draw_rng = MersenneTwister(6203)
    inverse_wishart_scale = [3.0 0.8; 0.8 2.0]
    inverse_wishart_dof = 10
    draw_sum = zeros(2, 2)
    for draw in 1:4_000
        covariance = USForecastBenchmarks._rand_inverse_wishart(
            draw_rng,
            inverse_wishart_scale,
            inverse_wishart_dof
        )
        draw == 1 &&
            @test minimum(eigvals(Symmetric(covariance))) > 0
        draw_sum .+= covariance
    end
    empirical_mean = draw_sum / 4_000
    analytic_mean =
        inverse_wishart_scale / (inverse_wishart_dof - 2 - 1)
    @test empirical_mean ≈ analytic_mean rtol = 0.06 atol = 0.015

    matrix_normal_rng = MersenneTwister(191)
    matrix_mean = [0.3 -0.4; 0.8 0.1]
    row_covariance = [0.5 0.1; 0.1 0.3]
    column_covariance = [0.9 0.35; 0.35 0.7]
    row_factor = cholesky(Symmetric(row_covariance)).L
    column_factor = cholesky(Symmetric(column_covariance)).L
    coefficient_samples = [
        USForecastBenchmarks._rand_matrix_normal(
                matrix_normal_rng,
                matrix_mean,
                row_factor,
                column_factor
            )[1, 1]
            for _ in 1:5_000
    ]
    @test mean(coefficient_samples) ≈ matrix_mean[1, 1] atol = 0.025
    @test var(coefficient_samples) ≈
        row_covariance[1, 1] * column_covariance[1, 1] rtol = 0.06
    @test_throws DimensionMismatch USForecastBenchmarks._rand_matrix_normal(
        matrix_normal_rng,
        matrix_mean,
        ones(3, 3),
        column_factor
    )
end

@testset "BVAR shrinkage and weak-prior limit" begin
    rng = MersenneTwister(441)
    observations = 240
    transition = [0.62 0.18; -0.11 0.47]
    innovation_factor = cholesky(Symmetric([0.4 0.16; 0.16 0.3])).L
    training = zeros(observations, 2)
    for time in 2:observations
        training[time, :] .=
            [0.15, -0.08] +
            transition * training[time - 1, :] +
            innovation_factor * randn(rng, 2)
    end

    strong_spec = BVARSpec(
        lags = 1,
        tightness = 1.0e-5,
        intercept_variance = 1.0e12
    )
    weak_spec = BVARSpec(
        lags = 1,
        tightness = 1.0e6,
        intercept_variance = 1.0e12
    )
    strong_fit = USForecastBenchmarks._fit_bvar(strong_spec, training)
    weak_fit = USForecastBenchmarks._fit_bvar(weak_spec, training)
    ols = weak_fit.design \ weak_fit.response
    lag_rows = 2:3

    @test strong_fit.posterior_mean[lag_rows, :] ≈
        Matrix{Float64}(I, 2, 2) atol = 1.0e-7
    @test norm(
        strong_fit.posterior_mean[lag_rows, :] -
            strong_fit.prior_mean[lag_rows, :]
    ) <
        norm(
        weak_fit.posterior_mean[lag_rows, :] -
            weak_fit.prior_mean[lag_rows, :]
    )
    @test weak_fit.posterior_mean ≈ ols rtol = 1.0e-9 atol = 1.0e-9
    @test weak_fit.posterior_dof ==
        size(training, 2) +
        weak_spec.iw_dof_offset +
        observations -
        weak_spec.lags
end

@testset "BVAR origin firewall, alignment, and seeded joint density" begin
    rng = MersenneTwister(773)
    observations = 260
    transition = [0.48 0.12; -0.08 0.36]
    innovation_factor = cholesky(Symmetric([0.7 0.5; 0.5 0.9])).L
    training = zeros(observations, 2)
    for time in 2:observations
        training[time, :] .=
            transition * training[time - 1, :] +
            innovation_factor * randn(rng, 2)
    end
    x_train = randn(rng, observations, 1)
    sample_a = bvar_sample(
        training;
        forecast_horizon = 6,
        x_train,
        x_future = zeros(6, 1)
    )
    sample_b = bvar_sample(
        training;
        forecast_horizon = 6,
        x_train = fill(1.0e15, observations, 1),
        x_future = fill(-1.0e15, 6, 1)
    )
    spec = BVARSpec(lags = 2)

    first = run_benchmark(spec, sample_a; n_draws = 1_500, seed = 992)
    repeated =
        run_benchmark(spec, sample_a; n_draws = 1_500, seed = 992)
    changed_seed =
        run_benchmark(spec, sample_a; n_draws = 1_500, seed = 993)
    changed_future =
        run_benchmark(spec, sample_b; n_draws = 1_500, seed = 992)
    point_only = run_benchmark(spec, sample_a; seed = 7)

    @test first.status == :ok
    @test first.forecast.forecast_keys ==
        collect((observations + 1):(observations + 6))
    @test size(first.forecast.point) == (6, 2)
    @test size(first.forecast.draws) == (6, 2, 1_500)
    @test first.forecast.point == repeated.forecast.point
    @test first.forecast.draws == repeated.forecast.draws
    @test first.forecast.draws != changed_seed.forecast.draws
    @test first.forecast.point == changed_seed.forecast.point
    @test first.forecast.point == changed_future.forecast.point
    @test first.forecast.draws == changed_future.forecast.draws
    @test first.forecast.point == point_only.forecast.point
    @test size(point_only.forecast.draws) == (6, 2, 0)
    @test !first.forecast.diagnostics["future_exogenous_used"]
    @test first.forecast.diagnostics["hyperparameter_selection"] == "none"
    @test first.forecast.diagnostics["parameter_uncertainty_in_draws"]
    @test first.forecast.diagnostics[
        "joint_innovation_uncertainty_in_draws",
    ]

    first_step_draws = dropdims(first.forecast.draws[1:1, :, :]; dims = 1)
    predictive_covariance = cov(first_step_draws; dims = 2)
    @test predictive_covariance[1, 2] > 0.2
    @test minimum(eigvals(Symmetric(predictive_covariance))) > 0

    fit = USForecastBenchmarks._fit_bvar(spec, training)
    first_regressor = USForecastBenchmarks._bvar_regressor(
        vcat(training, zeros(1, 2)),
        observations + 1,
        spec
    )
    @test first.forecast.point[1, :] ≈
        fit.posterior_mean' * first_regressor atol = 1.0e-12
end

@testset "BVAR invalid priors, degrees of freedom, and rank handling" begin
    @test_throws ArgumentError BVARSpec(lags = 0)
    @test_throws ArgumentError BVARSpec(intercept = 1)
    @test_throws ArgumentError BVARSpec(tightness = 0)
    @test_throws ArgumentError BVARSpec(tightness = Inf)
    @test_throws ArgumentError BVARSpec(lag_decay = -1)
    @test_throws ArgumentError BVARSpec(own_lag_mean = NaN)
    @test_throws ArgumentError BVARSpec(intercept_variance = 0)
    @test_throws ArgumentError BVARSpec(iw_dof_offset = 1)
    @test_throws ArgumentError BVARSpec(iw_dof_offset = true)
    @test_throws ArgumentError BVARSpec(innovation_scale = -1)
    @test_throws ArgumentError BVARSpec(scale_floor = 0)

    response = [1.0 0.5; 2.0 1.0; 3.0 1.5]
    rank_deficient_design = [1.0 1.0; 1.0 1.0; 1.0 1.0]
    prior_mean = zeros(2, 2)
    proper_precision = Matrix{Float64}(I, 2, 2)
    proper_scale = Matrix{Float64}(I, 2, 2)

    regularized = USForecastBenchmarks._mniw_posterior(
        response,
        rank_deficient_design,
        prior_mean,
        proper_precision,
        proper_scale,
        4
    )
    @test rank(rank_deficient_design) == 1
    @test minimum(eigvals(Symmetric(regularized.row_covariance))) > 0

    @test_throws ArgumentError USForecastBenchmarks._mniw_posterior(
        response,
        rank_deficient_design,
        prior_mean,
        [1.0 0.0; 0.0 0.0],
        proper_scale,
        4
    )
    @test_throws ArgumentError USForecastBenchmarks._mniw_posterior(
        response,
        rank_deficient_design,
        prior_mean,
        proper_precision,
        [1.0 0.0; 0.0 0.0],
        4
    )
    @test_throws ArgumentError USForecastBenchmarks._mniw_posterior(
        response,
        rank_deficient_design,
        prior_mean,
        proper_precision,
        proper_scale,
        1
    )
    @test_throws DimensionMismatch USForecastBenchmarks._mniw_posterior(
        response,
        rank_deficient_design[1:2, :],
        prior_mean,
        proper_precision,
        proper_scale,
        4
    )

    too_short = bvar_sample(reshape(collect(1.0:4.0), :, 1))
    failed = run_benchmark(BVARSpec(lags = 4), too_short)
    @test failed.status == :failed
    @test failed.forecast === nothing
    @test failed.failure.code == :invalid_input
    @test occursin("requires more than", failed.failure.message)
end

@testset "BVAR model-card and identifier completeness" begin
    spec = BVARSpec()
    card = model_card(spec)
    for key in (
            "interface_version",
            "model_id",
            "family",
            "estimation_information_set",
            "point_rule",
            "density_rule",
            "failure_policy",
            "seed_policy",
            "prior_family",
            "prior_formula",
            "posterior_formula",
            "hyperparameters",
            "hyperparameter_selection",
            "model_id_encoding",
            "scale_rule",
            "parameter_uncertainty",
            "joint_innovation_uncertainty",
            "point_path_limitation",
            "known_limitations",
        )
        @test haskey(card, key)
        @test !isempty(card[key])
    end
    @test card["model_id"] == model_id(spec)
    @test card["hyperparameter_selection"] ==
        "None. Values are constructor-fixed and model-id encoded."
    @test length(card["hyperparameters"]) == 9

    identifiers = [
        model_id(BVARSpec()),
        model_id(BVARSpec(lags = 3)),
        model_id(BVARSpec(intercept = false)),
        model_id(BVARSpec(tightness = nextfloat(0.2))),
        model_id(BVARSpec(lag_decay = 2.0)),
        model_id(BVARSpec(own_lag_mean = 0.0)),
        model_id(BVARSpec(intercept_variance = 99.0)),
        model_id(BVARSpec(iw_dof_offset = 3)),
        model_id(BVARSpec(innovation_scale = 2.0)),
        model_id(BVARSpec(scale_floor = 1.0e-7)),
    ]
    @test length(unique(identifiers)) == length(identifiers)
end
