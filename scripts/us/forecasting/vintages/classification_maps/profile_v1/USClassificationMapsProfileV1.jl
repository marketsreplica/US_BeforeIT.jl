module USClassificationMapsProfileV1

using SHA
using TOML

export ClassificationMapError,
    PROFILE_PATH,
    profile_semantic_sha256,
    validate_compiled_result,
    validate_object_set,
    validate_profile

const PROFILE_PATH = joinpath(@__DIR__, "classification_maps_profile_v1.toml")
const REPOSITORY_ROOT = dirname(
    normpath(
        joinpath(
            @__DIR__, "..", "..", "..", "..", "..", "..",
            "repository-root-sentinel",
        ),
    ),
)
const PROFILE_SCHEMA = "beforeit-us-classification-maps-offline-profile.v1"
const CONTRACT_ID = "classification-maps-six-profile-offline-parser-candidate.v1"
const CANONICALIZATION =
    "sorted-typed-length-aware-excluding-artifact-content-sha256.v1"
const EXPECTED_PROFILE_PHYSICAL_SHA256 =
    "9bc1934a66adc19d981b89adf81a2d5f3e8c61ba268c6267fcc968eead2423e2"
const EXPECTED_PROFILE_SEMANTIC_SHA256 =
    "1ea4517532226a4d7026fd5e2061f32a2866e057a73e1064351ffb55ac33c992"
const XLSX_MEDIA_TYPE =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
const FIXTURE_ORIGIN = "SYNTHETIC_NO_URL_ATTRIBUTION"
const PART_NAMES = (
    "xl/workbook.xml",
    "xl/_rels/workbook.xml.rels",
    "xl/worksheets/sheet1.xml",
)
const OFFICIAL_FIXTURE_OBJECT_IDS = (
    "bea_summary_use_2024",
    "bea_summary_make_2024",
    "bea_industry_commodity_naics_concordance",
    "naics_2017_structure",
    "naics_2017_to_2022_concordance",
    "naics_2022_structure",
)
const RESULT_OBJECT_ORDER = (
    "bea_summary_use_2024",
    "bea_summary_make_2024",
    "bea_industry_commodity_naics_concordance",
    "beforeit_bea71_model_bridge",
    "naics_2017_structure",
    "naics_2017_to_2022_concordance",
    "naics_2022_structure",
)
const PROFILE_IDS = (
    "bea_summary_codes",
    "bea_industry_commodity_naics_concordance",
    "beforeit_bea71_model_bridge",
    "naics_2017",
    "naics_2017_to_2022",
    "naics_2022",
)
const EXPECTED_SELECTORS = (
    "BEA:InputOutput:Year=2024:summary_industry_and_commodity_code_lists:71_source_industries,71_source_commodities,Other,Used",
    "BEA:InputOutputClassification:member=BEA-Industry-and-Commodity-Codes-and-NAICS-Concordance.xlsx:publication_path=2023-10:full_published_industry_and_commodity_code_to_NAICS_definitions=true",
    "BEFOREIT:repository:scripts/us/bea71.toml:sha256=2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f:71_to_68_retail_Other_Used_QCEW_SUSB_fixed_asset_concordance",
    "CENSUS:NAICS:2017:official_structure",
    "CENSUS:NAICS:2017_to_2022:official_concordance",
    "CENSUS:NAICS:2022:official_structure",
)
const EXPECTED_PROFILE_OBJECT_IDS = (
    ("bea_summary_use_2024", "bea_summary_make_2024"),
    ("bea_industry_commodity_naics_concordance",),
    ("beforeit_bea71_model_bridge",),
    ("naics_2017_structure",),
    ("naics_2017_to_2022_concordance",),
    ("naics_2022_structure",),
)
const EXPECTED_PARSER_CONTRACTS = (
    "BEA_SUMMARY_AXIS_V1",
    "BEA_TO_NAICS_CONCORDANCE_V1",
    "BEFOREIT_BEA71_TOML_V1",
    "NAICS_STRUCTURE_V1",
    "NAICS_CONCORDANCE_V1",
    "NAICS_STRUCTURE_V1",
)
const EXPECTED_DIRECTIONS = (
    "SHARED_USE_MAKE_AXIS_EQUALITY",
    "BEA_TO_NAICS",
    "BEA71_TO_BEFOREIT68_WITH_TYPED_AUXILIARY_MAPPINGS",
    "NAICS_2017_HIERARCHY",
    "NAICS_2017_TO_NAICS_2022",
    "NAICS_2022_HIERARCHY",
)
const EXPECTED_SOURCE_PINS = (
    (
        "prospective_v2_module",
        "scripts/us/forecasting/vintages/prospective/USProspectiveAcquisitionContractV2.jl",
        "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379",
    ),
    (
        "prospective_v2_contract",
        "scripts/us/forecasting/vintages/prospective/prospective_2026q3_contract_v2.toml",
        "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f",
    ),
    (
        "common_origin_v4_module",
        "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/USCommonOriginAcquisitionV4.jl",
        "0f4c248950ebee59d1e6b5882db6516cbb539f9e54c7dfbb6b53fe0f7a5f6b4e",
    ),
    (
        "common_origin_v4_policy",
        "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/common_origin_acquisition_v4_policy.toml",
        "84e74d236f0e0ac781a482b996be95fceefe56f2a349be089b51054c3edd8834",
    ),
    (
        "after_redefinitions_adapter_module",
        "scripts/us/forecasting/vintages/bea_industry/after_redefinitions_2025_adapter_v1/USBEAAfterRedefinitions2025AdapterV1.jl",
        "11be31c23033593c140d056093b82752ffe151d185ec88f27261e4e476dc4018",
    ),
    (
        "after_redefinitions_profile",
        "scripts/us/forecasting/vintages/bea_industry/after_redefinitions_2025_adapter_v1/bea_after_redefinitions_2025_profile_v1.toml",
        "57c71a1d9a1a8f4ecad7fbc4dbc284590792aa3b2966388bf138397dc0e10d11",
    ),
    (
        "beforeit_bea71_model_bridge",
        "scripts/us/bea71.toml",
        "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f",
    ),
    (
        "current_inventory",
        "scripts/us/forecasting/vintages/current_inventory.toml",
        "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae",
    ),
)
const SUMMARY_CODES = (
    "111CA", "113FF", "211", "212", "213", "22", "23", "321", "327",
    "331", "332", "333", "334", "335", "3361MV", "3364OT", "337",
    "339", "311FT", "313TT", "315AL", "322", "323", "324", "325",
    "326", "42", "441", "445", "452", "4A0", "481", "482", "483",
    "484", "485", "486", "487OS", "493", "511", "512", "513", "514",
    "521CI", "523", "524", "525", "HS", "ORE", "532RL", "5411", "5415",
    "5412OP", "55", "561", "562", "61", "621", "622", "623", "624",
    "711AS", "713", "721", "722", "81", "GFGD", "GFGN", "GFE", "GSLG",
    "GSLE",
)
const MODEL_CODES = (
    "111CA", "113FF", "211", "212", "213", "22", "23", "311FT", "313TT",
    "315AL", "321", "322", "323", "324", "325", "326", "327", "331",
    "332", "333", "334", "335", "3361MV", "3364OT", "337", "339", "42",
    "481", "482", "483", "484", "485", "486", "487OS", "493", "4A0",
    "511", "512", "513", "514", "521CI", "523", "524", "525", "532RL",
    "5411", "5412OP", "5415", "55", "561", "562", "61", "621", "622",
    "623", "624", "711AS", "713", "721", "722", "81", "GFE", "GFGD",
    "GFGN", "GSLE", "GSLG", "HS", "ORE",
)
const SECTOR_CODES = (
    "111CA", "113FF", "211", "212", "213", "22", "23", "311FT", "313TT",
    "315AL", "321", "322", "323", "324", "325", "326", "327", "331",
    "332", "333", "334", "335", "3361MV", "3364OT", "337", "339", "42",
    "4A0", "481", "482", "483", "484", "485", "486", "487OS", "493",
    "511", "512", "513", "514", "521CI", "523", "524", "525", "532RL",
    "5411", "5412OP", "5415", "55", "561", "562", "61", "621", "622",
    "623", "624", "711AS", "713", "721", "722", "81", "GFE", "GFGD",
    "GFGN", "GSLE", "GSLG", "HS", "ORE",
)
const PROHIBITED_ACTIONS = (
    "NETWORK_REQUEST",
    "FILESYSTEM_WRITE",
    "RAW_CAPTURE",
    "ORIGIN_ADMISSION",
    "SOURCE_INVENTORY_MUTATION",
    "FORECAST_EXECUTION",
    "TRUTH_ACCESS",
    "SCORING",
    "MODEL_MAPPING_PROMOTION",
    "CLAIM_PUBLISHER_AUTHENTICATION",
    "CLAIM_CURRENT_ORIGIN",
    "CLAIM_SYNTHETIC_BYTES_CAME_FROM_PLANNED_LOCATOR",
    "REVERSE_CONCORDANCE_IN_PLACE",
    "TREAT_OTHER_OR_USED_AS_NAICS",
)
const RESULT_BLOCKERS = (
    "official_bea_summary_use_workbook_body_missing",
    "official_bea_summary_make_workbook_body_missing",
    "official_bea_naics_concordance_workbook_body_missing",
    "official_naics_2017_structure_workbook_body_missing",
    "official_naics_2017_to_2022_workbook_body_missing",
    "official_naics_2022_structure_workbook_body_missing",
    "provider_physical_layouts_unverified",
    "current_origin_receipts_missing",
    "publisher_authentication_missing",
    "beforeit_bea71_prospective_receipt_missing",
    "classification_leaf_verifier_not_integrated_with_common_origin_v4",
)

struct ClassificationMapError <: Exception
    code::Symbol
    detail::String
end

Base.showerror(io::IO, error::ClassificationMapError) =
    print(io, String(error.code), ": ", error.detail)

_fail(code::Symbol, detail) = throw(ClassificationMapError(code, string(detail)))

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        keys_sorted = sort!(collect(String.(keys(value))))
        write(io, "D", string(length(keys_sorted)), ":")
        for key in keys_sorted
            _canonical_write(io, key)
            _canonical_write(io, value[key])
        end
    elseif value isa AbstractVector || value isa Tuple
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
        _fail(:unsupported_canonical_type, typeof(value))
    end
    return io
end

function _semantic_document(document::AbstractDict)
    copy = deepcopy(document)
    artifact = get(copy, "artifact", nothing)
    artifact isa AbstractDict || _fail(:artifact_missing, "artifact table required")
    pop!(artifact, "content_sha256", nothing)
    return copy
end

function _canonical_sha256(document::AbstractDict; exclude_artifact_hash::Bool = false)
    io = IOBuffer()
    _canonical_write(io, exclude_artifact_hash ? _semantic_document(document) : document)
    return bytes2hex(sha256(take!(io)))
end

profile_semantic_sha256(profile::AbstractDict) =
    _canonical_sha256(profile; exclude_artifact_hash = true)

function _expect_keys(value, expected, code::Symbol)
    value isa AbstractDict || _fail(code, "expected object")
    raw_keys = collect(keys(value))
    all(key -> key isa String, raw_keys) ||
        _fail(code, "all object-member names must be String")
    length(raw_keys) == length(expected) ||
        _fail(code, "duplicate-decoded or extra object-member name")
    actual = Set(String.(raw_keys))
    target = Set(String.(expected))
    actual == target ||
        _fail(code, "expected $(sort!(collect(target))); got $(sort!(collect(actual)))")
    return value
end

function _string(value, code::Symbol; allow_empty::Bool = false)
    value isa AbstractString || _fail(code, "expected String, got $(typeof(value))")
    text = String(value)
    (!allow_empty && isempty(text)) && _fail(code, "empty string forbidden")
    isvalid(text) || _fail(code, "invalid UTF-8")
    return text
end

function _int(value, code::Symbol)
    typeof(value) === Int || _fail(code, "expected Int, got $(typeof(value))")
    return value
end

function _bool(value, expected::Bool, code::Symbol)
    value isa Bool && value === expected || _fail(code, "expected $expected")
    return value
end

function _hash(value, code::Symbol)
    text = _string(value, code)
    ncodeunits(text) == 64 || _fail(code, "expected 64 lowercase hex characters")
    all(character -> character in '0':'9' || character in 'a':'f', text) ||
        _fail(code, "expected lowercase SHA-256")
    return text
end

function _source_path(relative, code::Symbol)
    path_text = _string(relative, code)
    isabspath(path_text) && _fail(code, "absolute source path forbidden")
    normpath(path_text) == path_text || _fail(code, "source path must be normalized")
    startswith(path_text, "../") && _fail(code, "path escapes repository")
    path = normpath(joinpath(REPOSITORY_ROOT, path_text))
    startswith(path, REPOSITORY_ROOT * "/") || _fail(code, "path escapes repository")
    relative_parts = split(path_text, '/')
    candidate = REPOSITORY_ROOT
    for part in relative_parts
        part in ("", ".", "..") && _fail(code, "non-canonical component")
        candidate = joinpath(candidate, part)
        ispath(candidate) || _fail(code, "missing source $path_text")
        islink(candidate) && _fail(code, "symbolic path component forbidden")
    end
    isfile(path) || _fail(code, "source must be a regular file")
    stat(path).nlink == 1 || _fail(code, "hard-linked source forbidden")
    realpath(path) == path || _fail(code, "source path must be canonical")
    return path
end

function _same_file_identity(left, right)
    return left.device == right.device && left.inode == right.inode
end

function _same_file_snapshot(left, right)
    return _same_file_identity(left, right) && left.mode == right.mode &&
        left.nlink == right.nlink && left.size == right.size &&
        isequal(left.mtime, right.mtime) && isequal(left.ctime, right.ctime)
end

function _read_stable_source(
        relative,
        code::Symbol;
        maximum_bytes::Int = 16_777_216,
    )
    path = _source_path(relative, code)
    path_before = lstat(path)
    isfile(path_before) || _fail(code, "source must be a regular file")
    path_before.nlink == 1 || _fail(code, "hard-linked source forbidden")
    bytes, digest = open(path, "r") do io
        handle_before = stat(io)
        isfile(handle_before) || _fail(code, "opened source must be a regular file")
        handle_before.nlink == 1 || _fail(code, "opened hard-linked source forbidden")
        _same_file_snapshot(path_before, handle_before) ||
            _fail(:source_unstable, "$relative changed between path check and open")
        handle_before.size <= maximum_bytes ||
            _fail(:source_size, "$relative exceeds the stable-read byte cap")

        first_bytes = read(io)
        after_first_read = stat(io)
        _same_file_snapshot(handle_before, after_first_read) ||
            _fail(:source_unstable, "$relative changed during first read")
        seekstart(io)
        second_bytes = read(io)
        handle_after = stat(io)
        _same_file_snapshot(after_first_read, handle_after) ||
            _fail(:source_unstable, "$relative changed during replay read")
        length(first_bytes) == handle_after.size ||
            _fail(:source_unstable, "$relative byte count differs from file metadata")
        first_digest = bytes2hex(sha256(first_bytes))
        second_digest = bytes2hex(sha256(second_bytes))
        first_digest == second_digest && first_bytes == second_bytes ||
            _fail(:source_unstable, "$relative replay bytes or hashes differ")
        return first_bytes, first_digest
    end

    _source_path(relative, code) == path ||
        _fail(:source_unstable, "$relative resolved path changed after read")
    path_after = lstat(path)
    _same_file_snapshot(path_before, path_after) ||
        _fail(:source_unstable, "$relative path identity changed after read")
    return (path = path, bytes = bytes, sha256 = digest)
end

function _validate_source_pins(pins)
    pins isa AbstractVector || _fail(:source_pins, "expected array")
    length(pins) == length(EXPECTED_SOURCE_PINS) ||
        _fail(:source_pins, "source pin count mismatch")
    for (index, expected) in enumerate(EXPECTED_SOURCE_PINS)
        pin = _expect_keys(pins[index], ("pin_id", "path", "sha256"), :source_pin_shape)
        tuple = (pin["pin_id"], pin["path"], pin["sha256"])
        tuple == expected || _fail(:source_pin, "source pin $index drift")
        source = _read_stable_source(pin["path"], :source_pin_path)
        source.sha256 == pin["sha256"] ||
            _fail(:source_pin_hash, "$(pin["pin_id"]) differs from frozen SHA-256")
    end
    return true
end

function _validate_profile_document(profile::AbstractDict)
    _expect_keys(
        profile,
        (
            "prohibited_actions", "artifact", "scope", "limits", "semantics",
            "profiles", "objects", "source_pins", "gates",
        ),
        :profile_shape,
    )
    profile["prohibited_actions"] == collect(PROHIBITED_ACTIONS) ||
        _fail(:prohibited_actions, "exact prohibited action list drift")
    artifact = _expect_keys(
        profile["artifact"],
        ("schema_version", "contract_id", "status", "canonicalization", "content_sha256"),
        :artifact_shape,
    )
    artifact["schema_version"] == PROFILE_SCHEMA || _fail(:profile_schema, "schema drift")
    artifact["contract_id"] == CONTRACT_ID || _fail(:contract_id, "contract drift")
    artifact["status"] == "CANNOT_RUN" || _fail(:status, "must remain CANNOT_RUN")
    artifact["canonicalization"] == CANONICALIZATION ||
        _fail(:canonicalization, "canonicalization drift")
    _hash(artifact["content_sha256"], :profile_semantic_hash)
    semantic_hash = profile_semantic_sha256(profile)
    semantic_hash == artifact["content_sha256"] ||
        _fail(:profile_semantic_hash, "semantic self-hash mismatch")
    EXPECTED_PROFILE_SEMANTIC_SHA256 == "TO_BE_FROZEN" ||
        semantic_hash == EXPECTED_PROFILE_SEMANTIC_SHA256 ||
        _fail(:profile_frozen_semantic_hash, "coordinated restamp rejected")

    scope = _expect_keys(
        profile["scope"],
        (
            "requirement_id", "source_id", "capture_id", "profile_count",
            "object_count", "official_workbook_count", "shared_projection_object_count",
            "repository_local_object_count", "offline_validation_only",
            "synthetic_fixture_only", "network_action_count",
            "filesystem_write_action_count", "current_qualified_count",
            "official_workbook_bodies_present", "current_origin_receipts_present",
            "provider_physical_layouts_evidenced",
            "synthetic_fixture_is_provider_layout_claim",
            "fixture_bytes_attributed_to_planned_locators",
            "local_bridge_exact_bytes_present",
            "local_bridge_prospective_receipt_present", "common_origin_v4_integration",
            "claim_ceiling",
        ),
        :scope_shape,
    )
    scope["requirement_id"] == "classification_maps" || _fail(:scope, "requirement drift")
    scope["source_id"] == "official_classification_maps" || _fail(:scope, "source drift")
    scope["capture_id"] == "final_structural_pre_origin" || _fail(:scope, "capture drift")
    for (key, expected) in (
            "profile_count" => 6,
            "object_count" => 7,
            "official_workbook_count" => 6,
            "shared_projection_object_count" => 2,
            "repository_local_object_count" => 1,
            "network_action_count" => 0,
            "filesystem_write_action_count" => 0,
            "current_qualified_count" => 0,
        )
        _int(scope[key], :scope_count) == expected || _fail(:scope_count, "$key drift")
    end
    for key in ("offline_validation_only", "synthetic_fixture_only", "local_bridge_exact_bytes_present")
        _bool(scope[key], true, :scope_boundary)
    end
    for key in (
            "official_workbook_bodies_present", "current_origin_receipts_present",
            "provider_physical_layouts_evidenced",
            "synthetic_fixture_is_provider_layout_claim",
            "fixture_bytes_attributed_to_planned_locators",
            "local_bridge_prospective_receipt_present", "common_origin_v4_integration",
        )
        _bool(scope[key], false, :scope_boundary)
    end
    scope["claim_ceiling"] ==
        "OFFLINE_SYNTHETIC_PARSER_AND_LOCAL_FIXITY_RECEIPT_ONLY_NO_OFFICIAL_BODY_OR_CURRENT_ORIGIN" ||
        _fail(:claim_ceiling, "claim ceiling drift")

    limits = _expect_keys(
        profile["limits"],
        (
            "maximum_part_bytes", "maximum_workbook_bytes", "maximum_xml_nodes",
            "maximum_xml_depth", "maximum_xml_attributes_per_node", "maximum_rows",
            "maximum_columns", "maximum_cell_bytes", "maximum_bridge_bytes",
        ),
        :limits_shape,
    )
    expected_limits = (
        8_388_608, 33_554_432, 250_000, 64, 32, 100_000, 64, 1_048_576,
        1_048_576,
    )
    for (index, key) in enumerate(
            (
                "maximum_part_bytes", "maximum_workbook_bytes", "maximum_xml_nodes",
                "maximum_xml_depth", "maximum_xml_attributes_per_node", "maximum_rows",
                "maximum_columns", "maximum_cell_bytes", "maximum_bridge_bytes",
            )
        )
        _int(limits[key], :limit_type) == expected_limits[index] ||
            _fail(:limit_value, "$key drift")
    end

    semantics = _expect_keys(
        profile["semantics"],
        (
            "bea_concordance_direction", "naics_concordance_direction",
            "inverse_policy", "cardinality_policy", "row_preservation_policy",
            "summary_axis_policy", "summary_industry_count",
            "summary_commodity_count_including_special_accounts",
            "summary_special_accounts", "special_account_policy", "range_code_policy",
            "fixture_origin_label", "ooxml_fixture_policy", "local_bridge_policy",
        ),
        :semantics_shape,
    )
    semantics["bea_concordance_direction"] == "BEA_TO_NAICS" ||
        _fail(:direction, "BEA direction drift")
    semantics["naics_concordance_direction"] == "NAICS_2017_TO_NAICS_2022" ||
        _fail(:direction, "NAICS direction drift")
    semantics["inverse_policy"] == "SEPARATE_DERIVATION_ONLY_NEVER_IN_PLACE_REVERSAL" ||
        _fail(:inverse_policy, "inverse policy drift")
    semantics["cardinality_policy"] ==
        "DERIVE_FROM_COMPLETE_ORDERED_SOURCE_TARGET_PAIRS" ||
        _fail(:cardinality_policy, "cardinality policy drift")
    semantics["row_preservation_policy"] ==
        "PRESERVE_CODES_TITLES_ORDER_NOTES_AND_EXPLICIT_BLANKS" ||
        _fail(:row_policy, "row policy drift")
    semantics["summary_axis_policy"] ==
        "SHARED_2024_USE_MAKE_OBJECT_PROJECTIONS_MUST_MATCH_EXACTLY" ||
        _fail(:summary_axis_policy, "summary axis policy drift")
    _int(semantics["summary_industry_count"], :summary_count) == 71 ||
        _fail(:summary_count, "industry count drift")
    _int(semantics["summary_commodity_count_including_special_accounts"], :summary_count) == 73 ||
        _fail(:summary_count, "commodity count drift")
    semantics["summary_special_accounts"] == ["Other", "Used"] ||
        _fail(:special_accounts, "special account order drift")
    semantics["special_account_policy"] ==
        "BEA_SPECIAL_ACCOUNTS_NOT_NAICS_INDUSTRIES_OR_MISSINGNESS_TOKENS" ||
        _fail(:special_account_policy, "special account policy drift")
    semantics["range_code_policy"] ==
        "PRESERVE_RANGE_CODES_AS_STRINGS_NEVER_NUMERICALLY_COERCE" ||
        _fail(:range_policy, "range policy drift")
    semantics["fixture_origin_label"] == FIXTURE_ORIGIN ||
        _fail(:fixture_origin, "fixture origin drift")
    semantics["ooxml_fixture_policy"] ==
        "INDEPENDENT_SYNTHETIC_PARTS_NOT_ZIP_OR_PROVIDER_LAYOUT_EVIDENCE" ||
        _fail(:ooxml_policy, "OOXML policy drift")
    semantics["local_bridge_policy"] ==
        "REPOSITORY_AUTHORED_MAPPING_NOT_OFFICIAL_BEA_OR_CENSUS_CROSSWALK" ||
        _fail(:bridge_policy, "bridge policy drift")

    profiles = profile["profiles"]
    profiles isa AbstractVector && length(profiles) == 6 ||
        _fail(:profiles, "exact six-profile set required")
    for index in 1:6
        entry = _expect_keys(
            profiles[index],
            ("profile_id", "selector", "object_ids", "parser_contract", "direction"),
            :profile_entry_shape,
        )
        entry["profile_id"] == PROFILE_IDS[index] || _fail(:profile_order, index)
        entry["selector"] == EXPECTED_SELECTORS[index] || _fail(:selector, index)
        Tuple(entry["object_ids"]) == EXPECTED_PROFILE_OBJECT_IDS[index] ||
            _fail(:profile_objects, index)
        entry["parser_contract"] == EXPECTED_PARSER_CONTRACTS[index] ||
            _fail(:parser_contract, index)
        entry["direction"] == EXPECTED_DIRECTIONS[index] || _fail(:direction, index)
    end

    objects = profile["objects"]
    objects isa AbstractVector && length(objects) == 7 ||
        _fail(:objects, "exact seven-object catalog required")
    expected_object_keys = (
        "object_id", "source_class", "planned_locator", "media_type", "fixture_kind",
        "evidence_status", "official", "official_body_present", "local_bytes_present",
        "current_origin_receipt_present", "provider_layout_evidenced",
        "shared_parent_profile_sha256", "shared_parent_object_sha256",
        "repository_path", "repository_sha256",
    )
    for (index, object) in enumerate(objects)
        _expect_keys(object, expected_object_keys, :object_shape)
        object["object_id"] == RESULT_OBJECT_ORDER[index] || _fail(:object_order, index)
        object["current_origin_receipt_present"] === false ||
            _fail(:origin_receipt, "must remain false")
        if object["object_id"] == "beforeit_bea71_model_bridge"
            object["official"] === false || _fail(:bridge_official, "local bridge is not official")
            object["local_bytes_present"] === true || _fail(:bridge_bytes, "local bytes required")
            object["repository_path"] == "scripts/us/bea71.toml" || _fail(:bridge_path, "path drift")
            object["repository_sha256"] == EXPECTED_SOURCE_PINS[7][3] ||
                _fail(:bridge_hash, "hash drift")
            object["media_type"] == "application/toml" || _fail(:bridge_media, "media drift")
            object["fixture_kind"] == "REPOSITORY_LOCAL_EXACT_TOML_RECEIPT" ||
                _fail(:bridge_kind, "kind drift")
            object["provider_layout_evidenced"] === true ||
                _fail(:bridge_layout, "repository TOML layout must be exact")
        else
            object["official"] === true || _fail(:official_object, index)
            object["official_body_present"] === false || _fail(:official_body, index)
            object["local_bytes_present"] === false || _fail(:official_body, index)
            object["provider_layout_evidenced"] === false || _fail(:provider_layout, index)
            object["media_type"] == XLSX_MEDIA_TYPE || _fail(:media_type, index)
            object["fixture_kind"] == "SYNTHETIC_OOXML_PARTS_ONLY" ||
                _fail(:fixture_kind, index)
        end
    end
    objects[1]["shared_parent_profile_sha256"] == EXPECTED_SOURCE_PINS[6][3] ||
        _fail(:shared_parent, "use parent profile drift")
    objects[2]["shared_parent_profile_sha256"] == EXPECTED_SOURCE_PINS[6][3] ||
        _fail(:shared_parent, "make parent profile drift")
    objects[1]["shared_parent_object_sha256"] ==
        "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7" ||
        _fail(:shared_parent, "use object hash drift")
    objects[2]["shared_parent_object_sha256"] ==
        "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6" ||
        _fail(:shared_parent, "make object hash drift")

    _validate_source_pins(profile["source_pins"])
    gates = _expect_keys(
        profile["gates"],
        (
            "official_bodies_captured", "current_origin_receipts_verified",
            "provider_layouts_verified", "all_profiles_physically_qualified",
            "origin_admissible", "model_mapping_allowed", "forecast_execution_allowed",
            "truth_access_allowed", "scoring_allowed", "inventory_mutation_allowed",
            "production_allowed", "ready",
        ),
        :gates_shape,
    )
    all(value -> value isa Bool && value === false, values(gates)) ||
        _fail(:gate, "all gates must remain false")
    return profile
end

function validate_profile()
    source = _read_stable_source(
        relpath(PROFILE_PATH, REPOSITORY_ROOT),
        :profile_path,
        maximum_bytes = 1_048_576,
    )
    EXPECTED_PROFILE_PHYSICAL_SHA256 == "TO_BE_FROZEN" ||
        source.sha256 == EXPECTED_PROFILE_PHYSICAL_SHA256 ||
        _fail(:profile_physical_hash, "frozen profile bytes differ")
    text = String(copy(source.bytes))
    isvalid(text) || _fail(:profile_utf8, "profile must be valid UTF-8")
    profile = try
        TOML.parse(text)
    catch error
        _fail(:profile_toml, sprint(showerror, error))
    end
    return _validate_profile_document(profile)
end

mutable struct _XMLNode
    name::String
    attributes::Dict{String, String}
    children::Vector{_XMLNode}
    text::String
end

function _xml_scalar(codepoint::Int, code::Symbol)
    (
        codepoint == 9 || codepoint == 10 || codepoint == 13 ||
            0x20 <= codepoint <= 0xd7ff || 0xe000 <= codepoint <= 0xfffd ||
            0x00010000 <= codepoint <= 0x0010ffff
    ) ||
        _fail(code, "invalid XML 1.0 scalar U+$(uppercase(string(codepoint; base = 16)))")
    return Char(codepoint)
end

function _xml_decode(value::String, code::Symbol)
    normalized = replace(value, "\r\n" => "\n", '\r' => '\n')
    output = IOBuffer()
    position = firstindex(normalized)
    while position <= lastindex(normalized)
        character = normalized[position]
        if character != '&'
            write(output, _xml_scalar(Int(character), code))
            position = nextind(normalized, position)
            continue
        end
        terminal = findnext(';', normalized, nextind(normalized, position))
        terminal === nothing && _fail(code, "unterminated XML entity")
        token = normalized[nextind(normalized, position):prevind(normalized, terminal)]
        if token == "amp"
            write(output, '&')
        elseif token == "lt"
            write(output, '<')
        elseif token == "gt"
            write(output, '>')
        elseif token == "quot"
            write(output, '"')
        elseif token == "apos"
            write(output, '\'')
        elseif startswith(token, "#x")
            length(token) > 2 || _fail(code, "empty hexadecimal character reference")
            point = tryparse(Int, token[3:end]; base = 16)
            point === nothing && _fail(code, "invalid hexadecimal character reference")
            write(output, _xml_scalar(point, code))
        elseif startswith(token, "#")
            length(token) > 1 || _fail(code, "empty decimal character reference")
            point = tryparse(Int, token[2:end]; base = 10)
            point === nothing && _fail(code, "invalid decimal character reference")
            write(output, _xml_scalar(point, code))
        else
            _fail(code, "unsupported XML entity &$token;")
        end
        position = nextind(normalized, terminal)
    end
    return String(take!(output))
end

_name_start(byte::UInt8) =
    byte == UInt8('_') || byte in UInt8('A'):UInt8('Z') || byte in UInt8('a'):UInt8('z')
_name_continue(byte::UInt8) =
    _name_start(byte) || byte in UInt8('0'):UInt8('9') ||
    byte in (UInt8('-'), UInt8('.'), UInt8(':'))
_space(byte::UInt8) = byte in (UInt8(' '), UInt8('\t'), UInt8('\n'), UInt8('\r'))

function _parse_tag(value::String, code::Symbol)
    bytes = Vector{UInt8}(codeunits(value))
    isempty(bytes) && _fail(code, "empty tag")
    position = 1
    _name_start(bytes[position]) || _fail(code, "invalid element name")
    start = position
    position += 1
    while position <= length(bytes) && _name_continue(bytes[position])
        position += 1
    end
    name = String(bytes[start:(position - 1)])
    attributes = Dict{String, String}()
    while true
        while position <= length(bytes) && _space(bytes[position])
            position += 1
        end
        position > length(bytes) && break
        _name_start(bytes[position]) || _fail(code, "invalid attribute name")
        start = position
        position += 1
        while position <= length(bytes) && _name_continue(bytes[position])
            position += 1
        end
        attribute_name = String(bytes[start:(position - 1)])
        while position <= length(bytes) && _space(bytes[position])
            position += 1
        end
        position <= length(bytes) && bytes[position] == UInt8('=') ||
            _fail(code, "attribute equals sign required")
        position += 1
        while position <= length(bytes) && _space(bytes[position])
            position += 1
        end
        position <= length(bytes) && bytes[position] == UInt8('"') ||
            _fail(code, "double-quoted attribute required")
        position += 1
        start = position
        while position <= length(bytes) && bytes[position] != UInt8('"')
            bytes[position] == UInt8('<') && _fail(code, "less-than in attribute")
            position += 1
        end
        position <= length(bytes) || _fail(code, "unterminated attribute")
        attribute_value = String(bytes[start:(position - 1)])
        position += 1
        haskey(attributes, attribute_name) &&
            _fail(code, "duplicate attribute $attribute_name")
        attributes[attribute_name] = _xml_decode(attribute_value, code)
        length(attributes) <= 32 || _fail(code, "attribute count exceeds cap")
    end
    return name, attributes
end

function _parse_xml(payload, location::String)
    bytes = try
        Vector{UInt8}(payload)
    catch
        _fail(:xml_type, "$location must be byte-like")
    end
    length(bytes) <= 8_388_608 || _fail(:xml_size, "$location exceeds part cap")
    isvalid(String, bytes) || _fail(:xml_utf8, "$location must be UTF-8")
    text = String(copy(bytes))
    startswith(text, '\ufeff') && _fail(:xml_bom, "$location BOM is not part of synthetic schema")
    for character in text
        _xml_scalar(Int(character), :xml_scalar)
    end
    data = Vector{UInt8}(codeunits(text))
    stack = _XMLNode[]
    root = nothing
    nodes = 0
    position = 1
    while position <= length(data)
        opening = findnext(==(UInt8('<')), data, position)
        opening === nothing && _fail(:xml_syntax, "$location has trailing text without close")
        if opening > position
            fragment = String(data[position:(opening - 1)])
            occursin("]]>", fragment) &&
                _fail(:xml_text, "$location contains raw ]]> in character data")
            decoded = _xml_decode(fragment, :xml_text)
            if isempty(stack)
                all(isspace, decoded) || _fail(:xml_syntax, "$location text outside root")
            else
                stack[end].text *= decoded
            end
        end
        closing = opening + 1
        quoted = false
        while closing <= length(data)
            byte = data[closing]
            byte == UInt8('"') && (quoted = !quoted)
            byte == UInt8('>') && !quoted && break
            closing += 1
        end
        closing <= length(data) || _fail(:xml_syntax, "$location unterminated tag")
        raw = String(data[(opening + 1):(closing - 1)])
        isempty(raw) && _fail(:xml_syntax, "$location empty tag")
        if startswith(raw, "!") || startswith(raw, "?")
            _fail(:xml_declaration, "$location declarations, entities, comments, and PIs forbidden")
        elseif startswith(raw, "/")
            name = raw[2:end]
            isempty(name) && _fail(:xml_syntax, "$location empty closing tag")
            any(isspace, name) && _fail(:xml_syntax, "$location whitespace in closing tag")
            isempty(stack) && _fail(:xml_syntax, "$location unmatched closing tag")
            stack[end].name == name ||
                _fail(:xml_syntax, "$location closes $name while $(stack[end].name) is open")
            pop!(stack)
        else
            self_closing = endswith(raw, "/")
            content = self_closing ? raw[1:(end - 1)] : raw
            name, attributes = _parse_tag(content, :xml_tag)
            node = _XMLNode(name, attributes, _XMLNode[], "")
            nodes += 1
            nodes <= 250_000 || _fail(:xml_nodes, "$location node cap exceeded")
            if isempty(stack)
                root === nothing || _fail(:xml_root, "$location has multiple roots")
                root = node
            else
                push!(stack[end].children, node)
            end
            if !self_closing
                push!(stack, node)
                length(stack) <= 64 || _fail(:xml_depth, "$location depth cap exceeded")
            end
        end
        position = closing + 1
        if isempty(stack) && root !== nothing && position <= length(data)
            remainder = String(data[position:end])
            all(isspace, remainder) || _fail(:xml_syntax, "$location content after root")
            position = length(data) + 1
        end
    end
    root === nothing && _fail(:xml_root, "$location lacks root")
    isempty(stack) || _fail(:xml_syntax, "$location has unclosed tags")
    return root
end

function _whitespace(node::_XMLNode, code::Symbol)
    all(isspace, node.text) || _fail(code, "unexpected structural text")
    return true
end

function _children(node::_XMLNode, name::String)
    return [child for child in node.children if child.name == name]
end

function _only_child(node::_XMLNode, name::String, code::Symbol)
    matches = _children(node, name)
    length(matches) == 1 || _fail(code, "expected exactly one $name child")
    return only(matches)
end

function _parse_workbook(root::_XMLNode)
    root.name == "workbook" || _fail(:workbook_root, root.name)
    isempty(root.attributes) || _fail(:workbook_shape, "root attributes forbidden in synthetic schema")
    _whitespace(root, :workbook_shape)
    length(root.children) == 1 || _fail(:workbook_shape, "only sheets child allowed")
    sheets = _only_child(root, "sheets", :workbook_shape)
    isempty(sheets.attributes) || _fail(:workbook_shape, "sheets attributes forbidden")
    _whitespace(sheets, :workbook_shape)
    length(sheets.children) == 1 || _fail(:workbook_shape, "exactly one sheet required")
    sheet = only(sheets.children)
    sheet.name == "sheet" || _fail(:workbook_shape, "sheet declaration required")
    _whitespace(sheet, :workbook_shape)
    isempty(sheet.children) || _fail(:workbook_shape, "sheet must be empty")
    _expect_keys(sheet.attributes, ("name", "sheetId", "r:id"), :sheet_attributes)
    sheet.attributes["name"] == "ClassificationMap" || _fail(:sheet_name, "name drift")
    sheet.attributes["sheetId"] == "1" || _fail(:sheet_id, "sheetId drift")
    sheet.attributes["r:id"] == "rId1" || _fail(:sheet_relationship, "relationship drift")
    return sheet.attributes["name"]
end

function _parse_relationships(root::_XMLNode)
    root.name == "Relationships" || _fail(:relationships_root, root.name)
    isempty(root.attributes) || _fail(:relationships_shape, "root attributes forbidden")
    _whitespace(root, :relationships_shape)
    length(root.children) == 1 || _fail(:relationships_shape, "exactly one relationship required")
    relationship = only(root.children)
    relationship.name == "Relationship" || _fail(:relationships_shape, "Relationship required")
    isempty(relationship.children) || _fail(:relationships_shape, "Relationship must be empty")
    _whitespace(relationship, :relationships_shape)
    _expect_keys(relationship.attributes, ("Id", "Type", "Target"), :relationship_attributes)
    relationship.attributes["Id"] == "rId1" || _fail(:relationship_id, "Id drift")
    relationship.attributes["Type"] ==
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ||
        _fail(:relationship_type, "worksheet relationship required")
    relationship.attributes["Target"] == "worksheets/sheet1.xml" ||
        _fail(:relationship_target, "target drift or traversal")
    return true
end

function _column_number(reference::String)
    isempty(reference) && _fail(:cell_reference, "empty reference")
    position = firstindex(reference)
    column = 0
    while position <= lastindex(reference) && isuppercase(reference[position])
        column = 26 * column + Int(reference[position] - 'A') + 1
        position = nextind(reference, position)
    end
    column > 0 || _fail(:cell_reference, "column letters required")
    position <= lastindex(reference) || _fail(:cell_reference, "row digits required")
    row_text = reference[position:end]
    all(character -> character in '0':'9', row_text) ||
        _fail(:cell_reference, "invalid row digits")
    startswith(row_text, "0") && _fail(:cell_reference, "leading-zero row forbidden")
    row = tryparse(Int, row_text)
    row === nothing && _fail(:cell_reference, "row overflow")
    return column, row
end

function _cell_text(cell::_XMLNode)
    _expect_keys(cell.attributes, ("r", "t"), :cell_attributes)
    cell.attributes["t"] == "inlineStr" || _fail(:cell_type, "only explicit inline strings allowed")
    _whitespace(cell, :cell_shape)
    length(cell.children) == 1 || _fail(:cell_shape, "exactly one is child required")
    inline = _only_child(cell, "is", :cell_shape)
    isempty(inline.attributes) || _fail(:cell_shape, "is attributes forbidden")
    _whitespace(inline, :cell_shape)
    length(inline.children) == 1 || _fail(:cell_shape, "exactly one t child required")
    text = _only_child(inline, "t", :cell_shape)
    _expect_keys(text.attributes, ("xml:space",), :text_attributes)
    text.attributes["xml:space"] == "preserve" || _fail(:text_space, "preserve required")
    isempty(text.children) || _fail(:cell_shape, "rich text forbidden")
    ncodeunits(text.text) <= 1_048_576 || _fail(:cell_size, "cell exceeds cap")
    return text.text
end

function _parse_worksheet(root::_XMLNode)
    root.name == "worksheet" || _fail(:worksheet_root, root.name)
    isempty(root.attributes) || _fail(:worksheet_shape, "root attributes forbidden")
    _whitespace(root, :worksheet_shape)
    length(root.children) == 1 || _fail(:worksheet_shape, "only sheetData child allowed")
    data = _only_child(root, "sheetData", :worksheet_shape)
    isempty(data.attributes) || _fail(:worksheet_shape, "sheetData attributes forbidden")
    _whitespace(data, :worksheet_shape)
    isempty(data.children) && _fail(:worksheet_rows, "at least a header row required")
    length(data.children) <= 100_000 || _fail(:worksheet_rows, "row cap exceeded")
    rows = Vector{Vector{String}}()
    expected_width = 0
    for (row_index, row) in enumerate(data.children)
        row.name == "row" || _fail(:worksheet_shape, "only row children allowed")
        _expect_keys(row.attributes, ("r",), :row_attributes)
        row.attributes["r"] == string(row_index) || _fail(:row_order, "row coordinate drift")
        _whitespace(row, :row_shape)
        isempty(row.children) && _fail(:row_shape, "empty physical row forbidden")
        length(row.children) <= 64 || _fail(:column_count, "column cap exceeded")
        values = String[]
        seen = Set{String}()
        for (column_index, cell) in enumerate(row.children)
            cell.name == "c" || _fail(:row_shape, "only c children allowed")
            reference = get(cell.attributes, "r", "")
            reference in seen && _fail(:duplicate_cell, reference)
            push!(seen, reference)
            column, physical_row = _column_number(reference)
            column == column_index || _fail(:cell_order, "missing, duplicate, or reordered cell")
            physical_row == row_index || _fail(:cell_reference, "row mismatch")
            push!(values, _cell_text(cell))
        end
        if row_index == 1
            expected_width = length(values)
        else
            length(values) == expected_width ||
                _fail(:row_width, "explicit cells, including blanks, required")
        end
        push!(rows, values)
    end
    return rows
end

function _part_vector(parts)
    parts isa AbstractVector || _fail(:parts_type, "parts must be an ordered pair vector")
    length(parts) == length(PART_NAMES) || _fail(:part_count, "exactly three parts required")
    result = Pair{String, Vector{UInt8}}[]
    seen = Set{String}()
    total = 0
    for (index, pair) in enumerate(parts)
        pair isa Pair || _fail(:part_type, "part $index must be Pair")
        name = _string(pair.first, :part_name)
        name == PART_NAMES[index] || _fail(:part_order, "expected $(PART_NAMES[index])")
        name in seen && _fail(:duplicate_part, name)
        push!(seen, name)
        pair.second isa AbstractVector{UInt8} ||
            _fail(:part_payload, "$name must be a byte vector")
        payload = Vector{UInt8}(pair.second)
        length(payload) <= 8_388_608 || _fail(:part_size, "$name exceeds cap")
        total += length(payload)
        total <= 33_554_432 || _fail(:workbook_size, "aggregate part cap exceeded")
        push!(result, name => payload)
    end
    return result
end

function _synthetic_workbook(object, object_id::String)
    _expect_keys(object, ("fixture_kind", "fixture_origin", "media_type", "parts"), :fixture_shape)
    object["fixture_kind"] == "SYNTHETIC_OOXML_PARTS" ||
        _fail(:fixture_kind, "$object_id fixture kind drift")
    object["fixture_origin"] == FIXTURE_ORIGIN ||
        _fail(:fixture_origin, "$object_id cannot be attributed to a URL")
    object["media_type"] == XLSX_MEDIA_TYPE || _fail(:fixture_media, object_id)
    parts = _part_vector(object["parts"])
    _parse_workbook(_parse_xml(parts[1].second, "workbook.xml"))
    _parse_relationships(_parse_xml(parts[2].second, "workbook.xml.rels"))
    rows = _parse_worksheet(_parse_xml(parts[3].second, "sheet1.xml"))
    io = IOBuffer()
    write(io, "beforeit-synthetic-ooxml-parts-subject.v1\0")
    write(io, string(ncodeunits(object_id)), ":", object_id)
    part_receipts = Dict{String, Any}[]
    for (ordinal, pair) in enumerate(parts)
        digest = bytes2hex(sha256(pair.second))
        write(io, string(ncodeunits(pair.first)), ":", pair.first)
        write(io, string(length(pair.second)), ":")
        write(io, pair.second)
        push!(
            part_receipts,
            Dict{String, Any}(
                "ordinal" => ordinal,
                "part_name" => pair.first,
                "byte_count" => length(pair.second),
                "sha256" => digest,
            ),
        )
    end
    return (
        rows = rows,
        object_subject_sha256 = bytes2hex(sha256(take!(io))),
        part_receipts = part_receipts,
    )
end

function _header(rows, expected, code::Symbol)
    isempty(rows) && _fail(code, "header absent")
    rows[1] == collect(expected) ||
        _fail(code, "expected $(collect(expected)); got $(rows[1])")
    length(rows) > 1 || _fail(code, "data rows absent")
    return rows[2:end]
end

function _positive_decimal(value::String, code::Symbol)
    isempty(value) && _fail(code, "empty integer")
    all(character -> character in '0':'9', value) ||
        _fail(code, "expected decimal integer")
    startswith(value, "0") && _fail(code, "leading zero forbidden")
    parsed = tryparse(Int, value)
    parsed === nothing && _fail(code, "integer overflow")
    parsed > 0 || _fail(code, "must be positive")
    return parsed
end

function _exact_code(value::String, code::Symbol; allow_range::Bool = true)
    isempty(value) && _fail(code, "empty code")
    strip(value) == value || _fail(code, "leading or trailing whitespace forbidden")
    value in ("Other", "Used") && _fail(:special_account_as_naics, value)
    all(
        character -> isascii(character) &&
            (isletter(character) || isdigit(character) || character == '-'),
        value,
    ) ||
        _fail(code, "invalid code token")
    !allow_range && occursin('-', value) && _fail(code, "range code forbidden")
    return value
end

function _naics_code(value::String, code::Symbol)
    _exact_code(value, code)
    if length(value) in 2:6 && all(character -> character in '0':'9', value)
        return value
    end
    if ncodeunits(value) == 5 && value[3] == '-' &&
            all(isdigit, value[1:2]) && all(isdigit, value[4:5])
        all(character -> character in '0':'9', value[1:2]) &&
            all(character -> character in '0':'9', value[4:5]) ||
            _fail(code, "range endpoints must be ASCII digits")
        parse(Int, value[1:2]) < parse(Int, value[4:5]) ||
            _fail(code, "range endpoints must ascend")
        return value
    end
    return _fail(code, "NAICS code must be 2-6 digits or an ascending two-digit range")
end

function _title(value::String, code::Symbol)
    isempty(value) && _fail(code, "title must be nonempty")
    strip(value) == value || _fail(code, "title edge whitespace forbidden")
    return value
end

function _consistent_title!(titles::Dict{String, String}, key::String, title::String, code::Symbol)
    if haskey(titles, key)
        titles[key] == title || _fail(code, "conflicting title for $key")
    else
        titles[key] = title
    end
    return title
end

function _cardinalities(rows, source_key, target_key)
    source_targets = Dict{String, Set{String}}()
    target_sources = Dict{String, Set{String}}()
    for row in rows
        source = source_key(row)
        target = target_key(row)
        push!(get!(source_targets, source, Set{String}()), target)
        push!(get!(target_sources, target, Set{String}()), source)
    end
    output = Dict{String, Any}[]
    for row in rows
        source = source_key(row)
        target = target_key(row)
        targets = length(source_targets[source])
        sources = length(target_sources[target])
        relationship = if targets == 1 && sources == 1
            "one_to_one"
        elseif targets > 1 && sources == 1
            "one_to_many"
        elseif targets == 1 && sources > 1
            "many_to_one"
        else
            "many_to_many"
        end
        copy = deepcopy(row)
        copy["source_target_count"] = targets
        copy["target_source_count"] = sources
        copy["relationship"] = relationship
        push!(output, copy)
    end
    return output
end

function _parse_summary_axis(rows, object_id::String)
    body = _header(
        rows,
        ("axis", "ordinal", "code", "title", "account_kind", "note"),
        :summary_header,
    )
    length(body) == 144 || _fail(:summary_row_count, "$object_id requires 144 rows")
    parsed = Dict{String, Any}[]
    axis_ordinals = Dict("Industry" => 0, "Commodity" => 0)
    axis_codes = Dict("Industry" => String[], "Commodity" => String[])
    for row in body
        axis, ordinal_text, raw_code, raw_title, account_kind, note = row
        axis in ("Industry", "Commodity") || _fail(:summary_axis, axis)
        ordinal = _positive_decimal(ordinal_text, :summary_ordinal)
        ordinal == axis_ordinals[axis] + 1 || _fail(:summary_order, "$axis ordinal gap")
        axis_ordinals[axis] = ordinal
        code = _string(raw_code, :summary_code)
        strip(code) == code || _fail(:summary_code, "edge whitespace")
        title = _title(raw_title, :summary_title)
        _string(note, :summary_note; allow_empty = true)
        expected_codes = axis == "Industry" ? SUMMARY_CODES : (SUMMARY_CODES..., "Other", "Used")
        ordinal <= length(expected_codes) || _fail(:summary_order, "too many $axis rows")
        code == expected_codes[ordinal] || _fail(:summary_code, "$axis ordinal $ordinal drift")
        expected_kind = code in ("Other", "Used") ?
            "BEA_SPECIAL_ACCOUNT_NON_NAICS" : "ORDINARY_BEA_SUMMARY"
        account_kind == expected_kind || _fail(:summary_account_kind, "$code kind drift")
        axis == "Industry" && code in ("Other", "Used") &&
            _fail(:special_account_as_industry, code)
        push!(axis_codes[axis], code)
        push!(
            parsed,
            Dict{String, Any}(
                "axis" => axis,
                "ordinal" => ordinal,
                "code" => code,
                "title" => title,
                "account_kind" => account_kind,
                "note" => note,
            ),
        )
    end
    axis_ordinals["Industry"] == 71 || _fail(:summary_count, "industry count")
    axis_ordinals["Commodity"] == 73 || _fail(:summary_count, "commodity count")
    axis_codes["Industry"] == collect(SUMMARY_CODES) || _fail(:summary_industries, "axis drift")
    axis_codes["Commodity"][1:71] == collect(SUMMARY_CODES) ||
        _fail(:summary_commodities, "ordinary axis drift")
    axis_codes["Commodity"][72:73] == ["Other", "Used"] ||
        _fail(:summary_special, "special account order drift")
    return parsed
end

function _parse_bea_concordance(rows)
    body = _header(
        rows,
        ("ordinal", "bea_axis", "bea_code", "bea_title", "naics_code", "naics_title", "note"),
        :bea_concordance_header,
    )
    source_titles = Dict{String, String}()
    target_titles = Dict{String, String}()
    seen_rows = Set{NTuple{6, String}}()
    parsed = Dict{String, Any}[]
    for (index, row) in enumerate(body)
        ordinal_text, axis, raw_bea, raw_bea_title, raw_naics, raw_naics_title, note = row
        ordinal = _positive_decimal(ordinal_text, :bea_concordance_ordinal)
        ordinal == index || _fail(:bea_concordance_order, "ordinal drift")
        axis in ("Industry", "Commodity") || _fail(:bea_axis, axis)
        bea_code = _exact_code(raw_bea, :bea_code)
        naics_code = _naics_code(raw_naics, :naics_code)
        bea_title = _title(raw_bea_title, :bea_title)
        naics_title = _title(raw_naics_title, :naics_title)
        _string(note, :bea_note; allow_empty = true)
        _consistent_title!(source_titles, axis * "\0" * bea_code, bea_title, :bea_title_conflict)
        _consistent_title!(target_titles, naics_code, naics_title, :naics_title_conflict)
        signature = (axis, bea_code, bea_title, naics_code, naics_title, note)
        signature in seen_rows && _fail(:duplicate_mapping_row, "BEA concordance row $index")
        push!(seen_rows, signature)
        push!(
            parsed,
            Dict{String, Any}(
                "ordinal" => ordinal,
                "bea_axis" => axis,
                "bea_code" => bea_code,
                "bea_title" => bea_title,
                "naics_code" => naics_code,
                "naics_title" => naics_title,
                "note" => note,
                "direction" => "BEA_TO_NAICS",
            ),
        )
    end
    return _cardinalities(
        parsed,
        row -> row["bea_axis"] * "\0" * row["bea_code"],
        row -> row["bea_axis"] * "\0" * row["naics_code"],
    )
end

function _expected_naics_level(code::String)
    occursin('-', code) && return 2
    return ncodeunits(code)
end

function _parse_naics_structure(rows, vintage::Int)
    body = _header(rows, ("ordinal", "level", "code", "title", "note"), :naics_header)
    parsed = Dict{String, Any}[]
    seen = Set{String}()
    for (index, row) in enumerate(body)
        ordinal_text, level_text, raw_code, raw_title, note = row
        ordinal = _positive_decimal(ordinal_text, :naics_ordinal)
        ordinal == index || _fail(:naics_order, "ordinal drift")
        level = _positive_decimal(level_text, :naics_level)
        level in 2:6 || _fail(:naics_level, "level must be 2-6")
        code = _naics_code(raw_code, :naics_code)
        level == _expected_naics_level(code) || _fail(:naics_level, "$code level mismatch")
        code in seen && _fail(:duplicate_naics_code, code)
        push!(seen, code)
        title = _title(raw_title, :naics_title)
        _string(note, :naics_note; allow_empty = true)
        push!(
            parsed,
            Dict{String, Any}(
                "ordinal" => ordinal,
                "level" => level,
                "code" => code,
                "title" => title,
                "note" => note,
                "vintage" => vintage,
            ),
        )
    end
    return parsed
end

function _parse_naics_concordance(rows)
    body = _header(
        rows,
        ("ordinal", "2017_code", "2017_title", "2022_code", "2022_title", "note"),
        :naics_concordance_header,
    )
    source_titles = Dict{String, String}()
    target_titles = Dict{String, String}()
    seen_rows = Set{NTuple{5, String}}()
    parsed = Dict{String, Any}[]
    for (index, row) in enumerate(body)
        ordinal_text, raw_source, raw_source_title, raw_target, raw_target_title, note = row
        ordinal = _positive_decimal(ordinal_text, :naics_concordance_ordinal)
        ordinal == index || _fail(:naics_concordance_order, "ordinal drift")
        source = _naics_code(raw_source, :naics_2017_code)
        target = _naics_code(raw_target, :naics_2022_code)
        source_title = _title(raw_source_title, :naics_2017_title)
        target_title = _title(raw_target_title, :naics_2022_title)
        _string(note, :naics_concordance_note; allow_empty = true)
        _consistent_title!(source_titles, source, source_title, :naics_2017_title_conflict)
        _consistent_title!(target_titles, target, target_title, :naics_2022_title_conflict)
        signature = (source, source_title, target, target_title, note)
        signature in seen_rows && _fail(:duplicate_mapping_row, "NAICS concordance row $index")
        push!(seen_rows, signature)
        push!(
            parsed,
            Dict{String, Any}(
                "ordinal" => ordinal,
                "2017_code" => source,
                "2017_title" => source_title,
                "2022_code" => target,
                "2022_title" => target_title,
                "note" => note,
                "direction" => "NAICS_2017_TO_NAICS_2022",
            ),
        )
    end
    return _cardinalities(parsed, row -> row["2017_code"], row -> row["2022_code"])
end

function _string_vector(value, code::Symbol)
    value isa AbstractVector || _fail(code, "expected vector")
    output = String[]
    for item in value
        text = _string(item, code)
        text in ("Other", "Used") && _fail(:special_account_as_naics, text)
        strip(text) == text || _fail(code, "edge whitespace")
        push!(output, text)
    end
    length(unique(output)) == length(output) || _fail(code, "duplicate element")
    return output
end

function _integer_vector(value, code::Symbol)
    value isa AbstractVector || _fail(code, "expected vector")
    output = Int[]
    for item in value
        integer = _int(item, code)
        integer > 0 || _fail(code, "positive line required")
        push!(output, integer)
    end
    length(unique(output)) == length(output) || _fail(code, "duplicate element")
    return output
end

function _validate_bridge_document(document::AbstractDict)
    _expect_keys(document, ("model", "industry_to_model", "sector", "special"), :bridge_shape)
    model = _expect_keys(document["model"], ("name", "year", "sector_count", "codes", "note"), :bridge_model_shape)
    model["name"] == "BEA summary observed-commodity model" || _fail(:bridge_model, "name drift")
    _int(model["year"], :bridge_year) == 2024 || _fail(:bridge_year, "year drift")
    _int(model["sector_count"], :bridge_sector_count) == 68 || _fail(:bridge_sector_count, "count drift")
    codes = _string_vector(model["codes"], :bridge_model_code)
    Tuple(codes) == MODEL_CODES || _fail(:bridge_model_codes, "exact model code order drift")
    _string(model["note"], :bridge_model_note)

    industry = _expect_keys(document["industry_to_model"], ("441", "445", "452", "4A0"), :bridge_industry_shape)
    all(key -> industry[key] == "4A0", ("441", "445", "452", "4A0")) ||
        _fail(:bridge_industry_mapping, "retail mapping drift")

    sectors = document["sector"]
    sectors isa AbstractVector && length(sectors) == 68 ||
        _fail(:bridge_sectors, "exactly 68 sectors required")
    parsed_sectors = Dict{String, Any}[]
    for (index, sector) in enumerate(sectors)
        _expect_keys(sector, ("code", "qcew_2022", "susb_2017", "fixed_asset_lines"), :bridge_sector_shape)
        sector["code"] == SECTOR_CODES[index] || _fail(:bridge_sector_order, index)
        qcew = _string_vector(sector["qcew_2022"], :bridge_qcew)
        susb = _string_vector(sector["susb_2017"], :bridge_susb)
        foreach(value -> _naics_code(value, :bridge_qcew), qcew)
        foreach(value -> _naics_code(value, :bridge_susb), susb)
        fixed = _integer_vector(sector["fixed_asset_lines"], :bridge_fixed_assets)
        push!(
            parsed_sectors,
            Dict{String, Any}(
                "ordinal" => index,
                "code" => sector["code"],
                "qcew_2022" => qcew,
                "susb_2017" => susb,
                "fixed_asset_lines" => fixed,
            ),
        )
    end
    special_keys = (
        "farm_firms_source", "housing_fixed_assets", "housing_depreciation",
        "other_real_estate_fixed_assets", "other_real_estate_dwellings",
        "other_real_estate_depreciation", "federal_assets",
        "federal_defense_assets", "federal_nondefense_assets", "state_local_assets",
        "general_government_assets", "government_enterprise_assets",
        "government_allocation_status",
    )
    special = _expect_keys(document["special"], special_keys, :bridge_special_shape)
    parsed_special = Dict{String, Any}()
    for key in special_keys
        parsed_special[key] = _string(special[key], :bridge_special_value)
    end
    return Dict{String, Any}(
        "model_name" => model["name"],
        "year" => model["year"],
        "sector_count" => model["sector_count"],
        "model_codes" => codes,
        "sector_codes" => collect(SECTOR_CODES),
        "sector_order_differs_from_model_codes" => true,
        "sector_order_difference_positions" => collect(28:36),
        "model_note" => model["note"],
        "industry_to_model" => Dict(key => industry[key] for key in ("441", "445", "452", "4A0")),
        "sectors" => parsed_sectors,
        "special" => parsed_special,
    )
end

function _repository_bridge_projection()
    source = _read_stable_source(
        "scripts/us/bea71.toml",
        :bridge_path,
        maximum_bytes = 1_048_576,
    )
    bytes = source.bytes
    byte_count = length(bytes)
    digest = source.sha256
    digest == EXPECTED_SOURCE_PINS[7][3] || _fail(:bridge_hash, "bridge bytes drift")
    isvalid(String, bytes) || _fail(:bridge_utf8, "bridge must be UTF-8")
    text = String(copy(bytes))
    startswith(text, '\ufeff') && _fail(:bridge_bom, "BOM forbidden")
    document = try
        TOML.parse(text)
    catch error
        _fail(:bridge_toml, sprint(showerror, error))
    end
    projection = _validate_bridge_document(document)
    projection["profile_id"] = "beforeit_bea71_model_bridge"
    projection["object_id"] = "beforeit_bea71_model_bridge"
    projection["repository_path"] = "scripts/us/bea71.toml"
    projection["repository_sha256"] = digest
    projection["repository_byte_count"] = byte_count
    projection["official_crosswalk"] = false
    projection["prospective_receipt_present"] = false
    projection["physically_qualified"] = false
    return projection
end

function _normalize_objects(objects)
    objects isa AbstractVector || _fail(:object_set_type, "ordered Pair vector required")
    length(objects) == length(OFFICIAL_FIXTURE_OBJECT_IDS) ||
        _fail(:object_set_count, "exactly six official synthetic workbook fixtures required")
    output = Pair{String, Any}[]
    seen = Set{String}()
    for (index, pair) in enumerate(objects)
        pair isa Pair || _fail(:object_type, "object $index must be Pair")
        object_id = _string(pair.first, :object_id)
        object_id in seen && _fail(:duplicate_object, object_id)
        push!(seen, object_id)
        object_id == OFFICIAL_FIXTURE_OBJECT_IDS[index] ||
            _fail(:object_order, "expected $(OFFICIAL_FIXTURE_OBJECT_IDS[index])")
        pair.second isa AbstractDict || _fail(:object_value, "$object_id must be object")
        push!(output, object_id => pair.second)
    end
    return output
end

function _manifest_entry(object_id, ordinal, parsed)
    return Dict{String, Any}(
        "ordinal" => ordinal,
        "object_id" => object_id,
        "fixture_origin" => FIXTURE_ORIGIN,
        "planned_locator_attributed_to_fixture" => false,
        "official_body_claimed" => false,
        "provider_layout_claimed" => false,
        "object_subject_sha256" => parsed.object_subject_sha256,
        "part_receipts" => deepcopy(parsed.part_receipts),
    )
end

function validate_object_set(objects)
    profile = validate_profile()
    normalized = _normalize_objects(objects)
    parsed = Dict{String, Any}()
    manifest_by_id = Dict{String, Dict{String, Any}}()
    for (ordinal, pair) in enumerate(normalized)
        workbook = _synthetic_workbook(pair.second, pair.first)
        parsed[pair.first] = workbook
        manifest_by_id[pair.first] = _manifest_entry(pair.first, ordinal, workbook)
    end

    use_axis = _parse_summary_axis(parsed["bea_summary_use_2024"].rows, "bea_summary_use_2024")
    make_axis = _parse_summary_axis(parsed["bea_summary_make_2024"].rows, "bea_summary_make_2024")
    _canonical_sha256(Dict("rows" => use_axis)) ==
        _canonical_sha256(Dict("rows" => make_axis)) ||
        _fail(:shared_axis_mismatch, "2024 use and make axes differ")
    shared_projection = Dict{String, Any}(
        "profile_id" => "bea_summary_codes",
        "object_ids" => ["bea_summary_use_2024", "bea_summary_make_2024"],
        "shared_parent_profile_sha256" => EXPECTED_SOURCE_PINS[6][3],
        "shared_parent_object_sha256" => [
            "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7",
            "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6",
        ],
        "fixture_rows" => use_axis,
        "industry_count" => 71,
        "commodity_count" => 73,
        "special_accounts" => ["Other", "Used"],
        "fixture_matches_across_use_make" => true,
        "parent_raw_bytes_replayed" => false,
        "physically_qualified" => false,
    )
    bea_projection = Dict{String, Any}(
        "profile_id" => "bea_industry_commodity_naics_concordance",
        "object_id" => "bea_industry_commodity_naics_concordance",
        "direction" => "BEA_TO_NAICS",
        "inverse_generated" => false,
        "rows" => _parse_bea_concordance(
            parsed["bea_industry_commodity_naics_concordance"].rows,
        ),
        "physically_qualified" => false,
    )
    bridge_projection = _repository_bridge_projection()
    naics_2017_projection = Dict{String, Any}(
        "profile_id" => "naics_2017",
        "object_id" => "naics_2017_structure",
        "rows" => _parse_naics_structure(parsed["naics_2017_structure"].rows, 2017),
        "physically_qualified" => false,
    )
    naics_concordance_projection = Dict{String, Any}(
        "profile_id" => "naics_2017_to_2022",
        "object_id" => "naics_2017_to_2022_concordance",
        "direction" => "NAICS_2017_TO_NAICS_2022",
        "inverse_generated" => false,
        "rows" => _parse_naics_concordance(
            parsed["naics_2017_to_2022_concordance"].rows,
        ),
        "physically_qualified" => false,
    )
    naics_2022_projection = Dict{String, Any}(
        "profile_id" => "naics_2022",
        "object_id" => "naics_2022_structure",
        "rows" => _parse_naics_structure(parsed["naics_2022_structure"].rows, 2022),
        "physically_qualified" => false,
    )
    projections = [
        shared_projection,
        bea_projection,
        bridge_projection,
        naics_2017_projection,
        naics_concordance_projection,
        naics_2022_projection,
    ]

    manifest = Dict{String, Any}[]
    for (ordinal, object_id) in enumerate(RESULT_OBJECT_ORDER)
        if object_id == "beforeit_bea71_model_bridge"
            push!(
                manifest,
                Dict{String, Any}(
                    "ordinal" => ordinal,
                    "object_id" => object_id,
                    "fixture_origin" => "REPOSITORY_LOCAL_EXACT_BYTES",
                    "planned_locator_attributed_to_fixture" => false,
                    "official_body_claimed" => false,
                    "provider_layout_claimed" => true,
                    "object_subject_sha256" => bridge_projection["repository_sha256"],
                    "part_receipts" => Dict{String, Any}[],
                ),
            )
        else
            entry = deepcopy(manifest_by_id[object_id])
            entry["ordinal"] = ordinal
            push!(manifest, entry)
        end
    end

    gates = Dict{String, Any}(key => false for key in keys(profile["gates"]))
    result = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => "beforeit-us-classification-maps-offline-result.v1",
            "contract_id" => CONTRACT_ID,
            "status" => "CANNOT_RUN",
            "claim_ceiling" => profile["scope"]["claim_ceiling"],
            "content_sha256" => repeat("0", 64),
        ),
        "validation" => Dict{String, Any}(
            "profile_physical_sha256" => EXPECTED_PROFILE_PHYSICAL_SHA256,
            "profile_semantic_sha256" => profile_semantic_sha256(profile),
            "offline_validation_only" => true,
            "synthetic_fixture_only" => true,
            "network_action_count" => 0,
            "filesystem_write_action_count" => 0,
            "official_fixture_url_attribution_count" => 0,
            "official_body_count" => 0,
            "current_origin_receipt_count" => 0,
            "qualified_profile_count" => 0,
            "profile_count" => 6,
            "object_count" => 7,
        ),
        "object_order" => collect(RESULT_OBJECT_ORDER),
        "object_set_manifest" => manifest,
        "profile_projections" => projections,
        "blockers" => collect(RESULT_BLOCKERS),
        "gates" => gates,
    )
    result["artifact"]["content_sha256"] =
        _canonical_sha256(result; exclude_artifact_hash = true)
    return result
end

function _deep_exact(left, right)
    typeof(left) === typeof(right) || return false
    if left isa AbstractDict
        length(left) == length(right) || return false
        all(key -> haskey(right, key), keys(left)) || return false
        return all(key -> _deep_exact(left[key], right[key]), keys(left))
    elseif left isa AbstractArray
        axes(left) == axes(right) || return false
        return all(index -> _deep_exact(left[index], right[index]), eachindex(left))
    elseif left isa Tuple
        length(left) == length(right) || return false
        return all(index -> _deep_exact(left[index], right[index]), eachindex(left))
    end
    return isequal(left, right)
end

function validate_compiled_result(result::AbstractDict, objects)
    expected = validate_object_set(objects)
    _deep_exact(result, expected) ||
        _fail(:result_replay, "compiled result differs from type-exact replay")
    _expect_keys(
        result,
        (
            "artifact", "validation", "object_order", "object_set_manifest",
            "profile_projections", "blockers", "gates",
        ),
        :result_shape,
    )
    artifact = _expect_keys(
        result["artifact"],
        ("schema_version", "contract_id", "status", "claim_ceiling", "content_sha256"),
        :result_artifact_shape,
    )
    artifact["schema_version"] == "beforeit-us-classification-maps-offline-result.v1" ||
        _fail(:result_schema, "schema drift")
    artifact["contract_id"] == CONTRACT_ID || _fail(:result_contract, "contract drift")
    artifact["status"] == "CANNOT_RUN" || _fail(:result_status, "must remain CANNOT_RUN")
    _hash(artifact["content_sha256"], :result_hash)
    _canonical_sha256(result; exclude_artifact_hash = true) == artifact["content_sha256"] ||
        _fail(:result_hash, "self-hash mismatch")
    _canonical_sha256(result) == _canonical_sha256(expected) ||
        _fail(:result_replay, "compiled result digest differs from strict replay")
    return result
end

end
