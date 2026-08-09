module BEAHMI7AdvanceCapture

using Dates
using SHA
using TOML

include(
    joinpath(
        @__DIR__,
        "..",
        "advance_metadata_manifest",
        "BEAHMI7AdvanceMetadataManifest.jl",
    ),
)
using .BEAHMI7AdvanceMetadataManifest

export BEAHMI7AdvanceCaptureError,
    FetchResponse,
    MAX_REDIRECTS,
    MAX_WORKBOOK_BYTES,
    MIN_WORKBOOK_BYTES,
    SCHEMA_VERSION,
    TERMS_LOCATOR,
    XLS_MEDIA_TYPE,
    XLSX_MEDIA_TYPE,
    capture_plan,
    capture_present_day_with_fetcher,
    derive_workbook_url,
    import_present_day_pair,
    receipt_file_sha256,
    receipt_sha256,
    validate_capture_bundle

const SCHEMA_VERSION =
    "beforeit-us-bea-hmi7-advance-present-day-capture.v2"
const CANONICALIZATION =
    "sorted_toml_excluding_artifact_receipt_sha256.v1"
const DIGEST_ALGORITHM = "sha256"
const PAIR_HASH_DOMAIN =
    "beforeit-us-bea-hmi7-advance-present-day-pair.v1"
const BUNDLE_PREFIX = "receipt-sha256-"
const RECEIPT_PREFIX = "receipt-self-sha256-"
const OFFICIAL_FILES_PREFIX =
    "https://apps.bea.gov/HistData/Files/"
const INTERNAL_FILES_PREFIX =
    "/Inetpub/wwwroot/website/website/HistData/Files/"
const TERMS_LOCATOR = "https://www.bea.gov/index.php/help/faq/145"
const SOURCE_AGENCY = "U.S. Bureau of Economic Analysis"
const SOURCE_ATTRIBUTION = "Source: U.S. Bureau of Economic Analysis"
const USER_AGENT =
    "BeforeIT-US-BEA-HMI7-Advance-Capture/1.0"
const SNAPSHOT_BOUNDARY =
    "PRESENT_DAY_HMI7_ARCHIVE_RETRIEVAL_NOT_HISTORICAL_FIRST_STATE"
const HISTORICAL_AVAILABILITY_STATUS =
    "UNKNOWN_NOT_ESTABLISHED_BY_PRESENT_DAY_CAPTURE"
const XLS_MEDIA_TYPE = "application/vnd.ms-excel"
const XLSX_MEDIA_TYPE =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
const XLS_MAGIC =
    UInt8[0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]
const XLSX_MAGIC = UInt8[0x50, 0x4b, 0x03, 0x04]
const MIN_WORKBOOK_BYTES = 512
const MAX_WORKBOOK_BYTES = 25_000_000
const MAX_REDIRECTS = 0
const MAX_HEADERS = 64
const MAX_HEADER_NAME_BYTES = 128
const MAX_HEADER_VALUE_BYTES = 8_192
const MAX_URL_BYTES = 1_024
const MAX_RECEIPT_BYTES = 256_000
const MAX_TOTAL_UNCOMPRESSED_BYTES = 250_000_000
const EXPECTED_WORKBOOK_COUNT = 2
const MAX_RELEASES_PER_CAPTURE = 1
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const SAFE_PATH_COMPONENT_PATTERN = r"^[A-Za-z0-9._-]+$"
const HEADER_NAME_PATTERN =
    r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$"
const RFC3339_PATTERN =
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"
const RFC3339_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
const ALLOWED_SOURCE_MODES =
    ("LOCAL_IMPORT", "INJECTED_FETCHER_OUTPUT")
const ATTESTATION_AUTHENTICATION =
    "UNAUTHENTICATED_LOCAL_PROCESS_ASSERTION"
const NOT_APPLICABLE_TERMS_DATE =
    "NOT_APPLICABLE_NONLIVE_IMPORT"
const REQUIRED_XLSX_ENTRIES =
    Set(["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml"])
const GATE_KEYS = (
    "historical_first_state_proven",
    "historical_workbook_availability_proven",
    "strict_origin_admissible",
    "source_inventory_mutation_allowed",
    "empirical_forecast_execution_allowed",
    "promotion_eligible",
    "production_scoring_allowed",
    "ready",
)

struct BEAHMI7AdvanceCaptureError <: Exception
    message::String
end

Base.showerror(io::IO, error::BEAHMI7AdvanceCaptureError) =
    print(io, error.message)

fail(location, message) =
    throw(BEAHMI7AdvanceCaptureError("$location: $message"))

"""
    FetchResponse(...)

Untrusted response material supplied by a local importer or injected fetcher.
The constructor copies all mutable byte, header, and redirect vectors. Capture
validation snapshots the object again before computing any trusted digest.
"""
struct FetchResponse
    raw_bytes::Vector{UInt8}
    http_status::Int
    request_headers::Vector{Pair{String, String}}
    response_headers::Vector{Pair{String, String}}
    response_headers_complete::Bool
    requested_url::String
    effective_url::String
    redirect_chain::Vector{Tuple{Int, String, String}}
    request_started_at_utc::String
    response_headers_at_utc::String
    response_body_completed_at_utc::String

    function FetchResponse(
            raw_bytes,
            http_status,
            request_headers,
            response_headers,
            response_headers_complete,
            requested_url,
            effective_url,
            redirect_chain,
            request_started_at_utc,
            response_headers_at_utc,
            response_body_completed_at_utc,
        )
        http_status isa Integer && !(http_status isa Bool) ||
            fail("FetchResponse.http_status", "must be an integer")
        response_headers_complete isa Bool ||
            fail(
            "FetchResponse.response_headers_complete",
            "must be a Boolean",
        )
        bytes = UInt8[byte for byte in raw_bytes]
        request = Pair{String, String}[
            String(first(header)) => String(last(header)) for
                header in request_headers
        ]
        response = Pair{String, String}[
            String(first(header)) => String(last(header)) for
                header in response_headers
        ]
        redirects = Tuple{Int, String, String}[
            (
                    Int(hop[1]),
                    String(hop[2]),
                    String(hop[3]),
                ) for hop in redirect_chain
        ]
        return new(
            bytes,
            Int(http_status),
            request,
            response,
            response_headers_complete,
            String(requested_url),
            String(effective_url),
            redirects,
            String(request_started_at_utc),
            String(response_headers_at_utc),
            String(response_body_completed_at_utc),
        )
    end
end

sha256_hex(bytes) = bytes2hex(sha256(bytes))

function _expect_string(value, location; maximum_bytes = nothing)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
    if maximum_bytes !== nothing
        ncodeunits(text) <= maximum_bytes ||
            fail(location, "exceeds the $maximum_bytes-byte limit")
    end
    return text
end

function _expect_integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    number = Int(value)
    number >= minimum || fail(location, "must be at least $minimum")
    return number
end

function _expect_bool(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function _expect_hash(value, location)
    text = _expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

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

function _expect_exact(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function _parse_date(value, location)
    text = _expect_string(value, location)
    occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", text) ||
        fail(location, "must use YYYY-MM-DD")
    parsed = tryparse(Date, text)
    parsed === nothing && fail(location, "must be a valid calendar date")
    string(parsed) == text || fail(location, "must be canonical")
    return parsed
end

function _parse_timestamp(value, location)
    text = _expect_string(value, location)
    occursin(RFC3339_PATTERN, text) ||
        fail(location, "must use RFC 3339 UTC milliseconds")
    parsed = tryparse(DateTime, text[1:(end - 1)], RFC3339_FORMAT)
    parsed === nothing && fail(location, "must be a valid UTC timestamp")
    return parsed
end

function _media_type(extension)
    extension == "xls" && return XLS_MEDIA_TYPE
    extension == "xlsx" && return XLSX_MEDIA_TYPE
    return fail("workbook_extension", "must be xls or xlsx")
end

function _magic_name(extension)
    extension == "xls" && return "OLE_COMPOUND_FILE_ENVELOPE"
    extension == "xlsx" && return "OOXML_ZIP_ENVELOPE"
    return fail("workbook_extension", "must be xls or xlsx")
end

function _expected_request_headers(media_type)
    return (
        "Accept" => media_type,
        "Accept-Encoding" => "identity",
        "User-Agent" => USER_AGENT,
    )
end

"""
    derive_workbook_url(release, filename)

Derive the exact direct BEA HMI7 file URL from a validated immutable metadata
row. Path components are case-preserving; in particular, the 2014Q3 `q3`
component is never normalized.
"""
function derive_workbook_url(release, filename::AbstractString)
    path = _expect_string(release.archive_path, "release.archive_path")
    startswith(path, INTERNAL_FILES_PREFIX) ||
        fail(
        "release.archive_path",
        "does not start with the sealed internal Files prefix",
    )
    raw_filename = _expect_string(filename, "filename")
    relative = path[(ncodeunits(INTERNAL_FILES_PREFIX) + 1):end]
    path_components =
        split(replace(relative, '\\' => '/'), '/'; keepempty = true)
    components = [path_components; raw_filename]
    length(components) <= 8 ||
        fail("release.archive_path", "has too many path components")
    for (index, component) in enumerate(components)
        isempty(component) &&
            fail("release.archive_path[$index]", "must not be empty")
        component in (".", "..") &&
            fail("release.archive_path[$index]", "traversal is forbidden")
        occursin(SAFE_PATH_COMPONENT_PATTERN, component) ||
            fail(
            "release.archive_path[$index]",
            "contains a character outside the exact URL grammar",
        )
    end
    url = OFFICIAL_FILES_PREFIX * join(components, "/")
    ncodeunits(url) <= MAX_URL_BYTES ||
        fail("workbook.url", "exceeds the URL byte limit")
    startswith(url, OFFICIAL_FILES_PREFIX * "Releases/GDP_and_PI/") ||
        fail("workbook.url", "is outside the official HMI7 release path")
    return url
end

function _capture_plan(sequence::Integer, metadata_path)
    sequence isa Bool && fail("sequence", "must be an integer, not a Boolean")
    artifact = manifest_artifact(String(metadata_path))
    1 <= sequence <= length(artifact.releases) ||
        fail("sequence", "must identify one of the 40 sealed releases")
    release = artifact.releases[Int(sequence)]
    workbook_rows = (
        (
            section_id = "1",
            filename = release.section1_filename,
            extension = release.workbook_extension,
        ),
        (
            section_id = "2",
            filename = release.section2_filename,
            extension = release.workbook_extension,
        ),
    )
    workbooks = Tuple(
        (
                section_id = row.section_id,
                filename = row.filename,
                extension = row.extension,
                media_type = _media_type(row.extension),
                url = derive_workbook_url(release, row.filename),
                request_headers =
                _expected_request_headers(_media_type(row.extension)),
            ) for row in workbook_rows
    )
    return (;
        metadata = (;
            schema_version = artifact.schema_version,
            contract_id = artifact.contract.contract_id,
            content_sha256 = artifact.content_sha256,
            file_sha256 = artifact.file_sha256,
            file_byte_count = artifact.file_byte_count,
        ),
        release = (;
            sequence = release.sequence,
            reference_period = release.reference_period,
            estimate_family = release.estimate_family,
            directory_id = release.directory_id,
            archive_path = release.archive_path,
            archive_label = release.archive_label,
            archive_folder_date = release.archive_folder_date,
            event_timestamp_utc = release.event_timestamp_utc,
            bea_release_number = release.bea_release_number,
            event_page_url = release.event_page_url,
            update_type = release.update_type,
            irregular_flag = release.irregular_flag,
        ),
        workbooks,
    )
end

"""
    capture_plan(sequence; metadata_path=...)

Return an immutable one-release capture plan driven by the compiled-pin
validated 40-release metadata artifact. This function performs no network
access and does not mutate a source inventory.
"""
function capture_plan(
        sequence::Integer;
        metadata_path::AbstractString =
            BEAHMI7AdvanceMetadataManifest.DEFAULT_MANIFEST_PATH,
    )
    return _capture_plan(sequence, metadata_path)
end

function _snapshot_response(response, location)
    response isa FetchResponse ||
        fail(location, "must be a FetchResponse")
    return FetchResponse(
        copy(response.raw_bytes),
        response.http_status,
        copy(response.request_headers),
        copy(response.response_headers),
        response.response_headers_complete,
        response.requested_url,
        response.effective_url,
        copy(response.redirect_chain),
        response.request_started_at_utc,
        response.response_headers_at_utc,
        response.response_body_completed_at_utc,
    )
end

function _validate_header_pair(header, location)
    name = _expect_string(
        first(header),
        "$location.name";
        maximum_bytes = MAX_HEADER_NAME_BYTES,
    )
    value = String(last(header))
    ncodeunits(value) <= MAX_HEADER_VALUE_BYTES ||
        fail("$location.value", "exceeds the header value byte limit")
    occursin(HEADER_NAME_PATTERN, name) ||
        fail("$location.name", "is not an RFC HTTP field-name token")
    any(
        character ->
        (Int(character) < 0x20 && character != '\t') ||
            Int(character) == 0x7f,
        value,
    ) &&
        fail("$location.value", "contains a forbidden control character")
    return name => value
end

function _validate_headers(headers, location)
    headers isa AbstractVector || fail(location, "must be a vector")
    length(headers) <= MAX_HEADERS ||
        fail(location, "exceeds the $MAX_HEADERS-header limit")
    return Tuple(
        _validate_header_pair(header, "$location[$index]") for
            (index, header) in enumerate(headers)
    )
end

function _header_values(headers, name)
    wanted = lowercase(name)
    return [
        last(header) for header in headers if
            lowercase(first(header)) == wanted
    ]
end

function _single_header(headers, name, location; required = true)
    values = _header_values(headers, name)
    length(values) <= 1 ||
        fail("$location.$name", "must not be repeated")
    required && isempty(values) &&
        fail("$location.$name", "must be present")
    return isempty(values) ? nothing : only(values)
end

function _base_media_type(value)
    return lowercase(strip(first(split(String(value), ';'; limit = 2))))
end

function _contains_bytes(haystack, needle)
    isempty(needle) && return true
    length(needle) <= length(haystack) || return false
    for first_index in 1:(length(haystack) - length(needle) + 1)
        haystack[first_index:(first_index + length(needle) - 1)] ==
            needle && return true
    end
    return false
end

function _u16(bytes, position, location)
    position >= 1 && position + 1 <= length(bytes) ||
        fail(location, "contains a truncated 16-bit ZIP field")
    return Int(bytes[position]) | (Int(bytes[position + 1]) << 8)
end

function _u32(bytes, position, location)
    position >= 1 && position + 3 <= length(bytes) ||
        fail(location, "contains a truncated 32-bit ZIP field")
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
    length(bytes) >= MIN_WORKBOOK_BYTES ||
        fail(location, "is shorter than the workbook byte floor")
    _signature_at(bytes, 1, XLSX_MAGIC) ||
        fail(location, "does not start with a ZIP local-file header")

    eocd_signature = UInt8[0x50, 0x4b, 0x05, 0x06]
    first_candidate = max(1, length(bytes) - 65_535 - 22 + 1)
    eocd = nothing
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

    eocd_position = something(eocd)
    disk_number = _u16(bytes, eocd_position + 4, location)
    central_disk = _u16(bytes, eocd_position + 6, location)
    entries_on_disk = _u16(bytes, eocd_position + 8, location)
    total_entries = _u16(bytes, eocd_position + 10, location)
    central_size = _u32(bytes, eocd_position + 12, location)
    central_offset = _u32(bytes, eocd_position + 16, location)
    disk_number == 0 && central_disk == 0 ||
        fail(location, "multi-disk ZIP archives are forbidden")
    0 < total_entries < 0xffff && entries_on_disk == total_entries ||
        fail(location, "ZIP entry count is invalid or ZIP64")

    central_start = central_offset + 1
    central_end_exclusive = central_start + central_size
    central_start >= 1 &&
        central_end_exclusive - 1 < eocd_position ||
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
        _signature_at(bytes, local_position, XLSX_MAGIC) ||
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

        cursor = name_end + 1 + extra_length + comment_length
        cursor <= central_end_exclusive ||
            fail(location, "central entry $index exceeds directory bounds")
    end
    cursor == central_end_exclusive ||
        fail(location, "central directory size does not match its entries")
    all(name -> name in names, REQUIRED_XLSX_ENTRIES) ||
        fail(location, "lacks required XLSX package entries")
    return nothing
end

function _validate_xls_magic(bytes, location)
    length(bytes) >= 512 || fail(location, "is shorter than an OLE header")
    bytes[1:length(XLS_MAGIC)] == XLS_MAGIC ||
        fail(location, "does not begin with OLE Compound File magic")
    bytes[29:30] == UInt8[0xfe, 0xff] ||
        fail(location, "does not declare OLE little-endian byte order")
    major_version = bytes[27:28]
    sector_shift = bytes[31:32]
    valid_version =
        (
        major_version == UInt8[0x03, 0x00] &&
            sector_shift == UInt8[0x09, 0x00]
    ) ||
        (
        major_version == UInt8[0x04, 0x00] &&
            sector_shift == UInt8[0x0c, 0x00]
    )
    valid_version ||
        fail(location, "has an unsupported OLE version/sector-size pair")
    bytes[33:34] == UInt8[0x06, 0x00] ||
        fail(location, "does not use the required OLE mini-sector shift")
    all(iszero, bytes[35:40]) ||
        fail(location, "has nonzero OLE reserved header bytes")

    sector_size = 1 << _u16(bytes, 31, location)
    length(bytes) % sector_size == 0 ||
        fail(location, "is not aligned to the declared OLE sector size")
    sector_count = length(bytes) ÷ sector_size - 1
    sector_count >= 2 ||
        fail(location, "does not contain directory and FAT sectors")
    major_version == UInt8[0x03, 0x00] &&
        _u32(bytes, 41, location) != 0 &&
        fail(location, "version-3 OLE files must declare zero directory sectors")

    fat_sector_count = _u32(bytes, 45, location)
    1 <= fat_sector_count <= sector_count ||
        fail(location, "declares an invalid OLE FAT-sector count")
    first_directory_sector = _u32(bytes, 49, location)
    first_directory_sector < sector_count ||
        fail(location, "declares an invalid OLE directory-sector index")
    _u32(bytes, 57, location) == 4096 ||
        fail(location, "does not declare the standard OLE mini-stream cutoff")

    end_of_chain = 0xfffffffe
    free_sector = 0xffffffff
    first_mini_fat_sector = _u32(bytes, 61, location)
    mini_fat_sector_count = _u32(bytes, 65, location)
    if mini_fat_sector_count == 0
        first_mini_fat_sector in (end_of_chain, free_sector) ||
            fail(location, "has inconsistent empty OLE mini-FAT metadata")
    else
        first_mini_fat_sector < sector_count ||
            fail(location, "declares an invalid OLE mini-FAT sector")
        mini_fat_sector_count <= sector_count ||
            fail(location, "declares too many OLE mini-FAT sectors")
    end

    first_difat_sector = _u32(bytes, 69, location)
    difat_sector_count = _u32(bytes, 73, location)
    if difat_sector_count == 0
        first_difat_sector in (end_of_chain, free_sector) ||
            fail(location, "has inconsistent empty OLE DIFAT metadata")
    else
        first_difat_sector < sector_count ||
            fail(location, "declares an invalid OLE DIFAT sector")
        difat_sector_count <= sector_count ||
            fail(location, "declares too many OLE DIFAT sectors")
    end

    header_difat = Int[]
    for index in 0:108
        sector = _u32(bytes, 77 + 4index, location)
        sector in (end_of_chain, free_sector) && continue
        sector < sector_count ||
            fail(location, "OLE header DIFAT contains an invalid sector")
        push!(header_difat, sector)
    end
    length(unique(header_difat)) == length(header_difat) ||
        fail(location, "OLE header DIFAT contains duplicate sectors")
    length(header_difat) >= min(fat_sector_count, 109) ||
        fail(location, "OLE header DIFAT does not identify its FAT sectors")
    return "OLE_COMPOUND_FILE_ENVELOPE"
end

function _validate_xlsx_magic(bytes, location)
    _validate_xlsx_zip(bytes, location)
    return "OOXML_ZIP_ENVELOPE"
end

function _validate_magic(bytes, extension, location)
    extension == "xls" && return _validate_xls_magic(bytes, location)
    extension == "xlsx" && return _validate_xlsx_magic(bytes, location)
    return fail(location, "has an unsupported workbook extension")
end

function _validate_request_headers(headers, target, location)
    observed = _validate_headers(headers, location)
    observed == target.request_headers ||
        fail(
        location,
        "must exactly equal the sealed identity-encoding request headers",
    )
    return observed
end

function _validate_response_headers(headers, target, byte_count, location)
    observed = _validate_headers(headers, location)
    content_type =
        _single_header(observed, "Content-Type", location; required = true)
    _base_media_type(content_type) == target.media_type ||
        fail(
        "$location.Content-Type",
        "does not match $(target.media_type)",
    )
    content_length =
        _single_header(observed, "Content-Length", location; required = false)
    if content_length !== nothing
        occursin(r"^(0|[1-9][0-9]*)$", content_length) ||
            fail("$location.Content-Length", "must be a canonical integer")
        parsed_length = tryparse(Int, content_length)
        parsed_length === nothing &&
            fail("$location.Content-Length", "does not fit in an Int")
        parsed_length == byte_count ||
            fail("$location.Content-Length", "does not equal body byte count")
    end
    encoding = _single_header(
        observed,
        "Content-Encoding",
        location;
        required = false,
    )
    encoding === nothing || lowercase(strip(encoding)) == "identity" ||
        fail(
        "$location.Content-Encoding",
        "must be absent or identity",
    )
    return observed
end

function _validate_response(response::FetchResponse, target, location)
    response.http_status == 200 ||
        fail("$location.http_status", "must equal 200")
    response.response_headers_complete ||
        fail(
        "$location.response_headers_complete",
        "must be explicitly true",
    )
    response.requested_url == target.url ||
        fail("$location.requested_url", "does not equal the sealed URL")
    response.effective_url == target.url ||
        fail(
        "$location.effective_url",
        "redirects or URL normalization are forbidden",
    )
    ncodeunits(response.requested_url) <= MAX_URL_BYTES ||
        fail("$location.requested_url", "exceeds the URL byte limit")
    startswith(response.requested_url, OFFICIAL_FILES_PREFIX) ||
        fail("$location.requested_url", "must use the official HTTPS host")
    length(response.redirect_chain) <= MAX_REDIRECTS ||
        fail(
        "$location.redirect_chain",
        "redirects are forbidden by the zero-hop limit",
    )
    isempty(response.redirect_chain) ||
        fail("$location.redirect_chain", "must be empty")

    byte_count = length(response.raw_bytes)
    MIN_WORKBOOK_BYTES <= byte_count <= MAX_WORKBOOK_BYTES ||
        fail(
        "$location.raw_bytes",
        "is outside the $MIN_WORKBOOK_BYTES:$MAX_WORKBOOK_BYTES limit",
    )
    magic =
        _validate_magic(response.raw_bytes, target.extension, "$location.raw_bytes")
    request_headers = _validate_request_headers(
        response.request_headers,
        target,
        "$location.request_headers",
    )
    response_headers = _validate_response_headers(
        response.response_headers,
        target,
        byte_count,
        "$location.response_headers",
    )
    started = _parse_timestamp(
        response.request_started_at_utc,
        "$location.request_started_at_utc",
    )
    headers_at = _parse_timestamp(
        response.response_headers_at_utc,
        "$location.response_headers_at_utc",
    )
    completed = _parse_timestamp(
        response.response_body_completed_at_utc,
        "$location.response_body_completed_at_utc",
    )
    started <= headers_at <= completed ||
        fail("$location.timestamps", "must be nondecreasing")
    return (;
        raw_sha256 = sha256_hex(response.raw_bytes),
        raw_byte_count = byte_count,
        magic,
        request_headers,
        response_headers,
        started,
        headers_at,
        completed,
    )
end

function _hash_field!(io, name, value)
    name_bytes = Vector{UInt8}(codeunits(String(name)))
    value_bytes = Vector{UInt8}(codeunits(string(value)))
    write(io, string(length(name_bytes)), ':', name_bytes)
    write(io, string(length(value_bytes)), ':', value_bytes)
    return io
end

function _pair_sha256(plan, results)
    io = IOBuffer()
    _hash_field!(io, "domain", PAIR_HASH_DOMAIN)
    _hash_field!(io, "metadata_content_sha256", plan.metadata.content_sha256)
    _hash_field!(io, "sequence", plan.release.sequence)
    _hash_field!(io, "reference_period", plan.release.reference_period)
    for (index, (target, result)) in
        enumerate(zip(plan.workbooks, results))
        _hash_field!(io, "workbook_index", index)
        _hash_field!(io, "section_id", target.section_id)
        _hash_field!(io, "source_url", target.url)
        _hash_field!(io, "raw_sha256", result.raw_sha256)
        _hash_field!(io, "raw_byte_count", result.raw_byte_count)
    end
    return sha256_hex(take!(io))
end

function _headers_document(headers)
    return [
        Dict{String, Any}(
                "sequence" => index,
                "name" => first(header),
                "value" => last(header),
            ) for (index, header) in enumerate(headers)
    ]
end

function _workbook_document(target, response, result)
    object_relative_path =
        "objects/sha256-" * result.raw_sha256 * "." * target.extension
    return Dict{String, Any}(
        "section_id" => target.section_id,
        "filename" => target.filename,
        "extension" => target.extension,
        "expected_media_type" => target.media_type,
        "validated_magic" => result.magic,
        "requested_url" => response.requested_url,
        "effective_url" => response.effective_url,
        "http_status" => response.http_status,
        "redirect_count" => length(response.redirect_chain),
        "response_headers_complete" => response.response_headers_complete,
        "request_headers" => _headers_document(result.request_headers),
        "response_headers" => _headers_document(result.response_headers),
        "request_started_at_utc" => response.request_started_at_utc,
        "response_headers_at_utc" => response.response_headers_at_utc,
        "response_body_completed_at_utc" =>
            response.response_body_completed_at_utc,
        "observed_byte_count" => result.raw_byte_count,
        "observed_raw_sha256" => result.raw_sha256,
        "object_relative_path" => object_relative_path,
    )
end

function _build_receipt(
        plan,
        responses,
        results;
        source_mode,
        capture_local_date,
        actor,
        terms_reviewed,
        terms_reviewed_local_date,
    )
    pair_digest = _pair_sha256(plan, results)
    capture_started = minimum(result.started for result in results)
    capture_completed = maximum(result.completed for result in results)
    for (label, timestamp) in (
            "capture_started_at_utc" => capture_started,
            "capture_completed_at_utc" => capture_completed,
        )
        abs(Dates.value(Date(timestamp) - capture_local_date)) <= 1 ||
            fail(
            "capture.$label",
            "must fall within one UTC date of capture_local_date",
        )
    end
    gates = Dict{String, Any}(key => false for key in GATE_KEYS)
    terms_date = terms_reviewed ?
        string(terms_reviewed_local_date) :
        NOT_APPLICABLE_TERMS_DATE
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => SCHEMA_VERSION,
            "canonicalization" => CANONICALIZATION,
            "digest_algorithm" => DIGEST_ALGORITHM,
            "receipt_sha256" => repeat("0", 64),
            "pair_sha256" => pair_digest,
            "immutable_bundle" => true,
        ),
        "source_contract" => Dict{String, Any}(
            "metadata_schema_version" => plan.metadata.schema_version,
            "metadata_contract_id" => plan.metadata.contract_id,
            "metadata_content_sha256" => plan.metadata.content_sha256,
            "metadata_file_sha256" => plan.metadata.file_sha256,
            "metadata_file_byte_count" => plan.metadata.file_byte_count,
        ),
        "release" => Dict{String, Any}(
            "sequence" => plan.release.sequence,
            "reference_period" => plan.release.reference_period,
            "estimate_family" => plan.release.estimate_family,
            "directory_id" => plan.release.directory_id,
            "archive_path" => plan.release.archive_path,
            "archive_label" => plan.release.archive_label,
            "archive_folder_date" => plan.release.archive_folder_date,
            "event_timestamp_utc" => plan.release.event_timestamp_utc,
            "bea_release_number" => plan.release.bea_release_number,
            "event_page_url" => plan.release.event_page_url,
            "update_type" => plan.release.update_type,
            "irregular_flag" => plan.release.irregular_flag,
            "snapshot_boundary" => SNAPSHOT_BOUNDARY,
            "historical_availability_status" =>
                HISTORICAL_AVAILABILITY_STATUS,
        ),
        "capture" => Dict{String, Any}(
            "source_mode_attested" => source_mode,
            "attestation_authentication" =>
                ATTESTATION_AUTHENTICATION,
            "actor" => actor,
            "capture_local_date" => string(capture_local_date),
            "capture_started_at_utc" =>
                Dates.format(capture_started, RFC3339_FORMAT) * "Z",
            "capture_completed_at_utc" =>
                Dates.format(capture_completed, RFC3339_FORMAT) * "Z",
            "network_transport_verified" => false,
            "terms_locator" => TERMS_LOCATOR,
            "terms_review_attested" => terms_reviewed,
            "terms_review_attested_local_date" => terms_date,
            "terms_review_confers_redistribution_authority" => false,
            "source_agency" => SOURCE_AGENCY,
            "source_attribution" => SOURCE_ATTRIBUTION,
            "present_day_retrieval_only" => true,
        ),
        "limits" => Dict{String, Any}(
            "max_releases_per_capture" => MAX_RELEASES_PER_CAPTURE,
            "expected_workbook_count" => EXPECTED_WORKBOOK_COUNT,
            "min_workbook_bytes" => MIN_WORKBOOK_BYTES,
            "max_workbook_bytes" => MAX_WORKBOOK_BYTES,
            "max_total_uncompressed_bytes" =>
                MAX_TOTAL_UNCOMPRESSED_BYTES,
            "max_redirects" => MAX_REDIRECTS,
            "max_headers_per_response" => MAX_HEADERS,
            "max_header_name_bytes" => MAX_HEADER_NAME_BYTES,
            "max_header_value_bytes" => MAX_HEADER_VALUE_BYTES,
            "max_url_bytes" => MAX_URL_BYTES,
            "response_body_content_encoding" => "IDENTITY_OR_ABSENT",
        ),
        "workbooks" => [
            _workbook_document(target, response, result) for
                (target, response, result) in
                zip(plan.workbooks, responses, results)
        ],
        "gates" => gates,
    )
    document["artifact"]["receipt_sha256"] = receipt_sha256(document)
    return document
end

function _receipt_without_hash(document)
    copied = deepcopy(document)
    artifact = get(copied, "artifact", nothing)
    artifact isa AbstractDict ||
        fail("receipt.artifact", "must be a table")
    pop!(artifact, "receipt_sha256", nothing)
    return copied
end

function _toml_bytes(document)
    io = IOBuffer()
    try
        TOML.print(io, document; sorted = true)
    catch error
        fail(
            "receipt.serialization",
            "could not serialize TOML: $(sprint(showerror, error))",
        )
    end
    bytes = take!(io)
    isempty(bytes) && fail("receipt.serialization", "must not be empty")
    bytes[end] == UInt8('\n') || push!(bytes, UInt8('\n'))
    length(bytes) <= MAX_RECEIPT_BYTES ||
        fail(
        "receipt.serialization",
        "exceeds the $MAX_RECEIPT_BYTES-byte limit",
    )
    return bytes
end

"""
    receipt_sha256(document)

Compute the receipt semantic self-hash over sorted TOML with only the
`artifact.receipt_sha256` field omitted.
"""
function receipt_sha256(document)
    document isa AbstractDict || fail("receipt", "must be a table")
    return sha256_hex(_toml_bytes(_receipt_without_hash(document)))
end

receipt_file_sha256(document) = sha256_hex(_toml_bytes(document))

function _canonical_root(raw_root)
    root = String(raw_root)
    isabspath(root) || fail("raw_root", "must be absolute")
    normpath(root) == root ||
        fail("raw_root", "must be normalized without traversal aliases")
    candidate = root
    while true
        ispath(candidate) && islink(candidate) &&
            fail("raw_root", "must not traverse a symbolic link")
        parent = dirname(candidate)
        parent == candidate && break
        candidate = parent
    end
    mkpath(root)
    realpath(root) == root ||
        fail("raw_root", "must be its canonical filesystem path")
    return root
end

function _write_exact(path, bytes)
    ispath(path) && fail("bundle.staging", "refuses to overwrite $path")
    open(path, "w") do io
        write(io, bytes)
        flush(io)
    end
    read(path) == bytes ||
        fail("bundle.staging", "read-back does not match $path")
    return path
end

function _rename_exclusive(source, target)
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
            "bundle.install",
            "platform lacks a sealed exclusive-directory rename",
        )
    end
    result == 0 && return true
    error_number = Base.Libc.errno()
    error_number == Base.Libc.EEXIST && return false
    return fail(
        "bundle.install",
        "exclusive rename failed with errno $error_number " *
            "($(Base.Libc.strerror(error_number)))",
    )
end

function _make_read_only(path)
    if isdir(path)
        chmod(path, 0o555)
    else
        chmod(path, 0o444)
    end
    return path
end

function _seal_capture(
        sequence,
        raw_root,
        supplied_responses;
        metadata_path,
        source_mode,
        capture_local_date,
        actor,
        terms_reviewed,
        terms_reviewed_local_date,
    )
    source_mode in ALLOWED_SOURCE_MODES ||
        fail("source_mode", "has an unsupported value")
    plan = _capture_plan(sequence, metadata_path)
    supplied_responses isa AbstractVector ||
        fail("responses", "must be a vector")
    length(supplied_responses) == EXPECTED_WORKBOOK_COUNT ||
        fail("responses", "must contain the exact Section 1/Section 2 pair")
    responses = [
        _snapshot_response(response, "responses[$index]") for
            (index, response) in enumerate(supplied_responses)
    ]
    results = [
        _validate_response(response, target, "responses[$index]") for
            (index, (response, target)) in
            enumerate(zip(responses, plan.workbooks))
    ]
    length(Set(result.raw_sha256 for result in results)) ==
        EXPECTED_WORKBOOK_COUNT ||
        fail("responses", "workbook raw-byte digest aliases are forbidden")
    receipt = _build_receipt(
        plan,
        responses,
        results;
        source_mode,
        capture_local_date,
        actor,
        terms_reviewed,
        terms_reviewed_local_date,
    )
    receipt_digest = receipt["artifact"]["receipt_sha256"]
    receipt_bytes = _toml_bytes(receipt)
    root = _canonical_root(raw_root)
    target = joinpath(root, BUNDLE_PREFIX * receipt_digest)
    staging = mktempdir(root; prefix = ".bea-hmi7-advance-staging-")
    installed = false
    try
        objects_path = joinpath(staging, "objects")
        mkdir(objects_path)
        for (workbook, response) in zip(receipt["workbooks"], responses)
            object_path =
                joinpath(staging, workbook["object_relative_path"])
            dirname(object_path) == objects_path ||
                fail("bundle.staging", "object path escaped the bundle")
            _write_exact(object_path, response.raw_bytes)
            _make_read_only(object_path)
        end
        receipt_path =
            joinpath(staging, RECEIPT_PREFIX * receipt_digest * ".toml")
        _write_exact(receipt_path, receipt_bytes)
        _make_read_only(receipt_path)
        _make_read_only(objects_path)
        _make_read_only(staging)
        if _rename_exclusive(staging, target)
            installed = true
        else
            chmod(staging, 0o755)
            chmod(objects_path, 0o755)
            for name in readdir(objects_path)
                chmod(joinpath(objects_path, name), 0o644)
            end
            chmod(receipt_path, 0o644)
            rm(staging; recursive = true)
        end
    finally
        if ispath(staging)
            try
                chmod(staging, 0o755)
                objects_path = joinpath(staging, "objects")
                if isdir(objects_path)
                    chmod(objects_path, 0o755)
                    for name in readdir(objects_path)
                        chmod(joinpath(objects_path, name), 0o644)
                    end
                end
                for name in readdir(staging)
                    path = joinpath(staging, name)
                    isfile(path) && chmod(path, 0o644)
                end
                rm(staging; recursive = true)
            catch
            end
        end
    end
    validated =
        validate_capture_bundle(target; metadata_path = String(metadata_path))
    validated.receipt_sha256 == receipt_digest ||
        fail("bundle.install", "installed receipt digest changed")
    return merge(validated, (; installed))
end

function _actor(value, location)
    text = _expect_string(value, location; maximum_bytes = 256)
    any(character -> character in ('\r', '\n', '\0'), text) &&
        fail(location, "contains a forbidden control character")
    return text
end

"""
    import_present_day_pair(sequence, raw_root, responses; ...)

Seal one exact local Section 1/Section 2 response pair. This boundary performs
no network access. It records a present-day/local-import observation only and
cannot establish historical first state, historical availability, an
admissible origin, or readiness.
"""
function import_present_day_pair(
        sequence::Integer,
        raw_root::AbstractString,
        responses;
        observed_local_date,
        importer,
        metadata_path::AbstractString =
            BEAHMI7AdvanceMetadataManifest.DEFAULT_MANIFEST_PATH,
    )
    local_date = observed_local_date isa Date ?
        observed_local_date :
        _parse_date(observed_local_date, "observed_local_date")
    actor = _actor(importer, "importer")
    return _seal_capture(
        sequence,
        raw_root,
        responses;
        metadata_path,
        source_mode = "LOCAL_IMPORT",
        capture_local_date = local_date,
        actor,
        terms_reviewed = false,
        terms_reviewed_local_date = nothing,
    )
end

"""
    capture_present_day_with_fetcher(sequence, raw_root, fetcher; ...)

Opt-in live acquisition of exactly one sealed release pair through an injected
fetch function. There is deliberately no built-in downloader. The fetcher is
called once for each immutable workbook target and must return `FetchResponse`.
Live capture requires explicit BEA terms review on the current host-local date
both before and after fetching.
"""
function capture_present_day_with_fetcher(
        sequence::Integer,
        raw_root::AbstractString,
        fetcher;
        live::Bool = false,
        terms_reviewed::Bool = false,
        terms_reviewed_local_date = nothing,
        reviewer = "",
        metadata_path::AbstractString =
            BEAHMI7AdvanceMetadataManifest.DEFAULT_MANIFEST_PATH,
    )
    live || fail("live", "must be explicitly true")
    terms_reviewed ||
        fail("terms_reviewed", "must be explicitly true")
    reviewed_date = terms_reviewed_local_date isa Date ?
        terms_reviewed_local_date :
        _parse_date(
            terms_reviewed_local_date,
            "terms_reviewed_local_date",
        )
    local_date = today()
    reviewed_date == local_date ||
        fail(
        "terms_reviewed_local_date",
        "must equal the current host-local date $local_date",
    )
    actor = _actor(reviewer, "reviewer")
    plan = _capture_plan(sequence, metadata_path)
    responses = FetchResponse[]
    for target in plan.workbooks
        response = fetcher(target)
        push!(responses, _snapshot_response(response, "fetcher.result"))
    end
    today() == local_date ||
        fail(
        "capture_local_date",
        "host-local date changed during capture; review terms and rerun",
    )
    return _seal_capture(
        sequence,
        raw_root,
        responses;
        metadata_path,
        source_mode = "INJECTED_FETCHER_OUTPUT",
        capture_local_date = local_date,
        actor,
        terms_reviewed = true,
        terms_reviewed_local_date = reviewed_date,
    )
end

const ROOT_KEYS =
    ("artifact", "source_contract", "release", "capture", "limits", "workbooks", "gates")
const ARTIFACT_KEYS = (
    "schema_version",
    "canonicalization",
    "digest_algorithm",
    "receipt_sha256",
    "pair_sha256",
    "immutable_bundle",
)
const SOURCE_CONTRACT_KEYS = (
    "metadata_schema_version",
    "metadata_contract_id",
    "metadata_content_sha256",
    "metadata_file_sha256",
    "metadata_file_byte_count",
)
const RELEASE_KEYS = (
    "sequence",
    "reference_period",
    "estimate_family",
    "directory_id",
    "archive_path",
    "archive_label",
    "archive_folder_date",
    "event_timestamp_utc",
    "bea_release_number",
    "event_page_url",
    "update_type",
    "irregular_flag",
    "snapshot_boundary",
    "historical_availability_status",
)
const CAPTURE_KEYS = (
    "source_mode_attested",
    "attestation_authentication",
    "actor",
    "capture_local_date",
    "capture_started_at_utc",
    "capture_completed_at_utc",
    "network_transport_verified",
    "terms_locator",
    "terms_review_attested",
    "terms_review_attested_local_date",
    "terms_review_confers_redistribution_authority",
    "source_agency",
    "source_attribution",
    "present_day_retrieval_only",
)
const LIMIT_KEYS = (
    "max_releases_per_capture",
    "expected_workbook_count",
    "min_workbook_bytes",
    "max_workbook_bytes",
    "max_total_uncompressed_bytes",
    "max_redirects",
    "max_headers_per_response",
    "max_header_name_bytes",
    "max_header_value_bytes",
    "max_url_bytes",
    "response_body_content_encoding",
)
const WORKBOOK_KEYS = (
    "section_id",
    "filename",
    "extension",
    "expected_media_type",
    "validated_magic",
    "requested_url",
    "effective_url",
    "http_status",
    "redirect_count",
    "response_headers_complete",
    "request_headers",
    "response_headers",
    "request_started_at_utc",
    "response_headers_at_utc",
    "response_body_completed_at_utc",
    "observed_byte_count",
    "observed_raw_sha256",
    "object_relative_path",
)
const HEADER_KEYS = ("sequence", "name", "value")

function _validate_header_documents(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    length(value) <= MAX_HEADERS ||
        fail(location, "exceeds the header-count limit")
    headers = Pair{String, String}[]
    for (index, item) in enumerate(value)
        header =
            _expect_exact_keys(item, HEADER_KEYS, "$location[$index]")
        _expect_exact(
            _expect_integer(
                header["sequence"],
                "$location[$index].sequence";
                minimum = 1,
            ),
            index,
            "$location[$index].sequence",
        )
        push!(
            headers,
            _validate_header_pair(
                header["name"] => header["value"],
                "$location[$index]",
            ),
        )
    end
    return Tuple(headers)
end

function _validate_read_only(path, location)
    ispath(path) || fail(location, "does not exist")
    islink(path) && fail(location, "must not be a symbolic link")
    (uperm(path) & 0x02) == 0 ||
        fail(location, "must not be owner-writable")
    (gperm(path) & 0x02) == 0 ||
        fail(location, "must not be group-writable")
    (operm(path) & 0x02) == 0 ||
        fail(location, "must not be other-writable")
    return path
end

function _load_receipt(bundle_path)
    names = sort(readdir(bundle_path))
    receipt_names = filter(
        name -> startswith(name, RECEIPT_PREFIX) && endswith(name, ".toml"),
        names,
    )
    length(receipt_names) == 1 ||
        fail("bundle", "must contain exactly one self-hashed receipt")
    Set(names) == Set(["objects", only(receipt_names)]) ||
        fail("bundle", "contains an unknown top-level entry")
    receipt_path = joinpath(bundle_path, only(receipt_names))
    _validate_read_only(receipt_path, "bundle.receipt")
    isfile(receipt_path) || fail("bundle.receipt", "must be a regular file")
    stat(receipt_path).nlink == 1 ||
        fail("bundle.receipt", "hard-link aliases are forbidden")
    bytes = read(receipt_path)
    length(bytes) <= MAX_RECEIPT_BYTES ||
        fail("bundle.receipt", "exceeds the receipt byte limit")
    document = try
        TOML.parse(String(copy(bytes)))
    catch error
        fail(
            "bundle.receipt",
            "could not parse TOML: $(sprint(showerror, error))",
        )
    end
    _toml_bytes(document) == bytes ||
        fail("bundle.receipt", "is not in canonical sorted TOML form")
    return (; receipt_path, bytes, document)
end

function _validate_source_contract(document, plan)
    source = _expect_exact_keys(
        document["source_contract"],
        SOURCE_CONTRACT_KEYS,
        "receipt.source_contract",
    )
    expected = (
        "metadata_schema_version" => plan.metadata.schema_version,
        "metadata_contract_id" => plan.metadata.contract_id,
        "metadata_content_sha256" => plan.metadata.content_sha256,
        "metadata_file_sha256" => plan.metadata.file_sha256,
        "metadata_file_byte_count" => plan.metadata.file_byte_count,
    )
    for (key, value) in expected
        _expect_exact(source[key], value, "receipt.source_contract.$key")
    end
    return source
end

function _validate_release(document, plan)
    release =
        _expect_exact_keys(document["release"], RELEASE_KEYS, "receipt.release")
    expected = (
        "sequence" => plan.release.sequence,
        "reference_period" => plan.release.reference_period,
        "estimate_family" => plan.release.estimate_family,
        "directory_id" => plan.release.directory_id,
        "archive_path" => plan.release.archive_path,
        "archive_label" => plan.release.archive_label,
        "archive_folder_date" => plan.release.archive_folder_date,
        "event_timestamp_utc" => plan.release.event_timestamp_utc,
        "bea_release_number" => plan.release.bea_release_number,
        "event_page_url" => plan.release.event_page_url,
        "update_type" => plan.release.update_type,
        "irregular_flag" => plan.release.irregular_flag,
        "snapshot_boundary" => SNAPSHOT_BOUNDARY,
        "historical_availability_status" =>
            HISTORICAL_AVAILABILITY_STATUS,
    )
    for (key, value) in expected
        _expect_exact(release[key], value, "receipt.release.$key")
    end
    return release
end

function _validate_capture(document)
    capture =
        _expect_exact_keys(document["capture"], CAPTURE_KEYS, "receipt.capture")
    source_mode_attested = _expect_string(
        capture["source_mode_attested"],
        "receipt.capture.source_mode_attested",
    )
    source_mode_attested in ALLOWED_SOURCE_MODES ||
        fail(
        "receipt.capture.source_mode_attested",
        "has an unsupported value",
    )
    _expect_exact(
        capture["attestation_authentication"],
        ATTESTATION_AUTHENTICATION,
        "receipt.capture.attestation_authentication",
    )
    actor = _actor(capture["actor"], "receipt.capture.actor")
    capture_date =
        _parse_date(capture["capture_local_date"], "receipt.capture.capture_local_date")
    started = _parse_timestamp(
        capture["capture_started_at_utc"],
        "receipt.capture.capture_started_at_utc",
    )
    completed = _parse_timestamp(
        capture["capture_completed_at_utc"],
        "receipt.capture.capture_completed_at_utc",
    )
    started <= completed ||
        fail("receipt.capture", "timestamps are not ordered")
    for (label, timestamp) in (
            "capture_started_at_utc" => started,
            "capture_completed_at_utc" => completed,
        )
        abs(Dates.value(Date(timestamp) - capture_date)) <= 1 ||
            fail(
            "receipt.capture.$label",
            "must fall within one UTC date of capture_local_date",
        )
    end
    is_injected = source_mode_attested == "INJECTED_FETCHER_OUTPUT"
    _expect_exact(
        _expect_bool(
            capture["network_transport_verified"],
            "receipt.capture.network_transport_verified",
        ),
        false,
        "receipt.capture.network_transport_verified",
    )
    _expect_exact(
        capture["terms_locator"],
        TERMS_LOCATOR,
        "receipt.capture.terms_locator",
    )
    reviewed = _expect_bool(
        capture["terms_review_attested"],
        "receipt.capture.terms_review_attested",
    )
    _expect_exact(
        reviewed,
        is_injected,
        "receipt.capture.terms_review_attested",
    )
    if is_injected
        reviewed_date = _parse_date(
            capture["terms_review_attested_local_date"],
            "receipt.capture.terms_review_attested_local_date",
        )
        reviewed_date == capture_date ||
            fail(
            "receipt.capture.terms_review_attested_local_date",
            "must equal capture_local_date",
        )
    else
        _expect_exact(
            capture["terms_review_attested_local_date"],
            NOT_APPLICABLE_TERMS_DATE,
            "receipt.capture.terms_review_attested_local_date",
        )
    end
    for (key, expected) in (
            "terms_review_confers_redistribution_authority" => false,
            "source_agency" => SOURCE_AGENCY,
            "source_attribution" => SOURCE_ATTRIBUTION,
            "present_day_retrieval_only" => true,
        )
        _expect_exact(capture[key], expected, "receipt.capture.$key")
    end
    return (;
        source_mode_attested,
        actor,
        capture_date,
        started,
        completed,
    )
end

function _validate_limits(document)
    limits =
        _expect_exact_keys(document["limits"], LIMIT_KEYS, "receipt.limits")
    expected = (
        "max_releases_per_capture" => MAX_RELEASES_PER_CAPTURE,
        "expected_workbook_count" => EXPECTED_WORKBOOK_COUNT,
        "min_workbook_bytes" => MIN_WORKBOOK_BYTES,
        "max_workbook_bytes" => MAX_WORKBOOK_BYTES,
        "max_total_uncompressed_bytes" =>
            MAX_TOTAL_UNCOMPRESSED_BYTES,
        "max_redirects" => MAX_REDIRECTS,
        "max_headers_per_response" => MAX_HEADERS,
        "max_header_name_bytes" => MAX_HEADER_NAME_BYTES,
        "max_header_value_bytes" => MAX_HEADER_VALUE_BYTES,
        "max_url_bytes" => MAX_URL_BYTES,
        "response_body_content_encoding" => "IDENTITY_OR_ABSENT",
    )
    for (key, value) in expected
        _expect_exact(limits[key], value, "receipt.limits.$key")
    end
    return limits
end

function _validate_workbooks(document, plan, bundle_path, capture)
    workbooks = get(document, "workbooks", nothing)
    workbooks isa AbstractVector ||
        fail("receipt.workbooks", "must be an array")
    length(workbooks) == EXPECTED_WORKBOOK_COUNT ||
        fail("receipt.workbooks", "must contain exactly two entries")
    objects_path = joinpath(bundle_path, "objects")
    _validate_read_only(objects_path, "bundle.objects")
    isdir(objects_path) || fail("bundle.objects", "must be a directory")
    expected_object_names = String[]
    validated = NamedTuple[]
    results = NamedTuple[]
    for (index, (workbook, target)) in
        enumerate(zip(workbooks, plan.workbooks))
        location = "receipt.workbooks[$index]"
        row = _expect_exact_keys(workbook, WORKBOOK_KEYS, location)
        for (key, expected) in (
                "section_id" => target.section_id,
                "filename" => target.filename,
                "extension" => target.extension,
                "expected_media_type" => target.media_type,
                "validated_magic" => _magic_name(target.extension),
                "requested_url" => target.url,
                "effective_url" => target.url,
                "http_status" => 200,
                "redirect_count" => MAX_REDIRECTS,
                "response_headers_complete" => true,
            )
            _expect_exact(row[key], expected, "$location.$key")
        end
        request_headers = _validate_header_documents(
            row["request_headers"],
            "$location.request_headers",
        )
        request_headers == target.request_headers ||
            fail(
            "$location.request_headers",
            "does not match the sealed request",
        )
        byte_count = _expect_integer(
            row["observed_byte_count"],
            "$location.observed_byte_count";
            minimum = MIN_WORKBOOK_BYTES,
        )
        byte_count <= MAX_WORKBOOK_BYTES ||
            fail("$location.observed_byte_count", "exceeds the size limit")
        response_headers = _validate_response_headers(
            Pair{String, String}[
                header for header in _validate_header_documents(
                        row["response_headers"],
                        "$location.response_headers",
                    )
            ],
            target,
            byte_count,
            "$location.response_headers",
        )
        started = _parse_timestamp(
            row["request_started_at_utc"],
            "$location.request_started_at_utc",
        )
        headers_at = _parse_timestamp(
            row["response_headers_at_utc"],
            "$location.response_headers_at_utc",
        )
        completed = _parse_timestamp(
            row["response_body_completed_at_utc"],
            "$location.response_body_completed_at_utc",
        )
        capture.started <= started <= headers_at <= completed <=
            capture.completed ||
            fail("$location.timestamps", "lie outside the capture interval")
        digest =
            _expect_hash(row["observed_raw_sha256"], "$location.observed_raw_sha256")
        expected_relative =
            "objects/sha256-" * digest * "." * target.extension
        _expect_exact(
            row["object_relative_path"],
            expected_relative,
            "$location.object_relative_path",
        )
        object_name = basename(expected_relative)
        push!(expected_object_names, object_name)
        object_path = joinpath(bundle_path, expected_relative)
        dirname(object_path) == objects_path ||
            fail("$location.object_relative_path", "escapes the object store")
        _validate_read_only(object_path, "bundle.object[$index]")
        isfile(object_path) ||
            fail("bundle.object[$index]", "must be a regular file")
        stat(object_path).nlink == 1 ||
            fail(
            "bundle.object[$index]",
            "hard-link aliases are forbidden",
        )
        bytes = read(object_path)
        length(bytes) == byte_count ||
            fail("bundle.object[$index]", "byte count does not match receipt")
        sha256_hex(bytes) == digest ||
            fail("bundle.object[$index]", "SHA-256 does not match receipt")
        magic =
            _validate_magic(bytes, target.extension, "bundle.object[$index]")
        magic == row["validated_magic"] ||
            fail("bundle.object[$index]", "magic classification changed")
        push!(
            results,
            (;
                raw_sha256 = digest,
                raw_byte_count = byte_count,
            ),
        )
        push!(
            validated,
            (;
                section_id = target.section_id,
                filename = target.filename,
                extension = target.extension,
                url = target.url,
                raw_sha256 = digest,
                raw_byte_count = byte_count,
                request_headers = Tuple(request_headers),
                response_headers = Tuple(response_headers),
                request_started_at_utc =
                    String(row["request_started_at_utc"]),
                response_headers_at_utc =
                    String(row["response_headers_at_utc"]),
                response_body_completed_at_utc =
                    String(row["response_body_completed_at_utc"]),
                object_path,
            ),
        )
    end
    sort(readdir(objects_path)) == sort(expected_object_names) ||
        fail("bundle.objects", "contains an unknown or missing object")
    length(Set(result.raw_sha256 for result in results)) ==
        EXPECTED_WORKBOOK_COUNT ||
        fail("receipt.workbooks", "raw-byte digest aliases are forbidden")
    return (; validated = Tuple(validated), results = Tuple(results))
end

function _validate_gates(document)
    gates = _expect_exact_keys(document["gates"], GATE_KEYS, "receipt.gates")
    for key in GATE_KEYS
        _expect_exact(
            _expect_bool(gates[key], "receipt.gates.$key"),
            false,
            "receipt.gates.$key",
        )
    end
    return gates
end

"""
    validate_capture_bundle(bundle_path; metadata_path=...)

Validate a content-addressed capture bundle, its exact raw objects, immutable
permissions, receipt self-hash, metadata pin, schema, headers, timings, and
false gates. The returned trusted view contains only immutable named tuples
and tuples; it never exposes the parsed TOML dictionaries or raw byte vectors.
"""
function validate_capture_bundle(
        bundle_path::AbstractString;
        metadata_path::AbstractString =
            BEAHMI7AdvanceMetadataManifest.DEFAULT_MANIFEST_PATH,
    )
    path = String(bundle_path)
    isabspath(path) || fail("bundle", "path must be absolute")
    normpath(path) == path ||
        fail("bundle", "path must be normalized without traversal aliases")
    _validate_read_only(path, "bundle")
    isdir(path) || fail("bundle", "must be a directory")
    realpath(path) == path ||
        fail("bundle", "must be its canonical filesystem path")
    basename_value = basename(path)
    startswith(basename_value, BUNDLE_PREFIX) ||
        fail("bundle", "name must use the content-addressed prefix")
    path_digest = basename_value[(ncodeunits(BUNDLE_PREFIX) + 1):end]
    _expect_hash(path_digest, "bundle.name_digest")
    source = _load_receipt(path)
    document = _expect_exact_keys(source.document, ROOT_KEYS, "receipt")
    artifact = _expect_exact_keys(
        document["artifact"],
        ARTIFACT_KEYS,
        "receipt.artifact",
    )
    for (key, expected) in (
            "schema_version" => SCHEMA_VERSION,
            "canonicalization" => CANONICALIZATION,
            "digest_algorithm" => DIGEST_ALGORITHM,
            "immutable_bundle" => true,
        )
        _expect_exact(artifact[key], expected, "receipt.artifact.$key")
    end
    declared =
        _expect_hash(artifact["receipt_sha256"], "receipt.artifact.receipt_sha256")
    _expect_exact(declared, path_digest, "receipt.artifact.receipt_sha256")
    expected_receipt_name = RECEIPT_PREFIX * declared * ".toml"
    _expect_exact(
        basename(source.receipt_path),
        expected_receipt_name,
        "bundle.receipt.name",
    )
    computed = receipt_sha256(document)
    _expect_exact(
        declared,
        computed,
        "receipt.artifact.receipt_sha256",
    )
    pair_digest =
        _expect_hash(artifact["pair_sha256"], "receipt.artifact.pair_sha256")
    sequence = _expect_integer(
        get(document["release"], "sequence", nothing),
        "receipt.release.sequence";
        minimum = 1,
    )
    plan = _capture_plan(sequence, metadata_path)
    _validate_source_contract(document, plan)
    _validate_release(document, plan)
    capture = _validate_capture(document)
    _validate_limits(document)
    workbook_validation =
        _validate_workbooks(document, plan, path, capture)
    _expect_exact(
        pair_digest,
        _pair_sha256(plan, workbook_validation.results),
        "receipt.artifact.pair_sha256",
    )
    _validate_gates(document)
    return (;
        bundle_path = path,
        receipt_path = source.receipt_path,
        receipt_sha256 = declared,
        receipt_file_sha256 = sha256_hex(source.bytes),
        pair_sha256 = pair_digest,
        source_contract = (;
            metadata_schema_version = plan.metadata.schema_version,
            metadata_contract_id = plan.metadata.contract_id,
            metadata_content_sha256 = plan.metadata.content_sha256,
            metadata_file_sha256 = plan.metadata.file_sha256,
            metadata_file_byte_count = plan.metadata.file_byte_count,
        ),
        release = plan.release,
        capture = (;
            source_mode_attested = capture.source_mode_attested,
            attestation_authentication =
                ATTESTATION_AUTHENTICATION,
            network_transport_verified = false,
            actor = capture.actor,
            capture_local_date = string(capture.capture_date),
            capture_started_at_utc =
                String(document["capture"]["capture_started_at_utc"]),
            capture_completed_at_utc =
                String(document["capture"]["capture_completed_at_utc"]),
            present_day_retrieval_only = true,
        ),
        workbooks = workbook_validation.validated,
        gates = NamedTuple{
            Tuple(Symbol.(GATE_KEYS)),
        }(ntuple(_ -> false, length(GATE_KEYS))),
    )
end

end
