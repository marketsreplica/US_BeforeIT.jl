module USCensusStructuralProfileV1

using SHA
using TOML

export CensusProfileError,
    PROFILE_PATH,
    build_structural_result,
    load_profile,
    parse_logical_fixture,
    profile_content_sha256,
    sha256_hex,
    validate_profile_document,
    validate_structural_result

const PROFILE_PATH = joinpath(@__DIR__, "census_structural_profile_v1.toml")
const REPOSITORY_ROOT_WITH_SEPARATOR = normpath(
    dirname(
        joinpath(
            @__DIR__,
            "..",
            "..",
            "..",
            "..",
            "..",
            "..",
            ".repository-root-sentinel",
        ),
    ),
)
const REPOSITORY_ROOT = endswith(
        REPOSITORY_ROOT_WITH_SEPARATOR,
        Base.Filesystem.path_separator,
    ) ? chop(REPOSITORY_ROOT_WITH_SEPARATOR; tail = 1) : REPOSITORY_ROOT_WITH_SEPARATOR
const PROFILE_SCHEMA = "beforeit-us-census-structural-logical-profile.v1"
const PROFILE_STATUS = "CANNOT_RUN"
const PROFILE_ROLE = "LOGICAL_SCHEMA_MECHANICS_ONLY"
const FIXTURE_FORMAT = "BEFOREIT_SYNTHETIC_LOGICAL_TSV_V1_NOT_PROVIDER_BYTES"
const CANONICALIZATION =
    "sorted-typed-length-prefixed-v1-excluding-artifact-content-sha256"
const EXPECTED_PROFILE_PHYSICAL_SHA256 =
    "512b35c1d80c9d6c8b387cdd68affd4a1ae92b1dc040c04aacae8545b47ef157"
const EXPECTED_PROFILE_SEMANTIC_SHA256 =
    "c661bc84b0b9f9ee3c6ff28982721a9a9dacd14d6e73cc6859db54737429b491"
const MAX_FIXTURE_BYTES = 8_388_608
const MAX_FIXTURE_ROWS = 100_000
const MAX_FIELD_BYTES = 1_048_576
const MAX_NUMERIC_BYTES = 128

const PROHIBITED_ACTIONS = (
    "ACCESS_PROVIDER_BODY_BYTES",
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
    "PARSE_SYNTHETIC_FIXTURE_AS_PROVIDER_BYTES",
    "PROMOTE_MODEL",
    "WRITE_DATA",
    "WRITE_RECEIPT",
)

const AIES_COMMON_FIELDS = (
    "GEO_ID",
    "GEO_ID_F",
    "INDLEVEL",
    "NAICS",
    "NAICS_F",
    "NAICS_LABEL",
    "NAME",
    "SECTOR",
    "YEAR",
)
const AIES_VALUE_FLAGS = ("", "D", "N", "S", "Z")
const AIES_CV_FLAGS = ("", "v", "w")
const SUSB_FIELDS = (
    "STATE",
    "NAICS",
    "ENTRSIZE",
    "FIRM",
    "ESTB",
    "EMPL",
    "EMPLFL_R",
    "EMPLFL_N",
    "PAYR",
    "PAYRFL_N",
    "RCPT",
    "RCPTFL_N",
    "STATEDSCR",
    "NAICSDSCR",
    "ENTRSIZEDSCR",
)
const SUSB_SIZE_CODES = ("01", "02", "03", "04", "05", "06", "07", "08", "09")
const SUSB_FLAG_TOKENS = ("", "G", "H", "J", "S", "D")
const SUSB_METRICS = ("FIRM", "ESTB", "EMPL", "PAYR", "RCPT")
const SUSB_OVERLAP_EQUATIONS = (
    (target = "05", components = ("02", "03", "04")),
    (target = "08", components = ("05", "06", "07")),
    (target = "01", components = ("08", "09")),
)

const EXPECTED_PROFILE_SPECS = (
    (
        profile_id = "aies00inv_2023_economy_wide",
        requirement_id = "census_aies_inventory_allocation",
        product_code = "AIES00INV",
        archive_filename = "AIES00INV.zip",
        source_url =
            "https://www2.census.gov/programs-surveys/aies/data/2023/AIES00INV.zip",
        provider_member_name = "UNRESOLVED_NOT_CAPTURED",
        expected_field_count = 21,
        key_fields = ("GEO_ID", "YEAR", "NAICS", "TYPOP", "TAXSTAT"),
        dimension_fields =
            ("GEO_ID", "INDLEVEL", "NAICS", "SECTOR", "YEAR", "TAXSTAT", "TYPOP"),
        label_fields = ("NAICS_LABEL", "NAME", "TAXSTAT_LABEL", "TYPOP_LABEL"),
        structural_flag_fields = ("GEO_ID_F", "NAICS_F"),
        measure_value_fields = ("RCPT_TOT_VAL", "INV_E_TOT_DVAL"),
        measure_value_flag_fields = ("RCPT_TOT_VAL_F", "INV_E_TOT_DVAL_F"),
        measure_cv_fields = ("RCPT_TOT_CV", "INV_E_TOT_CV"),
        measure_cv_flag_fields = ("RCPT_TOT_CV_F", "INV_E_TOT_CV_F"),
        logical_fields = (
            AIES_COMMON_FIELDS...,
            "TAXSTAT",
            "TAXSTAT_LABEL",
            "TYPOP",
            "TYPOP_LABEL",
            "RCPT_TOT_VAL",
            "RCPT_TOT_VAL_F",
            "RCPT_TOT_CV",
            "RCPT_TOT_CV_F",
            "INV_E_TOT_DVAL",
            "INV_E_TOT_DVAL_F",
            "INV_E_TOT_CV",
            "INV_E_TOT_CV_F",
        ),
    ),
    (
        profile_id = "aies31inv_2023_manufacturing_valuation",
        requirement_id = "census_aies_inventory_allocation",
        product_code = "AIES31INV",
        archive_filename = "AIES31INV.zip",
        source_url =
            "https://www2.census.gov/programs-surveys/aies/data/2023/AIES31INV.zip",
        provider_member_name = "UNRESOLVED_NOT_CAPTURED",
        expected_field_count = 21,
        key_fields = ("GEO_ID", "YEAR", "NAICS"),
        dimension_fields = ("GEO_ID", "INDLEVEL", "NAICS", "SECTOR", "YEAR"),
        label_fields = ("NAICS_LABEL", "NAME"),
        structural_flag_fields = ("GEO_ID_F", "NAICS_F"),
        measure_value_fields =
            ("INV_E_TOT_DVAL", "INV_E_LIFO_VAL", "INV_E_LIFO_RSV_VAL"),
        measure_value_flag_fields =
            ("INV_E_TOT_DVAL_F", "INV_E_LIFO_VAL_F", "INV_E_LIFO_RSV_VAL_F"),
        measure_cv_fields =
            ("INV_E_TOT_CV", "INV_E_LIFO_CV", "INV_E_LIFO_RSV_CV"),
        measure_cv_flag_fields =
            ("INV_E_TOT_CV_F", "INV_E_LIFO_CV_F", "INV_E_LIFO_RSV_CV_F"),
        logical_fields = (
            AIES_COMMON_FIELDS...,
            "INV_E_TOT_DVAL",
            "INV_E_TOT_DVAL_F",
            "INV_E_TOT_CV",
            "INV_E_TOT_CV_F",
            "INV_E_LIFO_VAL",
            "INV_E_LIFO_VAL_F",
            "INV_E_LIFO_CV",
            "INV_E_LIFO_CV_F",
            "INV_E_LIFO_RSV_VAL",
            "INV_E_LIFO_RSV_VAL_F",
            "INV_E_LIFO_RSV_CV",
            "INV_E_LIFO_RSV_CV_F",
        ),
    ),
    (
        profile_id = "aies42inv_2023_wholesale_valuation",
        requirement_id = "census_aies_inventory_allocation",
        product_code = "AIES42INV",
        archive_filename = "AIES42INV.zip",
        source_url =
            "https://www2.census.gov/programs-surveys/aies/data/2023/AIES42INV.zip",
        provider_member_name = "UNRESOLVED_NOT_CAPTURED",
        expected_field_count = 23,
        key_fields = ("GEO_ID", "YEAR", "NAICS", "TYPOP"),
        dimension_fields = ("GEO_ID", "INDLEVEL", "NAICS", "SECTOR", "YEAR", "TYPOP"),
        label_fields = ("NAICS_LABEL", "NAME", "TYPOP_LABEL"),
        structural_flag_fields = ("GEO_ID_F", "NAICS_F"),
        measure_value_fields =
            ("INV_E_TOT_DVAL", "INV_E_LIFO_VAL", "INV_E_LIFO_RSV_VAL"),
        measure_value_flag_fields =
            ("INV_E_TOT_DVAL_F", "INV_E_LIFO_VAL_F", "INV_E_LIFO_RSV_VAL_F"),
        measure_cv_fields =
            ("INV_E_TOT_CV", "INV_E_LIFO_CV", "INV_E_LIFO_RSV_CV"),
        measure_cv_flag_fields =
            ("INV_E_TOT_CV_F", "INV_E_LIFO_CV_F", "INV_E_LIFO_RSV_CV_F"),
        logical_fields = (
            AIES_COMMON_FIELDS...,
            "TYPOP",
            "TYPOP_LABEL",
            "INV_E_TOT_DVAL",
            "INV_E_TOT_DVAL_F",
            "INV_E_TOT_CV",
            "INV_E_TOT_CV_F",
            "INV_E_LIFO_VAL",
            "INV_E_LIFO_VAL_F",
            "INV_E_LIFO_CV",
            "INV_E_LIFO_CV_F",
            "INV_E_LIFO_RSV_VAL",
            "INV_E_LIFO_RSV_VAL_F",
            "INV_E_LIFO_RSV_CV",
            "INV_E_LIFO_RSV_CV_F",
        ),
    ),
    (
        profile_id = "aies44inv_2023_retail_valuation",
        requirement_id = "census_aies_inventory_allocation",
        product_code = "AIES44INV",
        archive_filename = "AIES44INV.zip",
        source_url =
            "https://www2.census.gov/programs-surveys/aies/data/2023/AIES44INV.zip",
        provider_member_name = "UNRESOLVED_NOT_CAPTURED",
        expected_field_count = 23,
        key_fields = ("GEO_ID", "YEAR", "NAICS"),
        dimension_fields =
            ("GEO_ID", "INDLEVEL", "NAICS", "SECTOR", "YEAR", "INDGROUP", "SUBSECTOR"),
        label_fields = ("NAICS_LABEL", "NAME"),
        structural_flag_fields = ("GEO_ID_F", "NAICS_F"),
        measure_value_fields =
            ("INV_E_TOT_DVAL", "INV_E_LIFO_VAL", "INV_E_LIFO_RSV_VAL"),
        measure_value_flag_fields =
            ("INV_E_TOT_DVAL_F", "INV_E_LIFO_VAL_F", "INV_E_LIFO_RSV_VAL_F"),
        measure_cv_fields =
            ("INV_E_TOT_CV", "INV_E_LIFO_CV", "INV_E_LIFO_RSV_CV"),
        measure_cv_flag_fields =
            ("INV_E_TOT_CV_F", "INV_E_LIFO_CV_F", "INV_E_LIFO_RSV_CV_F"),
        logical_fields = (
            AIES_COMMON_FIELDS...,
            "INDGROUP",
            "SUBSECTOR",
            "INV_E_TOT_DVAL",
            "INV_E_TOT_DVAL_F",
            "INV_E_TOT_CV",
            "INV_E_TOT_CV_F",
            "INV_E_LIFO_VAL",
            "INV_E_LIFO_VAL_F",
            "INV_E_LIFO_CV",
            "INV_E_LIFO_CV_F",
            "INV_E_LIFO_RSV_VAL",
            "INV_E_LIFO_RSV_VAL_F",
            "INV_E_LIFO_RSV_CV",
            "INV_E_LIFO_RSV_CV_F",
        ),
    ),
    (
        profile_id = "aies51inv_2023_information_stages",
        requirement_id = "census_aies_inventory_allocation",
        product_code = "AIES51INV",
        archive_filename = "AIES51INV.zip",
        source_url =
            "https://www2.census.gov/programs-surveys/aies/data/2023/AIES51INV.zip",
        provider_member_name = "UNRESOLVED_NOT_CAPTURED",
        expected_field_count = 27,
        key_fields = ("GEO_ID", "YEAR", "NAICS", "TAXSTAT"),
        dimension_fields = ("GEO_ID", "INDLEVEL", "NAICS", "SECTOR", "YEAR", "TAXSTAT"),
        label_fields = ("NAICS_LABEL", "NAME", "TAXSTAT_LABEL"),
        structural_flag_fields = ("GEO_ID_F", "NAICS_F"),
        measure_value_fields =
            ("INV_E_TOT_DVAL", "INV_E_FIN_VAL", "INV_E_WIP_VAL", "INV_E_MAT_VAL"),
        measure_value_flag_fields = (
            "INV_E_TOT_DVAL_F",
            "INV_E_FIN_VAL_F",
            "INV_E_WIP_VAL_F",
            "INV_E_MAT_VAL_F",
        ),
        measure_cv_fields =
            ("INV_E_TOT_CV", "INV_E_FIN_CV", "INV_E_WIP_CV", "INV_E_MAT_CV"),
        measure_cv_flag_fields = (
            "INV_E_TOT_CV_F",
            "INV_E_FIN_CV_F",
            "INV_E_WIP_CV_F",
            "INV_E_MAT_CV_F",
        ),
        logical_fields = (
            AIES_COMMON_FIELDS...,
            "TAXSTAT",
            "TAXSTAT_LABEL",
            "INV_E_TOT_DVAL",
            "INV_E_TOT_DVAL_F",
            "INV_E_TOT_CV",
            "INV_E_TOT_CV_F",
            "INV_E_FIN_VAL",
            "INV_E_FIN_VAL_F",
            "INV_E_FIN_CV",
            "INV_E_FIN_CV_F",
            "INV_E_WIP_VAL",
            "INV_E_WIP_VAL_F",
            "INV_E_WIP_CV",
            "INV_E_WIP_CV_F",
            "INV_E_MAT_VAL",
            "INV_E_MAT_VAL_F",
            "INV_E_MAT_CV",
            "INV_E_MAT_CV_F",
        ),
    ),
    (
        profile_id = "susb_employer_enterprises",
        requirement_id = "census_susb_structural",
        product_code = "SUSB_2022_US_STATE_6DIGIT_NAICS",
        archive_filename = "us_state_6digitnaics_2022.txt",
        source_url =
            "https://www2.census.gov/programs-surveys/susb/tables/2022/us_state_6digitnaics_2022.txt",
        provider_member_name = "NOT_APPLICABLE_DIRECT_TEXT_OBJECT",
        expected_field_count = 15,
        key_fields = ("STATE", "NAICS", "ENTRSIZE"),
        dimension_fields = ("STATE", "NAICS", "ENTRSIZE"),
        label_fields = ("STATEDSCR", "NAICSDSCR", "ENTRSIZEDSCR"),
        structural_flag_fields = ("EMPLFL_R", "EMPLFL_N", "PAYRFL_N", "RCPTFL_N"),
        measure_value_fields = SUSB_METRICS,
        measure_value_flag_fields = (),
        measure_cv_fields = (),
        measure_cv_flag_fields = (),
        logical_fields = SUSB_FIELDS,
    ),
)

const EXPECTED_SOURCE_BINDINGS = (
    (
        binding_id = "prospective_v2_module",
        repository_relative_path =
            "scripts/us/forecasting/vintages/prospective/USProspectiveAcquisitionContractV2.jl",
        physical_sha256 =
            "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379",
    ),
    (
        binding_id = "prospective_v2_contract",
        repository_relative_path =
            "scripts/us/forecasting/vintages/prospective/prospective_2026q3_contract_v2.toml",
        physical_sha256 =
            "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f",
    ),
    (
        binding_id = "common_origin_v4_module",
        repository_relative_path =
            "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/USCommonOriginAcquisitionV4.jl",
        physical_sha256 =
            "0f4c248950ebee59d1e6b5882db6516cbb539f9e54c7dfbb6b53fe0f7a5f6b4e",
    ),
    (
        binding_id = "common_origin_v4_policy",
        repository_relative_path =
            "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/common_origin_acquisition_v4_policy.toml",
        physical_sha256 =
            "84e74d236f0e0ac781a482b996be95fceefe56f2a349be089b51054c3edd8834",
    ),
    (
        binding_id = "current_inventory",
        repository_relative_path = "scripts/us/forecasting/vintages/current_inventory.toml",
        physical_sha256 =
            "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae",
    ),
    (
        binding_id = "sources_toml",
        repository_relative_path = "scripts/us/sources.toml",
        physical_sha256 =
            "41b2bf73b92fb0cf9d9e02ae836beb91d07cd6a3bd20ecf668882350c86f23c9",
    ),
    (
        binding_id = "us_pipeline",
        repository_relative_path = "scripts/us/USPipeline.jl",
        physical_sha256 =
            "ce4d8138a1c07fdc9509d7560f307f226dc314eb0a4394270ef1e1014b9ca14d",
    ),
    (
        binding_id = "scripts_us_project",
        repository_relative_path = "scripts/us/Project.toml",
        physical_sha256 =
            "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c",
    ),
    (
        binding_id = "scripts_us_manifest",
        repository_relative_path = "scripts/us/Manifest.toml",
        physical_sha256 =
            "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263",
    ),
)

const EXPECTED_CITATIONS = (
    (
        id = "census_2023_aies_tables",
        url = "https://www.census.gov/data/tables/2023/econ/aies/2023-aies-tables.html",
        status = "OFFICIAL_PAGE_ROUTE_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "aies00inv_group_dictionary",
        url = "https://api.census.gov/data/timeseries/aies/inv/groups/AIES00INV.html",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "aies31inv_group_dictionary",
        url =
            "https://api.census.gov/data/timeseries/aies/miscsector/groups/AIES31INV.html",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "aies42inv_group_dictionary",
        url =
            "https://api.census.gov/data/timeseries/aies/miscsector/groups/AIES42INV.html",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "aies44inv_group_dictionary",
        url =
            "https://api.census.gov/data/timeseries/aies/miscsector/groups/AIES44INV.html",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "aies51inv_group_dictionary",
        url =
            "https://api.census.gov/data/timeseries/aies/miscsector/groups/AIES51INV.html",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "susb_2022_dataset",
        url = "https://www.census.gov/data/datasets/2022/econ/susb/2022-susb.html",
        status = "OFFICIAL_PAGE_ROUTE_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "susb_record_layout",
        url = "https://www2.census.gov/programs-surveys/susb/technical-documentation/record_layout_us_and_state_2007_to_present.txt",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "susb_enterprise_size_codes",
        url = "https://www2.census.gov/programs-surveys/susb/technical-documentation/enterprise_codes_2017.txt",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "susb_glossary",
        url = "https://www.census.gov/programs-surveys/susb/about/glossary.html",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
    (
        id = "susb_methodology",
        url = "https://www.census.gov/programs-surveys/susb/technical-documentation/methodology.html",
        status = "OFFICIAL_DOCUMENTATION_PAGE_VISIBLE_UNPRESERVED",
    ),
)

struct CensusProfileError <: Exception
    code::Symbol
    detail::String
end

Base.showerror(io::IO, error::CensusProfileError) =
    print(io, String(error.code), ": ", error.detail)

fail(code::Symbol, detail) = throw(CensusProfileError(code, string(detail)))

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(sha256(bytes))

_is_ascii_digit(byte::UInt8) = UInt8('0') <= byte <= UInt8('9')

function _is_ascii_digits(value::AbstractString)
    bytes = codeunits(value)
    return !isempty(bytes) && all(_is_ascii_digit, bytes)
end

function _is_ascii_alphanumeric_hyphen(value::AbstractString)
    bytes = codeunits(value)
    return !isempty(bytes) && all(bytes) do byte
        _is_ascii_digit(byte) || UInt8('A') <= byte <= UInt8('Z') ||
            UInt8('a') <= byte <= UInt8('z') || byte == UInt8('-')
    end
end

function _is_lower_sha256(value::AbstractString)
    bytes = codeunits(value)
    return length(bytes) == 64 && all(bytes) do byte
        _is_ascii_digit(byte) || UInt8('a') <= byte <= UInt8('f')
    end
end


function _is_decimal_lexeme(
        value::AbstractString;
        allow_negative::Bool,
        allow_fraction::Bool,
    )
    bytes = codeunits(value)
    isempty(bytes) && return false
    position = 1
    if bytes[position] == UInt8('-')
        allow_negative || return false
        position += 1
        position <= length(bytes) || return false
    end
    if bytes[position] == UInt8('0')
        position += 1
        position <= length(bytes) && _is_ascii_digit(bytes[position]) && return false
    elseif UInt8('1') <= bytes[position] <= UInt8('9')
        position += 1
        while position <= length(bytes) && _is_ascii_digit(bytes[position])
            position += 1
        end
    else
        return false
    end
    if position <= length(bytes) && bytes[position] == UInt8('.')
        allow_fraction || return false
        position += 1
        position <= length(bytes) && _is_ascii_digit(bytes[position]) || return false
        while position <= length(bytes) && _is_ascii_digit(bytes[position])
            position += 1
        end
    end
    return position > length(bytes)
end

_is_signed_decimal(value::AbstractString) =
    _is_decimal_lexeme(value; allow_negative = true, allow_fraction = true)

_is_nonnegative_decimal(value::AbstractString) =
    _is_decimal_lexeme(value; allow_negative = false, allow_fraction = true)

_is_nonnegative_integer(value::AbstractString) =
    _is_decimal_lexeme(value; allow_negative = false, allow_fraction = false)

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        keys_sorted = sort!([String(key) for key in keys(value)])
        write(io, "D", string(length(keys_sorted)), ":")
        for key in keys_sorted
            _canonical_write(io, key)
            _canonical_write(io, value[key])
        end
    elseif value isa AbstractVector
        write(io, "A", string(length(value)), ":")
        for element in value
            _canonical_write(io, element)
        end
    elseif value isa Bool
        write(io, value ? "B1" : "B0")
    elseif value isa Integer
        representation = string(value)
        write(io, "I", string(ncodeunits(representation)), ":", representation)
    elseif value isa AbstractString
        write(io, "S", string(ncodeunits(value)), ":", value)
    elseif value === nothing
        write(io, "N")
    else
        fail(:UNSUPPORTED_CANONICAL_TYPE, typeof(value))
    end
    return io
end

function _without_content_hash(document::AbstractDict)
    copy = deepcopy(document)
    artifact = get(copy, "artifact", nothing)
    artifact isa AbstractDict || fail(:PROFILE_ARTIFACT_MISSING, "artifact table is required")
    pop!(artifact, "content_sha256", nothing)
    return copy
end

function _canonical_sha256(value)
    io = IOBuffer()
    _canonical_write(io, value)
    return sha256_hex(take!(io))
end

profile_content_sha256(document::AbstractDict) =
    _canonical_sha256(_without_content_hash(document))

function _stamp_profile_content_sha256!(document::AbstractDict)
    artifact = get(document, "artifact", nothing)
    artifact isa AbstractDict || fail(:PROFILE_ARTIFACT_MISSING, "artifact table is required")
    artifact["content_sha256"] = profile_content_sha256(document)
    return document
end

function _validate_toml_concrete_types(value, location::String)
    if typeof(value) === Dict{String, Any}
        for (key, child) in value
            _validate_toml_concrete_types(child, "$location.$key")
        end
    elseif typeof(value) === Vector{Any}
        for (index, child) in enumerate(value)
            typeof(child) === Dict{String, Any} ||
                fail(
                :PROFILE_CONCRETE_TYPE,
                "$location[$index] must be a concrete TOML table, got $(typeof(child))",
            )
            _validate_toml_concrete_types(child, "$location[$index]")
        end
    elseif typeof(value) === Vector{String}
        all(item -> typeof(item) === String, value) ||
            fail(:PROFILE_CONCRETE_TYPE, "$location must contain exact String values")
    elseif typeof(value) === Vector{Union{}}
        isempty(value) || fail(:PROFILE_CONCRETE_TYPE, "$location empty-array type drift")
    elseif typeof(value) === String || typeof(value) === Bool || typeof(value) === Int
        return value
    else
        fail(
            :PROFILE_CONCRETE_TYPE,
            "$location has noncanonical TOML concrete type $(typeof(value))",
        )
    end
    return value
end

function _validate_toml_type_topology(value, expected, location::String)
    typeof(value) === typeof(expected) ||
        fail(
        :PROFILE_CONCRETE_TYPE,
        "$location must have concrete type $(typeof(expected)), got $(typeof(value))",
    )
    if value isa Dict{String, Any}
        for key in keys(value)
            haskey(expected, key) || continue
            _validate_toml_type_topology(value[key], expected[key], "$location.$key")
        end
    elseif value isa AbstractVector
        for index in 1:min(length(value), length(expected))
            _validate_toml_type_topology(value[index], expected[index], "$location[$index]")
        end
    end
    return value
end

function _expect_keys(value, expected, code::Symbol, location::AbstractString)
    value isa AbstractDict || fail(code, "$location must be a table")
    actual = Set(String(key) for key in keys(value))
    target = Set(String.(expected))
    actual == target ||
        fail(code, "$location expected $(sort!(collect(target))); got $(sort!(collect(actual)))")
    return value
end

function _exact_string(value, code::Symbol, location::AbstractString)
    value isa String || fail(code, "$location must be a String, got $(typeof(value))")
    return value
end

function _exact_bool(value, expected::Bool, code::Symbol, location::AbstractString)
    typeof(value) === Bool || fail(code, "$location must be Bool, got $(typeof(value))")
    value === expected || fail(code, "$location must equal $expected")
    return value
end

function _exact_int(value, expected::Int, code::Symbol, location::AbstractString)
    typeof(value) === Int || fail(code, "$location must be Int, got $(typeof(value))")
    value == expected || fail(code, "$location must equal $expected")
    return value
end

function _string_tuple(value, code::Symbol, location::AbstractString)
    value isa AbstractVector || fail(code, "$location must be an array")
    all(item -> item isa String, value) || fail(code, "$location must contain only strings")
    return Tuple(String.(value))
end

function _expect_string_tuple(value, expected, code::Symbol, location::AbstractString)
    actual = _string_tuple(value, code, location)
    actual == expected || fail(code, "$location drifted")
    return actual
end

function _validate_artifact(profile)
    artifact = _expect_keys(
        profile["artifact"],
        ("schema_version", "status", "role", "canonicalization", "content_sha256"),
        :PROFILE_ARTIFACT_SHAPE,
        "profile.artifact",
    )
    artifact["schema_version"] == PROFILE_SCHEMA ||
        fail(:PROFILE_SCHEMA, artifact["schema_version"])
    artifact["status"] == PROFILE_STATUS || fail(:PROFILE_STATUS, artifact["status"])
    artifact["role"] == PROFILE_ROLE || fail(:PROFILE_ROLE, artifact["role"])
    artifact["canonicalization"] == CANONICALIZATION ||
        fail(:PROFILE_CANONICALIZATION, artifact["canonicalization"])
    content_hash = _exact_string(
        artifact["content_sha256"],
        :PROFILE_CONTENT_HASH_TYPE,
        "profile.artifact.content_sha256",
    )
    _is_lower_sha256(content_hash) ||
        fail(:PROFILE_CONTENT_HASH_FORMAT, "content hash must be lowercase SHA-256")
    computed = profile_content_sha256(profile)
    computed == content_hash || fail(:PROFILE_CONTENT_HASH, "semantic self-hash mismatch")
    if EXPECTED_PROFILE_SEMANTIC_SHA256 != "TO_BE_FROZEN"
        computed == EXPECTED_PROFILE_SEMANTIC_SHA256 ||
            fail(:PROFILE_FROZEN_CONTENT_HASH, "coordinated restamp rejected")
    end
    return artifact
end

function _validate_contract(profile)
    contract = _expect_keys(
        profile["contract"],
        (
            "evidence_date",
            "permanent_nonadmitting",
            "maximum_status",
            "successor_required_for_any_higher_status",
            "standard_library_only",
            "synthetic_fixtures_only",
            "synthetic_fixture_format",
            "synthetic_fixture_attributed_to_provider",
            "network_access_forbidden",
            "filesystem_write_forbidden",
            "provider_body_access_forbidden",
            "source_binding_verification_mandatory_for_operational_build_and_replay",
            "source_binding_bypass_keyword_forbidden",
            "required_profile_count",
            "resolved_logical_schema_count",
            "qualified_physical_layout_count",
            "current_qualified_count",
        ),
        :PROFILE_CONTRACT_SHAPE,
        "profile.contract",
    )
    contract["evidence_date"] == "2026-08-08" || fail(:CONTRACT_DATE, "date drift")
    contract["maximum_status"] == PROFILE_STATUS || fail(:CONTRACT_STATUS, "status drift")
    contract["synthetic_fixture_format"] == FIXTURE_FORMAT ||
        fail(:FIXTURE_FORMAT, "fixture format drift")
    for key in (
            "permanent_nonadmitting",
            "successor_required_for_any_higher_status",
            "standard_library_only",
            "synthetic_fixtures_only",
            "network_access_forbidden",
            "filesystem_write_forbidden",
            "provider_body_access_forbidden",
            "source_binding_verification_mandatory_for_operational_build_and_replay",
            "source_binding_bypass_keyword_forbidden",
        )
        _exact_bool(contract[key], true, :CONTRACT_BOUNDARY, "profile.contract.$key")
    end
    _exact_bool(
        contract["synthetic_fixture_attributed_to_provider"],
        false,
        :CONTRACT_BOUNDARY,
        "profile.contract.synthetic_fixture_attributed_to_provider",
    )
    _exact_int(contract["required_profile_count"], 6, :CONTRACT_COUNT, "required count")
    _exact_int(contract["resolved_logical_schema_count"], 6, :CONTRACT_COUNT, "logical count")
    _exact_int(contract["qualified_physical_layout_count"], 0, :CONTRACT_COUNT, "physical count")
    _exact_int(contract["current_qualified_count"], 0, :CONTRACT_COUNT, "qualified count")
    return contract
end

function _validate_physical_evidence(profile)
    evidence = _expect_keys(
        profile["physical_evidence"],
        (
            "status",
            "provider_bodies_preserved",
            "provider_bytes_claimed",
            "provider_header_bytes_verified",
            "provider_column_order_verified",
            "provider_encoding_verified",
            "provider_bom_verified",
            "provider_newlines_verified",
            "provider_null_lexemes_verified",
            "provider_row_order_verified",
            "provider_row_membership_verified",
            "aies_member_names_verified",
            "aies_member_crcs_verified",
            "aies_delimiter_verified",
            "susb_physical_emplfl_r_presence_2022_resolved",
            "susb_complete_flag_vocabulary_resolved",
            "availability_verified",
            "publisher_authentication_verified",
            "transport_authentication_verified",
            "full_provider_object_completeness_verified",
        ),
        :PHYSICAL_EVIDENCE_SHAPE,
        "profile.physical_evidence",
    )
    evidence["status"] == "MISSING_FUTURE_PROSPECTIVE_SIX_BODY_CAPTURE_REQUIRED" ||
        fail(:PHYSICAL_EVIDENCE_STATUS, "status drift")
    for (key, value) in evidence
        key == "status" && continue
        _exact_bool(value, false, :PHYSICAL_EVIDENCE_CLAIM, "profile.physical_evidence.$key")
    end
    return evidence
end

function _validate_aies(profile)
    aies = _expect_keys(
        profile["aies"],
        (
            "year",
            "naics_vintage",
            "geography",
            "common_structural_fields",
            "value_publication_flag_tokens",
            "cv_publication_flag_tokens",
            "flagged_numeric_zero_fill_forbidden",
            "raw_lexeme_preservation_required",
            "flag_meanings",
        ),
        :AIES_SHAPE,
        "profile.aies",
    )
    aies["year"] == "2023" || fail(:AIES_YEAR, "year drift")
    aies["naics_vintage"] == "2017" || fail(:AIES_NAICS, "vintage drift")
    aies["geography"] == "0100000US" || fail(:AIES_GEOGRAPHY, "geography drift")
    _expect_string_tuple(aies["common_structural_fields"], AIES_COMMON_FIELDS, :AIES_FIELDS, "common fields")
    _expect_string_tuple(aies["value_publication_flag_tokens"], AIES_VALUE_FLAGS, :AIES_FLAGS, "value flags")
    _expect_string_tuple(aies["cv_publication_flag_tokens"], AIES_CV_FLAGS, :AIES_FLAGS, "CV flags")
    _exact_bool(aies["flagged_numeric_zero_fill_forbidden"], true, :AIES_ZERO_FILL, "zero-fill rule")
    _exact_bool(aies["raw_lexeme_preservation_required"], true, :AIES_LEXEME, "lexeme rule")
    meanings = _expect_keys(aies["flag_meanings"], ("D", "N", "S", "Z", "v", "w"), :AIES_FLAG_MEANINGS, "AIES meanings")
    expected = (
        D = "WITHHELD_TO_AVOID_DISCLOSING_OPERATIONS_OF_INDIVIDUAL_COMPANIES_DATA_INCLUDED_IN_HIGHER_LEVEL_TOTALS",
        N = "NOT_AVAILABLE_OR_NOT_COMPARABLE",
        S = "ESTIMATE_DOES_NOT_MEET_PUBLICATION_STANDARDS",
        Z = "ESTIMATE_ROUNDS_TO_ZERO",
        v = "CV_30_POINT_0_TO_60_POINT_8_PERCENT",
        w = "CV_GREATER_THAN_60_POINT_8_PERCENT_AND_NOT_SIGNIFICANTLY_DIFFERENT_FROM_ZERO_AT_90_PERCENT",
    )
    for key in keys(expected)
        meanings[String(key)] == getproperty(expected, key) || fail(:AIES_FLAG_MEANINGS, String(key))
    end
    return aies
end

function _validate_susb(profile)
    susb = _expect_keys(
        profile["susb"],
        (
            "year",
            "naics_vintage",
            "canonical_filename",
            "logical_fields",
            "key_fields",
            "integer_fields",
            "flag_fields",
            "description_fields",
            "national_state_code",
            "all_published_size_codes",
            "disjoint_size_codes",
            "subtotal_05_components",
            "subtotal_08_components",
            "total_01_components",
            "all_published_codes_means_retain_not_sum",
            "national_total_projection_state",
            "national_total_projection_size",
            "national_total_projection_must_be_separately_hashed",
            "synthetic_known_noise_flag_tokens",
            "complete_provider_flag_vocabulary_resolved",
            "historical_D_replaced_by_S_starting_2017",
            "historical_D_allowed_in_2022_synthetic_fixture",
            "emplfl_r_discontinued_starting_2018",
            "synthetic_2022_emplfl_r_must_be_empty",
            "physical_2022_emplfl_r_column_presence_resolved",
            "suppressed_numeric_zero_is_withheld_unknown",
            "suppressed_value_included_in_broader_totals",
            "firm_interindustry_additivity",
            "firm_model_role",
            "overlap_checks_limited_to_each_state_naics_key",
            "cross_naics_firm_sum_forbidden",
            "known_flag_meanings",
        ),
        :SUSB_SHAPE,
        "profile.susb",
    )
    susb["year"] == "2022" || fail(:SUSB_YEAR, "year drift")
    susb["naics_vintage"] == "2017" || fail(:SUSB_NAICS, "vintage drift")
    susb["canonical_filename"] == "us_state_6digitnaics_2022.txt" ||
        fail(:SUSB_FILENAME, "canonical filename drift")
    _expect_string_tuple(susb["logical_fields"], SUSB_FIELDS, :SUSB_FIELDS, "logical fields")
    _expect_string_tuple(susb["key_fields"], ("STATE", "NAICS", "ENTRSIZE"), :SUSB_FIELDS, "key fields")
    _expect_string_tuple(susb["integer_fields"], SUSB_METRICS, :SUSB_FIELDS, "integer fields")
    _expect_string_tuple(susb["flag_fields"], ("EMPLFL_R", "EMPLFL_N", "PAYRFL_N", "RCPTFL_N"), :SUSB_FIELDS, "flag fields")
    _expect_string_tuple(susb["description_fields"], ("STATEDSCR", "NAICSDSCR", "ENTRSIZEDSCR"), :SUSB_FIELDS, "description fields")
    _expect_string_tuple(susb["all_published_size_codes"], SUSB_SIZE_CODES, :SUSB_SIZE_CODES, "all size codes")
    _expect_string_tuple(susb["disjoint_size_codes"], ("02", "03", "04", "06", "07", "09"), :SUSB_SIZE_CODES, "disjoint size codes")
    _expect_string_tuple(susb["subtotal_05_components"], ("02", "03", "04"), :SUSB_SIZE_CODES, "05 identity")
    _expect_string_tuple(susb["subtotal_08_components"], ("05", "06", "07"), :SUSB_SIZE_CODES, "08 identity")
    _expect_string_tuple(susb["total_01_components"], ("08", "09"), :SUSB_SIZE_CODES, "01 identity")
    _expect_string_tuple(susb["synthetic_known_noise_flag_tokens"], SUSB_FLAG_TOKENS, :SUSB_FLAGS, "synthetic flags")
    susb["national_state_code"] == "00" || fail(:SUSB_STATE, "national state drift")
    susb["national_total_projection_state"] == "00" || fail(:SUSB_PROJECTION, "state drift")
    susb["national_total_projection_size"] == "01" || fail(:SUSB_PROJECTION, "size drift")
    susb["firm_interindustry_additivity"] ==
        "PROHIBITED_MULTI_INDUSTRY_ENTERPRISE_DOUBLE_COUNT_RISK" ||
        fail(:SUSB_FIRM_CEILING, "interindustry ceiling drift")
    susb["firm_model_role"] ==
        "INDUSTRY_FIRM_PRESENCES_PROXY_ONLY_PENDING_VALIDATED_ALLOCATION_OR_DEDUPLICATION_ONTOLOGY" ||
        fail(:SUSB_FIRM_CEILING, "model role drift")
    for key in (
            "all_published_codes_means_retain_not_sum",
            "national_total_projection_must_be_separately_hashed",
            "historical_D_replaced_by_S_starting_2017",
            "emplfl_r_discontinued_starting_2018",
            "synthetic_2022_emplfl_r_must_be_empty",
            "suppressed_numeric_zero_is_withheld_unknown",
            "suppressed_value_included_in_broader_totals",
            "overlap_checks_limited_to_each_state_naics_key",
            "cross_naics_firm_sum_forbidden",
        )
        _exact_bool(susb[key], true, :SUSB_RULE, "profile.susb.$key")
    end
    for key in (
            "complete_provider_flag_vocabulary_resolved",
            "historical_D_allowed_in_2022_synthetic_fixture",
            "physical_2022_emplfl_r_column_presence_resolved",
        )
        _exact_bool(susb[key], false, :SUSB_RULE, "profile.susb.$key")
    end
    meanings = _expect_keys(susb["known_flag_meanings"], ("G", "H", "J", "S", "D"), :SUSB_FLAG_MEANINGS, "SUSB meanings")
    expected = (
        G = "NOISE_RANGE_LESS_THAN_2_PERCENT",
        H = "NOISE_RANGE_2_TO_LESS_THAN_5_PERCENT",
        J = "NOISE_RANGE_AT_LEAST_5_PERCENT",
        S = "WITHHELD_NUMERIC_SET_TO_ZERO_AND_INCLUDED_IN_BROADER_TOTALS",
        D = "HISTORICAL_DISCLOSURE_FLAG_REPLACED_BY_S_STARTING_2017",
    )
    for key in keys(expected)
        meanings[String(key)] == getproperty(expected, key) || fail(:SUSB_FLAG_MEANINGS, String(key))
    end
    return susb
end

function _validate_profiles(profile)
    profiles = profile["profiles"]
    profiles isa AbstractVector || fail(:PROFILES_SHAPE, "profiles must be an array")
    length(profiles) == length(EXPECTED_PROFILE_SPECS) ||
        fail(:PROFILE_COUNT, "expected six profiles")
    required_keys = (
        "profile_id",
        "requirement_id",
        "product_code",
        "archive_filename",
        "source_url",
        "provider_member_name",
        "expected_field_count",
        "key_fields",
        "dimension_fields",
        "label_fields",
        "structural_flag_fields",
        "measure_value_fields",
        "measure_value_flag_fields",
        "measure_cv_fields",
        "measure_cv_flag_fields",
        "logical_fields",
    )
    for (index, expected) in enumerate(EXPECTED_PROFILE_SPECS)
        location = "profile.profiles[$index]"
        entry = _expect_keys(profiles[index], required_keys, :PROFILE_ENTRY_SHAPE, location)
        for key in (
                :profile_id,
                :requirement_id,
                :product_code,
                :archive_filename,
                :source_url,
                :provider_member_name,
            )
            entry[String(key)] == getproperty(expected, key) ||
                fail(:PROFILE_ENTRY_DRIFT, "$location.$key")
        end
        _exact_int(
            entry["expected_field_count"],
            expected.expected_field_count,
            :PROFILE_FIELD_COUNT,
            "$location.expected_field_count",
        )
        for key in (
                :key_fields,
                :dimension_fields,
                :label_fields,
                :structural_flag_fields,
                :measure_value_fields,
                :measure_value_flag_fields,
                :measure_cv_fields,
                :measure_cv_flag_fields,
                :logical_fields,
            )
            _expect_string_tuple(
                entry[String(key)],
                getproperty(expected, key),
                :PROFILE_ENTRY_DRIFT,
                "$location.$key",
            )
        end
        fields = expected.logical_fields
        length(fields) == expected.expected_field_count ||
            fail(:PROFILE_FIELD_COUNT, "$location internal count mismatch")
        length(Set(fields)) == length(fields) || fail(:PROFILE_DUPLICATE_FIELD, location)
        all(field -> field in fields, expected.key_fields) ||
            fail(:PROFILE_KEY_FIELD, "$location key outside schema")
        all(field -> field in expected.dimension_fields, expected.key_fields) ||
            fail(:PROFILE_KEY_FIELD, "$location key outside dimensions")
        if startswith(expected.product_code, "AIES")
            fields[1:length(AIES_COMMON_FIELDS)] == AIES_COMMON_FIELDS ||
                fail(:AIES_COMMON_FIELD_ORDER, location)
            length(expected.measure_value_fields) == length(expected.measure_value_flag_fields) ==
                length(expected.measure_cv_fields) == length(expected.measure_cv_flag_fields) ||
                fail(:AIES_MEASURE_PAIRING, location)
        else
            fields == SUSB_FIELDS || fail(:SUSB_FIELDS, location)
        end
    end
    return profiles
end

function _validate_source_binding_declarations(bindings)
    bindings isa AbstractVector || fail(:SOURCE_BINDINGS_SHAPE, "bindings must be an array")
    length(bindings) == length(EXPECTED_SOURCE_BINDINGS) ||
        fail(:SOURCE_BINDINGS_COUNT, "binding count drift")
    for (index, expected) in enumerate(EXPECTED_SOURCE_BINDINGS)
        location = "profile.source_bindings[$index]"
        entry = _expect_keys(
            bindings[index],
            ("binding_id", "repository_relative_path", "physical_sha256"),
            :SOURCE_BINDING_SHAPE,
            location,
        )
        for key in (:binding_id, :repository_relative_path, :physical_sha256)
            value = _exact_string(entry[String(key)], :SOURCE_BINDING_TYPE, "$location.$key")
            value == getproperty(expected, key) || fail(:SOURCE_BINDING_DRIFT, "$location.$key")
        end
        _is_lower_sha256(entry["physical_sha256"]) ||
            fail(:SOURCE_BINDING_HASH_FORMAT, location)
    end
    return bindings
end

function _path_inside_repository(relative_path::String)
    isabspath(relative_path) && fail(:SOURCE_BINDING_PATH, "absolute path forbidden")
    split_path = splitpath(relative_path)
    any(component -> component in ("", ".", ".."), split_path) &&
        fail(:SOURCE_BINDING_PATH, "noncanonical path component")
    resolved = normpath(joinpath(REPOSITORY_ROOT, relative_path))
    prefix = REPOSITORY_ROOT * Base.Filesystem.path_separator
    startswith(resolved, prefix) || fail(:SOURCE_BINDING_PATH, "path escapes repository")
    cursor = REPOSITORY_ROOT
    for component in split_path
        cursor = joinpath(cursor, component)
        islink(cursor) && fail(:SOURCE_BINDING_SYMLINK, relative_path)
    end
    return resolved
end

function _read_single_link_regular_file(path::String, location::String)
    islink(path) && fail(:SYMLINK_FILE, location)
    isfile(path) || fail(:MISSING_FILE, location)
    metadata = stat(path)
    metadata.nlink == 1 || fail(:HARDLINK_FILE, "$location has $(metadata.nlink) links")
    return read(path)
end

function _verify_source_bindings(bindings)
    _validate_source_binding_declarations(bindings)
    for (index, expected) in enumerate(EXPECTED_SOURCE_BINDINGS)
        entry = bindings[index]
        path = _path_inside_repository(expected.repository_relative_path)
        bytes = _read_single_link_regular_file(path, expected.repository_relative_path)
        actual = sha256_hex(bytes)
        actual == expected.physical_sha256 ||
            fail(:SOURCE_BINDING_HASH, "$(expected.binding_id) expected $(expected.physical_sha256), got $actual")
        entry["physical_sha256"] == actual || fail(:SOURCE_BINDING_HASH, expected.binding_id)
    end
    return true
end

function _validate_citations(profile)
    citations = profile["citations"]
    citations isa AbstractVector || fail(:CITATIONS_SHAPE, "citations must be an array")
    length(citations) == length(EXPECTED_CITATIONS) || fail(:CITATIONS_COUNT, "count drift")
    for (index, expected) in enumerate(EXPECTED_CITATIONS)
        entry = _expect_keys(
            citations[index],
            ("id", "url", "status", "local_bytes_sha256"),
            :CITATION_SHAPE,
            "profile.citations[$index]",
        )
        entry["id"] == expected.id || fail(:CITATION_DRIFT, "id $index")
        entry["url"] == expected.url || fail(:CITATION_DRIFT, "url $index")
        entry["status"] == expected.status || fail(:CITATION_DRIFT, "status $index")
        entry["local_bytes_sha256"] == "NOT_PRESERVED" ||
            fail(:CITATION_BYTES_CLAIM, "citation $index")
    end
    return citations
end

function validate_profile_document(document)
    _validate_toml_concrete_types(document, "profile")
    expected_type_topology = _read_profile(PROFILE_PATH)
    _validate_toml_type_topology(document, expected_type_topology, "profile")
    profile = _expect_keys(
        document,
        (
            "prohibited_actions",
            "artifact",
            "contract",
            "physical_evidence",
            "aies",
            "susb",
            "gates",
            "profiles",
            "source_bindings",
            "citations",
        ),
        :PROFILE_TOP_LEVEL_SHAPE,
        "profile",
    )
    _expect_string_tuple(
        profile["prohibited_actions"],
        PROHIBITED_ACTIONS,
        :PROHIBITED_ACTIONS,
        "profile.prohibited_actions",
    )
    _validate_artifact(profile)
    _validate_contract(profile)
    _validate_physical_evidence(profile)
    _validate_aies(profile)
    _validate_susb(profile)
    _validate_profiles(profile)
    gates = profile["gates"]
    gates isa AbstractDict || fail(:GATES_SHAPE, "gates must be a table")
    Set(String(key) for key in keys(gates)) == Set(
        (
            "provider_parser_allowed",
            "capture_allowed",
            "qualified_leaf_allowed",
            "model_input_allowed",
            "origin_admission_allowed",
            "forecast_execution_allowed",
            "truth_access_allowed",
            "scoring_allowed",
            "accuracy_claim_allowed",
            "promotion_allowed",
            "production_allowed",
        )
    ) || fail(:GATES_SHAPE, "gate set drift")
    for (key, value) in gates
        _exact_bool(value, false, :GATE_TRUE, "profile.gates.$key")
    end
    _validate_source_binding_declarations(profile["source_bindings"])
    _validate_citations(profile)
    _verify_source_bindings(profile["source_bindings"])
    return profile
end

function _read_profile(path::AbstractString)
    path isa String || fail(:PROFILE_PATH_TYPE, "profile path must be String")
    isabspath(path) || fail(:PROFILE_PATH, "profile path must be absolute")
    bytes = _read_single_link_regular_file(path, path)
    length(bytes) <= 1_048_576 || fail(:PROFILE_SIZE, "profile exceeds one MiB")
    physical_hash = sha256_hex(bytes)
    if EXPECTED_PROFILE_PHYSICAL_SHA256 != "TO_BE_FROZEN"
        physical_hash == EXPECTED_PROFILE_PHYSICAL_SHA256 ||
            fail(:PROFILE_FROZEN_PHYSICAL_HASH, "profile physical identity mismatch")
    end
    text = String(copy(bytes))
    isvalid(text) || fail(:PROFILE_UTF8, "profile is invalid UTF-8")
    document = try
        TOML.parse(text)
    catch error
        fail(:PROFILE_TOML, sprint(showerror, error))
    end
    return document
end

function load_profile(path::AbstractString = PROFILE_PATH)
    document = _read_profile(path)
    return validate_profile_document(document)
end

function _profile_entry(profile, profile_id::String)
    matches = [entry for entry in profile["profiles"] if entry["profile_id"] == profile_id]
    length(matches) == 1 || fail(:UNKNOWN_PROFILE, profile_id)
    return only(matches)
end

function _validate_fixture_bytes(bytes)
    typeof(bytes) === Vector{UInt8} ||
        fail(:FIXTURE_BYTES_TYPE, "fixture must be an exact Vector{UInt8}")
    isempty(bytes) && fail(:FIXTURE_EMPTY, "fixture is empty")
    length(bytes) <= MAX_FIXTURE_BYTES || fail(:FIXTURE_SIZE, "fixture exceeds byte limit")
    text = String(copy(bytes))
    isvalid(text) || fail(:FIXTURE_UTF8, "fixture is invalid UTF-8")
    length(bytes) >= 3 && bytes[1:3] == UInt8[0xef, 0xbb, 0xbf] &&
        fail(:FIXTURE_BOM, "BOM forbidden")
    bytes[end] == 0x0a || fail(:FIXTURE_TERMINATOR, "final LF required")
    for byte in bytes
        if byte == 0x0d
            fail(:FIXTURE_NEWLINE, "CR is forbidden")
        elseif byte < 0x20 && byte != 0x09 && byte != 0x0a
            fail(:FIXTURE_CONTROL, "control byte 0x$(string(byte; base = 16))")
        elseif byte == 0x7f
            fail(:FIXTURE_CONTROL, "DEL is forbidden")
        end
    end
    return text
end

function _split_fixture(bytes)
    text = _validate_fixture_bytes(bytes)
    lines = split(text, '\n'; keepempty = true)
    isempty(lines[end]) || fail(:FIXTURE_TERMINATOR, "final LF parse mismatch")
    pop!(lines)
    length(lines) >= 2 || fail(:FIXTURE_ROWS, "header and at least one row required")
    length(lines) - 1 <= MAX_FIXTURE_ROWS || fail(:FIXTURE_ROWS, "row limit exceeded")
    any(isempty, lines) && fail(:FIXTURE_BLANK_LINE, "blank line forbidden")
    return lines
end

function _split_fields(line::AbstractString, ordinal::Int)
    fields = String.(split(line, '\t'; keepempty = true))
    for (column, field) in enumerate(fields)
        ncodeunits(field) <= MAX_FIELD_BYTES ||
            fail(:FIXTURE_FIELD_SIZE, "row $ordinal column $column")
        any(iscntrl, field) &&
            fail(:FIXTURE_FIELD_CONTROL, "row $ordinal column $column")
        strip(field) == field ||
            fail(:FIXTURE_FIELD_WHITESPACE, "row $ordinal column $column")
    end
    return fields
end

function _key_fingerprint(row, key_fields)
    io = IOBuffer()
    for field in key_fields
        value = row[field]
        write(io, string(ncodeunits(value)), ":", value, ";")
    end
    return sha256_hex(take!(io))
end

function _state_record(raw_value, raw_flag, publication_state, model_numeric_allowed)
    return Dict{String, Any}(
        "raw_value" => raw_value,
        "raw_flag" => raw_flag,
        "publication_state" => publication_state,
        "model_numeric_allowed" => model_numeric_allowed,
        "zero_fill_forbidden" => true,
    )
end

function _validate_numeric_lexeme(
        raw_value,
        policy::Symbol,
        code::Symbol,
        location::String,
    )
    ncodeunits(raw_value) <= MAX_NUMERIC_BYTES || fail(:NUMERIC_LEXEME_SIZE, location)
    valid = if policy === :SIGNED_DECIMAL
        _is_signed_decimal(raw_value)
    elseif policy === :NONNEGATIVE_DECIMAL
        _is_nonnegative_decimal(raw_value)
    elseif policy === :NONNEGATIVE_INTEGER
        _is_nonnegative_integer(raw_value)
    else
        fail(:NUMERIC_POLICY, "unsupported numeric policy $policy")
    end
    valid || fail(code, location)
    return raw_value
end

function _validate_aies_row(entry, row, ordinal)
    row["GEO_ID"] == "0100000US" || fail(:AIES_GEOGRAPHY, "row $ordinal")
    row["YEAR"] == "2023" || fail(:AIES_YEAR, "row $ordinal")
    _is_ascii_digits(row["INDLEVEL"]) || fail(:AIES_INDLEVEL_TYPE, "row $ordinal")
    _is_ascii_alphanumeric_hyphen(row["NAICS"]) ||
        fail(:AIES_NAICS_TYPE, "row $ordinal")
    for field in entry["dimension_fields"]
        isempty(row[field]) && fail(:AIES_DIMENSION_EMPTY, "row $ordinal field $field")
        if field != "GEO_ID" && field != "YEAR"
            _is_ascii_alphanumeric_hyphen(row[field]) ||
                fail(:AIES_DIMENSION_TYPE, "row $ordinal field $field")
        end
    end
    for field in entry["label_fields"]
        isempty(row[field]) && fail(:AIES_LABEL_EMPTY, "row $ordinal field $field")
    end
    for field in entry["structural_flag_fields"]
        isempty(row[field]) || fail(:AIES_STRUCTURAL_FLAG_UNRESOLVED, "row $ordinal field $field")
    end
    states = Dict{String, Any}()
    for index in eachindex(entry["measure_value_fields"])
        value_field = entry["measure_value_fields"][index]
        flag_field = entry["measure_value_flag_fields"][index]
        raw_value = row[value_field]
        raw_flag = row[flag_field]
        raw_flag in AIES_VALUE_FLAGS ||
            fail(:AIES_VALUE_FLAG, "row $ordinal field $flag_field token '$raw_flag'")
        if isempty(raw_flag)
            _validate_numeric_lexeme(
                raw_value,
                :SIGNED_DECIMAL,
                :AIES_VALUE_TYPE,
                "row $ordinal field $value_field",
            )
            state = "PUBLISHED_NUMERIC"
            allowed = true
        else
            if !isempty(raw_value)
                _validate_numeric_lexeme(
                    raw_value,
                    :SIGNED_DECIMAL,
                    :AIES_VALUE_TYPE,
                    "row $ordinal field $value_field",
                )
            end
            state = "PUBLICATION_STATE_" * raw_flag
            allowed = false
        end
        states[value_field] = _state_record(raw_value, raw_flag, state, allowed)

        cv_field = entry["measure_cv_fields"][index]
        cv_flag_field = entry["measure_cv_flag_fields"][index]
        raw_cv = row[cv_field]
        raw_cv_flag = row[cv_flag_field]
        raw_cv_flag in AIES_CV_FLAGS ||
            fail(:AIES_CV_FLAG, "row $ordinal field $cv_flag_field token '$raw_cv_flag'")
        _validate_numeric_lexeme(
            raw_cv,
            :NONNEGATIVE_DECIMAL,
            :AIES_CV_TYPE,
            "row $ordinal field $cv_field",
        )
        cv_state = isempty(raw_cv_flag) ? "PUBLISHED_CV" : "PUBLICATION_STATE_" * raw_cv_flag
        states[cv_field] =
            _state_record(raw_cv, raw_cv_flag, cv_state, isempty(raw_cv_flag))
    end
    return states
end

function _susb_metric_flag(row, metric)
    if metric == "EMPL"
        return isempty(row["EMPLFL_R"]) ? row["EMPLFL_N"] : row["EMPLFL_R"]
    elseif metric == "PAYR"
        return row["PAYRFL_N"]
    elseif metric == "RCPT"
        return row["RCPTFL_N"]
    end
    return ""
end

function _validate_susb_row(row, ordinal)
    ncodeunits(row["STATE"]) == 2 && _is_ascii_digits(row["STATE"]) ||
        fail(:SUSB_STATE_TYPE, "row $ordinal")
    2 <= ncodeunits(row["NAICS"]) <= 8 && _is_ascii_alphanumeric_hyphen(row["NAICS"]) ||
        fail(:SUSB_NAICS_TYPE, "row $ordinal")
    row["ENTRSIZE"] in SUSB_SIZE_CODES || fail(:SUSB_SIZE_CODE, "row $ordinal")
    for field in ("STATEDSCR", "NAICSDSCR", "ENTRSIZEDSCR")
        isempty(row[field]) && fail(:SUSB_DESCRIPTION_EMPTY, "row $ordinal field $field")
    end
    isempty(row["EMPLFL_R"]) || fail(:SUSB_EMPLFL_R_2022, "row $ordinal must be empty")
    for field in ("EMPLFL_N", "PAYRFL_N", "RCPTFL_N")
        token = row[field]
        token in SUSB_FLAG_TOKENS || fail(:SUSB_FLAG, "row $ordinal field $field")
        token == "D" && fail(:SUSB_HISTORICAL_D_2022, "row $ordinal field $field")
    end
    states = Dict{String, Any}()
    for metric in SUSB_METRICS
        raw_value = row[metric]
        _validate_numeric_lexeme(
            raw_value,
            :NONNEGATIVE_INTEGER,
            :SUSB_INTEGER_TYPE,
            "row $ordinal field $metric",
        )
        raw_flag = _susb_metric_flag(row, metric)
        if raw_flag == "S"
            raw_value == "0" || fail(:SUSB_SUPPRESSED_LEXEME, "row $ordinal field $metric")
            state = "WITHHELD_UNKNOWN_INCLUDED_IN_BROADER_TOTALS"
            model_allowed = false
            identity_allowed = false
        elseif raw_flag in ("G", "H", "J")
            state = "PUBLISHED_NOISE_CLASS_" * raw_flag
            model_allowed = true
            identity_allowed = false
        else
            state = "PUBLISHED_NUMERIC"
            model_allowed = true
            identity_allowed = true
        end
        record = _state_record(raw_value, raw_flag, state, model_allowed)
        record["overlap_identity_numeric_allowed"] = identity_allowed
        states[metric] = record
    end
    return states
end

function _parse_logical_fixture(profile, entry, bytes)
    lines = _split_fixture(bytes)
    header = _split_fields(lines[1], 1)
    length(Set(header)) == length(header) || fail(:FIXTURE_DUPLICATE_HEADER, entry["profile_id"])
    expected_header = String.(entry["logical_fields"])
    header == expected_header || fail(:FIXTURE_HEADER, entry["profile_id"])
    rows = Vector{Dict{String, String}}()
    row_states = Vector{Dict{String, Any}}()
    row_key_sha256 = String[]
    seen_keys = Set{Tuple}()
    for (offset, line) in enumerate(lines[2:end])
        ordinal = offset + 1
        fields = _split_fields(line, ordinal)
        length(fields) == length(header) ||
            fail(:FIXTURE_ROW_WIDTH, "$(entry["profile_id"]) row $ordinal")
        row = Dict{String, String}(header[index] => fields[index] for index in eachindex(header))
        key = Tuple(row[field] for field in entry["key_fields"])
        key in seen_keys &&
            fail(:FIXTURE_DUPLICATE_KEY, "$(entry["profile_id"]) row $ordinal")
        push!(seen_keys, key)
        fingerprint = _key_fingerprint(row, entry["key_fields"])
        states = if startswith(entry["product_code"], "AIES")
            _validate_aies_row(entry, row, ordinal)
        else
            _validate_susb_row(row, ordinal)
        end
        push!(rows, row)
        push!(row_states, states)
        push!(row_key_sha256, fingerprint)
    end
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-census-synthetic-logical-table.v1",
        "profile_id" => entry["profile_id"],
        "fixture_format" => FIXTURE_FORMAT,
        "synthetic_fixture_attributed_to_provider" => false,
        "fixture_sha256" => sha256_hex(bytes),
        "header" => header,
        "row_count" => length(rows),
        "rows" => rows,
        "row_states" => row_states,
        "row_key_sha256" => row_key_sha256,
        "provider_physical_layout_claimed" => false,
    )
end

function _susb_groups(table)
    groups = Dict{Tuple{String, String}, Dict{String, Int}}()
    for (index, row) in enumerate(table["rows"])
        group = get!(groups, (row["STATE"], row["NAICS"]), Dict{String, Int}())
        group[row["ENTRSIZE"]] = index
    end
    isempty(groups) && fail(:SUSB_COVERAGE, "no SUSB groups")
    for (key, index_by_code) in groups
        Set(keys(index_by_code)) == Set(SUSB_SIZE_CODES) ||
            fail(:SUSB_COVERAGE, "group $key must contain exact codes 01-09")
    end
    any(key -> key[1] == "00", keys(groups)) ||
        fail(:SUSB_NATIONAL_COVERAGE, "at least one STATE=00 group is required")
    return groups
end

function _susb_overlap_checks(table, groups)
    checks = Vector{Dict{String, Any}}()
    for group_key in sort!(collect(keys(groups)))
        index_by_code = groups[group_key]
        for metric in SUSB_METRICS
            for equation in SUSB_OVERLAP_EQUATIONS
                codes = (equation.target, equation.components...)
                indices = [index_by_code[code] for code in codes]
                states = [table["row_states"][index][metric] for index in indices]
                raw_values = [table["rows"][index][metric] for index in indices]
                exact_check_allowed = all(state -> state["overlap_identity_numeric_allowed"], states)
                status = if exact_check_allowed
                    target = parse(BigInt, raw_values[1])
                    components = parse.(BigInt, raw_values[2:end])
                    target == sum(components) || fail(
                        :SUSB_OVERLAP_IDENTITY,
                        "state=$(group_key[1]) naics=$(group_key[2]) metric=$metric target=$(equation.target)",
                    )
                    "VERIFIED_EXACT"
                else
                    "UNVERIFIABLE_PUBLICATION_STATE_NOT_ZERO_FILLED"
                end
                push!(
                    checks,
                    Dict{String, Any}(
                        "state" => group_key[1],
                        "naics" => group_key[2],
                        "metric" => metric,
                        "target_size_code" => equation.target,
                        "component_size_codes" => collect(equation.components),
                        "raw_values_target_then_components" => raw_values,
                        "status" => status,
                        "cross_naics_aggregation_performed" => false,
                    ),
                )
            end
        end
    end
    return checks
end

function _susb_projection(table)
    selected_indices = [
        index for (index, row) in enumerate(table["rows"])
            if row["STATE"] == "00" && row["ENTRSIZE"] == "01"
    ]
    isempty(selected_indices) && fail(:SUSB_NATIONAL_PROJECTION, "projection is empty")
    rows = [deepcopy(table["rows"][index]) for index in selected_indices]
    states = [deepcopy(table["row_states"][index]) for index in selected_indices]
    projection_body = Dict{String, Any}(
        "source_fixture_sha256" => table["fixture_sha256"],
        "selection" => "STATE=00_AND_ENTRSIZE=01",
        "input_row_count" => table["row_count"],
        "projection_row_count" => length(rows),
        "rows" => rows,
        "row_states" => states,
        "firm_model_role" =>
            "INDUSTRY_FIRM_PRESENCES_PROXY_ONLY_PENDING_VALIDATED_ALLOCATION_OR_DEDUPLICATION_ONTOLOGY",
        "cross_naics_firm_sum_forbidden" => true,
    )
    return Dict{String, Any}(
        projection_body...,
        "content_sha256" => _canonical_sha256(projection_body),
    )
end

function parse_logical_fixture(
        profile_id::AbstractString,
        bytes;
        profile_path::AbstractString = PROFILE_PATH,
    )
    profile_id isa String || fail(:PROFILE_ID_TYPE, "profile ID must be String")
    profile = load_profile(profile_path)
    entry = _profile_entry(profile, profile_id)
    table = _parse_logical_fixture(profile, entry, bytes)
    if profile_id == "susb_employer_enterprises"
        groups = _susb_groups(table)
        _susb_overlap_checks(table, groups)
        _susb_projection(table)
    end
    return table
end

function _validate_fixture_set(profile, fixtures)
    fixtures isa AbstractDict || fail(:FIXTURE_SET_TYPE, "fixtures must be a dictionary")
    all(key -> key isa String, keys(fixtures)) ||
        fail(:FIXTURE_SET_KEY_TYPE, "fixture keys must be strings")
    expected_ids = Tuple(entry["profile_id"] for entry in profile["profiles"])
    Set(String(key) for key in keys(fixtures)) == Set(expected_ids) ||
        fail(:FIXTURE_SET_COVERAGE, "fixture set must contain exactly six profile IDs")
    return expected_ids
end

function _build_result(profile, fixtures)
    expected_ids = _validate_fixture_set(profile, fixtures)
    tables = Vector{Dict{String, Any}}()
    for profile_id in expected_ids
        entry = _profile_entry(profile, profile_id)
        push!(tables, _parse_logical_fixture(profile, entry, fixtures[profile_id]))
    end
    susb_table = only(table for table in tables if table["profile_id"] == "susb_employer_enterprises")
    groups = _susb_groups(susb_table)
    overlap_checks = _susb_overlap_checks(susb_table, groups)
    projection = _susb_projection(susb_table)
    body = Dict{String, Any}(
        "schema_version" => "beforeit-us-census-structural-logical-result.v1",
        "status" => PROFILE_STATUS,
        "role" => PROFILE_ROLE,
        "profile_content_sha256" => profile["artifact"]["content_sha256"],
        "fixture_format" => FIXTURE_FORMAT,
        "synthetic_fixtures_attributed_to_provider" => false,
        "profile_count" => length(tables),
        "resolved_logical_schema_count" => 6,
        "qualified_physical_layout_count" => 0,
        "tables" => tables,
        "susb_overlap_checks" => overlap_checks,
        "susb_national_total_projection" => projection,
        "susb_all_size_codes_retained" => collect(SUSB_SIZE_CODES),
        "susb_all_codes_are_never_summed_together" => true,
        "susb_firm_interindustry_additivity" =>
            "PROHIBITED_MULTI_INDUSTRY_ENTERPRISE_DOUBLE_COUNT_RISK",
        "provider_physical_layouts_unresolved" => true,
        "gates" => deepcopy(profile["gates"]),
    )
    return Dict{String, Any}(body..., "content_sha256" => _canonical_sha256(body))
end

function build_structural_result(
        fixtures;
        profile_path::AbstractString = PROFILE_PATH,
    )
    profile = load_profile(profile_path)
    return _build_result(profile, fixtures)
end

function _deep_exact(left, right)
    typeof(left) === typeof(right) || return false
    if left isa AbstractDict
        Set(keys(left)) == Set(keys(right)) || return false
        return all(key -> _deep_exact(left[key], right[key]), keys(left))
    elseif left isa AbstractVector
        length(left) == length(right) || return false
        return all(index -> _deep_exact(left[index], right[index]), eachindex(left))
    end
    return isequal(left, right)
end

function validate_structural_result(
        result,
        fixtures;
        profile_path::AbstractString = PROFILE_PATH,
    )
    result isa AbstractDict || fail(:RESULT_TYPE, "result must be a dictionary")
    profile = load_profile(profile_path)
    expected = _build_result(profile, fixtures)
    _deep_exact(result, expected) || fail(:RESULT_REPLAY, "result differs from exact replay")
    return result
end

end
