module BEAScheduleMonitor

using Dates
using Downloads
using SHA
using TOML

export BEA_SCHEDULE_URL,
    EXPECTED_DATE_TEXT,
    EXPECTED_TIME_TEXT,
    EXPECTED_TITLE,
    FetchedSchedule,
    ScheduleMonitorError,
    ValidatedScheduleEvent,
    capture_live_snapshot,
    fetch_official_schedule,
    sha256_hex,
    validate_expected_event,
    write_validated_snapshot

const BEA_SCHEDULE_URL = "https://www.bea.gov/news/schedule"
const EXPECTED_DATE_TEXT = "October 29"
const EXPECTED_TIME_TEXT = "8:30 AM"
const EXPECTED_TITLE = "GDP (Advance Estimate), 3rd Quarter 2026"
const MAX_RESPONSE_BYTES = 2_000_000
const FETCH_TIMEOUT_SECONDS = 30
const SNAPSHOT_SCHEMA = "beforeit-us-bea-schedule-snapshot.v1"
const SNAPSHOT_STATUS =
    "MUTABLE_SCHEDULE_SNAPSHOT_ONLY_NOT_RELEASE_OR_ORIGIN_EVIDENCE"
const EVIDENCE_CLASS = "mutable_official_schedule_snapshot"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const TARGET_ROW_PATTERN =
r"""(?is)<tr\s+class="scheduled-releases-type-press"\s*>(.*?)</tr\s*>"""
const DATE_PATTERN =
r"""(?is)<div\s+class="release-date"\s*>(.*?)</div\s*>"""
const TIME_PATTERN =
r"""(?is)<small\s+class="text-muted"\s*>(.*?)</small\s*>"""
const TITLE_PATTERN = Regex(
    raw"""(?is)<td\s+class="release-title views-field views-field-field-scheduled-releases-type"\s+headers="view-field-scheduled-release-subject-table-column"\s*>(.*?)</td\s*>""",
)
const CANONICAL_PATTERN = Regex(
    raw"""(?is)<link\s+rel="canonical"\s+href="https://www\.bea\.gov/news/schedule"\s*/?>""",
)

struct ScheduleMonitorError <: Exception
    message::String
end

Base.showerror(io::IO, error::ScheduleMonitorError) =
    print(io, error.message)

struct ValidatedScheduleEvent
    date_text::String
    time_text::String
    title::String
    match_count::Int
    evidence_class::String
    release_evidence::Bool
    origin_evidence::Bool
    origin_admissible::Bool
end

struct FetchedSchedule
    raw_bytes::Vector{UInt8}
    http_status::Int
    content_type::String
    effective_locator::String
    response_date::String
    etag::String
    last_modified::String
end

fail(location, message) =
    throw(ScheduleMonitorError("$location: $message"))

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(sha256(bytes))
sha256_hex(text::AbstractString) =
    sha256_hex(Vector{UInt8}(codeunits(text)))

function _schedule_text(payload)
    bytes = if payload isa AbstractVector{UInt8}
        Vector{UInt8}(payload)
    elseif payload isa AbstractString
        Vector{UInt8}(codeunits(payload))
    else
        return fail("schedule", "must be UTF-8 text or bytes")
    end
    isempty(bytes) && fail("schedule", "must not be empty")
    length(bytes) <= MAX_RESPONSE_BYTES ||
        fail(
        "schedule",
        "exceeds the $(MAX_RESPONSE_BYTES)-byte parser limit",
    )
    text = String(bytes)
    isvalid(text) || fail("schedule", "is not valid UTF-8")
    occursin('\0', text) &&
        fail("schedule", "must not contain NUL bytes")
    return text
end

function _only_capture(pattern, text, location)
    matches = collect(eachmatch(pattern, text))
    length(matches) == 1 ||
        fail(location, "must occur exactly once; found $(length(matches))")
    return only(matches).captures[1]
end

function _plain_text(fragment, location)
    occursin(r"[<>&]", fragment) &&
        fail(location, "must contain plain text without nested markup")
    return strip(replace(fragment, r"\s+" => " "))
end

function validate_expected_event(payload)
    text = _schedule_text(payload)
    length(collect(eachmatch(CANONICAL_PATTERN, text))) == 1 ||
        fail(
        "schedule.canonical",
        "must identify the official BEA schedule exactly once",
    )
    length(findall(EXPECTED_TITLE, text)) == 1 ||
        fail(
        "schedule.expected_title",
        "must occur exactly once as literal text",
    )

    target_rows = String[]
    for row_match in eachmatch(TARGET_ROW_PATTERN, text)
        row = row_match.captures[1]
        occursin(EXPECTED_TITLE, row) && push!(target_rows, row)
    end
    length(target_rows) == 1 ||
        fail(
        "schedule.expected_row",
        "must occur exactly once as a strict press-release row; found $(length(target_rows))",
    )

    row = only(target_rows)
    date_text = _plain_text(
        _only_capture(DATE_PATTERN, row, "schedule.expected_row.date"),
        "schedule.expected_row.date",
    )
    time_text = _plain_text(
        _only_capture(TIME_PATTERN, row, "schedule.expected_row.time"),
        "schedule.expected_row.time",
    )
    title = _plain_text(
        _only_capture(TITLE_PATTERN, row, "schedule.expected_row.title"),
        "schedule.expected_row.title",
    )

    date_text == EXPECTED_DATE_TEXT ||
        fail(
        "schedule.expected_row.date",
        "expected \"$EXPECTED_DATE_TEXT\", found \"$date_text\"",
    )
    time_text == EXPECTED_TIME_TEXT ||
        fail(
        "schedule.expected_row.time",
        "expected \"$EXPECTED_TIME_TEXT\", found \"$time_text\"",
    )
    title == EXPECTED_TITLE ||
        fail(
        "schedule.expected_row.title",
        "expected \"$EXPECTED_TITLE\", found \"$title\"",
    )

    return ValidatedScheduleEvent(
        date_text,
        time_text,
        title,
        1,
        EVIDENCE_CLASS,
        false,
        false,
        false,
    )
end

function _header(response, name)
    values = String[
        String(value) for (key, value) in response.headers if
            lowercase(String(key)) == lowercase(name)
    ]
    length(values) <= 1 ||
        fail("http.header.$name", "must not be repeated")
    return isempty(values) ? "NOT_PROVIDED" : only(values)
end

function fetch_official_schedule()
    temporary_path, temporary_io = mktemp()
    close(temporary_io)
    try
        response = Downloads.request(
            BEA_SCHEDULE_URL;
            headers = [
                "Accept" => "text/html",
                "Accept-Encoding" => "identity",
                "User-Agent" =>
                    "BeforeIT-US-BEA-Schedule-Monitor/1.0",
            ],
            output = temporary_path,
            timeout = FETCH_TIMEOUT_SECONDS,
        )
        response.status == 200 ||
            fail("http.status", "expected 200, found $(response.status)")
        response.url == BEA_SCHEDULE_URL ||
            fail(
            "http.effective_locator",
            "expected $BEA_SCHEDULE_URL, found $(response.url)",
        )
        content_type = _header(response, "content-type")
        startswith(lowercase(content_type), "text/html") ||
            fail(
            "http.content_type",
            "expected text/html, found \"$content_type\"",
        )
        raw_bytes = read(temporary_path)
        length(raw_bytes) <= MAX_RESPONSE_BYTES ||
            fail(
            "http.body",
            "exceeds the $(MAX_RESPONSE_BYTES)-byte snapshot limit",
        )
        isempty(raw_bytes) && fail("http.body", "must not be empty")
        return FetchedSchedule(
            raw_bytes,
            response.status,
            content_type,
            String(response.url),
            _header(response, "date"),
            _header(response, "etag"),
            _header(response, "last-modified"),
        )
    finally
        ispath(temporary_path) && rm(temporary_path)
    end
end

function _timestamp(observed_at_utc)
    observed_at_utc isa DateTime ||
        fail("observed_at_utc", "must be a DateTime interpreted as UTC")
    return Dates.format(observed_at_utc, RFC3339_SECONDS_FORMAT) * "Z"
end

function _atomic_write(path, bytes)
    islink(path) &&
        fail("output", "refuses to replace symbolic link $path")
    if ispath(path)
        isfile(path) ||
            fail("output", "existing target is not a regular file: $path")
        read(path) == bytes ||
            fail("output", "hash-addressed target has different bytes: $path")
        return path
    end

    temporary_path, temporary_io = mktemp(dirname(path))
    try
        write(temporary_io, bytes)
        flush(temporary_io)
        close(temporary_io)
        mv(temporary_path, path)
    finally
        isopen(temporary_io) && close(temporary_io)
        ispath(temporary_path) && rm(temporary_path)
    end
    return path
end

function _metadata_bytes(
        fetched::FetchedSchedule,
        event::ValidatedScheduleEvent,
        raw_filename,
        raw_sha256,
        observed_at_utc,
    )
    metadata = Dict(
        "artifact" => Dict(
            "schema_version" => SNAPSHOT_SCHEMA,
            "status" => SNAPSHOT_STATUS,
            "evidence_class" => event.evidence_class,
            "observed_at_utc" => _timestamp(observed_at_utc),
            "source_locator" => BEA_SCHEDULE_URL,
            "effective_locator" => fetched.effective_locator,
            "http_status" => fetched.http_status,
            "http_content_type" => fetched.content_type,
            "http_response_date" => fetched.response_date,
            "http_etag" => fetched.etag,
            "http_last_modified" => fetched.last_modified,
            "raw_response_filename" => raw_filename,
            "raw_response_sha256" => raw_sha256,
            "raw_response_bytes" => length(fetched.raw_bytes),
            "digest_algorithm" => "sha256",
            "metadata_addressing" =>
                "SHA256_OF_EXACT_METADATA_TOML_BYTES_IN_FILENAME",
            "persistence_scope" =>
                "CALLER_SUPPLIED_OUTPUT_ONLY_NO_PERMANENCE_OR_AVAILABILITY_CLAIM",
            "schedule_is_mutable" => true,
            "release_bytes_included" => false,
            "release_event_evidence" => false,
            "origin_availability_evidence" => false,
            "origin_admissible" => false,
            "inventory_mutated" => false,
            "admission_mutated" => false,
            "ready" => false,
        ),
        "validated_event" => Dict(
            "date_text" => event.date_text,
            "time_text" => event.time_text,
            "title" => event.title,
            "strict_match_count" => event.match_count,
            "validation_status" => "EXPECTED_MUTABLE_SCHEDULE_ROW_PRESENT",
            "release_evidence" => event.release_evidence,
            "origin_evidence" => event.origin_evidence,
            "origin_admissible" => event.origin_admissible,
        ),
    )
    io = IOBuffer()
    TOML.print(io, metadata; sorted = true)
    write(io, '\n')
    return take!(io)
end

function write_validated_snapshot(
        output_dir,
        fetched::FetchedSchedule;
        observed_at_utc = now(UTC),
    )
    output_path = abspath(String(output_dir))
    isdir(output_path) ||
        fail("output_dir", "must be an existing directory: $output_path")
    islink(output_path) &&
        fail("output_dir", "must not be a symbolic link: $output_path")
    fetched.http_status == 200 ||
        fail("http.status", "expected 200, found $(fetched.http_status)")
    fetched.effective_locator == BEA_SCHEDULE_URL ||
        fail(
        "http.effective_locator",
        "expected $BEA_SCHEDULE_URL, found $(fetched.effective_locator)",
    )
    startswith(lowercase(fetched.content_type), "text/html") ||
        fail(
        "http.content_type",
        "expected text/html, found \"$(fetched.content_type)\"",
    )

    event = validate_expected_event(fetched.raw_bytes)
    raw_sha256 = sha256_hex(fetched.raw_bytes)
    raw_filename = "bea-schedule-raw-sha256-$raw_sha256.html"
    metadata_bytes = _metadata_bytes(
        fetched,
        event,
        raw_filename,
        raw_sha256,
        observed_at_utc,
    )
    metadata_sha256 = sha256_hex(metadata_bytes)
    metadata_filename =
        "bea-schedule-metadata-sha256-$metadata_sha256.toml"

    raw_path = joinpath(output_path, raw_filename)
    metadata_path = joinpath(output_path, metadata_filename)
    _atomic_write(raw_path, fetched.raw_bytes)
    _atomic_write(metadata_path, metadata_bytes)
    return (
        raw_path = raw_path,
        raw_sha256 = raw_sha256,
        metadata_path = metadata_path,
        metadata_sha256 = metadata_sha256,
        event = event,
    )
end

function capture_live_snapshot(
        output_dir;
        observed_at_utc = now(UTC),
        fetcher = fetch_official_schedule,
    )
    fetched = fetcher()
    fetched isa FetchedSchedule ||
        fail("fetcher", "must return FetchedSchedule")
    return write_validated_snapshot(
        output_dir,
        fetched;
        observed_at_utc = observed_at_utc,
    )
end

end
