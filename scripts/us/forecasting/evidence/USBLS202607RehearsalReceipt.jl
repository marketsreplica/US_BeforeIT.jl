module USBLS202607RehearsalReceipt

using Dates
using JSON
using SHA
using TOML

export DEFAULT_PROSPECTIVE_CONTRACT_PATH,
    EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256,
    RehearsalReceiptError,
    computed_receipt_sha256,
    stamp_receipt_sha256!,
    validate_rehearsal_receipt_file

const DEFAULT_PROSPECTIVE_CONTRACT_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "vintages",
        "prospective",
        "prospective_2026q3_contract_v2.toml",
    ),
)
const EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256 =
    "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
const EXPECTED_PROSPECTIVE_CONTRACT_CONTENT_SHA256 =
    "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
const RECEIPT_SCHEMA = "beforeit-us-bls-employment-rehearsal-receipt.v1"
const RECEIPT_SCOPE =
    "BLS_2026_07_CAPTURE_REHEARSAL_LOCAL_INTEGRITY_ONLY"
const CANONICALIZATION =
    "sorted_typed_v1_excluding_artifact_content_sha256"
const EVENT_ID = "bls_employment_situation_2026_07"
const EVENT_START = DateTime(2026, 8, 7, 12, 30)
const EVENT_DEADLINE = DateTime(2026, 8, 7, 12, 45)
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const TIMESTAMP_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
const NUMBER_PATTERN = r"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$"
const COPY_IDS = ["replica-a", "replica-b"]
const RESPONSE_HEADER_ALLOWLIST = Set(
    [
        "age",
        "cache-control",
        "content-length",
        "content-type",
        "date",
        "etag",
        "expires",
        "last-modified",
        "vary",
        "x-cache",
    ],
)
const API_WITH_NEWS_MODE =
    "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_PLUS_NEWS_BYTES"
const API_FALLBACK_MODE =
    "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK"
const API_REQUEST_BODY =
"""{"seriesid":["CES0000000001","LNS14000000"],"startyear":"2026","endyear":"2026"}"""
const RECEIPT_BLOCKERS = [
    "API_HOST_NOT_PRODUCTION_CONTRACT_ALLOWLISTED",
    "API_RESPONSE_IS_HISTORY_AS_KNOWN_AT_CAPTURE_ONLY",
    "BLS_DAILY_API_QUOTA_REMAINDER_NOT_ATTESTED",
    "CAPTURE_AGENT_SOURCE_NOT_EXTERNALLY_ATTESTED",
    "DURABLE_STORAGE_NOT_EXTERNALLY_ATTESTED",
    "EXTERNAL_TIMESTAMP_NOT_VERIFIED",
    "PRODUCTION_PROSPECTIVE_VERIFIER_NOT_ACTIVATED",
    "REHEARSAL_EVENT_NOT_REQUIRED_FOR_COMPLETE_ORIGIN",
    "SOURCE_TRANSPORT_NOT_INDEPENDENTLY_ATTESTED",
]

const EXPECTED_OBJECTS = Dict(
    "employment_situation_release_html" => (
        role = "release_news_file",
        requested_url =
            "https://www.bls.gov/news.release/empsit.nr0.htm",
        media_type = "text/html",
        extension = "html",
        http_method = "GET",
        request_body = "NOT_APPLICABLE",
    ),
    "employment_situation_release_pdf" => (
        role = "release_news_pdf_opaque_signature_only",
        requested_url =
            "https://www.bls.gov/news.release/pdf/empsit.pdf",
        media_type = "application/pdf",
        extension = "pdf",
        http_method = "GET",
        request_body = "NOT_APPLICABLE",
    ),
    "bls_v2_endpoint_unregistered_response" => (
        role =
            "v2_endpoint_unregistered_v1_compatible_history_as_known_at_capture",
        requested_url =
            "https://api.bls.gov/publicAPI/v2/timeseries/data/",
        media_type = "application/json",
        extension = "json",
        http_method = "POST",
        request_body = API_REQUEST_BODY,
    ),
)

const ROOT_KEYS = Set(
    [
        "artifact",
        "contract_binding",
        "event",
        "capture",
        "attempts",
        "attempt_objects",
        "objects",
        "fingerprint",
        "storage",
        "attestation",
        "disposition",
    ],
)
const ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "receipt_id",
        "scope",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const CONTRACT_BINDING_KEYS = Set(
    [
        "contract_id",
        "contract_file_sha256",
        "contract_content_sha256",
        "event_id",
    ],
)
const EVENT_KEYS = Set(
    [
        "source_id",
        "reference_period",
        "scheduled_timestamp_utc",
        "capture_not_before_utc",
        "capture_deadline_utc",
        "event_purpose",
        "required_for_complete_origin",
    ],
)
const CAPTURE_KEYS = Set(
    [
        "transaction_id",
        "observer_id",
        "capture_agent",
        "capture_agent_version",
        "capture_agent_source_sha256",
        "receipt_verifier_source_sha256",
        "source_revision",
        "capture_started_at_utc",
        "capture_completed_at_utc",
        "maximum_span_seconds",
        "observed_span_seconds",
        "clock_basis",
        "acquisition_mode",
        "api_attempt_count",
        "accepted_api_attempt_number",
    ],
)
const ATTEMPT_KEYS = Set(
    [
        "attempt_number",
        "object_id",
        "attempted_at_utc",
        "status_code",
        "response_sha256",
        "outcome",
        "detail",
        "accepted",
    ],
)
const ATTEMPT_OBJECT_KEYS = Set(
    [
        "raw_sha256",
        "raw_byte_count",
        "primary_path",
        "replica_path",
    ],
)
const OBJECT_KEYS = Set(
    [
        "object_id",
        "role",
        "requested_url",
        "effective_url",
        "http_method",
        "request_body",
        "request_body_sha256",
        "status_code",
        "content_type",
        "response_headers",
        "acquisition_started_at_utc",
        "response_metadata_observed_at_utc",
        "acquisition_completed_at_utc",
        "raw_sha256",
        "raw_byte_count",
        "primary_path",
        "replica_path",
    ],
)
const FINGERPRINT_KEYS = Set(
    [
        "reference_period",
        "release_html_marker",
        "ces_series_id",
        "ces_year",
        "ces_period",
        "ces_value",
        "cps_series_id",
        "cps_year",
        "cps_period",
        "cps_value",
    ],
)
const STORAGE_KEYS = Set(
    [
        "policy",
        "copy_ids",
        "minimum_local_copy_count",
        "receipt_replica_required",
        "external_durable_storage_attestation_status",
    ],
)
const ATTESTATION_KEYS = Set(
    [
        "capture_clock_attestation_status",
        "source_transport_attestation_status",
        "external_timestamp_attestation_status",
        "production_prospective_verifier_status",
        "cryptographic_signoff_status",
    ],
)
const DISPOSITION_KEYS = Set(
    [
        "rehearsal_only",
        "origin_evidence",
        "origin_admissible",
        "ready",
        "inventory_mutation_authorized",
        "accuracy_evaluation_allowed",
    ],
)

struct RehearsalReceiptError <: Exception
    message::String
end

Base.showerror(io::IO, error::RehearsalReceiptError) =
    print(io, error.message)

fail(location, message) =
    throw(RehearsalReceiptError("$location: $message"))

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    actual == expected ||
        fail(
        location,
        "keys differ; missing=$(sort!(collect(setdiff(expected, actual)))) " *
            "extra=$(sort!(collect(setdiff(actual, expected))))",
    )
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
    occursin(IDENTIFIER_PATTERN, text) ||
        fail(location, "must be a stable identifier")
    return text
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be a lowercase SHA-256")
    return text
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function expect_int(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    number = Int(value)
    number >= minimum || fail(location, "must be at least $minimum")
    return number
end

function expect_timestamp(value, location)
    text = expect_string(value, location)
    occursin(TIMESTAMP_PATTERN, text) ||
        fail(location, "must use RFC3339 UTC at second precision")
    timestamp = try
        DateTime(chop(text; tail = 1), TIMESTAMP_FORMAT)
    catch
        fail(location, "must be a valid UTC timestamp")
    end
    Dates.format(timestamp, TIMESTAMP_FORMAT) * "Z" == text ||
        fail(location, "must be canonical")
    return timestamp
end

function expect_string_array(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    result = [
        expect_string(item, "$location[$index]")
            for (index, item) in enumerate(value)
    ]
    length(result) == length(unique(result)) ||
        fail(location, "must not contain duplicates")
    return result
end

function validate_response_headers(value, declared_content_type, location)
    headers = expect_string_array(value, location)
    isempty(headers) && fail(location, "must not be empty")
    parsed = Dict{String, String}()
    for (index, header) in enumerate(headers)
        occursin('\n', header) &&
            fail("$location[$index]", "must not contain a line break")
        matched = match(r"^([a-z0-9-]+): (.+)$", header)
        matched === nothing &&
            fail(
            "$location[$index]",
            "must use normalized lowercase-name header syntax",
        )
        name, header_value = String.(matched.captures)
        name in RESPONSE_HEADER_ALLOWLIST ||
            fail("$location[$index]", "header is not in the evidence allowlist")
        haskey(parsed, name) &&
            fail("$location[$index]", "duplicate header name")
        parsed[name] = header_value
    end
    haskey(parsed, "content-type") ||
        fail(location, "must retain content-type")
    lowercase(parsed["content-type"]) == lowercase(declared_content_type) ||
        fail(location, "content-type does not match the declared metadata")
    haskey(parsed, "date") ||
        fail(location, "must retain the server Date header")
    server_date = try
        DateTime(
            parsed["date"],
            DateFormat("e, dd u yyyy HH:MM:SS \\G\\M\\T"),
        )
    catch
        fail(location, "Date header must be a valid IMF-fixdate")
    end
    startswith(parsed["date"], dayabbr(server_date) * ",") ||
        fail(location, "Date header weekday does not match its date")
    Dates.format(
        server_date,
        DateFormat("e, dd u yyyy HH:MM:SS \\G\\M\\T"),
    ) == parsed["date"] ||
        fail(location, "Date header must use canonical IMF-fixdate spelling")
    parsed["__parsed_server_date"] =
        Dates.format(server_date, TIMESTAMP_FORMAT) * "Z"
    return parsed
end

function _media_type_token(value)
    text = lowercase(expect_string(value, "content type"))
    return strip(first(split(text, ';'; limit = 2)))
end

function _assert_distinct_file_identities(paths, location)
    identities = [(stat(path).device, stat(path).inode) for path in paths]
    length(identities) == length(unique(identities)) ||
        fail(location, "declared copies must not be hardlinks to one file")
    return nothing
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
    else
        fail(
            "canonicalization",
            "unsupported value of type $(typeof(value))",
        )
    end
    return io
end

function computed_receipt_sha256(receipt)
    copy = deepcopy(expect_table(receipt, "receipt"))
    artifact =
        expect_table(get(copy, "artifact", nothing), "receipt.artifact")
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, copy)
    return bytes2hex(sha256(take!(io)))
end

function stamp_receipt_sha256!(receipt)
    root = expect_table(receipt, "receipt")
    artifact =
        expect_table(get(root, "artifact", nothing), "receipt.artifact")
    artifact["content_sha256"] = computed_receipt_sha256(root)
    return root
end

sha256_hex(bytes) = bytes2hex(sha256(bytes))

receipt_verifier_source_sha256() = sha256_hex(read(@__FILE__))

capture_agent_source_sha256() =
    sha256_hex(read(joinpath(@__DIR__, "USBLS202607RehearsalCapture.jl")))

function expect_source_revision(value, location)
    text = expect_string(value, location)
    text == "UNVERIFIED_LOCAL_WORKTREE" ||
        occursin(r"^[0-9a-f]{40}$", text) ||
        fail(location, "must be a lowercase Git commit or local-worktree sentinel")
    return text
end

function _parse_toml_bytes(bytes, location)
    isvalid(String, bytes) || fail(location, "must contain valid UTF-8")
    return try
        TOML.parse(String(copy(bytes)))
    catch error
        fail(location, "could not parse TOML: $(sprint(showerror, error))")
    end
end

function _validate_contract(contract_path)
    path = abspath(String(contract_path))
    isfile(path) || fail("prospective contract", "file does not exist")
    islink(path) &&
        fail("prospective contract", "must not be a symbolic link")
    bytes = read(path)
    digest = sha256_hex(bytes)
    digest == EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256 ||
        fail(
        "prospective contract",
        "raw SHA-256 does not match the audited v6 contract",
    )
    contract = _parse_toml_bytes(bytes, "prospective contract")
    artifact = expect_table(
        get(contract, "artifact", nothing),
        "prospective contract.artifact",
    )
    artifact["contract_id"] ==
        "beforeit-us-prospective-2026q3-acquisition.v2" ||
        fail("prospective contract.artifact.contract_id", "contract mismatch")
    artifact["content_sha256"] ==
        EXPECTED_PROSPECTIVE_CONTRACT_CONTENT_SHA256 ||
        fail(
        "prospective contract.artifact.content_sha256",
        "content digest mismatch",
    )
    events = get(contract, "fixed_events", nothing)
    events isa AbstractVector ||
        fail("prospective contract.fixed_events", "must be an array")
    matches = [event for event in events if get(event, "event_id", nothing) == EVENT_ID]
    length(matches) == 1 ||
        fail("prospective contract.fixed_events", "event must occur exactly once")
    event = only(matches)
    expected = Dict(
        "source_id" => "bls_employment_situation",
        "reference_period" => "2026-07",
        "scheduled_timestamp_utc" => "2026-08-07T12:30:00Z",
        "capture_not_before_utc" => "2026-08-07T12:30:00Z",
        "capture_deadline_utc" => "2026-08-07T12:45:00Z",
        "event_purpose" => "capture_rehearsal",
        "required_for_complete_origin" => false,
        "capture_status" => "PLANNED_NOT_CAPTURED",
        "immutable_receipt_status" => "MISSING",
        "receipt_count" => 0,
        "origin_eligible" => false,
    )
    for (field, value) in expected
        get(event, field, nothing) == value ||
            fail(
            "prospective contract.$EVENT_ID.$field",
            "does not match the audited rehearsal boundary",
        )
    end
    return (; digest, contract, event)
end

function _validate_relative_path(value, location)
    path = expect_string(value, location)
    isabspath(path) && fail(location, "must be relative")
    occursin('\\', path) &&
        fail(location, "must use forward-slash separators")
    normpath(path) == path || fail(location, "must be normalized")
    components = split(path, '/')
    any(component -> component in ("", ".", ".."), components) &&
        fail(location, "must not contain empty, dot, or parent components")
    return path
end

function _inside_root(path, root)
    relative = relpath(path, root)
    return relative != ".." &&
        !startswith(relative, "..$(Base.Filesystem.path_separator)")
end

function _resolve_regular_bytes(root_directory, declared_path, location)
    relative = _validate_relative_path(declared_path, location)
    root = realpath(root_directory)
    candidate = joinpath(root, relative)
    isfile(candidate) || fail(location, "file does not exist")
    current = candidate
    while current != root
        islink(current) && fail(location, "must not traverse a symbolic link")
        current = dirname(current)
    end
    resolved = realpath(candidate)
    _inside_root(resolved, root) ||
        fail(location, "resolves outside the receipt bundle")
    isfile(resolved) || fail(location, "must resolve to a regular file")
    return read(resolved)
end

function _validate_object(
        item,
        index,
        bundle_directory,
        capture_start,
        capture_end,
    )
    location = "receipt.objects[$index]"
    row = expect_exact_keys(item, OBJECT_KEYS, location)
    object_id = expect_identifier(row["object_id"], "$location.object_id")
    haskey(EXPECTED_OBJECTS, object_id) ||
        fail("$location.object_id", "unknown rehearsal object")
    expected = EXPECTED_OBJECTS[object_id]
    row["role"] == expected.role ||
        fail("$location.role", "role mismatch")
    row["requested_url"] == expected.requested_url ||
        fail("$location.requested_url", "official locator mismatch")
    row["effective_url"] == expected.requested_url ||
        fail("$location.effective_url", "unexpected redirect or locator")
    row["http_method"] == expected.http_method ||
        fail("$location.http_method", "method mismatch")
    row["request_body"] == expected.request_body ||
        fail("$location.request_body", "request body mismatch")
    expected_request_hash =
        expected.http_method == "POST" ?
        sha256_hex(codeunits(expected.request_body)) : "NOT_APPLICABLE"
    row["request_body_sha256"] == expected_request_hash ||
        fail("$location.request_body_sha256", "request body hash mismatch")
    expect_int(row["status_code"], "$location.status_code") == 200 ||
        fail("$location.status_code", "must be HTTP 200")
    content_type = expect_string(row["content_type"], "$location.content_type")
    _media_type_token(content_type) == expected.media_type ||
        fail("$location.content_type", "media type mismatch")
    parsed_headers = validate_response_headers(
        row["response_headers"],
        content_type,
        "$location.response_headers",
    )

    started = expect_timestamp(
        row["acquisition_started_at_utc"],
        "$location.acquisition_started_at_utc",
    )
    metadata_observed = expect_timestamp(
        row["response_metadata_observed_at_utc"],
        "$location.response_metadata_observed_at_utc",
    )
    completed = expect_timestamp(
        row["acquisition_completed_at_utc"],
        "$location.acquisition_completed_at_utc",
    )
    capture_start <= started <= metadata_observed <= completed <= capture_end ||
        fail(location, "object timestamps must be ordered inside capture")
    server_date = expect_timestamp(
        parsed_headers["__parsed_server_date"],
        "$location.response_headers.date",
    )
    started - Minute(5) <= server_date <= completed + Minute(5) ||
        fail(
        "$location.response_headers.date",
        "server date must be consistent with host observations",
    )

    digest = expect_hash(row["raw_sha256"], "$location.raw_sha256")
    byte_count =
        expect_int(row["raw_byte_count"], "$location.raw_byte_count"; minimum = 1)
    primary_path =
        _validate_relative_path(row["primary_path"], "$location.primary_path")
    replica_path =
        _validate_relative_path(row["replica_path"], "$location.replica_path")
    primary_path != replica_path ||
        fail(location, "replica paths must be distinct")
    primary_parts = split(primary_path, '/')
    replica_parts = split(replica_path, '/')
    primary_parts[1] == COPY_IDS[1] ||
        fail("$location.primary_path", "must use $(COPY_IDS[1])")
    replica_parts[1] == COPY_IDS[2] ||
        fail("$location.replica_path", "must use $(COPY_IDS[2])")
    expected_name = "raw-sha256-$digest.$(expected.extension)"
    basename(primary_path) == expected_name ||
        fail("$location.primary_path", "must be content addressed")
    basename(replica_path) == expected_name ||
        fail("$location.replica_path", "must be content addressed")

    primary_bytes = _resolve_regular_bytes(
        bundle_directory,
        primary_path,
        "$location.primary_path",
    )
    replica_bytes = _resolve_regular_bytes(
        bundle_directory,
        replica_path,
        "$location.replica_path",
    )
    primary_bytes == replica_bytes ||
        fail(location, "local replicas are not byte identical")
    _assert_distinct_file_identities(
        [
            realpath(joinpath(bundle_directory, primary_path)),
            realpath(joinpath(bundle_directory, replica_path)),
        ],
        location,
    )
    length(primary_bytes) == byte_count ||
        fail("$location.raw_byte_count", "does not match local bytes")
    sha256_hex(primary_bytes) == digest ||
        fail("$location.raw_sha256", "does not match local bytes")
    if expected.extension == "pdf"
        length(primary_bytes) >= 5 ||
            fail(location, "PDF response is too short")
        primary_bytes[1:5] == Vector{UInt8}(codeunits("%PDF-")) ||
            fail(location, "PDF response has no PDF signature")
    end
    return (;
        object_id,
        bytes = primary_bytes,
        started,
        metadata_observed,
        completed,
        digest,
        primary_path,
        replica_path,
    )
end

function _validate_numeric_text(value, location)
    text = expect_string(value, location)
    occursin(NUMBER_PATTERN, text) ||
        fail(location, "value must be a canonical finite decimal")
    number = try
        parse(Float64, text)
    catch
        fail(location, "value must be numeric")
    end
    isfinite(number) || fail(location, "value must be finite")
    return text
end

function _parse_api_values(bytes)
    isvalid(String, bytes) ||
        fail("BLS API response", "must contain valid UTF-8")
    document = try
        JSON.parse(String(copy(bytes)))
    catch error
        fail(
            "BLS API response",
            "must be valid JSON ($(sprint(showerror, error)))",
        )
    end
    root = expect_table(document, "BLS API response")
    get(root, "status", nothing) == "REQUEST_SUCCEEDED" ||
        fail("BLS API response.status", "request did not succeed")
    results =
        expect_table(get(root, "Results", nothing), "BLS API response.Results")
    series = get(results, "series", nothing)
    series isa AbstractVector ||
        fail("BLS API response.Results.series", "must be an array")
    expected_ids = Set(["CES0000000001", "LNS14000000"])
    length(series) == length(expected_ids) ||
        fail(
        "BLS API response.Results.series",
        "must contain exactly the two requested series",
    )
    values = Dict{String, String}()
    for (index, item) in enumerate(series)
        location = "BLS API response.Results.series[$index]"
        row = expect_table(item, location)
        series_id = expect_string(get(row, "seriesID", nothing), "$location.seriesID")
        series_id in expected_ids ||
            fail("$location.seriesID", "unexpected series")
        haskey(values, series_id) &&
            fail("$location.seriesID", "duplicate series")
        data = get(row, "data", nothing)
        data isa AbstractVector || fail("$location.data", "must be an array")
        matches = [
            observation for observation in data if
                get(observation, "year", nothing) == "2026" &&
                get(observation, "period", nothing) == "M07"
        ]
        length(matches) == 1 ||
            fail(
            "$location.data",
            "must contain exactly one July 2026 observation",
        )
        observation = expect_table(only(matches), "$location.data.M07")
        values[series_id] = _validate_numeric_text(
            get(observation, "value", nothing),
            "$location.data.M07.value",
        )
    end
    Set(keys(values)) == expected_ids ||
        fail("BLS API response.Results.series", "series set mismatch")
    return values
end

function _expected_series_without_complete_m07(bytes)
    isvalid(String, bytes) || return false
    document = try
        JSON.parse(String(copy(bytes)))
    catch
        return false
    end
    document isa AbstractDict || return false
    get(document, "status", nothing) == "REQUEST_SUCCEEDED" ||
        return false
    results = get(document, "Results", nothing)
    results isa AbstractDict || return false
    series = get(results, "series", nothing)
    series isa AbstractVector || return false
    length(series) == 2 || return false

    seen = Set{String}()
    missing = false
    for item in series
        item isa AbstractDict || return false
        series_id = get(item, "seriesID", nothing)
        series_id isa AbstractString || return false
        series_id = String(series_id)
        series_id in ("CES0000000001", "LNS14000000") || return false
        series_id in seen && return false
        push!(seen, series_id)
        data = get(item, "data", nothing)
        data isa AbstractVector || return false
        matches = [
            observation for observation in data if
                observation isa AbstractDict &&
                get(observation, "year", nothing) == "2026" &&
                get(observation, "period", nothing) == "M07"
        ]
        length(matches) <= 1 || return false
        if isempty(matches)
            missing = true
        else
            value = get(only(matches), "value", nothing)
            try
                _validate_numeric_text(value, "BLS API M07 value")
            catch error
                error isa RehearsalReceiptError || rethrow()
                return false
            end
        end
    end
    return seen == Set(["CES0000000001", "LNS14000000"]) && missing
end

function _normalized_html_text(bytes)
    isvalid(String, bytes) ||
        fail("release HTML", "must contain valid UTF-8")
    text = String(copy(bytes))
    text = replace(
        text,
        "&mdash;" => "-",
        "&ndash;" => "-",
        "&#8212;" => "-",
        '—' => '-',
        '–' => '-',
    )
    text = replace(text, r"<[^>]*>" => " ")
    return uppercase(strip(replace(text, r"\s+" => " ")))
end

function _validate_fingerprint(fingerprint, object_lookup, acquisition_mode)
    row = expect_exact_keys(
        fingerprint,
        FINGERPRINT_KEYS,
        "receipt.fingerprint",
    )
    row["reference_period"] == "2026-07" ||
        fail("receipt.fingerprint.reference_period", "period mismatch")
    marker = expect_string(
        row["release_html_marker"],
        "receipt.fingerprint.release_html_marker",
    )
    if acquisition_mode == API_WITH_NEWS_MODE
        marker == "Employment Situation Summary - 2026 M07 Results" ||
            fail("receipt.fingerprint.release_html_marker", "marker mismatch")
        html_bytes =
            object_lookup["employment_situation_release_html"].bytes
        html = String(copy(html_bytes))
        occursin(marker, html) ||
            fail("release HTML", "does not contain the pinned page title")
        normalized = _normalized_html_text(html_bytes)
        occursin("THE EMPLOYMENT SITUATION - JULY 2026", normalized) ||
            fail("release HTML", "does not identify the July 2026 release")
        occursin("EMBARGOED UNTIL", normalized) ||
            fail("release HTML", "does not contain the embargo statement")
        occursin("AUGUST 7, 2026", normalized) ||
            fail("release HTML", "does not contain the audited release date")
        occursin("TOTAL NONFARM", normalized) ||
            fail("release HTML", "does not contain the CES target label")
        occursin("UNEMPLOYMENT RATE", normalized) ||
            fail("release HTML", "does not contain the CPS target label")
    else
        marker == "NOT_CAPTURED_API_ONLY_FALLBACK" ||
            fail(
            "receipt.fingerprint.release_html_marker",
            "API-only fallback must record news-byte absence",
        )
    end

    api_values =
        _parse_api_values(
        object_lookup["bls_v2_endpoint_unregistered_response"].bytes,
    )
    expected_series = (
        (prefix = "ces", series_id = "CES0000000001"),
        (prefix = "cps", series_id = "LNS14000000"),
    )
    values = Dict{String, String}()
    for expected in expected_series
        prefix = expected.prefix
        row["$(prefix)_series_id"] == expected.series_id ||
            fail(
            "receipt.fingerprint.$(prefix)_series_id",
            "series mismatch",
        )
        row["$(prefix)_year"] == "2026" ||
            fail("receipt.fingerprint.$(prefix)_year", "year mismatch")
        row["$(prefix)_period"] == "M07" ||
            fail("receipt.fingerprint.$(prefix)_period", "period mismatch")
        extracted = api_values[expected.series_id]
        claimed = expect_string(
            row["$(prefix)_value"],
            "receipt.fingerprint.$(prefix)_value",
        )
        claimed == extracted ||
            fail(
            "receipt.fingerprint.$(prefix)_value",
            "does not match the API response bytes",
        )
        values[prefix] = extracted
    end
    return values
end

function _validate_attempt_rows(
        attempts;
        ledger_location = "receipt.attempts",
        allow_empty = false,
    )
    attempts isa AbstractVector ||
        fail(ledger_location, "must be an array")
    !allow_empty && isempty(attempts) &&
        fail(ledger_location, "must contain at least one API attempt")
    length(attempts) <= 25 ||
        fail(ledger_location, "exceeds the per-invocation anonymous API cap")

    accepted_numbers = Int[]
    previous_timestamp = nothing
    hash_signatures = Dict{String, Tuple{Int, String, String}}()
    for (index, item) in enumerate(attempts)
        location = "$ledger_location[$index]"
        row = expect_exact_keys(item, ATTEMPT_KEYS, location)
        attempt_number =
            expect_int(row["attempt_number"], "$location.attempt_number"; minimum = 1)
        attempt_number == index ||
            fail("$location.attempt_number", "must be contiguous and ordered")
        row["object_id"] == "bls_v2_endpoint_unregistered_response" ||
            fail("$location.object_id", "must identify the canonical API request")
        attempted_at = expect_timestamp(
            row["attempted_at_utc"],
            "$location.attempted_at_utc",
        )
        EVENT_START <= attempted_at <= EVENT_DEADLINE ||
            fail("$location.attempted_at_utc", "must be inside the event window")
        previous_timestamp === nothing ||
            previous_timestamp <= attempted_at ||
            fail("$location.attempted_at_utc", "must be nondecreasing")
        previous_timestamp = attempted_at

        status_code =
            expect_int(row["status_code"], "$location.status_code"; minimum = 0)
        status_code == 0 || 100 <= status_code <= 599 ||
            fail("$location.status_code", "must be zero or an HTTP status")
        response_sha256 =
            expect_string(row["response_sha256"], "$location.response_sha256")
        outcome = expect_string(row["outcome"], "$location.outcome")
        detail = expect_string(row["detail"], "$location.detail")
        accepted = expect_bool(row["accepted"], "$location.accepted")
        if response_sha256 != "unavailable"
            signature = (status_code, outcome, detail)
            if haskey(hash_signatures, response_sha256)
                hash_signatures[response_sha256] == signature ||
                    fail(
                    "$location.response_sha256",
                    "same bytes cannot have inconsistent attempt semantics",
                )
            else
                hash_signatures[response_sha256] = signature
            end
        end

        if outcome == "REQUEST_FAILED"
            status_code == 0 ||
                fail("$location.status_code", "request failure must use zero")
            response_sha256 == "unavailable" ||
                fail(
                "$location.response_sha256",
                "request failure must use unavailable",
            )
            detail == "REQUEST_EXCEPTION" ||
                fail("$location.detail", "request failure detail mismatch")
            !accepted ||
                fail("$location.accepted", "request failure cannot be accepted")
        elseif outcome == "HTTP_NON_200"
            status_code != 0 && status_code != 200 ||
                fail("$location.status_code", "must identify a non-200 response")
            expect_hash(response_sha256, "$location.response_sha256")
            detail == "HTTP_$status_code" ||
                fail("$location.detail", "HTTP detail mismatch")
            !accepted ||
                fail("$location.accepted", "non-200 response cannot be accepted")
        elseif outcome == "M07_NOT_AVAILABLE"
            status_code == 200 ||
                fail("$location.status_code", "unavailable response must be HTTP 200")
            expect_hash(response_sha256, "$location.response_sha256")
            detail == "EXPECTED_SERIES_WITHOUT_COMPLETE_M07" ||
                fail("$location.detail", "unavailable-response detail mismatch")
            !accepted ||
                fail("$location.accepted", "unavailable response cannot be accepted")
        elseif outcome == "INVALID_API_RESPONSE"
            status_code == 200 ||
                fail("$location.status_code", "invalid response must be HTTP 200")
            expect_hash(response_sha256, "$location.response_sha256")
            detail == "CANONICAL_RESPONSE_VALIDATION_FAILED" ||
                fail("$location.detail", "invalid-response detail mismatch")
            !accepted ||
                fail("$location.accepted", "invalid response cannot be accepted")
        elseif outcome == "INVALID_API_RESPONSE_METADATA_REPORTED"
            status_code == 200 ||
                fail("$location.status_code", "invalid metadata must be HTTP 200")
            expect_hash(response_sha256, "$location.response_sha256")
            detail == "CAPTURE_AGENT_REPORTED_METADATA_VALIDATION_FAILED" ||
                fail("$location.detail", "invalid-metadata detail mismatch")
            !accepted ||
                fail("$location.accepted", "invalid metadata cannot be accepted")
        elseif outcome == "ACCEPTED_M07"
            status_code == 200 ||
                fail("$location.status_code", "accepted response must be HTTP 200")
            expect_hash(response_sha256, "$location.response_sha256")
            detail == "CES_AND_CPS_M07_PRESENT" ||
                fail("$location.detail", "accepted-response detail mismatch")
            accepted ||
                fail("$location.accepted", "accepted response must be marked true")
            push!(accepted_numbers, attempt_number)
        else
            fail("$location.outcome", "unsupported API attempt outcome")
        end
    end
    return accepted_numbers
end

function _validate_attempts(
        attempts,
        api_attempt_count,
        accepted_api_attempt_number,
        api_object,
    )
    accepted_numbers = _validate_attempt_rows(attempts)
    length(attempts) == api_attempt_count ||
        fail("receipt.capture.api_attempt_count", "does not match the ledger")
    accepted_numbers == [accepted_api_attempt_number] ||
        fail(
        "receipt.capture.accepted_api_attempt_number",
        "must identify the sole accepted attempt",
    )
    accepted_api_attempt_number == length(attempts) ||
        fail(
        "receipt.capture.accepted_api_attempt_number",
        "accepted attempt must be the final attempt",
    )
    accepted = attempts[accepted_api_attempt_number]
    accepted["response_sha256"] == api_object.digest ||
        fail(
        "receipt.attempts[$accepted_api_attempt_number].response_sha256",
        "does not match the installed API object",
    )
    any(
        row -> row["response_sha256"] == api_object.digest,
        attempts[1:(accepted_api_attempt_number - 1)],
    ) &&
        fail(
        "receipt.attempts",
        "accepted bytes cannot appear in a pre-acceptance attempt",
    )
    accepted_at = expect_timestamp(
        accepted["attempted_at_utc"],
        "receipt.attempts[$accepted_api_attempt_number].attempted_at_utc",
    )
    accepted_at <= api_object.started ||
        fail(
        "receipt.attempts[$accepted_api_attempt_number].attempted_at_utc",
        "must not follow the accepted API acquisition start",
    )
    return nothing
end

function _validate_attempt_objects(
        items,
        attempts,
        api_object,
        bundle_directory,
    )
    items isa AbstractVector ||
        fail("receipt.attempt_objects", "must be an array")
    external_digest = api_object === nothing ? nothing : api_object.digest
    expected_hashes = Set(
        row["response_sha256"] for row in attempts if
            row["response_sha256"] != "unavailable" &&
            row["response_sha256"] != external_digest
    )
    length(items) == length(expected_hashes) ||
        fail("receipt.attempt_objects", "object count mismatch")
    bytes_by_hash = Dict{String, Vector{UInt8}}()
    all_paths = String[]
    for (index, item) in enumerate(items)
        location = "receipt.attempt_objects[$index]"
        row = expect_exact_keys(item, ATTEMPT_OBJECT_KEYS, location)
        digest = expect_hash(row["raw_sha256"], "$location.raw_sha256")
        digest in expected_hashes ||
            fail("$location.raw_sha256", "is not referenced by the attempt ledger")
        haskey(bytes_by_hash, digest) &&
            fail("$location.raw_sha256", "duplicate attempt object")
        byte_count = expect_int(
            row["raw_byte_count"],
            "$location.raw_byte_count";
            minimum = 0,
        )
        primary_path =
            _validate_relative_path(row["primary_path"], "$location.primary_path")
        replica_path =
            _validate_relative_path(row["replica_path"], "$location.replica_path")
        primary_path != replica_path ||
            fail(location, "replica paths must be distinct")
        split(primary_path, '/')[1] == COPY_IDS[1] ||
            fail("$location.primary_path", "must use $(COPY_IDS[1])")
        split(replica_path, '/')[1] == COPY_IDS[2] ||
            fail("$location.replica_path", "must use $(COPY_IDS[2])")
        expected_name = "api-attempt-raw-sha256-$digest.bin"
        basename(primary_path) == expected_name ||
            fail("$location.primary_path", "must be content addressed")
        basename(replica_path) == expected_name ||
            fail("$location.replica_path", "must be content addressed")
        primary_bytes = _resolve_regular_bytes(
            bundle_directory,
            primary_path,
            "$location.primary_path",
        )
        replica_bytes = _resolve_regular_bytes(
            bundle_directory,
            replica_path,
            "$location.replica_path",
        )
        primary_bytes == replica_bytes ||
            fail(location, "local replicas are not byte identical")
        length(primary_bytes) == byte_count ||
            fail("$location.raw_byte_count", "does not match local bytes")
        sha256_hex(primary_bytes) == digest ||
            fail("$location.raw_sha256", "does not match local bytes")
        _assert_distinct_file_identities(
            [
                realpath(joinpath(bundle_directory, primary_path)),
                realpath(joinpath(bundle_directory, replica_path)),
            ],
            location,
        )
        append!(all_paths, [primary_path, replica_path])
        bytes_by_hash[digest] = primary_bytes
    end
    Set(keys(bytes_by_hash)) == expected_hashes ||
        fail("receipt.attempt_objects", "object hash set mismatch")
    length(all_paths) == length(unique(all_paths)) ||
        fail("receipt.attempt_objects", "paths must be unique")

    for (index, row) in enumerate(attempts)
        digest = row["response_sha256"]
        digest == "unavailable" && continue
        bytes =
            digest == external_digest ? api_object.bytes :
            bytes_by_hash[digest]
        if row["outcome"] == "ACCEPTED_M07"
            _parse_api_values(bytes)
        elseif row["outcome"] == "M07_NOT_AVAILABLE"
            _expected_series_without_complete_m07(bytes) ||
                fail(
                "receipt.attempts[$index].outcome",
                "does not match the retained response bytes",
            )
        elseif row["outcome"] == "INVALID_API_RESPONSE"
            invalid = try
                _parse_api_values(bytes)
                false
            catch error
                error isa RehearsalReceiptError || rethrow()
                !_expected_series_without_complete_m07(bytes)
            end
            invalid ||
                fail(
                "receipt.attempts[$index].outcome",
                "does not match the retained response bytes",
            )
        elseif row["outcome"] == "INVALID_API_RESPONSE_METADATA_REPORTED"
            _parse_api_values(bytes)
        end
    end
    return (; count = length(items), bytes_by_hash)
end

function _validate_receipt_document(
        receipt,
        bundle_directory,
        contract_path,
    )
    root = expect_exact_keys(receipt, ROOT_KEYS, "receipt")
    artifact =
        expect_exact_keys(root["artifact"], ARTIFACT_KEYS, "receipt.artifact")
    artifact["schema_version"] == RECEIPT_SCHEMA ||
        fail("receipt.artifact.schema_version", "schema mismatch")
    receipt_id =
        expect_identifier(artifact["receipt_id"], "receipt.artifact.receipt_id")
    artifact["scope"] == RECEIPT_SCOPE ||
        fail("receipt.artifact.scope", "scope mismatch")
    artifact["canonicalization"] == CANONICALIZATION ||
        fail("receipt.artifact.canonicalization", "canonicalization mismatch")
    artifact["digest_algorithm"] == "sha256" ||
        fail("receipt.artifact.digest_algorithm", "must be sha256")
    declared =
        expect_hash(artifact["content_sha256"], "receipt.artifact.content_sha256")
    declared == computed_receipt_sha256(root) ||
        fail("receipt.artifact.content_sha256", "content digest mismatch")

    contract = _validate_contract(contract_path)
    binding = expect_exact_keys(
        root["contract_binding"],
        CONTRACT_BINDING_KEYS,
        "receipt.contract_binding",
    )
    binding["contract_id"] ==
        "beforeit-us-prospective-2026q3-acquisition.v2" ||
        fail("receipt.contract_binding.contract_id", "contract mismatch")
    binding["contract_file_sha256"] == contract.digest ||
        fail(
        "receipt.contract_binding.contract_file_sha256",
        "raw contract binding mismatch",
    )
    binding["contract_content_sha256"] ==
        EXPECTED_PROSPECTIVE_CONTRACT_CONTENT_SHA256 ||
        fail(
        "receipt.contract_binding.contract_content_sha256",
        "semantic contract binding mismatch",
    )
    binding["event_id"] == EVENT_ID ||
        fail("receipt.contract_binding.event_id", "event mismatch")

    event = expect_exact_keys(root["event"], EVENT_KEYS, "receipt.event")
    expected_event = Dict(
        "source_id" => "bls_employment_situation",
        "reference_period" => "2026-07",
        "scheduled_timestamp_utc" => "2026-08-07T12:30:00Z",
        "capture_not_before_utc" => "2026-08-07T12:30:00Z",
        "capture_deadline_utc" => "2026-08-07T12:45:00Z",
        "event_purpose" => "capture_rehearsal",
        "required_for_complete_origin" => false,
    )
    event == expected_event ||
        fail("receipt.event", "does not match the audited fixed event")

    capture =
        expect_exact_keys(root["capture"], CAPTURE_KEYS, "receipt.capture")
    transaction_id = expect_identifier(
        capture["transaction_id"],
        "receipt.capture.transaction_id",
    )
    expect_identifier(capture["observer_id"], "receipt.capture.observer_id")
    capture["capture_agent"] == "beforeit-bls-employment-rehearsal" ||
        fail("receipt.capture.capture_agent", "capture agent mismatch")
    capture["capture_agent_version"] == "1.0.0" ||
        fail("receipt.capture.capture_agent_version", "version mismatch")
    capture["capture_agent_source_sha256"] ==
        capture_agent_source_sha256() ||
        fail(
        "receipt.capture.capture_agent_source_sha256",
        "does not match the local collector source",
    )
    capture["receipt_verifier_source_sha256"] ==
        receipt_verifier_source_sha256() ||
        fail(
        "receipt.capture.receipt_verifier_source_sha256",
        "does not match the local verifier source",
    )
    source_revision = expect_source_revision(
        capture["source_revision"],
        "receipt.capture.source_revision",
    )
    acquisition_mode = expect_string(
        capture["acquisition_mode"],
        "receipt.capture.acquisition_mode",
    )
    acquisition_mode in (API_WITH_NEWS_MODE, API_FALLBACK_MODE) ||
        fail(
        "receipt.capture.acquisition_mode",
        "unsupported rehearsal acquisition mode",
    )
    receipt_stage =
        acquisition_mode == API_WITH_NEWS_MODE ?
        "api-plus-news" : "api-only-checkpoint"
    receipt_id ==
        "bls-employment-situation-2026-07-rehearsal.$transaction_id.$receipt_stage" ||
        fail(
        "receipt.artifact.receipt_id",
        "must bind the transaction and capture stage",
    )
    capture["clock_basis"] == "CAPTURE_HOST_UTC_CLOCK_ONLY" ||
        fail("receipt.capture.clock_basis", "clock basis mismatch")
    api_attempt_count = expect_int(
        capture["api_attempt_count"],
        "receipt.capture.api_attempt_count";
        minimum = 1,
    )
    accepted_api_attempt_number = expect_int(
        capture["accepted_api_attempt_number"],
        "receipt.capture.accepted_api_attempt_number";
        minimum = 1,
    )
    capture_start = expect_timestamp(
        capture["capture_started_at_utc"],
        "receipt.capture.capture_started_at_utc",
    )
    capture_end = expect_timestamp(
        capture["capture_completed_at_utc"],
        "receipt.capture.capture_completed_at_utc",
    )
    EVENT_START <= capture_start <= capture_end <= EVENT_DEADLINE ||
        fail("receipt.capture", "capture is outside the fixed rehearsal window")
    maximum_span = expect_int(
        capture["maximum_span_seconds"],
        "receipt.capture.maximum_span_seconds";
        minimum = 1,
    )
    maximum_span == 900 ||
        fail("receipt.capture.maximum_span_seconds", "must remain 900")
    observed_span = div(Dates.value(capture_end - capture_start), 1000)
    expect_int(
        capture["observed_span_seconds"],
        "receipt.capture.observed_span_seconds";
        minimum = 0,
    ) == observed_span ||
        fail("receipt.capture.observed_span_seconds", "span mismatch")
    observed_span <= maximum_span ||
        fail("receipt.capture.observed_span_seconds", "exceeds maximum")

    objects = root["objects"]
    objects isa AbstractVector ||
        fail("receipt.objects", "must be an array")
    expected_object_ids =
        acquisition_mode == API_WITH_NEWS_MODE ?
        Set(
            [
                "employment_situation_release_html",
                "employment_situation_release_pdf",
                "bls_v2_endpoint_unregistered_response",
            ],
        ) : Set(["bls_v2_endpoint_unregistered_response"])
    length(objects) == length(expected_object_ids) ||
        fail(
        "receipt.objects",
        "object count does not match the acquisition mode",
    )
    validated = [
        _validate_object(
                object,
                index,
                bundle_directory,
                capture_start,
                capture_end,
            )
            for (index, object) in enumerate(objects)
    ]
    object_ids = [object.object_id for object in validated]
    length(object_ids) == length(unique(object_ids)) ||
        fail("receipt.objects", "object IDs must be unique")
    Set(object_ids) == expected_object_ids ||
        fail("receipt.objects", "object set mismatch")
    raw_hashes = [object.digest for object in validated]
    length(raw_hashes) == length(unique(raw_hashes)) ||
        fail("receipt.objects", "raw objects must have distinct bytes")
    all_paths = vcat(
        [object.primary_path for object in validated],
        [object.replica_path for object in validated],
    )
    length(all_paths) == length(unique(all_paths)) ||
        fail("receipt.objects", "all local paths must be distinct")
    first_attempt = expect_timestamp(
        root["attempts"][1]["attempted_at_utc"],
        "receipt.attempts[1].attempted_at_utc",
    )
    min(first_attempt, minimum(object.started for object in validated)) ==
        capture_start ||
        fail(
        "receipt.capture.capture_started_at_utc",
        "must equal the first bound API attempt or retained-object fetch",
    )
    maximum(object.completed for object in validated) == capture_end ||
        fail(
        "receipt.capture.capture_completed_at_utc",
        "must equal last fetch",
    )
    object_lookup = Dict(object.object_id => object for object in validated)
    _validate_attempts(
        root["attempts"],
        api_attempt_count,
        accepted_api_attempt_number,
        object_lookup["bls_v2_endpoint_unregistered_response"],
    )
    attempt_objects = _validate_attempt_objects(
        root["attempt_objects"],
        root["attempts"],
        object_lookup["bls_v2_endpoint_unregistered_response"],
        bundle_directory,
    )
    fingerprint = _validate_fingerprint(
        root["fingerprint"],
        object_lookup,
        acquisition_mode,
    )

    storage =
        expect_exact_keys(root["storage"], STORAGE_KEYS, "receipt.storage")
    storage["policy"] ==
        "TWO_DISTINCT_LOCAL_CONTENT_ADDRESSED_REPLICAS_PLUS_RECEIPT_COPIES" ||
        fail("receipt.storage.policy", "storage policy mismatch")
    expect_string_array(storage["copy_ids"], "receipt.storage.copy_ids") ==
        COPY_IDS ||
        fail("receipt.storage.copy_ids", "copy IDs mismatch")
    expect_int(
        storage["minimum_local_copy_count"],
        "receipt.storage.minimum_local_copy_count";
        minimum = 2,
    ) == 2 ||
        fail("receipt.storage.minimum_local_copy_count", "must remain two")
    expect_bool(
        storage["receipt_replica_required"],
        "receipt.storage.receipt_replica_required",
    ) ||
        fail("receipt.storage.receipt_replica_required", "must remain true")
    storage["external_durable_storage_attestation_status"] ==
        "NOT_VERIFIED" ||
        fail(
        "receipt.storage.external_durable_storage_attestation_status",
        "must remain unverified",
    )

    attestation = expect_exact_keys(
        root["attestation"],
        ATTESTATION_KEYS,
        "receipt.attestation",
    )
    expected_attestation = Dict(
        "capture_clock_attestation_status" =>
            "HOST_CLOCK_OBSERVATION_ONLY",
        "source_transport_attestation_status" =>
            "HOST_REPORTED_HTTP_METADATA_ONLY",
        "external_timestamp_attestation_status" => "NOT_VERIFIED",
        "production_prospective_verifier_status" => "NOT_ACTIVATED",
        "cryptographic_signoff_status" => "UNSIGNED",
    )
    attestation == expected_attestation ||
        fail(
        "receipt.attestation",
        "rehearsal must not assert external verification",
    )

    disposition = expect_exact_keys(
        root["disposition"],
        DISPOSITION_KEYS,
        "receipt.disposition",
    )
    expect_bool(
        disposition["rehearsal_only"],
        "receipt.disposition.rehearsal_only",
    ) ||
        fail("receipt.disposition.rehearsal_only", "must remain true")
    for field in (
            "origin_evidence",
            "origin_admissible",
            "ready",
            "inventory_mutation_authorized",
            "accuracy_evaluation_allowed",
        )
        !expect_bool(
            disposition[field],
            "receipt.disposition.$field",
        ) ||
            fail("receipt.disposition.$field", "must remain false")
    end
    return (;
        content_sha256 = declared,
        fingerprint,
        acquisition_mode,
        api_attempt_count,
        accepted_api_attempt_number,
        attempt_object_count = attempt_objects.count,
        source_revision,
    )
end

function _validate_receipt_replicas(
        bundle_directory,
        receipt_name,
        receipt_bytes,
    )
    for copy_id in COPY_IDS
        relative_path = "$copy_id/$receipt_name"
        copy_bytes = _resolve_regular_bytes(
            bundle_directory,
            relative_path,
            "receipt replica $copy_id",
        )
        copy_bytes == receipt_bytes ||
            fail("receipt replica $copy_id", "does not match root receipt bytes")
    end
    _assert_distinct_file_identities(
        [
            realpath(joinpath(bundle_directory, receipt_name)),
            [
                realpath(joinpath(bundle_directory, copy_id, receipt_name))
                    for copy_id in COPY_IDS
            ]...,
        ],
        "receipt replicas",
    )
    return nothing
end

"""
    validate_rehearsal_receipt_file(path; contract_path=...)

Verify an immutable, content-addressed BLS July 2026 rehearsal bundle. Success
establishes local byte integrity, two local replicas, capture-window
consistency, and the declared CES/CPS series-period fingerprints only. It
always remains non-admitting because external time, durable storage,
cryptographic approval, and the production prospective verifier are absent.
"""
function validate_rehearsal_receipt_file(
        path::AbstractString;
        contract_path = DEFAULT_PROSPECTIVE_CONTRACT_PATH,
    )
    receipt_path = abspath(String(path))
    isfile(receipt_path) ||
        fail("receipt file", "file does not exist: $receipt_path")
    islink(receipt_path) &&
        fail("receipt file", "must not be a symbolic link")
    bundle_directory = dirname(receipt_path)
    islink(bundle_directory) &&
        fail("receipt bundle", "must not be a symbolic link")
    receipt_bytes = read(receipt_path)
    isempty(receipt_bytes) && fail("receipt file", "must not be empty")
    receipt = _parse_toml_bytes(receipt_bytes, "receipt file")
    result = _validate_receipt_document(
        receipt,
        bundle_directory,
        contract_path,
    )
    expected_name =
        "receipt-content-sha256-$(result.content_sha256).toml"
    basename(receipt_path) == expected_name ||
        fail("receipt file", "must be content addressed as $expected_name")
    _validate_receipt_replicas(
        bundle_directory,
        expected_name,
        receipt_bytes,
    )
    api_only = result.acquisition_mode == API_FALLBACK_MODE
    blockers = copy(RECEIPT_BLOCKERS)
    if api_only
        push!(blockers, "NEWS_RELEASE_BYTES_NOT_CAPTURED")
    else
        push!(blockers, "NEWS_RELEASE_PDF_SEMANTICS_NOT_VALIDATED")
    end
    return (
        status = "LOCAL_REHEARSAL_INTEGRITY_VERIFIED_NONADMITTING",
        verification_scope = "local_rehearsal_bundle_integrity_only",
        content_sha256 = result.content_sha256,
        acquisition_mode = result.acquisition_mode,
        ces_value = result.fingerprint["ces"],
        cps_value = result.fingerprint["cps"],
        source_object_count = api_only ? 1 : 3,
        api_attempt_count = result.api_attempt_count,
        accepted_api_attempt_number = result.accepted_api_attempt_number,
        attempt_response_object_count = result.attempt_object_count,
        capture_agent_source_sha256 =
            capture_agent_source_sha256(),
        receipt_verifier_source_sha256 =
            receipt_verifier_source_sha256(),
        source_revision = result.source_revision,
        local_copy_count = 2,
        blockers,
        news_release_bytes_captured = !api_only,
        news_release_pdf_semantics_verified = false,
        api_response_captured = true,
        api_response_semantics =
            "v2_endpoint_unregistered_v1_compatible_history_as_known_at_capture",
        external_timestamp_verified = false,
        source_transport_verified = false,
        durable_storage_verified = false,
        production_verifier_attested = false,
        origin_evidence = false,
        origin_admissible = false,
        ready = false,
        inventory_mutation_authorized = false,
        accuracy_evaluation_allowed = false,
    )
end

end
