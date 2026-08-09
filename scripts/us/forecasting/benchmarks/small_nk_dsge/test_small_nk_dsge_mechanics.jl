#!/usr/bin/env julia

using LinearAlgebra
using Test

include(joinpath(@__DIR__, "USSmallNKDSGEMechanics.jl"))
using .USSmallNKDSGEMechanics

const NK = USSmallNKDSGEMechanics

function replace_parameter(parameters::SmallNKParameters, field::Symbol, value::Float64)
    values = [getfield(parameters, name) for name in fieldnames(SmallNKParameters)]
    values[findfirst(==(field), collect(fieldnames(SmallNKParameters)))] = value
    return SmallNKParameters(values...)
end

function scaled_system(system::CanonicalSystem, scale::Float64)
    return CanonicalSystem(
        scale .* system.gamma0,
        scale .* system.gamma1,
        scale .* system.constant,
        scale .* system.shock_loading,
        scale .* system.expectational_loading,
    )
end

function replaced_solution(
        solution::GensysSolution;
        transition = solution.transition,
        constant = solution.constant,
        impact = solution.impact,
        eu = solution.eu,
        generalized_roots = solution.generalized_roots,
        stable_root_count = solution.stable_root_count,
        unstable_root_count = solution.unstable_root_count,
        equation_residual_max = solution.equation_residual_max,
    )
    return GensysSolution(
        transition,
        constant,
        impact,
        eu,
        generalized_roots,
        stable_root_count,
        unstable_root_count,
        equation_residual_max,
    )
end

function replaced_measurement(
        measurement::MeasurementSystem;
        loading = measurement.loading,
        intercept = measurement.intercept,
        shock_covariance = measurement.shock_covariance,
        measurement_covariance = measurement.measurement_covariance,
    )
    return MeasurementSystem(
        loading,
        intercept,
        shock_covariance,
        measurement_covariance,
    )
end

function replaced_filter(
        filtered::FilterResult;
        loglikelihood = filtered.loglikelihood,
        filtered_mean = filtered.filtered_mean,
        filtered_covariance = filtered.filtered_covariance,
        innovation_ranks = filtered.innovation_ranks,
    )
    return FilterResult(
        loglikelihood,
        filtered_mean,
        filtered_covariance,
        innovation_ranks,
    )
end

@testset "official FRBNY fixture and canonical equations" begin
    fixture = load_reference_fixture()
    @test fixture.sha256 == NK.REFERENCE_FIXTURE_SHA256
    @test fixture.eu == (1, 1)
    @test size(fixture.transition) == (8, 8)
    @test size(fixture.impact) == (8, 3)
    @test fixture.constant == zeros(8)

    parameters = reference_parameters()
    @test fixture.parameters isa SmallNKParameters
    for field in fieldnames(SmallNKParameters)
        @test reinterpret(UInt64, getfield(fixture.parameters, field)) ==
            reinterpret(UInt64, getfield(parameters, field))
    end
    @test reinterpret(UInt64, fixture.stake) ==
        reinterpret(UInt64, 1.0 + NK.UNIT_ROOT_BAND)
    @test Set(keys(fixture.document["upstream"])) ==
        Set(first(pair) for pair in NK.REFERENCE_UPSTREAM_METADATA)
    for (key, expected) in NK.REFERENCE_UPSTREAM_METADATA
        @test fixture.document["upstream"][key] == expected
    end
    changed_parameters = deepcopy(fixture.document["parameters"])
    changed_parameters["pi_star"] = "0x40204d35a858793f"
    @test_throws SmallNKMechanicsError NK._fixture_parameters(changed_parameters)
    missing_parameter = deepcopy(fixture.document["parameters"])
    pop!(missing_parameter, "sigma_z")
    @test_throws SmallNKMechanicsError NK._fixture_parameters(missing_parameter)
    changed_upstream = deepcopy(fixture.document["upstream"])
    changed_upstream["commit"] = repeat("0", 40)
    @test_throws SmallNKMechanicsError NK._validate_fixture_upstream(
        changed_upstream,
    )
    changed_stake = deepcopy(fixture.document["upstream"])
    changed_stake["stake_ieee754_hex"] = "0x3ff0000000000000"
    @test_throws SmallNKMechanicsError NK._validate_fixture_upstream(
        changed_stake,
    )
    system = build_canonical_system(parameters)
    @test size(system.gamma0) == (8, 8)
    @test size(system.gamma1) == (8, 8)
    @test size(system.shock_loading) == (8, 3)
    @test size(system.expectational_loading) == (8, 2)
    @test system.gamma0[1, 1] == 1.0
    @test system.gamma0[1, 3] == 1.0 / parameters.tau
    @test system.gamma0[1, 5] == -(1.0 - parameters.rho_g)
    @test system.gamma0[1, 6] == -parameters.rho_z / parameters.tau
    @test system.gamma0[2, 2] == 1.0
    @test system.gamma0[2, 8] == -1.0 / (1.0 + parameters.r_annual / 400.0)
    @test system.gamma1[3, 3] == parameters.rho_rate
    @test system.gamma1[4, 1] == 1.0
    @test system.gamma1[5, 5] == parameters.rho_g
    @test system.gamma1[6, 6] == parameters.rho_z
    @test system.expectational_loading[7, 1] == 1.0
    @test system.expectational_loading[8, 2] == 1.0
    @test count(!iszero, system.shock_loading) == 3

    solution = solve_gensys(system)
    @test solution.eu == (1, 1)
    @test solution.stable_root_count == 6
    @test solution.unstable_root_count == 2
    @test solution.equation_residual_max <= NK.EQUATION_RESIDUAL_TOLERANCE
    @test solution.transition ≈ fixture.transition atol = 1.0e-12 rtol = 0.0
    @test solution.constant == fixture.constant
    @test solution.impact ≈ fixture.impact atol = 1.0e-12 rtol = 0.0

    for scale in (1.0e-12, 1.0e-10, 1.0e-8, 1.0, 17.0, 1.0e8, 1.0e10, 1.0e12)
        scaled = solve_gensys(scaled_system(system, scale))
        @test scaled.eu == solution.eu
        @test scaled.transition ≈ solution.transition atol = 1.0e-12 rtol = 0.0
        @test scaled.constant ≈ solution.constant atol = 1.0e-12 rtol = 0.0
        @test scaled.impact ≈ solution.impact atol = 1.0e-12 rtol = 0.0
        @test scaled.equation_residual_max <= NK.EQUATION_RESIDUAL_TOLERANCE
    end
end

@testset "root classification and determinacy fail closed" begin
    schur_s = ComplexF64[1.0 0.0; 0.0 1.0]
    schur_t = ComplexF64[0.5 0.0; 0.0 2.0]
    classified = classify_generalized_roots(schur_s, schur_t)
    @test classified.stable == [true, false]
    @test classified.roots == ComplexF64[0.5, 2.0]
    for scale in (1.0e-12, 1.0e-8, 1.0, 1.0e8, 1.0e12)
        scaled = classify_generalized_roots(scale .* schur_s, scale .* schur_t)
        @test scaled.stable == classified.stable
        @test scaled.roots ≈ classified.roots atol = 1.0e-15 rtol = 0.0
    end

    near_unit = copy(schur_t)
    near_unit[1, 1] = 1.0 + 0.5e-6
    @test_throws SmallNKMechanicsError classify_generalized_roots(schur_s, near_unit)
    coincident_s = copy(schur_s)
    coincident_t = copy(schur_t)
    coincident_s[1, 1] = 0.0
    coincident_t[1, 1] = 0.0
    @test_throws SmallNKMechanicsError classify_generalized_roots(
        coincident_s,
        coincident_t,
    )
    @test_throws SmallNKMechanicsError classify_generalized_roots(
        schur_s,
        schur_t;
        unit_band = 0.0,
    )
    nonfinite_s = copy(schur_s)
    nonfinite_s[1, 1] = ComplexF64(NaN)
    @test_throws SmallNKMechanicsError classify_generalized_roots(
        nonfinite_s,
        schur_t,
    )
    @test_throws SmallNKMechanicsError classify_generalized_roots(
        schur_s,
        schur_t;
        unit_band = NaN,
    )
    @test_throws SmallNKMechanicsError classify_generalized_roots(
        schur_s,
        schur_t;
        zero_tolerance = Inf,
    )

    parameters = adapted_mechanics_parameters()
    determinate = solve_gensys(build_canonical_system(parameters))
    @test determinate.eu == (1, 1)
    @test determinate.equation_residual_max <= NK.EQUATION_RESIDUAL_TOLERANCE
    indeterminate_parameters = replace_parameter(parameters, :psi1, 0.5)
    indeterminate_system = build_canonical_system(indeterminate_parameters)
    @test solve_gensys(
        indeterminate_system;
        require_determinate = false,
    ).eu == (1, 0)
    @test_throws SmallNKMechanicsError solve_gensys(indeterminate_system)

    missing_expectations = build_canonical_system(parameters)
    no_expectational_errors = CanonicalSystem(
        missing_expectations.gamma0,
        missing_expectations.gamma1,
        missing_expectations.constant,
        missing_expectations.shock_loading,
        zeros(8, 2),
    )
    @test solve_gensys(
        no_expectational_errors;
        require_determinate = false,
    ).eu[1] == 0
    @test_throws SmallNKMechanicsError solve_gensys(no_expectational_errors)
    @test_throws SmallNKMechanicsError solve_gensys(
        build_canonical_system(parameters);
        svd_tolerance = NaN,
    )
    @test_throws SmallNKMechanicsError solve_gensys(
        build_canonical_system(parameters);
        reality_tolerance = Inf,
    )
    @test_throws SmallNKMechanicsError solve_gensys(
        build_canonical_system(parameters);
        equation_residual_tolerance = NaN,
    )
end

@testset "aggregate-PCE measurement contract" begin
    parameters = adapted_mechanics_parameters()
    measurement = build_measurement_system(parameters)
    @test measurement.loading[1, [1, 4, 6]] == [4.0, -4.0, 4.0]
    @test measurement.loading[2, 2] == 4.0
    @test measurement.loading[3, 3] == 4.0
    @test measurement.intercept == [
        4.0 * parameters.gamma_quarterly,
        parameters.pi_star,
        parameters.pi_star + parameters.r_annual +
            4.0 * parameters.gamma_quarterly,
    ]
    @test measurement.shock_covariance == Diagonal(
        [
            parameters.sigma_z^2,
            parameters.sigma_g^2,
            parameters.sigma_rate^2,
        ]
    )
    @test measurement.measurement_covariance == zeros(3, 3)
end

@testset "zero-jitter Kalman and coherent predictive paths" begin
    parameters = adapted_mechanics_parameters()
    solution = solve_gensys(build_canonical_system(parameters))
    measurement = build_measurement_system(parameters)
    moments = stationary_state_moments(solution, measurement)
    @test size(moments.mean) == (8,)
    @test size(moments.covariance) == (8, 8)
    @test rank(moments.observation_covariance; atol = NK.COVARIANCE_TOLERANCE, rtol = 0.0) == 3
    @test cholesky(Symmetric(moments.observation_covariance); check = true) isa Cholesky

    observations = simulate_synthetic_observations(
        parameters,
        100;
        seed = 7301,
    )
    @test observations == simulate_synthetic_observations(
        parameters,
        100;
        seed = 7301,
    )
    @test observations != simulate_synthetic_observations(
        parameters,
        100;
        seed = 7302,
    )
    filtered = filter_loglikelihood(observations, solution, measurement)
    @test isfinite(filtered.loglikelihood)
    @test filtered.innovation_ranks == fill(3, 100)
    mutated = copy(observations)
    mutated[end, 1] += 0.125
    @test filter_loglikelihood(mutated, solution, measurement).loglikelihood !=
        filtered.loglikelihood

    forecast = conditional_forecast_moments(filtered, solution, measurement, 12)
    @test size(forecast.means) == (12, 3)
    @test size(forecast.covariances) == (3, 3, 12)
    @test all(isfinite, forecast.means)
    @test all(isfinite, forecast.covariances)
    paths = draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        4,
        3;
        seed = 991,
    )
    @test paths == draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        4,
        3;
        seed = 991,
    )
    @test paths[1:2, :, :] == draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        2,
        3;
        seed = 991,
    )
    five_paths = draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        4,
        5;
        seed = 991,
    )
    @test five_paths[:, :, 1:3] == paths
    @test paths[:, :, 1] != paths[:, :, 2]
    @test paths != draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        4,
        3;
        seed = 992,
    )

    fingerprint = mechanics_fingerprint(
        parameters,
        build_canonical_system(parameters),
        solution,
        measurement,
    )
    @test occursin(r"^[0-9a-f]{64}$", fingerprint)
    @test fingerprint == NK.ADAPTED_MECHANICS_FINGERPRINT_SHA256
    @test fingerprint == mechanics_fingerprint(
        parameters,
        build_canonical_system(parameters),
        solution,
        measurement,
    )
    @test fingerprint != mechanics_fingerprint(
        reference_parameters(),
        build_canonical_system(reference_parameters()),
        solve_gensys(build_canonical_system(reference_parameters())),
        build_measurement_system(reference_parameters()),
    )
end

@testset "stochastic singularity and malformed input are rejected" begin
    parameters = adapted_mechanics_parameters()
    solution = solve_gensys(build_canonical_system(parameters))
    measurement = build_measurement_system(parameters)
    valid = simulate_synthetic_observations(parameters, 8; seed = 12)
    filtered = filter_loglikelihood(valid, solution, measurement)

    duplicate_loading = copy(measurement.loading)
    duplicate_loading[3, :] = duplicate_loading[2, :]
    singular = MeasurementSystem(
        duplicate_loading,
        measurement.intercept,
        measurement.shock_covariance,
        measurement.measurement_covariance,
    )
    @test_throws SmallNKMechanicsError stationary_state_moments(solution, singular)

    noisy = MeasurementSystem(
        measurement.loading,
        measurement.intercept,
        measurement.shock_covariance,
        Matrix{Float64}(I, 3, 3),
    )
    @test_throws SmallNKMechanicsError stationary_state_moments(solution, noisy)

    zero_shock = copy(measurement.shock_covariance)
    zero_shock[1, 1] = 0.0
    invalid_shocks = MeasurementSystem(
        measurement.loading,
        measurement.intercept,
        zero_shock,
        measurement.measurement_covariance,
    )
    @test_throws SmallNKMechanicsError stationary_state_moments(
        solution,
        invalid_shocks,
    )

    correlated_shocks = copy(measurement.shock_covariance)
    correlated_shocks[1, 2] = correlated_shocks[2, 1] = 0.01
    correlated = replaced_measurement(
        measurement;
        shock_covariance = correlated_shocks,
    )
    nonfinite_loading = copy(measurement.loading)
    nonfinite_loading[1, 1] = NaN
    nonfinite_measurement = replaced_measurement(
        measurement;
        loading = nonfinite_loading,
    )
    for invalid_measurement in (noisy, correlated, nonfinite_measurement)
        @test_throws SmallNKMechanicsError filter_loglikelihood(
            valid,
            solution,
            invalid_measurement,
        )
        @test_throws SmallNKMechanicsError conditional_forecast_moments(
            filtered,
            solution,
            invalid_measurement,
            4,
        )
        @test_throws SmallNKMechanicsError draw_joint_predictive_paths(
            filtered,
            solution,
            invalid_measurement,
            4,
            3;
            seed = 3,
        )
    end

    @test_throws MethodError filter_loglikelihood(Float32.(valid), solution, measurement)
    @test_throws SmallNKMechanicsError filter_loglikelihood(valid[:, 1:2], solution, measurement)
    nonfinite = copy(valid)
    nonfinite[1, 1] = NaN
    @test_throws SmallNKMechanicsError filter_loglikelihood(nonfinite, solution, measurement)
    @test_throws SmallNKMechanicsError conditional_forecast_moments(
        filter_loglikelihood(valid, solution, measurement),
        solution,
        measurement,
        13,
    )
    @test_throws SmallNKMechanicsError SmallNKParameters(
        true,
        0.5,
        1.7,
        0.5,
        0.5,
        2.0,
        0.4,
        0.5,
        0.8,
        0.5,
        0.4,
        1.0,
        0.5,
    )
    invalid_rho = replace_parameter(parameters, :rho_z, 1.0)
    @test_throws SmallNKMechanicsError build_canonical_system(invalid_rho)

    tiny_tau = replace_parameter(parameters, :tau, nextfloat(0.0))
    @test_throws SmallNKMechanicsError build_canonical_system(tiny_tau)
    huge_gamma = replace_parameter(parameters, :gamma_quarterly, 1.0e308)
    @test_throws SmallNKMechanicsError build_measurement_system(huge_gamma)
    huge_sigma = replace_parameter(parameters, :sigma_g, 1.0e308)
    @test_throws SmallNKMechanicsError build_measurement_system(huge_sigma)

    indeterminate = solve_gensys(
        build_canonical_system(replace_parameter(parameters, :psi1, 0.5));
        require_determinate = false,
    )
    @test indeterminate.eu == (1, 0)
    @test_throws SmallNKMechanicsError stationary_state_moments(
        indeterminate,
        measurement,
    )
    @test_throws SmallNKMechanicsError filter_loglikelihood(
        valid,
        indeterminate,
        measurement,
    )
    @test_throws SmallNKMechanicsError conditional_forecast_moments(
        filtered,
        indeterminate,
        measurement,
        4,
    )
    @test_throws SmallNKMechanicsError draw_joint_predictive_paths(
        filtered,
        indeterminate,
        measurement,
        4,
        3;
        seed = 3,
    )
    @test_throws SmallNKMechanicsError mechanics_fingerprint(
        parameters,
        build_canonical_system(parameters),
        indeterminate,
        measurement,
    )

    malformed_solution = replaced_solution(
        solution;
        transition = zeros(7, 7),
        constant = zeros(7),
        impact = zeros(7, 3),
    )
    nonfinite_transition = copy(solution.transition)
    nonfinite_transition[1, 1] = NaN
    nonfinite_solution = replaced_solution(
        solution;
        transition = nonfinite_transition,
    )
    bad_roots = copy(solution.generalized_roots)
    bad_roots[1] = ComplexF64(NaN, 0.0)
    nan_root_solution = replaced_solution(
        solution;
        generalized_roots = bad_roots,
    )
    negative_residual = replaced_solution(
        solution;
        equation_residual_max = -1.0,
    )
    for invalid_solution in (
            malformed_solution,
            nonfinite_solution,
            nan_root_solution,
            negative_residual,
        )
        @test_throws SmallNKMechanicsError stationary_state_moments(
            invalid_solution,
            measurement,
        )
        @test_throws SmallNKMechanicsError filter_loglikelihood(
            valid,
            invalid_solution,
            measurement,
        )
    end

    indefinite_covariance = Matrix{Float64}(I, 8, 8)
    indefinite_covariance[1, 1] = -1.0
    invalid_filters = (
        replaced_filter(filtered; loglikelihood = NaN),
        replaced_filter(filtered; filtered_mean = zeros(7)),
        replaced_filter(filtered; filtered_mean = fill(NaN, 8)),
        replaced_filter(filtered; filtered_covariance = zeros(7, 7)),
        replaced_filter(filtered; filtered_covariance = indefinite_covariance),
        replaced_filter(filtered; innovation_ranks = Int[]),
        replaced_filter(filtered; innovation_ranks = [3, 2]),
    )
    for invalid_filter in invalid_filters
        @test_throws SmallNKMechanicsError conditional_forecast_moments(
            invalid_filter,
            solution,
            measurement,
            4,
        )
        @test_throws SmallNKMechanicsError draw_joint_predictive_paths(
            invalid_filter,
            solution,
            measurement,
            4,
            3;
            seed = 3,
        )
    end

    @test_throws MethodError conditional_forecast_moments(
        filtered,
        solution,
        measurement,
        true,
    )
    @test_throws MethodError draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        true,
        3;
        seed = 3,
    )
    @test_throws MethodError draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        4,
        true;
        seed = 3,
    )
    @test_throws TypeError draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        4,
        3;
        seed = true,
    )
    @test_throws MethodError simulate_synthetic_observations(
        parameters,
        true;
        seed = 3,
    )

    invalid_system = build_canonical_system(parameters)
    invalid_gamma0 = copy(invalid_system.gamma0)
    invalid_gamma0[1, 1] = Inf
    @test_throws SmallNKMechanicsError solve_gensys(
        CanonicalSystem(
            invalid_gamma0,
            invalid_system.gamma1,
            invalid_system.constant,
            invalid_system.shock_loading,
            invalid_system.expectational_loading,
        ),
    )
    @test_throws SmallNKMechanicsError mechanics_fingerprint(
        parameters,
        scaled_system(build_canonical_system(parameters), 2.0),
        solution,
        measurement,
    )
    @test_throws SmallNKMechanicsError mechanics_fingerprint(
        parameters,
        build_canonical_system(parameters),
        solution,
        noisy,
    )
end

@testset "mechanics remains unregistered and unscored" begin
    registry = read(
        joinpath(@__DIR__, "..", "benchmark_model_registry.toml"),
        String,
    )
    @test !occursin("small_new_keynesian_dsge", registry)
    @test !occursin("quarterly_nk3_aggregate_pce_contract_v1", registry)
    @test !isdefined(NK, :forecast)
    @test !isdefined(NK, :score)
    @test NK.STATUS == "FIXED_PARAMETER_DSGE_MECHANICS_VALIDATED_NO_EMPIRICAL_EVIDENCE"
end
