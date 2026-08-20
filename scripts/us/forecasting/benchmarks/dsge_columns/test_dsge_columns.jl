# Hermetic tests for the Stage-2b DSGE scored columns.
#
# Run:
#   julia --startup-file=no --check-bounds=yes --project=scripts/us \
#     scripts/us/forecasting/benchmarks/dsge_columns/test_dsge_columns.jl

using Test
using LinearAlgebra
using Statistics

include(joinpath(@__DIR__, "USDSGEColumns.jl"))
using .USDSGEColumns
const D = USDSGEColumns

@testset "dsge columns" begin
    @testset "generic gensys oracle against sealed solver" begin
        parameters = D.NK.reference_parameters()
        system = D.NK.build_canonical_system(parameters)
        sealed = D.NK.solve_gensys(system)
        generic = D.generic_gensys(
            system.gamma0, system.gamma1, system.constant,
            system.shock_loading, system.expectational_loading,
        )
        @test maximum(abs.(sealed.transition .- generic.transition)) <= 1.0e-12
        @test maximum(abs.(sealed.impact .- generic.impact)) <= 1.0e-12
        @test maximum(abs.(sealed.constant .- generic.constant)) <= 1.0e-12
        @test generic.eu == sealed.eu == (1, 1)
        @test generic.stable_root_count == sealed.stable_root_count
        # indeterminacy fails closed exactly like the sealed solver
        weak = D.NK.SmallNKParameters(
            2.0, 0.15, 0.5, 0.5, 1.0, 3.0, 0.5, 0.6, 0.9, 0.9, 0.2, 0.6, 0.3,
        )
        weak_system = D.NK.build_canonical_system(weak)
        @test_throws Exception D.generic_gensys(
            weak_system.gamma0, weak_system.gamma1, weak_system.constant,
            weak_system.shock_loading, weak_system.expectational_loading,
        )
    end

    @testset "sw07 assembly and solution at the published mode" begin
        names = D.sw07_parameter_names()
        @test length(names) == 36
        mode = Float64[D.sw07_mode_start()[n] for n in names]
        space = D.sw07_state_space(mode)
        @test space.solution.eu == (1, 1)
        # 12 expectational errors -> exactly 12 unstable roots
        @test space.solution.unstable_root_count == 12
        @test size(space.Z) == (7, length(D.SW07_STATE_NAMES))
        @test size(space.Q) == (7, 7)
        radius = maximum(abs.(eigvals(space.solution.transition)))
        @test radius < 1.0 - 1.0e-6
    end

    @testset "sw07 kalman filter matches a direct implementation" begin
        # simulate a short synthetic sample at the mode and cross-check the
        # optimized (steady-state-switching) filter against a plain filter
        names = D.sw07_parameter_names()
        mode = Float64[D.sw07_mode_start()[n] for n in names]
        space = D.sw07_state_space(mode)
        T_mat = space.solution.transition
        R_mat = space.solution.impact
        sd = sqrt.(diag(space.Q))
        n_state = size(T_mat, 1)
        state = zeros(n_state)
        observations = Matrix{Float64}(undef, 60, 7)
        for t in 1:60
            shocks = [sd[k] * sin(0.7 * t + 1.3 * k) for k in 1:7]
            state = T_mat * state + R_mat * shocks
            observations[t, :] = space.Z * state + space.d
        end
        fast, _, _ = D.kalman_loglikelihood(
            observations, T_mat, space.solution.constant, R_mat, space.Q,
            space.Z, space.d,
        )
        # plain reference filter without the steady-state switch
        RQR = R_mat * space.Q * R_mat'
        s = (I - T_mat) \ space.solution.constant
        P = Matrix(D.lyapunov_covariance(T_mat, RQR))
        reference = 0.0
        for t in 1:60
            s_pred = T_mat * s + space.solution.constant
            P_pred = T_mat * P * T_mat' + RQR
            innovation = vec(observations[t, :]) - (space.Z * s_pred + space.d)
            F = cholesky(
                Symmetric(space.Z * P_pred * space.Z') + 1.0e-12 * I,
            )
            half = F.L \ innovation
            reference += -0.5 * (
                7 * log(2.0 * pi) + 2.0 * sum(log.(diag(F.L))) + dot(half, half)
            )
            K = (P_pred * space.Z') / F
            s = s_pred + K * innovation
            P = (P_pred - K * space.Z * P_pred + (P_pred - K * space.Z * P_pred)') / 2.0
        end
        @test isapprox(fast, reference; rtol = 1.0e-8)
    end

    @testset "sw07 synthetic mode recovery moves toward truth" begin
        # estimation on model-generated data must improve the posterior over a
        # perturbed start and keep determinacy
        names = D.sw07_parameter_names()
        mode = Float64[D.sw07_mode_start()[n] for n in names]
        space = D.sw07_state_space(mode)
        T_mat = space.solution.transition
        R_mat = space.solution.impact
        sd = sqrt.(diag(space.Q))
        n_state = size(T_mat, 1)
        state = zeros(n_state)
        observations = Matrix{Float64}(undef, 160, 7)
        for t in 1:160
            shocks = [
                sd[k] * (sin(0.9 * t + 0.7 * k) + cos(0.31 * t * k)) / sqrt(2.0)
                    for k in 1:7
            ]
            state = T_mat * state + R_mat * shocks
            observations[t, :] = space.Z * state + space.d
        end
        truth_lp = D.sw07_log_posterior(observations, mode)
        transforms = D.sw07_transforms()
        perturbed = [
            D.to_domain(
                    transforms[i],
                    D.to_unconstrained(transforms[i], mode[i]) + 0.15 * sin(3.1 * i),
                ) for i in 1:36
        ]
        perturbed_lp = D.sw07_log_posterior(observations, perturbed)
        result = D.sw07_estimate(
            observations; start = perturbed, max_evaluations = 1200,
        )
        @test result.usable
        @test result.log_posterior > perturbed_lp
        @test result.space.solution.eu == (1, 1)
    end

    @testset "small-NK estimation improves the posterior" begin
        parameters = D.NK.reference_parameters()
        observations = D.NK.simulate_synthetic_observations(
            parameters, 120; seed = 42,
        )
        start = D.small_nk_vector(D.NK.adapted_mechanics_parameters())
        start_lp = D.small_nk_log_posterior(observations, start)
        result = D.small_nk_estimate(
            observations; start = start, max_evaluations = 1500,
        )
        @test result.usable
        @test result.log_posterior >= start_lp
        @test result.solution.eu == (1, 1)
    end

    @testset "okun bridge and path simulation" begin
        growth = [2.0 + 1.5 * sin(0.4 * t) for t in 1:60]
        unemployment = zeros(60)
        unemployment[1] = 6.0
        for t in 2:60
            unemployment[t] =
                unemployment[t - 1] + 0.05 - 0.09 * growth[t] + 0.03 * cos(1.7 * t)
        end
        intercept, slope, sigma = D.okun_bridge(growth, unemployment)
        @test slope < 0.0                      # growth lowers unemployment
        @test isapprox(slope, -0.09; atol = 0.02)
        @test sigma > 0.0
        rng = D.Random.MersenneTwister(7)
        paths = D.simulate_unemployment_paths(
            rng, fill(2.0, 12, 40), 5.0, intercept, slope, sigma,
        )
        @test size(paths) == (12, 40)
        @test all(paths .>= 0.0)               # floored at zero
        @test_throws ArgumentError D.okun_bridge(growth[1:10], unemployment[1:10])
    end

    @testset "deterministic emission schema" begin
        @test D.quarter_add("2010Q2", 1) == "2010Q3"
        @test D.quarter_add("2010Q4", 1) == "2011Q1"
        @test D.quarter_add("2025Q2", 12) == "2028Q2"
        @test D.compose_nominal(2.0, 2.0) ≈
            400.0 * ((1.0 + 2.0 / 400.0)^2 - 1.0)
    end
end
