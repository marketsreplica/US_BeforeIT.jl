module USForecastScores

using LinearAlgebra
using Statistics

export brier_score
export coverage_summary
export energy_score
export ensemble_crps
export ensemble_pit_interval
export interval_score
export point_scores
export quantile_score
export relative_skill
export seasonal_naive_scale
export variogram_score
export weighted_interval_score

# Every finite Float64 is an integer multiple of 2^-1074. Across the largest
# vector indexable by Julia, an exact sum of squared Float64 differences needs
# fewer than 4,262 significand bits; the corresponding WIS product sum needs
# fewer than 3,237. This precision therefore retains every dyadic input term
# and leaves guard bits for division/square root before the final Float64
# rounding. A conventional 256-bit BigFloat is not sufficient across the full
# Float64 exponent range.
const FLOAT64_AGGREGATION_PRECISION_BITS = 4608

function finite_vector(
        values::AbstractVector{<:Real},
        name::AbstractString;
        minimum_length::Integer = 1
    )
    length(values) >= minimum_length ||
        throw(ArgumentError("$name must contain at least $minimum_length value(s)"))
    result = Float64.(values)
    all(isfinite, result) ||
        throw(ArgumentError("$name must contain only finite values"))
    return result
end

function paired_finite_vectors(
        first::AbstractVector{<:Real},
        second::AbstractVector{<:Real},
        first_name::AbstractString,
        second_name::AbstractString
    )
    length(first) == length(second) ||
        throw(
        DimensionMismatch(
            "$first_name and $second_name must have equal length; got " *
                "$(length(first)) and $(length(second))"
        )
    )
    return (
        finite_vector(first, first_name),
        finite_vector(second, second_name),
    )
end

"""
    seasonal_naive_scale(training; seasonality = 1)

Return the mean absolute `seasonality`-period change in an origin's training
sample. This is the denominator used by MASE. The caller is responsible for
supplying training data available at the forecast origin; realized evaluation
truth must never be used to construct the scale.
"""
function seasonal_naive_scale(
        training::AbstractVector{<:Real};
        seasonality::Integer = 1
    )
    seasonality isa Bool &&
        throw(ArgumentError("seasonality must be an integer, not Bool"))
    seasonality >= 1 ||
        throw(ArgumentError("seasonality must be at least 1"))
    seasonality < length(training) ||
        throw(
        ArgumentError(
            "training must contain at least seasonality + 1 values"
        )
    )
    lag = Int(seasonality)
    sample = finite_vector(
        training,
        "training";
        minimum_length = lag + 1
    )
    scale = setprecision(
        BigFloat,
        FLOAT64_AGGREGATION_PRECISION_BITS,
    ) do
        total = BigFloat(0)
        for index in (lag + 1):length(sample)
            total += abs(
                BigFloat(sample[index]) -
                    BigFloat(sample[index - lag])
            )
        end
        Float64(total / BigFloat(length(sample) - lag))
    end
    finite_result(scale, "seasonal-naive scale")
    isfinite(scale) && scale > 0 ||
        throw(
        DomainError(
            scale,
            "the seasonal-naive MASE denominator must be finite and positive"
        )
    )
    return scale
end

"""
    point_scores(actual, forecast; mase_denominator = nothing)

Compute point-forecast scores with forecast error defined as
`actual - forecast`. The result contains the observation count, mean error,
RMSE, MAE, median absolute error, and optionally MASE. A MASE denominator must
be positive and should be produced from origin-eligible training data with
[`seasonal_naive_scale`](@ref).
"""
function point_scores(
        actual::AbstractVector{<:Real},
        forecast::AbstractVector{<:Real};
        mase_denominator::Union{Nothing, Real} = nothing
    )
    observed, predicted =
        paired_finite_vectors(actual, forecast, "actual", "forecast")
    aggregates = setprecision(
        BigFloat,
        FLOAT64_AGGREGATION_PRECISION_BITS,
    ) do
        error_sum = BigFloat(0)
        absolute_error_sum = BigFloat(0)
        squared_error_sum = BigFloat(0)
        absolute_errors = BigFloat[]
        sizehint!(absolute_errors, length(observed))
        for index in eachindex(observed)
            error =
                BigFloat(observed[index]) - BigFloat(predicted[index])
            absolute_error = abs(error)
            error_sum += error
            absolute_error_sum += absolute_error
            squared_error_sum += error^2
            push!(absolute_errors, absolute_error)
        end
        count = BigFloat(length(observed))
        return (
            mean_error = error_sum / count,
            rmse = sqrt(squared_error_sum / count),
            mae = absolute_error_sum / count,
            median_absolute_error = median(absolute_errors),
        )
    end
    mean_error =
        finite_result(Float64(aggregates.mean_error), "mean error")
    rmse = finite_result(Float64(aggregates.rmse), "RMSE")
    mae = finite_result(Float64(aggregates.mae), "MAE")
    median_absolute_error = finite_result(
        Float64(aggregates.median_absolute_error),
        "median absolute error"
    )

    mase = if isnothing(mase_denominator)
        nothing
    else
        denominator = Float64(mase_denominator)
        isfinite(denominator) && denominator > 0 ||
            throw(
            DomainError(
                denominator,
                "mase_denominator must be finite and positive"
            )
        )
        scaled = setprecision(
            BigFloat,
            FLOAT64_AGGREGATION_PRECISION_BITS,
        ) do
            Float64(aggregates.mae / BigFloat(denominator))
        end
        finite_result(scaled, "MASE")
    end

    return (
        n = length(observed),
        mean_error,
        rmse,
        mae,
        median_absolute_error,
        mase = mase,
    )
end

"""
    relative_skill(model_loss, reference_loss; percentage = false)

Return `1 - model_loss / reference_loss`, so positive values favor the model
and zero denotes equal loss. Set `percentage = true` for the Poledna-style
percentage gain convention.
"""
function relative_skill(
        model_loss::Real,
        reference_loss::Real;
        percentage::Bool = false
    )
    candidate = Float64(model_loss)
    reference = Float64(reference_loss)
    isfinite(candidate) && candidate >= 0 ||
        throw(DomainError(candidate, "model_loss must be finite and nonnegative"))
    isfinite(reference) && reference > 0 ||
        throw(DomainError(reference, "reference_loss must be finite and positive"))
    skill = 1 - candidate / reference
    result = percentage ? 100 * skill : skill
    return finite_result(result, "relative skill")
end

"""
    quantile_score(actual, quantile, probability)

Compute twice the pinball loss for a quantile forecast. This normalization
makes the median score equal to absolute error.
"""
function quantile_score(actual::Real, quantile::Real, probability::Real)
    y = finite_scalar(actual, "actual")
    q = finite_scalar(quantile, "quantile")
    probability_value = finite_probability(
        probability,
        "probability";
        open_interval = true
    )
    error = y - q
    isfinite(error) ||
        throw(
        DomainError(
            error,
            "quantile error overflowed despite finite inputs"
        )
    )
    score = 2 * (
        probability_value * max(error, 0.0) +
            (1 - probability_value) * max(-error, 0.0)
    )
    return finite_result(score, "quantile score")
end

"""
    interval_score(actual, lower, upper, alpha)

Compute the central `(1 - alpha)` interval score: width plus asymmetric
penalties of `2 / alpha` for observations below or above the interval.
"""
function interval_score(
        actual::Real,
        lower::Real,
        upper::Real,
        alpha::Real
    )
    y = finite_scalar(actual, "actual")
    lower_value = finite_scalar(lower, "lower")
    upper_value = finite_scalar(upper, "upper")
    lower_value <= upper_value ||
        throw(ArgumentError("lower must be no greater than upper"))
    alpha_value =
        finite_probability(alpha, "alpha"; open_interval = true)

    width = upper_value - lower_value
    isfinite(width) ||
        throw(
        DomainError(
            width,
            "interval width overflowed despite finite bounds"
        )
    )
    below_penalty =
        y < lower_value ? 2 * ((lower_value - y) / alpha_value) : 0.0
    above_penalty =
        y > upper_value ? 2 * ((y - upper_value) / alpha_value) : 0.0
    score = width + below_penalty + above_penalty
    return finite_result(score, "interval score")
end

"""
    weighted_interval_score(actual, median, lowers, uppers, alphas)

Compute the weighted interval score (WIS) for nested central prediction
intervals. `alphas` are miscoverage probabilities. Inputs are rejected when
intervals cross or become less nested as `alpha` increases.
"""
function weighted_interval_score(
        actual::Real,
        median_forecast::Real,
        lowers::AbstractVector{<:Real},
        uppers::AbstractVector{<:Real},
        alphas::AbstractVector{<:Real}
    )
    length(lowers) == length(uppers) == length(alphas) ||
        throw(
        DimensionMismatch(
            "lowers, uppers, and alphas must have equal length"
        )
    )
    isempty(alphas) &&
        throw(ArgumentError("at least one central interval is required"))

    lower_values = finite_vector(lowers, "lowers")
    upper_values = finite_vector(uppers, "uppers")
    alpha_values = finite_vector(alphas, "alphas")
    all(alpha -> 0 < alpha < 1, alpha_values) ||
        throw(ArgumentError("all alphas must lie strictly between 0 and 1"))
    issorted(alpha_values) ||
        throw(ArgumentError("alphas must be strictly increasing"))
    allunique(alpha_values) ||
        throw(ArgumentError("alphas must be unique"))

    for index in eachindex(alpha_values)
        lower_values[index] <= upper_values[index] ||
            throw(ArgumentError("interval $index has lower greater than upper"))
    end
    for index in 2:length(alpha_values)
        lower_values[index - 1] <= lower_values[index] ||
            throw(
            ArgumentError(
                "central intervals must be nested: lower bounds must not " *
                    "decrease as alpha increases"
            )
        )
        upper_values[index - 1] >= upper_values[index] ||
            throw(
            ArgumentError(
                "central intervals must be nested: upper bounds must not " *
                    "increase as alpha increases"
            )
        )
    end

    y = finite_scalar(actual, "actual")
    median_value = finite_scalar(median_forecast, "median_forecast")
    for index in eachindex(alpha_values)
        lower_values[index] <= median_value <= upper_values[index] ||
            throw(
            ArgumentError(
                "median_forecast must lie inside every central interval"
            )
        )
    end
    # Applying interval weights and the final denominator before the Float64
    # conversion avoids both overflow and underflow in representable WIS
    # results. The module-wide precision bound also retains low-order Float64
    # terms that can decide rounding after extreme opposite-sign subtraction.
    score = setprecision(
        BigFloat,
        FLOAT64_AGGREGATION_PRECISION_BITS,
    ) do
        big_y = BigFloat(y)
        big_median = BigFloat(median_value)
        total = abs(big_y - big_median) / 2
        for index in eachindex(alpha_values)
            big_lower = BigFloat(lower_values[index])
            big_upper = BigFloat(upper_values[index])
            total +=
                BigFloat(alpha_values[index]) *
                (big_upper - big_lower) / 2
            if y < lower_values[index]
                total += big_lower - big_y
            elseif y > upper_values[index]
                total += big_y - big_upper
            end
        end
        return total / (BigFloat(length(alpha_values)) + BigFloat(0.5))
    end
    return finite_result(Float64(score), "weighted interval score")
end

"""
    ensemble_crps(actual, draws)

Compute the continuous ranked probability score for the empirical predictive
distribution represented by `draws`. The implementation is exact and uses a
sorted `O(M log M)` pairwise-distance identity.
"""
function ensemble_crps(
        actual::Real,
        draws::AbstractVector{<:Real}
    )
    y = finite_scalar(actual, "actual")
    sample = finite_vector(draws, "draws")
    draw_count = length(sample)
    ordered = sort(sample)

    first_term = mean(abs.(ordered .- y))
    pair_sum = 0.0
    for index in 1:(draw_count - 1)
        pair_sum +=
            index * (draw_count - index) *
            (ordered[index + 1] - ordered[index])
    end
    second_term = pair_sum / draw_count^2
    score = first_term - second_term
    return nonnegative_score(
        score,
        "CRPS";
        numerical_scale = first_term + second_term
    )
end

"""
    ensemble_pit_interval(actual, draws)

Return `(lower, upper, midpoint)` for the empirical PIT. Ties occupy the
interval `[F(actual-), F(actual)]`; `midpoint` is a deterministic diagnostic,
not a randomized PIT.
"""
function ensemble_pit_interval(
        actual::Real,
        draws::AbstractVector{<:Real}
    )
    y = finite_scalar(actual, "actual")
    sample = finite_vector(draws, "draws")
    less = count(value -> value < y, sample)
    less_or_equal = count(value -> value <= y, sample)
    lower = less / length(sample)
    upper = less_or_equal / length(sample)
    return (lower = lower, upper = upper, midpoint = (lower + upper) / 2)
end

"""
    coverage_summary(actual, lowers, uppers)

Summarize empirical central-interval coverage, mean width, and one-sided miss
rates over a balanced finite sample.
"""
function coverage_summary(
        actual::AbstractVector{<:Real},
        lowers::AbstractVector{<:Real},
        uppers::AbstractVector{<:Real}
    )
    length(actual) == length(lowers) == length(uppers) ||
        throw(
        DimensionMismatch(
            "actual, lowers, and uppers must have equal length"
        )
    )
    observed = finite_vector(actual, "actual")
    lower_values = finite_vector(lowers, "lowers")
    upper_values = finite_vector(uppers, "uppers")
    all(lower_values .<= upper_values) ||
        throw(ArgumentError("every lower bound must be no greater than its upper bound"))

    below = observed .< lower_values
    above = observed .> upper_values
    covered = .!(below .| above)
    widths = upper_values .- lower_values
    all(isfinite, widths) ||
        throw(
        DomainError(
            widths,
            "interval widths overflowed despite finite bounds"
        )
    )
    return (
        n = length(observed),
        coverage = mean(covered),
        mean_width =
            stable_nonnegative_mean(widths, "mean interval width"),
        below_rate = mean(below),
        above_rate = mean(above),
    )
end

"""
    brier_score(outcome, probability)

Compute squared error for a binary-event probability forecast.
"""
function brier_score(outcome, probability::Real)
    observed = if outcome isa Bool
        outcome ? 1.0 : 0.0
    elseif outcome isa Integer && outcome in (0, 1)
        Float64(outcome)
    else
        throw(ArgumentError("outcome must be Bool or integer 0/1"))
    end
    probability_value =
        finite_probability(probability, "probability"; open_interval = false)
    return abs2(probability_value - observed)
end

function standardized_ensemble(
        actual::AbstractVector{<:Real},
        draws::AbstractMatrix{<:Real},
        scales::AbstractVector{<:Real};
        centers::Union{Nothing, AbstractVector{<:Real}} = nothing
    )
    observed = finite_vector(actual, "actual")
    size(draws, 1) >= 1 ||
        throw(ArgumentError("draws must contain at least one row"))
    size(draws, 2) == length(observed) ||
        throw(
        DimensionMismatch(
            "draw columns must equal the actual dimension; got " *
                "$(size(draws, 2)) and $(length(observed))"
        )
    )
    predictive_sample = Matrix{Float64}(draws)
    all(isfinite, predictive_sample) ||
        throw(ArgumentError("draws must contain only finite values"))
    scale_values = finite_vector(scales, "scales")
    length(scale_values) == length(observed) ||
        throw(
        DimensionMismatch(
            "scales must equal the actual dimension; got " *
                "$(length(scale_values)) and $(length(observed))"
        )
    )
    all(>(0), scale_values) ||
        throw(DomainError(scale_values, "all scales must be positive"))

    center_values = if isnothing(centers)
        zeros(length(observed))
    else
        values = finite_vector(centers, "centers")
        length(values) == length(observed) ||
            throw(
            DimensionMismatch(
                "centers must equal the actual dimension; got " *
                    "$(length(values)) and $(length(observed))"
            )
        )
        values
    end
    standardized_observed =
        (observed .- center_values) ./ scale_values
    standardized_draws =
        (predictive_sample .- reshape(center_values, 1, :)) ./
        reshape(scale_values, 1, :)
    all(isfinite, standardized_observed) &&
        all(isfinite, standardized_draws) ||
        throw(
        DomainError(
            scale_values,
            "centering or scaling produced nonfinite standardized values"
        )
    )
    return standardized_observed, standardized_draws
end

"""
    energy_score(actual, draws; scales)

Compute the energy score for a multivariate empirical predictive
distribution. Rows are coherent draws and columns are components. `scales` is
mandatory because the score is not invariant to the heterogeneous units of
the U.S. target panel; it must be frozen from origin-eligible training data.
"""
function energy_score(
        actual::AbstractVector{<:Real},
        draws::AbstractMatrix{<:Real};
        scales::AbstractVector{<:Real}
    )
    observed, predictive_sample =
        standardized_ensemble(actual, draws, scales)
    draw_count = size(predictive_sample, 1)

    first_term = 0.0
    for draw_index in 1:draw_count
        first_term +=
            norm(view(predictive_sample, draw_index, :) .- observed)
    end
    first_term /= draw_count

    pair_sum = 0.0
    for first_index in 1:draw_count
        for second_index in (first_index + 1):draw_count
            pair_sum += norm(
                view(predictive_sample, first_index, :) .-
                    view(predictive_sample, second_index, :)
            )
        end
    end
    second_term = pair_sum / draw_count^2
    score = first_term - second_term
    return nonnegative_score(
        score,
        "energy score";
        numerical_scale = first_term + second_term
    )
end

"""
    variogram_score(actual, draws; centers, scales, weights, order = 0.5)

Compute the weighted variogram score for a coherent multivariate ensemble.
Component centers, scaling, and the symmetric nonnegative weight matrix are
mandatory and must be frozen from origin-eligible information before
evaluation. Only the strict upper triangle is used.
"""
function variogram_score(
        actual::AbstractVector{<:Real},
        draws::AbstractMatrix{<:Real};
        centers::AbstractVector{<:Real},
        scales::AbstractVector{<:Real},
        weights::AbstractMatrix{<:Real},
        order::Real = 0.5
    )
    observed, predictive_sample =
        standardized_ensemble(actual, draws, scales; centers)
    dimension = length(observed)
    dimension >= 2 ||
        throw(ArgumentError("variogram score requires at least two components"))

    weight_values = Matrix{Float64}(weights)
    size(weight_values) == (dimension, dimension) ||
        throw(
        DimensionMismatch(
            "weights must have size ($dimension, $dimension); got " *
                "$(size(weight_values))"
        )
    )
    all(isfinite, weight_values) ||
        throw(ArgumentError("weights must contain only finite values"))
    all(>=(0), weight_values) ||
        throw(DomainError(weight_values, "weights must be nonnegative"))
    issymmetric(weight_values) ||
        throw(ArgumentError("weights must be symmetric"))
    all(iszero, diag(weight_values)) ||
        throw(ArgumentError("weights must have a zero diagonal"))
    sum(weight_values) > 0 ||
        throw(DomainError(weight_values, "at least one off-diagonal weight must be positive"))

    order_value = finite_scalar(order, "order")
    order_value > 0 ||
        throw(ArgumentError("order must be positive"))

    score = 0.0
    draw_count = size(predictive_sample, 1)
    for first_component in 1:(dimension - 1)
        for second_component in (first_component + 1):dimension
            weight = weight_values[first_component, second_component]
            iszero(weight) && continue
            observed_variogram =
                abs(observed[first_component] - observed[second_component])^order_value
            forecast_variogram = mean(
                abs.(
                    view(predictive_sample, :, first_component) .-
                        view(predictive_sample, :, second_component)
                ) .^ order_value
            )
            component =
                weight * abs2(observed_variogram - forecast_variogram)
            score += finite_result(component, "variogram-score component")
            isfinite(score) ||
                throw(
                DomainError(
                    score,
                    "variogram-score accumulation overflowed"
                )
            )
        end
    end
    draw_count >= 1 || error("unreachable empty predictive sample")
    return nonnegative_score(score, "variogram score")
end

function finite_scalar(value::Real, name::AbstractString)
    result = Float64(value)
    isfinite(result) || throw(ArgumentError("$name must be finite"))
    return result
end

function finite_result(value::Real, name::AbstractString)
    result = Float64(value)
    isfinite(result) ||
        throw(DomainError(result, "$name is not finite"))
    return result
end

function stable_nonnegative_mean(
        values::AbstractVector{<:Real},
        name::AbstractString
    )
    all(value -> isfinite(value) && value >= 0, values) ||
        throw(DomainError(values, "$name requires finite nonnegative values"))
    scale = maximum(values)
    iszero(scale) && return 0.0
    result = scale * mean(values ./ scale)
    return finite_result(result, name)
end

function finite_probability(
        value::Real,
        name::AbstractString;
        open_interval::Bool
    )
    result = finite_scalar(value, name)
    valid = open_interval ? 0 < result < 1 : 0 <= result <= 1
    interval = open_interval ? "strictly between 0 and 1" : "between 0 and 1"
    valid || throw(ArgumentError("$name must be $interval"))
    return result
end

function nonnegative_score(
        value::Real,
        name::AbstractString;
        numerical_scale::Real = value
    )
    score = Float64(value)
    isfinite(score) ||
        throw(DomainError(score, "$name is not finite"))
    scale = Float64(numerical_scale)
    isfinite(scale) && scale >= 0 ||
        throw(DomainError(scale, "$name numerical scale is invalid"))
    tolerance = 100 * eps(Float64) * max(scale, 1.0)
    score >= -tolerance ||
        throw(DomainError(score, "$name is unexpectedly negative"))
    return max(score, 0.0)
end

end
