module BEAWorkbookReceipts

using Base64
using Dates
using JSON
using SHA
using TOML

include(
    joinpath(
        @__DIR__,
        "..",
        "mapping_audit",
        "BEANIPAMappingAudit.jl",
    ),
)
using .BEANIPAMappingAudit

export WorkbookFetch,
    ReceiptValidationError,
    build_receipt,
    computed_content_sha256,
    file_sha256,
    stamp_content_sha256!,
    validate_receipt,
    validate_receipt_file,
    validate_receipt_set,
    validate_target_profile,
    verify_local_raw_files

const RECEIPT_SCHEMA = "beforeit-us-bea-nipa-workbook-receipt.v1"
const PROFILE_SCHEMA = "beforeit-us-bea-nipa-workbook-target-profile.v1"
const CONTENT_FINGERPRINT_SCHEMA =
    "beforeit-us-bea-nipa-content-fingerprint.v2"
const CONTENT_FINGERPRINT_PARSER_VERSION =
    "beforeit-us-bea-nipa-ooxml-parser.v2"
const CONTENT_FINGERPRINT_PARSER_SHA256 =
    "7f054199aa7077a2ee3a68c001279a3795c9d4305031588253441ddb90cda55e"
const CONTENT_FINGERPRINT_CANONICALIZATION =
    "utf8_sorted_keys_compact_json_lf"
const CONTENT_FINGERPRINT_SEMANTIC_IDENTITY_SCOPE =
    "RAW_WORKBOOK_BYTES_RELEASE_MAPPING_PARSED_VALUES_AND_PARSER_BYTES"
const CONTENT_FINGERPRINT_PRODUCTION_STATUS =
    "PRESENT_DAY_ARCHIVE_BYTES_PARSED_NONADMITTING"
const CONTENT_FINGERPRINT_SYNTHETIC_STATUS =
    "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE"
const CONTENT_FINGERPRINT_PRODUCTION_EVIDENCE_CLASS =
    "present_day_archive_content_observation"
const CONTENT_FINGERPRINT_SYNTHETIC_EVIDENCE_CLASS =
    "synthetic_contract_fixture"
const CANONICALIZATION =
    "sorted_typed_v1_excluding_artifact_content_sha256"
const PRODUCTION_SCOPE = "PRESENT_DAY_ACQUISITION_OBSERVATION"
const SYNTHETIC_SCOPE = "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE"
const PRODUCTION_STATE =
    "PRESENT_DAY_BYTES_OBSERVED_NOT_HISTORICAL_AVAILABILITY"
const SYNTHETIC_STATE = "SYNTHETIC_CONTRACT_FIXTURE"
const PROFILE_PRODUCTION_SCOPE = "EXACT_INSPECTED_WORKBOOK_TARGET_PROFILE"
const PROFILE_SYNTHETIC_SCOPE =
    "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const HTTP_DATE_PATTERN =
    r"^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
const OFFICIAL_URL_PATTERN =
    r"^https://apps\.bea\.gov/HistData/Files/Releases/GDP_and_PI/(\d{4})/(Q[1-4])/([^/?#]+)/([^/?#]+)$"
const WORKBOOK_FILENAME_PATTERN =
    r"(?i)^Section([0-9]+|S)all_xls\.(xls|xlsx)$"
const XLS_MEDIA_TYPE = "application/vnd.ms-excel"
const XLSX_MEDIA_TYPE =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
const OLE_SIGNATURE =
    UInt8[0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]
const ZIP_LOCAL_SIGNATURE = UInt8[0x50, 0x4b, 0x03, 0x04]
const ZIP_END_SIGNATURE = UInt8[0x50, 0x4b, 0x05, 0x06]

const RECEIPT_ROOT_KEYS = Set(["artifact", "capture", "semantic_linkage", "workbooks"])
const RECEIPT_ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "receipt_id",
        "scope",
        "state",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
        "immutable_receipt",
        "present_day_acquisition_observed",
        "historical_release_availability_verified",
        "release_event_timestamp_verified",
        "first_state_verified",
        "origin_admissible",
        "inventory_registered",
        "ready",
    ],
)
const CAPTURE_KEYS = Set(
    [
        "transaction_id",
        "observer_id",
        "capture_agent",
        "capture_agent_version",
        "pair_started_at_utc",
        "pair_completed_at_utc",
        "max_pair_span_seconds",
        "observed_pair_span_seconds",
        "atomicity_policy",
        "atomic_pair_complete",
        "acquisition_clock_basis",
    ],
)
const SEMANTIC_LINKAGE_KEYS = Set(
    [
        "profile_artifact_path",
        "profile_file_sha256",
        "profile_content_sha256",
        "source_mapping_audit_file_sha256",
        "profile_id",
        "content_fingerprint_artifact_path",
        "content_fingerprint_file_sha256",
        "content_fingerprint_schema_version",
        "content_fingerprint_parser_sha256",
        "linked_target_ids",
        "linkage_basis",
        "linkage_status",
        "historical_availability_inferred",
        "origin_admission_inferred",
    ],
)
const WORKBOOK_KEYS = Set(
    [
        "release_id",
        "workbook_id",
        "reference_period",
        "estimate_label",
        "archive_label_url_component",
        "archive_directory_id",
        "hmi_id",
        "publication_variant",
        "section_id",
        "filename",
        "file_format",
        "identity_status",
        "raw_artifact_path",
        "storage_encoding",
        "raw_sha256",
        "raw_bytes",
        "container_signature",
        "acquisition_started_at_utc",
        "response_headers_at_utc",
        "acquisition_completed_at_utc",
        "retrieval_observation_scope",
        "method",
        "requested_url",
        "effective_url",
        "status_code",
        "redirect_count",
        "content_type",
        "content_length_header_status",
        "content_length_header",
        "etag_status",
        "etag",
        "last_modified_status",
        "last_modified",
        "content_disposition_status",
        "content_disposition",
    ],
)
const PROFILE_ROOT_KEYS = Set(["artifact", "profile", "workbooks", "targets"])
const PROFILE_ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "profile_artifact_id",
        "scope",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
        "source_mapping_audit_file_sha256",
        "historical_release_availability_verified",
        "origin_admissible",
        "ready",
    ],
)
const PROFILE_KEYS = Set(
    [
        "profile_id",
        "release_id",
        "reference_period",
        "workbook_count",
        "target_count",
        "mapping_assignment_basis",
    ],
)
const PROFILE_WORKBOOK_KEYS = Set(
    [
        "workbook_id",
        "section_id",
        "file_format",
        "official_url",
        "raw_sha256",
        "synthetic_bytes",
    ],
)
const PROFILE_TARGET_KEYS = Set(
    [
        "target_id",
        "section_id",
        "sheet_name",
        "table_number",
        "published_line_number",
        "physical_row_number",
        "series_code",
        "frequency",
        "seasonal_adjustment",
        "unit",
        "base_year",
        "mapping_fingerprint",
    ],
)
const CONTENT_FINGERPRINT_ROOT_KEYS =
    Set(["artifact", "targets", "workbooks"])
const CONTENT_FINGERPRINT_ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "parser_version",
        "status",
        "release_id",
        "reference_quarter",
        "estimate_label",
        "mapping_profile_id",
        "mapping_audit_sha256",
        "raw_bundle_sha256",
        "source_agency",
        "source_attribution",
        "parser_sha256",
        "canonicalization",
        "semantic_identity_scope",
        "execution_environment_included",
        "repository_state_included",
        "persistence_scope",
        "evidence_class",
        "release_event_evidence_included",
        "historical_availability_evidence_included",
        "historical_availability_verified",
        "inventory_mutated",
        "origin_admissible",
        "ready",
    ],
)
const CONTENT_FINGERPRINT_WORKBOOK_KEYS = Set(
    [
        "data_published_text",
        "file_format",
        "historical_availability_verified",
        "mapping_profile_id",
        "ooxml_zip_integrity_verified",
        "origin_admissible",
        "raw_byte_count",
        "raw_object_path",
        "raw_sha256",
        "ready",
        "release_id",
        "requested_locator",
        "section_id",
        "sheet_count",
        "workbook_id",
    ],
)
const CONTENT_FINGERPRINT_TARGET_KEYS = Set(
    [
        "available_value_count",
        "base_year",
        "decimal_places",
        "frequency",
        "historical_availability_verified",
        "missing_value_count",
        "normalized_concept",
        "number_format_code",
        "observations",
        "origin_admissible",
        "physical_row_number",
        "published_line_number",
        "published_values_sha256",
        "raw_sha256",
        "raw_values_sha256",
        "ready",
        "reference_period_count",
        "reference_period_end",
        "reference_period_start",
        "seasonal_adjustment",
        "section_id",
        "series_code",
        "sheet_name",
        "source_cells",
        "source_concept_text",
        "table_number",
        "table_title",
        "target_id",
        "unit",
        "workbook_id",
    ],
)
const CONTENT_FINGERPRINT_SOURCE_CELL_KEYS = Set(
    [
        "concept",
        "coverage",
        "line",
        "publication",
        "reference_period_range",
        "series",
        "table_title",
        "units",
        "value_range",
    ],
)
const CONTENT_FINGERPRINT_OBSERVATION_KEYS =
    Set(["period", "published_value_text", "raw_value_text"])

struct ReceiptValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::ReceiptValidationError) =
    print(io, error.message)

Base.@kwdef struct WorkbookFetch
    raw_bytes::Vector{UInt8}
    raw_artifact_path::String
    storage_encoding::String = "identity"
    release_id::String
    workbook_id::String
    reference_period::String
    estimate_label::String
    archive_label_url_component::String
    archive_directory_id::String
    section_id::String
    filename::String
    file_format::String
    requested_url::String
    effective_url::String
    status_code::Int = 200
    redirect_count::Int = 0
    content_type::String
    content_length_header::Union{Nothing, Int} = nothing
    etag::Union{Nothing, String} = nothing
    last_modified::Union{Nothing, String} = nothing
    content_disposition::Union{Nothing, String} = nothing
    acquisition_started_at_utc::DateTime
    response_headers_at_utc::DateTime
    acquisition_completed_at_utc::DateTime
end

fail(location, message) =
    throw(ReceiptValidationError("$location: $message"))

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    found = Set(String.(keys(table)))
    found == expected ||
        fail(
        location,
        "keys differ; missing=$(sort!(collect(setdiff(expected, found)))) " *
            "extra=$(sort!(collect(setdiff(found, expected))))",
    )
    return table
end

function expect_array(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    return value
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
    return text
end

function expect_nonempty_text(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    isempty(text) && fail(location, "must not be empty")
    return text
end

function expect_identifier(value, location)
    text = expect_string(value, location)
    occursin(IDENTIFIER_PATTERN, text) ||
        fail(location, "contains unsupported characters")
    return text
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be a lowercase SHA-256")
    return text
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be boolean")
    return value
end

function expect_true(value, location)
    expect_bool(value, location) === true ||
        fail(location, "must be true")
    return true
end

function expect_false(value, location)
    expect_bool(value, location) === false ||
        fail(location, "must remain false")
    return false
end

function expect_integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    value >= minimum || fail(location, "must be at least $minimum")
    return Int(value)
end

function expect_one_of(value, choices, location)
    text = expect_string(value, location)
    text in choices ||
        fail(location, "must be one of $(join(sort!(collect(choices)), ", "))")
    return text
end

function expect_timestamp(value, location)
    text = expect_string(value, location)
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", text) ||
        fail(location, "must be RFC3339 UTC at second precision")
    return try
        DateTime(text[1:(end - 1)], RFC3339_SECONDS_FORMAT)
    catch
        fail(location, "is not a valid timestamp")
    end
end

function timestamp_text(value::DateTime)
    return Dates.format(value, RFC3339_SECONDS_FORMAT) * "Z"
end

function expect_reference_period(value, location)
    text = expect_string(value, location)
    occursin(r"^\d{4}Q[1-4]$", text) ||
        fail(location, "must use YYYYQn")
    return text
end

function expect_sorted_unique_strings(value, location; expected = nothing)
    array = expect_array(value, location)
    strings = [
        expect_string(item, "$location[$index]")
            for (index, item) in pairs(array)
    ]
    issorted(strings) || fail(location, "must be sorted")
    length(strings) == length(unique(strings)) ||
        fail(location, "must contain unique strings")
    if expected !== nothing
        strings == sort!(collect(String.(expected))) ||
            fail(location, "does not match the expected identities")
    end
    return strings
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
    elseif value isa AbstractVector || value isa Tuple
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
    artifact = deepcopy(expect_table(value, "artifact root"))
    header = expect_table(
        get(artifact, "artifact", nothing),
        "artifact root.artifact",
    )
    pop!(header, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, artifact)
    return bytes2hex(sha256(take!(io)))
end

function stamp_content_sha256!(value)
    artifact = expect_table(value, "artifact root")
    header = expect_table(
        get(artifact, "artifact", nothing),
        "artifact root.artifact",
    )
    header["content_sha256"] = computed_content_sha256(artifact)
    return artifact
end

file_sha256(bytes::AbstractVector{UInt8}) = bytes2hex(sha256(bytes))
file_sha256(path::AbstractString) = file_sha256(read(path))

function _strict_toml_file(path, location)
    isfile(path) || fail(location, "file does not exist: $(abspath(path))")
    islink(path) && fail(location, "must not be a symbolic link")
    bytes = read(path)
    isempty(bytes) && fail(location, "must not be empty")
    bytes[end] == UInt8('\n') || fail(location, "must end with LF")
    UInt8('\r') in bytes && fail(location, "must use LF, not CRLF")
    digest = file_sha256(bytes)
    text = String(copy(bytes))
    isvalid(text) || fail(location, "must be valid UTF-8")
    document = try
        TOML.parse(text)
    catch error
        return fail(
            location,
            "is not valid TOML ($(sprint(showerror, error)))",
        )
    end
    return (; document, bytes, sha256 = digest)
end

function _strict_json_file(path, location)
    isfile(path) || fail(location, "file does not exist: $(abspath(path))")
    islink(path) && fail(location, "must not be a symbolic link")
    bytes = read(path)
    isempty(bytes) && fail(location, "must not be empty")
    bytes[end] == UInt8('\n') || fail(location, "must end with LF")
    UInt8('\r') in bytes && fail(location, "must use LF, not CRLF")
    digest = file_sha256(bytes)
    text = String(copy(bytes))
    isvalid(text) || fail(location, "must be valid UTF-8")
    document = try
        JSON.parse(text)
    catch error
        return fail(
            location,
            "is not valid JSON ($(sprint(showerror, error)))",
        )
    end
    canonical =
        Vector{UInt8}(codeunits(JSON.json(document; sort_keys = true) * "\n"))
    bytes == canonical ||
        fail(
        location,
        "must be canonical JSON with sorted keys, compact separators, and one terminal LF",
    )
    return (; document, bytes, sha256 = digest)
end

function _relative_file(base_dir, value, location)
    name = expect_string(value, location)
    basename(name) == name ||
        fail(location, "must name an adjacent file without directories")
    name in (".", "..") && fail(location, "must not be a dot path")
    occursin('\\', name) &&
        fail(location, "must not contain a backslash")
    base_path = abspath(String(base_dir))
    isdir(base_path) ||
        fail(location, "base directory does not exist: $base_path")
    islink(base_path) &&
        fail(location, "base directory must not be a symbolic link")
    path = joinpath(base_path, name)
    isfile(path) || fail(location, "file does not exist: $path")
    islink(path) && fail(location, "must not resolve to a symbolic link")
    return path
end

function _validate_artifact_hash(root, schema, location)
    artifact = root["artifact"]
    expect_string(artifact["schema_version"], "$location.schema_version") ==
        schema ||
        fail("$location.schema_version", "must equal $schema")
    expect_string(artifact["canonicalization"], "$location.canonicalization") ==
        CANONICALIZATION ||
        fail("$location.canonicalization", "has unsupported value")
    expect_string(artifact["digest_algorithm"], "$location.digest_algorithm") ==
        "sha256" ||
        fail("$location.digest_algorithm", "must equal sha256")
    stored =
        expect_hash(artifact["content_sha256"], "$location.content_sha256")
    computed = computed_content_sha256(root)
    stored == computed ||
        fail(
        "$location.content_sha256",
        "declares $stored but computed $computed",
    )
    return stored
end

function _allow_scope(scope, production, synthetic, allow_synthetic, location)
    scope in (production, synthetic) ||
        fail(location, "has unsupported scope $(repr(scope))")
    scope == synthetic && !allow_synthetic &&
        fail(location, "synthetic fixtures require allow_synthetic=true")
    return scope
end

function _find_signature(bytes, signature)
    length(bytes) >= length(signature) || return false
    final_start = length(bytes) - length(signature) + 1
    for index in 1:final_start
        bytes[index:(index + length(signature) - 1)] == signature &&
            return true
    end
    return false
end

function _validate_container(bytes, file_format, location)
    if file_format == "xlsx"
        length(bytes) >= 22 ||
            fail(location, "OOXML workbook is too short")
        bytes[1:4] == ZIP_LOCAL_SIGNATURE ||
            fail(location, "does not begin with an OOXML ZIP signature")
        _find_signature(bytes, ZIP_END_SIGNATURE) ||
            fail(location, "does not contain a ZIP end-of-directory record")
        return "ooxml_zip"
    elseif file_format == "xls"
        length(bytes) >= 512 ||
            fail(location, "OLE workbook is too short")
        bytes[1:8] == OLE_SIGNATURE ||
            fail(location, "does not begin with an OLE compound-file signature")
        return "ole_compound_file"
    end
    return fail(location, "file format must be xls or xlsx")
end

function _decode_raw_file(path, encoding, location)
    stored = read(path)
    isempty(stored) && fail(location, "stored artifact must not be empty")
    if encoding == "identity"
        return stored
    elseif encoding == "base64_rfc4648"
        stored[end] == UInt8('\n') ||
            fail(location, "base64 artifact must end with LF")
        UInt8('\r') in stored &&
            fail(location, "base64 artifact must use LF")
        text = String(stored)
        isvalid(text) || fail(location, "base64 artifact must be UTF-8")
        encoded = text[1:(end - 1)]
        occursin(r"^[A-Za-z0-9+/]*={0,2}$", encoded) ||
            fail(location, "base64 artifact is not canonical RFC4648")
        decoded = try
            base64decode(encoded)
        catch error
            return fail(
                location,
                "base64 decoding failed ($(sprint(showerror, error)))",
            )
        end
        base64encode(decoded) == encoded ||
            fail(location, "base64 artifact is not canonical")
        return decoded
    end
    return fail(location, "unsupported storage encoding $encoding")
end

function _expected_media_type(file_format)
    file_format == "xls" && return XLS_MEDIA_TYPE
    file_format == "xlsx" && return XLSX_MEDIA_TYPE
    return fail("file_format", "must be xls or xlsx")
end

function _validate_url(url, workbook, location)
    matched = match(OFFICIAL_URL_PATTERN, url)
    matched === nothing &&
        fail(location, "must be an exact official apps.bea.gov HMI7 workbook URL")
    year, quarter, archive_component, filename = matched.captures
    reference_period = workbook["reference_period"]
    year == reference_period[1:4] ||
        fail(location, "URL year does not match reference_period")
    quarter == reference_period[5:6] ||
        fail(location, "URL quarter does not match reference_period")
    archive_component == workbook["archive_label_url_component"] ||
        fail(location, "URL archive label does not match workbook identity")
    filename == workbook["filename"] ||
        fail(location, "URL filename does not match workbook identity")
    prefixes = Dict(
        "advance" => ("Advance_", "1.%20Advance_"),
        "second" => ("Second_",),
        "third" => ("Third_",),
        "preliminary" => ("2.%20Preliminary_",),
        "final" => ("3.%20Final_",),
    )
    estimate_label = workbook["estimate_label"]
    haskey(prefixes, estimate_label) ||
        fail("$location.estimate_label", "has unsupported estimate label")
    any(prefix -> startswith(archive_component, prefix), prefixes[estimate_label]) ||
        fail(location, "archive label does not encode estimate_label")
    return url
end

function _validate_header(status, value, location; date = false)
    header_status =
        expect_one_of(status, Set(["PRESENT", "ABSENT"]), "$location.status")
    text = expect_string(value, "$location.value")
    if header_status == "ABSENT"
        text == "NOT_PROVIDED" ||
            fail("$location.value", "must be NOT_PROVIDED when absent")
    else
        text != "NOT_PROVIDED" ||
            fail("$location.value", "must contain the observed header")
        date && !occursin(HTTP_DATE_PATTERN, text) &&
            fail("$location.value", "must use IMF-fixdate")
    end
    return text
end

function _validate_profile_target(target, location, profile_id)
    expect_exact_keys(target, PROFILE_TARGET_KEYS, location)
    for key in (
            "target_id",
            "section_id",
            "sheet_name",
            "table_number",
            "series_code",
            "frequency",
            "seasonal_adjustment",
            "unit",
            "base_year",
            "mapping_fingerprint",
        )
        expect_string(target[key], "$location.$key")
    end
    for key in ("published_line_number", "physical_row_number")
        expect_integer(target[key], "$location.$key"; minimum = 1)
    end
    computed =
        BEANIPAMappingAudit.mapping_fingerprint(profile_id, target)
    target["mapping_fingerprint"] == computed ||
        fail(
        "$location.mapping_fingerprint",
        "does not match the exact target mapping",
    )
    return String(target["target_id"])
end

"""
    validate_target_profile(profile; allow_synthetic=false, audit=load_mapping_audit())

Validate an immutable semantic profile for one exact two-workbook release.
Production profiles must reuse the exact workbook URLs and raw hashes recorded
by the pinned mapping audit. Synthetic fixtures may substitute bytes only when
explicitly enabled; their target mappings must still match the audited profile.
"""
function validate_target_profile(
        profile;
        allow_synthetic = false,
        audit = BEANIPAMappingAudit.load_mapping_audit(),
    )
    root = expect_exact_keys(profile, PROFILE_ROOT_KEYS, "target_profile")
    artifact = expect_exact_keys(
        root["artifact"],
        PROFILE_ARTIFACT_KEYS,
        "target_profile.artifact",
    )
    expect_string(
        artifact["schema_version"],
        "target_profile.artifact.schema_version",
    ) == PROFILE_SCHEMA ||
        fail(
        "target_profile.artifact.schema_version",
        "must equal $PROFILE_SCHEMA",
    )
    expect_identifier(
        artifact["profile_artifact_id"],
        "target_profile.artifact.profile_artifact_id",
    )
    scope = _allow_scope(
        expect_string(
            artifact["scope"],
            "target_profile.artifact.scope",
        ),
        PROFILE_PRODUCTION_SCOPE,
        PROFILE_SYNTHETIC_SCOPE,
        allow_synthetic,
        "target_profile.artifact.scope",
    )
    expect_hash(
        artifact["source_mapping_audit_file_sha256"],
        "target_profile.artifact.source_mapping_audit_file_sha256",
    ) == audit.sha256 ||
        fail(
        "target_profile.artifact.source_mapping_audit_file_sha256",
        "does not match the pinned mapping audit",
    )
    for key in (
            "historical_release_availability_verified",
            "origin_admissible",
            "ready",
        )
        expect_false(
            artifact[key],
            "target_profile.artifact.$key",
        )
    end
    content_sha256 =
        _validate_artifact_hash(root, PROFILE_SCHEMA, "target_profile.artifact")

    metadata = expect_exact_keys(
        root["profile"],
        PROFILE_KEYS,
        "target_profile.profile",
    )
    profile_id =
        expect_identifier(metadata["profile_id"], "target_profile.profile.profile_id")
    release_id =
        expect_identifier(metadata["release_id"], "target_profile.profile.release_id")
    reference_period = expect_reference_period(
        metadata["reference_period"],
        "target_profile.profile.reference_period",
    )
    metadata["mapping_assignment_basis"] ==
        "EXACT_INSPECTED_RELEASE_AND_TARGET_MAPPING_FINGERPRINTS" ||
        fail(
        "target_profile.profile.mapping_assignment_basis",
        "has unsupported value",
    )
    expect_integer(
        metadata["workbook_count"],
        "target_profile.profile.workbook_count";
        minimum = 0,
    ) == 2 ||
        fail("target_profile.profile.workbook_count", "must equal 2")
    expect_integer(
        metadata["target_count"],
        "target_profile.profile.target_count";
        minimum = 0,
    ) == 5 ||
        fail("target_profile.profile.target_count", "must equal 5")

    audited_profile =
        BEANIPAMappingAudit.profile_for_release(audit, release_id)
    audited_profile["profile_id"] == profile_id ||
        fail(
        "target_profile.profile.profile_id",
        "does not match the audited release assignment",
    )
    audited_release = audit.releases_by_id[release_id]
    audited_release["reference_period"] == reference_period ||
        fail(
        "target_profile.profile.reference_period",
        "does not match the audited release",
    )

    raw_workbooks =
        expect_array(root["workbooks"], "target_profile.workbooks")
    length(raw_workbooks) == 2 ||
        fail("target_profile.workbooks", "must contain exactly two records")
    workbooks_by_section = Dict{String, Any}()
    workbooks_by_id = Dict{String, Any}()
    synthetic = scope == PROFILE_SYNTHETIC_SCOPE
    for (index, raw_workbook) in pairs(raw_workbooks)
        location = "target_profile.workbooks[$index]"
        workbook =
            expect_exact_keys(raw_workbook, PROFILE_WORKBOOK_KEYS, location)
        workbook_id =
            expect_identifier(workbook["workbook_id"], "$location.workbook_id")
        section_id = expect_one_of(
            workbook["section_id"],
            Set(["1", "2"]),
            "$location.section_id",
        )
        file_format = expect_one_of(
            workbook["file_format"],
            Set(["xls", "xlsx"]),
            "$location.file_format",
        )
        official_url =
            expect_string(workbook["official_url"], "$location.official_url")
        raw_sha256 =
            expect_hash(workbook["raw_sha256"], "$location.raw_sha256")
        synthetic_bytes =
            expect_bool(workbook["synthetic_bytes"], "$location.synthetic_bytes")
        synthetic_bytes == synthetic ||
            fail(
            "$location.synthetic_bytes",
            "does not match target-profile scope",
        )
        haskey(audit.workbooks_by_id, workbook_id) ||
            fail("$location.workbook_id", "is absent from the mapping audit")
        audited = audit.workbooks_by_id[workbook_id]
        audited["release_id"] == release_id ||
            fail("$location.workbook_id", "belongs to another release")
        audited["section_id"] == section_id ||
            fail("$location.section_id", "does not match the mapping audit")
        audited["file_format"] == file_format ||
            fail("$location.file_format", "does not match the mapping audit")
        audited["url"] == official_url ||
            fail("$location.official_url", "does not match the mapping audit")
        !synthetic && audited["sha256"] != raw_sha256 &&
            fail("$location.raw_sha256", "does not match the mapping audit")
        haskey(workbooks_by_section, section_id) &&
            fail("$location.section_id", "duplicates section $section_id")
        haskey(workbooks_by_id, workbook_id) &&
            fail("$location.workbook_id", "duplicates $workbook_id")
        workbooks_by_section[section_id] = workbook
        workbooks_by_id[workbook_id] = workbook
    end
    Set(keys(workbooks_by_section)) == Set(["1", "2"]) ||
        fail("target_profile.workbooks", "must contain Sections 1 and 2")

    raw_targets = expect_array(root["targets"], "target_profile.targets")
    length(raw_targets) == 5 ||
        fail("target_profile.targets", "must contain exactly five mappings")
    target_ids = String[]
    target_fingerprints = Dict{String, String}()
    audited_targets = Dict(
        String(target["target_id"]) => target for
            target in audited_profile["targets"]
    )
    for (index, target) in pairs(raw_targets)
        location = "target_profile.targets[$index]"
        target_id = _validate_profile_target(target, location, profile_id)
        haskey(audited_targets, target_id) ||
            fail("$location.target_id", "is absent from the audited profile")
        expected_fingerprint = BEANIPAMappingAudit.mapping_fingerprint(
            profile_id,
            audited_targets[target_id],
        )
        target["mapping_fingerprint"] == expected_fingerprint ||
            fail(
            "$location.mapping_fingerprint",
            "does not match the mapping audit",
        )
        haskey(workbooks_by_section, String(target["section_id"])) ||
            fail("$location.section_id", "has no workbook in the pair")
        target_id in target_ids &&
            fail("$location.target_id", "duplicates $target_id")
        push!(target_ids, target_id)
        target_fingerprints[target_id] = expected_fingerprint
    end
    issorted(target_ids) ||
        fail("target_profile.targets", "must be sorted by target_id")
    Set(target_ids) == Set(keys(audited_targets)) ||
        fail("target_profile.targets", "does not cover the audited profile")

    return (;
        profile_id,
        release_id,
        reference_period,
        scope,
        content_sha256,
        source_mapping_audit_file_sha256 = audit.sha256,
        workbooks_by_section,
        workbooks_by_id,
        target_ids,
        target_fingerprints,
    )
end

function _load_profile(
        base_dir,
        path_value,
        expected_file_sha256;
        allow_synthetic,
        audit,
    )
    path = _relative_file(
        base_dir,
        path_value,
        "receipt.semantic_linkage.profile_artifact_path",
    )
    loaded = _strict_toml_file(path, "target profile file")
    expected = expect_hash(
        expected_file_sha256,
        "receipt.semantic_linkage.profile_file_sha256",
    )
    loaded.sha256 == expected ||
        fail(
        "receipt.semantic_linkage.profile_file_sha256",
        "declares $expected but exact profile bytes hash to $(loaded.sha256)",
    )
    result = validate_target_profile(
        loaded.document;
        allow_synthetic = allow_synthetic,
        audit = audit,
    )
    return merge(
        result,
        (
            file_sha256 = loaded.sha256,
            path = path,
            document = loaded.document,
        ),
    )
end

function _validate_content_fingerprint(
        document,
        profile,
        receipt_workbooks;
        receipt_scope,
        expected_schema_version,
        expected_parser_sha256,
        allow_synthetic,
    )
    root = expect_exact_keys(
        document,
        CONTENT_FINGERPRINT_ROOT_KEYS,
        "content_fingerprint",
    )
    artifact = expect_exact_keys(
        root["artifact"],
        CONTENT_FINGERPRINT_ARTIFACT_KEYS,
        "content_fingerprint.artifact",
    )
    schema_version = expect_string(
        artifact["schema_version"],
        "content_fingerprint.artifact.schema_version",
    )
    schema_version == CONTENT_FINGERPRINT_SCHEMA ||
        fail(
        "content_fingerprint.artifact.schema_version",
        "must equal $CONTENT_FINGERPRINT_SCHEMA",
    )
    schema_version == expect_string(
        expected_schema_version,
        "receipt.semantic_linkage.content_fingerprint_schema_version",
    ) ||
        fail(
        "receipt.semantic_linkage.content_fingerprint_schema_version",
        "does not match the content-fingerprint artifact",
    )
    artifact["parser_version"] == CONTENT_FINGERPRINT_PARSER_VERSION ||
        fail(
        "content_fingerprint.artifact.parser_version",
        "must equal $CONTENT_FINGERPRINT_PARSER_VERSION",
    )
    artifact["canonicalization"] ==
        CONTENT_FINGERPRINT_CANONICALIZATION ||
        fail(
        "content_fingerprint.artifact.canonicalization",
        "must equal $CONTENT_FINGERPRINT_CANONICALIZATION",
    )
    artifact["semantic_identity_scope"] ==
        CONTENT_FINGERPRINT_SEMANTIC_IDENTITY_SCOPE ||
        fail(
        "content_fingerprint.artifact.semantic_identity_scope",
        "must equal $CONTENT_FINGERPRINT_SEMANTIC_IDENTITY_SCOPE",
    )
    parser_sha256 = expect_hash(
        artifact["parser_sha256"],
        "content_fingerprint.artifact.parser_sha256",
    )
    parser_sha256 == CONTENT_FINGERPRINT_PARSER_SHA256 ||
        fail(
        "content_fingerprint.artifact.parser_sha256",
        "must equal the pinned v2 parser SHA-256",
    )
    parser_sha256 == expect_hash(
        expected_parser_sha256,
        "receipt.semantic_linkage.content_fingerprint_parser_sha256",
    ) ||
        fail(
        "receipt.semantic_linkage.content_fingerprint_parser_sha256",
        "does not match the content-fingerprint artifact",
    )

    expected_status =
        receipt_scope == PRODUCTION_SCOPE ?
        CONTENT_FINGERPRINT_PRODUCTION_STATUS :
        CONTENT_FINGERPRINT_SYNTHETIC_STATUS
    expected_evidence_class =
        receipt_scope == PRODUCTION_SCOPE ?
        CONTENT_FINGERPRINT_PRODUCTION_EVIDENCE_CLASS :
        CONTENT_FINGERPRINT_SYNTHETIC_EVIDENCE_CLASS
    status =
        expect_string(artifact["status"], "content_fingerprint.artifact.status")
    status == expected_status ||
        fail(
        "content_fingerprint.artifact.status",
        "must equal $expected_status for the receipt scope",
    )
    status == CONTENT_FINGERPRINT_SYNTHETIC_STATUS && !allow_synthetic &&
        fail(
        "content_fingerprint.artifact.status",
        "synthetic fixtures require allow_synthetic=true",
    )
    artifact["evidence_class"] == expected_evidence_class ||
        fail(
        "content_fingerprint.artifact.evidence_class",
        "does not match the receipt scope",
    )

    artifact["release_id"] == profile.release_id ||
        fail(
        "content_fingerprint.artifact.release_id",
        "does not match the target profile",
    )
    artifact["reference_quarter"] == profile.reference_period ||
        fail(
        "content_fingerprint.artifact.reference_quarter",
        "does not match the target profile",
    )
    artifact["mapping_profile_id"] == profile.profile_id ||
        fail(
        "content_fingerprint.artifact.mapping_profile_id",
        "does not match the target profile",
    )
    expect_hash(
        artifact["mapping_audit_sha256"],
        "content_fingerprint.artifact.mapping_audit_sha256",
    ) == profile.source_mapping_audit_file_sha256 ||
        fail(
        "content_fingerprint.artifact.mapping_audit_sha256",
        "does not match the pinned mapping audit",
    )
    expect_hash(
        artifact["raw_bundle_sha256"],
        "content_fingerprint.artifact.raw_bundle_sha256",
    )
    estimate_labels =
        unique(workbook.estimate_label for workbook in receipt_workbooks)
    length(estimate_labels) == 1 ||
        fail("content_fingerprint", "receipt pair has ambiguous estimate labels")
    artifact["estimate_label"] == only(estimate_labels) ||
        fail(
        "content_fingerprint.artifact.estimate_label",
        "does not match the receipt pair",
    )
    artifact["source_agency"] == "U.S. Bureau of Economic Analysis" ||
        fail(
        "content_fingerprint.artifact.source_agency",
        "has unsupported value",
    )
    artifact["source_attribution"] ==
        "Source: U.S. Bureau of Economic Analysis" ||
        fail(
        "content_fingerprint.artifact.source_attribution",
        "has unsupported value",
    )
    expect_string(
        artifact["persistence_scope"],
        "content_fingerprint.artifact.persistence_scope",
    )
    for key in (
            "execution_environment_included",
            "repository_state_included",
            "release_event_evidence_included",
            "historical_availability_evidence_included",
            "historical_availability_verified",
            "inventory_mutated",
            "origin_admissible",
            "ready",
        )
        expect_false(
            artifact[key],
            "content_fingerprint.artifact.$key",
        )
    end

    receipt_by_id = Dict(
        workbook.workbook_id => workbook for workbook in receipt_workbooks
    )
    raw_workbooks =
        expect_array(root["workbooks"], "content_fingerprint.workbooks")
    length(raw_workbooks) == 2 ||
        fail(
        "content_fingerprint.workbooks",
        "must contain exactly two records",
    )
    fingerprint_workbooks = Dict{String, Any}()
    workbook_ids = String[]
    sections = String[]
    for (index, raw_workbook) in pairs(raw_workbooks)
        location = "content_fingerprint.workbooks[$index]"
        workbook = expect_exact_keys(
            raw_workbook,
            CONTENT_FINGERPRINT_WORKBOOK_KEYS,
            location,
        )
        workbook_id =
            expect_identifier(workbook["workbook_id"], "$location.workbook_id")
        section_id = expect_one_of(
            workbook["section_id"],
            Set(["1", "2"]),
            "$location.section_id",
        )
        haskey(receipt_by_id, workbook_id) ||
            fail(
            "$location.workbook_id",
            "is absent from the receipt pair",
        )
        haskey(fingerprint_workbooks, workbook_id) &&
            fail("$location.workbook_id", "duplicates $workbook_id")
        receipt_workbook = receipt_by_id[workbook_id]
        section_id == receipt_workbook.section_id ||
            fail("$location.section_id", "does not match the receipt")
        workbook["release_id"] == receipt_workbook.release_id ||
            fail("$location.release_id", "does not match the receipt")
        workbook["mapping_profile_id"] == profile.profile_id ||
            fail(
            "$location.mapping_profile_id",
            "does not match the target profile",
        )
        workbook["file_format"] == receipt_workbook.file_format ||
            fail("$location.file_format", "does not match the receipt")
        workbook["file_format"] == "xlsx" ||
            fail(
            "$location.file_format",
            "content-fingerprint v2 supports xlsx only",
        )
        expect_true(
            workbook["ooxml_zip_integrity_verified"],
            "$location.ooxml_zip_integrity_verified",
        )
        expect_string(
            workbook["data_published_text"],
            "$location.data_published_text",
        )
        expect_string(
            workbook["raw_object_path"],
            "$location.raw_object_path",
        )
        workbook["requested_locator"] == receipt_workbook.effective_url ||
            fail(
            "$location.requested_locator",
            "does not match the receipt URL",
        )
        raw_sha256 =
            expect_hash(workbook["raw_sha256"], "$location.raw_sha256")
        raw_sha256 == receipt_workbook.raw_sha256 ||
            fail(
            "$location.raw_sha256",
            "does not match the receipt's exact raw bytes",
        )
        expect_integer(
            workbook["raw_byte_count"],
            "$location.raw_byte_count";
            minimum = 1,
        ) == receipt_workbook.raw_bytes ||
            fail(
            "$location.raw_byte_count",
            "does not match the receipt's exact raw byte count",
        )
        expect_integer(
            workbook["sheet_count"],
            "$location.sheet_count";
            minimum = 1,
        )
        for key in (
                "historical_availability_verified",
                "origin_admissible",
                "ready",
            )
            expect_false(workbook[key], "$location.$key")
        end
        fingerprint_workbooks[workbook_id] = workbook
        push!(workbook_ids, workbook_id)
        push!(sections, section_id)
    end
    issorted(workbook_ids) ||
        fail(
        "content_fingerprint.workbooks",
        "must be sorted by workbook_id",
    )
    sections == ["1", "2"] ||
        fail(
        "content_fingerprint.workbooks",
        "must be sorted as Sections 1 then 2",
    )
    Set(workbook_ids) == Set(keys(receipt_by_id)) ||
        fail(
        "content_fingerprint.workbooks",
        "does not cover the exact receipt pair",
    )

    raw_targets =
        expect_array(root["targets"], "content_fingerprint.targets")
    length(raw_targets) == 5 ||
        fail(
        "content_fingerprint.targets",
        "must contain exactly five records",
    )
    target_ids = String[]
    for (index, raw_target) in pairs(raw_targets)
        location = "content_fingerprint.targets[$index]"
        target = expect_exact_keys(
            raw_target,
            CONTENT_FINGERPRINT_TARGET_KEYS,
            location,
        )
        for key in (
                "target_id",
                "workbook_id",
                "section_id",
                "sheet_name",
                "table_number",
                "table_title",
                "normalized_concept",
                "series_code",
                "frequency",
                "seasonal_adjustment",
                "unit",
                "base_year",
                "number_format_code",
            )
            expect_string(target[key], "$location.$key")
        end
        expect_nonempty_text(
            target["source_concept_text"],
            "$location.source_concept_text",
        )
        target_id =
            expect_identifier(target["target_id"], "$location.target_id")
        workbook_id =
            expect_identifier(target["workbook_id"], "$location.workbook_id")
        haskey(fingerprint_workbooks, workbook_id) ||
            fail("$location.workbook_id", "is absent from the workbook pair")
        workbook = fingerprint_workbooks[workbook_id]
        target["section_id"] == workbook["section_id"] ||
            fail(
            "$location.section_id",
            "does not match its fingerprint workbook",
        )
        raw_sha256 =
            expect_hash(target["raw_sha256"], "$location.raw_sha256")
        raw_sha256 == workbook["raw_sha256"] ||
            fail(
            "$location.raw_sha256",
            "does not match its fingerprint workbook",
        )
        for key in ("published_line_number", "physical_row_number")
            expect_integer(target[key], "$location.$key"; minimum = 1)
        end
        expect_integer(
            target["decimal_places"],
            "$location.decimal_places";
            minimum = 0,
        )
        reference_period_count = expect_integer(
            target["reference_period_count"],
            "$location.reference_period_count";
            minimum = 1,
        )
        available_value_count = expect_integer(
            target["available_value_count"],
            "$location.available_value_count";
            minimum = 0,
        )
        missing_value_count = expect_integer(
            target["missing_value_count"],
            "$location.missing_value_count";
            minimum = 0,
        )
        available_value_count + missing_value_count ==
            reference_period_count ||
            fail(
            location,
            "available and missing counts do not cover every reference period",
        )
        reference_period_start = expect_reference_period(
            target["reference_period_start"],
            "$location.reference_period_start",
        )
        reference_period_end = expect_reference_period(
            target["reference_period_end"],
            "$location.reference_period_end",
        )
        expect_hash(
            target["raw_values_sha256"],
            "$location.raw_values_sha256",
        )
        expect_hash(
            target["published_values_sha256"],
            "$location.published_values_sha256",
        )
        source_cells = expect_exact_keys(
            target["source_cells"],
            CONTENT_FINGERPRINT_SOURCE_CELL_KEYS,
            "$location.source_cells",
        )
        for key in CONTENT_FINGERPRINT_SOURCE_CELL_KEYS
            expect_string(source_cells[key], "$location.source_cells.$key")
        end
        observations =
            expect_array(target["observations"], "$location.observations")
        length(observations) == reference_period_count ||
            fail(
            "$location.observations",
            "length does not match reference_period_count",
        )
        periods = String[]
        observed_missing = 0
        for (observation_index, raw_observation) in pairs(observations)
            observation_location =
                "$location.observations[$observation_index]"
            observation = expect_exact_keys(
                raw_observation,
                CONTENT_FINGERPRINT_OBSERVATION_KEYS,
                observation_location,
            )
            period = expect_reference_period(
                observation["period"],
                "$observation_location.period",
            )
            raw_value = expect_string(
                observation["raw_value_text"],
                "$observation_location.raw_value_text",
            )
            expect_string(
                observation["published_value_text"],
                "$observation_location.published_value_text",
            )
            raw_value == "....." && (observed_missing += 1)
            push!(periods, period)
        end
        issorted(periods) ||
            fail("$location.observations", "must be sorted by period")
        length(periods) == length(unique(periods)) ||
            fail("$location.observations", "contains duplicate periods")
        first(periods) == reference_period_start ||
            fail(
            "$location.reference_period_start",
            "does not match the first observation",
        )
        last(periods) == reference_period_end ||
            fail(
            "$location.reference_period_end",
            "does not match the last observation",
        )
        observed_missing == missing_value_count ||
            fail(
            "$location.missing_value_count",
            "does not match the observation values",
        )
        for key in (
                "historical_availability_verified",
                "origin_admissible",
                "ready",
            )
            expect_false(target[key], "$location.$key")
        end
        haskey(profile.target_fingerprints, target_id) ||
            fail("$location.target_id", "is absent from the target profile")
        mapping_fingerprint =
            BEANIPAMappingAudit.mapping_fingerprint(profile.profile_id, target)
        mapping_fingerprint == profile.target_fingerprints[target_id] ||
            fail(
            location,
            "mapping fingerprint does not match the target profile",
        )
        target_id in target_ids &&
            fail("$location.target_id", "duplicates $target_id")
        push!(target_ids, target_id)
    end
    issorted(target_ids) ||
        fail(
        "content_fingerprint.targets",
        "must be sorted by target_id",
    )
    target_ids == profile.target_ids ||
        fail(
        "content_fingerprint.targets",
        "does not cover the target profile",
    )

    return (;
        schema_version,
        parser_sha256,
        status,
        target_ids,
        workbooks_by_id = fingerprint_workbooks,
    )
end

function _load_content_fingerprint(
        base_dir,
        path_value,
        expected_file_sha256,
        expected_schema_version,
        expected_parser_sha256,
        profile,
        receipt_workbooks;
        receipt_scope,
        allow_synthetic,
    )
    path = _relative_file(
        base_dir,
        path_value,
        "receipt.semantic_linkage.content_fingerprint_artifact_path",
    )
    loaded = _strict_json_file(path, "content-fingerprint file")
    expected = expect_hash(
        expected_file_sha256,
        "receipt.semantic_linkage.content_fingerprint_file_sha256",
    )
    loaded.sha256 == expected ||
        fail(
        "receipt.semantic_linkage.content_fingerprint_file_sha256",
        "declares $expected but exact JSON bytes hash to $(loaded.sha256)",
    )
    result = _validate_content_fingerprint(
        loaded.document,
        profile,
        receipt_workbooks;
        receipt_scope = receipt_scope,
        expected_schema_version = expected_schema_version,
        expected_parser_sha256 = expected_parser_sha256,
        allow_synthetic = allow_synthetic,
    )
    return merge(
        result,
        (
            file_sha256 = loaded.sha256,
            path = path,
            document = loaded.document,
        ),
    )
end

function _content_fingerprint_identity(base_dir, path_value)
    path = _relative_file(
        base_dir,
        path_value,
        "content_fingerprint_artifact_path",
    )
    loaded = _strict_json_file(path, "content-fingerprint file")
    root = expect_exact_keys(
        loaded.document,
        CONTENT_FINGERPRINT_ROOT_KEYS,
        "content_fingerprint",
    )
    artifact = expect_exact_keys(
        root["artifact"],
        CONTENT_FINGERPRINT_ARTIFACT_KEYS,
        "content_fingerprint.artifact",
    )
    return (;
        file_sha256 = loaded.sha256,
        schema_version = expect_string(
            artifact["schema_version"],
            "content_fingerprint.artifact.schema_version",
        ),
        parser_sha256 = expect_hash(
            artifact["parser_sha256"],
            "content_fingerprint.artifact.parser_sha256",
        ),
    )
end

function _raw_bytes(
        workbook,
        base_dir,
        location;
        raw_overrides = nothing,
    )
    path_value =
        expect_string(workbook["raw_artifact_path"], "$location.raw_artifact_path")
    bytes = if raw_overrides !== nothing && haskey(raw_overrides, path_value)
        Vector{UInt8}(raw_overrides[path_value])
    else
        path = _relative_file(
            base_dir,
            path_value,
            "$location.raw_artifact_path",
        )
        _decode_raw_file(
            path,
            expect_string(
                workbook["storage_encoding"],
                "$location.storage_encoding",
            ),
            "$location.raw_artifact_path",
        )
    end
    expected_bytes =
        expect_integer(workbook["raw_bytes"], "$location.raw_bytes"; minimum = 1)
    length(bytes) == expected_bytes ||
        fail(
        "$location.raw_bytes",
        "declares $expected_bytes but decoded artifact has $(length(bytes)) bytes",
    )
    expected_sha =
        expect_hash(workbook["raw_sha256"], "$location.raw_sha256")
    actual_sha = file_sha256(bytes)
    actual_sha == expected_sha ||
        fail(
        "$location.raw_sha256",
        "declares $expected_sha but decoded artifact hashes to $actual_sha",
    )
    format =
        expect_one_of(workbook["file_format"], Set(["xls", "xlsx"]), "$location.file_format")
    signature = _validate_container(bytes, format, "$location.container_signature")
    workbook["container_signature"] == signature ||
        fail(
        "$location.container_signature",
        "declares $(workbook["container_signature"]) but detected $signature",
    )
    expected_name = if workbook["storage_encoding"] == "identity"
        "raw-sha256-$actual_sha.$format"
    elseif workbook["storage_encoding"] == "base64_rfc4648"
        "raw-sha256-$actual_sha.$format.b64"
    else
        fail("$location.storage_encoding", "has unsupported value")
    end
    path_value == expected_name ||
        fail(
        "$location.raw_artifact_path",
        "must be content addressed as $expected_name",
    )
    return (; bytes, sha256 = actual_sha, byte_count = length(bytes))
end

function _validate_workbook_record(
        workbook,
        index,
        base_dir,
        profile;
        receipt_scope,
        raw_overrides = nothing,
    )
    location = "receipt.workbooks[$index]"
    expect_exact_keys(workbook, WORKBOOK_KEYS, location)
    release_id = expect_identifier(workbook["release_id"], "$location.release_id")
    workbook_id =
        expect_identifier(workbook["workbook_id"], "$location.workbook_id")
    reference_period =
        expect_reference_period(workbook["reference_period"], "$location.reference_period")
    estimate_label = expect_one_of(
        workbook["estimate_label"],
        Set(["advance", "second", "third", "preliminary", "final"]),
        "$location.estimate_label",
    )
    expect_string(
        workbook["archive_label_url_component"],
        "$location.archive_label_url_component",
    )
    occursin(
        r"^\d+$", expect_string(
            workbook["archive_directory_id"],
            "$location.archive_directory_id",
        )
    ) || fail("$location.archive_directory_id", "must contain decimal digits")
    expect_integer(workbook["hmi_id"], "$location.hmi_id"; minimum = 0) == 7 ||
        fail("$location.hmi_id", "must equal 7")
    workbook["publication_variant"] == "published_main" ||
        fail("$location.publication_variant", "must equal published_main")
    section_id =
        expect_one_of(workbook["section_id"], Set(["1", "2"]), "$location.section_id")
    filename = expect_string(workbook["filename"], "$location.filename")
    matched = match(WORKBOOK_FILENAME_PATTERN, filename)
    matched === nothing &&
        fail("$location.filename", "is not a BEA section workbook filename")
    uppercase(matched.captures[1]) == section_id ||
        fail("$location.filename", "does not match section_id")
    file_format =
        expect_one_of(workbook["file_format"], Set(["xls", "xlsx"]), "$location.file_format")
    lowercase(matched.captures[2]) == file_format ||
        fail("$location.filename", "extension does not match file_format")
    workbook["identity_status"] ==
        "EXACT_URL_PATH_FILENAME_SECTION_PROFILE_AND_BYTES_BOUND" ||
        fail("$location.identity_status", "has unsupported value")
    expect_one_of(
        workbook["storage_encoding"],
        Set(["identity", "base64_rfc4648"]),
        "$location.storage_encoding",
    )
    receipt_scope == PRODUCTION_SCOPE &&
        workbook["storage_encoding"] != "identity" &&
        fail("$location.storage_encoding", "production receipts require identity bytes")
    raw = _raw_bytes(
        workbook,
        base_dir,
        location;
        raw_overrides = raw_overrides,
    )

    started = expect_timestamp(
        workbook["acquisition_started_at_utc"],
        "$location.acquisition_started_at_utc",
    )
    headers = expect_timestamp(
        workbook["response_headers_at_utc"],
        "$location.response_headers_at_utc",
    )
    completed = expect_timestamp(
        workbook["acquisition_completed_at_utc"],
        "$location.acquisition_completed_at_utc",
    )
    started <= headers <= completed ||
        fail(location, "acquisition timestamps are not ordered")
    workbook["retrieval_observation_scope"] ==
        "PRESENT_DAY_RETRIEVAL_TIMES_NOT_HISTORICAL_RELEASE_AVAILABILITY" ||
        fail("$location.retrieval_observation_scope", "has unsupported value")

    workbook["method"] == "GET" ||
        fail("$location.method", "must equal GET")
    requested_url =
        expect_string(workbook["requested_url"], "$location.requested_url")
    effective_url =
        expect_string(workbook["effective_url"], "$location.effective_url")
    requested_url == effective_url ||
        fail(location, "redirected workbook responses are ambiguous")
    _validate_url(effective_url, workbook, "$location.effective_url")
    expect_integer(workbook["status_code"], "$location.status_code") == 200 ||
        fail("$location.status_code", "must equal 200")
    expect_integer(
        workbook["redirect_count"],
        "$location.redirect_count";
        minimum = 0,
    ) == 0 ||
        fail("$location.redirect_count", "must equal 0")
    expected_content_type = _expected_media_type(file_format)
    workbook["content_type"] == expected_content_type ||
        fail(
        "$location.content_type",
        "must equal $expected_content_type",
    )
    content_length_status = expect_one_of(
        workbook["content_length_header_status"],
        Set(["PRESENT", "ABSENT"]),
        "$location.content_length_header_status",
    )
    content_length = expect_integer(
        workbook["content_length_header"],
        "$location.content_length_header";
        minimum = -1,
    )
    if content_length_status == "PRESENT"
        content_length == raw.byte_count ||
            fail(
            "$location.content_length_header",
            "does not equal decoded raw byte count",
        )
    else
        content_length == -1 ||
            fail(
            "$location.content_length_header",
            "must equal -1 when header is absent",
        )
    end
    _validate_header(
        workbook["etag_status"],
        workbook["etag"],
        "$location.etag",
    )
    _validate_header(
        workbook["last_modified_status"],
        workbook["last_modified"],
        "$location.last_modified";
        date = true,
    )
    content_disposition = _validate_header(
        workbook["content_disposition_status"],
        workbook["content_disposition"],
        "$location.content_disposition",
    )
    if workbook["content_disposition_status"] == "PRESENT"
        occursin(filename, content_disposition) ||
            fail(
            "$location.content_disposition",
            "does not identify the exact workbook filename",
        )
    end

    release_id == profile.release_id ||
        fail("$location.release_id", "does not match semantic profile")
    reference_period == profile.reference_period ||
        fail("$location.reference_period", "does not match semantic profile")
    haskey(profile.workbooks_by_id, workbook_id) ||
        fail("$location.workbook_id", "is absent from semantic profile")
    profile_workbook = profile.workbooks_by_id[workbook_id]
    profile_workbook["section_id"] == section_id ||
        fail("$location.section_id", "does not match semantic profile")
    profile_workbook["official_url"] == effective_url ||
        fail("$location.effective_url", "does not match semantic profile")
    profile_workbook["file_format"] == file_format ||
        fail("$location.file_format", "does not match semantic profile")
    profile_workbook["raw_sha256"] == raw.sha256 ||
        fail("$location.raw_sha256", "does not match semantic profile")

    return (;
        release_id,
        workbook_id,
        reference_period,
        estimate_label,
        archive_label_url_component =
            String(workbook["archive_label_url_component"]),
        archive_directory_id = String(workbook["archive_directory_id"]),
        section_id,
        filename,
        file_format,
        effective_url,
        raw_sha256 = raw.sha256,
        raw_bytes = raw.byte_count,
        started,
        headers,
        completed,
    )
end

function _validate_receipt(
        receipt,
        base_dir;
        allow_synthetic = false,
        audit = BEANIPAMappingAudit.load_mapping_audit(),
        raw_overrides = nothing,
    )
    root = expect_exact_keys(receipt, RECEIPT_ROOT_KEYS, "receipt")
    artifact = expect_exact_keys(
        root["artifact"],
        RECEIPT_ARTIFACT_KEYS,
        "receipt.artifact",
    )
    receipt_id =
        expect_identifier(artifact["receipt_id"], "receipt.artifact.receipt_id")
    scope = _allow_scope(
        expect_string(artifact["scope"], "receipt.artifact.scope"),
        PRODUCTION_SCOPE,
        SYNTHETIC_SCOPE,
        allow_synthetic,
        "receipt.artifact.scope",
    )
    expected_state =
        scope == PRODUCTION_SCOPE ? PRODUCTION_STATE : SYNTHETIC_STATE
    artifact["state"] == expected_state ||
        fail(
        "receipt.artifact.state",
        "must equal $expected_state for the declared scope",
    )
    expect_true(
        artifact["immutable_receipt"],
        "receipt.artifact.immutable_receipt",
    )
    expect_true(
        artifact["present_day_acquisition_observed"],
        "receipt.artifact.present_day_acquisition_observed",
    )
    for key in (
            "historical_release_availability_verified",
            "release_event_timestamp_verified",
            "first_state_verified",
            "origin_admissible",
            "inventory_registered",
            "ready",
        )
        expect_false(artifact[key], "receipt.artifact.$key")
    end
    content_sha256 =
        _validate_artifact_hash(root, RECEIPT_SCHEMA, "receipt.artifact")

    capture =
        expect_exact_keys(root["capture"], CAPTURE_KEYS, "receipt.capture")
    transaction_id =
        expect_identifier(capture["transaction_id"], "receipt.capture.transaction_id")
    expect_identifier(capture["observer_id"], "receipt.capture.observer_id")
    expect_identifier(capture["capture_agent"], "receipt.capture.capture_agent")
    expect_identifier(
        capture["capture_agent_version"],
        "receipt.capture.capture_agent_version",
    )
    pair_started =
        expect_timestamp(capture["pair_started_at_utc"], "receipt.capture.pair_started_at_utc")
    pair_completed = expect_timestamp(
        capture["pair_completed_at_utc"],
        "receipt.capture.pair_completed_at_utc",
    )
    pair_started <= pair_completed ||
        fail("receipt.capture", "pair completion precedes pair start")
    max_span = expect_integer(
        capture["max_pair_span_seconds"],
        "receipt.capture.max_pair_span_seconds";
        minimum = 1,
    )
    observed_span = expect_integer(
        capture["observed_pair_span_seconds"],
        "receipt.capture.observed_pair_span_seconds";
        minimum = 0,
    )
    computed_span =
        div(Dates.value(pair_completed - pair_started), 1000)
    observed_span == computed_span ||
        fail(
        "receipt.capture.observed_pair_span_seconds",
        "declares $observed_span but timestamps imply $computed_span",
    )
    observed_span <= max_span ||
        fail("receipt.capture", "pair acquisition exceeds maximum span")
    capture["atomicity_policy"] ==
        "ALL_OR_NOTHING_SECTION_1_AND_2_SAME_RELEASE_TRANSACTION" ||
        fail("receipt.capture.atomicity_policy", "has unsupported value")
    expect_true(
        capture["atomic_pair_complete"],
        "receipt.capture.atomic_pair_complete",
    )
    capture["acquisition_clock_basis"] ==
        "CAPTURE_HOST_UTC_CLOCK_OBSERVATION_ONLY" ||
        fail("receipt.capture.acquisition_clock_basis", "has unsupported value")

    linkage = expect_exact_keys(
        root["semantic_linkage"],
        SEMANTIC_LINKAGE_KEYS,
        "receipt.semantic_linkage",
    )
    profile = _load_profile(
        base_dir,
        linkage["profile_artifact_path"],
        linkage["profile_file_sha256"];
        allow_synthetic = allow_synthetic,
        audit = audit,
    )
    linkage["profile_content_sha256"] == profile.content_sha256 ||
        fail(
        "receipt.semantic_linkage.profile_content_sha256",
        "does not match target profile",
    )
    linkage["source_mapping_audit_file_sha256"] ==
        profile.source_mapping_audit_file_sha256 ||
        fail(
        "receipt.semantic_linkage.source_mapping_audit_file_sha256",
        "does not match target profile",
    )
    linkage["profile_id"] == profile.profile_id ||
        fail("receipt.semantic_linkage.profile_id", "does not match target profile")
    linked_target_ids = expect_sorted_unique_strings(
        linkage["linked_target_ids"],
        "receipt.semantic_linkage.linked_target_ids";
        expected = profile.target_ids,
    )
    linkage["linkage_basis"] ==
        "EXACT_PROFILE_AND_CONTENT_FINGERPRINT_FILES_RAW_SHA_URL_WORKBOOK_IDS_AND_TARGET_FINGERPRINTS" ||
        fail("receipt.semantic_linkage.linkage_basis", "has unsupported value")
    linkage["linkage_status"] == "EXACTLY_LINKED_NON_ADMITTING" ||
        fail("receipt.semantic_linkage.linkage_status", "has unsupported value")
    expect_false(
        linkage["historical_availability_inferred"],
        "receipt.semantic_linkage.historical_availability_inferred",
    )
    expect_false(
        linkage["origin_admission_inferred"],
        "receipt.semantic_linkage.origin_admission_inferred",
    )

    raw_workbooks = expect_array(root["workbooks"], "receipt.workbooks")
    length(raw_workbooks) == 2 ||
        fail("receipt.workbooks", "must contain exactly two records")
    results = [
        _validate_workbook_record(
                workbook,
                index,
                base_dir,
                profile;
                receipt_scope = scope,
                raw_overrides = raw_overrides,
            )
            for (index, workbook) in pairs(raw_workbooks)
    ]
    sections = [result.section_id for result in results]
    sections == ["1", "2"] ||
        fail("receipt.workbooks", "must be sorted as Sections 1 then 2")
    length(unique(result.workbook_id for result in results)) == 2 ||
        fail("receipt.workbooks", "contains duplicate workbook IDs")
    length(unique(result.effective_url for result in results)) == 2 ||
        fail("receipt.workbooks", "contains duplicate workbook URLs")
    length(unique(result.raw_sha256 for result in results)) == 2 ||
        fail("receipt.workbooks", "contains duplicate raw hashes")
    all(result -> result.release_id == profile.release_id, results) ||
        fail("receipt.workbooks", "pair spans multiple release IDs")
    length(unique(result.reference_period for result in results)) == 1 ||
        fail("receipt.workbooks", "pair spans multiple reference periods")
    length(unique(result.estimate_label for result in results)) == 1 ||
        fail("receipt.workbooks", "pair spans multiple estimate labels")
    length(
        unique(result.archive_label_url_component for result in results),
    ) == 1 ||
        fail("receipt.workbooks", "pair spans multiple archive labels")
    length(unique(result.archive_directory_id for result in results)) == 1 ||
        fail("receipt.workbooks", "pair spans multiple archive directory IDs")
    all(
        result ->
        pair_started <= result.started <= result.completed <=
            pair_completed,
        results,
    ) || fail("receipt.capture", "workbook interval lies outside pair interval")
    content_fingerprint = _load_content_fingerprint(
        base_dir,
        linkage["content_fingerprint_artifact_path"],
        linkage["content_fingerprint_file_sha256"],
        linkage["content_fingerprint_schema_version"],
        linkage["content_fingerprint_parser_sha256"],
        profile,
        results;
        receipt_scope = scope,
        allow_synthetic = allow_synthetic,
    )

    return (;
        receipt_id,
        transaction_id,
        scope,
        state = String(artifact["state"]),
        content_sha256,
        profile_id = profile.profile_id,
        profile_file_sha256 = profile.file_sha256,
        profile_content_sha256 = profile.content_sha256,
        content_fingerprint_file_sha256 =
            content_fingerprint.file_sha256,
        content_fingerprint_schema_version =
            content_fingerprint.schema_version,
        content_fingerprint_parser_sha256 =
            content_fingerprint.parser_sha256,
        release_id = profile.release_id,
        reference_period = profile.reference_period,
        linked_target_ids,
        workbooks = results,
        pair_started,
        pair_completed,
        present_day_acquisition_observed = true,
        historical_release_availability_verified = false,
        release_event_timestamp_verified = false,
        first_state_verified = false,
        origin_admissible = false,
        inventory_registered = false,
        ready = false,
    )
end

"""
    validate_receipt(receipt, base_dir; allow_synthetic=false)

Validate a parsed atomic receipt and its adjacent target-profile/raw files.
This proves only a present-day acquisition observation. Historical release
availability, first-state status, inventory registration, origin admission,
and READY remain false.
"""
function validate_receipt(
        receipt,
        base_dir;
        allow_synthetic = false,
        audit = BEANIPAMappingAudit.load_mapping_audit(),
    )
    return _validate_receipt(
        receipt,
        base_dir;
        allow_synthetic = allow_synthetic,
        audit = audit,
    )
end

function validate_receipt_file(
        path::AbstractString;
        allow_synthetic = false,
        audit = BEANIPAMappingAudit.load_mapping_audit(),
    )
    loaded = _strict_toml_file(path, "receipt file")
    result = validate_receipt(
        loaded.document,
        dirname(abspath(path));
        allow_synthetic = allow_synthetic,
        audit = audit,
    )
    return merge(
        result,
        (
            receipt_file_sha256 = loaded.sha256,
            receipt_file_bytes = length(loaded.bytes),
            receipt_path = abspath(path),
        ),
    )
end

"""
    verify_local_raw_files(receipt, base_dir)

Verify that both adjacent raw artifacts exist, are regular non-symlink files,
decode canonically when stored as base64, match their exact byte counts and
SHA-256 values, and carry the declared workbook container signatures.
"""
function verify_local_raw_files(receipt, base_dir)
    root = expect_exact_keys(receipt, RECEIPT_ROOT_KEYS, "receipt")
    raw_workbooks = expect_array(root["workbooks"], "receipt.workbooks")
    length(raw_workbooks) == 2 ||
        fail("receipt.workbooks", "must contain exactly two records")
    results = Dict{String, Any}()
    for (index, workbook) in pairs(raw_workbooks)
        location = "receipt.workbooks[$index]"
        expect_exact_keys(workbook, WORKBOOK_KEYS, location)
        section =
            expect_one_of(workbook["section_id"], Set(["1", "2"]), "$location.section_id")
        haskey(results, section) &&
            fail("$location.section_id", "duplicates section $section")
        results[section] = _raw_bytes(workbook, base_dir, location)
    end
    Set(keys(results)) == Set(["1", "2"]) ||
        fail("receipt.workbooks", "must contain Sections 1 and 2")
    return results
end

function _header_fields(value)
    if value === nothing
        return ("ABSENT", "NOT_PROVIDED")
    end
    return ("PRESENT", String(value))
end

function _fetch_record(fetch::WorkbookFetch)
    raw_sha256 = file_sha256(fetch.raw_bytes)
    signature =
        _validate_container(fetch.raw_bytes, fetch.file_format, "workbook fetch")
    content_length_status =
        fetch.content_length_header === nothing ? "ABSENT" : "PRESENT"
    content_length =
        fetch.content_length_header === nothing ? -1 : fetch.content_length_header
    etag_status, etag = _header_fields(fetch.etag)
    last_modified_status, last_modified = _header_fields(fetch.last_modified)
    disposition_status, disposition =
        _header_fields(fetch.content_disposition)
    return Dict(
        "release_id" => fetch.release_id,
        "workbook_id" => fetch.workbook_id,
        "reference_period" => fetch.reference_period,
        "estimate_label" => fetch.estimate_label,
        "archive_label_url_component" =>
            fetch.archive_label_url_component,
        "archive_directory_id" => fetch.archive_directory_id,
        "hmi_id" => 7,
        "publication_variant" => "published_main",
        "section_id" => fetch.section_id,
        "filename" => fetch.filename,
        "file_format" => fetch.file_format,
        "identity_status" =>
            "EXACT_URL_PATH_FILENAME_SECTION_PROFILE_AND_BYTES_BOUND",
        "raw_artifact_path" => fetch.raw_artifact_path,
        "storage_encoding" => fetch.storage_encoding,
        "raw_sha256" => raw_sha256,
        "raw_bytes" => length(fetch.raw_bytes),
        "container_signature" => signature,
        "acquisition_started_at_utc" =>
            timestamp_text(fetch.acquisition_started_at_utc),
        "response_headers_at_utc" =>
            timestamp_text(fetch.response_headers_at_utc),
        "acquisition_completed_at_utc" =>
            timestamp_text(fetch.acquisition_completed_at_utc),
        "retrieval_observation_scope" =>
            "PRESENT_DAY_RETRIEVAL_TIMES_NOT_HISTORICAL_RELEASE_AVAILABILITY",
        "method" => "GET",
        "requested_url" => fetch.requested_url,
        "effective_url" => fetch.effective_url,
        "status_code" => fetch.status_code,
        "redirect_count" => fetch.redirect_count,
        "content_type" => fetch.content_type,
        "content_length_header_status" => content_length_status,
        "content_length_header" => content_length,
        "etag_status" => etag_status,
        "etag" => etag,
        "last_modified_status" => last_modified_status,
        "last_modified" => last_modified,
        "content_disposition_status" => disposition_status,
        "content_disposition" => disposition,
    )
end

"""
    build_receipt(; fetched_workbooks, profile_artifact_path,
                  content_fingerprint_artifact_path, base_dir, ...)

Construct and validate a receipt dictionary from exactly two fetched workbook
observations and exact adjacent semantic artifacts. The function does not
write files. A live driver must atomically persist the two raw artifacts and
receipt, then call `verify_local_raw_files` or `validate_receipt_file`.
"""
function build_receipt(;
        receipt_id,
        transaction_id,
        observer_id,
        capture_agent,
        capture_agent_version,
        fetched_workbooks,
        profile_artifact_path,
        content_fingerprint_artifact_path,
        base_dir,
        max_pair_span_seconds = 300,
        scope = PRODUCTION_SCOPE,
        allow_synthetic = false,
        audit = BEANIPAMappingAudit.load_mapping_audit(),
    )
    length(fetched_workbooks) == 2 ||
        fail("fetched_workbooks", "must contain exactly two workbooks")
    fetches = sort!(collect(fetched_workbooks); by = fetch -> fetch.section_id)
    [fetch.section_id for fetch in fetches] == ["1", "2"] ||
        fail("fetched_workbooks", "must contain Sections 1 and 2")
    profile_path = _relative_file(
        base_dir,
        profile_artifact_path,
        "profile_artifact_path",
    )
    profile_loaded = _strict_toml_file(profile_path, "target profile file")
    profile = validate_target_profile(
        profile_loaded.document;
        allow_synthetic = allow_synthetic,
        audit = audit,
    )
    content_fingerprint_identity = _content_fingerprint_identity(
        base_dir,
        content_fingerprint_artifact_path,
    )
    pair_started =
        minimum(fetch.acquisition_started_at_utc for fetch in fetches)
    pair_completed =
        maximum(fetch.acquisition_completed_at_utc for fetch in fetches)
    pair_started_at_utc = timestamp_text(pair_started)
    pair_completed_at_utc = timestamp_text(pair_completed)
    serialized_pair_started = expect_timestamp(
        pair_started_at_utc,
        "capture.pair_started_at_utc",
    )
    serialized_pair_completed = expect_timestamp(
        pair_completed_at_utc,
        "capture.pair_completed_at_utc",
    )
    observed_span = div(
        Dates.value(serialized_pair_completed - serialized_pair_started),
        1000,
    )
    records = [_fetch_record(fetch) for fetch in fetches]
    receipt = Dict(
        "artifact" => Dict(
            "schema_version" => RECEIPT_SCHEMA,
            "receipt_id" => String(receipt_id),
            "scope" => String(scope),
            "state" =>
                scope == PRODUCTION_SCOPE ? PRODUCTION_STATE :
                SYNTHETIC_STATE,
            "canonicalization" => CANONICALIZATION,
            "digest_algorithm" => "sha256",
            "content_sha256" => repeat("0", 64),
            "immutable_receipt" => true,
            "present_day_acquisition_observed" => true,
            "historical_release_availability_verified" => false,
            "release_event_timestamp_verified" => false,
            "first_state_verified" => false,
            "origin_admissible" => false,
            "inventory_registered" => false,
            "ready" => false,
        ),
        "capture" => Dict(
            "transaction_id" => String(transaction_id),
            "observer_id" => String(observer_id),
            "capture_agent" => String(capture_agent),
            "capture_agent_version" => String(capture_agent_version),
            "pair_started_at_utc" => pair_started_at_utc,
            "pair_completed_at_utc" => pair_completed_at_utc,
            "max_pair_span_seconds" => Int(max_pair_span_seconds),
            "observed_pair_span_seconds" => observed_span,
            "atomicity_policy" =>
                "ALL_OR_NOTHING_SECTION_1_AND_2_SAME_RELEASE_TRANSACTION",
            "atomic_pair_complete" => true,
            "acquisition_clock_basis" =>
                "CAPTURE_HOST_UTC_CLOCK_OBSERVATION_ONLY",
        ),
        "semantic_linkage" => Dict(
            "profile_artifact_path" => String(profile_artifact_path),
            "profile_file_sha256" => profile_loaded.sha256,
            "profile_content_sha256" => profile.content_sha256,
            "source_mapping_audit_file_sha256" =>
                profile.source_mapping_audit_file_sha256,
            "profile_id" => profile.profile_id,
            "content_fingerprint_artifact_path" =>
                String(content_fingerprint_artifact_path),
            "content_fingerprint_file_sha256" =>
                content_fingerprint_identity.file_sha256,
            "content_fingerprint_schema_version" =>
                content_fingerprint_identity.schema_version,
            "content_fingerprint_parser_sha256" =>
                content_fingerprint_identity.parser_sha256,
            "linked_target_ids" => profile.target_ids,
            "linkage_basis" =>
                "EXACT_PROFILE_AND_CONTENT_FINGERPRINT_FILES_RAW_SHA_URL_WORKBOOK_IDS_AND_TARGET_FINGERPRINTS",
            "linkage_status" => "EXACTLY_LINKED_NON_ADMITTING",
            "historical_availability_inferred" => false,
            "origin_admission_inferred" => false,
        ),
        "workbooks" => records,
    )
    stamp_content_sha256!(receipt)
    overrides = Dict(
        fetch.raw_artifact_path => fetch.raw_bytes for fetch in fetches
    )
    _validate_receipt(
        receipt,
        base_dir;
        allow_synthetic = allow_synthetic,
        audit = audit,
        raw_overrides = overrides,
    )
    return receipt
end

"""
    validate_receipt_set(paths; allow_synthetic=false)

Validate multiple receipts and reject duplicate receipt/transaction IDs,
duplicate acquisition observations, or reuse of the same exact bytes under
conflicting workbook/profile identities.
"""
function validate_receipt_set(
        paths;
        allow_synthetic = false,
        audit = BEANIPAMappingAudit.load_mapping_audit(),
    )
    isempty(paths) && fail("receipt set", "must not be empty")
    results = [
        validate_receipt_file(
                path;
                allow_synthetic = allow_synthetic,
                audit = audit,
            )
            for path in paths
    ]
    receipt_ids = Set{String}()
    transaction_ids = Set{String}()
    observation_keys = Set{Tuple}()
    raw_identities = Dict{String, Tuple}()
    for result in results
        result.receipt_id in receipt_ids &&
            fail("receipt set", "duplicates receipt_id $(result.receipt_id)")
        push!(receipt_ids, result.receipt_id)
        result.transaction_id in transaction_ids &&
            fail(
            "receipt set",
            "duplicates transaction_id $(result.transaction_id)",
        )
        push!(transaction_ids, result.transaction_id)
        observation_key = (
            result.release_id,
            result.pair_started,
            result.pair_completed,
        )
        observation_key in observation_keys &&
            fail("receipt set", "duplicates an atomic acquisition observation")
        push!(observation_keys, observation_key)
        for workbook in result.workbooks
            identity = (
                workbook.release_id,
                workbook.workbook_id,
                workbook.effective_url,
                result.profile_content_sha256,
                result.content_fingerprint_file_sha256,
            )
            if haskey(raw_identities, workbook.raw_sha256)
                raw_identities[workbook.raw_sha256] == identity ||
                    fail(
                    "receipt set",
                    "raw SHA $(workbook.raw_sha256) has conflicting identities",
                )
            else
                raw_identities[workbook.raw_sha256] = identity
            end
        end
    end
    return results
end

end
