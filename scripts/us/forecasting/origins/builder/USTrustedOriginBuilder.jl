if !isdefined(@__MODULE__, :USForecastBenchmarks)
    include(joinpath(@__DIR__, "..", "..", "benchmarks", "USForecastBenchmarks.jl"))
end
if !isdefined(@__MODULE__, :USOriginDataReceipt)
    include(joinpath(@__DIR__, "..", "..", "runner", "USOriginDataReceipt.jl"))
end

module USTrustedOriginBuilder

    using Dates
    using SHA

    using ..USForecastBenchmarks: OriginData
    using ..USOriginDataReceipt: origin_data_sha256

    export BuilderSourceArtifact,
        BuiltOriginData,
        CellDerivation,
        SourceObservation,
        TransformationReceipt,
        TrustedOriginBuilderError,
        build_synthetic_origin_data,
        derivation_receipt_sha256,
        validate_built_origin_data

    const SCHEMA_VERSION = "beforeit-us-origin-derivation-receipt.v1"
    const CANONICALIZATION = "typed-length-prefixed-big-endian.v1"
    const DIGEST_ALGORITHM = "sha256"
    const EVIDENCE_CLASS = "synthetic_fixture_only"
    const EMPIRICAL_EXECUTION_AUTHORIZED = false
    const PRODUCTION_ADMISSION_AUTHORIZED = false
    const DERIVATION_DOMAIN = "beforeit-us-origin-derivation-receipt-self-hash.v1"
    const ZERO_HASH = repeat("0", 64)
    const SUPPORTED_OPERATORS = (
        ("identity", "v1"),
        ("weighted_sum", "v1"),
    )
    const SIGNED_KEY_TYPES = (Int8, Int16, Int32, Int64, Int128)
    const UNSIGNED_KEY_TYPES = (UInt8, UInt16, UInt32, UInt64, UInt128)
    const SUPPORTED_KEY_TYPES = (String, Date, DateTime, SIGNED_KEY_TYPES..., UNSIGNED_KEY_TYPES...)
    const UNSIGNED_TYPE = Dict{DataType, DataType}(
        Int8 => UInt8,
        Int16 => UInt16,
        Int32 => UInt32,
        Int64 => UInt64,
        Int128 => UInt128,
        UInt8 => UInt8,
        UInt16 => UInt16,
        UInt32 => UInt32,
        UInt64 => UInt64,
        UInt128 => UInt128,
    )

    struct TrustedOriginBuilderError <: Exception
        message::String
    end

    Base.showerror(io::IO, error::TrustedOriginBuilderError) = print(io, error.message)
    fail(location, message) = throw(TrustedOriginBuilderError("$location: $message"))

    function expect_string(value, location)
        typeof(value) === String || fail(location, "must be an exact String")
        value == strip(value) || fail(location, "has surrounding whitespace")
        isempty(value) && fail(location, "must not be empty")
        return value
    end

    function expect_identifier(value, location)
        text = expect_string(value, location)
        occursin(r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$", text) ||
            fail(location, "contains unsupported characters")
        return text
    end

    function expect_hash(value, location)
        text = expect_string(value, location)
        occursin(r"^[0-9a-f]{64}$", text) ||
            fail(location, "must be 64 lowercase hexadecimal characters")
        text == ZERO_HASH && fail(location, "must not be the all-zero placeholder hash")
        return text
    end

    function expect_key(value, location)
        typeof(value) in SUPPORTED_KEY_TYPES || fail(location, "has unsupported key type $(typeof(value))")
        return value
    end

    function copy_key_vector(value, key_type, location)
        typeof(value) === Vector{key_type} || fail(location, "must be an exact Vector{$key_type}")
        result = copy(value)
        isempty(result) && fail(location, "must not be empty")
        for index in 2:length(result)
            isless(result[index - 1], result[index]) || fail(location, "must be strictly increasing")
        end
        return result
    end

    function expect_exact_string_vector(value, location)
        typeof(value) === Vector{String} || fail(location, "must be an exact Vector{String}")
        result = String[]
        for (index, item) in enumerate(value)
            push!(result, expect_identifier(item, "$location[$index]"))
        end
        allunique(result) || fail(location, "must not contain duplicates")
        return result
    end

    function expect_float_vector(value, location)
        typeof(value) === Vector{Float64} || fail(location, "must be an exact Vector{Float64}")
        all(isfinite, value) || fail(location, "must contain only finite Float64 values")
        return copy(value)
    end

    """One immutable raw artifact identity available to a derivation."""
    struct BuilderSourceArtifact
        artifact_id::String
        sha256::String

        function BuilderSourceArtifact(artifact_id, sha256)
            return new(
                expect_identifier(artifact_id, "source_artifact.artifact_id"),
                expect_hash(sha256, "source_artifact.sha256"),
            )
        end
    end

    BuilderSourceArtifact(; artifact_id, sha256) = BuilderSourceArtifact(artifact_id, sha256)

    """
    One source value with its artifact, observation, period, and vintage identity.
    The value is a synthetic fixture value in v1; no acquisition claim is made.
    """
    struct SourceObservation{K}
        observation_id::String
        artifact_id::String
        artifact_sha256::String
        source_series_id::String
        period_key::K
        vintage_id::String
        value::Float64

        function SourceObservation(
                observation_id,
                artifact_id,
                artifact_sha256,
                source_series_id,
                period_key,
                vintage_id,
                value,
            )
            typeof(value) === Float64 || fail("source_observation.value", "must be an exact Float64")
            isfinite(value) || fail("source_observation.value", "must be finite")
            return new{typeof(expect_key(period_key, "source_observation.period_key"))}(
                expect_identifier(observation_id, "source_observation.observation_id"),
                expect_identifier(artifact_id, "source_observation.artifact_id"),
                expect_hash(artifact_sha256, "source_observation.artifact_sha256"),
                expect_identifier(source_series_id, "source_observation.source_series_id"),
                period_key,
                expect_identifier(vintage_id, "source_observation.vintage_id"),
                Float64(value),
            )
        end
    end

    SourceObservation(; observation_id, artifact_id, artifact_sha256, source_series_id, period_key, vintage_id, value) =
        SourceObservation(observation_id, artifact_id, artifact_sha256, source_series_id, period_key, vintage_id, value)

    """
    The complete derivation claim for one output cell. `input_observation_ids` is an
    ordered edge list. `operator_parameters` is empty for identity and is
    `[coefficient_1, ..., coefficient_n, intercept]` for weighted_sum.
    """
    struct CellDerivation{K}
        output_slot::String
        output_key::K
        output_name::String
        output_value::Float64
        transformation_id::String
        transformation_version::String
        operator_id::String
        operator_version::String
        input_observation_ids::Vector{String}
        operator_parameters::Vector{Float64}

        function CellDerivation(
                output_slot,
                output_key,
                output_name,
                output_value,
                transformation_id,
                transformation_version,
                operator_id,
                operator_version,
                input_observation_ids,
                operator_parameters,
            )
            typeof(output_value) === Float64 || fail("cell_derivation.output_value", "must be an exact Float64")
            slot = expect_identifier(output_slot, "cell_derivation.output_slot")
            slot in ("y_train", "x_train", "x_future") ||
                fail("cell_derivation.output_slot", "must be y_train, x_train, or x_future")
            isfinite(output_value) || fail("cell_derivation.output_value", "must be finite")
            typeof(input_observation_ids) === Vector{String} ||
                fail("cell_derivation.input_observation_ids", "must be an exact Vector{String}")
            inputs = [
                expect_identifier(item, "cell_derivation.input_observation_ids[$index]") for
                    (index, item) in enumerate(input_observation_ids)
            ]
            isempty(inputs) && fail("cell_derivation.input_observation_ids", "must not be empty")
            allunique(inputs) || fail("cell_derivation.input_observation_ids", "must not contain duplicates")
            return new{typeof(expect_key(output_key, "cell_derivation.output_key"))}(
                slot,
                output_key,
                expect_identifier(output_name, "cell_derivation.output_name"),
                Float64(output_value),
                expect_identifier(transformation_id, "cell_derivation.transformation_id"),
                expect_identifier(transformation_version, "cell_derivation.transformation_version"),
                expect_identifier(operator_id, "cell_derivation.operator_id"),
                expect_identifier(operator_version, "cell_derivation.operator_version"),
                inputs,
                expect_float_vector(operator_parameters, "cell_derivation.operator_parameters"),
            )
        end
    end

    CellDerivation(; output_slot, output_key, output_name, output_value, transformation_id, transformation_version, operator_id, operator_version, input_observation_ids, operator_parameters) =
        CellDerivation(output_slot, output_key, output_name, output_value, transformation_id, transformation_version, operator_id, operator_version, input_observation_ids, operator_parameters)

    """Self-hashed, synthetic-only source-to-cell derivation receipt."""
    struct TransformationReceipt{K}
        schema_version::String
        canonicalization::String
        digest_algorithm::String
        evidence_class::String
        empirical_execution_authorized::Bool
        production_admission_authorized::Bool
        source_artifacts::Vector{BuilderSourceArtifact}
        source_observations::Vector{SourceObservation{K}}
        cell_derivations::Vector{CellDerivation{K}}
        sample_sha256::String
        receipt_sha256::String
    end

    """Owned `OriginData` plus the source-to-cell derivation receipt."""
    struct BuiltOriginData{K}
        sample::OriginData{K}
        receipt::TransformationReceipt{K}
    end

    function validate_artifacts(value)
        value isa Union{Vector, Tuple} || fail("source_artifacts", "must be a vector or tuple")
        artifacts = BuilderSourceArtifact[]
        for (index, artifact) in enumerate(value)
            artifact isa BuilderSourceArtifact || fail("source_artifacts[$index]", "must be a BuilderSourceArtifact")
            push!(artifacts, BuilderSourceArtifact(artifact.artifact_id, artifact.sha256))
        end
        isempty(artifacts) && fail("source_artifacts", "must not be empty")
        allunique(item -> item.artifact_id, artifacts) || fail("source_artifacts", "has duplicate artifact IDs")
        allunique(item -> item.sha256, artifacts) || fail("source_artifacts", "has hash aliases")
        sort!(artifacts; by = item -> (item.artifact_id, item.sha256))
        return artifacts
    end

    function validate_observations(value, key_type, artifacts)
        value isa Union{Vector, Tuple} || fail("source_observations", "must be a vector or tuple")
        observations = SourceObservation{key_type}[]
        artifact_map = Dict(item.artifact_id => item.sha256 for item in artifacts)
        for (index, observation) in enumerate(value)
            observation isa SourceObservation{key_type} ||
                fail("source_observations[$index]", "must have the same key type as origin_key")
            get(artifact_map, observation.artifact_id, nothing) == observation.artifact_sha256 ||
                fail("source_observations[$index]", "does not bind to exactly one supplied source artifact")
            push!(
                observations, SourceObservation(
                    observation.observation_id, observation.artifact_id, observation.artifact_sha256,
                    observation.source_series_id, observation.period_key, observation.vintage_id, observation.value,
                )
            )
        end
        isempty(observations) && fail("source_observations", "must not be empty")
        allunique(item -> item.observation_id, observations) || fail("source_observations", "has duplicate observation IDs")
        allunique(item -> (item.artifact_id, item.source_series_id, item.period_key, item.vintage_id), observations) ||
            fail("source_observations", "has duplicate artifact/series/period/vintage identities")
        used_artifacts = Set(item.artifact_id for item in observations)
        used_artifacts == Set(item.artifact_id for item in artifacts) ||
            fail("source_artifacts", "contains an artifact with no source observations")
        sort!(observations; by = item -> item.observation_id)
        return observations
    end

    function expected_cell_vector(training_keys, forecast_keys, target_names, predictor_names)
        expected = Tuple{String, Any, String}[]
        for key in training_keys, name in target_names
            push!(expected, ("y_train", key, name))
        end
        for key in training_keys, name in predictor_names
            push!(expected, ("x_train", key, name))
        end
        for key in forecast_keys, name in predictor_names
            push!(expected, ("x_future", key, name))
        end
        return expected
    end

    expected_cell_set(args...) = Set(expected_cell_vector(args...))

    function operator_value(derivation, observation_map, location)
        input_values = Float64[]
        for observation_id in derivation.input_observation_ids
            observation = get(observation_map, observation_id, nothing)
            observation === nothing && fail(location, "references unknown source observation $observation_id")
            !isless(derivation.output_key, observation.period_key) ||
                fail(location, "uses a source period later than its output cell")
            push!(input_values, observation.value)
        end
        operator = (derivation.operator_id, derivation.operator_version)
        operator in SUPPORTED_OPERATORS || fail(location, "uses unsupported or ambiguous operator $(operator)")
        if operator == ("identity", "v1")
            length(input_values) == 1 || fail(location, "identity.v1 requires exactly one input")
            isempty(derivation.operator_parameters) || fail(location, "identity.v1 requires no parameters")
            return input_values[1]
        end
        length(derivation.operator_parameters) == length(input_values) + 1 ||
            fail(location, "weighted_sum.v1 requires one coefficient per input plus an intercept")
        value = derivation.operator_parameters[end]
        for index in eachindex(input_values)
            value += derivation.operator_parameters[index] * input_values[index]
        end
        isfinite(value) || fail(location, "operator result is nonfinite")
        return value
    end

    function validate_derivations(value, key_type, expected_cells, observations)
        value isa Union{Vector, Tuple} || fail("cell_derivations", "must be a vector or tuple")
        derivations = CellDerivation{key_type}[]
        observation_map = Dict(item.observation_id => item for item in observations)
        actual_cells = Set{Tuple{String, Any, String}}()
        used_observation_ids = Set{String}()
        length(value) == length(expected_cells) ||
            fail("cell_derivations", "must cover every output cell exactly once")
        for (index, derivation) in enumerate(value)
            derivation isa CellDerivation{key_type} ||
                fail("cell_derivations[$index]", "must have the same key type as origin_key")
            cell = (derivation.output_slot, derivation.output_key, derivation.output_name)
            cell in expected_cells || fail("cell_derivations[$index]", "targets an absent output cell")
            cell == expected_cells[index] ||
                fail("cell_derivations[$index]", "is not in canonical output-cell order")
            cell in actual_cells && fail("cell_derivations[$index]", "duplicates output cell $(cell)")
            computed_value = operator_value(derivation, observation_map, "cell_derivations[$index]")
            reinterpret(UInt64, computed_value) == reinterpret(UInt64, derivation.output_value) ||
                fail("cell_derivations[$index]", "declared output_value does not exactly equal operator result")
            push!(actual_cells, cell)
            union!(used_observation_ids, derivation.input_observation_ids)
            push!(
                derivations, CellDerivation(
                    derivation.output_slot, derivation.output_key, derivation.output_name, derivation.output_value,
                    derivation.transformation_id, derivation.transformation_version,
                    derivation.operator_id, derivation.operator_version,
                    derivation.input_observation_ids, derivation.operator_parameters,
                )
            )
        end
        actual_cells == Set(expected_cells) || fail("cell_derivations", "must cover every output cell exactly once")
        expected_ids = Set(item.observation_id for item in observations)
        used_observation_ids == expected_ids || fail("cell_derivations", "contains unused source observations")
        return derivations
    end

    function build_matrices(training_keys, forecast_keys, target_names, predictor_names, derivations)
        y_train = Matrix{Float64}(undef, length(training_keys), length(target_names))
        x_train = isempty(predictor_names) ? nothing : Matrix{Float64}(undef, length(training_keys), length(predictor_names))
        x_future = isempty(predictor_names) ? nothing : Matrix{Float64}(undef, length(forecast_keys), length(predictor_names))
        train_index = Dict(key => index for (index, key) in enumerate(training_keys))
        future_index = Dict(key => index for (index, key) in enumerate(forecast_keys))
        target_index = Dict(name => index for (index, name) in enumerate(target_names))
        predictor_index = Dict(name => index for (index, name) in enumerate(predictor_names))
        for derivation in derivations
            if derivation.output_slot == "y_train"
                y_train[train_index[derivation.output_key], target_index[derivation.output_name]] = derivation.output_value
            elseif derivation.output_slot == "x_train"
                x_train[train_index[derivation.output_key], predictor_index[derivation.output_name]] = derivation.output_value
            else
                x_future[future_index[derivation.output_key], predictor_index[derivation.output_name]] = derivation.output_value
            end
        end
        return y_train, x_train, x_future
    end

    function write_unsigned_be(io, value::T) where {T <: Unsigned}
        for byte_index in (sizeof(T) - 1):-1:0
            write(io, UInt8((value >> (8 * byte_index)) & T(0xff)))
        end
        return io
    end

    function append_frame!(io, tag::String, payload::Vector{UInt8})
        tag_bytes = collect(codeunits(tag))
        length(tag_bytes) <= typemax(UInt32) || fail("canonicalization.tag", "is too long")
        write_unsigned_be(io, UInt32(length(tag_bytes)))
        write(io, tag_bytes)
        write_unsigned_be(io, UInt64(length(payload)))
        write(io, payload)
        return io
    end

    function frame(tag, payload = UInt8[])
        io = IOBuffer()
        append_frame!(io, tag, payload)
        return take!(io)
    end

    function string_bytes(value)
        return frame("String", collect(codeunits(value)))
    end

    function bool_bytes(value)
        return frame("Bool", UInt8[value ? 0x01 : 0x00])
    end

    function key_bytes(value)
        key_type = typeof(value)
        key_type === String && return string_bytes(value)
        if key_type === Date
            io = IOBuffer(); write_unsigned_be(io, reinterpret(UInt64, Dates.value(value))); return frame("Date/days", take!(io))
        elseif key_type === DateTime
            io = IOBuffer(); write_unsigned_be(io, reinterpret(UInt64, Dates.value(value))); return frame("DateTime/milliseconds", take!(io))
        end
        unsigned_type = UNSIGNED_TYPE[key_type]
        unsigned_value = key_type <: Signed ? reinterpret(unsigned_type, value) : value
        io = IOBuffer(); write_unsigned_be(io, unsigned_value); return frame(string(key_type), take!(io))
    end

    function vector_bytes(tag, values, item_bytes)
        io = IOBuffer(); write_unsigned_be(io, UInt64(length(values)))
        for value in values
            write(io, item_bytes(value))
        end
        return frame(tag, take!(io))
    end

    function float_bytes(value)
        io = IOBuffer(); write_unsigned_be(io, reinterpret(UInt64, value)); return frame("Float64", take!(io))
    end

    function record_bytes(tag, fields)
        io = IOBuffer()
        for (name, encoded) in fields
            append_frame!(io, "field:$name", encoded)
        end
        return frame(tag, take!(io))
    end

    artifact_bytes(item) = record_bytes("BuilderSourceArtifact", ["artifact_id" => string_bytes(item.artifact_id), "sha256" => string_bytes(item.sha256)])
    observation_bytes(item) = record_bytes(
        "SourceObservation", [
            "observation_id" => string_bytes(item.observation_id), "artifact_id" => string_bytes(item.artifact_id),
            "artifact_sha256" => string_bytes(item.artifact_sha256), "source_series_id" => string_bytes(item.source_series_id),
            "period_key" => key_bytes(item.period_key), "vintage_id" => string_bytes(item.vintage_id), "value" => float_bytes(item.value),
        ]
    )
    derivation_bytes(item) = record_bytes(
        "CellDerivation", [
            "output_slot" => string_bytes(item.output_slot), "output_key" => key_bytes(item.output_key),
            "output_name" => string_bytes(item.output_name), "output_value" => float_bytes(item.output_value),
            "transformation_id" => string_bytes(item.transformation_id), "transformation_version" => string_bytes(item.transformation_version),
            "operator_id" => string_bytes(item.operator_id), "operator_version" => string_bytes(item.operator_version),
            "input_observation_ids" => vector_bytes("OrderedObservationIds", item.input_observation_ids, string_bytes),
            "operator_parameters" => vector_bytes("OrderedFloat64", item.operator_parameters, float_bytes),
        ]
    )

    function receipt_preimage(receipt)
        return record_bytes(
            DERIVATION_DOMAIN, [
                "schema_version" => string_bytes(receipt.schema_version),
                "canonicalization" => string_bytes(receipt.canonicalization),
                "digest_algorithm" => string_bytes(receipt.digest_algorithm),
                "evidence_class" => string_bytes(receipt.evidence_class),
                "empirical_execution_authorized" => bool_bytes(receipt.empirical_execution_authorized),
                "production_admission_authorized" => bool_bytes(receipt.production_admission_authorized),
                "source_artifacts" => vector_bytes("SortedSourceArtifacts", receipt.source_artifacts, artifact_bytes),
                "source_observations" => vector_bytes("SourceObservations", receipt.source_observations, observation_bytes),
                "cell_derivations" => vector_bytes("CellDerivations", receipt.cell_derivations, derivation_bytes),
                "sample_sha256" => string_bytes(receipt.sample_sha256),
            ]
        )
    end

    sha256_hex(value) = bytes2hex(SHA.sha256(value))
    derivation_receipt_sha256(receipt::TransformationReceipt) = sha256_hex(receipt_preimage(receipt))

    function validate_receipt_constants(receipt)
        receipt.schema_version == SCHEMA_VERSION || fail("receipt.schema_version", "is unsupported")
        receipt.canonicalization == CANONICALIZATION || fail("receipt.canonicalization", "is unsupported")
        receipt.digest_algorithm == DIGEST_ALGORITHM || fail("receipt.digest_algorithm", "is unsupported")
        receipt.evidence_class == EVIDENCE_CLASS || fail("receipt.evidence_class", "must remain synthetic-only")
        receipt.empirical_execution_authorized == EMPIRICAL_EXECUTION_AUTHORIZED || fail("receipt.empirical_execution_authorized", "cannot authorize empirical execution")
        receipt.production_admission_authorized == PRODUCTION_ADMISSION_AUTHORIZED || fail("receipt.production_admission_authorized", "cannot authorize production admission")
        expect_hash(receipt.sample_sha256, "receipt.sample_sha256")
        expect_hash(receipt.receipt_sha256, "receipt.receipt_sha256")
        return nothing
    end

    """Recompute and validate every source-to-cell edge and receipt seal."""
    function validate_built_origin_data(result::BuiltOriginData{K}) where {K}
        expect_identifier(result.sample.origin_id, "sample.origin_id")
        expect_key(result.sample.origin_key, "sample.origin_key")
        receipt = result.receipt
        validate_receipt_constants(receipt)
        artifacts = validate_artifacts(receipt.source_artifacts)
        artifacts == receipt.source_artifacts || fail("receipt.source_artifacts", "must be sorted canonically")
        observations = validate_observations(receipt.source_observations, K, artifacts)
        observations == receipt.source_observations || fail("receipt.source_observations", "must be sorted canonically by observation ID")
        training_keys = copy_key_vector(result.sample.training_keys, K, "sample.training_keys")
        forecast_keys = copy_key_vector(result.sample.forecast_keys, K, "sample.forecast_keys")
        all(key -> !isless(result.sample.origin_key, key), training_keys) || fail("sample.training_keys", "looks ahead of origin_key")
        all(key -> isless(result.sample.origin_key, key), forecast_keys) || fail("sample.forecast_keys", "must be later than origin_key")
        target_names = expect_exact_string_vector(result.sample.target_names, "sample.target_names")
        predictor_names = expect_exact_string_vector(result.sample.predictor_names, "sample.predictor_names")
        expected = expected_cell_vector(training_keys, forecast_keys, target_names, predictor_names)
        derivations = validate_derivations(receipt.cell_derivations, K, expected, observations)
        y_train, x_train, x_future = build_matrices(training_keys, forecast_keys, target_names, predictor_names, derivations)
        rebuilt = OriginData(
            origin_id = result.sample.origin_id, origin_key = result.sample.origin_key,
            training_keys = training_keys, forecast_keys = forecast_keys, y_train = y_train,
            x_train = x_train, x_future = x_future, target_names = target_names, predictor_names = predictor_names
        )
        origin_data_sha256(rebuilt) == origin_data_sha256(result.sample) || fail("sample", "does not exactly equal its cell derivations")
        sample_hash = origin_data_sha256(result.sample)
        sample_hash == receipt.sample_sha256 || fail("receipt.sample_sha256", "does not match sample")
        derivation_receipt_sha256(receipt) == receipt.receipt_sha256 || fail("receipt.receipt_sha256", "self-hash does not match receipt")
        return (sample_sha256 = sample_hash, receipt_sha256 = receipt.receipt_sha256, source_observation_count = length(observations), cell_derivation_count = length(derivations))
    end

    """
        build_synthetic_origin_data(; ...)

    Construct an owned `OriginData` from explicit, complete source-to-cell lineages.
    This v1 contract is deliberately synthetic-only and cannot authorize acquisition,
    empirical scoring, or production origin admission.
    """
    function build_synthetic_origin_data(;
            origin_id, origin_key, training_keys, forecast_keys, target_names,
            predictor_names = String[], source_artifacts, source_observations, cell_derivations
        )
        key = expect_key(origin_key, "origin_key")
        key_type = typeof(key)
        id = expect_identifier(origin_id, "origin_id")
        train = copy_key_vector(training_keys, key_type, "training_keys")
        future = copy_key_vector(forecast_keys, key_type, "forecast_keys")
        all(item -> !isless(key, item), train) || fail("training_keys", "looks ahead of origin_key")
        all(item -> isless(key, item), future) || fail("forecast_keys", "must be later than origin_key")
        targets = expect_exact_string_vector(target_names, "target_names")
        isempty(targets) && fail("target_names", "must not be empty")
        predictors = expect_exact_string_vector(predictor_names, "predictor_names")
        artifacts = validate_artifacts(source_artifacts)
        observations = validate_observations(source_observations, key_type, artifacts)
        expected = expected_cell_vector(train, future, targets, predictors)
        derivations = validate_derivations(cell_derivations, key_type, expected, observations)
        y_train, x_train, x_future = build_matrices(train, future, targets, predictors, derivations)
        sample = OriginData(
            origin_id = id, origin_key = key, training_keys = train, forecast_keys = future,
            y_train = y_train, x_train = x_train, x_future = x_future, target_names = targets, predictor_names = predictors
        )
        sample_hash = origin_data_sha256(sample)
        provisional = TransformationReceipt{key_type}(
            SCHEMA_VERSION, CANONICALIZATION, DIGEST_ALGORITHM, EVIDENCE_CLASS,
            EMPIRICAL_EXECUTION_AUTHORIZED, PRODUCTION_ADMISSION_AUTHORIZED,
            artifacts, observations, derivations, sample_hash, repeat("1", 64),
        )
        receipt = TransformationReceipt{key_type}(
            SCHEMA_VERSION, CANONICALIZATION, DIGEST_ALGORITHM, EVIDENCE_CLASS,
            EMPIRICAL_EXECUTION_AUTHORIZED, PRODUCTION_ADMISSION_AUTHORIZED,
            artifacts, observations, derivations, sample_hash, derivation_receipt_sha256(provisional),
        )
        result = BuiltOriginData{key_type}(sample, receipt)
        validate_built_origin_data(result)
        return result
    end

end
