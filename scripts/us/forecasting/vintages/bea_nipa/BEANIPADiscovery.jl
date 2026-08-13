module BEANIPADiscovery

using Dates
using HTTP
using JSON
using SHA
using TOML

export BEADiscoveryError,
    INTERNAL_RELEASE_ROOT,
    ROOT_DISCOVERY_URL,
    ReleaseDirectory,
    ReleaseWorkbook,
    Tier1DiscoveryCatalog,
    Tier1TargetDiscovery,
    TIER1_MAPPING_CONTRACT_VERSION,
    build_tier1_catalog,
    directory_id_url,
    discover_release_directories,
    discover_release_workbooks,
    live_discover,
    official_file_url,
    parse_directory_id,
    parse_resolved_path,
    release_files_url,
    resolved_path_url,
    sha256_hex,
    tier1_table_map,
    validate_effective_uri

const ROOT_DISCOVERY_URL =
    "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/" *
    "?HistMainId=7&getFiles=false&getDirs=true"
const DIRECTORY_ID_ENDPOINT =
    "https://apps.bea.gov/histdata/core/data/UrlPath_getID/"
const RESOLVED_PATH_ENDPOINT =
    "https://apps.bea.gov/histdata/core/data/getPath/"
const RELEASE_FILES_ENDPOINT =
    "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/"
const INTERNAL_HISTDATA_ROOT =
    "/Inetpub/wwwroot/website/website/HistData/"
const INTERNAL_RELEASE_ROOT =
    INTERNAL_HISTDATA_ROOT * "Files/Releases/GDP_and_PI"
const OFFICIAL_HISTDATA_ROOT = "https://apps.bea.gov/HistData/"
const OFFICIAL_HOST = "apps.bea.gov"
const MAIN_NAME = "National Accounts (NIPA)"
const FOLDER_PATTERN = "GDP_and_PI\\dataYear\\Quarter\\vintage_NewReleaseDate"
const TIER1_MAPPING_CONTRACT_VERSION =
    "beforeit-us-bea-nipa-protocol-to-hmi7-workbook.v2"
const TIER1_MAPPING_CONTRACT_PATH =
    joinpath(@__DIR__, "protocol_to_hmi7_workbook_mapping.toml")
const HISTORICAL_WORKBOOK_SECTION_STATUS =
    "UNRESOLVED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION"
const HISTORICAL_ROW_MAPPING_STATUS =
    "UNVERIFIED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION"
const RECOGNIZED_RELEASE_KINDS = Set(
    [
        "1. Advance",
        "2. Final",
        "2. Preliminary",
        "3. Final",
        "3. Preliminary",
        "Advance",
        "Initial",
        "Second",
        "Third",
        "Updated",
    ],
)
const TARGET_IDS = Set(
    [
        "core_pce_price_index",
        "gdp_deflator",
        "nominal_gdp",
        "pce_price_index",
        "real_gdp",
    ],
)
const DISCOVERY_SCOPE = "official_archive_locator_metadata_only"
const NOT_ACQUIRED = "NOT_ACQUIRED"
const NOT_VERIFIED = "NOT_VERIFIED"

struct BEADiscoveryError <: Exception
    message::String
end

Base.showerror(io::IO, error::BEADiscoveryError) = print(io, error.message)

fail(location, message) =
    throw(BEADiscoveryError("$location: $message"))

struct ReleaseDirectory
    internal_path::String
    reference_year::Int
    reference_quarter::Int
    archive_label::String
    archive_label_date_text::Union{Nothing, String}
    archive_label_date::Union{Nothing, Date}
end

struct ReleaseWorkbook
    internal_path::String
    official_locator::String
    filename::String
    section_id::String
    publication_variant::String
end

struct Tier1TargetDiscovery
    target_id::String
    mapping_contract_version::String
    protocol_current_source_observation_id::String
    protocol_current_source_table_id::String
    protocol_current_source_line_number::Int
    protocol_current_source_series_code::String
    protocol_current_expected_hmi7_workbook_section::String
    archive_directory_id::String
    directory_path_reverse_checked::Bool
    release_internal_path::String
    discovery_scope::String
    release_bytes_status::String
    workbook_contents_status::String
    historical_workbook_section_status::String
    historical_row_mapping_status::String
    exact_availability_status::String
    origin_admissible::Bool
    ready::Bool
end

struct Tier1DiscoveryCatalog
    archive_directory_id::String
    directory_path_reverse_checked::Bool
    release_internal_path::String
    main_workbooks::Vector{ReleaseWorkbook}
    target_discoveries::Vector{Tier1TargetDiscovery}
    origin_admissible::Bool
    ready::Bool
end

function _document(payload, location)
    if payload isa AbstractDict
        return payload
    elseif payload isa AbstractVector{UInt8}
        try
            return JSON.parse(String(payload))
        catch error
            fail(location, "is not valid UTF-8 JSON ($(sprint(showerror, error)))")
        end
    elseif payload isa AbstractVector
        return payload
    elseif payload isa AbstractString
        try
            return JSON.parse(String(payload))
        catch error
            fail(location, "is not valid JSON ($(sprint(showerror, error)))")
        end
    end
    return fail(location, "must be JSON text, bytes, or a parsed object")
end

function _table(value, location)
    value isa AbstractDict || fail(location, "must be a JSON object")
    return value
end

function _array(value, location)
    value isa AbstractVector || fail(location, "must be a JSON array")
    return value
end

function _string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    isempty(text) && fail(location, "must not be empty")
    return text
end

function _field(table, key, location)
    haskey(table, key) || fail(location, "missing key $key")
    return table[key]
end

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(sha256(bytes))
sha256_hex(text::AbstractString) = sha256_hex(Vector{UInt8}(codeunits(text)))

"""
    validate_effective_uri(value)

Require an HTTPS URI on BEA's exact official host. This is applied to both the
requested URI and HTTP.jl's final response URI after redirects.
"""
function validate_effective_uri(value::AbstractString)
    text = String(value)
    text == strip(text) ||
        fail("effective_uri", "must not contain surrounding whitespace")
    uri = try
        HTTP.URI(text)
    catch error
        fail("effective_uri", "is invalid ($(sprint(showerror, error)))")
    end
    lowercase(uri.scheme) == "https" ||
        fail("effective_uri", "must use HTTPS")
    lowercase(uri.host) == OFFICIAL_HOST ||
        fail("effective_uri", "must use the exact apps.bea.gov host")
    uri.port in ("", "443") ||
        fail("effective_uri", "must use the default HTTPS port")
    isempty(uri.userinfo) ||
        fail("effective_uri", "must not contain user information")
    isempty(uri.fragment) ||
        fail("effective_uri", "must not contain a fragment")
    return string(uri)
end

function _parse_archive_label_date(label)
    separator = findlast(==('_'), label)
    separator === nothing && return (nothing, nothing)
    separator == lastindex(label) && return (nothing, nothing)
    release_kind = label[begin:prevind(label, separator)]
    release_kind in RECOGNIZED_RELEASE_KINDS || return (nothing, nothing)
    date_text = label[nextind(label, separator):end]
    parsed = tryparse(Date, date_text, dateformat"U-d-y")
    return parsed === nothing ? (date_text, nothing) : (date_text, parsed)
end

function _release_directory(path)
    prefix = INTERNAL_RELEASE_ROOT * "\\"
    startswith(path, prefix) || return nothing
    suffix = path[nextind(path, lastindex(INTERNAL_RELEASE_ROOT)):end]
    startswith(suffix, "\\") || return nothing
    segments = split(suffix[2:end], '\\'; keepempty = true)
    length(segments) == 3 || return nothing

    year_text, quarter_text, archive_label = segments
    occursin(r"^\d{4}$", year_text) || return nothing
    occursin(r"^[Qq][1-4]$", quarter_text) || return nothing
    isempty(archive_label) && return nothing
    date_text, archive_date = _parse_archive_label_date(archive_label)
    archive_date === nothing && return nothing
    return ReleaseDirectory(
        path,
        parse(Int, year_text),
        parse(Int, quarter_text[end:end]),
        archive_label,
        date_text,
        archive_date,
    )
end

"""
    discover_release_directories(payload)

Parse the HMI7 directory-listing response and return only exact release
directories. Year, quarter, release-date labels, and nested `UND` directories
in the same `FileArray` are not mistaken for releases. An archive label date is
descriptive metadata only; this function does not establish an availability
timestamp.
"""
function discover_release_directories(payload)
    document = _table(_document(payload, "directory response"), "directory response")
    main_name =
        _string(_field(document, "MainName", "directory response"), "MainName")
    main_name == MAIN_NAME ||
        fail("MainName", "expected $(repr(MAIN_NAME)), found $(repr(main_name))")
    folder_pattern = _string(
        _field(document, "FolderPattern", "directory response"),
        "FolderPattern",
    )
    folder_pattern == FOLDER_PATTERN ||
        fail(
        "FolderPattern",
        "expected $(repr(FOLDER_PATTERN)), found $(repr(folder_pattern))",
    )
    paths =
        _array(_field(document, "FileArray", "directory response"), "FileArray")

    releases = ReleaseDirectory[]
    seen = Set{String}()
    for (index, value) in pairs(paths)
        path = _string(value, "FileArray[$index]")
        release = _release_directory(path)
        release === nothing && continue
        release.internal_path in seen &&
            fail("FileArray[$index]", "duplicates release path $(repr(path))")
        push!(seen, release.internal_path)
        push!(releases, release)
    end
    sort!(releases; by = release -> release.internal_path)
    return releases
end

function _single_record(payload, location)
    document = _array(_document(payload, location), location)
    length(document) == 1 ||
        fail(location, "must contain exactly one record")
    return _table(only(document), "$location[1]")
end

"""
    parse_directory_id(payload)

Validate the shape of a path-to-ID response. The response contains no path, so
this parser cannot bind the returned ID to a request path. A discovery session
must resolve the ID back to a path and compare that path with its request.
"""
function parse_directory_id(payload)
    record = _single_record(payload, "directory ID response")
    directory_id =
        _string(_field(record, "Theid", "directory ID response"), "Theid")
    occursin(r"^\d+$", directory_id) ||
        fail("Theid", "must contain decimal digits only")
    return directory_id
end

"""
    parse_resolved_path(payload, requested_id)

Validate the shape of an ID-to-path response and require an HMI7 release path.
`requested_id` identifies the request but is absent from the response body, so
callers must still reverse-check the returned path against the original path.
"""
function parse_resolved_path(payload, requested_id::AbstractString)
    id = String(requested_id)
    occursin(r"^\d+$", id) ||
        fail("requested_id", "must contain decimal digits only")
    record = _single_record(payload, "resolved path response")
    path = _string(
        _field(record, "Thepath", "resolved path response"),
        "Thepath",
    )
    _release_directory(path) === nothing &&
        fail("Thepath", "is not an HMI7 release directory")
    return path
end

function _percent_encode(text::AbstractString)
    io = IOBuffer()
    for byte in codeunits(String(text))
        if (
                UInt8('A') <= byte <= UInt8('Z') ||
                    UInt8('a') <= byte <= UInt8('z') ||
                    UInt8('0') <= byte <= UInt8('9') ||
                    byte in UInt8.(['-', '.', '_', '~'])
            )
            write(io, byte)
        else
            print(io, '%', uppercase(string(byte; base = 16, pad = 2)))
        end
    end
    return String(take!(io))
end

function directory_id_url(path::AbstractString)
    _release_directory(String(path)) === nothing &&
        fail("path", "is not an HMI7 release directory")
    return DIRECTORY_ID_ENDPOINT * "?UrlPath=" * _percent_encode(path)
end

function resolved_path_url(directory_id::AbstractString)
    id = String(directory_id)
    occursin(r"^\d+$", id) ||
        fail("directory_id", "must contain decimal digits only")
    return RESOLVED_PATH_ENDPOINT * id
end

function release_files_url(path::AbstractString)
    _release_directory(String(path)) === nothing &&
        fail("path", "is not an HMI7 release directory")
    return RELEASE_FILES_ENDPOINT *
        "?HistMainId=7&thePath=" *
        _percent_encode(path) *
        "&getFiles=true&getDirs=false"
end

function official_file_url(internal_path::AbstractString)
    path = String(internal_path)
    prefix = INTERNAL_RELEASE_ROOT * "\\"
    startswith(path, prefix) ||
        fail("internal_path", "is outside the official HMI7 release root")
    relative = path[nextind(path, lastindex(INTERNAL_RELEASE_ROOT)):end]
    startswith(relative, "\\") ||
        fail("internal_path", "does not use the canonical HMI7 separator")
    relative = relative[2:end]
    occursin('/', relative) &&
        fail("internal_path", "does not use the canonical HMI7 separator")
    segments = split(relative, '\\'; keepempty = true)
    any(isempty, segments) &&
        fail("internal_path", "contains an empty path segment")
    any(segment -> segment in (".", ".."), segments) &&
        fail("internal_path", "contains a dot path segment")
    release_root = "Files/Releases/GDP_and_PI/"
    return OFFICIAL_HISTDATA_ROOT *
        release_root *
        join(_percent_encode.(segments), "/")
end

function _workbook(path, expected_release_path)
    prefix = expected_release_path * "\\"
    startswith(path, prefix) || return nothing
    relative = path[nextind(path, lastindex(expected_release_path)):end]
    startswith(relative, "\\") || return nothing
    segments = split(relative[2:end], '\\'; keepempty = true)

    publication_variant = if length(segments) == 1
        "published_main"
    elseif length(segments) == 2 && uppercase(segments[1]) == "UND"
        "unadjusted"
    else
        return nothing
    end
    filename = last(segments)
    matched =
        match(r"(?i)^Section([0-9]+|S)all_xls\.(xls|xlsx)$", filename)
    matched === nothing && return nothing
    return ReleaseWorkbook(
        path,
        official_file_url(path),
        filename,
        uppercase(matched.captures[1]),
        publication_variant,
    )
end

"""
    discover_release_workbooks(payload, expected_release_path)

Parse an HMI7 file-list response and return Excel section workbooks. The result
is a locator catalog only: no workbook is downloaded, hashed, or inspected.
"""
function discover_release_workbooks(payload, expected_release_path::AbstractString)
    release_path = String(expected_release_path)
    _release_directory(release_path) === nothing &&
        fail("expected_release_path", "is not an HMI7 release directory")
    document =
        _table(_document(payload, "release files response"), "release files response")
    main_name =
        _string(_field(document, "MainName", "release files response"), "MainName")
    main_name == MAIN_NAME ||
        fail("MainName", "expected $(repr(MAIN_NAME)), found $(repr(main_name))")
    paths = _array(
        _field(document, "Filearray3", "release files response"),
        "Filearray3",
    )

    workbooks = ReleaseWorkbook[]
    seen = Set{Tuple{String, String}}()
    for (index, value) in pairs(paths)
        path = _string(value, "Filearray3[$index]")
        workbook = _workbook(path, release_path)
        workbook === nothing && continue
        key = (workbook.section_id, workbook.publication_variant)
        key in seen &&
            fail(
            "Filearray3[$index]",
            "duplicates section $(workbook.section_id) " *
                "$(workbook.publication_variant) workbook",
        )
        push!(seen, key)
        push!(workbooks, workbook)
    end
    sort!(
        workbooks;
        by = workbook -> (workbook.publication_variant, workbook.section_id),
    )
    return workbooks
end

"""
Load the versioned mapping from current protocol selectors to expected HMI7
section workbooks. Protocol line numbers are never treated as historical row
selectors; each historical workbook requires vintage-aware content validation.
"""
function tier1_table_map()
    document = TOML.parsefile(TIER1_MAPPING_CONTRACT_PATH)
    artifact = _table(
        _field(document, "artifact", "mapping contract"),
        "mapping contract.artifact",
    )
    contract_id = _string(
        _field(artifact, "contract_id", "mapping contract.artifact"),
        "mapping contract.artifact.contract_id",
    )
    contract_id == TIER1_MAPPING_CONTRACT_VERSION ||
        fail(
        "mapping contract.artifact.contract_id",
        "expected $(repr(TIER1_MAPPING_CONTRACT_VERSION))",
    )
    status = _string(
        _field(artifact, "status", "mapping contract.artifact"),
        "mapping contract.artifact.status",
    )
    status == "DISCOVERY_ONLY_HISTORICAL_SECTION_AND_ROWS_UNRESOLVED" ||
        fail("mapping contract.artifact.status", "is not fail-closed")
    get(
        artifact,
        "protocol_current_section_reuse_across_vintages_allowed",
        nothing,
    ) ===
        false ||
        fail(
        "mapping contract.artifact." *
            "protocol_current_section_reuse_across_vintages_allowed",
        "must be false",
    )
    get(
        artifact,
        "protocol_current_line_reuse_across_vintages_allowed",
        nothing,
    ) ===
        false ||
        fail(
        "mapping contract.artifact." *
            "protocol_current_line_reuse_across_vintages_allowed",
        "must be false",
    )
    get(
        artifact,
        "historical_workbook_section_mapping_verified",
        nothing,
    ) === false ||
        fail(
        "mapping contract.artifact." *
            "historical_workbook_section_mapping_verified",
        "must be false",
    )
    get(artifact, "historical_row_mapping_verified", nothing) === false ||
        fail(
        "mapping contract.artifact.historical_row_mapping_verified",
        "must be false",
    )
    get(artifact, "origin_admissible", nothing) === false ||
        fail(
        "mapping contract.artifact.origin_admissible",
        "must be false",
    )
    get(artifact, "ready", nothing) === false ||
        fail("mapping contract.artifact.ready", "must be false")

    raw_rows = _array(
        _field(document, "target_mappings", "mapping contract"),
        "mapping contract.target_mappings",
    )
    rows = NamedTuple[]
    seen_targets = Set{String}()
    for (index, raw_row) in pairs(raw_rows)
        location = "mapping contract.target_mappings[$index]"
        row = _table(raw_row, location)
        target_id =
            _string(_field(row, "target_id", location), "$location.target_id")
        target_id in seen_targets &&
            fail("$location.target_id", "duplicates $(repr(target_id))")
        push!(seen_targets, target_id)
        observation_id = _string(
            _field(
                row,
                "protocol_current_source_observation_id",
                location,
            ),
            "$location.protocol_current_source_observation_id",
        )
        table_id = _string(
            _field(row, "protocol_current_source_table_id", location),
            "$location.protocol_current_source_table_id",
        )
        line_number =
            _field(row, "protocol_current_source_line_number", location)
        line_number isa Integer && line_number > 0 ||
            fail(
            "$location.protocol_current_source_line_number",
            "must be positive",
        )
        observation_id == "$table_id:$line_number" ||
            fail(
            "$location.protocol_current_source_observation_id",
            "does not match the protocol table and line",
        )
        series_code = _string(
            _field(row, "protocol_current_source_series_code", location),
            "$location.protocol_current_source_series_code",
        )
        current_section = _string(
            _field(
                row,
                "protocol_current_expected_hmi7_workbook_section",
                location,
            ),
            "$location.protocol_current_expected_hmi7_workbook_section",
        )
        current_section in ("1", "2") ||
            fail(
            "$location.protocol_current_expected_hmi7_workbook_section",
            "must be \"1\" or \"2\"",
        )
        historical_section_status = _string(
            _field(row, "historical_workbook_section_status", location),
            "$location.historical_workbook_section_status",
        )
        historical_section_status == HISTORICAL_WORKBOOK_SECTION_STATUS ||
            fail(
            "$location.historical_workbook_section_status",
            "must remain unresolved",
        )
        historical_row_status = _string(
            _field(row, "historical_row_mapping_status", location),
            "$location.historical_row_mapping_status",
        )
        historical_row_status == HISTORICAL_ROW_MAPPING_STATUS ||
            fail(
            "$location.historical_row_mapping_status",
            "must remain unverified",
        )
        push!(
            rows,
            (
                target_id = target_id,
                protocol_current_source_observation_id = observation_id,
                protocol_current_source_table_id = table_id,
                protocol_current_source_line_number = Int(line_number),
                protocol_current_source_series_code = series_code,
                protocol_current_expected_hmi7_workbook_section =
                    current_section,
                historical_workbook_section_status =
                    historical_section_status,
                historical_row_mapping_status = historical_row_status,
            ),
        )
    end
    seen_targets == TARGET_IDS ||
        fail(
        "mapping contract.target_mappings",
        "does not exactly cover the five BEA targets",
    )
    return rows
end

"""
    build_tier1_catalog(release, archive_directory_id, resolved_path, workbooks)

Build two separate discovery products: the complete catalog of discovered main
section workbooks and five target records carrying current protocol selectors.
No target record is attached to a discovered workbook. Both the historical
workbook section and row remain unresolved, and a missing current-era section
never suppresses a target record.
"""
function build_tier1_catalog(
        release::ReleaseDirectory,
        archive_directory_id::AbstractString,
        resolved_path::AbstractString,
        workbooks::AbstractVector{ReleaseWorkbook},
        ;
        directory_path_reverse_checked::Bool = false,
    )
    id = String(archive_directory_id)
    occursin(r"^\d+$", id) ||
        fail("archive_directory_id", "must contain decimal digits only")
    path = String(resolved_path)
    path == release.internal_path ||
        fail("resolved_path", "does not equal the requested release path")

    main_by_section = Dict{String, ReleaseWorkbook}()
    for (index, workbook) in pairs(workbooks)
        startswith(workbook.internal_path, path * "\\") ||
            fail(
            "workbooks[$index].internal_path",
            "is not a child of the resolved release path",
        )
        parsed_workbook = _workbook(workbook.internal_path, path)
        parsed_workbook === nothing &&
            fail(
            "workbooks[$index]",
            "is not a canonical HMI7 section workbook",
        )
        (
            workbook.official_locator == parsed_workbook.official_locator &&
                workbook.filename == parsed_workbook.filename &&
                workbook.section_id == parsed_workbook.section_id &&
                workbook.publication_variant ==
                parsed_workbook.publication_variant
        ) ||
            fail(
            "workbooks[$index]",
            "fields do not match the parsed official workbook path",
        )
        workbook.publication_variant == "published_main" || continue
        haskey(main_by_section, workbook.section_id) &&
            fail(
            "workbooks",
            "contains duplicate main workbook for section " *
                workbook.section_id,
        )
        main_by_section[workbook.section_id] = workbook
    end
    main_workbooks = sort!(
        collect(values(main_by_section));
        by = workbook -> workbook.section_id,
    )

    mapping = tier1_table_map()
    Set(row.target_id for row in mapping) == TARGET_IDS ||
        fail("tier1_table_map", "does not exactly cover the five BEA targets")
    target_discoveries = Tier1TargetDiscovery[]
    for row in mapping
        push!(
            target_discoveries,
            Tier1TargetDiscovery(
                row.target_id,
                TIER1_MAPPING_CONTRACT_VERSION,
                row.protocol_current_source_observation_id,
                row.protocol_current_source_table_id,
                row.protocol_current_source_line_number,
                row.protocol_current_source_series_code,
                row.protocol_current_expected_hmi7_workbook_section,
                id,
                directory_path_reverse_checked,
                path,
                DISCOVERY_SCOPE,
                NOT_ACQUIRED,
                NOT_VERIFIED,
                row.historical_workbook_section_status,
                row.historical_row_mapping_status,
                NOT_VERIFIED,
                false,
                false,
            ),
        )
    end
    sort!(target_discoveries; by = target -> target.target_id)
    return Tier1DiscoveryCatalog(
        id,
        directory_path_reverse_checked,
        path,
        main_workbooks,
        target_discoveries,
        false,
        false,
    )
end

function _http_get(url)
    requested_uri = validate_effective_uri(String(url))
    response = HTTP.get(
        requested_uri;
        connect_timeout = 15,
        readtimeout = 30,
        redirect = true,
        retries = 0,
        status_exception = true,
        headers = ["User-Agent" => "BeforeIT-US-BEA-discovery/1.0"],
    )
    bytes = Vector{UInt8}(response.body)
    isempty(bytes) && fail("live response", "was empty for $requested_uri")
    effective_uri =
        validate_effective_uri(string(response.request.url))
    return (
        bytes = bytes,
        sha256 = sha256_hex(bytes),
        effective_uri = effective_uri,
    )
end

function _release_dict(release)
    return Dict(
        "internal_path" => release.internal_path,
        "reference_year" => release.reference_year,
        "reference_quarter" => release.reference_quarter,
        "archive_label" => release.archive_label,
        "archive_label_date_text" => something(
            release.archive_label_date_text,
            "",
        ),
        "archive_label_date_status" => "DESCRIPTIVE_ONLY_NOT_AVAILABILITY",
    )
end

function _workbook_dict(workbook)
    return Dict(
        "section_id" => workbook.section_id,
        "filename" => workbook.filename,
        "publication_variant" => workbook.publication_variant,
        "internal_path" => workbook.internal_path,
        "official_locator" => workbook.official_locator,
        "release_bytes_status" => NOT_ACQUIRED,
        "workbook_contents_status" => NOT_VERIFIED,
    )
end

function _target_discovery_dict(target)
    return Dict(
        "target_id" => target.target_id,
        "mapping_contract_version" => target.mapping_contract_version,
        "protocol_current_source_observation_id" =>
            target.protocol_current_source_observation_id,
        "protocol_current_source_table_id" =>
            target.protocol_current_source_table_id,
        "protocol_current_source_line_number" =>
            target.protocol_current_source_line_number,
        "protocol_current_source_series_code" =>
            target.protocol_current_source_series_code,
        "protocol_current_expected_hmi7_workbook_section" =>
            target.protocol_current_expected_hmi7_workbook_section,
        "archive_directory_id" => target.archive_directory_id,
        "directory_path_reverse_checked" =>
            target.directory_path_reverse_checked,
        "release_internal_path" => target.release_internal_path,
        "discovery_scope" => target.discovery_scope,
        "release_bytes_status" => target.release_bytes_status,
        "workbook_contents_status" => target.workbook_contents_status,
        "historical_workbook_section_status" =>
            target.historical_workbook_section_status,
        "historical_row_mapping_status" =>
            target.historical_row_mapping_status,
        "exact_availability_status" => target.exact_availability_status,
        "origin_admissible" => target.origin_admissible,
        "ready" => target.ready,
    )
end

"""
    live_discover(year, quarter; archive_label_contains)

Opt-in live metadata probe. It downloads JSON discovery responses only; it
never downloads the listed Excel workbooks and never mutates the release
inventory. Each metadata response receives a SHA-256 in the returned audit
object.
"""
function live_discover(
        year::Integer,
        quarter::Integer;
        archive_label_contains::AbstractString,
    )
    2000 <= year <= 2099 || fail("year", "must be between 2000 and 2099")
    1 <= quarter <= 4 || fail("quarter", "must be between 1 and 4")
    needle = lowercase(String(archive_label_contains))
    isempty(needle) && fail("archive_label_contains", "must not be empty")

    root = _http_get(ROOT_DISCOVERY_URL)
    releases = filter(
        release ->
        release.reference_year == year &&
            release.reference_quarter == quarter &&
            occursin(needle, lowercase(release.archive_label)),
        discover_release_directories(root.bytes),
    )
    length(releases) == 1 ||
        fail(
        "live selection",
        "expected one matching release, found $(length(releases))",
    )
    release = only(releases)

    id_request_locator = directory_id_url(release.internal_path)
    id_response = _http_get(id_request_locator)
    directory_id = parse_directory_id(id_response.bytes)
    path_request_locator = resolved_path_url(directory_id)
    path_response = _http_get(path_request_locator)
    resolved_path = parse_resolved_path(path_response.bytes, directory_id)
    resolved_path == release.internal_path ||
        fail("live resolved path", "does not equal the requested path")
    files_request_locator = release_files_url(resolved_path)
    files_response = _http_get(files_request_locator)
    workbooks =
        discover_release_workbooks(files_response.bytes, resolved_path)
    catalog =
        build_tier1_catalog(
        release,
        directory_id,
        resolved_path,
        workbooks;
        directory_path_reverse_checked = true,
    )

    return Dict(
        "schema_version" => "beforeit-us-bea-nipa-discovery-probe.v2",
        "status" => "DISCOVERY_METADATA_ONLY_NOT_ACQUIRED",
        "release" => _release_dict(release),
        "archive_directory_id" => directory_id,
        "directory_path_reverse_checked" => true,
        "request_locators" => Dict(
            "directory_listing" => ROOT_DISCOVERY_URL,
            "directory_id" => id_request_locator,
            "resolved_path" => path_request_locator,
            "release_files" => files_request_locator,
        ),
        "effective_response_uris" => Dict(
            "directory_listing" => root.effective_uri,
            "directory_id" => id_response.effective_uri,
            "resolved_path" => path_response.effective_uri,
            "release_files" => files_response.effective_uri,
        ),
        "response_sha256" => Dict(
            "directory_listing" => root.sha256,
            "directory_id" => id_response.sha256,
            "resolved_path" => path_response.sha256,
            "release_files" => files_response.sha256,
        ),
        "discovered_workbook_count" => length(workbooks),
        "discovered_main_workbook_count" =>
            length(catalog.main_workbooks),
        "discovered_unadjusted_workbook_count" => count(
            workbook -> workbook.publication_variant == "unadjusted",
            workbooks,
        ),
        "main_workbook_catalog" =>
            _workbook_dict.(catalog.main_workbooks),
        "target_discovery_count" =>
            length(catalog.target_discoveries),
        "target_discoveries" =>
            _target_discovery_dict.(catalog.target_discoveries),
        "release_bytes_acquired" => false,
        "release_bytes_verified" => false,
        "workbook_contents_verified" => false,
        "historical_workbook_section_mappings_verified" => false,
        "historical_row_mappings_verified" => false,
        "exact_availability_verified" => false,
        "origin_admissible" => catalog.origin_admissible,
        "ready" => catalog.ready,
    )
end

end
