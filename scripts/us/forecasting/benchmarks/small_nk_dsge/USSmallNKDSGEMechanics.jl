module USSmallNKDSGEMechanics

using LinearAlgebra
using Random
using SHA
using TOML

export CanonicalSystem,
    FilterResult,
    GensysSolution,
    MeasurementSystem,
    SmallNKMechanicsError,
    SmallNKParameters,
    adapted_mechanics_parameters,
    build_canonical_system,
    build_measurement_system,
    classify_generalized_roots,
    conditional_forecast_moments,
    draw_joint_predictive_paths,
    filter_loglikelihood,
    load_reference_fixture,
    mechanics_fingerprint,
    reference_parameters,
    simulate_synthetic_observations,
    solve_gensys,
    stationary_state_moments

const MODEL_CLASS = "small_new_keynesian_dsge"
const TARGET_PANEL_ID = "quarterly_nk3_aggregate_pce_contract_v1"
const STATUS = "FIXED_PARAMETER_DSGE_MECHANICS_VALIDATED_NO_EMPIRICAL_EVIDENCE"
const STATE_NAMES = (:y, :pi, :rate, :y_lag, :g, :z, :expected_y, :expected_pi)
const SHOCK_NAMES = (:technology, :government_spending, :monetary_policy)
const OBSERVABLE_NAMES = (:real_gdp_growth, :pce_inflation, :effective_federal_funds_rate)
const UNIT_ROOT_BAND = 1.0e-6
const SCHUR_ZERO_TOLERANCE = 1.0e-12
const SVD_TOLERANCE = 1.0e-6
const REALITY_TOLERANCE = 5.0e-10
const EQUATION_RESIDUAL_TOLERANCE = 1.0e-9
const COVARIANCE_TOLERANCE = 1.0e-9
const MAXIMUM_PREDICTIVE_HORIZON = 12
const PREDICTIVE_RNG_SCHEME =
    "sha256-domain-separated-mersenne-twister-per-path.v1"
const ADAPTED_MECHANICS_FINGERPRINT_SHA256 =
    "d45d4432c7e24bbe78e03c2953bd02cba52a89f942d45d9d6f11ad0fbc540e21"
const REFERENCE_FIXTURE_PATH = joinpath(@__DIR__, "frbny_gensys_reference.toml")
const REFERENCE_FIXTURE_SHA256 =
    "ec0a4a891e49e518ab5e08b98fdeda6b828f1b611600a3ddf4e198d0c70bc89e"
const REFERENCE_UPSTREAM_METADATA = (
    "repository" => "https://github.com/FRBNY-DSGE/DSGE.jl",
    "tag" => "v1.3.0",
    "commit" => "45c26624ec225d6d355219cde71638f6171694ad",
    "license" => "BSD-3-Clause",
    "stake_ieee754_hex" => "0x3ff000010c6f7a0b",
    "model_source_url" => "https://raw.githubusercontent.com/FRBNY-DSGE/DSGE.jl/v1.3.0/src/models/representative/an_schorfheide/an_schorfheide.jl",
    "model_source_sha256" => "2fa0fa3fd0971ffde20181e967492bbff9f638181ce7dbae539dfe1fdbf2b87e",
    "equilibrium_source_url" => "https://raw.githubusercontent.com/FRBNY-DSGE/DSGE.jl/v1.3.0/src/models/representative/an_schorfheide/eqcond.jl",
    "equilibrium_source_sha256" => "104fa4c91950fb9f9b023c6dc85014ebff0b49b5e7caf88b532f68c7f8604b8d",
    "measurement_source_url" => "https://raw.githubusercontent.com/FRBNY-DSGE/DSGE.jl/v1.3.0/src/models/representative/an_schorfheide/measurement.jl",
    "measurement_source_sha256" => "8cd81cf19a039337261569081328604250095ab5a2e3141f32b3f17a80f06402",
    "solver_source_url" => "https://raw.githubusercontent.com/FRBNY-DSGE/DSGE.jl/v1.3.0/src/solve/gensys.jl",
    "solver_source_sha256" => "a8bba403c557dd27176b9045cb4b236998c55fd4a5fd36cbb5a58fe9b85aba1b",
    "test_source_url" => "https://raw.githubusercontent.com/FRBNY-DSGE/DSGE.jl/v1.3.0/test/solve/gensys.jl",
    "test_source_sha256" => "3347367070a39aeb951e99929937f6288a68aeb90943ae5cdeb7f1cda672895c",
    "reference_hdf5_url" => "https://raw.githubusercontent.com/FRBNY-DSGE/DSGE.jl/v1.3.0/test/reference/gensys.h5",
    "reference_hdf5_sha256" => "42bc870270cc66e5699c09faf8ce00bdfb3d27c49936a058f0afea48f20cbb92",
    "numeric_storage" => "column_major_ieee754_binary64_bits",
)

struct SmallNKMechanicsError <: Exception
    message::String
end

Base.showerror(io::IO, error::SmallNKMechanicsError) = print(io, error.message)
fail(message) = throw(SmallNKMechanicsError(String(message)))

struct SmallNKParameters
    tau::Float64
    kappa::Float64
    psi1::Float64
    psi2::Float64
    r_annual::Float64
    pi_star::Float64
    gamma_quarterly::Float64
    rho_rate::Float64
    rho_g::Float64
    rho_z::Float64
    sigma_rate::Float64
    sigma_g::Float64
    sigma_z::Float64

    function SmallNKParameters(
            tau,
            kappa,
            psi1,
            psi2,
            r_annual,
            pi_star,
            gamma_quarterly,
            rho_rate,
            rho_g,
            rho_z,
            sigma_rate,
            sigma_g,
            sigma_z,
        )
        values = (
            tau,
            kappa,
            psi1,
            psi2,
            r_annual,
            pi_star,
            gamma_quarterly,
            rho_rate,
            rho_g,
            rho_z,
            sigma_rate,
            sigma_g,
            sigma_z,
        )
        all(value -> typeof(value) === Float64, values) ||
            fail("SmallNKParameters requires exact Float64 arguments")
        return new(values...)
    end
end

struct CanonicalSystem
    gamma0::Matrix{Float64}
    gamma1::Matrix{Float64}
    constant::Vector{Float64}
    shock_loading::Matrix{Float64}
    expectational_loading::Matrix{Float64}
end

struct GensysSolution
    transition::Matrix{Float64}
    constant::Vector{Float64}
    impact::Matrix{Float64}
    eu::NTuple{2, Int}
    generalized_roots::Vector{ComplexF64}
    stable_root_count::Int
    unstable_root_count::Int
    equation_residual_max::Float64
end

struct MeasurementSystem
    loading::Matrix{Float64}
    intercept::Vector{Float64}
    shock_covariance::Matrix{Float64}
    measurement_covariance::Matrix{Float64}
end

struct FilterResult
    loglikelihood::Float64
    filtered_mean::Vector{Float64}
    filtered_covariance::Matrix{Float64}
    innovation_ranks::Vector{Int}
end

function _exact_float(value, location)
    typeof(value) === Float64 || fail("$location must be exactly Float64")
    isfinite(value) || fail("$location must be finite")
    return value
end

function validate_parameters(parameters::SmallNKParameters)
    for field in fieldnames(SmallNKParameters)
        _exact_float(getfield(parameters, field), "parameters.$field")
    end
    parameters.tau > 0.0 || fail("parameters.tau must be positive")
    0.0 < parameters.kappa < 1.0 ||
        fail("parameters.kappa must lie strictly between zero and one")
    parameters.psi1 > 0.0 || fail("parameters.psi1 must be positive")
    parameters.psi2 > 0.0 || fail("parameters.psi2 must be positive")
    parameters.r_annual > 0.0 || fail("parameters.r_annual must be positive")
    for field in (:rho_rate, :rho_g, :rho_z)
        0.0 < getfield(parameters, field) < 1.0 ||
            fail("parameters.$field must lie strictly between zero and one")
    end
    for field in (:sigma_rate, :sigma_g, :sigma_z)
        getfield(parameters, field) > 0.0 ||
            fail("parameters.$field must be positive")
    end
    return parameters
end

"""Exact FRBNY v1.3.0 `AnSchorfheide()` defaults used by the solver fixture."""
reference_parameters() = validate_parameters(
    SmallNKParameters(
        1.9937,
        0.7306,
        1.1434,
        0.4536,
        0.0313,
        8.1508,
        1.5,
        0.3847,
        0.3777,
        0.9579,
        0.49,
        1.4594,
        0.9247,
    ),
)

"""Fixed, synthetic-only aggregate-PCE mechanics calibration; it is not estimated."""
adapted_mechanics_parameters() = validate_parameters(
    SmallNKParameters(
        2.0,
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
    ),
)

function build_canonical_system(parameters::SmallNKParameters)
    p = validate_parameters(parameters)
    gamma0 = zeros(Float64, 8, 8)
    gamma1 = zeros(Float64, 8, 8)
    constant = zeros(Float64, 8)
    psi = zeros(Float64, 8, 3)
    pi_loading = zeros(Float64, 8, 2)

    y, inflation, rate, y_lag, government, technology, expected_y, expected_pi = 1:8
    technology_shock, government_shock, policy_shock = 1:3
    expected_y_shock, expected_pi_shock = 1:2
    euler, phillips, policy, lag_equation, government_equation, technology_equation,
        expected_y_equation, expected_pi_equation = 1:8

    gamma0[euler, y] = 1.0
    gamma0[euler, rate] = 1.0 / p.tau
    gamma0[euler, government] = -(1.0 - p.rho_g)
    gamma0[euler, technology] = -p.rho_z / p.tau
    gamma0[euler, expected_y] = -1.0
    gamma0[euler, expected_pi] = -1.0 / p.tau

    gamma0[phillips, y] = -p.kappa
    gamma0[phillips, inflation] = 1.0
    gamma0[phillips, government] = p.kappa
    gamma0[phillips, expected_pi] = -1.0 / (1.0 + p.r_annual / 400.0)

    gamma0[policy, y] = -(1.0 - p.rho_rate) * p.psi2
    gamma0[policy, inflation] = -(1.0 - p.rho_rate) * p.psi1
    gamma0[policy, rate] = 1.0
    gamma0[policy, government] = (1.0 - p.rho_rate) * p.psi2
    gamma1[policy, rate] = p.rho_rate
    psi[policy, policy_shock] = 1.0

    gamma0[lag_equation, y_lag] = 1.0
    gamma1[lag_equation, y] = 1.0

    gamma0[government_equation, government] = 1.0
    gamma1[government_equation, government] = p.rho_g
    psi[government_equation, government_shock] = 1.0

    gamma0[technology_equation, technology] = 1.0
    gamma1[technology_equation, technology] = p.rho_z
    psi[technology_equation, technology_shock] = 1.0

    gamma0[expected_y_equation, y] = 1.0
    gamma1[expected_y_equation, expected_y] = 1.0
    pi_loading[expected_y_equation, expected_y_shock] = 1.0

    gamma0[expected_pi_equation, inflation] = 1.0
    gamma1[expected_pi_equation, expected_pi] = 1.0
    pi_loading[expected_pi_equation, expected_pi_shock] = 1.0

    return _validate_canonical_system(
        CanonicalSystem(gamma0, gamma1, constant, psi, pi_loading),
    )
end

function build_measurement_system(parameters::SmallNKParameters)
    p = validate_parameters(parameters)
    loading = zeros(Float64, 3, 8)
    intercept = zeros(Float64, 3)
    y, inflation, rate, y_lag, _, technology = 1:6

    loading[1, y] = 4.0
    loading[1, y_lag] = -4.0
    loading[1, technology] = 4.0
    intercept[1] = 4.0 * p.gamma_quarterly

    loading[2, inflation] = 4.0
    intercept[2] = p.pi_star

    loading[3, rate] = 4.0
    intercept[3] =
        p.pi_star + p.r_annual + 4.0 * p.gamma_quarterly

    shock_covariance = Diagonal(
        [
            p.sigma_z^2,
            p.sigma_g^2,
            p.sigma_rate^2,
        ]
    ) |> Matrix
    measurement_covariance = zeros(Float64, 3, 3)
    return _validate_measurement(
        MeasurementSystem(
            loading,
            intercept,
            shock_covariance,
            measurement_covariance,
        ),
    )
end

function _validate_canonical_system(system::CanonicalSystem)
    size(system.gamma0) == (8, 8) || fail("gamma0 must be 8 by 8")
    size(system.gamma1) == (8, 8) || fail("gamma1 must be 8 by 8")
    size(system.constant) == (8,) || fail("constant must contain eight values")
    size(system.shock_loading) == (8, 3) ||
        fail("shock_loading must be 8 by 3")
    size(system.expectational_loading) == (8, 2) ||
        fail("expectational_loading must be 8 by 2")
    for field in fieldnames(CanonicalSystem)
        all(isfinite, getfield(system, field)) || fail("$field contains nonfinite values")
    end
    return system
end

function _normalized_canonical_system(system::CanonicalSystem)
    validated = _validate_canonical_system(system)
    values = (
        validated.gamma0,
        validated.gamma1,
        validated.constant,
        validated.shock_loading,
        validated.expectational_loading,
    )
    scale = maximum(maximum(abs, value) for value in values)
    isfinite(scale) && scale > 0.0 ||
        fail("canonical system has no finite positive normalization scale")
    normalized = CanonicalSystem(
        validated.gamma0 ./ scale,
        validated.gamma1 ./ scale,
        validated.constant ./ scale,
        validated.shock_loading ./ scale,
        validated.expectational_loading ./ scale,
    )
    return _validate_canonical_system(normalized)
end

function classify_generalized_roots(
        schur_s::AbstractMatrix{<:Complex},
        schur_t::AbstractMatrix{<:Complex};
        unit_band::Float64 = UNIT_ROOT_BAND,
        zero_tolerance::Float64 = SCHUR_ZERO_TOLERANCE,
    )
    size(schur_s) == size(schur_t) || fail("generalized Schur factors differ in size")
    size(schur_s, 1) == size(schur_s, 2) || fail("Schur factors must be square")
    !isempty(schur_s) || fail("Schur factors must not be empty")
    all(isfinite, schur_s) && all(isfinite, schur_t) ||
        fail("Schur factors must be finite")
    isfinite(unit_band) && 0.0 < unit_band < 1.0 ||
        fail("unit-root band must be finite and lie between zero and one")
    isfinite(zero_tolerance) && zero_tolerance > 0.0 ||
        fail("relative Schur-zero tolerance must be finite and positive")
    schur_scale = max(maximum(abs, schur_s), maximum(abs, schur_t))
    isfinite(schur_scale) && schur_scale > 0.0 ||
        fail("Schur factors have no finite positive scale")
    zero_cutoff = zero_tolerance * schur_scale
    roots = ComplexF64[]
    stable = Bool[]
    for index in axes(schur_s, 1)
        s = ComplexF64(schur_s[index, index])
        t = ComplexF64(schur_t[index, index])
        if abs(s) <= zero_cutoff && abs(t) <= zero_cutoff
            fail("coincident generalized-Schur zeros at index $index")
        end
        root = abs(s) <= zero_cutoff ? ComplexF64(Inf) : t / s
        modulus = abs(root)
        if 1.0 - unit_band <= modulus <= 1.0 + unit_band
            fail("generalized root $index lies in the sealed unit-root exclusion band")
        end
        push!(roots, root)
        push!(stable, modulus < 1.0 - unit_band)
    end
    return (; roots, stable)
end

function _svd_subspaces(matrix::Matrix{ComplexF64}, tolerance::Float64)
    decomposition = svd(matrix)
    maximum_singular_value = isempty(decomposition.S) ? 0.0 : maximum(decomposition.S)
    cutoff = tolerance * maximum_singular_value
    selected = findall(value -> value > cutoff, decomposition.S)
    return (
        u = decomposition.U[:, selected],
        v = decomposition.V[:, selected],
        d = Matrix(Diagonal(decomposition.S[selected])),
        rank = length(selected),
    )
end

function _maximum_imaginary(values...)
    maximum_value = 0.0
    for value in values
        isempty(value) && continue
        maximum_value = max(maximum_value, maximum(abs, imag.(value)))
    end
    return maximum_value
end

function _equation_residual_max(
        system::CanonicalSystem,
        transition::Matrix{Float64},
        constant::Vector{Float64},
        impact::Matrix{Float64},
    )
    residuals = (
        system.gamma0 * transition - system.gamma1,
        reshape(system.gamma0 * constant - system.constant, :, 1),
        system.gamma0 * impact - system.shock_loading,
    )
    maximum_residual = 0.0
    for residual in residuals
        expectational_coefficients =
            system.expectational_loading \ residual
        closure = residual -
            system.expectational_loading * expectational_coefficients
        maximum_residual = max(maximum_residual, maximum(abs, closure))
    end
    return maximum_residual
end

function solve_gensys(
        system::CanonicalSystem;
        unit_band::Float64 = UNIT_ROOT_BAND,
        zero_tolerance::Float64 = SCHUR_ZERO_TOLERANCE,
        svd_tolerance::Float64 = SVD_TOLERANCE,
        reality_tolerance::Float64 = REALITY_TOLERANCE,
        equation_residual_tolerance::Float64 = EQUATION_RESIDUAL_TOLERANCE,
        require_determinate::Bool = true,
    )
    working_system = _normalized_canonical_system(system)
    typeof(require_determinate) === Bool || fail("require_determinate must be Bool")
    isfinite(svd_tolerance) && svd_tolerance > 0.0 ||
        fail("relative SVD tolerance must be finite and positive")
    isfinite(reality_tolerance) && reality_tolerance > 0.0 ||
        fail("reality tolerance must be finite and positive")
    isfinite(equation_residual_tolerance) && equation_residual_tolerance > 0.0 ||
        fail("normalized equation-residual tolerance must be finite and positive")

    decomposition = try
        schur(complex(working_system.gamma0), complex(working_system.gamma1))
    catch error
        fail("generalized Schur decomposition failed: $(sprint(showerror, error))")
    end
    classification = classify_generalized_roots(
        decomposition.S,
        decomposition.T;
        unit_band,
        zero_tolerance,
    )
    ordered = try
        ordschur(decomposition, classification.stable)
    catch error
        fail("generalized Schur reordering failed: $(sprint(showerror, error))")
    end

    a = ordered.S
    b = ordered.T
    q = ordered.Q
    z = ordered.Z
    state_count = size(a, 1)
    stable_count = count(classification.stable)
    unstable_count = state_count - stable_count
    shock_count = size(working_system.shock_loading, 2)
    q_stable = q[:, 1:stable_count]
    q_unstable = q[:, (stable_count + 1):state_count]

    eta_unstable = Matrix{ComplexF64}(
        q_unstable' * working_system.expectational_loading,
    )
    unstable_svd = _svd_subspaces(eta_unstable, svd_tolerance)
    existence = unstable_svd.rank >= unstable_count

    eta_stable = Matrix{ComplexF64}(
        q_stable' * working_system.expectational_loading,
    )
    stable_svd = _svd_subspaces(eta_stable, svd_tolerance)
    if stable_svd.rank == 0
        uniqueness = true
    else
        projection = unstable_svd.v * unstable_svd.v'
        loose = stable_svd.v - projection * stable_svd.v
        loose_singular_values = svdvals(loose)
        uniqueness = all(value -> value <= svd_tolerance * state_count, loose_singular_values)
    end
    eu = (existence ? 1 : 0, uniqueness ? 1 : 0)

    if unstable_svd.rank == 0 || stable_svd.rank == 0
        correction = zeros(ComplexF64, stable_count, unstable_count)
    else
        correction = -(
            unstable_svd.u *
                (unstable_svd.d \ unstable_svd.v') *
                stable_svd.v *
                (stable_svd.d * stable_svd.u')
        )'
    end
    transformation = hcat(
        Matrix{ComplexF64}(I, stable_count, stable_count),
        correction,
    )
    bottom = hcat(
        zeros(ComplexF64, unstable_count, stable_count),
        Matrix{ComplexF64}(I, unstable_count, unstable_count),
    )
    g0 = vcat(transformation * a, bottom)
    g1_rhs = vcat(transformation * b, zeros(ComplexF64, unstable_count, state_count))
    q_constant = q' * working_system.constant
    q_shocks = q' * working_system.shock_loading
    if unstable_count == 0
        unstable_constant = ComplexF64[]
    else
        unstable_range = (stable_count + 1):state_count
        unstable_constant =
            (a[unstable_range, unstable_range] - b[unstable_range, unstable_range]) \
            (q_unstable' * working_system.constant)
    end
    constant_rhs = vcat(transformation * q_constant, unstable_constant)
    impact_rhs = vcat(
        transformation * q_shocks,
        zeros(ComplexF64, unstable_count, shock_count),
    )
    transition_complex = z * ((g0 \ g1_rhs) * z')
    constant_complex = z * (g0 \ constant_rhs)
    impact_complex = z * (g0 \ impact_rhs)
    _maximum_imaginary(transition_complex, constant_complex, impact_complex) <=
        reality_tolerance || fail("gensys solution has a material imaginary component")

    transition = real(transition_complex)
    constant = real(constant_complex)
    impact = real(impact_complex)
    all(isfinite, transition) || fail("gensys transition is nonfinite")
    all(isfinite, constant) || fail("gensys constant is nonfinite")
    all(isfinite, impact) || fail("gensys impact is nonfinite")
    equation_residual_max =
        _equation_residual_max(working_system, transition, constant, impact)
    if eu == (1, 1)
        equation_residual_max <= equation_residual_tolerance ||
            fail("gensys solution does not close the canonical equations")
    end
    spectral_radius = maximum(abs, eigvals(transition))
    spectral_radius < 1.0 - unit_band ||
        fail("reduced transition is not strictly stationary")
    require_determinate && eu != (1, 1) &&
        fail("gensys existence/uniqueness failed with eu=$eu")
    return GensysSolution(
        transition,
        constant,
        impact,
        eu,
        classification.roots,
        stable_count,
        unstable_count,
        equation_residual_max,
    )
end

function _validate_measurement(measurement::MeasurementSystem)
    size(measurement.loading) == (3, 8) || fail("measurement loading must be 3 by 8")
    size(measurement.intercept) == (3,) || fail("measurement intercept must contain three values")
    size(measurement.shock_covariance) == (3, 3) || fail("shock covariance must be 3 by 3")
    size(measurement.measurement_covariance) == (3, 3) ||
        fail("measurement covariance must be 3 by 3")
    for field in fieldnames(MeasurementSystem)
        all(isfinite, getfield(measurement, field)) || fail("measurement.$field is nonfinite")
    end
    measurement.shock_covariance == Diagonal(diag(measurement.shock_covariance)) ||
        fail("structural shocks must remain mutually independent")
    all(value -> value > 0.0, diag(measurement.shock_covariance)) ||
        fail("structural-shock variances must be positive")
    measurement.measurement_covariance == zeros(3, 3) ||
        fail("base mechanics measurement error must remain exactly zero")
    rank(measurement.loading; atol = COVARIANCE_TOLERANCE, rtol = 0.0) == 3 ||
        fail("measurement loading must have full observable rank")
    return measurement
end

function _validate_solution(solution::GensysSolution)
    size(solution.transition) == (8, 8) ||
        fail("solution transition must be 8 by 8")
    size(solution.constant) == (8,) ||
        fail("solution constant must contain eight values")
    size(solution.impact) == (8, 3) ||
        fail("solution impact must be 8 by 3")
    for field in (:transition, :constant, :impact)
        all(isfinite, getfield(solution, field)) ||
            fail("solution.$field contains nonfinite values")
    end
    solution.eu == (1, 1) ||
        fail("downstream mechanics require a determinate solution")
    length(solution.generalized_roots) == 8 ||
        fail("solution must contain eight generalized roots")
    for (index, root) in enumerate(solution.generalized_roots)
        (isnan(real(root)) || isnan(imag(root))) &&
            fail("solution generalized root $index contains NaN")
        (isfinite(root) || (isinf(real(root)) && imag(root) == 0.0)) ||
            fail("solution generalized root $index has an invalid infinite form")
        modulus = abs(root)
        1.0 - UNIT_ROOT_BAND <= modulus <= 1.0 + UNIT_ROOT_BAND &&
            fail("solution generalized root $index lies in the unit-root band")
    end
    0 <= solution.stable_root_count <= 8 ||
        fail("solution stable-root count is invalid")
    0 <= solution.unstable_root_count <= 8 ||
        fail("solution unstable-root count is invalid")
    solution.stable_root_count + solution.unstable_root_count == 8 ||
        fail("solution root counts do not sum to eight")
    derived_stable_count = count(
        root -> abs(root) < 1.0 - UNIT_ROOT_BAND,
        solution.generalized_roots,
    )
    solution.stable_root_count == derived_stable_count ||
        fail("solution stable-root count does not match its roots")
    solution.unstable_root_count == 8 - derived_stable_count ||
        fail("solution unstable-root count does not match its roots")
    isfinite(solution.equation_residual_max) &&
        0.0 <= solution.equation_residual_max <= EQUATION_RESIDUAL_TOLERANCE ||
        fail("solution normalized equation residual is invalid")
    spectral_radius = try
        maximum(abs, eigvals(solution.transition))
    catch error
        fail("solution spectral-radius calculation failed: $(sprint(showerror, error))")
    end
    isfinite(spectral_radius) && spectral_radius < 1.0 - UNIT_ROOT_BAND ||
        fail("solution transition is not finite and strictly stationary")
    return solution
end

function _validate_filter_result(
        filtered::FilterResult;
        covariance_tolerance::Float64 = COVARIANCE_TOLERANCE,
    )
    isfinite(covariance_tolerance) && covariance_tolerance > 0.0 ||
        fail("filter covariance tolerance must be finite and positive")
    isfinite(filtered.loglikelihood) ||
        fail("filtered log likelihood must be finite")
    size(filtered.filtered_mean) == (8,) ||
        fail("filtered mean must contain eight states")
    size(filtered.filtered_covariance) == (8, 8) ||
        fail("filtered covariance must be 8 by 8")
    all(isfinite, filtered.filtered_mean) ||
        fail("filtered mean contains nonfinite values")
    all(isfinite, filtered.filtered_covariance) ||
        fail("filtered covariance contains nonfinite values")
    maximum(abs, filtered.filtered_covariance - filtered.filtered_covariance') <=
        covariance_tolerance || fail("filtered covariance is not symmetric")
    minimum(eigvals(Symmetric(filtered.filtered_covariance))) >=
        -covariance_tolerance ||
        fail("filtered covariance is not positive semidefinite")
    !isempty(filtered.innovation_ranks) ||
        fail("filtered result has no innovation-rank evidence")
    all(==(3), filtered.innovation_ranks) ||
        fail("filtered result contains a non-full-rank innovation")
    return filtered
end

function stationary_state_moments(
        solution::GensysSolution,
        measurement::MeasurementSystem;
        covariance_tolerance::Float64 = COVARIANCE_TOLERANCE,
    )
    _validate_solution(solution)
    _validate_measurement(measurement)
    isfinite(covariance_tolerance) && covariance_tolerance > 0.0 ||
        fail("covariance tolerance must be finite and positive")
    transition = solution.transition
    state_count = size(transition, 1)
    state_shock_covariance =
        solution.impact * measurement.shock_covariance * solution.impact'
    system = Matrix{Float64}(I, state_count^2, state_count^2) -
        kron(transition, transition)
    covariance = reshape(system \ vec(state_shock_covariance), state_count, state_count)
    covariance = Matrix(Symmetric((covariance + covariance') / 2.0))
    all(isfinite, covariance) ||
        fail("stationary state covariance contains nonfinite values")
    minimum(eigvals(Symmetric(covariance))) >= -covariance_tolerance ||
        fail("stationary state covariance is not positive semidefinite")
    mean_state = (Matrix{Float64}(I, state_count, state_count) - transition) \
        solution.constant
    all(isfinite, mean_state) || fail("stationary state mean is nonfinite")
    observation_covariance = Matrix(
        Symmetric(
            measurement.loading * covariance * measurement.loading' +
                measurement.measurement_covariance,
        )
    )
    all(isfinite, observation_covariance) ||
        fail("stationary observation covariance contains nonfinite values")
    rank(observation_covariance; atol = covariance_tolerance, rtol = 0.0) == 3 ||
        fail("stationary observation covariance is rank deficient")
    cholesky(Symmetric(observation_covariance); check = true)
    return (; mean = mean_state, covariance, observation_covariance)
end

function _strict_innovation_factor(covariance, tolerance, location)
    symmetric = Matrix(Symmetric((covariance + covariance') / 2.0))
    rank(symmetric; atol = tolerance, rtol = 0.0) == size(symmetric, 1) ||
        fail("$location innovation covariance is rank deficient")
    return try
        cholesky(Symmetric(symmetric); check = true)
    catch error
        fail("$location innovation covariance is not positive definite: $(sprint(showerror, error))")
    end
end

function filter_loglikelihood(
        observations::Matrix{Float64},
        solution::GensysSolution,
        measurement::MeasurementSystem;
        covariance_tolerance::Float64 = COVARIANCE_TOLERANCE,
    )
    _validate_solution(solution)
    _validate_measurement(measurement)
    isfinite(covariance_tolerance) && covariance_tolerance > 0.0 ||
        fail("covariance tolerance must be finite and positive")
    size(observations, 2) == 3 || fail("observations must have exactly three columns")
    size(observations, 1) >= 1 || fail("observations must contain at least one quarter")
    all(isfinite, observations) || fail("observations contain nonfinite values")
    moments = stationary_state_moments(
        solution,
        measurement;
        covariance_tolerance,
    )
    state_mean = copy(moments.mean)
    state_covariance = copy(moments.covariance)
    state_shock_covariance =
        solution.impact * measurement.shock_covariance * solution.impact'
    state_identity = Matrix{Float64}(I, length(state_mean), length(state_mean))
    loglikelihood = 0.0
    innovation_ranks = Int[]
    for row in axes(observations, 1)
        predicted_mean = solution.constant + solution.transition * state_mean
        predicted_covariance = Matrix(
            Symmetric(
                solution.transition * state_covariance * solution.transition' +
                    state_shock_covariance,
            )
        )
        all(isfinite, predicted_mean) ||
            fail("predicted state mean is nonfinite at observation $row")
        all(isfinite, predicted_covariance) ||
            fail("predicted state covariance is nonfinite at observation $row")
        innovation =
            observations[row, :] -
            measurement.intercept -
            measurement.loading * predicted_mean
        innovation_covariance = Matrix(
            Symmetric(
                measurement.loading * predicted_covariance * measurement.loading' +
                    measurement.measurement_covariance,
            )
        )
        all(isfinite, innovation) ||
            fail("innovation is nonfinite at observation $row")
        all(isfinite, innovation_covariance) ||
            fail("innovation covariance is nonfinite at observation $row")
        factor = _strict_innovation_factor(
            innovation_covariance,
            covariance_tolerance,
            "observation $row",
        )
        push!(innovation_ranks, rank(innovation_covariance; atol = covariance_tolerance, rtol = 0.0))
        quadratic = dot(innovation, factor \ innovation)
        log_determinant = 2.0 * sum(log, diag(factor.L))
        loglikelihood += -0.5 * (3.0 * log(2.0 * pi) + log_determinant + quadratic)
        gain = (factor \ (measurement.loading * predicted_covariance))'
        state_mean = predicted_mean + gain * innovation
        update = state_identity - gain * measurement.loading
        state_covariance = Matrix(
            Symmetric(
                update * predicted_covariance * update' +
                    gain * measurement.measurement_covariance * gain',
            )
        )
        minimum(eigvals(Symmetric(state_covariance))) >= -covariance_tolerance ||
            fail("filtered covariance became indefinite at observation $row")
    end
    isfinite(loglikelihood) || fail("Kalman log likelihood is nonfinite")
    return _validate_filter_result(
        FilterResult(
            loglikelihood,
            state_mean,
            state_covariance,
            innovation_ranks,
        );
        covariance_tolerance,
    )
end

function conditional_forecast_moments(
        filtered::FilterResult,
        solution::GensysSolution,
        measurement::MeasurementSystem,
        horizon::Int,
    )
    _validate_solution(solution)
    _validate_measurement(measurement)
    _validate_filter_result(filtered)
    typeof(horizon) === Int && 1 <= horizon <= MAXIMUM_PREDICTIVE_HORIZON ||
        fail("forecast horizon must be an exact Int in 1:$MAXIMUM_PREDICTIVE_HORIZON")
    mean_state = copy(filtered.filtered_mean)
    covariance = copy(filtered.filtered_covariance)
    shock_covariance =
        solution.impact * measurement.shock_covariance * solution.impact'
    means = Matrix{Float64}(undef, horizon, 3)
    covariances = Array{Float64, 3}(undef, 3, 3, horizon)
    for step in 1:horizon
        mean_state = solution.constant + solution.transition * mean_state
        covariance = Matrix(
            Symmetric(
                solution.transition * covariance * solution.transition' +
                    shock_covariance,
            )
        )
        means[step, :] = measurement.intercept + measurement.loading * mean_state
        covariances[:, :, step] = Matrix(
            Symmetric(
                measurement.loading * covariance * measurement.loading' +
                    measurement.measurement_covariance,
            )
        )
        all(isfinite, @view(means[step, :])) ||
            fail("forecast mean is nonfinite at horizon $step")
        forecast_covariance = @view covariances[:, :, step]
        all(isfinite, forecast_covariance) ||
            fail("forecast covariance is nonfinite at horizon $step")
        minimum(eigvals(Symmetric(forecast_covariance))) >=
            -COVARIANCE_TOLERANCE ||
            fail("forecast covariance is indefinite at horizon $step")
    end
    return (; means, covariances)
end

function _positive_semidefinite_factor(covariance::Matrix{Float64})
    decomposition = eigen(Symmetric((covariance + covariance') / 2.0))
    minimum(decomposition.values) >= -COVARIANCE_TOLERANCE ||
        fail("predictive covariance is materially indefinite")
    roots = sqrt.(max.(decomposition.values, 0.0))
    return decomposition.vectors * Diagonal(roots)
end

function _domain_separated_path_rng(seed::Int, path::Int)
    path >= 1 || fail("predictive path index must be positive")
    io = IOBuffer()
    write(io, PREDICTIVE_RNG_SCHEME)
    write(io, hton(reinterpret(UInt64, Int64(seed))))
    write(io, hton(UInt64(path)))
    digest = SHA.sha256(take!(io))
    words = UInt32[]
    for offset in 1:4:length(digest)
        word =
            (UInt32(digest[offset]) << 24) |
            (UInt32(digest[offset + 1]) << 16) |
            (UInt32(digest[offset + 2]) << 8) |
            UInt32(digest[offset + 3])
        push!(words, word)
    end
    return MersenneTwister(words)
end

function draw_joint_predictive_paths(
        filtered::FilterResult,
        solution::GensysSolution,
        measurement::MeasurementSystem,
        horizon::Int,
        path_count::Int;
        seed::Int,
    )
    _validate_solution(solution)
    _validate_measurement(measurement)
    _validate_filter_result(filtered)
    typeof(horizon) === Int && 1 <= horizon <= MAXIMUM_PREDICTIVE_HORIZON ||
        fail("predictive horizon must be an exact Int in 1:$MAXIMUM_PREDICTIVE_HORIZON")
    typeof(path_count) === Int && path_count >= 1 ||
        fail("path_count must be an exact positive Int")
    typeof(seed) === Int || fail("predictive seed must be an exact Int")
    terminal_factor = _positive_semidefinite_factor(filtered.filtered_covariance)
    shock_factor = cholesky(Symmetric(measurement.shock_covariance); check = true).L
    paths = Array{Float64, 3}(undef, horizon, 3, path_count)
    for path in 1:path_count
        rng = _domain_separated_path_rng(seed, path)
        state = filtered.filtered_mean + terminal_factor * randn(rng, 8)
        for step in 1:horizon
            shock = shock_factor * randn(rng, 3)
            state = solution.constant + solution.transition * state + solution.impact * shock
            paths[step, :, path] = measurement.intercept + measurement.loading * state
        end
    end
    all(isfinite, paths) || fail("predictive paths contain nonfinite values")
    return paths
end

function simulate_synthetic_observations(
        parameters::SmallNKParameters,
        quarters::Int;
        seed::Int,
        burnin::Int = 200,
    )
    typeof(quarters) === Int && quarters >= 1 ||
        fail("quarters must be an exact positive Int")
    typeof(seed) === Int || fail("synthetic seed must be an exact Int")
    typeof(burnin) === Int && burnin >= 0 ||
        fail("burnin must be an exact nonnegative Int")
    quarters <= typemax(Int) - burnin ||
        fail("burnin plus quarters exceeds Int capacity")
    solution = solve_gensys(build_canonical_system(parameters))
    measurement = build_measurement_system(parameters)
    moments = stationary_state_moments(solution, measurement)
    rng = MersenneTwister(seed)
    shock_factor = cholesky(Symmetric(measurement.shock_covariance); check = true).L
    state = copy(moments.mean)
    observations = Matrix{Float64}(undef, quarters, 3)
    for index in 1:(burnin + quarters)
        shock = shock_factor * randn(rng, 3)
        state = solution.constant + solution.transition * state + solution.impact * shock
        if index > burnin
            observations[index - burnin, :] =
                measurement.intercept + measurement.loading * state
        end
    end
    all(isfinite, observations) || fail("synthetic observations contain nonfinite values")
    return observations
end

function _write_numeric_bits(io::IO, value)
    if value isa AbstractArray{Float64}
        write(io, string(size(value)), ':')
        for item in value
            write(io, hton(reinterpret(UInt64, item)))
        end
    elseif value isa Float64
        write(io, hton(reinterpret(UInt64, value)))
    elseif value isa Integer
        write(io, string(value), ';')
    elseif value isa AbstractString
        write(io, string(ncodeunits(value)), ':', value)
    else
        fail("unsupported mechanics-fingerprint value $(typeof(value))")
    end
    return io
end

function mechanics_fingerprint(
        parameters::SmallNKParameters,
        system::CanonicalSystem,
        solution::GensysSolution,
        measurement::MeasurementSystem,
    )
    validate_parameters(parameters)
    _validate_canonical_system(system)
    _validate_solution(solution)
    _validate_measurement(measurement)
    expected_system = build_canonical_system(parameters)
    for field in fieldnames(CanonicalSystem)
        getfield(system, field) == getfield(expected_system, field) ||
            fail("fingerprint canonical system is inconsistent with its parameters")
    end
    expected_measurement = build_measurement_system(parameters)
    for field in fieldnames(MeasurementSystem)
        getfield(measurement, field) == getfield(expected_measurement, field) ||
            fail("fingerprint measurement system is inconsistent with its parameters")
    end
    expected_solution = solve_gensys(expected_system)
    solution.eu == expected_solution.eu ||
        fail("fingerprint solution determinacy differs from the canonical solution")
    solution.stable_root_count == expected_solution.stable_root_count ||
        fail("fingerprint stable-root count differs from the canonical solution")
    solution.unstable_root_count == expected_solution.unstable_root_count ||
        fail("fingerprint unstable-root count differs from the canonical solution")
    for (field, tolerance) in (
            (:transition, 1.0e-12),
            (:constant, 1.0e-12),
            (:impact, 1.0e-12),
            (:generalized_roots, 1.0e-10),
        )
        isapprox(
            getfield(solution, field),
            getfield(expected_solution, field);
            atol = tolerance,
            rtol = 0.0,
        ) || fail("fingerprint solution.$field differs from the canonical solution")
    end
    isapprox(
        solution.equation_residual_max,
        expected_solution.equation_residual_max;
        atol = 1.0e-15,
        rtol = 0.0,
    ) || fail("fingerprint normalized equation residual is inconsistent")
    io = IOBuffer()
    for text in (
            MODEL_CLASS,
            TARGET_PANEL_ID,
            STATUS,
            REFERENCE_FIXTURE_SHA256,
            PREDICTIVE_RNG_SCHEME,
        )
        _write_numeric_bits(io, text)
    end
    for name in (STATE_NAMES..., SHOCK_NAMES..., OBSERVABLE_NAMES...)
        _write_numeric_bits(io, String(name))
    end
    for value in (
            UNIT_ROOT_BAND,
            SCHUR_ZERO_TOLERANCE,
            SVD_TOLERANCE,
            REALITY_TOLERANCE,
            EQUATION_RESIDUAL_TOLERANCE,
            COVARIANCE_TOLERANCE,
        )
        _write_numeric_bits(io, value)
    end
    _write_numeric_bits(io, MAXIMUM_PREDICTIVE_HORIZON)
    for (key, value) in REFERENCE_UPSTREAM_METADATA
        _write_numeric_bits(io, key)
        _write_numeric_bits(io, value)
    end
    for field in fieldnames(SmallNKParameters)
        _write_numeric_bits(io, getfield(parameters, field))
    end
    for value in (
            system.gamma0,
            system.gamma1,
            system.constant,
            system.shock_loading,
            system.expectational_loading,
            solution.transition,
            solution.constant,
            solution.impact,
            measurement.loading,
            measurement.intercept,
            measurement.shock_covariance,
            measurement.measurement_covariance,
        )
        _write_numeric_bits(io, value)
    end
    for value in solution.eu
        _write_numeric_bits(io, value)
    end
    _write_numeric_bits(io, solution.equation_residual_max)
    return bytes2hex(SHA.sha256(take!(io)))
end

function _decode_hex_float(value, location)
    typeof(value) === String || fail("$location must be a hexadecimal Float64 string")
    occursin(r"^0x[0-9a-f]{16}$", value) ||
        fail("$location must be exact lowercase IEEE-754 hexadecimal bits")
    bits = parse(UInt64, value[3:end]; base = 16)
    return reinterpret(Float64, bits)
end

function _fixture_matrix(table, location)
    table isa AbstractDict || fail("$location must be a table")
    Set(keys(table)) == Set(["rows", "cols", "values_ieee754_hex"]) ||
        fail("$location keys changed")
    rows = table["rows"]
    cols = table["cols"]
    typeof(rows) === Int64 || fail("$location.rows must be Int64")
    typeof(cols) === Int64 || fail("$location.cols must be Int64")
    values = table["values_ieee754_hex"]
    typeof(values) === Vector{String} || fail("$location values must be Vector{String}")
    length(values) == rows * cols || fail("$location value count changed")
    decoded = [
        _decode_hex_float(value, "$location.values[$index]") for
            (index, value) in enumerate(values)
    ]
    return reshape(decoded, rows, cols)
end

function _fixture_parameters(table)
    table isa AbstractDict || fail("parameters must be a table")
    names = fieldnames(SmallNKParameters)
    expected_keys = Set(String(name) for name in names)
    Set(keys(table)) == expected_keys || fail("fixture parameter keys changed")
    values = Float64[]
    for name in names
        key = String(name)
        push!(values, _decode_hex_float(table[key], "parameters.$key"))
    end
    parameters = SmallNKParameters(values...)
    reference = reference_parameters()
    for name in names
        reinterpret(UInt64, getfield(parameters, name)) ==
            reinterpret(UInt64, getfield(reference, name)) ||
            fail("fixture parameter $name does not match the FRBNY default bits")
    end
    return parameters
end

function _validate_fixture_upstream(table)
    table isa AbstractDict || fail("upstream must be a table")
    expected_keys = Set(first(pair) for pair in REFERENCE_UPSTREAM_METADATA)
    Set(keys(table)) == expected_keys || fail("fixture upstream keys changed")
    for (key, expected) in REFERENCE_UPSTREAM_METADATA
        get(table, key, nothing) == expected ||
            fail("fixture upstream.$key changed")
    end
    stake = _decode_hex_float(table["stake_ieee754_hex"], "upstream.stake_ieee754_hex")
    reinterpret(UInt64, stake) == reinterpret(UInt64, 1.0 + UNIT_ROOT_BAND) ||
        fail("fixture stake does not bind one plus the unit-root band")
    return stake
end

function load_reference_fixture(path::AbstractString = REFERENCE_FIXTURE_PATH)
    isfile(path) || fail("FRBNY gensys fixture is missing")
    islink(path) && fail("FRBNY gensys fixture must not be a symbolic link")
    bytes = read(path)
    digest = bytes2hex(SHA.sha256(bytes))
    REFERENCE_FIXTURE_SHA256 == repeat("0", 64) ||
        digest == REFERENCE_FIXTURE_SHA256 || fail("FRBNY fixture SHA-256 changed")
    document = try
        TOML.parse(String(bytes))
    catch error
        fail("FRBNY fixture TOML is invalid: $(sprint(showerror, error))")
    end
    Set(keys(document)) == Set(
        [
            "schema_version",
            "status",
            "upstream",
            "parameters",
            "g1",
            "constant",
            "impact",
            "eu",
        ]
    ) || fail("FRBNY fixture top-level keys changed")
    document["schema_version"] == "beforeit-us-frbny-gensys-reference.v1" ||
        fail("FRBNY fixture schema changed")
    document["status"] == "EXTERNAL_NUMERIC_REFERENCE_FIXTURE_ONLY" ||
        fail("FRBNY fixture status changed")
    stake = _validate_fixture_upstream(document["upstream"])
    parameters = _fixture_parameters(document["parameters"])
    eu_value = document["eu"]
    typeof(eu_value) === Vector{Int64} && eu_value == [1, 1] ||
        fail("FRBNY fixture eu changed")
    return (
        document,
        sha256 = digest,
        parameters,
        stake,
        transition = _fixture_matrix(document["g1"], "g1"),
        constant = vec(_fixture_matrix(document["constant"], "constant")),
        impact = _fixture_matrix(document["impact"], "impact"),
        eu = (eu_value[1], eu_value[2]),
    )
end

end
