module BEANIPAAcquisition

using Dates
using Downloads
using SHA

if !isdefined(parentmodule(@__MODULE__), :BEANIPADiscovery)
    include(joinpath(@__DIR__, "BEANIPADiscovery.jl"))
end
using ..BEANIPADiscovery: validate_effective_uri

export AcquisitionError,
    ExpectedWorkbook,
    FetchedWorkbook,
    PILOT_EXPECTATIONS,
    PILOT_MAPPING_PROFILE_ID,
    PILOT_RELEASE_ID,
    PILOT_TARGET_IDS,
    acquire_pilot,
    bundle_sha256,
    fetch_official_workbook,
    persist_raw_bundle,
    sha256_hex,
    validate_fetched_pair,
    validate_fetched_workbook

const PILOT_RELEASE_ID = "r2026q2_advance"
const PILOT_MAPPING_PROFILE_ID = "september_2023_rebase"
const PILOT_TARGET_IDS = Set(
    [
        "core_pce_price_index",
        "gdp_deflator",
        "nominal_gdp",
        "pce_price_index",
        "real_gdp",
    ],
)
const XLSX_CONTENT_TYPE =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
const MAX_WORKBOOK_BYTES = 25_000_000
const FETCH_TIMEOUT_SECONDS = 120
const USER_AGENT = "BeforeIT-US-BEA-NIPA-Acquisition/1.0"
const HASH_PATTERN = r"^[0-9a-f]{64}$"

struct AcquisitionError <: Exception
    message::String
end

Base.showerror(io::IO, error::AcquisitionError) = print(io, error.message)

fail(location, message) =
    throw(AcquisitionError("$location: $message"))

struct ExpectedWorkbook
    workbook_id::String
    release_id::String
    section_id::String
    requested_locator::String
    expected_sha256::String
    expected_byte_count::Int
    target_ids::Set{String}
end

struct FetchedWorkbook
    raw_bytes::Vector{UInt8}
    http_status::Int
    content_type::String
    requested_locator::String
    effective_locator::String
    response_date::String
    etag::String
    last_modified::String
    content_length::String
    acquisition_started_at_utc::DateTime
    response_headers_at_utc::DateTime
    acquisition_completed_at_utc::DateTime
end

const PILOT_EXPECTATIONS = [
    ExpectedWorkbook(
        "r2026q2_advance_s1",
        PILOT_RELEASE_ID,
        "1",
        "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2026/Q2/Advance_July-30-2026/Section1all_xls.xlsx",
        "ddcd0c5b693cb5d179198e67dda60f817e0e97196e6f1c158152971bbc80b136",
        4_056_562,
        Set(["gdp_deflator", "nominal_gdp", "real_gdp"]),
    ),
    ExpectedWorkbook(
        "r2026q2_advance_s2",
        PILOT_RELEASE_ID,
        "2",
        "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2026/Q2/Advance_July-30-2026/Section2all_xls.xlsx",
        "1d5e3c6e177f6ba818bacf6361b3f21b7996e6cfdf55afb4d2a86a41bd2a4011",
        4_870_580,
        Set(["core_pce_price_index", "pce_price_index"]),
    ),
]

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(sha256(bytes))

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

function _is_xlsx_magic(bytes)
    length(bytes) >= 4 || return false
    return bytes[1:4] == UInt8[0x50, 0x4b, 0x03, 0x04]
end

function _validated_content_length(value, location)
    text = String(value)
    text == "NOT_PROVIDED" &&
        fail(location, "is required for exact workbook acquisition")
    occursin(r"^[1-9][0-9]*$", text) ||
        fail(location, "must be a positive canonical integer")
    count = tryparse(Int, text)
    count === nothing &&
        fail(location, "does not fit in an Int")
    return count
end

function _validate_expectation(expectation, location)
    expectation isa ExpectedWorkbook ||
        fail(location, "must be an ExpectedWorkbook")
    isempty(expectation.workbook_id) &&
        fail("$location.workbook_id", "must not be empty")
    expectation.release_id == PILOT_RELEASE_ID ||
        fail(
        "$location.release_id",
        "expected $PILOT_RELEASE_ID, found $(expectation.release_id)",
    )
    occursin(r"^[0-9]+$", expectation.section_id) ||
        fail("$location.section_id", "must contain decimal digits")
    validate_effective_uri(expectation.requested_locator) ==
        expectation.requested_locator ||
        fail("$location.requested_locator", "is not canonical")
    occursin(HASH_PATTERN, expectation.expected_sha256) ||
        fail("$location.expected_sha256", "must be lowercase SHA-256")
    0 < expectation.expected_byte_count <= MAX_WORKBOOK_BYTES ||
        fail(
        "$location.expected_byte_count",
        "must be within the acquisition byte limit",
    )
    isempty(expectation.target_ids) &&
        fail("$location.target_ids", "must not be empty")
    return expectation
end

"""
    fetch_official_workbook(locator)

Opt-in network primitive. It accepts only the exact official BEA HTTPS host,
disables content encoding, requires a direct HTTP 200 XLSX response, and
returns the exact response-body bytes plus selected server headers. It does
not write files, infer workbook semantics, establish historical availability,
or mutate any forecast inventory.
"""
function fetch_official_workbook(locator::AbstractString)
    requested_locator = validate_effective_uri(String(locator))
    temporary_path, temporary_io = mktemp()
    close(temporary_io)
    try
        acquisition_started_at_utc = now(UTC)
        response = Downloads.request(
            requested_locator;
            headers = [
                "Accept" => XLSX_CONTENT_TYPE,
                "Accept-Encoding" => "identity",
                "User-Agent" => USER_AGENT,
            ],
            output = temporary_path,
            timeout = FETCH_TIMEOUT_SECONDS,
        )
        response_headers_at_utc = now(UTC)
        effective_locator =
            validate_effective_uri(String(response.url))
        response.status == 200 ||
            fail(
            "http.status",
            "expected 200, found $(response.status)",
        )
        effective_locator == requested_locator ||
            fail(
            "http.effective_locator",
            "redirects are not accepted for exact byte identity",
        )
        bytes = read(temporary_path)
        isempty(bytes) && fail("http.body", "must not be empty")
        length(bytes) <= MAX_WORKBOOK_BYTES ||
            fail(
            "http.body",
            "exceeds the $MAX_WORKBOOK_BYTES-byte acquisition limit",
        )
        content_type = _header(response, "content-type")
        _base_content_type(content_type) == XLSX_CONTENT_TYPE ||
            fail(
            "http.content_type",
            "expected $XLSX_CONTENT_TYPE, found $(repr(content_type))",
        )
        content_length = _header(response, "content-length")
        _validated_content_length(
            content_length,
            "http.content_length",
        ) == length(bytes) ||
            fail(
            "http.content_length",
            "does not equal the response-body byte count",
        )
        _is_xlsx_magic(bytes) ||
            fail("http.body", "does not begin with OOXML ZIP magic")
        acquisition_completed_at_utc = now(UTC)
        return FetchedWorkbook(
            bytes,
            response.status,
            content_type,
            requested_locator,
            effective_locator,
            _header(response, "date"),
            _header(response, "etag"),
            _header(response, "last-modified"),
            content_length,
            acquisition_started_at_utc,
            response_headers_at_utc,
            acquisition_completed_at_utc,
        )
    finally
        ispath(temporary_path) && rm(temporary_path)
    end
end

function validate_fetched_workbook(
        fetched::FetchedWorkbook,
        expectation::ExpectedWorkbook;
        location = "workbook",
    )
    _validate_expectation(expectation, "$location.expectation")
    fetched.http_status == 200 ||
        fail("$location.http_status", "must equal 200")
    fetched.requested_locator == expectation.requested_locator ||
        fail(
        "$location.requested_locator",
        "does not match the acquisition expectation",
    )
    fetched.effective_locator == expectation.requested_locator ||
        fail(
        "$location.effective_locator",
        "does not match the exact requested locator",
    )
    _base_content_type(fetched.content_type) == XLSX_CONTENT_TYPE ||
        fail(
        "$location.content_type",
        "must be the XLSX media type",
    )
    _validated_content_length(
        fetched.content_length,
        "$location.content_length",
    ) == length(fetched.raw_bytes) ||
        fail(
        "$location.content_length",
        "does not equal the response-body byte count",
    )
    length(fetched.raw_bytes) == expectation.expected_byte_count ||
        fail(
        "$location.raw_bytes",
        "byte count does not match the pinned expectation",
    )
    _is_xlsx_magic(fetched.raw_bytes) ||
        fail("$location.raw_bytes", "does not have OOXML ZIP magic")
    digest = sha256_hex(fetched.raw_bytes)
    digest == expectation.expected_sha256 ||
        fail(
        "$location.raw_bytes",
        "SHA-256 does not match the pinned expectation",
    )
    fetched.acquisition_started_at_utc <=
        fetched.response_headers_at_utc <=
        fetched.acquisition_completed_at_utc ||
        fail(
        "$location.timestamps",
        "acquisition timestamps are not ordered",
    )
    return (
        workbook_id = expectation.workbook_id,
        section_id = expectation.section_id,
        raw_sha256 = digest,
        raw_byte_count = length(fetched.raw_bytes),
    )
end

function validate_fetched_pair(
        fetched_workbooks,
        expectations = PILOT_EXPECTATIONS,
    )
    fetched_workbooks isa AbstractVector ||
        fail("workbooks", "must be a vector")
    expectations isa AbstractVector ||
        fail("expectations", "must be a vector")
    length(fetched_workbooks) == length(expectations) ||
        fail("workbooks", "count does not match expectations")
    length(expectations) == 2 ||
        fail("expectations", "pilot requires exactly two workbooks")

    results = [
        validate_fetched_workbook(
                fetched,
                expectation;
                location = "workbooks[$index]",
            )
            for (index, (fetched, expectation)) in
            enumerate(zip(fetched_workbooks, expectations))
    ]
    workbook_ids = [row.workbook_id for row in results]
    length(Set(workbook_ids)) == length(workbook_ids) ||
        fail("expectations", "workbook IDs must be unique")
    sections = [row.section_id for row in results]
    Set(sections) == Set(["1", "2"]) ||
        fail("expectations", "must cover Sections 1 and 2 exactly")
    union((expectation.target_ids for expectation in expectations)...) ==
        PILOT_TARGET_IDS ||
        fail("expectations", "must cover all five pilot targets exactly")
    isempty(
        intersect(
            expectations[1].target_ids,
            expectations[2].target_ids,
        ),
    ) ||
        fail("expectations", "target coverage must not overlap")
    return results
end

function bundle_sha256(expectations = PILOT_EXPECTATIONS)
    rows = sort(
        [
            string(
                    expectation.workbook_id,
                    '\0',
                    expectation.expected_sha256,
                    '\0',
                    expectation.expected_byte_count,
                )
                for expectation in expectations
        ],
    )
    bytes = Vector{UInt8}(codeunits(join(rows, '\n') * "\n"))
    return sha256_hex(bytes)
end

function _raw_filename(expectation)
    return string(
        "section-",
        expectation.section_id,
        "-sha256-",
        expectation.expected_sha256,
        ".xlsx",
    )
end

function _verify_existing_bundle(
        bundle_path,
        fetched_workbooks,
        expectations,
    )
    islink(bundle_path) &&
        fail("raw_bundle", "must not be a symbolic link")
    isdir(bundle_path) ||
        fail("raw_bundle", "existing path is not a directory")
    expected_names = sort(_raw_filename.(expectations))
    readdir(bundle_path; sort = true) == expected_names ||
        fail("raw_bundle", "contains an unexpected file set")
    for (fetched, expectation) in zip(fetched_workbooks, expectations)
        path = joinpath(bundle_path, _raw_filename(expectation))
        islink(path) &&
            fail("raw_bundle", "workbook path must not be a symbolic link")
        isfile(path) ||
            fail("raw_bundle", "workbook path is not a regular file")
        read(path) == fetched.raw_bytes ||
            fail(
            "raw_bundle",
            "hash-addressed workbook differs from fetched bytes",
        )
    end
    return bundle_path
end

"""
    persist_raw_bundle(raw_root, fetched_workbooks; expectations)

After all workbooks pass exact validation in memory, persist the pair as one
content-addressed directory beneath the caller-supplied raw root. A new bundle
is assembled in a sibling temporary directory and renamed into place. Existing
hash-addressed bundles are accepted only when their exact file set and bytes
match. No receipt, inventory, or admission artifact is changed here.
"""
function persist_raw_bundle(
        raw_root,
        fetched_workbooks;
        expectations = PILOT_EXPECTATIONS,
    )
    validations = validate_fetched_pair(fetched_workbooks, expectations)
    root = abspath(String(raw_root))
    ispath(root) && !isdir(root) &&
        fail("raw_root", "existing path is not a directory")
    islink(root) &&
        fail("raw_root", "must not be a symbolic link")
    mkpath(root)
    object_root = joinpath(root, "bea_nipa", "hmi7", "objects")
    mkpath(object_root)
    islink(object_root) &&
        fail("raw_root", "object directory must not be a symbolic link")
    digest = bundle_sha256(expectations)
    bundle_path = joinpath(object_root, "sha256-$digest")

    if ispath(bundle_path)
        _verify_existing_bundle(
            bundle_path,
            fetched_workbooks,
            expectations,
        )
    else
        staging_path = mktempdir(object_root; prefix = ".staging-")
        installed = false
        try
            for (fetched, expectation) in
                zip(fetched_workbooks, expectations)
                path =
                    joinpath(staging_path, _raw_filename(expectation))
                open(path, "w") do io
                    write(io, fetched.raw_bytes)
                    flush(io)
                end
            end
            mv(staging_path, bundle_path)
            installed = true
        finally
            !installed && ispath(staging_path) && rm(staging_path; recursive = true)
        end
    end

    paths = Dict(
        expectation.workbook_id =>
            joinpath(bundle_path, _raw_filename(expectation))
            for expectation in expectations
    )
    return (
        release_id = PILOT_RELEASE_ID,
        mapping_profile_id = PILOT_MAPPING_PROFILE_ID,
        bundle_sha256 = digest,
        bundle_path = bundle_path,
        workbook_paths = paths,
        validations = validations,
        historical_availability_verified = false,
        origin_admissible = false,
        ready = false,
    )
end

"""
    acquire_pilot(raw_root; fetcher)

Fetch and validate both pinned 2026Q2 advance workbooks before atomically
installing their content-addressed raw bundle. The result is a present-day
transport/storage observation only.
"""
function acquire_pilot(
        raw_root;
        fetcher = fetch_official_workbook,
    )
    fetched = FetchedWorkbook[]
    for expectation in PILOT_EXPECTATIONS
        workbook = fetcher(expectation.requested_locator)
        workbook isa FetchedWorkbook ||
            fail("fetcher", "must return FetchedWorkbook")
        push!(fetched, workbook)
    end
    result = persist_raw_bundle(
        raw_root,
        fetched;
        expectations = PILOT_EXPECTATIONS,
    )
    return (; fetched_workbooks = fetched, result...)
end

end
