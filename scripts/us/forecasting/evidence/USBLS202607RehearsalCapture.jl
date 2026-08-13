module USBLS202607RehearsalCapture

using Dates
using Downloads
using Random
using SHA
using TOML

include(joinpath(@__DIR__, "USBLS202607RehearsalReceipt.jl"))
using .USBLS202607RehearsalReceipt

export CapturedResponse,
    RehearsalCaptureError,
    acquire_live_rehearsal,
    install_rehearsal_capture,
    install_rehearsal_attempt_journal,
    install_rehearsal_news_diagnostic,
    validate_rehearsal_news_diagnostic_file,
    validate_rehearsal_attempt_journal_file

const ReceiptVerifier = USBLS202607RehearsalReceipt
const API_WITH_NEWS_MODE =
    "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_PLUS_NEWS_BYTES"
const API_FALLBACK_MODE =
    "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK"
const API_OBJECT_ID = "bls_v2_endpoint_unregistered_response"
const HTML_OBJECT_ID = "employment_situation_release_html"
const PDF_OBJECT_ID = "employment_situation_release_pdf"
const API_REQUEST_BODY =
"""{"seriesid":["CES0000000001","LNS14000000"],"startyear":"2026","endyear":"2026"}"""
const EVENT_START = DateTime(2026, 8, 7, 12, 30)
const EVENT_DEADLINE = DateTime(2026, 8, 7, 12, 45)
const UNREGISTERED_API_DAILY_LIMIT = 25
const LIVE_REQUEST_TIMEOUT_SECONDS = 12
const LIVE_TRANSPORT_POLICY =
    "DIRECT_TLS_NO_REDIRECT_NO_NETRC_NO_COOKIES_NO_AMBIENT_PROXY"
const LIVE_BODY_LIMITS = Dict(
    API_OBJECT_ID => 1 * 1024 * 1024,
    HTML_OBJECT_ID => 2 * 1024 * 1024,
    PDF_OBJECT_ID => 8 * 1024 * 1024,
)
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const CAPTURE_AGENT = "beforeit-bls-employment-rehearsal"
const CAPTURE_AGENT_VERSION = "1.0.0"
const JOURNAL_SCHEMA =
    "beforeit-us-bls-employment-rehearsal-attempt-journal.v1"
const JOURNAL_SCOPE =
    "BLS_2026_07_CAPTURE_REHEARSAL_DIAGNOSTICS_ONLY"
const NEWS_DIAGNOSTIC_SCHEMA =
    "beforeit-us-bls-employment-rehearsal-news-diagnostic.v1"
const NEWS_DIAGNOSTIC_SCOPE =
    "BLS_2026_07_UNBOUND_HOST_NEWS_REHEARSAL_DIAGNOSTICS_ONLY"
const JOURNAL_ROOT_KEYS = Set(
    [
        "artifact",
        "contract_binding",
        "event",
        "journal",
        "attempts",
        "attempt_objects",
        "storage",
        "attestation",
        "disposition",
    ],
)
const JOURNAL_ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "journal_id",
        "scope",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const JOURNAL_KEYS = Set(
    [
        "transaction_id",
        "observer_id",
        "capture_agent",
        "capture_agent_version",
        "capture_agent_source_sha256",
        "receipt_verifier_source_sha256",
        "source_revision",
        "recorded_at_utc",
        "clock_basis",
        "api_attempt_count",
        "state",
        "terminal",
        "failure_reason",
    ],
)
const JOURNAL_STORAGE_KEYS = Set(
    [
        "policy",
        "copy_ids",
        "minimum_local_copy_count",
        "external_durable_storage_attestation_status",
    ],
)
const JOURNAL_ATTESTATION_KEYS = Set(
    [
        "capture_clock_attestation_status",
        "source_transport_attestation_status",
        "external_timestamp_attestation_status",
        "cryptographic_signoff_status",
    ],
)
const JOURNAL_DISPOSITION_KEYS = Set(
    [
        "rehearsal_only",
        "diagnostics_only",
        "origin_evidence",
        "origin_admissible",
        "ready",
        "inventory_mutation_authorized",
        "accuracy_evaluation_allowed",
    ],
)
const JOURNAL_STATES = Set(
    [
        "POLLING",
        "ACCEPTED_M07_PENDING_BUNDLE",
        "BUNDLE_INSTALLED",
        "FAILED",
    ],
)
const JOURNAL_FAILURE_REASONS = Set(
    [
        "API_DEADLINE_REACHED",
        "BUNDLE_INSTALLATION_FAILED",
        "CLOCK_FAILURE",
        "FETCH_CONTRACT_VIOLATION",
        "MAXIMUM_API_ATTEMPTS_EXHAUSTED",
        "NO_ACCEPTED_M07_RESPONSE",
        "OUTSIDE_EVENT_WINDOW",
        "WAIT_FAILED",
    ],
)
const NEWS_DIAGNOSTIC_ROOT_KEYS = Set(
    [
        "artifact",
        "contract_binding",
        "event",
        "diagnostic",
        "attempts",
        "storage",
        "attestation",
        "disposition",
    ],
)
const NEWS_DIAGNOSTIC_ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "diagnostic_id",
        "scope",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const NEWS_DIAGNOSTIC_KEYS = Set(
    [
        "transaction_id",
        "observer_id",
        "capture_agent",
        "capture_agent_version",
        "capture_agent_source_sha256",
        "receipt_verifier_source_sha256",
        "source_revision",
        "recorded_at_utc",
        "clock_basis",
        "transport_policy",
        "api_checkpoint_binding_status",
        "attempt_count",
    ],
)
const NEWS_ATTEMPT_KEYS = Set(
    [
        "object_id",
        "reported_object_id",
        "requested_url",
        "effective_url",
        "attempted_at_utc",
        "response_metadata_observed_at_utc",
        "acquisition_completed_at_utc",
        "status_code",
        "content_type",
        "response_headers",
        "raw_sha256",
        "raw_byte_count",
        "primary_path",
        "replica_path",
        "outcome",
        "detail",
    ],
)
const NEWS_STORAGE_KEYS = Set(
    [
        "policy",
        "copy_ids",
        "minimum_local_copy_count",
        "diagnostic_replica_required",
        "external_durable_storage_attestation_status",
    ],
)
const NEWS_ATTESTATION_KEYS = Set(
    [
        "capture_clock_attestation_status",
        "source_transport_attestation_status",
        "external_timestamp_attestation_status",
        "cryptographic_signoff_status",
    ],
)
const NEWS_DISPOSITION_KEYS = Set(
    [
        "rehearsal_only",
        "diagnostics_only",
        "origin_evidence",
        "origin_admissible",
        "ready",
        "inventory_mutation_authorized",
        "accuracy_evaluation_allowed",
    ],
)
const NEWS_REJECTED_OUTCOMES = Set(
    [
        "REQUEST_FAILED",
        "FETCH_CONTRACT_VIOLATION",
        "HTTP_NON_200",
        "REJECTED_OBJECT_ID",
        "REJECTED_OFFICIAL_ROUTE",
        "REJECTED_REDIRECT",
        "REJECTED_MEDIA_TYPE",
        "REJECTED_RESPONSE_HEADERS",
        "REJECTED_TIMING",
        "REJECTED_RELEASE_IDENTITY",
        "REJECTED_PDF_SIGNATURE",
    ],
)
const NEWS_VALID_FINAL_OUTCOMES = Set(
    [
        "VALIDATED_COMPLETE_NEWS_SET",
        "VALIDATED_NOT_INSTALLED_INCOMPLETE_SET",
    ],
)
const USER_AGENT =
    "BeforeIT-US-Forecast-Rehearsal/1.0 (+https://github.com/marketsreplica/US_BeforeIT.jl)"

struct RehearsalCaptureError <: Exception
    message::String
end

Base.showerror(io::IO, error::RehearsalCaptureError) =
    print(io, error.message)

fail(location, message) =
    throw(RehearsalCaptureError("$location: $message"))

Base.@kwdef struct CapturedResponse
    object_id::String
    body::Vector{UInt8}
    requested_url::String
    effective_url::String = requested_url
    status_code::Int
    content_type::String
    response_headers::Vector{String}
    acquisition_started_at_utc::DateTime
    response_metadata_observed_at_utc::DateTime
    acquisition_completed_at_utc::DateTime
end

sha256_hex(bytes) = bytes2hex(sha256(bytes))

function current_source_revision()
    claimed = get(ENV, "GITHUB_SHA", "")
    occursin(r"^[0-9a-f]{40}$", claimed) ||
        return "UNVERIFIED_LOCAL_WORKTREE"
    repository_root = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
    source_paths = [
        relpath(@__FILE__, repository_root),
        relpath(
            joinpath(@__DIR__, "USBLS202607RehearsalReceipt.jl"),
            repository_root,
        ),
    ]
    try
        head = readchomp(`git -C $repository_root rev-parse HEAD`)
        head == claimed || return "UNVERIFIED_LOCAL_WORKTREE"
        for source_path in source_paths
            success(
                `git -C $repository_root ls-files --error-unmatch -- $source_path`,
            ) || return "UNVERIFIED_LOCAL_WORKTREE"
        end
        success(`git -C $repository_root diff --quiet HEAD -- $source_paths`) ||
            return "UNVERIFIED_LOCAL_WORKTREE"
    catch
        return "UNVERIFIED_LOCAL_WORKTREE"
    end
    return claimed
end

function _default_transaction_id(;
        clock = () -> now(UTC),
        nonce_bytes = () -> rand(RandomDevice(), UInt8, 16),
    )
    instant = clock()
    instant isa DateTime ||
        fail("transaction ID", "clock must return a DateTime")
    nonce = Vector{UInt8}(nonce_bytes())
    length(nonce) == 16 ||
        fail("transaction ID", "nonce source must return 16 bytes")
    return "host-" *
        lowercase(Dates.format(instant, dateformat"yyyymmddTHHMMSS")) *
        "-" *
        bytes2hex(nonce)
end

timestamp(value::DateTime) =
    Dates.format(value, TIMESTAMP_FORMAT) * "Z"

canonical_second(value::DateTime) =
    DateTime(Dates.format(value, TIMESTAMP_FORMAT), TIMESTAMP_FORMAT)

function _expected_object(object_id)
    haskey(ReceiptVerifier.EXPECTED_OBJECTS, object_id) ||
        fail("response.object_id", "unknown rehearsal object '$object_id'")
    return ReceiptVerifier.EXPECTED_OBJECTS[object_id]
end

function _validate_response_shape(response, index)
    location = "responses[$index]"
    expected = _expected_object(response.object_id)
    isempty(response.body) && fail("$location.body", "must not be empty")
    response.requested_url == expected.requested_url ||
        fail("$location.requested_url", "official locator mismatch")
    response.effective_url == expected.requested_url ||
        fail("$location.effective_url", "unexpected redirect")
    response.status_code == 200 ||
        fail("$location.status_code", "must be HTTP 200")
    ReceiptVerifier._media_type_token(response.content_type) ==
        expected.media_type ||
        fail("$location.content_type", "media type mismatch")
    response.acquisition_started_at_utc <=
        response.response_metadata_observed_at_utc <=
        response.acquisition_completed_at_utc ||
        fail(location, "timestamps are not ordered")
    ReceiptVerifier.validate_response_headers(
        response.response_headers,
        response.content_type,
        "$location.response_headers",
    )
    return expected
end

function _capture_mode(responses)
    ids = Set(response.object_id for response in responses)
    if ids == Set([API_OBJECT_ID, HTML_OBJECT_ID, PDF_OBJECT_ID])
        return API_WITH_NEWS_MODE
    elseif ids == Set([API_OBJECT_ID])
        return API_FALLBACK_MODE
    end
    return fail(
        "responses",
        "must contain API only or API plus both news-release objects",
    )
end

function _object_record(response, expected)
    digest = sha256_hex(response.body)
    name = "raw-sha256-$digest.$(expected.extension)"
    request_hash =
        expected.http_method == "POST" ?
        sha256_hex(codeunits(expected.request_body)) : "NOT_APPLICABLE"
    return Dict{String, Any}(
        "object_id" => response.object_id,
        "role" => expected.role,
        "requested_url" => response.requested_url,
        "effective_url" => response.effective_url,
        "http_method" => expected.http_method,
        "request_body" => expected.request_body,
        "request_body_sha256" => request_hash,
        "status_code" => response.status_code,
        "content_type" => response.content_type,
        "response_headers" => response.response_headers,
        "acquisition_started_at_utc" =>
            timestamp(response.acquisition_started_at_utc),
        "response_metadata_observed_at_utc" =>
            timestamp(response.response_metadata_observed_at_utc),
        "acquisition_completed_at_utc" =>
            timestamp(response.acquisition_completed_at_utc),
        "raw_sha256" => digest,
        "raw_byte_count" => length(response.body),
        "primary_path" => "replica-a/$name",
        "replica_path" => "replica-b/$name",
    )
end

function _attempt_value(attempt, name)
    if attempt isa NamedTuple
        hasproperty(attempt, name) ||
            fail("API attempts", "missing $(String(name))")
        return getproperty(attempt, name)
    elseif attempt isa AbstractDict
        key = String(name)
        haskey(attempt, key) ||
            fail("API attempts", "missing $key")
        return attempt[key]
    end
    return fail("API attempts", "each attempt must be a named record")
end

function _attempt_records(api_attempts, api_response)
    source = if api_attempts === nothing
        [
            (
                attempt_number = 1,
                attempted_at_utc =
                    timestamp(api_response.acquisition_started_at_utc),
                status_code = api_response.status_code,
                response_sha256 = sha256_hex(api_response.body),
                outcome = "ACCEPTED_M07",
                detail = "CES_AND_CPS_M07_PRESENT",
            ),
        ]
    else
        collect(api_attempts)
    end
    isempty(source) &&
        fail("API attempts", "must contain an accepted attempt")
    return [
        begin
                outcome = String(_attempt_value(attempt, :outcome))
                Dict{String, Any}(
                    "attempt_number" =>
                    Int(_attempt_value(attempt, :attempt_number)),
                    "object_id" => API_OBJECT_ID,
                    "attempted_at_utc" =>
                    String(_attempt_value(attempt, :attempted_at_utc)),
                    "status_code" => Int(_attempt_value(attempt, :status_code)),
                    "response_sha256" =>
                    String(_attempt_value(attempt, :response_sha256)),
                    "outcome" => outcome,
                    "detail" => String(_attempt_value(attempt, :detail)),
                    "accepted" => outcome == "ACCEPTED_M07",
                )
            end for attempt in source
    ]
end

function _attempt_object_records(
        attempt_records,
        api_response,
        api_attempt_bodies,
    )
    provided = Dict{String, Vector{UInt8}}()
    for (digest, bytes) in pairs(api_attempt_bodies)
        key = String(digest)
        value = Vector{UInt8}(bytes)
        sha256_hex(value) == key ||
            fail("API attempt bodies", "body hash does not match key $key")
        provided[key] = value
    end
    accepted_digest = sha256_hex(api_response.body)
    if haskey(provided, accepted_digest)
        provided[accepted_digest] == api_response.body ||
            fail("API attempt bodies", "accepted response bytes conflict")
    else
        provided[accepted_digest] = api_response.body
    end
    referenced = Set(
        row["response_sha256"] for row in attempt_records if
            row["response_sha256"] != "unavailable"
    )
    Set(keys(provided)) == referenced ||
        fail("API attempt bodies", "must contain every and only retained response")
    diagnostic_hashes = sort!(collect(setdiff(referenced, Set([accepted_digest]))))
    records = [
        Dict{String, Any}(
                "raw_sha256" => digest,
                "raw_byte_count" => length(provided[digest]),
                "primary_path" =>
                "replica-a/api-attempt-raw-sha256-$digest.bin",
                "replica_path" =>
                "replica-b/api-attempt-raw-sha256-$digest.bin",
            ) for digest in diagnostic_hashes
    ]
    return (; records, bodies = provided)
end

function _journal_attempt_object_records(attempt_records, api_attempt_bodies)
    provided = Dict{String, Vector{UInt8}}(
        String(digest) => Vector{UInt8}(bytes)
            for (digest, bytes) in pairs(api_attempt_bodies)
    )
    for (digest, bytes) in provided
        sha256_hex(bytes) == digest ||
            fail("API attempt bodies", "body hash does not match key $digest")
    end
    referenced = Set(
        row["response_sha256"] for row in attempt_records if
            row["response_sha256"] != "unavailable"
    )
    Set(keys(provided)) == referenced ||
        fail("API attempt bodies", "must contain every and only retained response")
    records = [
        Dict{String, Any}(
                "raw_sha256" => digest,
                "raw_byte_count" => length(provided[digest]),
                "primary_path" =>
                "replica-a/api-attempt-raw-sha256-$digest.bin",
                "replica_path" =>
                "replica-b/api-attempt-raw-sha256-$digest.bin",
            ) for digest in sort!(collect(referenced))
    ]
    return (; records, bodies = provided)
end

function _receipt_document(
        responses;
        transaction_id,
        observer_id,
        api_attempts = nothing,
        api_attempt_bodies = Dict{String, Vector{UInt8}}(),
    )
    isempty(responses) && fail("responses", "must not be empty")
    ids = [response.object_id for response in responses]
    length(ids) == length(unique(ids)) ||
        fail("responses", "object IDs must be unique")
    mode = _capture_mode(responses)
    ordered = sort(
        collect(responses);
        by = response -> (
            response.acquisition_started_at_utc,
            response.object_id,
        ),
    )
    expected = [
        _validate_response_shape(response, index)
            for (index, response) in enumerate(ordered)
    ]
    api_response = only(
        response for response in ordered if
            response.object_id == API_OBJECT_ID
    )
    api_values = ReceiptVerifier._parse_api_values(api_response.body)
    attempt_records = _attempt_records(api_attempts, api_response)
    first_attempt = ReceiptVerifier.expect_timestamp(
        attempt_records[1]["attempted_at_utc"],
        "API attempts[1].attempted_at_utc",
    )
    capture_start = min(
        first_attempt,
        minimum(response.acquisition_started_at_utc for response in ordered),
    )
    capture_end =
        maximum(response.acquisition_completed_at_utc for response in ordered)
    EVENT_START <= capture_start <= capture_end <= EVENT_DEADLINE ||
        fail("responses", "capture is outside the fixed rehearsal window")
    canonical_capture_start = canonical_second(capture_start)
    canonical_capture_end = canonical_second(capture_end)
    span_seconds =
        div(Dates.value(canonical_capture_end - canonical_capture_start), 1000)
    span_seconds <= 900 ||
        fail("responses", "capture exceeds the 15-minute window")

    attempt_objects = _attempt_object_records(
        attempt_records,
        api_response,
        api_attempt_bodies,
    )
    accepted_attempts = [
        row["attempt_number"] for row in attempt_records if row["accepted"]
    ]
    length(accepted_attempts) == 1 ||
        fail("API attempts", "must contain exactly one accepted attempt")
    receipt_stage =
        mode == API_WITH_NEWS_MODE ? "api-plus-news" : "api-only-checkpoint"
    receipt = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-bls-employment-rehearsal-receipt.v1",
            "receipt_id" =>
                "bls-employment-situation-2026-07-rehearsal.$transaction_id.$receipt_stage",
            "scope" =>
                "BLS_2026_07_CAPTURE_REHEARSAL_LOCAL_INTEGRITY_ONLY",
            "canonicalization" =>
                "sorted_typed_v1_excluding_artifact_content_sha256",
            "digest_algorithm" => "sha256",
            "content_sha256" => repeat("0", 64),
        ),
        "contract_binding" => Dict{String, Any}(
            "contract_id" =>
                "beforeit-us-prospective-2026q3-acquisition.v2",
            "contract_file_sha256" =>
                EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256,
            "contract_content_sha256" =>
                "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a",
            "event_id" => "bls_employment_situation_2026_07",
        ),
        "event" => Dict{String, Any}(
            "source_id" => "bls_employment_situation",
            "reference_period" => "2026-07",
            "scheduled_timestamp_utc" => "2026-08-07T12:30:00Z",
            "capture_not_before_utc" => "2026-08-07T12:30:00Z",
            "capture_deadline_utc" => "2026-08-07T12:45:00Z",
            "event_purpose" => "capture_rehearsal",
            "required_for_complete_origin" => false,
        ),
        "capture" => Dict{String, Any}(
            "transaction_id" => transaction_id,
            "observer_id" => observer_id,
            "capture_agent" => CAPTURE_AGENT,
            "capture_agent_version" => CAPTURE_AGENT_VERSION,
            "capture_agent_source_sha256" =>
                ReceiptVerifier.capture_agent_source_sha256(),
            "receipt_verifier_source_sha256" =>
                ReceiptVerifier.receipt_verifier_source_sha256(),
            "source_revision" => current_source_revision(),
            "acquisition_mode" => mode,
            "capture_started_at_utc" => timestamp(capture_start),
            "capture_completed_at_utc" => timestamp(capture_end),
            "maximum_span_seconds" => 900,
            "observed_span_seconds" => span_seconds,
            "clock_basis" => "CAPTURE_HOST_UTC_CLOCK_ONLY",
            "api_attempt_count" => length(attempt_records),
            "accepted_api_attempt_number" => only(accepted_attempts),
        ),
        "attempts" => attempt_records,
        "attempt_objects" => attempt_objects.records,
        "objects" => [
            _object_record(response, expected_row)
                for (response, expected_row) in zip(ordered, expected)
        ],
        "fingerprint" => Dict{String, Any}(
            "reference_period" => "2026-07",
            "release_html_marker" =>
                mode == API_WITH_NEWS_MODE ?
                "Employment Situation Summary - 2026 M07 Results" :
                "NOT_CAPTURED_API_ONLY_FALLBACK",
            "ces_series_id" => "CES0000000001",
            "ces_year" => "2026",
            "ces_period" => "M07",
            "ces_value" => api_values["CES0000000001"],
            "cps_series_id" => "LNS14000000",
            "cps_year" => "2026",
            "cps_period" => "M07",
            "cps_value" => api_values["LNS14000000"],
        ),
        "storage" => Dict{String, Any}(
            "policy" =>
                "TWO_DISTINCT_LOCAL_CONTENT_ADDRESSED_REPLICAS_PLUS_RECEIPT_COPIES",
            "copy_ids" => ["replica-a", "replica-b"],
            "minimum_local_copy_count" => 2,
            "receipt_replica_required" => true,
            "external_durable_storage_attestation_status" =>
                "NOT_VERIFIED",
        ),
        "attestation" => Dict{String, Any}(
            "capture_clock_attestation_status" =>
                "HOST_CLOCK_OBSERVATION_ONLY",
            "source_transport_attestation_status" =>
                "HOST_REPORTED_HTTP_METADATA_ONLY",
            "external_timestamp_attestation_status" => "NOT_VERIFIED",
            "production_prospective_verifier_status" => "NOT_ACTIVATED",
            "cryptographic_signoff_status" => "UNSIGNED",
        ),
        "disposition" => Dict{String, Any}(
            "rehearsal_only" => true,
            "origin_evidence" => false,
            "origin_admissible" => false,
            "ready" => false,
            "inventory_mutation_authorized" => false,
            "accuracy_evaluation_allowed" => false,
        ),
    )
    stamp_receipt_sha256!(receipt)
    return receipt
end

function _toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    bytes = take!(io)
    isempty(bytes) || bytes[end] == UInt8('\n') ||
        push!(bytes, UInt8('\n'))
    return bytes
end

function _write_exact(path, bytes)
    ispath(path) && fail("installation", "refuses to overwrite $path")
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, bytes)
        flush(io)
    end
    read(path) == bytes ||
        fail("installation", "written bytes failed read-back at $path")
    return path
end

function _journal_document(
        api_attempts;
        api_attempt_bodies,
        transaction_id,
        observer_id,
        recorded_at,
        state,
        failure_reason,
    )
    recorded_at isa DateTime ||
        fail("attempt journal", "recorded_at must be a DateTime")
    attempt_records =
        isempty(api_attempts) ? Dict{String, Any}[] :
        _attempt_records(api_attempts, nothing)
    attempt_objects =
        _journal_attempt_object_records(attempt_records, api_attempt_bodies)
    terminal = state in ("BUNDLE_INSTALLED", "FAILED")
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => JOURNAL_SCHEMA,
            "journal_id" =>
                "bls-employment-situation-2026-07-attempt-journal.$transaction_id." *
                "attempt-$(length(attempt_records)).$(String(state))." *
                timestamp(recorded_at),
            "scope" => JOURNAL_SCOPE,
            "canonicalization" =>
                "sorted_typed_v1_excluding_artifact_content_sha256",
            "digest_algorithm" => "sha256",
            "content_sha256" => repeat("0", 64),
        ),
        "contract_binding" => Dict{String, Any}(
            "contract_id" =>
                "beforeit-us-prospective-2026q3-acquisition.v2",
            "contract_file_sha256" =>
                EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256,
            "contract_content_sha256" =>
                "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a",
            "event_id" => "bls_employment_situation_2026_07",
        ),
        "event" => Dict{String, Any}(
            "source_id" => "bls_employment_situation",
            "reference_period" => "2026-07",
            "scheduled_timestamp_utc" => "2026-08-07T12:30:00Z",
            "capture_not_before_utc" => "2026-08-07T12:30:00Z",
            "capture_deadline_utc" => "2026-08-07T12:45:00Z",
            "event_purpose" => "capture_rehearsal",
            "required_for_complete_origin" => false,
        ),
        "journal" => Dict{String, Any}(
            "transaction_id" => String(transaction_id),
            "observer_id" => String(observer_id),
            "capture_agent" => CAPTURE_AGENT,
            "capture_agent_version" => CAPTURE_AGENT_VERSION,
            "capture_agent_source_sha256" =>
                ReceiptVerifier.capture_agent_source_sha256(),
            "receipt_verifier_source_sha256" =>
                ReceiptVerifier.receipt_verifier_source_sha256(),
            "source_revision" => current_source_revision(),
            "recorded_at_utc" => timestamp(recorded_at),
            "clock_basis" => "CAPTURE_HOST_UTC_CLOCK_ONLY",
            "api_attempt_count" => length(attempt_records),
            "state" => String(state),
            "terminal" => terminal,
            "failure_reason" => String(failure_reason),
        ),
        "attempts" => attempt_records,
        "attempt_objects" => attempt_objects.records,
        "storage" => Dict{String, Any}(
            "policy" => "TWO_DISTINCT_LOCAL_CONTENT_ADDRESSED_JOURNAL_COPIES",
            "copy_ids" => ["replica-a", "replica-b"],
            "minimum_local_copy_count" => 2,
            "external_durable_storage_attestation_status" =>
                "NOT_VERIFIED",
        ),
        "attestation" => Dict{String, Any}(
            "capture_clock_attestation_status" =>
                "HOST_CLOCK_OBSERVATION_ONLY",
            "source_transport_attestation_status" =>
                "HOST_REPORTED_HTTP_METADATA_ONLY",
            "external_timestamp_attestation_status" => "NOT_VERIFIED",
            "cryptographic_signoff_status" => "UNSIGNED",
        ),
        "disposition" => Dict{String, Any}(
            "rehearsal_only" => true,
            "diagnostics_only" => true,
            "origin_evidence" => false,
            "origin_admissible" => false,
            "ready" => false,
            "inventory_mutation_authorized" => false,
            "accuracy_evaluation_allowed" => false,
        ),
    )
    stamp_receipt_sha256!(document)
    return document
end

function _validate_journal_state(
        state,
        terminal,
        failure_reason,
        attempts,
        accepted_numbers,
    )
    state in JOURNAL_STATES ||
        fail("attempt journal.journal.state", "unsupported state")
    if state == "POLLING"
        !terminal ||
            fail("attempt journal.journal.terminal", "polling is nonterminal")
        failure_reason == "NOT_APPLICABLE" ||
            fail("attempt journal.journal.failure_reason", "must not claim failure")
        !isempty(attempts) ||
            fail("attempt journal.attempts", "polling requires an attempt")
        isempty(accepted_numbers) ||
            fail("attempt journal.attempts", "polling cannot contain acceptance")
    elseif state == "ACCEPTED_M07_PENDING_BUNDLE"
        !terminal ||
            fail("attempt journal.journal.terminal", "pending state is nonterminal")
        failure_reason == "NOT_APPLICABLE" ||
            fail("attempt journal.journal.failure_reason", "must not claim failure")
        accepted_numbers == [length(attempts)] ||
            fail("attempt journal.attempts", "final attempt must be accepted")
    elseif state == "BUNDLE_INSTALLED"
        terminal ||
            fail("attempt journal.journal.terminal", "installed state is terminal")
        failure_reason == "NOT_APPLICABLE" ||
            fail("attempt journal.journal.failure_reason", "must not claim failure")
        accepted_numbers == [length(attempts)] ||
            fail("attempt journal.attempts", "final attempt must be accepted")
    else
        terminal ||
            fail("attempt journal.journal.terminal", "failed state is terminal")
        failure_reason in JOURNAL_FAILURE_REASONS ||
            fail("attempt journal.journal.failure_reason", "unsupported reason")
        if failure_reason == "BUNDLE_INSTALLATION_FAILED"
            accepted_numbers == [length(attempts)] ||
                fail(
                "attempt journal.attempts",
                "bundle failure requires a final accepted attempt",
            )
        else
            isempty(accepted_numbers) ||
                fail(
                "attempt journal.attempts",
                "pre-acceptance failure cannot claim acceptance",
            )
        end
    end
    return nothing
end

function _validate_journal_document(document, bundle_directory, contract_path)
    root = ReceiptVerifier.expect_exact_keys(
        document,
        JOURNAL_ROOT_KEYS,
        "attempt journal",
    )
    artifact = ReceiptVerifier.expect_exact_keys(
        root["artifact"],
        JOURNAL_ARTIFACT_KEYS,
        "attempt journal.artifact",
    )
    artifact["schema_version"] == JOURNAL_SCHEMA ||
        fail("attempt journal.artifact.schema_version", "schema mismatch")
    journal_id = ReceiptVerifier.expect_identifier(
        artifact["journal_id"],
        "attempt journal.artifact.journal_id",
    )
    artifact["scope"] == JOURNAL_SCOPE ||
        fail("attempt journal.artifact.scope", "scope mismatch")
    artifact["canonicalization"] ==
        "sorted_typed_v1_excluding_artifact_content_sha256" ||
        fail("attempt journal.artifact.canonicalization", "method mismatch")
    artifact["digest_algorithm"] == "sha256" ||
        fail("attempt journal.artifact.digest_algorithm", "must be sha256")
    content_sha256 = ReceiptVerifier.expect_hash(
        artifact["content_sha256"],
        "attempt journal.artifact.content_sha256",
    )
    content_sha256 == computed_receipt_sha256(root) ||
        fail("attempt journal.artifact.content_sha256", "content digest mismatch")

    contract = ReceiptVerifier._validate_contract(contract_path)
    binding = ReceiptVerifier.expect_exact_keys(
        root["contract_binding"],
        ReceiptVerifier.CONTRACT_BINDING_KEYS,
        "attempt journal.contract_binding",
    )
    binding == Dict(
        "contract_id" =>
            "beforeit-us-prospective-2026q3-acquisition.v2",
        "contract_file_sha256" => contract.digest,
        "contract_content_sha256" =>
            "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a",
        "event_id" => "bls_employment_situation_2026_07",
    ) || fail("attempt journal.contract_binding", "contract binding mismatch")
    event = ReceiptVerifier.expect_exact_keys(
        root["event"],
        ReceiptVerifier.EVENT_KEYS,
        "attempt journal.event",
    )
    event == Dict(
        "source_id" => "bls_employment_situation",
        "reference_period" => "2026-07",
        "scheduled_timestamp_utc" => "2026-08-07T12:30:00Z",
        "capture_not_before_utc" => "2026-08-07T12:30:00Z",
        "capture_deadline_utc" => "2026-08-07T12:45:00Z",
        "event_purpose" => "capture_rehearsal",
        "required_for_complete_origin" => false,
    ) || fail("attempt journal.event", "fixed event mismatch")

    journal = ReceiptVerifier.expect_exact_keys(
        root["journal"],
        JOURNAL_KEYS,
        "attempt journal.journal",
    )
    transaction_id = ReceiptVerifier.expect_identifier(
        journal["transaction_id"],
        "attempt journal.journal.transaction_id",
    )
    ReceiptVerifier.expect_identifier(
        journal["observer_id"],
        "attempt journal.journal.observer_id",
    )
    journal["capture_agent"] == CAPTURE_AGENT ||
        fail("attempt journal.journal.capture_agent", "agent mismatch")
    journal["capture_agent_version"] == CAPTURE_AGENT_VERSION ||
        fail("attempt journal.journal.capture_agent_version", "version mismatch")
    journal["capture_agent_source_sha256"] ==
        ReceiptVerifier.capture_agent_source_sha256() ||
        fail(
        "attempt journal.journal.capture_agent_source_sha256",
        "collector source mismatch",
    )
    journal["receipt_verifier_source_sha256"] ==
        ReceiptVerifier.receipt_verifier_source_sha256() ||
        fail(
        "attempt journal.journal.receipt_verifier_source_sha256",
        "verifier source mismatch",
    )
    source_revision = ReceiptVerifier.expect_source_revision(
        journal["source_revision"],
        "attempt journal.journal.source_revision",
    )
    journal["clock_basis"] == "CAPTURE_HOST_UTC_CLOCK_ONLY" ||
        fail("attempt journal.journal.clock_basis", "clock basis mismatch")
    recorded_at = ReceiptVerifier.expect_timestamp(
        journal["recorded_at_utc"],
        "attempt journal.journal.recorded_at_utc",
    )
    attempt_count = ReceiptVerifier.expect_int(
        journal["api_attempt_count"],
        "attempt journal.journal.api_attempt_count";
        minimum = 0,
    )
    attempts = root["attempts"]
    accepted_numbers = ReceiptVerifier._validate_attempt_rows(
        attempts;
        ledger_location = "attempt journal.attempts",
        allow_empty = true,
    )
    length(attempts) == attempt_count ||
        fail("attempt journal.journal.api_attempt_count", "ledger mismatch")
    attempt_objects = ReceiptVerifier._validate_attempt_objects(
        root["attempt_objects"],
        attempts,
        nothing,
        bundle_directory,
    )
    if !isempty(attempts)
        last_attempt = ReceiptVerifier.expect_timestamp(
            attempts[end]["attempted_at_utc"],
            "attempt journal.attempts[$attempt_count].attempted_at_utc",
        )
        last_attempt <= recorded_at ||
            fail("attempt journal.journal.recorded_at_utc", "precedes last attempt")
    end
    state = ReceiptVerifier.expect_string(
        journal["state"],
        "attempt journal.journal.state",
    )
    terminal = ReceiptVerifier.expect_bool(
        journal["terminal"],
        "attempt journal.journal.terminal",
    )
    failure_reason = ReceiptVerifier.expect_string(
        journal["failure_reason"],
        "attempt journal.journal.failure_reason",
    )
    journal_id ==
        "bls-employment-situation-2026-07-attempt-journal.$transaction_id." *
        "attempt-$attempt_count.$state.$(journal["recorded_at_utc"])" ||
        fail(
        "attempt journal.artifact.journal_id",
        "transaction and snapshot binding mismatch",
    )
    _validate_journal_state(
        state,
        terminal,
        failure_reason,
        attempts,
        accepted_numbers,
    )

    storage = ReceiptVerifier.expect_exact_keys(
        root["storage"],
        JOURNAL_STORAGE_KEYS,
        "attempt journal.storage",
    )
    storage == Dict(
        "policy" => "TWO_DISTINCT_LOCAL_CONTENT_ADDRESSED_JOURNAL_COPIES",
        "copy_ids" => ["replica-a", "replica-b"],
        "minimum_local_copy_count" => 2,
        "external_durable_storage_attestation_status" => "NOT_VERIFIED",
    ) || fail("attempt journal.storage", "storage claim mismatch")
    attestation = ReceiptVerifier.expect_exact_keys(
        root["attestation"],
        JOURNAL_ATTESTATION_KEYS,
        "attempt journal.attestation",
    )
    attestation == Dict(
        "capture_clock_attestation_status" =>
            "HOST_CLOCK_OBSERVATION_ONLY",
        "source_transport_attestation_status" =>
            "HOST_REPORTED_HTTP_METADATA_ONLY",
        "external_timestamp_attestation_status" => "NOT_VERIFIED",
        "cryptographic_signoff_status" => "UNSIGNED",
    ) || fail("attempt journal.attestation", "attestation mismatch")
    disposition = ReceiptVerifier.expect_exact_keys(
        root["disposition"],
        JOURNAL_DISPOSITION_KEYS,
        "attempt journal.disposition",
    )
    disposition == Dict(
        "rehearsal_only" => true,
        "diagnostics_only" => true,
        "origin_evidence" => false,
        "origin_admissible" => false,
        "ready" => false,
        "inventory_mutation_authorized" => false,
        "accuracy_evaluation_allowed" => false,
    ) || fail("attempt journal.disposition", "must remain nonadmitting")
    return (;
        content_sha256,
        state,
        terminal,
        failure_reason,
        attempt_count,
        attempt_object_count = attempt_objects.count,
        accepted_attempt_number =
            isempty(accepted_numbers) ? nothing : only(accepted_numbers),
        source_revision,
    )
end

function validate_rehearsal_attempt_journal_file(
        path;
        contract_path = DEFAULT_PROSPECTIVE_CONTRACT_PATH,
    )
    journal_path = abspath(String(path))
    isfile(journal_path) ||
        fail("attempt journal file", "file does not exist")
    islink(journal_path) &&
        fail("attempt journal file", "must not be a symbolic link")
    bundle_directory = dirname(journal_path)
    islink(bundle_directory) &&
        fail("attempt journal bundle", "must not be a symbolic link")
    bytes = read(journal_path)
    isempty(bytes) &&
        fail("attempt journal file", "must not be empty")
    document =
        ReceiptVerifier._parse_toml_bytes(bytes, "attempt journal file")
    result =
        _validate_journal_document(document, bundle_directory, contract_path)
    name = "journal-content-sha256-$(result.content_sha256).toml"
    basename(journal_path) == name ||
        fail("attempt journal file", "must be content addressed as $name")
    replica_paths = String[]
    for copy_id in ("replica-a", "replica-b")
        relative_path = "$copy_id/$name"
        replica_bytes = ReceiptVerifier._resolve_regular_bytes(
            bundle_directory,
            relative_path,
            "attempt journal replica $copy_id",
        )
        replica_bytes == bytes ||
            fail("attempt journal replica", "bytes do not match")
        push!(replica_paths, realpath(joinpath(bundle_directory, relative_path)))
    end
    ReceiptVerifier._assert_distinct_file_identities(
        [realpath(journal_path), realpath.(replica_paths)...],
        "attempt journal replicas",
    )
    return (;
        status = "LOCAL_REHEARSAL_ATTEMPT_JOURNAL_VERIFIED_NONADMITTING",
        result...,
        local_copy_count = 2,
        external_timestamp_verified = false,
        durable_storage_verified = false,
        origin_evidence = false,
        origin_admissible = false,
        ready = false,
        inventory_mutation_authorized = false,
        accuracy_evaluation_allowed = false,
    )
end

function install_rehearsal_attempt_journal(
        output_root,
        api_attempts;
        transaction_id,
        observer_id = "beforeit-us-forecasting",
        recorded_at,
        state,
        failure_reason = "NOT_APPLICABLE",
        api_attempt_bodies = Dict{String, Vector{UInt8}}(),
        contract_path = DEFAULT_PROSPECTIVE_CONTRACT_PATH,
    )
    root = abspath(String(output_root))
    mkpath(root)
    islink(root) &&
        fail("attempt journal output root", "must not be a symbolic link")
    document = _journal_document(
        api_attempts;
        api_attempt_bodies,
        transaction_id = String(transaction_id),
        observer_id = String(observer_id),
        recorded_at,
        state = String(state),
        failure_reason = String(failure_reason),
    )
    content_sha256 = document["artifact"]["content_sha256"]
    name = "journal-content-sha256-$content_sha256.toml"
    bytes = _toml_bytes(document)
    journals_root = joinpath(root, "attempt-journals")
    mkpath(journals_root)
    islink(journals_root) &&
        fail("attempt journal output", "must not be a symbolic link")
    final_path = joinpath(journals_root, "sha256-$content_sha256")
    if ispath(final_path)
        isdir(final_path) ||
            fail("attempt journal installation", "content address is not a directory")
        validation = validate_rehearsal_attempt_journal_file(
            joinpath(final_path, name);
            contract_path,
        )
        return (;
            bundle_path = final_path,
            journal_path = joinpath(final_path, name),
            installed = false,
            validation,
        )
    end

    staging_path = mktempdir(journals_root; prefix = ".staging-")
    published = false
    try
        journal_path =
            _write_exact(joinpath(staging_path, name), bytes)
        for object in document["attempt_objects"]
            body = api_attempt_bodies[object["raw_sha256"]]
            _write_exact(joinpath(staging_path, object["primary_path"]), body)
            _write_exact(joinpath(staging_path, object["replica_path"]), body)
        end
        for copy_id in ("replica-a", "replica-b")
            _write_exact(joinpath(staging_path, copy_id, name), bytes)
        end
        validation = validate_rehearsal_attempt_journal_file(
            journal_path;
            contract_path,
        )
        mv(staging_path, final_path)
        published = true
        return (;
            bundle_path = final_path,
            journal_path = joinpath(final_path, name),
            installed = true,
            validation,
        )
    finally
        !published && isdir(staging_path) &&
            rm(staging_path; recursive = true)
    end
end

"""
    install_rehearsal_capture(output_root, responses; ...)

Install an already captured API-only or API-plus-news rehearsal transaction as
two local content-addressed object replicas and two byte-identical receipt
copies, then rerun the independent local verifier before publishing the bundle
directory. Local replication is not an external durability or timestamp
attestation and cannot admit an origin.
"""
function install_rehearsal_capture(
        output_root,
        responses;
        transaction_id,
        observer_id = "beforeit-us-forecasting",
        contract_path = DEFAULT_PROSPECTIVE_CONTRACT_PATH,
        api_attempts = nothing,
        api_attempt_bodies = Dict{String, Vector{UInt8}}(),
    )
    root = abspath(String(output_root))
    mkpath(root)
    islink(root) && fail("output root", "must not be a symbolic link")
    receipt = _receipt_document(
        responses;
        transaction_id = String(transaction_id),
        observer_id = String(observer_id),
        api_attempts,
        api_attempt_bodies,
    )
    content_sha256 = receipt["artifact"]["content_sha256"]
    receipt_name =
        "receipt-content-sha256-$content_sha256.toml"
    receipt_bytes = _toml_bytes(receipt)
    final_path = joinpath(root, "sha256-$content_sha256")
    if ispath(final_path)
        isdir(final_path) ||
            fail("installation", "existing content address is not a directory")
        validation = validate_rehearsal_receipt_file(
            joinpath(final_path, receipt_name);
            contract_path,
        )
        return (;
            bundle_path = final_path,
            receipt_path = joinpath(final_path, receipt_name),
            installed = false,
            validation,
        )
    end

    staging_path = mktempdir(root; prefix = ".staging-")
    published = false
    try
        attempt_body_lookup = Dict(
            String(digest) => Vector{UInt8}(bytes)
                for (digest, bytes) in pairs(api_attempt_bodies)
        )
        response_lookup =
            Dict(response.object_id => response for response in responses)
        for object in receipt["objects"]
            body = response_lookup[object["object_id"]].body
            _write_exact(joinpath(staging_path, object["primary_path"]), body)
            _write_exact(joinpath(staging_path, object["replica_path"]), body)
        end
        for object in receipt["attempt_objects"]
            body = attempt_body_lookup[object["raw_sha256"]]
            _write_exact(joinpath(staging_path, object["primary_path"]), body)
            _write_exact(joinpath(staging_path, object["replica_path"]), body)
        end
        receipt_path =
            _write_exact(joinpath(staging_path, receipt_name), receipt_bytes)
        for copy_id in ("replica-a", "replica-b")
            _write_exact(
                joinpath(staging_path, copy_id, receipt_name),
                receipt_bytes,
            )
        end
        validation = validate_rehearsal_receipt_file(
            receipt_path;
            contract_path,
        )
        mv(staging_path, final_path)
        published = true
        return (;
            bundle_path = final_path,
            receipt_path = joinpath(final_path, receipt_name),
            installed = true,
            validation,
        )
    finally
        !published && isdir(staging_path) &&
            rm(staging_path; recursive = true)
    end
end

function _normalized_headers(response; require_required = true)
    collected = Dict{String, String}()
    for (name, value) in response.headers
        key = lowercase(strip(String(name)))
        key in ReceiptVerifier.RESPONSE_HEADER_ALLOWLIST ||
            continue
        text = strip(String(value))
        if haskey(collected, key)
            collected[key] *= ", " * text
        else
            collected[key] = text
        end
    end
    if require_required
        for required in ("content-type", "date")
            haskey(collected, required) ||
                fail("live response headers", "missing $required")
        end
    end
    return sort!(["$name: $value" for (name, value) in collected])
end

function _sanitized_captured_response(response::CapturedResponse)
    retained = String[]
    for header in response.response_headers
        text = String(header)
        (occursin('\r', text) || occursin('\n', text)) && continue
        pieces = split(text, ':'; limit = 2)
        length(pieces) == 2 || continue
        name = lowercase(strip(pieces[1]))
        name in ReceiptVerifier.RESPONSE_HEADER_ALLOWLIST || continue
        push!(retained, "$name: $(strip(pieces[2]))")
    end
    return CapturedResponse(
        object_id = response.object_id,
        body = copy(response.body),
        requested_url = response.requested_url,
        effective_url = response.effective_url,
        status_code = response.status_code,
        content_type = response.content_type,
        response_headers = sort!(retained),
        acquisition_started_at_utc = response.acquisition_started_at_utc,
        response_metadata_observed_at_utc =
            response.response_metadata_observed_at_utc,
        acquisition_completed_at_utc = response.acquisition_completed_at_utc,
    )
end

function _classify_news_response(response, expected_object_id)
    expected = _expected_object(expected_object_id)
    response.object_id == expected_object_id ||
        return (
        outcome = "REJECTED_OBJECT_ID",
        detail = "FETCH_REPORTED_WRONG_OBJECT_ID",
    )
    response.requested_url == expected.requested_url ||
        return (
        outcome = "REJECTED_OFFICIAL_ROUTE",
        detail = "REQUESTED_URL_MISMATCH",
    )
    response.effective_url == expected.requested_url ||
        return (
        outcome = "REJECTED_REDIRECT",
        detail = "EFFECTIVE_URL_MISMATCH",
    )
    response.status_code == 200 ||
        return (
        outcome = "HTTP_NON_200",
        detail = "HTTP_$(response.status_code)",
    )
    ReceiptVerifier._media_type_token(response.content_type) ==
        expected.media_type ||
        return (
        outcome = "REJECTED_MEDIA_TYPE",
        detail = "CONTENT_TYPE_MISMATCH",
    )
    parsed_headers = try
        ReceiptVerifier.validate_response_headers(
            response.response_headers,
            response.content_type,
            "news response headers",
        )
    catch error
        error isa ReceiptVerifier.RehearsalReceiptError || rethrow()
        return (
            outcome = "REJECTED_RESPONSE_HEADERS",
            detail = "SANITIZED_HEADER_CONTRACT_FAILED",
        )
    end
    if !(
            EVENT_START <=
                response.acquisition_started_at_utc <=
                response.response_metadata_observed_at_utc <=
                response.acquisition_completed_at_utc <=
                EVENT_DEADLINE
        )
        return (
            outcome = "REJECTED_TIMING",
            detail = "CAPTURE_WINDOW_OR_ORDER_FAILED",
        )
    end
    server_date = DateTime(
        chop(parsed_headers["__parsed_server_date"]; tail = 1),
        TIMESTAMP_FORMAT,
    )
    if !(
            response.acquisition_started_at_utc - Minute(5) <=
                server_date <=
                response.acquisition_completed_at_utc + Minute(5)
        )
        return (
            outcome = "REJECTED_TIMING",
            detail = "SERVER_DATE_INCONSISTENT_WITH_HOST",
        )
    end
    if expected_object_id == HTML_OBJECT_ID
        valid = try
            html = String(copy(response.body))
            normalized = ReceiptVerifier._normalized_html_text(response.body)
            occursin(
                "Employment Situation Summary - 2026 M07 Results",
                html,
            ) &&
                occursin(
                "THE EMPLOYMENT SITUATION - JULY 2026",
                normalized,
            ) &&
                occursin("EMBARGOED UNTIL", normalized) &&
                occursin("AUGUST 7, 2026", normalized) &&
                occursin("TOTAL NONFARM", normalized) &&
                occursin("UNEMPLOYMENT RATE", normalized)
        catch error
            error isa ReceiptVerifier.RehearsalReceiptError || rethrow()
            false
        end
        valid ||
            return (
            outcome = "REJECTED_RELEASE_IDENTITY",
            detail = "JULY_2026_RELEASE_MARKERS_FAILED",
        )
    else
        length(response.body) >= 5 &&
            response.body[1:5] == Vector{UInt8}(codeunits("%PDF-")) ||
            return (
            outcome = "REJECTED_PDF_SIGNATURE",
            detail = "OPAQUE_PDF_SIGNATURE_FAILED",
        )
    end
    return (
        outcome = "VALIDATED",
        detail = "CANONICAL_NEWS_OBJECT_VALIDATED",
    )
end

function _news_response_attempt(response, expected_object_id)
    classification = _classify_news_response(response, expected_object_id)
    digest = sha256_hex(response.body)
    name =
        "news-attempt-$expected_object_id-raw-sha256-$digest.bin"
    return Dict{String, Any}(
        "object_id" => expected_object_id,
        "reported_object_id" => response.object_id,
        "requested_url" => response.requested_url,
        "effective_url" => response.effective_url,
        "attempted_at_utc" =>
            timestamp(response.acquisition_started_at_utc),
        "response_metadata_observed_at_utc" =>
            timestamp(response.response_metadata_observed_at_utc),
        "acquisition_completed_at_utc" =>
            timestamp(response.acquisition_completed_at_utc),
        "status_code" => response.status_code,
        "content_type" => response.content_type,
        "response_headers" => response.response_headers,
        "raw_sha256" => digest,
        "raw_byte_count" => length(response.body),
        "primary_path" => "replica-a/$name",
        "replica_path" => "replica-b/$name",
        "outcome" => classification.outcome,
        "detail" => classification.detail,
    )
end

function _news_unavailable_attempt(object_id, attempted_at, outcome)
    outcome in ("REQUEST_FAILED", "FETCH_CONTRACT_VIOLATION") ||
        fail("news diagnostic", "unsupported unavailable outcome")
    return Dict{String, Any}(
        "object_id" => object_id,
        "reported_object_id" => "UNAVAILABLE",
        "requested_url" => _expected_object(object_id).requested_url,
        "effective_url" => "UNAVAILABLE",
        "attempted_at_utc" => timestamp(attempted_at),
        "response_metadata_observed_at_utc" => timestamp(attempted_at),
        "acquisition_completed_at_utc" => timestamp(attempted_at),
        "status_code" => 0,
        "content_type" => "UNAVAILABLE",
        "response_headers" => String[],
        "raw_sha256" => "unavailable",
        "raw_byte_count" => 0,
        "primary_path" => "NOT_APPLICABLE",
        "replica_path" => "NOT_APPLICABLE",
        "outcome" => outcome,
        "detail" =>
            outcome == "REQUEST_FAILED" ?
            "REQUEST_EXCEPTION" : "FETCH_RETURN_TYPE_MISMATCH",
    )
end

function _finalize_news_attempts!(attempts)
    validated = [row["outcome"] == "VALIDATED" for row in attempts]
    if all(validated)
        for row in attempts
            row["outcome"] = "VALIDATED_COMPLETE_NEWS_SET"
            row["detail"] = "BOTH_NEWS_OBJECTS_LOCALLY_VALIDATED"
        end
    else
        for (row, is_valid) in zip(attempts, validated)
            is_valid || continue
            row["outcome"] = "VALIDATED_NOT_INSTALLED_INCOMPLETE_SET"
            row["detail"] = "PEER_NEWS_OBJECT_REJECTED_OR_UNAVAILABLE"
        end
    end
    return attempts
end

function _news_diagnostic_document(
        attempts;
        transaction_id,
        observer_id,
        recorded_at,
    )
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => NEWS_DIAGNOSTIC_SCHEMA,
            "diagnostic_id" =>
                "bls-employment-situation-2026-07-news-diagnostic.$transaction_id",
            "scope" => NEWS_DIAGNOSTIC_SCOPE,
            "canonicalization" =>
                "sorted_typed_v1_excluding_artifact_content_sha256",
            "digest_algorithm" => "sha256",
            "content_sha256" => repeat("0", 64),
        ),
        "contract_binding" => Dict{String, Any}(
            "contract_id" =>
                "beforeit-us-prospective-2026q3-acquisition.v2",
            "contract_file_sha256" =>
                EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256,
            "contract_content_sha256" =>
                "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a",
            "event_id" => "bls_employment_situation_2026_07",
        ),
        "event" => Dict{String, Any}(
            "source_id" => "bls_employment_situation",
            "reference_period" => "2026-07",
            "scheduled_timestamp_utc" => "2026-08-07T12:30:00Z",
            "capture_not_before_utc" => "2026-08-07T12:30:00Z",
            "capture_deadline_utc" => "2026-08-07T12:45:00Z",
            "event_purpose" => "capture_rehearsal",
            "required_for_complete_origin" => false,
        ),
        "diagnostic" => Dict{String, Any}(
            "transaction_id" => String(transaction_id),
            "observer_id" => String(observer_id),
            "capture_agent" => CAPTURE_AGENT,
            "capture_agent_version" => CAPTURE_AGENT_VERSION,
            "capture_agent_source_sha256" =>
                ReceiptVerifier.capture_agent_source_sha256(),
            "receipt_verifier_source_sha256" =>
                ReceiptVerifier.receipt_verifier_source_sha256(),
            "source_revision" => current_source_revision(),
            "recorded_at_utc" => timestamp(recorded_at),
            "clock_basis" => "CAPTURE_HOST_UTC_CLOCK_ONLY",
            "transport_policy" => LIVE_TRANSPORT_POLICY,
            "api_checkpoint_binding_status" =>
                "UNBOUND_CALLER_REPORTED_TRANSACTION_ID_ONLY",
            "attempt_count" => length(attempts),
        ),
        "attempts" => attempts,
        "storage" => Dict{String, Any}(
            "policy" =>
                "TWO_DISTINCT_LOCAL_CONTENT_ADDRESSED_NEWS_DIAGNOSTIC_COPIES",
            "copy_ids" => ["replica-a", "replica-b"],
            "minimum_local_copy_count" => 2,
            "diagnostic_replica_required" => true,
            "external_durable_storage_attestation_status" => "NOT_VERIFIED",
        ),
        "attestation" => Dict{String, Any}(
            "capture_clock_attestation_status" =>
                "HOST_CLOCK_OBSERVATION_ONLY",
            "source_transport_attestation_status" =>
                "HOST_REPORTED_HTTP_METADATA_ONLY",
            "external_timestamp_attestation_status" => "NOT_VERIFIED",
            "cryptographic_signoff_status" => "UNSIGNED",
        ),
        "disposition" => Dict{String, Any}(
            "rehearsal_only" => true,
            "diagnostics_only" => true,
            "origin_evidence" => false,
            "origin_admissible" => false,
            "ready" => false,
            "inventory_mutation_authorized" => false,
            "accuracy_evaluation_allowed" => false,
        ),
    )
    stamp_receipt_sha256!(document)
    return document
end

function _validate_news_attempt(row, index, bundle_directory)
    location = "news diagnostic.attempts[$index]"
    item = ReceiptVerifier.expect_exact_keys(row, NEWS_ATTEMPT_KEYS, location)
    expected_object_id = index == 1 ? HTML_OBJECT_ID : PDF_OBJECT_ID
    item["object_id"] == expected_object_id ||
        fail("$location.object_id", "news attempt order or object mismatch")
    attempted_at = ReceiptVerifier.expect_timestamp(
        item["attempted_at_utc"],
        "$location.attempted_at_utc",
    )
    metadata_at = ReceiptVerifier.expect_timestamp(
        item["response_metadata_observed_at_utc"],
        "$location.response_metadata_observed_at_utc",
    )
    completed_at = ReceiptVerifier.expect_timestamp(
        item["acquisition_completed_at_utc"],
        "$location.acquisition_completed_at_utc",
    )
    EVENT_START <= attempted_at <= metadata_at <= completed_at <=
        EVENT_DEADLINE + Minute(2) ||
        fail(location, "diagnostic timestamps are outside the bounded run")
    status_code = ReceiptVerifier.expect_int(
        item["status_code"],
        "$location.status_code";
        minimum = 0,
    )
    status_code == 0 || 100 <= status_code <= 599 ||
        fail("$location.status_code", "must be zero or an HTTP status")
    outcome =
        ReceiptVerifier.expect_string(item["outcome"], "$location.outcome")
    detail = ReceiptVerifier.expect_string(item["detail"], "$location.detail")
    raw_sha256 =
        ReceiptVerifier.expect_string(item["raw_sha256"], "$location.raw_sha256")
    if outcome in ("REQUEST_FAILED", "FETCH_CONTRACT_VIOLATION")
        status_code == 0 ||
            fail("$location.status_code", "unavailable attempt must use zero")
        raw_sha256 == "unavailable" ||
            fail("$location.raw_sha256", "unavailable attempt cannot claim bytes")
        item["reported_object_id"] == "UNAVAILABLE" ||
            fail("$location.reported_object_id", "must be unavailable")
        item["requested_url"] ==
            _expected_object(expected_object_id).requested_url ||
            fail("$location.requested_url", "official locator mismatch")
        item["effective_url"] == "UNAVAILABLE" ||
            fail("$location.effective_url", "must be unavailable")
        item["content_type"] == "UNAVAILABLE" ||
            fail("$location.content_type", "must be unavailable")
        ReceiptVerifier.expect_string_array(
            item["response_headers"],
            "$location.response_headers",
        ) == String[] ||
            fail("$location.response_headers", "must be empty")
        ReceiptVerifier.expect_int(
            item["raw_byte_count"],
            "$location.raw_byte_count";
            minimum = 0,
        ) == 0 ||
            fail("$location.raw_byte_count", "must be zero")
        item["primary_path"] == "NOT_APPLICABLE" ||
            fail("$location.primary_path", "must not claim bytes")
        item["replica_path"] == "NOT_APPLICABLE" ||
            fail("$location.replica_path", "must not claim bytes")
        attempted_at == metadata_at == completed_at ||
            fail(location, "unavailable attempt timestamps must be identical")
        expected_detail =
            outcome == "REQUEST_FAILED" ?
            "REQUEST_EXCEPTION" : "FETCH_RETURN_TYPE_MISMATCH"
        detail == expected_detail ||
            fail("$location.detail", "unavailable-attempt detail mismatch")
        return (; outcome, completed_at, raw_paths = String[])
    end

    digest = ReceiptVerifier.expect_hash(raw_sha256, "$location.raw_sha256")
    byte_count = ReceiptVerifier.expect_int(
        item["raw_byte_count"],
        "$location.raw_byte_count";
        minimum = 0,
    )
    primary_path = ReceiptVerifier._validate_relative_path(
        item["primary_path"],
        "$location.primary_path",
    )
    replica_path = ReceiptVerifier._validate_relative_path(
        item["replica_path"],
        "$location.replica_path",
    )
    expected_name =
        "news-attempt-$expected_object_id-raw-sha256-$digest.bin"
    primary_path == "replica-a/$expected_name" ||
        fail("$location.primary_path", "content-addressed path mismatch")
    replica_path == "replica-b/$expected_name" ||
        fail("$location.replica_path", "content-addressed path mismatch")
    primary_bytes = ReceiptVerifier._resolve_regular_bytes(
        bundle_directory,
        primary_path,
        "$location.primary_path",
    )
    replica_bytes = ReceiptVerifier._resolve_regular_bytes(
        bundle_directory,
        replica_path,
        "$location.replica_path",
    )
    primary_bytes == replica_bytes ||
        fail(location, "raw news replicas do not match")
    length(primary_bytes) == byte_count ||
        fail("$location.raw_byte_count", "does not match retained bytes")
    sha256_hex(primary_bytes) == digest ||
        fail("$location.raw_sha256", "does not match retained bytes")
    raw_paths = [
        realpath(joinpath(bundle_directory, primary_path)),
        realpath(joinpath(bundle_directory, replica_path)),
    ]
    ReceiptVerifier._assert_distinct_file_identities(raw_paths, location)
    response = CapturedResponse(
        object_id = String(item["reported_object_id"]),
        body = primary_bytes,
        requested_url = String(item["requested_url"]),
        effective_url = String(item["effective_url"]),
        status_code = status_code,
        content_type = String(item["content_type"]),
        response_headers = ReceiptVerifier.expect_string_array(
            item["response_headers"],
            "$location.response_headers",
        ),
        acquisition_started_at_utc = attempted_at,
        response_metadata_observed_at_utc = metadata_at,
        acquisition_completed_at_utc = completed_at,
    )
    classification = _classify_news_response(response, expected_object_id)
    if outcome in NEWS_VALID_FINAL_OUTCOMES
        classification.outcome == "VALIDATED" ||
            fail("$location.outcome", "final claim does not match retained bytes")
        expected_detail = Dict(
            "VALIDATED_COMPLETE_NEWS_SET" =>
                "BOTH_NEWS_OBJECTS_LOCALLY_VALIDATED",
            "VALIDATED_NOT_INSTALLED_INCOMPLETE_SET" =>
                "PEER_NEWS_OBJECT_REJECTED_OR_UNAVAILABLE",
        )[outcome]
        detail == expected_detail ||
            fail("$location.detail", "final news disposition mismatch")
    else
        outcome in NEWS_REJECTED_OUTCOMES ||
            fail("$location.outcome", "unsupported news diagnostic outcome")
        (outcome, detail) ==
            (classification.outcome, classification.detail) ||
            fail("$location.outcome", "does not match retained response evidence")
    end
    return (; outcome, completed_at, raw_paths)
end

function _validate_news_diagnostic_document(
        document,
        bundle_directory,
        contract_path,
    )
    root = ReceiptVerifier.expect_exact_keys(
        document,
        NEWS_DIAGNOSTIC_ROOT_KEYS,
        "news diagnostic",
    )
    artifact = ReceiptVerifier.expect_exact_keys(
        root["artifact"],
        NEWS_DIAGNOSTIC_ARTIFACT_KEYS,
        "news diagnostic.artifact",
    )
    artifact["schema_version"] == NEWS_DIAGNOSTIC_SCHEMA ||
        fail("news diagnostic.artifact.schema_version", "schema mismatch")
    artifact["scope"] == NEWS_DIAGNOSTIC_SCOPE ||
        fail("news diagnostic.artifact.scope", "scope mismatch")
    artifact["canonicalization"] ==
        "sorted_typed_v1_excluding_artifact_content_sha256" ||
        fail("news diagnostic.artifact.canonicalization", "method mismatch")
    artifact["digest_algorithm"] == "sha256" ||
        fail("news diagnostic.artifact.digest_algorithm", "must be sha256")
    content_sha256 = ReceiptVerifier.expect_hash(
        artifact["content_sha256"],
        "news diagnostic.artifact.content_sha256",
    )
    content_sha256 == computed_receipt_sha256(root) ||
        fail("news diagnostic.artifact.content_sha256", "content digest mismatch")

    contract = ReceiptVerifier._validate_contract(contract_path)
    root["contract_binding"] == Dict(
        "contract_id" =>
            "beforeit-us-prospective-2026q3-acquisition.v2",
        "contract_file_sha256" => contract.digest,
        "contract_content_sha256" =>
            "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a",
        "event_id" => "bls_employment_situation_2026_07",
    ) || fail("news diagnostic.contract_binding", "contract mismatch")
    root["event"] == Dict(
        "source_id" => "bls_employment_situation",
        "reference_period" => "2026-07",
        "scheduled_timestamp_utc" => "2026-08-07T12:30:00Z",
        "capture_not_before_utc" => "2026-08-07T12:30:00Z",
        "capture_deadline_utc" => "2026-08-07T12:45:00Z",
        "event_purpose" => "capture_rehearsal",
        "required_for_complete_origin" => false,
    ) || fail("news diagnostic.event", "fixed event mismatch")

    diagnostic = ReceiptVerifier.expect_exact_keys(
        root["diagnostic"],
        NEWS_DIAGNOSTIC_KEYS,
        "news diagnostic.diagnostic",
    )
    transaction_id = ReceiptVerifier.expect_identifier(
        diagnostic["transaction_id"],
        "news diagnostic.diagnostic.transaction_id",
    )
    artifact["diagnostic_id"] ==
        "bls-employment-situation-2026-07-news-diagnostic.$transaction_id" ||
        fail("news diagnostic.artifact.diagnostic_id", "transaction mismatch")
    ReceiptVerifier.expect_identifier(
        diagnostic["observer_id"],
        "news diagnostic.diagnostic.observer_id",
    )
    diagnostic["capture_agent"] == CAPTURE_AGENT ||
        fail("news diagnostic.diagnostic.capture_agent", "agent mismatch")
    diagnostic["capture_agent_version"] == CAPTURE_AGENT_VERSION ||
        fail("news diagnostic.diagnostic.capture_agent_version", "version mismatch")
    diagnostic["capture_agent_source_sha256"] ==
        ReceiptVerifier.capture_agent_source_sha256() ||
        fail(
        "news diagnostic.diagnostic.capture_agent_source_sha256",
        "collector source mismatch",
    )
    diagnostic["receipt_verifier_source_sha256"] ==
        ReceiptVerifier.receipt_verifier_source_sha256() ||
        fail(
        "news diagnostic.diagnostic.receipt_verifier_source_sha256",
        "verifier source mismatch",
    )
    source_revision = ReceiptVerifier.expect_source_revision(
        diagnostic["source_revision"],
        "news diagnostic.diagnostic.source_revision",
    )
    diagnostic["clock_basis"] == "CAPTURE_HOST_UTC_CLOCK_ONLY" ||
        fail("news diagnostic.diagnostic.clock_basis", "clock basis mismatch")
    diagnostic["transport_policy"] == LIVE_TRANSPORT_POLICY ||
        fail("news diagnostic.diagnostic.transport_policy", "policy mismatch")
    diagnostic["api_checkpoint_binding_status"] ==
        "UNBOUND_CALLER_REPORTED_TRANSACTION_ID_ONLY" ||
        fail(
        "news diagnostic.diagnostic.api_checkpoint_binding_status",
        "diagnostic must not claim checkpoint binding",
    )
    attempt_count = ReceiptVerifier.expect_int(
        diagnostic["attempt_count"],
        "news diagnostic.diagnostic.attempt_count";
        minimum = 2,
    )
    attempt_count == 2 ||
        fail("news diagnostic.diagnostic.attempt_count", "must be two")
    attempts = root["attempts"]
    attempts isa AbstractVector && length(attempts) == 2 ||
        fail("news diagnostic.attempts", "must contain HTML and PDF attempts")
    validated = [
        _validate_news_attempt(row, index, bundle_directory)
            for (index, row) in enumerate(attempts)
    ]
    outcomes = [row.outcome for row in validated]
    if any(outcome -> outcome == "VALIDATED_COMPLETE_NEWS_SET", outcomes)
        all(outcome -> outcome == "VALIDATED_COMPLETE_NEWS_SET", outcomes) ||
            fail("news diagnostic.attempts", "complete news set must be paired")
    elseif any(
            outcome -> outcome == "VALIDATED_NOT_INSTALLED_INCOMPLETE_SET",
            outcomes,
        )
        any(outcome -> outcome in NEWS_REJECTED_OUTCOMES, outcomes) ||
            fail("news diagnostic.attempts", "incomplete set needs a rejected peer")
    end
    recorded_at = ReceiptVerifier.expect_timestamp(
        diagnostic["recorded_at_utc"],
        "news diagnostic.diagnostic.recorded_at_utc",
    )
    maximum(row.completed_at for row in validated) <= recorded_at <=
        EVENT_DEADLINE + Hour(1) ||
        fail("news diagnostic.diagnostic.recorded_at_utc", "timestamp mismatch")
    all_raw_paths = reduce(
        vcat,
        (row.raw_paths for row in validated);
        init = String[],
    )
    length(all_raw_paths) == length(unique(all_raw_paths)) ||
        fail("news diagnostic.attempts", "raw paths must be unique")

    storage = ReceiptVerifier.expect_exact_keys(
        root["storage"],
        NEWS_STORAGE_KEYS,
        "news diagnostic.storage",
    )
    storage == Dict(
        "policy" =>
            "TWO_DISTINCT_LOCAL_CONTENT_ADDRESSED_NEWS_DIAGNOSTIC_COPIES",
        "copy_ids" => ["replica-a", "replica-b"],
        "minimum_local_copy_count" => 2,
        "diagnostic_replica_required" => true,
        "external_durable_storage_attestation_status" => "NOT_VERIFIED",
    ) || fail("news diagnostic.storage", "storage claim mismatch")
    attestation = ReceiptVerifier.expect_exact_keys(
        root["attestation"],
        NEWS_ATTESTATION_KEYS,
        "news diagnostic.attestation",
    )
    attestation == Dict(
        "capture_clock_attestation_status" =>
            "HOST_CLOCK_OBSERVATION_ONLY",
        "source_transport_attestation_status" =>
            "HOST_REPORTED_HTTP_METADATA_ONLY",
        "external_timestamp_attestation_status" => "NOT_VERIFIED",
        "cryptographic_signoff_status" => "UNSIGNED",
    ) || fail("news diagnostic.attestation", "attestation mismatch")
    disposition = ReceiptVerifier.expect_exact_keys(
        root["disposition"],
        NEWS_DISPOSITION_KEYS,
        "news diagnostic.disposition",
    )
    disposition == Dict(
        "rehearsal_only" => true,
        "diagnostics_only" => true,
        "origin_evidence" => false,
        "origin_admissible" => false,
        "ready" => false,
        "inventory_mutation_authorized" => false,
        "accuracy_evaluation_allowed" => false,
    ) || fail("news diagnostic.disposition", "must remain nonadmitting")
    return (;
        content_sha256,
        source_revision,
        outcomes,
        raw_response_count = count(
            !=("unavailable"), [
                row["raw_sha256"] for row in attempts
            ]
        ),
    )
end

function validate_rehearsal_news_diagnostic_file(
        path;
        contract_path = DEFAULT_PROSPECTIVE_CONTRACT_PATH,
    )
    diagnostic_path = abspath(String(path))
    isfile(diagnostic_path) ||
        fail("news diagnostic file", "file does not exist")
    islink(diagnostic_path) &&
        fail("news diagnostic file", "must not be a symbolic link")
    bundle_directory = dirname(diagnostic_path)
    islink(bundle_directory) &&
        fail("news diagnostic bundle", "must not be a symbolic link")
    bytes = read(diagnostic_path)
    document =
        ReceiptVerifier._parse_toml_bytes(bytes, "news diagnostic file")
    result = _validate_news_diagnostic_document(
        document,
        bundle_directory,
        contract_path,
    )
    name =
        "diagnostic-content-sha256-$(result.content_sha256).toml"
    basename(diagnostic_path) == name ||
        fail("news diagnostic file", "must be content addressed as $name")
    replica_paths = String[]
    for copy_id in ("replica-a", "replica-b")
        relative_path = "$copy_id/$name"
        replica_bytes = ReceiptVerifier._resolve_regular_bytes(
            bundle_directory,
            relative_path,
            "news diagnostic replica $copy_id",
        )
        replica_bytes == bytes ||
            fail("news diagnostic replica", "bytes do not match")
        push!(
            replica_paths,
            realpath(joinpath(bundle_directory, relative_path)),
        )
    end
    ReceiptVerifier._assert_distinct_file_identities(
        [realpath(diagnostic_path), replica_paths...],
        "news diagnostic replicas",
    )
    return (;
        status = "LOCAL_REHEARSAL_NEWS_DIAGNOSTIC_VERIFIED_NONADMITTING",
        result...,
        origin_evidence = false,
        origin_admissible = false,
        ready = false,
    )
end

function install_rehearsal_news_diagnostic(
        output_root,
        attempts,
        response_bodies;
        transaction_id,
        observer_id = "beforeit-us-forecasting",
        recorded_at,
        contract_path = DEFAULT_PROSPECTIVE_CONTRACT_PATH,
    )
    root = abspath(String(output_root))
    mkpath(root)
    islink(root) &&
        fail("news diagnostic output root", "must not be a symbolic link")
    document = _news_diagnostic_document(
        deepcopy(attempts);
        transaction_id,
        observer_id,
        recorded_at,
    )
    bodies = Dict(
        String(object_id) => Vector{UInt8}(bytes)
            for (object_id, bytes) in pairs(response_bodies)
    )
    expected_body_ids = Set(
        row["object_id"] for row in document["attempts"] if
            row["raw_sha256"] != "unavailable"
    )
    Set(keys(bodies)) == expected_body_ids ||
        fail(
        "news diagnostic response bodies",
        "must contain every and only retained response",
    )
    for row in document["attempts"]
        row["raw_sha256"] == "unavailable" && continue
        sha256_hex(bodies[row["object_id"]]) == row["raw_sha256"] ||
            fail("news diagnostic response bodies", "hash mismatch")
    end
    content_sha256 = document["artifact"]["content_sha256"]
    name = "diagnostic-content-sha256-$content_sha256.toml"
    bytes = _toml_bytes(document)
    diagnostics_root = joinpath(root, "news-diagnostics")
    mkpath(diagnostics_root)
    islink(diagnostics_root) &&
        fail("news diagnostic output", "must not be a symbolic link")
    final_path =
        joinpath(diagnostics_root, "sha256-$content_sha256")
    if ispath(final_path)
        validation = validate_rehearsal_news_diagnostic_file(
            joinpath(final_path, name);
            contract_path,
        )
        return (;
            bundle_path = final_path,
            diagnostic_path = joinpath(final_path, name),
            installed = false,
            validation,
        )
    end
    staging_path = mktempdir(diagnostics_root; prefix = ".staging-")
    published = false
    try
        diagnostic_path =
            _write_exact(joinpath(staging_path, name), bytes)
        for row in document["attempts"]
            row["raw_sha256"] == "unavailable" && continue
            body = bodies[row["object_id"]]
            _write_exact(joinpath(staging_path, row["primary_path"]), body)
            _write_exact(joinpath(staging_path, row["replica_path"]), body)
        end
        for copy_id in ("replica-a", "replica-b")
            _write_exact(joinpath(staging_path, copy_id, name), bytes)
        end
        validation = validate_rehearsal_news_diagnostic_file(
            diagnostic_path;
            contract_path,
        )
        mv(staging_path, final_path)
        published = true
        return (;
            bundle_path = final_path,
            diagnostic_path = joinpath(final_path, name),
            installed = true,
            validation,
        )
    finally
        !published && isdir(staging_path) &&
            rm(staging_path; recursive = true)
    end
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
        # Empty CURLOPT_PROXY overrides proxy environment variables. NOPROXY is
        # also pinned to every host so this collector has one direct route policy.
        curl.setopt(easy, curl.CURLOPT_PROXY, "")
        curl.setopt(easy, curl.CURLOPT_NOPROXY, "*")
    end
    return downloader
end

function _bounded_request(
        url;
        method,
        headers,
        request_body = UInt8[],
        body_limit,
        timeout_seconds = LIVE_REQUEST_TIMEOUT_SECONDS,
    )
    body_limit isa Integer && body_limit > 0 ||
        fail("live transport", "body limit must be a positive integer")
    timeout_seconds isa Real && isfinite(timeout_seconds) &&
        timeout_seconds > 0 ||
        fail("live transport", "timeout must be finite and positive")
    output = IOBuffer(; maxsize = body_limit + 1)
    input = isempty(request_body) ? nothing : IOBuffer(request_body)
    started = now(UTC)
    response = try
        Downloads.request(
            String(url);
            downloader = _direct_only_downloader(),
            input,
            output,
            method = String(method),
            headers,
            timeout = timeout_seconds,
        )
    catch
        fail(
            "live transport",
            "request failed under the direct bounded transport policy",
        )
    end
    completed = now(UTC)
    body = take!(output)
    length(body) <= body_limit ||
        fail("live transport", "response exceeded the strict byte limit")
    return (; response, body, started, completed)
end

function _live_fetch(object_id)
    expected = _expected_object(object_id)
    request_headers = [
        "Accept" => expected.media_type,
        "Accept-Encoding" => "identity",
        "User-Agent" => USER_AGENT,
    ]
    request_body = UInt8[]
    if expected.http_method == "POST"
        push!(request_headers, "Content-Type" => "application/json")
        request_body = Vector{UInt8}(codeunits(expected.request_body))
    end
    body_limit = LIVE_BODY_LIMITS[object_id]
    fetched = try
        _bounded_request(
            expected.requested_url;
            method = expected.http_method,
            headers = request_headers,
            request_body,
            body_limit,
        )
    catch
        fail(
            "live $object_id",
            "request failed under $LIVE_TRANSPORT_POLICY",
        )
    end
    response = fetched.response
    content_type = ""
    for (name, value) in response.headers
        lowercase(String(name)) == "content-type" || continue
        content_type = String(value)
        break
    end
    return CapturedResponse(
        object_id = object_id,
        body = fetched.body,
        requested_url = expected.requested_url,
        effective_url = response.url,
        status_code = response.status,
        content_type = content_type,
        response_headers = _normalized_headers(response; require_required = false),
        acquisition_started_at_utc = fetched.started,
        response_metadata_observed_at_utc = fetched.completed,
        acquisition_completed_at_utc = fetched.completed,
    )
end

"""
    acquire_live_rehearsal(output_root; ...)

Execute the fixed 2026-08-07 BLS rehearsal. The canonical POST uses the v2
endpoint with an unregistered v1-compatible request signature, not the
registered v2 service. News HTML and PDF are attempted next; if either official
route is unavailable, the installed receipt is explicitly downgraded to the
API-only history-as-known-at-capture scope. The 25-attempt cap is per
invocation and does not attest the same-IP daily quota remainder. No mode is
origin evidence.
"""
function acquire_live_rehearsal(
        output_root;
        transaction_id = _default_transaction_id(),
        observer_id = "beforeit-us-forecasting",
        clock = () -> now(UTC),
        fetch = _live_fetch,
        wait = seconds -> sleep(seconds),
        recorded_clock = () -> now(UTC),
        poll_interval_seconds = 37,
        maximum_api_attempts = UNREGISTERED_API_DAILY_LIMIT,
    )
    poll_interval_seconds isa Integer && poll_interval_seconds > 0 ||
        fail("poll interval", "must be a positive integer")
    maximum_api_attempts isa Integer && maximum_api_attempts > 0 ||
        fail("maximum API attempts", "must be a positive integer")
    maximum_api_attempts <= UNREGISTERED_API_DAILY_LIMIT ||
        fail(
        "maximum API attempts",
        "must not exceed the anonymous per-invocation safety cap of " *
            "$UNREGISTERED_API_DAILY_LIMIT",
    )
    api_attempts = NamedTuple[]
    api_attempt_bodies = Dict{String, Vector{UInt8}}()
    journal_snapshots = NamedTuple[]
    function fresh_recorded_at(fallback)
        value = recorded_clock()
        value isa DateTime ||
            return fallback
        return max(value, fallback)
    end
    function record_journal!(
            state,
            recorded_at;
            failure_reason = "NOT_APPLICABLE",
        )
        snapshot = install_rehearsal_attempt_journal(
            output_root,
            api_attempts;
            api_attempt_bodies,
            transaction_id,
            observer_id,
            recorded_at,
            state,
            failure_reason,
        )
        push!(journal_snapshots, snapshot)
        return snapshot
    end
    observed = clock()
    observed isa DateTime ||
        fail("live clock", "must return a DateTime")
    if !(EVENT_START <= observed <= EVENT_DEADLINE)
        record_journal!(
            "FAILED",
            observed;
            failure_reason = "OUTSIDE_EVENT_WINDOW",
        )
        fail(
            "live clock",
            "must start between 2026-08-07T12:30:00Z and 12:45:00Z",
        )
    end
    api = nothing
    last_known_time = observed
    for attempt_number in 1:maximum_api_attempts
        attempt_started = try
            clock()
        catch
            record_journal!(
                "FAILED",
                last_known_time;
                failure_reason = "CLOCK_FAILURE",
            )
            fail("live clock", "failed while starting an API attempt")
        end
        if !(attempt_started isa DateTime) ||
                attempt_started < last_known_time
            record_journal!(
                "FAILED",
                last_known_time;
                failure_reason = "CLOCK_FAILURE",
            )
            fail("live clock", "must return a DateTime")
        end
        last_known_time = attempt_started
        if attempt_started > EVENT_DEADLINE
            record_journal!(
                "FAILED",
                attempt_started;
                failure_reason = "API_DEADLINE_REACHED",
            )
            fail("live API", "July data were not available by the deadline")
        end
        response = try
            fetch(API_OBJECT_ID)
        catch error
            push!(
                api_attempts,
                (
                    attempt_number,
                    attempted_at_utc = timestamp(attempt_started),
                    status_code = 0,
                    response_sha256 = "unavailable",
                    outcome = "REQUEST_FAILED",
                    detail = "REQUEST_EXCEPTION",
                ),
            )
            nothing
        end
        if response !== nothing
            if !(response isa CapturedResponse)
                push!(
                    api_attempts,
                    (
                        attempt_number,
                        attempted_at_utc = timestamp(attempt_started),
                        status_code = 0,
                        response_sha256 = "unavailable",
                        outcome = "REQUEST_FAILED",
                        detail = "REQUEST_EXCEPTION",
                    ),
                )
                record_journal!(
                    "FAILED",
                    attempt_started;
                    failure_reason = "FETCH_CONTRACT_VIOLATION",
                )
                fail("live API", "fetch must return CapturedResponse")
            end
            outcome =
                response.status_code == 200 ? "INVALID_API_RESPONSE" :
                "HTTP_NON_200"
            detail =
                response.status_code == 200 ?
                "CANONICAL_RESPONSE_VALIDATION_FAILED" :
                "HTTP_$(response.status_code)"
            if response.status_code == 200
                try
                    ReceiptVerifier._parse_api_values(response.body)
                    try
                        _validate_response_shape(response, attempt_number)
                        outcome = "ACCEPTED_M07"
                        detail = "CES_AND_CPS_M07_PRESENT"
                        api = response
                    catch error
                        (
                            error isa RehearsalCaptureError ||
                                error isa ReceiptVerifier.RehearsalReceiptError
                        ) || rethrow()
                        outcome = "INVALID_API_RESPONSE_METADATA_REPORTED"
                        detail =
                            "CAPTURE_AGENT_REPORTED_METADATA_VALIDATION_FAILED"
                    end
                catch error
                    error isa ReceiptVerifier.RehearsalReceiptError ||
                        rethrow()
                    if ReceiptVerifier._expected_series_without_complete_m07(
                            response.body,
                        )
                        outcome = "M07_NOT_AVAILABLE"
                        detail =
                            "EXPECTED_SERIES_WITHOUT_COMPLETE_M07"
                    end
                end
            end
            push!(
                api_attempts,
                (
                    attempt_number,
                    attempted_at_utc = timestamp(attempt_started),
                    status_code = response.status_code,
                    response_sha256 = sha256_hex(response.body),
                    outcome,
                    detail,
                ),
            )
            api_attempt_bodies[sha256_hex(response.body)] =
                copy(response.body)
        end
        recorded_at =
            response === nothing ? attempt_started :
            max(attempt_started, response.acquisition_completed_at_utc)
        record_journal!(
            api === nothing ? "POLLING" :
                "ACCEPTED_M07_PENDING_BUNDLE",
            recorded_at,
        )
        api !== nothing && break
        after_attempt = try
            clock()
        catch
            record_journal!(
                "FAILED",
                recorded_at;
                failure_reason = "CLOCK_FAILURE",
            )
            fail("live clock", "failed after an API attempt")
        end
        if !(after_attempt isa DateTime)
            record_journal!(
                "FAILED",
                recorded_at;
                failure_reason = "CLOCK_FAILURE",
            )
            fail("live clock", "must return a DateTime")
        end
        if after_attempt < last_known_time
            record_journal!(
                "FAILED",
                last_known_time;
                failure_reason = "CLOCK_FAILURE",
            )
            fail("live clock", "must be nondecreasing")
        end
        last_known_time = after_attempt
        if after_attempt >= EVENT_DEADLINE
            record_journal!(
                "FAILED",
                after_attempt;
                failure_reason = "API_DEADLINE_REACHED",
            )
            fail("live API", "July data were not available by the deadline")
        end
        if attempt_number >= maximum_api_attempts
            record_journal!(
                "FAILED",
                after_attempt;
                failure_reason = "MAXIMUM_API_ATTEMPTS_EXHAUSTED",
            )
            fail("live API", "maximum polling attempts exhausted")
        end
        remaining_seconds =
            div(Dates.value(EVENT_DEADLINE - after_attempt), 1000)
        wait_seconds = min(Int(poll_interval_seconds), remaining_seconds)
        if wait_seconds <= 0
            record_journal!(
                "FAILED",
                after_attempt;
                failure_reason = "API_DEADLINE_REACHED",
            )
            fail("live API", "no time remains before the deadline")
        end
        try
            wait(wait_seconds)
        catch
            record_journal!(
                "FAILED",
                after_attempt;
                failure_reason = "WAIT_FAILED",
            )
            fail("live API", "poll wait failed")
        end
    end
    if api === nothing
        recorded_at =
            isempty(api_attempts) ? observed :
            DateTime(
                chop(api_attempts[end].attempted_at_utc; tail = 1),
                TIMESTAMP_FORMAT,
            )
        record_journal!(
            "FAILED",
            recorded_at;
            failure_reason = "NO_ACCEPTED_M07_RESPONSE",
        )
        fail("live API", "no accepted July response was captured")
    end

    api_installation = try
        install_rehearsal_capture(
            output_root,
            CapturedResponse[api];
            transaction_id,
            observer_id,
            api_attempts,
            api_attempt_bodies,
        )
    catch
        record_journal!(
            "FAILED",
            fresh_recorded_at(api.acquisition_completed_at_utc);
            failure_reason = "BUNDLE_INSTALLATION_FAILED",
        )
        rethrow()
    end
    api_bundle_recorded_at =
        fresh_recorded_at(api.acquisition_completed_at_utc)
    record_journal!("BUNDLE_INSTALLED", api_bundle_recorded_at)

    news = CapturedResponse[]
    news_attempt_records = Dict{String, Any}[]
    news_response_bodies = Dict{String, Vector{UInt8}}()
    news_last_time = api.acquisition_completed_at_utc
    for object_id in (HTML_OBJECT_ID, PDF_OBJECT_ID)
        attempted_at = fresh_recorded_at(news_last_time)
        response = try
            fetch(object_id)
        catch
            push!(
                news_attempt_records,
                _news_unavailable_attempt(
                    object_id,
                    attempted_at,
                    "REQUEST_FAILED",
                ),
            )
            continue
        end
        if !(response isa CapturedResponse)
            push!(
                news_attempt_records,
                _news_unavailable_attempt(
                    object_id,
                    attempted_at,
                    "FETCH_CONTRACT_VIOLATION",
                ),
            )
            continue
        end
        sanitized = _sanitized_captured_response(response)
        news_last_time =
            max(news_last_time, sanitized.acquisition_completed_at_utc)
        record = _news_response_attempt(sanitized, object_id)
        push!(news_attempt_records, record)
        news_response_bodies[object_id] = copy(sanitized.body)
        record["outcome"] == "VALIDATED" && push!(news, sanitized)
    end
    installation = api_installation
    full_bundle_error = nothing
    if length(news) == 2
        try
            installation = install_rehearsal_capture(
                output_root,
                vcat([api], news);
                transaction_id,
                observer_id,
                api_attempts,
                api_attempt_bodies,
            )
        catch error
            full_bundle_error = error
        end
    end
    _finalize_news_attempts!(news_attempt_records)
    news_diagnostic = install_rehearsal_news_diagnostic(
        output_root,
        news_attempt_records,
        news_response_bodies;
        transaction_id,
        observer_id,
        recorded_at = fresh_recorded_at(news_last_time),
    )
    full_bundle_error === nothing || throw(full_bundle_error)
    news_attempts = [
        (
                object_id = row["object_id"],
                status_code = row["status_code"],
                outcome = row["outcome"],
                detail = row["detail"],
                response_sha256 = row["raw_sha256"],
            ) for row in news_attempt_records
    ]
    return (;
        installation...,
        api_bundle_path = api_installation.bundle_path,
        api_receipt_path = api_installation.receipt_path,
        api_attempts,
        news_attempts,
        news_diagnostic_path = news_diagnostic.diagnostic_path,
        news_diagnostic_bundle_path = news_diagnostic.bundle_path,
        news_diagnostic_validation = news_diagnostic.validation,
        journal_snapshots,
    )
end

end
