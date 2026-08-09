module RTDSMQuarterlyAcquisition

using Dates
using Downloads
using SHA
using TOML

export FetchedMatrix,
    PROFILE,
    PROFILE_PATH,
    PROFILE_SHA256,
    RESEARCH_PURPOSE_ATTESTATION,
    RTDSMAcquisitionError,
    SeriesExpectation,
    bundle_sha256,
    capture_research_snapshot,
    expectation_for,
    fetch_official_set,
    load_profile,
    new_york_local_date,
    receipt_file_sha256,
    receipt_sha256,
    research_gates,
    validate_capture_bundle,
    validate_fetched_set,
    validate_source_url

const PROFILE_PATH =
    normpath(joinpath(@__DIR__, "..", "rtdsm_quarterly_profile.json"))
const REPOSITORY_ROOT = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."),
)
const PROFILE_SHA256 =
    "6eb3a722dc6cfed72f16782f6f065a85de1bc0a3b2c1b733695c6338db1b593c"
const PROFILE_BYTE_COUNT = 6_658
const TIMEZONE_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "availability",
        "timezone_semantics_iana_tzdb_2026c.toml",
    ),
)
const TIMEZONE_FILE_SHA256 =
    "09677ac80771c2fe41fe5f23510257d3a214bbe5c689591ea9e0ae9920c14983"
const TIMEZONE_CONTENT_SHA256 =
    "8ed940e6deb1a1aa0922369eb8b0ad327ecf52def3c37c7317f81b87afe7a174"
const SCHEMA_VERSION =
    "beforeit-us-rtdsm-quarterly-research-acquisition.v1"
const CANONICALIZATION =
    "sorted-toml-with-artifact-receipt-sha256-omitted.v1"
const BUNDLE_HASH_DOMAIN =
    "beforeit-us-rtdsm-quarterly-five-file-bundle-sha256.v1"
const SOURCE_HOST = "www.philadelphiafed.org"
const SOURCE_PREFIX =
    "https://www.philadelphiafed.org/-/media/FRBP/Assets/Surveys-And-Data/" *
    "real-time-data/data-files/xlsx/"
const EXPECTED_CONTENT_TYPE =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
const TERMS_URL =
    "https://www.philadelphiafed.org/about-us/privacy-notice"
const TERMS_TIMEZONE = "America/New_York"
const MAX_FILE_BYTES = 10_000_000
const MAX_TOTAL_UNCOMPRESSED_BYTES = 250_000_000
const EXPECTED_FILE_COUNT = 5
const FETCH_TIMEOUT_SECONDS = 120
const MAX_SERVER_CLOCK_SKEW_SECONDS = 300
const USER_AGENT = "BeforeIT-US-RTDSM-Research-Acquisition/1.0"
const RESEARCH_PURPOSE_ATTESTATION = "RESEARCH_DIAGNOSTIC_ONLY"
const RECEIPT_FILENAME_PATTERN =
    r"^receipt-self-sha256-([0-9a-f]{64})\.toml$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const RFC3339_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"
const RFC3339_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
const HTTP_DATE_PATTERN =
    r"^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$"
const HTTP_DATE_FORMAT = dateformat"dd u yyyy HH:MM:SS"
const REQUIRED_XLSX_ENTRIES =
    Set(["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml"])
const REQUIRED_FALSE_GATES = [
    "historical_availability_verified",
    "intraday_availability_verified",
    "strict_origin_admissible",
    "truth_admissible",
    "model_input_allowed",
    "empirical_execution_allowed",
    "inventory_mutation_authorized",
    "production_authorized",
    "ready",
]
const GATE_KEYS = Set(
    vcat(
        REQUIRED_FALSE_GATES,
        ["training_use_allowed", "research_diagnostic_allowed"],
    ),
)

struct RTDSMAcquisitionError <: Exception
    message::String
end

Base.showerror(io::IO, error::RTDSMAcquisitionError) =
    print(io, error.message)

fail(location, message) =
    throw(RTDSMAcquisitionError("$location: $message"))

struct SeriesExpectation
    series_id::String
    filename::String
    landing_page_url::String
    canonical_url::String
    advertised_url_at_profile_review::String
    sheet_name::String
    header_prefix::String
    first_supported_vintage::String
    reference_period_grammar::String
    vintage_header_grammar::String
    source_semantics::String
    protocol_mapping::String
    mapping_status::String
    forbidden_direct_mapping::Bool
end

struct SourceProfile
    schema_version::String
    dataset_id::String
    source_agency::String
    source_attribution::String
    profile_reviewed_at_utc::String
    advertised_dataset_update_date::String
    terms_url::String
    terms_timezone::String
    expected_content_type::String
    maximum_file_bytes::Int
    expected_file_count::Int
    series::NTuple{5, SeriesExpectation}
    selected_crosschecks::Vector{Dict{String, Any}}
    required_false_gates::Vector{String}
end

struct FetchedMatrix
    raw_bytes::Vector{UInt8}
    http_status::Int
    content_type::String
    content_length::String
    content_encoding::String
    requested_url::String
    effective_url::String
    response_date::String
    etag::String
    last_modified::String
    acquisition_started_at_utc::DateTime
    response_returned_at_utc::DateTime
    acquisition_completed_at_utc::DateTime
end

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(sha256(bytes))

function sha256_file(path)
    return open(path, "r") do io
        return bytes2hex(sha256(io))
    end
end

function _reject_symlink_chain(path, location)
    candidate = abspath(String(path))
    while true
        (ispath(candidate) || islink(candidate)) &&
            islink(candidate) &&
            fail(location, "must not traverse a symbolic link")
        parent = dirname(candidate)
        parent == candidate && break
        candidate = parent
    end
    return nothing
end

mutable struct _JSONCursor
    bytes::Vector{UInt8}
    index::Int
end

_json_eof(cursor) = cursor.index > length(cursor.bytes)

function _json_skip_space!(cursor)
    while !_json_eof(cursor) &&
            cursor.bytes[cursor.index] in
            (UInt8(' '), UInt8('\t'), UInt8('\r'), UInt8('\n'))
        cursor.index += 1
    end
    return
end

function _json_literal!(cursor, text, value)
    bytes = Vector{UInt8}(codeunits(text))
    last = cursor.index + length(bytes) - 1
    last <= length(cursor.bytes) &&
        cursor.bytes[cursor.index:last] == bytes ||
        fail("profile JSON", "contains an invalid literal")
    cursor.index = last + 1
    return value
end

function _json_hex4!(cursor)
    cursor.index + 3 <= length(cursor.bytes) ||
        fail("profile JSON", "contains a truncated Unicode escape")
    value = 0
    for byte in cursor.bytes[cursor.index:(cursor.index + 3)]
        digit =
            UInt8('0') <= byte <= UInt8('9') ? Int(byte - UInt8('0')) :
            UInt8('a') <= byte <= UInt8('f') ?
            Int(byte - UInt8('a')) + 10 :
            UInt8('A') <= byte <= UInt8('F') ?
            Int(byte - UInt8('A')) + 10 :
            fail("profile JSON", "contains an invalid Unicode escape")
        value = 16 * value + digit
    end
    cursor.index += 4
    return value
end

function _json_string!(cursor)
    cursor.bytes[cursor.index] == UInt8('"') ||
        fail("profile JSON", "expected a string")
    cursor.index += 1
    io = IOBuffer()
    while !_json_eof(cursor)
        byte = cursor.bytes[cursor.index]
        cursor.index += 1
        byte == UInt8('"') && return String(take!(io))
        byte < 0x20 &&
            fail("profile JSON", "contains an unescaped control character")
        if byte != UInt8('\\')
            write(io, byte)
            continue
        end
        _json_eof(cursor) &&
            fail("profile JSON", "contains a truncated escape")
        escaped = cursor.bytes[cursor.index]
        cursor.index += 1
        if escaped in
                (
                UInt8('"'),
                UInt8('\\'),
                UInt8('/'),
            )
            write(io, escaped)
        elseif escaped == UInt8('b')
            write(io, UInt8('\b'))
        elseif escaped == UInt8('f')
            write(io, UInt8('\f'))
        elseif escaped == UInt8('n')
            write(io, UInt8('\n'))
        elseif escaped == UInt8('r')
            write(io, UInt8('\r'))
        elseif escaped == UInt8('t')
            write(io, UInt8('\t'))
        elseif escaped == UInt8('u')
            codepoint = _json_hex4!(cursor)
            0xd800 <= codepoint <= 0xdfff &&
                fail("profile JSON", "surrogate escapes are not accepted")
            write(io, Char(codepoint))
        else
            fail("profile JSON", "contains an invalid escape")
        end
    end
    return fail("profile JSON", "contains an unterminated string")
end

function _json_number!(cursor)
    start = cursor.index
    while !_json_eof(cursor) &&
            cursor.bytes[cursor.index] in
            Vector{UInt8}(codeunits("-+0123456789.eE"))
        cursor.index += 1
    end
    text = String(cursor.bytes[start:(cursor.index - 1)])
    occursin(
        r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$",
        text,
    ) || fail("profile JSON", "contains a noncanonical number")
    if occursin(r"[.eE]", text)
        value = tryparse(Float64, text)
        value !== nothing && isfinite(value) ||
            fail("profile JSON", "contains an invalid number")
        return value
    end
    value = tryparse(Int, text)
    value === nothing && fail("profile JSON", "integer is outside Int range")
    return value
end

function _json_array!(cursor)
    cursor.index += 1
    result = Any[]
    _json_skip_space!(cursor)
    if !_json_eof(cursor) && cursor.bytes[cursor.index] == UInt8(']')
        cursor.index += 1
        return result
    end
    while true
        push!(result, _json_value!(cursor))
        _json_skip_space!(cursor)
        _json_eof(cursor) &&
            fail("profile JSON", "contains an unterminated array")
        delimiter = cursor.bytes[cursor.index]
        cursor.index += 1
        delimiter == UInt8(']') && return result
        delimiter == UInt8(',') ||
            fail("profile JSON", "contains an invalid array delimiter")
        _json_skip_space!(cursor)
    end
    return
end

function _json_object!(cursor)
    cursor.index += 1
    result = Dict{String, Any}()
    _json_skip_space!(cursor)
    if !_json_eof(cursor) && cursor.bytes[cursor.index] == UInt8('}')
        cursor.index += 1
        return result
    end
    while true
        !_json_eof(cursor) && cursor.bytes[cursor.index] == UInt8('"') ||
            fail("profile JSON", "object key must be a string")
        key = _json_string!(cursor)
        haskey(result, key) &&
            fail("profile JSON", "contains duplicate key $key")
        _json_skip_space!(cursor)
        !_json_eof(cursor) && cursor.bytes[cursor.index] == UInt8(':') ||
            fail("profile JSON", "object key lacks a colon")
        cursor.index += 1
        result[key] = _json_value!(cursor)
        _json_skip_space!(cursor)
        _json_eof(cursor) &&
            fail("profile JSON", "contains an unterminated object")
        delimiter = cursor.bytes[cursor.index]
        cursor.index += 1
        delimiter == UInt8('}') && return result
        delimiter == UInt8(',') ||
            fail("profile JSON", "contains an invalid object delimiter")
        _json_skip_space!(cursor)
    end
    return
end

function _json_value!(cursor)
    _json_skip_space!(cursor)
    _json_eof(cursor) && fail("profile JSON", "ends before a value")
    byte = cursor.bytes[cursor.index]
    return byte == UInt8('"') ? _json_string!(cursor) :
        byte == UInt8('{') ? _json_object!(cursor) :
        byte == UInt8('[') ? _json_array!(cursor) :
        byte == UInt8('t') ? _json_literal!(cursor, "true", true) :
        byte == UInt8('f') ? _json_literal!(cursor, "false", false) :
        byte == UInt8('n') ? _json_literal!(cursor, "null", nothing) :
        byte == UInt8('-') || UInt8('0') <= byte <= UInt8('9') ?
        _json_number!(cursor) :
        fail("profile JSON", "contains an invalid value")
end

function _parse_json(bytes)
    cursor = _JSONCursor(copy(bytes), 1)
    result = _json_value!(cursor)
    _json_skip_space!(cursor)
    _json_eof(cursor) ||
        fail("profile JSON", "contains trailing non-whitespace bytes")
    return result
end

function _expect_keys(value, expected_keys, location)
    value isa AbstractDict || fail(location, "must be an object")
    Set(String.(collect(keys(value)))) == Set(expected_keys) ||
        fail(location, "keys differ from the sealed schema")
    return value
end

function _expect_string(value, location)
    value isa String || fail(location, "must be a string")
    isempty(value) && fail(location, "must not be empty")
    return value
end

function _expect_equal(actual, expected, location)
    typeof(actual) === typeof(expected) && actual == expected ||
        fail(location, "differs from the sealed profile")
    return actual
end

function _parse_rfc3339(value, location)
    text = _expect_string(value, location)
    occursin(RFC3339_PATTERN, text) ||
        fail(location, "must be canonical UTC RFC3339 with milliseconds")
    return try
        DateTime(text[1:(end - 1)], RFC3339_FORMAT)
    catch
        fail(location, "is not a valid timestamp")
    end
end

function _profile_series(record, index)
    required = Set(
        [
            "series_id",
            "filename",
            "landing_page_url",
            "canonical_url",
            "advertised_url_at_profile_review",
            "sheet_name",
            "header_prefix",
            "first_supported_vintage",
            "reference_period_grammar",
            "vintage_header_grammar",
            "source_semantics",
            "protocol_mapping",
            "mapping_status",
        ],
    )
    allowed = union(required, Set(["forbidden_direct_mapping"]))
    record isa AbstractDict ||
        fail("profile.series[$index]", "must be an object")
    Set(keys(record)) in (required, allowed) ||
        fail("profile.series[$index]", "keys differ from the sealed schema")
    fields = [
        _expect_string(record[key], "profile.series[$index].$key") for key in
            [
                "series_id",
                "filename",
                "landing_page_url",
                "canonical_url",
                "advertised_url_at_profile_review",
                "sheet_name",
                "header_prefix",
                "first_supported_vintage",
                "reference_period_grammar",
                "vintage_header_grammar",
                "source_semantics",
                "protocol_mapping",
                "mapping_status",
            ]
    ]
    forbidden = get(record, "forbidden_direct_mapping", false)
    forbidden isa Bool ||
        fail(
        "profile.series[$index].forbidden_direct_mapping",
        "must be Boolean",
    )
    return SeriesExpectation(fields..., forbidden)
end

function validate_source_url(url, expectation::SeriesExpectation)
    text = String(url)
    text == expectation.canonical_url ||
        fail("source_url", "is not the exact profile-canonical URL")
    occursin(
        r"^https://www\.philadelphiafed\.org/[A-Za-z0-9_./-]+\.xlsx$",
        text,
    ) || fail("source_url", "has an invalid scheme, host, path, or suffix")
    any(character -> character in ('?', '#', '@'), text) &&
        fail("source_url", "queries, fragments, and user information are forbidden")
    return text
end

function load_profile(path::AbstractString = PROFILE_PATH)
    text = String(path)
    isabspath(text) || fail("profile", "path must be absolute")
    normpath(text) == text || fail("profile", "path must be normalized")
    _reject_symlink_chain(text, "profile")
    isfile(text) || fail("profile", "must be a regular file")
    metadata = stat(text)
    metadata.nlink == 1 || fail("profile", "hard-link aliases are forbidden")
    bytes = read(text)
    length(bytes) == PROFILE_BYTE_COUNT ||
        fail("profile", "byte count differs from the sealed profile")
    sha256_hex(bytes) == PROFILE_SHA256 ||
        fail("profile", "SHA-256 differs from the sealed profile")
    document = _parse_json(bytes)
    root_keys = Set(
        [
            "schema_version",
            "dataset_id",
            "source_agency",
            "source_attribution",
            "profile_reviewed_at_utc",
            "advertised_dataset_update_date",
            "terms_url",
            "terms_timezone",
            "research_use_only",
            "redistribution_authorized",
            "raw_git_commit_authorized",
            "commercial_use_authorized",
            "logo_reuse_authorized",
            "model_training_authorized_by_contract",
            "expected_content_type",
            "maximum_file_bytes",
            "expected_file_count",
            "series",
            "selected_crosschecks",
            "required_false_gates",
        ],
    )
    _expect_keys(document, root_keys, "profile")
    _expect_equal(
        document["schema_version"],
        "beforeit-us-rtdsm-quarterly-source-profile.v1",
        "profile.schema_version",
    )
    _expect_equal(
        document["dataset_id"],
        "philadelphia_fed_rtdsm_quarterly_vintage_matrices",
        "profile.dataset_id",
    )
    _expect_equal(
        document["source_agency"],
        "Federal Reserve Bank of Philadelphia",
        "profile.source_agency",
    )
    _expect_equal(
        document["source_attribution"],
        "Source: Federal Reserve Bank of Philadelphia Real-Time Data Set for Macroeconomists",
        "profile.source_attribution",
    )
    _parse_rfc3339(
        replace(document["profile_reviewed_at_utc"], "Z" => ".000Z"),
        "profile.profile_reviewed_at_utc",
    )
    date_text = _expect_string(
        document["advertised_dataset_update_date"],
        "profile.advertised_dataset_update_date",
    )
    parsed_date = tryparse(Date, date_text)
    parsed_date !== nothing && string(parsed_date) == date_text ||
        fail(
        "profile.advertised_dataset_update_date",
        "must be canonical YYYY-MM-DD",
    )
    _expect_equal(document["terms_url"], TERMS_URL, "profile.terms_url")
    _expect_equal(
        document["terms_timezone"],
        TERMS_TIMEZONE,
        "profile.terms_timezone",
    )
    for (key, expected) in (
            "research_use_only" => true,
            "redistribution_authorized" => false,
            "raw_git_commit_authorized" => false,
            "commercial_use_authorized" => false,
            "logo_reuse_authorized" => false,
            "model_training_authorized_by_contract" => false,
        )
        _expect_equal(document[key], expected, "profile.$key")
    end
    _expect_equal(
        document["expected_content_type"],
        EXPECTED_CONTENT_TYPE,
        "profile.expected_content_type",
    )
    _expect_equal(
        document["maximum_file_bytes"],
        MAX_FILE_BYTES,
        "profile.maximum_file_bytes",
    )
    _expect_equal(
        document["expected_file_count"],
        EXPECTED_FILE_COUNT,
        "profile.expected_file_count",
    )
    series_records = document["series"]
    series_records isa AbstractVector ||
        fail("profile.series", "must be an array")
    length(series_records) == EXPECTED_FILE_COUNT ||
        fail("profile.series", "must contain exactly five records")
    series = ntuple(
        index -> _profile_series(series_records[index], index),
        EXPECTED_FILE_COUNT,
    )
    expected_ids = ["NOUTPUT", "ROUTPUT", "P", "PCON", "PCONX"]
    expected_filenames = [
        "NOUTPUTQvQd.xlsx",
        "ROUTPUTQvQd.xlsx",
        "PQvQd.xlsx",
        "pconQvQd.xlsx",
        "PCONXQvQd.xlsx",
    ]
    for (index, expectation) in enumerate(series)
        expectation.series_id == expected_ids[index] ||
            fail("profile.series[$index].series_id", "order or identity drifted")
        expectation.filename == expected_filenames[index] ||
            fail("profile.series[$index].filename", "identity drifted")
        expectation.canonical_url == SOURCE_PREFIX * expectation.filename ||
            fail("profile.series[$index].canonical_url", "is not canonical")
        validate_source_url(expectation.canonical_url, expectation)
        occursin(
            Regex(
                "^" *
                    replace(expectation.canonical_url, "." => "\\.") *
                    "\\?hash=[0-9A-F]{32}&sc_lang=en\$",
            ),
            expectation.advertised_url_at_profile_review,
        ) ||
            fail(
            "profile.series[$index].advertised_url_at_profile_review",
            "does not match the reviewed advertised URL grammar",
        )
        expectation.reference_period_grammar == "YYYY:Qq" ||
            fail(
            "profile.series[$index].reference_period_grammar",
            "drifted",
        )
        (expectation.series_id in ("P", "PCON")) ==
            expectation.forbidden_direct_mapping ||
            fail(
            "profile.series[$index].forbidden_direct_mapping",
            "does not match the conservative mapping boundary",
        )
    end
    crosschecks = document["selected_crosschecks"]
    crosschecks isa Vector && length(crosschecks) == 2 ||
        fail("profile.selected_crosschecks", "must contain exactly two records")
    for (index, crosscheck) in enumerate(crosschecks)
        _expect_keys(
            crosscheck,
            Set(
                [
                    "reference_period",
                    "rtdsm_vintage",
                    "bea_fingerprint_sha256",
                    "bea_annual_update_caveat",
                ],
            ),
            "profile.selected_crosschecks[$index]",
        )
        occursin(
            HASH_PATTERN,
            _expect_string(
                crosscheck["bea_fingerprint_sha256"],
                "profile.selected_crosschecks[$index].bea_fingerprint_sha256",
            ),
        ) ||
            fail(
            "profile.selected_crosschecks[$index].bea_fingerprint_sha256",
            "must be SHA-256",
        )
    end
    gates = document["required_false_gates"]
    gates isa Vector && all(value -> value isa String, gates) ||
        fail("profile.required_false_gates", "must be a string array")
    gates == REQUIRED_FALSE_GATES ||
        fail("profile.required_false_gates", "drifted")
    return SourceProfile(
        document["schema_version"],
        document["dataset_id"],
        document["source_agency"],
        document["source_attribution"],
        document["profile_reviewed_at_utc"],
        document["advertised_dataset_update_date"],
        document["terms_url"],
        document["terms_timezone"],
        document["expected_content_type"],
        document["maximum_file_bytes"],
        document["expected_file_count"],
        series,
        Dict{String, Any}.(crosschecks),
        String.(gates),
    )
end

const PROFILE = load_profile()
const EXPECTATION_BY_ID =
    Dict(expectation.series_id => expectation for expectation in PROFILE.series)

function expectation_for(series_id)
    identifier = String(series_id)
    haskey(EXPECTATION_BY_ID, identifier) ||
        fail("series_id", "is not one of the five sealed RTDSM matrices")
    return EXPECTATION_BY_ID[identifier]
end

function research_gates(; research_diagnostic_allowed = true)
    research_diagnostic_allowed isa Bool ||
        fail("gates.research_diagnostic_allowed", "must be Boolean")
    gates = Dict{String, Any}(
        key => false for key in REQUIRED_FALSE_GATES
    )
    gates["training_use_allowed"] = false
    gates["research_diagnostic_allowed"] = research_diagnostic_allowed
    return gates
end

function _load_timezone_semantics(path = TIMEZONE_PATH)
    text = String(path)
    isabspath(text) || fail("timezone semantics", "path must be absolute")
    normpath(text) == text ||
        fail("timezone semantics", "path must be normalized")
    _reject_symlink_chain(text, "timezone semantics")
    isfile(text) || fail("timezone semantics", "must be a regular file")
    sha256_file(text) == TIMEZONE_FILE_SHA256 ||
        fail("timezone semantics", "file SHA-256 drifted")
    document = try
        TOML.parsefile(text)
    catch error
        fail(
            "timezone semantics",
            "cannot be parsed ($(sprint(showerror, error)))",
        )
    end
    document["artifact"]["content_sha256"] == TIMEZONE_CONTENT_SHA256 ||
        fail("timezone semantics", "content identity drifted")
    document["source"]["iana_tzdb_version"] == "2026c" ||
        fail("timezone semantics", "IANA version drifted")
    document["coverage"]["local_date_start_inclusive"] == "1997-01-01" ||
        fail("timezone semantics", "coverage start drifted")
    document["coverage"]["local_date_end_inclusive"] == "2036-01-01" ||
        fail("timezone semantics", "coverage end drifted")
    return document
end

function _offset_minutes(text, location)
    parsed_match = match(r"^([+-])(\d{2}):(\d{2})$", String(text))
    parsed_match === nothing && fail(location, "must be a UTC offset")
    hours = parse(Int, parsed_match[2])
    minutes = parse(Int, parsed_match[3])
    hours <= 23 && minutes <= 59 || fail(location, "offset is out of range")
    value = 60 * hours + minutes
    return parsed_match[1] == "-" ? -value : value
end

function _offset_at_local_midnight(document, local_date::Date)
    Date(1997, 1, 1) <= local_date <= Date(2036, 1, 1) ||
        fail("America/New_York local date", "is outside sealed TZDB coverage")
    segments = document["zones"][TERMS_TIMEZONE]["segments"]
    selected = nothing
    for segment in segments
        start = Date(segment["local_date_start"])
        start <= local_date && (selected = segment)
    end
    selected === nothing &&
        fail("America/New_York local date", "has no TZDB segment")
    return _offset_minutes(
        selected["utc_offset"],
        "America/New_York UTC offset",
    )
end

function new_york_local_date(
        instant::DateTime;
        timezone_path::AbstractString = TIMEZONE_PATH,
    )
    document = _load_timezone_semantics(timezone_path)
    candidates = Set{Date}()
    for assumed_offset in (-300, -240)
        candidate = Date(instant + Minute(assumed_offset))
        actual_offset = _offset_at_local_midnight(document, candidate)
        Date(instant + Minute(actual_offset)) == candidate &&
            push!(candidates, candidate)
    end
    length(candidates) == 1 ||
        fail(
        "America/New_York local date",
        "cannot be uniquely resolved from sealed TZDB semantics",
    )
    return only(candidates)
end

function _format_utc(value::DateTime)
    return Dates.format(value, RFC3339_FORMAT) * "Z"
end

function _parse_http_date(value, location)
    text = _expect_string(value, location)
    occursin(HTTP_DATE_PATTERN, text) ||
        fail(location, "must be a canonical IMF-fixdate")
    parsed = try
        DateTime(text[6:(end - 4)], HTTP_DATE_FORMAT)
    catch
        fail(location, "is not a valid IMF-fixdate")
    end
    text[1:3] == dayabbr(Date(parsed)) ||
        fail(location, "weekday does not match the date")
    return parsed
end

function _base_content_type(value)
    return lowercase(strip(first(split(String(value), ';'; limit = 2))))
end

function _validated_content_length(value, location)
    text = _expect_string(value, location)
    occursin(r"^[1-9][0-9]*$", text) ||
        fail(location, "must be a positive canonical integer")
    result = tryparse(Int, text)
    result === nothing && fail(location, "does not fit in Int")
    result <= MAX_FILE_BYTES ||
        fail(location, "exceeds the profile byte limit")
    return result
end

function _u16(bytes, position, location)
    position >= 1 && position + 1 <= length(bytes) ||
        fail(location, "contains a truncated 16-bit field")
    return Int(bytes[position]) | (Int(bytes[position + 1]) << 8)
end

function _u32(bytes, position, location)
    position >= 1 && position + 3 <= length(bytes) ||
        fail(location, "contains a truncated 32-bit field")
    return Int(bytes[position]) |
        (Int(bytes[position + 1]) << 8) |
        (Int(bytes[position + 2]) << 16) |
        (Int(bytes[position + 3]) << 24)
end

function _signature_at(bytes, position, signature)
    return position >= 1 &&
        position + length(signature) - 1 <= length(bytes) &&
        bytes[position:(position + length(signature) - 1)] == signature
end

function _validate_xlsx_zip(bytes, location)
    22 <= length(bytes) <= MAX_FILE_BYTES ||
        fail(location, "byte count is outside the ZIP/XLSX range")
    _signature_at(bytes, 1, UInt8[0x50, 0x4b, 0x03, 0x04]) ||
        fail(location, "does not start with a ZIP local-file header")
    eocd_signature = UInt8[0x50, 0x4b, 0x05, 0x06]
    eocd = nothing
    first_candidate = max(1, length(bytes) - 65_535 - 22 + 1)
    for position in (length(bytes) - 21):-1:first_candidate
        if _signature_at(bytes, position, eocd_signature)
            comment_length = _u16(bytes, position + 20, location)
            if position + 22 + comment_length - 1 == length(bytes)
                eocd = position
                break
            end
        end
    end
    eocd === nothing &&
        fail(location, "does not contain a terminal ZIP EOCD record")
    position = something(eocd)
    disk_number = _u16(bytes, position + 4, location)
    central_disk = _u16(bytes, position + 6, location)
    entries_on_disk = _u16(bytes, position + 8, location)
    total_entries = _u16(bytes, position + 10, location)
    central_size = _u32(bytes, position + 12, location)
    central_offset = _u32(bytes, position + 16, location)
    disk_number == 0 && central_disk == 0 ||
        fail(location, "multi-disk ZIP archives are forbidden")
    0 < total_entries < 0xffff && entries_on_disk == total_entries ||
        fail(location, "ZIP entry count is invalid or ZIP64")
    central_start = central_offset + 1
    central_end_exclusive = central_start + central_size
    central_start >= 1 &&
        central_end_exclusive - 1 < position ||
        fail(location, "central directory bounds are invalid")
    names = Set{String}()
    total_uncompressed = 0
    cursor = central_start
    for index in 1:total_entries
        _signature_at(
            bytes,
            cursor,
            UInt8[0x50, 0x4b, 0x01, 0x02],
        ) ||
            fail(location, "central entry $index has an invalid signature")
        flags = _u16(bytes, cursor + 8, location)
        flags & 0x0001 == 0 ||
            fail(location, "encrypted ZIP entries are forbidden")
        compressed_size = _u32(bytes, cursor + 20, location)
        uncompressed_size = _u32(bytes, cursor + 24, location)
        compressed_size != 0xffffffff && uncompressed_size != 0xffffffff ||
            fail(location, "ZIP64 entry sizes are forbidden")
        total_uncompressed += uncompressed_size
        total_uncompressed <= MAX_TOTAL_UNCOMPRESSED_BYTES ||
            fail(location, "advertised uncompressed size exceeds the limit")
        name_length = _u16(bytes, cursor + 28, location)
        extra_length = _u16(bytes, cursor + 30, location)
        comment_length = _u16(bytes, cursor + 32, location)
        disk_start = _u16(bytes, cursor + 34, location)
        disk_start == 0 ||
            fail(location, "central entry $index starts on another disk")
        name_length > 0 ||
            fail(location, "central entry $index has an empty name")
        name_start = cursor + 46
        name_end = name_start + name_length - 1
        name_end <= length(bytes) ||
            fail(location, "central entry $index name is truncated")
        name_bytes = bytes[name_start:name_end]
        isvalid(String, name_bytes) ||
            fail(location, "central entry $index name is not UTF-8")
        name = String(copy(name_bytes))
        startswith(name, "/") ||
            occursin('\\', name) ||
            any(part -> part in ("", ".", ".."), split(name, '/')) ?
            fail(location, "central entry $index has an unsafe name") :
            nothing
        name in names &&
            fail(location, "contains duplicate ZIP entry $name")
        push!(names, name)
        local_offset = _u32(bytes, cursor + 42, location)
        local_offset != 0xffffffff ||
            fail(location, "ZIP64 local offsets are forbidden")
        local_position = local_offset + 1
        _signature_at(
            bytes,
            local_position,
            UInt8[0x50, 0x4b, 0x03, 0x04],
        ) ||
            fail(location, "central entry $index has no matching local header")
        local_flags = _u16(bytes, local_position + 6, location)
        local_flags == flags ||
            fail(location, "central/local flags differ for entry $index")
        local_name_length = _u16(bytes, local_position + 26, location)
        local_extra_length = _u16(bytes, local_position + 28, location)
        local_name_start = local_position + 30
        local_name_end = local_name_start + local_name_length - 1
        local_name_end <= length(bytes) ||
            fail(location, "local entry $index name is truncated")
        local_name_length == name_length &&
            bytes[local_name_start:local_name_end] == name_bytes ||
            fail(location, "central/local names differ for entry $index")
        data_start = local_name_end + 1 + local_extra_length
        data_start + compressed_size - 1 < central_start ||
            fail(location, "local entry $index data exceeds local-data bounds")
        cursor =
            name_end + 1 + extra_length + comment_length
        cursor <= central_end_exclusive ||
            fail(location, "central entry $index exceeds directory bounds")
    end
    cursor == central_end_exclusive ||
        fail(location, "central directory size does not match its entries")
    all(name -> name in names, REQUIRED_XLSX_ENTRIES) ||
        fail(location, "lacks required XLSX package entries")
    return (
        entry_count = total_entries,
        required_entries_verified = true,
        total_uncompressed_bytes = total_uncompressed,
    )
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
    dl_total <= MAX_FILE_BYTES ||
        fail("http.progress", "advertised body exceeds the profile limit")
    dl_now <= MAX_FILE_BYTES ||
        fail("http.progress", "download exceeds the profile limit")
    ul_total == 0 && ul_now == 0 ||
        fail("http.progress", "GET upload counters must remain zero")
    return nothing
end

function _validate_fetched_matrix(
        fetched::FetchedMatrix,
        expectation::SeriesExpectation;
        location,
    )
    validate_source_url(expectation.canonical_url, expectation)
    fetched.http_status == 200 ||
        fail("$location.http_status", "must equal 200")
    fetched.requested_url == expectation.canonical_url ||
        fail("$location.requested_url", "differs from the profile URL")
    fetched.effective_url == expectation.canonical_url ||
        fail("$location.effective_url", "redirects are forbidden")
    _base_content_type(fetched.content_type) == EXPECTED_CONTENT_TYPE ||
        fail("$location.content_type", "must be the XLSX media type")
    fetched.content_encoding in ("NOT_PROVIDED", "identity") ||
        fail("$location.content_encoding", "must be absent or identity")
    byte_count = length(fetched.raw_bytes)
    _validated_content_length(
        fetched.content_length,
        "$location.content_length",
    ) == byte_count ||
        fail("$location.content_length", "does not equal body byte count")
    0 < byte_count <= MAX_FILE_BYTES ||
        fail("$location.raw_bytes", "byte count is outside profile bounds")
    zip = _validate_xlsx_zip(fetched.raw_bytes, "$location.raw_bytes")
    fetched.acquisition_started_at_utc <=
        fetched.response_returned_at_utc <=
        fetched.acquisition_completed_at_utc ||
        fail("$location.timestamps", "must be ordered")
    server_date = _parse_http_date(
        fetched.response_date,
        "$location.response_date",
    )
    skew = Second(MAX_SERVER_CLOCK_SKEW_SECONDS)
    fetched.acquisition_started_at_utc - skew <= server_date <=
        fetched.response_returned_at_utc + skew ||
        fail(
        "$location.response_date",
        "is outside the server/local clock-skew bound",
    )
    return (
        raw_sha256 = sha256_hex(fetched.raw_bytes),
        raw_byte_count = byte_count,
        zip_entry_count = zip.entry_count,
    )
end

function validate_fetched_set(
        fetched_matrices,
        profile::SourceProfile = PROFILE,
    )
    fetched_matrices isa AbstractVector ||
        fail("matrices", "must be a vector")
    length(fetched_matrices) == profile.expected_file_count ||
        fail("matrices", "must contain exactly five matrices")
    all(value -> value isa FetchedMatrix, fetched_matrices) ||
        fail("matrices", "must contain only FetchedMatrix records")
    length(unique(objectid(value) for value in fetched_matrices)) ==
        profile.expected_file_count ||
        fail("matrices", "object aliases are forbidden")
    results = [
        _validate_fetched_matrix(
                fetched,
                expectation;
                location = "matrices[$index].$(expectation.series_id)",
            )
            for (index, (fetched, expectation)) in
            enumerate(zip(fetched_matrices, profile.series))
    ]
    length(unique(result.raw_sha256 for result in results)) ==
        profile.expected_file_count ||
        fail("matrices", "raw-byte aliases are forbidden")
    return results
end

function _hash_field!(io, name, value)
    name_bytes = Vector{UInt8}(codeunits(String(name)))
    value_bytes = Vector{UInt8}(codeunits(string(value)))
    write(io, string(length(name_bytes)), ':', name_bytes)
    write(io, string(length(value_bytes)), ':', value_bytes)
    return io
end

function bundle_sha256(
        fetched_matrices,
        profile::SourceProfile = PROFILE,
    )
    results = validate_fetched_set(fetched_matrices, profile)
    io = IOBuffer()
    _hash_field!(io, "domain", BUNDLE_HASH_DOMAIN)
    _hash_field!(io, "profile_sha256", PROFILE_SHA256)
    _hash_field!(io, "dataset_id", profile.dataset_id)
    for (index, (expectation, result)) in
        enumerate(zip(profile.series, results))
        _hash_field!(io, "matrix_index", index)
        _hash_field!(io, "series_id", expectation.series_id)
        _hash_field!(io, "filename", expectation.filename)
        _hash_field!(io, "canonical_url", expectation.canonical_url)
        _hash_field!(io, "raw_sha256", result.raw_sha256)
        _hash_field!(io, "raw_byte_count", result.raw_byte_count)
    end
    return sha256_hex(take!(io))
end

function _header(response, name)
    values = String[
        String(value) for (key, value) in response.headers if
            lowercase(String(key)) == lowercase(String(name))
    ]
    length(values) <= 1 ||
        fail("http.header.$name", "must not be repeated")
    return isempty(values) ? "NOT_PROVIDED" : only(values)
end

function fetch_official_matrix(expectation::SeriesExpectation)
    validate_source_url(expectation.canonical_url, expectation)
    response_body = IOBuffer()
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, info) -> Downloads.Curl.setopt(
        easy,
        Downloads.Curl.CURLOPT_FOLLOWLOCATION,
        false,
    )
    started = now(UTC)
    response = Downloads.request(
        expectation.canonical_url;
        method = "GET",
        headers = [
            "Accept" => EXPECTED_CONTENT_TYPE,
            "Accept-Encoding" => "identity",
            "User-Agent" => USER_AGENT,
        ],
        output = response_body,
        timeout = FETCH_TIMEOUT_SECONDS,
        progress = _enforce_download_limit,
        downloader = downloader,
        throw = false,
    )
    returned = now(UTC)
    bytes = take!(response_body)
    completed = now(UTC)
    length(bytes) <= MAX_FILE_BYTES ||
        fail("http.body", "exceeds the profile byte limit")
    return FetchedMatrix(
        bytes,
        response.status,
        _header(response, "content-type"),
        _header(response, "content-length"),
        _header(response, "content-encoding"),
        expectation.canonical_url,
        String(response.url),
        _header(response, "date"),
        _header(response, "etag"),
        _header(response, "last-modified"),
        started,
        returned,
        completed,
    )
end

function fetch_official_set(profile::SourceProfile = PROFILE)
    fetched = FetchedMatrix[
        fetch_official_matrix(expectation) for expectation in profile.series
    ]
    validate_fetched_set(fetched, profile)
    return fetched
end

function _toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    bytes = take!(io)
    isempty(bytes) && fail("receipt serialization", "must not be empty")
    bytes[end] == UInt8('\n') || push!(bytes, UInt8('\n'))
    return bytes
end

function _receipt_without_hash(document)
    copy = deepcopy(document)
    artifact = get(copy, "artifact", nothing)
    artifact isa AbstractDict ||
        fail("receipt.artifact", "must be a table")
    haskey(artifact, "receipt_sha256") ||
        fail("receipt.artifact.receipt_sha256", "is missing")
    delete!(artifact, "receipt_sha256")
    return copy
end

function receipt_sha256(document)
    document isa AbstractDict || fail("receipt", "must be a TOML document")
    return sha256_hex(_toml_bytes(_receipt_without_hash(document)))
end

function receipt_file_sha256(document)
    document isa AbstractDict || fail("receipt", "must be a TOML document")
    return sha256_hex(_toml_bytes(document))
end

function _raw_filename(series_id, digest)
    occursin(HASH_PATTERN, String(digest)) ||
        fail("raw filename", "digest must be SHA-256")
    String(series_id) in keys(EXPECTATION_BY_ID) ||
        fail("raw filename", "series identity is not sealed")
    return "raw-$(String(series_id))-sha256-$(String(digest)).xlsx"
end

function _build_receipt(
        fetched_matrices,
        profile::SourceProfile;
        terms_reviewed_local_date::Date,
        capture_local_date::Date,
        capture_started_at_utc::DateTime,
        capture_completed_at_utc::DateTime,
    )
    results = validate_fetched_set(fetched_matrices, profile)
    capture_started_at_utc <= capture_completed_at_utc ||
        fail("capture timestamps", "must be ordered")
    capture_id = _capture_id(capture_started_at_utc)
    matrices = Dict{String, Any}[]
    for (expectation, fetched, result) in
        zip(profile.series, fetched_matrices, results)
        push!(
            matrices,
            Dict{String, Any}(
                "series_id" => expectation.series_id,
                "official_filename" => expectation.filename,
                "stored_filename" =>
                    _raw_filename(expectation.series_id, result.raw_sha256),
                "landing_page_url" => expectation.landing_page_url,
                "canonical_url" => expectation.canonical_url,
                "advertised_url_at_profile_review" =>
                    expectation.advertised_url_at_profile_review,
                "requested_url" => fetched.requested_url,
                "effective_url" => fetched.effective_url,
                "sheet_name" => expectation.sheet_name,
                "header_prefix" => expectation.header_prefix,
                "first_supported_vintage" =>
                    expectation.first_supported_vintage,
                "reference_period_grammar" =>
                    expectation.reference_period_grammar,
                "vintage_header_grammar" =>
                    expectation.vintage_header_grammar,
                "source_semantics" => expectation.source_semantics,
                "protocol_mapping" => expectation.protocol_mapping,
                "mapping_status" => expectation.mapping_status,
                "forbidden_direct_mapping" =>
                    expectation.forbidden_direct_mapping,
                "http_status" => fetched.http_status,
                "content_type" => fetched.content_type,
                "content_length_header" => fetched.content_length,
                "content_encoding" => fetched.content_encoding,
                "response_date" => fetched.response_date,
                "etag" => fetched.etag,
                "last_modified" => fetched.last_modified,
                "acquisition_started_at_utc" =>
                    _format_utc(fetched.acquisition_started_at_utc),
                "response_returned_at_utc" =>
                    _format_utc(fetched.response_returned_at_utc),
                "acquisition_completed_at_utc" =>
                    _format_utc(fetched.acquisition_completed_at_utc),
                "observed_raw_sha256" => result.raw_sha256,
                "observed_byte_count" => result.raw_byte_count,
                "zip_entry_count" => result.zip_entry_count,
            ),
        )
    end
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => SCHEMA_VERSION,
            "receipt_id" => capture_id,
            "canonicalization" => CANONICALIZATION,
            "digest_algorithm" => "sha256",
            "receipt_sha256" => repeat("0", 64),
            "immutable_bundle" => true,
        ),
        "profile" => Dict{String, Any}(
            "profile_path" =>
                "scripts/us/forecasting/vintages/rtdsm/rtdsm_quarterly_profile.json",
            "profile_sha256" => PROFILE_SHA256,
            "schema_version" => profile.schema_version,
            "dataset_id" => profile.dataset_id,
            "source_agency" => profile.source_agency,
            "source_attribution" => profile.source_attribution,
            "profile_reviewed_at_utc" => profile.profile_reviewed_at_utc,
            "advertised_dataset_update_date" =>
                profile.advertised_dataset_update_date,
        ),
        "terms" => Dict{String, Any}(
            "terms_url" => profile.terms_url,
            "terms_timezone" => profile.terms_timezone,
            "terms_reviewed_local_date" =>
                string(terms_reviewed_local_date),
            "research_purpose_attestation" =>
                RESEARCH_PURPOSE_ATTESTATION,
            "research_purpose_attested" => true,
            "research_use_only" => true,
            "redistribution_authorized" => false,
            "raw_git_commit_authorized" => false,
            "commercial_use_authorized" => false,
            "logo_reuse_authorized" => false,
            "model_training_authorized_by_contract" => false,
            "fred_alfred_service_used" => false,
        ),
        "capture" => Dict{String, Any}(
            "capture_method" =>
                "DIRECT_OFFICIAL_HTTPS_GET_NO_REDIRECT_ACCEPT_ENCODING_IDENTITY",
            "capture_started_at_utc" =>
                _format_utc(capture_started_at_utc),
            "capture_completed_at_utc" =>
                _format_utc(capture_completed_at_utc),
            "capture_local_date" => string(capture_local_date),
            "capture_timezone" => TERMS_TIMEZONE,
            "present_day_retrieval_only" => true,
            "historical_availability_evidence" => false,
            "intraday_availability_evidence" => false,
            "five_file_transaction" => true,
        ),
        "timezone_evidence" => Dict{String, Any}(
            "iana_tzdb_version" => "2026c",
            "timezone_semantics_file_sha256" => TIMEZONE_FILE_SHA256,
            "timezone_semantics_content_sha256" =>
                TIMEZONE_CONTENT_SHA256,
            "timezone_name" => TERMS_TIMEZONE,
        ),
        "raw_bundle" => Dict{String, Any}(
            "bundle_sha256" => bundle_sha256(fetched_matrices, profile),
            "hash_domain" => BUNDLE_HASH_DOMAIN,
            "expected_file_count" => EXPECTED_FILE_COUNT,
            "storage_mode" =>
                "CONTENT_ADDRESSED_RECEIPT_SPECIFIC_EXACT_FIVE_FILE_TRANSACTION",
            "storage_encoding" => "exact_response_bytes",
            "raw_redistribution_authorized" => false,
            "raw_git_commit_authorized" => false,
        ),
        "matrices" => matrices,
        "gates" => research_gates(),
    )
    document["artifact"]["receipt_sha256"] = receipt_sha256(document)
    return document
end

_capture_id(capture_started_at_utc::DateTime) =
    "rtdsm_quarterly_" *
    replace(_format_utc(capture_started_at_utc), r"[-:.]" => "")

const RECEIPT_ROOT_KEYS = Set(
    [
        "artifact",
        "profile",
        "terms",
        "capture",
        "timezone_evidence",
        "raw_bundle",
        "matrices",
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
const PROFILE_KEYS = Set(
    [
        "profile_path",
        "profile_sha256",
        "schema_version",
        "dataset_id",
        "source_agency",
        "source_attribution",
        "profile_reviewed_at_utc",
        "advertised_dataset_update_date",
    ],
)
const TERMS_KEYS = Set(
    [
        "terms_url",
        "terms_timezone",
        "terms_reviewed_local_date",
        "research_purpose_attestation",
        "research_purpose_attested",
        "research_use_only",
        "redistribution_authorized",
        "raw_git_commit_authorized",
        "commercial_use_authorized",
        "logo_reuse_authorized",
        "model_training_authorized_by_contract",
        "fred_alfred_service_used",
    ],
)
const CAPTURE_KEYS = Set(
    [
        "capture_method",
        "capture_started_at_utc",
        "capture_completed_at_utc",
        "capture_local_date",
        "capture_timezone",
        "present_day_retrieval_only",
        "historical_availability_evidence",
        "intraday_availability_evidence",
        "five_file_transaction",
    ],
)
const TIMEZONE_KEYS = Set(
    [
        "iana_tzdb_version",
        "timezone_semantics_file_sha256",
        "timezone_semantics_content_sha256",
        "timezone_name",
    ],
)
const RAW_BUNDLE_KEYS = Set(
    [
        "bundle_sha256",
        "hash_domain",
        "expected_file_count",
        "storage_mode",
        "storage_encoding",
        "raw_redistribution_authorized",
        "raw_git_commit_authorized",
    ],
)
const MATRIX_KEYS = Set(
    [
        "series_id",
        "official_filename",
        "stored_filename",
        "landing_page_url",
        "canonical_url",
        "advertised_url_at_profile_review",
        "requested_url",
        "effective_url",
        "sheet_name",
        "header_prefix",
        "first_supported_vintage",
        "reference_period_grammar",
        "vintage_header_grammar",
        "source_semantics",
        "protocol_mapping",
        "mapping_status",
        "forbidden_direct_mapping",
        "http_status",
        "content_type",
        "content_length_header",
        "content_encoding",
        "response_date",
        "etag",
        "last_modified",
        "acquisition_started_at_utc",
        "response_returned_at_utc",
        "acquisition_completed_at_utc",
        "observed_raw_sha256",
        "observed_byte_count",
        "zip_entry_count",
    ],
)

function _expect_bool(value, expected, location)
    value isa Bool && value == expected ||
        fail(location, "must equal $expected")
    return value
end

function _expect_hash(value, location)
    text = _expect_string(value, location)
    occursin(HASH_PATTERN, text) || fail(location, "must be SHA-256")
    return text
end

function _receipt_bundle_hash(document, profile)
    io = IOBuffer()
    _hash_field!(io, "domain", BUNDLE_HASH_DOMAIN)
    _hash_field!(io, "profile_sha256", PROFILE_SHA256)
    _hash_field!(io, "dataset_id", profile.dataset_id)
    for (index, (matrix, expectation)) in
        enumerate(zip(document["matrices"], profile.series))
        _hash_field!(io, "matrix_index", index)
        _hash_field!(io, "series_id", expectation.series_id)
        _hash_field!(io, "filename", expectation.filename)
        _hash_field!(io, "canonical_url", expectation.canonical_url)
        _hash_field!(io, "raw_sha256", matrix["observed_raw_sha256"])
        _hash_field!(io, "raw_byte_count", matrix["observed_byte_count"])
    end
    return sha256_hex(take!(io))
end

function _validate_receipt(document, profile::SourceProfile = PROFILE)
    _expect_keys(document, RECEIPT_ROOT_KEYS, "receipt")
    artifact = _expect_keys(document["artifact"], ARTIFACT_KEYS, "receipt.artifact")
    profile_record =
        _expect_keys(document["profile"], PROFILE_KEYS, "receipt.profile")
    terms = _expect_keys(document["terms"], TERMS_KEYS, "receipt.terms")
    capture =
        _expect_keys(document["capture"], CAPTURE_KEYS, "receipt.capture")
    timezone = _expect_keys(
        document["timezone_evidence"],
        TIMEZONE_KEYS,
        "receipt.timezone_evidence",
    )
    raw_bundle = _expect_keys(
        document["raw_bundle"],
        RAW_BUNDLE_KEYS,
        "receipt.raw_bundle",
    )
    gates = _expect_keys(document["gates"], GATE_KEYS, "receipt.gates")
    _expect_equal(
        artifact["schema_version"],
        SCHEMA_VERSION,
        "receipt.artifact.schema_version",
    )
    _expect_equal(
        artifact["canonicalization"],
        CANONICALIZATION,
        "receipt.artifact.canonicalization",
    )
    _expect_equal(
        artifact["digest_algorithm"],
        "sha256",
        "receipt.artifact.digest_algorithm",
    )
    _expect_bool(
        artifact["immutable_bundle"],
        true,
        "receipt.artifact.immutable_bundle",
    )
    receipt_digest =
        _expect_hash(artifact["receipt_sha256"], "receipt.artifact.receipt_sha256")
    receipt_digest == receipt_sha256(document) ||
        fail("receipt.artifact.receipt_sha256", "does not self-verify")
    expected_profile = Dict(
        "profile_path" =>
            "scripts/us/forecasting/vintages/rtdsm/rtdsm_quarterly_profile.json",
        "profile_sha256" => PROFILE_SHA256,
        "schema_version" => profile.schema_version,
        "dataset_id" => profile.dataset_id,
        "source_agency" => profile.source_agency,
        "source_attribution" => profile.source_attribution,
        "profile_reviewed_at_utc" => profile.profile_reviewed_at_utc,
        "advertised_dataset_update_date" =>
            profile.advertised_dataset_update_date,
    )
    for (key, expected) in expected_profile
        _expect_equal(
            profile_record[key],
            expected,
            "receipt.profile.$key",
        )
    end
    _expect_equal(terms["terms_url"], TERMS_URL, "receipt.terms.terms_url")
    _expect_equal(
        terms["terms_timezone"],
        TERMS_TIMEZONE,
        "receipt.terms.terms_timezone",
    )
    _expect_equal(
        terms["research_purpose_attestation"],
        RESEARCH_PURPOSE_ATTESTATION,
        "receipt.terms.research_purpose_attestation",
    )
    for key in ("research_purpose_attested", "research_use_only")
        _expect_bool(terms[key], true, "receipt.terms.$key")
    end
    for key in (
            "redistribution_authorized",
            "raw_git_commit_authorized",
            "commercial_use_authorized",
            "logo_reuse_authorized",
            "model_training_authorized_by_contract",
            "fred_alfred_service_used",
        )
        _expect_bool(terms[key], false, "receipt.terms.$key")
    end
    review_date_text = _expect_string(
        terms["terms_reviewed_local_date"],
        "receipt.terms.terms_reviewed_local_date",
    )
    review_date = tryparse(Date, review_date_text)
    review_date !== nothing &&
        string(review_date) == review_date_text ||
        fail(
        "receipt.terms.terms_reviewed_local_date",
        "must be canonical YYYY-MM-DD",
    )
    _expect_equal(
        capture["capture_method"],
        "DIRECT_OFFICIAL_HTTPS_GET_NO_REDIRECT_ACCEPT_ENCODING_IDENTITY",
        "receipt.capture.capture_method",
    )
    _expect_equal(
        capture["capture_timezone"],
        TERMS_TIMEZONE,
        "receipt.capture.capture_timezone",
    )
    for key in ("present_day_retrieval_only", "five_file_transaction")
        _expect_bool(capture[key], true, "receipt.capture.$key")
    end
    for key in (
            "historical_availability_evidence",
            "intraday_availability_evidence",
        )
        _expect_bool(capture[key], false, "receipt.capture.$key")
    end
    started = _parse_rfc3339(
        capture["capture_started_at_utc"],
        "receipt.capture.capture_started_at_utc",
    )
    completed = _parse_rfc3339(
        capture["capture_completed_at_utc"],
        "receipt.capture.capture_completed_at_utc",
    )
    started <= completed ||
        fail("receipt.capture", "timestamps are not ordered")
    _expect_equal(
        artifact["receipt_id"],
        _capture_id(started),
        "receipt.artifact.receipt_id",
    )
    capture_date_text = _expect_string(
        capture["capture_local_date"],
        "receipt.capture.capture_local_date",
    )
    capture_date = tryparse(Date, capture_date_text)
    capture_date !== nothing &&
        string(capture_date) == capture_date_text ||
        fail("receipt.capture.capture_local_date", "must be YYYY-MM-DD")
    review_date == capture_date ||
        fail("receipt.terms", "review and capture dates differ")
    new_york_local_date(started) == capture_date &&
        new_york_local_date(completed) == capture_date ||
        fail("receipt.capture.capture_local_date", "does not match TZDB")
    _expect_equal(
        timezone["iana_tzdb_version"],
        "2026c",
        "receipt.timezone_evidence.iana_tzdb_version",
    )
    _expect_equal(
        timezone["timezone_semantics_file_sha256"],
        TIMEZONE_FILE_SHA256,
        "receipt.timezone_evidence.timezone_semantics_file_sha256",
    )
    _expect_equal(
        timezone["timezone_semantics_content_sha256"],
        TIMEZONE_CONTENT_SHA256,
        "receipt.timezone_evidence.timezone_semantics_content_sha256",
    )
    _expect_equal(
        timezone["timezone_name"],
        TERMS_TIMEZONE,
        "receipt.timezone_evidence.timezone_name",
    )
    _expect_hash(raw_bundle["bundle_sha256"], "receipt.raw_bundle.bundle_sha256")
    _expect_equal(
        raw_bundle["hash_domain"],
        BUNDLE_HASH_DOMAIN,
        "receipt.raw_bundle.hash_domain",
    )
    _expect_equal(
        raw_bundle["expected_file_count"],
        EXPECTED_FILE_COUNT,
        "receipt.raw_bundle.expected_file_count",
    )
    _expect_equal(
        raw_bundle["storage_mode"],
        "CONTENT_ADDRESSED_RECEIPT_SPECIFIC_EXACT_FIVE_FILE_TRANSACTION",
        "receipt.raw_bundle.storage_mode",
    )
    _expect_equal(
        raw_bundle["storage_encoding"],
        "exact_response_bytes",
        "receipt.raw_bundle.storage_encoding",
    )
    for key in ("raw_redistribution_authorized", "raw_git_commit_authorized")
        _expect_bool(raw_bundle[key], false, "receipt.raw_bundle.$key")
    end
    matrices = document["matrices"]
    matrices isa Vector && length(matrices) == EXPECTED_FILE_COUNT ||
        fail("receipt.matrices", "must contain exactly five records")
    observed_hashes = Set{String}()
    stored_filenames = Set{String}()
    previous_completed = started
    for (index, (matrix, expectation)) in
        enumerate(zip(matrices, profile.series))
        _expect_keys(matrix, MATRIX_KEYS, "receipt.matrices[$index]")
        for (key, expected) in (
                "series_id" => expectation.series_id,
                "official_filename" => expectation.filename,
                "landing_page_url" => expectation.landing_page_url,
                "canonical_url" => expectation.canonical_url,
                "advertised_url_at_profile_review" =>
                    expectation.advertised_url_at_profile_review,
                "requested_url" => expectation.canonical_url,
                "effective_url" => expectation.canonical_url,
                "sheet_name" => expectation.sheet_name,
                "header_prefix" => expectation.header_prefix,
                "first_supported_vintage" =>
                    expectation.first_supported_vintage,
                "reference_period_grammar" =>
                    expectation.reference_period_grammar,
                "vintage_header_grammar" =>
                    expectation.vintage_header_grammar,
                "source_semantics" => expectation.source_semantics,
                "protocol_mapping" => expectation.protocol_mapping,
                "mapping_status" => expectation.mapping_status,
                "forbidden_direct_mapping" =>
                    expectation.forbidden_direct_mapping,
                "http_status" => 200,
            )
            _expect_equal(
                matrix[key],
                expected,
                "receipt.matrices[$index].$key",
            )
        end
        content_type = _expect_string(
            matrix["content_type"],
            "receipt.matrices[$index].content_type",
        )
        _base_content_type(content_type) == EXPECTED_CONTENT_TYPE ||
            fail("receipt.matrices[$index].content_type", "drifted")
        content_encoding = _expect_string(
            matrix["content_encoding"],
            "receipt.matrices[$index].content_encoding",
        )
        content_encoding in ("NOT_PROVIDED", "identity") ||
            fail("receipt.matrices[$index].content_encoding", "drifted")
        for key in ("response_date", "etag", "last_modified")
            _expect_string(
                matrix[key],
                "receipt.matrices[$index].$key",
            )
        end
        byte_count = _validated_content_length(
            matrix["content_length_header"],
            "receipt.matrices[$index].content_length_header",
        )
        byte_count == matrix["observed_byte_count"] ||
            fail("receipt.matrices[$index].observed_byte_count", "drifted")
        digest = _expect_hash(
            matrix["observed_raw_sha256"],
            "receipt.matrices[$index].observed_raw_sha256",
        )
        matrix["stored_filename"] ==
            _raw_filename(expectation.series_id, digest) ||
            fail("receipt.matrices[$index].stored_filename", "drifted")
        digest in observed_hashes &&
            fail("receipt.matrices[$index].observed_raw_sha256", "is aliased")
        push!(observed_hashes, digest)
        stored_filename = String(matrix["stored_filename"])
        stored_filename in stored_filenames &&
            fail("receipt.matrices[$index].stored_filename", "is duplicated")
        push!(stored_filenames, stored_filename)
        matrix["zip_entry_count"] isa Int &&
            matrix["zip_entry_count"] >= length(REQUIRED_XLSX_ENTRIES) ||
            fail("receipt.matrices[$index].zip_entry_count", "is invalid")
        matrix_started = _parse_rfc3339(
            matrix["acquisition_started_at_utc"],
            "receipt.matrices[$index].acquisition_started_at_utc",
        )
        returned = _parse_rfc3339(
            matrix["response_returned_at_utc"],
            "receipt.matrices[$index].response_returned_at_utc",
        )
        matrix_completed = _parse_rfc3339(
            matrix["acquisition_completed_at_utc"],
            "receipt.matrices[$index].acquisition_completed_at_utc",
        )
        previous_completed <= matrix_started <= returned <=
            matrix_completed <= completed ||
            fail("receipt.matrices[$index].timestamps", "are not ordered")
        previous_completed = matrix_completed
        server_date = _parse_http_date(
            matrix["response_date"],
            "receipt.matrices[$index].response_date",
        )
        matrix_started - Second(MAX_SERVER_CLOCK_SKEW_SECONDS) <=
            server_date <=
            returned + Second(MAX_SERVER_CLOCK_SKEW_SECONDS) ||
            fail("receipt.matrices[$index].response_date", "has invalid skew")
    end
    _receipt_bundle_hash(document, profile) == raw_bundle["bundle_sha256"] ||
        fail("receipt.raw_bundle.bundle_sha256", "does not verify")
    for key in REQUIRED_FALSE_GATES
        _expect_bool(gates[key], false, "receipt.gates.$key")
    end
    _expect_bool(
        gates["training_use_allowed"],
        false,
        "receipt.gates.training_use_allowed",
    )
    _expect_bool(
        gates["research_diagnostic_allowed"],
        true,
        "receipt.gates.research_diagnostic_allowed",
    )
    return (
        receipt_sha256 = receipt_digest,
        bundle_sha256 = raw_bundle["bundle_sha256"],
        capture_id = artifact["receipt_id"],
        capture_local_date = capture_date,
        research_diagnostic_allowed = true,
        ready = false,
    )
end

function _canonical_raw_root(raw_root)
    text = String(raw_root)
    isabspath(text) || fail("raw_root", "must be absolute")
    normpath(text) == text ||
        fail("raw_root", "must be normalized and traversal-free")
    _reject_symlink_chain(text, "raw_root")
    isdir(text) || fail("raw_root", "must already exist as a directory")
    realpath(text) == text ||
        fail("raw_root", "must be its canonical filesystem path")
    relative = relpath(text, REPOSITORY_ROOT)
    inside_repository =
        relative == "." ||
        (
        !startswith(relative, ".." * Base.Filesystem.path_separator) &&
            relative != ".." &&
            !isabspath(relative)
    )
    if inside_repository
        command = Cmd(
            [
                "git",
                "-C",
                REPOSITORY_ROOT,
                "check-ignore",
                "--quiet",
                "--no-index",
                "--",
                text,
            ],
        )
        process = try
            run(ignorestatus(command))
        catch error
            fail(
                "raw_root",
                "cannot verify Git-ignore status ($(sprint(showerror, error)))",
            )
        end
        success(process) ||
            fail(
            "raw_root",
            "inside-repository storage must be matched by Git ignore rules",
        )
    end
    return text
end

function _write_exact(path, bytes)
    (ispath(path) || islink(path)) &&
        fail("bundle staging", "refuses to overwrite $path")
    flags =
        Base.Filesystem.JL_O_WRONLY |
        Base.Filesystem.JL_O_CREAT |
        Base.Filesystem.JL_O_EXCL |
        Base.Filesystem.JL_O_CLOEXEC
    io = try
        Base.Filesystem.open(path, flags, 0o600)
    catch error
        fail(
            "bundle staging",
            "cannot create $path exclusively ($(sprint(showerror, error)))",
        )
    end
    try
        write(io, bytes)
        flush(io)
        ccall(:fsync, Cint, (Cint,), fd(io)) == 0 ||
            fail("bundle staging", "fsync failed for $path")
    finally
        close(io)
    end
    read(path) == bytes ||
        fail("bundle staging", "read-back differs at $path")
    return path
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
            "platform lacks the sealed exclusive-rename primitive",
        )
    end
    result == 0 && return true
    error_number = Base.Libc.errno()
    error_number == Base.Libc.EEXIST && return false
    return fail(
        "capture storage",
        "exclusive rename failed with errno $error_number " *
            "($(Base.Libc.strerror(error_number)))",
    )
end

function _bundle_expected_names(document)
    names = Set(String(matrix["stored_filename"]) for matrix in document["matrices"])
    receipt_digest = document["artifact"]["receipt_sha256"]
    push!(names, "receipt-self-sha256-$receipt_digest.toml")
    return names
end

function _validate_capture_bundle(
        bundle_path::AbstractString;
        validate_storage_path::Bool = true,
        profile::SourceProfile = PROFILE,
    )
    path = String(bundle_path)
    isabspath(path) || fail("bundle", "path must be absolute")
    normpath(path) == path || fail("bundle", "path must be normalized")
    _reject_symlink_chain(path, "bundle")
    isdir(path) || fail("bundle", "must be a directory")
    stat(path).mode & 0o777 == 0o555 ||
        fail("bundle", "directory mode must be exactly 0555")
    names = readdir(path; sort = true)
    length(names) == EXPECTED_FILE_COUNT + 1 ||
        fail("bundle", "must contain five matrices and one receipt")
    receipt_names =
        filter(name -> occursin(RECEIPT_FILENAME_PATTERN, name), names)
    length(receipt_names) == 1 ||
        fail("bundle", "must contain one self-hashed receipt")
    receipt_name = only(receipt_names)
    receipt_path = joinpath(path, receipt_name)
    isfile(receipt_path) && !islink(receipt_path) ||
        fail("bundle.receipt", "must be a regular non-symlink file")
    receipt_metadata = stat(receipt_path)
    receipt_metadata.mode & 0o777 == 0o444 ||
        fail("bundle.receipt", "mode must be exactly 0444")
    receipt_metadata.nlink == 1 ||
        fail("bundle.receipt", "hard-link aliases are forbidden")
    receipt_bytes = read(receipt_path)
    document = try
        TOML.parse(String(copy(receipt_bytes)))
    catch error
        fail(
            "bundle.receipt",
            "is invalid TOML ($(sprint(showerror, error)))",
        )
    end
    receipt_bytes == _toml_bytes(document) ||
        fail("bundle.receipt", "is not canonical TOML")
    validated = _validate_receipt(document, profile)
    receipt_name ==
        "receipt-self-sha256-$(validated.receipt_sha256).toml" ||
        fail("bundle.receipt", "filename does not match self-hash")
    Set(names) == _bundle_expected_names(document) ||
        fail("bundle", "contains an unexpected or missing file")
    for (index, (matrix, expectation)) in
        enumerate(zip(document["matrices"], profile.series))
        raw_path = joinpath(path, matrix["stored_filename"])
        isfile(raw_path) && !islink(raw_path) ||
            fail("bundle.matrices[$index]", "must be a regular file")
        metadata = stat(raw_path)
        metadata.mode & 0o777 == 0o444 ||
            fail("bundle.matrices[$index]", "mode must be exactly 0444")
        metadata.nlink == 1 ||
            fail(
            "bundle.matrices[$index]",
            "hard-link aliases are forbidden",
        )
        bytes = read(raw_path)
        length(bytes) == matrix["observed_byte_count"] ||
            fail("bundle.matrices[$index]", "byte count differs")
        sha256_hex(bytes) == matrix["observed_raw_sha256"] ||
            fail("bundle.matrices[$index]", "SHA-256 differs")
        zip = _validate_xlsx_zip(bytes, "bundle.matrices[$index]")
        zip.entry_count == matrix["zip_entry_count"] ||
            fail("bundle.matrices[$index]", "ZIP entry count differs")
        basename(raw_path) ==
            _raw_filename(
            expectation.series_id,
            matrix["observed_raw_sha256"],
        ) ||
            fail("bundle.matrices[$index]", "filename differs")
    end
    if validate_storage_path
        basename(path) ==
            "receipt-self-sha256-$(validated.receipt_sha256)" ||
            fail("bundle", "directory name differs from receipt self-hash")
        basename(dirname(path)) ==
            "bundle-sha256-$(validated.bundle_sha256)" ||
            fail("bundle", "parent does not match bundle SHA-256")
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
    _validate_capture_bundle(bundle_path)

function _install_bundle(
        raw_root,
        fetched_matrices,
        receipt;
        profile::SourceProfile = PROFILE,
        rename_exclusive::Function = _rename_exclusive,
    )
    root = _canonical_raw_root(raw_root)
    validated_receipt = _validate_receipt(receipt, profile)
    parent = joinpath(
        root,
        "philadelphia_fed",
        "rtdsm",
        "quarterly",
        "captures",
        "bundle-sha256-$(validated_receipt.bundle_sha256)",
    )
    mkpath(parent)
    _reject_symlink_chain(parent, "capture storage")
    realpath(parent) == parent ||
        fail("capture storage", "parent is not canonical")
    target = joinpath(
        parent,
        "receipt-self-sha256-$(validated_receipt.receipt_sha256)",
    )
    if ispath(target) || islink(target)
        islink(target) &&
            fail("capture storage", "target collision is a symlink")
        return _validate_capture_bundle(target; profile = profile)
    end
    staging = mktempdir(parent; prefix = ".capture-staging-")
    moved = false
    try
        for (fetched, matrix) in zip(fetched_matrices, receipt["matrices"])
            _write_exact(
                joinpath(staging, matrix["stored_filename"]),
                fetched.raw_bytes,
            )
        end
        receipt_path = joinpath(
            staging,
            "receipt-self-sha256-$(validated_receipt.receipt_sha256).toml",
        )
        _write_exact(receipt_path, _toml_bytes(receipt))
        for name in readdir(staging)
            chmod(joinpath(staging, name), 0o444)
        end
        chmod(staging, 0o555)
        staged = _validate_capture_bundle(
            staging;
            validate_storage_path = false,
            profile = profile,
        )
        staged.receipt_file_sha256 == receipt_file_sha256(receipt) ||
            fail("bundle staging", "receipt file hash drifted")
        if !rename_exclusive(staging, target)
            if ispath(target) || islink(target)
                islink(target) &&
                    fail("capture storage", "racing target is a symlink")
                return _validate_capture_bundle(target; profile = profile)
            end
            fail(
                "capture storage",
                "exclusive rename reported collision without a valid target",
            )
        end
        moved = true
        return _validate_capture_bundle(target; profile = profile)
    finally
        if !moved && (ispath(staging) || islink(staging))
            if isdir(staging) && !islink(staging)
                chmod(staging, 0o755)
                for name in readdir(staging)
                    child = joinpath(staging, name)
                    !islink(child) && chmod(child, 0o644)
                end
            end
            rm(staging; recursive = true, force = true)
        end
    end
end

function _validate_live_attestations(
        live,
        terms_reviewed_local_date,
        research_purpose_attestation,
        instant::DateTime,
    )
    live === true || fail("live", "must be explicitly true")
    research_purpose_attestation == RESEARCH_PURPOSE_ATTESTATION ||
        fail(
        "research_purpose_attestation",
        "must equal $RESEARCH_PURPOSE_ATTESTATION",
    )
    review_date = terms_reviewed_local_date isa Date ?
        terms_reviewed_local_date :
        tryparse(Date, String(terms_reviewed_local_date))
    review_date === nothing &&
        fail("terms_reviewed_local_date", "must be canonical YYYY-MM-DD")
    local_date = new_york_local_date(instant)
    review_date == local_date ||
        fail(
        "terms_reviewed_local_date",
        "must equal current America/New_York date $local_date",
    )
    return review_date, local_date
end

function _capture_from_fetched(
        fetched_matrices,
        raw_root;
        live,
        terms_reviewed_local_date,
        research_purpose_attestation,
        capture_started_at_utc::DateTime,
        capture_completed_at_utc::DateTime,
        rename_exclusive::Function = _rename_exclusive,
    )
    review_date, local_date = _validate_live_attestations(
        live,
        terms_reviewed_local_date,
        research_purpose_attestation,
        capture_started_at_utc,
    )
    new_york_local_date(capture_completed_at_utc) == local_date ||
        fail("capture_local_date", "changed during the five-file transaction")
    validate_fetched_set(fetched_matrices, PROFILE)
    receipt = _build_receipt(
        fetched_matrices,
        PROFILE;
        terms_reviewed_local_date = review_date,
        capture_local_date = local_date,
        capture_started_at_utc = capture_started_at_utc,
        capture_completed_at_utc = capture_completed_at_utc,
    )
    return _install_bundle(
        raw_root,
        fetched_matrices,
        receipt;
        profile = PROFILE,
        rename_exclusive = rename_exclusive,
    )
end

function capture_research_snapshot(
        raw_root;
        live = false,
        terms_reviewed_local_date = "",
        research_purpose_attestation = "",
    )
    started = now(UTC)
    review_date, local_date = _validate_live_attestations(
        live,
        terms_reviewed_local_date,
        research_purpose_attestation,
        started,
    )
    _canonical_raw_root(raw_root)
    fetched = fetch_official_set(PROFILE)
    completed = now(UTC)
    new_york_local_date(completed) == local_date ||
        fail("capture_local_date", "changed during the five-file transaction")
    return _capture_from_fetched(
        fetched,
        raw_root;
        live = true,
        terms_reviewed_local_date = review_date,
        research_purpose_attestation = RESEARCH_PURPOSE_ATTESTATION,
        capture_started_at_utc = started,
        capture_completed_at_utc = completed,
    )
end

end
