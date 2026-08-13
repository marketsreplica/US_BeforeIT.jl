"""
    DirectARSpec(; candidate_lags = 1:8, intercept = true)

Horizon-specific univariate autoregression. For target `j` and horizon `h`,
the training regression is

`y[t + h, j] = c[h, j] + sum(a[h, j, lag] * y[t + 1 - lag, j]) + error[t, h, j]`.

Every predictor is therefore known at historical forecast origin `t`, and the
latest response used in estimation is `y[T, j]`. Each target and horizon
selects its lag independently by BIC on a common candidate window. Supplying a
single candidate produces a fixed-lag direct AR.

Density paths add one draw from the training-only joint covariance of aligned
direct forecast residuals. The joint residual vector is ordered by horizon and
then target. Draws include neither coefficient uncertainty nor future target
values.
"""
struct DirectARSpec <: AbstractBenchmarkSpec
    candidate_lags::Vector{Int}
    intercept::Bool
    function DirectARSpec(; candidate_lags = 1:8, intercept = true)
        intercept isa Bool ||
            throw(ArgumentError("intercept must be Bool"))
        raw_candidates = if candidate_lags isa Number ||
                candidate_lags isa Bool
            [candidate_lags]
        else
            try
                collect(candidate_lags)
            catch
                throw(
                    ArgumentError(
                        "candidate_lags must be an integer or iterable of integers"
                    )
                )
            end
        end
        isempty(raw_candidates) &&
            throw(ArgumentError("candidate_lags must not be empty"))
        all(
            lag -> lag isa Integer && !(lag isa Bool),
            raw_candidates
        ) ||
            throw(
            ArgumentError(
                "candidate_lags must contain only integers"
            )
        )
        integer_candidates = sort!(unique!(Int.(raw_candidates)))
        all(>=(1), integer_candidates) ||
            throw(ArgumentError("candidate_lags must be at least 1"))
        return new(integer_candidates, intercept)
    end
end

function model_id(spec::DirectARSpec)
    lag_rule = if length(spec.candidate_lags) == 1
        "fixed_p$(only(spec.candidate_lags))"
    else
        "bic_p$(join(spec.candidate_lags, '-'))"
    end
    return join(
        (
            "direct_univariate_ar_v1",
            lag_rule,
            _intercept_suffix(spec.intercept),
            "joint_aligned_residual_gaussian_v1",
        ),
        "_"
    )
end

function model_card(spec::DirectARSpec)
    lag_rule = if length(spec.candidate_lags) == 1
        "Fixed lag $(only(spec.candidate_lags))."
    else
        "Target- and horizon-specific BIC over $(spec.candidate_lags), using one common training window within each horizon."
    end
    card = _card(
        model_id(spec),
        "Direct multi-step univariate autoregression",
        "One horizon-specific OLS regression per target and forecast horizon. $lag_rule",
        "One zero-mean Gaussian draw from the full training-only covariance of aligned horizon-by-target direct residuals is added to each point path.",
        "Rejects x_train and x_future; no exogenous values are used."
    )
    card["estimation_equation"] =
        "y[t+h,j] = intercept[h,j] + sum_lag beta[h,j,lag]*y[t+1-lag,j] + error[t,h,j]"
    card["historical_forecast_origin"] =
        "Regressors use observations no later than t; the response is y[t+h], with t+h no later than the current origin."
    card["lag_selection"] =
        "BIC is evaluated separately for every target and horizon. All candidates at a horizon use origins max(candidate_lags):(T-h), so their response samples are identical; the selected lag is then refitted on origins p:(T-h)."
    card["density_vector_order"] =
        "horizon_major_target_minor: (h=1,j=1..K), then (h=2,j=1..K), and so on."
    card["density_alignment"] =
        "Residual covariance uses only historical forecast origins max(selected_lags):(T-H), for which every selected horizon-target regression is evaluable."
    card["density_covariance"] =
        "Corrected sample covariance after column centering; a density run requires more aligned origins than joint residual dimensions and full centered-residual column rank."
    card["parameter_uncertainty"] =
        "Excluded. Coefficients, lag-selection uncertainty, and covariance-estimation uncertainty are not drawn."
    card["model_id_encoding"] =
        "Version, exact canonical lag candidate set, intercept choice, and joint-density rule are encoded in the identifier."
    card["literature"] = [
        "Marcellino, Stock, and Watson (2006), A comparison of direct and iterated multistep AR methods for forecasting macroeconomic time series, Journal of Econometrics 135, 499-526, https://doi.org/10.1016/j.jeconom.2005.07.020",
        "Chevillon (2007), Direct Multi-Step Estimation and Forecasting, Journal of Economic Surveys 21, 746-785, https://doi.org/10.1111/j.1467-6419.2007.00518.x",
    ]
    card["comparative_claim"] =
        "No dominance claim is made. Direct-versus-iterated accuracy is an empirical question and must be evaluated under the frozen origin protocol."
    card["known_limitations"] =
        "Linear, univariate point equations; no cross-target predictors, exogenous inputs, regularization, breaks, parameter uncertainty, lag-selection uncertainty, or covariance uncertainty. BIC uses the Gaussian OLS criterion without a HAC correction for overlapping-horizon residuals. Full-rank density estimation can fail in short samples or at large horizon-target dimension."
    return card
end

function _forecast(
        spec::DirectARSpec,
        sample::OriginData,
        n_draws::Int,
        seed::Int
    )
    if sample.x_train !== nothing || sample.x_future !== nothing
        throw(
            ArgumentError(
                "DirectARSpec rejects x_train and x_future; use an explicitly exogenous benchmark instead"
            )
        )
    end

    observations, variables = size(sample.y_train)
    forecast_horizon = horizon(sample)
    maximum_lag = maximum(spec.candidate_lags)
    maximum_parameters = maximum_lag + Int(spec.intercept)

    selected_lags =
        Matrix{Int}(undef, forecast_horizon, variables)
    coefficients =
        Matrix{Vector{Float64}}(undef, forecast_horizon, variables)
    criteria =
        Matrix{Dict{Int, Float64}}(undef, forecast_horizon, variables)
    selection_rows =
        Matrix{Int}(undef, forecast_horizon, variables)
    estimation_rows =
        Matrix{Int}(undef, forecast_horizon, variables)
    point =
        Matrix{Float64}(undef, forecast_horizon, variables)

    for forecast_step in 1:forecast_horizon
        common_rows =
            observations - forecast_step - maximum_lag + 1
        common_rows > maximum_parameters ||
            throw(
            ArgumentError(
                "direct AR horizon $forecast_step needs more than $maximum_parameters common lag-selection rows; got $(max(common_rows, 0))"
            )
        )

        for variable in 1:variables
            series = @view(sample.y_train[:, variable])
            selected_lag, scores = _direct_select_lag(
                series,
                forecast_step,
                spec.candidate_lags,
                spec.intercept,
                maximum_lag
            )
            fit = _fit_direct_ar(
                series,
                forecast_step,
                selected_lag,
                spec.intercept,
                selected_lag
            )
            selected_lags[forecast_step, variable] = selected_lag
            coefficients[forecast_step, variable] = fit.coefficients
            criteria[forecast_step, variable] = scores
            selection_rows[forecast_step, variable] = common_rows
            estimation_rows[forecast_step, variable] =
                length(fit.residuals)
            regressor = _direct_regressor(
                series,
                observations,
                selected_lag,
                spec.intercept
            )
            point[forecast_step, variable] =
                dot(regressor, fit.coefficients)
        end
    end

    alignment_first_origin = maximum(selected_lags)
    alignment_last_origin = observations - forecast_horizon
    aligned_rows =
        max(alignment_last_origin - alignment_first_origin + 1, 0)
    joint_dimensions = forecast_horizon * variables
    density = if n_draws == 0
        (
            draws = Array{Float64}(
                undef,
                forecast_horizon,
                variables,
                0
            ),
            covariance = nothing,
            residual_rank = nothing,
        )
    else
        _direct_density_draws(
            sample.y_train,
            point,
            coefficients,
            selected_lags,
            spec.intercept,
            forecast_horizon,
            n_draws,
            seed
        )
    end

    diagnostics = Dict{String, Any}(
        "point_rule" => "horizon_specific_direct_univariate_ar",
        "selection_rule" => "BIC_common_window_within_horizon",
        "candidate_lags" => copy(spec.candidate_lags),
        "selected_lags" => selected_lags,
        "coefficients_by_horizon_target" => coefficients,
        "bic_by_horizon_target" => criteria,
        "common_selection_first_origin" => maximum_lag,
        "common_selection_rows" => selection_rows,
        "final_estimation_rows" => estimation_rows,
        "joint_residual_order" => "horizon_major_target_minor",
        "joint_residual_first_origin" => alignment_first_origin,
        "joint_residual_last_origin" => alignment_last_origin,
        "joint_residual_rows" => aligned_rows,
        "joint_residual_dimensions" => joint_dimensions,
        "joint_residual_covariance" => density.covariance,
        "joint_residual_rank" => density.residual_rank,
        "density_covariance_status" =>
            n_draws == 0 ? "not_requested" : "estimated_full_rank",
        "parameter_uncertainty_in_draws" => false,
        "lag_selection_uncertainty_in_draws" => false,
        "covariance_uncertainty_in_draws" => false,
        "future_exogenous_used" => false
    )
    return point, density.draws, diagnostics
end

function _direct_select_lag(
        series,
        forecast_step::Int,
        candidates,
        intercept::Bool,
        common_first_origin::Int
    )
    scores = Dict{Int, Float64}()
    for lag in candidates
        try
            fit = _fit_direct_ar(
                series,
                forecast_step,
                lag,
                intercept,
                common_first_origin
            )
            observations = length(fit.residuals)
            parameters = lag + Int(intercept)
            variance = max(
                sum(abs2, fit.residuals) / observations,
                eps(Float64)
            )
            scores[lag] =
                observations * log(variance) +
                parameters * log(observations)
        catch error
            if error isa ArgumentError ||
                    error isa LinearAlgebra.SingularException
                scores[lag] = Inf
            else
                rethrow()
            end
        end
    end

    finite_candidates =
        filter(lag -> isfinite(scores[lag]), candidates)
    isempty(finite_candidates) &&
        throw(
        ArgumentError(
            "no direct AR candidate could be estimated at horizon $forecast_step"
        )
    )
    selected = first(finite_candidates)
    for lag in Iterators.drop(finite_candidates, 1)
        if scores[lag] < scores[selected]
            selected = lag
        end
    end
    return selected, scores
end

function _fit_direct_ar(
        series,
        forecast_step::Int,
        lag::Int,
        intercept::Bool,
        first_origin::Int
    )
    design, response, origins = _direct_training_matrices(
        series,
        forecast_step,
        lag,
        intercept,
        first_origin
    )
    parameters = size(design, 2)
    rank(design) == parameters ||
        throw(ArgumentError("direct AR design matrix is rank deficient"))
    coefficients = design \ response
    all(isfinite, coefficients) ||
        throw(ArgumentError("direct AR coefficients are not finite"))
    residuals = response - design * coefficients
    all(isfinite, residuals) ||
        throw(ArgumentError("direct AR residuals are not finite"))
    return (
        coefficients = coefficients,
        residuals = residuals,
        design = design,
        response = response,
        origins = origins,
    )
end

function _direct_training_matrices(
        series,
        forecast_step::Int,
        lag::Int,
        intercept::Bool,
        first_origin::Int
    )
    forecast_step >= 1 ||
        throw(ArgumentError("direct AR horizon must be at least 1"))
    lag >= 1 ||
        throw(ArgumentError("direct AR lag must be at least 1"))
    first_origin >= lag ||
        throw(
        ArgumentError(
            "first direct AR forecast origin must be at least its lag"
        )
    )
    observations = length(series)
    last_origin = observations - forecast_step
    first_origin <= last_origin ||
        throw(
        ArgumentError(
            "direct AR horizon $forecast_step has no training responses"
        )
    )
    origins = collect(first_origin:last_origin)
    parameters = lag + Int(intercept)
    length(origins) > parameters ||
        throw(
        ArgumentError(
            "direct AR fit has no residual degrees of freedom"
        )
    )

    design =
        Matrix{Float64}(undef, length(origins), parameters)
    response = Vector{Float64}(undef, length(origins))
    for (row, historical_origin) in enumerate(origins)
        design[row, :] .= _direct_regressor(
            series,
            historical_origin,
            lag,
            intercept
        )
        response[row] = series[historical_origin + forecast_step]
    end
    all(isfinite, design) ||
        throw(ArgumentError("direct AR design is not finite"))
    all(isfinite, response) ||
        throw(ArgumentError("direct AR response is not finite"))
    return design, response, origins
end

function _direct_regressor(
        series,
        historical_origin::Int,
        lag::Int,
        intercept::Bool
    )
    historical_origin >= lag ||
        throw(
        ArgumentError(
            "direct AR forecast origin must be at least its lag"
        )
    )
    historical_origin <= length(series) ||
        throw(
        ArgumentError(
            "direct AR forecast origin exceeds available observations"
        )
    )
    regressor = Vector{Float64}(undef, lag + Int(intercept))
    column = 1
    if intercept
        regressor[column] = 1.0
        column += 1
    end
    for delay in 1:lag
        regressor[column] = series[historical_origin + 1 - delay]
        column += 1
    end
    return regressor
end

function _direct_joint_residuals(
        training,
        coefficients,
        selected_lags,
        intercept::Bool,
        forecast_horizon::Int
    )
    observations, variables = size(training)
    first_origin = maximum(selected_lags)
    last_origin = observations - forecast_horizon
    first_origin <= last_origin ||
        throw(
        ArgumentError(
            "direct AR density has no aligned historical forecast origins"
        )
    )
    origins = collect(first_origin:last_origin)
    dimensions = forecast_horizon * variables
    residuals =
        Matrix{Float64}(undef, length(origins), dimensions)
    for (row, historical_origin) in enumerate(origins)
        for forecast_step in 1:forecast_horizon
            for variable in 1:variables
                lag = selected_lags[forecast_step, variable]
                regressor = _direct_regressor(
                    @view(training[:, variable]),
                    historical_origin,
                    lag,
                    intercept
                )
                residual_column =
                    (forecast_step - 1) * variables + variable
                residuals[row, residual_column] =
                    training[
                    historical_origin + forecast_step,
                    variable,
                ] -
                    dot(
                    regressor,
                    coefficients[forecast_step, variable]
                )
            end
        end
    end
    all(isfinite, residuals) ||
        throw(ArgumentError("direct AR joint residuals are not finite"))
    return residuals, origins
end

function _direct_joint_residual_covariance(residuals)
    observations, dimensions = size(residuals)
    observations > dimensions ||
        throw(
        ArgumentError(
            "direct AR density requires more aligned residual origins than joint dimensions; got $observations origins for $dimensions dimensions"
        )
    )
    centered =
        residuals .- mean(residuals; dims = 1)
    residual_rank = rank(centered)
    residual_rank == dimensions ||
        throw(
        ArgumentError(
            "direct AR centered joint residual matrix is rank deficient: rank $residual_rank for $dimensions dimensions"
        )
    )
    degrees_of_freedom = observations - 1
    degrees_of_freedom >= dimensions ||
        throw(
        ArgumentError(
            "direct AR joint covariance has insufficient degrees of freedom"
        )
    )
    covariance =
        Matrix{Float64}(centered' * centered / degrees_of_freedom)
    covariance =
        (covariance + covariance') / 2
    all(isfinite, covariance) ||
        throw(
        ArgumentError(
            "direct AR joint residual covariance is not finite"
        )
    )
    factor = try
        cholesky(Symmetric(covariance); check = true).L
    catch error
        if error isa LinearAlgebra.PosDefException
            throw(
                ArgumentError(
                    "direct AR joint residual covariance is not positive definite"
                )
            )
        end
        rethrow()
    end
    return (
        covariance = covariance,
        factor = Matrix{Float64}(factor),
        residual_rank = residual_rank,
    )
end

function _direct_density_draws(
        training,
        point,
        coefficients,
        selected_lags,
        intercept::Bool,
        forecast_horizon::Int,
        n_draws::Int,
        seed::Int
    )
    residuals, _ = _direct_joint_residuals(
        training,
        coefficients,
        selected_lags,
        intercept,
        forecast_horizon
    )
    covariance_fit =
        _direct_joint_residual_covariance(residuals)
    variables = size(training, 2)
    draws =
        Array{Float64}(
        undef,
        forecast_horizon,
        variables,
        n_draws
    )
    rng = MersenneTwister(seed)
    for draw in 1:n_draws
        innovation =
            covariance_fit.factor *
            randn(rng, forecast_horizon * variables)
        for forecast_step in 1:forecast_horizon
            for variable in 1:variables
                residual_column =
                    (forecast_step - 1) * variables + variable
                draws[forecast_step, variable, draw] =
                    point[forecast_step, variable] +
                    innovation[residual_column]
            end
        end
    end
    return (
        draws = draws,
        covariance = covariance_fit.covariance,
        residual_rank = covariance_fit.residual_rank,
    )
end
