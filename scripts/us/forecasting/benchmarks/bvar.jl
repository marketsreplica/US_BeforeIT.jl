"""
    BVARSpec(; lags = 4,
        intercept = true,
        tightness = 0.2,
        lag_decay = 1.0,
        own_lag_mean = 1.0,
        intercept_variance = 100.0,
        iw_dof_offset = 2,
        innovation_scale = 1.0,
        scale_floor = 1.0e-8)

Natural-conjugate Bayesian VAR with a matrix-normal/inverse-Wishart prior.
Every hyperparameter is fixed before the origin fit and encoded exactly in
`model_id`. No tuning or model selection occurs inside the benchmark.

For `Y = X * B + E`, the prior is

`Σ ~ IW(S₀, ν₀)` and `B | Σ ~ MN(B₀, V₀, Σ)`.

`B₀` is zero except for each variable's own first lag, whose mean is
`own_lag_mean`. The diagonal row covariance is
`tightness² / (lag^(2lag_decay) * scale_variance[predictor])` for lag
coefficients and `intercept_variance` for the intercept. Training-only scale
variances are the larger of mean squared first differences and `scale_floor`.
This is Minnesota-style shrinkage compatible with the common row covariance
required by the natural-conjugate matrix-normal prior; it does not implement
equation-specific dummy-observation Minnesota priors.

The inverse-Wishart prior has `ν₀ = number_of_targets + iw_dof_offset` and
`S₀ = (iw_dof_offset - 1) * innovation_scale * Diagonal(scale_variances)`,
so its mean is `innovation_scale * Diagonal(scale_variances)`.
`iw_dof_offset >= 2` is required so that this mean exists.
"""
struct BVARSpec <: AbstractBenchmarkSpec
    lags::Int
    intercept::Bool
    tightness::Float64
    lag_decay::Float64
    own_lag_mean::Float64
    intercept_variance::Float64
    iw_dof_offset::Int
    innovation_scale::Float64
    scale_floor::Float64
    function BVARSpec(;
            lags = 4,
            intercept = true,
            tightness = 0.2,
            lag_decay = 1.0,
            own_lag_mean = 1.0,
            intercept_variance = 100.0,
            iw_dof_offset = 2,
            innovation_scale = 1.0,
            scale_floor = 1.0e-8
        )
        fixed_lags = _fixed_lags(lags)
        fixed_intercept = _boolean(intercept, "intercept")
        fixed_tightness = _bvar_positive(tightness, "tightness")
        fixed_lag_decay = _bvar_nonnegative(lag_decay, "lag_decay")
        fixed_own_lag_mean = _bvar_finite(own_lag_mean, "own_lag_mean")
        fixed_intercept_variance =
            _bvar_positive(intercept_variance, "intercept_variance")
        iw_dof_offset isa Integer && !(iw_dof_offset isa Bool) ||
            throw(ArgumentError("iw_dof_offset must be an integer"))
        iw_dof_offset >= 2 ||
            throw(
            ArgumentError(
                "iw_dof_offset must be at least 2 so the inverse-Wishart prior mean exists"
            )
        )
        fixed_innovation_scale =
            _bvar_positive(innovation_scale, "innovation_scale")
        fixed_scale_floor = _bvar_positive(scale_floor, "scale_floor")
        return new(
            fixed_lags,
            fixed_intercept,
            fixed_tightness,
            fixed_lag_decay,
            fixed_own_lag_mean,
            fixed_intercept_variance,
            Int(iw_dof_offset),
            fixed_innovation_scale,
            fixed_scale_floor
        )
    end
end

function model_id(spec::BVARSpec)
    return join(
        (
            "bvar_mniw_v1",
            "p$(spec.lags)",
            _intercept_suffix(spec.intercept),
            "tight$(_bvar_float_token(spec.tightness))",
            "decay$(_bvar_float_token(spec.lag_decay))",
            "own$(_bvar_float_token(spec.own_lag_mean))",
            "ivar$(_bvar_float_token(spec.intercept_variance))",
            "iwoff$(spec.iw_dof_offset)",
            "iscale$(_bvar_float_token(spec.innovation_scale))",
            "floor$(_bvar_float_token(spec.scale_floor))",
            "diffmse_scale",
        ),
        "_"
    )
end

function model_card(spec::BVARSpec)
    card = _card(
        model_id(spec),
        "Natural-conjugate Bayesian VAR",
        "Recursive plug-in path using the matrix-normal posterior coefficient mean.",
        "Each path draws one joint covariance from the inverse-Wishart posterior, one coefficient matrix conditional on it, and correlated innovations at every horizon.",
        "Uses OriginData.y_train only; x_train and x_future are ignored."
    )
    card["prior_family"] = "matrix_normal_inverse_wishart"
    card["prior_version"] = "mniw_minnesota_style_v1"
    card["prior_formula"] =
        "Sigma ~ IW(S0, nu0); B|Sigma ~ MN(B0,V0,Sigma); V0 is diagonal with lag-decay and training-only first-difference scaling."
    card["posterior_formula"] =
        "Vn=(inv(V0)+X'X)^-1; Bn=Vn(inv(V0)B0+X'Y); nun=nu0+T; Sn=S0+(Y-XBn)'(Y-XBn)+(Bn-B0)'inv(V0)(Bn-B0)."
    card["hyperparameters"] = Dict{String, Any}(
        "lags" => spec.lags,
        "intercept" => spec.intercept,
        "tightness" => spec.tightness,
        "lag_decay" => spec.lag_decay,
        "own_lag_mean" => spec.own_lag_mean,
        "intercept_variance" => spec.intercept_variance,
        "iw_dof_offset" => spec.iw_dof_offset,
        "innovation_scale" => spec.innovation_scale,
        "scale_floor" => spec.scale_floor
    )
    card["hyperparameter_selection"] =
        "None. Values are constructor-fixed and model-id encoded."
    card["model_id_encoding"] =
        "All Float64 hyperparameters use exact 16-digit IEEE-754 hexadecimal tokens."
    card["scale_rule"] =
        "Per-target max(mean squared first difference in y_train, scale_floor)."
    card["parameter_uncertainty"] =
        "Included in density draws through B|Sigma,Y."
    card["joint_innovation_uncertainty"] =
        "Included in density draws through one full Sigma draw per path."
    card["point_path_limitation"] =
        "The point path iterates Bn; it is not the Monte Carlo mean of nonlinear multi-step posterior paths."
    card["known_limitations"] =
        "Integer inverse-Wishart degrees of freedom only; no hyperparameter tuning, stochastic volatility, pandemic/ELB treatment, direct forecasts, exogenous predictors, or non-conjugate equation-specific Minnesota prior."
    return card
end

function _forecast(
        spec::BVARSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    fit = _fit_bvar(spec, sample.y_train)
    point = _bvar_point_path(
        sample.y_train,
        fit.posterior_mean,
        spec,
        horizon(sample)
    )
    draws = _bvar_predictive_draws(
        sample.y_train,
        fit,
        spec,
        horizon(sample),
        n_draws,
        seed
    )
    posterior_innovation_mean =
        fit.posterior_scale /
        (fit.posterior_dof - size(sample.y_train, 2) - 1)
    diagnostics = Dict{String, Any}(
        "point_rule" => "recursive_posterior_coefficient_mean",
        "prior_family" => "matrix_normal_inverse_wishart",
        "prior_version" => "mniw_minnesota_style_v1",
        "lags" => spec.lags,
        "intercept" => spec.intercept,
        "training_response_rows" => size(fit.response, 1),
        "design_columns" => size(fit.design, 2),
        "likelihood_design_rank" => rank(fit.design),
        "prior_coefficient_mean" => fit.prior_mean,
        "prior_precision_diagonal" => diag(fit.prior_precision),
        "training_scale_variances" => fit.scale_variances,
        "posterior_coefficient_mean" => fit.posterior_mean,
        "posterior_row_covariance" => fit.posterior_row_covariance,
        "posterior_scale" => fit.posterior_scale,
        "posterior_dof" => fit.posterior_dof,
        "posterior_mean_innovation_covariance" =>
            posterior_innovation_mean,
        "parameter_uncertainty_in_draws" => true,
        "joint_innovation_uncertainty_in_draws" => true,
        "coefficient_draw_frequency" => "once_per_predictive_path",
        "covariance_draw_frequency" => "once_per_predictive_path",
        "future_exogenous_used" => false,
        "hyperparameter_selection" => "none"
    )
    return point, draws, diagnostics
end

function _fit_bvar(spec::BVARSpec, training::Matrix{Float64})
    design, response = _bvar_training_matrices(
        training,
        spec.lags,
        spec.intercept
    )
    prior = _bvar_prior(spec, training, size(design, 2))
    posterior = _mniw_posterior(
        response,
        design,
        prior.mean,
        prior.precision,
        prior.scale,
        prior.dof
    )
    return (
        design = design,
        response = response,
        prior_mean = prior.mean,
        prior_precision = prior.precision,
        prior_scale = prior.scale,
        prior_dof = prior.dof,
        scale_variances = prior.scale_variances,
        posterior_mean = posterior.mean,
        posterior_row_covariance = posterior.row_covariance,
        posterior_scale = posterior.scale,
        posterior_dof = posterior.dof,
    )
end

function _bvar_training_matrices(
        training::Matrix{Float64},
        lags::Int,
        intercept::Bool
    )
    observations, variables = size(training)
    observations > lags ||
        throw(
        ArgumentError(
            "BVAR($lags) requires more than $lags training observations; got $observations"
        )
    )
    response_rows = observations - lags
    columns = Int(intercept) + lags * variables
    design = Matrix{Float64}(undef, response_rows, columns)
    response = Matrix{Float64}(undef, response_rows, variables)
    for (row, time) in enumerate((lags + 1):observations)
        column = 1
        if intercept
            design[row, column] = 1.0
            column += 1
        end
        for lag in 1:lags
            for variable in 1:variables
                design[row, column] = training[time - lag, variable]
                column += 1
            end
        end
        response[row, :] .= training[time, :]
    end
    return design, response
end

function _bvar_prior(
        spec::BVARSpec,
        training::Matrix{Float64},
        coefficient_rows::Int
    )
    _, variables = size(training)
    expected_rows = Int(spec.intercept) + spec.lags * variables
    coefficient_rows == expected_rows ||
        throw(
        DimensionMismatch(
            "BVAR prior expected $expected_rows coefficient rows; got $coefficient_rows"
        )
    )
    scale_variances = _bvar_scale_variances(training, spec.scale_floor)
    prior_mean = zeros(coefficient_rows, variables)
    prior_variances = Vector{Float64}(undef, coefficient_rows)

    row = 1
    if spec.intercept
        prior_variances[row] = spec.intercept_variance
        row += 1
    end
    for lag in 1:spec.lags
        lag_penalty = lag^(2spec.lag_decay)
        for predictor in 1:variables
            prior_variances[row] =
                spec.tightness^2 /
                (lag_penalty * scale_variances[predictor])
            if lag == 1
                prior_mean[row, predictor] = spec.own_lag_mean
            end
            row += 1
        end
    end

    prior_precision = Diagonal(1 ./ prior_variances)
    prior_dof = variables + spec.iw_dof_offset
    prior_scale = Diagonal(
        (spec.iw_dof_offset - 1) *
            spec.innovation_scale .* scale_variances
    )
    return (
        mean = prior_mean,
        precision = Matrix(prior_precision),
        scale = Matrix(prior_scale),
        dof = prior_dof,
        scale_variances = scale_variances,
    )
end

function _bvar_scale_variances(
        training::Matrix{Float64},
        scale_floor::Float64
    )
    differences = diff(training; dims = 1)
    return [
        max(mean(abs2, view(differences, :, variable)), scale_floor)
            for variable in axes(training, 2)
    ]
end

"""
Analytic matrix-normal/inverse-Wishart update used by the BVAR. This low-level
kernel accepts a rank-deficient likelihood design because a positive-definite
proper prior makes the posterior precision full rank. Singular prior precision
or inverse-Wishart scale matrices are rejected.
"""
function _mniw_posterior(
        response::AbstractMatrix{<:Real},
        design::AbstractMatrix{<:Real},
        prior_mean::AbstractMatrix{<:Real},
        prior_precision::AbstractMatrix{<:Real},
        prior_scale::AbstractMatrix{<:Real},
        prior_dof
    )
    y = Matrix{Float64}(response)
    x = Matrix{Float64}(design)
    b0 = Matrix{Float64}(prior_mean)
    precision0 = Matrix{Float64}(prior_precision)
    scale0 = Matrix{Float64}(prior_scale)
    observations, variables = size(y)
    design_rows, coefficients = size(x)

    observations > 0 ||
        throw(ArgumentError("MNIW response must have at least one row"))
    variables > 0 ||
        throw(ArgumentError("MNIW response must have at least one column"))
    design_rows == observations ||
        throw(DimensionMismatch("MNIW response and design row counts differ"))
    coefficients > 0 ||
        throw(ArgumentError("MNIW design must have at least one column"))
    size(b0) == (coefficients, variables) ||
        throw(DimensionMismatch("MNIW prior mean has incompatible dimensions"))
    size(precision0) == (coefficients, coefficients) ||
        throw(
        DimensionMismatch(
            "MNIW prior precision must be $coefficients by $coefficients"
        )
    )
    size(scale0) == (variables, variables) ||
        throw(
        DimensionMismatch(
            "MNIW prior scale must be $variables by $variables"
        )
    )
    all(isfinite, y) && all(isfinite, x) && all(isfinite, b0) &&
        all(isfinite, precision0) && all(isfinite, scale0) ||
        throw(ArgumentError("MNIW inputs must contain only finite values"))
    prior_dof isa Integer && !(prior_dof isa Bool) ||
        throw(ArgumentError("MNIW prior degrees of freedom must be an integer"))
    prior_dof > variables - 1 ||
        throw(
        ArgumentError(
            "MNIW inverse-Wishart prior requires degrees of freedom greater than $(variables - 1)"
        )
    )

    _bvar_positive_definite_factor(precision0, "MNIW prior precision")
    _bvar_positive_definite_factor(scale0, "MNIW prior scale")
    posterior_precision =
        Symmetric(precision0 + x' * x)
    posterior_precision_factor = cholesky(posterior_precision)
    posterior_row_covariance =
        posterior_precision_factor \
        Matrix{Float64}(I, coefficients, coefficients)
    posterior_mean =
        posterior_precision_factor \
        (precision0 * b0 + x' * y)
    residuals = y - x * posterior_mean
    prior_distance = posterior_mean - b0
    posterior_scale = Symmetric(
        scale0 +
            residuals' * residuals +
            prior_distance' * precision0 * prior_distance
    )
    _bvar_positive_definite_factor(
        Matrix(posterior_scale),
        "MNIW posterior scale"
    )
    return (
        mean = posterior_mean,
        row_covariance = Matrix(Symmetric(posterior_row_covariance)),
        scale = Matrix(posterior_scale),
        dof = Int(prior_dof) + observations,
    )
end

function _bvar_point_path(
        training::Matrix{Float64},
        coefficients::Matrix{Float64},
        spec::BVARSpec,
        forecast_horizon::Int
    )
    observations, variables = size(training)
    history =
        Matrix{Float64}(undef, observations + forecast_horizon, variables)
    history[1:observations, :] .= training
    for step in 1:forecast_horizon
        time = observations + step
        regressor = _bvar_regressor(history, time, spec)
        history[time, :] .= coefficients' * regressor
    end
    return history[(observations + 1):end, :]
end

function _bvar_predictive_draws(
        training::Matrix{Float64},
        fit,
        spec::BVARSpec,
        forecast_horizon::Int,
        n_draws::Int,
        seed::Int
    )
    observations, variables = size(training)
    draws =
        Array{Float64}(undef, forecast_horizon, variables, n_draws)
    n_draws == 0 && return draws
    rng = MersenneTwister(seed)
    row_factor = cholesky(
        Symmetric(fit.posterior_row_covariance)
    ).L

    for draw in 1:n_draws
        innovation_covariance = _rand_inverse_wishart(
            rng,
            fit.posterior_scale,
            fit.posterior_dof
        )
        innovation_factor =
            cholesky(Symmetric(innovation_covariance)).L
        coefficient_draw = _rand_matrix_normal(
            rng,
            fit.posterior_mean,
            row_factor,
            innovation_factor
        )
        history =
            Matrix{Float64}(undef, observations + forecast_horizon, variables)
        history[1:observations, :] .= training
        for step in 1:forecast_horizon
            time = observations + step
            regressor = _bvar_regressor(history, time, spec)
            history[time, :] .=
                coefficient_draw' * regressor +
                innovation_factor * randn(rng, variables)
            draws[step, :, draw] .= history[time, :]
        end
    end
    return draws
end

function _rand_matrix_normal(
        rng::AbstractRNG,
        mean_matrix::Matrix{Float64},
        row_factor,
        column_factor
    )
    size(row_factor) ==
        (size(mean_matrix, 1), size(mean_matrix, 1)) ||
        throw(DimensionMismatch("matrix-normal row factor has incompatible dimensions"))
    size(column_factor) ==
        (size(mean_matrix, 2), size(mean_matrix, 2)) ||
        throw(DimensionMismatch("matrix-normal column factor has incompatible dimensions"))
    return mean_matrix +
        row_factor * randn(rng, size(mean_matrix)) * column_factor'
end

function _bvar_regressor(history, time::Int, spec::BVARSpec)
    variables = size(history, 2)
    regressor =
        Vector{Float64}(undef, Int(spec.intercept) + spec.lags * variables)
    column = 1
    if spec.intercept
        regressor[column] = 1.0
        column += 1
    end
    for lag in 1:spec.lags
        for variable in 1:variables
            regressor[column] = history[time - lag, variable]
            column += 1
        end
    end
    return regressor
end

function _rand_inverse_wishart(
        rng::AbstractRNG,
        scale::Matrix{Float64},
        dof::Int
    )
    variables = size(scale, 1)
    dof > variables - 1 ||
        throw(ArgumentError("inverse-Wishart draw has invalid degrees of freedom"))
    scale_factor =
        _bvar_positive_definite_factor(scale, "inverse-Wishart scale")
    inverse_scale_factor =
        scale_factor.U \ Matrix{Float64}(I, variables, variables)
    standard_normals = randn(rng, variables, dof)
    wishart_sample =
        Symmetric(
        inverse_scale_factor *
            standard_normals *
            standard_normals' *
            inverse_scale_factor'
    )
    wishart_factor = try
        cholesky(wishart_sample)
    catch error
        if error isa PosDefException
            throw(
                ArgumentError(
                    "inverse-Wishart precision draw is numerically rank deficient"
                )
            )
        end
        rethrow()
    end
    covariance =
        wishart_factor \ Matrix{Float64}(I, variables, variables)
    return Matrix(Symmetric(covariance))
end

function _bvar_positive_definite_factor(matrix, name)
    size(matrix, 1) == size(matrix, 2) ||
        throw(DimensionMismatch("$name must be square"))
    isapprox(matrix, matrix'; rtol = 1.0e-12, atol = 0.0) ||
        throw(ArgumentError("$name must be symmetric"))
    return try
        cholesky(Symmetric(matrix))
    catch error
        if error isa PosDefException
            throw(ArgumentError("$name must be positive definite"))
        end
        rethrow()
    end
end

function _bvar_positive(value, name)
    number = _bvar_finite(value, name)
    number > 0 || throw(ArgumentError("$name must be positive"))
    return number
end

function _bvar_nonnegative(value, name)
    number = _bvar_finite(value, name)
    number >= 0 || throw(ArgumentError("$name must be nonnegative"))
    return number
end

function _bvar_finite(value, name)
    value isa Real && !(value isa Bool) ||
        throw(ArgumentError("$name must be a real number"))
    number = Float64(value)
    isfinite(number) || throw(ArgumentError("$name must be finite"))
    return iszero(number) ? 0.0 : number
end

function _bvar_float_token(value::Float64)
    return lowercase(
        string(reinterpret(UInt64, value); base = 16, pad = 16)
    )
end
