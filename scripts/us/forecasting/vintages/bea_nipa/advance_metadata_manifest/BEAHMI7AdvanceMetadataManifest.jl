module BEAHMI7AdvanceMetadataManifest

using Dates
using SHA
using TOML

export CANONICALIZATION,
    CONTRACT_ID,
    DEFAULT_MANIFEST_PATH,
    EXPECTED_CONTENT_SHA256,
    MANIFEST_SCHEMA_VERSION,
    MetadataManifestError,
    computed_content_sha256,
    load_manifest,
    manifest_artifact,
    validate_manifest

const DEFAULT_MANIFEST_PATH = joinpath(
    @__DIR__,
    "bea_hmi7_advance_manifest_2011q3_2021q2.toml",
)
const MANIFEST_SCHEMA_VERSION =
    "beforeit-us-bea-hmi7-advance-metadata-manifest.v1"
const CONTRACT_ID =
    "bea-hmi7-earliest-complete-2011q3-2021q2-present-day-metadata.v1"
const CANONICALIZATION =
    "sorted_typed_v1_excluding_artifact_content_sha256"
const EXPECTED_CONTENT_SHA256 =
    "186903041b649480b34a130f8c7518fb53a875e5b02ce4d6c3ee674080d5b824"

const HMI7_ROOT_URL =
    "https://apps.bea.gov/histdata/core/data/" *
    "Fea_DisplayChildrenC/?HistMainId=7&getFiles=false&getDirs=true"
const HMI7_ROOT_BYTES = 100_290
const HMI7_ROOT_SHA256 =
    "f818afb3d7c95e9a1534373a17fd479b53db569575083c41c3744d03ab988d3d"
const RELEASE_SITEMAP_URL = "https://www.bea.gov/releases/sitemap.xml"
const RELEASE_SITEMAP_BYTES = 345_421
const RELEASE_SITEMAP_SHA256 =
    "10bb56c05889615103c866cd5a24dfa3c0050d953990458bf0b201a593af0f78"
const OBSERVED_DATE = "2026-08-07"

const ARCHIVE_INTERNAL_PREFIX =
    "/Inetpub/wwwroot/website/website/HistData/Files/Releases/" *
    "GDP_and_PI\\"
const EVENT_PAGE_PREFIX = "https://www.bea.gov/news/"
const EVENT_PDF_PREFIX = "https://www.bea.gov/sites/default/files/"
const EVENT_TIMEZONE = "America/New_York"
const AVAILABILITY_STATUS =
    "HISTORICAL_EXACT_WORKBOOK_BYTE_AVAILABILITY_NOT_PROVEN"

const HASH_PATTERN = r"^[0-9a-f]{64}$"
const DATE_PATTERN = r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
const QUARTER_PATTERN = r"^[0-9]{4}Q[1-4]$"
const DIRECTORY_ID_PATTERN = r"^[1-9][0-9]*$"
const RELEASE_NUMBER_PATTERN = r"^[0-9]{2}-[0-9]{2}$"
const LOCAL_TIMESTAMP_PATTERN =
    r"^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})([+-])([0-9]{2}):([0-9]{2})$"
const UTC_TIMESTAMP_PATTERN =
    r"^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})Z$"
const LABEL_PATTERN =
    r"^(Advance|Initial)_([A-Za-z]+)-([0-9]{1,2})-([0-9]{4})$"
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"

const ROOT_KEYS = (
    "artifact",
    "contract",
    "anchors",
    "gates",
    "releases",
)
const ARTIFACT_KEYS = (
    "schema_version",
    "canonicalization",
    "content_sha256",
)
const CONTRACT_KEYS = (
    "contract_id",
    "observed_date",
    "snapshot_class",
    "release_count",
    "first_reference_period",
    "last_reference_period",
    "archive_internal_prefix",
    "event_timezone",
    "availability_status",
    "metadata_only",
    "network_access_allowed",
    "workbook_bytes_acquired",
    "pdf_bytes_acquired",
)
const ANCHOR_KEYS = ("hmi7_root", "release_sitemap")
const ANCHOR_RECORD_KEYS = (
    "url",
    "byte_count",
    "sha256",
    "observed_date",
    "body_stored",
)
const GATE_KEYS = (
    "historical_workbook_availability_proven",
    "strict_origin_admissible",
    "empirical_forecast_execution_allowed",
    "promotion_eligible",
    "production_scoring_allowed",
    "ready",
)
const RELEASE_KEYS = (
    "sequence",
    "reference_period",
    "estimate_family",
    "directory_id",
    "archive_path",
    "archive_label",
    "archive_folder_date",
    "event_timestamp_local",
    "event_timestamp_utc",
    "event_timezone_iana",
    "event_timezone_abbreviation",
    "bea_release_number",
    "event_page_url",
    "event_pdf_url",
    "section1_filename",
    "section2_filename",
    "workbook_extension",
    "update_type",
    "irregular_flag",
    "irregular_evidence_url",
    "folder_lag_days",
    "availability_status",
    "strict_origin_available",
)

const UPDATE_TYPES = Set(
    [
        "none",
        "annual_revision",
        "annual_update",
        "comprehensive_revision",
        "comprehensive_update",
    ],
)
const EXPECTED_UPDATE_TYPES = Dict(
    "2012Q2" => "annual_revision",
    "2013Q2" => "comprehensive_revision",
    "2014Q2" => "annual_revision",
    "2015Q2" => "annual_revision",
    "2016Q2" => "annual_update",
    "2017Q2" => "annual_update",
    "2018Q2" => "comprehensive_update",
    "2019Q2" => "annual_update",
    "2020Q2" => "annual_update",
    "2021Q2" => "annual_update",
)
const EXPECTED_IRREGULAR = Dict(
    "2013Q3" => (
        "shutdown_delayed",
        "https://www.bea.gov/sites/default/files/newsreleases/" *
            "national/gdp/2013/pdf/tech3q13_adv.pdf",
    ),
    "2018Q4" => (
        "shutdown_initial_replaces_advance_and_second",
        "https://www.bea.gov/news/2019/" *
            "initial-gross-domestic-product-4th-quarter-and-annual-2018",
    ),
)
const MONTH_NUMBERS = Dict(
    "January" => 1,
    "February" => 2,
    "March" => 3,
    "April" => 4,
    "May" => 5,
    "June" => 6,
    "July" => 7,
    "August" => 8,
    "September" => 9,
    "October" => 10,
    "November" => 11,
    "December" => 12,
)

struct MetadataManifestError <: Exception
    message::String
end

Base.showerror(io::IO, error::MetadataManifestError) =
    print(io, error.message)

fail(location, message) =
    throw(MetadataManifestError("$location: $message"))

function _quarter_sequence(first_year, first_quarter, last_year, last_quarter)
    result = String[]
    year = first_year
    quarter = first_quarter
    while (year, quarter) <= (last_year, last_quarter)
        push!(result, "$(year)Q$(quarter)")
        quarter += 1
        if quarter == 5
            year += 1
            quarter = 1
        end
    end
    return result
end

const EXPECTED_REFERENCE_PERIODS =
    _quarter_sequence(2011, 3, 2021, 2)

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    expected_set = Set(String.(expected))
    missing = sort!(collect(setdiff(expected_set, actual)))
    unknown = sort!(collect(setdiff(actual, expected_set)))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown keys: $(join(unknown, ", "))")
    return table
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
    return text
end

function expect_exact(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function expect_integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    number = Int(value)
    number >= minimum || fail(location, "must be at least $minimum")
    return number
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

function expect_date(value, location)
    text = expect_string(value, location)
    occursin(DATE_PATTERN, text) ||
        fail(location, "must use YYYY-MM-DD")
    date = try
        Date(text)
    catch
        fail(location, "must be a valid calendar date")
    end
    string(date) == text || fail(location, "must be a canonical date")
    return date
end

function expect_https_url(value, prefix, location)
    url = expect_string(value, location)
    startswith(url, prefix) ||
        fail(location, "must use the exact official prefix $prefix")
    occursin('?', url) &&
        fail(location, "must not contain a query")
    occursin('#', url) &&
        fail(location, "must not contain a fragment")
    any(isspace, url) &&
        fail(location, "must not contain whitespace")
    return url
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
    elseif value isa AbstractVector
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

function _canonical_content_bytes(value)
    manifest = deepcopy(expect_table(value, "manifest"))
    artifact =
        expect_table(get(manifest, "artifact", nothing), "manifest.artifact")
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, manifest)
    return take!(io)
end

computed_content_sha256(value) =
    bytes2hex(sha256(_canonical_content_bytes(value)))

function _parse_local_timestamp(value, location)
    text = expect_string(value, location)
    matched = match(LOCAL_TIMESTAMP_PATTERN, text)
    matched === nothing ||
        length(matched.captures) == 4 ||
        fail(location, "must be an RFC 3339 timestamp with numeric offset")
    matched === nothing &&
        fail(location, "must be an RFC 3339 timestamp with numeric offset")
    local_time = try
        DateTime(matched.captures[1], TIMESTAMP_FORMAT)
    catch
        fail(location, "must contain a valid local date and time")
    end
    hours = parse(Int, matched.captures[3])
    minutes = parse(Int, matched.captures[4])
    hours <= 23 || fail(location, "offset hour is out of range")
    minutes <= 59 || fail(location, "offset minute is out of range")
    sign = matched.captures[2] == "+" ? 1 : -1
    offset_seconds = sign * (hours * 60 + minutes) * 60
    return (; text, local_time, offset_seconds)
end

function _parse_utc_timestamp(value, location)
    text = expect_string(value, location)
    matched = match(UTC_TIMESTAMP_PATTERN, text)
    matched === nothing &&
        fail(location, "must use RFC 3339 UTC seconds with a trailing Z")
    timestamp = try
        DateTime(matched.captures[1], TIMESTAMP_FORMAT)
    catch
        fail(location, "must contain a valid UTC date and time")
    end
    return (; text, timestamp)
end

function _nth_sunday(year, month, occurrence)
    first = Date(year, month, 1)
    days_to_sunday = mod(7 - dayofweek(first), 7)
    return first + Day(days_to_sunday + 7 * (occurrence - 1))
end

function _new_york_offset_seconds(date::Date)
    start_date = _nth_sunday(year(date), 3, 2)
    end_date = _nth_sunday(year(date), 11, 1)
    return start_date <= date < end_date ? -4 * 60 * 60 : -5 * 60 * 60
end

function _expected_event_month(reference_period)
    quarter = parse(Int, reference_period[end:end])
    reference_period == "2013Q3" && return 11
    reference_period == "2018Q4" && return 2
    return (4, 7, 10, 1)[quarter]
end

function _parse_archive_label(label, location)
    matched = match(LABEL_PATTERN, label)
    matched === nothing &&
        fail(location, "does not use the recognized label/date grammar")
    family = lowercase(matched.captures[1])
    month_name = matched.captures[2]
    haskey(MONTH_NUMBERS, month_name) ||
        fail(location, "contains an unsupported month name")
    day = parse(Int, matched.captures[3])
    year_number = parse(Int, matched.captures[4])
    date = try
        Date(year_number, MONTH_NUMBERS[month_name], day)
    catch
        fail(location, "contains an invalid calendar date")
    end
    return (; family, date)
end

function _validate_artifact(manifest)
    artifact = expect_exact_keys(
        manifest["artifact"],
        ARTIFACT_KEYS,
        "manifest.artifact",
    )
    expect_exact(
        artifact["schema_version"],
        MANIFEST_SCHEMA_VERSION,
        "manifest.artifact.schema_version",
    )
    expect_exact(
        artifact["canonicalization"],
        CANONICALIZATION,
        "manifest.artifact.canonicalization",
    )
    declared =
        expect_hash(artifact["content_sha256"], "manifest.artifact.content_sha256")
    computed = computed_content_sha256(manifest)
    declared == computed ||
        fail(
        "manifest.artifact.content_sha256",
        "declared $declared does not match computed $computed",
    )
    return declared
end

function _validate_contract(manifest)
    contract = expect_exact_keys(
        manifest["contract"],
        CONTRACT_KEYS,
        "manifest.contract",
    )
    expect_exact(
        contract["contract_id"],
        CONTRACT_ID,
        "manifest.contract.contract_id",
    )
    expect_exact(
        contract["observed_date"],
        OBSERVED_DATE,
        "manifest.contract.observed_date",
    )
    expect_exact(
        contract["snapshot_class"],
        "OFFICIAL_BEA_HMI7_PRESENT_DAY_ARCHIVE_SNAPSHOT",
        "manifest.contract.snapshot_class",
    )
    expect_exact(
        contract["release_count"],
        40,
        "manifest.contract.release_count",
    )
    expect_exact(
        contract["first_reference_period"],
        first(EXPECTED_REFERENCE_PERIODS),
        "manifest.contract.first_reference_period",
    )
    expect_exact(
        contract["last_reference_period"],
        last(EXPECTED_REFERENCE_PERIODS),
        "manifest.contract.last_reference_period",
    )
    expect_exact(
        contract["archive_internal_prefix"],
        ARCHIVE_INTERNAL_PREFIX,
        "manifest.contract.archive_internal_prefix",
    )
    expect_exact(
        contract["event_timezone"],
        EVENT_TIMEZONE,
        "manifest.contract.event_timezone",
    )
    expect_exact(
        contract["availability_status"],
        AVAILABILITY_STATUS,
        "manifest.contract.availability_status",
    )
    expect_exact(
        contract["metadata_only"],
        true,
        "manifest.contract.metadata_only",
    )
    for key in (
            "network_access_allowed",
            "workbook_bytes_acquired",
            "pdf_bytes_acquired",
        )
        expect_exact(
            expect_bool(contract[key], "manifest.contract.$key"),
            false,
            "manifest.contract.$key",
        )
    end
    return contract
end

function _validate_anchor(
        value,
        location;
        url,
        byte_count,
        digest,
    )
    anchor = expect_exact_keys(value, ANCHOR_RECORD_KEYS, location)
    expect_exact(anchor["url"], url, "$location.url")
    expect_exact(anchor["byte_count"], byte_count, "$location.byte_count")
    expect_exact(
        expect_hash(anchor["sha256"], "$location.sha256"),
        digest,
        "$location.sha256",
    )
    expect_exact(
        anchor["observed_date"],
        OBSERVED_DATE,
        "$location.observed_date",
    )
    expect_exact(
        expect_bool(anchor["body_stored"], "$location.body_stored"),
        false,
        "$location.body_stored",
    )
    return anchor
end

function _validate_anchors(manifest)
    anchors =
        expect_exact_keys(manifest["anchors"], ANCHOR_KEYS, "manifest.anchors")
    _validate_anchor(
        anchors["hmi7_root"],
        "manifest.anchors.hmi7_root";
        url = HMI7_ROOT_URL,
        byte_count = HMI7_ROOT_BYTES,
        digest = HMI7_ROOT_SHA256,
    )
    _validate_anchor(
        anchors["release_sitemap"],
        "manifest.anchors.release_sitemap";
        url = RELEASE_SITEMAP_URL,
        byte_count = RELEASE_SITEMAP_BYTES,
        digest = RELEASE_SITEMAP_SHA256,
    )
    return anchors
end

function _validate_gates(manifest)
    gates = expect_exact_keys(manifest["gates"], GATE_KEYS, "manifest.gates")
    for key in GATE_KEYS
        expect_exact(
            expect_bool(gates[key], "manifest.gates.$key"),
            false,
            "manifest.gates.$key",
        )
    end
    return gates
end

function _validate_release(record, expected_reference_period, expected_sequence)
    location = "manifest.releases[$expected_sequence]"
    row = expect_exact_keys(record, RELEASE_KEYS, location)
    expect_exact(
        expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
        expected_sequence,
        "$location.sequence",
    )
    reference_period =
        expect_string(row["reference_period"], "$location.reference_period")
    occursin(QUARTER_PATTERN, reference_period) ||
        fail("$location.reference_period", "must use YYYYQn")
    expect_exact(
        reference_period,
        expected_reference_period,
        "$location.reference_period",
    )
    reference_year = parse(Int, reference_period[1:4])
    reference_quarter = parse(Int, reference_period[end:end])

    family = expect_string(row["estimate_family"], "$location.estimate_family")
    expected_family = reference_period == "2018Q4" ? "initial" : "advance"
    expect_exact(family, expected_family, "$location.estimate_family")

    directory_id =
        expect_string(row["directory_id"], "$location.directory_id")
    occursin(DIRECTORY_ID_PATTERN, directory_id) ||
        fail("$location.directory_id", "must be a canonical positive ID")

    archive_label =
        expect_string(row["archive_label"], "$location.archive_label")
    parsed_label = _parse_archive_label(
        archive_label,
        "$location.archive_label",
    )
    expect_exact(
        parsed_label.family,
        family,
        "$location.archive_label",
    )
    folder_date =
        expect_date(row["archive_folder_date"], "$location.archive_folder_date")
    parsed_label.date == folder_date ||
        fail(
        "$location.archive_folder_date",
        "does not equal the date encoded in archive_label",
    )

    quarter_component =
        reference_period == "2014Q3" ? "q3" : "Q$reference_quarter"
    expected_archive_prefix =
        ARCHIVE_INTERNAL_PREFIX *
        string(reference_year) *
        "\\" *
        quarter_component *
        "\\"
    archive_path =
        expect_string(row["archive_path"], "$location.archive_path")
    startswith(archive_path, expected_archive_prefix) ||
        fail(
        "$location.archive_path",
        "does not preserve the exact year/quarter path case",
    )
    expect_exact(
        archive_path,
        expected_archive_prefix * archive_label,
        "$location.archive_path",
    )

    event_timestamp_local = expect_string(
        row["event_timestamp_local"],
        "$location.event_timestamp_local",
    )
    event_timestamp_utc = expect_string(
        row["event_timestamp_utc"],
        "$location.event_timestamp_utc",
    )
    local_event = _parse_local_timestamp(
        event_timestamp_local,
        "$location.event_timestamp_local",
    )
    utc_event = _parse_utc_timestamp(
        event_timestamp_utc,
        "$location.event_timestamp_utc",
    )
    Time(local_event.local_time) == Time(8, 30) ||
        fail("$location.event_timestamp_local", "must be 08:30:00")
    event_date = Date(local_event.local_time)
    expected_event_year =
        reference_quarter == 4 ? reference_year + 1 : reference_year
    year(event_date) == expected_event_year ||
        fail("$location.event_timestamp_local", "has the wrong event year")
    month(event_date) == _expected_event_month(reference_period) ||
        fail("$location.event_timestamp_local", "has the wrong event month")
    expected_offset = _new_york_offset_seconds(event_date)
    local_event.offset_seconds == expected_offset ||
        fail(
        "$location.event_timestamp_local",
        "offset does not match audited America/New_York rules",
    )
    expected_utc =
        local_event.local_time - Second(local_event.offset_seconds)
    utc_event.timestamp == expected_utc ||
        fail(
        "$location.event_timestamp_utc",
        "does not equal the offset-normalized local event timestamp",
    )
    event_timezone_iana = expect_string(
        row["event_timezone_iana"],
        "$location.event_timezone_iana",
    )
    expect_exact(
        event_timezone_iana,
        EVENT_TIMEZONE,
        "$location.event_timezone_iana",
    )
    expected_abbreviation = expected_offset == -4 * 60 * 60 ? "EDT" : "EST"
    event_timezone_abbreviation = expect_string(
        row["event_timezone_abbreviation"],
        "$location.event_timezone_abbreviation",
    )
    expect_exact(
        event_timezone_abbreviation,
        expected_abbreviation,
        "$location.event_timezone_abbreviation",
    )

    release_number =
        expect_string(row["bea_release_number"], "$location.bea_release_number")
    occursin(RELEASE_NUMBER_PATTERN, release_number) ||
        fail("$location.bea_release_number", "must use YY-NN")
    expected_release_year = lpad(string(mod(year(event_date), 100)), 2, '0')
    startswith(release_number, expected_release_year * "-") ||
        fail(
        "$location.bea_release_number",
        "does not match the event year",
    )

    event_page_url = expect_https_url(
        row["event_page_url"],
        EVENT_PAGE_PREFIX,
        "$location.event_page_url",
    )
    startswith(
        event_page_url,
        EVENT_PAGE_PREFIX * string(year(event_date)) * "/",
    ) || fail("$location.event_page_url", "does not match the event year")
    event_pdf_url = expect_https_url(
        row["event_pdf_url"],
        EVENT_PDF_PREFIX,
        "$location.event_pdf_url",
    )
    endswith(event_pdf_url, ".pdf") ||
        fail("$location.event_pdf_url", "must identify a PDF")

    extension =
        expect_string(row["workbook_extension"], "$location.workbook_extension")
    extension in ("xls", "xlsx") ||
        fail("$location.workbook_extension", "must be xls or xlsx")
    section1_filename = expect_string(
        row["section1_filename"],
        "$location.section1_filename",
    )
    section2_filename = expect_string(
        row["section2_filename"],
        "$location.section2_filename",
    )
    expect_exact(
        section1_filename,
        "Section1all_xls.$extension",
        "$location.section1_filename",
    )
    expect_exact(
        section2_filename,
        "Section2all_xls.$extension",
        "$location.section2_filename",
    )
    expected_extension = expected_sequence <= 24 ? "xls" : "xlsx"
    expect_exact(
        extension,
        expected_extension,
        "$location.workbook_extension",
    )

    update_type = expect_string(row["update_type"], "$location.update_type")
    update_type in UPDATE_TYPES ||
        fail("$location.update_type", "has an unsupported classification")
    expect_exact(
        update_type,
        get(EXPECTED_UPDATE_TYPES, reference_period, "none"),
        "$location.update_type",
    )

    irregular_flag =
        expect_string(row["irregular_flag"], "$location.irregular_flag")
    irregular_evidence_url = expect_string(
        row["irregular_evidence_url"],
        "$location.irregular_evidence_url",
    )
    expected_irregular =
        get(EXPECTED_IRREGULAR, reference_period, ("none", "none"))
    expect_exact(
        irregular_flag,
        expected_irregular[1],
        "$location.irregular_flag",
    )
    expect_exact(
        irregular_evidence_url,
        expected_irregular[2],
        "$location.irregular_evidence_url",
    )

    folder_lag_days = expect_integer(
        row["folder_lag_days"],
        "$location.folder_lag_days";
        minimum = 0,
    )
    actual_lag_days = Dates.value(folder_date - event_date)
    expect_exact(
        folder_lag_days,
        actual_lag_days,
        "$location.folder_lag_days",
    )
    folder_lag_days <= 4 ||
        fail("$location.folder_lag_days", "must not exceed four days")

    availability_status = expect_string(
        row["availability_status"],
        "$location.availability_status",
    )
    expect_exact(
        availability_status,
        AVAILABILITY_STATUS,
        "$location.availability_status",
    )
    strict_origin_available = expect_bool(
        row["strict_origin_available"],
        "$location.strict_origin_available",
    )
    expect_exact(
        strict_origin_available,
        false,
        "$location.strict_origin_available",
    )

    return (;
        sequence = expected_sequence,
        reference_period,
        estimate_family = family,
        directory_id,
        archive_path,
        archive_label,
        archive_folder_date = string(folder_date),
        event_timestamp_local,
        event_timestamp_utc,
        event_timezone_iana,
        event_timezone_abbreviation,
        bea_release_number = release_number,
        event_page_url,
        event_pdf_url,
        section1_filename,
        section2_filename,
        workbook_extension = extension,
        update_type,
        irregular_flag,
        irregular_evidence_url,
        folder_lag_days,
        availability_status,
        strict_origin_available,
    )
end

function _validate_releases(manifest)
    releases = get(manifest, "releases", nothing)
    releases isa AbstractVector ||
        fail("manifest.releases", "must be an array of tables")
    length(releases) == 40 ||
        fail("manifest.releases", "must contain exactly 40 rows")

    validated = [
        _validate_release(record, reference_period, sequence)
            for (sequence, (record, reference_period)) in enumerate(
                zip(releases, EXPECTED_REFERENCE_PERIODS),
            )
    ]

    for field in (
            :reference_period,
            :directory_id,
            :archive_path,
            :archive_label,
            :event_page_url,
            :event_pdf_url,
            :bea_release_number,
        )
        values = getproperty.(validated, field)
        length(values) == length(Set(values)) ||
            fail("manifest.releases", "$(String(field)) values must be unique")
    end
    count(row -> row.estimate_family == "advance", validated) == 39 ||
        fail("manifest.releases", "must contain 39 Advance-family rows")
    count(row -> row.estimate_family == "initial", validated) == 1 ||
        fail("manifest.releases", "must contain one Initial-family row")
    count(row -> row.workbook_extension == "xls", validated) == 24 ||
        fail("manifest.releases", "must contain 24 xls workbook pairs")
    count(row -> row.workbook_extension == "xlsx", validated) == 16 ||
        fail("manifest.releases", "must contain 16 xlsx workbook pairs")
    count(row -> row.update_type == "none", validated) == 30 ||
        fail("manifest.releases", "must contain 30 non-update rows")
    count(
        row -> row.update_type in ("annual_revision", "annual_update"),
        validated,
    ) == 8 ||
        fail("manifest.releases", "must contain eight annual-update rows")
    count(
        row ->
        row.update_type in
            ("comprehensive_revision", "comprehensive_update"),
        validated,
    ) == 2 ||
        fail(
        "manifest.releases",
        "must contain two comprehensive-update rows",
    )
    count(row -> row.irregular_flag != "none", validated) == 2 ||
        fail("manifest.releases", "must contain two irregular rows")
    count(row -> row.folder_lag_days > 0, validated) == 15 ||
        fail(
        "manifest.releases",
        "must contain 15 archive/event date mismatches",
    )
    return validated
end

function _immutable_anchor(anchor)
    return (;
        url = String(anchor["url"]),
        byte_count = Int(anchor["byte_count"]),
        sha256 = String(anchor["sha256"]),
        observed_date = String(anchor["observed_date"]),
        body_stored = Bool(anchor["body_stored"]),
    )
end

function _immutable_validation(root, releases, declared)
    contract = root["contract"]
    anchors = root["anchors"]
    gates = root["gates"]
    return (;
        schema_version = MANIFEST_SCHEMA_VERSION,
        canonicalization = CANONICALIZATION,
        contract = (;
            contract_id = String(contract["contract_id"]),
            observed_date = String(contract["observed_date"]),
            snapshot_class = String(contract["snapshot_class"]),
            release_count = Int(contract["release_count"]),
            first_reference_period =
                String(contract["first_reference_period"]),
            last_reference_period = String(contract["last_reference_period"]),
            archive_internal_prefix =
                String(contract["archive_internal_prefix"]),
            event_timezone = String(contract["event_timezone"]),
            availability_status = String(contract["availability_status"]),
            metadata_only = Bool(contract["metadata_only"]),
            network_access_allowed =
                Bool(contract["network_access_allowed"]),
            workbook_bytes_acquired =
                Bool(contract["workbook_bytes_acquired"]),
            pdf_bytes_acquired = Bool(contract["pdf_bytes_acquired"]),
        ),
        anchors = (;
            hmi7_root = _immutable_anchor(anchors["hmi7_root"]),
            release_sitemap =
                _immutable_anchor(anchors["release_sitemap"]),
        ),
        gates = (;
            historical_workbook_availability_proven =
                Bool(gates["historical_workbook_availability_proven"]),
            strict_origin_admissible =
                Bool(gates["strict_origin_admissible"]),
            empirical_forecast_execution_allowed =
                Bool(gates["empirical_forecast_execution_allowed"]),
            promotion_eligible = Bool(gates["promotion_eligible"]),
            production_scoring_allowed =
                Bool(gates["production_scoring_allowed"]),
            ready = Bool(gates["ready"]),
        ),
        releases = Tuple(releases),
        content_sha256 = String(declared),
    )
end

"""
    validate_manifest(manifest)

Validate the offline BEA HMI7 metadata contract. The compiled semantic-content
pin is mandatory, so changing a row and recomputing the self-hash cannot
silently redefine the sealed inventory. The returned view contains only
immutable named tuples and tuples; it never aliases the caller's mutable TOML
document.
"""
function validate_manifest(manifest)
    root = expect_exact_keys(manifest, ROOT_KEYS, "manifest")
    _validate_contract(root)
    _validate_anchors(root)
    _validate_gates(root)
    releases = _validate_releases(root)
    declared = _validate_artifact(root)
    declared == EXPECTED_CONTENT_SHA256 ||
        fail(
        "manifest.artifact.content_sha256",
        "does not match the compiled sealed-contract pin",
    )
    return _immutable_validation(root, releases, declared)
end

function _read_manifest(path)
    absolute = abspath(String(path))
    isfile(absolute) || fail("manifest", "file does not exist: $absolute")
    islink(absolute) &&
        fail("manifest", "must not be a symbolic link")
    bytes = try
        read(absolute)
    catch error
        fail("manifest", "could not read file: $(sprint(showerror, error))")
    end
    document = try
        TOML.parse(String(copy(bytes)))
    catch error
        fail("manifest", "could not parse TOML: $(sprint(showerror, error))")
    end
    return (; absolute, bytes, document)
end

"""
    load_manifest([path])

Read one TOML byte sequence, parse it, and validate it without network access.
"""
function load_manifest(path::AbstractString = DEFAULT_MANIFEST_PATH)
    source = _read_manifest(path)
    return validate_manifest(source.document)
end

"""
    manifest_artifact([path])

Return an immutable validated view, semantic self-hash, immutable canonical
content, and physical file hash. No external resource is opened.
"""
function manifest_artifact(path::AbstractString = DEFAULT_MANIFEST_PATH)
    source = _read_manifest(path)
    validation = validate_manifest(source.document)
    return (;
        path = source.absolute,
        schema_version = validation.schema_version,
        canonicalization = validation.canonicalization,
        contract = validation.contract,
        anchors = validation.anchors,
        gates = validation.gates,
        releases = validation.releases,
        content_sha256 = validation.content_sha256,
        canonical_content =
            String(_canonical_content_bytes(source.document)),
        file_sha256 = bytes2hex(sha256(source.bytes)),
        file_byte_count = length(source.bytes),
    )
end

end
