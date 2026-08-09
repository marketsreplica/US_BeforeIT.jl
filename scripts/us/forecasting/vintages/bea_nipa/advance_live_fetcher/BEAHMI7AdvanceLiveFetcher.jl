module BEAHMI7AdvanceLiveFetcher

using Dates
using Downloads
using SHA

export BEAHMI7AdvanceLiveFetcherError,
    LIVE_TIMEOUT_SECONDS,
    dry_run_plan,
    execute_live_pair,
    transport_policy

const CAPTURE_SOURCE_SHA256 =
    "6da4ad0bc4a458c05e6594448c23aea5c6ae3f25f743d74ae3507d27a8831339"
const METADATA_SOURCE_SHA256 =
    "ffa254aca14a2d26b711a1ceb7e7ef2be60e703f0918db4b736e780df30b4039"
const METADATA_MANIFEST_FILE_SHA256 =
    "b785ee5eea5788f7c38a5de391e4173a376780ce48043e0444c37eb84502c607"
const METADATA_MANIFEST_CONTENT_SHA256 =
    "186903041b649480b34a130f8c7518fb53a875e5b02ce4d6c3ee674080d5b824"
const PROJECT_FILE_SHA256 =
    "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"
const JULIA_MANIFEST_FILE_SHA256 =
    "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"

const SCRIPTS_US_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const DEFAULT_SOURCE_PATHS = (;
    capture_source_path = normpath(
        joinpath(
            @__DIR__,
            "..",
            "advance_capture",
            "BEAHMI7AdvanceCapture.jl",
        ),
    ),
    metadata_source_path = normpath(
        joinpath(
            @__DIR__,
            "..",
            "advance_metadata_manifest",
            "BEAHMI7AdvanceMetadataManifest.jl",
        ),
    ),
    metadata_manifest_path = normpath(
        joinpath(
            @__DIR__,
            "..",
            "advance_metadata_manifest",
            "bea_hmi7_advance_manifest_2011q3_2021q2.toml",
        ),
    ),
    project_path = joinpath(SCRIPTS_US_ROOT, "Project.toml"),
    julia_manifest_path = joinpath(SCRIPTS_US_ROOT, "Manifest.toml"),
)

const LIVE_TIMEOUT_SECONDS = 60
const TRANSPORT_POLICY_ID =
    "DOWNLOADS_DIRECT_HTTPS_GET_IDENTITY_NO_REDIRECT_NO_PROXY_NO_NETRC_NO_COOKIES_NO_RETRY_V1"
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
const OFFICIAL_URL_PREFIX =
    "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/"
const EXPECTED_REQUEST_COUNT = 2

const ALWAYS_FALSE_GATES = (;
    historical_first_state_proven = false,
    historical_workbook_availability_proven = false,
    strict_origin_admissible = false,
    empirical_forecast_execution_allowed = false,
    source_inventory_mutation_allowed = false,
    promotion_eligible = false,
    production_scoring_allowed = false,
    ready = false,
    transport_provenance_authenticated = false,
    reviewer_identity_authenticated = false,
    host_clock_authenticated = false,
)

struct BEAHMI7AdvanceLiveFetcherError <: Exception
    message::String
end

Base.showerror(io::IO, error::BEAHMI7AdvanceLiveFetcherError) =
    print(io, error.message)

fail(location, message) =
    throw(BEAHMI7AdvanceLiveFetcherError("$location: $message"))

sha256_hex(bytes) = bytes2hex(sha256(bytes))

function _regular_file_sha256(path, location)
    text = String(path)
    isabspath(text) || fail(location, "path must be absolute")
    normpath(text) == text || fail(location, "path must be normalized")
    isfile(text) || fail(location, "missing regular file $text")
    islink(text) && fail(location, "symbolic links are forbidden")
    realpath(text) == text || fail(location, "path must be canonical")
    stat(text).nlink == 1 || fail(location, "hard-linked files are forbidden")
    return sha256_hex(read(text))
end

function _validate_file_bindings(paths = DEFAULT_SOURCE_PATHS)
    observed = (;
        capture_source_sha256 = _regular_file_sha256(
            paths.capture_source_path,
            "source.capture",
        ),
        metadata_source_sha256 = _regular_file_sha256(
            paths.metadata_source_path,
            "source.metadata_module",
        ),
        metadata_manifest_file_sha256 = _regular_file_sha256(
            paths.metadata_manifest_path,
            "source.metadata_manifest",
        ),
        project_file_sha256 = _regular_file_sha256(
            paths.project_path,
            "source.project",
        ),
        julia_manifest_file_sha256 = _regular_file_sha256(
            paths.julia_manifest_path,
            "source.julia_manifest",
        ),
    )
    observed.capture_source_sha256 == CAPTURE_SOURCE_SHA256 ||
        fail("source.capture", "SHA-256 identity changed")
    observed.metadata_source_sha256 == METADATA_SOURCE_SHA256 ||
        fail("source.metadata_module", "SHA-256 identity changed")
    observed.metadata_manifest_file_sha256 ==
        METADATA_MANIFEST_FILE_SHA256 ||
        fail("source.metadata_manifest", "file SHA-256 identity changed")
    observed.project_file_sha256 == PROJECT_FILE_SHA256 ||
        fail("source.project", "SHA-256 identity changed")
    observed.julia_manifest_file_sha256 == JULIA_MANIFEST_FILE_SHA256 ||
        fail("source.julia_manifest", "SHA-256 identity changed")
    return observed
end

# Verify every executable and environment input before loading the accepted
# capture boundary. The same check runs again before every plan or live call.
const PREINCLUDE_FILE_BINDINGS = _validate_file_bindings()

include(DEFAULT_SOURCE_PATHS.capture_source_path)
using .BEAHMI7AdvanceCapture

const CaptureBoundary = BEAHMI7AdvanceCapture

function _validate_source_bindings(paths = DEFAULT_SOURCE_PATHS)
    bindings = _validate_file_bindings(paths)
    artifact = CaptureBoundary.capture_plan(1).metadata
    artifact.content_sha256 == METADATA_MANIFEST_CONTENT_SHA256 ||
        fail("source.metadata_manifest", "semantic SHA-256 identity changed")
    artifact.file_sha256 == METADATA_MANIFEST_FILE_SHA256 ||
        fail("source.metadata_manifest", "validated file identity changed")
    return merge(
        bindings,
        (;
            metadata_manifest_content_sha256 =
                METADATA_MANIFEST_CONTENT_SHA256,
            metadata_manifest_byte_count = artifact.file_byte_count,
            capture_schema_version = CaptureBoundary.SCHEMA_VERSION,
        ),
    )
end

function _canonical_date(value, location)
    value isa Date && return value
    value isa AbstractString || fail(location, "must be a Date or string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", text) ||
        fail(location, "must use canonical YYYY-MM-DD")
    parsed = tryparse(Date, text)
    parsed === nothing && fail(location, "is not a valid calendar date")
    string(parsed) == text || fail(location, "must be canonical")
    return parsed
end

function _reviewer(value)
    value isa AbstractString || fail("reviewer", "must be a string")
    text = String(value)
    text == strip(text) || fail("reviewer", "has surrounding whitespace")
    isempty(text) && fail("reviewer", "must not be empty")
    ncodeunits(text) <= 256 || fail("reviewer", "exceeds 256 bytes")
    any(character -> Int(character) < 0x20 || Int(character) == 0x7f, text) &&
        fail("reviewer", "contains a forbidden control character")
    return text
end

function _existing_canonical_raw_root(value)
    value isa AbstractString || fail("raw_root", "must be a string")
    root = String(value)
    root == strip(root) || fail("raw_root", "has surrounding whitespace")
    isabspath(root) || fail("raw_root", "must be absolute")
    normpath(root) == root ||
        fail("raw_root", "must be normalized without traversal aliases")
    dirname(root) != root || fail("raw_root", "filesystem roots are forbidden")
    isdir(root) || fail("raw_root", "must be an existing directory")
    candidate = root
    while true
        islink(candidate) &&
            fail("raw_root", "must not traverse a symbolic link")
        parent = dirname(candidate)
        parent == candidate && break
        candidate = parent
    end
    realpath(root) == root || fail("raw_root", "must be canonical")
    return root
end

function _validate_target(target)
    target.url isa AbstractString || fail("target.url", "must be a string")
    url = String(target.url)
    startswith(url, OFFICIAL_URL_PREFIX) ||
        fail("target.url", "is outside the exact BEA HMI7 HTTPS tree")
    occursin(r"[?#]", url) && fail("target.url", "query and fragment are forbidden")
    occursin('%', url) && fail("target.url", "percent-encoded paths are forbidden")
    target.request_headers == (
        "Accept" => target.media_type,
        "Accept-Encoding" => "identity",
        "User-Agent" => "BeforeIT-US-BEA-HMI7-Advance-Capture/1.0",
    ) || fail("target.request_headers", "changed from the accepted boundary")
    return target
end

"""
    transport_policy()

Return the closed built-in transport controls as inert data. This is an
inspectable local configuration assertion, not independent transport proof.
"""
function transport_policy()
    return (;
        policy_id = TRANSPORT_POLICY_ID,
        method = "GET",
        protocol = "HTTPS_ONLY",
        host = "apps.bea.gov",
        path_prefix = "/HistData/Files/Releases/GDP_and_PI/",
        follow_redirects = false,
        maximum_redirects = 0,
        ambient_proxy_allowed = false,
        netrc_allowed = false,
        cookies_allowed = false,
        retry_count = 0,
        timeout_seconds = LIVE_TIMEOUT_SECONDS,
        maximum_body_bytes = CaptureBoundary.MAX_WORKBOOK_BYTES,
        response_header_order_preserved = true,
        response_headers_allowlisted = false,
        transport_provenance_authenticated = false,
    )
end

function _direct_only_downloader()
    downloader = Downloads.Downloader(; grace = 0)
    downloader.easy_hook = (easy, info) -> begin
        info.method == "GET" ||
            fail("transport.method", "must be the exact GET method")
        startswith(String(info.url), OFFICIAL_URL_PREFIX) ||
            fail("transport.url", "must remain inside the sealed HTTPS tree")
        curl = Downloads.Curl
        curl.setopt(easy, curl.CURLOPT_FOLLOWLOCATION, false)
        curl.setopt(easy, curl.CURLOPT_MAXREDIRS, 0)
        curl.setopt(easy, curl.CURLOPT_AUTOREFERER, false)
        curl.setopt(easy, curl.CURLOPT_UNRESTRICTED_AUTH, false)
        curl.setopt(easy, curl.CURLOPT_PROTOCOLS, curl.CURLPROTO_HTTPS)
        curl.setopt(easy, curl.CURLOPT_REDIR_PROTOCOLS, 0)
        curl.setopt(easy, curl.CURLOPT_NETRC, curl.CURL_NETRC_IGNORED)
        curl.setopt(easy, curl.CURLOPT_NETRC_FILE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIEFILE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIEJAR, C_NULL)
        curl.setopt(easy, curl.CURLOPT_PROXY, "")
        curl.setopt(easy, curl.CURLOPT_NOPROXY, "*")
        curl.setopt(
            easy,
            curl.CURLOPT_MAXFILESIZE_LARGE,
            Int64(CaptureBoundary.MAX_WORKBOOK_BYTES),
        )
    end
    return downloader
end

function _download_progress(download_total, download_now, upload_total, upload_now)
    for (value, location) in (
            download_total => "download_total",
            download_now => "download_now",
            upload_total => "upload_total",
            upload_now => "upload_now",
        )
        value isa Integer && !(value isa Bool) ||
            fail("transport.progress.$location", "must be an integer")
        value >= 0 || fail("transport.progress.$location", "must not be negative")
    end
    upload_total == 0 && upload_now == 0 ||
        fail("transport.progress", "GET requests must not upload a body")
    ceiling = CaptureBoundary.MAX_WORKBOOK_BYTES
    download_total <= ceiling ||
        fail("transport.body", "advertised body exceeds $ceiling bytes")
    download_now <= ceiling ||
        fail("transport.body", "streamed body exceeds $ceiling bytes")
    return nothing
end

function _clock_sample(clock, location)
    value = clock()
    value isa DateTime || fail(location, "clock must return a UTC DateTime")
    return value
end

timestamp(value::DateTime) = Dates.format(value, TIMESTAMP_FORMAT) * "Z"

function _response_field(response, name)
    hasproperty(response, name) ||
        fail("transport.response", "missing field $name")
    return getproperty(response, name)
end

function _ordered_response_headers(value)
    value isa AbstractVector ||
        fail("transport.response.headers", "must be a vector")
    headers = Pair{String, String}[]
    for (index, header) in enumerate(value)
        header isa Pair ||
            fail(
            "transport.response.headers[$index]",
            "must be a name/value pair",
        )
        push!(headers, String(first(header)) => String(last(header)))
    end
    return headers
end

function _fetch_target(
        target,
        request_executor,
        downloader_factory,
        clock,
    )
    _validate_target(target)
    request_headers = collect(target.request_headers)
    output = IOBuffer(; maxsize = CaptureBoundary.MAX_WORKBOOK_BYTES)
    started = _clock_sample(clock, "transport.request_started_at_utc")
    response = try
        request_executor(
            target.url;
            output,
            method = "GET",
            headers = request_headers,
            timeout = LIVE_TIMEOUT_SECONDS,
            progress = _download_progress,
            downloader = downloader_factory(),
            throw = false,
        )
    catch error
        error isa BEAHMI7AdvanceLiveFetcherError && rethrow()
        fail("transport.request", "failed under the closed no-retry policy")
    end
    completed = _clock_sample(clock, "transport.response_body_completed_at_utc")
    completed >= started ||
        fail("transport.clock", "host UTC clock moved backwards")
    response isa Downloads.RequestError &&
        fail("transport.request", "Downloads returned a request error")
    proto = _response_field(response, :proto)
    proto == "https" || fail("transport.response.proto", "must equal https")
    status = _response_field(response, :status)
    status isa Integer && !(status isa Bool) ||
        fail("transport.response.status", "must be an integer")
    effective_url = _response_field(response, :url)
    effective_url isa AbstractString ||
        fail("transport.response.url", "must be a string")
    String(effective_url) == target.url ||
        fail("transport.response.url", "redirect or URL rewriting detected")
    response_headers =
        _ordered_response_headers(_response_field(response, :headers))
    body = take!(output)
    length(body) <= CaptureBoundary.MAX_WORKBOOK_BYTES ||
        fail("transport.body", "exceeds the streaming byte ceiling")

    # Downloads returns response metadata only after the body transfer. Record
    # that later observation for the header timestamp rather than inventing an
    # earlier socket-level time.
    fetched = CaptureBoundary.FetchResponse(
        body,
        Int(status),
        request_headers,
        response_headers,
        true,
        target.url,
        String(effective_url),
        Tuple[],
        timestamp(started),
        timestamp(completed),
        timestamp(completed),
    )
    CaptureBoundary._validate_response(fetched, target, "transport.response")
    return fetched
end

"""
    dry_run_plan(sequence)

Validate every frozen source identity and return the exact one-release/two-URL
plan. No downloader is constructed, no callback is invoked, and no filesystem
write is performed.
"""
function dry_run_plan(sequence::Integer)
    sequence isa Bool && fail("sequence", "must be an integer, not Boolean")
    bindings = _validate_source_bindings()
    plan = CaptureBoundary.capture_plan(sequence)
    for target in plan.workbooks
        _validate_target(target)
    end
    return (;
        dry_run = true,
        sequence = plan.release.sequence,
        release = plan.release,
        workbooks = plan.workbooks,
        request_count = length(plan.workbooks),
        source_bindings = bindings,
        transport = transport_policy(),
        network_callbacks_invoked = 0,
        network_requests_made = 0,
        filesystem_writes_made = 0,
        transport_assertion_authentication =
            "UNAUTHENTICATED_LOCAL_PROCESS_ASSERTION",
        gates = ALWAYS_FALSE_GATES,
    )
end

function _execute_pair_impl(
        sequence,
        raw_root,
        reviewed_date_value,
        reviewer_value,
        request_executor,
        downloader_factory,
        clock,
        source_paths,
    )
    sequence isa Integer && !(sequence isa Bool) ||
        fail("sequence", "must be an integer")
    bindings = _validate_source_bindings(source_paths)
    plan = CaptureBoundary.capture_plan(sequence)
    for target in plan.workbooks
        _validate_target(target)
    end
    length(plan.workbooks) == EXPECTED_REQUEST_COUNT ||
        fail("capture", "must contain exactly one Section 1/Section 2 pair")
    root = _existing_canonical_raw_root(raw_root)
    reviewed_date = _canonical_date(
        reviewed_date_value,
        "terms_reviewed_local_date",
    )
    host_local_date = today()
    reviewed_date == host_local_date ||
        fail(
        "terms_reviewed_local_date",
        "must equal the current host-local date $host_local_date",
    )
    reviewer = _reviewer(reviewer_value)

    callback_count = Ref(0)
    fetcher = target -> begin
        callback_count[] += 1
        callback_count[] <= EXPECTED_REQUEST_COUNT ||
            fail("capture", "fetcher exceeded the one-pair ceiling")
        target == plan.workbooks[callback_count[]] ||
            fail("capture", "workbook order changed")
        return _fetch_target(
            target,
            request_executor,
            downloader_factory,
            clock,
        )
    end
    result = CaptureBoundary.capture_present_day_with_fetcher(
        sequence,
        root,
        fetcher;
        live = true,
        terms_reviewed = true,
        terms_reviewed_local_date = reviewed_date,
        reviewer,
    )
    callback_count[] == EXPECTED_REQUEST_COUNT ||
        fail("capture", "did not execute the exact two-request pair")
    all(!value for value in values(result.gates)) ||
        fail("capture.gates", "accepted boundary enabled a forbidden gate")
    today() == host_local_date ||
        fail("capture_local_date", "host-local date changed during capture")
    return merge(
        result,
        (;
            downloader_invocation_count = callback_count[],
            downloader_invocation_ceiling = EXPECTED_REQUEST_COUNT,
            source_bindings = bindings,
            transport_policy = transport_policy(),
            transport_provenance_authenticated = false,
            reviewer_identity_authenticated = false,
            host_clock_authenticated = false,
        ),
    )
end

"""
    execute_live_pair(sequence, raw_root; terms_reviewed_local_date, reviewer)

Execute exactly one Section 1/Section 2 pair through the built-in Downloads
transport and the accepted content-addressed boundary. There is intentionally
no downloader, callback, clock, metadata-path, loop, or scheduler argument.
"""
function execute_live_pair(
        sequence::Integer,
        raw_root::AbstractString;
        terms_reviewed_local_date,
        reviewer,
    )
    return _execute_pair_impl(
        sequence,
        raw_root,
        terms_reviewed_local_date,
        reviewer,
        Downloads.request,
        _direct_only_downloader,
        () -> now(UTC),
        DEFAULT_SOURCE_PATHS,
    )
end

end
