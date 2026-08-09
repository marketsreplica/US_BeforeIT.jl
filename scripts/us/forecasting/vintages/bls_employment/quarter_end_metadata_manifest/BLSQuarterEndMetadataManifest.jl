module BLSQuarterEndMetadataManifest

using Dates
using SHA
using TOML

export ARTIFACT_PROVENANCE_STATES,
    CANONICALIZATION,
    CONTRACT_ID,
    DEFAULT_MANIFEST_PATH,
    ECONOMIC_VINTAGE_STATES,
    EXPECTED_CONTENT_SHA256,
    MANIFEST_SCHEMA_VERSION,
    SOURCE_ROLES,
    BLSQuarterEndMetadataError,
    computed_content_sha256,
    load_manifest,
    manifest_artifact,
    validate_manifest

const DEFAULT_MANIFEST_PATH = joinpath(
    @__DIR__,
    "bls_employment_quarter_end_manifest_2015q1_2024q4.toml",
)
const MANIFEST_SCHEMA_VERSION =
    "beforeit-us-bls-employment-quarter-end-metadata-manifest.v1"
const CONTRACT_ID =
    "bls-employment-quarter-end-2015q1-2024q4-official-archive-routes.v1"
const CANONICALIZATION =
    "sorted_typed_length_aware_v1_excluding_artifact_content_sha256"
const EXPECTED_CONTENT_SHA256 =
    "e4db93f8d938a127f642034151710ea1c5464eba6561c236b225415171e9ac1f"

const SOURCE_AGENCY = "U.S. Bureau of Labor Statistics"
const PUBLICATION_NAME = "Employment Situation"
const ARCHIVE_INDEX_URL =
    "https://www.bls.gov/bls/news-release/empsit.htm"
const ARCHIVE_URL_PREFIX =
    "https://www.bls.gov/news.release/archives/empsit_"
const EVENT_TIMEZONE = "America/New_York"
const OBSERVED_DATE = "2026-08-07"
const SNAPSHOT_CLASS =
    "OFFICIAL_BLS_ARCHIVE_RECONSTRUCTION_METADATA"
const EMBARGO_BASIS = "DOCUMENT_STATED_EMBARGO"
const NO_CORRECTION_STATE =
    "NO_CORRECTION_IDENTIFIED_IN_SURVEY"
const TARGET_UNAFFECTED_STATE =
    "TARGET_SCOPE_STATED_UNAFFECTED"

const ECONOMIC_VINTAGE_STATES = (
    "FIRST_PRELIMINARY",
    "SECOND_PRELIMINARY",
    "THIRD_SAMPLE_BASED",
    "ANNUAL_BENCHMARK_REVISED",
    "ANNUAL_SA_REVISED",
    "POPULATION_CONTROL_BREAK",
    "UNKNOWN_REVISION_STATE",
)
const ARTIFACT_PROVENANCE_STATES = (
    "FIRST_PUBLIC_BYTES_VERIFIED",
    "OFFICIAL_ARCHIVE_RECONSTRUCTION",
    "REISSUED_CORRECTED",
    "UNKNOWN_FIRST_STATE",
    "MISSING_ROUTE",
    "SKIPPED_NOT_PUBLISHED",
)
const SOURCE_ROLES = (
    "PRIMARY_VALUE_SOURCE",
    "PRIMARY_ARTIFACT_EVIDENCE",
    "CROSSCHECK_ONLY",
    "NOT_USED",
    "QUARANTINED",
)

const EXACT_RELEASE_KEYS = (
    "04032015",
    "07022015",
    "10022015",
    "01082016",
    "04012016",
    "07082016",
    "10072016",
    "01062017",
    "04072017",
    "07072017",
    "10062017",
    "01052018",
    "04062018",
    "07062018",
    "10052018",
    "01042019",
    "04052019",
    "07052019",
    "10042019",
    "01102020",
    "04032020",
    "07022020",
    "10022020",
    "01082021",
    "04022021",
    "07022021",
    "10082021",
    "01072022",
    "04012022",
    "07082022",
    "10072022",
    "01062023",
    "04072023",
    "07072023",
    "10062023",
    "01052024",
    "04052024",
    "07052024",
    "10042024",
    "01102025",
)

const HASH_PATTERN = r"^[0-9a-f]{64}$"
const QUARTER_PATTERN = r"^[0-9]{4}Q[1-4]$"
const MONTH_PATTERN = r"^[0-9]{4}-(0[1-9]|1[0-2])$"
const RELEASE_KEY_PATTERN = r"^[0-9]{8}$"
const DATE_PATTERN = r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
const LOCAL_TIMESTAMP_PATTERN =
    r"^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})([+-])([0-9]{2}):([0-9]{2})$"
const UTC_TIMESTAMP_PATTERN =
    r"^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})Z$"
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const RELEASE_KEY_FORMAT = dateformat"mmddyyyy"

const ROOT_KEYS = (
    "artifact",
    "contract",
    "gates",
    "events",
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
    "source_agency",
    "publication_name",
    "archive_index_url",
    "event_count",
    "first_quarter",
    "last_quarter",
    "event_timezone",
    "metadata_only",
    "network_access_allowed",
    "downloader_implemented",
    "parser_implemented",
    "html_bytes_acquired",
    "pdf_bytes_acquired",
    "values_extracted",
    "quarterly_aggregates_created",
    "origins_created",
    "source_inventory_mutation_authorized",
)
const GATE_KEYS = (
    "historical_first_state_verified",
    "historical_availability_proven",
    "strict_origin_admissible",
    "empirical_forecast_execution_allowed",
    "promotion_eligible",
    "production_scoring_allowed",
    "ready",
)
const EVENT_KEYS = (
    "sequence",
    "quarter",
    "reference_month",
    "release_key",
    "release_date",
    "html_url",
    "pdf_url",
    "embargo_basis",
    "event_timestamp_local",
    "event_timestamp_utc",
    "event_timezone_iana",
    "event_timezone_abbreviation",
    "economic_vintage_state",
    "artifact_provenance_state",
    "html_source_role",
    "pdf_source_role",
    "correction_scope_state",
    "first_public_bytes_verified",
    "strict_origin_available",
)

struct BLSQuarterEndMetadataError <: Exception
    message::String
end

Base.showerror(io::IO, error::BLSQuarterEndMetadataError) =
    print(io, error.message)

fail(location, message) =
    throw(BLSQuarterEndMetadataError("$location: $message"))

function _quarter_sequence(first_year, first_quarter, last_year, last_quarter)
    result = String[]
    year_number = first_year
    quarter = first_quarter
    while (year_number, quarter) <= (last_year, last_quarter)
        push!(result, "$(year_number)Q$(quarter)")
        quarter += 1
        if quarter == 5
            year_number += 1
            quarter = 1
        end
    end
    return result
end

const EXPECTED_QUARTERS = Tuple(_quarter_sequence(2015, 1, 2024, 4))

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
    occursin('\0', text) && fail(location, "must not contain NUL")
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

function expect_member(value, allowed, location)
    text = expect_string(value, location)
    text in allowed ||
        fail(
        location,
        "unsupported closed-enum value $(repr(text))",
    )
    return text
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

"""
    computed_content_sha256(manifest)

Compute the read-only semantic digest. This function never mutates or stamps
the caller's manifest.
"""
computed_content_sha256(value) =
    bytes2hex(sha256(_canonical_content_bytes(value)))

function _parse_local_timestamp(value, location)
    text = expect_string(value, location)
    matched = match(LOCAL_TIMESTAMP_PATTERN, text)
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

function _nth_sunday(year_number, month_number, occurrence)
    first_date = Date(year_number, month_number, 1)
    days_to_sunday = mod(7 - dayofweek(first_date), 7)
    return first_date + Day(days_to_sunday + 7 * (occurrence - 1))
end

function _new_york_offset_seconds(date::Date)
    start_date = _nth_sunday(year(date), 3, 2)
    end_date = _nth_sunday(year(date), 11, 1)
    return start_date <= date < end_date ? -4 * 60 * 60 : -5 * 60 * 60
end

function _parse_release_key(value, location)
    text = expect_string(value, location)
    occursin(RELEASE_KEY_PATTERN, text) ||
        fail(location, "must use MMDDYYYY")
    date = try
        Date(text, RELEASE_KEY_FORMAT)
    catch
        fail(location, "must encode a valid calendar date")
    end
    Dates.format(date, RELEASE_KEY_FORMAT) == text ||
        fail(location, "must be a canonical MMDDYYYY key")
    return (; text, date)
end

function _expected_reference_month(quarter)
    year_number = parse(Int, quarter[1:4])
    quarter_number = parse(Int, quarter[end:end])
    return "$(year_number)-$(lpad(string(3 * quarter_number), 2, '0'))"
end

function _expected_release_month(quarter)
    year_number = parse(Int, quarter[1:4])
    quarter_number = parse(Int, quarter[end:end])
    return quarter_number == 4 ? (year_number + 1, 1) :
        (year_number, 3 * quarter_number + 1)
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
    declared = expect_hash(
        artifact["content_sha256"],
        "manifest.artifact.content_sha256",
    )
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
    exact_values = (
        "contract_id" => CONTRACT_ID,
        "observed_date" => OBSERVED_DATE,
        "snapshot_class" => SNAPSHOT_CLASS,
        "source_agency" => SOURCE_AGENCY,
        "publication_name" => PUBLICATION_NAME,
        "archive_index_url" => ARCHIVE_INDEX_URL,
        "event_count" => 40,
        "first_quarter" => first(EXPECTED_QUARTERS),
        "last_quarter" => last(EXPECTED_QUARTERS),
        "event_timezone" => EVENT_TIMEZONE,
        "metadata_only" => true,
    )
    for (key, expected) in exact_values
        expect_exact(
            contract[key],
            expected,
            "manifest.contract.$key",
        )
    end
    for key in (
            "network_access_allowed",
            "downloader_implemented",
            "parser_implemented",
            "html_bytes_acquired",
            "pdf_bytes_acquired",
            "values_extracted",
            "quarterly_aggregates_created",
            "origins_created",
            "source_inventory_mutation_authorized",
        )
        expect_exact(
            expect_bool(contract[key], "manifest.contract.$key"),
            false,
            "manifest.contract.$key",
        )
    end
    return contract
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

function _validate_event(record, expected_quarter, expected_key, sequence)
    location = "manifest.events[$sequence]"
    row = expect_exact_keys(record, EVENT_KEYS, location)
    expect_exact(
        expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
        sequence,
        "$location.sequence",
    )

    quarter = expect_string(row["quarter"], "$location.quarter")
    occursin(QUARTER_PATTERN, quarter) ||
        fail("$location.quarter", "must use YYYYQn")
    expect_exact(quarter, expected_quarter, "$location.quarter")

    reference_month =
        expect_string(row["reference_month"], "$location.reference_month")
    occursin(MONTH_PATTERN, reference_month) ||
        fail("$location.reference_month", "must use YYYY-MM")
    expect_exact(
        reference_month,
        _expected_reference_month(quarter),
        "$location.reference_month",
    )

    release_key =
        _parse_release_key(row["release_key"], "$location.release_key")
    expect_exact(release_key.text, expected_key, "$location.release_key")
    release_date = expect_date(row["release_date"], "$location.release_date")
    expect_exact(
        release_date,
        release_key.date,
        "$location.release_date",
    )
    expected_release_year, expected_release_month =
        _expected_release_month(quarter)
    year(release_date) == expected_release_year ||
        fail("$location.release_date", "has the wrong release year")
    month(release_date) == expected_release_month ||
        fail("$location.release_date", "has the wrong release month")

    expected_html_url = ARCHIVE_URL_PREFIX * release_key.text * ".htm"
    expected_pdf_url = ARCHIVE_URL_PREFIX * release_key.text * ".pdf"
    html_url = expect_string(row["html_url"], "$location.html_url")
    pdf_url = expect_string(row["pdf_url"], "$location.pdf_url")
    expect_exact(html_url, expected_html_url, "$location.html_url")
    expect_exact(pdf_url, expected_pdf_url, "$location.pdf_url")

    embargo_basis =
        expect_string(row["embargo_basis"], "$location.embargo_basis")
    expect_exact(embargo_basis, EMBARGO_BASIS, "$location.embargo_basis")

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
    Date(local_event.local_time) == release_date ||
        fail(
        "$location.event_timestamp_local",
        "date must equal release_date",
    )
    Time(local_event.local_time) == Time(8, 30) ||
        fail(
        "$location.event_timestamp_local",
        "must preserve the document-stated 08:30:00 embargo",
    )
    expected_offset = _new_york_offset_seconds(release_date)
    local_event.offset_seconds == expected_offset ||
        fail(
        "$location.event_timestamp_local",
        "offset does not match America/New_York DST rules",
    )
    expected_utc =
        local_event.local_time - Second(local_event.offset_seconds)
    utc_event.timestamp == expected_utc ||
        fail(
        "$location.event_timestamp_utc",
        "does not equal the offset-normalized embargo timestamp",
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

    economic_vintage_state = expect_member(
        row["economic_vintage_state"],
        ECONOMIC_VINTAGE_STATES,
        "$location.economic_vintage_state",
    )
    artifact_provenance_state = expect_member(
        row["artifact_provenance_state"],
        ARTIFACT_PROVENANCE_STATES,
        "$location.artifact_provenance_state",
    )
    expected_artifact_state =
        quarter == "2019Q4" ? "REISSUED_CORRECTED" :
        "OFFICIAL_ARCHIVE_RECONSTRUCTION"
    expect_exact(
        artifact_provenance_state,
        expected_artifact_state,
        "$location.artifact_provenance_state",
    )
    html_source_role = expect_member(
        row["html_source_role"],
        SOURCE_ROLES,
        "$location.html_source_role",
    )
    expect_exact(
        html_source_role,
        "PRIMARY_VALUE_SOURCE",
        "$location.html_source_role",
    )
    pdf_source_role = expect_member(
        row["pdf_source_role"],
        SOURCE_ROLES,
        "$location.pdf_source_role",
    )
    expect_exact(
        pdf_source_role,
        "PRIMARY_ARTIFACT_EVIDENCE",
        "$location.pdf_source_role",
    )

    correction_scope_state = expect_string(
        row["correction_scope_state"],
        "$location.correction_scope_state",
    )
    expected_correction_state =
        quarter == "2019Q4" ? TARGET_UNAFFECTED_STATE :
        NO_CORRECTION_STATE
    expect_exact(
        correction_scope_state,
        expected_correction_state,
        "$location.correction_scope_state",
    )
    first_public_bytes_verified = expect_bool(
        row["first_public_bytes_verified"],
        "$location.first_public_bytes_verified",
    )
    expect_exact(
        first_public_bytes_verified,
        false,
        "$location.first_public_bytes_verified",
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
        sequence,
        quarter,
        reference_month,
        release_key = release_key.text,
        release_date = string(release_date),
        html_url,
        pdf_url,
        embargo_basis,
        event_timestamp_local,
        event_timestamp_utc,
        event_timezone_iana,
        event_timezone_abbreviation,
        economic_vintage_state,
        artifact_provenance_state,
        html_source_role,
        pdf_source_role,
        correction_scope_state,
        first_public_bytes_verified,
        strict_origin_available,
    )
end

function _validate_events(manifest)
    events = get(manifest, "events", nothing)
    events isa AbstractVector ||
        fail("manifest.events", "must be an array of tables")
    length(events) == 40 ||
        fail("manifest.events", "must contain exactly 40 rows")
    validated = [
        _validate_event(record, quarter, release_key, sequence)
            for (
                sequence,
                (record, quarter, release_key),
            ) in enumerate(zip(events, EXPECTED_QUARTERS, EXACT_RELEASE_KEYS))
    ]

    for field in (
            :quarter,
            :reference_month,
            :release_key,
            :release_date,
            :html_url,
            :pdf_url,
            :event_timestamp_local,
            :event_timestamp_utc,
        )
        values = getproperty.(validated, field)
        length(values) == length(Set(values)) ||
            fail("manifest.events", "$(String(field)) values must be unique")
    end
    count(
        row ->
        row.artifact_provenance_state ==
            "OFFICIAL_ARCHIVE_RECONSTRUCTION",
        validated,
    ) == 39 ||
        fail(
        "manifest.events",
        "must contain 39 official-archive reconstruction rows",
    )
    count(
        row -> row.artifact_provenance_state == "REISSUED_CORRECTED",
        validated,
    ) == 1 ||
        fail(
        "manifest.events",
        "must contain exactly one reissued-corrected row",
    )
    count(row -> row.event_timezone_abbreviation == "EDT", validated) == 30 ||
        fail("manifest.events", "must contain exactly 30 EDT rows")
    count(row -> row.event_timezone_abbreviation == "EST", validated) == 10 ||
        fail("manifest.events", "must contain exactly 10 EST rows")
    return validated
end

function _immutable_contract(contract)
    return (;
        contract_id = String(contract["contract_id"]),
        observed_date = String(contract["observed_date"]),
        snapshot_class = String(contract["snapshot_class"]),
        source_agency = String(contract["source_agency"]),
        publication_name = String(contract["publication_name"]),
        archive_index_url = String(contract["archive_index_url"]),
        event_count = Int(contract["event_count"]),
        first_quarter = String(contract["first_quarter"]),
        last_quarter = String(contract["last_quarter"]),
        event_timezone = String(contract["event_timezone"]),
        metadata_only = Bool(contract["metadata_only"]),
        network_access_allowed =
            Bool(contract["network_access_allowed"]),
        downloader_implemented = Bool(contract["downloader_implemented"]),
        parser_implemented = Bool(contract["parser_implemented"]),
        html_bytes_acquired = Bool(contract["html_bytes_acquired"]),
        pdf_bytes_acquired = Bool(contract["pdf_bytes_acquired"]),
        values_extracted = Bool(contract["values_extracted"]),
        quarterly_aggregates_created =
            Bool(contract["quarterly_aggregates_created"]),
        origins_created = Bool(contract["origins_created"]),
        source_inventory_mutation_authorized =
            Bool(contract["source_inventory_mutation_authorized"]),
    )
end

function _immutable_gates(gates)
    return (;
        historical_first_state_verified =
            Bool(gates["historical_first_state_verified"]),
        historical_availability_proven =
            Bool(gates["historical_availability_proven"]),
        strict_origin_admissible = Bool(gates["strict_origin_admissible"]),
        empirical_forecast_execution_allowed =
            Bool(gates["empirical_forecast_execution_allowed"]),
        promotion_eligible = Bool(gates["promotion_eligible"]),
        production_scoring_allowed =
            Bool(gates["production_scoring_allowed"]),
        ready = Bool(gates["ready"]),
    )
end

"""
    validate_manifest(manifest)

Validate the sealed, offline BLS route inventory. The compiled digest pin is
mandatory. The return graph contains only immutable named tuples, tuples, and
scalar values and never aliases the caller's parsed TOML.
"""
function validate_manifest(manifest)
    root = expect_exact_keys(manifest, ROOT_KEYS, "manifest")
    contract = _validate_contract(root)
    gates = _validate_gates(root)
    events = _validate_events(root)
    declared = _validate_artifact(root)
    declared == EXPECTED_CONTENT_SHA256 ||
        fail(
        "manifest.artifact.content_sha256",
        "does not match the compiled sealed-contract pin",
    )
    return (;
        schema_version = MANIFEST_SCHEMA_VERSION,
        canonicalization = CANONICALIZATION,
        contract = _immutable_contract(contract),
        gates = _immutable_gates(gates),
        events = Tuple(events),
        content_sha256 = String(declared),
    )
end

function _read_manifest(path)
    absolute = abspath(String(path))
    isfile(absolute) || fail("manifest", "file does not exist: $absolute")
    islink(absolute) && fail("manifest", "must not be a symbolic link")
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

Read and validate one local TOML byte sequence without network access.
"""
function load_manifest(path::AbstractString = DEFAULT_MANIFEST_PATH)
    source = _read_manifest(path)
    return validate_manifest(source.document)
end

"""
    manifest_artifact([path])

Return the immutable validated view, semantic digest, immutable canonical
text, and physical file identity. Raw manifest bytes are never returned.
"""
function manifest_artifact(path::AbstractString = DEFAULT_MANIFEST_PATH)
    source = _read_manifest(path)
    validation = validate_manifest(source.document)
    return (;
        path = source.absolute,
        schema_version = validation.schema_version,
        canonicalization = validation.canonicalization,
        contract = validation.contract,
        gates = validation.gates,
        events = validation.events,
        content_sha256 = validation.content_sha256,
        canonical_content =
            String(_canonical_content_bytes(source.document)),
        file_sha256 = bytes2hex(sha256(source.bytes)),
        file_byte_count = length(source.bytes),
    )
end

end
