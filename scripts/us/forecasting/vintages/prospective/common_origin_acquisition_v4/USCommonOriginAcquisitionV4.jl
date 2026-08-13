module USCommonOriginAcquisitionV4

using SHA
using TOML

export AuthenticatedEvidenceV4Error,
    CANNOT_RUN,
    CANONICALIZATION,
    EXPECTED_BLOCKERS,
    canonical_subject_bytes,
    canonical_subject_sha256,
    declared_successor_crypto_runtime,
    load_policy,
    validate_parent,
    validate_profile_selections,
    validate_raw_object_catalog,
    validate_result,
    verify_parent

const CANNOT_RUN = "CANNOT_RUN"
const CANONICALIZATION =
    "BEFOREIT_US_AUTHENTICATED_EVIDENCE_V4_DOMAIN_SEPARATED_TYPED_LENGTH_V1"
const SUBJECT_DOMAIN = "BeforeIT/US/authenticated-evidence/v4/canonical-subject/v1\0"
const POLICY_FILENAME = "common_origin_acquisition_v4_policy.toml"
const POLICY_PATH = joinpath(@__DIR__, POLICY_FILENAME)
const HEX64_PATTERN = raw"\A[0-9a-f]{64}\z"
const IDENTIFIER_PATTERN = raw"\A[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?\z"
const RELATIVE_PATH_PATTERN = raw"\A[A-Za-z0-9][A-Za-z0-9._/-]{0,510}[A-Za-z0-9]\z"
const HTTPS_URI_PATTERN =
    raw"\Ahttps://[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?(?:\?[A-Za-z0-9._~!$&'()*+,;=:@%/?-]*)?\z"
const ALLOWED_MEDIA_TYPES = (
    "application/json",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/zip",
    "text/csv",
    "text/plain",
    "text/tab-separated-values",
)
const MAX_CANONICAL_DEPTH = 32
const MAX_CANONICAL_ITEMS = 4_096
const MAX_CANONICAL_STRING_BYTES = 1_048_576
const MAX_RAW_OBJECT_BYTES = 536_870_912
const MAX_CATALOG_BYTES = 2_147_483_648
const EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const NO_REDIRECT_POLICY = "FORBID_REDIRECTS_REQUIRE_URI_EQUALITY"

const EXPECTED_BLOCKERS = (
    "production_trust_bootstrap_absent",
    "production_role_keys_absent",
    "authenticated_signature_validation_absent",
    "rfc3161_timestamp_evidence_absent",
    "production_profile_projection_bindings_absent",
    "qualified_leaf_verifiers_absent",
    "complete_107_profile_parent_absent",
    "effr_supersession_unfrozen",
    "physical_raw_and_replica_evidence_absent",
    "external_custody_domain_evidence_absent",
    "verifier_release_authentication_absent",
    "validator_source_and_runtime_bootstrap_unauthenticated",
    "julia_executable_sysimage_depot_preferences_cache_not_closed",
    "jll_transitive_dependency_closure_not_independently_authenticated",
)

const BEA_PROFILE_BINDINGS = (
    (
        profile_id = "faat301esi_net_stock",
        object_id = "bea-fixed-assets-section-3",
        table_id = "FAAt301ESI",
        interpretation = "NET_STOCK",
    ),
    (
        profile_id = "faat304esi_depreciation",
        object_id = "bea-fixed-assets-section-3",
        table_id = "FAAt304ESI",
        interpretation = "DEPRECIATION",
    ),
    (
        profile_id = "faat307esi_investment",
        object_id = "bea-fixed-assets-section-3",
        table_id = "FAAt307ESI",
        interpretation = "INVESTMENT",
    ),
    (
        profile_id = "faat501_residential_net_stock",
        object_id = "bea-fixed-assets-section-5",
        table_id = "FAAt501",
        interpretation = "RESIDENTIAL_NET_STOCK",
    ),
    (
        profile_id = "faat504_residential_depreciation",
        object_id = "bea-fixed-assets-section-5",
        table_id = "FAAt504",
        interpretation = "RESIDENTIAL_DEPRECIATION",
    ),
    (
        profile_id = "faat507_residential_investment",
        object_id = "bea-fixed-assets-section-5",
        table_id = "FAAt507",
        interpretation = "RESIDENTIAL_INVESTMENT",
    ),
    (
        profile_id = "faat701_government_net_stock",
        object_id = "bea-fixed-assets-section-7",
        table_id = "FAAt701",
        interpretation = "GOVERNMENT_NET_STOCK",
    ),
    (
        profile_id = "faat703_government_depreciation",
        object_id = "bea-fixed-assets-section-7",
        table_id = "FAAt703",
        interpretation = "GOVERNMENT_DEPRECIATION",
    ),
)
const BLS_PROFILES = (
    "cps_employed",
    "cps_inactive",
    "cps_labor_force",
    "cps_population",
    "cps_unemployed",
    "cps_unemployment_rate",
)
const BLS_OBJECT_SET = (
    "bls-cps-history-chunk-001",
    "bls-cps-history-chunk-002",
    "bls-cps-history-chunk-003",
)
const BLS_PROFILE_BINDINGS = (
    (profile_id = "cps_employed", interpretation = "EMPLOYED"),
    (profile_id = "cps_inactive", interpretation = "INACTIVE"),
    (profile_id = "cps_labor_force", interpretation = "LABOR_FORCE"),
    (profile_id = "cps_population", interpretation = "POPULATION"),
    (profile_id = "cps_unemployed", interpretation = "UNEMPLOYED"),
    (profile_id = "cps_unemployment_rate", interpretation = "UNEMPLOYMENT_RATE"),
)
const REQUIRED_DEMONSTRATION_PROFILES = (
    "cps_employed",
    "cps_inactive",
    "cps_labor_force",
    "cps_population",
    "cps_unemployed",
    "cps_unemployment_rate",
    "faat301esi_net_stock",
    "faat304esi_depreciation",
    "faat307esi_investment",
    "faat501_residential_net_stock",
    "faat504_residential_depreciation",
    "faat507_residential_investment",
    "faat701_government_net_stock",
    "faat703_government_depreciation",
)
const REQUIRED_CATALOG_OBJECTS = (
    "bea-fixed-assets-section-3",
    "bea-fixed-assets-section-5",
    "bea-fixed-assets-section-7",
    "bls-cps-history-chunk-001",
    "bls-cps-history-chunk-002",
    "bls-cps-history-chunk-003",
)

function bea_profile_binding(profile_id)
    for binding in BEA_PROFILE_BINDINGS
        binding.profile_id == profile_id && return binding
    end
    return nothing
end

function bls_profile_binding(profile_id)
    for binding in BLS_PROFILE_BINDINGS
        binding.profile_id == profile_id && return binding
    end
    return nothing
end

struct AuthenticatedEvidenceV4Error <: Exception
    code::String
    detail::String
end

function Base.showerror(io::IO, error::AuthenticatedEvidenceV4Error)
    return print(io, error.code, ": ", error.detail)
end

fail(code, detail) = throw(AuthenticatedEvidenceV4Error(code, detail))

function require_dict(value, name)
    value isa AbstractDict || fail("invalid_type", "$name must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail("invalid_type", "$name keys must be strings")
    return value
end

function require_vector(value, name)
    value isa AbstractVector || fail("invalid_type", "$name must be an array")
    return value
end

function require_string(value, name)
    value isa AbstractString || fail("invalid_type", "$name must be a string")
    return String(value)
end

function require_bool(value, name)
    value isa Bool || fail("invalid_type", "$name must be a Boolean")
    return value
end

function require_int(value, name)
    typeof(value) === Int || fail("invalid_type", "$name must be a machine Int")
    return value
end

function require_exact_keys(table, expected, name)
    actual = Set(String.(keys(table)))
    wanted = Set(expected)
    actual == wanted || fail(
        "unexpected_keys",
        "$name keys differ; missing=$(sort!(collect(setdiff(wanted, actual)))) " *
            "extra=$(sort!(collect(setdiff(actual, wanted))))",
    )
    return nothing
end

function require_literal(table, key, expected, name)
    haskey(table, key) || fail("missing_field", "$name.$key is required")
    value = table[key]
    typeof(value) === typeof(expected) ||
        fail("invalid_type", "$name.$key has the wrong concrete type")
    value == expected || fail("invalid_literal", "$name.$key must equal $expected")
    return value
end

function require_identifier(value, name)
    text = require_string(value, name)
    occursin(Regex(IDENTIFIER_PATTERN), text) ||
        fail("invalid_identifier", "$name is not closed-form")
    return text
end

function require_sha256(value, name)
    text = require_string(value, name)
    occursin(Regex(HEX64_PATTERN), text) ||
        fail("invalid_sha256", "$name is not lowercase SHA-256")
    return text
end

function require_relative_path(value, name)
    text = require_string(value, name)
    occursin(Regex(RELATIVE_PATH_PATTERN), text) ||
        fail("invalid_relative_path", "$name is invalid")
    startswith(text, "/") && fail("invalid_relative_path", "$name is absolute")
    occursin('\\', text) && fail("invalid_relative_path", "$name contains backslash")
    parts = split(text, '/')
    any(part -> part in ("", ".", ".."), parts) &&
        fail("invalid_relative_path", "$name contains an unsafe component")
    return text
end

function require_https_uri(value, name)
    text = require_string(value, name)
    ncodeunits(text) <= 2_048 || fail("uri_length_limit", "$name is too long")
    occursin(Regex(HTTPS_URI_PATTERN), text) ||
        fail("invalid_https_uri", "$name is not a closed HTTPS URI")
    occursin('@', text) && fail("invalid_https_uri", "$name contains user information")
    return text
end

function write_u64!(io, value::Integer)
    value >= 0 || fail("canonical_integer_range", "negative length")
    value <= typemax(UInt64) || fail("canonical_integer_range", "length overflow")
    number = UInt64(value)
    for shift in 56:-8:0
        write(io, UInt8((number >> shift) & 0xff))
    end
    return nothing
end

function encoded_node(tag::UInt8, payload::Vector{UInt8})
    io = IOBuffer()
    write(io, tag)
    write_u64!(io, length(payload))
    write(io, payload)
    return take!(io)
end

function encode_value(value, depth, item_counter)
    depth <= MAX_CANONICAL_DEPTH || fail("canonical_depth_limit", "nesting is too deep")
    item_counter[] += 1
    item_counter[] <= MAX_CANONICAL_ITEMS ||
        fail("canonical_item_limit", "canonical subject has too many values")

    if value === nothing
        return encoded_node(UInt8('N'), UInt8[])
    elseif value isa Bool
        return encoded_node(UInt8('B'), UInt8[value ? 0x01 : 0x00])
    elseif typeof(value) === Int
        payload = UInt8[]
        number = reinterpret(UInt64, Int64(value))
        for shift in 56:-8:0
            push!(payload, UInt8((number >> shift) & 0xff))
        end
        return encoded_node(UInt8('I'), payload)
    elseif value isa AbstractString
        payload = Vector{UInt8}(codeunits(String(value)))
        length(payload) <= MAX_CANONICAL_STRING_BYTES ||
            fail("canonical_string_limit", "canonical string is too large")
        return encoded_node(UInt8('S'), payload)
    elseif value isa AbstractVector
        payload = IOBuffer()
        write_u64!(payload, length(value))
        for element in value
            write(payload, encode_value(element, depth + 1, item_counter))
        end
        return encoded_node(UInt8('L'), take!(payload))
    elseif value isa AbstractDict
        all(key -> key isa AbstractString, keys(value)) ||
            fail("canonical_key_type", "canonical map keys must be strings")
        ordered_keys = sort!(String.(collect(keys(value))))
        length(unique(ordered_keys)) == length(ordered_keys) ||
            fail("canonical_duplicate_key", "canonical map keys collide as strings")
        payload = IOBuffer()
        write_u64!(payload, length(ordered_keys))
        for key in ordered_keys
            write(payload, encode_value(key, depth + 1, item_counter))
            write(payload, encode_value(value[key], depth + 1, item_counter))
        end
        return encoded_node(UInt8('M'), take!(payload))
    end
    return fail("canonical_unsupported_type", "unsupported canonical value $(typeof(value))")
end

function canonical_subject_bytes(kind, value)
    kind_text = require_identifier(kind, "subject kind")
    io = IOBuffer()
    domain_bytes = Vector{UInt8}(codeunits(SUBJECT_DOMAIN))
    write(io, domain_bytes)
    write(io, encoded_node(UInt8('K'), Vector{UInt8}(codeunits(kind_text))))
    write(io, encode_value(value, 0, Ref(0)))
    return take!(io)
end

canonical_subject_sha256(kind, value) =
    bytes2hex(SHA.sha256(canonical_subject_bytes(kind, value)))

function load_policy(path = POLICY_PATH)
    abspath(path) == abspath(POLICY_PATH) ||
        fail("policy_path_not_exact", "only the adjacent v4 policy may be loaded")
    isfile(path) || fail("policy_missing", "v4 policy is missing")
    return TOML.parsefile(path)
end

function declared_successor_crypto_runtime()
    return Dict{String, Any}(
        "dependency" => "OpenSSL_jll",
        "declared_version" => "3.5.7+0",
        "package_tree_sha1" => "d8cce34295c55f47be683580f44791716045b8fe",
        "artifact_tree_sha1" => "5ffc993d703fa0051405cb562c49d46328b8d5f3",
        "target" => "aarch64-apple-darwin",
        "product_sha256" => Dict(
            "openssl" => "00292fe08c00550afd97d692c47a2a4a41ee56b136f52f3f63124df97db928c4",
            "libcrypto" => "b40cc0d4fd13fc9a32849fedf18d2fde97694efb5ac19573bd1ba5c40d941644",
            "libssl" => "b8ecb15e077227cf89a5a077335395c9db4bbea978253b7f6d96329f634f30fc",
        ),
        "pins_authenticated" => false,
        "runtime_loaded" => false,
        "products_opened" => false,
        "products_validated" => false,
        "subprocess_executed" => false,
        "cryptographic_validation_executed" => false,
        "fips_conformance_claimed" => false,
    )
end

function checked_byte_total(values; maximum = MAX_CATALOG_BYTES)
    typeof(maximum) === Int || fail("invalid_type", "byte-total maximum must be an Int")
    maximum >= 0 || fail("invalid_byte_count", "byte-total maximum must be nonnegative")
    total = 0
    for (index, value) in enumerate(values)
        require_int(value, "byte total value[$index]")
        value >= 0 || fail("invalid_byte_count", "byte total value[$index] is negative")
        total = try
            Base.Checked.checked_add(total, value)
        catch error
            error isa OverflowError || rethrow()
            fail("byte_count_overflow", "byte total overflows Int")
        end
        total <= maximum || fail("catalog_byte_limit", "byte total exceeds $maximum")
    end
    return total
end

function raw_object_subject_sha256(raw_object)
    projection = Dict{String, Any}(
        "object_id" => raw_object["object_id"],
        "artifact_role" => raw_object["artifact_role"],
        "provider_object_subject_sha256" => raw_object["provider_object_subject_sha256"],
        "relative_path" => raw_object["relative_path"],
        "sha256" => raw_object["sha256"],
        "byte_count" => raw_object["byte_count"],
    )
    return canonical_subject_sha256("raw-catalog-object", projection)
end

function provider_request_subject_sha256(raw_object)
    projection = Dict{String, Any}(
        "source_id" => raw_object["source_id"],
        "request_method" => raw_object["request_method"],
        "requested_uri" => raw_object["requested_uri"],
        "final_effective_uri" => raw_object["final_effective_uri"],
        "redirect_policy" => raw_object["redirect_policy"],
        "request_payload_sha256" => raw_object["request_payload_sha256"],
        "request_ordinal" => raw_object["request_ordinal"],
    )
    return canonical_subject_sha256("provider-request", projection)
end

function provider_object_subject_sha256(raw_object)
    projection = Dict{String, Any}(
        "provider_request_subject_sha256" => provider_request_subject_sha256(raw_object),
        "provider_object_version" => raw_object["provider_object_version"],
        "response_media_type" => raw_object["media_type"],
        "response_sha256" => raw_object["sha256"],
        "response_byte_count" => raw_object["byte_count"],
    )
    return canonical_subject_sha256("provider-object", projection)
end

function validate_replica(replica, object_name, replica_index, object_subject)
    name = "$object_name.replicas[$replica_index]"
    table = require_dict(replica, name)
    require_exact_keys(
        table,
        [
            "replica_id",
            "relative_path",
            "sha256",
            "byte_count",
            "storage_domain_id",
            "storage_backend_id",
            "storage_object_version",
            "custody_operator_key_id",
            "custody_attestation_id",
            "catalog_object_subject_sha256",
        ],
        name,
    )
    require_identifier(table["replica_id"], "$name.replica_id")
    require_relative_path(table["relative_path"], "$name.relative_path")
    require_sha256(table["sha256"], "$name.sha256")
    require_int(table["byte_count"], "$name.byte_count") > 0 ||
        fail("invalid_byte_count", "$name.byte_count must be positive")
    require_identifier(table["storage_domain_id"], "$name.storage_domain_id")
    require_identifier(table["storage_backend_id"], "$name.storage_backend_id")
    require_identifier(table["storage_object_version"], "$name.storage_object_version")
    require_identifier(table["custody_operator_key_id"], "$name.custody_operator_key_id")
    require_identifier(table["custody_attestation_id"], "$name.custody_attestation_id")
    require_sha256(
        table["catalog_object_subject_sha256"],
        "$name.catalog_object_subject_sha256",
    )
    table["catalog_object_subject_sha256"] == object_subject ||
        fail("replica_object_binding_mismatch", "$name does not bind the catalog object")
    return table
end

function validate_catalog_object(raw_object, object_index)
    name = "raw_object_catalog.objects[$object_index]"
    table = require_dict(raw_object, name)
    require_exact_keys(
        table,
        [
            "object_id",
            "source_id",
            "artifact_role",
            "media_type",
            "request_method",
            "requested_uri",
            "final_effective_uri",
            "redirect_policy",
            "request_payload_sha256",
            "request_ordinal",
            "provider_object_version",
            "provider_object_subject_sha256",
            "relative_path",
            "sha256",
            "byte_count",
            "replicas",
        ],
        name,
    )
    require_identifier(table["object_id"], "$name.object_id")
    require_identifier(table["source_id"], "$name.source_id")
    require_identifier(table["artifact_role"], "$name.artifact_role")
    media_type = require_string(table["media_type"], "$name.media_type")
    media_type in ALLOWED_MEDIA_TYPES ||
        fail("invalid_media_type", "$name.media_type is not allowed")
    request_method = require_string(table["request_method"], "$name.request_method")
    request_method in ("GET", "POST") ||
        fail("invalid_request_method", "$name.request_method is not allowed")
    requested_uri = require_https_uri(table["requested_uri"], "$name.requested_uri")
    final_effective_uri = require_https_uri(
        table["final_effective_uri"],
        "$name.final_effective_uri",
    )
    require_literal(table, "redirect_policy", NO_REDIRECT_POLICY, name)
    requested_uri == final_effective_uri ||
        fail("redirect_uri_mismatch", "$name final URI differs under the no-redirect policy")
    request_payload_sha256 =
        require_sha256(table["request_payload_sha256"], "$name.request_payload_sha256")
    request_method == "GET" && request_payload_sha256 != EMPTY_SHA256 &&
        fail("get_payload_not_empty", "$name GET payload hash must bind empty bytes")
    request_ordinal = require_int(table["request_ordinal"], "$name.request_ordinal")
    1 <= request_ordinal <= 10_000 ||
        fail("invalid_request_ordinal", "$name.request_ordinal is outside 1:10000")
    require_identifier(table["provider_object_version"], "$name.provider_object_version")
    declared_provider_subject = require_sha256(
        table["provider_object_subject_sha256"],
        "$name.provider_object_subject_sha256",
    )
    require_relative_path(table["relative_path"], "$name.relative_path")
    raw_hash = require_sha256(table["sha256"], "$name.sha256")
    byte_count = require_int(table["byte_count"], "$name.byte_count")
    byte_count > 0 || fail("invalid_byte_count", "$name.byte_count must be positive")
    byte_count <= MAX_RAW_OBJECT_BYTES ||
        fail("object_byte_limit", "$name.byte_count exceeds $MAX_RAW_OBJECT_BYTES")
    derived_provider_subject = provider_object_subject_sha256(table)
    declared_provider_subject == derived_provider_subject ||
        fail("provider_object_subject_mismatch", "$name provider object subject is stale")
    object_subject = raw_object_subject_sha256(table)
    replicas = require_vector(table["replicas"], "$name.replicas")
    length(replicas) == 2 || fail("replica_count", "$name must declare exactly two replicas")
    for (index, replica) in enumerate(replicas)
        validated = validate_replica(replica, name, index, object_subject)
        validated["sha256"] == raw_hash ||
            fail("replica_hash_mismatch", "$name replica does not bind the raw hash")
        validated["byte_count"] == byte_count ||
            fail("replica_size_mismatch", "$name replica does not bind the raw size")
    end
    for field in (
            "replica_id",
            "relative_path",
            "storage_domain_id",
            "storage_backend_id",
            "storage_object_version",
            "custody_operator_key_id",
            "custody_attestation_id",
        )
        replicas[1][field] != replicas[2][field] ||
            fail("replica_independence", "$name replicas share $field")
    end
    return table
end

function register_unique!(seen, value, label)
    haskey(seen, value) && fail(
        "global_identity_collision",
        "$label $value already belongs to $(seen[value])",
    )
    seen[value] = label
    return nothing
end

function validate_raw_object_catalog(catalog)
    table = require_dict(catalog, "raw_object_catalog")
    require_exact_keys(
        table,
        ["schema_version", "evidence_class", "catalog_id", "objects"],
        "raw_object_catalog",
    )
    require_literal(
        table,
        "schema_version",
        "beforeit-us-raw-object-catalog.v1",
        "raw_object_catalog",
    )
    require_literal(table, "evidence_class", "SYNTHETIC_INERT", "raw_object_catalog")
    require_identifier(table["catalog_id"], "raw_object_catalog.catalog_id")
    objects = require_vector(table["objects"], "raw_object_catalog.objects")
    length(objects) == length(REQUIRED_CATALOG_OBJECTS) ||
        fail("catalog_object_count", "demonstration catalog must contain six objects")

    global_seen = Dict{String, String}()
    object_ids = String[]
    for (index, raw_object) in enumerate(objects)
        validated = validate_catalog_object(raw_object, index)
        object_id = String(validated["object_id"])
        push!(object_ids, object_id)
        for field in ("object_id", "relative_path")
            register_unique!(global_seen, String(validated[field]), "raw.$field")
        end
        register_unique!(
            global_seen,
            provider_request_subject_sha256(validated),
            "provider.request_subject",
        )
        register_unique!(
            global_seen,
            provider_object_subject_sha256(validated),
            "provider.object_subject",
        )
        for replica in validated["replicas"]
            for field in (
                    "replica_id",
                    "relative_path",
                    "storage_object_version",
                    "custody_attestation_id",
                )
                register_unique!(global_seen, String(replica[field]), "replica.$field")
            end
        end
    end
    object_ids == sort(object_ids) ||
        fail("catalog_order", "raw objects must be sorted by object_id")
    Tuple(object_ids) == REQUIRED_CATALOG_OBJECTS ||
        fail("catalog_membership", "demonstration catalog has the wrong object IDs")
    bea_objects = filter(object -> startswith(object["object_id"], "bea-"), objects)
    all(object -> object["source_id"] == "bea.fixed.assets", bea_objects) ||
        fail("source_geometry", "BEA objects have the wrong source")
    all(object -> object["request_method"] == "GET", bea_objects) ||
        fail("source_geometry", "BEA objects must use GET")
    all(
        object -> object["media_type"] ==
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        bea_objects,
    ) || fail("source_geometry", "BEA objects must be XLSX workbooks")
    bls_objects = filter(object -> startswith(object["object_id"], "bls-"), objects)
    all(object -> object["source_id"] == "bls.cps", bls_objects) ||
        fail("source_geometry", "BLS objects have the wrong source")
    all(object -> object["request_method"] == "POST", bls_objects) ||
        fail("source_geometry", "BLS objects must use POST")
    all(object -> object["media_type"] == "application/json", bls_objects) ||
        fail("source_geometry", "BLS API objects must be JSON")
    length(unique(object["requested_uri"] for object in bls_objects)) == 1 ||
        fail("source_geometry", "BLS chunks must share one requested URI")
    length(unique(object["final_effective_uri"] for object in bls_objects)) == 1 ||
        fail("source_geometry", "BLS chunks must share one final URI")
    [object["request_ordinal"] for object in bls_objects] == [1, 2, 3] ||
        fail("source_geometry", "BLS request ordinals must be 1,2,3")
    length(unique(object["request_payload_sha256"] for object in bls_objects)) == 3 ||
        fail("source_geometry", "BLS chunk request bodies must be distinct")
    checked_byte_total(object["byte_count"] for object in objects)
    return Dict(object_id => objects[index] for (index, object_id) in enumerate(object_ids))
end

function expected_profile_projection(profile_id)
    bea_binding = bea_profile_binding(profile_id)
    if bea_binding !== nothing
        section = last(split(bea_binding.object_id, '-'))
        table_id = bea_binding.table_id
        return Dict{String, Any}(
            "schema_version" => "beforeit-us-profile-projection-descriptor.v1",
            "source_id" => "bea.fixed.assets",
            "projection_kind" => "BEA_FIXED_ASSETS_TABLE",
            "container_id" => "BEA_FIXED_ASSETS_SECTION_$(section)_WORKBOOK",
            "sheet_or_series_id" => table_id,
            "table_or_formula_id" => table_id,
            "line_selector" => "SYNTHETIC_UNRESOLVED_PRODUCTION_LINE_SELECTOR",
            "coverage_selector" => "SYNTHETIC_UNRESOLVED_PRODUCTION_YEAR_RANGE",
            "unit_selector" => "SYNTHETIC_UNRESOLVED_PRODUCTION_UNIT",
            "frequency" => "ANNUAL",
            "interpretation" => bea_binding.interpretation,
            "production_binding_state" => "ABSENT_SYNTHETIC_SENTINEL",
        )
    end
    bls_binding = bls_profile_binding(profile_id)
    if bls_binding !== nothing
        return Dict{String, Any}(
            "schema_version" => "beforeit-us-profile-projection-descriptor.v1",
            "source_id" => "bls.cps",
            "projection_kind" => "BLS_CPS_SERIES_OR_FORMULA",
            "container_id" => "BLS_CPS_ORDERED_HISTORY_CHUNKS",
            "sheet_or_series_id" => "SYNTHETIC_UNRESOLVED_SERIES_$profile_id",
            "table_or_formula_id" =>
                "SYNTHETIC_UNRESOLVED_PRODUCTION_DIRECT_OR_DERIVED_FORMULA",
            "line_selector" => "NOT_APPLICABLE",
            "coverage_selector" =>
                "SYNTHETIC_UNRESOLVED_PRODUCTION_MONTH_RANGE_AND_NO_GAP_RULE",
            "unit_selector" => "SYNTHETIC_UNRESOLVED_PRODUCTION_UNIT",
            "frequency" => "MONTHLY",
            "interpretation" => bls_binding.interpretation,
            "production_binding_state" => "ABSENT_SYNTHETIC_SENTINEL",
        )
    end
    return fail("unknown_profile", "$profile_id is outside the demonstration")
end

function profile_projection_subject_sha256(profile_id, ordered_object_ids, projection)
    subject = Dict{String, Any}(
        "profile_id" => profile_id,
        "ordered_object_ids" => ordered_object_ids,
        "projection" => projection,
    )
    return canonical_subject_sha256("profile-object-projection", subject)
end

function validate_profile_projection(projection, profile_id, ordered_object_ids, name)
    table = require_dict(projection, "$name.projection")
    expected = expected_profile_projection(profile_id)
    require_exact_keys(table, collect(keys(expected)), "$name.projection")
    for field in keys(expected)
        require_literal(table, field, expected[field], "$name.projection")
    end
    return profile_projection_subject_sha256(profile_id, ordered_object_ids, table)
end

function validate_profile_selections(selections, catalog)
    object_index = validate_raw_object_catalog(catalog)
    rows = require_vector(selections, "profile_selections")
    length(rows) == length(REQUIRED_DEMONSTRATION_PROFILES) ||
        fail("profile_selection_count", "demonstration must contain 14 selections")
    observed_profiles = String[]
    reference_count = Dict(object_id => 0 for object_id in keys(object_index))
    for (index, row) in enumerate(rows)
        name = "profile_selections[$index]"
        table = require_dict(row, name)
        require_exact_keys(
            table,
            [
                "schema_version",
                "profile_id",
                "ordered_object_ids",
                "projection",
                "projection_subject_sha256",
            ],
            name,
        )
        require_literal(
            table,
            "schema_version",
            "beforeit-us-profile-object-set-selection.v2",
            name,
        )
        profile_id = require_identifier(table["profile_id"], "$name.profile_id")
        push!(observed_profiles, profile_id)
        selected = require_vector(table["ordered_object_ids"], "$name.ordered_object_ids")
        all(value -> value isa AbstractString, selected) ||
            fail("invalid_type", "$name.ordered_object_ids must contain strings")
        selected_ids = String.(selected)
        isempty(selected_ids) && fail("empty_selection", "$name selects no objects")
        length(unique(selected_ids)) == length(selected_ids) ||
            fail("duplicate_within_selection", "$name repeats an object")
        all(haskey(object_index, object_id) for object_id in selected_ids) ||
            fail("unknown_catalog_object", "$name references an unknown object")
        bea_binding = bea_profile_binding(profile_id)
        expected = if bea_binding !== nothing
            [bea_binding.object_id]
        elseif bls_profile_binding(profile_id) !== nothing
            collect(BLS_OBJECT_SET)
        else
            fail("unknown_profile", "$name profile is outside the demonstration")
        end
        selected_ids == expected ||
            fail("selection_semantics", "$profile_id has the wrong ordered object set")
        projection_subject = validate_profile_projection(
            table["projection"],
            profile_id,
            selected_ids,
            name,
        )
        declared_projection_subject = require_sha256(
            table["projection_subject_sha256"],
            "$name.projection_subject_sha256",
        )
        declared_projection_subject == projection_subject ||
            fail("projection_subject_mismatch", "$name projection subject is stale")
        for object_id in selected_ids
            reference_count[object_id] += 1
        end
    end
    observed_profiles == sort(observed_profiles) ||
        fail("profile_selection_order", "profile selections must be sorted by profile_id")
    Tuple(observed_profiles) == REQUIRED_DEMONSTRATION_PROFILES ||
        fail("profile_selection_membership", "demonstration profiles differ")
    expected_counts = Dict(
        "bea-fixed-assets-section-3" => 3,
        "bea-fixed-assets-section-5" => 3,
        "bea-fixed-assets-section-7" => 2,
        "bls-cps-history-chunk-001" => 6,
        "bls-cps-history-chunk-002" => 6,
        "bls-cps-history-chunk-003" => 6,
    )
    reference_count == expected_counts ||
        fail("shared_object_geometry", "selection reference geometry is not 3/3/2 plus 6x3")
    return reference_count
end

function validate_absent_trust(parent)
    bootstrap = require_dict(parent["trust_bootstrap"], "trust_bootstrap")
    require_exact_keys(
        bootstrap,
        ["schema_version", "state", "out_of_evidence_anchor_ids"],
        "trust_bootstrap",
    )
    require_literal(
        bootstrap,
        "schema_version",
        "beforeit-us-trust-bootstrap-reference.v1",
        "trust_bootstrap",
    )
    require_literal(bootstrap, "state", "ABSENT_NOT_PROVISIONED", "trust_bootstrap")
    isempty(
        require_vector(
            bootstrap["out_of_evidence_anchor_ids"],
            "trust_bootstrap.out_of_evidence_anchor_ids",
        )
    ) || fail("trust_material_forbidden", "synthetic candidate cannot contain anchors")

    registry = require_dict(parent["key_registry"], "key_registry")
    require_exact_keys(
        registry,
        ["schema_version", "state", "role_keys", "revocations", "rotations"],
        "key_registry",
    )
    require_literal(
        registry,
        "schema_version",
        "beforeit-us-trust-key-registry.v1",
        "key_registry",
    )
    require_literal(registry, "state", "ABSENT_NOT_PROVISIONED", "key_registry")
    for field in ("role_keys", "revocations", "rotations")
        isempty(require_vector(registry[field], "key_registry.$field")) ||
            fail("trust_material_forbidden", "synthetic candidate cannot contain $field")
    end

    timestamp = require_dict(parent["rfc3161_evidence"], "rfc3161_evidence")
    require_exact_keys(
        timestamp,
        ["schema_version", "state", "requests", "responses"],
        "rfc3161_evidence",
    )
    require_literal(
        timestamp,
        "schema_version",
        "beforeit-us-rfc3161-evidence.v1",
        "rfc3161_evidence",
    )
    require_literal(timestamp, "state", "ABSENT_NOT_REQUESTED", "rfc3161_evidence")
    isempty(require_vector(timestamp["requests"], "rfc3161_evidence.requests")) ||
        fail("timestamp_material_forbidden", "timestamp requests are forbidden")
    isempty(require_vector(timestamp["responses"], "rfc3161_evidence.responses")) ||
        fail("timestamp_material_forbidden", "timestamp responses are forbidden")

    custody = require_dict(parent["custody_manifest"], "custody_manifest")
    require_exact_keys(
        custody,
        [
            "schema_version",
            "state",
            "external_domain_attestations",
            "owner_decisions",
            "validator_decisions",
        ],
        "custody_manifest",
    )
    require_literal(
        custody,
        "schema_version",
        "beforeit-us-custody-operator-manifest.v1",
        "custody_manifest",
    )
    require_literal(custody, "state", "SYNTHETIC_DECLARATIONS_ONLY", "custody_manifest")
    for field in (
            "external_domain_attestations",
            "owner_decisions",
            "validator_decisions",
        )
        isempty(require_vector(custody[field], "custody_manifest.$field")) ||
            fail("authenticated_decision_forbidden", "synthetic candidate cannot contain $field")
    end

    release = require_dict(parent["verifier_release_manifest"], "verifier_release_manifest")
    require_exact_keys(
        release,
        [
            "schema_version",
            "state",
            "source_sha256",
            "project_sha256",
            "manifest_sha256",
            "owner_signature_ids",
            "validator_signature_ids",
            "timestamp_evidence_ids",
        ],
        "verifier_release_manifest",
    )
    require_literal(
        release,
        "schema_version",
        "beforeit-us-verifier-release-manifest.v1",
        "verifier_release_manifest",
    )
    require_literal(release, "state", "UNAUTHENTICATED_SYNTHETIC_PIN", "verifier_release_manifest")
    policy = load_policy()
    implementation = policy["implementation"]
    for (field, policy_field) in (
            ("source_sha256", "module_sha256"),
            ("project_sha256", "project_sha256"),
            ("manifest_sha256", "manifest_sha256"),
        )
        require_sha256(release[field], "verifier_release_manifest.$field")
        require_literal(
            release,
            field,
            implementation[policy_field],
            "verifier_release_manifest",
        )
    end
    for field in (
            "owner_signature_ids",
            "validator_signature_ids",
            "timestamp_evidence_ids",
        )
        isempty(require_vector(release[field], "verifier_release_manifest.$field")) ||
            fail("release_authentication_forbidden", "synthetic release cannot contain $field")
    end
    return nothing
end

function validate_parent(parent)
    table = require_dict(parent, "parent")
    require_exact_keys(
        table,
        [
            "schema_version",
            "evidence_class",
            "candidate_status",
            "maximum_status",
            "claim_ceiling",
            "raw_object_catalog",
            "profile_selections",
            "trust_bootstrap",
            "key_registry",
            "rfc3161_evidence",
            "custody_manifest",
            "verifier_release_manifest",
            "gates",
        ],
        "parent",
    )
    require_literal(
        table,
        "schema_version",
        "beforeit-us-common-origin-parent.v4",
        "parent",
    )
    require_literal(table, "evidence_class", "SYNTHETIC_INERT", "parent")
    require_literal(table, "candidate_status", CANNOT_RUN, "parent")
    require_literal(table, "maximum_status", CANNOT_RUN, "parent")
    require_literal(
        table,
        "claim_ceiling",
        "SYNTHETIC_SCHEMA_AND_FAIL_CLOSED_LOGIC_ONLY_NO_AUTHENTICATED_ORIGIN",
        "parent",
    )
    validate_profile_selections(table["profile_selections"], table["raw_object_catalog"])
    validate_absent_trust(table)
    gates = require_dict(table["gates"], "gates")
    required_gates = [
        "network_allowed",
        "raw_access_allowed",
        "signing_allowed",
        "timestamp_submission_allowed",
        "origin_admission_allowed",
        "model_access_allowed",
        "truth_access_allowed",
        "scoring_allowed",
        "inventory_mutation_allowed",
        "worklog_mutation_allowed",
    ]
    require_exact_keys(gates, required_gates, "gates")
    for gate in required_gates
        require_bool(gates[gate], "gates.$gate") == false ||
            fail("gate_must_be_false", "gates.$gate must remain false")
    end
    return true
end

function parent_subject(parent)
    return canonical_subject_sha256("common-origin-parent", parent)
end

function verify_parent(parent)
    validate_parent(parent)
    reference_count = validate_profile_selections(
        parent["profile_selections"],
        parent["raw_object_catalog"],
    )
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-independent-validation-result.v2",
        "status" => CANNOT_RUN,
        "maximum_status" => CANNOT_RUN,
        "claim_ceiling" => parent["claim_ceiling"],
        "parent_subject_sha256" => parent_subject(parent),
        "blockers" => collect(EXPECTED_BLOCKERS),
        "object_count" => length(parent["raw_object_catalog"]["objects"]),
        "profile_count" => length(parent["profile_selections"]),
        "selection_reference_count" => sum(values(reference_count)),
        "unique_object_byte_count" => checked_byte_total(
            object["byte_count"] for object in parent["raw_object_catalog"]["objects"]
        ),
        "authenticated_signature_count" => 0,
        "rfc3161_response_count" => 0,
        "external_custody_attestation_count" => 0,
        "network_action_count" => 0,
        "raw_read_action_count" => 0,
        "signing_action_count" => 0,
        "timestamp_submission_action_count" => 0,
        "model_action_count" => 0,
        "truth_action_count" => 0,
        "scoring_action_count" => 0,
        "inventory_mutation_count" => 0,
        "worklog_mutation_count" => 0,
        "openssl_subprocess_count" => 0,
        "fips_conformance_claimed" => false,
    )
end

function strict_equal(left, right)
    typeof(left) === typeof(right) || return false
    if left isa AbstractDict
        Set(keys(left)) == Set(keys(right)) || return false
        return all(strict_equal(left[key], right[key]) for key in keys(left))
    elseif left isa AbstractVector
        length(left) == length(right) || return false
        return all(strict_equal(left[index], right[index]) for index in eachindex(left))
    end
    return isequal(left, right)
end

function validate_result(parent, result)
    expected = verify_parent(parent)
    strict_equal(expected, result) ||
        fail("result_replay_mismatch", "result differs from a complete parent replay")
    return true
end

end
