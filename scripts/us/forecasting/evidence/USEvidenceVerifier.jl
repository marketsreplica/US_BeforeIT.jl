module USEvidenceVerifier

using Dates
using SHA
using TOML

export DEFAULT_EVIDENCE_PATH,
    EXPECTED_OPERATOR_IDS,
    EXPECTED_TARGET_IDS,
    MINIMUM_COMMON_ORIGINS,
    REQUIRED_TRUTH_LAYER_IDS,
    EvidenceError,
    computed_content_sha256,
    evidence_manifest_sha256,
    file_sha256,
    load_evidence_manifest,
    require_integrity_verified,
    require_verified_evidence,
    stamp_content_sha256!,
    validate_evidence_manifest,
    verify_evidence

const DEFAULT_EVIDENCE_PATH = joinpath(@__DIR__, "unavailable_evidence.toml")
const ROOT_SCHEMA_VERSION = "beforeit-us-artifact-evidence.v1"
const TRUTH_SCHEMA_VERSION = "beforeit-us-truth-evidence-manifest.v1"
const TRUTH_ARTIFACT_FORMAT = "beforeit-us-truth-values-tsv.v1"
const OPERATOR_SCHEMA_VERSION = "beforeit-us-operator-evidence-manifest.v1"
const VALIDATION_RECEIPT_SCHEMA_VERSION =
    "beforeit-us-operator-validation-receipt.v1"
const SIGNOFF_RECEIPT_SCHEMA_VERSION =
    "beforeit-us-operator-signoff-receipt.v1"
const CANONICALIZATION =
    "sorted_typed_v1_excluding_artifact_content_sha256"
const CONTRACT_ID = "beforeit-us-artifact-evidence-verification.v1"
const PROTOCOL_ID = "beforeit-us-forecast-evaluation.v1-draft"
const PROTOCOL_SHA256 =
    "88519e5b04936f528396cf5243ff270844d0d38651fd84fc3b1c76fef997b584"
const PRODUCT_ID = "quarterly_unconditional"
const ORIGIN_RULE_ID = "quarterly-after-advance.v1-draft"
const INFORMATION_TRACK = "common_information"
const MINIMUM_COMMON_ORIGINS = 40
const PROMOTION_EVIDENCE_CLASS = "retrospective_evaluation"

const EXPECTED_TARGET_IDS = (
    "real_gdp",
    "pce_price_index",
    "core_pce_price_index",
    "gdp_deflator",
    "unemployment_rate",
    "payroll_employment",
    "effective_federal_funds_rate",
    "nominal_gdp",
)

const REQUIRED_TRUTH_LAYER_IDS = (
    "first_release",
    "near_mature",
    "mature",
)

const EXPECTED_OPERATOR_IDS = Dict(
    "real_gdp" => "abm-to-bea-real-gdp.v1-draft",
    "pce_price_index" => "abm-to-bea-pce-price-index.v1-draft",
    "core_pce_price_index" =>
        "abm-to-bea-core-pce-price-index.v1-draft",
    "gdp_deflator" => "abm-to-bea-gdp-deflator.v1-draft",
    "unemployment_rate" =>
        "abm-to-bls-unemployment-rate.v1-draft",
    "payroll_employment" =>
        "abm-to-bls-payroll-employment.v1-draft",
    "effective_federal_funds_rate" =>
        "abm-to-frb-effective-federal-funds-rate.v1-draft",
    "nominal_gdp" => "abm-to-bea-nominal-gdp.v1-draft",
)

const EVIDENCE_CLASSES = Set(
    ["repository_audit", "retrospective_evaluation", "synthetic_test_only"],
)
const REFERENCE_STATUSES = Set(["available", "unavailable"])
const AVAILABILITY_STATUSES = Set(["unavailable", "partial", "candidate"])
const NULL_ARTIFACT = "unavailable"

struct EvidenceError <: Exception
    message::String
end

Base.showerror(io::IO, error::EvidenceError) = print(io, error.message)

fail(location, message) = throw(EvidenceError("$location: $message"))

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    expected_set = Set(String.(expected))
    missing = sort!(collect(setdiff(expected_set, actual)))
    unknown = sort!(collect(setdiff(actual, expected_set)))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown keys: $(join(unknown, ", "))")
    return table
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
    occursin('\0', text) && fail(location, "must not contain NUL")
    return text
end

function expect_identifier(value, location)
    text = expect_string(value, location)
    occursin(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", text) ||
        fail(location, "must be a canonical identifier")
    return text
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

function expect_integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    number = Int(value)
    number >= minimum || fail(location, "must be at least $minimum")
    return number
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function expect_exact(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function expect_one_of(value, allowed, location)
    text = expect_string(value, location)
    text in allowed || fail(location, "unsupported value '$text'")
    return text
end

function expect_timestamp(value, location)
    text = expect_string(value, location)
    occursin(
        r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
        text,
    ) || fail(location, "must use RFC3339 seconds in UTC")
    timestamp = try
        DateTime(text, dateformat"yyyy-mm-ddTHH:MM:SSZ")
    catch
        fail(location, "must be a valid UTC timestamp")
    end
    Dates.format(timestamp, dateformat"yyyy-mm-ddTHH:MM:SSZ") == text ||
        fail(location, "must be a canonical UTC timestamp")
    return timestamp
end

function expect_reference_key(value, location)
    text = expect_string(value, location)
    occursin(r"^[0-9]{4}-Q[1-4]$", text) ||
        fail(location, "must use YYYY-Q1 through YYYY-Q4")
    return text
end

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        entries =
            sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            _canonical_write(io, String(key))
            _canonical_write(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "A", length(value), "[")
        for entry in value
            _canonical_write(io, entry)
        end
        print(io, "]")
    elseif value isa AbstractString
        text = String(value)
        print(io, "S", ncodeunits(text), ":", text)
    elseif value isa Bool
        print(io, value ? "B1" : "B0")
    elseif value isa Integer
        print(io, "I", value, ";")
    elseif value isa AbstractFloat
        number = Float64(value)
        isfinite(number) ||
            fail("canonicalization", "cannot encode a nonfinite number")
        print(io, "F", bitstring(number), ";")
    else
        fail(
            "canonicalization",
            "unsupported value of type $(typeof(value))",
        )
    end
    return io
end

function computed_content_sha256(value)
    manifest = deepcopy(expect_table(value, "evidence"))
    artifact =
        expect_table(get(manifest, "artifact", nothing), "evidence.artifact")
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, manifest)
    return bytes2hex(sha256(take!(io)))
end

function stamp_content_sha256!(value)
    manifest = expect_table(value, "evidence")
    artifact =
        expect_table(get(manifest, "artifact", nothing), "evidence.artifact")
    artifact["content_sha256"] = computed_content_sha256(manifest)
    return manifest
end

file_sha256(path::AbstractString) = bytes2hex(sha256(read(path)))

function _parse_toml_bytes(bytes::Vector{UInt8}, location)
    isvalid(String, bytes) || fail(location, "must contain valid UTF-8")
    return try
        TOML.parse(String(copy(bytes)))
    catch error
        fail(location, "could not parse TOML: $(sprint(showerror, error))")
    end
end

function load_evidence_manifest(path::AbstractString = DEFAULT_EVIDENCE_PATH)
    isfile(path) ||
        fail("evidence", "file does not exist: $(abspath(path))")
    islink(path) &&
        fail("evidence", "root manifest must not be a symbolic link")
    return _parse_toml_bytes(read(path), "evidence")
end

function _inside_root(path, root)
    relative = relpath(path, root)
    return relative != ".." &&
        !startswith(relative, "..$(Base.Filesystem.path_separator)")
end

function _validate_declared_path(value, location)
    path = expect_string(value, location)
    path == NULL_ARTIFACT &&
        fail(location, "'$NULL_ARTIFACT' is not an available artifact path")
    isabspath(path) && fail(location, "must be relative")
    occursin('\\', path) &&
        fail(location, "must use forward-slash path separators")
    normpath(path) == path || fail(location, "must already be normalized")
    components = split(path, '/')
    any(component -> component in ("", ".", ".."), components) &&
        fail(location, "must not contain empty, dot, or parent components")
    return path
end

function _resolve_bytes(
        root_directory,
        base_directory,
        declared_path,
        declared_sha256,
        location,
    )
    relative_path = _validate_declared_path(declared_path, "$location.path")
    expected_sha256 = expect_hash(declared_sha256, "$location.sha256")

    root_absolute = abspath(root_directory)
    base_absolute = abspath(base_directory)
    _inside_root(base_absolute, root_absolute) ||
        fail(location, "base directory escapes the evidence root")

    lexical_path = normpath(joinpath(base_absolute, relative_path))
    _inside_root(lexical_path, root_absolute) ||
        fail("$location.path", "escapes the evidence root")
    isfile(lexical_path) ||
        fail("$location.path", "file does not exist: $lexical_path")

    root_real = realpath(root_absolute)
    base_relative = relpath(base_absolute, root_absolute)
    expected_real_path =
        normpath(joinpath(root_real, base_relative, relative_path))
    actual_real_path = realpath(lexical_path)
    _inside_root(actual_real_path, root_real) ||
        fail("$location.path", "resolves outside the evidence root")
    actual_real_path == expected_real_path ||
        fail("$location.path", "must not traverse a symbolic link")

    bytes = read(actual_real_path)
    actual_sha256 = bytes2hex(sha256(bytes))
    actual_sha256 == expected_sha256 ||
        fail(
        "$location.sha256",
        "declared $expected_sha256 does not match bytes $actual_sha256",
    )
    return (; bytes, path = actual_real_path, sha256 = actual_sha256)
end

function _validate_artifact(manifest)
    artifact = expect_exact_keys(
        manifest["artifact"],
        ("schema_version", "canonicalization", "content_sha256"),
        "evidence.artifact",
    )
    expect_exact(
        artifact["schema_version"],
        ROOT_SCHEMA_VERSION,
        "evidence.artifact.schema_version",
    )
    expect_exact(
        artifact["canonicalization"],
        CANONICALIZATION,
        "evidence.artifact.canonicalization",
    )
    declared =
        expect_hash(artifact["content_sha256"], "evidence.artifact.content_sha256")
    computed = computed_content_sha256(manifest)
    declared == computed ||
        fail(
        "evidence.artifact.content_sha256",
        "declared $declared does not match computed $computed",
    )
    return declared
end

function _validate_contract(contract)
    contract = expect_exact_keys(
        contract,
        (
            "contract_id",
            "protocol_id",
            "protocol_sha256",
            "evidence_class",
            "created_at_utc",
            "availability_status",
            "status_reason",
            "required_target_count",
            "required_truth_layers",
            "minimum_common_protocol_eligible_origins",
            "eligible_product_id",
            "eligible_origin_rule_id",
            "eligible_information_track",
        ),
        "evidence.contract",
    )
    expect_exact(
        contract["contract_id"],
        CONTRACT_ID,
        "evidence.contract.contract_id",
    )
    expect_exact(
        contract["protocol_id"],
        PROTOCOL_ID,
        "evidence.contract.protocol_id",
    )
    expect_exact(
        contract["protocol_sha256"],
        PROTOCOL_SHA256,
        "evidence.contract.protocol_sha256",
    )
    evidence_class = expect_one_of(
        contract["evidence_class"],
        EVIDENCE_CLASSES,
        "evidence.contract.evidence_class",
    )
    expect_timestamp(
        contract["created_at_utc"],
        "evidence.contract.created_at_utc",
    )
    availability_status = expect_one_of(
        contract["availability_status"],
        AVAILABILITY_STATUSES,
        "evidence.contract.availability_status",
    )
    expect_string(contract["status_reason"], "evidence.contract.status_reason")
    expect_exact(
        expect_integer(
            contract["required_target_count"],
            "evidence.contract.required_target_count";
            minimum = 1,
        ),
        length(EXPECTED_TARGET_IDS),
        "evidence.contract.required_target_count",
    )
    truth_layers = contract["required_truth_layers"]
    truth_layers isa AbstractVector ||
        fail("evidence.contract.required_truth_layers", "must be an array")
    layer_ids = [
        expect_string(
                layer,
                "evidence.contract.required_truth_layers[$index]",
            ) for (index, layer) in enumerate(truth_layers)
    ]
    layer_ids == collect(REQUIRED_TRUTH_LAYER_IDS) ||
        fail(
        "evidence.contract.required_truth_layers",
        "must equal $(join(REQUIRED_TRUTH_LAYER_IDS, ", ")) in order",
    )
    expect_exact(
        expect_integer(
            contract["minimum_common_protocol_eligible_origins"],
            "evidence.contract.minimum_common_protocol_eligible_origins";
            minimum = 1,
        ),
        MINIMUM_COMMON_ORIGINS,
        "evidence.contract.minimum_common_protocol_eligible_origins",
    )
    expect_exact(
        contract["eligible_product_id"],
        PRODUCT_ID,
        "evidence.contract.eligible_product_id",
    )
    expect_exact(
        contract["eligible_origin_rule_id"],
        ORIGIN_RULE_ID,
        "evidence.contract.eligible_origin_rule_id",
    )
    expect_exact(
        contract["eligible_information_track"],
        INFORMATION_TRACK,
        "evidence.contract.eligible_information_track",
    )
    return (; evidence_class, availability_status)
end

function _validate_reference_state(reference, location)
    status =
        expect_one_of(reference["status"], REFERENCE_STATUSES, "$location.status")
    path = expect_string(reference["manifest_path"], "$location.manifest_path")
    digest =
        expect_string(reference["manifest_sha256"], "$location.manifest_sha256")
    if status == "available"
        _validate_declared_path(path, "$location.manifest_path")
        expect_hash(digest, "$location.manifest_sha256")
    else
        path == NULL_ARTIFACT ||
            fail(
            "$location.manifest_path",
            "unavailable evidence must use '$NULL_ARTIFACT'",
        )
        digest == NULL_ARTIFACT ||
            fail(
            "$location.manifest_sha256",
            "unavailable evidence must use '$NULL_ARTIFACT'",
        )
    end
    return status
end

function _validate_truth_references(references)
    references isa AbstractVector ||
        fail("evidence.truth_manifests", "must be an array of tables")
    expected_keys = Set(
        (target_id, layer_id) for target_id in EXPECTED_TARGET_IDS for
            layer_id in REQUIRED_TRUTH_LAYER_IDS
    )
    seen = Set{Tuple{String, String}}()
    paths = Set{String}()
    available_count = 0
    validated = NamedTuple[]
    for (index, reference) in enumerate(references)
        location = "evidence.truth_manifests[$index]"
        reference = expect_exact_keys(
            reference,
            (
                "target_id",
                "truth_layer_id",
                "status",
                "manifest_path",
                "manifest_sha256",
            ),
            location,
        )
        target_id =
            expect_identifier(reference["target_id"], "$location.target_id")
        target_id in EXPECTED_TARGET_IDS ||
            fail("$location.target_id", "unexpected Tier-1 target '$target_id'")
        layer_id = expect_identifier(
            reference["truth_layer_id"],
            "$location.truth_layer_id",
        )
        layer_id in REQUIRED_TRUTH_LAYER_IDS ||
            fail(
            "$location.truth_layer_id",
            "unexpected truth layer '$layer_id'",
        )
        key = (target_id, layer_id)
        key in seen &&
            fail(location, "duplicates target/layer key $(join(key, "/"))")
        push!(seen, key)
        status = _validate_reference_state(reference, location)
        if status == "available"
            path = String(reference["manifest_path"])
            path in paths &&
                fail("$location.manifest_path", "must be unique")
            push!(paths, path)
            available_count += 1
        end
        push!(
            validated,
            (;
                target_id,
                layer_id,
                status,
                path = String(reference["manifest_path"]),
                sha256 = String(reference["manifest_sha256"]),
                location,
            ),
        )
    end
    seen == expected_keys ||
        fail(
        "evidence.truth_manifests",
        "must contain every Tier-1 target/truth-layer pair exactly once",
    )
    length(references) == length(expected_keys) ||
        fail("evidence.truth_manifests", "must contain exactly 24 entries")
    return (; references = validated, available_count)
end

function _validate_operator_references(references)
    references isa AbstractVector ||
        fail("evidence.operator_manifests", "must be an array of tables")
    seen = Set{String}()
    paths = Set{String}()
    available_count = 0
    validated = NamedTuple[]
    for (index, reference) in enumerate(references)
        location = "evidence.operator_manifests[$index]"
        reference = expect_exact_keys(
            reference,
            (
                "target_id",
                "operator_id",
                "status",
                "manifest_path",
                "manifest_sha256",
            ),
            location,
        )
        target_id =
            expect_identifier(reference["target_id"], "$location.target_id")
        haskey(EXPECTED_OPERATOR_IDS, target_id) ||
            fail("$location.target_id", "unexpected Tier-1 target '$target_id'")
        target_id in seen &&
            fail(location, "duplicates operator target '$target_id'")
        push!(seen, target_id)
        operator_id =
            expect_identifier(reference["operator_id"], "$location.operator_id")
        expected_operator = EXPECTED_OPERATOR_IDS[target_id]
        operator_id == expected_operator ||
            fail(
            "$location.operator_id",
            "expected '$expected_operator', got '$operator_id'",
        )
        status = _validate_reference_state(reference, location)
        if status == "available"
            path = String(reference["manifest_path"])
            path in paths &&
                fail("$location.manifest_path", "must be unique")
            push!(paths, path)
            available_count += 1
        end
        push!(
            validated,
            (;
                target_id,
                operator_id,
                status,
                path = String(reference["manifest_path"]),
                sha256 = String(reference["manifest_sha256"]),
                location,
            ),
        )
    end
    seen == Set(EXPECTED_TARGET_IDS) ||
        fail(
        "evidence.operator_manifests",
        "must contain every Tier-1 target operator exactly once",
    )
    length(references) == length(EXPECTED_TARGET_IDS) ||
        fail("evidence.operator_manifests", "must contain exactly eight entries")
    return (; references = validated, available_count)
end

function validate_evidence_manifest(manifest)
    manifest = expect_exact_keys(
        manifest,
        ("artifact", "contract", "truth_manifests", "operator_manifests"),
        "evidence",
    )
    contract = _validate_contract(manifest["contract"])
    truth = _validate_truth_references(manifest["truth_manifests"])
    operators = _validate_operator_references(manifest["operator_manifests"])
    available_count = truth.available_count + operators.available_count
    total_count =
        length(EXPECTED_TARGET_IDS) *
        (length(REQUIRED_TRUTH_LAYER_IDS) + 1)
    derived_status =
        available_count == 0 ?
        "unavailable" :
        available_count == total_count ? "candidate" : "partial"
    contract.availability_status == derived_status ||
        fail(
        "evidence.contract.availability_status",
        "declares $(contract.availability_status), derived $derived_status",
    )
    digest = _validate_artifact(manifest)
    return (;
        manifest,
        sha256 = digest,
        evidence_class = contract.evidence_class,
        availability_status = derived_status,
        truth_references = truth.references,
        operator_references = operators.references,
        available_truth_manifest_count = truth.available_count,
        available_operator_manifest_count = operators.available_count,
    )
end

evidence_manifest_sha256(manifest = load_evidence_manifest()) =
    validate_evidence_manifest(manifest).sha256

function _parse_resolved_toml(resolved, location)
    return _parse_toml_bytes(resolved.bytes, location)
end

function _parse_truth_artifact(resolved, reference, location)
    isempty(resolved.bytes) &&
        fail(location, "truth artifact must not be empty")
    isvalid(String, resolved.bytes) ||
        fail(location, "truth artifact must contain valid UTF-8")
    text = String(copy(resolved.bytes))
    occursin('\r', text) &&
        fail(location, "truth artifact must use LF line endings")
    endswith(text, '\n') ||
        fail(location, "truth artifact must end with one LF")

    lines = split(chop(text; tail = 1), '\n'; keepempty = true)
    expected_header =
        "target_id\ttruth_layer_id\torigin_id\treference_key\tvalue"
    isempty(lines) || first(lines) == expected_header ||
        fail(location, "truth artifact has an unsupported header")
    length(lines) >= 2 ||
        fail(location, "truth artifact must contain at least one value row")

    keys = Tuple{String, String}[]
    values = Float64[]
    for (index, line) in enumerate(Iterators.drop(lines, 1))
        row_location = "$location.rows[$index]"
        fields = split(line, '\t'; keepempty = true)
        length(fields) == 5 ||
            fail(row_location, "must contain exactly five tab-separated fields")
        target_id = expect_identifier(fields[1], "$row_location.target_id")
        expect_exact(
            target_id,
            reference.target_id,
            "$row_location.target_id",
        )
        layer_id =
            expect_identifier(fields[2], "$row_location.truth_layer_id")
        expect_exact(
            layer_id,
            reference.layer_id,
            "$row_location.truth_layer_id",
        )
        origin_id = expect_identifier(fields[3], "$row_location.origin_id")
        reference_key =
            expect_reference_key(fields[4], "$row_location.reference_key")
        value_text = expect_string(fields[5], "$row_location.value")
        occursin(
            r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$",
            value_text,
        ) || fail("$row_location.value", "must be a canonical decimal number")
        value = tryparse(Float64, value_text)
        value === nothing &&
            fail("$row_location.value", "could not parse numeric value")
        isfinite(value) ||
            fail("$row_location.value", "must be finite")
        push!(keys, (origin_id, reference_key))
        push!(values, value)
    end
    length(keys) == length(Set(keys)) ||
        fail(location, "truth artifact contains duplicate origin/reference keys")
    issorted(keys) ||
        fail(location, "truth artifact rows must be sorted by origin/reference key")
    return (; keys = Set(keys), row_count = length(keys), values)
end

function _validate_truth_observation(
        observation,
        location,
        origin_bindings,
        seen_keys,
    )
    observation = expect_exact_keys(
        observation,
        (
            "origin_id",
            "origin_timestamp_utc",
            "reference_key",
            "product_id",
            "origin_rule_id",
            "information_track",
            "protocol_eligible",
            "origin_evidence_sha256",
        ),
        location,
    )
    origin_id =
        expect_identifier(observation["origin_id"], "$location.origin_id")
    timestamp_text = expect_string(
        observation["origin_timestamp_utc"],
        "$location.origin_timestamp_utc",
    )
    expect_timestamp(timestamp_text, "$location.origin_timestamp_utc")
    reference_key =
        expect_reference_key(observation["reference_key"], "$location.reference_key")
    expect_exact(
        observation["product_id"],
        PRODUCT_ID,
        "$location.product_id",
    )
    expect_exact(
        observation["origin_rule_id"],
        ORIGIN_RULE_ID,
        "$location.origin_rule_id",
    )
    expect_exact(
        observation["information_track"],
        INFORMATION_TRACK,
        "$location.information_track",
    )
    eligible =
        expect_bool(observation["protocol_eligible"], "$location.protocol_eligible")
    evidence_digest = expect_string(
        observation["origin_evidence_sha256"],
        "$location.origin_evidence_sha256",
    )
    if eligible
        expect_hash(evidence_digest, "$location.origin_evidence_sha256")
    else
        evidence_digest == NULL_ARTIFACT ||
            fail(
            "$location.origin_evidence_sha256",
            "ineligible origins must use '$NULL_ARTIFACT'",
        )
    end

    key = (origin_id, reference_key)
    key in seen_keys &&
        fail(location, "duplicates origin/reference key $(join(key, "/"))")
    push!(seen_keys, key)

    binding = (timestamp_text, eligible, evidence_digest)
    if haskey(origin_bindings, origin_id)
        origin_bindings[origin_id] == binding ||
            fail(
            "$location.origin_id",
            "origin '$origin_id' has conflicting eligibility metadata",
        )
    else
        origin_bindings[origin_id] = binding
    end
    return (; origin_id, reference_key, key, eligible)
end

function _verify_truth_manifest(
        root_directory,
        reference,
        evidence_class,
    )
    resolved = _resolve_bytes(
        root_directory,
        root_directory,
        reference.path,
        reference.sha256,
        reference.location,
    )
    document =
        _parse_resolved_toml(resolved, "$(reference.location).manifest")
    document = expect_exact_keys(
        document,
        ("truth", "observations"),
        "$(reference.location).manifest",
    )
    truth = expect_exact_keys(
        document["truth"],
        (
            "schema_version",
            "manifest_id",
            "target_id",
            "truth_layer_id",
            "protocol_id",
            "protocol_sha256",
            "evidence_class",
            "truth_artifact_format",
            "truth_artifact_path",
            "truth_artifact_sha256",
            "observation_count",
        ),
        "$(reference.location).manifest.truth",
    )
    truth_location = "$(reference.location).manifest.truth"
    expect_exact(
        truth["schema_version"],
        TRUTH_SCHEMA_VERSION,
        "$truth_location.schema_version",
    )
    expected_manifest_id =
        "$(reference.target_id).$(reference.layer_id).truth.v1"
    expect_exact(
        truth["manifest_id"],
        expected_manifest_id,
        "$truth_location.manifest_id",
    )
    expect_exact(
        truth["target_id"],
        reference.target_id,
        "$truth_location.target_id",
    )
    expect_exact(
        truth["truth_layer_id"],
        reference.layer_id,
        "$truth_location.truth_layer_id",
    )
    expect_exact(truth["protocol_id"], PROTOCOL_ID, "$truth_location.protocol_id")
    expect_exact(
        truth["protocol_sha256"],
        PROTOCOL_SHA256,
        "$truth_location.protocol_sha256",
    )
    expect_exact(
        truth["evidence_class"],
        evidence_class,
        "$truth_location.evidence_class",
    )
    expect_exact(
        truth["truth_artifact_format"],
        TRUTH_ARTIFACT_FORMAT,
        "$truth_location.truth_artifact_format",
    )
    observation_count = expect_integer(
        truth["observation_count"],
        "$truth_location.observation_count";
        minimum = 1,
    )

    manifest_directory = dirname(resolved.path)
    truth_artifact = _resolve_bytes(
        root_directory,
        manifest_directory,
        truth["truth_artifact_path"],
        truth["truth_artifact_sha256"],
        "$truth_location.truth_artifact",
    )
    artifact_rows = _parse_truth_artifact(
        truth_artifact,
        reference,
        "$truth_location.truth_artifact",
    )

    observations = document["observations"]
    observations isa AbstractVector ||
        fail(
        "$(reference.location).manifest.observations",
        "must be an array of tables",
    )
    length(observations) == observation_count ||
        fail(
        "$truth_location.observation_count",
        "declares $observation_count, found $(length(observations)) observations",
    )
    seen_keys = Set{Tuple{String, String}}()
    manifest_keys = Set{Tuple{String, String}}()
    origin_bindings =
        Dict{String, Tuple{String, Bool, String}}()
    eligible_origins = Set{String}()
    for (index, observation) in enumerate(observations)
        result = _validate_truth_observation(
            observation,
            "$(reference.location).manifest.observations[$index]",
            origin_bindings,
            seen_keys,
        )
        result.eligible && push!(eligible_origins, result.origin_id)
        push!(manifest_keys, result.key)
    end
    artifact_rows.row_count == observation_count ||
        fail(
        "$truth_location.observation_count",
        "declares $observation_count observations but the truth artifact contains $(artifact_rows.row_count) rows",
    )
    artifact_rows.keys == manifest_keys ||
        fail(
        "$truth_location.truth_artifact",
        "truth artifact keys do not match manifest observation keys",
    )
    return (;
        target_id = reference.target_id,
        layer_id = reference.layer_id,
        manifest_path = resolved.path,
        manifest_sha256 = resolved.sha256,
        truth_artifact_path = truth_artifact.path,
        truth_artifact_sha256 = truth_artifact.sha256,
        truth_artifact_format = TRUTH_ARTIFACT_FORMAT,
        truth_value_count = artifact_rows.row_count,
        observation_count,
        eligible_origins,
        origin_bindings,
    )
end

function _validate_validation_receipt(
        document,
        location,
        reference,
        evidence_class,
        operator_artifact_sha256,
        validation_artifact_sha256,
    )
    document =
        expect_exact_keys(document, ("receipt",), location)
    receipt = expect_exact_keys(
        document["receipt"],
        (
            "schema_version",
            "receipt_id",
            "target_id",
            "operator_id",
            "protocol_id",
            "protocol_sha256",
            "evidence_class",
            "operator_artifact_sha256",
            "validation_artifact_sha256",
            "decision",
            "validator_id",
            "validator_role",
            "issued_at_utc",
        ),
        "$location.receipt",
    )
    receipt_location = "$location.receipt"
    expect_exact(
        receipt["schema_version"],
        VALIDATION_RECEIPT_SCHEMA_VERSION,
        "$receipt_location.schema_version",
    )
    receipt_id =
        expect_identifier(receipt["receipt_id"], "$receipt_location.receipt_id")
    expect_exact(
        receipt["target_id"],
        reference.target_id,
        "$receipt_location.target_id",
    )
    expect_exact(
        receipt["operator_id"],
        reference.operator_id,
        "$receipt_location.operator_id",
    )
    expect_exact(
        receipt["protocol_id"],
        PROTOCOL_ID,
        "$receipt_location.protocol_id",
    )
    expect_exact(
        receipt["protocol_sha256"],
        PROTOCOL_SHA256,
        "$receipt_location.protocol_sha256",
    )
    expect_exact(
        receipt["evidence_class"],
        evidence_class,
        "$receipt_location.evidence_class",
    )
    expect_exact(
        receipt["operator_artifact_sha256"],
        operator_artifact_sha256,
        "$receipt_location.operator_artifact_sha256",
    )
    expect_exact(
        receipt["validation_artifact_sha256"],
        validation_artifact_sha256,
        "$receipt_location.validation_artifact_sha256",
    )
    expect_exact(receipt["decision"], "approved", "$receipt_location.decision")
    validator_id =
        expect_identifier(receipt["validator_id"], "$receipt_location.validator_id")
    expect_exact(
        receipt["validator_role"],
        "independent_validation",
        "$receipt_location.validator_role",
    )
    issued_at = expect_timestamp(
        receipt["issued_at_utc"],
        "$receipt_location.issued_at_utc",
    )
    return (; receipt_id, validator_id, issued_at)
end

function _validate_signoff_receipt(
        document,
        location,
        reference,
        evidence_class,
        operator_artifact_sha256,
        validation_artifact_sha256,
        validation_receipt_sha256,
    )
    document =
        expect_exact_keys(document, ("receipt",), location)
    receipt = expect_exact_keys(
        document["receipt"],
        (
            "schema_version",
            "receipt_id",
            "target_id",
            "operator_id",
            "protocol_id",
            "protocol_sha256",
            "evidence_class",
            "operator_artifact_sha256",
            "validation_artifact_sha256",
            "validation_receipt_sha256",
            "decision",
            "signatory_id",
            "signatory_role",
            "issued_at_utc",
        ),
        "$location.receipt",
    )
    receipt_location = "$location.receipt"
    expect_exact(
        receipt["schema_version"],
        SIGNOFF_RECEIPT_SCHEMA_VERSION,
        "$receipt_location.schema_version",
    )
    receipt_id =
        expect_identifier(receipt["receipt_id"], "$receipt_location.receipt_id")
    expect_exact(
        receipt["target_id"],
        reference.target_id,
        "$receipt_location.target_id",
    )
    expect_exact(
        receipt["operator_id"],
        reference.operator_id,
        "$receipt_location.operator_id",
    )
    expect_exact(
        receipt["protocol_id"],
        PROTOCOL_ID,
        "$receipt_location.protocol_id",
    )
    expect_exact(
        receipt["protocol_sha256"],
        PROTOCOL_SHA256,
        "$receipt_location.protocol_sha256",
    )
    expect_exact(
        receipt["evidence_class"],
        evidence_class,
        "$receipt_location.evidence_class",
    )
    expect_exact(
        receipt["operator_artifact_sha256"],
        operator_artifact_sha256,
        "$receipt_location.operator_artifact_sha256",
    )
    expect_exact(
        receipt["validation_artifact_sha256"],
        validation_artifact_sha256,
        "$receipt_location.validation_artifact_sha256",
    )
    expect_exact(
        receipt["validation_receipt_sha256"],
        validation_receipt_sha256,
        "$receipt_location.validation_receipt_sha256",
    )
    expect_exact(receipt["decision"], "approved", "$receipt_location.decision")
    signatory_id = expect_identifier(
        receipt["signatory_id"],
        "$receipt_location.signatory_id",
    )
    expect_exact(
        receipt["signatory_role"],
        "research_lead",
        "$receipt_location.signatory_role",
    )
    issued_at = expect_timestamp(
        receipt["issued_at_utc"],
        "$receipt_location.issued_at_utc",
    )
    return (; receipt_id, signatory_id, issued_at)
end

function _verify_operator_manifest(
        root_directory,
        reference,
        evidence_class,
    )
    resolved = _resolve_bytes(
        root_directory,
        root_directory,
        reference.path,
        reference.sha256,
        reference.location,
    )
    document =
        _parse_resolved_toml(resolved, "$(reference.location).manifest")
    document = expect_exact_keys(
        document,
        ("operator",),
        "$(reference.location).manifest",
    )
    operator = expect_exact_keys(
        document["operator"],
        (
            "schema_version",
            "manifest_id",
            "target_id",
            "operator_id",
            "protocol_id",
            "protocol_sha256",
            "evidence_class",
            "operator_artifact_path",
            "operator_artifact_sha256",
            "validation_artifact_path",
            "validation_artifact_sha256",
            "validation_receipt_path",
            "validation_receipt_sha256",
            "signoff_receipt_path",
            "signoff_receipt_sha256",
        ),
        "$(reference.location).manifest.operator",
    )
    operator_location = "$(reference.location).manifest.operator"
    expect_exact(
        operator["schema_version"],
        OPERATOR_SCHEMA_VERSION,
        "$operator_location.schema_version",
    )
    expect_exact(
        operator["manifest_id"],
        "$(reference.target_id).operator.v1",
        "$operator_location.manifest_id",
    )
    expect_exact(
        operator["target_id"],
        reference.target_id,
        "$operator_location.target_id",
    )
    expect_exact(
        operator["operator_id"],
        reference.operator_id,
        "$operator_location.operator_id",
    )
    expect_exact(
        operator["protocol_id"],
        PROTOCOL_ID,
        "$operator_location.protocol_id",
    )
    expect_exact(
        operator["protocol_sha256"],
        PROTOCOL_SHA256,
        "$operator_location.protocol_sha256",
    )
    expect_exact(
        operator["evidence_class"],
        evidence_class,
        "$operator_location.evidence_class",
    )

    manifest_directory = dirname(resolved.path)
    operator_artifact = _resolve_bytes(
        root_directory,
        manifest_directory,
        operator["operator_artifact_path"],
        operator["operator_artifact_sha256"],
        "$operator_location.operator_artifact",
    )
    validation_artifact = _resolve_bytes(
        root_directory,
        manifest_directory,
        operator["validation_artifact_path"],
        operator["validation_artifact_sha256"],
        "$operator_location.validation_artifact",
    )
    isempty(operator_artifact.bytes) &&
        fail(
        "$operator_location.operator_artifact",
        "operator artifact must not be empty",
    )
    isempty(validation_artifact.bytes) &&
        fail(
        "$operator_location.validation_artifact",
        "validation artifact must not be empty",
    )
    validation_receipt = _resolve_bytes(
        root_directory,
        manifest_directory,
        operator["validation_receipt_path"],
        operator["validation_receipt_sha256"],
        "$operator_location.validation_receipt",
    )
    signoff_receipt = _resolve_bytes(
        root_directory,
        manifest_directory,
        operator["signoff_receipt_path"],
        operator["signoff_receipt_sha256"],
        "$operator_location.signoff_receipt",
    )
    bundle_paths = (
        operator_artifact.path,
        validation_artifact.path,
        validation_receipt.path,
        signoff_receipt.path,
    )
    length(Set(bundle_paths)) == length(bundle_paths) ||
        fail(
        operator_location,
        "operator, validation, and receipt paths must be distinct",
    )
    bundle_hashes = (
        operator_artifact.sha256,
        validation_artifact.sha256,
        validation_receipt.sha256,
        signoff_receipt.sha256,
    )
    length(Set(bundle_hashes)) == length(bundle_hashes) ||
        fail(
        operator_location,
        "operator, validation, and receipt byte hashes must be distinct",
    )

    validation = _validate_validation_receipt(
        _parse_resolved_toml(
            validation_receipt,
            "$operator_location.validation_receipt",
        ),
        "$operator_location.validation_receipt",
        reference,
        evidence_class,
        operator_artifact.sha256,
        validation_artifact.sha256,
    )
    signoff = _validate_signoff_receipt(
        _parse_resolved_toml(
            signoff_receipt,
            "$operator_location.signoff_receipt",
        ),
        "$operator_location.signoff_receipt",
        reference,
        evidence_class,
        operator_artifact.sha256,
        validation_artifact.sha256,
        validation_receipt.sha256,
    )
    validation.receipt_id != signoff.receipt_id ||
        fail(
        "$operator_location.signoff_receipt",
        "validation and signoff receipt IDs must be distinct",
    )
    validation.validator_id != signoff.signatory_id ||
        fail(
        "$operator_location.signoff_receipt",
        "validator and signatory must be distinct people",
    )
    validation.issued_at <= signoff.issued_at ||
        fail(
        "$operator_location.signoff_receipt",
        "signoff must not predate independent validation",
    )
    return (;
        target_id = reference.target_id,
        operator_id = reference.operator_id,
        manifest_path = resolved.path,
        manifest_sha256 = resolved.sha256,
        operator_artifact_path = operator_artifact.path,
        operator_artifact_sha256 = operator_artifact.sha256,
        validation_artifact_path = validation_artifact.path,
        validation_artifact_sha256 = validation_artifact.sha256,
        validation_receipt_path = validation_receipt.path,
        validation_receipt_sha256 = validation_receipt.sha256,
        validation_receipt_id = validation.receipt_id,
        signoff_receipt_path = signoff_receipt.path,
        signoff_receipt_sha256 = signoff_receipt.sha256,
        signoff_receipt_id = signoff.receipt_id,
    )
end

function _merge_origin_bindings!(global_bindings, local_bindings, location)
    for (origin_id, binding) in local_bindings
        if haskey(global_bindings, origin_id)
            global_bindings[origin_id] == binding ||
                fail(
                location,
                "origin '$origin_id' conflicts across truth manifests",
            )
        else
            global_bindings[origin_id] = binding
        end
    end
    return global_bindings
end

function _require_distinct_eligible_origins(global_bindings)
    timestamps = Dict{String, String}()
    evidence_hashes = Dict{String, String}()
    for origin_id in sort!(collect(keys(global_bindings)))
        timestamp, eligible, evidence_hash = global_bindings[origin_id]
        eligible || continue
        if haskey(timestamps, timestamp)
            fail(
                "evidence.truth_manifests",
                "eligible origins '$origin_id' and '$(timestamps[timestamp])' alias timestamp $timestamp",
            )
        end
        timestamps[timestamp] = origin_id
        if haskey(evidence_hashes, evidence_hash)
            fail(
                "evidence.truth_manifests",
                "eligible origins '$origin_id' and '$(evidence_hashes[evidence_hash])' alias origin-evidence hash $evidence_hash",
            )
        end
        evidence_hashes[evidence_hash] = origin_id
    end
    return nothing
end

function _require_unique_operator_receipts(operator_results)
    fields = (
        ("validation_receipt_path", "validation receipt paths"),
        ("validation_receipt_sha256", "validation receipt hashes"),
        ("validation_receipt_id", "validation receipt IDs"),
        ("signoff_receipt_path", "signoff receipt paths"),
        ("signoff_receipt_sha256", "signoff receipt hashes"),
        ("signoff_receipt_id", "signoff receipt IDs"),
    )
    for (field, label) in fields
        values = [getfield(result, Symbol(field)) for result in operator_results]
        length(values) == length(Set(values)) ||
            fail("evidence.operator_manifests", "$label must be unique")
    end
    all_receipt_ids = String[]
    for result in operator_results
        push!(all_receipt_ids, result.validation_receipt_id)
        push!(all_receipt_ids, result.signoff_receipt_id)
    end
    length(all_receipt_ids) == length(Set(all_receipt_ids)) ||
        fail("evidence.operator_manifests", "all receipt IDs must be unique")
    return nothing
end

function verify_evidence(path::AbstractString = DEFAULT_EVIDENCE_PATH)
    manifest = load_evidence_manifest(path)
    validation = validate_evidence_manifest(manifest)
    root_directory = dirname(realpath(abspath(path)))
    blockers = String[]
    truth_results = NamedTuple[]
    operator_results = NamedTuple[]
    global_origin_bindings =
        Dict{String, Tuple{String, Bool, String}}()

    for reference in validation.truth_references
        if reference.status == "unavailable"
            push!(
                blockers,
                "$(reference.target_id)/$(reference.layer_id) truth manifest is unavailable",
            )
            continue
        end
        result = _verify_truth_manifest(
            root_directory,
            reference,
            validation.evidence_class,
        )
        _merge_origin_bindings!(
            global_origin_bindings,
            result.origin_bindings,
            reference.location,
        )
        push!(truth_results, result)
    end

    for reference in validation.operator_references
        if reference.status == "unavailable"
            push!(
                blockers,
                "$(reference.target_id) operator manifest is unavailable",
            )
            continue
        end
        push!(
            operator_results,
            _verify_operator_manifest(
                root_directory,
                reference,
                validation.evidence_class,
            ),
        )
    end
    _require_unique_operator_receipts(operator_results)
    _require_distinct_eligible_origins(global_origin_bindings)

    required_truth_count =
        length(EXPECTED_TARGET_IDS) * length(REQUIRED_TRUTH_LAYER_IDS)
    common_origins = Set{String}()
    if length(truth_results) == required_truth_count
        common_origins = copy(first(truth_results).eligible_origins)
        for result in Iterators.drop(truth_results, 1)
            intersect!(common_origins, result.eligible_origins)
        end
    end
    common_origin_ids = sort!(collect(common_origins))
    common_origin_count = length(common_origin_ids)
    common_origin_count >= MINIMUM_COMMON_ORIGINS ||
        push!(
        blockers,
        "common protocol-eligible origin intersection is $common_origin_count/$(MINIMUM_COMMON_ORIGINS)",
    )

    integrity_verified =
        isempty(blockers) &&
        length(truth_results) == required_truth_count &&
        length(operator_results) == length(EXPECTED_TARGET_IDS)
    integrity_blockers = copy(blockers)
    if integrity_verified
        push!(
            blockers,
            "upstream origin-evidence bytes are digest-bound but not resolved against the source-release/origin registries",
        )
        push!(
            blockers,
            "origin-by-horizon reference quarters and first/near-mature/mature release semantics are not yet verified",
        )
        push!(
            blockers,
            "receipt identities are integrity-bound strings, not authenticated external approvals",
        )
        validation.evidence_class == PROMOTION_EVIDENCE_CLASS ||
            push!(
            blockers,
            "evidence class '$(validation.evidence_class)' is not promotion-eligible retrospective evidence",
        )
    end
    verified = false
    status = if !integrity_verified
        "NOT_VERIFIED"
    elseif validation.evidence_class == "synthetic_test_only"
        "VERIFIED_TEST_FIXTURE"
    elseif validation.evidence_class == "repository_audit"
        "BUNDLE_INTEGRITY_VERIFIED_AUDIT"
    else
        "BUNDLE_INTEGRITY_VERIFIED"
    end
    return (;
        verified,
        integrity_verified,
        promotion_eligible = false,
        status,
        verification_scope = "local_bundle_integrity_only",
        evidence_class = validation.evidence_class,
        evidence_manifest_sha256 = validation.sha256,
        available_truth_manifest_count = length(truth_results),
        available_operator_manifest_count = length(operator_results),
        common_origin_count,
        common_origin_ids,
        blockers,
        integrity_blockers,
        truth_results,
        operator_results,
    )
end

function require_integrity_verified(
        path::AbstractString = DEFAULT_EVIDENCE_PATH,
    )
    result = verify_evidence(path)
    result.integrity_verified ||
        fail(
        "evidence",
        "bundle integrity verification failed: $(join(result.integrity_blockers, "; "))",
    )
    return result
end

function require_verified_evidence(path::AbstractString = DEFAULT_EVIDENCE_PATH)
    result = verify_evidence(path)
    result.verified ||
        fail(
        "evidence",
        "verification failed: $(join(result.blockers, "; "))",
    )
    return result
end

end
