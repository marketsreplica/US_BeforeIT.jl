module USEFFRCaptureContract

using Dates
using SHA
using TOML

export EFFRCaptureContractError,
    MAX_CURRENT_LOOKBACK_DAYS,
    MAX_LATER_CORRECTION_LAG_DAYS,
    MAX_RECEIPT_BYTES,
    MAX_STRICT_PUBLICATION_LAG_DAYS,
    MAX_TERMS_SNAPSHOT_AGE_DAYS,
    SCHEMA_VERSION,
    canonical_receipt_sha256,
    pair_receipts,
    trusted_contract,
    validate_receipt

const SCHEMA_VERSION =
    "beforeit-us-effr-one-effective-date-capture-receipt.v2"
const CANONICALIZATION =
    "sorted_toml_excluding_receipt_sha256.v1"
const ENDPOINT =
    "https://markets.newyorkfed.org/api/rates/all/search.json"
const FINAL_HOST = "markets.newyorkfed.org"
const TERMS_URL = "https://www.newyorkfed.org/privacy/termsofuse"
const SOURCE_AUTHORITY = "Federal Reserve Bank of New York"
const SOURCE_ID = "NYFED_MARKETS_API"
const SERIES_ID = "EFFR"
const CONCEPT_REGIME = "POST_2016_FR2420_VOLUME_WEIGHTED_MEDIAN"
const MAX_RECEIPT_BYTES = 256_000
const MAX_RESPONSE_BYTES = 8_000_000
const MAX_STRICT_PUBLICATION_LAG_DAYS = 4
const MAX_LATER_CORRECTION_LAG_DAYS = 31
const MAX_CURRENT_LOOKBACK_DAYS = 7_305
const MAX_TERMS_SNAPSHOT_AGE_DAYS = 31
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const DATE_PATTERN = r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
const TIMESTAMP_PATTERN =
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
const RECEIPT_TOP_KEYS = (
    "schema_version",
    "receipt_id",
    "source",
    "observation",
    "request",
    "response",
    "artifact",
    "raw_fields",
    "classification",
    "governance",
    "lineage",
    "gates",
    "receipt_sha256",
)
const SOURCE_KEYS = (
    "authority",
    "source_id",
    "series_id",
    "evidence_track",
    "concept_regime",
    "route_class",
    "historical_vintage_claim",
)
const OBSERVATION_KEYS = (
    "effective_date",
    "publication_date",
    "publication_utc_offset",
    "report_type",
    "state_class",
    "scheduled_publication_window",
    "pair_key",
)
const REQUEST_KEYS = (
    "endpoint",
    "canonical_query",
    "requested_url",
    "request_started_at_utc",
    "secret_ref",
)
const RESPONSE_KEYS = (
    "response_headers_at_utc",
    "response_body_completed_at_utc",
    "availability_upper_bound_utc",
    "http_status",
    "final_host",
    "final_url",
    "redirect_count",
    "redirect_chain",
    "headers_complete",
    "content_type",
    "content_encoding",
    "content_length",
)
const ARTIFACT_KEYS = (
    "raw_sha256",
    "openapi_sha256",
    "durable_storage_locator",
    "durable_storage_receipt_sha256",
)
const RAW_FIELD_KEYS = (
    "effectiveDate",
    "type",
    "percentRate",
    "percentPercentile1",
    "percentPercentile25",
    "percentPercentile75",
    "percentPercentile99",
    "targetRateFrom",
    "targetRateTo",
    "volumeInBillions",
    "footnote",
    "revisionIndicator",
    "currentState",
)
const CLASSIFICATION_KEYS = (
    "revision_class",
    "footnote_class",
    "rate_report_volume_class",
    "unsupported_blank_class",
    "current_state_class",
    "schema_class",
    "schema_mismatch_detail",
    "quarantine_class",
    "adjudication_state",
    "evidence_locator",
    "blockers",
)
const GOVERNANCE_KEYS = (
    "terms_url",
    "terms_snapshot_sha256",
    "terms_snapshot_date",
    "terms_review_decision",
    "attribution_requirement",
    "disclaimer_requirement",
    "redistribution_scope",
    "secret_ref",
)
const LINEAGE_KEYS = (
    "predecessor_receipt_sha256",
    "supersedes_receipt_sha256",
    "supersession_status",
)
const GATE_KEYS = (
    "historical_first_byte_proven",
    "origin_admissible",
    "empirical_forecast_allowed",
    "source_inventory_mutation_allowed",
    "promotion_eligible",
    "production_scoring_allowed",
    "readiness",
    "current_api_proves_historical_vintage",
)
const STATE_CLASSES = (
    "FIRST_0900_STATE",
    "SAME_DAY_1430_REVISION",
    "LATER_CORRECTION",
    "ALFRED_DATE_STATE",
    "CURRENT_STATE",
)
const CAPTURABLE_STATE_CLASSES = (
    "FIRST_0900_STATE",
    "SAME_DAY_1430_REVISION",
    "LATER_CORRECTION",
    "CURRENT_STATE",
)
const REPORT_TYPES = ("rate", "volume")
const EVIDENCE_TRACKS = (
    "STRICT_FIRST_PUBLIC_BYTES",
    "CURRENT_REVISED_PROXY",
)
const PUBLICATION_WINDOWS = Dict(
    "FIRST_0900_STATE" => "NYFED_APPROX_0900_ET",
    "SAME_DAY_1430_REVISION" => "NYFED_APPROX_1430_ET",
    "LATER_CORRECTION" => "EXTRAORDINARY_LATER_CORRECTION",
    "CURRENT_STATE" => "CURRENT_API_OBSERVATION_TIME",
)
const REVISION_CLASSES = Dict(
    "" => "NOT_REVISED_RAW_EMPTY_TOKEN",
    "r" => "DOCUMENTED_REVISED_RAW_TOKEN_WITH_SCHEMA_MISMATCH",
)
const FOOTNOTE_CLASSES = Dict(
    "" => "NO_FOOTNOTE_RAW_EMPTY_TOKEN",
    "1" => "DOCUMENTED_REDUCED_VOLUME",
    "2" => "DOCUMENTED_BROKER_CONTINGENCY",
    "3" => "DOCUMENTED_PRIOR_DAY_REPUBLICATION",
)
const NUMERIC_RATE_FIELDS = (
    "percentRate",
    "percentPercentile1",
    "percentPercentile25",
    "percentPercentile75",
    "percentPercentile99",
    "targetRateFrom",
    "targetRateTo",
)
const TERMS_DECISIONS = (
    "PENDING_PROJECT_SPECIFIC_REVIEW",
    "APPROVED_FOR_BOUNDED_CAPTURE",
    "REJECTED",
)
const REDISTRIBUTION_SCOPES = (
    "INTERNAL_RESEARCH_ONLY",
    "PUBLIC_DERIVED_ONLY",
    "PROHIBITED",
)
const APPROVED_ATTRIBUTION =
    "ATTRIBUTION_REQUIRED_FEDERAL_RESERVE_BANK_OF_NEW_YORK"
const APPROVED_DISCLAIMER =
    "REFERENCE_RATE_DISCLAIMER_REQUIRED_FOR_DERIVED_USE"
const APPROVED_PUBLIC_ATTRIBUTION =
    "ATTRIBUTION_AND_DERIVATIVE_LABEL_REQUIRED_FEDERAL_RESERVE_BANK_OF_NEW_YORK"
const APPROVED_PUBLIC_DISCLAIMER =
    "REFERENCE_RATE_DISCLAIMER_REQUIRED_FOR_PUBLIC_DERIVED_USE"
const PENDING_ATTRIBUTION = "ATTRIBUTION_REQUIREMENT_PENDING_REVIEW"
const PENDING_DISCLAIMER = "DISCLAIMER_REQUIREMENT_PENDING_REVIEW"
const REJECTED_ATTRIBUTION = "USE_REJECTED_ATTRIBUTION_NOT_APPLICABLE"
const REJECTED_DISCLAIMER = "USE_REJECTED_DISCLAIMER_NOT_APPLICABLE"
const SCHEMA_CLASSES = (
    "PINNED_CURRENT_API_EXACT_FIELDSET",
    "DOCUMENTED_OPENAPI_EXAMPLE_MISMATCH_PINNED_FIELDSET",
    "SCHEMA_MISMATCH_QUARANTINED",
)
const QUARANTINE_CLASSES = (
    "NOT_QUARANTINED",
    "QUARANTINED_PENDING_MATCHED_STATE_REVIEW",
)
const ALLOWED_BLOCKERS = Set(
    (
        "CURRENT_API_NOT_HISTORICAL_VINTAGE",
        "EMPIRICAL_EXECUTION_FORBIDDEN",
        "HISTORICAL_FIRST_BYTES_UNPROVEN",
        "MATCHED_STATE_REVIEW_REQUIRED",
        "OPENAPI_EXAMPLE_MISMATCH_PRESERVED",
        "ORIGIN_ADMISSION_FORBIDDEN",
        "PRODUCTION_USE_FORBIDDEN",
        "PROMOTION_FORBIDDEN",
        "RATE_VOLUME_PAIR_NOT_YET_VALIDATED",
        "READINESS_FALSE",
        "SCHEMA_MISMATCH",
        "TERMS_REVIEW_REJECTED",
        "TERMS_REVIEW_PENDING",
        "UNSUPPORTED_BLANK_UNKNOWN_NOT_ZERO",
    ),
)
const ALWAYS_FALSE_GATES = NamedTuple{Symbol.(GATE_KEYS)}(
    ntuple(_ -> false, length(GATE_KEYS)),
)
const STATE_TAXONOMY = (
    (
        state_class = "FIRST_0900_STATE",
        source_route = "NYFED_PROSPECTIVE_CAPTURE",
        vintage_scope = "INTRADAY_FIRST_STATE_CANDIDATE",
        overwrite_policy = "APPEND_ONLY_NEVER_OVERWRITE",
    ),
    (
        state_class = "SAME_DAY_1430_REVISION",
        source_route = "NYFED_PROSPECTIVE_CAPTURE",
        vintage_scope = "INTRADAY_SAME_DAY_REVISION",
        overwrite_policy = "APPEND_ONLY_POINTER_TO_PREDECESSOR",
    ),
    (
        state_class = "LATER_CORRECTION",
        source_route = "NYFED_PROSPECTIVE_CAPTURE",
        vintage_scope = "EXTRAORDINARY_LATER_CORRECTION",
        overwrite_policy = "APPEND_ONLY_POINTER_TO_PREDECESSOR",
    ),
    (
        state_class = "ALFRED_DATE_STATE",
        source_route = "ALFRED_EFFR_GOVERNANCE_BLOCKED",
        vintage_scope = "DATE_LEVEL_VINTAGE_NOT_INTRADAY",
        overwrite_policy = "APPEND_ONLY_NEVER_COERCE_TO_INTRADAY",
    ),
    (
        state_class = "CURRENT_STATE",
        source_route = "NYFED_CURRENT_API",
        vintage_scope = "CURRENT_STATE_FLAG_NOT_VINTAGE",
        overwrite_policy = "APPEND_ONLY_NEVER_CLAIM_HISTORICAL_STATE",
    ),
)

struct EFFRCaptureContractError <: Exception
    message::String
end

Base.showerror(io::IO, error::EFFRCaptureContractError) =
    print(io, error.message)

fail(location, message) =
    throw(EFFRCaptureContractError("$location: $message"))

function _expect_exact_keys(value, expected, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    actual = Set(String.(keys(value)))
    wanted = Set(String.(expected))
    missing = sort!(collect(setdiff(wanted, actual)))
    unknown = sort!(collect(setdiff(actual, wanted)))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown keys: $(join(unknown, ", "))")
    return value
end

function _expect_string(value, location; allow_empty = false, maximum = 8_192)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    (!isempty(text) || allow_empty) ||
        fail(location, "must not be empty")
    ncodeunits(text) <= maximum ||
        fail(location, "exceeds the $maximum-byte limit")
    return text
end

function _expect_exact(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function _expect_member(value, allowed, location; allow_empty = false)
    text = _expect_string(value, location; allow_empty)
    text in allowed ||
        fail(location, "is not in the closed vocabulary")
    return text
end

function _expect_bool(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function _expect_integer(value, location; minimum = typemin(Int), maximum = typemax(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer, not a Boolean")
    number = try
        Int(value)
    catch
        fail(location, "does not fit in Int")
    end
    minimum <= number <= maximum ||
        fail(location, "must be between $minimum and $maximum")
    return number
end

function _expect_hash(value, location)
    text = _expect_string(value, location; maximum = 64)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

function _expect_date(value, location)
    text = _expect_string(value, location; maximum = 10)
    occursin(DATE_PATTERN, text) ||
        fail(location, "must use YYYY-MM-DD")
    date = tryparse(Date, text)
    date === nothing && fail(location, "must be a valid date")
    string(date) == text || fail(location, "must be canonical")
    return date
end

function _expect_timestamp(value, location)
    text = _expect_string(value, location; maximum = 24)
    occursin(TIMESTAMP_PATTERN, text) ||
        fail(location, "must use RFC 3339 UTC milliseconds")
    parsed = tryparse(DateTime, text[1:(end - 1)], TIMESTAMP_FORMAT)
    parsed === nothing && fail(location, "must be a valid timestamp")
    return parsed
end

function _first_sunday(year, month)
    first = Date(year, month, 1)
    return first + Day(mod(7 - dayofweek(first), 7))
end

function _expected_eastern_offset(publication_date)
    daylight_start = _first_sunday(year(publication_date), 3) + Day(7)
    standard_start = _first_sunday(year(publication_date), 11)
    if daylight_start <= publication_date < standard_start
        return ("-04:00", -4 * 60)
    end
    return ("-05:00", -5 * 60)
end

function _expect_weekday(date, location)
    dayofweek(date) <= 5 ||
        fail(location, "must be a Monday-through-Friday date")
    return date
end

function _validate_publication_lag(effective_date, publication_date, state_class)
    lag = Dates.value(publication_date - effective_date)
    if state_class in ("FIRST_0900_STATE", "SAME_DAY_1430_REVISION")
        1 <= lag <= MAX_STRICT_PUBLICATION_LAG_DAYS ||
            fail(
            "receipt.observation.publication_date",
            "strict intraday state requires a 1-$MAX_STRICT_PUBLICATION_LAG_DAYS day publication lag",
        )
    elseif state_class == "LATER_CORRECTION"
        2 <= lag <= MAX_LATER_CORRECTION_LAG_DAYS ||
            fail(
            "receipt.observation.publication_date",
            "later correction requires a 2-$MAX_LATER_CORRECTION_LAG_DAYS day lag",
        )
    elseif state_class == "CURRENT_STATE"
        1 <= lag <= MAX_CURRENT_LOOKBACK_DAYS ||
            fail(
            "receipt.observation.publication_date",
            "current state requires a 1-$MAX_CURRENT_LOOKBACK_DAYS day lookback",
        )
    end
    return lag
end

function _local_datetime(timestamp, utc_offset_minutes)
    return timestamp + Minute(utc_offset_minutes)
end

function _validate_capture_clock(observation, request, response)
    offset_minutes = observation.publication_utc_offset_minutes
    publication_date = Date(observation.publication_date)
    local_times = (
        _local_datetime(request.request_started, offset_minutes),
        _local_datetime(
            _expect_timestamp(
                response.response_headers_at_utc,
                "receipt.response.response_headers_at_utc",
            ),
            offset_minutes,
        ),
        _local_datetime(
            _expect_timestamp(
                response.response_body_completed_at_utc,
                "receipt.response.response_body_completed_at_utc",
            ),
            offset_minutes,
        ),
    )
    all(Date(timestamp) == publication_date for timestamp in local_times) ||
        fail(
        "receipt.response",
        "request, headers, and completion must share the declared New York publication date",
    )
    local_clock_times = Time.(local_times)
    if observation.state_class == "FIRST_0900_STATE"
        all(
            Time(9, 0) <= timestamp < Time(14, 30) for
                timestamp in local_clock_times
        ) ||
            fail(
            "receipt.request.request_started_at_utc",
            "FIRST_0900_STATE must complete inside [09:00,14:30) New York time",
        )
    elseif observation.state_class == "SAME_DAY_1430_REVISION"
        all(Time(14, 30) <= timestamp for timestamp in local_clock_times) ||
            fail(
            "receipt.request.request_started_at_utc",
            "SAME_DAY_1430_REVISION must occur inside [14:30,24:00) New York time",
        )
    end
    return nothing
end

function _expect_measure(value, location; minimum, maximum)
    value isa Real && !(value isa Bool) ||
        fail(location, "must be a real number, not a Boolean")
    number = try
        Float64(value)
    catch
        fail(location, "cannot be represented as Float64")
    end
    isfinite(number) || fail(location, "must be finite")
    minimum <= number <= maximum ||
        fail(location, "must be between $minimum and $maximum")
    return number
end

function _expect_measure_or_blank(value, location; minimum, maximum)
    value == "" && return ""
    return _expect_measure(value, location; minimum, maximum)
end

function _validate_non_decreasing(values, fields, location)
    for index in 1:(length(values) - 1)
        left = values[index]
        right = values[index + 1]
        if left isa Float64 && right isa Float64
            left <= right ||
                fail(
                location,
                "$(fields[index]) must not exceed $(fields[index + 1])",
            )
        end
    end
    return nothing
end

function _canonical_bytes(receipt)
    receipt isa AbstractDict || fail("receipt", "must be a table")
    document = deepcopy(receipt)
    haskey(document, "receipt_sha256") ||
        fail("receipt.receipt_sha256", "is required before hashing")
    delete!(document, "receipt_sha256")
    io = IOBuffer()
    try
        TOML.print(io, document; sorted = true)
    catch error
        fail("receipt", "cannot be canonically encoded: $(sprint(showerror, error))")
    end
    bytes = take!(io)
    length(bytes) <= MAX_RECEIPT_BYTES ||
        fail("receipt", "canonical encoding exceeds $MAX_RECEIPT_BYTES bytes")
    return bytes
end

"""
    canonical_receipt_sha256(receipt)

Hash a receipt after removing its embedded `receipt_sha256`. This helper does
not authenticate the receipt. `validate_receipt` separately requires the same
digest from an out-of-band caller pin, so rewriting the document and its own
hash cannot preserve trust.
"""
canonical_receipt_sha256(receipt) =
    bytes2hex(sha256(_canonical_bytes(receipt)))

function _expected_query(effective_date, report_type)
    return "endDate=$effective_date&startDate=$effective_date&type=$report_type"
end

function _expected_pair_key(effective_date, revision_token)
    encoded = isempty(revision_token) ? "EMPTY" : revision_token
    return "effectiveDate=$effective_date;revisionToken=$encoded"
end

function _validate_source(source, state_class)
    row = _expect_exact_keys(source, SOURCE_KEYS, "receipt.source")
    _expect_exact(row["authority"], SOURCE_AUTHORITY, "receipt.source.authority")
    _expect_exact(row["source_id"], SOURCE_ID, "receipt.source.source_id")
    _expect_exact(row["series_id"], SERIES_ID, "receipt.source.series_id")
    evidence_track = _expect_member(
        row["evidence_track"],
        EVIDENCE_TRACKS,
        "receipt.source.evidence_track",
    )
    expected_track =
        state_class == "CURRENT_STATE" ?
        "CURRENT_REVISED_PROXY" : "STRICT_FIRST_PUBLIC_BYTES"
    _expect_exact(
        evidence_track,
        expected_track,
        "receipt.source.evidence_track",
    )
    _expect_exact(
        row["concept_regime"],
        CONCEPT_REGIME,
        "receipt.source.concept_regime",
    )
    expected_route =
        state_class == "CURRENT_STATE" ?
        "NYFED_CURRENT_API" : "NYFED_PROSPECTIVE_CAPTURE"
    _expect_exact(
        row["route_class"],
        expected_route,
        "receipt.source.route_class",
    )
    _expect_exact(
        row["historical_vintage_claim"],
        "CURRENT_API_DOES_NOT_PROVE_HISTORICAL_VINTAGE",
        "receipt.source.historical_vintage_claim",
    )
    return (
        authority = SOURCE_AUTHORITY,
        source_id = SOURCE_ID,
        series_id = SERIES_ID,
        evidence_track = evidence_track,
        concept_regime = CONCEPT_REGIME,
        route_class = expected_route,
        historical_vintage_claim =
            "CURRENT_API_DOES_NOT_PROVE_HISTORICAL_VINTAGE",
    )
end

function _validate_observation(observation)
    row = _expect_exact_keys(
        observation,
        OBSERVATION_KEYS,
        "receipt.observation",
    )
    effective_date_value = _expect_weekday(
        _expect_date(
            row["effective_date"],
            "receipt.observation.effective_date",
        ),
        "receipt.observation.effective_date",
    )
    effective_date_value >= Date(2016, 3, 1) ||
        fail(
        "receipt.observation.effective_date",
        "must remain in the post-2016 EFFR concept regime",
    )
    effective_date = string(effective_date_value)
    report_type = _expect_member(
        row["report_type"],
        REPORT_TYPES,
        "receipt.observation.report_type",
    )
    state_class = _expect_member(
        row["state_class"],
        STATE_CLASSES,
        "receipt.observation.state_class",
    )
    state_class in CAPTURABLE_STATE_CLASSES ||
        fail(
        "receipt.observation.state_class",
        "ALFRED_DATE_STATE is represented by the taxonomy but is not a New York Fed capture receipt",
    )
    publication_date_value = _expect_weekday(
        _expect_date(
            row["publication_date"],
            "receipt.observation.publication_date",
        ),
        "receipt.observation.publication_date",
    )
    _validate_publication_lag(
        effective_date_value,
        publication_date_value,
        state_class,
    )
    expected_offset, offset_minutes =
        _expected_eastern_offset(publication_date_value)
    publication_utc_offset = _expect_exact(
        row["publication_utc_offset"],
        expected_offset,
        "receipt.observation.publication_utc_offset",
    )
    publication_window = _expect_exact(
        row["scheduled_publication_window"],
        PUBLICATION_WINDOWS[state_class],
        "receipt.observation.scheduled_publication_window",
    )
    pair_key =
        _expect_string(row["pair_key"], "receipt.observation.pair_key"; maximum = 64)
    return (
        effective_date = effective_date,
        publication_date = string(publication_date_value),
        publication_utc_offset = publication_utc_offset,
        publication_utc_offset_minutes = offset_minutes,
        report_type = report_type,
        state_class = state_class,
        scheduled_publication_window = publication_window,
        pair_key = pair_key,
    )
end

function _validate_request(request, effective_date, report_type)
    row = _expect_exact_keys(request, REQUEST_KEYS, "receipt.request")
    _expect_exact(row["endpoint"], ENDPOINT, "receipt.request.endpoint")
    expected_query = _expected_query(effective_date, report_type)
    canonical_query = _expect_exact(
        row["canonical_query"],
        expected_query,
        "receipt.request.canonical_query",
    )
    requested_url = _expect_exact(
        row["requested_url"],
        "$ENDPOINT?$expected_query",
        "receipt.request.requested_url",
    )
    started = _expect_timestamp(
        row["request_started_at_utc"],
        "receipt.request.request_started_at_utc",
    )
    _expect_exact(
        row["secret_ref"],
        "NOT_REQUIRED_PUBLIC_ENDPOINT",
        "receipt.request.secret_ref",
    )
    return (
        endpoint = ENDPOINT,
        canonical_query = canonical_query,
        requested_url = requested_url,
        request_started_at_utc =
            String(row["request_started_at_utc"]),
        request_started = started,
        secret_ref = "NOT_REQUIRED_PUBLIC_ENDPOINT",
    )
end

function _validate_response(response, request)
    row = _expect_exact_keys(response, RESPONSE_KEYS, "receipt.response")
    headers_at = _expect_timestamp(
        row["response_headers_at_utc"],
        "receipt.response.response_headers_at_utc",
    )
    completed_at = _expect_timestamp(
        row["response_body_completed_at_utc"],
        "receipt.response.response_body_completed_at_utc",
    )
    availability = _expect_timestamp(
        row["availability_upper_bound_utc"],
        "receipt.response.availability_upper_bound_utc",
    )
    request.request_started <= headers_at <= completed_at ||
        fail("receipt.response", "timestamps are not monotone")
    availability == completed_at ||
        fail(
        "receipt.response.availability_upper_bound_utc",
        "must equal response-body completion for this conservative boundary",
    )
    _expect_integer(
        row["http_status"],
        "receipt.response.http_status";
        minimum = 100,
        maximum = 599,
    ) == 200 ||
        fail("receipt.response.http_status", "must be 200")
    _expect_exact(row["final_host"], FINAL_HOST, "receipt.response.final_host")
    _expect_exact(
        row["final_url"],
        request.requested_url,
        "receipt.response.final_url",
    )
    redirect_count = _expect_integer(
        row["redirect_count"],
        "receipt.response.redirect_count";
        minimum = 0,
        maximum = 0,
    )
    row["redirect_chain"] isa AbstractVector ||
        fail("receipt.response.redirect_chain", "must be an array")
    isempty(row["redirect_chain"]) ||
        fail("receipt.response.redirect_chain", "must be empty")
    redirect_count == length(row["redirect_chain"]) ||
        fail("receipt.response.redirect_count", "does not match redirect_chain")
    _expect_bool(
        row["headers_complete"],
        "receipt.response.headers_complete",
    ) || fail("receipt.response.headers_complete", "must be true")
    _expect_exact(
        row["content_type"],
        "application/json",
        "receipt.response.content_type",
    )
    content_encoding = _expect_member(
        row["content_encoding"],
        ("identity", "gzip"),
        "receipt.response.content_encoding",
    )
    content_length = _expect_integer(
        row["content_length"],
        "receipt.response.content_length";
        minimum = 1,
        maximum = MAX_RESPONSE_BYTES,
    )
    return (
        response_headers_at_utc =
            String(row["response_headers_at_utc"]),
        response_body_completed_at_utc =
            String(row["response_body_completed_at_utc"]),
        availability_upper_bound_utc =
            String(row["availability_upper_bound_utc"]),
        http_status = 200,
        final_host = FINAL_HOST,
        final_url = request.requested_url,
        redirect_count = 0,
        redirect_chain = (),
        headers_complete = true,
        content_type = "application/json",
        content_encoding = content_encoding,
        content_length = content_length,
    )
end

function _validate_artifact(artifact, response)
    row = _expect_exact_keys(artifact, ARTIFACT_KEYS, "receipt.artifact")
    raw_sha256 = _expect_hash(
        row["raw_sha256"],
        "receipt.artifact.raw_sha256",
    )
    openapi_sha256 = _expect_hash(
        row["openapi_sha256"],
        "receipt.artifact.openapi_sha256",
    )
    _expect_exact(
        row["durable_storage_locator"],
        "artifact-sha256:$raw_sha256",
        "receipt.artifact.durable_storage_locator",
    )
    durable_receipt = _expect_hash(
        row["durable_storage_receipt_sha256"],
        "receipt.artifact.durable_storage_receipt_sha256",
    )
    response.content_length > 0 ||
        fail("receipt.artifact", "cannot bind an empty response")
    return (
        raw_sha256 = raw_sha256,
        openapi_sha256 = openapi_sha256,
        durable_storage_locator = "artifact-sha256:$raw_sha256",
        durable_storage_receipt_sha256 = durable_receipt,
    )
end

function _validate_raw_fields(raw_fields, observation)
    row = _expect_exact_keys(raw_fields, RAW_FIELD_KEYS, "receipt.raw_fields")
    _expect_exact(
        row["effectiveDate"],
        observation.effective_date,
        "receipt.raw_fields.effectiveDate",
    )
    _expect_exact(
        row["type"],
        observation.report_type,
        "receipt.raw_fields.type",
    )
    revision_token = _expect_member(
        row["revisionIndicator"],
        keys(REVISION_CLASSES),
        "receipt.raw_fields.revisionIndicator",
        allow_empty = true,
    )
    footnote_token = _expect_member(
        row["footnote"],
        keys(FOOTNOTE_CLASSES),
        "receipt.raw_fields.footnote",
        allow_empty = true,
    )
    current_state =
        _expect_bool(row["currentState"], "receipt.raw_fields.currentState")
    expected_current = observation.state_class == "CURRENT_STATE"
    current_state == expected_current ||
        fail(
        "receipt.raw_fields.currentState",
        "does not match the closed state class",
    )
    if observation.state_class == "FIRST_0900_STATE"
        revision_token == "" ||
            fail(
            "receipt.raw_fields.revisionIndicator",
            "FIRST_0900_STATE requires the raw empty token",
        )
    elseif observation.state_class in
            ("SAME_DAY_1430_REVISION", "LATER_CORRECTION")
        revision_token == "r" ||
            fail(
            "receipt.raw_fields.revisionIndicator",
            "$(observation.state_class) requires raw token r",
        )
    end
    expected_pair_key =
        _expected_pair_key(observation.effective_date, revision_token)
    observation.pair_key == expected_pair_key ||
        fail(
        "receipt.observation.pair_key",
        "does not bind exact effectiveDate and revisionIndicator",
    )
    values = Dict{String, Union{String, Float64}}()
    blank_fields = String[]
    if observation.report_type == "rate"
        for field in NUMERIC_RATE_FIELDS
            value = _expect_measure_or_blank(
                row[field],
                "receipt.raw_fields.$field";
                minimum = -10.0,
                maximum = 100.0,
            )
            values[field] = value
            value == "" && push!(blank_fields, field)
        end
        values["volumeInBillions"] = _expect_exact(
            row["volumeInBillions"],
            "NOT_REQUESTED_IN_REPORT_TYPE",
            "receipt.raw_fields.volumeInBillions",
        )
    else
        for field in NUMERIC_RATE_FIELDS
            values[field] = _expect_exact(
                row[field],
                "NOT_REQUESTED_IN_REPORT_TYPE",
                "receipt.raw_fields.$field",
            )
        end
        volume = _expect_measure_or_blank(
            row["volumeInBillions"],
            "receipt.raw_fields.volumeInBillions";
            minimum = 0.0,
            maximum = 1_000_000.0,
        )
        values["volumeInBillions"] = volume
        volume == "" && push!(blank_fields, "volumeInBillions")
    end
    if observation.report_type == "rate"
        percentile_fields = (
            "percentPercentile1",
            "percentPercentile25",
            "percentRate",
            "percentPercentile75",
            "percentPercentile99",
        )
        percentile_values = Tuple(values[field] for field in percentile_fields)
        _validate_non_decreasing(
            percentile_values,
            percentile_fields,
            "receipt.raw_fields.percentile_order",
        )
        _validate_non_decreasing(
            (values["targetRateFrom"], values["targetRateTo"]),
            ("targetRateFrom", "targetRateTo"),
            "receipt.raw_fields.target_range",
        )
    end
    return (
        effectiveDate = observation.effective_date,
        type = observation.report_type,
        percentRate = values["percentRate"],
        percentPercentile1 = values["percentPercentile1"],
        percentPercentile25 = values["percentPercentile25"],
        percentPercentile75 = values["percentPercentile75"],
        percentPercentile99 = values["percentPercentile99"],
        targetRateFrom = values["targetRateFrom"],
        targetRateTo = values["targetRateTo"],
        volumeInBillions = values["volumeInBillions"],
        footnote = footnote_token,
        revisionIndicator = revision_token,
        currentState = current_state,
        blank_fields = Tuple(blank_fields),
    )
end

function _expected_schema_class(raw_fields, supplied_class)
    if supplied_class == "SCHEMA_MISMATCH_QUARANTINED"
        return supplied_class
    end
    return isempty(raw_fields.revisionIndicator) ?
        "PINNED_CURRENT_API_EXACT_FIELDSET" :
        "DOCUMENTED_OPENAPI_EXAMPLE_MISMATCH_PINNED_FIELDSET"
end

function _expected_blockers(
        observation,
        raw_fields,
        schema_class,
        governance_decision,
        quarantine_class,
    )
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
    observation.state_class == "CURRENT_STATE" &&
        push!(blockers, "CURRENT_API_NOT_HISTORICAL_VINTAGE")
    isempty(raw_fields.revisionIndicator) ||
        push!(blockers, "OPENAPI_EXAMPLE_MISMATCH_PRESERVED")
    isempty(raw_fields.blank_fields) ||
        push!(blockers, "UNSUPPORTED_BLANK_UNKNOWN_NOT_ZERO")
    governance_decision == "PENDING_PROJECT_SPECIFIC_REVIEW" &&
        push!(blockers, "TERMS_REVIEW_PENDING")
    governance_decision == "REJECTED" &&
        push!(blockers, "TERMS_REVIEW_REJECTED")
    schema_class == "SCHEMA_MISMATCH_QUARANTINED" &&
        push!(blockers, "SCHEMA_MISMATCH")
    quarantine_class == "QUARANTINED_PENDING_MATCHED_STATE_REVIEW" &&
        push!(blockers, "MATCHED_STATE_REVIEW_REQUIRED")
    return sort!(collect(blockers))
end

function _validate_classification(
        classification,
        observation,
        raw_fields,
        artifact,
        governance_decision,
    )
    row = _expect_exact_keys(
        classification,
        CLASSIFICATION_KEYS,
        "receipt.classification",
    )
    revision_class = _expect_exact(
        row["revision_class"],
        REVISION_CLASSES[raw_fields.revisionIndicator],
        "receipt.classification.revision_class",
    )
    footnote_class = _expect_exact(
        row["footnote_class"],
        FOOTNOTE_CLASSES[raw_fields.footnote],
        "receipt.classification.footnote_class",
    )
    expected_volume_class =
        observation.report_type == "rate" ?
        "NOT_REQUESTED_IN_REPORT_TYPE" : "PUBLISHED_VOLUME_FIELD"
    volume_class = _expect_exact(
        row["rate_report_volume_class"],
        expected_volume_class,
        "receipt.classification.rate_report_volume_class",
    )
    expected_blank_class =
        isempty(raw_fields.blank_fields) ?
        "NO_UNSUPPORTED_BLANK" : "UNKNOWN_NOT_ZERO"
    blank_class = _expect_exact(
        row["unsupported_blank_class"],
        expected_blank_class,
        "receipt.classification.unsupported_blank_class",
    )
    expected_current_class =
        raw_fields.currentState ?
        "CURRENT_STATE_FLAG_NOT_VINTAGE" : "NOT_CURRENT_STATE_FLAG"
    current_class = _expect_exact(
        row["current_state_class"],
        expected_current_class,
        "receipt.classification.current_state_class",
    )
    supplied_schema = _expect_member(
        row["schema_class"],
        SCHEMA_CLASSES,
        "receipt.classification.schema_class",
    )
    expected_schema = _expected_schema_class(raw_fields, supplied_schema)
    _expect_exact(
        supplied_schema,
        expected_schema,
        "receipt.classification.schema_class",
    )
    mismatch_detail = _expect_string(
        row["schema_mismatch_detail"],
        "receipt.classification.schema_mismatch_detail";
        maximum = 1_024,
    )
    if supplied_schema == "SCHEMA_MISMATCH_QUARANTINED"
        mismatch_detail == "NONE" &&
            fail(
            "receipt.classification.schema_mismatch_detail",
            "must preserve a concrete mismatch detail",
        )
    else
        _expect_exact(
            mismatch_detail,
            "NONE",
            "receipt.classification.schema_mismatch_detail",
        )
    end
    quarantine_required =
        !isempty(raw_fields.blank_fields) ||
        supplied_schema == "SCHEMA_MISMATCH_QUARANTINED"
    expected_quarantine =
        quarantine_required ?
        "QUARANTINED_PENDING_MATCHED_STATE_REVIEW" : "NOT_QUARANTINED"
    quarantine_class = _expect_member(
        row["quarantine_class"],
        QUARANTINE_CLASSES,
        "receipt.classification.quarantine_class",
    )
    _expect_exact(
        quarantine_class,
        expected_quarantine,
        "receipt.classification.quarantine_class",
    )
    expected_adjudication =
        quarantine_required ?
        "PENDING_INDEPENDENT_MATCHED_STATE_REVIEW" :
        "NOT_REQUIRED_EXACT_SCHEMA"
    adjudication_state = _expect_exact(
        row["adjudication_state"],
        expected_adjudication,
        "receipt.classification.adjudication_state",
    )
    evidence_locator = _expect_exact(
        row["evidence_locator"],
        artifact.durable_storage_locator,
        "receipt.classification.evidence_locator",
    )
    row["blockers"] isa AbstractVector ||
        fail("receipt.classification.blockers", "must be an array")
    blockers = String[
        _expect_member(
                blocker,
                ALLOWED_BLOCKERS,
                "receipt.classification.blockers[$index]",
            ) for (index, blocker) in enumerate(row["blockers"])
    ]
    blockers == sort(unique(blockers)) ||
        fail(
        "receipt.classification.blockers",
        "must be unique and lexicographically sorted",
    )
    expected_blockers = _expected_blockers(
        observation,
        raw_fields,
        supplied_schema,
        governance_decision,
        quarantine_class,
    )
    blockers == expected_blockers ||
        fail(
        "receipt.classification.blockers",
        "does not equal the derived closed blocker set",
    )
    return (
        revision_class = revision_class,
        footnote_class = footnote_class,
        rate_report_volume_class = volume_class,
        unsupported_blank_class = blank_class,
        current_state_class = current_class,
        schema_class = supplied_schema,
        schema_mismatch_detail = mismatch_detail,
        quarantine_class = quarantine_class,
        adjudication_state = adjudication_state,
        evidence_locator = evidence_locator,
        blockers = Tuple(blockers),
    )
end

function _validate_governance(governance, request, observation)
    row = _expect_exact_keys(
        governance,
        GOVERNANCE_KEYS,
        "receipt.governance",
    )
    _expect_exact(row["terms_url"], TERMS_URL, "receipt.governance.terms_url")
    terms_hash = _expect_hash(
        row["terms_snapshot_sha256"],
        "receipt.governance.terms_snapshot_sha256",
    )
    terms_date =
        _expect_date(row["terms_snapshot_date"], "receipt.governance.terms_snapshot_date")
    publication_date = Date(observation.publication_date)
    terms_age = Dates.value(publication_date - terms_date)
    0 <= terms_age <= MAX_TERMS_SNAPSHOT_AGE_DAYS ||
        fail(
        "receipt.governance.terms_snapshot_date",
        "must be no more than $MAX_TERMS_SNAPSHOT_AGE_DAYS days old on the publication date",
    )
    decision = _expect_member(
        row["terms_review_decision"],
        TERMS_DECISIONS,
        "receipt.governance.terms_review_decision",
    )
    attribution = _expect_string(
        row["attribution_requirement"],
        "receipt.governance.attribution_requirement";
        maximum = 2_048,
    )
    disclaimer = _expect_string(
        row["disclaimer_requirement"],
        "receipt.governance.disclaimer_requirement";
        maximum = 2_048,
    )
    redistribution_scope = _expect_member(
        row["redistribution_scope"],
        REDISTRIBUTION_SCOPES,
        "receipt.governance.redistribution_scope",
    )
    expected_context = if decision == "APPROVED_FOR_BOUNDED_CAPTURE" &&
            redistribution_scope == "INTERNAL_RESEARCH_ONLY"
        (
            attribution = APPROVED_ATTRIBUTION,
            disclaimer = APPROVED_DISCLAIMER,
            redistribution = "INTERNAL_RESEARCH_ONLY",
        )
    elseif decision == "APPROVED_FOR_BOUNDED_CAPTURE" &&
            redistribution_scope == "PUBLIC_DERIVED_ONLY"
        (
            attribution = APPROVED_PUBLIC_ATTRIBUTION,
            disclaimer = APPROVED_PUBLIC_DISCLAIMER,
            redistribution = "PUBLIC_DERIVED_ONLY",
        )
    elseif decision == "PENDING_PROJECT_SPECIFIC_REVIEW"
        (
            attribution = PENDING_ATTRIBUTION,
            disclaimer = PENDING_DISCLAIMER,
            redistribution = "PROHIBITED",
        )
    elseif decision == "REJECTED"
        (
            attribution = REJECTED_ATTRIBUTION,
            disclaimer = REJECTED_DISCLAIMER,
            redistribution = "PROHIBITED",
        )
    else
        fail(
            "receipt.governance",
            "decision and redistribution scope are not a registered closed profile",
        )
    end
    _expect_exact(
        attribution,
        expected_context.attribution,
        "receipt.governance.attribution_requirement",
    )
    _expect_exact(
        disclaimer,
        expected_context.disclaimer,
        "receipt.governance.disclaimer_requirement",
    )
    _expect_exact(
        redistribution_scope,
        expected_context.redistribution,
        "receipt.governance.redistribution_scope",
    )
    _expect_exact(
        row["secret_ref"],
        request.secret_ref,
        "receipt.governance.secret_ref",
    )
    return (
        terms_url = TERMS_URL,
        terms_snapshot_sha256 = terms_hash,
        terms_snapshot_date = string(terms_date),
        terms_review_decision = decision,
        attribution_requirement = attribution,
        disclaimer_requirement = disclaimer,
        redistribution_scope = redistribution_scope,
        secret_ref = request.secret_ref,
    )
end

function _validate_lineage(lineage, state_class)
    row = _expect_exact_keys(lineage, LINEAGE_KEYS, "receipt.lineage")
    predecessor = row["predecessor_receipt_sha256"]
    supersedes = row["supersedes_receipt_sha256"]
    for (value, location) in (
            (predecessor, "receipt.lineage.predecessor_receipt_sha256"),
            (supersedes, "receipt.lineage.supersedes_receipt_sha256"),
        )
        value == "NONE" || _expect_hash(value, location)
    end
    predecessor == supersedes ||
        fail("receipt.lineage", "predecessor and supersedes pointers must agree")
    needs_predecessor =
        state_class in ("SAME_DAY_1430_REVISION", "LATER_CORRECTION")
    if needs_predecessor
        predecessor == "NONE" &&
            fail("receipt.lineage", "$state_class requires a predecessor")
        expected_status = "SUPERSEDES_BY_POINTER_WITHOUT_OVERWRITE"
    else
        predecessor == "NONE" ||
            fail("receipt.lineage", "$state_class must start without a predecessor")
        expected_status = "NEW_NONOVERWRITING_STATE"
    end
    status = _expect_exact(
        row["supersession_status"],
        expected_status,
        "receipt.lineage.supersession_status",
    )
    return (
        predecessor_receipt_sha256 = String(predecessor),
        supersedes_receipt_sha256 = String(supersedes),
        supersession_status = status,
    )
end

function _validate_gates(gates)
    row = _expect_exact_keys(gates, GATE_KEYS, "receipt.gates")
    for key in GATE_KEYS
        value = _expect_bool(row[key], "receipt.gates.$key")
        value &&
            fail("receipt.gates.$key", "is permanently false in this boundary")
    end
    return ALWAYS_FALSE_GATES
end

"""
    validate_receipt(receipt, expected_receipt_sha256)

Validate one untrusted, in-memory New York Fed rate or volume receipt. The
second argument is an out-of-band trusted pin. No filesystem path, network
client, raw response byte loader, inventory mutation, or score path exists.
"""
function validate_receipt(receipt, expected_receipt_sha256)
    row = _expect_exact_keys(receipt, RECEIPT_TOP_KEYS, "receipt")
    _expect_exact(row["schema_version"], SCHEMA_VERSION, "receipt.schema_version")
    receipt_id = _expect_string(
        row["receipt_id"],
        "receipt.receipt_id";
        maximum = 128,
    )
    occursin(r"^[A-Z0-9][A-Z0-9._:-]*$", receipt_id) ||
        fail("receipt.receipt_id", "must use the closed uppercase identifier syntax")
    observation = _validate_observation(row["observation"])
    expected_receipt_id = "EFFR:$(observation.effective_date):" *
        "$(uppercase(observation.report_type)):$(observation.state_class)"
    receipt_id == expected_receipt_id ||
        fail(
        "receipt.receipt_id",
        "must bind the exact effective date, report type, and state class",
    )
    source = _validate_source(row["source"], observation.state_class)
    request = _validate_request(
        row["request"],
        observation.effective_date,
        observation.report_type,
    )
    response = _validate_response(row["response"], request)
    _validate_capture_clock(observation, request, response)
    artifact = _validate_artifact(row["artifact"], response)
    raw_fields = _validate_raw_fields(row["raw_fields"], observation)
    governance = _validate_governance(
        row["governance"],
        request,
        observation,
    )
    classification = _validate_classification(
        row["classification"],
        observation,
        raw_fields,
        artifact,
        governance.terms_review_decision,
    )
    lineage = _validate_lineage(row["lineage"], observation.state_class)
    gates = _validate_gates(row["gates"])
    embedded_hash =
        _expect_hash(row["receipt_sha256"], "receipt.receipt_sha256")
    external_hash = _expect_hash(
        expected_receipt_sha256,
        "expected_receipt_sha256",
    )
    computed_hash = canonical_receipt_sha256(row)
    embedded_hash == computed_hash ||
        fail("receipt.receipt_sha256", "does not match canonical receipt bytes")
    external_hash == computed_hash ||
        fail(
        "expected_receipt_sha256",
        "out-of-band pin does not match canonical receipt bytes",
    )
    trusted_observation = Base.structdiff(
        observation,
        NamedTuple{(:publication_utc_offset_minutes,)}(
            (observation.publication_utc_offset_minutes,),
        ),
    )
    return (
        schema_version = SCHEMA_VERSION,
        canonicalization = CANONICALIZATION,
        receipt_id = receipt_id,
        source = source,
        observation = trusted_observation,
        request = Base.structdiff(
            request,
            NamedTuple{(:request_started,)}((request.request_started,)),
        ),
        response = response,
        artifact = artifact,
        raw_fields = Base.structdiff(
            raw_fields,
            NamedTuple{(:blank_fields,)}((raw_fields.blank_fields,)),
        ),
        blank_fields = raw_fields.blank_fields,
        classification = classification,
        governance = governance,
        lineage = lineage,
        gates = gates,
        receipt_sha256 = computed_hash,
    )
end

function _quarantined_pair(
        rate,
        volume,
        blocker;
        mismatch_fields = (),
    )
    return (
        pair_status = "QUARANTINED_PENDING_MATCHED_STATE_REVIEW",
        blocker = blocker,
        mismatch_fields = Tuple(mismatch_fields),
        rate_receipt_sha256 = rate.receipt_sha256,
        volume_receipt_sha256 = volume.receipt_sha256,
        rate_effective_date = rate.observation.effective_date,
        volume_effective_date = volume.observation.effective_date,
        rate_revision_token = rate.raw_fields.revisionIndicator,
        volume_revision_token = volume.raw_fields.revisionIndicator,
        rate_state_class = rate.observation.state_class,
        volume_state_class = volume.observation.state_class,
        joined_record = nothing,
        historical_first_byte_proven = false,
        origin_admissible = false,
        empirical_forecast_allowed = false,
        promotion_eligible = false,
        production_scoring_allowed = false,
        readiness = false,
    )
end

"""
    pair_receipts(rate_receipt, rate_pin, volume_receipt, volume_pin)

Validate two separate receipts and join them only when report types,
effective date, raw revision token, closed state class, publication context,
OpenAPI pin, pair key, and governance context agree. Mismatches return a typed
quarantine decision with no joined record.
"""
function pair_receipts(
        rate_receipt,
        rate_pin,
        volume_receipt,
        volume_pin,
    )
    rate = validate_receipt(rate_receipt, rate_pin)
    volume = validate_receipt(volume_receipt, volume_pin)
    rate.observation.report_type == "rate" ||
        fail("rate_receipt", "must have report_type rate")
    volume.observation.report_type == "volume" ||
        fail("volume_receipt", "must have report_type volume")
    rate.observation.effective_date == volume.observation.effective_date ||
        return _quarantined_pair(
        rate,
        volume,
        "PAIR_EFFECTIVE_DATE_MISMATCH",
    )
    rate.raw_fields.revisionIndicator ==
        volume.raw_fields.revisionIndicator ||
        return _quarantined_pair(
        rate,
        volume,
        "PAIR_REVISION_TOKEN_MISMATCH",
    )
    rate.observation.state_class == volume.observation.state_class ||
        return _quarantined_pair(rate, volume, "PAIR_STATE_CLASS_MISMATCH")
    rate.observation.publication_date == volume.observation.publication_date ||
        return _quarantined_pair(
        rate,
        volume,
        "PAIR_PUBLICATION_DATE_MISMATCH",
    )
    rate.observation.publication_utc_offset ==
        volume.observation.publication_utc_offset ||
        return _quarantined_pair(
        rate,
        volume,
        "PAIR_PUBLICATION_OFFSET_MISMATCH",
    )
    rate.observation.pair_key == volume.observation.pair_key ||
        return _quarantined_pair(rate, volume, "PAIR_KEY_MISMATCH")
    rate.artifact.openapi_sha256 == volume.artifact.openapi_sha256 ||
        return _quarantined_pair(rate, volume, "OPENAPI_PIN_MISMATCH")
    governance_fields = (
        :terms_snapshot_sha256,
        :terms_snapshot_date,
        :terms_review_decision,
        :attribution_requirement,
        :disclaimer_requirement,
        :redistribution_scope,
    )
    governance_mismatches = Tuple(
        String(field) for field in governance_fields if
            getproperty(rate.governance, field) !=
            getproperty(volume.governance, field)
    )
    if !isempty(governance_mismatches)
        return _quarantined_pair(
            rate,
            volume,
            "GOVERNANCE_CONTEXT_MISMATCH";
            mismatch_fields = governance_mismatches,
        )
    end
    rate.governance.terms_review_decision ==
        "APPROVED_FOR_BOUNDED_CAPTURE" ||
        return _quarantined_pair(
        rate,
        volume,
        "TERMS_REVIEW_NOT_APPROVED",
    )
    if rate.classification.quarantine_class != "NOT_QUARANTINED" ||
            volume.classification.quarantine_class != "NOT_QUARANTINED"
        return _quarantined_pair(
            rate,
            volume,
            "INPUT_RECEIPT_QUARANTINED",
        )
    end
    joined = (
        effective_date = rate.observation.effective_date,
        publication_date = rate.observation.publication_date,
        publication_utc_offset =
            rate.observation.publication_utc_offset,
        state_class = rate.observation.state_class,
        revision_token = rate.raw_fields.revisionIndicator,
        pair_key = rate.observation.pair_key,
        percent_rate = rate.raw_fields.percentRate,
        percentile_1 = rate.raw_fields.percentPercentile1,
        percentile_25 = rate.raw_fields.percentPercentile25,
        percentile_75 = rate.raw_fields.percentPercentile75,
        percentile_99 = rate.raw_fields.percentPercentile99,
        target_rate_from = rate.raw_fields.targetRateFrom,
        target_rate_to = rate.raw_fields.targetRateTo,
        volume_in_billions = volume.raw_fields.volumeInBillions,
        rate_footnote = rate.raw_fields.footnote,
        volume_footnote = volume.raw_fields.footnote,
        rate_raw_sha256 = rate.artifact.raw_sha256,
        volume_raw_sha256 = volume.artifact.raw_sha256,
        rate_receipt_sha256 = rate.receipt_sha256,
        volume_receipt_sha256 = volume.receipt_sha256,
        openapi_sha256 = rate.artifact.openapi_sha256,
        terms_snapshot_sha256 =
            rate.governance.terms_snapshot_sha256,
        terms_snapshot_date = rate.governance.terms_snapshot_date,
        terms_review_decision =
            rate.governance.terms_review_decision,
        attribution_requirement =
            rate.governance.attribution_requirement,
        disclaimer_requirement =
            rate.governance.disclaimer_requirement,
        redistribution_scope =
            rate.governance.redistribution_scope,
        pairing_rule =
            "EXACT_DATE_TOKEN_STATE_PUBLICATION_OPENAPI_GOVERNANCE_CONTEXT",
        overwrite_policy = "NEW_IMMUTABLE_JOINED_RECORD",
    )
    return (
        pair_status =
            "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT",
        blocker = "NONE",
        mismatch_fields = (),
        rate_receipt_sha256 = rate.receipt_sha256,
        volume_receipt_sha256 = volume.receipt_sha256,
        rate_effective_date = rate.observation.effective_date,
        volume_effective_date = volume.observation.effective_date,
        rate_revision_token = rate.raw_fields.revisionIndicator,
        volume_revision_token = volume.raw_fields.revisionIndicator,
        rate_state_class = rate.observation.state_class,
        volume_state_class = volume.observation.state_class,
        joined_record = joined,
        historical_first_byte_proven = false,
        origin_admissible = false,
        empirical_forecast_allowed = false,
        promotion_eligible = false,
        production_scoring_allowed = false,
        readiness = false,
    )
end

"""
    trusted_contract()

Return the immutable closed taxonomy and permanent negative gates for this
bounded capture boundary.
"""
function trusted_contract()
    return (
        schema_version = SCHEMA_VERSION,
        endpoint = ENDPOINT,
        source_authority = SOURCE_AUTHORITY,
        series_id = SERIES_ID,
        concept_regime = CONCEPT_REGIME,
        state_classes = STATE_TAXONOMY,
        report_types = REPORT_TYPES,
        revision_classes = (
            empty_token = REVISION_CLASSES[""],
            r_token = REVISION_CLASSES["r"],
        ),
        footnote_classes = (
            empty_token = FOOTNOTE_CLASSES[""],
            footnote_1 = FOOTNOTE_CLASSES["1"],
            footnote_2 = FOOTNOTE_CLASSES["2"],
            footnote_3 = FOOTNOTE_CLASSES["3"],
        ),
        missing_rate_report_volume = "NOT_REQUESTED_IN_REPORT_TYPE",
        unsupported_blank = "UNKNOWN_NOT_ZERO",
        schema_mismatch = "SCHEMA_MISMATCH_QUARANTINED",
        quarantine = "QUARANTINED_PENDING_MATCHED_STATE_REVIEW",
        pair_rule =
            "EXACT_DATE_TOKEN_STATE_PUBLICATION_OPENAPI_GOVERNANCE_CONTEXT",
        strict_publication_lag_days =
            1:MAX_STRICT_PUBLICATION_LAG_DAYS,
        later_correction_lag_days =
            2:MAX_LATER_CORRECTION_LAG_DAYS,
        current_lookback_days = 1:MAX_CURRENT_LOOKBACK_DAYS,
        terms_snapshot_max_age_days =
            MAX_TERMS_SNAPSHOT_AGE_DAYS,
        holiday_calendar_validation =
            "NOT_IMPLEMENTED_WEEKDAY_AND_BOUNDED_LAG_ONLY",
        raw_byte_input = "NOT_ACCEPTED_BY_THIS_MODULE",
        filesystem_path_input = "NOT_ACCEPTED_BY_THIS_MODULE",
        network_client = "ABSENT",
        gates = ALWAYS_FALSE_GATES,
    )
end

end
