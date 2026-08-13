module USOriginDataReceipt

using Dates
using SHA

export AuthenticatedOriginData,
    OriginDataReceipt,
    OriginDataReceiptError,
    OriginDataSnapshot,
    SourceArtifact,
    authenticate_origin_data,
    authenticated_sample,
    origin_data_sha256,
    validate_origin_data_receipt

const SCHEMA_VERSION = "beforeit-us-origin-data-receipt.v1"
const CANONICALIZATION =
    "typed-length-prefixed-big-endian.v1"
const DIGEST_ALGORITHM = "sha256"
const EVIDENCE_CLASS = "synthetic_fixture_only"
const EMPIRICAL_EXECUTION_AUTHORIZED = false
const SAMPLE_DOMAIN = "beforeit-us-origin-data-sample.v1"
const RECEIPT_DOMAIN = "beforeit-us-origin-data-receipt-self-hash.v1"
const ZERO_HASH = repeat("0", 64)

const SIGNED_KEY_TYPES = (
    Int8,
    Int16,
    Int32,
    Int64,
    Int128,
)
const UNSIGNED_KEY_TYPES = (
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    UInt128,
)
const SUPPORTED_KEY_TYPES = (
    String,
    Date,
    DateTime,
    SIGNED_KEY_TYPES...,
    UNSIGNED_KEY_TYPES...,
)
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

struct OriginDataReceiptError <: Exception
    message::String
end

Base.showerror(io::IO, error::OriginDataReceiptError) =
    print(io, error.message)

fail(location, message) =
    throw(OriginDataReceiptError("$location: $message"))

function expect_string(value, location)
    typeof(value) === String ||
        fail(location, "must be an exact String")
    value == strip(value) ||
        fail(location, "has surrounding whitespace")
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
    text == ZERO_HASH &&
        fail(location, "must not be the all-zero placeholder hash")
    return text
end

"""
One immutable source-artifact identity included in the receipt provenance set.
"""
struct SourceArtifact
    artifact_id::String
    sha256::String

    function SourceArtifact(artifact_id, sha256)
        return new(
            expect_identifier(
                artifact_id,
                "source_artifact.artifact_id",
            ),
            expect_hash(sha256, "source_artifact.sha256"),
        )
    end
end

SourceArtifact(; artifact_id, sha256) =
    SourceArtifact(artifact_id, sha256)

"""
A detached, owned copy of all fields in a benchmark `OriginData`.
"""
struct OriginDataSnapshot{K}
    origin_id::String
    origin_key::K
    training_keys::Vector{K}
    forecast_keys::Vector{K}
    y_train::Matrix{Float64}
    x_train::Union{Nothing, Matrix{Float64}}
    x_future::Union{Nothing, Matrix{Float64}}
    target_names::Vector{String}
    predictor_names::Vector{String}
end

"""
Versioned provenance and hash receipt. The fixed execution fields cannot grant
empirical authorization in v1.
"""
struct OriginDataReceipt
    schema_version::String
    canonicalization::String
    digest_algorithm::String
    evidence_class::String
    empirical_execution_authorized::Bool
    origin_manifest_sha256::String
    protocol_sha256::String
    model_registry_content_sha256::String
    target_contract_sha256::String
    target_panel_id::String
    source_artifacts::Tuple{Vararg{SourceArtifact}}
    sample_sha256::String
    receipt_sha256::String

    function OriginDataReceipt(
            schema_version,
            canonicalization,
            digest_algorithm,
            evidence_class,
            empirical_execution_authorized,
            origin_manifest_sha256,
            protocol_sha256,
            model_registry_content_sha256,
            target_contract_sha256,
            target_panel_id,
            source_artifacts,
            sample_sha256,
            receipt_sha256,
        )
        schema_version == SCHEMA_VERSION ||
            fail(
            "receipt.schema_version",
            "must be $SCHEMA_VERSION",
        )
        canonicalization == CANONICALIZATION ||
            fail(
            "receipt.canonicalization",
            "must be $CANONICALIZATION",
        )
        digest_algorithm == DIGEST_ALGORITHM ||
            fail(
            "receipt.digest_algorithm",
            "must be $DIGEST_ALGORITHM",
        )
        evidence_class == EVIDENCE_CLASS ||
            fail(
            "receipt.evidence_class",
            "must be $EVIDENCE_CLASS",
        )
        empirical_execution_authorized isa Bool ||
            fail(
            "receipt.empirical_execution_authorized",
            "must be Bool",
        )
        empirical_execution_authorized ==
            EMPIRICAL_EXECUTION_AUTHORIZED ||
            fail(
            "receipt.empirical_execution_authorized",
            "v1 cannot authorize empirical execution",
        )
        sources = validated_source_artifacts(
            source_artifacts;
            require_sorted = true,
        )
        return new(
            SCHEMA_VERSION,
            CANONICALIZATION,
            DIGEST_ALGORITHM,
            EVIDENCE_CLASS,
            EMPIRICAL_EXECUTION_AUTHORIZED,
            expect_hash(
                origin_manifest_sha256,
                "receipt.origin_manifest_sha256",
            ),
            expect_hash(
                protocol_sha256,
                "receipt.protocol_sha256",
            ),
            expect_hash(
                model_registry_content_sha256,
                "receipt.model_registry_content_sha256",
            ),
            expect_hash(
                target_contract_sha256,
                "receipt.target_contract_sha256",
            ),
            expect_identifier(
                target_panel_id,
                "receipt.target_panel_id",
            ),
            sources,
            expect_hash(sample_sha256, "receipt.sample_sha256"),
            expect_hash(receipt_sha256, "receipt.receipt_sha256"),
        )
    end
end

OriginDataReceipt(;
    schema_version,
    canonicalization,
    digest_algorithm,
    evidence_class,
    empirical_execution_authorized,
    origin_manifest_sha256,
    protocol_sha256,
    model_registry_content_sha256,
    target_contract_sha256,
    target_panel_id,
    source_artifacts,
    sample_sha256,
    receipt_sha256,
) = OriginDataReceipt(
    schema_version,
    canonicalization,
    digest_algorithm,
    evidence_class,
    empirical_execution_authorized,
    origin_manifest_sha256,
    protocol_sha256,
    model_registry_content_sha256,
    target_contract_sha256,
    target_panel_id,
    source_artifacts,
    sample_sha256,
    receipt_sha256,
)

"""Owned sample plus its deterministic provenance receipt."""
struct AuthenticatedOriginData{K}
    sample::OriginDataSnapshot{K}
    receipt::OriginDataReceipt
end

function required_property(value, property, location)
    hasproperty(value, property) ||
        fail(location, "is missing property $property")
    return getproperty(value, property)
end

function validated_source_artifacts(
        source_artifacts;
        require_sorted = false,
    )
    source_artifacts isa Union{AbstractVector, Tuple} ||
        fail(
        "source_artifacts",
        "must be a vector or tuple of SourceArtifact",
    )
    sources = SourceArtifact[]
    for (index, source) in enumerate(source_artifacts)
        source isa SourceArtifact ||
            fail(
            "source_artifacts[$index]",
            "must be a SourceArtifact",
        )
        push!(
            sources,
            SourceArtifact(source.artifact_id, source.sha256),
        )
    end
    isempty(sources) &&
        fail("source_artifacts", "must not be empty")
    artifact_ids = [source.artifact_id for source in sources]
    allunique(artifact_ids) ||
        fail("source_artifacts", "must have unique artifact IDs")
    sorted = sort(sources; by = source -> (source.artifact_id, source.sha256))
    source_keys =
        [(source.artifact_id, source.sha256) for source in sources]
    sorted_keys =
        [(source.artifact_id, source.sha256) for source in sorted]
    if require_sorted && source_keys != sorted_keys
        fail(
            "source_artifacts",
            "must be sorted by artifact ID and hash",
        )
    end
    return tuple(sorted...)
end

function expect_exact_string_vector(value, location)
    typeof(value) === Vector{String} ||
        fail(location, "must be an exact Vector{String}")
    result = String[]
    for (index, item) in enumerate(value)
        typeof(item) === String ||
            fail("$location[$index]", "must be an exact String")
        isempty(item) &&
            fail("$location[$index]", "must not be empty")
        push!(result, String(item))
    end
    allunique(result) ||
        fail(location, "must not contain duplicates")
    return result
end

function expect_key_type(key)
    key_type = typeof(key)
    key_type in SUPPORTED_KEY_TYPES ||
        fail(
        "sample.origin_key",
        "unsupported key type $key_type",
    )
    return key_type
end

function copy_key_vector(value, key_type, location)
    typeof(value) === Vector{key_type} ||
        fail(
        location,
        "must be an exact Vector{$key_type}",
    )
    result = key_type[value...]
    isempty(result) && fail(location, "must not be empty")
    for index in 2:length(result)
        isless(result[index - 1], result[index]) ||
            fail(location, "must be strictly increasing")
    end
    return result
end

function copy_matrix(value, location)
    typeof(value) === Matrix{Float64} ||
        fail(location, "must be an exact Matrix{Float64}")
    all(isfinite, value) ||
        fail(location, "must contain only finite Float64 values")
    return copy(value)
end

function snapshot_origin_data(sample)
    origin_id =
        expect_string(required_property(sample, :origin_id, "sample"), "sample.origin_id")
    origin_key = required_property(sample, :origin_key, "sample")
    key_type = expect_key_type(origin_key)
    training_keys = copy_key_vector(
        required_property(sample, :training_keys, "sample"),
        key_type,
        "sample.training_keys",
    )
    forecast_keys = copy_key_vector(
        required_property(sample, :forecast_keys, "sample"),
        key_type,
        "sample.forecast_keys",
    )
    all(key -> !isless(origin_key, key), training_keys) ||
        fail(
        "sample.training_keys",
        "must not contain a key later than origin_key",
    )
    all(key -> isless(origin_key, key), forecast_keys) ||
        fail(
        "sample.forecast_keys",
        "must contain only keys later than origin_key",
    )

    y_train = copy_matrix(
        required_property(sample, :y_train, "sample"),
        "sample.y_train",
    )
    size(y_train, 1) == length(training_keys) ||
        fail(
        "sample.y_train",
        "row count must match training_keys",
    )
    size(y_train, 2) >= 1 ||
        fail("sample.y_train", "must contain at least one target")

    target_names = expect_exact_string_vector(
        required_property(sample, :target_names, "sample"),
        "sample.target_names",
    )
    length(target_names) == size(y_train, 2) ||
        fail(
        "sample.target_names",
        "count must match y_train columns",
    )

    predictor_names = expect_exact_string_vector(
        required_property(sample, :predictor_names, "sample"),
        "sample.predictor_names",
    )
    raw_x_train = required_property(sample, :x_train, "sample")
    raw_x_future = required_property(sample, :x_future, "sample")
    if raw_x_train === nothing || raw_x_future === nothing
        raw_x_train === nothing && raw_x_future === nothing ||
            fail(
            "sample.x_train/x_future",
            "must be both present or both absent",
        )
        isempty(predictor_names) ||
            fail(
            "sample.predictor_names",
            "must be empty when exogenous matrices are absent",
        )
        x_train = nothing
        x_future = nothing
    else
        x_train = copy_matrix(raw_x_train, "sample.x_train")
        x_future = copy_matrix(raw_x_future, "sample.x_future")
        size(x_train, 1) == length(training_keys) ||
            fail(
            "sample.x_train",
            "row count must match training_keys",
        )
        size(x_future, 1) == length(forecast_keys) ||
            fail(
            "sample.x_future",
            "row count must match forecast_keys",
        )
        size(x_train, 2) == size(x_future, 2) ||
            fail(
            "sample.x_train/x_future",
            "column counts must match",
        )
        length(predictor_names) == size(x_train, 2) ||
            fail(
            "sample.predictor_names",
            "count must match exogenous matrix columns",
        )
    end

    return OriginDataSnapshot{key_type}(
        String(origin_id),
        origin_key,
        training_keys,
        forecast_keys,
        y_train,
        x_train,
        x_future,
        target_names,
        predictor_names,
    )
end

function write_unsigned_be(io, value::T) where {T <: Unsigned}
    for byte_index in (sizeof(T) - 1):-1:0
        write(io, UInt8((value >> (8byte_index)) & T(0xff)))
    end
    return io
end

function write_count(io, value, location)
    value >= 0 || fail(location, "must be nonnegative")
    value <= typemax(UInt64) ||
        fail(location, "is too large to canonicalize")
    write_unsigned_be(io, UInt64(value))
    return io
end

function append_frame!(io, tag::String, payload::Vector{UInt8})
    tag_bytes = collect(codeunits(tag))
    length(tag_bytes) <= typemax(UInt32) ||
        fail("canonicalization.tag", "is too long")
    write_unsigned_be(io, UInt32(length(tag_bytes)))
    write(io, tag_bytes)
    write_count(io, length(payload), "canonicalization.payload")
    write(io, payload)
    return io
end

function frame(tag::String, payload::Vector{UInt8} = UInt8[])
    io = IOBuffer()
    append_frame!(io, tag, payload)
    return take!(io)
end

string_bytes(value::String) =
    frame("String", collect(codeunits(value)))

function bool_bytes(value::Bool)
    return frame("Bool", UInt8[value ? 0x01 : 0x00])
end

function integer_payload(value)
    key_type = typeof(value)
    unsigned_type = UNSIGNED_TYPE[key_type]
    unsigned_value = if key_type <: Signed
        reinterpret(unsigned_type, value)
    else
        value
    end
    io = IOBuffer()
    write_unsigned_be(io, unsigned_value)
    return take!(io)
end

function key_bytes(value)
    key_type = expect_key_type(value)
    if key_type === String
        return string_bytes(value)
    elseif key_type === Date
        io = IOBuffer()
        write_unsigned_be(io, reinterpret(UInt64, Dates.value(value)))
        return frame("Date/days", take!(io))
    elseif key_type === DateTime
        io = IOBuffer()
        write_unsigned_be(io, reinterpret(UInt64, Dates.value(value)))
        return frame("DateTime/milliseconds", take!(io))
    end
    return frame(string(key_type), integer_payload(value))
end

function ordered_key_vector_bytes(values)
    io = IOBuffer()
    write_count(io, length(values), "canonicalization.key_count")
    for value in values
        write(io, key_bytes(value))
    end
    return frame("OrderedKeyVector", take!(io))
end

function string_vector_bytes(values)
    io = IOBuffer()
    write_count(io, length(values), "canonicalization.string_count")
    for value in values
        write(io, string_bytes(value))
    end
    return frame("OrderedStringVector", take!(io))
end

function matrix_bytes(value)
    value === nothing && return frame("Nothing")
    io = IOBuffer()
    write_count(io, size(value, 1), "canonicalization.matrix_rows")
    write_count(io, size(value, 2), "canonicalization.matrix_columns")
    for element in value
        write_unsigned_be(io, reinterpret(UInt64, element))
    end
    return frame(
        "Matrix{Float64}/column-major/ieee754-binary64",
        take!(io),
    )
end

function source_artifacts_bytes(sources)
    io = IOBuffer()
    write_count(
        io,
        length(sources),
        "canonicalization.source_artifact_count",
    )
    for source in sources
        payload = IOBuffer()
        append_frame!(
            payload,
            "field:artifact_id",
            string_bytes(source.artifact_id),
        )
        append_frame!(
            payload,
            "field:sha256",
            string_bytes(source.sha256),
        )
        write(
            io,
            frame("SourceArtifact", take!(payload)),
        )
    end
    return frame("SortedUniqueSourceArtifactSet", take!(io))
end

function record_bytes(tag, fields)
    io = IOBuffer()
    for (name, encoded_value) in fields
        append_frame!(io, "field:$name", encoded_value)
    end
    return frame(tag, take!(io))
end

function sample_bytes(snapshot)
    return record_bytes(
        SAMPLE_DOMAIN,
        [
            "origin_id" => string_bytes(snapshot.origin_id),
            "origin_key" => key_bytes(snapshot.origin_key),
            "training_keys" =>
                ordered_key_vector_bytes(snapshot.training_keys),
            "forecast_keys" =>
                ordered_key_vector_bytes(snapshot.forecast_keys),
            "y_train" => matrix_bytes(snapshot.y_train),
            "x_train" => matrix_bytes(snapshot.x_train),
            "x_future" => matrix_bytes(snapshot.x_future),
            "target_names" =>
                string_vector_bytes(snapshot.target_names),
            "predictor_names" =>
                string_vector_bytes(snapshot.predictor_names),
        ],
    )
end

sha256_hex(value::Vector{UInt8}) =
    bytes2hex(SHA.sha256(value))

function receipt_preimage(
        receipt,
        encoded_sample::Vector{UInt8},
    )
    return record_bytes(
        RECEIPT_DOMAIN,
        [
            "schema_version" =>
                string_bytes(receipt.schema_version),
            "canonicalization" =>
                string_bytes(receipt.canonicalization),
            "digest_algorithm" =>
                string_bytes(receipt.digest_algorithm),
            "evidence_class" =>
                string_bytes(receipt.evidence_class),
            "empirical_execution_authorized" =>
                bool_bytes(receipt.empirical_execution_authorized),
            "origin_manifest_sha256" =>
                string_bytes(receipt.origin_manifest_sha256),
            "protocol_sha256" =>
                string_bytes(receipt.protocol_sha256),
            "model_registry_content_sha256" =>
                string_bytes(receipt.model_registry_content_sha256),
            "target_contract_sha256" =>
                string_bytes(receipt.target_contract_sha256),
            "target_panel_id" =>
                string_bytes(receipt.target_panel_id),
            "source_artifacts" =>
                source_artifacts_bytes(receipt.source_artifacts),
            "sample_sha256" =>
                string_bytes(receipt.sample_sha256),
            "sample" => encoded_sample,
        ],
    )
end

function receipt_digest(
        ;
        origin_manifest_sha256,
        protocol_sha256,
        model_registry_content_sha256,
        target_contract_sha256,
        target_panel_id,
        source_artifacts,
        sample_sha256,
        encoded_sample,
    )
    metadata = (
        schema_version = SCHEMA_VERSION,
        canonicalization = CANONICALIZATION,
        digest_algorithm = DIGEST_ALGORITHM,
        evidence_class = EVIDENCE_CLASS,
        empirical_execution_authorized =
            EMPIRICAL_EXECUTION_AUTHORIZED,
        origin_manifest_sha256,
        protocol_sha256,
        model_registry_content_sha256,
        target_contract_sha256,
        target_panel_id,
        source_artifacts,
        sample_sha256,
    )
    return sha256_hex(receipt_preimage(metadata, encoded_sample))
end

"""
    authenticate_origin_data(sample; provenance...)

Copy and authenticate every `OriginData` field plus the supplied, hash-addressed
provenance. V1 always produces synthetic-only, non-empirical receipts.
"""
function authenticate_origin_data(
        sample;
        origin_manifest_sha256,
        protocol_sha256,
        model_registry_content_sha256,
        target_contract_sha256,
        target_panel_id,
        source_artifacts,
    )
    snapshot = snapshot_origin_data(sample)
    origin_hash =
        expect_hash(origin_manifest_sha256, "origin_manifest_sha256")
    protocol_hash = expect_hash(protocol_sha256, "protocol_sha256")
    model_registry_hash = expect_hash(
        model_registry_content_sha256,
        "model_registry_content_sha256",
    )
    target_hash =
        expect_hash(target_contract_sha256, "target_contract_sha256")
    panel_id = expect_identifier(target_panel_id, "target_panel_id")
    sources = validated_source_artifacts(source_artifacts)
    encoded_sample = sample_bytes(snapshot)
    sample_hash = sha256_hex(encoded_sample)
    seal = receipt_digest(;
        origin_manifest_sha256 = origin_hash,
        protocol_sha256 = protocol_hash,
        model_registry_content_sha256 = model_registry_hash,
        target_contract_sha256 = target_hash,
        target_panel_id = panel_id,
        source_artifacts = sources,
        sample_sha256 = sample_hash,
        encoded_sample,
    )
    receipt = OriginDataReceipt(
        SCHEMA_VERSION,
        CANONICALIZATION,
        DIGEST_ALGORITHM,
        EVIDENCE_CLASS,
        EMPIRICAL_EXECUTION_AUTHORIZED,
        origin_hash,
        protocol_hash,
        model_registry_hash,
        target_hash,
        panel_id,
        sources,
        sample_hash,
        seal,
    )
    envelope = AuthenticatedOriginData(snapshot, receipt)
    validate_origin_data_receipt(envelope)
    return envelope
end

"""
    origin_data_sha256(sample)

Return the v1 canonical sample hash without constructing a provenance receipt.
"""
function origin_data_sha256(sample)
    snapshot = snapshot_origin_data(sample)
    return sha256_hex(sample_bytes(snapshot))
end

function validate_receipt_constants(receipt)
    receipt.schema_version == SCHEMA_VERSION ||
        fail("receipt.schema_version", "is unsupported")
    receipt.canonicalization == CANONICALIZATION ||
        fail("receipt.canonicalization", "is unsupported")
    receipt.digest_algorithm == DIGEST_ALGORITHM ||
        fail("receipt.digest_algorithm", "is unsupported")
    receipt.evidence_class == EVIDENCE_CLASS ||
        fail("receipt.evidence_class", "must remain synthetic-only")
    receipt.empirical_execution_authorized ==
        EMPIRICAL_EXECUTION_AUTHORIZED ||
        fail(
        "receipt.empirical_execution_authorized",
        "v1 cannot authorize empirical execution",
    )
    expect_hash(
        receipt.origin_manifest_sha256,
        "receipt.origin_manifest_sha256",
    )
    expect_hash(receipt.protocol_sha256, "receipt.protocol_sha256")
    expect_hash(
        receipt.model_registry_content_sha256,
        "receipt.model_registry_content_sha256",
    )
    expect_hash(
        receipt.target_contract_sha256,
        "receipt.target_contract_sha256",
    )
    expect_identifier(
        receipt.target_panel_id,
        "receipt.target_panel_id",
    )
    validated_source_artifacts(
        receipt.source_artifacts;
        require_sorted = true,
    )
    expect_hash(receipt.sample_sha256, "receipt.sample_sha256")
    expect_hash(receipt.receipt_sha256, "receipt.receipt_sha256")
    return nothing
end

"""
    validate_origin_data_receipt(envelope; sample = nothing)

Recompute the sample hash and receipt self-hash. If `sample` is supplied, also
require its complete canonical bytes to equal the owned authenticated snapshot.
"""
function validate_origin_data_receipt(
        envelope::AuthenticatedOriginData;
        sample = nothing,
    )
    receipt = envelope.receipt
    validate_receipt_constants(receipt)
    owned_snapshot = snapshot_origin_data(envelope.sample)
    encoded_sample = sample_bytes(owned_snapshot)
    computed_sample_hash = sha256_hex(encoded_sample)
    computed_sample_hash == receipt.sample_sha256 ||
        fail(
        "receipt.sample_sha256",
        "does not match the authenticated sample",
    )
    computed_receipt_hash =
        sha256_hex(receipt_preimage(receipt, encoded_sample))
    computed_receipt_hash == receipt.receipt_sha256 ||
        fail(
        "receipt.receipt_sha256",
        "self-hash does not match receipt and sample",
    )

    if sample !== nothing
        candidate_snapshot = snapshot_origin_data(sample)
        candidate_bytes = sample_bytes(candidate_snapshot)
        candidate_bytes == encoded_sample ||
            fail(
            "sample",
            "does not exactly match the authenticated sample bytes",
        )
    end
    return (
        sample_sha256 = computed_sample_hash,
        receipt_sha256 = computed_receipt_hash,
        source_artifact_count = length(receipt.source_artifacts),
        key_type = typeof(owned_snapshot.origin_key),
    )
end

"""
Validate an envelope and return another owned sample copy.
"""
function authenticated_sample(envelope::AuthenticatedOriginData)
    validate_origin_data_receipt(envelope)
    return snapshot_origin_data(envelope.sample)
end

end
