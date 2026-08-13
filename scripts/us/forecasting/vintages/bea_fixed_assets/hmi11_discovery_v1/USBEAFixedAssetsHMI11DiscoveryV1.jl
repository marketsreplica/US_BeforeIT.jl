module USBEAFixedAssetsHMI11DiscoveryV1

using Dates
using SHA
using TOML

export DiscoveryError,
    build_discovery_plan,
    load_profile,
    validate_discovery_plan,
    validate_profile_document

const SCHEMA_VERSION =
    "beforeit-us-bea-fixed-assets-hmi11-discovery-profile.v1"
const STATUS = "CANNOT_RUN"
const ROLE = "DISCOVERY_MECHANICS_ONLY"
const CANONICALIZATION =
    "sorted-typed-length-prefixed-v1-excluding-artifact-content-sha256"
const PROFILE_CONTENT_SHA256 =
    "96d0f93b4bf538b45fac44843f47dfd0e8aa8ca4a8e9125cfd3861e2de9e6921"
const PROFILE_PHYSICAL_SHA256 =
    "656717ea525efd341004004f3f9be9d22ffccd7d36e5e84e90aabac9cad9d44c"
const PROFILE_PATH =
    joinpath(@__DIR__, "bea_fixed_assets_hmi11_discovery_profile_v1.toml")
const REPOSITORY_ROOT =
    dirname(dirname(dirname(dirname(dirname(dirname(@__DIR__))))))
const _SOURCE_VERIFICATION_TEST_PROBE = Ref{Union{Nothing, Function}}(nothing)

const HMI_ID = 11
const MAIN_NAME = "Fixed Asset"
const FOLDER_PATTERN = "FA\\dataYear\\vintage_NewReleaseDate"
const INTERNAL_HISTDATA_ROOT =
    "/Inetpub/wwwroot/website/website/HistData/"
const INTERNAL_RELEASE_ROOT = INTERNAL_HISTDATA_ROOT * "Files/Releases/FA"
const OFFICIAL_HISTDATA_ROOT = "https://apps.bea.gov/HistData/"
const ROOT_DISCOVERY_URL =
    "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/" *
    "?HistMainId=11&getFiles=false&getDirs=true"
const DIRECTORY_ID_ENDPOINT =
    "https://apps.bea.gov/histdata/core/data/UrlPath_getID/"
const RESOLVED_PATH_ENDPOINT =
    "https://apps.bea.gov/histdata/core/data/getPath/"
const RELEASE_FILES_ENDPOINT =
    "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/"

const MAX_JSON_BODY_BYTES = 1_048_576
const MAX_JSON_NESTING_DEPTH = 32
const MAX_JSON_STRING_BYTES = 65_536
const MAX_JSON_ARRAY_ITEMS = 4_096
const MAX_JSON_OBJECT_MEMBERS = 64
const MAX_JSON_NUMBER_BYTES = 128
const MAX_PROFILE_BYTES = 1_048_576
const MAX_CANONICAL_DEPTH = 64
const MAX_CANONICAL_ITEMS = 4_096
const MAX_CANONICAL_STRING_BYTES = 1_048_576
const MAX_CANONICAL_KEY_BYTES = 512
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const DECIMAL_ID_PATTERN = r"^[1-9][0-9]*$"
const JSON_NUMBER_PATTERN =
    r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"
const RELEASE_LABEL_PATTERN =
    r"^AnnualUpdate_([A-Z][a-z]+)-([1-9]|[12][0-9]|3[01])-(\d{4})$"
const RELEASE_DATE_FORMAT = dateformat"U-d-yyyy"
const SECTION_WORKBOOK_PATTERN =
    r"^section([0-9]+)all_xls\.(xlsx|xls)$"
const REQUIRED_SECTIONS = ("3", "5", "7")
const EXCLUDED_DIRECTORY_NAMES = Set(["notes", "_notes", "und"])
const ROOT_RESPONSE_ROLE = "ROOT_DIRECTORY_CATALOG"
const ID_RESPONSE_ROLE = "PATH_TO_DIRECTORY_ID"
const REVERSE_RESPONSE_ROLE = "DIRECTORY_ID_TO_PATH"
const FILES_RESPONSE_ROLE = "RELEASE_FILE_CATALOG"
const RESPONSE_ROLES = (
    ROOT_RESPONSE_ROLE,
    ID_RESPONSE_ROLE,
    REVERSE_RESPONSE_ROLE,
    FILES_RESPONSE_ROLE,
)
const NOT_APPLICABLE = "NOT_APPLICABLE"
const GENESIS = "GENESIS"
const RESPONSE_ENVELOPE_KEYS = [
    "body",
    "body_sha256",
    "directory_id",
    "final_effective_uri",
    "prior_response_body_sha256",
    "requested_uri",
    "response_role",
    "selected_release_internal_path",
    "sequence_index",
]

const PROHIBITED_ACTIONS = [
    "ACCESS_SOURCE_ARTIFACT_BYTES",
    "ADMIT_ORIGIN",
    "APPEND_FORECAST",
    "APPEND_SCORE",
    "APPEND_TRUTH",
    "AUTHENTICATE_PUBLISHER_FROM_LOCAL_HASHES",
    "CAPTURE_SOURCE",
    "DOWNLOAD_SOURCE",
    "EXECUTE_MODEL",
    "LOAD_TRUTH",
    "MAKE_HTTP_REQUEST",
    "MUTATE_SOURCE_INVENTORY",
    "PROMOTE_MODEL",
    "WRITE_DATA",
    "WRITE_RECEIPT",
]

const GATE_KEYS = [
    "accuracy_claim_allowed",
    "capture_allowed",
    "forecast_execution_allowed",
    "model_input_allowed",
    "origin_admission_allowed",
    "production_allowed",
    "promotion_allowed",
    "qualified_leaf_allowed",
    "scoring_allowed",
    "source_byte_access_allowed",
    "truth_access_allowed",
]

const UNRESOLVED_KEYS = [
    "approvals_complete",
    "capture_complete",
    "custody_complete",
    "future_2026_release_directory_resolved",
    "future_member_case_resolved",
    "official_intraday_availability_resolved",
    "publisher_trust_authenticated",
    "qualified_leaf_present",
    "raw_artifact_hashes_resolved",
    "source_artifact_bytes_verified",
    "transport_trust_authenticated",
    "workbook_contents_verified",
]

const ESI_LINES =
    "1,3,4,6,7,8,9,13,16,17,18,19,20,21,22,23,24,25,26,30,33,34,35,36,37,38,39,40,43,49,50,51,52,53,54,55,56,58,59,60,61,63,64,68,69,72,74,75,77,78,79,80,82,83,84,86,87,88,89,91,92,94,95,96"

const EXPECTED_PROFILES = [
    (
        profile_id = "faat301esi_net_stock",
        table_name = "FAAt301ESI",
        section_id = "3",
        candidate_sheet_name = "FAAt301ESI-A",
        line_numbers = ESI_LINES,
        selector =
            "BEA:FixedAssets:TableName=FAAt301ESI:Frequency=A:Year=2024:LineNumber=" *
            ESI_LINES,
    ),
    (
        profile_id = "faat304esi_depreciation",
        table_name = "FAAt304ESI",
        section_id = "3",
        candidate_sheet_name = "FAAt304ESI-A",
        line_numbers = ESI_LINES,
        selector =
            "BEA:FixedAssets:TableName=FAAt304ESI:Frequency=A:Year=2024:LineNumber=" *
            ESI_LINES,
    ),
    (
        profile_id = "faat307esi_investment",
        table_name = "FAAt307ESI",
        section_id = "3",
        candidate_sheet_name = "FAAt307ESI-A",
        line_numbers = ESI_LINES,
        selector =
            "BEA:FixedAssets:TableName=FAAt307ESI:Frequency=A:Year=2024:LineNumber=" *
            ESI_LINES,
    ),
    (
        profile_id = "faat501_residential_net_stock",
        table_name = "FAAt501",
        section_id = "5",
        candidate_sheet_name = "FAAt501-A",
        line_numbers = "11,12",
        selector =
            "BEA:FixedAssets:TableName=FAAt501:Frequency=A:Year=2024:LineNumber=11,12",
    ),
    (
        profile_id = "faat504_residential_depreciation",
        table_name = "FAAt504",
        section_id = "5",
        candidate_sheet_name = "FAAt504-A",
        line_numbers = "11,12",
        selector =
            "BEA:FixedAssets:TableName=FAAt504:Frequency=A:Year=2024:LineNumber=11,12",
    ),
    (
        profile_id = "faat507_residential_investment",
        table_name = "FAAt507",
        section_id = "5",
        candidate_sheet_name = "FAAt507-A",
        line_numbers = "11,12",
        selector =
            "BEA:FixedAssets:TableName=FAAt507:Frequency=A:Year=2024:LineNumber=11,12",
    ),
    (
        profile_id = "faat701_government_net_stock",
        table_name = "FAAt701",
        section_id = "7",
        candidate_sheet_name = "FAAt701-A",
        line_numbers = "1,21,22,55,79",
        selector =
            "BEA:FixedAssets:TableName=FAAt701:Frequency=A:Year=2024:LineNumber=1,21,22,55,79",
    ),
    (
        profile_id = "faat703_government_depreciation",
        table_name = "FAAt703",
        section_id = "7",
        candidate_sheet_name = "FAAt703-A",
        line_numbers = "1,21,22,55,79",
        selector =
            "BEA:FixedAssets:TableName=FAAt703:Frequency=A:Year=2024:LineNumber=1,21,22,55,79",
    ),
]

const EXPECTED_SOURCE_BINDINGS = [
    (
        binding_id = "legacy_v2_module",
        path =
            "scripts/us/forecasting/vintages/prospective/USProspectiveAcquisitionContractV2.jl",
        physical_sha256 =
            "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379",
        semantic_sha256 = "NOT_APPLICABLE",
        semantic_canonicalization = "NOT_APPLICABLE",
        role = "authoritative_legacy_contract_validator",
    ),
    (
        binding_id = "legacy_v2_contract",
        path =
            "scripts/us/forecasting/vintages/prospective/prospective_2026q3_contract_v2.toml",
        physical_sha256 =
            "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f",
        semantic_sha256 =
            "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a",
        semantic_canonicalization = "legacy_v2",
        role = "authoritative_eight_profile_selector_contract",
    ),
    (
        binding_id = "common_origin_v3_module",
        path =
            "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/USCommonOriginAcquisitionV3.jl",
        physical_sha256 =
            "9654eb61b92b2655391b00952ed4cbee0e9fa58224339f1fb0440c51570e719e",
        semantic_sha256 = "NOT_APPLICABLE",
        semantic_canonicalization = "NOT_APPLICABLE",
        role = "common_origin_composition_validator",
    ),
    (
        binding_id = "common_origin_v3_policy",
        path =
            "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/common_origin_acquisition_v3_policy.toml",
        physical_sha256 =
            "0deff5e3e6c950b5682bba96fcefa1fa2304bbbadae6227a940376dc7699bd3e",
        semantic_sha256 =
            "a69392029c2221ab5f490311c02d09a667e71982c486a1612100c1d6dcd96d13",
        semantic_canonicalization = "common_origin_v3",
        role = "permanent_cannot_run_parent_policy",
    ),
    (
        binding_id = "common_origin_parent_v3_schema",
        path =
            "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/common_origin_parent_v3.schema.toml",
        physical_sha256 =
            "cf4060554a6c53de079d728c2a2ac179309e9a7b888edc3bfa0a931ced5442a2",
        semantic_sha256 =
            "a140f2c730102ab882f606c2780d1214f0db691f4f921b5e9c1a140cfaf520ce",
        semantic_canonicalization = "common_origin_v3",
        role = "common_origin_parent_schema",
    ),
    (
        binding_id = "common_origin_leaf_v1_schema",
        path =
            "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/prospective_profile_verification_receipt_v1.schema.toml",
        physical_sha256 =
            "6bcd6f26efba67bb92053dabdc20c08f6b36d9c3569a92a5e980c5117265a4cd",
        semantic_sha256 =
            "702ffcf060fd9bfb3530e3f9dee5936304351ab58ee386b53455662c3f069fe8",
        semantic_canonicalization = "common_origin_v3",
        role = "currently_unqualified_leaf_receipt_schema",
    ),
    (
        binding_id = "common_origin_retention_v2_schema",
        path =
            "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/retention_custody_v2.schema.toml",
        physical_sha256 =
            "94eb2a1bdbd1346b4918d63bdf1befcf506a8b6d39c6eeaa1b50e87eb2c79598",
        semantic_sha256 =
            "2c6d6840a3396d5ced8e4e20b3bf0c5cc1fce68fdb927b796258fbf7a72382c3",
        semantic_canonicalization = "common_origin_v3",
        role = "common_origin_retention_schema",
    ),
    (
        binding_id = "current_inventory",
        path = "scripts/us/forecasting/vintages/current_inventory.toml",
        physical_sha256 =
            "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae",
        semantic_sha256 =
            "6b1fc42b1d645d43f9be6e215d42ab662924d6bb51249760aa2992d143031d74",
        semantic_canonicalization = "legacy_v2",
        role = "current_empty_fail_closed_release_inventory",
    ),
    (
        binding_id = "scripts_us_project",
        path = "scripts/us/Project.toml",
        physical_sha256 =
            "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c",
        semantic_sha256 = "NOT_APPLICABLE",
        semantic_canonicalization = "NOT_APPLICABLE",
        role = "offline_runtime_dependency_identity",
    ),
    (
        binding_id = "scripts_us_manifest",
        path = "scripts/us/Manifest.toml",
        physical_sha256 =
            "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263",
        semantic_sha256 = "NOT_APPLICABLE",
        semantic_canonicalization = "NOT_APPLICABLE",
        role = "offline_runtime_lock_identity",
    ),
    (
        binding_id = "hmi7_discovery_precedent",
        path =
            "scripts/us/forecasting/vintages/bea_nipa/BEANIPADiscovery.jl",
        physical_sha256 =
            "6f7497ae91f0cd40de6ffa110dd45f81c72adc0c0634f99d80fe652fb3f9437f",
        semantic_sha256 = "NOT_APPLICABLE",
        semantic_canonicalization = "NOT_APPLICABLE",
        role = "local_mechanics_precedent_not_hmi11_authority",
    ),
    (
        binding_id = "hmi7_discovery_documentation_precedent",
        path = "scripts/us/forecasting/vintages/bea_nipa/README.md",
        physical_sha256 =
            "639d79ebc1f944259e636e74c8bb68065d120d158ec6b850d253e3fbb23aeeb5",
        semantic_sha256 = "NOT_APPLICABLE",
        semantic_canonicalization = "NOT_APPLICABLE",
        role = "local_documentation_precedent_not_hmi11_authority",
    ),
]

struct DiscoveryError <: Exception
    code::Symbol
    location::String
    message::String
end

Base.showerror(io::IO, error::DiscoveryError) = print(
    io,
    "BEA Fixed Assets HMI11 discovery v1 ",
    error.code,
    " at ",
    error.location,
    ": ",
    error.message,
)

fail(code::Symbol, location, message) =
    throw(DiscoveryError(code, String(location), String(message)))

struct ExactJSONNumber
    lexeme::String
end

struct _ConstructionToken end
const _CONSTRUCTION_TOKEN = _ConstructionToken()

struct ReleaseDirectory
    internal_path::String
    data_year::Int
    archive_label::String
    archive_label_date_text::String
    archive_label_date::Date

    function ReleaseDirectory(
            ::_ConstructionToken,
            internal_path::String,
            data_year::Int,
            archive_label::String,
            archive_label_date_text::String,
            archive_label_date::Date,
        )
        return new(
            internal_path,
            data_year,
            archive_label,
            archive_label_date_text,
            archive_label_date,
        )
    end
end

struct ReleaseWorkbook
    section_id::String
    filename::String
    internal_path::String
    official_locator::String
    case_preserved::Bool
    source_bytes_accessed::Bool
    source_bytes_verified::Bool

    function ReleaseWorkbook(
            ::_ConstructionToken,
            section_id::String,
            filename::String,
            internal_path::String,
            official_locator::String,
            case_preserved::Bool,
            source_bytes_accessed::Bool,
            source_bytes_verified::Bool,
        )
        return new(
            section_id,
            filename,
            internal_path,
            official_locator,
            case_preserved,
            source_bytes_accessed,
            source_bytes_verified,
        )
    end
end

struct ProfileMapping
    profile_id::String
    table_name::String
    section_id::String
    candidate_sheet_name::String
    selector::String
    line_numbers::String
    workbook_filename::String
    workbook_locator::String
    sheet_verified::Bool
    contents_verified::Bool
    units_verified::Bool
    bytes_verified::Bool

    function ProfileMapping(
            ::_ConstructionToken,
            profile_id::String,
            table_name::String,
            section_id::String,
            candidate_sheet_name::String,
            selector::String,
            line_numbers::String,
            workbook_filename::String,
            workbook_locator::String,
            sheet_verified::Bool,
            contents_verified::Bool,
            units_verified::Bool,
            bytes_verified::Bool,
        )
        return new(
            profile_id,
            table_name,
            section_id,
            candidate_sheet_name,
            selector,
            line_numbers,
            workbook_filename,
            workbook_locator,
            sheet_verified,
            contents_verified,
            units_verified,
            bytes_verified,
        )
    end
end

struct MetadataResponseBinding
    sequence_index::Int
    response_role::String
    requested_uri::String
    final_effective_uri::String
    response_body_sha256::String
    prior_response_body_sha256::String
    selected_release_internal_path::String
    directory_id::String

    function MetadataResponseBinding(
            ::_ConstructionToken,
            sequence_index::Int,
            response_role::String,
            requested_uri::String,
            final_effective_uri::String,
            response_body_sha256::String,
            prior_response_body_sha256::String,
            selected_release_internal_path::String,
            directory_id::String,
        )
        return new(
            sequence_index,
            response_role,
            requested_uri,
            final_effective_uri,
            response_body_sha256,
            prior_response_body_sha256,
            selected_release_internal_path,
            directory_id,
        )
    end
end

struct DiscoveryPlan
    status::String
    role::String
    capture_cutoff::Date
    release::ReleaseDirectory
    directory_id::String
    metadata_response_lineage_replayed::Bool
    response_bindings::Vector{MetadataResponseBinding}
    workbooks::Vector{ReleaseWorkbook}
    profiles::Vector{ProfileMapping}
    gates::Dict{String, Bool}
    origin_admissible::Bool
    ready::Bool

    function DiscoveryPlan(
            ::_ConstructionToken,
            status::String,
            role::String,
            capture_cutoff::Date,
            release::ReleaseDirectory,
            directory_id::String,
            metadata_response_lineage_replayed::Bool,
            response_bindings::Vector{MetadataResponseBinding},
            workbooks::Vector{ReleaseWorkbook},
            profiles::Vector{ProfileMapping},
            gates::Dict{String, Bool},
            origin_admissible::Bool,
            ready::Bool,
        )
        return new(
            status,
            role,
            capture_cutoff,
            release,
            directory_id,
            metadata_response_lineage_replayed,
            response_bindings,
            workbooks,
            profiles,
            gates,
            origin_admissible,
            ready,
        )
    end
end

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(SHA.sha256(bytes))
sha256_hex(text::AbstractString) =
    sha256_hex(Vector{UInt8}(codeunits(String(text))))

mutable struct JSONCursor
    bytes::Vector{UInt8}
    index::Int
end

_json_eof(cursor::JSONCursor) = cursor.index > length(cursor.bytes)
_json_whitespace(byte::UInt8) =
    byte in (UInt8(' '), UInt8('\t'), UInt8('\n'), UInt8('\r'))

function _skip_json_whitespace!(cursor::JSONCursor)
    while !_json_eof(cursor) && _json_whitespace(cursor.bytes[cursor.index])
        cursor.index += 1
    end
    return nothing
end

function _hex_value(byte::UInt8, location)
    if UInt8('0') <= byte <= UInt8('9')
        return Int(byte - UInt8('0'))
    elseif UInt8('a') <= byte <= UInt8('f')
        return Int(byte - UInt8('a')) + 10
    elseif UInt8('A') <= byte <= UInt8('F')
        return Int(byte - UInt8('A')) + 10
    end
    return fail(:INVALID_JSON_UNICODE_ESCAPE, location, "requires four hexadecimal digits")
end

function _unicode_escape!(cursor::JSONCursor, location)
    cursor.index + 3 <= length(cursor.bytes) ||
        fail(:INVALID_JSON_UNICODE_ESCAPE, location, "is truncated")
    value = 0
    for _ in 1:4
        value = 16 * value + _hex_value(cursor.bytes[cursor.index], location)
        cursor.index += 1
    end
    return value
end

function _json_string!(cursor::JSONCursor, location)
    !_json_eof(cursor) && cursor.bytes[cursor.index] == UInt8('"') ||
        fail(:INVALID_JSON, location, "expected a string")
    cursor.index += 1
    output = IOBuffer()
    while !_json_eof(cursor)
        byte = cursor.bytes[cursor.index]
        cursor.index += 1
        if byte == UInt8('"')
            decoded = String(take!(output))
            isvalid(decoded) ||
                fail(:INVALID_JSON_UTF8, location, "decoded string is not valid UTF-8")
            ncodeunits(decoded) <= MAX_JSON_STRING_BYTES ||
                fail(:JSON_STRING_LIMIT_EXCEEDED, location, "decoded string is too large")
            return decoded
        elseif byte == UInt8('\\')
            _json_eof(cursor) &&
                fail(:INVALID_JSON, location, "unterminated escape")
            escape = cursor.bytes[cursor.index]
            cursor.index += 1
            if escape == UInt8('"')
                write(output, UInt8('"'))
            elseif escape == UInt8('\\')
                write(output, UInt8('\\'))
            elseif escape == UInt8('/')
                write(output, UInt8('/'))
            elseif escape == UInt8('b')
                write(output, UInt8(0x08))
            elseif escape == UInt8('f')
                write(output, UInt8(0x0c))
            elseif escape == UInt8('n')
                write(output, UInt8('\n'))
            elseif escape == UInt8('r')
                write(output, UInt8('\r'))
            elseif escape == UInt8('t')
                write(output, UInt8('\t'))
            elseif escape == UInt8('u')
                first_code = _unicode_escape!(cursor, location)
                if 0xd800 <= first_code <= 0xdbff
                    cursor.index + 1 <= length(cursor.bytes) &&
                        cursor.bytes[cursor.index] == UInt8('\\') &&
                        cursor.bytes[cursor.index + 1] == UInt8('u') ||
                        fail(
                        :INVALID_JSON_UNICODE,
                        location,
                        "high surrogate is not followed by a low surrogate",
                    )
                    cursor.index += 2
                    second_code = _unicode_escape!(cursor, location)
                    0xdc00 <= second_code <= 0xdfff ||
                        fail(
                        :INVALID_JSON_UNICODE,
                        location,
                        "high surrogate is not followed by a low surrogate",
                    )
                    codepoint =
                        0x00010000 +
                        ((first_code - 0xd800) << 10) +
                        (second_code - 0xdc00)
                    print(output, Char(codepoint))
                elseif 0xdc00 <= first_code <= 0xdfff
                    fail(
                        :INVALID_JSON_UNICODE,
                        location,
                        "unpaired low surrogate",
                    )
                else
                    print(output, Char(first_code))
                end
            else
                fail(:INVALID_JSON_ESCAPE, location, "unsupported escape")
            end
        elseif byte < 0x20
            fail(:INVALID_JSON_CONTROL, location, "contains an unescaped control byte")
        else
            write(output, byte)
        end
    end
    return fail(:INVALID_JSON, location, "unterminated string")
end

function _json_primitive!(cursor::JSONCursor, location)
    first_index = cursor.index
    while !_json_eof(cursor)
        byte = cursor.bytes[cursor.index]
        if _json_whitespace(byte) || byte in UInt8.([',', '}', ']'])
            break
        end
        cursor.index += 1
    end
    cursor.index > first_index ||
        fail(:INVALID_JSON, location, "missing primitive")
    lexeme = String(copy(cursor.bytes[first_index:(cursor.index - 1)]))
    if lexeme == "true"
        return true
    elseif lexeme == "false"
        return false
    elseif lexeme == "null"
        return nothing
    end
    ncodeunits(lexeme) <= MAX_JSON_NUMBER_BYTES ||
        fail(:JSON_NUMBER_LIMIT_EXCEEDED, location, "numeric token is too large")
    occursin(JSON_NUMBER_PATTERN, lexeme) ||
        fail(:INVALID_JSON_NUMBER, location, "outside the RFC 8259 number grammar")
    return ExactJSONNumber(lexeme)
end

function _json_value!(cursor::JSONCursor, location, depth)
    depth <= MAX_JSON_NESTING_DEPTH ||
        fail(:JSON_DEPTH_LIMIT_EXCEEDED, location, "nesting is too deep")
    _skip_json_whitespace!(cursor)
    _json_eof(cursor) && fail(:INVALID_JSON, location, "missing value")
    byte = cursor.bytes[cursor.index]
    if byte == UInt8('{')
        cursor.index += 1
        _skip_json_whitespace!(cursor)
        result = Dict{String, Any}()
        if !_json_eof(cursor) && cursor.bytes[cursor.index] == UInt8('}')
            cursor.index += 1
            return result
        end
        while true
            key = _json_string!(cursor, location)
            haskey(result, key) &&
                fail(
                :DUPLICATE_JSON_MEMBER,
                location,
                "duplicate member after escape decoding: $(repr(key))",
            )
            length(result) < MAX_JSON_OBJECT_MEMBERS ||
                fail(:JSON_OBJECT_LIMIT_EXCEEDED, location, "too many members")
            _skip_json_whitespace!(cursor)
            !_json_eof(cursor) && cursor.bytes[cursor.index] == UInt8(':') ||
                fail(:INVALID_JSON, location, "missing object member separator")
            cursor.index += 1
            result[key] = _json_value!(cursor, "$location.$key", depth + 1)
            _skip_json_whitespace!(cursor)
            _json_eof(cursor) &&
                fail(:INVALID_JSON, location, "unterminated object")
            if cursor.bytes[cursor.index] == UInt8('}')
                cursor.index += 1
                return result
            end
            cursor.bytes[cursor.index] == UInt8(',') ||
                fail(:INVALID_JSON, location, "invalid object separator")
            cursor.index += 1
            _skip_json_whitespace!(cursor)
        end
    elseif byte == UInt8('[')
        cursor.index += 1
        _skip_json_whitespace!(cursor)
        result = Any[]
        if !_json_eof(cursor) && cursor.bytes[cursor.index] == UInt8(']')
            cursor.index += 1
            return result
        end
        while true
            length(result) < MAX_JSON_ARRAY_ITEMS ||
                fail(:JSON_ARRAY_LIMIT_EXCEEDED, location, "too many items")
            push!(
                result,
                _json_value!(
                    cursor,
                    "$location[$(length(result) + 1)]",
                    depth + 1,
                ),
            )
            _skip_json_whitespace!(cursor)
            _json_eof(cursor) &&
                fail(:INVALID_JSON, location, "unterminated array")
            if cursor.bytes[cursor.index] == UInt8(']')
                cursor.index += 1
                return result
            end
            cursor.bytes[cursor.index] == UInt8(',') ||
                fail(:INVALID_JSON, location, "invalid array separator")
            cursor.index += 1
            _skip_json_whitespace!(cursor)
        end
    elseif byte == UInt8('"')
        return _json_string!(cursor, location)
    end
    return _json_primitive!(cursor, location)
end

function parse_exact_json(body, location::AbstractString = "JSON response")
    bytes = if body isa AbstractString
        Vector{UInt8}(codeunits(String(body)))
    elseif body isa AbstractVector{UInt8}
        Vector{UInt8}(body)
    else
        fail(:JSON_BODY_TYPE_MISMATCH, location, "must be UTF-8 text or bytes")
    end
    length(bytes) <= MAX_JSON_BODY_BYTES ||
        fail(:JSON_BODY_LIMIT_EXCEEDED, location, "body is too large")
    isvalid(String(copy(bytes))) ||
        fail(:INVALID_JSON_UTF8, location, "body is not valid UTF-8")
    cursor = JSONCursor(bytes, 1)
    value = _json_value!(cursor, String(location), 0)
    _skip_json_whitespace!(cursor)
    _json_eof(cursor) ||
        fail(:INVALID_JSON, location, "trailing bytes after the JSON value")
    return value
end

function _expect_table(value, location)
    value isa AbstractDict ||
        fail(:TYPE_MISMATCH, location, "must be an object/table")
    return value
end

function _expect_array(value, location)
    value isa AbstractVector ||
        fail(:TYPE_MISMATCH, location, "must be an array")
    return value
end

function _expect_string(value, location; allow_empty = false)
    value isa AbstractString ||
        fail(:TYPE_MISMATCH, location, "must be a string")
    text = String(value)
    !allow_empty && isempty(text) &&
        fail(:EMPTY_STRING, location, "must not be empty")
    return text
end

function _expect_bool(value, location)
    value isa Bool || fail(:TYPE_MISMATCH, location, "must be a Boolean")
    return value
end

function _expect_int(value, location; minimum = typemin(Int))
    value isa Int && !(value isa Bool) ||
        fail(:TYPE_MISMATCH, location, "must be a TOML integer")
    value >= minimum || fail(:VALUE_OUT_OF_RANGE, location, "is below minimum")
    return value
end

function _expect_exact_keys(table, expected, location)
    actual = Set(String.(collect(keys(_expect_table(table, location)))))
    required = Set(String.(collect(expected)))
    actual == required ||
        fail(
        :UNKNOWN_OR_MISSING_FIELDS,
        location,
        "expected $(sort!(collect(required))), found $(sort!(collect(actual)))",
    )
    return table
end

function _expect_exact(value, expected, location; code = :CONTRACT_DRIFT)
    value == expected ||
        fail(code, location, "expected $(repr(expected)), found $(repr(value))")
    return value
end

function _validate_path_text(path, location)
    path == strip(path) ||
        fail(:INVALID_INTERNAL_PATH, location, "has surrounding whitespace")
    any(character -> iscntrl(character), path) &&
        fail(:INVALID_INTERNAL_PATH, location, "contains a control character")
    startswith(path, INTERNAL_RELEASE_ROOT) ||
        fail(:INVALID_INTERNAL_PATH, location, "is outside the HMI11 release root")
    if path == INTERNAL_RELEASE_ROOT
        return String[]
    end
    prefix = INTERNAL_RELEASE_ROOT * "\\"
    startswith(path, prefix) ||
        fail(:INVALID_INTERNAL_PATH, location, "does not use the canonical separator")
    relative = path[(ncodeunits(prefix) + 1):end]
    occursin('/', relative) &&
        fail(:INVALID_INTERNAL_PATH, location, "contains a noncanonical separator")
    segments = String.(split(relative, '\\'; keepempty = true))
    any(isempty, segments) &&
        fail(:INVALID_INTERNAL_PATH, location, "contains an empty segment")
    any(segment -> segment in (".", ".."), segments) &&
        fail(:PATH_TRAVERSAL, location, "contains a dot segment")
    any(segment -> any(iscntrl, segment), segments) &&
        fail(:INVALID_INTERNAL_PATH, location, "contains a control character")
    return segments
end

function _excluded_directory(segments)
    return any(segment -> lowercase(segment) in EXCLUDED_DIRECTORY_NAMES, segments) ||
        any(segment -> endswith(lowercase(segment), "_notes"), segments)
end

function _release_directory(path::String, location)
    segments = _validate_path_text(path, location)
    _excluded_directory(segments) && return nothing
    length(segments) == 2 || return nothing
    data_year_text, archive_label = segments
    occursin(r"^[0-9]{4}$", data_year_text) || return nothing
    matched = match(RELEASE_LABEL_PATTERN, archive_label)
    matched === nothing && return nothing
    month_text, day_text, year_text = matched.captures
    date_text = "$month_text-$day_text-$year_text"
    release_date = tryparse(Date, date_text, RELEASE_DATE_FORMAT)
    release_date === nothing &&
        fail(:INVALID_RELEASE_DATE, location, "contains an invalid calendar date")
    Dates.format(release_date, RELEASE_DATE_FORMAT) == date_text ||
        fail(:NONCANONICAL_RELEASE_DATE, location, "release date is not canonical")
    return ReleaseDirectory(
        _CONSTRUCTION_TOKEN,
        path,
        parse(Int, data_year_text),
        archive_label,
        date_text,
        release_date,
    )
end

function _replay_release(release, location)
    release isa ReleaseDirectory ||
        fail(:TYPE_MISMATCH, location, "must be a ReleaseDirectory")
    replayed = _release_directory(release.internal_path, "$location.internal_path")
    replayed === nothing &&
        fail(
        :FORGED_RELEASE_DIRECTORY,
        location,
        "internal path is not a canonical HMI11 annual-update release",
    )
    fields = (
        :internal_path,
        :data_year,
        :archive_label,
        :archive_label_date_text,
        :archive_label_date,
    )
    for field in fields
        observed = getproperty(release, field)
        expected = getproperty(replayed, field)
        observed == expected ||
            fail(
            :FORGED_RELEASE_DIRECTORY,
            "$location.$field",
            "expected $(repr(expected)), found $(repr(observed))",
        )
    end
    return replayed
end

function parse_release_directories(body)
    document = _expect_exact_keys(
        parse_exact_json(body, "root discovery response"),
        ["FileArray", "FolderPattern", "MainName"],
        "root discovery response",
    )
    _expect_exact(
        _expect_string(document["MainName"], "root.MainName"),
        MAIN_NAME,
        "root.MainName",
        code = :HMI_IDENTITY_MISMATCH,
    )
    _expect_exact(
        _expect_string(document["FolderPattern"], "root.FolderPattern"),
        FOLDER_PATTERN,
        "root.FolderPattern",
        code = :HMI_IDENTITY_MISMATCH,
    )
    paths = _expect_array(document["FileArray"], "root.FileArray")
    isempty(paths) &&
        fail(:EMPTY_DIRECTORY_CATALOG, "root.FileArray", "must not be empty")
    releases = ReleaseDirectory[]
    seen_paths = Set{String}()
    seen_casefold_paths = Dict{String, String}()
    for (index, value) in enumerate(paths)
        location = "root.FileArray[$index]"
        path = _expect_string(value, location)
        path in seen_paths &&
            fail(:DUPLICATE_RELEASE_PATH, location, "duplicates an earlier path")
        push!(seen_paths, path)
        casefold = lowercase(path)
        if haskey(seen_casefold_paths, casefold)
            fail(
                :CASEFOLD_PATH_AMBIGUITY,
                location,
                "casefold-collides with $(repr(seen_casefold_paths[casefold]))",
            )
        end
        seen_casefold_paths[casefold] = path
        release = _release_directory(path, location)
        release === nothing || push!(releases, release)
    end
    isempty(releases) &&
        fail(:NO_CANONICAL_RELEASES, "root.FileArray", "contains no annual updates")
    sort!(releases; by = release -> (release.archive_label_date, release.internal_path))
    return releases
end

function select_latest_release(releases, capture_cutoff::Date)
    releases isa AbstractVector ||
        fail(:TYPE_MISMATCH, "releases", "must be an array")
    isempty(releases) && fail(:NO_CANONICAL_RELEASES, "releases", "is empty")
    all(release -> release isa ReleaseDirectory, releases) ||
        fail(:TYPE_MISMATCH, "releases", "must contain ReleaseDirectory values")
    validated = [
        _replay_release(release, "releases[$index]") for
            (index, release) in enumerate(releases)
    ]
    eligible = filter(
        release -> release.archive_label_date <= capture_cutoff,
        validated,
    )
    isempty(eligible) &&
        fail(
        :FUTURE_ONLY_RELEASE_CATALOG,
        "capture_cutoff",
        "no canonical release is no later than $capture_cutoff",
    )
    latest_date = maximum(release.archive_label_date for release in eligible)
    latest = filter(release -> release.archive_label_date == latest_date, eligible)
    length(latest) == 1 ||
        fail(
        :LATEST_RELEASE_TIE,
        "releases",
        "$(length(latest)) releases share latest eligible date $latest_date",
    )
    return only(latest)
end

function _one_hmi_record(body, location)
    document = _expect_array(parse_exact_json(body, location), location)
    length(document) == 1 ||
        fail(:RESPONSE_CARDINALITY_MISMATCH, location, "must contain exactly one record")
    return _expect_exact_keys(
        only(document),
        ["DescriptionLong", "Notes", "Theid", "Thepath"],
        "$location[1]",
    )
end

function _expect_nothing(value, location)
    value === nothing || fail(:TYPE_MISMATCH, location, "must be JSON null")
    return nothing
end

function parse_directory_id(body)
    record = _one_hmi_record(body, "path-to-ID response")
    _expect_nothing(record["Notes"], "path-to-ID response[1].Notes")
    _expect_nothing(record["Thepath"], "path-to-ID response[1].Thepath")
    _expect_nothing(
        record["DescriptionLong"],
        "path-to-ID response[1].DescriptionLong",
    )
    directory_id =
        _expect_string(record["Theid"], "path-to-ID response[1].Theid")
    occursin(DECIMAL_ID_PATTERN, directory_id) ||
        fail(
        :NONCANONICAL_DIRECTORY_ID,
        "path-to-ID response[1].Theid",
        "must be positive decimal digits without leading zeros",
    )
    return directory_id
end

function parse_resolved_path(body, expected_id::AbstractString, expected_path::AbstractString)
    directory_id = _expect_string(expected_id, "expected_id")
    occursin(DECIMAL_ID_PATTERN, directory_id) ||
        fail(:NONCANONICAL_DIRECTORY_ID, "expected_id", "must be canonical decimal digits")
    path = _expect_string(expected_path, "expected_path")
    _release_directory(path, "expected_path") === nothing &&
        fail(:INVALID_RELEASE_PATH, "expected_path", "is not a canonical annual update")
    record = _one_hmi_record(body, "ID-to-path response")
    _expect_nothing(record["Notes"], "ID-to-path response[1].Notes")
    _expect_nothing(record["Theid"], "ID-to-path response[1].Theid")
    _expect_nothing(
        record["DescriptionLong"],
        "ID-to-path response[1].DescriptionLong",
    )
    resolved =
        _expect_string(record["Thepath"], "ID-to-path response[1].Thepath")
    resolved == path ||
        fail(
        :DIRECTORY_REVERSE_MISMATCH,
        "ID-to-path response[1].Thepath",
        "does not equal the requested path bound to ID $directory_id",
    )
    return resolved
end

function _percent_encode(text::AbstractString)
    io = IOBuffer()
    for byte in codeunits(String(text))
        unreserved =
            UInt8('A') <= byte <= UInt8('Z') ||
            UInt8('a') <= byte <= UInt8('z') ||
            UInt8('0') <= byte <= UInt8('9') ||
            byte in UInt8.(['-', '.', '_', '~'])
        if unreserved
            write(io, byte)
        else
            print(io, '%', uppercase(string(byte; base = 16, pad = 2)))
        end
    end
    return String(take!(io))
end

function _directory_id_url(release::ReleaseDirectory)
    replayed = _replay_release(release, "directory_id_url.release")
    return DIRECTORY_ID_ENDPOINT *
        "?UrlPath=" *
        _percent_encode(replayed.internal_path)
end

function _resolved_path_url(directory_id::AbstractString)
    text = String(directory_id)
    occursin(DECIMAL_ID_PATTERN, text) ||
        fail(:NONCANONICAL_DIRECTORY_ID, "directory_id", "must be canonical decimal digits")
    return RESOLVED_PATH_ENDPOINT * text
end

function _release_files_url(release::ReleaseDirectory)
    replayed = _replay_release(release, "release_files_url.release")
    return RELEASE_FILES_ENDPOINT *
        "?HistMainId=11&thePath=" *
        _percent_encode(replayed.internal_path) *
        "&getFiles=true&getDirs=false"
end

function _exact_release_child(release::ReleaseDirectory, internal_path, location)
    replayed = _replay_release(release, "$location.release")
    path = _expect_string(internal_path, "$location.internal_path")
    child_segments = _validate_path_text(path, "$location.internal_path")
    release_segments = _validate_path_text(
        replayed.internal_path,
        "$location.release.internal_path",
    )
    length(child_segments) == length(release_segments) + 1 ||
        fail(
        :NONEXACT_RELEASE_CHILD,
        "$location.internal_path",
        "must be exactly one path component below the selected release",
    )
    child_segments[1:length(release_segments)] == release_segments ||
        fail(
        :NOT_SELECTED_RELEASE_CHILD,
        "$location.internal_path",
        "is not beneath the selected release",
    )
    startswith(path, replayed.internal_path * "\\") ||
        fail(
        :NOT_SELECTED_RELEASE_CHILD,
        "$location.internal_path",
        "does not replay the selected release prefix exactly",
    )
    return (replayed, path, last(child_segments))
end

function _official_file_url(release::ReleaseDirectory, internal_path::AbstractString)
    _, path, _ = _exact_release_child(
        release,
        internal_path,
        "official_file_url",
    )
    relative = path[(ncodeunits(INTERNAL_HISTDATA_ROOT) + 1):end]
    canonical = replace(relative, '\\' => '/')
    segments = String.(split(canonical, '/'; keepempty = true))
    any(isempty, segments) &&
        fail(:INVALID_INTERNAL_PATH, "internal_path", "contains an empty segment")
    any(segment -> segment in (".", ".."), segments) &&
        fail(:PATH_TRAVERSAL, "internal_path", "contains a dot segment")
    any(segment -> any(iscntrl, segment), segments) &&
        fail(:INVALID_INTERNAL_PATH, "internal_path", "contains a control character")
    return OFFICIAL_HISTDATA_ROOT * join(_percent_encode.(segments), "/")
end

function parse_release_workbooks(body, selected_release::ReleaseDirectory)
    selected_release = _replay_release(
        selected_release,
        "parse_release_workbooks.selected_release",
    )
    document = _expect_exact_keys(
        parse_exact_json(body, "release-file response"),
        ["Filearray3", "MainName"],
        "release-file response",
    )
    _expect_exact(
        _expect_string(document["MainName"], "release-files.MainName"),
        MAIN_NAME,
        "release-files.MainName",
        code = :HMI_IDENTITY_MISMATCH,
    )
    paths = _expect_array(document["Filearray3"], "release-files.Filearray3")
    isempty(paths) &&
        fail(:EMPTY_FILE_CATALOG, "release-files.Filearray3", "must not be empty")
    prefix = selected_release.internal_path * "\\"
    selected_segments = _validate_path_text(
        selected_release.internal_path,
        "selected_release.internal_path",
    )
    seen_casefold = Dict{String, String}()
    workbooks = Dict{String, ReleaseWorkbook}()
    for (index, value) in enumerate(paths)
        location = "release-files.Filearray3[$index]"
        path = _expect_string(value, location)
        segments = _validate_path_text(path, location)
        length(segments) > length(selected_segments) &&
            segments[1:length(selected_segments)] == selected_segments ||
            fail(:NOT_SELECTED_RELEASE_CHILD, location, "is not beneath the selected release")
        startswith(path, prefix) ||
            fail(:NOT_SELECTED_RELEASE_CHILD, location, "does not use the exact selected path prefix")
        relative_segments = segments[(length(selected_segments) + 1):end]
        if length(relative_segments) > 1
            lowercase(first(relative_segments)) in EXCLUDED_DIRECTORY_NAMES &&
                continue
            fail(:NONEXACT_RELEASE_CHILD, location, "is nested below an unrecognized directory")
        end
        filename = only(relative_segments)
        casefold = lowercase(filename)
        if haskey(seen_casefold, casefold)
            fail(
                :CASEFOLD_FILENAME_AMBIGUITY,
                location,
                "casefold-collides with $(repr(seen_casefold[casefold]))",
            )
        end
        seen_casefold[casefold] = filename
        matched = match(SECTION_WORKBOOK_PATTERN, casefold)
        matched === nothing && continue
        section_id = String(matched.captures[1])
        extension = String(matched.captures[2])
        extension == "xlsx" ||
            fail(:UNSUPPORTED_WORKBOOK_FORMAT, location, "main section workbook must be XLSX")
        section_id in REQUIRED_SECTIONS ||
            fail(:EXTRA_MAIN_SECTION, location, "unexpected main section $section_id")
        haskey(workbooks, section_id) &&
            fail(:DUPLICATE_MAIN_SECTION, location, "duplicates main section $section_id")
        workbooks[section_id] = ReleaseWorkbook(
            _CONSTRUCTION_TOKEN,
            section_id,
            filename,
            path,
            _official_file_url(selected_release, path),
            true,
            false,
            false,
        )
    end
    observed = Set(keys(workbooks))
    required = Set(REQUIRED_SECTIONS)
    observed == required ||
        fail(
        :MISSING_MAIN_SECTION,
        "release-files.Filearray3",
        "required sections $(collect(REQUIRED_SECTIONS)); found $(sort!(collect(observed)))",
    )
    return [workbooks[section] for section in REQUIRED_SECTIONS]
end

function _emit_length(io::IO, count::Integer)
    count >= 0 || fail(:CANONICALIZATION_ERROR, "canonical", "negative length")
    write(io, string(count), ':')
    return nothing
end

function _emit_canonical(io::IO, value, depth = 0)
    depth <= MAX_CANONICAL_DEPTH ||
        fail(:CANONICALIZATION_LIMIT, "canonical", "nesting is too deep")
    if value === nothing
        write(io, "N;")
    elseif value isa Bool
        write(io, value ? "B1;" : "B0;")
    elseif value isa Integer
        encoded = codeunits(string(value))
        write(io, 'I')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractFloat
        isfinite(value) ||
            fail(:CANONICALIZATION_ERROR, "canonical", "nonfinite float")
        encoded = codeunits(bitstring(Float64(value)))
        write(io, 'F')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractString
        ncodeunits(value) <= MAX_CANONICAL_STRING_BYTES ||
            fail(:CANONICALIZATION_LIMIT, "canonical", "string is too large")
        encoded = codeunits(String(value))
        write(io, 'S')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractVector
        length(value) <= MAX_CANONICAL_ITEMS ||
            fail(:CANONICALIZATION_LIMIT, "canonical", "array is too large")
        write(io, 'A')
        _emit_length(io, length(value))
        for item in value
            _emit_canonical(io, item, depth + 1)
        end
        write(io, ';')
    elseif value isa AbstractDict
        length(value) <= MAX_CANONICAL_ITEMS ||
            fail(:CANONICALIZATION_LIMIT, "canonical", "table is too large")
        all(key -> key isa AbstractString, keys(value)) ||
            fail(:CANONICALIZATION_ERROR, "canonical", "keys must be strings")
        ordered = sort!(String.(collect(keys(value))))
        all(key -> ncodeunits(key) <= MAX_CANONICAL_KEY_BYTES, ordered) ||
            fail(:CANONICALIZATION_LIMIT, "canonical", "key is too large")
        write(io, 'D')
        _emit_length(io, length(ordered))
        for key in ordered
            _emit_canonical(io, key, depth + 1)
            _emit_canonical(io, value[key], depth + 1)
        end
        write(io, ';')
    else
        fail(
            :CANONICALIZATION_ERROR,
            "canonical",
            "unsupported value type $(typeof(value))",
        )
    end
    return nothing
end

function _canonical_sha256(value)
    io = IOBuffer()
    _emit_canonical(io, value)
    return sha256_hex(take!(io))
end

function _emit_legacy_v2(io::IO, value)
    if value isa AbstractDict
        entries = sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            _emit_legacy_v2(io, String(key))
            _emit_legacy_v2(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector || value isa Tuple
        print(io, "A", length(value), "[")
        for entry in value
            _emit_legacy_v2(io, entry)
        end
        print(io, "]")
    elseif value isa AbstractString
        text = String(value)
        print(io, "S", ncodeunits(text), ":", text)
    elseif value isa Bool
        print(io, value ? "B1" : "B0")
    elseif value isa Integer
        print(io, "I", value, ";")
    else
        fail(
            :CANONICALIZATION_ERROR,
            "legacy_v2",
            "unsupported value type $(typeof(value))",
        )
    end
    return nothing
end

function _legacy_v2_sha256(value)
    io = IOBuffer()
    _emit_legacy_v2(io, value)
    return sha256_hex(take!(io))
end

function _without_content_hash(document)
    copy = deepcopy(_expect_table(document, "profile"))
    artifact = _expect_table(get(copy, "artifact", nothing), "profile.artifact")
    pop!(artifact, "content_sha256", nothing)
    return copy
end

profile_content_sha256(document) = _canonical_sha256(_without_content_hash(document))

function stamp_profile_content_sha256!(document)
    artifact = _expect_table(
        _expect_table(document, "profile")["artifact"],
        "profile.artifact",
    )
    artifact["content_sha256"] = profile_content_sha256(document)
    return document
end

function _validate_hash(value, location)
    text = _expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(:INVALID_SHA256, location, "must be a lowercase SHA-256")
    return text
end

function _validate_profile_source_binding_declarations(bindings)
    values = _expect_array(bindings, "profile.source_bindings")
    length(values) == length(EXPECTED_SOURCE_BINDINGS) ||
        fail(:SOURCE_BINDING_DRIFT, "profile.source_bindings", "wrong binding count")
    for (index, expected) in enumerate(EXPECTED_SOURCE_BINDINGS)
        location = "profile.source_bindings[$index]"
        binding = _expect_exact_keys(
            values[index],
            [
                "binding_id",
                "path",
                "physical_sha256",
                "role",
                "semantic_canonicalization",
                "semantic_sha256",
            ],
            location,
        )
        for key in keys(expected)
            _expect_exact(
                binding[String(key)],
                getproperty(expected, key),
                "$location.$key",
                code = :SOURCE_BINDING_DRIFT,
            )
        end
        expected.physical_sha256 == "NOT_APPLICABLE" ||
            _validate_hash(binding["physical_sha256"], "$location.physical_sha256")
        if expected.semantic_sha256 != "NOT_APPLICABLE"
            _validate_hash(binding["semantic_sha256"], "$location.semantic_sha256")
        end
    end
    return nothing
end

function _verify_profile_source_bindings(bindings)
    _validate_profile_source_binding_declarations(bindings)
    probe = _SOURCE_VERIFICATION_TEST_PROBE[]
    probe === nothing || probe()
    for (index, expected) in enumerate(EXPECTED_SOURCE_BINDINGS)
        location = "profile.source_bindings[$index]"
        source_path = normpath(joinpath(REPOSITORY_ROOT, expected.path))
        startswith(
            source_path,
            string(REPOSITORY_ROOT, Base.Filesystem.path_separator),
        ) ||
            fail(:SOURCE_PATH_ESCAPE, "$location.path", "escapes repository root")
        isfile(source_path) ||
            fail(:SOURCE_BINDING_MISSING, "$location.path", "file does not exist")
        bytes = read(source_path)
        actual_physical = sha256_hex(bytes)
        actual_physical == expected.physical_sha256 ||
            fail(
            :SOURCE_PHYSICAL_IDENTITY_MISMATCH,
            "$location.physical_sha256",
            "expected $(expected.physical_sha256), found $actual_physical",
        )
        expected.semantic_sha256 == "NOT_APPLICABLE" && continue
        document = try
            TOML.parse(String(bytes))
        catch error
            fail(
                :SOURCE_SEMANTIC_PARSE_FAILURE,
                location,
                sprint(showerror, error),
            )
        end
        semantic_copy = _without_content_hash(document)
        actual_semantic = if expected.semantic_canonicalization == "legacy_v2"
            _legacy_v2_sha256(semantic_copy)
        elseif expected.semantic_canonicalization == "common_origin_v3"
            _canonical_sha256(semantic_copy)
        else
            fail(
                :SOURCE_BINDING_DRIFT,
                "$location.semantic_canonicalization",
                "unsupported canonicalization",
            )
        end
        actual_semantic == expected.semantic_sha256 ||
            fail(
            :SOURCE_SEMANTIC_IDENTITY_MISMATCH,
            "$location.semantic_sha256",
            "expected $(expected.semantic_sha256), found $actual_semantic",
        )
    end
    return nothing
end

function _validate_profiles(profiles)
    values = _expect_array(profiles, "profile.profiles")
    length(values) == length(EXPECTED_PROFILES) ||
        fail(:PROFILE_MAPPING_DRIFT, "profile.profiles", "must contain exactly eight mappings")
    result = ProfileMapping[]
    for (index, expected) in enumerate(EXPECTED_PROFILES)
        location = "profile.profiles[$index]"
        profile = _expect_exact_keys(
            values[index],
            [
                "bytes_verified",
                "candidate_sheet_name",
                "contents_verified",
                "frequency",
                "line_numbers",
                "profile_id",
                "raw_sha256",
                "section_id",
                "selector",
                "selector_sha256",
                "sheet_verified",
                "table_name",
                "units_verified",
                "year",
            ],
            location,
        )
        for key in (
                :profile_id,
                :table_name,
                :section_id,
                :candidate_sheet_name,
                :line_numbers,
                :selector,
            )
            _expect_exact(
                profile[String(key)],
                getproperty(expected, key),
                "$location.$key",
                code = :PROFILE_MAPPING_DRIFT,
            )
        end
        _expect_exact(profile["frequency"], "A", "$location.frequency")
        _expect_exact(profile["year"], "2024", "$location.year")
        _expect_exact(
            profile["selector_sha256"],
            sha256_hex(expected.selector),
            "$location.selector_sha256",
        )
        _expect_exact(profile["raw_sha256"], "UNRESOLVED", "$location.raw_sha256")
        for key in (
                "bytes_verified",
                "contents_verified",
                "sheet_verified",
                "units_verified",
            )
            _expect_exact(
                _expect_bool(profile[key], "$location.$key"),
                false,
                "$location.$key",
                code = :GATE_ELEVATION,
            )
        end
        push!(
            result,
            ProfileMapping(
                _CONSTRUCTION_TOKEN,
                expected.profile_id,
                expected.table_name,
                expected.section_id,
                expected.candidate_sheet_name,
                expected.selector,
                expected.line_numbers,
                "UNRESOLVED",
                "UNRESOLVED",
                false,
                false,
                false,
                false,
            ),
        )
    end
    counts = Dict(
        section => count(profile -> profile.section_id == section, result) for
            section in REQUIRED_SECTIONS
    )
    counts == Dict("3" => 3, "5" => 3, "7" => 2) ||
        fail(:PROFILE_SECTION_CARDINALITY_DRIFT, "profile.profiles", "must remain 3/3/2")
    return result
end

function validate_profile_document(document)
    profile = _expect_exact_keys(
        document,
        [
            "artifact",
            "citations",
            "contract",
            "gates",
            "hmi11",
            "page_visible_observation",
            "parser",
            "profiles",
            "prohibited_actions",
            "response_envelope",
            "selection",
            "source_bindings",
            "unresolved",
        ],
        "profile",
    )
    artifact = _expect_exact_keys(
        profile["artifact"],
        [
            "canonicalization",
            "content_sha256",
            "role",
            "schema_version",
            "status",
        ],
        "profile.artifact",
    )
    _expect_exact(artifact["schema_version"], SCHEMA_VERSION, "profile.artifact.schema_version")
    _expect_exact(artifact["status"], STATUS, "profile.artifact.status", code = :GATE_ELEVATION)
    _expect_exact(artifact["role"], ROLE, "profile.artifact.role")
    _expect_exact(
        artifact["canonicalization"],
        CANONICALIZATION,
        "profile.artifact.canonicalization",
    )
    stored_content = _validate_hash(artifact["content_sha256"], "profile.artifact.content_sha256")
    computed_content = profile_content_sha256(profile)
    stored_content == computed_content ||
        fail(:PROFILE_SELF_HASH_MISMATCH, "profile.artifact.content_sha256", "does not match content")
    computed_content == PROFILE_CONTENT_SHA256 ||
        fail(:PROFILE_IDENTITY_CHANGED, "profile.artifact.content_sha256", "is not the compiled profile")

    contract = _expect_exact_keys(
        profile["contract"],
        [
            "capture_forbidden",
            "discovery_mechanics_only",
            "evidence_date",
            "filesystem_write_forbidden",
            "maximum_status",
            "network_access_forbidden",
            "permanent_nonadmitting",
            "source_binding_bypass_keyword_forbidden",
            "source_binding_verification_mandatory_for_operational_build_and_replay",
            "source_artifact_byte_access_forbidden",
            "standard_library_only",
            "successor_required_for_any_higher_status",
            "synthetic_fixtures_only",
        ],
        "profile.contract",
    )
    _expect_exact(contract["evidence_date"], "2026-08-08", "profile.contract.evidence_date")
    _expect_exact(
        contract["maximum_status"],
        STATUS,
        "profile.contract.maximum_status",
        code = :GATE_ELEVATION,
    )
    for key in (
            "capture_forbidden",
            "discovery_mechanics_only",
            "filesystem_write_forbidden",
            "network_access_forbidden",
            "permanent_nonadmitting",
            "source_binding_bypass_keyword_forbidden",
            "source_binding_verification_mandatory_for_operational_build_and_replay",
            "source_artifact_byte_access_forbidden",
            "standard_library_only",
            "successor_required_for_any_higher_status",
            "synthetic_fixtures_only",
        )
        value = _expect_bool(contract[key], "profile.contract.$key")
        _expect_exact(value, true, "profile.contract.$key", code = :CONTRACT_DRIFT)
    end

    hmi = _expect_exact_keys(
        profile["hmi11"],
        [
            "directory_id_endpoint",
            "folder_pattern",
            "history_main_id",
            "internal_histdata_root",
            "internal_release_root",
            "main_name",
            "official_histdata_root",
            "release_files_endpoint",
            "resolved_path_endpoint",
            "root_discovery_url",
        ],
        "profile.hmi11",
    )
    expected_hmi = Dict(
        "directory_id_endpoint" => DIRECTORY_ID_ENDPOINT,
        "folder_pattern" => FOLDER_PATTERN,
        "history_main_id" => HMI_ID,
        "internal_histdata_root" => INTERNAL_HISTDATA_ROOT,
        "internal_release_root" => INTERNAL_RELEASE_ROOT,
        "main_name" => MAIN_NAME,
        "official_histdata_root" => OFFICIAL_HISTDATA_ROOT,
        "release_files_endpoint" => RELEASE_FILES_ENDPOINT,
        "resolved_path_endpoint" => RESOLVED_PATH_ENDPOINT,
        "root_discovery_url" => ROOT_DISCOVERY_URL,
    )
    for key in keys(expected_hmi)
        if key == "history_main_id"
            _expect_int(hmi[key], "profile.hmi11.$key", minimum = 1)
        end
        _expect_exact(hmi[key], expected_hmi[key], "profile.hmi11.$key")
    end

    parser = _expect_exact_keys(
        profile["parser"],
        [
            "duplicate_members_after_escape_decode_rejected",
            "max_array_items",
            "max_body_bytes",
            "max_nesting_depth",
            "max_number_bytes",
            "max_object_members",
            "max_string_bytes",
            "unknown_response_fields_rejected",
        ],
        "profile.parser",
    )
    parser_expected = Dict(
        "duplicate_members_after_escape_decode_rejected" => true,
        "max_array_items" => MAX_JSON_ARRAY_ITEMS,
        "max_body_bytes" => MAX_JSON_BODY_BYTES,
        "max_nesting_depth" => MAX_JSON_NESTING_DEPTH,
        "max_number_bytes" => MAX_JSON_NUMBER_BYTES,
        "max_object_members" => MAX_JSON_OBJECT_MEMBERS,
        "max_string_bytes" => MAX_JSON_STRING_BYTES,
        "unknown_response_fields_rejected" => true,
    )
    for key in keys(parser_expected)
        value = parser[key]
        if parser_expected[key] isa Bool
            _expect_bool(value, "profile.parser.$key")
        else
            _expect_int(value, "profile.parser.$key", minimum = 1)
        end
        _expect_exact(value, parser_expected[key], "profile.parser.$key")
    end

    selection = _expect_exact_keys(
        profile["selection"],
        [
            "canonical_separator",
            "capture_cutoff_required",
            "data_year_pattern",
            "eligible_release_rule",
            "future_only_rejected",
            "latest_date_ties_rejected",
            "release_label_pattern",
            "release_path_dynamic_component_count",
            "required_sections",
        ],
        "profile.selection",
    )
    _expect_exact(selection["capture_cutoff_required"], true, "profile.selection.capture_cutoff_required")
    _expect_exact(selection["canonical_separator"], "\\", "profile.selection.canonical_separator")
    _expect_exact(selection["data_year_pattern"], "^[0-9]{4}\$", "profile.selection.data_year_pattern")
    _expect_exact(
        _expect_int(
            selection["release_path_dynamic_component_count"],
            "profile.selection.release_path_dynamic_component_count";
            minimum = 1,
        ),
        2,
        "profile.selection.release_path_dynamic_component_count",
    )
    _expect_exact(
        selection["eligible_release_rule"],
        "unique_latest_canonical_annual_update_date_no_later_than_explicit_capture_cutoff",
        "profile.selection.eligible_release_rule",
    )
    _expect_exact(selection["future_only_rejected"], true, "profile.selection.future_only_rejected")
    _expect_exact(selection["latest_date_ties_rejected"], true, "profile.selection.latest_date_ties_rejected")
    _expect_exact(
        selection["release_label_pattern"],
        "AnnualUpdate_Month-D-YYYY",
        "profile.selection.release_label_pattern",
    )
    _expect_exact(selection["required_sections"], collect(REQUIRED_SECTIONS), "profile.selection.required_sections")

    response_envelope = _expect_exact_keys(
        profile["response_envelope"],
        [
            "body_hash_reuse_forbidden",
            "body_path_equality_alone_insufficient",
            "body_requires_exact_byte_vector",
            "body_sha256_required",
            "directory_id_lineage_required",
            "final_effective_uri_must_equal_requested",
            "metadata_lineage_replay_required",
            "prior_body_hash_chain_required",
            "requested_uri_derived_from_prior_state",
            "required_count",
            "required_roles",
            "selected_path_lineage_required",
        ],
        "profile.response_envelope",
    )
    _expect_exact(
        _expect_int(
            response_envelope["required_count"],
            "profile.response_envelope.required_count";
            minimum = 1,
        ),
        4,
        "profile.response_envelope.required_count",
    )
    _expect_exact(
        response_envelope["required_roles"],
        collect(RESPONSE_ROLES),
        "profile.response_envelope.required_roles",
    )
    for key in (
            "body_hash_reuse_forbidden",
            "body_path_equality_alone_insufficient",
            "body_requires_exact_byte_vector",
            "body_sha256_required",
            "directory_id_lineage_required",
            "final_effective_uri_must_equal_requested",
            "metadata_lineage_replay_required",
            "prior_body_hash_chain_required",
            "requested_uri_derived_from_prior_state",
            "selected_path_lineage_required",
        )
        _expect_exact(
            _expect_bool(
                response_envelope[key],
                "profile.response_envelope.$key",
            ),
            true,
            "profile.response_envelope.$key",
        )
    end

    prohibited = _expect_array(profile["prohibited_actions"], "profile.prohibited_actions")
    _expect_exact(prohibited, PROHIBITED_ACTIONS, "profile.prohibited_actions", code = :CONTRACT_DRIFT)

    gates = _expect_exact_keys(profile["gates"], GATE_KEYS, "profile.gates")
    for key in GATE_KEYS
        _expect_exact(
            _expect_bool(gates[key], "profile.gates.$key"),
            false,
            "profile.gates.$key",
            code = :GATE_ELEVATION,
        )
    end

    unresolved = _expect_exact_keys(
        profile["unresolved"],
        UNRESOLVED_KEYS,
        "profile.unresolved",
    )
    for key in UNRESOLVED_KEYS
        _expect_bool(unresolved[key], "profile.unresolved.$key") &&
            fail(:CLAIM_ELEVATION, "profile.unresolved.$key", "must remain false")
    end

    page = _expect_exact_keys(
        profile["page_visible_observation"],
        [
            "artifact_bytes_preserved",
            "historical_member_names_resolved",
            "observation_status",
            "page_url",
            "release_date_label",
            "release_directory_id_label",
            "source_response_bytes_preserved",
        ],
        "profile.page_visible_observation",
    )
    _expect_exact(
        page["observation_status"],
        "PAGE_VISIBLE_UNPRESERVED_NOT_SOURCE_EVIDENCE",
        "profile.page_visible_observation.observation_status",
    )
    _expect_exact(page["release_date_label"], "September-26-2025", "profile.page_visible_observation.release_date_label")
    _expect_exact(page["release_directory_id_label"], "14195", "profile.page_visible_observation.release_directory_id_label")
    _expect_exact(
        page["page_url"],
        "https://apps.bea.gov/histdata/fileStructDisplay.html?theID=14195&HMI=11&oldDiv=National%20Accounts&year=2024&quarter=&ReleaseDate=September-26-2025&Vintage=AnnualUpdate",
        "profile.page_visible_observation.page_url",
    )
    for key in (
            "artifact_bytes_preserved",
            "historical_member_names_resolved",
            "source_response_bytes_preserved",
        )
        _expect_bool(page[key], "profile.page_visible_observation.$key") &&
            fail(:CLAIM_ELEVATION, "profile.page_visible_observation.$key", "must remain false")
    end

    citations = _expect_array(profile["citations"], "profile.citations")
    expected_citations = [
        (
            id = "bea_fixed_assets_landing",
            url = "https://www.bea.gov/itable/fixed-assets",
            status = "OFFICIAL_PAGE_ROUTE_PAGE_VISIBLE_UNPRESERVED",
        ),
        (
            id = "bea_fixed_assets_download_catalog",
            url = "https://apps.bea.gov/iTable/?categories=flatfiles&isuri=1&nipa_table_list=1&reqid=10&step=4",
            status = "OFFICIAL_PAGE_ROUTE_PAGE_VISIBLE_UNPRESERVED",
        ),
        (
            id = "bea_historical_data_archive",
            url = "https://apps.bea.gov/histdata/",
            status = "OFFICIAL_PAGE_ROUTE_PAGE_VISIBLE_UNPRESERVED",
        ),
    ]
    length(citations) == length(expected_citations) ||
        fail(:CITATION_DRIFT, "profile.citations", "wrong citation count")
    for (index, expected) in enumerate(expected_citations)
        citation = _expect_exact_keys(
            citations[index],
            ["id", "local_bytes_sha256", "status", "url"],
            "profile.citations[$index]",
        )
        _expect_exact(citation["id"], expected.id, "profile.citations[$index].id")
        _expect_exact(citation["url"], expected.url, "profile.citations[$index].url")
        _expect_exact(citation["status"], expected.status, "profile.citations[$index].status")
        _expect_exact(
            citation["local_bytes_sha256"],
            "NOT_PRESERVED",
            "profile.citations[$index].local_bytes_sha256",
        )
    end

    mappings = _validate_profiles(profile["profiles"])
    _verify_profile_source_bindings(profile["source_bindings"])
    return mappings
end

function load_profile(path::AbstractString = PROFILE_PATH)
    profile_path = abspath(String(path))
    isfile(profile_path) ||
        fail(:PROFILE_MISSING, "profile_path", "file does not exist")
    bytes = read(profile_path)
    length(bytes) <= MAX_PROFILE_BYTES ||
        fail(:PROFILE_SIZE_LIMIT_EXCEEDED, "profile_path", "file is too large")
    if profile_path == abspath(PROFILE_PATH)
        physical = sha256_hex(bytes)
        physical == PROFILE_PHYSICAL_SHA256 ||
            fail(
            :PROFILE_PHYSICAL_IDENTITY_MISMATCH,
            "profile_path",
            "expected $PROFILE_PHYSICAL_SHA256, found $physical",
        )
    end
    document = try
        TOML.parse(String(bytes))
    catch error
        fail(:INVALID_PROFILE_TOML, "profile_path", sprint(showerror, error))
    end
    validate_profile_document(document)
    return document
end

function _response_body(value, location)
    value isa AbstractVector{UInt8} ||
        fail(:TYPE_MISMATCH, location, "must be an exact byte vector")
    bytes = Vector{UInt8}(value)
    length(bytes) <= MAX_JSON_BODY_BYTES ||
        fail(:JSON_BODY_LIMIT_EXCEEDED, location, "body is too large")
    return bytes
end

function _response_envelope(
        value,
        expected_index,
        expected_role,
        expected_requested_uri,
        expected_prior_sha256,
        expected_selected_path,
        expected_directory_id,
    )
    location = "response_envelopes[$expected_index]"
    envelope = _expect_exact_keys(value, RESPONSE_ENVELOPE_KEYS, location)
    sequence_index = _expect_int(
        envelope["sequence_index"],
        "$location.sequence_index";
        minimum = 1,
    )
    _expect_exact(
        sequence_index,
        expected_index,
        "$location.sequence_index",
        code = :RESPONSE_ORDER_MISMATCH,
    )
    response_role =
        _expect_string(envelope["response_role"], "$location.response_role")
    _expect_exact(
        response_role,
        expected_role,
        "$location.response_role",
        code = :RESPONSE_ROLE_MISMATCH,
    )
    requested_uri =
        _expect_string(envelope["requested_uri"], "$location.requested_uri")
    _expect_exact(
        requested_uri,
        expected_requested_uri,
        "$location.requested_uri",
        code = :REQUEST_URI_LINEAGE_MISMATCH,
    )
    final_effective_uri = _expect_string(
        envelope["final_effective_uri"],
        "$location.final_effective_uri",
    )
    _expect_exact(
        final_effective_uri,
        expected_requested_uri,
        "$location.final_effective_uri",
        code = :FINAL_URI_LINEAGE_MISMATCH,
    )
    body = _response_body(envelope["body"], "$location.body")
    body_sha256 =
        _validate_hash(envelope["body_sha256"], "$location.body_sha256")
    actual_body_sha256 = sha256_hex(body)
    body_sha256 == actual_body_sha256 ||
        fail(
        :RESPONSE_BODY_HASH_MISMATCH,
        "$location.body_sha256",
        "expected $body_sha256, reconstructed $actual_body_sha256",
    )
    prior_sha256 = _expect_string(
        envelope["prior_response_body_sha256"],
        "$location.prior_response_body_sha256",
    )
    _expect_exact(
        prior_sha256,
        expected_prior_sha256,
        "$location.prior_response_body_sha256",
        code = :RESPONSE_CHAIN_MISMATCH,
    )
    selected_path = _expect_string(
        envelope["selected_release_internal_path"],
        "$location.selected_release_internal_path",
    )
    _expect_exact(
        selected_path,
        expected_selected_path,
        "$location.selected_release_internal_path",
        code = :SELECTED_PATH_LINEAGE_MISMATCH,
    )
    directory_id =
        _expect_string(envelope["directory_id"], "$location.directory_id")
    _expect_exact(
        directory_id,
        expected_directory_id,
        "$location.directory_id",
        code = :DIRECTORY_ID_LINEAGE_MISMATCH,
    )
    binding = MetadataResponseBinding(
        _CONSTRUCTION_TOKEN,
        sequence_index,
        response_role,
        requested_uri,
        final_effective_uri,
        body_sha256,
        prior_sha256,
        selected_path,
        directory_id,
    )
    return (binding, body)
end

function _build_discovery_plan(
        response_envelopes,
        capture_cutoff::Date;
        profile_path::AbstractString,
    )
    profile = load_profile(profile_path)
    envelopes = _expect_array(response_envelopes, "response_envelopes")
    length(envelopes) == length(RESPONSE_ROLES) ||
        fail(
        :RESPONSE_ENVELOPE_CARDINALITY_MISMATCH,
        "response_envelopes",
        "must contain exactly four role-ordered responses",
    )

    root_binding, root_body = _response_envelope(
        envelopes[1],
        1,
        ROOT_RESPONSE_ROLE,
        ROOT_DISCOVERY_URL,
        GENESIS,
        NOT_APPLICABLE,
        NOT_APPLICABLE,
    )
    releases = parse_release_directories(root_body)
    release = select_latest_release(releases, capture_cutoff)
    release = _replay_release(release, "selected_release")

    id_binding, id_body = _response_envelope(
        envelopes[2],
        2,
        ID_RESPONSE_ROLE,
        _directory_id_url(release),
        root_binding.response_body_sha256,
        release.internal_path,
        NOT_APPLICABLE,
    )
    directory_id = parse_directory_id(id_body)

    reverse_binding, reverse_body = _response_envelope(
        envelopes[3],
        3,
        REVERSE_RESPONSE_ROLE,
        _resolved_path_url(directory_id),
        id_binding.response_body_sha256,
        release.internal_path,
        directory_id,
    )
    parse_resolved_path(reverse_body, directory_id, release.internal_path)

    files_binding, files_body = _response_envelope(
        envelopes[4],
        4,
        FILES_RESPONSE_ROLE,
        _release_files_url(release),
        reverse_binding.response_body_sha256,
        release.internal_path,
        directory_id,
    )
    response_bindings = [
        root_binding,
        id_binding,
        reverse_binding,
        files_binding,
    ]
    body_hashes = [binding.response_body_sha256 for binding in response_bindings]
    length(unique(body_hashes)) == length(body_hashes) ||
        fail(
        :RESPONSE_BODY_REPLAY,
        "response_envelopes",
        "a response body hash is reused across metadata roles",
    )

    workbooks = parse_release_workbooks(files_body, release)
    workbook_by_section = Dict(
        workbook.section_id => workbook for workbook in workbooks
    )
    profile_mappings = ProfileMapping[]
    for mapping in _validate_profiles(profile["profiles"])
        workbook = workbook_by_section[mapping.section_id]
        push!(
            profile_mappings,
            ProfileMapping(
                _CONSTRUCTION_TOKEN,
                mapping.profile_id,
                mapping.table_name,
                mapping.section_id,
                mapping.candidate_sheet_name,
                mapping.selector,
                mapping.line_numbers,
                workbook.filename,
                workbook.official_locator,
                false,
                false,
                false,
                false,
            ),
        )
    end
    gates = Dict{String, Bool}(
        key => _expect_bool(profile["gates"][key], "profile.gates.$key") for
            key in GATE_KEYS
    )
    all(value -> value === false, values(gates)) ||
        fail(:GATE_ELEVATION, "profile.gates", "all gates must remain false")
    return DiscoveryPlan(
        _CONSTRUCTION_TOKEN,
        STATUS,
        ROLE,
        capture_cutoff,
        release,
        directory_id,
        true,
        response_bindings,
        workbooks,
        profile_mappings,
        gates,
        false,
        false,
    )
end

function _compare_fields(observed, expected, fields, location)
    typeof(observed) == typeof(expected) ||
        fail(:PLAN_REPLAY_MISMATCH, location, "type differs from replay")
    for field in fields
        observed_value = getproperty(observed, field)
        expected_value = getproperty(expected, field)
        observed_value == expected_value ||
            fail(
            :PLAN_REPLAY_MISMATCH,
            "$location.$field",
            "expected $(repr(expected_value)), found $(repr(observed_value))",
        )
    end
    return nothing
end

function _strict_compare_plan(observed, expected)
    observed isa DiscoveryPlan ||
        fail(:TYPE_MISMATCH, "plan", "must be a DiscoveryPlan")
    _compare_fields(
        observed,
        expected,
        (
            :status,
            :role,
            :capture_cutoff,
            :directory_id,
            :metadata_response_lineage_replayed,
            :origin_admissible,
            :ready,
        ),
        "plan",
    )
    observed_release = _replay_release(observed.release, "plan.release")
    expected_release = _replay_release(expected.release, "replay.release")
    _compare_fields(
        observed_release,
        expected_release,
        (
            :internal_path,
            :data_year,
            :archive_label,
            :archive_label_date_text,
            :archive_label_date,
        ),
        "plan.release",
    )

    length(observed.response_bindings) == length(expected.response_bindings) ||
        fail(:PLAN_REPLAY_MISMATCH, "plan.response_bindings", "length differs")
    binding_fields = (
        :sequence_index,
        :response_role,
        :requested_uri,
        :final_effective_uri,
        :response_body_sha256,
        :prior_response_body_sha256,
        :selected_release_internal_path,
        :directory_id,
    )
    for index in eachindex(expected.response_bindings)
        _compare_fields(
            observed.response_bindings[index],
            expected.response_bindings[index],
            binding_fields,
            "plan.response_bindings[$index]",
        )
    end

    length(observed.workbooks) == length(expected.workbooks) ||
        fail(:PLAN_REPLAY_MISMATCH, "plan.workbooks", "length differs")
    workbook_fields = (
        :section_id,
        :filename,
        :internal_path,
        :official_locator,
        :case_preserved,
        :source_bytes_accessed,
        :source_bytes_verified,
    )
    for index in eachindex(expected.workbooks)
        _compare_fields(
            observed.workbooks[index],
            expected.workbooks[index],
            workbook_fields,
            "plan.workbooks[$index]",
        )
    end

    length(observed.profiles) == length(expected.profiles) ||
        fail(:PLAN_REPLAY_MISMATCH, "plan.profiles", "length differs")
    profile_fields = (
        :profile_id,
        :table_name,
        :section_id,
        :candidate_sheet_name,
        :selector,
        :line_numbers,
        :workbook_filename,
        :workbook_locator,
        :sheet_verified,
        :contents_verified,
        :units_verified,
        :bytes_verified,
    )
    for index in eachindex(expected.profiles)
        _compare_fields(
            observed.profiles[index],
            expected.profiles[index],
            profile_fields,
            "plan.profiles[$index]",
        )
    end

    Set(keys(observed.gates)) == Set(keys(expected.gates)) ||
        fail(:PLAN_REPLAY_MISMATCH, "plan.gates", "keys differ")
    for key in sort!(collect(keys(expected.gates)))
        observed.gates[key] == expected.gates[key] ||
            fail(
            :PLAN_REPLAY_MISMATCH,
            "plan.gates.$key",
            "value differs from replay",
        )
    end
    return nothing
end

function build_discovery_plan(
        response_envelopes,
        capture_cutoff::Date;
        profile_path::AbstractString = PROFILE_PATH,
    )
    return _build_discovery_plan(
        response_envelopes,
        capture_cutoff;
        profile_path,
    )
end

function validate_discovery_plan(
        plan,
        response_envelopes,
        capture_cutoff::Date;
        profile_path::AbstractString = PROFILE_PATH,
    )
    replayed = _build_discovery_plan(
        response_envelopes,
        capture_cutoff;
        profile_path,
    )
    _strict_compare_plan(plan, replayed)
    return replayed
end

end
