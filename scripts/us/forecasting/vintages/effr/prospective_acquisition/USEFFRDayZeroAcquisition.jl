module USEFFRDayZeroAcquisition

using Dates
using Downloads
using JSON
using SHA
using TOML

include(
    joinpath(
        @__DIR__,
        "..",
        "capture_contract",
        "USEFFRCaptureContract.jl",
    ),
)
using .USEFFRCaptureContract

export CapturedObject,
    DayZeroAcquisitionError,
    EFFECTIVE_DATE,
    PUBLICATION_DATE,
    acquire_day_zero,
    dry_run_plan,
    load_and_validate_bundle

const ReceiptContract = USEFFRCaptureContract
const EFFECTIVE_DATE = Date(2026, 8, 6)
const PUBLICATION_DATE = Date(2026, 8, 7)
const FIRST_WINDOW = (
    start = DateTime(2026, 8, 7, 13, 0),
    deadline = DateTime(2026, 8, 7, 13, 15),
)
const REVISION_WINDOW = (
    start = DateTime(2026, 8, 7, 18, 30),
    deadline = DateTime(2026, 8, 7, 18, 45),
)
const DATA_ENDPOINT =
    "https://markets.newyorkfed.org/api/rates/all/search.json"
const API_DOCUMENTATION_URL =
    "https://markets.newyorkfed.org/static/docs/markets-api.html"
const OPENAPI_URL =
    "https://markets.newyorkfed.org/static/docs/markets-api.yml"
const TERMS_URL = "https://www.newyorkfed.org/privacy/termsofuse"
const HOLIDAY_URL =
    "https://www.newyorkfed.org/aboutthefed/holiday_schedule"
const PROSPECTIVE_CONTRACT_ID =
    "beforeit-us-prospective-2026q3-acquisition.v2"
const PROSPECTIVE_CONTRACT_CONTENT_SHA256 =
    "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
const EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256 =
    "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
const EXPECTED_RECEIPT_CONTRACT_FILE_SHA256 =
    "6c4ee3ff95b92daf34899db64dbff7fc920eb33e5bc4bf17a6adf99bf3b3f651"
const PROSPECTIVE_CONTRACT_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "prospective",
        "prospective_2026q3_contract_v2.toml",
    ),
)
const RECEIPT_CONTRACT_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "capture_contract",
        "USEFFRCaptureContract.jl",
    ),
)
const ACQUISITION_CLI_PATH =
    joinpath(@__DIR__, "capture_effr_day_zero.jl")
const PROJECT_PATH = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", "Project.toml"),
)
const MANIFEST_PATH = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", "Manifest.toml"),
)
const SCHEMA_VERSION =
    "beforeit-us-effr-2026-08-07-day-zero-acquisition.v1"
const STORAGE_SCHEMA =
    "beforeit-us-effr-local-storage-integrity-receipt.v1"
const JOURNAL_SCHEMA =
    "beforeit-us-effr-private-preflight-journal.v1"
const ATTEMPT_EVENT_SCHEMA =
    "beforeit-us-effr-request-attempt-event.v1"
const MANIFEST_CANONICALIZATION =
    "sorted_toml_excluding_artifact_manifest_sha256.v1"
const STORAGE_CANONICALIZATION =
    "sorted_toml_excluding_storage_receipt_sha256.v1"
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
const LIVE_TIMEOUT_SECONDS = 20
const USER_AGENT =
    "BeforeIT-US-EFFR-Prospective-Capture/1.0 (+https://github.com/MarketsReplica/US_BeforeIT.jl)"
const TRANSPORT_POLICY =
    "DIRECT_TLS_NO_REDIRECT_NO_NETRC_NO_COOKIES_NO_AMBIENT_PROXY"
const RESPONSE_HEADER_ALLOWLIST = Set(
    [
        "age",
        "cache-control",
        "content-encoding",
        "content-length",
        "content-type",
        "date",
        "etag",
        "expires",
        "last-modified",
        "pragma",
        "server",
        "strict-transport-security",
        "transfer-encoding",
        "vary",
        "x-correlation-id",
        "x-request-id",
    ],
)
const BLOCKERS = [
    "CAPTURE_CLOCK_HOST_OBSERVATION_ONLY",
    "CAPTURE_SOURCE_REVISION_NOT_EXTERNALLY_ATTESTED",
    "DAILY_MANIFEST_COMPLETENESS_NOT_VALIDATED",
    "DURABLE_TWO_COPY_STORAGE_NOT_ESTABLISHED",
    "EXTERNAL_TIMESTAMP_NOT_ESTABLISHED",
    "HISTORICAL_BACKFILL_PLAN_ACQUISITION_GATE_FALSE",
    "HOLIDAY_CALENDAR_BYTES_CAPTURED_NOT_MACHINE_VALIDATED",
    "LOCAL_RECEIPT_PIN_NOT_OUT_OF_BAND_AUTHENTICATION",
    "OPENAPI_BYTES_CAPTURED_SAME_RUN_NOT_PRECOMMITTED_TRUST_PIN",
    "OPENAPI_SCHEMA_NOT_COMPILED_OR_MACHINE_ENFORCED",
    "ORIGIN_ADMISSION_FORBIDDEN",
    "PRODUCTION_USE_FORBIDDEN",
    "PROMOTION_FORBIDDEN",
    "PROSPECTIVE_CONTRACT_DRAFT_UNAPPROVED",
    "READINESS_FALSE",
    "RETENTION_THROUGH_2031_NOT_EXTERNALLY_ATTESTED",
    "SOURCE_TRANSPORT_NOT_INDEPENDENTLY_ATTESTED",
    "TERMS_REVIEW_IS_PROJECT_INTERPRETATION_NOT_LEGAL_AUTHORIZATION",
]
const ALWAYS_FALSE_GATES = Dict{String, Any}(
    "historical_first_byte_proven" => false,
    "origin_admissible" => false,
    "empirical_forecast_allowed" => false,
    "source_inventory_mutation_allowed" => false,
    "promotion_eligible" => false,
    "production_scoring_allowed" => false,
    "accuracy_evaluation_allowed" => false,
    "readiness" => false,
)
const OBJECT_SPECS = Dict(
    "rate_response" => (
        url = "$DATA_ENDPOINT?endDate=2026-08-06&startDate=2026-08-06&type=rate",
        media_types = ("application/json",),
        extension = "json",
        maximum_bytes = 2_000_000,
        role = "one_date_rate_response",
    ),
    "volume_response" => (
        url = "$DATA_ENDPOINT?endDate=2026-08-06&startDate=2026-08-06&type=volume",
        media_types = ("application/json",),
        extension = "json",
        maximum_bytes = 2_000_000,
        role = "one_date_volume_response",
    ),
    "api_documentation_snapshot" => (
        url = API_DOCUMENTATION_URL,
        media_types = ("text/html",),
        extension = "html",
        maximum_bytes = 2_000_000,
        role = "official_api_documentation_discovery_page",
    ),
    "openapi_snapshot" => (
        url = OPENAPI_URL,
        media_types = (
            "application/octet-stream",
            "application/yaml",
            "text/plain",
            "text/yaml",
        ),
        extension = "yml",
        maximum_bytes = 4_000_000,
        role = "authoritative_openapi_discovered_from_official_api_documentation",
    ),
    "terms_snapshot" => (
        url = TERMS_URL,
        media_types = ("text/html",),
        extension = "html",
        maximum_bytes = 4_000_000,
        role = "terms_snapshot_project_review_input",
    ),
    "holiday_snapshot" => (
        url = HOLIDAY_URL,
        media_types = ("text/html",),
        extension = "html",
        maximum_bytes = 4_000_000,
        role = "official_holiday_schedule_unparsed_evidence",
    ),
)

struct DayZeroAcquisitionError <: Exception
    message::String
end

Base.showerror(io::IO, error::DayZeroAcquisitionError) =
    print(io, error.message)

fail(location, message) =
    throw(DayZeroAcquisitionError("$location: $message"))

Base.@kwdef struct CapturedObject
    object_id::String
    body::Vector{UInt8}
    requested_url::String
    final_url::String
    http_status::Int
    content_type::String
    content_encoding::String
    response_headers::Vector{String}
    request_started_at_utc::DateTime
    response_metadata_observed_at_utc::DateTime
    response_body_completed_at_utc::DateTime
end

sha256_hex(bytes) = bytes2hex(sha256(bytes))

function file_sha256(path)
    isfile(path) || fail("source binding", "missing file $path")
    islink(path) && fail("source binding", "refuses symbolic link $path")
    return sha256_hex(read(path))
end

timestamp(value::DateTime) =
    Dates.format(value, TIMESTAMP_FORMAT) * "Z"

function expect_phase(phase)
    text = String(phase)
    text in ("first", "revision-check") ||
        fail("phase", "must be first or revision-check")
    return text
end

phase_state(phase) =
    expect_phase(phase) == "first" ?
    "FIRST_0900_STATE" : "SAME_DAY_1430_REVISION_CHECK"

phase_window(phase) =
    expect_phase(phase) == "first" ? FIRST_WINDOW : REVISION_WINDOW

function validate_transaction_id(value)
    text = String(value)
    occursin(IDENTIFIER_PATTERN, text) ||
        fail(
        "transaction_id",
        "must match $(IDENTIFIER_PATTERN.pattern)",
    )
    return text
end

function _media_type(content_type)
    value = lowercase(strip(first(split(String(content_type), ';'; limit = 2))))
    isempty(value) && fail("response content type", "must not be empty")
    return value
end

function _validate_source_bindings()
    prospective_file_sha256 = file_sha256(PROSPECTIVE_CONTRACT_PATH)
    prospective_file_sha256 == EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256 ||
        fail(
        "prospective contract",
        "file SHA-256 differs from the preregistered day-zero pin",
    )
    contract = TOML.parsefile(PROSPECTIVE_CONTRACT_PATH)
    artifact = get(contract, "artifact", nothing)
    artifact isa AbstractDict ||
        fail("prospective contract", "missing artifact table")
    get(artifact, "contract_id", "") == PROSPECTIVE_CONTRACT_ID ||
        fail("prospective contract", "contract ID mismatch")
    get(artifact, "content_sha256", "") ==
        PROSPECTIVE_CONTRACT_CONTENT_SHA256 ||
        fail("prospective contract", "semantic content SHA-256 mismatch")
    receipt_contract_sha256 = file_sha256(RECEIPT_CONTRACT_PATH)
    receipt_contract_sha256 == EXPECTED_RECEIPT_CONTRACT_FILE_SHA256 ||
        fail(
        "receipt contract",
        "file SHA-256 differs from the reviewed one-date validator pin",
    )
    return (;
        prospective_file_sha256,
        prospective_content_sha256 =
            PROSPECTIVE_CONTRACT_CONTENT_SHA256,
        receipt_contract_sha256,
        acquisition_source_sha256 = file_sha256(@__FILE__),
        acquisition_cli_sha256 = file_sha256(ACQUISITION_CLI_PATH),
        project_sha256 = file_sha256(PROJECT_PATH),
        manifest_sha256 = file_sha256(MANIFEST_PATH),
    )
end

"""
    dry_run_plan(phase; transaction_id, output_root, predecessor_bundle=nothing)

Return the exact, network-free execution plan. This function neither creates
directories nor fetches source bytes.
"""
function dry_run_plan(
        phase;
        transaction_id,
        output_root,
        predecessor_bundle = nothing,
    )
    selected_phase = expect_phase(phase)
    transaction = validate_transaction_id(transaction_id)
    selected_phase == "revision-check" && predecessor_bundle === nothing &&
        fail(
        "predecessor_bundle",
        "is required for the revision-check phase",
    )
    bindings = _validate_source_bindings()
    window = phase_window(selected_phase)
    target = joinpath(
        abspath(String(output_root)),
        string(PUBLICATION_DATE),
        phase_state(selected_phase),
        transaction,
    )
    return (
        mode = "DRY_RUN_NO_NETWORK_NO_FILESYSTEM_WRITES",
        phase = selected_phase,
        state_class = phase_state(selected_phase),
        publication_date = string(PUBLICATION_DATE),
        effective_date = string(EFFECTIVE_DATE),
        capture_not_before_utc = timestamp(window.start),
        capture_deadline_utc = timestamp(window.deadline),
        ordered_requests = Tuple(
            (
                object_id = object_id,
                requested_url = OBJECT_SPECS[object_id].url,
            ) for object_id in (
                "rate_response",
                "volume_response",
                "api_documentation_snapshot",
                "openapi_snapshot",
                "terms_snapshot",
                "holiday_snapshot",
            )
        ),
        output_bundle = target,
        predecessor_bundle = predecessor_bundle === nothing ?
            "NOT_APPLICABLE" : abspath(String(predecessor_bundle)),
        source_bindings = bindings,
        gates = ALWAYS_FALSE_GATES,
        blockers = Tuple(BLOCKERS),
    )
end

function _direct_only_downloader()
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, _) -> begin
        curl = Downloads.Curl
        curl.setopt(easy, curl.CURLOPT_FOLLOWLOCATION, false)
        curl.setopt(easy, curl.CURLOPT_MAXREDIRS, 0)
        curl.setopt(easy, curl.CURLOPT_NETRC, curl.CURL_NETRC_IGNORED)
        curl.setopt(easy, curl.CURLOPT_NETRC_FILE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIEFILE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIEJAR, C_NULL)
        curl.setopt(easy, curl.CURLOPT_PROXY, "")
        curl.setopt(easy, curl.CURLOPT_NOPROXY, "*")
    end
    return downloader
end

function _normalized_headers(response)
    collected = Dict{String, String}()
    for (name, value) in response.headers
        key = lowercase(strip(String(name)))
        key in RESPONSE_HEADER_ALLOWLIST || continue
        text = strip(String(value))
        if haskey(collected, key)
            collected[key] *= ", " * text
        else
            collected[key] = text
        end
    end
    return sort!(["$name: $value" for (name, value) in collected])
end

function _header_value(headers, name)
    wanted = lowercase(String(name))
    for (key, value) in headers
        lowercase(String(key)) == wanted || continue
        return strip(String(value))
    end
    return ""
end

function _live_fetch(spec)
    object_id = String(spec.object_id)
    haskey(OBJECT_SPECS, object_id) ||
        fail("live fetch", "unknown object ID $object_id")
    expected = OBJECT_SPECS[object_id]
    expected.url == String(spec.requested_url) ||
        fail("live fetch", "requested URL differs from the closed plan")
    output = IOBuffer(; maxsize = expected.maximum_bytes + 1)
    started = now(UTC)
    response = try
        Downloads.request(
            expected.url;
            downloader = _direct_only_downloader(),
            output,
            method = "GET",
            headers = [
                "Accept" => join(expected.media_types, ", "),
                "Accept-Encoding" => "identity",
                "User-Agent" => USER_AGENT,
            ],
            timeout = LIVE_TIMEOUT_SECONDS,
        )
    catch
        fail(
            "live $object_id",
            "request failed under $TRANSPORT_POLICY",
        )
    end
    completed = now(UTC)
    body = take!(output)
    # Downloads exposes response metadata only after the body transfer returns.
    # We preserve that conservative observation time without pretending to have
    # an earlier header callback timestamp.
    metadata_observed = completed
    return CapturedObject(
        object_id = object_id,
        body = body,
        requested_url = expected.url,
        final_url = String(response.url),
        http_status = Int(response.status),
        content_type = _header_value(response.headers, "content-type"),
        content_encoding = begin
            observed = lowercase(_header_value(response.headers, "content-encoding"))
            isempty(observed) ? "identity" : observed
        end,
        response_headers = _normalized_headers(response),
        request_started_at_utc = started,
        response_metadata_observed_at_utc = metadata_observed,
        response_body_completed_at_utc = completed,
    )
end

function _validate_captured_object(object, phase)
    haskey(OBJECT_SPECS, object.object_id) ||
        fail("captured object", "unknown object ID $(object.object_id)")
    expected = OBJECT_SPECS[object.object_id]
    object.requested_url == expected.url ||
        fail(object.object_id, "requested URL mismatch")
    object.final_url == expected.url ||
        fail(object.object_id, "redirect or final URL mismatch")
    object.http_status == 200 ||
        fail(object.object_id, "HTTP status must be 200")
    any(
        header ->
            occursin('\r', header) || occursin('\n', header),
        object.response_headers,
    ) && fail(object.object_id, "response header contains an embedded line break")
    isempty(object.body) &&
        fail(object.object_id, "response body must not be empty")
    length(object.body) <= expected.maximum_bytes ||
        fail(object.object_id, "response body exceeds byte limit")
    _media_type(object.content_type) in expected.media_types ||
        fail(object.object_id, "unexpected response media type")
    object.content_encoding == "identity" ||
        fail(object.object_id, "response content encoding must be identity")
    object.request_started_at_utc <=
        object.response_metadata_observed_at_utc <=
        object.response_body_completed_at_utc ||
        fail(object.object_id, "response timestamps are not monotone")
    window = phase_window(phase)
    window.start <= object.request_started_at_utc <=
        object.response_body_completed_at_utc <= window.deadline ||
        fail(object.object_id, "capture is outside the preregistered window")
    return object
end

function _expect_dict(value, location)
    value isa AbstractDict || fail(location, "must be an object")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return Dict{String, Any}(String(key) => item for (key, item) in value)
end

function _expect_exact_keys(value, required, optional, location)
    row = _expect_dict(value, location)
    actual = Set(keys(row))
    required_set = Set(String.(required))
    optional_set = Set(String.(optional))
    missing = sort!(collect(setdiff(required_set, actual)))
    unknown = sort!(collect(setdiff(actual, union(required_set, optional_set))))
    isempty(missing) ||
        fail(location, "missing fields: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown fields: $(join(unknown, ", "))")
    return row
end

function _expect_string(value, location; allow_empty = false)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    (!isempty(text) || allow_empty) ||
        fail(location, "must not be empty")
    return text
end

function _expect_number(value, location)
    value isa Real && !(value isa Bool) ||
        fail(location, "must be a number")
    number = Float64(value)
    isfinite(number) || fail(location, "must be finite")
    return number
end

function _footnote_token(row, location)
    has_footnote = haskey(row, "footnote")
    has_footnote_id = haskey(row, "footnoteId")
    has_footnote && has_footnote_id &&
        fail(location, "must not contain both footnote and footnoteId")
    value = if has_footnote
        row["footnote"]
    elseif has_footnote_id
        row["footnoteId"]
    else
        ""
    end
    token = if value isa Integer && !(value isa Bool)
        string(value)
    elseif value isa AbstractString
        String(value)
    else
        fail(location, "footnote token has an unsupported type")
    end
    token in ("", "1", "2", "3") ||
        fail(location, "footnote token is outside the closed vocabulary")
    return token
end

function _select_effr_row(body, report_type)
    parsed = try
        # `String(::Vector{UInt8})` may take ownership of and empty its input.
        # Parse a copy so the exact captured bytes remain immutable evidence.
        JSON.parse(String(copy(body)))
    catch
        fail("$report_type response", "body is not valid UTF-8 JSON")
    end
    envelope = _expect_exact_keys(
        parsed,
        ("refRates",),
        (),
        "$report_type response envelope",
    )
    rows = envelope["refRates"]
    rows isa AbstractVector ||
        fail("$report_type response.refRates", "must be an array")
    candidates = Tuple{Int, Dict{String, Any}}[]
    for (index, raw_row) in enumerate(rows)
        row = _expect_dict(raw_row, "$report_type response.refRates[$index]")
        get(row, "type", nothing) == "EFFR" || continue
        push!(candidates, (index, row))
    end
    length(candidates) == 1 ||
        fail(
        "$report_type response.refRates",
        "must contain exactly one raw type=EFFR row; found $(length(candidates))",
    )
    index, row = only(candidates)
    common_required = (
        "effectiveDate",
        "type",
        "revisionIndicator",
    )
    optional = ("footnote", "footnoteId", "currentState")
    required = if report_type == "rate"
        (
            common_required...,
            "percentRate",
            "percentPercentile1",
            "percentPercentile25",
            "percentPercentile75",
            "percentPercentile99",
            "targetRateFrom",
            "targetRateTo",
        )
    else
        (common_required..., "volumeInBillions")
    end
    row = _expect_exact_keys(
        row,
        required,
        optional,
        "$report_type EFFR row",
    )
    _expect_string(row["effectiveDate"], "$report_type effectiveDate") ==
        string(EFFECTIVE_DATE) ||
        fail("$report_type effectiveDate", "does not equal 2026-08-06")
    _expect_string(row["type"], "$report_type raw identity") == "EFFR" ||
        fail("$report_type raw identity", "must be EFFR")
    revision = _expect_string(
        row["revisionIndicator"],
        "$report_type revisionIndicator";
        allow_empty = true,
    )
    revision in ("", "r") ||
        fail(
        "$report_type revisionIndicator",
        "unknown token $(repr(revision)); bytes retained without coercion",
    )
    if haskey(row, "currentState")
        row["currentState"] isa Bool ||
            fail("$report_type currentState", "must be Boolean")
        row["currentState"] === false ||
            fail(
            "$report_type currentState",
                "true current-state flag cannot be a prospective intraday receipt",
            )
        current_state_present = true
        current_state = false
        current_state_source = "RAW_FIELD_FALSE"
    else
        current_state_present = false
        current_state = nothing
        current_state_source =
            "ABSENT_FROM_RAW_RESPONSE_NOT_DERIVED"
    end
    footnote = _footnote_token(row, "$report_type EFFR row")
    values = Dict{String, Any}()
    if report_type == "rate"
        for field in (
                "percentRate",
                "percentPercentile1",
                "percentPercentile25",
                "percentPercentile75",
                "percentPercentile99",
                "targetRateFrom",
                "targetRateTo",
            )
            values[field] = _expect_number(row[field], "$report_type $field")
        end
    else
        values["volumeInBillions"] =
            _expect_number(row["volumeInBillions"], "$report_type volumeInBillions")
    end
    return (
        json_pointer = "/refRates/$(index - 1)",
        one_based_index = index,
        raw_identity_field = "type",
        raw_identity_value = "EFFR",
        raw_keys = Tuple(sort!(collect(keys(row)))),
        revision = revision,
        footnote = footnote,
        current_state_present = current_state_present,
        current_state = current_state,
        current_state_source = current_state_source,
        values = values,
    )
end

function _canonical_toml_bytes(document; excluded_path)
    copy = deepcopy(document)
    table_name, field_name = excluded_path
    haskey(copy, table_name) ||
        fail("canonicalization", "missing table $table_name")
    table = copy[table_name]
    table isa AbstractDict ||
        fail("canonicalization", "$table_name must be a table")
    haskey(table, field_name) ||
        fail("canonicalization", "missing field $table_name.$field_name")
    delete!(table, field_name)
    io = IOBuffer()
    TOML.print(io, copy; sorted = true)
    bytes = take!(io)
    isempty(bytes) || bytes[end] == UInt8('\n') ||
        push!(bytes, UInt8('\n'))
    return bytes
end

function _toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    bytes = take!(io)
    isempty(bytes) || bytes[end] == UInt8('\n') ||
        push!(bytes, UInt8('\n'))
    return bytes
end

function _storage_receipt(objects)
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => STORAGE_SCHEMA,
            "canonicalization" => STORAGE_CANONICALIZATION,
            "storage_receipt_sha256" => repeat("0", 64),
        ),
        "storage" => Dict{String, Any}(
            "storage_class" =>
                "TWO_LOCAL_IGNORED_REPLICAS_INTEGRITY_ONLY_NOT_DURABLE",
            "copy_ids" => ["replica-a", "replica-b"],
            "local_copy_count" => 2,
            "external_durable_copy_count" => 0,
            "external_timestamp_verified" => false,
            "retention_through_2031_attested" => false,
            "git_commit_authorized" => false,
        ),
        "objects" => [
            Dict{String, Any}(
                "object_id" => object.object_id,
                "raw_sha256" => sha256_hex(object.body),
                "raw_byte_count" => length(object.body),
            ) for object in sort(objects; by = item -> item.object_id)
        ],
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
    digest = sha256_hex(
        _canonical_toml_bytes(
            document;
            excluded_path = ("artifact", "storage_receipt_sha256"),
        ),
    )
    document["artifact"]["storage_receipt_sha256"] = digest
    return document
end

function _receipt_blockers(revision)
    blockers = Set(
        (
            "EMPIRICAL_EXECUTION_FORBIDDEN",
            "HISTORICAL_FIRST_BYTES_UNPROVEN",
            "ORIGIN_ADMISSION_FORBIDDEN",
            "PRODUCTION_USE_FORBIDDEN",
            "PROMOTION_FORBIDDEN",
            "RATE_VOLUME_PAIR_NOT_YET_VALIDATED",
            "READINESS_FALSE",
        ),
    )
    revision == "r" &&
        push!(blockers, "OPENAPI_EXAMPLE_MISMATCH_PRESERVED")
    return sort!(collect(blockers))
end

function _build_one_date_receipt(
        object,
        selected,
        report_type,
        state_class;
        openapi_sha256,
        terms_sha256,
        storage_receipt_sha256,
        predecessor = "NONE",
    )
    required_revision =
        state_class == "FIRST_0900_STATE" ? "" :
        state_class == "SAME_DAY_1430_REVISION" ? "r" :
        fail("receipt state", "unsupported state $state_class")
    selected.current_state_present ||
        fail(
        "$report_type receipt",
        "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT",
    )
    selected.current_state === false ||
        fail("$report_type receipt", "raw currentState must be false")
    selected.revision == required_revision ||
        fail(
        "$report_type receipt",
        "$state_class requires revision token $(repr(required_revision))",
    )
    not_requested = "NOT_REQUESTED_IN_REPORT_TYPE"
    values = selected.values
    raw_fields = Dict{String, Any}(
        "effectiveDate" => string(EFFECTIVE_DATE),
        "type" => report_type,
        "percentRate" =>
            report_type == "rate" ? values["percentRate"] : not_requested,
        "percentPercentile1" =>
            report_type == "rate" ? values["percentPercentile1"] : not_requested,
        "percentPercentile25" =>
            report_type == "rate" ? values["percentPercentile25"] : not_requested,
        "percentPercentile75" =>
            report_type == "rate" ? values["percentPercentile75"] : not_requested,
        "percentPercentile99" =>
            report_type == "rate" ? values["percentPercentile99"] : not_requested,
        "targetRateFrom" =>
            report_type == "rate" ? values["targetRateFrom"] : not_requested,
        "targetRateTo" =>
            report_type == "rate" ? values["targetRateTo"] : not_requested,
        "volumeInBillions" =>
            report_type == "volume" ? values["volumeInBillions"] : not_requested,
        "footnote" => selected.footnote,
        "revisionIndicator" => selected.revision,
        "currentState" => false,
    )
    encoded_revision = isempty(selected.revision) ? "EMPTY" : selected.revision
    query =
        "endDate=2026-08-06&startDate=2026-08-06&type=$report_type"
    raw_digest = sha256_hex(object.body)
    predecessor_required = state_class == "SAME_DAY_1430_REVISION"
    predecessor_required && predecessor == "NONE" &&
        fail("$report_type receipt", "revision requires predecessor receipt")
    document = Dict{String, Any}(
        "schema_version" => ReceiptContract.SCHEMA_VERSION,
        "receipt_id" =>
            "EFFR:2026-08-06:$(uppercase(report_type)):$state_class",
        "source" => Dict{String, Any}(
            "authority" => "Federal Reserve Bank of New York",
            "source_id" => "NYFED_MARKETS_API",
            "series_id" => "EFFR",
            "evidence_track" => "STRICT_FIRST_PUBLIC_BYTES",
            "concept_regime" =>
                "POST_2016_FR2420_VOLUME_WEIGHTED_MEDIAN",
            "route_class" => "NYFED_PROSPECTIVE_CAPTURE",
            "historical_vintage_claim" =>
                "CURRENT_API_DOES_NOT_PROVE_HISTORICAL_VINTAGE",
        ),
        "observation" => Dict{String, Any}(
            "effective_date" => "2026-08-06",
            "publication_date" => "2026-08-07",
            "publication_utc_offset" => "-04:00",
            "report_type" => report_type,
            "state_class" => state_class,
            "scheduled_publication_window" =>
                state_class == "FIRST_0900_STATE" ?
                "NYFED_APPROX_0900_ET" : "NYFED_APPROX_1430_ET",
            "pair_key" =>
                "effectiveDate=2026-08-06;revisionToken=$encoded_revision",
        ),
        "request" => Dict{String, Any}(
            "endpoint" => DATA_ENDPOINT,
            "canonical_query" => query,
            "requested_url" => "$DATA_ENDPOINT?$query",
            "request_started_at_utc" =>
                timestamp(object.request_started_at_utc),
            "secret_ref" => "NOT_REQUIRED_PUBLIC_ENDPOINT",
        ),
        "response" => Dict{String, Any}(
            "response_headers_at_utc" =>
                timestamp(object.response_metadata_observed_at_utc),
            "response_body_completed_at_utc" =>
                timestamp(object.response_body_completed_at_utc),
            "availability_upper_bound_utc" =>
                timestamp(object.response_body_completed_at_utc),
            "http_status" => object.http_status,
            "final_host" => "markets.newyorkfed.org",
            "final_url" => object.final_url,
            "redirect_count" => 0,
            "redirect_chain" => Any[],
            "headers_complete" => true,
            "content_type" => _media_type(object.content_type),
            "content_encoding" => object.content_encoding,
            "content_length" => length(object.body),
        ),
        "artifact" => Dict{String, Any}(
            "raw_sha256" => raw_digest,
            "openapi_sha256" => openapi_sha256,
            "durable_storage_locator" => "artifact-sha256:$raw_digest",
            "durable_storage_receipt_sha256" =>
                storage_receipt_sha256,
        ),
        "raw_fields" => raw_fields,
        "classification" => Dict{String, Any}(
            "revision_class" =>
                isempty(selected.revision) ?
                "NOT_REVISED_RAW_EMPTY_TOKEN" :
                "DOCUMENTED_REVISED_RAW_TOKEN_WITH_SCHEMA_MISMATCH",
            "footnote_class" => Dict(
                "" => "NO_FOOTNOTE_RAW_EMPTY_TOKEN",
                "1" => "DOCUMENTED_REDUCED_VOLUME",
                "2" => "DOCUMENTED_BROKER_CONTINGENCY",
                "3" => "DOCUMENTED_PRIOR_DAY_REPUBLICATION",
            )[selected.footnote],
            "rate_report_volume_class" =>
                report_type == "rate" ?
                "NOT_REQUESTED_IN_REPORT_TYPE" :
                "PUBLISHED_VOLUME_FIELD",
            "unsupported_blank_class" => "NO_UNSUPPORTED_BLANK",
            "current_state_class" => "NOT_CURRENT_STATE_FLAG",
            "schema_class" =>
                isempty(selected.revision) ?
                "PINNED_CURRENT_API_EXACT_FIELDSET" :
                "DOCUMENTED_OPENAPI_EXAMPLE_MISMATCH_PINNED_FIELDSET",
            "schema_mismatch_detail" => "NONE",
            "quarantine_class" => "NOT_QUARANTINED",
            "adjudication_state" => "NOT_REQUIRED_EXACT_SCHEMA",
            "evidence_locator" => "artifact-sha256:$raw_digest",
            "blockers" => _receipt_blockers(selected.revision),
        ),
        "governance" => Dict{String, Any}(
            "terms_url" => TERMS_URL,
            "terms_snapshot_sha256" => terms_sha256,
            "terms_snapshot_date" => "2026-08-07",
            "terms_review_decision" => "APPROVED_FOR_BOUNDED_CAPTURE",
            "attribution_requirement" =>
                "ATTRIBUTION_REQUIRED_FEDERAL_RESERVE_BANK_OF_NEW_YORK",
            "disclaimer_requirement" =>
                "REFERENCE_RATE_DISCLAIMER_REQUIRED_FOR_DERIVED_USE",
            "redistribution_scope" => "INTERNAL_RESEARCH_ONLY",
            "secret_ref" => "NOT_REQUIRED_PUBLIC_ENDPOINT",
        ),
        "lineage" => Dict{String, Any}(
            "predecessor_receipt_sha256" => predecessor,
            "supersedes_receipt_sha256" => predecessor,
            "supersession_status" =>
                predecessor_required ?
                "SUPERSEDES_BY_POINTER_WITHOUT_OVERWRITE" :
                "NEW_NONOVERWRITING_STATE",
        ),
        "gates" => Dict{String, Any}(
            "historical_first_byte_proven" => false,
            "origin_admissible" => false,
            "empirical_forecast_allowed" => false,
            "source_inventory_mutation_allowed" => false,
            "promotion_eligible" => false,
            "production_scoring_allowed" => false,
            "readiness" => false,
            "current_api_proves_historical_vintage" => false,
        ),
        "receipt_sha256" => repeat("0", 64),
    )
    document["receipt_sha256"] =
        ReceiptContract.canonical_receipt_sha256(document)
    ReceiptContract.validate_receipt(
        document,
        document["receipt_sha256"],
    )
    return document
end

function _object_record(object, extension)
    digest = sha256_hex(object.body)
    name = "raw-sha256-$digest.$extension"
    request_headers = [
        "Accept: $(join(OBJECT_SPECS[object.object_id].media_types, ", "))",
        "Accept-Encoding: identity",
        "User-Agent: $USER_AGENT",
    ]
    return Dict{String, Any}(
        "object_id" => object.object_id,
        "role" => OBJECT_SPECS[object.object_id].role,
        "requested_url" => object.requested_url,
        "final_url" => object.final_url,
        "canonical_query" =>
            object.object_id == "rate_response" ?
            "endDate=2026-08-06&startDate=2026-08-06&type=rate" :
            object.object_id == "volume_response" ?
            "endDate=2026-08-06&startDate=2026-08-06&type=volume" :
            "NOT_APPLICABLE",
        "http_method" => "GET",
        "request_headers" => request_headers,
        "request_headers_sha256" =>
            sha256_hex(codeunits(join(request_headers, "\n"))),
        "http_status" => object.http_status,
        "content_type" => object.content_type,
        "content_encoding" => object.content_encoding,
        "response_headers" => object.response_headers,
        "response_headers_sha256" =>
            sha256_hex(codeunits(join(object.response_headers, "\n"))),
        "request_started_at_utc" =>
            timestamp(object.request_started_at_utc),
        "response_metadata_observed_at_utc" =>
            timestamp(object.response_metadata_observed_at_utc),
        "response_body_completed_at_utc" =>
            timestamp(object.response_body_completed_at_utc),
        "response_header_timestamp_semantics" =>
            "CONSERVATIVE_POST_BODY_RESPONSE_OBJECT_OBSERVATION",
        "raw_sha256" => digest,
        "raw_byte_count" => length(object.body),
        "primary_path" => "replica-a/$name",
        "replica_path" => "replica-b/$name",
    )
end

function _identity_record(report_type, selected)
    return Dict{String, Any}(
        "report_type" => report_type,
        "full_response_preserved_before_parse" => true,
        "selection_rule" => "EXACTLY_ONE_RAW_TYPE_EQUALS_EFFR",
        "json_pointer" => selected.json_pointer,
        "one_based_array_index" => selected.one_based_index,
        "raw_identity_field" => selected.raw_identity_field,
        "raw_identity_value" => selected.raw_identity_value,
        "raw_keys" => collect(selected.raw_keys),
        "raw_revision_indicator" => selected.revision,
        "normalized_footnote_token" => selected.footnote,
        "raw_current_state_present" => selected.current_state_present,
        "raw_current_state_value" =>
            selected.current_state_present ? "false" : "ABSENT",
        "current_state_source" => selected.current_state_source,
        "alias_or_first_row_fallback_used" => false,
    )
end

function _manifest_digest!(manifest)
    digest = sha256_hex(
        _canonical_toml_bytes(
            manifest;
            excluded_path = ("artifact", "manifest_sha256"),
        ),
    )
    manifest["artifact"]["manifest_sha256"] = digest
    return digest
end

function _failure_code(error)
    message = sprint(showerror, error)
    if occursin("currentState", message)
        return "CURRENT_STATE_SCHEMA_CONFLICT"
    elseif occursin("revisionIndicator", message)
        return "REVISION_TOKEN_SCHEMA_CONFLICT"
    elseif occursin("exactly one raw type=EFFR", message)
        return "EFFR_ROW_CARDINALITY_FAILURE"
    elseif occursin("outside the preregistered window", message)
        return "CAPTURE_WINDOW_FAILURE"
    elseif occursin("request failed", message)
        return "NETWORK_REQUEST_FAILURE"
    elseif occursin("OpenAPI", message) || occursin("openapi", message)
        return "OPENAPI_CAPTURE_OR_BINDING_FAILURE"
    elseif occursin("terms", lowercase(message))
        return "TERMS_CAPTURE_OR_BINDING_FAILURE"
    end
    return "FAIL_CLOSED_VALIDATION_FAILURE"
end

function _base_manifest(
        phase,
        transaction_id,
        bindings,
        objects,
        storage_receipt,
    )
    object_records = [
        _object_record(
                object,
                OBJECT_SPECS[object.object_id].extension,
            ) for object in objects
    ]
    return Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => SCHEMA_VERSION,
            "manifest_id" =>
                "effr-day-zero-2026-08-07.$(phase_state(phase)).$transaction_id",
            "canonicalization" => MANIFEST_CANONICALIZATION,
            "manifest_sha256" => repeat("0", 64),
        ),
        "contract_binding" => Dict{String, Any}(
            "prospective_contract_id" => PROSPECTIVE_CONTRACT_ID,
            "prospective_contract_file_sha256" =>
                bindings.prospective_file_sha256,
            "prospective_contract_content_sha256" =>
                bindings.prospective_content_sha256,
            "prospective_contract_status" =>
                "DRAFT_UNAPPROVED_FAIL_CLOSED",
            "receipt_contract_schema_version" =>
                ReceiptContract.SCHEMA_VERSION,
            "receipt_contract_source_sha256" =>
                bindings.receipt_contract_sha256,
            "acquisition_source_sha256" =>
                bindings.acquisition_source_sha256,
            "acquisition_cli_sha256" =>
                bindings.acquisition_cli_sha256,
            "project_sha256" => bindings.project_sha256,
            "manifest_sha256" => bindings.manifest_sha256,
        ),
        "event" => Dict{String, Any}(
            "campaign_id" => "frbny_effr_daily_first_state_and_revision_check",
            "phase" => phase,
            "state_class_candidate" => phase_state(phase),
            "publication_date" => "2026-08-07",
            "effective_date" => "2026-08-06",
            "scheduled_time_utc" =>
                timestamp(phase_window(phase).start),
            "capture_deadline_utc" =>
                timestamp(phase_window(phase).deadline),
            "publication_utc_offset" => "-04:00",
            "official_publication_day_validated" => false,
        ),
        "capture" => Dict{String, Any}(
            "transaction_id" => transaction_id,
            "transport_policy" => TRANSPORT_POLICY,
            "request_order" => [
                "rate_response",
                "volume_response",
                "api_documentation_snapshot",
                "openapi_snapshot",
                "terms_snapshot",
                "holiday_snapshot",
            ],
            "response_header_timestamp_semantics" =>
                "CONSERVATIVE_POST_BODY_RESPONSE_OBJECT_OBSERVATION",
            "object_count" => length(objects),
            "network_request_count" => length(objects),
            "julia_version" => string(VERSION),
            "machine" => Sys.MACHINE,
            "julia_thread_count" => Threads.nthreads(),
        ),
        "objects" => object_records,
        "row_identity" => Dict{String, Any}[],
        "governance" => Dict{String, Any}(
            "terms_url" => TERMS_URL,
            "terms_snapshot_date" => "2026-08-07",
            "terms_review_decision" => "APPROVED_FOR_BOUNDED_CAPTURE",
            "terms_review_scope" =>
                "PROJECT_INTERPRETATION_FOR_INTERNAL_BOUNDED_CAPTURE_NOT_LEGAL_ADVICE",
            "attribution" =>
                "© 2026 Federal Reserve Bank of New York. Content from the New York Fed subject to the Terms of Use at newyorkfed.org.",
            "reference_rate_notice" =>
                "The Effective Federal Funds Rate data is subject to the Terms of Use posted at newyorkfed.org. The New York Fed is not responsible for publication of the Effective Federal Funds Rate data by BeforeIT, does not sanction or endorse any particular republication, and has no liability for your use.",
            "redistribution_scope" => "INTERNAL_RESEARCH_ONLY",
        ),
        "storage" => Dict{String, Any}(
            "local_storage_receipt_sha256" =>
                storage_receipt["artifact"]["storage_receipt_sha256"],
            "local_storage_receipt_file" =>
                "local-storage-receipt.toml",
            "two_local_copies_verified" => false,
            "durable_external_copy_count" => 0,
            "external_timestamp_verified" => false,
            "retention_through_2031_attested" => false,
            "raw_bytes_git_commit_authorized" => false,
        ),
        "result" => Dict{String, Any}(
            "status" => "PENDING_FAIL_CLOSED_EVALUATION",
            "success" => false,
            "raw_capture_complete" => false,
            "failure_code" => "NOT_YET_EVALUATED",
            "failure_detail" => "NOT_YET_EVALUATED",
            "rate_receipt_file" => "NONE",
            "volume_receipt_file" => "NONE",
            "rate_receipt_sha256" => "NONE",
            "volume_receipt_sha256" => "NONE",
            "pair_status" => "NOT_EVALUATED",
            "predecessor_bundle" => "NOT_APPLICABLE",
            "predecessor_rate_receipt_sha256" => "NONE",
            "predecessor_volume_receipt_sha256" => "NONE",
            "byte_equality_rate" => false,
            "byte_equality_volume" => false,
            "revision_observed" => false,
            "revision_receipt_created" => false,
            "one_date_receipt_validated" => false,
            "receipt_authentication_status" =>
                "SELF_GENERATED_LOCAL_INTEGRITY_PIN_NOT_OUT_OF_BAND",
        ),
        "blockers" => copy(BLOCKERS),
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
end

function _safe_file(path)
    isfile(path) || fail("bundle verification", "missing file $path")
    islink(path) && fail("bundle verification", "symbolic link rejected at $path")
    stat(path).nlink == 1 ||
        fail("bundle verification", "hard-linked file rejected at $path")
    return path
end

function _safe_relative_path(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    isabspath(text) && fail(location, "must be relative")
    normalized = normpath(text)
    normalized == text ||
        fail(location, "must already be a normalized relative path")
    pieces = splitpath(normalized)
    any(piece -> piece == "..", pieces) &&
        fail(location, "must not traverse outside the bundle")
    return text
end

function _validate_manifest_hash(manifest)
    embedded = get(get(manifest, "artifact", Dict()), "manifest_sha256", "")
    occursin(HASH_PATTERN, embedded) ||
        fail("bundle manifest", "invalid embedded manifest SHA-256")
    computed = sha256_hex(
        _canonical_toml_bytes(
            manifest;
            excluded_path = ("artifact", "manifest_sha256"),
        ),
    )
    embedded == computed ||
        fail("bundle manifest", "manifest SHA-256 mismatch")
    return computed
end

function _find_object_record(manifest, object_id)
    rows = get(manifest, "objects", nothing)
    rows isa AbstractVector ||
        fail("bundle manifest", "objects must be an array")
    matches = [
        row for row in rows if
            row isa AbstractDict &&
            get(row, "object_id", nothing) == object_id
    ]
    length(matches) == 1 ||
        fail("bundle manifest", "must contain exactly one $object_id")
    return only(matches)
end

function _validate_object_copies(bundle, record)
    digest = get(record, "raw_sha256", "")
    occursin(HASH_PATTERN, digest) ||
        fail("bundle object", "invalid raw SHA-256")
    expected_bytes = get(record, "raw_byte_count", -1)
    expected_bytes isa Integer && expected_bytes >= 0 ||
        fail("bundle object", "invalid raw byte count")
    primary_relative =
        _safe_relative_path(record["primary_path"], "bundle object primary_path")
    replica_relative =
        _safe_relative_path(record["replica_path"], "bundle object replica_path")
    startswith(primary_relative, "replica-a/") ||
        fail("bundle object", "primary path must use replica-a")
    startswith(replica_relative, "replica-b/") ||
        fail("bundle object", "replica path must use replica-b")
    primary = _safe_file(joinpath(bundle, primary_relative))
    replica = _safe_file(joinpath(bundle, replica_relative))
    primary_bytes = read(primary)
    replica_bytes = read(replica)
    primary_bytes == replica_bytes ||
        fail("bundle object", "local replicas differ")
    length(primary_bytes) == expected_bytes ||
        fail(
        "bundle object",
        "raw byte count mismatch for $(record["object_id"]): " *
            "expected $expected_bytes, observed $(length(primary_bytes))",
        )
    sha256_hex(primary_bytes) == digest ||
        fail("bundle object", "raw SHA-256 mismatch")
    return primary_bytes
end

function _validate_storage_receipt(bundle, manifest)
    storage = get(manifest, "storage", nothing)
    storage isa AbstractDict ||
        fail("bundle manifest", "storage must be a table")
    relative = _safe_relative_path(
        get(storage, "local_storage_receipt_file", ""),
        "bundle storage receipt path",
    )
    relative == "local-storage-receipt.toml" ||
        fail("bundle storage receipt path", "must use the closed filename")
    document = TOML.parsefile(_safe_file(joinpath(bundle, relative)))
    artifact = get(document, "artifact", nothing)
    artifact isa AbstractDict ||
        fail("local storage receipt", "missing artifact table")
    get(artifact, "schema_version", "") == STORAGE_SCHEMA ||
        fail("local storage receipt", "schema version mismatch")
    get(artifact, "canonicalization", "") == STORAGE_CANONICALIZATION ||
        fail("local storage receipt", "canonicalization mismatch")
    embedded = get(artifact, "storage_receipt_sha256", "")
    occursin(HASH_PATTERN, embedded) ||
        fail("local storage receipt", "invalid embedded SHA-256")
    computed = sha256_hex(
        _canonical_toml_bytes(
            document;
            excluded_path = ("artifact", "storage_receipt_sha256"),
        ),
    )
    embedded == computed ||
        fail("local storage receipt", "embedded SHA-256 mismatch")
    embedded == get(storage, "local_storage_receipt_sha256", "") ||
        fail("local storage receipt", "manifest digest binding mismatch")
    policy = get(document, "storage", nothing)
    policy isa AbstractDict ||
        fail("local storage receipt", "missing storage table")
    get(policy, "storage_class", "") ==
        "TWO_LOCAL_IGNORED_REPLICAS_INTEGRITY_ONLY_NOT_DURABLE" ||
        fail("local storage receipt", "storage class mismatch")
    get(policy, "copy_ids", Any[]) == ["replica-a", "replica-b"] ||
        fail("local storage receipt", "copy IDs mismatch")
    get(policy, "local_copy_count", 0) == 2 ||
        fail("local storage receipt", "local copy count mismatch")
    get(policy, "external_durable_copy_count", 1) == 0 ||
        fail("local storage receipt", "cannot claim an external durable copy")
    for key in (
            "external_timestamp_verified",
            "retention_through_2031_attested",
            "git_commit_authorized",
        )
        get(policy, key, true) === false ||
            fail("local storage receipt", "$key must remain false")
    end
    expected = sort(
        [
            (
                String(row["object_id"]),
                String(row["raw_sha256"]),
                Int(row["raw_byte_count"]),
            ) for row in manifest["objects"]
        ],
    )
    rows = get(document, "objects", nothing)
    rows isa AbstractVector ||
        fail("local storage receipt", "objects must be an array")
    observed = sort(
        [
            (
                String(row["object_id"]),
                String(row["raw_sha256"]),
                Int(row["raw_byte_count"]),
            ) for row in rows
        ],
    )
    observed == expected ||
        fail("local storage receipt", "object inventory differs from manifest")
    all(value === false for value in values(document["gates"])) ||
        fail("local storage receipt", "all gates must remain false")
    return document
end

function _validate_capture_journal(bundle, manifest)
    capture = get(manifest, "capture", nothing)
    capture isa AbstractDict ||
        fail("capture journal", "manifest capture table is missing")
    preflight_relative = _safe_relative_path(
        get(capture, "journal_preflight_file", ""),
        "capture journal preflight path",
    )
    preflight_relative == "journal-preflight.toml" ||
        fail("capture journal", "unexpected preflight filename")
    preflight_path = _safe_file(joinpath(bundle, preflight_relative))
    preflight_digest = get(capture, "journal_preflight_sha256", "")
    occursin(HASH_PATTERN, preflight_digest) ||
        fail("capture journal", "invalid preflight SHA-256")
    file_sha256(preflight_path) == preflight_digest ||
        fail("capture journal", "preflight SHA-256 mismatch")
    preflight = TOML.parsefile(preflight_path)
    get(preflight, "schema_version", "") == JOURNAL_SCHEMA ||
        fail("capture journal", "preflight schema mismatch")
    get(preflight, "transaction_id", "") ==
        get(capture, "transaction_id", "") ||
        fail("capture journal", "preflight transaction mismatch")
    get(preflight, "phase", "") == get(manifest["event"], "phase", "") ||
        fail("capture journal", "preflight phase mismatch")
    get(preflight, "created_before_network", false) === true ||
        fail("capture journal", "preflight was not created before network")
    get(preflight, "append_only", false) === true ||
        fail("capture journal", "preflight is not append-only")
    all(value === false for value in values(preflight["gates"])) ||
        fail("capture journal", "preflight gates must remain false")

    inventory = get(capture, "attempt_journal_files", nothing)
    inventory isa AbstractVector ||
        fail("capture journal", "event-file inventory is missing")
    expected_paths = String[]
    for record in inventory
        record isa AbstractDict ||
            fail("capture journal", "event-file record must be a table")
        relative = _safe_relative_path(
            get(record, "path", ""),
            "capture journal event path",
        )
        startswith(relative, "attempts/") ||
            fail("capture journal", "event path must be under attempts")
        path = _safe_file(joinpath(bundle, relative))
        digest = get(record, "sha256", "")
        occursin(HASH_PATTERN, digest) ||
            fail("capture journal", "invalid event-file SHA-256")
        file_sha256(path) == digest ||
            fail("capture journal", "event-file SHA-256 mismatch")
        filesize(path) == get(record, "byte_count", -1) ||
            fail("capture journal", "event-file byte count mismatch")
        event = TOML.parsefile(path)
        get(event, "schema_version", "") == ATTEMPT_EVENT_SCHEMA ||
            fail("capture journal", "attempt-event schema mismatch")
        all(value === false for value in values(event["gates"])) ||
            fail("capture journal", "attempt-event gates must remain false")
        push!(expected_paths, relative)
    end
    length(unique(expected_paths)) == length(expected_paths) ||
        fail("capture journal", "duplicate event-file inventory path")
    attempts_directory = joinpath(bundle, "attempts")
    _reject_symlink_components(
        attempts_directory,
        "capture journal";
        require_leaf = true,
    )
    actual_paths = sort!(
        ["attempts/$name" for name in readdir(attempts_directory)],
    )
    sort(expected_paths) == actual_paths ||
        fail("capture journal", "event-file inventory is not exhaustive")

    attempts = get(capture, "attempts", nothing)
    attempts isa AbstractVector ||
        fail("capture journal", "attempt records are missing")
    attempted = length(attempts)
    get(capture, "attempted_request_count", -1) == attempted ||
        fail("capture journal", "attempted request count mismatch")
    get(capture, "network_request_count", -1) == attempted ||
        fail("capture journal", "network request count mismatch")
    completed = count(
        attempt -> get(attempt, "completed_response_body", false) === true,
        attempts,
    )
    validated = count(
        attempt -> get(attempt, "response_validation_passed", false) === true,
        attempts,
    )
    failed = [
        attempt for attempt in attempts if
            get(attempt, "failure_stage", "NONE") != "NONE"
    ]
    get(capture, "completed_response_count", -1) == completed ||
        fail("capture journal", "completed response count mismatch")
    get(capture, "validated_response_count", -1) == validated ||
        fail("capture journal", "validated response count mismatch")
    get(capture, "failed_attempt_count", -1) == length(failed) ||
        fail("capture journal", "failed attempt count mismatch")
    get(capture, "object_count", -1) == completed ||
        fail("capture journal", "object count differs from completed bodies")
    for (index, attempt) in enumerate(attempts)
        get(attempt, "attempt_index", 0) == index ||
            fail("capture journal", "attempt indexes are not contiguous")
        get(attempt, "object_id", "") ==
            capture["request_order"][index] ||
            fail("capture journal", "attempt order differs from request order")
        event_files = get(attempt, "event_files", nothing)
        event_files isa AbstractVector ||
            fail("capture journal", "attempt event list is missing")
        all(file -> file in expected_paths, event_files) ||
            fail("capture journal", "attempt references an unbound event file")
        any(endswith(String(file), "-started.toml") for file in event_files) ||
            fail("capture journal", "attempt lacks a start event")
        if get(attempt, "completed_response_body", false) === true
            any(
                endswith(String(file), "-completed.toml") for
                    file in event_files
            ) || fail("capture journal", "completed attempt lacks event")
        end
        if get(attempt, "response_validation_passed", false) === true
            any(
                endswith(String(file), "-validated.toml") for
                    file in event_files
            ) || fail("capture journal", "validated attempt lacks event")
        end
        if get(attempt, "failure_stage", "NONE") != "NONE"
            any(endswith(String(file), "-failed.toml") for file in event_files) ||
                fail("capture journal", "failed attempt lacks event")
        end
    end
    if isempty(failed)
        get(capture, "failed_object_id", "") == "NONE" ||
            fail("capture journal", "unexpected failed object")
        get(capture, "failed_attempt_index", -1) == 0 ||
            fail("capture journal", "unexpected failed attempt index")
    else
        get(capture, "failed_object_id", "") == first(failed)["object_id"] ||
            fail("capture journal", "failed object mismatch")
        get(capture, "failed_attempt_index", 0) ==
            first(failed)["attempt_index"] ||
            fail("capture journal", "failed attempt index mismatch")
    end
    return (preflight = preflight, attempts = attempts)
end

"""
    load_and_validate_bundle(bundle_path)

Revalidate a published local bundle, its manifest hash, both raw-object copies,
the self-generated receipt pins, the one-date receipts, and any paired record.
This establishes local integrity only; it does not turn the pins into
out-of-band authentication or the local copies into durable storage.
"""
function load_and_validate_bundle(bundle_path)
    bundle = abspath(String(bundle_path))
    isdir(bundle) || fail("bundle verification", "not a directory: $bundle")
    islink(bundle) && fail("bundle verification", "bundle may not be a symlink")
    manifest_path = _safe_file(joinpath(bundle, "capture-manifest.toml"))
    manifest_bytes = read(manifest_path)
    for copy_id in ("replica-a", "replica-b")
        replica = _safe_file(joinpath(bundle, copy_id, "capture-manifest.toml"))
        read(replica) == manifest_bytes ||
            fail("bundle manifest", "$copy_id manifest copy differs")
    end
    manifest = TOML.parsefile(manifest_path)
    _validate_manifest_hash(manifest)
    _validate_storage_receipt(bundle, manifest)
    _validate_capture_journal(bundle, manifest)
    objects = get(manifest, "objects", Any[])
    for record in objects
        record isa AbstractDict ||
            fail("bundle verification", "object record must be a table")
        _validate_object_copies(bundle, record)
    end
    result = get(manifest, "result", Dict())
    success = get(result, "success", false)
    no_revision_check =
        get(result, "status", "") ==
        "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
    raw_contract_incompatible =
        get(result, "status", "") ==
        "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
    if success && raw_contract_incompatible
        get(result, "raw_capture_complete", false) === true ||
            fail("bundle verification", "raw capture is not complete")
        get(result, "failure_code", "") ==
            "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT" ||
            fail("bundle verification", "compatibility blocker mismatch")
        "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT" in
            manifest["blockers"] ||
            fail("bundle verification", "compatibility blocker missing")
        get(result, "rate_receipt_file", "NONE") == "NONE" ||
            fail("bundle verification", "incompatible raw capture cannot contain rate receipt")
        get(result, "volume_receipt_file", "NONE") == "NONE" ||
            fail("bundle verification", "incompatible raw capture cannot contain volume receipt")
        get(result, "one_date_receipt_validated", true) === false ||
            fail("bundle verification", "incompatible raw capture cannot validate receipt")
        identities = get(manifest, "row_identity", nothing)
        identities isa AbstractVector && length(identities) == 2 ||
            fail("bundle verification", "raw identity records are incomplete")
        any(
            get(identity, "raw_current_state_present", true) === false for
                identity in identities
        ) || fail(
            "bundle verification",
            "compatibility status requires an absent raw currentState field",
        )
        for gate in values(manifest["gates"])
            gate === false ||
                fail("bundle verification", "all manifest gates must be false")
        end
        return (;
            bundle_path = bundle,
            manifest,
            validated_rate = nothing,
            validated_volume = nothing,
            pair = nothing,
        )
    elseif success && no_revision_check
        get(result, "rate_receipt_file", "NONE") == "NONE" ||
            fail("bundle verification", "unchanged check must not contain a rate receipt")
        get(result, "volume_receipt_file", "NONE") == "NONE" ||
            fail("bundle verification", "unchanged check must not contain a volume receipt")
        get(result, "revision_observed", true) === false ||
            fail("bundle verification", "unchanged check cannot mark a revision")
        get(result, "revision_receipt_created", true) === false ||
            fail("bundle verification", "unchanged check cannot create a revision receipt")
        get(result, "byte_equality_rate", false) === true ||
            fail("bundle verification", "unchanged rate bytes were not attested equal")
        get(result, "byte_equality_volume", false) === true ||
            fail("bundle verification", "unchanged volume bytes were not attested equal")
        predecessor_path = get(result, "predecessor_bundle", "NOT_APPLICABLE")
        predecessor_path == "NOT_APPLICABLE" &&
            fail("bundle verification", "unchanged check lacks predecessor")
        predecessor = _load_first_predecessor(predecessor_path)
        rate_record = _find_object_record(manifest, "rate_response")
        volume_record = _find_object_record(manifest, "volume_response")
        _validate_object_copies(bundle, rate_record) == predecessor.rate_bytes ||
            fail("bundle verification", "rate bytes differ from predecessor")
        _validate_object_copies(bundle, volume_record) == predecessor.volume_bytes ||
            fail("bundle verification", "volume bytes differ from predecessor")
        for gate in values(manifest["gates"])
            gate === false ||
                fail("bundle verification", "all manifest gates must be false")
        end
        return (;
            bundle_path = bundle,
            manifest,
            validated_rate = nothing,
            validated_volume = nothing,
            pair = nothing,
        )
    elseif success
        rate_file = get(result, "rate_receipt_file", "NONE")
        volume_file = get(result, "volume_receipt_file", "NONE")
        rate_file == "NONE" &&
            fail("bundle verification", "successful bundle lacks rate receipt")
        volume_file == "NONE" &&
            fail("bundle verification", "successful bundle lacks volume receipt")
        rate = TOML.parsefile(_safe_file(joinpath(bundle, rate_file)))
        volume = TOML.parsefile(_safe_file(joinpath(bundle, volume_file)))
        rate_pin = get(result, "rate_receipt_sha256", "")
        volume_pin = get(result, "volume_receipt_sha256", "")
        validated_rate = ReceiptContract.validate_receipt(rate, rate_pin)
        validated_volume =
            ReceiptContract.validate_receipt(volume, volume_pin)
        pair = ReceiptContract.pair_receipts(
            rate,
            rate_pin,
            volume,
            volume_pin,
        )
        pair.pair_status ==
            "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT" ||
            fail("bundle verification", "one-date pair did not validate")
        for gate in values(manifest["gates"])
            gate === false ||
                fail("bundle verification", "all manifest gates must be false")
        end
        return (;
            bundle_path = bundle,
            manifest,
            validated_rate,
            validated_volume,
            pair,
        )
    end
    return (;
        bundle_path = bundle,
        manifest,
        validated_rate = nothing,
        validated_volume = nothing,
        pair = nothing,
    )
end

function _load_first_predecessor(bundle_path)
    validated = load_and_validate_bundle(bundle_path)
    manifest = validated.manifest
    get(manifest["event"], "state_class_candidate", "") ==
        "FIRST_0900_STATE" ||
        fail("predecessor", "must be a FIRST_0900_STATE bundle")
    get(manifest["result"], "success", false) === true ||
        fail("predecessor", "first-state bundle did not validate successfully")
    rate_record = _find_object_record(manifest, "rate_response")
    volume_record = _find_object_record(manifest, "volume_response")
    rate_bytes = _validate_object_copies(validated.bundle_path, rate_record)
    volume_bytes = _validate_object_copies(validated.bundle_path, volume_record)
    return (;
        validated,
        rate_bytes,
        volume_bytes,
        rate_receipt_sha256 =
            manifest["result"]["rate_receipt_sha256"],
        volume_receipt_sha256 =
            manifest["result"]["volume_receipt_sha256"],
    )
end

function _ancestor_chain(path)
    current = abspath(String(path))
    chain = String[]
    while true
        push!(chain, current)
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    reverse!(chain)
    return chain
end

function _reject_symlink_components(path, location; require_leaf = false)
    absolute = abspath(String(path))
    for component in _ancestor_chain(absolute)
        islink(component) &&
            fail(location, "symbolic-link component rejected: $component")
        ispath(component) || continue
        isdir(component) ||
            fail(location, "non-directory path component rejected: $component")
    end
    require_leaf && !isdir(absolute) &&
        fail(location, "required directory is missing: $absolute")
    return absolute
end

function _ensure_directory_tree(path; leaf_mode = 0o755)
    absolute = abspath(String(path))
    chain = _ancestor_chain(absolute)
    for (index, component) in enumerate(chain)
        islink(component) &&
            fail("output preflight", "symbolic-link component rejected: $component")
        if ispath(component)
            isdir(component) ||
                fail(
                    "output preflight",
                    "non-directory path component rejected: $component",
                )
            continue
        end
        mode = index == length(chain) ? leaf_mode : 0o755
        mkdir(component; mode)
        islink(component) &&
            fail("output preflight", "created directory became a symlink: $component")
        isdir(component) ||
            fail("output preflight", "failed to create directory: $component")
    end
    _reject_symlink_components(
        absolute,
        "output preflight";
        require_leaf = true,
    )
    return absolute
end

function _contained_realpath(child, parent, location)
    child_real = realpath(_reject_symlink_components(
        child,
        location;
        require_leaf = true,
    ))
    parent_real = realpath(_reject_symlink_components(
        parent,
        location;
        require_leaf = true,
    ))
    relative = relpath(child_real, parent_real)
    pieces = splitpath(relative)
    (
        relative == "." ||
        (!isabspath(relative) && !isempty(pieces) && first(pieces) != "..")
    ) || fail(location, "$child_real escapes $parent_real")
    return child_real
end

function _contained_absent_candidate(candidate, parent, location)
    absolute = abspath(String(candidate))
    islink(absolute) &&
        fail(location, "symbolic-link candidate rejected: $absolute")
    ispath(absolute) &&
        fail(location, "append-only target already exists: $absolute")
    parent_real = realpath(_reject_symlink_components(
        parent,
        location;
        require_leaf = true,
    ))
    dirname(absolute) == abspath(String(parent)) ||
        fail(location, "candidate is not a direct child of its verified parent")
    canonical_candidate = normpath(joinpath(parent_real, basename(absolute)))
    relative = relpath(canonical_candidate, parent_real)
    pieces = splitpath(relative)
    (
        !isabspath(relative) &&
        !isempty(pieces) &&
        first(pieces) != ".."
    ) || fail(location, "candidate escapes verified parent")
    return canonical_candidate
end

function _assert_journal_layout(paths)
    root_real = realpath(_reject_symlink_components(
        paths.root,
        "journal layout";
        require_leaf = true,
    ))
    date_real =
        _contained_realpath(paths.date_root, paths.root, "journal layout")
    state_real =
        _contained_realpath(paths.state_root, paths.date_root, "journal layout")
    journal_real =
        _contained_realpath(paths.journal_path, paths.state_root, "journal layout")
    _contained_realpath(paths.replica_a, paths.journal_path, "journal layout")
    _contained_realpath(paths.replica_b, paths.journal_path, "journal layout")
    _contained_realpath(paths.attempts_path, paths.journal_path, "journal layout")
    root_real == realpath(paths.root) ||
        fail("journal layout", "output-root realpath changed")
    startswith(relpath(date_real, root_real), "..") &&
        fail("journal layout", "date root escapes output root")
    startswith(relpath(state_real, date_real), "..") &&
        fail("journal layout", "state root escapes date root")
    startswith(relpath(journal_real, state_real), "..") &&
        fail("journal layout", "journal escapes state root")
    return nothing
end

function _assert_publish_layout(paths)
    _assert_journal_layout(paths)
    _contained_absent_candidate(
        paths.final_path,
        paths.state_root,
        "atomic publish",
    )
    return nothing
end

function _preflight_capture_journal(output_root, phase, transaction_id)
    root = abspath(String(output_root))
    _ensure_directory_tree(root)
    date_root = joinpath(root, string(PUBLICATION_DATE))
    _ensure_directory_tree(date_root)
    state_root = joinpath(date_root, phase_state(phase))
    _ensure_directory_tree(state_root)
    final_path = joinpath(state_root, transaction_id)
    _contained_absent_candidate(final_path, state_root, "output preflight")
    journal_path = joinpath(state_root, ".journal-$transaction_id")
    islink(journal_path) &&
        fail("output preflight", "journal path is a symbolic link")
    ispath(journal_path) &&
        fail(
            "output preflight",
            "recoverable journal already exists; refusing overwrite: $journal_path",
        )
    mkdir(journal_path; mode = 0o700)
    chmod(journal_path, 0o700)
    replica_a = joinpath(journal_path, "replica-a")
    replica_b = joinpath(journal_path, "replica-b")
    attempts_path = joinpath(journal_path, "attempts")
    _ensure_directory_tree(replica_a; leaf_mode = 0o700)
    _ensure_directory_tree(replica_b; leaf_mode = 0o700)
    _ensure_directory_tree(attempts_path; leaf_mode = 0o700)
    _fsync_directory(journal_path)
    _fsync_directory(state_root)
    paths = (;
        root,
        date_root,
        state_root,
        final_path,
        journal_path,
        replica_a,
        replica_b,
        attempts_path,
    )
    _assert_publish_layout(paths)
    (stat(journal_path).mode & 0o077) == 0 ||
        fail("output preflight", "journal permissions are not private")
    preflight = Dict{String, Any}(
        "schema_version" => JOURNAL_SCHEMA,
        "transaction_id" => transaction_id,
        "phase" => phase,
        "publication_date" => string(PUBLICATION_DATE),
        "effective_date" => string(EFFECTIVE_DATE),
        "output_root_realpath" => realpath(root),
        "date_root_realpath" => realpath(date_root),
        "state_root_realpath" => realpath(state_root),
        "journal_realpath" => realpath(journal_path),
        "final_canonical_candidate" =>
            _contained_absent_candidate(
            final_path,
            state_root,
            "output preflight",
        ),
        "created_before_network" => true,
        "append_only" => true,
        "private_mode" => "0700",
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
    _write_exact(
        joinpath(journal_path, "journal-preflight.toml"),
        _toml_bytes(preflight),
    )
    _assert_publish_layout(paths)
    return paths
end

function _fsync(io)
    flush(io)
    result = ccall(:fsync, Cint, (Cint,), fd(io))
    result == 0 || fail("journal write", "fsync failed")
    return nothing
end

function _fsync_directory(path)
    directory = _reject_symlink_components(
        path,
        "journal directory sync";
        require_leaf = true,
    )
    flags =
        Base.Filesystem.JL_O_RDONLY |
        Base.Filesystem.JL_O_DIRECTORY |
        Base.Filesystem.JL_O_CLOEXEC
    io = Base.Filesystem.open(directory, flags)
    try
        result = ccall(:fsync, Cint, (Cint,), fd(io))
        result == 0 || fail("journal directory sync", "fsync failed")
    finally
        close(io)
    end
    return nothing
end

function _write_exact(path, bytes)
    absolute = abspath(String(path))
    (ispath(absolute) || islink(absolute)) &&
        fail("installation", "refuses to overwrite $absolute")
    parent = dirname(absolute)
    _reject_symlink_components(
        parent,
        "installation";
        require_leaf = true,
    )
    flags =
        Base.Filesystem.JL_O_WRONLY |
        Base.Filesystem.JL_O_CREAT |
        Base.Filesystem.JL_O_EXCL |
        Base.Filesystem.JL_O_CLOEXEC |
        Base.Filesystem.JL_O_NOFOLLOW
    io = Base.Filesystem.open(absolute, flags, 0o600)
    try
        write(io, bytes)
        _fsync(io)
    finally
        close(io)
    end
    islink(absolute) &&
        fail("installation", "written path became a symbolic link: $absolute")
    stat(absolute).nlink == 1 ||
        fail("installation", "written path is hard-linked: $absolute")
    read(absolute) == bytes ||
        fail("installation", "read-back failed at $absolute")
    _fsync_directory(parent)
    return absolute
end

function _normalized_captured_object(expected_object_id, object)
    return CapturedObject(
        object_id = String(expected_object_id),
        body = copy(object.body),
        requested_url = object.requested_url,
        final_url = object.final_url,
        http_status = object.http_status,
        content_type = object.content_type,
        content_encoding = object.content_encoding,
        response_headers = copy(object.response_headers),
        request_started_at_utc = object.request_started_at_utc,
        response_metadata_observed_at_utc =
            object.response_metadata_observed_at_utc,
        response_body_completed_at_utc =
            object.response_body_completed_at_utc,
    )
end

function _journal_preserve_object!(paths, expected_object_id, object)
    _assert_journal_layout(paths)
    normalized = _normalized_captured_object(expected_object_id, object)
    spec = OBJECT_SPECS[String(expected_object_id)]
    digest = sha256_hex(normalized.body)
    filename = "raw-sha256-$digest.$(spec.extension)"
    primary = joinpath(paths.replica_a, filename)
    replica = joinpath(paths.replica_b, filename)
    _write_exact(primary, normalized.body)
    _assert_journal_layout(paths)
    _write_exact(replica, normalized.body)
    _assert_journal_layout(paths)
    read(primary) == read(replica) ||
        fail("journal persistence", "raw replicas differ")
    return normalized
end

function _append_attempt_event!(
        paths,
        attempt_index,
        object_id,
        event,
        fields = Dict{String, Any}(),
    )
    event_name = lowercase(String(event))
    event_name in ("started", "completed", "validated", "failed") ||
        fail("attempt journal", "unsupported event $event")
    _assert_journal_layout(paths)
    filename =
        "$(lpad(string(attempt_index), 4, '0'))-$(object_id)-$event_name.toml"
    document = Dict{String, Any}(
        "schema_version" => ATTEMPT_EVENT_SCHEMA,
        "attempt_index" => attempt_index,
        "object_id" => String(object_id),
        "event" => uppercase(event_name),
        "recorded_at_utc" => timestamp(now(UTC)),
        "fields" => deepcopy(fields),
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
    path = joinpath(paths.attempts_path, filename)
    _write_exact(path, _toml_bytes(document))
    return "attempts/$filename"
end

function _journal_file_inventory(paths)
    files = Dict{String, Any}[]
    for name in sort!(readdir(paths.attempts_path))
        path = _safe_file(joinpath(paths.attempts_path, name))
        push!(
            files,
            Dict{String, Any}(
                "path" => "attempts/$name",
                "sha256" => file_sha256(path),
                "byte_count" => filesize(path),
            ),
        )
    end
    return files
end

function _bind_journal!(
        manifest,
        paths,
        attempts,
    )
    preflight_path =
        _safe_file(joinpath(paths.journal_path, "journal-preflight.toml"))
    capture = manifest["capture"]
    capture["journal_preflight_file"] = "journal-preflight.toml"
    capture["journal_preflight_sha256"] = file_sha256(preflight_path)
    capture["attempt_journal_files"] = _journal_file_inventory(paths)
    capture["attempts"] = deepcopy(attempts)
    capture["attempted_request_count"] = length(attempts)
    capture["network_request_count"] = length(attempts)
    capture["completed_response_count"] = count(
        attempt -> get(attempt, "completed_response_body", false) === true,
        attempts,
    )
    capture["validated_response_count"] = count(
        attempt -> get(attempt, "response_validation_passed", false) === true,
        attempts,
    )
    failed = [
        attempt for attempt in attempts if
            get(attempt, "failure_stage", "NONE") != "NONE"
    ]
    capture["failed_attempt_count"] = length(failed)
    capture["failed_object_id"] =
        isempty(failed) ? "NONE" : String(first(failed)["object_id"])
    capture["failed_attempt_index"] =
        isempty(failed) ? 0 : Int(first(failed)["attempt_index"])
    return manifest
end

function _install_bundle(
        paths,
        objects,
        storage_receipt,
        manifest,
        receipts,
    )
    _assert_publish_layout(paths)
    for object in objects
        record = _find_object_record(manifest, object.object_id)
        read(_safe_file(joinpath(paths.journal_path, record["primary_path"]))) ==
            object.body ||
            fail("atomic publish", "primary journal bytes differ")
        read(_safe_file(joinpath(paths.journal_path, record["replica_path"]))) ==
            object.body ||
            fail("atomic publish", "replica journal bytes differ")
    end
    storage_bytes = _toml_bytes(storage_receipt)
    _write_exact(
        joinpath(paths.journal_path, "local-storage-receipt.toml"),
        storage_bytes,
    )
    for (filename, receipt) in receipts
        _write_exact(
            joinpath(paths.journal_path, filename),
            _toml_bytes(receipt),
        )
    end
    manifest_bytes = _toml_bytes(manifest)
    _write_exact(
        joinpath(paths.journal_path, "capture-manifest.toml"),
        manifest_bytes,
    )
    _write_exact(
        joinpath(paths.replica_a, "capture-manifest.toml"),
        manifest_bytes,
    )
    _write_exact(
        joinpath(paths.replica_b, "capture-manifest.toml"),
        manifest_bytes,
    )
    _assert_publish_layout(paths)
    load_and_validate_bundle(paths.journal_path)
    _assert_publish_layout(paths)
    mv(paths.journal_path, paths.final_path)
    _fsync_directory(paths.state_root)
    _reject_symlink_components(
        paths.final_path,
        "atomic publish";
        require_leaf = true,
    )
    _contained_realpath(
        paths.final_path,
        paths.state_root,
        "atomic publish",
    )
    validated = load_and_validate_bundle(paths.final_path)
    return (;
        bundle_path = paths.final_path,
        manifest_path = joinpath(paths.final_path, "capture-manifest.toml"),
        validation = validated,
    )
end

function _mark_current_state_contract_incompatibility!(
        manifest;
        revision_observed,
    )
    blocker = "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT"
    blocker in manifest["blockers"] || push!(manifest["blockers"], blocker)
    sort!(manifest["blockers"])
    result = manifest["result"]
    result["status"] =
        "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
    result["success"] = true
    result["failure_code"] = blocker
    result["failure_detail"] =
        "The official raw EFFR row omits currentState; no value was fabricated and no one-date receipt or pair was created."
    result["pair_status"] =
        "NOT_CREATED_RAW_CURRENT_STATE_FIELD_ABSENT"
    result["revision_observed"] = revision_observed
    result["revision_receipt_created"] = false
    result["one_date_receipt_validated"] = false
    return nothing
end

function _evaluate_capture!(
        manifest,
        phase,
        objects,
        storage_receipt;
        predecessor_bundle,
    )
    by_id = Dict(object.object_id => object for object in objects)
    required_ids = Set(keys(OBJECT_SPECS))
    Set(keys(by_id)) == required_ids ||
        fail(
        "capture",
        "missing required objects: $(join(sort!(collect(setdiff(required_ids, Set(keys(by_id))))), ", "))",
    )
    manifest["result"]["raw_capture_complete"] = true
    rate_selected =
        _select_effr_row(by_id["rate_response"].body, "rate")
    volume_selected =
        _select_effr_row(by_id["volume_response"].body, "volume")
    manifest["row_identity"] = [
        _identity_record("rate", rate_selected),
        _identity_record("volume", volume_selected),
    ]
    rate_selected.revision == volume_selected.revision ||
        fail("capture", "rate and volume revision indicators differ")
    openapi_sha256 = sha256_hex(by_id["openapi_snapshot"].body)
    documentation_text =
        String(copy(by_id["api_documentation_snapshot"].body))
    occursin("url: './markets-api.yml'", documentation_text) ||
        fail(
        "API documentation snapshot",
        "does not contain the official relative markets-api.yml discovery binding",
    )
    api_documentation_sha256 =
        sha256_hex(by_id["api_documentation_snapshot"].body)
    terms_sha256 = sha256_hex(by_id["terms_snapshot"].body)
    holiday_sha256 = sha256_hex(by_id["holiday_snapshot"].body)
    manifest["governance"]["terms_snapshot_sha256"] = terms_sha256
    manifest["governance"]["api_documentation_url"] =
        API_DOCUMENTATION_URL
    manifest["governance"]["api_documentation_snapshot_sha256"] =
        api_documentation_sha256
    manifest["governance"]["openapi_discovery_binding"] =
        "OFFICIAL_API_DOCUMENTATION_LITERAL_URL_RELATIVE_MARKETS_API_YML"
    manifest["governance"]["openapi_url"] = OPENAPI_URL
    manifest["governance"]["openapi_snapshot_sha256"] = openapi_sha256
    manifest["governance"]["holiday_schedule_url"] = HOLIDAY_URL
    manifest["governance"]["holiday_snapshot_sha256"] = holiday_sha256
    storage_digest =
        storage_receipt["artifact"]["storage_receipt_sha256"]
    receipts = Dict{String, Dict{String, Any}}()

    if phase == "first"
        rate_selected.revision == "" ||
            fail(
            "first-state capture",
            "raw revision token is not empty; no first-state receipt created",
        )
        if !rate_selected.current_state_present ||
                !volume_selected.current_state_present
            _mark_current_state_contract_incompatibility!(
                manifest;
                revision_observed = false,
            )
            return receipts
        end
        rate_receipt = _build_one_date_receipt(
            by_id["rate_response"],
            rate_selected,
            "rate",
            "FIRST_0900_STATE";
            openapi_sha256,
            terms_sha256,
            storage_receipt_sha256 = storage_digest,
        )
        volume_receipt = _build_one_date_receipt(
            by_id["volume_response"],
            volume_selected,
            "volume",
            "FIRST_0900_STATE";
            openapi_sha256,
            terms_sha256,
            storage_receipt_sha256 = storage_digest,
        )
        pair = ReceiptContract.pair_receipts(
            rate_receipt,
            rate_receipt["receipt_sha256"],
            volume_receipt,
            volume_receipt["receipt_sha256"],
        )
        pair.pair_status ==
            "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT" ||
            fail("first-state capture", "rate-volume pair did not validate")
        rate_name =
            "rate-receipt-sha256-$(rate_receipt["receipt_sha256"]).toml"
        volume_name =
            "volume-receipt-sha256-$(volume_receipt["receipt_sha256"]).toml"
        receipts[rate_name] = rate_receipt
        receipts[volume_name] = volume_receipt
        result = manifest["result"]
        result["status"] =
            "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
        result["success"] = true
        result["failure_code"] = "NONE"
        result["failure_detail"] = "NONE"
        result["rate_receipt_file"] = rate_name
        result["volume_receipt_file"] = volume_name
        result["rate_receipt_sha256"] =
            rate_receipt["receipt_sha256"]
        result["volume_receipt_sha256"] =
            volume_receipt["receipt_sha256"]
        result["pair_status"] = pair.pair_status
        result["one_date_receipt_validated"] = true
        return receipts
    end

    predecessor_bundle === nothing &&
        fail("revision check", "predecessor bundle is required")
    predecessor = _load_first_predecessor(predecessor_bundle)
    result = manifest["result"]
    result["predecessor_bundle"] =
        abspath(String(predecessor_bundle))
    result["predecessor_rate_receipt_sha256"] =
        predecessor.rate_receipt_sha256
    result["predecessor_volume_receipt_sha256"] =
        predecessor.volume_receipt_sha256
    rate_equal =
        by_id["rate_response"].body == predecessor.rate_bytes
    volume_equal =
        by_id["volume_response"].body == predecessor.volume_bytes
    result["byte_equality_rate"] = rate_equal
    result["byte_equality_volume"] = volume_equal
    if rate_selected.revision == ""
        if rate_equal && volume_equal
            result["status"] =
                "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
            result["success"] = true
            result["failure_code"] = "NONE"
            result["failure_detail"] =
                "NONE"
            result["pair_status"] = "NOT_APPLICABLE_NO_REVISION"
            result["revision_observed"] = false
            result["revision_receipt_created"] = false
            return receipts
        end
        fail(
            "revision check",
            "bytes changed without closed revision token r; no revision receipt created",
        )
    end
    rate_selected.revision == "r" ||
        fail("revision check", "unsupported revision token")
    (!rate_equal || !volume_equal) ||
        fail(
            "revision check",
            "revision token r appeared without any response-byte change",
        )
    if !rate_selected.current_state_present ||
            !volume_selected.current_state_present
        _mark_current_state_contract_incompatibility!(
            manifest;
            revision_observed = true,
        )
        return receipts
    end
    predecessor.rate_receipt_sha256 == "NONE" &&
        fail(
        "revision check",
        "cannot create a linked revision receipt without a validated predecessor rate receipt",
    )
    predecessor.volume_receipt_sha256 == "NONE" &&
        fail(
        "revision check",
        "cannot create a linked revision receipt without a validated predecessor volume receipt",
    )
    rate_receipt = _build_one_date_receipt(
        by_id["rate_response"],
        rate_selected,
        "rate",
        "SAME_DAY_1430_REVISION";
        openapi_sha256,
        terms_sha256,
        storage_receipt_sha256 = storage_digest,
        predecessor = predecessor.rate_receipt_sha256,
    )
    volume_receipt = _build_one_date_receipt(
        by_id["volume_response"],
        volume_selected,
        "volume",
        "SAME_DAY_1430_REVISION";
        openapi_sha256,
        terms_sha256,
        storage_receipt_sha256 = storage_digest,
        predecessor = predecessor.volume_receipt_sha256,
    )
    pair = ReceiptContract.pair_receipts(
        rate_receipt,
        rate_receipt["receipt_sha256"],
        volume_receipt,
        volume_receipt["receipt_sha256"],
    )
    pair.pair_status ==
        "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT" ||
        fail("revision check", "rate-volume revision pair did not validate")
    rate_name =
        "rate-receipt-sha256-$(rate_receipt["receipt_sha256"]).toml"
    volume_name =
        "volume-receipt-sha256-$(volume_receipt["receipt_sha256"]).toml"
    receipts[rate_name] = rate_receipt
    receipts[volume_name] = volume_receipt
    result["status"] =
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE"
    result["success"] = true
    result["failure_code"] = "NONE"
    result["failure_detail"] = "NONE"
    result["rate_receipt_file"] = rate_name
    result["volume_receipt_file"] = volume_name
    result["rate_receipt_sha256"] = rate_receipt["receipt_sha256"]
    result["volume_receipt_sha256"] =
        volume_receipt["receipt_sha256"]
    result["pair_status"] = pair.pair_status
    result["revision_observed"] = true
    result["revision_receipt_created"] = true
    result["one_date_receipt_validated"] = true
    return receipts
end

function _evaluation_failure_object_id(error)
    message = lowercase(sprint(showerror, error))
    occursin("volume", message) && return "volume_response"
    occursin("api documentation", message) &&
        return "api_documentation_snapshot"
    occursin("openapi", message) && return "openapi_snapshot"
    occursin("terms", message) && return "terms_snapshot"
    occursin("holiday", message) && return "holiday_snapshot"
    return "rate_response"
end

function _record_attempt_failure!(
        paths,
        attempts,
        object_id,
        stage,
        error,
    )
    matches = [
        attempt for attempt in attempts if
            attempt["object_id"] == object_id
    ]
    isempty(matches) &&
        fail("attempt journal", "cannot bind failure to $object_id")
    attempt = only(matches)
    attempt["failure_stage"] = String(stage)
    attempt["failure_code"] = _failure_code(error)
    attempt["failure_detail"] = sprint(showerror, error)
    attempt["outcome"] = "FAILED_FAIL_CLOSED"
    event_file = _append_attempt_event!(
        paths,
        attempt["attempt_index"],
        object_id,
        "failed",
        Dict{String, Any}(
            "failure_stage" => String(stage),
            "failure_code" => attempt["failure_code"],
            "failure_detail" => attempt["failure_detail"],
            "completed_response_body" =>
                attempt["completed_response_body"],
        ),
    )
    push!(attempt["event_files"], event_file)
    return attempt
end

"""
    acquire_day_zero(output_root; phase, transaction_id, ...)

Perform the bounded 2026-08-07 prospective request set. The function checks
the host clock before network access, preserves every complete response body in
two ignored local copies before treating parsed fields as evidence, and
installs a typed fail-closed bundle even when schema or receipt validation
fails after capture. A revision check with byte-identical empty-token responses
creates an immutable check record and deliberately creates no revision receipt.
"""
function acquire_day_zero(
        output_root;
        phase,
        transaction_id,
        predecessor_bundle = nothing,
        clock = () -> now(UTC),
        fetch = _live_fetch,
    )
    selected_phase = expect_phase(phase)
    transaction = validate_transaction_id(transaction_id)
    selected_phase == "revision-check" && predecessor_bundle === nothing &&
        fail(
        "predecessor_bundle",
        "is required for the revision-check phase",
    )
    bindings = _validate_source_bindings()
    observed = clock()
    observed isa DateTime ||
        fail("capture clock", "must return a DateTime")
    window = phase_window(selected_phase)
    window.start <= observed <= window.deadline ||
        fail(
        "capture clock",
        "must start inside [$(timestamp(window.start)), $(timestamp(window.deadline))]",
    )
    paths =
        _preflight_capture_journal(output_root, selected_phase, transaction)
    objects = CapturedObject[]
    attempts = Dict{String, Any}[]
    capture_error = nothing
    for object_id in (
            "rate_response",
            "volume_response",
            "api_documentation_snapshot",
            "openapi_snapshot",
            "terms_snapshot",
            "holiday_snapshot",
        )
        spec = (
            object_id = object_id,
            requested_url = OBJECT_SPECS[object_id].url,
        )
        attempt_index = length(attempts) + 1
        attempt = Dict{String, Any}(
            "attempt_index" => attempt_index,
            "object_id" => object_id,
            "requested_url" => spec.requested_url,
            "completed_response_body" => false,
            "response_validation_passed" => false,
            "observed_object_id" => "NOT_RETURNED",
            "raw_sha256" => "NONE",
            "raw_byte_count" => 0,
            "outcome" => "ATTEMPT_STARTED",
            "failure_stage" => "NONE",
            "failure_code" => "NONE",
            "failure_detail" => "NONE",
            "event_files" => String[],
        )
        push!(attempts, attempt)
        push!(
            attempt["event_files"],
            _append_attempt_event!(
                paths,
                attempt_index,
                object_id,
                "started",
                Dict{String, Any}(
                    "requested_url" => spec.requested_url,
                    "http_method" => "GET",
                ),
            ),
        )
        failure_stage = "TRANSPORT_OR_FETCHER"
        try
            fetched = fetch(spec)
            fetched isa CapturedObject ||
                fail("capture fetcher", "must return CapturedObject")
            attempt["observed_object_id"] = fetched.object_id
            failure_stage = "RAW_JOURNAL_PERSISTENCE"
            object =
                _journal_preserve_object!(paths, object_id, fetched)
            push!(objects, object)
            attempt["completed_response_body"] = true
            attempt["raw_sha256"] = sha256_hex(object.body)
            attempt["raw_byte_count"] = length(object.body)
            attempt["outcome"] = "COMPLETED_RESPONSE_BODY_PERSISTED"
            push!(
                attempt["event_files"],
                _append_attempt_event!(
                    paths,
                    attempt_index,
                    object_id,
                    "completed",
                    Dict{String, Any}(
                        "raw_sha256" => attempt["raw_sha256"],
                        "raw_byte_count" => attempt["raw_byte_count"],
                        "primary_path" =>
                            _object_record(
                            object,
                            OBJECT_SPECS[object_id].extension,
                        )["primary_path"],
                        "replica_path" =>
                            _object_record(
                            object,
                            OBJECT_SPECS[object_id].extension,
                        )["replica_path"],
                    ),
                ),
            )
            failure_stage = "POST_BODY_RESPONSE_VALIDATION"
            fetched.object_id == object_id ||
                fail(
                    "capture fetcher",
                    "returned object ID $(fetched.object_id) for $object_id",
                )
            _validate_captured_object(object, selected_phase)
            attempt["response_validation_passed"] = true
            attempt["outcome"] = "COMPLETED_RESPONSE_VALIDATED"
            push!(
                attempt["event_files"],
                _append_attempt_event!(
                    paths,
                    attempt_index,
                    object_id,
                    "validated",
                    Dict{String, Any}(
                        "response_validation_passed" => true,
                    ),
                ),
            )
        catch error
            capture_error = error isa DayZeroAcquisitionError ?
                error :
                DayZeroAcquisitionError(
                "live $object_id: request failed in injected transport",
            )
            _record_attempt_failure!(
                paths,
                attempts,
                object_id,
                failure_stage,
                capture_error,
            )
            failure_stage == "RAW_JOURNAL_PERSISTENCE" &&
                throw(capture_error)
            break
        end
    end
    storage_receipt = _storage_receipt(objects)
    manifest = _base_manifest(
        selected_phase,
        transaction,
        bindings,
        objects,
        storage_receipt,
    )
    receipts = Dict{String, Dict{String, Any}}()
    if capture_error === nothing
        try
            receipts = _evaluate_capture!(
                manifest,
                selected_phase,
                objects,
                storage_receipt;
                predecessor_bundle,
            )
        catch error
            capture_error = error
            _record_attempt_failure!(
                paths,
                attempts,
                _evaluation_failure_object_id(error),
                "SEMANTIC_OR_RECEIPT_EVALUATION",
                error,
            )
        end
    end
    if capture_error !== nothing
        manifest["result"]["status"] =
            "FAIL_CLOSED_RAW_BYTES_RETAINED_NO_RECEIPT_CLAIM"
        manifest["result"]["success"] = false
        manifest["result"]["failure_code"] =
            _failure_code(capture_error)
        manifest["result"]["failure_detail"] =
            sprint(showerror, capture_error)
        manifest["result"]["revision_receipt_created"] = false
        empty!(receipts)
    end
    manifest["storage"]["two_local_copies_verified"] = true
    _bind_journal!(manifest, paths, attempts)
    _manifest_digest!(manifest)
    installed = _install_bundle(
        paths,
        objects,
        storage_receipt,
        manifest,
        receipts,
    )
    return (;
        installed...,
        status = manifest["result"]["status"],
        success = manifest["result"]["success"],
        raw_capture_installed = true,
        raw_capture_complete =
            manifest["result"]["raw_capture_complete"],
        one_date_receipt_validated =
            manifest["result"]["one_date_receipt_validated"],
        failure_code = manifest["result"]["failure_code"],
        failure_detail = manifest["result"]["failure_detail"],
    )
end

end
