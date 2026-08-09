module USProspectiveSnapshotEnvelopeV1

using Dates
using SHA
using TOML

export CapturePlan,
    CapturePolicy,
    ClockSample,
    ClockSource,
    EnvelopeError,
    FetchResponse,
    TimestampEvidence,
    ZipEntry,
    capture_with_fetcher,
    crc32_hex,
    dry_run_plan,
    inspect_zip,
    policy_sha256,
    recover_transaction,
    system_clock_source,
    validate_bundle,
    validate_quarantine,
    validate_response,
    verify_member_payload,
    verify_ooxml_workbook

const SCHEMA_VERSION = "beforeit-us-prospective-snapshot-envelope.v1"
const RECEIPT_SCHEMA = "beforeit-us-prospective-snapshot-receipt.v1"
const MANIFEST_SCHEMA = "beforeit-us-prospective-snapshot-manifest.v1"
const JOURNAL_SCHEMA = "beforeit-us-prospective-snapshot-private-recovery-journal.v1"
const QUARANTINE_FAILURE_SCHEMA =
    "beforeit-us-prospective-snapshot-nonadmitting-quarantine-failure.v1"
const QUARANTINE_MANIFEST_SCHEMA =
    "beforeit-us-prospective-snapshot-nonadmitting-quarantine-manifest.v1"
const POLICY_CANONICALIZATION = "sorted_toml.v1"
const RECEIPT_CANONICALIZATION =
    "sorted_toml_excluding_artifact.receipt_sha256.v1"
const MANIFEST_CANONICALIZATION =
    "sorted_toml_excluding_artifact.manifest_sha256.v1"
const QUARANTINE_MANIFEST_CANONICALIZATION =
    "sorted_toml_excluding_artifact.manifest_sha256.v1"
const CLOCK_AUTHENTICATION = "UNAUTHENTICATED_LOCAL_HOST_CLOCK_ASSERTION"
const EXACT_INTEGER_CONTROL_NAMES = Set(
    [
        "compression_method",
        "duration_milliseconds",
        "header_bytes",
        "http_status",
        "maximum_redirects",
        "sequence",
    ],
)
const HEADER_NAME_PATTERN = r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
const RFC3339_PATTERN =
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"
const RFC3339_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
const FORBIDDEN_REQUEST_HEADERS = Set(
    [
        "authorization",
        "cookie",
        "proxy-authorization",
        "proxy-connection",
    ],
)
const ALWAYS_FALSE_GATES = Dict{String, Any}(
    "accuracy_evaluation_allowed" => false,
    "empirical_forecast_allowed" => false,
    "forecast_origin_admissible" => false,
    "model_state_write_allowed" => false,
    "production_scoring_allowed" => false,
    "promotion_eligible" => false,
    "source_inventory_mutation_allowed" => false,
)
const BASE_BLOCKERS = [
    "CAPTURE_HOST_CLOCK_UNAUTHENTICATED",
    "EXTERNAL_TIMESTAMP_UNAVAILABLE_UNLESS_SEPARATELY_VERIFIED",
    "LOCAL_TWO_COPY_STORAGE_IS_NOT_INDEPENDENT_FAULT_DOMAIN_CUSTODY",
    "PARSED_RESPONSE_HEADERS_ARE_NOT_RAW_WIRE_HEADERS",
    "REVIEWER_AND_TRANSPORT_ASSERTIONS_UNAUTHENTICATED",
    "SOURCE_BYTES_DO_NOT_PROVE_HISTORICAL_FIRST_PUBLICATION_STATE",
]

struct EnvelopeError <: Exception
    message::String
end

"""A millisecond-resolution UTC sample returned by a typed clock source."""
struct ClockSample
    observed_at_utc::DateTime
end

ClockSample(value::AbstractString) =
    ClockSample(_parse_timestamp(value, "clock_sample.observed_at_utc"))

"""Typed, injected clock source. Samples remain unauthenticated local assertions."""
struct ClockSource{F}
    sampler::F
end

system_clock_source() = ClockSource(() -> ClockSample(Dates.now(Dates.UTC)))

Base.showerror(io::IO, error::EnvelopeError) = print(io, error.message)
fail(location, message) = throw(EnvelopeError("$location: $message"))

"""Closed, source-specific policy consumed by the reusable envelope."""
struct CapturePolicy
    policy_id::String
    source_id::String
    campaign_id::String
    artifact_id::String
    requested_url::String
    expected_host::String
    media_types::Vector{String}
    extension::String
    minimum_body_bytes::Int
    maximum_body_bytes::Int
    maximum_duration_seconds::Int
    maximum_header_count::Int
    maximum_header_bytes::Int
    not_before_utc::String
    deadline_utc::String
    expected_body_sha256::String
    request_headers::Vector{Pair{String, String}}
    source_bindings::Dict{String, String}
    blockers::Vector{String}

    function CapturePolicy(;
            policy_id,
            source_id,
            campaign_id,
            artifact_id,
            requested_url,
            expected_host,
            media_types,
            extension,
            minimum_body_bytes,
            maximum_body_bytes,
            maximum_duration_seconds,
            maximum_header_count,
            maximum_header_bytes,
            not_before_utc,
            deadline_utc,
            expected_body_sha256 = "",
            request_headers,
            source_bindings,
            blockers = String[],
        )
        policy = new(
            _identifier(policy_id, "policy.policy_id"),
            _identifier(source_id, "policy.source_id"),
            _identifier(campaign_id, "policy.campaign_id"),
            _identifier(artifact_id, "policy.artifact_id"),
            _https_url(requested_url, expected_host, "policy.requested_url"),
            lowercase(_text(expected_host, "policy.expected_host")),
            String[_media_type(value, "policy.media_types") for value in media_types],
            _extension(extension, "policy.extension"),
            _integer(minimum_body_bytes, "policy.minimum_body_bytes"; minimum = 1),
            _integer(maximum_body_bytes, "policy.maximum_body_bytes"; minimum = 1),
            _integer(
                maximum_duration_seconds,
                "policy.maximum_duration_seconds";
                minimum = 1,
            ),
            _integer(maximum_header_count, "policy.maximum_header_count"; minimum = 1),
            _integer(maximum_header_bytes, "policy.maximum_header_bytes"; minimum = 1),
            _timestamp_text(not_before_utc, "policy.not_before_utc"),
            _timestamp_text(deadline_utc, "policy.deadline_utc"),
            isempty(String(expected_body_sha256)) ? "" :
                _hash(expected_body_sha256, "policy.expected_body_sha256"),
            _header_vector(request_headers, "policy.request_headers"),
            Dict{String, String}(
                _text(key, "policy.source_bindings.key") =>
                    _hash(value, "policy.source_bindings.$key") for
                    (key, value) in source_bindings
            ),
            sort!(unique(String[_text(value, "policy.blockers") for value in blockers])),
        )
        policy.minimum_body_bytes <= policy.maximum_body_bytes ||
            fail("policy.body_bytes", "minimum exceeds maximum")
        _parse_timestamp(policy.not_before_utc, "policy.not_before_utc") <=
            _parse_timestamp(policy.deadline_utc, "policy.deadline_utc") ||
            fail("policy.capture_window", "not-before exceeds deadline")
        isempty(policy.media_types) &&
            fail("policy.media_types", "must not be empty")
        length(unique(policy.media_types)) == length(policy.media_types) ||
            fail("policy.media_types", "duplicates are forbidden")
        _validate_request_headers(policy.request_headers)
        return policy
    end
end

"""Untrusted parsed response material. The constructor snapshots all vectors."""
struct FetchResponse
    body::Vector{UInt8}
    http_status::Int
    requested_url::String
    effective_url::String
    request_headers::Vector{Pair{String, String}}
    response_headers::Vector{Pair{String, String}}
    response_headers_complete::Bool
    parsed_header_order_preserved::Bool
    raw_wire_headers_preserved::Bool
    redirect_chain::Vector{Tuple{Int, String, String}}
    request_started_at_utc::String
    response_headers_at_utc::String
    response_body_completed_at_utc::String
    proxy_used::Bool
    netrc_used::Bool
    cookies_used::Bool
    retry_count::Int

    function FetchResponse(;
            body,
            http_status,
            requested_url,
            effective_url,
            request_headers,
            response_headers,
            response_headers_complete,
            parsed_header_order_preserved,
            raw_wire_headers_preserved,
            redirect_chain,
            request_started_at_utc,
            response_headers_at_utc,
            response_body_completed_at_utc,
            proxy_used,
            netrc_used,
            cookies_used,
            retry_count,
        )
        return new(
            UInt8[byte for byte in body],
            _integer(http_status, "response.http_status"),
            String(requested_url),
            String(effective_url),
            Pair{String, String}[
                String(first(value)) => String(last(value)) for value in request_headers
            ],
            Pair{String, String}[
                String(first(value)) => String(last(value)) for value in response_headers
            ],
            _boolean(response_headers_complete, "response.response_headers_complete"),
            _boolean(
                parsed_header_order_preserved,
                "response.parsed_header_order_preserved",
            ),
            _boolean(raw_wire_headers_preserved, "response.raw_wire_headers_preserved"),
            Tuple{Int, String, String}[
                (Int(value[1]), String(value[2]), String(value[3])) for
                    value in redirect_chain
            ],
            String(request_started_at_utc),
            String(response_headers_at_utc),
            String(response_body_completed_at_utc),
            _boolean(proxy_used, "response.proxy_used"),
            _boolean(netrc_used, "response.netrc_used"),
            _boolean(cookies_used, "response.cookies_used"),
            _integer(retry_count, "response.retry_count"; minimum = 0),
        )
    end
end

struct TimestampEvidence
    provider::String
    issued_at_utc::String
    token::Vector{UInt8}

    function TimestampEvidence(provider, issued_at_utc, token)
        return new(
            _text(provider, "timestamp.provider"),
            _timestamp_text(issued_at_utc, "timestamp.issued_at_utc"),
            UInt8[byte for byte in token],
        )
    end
end

struct CapturePlan
    policy_id::String
    policy_sha256::String
    transaction_id::String
    requested_url::String
    request_count_if_live::Int
    network_request_count::Int
    filesystem_write_count::Int
    gates::Dict{String, Any}
end

struct ZipEntry
    name::String
    flags::UInt16
    compression_method::UInt16
    crc32::UInt32
    compressed_size::UInt32
    uncompressed_size::UInt32
    local_header_offset::UInt32
    data_offset::Int
end

sha256_hex(bytes) = bytes2hex(sha256(bytes))

function _text(value, location; maximum_bytes = 16_384, allow_empty = false)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    !allow_empty && isempty(text) && fail(location, "must not be empty")
    ncodeunits(text) <= maximum_bytes || fail(location, "exceeds byte cap")
    any(character -> Int(character) < 0x20 || Int(character) == 0x7f, text) &&
        fail(location, "contains a control character")
    return text
end

function _identifier(value, location)
    text = _text(value, location; maximum_bytes = 128)
    occursin(IDENTIFIER_PATTERN, text) ||
        fail(location, "must match $(IDENTIFIER_PATTERN.pattern)")
    return text
end

function _integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) || fail(location, "must be an integer")
    number = Int(value)
    number >= minimum || fail(location, "must be at least $minimum")
    return number
end

function _validate_integer_controls(value, location)
    if value isa AbstractDict
        for (raw_key, item) in value
            key = String(raw_key)
            item_location = "$location.$key"
            if endswith(key, "_count") || endswith(key, "_bytes") ||
                    endswith(key, "_milliseconds") || endswith(key, "_seconds") ||
                    key in EXACT_INTEGER_CONTROL_NAMES
                _integer(item, item_location)
            end
            _validate_integer_controls(item, item_location)
        end
    elseif value isa AbstractVector
        for (index, item) in enumerate(value)
            _validate_integer_controls(item, "$location[$index]")
        end
    end
    return value
end

function _boolean(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function _hash(value, location)
    text = _text(value, location; maximum_bytes = 64)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

function _timestamp_text(value, location)
    text = _text(value, location; maximum_bytes = 24)
    _parse_timestamp(text, location)
    return text
end

function _parse_timestamp(value, location)
    text = String(value)
    occursin(RFC3339_PATTERN, text) ||
        fail(location, "must use UTC RFC 3339 milliseconds")
    parsed = tryparse(DateTime, text[1:(end - 1)], RFC3339_FORMAT)
    parsed === nothing && fail(location, "is not a valid UTC timestamp")
    return parsed
end

_clock_text(sample::ClockSample) =
    Dates.format(sample.observed_at_utc, RFC3339_FORMAT) * "Z"

function _sample_clock(source, location)
    source isa ClockSource || fail(location, "must be a ClockSource")
    sample = try
        source.sampler()
    catch error
        fail(location, "clock sampling failed: $(sprint(showerror, error))")
    end
    sample isa ClockSample || fail(location, "clock source must return ClockSample")
    # Round-trip through the closed timestamp grammar, including the supported
    # four-digit year and millisecond precision.
    _parse_timestamp(_clock_text(sample), location)
    return sample
end

function _authorize_clock_sample(policy, sample::ClockSample, location)
    observed = sample.observed_at_utc
    not_before = _parse_timestamp(policy.not_before_utc, "policy.not_before_utc")
    deadline = _parse_timestamp(policy.deadline_utc, "policy.deadline_utc")
    not_before <= observed <= deadline ||
        fail(location, "outside the closed capture window; callback remains unreachable")
    return sample
end

function _media_type(value, location)
    text = lowercase(_text(value, location; maximum_bytes = 256))
    occursin(r"^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$", text) ||
        fail(location, "must be a bare media type")
    return text
end

function _extension(value, location)
    text = lowercase(_text(value, location; maximum_bytes = 16))
    occursin(r"^[a-z0-9]+$", text) || fail(location, "must be alphanumeric")
    return text
end

function _https_url(value, expected_host, location)
    text = _text(value, location; maximum_bytes = 2_048)
    match_value = match(r"^https://([A-Za-z0-9.-]+)(/[^?#]*)$", text)
    match_value === nothing &&
        fail(location, "must be an HTTPS URL without userinfo, port, query, or fragment")
    host = lowercase(match_value.captures[1])
    host == lowercase(String(expected_host)) ||
        fail(location, "host differs from the exact policy host")
    occursin("//", match_value.captures[2]) &&
        fail(location, "path contains an empty component")
    return text
end

function _header_pair(value, location)
    value isa Pair || fail(location, "must be a Pair")
    name = String(first(value))
    header_value = String(last(value))
    isempty(name) && fail(location, "header name is empty")
    name == strip(name) || fail(location, "header name has surrounding whitespace")
    occursin(HEADER_NAME_PATTERN, name) || fail(location, "invalid HTTP token name")
    ncodeunits(name) <= 128 || fail(location, "header name exceeds 128 bytes")
    header_value == strip(header_value) ||
        fail(location, "header value has surrounding whitespace")
    ncodeunits(header_value) <= 8_192 ||
        fail(location, "header value exceeds 8192 bytes")
    any(character -> Int(character) < 0x20 || Int(character) == 0x7f, header_value) &&
        fail(location, "header value contains a control character")
    return name => header_value
end

function _header_vector(values, location)
    result = Pair{String, String}[]
    for (index, value) in enumerate(values)
        push!(result, _header_pair(value, "$location[$index]"))
    end
    return result
end

function _validate_request_headers(headers)
    seen = Set{String}()
    for (index, header) in enumerate(headers)
        name = lowercase(first(_header_pair(header, "request_headers[$index]")))
        name in FORBIDDEN_REQUEST_HEADERS &&
            fail("request_headers[$index]", "credential-bearing header is forbidden")
        name in seen && fail("request_headers", "duplicate header $name")
        push!(seen, name)
    end
    get_value(name) = only([last(pair) for pair in headers if lowercase(first(pair)) == name])
    "accept" in seen || fail("request_headers", "Accept is required")
    "accept-encoding" in seen || fail("request_headers", "Accept-Encoding is required")
    "user-agent" in seen || fail("request_headers", "User-Agent is required")
    lowercase(get_value("accept-encoding")) == "identity" ||
        fail("request_headers", "Accept-Encoding must be identity")
    return headers
end

function _policy_document(policy::CapturePolicy)
    return Dict{String, Any}(
        "schema_version" => SCHEMA_VERSION,
        "artifact_id" => policy.artifact_id,
        "campaign_id" => policy.campaign_id,
        "deadline_utc" => policy.deadline_utc,
        "expected_body_sha256" => policy.expected_body_sha256,
        "expected_host" => policy.expected_host,
        "extension" => policy.extension,
        "maximum_body_bytes" => policy.maximum_body_bytes,
        "maximum_duration_seconds" => policy.maximum_duration_seconds,
        "maximum_header_bytes" => policy.maximum_header_bytes,
        "maximum_header_count" => policy.maximum_header_count,
        "media_types" => copy(policy.media_types),
        "minimum_body_bytes" => policy.minimum_body_bytes,
        "not_before_utc" => policy.not_before_utc,
        "policy_id" => policy.policy_id,
        "request_headers" => [
            Dict("sequence" => index, "name" => first(value), "value" => last(value)) for
                (index, value) in enumerate(policy.request_headers)
        ],
        "requested_url" => policy.requested_url,
        "source_bindings" => deepcopy(policy.source_bindings),
        "source_id" => policy.source_id,
        "blockers" => copy(policy.blockers),
    )
end

function _toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    return take!(io)
end

policy_sha256(policy::CapturePolicy) = sha256_hex(_toml_bytes(_policy_document(policy)))

function _header_values(headers, name)
    wanted = lowercase(name)
    return [last(value) for value in headers if lowercase(first(value)) == wanted]
end

function _base_media_type(value, location)
    raw = _text(value, location; maximum_bytes = 8_192)
    return _media_type(first(split(raw, ';'; limit = 2)), location)
end

function _exact_duplicates(values, location)
    isempty(values) && return ""
    length(unique(values)) == 1 || fail(location, "conflicting duplicate values")
    return first(values)
end

function _response_snapshot(response::FetchResponse)
    return FetchResponse(
        body = copy(response.body),
        http_status = response.http_status,
        requested_url = response.requested_url,
        effective_url = response.effective_url,
        request_headers = copy(response.request_headers),
        response_headers = copy(response.response_headers),
        response_headers_complete = response.response_headers_complete,
        parsed_header_order_preserved = response.parsed_header_order_preserved,
        raw_wire_headers_preserved = response.raw_wire_headers_preserved,
        redirect_chain = copy(response.redirect_chain),
        request_started_at_utc = response.request_started_at_utc,
        response_headers_at_utc = response.response_headers_at_utc,
        response_body_completed_at_utc = response.response_body_completed_at_utc,
        proxy_used = response.proxy_used,
        netrc_used = response.netrc_used,
        cookies_used = response.cookies_used,
        retry_count = response.retry_count,
    )
end

"""Validate parsed response material without filesystem or network effects."""
function validate_response(policy::CapturePolicy, response::FetchResponse)
    snapshot = _response_snapshot(response)
    snapshot.http_status == 200 || fail("response.http_status", "must equal 200")
    snapshot.requested_url == policy.requested_url ||
        fail("response.requested_url", "differs from policy")
    snapshot.effective_url == policy.requested_url ||
        fail("response.effective_url", "redirect or URL drift detected")
    isempty(snapshot.redirect_chain) ||
        fail("response.redirect_chain", "redirects are forbidden")
    snapshot.request_headers == policy.request_headers ||
        fail("response.request_headers", "differs from the exact closed request")
    snapshot.response_headers_complete ||
        fail("response.response_headers_complete", "must be true")
    snapshot.parsed_header_order_preserved ||
        fail("response.parsed_header_order_preserved", "must be true")
    snapshot.raw_wire_headers_preserved &&
        fail(
        "response.raw_wire_headers_preserved",
        "this interface accepts parsed headers and cannot claim raw-wire preservation",
    )
    snapshot.proxy_used && fail("response.proxy_used", "must be false")
    snapshot.netrc_used && fail("response.netrc_used", "must be false")
    snapshot.cookies_used && fail("response.cookies_used", "must be false")
    snapshot.retry_count == 0 || fail("response.retry_count", "must equal zero")
    length(snapshot.response_headers) <= policy.maximum_header_count ||
        fail("response.response_headers", "header count exceeds policy")
    header_bytes = 0
    headers = Pair{String, String}[]
    for (index, header) in enumerate(snapshot.response_headers)
        parsed = _header_pair(header, "response.response_headers[$index]")
        header_bytes += ncodeunits(first(parsed)) + ncodeunits(last(parsed)) + 4
        push!(headers, parsed)
    end
    header_bytes <= policy.maximum_header_bytes ||
        fail("response.response_headers", "aggregate header bytes exceed policy")
    content_types = _header_values(headers, "content-type")
    isempty(content_types) && fail("response.content-type", "is required")
    content_type = _exact_duplicates(content_types, "response.content-type")
    _base_media_type(content_type, "response.content-type") in policy.media_types ||
        fail("response.content-type", "media type is not allowed")
    encodings = _header_values(headers, "content-encoding")
    content_encoding = _exact_duplicates(encodings, "response.content-encoding")
    isempty(content_encoding) || lowercase(content_encoding) == "identity" ||
        fail("response.content-encoding", "must be absent or identity")
    content_lengths = _header_values(headers, "content-length")
    if !isempty(content_lengths)
        raw_length = _exact_duplicates(content_lengths, "response.content-length")
        occursin(r"^(0|[1-9][0-9]*)$", raw_length) ||
            fail("response.content-length", "must be canonical decimal")
        tryparse(Int, raw_length) == length(snapshot.body) ||
            fail("response.content-length", "does not equal body bytes")
    end
    policy.minimum_body_bytes <= length(snapshot.body) <= policy.maximum_body_bytes ||
        fail("response.body", "body size is outside policy")
    body_sha256 = sha256_hex(snapshot.body)
    isempty(policy.expected_body_sha256) || body_sha256 == policy.expected_body_sha256 ||
        fail("response.body", "SHA-256 differs from the expected source identity")
    start = _parse_timestamp(snapshot.request_started_at_utc, "response.request_started_at_utc")
    header_time = _parse_timestamp(
        snapshot.response_headers_at_utc,
        "response.response_headers_at_utc",
    )
    completed = _parse_timestamp(
        snapshot.response_body_completed_at_utc,
        "response.response_body_completed_at_utc",
    )
    start <= header_time <= completed ||
        fail("response.timestamps", "must be monotone")
    duration_ms = Dates.value(completed - start)
    duration_ms <= 1_000 * policy.maximum_duration_seconds ||
        fail("response.timestamps", "request duration exceeds policy")
    not_before = _parse_timestamp(policy.not_before_utc, "policy.not_before_utc")
    deadline = _parse_timestamp(policy.deadline_utc, "policy.deadline_utc")
    not_before <= start <= deadline ||
        fail("response.request_started_at_utc", "outside capture window")
    completed <= deadline ||
        fail("response.response_body_completed_at_utc", "after capture deadline")
    return (
        response = snapshot,
        body_sha256 = body_sha256,
        body_byte_count = length(snapshot.body),
        content_type = content_type,
        content_encoding = content_encoding,
        header_bytes = header_bytes,
        duration_milliseconds = duration_ms,
    )
end

function _validate_received_response(
        policy::CapturePolicy,
        response::FetchResponse,
        terms_reviewed_date,
        post_journal_clock::ClockSample,
    )
    validated = validate_response(policy, response)
    terms_reviewed_date == validated.response.request_started_at_utc[1:10] ||
        fail(
        "terms_reviewed_local_date",
        "must equal the UTC request-start date in this stdlib contract",
    )
    post_journal_clock.observed_at_utc <= _parse_timestamp(
        validated.response.request_started_at_utc,
        "response.request_started_at_utc",
    ) || fail(
        "response.request_started_at_utc",
        "precedes the post-journal callback authorization sample",
    )
    return validated
end

function _u16(bytes, position, location)
    1 <= position <= length(bytes) - 1 || fail(location, "truncated UInt16")
    return UInt16(bytes[position]) | (UInt16(bytes[position + 1]) << 8)
end

function _u32(bytes, position, location)
    1 <= position <= length(bytes) - 3 || fail(location, "truncated UInt32")
    return UInt32(bytes[position]) |
        (UInt32(bytes[position + 1]) << 8) |
        (UInt32(bytes[position + 2]) << 16) |
        (UInt32(bytes[position + 3]) << 24)
end

_signature(bytes, position, value) =
    position <= length(bytes) - 3 && _u32(bytes, position, "zip.signature") == value

function _zip_name(raw, location)
    all(byte -> byte < 0x80, raw) || fail(location, "non-ASCII names are unsupported")
    # `String(::Vector{UInt8})` may take ownership of and empty its input.  The
    # caller still needs the exact central-directory name bytes for the local
    # header comparison, so construct the string from an explicit copy.
    name = String(copy(raw))
    isempty(name) && fail(location, "empty member name")
    ncodeunits(name) <= 1_024 || fail(location, "member name exceeds cap")
    startswith(name, "/") && fail(location, "absolute member name")
    occursin('\\', name) && fail(location, "backslash is forbidden")
    any(character -> Int(character) < 0x20 || Int(character) == 0x7f, name) &&
        fail(location, "control character in member name")
    components = split(name, '/'; keepempty = true)
    any(component -> isempty(component) || component in (".", ".."), components[1:(end - (endswith(name, "/") ? 1 : 0))]) &&
        fail(location, "non-canonical path component")
    return name
end

"""Parse and cross-check a classic (non-ZIP64) ZIP central directory."""
function inspect_zip(input; maximum_entries = 4_096, maximum_uncompressed_bytes = 1_000_000_000)
    bytes = UInt8[byte for byte in input]
    length(bytes) >= 22 || fail("zip", "too short")
    lower = max(1, length(bytes) - 65_557)
    eocd_positions = Int[]
    for position in lower:(length(bytes) - 3)
        _signature(bytes, position, 0x06054b50) && push!(eocd_positions, position)
    end
    candidates = Int[]
    for position in eocd_positions
        position + 21 <= length(bytes) || continue
        comment_length = Int(_u16(bytes, position + 20, "zip.eocd.comment_length"))
        position + 21 + comment_length == length(bytes) && push!(candidates, position)
    end
    length(candidates) == 1 || fail("zip.eocd", "expected one terminal EOCD")
    eocd = only(candidates)
    _u16(bytes, eocd + 4, "zip.eocd.disk") == 0 || fail("zip.eocd", "multidisk forbidden")
    _u16(bytes, eocd + 6, "zip.eocd.central_disk") == 0 ||
        fail("zip.eocd", "multidisk forbidden")
    entries_disk = Int(_u16(bytes, eocd + 8, "zip.eocd.entries_disk"))
    entry_count = Int(_u16(bytes, eocd + 10, "zip.eocd.entry_count"))
    entries_disk == entry_count || fail("zip.eocd", "entry count mismatch")
    entry_count <= maximum_entries || fail("zip.eocd", "entry count exceeds cap")
    entry_count != 0xffff || fail("zip.eocd", "ZIP64 is forbidden")
    central_size = Int(_u32(bytes, eocd + 12, "zip.eocd.central_size"))
    central_offset = Int(_u32(bytes, eocd + 16, "zip.eocd.central_offset"))
    central_offset != typemax(UInt32) || fail("zip.eocd", "ZIP64 is forbidden")
    central_start = central_offset + 1
    central_start + central_size == eocd ||
        fail("zip.eocd", "central directory boundary mismatch")
    entries = ZipEntry[]
    names = Set{String}()
    position = central_start
    total_uncompressed = 0
    for index in 1:entry_count
        _signature(bytes, position, 0x02014b50) ||
            fail("zip.central[$index]", "bad signature")
        flags = _u16(bytes, position + 8, "zip.central[$index].flags")
        (flags & 0x0001) == 0 || fail("zip.central[$index]", "encryption forbidden")
        (flags & 0x0040) == 0 || fail("zip.central[$index]", "strong encryption forbidden")
        method = _u16(bytes, position + 10, "zip.central[$index].method")
        method in (0x0000, 0x0008) ||
            fail("zip.central[$index]", "compression method unsupported")
        crc = _u32(bytes, position + 16, "zip.central[$index].crc32")
        compressed = _u32(bytes, position + 20, "zip.central[$index].compressed_size")
        uncompressed = _u32(bytes, position + 24, "zip.central[$index].uncompressed_size")
        any(value -> value == typemax(UInt32), (compressed, uncompressed)) &&
            fail("zip.central[$index]", "ZIP64 is forbidden")
        name_length = Int(_u16(bytes, position + 28, "zip.central[$index].name_length"))
        extra_length = Int(_u16(bytes, position + 30, "zip.central[$index].extra_length"))
        comment_length = Int(_u16(bytes, position + 32, "zip.central[$index].comment_length"))
        _u16(bytes, position + 34, "zip.central[$index].disk") == 0 ||
            fail("zip.central[$index]", "multidisk forbidden")
        local_offset = _u32(bytes, position + 42, "zip.central[$index].local_offset")
        local_offset != typemax(UInt32) || fail("zip.central[$index]", "ZIP64 forbidden")
        record_end = position + 45 + name_length + extra_length + comment_length
        record_end <= eocd || fail("zip.central[$index]", "record overruns directory")
        raw_name = bytes[(position + 46):(position + 45 + name_length)]
        name = _zip_name(raw_name, "zip.central[$index].name")
        name in names && fail("zip.central", "duplicate member name $name")
        push!(names, name)
        local_position = Int(local_offset) + 1
        _signature(bytes, local_position, 0x04034b50) ||
            fail("zip.local[$index]", "bad signature")
        local_flags = _u16(bytes, local_position + 6, "zip.local[$index].flags")
        local_method = _u16(bytes, local_position + 8, "zip.local[$index].method")
        local_flags == flags || fail("zip.local[$index]", "flags mismatch")
        local_method == method || fail("zip.local[$index]", "method mismatch")
        local_name_length = Int(
            _u16(bytes, local_position + 26, "zip.local[$index].name_length"),
        )
        local_extra_length = Int(
            _u16(bytes, local_position + 28, "zip.local[$index].extra_length"),
        )
        local_name =
            bytes[(local_position + 30):(local_position + 29 + local_name_length)]
        local_name == raw_name || fail("zip.local[$index]", "name mismatch")
        if (flags & 0x0008) == 0
            _u32(bytes, local_position + 14, "zip.local[$index].crc32") == crc ||
                fail("zip.local[$index]", "CRC mismatch")
            _u32(
                bytes,
                local_position + 18,
                "zip.local[$index].compressed_size",
            ) == compressed ||
                fail("zip.local[$index]", "compressed size mismatch")
            _u32(
                bytes,
                local_position + 22,
                "zip.local[$index].uncompressed_size",
            ) == uncompressed ||
                fail("zip.local[$index]", "uncompressed size mismatch")
        end
        data_offset =
            local_position + 30 + local_name_length + local_extra_length
        data_offset + Int(compressed) - 1 < central_start ||
            fail("zip.local[$index]", "member data overlaps central directory")
        total_uncompressed += Int(uncompressed)
        total_uncompressed <= maximum_uncompressed_bytes ||
            fail("zip", "aggregate uncompressed bytes exceed cap")
        push!(
            entries,
            ZipEntry(
                name,
                flags,
                method,
                crc,
                compressed,
                uncompressed,
                local_offset,
                data_offset,
            ),
        )
        position = record_end + 1
    end
    position == eocd || fail("zip.central", "directory size or entry count mismatch")
    return entries
end

function _crc32(bytes)
    crc = typemax(UInt32)
    for byte in bytes
        crc = xor(crc, UInt32(byte))
        for _ in 1:8
            crc = (crc & 0x00000001) == 0x00000001 ?
                xor(crc >> 1, UInt32(0xedb88320)) : crc >> 1
        end
    end
    return xor(crc, typemax(UInt32))
end

crc32_hex(bytes) = lowercase(string(_crc32(bytes); base = 16, pad = 8))

"""Verify an independently extracted member against a parsed ZIP directory."""
function verify_member_payload(entries, member_name, payload; expected_sha256 = "")
    name = _text(member_name, "member_name"; maximum_bytes = 1_024)
    matches = [entry for entry in entries if entry.name == name]
    length(matches) == 1 || fail("member.$name", "must occur exactly once")
    entry = only(matches)
    bytes = UInt8[byte for byte in payload]
    length(bytes) == Int(entry.uncompressed_size) ||
        fail("member.$name", "uncompressed size mismatch")
    _crc32(bytes) == entry.crc32 || fail("member.$name", "CRC-32 mismatch")
    digest = sha256_hex(bytes)
    isempty(String(expected_sha256)) || digest == _hash(expected_sha256, "member.expected_sha256") ||
        fail("member.$name", "SHA-256 mismatch")
    return (
        member_name = name,
        member_sha256 = digest,
        member_byte_count = length(bytes),
        member_crc32 = crc32_hex(bytes),
        compression_method = Int(entry.compression_method),
        compressed_byte_count = Int(entry.compressed_size),
    )
end

function _xml_decode(value, location)
    occursin(r"<!DOCTYPE|<!ENTITY", value) && fail(location, "DTD/entity declaration forbidden")
    unsupported = replace(
        value,
        "&quot;" => "",
        "&apos;" => "",
        "&lt;" => "",
        "&gt;" => "",
        "&amp;" => "",
    )
    occursin('&', unsupported) && fail(location, "unsupported or malformed XML entity")
    result = replace(
        value,
        "&quot;" => "\"",
        "&apos;" => "'",
        "&lt;" => "<",
        "&gt;" => ">",
        "&amp;" => "&",
    )
    return result
end

"""Validate XLSX container evidence and exact workbook sheet names."""
function verify_ooxml_workbook(
        workbook_bytes,
        workbook_xml_bytes;
        expected_workbook_sha256 = "",
        expected_workbook_xml_sha256 = "",
        required_sheets = String[],
    )
    workbook = UInt8[byte for byte in workbook_bytes]
    xml = UInt8[byte for byte in workbook_xml_bytes]
    workbook_digest = sha256_hex(workbook)
    isempty(String(expected_workbook_sha256)) ||
        workbook_digest == _hash(expected_workbook_sha256, "ooxml.expected_workbook_sha256") ||
        fail("ooxml.workbook", "SHA-256 mismatch")
    entries = inspect_zip(
        workbook;
        maximum_entries = 20_000,
        maximum_uncompressed_bytes = 500_000_000,
    )
    names = Set(entry.name for entry in entries)
    for required in ("[Content_Types].xml", "_rels/.rels", "xl/workbook.xml")
        required in names || fail("ooxml.workbook", "missing required member $required")
    end
    evidence = verify_member_payload(
        entries,
        "xl/workbook.xml",
        xml;
        expected_sha256 = expected_workbook_xml_sha256,
    )
    text = try
        String(xml)
    catch
        fail("ooxml.workbook.xml", "must be UTF-8")
    end
    occursin("<!DOCTYPE", text) && fail("ooxml.workbook.xml", "DOCTYPE forbidden")
    occursin("<!ENTITY", text) && fail("ooxml.workbook.xml", "ENTITY forbidden")
    sheets = String[]
    for match_value in eachmatch(r"<sheet\s+[^>]*\bname=\"([^\"]*)\"", text)
        push!(sheets, _xml_decode(match_value.captures[1], "ooxml.sheet.name"))
    end
    isempty(sheets) && fail("ooxml.workbook.xml", "no sheet declarations found")
    length(unique(sheets)) == length(sheets) ||
        fail("ooxml.workbook.xml", "duplicate decoded sheet names")
    for required in required_sheets
        String(required) in sheets || fail("ooxml.workbook.xml", "missing sheet $(repr(required))")
    end
    return (
        workbook_sha256 = workbook_digest,
        workbook_byte_count = length(workbook),
        workbook_xml_sha256 = evidence.member_sha256,
        workbook_xml_byte_count = evidence.member_byte_count,
        workbook_xml_crc32 = evidence.member_crc32,
        sheets = sheets,
    )
end

function dry_run_plan(policy::CapturePolicy, transaction_id)
    tx = _identifier(transaction_id, "transaction_id")
    return CapturePlan(
        policy.policy_id,
        policy_sha256(policy),
        tx,
        policy.requested_url,
        1,
        0,
        0,
        deepcopy(ALWAYS_FALSE_GATES),
    )
end

function _strict_root(value)
    root = String(value)
    isabspath(root) || fail("raw_root", "must be absolute")
    normpath(root) == root || fail("raw_root", "must be normalized")
    dirname(root) != root || fail("raw_root", "filesystem roots are forbidden")
    isdir(root) || fail("raw_root", "must exist")
    candidate = root
    while true
        islink(candidate) && fail("raw_root", "symbolic path component forbidden")
        parent = dirname(candidate)
        parent == candidate && break
        candidate = parent
    end
    realpath(root) == root || fail("raw_root", "must be canonical")
    # Portable filesystems use directory link counts for child-directory
    # bookkeeping; ordinary directories therefore need not report one link.
    # Internal symbolic links and every material regular file are checked
    # separately, while user-created directory hard links are not supported by
    # the target platforms.
    return root
end

function _check_components(path, root; expect_file = false)
    startswith(path, root * "/") || path == root || fail("path", "outside root")
    relative = relpath(path, root)
    candidate = root
    for component in split(relative, '/')
        component in ("", ".", "..") && fail("path", "non-canonical component")
        candidate = joinpath(candidate, component)
        ispath(candidate) || fail("path", "missing $candidate")
        islink(candidate) && fail("path", "symbolic path component forbidden")
    end
    if expect_file
        isfile(path) || fail("path", "expected regular file")
        stat(path).nlink == 1 || fail("path", "hard-linked file forbidden")
    end
    return path
end

function _transaction_paths(root, transaction_id)
    tx = _identifier(transaction_id, "transaction_id")
    return (
        final = joinpath(root, tx),
        staging = joinpath(root, ".$tx.staging"),
        quarantine = joinpath(root, "$tx.quarantine"),
        quarantine_staging = joinpath(root, ".$tx.quarantine.staging"),
        journal = joinpath(root, ".$tx.private-recovery.toml"),
        lock = joinpath(root, ".$tx.exactly-once.lock"),
    )
end

function _fsync_directory(path)
    directory = Base.Filesystem.open(path, Base.JL_O_RDONLY)
    try
        ccall(:fsync, Cint, (Cint,), fd(directory)) == 0 ||
            fail("storage", "directory fsync failed for $path")
    finally
        close(directory)
    end
    return path
end

function _write_file(path, bytes; mode = 0o600)
    ispath(path) && fail("write", "refuses overwrite of $path")
    io = try
        Base.Filesystem.open(
            path,
            Base.JL_O_CREAT | Base.JL_O_EXCL | Base.JL_O_WRONLY,
            mode,
        )
    catch error
        fail("write", "exclusive create failed for $path: $(sprint(showerror, error))")
    end
    try
        write(io, bytes)
        flush(io)
        ccall(:fsync, Cint, (Cint,), fd(io)) == 0 || fail("write", "fsync failed")
    finally
        close(io)
    end
    chmod(path, mode)
    _fsync_directory(dirname(path))
    return path
end

function _replace_private_file(path, bytes)
    temporary = path * ".next"
    ispath(temporary) && fail("journal", "stale temporary journal")
    _write_file(temporary, bytes; mode = 0o600)
    mv(temporary, path; force = true)
    chmod(path, 0o600)
    _fsync_directory(dirname(path))
    return path
end

function _journal_document(policy, transaction_id, state, request_may_have_begun)
    return Dict{String, Any}(
        "schema_version" => JOURNAL_SCHEMA,
        "policy_id" => policy.policy_id,
        "policy_sha256" => policy_sha256(policy),
        "transaction_id" => transaction_id,
        "state" => state,
        "request_may_have_begun" => request_may_have_begun,
    )
end

function _write_journal(path, policy, transaction_id, state, request_may_have_begun)
    bytes = _toml_bytes(
        _journal_document(policy, transaction_id, state, request_may_have_begun),
    )
    return if isfile(path)
        islink(path) && fail("journal", "symbolic link forbidden")
        stat(path).nlink == 1 || fail("journal", "hard link forbidden")
        _replace_private_file(path, bytes)
    else
        _write_file(path, bytes; mode = 0o600)
    end
end

function _validate_journal(path, policy, transaction_id)
    isfile(path) || fail("journal", "missing")
    islink(path) && fail("journal", "symbolic link forbidden")
    stat(path).nlink == 1 || fail("journal", "hard link forbidden")
    document = TOML.parsefile(path)
    Set(keys(document)) == Set(
        [
            "schema_version",
            "policy_id",
            "policy_sha256",
            "transaction_id",
            "state",
            "request_may_have_begun",
        ],
    ) || fail("journal", "keys differ from closed schema")
    document["schema_version"] == JOURNAL_SCHEMA || fail("journal", "schema mismatch")
    document["policy_id"] == policy.policy_id || fail("journal", "policy mismatch")
    document["policy_sha256"] == policy_sha256(policy) || fail("journal", "policy hash mismatch")
    document["transaction_id"] == transaction_id || fail("journal", "transaction mismatch")
    document["request_may_have_begun"] isa Bool ||
        fail("journal", "request_may_have_begun must be Boolean")
    return document
end

function _headers_document(headers)
    return [
        Dict("sequence" => index, "name" => first(pair), "value" => last(pair)) for
            (index, pair) in enumerate(headers)
    ]
end

function _transport_document(validated)
    response = validated.response
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-parsed-http-transport-evidence.v1",
        "body_byte_count" => validated.body_byte_count,
        "body_sha256" => validated.body_sha256,
        "content_encoding" => validated.content_encoding,
        "content_type" => validated.content_type,
        "cookies_used" => response.cookies_used,
        "duration_milliseconds" => validated.duration_milliseconds,
        "effective_url" => response.effective_url,
        "header_bytes" => validated.header_bytes,
        "http_status" => response.http_status,
        "netrc_used" => response.netrc_used,
        "parsed_header_order_preserved" => response.parsed_header_order_preserved,
        "proxy_used" => response.proxy_used,
        "raw_wire_headers_preserved" => response.raw_wire_headers_preserved,
        "redirect_chain" => [
            Dict("status" => hop[1], "from" => hop[2], "to" => hop[3]) for
                hop in response.redirect_chain
        ],
        "request_headers" => _headers_document(response.request_headers),
        "request_started_at_utc" => response.request_started_at_utc,
        "requested_url" => response.requested_url,
        "response_body_completed_at_utc" => response.response_body_completed_at_utc,
        "response_headers" => _headers_document(response.response_headers),
        "response_headers_at_utc" => response.response_headers_at_utc,
        "response_headers_complete" => response.response_headers_complete,
        "retry_count" => response.retry_count,
        "transport_assertion_authentication" => "UNAUTHENTICATED_LOCAL_PROCESS_ASSERTION",
    )
end

function _untrusted_transport_document(response::FetchResponse)
    snapshot = _response_snapshot(response)
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-untrusted-parsed-http-transport-evidence.v1",
        "body_byte_count" => length(snapshot.body),
        "body_sha256" => sha256_hex(snapshot.body),
        "cookies_used" => snapshot.cookies_used,
        "effective_url" => snapshot.effective_url,
        "http_status" => snapshot.http_status,
        "netrc_used" => snapshot.netrc_used,
        "parsed_header_order_preserved" => snapshot.parsed_header_order_preserved,
        "proxy_used" => snapshot.proxy_used,
        "raw_wire_headers_preserved" => snapshot.raw_wire_headers_preserved,
        "redirect_chain" => [
            Dict("status" => hop[1], "from" => hop[2], "to" => hop[3]) for
                hop in snapshot.redirect_chain
        ],
        "request_headers" => _headers_document(snapshot.request_headers),
        "request_started_at_utc" => snapshot.request_started_at_utc,
        "requested_url" => snapshot.requested_url,
        "response_body_completed_at_utc" => snapshot.response_body_completed_at_utc,
        "response_headers" => _headers_document(snapshot.response_headers),
        "response_headers_at_utc" => snapshot.response_headers_at_utc,
        "response_headers_complete" => snapshot.response_headers_complete,
        "retry_count" => snapshot.retry_count,
        "validation_status" => "UNTRUSTED_RECEIVED_RESPONSE_NOT_ACCEPTED",
        "wire_fidelity" => "PARSED_HEADERS_ONLY_RAW_WIRE_HEADERS_UNAVAILABLE",
    )
end

function _attestation_document(
        actor,
        terms_reviewed_date,
        initial_clock::ClockSample,
        post_journal_clock::ClockSample,
    )
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-local-capture-attestation.v1",
        "actor" => actor,
        "actor_authentication" => "UNAUTHENTICATED_LOCAL_ASSERTION",
        "clock_authentication" => CLOCK_AUTHENTICATION,
        "initial_authorization_clock_observed_at_utc" => _clock_text(initial_clock),
        "post_journal_issue_clock_observed_at_utc" => _clock_text(post_journal_clock),
        "terms_reviewed_local_date" => terms_reviewed_date,
        "terms_review_status" => "LOCAL_REVIEW_ASSERTION_NOT_LEGAL_AUTHORIZATION",
    )
end

function _attestation_clocks(document)
    initial = ClockSample(
        _timestamp_text(
            document["initial_authorization_clock_observed_at_utc"],
            "attestation.initial_authorization_clock_observed_at_utc",
        )
    )
    post_journal = ClockSample(
        _timestamp_text(
            document["post_journal_issue_clock_observed_at_utc"],
            "attestation.post_journal_issue_clock_observed_at_utc",
        )
    )
    initial.observed_at_utc <= post_journal.observed_at_utc ||
        fail("attestation.clock", "initial sample is after post-journal sample")
    return initial, post_journal
end

function _response_from_transport(body, document)
    _validate_integer_controls(document, "transport")
    request_headers = Pair{String, String}[
        String(row["name"]) => String(row["value"]) for
            row in document["request_headers"]
    ]
    response_headers = Pair{String, String}[
        String(row["name"]) => String(row["value"]) for
            row in document["response_headers"]
    ]
    for (index, row) in enumerate(document["request_headers"])
        _integer(row["sequence"], "transport.request_headers[$index].sequence"; minimum = 1) ==
            index || fail("transport.request_headers", "sequence mismatch")
    end
    for (index, row) in enumerate(document["response_headers"])
        _integer(row["sequence"], "transport.response_headers[$index].sequence"; minimum = 1) ==
            index || fail("transport.response_headers", "sequence mismatch")
    end
    redirects = Tuple{Int, String, String}[
        (
                _integer(row["status"], "transport.redirect_chain[$index].status"),
                String(row["from"]),
                String(row["to"]),
            ) for (index, row) in enumerate(document["redirect_chain"])
    ]
    return FetchResponse(
        body = body,
        http_status = document["http_status"],
        requested_url = document["requested_url"],
        effective_url = document["effective_url"],
        request_headers = request_headers,
        response_headers = response_headers,
        response_headers_complete = document["response_headers_complete"],
        parsed_header_order_preserved = document["parsed_header_order_preserved"],
        raw_wire_headers_preserved = document["raw_wire_headers_preserved"],
        redirect_chain = redirects,
        request_started_at_utc = document["request_started_at_utc"],
        response_headers_at_utc = document["response_headers_at_utc"],
        response_body_completed_at_utc = document["response_body_completed_at_utc"],
        proxy_used = document["proxy_used"],
        netrc_used = document["netrc_used"],
        cookies_used = document["cookies_used"],
        retry_count = document["retry_count"],
    )
end

function _receipt_document(
        policy,
        transaction_id,
        actor,
        terms_reviewed_date,
        validated,
        selector,
        timestamp_document,
        initial_clock::ClockSample,
        post_journal_clock::ClockSample,
    )
    occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", terms_reviewed_date) ||
        fail("terms_reviewed_local_date", "must use canonical YYYY-MM-DD")
    terms_reviewed_date == validated.response.request_started_at_utc[1:10] ||
        fail(
        "terms_reviewed_local_date",
        "must equal the UTC request-start date in this stdlib contract",
    )
    _authorize_clock_sample(policy, initial_clock, "receipt.initial_authorization_clock")
    _authorize_clock_sample(policy, post_journal_clock, "receipt.post_journal_issue_clock")
    initial_clock.observed_at_utc <= post_journal_clock.observed_at_utc ||
        fail("receipt.clock", "initial sample is after post-journal sample")
    post_journal_clock.observed_at_utc <= _parse_timestamp(
        validated.response.request_started_at_utc,
        "response.request_started_at_utc",
    ) || fail("receipt.clock", "post-journal issue sample is after request start assertion")
    blockers = sort!(unique(vcat(BASE_BLOCKERS, policy.blockers)))
    timestamp_document["established"] &&
        filter!(value -> value != "EXTERNAL_TIMESTAMP_UNAVAILABLE_UNLESS_SEPARATELY_VERIFIED", blockers)
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "canonicalization" => RECEIPT_CANONICALIZATION,
            "receipt_sha256" => repeat("0", 64),
            "schema_version" => RECEIPT_SCHEMA,
            "transaction_id" => transaction_id,
        ),
        "blockers" => blockers,
        "capture" => Dict{String, Any}(
            "actor" => actor,
            "actor_authentication" => "UNAUTHENTICATED_LOCAL_ASSERTION",
            "body_byte_count" => validated.body_byte_count,
            "body_sha256" => validated.body_sha256,
            "campaign_id" => policy.campaign_id,
            "content_encoding" => validated.content_encoding,
            "content_type" => validated.content_type,
            "duration_milliseconds" => validated.duration_milliseconds,
            "response_body_completed_at_utc" =>
                validated.response.response_body_completed_at_utc,
            "source_id" => policy.source_id,
            "terms_reviewed_local_date" => terms_reviewed_date,
            "terms_review_status" => "LOCAL_REVIEW_ASSERTION_NOT_LEGAL_AUTHORIZATION",
        ),
        "external_timestamp" => timestamp_document,
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
        "issue_authorization" => Dict{String, Any}(
            "clock_authentication" => CLOCK_AUTHENTICATION,
            "initial_authorization_clock_observed_at_utc" => _clock_text(initial_clock),
            "post_journal_issue_clock_observed_at_utc" => _clock_text(post_journal_clock),
            "window_gate_status" => "PASSED_TWICE_BEFORE_FETCH_CALLBACK",
        ),
        "limits" => Dict{String, Any}(
            "maximum_body_bytes" => policy.maximum_body_bytes,
            "maximum_duration_seconds" => policy.maximum_duration_seconds,
            "maximum_header_bytes" => policy.maximum_header_bytes,
            "maximum_header_count" => policy.maximum_header_count,
            "request_count" => 1,
            "retry_count" => 0,
        ),
        "policy" => Dict{String, Any}(
            "artifact_id" => policy.artifact_id,
            "deadline_utc" => policy.deadline_utc,
            "not_before_utc" => policy.not_before_utc,
            "policy_id" => policy.policy_id,
            "policy_sha256" => policy_sha256(policy),
            "requested_url" => policy.requested_url,
            "source_bindings" => deepcopy(policy.source_bindings),
        ),
        "selector" => selector,
        "transport" => Dict{String, Any}(
            "effective_url" => validated.response.effective_url,
            "http_status" => validated.response.http_status,
            "parsed_response_header_count" => length(validated.response.response_headers),
            "parsed_response_headers_preserved_in_order" => true,
            "raw_wire_headers_preserved" => false,
            "transport_assertion_authentication" => "UNAUTHENTICATED_LOCAL_PROCESS_ASSERTION",
        ),
    )
    document["artifact"]["receipt_sha256"] = _receipt_hash(document)
    return document
end

function _receipt_hash(document)
    copy_document = deepcopy(document)
    copy_document["artifact"]["receipt_sha256"] = repeat("0", 64)
    return sha256_hex(_toml_bytes(copy_document))
end

function _manifest_document(policy, transaction_id, file_records, receipt_hash)
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "canonicalization" => MANIFEST_CANONICALIZATION,
            "manifest_sha256" => repeat("0", 64),
            "schema_version" => MANIFEST_SCHEMA,
            "transaction_id" => transaction_id,
        ),
        "files" => file_records,
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
        "policy_id" => policy.policy_id,
        "policy_sha256" => policy_sha256(policy),
        "receipt_sha256" => receipt_hash,
        "replica_count" => 2,
        "replica_fault_domain_count" => 1,
    )
    document["artifact"]["manifest_sha256"] = _manifest_hash(document)
    return document
end

function _manifest_hash(document)
    copy_document = deepcopy(document)
    copy_document["artifact"]["manifest_sha256"] = repeat("0", 64)
    return sha256_hex(_toml_bytes(copy_document))
end

function _file_record(root, relative)
    path = joinpath(root, relative)
    bytes = read(path)
    return Dict{String, Any}(
        "path" => relative,
        "sha256" => sha256_hex(bytes),
        "byte_count" => length(bytes),
    )
end

function _seal_replica(
        staging,
        name,
        raw_name,
        body,
        transport_bytes,
        attestation_bytes,
    )
    directory = joinpath(staging, name)
    mkdir(directory; mode = 0o700)
    raw_path = joinpath(directory, raw_name)
    transport_path = joinpath(directory, "transport.toml")
    attestation_path = joinpath(directory, "attestation.toml")
    _write_file(raw_path, body)
    _write_file(transport_path, transport_bytes)
    _write_file(attestation_path, attestation_bytes)
    reread_body = read(raw_path)
    reread_transport = read(transport_path)
    reread_attestation = read(attestation_path)
    reread_body == body || fail("storage.$name", "raw reread differs")
    reread_transport == transport_bytes || fail("storage.$name", "transport reread differs")
    reread_attestation == attestation_bytes ||
        fail("storage.$name", "attestation reread differs")
    return (raw_path, transport_path, attestation_path)
end

function _timestamp_document(evidence, verifier, body_sha256)
    evidence === nothing && return Dict{String, Any}(
        "established" => false,
        "issued_at_utc" => "",
        "provider" => "",
        "token_byte_count" => 0,
        "token_sha256" => "",
        "verification_status" => "UNAVAILABLE",
    )
    evidence isa TimestampEvidence || fail("timestamp", "provider returned wrong type")
    verifier === nothing && fail("timestamp", "a verifier is required for supplied evidence")
    isempty(evidence.token) && fail("timestamp", "token must not be empty")
    verifier(evidence, body_sha256) === true || fail("timestamp", "verification failed")
    return Dict{String, Any}(
        "established" => true,
        "issued_at_utc" => evidence.issued_at_utc,
        "provider" => evidence.provider,
        "token_byte_count" => length(evidence.token),
        "token_sha256" => sha256_hex(evidence.token),
        "verification_status" => "VERIFIED_BY_INJECTED_VERIFIER",
    )
end

function _seal_bundle(
        policy,
        paths,
        transaction_id,
        actor,
        terms_reviewed_date,
        validated,
        selector,
        timestamp_evidence,
        timestamp_document,
        initial_clock::ClockSample,
        post_journal_clock::ClockSample,
    )
    mkdir(paths.staging; mode = 0o700)
    raw_name = "raw.$(policy.extension)"
    transport_bytes = _toml_bytes(_transport_document(validated))
    attestation_bytes = _toml_bytes(
        _attestation_document(
            actor,
            terms_reviewed_date,
            initial_clock,
            post_journal_clock,
        ),
    )
    replica_a = _seal_replica(
        paths.staging,
        "replica-a",
        raw_name,
        validated.response.body,
        transport_bytes,
        attestation_bytes,
    )
    replica_b = _seal_replica(
        paths.staging,
        "replica-b",
        raw_name,
        validated.response.body,
        transport_bytes,
        attestation_bytes,
    )
    stat(replica_a[1]).inode != stat(replica_b[1]).inode ||
        fail("storage", "raw replicas share an inode")
    stat(replica_a[2]).inode != stat(replica_b[2]).inode ||
        fail("storage", "transport replicas share an inode")
    stat(replica_a[3]).inode != stat(replica_b[3]).inode ||
        fail("storage", "attestation replicas share an inode")
    relative_files = [
        joinpath("replica-a", raw_name),
        joinpath("replica-a", "transport.toml"),
        joinpath("replica-a", "attestation.toml"),
        joinpath("replica-b", raw_name),
        joinpath("replica-b", "transport.toml"),
        joinpath("replica-b", "attestation.toml"),
    ]
    if timestamp_evidence !== nothing
        for replica in ("replica-a", "replica-b")
            path = joinpath(paths.staging, replica, "external-timestamp-token.bin")
            _write_file(path, timestamp_evidence.token)
            push!(relative_files, joinpath(replica, "external-timestamp-token.bin"))
        end
    end
    receipt = _receipt_document(
        policy,
        transaction_id,
        actor,
        terms_reviewed_date,
        validated,
        selector,
        timestamp_document,
        initial_clock,
        post_journal_clock,
    )
    receipt_bytes = _toml_bytes(receipt)
    _write_file(joinpath(paths.staging, "receipt.toml"), receipt_bytes)
    push!(relative_files, "receipt.toml")
    records = [_file_record(paths.staging, relative) for relative in relative_files]
    manifest = _manifest_document(
        policy,
        transaction_id,
        records,
        receipt["artifact"]["receipt_sha256"],
    )
    _write_file(joinpath(paths.staging, "manifest.toml"), _toml_bytes(manifest))
    for (root, directories, files) in walkdir(paths.staging; topdown = false)
        for file in files
            chmod(joinpath(root, file), 0o400)
        end
        for directory in directories
            chmod(joinpath(root, directory), 0o500)
        end
    end
    chmod(paths.staging, 0o500)
    _fsync_directory(paths.staging)
    _fsync_directory(dirname(paths.staging))
    return paths.staging
end

const QUARANTINE_FAILURES = Dict(
    "RESPONSE_VALIDATION" => "RESPONSE_VALIDATION_FAILED",
    "SELECTOR_VALIDATION" => "SELECTOR_VALIDATION_FAILED",
    "TIMESTAMP_EVIDENCE" => "TIMESTAMP_EVIDENCE_FAILED",
)

function _safe_failure_detail(value)
    raw = value isa Exception ? sprint(showerror, value) : String(value)
    characters = Char[]
    for character in raw
        length(characters) == 2_048 && break
        code = Int(character)
        push!(characters, (code < 0x20 || code == 0x7f) ? '?' : character)
    end
    detail = strip(String(characters))
    return isempty(detail) ? "UNAVAILABLE_LOCAL_ERROR_DETAIL" : detail
end

function _quarantine_failure_document(
        policy,
        transaction_id,
        phase,
        failure_code,
        failure_detail,
        response::FetchResponse,
    )
    get(QUARANTINE_FAILURES, phase, "") == failure_code ||
        fail("quarantine.failure", "phase/code pair is outside the closed vocabulary")
    detail = _safe_failure_detail(failure_detail)
    return Dict{String, Any}(
        "schema_version" => QUARANTINE_FAILURE_SCHEMA,
        "transaction_id" => transaction_id,
        "policy_id" => policy.policy_id,
        "policy_sha256" => policy_sha256(policy),
        "failure_phase" => phase,
        "failure_code" => failure_code,
        "failure_detail" => detail,
        "failure_detail_authentication" => "UNAUTHENTICATED_LOCAL_PROCESS_ASSERTION",
        "failure_reconstruction_scope" => phase == "RESPONSE_VALIDATION" ?
            "FULL_PURE_RESPONSE_VALIDATION_REPLAY" :
            "PHASE_ORDER_ONLY_EXTERNAL_CALLBACK_NOT_REPLAYED",
        "raw_body_sha256" => sha256_hex(response.body),
        "raw_body_byte_count" => length(response.body),
        "status" => "NONADMITTING_QUARANTINE_RECEIVED_BYTES_PRESERVED_NO_RETRY",
        "completion_receipt_created" => false,
        "selector_completion_claimed" => false,
        "profile_evidence_created" => false,
        "profile_count" => 0,
        "request_count" => 1,
        "retry_allowed" => false,
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
end

function _quarantine_manifest_document(policy, transaction_id, records, failure_code)
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "canonicalization" => QUARANTINE_MANIFEST_CANONICALIZATION,
            "manifest_sha256" => repeat("0", 64),
            "schema_version" => QUARANTINE_MANIFEST_SCHEMA,
            "transaction_id" => transaction_id,
        ),
        "failure_code" => failure_code,
        "files" => records,
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
        "policy_id" => policy.policy_id,
        "policy_sha256" => policy_sha256(policy),
        "replica_count" => 2,
        "replica_fault_domain_count" => 1,
        "receipt_present" => false,
        "selector_evidence_present" => false,
        "status" => "NONADMITTING_QUARANTINE_RECEIVED_BYTES_PRESERVED_NO_RETRY",
    )
    document["artifact"]["manifest_sha256"] = _manifest_hash(document)
    return document
end

function _seal_quarantine_replica(
        staging,
        name,
        raw_name,
        body,
        transport_bytes,
        attestation_bytes,
    )
    directory = joinpath(staging, name)
    mkdir(directory; mode = 0o700)
    raw_path = joinpath(directory, raw_name)
    transport_path = joinpath(directory, "untrusted-transport.toml")
    attestation_path = joinpath(directory, "local-attestation.toml")
    _write_file(raw_path, body)
    _write_file(transport_path, transport_bytes)
    _write_file(attestation_path, attestation_bytes)
    read(raw_path) == body || fail("quarantine.$name", "raw reread differs")
    read(transport_path) == transport_bytes ||
        fail("quarantine.$name", "transport reread differs")
    read(attestation_path) == attestation_bytes ||
        fail("quarantine.$name", "attestation reread differs")
    return raw_path, transport_path, attestation_path
end

function _seal_quarantine(
        policy,
        paths,
        transaction_id,
        actor,
        terms_reviewed_date,
        response::FetchResponse,
        initial_clock::ClockSample,
        post_journal_clock::ClockSample,
        phase,
        failure_code,
        failure_detail,
    )
    ispath(paths.quarantine) && fail("quarantine", "final target already exists")
    ispath(paths.quarantine_staging) && fail("quarantine", "staging target already exists")
    mkdir(paths.quarantine_staging; mode = 0o700)
    snapshot = _response_snapshot(response)
    raw_name = "raw.$(policy.extension)"
    transport_bytes = _toml_bytes(_untrusted_transport_document(snapshot))
    attestation_bytes = _toml_bytes(
        _attestation_document(
            actor,
            terms_reviewed_date,
            initial_clock,
            post_journal_clock,
        )
    )
    replica_a = _seal_quarantine_replica(
        paths.quarantine_staging,
        "replica-a",
        raw_name,
        snapshot.body,
        transport_bytes,
        attestation_bytes,
    )
    replica_b = _seal_quarantine_replica(
        paths.quarantine_staging,
        "replica-b",
        raw_name,
        snapshot.body,
        transport_bytes,
        attestation_bytes,
    )
    for index in eachindex(replica_a)
        stat(replica_a[index]).inode != stat(replica_b[index]).inode ||
            fail("quarantine", "replicas share an inode")
    end
    failure = _quarantine_failure_document(
        policy,
        transaction_id,
        phase,
        failure_code,
        failure_detail,
        snapshot,
    )
    _write_file(
        joinpath(paths.quarantine_staging, "failure.toml"),
        _toml_bytes(failure),
    )
    relatives = [
        joinpath("replica-a", raw_name),
        joinpath("replica-a", "untrusted-transport.toml"),
        joinpath("replica-a", "local-attestation.toml"),
        joinpath("replica-b", raw_name),
        joinpath("replica-b", "untrusted-transport.toml"),
        joinpath("replica-b", "local-attestation.toml"),
        "failure.toml",
    ]
    records = [_file_record(paths.quarantine_staging, relative) for relative in relatives]
    manifest = _quarantine_manifest_document(
        policy,
        transaction_id,
        records,
        failure_code,
    )
    _write_file(
        joinpath(paths.quarantine_staging, "quarantine-manifest.toml"),
        _toml_bytes(manifest),
    )
    for (root, directories, files) in walkdir(paths.quarantine_staging; topdown = false)
        for file in files
            chmod(joinpath(root, file), 0o400)
        end
        for directory in directories
            chmod(joinpath(root, directory), 0o500)
        end
    end
    chmod(paths.quarantine_staging, 0o500)
    _fsync_directory(paths.quarantine_staging)
    _fsync_directory(dirname(paths.quarantine_staging))
    _write_journal(
        paths.journal,
        policy,
        transaction_id,
        "QUARANTINE_SEALED",
        true,
    )
    validate_quarantine(policy, paths.quarantine_staging)
    mv(paths.quarantine_staging, paths.quarantine)
    _fsync_directory(dirname(paths.quarantine))
    _write_journal(
        paths.journal,
        policy,
        transaction_id,
        "QUARANTINED_NONADMITTING",
        true,
    )
    return validate_quarantine(policy, paths.quarantine)
end

function _quarantine_and_rethrow(
        caught,
        policy,
        paths,
        transaction_id,
        actor,
        terms_reviewed_date,
        response,
        initial_clock,
        post_journal_clock,
        phase,
    )
    failure_code = QUARANTINE_FAILURES[phase]
    try
        _seal_quarantine(
            policy,
            paths,
            transaction_id,
            actor,
            terms_reviewed_date,
            response,
            initial_clock,
            post_journal_clock,
            phase,
            failure_code,
            caught,
        )
    catch preservation_error
        fail(
            "quarantine",
            "preservation failed after $failure_code; original=$(_safe_failure_detail(caught)); preservation=$(_safe_failure_detail(preservation_error))",
        )
    end
    throw(caught)
end

"""Validate a nonadmitting quarantine by reconstructing all derived fields."""
function validate_quarantine(
        policy::CapturePolicy,
        quarantine_path;
        recovery_mode = false,
    )
    recovery_mode isa Bool || fail("quarantine.recovery_mode", "must be Boolean")
    quarantine = String(quarantine_path)
    isabspath(quarantine) || fail("quarantine", "must be absolute")
    normpath(quarantine) == quarantine || fail("quarantine", "must be normalized")
    isdir(quarantine) || fail("quarantine", "missing directory")
    islink(quarantine) && fail("quarantine", "symbolic link forbidden")
    realpath(quarantine) == quarantine || fail("quarantine", "must be canonical")
    name = basename(quarantine)
    matched = match(r"^\.?(.+)\.quarantine(?:\.staging)?$", name)
    matched === nothing && fail("quarantine", "directory name is outside the closed layout")
    transaction_id = _identifier(matched.captures[1], "quarantine.transaction_id")
    manifest_path = joinpath(quarantine, "quarantine-manifest.toml")
    failure_path = joinpath(quarantine, "failure.toml")
    _check_components(manifest_path, quarantine; expect_file = true)
    _check_components(failure_path, quarantine; expect_file = true)
    (stat(manifest_path).mode & 0o222) == 0 ||
        fail("quarantine.manifest", "sealed manifest remains writable")
    manifest = TOML.parsefile(manifest_path)
    failure = TOML.parsefile(failure_path)
    _validate_integer_controls(manifest, "quarantine.manifest")
    _validate_integer_controls(failure, "quarantine.failure")
    _validate_bundle_directories(quarantine)
    manifest["artifact"]["schema_version"] == QUARANTINE_MANIFEST_SCHEMA ||
        fail("quarantine.manifest", "schema mismatch")
    manifest["artifact"]["transaction_id"] == transaction_id ||
        fail("quarantine.manifest", "transaction mismatch")
    manifest["artifact"]["manifest_sha256"] == _manifest_hash(manifest) ||
        fail("quarantine.manifest", "self hash mismatch")
    manifest["policy_id"] == policy.policy_id ||
        fail("quarantine.manifest", "policy mismatch")
    manifest["policy_sha256"] == policy_sha256(policy) ||
        fail("quarantine.manifest", "policy hash mismatch")
    manifest["receipt_present"] === false ||
        fail("quarantine.manifest", "receipt presence claim must be false")
    manifest["selector_evidence_present"] === false ||
        fail("quarantine.manifest", "selector evidence claim must be false")
    manifest["gates"] == ALWAYS_FALSE_GATES ||
        fail("quarantine.manifest", "a closed gate changed")
    _integer(manifest["replica_count"], "quarantine.manifest.replica_count") == 2 ||
        fail("quarantine.manifest", "replica count mismatch")
    _integer(
        manifest["replica_fault_domain_count"],
        "quarantine.manifest.replica_fault_domain_count",
    ) == 1 ||
        fail("quarantine.manifest", "fault-domain claim mismatch")
    record_map = _file_record_map(manifest)
    expected_files = sort!(vcat(collect(keys(record_map)), ["quarantine-manifest.toml"]))
    _relative_file_set(quarantine) == expected_files ||
        fail("quarantine", "file set differs from closed manifest")
    for (relative, record) in record_map
        occursin('\\', relative) && fail("quarantine.files", "backslash forbidden")
        startswith(relative, "/") && fail("quarantine.files", "absolute path forbidden")
        any(component -> component in ("", ".", ".."), split(relative, '/')) &&
            fail("quarantine.files", "non-canonical path")
        path = joinpath(quarantine, relative)
        _check_components(path, quarantine; expect_file = true)
        (stat(path).mode & 0o222) == 0 ||
            fail("quarantine.files.$relative", "sealed file remains writable")
        bytes = read(path)
        _integer(record["byte_count"], "quarantine.files.$relative.byte_count"; minimum = 0) ==
            length(bytes) ||
            fail("quarantine.files.$relative", "size mismatch")
        record["sha256"] == sha256_hex(bytes) ||
            fail("quarantine.files.$relative", "hash mismatch")
    end
    raw_name = "raw.$(policy.extension)"
    raw_paths = [joinpath(quarantine, replica, raw_name) for replica in ("replica-a", "replica-b")]
    transport_paths = [
        joinpath(quarantine, replica, "untrusted-transport.toml") for
            replica in ("replica-a", "replica-b")
    ]
    attestation_paths = [
        joinpath(quarantine, replica, "local-attestation.toml") for
            replica in ("replica-a", "replica-b")
    ]
    for paths in (raw_paths, transport_paths, attestation_paths)
        for path in paths
            _check_components(path, quarantine; expect_file = true)
        end
        stat(paths[1]).inode != stat(paths[2]).inode ||
            fail("quarantine", "replicas share an inode")
        read(paths[1]) == read(paths[2]) || fail("quarantine", "replicas differ")
    end
    raw = read(raw_paths[1])
    transport_bytes = read(transport_paths[1])
    transport = TOML.parse(String(transport_bytes))
    response = _response_from_transport(raw, transport)
    _toml_bytes(transport) == _toml_bytes(_untrusted_transport_document(response)) ||
        fail("quarantine.transport", "differs from reconstruction of preserved material")
    attestation_bytes = read(attestation_paths[1])
    attestation = TOML.parse(String(attestation_bytes))
    Set(keys(attestation)) == Set(
        [
            "schema_version",
            "actor",
            "actor_authentication",
            "clock_authentication",
            "initial_authorization_clock_observed_at_utc",
            "post_journal_issue_clock_observed_at_utc",
            "terms_reviewed_local_date",
            "terms_review_status",
        ]
    ) || fail("quarantine.attestation", "keys differ from closed schema")
    attestation["clock_authentication"] == CLOCK_AUTHENTICATION ||
        fail("quarantine.attestation", "clock authentication claim differs")
    initial_clock, post_journal_clock = _attestation_clocks(attestation)
    _authorize_clock_sample(policy, initial_clock, "quarantine.initial_authorization_clock")
    _authorize_clock_sample(policy, post_journal_clock, "quarantine.post_journal_issue_clock")
    review_date = _text(
        attestation["terms_reviewed_local_date"],
        "quarantine.attestation.terms_reviewed_local_date";
        maximum_bytes = 10,
    )
    review_date == _clock_text(initial_clock)[1:10] ||
        fail("quarantine.attestation", "review date differs from initial clock date")
    review_date == _clock_text(post_journal_clock)[1:10] ||
        fail("quarantine.attestation", "review date differs from post-journal clock date")
    expected_attestation = _attestation_document(
        _text(attestation["actor"], "quarantine.attestation.actor"; maximum_bytes = 256),
        review_date,
        initial_clock,
        post_journal_clock,
    )
    _toml_bytes(attestation) == _toml_bytes(expected_attestation) ||
        fail("quarantine.attestation", "differs from closed local assertion schema")
    failure["schema_version"] == QUARANTINE_FAILURE_SCHEMA ||
        fail("quarantine.failure", "schema mismatch")
    failure["gates"] == ALWAYS_FALSE_GATES || fail("quarantine.failure", "a closed gate changed")
    failure["completion_receipt_created"] === false ||
        fail("quarantine.failure", "completion receipt claim must be false")
    failure["selector_completion_claimed"] === false ||
        fail("quarantine.failure", "selector completion claim must be false")
    failure["profile_evidence_created"] === false ||
        fail("quarantine.failure", "profile evidence claim must be false")
    _integer(failure["profile_count"], "quarantine.failure.profile_count"; minimum = 0) == 0 ||
        fail("quarantine.failure", "profile count must be zero")
    _integer(failure["request_count"], "quarantine.failure.request_count"; minimum = 0) == 1 ||
        fail("quarantine.failure", "request count must equal one")
    _integer(
        failure["raw_body_byte_count"],
        "quarantine.failure.raw_body_byte_count";
        minimum = 0,
    ) == length(raw) || fail("quarantine.failure", "raw body byte count mismatch")
    phase = String(failure["failure_phase"])
    if phase == "RESPONSE_VALIDATION"
        replayed_error = try
            _validate_received_response(
                policy,
                response,
                review_date,
                post_journal_clock,
            )
            nothing
        catch error
            error
        end
        replayed_error === nothing &&
            fail("quarantine.failure", "claimed response failure does not replay")
        failure["failure_detail"] == _safe_failure_detail(replayed_error) ||
            fail("quarantine.failure", "response failure detail differs from pure replay")
    else
        try
            _validate_received_response(
                policy,
                response,
                review_date,
                post_journal_clock,
            )
        catch error
            fail(
                "quarantine.failure",
                "claimed post-response phase is inconsistent because response validation fails first: $(_safe_failure_detail(error))",
            )
        end
    end
    expected_failure = _quarantine_failure_document(
        policy,
        transaction_id,
        failure["failure_phase"],
        failure["failure_code"],
        failure["failure_detail"],
        response,
    )
    _toml_bytes(failure) == _toml_bytes(expected_failure) ||
        fail("quarantine.failure", "does not equal reconstruction from raw evidence")
    manifest["failure_code"] == failure["failure_code"] ||
        fail("quarantine.manifest", "failure code mismatch")
    relatives = [
        joinpath("replica-a", raw_name),
        joinpath("replica-a", "untrusted-transport.toml"),
        joinpath("replica-a", "local-attestation.toml"),
        joinpath("replica-b", raw_name),
        joinpath("replica-b", "untrusted-transport.toml"),
        joinpath("replica-b", "local-attestation.toml"),
        "failure.toml",
    ]
    Set(relatives) == Set(keys(record_map)) ||
        fail("quarantine.manifest", "closed material file set mismatch")
    expected_records = [_file_record(quarantine, relative) for relative in relatives]
    expected_manifest = _quarantine_manifest_document(
        policy,
        transaction_id,
        expected_records,
        failure["failure_code"],
    )
    _toml_bytes(manifest) == _toml_bytes(expected_manifest) ||
        fail("quarantine.manifest", "does not equal reconstruction from material files")
    parent = dirname(quarantine)
    lock_path = joinpath(parent, ".$transaction_id.exactly-once.lock")
    isdir(lock_path) || fail("quarantine.exactly_once_lock", "missing")
    islink(lock_path) && fail("quarantine.exactly_once_lock", "symbolic link forbidden")
    realpath(lock_path) == lock_path ||
        fail("quarantine.exactly_once_lock", "path must be canonical")
    journal_path = joinpath(parent, ".$transaction_id.private-recovery.toml")
    journal = _validate_journal(journal_path, policy, transaction_id)
    allowed_states = if endswith(name, ".staging")
        Set(["REQUEST_AUTHORIZED", "QUARANTINE_SEALED"])
    elseif recovery_mode
        Set(["QUARANTINE_SEALED", "QUARANTINED_NONADMITTING"])
    else
        Set(["QUARANTINED_NONADMITTING"])
    end
    journal["state"] in allowed_states ||
        fail("quarantine.journal", "state is inconsistent with publication state")
    journal["request_may_have_begun"] === true ||
        fail("quarantine.journal", "preserved response requires request_may_have_begun=true")
    return (
        status = "VALIDATED_NONADMITTING_QUARANTINE_NO_RETRY",
        quarantine_path = quarantine,
        transaction_id = transaction_id,
        body_sha256 = sha256_hex(raw),
        body_byte_count = length(raw),
        failure_code = failure["failure_code"],
        completion_receipt_created = false,
        selector_completion_claimed = false,
        gates = deepcopy(ALWAYS_FALSE_GATES),
    )
end

function _selector(selector_builder, body)
    selector_builder === nothing && return Dict{String, Any}(
        "status" => "NO_SELECTOR_SUPPLIED_FAIL_CLOSED",
        "profile_count" => 0,
        "all_profiles_verified" => false,
    )
    value = selector_builder(copy(body))
    value isa AbstractDict || fail("selector", "must return a table")
    document = Dict{String, Any}(String(key) => deepcopy(item) for (key, item) in value)
    _validate_integer_controls(document, "selector")
    get(document, "all_profiles_verified", false) isa Bool ||
        fail("selector", "all_profiles_verified must be Boolean")
    return document
end

function recover_transaction(
        policy::CapturePolicy;
        raw_root,
        transaction_id,
        selector_builder = nothing,
        timestamp_verifier = nothing,
    )
    root = _strict_root(raw_root)
    tx = _identifier(transaction_id, "transaction_id")
    paths = _transaction_paths(root, tx)
    isdir(paths.final) && isdir(paths.quarantine) &&
        fail("recovery", "both completion and quarantine targets exist")
    if isdir(paths.final)
        validate_bundle(
            policy,
            paths.final;
            selector_builder = selector_builder,
            timestamp_verifier = timestamp_verifier,
            recovery_mode = true,
        )
        journal = _validate_journal(paths.journal, policy, tx)
        journal["state"] == "REPLICAS_SEALED" &&
            _write_journal(paths.journal, policy, tx, "PUBLISHED", true)
        return validate_bundle(
            policy,
            paths.final;
            selector_builder = selector_builder,
            timestamp_verifier = timestamp_verifier,
        )
    end
    if isdir(paths.quarantine)
        validate_quarantine(policy, paths.quarantine; recovery_mode = true)
        journal = _validate_journal(paths.journal, policy, tx)
        journal["state"] == "QUARANTINE_SEALED" && _write_journal(
            paths.journal,
            policy,
            tx,
            "QUARANTINED_NONADMITTING",
            true,
        )
        return validate_quarantine(policy, paths.quarantine)
    end
    isfile(paths.journal) || fail("recovery", "journal is absent")
    journal = _validate_journal(paths.journal, policy, tx)
    if isdir(paths.quarantine_staging) &&
            isfile(joinpath(paths.quarantine_staging, "quarantine-manifest.toml"))
        validate_quarantine(policy, paths.quarantine_staging)
        _write_journal(paths.journal, policy, tx, "QUARANTINE_SEALED", true)
        ispath(paths.quarantine) && fail("recovery", "quarantine target appeared")
        mv(paths.quarantine_staging, paths.quarantine)
        _fsync_directory(root)
        _write_journal(paths.journal, policy, tx, "QUARANTINED_NONADMITTING", true)
        return validate_quarantine(policy, paths.quarantine)
    end
    if isdir(paths.staging) && isfile(joinpath(paths.staging, "manifest.toml"))
        validate_bundle(
            policy,
            paths.staging;
            selector_builder = selector_builder,
            timestamp_verifier = timestamp_verifier,
        )
        ispath(paths.final) && fail("recovery", "final target appeared")
        mv(paths.staging, paths.final)
        _fsync_directory(root)
        _write_journal(paths.journal, policy, tx, "PUBLISHED", true)
        return validate_bundle(
            policy,
            paths.final;
            selector_builder = selector_builder,
            timestamp_verifier = timestamp_verifier,
        )
    end
    return fail(
        "recovery",
        "journal state $(journal["state"]) cannot prove a complete local bundle; no retry allowed",
    )
end

"""
    capture_with_fetcher(policy; ..., execute_live=false)

The envelope has no built-in network implementation. `fetcher` is invoked exactly
once only when `execute_live=true`, after the exactly-once lock and private journal
are durable. Any pre-existing final bundle or journal suppresses a new request.
"""
function capture_with_fetcher(
        policy::CapturePolicy;
        raw_root,
        transaction_id,
        actor,
        terms_reviewed_local_date,
        execute_live = false,
        fetcher = nothing,
        selector_builder = nothing,
        timestamp_provider = nothing,
        timestamp_verifier = nothing,
        clock_source = system_clock_source(),
    )
    plan = dry_run_plan(policy, transaction_id)
    execute_live isa Bool || fail("execute_live", "must be Boolean")
    execute_live || return plan
    fetcher === nothing && fail("fetcher", "required only for explicit live execution")
    root = _strict_root(raw_root)
    tx = plan.transaction_id
    actor_text = _text(actor, "actor"; maximum_bytes = 256)
    review_date = _text(terms_reviewed_local_date, "terms_reviewed_local_date"; maximum_bytes = 10)
    occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", review_date) ||
        fail("terms_reviewed_local_date", "must use YYYY-MM-DD")
    tryparse(Date, review_date) === nothing &&
        fail("terms_reviewed_local_date", "invalid calendar date")
    paths = _transaction_paths(root, tx)
    isdir(paths.final) && isdir(paths.quarantine) &&
        fail("capture", "both completion and quarantine targets exist")
    if isdir(paths.final) || isdir(paths.quarantine) || isfile(paths.journal) ||
            isdir(paths.lock) || isdir(paths.staging) ||
            isdir(paths.quarantine_staging)
        return recover_transaction(
            policy;
            raw_root = root,
            transaction_id = tx,
            selector_builder = selector_builder,
            timestamp_verifier = timestamp_verifier,
        )
    end
    # First fail-closed gate: this sample occurs before the exactly-once lock,
    # journal, or any other transaction mutation.
    initial_clock = _authorize_clock_sample(
        policy,
        _sample_clock(clock_source, "clock.initial_authorization"),
        "clock.initial_authorization",
    )
    review_date == _clock_text(initial_clock)[1:10] ||
        fail(
        "terms_reviewed_local_date",
        "must equal the initial authorization clock's UTC date",
    )
    mkdir(paths.lock; mode = 0o700)
    _fsync_directory(root)
    _write_journal(paths.journal, policy, tx, "PREPARED_NO_REQUEST", false)
    _write_journal(paths.journal, policy, tx, "REQUEST_AUTHORIZED", true)
    # Second fail-closed gate: resample after the durable journal. The fetcher
    # callback is the next effectful operation; response-supplied timestamps do
    # not authorize reachability of this callback.
    post_journal_clock = _authorize_clock_sample(
        policy,
        _sample_clock(clock_source, "clock.post_journal_issue"),
        "clock.post_journal_issue",
    )
    initial_clock.observed_at_utc <= post_journal_clock.observed_at_utc ||
        fail("clock.post_journal_issue", "precedes the initial authorization sample")
    review_date == _clock_text(post_journal_clock)[1:10] ||
        fail(
        "terms_reviewed_local_date",
        "must equal the post-journal issue clock's UTC date",
    )
    raw_response = fetcher(
        policy.requested_url,
        copy(policy.request_headers),
        policy.maximum_body_bytes,
        policy.maximum_duration_seconds,
    )
    raw_response isa FetchResponse || fail("fetcher", "must return FetchResponse")
    validated = try
        _validate_received_response(
            policy,
            raw_response,
            review_date,
            post_journal_clock,
        )
    catch error
        _quarantine_and_rethrow(
            error,
            policy,
            paths,
            tx,
            actor_text,
            review_date,
            raw_response,
            initial_clock,
            post_journal_clock,
            "RESPONSE_VALIDATION",
        )
    end
    selector = try
        _selector(selector_builder, validated.response.body)
    catch error
        _quarantine_and_rethrow(
            error,
            policy,
            paths,
            tx,
            actor_text,
            review_date,
            validated.response,
            initial_clock,
            post_journal_clock,
            "SELECTOR_VALIDATION",
        )
    end
    timestamp_evidence, timestamp_document = try
        evidence = timestamp_provider === nothing ? nothing : timestamp_provider(
                validated.body_sha256,
                validated.response.response_body_completed_at_utc,
            )
        document = _timestamp_document(
            evidence,
            timestamp_verifier,
            validated.body_sha256,
        )
        evidence, document
    catch error
        _quarantine_and_rethrow(
            error,
            policy,
            paths,
            tx,
            actor_text,
            review_date,
            validated.response,
            initial_clock,
            post_journal_clock,
            "TIMESTAMP_EVIDENCE",
        )
    end
    _write_journal(paths.journal, policy, tx, "RESPONSE_VALIDATED", true)
    _seal_bundle(
        policy,
        paths,
        tx,
        actor_text,
        review_date,
        validated,
        selector,
        timestamp_evidence,
        timestamp_document,
        initial_clock,
        post_journal_clock,
    )
    _write_journal(paths.journal, policy, tx, "REPLICAS_SEALED", true)
    validate_bundle(
        policy,
        paths.staging;
        selector_builder = selector_builder,
        timestamp_verifier = timestamp_verifier,
    )
    ispath(paths.final) && fail("publish", "final target appeared")
    mv(paths.staging, paths.final)
    _fsync_directory(root)
    _write_journal(paths.journal, policy, tx, "PUBLISHED", true)
    return validate_bundle(
        policy,
        paths.final;
        selector_builder = selector_builder,
        timestamp_verifier = timestamp_verifier,
    )
end

function _relative_file_set(bundle)
    result = String[]
    for (root, _, files) in walkdir(bundle)
        for file in files
            path = joinpath(root, file)
            islink(path) && fail("bundle", "internal symbolic-link path forbidden")
            push!(result, relpath(path, bundle))
        end
    end
    return sort!(result)
end

function _validate_bundle_directories(bundle)
    (stat(bundle).mode & 0o222) == 0 || fail("bundle", "sealed directory remains writable")
    observed = String[]
    for (root, directories, _) in walkdir(bundle; follow_symlinks = false)
        for directory in directories
            path = joinpath(root, directory)
            islink(path) && fail("bundle", "internal symbolic-link directory forbidden")
            (stat(path).mode & 0o222) == 0 ||
                fail("bundle", "sealed internal directory remains writable")
            push!(observed, relpath(path, bundle))
        end
    end
    sort!(observed)
    observed == ["replica-a", "replica-b"] ||
        fail("bundle", "directory set differs from closed two-replica layout")
    return observed
end

function _file_record_map(manifest)
    result = Dict{String, Dict{String, Any}}()
    for row in manifest["files"]
        path = String(row["path"])
        haskey(result, path) && fail("manifest.files", "duplicate path")
        result[path] = Dict{String, Any}(String(k) => v for (k, v) in row)
    end
    return result
end

"""Reconstruct every receipt field from raw, transport, policy, and selector evidence."""
function validate_bundle(
        policy::CapturePolicy,
        bundle_path;
        selector_builder = nothing,
        timestamp_verifier = nothing,
        recovery_mode = false,
    )
    recovery_mode isa Bool || fail("bundle.recovery_mode", "must be Boolean")
    bundle = String(bundle_path)
    isabspath(bundle) || fail("bundle", "must be absolute")
    normpath(bundle) == bundle || fail("bundle", "must be normalized")
    isdir(bundle) || fail("bundle", "missing directory")
    islink(bundle) && fail("bundle", "symbolic link forbidden")
    realpath(bundle) == bundle || fail("bundle", "must be canonical")
    transaction_id = basename(bundle)
    startswith(transaction_id, ".") &&
        (transaction_id = replace(transaction_id, r"^\." => "", r"\.staging$" => ""))
    _identifier(transaction_id, "bundle.transaction_id")
    manifest_path = joinpath(bundle, "manifest.toml")
    receipt_path = joinpath(bundle, "receipt.toml")
    _check_components(manifest_path, bundle; expect_file = true)
    _check_components(receipt_path, bundle; expect_file = true)
    (stat(manifest_path).mode & 0o222) == 0 ||
        fail("manifest", "sealed manifest remains writable")
    manifest = TOML.parsefile(manifest_path)
    receipt = TOML.parsefile(receipt_path)
    _validate_integer_controls(manifest, "manifest")
    _validate_integer_controls(receipt, "receipt")
    _validate_bundle_directories(bundle)
    manifest["artifact"]["schema_version"] == MANIFEST_SCHEMA ||
        fail("manifest", "schema mismatch")
    manifest["artifact"]["transaction_id"] == transaction_id ||
        fail("manifest", "transaction mismatch")
    manifest["artifact"]["manifest_sha256"] == _manifest_hash(manifest) ||
        fail("manifest", "self hash mismatch")
    manifest["policy_id"] == policy.policy_id || fail("manifest", "policy mismatch")
    manifest["policy_sha256"] == policy_sha256(policy) ||
        fail("manifest", "policy hash mismatch")
    _integer(manifest["replica_count"], "manifest.replica_count") == 2 ||
        fail("manifest", "replica count mismatch")
    _integer(
        manifest["replica_fault_domain_count"],
        "manifest.replica_fault_domain_count",
    ) == 1 ||
        fail("manifest", "fault-domain claim mismatch")
    record_map = _file_record_map(manifest)
    expected_files = sort!(vcat(collect(keys(record_map)), ["manifest.toml"]))
    _relative_file_set(bundle) == expected_files ||
        fail("bundle", "file set differs from manifest")
    for (relative, record) in record_map
        occursin('\\', relative) && fail("manifest.files", "backslash forbidden")
        startswith(relative, "/") && fail("manifest.files", "absolute path forbidden")
        any(component -> component in ("", ".", ".."), split(relative, '/')) &&
            fail("manifest.files", "non-canonical path")
        path = joinpath(bundle, relative)
        _check_components(path, bundle; expect_file = true)
        (stat(path).mode & 0o222) == 0 ||
            fail("manifest.files.$relative", "sealed file remains writable")
        bytes = read(path)
        _integer(record["byte_count"], "manifest.files.$relative.byte_count"; minimum = 0) ==
            length(bytes) || fail("manifest.files.$relative", "size mismatch")
        record["sha256"] == sha256_hex(bytes) || fail("manifest.files.$relative", "hash mismatch")
    end
    raw_name = "raw.$(policy.extension)"
    raw_a_path = joinpath(bundle, "replica-a", raw_name)
    raw_b_path = joinpath(bundle, "replica-b", raw_name)
    transport_a_path = joinpath(bundle, "replica-a", "transport.toml")
    transport_b_path = joinpath(bundle, "replica-b", "transport.toml")
    attestation_a_path = joinpath(bundle, "replica-a", "attestation.toml")
    attestation_b_path = joinpath(bundle, "replica-b", "attestation.toml")
    for path in (
            raw_a_path,
            raw_b_path,
            transport_a_path,
            transport_b_path,
            attestation_a_path,
            attestation_b_path,
        )
        _check_components(path, bundle; expect_file = true)
    end
    stat(raw_a_path).inode != stat(raw_b_path).inode || fail("bundle", "raw replicas share inode")
    stat(transport_a_path).inode != stat(transport_b_path).inode ||
        fail("bundle", "transport replicas share inode")
    stat(attestation_a_path).inode != stat(attestation_b_path).inode ||
        fail("bundle", "attestation replicas share inode")
    raw_a = read(raw_a_path)
    raw_b = read(raw_b_path)
    raw_a == raw_b || fail("bundle", "raw replicas differ")
    transport_a = read(transport_a_path)
    transport_b = read(transport_b_path)
    transport_a == transport_b || fail("bundle", "transport replicas differ")
    attestation_a = read(attestation_a_path)
    attestation_b = read(attestation_b_path)
    attestation_a == attestation_b || fail("bundle", "attestation replicas differ")
    attestation = TOML.parse(String(attestation_a))
    Set(keys(attestation)) == Set(
        [
            "schema_version",
            "actor",
            "actor_authentication",
            "clock_authentication",
            "initial_authorization_clock_observed_at_utc",
            "post_journal_issue_clock_observed_at_utc",
            "terms_reviewed_local_date",
            "terms_review_status",
        ],
    ) || fail("attestation", "keys differ from closed schema")
    attestation["clock_authentication"] == CLOCK_AUTHENTICATION ||
        fail("attestation", "clock authentication claim differs")
    initial_clock, post_journal_clock = _attestation_clocks(attestation)
    _authorize_clock_sample(policy, initial_clock, "attestation.initial_authorization_clock")
    _authorize_clock_sample(policy, post_journal_clock, "attestation.post_journal_issue_clock")
    expected_attestation = _attestation_document(
        _text(attestation["actor"], "attestation.actor"; maximum_bytes = 256),
        _text(
            attestation["terms_reviewed_local_date"],
            "attestation.terms_reviewed_local_date";
            maximum_bytes = 10,
        ),
        initial_clock,
        post_journal_clock,
    )
    _toml_bytes(attestation) == _toml_bytes(expected_attestation) ||
        fail("attestation", "content differs from closed local assertion schema")
    transport = TOML.parse(String(transport_a))
    reconstructed_response = _response_from_transport(raw_a, transport)
    validated = validate_response(policy, reconstructed_response)
    transport["body_sha256"] == validated.body_sha256 || fail("transport", "body hash mismatch")
    _integer(transport["body_byte_count"], "transport.body_byte_count"; minimum = 0) ==
        validated.body_byte_count || fail("transport", "body size mismatch")
    transport["content_type"] == validated.content_type || fail("transport", "content type mismatch")
    transport["content_encoding"] == validated.content_encoding ||
        fail("transport", "content encoding mismatch")
    _integer(transport["header_bytes"], "transport.header_bytes"; minimum = 0) ==
        validated.header_bytes || fail("transport", "header bytes mismatch")
    _integer(
        transport["duration_milliseconds"],
        "transport.duration_milliseconds";
        minimum = 0,
    ) == validated.duration_milliseconds ||
        fail("transport", "duration mismatch")
    selector = _selector(selector_builder, raw_a)
    external = receipt["external_timestamp"]
    timestamp_document = if _boolean(external["established"], "receipt.external_timestamp.established")
        token_a_path = joinpath(bundle, "replica-a", "external-timestamp-token.bin")
        token_b_path = joinpath(bundle, "replica-b", "external-timestamp-token.bin")
        for path in (token_a_path, token_b_path)
            _check_components(path, bundle; expect_file = true)
        end
        token_a = read(token_a_path)
        token_b = read(token_b_path)
        token_a == token_b || fail("timestamp", "replicas differ")
        evidence = TimestampEvidence(external["provider"], external["issued_at_utc"], token_a)
        _timestamp_document(evidence, timestamp_verifier, validated.body_sha256)
    else
        _timestamp_document(nothing, nothing, validated.body_sha256)
    end
    expected_receipt = _receipt_document(
        policy,
        transaction_id,
        attestation["actor"],
        attestation["terms_reviewed_local_date"],
        validated,
        selector,
        timestamp_document,
        initial_clock,
        post_journal_clock,
    )
    _toml_bytes(receipt) == _toml_bytes(expected_receipt) ||
        fail("receipt", "does not equal reconstruction from raw and manifest evidence")
    receipt["artifact"]["receipt_sha256"] == _receipt_hash(receipt) ||
        fail("receipt", "self hash mismatch")
    manifest["receipt_sha256"] == receipt["artifact"]["receipt_sha256"] ||
        fail("manifest", "receipt hash mismatch")
    ordered_relatives = [
        joinpath("replica-a", raw_name),
        joinpath("replica-a", "transport.toml"),
        joinpath("replica-a", "attestation.toml"),
        joinpath("replica-b", raw_name),
        joinpath("replica-b", "transport.toml"),
        joinpath("replica-b", "attestation.toml"),
    ]
    if timestamp_document["established"]
        push!(ordered_relatives, joinpath("replica-a", "external-timestamp-token.bin"))
        push!(ordered_relatives, joinpath("replica-b", "external-timestamp-token.bin"))
    end
    push!(ordered_relatives, "receipt.toml")
    Set(ordered_relatives) == Set(keys(record_map)) ||
        fail("manifest", "closed material file set mismatch")
    expected_records = [_file_record(bundle, relative) for relative in ordered_relatives]
    expected_manifest = _manifest_document(
        policy,
        transaction_id,
        expected_records,
        receipt["artifact"]["receipt_sha256"],
    )
    _toml_bytes(manifest) == _toml_bytes(expected_manifest) ||
        fail("manifest", "does not equal reconstruction from material files")
    parent = dirname(bundle)
    lock_path = joinpath(parent, ".$transaction_id.exactly-once.lock")
    isdir(lock_path) || fail("exactly_once_lock", "missing")
    islink(lock_path) && fail("exactly_once_lock", "symbolic link forbidden")
    realpath(lock_path) == lock_path ||
        fail("exactly_once_lock", "path must be canonical")
    journal_path = joinpath(parent, ".$transaction_id.private-recovery.toml")
    journal = _validate_journal(journal_path, policy, transaction_id)
    allowed_states = if startswith(basename(bundle), ".")
        Set(["RESPONSE_VALIDATED", "REPLICAS_SEALED"])
    elseif recovery_mode
        Set(["REPLICAS_SEALED", "PUBLISHED"])
    else
        Set(["PUBLISHED"])
    end
    journal["state"] in allowed_states ||
        fail("journal", "state is inconsistent with bundle publication state")
    journal["request_may_have_begun"] === true ||
        fail("journal", "published material requires request_may_have_begun=true")
    return (
        status = "VALIDATED_NONADMITTING_PROSPECTIVE_SNAPSHOT_BUNDLE",
        bundle_path = bundle,
        transaction_id = transaction_id,
        body_sha256 = validated.body_sha256,
        body_byte_count = validated.body_byte_count,
        receipt_sha256 = receipt["artifact"]["receipt_sha256"],
        manifest_sha256 = manifest["artifact"]["manifest_sha256"],
        selector = selector,
        external_timestamp_established = timestamp_document["established"],
        gates = deepcopy(ALWAYS_FALSE_GATES),
    )
end

end # module
