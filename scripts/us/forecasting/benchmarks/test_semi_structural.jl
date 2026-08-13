using LinearAlgebra
using Random
using Statistics
using Test

if !isdefined(Main, :USForecastBenchmarks)
    include("USForecastBenchmarks.jl")
end
if !isdefined(USForecastBenchmarks, :SemiStructuralSpec)
    Base.include(
        USForecastBenchmarks,
        joinpath(@__DIR__, "semi_structural.jl")
    )
end
using .USForecastBenchmarks

const SSB = USForecastBenchmarks

function semi_structural_sample(
        y_train;
        forecast_horizon = 4,
        origin_id = "semi-structural-fixture",
        target_names = collect(SSB.SEMI_STRUCTURAL_TARGET_NAMES),
        x_train = nothing,
        x_future = nothing
    )
    observations = size(y_train, 1)
    return OriginData(
        origin_id = origin_id,
        origin_key = observations,
        training_keys = collect(1:observations),
        forecast_keys =
            collect((observations + 1):(observations + forecast_horizon)),
        y_train = y_train,
        target_names = target_names,
        x_train = x_train,
        x_future = x_future
    )
end

function synthetic_semi_structural_panel(spec, periods; seed = 2041)
    system = SSB._semi_structural_system(spec)
    rng = MersenneTwister(seed)
    process_factor =
        SSB._semi_psd_factor(system.process_covariance, "process covariance")
    measurement_factor = SSB._semi_psd_factor(
        system.measurement_covariance,
        "measurement covariance"
    )
    state = copy(system.initial_mean)
    observations = zeros(periods, 4)
    states = zeros(periods, 8)
    for period in 1:periods
        state .=
            system.transition_constant +
            system.transition * state +
            process_factor * randn(rng, 8)
        states[period, :] .= state
        observations[period, :] .=
            system.observation_constant +
            system.observation * state +
            measurement_factor * randn(rng, 4)
    end
    return observations, states
end

@testset "exact Kalman filter against scalar known system" begin
    system = (
        transition_constant = [0.1],
        transition = reshape([0.8], 1, 1),
        process_covariance = reshape([0.2], 1, 1),
        observation_constant = [-0.2],
        observation = reshape([1.0], 1, 1),
        measurement_covariance = reshape([0.3], 1, 1),
        initial_mean = [0.5],
        initial_covariance = reshape([0.4], 1, 1),
    )
    observations = reshape([0.7, -0.1], :, 1)
    result = SSB._semi_kalman_filter(observations, system)

    predicted_mean_1 = 0.1 + 0.8 * 0.5
    predicted_variance_1 = 0.8^2 * 0.4 + 0.2
    innovation_1 = 0.7 - (-0.2 + predicted_mean_1)
    innovation_variance_1 = predicted_variance_1 + 0.3
    gain_1 = predicted_variance_1 / innovation_variance_1
    filtered_mean_1 = predicted_mean_1 + gain_1 * innovation_1
    filtered_variance_1 =
        (1.0 - gain_1)^2 * predicted_variance_1 + gain_1^2 * 0.3

    predicted_mean_2 = 0.1 + 0.8 * filtered_mean_1
    predicted_variance_2 = 0.8^2 * filtered_variance_1 + 0.2
    innovation_2 = -0.1 - (-0.2 + predicted_mean_2)
    innovation_variance_2 = predicted_variance_2 + 0.3
    gain_2 = predicted_variance_2 / innovation_variance_2
    filtered_mean_2 = predicted_mean_2 + gain_2 * innovation_2
    filtered_variance_2 =
        (1.0 - gain_2)^2 * predicted_variance_2 + gain_2^2 * 0.3
    expected_log_likelihood = -0.5 * (
        2.0 * log(2.0 * pi) +
            log(innovation_variance_1) +
            innovation_1^2 / innovation_variance_1 +
            log(innovation_variance_2) +
            innovation_2^2 / innovation_variance_2
    )

    @test result.predicted_means[:, 1] ≈
        [predicted_mean_1, predicted_mean_2] atol = 1.0e-14
    @test result.filtered_means[:, 1] ≈
        [filtered_mean_1, filtered_mean_2] atol = 1.0e-14
    @test result.filtered_mean ≈ [filtered_mean_2] atol = 1.0e-14
    @test result.filtered_covariance[1, 1] ≈
        filtered_variance_2 atol = 1.0e-14
    @test result.innovations[:, 1] ≈
        [innovation_1, innovation_2] atol = 1.0e-14
    @test result.log_likelihood ≈
        expected_log_likelihood atol = 1.0e-14
end

@testset "known semi-structural system and structural links" begin
    spec = SSB.SemiStructuralSpec()
    system = SSB._semi_structural_system(spec)
    @test size(system.transition) == (8, 8)
    @test size(system.observation) == (4, 8)
    @test system.transition[2, 4] == spec.is_slope
    @test system.transition[2, 6] == spec.is_slope
    @test system.transition[2, 7] == -spec.is_slope
    @test system.transition[6, 2] == spec.phillips_slope
    @test system.transition[7, 7] == spec.policy_smoothing
    @test system.transition[8, 2] == 1.0
    @test system.observation[1, [1, 2, 8]] == [1.0, 4.0, -4.0]
    @test system.observation[3, [2, 3]] ==
        [-spec.okun_slope, 1.0]
    @test system.observation[4, 7] == 1.0
    @test system.transition_constant +
        system.transition * system.initial_mean ≈
        system.initial_mean atol = 1.0e-14
    @test maximum(abs, eigvals(system.transition)) < 1.0

    observations, latent_states =
        synthetic_semi_structural_panel(spec, 160; seed = 87)
    filter_result = SSB._semi_kalman_filter(observations, system)
    @test isfinite(filter_result.log_likelihood)
    @test size(filter_result.filtered_means) == size(latent_states)
    @test sqrt(
        mean(
            (filter_result.filtered_means[:, 2] - latent_states[:, 2]) .^ 2
        )
    ) < 0.45
end

@testset "seeded posterior-state predictive paths" begin
    spec = SSB.SemiStructuralSpec()
    observations, _ =
        synthetic_semi_structural_panel(spec, 140; seed = 901)
    sample = semi_structural_sample(observations; forecast_horizon = 6)
    first = run_benchmark(spec, sample; n_draws = 2_000, seed = 781)
    repeated = run_benchmark(spec, sample; n_draws = 2_000, seed = 781)
    changed_seed = run_benchmark(spec, sample; n_draws = 2_000, seed = 782)
    point_only = run_benchmark(spec, sample; n_draws = 0, seed = 17)

    @test first.status == :ok
    @test size(first.forecast.point) == (6, 4)
    @test size(first.forecast.draws) == (6, 4, 2_000)
    @test first.forecast.draws == repeated.forecast.draws
    @test first.forecast.draws != changed_seed.forecast.draws
    @test first.forecast.point == repeated.forecast.point
    @test first.forecast.point == changed_seed.forecast.point
    @test first.forecast.point == point_only.forecast.point
    @test size(point_only.forecast.draws) == (6, 4, 0)
    @test first.forecast.diagnostics["filtered_state_uncertainty_in_draws"]
    @test first.forecast.diagnostics["process_shock_uncertainty_in_draws"]
    @test first.forecast.diagnostics["measurement_shock_uncertainty_in_draws"]
    @test !first.forecast.diagnostics["parameter_uncertainty_in_draws"]

    filter_result = SSB._semi_kalman_filter(
        observations,
        SSB._semi_structural_system(spec)
    )
    system = SSB._semi_structural_system(spec)
    expected_first_point =
        system.observation_constant +
        system.observation * (
        system.transition_constant +
            system.transition * filter_result.filtered_mean
    )
    unconditional_first_point =
        system.observation_constant +
        system.observation * (
        system.transition_constant +
            system.transition * system.initial_mean
    )
    @test first.forecast.point[1, :] ≈ expected_first_point atol = 1.0e-12
    @test norm(first.forecast.point[1, :] - unconditional_first_point) > 0.05

    first_step_draws =
        dropdims(first.forecast.draws[1:1, :, :]; dims = 1)
    predictive_covariance = cov(first_step_draws; dims = 2)
    @test minimum(eigvals(Symmetric(predictive_covariance))) > 0.0
    @test predictive_covariance[1, 3] < -0.01
end

@testset "target, unit, exogenous, and origin firewall contracts" begin
    spec = SSB.SemiStructuralSpec()
    observations, _ =
        synthetic_semi_structural_panel(spec, 90; seed = 55)
    valid = semi_structural_sample(observations)
    @test run_benchmark(spec, valid; n_draws = 4, seed = 1).status == :ok

    reversed_names = reverse(collect(SSB.SEMI_STRUCTURAL_TARGET_NAMES))
    wrong_order =
        semi_structural_sample(observations; target_names = reversed_names)
    failed_order = run_benchmark(spec, wrong_order)
    @test failed_order.status == :failed
    @test failed_order.failure.code == :invalid_input
    @test occursin("target_names", failed_order.failure.message)

    with_future_path = semi_structural_sample(
        observations;
        x_train = zeros(size(observations, 1), 1),
        x_future = fill(1.0e100, 4, 1)
    )
    failed_exogenous = run_benchmark(spec, with_future_path)
    @test failed_exogenous.status == :failed
    @test failed_exogenous.failure.code == :invalid_input
    @test occursin("rejects x_train/x_future", failed_exogenous.failure.message)

    card = model_card(spec)
    @test card["target_names"] == collect(SSB.SEMI_STRUCTURAL_TARGET_NAMES)
    @test card["target_units"] == collect(SSB.SEMI_STRUCTURAL_TARGET_UNITS)
    @test card["target_units"] == [
        "annualized_quarter_over_quarter_percent",
        "annualized_quarter_over_quarter_percent",
        "quarterly_average_percent",
        "quarterly_average_percent",
    ]
    @test !hasfield(OriginData, :y_future)
    @test_throws MethodError OriginData(
        origin_id = "future-target-impossible",
        origin_key = 4,
        training_keys = 1:4,
        forecast_keys = 5:6,
        y_train = observations[1:4, :],
        target_names = collect(SSB.SEMI_STRUCTURAL_TARGET_NAMES),
        y_future = observations[5:6, :]
    )

    cutoff = 60
    altered_panel = copy(observations)
    altered_panel[(cutoff + 1):end, :] .= 1.0e9
    cutoff_sample_a = semi_structural_sample(
        @view(observations[1:cutoff, :]);
        forecast_horizon = 5
    )
    cutoff_sample_b = semi_structural_sample(
        @view(altered_panel[1:cutoff, :]);
        forecast_horizon = 5
    )
    cutoff_a =
        run_benchmark(spec, cutoff_sample_a; n_draws = 100, seed = 919)
    cutoff_b =
        run_benchmark(spec, cutoff_sample_b; n_draws = 100, seed = 919)
    @test cutoff_a.forecast.point == cutoff_b.forecast.point
    @test cutoff_a.forecast.draws == cutoff_b.forecast.draws
end

@testset "stability, covariance, and model-id completeness" begin
    spec = SSB.SemiStructuralSpec()
    @test_throws ArgumentError SSB.SemiStructuralSpec(
        potential_growth_persistence = 1.0
    )
    @test_throws ArgumentError SSB.SemiStructuralSpec(policy_smoothing = -0.1)
    @test_throws ArgumentError SSB.SemiStructuralSpec(is_slope = 0.0)
    @test_throws ArgumentError SSB.SemiStructuralSpec(taylor_output = -0.1)
    @test_throws DimensionMismatch SSB.SemiStructuralSpec(
        measurement_covariance = zeros(3, 3)
    )
    indefinite_measurement = Matrix{Float64}(I, 4, 4)
    indefinite_measurement[1, 1] = -1.0
    @test_throws ArgumentError SSB.SemiStructuralSpec(
        measurement_covariance = indefinite_measurement
    )
    nonsymmetric_process = Matrix{Float64}(I, 7, 7)
    nonsymmetric_process[1, 2] = 0.2
    @test_throws ArgumentError SSB.SemiStructuralSpec(
        state_innovation_covariance = nonsymmetric_process
    )
    @test SSB.SemiStructuralSpec(
        state_innovation_covariance = zeros(7, 7)
    ) isa SSB.SemiStructuralSpec

    q_changed = copy(spec.state_innovation_covariance)
    q_changed[1, 1] = nextfloat(q_changed[1, 1])
    r_changed = copy(spec.measurement_covariance)
    r_changed[1, 1] = nextfloat(r_changed[1, 1])
    p_changed = copy(spec.initial_covariance)
    p_changed[1, 1] = nextfloat(p_changed[1, 1])
    identifiers = [
        model_id(spec),
        model_id(SSB.SemiStructuralSpec(potential_growth_mean = 2.1)),
        model_id(
            SSB.SemiStructuralSpec(potential_growth_persistence = 0.84)
        ),
        model_id(SSB.SemiStructuralSpec(output_gap_persistence = 0.74)),
        model_id(SSB.SemiStructuralSpec(is_slope = 0.11)),
        model_id(SSB.SemiStructuralSpec(natural_unemployment_mean = 4.4)),
        model_id(
            SSB.SemiStructuralSpec(
                natural_unemployment_persistence = 0.94
            )
        ),
        model_id(SSB.SemiStructuralSpec(neutral_rate_mean = 0.9)),
        model_id(SSB.SemiStructuralSpec(neutral_rate_persistence = 0.89)),
        model_id(SSB.SemiStructuralSpec(inflation_anchor_mean = 1.9)),
        model_id(
            SSB.SemiStructuralSpec(inflation_anchor_persistence = 0.94)
        ),
        model_id(SSB.SemiStructuralSpec(inflation_persistence = 0.64)),
        model_id(SSB.SemiStructuralSpec(phillips_slope = 0.07)),
        model_id(SSB.SemiStructuralSpec(okun_slope = 0.44)),
        model_id(SSB.SemiStructuralSpec(policy_smoothing = 0.74)),
        model_id(SSB.SemiStructuralSpec(taylor_inflation = 1.49)),
        model_id(SSB.SemiStructuralSpec(taylor_output = 0.34)),
        model_id(
            SSB.SemiStructuralSpec(state_innovation_covariance = q_changed)
        ),
        model_id(SSB.SemiStructuralSpec(measurement_covariance = r_changed)),
        model_id(SSB.SemiStructuralSpec(initial_covariance = p_changed)),
    ]
    @test length(unique(identifiers)) == length(identifiers)
    @test length(model_id(spec)) < 128
    @test occursin(r"_[0-9a-f]{64}$", model_id(spec))
    @test model_id(
        SSB.SemiStructuralSpec(potential_growth_mean = nextfloat(2.0))
    ) != model_id(spec)
end

@testset "fixed-parameter density limitation is explicit" begin
    spec = SSB.SemiStructuralSpec()
    card = model_card(spec)
    @test card["density_scope"] ==
        "Fixed-parameter conditional-on-hyperparameters posterior-state predictive density."
    @test card["origin_parameter_fitting"] ==
        "None. The origin update is latent-state filtering, not parameter estimation."
    @test card["parameter_uncertainty"] == "Excluded."
    @test !card["full_posterior_parameter_density"]
    @test !card["satisfies_full_posterior_parameter_density_requirement"]
    @test !card["satisfies_dsge_requirement"]
    @test occursin("not a DSGE", card["known_limitations"])
    @test occursin(
        "does not satisfy a full posterior-parameter density",
        card["known_limitations"]
    )
end
