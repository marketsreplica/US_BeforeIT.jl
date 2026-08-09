module USCommonOriginAcquisitionV3

using Dates
using SHA
using TOML

export CommonOriginAcquisitionError,
    canonical_sha256,
    load_parent,
    load_policy,
    validate_result,
    verify_parent

const POLICY_SCHEMA = "beforeit-us-common-origin-acquisition-policy.v3"
const POLICY_ID = "beforeit-us-common-origin-acquisition-composition.v3"
const PARENT_SCHEMA = "beforeit-us-common-origin-acquisition-parent.v3"
const LEAF_SCHEMA = "beforeit-us-prospective-profile-verification-receipt.v1"
const RETENTION_SCHEMA = "beforeit-us-retention-custody-covenant.v2"
const RESULT_SCHEMA = "beforeit-us-common-origin-acquisition-result.v3"
const CANONICALIZATION =
    "sorted-typed-length-prefixed-v1-excluding-artifact-content-sha256"
const CANNOT_RUN = "CANNOT_RUN"
const READY_FOR_SEAL = "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
const CURRENT_POLICY_READY_REACHABLE = false
const ORIGIN_ID = "origin.2026q3.prospective-capture-candidate.v2"
const ORIGIN_QUARTER = "2026Q3"
const ORIGIN_TIMESTAMP = "2026-10-30T14:00:00Z"
const ORIGIN_RULE =
    "FIRST_BUSINESS_DAY_AFTER_BEA_ADVANCE_AT_10:00_AMERICA/NEW_YORK"
const MINIMUM_RETAIN_UNTIL = "2034-09-30T23:59:59Z"
const MAXIMUM_TARGET_PERIOD_END = "2029-09-30T23:59:59Z"
const MAXIMUM_TARGET_QUARTER = "2029Q3"
const DELETION_RELEASE_RULE =
    "ONLY_AFTER_CALENDAR_BOUNDARY_AND_LAST_REQUIRED_MATURE_TRUTH_RECEIPT_COMPLETION_EXTERNAL_TIMESTAMP_DURABLE_REPLICATION_AND_INDEPENDENT_AUDIT"
const LEGACY_V2_MODULE_SHA256 =
    "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379"
const LEGACY_V2_CONTRACT_SHA256 =
    "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
const LEGACY_V2_SEMANTIC_SHA256 =
    "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
const OPAQUE_AUDIT_TUPLE_SHA256 =
    "9fa271ea0bc646c8f3789084d8c61e04e2b31c4c5e4eeb6b551a217499ac75fb"
const TYPED_LENGTH_TUPLE_SHA256 =
    "bff32b3b46270818e0e7d487173c1676df7d286c1d6846c16a2977d1bff20299"
const POLICY_PHYSICAL_SHA256 =
    "0deff5e3e6c950b5682bba96fcefa1fa2304bbbadae6227a940376dc7699bd3e"
const POLICY_CONTENT_SHA256 =
    "a69392029c2221ab5f490311c02d09a667e71982c486a1612100c1d6dcd96d13"
const POLICY_RELATIVE_PATH =
    "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/common_origin_acquisition_v3_policy.toml"
const LEGACY_CONTRACT_RELATIVE_PATH =
    "scripts/us/forecasting/vintages/prospective/prospective_2026q3_contract_v2.toml"
const REPOSITORY_ROOT = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."),
)
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const RFC3339_PATTERN = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
const MAXIMUM_METADATA_FILE_BYTES = 16_777_216
const MAXIMUM_RAW_OR_REPLICA_FILE_BYTES = 536_870_912
const MAXIMUM_TIMESTAMP_TOKEN_BYTES = 16_777_216
const MAXIMUM_TOTAL_RAW_BYTES_PER_PROFILE = 1_073_741_824
const MAXIMUM_TOTAL_REPLICA_BYTES_PER_PROFILE = 2_147_483_648
const MAXIMUM_TOTAL_RAW_BYTES_PER_PARENT = 68_719_476_736
const MAXIMUM_TOTAL_REPLICA_BYTES_PER_PARENT = 137_438_953_472
const MAXIMUM_RAW_ARTIFACTS_PER_PROFILE = 32
const MAXIMUM_REPLICAS_PER_PROFILE = 64
const MAXIMUM_CATALOG_CANDIDATES_PER_PROFILE = 256
const MAXIMUM_VECTOR_ITEMS = 4_096
const MAXIMUM_TABLE_ENTRIES = 4_096
const MAXIMUM_STRING_BYTES = 1_048_576
const MAXIMUM_IDENTIFIER_BYTES = 512
const MAXIMUM_RELATIVE_PATH_BYTES = 4_096
const MAXIMUM_PATH_COMPONENT_BYTES = 255
const MAXIMUM_PATH_COMPONENTS = 128

const GATE_KEYS = Set(
    [
        "origin_admission_allowed",
        "forecast_execution_allowed",
        "truth_access_allowed",
        "scoring_allowed",
        "accuracy_claim_allowed",
        "promotion_allowed",
        "production_allowed",
    ],
)
const SOURCE_BINDING_KEYS = Set(["binding_id", "path", "sha256", "kind"])
const DISPATCH_KEYS = Set(
    [
        "dispatch_id",
        "receipt_schema_version",
        "requirement_id",
        "source_id",
        "evidence_role",
        "qualified",
        "leaf_verifier_id",
        "leaf_verifier_version",
        "leaf_verifier_source_path",
        "leaf_verifier_source_sha256",
        "leaf_verifier_test_path",
        "leaf_verifier_test_sha256",
        "claim_schema_version",
        "independent_validation_receipt_schema_version",
        "allowed_profile_ids",
        "permitted_media_types",
        "permitted_artifact_roles",
        "blocker_ids",
    ],
)
const PARENT_ROW_KEYS = Set(
    [
        "legacy_requirement_id",
        "legacy_profile_id",
        "active_profile_id",
        "dispatch_id",
        "receipt_path",
        "receipt_sha256",
        "supersession_decision_sha256",
    ],
)

struct CommonOriginAcquisitionError <: Exception
    code::Symbol
    message::String
end

Base.showerror(io::IO, error::CommonOriginAcquisitionError) =
    print(io, "common-origin acquisition v3 ", error.code, ": ", error.message)

fail(code::Symbol, message) =
    throw(CommonOriginAcquisitionError(code, String(message)))

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(SHA.sha256(bytes))

function _emit_length(io::IO, count::Integer)
    count >= 0 || fail(:canonicalization, "negative canonical length")
    write(io, string(count), ':')
    return nothing
end

function _emit_canonical(io::IO, value, depth = 0)
    depth <= 64 || fail(:resource_limit, "canonical value exceeds the nesting-depth ceiling")
    if value === nothing
        write(io, "N;")
    elseif value isa Bool
        write(io, value ? "B1;" : "B0;")
    elseif value isa Integer
        encoded = codeunits(string(value))
        write(io, 'I')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractFloat
        isfinite(value) || fail(:canonicalization, "nonfinite float")
        encoded = codeunits(bitstring(Float64(value)))
        write(io, 'F')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractString
        ncodeunits(value) <= MAXIMUM_STRING_BYTES ||
            fail(:resource_limit, "canonical string exceeds the frozen byte ceiling")
        encoded = codeunits(String(value))
        write(io, 'S')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractVector
        length(value) <= MAXIMUM_VECTOR_ITEMS ||
            fail(:resource_limit, "canonical array exceeds the frozen item ceiling")
        write(io, 'A')
        _emit_length(io, length(value))
        for item in value
            _emit_canonical(io, item, depth + 1)
        end
        write(io, ';')
    elseif value isa AbstractDict
        length(value) <= MAXIMUM_TABLE_ENTRIES ||
            fail(:resource_limit, "canonical table exceeds the frozen entry ceiling")
        all(key -> key isa AbstractString, keys(value)) ||
            fail(:canonicalization, "dictionary keys must be strings")
        all(key -> ncodeunits(key) <= MAXIMUM_IDENTIFIER_BYTES, keys(value)) ||
            fail(:resource_limit, "canonical table has an oversized key")
        ordered = sort!(String.(collect(keys(value))))
        write(io, 'D')
        _emit_length(io, length(ordered))
        for key in ordered
            _emit_canonical(io, key, depth + 1)
            _emit_canonical(io, value[key], depth + 1)
        end
        write(io, ';')
    else
        fail(:canonicalization, "unsupported value type $(typeof(value))")
    end
    return nothing
end

function canonical_sha256(value)
    io = IOBuffer()
    _emit_canonical(io, value)
    return sha256_hex(take!(io))
end

function _without_content_hash(document::AbstractDict)
    _validate_value_bounds(document, "document")
    payload = deepcopy(document)
    artifact = _expect_table(get(payload, "artifact", nothing), "artifact")
    pop!(artifact, "content_sha256", nothing)
    return payload
end

document_content_sha256(document::AbstractDict) =
    canonical_sha256(_without_content_hash(document))

function _validate_value_bounds(value, location; depth = 0)
    depth <= 64 || fail(:resource_limit, "$location exceeds the frozen nesting-depth ceiling")
    if value isa AbstractString
        ncodeunits(value) <= MAXIMUM_STRING_BYTES ||
            fail(:resource_limit, "$location exceeds the frozen string byte ceiling")
    elseif value isa AbstractVector
        length(value) <= MAXIMUM_VECTOR_ITEMS ||
            fail(:resource_limit, "$location exceeds the frozen vector-item ceiling")
        for (index, item) in enumerate(value)
            _validate_value_bounds(item, "$location[$index]"; depth = depth + 1)
        end
    elseif value isa AbstractDict
        length(value) <= MAXIMUM_TABLE_ENTRIES ||
            fail(:resource_limit, "$location exceeds the frozen table-entry ceiling")
        for (key, item) in pairs(value)
            key isa AbstractString || fail(:invalid_schema, "$location has a non-string key")
            ncodeunits(key) <= MAXIMUM_IDENTIFIER_BYTES ||
                fail(:resource_limit, "$location has an oversized key")
            _validate_value_bounds(item, "$location.$key"; depth = depth + 1)
        end
    end
    return value
end

function _expect_table(value, location)
    value isa AbstractDict || fail(:invalid_schema, "$location must be a table")
    length(value) <= MAXIMUM_TABLE_ENTRIES ||
        fail(:resource_limit, "$location exceeds the frozen table-entry ceiling")
    return value
end

function _expect_vector(value, location; maximum_items = MAXIMUM_VECTOR_ITEMS)
    value isa AbstractVector || fail(:invalid_schema, "$location must be an array")
    length(value) <= maximum_items ||
        fail(:resource_limit, "$location exceeds the frozen item ceiling $maximum_items")
    return value
end

function _expect_string_vector(value, location; maximum_items = MAXIMUM_VECTOR_ITEMS)
    array = _expect_vector(value, location; maximum_items = maximum_items)
    result = String[]
    sizehint!(result, length(array))
    for (index, item) in enumerate(array)
        push!(result, _expect_string(item, "$location[$index]"))
    end
    return result
end

function _expect_string(value, location; maximum_bytes = MAXIMUM_STRING_BYTES)
    value isa AbstractString || fail(:invalid_schema, "$location must be a string")
    ncodeunits(value) <= maximum_bytes ||
        fail(:resource_limit, "$location exceeds the frozen byte ceiling $maximum_bytes")
    return String(value)
end

function _expect_bool(value, location)
    value isa Bool || fail(:invalid_schema, "$location must be boolean")
    return value
end

function _expect_integer(value, location)
    value isa Integer && !(value isa Bool) ||
        fail(:invalid_schema, "$location must be an integer")
    return Int(value)
end

function _expect_exact_integer(value, expected, location; code = :binding_mismatch)
    observed = _expect_integer(value, location)
    observed == expected ||
        fail(code, "$location expected $(repr(expected)), got $(repr(observed))")
    return observed
end

function _bounded_add(total, increment, maximum, location)
    for (value, label) in [(total, "total"), (increment, "increment"), (maximum, "maximum")]
        value isa Integer && !(value isa Bool) ||
            fail(:resource_limit, "$location $label must be an integer")
        value >= 0 || fail(:resource_limit, "$location $label must be nonnegative")
    end
    total <= maximum - increment ||
        fail(:resource_limit, "$location exceeds the frozen aggregate byte ceiling")
    return total + increment
end

function _expect_hash(value, location)
    text = _expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(:invalid_hash, "$location must be lowercase SHA-256")
    return text
end

function _expect_identifier(value, location)
    text = _expect_string(value, location; maximum_bytes = MAXIMUM_IDENTIFIER_BYTES)
    occursin(IDENTIFIER_PATTERN, text) ||
        fail(:invalid_identifier, "$location is not a closed identifier")
    return text
end

function _expect_exact_keys(table::AbstractDict, expected, location)
    length(table) <= MAXIMUM_TABLE_ENTRIES ||
        fail(:resource_limit, "$location exceeds the frozen table-entry ceiling")
    all(key -> key isa AbstractString, keys(table)) ||
        fail(:invalid_schema, "$location keys must be strings")
    all(key -> ncodeunits(key) <= MAXIMUM_IDENTIFIER_BYTES, keys(table)) ||
        fail(:resource_limit, "$location has an oversized key")
    actual = Set(String.(collect(keys(table))))
    wanted = Set(String.(collect(expected)))
    actual == wanted || begin
        missing = sort!(collect(setdiff(wanted, actual)))
        extra = sort!(collect(setdiff(actual, wanted)))
        fail(
            :invalid_schema,
            "$location keys differ; missing=$(join(missing, ',')) extra=$(join(extra, ','))",
        )
    end
    return table
end

function _expect_exact(value, expected, location; code = :binding_mismatch)
    value == expected || fail(code, "$location expected $(repr(expected)), got $(repr(value))")
    return value
end

function _expect_document_hash(document::AbstractDict, location)
    artifact = _expect_table(get(document, "artifact", nothing), "$location.artifact")
    declared = _expect_hash(
        get(artifact, "content_sha256", nothing),
        "$location.artifact.content_sha256",
    )
    computed = document_content_sha256(document)
    declared == computed ||
        fail(:self_hash_mismatch, "$location expected semantic hash $computed, got $declared")
    return declared
end

function _parse_rfc3339(value, location)
    text = _expect_string(value, location)
    occursin(RFC3339_PATTERN, text) ||
        fail(:invalid_timestamp, "$location must be RFC3339 UTC seconds")
    try
        return DateTime(chop(text; tail = 1), dateformat"yyyy-mm-ddTHH:MM:SS")
    catch error
        fail(:invalid_timestamp, "$location is not a valid timestamp: $(sprint(showerror, error))")
    end
end

function _parse_date(value, location)
    text = _expect_string(value, location)
    occursin(DATE_PATTERN, text) || fail(:invalid_date, "$location must be YYYY-MM-DD")
    try
        return Date(text, dateformat"yyyy-mm-dd")
    catch error
        fail(:invalid_date, "$location is not a valid date: $(sprint(showerror, error))")
    end
end

function _validate_relative_path(relative::AbstractString)
    text = _expect_string(
        relative,
        "relative path";
        maximum_bytes = MAXIMUM_RELATIVE_PATH_BYTES,
    )
    isempty(text) && fail(:unsafe_path, "empty relative path")
    isabspath(text) && fail(:unsafe_path, "absolute path is forbidden")
    occursin('\\', text) && fail(:unsafe_path, "backslash path is forbidden")
    components = split(text, '/'; keepempty = true)
    length(components) <= MAXIMUM_PATH_COMPONENTS ||
        fail(:resource_limit, "relative path exceeds the frozen component-count ceiling")
    all(component -> !isempty(component) && component != "." && component != "..", components) ||
        fail(:unsafe_path, "path contains empty, dot, or parent component")
    all(component -> ncodeunits(component) <= MAXIMUM_PATH_COMPONENT_BYTES, components) ||
        fail(:resource_limit, "relative path component exceeds the frozen byte ceiling")
    return components
end

function _stable_state(path)
    info = lstat(path)
    return (
        info.device,
        info.inode,
        info.mode,
        info.nlink,
        info.size,
        info.mtime,
        info.ctime,
    )
end

function _stable_identity(path)
    info = lstat(path)
    return (info.device, info.inode, info.mode)
end

function _require_stable(before, after, label)
    before == after || fail(:file_race, "$label changed during read")
    return after
end

function _snapshot_safe_root(root::AbstractString)
    ncodeunits(root) <= MAXIMUM_RELATIVE_PATH_BYTES ||
        fail(:resource_limit, "evidence-root path exceeds the frozen byte ceiling")
    root_path = normpath(String(root))
    isabspath(root_path) || fail(:unsafe_root, "evidence root must be absolute")
    root_path == normpath("/") && fail(:unsafe_root, "filesystem root cannot be an evidence root")
    components = split(root_path, '/'; keepempty = false)
    current = normpath("/")
    states = Pair{String, Any}[]
    for component in components
        current = joinpath(current, component)
        ispath(current) || fail(:unsafe_root, "evidence-root ancestor is missing")
        islink(current) &&
            fail(:unsafe_root, "evidence-root ancestor is a symbolic link: $current")
        state = current == root_path ? (:full, _stable_state(current)) :
            (:identity, _stable_identity(current))
        push!(states, current => state)
    end
    isdir(root_path) || fail(:unsafe_root, "evidence root is not a directory")
    return root_path, states
end

function _recheck_path_states(states, label)
    for (path, state) in states
        ispath(path) || fail(:file_race, "$label path disappeared: $path")
        islink(path) && fail(:file_race, "$label path became symbolic: $path")
        kind, before = state
        after = kind === :full ? _stable_state(path) : _stable_identity(path)
        _require_stable(before, after, "$label path $path")
    end
    return states
end

function _safe_read(
        root::AbstractString,
        relative::AbstractString;
        expected_hash = nothing,
        label = "file",
        maximum_bytes = MAXIMUM_METADATA_FILE_BYTES,
    )
    maximum_bytes isa Integer && !(maximum_bytes isa Bool) && maximum_bytes >= 0 ||
        fail(:resource_limit, "$label has an invalid read ceiling")
    root_path, root_states = _snapshot_safe_root(root)
    current = root_path
    component_states = Pair{String, Any}[]
    for component in _validate_relative_path(relative)
        current = joinpath(current, component)
        ispath(current) || fail(:missing_file, "$label missing at $relative")
        islink(current) &&
            fail(:unsafe_path, "$label has symbolic-link component $component")
        push!(component_states, current => (:full, _stable_state(current)))
    end
    isfile(current) || fail(:unsafe_path, "$label is not a regular file")
    initial = lstat(current)
    initial.nlink == 1 || fail(:unsafe_path, "$label is hard-linked")
    initial.size <= maximum_bytes ||
        fail(:resource_limit, "$label exceeds the frozen byte ceiling $maximum_bytes")
    before = _stable_state(current)
    bytes = read(current)
    after = _stable_state(current)
    _require_stable(before, after, label)
    for (component_path, component_state) in component_states
        ispath(component_path) || fail(:file_race, "$label path component disappeared")
        islink(component_path) &&
            fail(:file_race, "$label path component became a symbolic link")
        _, before_component = component_state
        _require_stable(before_component, _stable_state(component_path), "$label path component")
    end
    _recheck_path_states(root_states, "$label evidence root")
    digest = sha256_hex(bytes)
    expected_hash === nothing || digest == expected_hash ||
        fail(:physical_hash_mismatch, "$label expected $expected_hash, got $digest")
    return bytes, digest, before
end

function _parse_toml_bytes(bytes, location)
    try
        document = TOML.parse(String(copy(bytes)))
        return _validate_value_bounds(document, location)
    catch error
        error isa CommonOriginAcquisitionError && rethrow()
        fail(:invalid_toml, "$location TOML parse failed: $(sprint(showerror, error))")
    end
end

function _read_toml(
        root,
        relative;
        expected_hash = nothing,
        label = "TOML",
        maximum_bytes = MAXIMUM_METADATA_FILE_BYTES,
    )
    bytes, digest, state =
        _safe_read(
        root,
        relative;
        expected_hash = expected_hash,
        label = label,
        maximum_bytes = maximum_bytes,
    )
    return _parse_toml_bytes(bytes, label), bytes, digest, state
end

function _all_false_gates(table, location; keys = GATE_KEYS)
    _expect_exact_keys(table, keys, location)
    for key in sort!(collect(keys))
        _expect_bool(table[key], "$location.$key") === false ||
            fail(:gate_elevation, "$location.$key must be false")
    end
    return table
end

function _legacy_rows(contract)
    requirements = _expect_vector(get(contract, "requirements", nothing), "v2.requirements")
    rows = Dict{String, Any}[]
    for (requirement_index, requirement_value) in enumerate(requirements)
        location = "v2.requirements[$requirement_index]"
        requirement = _expect_table(requirement_value, location)
        requirement_id = _expect_identifier(requirement["requirement_id"], "$location.requirement_id")
        source_id = _expect_identifier(requirement["source_id"], "$location.source_id")
        default_capture = _expect_identifier(
            requirement["default_capture_id"],
            "$location.default_capture_id",
        )
        profiles = _expect_table(requirement["artifact_profiles"], "$location.artifact_profiles")
        overrides = _expect_table(
            requirement["profile_capture_overrides"],
            "$location.profile_capture_overrides",
        )
        completion_dates = _expect_table(
            requirement["profile_completion_dates"],
            "$location.profile_completion_dates",
        )
        _expect_integer(requirement["required_profile_count"], "$location.required_profile_count") ==
            length(profiles) || fail(:legacy_baseline_mismatch, "$requirement_id profile count changed")
        profile_ids = sort!(
            [
                _expect_identifier(key, "$location.artifact_profiles key") for key in keys(profiles)
            ]
        )
        for profile_id in profile_ids
            selector = _expect_string(profiles[profile_id], "$location.artifact_profiles.$profile_id")
            capture_id = _expect_identifier(
                get(overrides, profile_id, default_capture),
                "$location.capture_id.$profile_id",
            )
            completion_date = _expect_string(
                get(completion_dates, profile_id, "NOT_APPLICABLE"),
                "$location.completion_date.$profile_id",
            )
            completion_date == "NOT_APPLICABLE" ||
                _parse_date(completion_date, "$location.completion_date.$profile_id")
            push!(
                rows,
                Dict{String, Any}(
                    "requirement_id" => requirement_id,
                    "source_id" => source_id,
                    "profile_id" => profile_id,
                    "selector" => selector,
                    "capture_id" => capture_id,
                    "completion_date" => completion_date,
                ),
            )
        end
    end
    sort!(rows; by = row -> (row["requirement_id"], row["profile_id"]))
    return rows
end

function _tuple_projection(rows)
    return [
        Dict{String, Any}(
                "requirement_id" => row["requirement_id"],
                "profile_id" => row["profile_id"],
                "selector" => row["selector"],
                "capture_id" => row["capture_id"],
                "completion_date" => row["completion_date"],
            ) for row in rows
    ]
end

function _validate_schema_binding(policy_schemas, prefix, expected_schema, expected_physical, expected_content)
    path = _expect_string(policy_schemas["$(prefix)_path"], "policy.schemas.$(prefix)_path")
    physical = _expect_hash(
        policy_schemas["$(prefix)_physical_sha256"],
        "policy.schemas.$(prefix)_physical_sha256",
    )
    content = _expect_hash(
        policy_schemas["$(prefix)_content_sha256"],
        "policy.schemas.$(prefix)_content_sha256",
    )
    _expect_exact(physical, expected_physical, "policy.schemas.$prefix physical hash")
    _expect_exact(content, expected_content, "policy.schemas.$prefix content hash")
    document, _, _, _ = _read_toml(
        REPOSITORY_ROOT,
        path;
        expected_hash = physical,
        label = "$prefix schema",
    )
    _expect_document_hash(document, "$prefix schema") == content ||
        fail(:schema_hash_mismatch, "$prefix schema semantic hash changed")
    artifact = _expect_table(document["artifact"], "$prefix schema.artifact")
    _expect_exact(
        _expect_string(artifact["described_schema_version"], "$prefix described schema"),
        expected_schema,
        "$prefix described schema",
        code = :schema_version_mismatch,
    )
    return path
end

function _validate_policy(policy)
    _expect_exact_keys(
        policy,
        [
            "artifact",
            "contract",
            "origin",
            "legacy_baseline",
            "schemas",
            "resource_limits",
            "retention",
            "effr_supersession",
            "source_bindings",
            "dispatch",
        ],
        "policy",
    )
    artifact = _expect_table(policy["artifact"], "policy.artifact")
    _expect_exact_keys(
        artifact,
        [
            "schema_version",
            "policy_id",
            "status",
            "canonicalization",
            "content_sha256",
        ],
        "policy.artifact",
    )
    _expect_exact(artifact["schema_version"], POLICY_SCHEMA, "policy schema")
    _expect_exact(artifact["policy_id"], POLICY_ID, "policy ID")
    _expect_exact(artifact["status"], CANNOT_RUN, "policy status", code = :gate_elevation)
    _expect_exact(artifact["canonicalization"], CANONICALIZATION, "policy canonicalization")
    _expect_document_hash(policy, "policy") == POLICY_CONTENT_SHA256 ||
        fail(:policy_content_hash_mismatch, "policy semantic identity changed")

    contract = _expect_table(policy["contract"], "policy.contract")
    _expect_exact_keys(
        contract,
        [
            "scope",
            "allowed_statuses",
            "current_expected_status",
            "maximum_status",
            "successor_only_status",
            "current_policy_ready_status_reachable",
            "ready_requires_new_schema_and_authenticated_trust_anchors",
            "external_signature_reference_is_authentication",
            "arbitrary_timestamp_token_hash_is_authenticated_rfc3161",
            "ready_to_score_forbidden",
            "synthetic_evidence_can_satisfy_readiness",
            "leaf_source_execution_forbidden",
            "wildcard_dispatch_forbidden",
            "unknown_receipt_types_forbidden",
            "origin_admission_forbidden",
            "inventory_mutation_forbidden",
            "truth_access_forbidden",
            "model_execution_forbidden",
            "forecast_execution_forbidden",
            "scoring_forbidden",
            "network_access_forbidden",
            "filesystem_write_forbidden",
        ],
        "policy.contract",
    )
    allowed = _expect_string_vector(contract["allowed_statuses"], "policy.allowed_statuses")
    allowed == [CANNOT_RUN] ||
        fail(:gate_elevation, "policy status universe changed")
    _expect_exact(contract["current_expected_status"], CANNOT_RUN, "current expected status")
    _expect_exact(contract["maximum_status"], CANNOT_RUN, "maximum status")
    _expect_exact(contract["successor_only_status"], READY_FOR_SEAL, "successor-only status")
    _expect_bool(
        contract["synthetic_evidence_can_satisfy_readiness"],
        "policy.contract.synthetic_evidence_can_satisfy_readiness",
    ) === false || fail(:gate_elevation, "synthetic evidence cannot satisfy readiness")
    for key in [
            "current_policy_ready_status_reachable",
            "external_signature_reference_is_authentication",
            "arbitrary_timestamp_token_hash_is_authenticated_rfc3161",
        ]
        _expect_bool(contract[key], "policy.contract.$key") === false ||
            fail(:gate_elevation, "policy.contract.$key must remain false")
    end
    _expect_bool(
        contract["ready_requires_new_schema_and_authenticated_trust_anchors"],
        "policy.contract.ready_requires_new_schema_and_authenticated_trust_anchors",
    ) === true || fail(:gate_elevation, "READY must require a new trust-anchored successor")
    for key in setdiff(
            Set(keys(contract)),
            Set(
                [
                    "scope",
                    "allowed_statuses",
                    "current_expected_status",
                    "maximum_status",
                    "successor_only_status",
                    "synthetic_evidence_can_satisfy_readiness",
                    "current_policy_ready_status_reachable",
                    "ready_requires_new_schema_and_authenticated_trust_anchors",
                    "external_signature_reference_is_authentication",
                    "arbitrary_timestamp_token_hash_is_authenticated_rfc3161",
                ],
            ),
        )
        _expect_bool(contract[key], "policy.contract.$key") === true ||
            fail(:gate_elevation, "policy.contract.$key must remain true")
    end

    origin = _expect_table(policy["origin"], "policy.origin")
    _expect_exact_keys(
        origin,
        ["origin_id", "reference_quarter", "origin_timestamp_utc", "origin_rule"],
        "policy.origin",
    )
    _expect_exact(origin["origin_id"], ORIGIN_ID, "policy origin ID")
    _expect_exact(origin["reference_quarter"], ORIGIN_QUARTER, "policy origin quarter")
    _expect_exact(origin["origin_timestamp_utc"], ORIGIN_TIMESTAMP, "policy origin timestamp")
    _expect_exact(origin["origin_rule"], ORIGIN_RULE, "policy origin rule")

    baseline = _expect_table(policy["legacy_baseline"], "policy.legacy_baseline")
    _expect_exact_keys(
        baseline,
        [
            "requirement_count",
            "profile_count",
            "opaque_audit_tuple_sha256",
            "opaque_audit_tuple_serialization",
            "typed_length_tuple_sha256",
            "typed_length_tuple_serialization",
            "legacy_v2_module_sha256",
            "legacy_v2_contract_sha256",
            "legacy_v2_semantic_sha256",
        ],
        "policy.legacy_baseline",
    )
    _expect_exact_integer(baseline["requirement_count"], 21, "legacy requirement count")
    _expect_exact_integer(baseline["profile_count"], 107, "legacy profile count")
    _expect_exact(
        baseline["opaque_audit_tuple_sha256"],
        OPAQUE_AUDIT_TUPLE_SHA256,
        "opaque audit tuple",
    )
    _expect_exact(
        baseline["opaque_audit_tuple_serialization"],
        "UNRECOVERABLE_NOT_REDERIVED",
        "opaque audit serialization status",
    )
    _expect_exact(
        baseline["typed_length_tuple_sha256"],
        TYPED_LENGTH_TUPLE_SHA256,
        "typed-length tuple hash",
    )
    _expect_exact(
        baseline["legacy_v2_module_sha256"],
        LEGACY_V2_MODULE_SHA256,
        "legacy v2 module hash",
    )
    _expect_exact(
        baseline["legacy_v2_contract_sha256"],
        LEGACY_V2_CONTRACT_SHA256,
        "legacy v2 contract hash",
    )
    _expect_exact(
        baseline["legacy_v2_semantic_sha256"],
        LEGACY_V2_SEMANTIC_SHA256,
        "legacy v2 semantic hash",
    )

    schemas = _expect_table(policy["schemas"], "policy.schemas")
    _expect_exact_keys(
        schemas,
        [
            "parent_path",
            "parent_physical_sha256",
            "parent_content_sha256",
            "leaf_path",
            "leaf_physical_sha256",
            "leaf_content_sha256",
            "retention_path",
            "retention_physical_sha256",
            "retention_content_sha256",
        ],
        "policy.schemas",
    )
    _validate_schema_binding(
        schemas,
        "parent",
        PARENT_SCHEMA,
        "cf4060554a6c53de079d728c2a2ac179309e9a7b888edc3bfa0a931ced5442a2",
        "a140f2c730102ab882f606c2780d1214f0db691f4f921b5e9c1a140cfaf520ce",
    )
    _validate_schema_binding(
        schemas,
        "leaf",
        LEAF_SCHEMA,
        "6bcd6f26efba67bb92053dabdc20c08f6b36d9c3569a92a5e980c5117265a4cd",
        "702ffcf060fd9bfb3530e3f9dee5936304351ab58ee386b53455662c3f069fe8",
    )
    _validate_schema_binding(
        schemas,
        "retention",
        RETENTION_SCHEMA,
        "94eb2a1bdbd1346b4918d63bdf1befcf506a8b6d39c6eeaa1b50e87eb2c79598",
        "2c6d6840a3396d5ced8e4e20b3bf0c5cc1fce68fdb927b796258fbf7a72382c3",
    )

    resource_limits = _expect_table(policy["resource_limits"], "policy.resource_limits")
    expected_resource_limits = Dict{String, Int}(
        "maximum_metadata_file_bytes" => MAXIMUM_METADATA_FILE_BYTES,
        "maximum_raw_or_replica_file_bytes" => MAXIMUM_RAW_OR_REPLICA_FILE_BYTES,
        "maximum_timestamp_token_bytes" => MAXIMUM_TIMESTAMP_TOKEN_BYTES,
        "maximum_total_raw_bytes_per_profile" => MAXIMUM_TOTAL_RAW_BYTES_PER_PROFILE,
        "maximum_total_replica_bytes_per_profile" => MAXIMUM_TOTAL_REPLICA_BYTES_PER_PROFILE,
        "maximum_total_raw_bytes_per_parent" => MAXIMUM_TOTAL_RAW_BYTES_PER_PARENT,
        "maximum_total_replica_bytes_per_parent" => MAXIMUM_TOTAL_REPLICA_BYTES_PER_PARENT,
        "maximum_raw_artifacts_per_profile" => MAXIMUM_RAW_ARTIFACTS_PER_PROFILE,
        "maximum_replicas_per_profile" => MAXIMUM_REPLICAS_PER_PROFILE,
        "maximum_catalog_candidates_per_profile" => MAXIMUM_CATALOG_CANDIDATES_PER_PROFILE,
        "maximum_vector_items" => MAXIMUM_VECTOR_ITEMS,
        "maximum_table_entries" => MAXIMUM_TABLE_ENTRIES,
        "maximum_string_bytes" => MAXIMUM_STRING_BYTES,
        "maximum_identifier_bytes" => MAXIMUM_IDENTIFIER_BYTES,
        "maximum_relative_path_bytes" => MAXIMUM_RELATIVE_PATH_BYTES,
        "maximum_path_component_bytes" => MAXIMUM_PATH_COMPONENT_BYTES,
        "maximum_path_components" => MAXIMUM_PATH_COMPONENTS,
    )
    _expect_exact_keys(resource_limits, keys(expected_resource_limits), "policy.resource_limits")
    for key in sort!(collect(keys(expected_resource_limits)))
        _expect_exact_integer(
            resource_limits[key],
            expected_resource_limits[key],
            "policy.resource_limits.$key";
            code = :resource_limit,
        )
    end

    retention = _expect_table(policy["retention"], "policy.retention")
    _expect_exact_keys(
        retention,
        [
            "maximum_horizon_quarters",
            "maximum_target_reference_quarter",
            "maximum_target_period_end_utc",
            "mature_truth_lag_months",
            "mathematical_minimum_retain_until_utc",
            "later_mature_receipt_completion_required",
            "later_mature_receipt_external_timestamp_required",
            "later_mature_receipt_durable_replication_required",
            "post_receipt_independent_audit_required",
            "deletion_release_rule",
        ],
        "policy.retention",
    )
    _expect_exact_integer(retention["maximum_horizon_quarters"], 12, "maximum horizon")
    _expect_exact(
        retention["maximum_target_reference_quarter"],
        MAXIMUM_TARGET_QUARTER,
        "maximum target quarter",
    )
    _expect_exact(
        retention["maximum_target_period_end_utc"],
        MAXIMUM_TARGET_PERIOD_END,
        "maximum target period end",
    )
    _expect_exact_integer(retention["mature_truth_lag_months"], 60, "mature truth lag")
    _expect_exact(
        retention["mathematical_minimum_retain_until_utc"],
        MINIMUM_RETAIN_UNTIL,
        "retention boundary",
    )
    for key in [
            "later_mature_receipt_completion_required",
            "later_mature_receipt_external_timestamp_required",
            "later_mature_receipt_durable_replication_required",
            "post_receipt_independent_audit_required",
        ]
        _expect_bool(retention[key], "policy.retention.$key") === true ||
            fail(:retention_mismatch, "$key must remain required")
    end
    _expect_exact(retention["deletion_release_rule"], DELETION_RELEASE_RULE, "deletion rule")
    return policy
end

function _validate_source_bindings(policy)
    bindings = _expect_vector(policy["source_bindings"], "policy.source_bindings")
    length(bindings) == 19 || fail(:source_binding_mismatch, "expected 19 source bindings")
    ids = String[]
    paths = String[]
    for (index, value) in enumerate(bindings)
        binding = _expect_table(value, "policy.source_bindings[$index]")
        _expect_exact_keys(binding, SOURCE_BINDING_KEYS, "policy.source_bindings[$index]")
        id = _expect_identifier(binding["binding_id"], "source binding ID")
        path = _expect_string(binding["path"], "source binding path")
        _validate_relative_path(path)
        digest = _expect_hash(binding["sha256"], "source binding hash")
        kind = _expect_string(binding["kind"], "source binding kind")
        kind in ("source", "metadata_toml", "documentation") ||
            fail(:source_binding_mismatch, "unsupported source kind $kind")
        _safe_read(REPOSITORY_ROOT, path; expected_hash = digest, label = "source binding $id")
        push!(ids, id)
        push!(paths, path)
    end
    allunique(ids) || fail(:source_binding_mismatch, "duplicate source binding ID")
    allunique(paths) || fail(:source_binding_mismatch, "duplicate source binding path")
    return bindings
end

function _effr_overlay(policy)
    overlay = _expect_table(policy["effr_supersession"], "policy.effr_supersession")
    _expect_exact_keys(
        overlay,
        [
            "status",
            "accepted_endpoint_profile_path",
            "accepted_endpoint_profile_sha256",
            "accepted_endpoint_profile_content_sha256",
            "candidate_84_date_history_satisfies_training_history",
            "daily_history_start_justification_required",
            "minimum_common_information_training_quarters",
            "core3_training_geometry_start",
            "methodology_regime_boundary",
            "regime_treatment_approval_required",
            "predecessor_august_7_revision_may_be_borrowed",
            "restart_first_observation_count",
            "restart_later_observation_count",
            "restart_total_slot_count",
            "restart_complete_pair_count",
            "first_public_claim_allowed",
            "current_state_claim_allowed",
            "final_daily_state_claim_allowed",
            "no_later_revision_claim_allowed",
            "rows",
        ],
        "policy.effr_supersession",
    )
    _expect_exact(
        overlay["status"],
        "ENDPOINT_PROFILE_PINNED_CANNOT_RUN_SUPERSESSION_UNFROZEN",
        "EFFR overlay status",
    )
    _expect_exact(
        overlay["accepted_endpoint_profile_path"],
        "scripts/us/forecasting/vintages/effr/prospective_endpoint_profile_v1/effr_prospective_endpoint_profile_v1.toml",
        "EFFR endpoint profile path",
    )
    _expect_exact(
        overlay["accepted_endpoint_profile_sha256"],
        "7de8e23e11d202a887e20d6e90616501562c9c3682db1200c753bb207ae4451b",
        "EFFR profile hash",
    )
    _expect_exact(
        overlay["accepted_endpoint_profile_content_sha256"],
        "4ed9a0f99c6c8490da35c290ce87c6051a6a1bf08da5eb2ee8ac601f75a4eaa5",
        "EFFR profile semantic hash",
    )
    endpoint_profile, _, _, _ = _read_toml(
        REPOSITORY_ROOT,
        overlay["accepted_endpoint_profile_path"];
        expected_hash = overlay["accepted_endpoint_profile_sha256"],
        label = "accepted CANNOT_RUN EFFR endpoint profile",
    )
    endpoint_artifact = _expect_table(
        get(endpoint_profile, "artifact", nothing),
        "EFFR endpoint profile.artifact",
    )
    _expect_exact(
        endpoint_artifact["content_sha256"],
        overlay["accepted_endpoint_profile_content_sha256"],
        "EFFR endpoint profile semantic identity",
    )
    _expect_exact(
        endpoint_artifact["status"],
        "CANNOT_RUN",
        "EFFR endpoint profile status",
        code = :gate_elevation,
    )
    _expect_bool(overlay["candidate_84_date_history_satisfies_training_history"], "84-day sufficiency") ===
        false || fail(:effr_geometry, "84-day candidate cannot satisfy training history")
    _expect_bool(overlay["daily_history_start_justification_required"], "start justification") ===
        true || fail(:effr_geometry, "history start justification must be required")
    _expect_exact_integer(
        overlay["minimum_common_information_training_quarters"],
        60,
        "training quarters",
    )
    _expect_exact(overlay["core3_training_geometry_start"], "2000Q3", "core3 start")
    _expect_exact(overlay["methodology_regime_boundary"], "2016-03-01", "EFFR regime boundary")
    _expect_bool(overlay["regime_treatment_approval_required"], "regime approval") === true ||
        fail(:effr_geometry, "regime treatment approval must be required")
    _expect_bool(overlay["predecessor_august_7_revision_may_be_borrowed"], "August 7 borrowing") ===
        false || fail(:effr_geometry, "August 7 later observation cannot be borrowed")
    for (key, expected) in [
            "restart_first_observation_count" => 58,
            "restart_later_observation_count" => 57,
            "restart_total_slot_count" => 115,
            "restart_complete_pair_count" => 57,
        ]
        _expect_exact_integer(overlay[key], expected, "EFFR $key")
    end
    for key in [
            "first_public_claim_allowed",
            "current_state_claim_allowed",
            "final_daily_state_claim_allowed",
            "no_later_revision_claim_allowed",
        ]
        _expect_bool(overlay[key], "EFFR $key") === false ||
            fail(:effr_claim_elevation, "$key must remain false")
    end
    rows = _expect_vector(overlay["rows"], "policy.effr_supersession.rows")
    length(rows) == 3 || fail(:effr_geometry, "EFFR overlay must contain exactly three rows")
    result = Dict{String, Dict{String, Any}}()
    for (index, value) in enumerate(rows)
        row = _expect_table(value, "policy.effr_supersession.rows[$index]")
        _expect_exact_keys(
            row,
            [
                "legacy_profile_id",
                "active_profile_id",
                "active_semantic_role",
                "active_selector",
                "decision_status",
                "decision_sha256",
                "decision_path",
                "decision_schema_version",
                "decision_content_sha256",
            ],
            "policy.effr_supersession.rows[$index]",
        )
        legacy_id = _expect_identifier(row["legacy_profile_id"], "EFFR legacy profile")
        haskey(result, legacy_id) && fail(:effr_geometry, "duplicate EFFR legacy profile")
        _expect_identifier(row["active_profile_id"], "EFFR active profile")
        _expect_string(row["active_selector"], "EFFR active selector")
        _expect_exact(row["decision_status"], "REQUIRED_NOT_FROZEN", "EFFR decision status")
        _expect_exact(row["decision_sha256"], "UNAVAILABLE", "EFFR decision hash")
        _expect_exact(
            row["decision_path"],
            "UNAVAILABLE_NOT_FROZEN",
            "EFFR decision path",
        )
        _expect_exact(
            row["decision_schema_version"],
            "beforeit-us-effr-profile-supersession-decision.v1",
            "EFFR decision schema",
        )
        _expect_exact(
            row["decision_content_sha256"],
            "UNAVAILABLE",
            "EFFR decision semantic hash",
        )
        result[legacy_id] = Dict{String, Any}(row)
    end
    Set(keys(result)) ==
        Set(["effr_daily_history", "effr_first_state_manifest", "effr_revision_manifest"]) ||
        fail(:effr_geometry, "EFFR overlay profile universe changed")
    return result
end

function _dispatch_map(policy, legacy_rows)
    dispatches = _expect_vector(policy["dispatch"], "policy.dispatch")
    length(dispatches) == 21 || fail(:dispatch_mismatch, "expected exactly 21 dispatch entries")
    result = Dict{String, Dict{String, Any}}()
    keys4 = Set{Tuple{String, String, String, String}}()
    expected_by_requirement = Dict{String, Vector{Dict{String, Any}}}()
    for row in legacy_rows
        push!(
            get!(expected_by_requirement, row["requirement_id"], Dict{String, Any}[]),
            row,
        )
    end
    for (index, value) in enumerate(dispatches)
        location = "policy.dispatch[$index]"
        dispatch = _expect_table(value, location)
        _expect_exact_keys(dispatch, DISPATCH_KEYS, location)
        id = _expect_identifier(dispatch["dispatch_id"], "$location.dispatch_id")
        haskey(result, id) && fail(:dispatch_mismatch, "duplicate dispatch ID $id")
        receipt_schema = _expect_string(dispatch["receipt_schema_version"], "$location.receipt_schema")
        _expect_exact(receipt_schema, LEAF_SCHEMA, "$location receipt schema")
        requirement_id = _expect_identifier(dispatch["requirement_id"], "$location.requirement_id")
        source_id = _expect_identifier(dispatch["source_id"], "$location.source_id")
        evidence_role = _expect_identifier(dispatch["evidence_role"], "$location.evidence_role")
        key4 = (receipt_schema, requirement_id, source_id, evidence_role)
        key4 in keys4 && fail(:dispatch_mismatch, "duplicate dispatch key $(repr(key4))")
        push!(keys4, key4)
        haskey(expected_by_requirement, requirement_id) ||
            fail(:dispatch_mismatch, "unknown dispatch requirement $requirement_id")
        expected_rows = expected_by_requirement[requirement_id]
        all(row -> row["source_id"] == source_id, expected_rows) ||
            fail(:dispatch_mismatch, "$requirement_id source binding changed")
        allowed_profiles = _expect_string_vector(
            dispatch["allowed_profile_ids"],
            "$location.allowed_profiles",
        )
        expected_profiles = sort!([String(row["profile_id"]) for row in expected_rows])
        allowed_profiles == expected_profiles ||
            fail(:dispatch_mismatch, "$requirement_id exact profile universe changed")
        allunique(allowed_profiles) || fail(:dispatch_mismatch, "$requirement_id profiles duplicate")
        media = _expect_string_vector(
            dispatch["permitted_media_types"],
            "$location.media_types",
        )
        isempty(media) && fail(:dispatch_mismatch, "$requirement_id has no permitted media types")
        allunique(media) || fail(:dispatch_mismatch, "$requirement_id media types duplicate")
        roles = _expect_string_vector(
            dispatch["permitted_artifact_roles"],
            "$location.roles",
        )
        roles == ["SOURCE_PAYLOAD"] || fail(:dispatch_mismatch, "$requirement_id artifact roles changed")
        qualified = _expect_bool(dispatch["qualified"], "$location.qualified")
        qualified === false ||
            fail(:gate_elevation, "this exact v3 has no qualified dispatch branch")
        blockers = _expect_string_vector(dispatch["blocker_ids"], "$location.blocker_ids")
        isempty(blockers) && fail(:dispatch_mismatch, "unqualified dispatch $id lacks blockers")
        allunique(blockers) || fail(:dispatch_mismatch, "dispatch $id blocker IDs duplicate")
        _expect_exact(
            dispatch["leaf_verifier_id"],
            "UNAVAILABLE_NO_ACCEPTED_QUALIFIED_LEAF_VERIFIER",
            "$location leaf verifier ID",
        )
        _expect_exact(dispatch["leaf_verifier_version"], "NOT_APPLICABLE", "$location version")
        _expect_exact(dispatch["leaf_verifier_source_path"], "NOT_APPLICABLE", "$location source path")
        _expect_exact(dispatch["leaf_verifier_source_sha256"], "UNAVAILABLE", "$location source hash")
        _expect_exact(dispatch["leaf_verifier_test_path"], "NOT_APPLICABLE", "$location test path")
        _expect_exact(dispatch["leaf_verifier_test_sha256"], "UNAVAILABLE", "$location test hash")
        _expect_exact(
            dispatch["claim_schema_version"],
            "beforeit-us-origin-information-profile-claim.v1",
            "$location claim schema",
        )
        _expect_exact(
            dispatch["independent_validation_receipt_schema_version"],
            "beforeit-us-independent-profile-validation-receipt.v1",
            "$location independent-validation schema",
        )
        result[id] = Dict{String, Any}(dispatch)
    end
    Set(keys(expected_by_requirement)) == Set(dispatch["requirement_id"] for dispatch in values(result)) ||
        fail(:dispatch_mismatch, "dispatch requirement bijection changed")
    return result
end

function _load_policy_context()
    policy, _, _, _ = _read_toml(
        REPOSITORY_ROOT,
        POLICY_RELATIVE_PATH;
        expected_hash = POLICY_PHYSICAL_SHA256,
        label = "common-origin acquisition v3 policy",
    )
    _validate_policy(policy)
    _validate_source_bindings(policy)
    legacy_contract, _, _, _ = _read_toml(
        REPOSITORY_ROOT,
        LEGACY_CONTRACT_RELATIVE_PATH;
        expected_hash = LEGACY_V2_CONTRACT_SHA256,
        label = "frozen prospective v2 contract",
    )
    _expect_exact(
        legacy_contract["artifact"]["content_sha256"],
        LEGACY_V2_SEMANTIC_SHA256,
        "legacy v2 semantic identity",
    )
    legacy_rows = _legacy_rows(legacy_contract)
    length(legacy_rows) == 107 || fail(:legacy_baseline_mismatch, "legacy profile count is not 107")
    length(unique(row["requirement_id"] for row in legacy_rows)) == 21 ||
        fail(:legacy_baseline_mismatch, "legacy requirement count is not 21")
    canonical_sha256(_tuple_projection(legacy_rows)) == TYPED_LENGTH_TUPLE_SHA256 ||
        fail(:legacy_baseline_mismatch, "reproducible typed-length tuple changed")
    overlay = _effr_overlay(policy)
    dispatches = _dispatch_map(policy, legacy_rows)
    return (
        policy = policy,
        legacy_contract = legacy_contract,
        legacy_rows = legacy_rows,
        overlay = overlay,
        dispatches = dispatches,
    )
end

function load_policy()
    return deepcopy(_load_policy_context().policy)
end

function _expected_rows(context)
    rows = Dict{String, Any}[]
    for legacy in context.legacy_rows
        overlay = get(context.overlay, legacy["profile_id"], nothing)
        active_profile_id = overlay === nothing ? legacy["profile_id"] : overlay["active_profile_id"]
        active_selector = overlay === nothing ? legacy["selector"] : overlay["active_selector"]
        dispatch_id = "dispatch.$(legacy["requirement_id"]).v1"
        haskey(context.dispatches, dispatch_id) ||
            fail(:dispatch_mismatch, "missing dispatch $dispatch_id")
        push!(
            rows,
            Dict{String, Any}(
                "legacy_requirement_id" => legacy["requirement_id"],
                "legacy_profile_id" => legacy["profile_id"],
                "legacy_selector" => legacy["selector"],
                "legacy_selector_sha256" => sha256_hex(Vector{UInt8}(codeunits(legacy["selector"]))),
                "active_profile_id" => active_profile_id,
                "active_selector" => active_selector,
                "active_selector_sha256" => sha256_hex(Vector{UInt8}(codeunits(active_selector))),
                "dispatch_id" => dispatch_id,
                "capture_id" => legacy["capture_id"],
                "completion_date" => legacy["completion_date"],
                "source_id" => legacy["source_id"],
                "supersession_required" => overlay !== nothing,
            ),
        )
    end
    return rows
end

function _common_artifact(document, location, schema_version, evidence_class)
    artifact = _expect_table(get(document, "artifact", nothing), "$location.artifact")
    _expect_exact_keys(
        artifact,
        ["schema_version", "evidence_class", "canonicalization", "content_sha256"],
        "$location.artifact",
    )
    _expect_exact(artifact["schema_version"], schema_version, "$location schema")
    _expect_exact(artifact["evidence_class"], evidence_class, "$location evidence class")
    _expect_exact(artifact["canonicalization"], CANONICALIZATION, "$location canonicalization")
    _expect_document_hash(document, location)
    return artifact
end

function _load_supporting_document(root, path, digest, label, schema_version, evidence_class)
    document, _, _, _ =
        _read_toml(root, path; expected_hash = digest, label = label)
    _common_artifact(document, label, schema_version, evidence_class)
    return document
end

function _validate_approval_pair(
        root,
        table,
        subject_sha256,
        evidence_class,
        location;
        decision,
        not_before = nothing,
    )
    signed_times = DateTime[]
    _expect_exact_keys(
        table,
        [
            "evidence_subject_sha256",
            "owner_id",
            "owner_receipt_path",
            "owner_receipt_sha256",
            "validator_id",
            "validator_receipt_path",
            "validator_receipt_sha256",
        ],
        location,
    )
    _expect_exact(table["evidence_subject_sha256"], subject_sha256, "$location subject")
    owner_id = _expect_identifier(table["owner_id"], "$location.owner_id")
    validator_id = _expect_identifier(table["validator_id"], "$location.validator_id")
    owner_id != validator_id || fail(:approval_independence, "$location owner and validator are identical")
    owner_path = _expect_string(table["owner_receipt_path"], "$location.owner_receipt_path")
    validator_path = _expect_string(table["validator_receipt_path"], "$location.validator_receipt_path")
    owner_path != validator_path || fail(:approval_independence, "$location approval paths are identical")
    owner_hash = _expect_hash(table["owner_receipt_sha256"], "$location.owner_receipt_sha256")
    validator_hash = _expect_hash(
        table["validator_receipt_sha256"],
        "$location.validator_receipt_sha256",
    )
    owner_hash != validator_hash || fail(:approval_independence, "$location approval hashes are identical")
    for (role, signer_id, path, digest) in [
            ("MODEL_OWNER", owner_id, owner_path, owner_hash),
            ("INDEPENDENT_VALIDATOR", validator_id, validator_path, validator_hash),
        ]
        document = _load_supporting_document(
            root,
            path,
            digest,
            "$location $role receipt",
            "beforeit-us-profile-approval-attestation.v1",
            evidence_class,
        )
        _expect_exact_keys(document, ["artifact", "attestation"], "$location $role document")
        attestation = _expect_table(document["attestation"], "$location $role attestation")
        _expect_exact_keys(
            attestation,
            [
                "subject_sha256",
                "role",
                "signer_id",
                "decision",
                "signed_at_utc",
                "signature_scheme",
                "signature_value",
            ],
            "$location $role attestation",
        )
        _expect_exact(attestation["subject_sha256"], subject_sha256, "$location $role subject")
        _expect_exact(attestation["role"], role, "$location $role role")
        _expect_exact(attestation["signer_id"], signer_id, "$location $role signer")
        _expect_exact(attestation["decision"], decision, "$location $role decision")
        signed_at =
            _parse_rfc3339(attestation["signed_at_utc"], "$location $role signed_at_utc")
        signed_at < _parse_rfc3339(ORIGIN_TIMESTAMP, "origin timestamp") ||
            fail(:post_origin_evidence, "$location $role approval is not pre-origin")
        not_before === nothing || signed_at >= not_before ||
            fail(:approval_attestation, "$location $role approval predates its evidence")
        push!(signed_times, signed_at)
        scheme = _expect_string(attestation["signature_scheme"], "$location $role signature scheme")
        scheme == "EXTERNAL_SIGNATURE_REFERENCE_V1" ||
            fail(:approval_attestation, "$location $role signature scheme is not accepted")
        isempty(_expect_string(attestation["signature_value"], "$location $role signature value")) &&
            fail(:approval_attestation, "$location $role signature value is empty")
    end
    return maximum(signed_times)
end

function _parent_material_subject(parent)
    return canonical_sha256(
        Dict{String, Any}(
            "artifact_evidence_class" => parent["artifact"]["evidence_class"],
            "origin" => parent["origin"],
            "baseline" => parent["baseline"],
            "rows" => parent["rows"],
            "custody" => parent["custody"],
        ),
    )
end

function _custody_subject(parent)
    return canonical_sha256(
        Dict{String, Any}(
            "artifact_evidence_class" => parent["artifact"]["evidence_class"],
            "origin" => parent["origin"],
            "baseline" => parent["baseline"],
            "ordered_child_closure" => parent["rows"],
        ),
    )
end

function _validate_parent_shape(parent, context)
    _expect_exact_keys(
        parent,
        ["artifact", "origin", "baseline", "custody", "approvals", "gates", "rows"],
        "parent",
    )
    artifact = _expect_table(parent["artifact"], "parent.artifact")
    _expect_exact_keys(
        artifact,
        ["schema_version", "evidence_class", "canonicalization", "content_sha256"],
        "parent.artifact",
    )
    _expect_exact(artifact["schema_version"], PARENT_SCHEMA, "parent schema")
    evidence_class = _expect_string(artifact["evidence_class"], "parent evidence class")
    evidence_class in ("PROSPECTIVE_NONSYNTHETIC", "SYNTHETIC_TEST_ONLY") ||
        fail(:invalid_evidence_class, "parent evidence class is not closed")
    _expect_exact(artifact["canonicalization"], CANONICALIZATION, "parent canonicalization")
    _expect_document_hash(parent, "parent")

    origin = _expect_table(parent["origin"], "parent.origin")
    _expect_exact_keys(
        origin,
        ["origin_id", "reference_quarter", "origin_timestamp_utc", "origin_rule"],
        "parent.origin",
    )
    _expect_exact(origin["origin_id"], ORIGIN_ID, "parent origin ID")
    _expect_exact(origin["reference_quarter"], ORIGIN_QUARTER, "parent origin quarter")
    _expect_exact(origin["origin_timestamp_utc"], ORIGIN_TIMESTAMP, "parent origin timestamp")
    _expect_exact(origin["origin_rule"], ORIGIN_RULE, "parent origin rule")

    baseline = _expect_table(parent["baseline"], "parent.baseline")
    _expect_exact_keys(
        baseline,
        [
            "policy_path",
            "policy_physical_sha256",
            "legacy_v2_module_sha256",
            "legacy_v2_contract_sha256",
            "legacy_v2_semantic_sha256",
            "legacy_profile_count",
            "legacy_requirement_count",
            "opaque_audit_tuple_sha256",
            "typed_length_tuple_sha256",
        ],
        "parent.baseline",
    )
    _expect_exact(baseline["policy_path"], POLICY_RELATIVE_PATH, "parent policy path")
    _expect_exact(baseline["policy_physical_sha256"], POLICY_PHYSICAL_SHA256, "parent policy hash")
    _expect_exact(baseline["legacy_v2_module_sha256"], LEGACY_V2_MODULE_SHA256, "parent v2 module")
    _expect_exact(
        baseline["legacy_v2_contract_sha256"],
        LEGACY_V2_CONTRACT_SHA256,
        "parent v2 contract",
    )
    _expect_exact(
        baseline["legacy_v2_semantic_sha256"],
        LEGACY_V2_SEMANTIC_SHA256,
        "parent v2 semantic",
    )
    _expect_exact_integer(baseline["legacy_profile_count"], 107, "parent profile count")
    _expect_exact_integer(baseline["legacy_requirement_count"], 21, "parent requirement count")
    _expect_exact(
        baseline["opaque_audit_tuple_sha256"],
        OPAQUE_AUDIT_TUPLE_SHA256,
        "parent opaque tuple",
    )
    _expect_exact(
        baseline["typed_length_tuple_sha256"],
        TYPED_LENGTH_TUPLE_SHA256,
        "parent typed tuple",
    )

    rows = _expect_vector(parent["rows"], "parent.rows")
    length(rows) == 107 || fail(:parent_bijection, "parent must contain exactly 107 rows")
    expected = _expected_rows(context)
    observed_keys = Tuple{String, String}[]
    receipt_paths = String[]
    for index in eachindex(expected)
        location = "parent.rows[$index]"
        row = _expect_table(rows[index], location)
        _expect_exact_keys(row, PARENT_ROW_KEYS, location)
        expected_row = expected[index]
        requirement_id = _expect_identifier(row["legacy_requirement_id"], "$location requirement")
        profile_id = _expect_identifier(row["legacy_profile_id"], "$location profile")
        push!(observed_keys, (requirement_id, profile_id))
        _expect_exact(
            requirement_id,
            expected_row["legacy_requirement_id"],
            "$location requirement",
            code = :parent_order_or_binding,
        )
        _expect_exact(
            profile_id,
            expected_row["legacy_profile_id"],
            "$location profile",
            code = :parent_order_or_binding,
        )
        _expect_exact(
            row["active_profile_id"],
            expected_row["active_profile_id"],
            "$location active profile",
            code = :parent_order_or_binding,
        )
        _expect_exact(
            row["dispatch_id"],
            expected_row["dispatch_id"],
            "$location dispatch",
            code = :parent_order_or_binding,
        )
        receipt_path = _expect_string(row["receipt_path"], "$location receipt path")
        _validate_relative_path(receipt_path)
        _expect_hash(row["receipt_sha256"], "$location receipt hash")
        if expected_row["supersession_required"]
            _expect_exact(
                row["supersession_decision_sha256"],
                "UNAVAILABLE_NOT_FROZEN",
                "$location supersession decision",
                code = :effr_supersession_unavailable,
            )
        else
            _expect_exact(
                row["supersession_decision_sha256"],
                "NOT_APPLICABLE",
                "$location supersession decision",
            )
        end
        push!(receipt_paths, receipt_path)
    end
    allunique(observed_keys) || fail(:parent_bijection, "parent rows duplicate a legacy profile")
    allunique(receipt_paths) || fail(:parent_bijection, "parent receipt paths must be profile-specific")
    issorted(observed_keys) || fail(:parent_order_or_binding, "parent rows are not canonically ordered")
    custody = _expect_table(parent["custody"], "parent.custody")
    _expect_exact_keys(custody, ["receipt_path", "receipt_sha256"], "parent.custody")
    _validate_relative_path(_expect_string(custody["receipt_path"], "parent custody path"))
    _expect_hash(custody["receipt_sha256"], "parent custody hash")
    approvals = _expect_table(parent["approvals"], "parent.approvals")
    gates = _expect_table(parent["gates"], "parent.gates")
    _all_false_gates(gates, "parent.gates")
    return (
        evidence_class = evidence_class,
        material_subject_sha256 = _parent_material_subject(parent),
        custody_subject_sha256 = _custody_subject(parent),
        expected_rows = expected,
        approvals = approvals,
        custody = custody,
    )
end

function _validate_custody(
        root,
        path,
        digest,
        evidence_class,
        subject_sha256,
        latest_child_evidence_at,
    )
    document = _load_supporting_document(
        root,
        path,
        digest,
        "retention custody covenant",
        RETENTION_SCHEMA,
        evidence_class,
    )
    _expect_exact_keys(
        document,
        ["artifact", "geometry", "covenant", "approvals", "gates"],
        "custody",
    )
    geometry = _expect_table(document["geometry"], "custody.geometry")
    _expect_exact_keys(
        geometry,
        [
            "origin_reference_quarter",
            "maximum_horizon_quarters",
            "maximum_target_reference_quarter",
            "maximum_target_period_end_utc",
            "mature_truth_lag_months",
            "mathematical_minimum_retain_until_utc",
        ],
        "custody.geometry",
    )
    _expect_exact(geometry["origin_reference_quarter"], ORIGIN_QUARTER, "custody origin quarter")
    _expect_exact_integer(
        geometry["maximum_horizon_quarters"],
        12,
        "custody maximum horizon",
    )
    _expect_exact(
        geometry["maximum_target_reference_quarter"],
        MAXIMUM_TARGET_QUARTER,
        "custody target quarter",
    )
    _expect_exact(
        geometry["maximum_target_period_end_utc"],
        MAXIMUM_TARGET_PERIOD_END,
        "custody target period end",
    )
    _expect_exact_integer(
        geometry["mature_truth_lag_months"],
        60,
        "custody mature truth lag",
    )
    _expect_exact(
        geometry["mathematical_minimum_retain_until_utc"],
        MINIMUM_RETAIN_UNTIL,
        "custody mathematical boundary",
    )
    covenant = _expect_table(document["covenant"], "custody.covenant")
    _expect_exact_keys(
        covenant,
        [
            "custody_policy_id",
            "covered_subject_sha256",
            "minimum_durable_replica_count",
            "retain_origin_evidence_until_utc",
            "mature_truth_receipt_preseal_state",
            "later_mature_receipt_completion_required",
            "later_mature_receipt_external_timestamp_required",
            "later_mature_receipt_durable_replication_required",
            "post_receipt_independent_audit_required",
            "deletion_release_rule",
        ],
        "custody.covenant",
    )
    _expect_exact(
        covenant["custody_policy_id"],
        "beforeit-us-retention-custody-v2.2026q3",
        "custody policy ID",
    )
    _expect_exact(covenant["covered_subject_sha256"], subject_sha256, "custody covered subject")
    _expect_exact_integer(
        covenant["minimum_durable_replica_count"],
        2,
        "custody replica count",
    )
    _expect_exact(
        covenant["retain_origin_evidence_until_utc"],
        MINIMUM_RETAIN_UNTIL,
        "custody retention boundary",
    )
    _expect_exact(
        covenant["mature_truth_receipt_preseal_state"],
        "FUTURE_NOT_LOADED_EXPECTED",
        "custody pre-seal mature truth state",
    )
    for key in [
            "later_mature_receipt_completion_required",
            "later_mature_receipt_external_timestamp_required",
            "later_mature_receipt_durable_replication_required",
            "post_receipt_independent_audit_required",
        ]
        _expect_bool(covenant[key], "custody.covenant.$key") === true ||
            fail(:retention_mismatch, "custody $key must be true")
    end
    _expect_exact(covenant["deletion_release_rule"], DELETION_RELEASE_RULE, "custody deletion rule")
    approvals = _expect_table(document["approvals"], "custody.approvals")
    custody_approved_at = _validate_approval_pair(
        root,
        approvals,
        subject_sha256,
        evidence_class,
        "custody.approvals";
        decision = "APPROVED_FOR_CUSTODY_COVENANT_ONLY",
        not_before = latest_child_evidence_at,
    )
    custody_gate_keys = Set(
        [
            "truth_access_allowed",
            "scoring_allowed",
            "origin_admission_allowed",
            "deletion_allowed_pre_maturity",
        ],
    )
    _all_false_gates(
        _expect_table(document["gates"], "custody.gates"),
        "custody.gates";
        keys = custody_gate_keys,
    )
    return document, custody_approved_at
end

function _validate_catalog(
        root,
        selector,
        receipt_binding,
        raw_by_id,
        release,
        evidence_class,
        capture_completed_at,
    )
    path = _expect_string(selector["candidate_catalog_path"], "leaf.selector.candidate_catalog_path")
    digest = _expect_hash(selector["candidate_catalog_sha256"], "leaf selector catalog hash")
    document = _load_supporting_document(
        root,
        path,
        digest,
        "selector candidate catalog",
        "beforeit-us-selector-candidate-catalog.v1",
        evidence_class,
    )
    _expect_exact_keys(
        document,
        ["artifact", "receipt_completed_at_utc", "binding", "selection", "candidates"],
        "catalog",
    )
    completed_at =
        _parse_rfc3339(document["receipt_completed_at_utc"], "catalog receipt completion")
    completed_at >= capture_completed_at ||
        fail(:selector_closure, "selector candidate catalog predates capture completion")
    completed_at < _parse_rfc3339(ORIGIN_TIMESTAMP, "origin timestamp") ||
        fail(:post_origin_evidence, "selector candidate catalog is not pre-origin")
    binding = _expect_table(document["binding"], "catalog.binding")
    _expect_exact_keys(
        binding,
        [
            "requirement_id",
            "source_id",
            "active_profile_id",
            "active_selector",
            "active_selector_sha256",
        ],
        "catalog.binding",
    )
    for key in keys(binding)
        _expect_exact(binding[key], receipt_binding[key], "catalog.binding.$key")
    end
    selection = _expect_table(document["selection"], "catalog.selection")
    _expect_exact_keys(
        selection,
        ["eligible_candidate_count", "selected_candidate_rank", "selected_candidate_id"],
        "catalog.selection",
    )
    _expect_exact_integer(selection["eligible_candidate_count"], 1, "catalog eligible count")
    _expect_exact_integer(selection["selected_candidate_rank"], 1, "catalog selected rank")
    selected_id = _expect_identifier(selection["selected_candidate_id"], "catalog selected candidate")
    candidates = _expect_vector(
        document["candidates"],
        "catalog.candidates";
        maximum_items = MAXIMUM_CATALOG_CANDIDATES_PER_PROFILE,
    )
    isempty(candidates) && fail(:selector_closure, "candidate catalog is empty")
    candidate_ids = String[]
    eligible = Dict{String, Any}[]
    for (index, value) in enumerate(candidates)
        candidate = _expect_table(value, "catalog.candidates[$index]")
        _expect_exact_keys(
            candidate,
            [
                "candidate_id",
                "official_locator",
                "media_type",
                "artifact_role",
                "eligible",
                "rank",
                "raw_artifact_id",
                "raw_sha256",
            ],
            "catalog.candidates[$index]",
        )
        candidate_id = _expect_identifier(candidate["candidate_id"], "catalog candidate ID")
        push!(candidate_ids, candidate_id)
        isempty(_expect_string(candidate["official_locator"], "catalog official locator")) &&
            fail(:release_binding, "catalog official locator is empty")
        rank = _expect_integer(candidate["rank"], "catalog candidate rank")
        rank >= 1 || fail(:selector_closure, "catalog candidate rank must be positive")
        if _expect_bool(candidate["eligible"], "catalog candidate eligibility")
            push!(eligible, candidate)
        end
        raw_id = _expect_identifier(candidate["raw_artifact_id"], "catalog raw artifact ID")
        haskey(raw_by_id, raw_id) || fail(:selector_closure, "catalog references unknown raw artifact $raw_id")
        _expect_exact(candidate["raw_sha256"], raw_by_id[raw_id]["sha256"], "catalog raw hash")
        _expect_exact(candidate["media_type"], raw_by_id[raw_id]["media_type"], "catalog media type")
        _expect_exact(candidate["artifact_role"], raw_by_id[raw_id]["artifact_role"], "catalog role")
    end
    allunique(candidate_ids) || fail(:selector_closure, "catalog candidate IDs duplicate")
    length(eligible) == 1 || fail(:selector_closure, "catalog must have exactly one eligible candidate")
    _expect_exact(eligible[1]["candidate_id"], selected_id, "catalog selected candidate identity")
    _expect_exact_integer(eligible[1]["rank"], 1, "catalog eligible candidate rank")
    _expect_exact(
        eligible[1]["official_locator"],
        release["official_locator"],
        "catalog selected official locator";
        code = :release_binding,
    )
    return document, eligible[1], completed_at
end

function _validate_resolution(
        root,
        selector,
        receipt_binding,
        catalog_hash,
        selected,
        evidence_class,
        reference_period_start,
        reference_period_end,
        catalog_completed_at,
    )
    path = _expect_string(selector["resolution_path"], "leaf.selector.resolution_path")
    digest = _expect_hash(selector["resolution_sha256"], "leaf selector resolution hash")
    document = _load_supporting_document(
        root,
        path,
        digest,
        "selector resolution",
        "beforeit-us-selector-resolution.v1",
        evidence_class,
    )
    _expect_exact_keys(
        document,
        ["artifact", "receipt_completed_at_utc", "binding", "resolution"],
        "resolution",
    )
    completed_at =
        _parse_rfc3339(document["receipt_completed_at_utc"], "selector resolution completion")
    completed_at >= catalog_completed_at ||
        fail(:selector_closure, "selector resolution predates its candidate catalog")
    completed_at < _parse_rfc3339(ORIGIN_TIMESTAMP, "origin timestamp") ||
        fail(:post_origin_evidence, "selector resolution is not pre-origin")
    binding = _expect_table(document["binding"], "resolution.binding")
    _expect_exact_keys(
        binding,
        [
            "requirement_id",
            "source_id",
            "active_profile_id",
            "active_selector",
            "active_selector_sha256",
        ],
        "resolution.binding",
    )
    for key in keys(binding)
        _expect_exact(binding[key], receipt_binding[key], "resolution.binding.$key")
    end
    resolution = _expect_table(document["resolution"], "resolution.resolution")
    _expect_exact_keys(
        resolution,
        [
            "candidate_catalog_sha256",
            "selected_candidate_id",
            "selected_candidate_rank",
            "selected_raw_artifact_id",
            "selected_raw_sha256",
            "reference_period_start",
            "reference_period_end",
            "resolved_dimensions_complete",
            "set_resolution_complete",
        ],
        "resolution.resolution",
    )
    _expect_exact(resolution["candidate_catalog_sha256"], catalog_hash, "resolution catalog hash")
    _expect_exact(
        resolution["selected_candidate_id"],
        selected["candidate_id"],
        "resolution candidate ID",
    )
    _expect_exact_integer(resolution["selected_candidate_rank"], 1, "resolution candidate rank")
    _expect_exact(
        resolution["selected_raw_artifact_id"],
        selected["raw_artifact_id"],
        "resolution raw artifact ID",
    )
    _expect_exact(resolution["selected_raw_sha256"], selected["raw_sha256"], "resolution raw hash")
    _expect_exact(
        resolution["reference_period_start"],
        reference_period_start,
        "resolution reference-period start",
    )
    _expect_exact(
        resolution["reference_period_end"],
        reference_period_end,
        "resolution reference-period end",
    )
    _expect_bool(resolution["resolved_dimensions_complete"], "resolution dimensions") === true ||
        fail(:selector_closure, "resolved dimensions are incomplete")
    _expect_bool(resolution["set_resolution_complete"], "resolution set closure") === true ||
        fail(:selector_closure, "set resolution is incomplete")
    return document, completed_at
end

function _validate_release_notice(root, release, raw_by_id, source_id, evidence_class)
    path = _expect_string(release["release_notice_path"], "leaf.release.release_notice_path")
    digest = _expect_hash(release["release_notice_sha256"], "leaf release notice hash")
    document = _load_supporting_document(
        root,
        path,
        digest,
        "release notice",
        "beforeit-us-release-notice-evidence.v1",
        evidence_class,
    )
    _expect_exact_keys(document, ["artifact", "binding"], "release notice")
    binding = _expect_table(document["binding"], "release notice.binding")
    _expect_exact_keys(
        binding,
        [
            "source_id",
            "release_id",
            "official_locator",
            "official_release_timestamp_utc",
            "raw_artifact_ids",
            "raw_artifact_hashes",
        ],
        "release notice.binding",
    )
    _expect_exact(binding["source_id"], source_id, "release notice source")
    for key in ["release_id", "official_locator", "official_release_timestamp_utc"]
        _expect_exact(binding[key], release[key], "release notice $key")
    end
    ids = _expect_string_vector(binding["raw_artifact_ids"], "release notice raw IDs")
    hashes = _expect_string_vector(binding["raw_artifact_hashes"], "release notice raw hashes")
    expected_ids = sort!(collect(keys(raw_by_id)))
    ids == expected_ids || fail(:release_binding, "release notice raw artifact IDs are not exact")
    expected_hashes = [raw_by_id[id]["sha256"] for id in expected_ids]
    hashes == expected_hashes || fail(:release_binding, "release notice raw artifact hashes are not exact")
    return document
end

function _validate_domain_attestation(root, replica, raw_hash, evidence_class)
    path = _expect_string(
        replica["domain_attestation_path"],
        "leaf replica domain attestation path",
    )
    digest = _expect_hash(
        replica["domain_attestation_sha256"],
        "leaf replica domain attestation hash",
    )
    document = _load_supporting_document(
        root,
        path,
        digest,
        "replica domain attestation",
        "beforeit-us-replica-domain-attestation.v1",
        evidence_class,
    )
    _expect_exact_keys(document, ["artifact", "attestation"], "replica domain document")
    attestation = _expect_table(document["attestation"], "replica domain attestation")
    _expect_exact_keys(
        attestation,
        [
            "raw_sha256",
            "storage_domain_id",
            "storage_backend_id",
            "object_id",
            "custody_operator_id",
            "attested_at_utc",
            "signature_scheme",
            "signature_value",
        ],
        "replica domain attestation",
    )
    _expect_exact(attestation["raw_sha256"], raw_hash, "replica domain raw hash")
    for key in ["storage_domain_id", "storage_backend_id", "object_id"]
        _expect_exact(attestation[key], replica[key], "replica domain $key")
    end
    _expect_identifier(attestation["custody_operator_id"], "replica custody operator")
    attested_at =
        _parse_rfc3339(attestation["attested_at_utc"], "replica domain attested_at_utc")
    _expect_exact(
        attestation["signature_scheme"],
        "EXTERNAL_SIGNATURE_REFERENCE_V1",
        "replica domain signature scheme",
    )
    isempty(_expect_string(attestation["signature_value"], "replica domain signature")) &&
        fail(:replica_independence, "replica domain signature is empty")
    return document, attested_at
end

function _validate_external_timestamp(
        root,
        table,
        subject_sha256,
        evidence_class,
        subject_not_before,
    )
    _expect_exact_keys(
        table,
        ["evidence_subject_sha256", "receipt_path", "receipt_sha256"],
        "leaf.external_timestamp",
    )
    _expect_exact(
        table["evidence_subject_sha256"],
        subject_sha256,
        "leaf external timestamp subject",
    )
    path = _expect_string(table["receipt_path"], "leaf external timestamp path")
    digest = _expect_hash(table["receipt_sha256"], "leaf external timestamp hash")
    document = _load_supporting_document(
        root,
        path,
        digest,
        "external timestamp receipt",
        "beforeit-us-external-timestamp-attestation.v1",
        evidence_class,
    )
    _expect_exact_keys(document, ["artifact", "attestation"], "external timestamp document")
    attestation = _expect_table(document["attestation"], "external timestamp attestation")
    _expect_exact_keys(
        attestation,
        [
            "subject_sha256",
            "authority_id",
            "issued_at_utc",
            "token_path",
            "token_sha256",
            "token_media_type",
        ],
        "external timestamp attestation",
    )
    _expect_exact(attestation["subject_sha256"], subject_sha256, "timestamp subject")
    authority = _expect_identifier(attestation["authority_id"], "timestamp authority")
    startswith(authority, "local") &&
        fail(:timestamp_independence, "local timestamp authority is not external")
    issued_at = _parse_rfc3339(attestation["issued_at_utc"], "timestamp issued_at_utc")
    issued_at >= subject_not_before ||
        fail(:timestamp_binding, "external timestamp predates bound child evidence")
    issued_at < _parse_rfc3339(ORIGIN_TIMESTAMP, "origin timestamp") ||
        fail(:post_origin_evidence, "external timestamp is not pre-origin")
    token_path = _expect_string(attestation["token_path"], "timestamp token path")
    token_hash = _expect_hash(attestation["token_sha256"], "timestamp token hash")
    _safe_read(
        root,
        token_path;
        expected_hash = token_hash,
        label = "external timestamp token",
        maximum_bytes = MAXIMUM_TIMESTAMP_TOKEN_BYTES,
    )
    isempty(_expect_string(attestation["token_media_type"], "timestamp token media type")) &&
        fail(:timestamp_binding, "timestamp token media type is empty")
    return document, issued_at
end

function _receipt_subject(receipt)
    return canonical_sha256(
        Dict{String, Any}(
            "artifact_evidence_class" => receipt["artifact"]["evidence_class"],
            "binding" => receipt["binding"],
            "selector" => receipt["selector"],
            "capture" => receipt["capture"],
            "release" => receipt["release"],
            "raw_artifacts" => receipt["raw_artifacts"],
            "replicas" => receipt["replicas"],
            "retention" => receipt["retention"],
            "gates" => receipt["gates"],
        ),
    )
end

function _preflight_leaf_declared_sizes(root, parent_row, expected, evidence_class)
    receipt_path = _expect_string(parent_row["receipt_path"], "parent row receipt path")
    receipt_hash = _expect_hash(parent_row["receipt_sha256"], "parent row receipt hash")
    receipt, _, _, _ = _read_toml(
        root,
        receipt_path;
        expected_hash = receipt_hash,
        label = "profile size preflight $(expected["legacy_requirement_id"])/$(expected["legacy_profile_id"])",
    )
    _expect_exact_keys(
        receipt,
        [
            "artifact",
            "binding",
            "selector",
            "capture",
            "release",
            "raw_artifacts",
            "replicas",
            "leaf_verification",
            "approvals",
            "external_timestamp",
            "retention",
            "gates",
        ],
        "leaf size preflight",
    )
    _common_artifact(receipt, "leaf size preflight", LEAF_SCHEMA, evidence_class)
    raw_artifacts = _expect_vector(
        receipt["raw_artifacts"],
        "leaf size preflight raw_artifacts";
        maximum_items = MAXIMUM_RAW_ARTIFACTS_PER_PROFILE,
    )
    isempty(raw_artifacts) && fail(:raw_binding, "leaf size preflight has no raw artifacts")
    raw_sizes = Dict{String, Int}()
    total_raw_bytes = 0
    for (index, value) in enumerate(raw_artifacts)
        location = "leaf size preflight raw_artifacts[$index]"
        artifact = _expect_table(value, location)
        _expect_exact_keys(
            artifact,
            ["artifact_id", "path", "sha256", "byte_count", "media_type", "artifact_role"],
            location,
        )
        artifact_id = _expect_identifier(artifact["artifact_id"], "$location.artifact_id")
        haskey(raw_sizes, artifact_id) && fail(:raw_binding, "size preflight raw IDs duplicate")
        _validate_relative_path(_expect_string(artifact["path"], "$location.path"))
        _expect_hash(artifact["sha256"], "$location.sha256")
        byte_count = _expect_integer(artifact["byte_count"], "$location.byte_count")
        byte_count >= 0 || fail(:raw_binding, "$location byte count is negative")
        byte_count <= MAXIMUM_RAW_OR_REPLICA_FILE_BYTES ||
            fail(:resource_limit, "$location exceeds the frozen per-file byte ceiling")
        total_raw_bytes = _bounded_add(
            total_raw_bytes,
            byte_count,
            MAXIMUM_TOTAL_RAW_BYTES_PER_PROFILE,
            "leaf size preflight raw artifacts",
        )
        _expect_string(artifact["media_type"], "$location.media_type")
        _expect_string(artifact["artifact_role"], "$location.artifact_role")
        raw_sizes[artifact_id] = byte_count
    end

    replicas = _expect_vector(
        receipt["replicas"],
        "leaf size preflight replicas";
        maximum_items = MAXIMUM_REPLICAS_PER_PROFILE,
    )
    length(replicas) == 2 * length(raw_sizes) ||
        fail(:replica_independence, "size preflight requires two replicas per raw artifact")
    total_replica_bytes = 0
    for (index, value) in enumerate(replicas)
        location = "leaf size preflight replicas[$index]"
        replica = _expect_table(value, location)
        _expect_exact_keys(
            replica,
            [
                "replica_id",
                "raw_artifact_id",
                "path",
                "sha256",
                "byte_count",
                "storage_domain_id",
                "storage_backend_id",
                "object_id",
                "domain_attestation_path",
                "domain_attestation_sha256",
            ],
            location,
        )
        _expect_identifier(replica["replica_id"], "$location.replica_id")
        raw_id = _expect_identifier(replica["raw_artifact_id"], "$location.raw_artifact_id")
        haskey(raw_sizes, raw_id) ||
            fail(:replica_independence, "$location references an unknown raw artifact")
        _validate_relative_path(_expect_string(replica["path"], "$location.path"))
        _expect_hash(replica["sha256"], "$location.sha256")
        byte_count = _expect_integer(replica["byte_count"], "$location.byte_count")
        byte_count == raw_sizes[raw_id] ||
            fail(:replica_independence, "$location byte count differs from its raw artifact")
        byte_count <= MAXIMUM_RAW_OR_REPLICA_FILE_BYTES ||
            fail(:resource_limit, "$location exceeds the frozen per-file byte ceiling")
        total_replica_bytes = _bounded_add(
            total_replica_bytes,
            byte_count,
            MAXIMUM_TOTAL_REPLICA_BYTES_PER_PROFILE,
            "leaf size preflight replicas",
        )
        for key in ["storage_domain_id", "storage_backend_id", "object_id"]
            _expect_identifier(replica[key], "$location.$key")
        end
        _validate_relative_path(
            _expect_string(replica["domain_attestation_path"], "$location attestation path"),
        )
        _expect_hash(replica["domain_attestation_sha256"], "$location attestation hash")
    end
    return (raw_bytes = total_raw_bytes, replica_bytes = total_replica_bytes)
end

function _validate_raw_artifacts(root, values, dispatch)
    raw_artifacts = _expect_vector(
        values,
        "leaf.raw_artifacts";
        maximum_items = MAXIMUM_RAW_ARTIFACTS_PER_PROFILE,
    )
    isempty(raw_artifacts) && fail(:raw_binding, "leaf receipt has no raw artifacts")
    result = Dict{String, Dict{String, Any}}()
    states = Dict{String, Any}()
    paths = String[]
    validated = NamedTuple[]
    total_raw_bytes = 0
    for (index, value) in enumerate(raw_artifacts)
        location = "leaf.raw_artifacts[$index]"
        artifact = _expect_table(value, location)
        _expect_exact_keys(
            artifact,
            ["artifact_id", "path", "sha256", "byte_count", "media_type", "artifact_role"],
            location,
        )
        artifact_id = _expect_identifier(artifact["artifact_id"], "$location.artifact_id")
        haskey(result, artifact_id) && fail(:raw_binding, "duplicate raw artifact ID $artifact_id")
        path = _expect_string(artifact["path"], "$location.path")
        _validate_relative_path(path)
        digest = _expect_hash(artifact["sha256"], "$location.sha256")
        byte_count = _expect_integer(artifact["byte_count"], "$location.byte_count")
        byte_count >= 0 || fail(:raw_binding, "$location byte count is negative")
        byte_count <= MAXIMUM_RAW_OR_REPLICA_FILE_BYTES ||
            fail(:resource_limit, "$location exceeds the frozen per-file byte ceiling")
        total_raw_bytes = _bounded_add(
            total_raw_bytes,
            byte_count,
            MAXIMUM_TOTAL_RAW_BYTES_PER_PROFILE,
            "leaf raw artifacts",
        )
        media_type = _expect_string(artifact["media_type"], "$location.media_type")
        media_type in dispatch["permitted_media_types"] ||
            fail(:dispatch_mismatch, "$location media type is not permitted")
        role = _expect_string(artifact["artifact_role"], "$location.artifact_role")
        role in dispatch["permitted_artifact_roles"] ||
            fail(:dispatch_mismatch, "$location artifact role is not permitted")
        result[artifact_id] = Dict{String, Any}(artifact)
        push!(paths, path)
        push!(
            validated,
            (
                artifact_id = artifact_id,
                path = path,
                digest = digest,
                byte_count = byte_count,
                location = location,
            ),
        )
    end
    allunique(paths) || fail(:raw_binding, "raw artifact paths duplicate")
    for item in validated
        bytes, _, state = _safe_read(
            root,
            item.path;
            expected_hash = item.digest,
            label = "raw artifact $(item.artifact_id)",
            maximum_bytes = MAXIMUM_RAW_OR_REPLICA_FILE_BYTES,
        )
        length(bytes) == item.byte_count ||
            fail(:raw_binding, "$(item.location) byte count mismatch")
        states[item.artifact_id] = state
    end
    raw_inode_keys = [(state[1], state[2]) for state in Base.values(states)]
    allunique(raw_inode_keys) || fail(:raw_binding, "raw artifacts share an inode")
    return result, states, total_raw_bytes
end

function _validate_replicas(
        root,
        values,
        raw_by_id,
        raw_states,
        evidence_class,
        receipt_completed_at,
    )
    replicas = _expect_vector(
        values,
        "leaf.replicas";
        maximum_items = MAXIMUM_REPLICAS_PER_PROFILE,
    )
    length(replicas) == 2 * length(raw_by_id) ||
        fail(:replica_independence, "each raw artifact must have exactly two replicas")
    by_raw = Dict{String, Vector{Dict{String, Any}}}()
    all_paths = String[]
    all_attestation_paths = String[]
    all_replica_ids = String[]
    all_object_ids = String[]
    attestation_times = DateTime[]
    validated = NamedTuple[]
    total_replica_bytes = 0
    for (index, value) in enumerate(replicas)
        location = "leaf.replicas[$index]"
        replica = _expect_table(value, location)
        _expect_exact_keys(
            replica,
            [
                "replica_id",
                "raw_artifact_id",
                "path",
                "sha256",
                "byte_count",
                "storage_domain_id",
                "storage_backend_id",
                "object_id",
                "domain_attestation_path",
                "domain_attestation_sha256",
            ],
            location,
        )
        replica_id = _expect_identifier(replica["replica_id"], "$location.replica_id")
        raw_id = _expect_identifier(replica["raw_artifact_id"], "$location.raw_artifact_id")
        haskey(raw_by_id, raw_id) || fail(:replica_independence, "replica references unknown raw ID")
        path = _expect_string(replica["path"], "$location.path")
        _validate_relative_path(path)
        path != raw_by_id[raw_id]["path"] ||
            fail(:replica_independence, "canonical raw path cannot double as replica")
        digest = _expect_hash(replica["sha256"], "$location.sha256")
        _expect_exact(digest, raw_by_id[raw_id]["sha256"], "$location raw hash")
        byte_count = _expect_integer(replica["byte_count"], "$location.byte_count")
        _expect_exact(byte_count, raw_by_id[raw_id]["byte_count"], "$location byte count")
        byte_count <= MAXIMUM_RAW_OR_REPLICA_FILE_BYTES ||
            fail(:resource_limit, "$location exceeds the frozen per-file byte ceiling")
        total_replica_bytes = _bounded_add(
            total_replica_bytes,
            byte_count,
            MAXIMUM_TOTAL_REPLICA_BYTES_PER_PROFILE,
            "leaf replicas",
        )
        for key in ["storage_domain_id", "storage_backend_id", "object_id"]
            _expect_identifier(replica[key], "$location.$key")
        end
        attestation_path = _expect_string(
            replica["domain_attestation_path"],
            "$location.domain_attestation_path",
        )
        _validate_relative_path(attestation_path)
        _expect_hash(
            replica["domain_attestation_sha256"],
            "$location.domain_attestation_sha256",
        )
        push!(all_replica_ids, replica_id)
        push!(all_object_ids, replica["object_id"])
        push!(all_paths, path)
        push!(all_attestation_paths, attestation_path)
        push!(
            validated,
            (
                replica = replica,
                raw_id = raw_id,
                path = path,
                digest = digest,
                byte_count = byte_count,
                location = location,
            ),
        )
    end
    allunique(all_replica_ids) || fail(:replica_independence, "replica IDs are reused")
    allunique(all_object_ids) || fail(:replica_independence, "replica object IDs are reused")
    allunique(all_paths) || fail(:replica_independence, "replica paths duplicate")
    allunique(all_attestation_paths) ||
        fail(:replica_independence, "replica attestations are reused")
    raw_inodes = Set((state[1], state[2]) for state in Base.values(raw_states))
    replica_inodes = Set{Tuple{UInt64, UInt64}}()
    for item in validated
        bytes, _, state = _safe_read(
            root,
            item.path;
            expected_hash = item.digest,
            label = "replica",
            maximum_bytes = MAXIMUM_RAW_OR_REPLICA_FILE_BYTES,
        )
        length(bytes) == item.byte_count ||
            fail(:replica_independence, "$(item.location) byte count mismatch")
        inode = (UInt64(state[1]), UInt64(state[2]))
        inode in raw_inodes &&
            fail(:replica_independence, "replica shares an inode with canonical raw evidence")
        inode in replica_inodes &&
            fail(:replica_independence, "replicas share an inode")
        push!(replica_inodes, inode)
        _, attested_at =
            _validate_domain_attestation(root, item.replica, item.digest, evidence_class)
        attested_at >= receipt_completed_at ||
            fail(:replica_independence, "$(item.location) domain attestation predates evidence")
        attested_at < _parse_rfc3339(ORIGIN_TIMESTAMP, "origin timestamp") ||
            fail(:post_origin_evidence, "$(item.location) domain attestation is post-origin")
        push!(attestation_times, attested_at)
        push!(
            get!(by_raw, item.raw_id, Dict{String, Any}[]),
            Dict{String, Any}(item.replica),
        )
    end
    for (raw_id, group) in by_raw
        length(group) == 2 || fail(:replica_independence, "$raw_id does not have two replicas")
        for key in ["replica_id", "path", "storage_domain_id", "storage_backend_id", "object_id"]
            allunique(String.(getindex.(group, key))) ||
                fail(:replica_independence, "$raw_id replicas share $key")
        end
    end
    Set(keys(by_raw)) == Set(keys(raw_by_id)) ||
        fail(:replica_independence, "replica coverage is incomplete")
    return by_raw, maximum(attestation_times), total_replica_bytes
end

function _validate_leaf_verification(table, dispatch)
    _expect_exact_keys(
        table,
        [
            "verifier_id",
            "verifier_version",
            "verifier_source_path",
            "verifier_source_sha256",
            "verifier_test_path",
            "verifier_test_sha256",
            "verifier_qualified",
            "result",
            "result_receipt_path",
            "result_receipt_sha256",
            "independent_validation_receipt_schema_version",
            "independent_validation_receipt_path",
            "independent_validation_receipt_sha256",
        ],
        "leaf.leaf_verification",
    )
    for key in [
            "verifier_id",
            "verifier_version",
            "verifier_source_path",
            "verifier_source_sha256",
            "verifier_test_path",
            "verifier_test_sha256",
        ]
        _expect_exact(table[key], dispatch["leaf_$key"], "leaf verification $key")
    end
    qualified = _expect_bool(table["verifier_qualified"], "leaf verifier qualified")
    _expect_exact(qualified, dispatch["qualified"], "leaf verifier qualification")
    qualified === false ||
        fail(:gate_elevation, "this exact v3 has no qualified leaf-verifier branch")
    _expect_exact(
        table["independent_validation_receipt_schema_version"],
        dispatch["independent_validation_receipt_schema_version"],
        "leaf independent-validation schema",
    )
    _expect_exact(table["result"], "NOT_QUALIFIED_FAIL_CLOSED", "unqualified leaf result")
    for key in ["result_receipt_path", "independent_validation_receipt_path"]
        _expect_exact(table[key], "NOT_APPLICABLE", "unqualified leaf $key")
    end
    for key in ["result_receipt_sha256", "independent_validation_receipt_sha256"]
        _expect_exact(table[key], "UNAVAILABLE", "unqualified leaf $key")
    end
    return (qualified = false, latest_verification_at = nothing)
end

function _validate_leaf_receipt(
        root,
        parent_row,
        expected,
        dispatch,
        evidence_class,
    )
    receipt_path = _expect_string(parent_row["receipt_path"], "parent row receipt path")
    receipt_hash = _expect_hash(parent_row["receipt_sha256"], "parent row receipt hash")
    receipt, _, _, _ = _read_toml(
        root,
        receipt_path;
        expected_hash = receipt_hash,
        label = "profile receipt $(expected["legacy_requirement_id"])/$(expected["legacy_profile_id"])",
    )
    _expect_exact_keys(
        receipt,
        [
            "artifact",
            "binding",
            "selector",
            "capture",
            "release",
            "raw_artifacts",
            "replicas",
            "leaf_verification",
            "approvals",
            "external_timestamp",
            "retention",
            "gates",
        ],
        "leaf",
    )
    _common_artifact(receipt, "leaf", LEAF_SCHEMA, evidence_class)
    binding = _expect_table(receipt["binding"], "leaf.binding")
    _expect_exact_keys(
        binding,
        [
            "dispatch_id",
            "requirement_id",
            "source_id",
            "evidence_role",
            "legacy_profile_id",
            "active_profile_id",
            "legacy_selector",
            "legacy_selector_sha256",
            "active_selector",
            "active_selector_sha256",
            "legacy_v2_module_sha256",
            "legacy_v2_contract_sha256",
            "legacy_v2_semantic_sha256",
        ],
        "leaf.binding",
    )
    expected_bindings = Dict(
        "dispatch_id" => expected["dispatch_id"],
        "requirement_id" => expected["legacy_requirement_id"],
        "source_id" => expected["source_id"],
        "evidence_role" => dispatch["evidence_role"],
        "legacy_profile_id" => expected["legacy_profile_id"],
        "active_profile_id" => expected["active_profile_id"],
        "legacy_selector" => expected["legacy_selector"],
        "legacy_selector_sha256" => expected["legacy_selector_sha256"],
        "active_selector" => expected["active_selector"],
        "active_selector_sha256" => expected["active_selector_sha256"],
        "legacy_v2_module_sha256" => LEGACY_V2_MODULE_SHA256,
        "legacy_v2_contract_sha256" => LEGACY_V2_CONTRACT_SHA256,
        "legacy_v2_semantic_sha256" => LEGACY_V2_SEMANTIC_SHA256,
    )
    for (key, value) in expected_bindings
        _expect_exact(binding[key], value, "leaf.binding.$key", code = :leaf_binding_mismatch)
    end

    capture = _expect_table(receipt["capture"], "leaf.capture")
    _expect_exact_keys(
        capture,
        [
            "capture_id",
            "capture_started_at_utc",
            "receipt_completed_at_utc",
            "availability_upper_bound_utc",
            "reference_period_start",
            "reference_period_end",
        ],
        "leaf.capture",
    )
    _expect_exact(capture["capture_id"], expected["capture_id"], "leaf capture ID")
    started_at = _parse_rfc3339(capture["capture_started_at_utc"], "leaf capture start")
    completed_at = _parse_rfc3339(capture["receipt_completed_at_utc"], "leaf receipt completion")
    availability = _parse_rfc3339(capture["availability_upper_bound_utc"], "leaf availability")
    started_at <= completed_at || fail(:capture_timing, "capture completes before it starts")
    completed_at == availability ||
        fail(:capture_timing, "availability upper bound must equal receipt completion")
    completed_at < _parse_rfc3339(ORIGIN_TIMESTAMP, "origin timestamp") ||
        fail(:post_origin_evidence, "profile receipt is not strictly pre-origin")
    reference_start = _parse_date(capture["reference_period_start"], "leaf reference start")
    reference_end = _parse_date(capture["reference_period_end"], "leaf reference end")
    reference_start <= reference_end || fail(:capture_timing, "reference period is inverted")
    reference_end <= Date(completed_at) ||
        fail(:capture_timing, "reference period ends after receipt completion")
    expected["completion_date"] == "NOT_APPLICABLE" ||
        Date(completed_at) == Date(expected["completion_date"]) ||
        fail(:capture_timing, "receipt completion date does not match frozen v2")

    release = _expect_table(receipt["release"], "leaf.release")
    _expect_exact_keys(
        release,
        [
            "release_id",
            "official_locator",
            "official_release_timestamp_utc",
            "release_notice_path",
            "release_notice_sha256",
        ],
        "leaf.release",
    )
    _expect_identifier(release["release_id"], "leaf release ID")
    isempty(_expect_string(release["official_locator"], "leaf official locator")) &&
        fail(:release_binding, "official locator is empty")
    official_release = _expect_string(
        release["official_release_timestamp_utc"],
        "leaf official release timestamp",
    )
    official_release == "UNKNOWN_NOT_ASSERTED" ||
        _parse_rfc3339(official_release, "leaf official release timestamp") <= completed_at ||
        fail(:release_binding, "official release timestamp follows receipt completion")

    raw_by_id, raw_states, raw_byte_count =
        _validate_raw_artifacts(root, receipt["raw_artifacts"], dispatch)
    _, latest_replica_attestation_at, replica_byte_count = _validate_replicas(
        root,
        receipt["replicas"],
        raw_by_id,
        raw_states,
        evidence_class,
        completed_at,
    )

    selector = _expect_table(receipt["selector"], "leaf.selector")
    _expect_exact_keys(
        selector,
        [
            "candidate_catalog_path",
            "candidate_catalog_sha256",
            "resolution_path",
            "resolution_sha256",
            "eligible_candidate_count",
            "selected_candidate_rank",
            "set_resolution_complete",
        ],
        "leaf.selector",
    )
    _expect_exact_integer(selector["eligible_candidate_count"], 1, "leaf selector eligible count")
    _expect_exact_integer(selector["selected_candidate_rank"], 1, "leaf selector selected rank")
    _expect_bool(selector["set_resolution_complete"], "leaf selector set resolution") === true ||
        fail(:selector_closure, "leaf selector set resolution is incomplete")
    catalog, selected, catalog_completed_at =
        _validate_catalog(
        root,
        selector,
        binding,
        raw_by_id,
        release,
        evidence_class,
        completed_at,
    )
    _, resolution_completed_at = _validate_resolution(
        root,
        selector,
        binding,
        selector["candidate_catalog_sha256"],
        selected,
        evidence_class,
        capture["reference_period_start"],
        capture["reference_period_end"],
        catalog_completed_at,
    )
    _validate_release_notice(root, release, raw_by_id, expected["source_id"], evidence_class)

    retention = _expect_table(receipt["retention"], "leaf.retention")
    _expect_exact_keys(
        retention,
        ["custody_policy_id", "custody_schema_version", "minimum_retain_until_utc"],
        "leaf.retention",
    )
    _expect_exact(
        retention["custody_policy_id"],
        "beforeit-us-retention-custody-v2.2026q3",
        "leaf custody policy",
    )
    _expect_exact(retention["custody_schema_version"], RETENTION_SCHEMA, "leaf custody schema")
    _expect_exact(retention["minimum_retain_until_utc"], MINIMUM_RETAIN_UNTIL, "leaf retention")
    gates = _expect_table(receipt["gates"], "leaf.gates")
    _all_false_gates(gates, "leaf.gates")
    subject_sha256 = _receipt_subject(receipt)
    child_evidence_at = maximum(
        [
            completed_at,
            latest_replica_attestation_at,
            catalog_completed_at,
            resolution_completed_at,
        ],
    )
    timestamp = _expect_table(receipt["external_timestamp"], "leaf.external_timestamp")
    _, timestamp_at = _validate_external_timestamp(
        root,
        timestamp,
        subject_sha256,
        evidence_class,
        child_evidence_at,
    )
    approvals = _expect_table(receipt["approvals"], "leaf.approvals")
    approval_at = _validate_approval_pair(
        root,
        approvals,
        subject_sha256,
        evidence_class,
        "leaf.approvals";
        decision = "APPROVED_FOR_ORIGIN_INFORMATION_PROFILE_ONLY",
        not_before = max(child_evidence_at, timestamp_at),
    )
    leaf_verification = _expect_table(receipt["leaf_verification"], "leaf.leaf_verification")
    verification_result = _validate_leaf_verification(leaf_verification, dispatch)
    return (
        receipt_physical_sha256 = receipt_hash,
        receipt_subject_sha256 = subject_sha256,
        qualified = verification_result.qualified,
        latest_evidence_at = maximum(
            [
                completed_at,
                latest_replica_attestation_at,
                catalog_completed_at,
                resolution_completed_at,
                approval_at,
                timestamp_at,
            ],
        ),
        raw_artifact_count = length(raw_by_id),
        replica_count = 2 * length(raw_by_id),
        raw_byte_count = raw_byte_count,
        replica_byte_count = replica_byte_count,
        catalog_sha256 = catalog["artifact"]["content_sha256"],
    )
end

function _result_payload(result)
    artifact = _expect_table(result["artifact"], "result.artifact")
    artifact["content_sha256"] = document_content_sha256(result)
    return result
end

function _validate_result_shape(result::AbstractDict)
    _validate_value_bounds(result, "result")
    _expect_exact_keys(
        result,
        [
            "artifact",
            "verification",
            "profile_results",
            "blocking_reasons",
            "limitations",
            "scientific_gates",
            "action_counts",
        ],
        "result",
    )
    artifact = _expect_table(result["artifact"], "result.artifact")
    _expect_exact_keys(
        artifact,
        ["schema_version", "canonicalization", "content_sha256"],
        "result.artifact",
    )
    _expect_exact(artifact["schema_version"], RESULT_SCHEMA, "result schema")
    _expect_exact(artifact["canonicalization"], CANONICALIZATION, "result canonicalization")
    _expect_document_hash(result, "result")
    verification = _expect_table(result["verification"], "result.verification")
    _expect_exact_keys(
        verification,
        [
            "status",
            "claim_ceiling",
            "maximum_status",
            "successor_only_status",
            "current_policy_ready_status_reachable",
            "authenticated_trust_anchor_count",
            "authenticated_signature_validator_count",
            "authenticated_timestamp_validator_count",
            "same_user_path_race_resistance_attested",
            "parent_path",
            "parent_physical_sha256",
            "origin_information_set_sha256",
            "material_subject_sha256",
            "evidence_class",
            "policy_physical_sha256",
            "policy_content_sha256",
            "legacy_requirement_count",
            "legacy_profile_count",
            "opaque_audit_tuple_sha256",
            "opaque_audit_serialization_recovered",
            "typed_length_tuple_sha256",
            "qualified_dispatch_count",
            "qualified_profile_count",
            "blocking_reason_count",
            "limitation_count",
            "action_count_scope",
            "verifier_truth_artifact_access_count",
            "verifier_model_execution_count",
            "verifier_leaf_source_execution_count",
            "total_raw_artifact_bytes",
            "total_replica_bytes",
        ],
        "result.verification",
    )
    status = _expect_string(verification["status"], "result status")
    status == CANNOT_RUN || fail(:gate_elevation, "this exact v3 is permanently CANNOT_RUN")
    _expect_exact(verification["claim_ceiling"], status, "result claim ceiling")
    _expect_exact(verification["maximum_status"], CANNOT_RUN, "result maximum status")
    _expect_exact(
        verification["successor_only_status"],
        READY_FOR_SEAL,
        "result successor-only status",
    )
    _expect_bool(
        verification["current_policy_ready_status_reachable"],
        "result current-policy READY reachability",
    ) === false || fail(:gate_elevation, "this v3 cannot reach READY")
    for key in [
            "authenticated_trust_anchor_count",
            "authenticated_signature_validator_count",
            "authenticated_timestamp_validator_count",
        ]
        _expect_exact_integer(verification[key], 0, "result $key")
    end
    _expect_bool(
        verification["same_user_path_race_resistance_attested"],
        "result same-user race attestation",
    ) === false || fail(:gate_elevation, "same-user path-race resistance is unattested")
    parent_path = _expect_string(verification["parent_path"], "result parent path")
    _validate_relative_path(parent_path)
    _expect_hash(verification["parent_physical_sha256"], "result parent physical hash")
    _expect_exact(
        verification["origin_information_set_sha256"],
        verification["parent_physical_sha256"],
        "origin information set identity",
    )
    _expect_hash(verification["material_subject_sha256"], "result material subject")
    evidence_class = _expect_string(verification["evidence_class"], "result evidence class")
    evidence_class in ("PROSPECTIVE_NONSYNTHETIC", "SYNTHETIC_TEST_ONLY") ||
        fail(:invalid_evidence_class, "result evidence class is not closed")
    _expect_exact(verification["policy_physical_sha256"], POLICY_PHYSICAL_SHA256, "result policy")
    _expect_exact(verification["policy_content_sha256"], POLICY_CONTENT_SHA256, "result policy content")
    _expect_exact_integer(verification["legacy_requirement_count"], 21, "result requirement count")
    _expect_exact_integer(verification["legacy_profile_count"], 107, "result profile count")
    _expect_exact(
        verification["opaque_audit_tuple_sha256"],
        OPAQUE_AUDIT_TUPLE_SHA256,
        "result opaque tuple",
    )
    _expect_bool(
        verification["opaque_audit_serialization_recovered"],
        "result opaque audit serialization",
    ) === false || fail(:audit_overclaim, "opaque audit serialization was not recovered")
    _expect_exact(
        verification["typed_length_tuple_sha256"],
        TYPED_LENGTH_TUPLE_SHA256,
        "result typed tuple",
    )
    profile_results = _expect_vector(result["profile_results"], "result.profile_results")
    length(profile_results) == 107 || fail(:parent_bijection, "result must cover 107 profiles")
    calculated_raw_bytes = 0
    calculated_replica_bytes = 0
    for (index, value) in enumerate(profile_results)
        row = _expect_table(value, "result.profile_results[$index]")
        _expect_exact_keys(
            row,
            [
                "requirement_id",
                "legacy_profile_id",
                "active_profile_id",
                "dispatch_id",
                "receipt_physical_sha256",
                "receipt_subject_sha256",
                "qualified",
                "raw_artifact_count",
                "replica_count",
                "raw_artifact_bytes",
                "replica_bytes",
            ],
            "result.profile_results[$index]",
        )
        for key in ["requirement_id", "legacy_profile_id", "active_profile_id", "dispatch_id"]
            _expect_identifier(row[key], "result.profile_results[$index].$key")
        end
        for key in ["receipt_physical_sha256", "receipt_subject_sha256"]
            _expect_hash(row[key], "result.profile_results[$index].$key")
        end
        _expect_bool(row["qualified"], "result.profile_results[$index].qualified") === false ||
            fail(:gate_elevation, "exact v3 profile results cannot be qualified")
        raw_count = _expect_integer(
            row["raw_artifact_count"],
            "result.profile_results[$index].raw_artifact_count",
        )
        replica_count = _expect_integer(
            row["replica_count"],
            "result.profile_results[$index].replica_count",
        )
        1 <= raw_count <= MAXIMUM_RAW_ARTIFACTS_PER_PROFILE ||
            fail(:resource_limit, "result raw-artifact count exceeds the frozen ceiling")
        replica_count == 2 * raw_count ||
            fail(:replica_independence, "result replica count does not match raw coverage")
        raw_bytes = _expect_integer(
            row["raw_artifact_bytes"],
            "result.profile_results[$index].raw_artifact_bytes",
        )
        replica_bytes = _expect_integer(
            row["replica_bytes"],
            "result.profile_results[$index].replica_bytes",
        )
        0 <= raw_bytes <= MAXIMUM_TOTAL_RAW_BYTES_PER_PROFILE ||
            fail(:resource_limit, "result profile raw bytes exceed the frozen ceiling")
        0 <= replica_bytes <= MAXIMUM_TOTAL_REPLICA_BYTES_PER_PROFILE ||
            fail(:resource_limit, "result profile replica bytes exceed the frozen ceiling")
        replica_bytes == 2 * raw_bytes ||
            fail(:replica_independence, "result profile replica bytes differ from exact copies")
        calculated_raw_bytes = _bounded_add(
            calculated_raw_bytes,
            raw_bytes,
            MAXIMUM_TOTAL_RAW_BYTES_PER_PARENT,
            "result parent raw bytes",
        )
        calculated_replica_bytes = _bounded_add(
            calculated_replica_bytes,
            replica_bytes,
            MAXIMUM_TOTAL_REPLICA_BYTES_PER_PARENT,
            "result parent replica bytes",
        )
    end
    blockers = _expect_vector(result["blocking_reasons"], "result.blocking_reasons")
    limitations = _expect_vector(result["limitations"], "result.limitations")
    _expect_exact_integer(
        verification["blocking_reason_count"],
        length(blockers),
        "result blocker count",
    )
    _expect_exact_integer(
        verification["limitation_count"],
        length(limitations),
        "result limitation count",
    )
    _expect_exact(
        verification["action_count_scope"],
        "COMMON_ORIGIN_ACQUISITION_V3_VERIFIER_INVOCATION_ONLY",
        "result action-count scope",
    )
    for key in [
            "verifier_truth_artifact_access_count",
            "verifier_model_execution_count",
            "verifier_leaf_source_execution_count",
        ]
        _expect_exact_integer(verification[key], 0, "result $key")
    end
    _expect_exact_integer(verification["qualified_dispatch_count"], 0, "result qualified dispatches")
    _expect_exact_integer(verification["qualified_profile_count"], 0, "result qualified profiles")
    total_raw_bytes = _expect_integer(
        verification["total_raw_artifact_bytes"],
        "result total raw artifact bytes",
    )
    total_replica_bytes =
        _expect_integer(verification["total_replica_bytes"], "result total replica bytes")
    0 <= total_raw_bytes <= MAXIMUM_TOTAL_RAW_BYTES_PER_PARENT ||
        fail(:resource_limit, "result raw bytes exceed the parent ceiling")
    0 <= total_replica_bytes <= MAXIMUM_TOTAL_REPLICA_BYTES_PER_PARENT ||
        fail(:resource_limit, "result replica bytes exceed the parent ceiling")
    total_raw_bytes == calculated_raw_bytes ||
        fail(:binding_mismatch, "result total raw bytes do not match profile rows")
    total_replica_bytes == calculated_replica_bytes ||
        fail(:binding_mismatch, "result total replica bytes do not match profile rows")
    gates = _expect_table(result["scientific_gates"], "result.scientific_gates")
    _all_false_gates(gates, "result.scientific_gates")
    actions = _expect_table(result["action_counts"], "result.action_counts")
    _expect_exact_keys(
        actions,
        [
            "verifier_network_requests",
            "verifier_filesystem_writes",
            "verifier_truth_artifacts_accessed",
            "verifier_model_modules_imported",
            "verifier_models_constructed",
            "verifier_models_executed",
            "verifier_forecasts_emitted",
            "verifier_scores_computed",
            "verifier_leaf_sources_executed",
            "verifier_source_inventory_mutations",
        ],
        "result.action_counts",
    )
    for key in keys(actions)
        _expect_exact_integer(actions[key], 0, "result.action_counts.$key"; code = :action_boundary)
    end
    return result
end

function verify_parent(
        parent_path::AbstractString;
        evidence_root::AbstractString = REPOSITORY_ROOT,
    )
    canonical_evidence_root, evidence_root_states = _snapshot_safe_root(evidence_root)
    context = _load_policy_context()
    parent, _, parent_physical_sha256, _ = _read_toml(
        canonical_evidence_root,
        parent_path;
        label = "common-origin acquisition parent",
    )
    parent_state = _validate_parent_shape(parent, context)
    custody_path = _expect_string(parent_state.custody["receipt_path"], "parent custody path")
    custody_hash = _expect_hash(parent_state.custody["receipt_sha256"], "parent custody hash")

    profile_results = Dict{String, Any}[]
    blocking_reasons = Dict{String, Any}[]
    qualified_profiles = 0
    latest_child_evidence_times = DateTime[]
    total_parent_raw_bytes = 0
    total_parent_replica_bytes = 0
    preflight_parent_raw_bytes = 0
    preflight_parent_replica_bytes = 0
    for index in eachindex(parent_state.expected_rows)
        expected = parent_state.expected_rows[index]
        parent_row = parent["rows"][index]
        declared = _preflight_leaf_declared_sizes(
            canonical_evidence_root,
            parent_row,
            expected,
            parent_state.evidence_class,
        )
        preflight_parent_raw_bytes = _bounded_add(
            preflight_parent_raw_bytes,
            declared.raw_bytes,
            MAXIMUM_TOTAL_RAW_BYTES_PER_PARENT,
            "parent raw-evidence metadata preflight",
        )
        preflight_parent_replica_bytes = _bounded_add(
            preflight_parent_replica_bytes,
            declared.replica_bytes,
            MAXIMUM_TOTAL_REPLICA_BYTES_PER_PARENT,
            "parent replica-evidence metadata preflight",
        )
    end
    for index in eachindex(parent_state.expected_rows)
        expected = parent_state.expected_rows[index]
        parent_row = parent["rows"][index]
        dispatch = context.dispatches[expected["dispatch_id"]]
        leaf = _validate_leaf_receipt(
            canonical_evidence_root,
            parent_row,
            expected,
            dispatch,
            parent_state.evidence_class,
        )
        leaf.qualified && (qualified_profiles += 1)
        push!(latest_child_evidence_times, leaf.latest_evidence_at)
        total_parent_raw_bytes = _bounded_add(
            total_parent_raw_bytes,
            leaf.raw_byte_count,
            MAXIMUM_TOTAL_RAW_BYTES_PER_PARENT,
            "parent raw evidence",
        )
        total_parent_replica_bytes = _bounded_add(
            total_parent_replica_bytes,
            leaf.replica_byte_count,
            MAXIMUM_TOTAL_REPLICA_BYTES_PER_PARENT,
            "parent replica evidence",
        )
        push!(
            profile_results,
            Dict{String, Any}(
                "requirement_id" => expected["legacy_requirement_id"],
                "legacy_profile_id" => expected["legacy_profile_id"],
                "active_profile_id" => expected["active_profile_id"],
                "dispatch_id" => expected["dispatch_id"],
                "receipt_physical_sha256" => leaf.receipt_physical_sha256,
                "receipt_subject_sha256" => leaf.receipt_subject_sha256,
                "qualified" => leaf.qualified,
                "raw_artifact_count" => leaf.raw_artifact_count,
                "replica_count" => leaf.replica_count,
                "raw_artifact_bytes" => leaf.raw_byte_count,
                "replica_bytes" => leaf.replica_byte_count,
            ),
        )
    end
    total_parent_raw_bytes == preflight_parent_raw_bytes ||
        fail(:file_race, "raw declarations changed after parent metadata preflight")
    total_parent_replica_bytes == preflight_parent_replica_bytes ||
        fail(:file_race, "replica declarations changed after parent metadata preflight")
    latest_child_evidence_at = maximum(latest_child_evidence_times)
    _, custody_approved_at = _validate_custody(
        canonical_evidence_root,
        custody_path,
        custody_hash,
        parent_state.evidence_class,
        parent_state.custody_subject_sha256,
        latest_child_evidence_at,
    )
    _validate_approval_pair(
        canonical_evidence_root,
        parent_state.approvals,
        parent_state.material_subject_sha256,
        parent_state.evidence_class,
        "parent.approvals";
        decision = "APPROVED_FOR_ORIGIN_INFORMATION_SET_ONLY",
        not_before = max(latest_child_evidence_at, custody_approved_at),
    )
    qualified_dispatches = count(dispatch -> dispatch["qualified"], values(context.dispatches))
    for dispatch in sort!(collect(values(context.dispatches)); by = item -> item["dispatch_id"])
        if !dispatch["qualified"]
            for blocker_id in dispatch["blocker_ids"]
                push!(
                    blocking_reasons,
                    Dict{String, Any}(
                        "blocker_id" => blocker_id,
                        "requirement_id" => dispatch["requirement_id"],
                        "dispatch_id" => dispatch["dispatch_id"],
                        "detail" => "immutable dispatch is not backed by an accepted qualified leaf verifier",
                    ),
                )
            end
        end
    end
    if parent_state.evidence_class != "PROSPECTIVE_NONSYNTHETIC"
        push!(
            blocking_reasons,
            Dict{String, Any}(
                "blocker_id" => "synthetic_parent_not_readiness_evidence",
                "requirement_id" => "ALL",
                "dispatch_id" => "ALL",
                "detail" => "synthetic fixtures can exercise verification but cannot satisfy readiness",
            ),
        )
    end
    if context.policy["effr_supersession"]["status"] != "FROZEN_ACCEPTED"
        push!(
            blocking_reasons,
            Dict{String, Any}(
                "blocker_id" => "effr_semantic_supersession_overlay_unfrozen",
                "requirement_id" => "frbny_effr_tier1",
                "dispatch_id" => "dispatch.frbny_effr_tier1.v1",
                "detail" => "the endpoint profile is pinned only at CANNOT_RUN and its three semantic-supersession decisions remain unfrozen",
            ),
        )
    end
    push!(
        blocking_reasons,
        Dict{String, Any}(
            "blocker_id" => "current_v3_authenticated_trust_roots_absent",
            "requirement_id" => "ALL",
            "dispatch_id" => "ALL",
            "detail" => "this exact schema has no pinned authenticated signature or timestamp trust root and is permanently CANNOT_RUN",
        ),
    )
    sort!(
        blocking_reasons;
        by = item -> (item["blocker_id"], item["requirement_id"], item["dispatch_id"]),
    )
    limitations = Dict{String, Any}[
        Dict(
            "limitation_id" => "opaque_audit_tuple_serialization_unrecoverable",
            "detail" => "9fa271... is retained only as the published audit fingerprint; exact coverage is independently rederived under bff32b...",
        ),
        Dict(
            "limitation_id" => "external_signature_references_not_cryptographically_verified",
            "detail" => "stdlib metadata verification binds distinct attestation bytes and identities but does not authenticate external public keys",
        ),
        Dict(
            "limitation_id" => "local_hashes_do_not_authenticate_publishers",
            "detail" => "rehashing proves local fixity and binding, not publisher or transport provenance",
        ),
        Dict(
            "limitation_id" => "preseal_custody_covenant_does_not_load_future_truth",
            "detail" => "release remains contingent on later mature-receipt completion, timestamping, replication, and audit",
        ),
        Dict(
            "limitation_id" => "same_user_path_race_resistance_unattested",
            "detail" => "ancestor/root/leaf states are checked before and after reads, but stdlib pathname checks are not a kernel-atomic same-user race defense",
        ),
    ]
    status = CANNOT_RUN
    result = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => RESULT_SCHEMA,
            "canonicalization" => CANONICALIZATION,
            "content_sha256" => repeat("0", 64),
        ),
        "verification" => Dict{String, Any}(
            "status" => status,
            "claim_ceiling" => status,
            "maximum_status" => CANNOT_RUN,
            "successor_only_status" => READY_FOR_SEAL,
            "current_policy_ready_status_reachable" => CURRENT_POLICY_READY_REACHABLE,
            "authenticated_trust_anchor_count" => 0,
            "authenticated_signature_validator_count" => 0,
            "authenticated_timestamp_validator_count" => 0,
            "same_user_path_race_resistance_attested" => false,
            "parent_path" => String(parent_path),
            "parent_physical_sha256" => parent_physical_sha256,
            "origin_information_set_sha256" => parent_physical_sha256,
            "material_subject_sha256" => parent_state.material_subject_sha256,
            "evidence_class" => parent_state.evidence_class,
            "policy_physical_sha256" => POLICY_PHYSICAL_SHA256,
            "policy_content_sha256" => POLICY_CONTENT_SHA256,
            "legacy_requirement_count" => 21,
            "legacy_profile_count" => 107,
            "opaque_audit_tuple_sha256" => OPAQUE_AUDIT_TUPLE_SHA256,
            "opaque_audit_serialization_recovered" => false,
            "typed_length_tuple_sha256" => TYPED_LENGTH_TUPLE_SHA256,
            "qualified_dispatch_count" => qualified_dispatches,
            "qualified_profile_count" => qualified_profiles,
            "blocking_reason_count" => length(blocking_reasons),
            "limitation_count" => length(limitations),
            "action_count_scope" =>
                "COMMON_ORIGIN_ACQUISITION_V3_VERIFIER_INVOCATION_ONLY",
            "verifier_truth_artifact_access_count" => 0,
            "verifier_model_execution_count" => 0,
            "verifier_leaf_source_execution_count" => 0,
            "total_raw_artifact_bytes" => total_parent_raw_bytes,
            "total_replica_bytes" => total_parent_replica_bytes,
        ),
        "profile_results" => profile_results,
        "blocking_reasons" => blocking_reasons,
        "limitations" => limitations,
        "scientific_gates" => Dict{String, Any}(key => false for key in GATE_KEYS),
        "action_counts" => Dict{String, Any}(
            "verifier_network_requests" => 0,
            "verifier_filesystem_writes" => 0,
            "verifier_truth_artifacts_accessed" => 0,
            "verifier_model_modules_imported" => 0,
            "verifier_models_constructed" => 0,
            "verifier_models_executed" => 0,
            "verifier_forecasts_emitted" => 0,
            "verifier_scores_computed" => 0,
            "verifier_leaf_sources_executed" => 0,
            "verifier_source_inventory_mutations" => 0,
        ),
    )
    _recheck_path_states(evidence_root_states, "complete parent verification evidence root")
    _result_payload(result)
    return _validate_result_shape(result)
end

function validate_result(
        result::AbstractDict;
        evidence_root::AbstractString,
    )
    _validate_result_shape(result)
    verification = _expect_table(result["verification"], "result.verification")
    parent_path = _expect_string(verification["parent_path"], "result parent path")
    replayed = verify_parent(parent_path; evidence_root = evidence_root)
    result == replayed ||
        fail(:result_replay_mismatch, "result does not exactly match replay from its physical parent")
    canonical_sha256(result) == canonical_sha256(replayed) ||
        fail(:result_replay_mismatch, "result canonical identity differs from replay")
    return result
end

function load_parent(parent_path::AbstractString; evidence_root::AbstractString = REPOSITORY_ROOT)
    canonical_evidence_root, evidence_root_states = _snapshot_safe_root(evidence_root)
    document, _, _, _ =
        _read_toml(canonical_evidence_root, parent_path; label = "common-origin parent")
    context = _load_policy_context()
    _validate_parent_shape(document, context)
    _recheck_path_states(evidence_root_states, "complete parent load evidence root")
    return deepcopy(document)
end

end
