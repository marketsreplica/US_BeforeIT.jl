# ---------------------------------------------------------------------------
# Shared estimation kernel for the Stage-2b DSGE scored columns.
#
# Everything here is deterministic and stdlib-only (LinearAlgebra, Statistics).
# No forecast error ever enters an objective: the posterior is
# (Kalman-filter log-likelihood on training data through the origin) +
# (frozen log-prior). The optimizer is a fixed-budget Nelder–Mead simplex with
# deterministic initialization, so a re-run reproduces the same mode
# bit-for-bit on the same platform.
# ---------------------------------------------------------------------------

# --- parameter transforms ---------------------------------------------------
# Estimation runs in an unconstrained space; each parameter carries a transform
# to its economic domain. `:log` maps R -> (0, Inf); `:logit` maps R -> (lo, hi);
# `:identity` leaves R.

struct ParameterTransform
    name::Symbol            # :log | :logit | :identity
    lower::Float64
    upper::Float64
end

to_domain(t::ParameterTransform, x::Float64) =
    t.name === :log ? exp(x) :
    t.name === :logit ? t.lower + (t.upper - t.lower) / (1.0 + exp(-x)) :
    x

function to_unconstrained(t::ParameterTransform, v::Float64)
    if t.name === :log
        v > 0.0 || throw(ArgumentError("log-transform requires positive value"))
        return log(v)
    elseif t.name === :logit
        t.lower < v < t.upper ||
            throw(ArgumentError("logit-transform requires value inside bounds"))
        u = (v - t.lower) / (t.upper - t.lower)
        return log(u / (1.0 - u))
    end
    return v
end

# --- log-priors -------------------------------------------------------------
# Distribution vocabulary follows the Dynare/Smets–Wouters conventions:
# NORMAL(mean, sd); GAMMA(mean, sd); BETA(mean, sd); INV_GAMMA1(mean, "df"-style
# scale) for shock standard deviations, using the Sims/Dynare inverse-gamma-1
# density p(sigma) ∝ sigma^-(nu+1) exp(-nu*s^2/(2 sigma^2)).

struct PriorSpec
    kind::Symbol            # :normal | :gamma | :beta | :invgamma1 | :flat
    a::Float64              # mean          (or s  for invgamma1)
    b::Float64              # sd            (or nu for invgamma1)
end

function log_prior_density(p::PriorSpec, v::Float64)
    if p.kind === :normal
        z = (v - p.a) / p.b
        return -0.5 * z^2 - log(p.b) - 0.5 * log(2.0 * pi)
    elseif p.kind === :gamma
        v > 0.0 || return -Inf
        # mean = k*theta, var = k*theta^2  =>  k = (mean/sd)^2, theta = sd^2/mean
        k = (p.a / p.b)^2
        theta = p.b^2 / p.a
        return (k - 1.0) * log(v) - v / theta - k * log(theta) - loggamma_local(k)
    elseif p.kind === :beta
        0.0 < v < 1.0 || return -Inf
        # mean = alpha/(alpha+beta); var = ab/((a+b)^2 (a+b+1))
        m, s2 = p.a, p.b^2
        nu = m * (1.0 - m) / s2 - 1.0
        nu > 0.0 || throw(ArgumentError("beta prior sd too large for mean"))
        alpha = m * nu
        beta = (1.0 - m) * nu
        return (alpha - 1.0) * log(v) + (beta - 1.0) * log(1.0 - v) -
            (loggamma_local(alpha) + loggamma_local(beta) - loggamma_local(alpha + beta))
    elseif p.kind === :invgamma1
        v > 0.0 || return -Inf
        s, nu = p.a, p.b
        return -(nu + 1.0) * log(v) - nu * s^2 / (2.0 * v^2)   # unnormalized
    end
    return 0.0                                                  # :flat
end

# Lanczos log-gamma; stdlib-only (SpecialFunctions is not a project dependency).
function loggamma_local(x::Float64)
    x > 0.0 || throw(ArgumentError("loggamma_local requires positive argument"))
    if x < 0.5
        return log(pi / sin(pi * x)) - loggamma_local(1.0 - x)
    end
    g = 7.0
    coefficients = (
        0.99999999999980993, 676.5203681218851, -1259.1392167224028,
        771.32342877765313, -176.61502916214059, 12.507343278686905,
        -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7,
    )
    z = x - 1.0
    a = coefficients[1]
    t = z + g + 0.5
    for i in 2:9
        a += coefficients[i] / (z + i - 1.0)
    end
    return 0.5 * log(2.0 * pi) + (z + 0.5) * log(t) - t + log(a)
end

# --- deterministic Nelder–Mead ---------------------------------------------
# Fixed-budget simplex maximizer over the unconstrained space. Deterministic:
# the initial simplex is built from fixed relative steps, and tie-breaking is
# by index. Returns (x_best, f_best, evaluations, converged).

function nelder_mead_maximize(
        objective::Function,
        x0::Vector{Float64};
        initial_step::Float64 = 0.08,
        max_evaluations::Int = 4000,
        tolerance::Float64 = 1.0e-7,
    )
    n = length(x0)
    f_count = 0
    evaluate = x -> begin
        f_count += 1
        value = objective(x)
        isfinite(value) ? value : -Inf
    end
    simplex = [copy(x0)]
    for i in 1:n
        vertex = copy(x0)
        vertex[i] += initial_step * max(1.0, abs(x0[i]))
        push!(simplex, vertex)
    end
    values = [evaluate(vertex) for vertex in simplex]
    alpha, gamma_e, rho_c, sigma_s = 1.0, 2.0, 0.5, 0.5
    while f_count < max_evaluations
        order = sortperm(values; rev = true)     # maximizing
        simplex = simplex[order]
        values = values[order]
        spread = values[1] - values[end]
        if spread < tolerance && isfinite(values[end])
            return simplex[1], values[1], f_count, true
        end
        centroid = zeros(n)
        for i in 1:n
            centroid .+= simplex[i]
        end
        centroid ./= n
        worst = simplex[end]
        reflected = centroid .+ alpha .* (centroid .- worst)
        f_reflected = evaluate(reflected)
        if f_reflected > values[1]
            expanded = centroid .+ gamma_e .* (reflected .- centroid)
            f_expanded = evaluate(expanded)
            if f_expanded > f_reflected
                simplex[end] = expanded
                values[end] = f_expanded
            else
                simplex[end] = reflected
                values[end] = f_reflected
            end
        elseif f_reflected > values[end - 1]
            simplex[end] = reflected
            values[end] = f_reflected
        else
            contracted = centroid .+ rho_c .* (worst .- centroid)
            f_contracted = evaluate(contracted)
            if f_contracted > values[end]
                simplex[end] = contracted
                values[end] = f_contracted
            else
                best = simplex[1]
                for i in 2:(n + 1)
                    simplex[i] = best .+ sigma_s .* (simplex[i] .- best)
                    values[i] = evaluate(simplex[i])
                end
            end
        end
    end
    order = sortperm(values; rev = true)
    return simplex[order[1]], values[order[1]], f_count, false
end

# --- size-generic gensys ----------------------------------------------------
# Verbatim transcription of the validated solver in
# `benchmarks/small_nk_dsge/USSmallNKDSGEMechanics.jl` (`solve_gensys`), with
# the 8-state shape validation removed so larger canonical systems (SW07) can
# be solved. Tolerances and every numeric guard are identical. The test suite
# oracle-compares this function against the sealed solver on the small-NK
# system: transition/constant/impact must agree to 1e-12.

const GENSYS_UNIT_ROOT_BAND = 1.0e-6
const GENSYS_SCHUR_ZERO_TOLERANCE = 1.0e-12
const GENSYS_SVD_TOLERANCE = 1.0e-6
const GENSYS_REALITY_TOLERANCE = 5.0e-10
const GENSYS_EQUATION_RESIDUAL_TOLERANCE = 1.0e-9

struct GenericGensysSolution
    transition::Matrix{Float64}
    constant::Vector{Float64}
    impact::Matrix{Float64}
    eu::NTuple{2, Int}
    stable_root_count::Int
    unstable_root_count::Int
    equation_residual_max::Float64
end

function _generic_svd_subspaces(matrix::Matrix{ComplexF64}, tolerance::Float64)
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

function generic_gensys(
        gamma0::Matrix{Float64},
        gamma1::Matrix{Float64},
        constant_vector::Vector{Float64},
        shock_loading::Matrix{Float64},
        expectational_loading::Matrix{Float64};
        unit_band::Float64 = GENSYS_UNIT_ROOT_BAND,
        zero_tolerance::Float64 = GENSYS_SCHUR_ZERO_TOLERANCE,
        svd_tolerance::Float64 = GENSYS_SVD_TOLERANCE,
        reality_tolerance::Float64 = GENSYS_REALITY_TOLERANCE,
        equation_residual_tolerance::Float64 = GENSYS_EQUATION_RESIDUAL_TOLERANCE,
        require_determinate::Bool = true,
    )
    values = (gamma0, gamma1, constant_vector, shock_loading, expectational_loading)
    all(value -> all(isfinite, value), values) ||
        error("canonical system must be finite")
    scale = maximum(maximum(abs, value) for value in values)
    isfinite(scale) && scale > 0.0 ||
        error("canonical system has no finite positive normalization scale")
    g0_n = gamma0 ./ scale
    g1_n = gamma1 ./ scale
    c_n = constant_vector ./ scale
    psi_n = shock_loading ./ scale
    pi_n = expectational_loading ./ scale

    decomposition = schur(complex(g0_n), complex(g1_n))
    schur_scale = max(maximum(abs, decomposition.S), maximum(abs, decomposition.T))
    zero_cutoff = zero_tolerance * schur_scale
    state_count = size(g0_n, 1)
    stable = Bool[]
    for index in 1:state_count
        s = ComplexF64(decomposition.S[index, index])
        t = ComplexF64(decomposition.T[index, index])
        if abs(s) <= zero_cutoff && abs(t) <= zero_cutoff
            error("coincident generalized-Schur zeros at index $index")
        end
        root = abs(s) <= zero_cutoff ? ComplexF64(Inf) : t / s
        modulus = abs(root)
        if 1.0 - unit_band <= modulus <= 1.0 + unit_band
            error("generalized root $index lies in the unit-root exclusion band")
        end
        push!(stable, modulus < 1.0 - unit_band)
    end
    ordered = ordschur(decomposition, stable)
    a = ordered.S
    b = ordered.T
    q = ordered.Q
    z = ordered.Z
    stable_count = count(stable)
    unstable_count = state_count - stable_count
    shock_count = size(psi_n, 2)
    q_stable = q[:, 1:stable_count]
    q_unstable = q[:, (stable_count + 1):state_count]

    eta_unstable = Matrix{ComplexF64}(q_unstable' * pi_n)
    unstable_svd = _generic_svd_subspaces(eta_unstable, svd_tolerance)
    existence = unstable_svd.rank >= unstable_count
    eta_stable = Matrix{ComplexF64}(q_stable' * pi_n)
    stable_svd = _generic_svd_subspaces(eta_stable, svd_tolerance)
    if stable_svd.rank == 0
        uniqueness = true
    else
        projection = unstable_svd.v * unstable_svd.v'
        loose = stable_svd.v - projection * stable_svd.v
        loose_singular_values = svdvals(loose)
        uniqueness =
            all(value -> value <= svd_tolerance * state_count, loose_singular_values)
    end
    eu = (existence ? 1 : 0, uniqueness ? 1 : 0)
    require_determinate && eu != (1, 1) &&
        error("gensys existence/uniqueness failed with eu=$eu")

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
    g0_solved = vcat(transformation * a, bottom)
    g1_rhs = vcat(transformation * b, zeros(ComplexF64, unstable_count, state_count))
    q_constant = q' * c_n
    q_shocks = q' * psi_n
    if unstable_count == 0
        unstable_constant = ComplexF64[]
    else
        unstable_range = (stable_count + 1):state_count
        unstable_constant =
            (a[unstable_range, unstable_range] - b[unstable_range, unstable_range]) \
            (q_unstable' * c_n)
    end
    constant_rhs = vcat(transformation * q_constant, unstable_constant)
    impact_rhs = vcat(
        transformation * q_shocks,
        zeros(ComplexF64, unstable_count, shock_count),
    )
    transition_complex = z * ((g0_solved \ g1_rhs) * z')
    constant_complex = z * (g0_solved \ constant_rhs)
    impact_complex = z * (g0_solved \ impact_rhs)
    maximum_imaginary = max(
        isempty(transition_complex) ? 0.0 : maximum(abs, imag.(transition_complex)),
        isempty(constant_complex) ? 0.0 : maximum(abs, imag.(constant_complex)),
        isempty(impact_complex) ? 0.0 : maximum(abs, imag.(impact_complex)),
    )
    maximum_imaginary <= reality_tolerance ||
        error("gensys solution has a material imaginary component")
    transition = real(transition_complex)
    constant_solved = real(constant_complex)
    impact = real(impact_complex)
    all(isfinite, transition) && all(isfinite, constant_solved) &&
        all(isfinite, impact) || error("gensys solution is nonfinite")
    residual_max = 0.0
    for residual in (
            g0_n * transition - g1_n,
            reshape(g0_n * constant_solved - c_n, :, 1),
            g0_n * impact - psi_n,
        )
        expectational_coefficients = pi_n \ residual
        closure = residual - pi_n * expectational_coefficients
        residual_max = max(residual_max, maximum(abs, closure))
    end
    if eu == (1, 1)
        residual_max <= equation_residual_tolerance ||
            error("gensys solution does not close the canonical equations")
    end
    spectral_radius = maximum(abs, eigvals(transition))
    spectral_radius < 1.0 - unit_band ||
        error("reduced transition is not strictly stationary")
    return GenericGensysSolution(
        transition, constant_solved, impact, eu,
        stable_count, unstable_count, residual_max,
    )
end

# --- generic Kalman filter --------------------------------------------------
# State space:  s_t = T s_{t-1} + c + R eta_t,  eta ~ N(0, Q)
#               y_t = Z s_t + d,                no measurement error.
# Missing observations are not supported (panels here are complete-case).
# Initialization is the unconditional (Lyapunov) moment pair; the transition is
# required to be stable. Returns loglik and the terminal filtered state.

function lyapunov_covariance(
        T_mat::Matrix{Float64}, RQR::Matrix{Float64};
        iterations::Int = 60, tolerance::Float64 = 1.0e-13
    )
    # doubling algorithm: quadratic convergence for stable transitions
    A = copy(T_mat)
    P = copy(RQR)
    for _ in 1:iterations
        P_next = P + A * P * A'
        A_next = A * A
        delta = maximum(abs.(P_next .- P))
        P = P_next
        A = A_next
        delta < tolerance && break
    end
    return Symmetric((P + P') / 2.0)
end

function kalman_loglikelihood(
        observations::Matrix{Float64},   # T x n_obs
        T_mat::Matrix{Float64},
        c_vec::Vector{Float64},
        R_mat::Matrix{Float64},
        Q_mat::Matrix{Float64},
        Z_mat::Matrix{Float64},
        d_vec::Vector{Float64},
    )
    n_state = size(T_mat, 1)
    n_obs = size(Z_mat, 1)
    size(observations, 2) == n_obs ||
        throw(ArgumentError("observation width must match measurement rows"))
    RQR = R_mat * Q_mat * R_mat'
    steady = (LinearAlgebra.I - T_mat) \ c_vec
    s = steady
    P = Matrix(lyapunov_covariance(T_mat, RQR))
    loglik = 0.0
    periods = size(observations, 1)
    # Riccati recursion converges for a stationary system; once the predicted
    # covariance is numerically constant the gain is frozen (steady-state
    # Kalman filter), which removes the per-step matrix-matrix work.
    steady_state = false
    K = Matrix{Float64}(undef, n_state, n_obs)
    F_chol = cholesky(Symmetric(Matrix{Float64}(LinearAlgebra.I, n_obs, n_obs)))
    log_det_half = 0.0
    P_prev = fill(Inf, n_state, n_state)
    for t in 1:periods
        s_pred = T_mat * s + c_vec
        if !steady_state
            P_pred = T_mat * P * T_mat' + RQR
            F = Symmetric(Z_mat * P_pred * Z_mat')
            F_fact = cholesky(F + 1.0e-12 * LinearAlgebra.I; check = false)
            issuccess(F_fact) || return (-Inf, s, P)
            F_chol = F_fact
            log_det_half = sum(log.(diag(F_chol.L)))
            K = (P_pred * Z_mat') / F_chol
            P = P_pred - K * Z_mat * P_pred
            P = (P + P') / 2.0
            if maximum(abs.(P_pred .- P_prev)) < 1.0e-11
                steady_state = true
            end
            P_prev = P_pred
        end
        innovation = vec(observations[t, :]) - (Z_mat * s_pred + d_vec)
        half = F_chol.L \ innovation
        loglik += -0.5 * (n_obs * log(2.0 * pi) + 2.0 * log_det_half + dot(half, half))
        s = s_pred + K * innovation
    end
    return (loglik, s, P)
end
