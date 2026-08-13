module USUsedOtherEvidenceLedger

using CSV
using JSON
using SHA
using TOML

export APPROVED_CONTRACT_SHA256,
    CHECK_SCHEMA,
    COMPONENT_SCHEMA,
    CONTRACT_SCHEMA,
    DECISION_SCHEMA,
    LITERATURE_SCHEMA,
    OBSERVATION_SCHEMA,
    ComponentEvidence,
    EvidenceObservation,
    LiteratureEvidence,
    SourceCheck,
    UsedOtherDecision,
    UsedOtherEvidenceContract,
    UsedOtherEvidenceReport,
    allocate_2024_components,
    build_used_other_evidence,
    classify_special_account,
    load_used_other_evidence_contract,
    materialize_used_other_model_state,
    project_2017_component_shares_to_2024,
    validate_used_other_evidence,
    write_used_other_evidence

const CONTRACT_SCHEMA =
    "beforeit-us-used-other-evidence-ledger-contract.v1"
const OBSERVATION_SCHEMA =
    "beforeit-us-used-other-evidence-observation.v1"
const COMPONENT_SCHEMA =
    "beforeit-us-used-other-component-evidence.v1"
const CHECK_SCHEMA = "beforeit-us-used-other-source-check.v1"
const DECISION_SCHEMA =
    "beforeit-us-used-other-decision-assessment.v1"
const LITERATURE_SCHEMA =
    "beforeit-us-used-other-literature-evidence.v1"
const REPORT_SCHEMA = "beforeit-us-used-other-evidence-report.v1"
const DETAIL_SCOPE_INVENTORY_SCHEMA =
    "beforeit-us-bea-after-redefinitions-workbook-sheet-inventory.v1"
const APPROVED_CONTRACT_SHA256 =
    "326dc50276692c5623e23fe63085cb82742435b6c6b3d0a04676451426d9d128"
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "used_other_evidence_ledger.toml")
const DEFAULT_REPO_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", ".."))

const DETAIL_CODES = ["S00401", "S00402", "S00300", "S00900"]
const SUMMARY_CODES = ["Used", "Other"]
const ALL_SPECIAL_CODES = Set(vcat(DETAIL_CODES, SUMMARY_CODES))
const COMPONENT_TO_AGGREGATE = Dict(
    "S00401" => "Used",
    "S00402" => "Used",
    "S00300" => "Other",
    "S00900" => "Other",
)
const COMPONENT_TYPES = Dict(
    "S00401" =>
        "MIXED_SCRAP_CURRENT_BYPRODUCT_AND_EXISTING_ASSET_DISPOSAL",
    "S00402" => "EXISTING_GOOD_OR_ASSET_TRANSFER",
    "S00300" => "IMPORT_BOUNDARY_NONCOMPARABLE_SERVICES_OR_RIGHTS",
    "S00900" => "FINAL_USE_RESIDENCE_RECLASSIFICATION_ADJUSTMENT",
)
const AGGREGATE_TYPE = "UNRESOLVED_VINTAGE_SPECIFIC_COMPOSITE"
const EXPECTED_ARTIFACT_IDS = Set(
    [
        "special_2017_cells",
        "special_2017_manifest",
        "special_component_crosswalk",
        "special_source_acquisition_receipt",
        "after_redefinitions_workbook_sheet_inventory",
        "common_basis_2024_cells",
        "common_basis_2024_manifest",
        "model_core_mapping",
        "model_sector_mapping",
        "bea_io_methods_pdf",
        "bea_io_methods_receipt",
        "scripts_us_project",
        "scripts_us_manifest",
    ],
)
const EXPECTED_LITERATURE_IDS = Set(
    [
        "bea_official_component_crosswalk",
        "bea_current_archive_detail_scope",
        "bea_used_scrap_treatment",
        "bea_noncomparable_imports_and_row",
        "bea_scrap_byproduct_transform",
        "sna_existing_asset_transfer",
        "sna_scrap_disposal",
        "esa_existing_goods_transfer",
        "un_byproduct_definition",
        "un_used_scrap_trade_services",
        "un_used_scrap_transport_services",
        "esa_trade_transport_valuation",
        "oecd_valuation_and_import_split",
    ],
)
const EXPECTED_DECISION_IDS = [
    "dealer_service_allocation",
    "transport_service_allocation",
    "used_2024_component_allocation",
    "other_2024_component_allocation",
    "project_2017_component_shares_to_2024",
    "label_based_core_or_model_absorption",
    "s00900_government_producer_inference",
    "other_as_row_behavior_or_zero_cash",
    "runtime_state_gate_origin_or_score_write",
]
const EXPECTED_CHECK_IDS = [
    "newer_than_2017_detail_vintage_absence",
    "2017_used_t001_reconstruction",
    "2017_used_t004_reconstruction",
    "2017_used_t007_reconstruction",
    "2017_other_t001_reconstruction",
    "2017_other_t004_reconstruction",
    "2017_other_t007_reconstruction",
    "2017_used_final_cell_maximum_residual",
    "2017_other_final_cell_maximum_residual",
    "2017_s00401_use_output_identity",
    "2017_s00402_use_output_identity",
    "2017_s00300_use_output_identity",
    "2017_s00900_use_output_identity",
    "2017_s00401_make_to_output",
    "2017_s00402_make_to_output",
    "2017_s00300_make_to_output",
    "2017_s00900_make_to_output",
    "2017_s00401_make_placement_count",
    "2017_s00402_make_placement_count",
    "2017_s00300_make_placement_count",
    "2017_s00900_make_placement_count",
    "2024_used_make_to_output",
    "2024_other_make_to_output",
    "2024_used_producer_control_identity",
    "2024_other_producer_control_identity",
    "2024_used_import_control_identity",
    "2024_other_import_control_identity",
    "2024_used_producer_intermediate_to_control",
    "2024_other_producer_intermediate_to_control",
    "2024_used_producer_final_to_control",
    "2024_other_producer_final_to_control",
    "2024_used_import_intermediate_to_control",
    "2024_other_import_intermediate_to_control",
    "2024_used_import_final_to_control",
    "2024_other_import_final_to_control",
]
const EXPECTED_2017_PROJECTIONS = Set(
    [
        "detail_use_intermediate_2017",
        "detail_use_final_2017",
        "detail_use_controls_2017",
        "summary_use_intermediate_2017",
        "summary_use_final_2017",
        "summary_use_controls_2017",
        "detail_make_components_2017",
        "detail_make_output_2017",
        "summary_make_components_2017",
        "summary_make_output_2017",
    ],
)
const EXPECTED_2024_PROJECTIONS = Set(
    [
        "producer_intermediate_use_2024",
        "producer_final_use_2024",
        "producer_use_commodity_controls_2024",
        "producer_make_2024",
        "producer_make_commodity_output_2024",
        "import_intermediate_use_2024",
        "import_final_use_2024",
        "import_commodity_controls_2024",
    ],
)
const PROJECTION_SOURCE_ROLES = Dict(
    "detail_use_intermediate_2017" =>
        "PUBLISHED_PRODUCER_INTERMEDIATE_USE_CELL",
    "detail_use_final_2017" => "PUBLISHED_PRODUCER_FINAL_USE_CELL",
    "detail_use_controls_2017" => "PUBLISHED_PRODUCER_USE_CONTROL",
    "summary_use_intermediate_2017" =>
        "PUBLISHED_PRODUCER_INTERMEDIATE_USE_CELL",
    "summary_use_final_2017" => "PUBLISHED_PRODUCER_FINAL_USE_CELL",
    "summary_use_controls_2017" => "PUBLISHED_PRODUCER_USE_CONTROL",
    "detail_make_components_2017" =>
        "PUBLISHED_SOURCE_MAKE_PLACEMENT",
    "detail_make_output_2017" =>
        "PUBLISHED_COMMODITY_OUTPUT_CONTROL",
    "summary_make_components_2017" =>
        "PUBLISHED_SOURCE_MAKE_PLACEMENT",
    "summary_make_output_2017" =>
        "PUBLISHED_COMMODITY_OUTPUT_CONTROL",
    "producer_intermediate_use_2024" =>
        "PUBLISHED_PRODUCER_INTERMEDIATE_USE_CELL",
    "producer_final_use_2024" =>
        "PUBLISHED_PRODUCER_FINAL_USE_CELL",
    "producer_use_commodity_controls_2024" =>
        "PUBLISHED_PRODUCER_USE_CONTROL",
    "producer_make_2024" => "PUBLISHED_SOURCE_MAKE_PLACEMENT",
    "producer_make_commodity_output_2024" =>
        "PUBLISHED_COMMODITY_OUTPUT_CONTROL",
    "import_intermediate_use_2024" =>
        "PUBLISHED_IMPORT_INTERMEDIATE_USE_CELL",
    "import_final_use_2024" => "PUBLISHED_IMPORT_FINAL_USE_CELL",
    "import_commodity_controls_2024" =>
        "PUBLISHED_IMPORT_USE_CONTROL",
)
const EXPECTED_TOP_LEVEL_KEYS = Set(
    [
        "schema_version",
        "contract_id",
        "classification",
        "promotion_status",
        "scientific_role",
        "source_mask_policy",
        "vintage_policy",
        "component_policy",
        "mapping_policy",
        "transfer_output_policy",
        "dealer_transport_policy",
        "forecast_origin_admissible",
        "promotion_ready",
        "model_state_write",
        "accounting_gate_effect",
        "forecast_score_write",
        "detail_vintage_scope",
        "expected",
        "artifact",
        "component",
        "decision",
        "literature",
    ],
)
const EXPECTED_ARTIFACT_KEYS =
    Set(["artifact_id", "path", "sha256", "role"])
const EXPECTED_COMPONENT_KEYS = Set(
    [
        "component_code",
        "label",
        "aggregate_code",
        "economic_type",
        "source_use_role",
        "source_make_role",
        "literature_ids",
        "observed_2017_intermediate_millions",
        "observed_2017_final_use_millions",
        "observed_2017_output_millions",
        "observed_2017_output_cell_kind",
        "observed_2017_make_placement_count",
        "observed_2017_make_placement_sum_millions",
        "current_production_output",
        "existing_asset_transfer",
        "import_boundary",
        "reclassification",
        "structural_zero_claimed",
        "source_make_placement_is_producer_inference",
        "allocation_2024_status",
        "runtime_target_namespace",
        "mapping_applied",
    ],
)
const EXPECTED_DECISION_KEYS = Set(
    [
        "decision_id",
        "status",
        "blocker",
        "required_evidence",
        "literature_ids",
        "mapping_applied",
        "output_emitted",
        "target_namespace",
    ],
)
const EXPECTED_LITERATURE_KEYS = Set(
    [
        "literature_id",
        "authority",
        "title",
        "version",
        "url",
        "locator",
        "document_sha256",
        "accessed_on",
        "source_fact",
        "project_decision",
        "uncertainty",
        "test_ids",
    ],
)
const EXPECTED_DETAIL_SCOPE_KEYS = Set(
    [
        "source_endpoint",
        "source_zip_sha256",
        "source_zip_byte_count",
        "source_http_last_modified",
        "producer_detail_workbooks",
        "producer_detail_sheet_names",
        "producer_summary_workbooks",
        "producer_summary_year_span",
        "latest_detail_year",
        "latest_summary_year",
        "newer_than_2017_detail_available",
        "finding",
        "allocation_effect",
    ],
)
const EXPECTED_SCOPE_INVENTORY_KEYS = Set(
    [
        "schema_version",
        "classification",
        "source_agency",
        "source_url",
        "source_retrieved_at_utc",
        "source_http_last_modified",
        "source_zip_sha256",
        "source_zip_byte_count",
        "inventory_method",
        "detail_workbook_count",
        "summary_workbook_count",
        "detail_years",
        "summary_years",
        "latest_detail_year",
        "latest_summary_year",
        "newer_than_2017_detail_available",
        "finding",
        "forecast_origin_admissible",
        "model_state_write",
        "accounting_gate_effect",
        "forecast_score_write",
        "workbook",
    ],
)
const EXPECTED_SCOPE_WORKBOOK_KEYS =
    Set(["member", "table", "level", "sha256", "sheet_names"])
const EXPECTED_DETAIL_SHEET_NAMES =
    ["NAICS Codes", "2007", "2012", "2017"]
const EXPECTED_SUMMARY_SHEET_NAMES = string.(1997:2024)
const EXPECTED_SCOPE_WORKBOOKS = Dict(
    "IOUse_After_Redefinitions_PRO_Detail.xlsx" => (
        table = "PRODUCER_USE",
        level = "DETAIL",
        sha256 =
            "ee0f977ccc6b884d3e3b912596e39c1036f513880531dda33be947e68fb03fe4",
        sheet_names = EXPECTED_DETAIL_SHEET_NAMES,
    ),
    "IOMake_After_Redefinitions_PRO_Detail.xlsx" => (
        table = "PRODUCER_MAKE",
        level = "DETAIL",
        sha256 =
            "96fb70a032e3ab81514231f49c2eae888b7ef8b741b00f352f2fc0fa8776db67",
        sheet_names = EXPECTED_DETAIL_SHEET_NAMES,
    ),
    "IOUse_After_Redefinitions_PRO_Summary.xlsx" => (
        table = "PRODUCER_USE",
        level = "SUMMARY",
        sha256 =
            "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7",
        sheet_names = EXPECTED_SUMMARY_SHEET_NAMES,
    ),
    "IOMake_After_Redefinitions_PRO_Summary.xlsx" => (
        table = "PRODUCER_MAKE",
        level = "SUMMARY",
        sha256 =
            "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6",
        sheet_names = EXPECTED_SUMMARY_SHEET_NAMES,
    ),
)
const EXPECTED_SUMMARY_KEYS = Set(
    [
        "observation_count",
        "observation_2017_count",
        "observation_2017_detail_count",
        "observation_2017_summary_count",
        "observation_2024_summary_count",
        "numeric_cell_count",
        "native_blank_count",
        "native_ellipsis_count",
        "selected_zero_not_shown_count",
        "explicit_numeric_zero_count",
        "negative_cell_count",
        "component_count",
        "source_check_count",
        "decision_count",
        "blocked_decision_count",
        "literature_count",
        "newer_than_2017_detail_vintage_count",
        "projected_2017_share_count",
        "dealer_margin_allocation_count",
        "transport_service_allocation_count",
        "component_allocation_2024_count",
        "core_absorption_count",
        "model_absorption_count",
        "government_producer_inference_count",
        "row_behavior_inference_count",
        "model_state_write_count",
        "gate_effect_count",
        "origin_admissible_output_count",
        "forecast_score_write_count",
    ],
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
file_sha256(path) = sha256_hex(read(path))

function fail(location::AbstractString, message::AbstractString)
    throw(ArgumentError("$location: $message"))
end

function exact_keys(value, expected::Set{String}, location)
    value isa AbstractDict || fail(location, "must be a table")
    actual = Set(String.(keys(value)))
    actual == expected ||
        fail(
        location,
        "keys differ; missing=$(sort!(collect(setdiff(expected, actual)))) " *
            "extra=$(sort!(collect(setdiff(actual, expected))))",
    )
    return nothing
end

function string_value(value)
    return ismissing(value) ? "" : String(value)
end

struct PinnedArtifact
    artifact_id::String
    relative_path::String
    path::String
    sha256::String
    role::String
end

struct ComponentRule
    component_code::String
    label::String
    aggregate_code::String
    economic_type::String
    source_use_role::String
    source_make_role::String
    literature_ids::Vector{String}
    observed_2017_intermediate_millions::Float64
    observed_2017_final_use_millions::Float64
    observed_2017_output_millions::Float64
    observed_2017_output_cell_kind::String
    observed_2017_make_placement_count::Int
    observed_2017_make_placement_sum_millions::Float64
    current_production_output::Bool
    existing_asset_transfer::Bool
    import_boundary::Bool
    reclassification::Bool
    structural_zero_claimed::Bool
    source_make_placement_is_producer_inference::Bool
    allocation_2024_status::String
    runtime_target_namespace::String
    mapping_applied::Bool
end

struct DecisionSpec
    decision_id::String
    status::String
    blocker::String
    required_evidence::String
    literature_ids::Vector{String}
    mapping_applied::Bool
    output_emitted::Bool
    target_namespace::String
end

mutable struct LiteratureEvidence
    schema_version::String
    literature_id::String
    authority::String
    title::String
    version::String
    url::String
    locator::String
    document_sha256::String
    accessed_on::String
    source_fact::String
    project_decision::String
    uncertainty::String
    test_ids::String
end

struct UsedOtherEvidenceContract
    path::String
    repo_root::String
    sha256::String
    contract_id::String
    classification::String
    promotion_status::String
    scientific_role::String
    policies::Dict{String, String}
    detail_vintage_scope::Dict{String, Any}
    expected::Dict{String, Any}
    artifacts::Dict{String, PinnedArtifact}
    components::Dict{String, ComponentRule}
    decisions::Vector{DecisionSpec}
    literature::Vector{LiteratureEvidence}
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_state_write::Bool
    accounting_gate_effect::Symbol
    forecast_score_write::Bool
end

mutable struct EvidenceObservation
    schema_version::String
    record_id::String
    source_fixture_id::String
    source_record_key::String
    year::Int
    vintage_scope::String
    source_level::String
    projection_id::String
    source_table::String
    source_role::String
    account_axis::String
    account_code::String
    aggregate_account_code::String
    component_code::String
    economic_type::String
    row_position::Int
    row_code::String
    row_description::String
    column_position::Int
    column_code::String
    column_description::String
    counterparty_code::String
    source_locator::String
    value_millions::Float64
    sign_class::String
    native_cell_kind::String
    numeric_mask::Bool
    native_blank_mask::Bool
    native_ellipsis_mask::Bool
    selected_zero_not_shown_mask::Bool
    explicit_numeric_zero::Bool
    structural_zero_claimed::Bool
    price_basis::String
    unit::String
    source_make_placement_is_producer_inference::Bool
    mapping_applied::Bool
end

mutable struct ComponentEvidence
    schema_version::String
    component_code::String
    label::String
    aggregate_code::String
    economic_type::String
    source_use_role::String
    source_make_role::String
    literature_ids::String
    observed_2017_intermediate_millions::Float64
    observed_2017_final_use_millions::Float64
    observed_2017_output_millions::Float64
    observed_2017_output_cell_kind::String
    observed_2017_make_placement_count::Int
    observed_2017_make_placement_sum_millions::Float64
    current_production_output::Bool
    existing_asset_transfer::Bool
    import_boundary::Bool
    reclassification::Bool
    structural_zero_claimed::Bool
    source_make_placement_is_producer_inference::Bool
    allocation_2024_status::String
    runtime_target_namespace::String
    mapping_applied::Bool
end

mutable struct SourceCheck
    schema_version::String
    check_id::String
    status::String
    source_year::Int
    account_code::String
    equation::String
    lhs::Float64
    rhs::Float64
    residual::Float64
    absolute_residual::Float64
    tolerance::Float64
    evidence_scope::String
    correction_applied::Bool
    mapping_applied::Bool
end

mutable struct UsedOtherDecision
    schema_version::String
    decision_id::String
    status::String
    diagnostic_value::Union{Missing, Float64}
    tolerance::Union{Missing, Float64}
    blocker::String
    required_evidence::String
    literature_ids::String
    mapping_applied::Bool
    output_emitted::Bool
    target_namespace::String
    forecast_origin_admissible::Bool
end

mutable struct UsedOtherEvidenceReport
    classification::String
    promotion_status::String
    observations::Vector{EvidenceObservation}
    components::Vector{ComponentEvidence}
    checks::Vector{SourceCheck}
    decisions::Vector{UsedOtherDecision}
    literature::Vector{LiteratureEvidence}
    summary::Dict{String, Any}
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_state_write::Bool
    accounting_gate_effect::Symbol
    forecast_score_write::Bool
end

function parse_artifact(raw, repo_root)
    artifact_id = String(raw["artifact_id"])
    relative_path = String(raw["path"])
    path = normpath(joinpath(repo_root, relative_path))
    startswith(path, string(repo_root, Base.Filesystem.path_separator)) ||
        fail("artifact.$artifact_id.path", "escapes repository root")
    isfile(path) || fail("artifact.$artifact_id.path", "file is absent")
    expected_sha256 = String(raw["sha256"])
    length(expected_sha256) == 64 ||
        fail("artifact.$artifact_id.sha256", "must have 64 hex characters")
    actual_sha256 = file_sha256(path)
    actual_sha256 == expected_sha256 ||
        fail(
        "artifact.$artifact_id.sha256",
        "expected $expected_sha256, got $actual_sha256",
    )
    return PinnedArtifact(
        artifact_id,
        relative_path,
        path,
        expected_sha256,
        String(raw["role"]),
    )
end

function parse_component(raw)
    return ComponentRule(
        String(raw["component_code"]),
        String(raw["label"]),
        String(raw["aggregate_code"]),
        String(raw["economic_type"]),
        String(raw["source_use_role"]),
        String(raw["source_make_role"]),
        String.(raw["literature_ids"]),
        Float64(raw["observed_2017_intermediate_millions"]),
        Float64(raw["observed_2017_final_use_millions"]),
        Float64(raw["observed_2017_output_millions"]),
        String(raw["observed_2017_output_cell_kind"]),
        Int(raw["observed_2017_make_placement_count"]),
        Float64(raw["observed_2017_make_placement_sum_millions"]),
        Bool(raw["current_production_output"]),
        Bool(raw["existing_asset_transfer"]),
        Bool(raw["import_boundary"]),
        Bool(raw["reclassification"]),
        Bool(raw["structural_zero_claimed"]),
        Bool(raw["source_make_placement_is_producer_inference"]),
        String(raw["allocation_2024_status"]),
        String(raw["runtime_target_namespace"]),
        Bool(raw["mapping_applied"]),
    )
end

function parse_decision(raw)
    return DecisionSpec(
        String(raw["decision_id"]),
        String(raw["status"]),
        String(raw["blocker"]),
        String(raw["required_evidence"]),
        String.(raw["literature_ids"]),
        Bool(raw["mapping_applied"]),
        Bool(raw["output_emitted"]),
        String(raw["target_namespace"]),
    )
end

function parse_literature(raw)
    return LiteratureEvidence(
        LITERATURE_SCHEMA,
        String(raw["literature_id"]),
        String(raw["authority"]),
        String(raw["title"]),
        String(raw["version"]),
        String(raw["url"]),
        String(raw["locator"]),
        String(raw["document_sha256"]),
        String(raw["accessed_on"]),
        String(raw["source_fact"]),
        String(raw["project_decision"]),
        String(raw["uncertainty"]),
        join(String.(raw["test_ids"]), ";"),
    )
end

function load_detail_scope_inventory(contract::UsedOtherEvidenceContract)
    inventory_path = contract.artifacts[
        "after_redefinitions_workbook_sheet_inventory",
    ].path
    inventory = TOML.parsefile(inventory_path)
    exact_keys(
        inventory,
        EXPECTED_SCOPE_INVENTORY_KEYS,
        "detail_scope_inventory",
    )
    inventory["schema_version"] == DETAIL_SCOPE_INVENTORY_SCHEMA ||
        fail("detail_scope_inventory.schema_version", "changed")
    inventory["classification"] ==
        "PINNED_SOURCE_SCOPE_EVIDENCE_NOT_ORIGIN_ELIGIBLE" ||
        fail("detail_scope_inventory.classification", "changed")

    scope = contract.detail_vintage_scope
    for (inventory_key, scope_key) in (
            ("source_url", "source_endpoint"),
            ("source_zip_sha256", "source_zip_sha256"),
            ("source_zip_byte_count", "source_zip_byte_count"),
            ("source_http_last_modified", "source_http_last_modified"),
            ("latest_detail_year", "latest_detail_year"),
            ("latest_summary_year", "latest_summary_year"),
            (
                "newer_than_2017_detail_available",
                "newer_than_2017_detail_available",
            ),
        )
        inventory[inventory_key] == scope[scope_key] ||
            fail(
            "detail_scope_inventory.$inventory_key",
            "differs from the approved contract",
        )
    end
    inventory["detail_years"] == [2007, 2012, 2017] ||
        fail("detail_scope_inventory.detail_years", "changed")
    inventory["summary_years"] == collect(1997:2024) ||
        fail("detail_scope_inventory.summary_years", "changed")
    Int(inventory["detail_workbook_count"]) == 2 ||
        fail("detail_scope_inventory.detail_workbook_count", "changed")
    Int(inventory["summary_workbook_count"]) == 2 ||
        fail("detail_scope_inventory.summary_workbook_count", "changed")
    for key in (
            "forecast_origin_admissible",
            "model_state_write",
            "forecast_score_write",
        )
        inventory[key] === false ||
            fail("detail_scope_inventory.$key", "must remain false")
    end
    inventory["accounting_gate_effect"] == "NONE" ||
        fail(
        "detail_scope_inventory.accounting_gate_effect",
        "must remain NONE",
    )

    workbook_rows = inventory["workbook"]
    length(workbook_rows) == 4 ||
        fail("detail_scope_inventory.workbook", "count changed")
    workbook_by_member = Dict{String, Any}()
    for (index, workbook) in pairs(workbook_rows)
        exact_keys(
            workbook,
            EXPECTED_SCOPE_WORKBOOK_KEYS,
            "detail_scope_inventory.workbook[$index]",
        )
        member = String(workbook["member"])
        haskey(workbook_by_member, member) &&
            fail(
            "detail_scope_inventory.workbook",
            "duplicate member $member",
        )
        workbook_by_member[member] = workbook
    end
    Set(keys(workbook_by_member)) ==
        Set(keys(EXPECTED_SCOPE_WORKBOOKS)) ||
        fail("detail_scope_inventory.workbook", "member set changed")
    for (member, expected) in EXPECTED_SCOPE_WORKBOOKS
        workbook = workbook_by_member[member]
        String(workbook["table"]) == expected.table ||
            fail("detail_scope_inventory.$member.table", "changed")
        String(workbook["level"]) == expected.level ||
            fail("detail_scope_inventory.$member.level", "changed")
        String(workbook["sha256"]) == expected.sha256 ||
            fail("detail_scope_inventory.$member.sha256", "changed")
        String.(workbook["sheet_names"]) == expected.sheet_names ||
            fail("detail_scope_inventory.$member.sheet_names", "changed")
    end

    detail_members = [
        String(workbook["member"])
            for workbook in workbook_rows
            if workbook["level"] == "DETAIL"
    ]
    summary_members = [
        String(workbook["member"])
            for workbook in workbook_rows
            if workbook["level"] == "SUMMARY"
    ]
    detail_members == String.(scope["producer_detail_workbooks"]) ||
        fail(
        "detail_scope_inventory.detail_members",
        "differ from the approved contract",
    )
    summary_members == String.(scope["producer_summary_workbooks"]) ||
        fail(
        "detail_scope_inventory.summary_members",
        "differ from the approved contract",
    )

    receipt = JSON.parsefile(
        contract.artifacts["special_source_acquisition_receipt"].path,
    )
    for (receipt_key, inventory_key) in (
            ("source_url", "source_url"),
            ("sha256", "source_zip_sha256"),
            ("byte_count", "source_zip_byte_count"),
            ("http_last_modified", "source_http_last_modified"),
            ("acquired_at_utc", "source_retrieved_at_utc"),
        )
        receipt[receipt_key] == inventory[inventory_key] ||
            fail(
            "detail_scope_inventory.$inventory_key",
            "differs from the pinned HTTP acquisition receipt",
        )
    end

    special_manifest = TOML.parsefile(
        contract.artifacts["special_2017_manifest"].path,
    )
    for (manifest_key, member) in (
            (
                "detail_use_workbook_sha256",
                "IOUse_After_Redefinitions_PRO_Detail.xlsx",
            ),
            (
                "detail_make_workbook_sha256",
                "IOMake_After_Redefinitions_PRO_Detail.xlsx",
            ),
            (
                "summary_use_workbook_sha256",
                "IOUse_After_Redefinitions_PRO_Summary.xlsx",
            ),
            (
                "summary_make_workbook_sha256",
                "IOMake_After_Redefinitions_PRO_Summary.xlsx",
            ),
        )
        special_manifest[manifest_key] ==
            workbook_by_member[member]["sha256"] ||
            fail(
            "detail_scope_inventory.$member.sha256",
            "differs from the pinned 2017 fixture manifest",
        )
    end
    return inventory
end

function validate_component_rules(components, literature_ids)
    Set(keys(components)) == Set(DETAIL_CODES) ||
        fail("component", "component-code set changed")
    for code in DETAIL_CODES
        item = components[code]
        item.aggregate_code == COMPONENT_TO_AGGREGATE[code] ||
            fail("component.$code.aggregate_code", "changed")
        item.economic_type == COMPONENT_TYPES[code] ||
            fail("component.$code.economic_type", "changed")
        item.allocation_2024_status == "NOT_RUN_BLOCKED" ||
            fail("component.$code.allocation_2024_status", "must be blocked")
        isempty(item.runtime_target_namespace) ||
            fail("component.$code.runtime_target_namespace", "must be empty")
        item.mapping_applied &&
            fail("component.$code.mapping_applied", "must remain false")
        item.structural_zero_claimed &&
            fail("component.$code.structural_zero_claimed", "must remain false")
        item.source_make_placement_is_producer_inference &&
            fail(
            "component.$code.source_make_placement_is_producer_inference",
            "must remain false",
        )
        Set(item.literature_ids) ⊆ literature_ids ||
            fail("component.$code.literature_ids", "contains an unknown id")
    end
    return nothing
end

function load_used_other_evidence_contract(
        path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    contract_path = abspath(normpath(String(path)))
    isfile(contract_path) || fail("contract", "file is absent")
    contract_sha256 = file_sha256(contract_path)
    contract_sha256 == APPROVED_CONTRACT_SHA256 ||
        fail(
        "contract.sha256",
        "expected $APPROVED_CONTRACT_SHA256, got $contract_sha256",
    )
    root = rstrip(
        abspath(normpath(String(repo_root))),
        ['/', '\\'],
    )
    raw = TOML.parsefile(contract_path)
    exact_keys(raw, EXPECTED_TOP_LEVEL_KEYS, "contract")
    raw["schema_version"] == CONTRACT_SCHEMA ||
        fail("contract.schema_version", "changed")

    detail_scope = raw["detail_vintage_scope"]
    exact_keys(
        detail_scope,
        EXPECTED_DETAIL_SCOPE_KEYS,
        "contract.detail_vintage_scope",
    )
    detail_scope["producer_detail_sheet_names"] ==
        ["NAICS Codes", "2007", "2012", "2017"] ||
        fail(
        "contract.detail_vintage_scope.producer_detail_sheet_names",
        "changed",
    )
    Int(detail_scope["latest_detail_year"]) == 2017 ||
        fail("contract.detail_vintage_scope.latest_detail_year", "changed")
    Int(detail_scope["latest_summary_year"]) == 2024 ||
        fail("contract.detail_vintage_scope.latest_summary_year", "changed")
    detail_scope["newer_than_2017_detail_available"] === false ||
        fail(
        "contract.detail_vintage_scope.newer_than_2017_detail_available",
        "must remain false",
    )
    detail_scope["allocation_effect"] == "NONE" ||
        fail("contract.detail_vintage_scope.allocation_effect", "changed")

    expected = raw["expected"]
    exact_keys(expected, EXPECTED_SUMMARY_KEYS, "contract.expected")

    artifact_rows = raw["artifact"]
    for (index, artifact) in pairs(artifact_rows)
        exact_keys(
            artifact,
            EXPECTED_ARTIFACT_KEYS,
            "contract.artifact[$index]",
        )
    end
    artifacts = Dict{String, PinnedArtifact}()
    for artifact in artifact_rows
        item = parse_artifact(artifact, root)
        haskey(artifacts, item.artifact_id) &&
            fail("contract.artifact", "duplicate id $(item.artifact_id)")
        artifacts[item.artifact_id] = item
    end
    Set(keys(artifacts)) == EXPECTED_ARTIFACT_IDS ||
        fail("contract.artifact", "artifact-id set changed")

    literature_rows = raw["literature"]
    for (index, literature) in pairs(literature_rows)
        exact_keys(
            literature,
            EXPECTED_LITERATURE_KEYS,
            "contract.literature[$index]",
        )
    end
    literature = parse_literature.(literature_rows)
    literature_ids = Set(getfield.(literature, :literature_id))
    literature_ids == EXPECTED_LITERATURE_IDS ||
        fail("contract.literature", "literature-id set changed")
    length(literature_ids) == length(literature) ||
        fail("contract.literature", "duplicate literature id")
    for item in literature
        startswith(item.url, "https://") ||
            fail("contract.literature.$(item.literature_id).url", "not HTTPS")
        length(item.document_sha256) == 64 ||
            fail(
            "contract.literature.$(item.literature_id).document_sha256",
            "must have 64 hex characters",
        )
        item.accessed_on == "2026-08-06" ||
            fail(
            "contract.literature.$(item.literature_id).accessed_on",
            "changed",
        )
        isempty(item.locator) &&
            fail(
            "contract.literature.$(item.literature_id).locator",
            "must be nonempty",
        )
    end

    component_rows = raw["component"]
    for (index, component) in pairs(component_rows)
        exact_keys(
            component,
            EXPECTED_COMPONENT_KEYS,
            "contract.component[$index]",
        )
    end
    components = Dict{String, ComponentRule}()
    for component in component_rows
        item = parse_component(component)
        haskey(components, item.component_code) &&
            fail("contract.component", "duplicate id $(item.component_code)")
        components[item.component_code] = item
    end
    validate_component_rules(components, literature_ids)

    decision_rows = raw["decision"]
    for (index, decision) in pairs(decision_rows)
        exact_keys(
            decision,
            EXPECTED_DECISION_KEYS,
            "contract.decision[$index]",
        )
    end
    decisions = parse_decision.(decision_rows)
    getfield.(decisions, :decision_id) == EXPECTED_DECISION_IDS ||
        fail("contract.decision", "decision order or ids changed")
    for item in decisions
        item.status == "NOT_RUN_BLOCKED" ||
            fail("contract.decision.$(item.decision_id).status", "not blocked")
        item.mapping_applied &&
            fail(
            "contract.decision.$(item.decision_id).mapping_applied",
            "must remain false",
        )
        item.output_emitted &&
            fail(
            "contract.decision.$(item.decision_id).output_emitted",
            "must remain false",
        )
        isempty(item.target_namespace) ||
            fail(
            "contract.decision.$(item.decision_id).target_namespace",
            "must remain empty",
        )
        Set(item.literature_ids) ⊆ literature_ids ||
            fail(
            "contract.decision.$(item.decision_id).literature_ids",
            "contains an unknown id",
        )
    end

    policies = Dict(
        key => String(raw[key])
            for key in (
                "source_mask_policy",
                "vintage_policy",
                "component_policy",
                "mapping_policy",
                "transfer_output_policy",
                "dealer_transport_policy",
            )
    )
    raw["forecast_origin_admissible"] === false ||
        fail("contract.forecast_origin_admissible", "must remain false")
    raw["promotion_ready"] === false ||
        fail("contract.promotion_ready", "must remain false")
    raw["model_state_write"] === false ||
        fail("contract.model_state_write", "must remain false")
    raw["accounting_gate_effect"] == "NONE" ||
        fail("contract.accounting_gate_effect", "must remain NONE")
    raw["forecast_score_write"] === false ||
        fail("contract.forecast_score_write", "must remain false")

    contract = UsedOtherEvidenceContract(
        contract_path,
        root,
        contract_sha256,
        String(raw["contract_id"]),
        String(raw["classification"]),
        String(raw["promotion_status"]),
        String(raw["scientific_role"]),
        policies,
        Dict{String, Any}(
            String(key) => value for (key, value) in detail_scope
        ),
        Dict{String, Any}(String(key) => value for (key, value) in expected),
        artifacts,
        components,
        decisions,
        literature,
        false,
        false,
        false,
        :none,
        false,
    )
    load_detail_scope_inventory(contract)
    return contract
end

function struct_fields_payload(item)
    return Tuple(
        getfield(item, field_name)
            for field_name in fieldnames(typeof(item))
    )
end

function contract_identity_payload(contract::UsedOtherEvidenceContract)
    return (
        path = contract.path,
        repo_root = contract.repo_root,
        sha256 = contract.sha256,
        contract_id = contract.contract_id,
        classification = contract.classification,
        promotion_status = contract.promotion_status,
        scientific_role = contract.scientific_role,
        policies = sort!(collect(contract.policies); by = first),
        detail_vintage_scope = contract.detail_vintage_scope,
        expected = contract.expected,
        artifacts = [
            struct_fields_payload(contract.artifacts[artifact_id])
                for artifact_id in sort!(collect(keys(contract.artifacts)))
        ],
        components = [
            struct_fields_payload(contract.components[component_code])
                for component_code in sort!(collect(keys(contract.components)))
        ],
        decisions = struct_fields_payload.(contract.decisions),
        literature = struct_fields_payload.(contract.literature),
        forecast_origin_admissible =
            contract.forecast_origin_admissible,
        promotion_ready = contract.promotion_ready,
        model_state_write = contract.model_state_write,
        accounting_gate_effect = contract.accounting_gate_effect,
        forecast_score_write = contract.forecast_score_write,
    )
end

function authenticate_contract(contract::UsedOtherEvidenceContract)
    approved = load_used_other_evidence_contract(
        contract.path;
        repo_root = contract.repo_root,
    )
    isequal(
        contract_identity_payload(contract),
        contract_identity_payload(approved),
    ) ||
        fail(
        "contract",
        "in-memory contract differs from its authenticated bytes",
    )
    return approved
end

"""
Classify a special account strictly by code. `label` is retained only to make
the code-first behavior explicit to callers and adversarial tests.
"""
function classify_special_account(code::AbstractString, label::AbstractString)
    account_code = String(code)
    String(label)
    if haskey(COMPONENT_TYPES, account_code)
        return (
            account_code = account_code,
            aggregate_account_code = COMPONENT_TO_AGGREGATE[account_code],
            component_code = account_code,
            economic_type = COMPONENT_TYPES[account_code],
        )
    elseif account_code in SUMMARY_CODES
        return (
            account_code = account_code,
            aggregate_account_code = account_code,
            component_code = "",
            economic_type = AGGREGATE_TYPE,
        )
    end
    return fail(
        "special_account.code",
        "unknown code $account_code; labels cannot select an account",
    )
end

function locate_special_axis(row_code, row_label, column_code, column_label)
    row_special = row_code in ALL_SPECIAL_CODES
    column_special = column_code in ALL_SPECIAL_CODES
    xor(row_special, column_special) ||
        fail(
        "source.special_axis",
        "expected exactly one code-keyed special axis, got row=$row_code column=$column_code",
    )
    if row_special
        classification = classify_special_account(row_code, row_label)
        return (
            account_axis = "ROW",
            account_label = row_label,
            counterparty_code = column_code,
            classification = classification,
        )
    end
    classification = classify_special_account(column_code, column_label)
    return (
        account_axis = "COLUMN",
        account_label = column_label,
        counterparty_code = row_code,
        classification = classification,
    )
end

function sign_class(value::Float64)
    if value < 0
        return "NEGATIVE"
    elseif value > 0
        return "POSITIVE"
    end
    return "ZERO"
end

function masks_for_cell_kind(kind::String, value::Float64, source_fixture_id)
    if source_fixture_id == "bea_after_redefinitions_2017_special_accounts"
        kind in ("numeric", "blank", "ellipsis") ||
            fail("source.2017.cell_kind", "unexpected kind $kind")
        numeric = kind == "numeric"
        blank = kind == "blank"
        ellipsis = kind == "ellipsis"
        selected_zero = blank || ellipsis
    elseif source_fixture_id ==
            "bea_after_redefinitions_2024_summary_used_other"
        kind in ("numeric", "selected_zero_not_shown") ||
            fail("source.2024.cell_kind", "unexpected kind $kind")
        numeric = kind == "numeric"
        blank = false
        ellipsis = false
        selected_zero = kind == "selected_zero_not_shown"
    else
        fail("source.fixture_id", "unknown fixture $source_fixture_id")
    end
    selected_zero && !iszero(value) &&
        fail("source.cell_kind", "selected-zero cell is nonzero")
    return (
        numeric = numeric,
        blank = blank,
        ellipsis = ellipsis,
        selected_zero = selected_zero,
        explicit_numeric_zero = numeric && iszero(value),
    )
end

function observation_from_2017(row)
    projection_id = String(row.projection_id)
    projection_id in EXPECTED_2017_PROJECTIONS ||
        fail("source.2017.projection_id", "unexpected $projection_id")
    row_code = String(row.row_code)
    row_description = String(row.row_description)
    column_code = String(row.column_code)
    column_description = String(row.column_description)
    row_summary_code = string_value(row.row_summary_industry_code)
    column_summary_code = string_value(row.column_summary_industry_code)
    located = locate_special_axis(
        row_code,
        row_description,
        column_code,
        column_description,
    )
    counterparty_code = if located.account_axis == "ROW"
        isempty(column_summary_code) ? column_code : column_summary_code
    else
        isempty(row_summary_code) ? row_code : row_summary_code
    end
    source_level = String(row.source_level)
    source_level in ("detail", "summary") ||
        fail("source.2017.source_level", "unexpected $source_level")
    expected_codes =
        source_level == "detail" ? Set(DETAIL_CODES) : Set(SUMMARY_CODES)
    located.classification.account_code in expected_codes ||
        fail(
        "source.2017.account_code",
        "code does not match source level",
    )
    value = Float64(row.value)
    kind = String(row.source_cell_kind)
    masks = masks_for_cell_kind(
        kind,
        value,
        "bea_after_redefinitions_2017_special_accounts",
    )
    row_position = Int(row.row_position)
    column_position = Int(row.column_position)
    source_record_key =
        "$projection_id|r=$row_position|c=$column_position"
    vintage_scope =
        source_level == "detail" ?
        "BENCHMARK_2017_DETAILED_COMPONENT_EVIDENCE" :
        "BENCHMARK_2017_INDEPENDENT_SUMMARY_EVIDENCE"
    return EvidenceObservation(
        OBSERVATION_SCHEMA,
        "bea_2017_$projection_id" *
            "_r$(lpad(row_position, 3, '0'))" *
            "_c$(lpad(column_position, 3, '0'))",
        "bea_after_redefinitions_2017_special_accounts",
        source_record_key,
        2017,
        vintage_scope,
        source_level,
        projection_id,
        String(row.source_table),
        PROJECTION_SOURCE_ROLES[projection_id],
        located.account_axis,
        located.classification.account_code,
        located.classification.aggregate_account_code,
        located.classification.component_code,
        located.classification.economic_type,
        row_position,
        row_code,
        row_description,
        column_position,
        column_code,
        column_description,
        counterparty_code,
        String(row.source_address),
        value,
        sign_class(value),
        kind,
        masks.numeric,
        masks.blank,
        masks.ellipsis,
        masks.selected_zero,
        masks.explicit_numeric_zero,
        false,
        "PRODUCERS_PRICES",
        "MILLIONS_OF_CURRENT_DOLLARS",
        false,
        false,
    )
end

function observation_from_2024(row)
    projection_id = String(row.matrix_id)
    projection_id in EXPECTED_2024_PROJECTIONS ||
        fail("source.2024.projection_id", "unexpected $projection_id")
    row_code = String(row.row_code)
    row_description = String(row.row_description)
    column_code = String(row.column_code)
    column_description = String(row.column_description)
    located = locate_special_axis(
        row_code,
        row_description,
        column_code,
        column_description,
    )
    located.classification.account_code in SUMMARY_CODES ||
        fail(
        "source.2024.account_code",
        "detailed component appeared in summary fixture",
    )
    value = Float64(row.value)
    kind = String(row.source_cell_kind)
    masks = masks_for_cell_kind(
        kind,
        value,
        "bea_after_redefinitions_2024_summary_used_other",
    )
    row_position = Int(row.row_position)
    column_position = Int(row.column_position)
    source_record_key =
        "$projection_id|r=$row_position|c=$column_position"
    source_table = startswith(projection_id, "import_") ?
        "import_matrix" :
        startswith(projection_id, "producer_make") ?
        "producer_make" : "producer_use"
    return EvidenceObservation(
        OBSERVATION_SCHEMA,
        "bea_2024_$projection_id" *
            "_r$(lpad(row_position, 3, '0'))" *
            "_c$(lpad(column_position, 3, '0'))",
        "bea_after_redefinitions_2024_summary_used_other",
        source_record_key,
        2024,
        "CURRENT_2024_SUMMARY_COMPOSITE_EVIDENCE",
        "summary",
        projection_id,
        source_table,
        PROJECTION_SOURCE_ROLES[projection_id],
        located.account_axis,
        located.classification.account_code,
        located.classification.aggregate_account_code,
        located.classification.component_code,
        located.classification.economic_type,
        row_position,
        row_code,
        row_description,
        column_position,
        column_code,
        column_description,
        located.counterparty_code,
        "$(projection_id)!R$(row_position)C$(column_position)",
        value,
        sign_class(value),
        kind,
        masks.numeric,
        masks.blank,
        masks.ellipsis,
        masks.selected_zero,
        masks.explicit_numeric_zero,
        false,
        "PRODUCERS_PRICES",
        "MILLIONS_OF_CURRENT_DOLLARS",
        false,
        false,
    )
end

function load_source_observations(contract)
    source_2017 = contract.artifacts["special_2017_cells"].path
    observations_2017 =
        EvidenceObservation[observation_from_2017(row) for row in CSV.File(source_2017)]
    length(observations_2017) == 3_644 ||
        fail("source.2017", "cell count changed")

    source_2024 = contract.artifacts["common_basis_2024_cells"].path
    observations_2024 = EvidenceObservation[]
    for row in CSV.File(source_2024)
        Int(row.year) == 2024 || continue
        row_code = String(row.row_code)
        column_code = String(row.column_code)
        (row_code in SUMMARY_CODES || column_code in SUMMARY_CODES) ||
            continue
        push!(observations_2024, observation_from_2024(row))
    end
    length(observations_2024) == 518 ||
        fail("source.2024", "Used/Other cell count changed")

    observations = vcat(observations_2017, observations_2024)
    sort!(
        observations;
        by = item -> (
            item.year,
            item.source_fixture_id,
            item.projection_id,
            item.row_position,
            item.column_position,
        ),
    )
    return observations
end

function select_observations(
        observations;
        year = nothing,
        projection_id = nothing,
        account_code = nothing,
        counterparty_code = nothing,
    )
    return filter(observations) do item
        (year === nothing || item.year == year) &&
            (
            projection_id === nothing ||
                item.projection_id == projection_id
        ) &&
            (
            account_code === nothing ||
                item.account_code == account_code
        ) &&
            (
            counterparty_code === nothing ||
                item.counterparty_code == counterparty_code
        )
    end
end

function source_value(
        observations,
        projection_id,
        account_code,
        counterparty_code,
    )
    selected = select_observations(
        observations;
        projection_id = projection_id,
        account_code = account_code,
        counterparty_code = counterparty_code,
    )
    length(selected) == 1 ||
        fail(
        "source_value",
        "expected one $projection_id/$account_code/$counterparty_code cell, got $(length(selected))",
    )
    return only(selected).value_millions
end

function source_cell_kind(
        observations,
        projection_id,
        account_code,
        counterparty_code,
    )
    selected = select_observations(
        observations;
        projection_id = projection_id,
        account_code = account_code,
        counterparty_code = counterparty_code,
    )
    length(selected) == 1 ||
        fail(
        "source_cell_kind",
        "expected one $projection_id/$account_code/$counterparty_code cell",
    )
    return only(selected).native_cell_kind
end

function source_sum(observations, projection_id, account_code)
    return sum(
        item.value_millions
            for item in select_observations(
                observations;
                projection_id = projection_id,
                account_code = account_code,
            )
    )
end

function nonzero_source_count(observations, projection_id, account_code)
    return count(
        !iszero(item.value_millions)
            for item in select_observations(
                observations;
                projection_id = projection_id,
                account_code = account_code,
            )
    )
end

function make_check(
        check_id,
        source_year,
        account_code,
        equation,
        lhs,
        rhs,
        tolerance,
        evidence_scope,
    )
    left = Float64(lhs)
    right = Float64(rhs)
    residual = left - right
    threshold = Float64(tolerance)
    status =
        threshold == 0.0 ? "PASS_SOURCE_EVIDENCE" :
        "PASS_SOURCE_ROUNDING"
    return SourceCheck(
        CHECK_SCHEMA,
        String(check_id),
        status,
        Int(source_year),
        String(account_code),
        String(equation),
        left,
        right,
        residual,
        abs(residual),
        threshold,
        String(evidence_scope),
        false,
        false,
    )
end

function detail_components_for_aggregate(aggregate_code)
    aggregate_code == "Used" && return ["S00401", "S00402"]
    aggregate_code == "Other" && return ["S00300", "S00900"]
    return fail("aggregate_code", "unknown aggregate $aggregate_code")
end

function aggregate_control_reconstruction_check(
        observations,
        aggregate_code,
        control_code,
    )
    components = detail_components_for_aggregate(aggregate_code)
    detail_value = sum(
        source_value(
                observations,
                "detail_use_controls_2017",
                component,
                control_code,
            )
            for component in components
    )
    summary_value = source_value(
        observations,
        "summary_use_controls_2017",
        aggregate_code,
        control_code,
    )
    return make_check(
        "2017_$(lowercase(aggregate_code))_$(lowercase(control_code))_reconstruction",
        2017,
        aggregate_code,
        "sum(code-keyed detailed components) = independently published summary control",
        detail_value,
        summary_value,
        0.0,
        "2017_COMPONENT_TO_SUMMARY_CONTROL",
    )
end

function final_cell_maximum_residual_check(observations, aggregate_code)
    components = detail_components_for_aggregate(aggregate_code)
    summary_cells = select_observations(
        observations;
        projection_id = "summary_use_final_2017",
        account_code = aggregate_code,
    )
    length(summary_cells) == 20 ||
        fail("2017.final_use.$aggregate_code", "cell count changed")
    residuals = Float64[]
    for summary_cell in summary_cells
        detailed_value = sum(
            source_value(
                    observations,
                    "detail_use_final_2017",
                    component,
                    summary_cell.counterparty_code,
                )
                for component in components
        )
        push!(residuals, summary_cell.value_millions - detailed_value)
    end
    maximum_absolute_residual = maximum(abs, residuals)
    return make_check(
        "2017_$(lowercase(aggregate_code))_final_cell_maximum_residual",
        2017,
        aggregate_code,
        "maximum absolute independently rounded summary-minus-detail final-use cell",
        maximum_absolute_residual,
        0.0,
        1.0,
        "2017_CODE_KEYED_FINAL_USE_RECONSTRUCTION",
    )
end

function component_use_output_check(observations, component_code)
    intermediate = source_value(
        observations,
        "detail_use_controls_2017",
        component_code,
        "T001",
    )
    final_use = source_value(
        observations,
        "detail_use_controls_2017",
        component_code,
        "T004",
    )
    output = source_value(
        observations,
        "detail_use_controls_2017",
        component_code,
        "T007",
    )
    return make_check(
        "2017_$(lowercase(component_code))_use_output_identity",
        2017,
        component_code,
        "published T001 + published T004 = published T007",
        intermediate + final_use,
        output,
        0.0,
        component_code == "S00402" ?
            "SOURCE_SUPPORTED_EXISTING_GOOD_TRANSFER_WITH_ZERO_UNDERLYING_OUTPUT" :
            component_code == "S00401" ?
            "MIXED_SCRAP_CURRENT_BYPRODUCT_OUTPUT_AND_FINAL_USER_DISPOSAL" :
            "2017_DETAILED_SOURCE_CONTROL_IDENTITY",
    )
end

function component_make_output_check(observations, component_code)
    placements =
        source_sum(observations, "detail_make_components_2017", component_code)
    output = source_value(
        observations,
        "detail_make_output_2017",
        component_code,
        "T007",
    )
    tolerance = component_code == "S00401" ? 2.0 : 0.0
    return make_check(
        "2017_$(lowercase(component_code))_make_to_output",
        2017,
        component_code,
        "sum(published detailed make placements) = published output control",
        placements,
        output,
        tolerance,
        "2017_DETAILED_MAKE_PLACEMENT_ROUNDING",
    )
end

function component_make_placement_count_check(
        observations,
        component::ComponentRule,
    )
    count_observed = nonzero_source_count(
        observations,
        "detail_make_components_2017",
        component.component_code,
    )
    return make_check(
        "2017_$(lowercase(component.component_code))_make_placement_count",
        2017,
        component.component_code,
        "nonzero source make placement count = frozen component evidence count",
        count_observed,
        component.observed_2017_make_placement_count,
        0.0,
        "SOURCE_ACCOUNTING_PLACEMENT_NOT_PRODUCER_INFERENCE",
    )
end

function make_to_output_2024_check(observations, aggregate_code)
    placements =
        source_sum(observations, "producer_make_2024", aggregate_code)
    output = source_value(
        observations,
        "producer_make_commodity_output_2024",
        aggregate_code,
        "T007",
    )
    return make_check(
        "2024_$(lowercase(aggregate_code))_make_to_output",
        2024,
        aggregate_code,
        "sum(summary make placements) = published summary output control",
        placements,
        output,
        0.0,
        "2024_SUMMARY_COMPOSITE_ONLY_NO_COMPONENT_SPLIT",
    )
end

function producer_control_identity_2024_check(
        observations,
        aggregate_code,
    )
    t001 = source_value(
        observations,
        "producer_use_commodity_controls_2024",
        aggregate_code,
        "T001",
    )
    t004 = source_value(
        observations,
        "producer_use_commodity_controls_2024",
        aggregate_code,
        "T004",
    )
    t007 = source_value(
        observations,
        "producer_use_commodity_controls_2024",
        aggregate_code,
        "T007",
    )
    return make_check(
        "2024_$(lowercase(aggregate_code))_producer_control_identity",
        2024,
        aggregate_code,
        "published producer T001 + T004 = published T007",
        t001 + t004,
        t007,
        aggregate_code == "Other" ? 1.0 : 0.0,
        "2024_INDEPENDENTLY_ROUNDED_SUMMARY_CONTROLS",
    )
end

function import_control_identity_2024_check(observations, aggregate_code)
    t001 = source_value(
        observations,
        "import_commodity_controls_2024",
        aggregate_code,
        "T001",
    )
    t004 = source_value(
        observations,
        "import_commodity_controls_2024",
        aggregate_code,
        "T004",
    )
    return make_check(
        "2024_$(lowercase(aggregate_code))_import_control_identity",
        2024,
        aggregate_code,
        "published import T001 + T004 = zero",
        t001 + t004,
        0.0,
        0.0,
        "2024_SUMMARY_IMPORT_BOUNDARY_CONTROL",
    )
end

function cells_to_control_2024_check(
        observations,
        aggregate_code,
        source_kind,
    )
    if source_kind == :producer_intermediate
        projection_id = "producer_intermediate_use_2024"
        controls_id = "producer_use_commodity_controls_2024"
        control_code = "T001"
        tolerance = 36.0
        suffix = "producer_intermediate_to_control"
    elseif source_kind == :producer_final
        projection_id = "producer_final_use_2024"
        controls_id = "producer_use_commodity_controls_2024"
        control_code = "T004"
        tolerance = 10.0
        suffix = "producer_final_to_control"
    elseif source_kind == :import_intermediate
        projection_id = "import_intermediate_use_2024"
        controls_id = "import_commodity_controls_2024"
        control_code = "T001"
        tolerance = 36.0
        suffix = "import_intermediate_to_control"
    elseif source_kind == :import_final
        projection_id = "import_final_use_2024"
        controls_id = "import_commodity_controls_2024"
        control_code = "T004"
        tolerance = 10.0
        suffix = "import_final_to_control"
    else
        fail("source_kind", "unexpected $source_kind")
    end
    cells = source_sum(observations, projection_id, aggregate_code)
    control =
        source_value(observations, controls_id, aggregate_code, control_code)
    return make_check(
        "2024_$(lowercase(aggregate_code))_$suffix",
        2024,
        aggregate_code,
        "sum(published summary cells) = independently published summary control",
        cells,
        control,
        tolerance,
        "SOURCE_ROUNDING_ONLY_NO_CORRECTION",
    )
end

function detailed_years_from_inventory(contract)
    inventory = load_detail_scope_inventory(contract)
    years = Int[]
    for workbook in inventory["workbook"]
        workbook["level"] == "DETAIL" || continue
        append!(
            years,
            parse.(
                Int,
                filter(
                    sheet_name -> all(isdigit, sheet_name),
                    String.(workbook["sheet_names"]),
                ),
            ),
        )
    end
    return sort!(unique(years))
end

function build_source_checks(observations, contract)
    detailed_years = detailed_years_from_inventory(contract)
    checks = SourceCheck[
        make_check(
            "newer_than_2017_detail_vintage_absence",
            2024,
            "DETAIL_SCOPE",
            "count(detail vintages later than 2017 in the pinned archive-derived workbook inventory) = 0",
            count(year -> year > 2017, detailed_years),
            0.0,
            0.0,
            "PINNED_ARCHIVE_DERIVED_WORKBOOK_SHEET_INVENTORY",
        ),
    ]
    for aggregate_code in SUMMARY_CODES
        for control_code in ("T001", "T004", "T007")
            push!(
                checks,
                aggregate_control_reconstruction_check(
                    observations,
                    aggregate_code,
                    control_code,
                ),
            )
        end
    end
    for aggregate_code in SUMMARY_CODES
        push!(
            checks,
            final_cell_maximum_residual_check(
                observations,
                aggregate_code,
            ),
        )
    end
    for component_code in DETAIL_CODES
        push!(
            checks,
            component_use_output_check(observations, component_code),
        )
    end
    for component_code in DETAIL_CODES
        push!(
            checks,
            component_make_output_check(observations, component_code),
        )
    end
    for component_code in DETAIL_CODES
        push!(
            checks,
            component_make_placement_count_check(
                observations,
                contract.components[component_code],
            ),
        )
    end
    for aggregate_code in SUMMARY_CODES
        push!(
            checks,
            make_to_output_2024_check(observations, aggregate_code),
        )
    end
    for aggregate_code in SUMMARY_CODES
        push!(
            checks,
            producer_control_identity_2024_check(
                observations,
                aggregate_code,
            ),
        )
    end
    for aggregate_code in SUMMARY_CODES
        push!(
            checks,
            import_control_identity_2024_check(
                observations,
                aggregate_code,
            ),
        )
    end
    for source_kind in (
            :producer_intermediate,
            :producer_final,
            :import_intermediate,
            :import_final,
        )
        for aggregate_code in SUMMARY_CODES
            push!(
                checks,
                cells_to_control_2024_check(
                    observations,
                    aggregate_code,
                    source_kind,
                ),
            )
        end
    end
    getfield.(checks, :check_id) == EXPECTED_CHECK_IDS ||
        fail("source_checks", "check order or ids changed")
    return checks
end

function component_evidence(component::ComponentRule)
    return ComponentEvidence(
        COMPONENT_SCHEMA,
        component.component_code,
        component.label,
        component.aggregate_code,
        component.economic_type,
        component.source_use_role,
        component.source_make_role,
        join(component.literature_ids, ";"),
        component.observed_2017_intermediate_millions,
        component.observed_2017_final_use_millions,
        component.observed_2017_output_millions,
        component.observed_2017_output_cell_kind,
        component.observed_2017_make_placement_count,
        component.observed_2017_make_placement_sum_millions,
        component.current_production_output,
        component.existing_asset_transfer,
        component.import_boundary,
        component.reclassification,
        component.structural_zero_claimed,
        component.source_make_placement_is_producer_inference,
        component.allocation_2024_status,
        component.runtime_target_namespace,
        component.mapping_applied,
    )
end

function decision_assessment(decision::DecisionSpec)
    return UsedOtherDecision(
        DECISION_SCHEMA,
        decision.decision_id,
        decision.status,
        missing,
        missing,
        decision.blocker,
        decision.required_evidence,
        join(decision.literature_ids, ";"),
        decision.mapping_applied,
        decision.output_emitted,
        decision.target_namespace,
        false,
    )
end

function report_summary(
        observations,
        components,
        checks,
        decisions,
        literature,
    )
    observations_2017 = filter(item -> item.year == 2017, observations)
    observations_2024 = filter(item -> item.year == 2024, observations)
    observations_2017_detail =
        filter(item -> item.source_level == "detail", observations_2017)
    observations_2017_summary =
        filter(item -> item.source_level == "summary", observations_2017)
    return Dict{String, Any}(
        "observation_count" => length(observations),
        "observation_2017_count" => length(observations_2017),
        "observation_2017_detail_count" =>
            length(observations_2017_detail),
        "observation_2017_summary_count" =>
            length(observations_2017_summary),
        "observation_2024_summary_count" => length(observations_2024),
        "numeric_cell_count" =>
            count(item -> item.numeric_mask, observations),
        "native_blank_count" =>
            count(item -> item.native_blank_mask, observations),
        "native_ellipsis_count" =>
            count(item -> item.native_ellipsis_mask, observations),
        "selected_zero_not_shown_count" => count(
            item -> item.selected_zero_not_shown_mask,
            observations,
        ),
        "explicit_numeric_zero_count" =>
            count(item -> item.explicit_numeric_zero, observations),
        "negative_cell_count" =>
            count(item -> item.value_millions < 0, observations),
        "component_count" => length(components),
        "source_check_count" => length(checks),
        "decision_count" => length(decisions),
        "blocked_decision_count" =>
            count(item -> item.status == "NOT_RUN_BLOCKED", decisions),
        "literature_count" => length(literature),
        "newer_than_2017_detail_vintage_count" => 0,
        "projected_2017_share_count" => 0,
        "dealer_margin_allocation_count" => 0,
        "transport_service_allocation_count" => 0,
        "component_allocation_2024_count" => 0,
        "core_absorption_count" => 0,
        "model_absorption_count" => 0,
        "government_producer_inference_count" => 0,
        "row_behavior_inference_count" => 0,
        "model_state_write_count" => 0,
        "gate_effect_count" => 0,
        "origin_admissible_output_count" => 0,
        "forecast_score_write_count" => 0,
    )
end

function _build_used_other_evidence(contract, observations)
    components =
        ComponentEvidence[
        component_evidence(contract.components[code]) for code in DETAIL_CODES
    ]
    checks = build_source_checks(observations, contract)
    decisions = decision_assessment.(contract.decisions)
    literature = deepcopy(contract.literature)
    summary =
        report_summary(observations, components, checks, decisions, literature)
    return UsedOtherEvidenceReport(
        contract.classification,
        contract.promotion_status,
        observations,
        components,
        checks,
        decisions,
        literature,
        summary,
        false,
        false,
        false,
        :none,
        false,
    )
end

observation_payload(item::EvidenceObservation) = (
    schema_version = item.schema_version,
    record_id = item.record_id,
    source_fixture_id = item.source_fixture_id,
    source_record_key = item.source_record_key,
    year = item.year,
    vintage_scope = item.vintage_scope,
    source_level = item.source_level,
    projection_id = item.projection_id,
    source_table = item.source_table,
    source_role = item.source_role,
    account_axis = item.account_axis,
    account_code = item.account_code,
    aggregate_account_code = item.aggregate_account_code,
    component_code = item.component_code,
    economic_type = item.economic_type,
    row_position = item.row_position,
    row_code = item.row_code,
    row_description = item.row_description,
    column_position = item.column_position,
    column_code = item.column_code,
    column_description = item.column_description,
    counterparty_code = item.counterparty_code,
    source_locator = item.source_locator,
    value_millions = item.value_millions,
    sign_class = item.sign_class,
    native_cell_kind = item.native_cell_kind,
    numeric_mask = item.numeric_mask,
    native_blank_mask = item.native_blank_mask,
    native_ellipsis_mask = item.native_ellipsis_mask,
    selected_zero_not_shown_mask = item.selected_zero_not_shown_mask,
    explicit_numeric_zero = item.explicit_numeric_zero,
    structural_zero_claimed = item.structural_zero_claimed,
    price_basis = item.price_basis,
    unit = item.unit,
    source_make_placement_is_producer_inference =
        item.source_make_placement_is_producer_inference,
    mapping_applied = item.mapping_applied,
)

component_payload(item::ComponentEvidence) = (
    schema_version = item.schema_version,
    component_code = item.component_code,
    label = item.label,
    aggregate_code = item.aggregate_code,
    economic_type = item.economic_type,
    source_use_role = item.source_use_role,
    source_make_role = item.source_make_role,
    literature_ids = item.literature_ids,
    observed_2017_intermediate_millions =
        item.observed_2017_intermediate_millions,
    observed_2017_final_use_millions =
        item.observed_2017_final_use_millions,
    observed_2017_output_millions = item.observed_2017_output_millions,
    observed_2017_output_cell_kind =
        item.observed_2017_output_cell_kind,
    observed_2017_make_placement_count =
        item.observed_2017_make_placement_count,
    observed_2017_make_placement_sum_millions =
        item.observed_2017_make_placement_sum_millions,
    current_production_output = item.current_production_output,
    existing_asset_transfer = item.existing_asset_transfer,
    import_boundary = item.import_boundary,
    reclassification = item.reclassification,
    structural_zero_claimed = item.structural_zero_claimed,
    source_make_placement_is_producer_inference =
        item.source_make_placement_is_producer_inference,
    allocation_2024_status = item.allocation_2024_status,
    runtime_target_namespace = item.runtime_target_namespace,
    mapping_applied = item.mapping_applied,
)

check_payload(item::SourceCheck) = (
    schema_version = item.schema_version,
    check_id = item.check_id,
    status = item.status,
    source_year = item.source_year,
    account_code = item.account_code,
    equation = item.equation,
    lhs = item.lhs,
    rhs = item.rhs,
    residual = item.residual,
    absolute_residual = item.absolute_residual,
    tolerance = item.tolerance,
    evidence_scope = item.evidence_scope,
    correction_applied = item.correction_applied,
    mapping_applied = item.mapping_applied,
)

decision_payload(item::UsedOtherDecision) = (
    schema_version = item.schema_version,
    decision_id = item.decision_id,
    status = item.status,
    diagnostic_value = item.diagnostic_value,
    tolerance = item.tolerance,
    blocker = item.blocker,
    required_evidence = item.required_evidence,
    literature_ids = item.literature_ids,
    mapping_applied = item.mapping_applied,
    output_emitted = item.output_emitted,
    target_namespace = item.target_namespace,
    forecast_origin_admissible = item.forecast_origin_admissible,
)

literature_payload(item::LiteratureEvidence) = (
    schema_version = item.schema_version,
    literature_id = item.literature_id,
    authority = item.authority,
    title = item.title,
    version = item.version,
    url = item.url,
    locator = item.locator,
    document_sha256 = item.document_sha256,
    accessed_on = item.accessed_on,
    source_fact = item.source_fact,
    project_decision = item.project_decision,
    uncertainty = item.uncertainty,
    test_ids = item.test_ids,
)

function validate_observation(item)
    item.schema_version == OBSERVATION_SCHEMA ||
        fail("observation.$(item.record_id).schema_version", "changed")
    item.year in (2017, 2024) ||
        fail("observation.$(item.record_id).year", "unexpected")
    item.projection_id in keys(PROJECTION_SOURCE_ROLES) ||
        fail("observation.$(item.record_id).projection_id", "unexpected")
    item.source_role == PROJECTION_SOURCE_ROLES[item.projection_id] ||
        fail("observation.$(item.record_id).source_role", "changed")
    item.account_axis in ("ROW", "COLUMN") ||
        fail("observation.$(item.record_id).account_axis", "unexpected")
    classification =
        classify_special_account(item.account_code, "ignored-label")
    item.aggregate_account_code ==
        classification.aggregate_account_code ||
        fail(
        "observation.$(item.record_id).aggregate_account_code",
        "is not code keyed",
    )
    item.component_code == classification.component_code ||
        fail(
        "observation.$(item.record_id).component_code",
        "is not code keyed",
    )
    item.economic_type == classification.economic_type ||
        fail(
        "observation.$(item.record_id).economic_type",
        "is not code keyed",
    )
    isfinite(item.value_millions) ||
        fail("observation.$(item.record_id).value_millions", "not finite")
    item.sign_class == sign_class(item.value_millions) ||
        fail("observation.$(item.record_id).sign_class", "changed")
    state_count =
        Int(item.numeric_mask) +
        Int(item.native_blank_mask) +
        Int(item.native_ellipsis_mask) +
        Int(
        item.selected_zero_not_shown_mask &&
            !item.native_blank_mask &&
            !item.native_ellipsis_mask,
    )
    state_count == 1 ||
        fail(
        "observation.$(item.record_id).cell_masks",
        "not disjoint and exhaustive",
    )
    item.selected_zero_not_shown_mask ==
        (
        item.native_blank_mask ||
            item.native_ellipsis_mask ||
            item.native_cell_kind == "selected_zero_not_shown"
    ) ||
        fail(
        "observation.$(item.record_id).selected_zero_not_shown_mask",
        "changed",
    )
    item.explicit_numeric_zero ==
        (item.numeric_mask && iszero(item.value_millions)) ||
        fail(
        "observation.$(item.record_id).explicit_numeric_zero",
        "changed",
    )
    item.selected_zero_not_shown_mask && !iszero(item.value_millions) &&
        fail(
        "observation.$(item.record_id).value_millions",
        "selected-zero cell is nonzero",
    )
    item.structural_zero_claimed &&
        fail(
        "observation.$(item.record_id).structural_zero_claimed",
        "must remain false",
    )
    item.source_make_placement_is_producer_inference &&
        fail(
        "observation.$(item.record_id).source_make_placement_is_producer_inference",
        "must remain false",
    )
    item.mapping_applied &&
        fail(
        "observation.$(item.record_id).mapping_applied",
        "must remain false",
    )
    item.price_basis == "PRODUCERS_PRICES" ||
        fail("observation.$(item.record_id).price_basis", "changed")
    item.unit == "MILLIONS_OF_CURRENT_DOLLARS" ||
        fail("observation.$(item.record_id).unit", "changed")
    if item.year == 2017 && item.source_level == "detail"
        item.account_code in DETAIL_CODES ||
            fail(
            "observation.$(item.record_id).account_code",
            "2017 detail code changed",
        )
    elseif item.year == 2017 && item.source_level == "summary"
        item.account_code in SUMMARY_CODES ||
            fail(
            "observation.$(item.record_id).account_code",
            "2017 summary code changed",
        )
    elseif item.year == 2024
        item.source_level == "summary" ||
            fail(
            "observation.$(item.record_id).source_level",
            "2024 must remain summary",
        )
        item.account_code in SUMMARY_CODES ||
            fail(
            "observation.$(item.record_id).account_code",
            "2024 detailed allocation appeared",
        )
        isempty(item.component_code) ||
            fail(
            "observation.$(item.record_id).component_code",
            "2024 component allocation appeared",
        )
    else
        fail("observation.$(item.record_id)", "invalid vintage namespace")
    end
    return nothing
end

function validate_component_against_source(
        item::ComponentEvidence,
        observations,
    )
    code = item.component_code
    intermediate = source_value(
        observations,
        "detail_use_controls_2017",
        code,
        "T001",
    )
    final_use = source_value(
        observations,
        "detail_use_controls_2017",
        code,
        "T004",
    )
    output = source_value(
        observations,
        "detail_use_controls_2017",
        code,
        "T007",
    )
    output_kind = source_cell_kind(
        observations,
        "detail_use_controls_2017",
        code,
        "T007",
    )
    placements =
        source_sum(observations, "detail_make_components_2017", code)
    placement_count = nonzero_source_count(
        observations,
        "detail_make_components_2017",
        code,
    )
    (
        item.observed_2017_intermediate_millions,
        item.observed_2017_final_use_millions,
        item.observed_2017_output_millions,
        item.observed_2017_output_cell_kind,
        item.observed_2017_make_placement_count,
        item.observed_2017_make_placement_sum_millions,
    ) == (
        intermediate,
        final_use,
        output,
        output_kind,
        placement_count,
        placements,
    ) || fail("component.$code", "differs from pinned 2017 source")
    item.allocation_2024_status == "NOT_RUN_BLOCKED" ||
        fail("component.$code.allocation_2024_status", "changed")
    isempty(item.runtime_target_namespace) ||
        fail("component.$code.runtime_target_namespace", "must be empty")
    item.mapping_applied &&
        fail("component.$code.mapping_applied", "must remain false")
    item.structural_zero_claimed &&
        fail("component.$code.structural_zero_claimed", "must remain false")
    item.source_make_placement_is_producer_inference &&
        fail(
        "component.$code.source_make_placement_is_producer_inference",
        "must remain false",
    )
    return nothing
end

function validate_special_placements(observations)
    s009_detail = filter(
        item ->
        item.projection_id == "detail_make_components_2017" &&
            item.account_code == "S00900" &&
            !iszero(item.value_millions),
        observations,
    )
    length(s009_detail) == 1 ||
        fail("source.s00900.detail_make", "placement count changed")
    only(s009_detail).row_code == "S00600" ||
        fail("source.s00900.detail_make", "source placement code changed")
    only(s009_detail).value_millions == 3_468.0 ||
        fail("source.s00900.detail_make", "source placement value changed")

    other_summary = filter(
        item ->
        item.projection_id == "summary_make_components_2017" &&
            item.account_code == "Other" &&
            !iszero(item.value_millions),
        observations,
    )
    length(other_summary) == 1 ||
        fail("source.other.summary_make", "placement count changed")
    only(other_summary).row_code == "GFGN" ||
        fail("source.other.summary_make", "source placement code changed")
    only(other_summary).value_millions == 3_468.0 ||
        fail("source.other.summary_make", "source placement value changed")
    return nothing
end

function validate_used_other_evidence(
        report::UsedOtherEvidenceReport,
        contract::UsedOtherEvidenceContract,
    )
    contract = authenticate_contract(contract)
    report.classification == contract.classification ||
        fail("report.classification", "changed")
    report.promotion_status == contract.promotion_status ||
        fail("report.promotion_status", "changed")
    for (value, location) in (
            (
                report.forecast_origin_admissible,
                "report.forecast_origin_admissible",
            ),
            (report.promotion_ready, "report.promotion_ready"),
            (report.model_state_write, "report.model_state_write"),
            (report.forecast_score_write, "report.forecast_score_write"),
        )
        value && fail(location, "must remain false")
    end
    report.accounting_gate_effect == :none ||
        fail("report.accounting_gate_effect", "must remain NONE")

    length(report.observations) ==
        Int(contract.expected["observation_count"]) ||
        fail("report.observations", "count changed")
    length(unique(getfield.(report.observations, :record_id))) ==
        length(report.observations) ||
        fail("report.observations", "record ids duplicate")
    length(
        unique(
            (item.source_fixture_id, item.source_record_key)
                for item in report.observations
        ),
    ) == length(report.observations) ||
        fail("report.observations", "source record keys duplicate")
    foreach(validate_observation, report.observations)
    Set(
        item.projection_id for item in report.observations if item.year == 2017
    ) == EXPECTED_2017_PROJECTIONS ||
        fail("report.observations.2017", "projection set changed")
    Set(
        item.projection_id for item in report.observations if item.year == 2024
    ) == EXPECTED_2024_PROJECTIONS ||
        fail("report.observations.2024", "projection set changed")
    validate_special_placements(report.observations)

    getfield.(report.components, :component_code) == DETAIL_CODES ||
        fail("report.components", "component order or codes changed")
    foreach(
        item -> validate_component_against_source(
            item,
            report.observations,
        ),
        report.components,
    )

    getfield.(report.checks, :check_id) == EXPECTED_CHECK_IDS ||
        fail("report.checks", "check order or ids changed")
    for item in report.checks
        item.schema_version == CHECK_SCHEMA ||
            fail("check.$(item.check_id).schema_version", "changed")
        item.status in ("PASS_SOURCE_EVIDENCE", "PASS_SOURCE_ROUNDING") ||
            fail("check.$(item.check_id).status", "changed")
        item.residual == item.lhs - item.rhs ||
            fail("check.$(item.check_id).residual", "changed")
        item.absolute_residual == abs(item.residual) ||
            fail("check.$(item.check_id).absolute_residual", "changed")
        item.tolerance >= 0 && isfinite(item.tolerance) ||
            fail("check.$(item.check_id).tolerance", "invalid")
        item.absolute_residual <= item.tolerance ||
            fail("check.$(item.check_id)", "does not pass")
        item.correction_applied &&
            fail("check.$(item.check_id).correction_applied", "must be false")
        item.mapping_applied &&
            fail("check.$(item.check_id).mapping_applied", "must be false")
    end

    getfield.(report.decisions, :decision_id) == EXPECTED_DECISION_IDS ||
        fail("report.decisions", "decision order or ids changed")
    for item in report.decisions
        item.schema_version == DECISION_SCHEMA ||
            fail("decision.$(item.decision_id).schema_version", "changed")
        item.status == "NOT_RUN_BLOCKED" ||
            fail("decision.$(item.decision_id).status", "must be blocked")
        ismissing(item.diagnostic_value) ||
            fail(
            "decision.$(item.decision_id).diagnostic_value",
            "must be structurally missing",
        )
        ismissing(item.tolerance) ||
            fail(
            "decision.$(item.decision_id).tolerance",
            "must be structurally missing",
        )
        item.mapping_applied &&
            fail(
            "decision.$(item.decision_id).mapping_applied",
            "must remain false",
        )
        item.output_emitted &&
            fail(
            "decision.$(item.decision_id).output_emitted",
            "must remain false",
        )
        isempty(item.target_namespace) ||
            fail(
            "decision.$(item.decision_id).target_namespace",
            "must remain empty",
        )
        item.forecast_origin_admissible &&
            fail(
            "decision.$(item.decision_id).forecast_origin_admissible",
            "must remain false",
        )
    end

    length(report.literature) ==
        Int(contract.expected["literature_count"]) ||
        fail("report.literature", "count changed")
    Set(getfield.(report.literature, :literature_id)) ==
        EXPECTED_LITERATURE_IDS ||
        fail("report.literature", "literature ids changed")
    for item in report.literature
        item.schema_version == LITERATURE_SCHEMA ||
            fail(
            "literature.$(item.literature_id).schema_version",
            "changed",
        )
        startswith(item.url, "https://") ||
            fail("literature.$(item.literature_id).url", "not HTTPS")
        length(item.document_sha256) == 64 ||
            fail(
            "literature.$(item.literature_id).document_sha256",
            "changed",
        )
        isempty(item.locator) &&
            fail("literature.$(item.literature_id).locator", "empty")
    end

    Set(keys(report.summary)) == EXPECTED_SUMMARY_KEYS ||
        fail("report.summary", "keys changed")
    report.summary == contract.expected ||
        fail("report.summary", "differs from frozen expected counts")

    source = load_source_observations(contract)
    expected_report = _build_used_other_evidence(contract, source)
    observation_payload.(report.observations) ==
        observation_payload.(expected_report.observations) ||
        fail("report.observations", "differs from pinned source")
    component_payload.(report.components) ==
        component_payload.(expected_report.components) ||
        fail("report.components", "differs from contract and source")
    check_payload.(report.checks) == check_payload.(expected_report.checks) ||
        fail("report.checks", "differs from pinned source reconstruction")
    isequal(
        decision_payload.(report.decisions),
        decision_payload.(expected_report.decisions),
    ) || fail("report.decisions", "differs from blocked decision contract")
    literature_payload.(report.literature) ==
        literature_payload.(expected_report.literature) ||
        fail("report.literature", "differs from cited literature contract")
    report.summary == expected_report.summary ||
        fail("report.summary", "differs from deterministic reconstruction")
    return report
end

function build_used_other_evidence(
        contract::UsedOtherEvidenceContract =
            load_used_other_evidence_contract(),
    )
    contract = authenticate_contract(contract)
    observations = load_source_observations(contract)
    report = _build_used_other_evidence(contract, observations)
    return validate_used_other_evidence(report, contract)
end

function allocate_2024_components(::UsedOtherEvidenceReport)
    throw(
        ArgumentError(
            "2024 Used/Other component allocation is NOT_RUN_BLOCKED: the pinned current archive has detail sheets only for 2007, 2012, and 2017",
        ),
    )
end

function project_2017_component_shares_to_2024(
        ::UsedOtherEvidenceReport,
    )
    throw(
        ArgumentError(
            "2017-to-2024 component-share projection is NOT_RUN_BLOCKED and prohibited by the vintage-separation contract",
        ),
    )
end

function materialize_used_other_model_state(::UsedOtherEvidenceReport)
    throw(
        ArgumentError(
            "Used/Other evidence is not a model-state, gate, origin, or score artifact",
        ),
    )
end

function report_manifest(report, contract, hashes)
    return Dict{String, Any}(
        "schema_version" => REPORT_SCHEMA,
        "contract_path" => relpath(contract.path, contract.repo_root),
        "contract_sha256" => contract.sha256,
        "classification" => report.classification,
        "promotion_status" => report.promotion_status,
        "scientific_role" => contract.scientific_role,
        "observation_count" => length(report.observations),
        "observations_csv" => "used_other_observations.csv",
        "observations_csv_sha256" => hashes.observations,
        "component_count" => length(report.components),
        "components_csv" => "used_other_components.csv",
        "components_csv_sha256" => hashes.components,
        "source_check_count" => length(report.checks),
        "source_checks_csv" => "used_other_source_checks.csv",
        "source_checks_csv_sha256" => hashes.checks,
        "blocked_decision_count" => length(report.decisions),
        "decisions_csv" => "used_other_decisions.csv",
        "decisions_csv_sha256" => hashes.decisions,
        "literature_count" => length(report.literature),
        "literature_csv" => "used_other_literature.csv",
        "literature_csv_sha256" => hashes.literature,
        "summary" => deepcopy(report.summary),
        "policies" => deepcopy(contract.policies),
        "detail_vintage_scope" =>
            deepcopy(contract.detail_vintage_scope),
        "artifacts" => [
            Dict{String, Any}(
                    "artifact_id" => artifact_id,
                    "path" => item.relative_path,
                    "sha256" => item.sha256,
                    "role" => item.role,
                )
                for (artifact_id, item) in sort!(
                    collect(contract.artifacts);
                    by = first,
                )
        ],
        "projected_2017_share_count" => 0,
        "dealer_margin_allocation_count" => 0,
        "transport_service_allocation_count" => 0,
        "component_allocation_2024_count" => 0,
        "core_absorption_count" => 0,
        "model_absorption_count" => 0,
        "government_producer_inference_count" => 0,
        "row_behavior_inference_count" => 0,
        "forecast_origin_admissible" => false,
        "promotion_ready" => false,
        "model_state_write" => false,
        "accounting_gate_effect" => "NONE",
        "forecast_score_write" => false,
    )
end

function write_used_other_evidence(
        report::UsedOtherEvidenceReport,
        contract::UsedOtherEvidenceContract,
        output_directory::AbstractString,
    )
    contract = authenticate_contract(contract)
    validate_used_other_evidence(report, contract)
    target = abspath(normpath(String(output_directory)))
    ispath(target) &&
        fail("output_directory", "refusing to overwrite existing path $target")
    parent = dirname(target)
    mkpath(parent)
    temporary = mktempdir(parent)
    observations_path = joinpath(temporary, "used_other_observations.csv")
    components_path = joinpath(temporary, "used_other_components.csv")
    checks_path = joinpath(temporary, "used_other_source_checks.csv")
    decisions_path = joinpath(temporary, "used_other_decisions.csv")
    literature_path = joinpath(temporary, "used_other_literature.csv")
    manifest_path = joinpath(temporary, "manifest.toml")
    try
        CSV.write(
            observations_path,
            observation_payload.(report.observations),
        )
        CSV.write(components_path, component_payload.(report.components))
        CSV.write(checks_path, check_payload.(report.checks))
        CSV.write(decisions_path, decision_payload.(report.decisions))
        CSV.write(
            literature_path,
            literature_payload.(report.literature),
        )
        hashes = (
            observations = file_sha256(observations_path),
            components = file_sha256(components_path),
            checks = file_sha256(checks_path),
            decisions = file_sha256(decisions_path),
            literature = file_sha256(literature_path),
        )
        manifest = report_manifest(report, contract, hashes)
        open(manifest_path, "w") do io
            TOML.print(io, manifest; sorted = true)
        end
        mv(temporary, target)
    finally
        isdir(temporary) && rm(temporary; recursive = true)
    end
    installed = (
        observations = joinpath(target, "used_other_observations.csv"),
        components = joinpath(target, "used_other_components.csv"),
        checks = joinpath(target, "used_other_source_checks.csv"),
        decisions = joinpath(target, "used_other_decisions.csv"),
        literature = joinpath(target, "used_other_literature.csv"),
        manifest = joinpath(target, "manifest.toml"),
    )
    return (
        directory = target,
        observation_count = length(report.observations),
        component_count = length(report.components),
        source_check_count = length(report.checks),
        blocked_decision_count = length(report.decisions),
        literature_count = length(report.literature),
        observations_sha256 = file_sha256(installed.observations),
        components_sha256 = file_sha256(installed.components),
        checks_sha256 = file_sha256(installed.checks),
        decisions_sha256 = file_sha256(installed.decisions),
        literature_sha256 = file_sha256(installed.literature),
        manifest_sha256 = file_sha256(installed.manifest),
    )
end

end # module
