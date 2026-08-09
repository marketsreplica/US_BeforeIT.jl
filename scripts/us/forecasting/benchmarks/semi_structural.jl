"""
    SemiStructuralSpec(; kwargs...)

Fixed-parameter quarterly linear-Gaussian semi-structural model for, in this
exact order, real GDP growth, PCE inflation, unemployment, and the effective
federal funds rate. The eight states are potential growth, the output gap,
natural unemployment, the neutral real rate, the inflation anchor, inflation,
the policy rate, and the lagged output gap.

The constructor fixes every structural coefficient and covariance before an
origin is seen. At an origin, only the latent-state distribution is updated by
the exact Kalman filter; no parameter is fitted or selected. Predictive draws
sample the filtered terminal state and future process and measurement shocks.
They are therefore fixed-parameter, conditional-on-hyperparameters density
draws, not draws from a full posterior over parameters and not a DSGE density.
"""
struct SemiStructuralSpec <: AbstractBenchmarkSpec
    potential_growth_mean::Float64
    potential_growth_persistence::Float64
    output_gap_persistence::Float64
    is_slope::Float64
    natural_unemployment_mean::Float64
    natural_unemployment_persistence::Float64
    neutral_rate_mean::Float64
    neutral_rate_persistence::Float64
    inflation_anchor_mean::Float64
    inflation_anchor_persistence::Float64
    inflation_persistence::Float64
    phillips_slope::Float64
    okun_slope::Float64
    policy_smoothing::Float64
    taylor_inflation::Float64
    taylor_output::Float64
    state_innovation_covariance::Matrix{Float64}
    measurement_covariance::Matrix{Float64}
    initial_covariance::Matrix{Float64}
    function SemiStructuralSpec(;
            potential_growth_mean = 2.0,
            potential_growth_persistence = 0.85,
            output_gap_persistence = 0.75,
            is_slope = 0.12,
            natural_unemployment_mean = 4.5,
            natural_unemployment_persistence = 0.95,
            neutral_rate_mean = 1.0,
            neutral_rate_persistence = 0.9,
            inflation_anchor_mean = 2.0,
            inflation_anchor_persistence = 0.95,
            inflation_persistence = 0.65,
            phillips_slope = 0.08,
            okun_slope = 0.45,
            policy_smoothing = 0.75,
            taylor_inflation = 1.5,
            taylor_output = 0.35,
            state_innovation_covariance = Diagonal(
                [0.08, 0.35, 0.05, 0.08, 0.05, 0.2, 0.15] .^ 2
            ),
            measurement_covariance = Diagonal(
                [0.12, 0.08, 0.05, 0.04] .^ 2
            ),
            initial_covariance = Diagonal(
                [0.5, 1.0, 0.5, 0.5, 0.5, 0.5, 1.0, 1.0] .^ 2
            )
        )
        fixed_potential_growth_mean =
            _semi_finite(potential_growth_mean, "potential_growth_mean")
        fixed_potential_growth_persistence = _semi_persistence(
            potential_growth_persistence,
            "potential_growth_persistence"
        )
        fixed_output_gap_persistence =
            _semi_finite(output_gap_persistence, "output_gap_persistence")
        fixed_is_slope = _semi_positive(is_slope, "is_slope")
        fixed_natural_unemployment_mean = _semi_finite(
            natural_unemployment_mean,
            "natural_unemployment_mean"
        )
        fixed_natural_unemployment_persistence = _semi_persistence(
            natural_unemployment_persistence,
            "natural_unemployment_persistence"
        )
        fixed_neutral_rate_mean =
            _semi_finite(neutral_rate_mean, "neutral_rate_mean")
        fixed_neutral_rate_persistence =
            _semi_persistence(neutral_rate_persistence, "neutral_rate_persistence")
        fixed_inflation_anchor_mean =
            _semi_finite(inflation_anchor_mean, "inflation_anchor_mean")
        fixed_inflation_anchor_persistence = _semi_persistence(
            inflation_anchor_persistence,
            "inflation_anchor_persistence"
        )
        fixed_inflation_persistence =
            _semi_persistence(inflation_persistence, "inflation_persistence")
        fixed_phillips_slope =
            _semi_positive(phillips_slope, "phillips_slope")
        fixed_okun_slope = _semi_positive(okun_slope, "okun_slope")
        fixed_policy_smoothing =
            _semi_unit_interval(policy_smoothing, "policy_smoothing")
        fixed_taylor_inflation =
            _semi_positive(taylor_inflation, "taylor_inflation")
        fixed_taylor_output =
            _semi_nonnegative(taylor_output, "taylor_output")
        fixed_state_covariance = _semi_covariance(
            state_innovation_covariance,
            7,
            "state_innovation_covariance"
        )
        fixed_measurement_covariance = _semi_covariance(
            measurement_covariance,
            4,
            "measurement_covariance"
        )
        fixed_initial_covariance =
            _semi_covariance(initial_covariance, 8, "initial_covariance")

        spec = new(
            fixed_potential_growth_mean,
            fixed_potential_growth_persistence,
            fixed_output_gap_persistence,
            fixed_is_slope,
            fixed_natural_unemployment_mean,
            fixed_natural_unemployment_persistence,
            fixed_neutral_rate_mean,
            fixed_neutral_rate_persistence,
            fixed_inflation_anchor_mean,
            fixed_inflation_anchor_persistence,
            fixed_inflation_persistence,
            fixed_phillips_slope,
            fixed_okun_slope,
            fixed_policy_smoothing,
            fixed_taylor_inflation,
            fixed_taylor_output,
            fixed_state_covariance,
            fixed_measurement_covariance,
            fixed_initial_covariance
        )
        spectral_radius =
            maximum(abs, eigvals(_semi_structural_system(spec).transition))
        spectral_radius < 1.0 ||
            throw(
            ArgumentError(
                "semi-structural transition must be stable; spectral radius is $spectral_radius"
            )
        )
        return spec
    end
end

const SEMI_STRUCTURAL_TARGET_NAMES = (
    "real_gdp_growth",
    "pce_inflation",
    "unemployment_rate",
    "effective_federal_funds_rate",
)

const SEMI_STRUCTURAL_TARGET_UNITS = (
    "annualized_quarter_over_quarter_percent",
    "annualized_quarter_over_quarter_percent",
    "quarterly_average_percent",
    "quarterly_average_percent",
)

const SEMI_STRUCTURAL_TARGET_CONTRACT_VERSION =
    "quarterly_core4_contract_v1"

const SEMI_STRUCTURAL_GAP_ANNUALIZATION = 4.0

const SEMI_STRUCTURAL_STATE_NAMES = (
    "potential_growth",
    "output_gap",
    "natural_unemployment",
    "neutral_real_rate",
    "inflation_anchor",
    "inflation",
    "policy_rate",
    "lagged_output_gap",
)

function model_id(spec::SemiStructuralSpec)
    digest = bytes2hex(SHA.sha256(_semi_parameter_payload(spec)))
    return "semi_structural_lgssm_v1_$(SEMI_STRUCTURAL_TARGET_CONTRACT_VERSION)_$digest"
end

function model_card(spec::SemiStructuralSpec)
    system = _semi_structural_system(spec)
    card = _card(
        model_id(spec),
        "Fixed-parameter linear-Gaussian quarterly semi-structural state-space model",
        "Exact Kalman-filter terminal state mean propagated through the fixed transition and observation equations.",
        "Posterior-state predictive paths conditional on constructor-fixed hyperparameters, with filtered-state, process-shock, and measurement-shock uncertainty but no parameter uncertainty.",
        "Unconditional with respect to future exogenous paths: x_train/x_future are rejected rather than used or ignored."
    )
    card["model_class"] = "semi_structural_not_dsge"
    card["frequency"] = "quarterly"
    card["target_contract_version"] =
        SEMI_STRUCTURAL_TARGET_CONTRACT_VERSION
    card["target_names"] = collect(SEMI_STRUCTURAL_TARGET_NAMES)
    card["target_units"] = collect(SEMI_STRUCTURAL_TARGET_UNITS)
    card["state_names"] = collect(SEMI_STRUCTURAL_STATE_NAMES)
    card["structural_links"] = Dict{String, Any}(
        "is" =>
            "gap[t] = rho_gap*gap[t-1] - alpha*((policy[t-1]-inflation[t-1])-neutral_rate[t-1]) + shock_gap[t]",
        "phillips" =>
            "inflation[t] = rho_pi*inflation[t-1] + (1-rho_pi)*anchor[t-1] + kappa*gap[t-1] + shock_pi[t]",
        "okun" =>
            "unemployment[t] = natural_unemployment[t] - beta*gap[t] + measurement_error[t]",
        "taylor" =>
            "policy[t] = rho_i*policy[t-1] + (1-rho_i)*(neutral_rate[t-1]+anchor[t-1]+phi_pi*(inflation[t-1]-anchor[t-1])+phi_y*gap[t-1]) + shock_i[t]",
        "gdp_growth" =>
            "gdp_growth[t] = potential_growth[t] + 4*(gap[t]-gap[t-1]) + measurement_error[t]"
    )
    card["hyperparameters"] = _semi_hyperparameters(spec)
    card["hyperparameter_selection"] =
        "None. Every coefficient and covariance is constructor-fixed and bound by the model-id digest."
    card["origin_parameter_fitting"] =
        "None. The origin update is latent-state filtering, not parameter estimation."
    card["model_id_encoding"] =
        "SHA-256 of a versioned canonical payload. Every forecast-relevant Float64 uses its exact 16-digit IEEE-754 hexadecimal token; symmetric covariances encode their full upper triangles."
    card["transition_spectral_radius"] =
        maximum(abs, eigvals(system.transition))
    card["covariance_contract"] =
        "State-innovation, measurement, and initial covariances must be finite, symmetric, and positive semidefinite."
    card["density_scope"] =
        "Fixed-parameter conditional-on-hyperparameters posterior-state predictive density."
    card["filtered_state_uncertainty"] = "Included."
    card["process_shock_uncertainty"] = "Included."
    card["measurement_shock_uncertainty"] = "Included."
    card["parameter_uncertainty"] = "Excluded."
    card["full_posterior_parameter_density"] = false
    card["satisfies_full_posterior_parameter_density_requirement"] = false
    card["satisfies_dsge_requirement"] = false
    card["known_limitations"] =
        "This v1 kernel is not a DSGE model and does not satisfy a full posterior-parameter density or DSGE requirement. It has fixed coefficients, fixed covariances, no parameter learning, no regimes, no ELB, no stochastic volatility, and no future exogenous conditioning."
    return card
end

function _forecast(
        spec::SemiStructuralSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    _validate_semi_structural_sample(sample)
    system = _semi_structural_system(spec)
    filter_result = _semi_kalman_filter(sample.y_train, system)
    point = _semi_structural_point_path(
        filter_result.filtered_mean,
        system,
        horizon(sample)
    )
    draws = _semi_structural_predictive_draws(
        filter_result.filtered_mean,
        filter_result.filtered_covariance,
        system,
        horizon(sample),
        n_draws,
        seed
    )
    diagnostics = Dict{String, Any}(
        "point_rule" => "conditional_mean_from_exact_kalman_filter",
        "density_scope" =>
            "fixed_parameter_conditional_on_hyperparameters_posterior_state_predictive",
        "kalman_filter" => "exact_linear_gaussian_no_jitter",
        "kalman_log_likelihood_conditional_on_fixed_parameters" =>
            filter_result.log_likelihood,
        "filtered_state_mean" => filter_result.filtered_mean,
        "filtered_state_covariance" => filter_result.filtered_covariance,
        "state_names" => collect(SEMI_STRUCTURAL_STATE_NAMES),
        "target_names" => collect(SEMI_STRUCTURAL_TARGET_NAMES),
        "target_units" => collect(SEMI_STRUCTURAL_TARGET_UNITS),
        "transition_spectral_radius" =>
            maximum(abs, eigvals(system.transition)),
        "hyperparameter_selection" => "none",
        "origin_parameter_fitting" => false,
        "filtered_state_uncertainty_in_draws" => true,
        "process_shock_uncertainty_in_draws" => true,
        "measurement_shock_uncertainty_in_draws" => true,
        "parameter_uncertainty_in_draws" => false,
        "future_exogenous_used" => false,
        "future_exogenous_policy" => "x_train_and_x_future_rejected",
        "full_posterior_parameter_density" => false,
        "dsge_model" => false
    )
    return point, draws, diagnostics
end

function _validate_semi_structural_sample(sample::OriginData)
    sample.x_train === nothing && sample.x_future === nothing ||
        throw(
        ArgumentError(
            "SemiStructuralSpec is an unconditional benchmark and rejects x_train/x_future"
        )
    )
    size(sample.y_train, 2) == length(SEMI_STRUCTURAL_TARGET_NAMES) ||
        throw(
        DimensionMismatch(
            "SemiStructuralSpec requires exactly $(length(SEMI_STRUCTURAL_TARGET_NAMES)) target columns"
        )
    )
    Tuple(sample.target_names) == SEMI_STRUCTURAL_TARGET_NAMES ||
        throw(
        ArgumentError(
            "SemiStructuralSpec target_names must equal $(collect(SEMI_STRUCTURAL_TARGET_NAMES)) in that order and with the units declared by quarterly_core4_contract_v1"
        )
    )
    return nothing
end

function _semi_structural_system(spec::SemiStructuralSpec)
    transition = zeros(8, 8)
    transition[1, 1] = spec.potential_growth_persistence
    transition[2, 2] = spec.output_gap_persistence
    transition[2, 4] = spec.is_slope
    transition[2, 6] = spec.is_slope
    transition[2, 7] = -spec.is_slope
    transition[3, 3] = spec.natural_unemployment_persistence
    transition[4, 4] = spec.neutral_rate_persistence
    transition[5, 5] = spec.inflation_anchor_persistence
    transition[6, 2] = spec.phillips_slope
    transition[6, 5] = 1.0 - spec.inflation_persistence
    transition[6, 6] = spec.inflation_persistence
    policy_adjustment = 1.0 - spec.policy_smoothing
    transition[7, 2] = policy_adjustment * spec.taylor_output
    transition[7, 4] = policy_adjustment
    transition[7, 5] =
        policy_adjustment * (1.0 - spec.taylor_inflation)
    transition[7, 6] =
        policy_adjustment * spec.taylor_inflation
    transition[7, 7] = spec.policy_smoothing
    transition[8, 2] = 1.0

    transition_constant = zeros(8)
    transition_constant[1] =
        (1.0 - spec.potential_growth_persistence) *
        spec.potential_growth_mean
    transition_constant[3] =
        (1.0 - spec.natural_unemployment_persistence) *
        spec.natural_unemployment_mean
    transition_constant[4] =
        (1.0 - spec.neutral_rate_persistence) *
        spec.neutral_rate_mean
    transition_constant[5] =
        (1.0 - spec.inflation_anchor_persistence) *
        spec.inflation_anchor_mean

    process_covariance = zeros(8, 8)
    process_covariance[1:7, 1:7] .=
        spec.state_innovation_covariance

    observation = zeros(4, 8)
    observation[1, 1] = 1.0
    observation[1, 2] = SEMI_STRUCTURAL_GAP_ANNUALIZATION
    observation[1, 8] = -SEMI_STRUCTURAL_GAP_ANNUALIZATION
    observation[2, 6] = 1.0
    observation[3, 2] = -spec.okun_slope
    observation[3, 3] = 1.0
    observation[4, 7] = 1.0

    initial_mean = [
        spec.potential_growth_mean,
        0.0,
        spec.natural_unemployment_mean,
        spec.neutral_rate_mean,
        spec.inflation_anchor_mean,
        spec.inflation_anchor_mean,
        spec.neutral_rate_mean + spec.inflation_anchor_mean,
        0.0,
    ]
    return (
        transition_constant = transition_constant,
        transition = transition,
        process_covariance = process_covariance,
        observation_constant = zeros(4),
        observation = observation,
        measurement_covariance = spec.measurement_covariance,
        initial_mean = initial_mean,
        initial_covariance = spec.initial_covariance,
    )
end

function _semi_kalman_filter(observations::AbstractMatrix, system)
    data = Matrix{Float64}(observations)
    all(isfinite, data) ||
        throw(ArgumentError("Kalman-filter observations must be finite"))
    transition_constant = Vector{Float64}(system.transition_constant)
    transition = Matrix{Float64}(system.transition)
    process_covariance = Matrix{Float64}(system.process_covariance)
    observation_constant = Vector{Float64}(system.observation_constant)
    observation = Matrix{Float64}(system.observation)
    measurement_covariance =
        Matrix{Float64}(system.measurement_covariance)
    previous_mean = Vector{Float64}(system.initial_mean)
    previous_covariance = Matrix{Float64}(system.initial_covariance)
    states = length(previous_mean)
    observed_variables = size(data, 2)
    _validate_semi_system_dimensions(
        states,
        observed_variables,
        transition_constant,
        transition,
        process_covariance,
        observation_constant,
        observation,
        measurement_covariance,
        previous_covariance
    )

    periods = size(data, 1)
    predicted_means = Matrix{Float64}(undef, periods, states)
    filtered_means = Matrix{Float64}(undef, periods, states)
    predicted_covariances =
        Array{Float64, 3}(undef, states, states, periods)
    filtered_covariances =
        Array{Float64, 3}(undef, states, states, periods)
    innovations = Matrix{Float64}(undef, periods, observed_variables)
    innovation_covariances =
        Array{Float64, 3}(undef, observed_variables, observed_variables, periods)
    identity_states = Matrix{Float64}(I, states, states)
    log_likelihood = 0.0

    for period in 1:periods
        predicted_mean =
            transition_constant + transition * previous_mean
        predicted_covariance = _semi_symmetric(
            transition * previous_covariance * transition' +
                process_covariance
        )
        innovation =
            data[period, :] -
            observation_constant -
            observation * predicted_mean
        innovation_covariance = _semi_symmetric(
            observation * predicted_covariance * observation' +
                measurement_covariance
        )
        innovation_factor = cholesky(Symmetric(innovation_covariance))
        gain =
            (innovation_factor \ (observation * predicted_covariance'))'
        filtered_mean = predicted_mean + gain * innovation
        residual_operator = identity_states - gain * observation
        filtered_covariance = _semi_symmetric(
            residual_operator *
                predicted_covariance *
                residual_operator' +
                gain * measurement_covariance * gain'
        )
        log_likelihood -= 0.5 * (
            observed_variables * log(2.0 * pi) +
                2.0 * sum(log, diag(innovation_factor.L)) +
                dot(innovation, innovation_factor \ innovation)
        )

        predicted_means[period, :] .= predicted_mean
        filtered_means[period, :] .= filtered_mean
        predicted_covariances[:, :, period] .= predicted_covariance
        filtered_covariances[:, :, period] .= filtered_covariance
        innovations[period, :] .= innovation
        innovation_covariances[:, :, period] .= innovation_covariance
        previous_mean = filtered_mean
        previous_covariance = filtered_covariance
    end

    return (
        filtered_mean = previous_mean,
        filtered_covariance = previous_covariance,
        predicted_means = predicted_means,
        filtered_means = filtered_means,
        predicted_covariances = predicted_covariances,
        filtered_covariances = filtered_covariances,
        innovations = innovations,
        innovation_covariances = innovation_covariances,
        log_likelihood = log_likelihood,
    )
end

function _semi_structural_point_path(filtered_mean, system, forecast_horizon)
    state = Vector{Float64}(filtered_mean)
    point = Matrix{Float64}(
        undef,
        forecast_horizon,
        length(system.observation_constant)
    )
    for step in 1:forecast_horizon
        state = system.transition_constant + system.transition * state
        point[step, :] .=
            system.observation_constant + system.observation * state
    end
    return point
end

function _semi_structural_predictive_draws(
        filtered_mean,
        filtered_covariance,
        system,
        forecast_horizon,
        n_draws,
        seed
    )
    observed_variables = length(system.observation_constant)
    draws =
        Array{Float64, 3}(undef, forecast_horizon, observed_variables, n_draws)
    n_draws == 0 && return draws
    rng = MersenneTwister(seed)
    filtered_factor =
        _semi_psd_factor(filtered_covariance, "filtered state covariance")
    process_factor =
        _semi_psd_factor(system.process_covariance, "process covariance")
    measurement_factor = _semi_psd_factor(
        system.measurement_covariance,
        "measurement covariance"
    )
    states = length(filtered_mean)

    for draw in 1:n_draws
        state =
            filtered_mean + filtered_factor * randn(rng, states)
        for step in 1:forecast_horizon
            state =
                system.transition_constant +
                system.transition * state +
                process_factor * randn(rng, states)
            draws[step, :, draw] .=
                system.observation_constant +
                system.observation * state +
                measurement_factor * randn(rng, observed_variables)
        end
    end
    return draws
end

function _validate_semi_system_dimensions(
        states,
        observed_variables,
        transition_constant,
        transition,
        process_covariance,
        observation_constant,
        observation,
        measurement_covariance,
        initial_covariance
    )
    length(transition_constant) == states ||
        throw(DimensionMismatch("transition constant has incompatible length"))
    size(transition) == (states, states) ||
        throw(DimensionMismatch("transition matrix has incompatible size"))
    size(process_covariance) == (states, states) ||
        throw(DimensionMismatch("process covariance has incompatible size"))
    length(observation_constant) == observed_variables ||
        throw(DimensionMismatch("observation constant has incompatible length"))
    size(observation) == (observed_variables, states) ||
        throw(DimensionMismatch("observation matrix has incompatible size"))
    size(measurement_covariance) ==
        (observed_variables, observed_variables) ||
        throw(DimensionMismatch("measurement covariance has incompatible size"))
    size(initial_covariance) == (states, states) ||
        throw(DimensionMismatch("initial covariance has incompatible size"))
    return nothing
end

function _semi_hyperparameters(spec::SemiStructuralSpec)
    return Dict{String, Any}(
        "potential_growth_mean" => spec.potential_growth_mean,
        "potential_growth_persistence" =>
            spec.potential_growth_persistence,
        "output_gap_persistence" => spec.output_gap_persistence,
        "is_slope" => spec.is_slope,
        "natural_unemployment_mean" => spec.natural_unemployment_mean,
        "natural_unemployment_persistence" =>
            spec.natural_unemployment_persistence,
        "neutral_rate_mean" => spec.neutral_rate_mean,
        "neutral_rate_persistence" => spec.neutral_rate_persistence,
        "inflation_anchor_mean" => spec.inflation_anchor_mean,
        "inflation_anchor_persistence" =>
            spec.inflation_anchor_persistence,
        "inflation_persistence" => spec.inflation_persistence,
        "phillips_slope" => spec.phillips_slope,
        "okun_slope" => spec.okun_slope,
        "policy_smoothing" => spec.policy_smoothing,
        "taylor_inflation" => spec.taylor_inflation,
        "taylor_output" => spec.taylor_output,
        "state_innovation_covariance" =>
            copy(spec.state_innovation_covariance),
        "measurement_covariance" => copy(spec.measurement_covariance),
        "initial_covariance" => copy(spec.initial_covariance)
    )
end

function _semi_covariance(value, dimension, name)
    matrix = try
        Matrix{Float64}(value)
    catch
        throw(ArgumentError("$name must be a numeric matrix"))
    end
    size(matrix) == (dimension, dimension) ||
        throw(
        DimensionMismatch(
            "$name has size $(size(matrix)); expected ($dimension, $dimension)"
        )
    )
    all(isfinite, matrix) ||
        throw(ArgumentError("$name must contain only finite values"))
    isapprox(matrix, matrix'; rtol = 1.0e-12, atol = 1.0e-14) ||
        throw(ArgumentError("$name must be symmetric"))
    symmetric_matrix = _semi_symmetric(matrix)
    decomposition = eigen(Symmetric(symmetric_matrix))
    tolerance =
        100 * dimension * eps(Float64) *
        max(maximum(abs, decomposition.values), 1.0)
    minimum(decomposition.values) >= -tolerance ||
        throw(ArgumentError("$name must be positive semidefinite"))
    if minimum(decomposition.values) < 0.0
        symmetric_matrix = _semi_symmetric(
            decomposition.vectors *
                Diagonal(max.(decomposition.values, 0.0)) *
                decomposition.vectors'
        )
    end
    symmetric_matrix .= ifelse.(iszero.(symmetric_matrix), 0.0, symmetric_matrix)
    return symmetric_matrix
end

function _semi_psd_factor(matrix, name)
    symmetric_matrix = _semi_symmetric(Matrix{Float64}(matrix))
    decomposition = eigen(Symmetric(symmetric_matrix))
    dimension = size(symmetric_matrix, 1)
    tolerance =
        1_000 * dimension * eps(Float64) *
        max(maximum(abs, decomposition.values), 1.0)
    minimum(decomposition.values) >= -tolerance ||
        throw(ArgumentError("$name must be positive semidefinite"))
    return decomposition.vectors *
        Diagonal(sqrt.(max.(decomposition.values, 0.0)))
end

_semi_symmetric(matrix) = Matrix(Symmetric((matrix + matrix') / 2))

function _semi_persistence(value, name)
    number = _semi_finite(value, name)
    abs(number) < 1.0 ||
        throw(ArgumentError("$name must have absolute value below one"))
    return number
end

function _semi_unit_interval(value, name)
    number = _semi_finite(value, name)
    0.0 <= number < 1.0 ||
        throw(ArgumentError("$name must be in [0, 1)"))
    return number
end

function _semi_positive(value, name)
    number = _semi_finite(value, name)
    number > 0.0 || throw(ArgumentError("$name must be positive"))
    return number
end

function _semi_nonnegative(value, name)
    number = _semi_finite(value, name)
    number >= 0.0 || throw(ArgumentError("$name must be nonnegative"))
    return number
end

function _semi_finite(value, name)
    value isa Real && !(value isa Bool) ||
        throw(ArgumentError("$name must be a real number"))
    number = Float64(value)
    isfinite(number) || throw(ArgumentError("$name must be finite"))
    return iszero(number) ? 0.0 : number
end

function _semi_float_token(value::Float64)
    return lowercase(
        string(reinterpret(UInt64, value); base = 16, pad = 16)
    )
end

function _semi_parameter_payload(spec::SemiStructuralSpec)
    return join(
        (
            "semi_structural_parameter_payload_v1",
            "target_contract=$(SEMI_STRUCTURAL_TARGET_CONTRACT_VERSION)",
            "gap_annualization=$(_semi_float_token(SEMI_STRUCTURAL_GAP_ANNUALIZATION))",
            "potential_growth_mean=$(_semi_float_token(spec.potential_growth_mean))",
            "potential_growth_persistence=$(_semi_float_token(spec.potential_growth_persistence))",
            "output_gap_persistence=$(_semi_float_token(spec.output_gap_persistence))",
            "is_slope=$(_semi_float_token(spec.is_slope))",
            "natural_unemployment_mean=$(_semi_float_token(spec.natural_unemployment_mean))",
            "natural_unemployment_persistence=$(_semi_float_token(spec.natural_unemployment_persistence))",
            "neutral_rate_mean=$(_semi_float_token(spec.neutral_rate_mean))",
            "neutral_rate_persistence=$(_semi_float_token(spec.neutral_rate_persistence))",
            "inflation_anchor_mean=$(_semi_float_token(spec.inflation_anchor_mean))",
            "inflation_anchor_persistence=$(_semi_float_token(spec.inflation_anchor_persistence))",
            "inflation_persistence=$(_semi_float_token(spec.inflation_persistence))",
            "phillips_slope=$(_semi_float_token(spec.phillips_slope))",
            "okun_slope=$(_semi_float_token(spec.okun_slope))",
            "policy_smoothing=$(_semi_float_token(spec.policy_smoothing))",
            "taylor_inflation=$(_semi_float_token(spec.taylor_inflation))",
            "taylor_output=$(_semi_float_token(spec.taylor_output))",
            "state_innovation_covariance=$(_semi_matrix_token(spec.state_innovation_covariance))",
            "measurement_covariance=$(_semi_matrix_token(spec.measurement_covariance))",
            "initial_covariance=$(_semi_matrix_token(spec.initial_covariance))",
        ),
        '\n'
    )
end

function _semi_matrix_token(matrix::Matrix{Float64})
    return join(
        (
            _semi_float_token(matrix[row, column])
                for column in axes(matrix, 2) for row in 1:column
        ),
        "."
    )
end
