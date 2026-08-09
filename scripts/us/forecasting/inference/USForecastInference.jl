module USForecastInference

using LinearAlgebra
using Random
using Statistics

export ExternalPluginBlockLength,
    FixedBlockLength,
    HLNDMResult,
    ResolvedBlockLength,
    RomanoWolfResult,
    StationaryBootstrapIndices,
    StudentizedBootstrapResult,
    hln_dm,
    loss_differential,
    resolve_block_length,
    romano_wolf_stepdown,
    stationary_bootstrap_indices,
    studentized_stationary_bootstrap

abstract type AbstractBlockLengthSpec end

const _ARTIFACT_SHA256_PATTERN = r"^artifact-sha256:[0-9a-f]{64}$"

"""
    FixedBlockLength(expected_length)

Declare an expected stationary-bootstrap block length selected before the
analysis. [`resolve_block_length`](@ref) requires the caller to choose whether
the value is used unchanged or visibly bounded below by the largest horizon.
"""
struct FixedBlockLength <: AbstractBlockLengthSpec
    expected_length::Float64

    function FixedBlockLength(expected_length::Real)
        expected_length isa Bool &&
            throw(ArgumentError("expected_length must be real, not Bool"))
        value = Float64(expected_length)
        isfinite(value) && value >= 1 ||
            throw(
            ArgumentError(
                "expected_length must be finite and at least 1"
            )
        )
        return new(value)
    end
end

"""
    ExternalPluginBlockLength(expected_length, method_id, provenance)

Declare a plug-in expected block length computed outside this kernel.
`method_id` is a mandatory audit label and `provenance` must be exactly
`artifact-sha256:` followed by 64 lowercase hexadecimal characters. This
type does not claim to implement or verify the corrected Politis--White
estimator.
"""
struct ExternalPluginBlockLength <: AbstractBlockLengthSpec
    expected_length::Float64
    method_id::String
    provenance::String

    function ExternalPluginBlockLength(
            expected_length::Real,
            method_id::AbstractString,
            provenance::AbstractString
        )
        expected_length isa Bool &&
            throw(ArgumentError("expected_length must be real, not Bool"))
        value = Float64(expected_length)
        isfinite(value) && value >= 1 ||
            throw(
            ArgumentError(
                "expected_length must be finite and at least 1"
            )
        )
        method = strip(String(method_id))
        isempty(method) &&
            throw(ArgumentError("method_id must be nonempty"))
        source = String(provenance)
        source == strip(source) &&
            occursin(_ARTIFACT_SHA256_PATTERN, source) ||
            throw(
            ArgumentError(
                "provenance must match " *
                    "artifact-sha256:<64 lowercase hex>"
            )
        )
        return new(value, method, source)
    end
end

"""
Resolved stationary-bootstrap block-length metadata.

`horizon_floor_policy` is the caller's explicit `:none` or `:max_horizon`
choice. `horizon_bounded` is true only when `:max_horizon` raised the
requested length, so an adjustment is never silent.
"""
struct ResolvedBlockLength
    source::Symbol
    requested::Float64
    horizon_floor_policy::Symbol
    horizon_floor::Union{Nothing, Int}
    effective::Float64
    horizon_bounded::Bool
    method_id::String
    provenance::Union{Nothing, String}
end

"""
Result of a Harvey--Leybourne--Newbold corrected Diebold--Mariano test.

The estimated effect is the mean paired loss differential. Negative values
favor the challenger. The confidence interval uses the corrected standard
error and a Student `t(n - 1)` critical value.
"""
struct HLNDMResult
    n::Int
    horizon::Int
    mean_differential::Float64
    long_run_variance::Float64
    standard_error::Float64
    hln_correction::Float64
    corrected_standard_error::Float64
    statistic::Float64
    p_value::Float64
    confidence_level::Float64
    confidence_lower::Float64
    confidence_upper::Float64
end

"""
Joint stationary-bootstrap index draws.

Each column is one bootstrap replicate. A caller must use the same index
column for every hypothesis to preserve contemporaneous cross-hypothesis
dependence.
"""
struct StationaryBootstrapIndices
    n::Int
    replicates::Int
    seed::UInt64
    block_length::ResolvedBlockLength
    indices::Matrix{Int}
end

"""
Joint studentized stationary-bootstrap result.

`bootstrap_statistics` has one row per replicate and one column per
hypothesis. Every row was generated from one shared origin-index draw.
Marginal p-values and confidence intervals are two-sided and are not
multiplicity-adjusted.
"""
struct StudentizedBootstrapResult
    n::Int
    hypotheses::Int
    replicates::Int
    seed::UInt64
    horizons::Vector{Int}
    block_length::ResolvedBlockLength
    indices::Matrix{Int}
    effects::Vector{Float64}
    corrected_standard_errors::Vector{Float64}
    statistics::Vector{Float64}
    bootstrap_statistics::Matrix{Float64}
    confidence_level::Float64
    marginal_p_values::Vector{Float64}
    confidence_lower::Vector{Float64}
    confidence_upper::Vector{Float64}
end

"""
Romano--Wolf stepdown max-t result.

For `alternative = :less`, larger evidence corresponds to a more negative
loss differential and therefore favors the challenger.
"""
struct RomanoWolfResult
    hypothesis_ids::Vector{String}
    alternative::Symbol
    alpha::Float64
    observed_statistics::Vector{Float64}
    evidence_statistics::Vector{Float64}
    unadjusted_p_values::Vector{Float64}
    adjusted_p_values::Vector{Float64}
    rejected::Vector{Bool}
    stepdown_order::Vector{Int}
end

"""
    loss_differential(challenger_errors, comparator_errors; loss = :squared)

Construct paired per-origin loss differences as
`loss(challenger_error) - loss(comparator_error)`. Negative values favor the
challenger. Supported loss families are `:squared` and `:absolute`.
"""
function loss_differential(
        challenger_errors::AbstractVector{<:Real},
        comparator_errors::AbstractVector{<:Real};
        loss::Symbol = :squared
    )
    length(challenger_errors) == length(comparator_errors) ||
        throw(
        DimensionMismatch(
            "challenger_errors and comparator_errors must have equal length"
        )
    )
    isempty(challenger_errors) &&
        throw(ArgumentError("paired error vectors must be nonempty"))
    loss in (:squared, :absolute) ||
        throw(ArgumentError("loss must be :squared or :absolute"))
    any(value -> value isa Bool, challenger_errors) &&
        throw(
        ArgumentError(
            "challenger_errors must not contain Bool observations"
        )
    )
    any(value -> value isa Bool, comparator_errors) &&
        throw(
        ArgumentError(
            "comparator_errors must not contain Bool observations"
        )
    )

    challenger = Float64.(challenger_errors)
    comparator = Float64.(comparator_errors)
    all(isfinite, challenger) ||
        throw(
        ArgumentError(
            "challenger_errors must contain only finite values"
        )
    )
    all(isfinite, comparator) ||
        throw(
        ArgumentError(
            "comparator_errors must contain only finite values"
        )
    )

    differential = Vector{Float64}(undef, length(challenger))
    for index in eachindex(challenger, comparator)
        challenger_loss = if loss == :squared
            challenger[index]^2
        else
            abs(challenger[index])
        end
        comparator_loss = if loss == :squared
            comparator[index]^2
        else
            abs(comparator[index])
        end
        isfinite(challenger_loss) ||
            throw(
            DomainError(
                challenger_loss,
                "challenger loss overflowed"
            )
        )
        isfinite(comparator_loss) ||
            throw(
            DomainError(
                comparator_loss,
                "comparator loss overflowed"
            )
        )
        value = challenger_loss - comparator_loss
        isfinite(value) ||
            throw(DomainError(value, "paired loss differential overflowed"))
        differential[index] = value
    end
    return differential
end

"""
    hln_dm(differential, horizon; confidence_level = 0.95)

Compute the two-sided HLN-corrected Diebold--Mariano test for a paired loss
differential. The Bartlett HAC estimator uses lags `0:(horizon - 1)` and
weights `1 - lag / horizon`. Invalid, non-finite, too-short, and degenerate
inputs throw.
"""
function hln_dm(
        differential::AbstractVector{<:Real},
        horizon::Integer;
        confidence_level::Real = 0.95
    )
    sample = _finite_vector(
        differential,
        "differential";
        minimum_length = 2
    )
    h = _validate_horizon(horizon, length(sample))
    confidence = _validate_probability(
        confidence_level,
        "confidence_level"
    )
    components = _hln_components(sample, h)
    p_value = _student_t_two_sided_pvalue(
        components.statistic,
        length(sample) - 1
    )
    critical = _student_t_critical(confidence, length(sample) - 1)
    margin = critical * components.corrected_standard_error
    isfinite(margin) ||
        throw(DomainError(margin, "confidence-interval margin is not finite"))
    lower = components.effect - margin
    upper = components.effect + margin
    isfinite(lower) && isfinite(upper) ||
        throw(
        DomainError(
            (lower, upper),
            "confidence-interval endpoints are not finite"
        )
    )

    return HLNDMResult(
        length(sample),
        h,
        components.effect,
        components.long_run_variance,
        components.standard_error,
        components.hln_correction,
        components.corrected_standard_error,
        components.statistic,
        p_value,
        confidence,
        lower,
        upper,
    )
end

"""
    resolve_block_length(spec, horizons, n; horizon_floor_policy)

Resolve a fixed or externally computed plug-in expected block length under a
required caller policy. `:none` uses the requested value unchanged.
`:max_horizon` uses `max(spec.expected_length, maximum(horizons))` and records
whether that explicit policy changed the request. Lengths greater than `n`
fail rather than being silently truncated.
"""
function resolve_block_length(
        spec::AbstractBlockLengthSpec,
        horizons::AbstractVector{<:Integer},
        n::Integer;
        horizon_floor_policy::Symbol
    )
    sample_size = _validate_count(n, "n"; minimum = 2)
    validated_horizons = _validate_horizons(horizons, sample_size)
    policy = _validate_horizon_floor_policy(horizon_floor_policy)
    requested = spec.expected_length
    horizon_floor =
        policy == :max_horizon ? maximum(validated_horizons) : nothing
    effective = if isnothing(horizon_floor)
        requested
    else
        max(requested, Float64(horizon_floor))
    end
    effective <= sample_size ||
        throw(
        ArgumentError(
            "effective block length $effective exceeds sample size " *
                "$sample_size"
        )
    )

    if spec isa FixedBlockLength
        return ResolvedBlockLength(
            :fixed,
            requested,
            policy,
            horizon_floor,
            effective,
            effective != requested,
            "fixed",
            nothing,
        )
    end
    plugin = spec::ExternalPluginBlockLength
    return ResolvedBlockLength(
        :external_plugin,
        requested,
        policy,
        horizon_floor,
        effective,
        effective != requested,
        plugin.method_id,
        plugin.provenance,
    )
end

"""
    stationary_bootstrap_indices(n, horizons;
        block_length,
        horizon_floor_policy,
        seed,
        replicates = 9_999)

Generate circular Politis--Romano stationary-bootstrap indices with restart
probability `1 / effective_block_length`. The seed is mandatory. Each
replicate is a column of the returned matrix.
"""
function stationary_bootstrap_indices(
        n::Integer,
        horizons::AbstractVector{<:Integer};
        block_length::AbstractBlockLengthSpec,
        horizon_floor_policy::Symbol,
        seed::Integer,
        replicates::Integer = 9_999
    )
    sample_size = _validate_count(n, "n"; minimum = 2)
    draws = _validate_count(replicates, "replicates"; minimum = 1)
    rng_seed = _validate_seed(seed)
    resolved = resolve_block_length(
        block_length,
        horizons,
        sample_size;
        horizon_floor_policy,
    )
    indices = Matrix{Int}(undef, sample_size, draws)
    rng = MersenneTwister(rng_seed)
    restart_probability = 1 / resolved.effective

    for replicate in 1:draws
        source_index = rand(rng, 1:sample_size)
        indices[1, replicate] = source_index
        for row in 2:sample_size
            source_index = if rand(rng) < restart_probability
                rand(rng, 1:sample_size)
            elseif source_index == sample_size
                1
            else
                source_index + 1
            end
            indices[row, replicate] = source_index
        end
    end

    return StationaryBootstrapIndices(
        sample_size,
        draws,
        rng_seed,
        resolved,
        indices,
    )
end

"""
    studentized_stationary_bootstrap(differentials, horizons;
        block_length,
        horizon_floor_policy,
        seed,
        replicates = 9_999,
        confidence_level = 0.95)

Apply a joint, null-centered stationary bootstrap to an origin-by-hypothesis
matrix. Each bootstrap replicate uses one shared row-index draw for every
hypothesis. Studentization uses the same horizon-specific Bartlett HAC and
HLN correction as [`hln_dm`](@ref).

The marginal p-values use the conservative `(1 + exceedances) / (B + 1)`
finite-resample convention. Confidence intervals are equal-tailed
studentized intervals. They are marginal, not simultaneous. The primary
design uses 9,999 replicates; this inference API rejects fewer than 999.
"""
function studentized_stationary_bootstrap(
        differentials::AbstractMatrix{<:Real},
        horizons::AbstractVector{<:Integer};
        block_length::AbstractBlockLengthSpec,
        horizon_floor_policy::Symbol,
        seed::Integer,
        replicates::Integer = 9_999,
        confidence_level::Real = 0.95
    )
    any(value -> value isa Bool, differentials) &&
        throw(
        ArgumentError(
            "differentials must not contain Bool observations"
        )
    )
    sample = Matrix{Float64}(differentials)
    n, hypotheses = size(sample)
    n >= 2 ||
        throw(ArgumentError("differentials must have at least 2 rows"))
    hypotheses >= 1 ||
        throw(ArgumentError("differentials must have at least 1 column"))
    all(isfinite, sample) ||
        throw(ArgumentError("differentials must contain only finite values"))
    validated_horizons = _validate_horizons(horizons, n)
    length(validated_horizons) == hypotheses ||
        throw(
        DimensionMismatch(
            "horizons must contain one value per hypothesis; got " *
                "$(length(validated_horizons)) and $hypotheses"
        )
    )
    confidence = _validate_probability(
        confidence_level,
        "confidence_level"
    )
    draws = _validate_count(
        replicates,
        "replicates";
        minimum = 999
    )

    effects = Vector{Float64}(undef, hypotheses)
    corrected_standard_errors = Vector{Float64}(undef, hypotheses)
    statistics = Vector{Float64}(undef, hypotheses)
    centered = Matrix{Float64}(undef, n, hypotheses)
    for hypothesis in 1:hypotheses
        column = view(sample, :, hypothesis)
        components = _hln_components(
            column,
            validated_horizons[hypothesis]
        )
        effects[hypothesis] = components.effect
        corrected_standard_errors[hypothesis] =
            components.corrected_standard_error
        statistics[hypothesis] = components.statistic
        for row in 1:n
            value = sample[row, hypothesis] - components.effect
            isfinite(value) ||
                throw(
                DomainError(
                    value,
                    "null-centering overflowed for hypothesis $hypothesis"
                )
            )
            centered[row, hypothesis] = value
        end
    end

    index_draws = stationary_bootstrap_indices(
        n,
        validated_horizons;
        block_length,
        horizon_floor_policy,
        seed,
        replicates = draws,
    )
    bootstrap_statistics =
        Matrix{Float64}(undef, index_draws.replicates, hypotheses)
    resampled = Matrix{Float64}(undef, n, hypotheses)
    for replicate in 1:index_draws.replicates
        for row in 1:n
            source_row = index_draws.indices[row, replicate]
            for hypothesis in 1:hypotheses
                resampled[row, hypothesis] = centered[source_row, hypothesis]
            end
        end
        for hypothesis in 1:hypotheses
            try
                components = _hln_components(
                    view(resampled, :, hypothesis),
                    validated_horizons[hypothesis]
                )
                bootstrap_statistics[replicate, hypothesis] =
                    components.statistic
            catch error
                error isa Union{
                    ArgumentError,
                    DimensionMismatch,
                    DomainError,
                } || rethrow()
                message = sprint(showerror, error)
                throw(
                    ArgumentError(
                        "bootstrap replicate $replicate, hypothesis " *
                            "$hypothesis failed studentization: $message"
                    )
                )
            end
        end
    end

    alpha = 1 - confidence
    marginal_p_values = Vector{Float64}(undef, hypotheses)
    confidence_lower = Vector{Float64}(undef, hypotheses)
    confidence_upper = Vector{Float64}(undef, hypotheses)
    for hypothesis in 1:hypotheses
        draws = view(bootstrap_statistics, :, hypothesis)
        threshold = abs(statistics[hypothesis])
        exceedances = count(value -> abs(value) >= threshold, draws)
        marginal_p_values[hypothesis] =
            (1 + exceedances) / (index_draws.replicates + 1)
        lower_quantile = quantile(draws, alpha / 2)
        upper_quantile = quantile(draws, 1 - alpha / 2)
        lower =
            effects[hypothesis] -
            upper_quantile * corrected_standard_errors[hypothesis]
        upper =
            effects[hypothesis] -
            lower_quantile * corrected_standard_errors[hypothesis]
        isfinite(lower) && isfinite(upper) ||
            throw(
            DomainError(
                (lower, upper),
                "bootstrap confidence interval is non-finite for " *
                    "hypothesis $hypothesis"
            )
        )
        lower <= upper ||
            throw(
            DomainError(
                (lower, upper),
                "bootstrap confidence interval is reversed for " *
                    "hypothesis $hypothesis"
            )
        )
        confidence_lower[hypothesis] = lower
        confidence_upper[hypothesis] = upper
    end

    return StudentizedBootstrapResult(
        n,
        hypotheses,
        index_draws.replicates,
        index_draws.seed,
        validated_horizons,
        index_draws.block_length,
        index_draws.indices,
        effects,
        corrected_standard_errors,
        statistics,
        bootstrap_statistics,
        confidence,
        marginal_p_values,
        confidence_lower,
        confidence_upper,
    )
end

"""
    romano_wolf_stepdown(result;
        hypothesis_ids = nothing,
        alternative = :two_sided,
        alpha = 0.05)

Apply the Romano--Wolf stepdown max-t procedure to a joint
[`StudentizedBootstrapResult`](@ref). Supported alternatives are
`:two_sided`, `:less`, and `:greater`. `:less` is the directional alternative
that the challenger has lower expected loss. Results with fewer than 999
bootstrap replicates are rejected.
"""
function romano_wolf_stepdown(
        result::StudentizedBootstrapResult;
        hypothesis_ids::Union{Nothing, AbstractVector{<:AbstractString}} =
            nothing,
        alternative::Symbol = :two_sided,
        alpha::Real = 0.05
    )
    _validate_bootstrap_result(result)
    alternative in (:two_sided, :less, :greater) ||
        throw(
        ArgumentError(
            "alternative must be :two_sided, :less, or :greater"
        )
    )
    significance = _validate_probability(alpha, "alpha")
    ids = if isnothing(hypothesis_ids)
        ["hypothesis_$index" for index in 1:result.hypotheses]
    else
        length(hypothesis_ids) == result.hypotheses ||
            throw(
            DimensionMismatch(
                "hypothesis_ids must contain one ID per hypothesis"
            )
        )
        String.(hypothesis_ids)
    end
    all(id -> !isempty(strip(id)), ids) ||
        throw(ArgumentError("hypothesis_ids must be nonempty"))
    length(unique(ids)) == length(ids) ||
        throw(ArgumentError("hypothesis_ids must be unique"))

    evidence = _evidence_transform(result.statistics, alternative)
    bootstrap_evidence = _evidence_transform(
        result.bootstrap_statistics,
        alternative
    )
    order = sortperm(evidence; rev = true, alg = MergeSort)
    adjusted = fill(NaN, result.hypotheses)
    unadjusted = Vector{Float64}(undef, result.hypotheses)
    denominator = result.replicates + 1

    for hypothesis in 1:result.hypotheses
        exceedances = count(
            value -> value >= evidence[hypothesis],
            view(bootstrap_evidence, :, hypothesis),
        )
        unadjusted[hypothesis] = (1 + exceedances) / denominator
    end

    running_adjusted = 0.0
    for step in eachindex(order)
        hypothesis = order[step]
        remaining = view(order, step:length(order))
        exceedances = 0
        for replicate in 1:result.replicates
            maximum_statistic = maximum(
                view(bootstrap_evidence, replicate, remaining)
            )
            exceedances += maximum_statistic >= evidence[hypothesis]
        end
        raw_adjusted = (1 + exceedances) / denominator
        running_adjusted = max(running_adjusted, raw_adjusted)
        adjusted[hypothesis] = running_adjusted
    end
    all(isfinite, adjusted) ||
        throw(
        DomainError(
            adjusted,
            "Romano--Wolf adjusted p-values are not finite"
        )
    )

    return RomanoWolfResult(
        ids,
        alternative,
        significance,
        copy(result.statistics),
        evidence,
        unadjusted,
        adjusted,
        adjusted .<= significance,
        order,
    )
end

function _validate_bootstrap_result(result::StudentizedBootstrapResult)
    result.n >= 2 ||
        throw(ArgumentError("bootstrap result n must be at least 2"))
    result.hypotheses >= 1 ||
        throw(
        ArgumentError(
            "bootstrap result must contain at least 1 hypothesis"
        )
    )
    result.replicates >= 999 ||
        throw(
        ArgumentError(
            "bootstrap inference requires at least 999 replicates"
        )
    )
    horizons = _validate_horizons(result.horizons, result.n)
    length(horizons) == result.hypotheses ||
        throw(
        DimensionMismatch(
            "bootstrap result horizon count does not match hypotheses"
        )
    )
    size(result.indices) == (result.n, result.replicates) ||
        throw(
        DimensionMismatch(
            "bootstrap result index dimensions are inconsistent"
        )
    )
    all(index -> 1 <= index <= result.n, result.indices) ||
        throw(ArgumentError("bootstrap result contains an invalid row index"))
    size(result.bootstrap_statistics) ==
        (result.replicates, result.hypotheses) ||
        throw(
        DimensionMismatch(
            "bootstrap statistic dimensions are inconsistent"
        )
    )
    all(isfinite, result.bootstrap_statistics) ||
        throw(
        ArgumentError(
            "bootstrap statistics must contain only finite values"
        )
    )

    vector_fields = (
        result.effects,
        result.corrected_standard_errors,
        result.statistics,
        result.marginal_p_values,
        result.confidence_lower,
        result.confidence_upper,
    )
    all(length(values) == result.hypotheses for values in vector_fields) ||
        throw(
        DimensionMismatch(
            "bootstrap result vector lengths are inconsistent"
        )
    )
    all(all(isfinite, values) for values in vector_fields) ||
        throw(
        ArgumentError(
            "bootstrap result vectors must contain only finite values"
        )
    )
    all(result.corrected_standard_errors .> 0) ||
        throw(
        DomainError(
            result.corrected_standard_errors,
            "bootstrap standard errors must be positive"
        )
    )
    all(value -> 0 <= value <= 1, result.marginal_p_values) ||
        throw(
        DomainError(
            result.marginal_p_values,
            "bootstrap marginal p-values must be in [0, 1]"
        )
    )
    all(result.confidence_lower .<= result.confidence_upper) ||
        throw(
        DomainError(
            (result.confidence_lower, result.confidence_upper),
            "bootstrap confidence intervals are reversed"
        )
    )
    _validate_probability(result.confidence_level, "confidence_level")
    block_length = result.block_length
    if block_length.source == :fixed
        block_length.method_id == "fixed" ||
            throw(
            ArgumentError(
                "fixed block-length metadata must use method_id fixed"
            )
        )
        isnothing(block_length.provenance) ||
            throw(
            ArgumentError(
                "fixed block-length metadata must not have provenance"
            )
        )
    elseif block_length.source == :external_plugin
        method_id = block_length.method_id
        method_id == strip(method_id) && !isempty(method_id) ||
            throw(
            ArgumentError(
                "external plug-in block-length method_id must be " *
                    "nonempty and trimmed"
            )
        )
        provenance = block_length.provenance
        provenance isa String &&
            provenance == strip(provenance) &&
            occursin(_ARTIFACT_SHA256_PATTERN, provenance) ||
            throw(
            ArgumentError(
                "external plug-in block-length provenance must match " *
                    "artifact-sha256:<64 lowercase hex>"
            )
        )
    else
        throw(
            ArgumentError(
                "bootstrap result block-length source must be " *
                    ":fixed or :external_plugin"
            )
        )
    end
    policy = _validate_horizon_floor_policy(
        block_length.horizon_floor_policy
    )
    requested = block_length.requested
    isfinite(requested) && requested >= 1 ||
        throw(
        DomainError(
            requested,
            "bootstrap requested block length must be finite and at least 1"
        )
    )
    expected_floor =
        policy == :max_horizon ? maximum(horizons) : nothing
    block_length.horizon_floor == expected_floor ||
        throw(
        ArgumentError(
            "bootstrap result horizon-floor metadata is inconsistent"
        )
    )
    expected_effective = if isnothing(expected_floor)
        requested
    else
        max(requested, Float64(expected_floor))
    end
    block_length.effective == expected_effective ||
        throw(
        ArgumentError(
            "bootstrap result effective block length is inconsistent"
        )
    )
    expected_bounded = expected_effective != requested
    block_length.horizon_bounded == expected_bounded ||
        throw(
        ArgumentError(
            "bootstrap result horizon-bound flag is inconsistent"
        )
    )
    block_length.effective <= result.n ||
        throw(
        ArgumentError(
            "bootstrap result block length exceeds the sample size"
        )
    )
    implied_statistics =
        result.effects ./ result.corrected_standard_errors
    all(
        isapprox.(
            implied_statistics,
            result.statistics;
            rtol = 32eps(Float64),
            atol = 0.0,
        ),
    ) ||
        throw(
        ArgumentError(
            "bootstrap observed statistics are inconsistent with " *
                "effects and standard errors"
        )
    )
    return nothing
end

function _finite_vector(
        values::AbstractVector{<:Real},
        name::AbstractString;
        minimum_length::Integer
    )
    length(values) >= minimum_length ||
        throw(
        ArgumentError(
            "$name must contain at least $minimum_length observations"
        )
    )
    any(value -> value isa Bool, values) &&
        throw(
        ArgumentError(
            "$name must not contain Bool observations"
        )
    )
    sample = Float64.(values)
    all(isfinite, sample) ||
        throw(ArgumentError("$name must contain only finite values"))
    return sample
end

function _validate_count(
        value::Integer,
        name::AbstractString;
        minimum::Integer
    )
    value isa Bool &&
        throw(ArgumentError("$name must be an integer, not Bool"))
    value >= minimum ||
        throw(ArgumentError("$name must be at least $minimum"))
    value <= typemax(Int) ||
        throw(ArgumentError("$name exceeds typemax(Int)"))
    return Int(value)
end

function _validate_horizon(horizon::Integer, n::Integer)
    horizon isa Bool &&
        throw(ArgumentError("forecast horizon must be an integer, not Bool"))
    horizon >= 1 ||
        throw(ArgumentError("forecast horizon must be at least 1"))
    horizon < n ||
        throw(
        ArgumentError(
            "forecast horizon must be smaller than sample size $n"
        )
    )
    return Int(horizon)
end

function _validate_horizons(
        horizons::AbstractVector{<:Integer},
        n::Integer
    )
    isempty(horizons) &&
        throw(ArgumentError("horizons must be nonempty"))
    return [_validate_horizon(horizon, n) for horizon in horizons]
end

function _validate_horizon_floor_policy(policy::Symbol)
    policy in (:none, :max_horizon) ||
        throw(
        ArgumentError(
            "horizon_floor_policy must be :none or :max_horizon"
        )
    )
    return policy
end

function _validate_probability(value::Real, name::AbstractString)
    value isa Bool &&
        throw(ArgumentError("$name must be real, not Bool"))
    probability = Float64(value)
    isfinite(probability) && 0 < probability < 1 ||
        throw(ArgumentError("$name must be finite and strictly between 0 and 1"))
    return probability
end

function _validate_seed(seed::Integer)
    seed isa Bool &&
        throw(ArgumentError("seed must be an integer, not Bool"))
    0 <= seed <= typemax(UInt64) ||
        throw(
        ArgumentError(
            "seed must be between 0 and typemax(UInt64), inclusive"
        )
    )
    return UInt64(seed)
end

function _hln_components(
        sample::AbstractVector{<:Real},
        horizon::Integer
    )
    n = length(sample)
    h = _validate_horizon(horizon, n)
    effect = mean(sample)
    isfinite(effect) ||
        throw(DomainError(effect, "mean loss differential is not finite"))
    long_run_variance = _bartlett_long_run_variance(sample, h - 1)
    standard_error = sqrt(long_run_variance / n)
    isfinite(standard_error) && standard_error > 0 ||
        throw(
        DomainError(
            standard_error,
            "HAC standard error is nonpositive or non-finite"
        )
    )
    correction_squared =
        (n + 1 - 2h + h * (h - 1) / n) / n
    isfinite(correction_squared) && correction_squared > 0 ||
        throw(
        DomainError(
            correction_squared,
            "HLN correction is nonpositive or non-finite"
        )
    )
    correction = sqrt(correction_squared)
    corrected_standard_error = standard_error / correction
    isfinite(corrected_standard_error) && corrected_standard_error > 0 ||
        throw(
        DomainError(
            corrected_standard_error,
            "HLN-corrected standard error is invalid"
        )
    )
    statistic = effect / corrected_standard_error
    isfinite(statistic) ||
        throw(DomainError(statistic, "HLN-DM statistic is not finite"))
    return (
        effect,
        long_run_variance,
        standard_error,
        hln_correction = correction,
        corrected_standard_error,
        statistic,
    )
end

function _bartlett_long_run_variance(
        values::AbstractVector{<:Real},
        maxlag::Integer
    )
    n = length(values)
    0 <= maxlag < n ||
        throw(
        ArgumentError(
            "HAC lag must be nonnegative and smaller than sample size"
        )
    )
    center = mean(values)
    isfinite(center) ||
        throw(DomainError(center, "HAC centering mean is not finite"))
    centered = Vector{Float64}(undef, n)
    for index in eachindex(values)
        value = Float64(values[index]) - center
        isfinite(value) ||
            throw(DomainError(value, "HAC centering overflowed"))
        centered[index] = value
    end

    gamma_zero = dot(centered, centered) / n
    isfinite(gamma_zero) ||
        throw(DomainError(gamma_zero, "lag-zero covariance is not finite"))
    estimate = gamma_zero
    absolute_scale = abs(gamma_zero)
    for lag in 1:maxlag
        autocovariance =
            dot(
            view(centered, (lag + 1):n),
            view(centered, 1:(n - lag)),
        ) / n
        isfinite(autocovariance) ||
            throw(
            DomainError(
                autocovariance,
                "HAC autocovariance at lag $lag is not finite"
            )
        )
        weight = 1 - lag / (maxlag + 1)
        contribution = 2 * weight * autocovariance
        estimate += contribution
        absolute_scale += abs(contribution)
    end
    isfinite(estimate) ||
        throw(DomainError(estimate, "HAC long-run variance is not finite"))
    tolerance = 100 * eps(Float64) * absolute_scale
    estimate > tolerance ||
        throw(
        DomainError(
            estimate,
            "HAC long-run variance is nonpositive or numerically " *
                "degenerate"
        )
    )
    return estimate
end

function _evidence_transform(
        statistics::AbstractArray{<:Real},
        alternative::Symbol
    )
    if alternative == :two_sided
        return abs.(statistics)
    elseif alternative == :less
        return .-statistics
    end
    return Float64.(statistics)
end

const _LANCZOS_COEFFICIENTS = (
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
)

function _loggamma_positive(value::Float64)
    value > 0 ||
        throw(ArgumentError("log-gamma input must be positive"))
    shifted = value - 1
    accumulator = 0.99999999999980993
    for (index, coefficient) in enumerate(_LANCZOS_COEFFICIENTS)
        accumulator += coefficient / (shifted + index)
    end
    scale = shifted + 7.5
    return (
        0.5 * log(2pi) +
            (shifted + 0.5) * log(scale) - scale + log(accumulator)
    )
end

function _beta_continued_fraction(
        first_shape::Float64,
        second_shape::Float64,
        probability::Float64
    )
    maximum_iterations = 300
    tolerance = 8eps(Float64)
    floor_value = floatmin(Float64) / eps(Float64)
    combined = first_shape + second_shape
    numerator_offset = first_shape + 1
    denominator_offset = first_shape - 1
    c_term = 1.0
    d_term = 1 - combined * probability / numerator_offset
    abs(d_term) < floor_value && (d_term = floor_value)
    d_term = inv(d_term)
    result = d_term

    for iteration in 1:maximum_iterations
        even = 2iteration
        coefficient =
            iteration * (second_shape - iteration) * probability /
            ((denominator_offset + even) * (first_shape + even))
        d_term = 1 + coefficient * d_term
        abs(d_term) < floor_value && (d_term = floor_value)
        c_term = 1 + coefficient / c_term
        abs(c_term) < floor_value && (c_term = floor_value)
        d_term = inv(d_term)
        result *= d_term * c_term

        coefficient =
            -(first_shape + iteration) *
            (combined + iteration) * probability /
            ((first_shape + even) * (numerator_offset + even))
        d_term = 1 + coefficient * d_term
        abs(d_term) < floor_value && (d_term = floor_value)
        c_term = 1 + coefficient / c_term
        abs(c_term) < floor_value && (c_term = floor_value)
        d_term = inv(d_term)
        change = d_term * c_term
        result *= change
        abs(change - 1) <= tolerance && return result
    end
    throw(ErrorException("incomplete-beta continued fraction did not converge"))
end

function _regularized_incomplete_beta(
        probability::Float64,
        first_shape::Float64,
        second_shape::Float64
    )
    0 <= probability <= 1 ||
        throw(ArgumentError("beta probability must be in [0, 1]"))
    first_shape > 0 && second_shape > 0 ||
        throw(ArgumentError("beta shapes must be positive"))
    probability == 0 && return 0.0
    probability == 1 && return 1.0
    log_front =
        _loggamma_positive(first_shape + second_shape) -
        _loggamma_positive(first_shape) -
        _loggamma_positive(second_shape) +
        first_shape * log(probability) +
        second_shape * log1p(-probability)
    front = exp(log_front)

    result = if probability <
            (first_shape + 1) / (first_shape + second_shape + 2)
        front *
            _beta_continued_fraction(
            first_shape,
            second_shape,
            probability,
        ) / first_shape
    else
        1 -
            front *
            _beta_continued_fraction(
            second_shape,
            first_shape,
            1 - probability,
        ) / second_shape
    end
    isfinite(result) ||
        throw(DomainError(result, "regularized incomplete beta is not finite"))
    return clamp(result, 0.0, 1.0)
end

function _student_t_two_sided_pvalue(statistic::Real, degrees_freedom::Integer)
    degrees_freedom >= 1 ||
        throw(ArgumentError("degrees_freedom must be at least 1"))
    value = abs(Float64(statistic))
    isfinite(value) ||
        throw(ArgumentError("statistic must be finite"))
    value == 0 && return 1.0
    squared = value^2
    beta_probability = if isfinite(squared)
        degrees_freedom / (degrees_freedom + squared)
    else
        0.0
    end
    return _regularized_incomplete_beta(
        beta_probability,
        degrees_freedom / 2,
        0.5,
    )
end

function _student_t_critical(
        confidence_level::Float64,
        degrees_freedom::Integer
    )
    tail_probability = 1 - confidence_level
    lower = 0.0
    upper = 1.0
    while _student_t_two_sided_pvalue(upper, degrees_freedom) >
            tail_probability
        upper *= 2
        isfinite(upper) ||
            throw(
            ErrorException(
                "failed to bracket Student-t critical value"
            )
        )
    end
    for _ in 1:100
        midpoint = (lower + upper) / 2
        if _student_t_two_sided_pvalue(midpoint, degrees_freedom) >
                tail_probability
            lower = midpoint
        else
            upper = midpoint
        end
    end
    critical = (lower + upper) / 2
    isfinite(critical) && critical > 0 ||
        throw(DomainError(critical, "Student-t critical value is invalid"))
    return critical
end

end
