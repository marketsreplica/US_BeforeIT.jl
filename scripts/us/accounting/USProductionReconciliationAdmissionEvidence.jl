module USProductionReconciliationAdmissionEvidence

using CSV
using JSON
using SHA
using TOML

using ..USProductionReconciliationLedger:
    ProductionReconciliationLedger,
    ProductionCellRecord,
    ProductionControlRecord,
    SourceLineageMember,
    TargetLineage,
    ControlLineage,
    build_production_reconciliation_ledger

export CONTRACT_SCHEMA,
    APPROVED_CONTRACT_SHA256,
    AdmissionEvidenceContractError,
    AdmissionSolverBlockedError,
    SourceDisplayRecord,
    ReleaseMarkerReceipt,
    ValuationImportBoundaryEvidence,
    DomesticUsePointRecord,
    ObservationLoading,
    ControlDisplayDiagnostic,
    NegativeCellEvidence,
    CandidateDependenceGroup,
    RevisionVintageReceipt,
    ProductionReconciliationAdmissionEvidenceReport,
    load_admission_evidence_contract,
    build_production_reconciliation_admission_evidence,
    production_reconciliation_admission_evidence_internal_controls_pass,
    production_reconciliation_admission_evidence_controls_pass,
    materialize_production_reconciliation_admission_solver_input,
    write_production_reconciliation_admission_evidence_report,
    normalized_module_sha256

const CONTRACT_SCHEMA =
    "beforeit-us-production-reconciliation-admission-evidence-contract.v1"
const REPORT_SCHEMA =
    "beforeit-us-production-reconciliation-admission-evidence-report.v1"
const STATUS_SCHEMA =
    "beforeit-us-production-reconciliation-admission-evidence-status.v1"
const MANIFEST_SCHEMA =
    "beforeit-us-production-reconciliation-admission-evidence-manifest.v1"
const APPROVED_CONTRACT_SHA256 =
    "35ca8e8b0cbb1ff6d50e510ae1a49a11f4f87fe0c0495aebe3e89012e410d67b"
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "production_reconciliation_admission_evidence.toml")
const DEFAULT_REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const ZERO_SHA256 = repeat("0", 64)
const SELECTED_ZERO_STATE = "SOURCE_SELECTED_ZERO_NOT_SHOWN"
const EXACT_IDENTITY_KIND = "EXACT_ACCOUNTING_IDENTITY"
const MEASURED_MARGIN_KIND = "MEASURED_PUBLISHED_MARGIN"
const PRIMARY_SCENARIO = "AUTHENTICATED_RELEASE_SCOPED_DISPLAY_ZERO"
const COUNTERFACTUAL_SCENARIO =
    "WORKBOOK_LOCAL_NOTE_ONLY_COUNTERFACTUAL"

const TOP_LEVEL_KEYS = Set(
    [
        "schema_version",
        "contract_id",
        "classification",
        "artifact_role",
        "promotion_status",
        "scientific_scope",
        "as_of_date",
        "candidate_problem_scope_hash",
        "candidate_problem_hash",
        "candidate_ledger_contract_sha256",
        "display_semantics_fixture_sha256",
        "display_semantics_manifest_sha256",
        "display_semantics_generator_sha256",
        "solver_admissible",
        "solver_invocation_count",
        "solver_input_cell_count",
        "solver_input_control_count",
        "approved_exact_control_count",
        "approved_structural_zero_count",
        "numerical_reliability_receipt_count",
        "numerical_covariance_receipt_count",
        "adjustment_record_count",
        "forecast_origin_admissible",
        "promotion_ready",
        "model_state_write",
        "accounting_gate_effect",
        "forecast_score_effect",
        "promotion_blockers",
        "display_policy",
        "display_resolution_sensitivity",
        "revision_evidence",
        "implementation",
        "expected",
        "artifact",
        "literature",
    ],
)
const DISPLAY_POLICY_KEYS = Set(
    [
        "primary_scenario_id",
        "counterfactual_scenario_id",
        "producer_selected_ellipsis_source_semantics",
        "producer_selected_ellipsis_published_value_millions",
        "producer_selected_ellipsis_underlying_exactness",
        "producer_selected_ellipsis_structural_zero_status",
        "producer_selected_ellipsis_variance_status",
        "import_selected_ellipsis_primary_semantics",
        "import_selected_ellipsis_counterfactual_semantics",
        "raw_token_preservation",
        "blank_missing_suppressed_inheritance",
    ],
)
const SENSITIVITY_KEYS = Set(
    [
        "enabled_for_diagnostics",
        "assumption_id",
        "display_increment_millions",
        "half_width_per_raw_display_millions",
        "interval_rule",
        "source_certified_rounding_rule",
        "confidence_interval",
        "probability_distribution",
        "variance_from_rounding",
        "solver_weight_effect",
    ],
)
const REVISION_KEYS = Set(
    [
        "current_release_id",
        "current_release_date",
        "current_archive_url",
        "current_archive_sha256",
        "earlier_release_id",
        "earlier_release_date",
        "earlier_archive_url",
        "earlier_archive_sha256",
        "earlier_producer_use_member",
        "earlier_producer_use_sha256",
        "earlier_producer_make_member",
        "earlier_producer_make_sha256",
        "common_reference_year_candidate",
        "archive_hashes_verified_during_development",
        "checked_in_revision_cell_fixture",
        "revision_pair_status",
        "realized_2024_revision_observation_count",
    ],
)
const IMPLEMENTATION_KEYS = Set(
    [
        "module_path",
        "module_hash_policy",
        "module_normalized_sha256",
        "runner_path",
        "runner_sha256",
    ],
)
const ARTIFACT_KEYS =
    Set(["artifact_id", "path", "sha256", "role"])
const LITERATURE_KEYS =
    Set(["literature_id", "title", "url", "role"])
const EXPECTED_KEYS = Set(
    [
        "candidate_cell_count",
        "candidate_control_count",
        "candidate_identity_count",
        "published_control_count",
        "source_lineage_member_count",
        "target_loading_owner_count",
        "measured_control_loading_owner_count",
        "observation_loading_owner_count",
        "observation_loading_count",
        "target_multi_source_owner_count",
        "measured_control_multi_source_owner_count",
        "producer_selected_zero_source_leaf_count",
        "import_selected_zero_source_leaf_count",
        "release_marker_receipt_count",
        "valuation_import_boundary_count",
        "domestic_use_point_count",
        "domestic_use_raw_evaluable_count",
        "domestic_f050_diagnostic_count",
        "primary_evaluable_identity_count",
        "primary_nonevaluable_identity_count",
        "primary_zero_residual_identity_count",
        "primary_nonzero_residual_identity_count",
        "primary_evaluable_published_count",
        "primary_nonevaluable_published_count",
        "primary_zero_residual_published_count",
        "primary_nonzero_residual_published_count",
        "primary_within_sensitivity_count",
        "counterfactual_evaluable_identity_count",
        "counterfactual_nonevaluable_identity_count",
        "counterfactual_zero_residual_identity_count",
        "counterfactual_nonzero_residual_identity_count",
        "counterfactual_evaluable_published_count",
        "counterfactual_nonevaluable_published_count",
        "counterfactual_zero_residual_published_count",
        "counterfactual_nonzero_residual_published_count",
        "counterfactual_within_sensitivity_count",
        "identity_maximum_absolute_residual_millions",
        "published_maximum_absolute_residual_millions",
        "negative_cell_count",
        "source_unresolved_negative_cell_count",
        "literature_supported_negative_cell_count",
        "source_mechanically_typed_negative_cell_count",
        "component_unresolved_signed_cell_count",
        "unresolved_negative_cell_count",
        "candidate_dependence_group_count",
        "revision_vintage_receipt_count",
        "numerical_reliability_receipt_count",
        "numerical_covariance_receipt_count",
        "solver_input_cell_count",
        "solver_input_control_count",
        "approved_exact_control_count",
        "approved_structural_zero_count",
        "adjustment_record_count",
    ],
)
const DISPLAY_FIXTURE_COLUMNS = [
    "record_id",
    "workbook_member",
    "workbook_sha256",
    "sheet",
    "cell_address",
    "record_kind",
    "semantic_class",
    "source_token",
    "exact_text_or_value",
]
const NEGATIVE_SEMANTICS_COLUMNS = [
    "cell_id",
    "expected_raw_value_millions",
    "source_member",
    "source_workbook_sha256",
    "source_sheet",
    "source_cell_address",
    "evidence_classification_key",
    "evidence_negative_economic_type",
    "evidence_sign_domain",
    "classification_status",
    "component_resolution_status",
    "evidence_ids",
]
const NEGATIVE_CLASSIFICATION_SIGNATURES = Dict(
    "A" => (
        economic_type = "IMPUTED_IMPORT_ALLOCATION_TO_INVENTORY_CHANGE",
        sign_domain = "SIGNED_FLOW",
        status = "LITERATURE_SUPPORTED_SIGNED_FLOW",
        component_status = "NOT_APPLICABLE_CODE_KEYED_INVENTORY_FLOW",
    ),
    "B" => (
        economic_type =
            "USED_SCRAP_COMPOSITE_FIXED_ASSET_ACQUISITIONS_LESS_DISPOSALS",
        sign_domain = "SIGNED_FLOW",
        status = "LITERATURE_SUPPORTED_SIGN_DOMAIN_COMPONENT_UNRESOLVED",
        component_status =
            "USED_SCRAP_COMPONENT_AND_COUNTERPART_UNRESOLVED_2024",
    ),
    "C" => (
        economic_type =
            "USED_SCRAP_COMPOSITE_NET_SALE_OR_DISPOSAL_BY_INDUSTRY",
        sign_domain = "SIGNED_FLOW",
        status = "LITERATURE_SUPPORTED_SIGN_DOMAIN_COMPONENT_UNRESOLVED",
        component_status =
            "USED_SCRAP_COMPONENT_AND_COUNTERPART_UNRESOLVED_2024",
    ),
    "D" => (
        economic_type =
            "OTHER_NONCOMPARABLE_IMPORTS_ROW_ADJUSTMENT_COMPOSITE_SIGNED_FINAL_USE_RECLASSIFICATION",
        sign_domain = "SIGNED_FLOW",
        status = "LITERATURE_SUPPORTED_SIGN_DOMAIN_COMPONENT_UNRESOLVED",
        component_status = "OTHER_COMPONENT_ATTRIBUTION_UNRESOLVED_2024",
    ),
    "E" => (
        economic_type = "UNRESOLVED_IMPUTED_IMPORT_IPP_NEGATIVE_ALLOCATION",
        sign_domain = "UNRESOLVED_BLOCKED",
        status = "UNRESOLVED_SEMANTIC_BLOCKER",
        component_status = "NO_ADMISSIBLE_ECONOMIC_MECHANISM_ESTABLISHED",
    ),
    "F" => (
        economic_type =
            "UNRESOLVED_IMPUTED_IMPORT_INTERMEDIATE_NEGATIVE_ALLOCATION",
        sign_domain = "UNRESOLVED_BLOCKED",
        status = "UNRESOLVED_SEMANTIC_BLOCKER",
        component_status = "NO_ADMISSIBLE_ECONOMIC_MECHANISM_ESTABLISHED",
    ),
    "G" => (
        economic_type = "UNRESOLVED_NEGATIVE_INDUSTRY_COMMODITY_MAKE",
        sign_domain = "UNRESOLVED_BLOCKED",
        status = "UNRESOLVED_SEMANTIC_BLOCKER",
        component_status = "NO_ADMISSIBLE_ECONOMIC_MECHANISM_ESTABLISHED",
    ),
)

struct AdmissionEvidenceContractError <: Exception
    location::String
    detail::String
end

function Base.showerror(io::IO, error::AdmissionEvidenceContractError)
    return print(io, error.location, ": ", error.detail)
end

struct AdmissionSolverBlockedError <: Exception
    blockers::Vector{String}
end

function Base.showerror(io::IO, error::AdmissionSolverBlockedError)
    return print(
        io,
        "production reconciliation admission remains blocked: ",
        join(error.blockers, ", "),
    )
end

struct EvidenceArtifactBinding
    artifact_id::String
    relative_path::String
    path::String
    sha256::String
    role::String
end

struct LiteratureReference
    literature_id::String
    title::String
    url::String
    role::String
end

struct AdmissionEvidenceContract
    source_sha256::String
    contract_id::String
    classification::String
    artifact_role::String
    promotion_status::String
    scientific_scope::String
    as_of_date::String
    candidate_problem_scope_hash::String
    candidate_problem_hash::String
    candidate_ledger_contract_sha256::String
    display_semantics_fixture_sha256::String
    display_semantics_manifest_sha256::String
    display_semantics_generator_sha256::String
    display_policy::Dict{String, Any}
    sensitivity::Dict{String, Any}
    revision_evidence::Dict{String, Any}
    module_path::String
    module_normalized_sha256::String
    runner_path::String
    runner_sha256::String
    expected::Dict{String, Int}
    artifacts::Dict{String, EvidenceArtifactBinding}
    literature::Vector{LiteratureReference}
    promotion_blockers::Vector{String}
end

struct SourceDisplayRecord
    record_id::String
    workbook_member::String
    workbook_sha256::String
    sheet::String
    cell_address::String
    record_kind::String
    semantic_class::String
    source_token::String
    exact_text_or_value::String
end

struct ReleaseMarkerReceipt
    table_key::String
    title::String
    request_sha256::String
    raw_transport_response_sha256::String
    decoded_response_sha256::String
    canonical_table_sha256::String
    axes_sha256::String
    cell_classes_sha256::String
    api_row_count::Int
    api_column_count::Int
    projection_row_count::Int
    projection_column_count::Int
    projection_cell_count::Int
    marker_count::Int
    literal_zero_count::Int
    marker_coordinate_set_sha256::String
    literal_zero_coordinate_set_sha256::String
    exact_common_basis_coordinate_match::Bool
    canonical_full_grid_sha256::String
    full_grid_exact_match_count::Int
    full_grid_mismatch_count::Int
    full_grid_maximum_absolute_difference_millions::Int
    exact_common_basis_full_grid_match::Bool
    semantic_scope::String
    solver_admissible::Bool
end

struct NegativeSemanticRecord
    cell_id::String
    expected_raw_value_millions::Float64
    source_member::String
    source_workbook_sha256::String
    source_sheet::String
    source_cell_address::String
    evidence_classification_key::String
    evidence_negative_economic_type::String
    evidence_sign_domain::String
    classification_status::String
    component_resolution_status::String
    evidence_ids::String
end

struct ValuationImportBoundaryEvidence
    boundary_id::String
    evidence_status::String
    source_basis::String
    permitted_diagnostic_use::String
    prohibited_operation::String
    blocker_id::String
    solver_admissible::Bool
end

struct DomesticUsePointRecord
    cell_id::String
    producer_use_cell_id::String
    imputed_import_cell_id::String
    row_code::String
    column_code::String
    display_scenario_id::String
    display_point_value_millions::Float64
    raw_numeric_residual_millions::Union{Nothing, Float64}
    input_selected_zero_count::Int
    raw_source_leaf_count::Int
    lineage_hash::String
    boundary_role::String
    evaluation_status::String
    observation_role::String
    independent_observation::Bool
    solver_admissible::Bool
end

struct ObservationLoading
    owner_kind::String
    owner_id::String
    canonical_source_key::String
    source_lineage_hash::String
    coefficient::Float64
    projection_id::String
    projection_sha256::String
    source_member::String
    source_workbook_sha256::String
    row_type::String
    row_code::String
    column_type::String
    column_code::String
    source_value_token::String
    source_cell_state::String
    numerical_reliability_receipt_id::Union{Nothing, String}
    numerical_covariance_receipt_id::Union{Nothing, String}
    solver_admissible::Bool
end

struct ControlDisplayDiagnostic
    scenario_id::String
    scenario_approval_status::String
    control_id::String
    control_kind::String
    control_family::String
    term_target_count::Int
    term_source_leaf_count::Int
    rhs_source_leaf_count::Int
    selected_zero_source_leaf_count::Int
    unresolved_import_selected_zero_source_leaf_count::Int
    evaluation_status::String
    point_residual_millions::Union{Nothing, Float64}
    point_residual_zero::Union{Nothing, Bool}
    sensitivity_assumption_id::String
    sensitivity_half_width_millions::Union{Nothing, Float64}
    sensitivity_status::String
    fixed_status::String
    solver_admissible::Bool
end

struct NegativeCellEvidence
    cell_id::String
    raw_value_millions::Float64
    source_economic_type::String
    source_negative_economic_type::String
    source_sign_domain::String
    evidence_negative_economic_type::String
    evidence_sign_domain::String
    classification_status::String
    component_resolution_status::String
    evidence_ids::String
    reliability_class_id::Union{Nothing, String}
    covariance_group_id::Union{Nothing, String}
    approval_id::Union{Nothing, String}
    solver_admissible::Bool
end

struct CandidateDependenceGroup
    group_id::String
    group_kind::String
    member_count::Int
    dependence_status::String
    numerical_parameter_status::String
    solver_admissible::Bool
end

struct RevisionVintageReceipt
    release_id::String
    release_date::String
    archive_url::String
    archive_sha256::String
    common_reference_year_candidate::Int
    checked_in_cell_fixture::Bool
    receipt_status::String
    numerical_reliability_receipt_count::Int
    numerical_covariance_receipt_count::Int
    solver_admissible::Bool
end

struct ProductionReconciliationAdmissionEvidenceReport
    schema_version::String
    contract_sha256::String
    candidate_problem_scope_hash::String
    candidate_problem_hash::String
    evidence_hash::String
    source_display_records::Vector{SourceDisplayRecord}
    release_marker_receipts::Vector{ReleaseMarkerReceipt}
    valuation_import_boundaries::Vector{ValuationImportBoundaryEvidence}
    domestic_use_points::Vector{DomesticUsePointRecord}
    observation_loadings::Vector{ObservationLoading}
    control_diagnostics::Vector{ControlDisplayDiagnostic}
    negative_cells::Vector{NegativeCellEvidence}
    dependence_groups::Vector{CandidateDependenceGroup}
    revision_vintages::Vector{RevisionVintageReceipt}
    promotion_blockers::Vector{String}
    solver_invocation_count::Int
    solver_input_cell_count::Int
    solver_input_control_count::Int
    approved_exact_control_count::Int
    approved_structural_zero_count::Int
    numerical_reliability_receipt_count::Int
    numerical_covariance_receipt_count::Int
    adjustment_record_count::Int
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_state_write::Bool
    accounting_gate_effect::String
    forecast_score_effect::String
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
file_sha256(path) = sha256_hex(read(path))

function digest(parts...)
    io = IOBuffer()
    for part in parts
        bytes = codeunits(string(part))
        write(io, string(length(bytes)))
        write(io, ':')
        write(io, bytes)
        write(io, ';')
    end
    return sha256_hex(take!(io))
end

function is_sha256(value)
    return value isa AbstractString &&
        occursin(r"^[0-9a-f]{64}$", String(value))
end

function exact_keys(value, expected, location)
    value isa AbstractDict ||
        throw(
        AdmissionEvidenceContractError(
            location,
            "must be a table",
        ),
    )
    actual = Set(String.(keys(value)))
    actual == expected ||
        throw(
        AdmissionEvidenceContractError(
            location,
            "keys changed; expected $(sort!(collect(expected))), got $(sort!(collect(actual)))",
        ),
    )
    return value
end

function required_string(value, key, location)
    haskey(value, key) ||
        throw(AdmissionEvidenceContractError(location, "missing $key"))
    item = value[key]
    item isa AbstractString && !isempty(strip(item)) ||
        throw(
        AdmissionEvidenceContractError(
            "$location.$key",
            "must be a nonempty string",
        ),
    )
    return String(item)
end

function required_bool(value, key, location)
    haskey(value, key) ||
        throw(AdmissionEvidenceContractError(location, "missing $key"))
    value[key] isa Bool ||
        throw(
        AdmissionEvidenceContractError(
            "$location.$key",
            "must be Boolean",
        ),
    )
    return Bool(value[key])
end

function required_int(value, key, location)
    haskey(value, key) ||
        throw(AdmissionEvidenceContractError(location, "missing $key"))
    item = value[key]
    item isa Integer ||
        throw(
        AdmissionEvidenceContractError(
            "$location.$key",
            "must be an integer",
        ),
    )
    return Int(item)
end

function safe_artifact_path(repo_root, relative_path, location)
    isabspath(relative_path) &&
        throw(
        AdmissionEvidenceContractError(
            location,
            "must be repository-relative",
        ),
    )
    ispath(repo_root) ||
        throw(
        AdmissionEvidenceContractError(
            location,
            "repository root does not exist",
        ),
    )
    root = realpath(repo_root)
    candidate = normpath(joinpath(root, relative_path))
    relative = relpath(candidate, root)
    (relative == ".." || startswith(relative, ".." * string(Base.Filesystem.path_separator))) &&
        throw(
        AdmissionEvidenceContractError(
            location,
            "escapes repository root",
        ),
    )
    ispath(candidate) ||
        throw(
        AdmissionEvidenceContractError(
            location,
            "path does not exist",
        ),
    )
    islink(candidate) &&
        throw(
        AdmissionEvidenceContractError(
            location,
            "must not be a symbolic link",
        ),
    )
    isfile(candidate) ||
        throw(
        AdmissionEvidenceContractError(
            location,
            "must be a regular file",
        ),
    )
    resolved = realpath(candidate)
    prefix = root * string(Base.Filesystem.path_separator)
    (resolved == root || startswith(resolved, prefix)) ||
        throw(
        AdmissionEvidenceContractError(
            location,
            "resolved path escapes repository root",
        ),
    )
    return resolved
end

function normalized_module_sha256(path::AbstractString)
    source = read(path, String)
    occurrences = findall(APPROVED_CONTRACT_SHA256, source)
    length(occurrences) == 1 ||
        throw(
        AdmissionEvidenceContractError(
            "implementation.module",
            "approved contract hash literal must occur exactly once",
        ),
    )
    normalized =
        replace(source, APPROVED_CONTRACT_SHA256 => ZERO_SHA256; count = 1)
    return sha256_hex(codeunits(normalized))
end

function load_admission_evidence_contract(
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    contract_hash = file_sha256(contract_path)
    contract_hash == APPROVED_CONTRACT_SHA256 ||
        throw(
        AdmissionEvidenceContractError(
            "contract",
            "SHA-256 changed",
        ),
    )
    raw = TOML.parsefile(contract_path)
    exact_keys(raw, TOP_LEVEL_KEYS, "contract")
    required_string(raw, "schema_version", "contract") == CONTRACT_SCHEMA ||
        throw(
        AdmissionEvidenceContractError(
            "contract.schema_version",
            "changed",
        ),
    )
    contract_id = required_string(raw, "contract_id", "contract")
    classification = required_string(raw, "classification", "contract")
    artifact_role = required_string(raw, "artifact_role", "contract")
    promotion_status =
        required_string(raw, "promotion_status", "contract")
    scientific_scope =
        required_string(raw, "scientific_scope", "contract")
    as_of_date = required_string(raw, "as_of_date", "contract")
    occursin(r"^\d{4}-\d{2}-\d{2}$", as_of_date) ||
        throw(
        AdmissionEvidenceContractError(
            "contract.as_of_date",
            "must be YYYY-MM-DD",
        ),
    )
    candidate_problem_scope_hash =
        required_string(raw, "candidate_problem_scope_hash", "contract")
    candidate_problem_hash =
        required_string(raw, "candidate_problem_hash", "contract")
    startswith(candidate_problem_scope_hash, "scope1:") ||
        throw(
        AdmissionEvidenceContractError(
            "contract.candidate_problem_scope_hash",
            "changed",
        ),
    )
    startswith(candidate_problem_hash, "problem1:") ||
        throw(
        AdmissionEvidenceContractError(
            "contract.candidate_problem_hash",
            "changed",
        ),
    )
    candidate_ledger_contract_sha256 =
        required_string(raw, "candidate_ledger_contract_sha256", "contract")
    display_semantics_fixture_sha256 =
        required_string(raw, "display_semantics_fixture_sha256", "contract")
    display_semantics_manifest_sha256 =
        required_string(raw, "display_semantics_manifest_sha256", "contract")
    display_semantics_generator_sha256 =
        required_string(raw, "display_semantics_generator_sha256", "contract")
    all(
        is_sha256,
        (
            candidate_ledger_contract_sha256,
            display_semantics_fixture_sha256,
            display_semantics_manifest_sha256,
            display_semantics_generator_sha256,
        ),
    ) ||
        throw(
        AdmissionEvidenceContractError(
            "contract",
            "contains a malformed SHA-256",
        ),
    )

    for key in (
            "solver_admissible",
            "forecast_origin_admissible",
            "promotion_ready",
            "model_state_write",
        )
        required_bool(raw, key, "contract") &&
            throw(
            AdmissionEvidenceContractError(
                "contract.$key",
                "must remain false",
            ),
        )
    end
    for key in (
            "solver_invocation_count",
            "solver_input_cell_count",
            "solver_input_control_count",
            "approved_exact_control_count",
            "approved_structural_zero_count",
            "numerical_reliability_receipt_count",
            "numerical_covariance_receipt_count",
            "adjustment_record_count",
        )
        required_int(raw, key, "contract") == 0 ||
            throw(
            AdmissionEvidenceContractError(
                "contract.$key",
                "must remain zero",
            ),
        )
    end
    required_string(raw, "accounting_gate_effect", "contract") == "NONE" ||
        throw(
        AdmissionEvidenceContractError(
            "contract.accounting_gate_effect",
            "must remain NONE",
        ),
    )
    required_string(raw, "forecast_score_effect", "contract") == "NONE" ||
        throw(
        AdmissionEvidenceContractError(
            "contract.forecast_score_effect",
            "must remain NONE",
        ),
    )

    blockers_raw = raw["promotion_blockers"]
    blockers_raw isa AbstractVector ||
        throw(
        AdmissionEvidenceContractError(
            "contract.promotion_blockers",
            "must be an array",
        ),
    )
    promotion_blockers = String.(blockers_raw)
    !isempty(promotion_blockers) &&
        length(unique(promotion_blockers)) == length(promotion_blockers) ||
        throw(
        AdmissionEvidenceContractError(
            "contract.promotion_blockers",
            "must be nonempty and unique",
        ),
    )

    display_policy =
        Dict{String, Any}(
        exact_keys(
            raw["display_policy"],
            DISPLAY_POLICY_KEYS,
            "contract.display_policy",
        )
    )
    display_policy["primary_scenario_id"] == PRIMARY_SCENARIO ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_policy.primary_scenario_id",
            "changed",
        ),
    )
    display_policy["counterfactual_scenario_id"] ==
        COUNTERFACTUAL_SCENARIO ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_policy.counterfactual_scenario_id",
            "changed",
        ),
    )
    display_policy["producer_selected_ellipsis_published_value_millions"] ==
        0.0 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_policy",
            "producer display value changed",
        ),
    )
    display_policy["producer_selected_ellipsis_structural_zero_status"] ==
        "NOT_ESTABLISHED" ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_policy",
            "structural-zero status changed",
        ),
    )
    display_policy["producer_selected_ellipsis_variance_status"] ==
        "NOT_ESTABLISHED" ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_policy",
            "variance status changed",
        ),
    )
    display_policy["producer_selected_ellipsis_source_semantics"] ==
        "BEA_ZERO_VALUE_NOT_SHOWN" &&
        display_policy["producer_selected_ellipsis_underlying_exactness"] ==
        "UNKNOWN" &&
        display_policy["import_selected_ellipsis_primary_semantics"] ==
        "PUBLISHED_ZERO_UNDER_PINNED_RELEASE_SCOPED_ITABLE_AND_WORKBOOK_COORDINATE_CORROBORATION" &&
        display_policy[
        "import_selected_ellipsis_counterfactual_semantics",
    ] ==
        "UNRESOLVED_IF_EVIDENCE_IS_ARTIFICIALLY_RESTRICTED_TO_SAME_WORKBOOK_NOTES" &&
        display_policy["raw_token_preservation"] ==
        "REQUIRED_DISTINCT_FROM_NUMERIC_ZERO" &&
        display_policy["blank_missing_suppressed_inheritance"] ==
        "FORBIDDEN" ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_policy",
            "source-state boundary changed",
        ),
    )

    sensitivity =
        Dict{String, Any}(
        exact_keys(
            raw["display_resolution_sensitivity"],
            SENSITIVITY_KEYS,
            "contract.display_resolution_sensitivity",
        )
    )
    sensitivity["enabled_for_diagnostics"] === true ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_resolution_sensitivity",
            "diagnostic scenario must remain explicit",
        ),
    )
    sensitivity["display_increment_millions"] == 1.0 &&
        sensitivity["half_width_per_raw_display_millions"] == 0.5 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_resolution_sensitivity",
            "display resolution changed",
        ),
    )
    sensitivity["source_certified_rounding_rule"] === false &&
        sensitivity["confidence_interval"] === false &&
        sensitivity["probability_distribution"] == "NONE" &&
        sensitivity["variance_from_rounding"] == "NONE" &&
        sensitivity["solver_weight_effect"] == "NONE" ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_resolution_sensitivity",
            "nonprobabilistic boundary changed",
        ),
    )

    revision_evidence =
        Dict{String, Any}(
        exact_keys(
            raw["revision_evidence"],
            REVISION_KEYS,
            "contract.revision_evidence",
        )
    )
    for key in (
            "current_archive_sha256",
            "earlier_archive_sha256",
            "earlier_producer_use_sha256",
            "earlier_producer_make_sha256",
        )
        is_sha256(revision_evidence[key]) ||
            throw(
            AdmissionEvidenceContractError(
                "contract.revision_evidence.$key",
                "is not a SHA-256",
            ),
        )
    end
    revision_evidence["archive_hashes_verified_during_development"] === true ||
        throw(
        AdmissionEvidenceContractError(
            "contract.revision_evidence",
            "archive verification receipt changed",
        ),
    )
    revision_evidence["checked_in_revision_cell_fixture"] === false &&
        revision_evidence["realized_2024_revision_observation_count"] == 0 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.revision_evidence",
            "revision evidence is overclaimed",
        ),
    )

    implementation =
        exact_keys(
        raw["implementation"],
        IMPLEMENTATION_KEYS,
        "contract.implementation",
    )
    module_path =
        required_string(implementation, "module_path", "contract.implementation")
    module_normalized_sha256 = required_string(
        implementation,
        "module_normalized_sha256",
        "contract.implementation",
    )
    runner_path =
        required_string(implementation, "runner_path", "contract.implementation")
    runner_sha256 =
        required_string(implementation, "runner_sha256", "contract.implementation")
    all(is_sha256, (module_normalized_sha256, runner_sha256)) ||
        throw(
        AdmissionEvidenceContractError(
            "contract.implementation",
            "contains a malformed SHA-256",
        ),
    )
    module_full_path =
        safe_artifact_path(repo_root, module_path, "contract.implementation.module_path")
    runner_full_path =
        safe_artifact_path(repo_root, runner_path, "contract.implementation.runner_path")
    normalized_module_sha256(module_full_path) == module_normalized_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.implementation.module_normalized_sha256",
            "changed",
        ),
    )
    file_sha256(runner_full_path) == runner_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.implementation.runner_sha256",
            "changed",
        ),
    )

    expected_raw = raw["expected"]
    exact_keys(expected_raw, EXPECTED_KEYS, "contract.expected")
    expected = Dict{String, Int}()
    for (key, value) in expected_raw
        value isa Integer ||
            throw(
            AdmissionEvidenceContractError(
                "contract.expected.$key",
                "must be an integer",
            ),
        )
        Int(value) >= 0 ||
            throw(
            AdmissionEvidenceContractError(
                "contract.expected.$key",
                "cannot be negative",
            ),
        )
        expected[String(key)] = Int(value)
    end

    artifacts = Dict{String, EvidenceArtifactBinding}()
    for (index, item) in enumerate(raw["artifact"])
        location = "contract.artifact[$index]"
        exact_keys(item, ARTIFACT_KEYS, location)
        artifact_id = required_string(item, "artifact_id", location)
        haskey(artifacts, artifact_id) &&
            throw(
            AdmissionEvidenceContractError(
                "$location.artifact_id",
                "duplicate",
            ),
        )
        relative_path = required_string(item, "path", location)
        sha256 = required_string(item, "sha256", location)
        is_sha256(sha256) ||
            throw(
            AdmissionEvidenceContractError(
                "$location.sha256",
                "is not a SHA-256",
            ),
        )
        full_path = safe_artifact_path(repo_root, relative_path, "$location.path")
        isfile(full_path) ||
            throw(
            AdmissionEvidenceContractError(
                "$location.path",
                "does not exist",
            ),
        )
        file_sha256(full_path) == sha256 ||
            throw(
            AdmissionEvidenceContractError(
                "$location.sha256",
                "artifact changed",
            ),
        )
        artifacts[artifact_id] = EvidenceArtifactBinding(
            artifact_id,
            relative_path,
            full_path,
            sha256,
            required_string(item, "role", location),
        )
    end
    Set(keys(artifacts)) == Set(
        [
            "candidate_ledger_contract",
            "display_semantics_fixture",
            "display_semantics_manifest",
            "display_semantics_generator",
            "itable_marker_receipt",
            "itable_canonical_grid",
            "itable_marker_generator",
            "itable_marker_test",
            "negative_cell_semantics_fixture",
            "negative_cell_semantics_manifest",
            "valuation_envelope_contract",
            "final_use_envelope_contract",
        ],
    ) ||
        throw(
        AdmissionEvidenceContractError(
            "contract.artifact",
            "artifact registry changed",
        ),
    )
    artifacts["candidate_ledger_contract"].sha256 ==
        candidate_ledger_contract_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.candidate_ledger_contract_sha256",
            "does not match artifact registry",
        ),
    )
    artifacts["display_semantics_fixture"].sha256 ==
        display_semantics_fixture_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_semantics_fixture_sha256",
            "does not match artifact registry",
        ),
    )
    artifacts["display_semantics_manifest"].sha256 ==
        display_semantics_manifest_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_semantics_manifest_sha256",
            "does not match artifact registry",
        ),
    )
    artifacts["display_semantics_generator"].sha256 ==
        display_semantics_generator_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "contract.display_semantics_generator_sha256",
            "does not match artifact registry",
        ),
    )

    literature = LiteratureReference[]
    for (index, item) in enumerate(raw["literature"])
        location = "contract.literature[$index]"
        exact_keys(item, LITERATURE_KEYS, location)
        reference = LiteratureReference(
            required_string(item, "literature_id", location),
            required_string(item, "title", location),
            required_string(item, "url", location),
            required_string(item, "role", location),
        )
        startswith(reference.url, "https://") ||
            throw(
            AdmissionEvidenceContractError(
                "$location.url",
                "must be HTTPS",
            ),
        )
        push!(literature, reference)
    end
    length(literature) >= 6 &&
        length(unique(item.literature_id for item in literature)) ==
        length(literature) ||
        throw(
        AdmissionEvidenceContractError(
            "contract.literature",
            "must be unique and sufficiently documented",
        ),
    )

    return AdmissionEvidenceContract(
        contract_hash,
        contract_id,
        classification,
        artifact_role,
        promotion_status,
        scientific_scope,
        as_of_date,
        candidate_problem_scope_hash,
        candidate_problem_hash,
        candidate_ledger_contract_sha256,
        display_semantics_fixture_sha256,
        display_semantics_manifest_sha256,
        display_semantics_generator_sha256,
        display_policy,
        sensitivity,
        revision_evidence,
        module_path,
        module_normalized_sha256,
        runner_path,
        runner_sha256,
        expected,
        artifacts,
        literature,
        promotion_blockers,
    )
end

function load_source_display_records(contract::AdmissionEvidenceContract)
    manifest_path = contract.artifacts["display_semantics_manifest"].path
    fixture_path = contract.artifacts["display_semantics_fixture"].path
    manifest = TOML.parsefile(manifest_path)
    manifest["fixture_sha256"] == contract.display_semantics_fixture_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "display_manifest.fixture_sha256",
            "changed",
        ),
    )
    manifest["source_zip_sha256"] ==
        contract.revision_evidence["current_archive_sha256"] ||
        throw(
        AdmissionEvidenceContractError(
            "display_manifest.source_zip_sha256",
            "does not match the archived release",
        ),
    )
    manifest["producer_zero_note_status"] ==
        "AUTHENTICATED_SAME_SHEET_NOTE" ||
        throw(
        AdmissionEvidenceContractError(
            "display_manifest.producer_zero_note_status",
            "changed",
        ),
    )
    manifest["producer_selected_ellipsis_structural_zero_status"] ==
        "NOT_ESTABLISHED" ||
        throw(
        AdmissionEvidenceContractError(
            "display_manifest",
            "structural-zero status changed",
        ),
    )
    manifest["producer_selected_ellipsis_variance_status"] ==
        "NOT_ESTABLISHED" ||
        throw(
        AdmissionEvidenceContractError(
            "display_manifest",
            "variance status changed",
        ),
    )
    manifest["import_same_sheet_zero_note_present"] === false &&
        manifest["import_ellipsis_semantics_status"] ==
        "RELEASE_SCOPED_CORROBORATED_BY_SEPARATELY_PINNED_ITABLE_RECEIPT" ||
        throw(
        AdmissionEvidenceContractError(
            "display_manifest",
            "import release-family corroboration changed",
        ),
    )
    manifest["solver_admissible"] === false ||
        throw(
        AdmissionEvidenceContractError(
            "display_manifest.solver_admissible",
            "must remain false",
        ),
    )
    for key in (
            "structural_zero_approval_count",
            "reliability_receipt_count",
            "covariance_receipt_count",
        )
        manifest[key] == 0 ||
            throw(
            AdmissionEvidenceContractError(
                "display_manifest.$key",
                "must remain zero",
            ),
        )
    end

    table = CSV.File(
        fixture_path;
        types = Dict(
            Symbol(field) => Union{Missing, String}
                for field in DISPLAY_FIXTURE_COLUMNS
        ),
    )
    String.(propertynames(first(table))) == DISPLAY_FIXTURE_COLUMNS ||
        throw(
        AdmissionEvidenceContractError(
            "display_fixture",
            "columns changed",
        ),
    )
    records = SourceDisplayRecord[]
    for row in table
        push!(
            records,
            SourceDisplayRecord(
                String(coalesce(row.record_id, "")),
                String(coalesce(row.workbook_member, "")),
                String(coalesce(row.workbook_sha256, "")),
                String(coalesce(row.sheet, "")),
                String(coalesce(row.cell_address, "")),
                String(coalesce(row.record_kind, "")),
                String(coalesce(row.semantic_class, "")),
                String(coalesce(row.source_token, "")),
                String(coalesce(row.exact_text_or_value, "")),
            ),
        )
    end
    issorted(getfield.(records, :record_id)) ||
        throw(
        AdmissionEvidenceContractError(
            "display_fixture.record_id",
            "must be sorted",
        ),
    )
    length(records) == 12 ==
        manifest["fixture_record_count"] ||
        throw(
        AdmissionEvidenceContractError(
            "display_fixture",
            "record count changed",
        ),
    )
    length(unique(record.record_id for record in records)) == length(records) ||
        throw(
        AdmissionEvidenceContractError(
            "display_fixture.record_id",
            "duplicate",
        ),
    )
    by_id = Dict(record.record_id => record for record in records)
    for record_id in (
            "PRODUCER_USE_2024_ZERO_VALUE_NOTE",
            "PRODUCER_MAKE_2024_ZERO_VALUE_NOTE",
        )
        by_id[record_id].semantic_class ==
            "SELECTED_ELLIPSIS_IS_PUBLISHED_ZERO" ||
            throw(
            AdmissionEvidenceContractError(
                "display_fixture.$record_id",
                "semantic class changed",
            ),
        )
        by_id[record_id].exact_text_or_value ==
            "Note. Selected data with zero values are not shown." ||
            throw(
            AdmissionEvidenceContractError(
                "display_fixture.$record_id",
                "source note changed",
            ),
        )
    end
    by_id["IMPORT_2024_ELLIPSIS_WITNESS"].semantic_class ==
        "RELEASE_SCOPED_CORROBORATED_SELECTED_ZERO_DISPLAY_TOKEN" ||
        throw(
        AdmissionEvidenceContractError(
            "display_fixture.IMPORT_2024_ELLIPSIS_WITNESS",
            "release-scoped semantic class changed",
        ),
    )
    return records
end

function load_release_marker_receipts(
        contract::AdmissionEvidenceContract,
    )
    receipt = JSON.parsefile(
        contract.artifacts["itable_marker_receipt"].path,
    )
    receipt["schema_version"] ==
        "beforeit-us-bea-itable-display-semantics-receipt.v2" ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt.schema_version",
            "changed",
        ),
    )
    receipt["classification"] ==
        "AUTHENTICATED_RELEASE_SCOPED_DISPLAY_SEMANTICS_EVIDENCE" ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt.classification",
            "changed",
        ),
    )
    receipt["promotion_status"] ==
        "EVIDENCE_ONLY_NOT_SOLVER_ADMITTED" ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt.promotion_status",
            "changed",
        ),
    )
    receipt["accounting_gate_effect"] == "NONE" &&
        receipt["forecast_score_effect"] == "NONE" ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt",
            "must not affect gates or scores",
        ),
    )
    conclusions = receipt["conclusions"]
    conclusions["api_request_release_selector_status"] == "ABSENT" &&
        conclusions["pinned_archive_content_identity_status"] ==
        "FULL_COMMON_BASIS_TOKEN_VALUE_AND_SEMANTIC_MATCH" &&
        conclusions["import_ellipsis_display_value_millions"] == 0 &&
        conclusions["import_ellipsis_evidence_status"] ==
        "BEA_RELEASE_FAMILY_CORROBORATED_PUBLISHED_ZERO" &&
        conclusions["import_ellipsis_scope"] ==
        "PINNED_2025_ANNUAL_RELEASE_2024_SUMMARY_TABLE_ONLY" &&
        conclusions["import_ellipsis_structural_zero_status"] ==
        "NOT_ESTABLISHED" &&
        conclusions["import_ellipsis_variance_status"] ==
        "NOT_ESTABLISHED" &&
        conclusions["missing_value_rule_status"] ==
        "NOT_A_GENERIC_BEA_MISSING_VALUE_RULE" ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt.conclusions",
            "scientific boundary changed",
        ),
    )
    source_binding = receipt["source_binding"]
    source_binding["source_zip_sha256"] ==
        contract.revision_evidence["current_archive_sha256"] ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt.source_binding",
            "source release changed",
        ),
    )
    display_binding = receipt["display_semantics_binding"]
    display_binding["cells"]["sha256"] ==
        contract.display_semantics_fixture_sha256 &&
        display_binding["manifest"]["sha256"] ==
        contract.display_semantics_manifest_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt.display_semantics_binding",
            "display fixture binding changed",
        ),
    )
    grid_binding = receipt["canonical_common_basis_grid"]
    grid_artifact = contract.artifacts["itable_canonical_grid"]
    grid_binding["repository_path"] == grid_artifact.relative_path &&
        grid_binding["sha256"] == grid_artifact.sha256 &&
        Int(grid_binding["byte_count"]) == filesize(grid_artifact.path) &&
        grid_binding["serialization"] ==
        "RFC4180_UTF8_LF_TABLE_THEN_ROW_MAJOR_COMMON_BASIS_ONLY" &&
        Int(grid_binding["row_count"]) == 11_972 &&
        Int(grid_binding["exact_match_count"]) == 11_972 &&
        Int(grid_binding["mismatch_count"]) == 0 &&
        Int(grid_binding["maximum_absolute_difference_millions"]) == 0 ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt.canonical_common_basis_grid",
            "full-grid artifact binding or equality changed",
        ),
    )

    expected = Dict(
        "UIMARI" => (
            title = "Import Matrix, After Redefinitions - Summary",
            request =
                "c4b58e84b903541570bfea69bba4b8f2ac27e0f75dd0364a1e9bff0635a90084",
            raw =
                "75a281dd4227c2f5a945fa0960e56d3876dadb13d9b9c2cbd430e7cb1b418b1f",
            decoded =
                "7b20401412415df349c4067d25d9a38576715c9f6b266372949f4dca9e3a50d3",
            table =
                "7e86247570afd23bba1d7c9282cbfd72235f0c560e875d95d5f04a995612fc66",
            axes =
                "f6ad266dbb923f21eac721cb86e37c4c7b88bc9905b8441d6ef3a33fe113fe30",
            classes =
                "43a2301adafccc092bc5bbd31d89997201ca4a51786659e32b00c9e1e2e3344b",
            marker_hash =
                "64a7789eb575a8a8d84b6bde179b47e25de8d2b2419a310a886ee939dd73ca7e",
            zero_hash =
                "d83d1fd4be47c1a7b3da5fb513032223fbbcf923ffae87412ba91ce5ecf105ea",
            api_rows = 73,
            api_columns = 93,
            projection_rows = 73,
            projection_columns = 93,
            cells = 6_789,
            markers = 4_102,
            zeros = 369,
            nonzero_integers = 2_318,
            grid_bytes = 495_255,
            grid_hash =
                "f7cca6e5f4d097e8d43fe9883239e3f31fe767841c3314160392d1b10fe44a84",
            scope =
                "PINNED_2025_ANNUAL_RELEASE_2024_SUMMARY_TABLE_ONLY",
        ),
        "MakeAR" => (
            title =
                "The Make of Commodities by Industries, After Redefinitions - Summary",
            request =
                "8478598e4819286c3a5d203f43d98f1f36f9621fa43a685db2d3850cd25bdf40",
            raw =
                "cbac08eeb2778ebb551911644e84e9e9e799e0f5949ab0a6856b523765940688",
            decoded =
                "4f27324594c859c51aa42ac74f686b84c48a00f174f7528dcd889db8b3229e41",
            table =
                "f956a7a671c329bc87d930dec0b7a5a7589e5ed5fec3e541c9d6e19677fc16f1",
            axes =
                "5f8d03464102e46d957a11120ebf4d818a7439c9e41a46d9156a32df2ca07cf8",
            classes =
                "2b39f113340cc37f291dce29c95cecad574acffe6e170a5c870083709a82707c",
            marker_hash =
                "3a6c3fda102796d8076a856a810cef6d45c9ed672845a5a2bc94b5efe65baf53",
            zero_hash =
                "bd9c9ef1c0158fa308361328f8671f395e5699512abb39d6f827eda6a8bc2226",
            api_rows = 72,
            api_columns = 74,
            projection_rows = 71,
            projection_columns = 73,
            cells = 5_183,
            markers = 4_682,
            zeros = 84,
            nonzero_integers = 417,
            grid_bytes = 401_306,
            grid_hash =
                "5436806fcac78ca1d72a970c99291fc56e496b68e8d6996d7feaf54ea851672a",
            scope =
                "PINNED_2025_ANNUAL_RELEASE_2024_SUMMARY_MAKE_TABLE_ONLY",
        ),
    )
    tables = receipt["tables"]
    length(tables) == length(expected) ||
        throw(
        AdmissionEvidenceContractError(
            "itable_marker_receipt.tables",
            "table count changed",
        ),
    )
    records = ReleaseMarkerReceipt[]
    for table in tables
        table_key = String(table["table_key"])
        haskey(expected, table_key) ||
            throw(
            AdmissionEvidenceContractError(
                "itable_marker_receipt.tables",
                "unexpected table $table_key",
            ),
        )
        item = expected[table_key]
        request = table["http_request"]
        response = table["http_response"]
        axes = table["api_axes"]
        classes = table["api_cell_classes"]
        markers = classes["marker_triple_dash"]
        zeros = classes["literal_zero"]
        projection = table["common_basis_projection"]
        grid = table["full_common_basis_grid_comparison"]
        grid_classes = grid["token_class_counts"]
        table["title"] == item.title &&
            request["method"] == "POST" &&
            request["content_type"] == "application/json" &&
            request["endpoint"] ==
            "https://apps.bea.gov/iTablecore/data/app/GetSteps" &&
            request["body_sha256"] == item.request &&
            response["raw_transport_body_sha256"] == item.raw &&
            response["decoded_json_document_sha256"] == item.decoded &&
            table["api_canonical_table"]["sha256"] == item.table &&
            axes["sha256"] == item.axes &&
            classes["sha256"] == item.classes &&
            Int(axes["row_count"]) == item.api_rows &&
            Int(axes["column_count"]) == item.api_columns &&
            Int(projection["row_count"]) == item.projection_rows &&
            Int(projection["column_count"]) == item.projection_columns &&
            Int(projection["cell_count"]) == item.cells &&
            Int(markers["coordinate_count"]) == item.markers &&
            Int(zeros["coordinate_count"]) == item.zeros &&
            markers["coordinate_set_sha256"] == item.marker_hash &&
            zeros["coordinate_set_sha256"] == item.zero_hash &&
            markers["exact_common_basis_coordinate_match"] === true &&
            zeros["exact_common_basis_coordinate_match"] === true &&
            Int(grid["canonical_table_grid_byte_count"]) ==
            item.grid_bytes &&
            grid["canonical_table_grid_sha256"] == item.grid_hash &&
            Int(grid["exact_match_count"]) == item.cells &&
            Int(grid["mismatch_count"]) == 0 &&
            Int(grid["maximum_absolute_difference_millions"]) == 0 &&
            Int(grid_classes["MARKER_TRIPLE_DASH"]) == item.markers &&
            Int(grid_classes["LITERAL_ZERO"]) == item.zeros &&
            Int(grid_classes["NONZERO_INTEGER"]) ==
            item.nonzero_integers ||
            throw(
            AdmissionEvidenceContractError(
                "itable_marker_receipt.tables.$table_key",
                "authenticated table receipt changed",
            ),
        )
        push!(
            records,
            ReleaseMarkerReceipt(
                table_key,
                String(table["title"]),
                String(request["body_sha256"]),
                String(response["raw_transport_body_sha256"]),
                String(response["decoded_json_document_sha256"]),
                String(table["api_canonical_table"]["sha256"]),
                String(axes["sha256"]),
                String(classes["sha256"]),
                Int(axes["row_count"]),
                Int(axes["column_count"]),
                Int(projection["row_count"]),
                Int(projection["column_count"]),
                Int(projection["cell_count"]),
                Int(markers["coordinate_count"]),
                Int(zeros["coordinate_count"]),
                String(markers["coordinate_set_sha256"]),
                String(zeros["coordinate_set_sha256"]),
                true,
                String(grid["canonical_table_grid_sha256"]),
                Int(grid["exact_match_count"]),
                Int(grid["mismatch_count"]),
                Int(grid["maximum_absolute_difference_millions"]),
                true,
                item.scope,
                false,
            ),
        )
    end
    sort!(records; by = item -> item.table_key)
    return records
end

function build_valuation_import_boundaries(
        contract::AdmissionEvidenceContract,
    )
    valuation = TOML.parsefile(
        contract.artifacts["valuation_envelope_contract"].path,
    )
    final_use = TOML.parsefile(
        contract.artifacts["final_use_envelope_contract"].path,
    )
    valuation["schema_version"] ==
        "beforeit-us-after-redefinitions-valuation-envelope.v1" &&
        valuation["after_redefinitions_source_zip_sha256"] ==
        contract.revision_evidence["current_archive_sha256"] &&
        valuation["cell_allocation_policy"] == "NONE" &&
        valuation["margin_allocation_applied"] === false &&
        valuation["tax_allocation_applied"] === false &&
        valuation["domestic_use_subtraction_applied"] === false &&
        valuation["balancing_applied"] === false &&
        valuation["clipping_applied"] === false ||
        throw(
        AdmissionEvidenceContractError(
            "valuation_envelope_contract",
            "scientific boundary changed",
        ),
    )
    final_use["schema_version"] ==
        "beforeit-us-after-redefinitions-final-use-envelope.v1" &&
        final_use["after_redefinitions_source_zip_sha256"] ==
        contract.revision_evidence["current_archive_sha256"] &&
        final_use["valuation_envelope_contract_sha256"] ==
        contract.artifacts["valuation_envelope_contract"].sha256 &&
        final_use["import_policy"] ==
        "F050_SIGNED_ACCOUNTING_OFFSET_NOT_MODEL_IMPORT_VECTOR" &&
        final_use["cell_level_valuation_allocation_status"] == "MISSING" &&
        final_use["import_boundary_selected"] === false &&
        final_use["balancing_applied"] === false &&
        final_use["clipping_applied"] === false ||
        throw(
        AdmissionEvidenceContractError(
            "final_use_envelope_contract",
            "scientific boundary changed",
        ),
    )

    records = [
        ValuationImportBoundaryEvidence(
            "AFTER_REDEFINITIONS_PRODUCER_USE_TARGET",
            "AUTHENTICATED_SOURCE_IDENTIFIED",
            "2024_PRODUCER_PRICE_USE_AFTER_REDEFINITIONS",
            "RETAIN_CODE_KEYED_PRODUCER_USE_OBSERVATIONS",
            "DO_NOT_RELABEL_AS_BASIC_OR_PURCHASER_PRICE",
            "RECIPIENT_LEVEL_VALUATION_TAX_MARGIN_BRIDGE_INCOMPLETE",
            false,
        ),
        ValuationImportBoundaryEvidence(
            "IMPUTED_IMPORT_ALLOCATION_SOURCE",
            "AUTHENTICATED_SIGNED_IMPUTED_ALLOCATION_EVIDENCE",
            "2024_DOMESTIC_PORT_SUBSTITUTION_VALUE_AFTER_REDEFINITIONS",
            "RETAIN_CODE_KEYED_SIGNED_IMPORT_ALLOCATION_OBSERVATIONS",
            "DO_NOT_RELABEL_AS_MEASURED_IMPORTS_OR_NONNEGATIVE_MODEL_DEMAND",
            "IMPORT_BOUNDARY_NOT_SELECTED",
            false,
        ),
        ValuationImportBoundaryEvidence(
            "DOMESTIC_USE_DIFFERENCE_OPERATOR",
            "DETERMINISTIC_DISPLAY_POINT_WITH_NULLABLE_RAW_NUMERIC_RESIDUAL",
            "PRODUCER_USE_MINUS_IMPUTED_IMPORT_ALLOCATION",
            "MATERIALIZE_RAW_RESIDUAL_ONLY_WHEN_BOTH_PARENT_LINEAGES_HAVE_NO_SELECTED_ZERO_SOURCE_LEAF_WITH_ZERO_EXTRA_LIKELIHOOD",
            "DO_NOT_CONVERT_MIXED_NUMERIC_AND_SELECTED_ZERO_PARENT_LINEAGES_TO_RAW_NUMERIC_EVIDENCE",
            "PRODUCTION_SOLVER_ADMISSION_NOT_APPROVED",
            false,
        ),
        ValuationImportBoundaryEvidence(
            "IMPORT_COMMODITY_CONTROLS",
            "MEASURED_PUBLISHED_ROUNDING_CANDIDATES",
            "2024_IMPORT_MATRIX_COMMODITY_TOTALS",
            "COMPUTE_AND_REPORT_CODE_KEYED_DISPLAY_RESIDUALS",
            "DO_NOT_PROMOTE_ALL_PUBLISHED_TOTALS_TO_EXACT_IDENTITIES",
            "EXACT_CONTROL_SET_NOT_INDEPENDENTLY_APPROVED",
            false,
        ),
        ValuationImportBoundaryEvidence(
            "RECIPIENT_LEVEL_MARGIN_TAX_WEDGE",
            "SOURCE_COMPONENT_TOTALS_EXIST_RECIPIENT_ALLOCATION_MISSING",
            "BASIC_PRICE_PLUS_PRODUCT_TAX_AND_TRADE_TRANSPORT_WEDGES",
            "RETAIN_COMMODITY_TOTALS_AND_HISTORICAL_BENCHMARK_EVIDENCE",
            "DO_NOT_PROJECT_2017_WEDGES_OR_PROPORTIONALLY_SMEAR_2024_TOTALS",
            "RECIPIENT_LEVEL_VALUATION_TAX_MARGIN_BRIDGE_INCOMPLETE",
            false,
        ),
        ValuationImportBoundaryEvidence(
            "CROSS_ARCHIVE_RELEASE_IDENTITY",
            "NOT_EXTERNALLY_BOUND",
            "SEPARATELY_CAPTURED_REFERENCE_YEAR_2024_ARCHIVES",
            "KEEP_CROSS_ARCHIVE_COMPARISONS_QUARANTINED",
            "DO_NOT_TREAT_MATCHING_YEAR_AS_COMMON_RELEASE_PROOF",
            "RECIPIENT_LEVEL_VALUATION_TAX_MARGIN_BRIDGE_INCOMPLETE",
            false,
        ),
    ]
    sort!(records; by = item -> item.boundary_id)
    return records
end

source_value(member::SourceLineageMember) =
    parse(Float64, member.source_value_token)

cell_display_point(cell::ProductionCellRecord) =
    cell.raw_value === nothing ? 0.0 : cell.raw_value

function build_domestic_use_points(
        ledger::ProductionReconciliationLedger,
    )
    cells = Dict(cell.cell_id => cell for cell in ledger.cells)
    lineages =
        Dict(lineage.owner_id => lineage for lineage in ledger.target_lineages)
    source_members = Dict(
        member.canonical_source_key => member
            for member in ledger.source_lineage_members
    )
    records = DomesticUsePointRecord[]
    for producer in ledger.cells
        producer_block = split(producer.cell_id, ':')[2]
        producer_block in (
            "PRODUCER_INTERMEDIATE_USE",
            "PRODUCER_FINAL_USE",
        ) || continue
        import_block = producer_block == "PRODUCER_INTERMEDIATE_USE" ?
            "IMPORT_INTERMEDIATE_USE" :
            "IMPORT_FINAL_USE"
        domestic_block = producer_block == "PRODUCER_INTERMEDIATE_USE" ?
            "DOMESTIC_INTERMEDIATE_USE" :
            "DOMESTIC_FINAL_USE"
        import_id = replace(
            producer.cell_id,
            ":$producer_block:" => ":$import_block:";
            count = 1,
        )
        domestic_id = replace(
            producer.cell_id,
            ":$producer_block:" => ":$domestic_block:";
            count = 1,
        )
        haskey(cells, import_id) ||
            throw(
            AdmissionEvidenceContractError(
                "domestic_use.$domestic_id",
                "matching imputed-import cell is missing",
            ),
        )
        imports = cells[import_id]
        (
            producer.row_code,
            producer.column_code,
            producer.release_id,
            producer.reference_period,
            producer.frequency,
            producer.time_basis,
            producer.stock_flow_class,
            producer.country,
            producer.currency,
            producer.unit,
            producer.price_basis,
            producer.problem_scope_hash,
        ) == (
            imports.row_code,
            imports.column_code,
            imports.release_id,
            imports.reference_period,
            imports.frequency,
            imports.time_basis,
            imports.stock_flow_class,
            imports.country,
            imports.currency,
            imports.unit,
            imports.price_basis,
            imports.problem_scope_hash,
        ) ||
            throw(
            AdmissionEvidenceContractError(
                "domestic_use.$domestic_id",
                "producer/import semantic tuple differs",
            ),
        )
        producer_lineage = lineages[producer.cell_id]
        import_lineage = lineages[imports.cell_id]
        parent_keys = sort!(
            vcat(
                producer_lineage.parent_source_keys,
                import_lineage.parent_source_keys,
            )
        )
        length(parent_keys) == length(unique(parent_keys)) ||
            throw(
            AdmissionEvidenceContractError(
                "domestic_use.$domestic_id",
                "parent source lineage overlaps",
            ),
        )
        parent_members = [source_members[key] for key in parent_keys]
        selected_count = count(
            member -> member.source_cell_state == SELECTED_ZERO_STATE,
            parent_members,
        )
        display_point_value =
            cell_display_point(producer) - cell_display_point(imports)
        raw_numeric_residual = selected_count == 0 ?
            producer.raw_value - imports.raw_value :
            nothing
        lineage_hash = "domestic1:" * digest(
            domestic_id,
            producer.cell_id,
            imports.cell_id,
            PRIMARY_SCENARIO,
            (
                key * "|" * source_members[key].lineage_hash
                    for key in parent_keys
            )...,
        )
        push!(
            records,
            DomesticUsePointRecord(
                domestic_id,
                producer.cell_id,
                imports.cell_id,
                producer.row_code,
                producer.column_code,
                PRIMARY_SCENARIO,
                display_point_value,
                raw_numeric_residual,
                selected_count,
                length(parent_keys),
                lineage_hash,
                producer.column_code == "F050" ?
                    "IMPORT_ACCOUNTING_OFFSET_DIAGNOSTIC_ONLY" :
                    "DOMESTIC_USE_DIFFERENCE_CANDIDATE",
                raw_numeric_residual === nothing ?
                    "RAW_RESIDUAL_NOT_EVALUABLE_SELECTED_ZERO_PARENT_DISPLAY_POINT_ONLY" :
                    "RAW_NUMERIC_RESIDUAL_EVALUATED",
                "DETERMINISTIC_DERIVED_RECORD_ZERO_EXTRA_LIKELIHOOD",
                false,
                false,
            ),
        )
    end
    sort!(records; by = item -> item.cell_id)
    length(records) == 6_160 &&
        length(unique(item.cell_id for item in records)) == 6_160 ||
        throw(
        AdmissionEvidenceContractError(
            "domestic_use",
            "derived point registry changed",
        ),
    )
    return records
end

function build_observation_loadings(
        ledger::ProductionReconciliationLedger,
    )
    members = Dict(
        member.canonical_source_key => member
            for member in ledger.source_lineage_members
    )
    loadings = ObservationLoading[]
    function add_owner(owner_kind, owner_id, parent_keys, parent_hashes)
        length(parent_keys) == length(parent_hashes) ||
            throw(
            AdmissionEvidenceContractError(
                "loading.$owner_id",
                "parent key/hash length mismatch",
            ),
        )
        for (key, lineage_hash) in zip(parent_keys, parent_hashes)
            haskey(members, key) ||
                throw(
                AdmissionEvidenceContractError(
                    "loading.$owner_id",
                    "unknown source key",
                ),
            )
            member = members[key]
            member.lineage_hash == lineage_hash ||
                throw(
                AdmissionEvidenceContractError(
                    "loading.$owner_id",
                    "source lineage mismatch",
                ),
            )
            push!(
                loadings,
                ObservationLoading(
                    owner_kind,
                    owner_id,
                    member.canonical_source_key,
                    member.lineage_hash,
                    1.0,
                    member.projection_id,
                    member.projection_sha256,
                    member.source_member,
                    member.source_workbook_sha256,
                    member.row_type,
                    member.row_code,
                    member.column_type,
                    member.column_code,
                    member.source_value_token,
                    member.source_cell_state,
                    nothing,
                    nothing,
                    false,
                ),
            )
        end
        return
    end
    for lineage in ledger.target_lineages
        add_owner(
            "TARGET_CELL",
            lineage.owner_id,
            lineage.parent_source_keys,
            lineage.parent_lineage_hashes,
        )
    end
    for lineage in ledger.control_lineages
        isempty(lineage.parent_source_keys) && continue
        add_owner(
            "MEASURED_PUBLISHED_MARGIN_RHS",
            lineage.owner_id,
            lineage.parent_source_keys,
            lineage.parent_lineage_hashes,
        )
    end
    sort!(
        loadings;
        by = item -> (
            item.owner_kind,
            item.owner_id,
            item.canonical_source_key,
        ),
    )
    keys = getfield.(loadings, :canonical_source_key)
    length(keys) == length(unique(keys)) ==
        length(ledger.source_lineage_members) ||
        throw(
        AdmissionEvidenceContractError(
            "observation_loadings",
            "must partition the raw source registry exactly once",
        ),
    )
    Set(keys) ==
        Set(member.canonical_source_key for member in ledger.source_lineage_members) ||
        throw(
        AdmissionEvidenceContractError(
            "observation_loadings",
            "source partition changed",
        ),
    )
    return loadings
end

function import_selected_zero_count(parent_keys, members)
    return count(
        key -> begin
            member = members[key]
            startswith(member.projection_id, "import_") &&
                member.source_cell_state == SELECTED_ZERO_STATE
        end,
        parent_keys,
    )
end

function selected_zero_count(parent_keys, members)
    return count(
        key -> members[key].source_cell_state == SELECTED_ZERO_STATE,
        parent_keys,
    )
end

function owner_display_value(
        parent_keys,
        members,
        scenario_id,
    )
    scenario_id in (PRIMARY_SCENARIO, COUNTERFACTUAL_SCENARIO) ||
        throw(ArgumentError("unsupported scenario $scenario_id"))
    if scenario_id == COUNTERFACTUAL_SCENARIO &&
            import_selected_zero_count(parent_keys, members) > 0
        return nothing
    end
    return sum(source_value(members[key]) for key in parent_keys)
end

function control_family(control_id)
    parts = split(control_id, ':')
    length(parts) >= 3 ||
        throw(
        AdmissionEvidenceContractError(
            "control.$control_id",
            "identifier is malformed",
        ),
    )
    return parts[3]
end

function build_control_diagnostics(
        ledger::ProductionReconciliationLedger,
        contract::AdmissionEvidenceContract,
    )
    cells = Dict(cell.cell_id => cell for cell in ledger.cells)
    target_lineages =
        Dict(lineage.owner_id => lineage for lineage in ledger.target_lineages)
    control_lineages =
        Dict(lineage.owner_id => lineage for lineage in ledger.control_lineages)
    members = Dict(
        member.canonical_source_key => member
            for member in ledger.source_lineage_members
    )
    diagnostics = ControlDisplayDiagnostic[]
    for scenario_id in (PRIMARY_SCENARIO, COUNTERFACTUAL_SCENARIO)
        scenario_status = scenario_id == PRIMARY_SCENARIO ?
            "AUTHENTICATED_RELEASE_SCOPED_DISPLAY_ZERO_NOT_STRUCTURAL_ZERO" :
            "COUNTERFACTUAL_REQUIRING_SAME_WORKBOOK_NOTE_ONLY"
        for control in ledger.controls
            control_lineage = control_lineages[control.control_id]
            term_values = Union{Nothing, Float64}[]
            term_source_leaf_count = 0
            all_term_parent_keys = String[]
            for (cell_id, coefficient) in
                zip(control.term_cell_ids, control.coefficients)
                lineage = target_lineages[cell_id]
                append!(all_term_parent_keys, lineage.parent_source_keys)
                term_source_leaf_count +=
                    round(
                    Int,
                    abs(coefficient) * length(lineage.parent_source_keys),
                )
                push!(
                    term_values,
                    owner_display_value(
                        lineage.parent_source_keys,
                        members,
                        scenario_id,
                    ),
                )
            end
            rhs_parent_keys = control_lineage.parent_source_keys
            rhs_value = if isempty(rhs_parent_keys)
                control.rhs
            else
                owner_display_value(
                    rhs_parent_keys,
                    members,
                    scenario_id,
                )
            end
            all_parent_keys = vcat(all_term_parent_keys, rhs_parent_keys)
            length(all_parent_keys) == length(unique(all_parent_keys)) ||
                throw(
                AdmissionEvidenceContractError(
                    "control.$(control.control_id)",
                    "source leaves are duplicated across an equation",
                ),
            )
            unresolved_import_count =
                import_selected_zero_count(all_parent_keys, members)
            selected_count = selected_zero_count(all_parent_keys, members)
            evaluable =
                rhs_value !== nothing &&
                all(value -> value !== nothing, term_values)
            residual = evaluable ?
                sum(
                    control.coefficients[index] * term_values[index]
                    for index in eachindex(term_values)
                ) - rhs_value :
                nothing
            source_leaf_loading_count =
                term_source_leaf_count + length(rhs_parent_keys)
            half_width = evaluable ?
                Float64(
                    contract.sensitivity[
                        "half_width_per_raw_display_millions",
                    ],
                ) * source_leaf_loading_count :
                nothing
            sensitivity_status = if !evaluable
                "NOT_EVALUABLE_UNRESOLVED_IMPORT_ELLIPSIS"
            elseif abs(residual) <= half_width
                "WITHIN_UNAPPROVED_NEAREST_INTEGER_SENSITIVITY_ENVELOPE"
            else
                "OUTSIDE_UNAPPROVED_NEAREST_INTEGER_SENSITIVITY_ENVELOPE"
            end
            fixed_status = control.control_kind == EXACT_IDENTITY_KIND ?
                "CANDIDATE_EXACT_IDENTITY_NOT_APPROVED" :
                "MEASURED_MARGIN_NOT_FIXED"
            push!(
                diagnostics,
                ControlDisplayDiagnostic(
                    scenario_id,
                    scenario_status,
                    control.control_id,
                    control.control_kind,
                    control_family(control.control_id),
                    length(control.term_cell_ids),
                    term_source_leaf_count,
                    length(rhs_parent_keys),
                    selected_count,
                    scenario_id == COUNTERFACTUAL_SCENARIO ?
                        unresolved_import_count :
                        0,
                    evaluable ?
                        "DISPLAY_POINT_RESIDUAL_EVALUATED" :
                        "NOT_EVALUABLE_UNRESOLVED_IMPORT_ELLIPSIS",
                    residual,
                    residual === nothing ? nothing : residual == 0.0,
                    String(contract.sensitivity["assumption_id"]),
                    half_width,
                    sensitivity_status,
                    fixed_status,
                    false,
                ),
            )
        end
    end
    sort!(
        diagnostics;
        by = item -> (item.scenario_id, item.control_id),
    )
    return diagnostics
end

function load_negative_semantic_records(
        contract::AdmissionEvidenceContract,
    )
    manifest = TOML.parsefile(
        contract.artifacts["negative_cell_semantics_manifest"].path,
    )
    manifest["schema_version"] ==
        "beforeit-us-bea-2024-negative-cell-semantics-fixture.v1" ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_manifest.schema_version",
            "changed",
        ),
    )
    manifest["classification"] ==
        "LITERATURE_BACKED_CELL_LEVEL_SIGN_DOMAIN_EVIDENCE_NOT_SOLVER_ADMISSION" &&
        manifest["promotion_status"] == "RESEARCH_ONLY_NOT_PROMOTED" ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_manifest",
            "classification changed",
        ),
    )
    manifest["candidate_problem_scope_hash"] ==
        contract.candidate_problem_scope_hash &&
        manifest["candidate_problem_hash"] ==
        contract.candidate_problem_hash &&
        manifest["source_zip_sha256"] ==
        contract.revision_evidence["current_archive_sha256"] ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_manifest",
            "problem or source binding changed",
        ),
    )
    manifest["fixture_sha256"] ==
        contract.artifacts["negative_cell_semantics_fixture"].sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_manifest.fixture_sha256",
            "changed",
        ),
    )
    manifest["source_unresolved_cell_count"] == 23 &&
        manifest["literature_supported_signed_cell_count"] == 16 &&
        manifest["remaining_unresolved_cell_count"] == 7 &&
        manifest["used_other_component_resolved"] === false &&
        manifest["solver_admissible"] === false &&
        manifest["reliability_receipt_count"] == 0 &&
        manifest["covariance_receipt_count"] == 0 &&
        manifest["structural_zero_approval_count"] == 0 &&
        manifest["adjustment_record_count"] == 0 &&
        manifest["model_state_write"] === false &&
        manifest["accounting_gate_effect"] == "NONE" &&
        manifest["forecast_score_effect"] == "NONE" ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_manifest",
            "scientific boundary changed",
        ),
    )
    literature_locators = exact_keys(
        manifest["literature_locator"],
        Set(
            [
                "BEA_IO_CONCEPTS_METHODS_2006",
                "BEA_NIPA_HANDBOOK_CHAPTER_7",
                "SNA_2008",
                "BEA_INDUSTRY_CLASSIFICATION_2018",
            ],
        ),
        "negative_semantics_manifest.literature_locator",
    )
    all(
        value -> value isa AbstractString && !isempty(strip(value)),
        values(literature_locators),
    ) ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_manifest.literature_locator",
            "locators must be nonempty strings",
        ),
    )

    table = CSV.File(
        contract.artifacts["negative_cell_semantics_fixture"].path;
        types = Dict(
            Symbol(field) => String for field in NEGATIVE_SEMANTICS_COLUMNS
        ),
    )
    String.(propertynames(first(table))) == NEGATIVE_SEMANTICS_COLUMNS ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_fixture",
            "columns changed",
        ),
    )
    records = NegativeSemanticRecord[]
    for row in table
        push!(
            records,
            NegativeSemanticRecord(
                String(row.cell_id),
                parse(Float64, row.expected_raw_value_millions),
                String(row.source_member),
                String(row.source_workbook_sha256),
                String(row.source_sheet),
                String(row.source_cell_address),
                String(row.evidence_classification_key),
                String(row.evidence_negative_economic_type),
                String(row.evidence_sign_domain),
                String(row.classification_status),
                String(row.component_resolution_status),
                String(row.evidence_ids),
            ),
        )
    end
    length(records) == 23 &&
        length(unique(item.cell_id for item in records)) == 23 &&
        issorted(getfield.(records, :cell_id)) ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_fixture",
            "record identity or ordering changed",
        ),
    )
    for record in records
        signature = get(
            NEGATIVE_CLASSIFICATION_SIGNATURES,
            record.evidence_classification_key,
            nothing,
        )
        signature !== nothing &&
            (
            record.evidence_negative_economic_type,
            record.evidence_sign_domain,
            record.classification_status,
            record.component_resolution_status,
        ) == (
            signature.economic_type,
            signature.sign_domain,
            signature.status,
            signature.component_status,
        ) ||
            throw(
            AdmissionEvidenceContractError(
                "negative_semantics_fixture.$(record.cell_id)",
                "classification signature changed",
            ),
        )
    end
    count(
        item ->
        item.classification_status == "UNRESOLVED_SEMANTIC_BLOCKER",
        records,
    ) == 7 ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_fixture",
            "unresolved partition changed",
        ),
    )
    count(
        item ->
        startswith(item.classification_status, "LITERATURE_SUPPORTED_"),
        records,
    ) == 16 ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_fixture",
            "supported partition changed",
        ),
    )
    literature_ids = Set(item.literature_id for item in contract.literature)
    for record in records
        record_ids = split(record.evidence_ids, '|')
        !isempty(record_ids) &&
            length(unique(record_ids)) == length(record_ids) &&
            all(
            id -> id in literature_ids && haskey(literature_locators, id),
            record_ids,
        ) ||
            throw(
            AdmissionEvidenceContractError(
                "negative_semantics_fixture.$(record.cell_id).evidence_ids",
                "must resolve uniquely to contract literature IDs",
            ),
        )
    end
    return Dict(item.cell_id => item for item in records)
end

function excel_column_label(position::Int)
    position > 0 ||
        throw(ArgumentError("Excel column position must be positive"))
    reversed = UInt8[]
    remaining = position
    while remaining > 0
        remaining, digit = divrem(remaining - 1, 26)
        push!(reversed, UInt8('A') + digit)
    end
    return String(reverse(reversed))
end

function source_cell_address(member::SourceLineageMember)
    data_start_column = if member.projection_id in (
            "import_final_use_2024",
            "producer_final_use_2024",
        )
        75 # BW
    elseif member.projection_id in (
            "import_intermediate_use_2024",
            "producer_intermediate_use_2024",
            "producer_make_2024",
        )
        3 # C
    else
        throw(
            AdmissionEvidenceContractError(
                "negative_semantics_fixture.$(member.canonical_source_key)",
                "unsupported projection for exact workbook-address binding",
            ),
        )
    end
    return excel_column_label(
        data_start_column + member.column_position - 1,
    ) * string(8 + member.row_position - 1)
end

function build_negative_cells(
        ledger::ProductionReconciliationLedger,
        contract::AdmissionEvidenceContract,
    )
    semantic_records = load_negative_semantic_records(contract)
    source_unresolved_ids = Set(
        cell.cell_id
            for cell in ledger.cells
            if cell.raw_value !== nothing &&
            cell.raw_value < 0.0 &&
            startswith(cell.negative_economic_type, "UNRESOLVED_")
    )
    source_unresolved_ids == Set(keys(semantic_records)) ||
        throw(
        AdmissionEvidenceContractError(
            "negative_semantics_fixture",
            "does not exactly partition source-unresolved negative cells",
        ),
    )
    target_lineages =
        Dict(item.owner_id => item for item in ledger.target_lineages)
    source_members = Dict(
        item.canonical_source_key => item
            for item in ledger.source_lineage_members
    )
    records = NegativeCellEvidence[]
    for cell in ledger.cells
        cell.raw_value === nothing && continue
        cell.raw_value < 0.0 || continue
        semantic = get(semantic_records, cell.cell_id, nothing)
        evidence_negative_economic_type = cell.negative_economic_type
        evidence_sign_domain = cell.sign_domain
        classification_status = "SOURCE_MECHANICALLY_TYPED_SIGNED_FLOW"
        component_resolution_status = "NOT_APPLICABLE"
        evidence_ids = "SOURCE_CODE_KEYED_ACCOUNTING_SEMANTICS"
        if semantic !== nothing
            cell.raw_value == semantic.expected_raw_value_millions ||
                throw(
                AdmissionEvidenceContractError(
                    "negative_semantics_fixture.$(cell.cell_id)",
                    "raw value changed",
                ),
            )
            lineage = target_lineages[cell.cell_id]
            length(lineage.parent_source_keys) == 1 ||
                throw(
                AdmissionEvidenceContractError(
                    "negative_semantics_fixture.$(cell.cell_id)",
                    "target is no longer a one-to-one source selection",
                ),
            )
            member = source_members[only(lineage.parent_source_keys)]
            member.source_member == semantic.source_member &&
                member.source_workbook_sha256 ==
                semantic.source_workbook_sha256 &&
                member.row_code == cell.row_code &&
                member.column_code == cell.column_code &&
                semantic.source_sheet == "2024" &&
                source_cell_address(member) == semantic.source_cell_address ||
                throw(
                AdmissionEvidenceContractError(
                    "negative_semantics_fixture.$(cell.cell_id)",
                    "source workbook, coordinate, or address binding changed",
                ),
            )
            evidence_negative_economic_type =
                semantic.evidence_negative_economic_type
            evidence_sign_domain = semantic.evidence_sign_domain
            classification_status = semantic.classification_status
            component_resolution_status =
                semantic.component_resolution_status
            evidence_ids = semantic.evidence_ids
        end
        push!(
            records,
            NegativeCellEvidence(
                cell.cell_id,
                cell.raw_value,
                cell.economic_type,
                cell.negative_economic_type,
                cell.sign_domain,
                evidence_negative_economic_type,
                evidence_sign_domain,
                classification_status,
                component_resolution_status,
                evidence_ids,
                cell.reliability_class_id,
                cell.covariance_group_id,
                cell.approval_id,
                false,
            ),
        )
    end
    sort!(records; by = item -> item.cell_id)
    return records
end

function build_dependence_groups(
        ledger::ProductionReconciliationLedger,
    )
    members = ledger.source_lineage_members
    groups = CandidateDependenceGroup[]
    push!(
        groups,
        CandidateDependenceGroup(
            "RELEASE:" * ledger.cells[1].release_id,
            "SHARED_RELEASE_CANDIDATE",
            length(members),
            "DEPENDENCE_POSSIBLE_NOT_QUANTIFIED",
            "NO_NUMERICAL_CORRELATION_RECEIPT",
            false,
        ),
    )
    workbook_groups = Dict{Tuple{String, String}, Int}()
    projection_groups = Dict{Tuple{String, String}, Int}()
    for member in members
        workbook_key =
            (member.source_member, member.source_workbook_sha256)
        workbook_groups[workbook_key] =
            get(workbook_groups, workbook_key, 0) + 1
        projection_key =
            (member.projection_id, member.projection_sha256)
        projection_groups[projection_key] =
            get(projection_groups, projection_key, 0) + 1
    end
    for ((source_member, source_hash), count) in
        sort!(collect(workbook_groups); by = first)
        push!(
            groups,
            CandidateDependenceGroup(
                "WORKBOOK:$source_member:$source_hash",
                "SHARED_WORKBOOK_CANDIDATE",
                count,
                "DEPENDENCE_POSSIBLE_NOT_QUANTIFIED",
                "NO_NUMERICAL_CORRELATION_RECEIPT",
                false,
            ),
        )
    end
    for ((projection_id, projection_hash), count) in
        sort!(collect(projection_groups); by = first)
        push!(
            groups,
            CandidateDependenceGroup(
                "PROJECTION:$projection_id:$projection_hash",
                "SHARED_PROJECTION_CANDIDATE",
                count,
                "DEPENDENCE_POSSIBLE_NOT_QUANTIFIED",
                "NO_NUMERICAL_CORRELATION_RECEIPT",
                false,
            ),
        )
    end
    sort!(groups; by = item -> (item.group_kind, item.group_id))
    return groups
end

function build_revision_vintages(contract::AdmissionEvidenceContract)
    revision = contract.revision_evidence
    reference_year = Int(revision["common_reference_year_candidate"])
    records = [
        RevisionVintageReceipt(
            String(revision["earlier_release_id"]),
            String(revision["earlier_release_date"]),
            String(revision["earlier_archive_url"]),
            String(revision["earlier_archive_sha256"]),
            reference_year,
            false,
            "HASH_VERIFIED_DURING_DEVELOPMENT_CELL_PANEL_NOT_MATERIALIZED",
            0,
            0,
            false,
        ),
        RevisionVintageReceipt(
            String(revision["current_release_id"]),
            String(revision["current_release_date"]),
            String(revision["current_archive_url"]),
            String(revision["current_archive_sha256"]),
            reference_year,
            false,
            "HASH_MATCHES_CURRENT_AUTHENTICATED_SOURCE_CELL_PANEL_NOT_MATERIALIZED",
            0,
            0,
            false,
        ),
    ]
    sort!(records; by = item -> (item.release_date, item.release_id))
    return records
end

function evidence_hash(
        contract_sha256,
        problem_scope_hash,
        problem_hash,
        display_records,
        marker_receipts,
        valuation_boundaries,
        domestic_use_points,
        loadings,
        diagnostics,
        negative_cells,
        dependence_groups,
        revision_vintages,
        blockers,
    )
    parts = Any[
        REPORT_SCHEMA,
        contract_sha256,
        problem_scope_hash,
        problem_hash,
    ]
    for record in display_records
        append!(
            parts,
            [getfield(record, field) for field in fieldnames(SourceDisplayRecord)],
        )
    end
    for receipt in marker_receipts
        append!(
            parts,
            [
                getfield(receipt, field)
                    for field in fieldnames(ReleaseMarkerReceipt)
            ],
        )
    end
    for boundary in valuation_boundaries
        append!(
            parts,
            [
                getfield(boundary, field)
                    for field in fieldnames(ValuationImportBoundaryEvidence)
            ],
        )
    end
    for record in domestic_use_points
        append!(
            parts,
            [
                getfield(record, field)
                    for field in fieldnames(DomesticUsePointRecord)
            ],
        )
    end
    for loading in loadings
        append!(
            parts,
            [getfield(loading, field) for field in fieldnames(ObservationLoading)],
        )
    end
    for item in diagnostics
        append!(
            parts,
            [
                getfield(item, field)
                    for field in fieldnames(ControlDisplayDiagnostic)
            ],
        )
    end
    for item in negative_cells
        append!(
            parts,
            [getfield(item, field) for field in fieldnames(NegativeCellEvidence)],
        )
    end
    for item in dependence_groups
        append!(
            parts,
            [
                getfield(item, field)
                    for field in fieldnames(CandidateDependenceGroup)
            ],
        )
    end
    for item in revision_vintages
        append!(
            parts,
            [
                getfield(item, field)
                    for field in fieldnames(RevisionVintageReceipt)
            ],
        )
    end
    append!(parts, blockers)
    return "admission1:" * digest(parts...)
end

function _build_production_reconciliation_admission_evidence(
        contract::AdmissionEvidenceContract,
        ledger::ProductionReconciliationLedger,
    )
    ledger.problem_scope_hash == contract.candidate_problem_scope_hash ||
        throw(
        AdmissionEvidenceContractError(
            "candidate.problem_scope_hash",
            "changed",
        ),
    )
    ledger.problem_hash == contract.candidate_problem_hash ||
        throw(
        AdmissionEvidenceContractError(
            "candidate.problem_hash",
            "changed",
        ),
    )
    ledger.contract_sha256 == contract.candidate_ledger_contract_sha256 ||
        throw(
        AdmissionEvidenceContractError(
            "candidate.contract_sha256",
            "changed",
        ),
    )
    display_records = load_source_display_records(contract)
    marker_receipts = load_release_marker_receipts(contract)
    valuation_boundaries = build_valuation_import_boundaries(contract)
    domestic_use_points = build_domestic_use_points(ledger)
    loadings = build_observation_loadings(ledger)
    diagnostics = build_control_diagnostics(ledger, contract)
    negative_cells = build_negative_cells(ledger, contract)
    dependence_groups = build_dependence_groups(ledger)
    revision_vintages = build_revision_vintages(contract)
    report_hash = evidence_hash(
        contract.source_sha256,
        ledger.problem_scope_hash,
        ledger.problem_hash,
        display_records,
        marker_receipts,
        valuation_boundaries,
        domestic_use_points,
        loadings,
        diagnostics,
        negative_cells,
        dependence_groups,
        revision_vintages,
        contract.promotion_blockers,
    )
    return ProductionReconciliationAdmissionEvidenceReport(
        REPORT_SCHEMA,
        contract.source_sha256,
        ledger.problem_scope_hash,
        ledger.problem_hash,
        report_hash,
        display_records,
        marker_receipts,
        valuation_boundaries,
        domestic_use_points,
        loadings,
        diagnostics,
        negative_cells,
        dependence_groups,
        revision_vintages,
        copy(contract.promotion_blockers),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        false,
        false,
        false,
        "NONE",
        "NONE",
    )
end

function scenario_diagnostics(report, scenario_id)
    return filter(
        item -> item.scenario_id == scenario_id,
        report.control_diagnostics,
    )
end

function count_diagnostics(items, kind, predicate)
    return count(
        item -> item.control_kind == kind && predicate(item),
        items,
    )
end

function domestic_point_matches_loadings(
        record::DomesticUsePointRecord,
        target_loadings::Dict{String, Vector{ObservationLoading}},
    )
    producer = get(target_loadings, record.producer_use_cell_id, nothing)
    imports = get(target_loadings, record.imputed_import_cell_id, nothing)
    producer === nothing && return false
    imports === nothing && return false
    isempty(producer) && return false
    isempty(imports) && return false
    target_coordinate_suffix = ":$(record.row_code):$(record.column_code)"
    endswith(record.cell_id, target_coordinate_suffix) || return false
    endswith(record.producer_use_cell_id, target_coordinate_suffix) ||
        return false
    endswith(record.imputed_import_cell_id, target_coordinate_suffix) ||
        return false
    all(
        item -> !startswith(item.projection_id, "import_"),
        producer,
    ) || return false
    all(
        item -> startswith(item.projection_id, "import_"),
        imports,
    ) || return false
    sort([(item.row_code, item.column_code) for item in producer]) ==
        sort([(item.row_code, item.column_code) for item in imports]) ||
        return false
    parents = vcat(producer, imports)
    parent_keys = sort!(getfield.(parents, :canonical_source_key))
    length(parent_keys) == length(unique(parent_keys)) || return false
    selected_count = count(
        item -> item.source_cell_state == SELECTED_ZERO_STATE,
        parents,
    )
    producer_value =
        sum(parse(Float64, item.source_value_token) for item in producer)
    import_value =
        sum(parse(Float64, item.source_value_token) for item in imports)
    display_point_value = producer_value - import_value
    raw_numeric_residual =
        selected_count == 0 ? display_point_value : nothing
    lineage_by_key = Dict(
        item.canonical_source_key => item.source_lineage_hash
            for item in parents
    )
    lineage_hash = "domestic1:" * digest(
        record.cell_id,
        record.producer_use_cell_id,
        record.imputed_import_cell_id,
        PRIMARY_SCENARIO,
        (key * "|" * lineage_by_key[key] for key in parent_keys)...,
    )
    return record.display_scenario_id == PRIMARY_SCENARIO &&
        record.display_point_value_millions == display_point_value &&
        isequal(
        record.raw_numeric_residual_millions,
        raw_numeric_residual,
    ) &&
        record.input_selected_zero_count == selected_count &&
        record.raw_source_leaf_count == length(parents) &&
        record.lineage_hash == lineage_hash
end

function production_reconciliation_admission_evidence_internal_controls_pass(
        report::ProductionReconciliationAdmissionEvidenceReport,
        contract::AdmissionEvidenceContract,
    )
    try
        expected = contract.expected
        report.schema_version == REPORT_SCHEMA || return false
        report.contract_sha256 == contract.source_sha256 || return false
        report.candidate_problem_scope_hash ==
            contract.candidate_problem_scope_hash || return false
        report.candidate_problem_hash == contract.candidate_problem_hash ||
            return false
        startswith(report.evidence_hash, "admission1:") || return false
        length(report.source_display_records) == 12 || return false
        length(report.release_marker_receipts) ==
            expected["release_marker_receipt_count"] || return false
        all(
            item ->
            item.exact_common_basis_coordinate_match &&
                item.exact_common_basis_full_grid_match &&
                item.full_grid_exact_match_count ==
                item.projection_cell_count &&
                item.full_grid_mismatch_count == 0 &&
                item.full_grid_maximum_absolute_difference_millions == 0 &&
                is_sha256(item.canonical_full_grid_sha256) &&
                !item.solver_admissible,
            report.release_marker_receipts,
        ) || return false
        only(
            item
                for item in report.release_marker_receipts
                if item.table_key == "UIMARI"
        ).marker_count ==
            expected["import_selected_zero_source_leaf_count"] || return false
        length(report.valuation_import_boundaries) ==
            expected["valuation_import_boundary_count"] || return false
        all(
            item -> !item.solver_admissible,
            report.valuation_import_boundaries,
        ) || return false
        target_loadings = Dict{String, Vector{ObservationLoading}}()
        for item in report.observation_loadings
            item.owner_kind == "TARGET_CELL" || continue
            push!(
                get!(target_loadings, item.owner_id, ObservationLoading[]),
                item,
            )
        end
        length(report.domestic_use_points) ==
            expected["domestic_use_point_count"] || return false
        count(
            item -> item.raw_numeric_residual_millions !== nothing,
            report.domestic_use_points,
        ) == expected["domestic_use_raw_evaluable_count"] || return false
        length(
            unique(
                item.cell_id for item in report.domestic_use_points
            )
        ) == length(report.domestic_use_points) || return false
        length(
            unique(
                item.lineage_hash for item in report.domestic_use_points
            )
        ) == length(report.domestic_use_points) || return false
        all(
            item -> domestic_point_matches_loadings(item, target_loadings),
            report.domestic_use_points,
        ) || return false
        all(
            item ->
            startswith(item.lineage_hash, "domestic1:") &&
                item.display_scenario_id == PRIMARY_SCENARIO &&
                !item.independent_observation &&
                !item.solver_admissible &&
                (
                item.input_selected_zero_count == 0 ?
                    item.raw_numeric_residual_millions !== nothing &&
                    item.evaluation_status ==
                    "RAW_NUMERIC_RESIDUAL_EVALUATED" :
                    item.raw_numeric_residual_millions === nothing &&
                    item.evaluation_status ==
                    "RAW_RESIDUAL_NOT_EVALUABLE_SELECTED_ZERO_PARENT_DISPLAY_POINT_ONLY"
            ),
            report.domestic_use_points,
        ) || return false
        count(
            item ->
            item.boundary_role ==
                "IMPORT_ACCOUNTING_OFFSET_DIAGNOSTIC_ONLY",
            report.domestic_use_points,
        ) == expected["domestic_f050_diagnostic_count"] || return false
        length(report.observation_loadings) ==
            expected["observation_loading_count"] || return false
        length(report.observation_loadings) ==
            expected["source_lineage_member_count"] || return false
        length(unique(item.canonical_source_key for item in report.observation_loadings)) ==
            length(report.observation_loadings) || return false
        target_owners = unique(
            item.owner_id
                for item in report.observation_loadings
                if item.owner_kind == "TARGET_CELL"
        )
        measured_owners = unique(
            item.owner_id
                for item in report.observation_loadings
                if item.owner_kind == "MEASURED_PUBLISHED_MARGIN_RHS"
        )
        length(target_owners) == expected["target_loading_owner_count"] ||
            return false
        length(target_owners) == expected["candidate_cell_count"] ||
            return false
        length(measured_owners) ==
            expected["measured_control_loading_owner_count"] || return false
        length(union(Set(target_owners), Set(measured_owners))) ==
            expected["observation_loading_owner_count"] || return false
        owner_loading_counts = Dict{Tuple{String, String}, Int}()
        for item in report.observation_loadings
            key = (item.owner_kind, item.owner_id)
            owner_loading_counts[key] =
                get(owner_loading_counts, key, 0) + 1
        end
        count(
            item ->
            item.first[1] == "TARGET_CELL" && item.second > 1,
            owner_loading_counts,
        ) == expected["target_multi_source_owner_count"] || return false
        count(
            item ->
            item.first[1] == "MEASURED_PUBLISHED_MARGIN_RHS" &&
                item.second > 1,
            owner_loading_counts,
        ) == expected["measured_control_multi_source_owner_count"] ||
            return false
        all(
            item ->
            item.coefficient == 1.0 &&
                item.numerical_reliability_receipt_id === nothing &&
                item.numerical_covariance_receipt_id === nothing &&
                !item.solver_admissible,
            report.observation_loadings,
        ) || return false
        producer_selected = count(
            item ->
            !startswith(item.projection_id, "import_") &&
                item.source_cell_state == SELECTED_ZERO_STATE,
            report.observation_loadings,
        )
        import_selected = count(
            item ->
            startswith(item.projection_id, "import_") &&
                item.source_cell_state == SELECTED_ZERO_STATE,
            report.observation_loadings,
        )
        producer_selected ==
            expected["producer_selected_zero_source_leaf_count"] || return false
        import_selected ==
            expected["import_selected_zero_source_leaf_count"] || return false

        primary = scenario_diagnostics(report, PRIMARY_SCENARIO)
        counterfactual =
            scenario_diagnostics(report, COUNTERFACTUAL_SCENARIO)
        length(primary) == expected["candidate_control_count"] || return false
        length(counterfactual) == expected["candidate_control_count"] ||
            return false
        count(item -> item.control_kind == EXACT_IDENTITY_KIND, primary) ==
            expected["candidate_identity_count"] || return false
        count(item -> item.control_kind == MEASURED_MARGIN_KIND, primary) ==
            expected["published_control_count"] || return false
        count_diagnostics(
            primary,
            EXACT_IDENTITY_KIND,
            item -> item.point_residual_millions !== nothing,
        ) == expected["primary_evaluable_identity_count"] || return false
        count_diagnostics(
            primary,
            EXACT_IDENTITY_KIND,
            item -> item.point_residual_millions === nothing,
        ) == expected["primary_nonevaluable_identity_count"] || return false
        count_diagnostics(
            primary,
            EXACT_IDENTITY_KIND,
            item -> item.point_residual_zero === true,
        ) == expected["primary_zero_residual_identity_count"] || return false
        count_diagnostics(
            primary,
            EXACT_IDENTITY_KIND,
            item ->
            item.point_residual_zero === false,
        ) == expected["primary_nonzero_residual_identity_count"] ||
            return false
        count_diagnostics(
            primary,
            MEASURED_MARGIN_KIND,
            item -> item.point_residual_millions !== nothing,
        ) == expected["primary_evaluable_published_count"] || return false
        count_diagnostics(
            primary,
            MEASURED_MARGIN_KIND,
            item -> item.point_residual_millions === nothing,
        ) == expected["primary_nonevaluable_published_count"] || return false
        count_diagnostics(
            primary,
            MEASURED_MARGIN_KIND,
            item -> item.point_residual_zero === true,
        ) == expected["primary_zero_residual_published_count"] || return false
        count_diagnostics(
            primary,
            MEASURED_MARGIN_KIND,
            item ->
            item.point_residual_zero === false,
        ) == expected["primary_nonzero_residual_published_count"] ||
            return false
        count(
            item ->
            item.sensitivity_status ==
                "WITHIN_UNAPPROVED_NEAREST_INTEGER_SENSITIVITY_ENVELOPE",
            primary,
        ) == expected["primary_within_sensitivity_count"] || return false

        count_diagnostics(
            counterfactual,
            EXACT_IDENTITY_KIND,
            item -> item.point_residual_millions !== nothing,
        ) == expected["counterfactual_evaluable_identity_count"] ||
            return false
        count_diagnostics(
            counterfactual,
            EXACT_IDENTITY_KIND,
            item -> item.point_residual_millions === nothing,
        ) == expected["counterfactual_nonevaluable_identity_count"] ||
            return false
        count_diagnostics(
            counterfactual,
            EXACT_IDENTITY_KIND,
            item -> item.point_residual_zero === true,
        ) == expected["counterfactual_zero_residual_identity_count"] ||
            return false
        count_diagnostics(
            counterfactual,
            EXACT_IDENTITY_KIND,
            item ->
            item.point_residual_zero === false,
        ) == expected["counterfactual_nonzero_residual_identity_count"] ||
            return false
        count_diagnostics(
            counterfactual,
            MEASURED_MARGIN_KIND,
            item -> item.point_residual_millions !== nothing,
        ) == expected["counterfactual_evaluable_published_count"] ||
            return false
        count_diagnostics(
            counterfactual,
            MEASURED_MARGIN_KIND,
            item -> item.point_residual_millions === nothing,
        ) == expected["counterfactual_nonevaluable_published_count"] ||
            return false
        count_diagnostics(
            counterfactual,
            MEASURED_MARGIN_KIND,
            item -> item.point_residual_zero === true,
        ) == expected["counterfactual_zero_residual_published_count"] ||
            return false
        count_diagnostics(
            counterfactual,
            MEASURED_MARGIN_KIND,
            item ->
            item.point_residual_zero === false,
        ) == expected["counterfactual_nonzero_residual_published_count"] ||
            return false
        count(
            item ->
            item.sensitivity_status ==
                "WITHIN_UNAPPROVED_NEAREST_INTEGER_SENSITIVITY_ENVELOPE",
            counterfactual,
        ) == expected["counterfactual_within_sensitivity_count"] ||
            return false
        maximum(
            abs(item.point_residual_millions)
                for item in primary
                if item.control_kind == EXACT_IDENTITY_KIND
        ) == expected["identity_maximum_absolute_residual_millions"] ||
            return false
        maximum(
            abs(item.point_residual_millions)
                for item in primary
                if item.control_kind == MEASURED_MARGIN_KIND
        ) == expected["published_maximum_absolute_residual_millions"] ||
            return false
        all(!item.solver_admissible for item in report.control_diagnostics) ||
            return false

        length(report.negative_cells) == expected["negative_cell_count"] ||
            return false
        count(
            item ->
            startswith(
                item.source_negative_economic_type,
                "UNRESOLVED_",
            ),
            report.negative_cells,
        ) == expected["source_unresolved_negative_cell_count"] ||
            return false
        count(
            item ->
            item.classification_status == "UNRESOLVED_SEMANTIC_BLOCKER",
            report.negative_cells,
        ) == expected["unresolved_negative_cell_count"] || return false
        count(
            item ->
            startswith(
                item.classification_status,
                "LITERATURE_SUPPORTED_",
            ),
            report.negative_cells,
        ) == expected["literature_supported_negative_cell_count"] ||
            return false
        count(
            item ->
            item.classification_status ==
                "SOURCE_MECHANICALLY_TYPED_SIGNED_FLOW",
            report.negative_cells,
        ) == expected["source_mechanically_typed_negative_cell_count"] ||
            return false
        count(
            item ->
            occursin(
                "COMPONENT_AND_COUNTERPART_UNRESOLVED_2024",
                item.component_resolution_status,
            ) ||
                item.component_resolution_status ==
                "OTHER_COMPONENT_ATTRIBUTION_UNRESOLVED_2024",
            report.negative_cells,
        ) == expected["component_unresolved_signed_cell_count"] ||
            return false
        all(
            item ->
            !startswith(
                item.classification_status,
                "LITERATURE_SUPPORTED_",
            ) ||
                item.evidence_sign_domain == "SIGNED_FLOW",
            report.negative_cells,
        ) || return false
        all(
            item ->
            item.reliability_class_id === nothing &&
                item.covariance_group_id === nothing &&
                item.approval_id === nothing &&
                !item.solver_admissible,
            report.negative_cells,
        ) || return false
        length(report.dependence_groups) ==
            expected["candidate_dependence_group_count"] || return false
        all(
            item ->
            item.numerical_parameter_status ==
                "NO_NUMERICAL_CORRELATION_RECEIPT" &&
                !item.solver_admissible,
            report.dependence_groups,
        ) || return false
        length(report.revision_vintages) ==
            expected["revision_vintage_receipt_count"] || return false
        all(
            item ->
            !item.checked_in_cell_fixture &&
                item.numerical_reliability_receipt_count == 0 &&
                item.numerical_covariance_receipt_count == 0 &&
                !item.solver_admissible,
            report.revision_vintages,
        ) || return false

        report.evidence_hash == evidence_hash(
            report.contract_sha256,
            report.candidate_problem_scope_hash,
            report.candidate_problem_hash,
            report.source_display_records,
            report.release_marker_receipts,
            report.valuation_import_boundaries,
            report.domestic_use_points,
            report.observation_loadings,
            report.control_diagnostics,
            report.negative_cells,
            report.dependence_groups,
            report.revision_vintages,
            report.promotion_blockers,
        ) || return false
        report.promotion_blockers == contract.promotion_blockers ||
            return false
        report.solver_invocation_count == 0 || return false
        report.solver_input_cell_count ==
            expected["solver_input_cell_count"] == 0 || return false
        report.solver_input_control_count ==
            expected["solver_input_control_count"] == 0 || return false
        report.approved_exact_control_count ==
            expected["approved_exact_control_count"] == 0 || return false
        report.approved_structural_zero_count ==
            expected["approved_structural_zero_count"] == 0 || return false
        report.numerical_reliability_receipt_count ==
            expected["numerical_reliability_receipt_count"] == 0 ||
            return false
        report.numerical_covariance_receipt_count ==
            expected["numerical_covariance_receipt_count"] == 0 ||
            return false
        report.adjustment_record_count ==
            expected["adjustment_record_count"] == 0 || return false
        !report.forecast_origin_admissible || return false
        !report.promotion_ready || return false
        !report.model_state_write || return false
        report.accounting_gate_effect == "NONE" || return false
        report.forecast_score_effect == "NONE" || return false
    catch
        return false
    end
    return true
end

function production_reconciliation_admission_evidence_controls_pass(
        report::ProductionReconciliationAdmissionEvidenceReport,
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    try
        contract =
            load_admission_evidence_contract(contract_path; repo_root)
        return production_reconciliation_admission_evidence_internal_controls_pass(
            report,
            contract,
        ) && all(
            file_sha256(binding.path) == binding.sha256
                for binding in values(contract.artifacts)
        )
    catch
        return false
    end
end

function build_production_reconciliation_admission_evidence(
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    contract =
        load_admission_evidence_contract(contract_path; repo_root)
    before_hashes = Dict(
        id => file_sha256(binding.path)
            for (id, binding) in contract.artifacts
    )
    ledger = build_production_reconciliation_ledger(
        contract.artifacts["candidate_ledger_contract"].path;
        repo_root,
    )
    report = _build_production_reconciliation_admission_evidence(
        contract,
        ledger,
    )
    production_reconciliation_admission_evidence_internal_controls_pass(
        report,
        contract,
    ) ||
        throw(
        AdmissionEvidenceContractError(
            "report",
            "internal controls do not pass",
        ),
    )
    for (id, binding) in contract.artifacts
        file_sha256(binding.path) == before_hashes[id] ||
            throw(
            AdmissionEvidenceContractError(
                "artifact.$id",
                "changed during construction",
            ),
        )
    end
    return report
end

function materialize_production_reconciliation_admission_solver_input(
        report::ProductionReconciliationAdmissionEvidenceReport,
    )
    throw(AdmissionSolverBlockedError(copy(report.promotion_blockers)))
end

function render_csv_value(value)
    value === nothing && return ""
    value isa Bool && return lowercase(string(value))
    value isa AbstractVector && return join(string.(value), "|")
    return string(value)
end

function csv_escape(value)
    text = render_csv_value(value)
    if occursin(',', text) ||
            occursin('"', text) ||
            occursin('\n', text) ||
            occursin('\r', text)
        return "\"" * replace(text, "\"" => "\"\"") * "\""
    end
    return text
end

function write_csv(path, headers, rows)
    open(path, "w") do io
        println(io, join(headers, ","))
        for row in rows
            println(io, join((csv_escape(value) for value in row), ","))
        end
    end
    return path
end

function toml_quote(value)
    text = string(value)
    escaped = replace(
        text,
        "\\" => "\\\\",
        "\"" => "\\\"",
        "\n" => "\\n",
        "\r" => "\\r",
        "\t" => "\\t",
    )
    return "\"" * escaped * "\""
end

function write_status(path, report, contract)
    primary = scenario_diagnostics(report, PRIMARY_SCENARIO)
    counterfactual =
        scenario_diagnostics(report, COUNTERFACTUAL_SCENARIO)
    open(path, "w") do io
        println(io, "schema_version = ", toml_quote(STATUS_SCHEMA))
        println(io, "contract_id = ", toml_quote(contract.contract_id))
        println(io, "contract_sha256 = ", toml_quote(report.contract_sha256))
        println(
            io,
            "candidate_problem_scope_hash = ",
            toml_quote(report.candidate_problem_scope_hash),
        )
        println(
            io,
            "candidate_problem_hash = ",
            toml_quote(report.candidate_problem_hash),
        )
        println(io, "evidence_hash = ", toml_quote(report.evidence_hash))
        println(
            io,
            "classification = ",
            toml_quote(contract.classification),
        )
        println(
            io,
            "source_display_record_count = ",
            length(report.source_display_records),
        )
        println(
            io,
            "release_marker_receipt_count = ",
            length(report.release_marker_receipts),
        )
        println(
            io,
            "valuation_import_boundary_count = ",
            length(report.valuation_import_boundaries),
        )
        println(
            io,
            "domestic_use_point_count = ",
            length(report.domestic_use_points),
        )
        println(
            io,
            "domestic_use_raw_evaluable_count = ",
            count(
                item -> item.raw_numeric_residual_millions !== nothing,
                report.domestic_use_points,
            ),
        )
        println(
            io,
            "observation_loading_count = ",
            length(report.observation_loadings),
        )
        println(
            io,
            "primary_evaluable_control_count = ",
            count(item -> item.point_residual_millions !== nothing, primary),
        )
        println(
            io,
            "primary_nonevaluable_control_count = ",
            count(item -> item.point_residual_millions === nothing, primary),
        )
        println(
            io,
            "counterfactual_evaluable_control_count = ",
            count(
                item -> item.point_residual_millions !== nothing,
                counterfactual,
            ),
        )
        println(
            io,
            "counterfactual_zero_point_residual_count = ",
            count(
                item -> item.point_residual_zero === true,
                counterfactual,
            ),
        )
        println(
            io,
            "counterfactual_nonzero_point_residual_count = ",
            count(
                item -> item.point_residual_zero === false,
                counterfactual,
            ),
        )
        println(
            io,
            "negative_cell_count = ",
            length(report.negative_cells),
        )
        println(
            io,
            "unresolved_negative_cell_count = ",
            count(
                item ->
                item.classification_status == "UNRESOLVED_SEMANTIC_BLOCKER",
                report.negative_cells,
            ),
        )
        println(
            io,
            "literature_supported_negative_cell_count = ",
            count(
                item ->
                startswith(
                    item.classification_status,
                    "LITERATURE_SUPPORTED_",
                ),
                report.negative_cells,
            ),
        )
        println(
            io,
            "candidate_dependence_group_count = ",
            length(report.dependence_groups),
        )
        println(
            io,
            "revision_vintage_receipt_count = ",
            length(report.revision_vintages),
        )
        println(io, "solver_invocation_count = 0")
        println(io, "solver_input_cell_count = 0")
        println(io, "solver_input_control_count = 0")
        println(io, "approved_exact_control_count = 0")
        println(io, "approved_structural_zero_count = 0")
        println(io, "numerical_reliability_receipt_count = 0")
        println(io, "numerical_covariance_receipt_count = 0")
        println(io, "adjustment_record_count = 0")
        println(io, "forecast_origin_admissible = false")
        println(io, "promotion_ready = false")
        println(io, "model_state_write = false")
        println(io, "accounting_gate_effect = \"NONE\"")
        println(io, "forecast_score_effect = \"NONE\"")
        println(
            io,
            "promotion_blockers = [",
            join(
                (toml_quote(item) for item in report.promotion_blockers),
                ", ",
            ),
            "]",
        )
    end
    return path
end

function write_manifest(path, report, contract, outputs)
    open(path, "w") do io
        println(io, "schema_version = ", toml_quote(MANIFEST_SCHEMA))
        println(io, "contract_id = ", toml_quote(contract.contract_id))
        println(io, "contract_sha256 = ", toml_quote(report.contract_sha256))
        println(
            io,
            "module_normalized_sha256 = ",
            toml_quote(contract.module_normalized_sha256),
        )
        println(io, "runner_sha256 = ", toml_quote(contract.runner_sha256))
        println(
            io,
            "candidate_problem_scope_hash = ",
            toml_quote(report.candidate_problem_scope_hash),
        )
        println(
            io,
            "candidate_problem_hash = ",
            toml_quote(report.candidate_problem_hash),
        )
        println(io, "evidence_hash = ", toml_quote(report.evidence_hash))
        println(io, "julia_version = ", toml_quote(VERSION))
        println(io, "machine = ", toml_quote(Sys.MACHINE))
        println(io, "word_size = ", Sys.WORD_SIZE)
        println(io, "solver_invocation_count = 0")
        println(io, "forecast_origin_admissible = false")
        println(io, "promotion_ready = false")
        for output in outputs
            println(io)
            println(io, "[[output]]")
            println(io, "role = ", toml_quote(output.role))
            println(io, "path = ", toml_quote(output.path))
            println(io, "sha256 = ", toml_quote(output.sha256))
        end
    end
    return path
end

function write_production_reconciliation_admission_evidence_report(
        output_directory::AbstractString,
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    contract =
        load_admission_evidence_contract(contract_path; repo_root)
    report = build_production_reconciliation_admission_evidence(
        contract_path;
        repo_root,
    )
    mkpath(output_directory)
    display_path =
        joinpath(output_directory, "source_display_records.csv")
    loading_path =
        joinpath(output_directory, "observation_loadings.csv")
    marker_receipt_path =
        joinpath(output_directory, "release_marker_receipts.csv")
    valuation_boundary_path =
        joinpath(output_directory, "valuation_import_boundaries.csv")
    domestic_use_path =
        joinpath(output_directory, "domestic_use_points.csv")
    control_path =
        joinpath(output_directory, "control_display_diagnostics.csv")
    negative_path =
        joinpath(output_directory, "negative_cell_evidence.csv")
    dependence_path =
        joinpath(output_directory, "candidate_dependence_groups.csv")
    revision_path =
        joinpath(output_directory, "revision_vintage_receipts.csv")
    status_path =
        joinpath(output_directory, "admission_evidence_status.toml")
    manifest_path =
        joinpath(output_directory, "admission_evidence_manifest.toml")

    for (path, type, rows) in (
            (
                display_path,
                SourceDisplayRecord,
                report.source_display_records,
            ),
            (
                marker_receipt_path,
                ReleaseMarkerReceipt,
                report.release_marker_receipts,
            ),
            (
                valuation_boundary_path,
                ValuationImportBoundaryEvidence,
                report.valuation_import_boundaries,
            ),
            (
                domestic_use_path,
                DomesticUsePointRecord,
                report.domestic_use_points,
            ),
            (
                loading_path,
                ObservationLoading,
                report.observation_loadings,
            ),
            (
                control_path,
                ControlDisplayDiagnostic,
                report.control_diagnostics,
            ),
            (
                negative_path,
                NegativeCellEvidence,
                report.negative_cells,
            ),
            (
                dependence_path,
                CandidateDependenceGroup,
                report.dependence_groups,
            ),
            (
                revision_path,
                RevisionVintageReceipt,
                report.revision_vintages,
            ),
        )
        fields = fieldnames(type)
        write_csv(
            path,
            String.(fields),
            (
                Any[getfield(item, field) for field in fields]
                    for item in rows
            ),
        )
    end
    write_status(status_path, report, contract)
    output_paths = [
        (
            role = "SOURCE_DISPLAY_RECORDS",
            path = basename(display_path),
            full_path = display_path,
        ),
        (
            role = "RELEASE_MARKER_RECEIPTS",
            path = basename(marker_receipt_path),
            full_path = marker_receipt_path,
        ),
        (
            role = "VALUATION_IMPORT_BOUNDARIES",
            path = basename(valuation_boundary_path),
            full_path = valuation_boundary_path,
        ),
        (
            role = "DOMESTIC_USE_POINTS",
            path = basename(domestic_use_path),
            full_path = domestic_use_path,
        ),
        (
            role = "OBSERVATION_LOADINGS",
            path = basename(loading_path),
            full_path = loading_path,
        ),
        (
            role = "CONTROL_DISPLAY_DIAGNOSTICS",
            path = basename(control_path),
            full_path = control_path,
        ),
        (
            role = "NEGATIVE_CELL_EVIDENCE",
            path = basename(negative_path),
            full_path = negative_path,
        ),
        (
            role = "CANDIDATE_DEPENDENCE_GROUPS",
            path = basename(dependence_path),
            full_path = dependence_path,
        ),
        (
            role = "REVISION_VINTAGE_RECEIPTS",
            path = basename(revision_path),
            full_path = revision_path,
        ),
        (
            role = "ADMISSION_EVIDENCE_STATUS",
            path = basename(status_path),
            full_path = status_path,
        ),
    ]
    outputs = [
        (
                role = item.role,
                path = item.path,
                sha256 = file_sha256(item.full_path),
            )
            for item in output_paths
    ]
    write_manifest(manifest_path, report, contract, outputs)
    production_reconciliation_admission_evidence_controls_pass(
        report,
        contract_path;
        repo_root,
    ) ||
        throw(
        AdmissionEvidenceContractError(
            "report",
            "post-write controls do not pass",
        ),
    )
    return (
        report = report,
        manifest_path = manifest_path,
        manifest_sha256 = file_sha256(manifest_path),
        outputs = outputs,
    )
end

end
