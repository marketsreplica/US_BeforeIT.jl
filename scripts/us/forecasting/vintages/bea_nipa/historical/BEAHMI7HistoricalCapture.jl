module BEAHMI7HistoricalCapture

using Dates
using Downloads
using SHA
using TOML

export BEAHMI7HistoricalCaptureError,
    CaptureExpectation,
    FetchedWorkbook,
    WorkbookExpectation,
    EXPECTATIONS,
    capture_present_day,
    expectation_for,
    fetch_official_pair,
    pair_sha256,
    receipt_file_sha256,
    receipt_sha256,
    validate_capture_bundle,
    validate_fetched_pair

const SCHEMA_VERSION =
    "beforeit-us-bea-hmi7-historical-present-day-capture.v1"
const CANONICALIZATION =
    "sorted-toml-with-artifact-receipt-sha256-omitted.v1"
const DIGEST_ALGORITHM = "sha256"
const PAIR_HASH_DOMAIN =
    "beforeit-us-bea-hmi7-historical-pair-sha256.v1"
const SOURCE_AGENCY = "U.S. Bureau of Economic Analysis"
const SOURCE_ATTRIBUTION =
    "Source: U.S. Bureau of Economic Analysis"
const TERMS_LOCATOR = "https://www.bea.gov/index.php/help/faq/145"
const TERMS_REVIEW_STATUS =
    "REVIEWED_AS_OF_CAPTURE_LOCAL_DATE_RECHECK_BEFORE_EACH_LIVE_CAPTURE"
const LOGO_REUSE_AUTHORIZED = false
const STORAGE_MODE =
    "ATOMIC_CONTENT_ADDRESSED_EXACT_SECTION_PAIR_WITH_SELF_HASHED_RECEIPT"
const CAPTURE_METHOD =
    "DIRECT_OFFICIAL_HTTPS_GET_ACCEPT_ENCODING_IDENTITY"
const WORKBOOK_SNAPSHOT_STATUS =
    "HMI7_NEXT_DAY_MONTHLY_TABLE_SNAPSHOT_NOT_EXACT_RELEASE_TIME_CAPTURE"
const FIRST_STATE_STATUS = "UNKNOWN_NOT_ESTABLISHED"
const AVAILABILITY_STATUS = "UNKNOWN_NOT_ESTABLISHED"
const XLSX_CONTENT_TYPE =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
const USER_AGENT =
    "BeforeIT-US-BEA-HMI7-Historical-Capture/1.0"
const MAX_WORKBOOK_BYTES = 25_000_000
const FETCH_TIMEOUT_SECONDS = 120
const MAX_SERVER_CLOCK_SKEW_SECONDS = 300
const XLSX_MAGIC = UInt8[0x50, 0x4b, 0x03, 0x04]
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const ID_PATTERN = r"^[a-z0-9][a-z0-9._-]*$"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
const RFC3339_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"
const HTTP_DATE_PATTERN =
    r"^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$"
const HTTP_DATE_CORE_FORMAT = dateformat"dd u yyyy HH:MM:SS"

struct BEAHMI7HistoricalCaptureError <: Exception
    message::String
end

Base.showerror(io::IO, error::BEAHMI7HistoricalCaptureError) =
    print(io, error.message)

fail(location, message) =
    throw(BEAHMI7HistoricalCaptureError("$location: $message"))

struct WorkbookExpectation
    section_id::String
    filename::String
    source_url::String
    expected_raw_sha256::String
    expected_byte_count::Int
    expected_etag::String
    expected_last_modified::String
end

struct CaptureExpectation
    capture_id::String
    reference_period::String
    estimate_label::String
    archive_directory_id::String
    archive_relative_path::String
    release_number::String
    release_page_url::String
    release_event_timestamp_utc::String
    annual_update_caveat::String
    workbooks::NTuple{2, WorkbookExpectation}
end

struct FetchedWorkbook
    raw_bytes::Vector{UInt8}
    http_status::Int
    content_type::String
    content_length::String
    requested_url::String
    effective_url::String
    response_date::String
    etag::String
    last_modified::String
    acquisition_started_at_utc::DateTime
    response_returned_at_utc::DateTime
    acquisition_completed_at_utc::DateTime
end

const EXPECTATIONS = (
    CaptureExpectation(
        "bea_hmi7_2019q4_advance_monthly_snapshot",
        "2019Q4",
        "advance",
        "13075",
        "Files/Releases/GDP_and_PI/2019/Q4/Advance_January-31-2020",
        "BEA 20-04",
        "https://www.bea.gov/news/2020/gross-domestic-product-fourth-quarter-and-year-2019-advance-estimate",
        "2020-01-30T13:30:00.000Z",
        "NOT_AN_ANNUAL_UPDATE_RELEASE",
        (
            WorkbookExpectation(
                "1",
                "Section1all_xls.xlsx",
                "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2019/Q4/Advance_January-31-2020/Section1all_xls.xlsx",
                "35b170c5c82980a0dfea5cb6db45f2851fc3a3e4dfbbb37773ec71f23b44501a",
                3_743_559,
                "\"028598044d8d51:0\"",
                "Fri, 31 Jan 2020 14:41:20 GMT",
            ),
            WorkbookExpectation(
                "2",
                "Section2all_xls.xlsx",
                "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2019/Q4/Advance_January-31-2020/Section2all_xls.xlsx",
                "8f3935eb2ae44fea9066cdac632f38b858cfbd74731756db2461123726fb6028",
                1_759_752,
                "\"028598044d8d51:0\"",
                "Fri, 31 Jan 2020 14:41:20 GMT",
            ),
        ),
    ),
    CaptureExpectation(
        "bea_hmi7_2021q2_advance_annual_update_monthly_snapshot",
        "2021Q2",
        "advance",
        "13091",
        "Files/Releases/GDP_and_PI/2021/Q2/Advance_July-30-2021",
        "BEA 21-36",
        "https://www.bea.gov/news/2021/gross-domestic-product-second-quarter-2021-advance-estimate-and-annual-update",
        "2021-07-29T12:30:00.000Z",
        "THIS_RELEASE_INCLUDES_THE_2021_ANNUAL_UPDATE_AND_REVISED_HISTORY_MUST_NOT_BE_TREATED_AS_A_STANDARD_WITHIN_DEFINITION_VINTAGE",
        (
            WorkbookExpectation(
                "1",
                "Section1all_xls.xlsx",
                "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2021/Q2/Advance_July-30-2021/Section1all_xls.xlsx",
                "ccc7a5cf63de4022613404d05bcb2a0a1689875d5c45bcc5f3386ae09eec9ffb",
                3_816_200,
                "\"06d24644785d71:0\"",
                "Fri, 30 Jul 2021 13:32:50 GMT",
            ),
            WorkbookExpectation(
                "2",
                "Section2all_xls.xlsx",
                "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2021/Q2/Advance_July-30-2021/Section2all_xls.xlsx",
                "84dff5de137cd3043e0392798875c1bb80a9190c4bddfdb76f495163cdf1ff9a",
                1_784_998,
                "\"06d24644785d71:0\"",
                "Fri, 30 Jul 2021 13:32:50 GMT",
            ),
        ),
    ),
)

const EXPECTATION_BY_ID =
    Dict(expectation.capture_id => expectation for expectation in EXPECTATIONS)

const TOP_LEVEL_KEYS = Set(
    [
        "artifact",
        "capture_scope",
        "release_event",
        "workbook_snapshot_boundary",
        "terms",
        "capture",
        "raw_bundle",
        "workbooks",
        "gates",
    ],
)
const ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "receipt_id",
        "canonicalization",
        "digest_algorithm",
        "receipt_sha256",
        "immutable_bundle",
    ],
)
const CAPTURE_SCOPE_KEYS = Set(
    [
        "capture_id",
        "reference_period",
        "estimate_label",
        "archive_directory_id",
        "archive_relative_path",
        "directory_id_locator",
        "resolved_path_locator",
        "source_agency",
        "source_attribution",
    ],
)
const RELEASE_EVENT_KEYS = Set(
    [
        "release_number",
        "release_page_url",
        "release_event_timestamp_utc",
        "release_event_is_workbook_snapshot",
    ],
)
const SNAPSHOT_BOUNDARY_KEYS = Set(
    [
        "status",
        "monthly_table_snapshot_is_next_calendar_day",
        "exact_release_time_capture",
        "historical_first_state_status",
        "historical_availability_status",
        "annual_update_caveat",
        "archive_label_date_is_availability_evidence",
        "current_http_headers_are_historical_availability_evidence",
    ],
)
const TERMS_KEYS = Set(
    [
        "terms_locator",
        "terms_reviewed_local_date",
        "terms_review_status",
        "source_attribution",
        "bea_logo_reuse_authorized",
        "redistribution_authorized_by_capture_contract",
    ],
)
const CAPTURE_KEYS = Set(
    [
        "capture_method",
        "capture_started_at_utc",
        "capture_completed_at_utc",
        "capture_local_date",
        "present_day_retrieval_only",
    ],
)
const RAW_BUNDLE_KEYS = Set(
    [
        "pair_sha256",
        "storage_mode",
        "storage_encoding",
        "expected_file_count",
    ],
)
const WORKBOOK_KEYS = Set(
    [
        "section_id",
        "filename",
        "source_url",
        "effective_url",
        "expected_raw_sha256",
        "expected_byte_count",
        "observed_raw_sha256",
        "observed_byte_count",
        "expected_etag",
        "observed_etag",
        "expected_last_modified",
        "observed_last_modified",
        "http_status",
        "content_type",
        "content_length_header",
        "response_date",
        "response_date_max_clock_skew_seconds",
        "acquisition_started_at_utc",
        "response_returned_at_utc",
        "acquisition_completed_at_utc",
        "xlsx_zip_magic_verified",
        "raw_object_relative_path",
    ],
)
const GATE_KEYS = Set(
    [
        "historical_first_state_verified",
        "historical_availability_verified",
        "origin_admissible",
        "empirical_execution_allowed",
        "inventory_mutation_authorized",
        "production_authorized",
        "ready",
    ],
)

sha256_hex(bytes::AbstractVector{UInt8}) =
    bytes2hex(SHA.sha256(bytes))

function _expect_exact_keys(table, expected, location)
    table isa AbstractDict || fail(location, "must be a table")
    actual = Set(String(key) for key in keys(table))
    actual == expected ||
        fail(
        location,
        "keys must equal $(sort!(collect(expected))); found $(sort!(collect(actual)))",
    )
    return table
end

function _expect_string(value, location)
    value isa String || fail(location, "must be a string")
    isempty(value) && fail(location, "must not be empty")
    return value
end

function _expect_hash(value, location)
    text = _expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be a lowercase SHA-256")
    return text
end

function _expect_false(value, location)
    value === false || fail(location, "must be false")
    return false
end

function _expect_true(value, location)
    value === true || fail(location, "must be true")
    return true
end

function _expect_equal(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), found $(repr(value))")
    return value
end

function _timestamp(value, location)
    text = _expect_string(value, location)
    occursin(RFC3339_PATTERN, text) ||
        fail(location, "must be UTC RFC3339 with millisecond precision")
    return try
        DateTime(chop(text; tail = 1), RFC3339_SECONDS_FORMAT)
    catch error
        fail(location, "is invalid ($(sprint(showerror, error)))")
    end
end

format_timestamp(value::DateTime) =
    Dates.format(value, RFC3339_SECONDS_FORMAT) * "Z"

function _http_date(value, location)
    text = _expect_string(value, location)
    occursin(HTTP_DATE_PATTERN, text) ||
        fail(location, "must be a canonical IMF-fixdate in GMT")
    core = text[6:(end - 4)]
    parsed = try
        DateTime(core, HTTP_DATE_CORE_FORMAT)
    catch error
        fail(location, "is not a valid IMF-fixdate ($(sprint(showerror, error)))")
    end
    expected =
        dayabbr(parsed) *
        ", " *
        Dates.format(parsed, HTTP_DATE_CORE_FORMAT) *
        " GMT"
    text == expected ||
        fail(location, "weekday or canonical representation is inconsistent")
    return parsed
end

function expectation_for(capture_id::AbstractString)
    id = String(capture_id)
    haskey(EXPECTATION_BY_ID, id) ||
        fail("capture_id", "is not one of the two sealed historical pilots")
    return EXPECTATION_BY_ID[id]
end

function _directory_id_locator(expectation)
    archive_prefix = "Files/Releases/GDP_and_PI/"
    startswith(expectation.archive_relative_path, archive_prefix) ||
        fail("archive_relative_path", "has an invalid discovery root")
    suffix = expectation.archive_relative_path[
        nextind(
            expectation.archive_relative_path,
            lastindex(archive_prefix),
        ):end,
    ]
    encoded_suffix = replace(suffix, "/" => "%5C")
    return "https://apps.bea.gov/histdata/core/data/UrlPath_getID/" *
        "?UrlPath=%2FInetpub%2Fwwwroot%2Fwebsite%2Fwebsite%2FHistData%2F" *
        "Files%2FReleases%2FGDP_and_PI%5C" *
        encoded_suffix
end

function _resolved_path_locator(expectation)
    return "https://apps.bea.gov/histdata/core/data/getPath/" *
        expectation.archive_directory_id
end

function _validate_expectation(expectation, location)
    expectation isa CaptureExpectation ||
        fail(location, "must be a CaptureExpectation")
    occursin(ID_PATTERN, expectation.capture_id) ||
        fail("$location.capture_id", "must be a canonical identifier")
    occursin(r"^\d{4}Q[1-4]$", expectation.reference_period) ||
        fail("$location.reference_period", "must be YYYYQn")
    expectation.estimate_label == "advance" ||
        fail("$location.estimate_label", "must equal advance")
    occursin(r"^[1-9][0-9]*$", expectation.archive_directory_id) ||
        fail("$location.archive_directory_id", "must contain digits")
    startswith(
        expectation.archive_relative_path,
        "Files/Releases/GDP_and_PI/",
    ) ||
        fail("$location.archive_relative_path", "has an invalid root")
    occursin("..", expectation.archive_relative_path) &&
        fail("$location.archive_relative_path", "must not contain traversal")
    _timestamp(
        expectation.release_event_timestamp_utc,
        "$location.release_event_timestamp_utc",
    )
    startswith(expectation.release_page_url, "https://www.bea.gov/news/") ||
        fail("$location.release_page_url", "must use the official BEA news host")
    length(expectation.workbooks) == 2 ||
        fail("$location.workbooks", "must contain exactly two workbooks")
    Set(workbook.section_id for workbook in expectation.workbooks) ==
        Set(["1", "2"]) ||
        fail("$location.workbooks", "must cover Sections 1 and 2 exactly")
    length(unique(workbook.source_url for workbook in expectation.workbooks)) ==
        2 ||
        fail("$location.workbooks", "source URLs must be unique")
    length(
        unique(
            workbook.expected_raw_sha256 for
                workbook in expectation.workbooks
        ),
    ) == 2 ||
        fail("$location.workbooks", "raw hash aliases are forbidden")
    for (index, workbook) in enumerate(expectation.workbooks)
        prefix =
            "https://apps.bea.gov/HistData/" *
            expectation.archive_relative_path *
            "/"
        workbook.section_id == string(index) ||
            fail(
            "$location.workbooks[$index].section_id",
            "must be in canonical Section 1, Section 2 order",
        )
        workbook.filename == "Section$(index)all_xls.xlsx" ||
            fail("$location.workbooks[$index].filename", "is not canonical")
        workbook.source_url == prefix * workbook.filename ||
            fail(
            "$location.workbooks[$index].source_url",
            "does not match the bound archive path",
        )
        _expect_hash(
            workbook.expected_raw_sha256,
            "$location.workbooks[$index].expected_raw_sha256",
        )
        0 < workbook.expected_byte_count <= MAX_WORKBOOK_BYTES ||
            fail(
            "$location.workbooks[$index].expected_byte_count",
            "is outside the accepted range",
        )
        occursin(r"^\"[0-9a-f]+:[0-9]+\"$", workbook.expected_etag) ||
            fail("$location.workbooks[$index].expected_etag", "is invalid")
        _http_date(
            workbook.expected_last_modified,
            "$location.workbooks[$index].expected_last_modified",
        )
    end
    return expectation
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

function _base_content_type(value)
    return lowercase(strip(first(split(String(value), ';'; limit = 2))))
end

function _has_xlsx_magic(bytes)
    return length(bytes) >= length(XLSX_MAGIC) &&
        bytes[1:length(XLSX_MAGIC)] == XLSX_MAGIC
end

function _enforce_download_limit(dl_total, dl_now, ul_total, ul_now)
    for (name, value) in (
            "download total" => dl_total,
            "download current" => dl_now,
            "upload total" => ul_total,
            "upload current" => ul_now,
        )
        value isa Integer ||
            fail("http.progress.$name", "must be an integer")
        value >= 0 ||
            fail("http.progress.$name", "must be nonnegative")
    end
    dl_total <= MAX_WORKBOOK_BYTES ||
        fail("http.body", "advertised size exceeds the workbook byte limit")
    dl_now <= MAX_WORKBOOK_BYTES ||
        fail("http.body", "download exceeds the workbook byte limit")
    ul_total == 0 ||
        fail("http.upload", "must remain empty for a GET capture")
    ul_now == 0 ||
        fail("http.upload", "must remain empty for a GET capture")
    return nothing
end

function _validated_content_length(value, location)
    text = _expect_string(value, location)
    occursin(r"^[1-9][0-9]*$", text) ||
        fail(location, "must be a positive canonical integer")
    count = tryparse(Int, text)
    count === nothing && fail(location, "does not fit in an Int")
    return count
end

function _validate_fetched_workbook(
        fetched::FetchedWorkbook,
        expectation::WorkbookExpectation;
        location,
    )
    fetched.http_status == 200 ||
        fail("$location.http_status", "must equal 200")
    fetched.requested_url == expectation.source_url ||
        fail("$location.requested_url", "does not match expectation")
    fetched.effective_url == expectation.source_url ||
        fail("$location.effective_url", "redirects are not accepted")
    _base_content_type(fetched.content_type) == XLSX_CONTENT_TYPE ||
        fail("$location.content_type", "must be the XLSX media type")
    _validated_content_length(
        fetched.content_length,
        "$location.content_length",
    ) == length(fetched.raw_bytes) ||
        fail("$location.content_length", "does not equal body byte count")
    length(fetched.raw_bytes) == expectation.expected_byte_count ||
        fail("$location.raw_bytes", "byte count does not match expectation")
    _has_xlsx_magic(fetched.raw_bytes) ||
        fail("$location.raw_bytes", "does not begin with OOXML ZIP magic")
    digest = sha256_hex(fetched.raw_bytes)
    digest == expectation.expected_raw_sha256 ||
        fail("$location.raw_bytes", "SHA-256 does not match expectation")
    fetched.etag == expectation.expected_etag ||
        fail("$location.etag", "does not match the pinned present-day header")
    fetched.last_modified == expectation.expected_last_modified ||
        fail(
        "$location.last_modified",
        "does not match the pinned present-day header",
    )
    server_date =
        _http_date(fetched.response_date, "$location.response_date")
    fetched.acquisition_started_at_utc <=
        fetched.response_returned_at_utc <=
        fetched.acquisition_completed_at_utc ||
        fail("$location.timestamps", "are not ordered")
    skew = Second(MAX_SERVER_CLOCK_SKEW_SECONDS)
    fetched.acquisition_started_at_utc - skew <= server_date <=
        fetched.response_returned_at_utc + skew ||
        fail(
        "$location.response_date",
        "lies outside the sealed server/local clock-skew bound",
    )
    return (
        raw_sha256 = digest,
        raw_byte_count = length(fetched.raw_bytes),
    )
end

function validate_fetched_pair(
        fetched_workbooks,
        expectation::CaptureExpectation,
    )
    _validate_expectation(expectation, "expectation")
    fetched_workbooks isa AbstractVector ||
        fail("workbooks", "must be a vector")
    length(fetched_workbooks) == 2 ||
        fail("workbooks", "must contain the complete two-workbook pair")
    length(unique(objectid(fetched) for fetched in fetched_workbooks)) == 2 ||
        fail("workbooks", "object aliases are forbidden")
    results = [
        _validate_fetched_workbook(
                fetched,
                workbook;
                location = "workbooks[$index]",
            )
            for (index, (fetched, workbook)) in
            enumerate(zip(fetched_workbooks, expectation.workbooks))
    ]
    length(unique(result.raw_sha256 for result in results)) == 2 ||
        fail("workbooks", "raw-byte hash aliases are forbidden")
    return results
end

function _hash_field!(io, name, value)
    name_bytes = Vector{UInt8}(codeunits(String(name)))
    value_bytes = Vector{UInt8}(codeunits(string(value)))
    write(io, string(length(name_bytes)), ':', name_bytes)
    write(io, string(length(value_bytes)), ':', value_bytes)
    return io
end

function pair_sha256(
        fetched_workbooks,
        expectation::CaptureExpectation,
    )
    results = validate_fetched_pair(fetched_workbooks, expectation)
    io = IOBuffer()
    _hash_field!(io, "domain", PAIR_HASH_DOMAIN)
    _hash_field!(io, "capture_id", expectation.capture_id)
    for (index, (result, workbook)) in
        enumerate(zip(results, expectation.workbooks))
        _hash_field!(io, "workbook_index", index)
        _hash_field!(io, "section_id", workbook.section_id)
        _hash_field!(io, "source_url", workbook.source_url)
        _hash_field!(io, "raw_sha256", result.raw_sha256)
        _hash_field!(io, "raw_byte_count", result.raw_byte_count)
    end
    return sha256_hex(take!(io))
end

function fetch_official_workbook(expectation::WorkbookExpectation)
    temporary_path, temporary_io = mktemp()
    close(temporary_io)
    try
        started = now(UTC)
        response = Downloads.request(
            expectation.source_url;
            headers = [
                "Accept" => XLSX_CONTENT_TYPE,
                "Accept-Encoding" => "identity",
                "User-Agent" => USER_AGENT,
            ],
            output = temporary_path,
            timeout = FETCH_TIMEOUT_SECONDS,
            progress = _enforce_download_limit,
        )
        returned_at = now(UTC)
        bytes = read(temporary_path)
        completed = now(UTC)
        length(bytes) <= MAX_WORKBOOK_BYTES ||
            fail("http.body", "exceeds the workbook byte limit")
        effective_url = String(response.url)
        return FetchedWorkbook(
            bytes,
            response.status,
            _header(response, "content-type"),
            _header(response, "content-length"),
            expectation.source_url,
            effective_url,
            _header(response, "date"),
            _header(response, "etag"),
            _header(response, "last-modified"),
            started,
            returned_at,
            completed,
        )
    finally
        ispath(temporary_path) && rm(temporary_path)
    end
end

function fetch_official_pair(expectation::CaptureExpectation)
    _validate_expectation(expectation, "expectation")
    fetched = FetchedWorkbook[
        fetch_official_workbook(workbook) for
            workbook in expectation.workbooks
    ]
    validate_fetched_pair(fetched, expectation)
    return fetched
end

function _receipt_without_hash(document)
    copy = deepcopy(document)
    artifact = copy["artifact"]
    delete!(artifact, "receipt_sha256")
    return copy
end

function _toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    bytes = take!(io)
    isempty(bytes) && fail("receipt serialization", "must not be empty")
    bytes[end] == UInt8('\n') || push!(bytes, UInt8('\n'))
    return bytes
end

function receipt_sha256(document)
    document isa AbstractDict ||
        fail("receipt", "must be a parsed TOML table")
    return sha256_hex(_toml_bytes(_receipt_without_hash(document)))
end

receipt_file_sha256(document) = sha256_hex(_toml_bytes(document))

function _raw_filename(workbook)
    return "section-$(workbook.section_id)-raw-sha256-" *
        workbook.expected_raw_sha256 *
        ".xlsx"
end

function _build_receipt(
        expectation::CaptureExpectation,
        fetched_workbooks;
        capture_started_at_utc::DateTime,
        capture_completed_at_utc::DateTime,
        capture_local_date::Date,
        terms_reviewed_local_date::Date,
    )
    results = validate_fetched_pair(fetched_workbooks, expectation)
    capture_started_at_utc <= capture_completed_at_utc ||
        fail("capture.timestamps", "are not ordered")
    terms_reviewed_local_date == capture_local_date ||
        fail(
        "terms_reviewed_local_date",
        "must equal the capture host-local date",
    )
    for (index, fetched) in enumerate(fetched_workbooks)
        capture_started_at_utc <= fetched.acquisition_started_at_utc ||
            fail(
            "workbooks[$index].acquisition_started_at_utc",
            "precedes capture start",
        )
        fetched.acquisition_completed_at_utc <= capture_completed_at_utc ||
            fail(
            "workbooks[$index].acquisition_completed_at_utc",
            "follows capture completion",
        )
    end
    pair_digest = pair_sha256(fetched_workbooks, expectation)
    receipt_id =
        expectation.capture_id * "_pair_" * pair_digest[1:16]
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => SCHEMA_VERSION,
            "receipt_id" => receipt_id,
            "canonicalization" => CANONICALIZATION,
            "digest_algorithm" => DIGEST_ALGORITHM,
            "receipt_sha256" => repeat("0", 64),
            "immutable_bundle" => true,
        ),
        "capture_scope" => Dict{String, Any}(
            "capture_id" => expectation.capture_id,
            "reference_period" => expectation.reference_period,
            "estimate_label" => expectation.estimate_label,
            "archive_directory_id" => expectation.archive_directory_id,
            "archive_relative_path" => expectation.archive_relative_path,
            "directory_id_locator" => _directory_id_locator(expectation),
            "resolved_path_locator" => _resolved_path_locator(expectation),
            "source_agency" => SOURCE_AGENCY,
            "source_attribution" => SOURCE_ATTRIBUTION,
        ),
        "release_event" => Dict{String, Any}(
            "release_number" => expectation.release_number,
            "release_page_url" => expectation.release_page_url,
            "release_event_timestamp_utc" =>
                expectation.release_event_timestamp_utc,
            "release_event_is_workbook_snapshot" => false,
        ),
        "workbook_snapshot_boundary" => Dict{String, Any}(
            "status" => WORKBOOK_SNAPSHOT_STATUS,
            "monthly_table_snapshot_is_next_calendar_day" => true,
            "exact_release_time_capture" => false,
            "historical_first_state_status" => FIRST_STATE_STATUS,
            "historical_availability_status" => AVAILABILITY_STATUS,
            "annual_update_caveat" => expectation.annual_update_caveat,
            "archive_label_date_is_availability_evidence" => false,
            "current_http_headers_are_historical_availability_evidence" =>
                false,
        ),
        "terms" => Dict{String, Any}(
            "terms_locator" => TERMS_LOCATOR,
            "terms_reviewed_local_date" =>
                string(terms_reviewed_local_date),
            "terms_review_status" => TERMS_REVIEW_STATUS,
            "source_attribution" => SOURCE_ATTRIBUTION,
            "bea_logo_reuse_authorized" => LOGO_REUSE_AUTHORIZED,
            "redistribution_authorized_by_capture_contract" => false,
        ),
        "capture" => Dict{String, Any}(
            "capture_method" => CAPTURE_METHOD,
            "capture_started_at_utc" =>
                format_timestamp(capture_started_at_utc),
            "capture_completed_at_utc" =>
                format_timestamp(capture_completed_at_utc),
            "capture_local_date" => string(capture_local_date),
            "present_day_retrieval_only" => true,
        ),
        "raw_bundle" => Dict{String, Any}(
            "pair_sha256" => pair_digest,
            "storage_mode" => STORAGE_MODE,
            "storage_encoding" => "identity",
            "expected_file_count" => 3,
        ),
        "workbooks" => [
            Dict{String, Any}(
                    "section_id" => workbook.section_id,
                    "filename" => workbook.filename,
                    "source_url" => workbook.source_url,
                    "effective_url" => fetched.effective_url,
                    "expected_raw_sha256" =>
                    workbook.expected_raw_sha256,
                    "expected_byte_count" =>
                    workbook.expected_byte_count,
                    "observed_raw_sha256" => result.raw_sha256,
                    "observed_byte_count" => result.raw_byte_count,
                    "expected_etag" => workbook.expected_etag,
                    "observed_etag" => fetched.etag,
                    "expected_last_modified" =>
                    workbook.expected_last_modified,
                    "observed_last_modified" => fetched.last_modified,
                    "http_status" => fetched.http_status,
                    "content_type" => fetched.content_type,
                    "content_length_header" => fetched.content_length,
                    "response_date" => fetched.response_date,
                    "response_date_max_clock_skew_seconds" =>
                    MAX_SERVER_CLOCK_SKEW_SECONDS,
                    "acquisition_started_at_utc" =>
                    format_timestamp(
                        fetched.acquisition_started_at_utc,
                    ),
                    "response_returned_at_utc" =>
                    format_timestamp(fetched.response_returned_at_utc),
                    "acquisition_completed_at_utc" =>
                    format_timestamp(
                        fetched.acquisition_completed_at_utc,
                    ),
                    "xlsx_zip_magic_verified" => true,
                    "raw_object_relative_path" => _raw_filename(workbook),
                )
                for (workbook, fetched, result) in
                zip(expectation.workbooks, fetched_workbooks, results)
        ],
        "gates" => Dict{String, Any}(
            "historical_first_state_verified" => false,
            "historical_availability_verified" => false,
            "origin_admissible" => false,
            "empirical_execution_allowed" => false,
            "inventory_mutation_authorized" => false,
            "production_authorized" => false,
            "ready" => false,
        ),
    )
    document["artifact"]["receipt_sha256"] = receipt_sha256(document)
    return document
end

function _validate_receipt(
        document,
        expectation::CaptureExpectation;
        location = "receipt",
    )
    _validate_expectation(expectation, "expectation")
    _expect_exact_keys(document, TOP_LEVEL_KEYS, location)

    artifact = _expect_exact_keys(
        document["artifact"],
        ARTIFACT_KEYS,
        "$location.artifact",
    )
    _expect_equal(
        artifact["schema_version"],
        SCHEMA_VERSION,
        "$location.artifact.schema_version",
    )
    _expect_equal(
        artifact["canonicalization"],
        CANONICALIZATION,
        "$location.artifact.canonicalization",
    )
    _expect_equal(
        artifact["digest_algorithm"],
        DIGEST_ALGORITHM,
        "$location.artifact.digest_algorithm",
    )
    _expect_true(
        artifact["immutable_bundle"],
        "$location.artifact.immutable_bundle",
    )
    _expect_hash(
        artifact["receipt_sha256"],
        "$location.artifact.receipt_sha256",
    )
    _expect_equal(
        artifact["receipt_sha256"],
        receipt_sha256(document),
        "$location.artifact.receipt_sha256",
    )

    scope = _expect_exact_keys(
        document["capture_scope"],
        CAPTURE_SCOPE_KEYS,
        "$location.capture_scope",
    )
    for (key, expected) in (
            "capture_id" => expectation.capture_id,
            "reference_period" => expectation.reference_period,
            "estimate_label" => expectation.estimate_label,
            "archive_directory_id" => expectation.archive_directory_id,
            "archive_relative_path" => expectation.archive_relative_path,
            "directory_id_locator" => _directory_id_locator(expectation),
            "resolved_path_locator" => _resolved_path_locator(expectation),
            "source_agency" => SOURCE_AGENCY,
            "source_attribution" => SOURCE_ATTRIBUTION,
        )
        _expect_equal(
            scope[key],
            expected,
            "$location.capture_scope.$key",
        )
    end
    _expect_equal(
        artifact["receipt_id"],
        expectation.capture_id *
            "_pair_" *
            document["raw_bundle"]["pair_sha256"][1:16],
        "$location.artifact.receipt_id",
    )

    event = _expect_exact_keys(
        document["release_event"],
        RELEASE_EVENT_KEYS,
        "$location.release_event",
    )
    for (key, expected) in (
            "release_number" => expectation.release_number,
            "release_page_url" => expectation.release_page_url,
            "release_event_timestamp_utc" =>
                expectation.release_event_timestamp_utc,
        )
        _expect_equal(event[key], expected, "$location.release_event.$key")
    end
    _expect_false(
        event["release_event_is_workbook_snapshot"],
        "$location.release_event.release_event_is_workbook_snapshot",
    )

    boundary = _expect_exact_keys(
        document["workbook_snapshot_boundary"],
        SNAPSHOT_BOUNDARY_KEYS,
        "$location.workbook_snapshot_boundary",
    )
    for (key, expected) in (
            "status" => WORKBOOK_SNAPSHOT_STATUS,
            "historical_first_state_status" => FIRST_STATE_STATUS,
            "historical_availability_status" => AVAILABILITY_STATUS,
            "annual_update_caveat" => expectation.annual_update_caveat,
        )
        _expect_equal(
            boundary[key],
            expected,
            "$location.workbook_snapshot_boundary.$key",
        )
    end
    _expect_true(
        boundary["monthly_table_snapshot_is_next_calendar_day"],
        "$location.workbook_snapshot_boundary.monthly_table_snapshot_is_next_calendar_day",
    )
    for key in (
            "exact_release_time_capture",
            "archive_label_date_is_availability_evidence",
            "current_http_headers_are_historical_availability_evidence",
        )
        _expect_false(
            boundary[key],
            "$location.workbook_snapshot_boundary.$key",
        )
    end

    terms = _expect_exact_keys(
        document["terms"],
        TERMS_KEYS,
        "$location.terms",
    )
    for (key, expected) in (
            "terms_locator" => TERMS_LOCATOR,
            "terms_review_status" => TERMS_REVIEW_STATUS,
            "source_attribution" => SOURCE_ATTRIBUTION,
        )
        _expect_equal(terms[key], expected, "$location.terms.$key")
    end
    _expect_false(
        terms["bea_logo_reuse_authorized"],
        "$location.terms.bea_logo_reuse_authorized",
    )
    _expect_false(
        terms["redistribution_authorized_by_capture_contract"],
        "$location.terms.redistribution_authorized_by_capture_contract",
    )

    capture = _expect_exact_keys(
        document["capture"],
        CAPTURE_KEYS,
        "$location.capture",
    )
    _expect_equal(
        capture["capture_method"],
        CAPTURE_METHOD,
        "$location.capture.capture_method",
    )
    _expect_true(
        capture["present_day_retrieval_only"],
        "$location.capture.present_day_retrieval_only",
    )
    capture_started = _timestamp(
        capture["capture_started_at_utc"],
        "$location.capture.capture_started_at_utc",
    )
    capture_completed = _timestamp(
        capture["capture_completed_at_utc"],
        "$location.capture.capture_completed_at_utc",
    )
    capture_started <= capture_completed ||
        fail("$location.capture", "timestamps are not ordered")
    capture_date = tryparse(Date, capture["capture_local_date"])
    capture_date === nothing ||
        string(capture_date) != capture["capture_local_date"] ?
        fail("$location.capture.capture_local_date", "must be YYYY-MM-DD") :
        nothing
    _expect_equal(
        terms["terms_reviewed_local_date"],
        capture["capture_local_date"],
        "$location.terms.terms_reviewed_local_date",
    )

    raw_bundle = _expect_exact_keys(
        document["raw_bundle"],
        RAW_BUNDLE_KEYS,
        "$location.raw_bundle",
    )
    _expect_hash(
        raw_bundle["pair_sha256"],
        "$location.raw_bundle.pair_sha256",
    )
    _expect_equal(
        raw_bundle["storage_mode"],
        STORAGE_MODE,
        "$location.raw_bundle.storage_mode",
    )
    _expect_equal(
        raw_bundle["storage_encoding"],
        "identity",
        "$location.raw_bundle.storage_encoding",
    )
    _expect_equal(
        raw_bundle["expected_file_count"],
        3,
        "$location.raw_bundle.expected_file_count",
    )

    workbooks = document["workbooks"]
    workbooks isa AbstractVector ||
        fail("$location.workbooks", "must be an array of tables")
    length(workbooks) == 2 ||
        fail("$location.workbooks", "must contain the complete pair")
    for (index, (workbook, expected)) in
        enumerate(zip(workbooks, expectation.workbooks))
        _expect_exact_keys(
            workbook,
            WORKBOOK_KEYS,
            "$location.workbooks[$index]",
        )
        for (key, expected_value) in (
                "section_id" => expected.section_id,
                "filename" => expected.filename,
                "source_url" => expected.source_url,
                "effective_url" => expected.source_url,
                "expected_raw_sha256" => expected.expected_raw_sha256,
                "expected_byte_count" => expected.expected_byte_count,
                "observed_raw_sha256" => expected.expected_raw_sha256,
                "observed_byte_count" => expected.expected_byte_count,
                "expected_etag" => expected.expected_etag,
                "observed_etag" => expected.expected_etag,
                "expected_last_modified" =>
                    expected.expected_last_modified,
                "observed_last_modified" =>
                    expected.expected_last_modified,
                "http_status" => 200,
                "raw_object_relative_path" => _raw_filename(expected),
            )
            _expect_equal(
                workbook[key],
                expected_value,
                "$location.workbooks[$index].$key",
            )
        end
        _expect_equal(
            _base_content_type(workbook["content_type"]),
            XLSX_CONTENT_TYPE,
            "$location.workbooks[$index].content_type",
        )
        _expect_equal(
            _validated_content_length(
                workbook["content_length_header"],
                "$location.workbooks[$index].content_length_header",
            ),
            expected.expected_byte_count,
            "$location.workbooks[$index].content_length_header",
        )
        server_date = _http_date(
            workbook["response_date"],
            "$location.workbooks[$index].response_date",
        )
        _expect_equal(
            workbook["response_date_max_clock_skew_seconds"],
            MAX_SERVER_CLOCK_SKEW_SECONDS,
            "$location.workbooks[$index].response_date_max_clock_skew_seconds",
        )
        started = _timestamp(
            workbook["acquisition_started_at_utc"],
            "$location.workbooks[$index].acquisition_started_at_utc",
        )
        returned_at = _timestamp(
            workbook["response_returned_at_utc"],
            "$location.workbooks[$index].response_returned_at_utc",
        )
        completed = _timestamp(
            workbook["acquisition_completed_at_utc"],
            "$location.workbooks[$index].acquisition_completed_at_utc",
        )
        capture_started <= started <= returned_at <= completed <=
            capture_completed ||
            fail(
            "$location.workbooks[$index]",
            "timestamps are not ordered within capture interval",
        )
        skew = Second(MAX_SERVER_CLOCK_SKEW_SECONDS)
        started - skew <= server_date <= returned_at + skew ||
            fail(
            "$location.workbooks[$index].response_date",
            "lies outside the sealed server/local clock-skew bound",
        )
        _expect_true(
            workbook["xlsx_zip_magic_verified"],
            "$location.workbooks[$index].xlsx_zip_magic_verified",
        )
    end

    expected_pair = _pair_sha256_from_receipt(document, expectation)
    _expect_equal(
        raw_bundle["pair_sha256"],
        expected_pair,
        "$location.raw_bundle.pair_sha256",
    )

    gates = _expect_exact_keys(
        document["gates"],
        GATE_KEYS,
        "$location.gates",
    )
    for key in GATE_KEYS
        _expect_false(gates[key], "$location.gates.$key")
    end
    return (
        capture_id = expectation.capture_id,
        receipt_sha256 = artifact["receipt_sha256"],
        pair_sha256 = raw_bundle["pair_sha256"],
        historical_first_state_verified = false,
        historical_availability_verified = false,
        origin_admissible = false,
        empirical_execution_allowed = false,
        inventory_mutation_authorized = false,
        production_authorized = false,
        ready = false,
    )
end

function _pair_sha256_from_receipt(document, expectation)
    io = IOBuffer()
    _hash_field!(io, "domain", PAIR_HASH_DOMAIN)
    _hash_field!(io, "capture_id", expectation.capture_id)
    for (index, (workbook, expected)) in
        enumerate(zip(document["workbooks"], expectation.workbooks))
        _hash_field!(io, "workbook_index", index)
        _hash_field!(io, "section_id", expected.section_id)
        _hash_field!(io, "source_url", expected.source_url)
        _hash_field!(io, "raw_sha256", workbook["observed_raw_sha256"])
        _hash_field!(io, "raw_byte_count", workbook["observed_byte_count"])
    end
    return sha256_hex(take!(io))
end

function _reject_symlink_chain(path, location)
    absolute = abspath(String(path))
    candidate = absolute
    while true
        if ispath(candidate)
            islink(candidate) && fail(location, "must not traverse a symlink")
        end
        parent = dirname(candidate)
        parent == candidate && break
        candidate = parent
    end
    return absolute
end

function _canonical_raw_root(raw_root)
    text = String(raw_root)
    isabspath(text) || fail("raw_root", "must be absolute")
    normpath(text) == text ||
        fail("raw_root", "must be normalized and contain no traversal aliases")
    _reject_symlink_chain(text, "raw_root")
    mkpath(text)
    _reject_symlink_chain(text, "raw_root")
    realpath(text) == text ||
        fail("raw_root", "must be its canonical filesystem path")
    return text
end

function _write_exact(path, bytes)
    ispath(path) && fail("bundle staging", "refuses to overwrite $path")
    open(path, "w") do io
        write(io, bytes)
        flush(io)
    end
    read(path) == bytes ||
        fail("bundle staging", "read-back does not match at $path")
    return path
end

function _receipt_path(bundle_path, receipt_digest)
    return joinpath(
        bundle_path,
        "receipt-self-sha256-$receipt_digest.toml",
    )
end

function _rename_exclusive(source::AbstractString, target::AbstractString)
    result = @static if Sys.isapple()
        ccall(
            :renameatx_np,
            Cint,
            (Cint, Cstring, Cint, Cstring, Cuint),
            Cint(-2),
            String(source),
            Cint(-2),
            String(target),
            Cuint(0x00000004),
        )
    elseif Sys.islinux()
        ccall(
            :renameat2,
            Cint,
            (Cint, Cstring, Cint, Cstring, Cuint),
            Cint(-100),
            String(source),
            Cint(-100),
            String(target),
            Cuint(0x00000001),
        )
    else
        fail(
            "capture storage",
            "this platform has no sealed exclusive-rename implementation",
        )
    end
    result == 0 && return true
    error_number = Base.Libc.errno()
    error_number == Base.Libc.EEXIST && return false
    return fail(
        "capture storage",
        "exclusive directory rename failed with errno $error_number " *
            "($(Base.Libc.strerror(error_number)))",
    )
end

function _validate_capture_bundle(
        bundle_path::AbstractString,
        supplied_expectation::Union{Nothing, CaptureExpectation};
        validate_storage_path::Bool = true,
    )
    path = String(bundle_path)
    isabspath(path) || fail("bundle", "path must be absolute")
    normpath(path) == path ||
        fail("bundle", "path must be normalized")
    _reject_symlink_chain(path, "bundle")
    isdir(path) || fail("bundle", "does not exist as a directory")
    stat(path).mode & 0o222 == 0 ||
        fail("bundle", "directory must be write-protected")
    names = readdir(path; sort = true)
    length(names) == 3 ||
        fail("bundle", "must contain exactly two workbooks and one receipt")
    receipt_names = filter(
        name -> occursin(
            r"^receipt-self-sha256-[0-9a-f]{64}\.toml$",
            name,
        ),
        names,
    )
    length(receipt_names) == 1 ||
        fail("bundle", "must contain exactly one self-hashed receipt")
    receipt_name = only(receipt_names)
    receipt_path = joinpath(path, receipt_name)
    isfile(receipt_path) ||
        fail("bundle.receipt", "must be a regular file")
    islink(receipt_path) &&
        fail("bundle.receipt", "must not be a symbolic link")
    receipt_stat = stat(receipt_path)
    receipt_stat.mode & 0o222 == 0 ||
        fail("bundle.receipt", "must be write-protected")
    receipt_stat.nlink == 1 ||
        fail("bundle.receipt", "hard-link aliases are forbidden")
    receipt_bytes = read(receipt_path)
    document = try
        TOML.parse(String(copy(receipt_bytes)))
    catch error
        fail("bundle.receipt", "is invalid TOML ($(sprint(showerror, error)))")
    end
    receipt_bytes == _toml_bytes(document) ||
        fail("bundle.receipt", "bytes are not canonical receipt TOML")
    scope = get(document, "capture_scope", nothing)
    scope isa AbstractDict ||
        fail("bundle.receipt.capture_scope", "is missing")
    capture_id = get(scope, "capture_id", nothing)
    capture_id isa String ||
        fail("bundle.receipt.capture_scope.capture_id", "must be a string")
    expectation = supplied_expectation === nothing ?
        expectation_for(capture_id) :
        supplied_expectation
    capture_id == expectation.capture_id ||
        fail(
        "bundle.receipt.capture_scope.capture_id",
        "does not match the supplied expectation",
    )
    validated = _validate_receipt(document, expectation)
    expected_receipt_name =
        "receipt-self-sha256-$(validated.receipt_sha256).toml"
    receipt_name == expected_receipt_name ||
        fail("bundle.receipt", "filename does not match receipt self-hash")
    expected_names = Set(
        vcat(
            [_raw_filename(workbook) for workbook in expectation.workbooks],
            [expected_receipt_name],
        ),
    )
    Set(names) == expected_names ||
        fail("bundle", "contains an unexpected or missing file")
    for workbook in expectation.workbooks
        raw_path = joinpath(path, _raw_filename(workbook))
        isfile(raw_path) ||
            fail("bundle.$(workbook.section_id)", "must be a regular file")
        islink(raw_path) &&
            fail("bundle.$(workbook.section_id)", "must not be a symlink")
        raw_stat = stat(raw_path)
        raw_stat.mode & 0o222 == 0 ||
            fail(
            "bundle.$(workbook.section_id)",
            "must be write-protected",
        )
        raw_stat.nlink == 1 ||
            fail(
            "bundle.$(workbook.section_id)",
            "hard-link aliases are forbidden",
        )
        bytes = read(raw_path)
        length(bytes) == workbook.expected_byte_count ||
            fail(
            "bundle.$(workbook.section_id)",
            "byte count does not match receipt",
        )
        _has_xlsx_magic(bytes) ||
            fail(
            "bundle.$(workbook.section_id)",
            "does not have OOXML ZIP magic",
        )
        sha256_hex(bytes) == workbook.expected_raw_sha256 ||
            fail(
            "bundle.$(workbook.section_id)",
            "SHA-256 does not match receipt",
        )
    end
    if validate_storage_path
        basename(path) ==
            "receipt-self-sha256-$(validated.receipt_sha256)" ||
            fail("bundle", "directory name does not match receipt self-hash")
        basename(dirname(path)) ==
            "pair-sha256-$(validated.pair_sha256)" ||
            fail("bundle", "parent directory does not match pair SHA-256")
    end
    return merge(
        validated,
        (
            bundle_path = path,
            receipt_path = receipt_path,
            receipt_file_sha256 = sha256_hex(receipt_bytes),
        ),
    )
end

validate_capture_bundle(bundle_path::AbstractString) =
    _validate_capture_bundle(bundle_path, nothing)

function _install_bundle(raw_root, expectation, fetched, receipt)
    root = _canonical_raw_root(raw_root)
    pair_digest = receipt["raw_bundle"]["pair_sha256"]
    receipt_digest = receipt["artifact"]["receipt_sha256"]
    parent = joinpath(
        root,
        "bea_nipa",
        "hmi7",
        "historical",
        "captures",
        "pair-sha256-$pair_digest",
    )
    mkpath(parent)
    _reject_symlink_chain(parent, "capture storage")
    target = joinpath(parent, "receipt-self-sha256-$receipt_digest")
    if ispath(target)
        return _validate_capture_bundle(target, expectation)
    end

    staging_root = mktempdir(parent; prefix = ".capture-staging-")
    staged_bundle = staging_root
    moved = false
    try
        for (workbook, response) in zip(expectation.workbooks, fetched)
            _write_exact(
                joinpath(staged_bundle, _raw_filename(workbook)),
                response.raw_bytes,
            )
        end
        receipt_path = _receipt_path(staged_bundle, receipt_digest)
        _write_exact(receipt_path, _toml_bytes(receipt))
        for name in readdir(staged_bundle)
            chmod(joinpath(staged_bundle, name), 0o444)
        end
        chmod(staged_bundle, 0o555)
        staged_result =
            _validate_capture_bundle(
            staged_bundle,
            expectation;
            validate_storage_path = false,
        )
        staged_result.receipt_file_sha256 ==
            receipt_file_sha256(receipt) ||
            fail("bundle staging", "receipt file digest drifted")
        # Keep the staged leaf sealed. Rename requires writable parents, not a
        # writable source directory. The platform-exclusive primitive prevents
        # both copy/delete fallback and replacement of a racing target.
        if !_rename_exclusive(staged_bundle, target)
            if ispath(target)
                return _validate_capture_bundle(target, expectation)
            end
            fail(
                "capture storage",
                "exclusive directory rename reported a target collision, " *
                    "but the target cannot be validated",
            )
        end
        moved = true
        return _validate_capture_bundle(target, expectation)
    finally
        if !moved
            if isdir(staged_bundle) && !islink(staged_bundle)
                chmod(staged_bundle, 0o755)
                for name in readdir(staged_bundle)
                    chmod(joinpath(staged_bundle, name), 0o644)
                end
            end
            ispath(staging_root) &&
                rm(staging_root; recursive = true)
        end
    end
end

function _capture_from_fetched(
        expectation::CaptureExpectation,
        fetched_workbooks,
        raw_root;
        live::Bool,
        terms_reviewed_local_date::Date,
        capture_local_date::Date,
        capture_started_at_utc::DateTime,
        capture_completed_at_utc::DateTime,
    )
    live || fail("live", "must be explicitly true")
    receipt = _build_receipt(
        expectation,
        fetched_workbooks;
        capture_started_at_utc,
        capture_completed_at_utc,
        capture_local_date,
        terms_reviewed_local_date,
    )
    return _install_bundle(raw_root, expectation, fetched_workbooks, receipt)
end

function _require_same_host_local_date(expected::Date, observed::Date)
    expected == observed ||
        fail(
        "capture_local_date",
        "host-local date changed from $expected to $observed; " *
            "review terms and rerun",
    )
    return expected
end

"""
    capture_present_day(capture_id, raw_root; live, terms_reviewed_local_date)

Opt-in live acquisition of one sealed two-workbook HMI7 pair. Both official
workbooks are fetched and validated before a single content-addressed bundle
is atomically installed. The resulting receipt is present-day evidence only:
it cannot establish historical first state or availability, admit an origin,
authorize empirical execution, or mutate the source inventory.
"""
function capture_present_day(
        capture_id::AbstractString,
        raw_root::AbstractString;
        live::Bool = false,
        terms_reviewed_local_date,
    )
    live || fail("live", "must be explicitly true")
    review_date = terms_reviewed_local_date isa Date ?
        terms_reviewed_local_date :
        tryparse(Date, String(terms_reviewed_local_date))
    review_date === nothing &&
        fail("terms_reviewed_local_date", "must be YYYY-MM-DD")
    local_date = today()
    review_date == local_date ||
        fail(
        "terms_reviewed_local_date",
        "must equal today's host-local date $local_date",
    )
    expectation = expectation_for(capture_id)
    capture_started = now(UTC)
    fetched = fetch_official_pair(expectation)
    capture_completed = now(UTC)
    _require_same_host_local_date(local_date, today())
    return _capture_from_fetched(
        expectation,
        fetched,
        raw_root;
        live,
        terms_reviewed_local_date = review_date,
        capture_local_date = local_date,
        capture_started_at_utc = capture_started,
        capture_completed_at_utc = capture_completed,
    )
end

end
