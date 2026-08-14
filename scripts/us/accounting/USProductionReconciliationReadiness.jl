module USProductionReconciliationReadiness

using SHA
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsValuationEnvelope.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsFinalUseEnvelope.jl"))
include(
    joinpath(
        @__DIR__,
        "USAfterRedefinitionsProducerPriceAdapterCandidate.jl",
    ),
)
include(joinpath(@__DIR__, "USProductionReconciliationLedger.jl"))
include(joinpath(@__DIR__, "USProductionReconciliationAdmissionEvidence.jl"))

export CONTRACT_SCHEMA,
    STATUS_SCHEMA,
    REPORT_MANIFEST_SCHEMA,
    APPROVED_CONTRACT_SHA256,
    ReadinessContractError,
    ArtifactIntegrityError,
    EvidenceProbeError,
    ProductionReconciliationBlockedError,
    ArtifactBinding,
    EvidenceProbe,
    AdmissionBlockerMapping,
    SourceFamily,
    ReadinessBlocker,
    ReadinessCriterion,
    SolverCandidate,
    LiteratureCitation,
    ProductionReadinessContract,
    ArtifactValidation,
    EvidenceProbeResult,
    ProductionReadinessResult,
    file_sha256,
    normalized_module_sha256,
    load_production_readiness_contract,
    validate_production_readiness_contract,
    evaluate_production_readiness,
    require_production_reconciliation_ready,
    build_production_readiness_report

const CONTRACT_SCHEMA =
    "beforeit-us-production-reconciliation-readiness-contract.v2"
const STATUS_SCHEMA =
    "beforeit-us-production-reconciliation-readiness-status.v2"
const REPORT_MANIFEST_SCHEMA =
    "beforeit-us-production-reconciliation-readiness-manifest.v2"
const APPROVED_CONTRACT_SHA256 =
    "e21222f862a35ff52c6720e3692aae51ef73f1fafacaef33428e493cfaff69cf"
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "production_reconciliation_readiness.toml")
const DEFAULT_REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const ZERO_SHA256 = repeat("0", 64)

const CONTRACT_KEYS = Set(
    [
        "schema_version",
        "contract_id",
        "classification",
        "promotion_status",
        "scientific_scope",
        "admission_evidence_hash",
        "target_country",
        "target_reference_period",
        "target_frequency",
        "target_time_basis",
        "target_stock_flow_class",
        "target_currency",
        "target_unit",
        "target_price_basis",
        "target_axis",
        "solver_method_id",
        "solver_invocation_status",
        "artifact_hash_policy",
        "missing_value_policy",
        "zero_policy",
        "sign_policy",
        "structural_zero_policy",
        "exact_control_policy",
        "reliability_policy",
        "covariance_policy",
        "control_dependency_policy",
        "lineage_policy",
        "production_cell_schema_fields",
        "production_control_schema_fields",
        "allowed_control_kinds",
        "forecast_origin_admissible",
        "promotion_ready",
        "model_state_write",
        "accounting_gate_effect",
        "forecast_score_effect",
        "implementation",
        "expected",
        "artifact",
        "probe",
        "admission_blocker_mapping",
        "source_family",
        "blocker",
        "criterion",
        "solver_candidate",
        "citation",
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
const EXPECTED_KEYS = Set(
    [
        "artifact_count",
        "probe_count",
        "source_family_count",
        "blocker_count",
        "criterion_count",
        "mandatory_criterion_count",
        "passed_criterion_count",
        "blocked_criterion_count",
        "solver_candidate_count",
        "admitted_solver_family_count",
        "solver_input_cell_count",
        "solver_input_control_count",
        "production_reliability_class_count",
        "production_covariance_class_count",
        "approved_exact_control_count",
        "approved_structural_zero_count",
        "reconciliation_run_count",
        "adjustment_record_count",
    ],
)
const ARTIFACT_KEYS = Set(["artifact_id", "path", "sha256", "role"])
const PROBE_BASE_KEYS =
    Set(["probe_id", "artifact_id", "field_path", "expected_type"])
const PROBE_VALUE_KEYS = Set(
    [
        "expected_string",
        "expected_strings",
        "expected_boolean",
        "expected_integer",
        "expected_number",
    ],
)
const ADMISSION_BLOCKER_MAPPING_KEYS =
    Set(["admission_blocker_id", "readiness_blocker_ids"])
const PRODUCTION_CELL_SCHEMA_FIELDS = [
    "cell_id",
    "canonical_source_key",
    "lineage_hash",
    "source_family_id",
    "source_artifact_sha256",
    "source_projection_sha256",
    "release_id",
    "retrieved_at_utc",
    "reference_period",
    "frequency",
    "time_basis",
    "stock_flow_class",
    "country",
    "currency",
    "unit",
    "price_basis",
    "valuation_basis",
    "row_namespace",
    "row_code",
    "column_namespace",
    "column_code",
    "raw_value",
    "cell_state",
    "economic_type",
    "negative_economic_type",
    "sign_domain",
    "counterpart_group_id",
    "structural_zero_evidence_id",
    "transformation_ids",
    "reliability_class_id",
    "covariance_group_id",
    "solver_role",
    "problem_scope_hash",
    "approval_id",
    "provenance",
]
const PRODUCTION_CONTROL_SCHEMA_FIELDS = [
    "control_id",
    "control_kind",
    "term_cell_ids",
    "coefficients",
    "rhs",
    "rhs_state",
    "country",
    "reference_period",
    "frequency",
    "time_basis",
    "stock_flow_class",
    "currency",
    "unit",
    "price_basis",
    "valuation_basis",
    "source_artifact_sha256s",
    "source_projection_sha256s",
    "release_id",
    "retrieved_at_utc",
    "canonical_control_key",
    "lineage_hash",
    "transformation_ids",
    "rounding_or_measurement_model",
    "independence_status",
    "fixed_status",
    "problem_scope_hash",
    "approval_id",
    "provenance",
]
const PRODUCTION_LEDGER_ARTIFACT_ID =
    "production_reconciliation_candidate_ledger"
const ADMISSION_CONTRACT_ARTIFACT_ID =
    "production_reconciliation_admission_evidence"
const ADMISSION_CRITERION_ID =
    "production_admission_evidence_authenticated"
const ADMISSION_CONTRACT_PATH =
    "scripts/us/accounting/production_reconciliation_admission_evidence.toml"
const ADMISSION_REQUIRED_PROBE_IDS = Set(
    [
        "admission_schema",
        "admission_classification",
        "admission_artifact_role",
        "admission_promotion_status",
        "admission_promotion_blockers",
        "admission_candidate_problem_scope_hash",
        "admission_candidate_problem_hash",
        "admission_candidate_ledger_contract_sha256",
        "admission_solver_admissible",
        "admission_solver_invocation_count",
        "admission_solver_input_cell_count",
        "admission_solver_input_control_count",
        "admission_approved_exact_control_count",
        "admission_approved_structural_zero_count",
        "admission_numerical_reliability_receipt_count",
        "admission_numerical_covariance_receipt_count",
        "admission_adjustment_record_count",
        "admission_forecast_origin_blocked",
        "admission_promotion_blocked",
        "admission_model_state_write_blocked",
        "admission_accounting_gate_effect",
        "admission_forecast_score_effect",
        "admission_candidate_cell_count",
        "admission_candidate_control_count",
        "admission_observation_loading_count",
        "admission_domestic_use_point_count",
        "admission_domestic_use_raw_evaluable_count",
        "admission_negative_cell_count",
        "admission_source_unresolved_negative_cell_count",
        "admission_source_mechanically_typed_negative_cell_count",
        "admission_literature_supported_negative_cell_count",
        "admission_component_unresolved_signed_cell_count",
        "admission_unresolved_negative_cell_count",
        "admission_dependence_group_count",
        "admission_revision_vintage_receipt_count",
        "admission_revision_panel_status",
        "admission_revision_fixture_absent",
        "admission_realized_revision_observation_count",
        "admission_producer_underlying_exactness",
        "admission_producer_structural_zero_status",
        "admission_producer_variance_status",
        "admission_rounding_source_certified",
        "admission_rounding_confidence_interval",
        "admission_rounding_variance_none",
        "admission_rounding_solver_weight_none",
        "admission_import_selected_semantics",
        "admission_module_normalized_sha256",
        "admission_runner_sha256",
    ],
)
const PRODUCTION_SCHEMA_PROBE_IDS = Set(
    [
        "ledger_schema",
        "ledger_classification",
        "ledger_artifact_role",
        "ledger_cell_schema",
        "ledger_control_schema",
        "ledger_candidate_cell_count",
        "ledger_candidate_control_count",
        "ledger_solver_input_cell_count",
        "ledger_solver_input_control_count",
    ],
)
const CANONICAL_LINEAGE_PROBE_IDS = Set(
    [
        "ledger_target_raw_source_leaf_count",
        "ledger_control_raw_source_leaf_count",
        "ledger_source_lineage_member_count",
        "ledger_candidate_cell_count",
        "ledger_overlay_count",
        "ledger_unique_overlay_owner_count",
        "ledger_lineage_relation_count",
    ],
)
const SOURCE_FAMILY_KEYS = Set(
    [
        "source_family_id",
        "artifact_ids",
        "source_namespace",
        "evidence_role",
        "country",
        "reference_period",
        "frequency",
        "time_basis",
        "stock_flow_class",
        "currency",
        "unit",
        "price_basis",
        "valuation_basis",
        "row_axis",
        "column_axis",
        "vintage_status",
        "release_identity",
        "cell_state_policy",
        "target_basis_compatible",
        "lineage_group",
        "admission_status",
        "solver_cell_count",
        "solver_control_count",
        "blocker_ids",
        "literature_ids",
    ],
)
const BLOCKER_KEYS = Set(
    [
        "blocker_id",
        "status",
        "required_for",
        "source_family_ids",
        "blocking_fact",
        "required_evidence",
        "resolution_test",
        "evidence_probe_ids",
        "literature_ids",
    ],
)
const CRITERION_KEYS = Set(
    [
        "criterion_id",
        "category",
        "mandatory",
        "status",
        "blocker_ids",
        "evidence_probe_ids",
        "finding",
        "completion_requirement",
    ],
)
const SOLVER_CANDIDATE_KEYS = Set(
    [
        "candidate_id",
        "method_id",
        "status",
        "required_criterion_ids",
        "blocker_ids",
        "admitted_solver_family_count",
        "solver_input_cell_count",
        "solver_input_control_count",
        "production_reliability_class_count",
        "production_covariance_class_count",
        "approved_exact_control_count",
        "approved_structural_zero_count",
        "solver_invoked",
        "reconciliation_run_count",
        "adjustment_record_count",
        "candidate_frozen",
        "adjustment_report_emitted",
        "forecast_origin_admissible",
        "promotion_ready",
        "model_state_write",
        "accounting_gate_effect",
        "forecast_score_effect",
    ],
)
const CITATION_KEYS = Set(
    [
        "citation_id",
        "kind",
        "authors",
        "year",
        "title",
        "locator",
        "url",
        "doi",
        "relevance",
    ],
)
const ZERO_EXPECTED_FIELDS = [
    "admitted_solver_family_count",
    "solver_input_cell_count",
    "solver_input_control_count",
    "production_reliability_class_count",
    "production_covariance_class_count",
    "approved_exact_control_count",
    "approved_structural_zero_count",
    "reconciliation_run_count",
    "adjustment_record_count",
]

abstract type AbstractProductionReadinessError <: Exception end

struct ReadinessContractError <: AbstractProductionReadinessError
    location::String
    detail::String
end

struct ArtifactIntegrityError <: AbstractProductionReadinessError
    artifact_id::String
    detail::String
end

struct EvidenceProbeError <: AbstractProductionReadinessError
    probe_id::String
    detail::String
end

struct ProductionReconciliationBlockedError <: AbstractProductionReadinessError
    blocker_ids::Vector{String}
end

function Base.showerror(io::IO, error::ReadinessContractError)
    return print(io, error.location, ": ", error.detail)
end

function Base.showerror(io::IO, error::ArtifactIntegrityError)
    return print(
        io,
        "artifact ",
        error.artifact_id,
        " failed integrity validation: ",
        error.detail,
    )
end

function Base.showerror(io::IO, error::EvidenceProbeError)
    return print(
        io,
        "evidence probe ",
        error.probe_id,
        " failed: ",
        error.detail,
    )
end

function Base.showerror(io::IO, error::ProductionReconciliationBlockedError)
    return print(
        io,
        "production reconciliation is blocked by: ",
        join(error.blocker_ids, ", "),
    )
end

struct ArtifactBinding
    artifact_id::String
    path::String
    sha256::String
    role::String
end

struct EvidenceProbe
    probe_id::String
    artifact_id::String
    field_path::Vector{String}
    expected_type::String
    expected_value::Any
end

struct AdmissionBlockerMapping
    admission_blocker_id::String
    readiness_blocker_ids::Vector{String}
end

struct SourceFamily
    source_family_id::String
    artifact_ids::Vector{String}
    source_namespace::String
    evidence_role::String
    country::String
    reference_period::String
    frequency::String
    time_basis::String
    stock_flow_class::String
    currency::String
    unit::String
    price_basis::String
    valuation_basis::String
    row_axis::String
    column_axis::String
    vintage_status::String
    release_identity::String
    cell_state_policy::String
    target_basis_compatible::Bool
    lineage_group::String
    admission_status::String
    solver_cell_count::Int
    solver_control_count::Int
    blocker_ids::Vector{String}
    literature_ids::Vector{String}
end

struct ReadinessBlocker
    blocker_id::String
    status::String
    required_for::String
    source_family_ids::Vector{String}
    blocking_fact::String
    required_evidence::String
    resolution_test::String
    evidence_probe_ids::Vector{String}
    literature_ids::Vector{String}
end

struct ReadinessCriterion
    criterion_id::String
    category::String
    mandatory::Bool
    status::String
    blocker_ids::Vector{String}
    evidence_probe_ids::Vector{String}
    finding::String
    completion_requirement::String
end

struct SolverCandidate
    candidate_id::String
    method_id::String
    status::String
    required_criterion_ids::Vector{String}
    blocker_ids::Vector{String}
    admitted_solver_family_count::Int
    solver_input_cell_count::Int
    solver_input_control_count::Int
    production_reliability_class_count::Int
    production_covariance_class_count::Int
    approved_exact_control_count::Int
    approved_structural_zero_count::Int
    solver_invoked::Bool
    reconciliation_run_count::Int
    adjustment_record_count::Int
    candidate_frozen::Bool
    adjustment_report_emitted::Bool
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_state_write::Bool
    accounting_gate_effect::String
    forecast_score_effect::String
end

struct LiteratureCitation
    citation_id::String
    kind::String
    authors::String
    year::Int
    title::String
    locator::String
    url::String
    doi::String
    relevance::String
end

struct ProductionReadinessContract
    schema_version::String
    contract_id::String
    classification::String
    promotion_status::String
    scientific_scope::String
    admission_evidence_hash::String
    target_country::String
    target_reference_period::String
    target_frequency::String
    target_time_basis::String
    target_stock_flow_class::String
    target_currency::String
    target_unit::String
    target_price_basis::String
    target_axis::String
    solver_method_id::String
    solver_invocation_status::String
    artifact_hash_policy::String
    missing_value_policy::String
    zero_policy::String
    sign_policy::String
    structural_zero_policy::String
    exact_control_policy::String
    reliability_policy::String
    covariance_policy::String
    control_dependency_policy::String
    lineage_policy::String
    production_cell_schema_fields::Vector{String}
    production_control_schema_fields::Vector{String}
    allowed_control_kinds::Vector{String}
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_state_write::Bool
    accounting_gate_effect::String
    forecast_score_effect::String
    module_path::String
    module_hash_policy::String
    module_normalized_sha256::String
    runner_path::String
    runner_sha256::String
    expected::Dict{String, Int}
    artifacts::Vector{ArtifactBinding}
    probes::Vector{EvidenceProbe}
    admission_blocker_mappings::Vector{AdmissionBlockerMapping}
    source_families::Vector{SourceFamily}
    blockers::Vector{ReadinessBlocker}
    criteria::Vector{ReadinessCriterion}
    solver_candidates::Vector{SolverCandidate}
    citations::Vector{LiteratureCitation}
    source_sha256::String
end

struct ArtifactValidation
    artifact_id::String
    path::String
    role::String
    expected_sha256::String
    before_sha256::String
    after_sha256::String
    status::String
end

struct EvidenceProbeResult
    probe_id::String
    artifact_id::String
    field_path::Vector{String}
    expected_type::String
    expected_value::Any
    observed_value::Any
    status::String
end

struct ProductionReadinessResult
    contract_sha256::String
    admission_evidence_hash::String
    overall_status::String
    ready::Bool
    artifact_validations::Vector{ArtifactValidation}
    probe_results::Vector{EvidenceProbeResult}
    source_families::Vector{SourceFamily}
    blockers::Vector{ReadinessBlocker}
    criteria::Vector{ReadinessCriterion}
    candidate::SolverCandidate
    blocking_criterion_ids::Vector{String}
    blocker_ids::Vector{String}
end

file_sha256(path::AbstractString) =
    open(path, "r") do io
    return bytes2hex(sha256(io))
end

function normalized_module_sha256(path::AbstractString)
    source = read(path, String)
    count = length(findall(APPROVED_CONTRACT_SHA256, source))
    count == 1 ||
        throw(
        ReadinessContractError(
            "implementation.module_path",
            "approved contract hash literal must occur exactly once, found $count",
        ),
    )
    normalized = replace(
        source,
        APPROVED_CONTRACT_SHA256 => ZERO_SHA256;
        count = 1,
    )
    return bytes2hex(sha256(codeunits(normalized)))
end

function require_keys(
        table::AbstractDict,
        expected::Set{String},
        location::String,
    )
    observed = Set(String(key) for key in keys(table))
    observed == expected ||
        throw(
        ReadinessContractError(
            location,
            "expected keys $(sort!(collect(expected))), got $(sort!(collect(observed)))",
        ),
    )
    return nothing
end

function require_string(
        table::AbstractDict,
        key::String,
        location::String,
    )
    value = table[key]
    value isa String ||
        throw(ReadinessContractError("$location.$key", "must be a string"))
    isempty(value) &&
        throw(ReadinessContractError("$location.$key", "must not be empty"))
    return value
end

function optional_empty_string(
        table::AbstractDict,
        key::String,
        location::String,
    )
    value = table[key]
    value isa String ||
        throw(ReadinessContractError("$location.$key", "must be a string"))
    return value
end

function require_bool(
        table::AbstractDict,
        key::String,
        location::String,
    )
    value = table[key]
    value isa Bool ||
        throw(ReadinessContractError("$location.$key", "must be Boolean"))
    return value
end

function require_int(
        table::AbstractDict,
        key::String,
        location::String,
    )
    value = table[key]
    value isa Integer && !(value isa Bool) ||
        throw(ReadinessContractError("$location.$key", "must be an integer"))
    value >= 0 ||
        throw(ReadinessContractError("$location.$key", "must be nonnegative"))
    return Int(value)
end

function require_string_vector(
        table::AbstractDict,
        key::String,
        location::String;
        allow_empty::Bool = false,
    )
    value = table[key]
    value isa AbstractVector ||
        throw(ReadinessContractError("$location.$key", "must be an array"))
    all(item -> item isa String && !isempty(item), value) ||
        throw(
        ReadinessContractError(
            "$location.$key",
            "must contain only nonempty strings",
        ),
    )
    !allow_empty && isempty(value) &&
        throw(ReadinessContractError("$location.$key", "must not be empty"))
    result = String[item for item in value]
    length(result) == length(unique(result)) ||
        throw(ReadinessContractError("$location.$key", "contains duplicates"))
    return result
end

function is_sha256(value::String)
    return length(value) == 64 &&
        all(character -> character in '0':'9' || character in 'a':'f', value)
end

function validate_relative_path(path::String, location::String)
    isabspath(path) &&
        throw(ReadinessContractError(location, "must be repository relative"))
    components = splitpath(path)
    any(component -> component == ".." || isempty(component), components) &&
        throw(
        ReadinessContractError(
            location,
            "must not contain parent traversal or empty components",
        ),
    )
    normpath(path) == path ||
        throw(ReadinessContractError(location, "must be normalized"))
    return nothing
end

function parse_artifact(table, index)
    location = "artifact[$index]"
    require_keys(table, ARTIFACT_KEYS, location)
    return ArtifactBinding(
        require_string(table, "artifact_id", location),
        require_string(table, "path", location),
        require_string(table, "sha256", location),
        require_string(table, "role", location),
    )
end

function parse_probe(table, index)
    location = "probe[$index]"
    observed = Set(String(key) for key in keys(table))
    base_present = intersect(observed, PROBE_BASE_KEYS)
    base_present == PROBE_BASE_KEYS ||
        throw(
        ReadinessContractError(
            location,
            "missing or invalid base keys",
        ),
    )
    expected_type = require_string(table, "expected_type", location)
    value_key = if expected_type == "STRING"
        "expected_string"
    elseif expected_type == "STRING_ARRAY"
        "expected_strings"
    elseif expected_type == "BOOLEAN"
        "expected_boolean"
    elseif expected_type == "INTEGER"
        "expected_integer"
    elseif expected_type == "NUMBER"
        "expected_number"
    else
        throw(
            ReadinessContractError(
                "$location.expected_type",
                "unsupported type $expected_type",
            ),
        )
    end
    observed == union(PROBE_BASE_KEYS, Set([value_key])) ||
        throw(
        ReadinessContractError(
            location,
            "must contain exactly one expected-value key for $expected_type",
        ),
    )
    expected_value = table[value_key]
    if expected_type == "STRING"
        expected_value isa String ||
            throw(
            ReadinessContractError(
                "$location.$value_key",
                "must be a string",
            ),
        )
    elseif expected_type == "STRING_ARRAY"
        expected_value isa AbstractVector &&
            all(item -> item isa String && !isempty(item), expected_value) ||
            throw(
            ReadinessContractError(
                "$location.$value_key",
                "must be an array of nonempty strings",
            ),
        )
        expected_value = String.(expected_value)
        length(expected_value) == length(unique(expected_value)) ||
            throw(
            ReadinessContractError(
                "$location.$value_key",
                "must not contain duplicates",
            ),
        )
    elseif expected_type == "BOOLEAN"
        expected_value isa Bool ||
            throw(
            ReadinessContractError(
                "$location.$value_key",
                "must be Boolean",
            ),
        )
    elseif expected_type == "INTEGER"
        expected_value isa Integer && !(expected_value isa Bool) ||
            throw(
            ReadinessContractError(
                "$location.$value_key",
                "must be an integer",
            ),
        )
        expected_value = Int(expected_value)
    else
        expected_value isa Real && !(expected_value isa Bool) ||
            throw(
            ReadinessContractError(
                "$location.$value_key",
                "must be numeric",
            ),
        )
        expected_value = Float64(expected_value)
    end
    return EvidenceProbe(
        require_string(table, "probe_id", location),
        require_string(table, "artifact_id", location),
        require_string_vector(table, "field_path", location),
        expected_type,
        expected_value,
    )
end

function parse_admission_blocker_mapping(table, index)
    location = "admission_blocker_mapping[$index]"
    require_keys(table, ADMISSION_BLOCKER_MAPPING_KEYS, location)
    return AdmissionBlockerMapping(
        require_string(table, "admission_blocker_id", location),
        require_string_vector(table, "readiness_blocker_ids", location),
    )
end

function parse_source_family(table, index)
    location = "source_family[$index]"
    require_keys(table, SOURCE_FAMILY_KEYS, location)
    return SourceFamily(
        require_string(table, "source_family_id", location),
        require_string_vector(table, "artifact_ids", location),
        require_string(table, "source_namespace", location),
        require_string(table, "evidence_role", location),
        require_string(table, "country", location),
        require_string(table, "reference_period", location),
        require_string(table, "frequency", location),
        require_string(table, "time_basis", location),
        require_string(table, "stock_flow_class", location),
        require_string(table, "currency", location),
        require_string(table, "unit", location),
        require_string(table, "price_basis", location),
        require_string(table, "valuation_basis", location),
        require_string(table, "row_axis", location),
        require_string(table, "column_axis", location),
        require_string(table, "vintage_status", location),
        require_string(table, "release_identity", location),
        require_string(table, "cell_state_policy", location),
        require_bool(table, "target_basis_compatible", location),
        require_string(table, "lineage_group", location),
        require_string(table, "admission_status", location),
        require_int(table, "solver_cell_count", location),
        require_int(table, "solver_control_count", location),
        require_string_vector(
            table,
            "blocker_ids",
            location;
            allow_empty = true,
        ),
        require_string_vector(
            table,
            "literature_ids",
            location;
            allow_empty = true,
        ),
    )
end

function parse_blocker(table, index)
    location = "blocker[$index]"
    require_keys(table, BLOCKER_KEYS, location)
    return ReadinessBlocker(
        require_string(table, "blocker_id", location),
        require_string(table, "status", location),
        require_string(table, "required_for", location),
        require_string_vector(
            table,
            "source_family_ids",
            location;
            allow_empty = true,
        ),
        require_string(table, "blocking_fact", location),
        require_string(table, "required_evidence", location),
        require_string(table, "resolution_test", location),
        require_string_vector(
            table,
            "evidence_probe_ids",
            location;
            allow_empty = true,
        ),
        require_string_vector(
            table,
            "literature_ids",
            location;
            allow_empty = true,
        ),
    )
end

function parse_criterion(table, index)
    location = "criterion[$index]"
    require_keys(table, CRITERION_KEYS, location)
    return ReadinessCriterion(
        require_string(table, "criterion_id", location),
        require_string(table, "category", location),
        require_bool(table, "mandatory", location),
        require_string(table, "status", location),
        require_string_vector(
            table,
            "blocker_ids",
            location;
            allow_empty = true,
        ),
        require_string_vector(
            table,
            "evidence_probe_ids",
            location;
            allow_empty = true,
        ),
        require_string(table, "finding", location),
        require_string(table, "completion_requirement", location),
    )
end

function parse_solver_candidate(table, index)
    location = "solver_candidate[$index]"
    require_keys(table, SOLVER_CANDIDATE_KEYS, location)
    return SolverCandidate(
        require_string(table, "candidate_id", location),
        require_string(table, "method_id", location),
        require_string(table, "status", location),
        require_string_vector(table, "required_criterion_ids", location),
        require_string_vector(table, "blocker_ids", location),
        require_int(table, "admitted_solver_family_count", location),
        require_int(table, "solver_input_cell_count", location),
        require_int(table, "solver_input_control_count", location),
        require_int(
            table,
            "production_reliability_class_count",
            location,
        ),
        require_int(
            table,
            "production_covariance_class_count",
            location,
        ),
        require_int(table, "approved_exact_control_count", location),
        require_int(table, "approved_structural_zero_count", location),
        require_bool(table, "solver_invoked", location),
        require_int(table, "reconciliation_run_count", location),
        require_int(table, "adjustment_record_count", location),
        require_bool(table, "candidate_frozen", location),
        require_bool(table, "adjustment_report_emitted", location),
        require_bool(table, "forecast_origin_admissible", location),
        require_bool(table, "promotion_ready", location),
        require_bool(table, "model_state_write", location),
        require_string(table, "accounting_gate_effect", location),
        require_string(table, "forecast_score_effect", location),
    )
end

function parse_citation(table, index)
    location = "citation[$index]"
    require_keys(table, CITATION_KEYS, location)
    return LiteratureCitation(
        require_string(table, "citation_id", location),
        require_string(table, "kind", location),
        require_string(table, "authors", location),
        require_int(table, "year", location),
        require_string(table, "title", location),
        require_string(table, "locator", location),
        require_string(table, "url", location),
        optional_empty_string(table, "doi", location),
        require_string(table, "relevance", location),
    )
end

function load_production_readiness_contract(
        path::AbstractString = DEFAULT_CONTRACT_PATH;
        verify_hash::Bool = true,
    )
    source_sha256 = file_sha256(path)
    verify_hash && source_sha256 != APPROVED_CONTRACT_SHA256 &&
        throw(
        ReadinessContractError(
            "contract.sha256",
            "expected $APPROVED_CONTRACT_SHA256, got $source_sha256",
        ),
    )
    document = TOML.parsefile(path)
    require_keys(document, CONTRACT_KEYS, "contract")
    implementation = document["implementation"]
    implementation isa AbstractDict ||
        throw(
        ReadinessContractError(
            "contract.implementation",
            "must be a table",
        ),
    )
    require_keys(implementation, IMPLEMENTATION_KEYS, "implementation")
    expected_table = document["expected"]
    expected_table isa AbstractDict ||
        throw(ReadinessContractError("contract.expected", "must be a table"))
    require_keys(expected_table, EXPECTED_KEYS, "expected")
    expected = Dict{String, Int}(
        key => require_int(expected_table, key, "expected")
            for key in sort!(collect(EXPECTED_KEYS))
    )
    artifacts = ArtifactBinding[
        parse_artifact(table, index)
            for (index, table) in enumerate(document["artifact"])
    ]
    probes = EvidenceProbe[
        parse_probe(table, index)
            for (index, table) in enumerate(document["probe"])
    ]
    admission_blocker_mappings = AdmissionBlockerMapping[
        parse_admission_blocker_mapping(table, index)
            for (index, table) in
            enumerate(document["admission_blocker_mapping"])
    ]
    source_families = SourceFamily[
        parse_source_family(table, index)
            for (index, table) in enumerate(document["source_family"])
    ]
    blockers = ReadinessBlocker[
        parse_blocker(table, index)
            for (index, table) in enumerate(document["blocker"])
    ]
    criteria = ReadinessCriterion[
        parse_criterion(table, index)
            for (index, table) in enumerate(document["criterion"])
    ]
    candidates = SolverCandidate[
        parse_solver_candidate(table, index)
            for (index, table) in enumerate(document["solver_candidate"])
    ]
    citations = LiteratureCitation[
        parse_citation(table, index)
            for (index, table) in enumerate(document["citation"])
    ]
    contract = ProductionReadinessContract(
        require_string(document, "schema_version", "contract"),
        require_string(document, "contract_id", "contract"),
        require_string(document, "classification", "contract"),
        require_string(document, "promotion_status", "contract"),
        require_string(document, "scientific_scope", "contract"),
        require_string(document, "admission_evidence_hash", "contract"),
        require_string(document, "target_country", "contract"),
        require_string(document, "target_reference_period", "contract"),
        require_string(document, "target_frequency", "contract"),
        require_string(document, "target_time_basis", "contract"),
        require_string(document, "target_stock_flow_class", "contract"),
        require_string(document, "target_currency", "contract"),
        require_string(document, "target_unit", "contract"),
        require_string(document, "target_price_basis", "contract"),
        require_string(document, "target_axis", "contract"),
        require_string(document, "solver_method_id", "contract"),
        require_string(document, "solver_invocation_status", "contract"),
        require_string(document, "artifact_hash_policy", "contract"),
        require_string(document, "missing_value_policy", "contract"),
        require_string(document, "zero_policy", "contract"),
        require_string(document, "sign_policy", "contract"),
        require_string(document, "structural_zero_policy", "contract"),
        require_string(document, "exact_control_policy", "contract"),
        require_string(document, "reliability_policy", "contract"),
        require_string(document, "covariance_policy", "contract"),
        require_string(document, "control_dependency_policy", "contract"),
        require_string(document, "lineage_policy", "contract"),
        require_string_vector(
            document,
            "production_cell_schema_fields",
            "contract",
        ),
        require_string_vector(
            document,
            "production_control_schema_fields",
            "contract",
        ),
        require_string_vector(document, "allowed_control_kinds", "contract"),
        require_bool(document, "forecast_origin_admissible", "contract"),
        require_bool(document, "promotion_ready", "contract"),
        require_bool(document, "model_state_write", "contract"),
        require_string(document, "accounting_gate_effect", "contract"),
        require_string(document, "forecast_score_effect", "contract"),
        require_string(implementation, "module_path", "implementation"),
        require_string(
            implementation,
            "module_hash_policy",
            "implementation",
        ),
        require_string(
            implementation,
            "module_normalized_sha256",
            "implementation",
        ),
        require_string(implementation, "runner_path", "implementation"),
        require_string(implementation, "runner_sha256", "implementation"),
        expected,
        artifacts,
        probes,
        admission_blocker_mappings,
        source_families,
        blockers,
        criteria,
        candidates,
        citations,
        source_sha256,
    )
    validate_production_readiness_contract(contract)
    return contract
end

function assert_unique(ids::Vector{String}, location::String)
    length(ids) == length(unique(ids)) ||
        throw(ReadinessContractError(location, "contains duplicate IDs"))
    return Set(ids)
end

function validate_production_readiness_contract(
        contract::ProductionReadinessContract,
    )
    contract.schema_version == CONTRACT_SCHEMA ||
        throw(
        ReadinessContractError(
            "contract.schema_version",
            "expected $CONTRACT_SCHEMA",
        ),
    )
    contract.contract_id == "us-ws2c-production-reconciliation-readiness-v2" ||
        throw(
        ReadinessContractError(
            "contract.contract_id",
            "must identify the admission-overlay-integrated v2 contract",
        ),
    )
    occursin(r"^admission1:[0-9a-f]{64}$", contract.admission_evidence_hash) ||
        throw(
        ReadinessContractError(
            "contract.admission_evidence_hash",
            "must be a lowercase admission1 content identity",
        ),
    )
    contract.classification ==
        "CURRENT_VINTAGE_FAIL_CLOSED_READINESS_GATE_NOT_ORIGIN_ELIGIBLE" ||
        throw(
        ReadinessContractError(
            "contract.classification",
            "must remain fail-closed and not origin eligible",
        ),
    )
    contract.promotion_status == "NOT_READY_NOT_PROMOTED" ||
        throw(
        ReadinessContractError(
            "contract.promotion_status",
            "must remain not ready",
        ),
    )
    contract.target_country == "USA" ||
        throw(ReadinessContractError("contract.target_country", "changed"))
    contract.target_reference_period == "CALENDAR_YEAR_2024" ||
        throw(
        ReadinessContractError(
            "contract.target_reference_period",
            "changed",
        ),
    )
    contract.target_frequency == "ANNUAL" ||
        throw(ReadinessContractError("contract.target_frequency", "changed"))
    contract.target_time_basis == "CALENDAR_YEAR_ACCOUNTING_FLOW" ||
        throw(ReadinessContractError("contract.target_time_basis", "changed"))
    contract.target_stock_flow_class == "FLOW" ||
        throw(
        ReadinessContractError(
            "contract.target_stock_flow_class",
            "changed",
        ),
    )
    contract.target_currency == "USD" ||
        throw(ReadinessContractError("contract.target_currency", "changed"))
    contract.target_unit == "MILLIONS_CURRENT_DOLLARS" ||
        throw(ReadinessContractError("contract.target_unit", "changed"))
    contract.target_price_basis == "PRODUCERS_PRICES" ||
        throw(
        ReadinessContractError(
            "contract.target_price_basis",
            "changed",
        ),
    )
    contract.target_axis ==
        "BEA_AFTER_REDEFINITIONS_68_CORE_PLUS_EXPLICIT_USED_OTHER_CLOSURE" ||
        throw(ReadinessContractError("contract.target_axis", "changed"))
    contract.solver_method_id == "CONSTRAINED_STONE_GLS" ||
        throw(
        ReadinessContractError(
            "contract.solver_method_id",
            "unsupported method",
        ),
    )
    contract.solver_invocation_status == "NOT_RUN_BLOCKED" ||
        throw(
        ReadinessContractError(
            "contract.solver_invocation_status",
            "must remain blocked",
        ),
    )
    contract.forecast_origin_admissible &&
        throw(
        ReadinessContractError(
            "contract.forecast_origin_admissible",
            "must be false",
        ),
    )
    contract.promotion_ready &&
        throw(
        ReadinessContractError(
            "contract.promotion_ready",
            "must be false",
        ),
    )
    contract.model_state_write &&
        throw(
        ReadinessContractError(
            "contract.model_state_write",
            "must be false",
        ),
    )
    contract.accounting_gate_effect == "NONE" ||
        throw(
        ReadinessContractError(
            "contract.accounting_gate_effect",
            "must be NONE",
        ),
    )
    contract.forecast_score_effect == "NONE" ||
        throw(
        ReadinessContractError(
            "contract.forecast_score_effect",
            "must be NONE",
        ),
    )
    "truth_value" in contract.production_cell_schema_fields &&
        throw(
        ReadinessContractError(
            "contract.production_cell_schema_fields",
            "production schema must not contain truth_value",
        ),
    )
    "benchmark_role" in contract.production_cell_schema_fields &&
        throw(
        ReadinessContractError(
            "contract.production_cell_schema_fields",
            "production schema must not contain benchmark_role",
        ),
    )
    contract.production_cell_schema_fields ==
        PRODUCTION_CELL_SCHEMA_FIELDS ||
        throw(
        ReadinessContractError(
            "contract.production_cell_schema_fields",
            "must exactly match the authenticated 35-field production ledger schema",
        ),
    )
    contract.production_control_schema_fields ==
        PRODUCTION_CONTROL_SCHEMA_FIELDS ||
        throw(
        ReadinessContractError(
            "contract.production_control_schema_fields",
            "must exactly match the authenticated 28-field production ledger schema",
        ),
    )
    Set(contract.allowed_control_kinds) ==
        Set(
        [
            "EXACT_ACCOUNTING_IDENTITY",
            "MEASURED_PUBLISHED_MARGIN",
            "FIXED_PUBLISHED_CONTROL_APPROVED",
        ],
    ) ||
        throw(
        ReadinessContractError(
            "contract.allowed_control_kinds",
            "changed",
        ),
    )

    is_sha256(contract.module_normalized_sha256) ||
        throw(
        ReadinessContractError(
            "implementation.module_normalized_sha256",
            "must be lowercase SHA-256",
        ),
    )
    is_sha256(contract.runner_sha256) ||
        throw(
        ReadinessContractError(
            "implementation.runner_sha256",
            "must be lowercase SHA-256",
        ),
    )
    validate_relative_path(contract.module_path, "implementation.module_path")
    validate_relative_path(contract.runner_path, "implementation.runner_path")
    contract.module_hash_policy ==
        "SHA256_AFTER_REPLACING_SINGLE_APPROVED_CONTRACT_HASH_LITERAL_WITH_64_ZEROES" ||
        throw(
        ReadinessContractError(
            "implementation.module_hash_policy",
            "unsupported policy",
        ),
    )

    artifact_ids = assert_unique(
        String[artifact.artifact_id for artifact in contract.artifacts],
        "artifact",
    )
    for artifact in contract.artifacts
        validate_relative_path(
            artifact.path,
            "artifact.$(artifact.artifact_id).path",
        )
        is_sha256(artifact.sha256) ||
            throw(
            ReadinessContractError(
                "artifact.$(artifact.artifact_id).sha256",
                "must be lowercase SHA-256",
            ),
        )
    end
    artifact_paths = String[artifact.path for artifact in contract.artifacts]
    length(artifact_paths) == length(unique(artifact_paths)) ||
        throw(
        ReadinessContractError(
            "artifact.path",
            "each authenticated path must have exactly one binding",
        ),
    )
    probe_ids = assert_unique(
        String[probe.probe_id for probe in contract.probes],
        "probe",
    )
    for probe in contract.probes
        probe.artifact_id in artifact_ids ||
            throw(
            ReadinessContractError(
                "probe.$(probe.probe_id).artifact_id",
                "unknown artifact",
            ),
        )
    end
    citation_ids = assert_unique(
        String[citation.citation_id for citation in contract.citations],
        "citation",
    )
    source_ids = assert_unique(
        String[
            source.source_family_id
                for source in contract.source_families
        ],
        "source_family",
    )
    blocker_ids = assert_unique(
        String[blocker.blocker_id for blocker in contract.blockers],
        "blocker",
    )
    admission_blocker_ids = assert_unique(
        String[
            mapping.admission_blocker_id
                for mapping in contract.admission_blocker_mappings
        ],
        "admission_blocker_mapping",
    )
    length(admission_blocker_ids) == 13 ||
        throw(
        ReadinessContractError(
            "admission_blocker_mapping",
            "must map all 13 admission promotion blockers exactly once",
        ),
    )
    for mapping in contract.admission_blocker_mappings
        isempty(mapping.readiness_blocker_ids) &&
            throw(
            ReadinessContractError(
                "admission_blocker_mapping.$(mapping.admission_blocker_id)",
                "must map to at least one readiness blocker",
            ),
        )
        issubset(Set(mapping.readiness_blocker_ids), blocker_ids) ||
            throw(
            ReadinessContractError(
                "admission_blocker_mapping.$(mapping.admission_blocker_id)",
                "contains an unknown readiness blocker",
            ),
        )
    end
    criterion_ids = assert_unique(
        String[
            criterion.criterion_id
                for criterion in contract.criteria
        ],
        "criterion",
    )
    candidate_ids = assert_unique(
        String[
            candidate.candidate_id
                for candidate in contract.solver_candidates
        ],
        "solver_candidate",
    )
    isempty(candidate_ids) &&
        throw(
        ReadinessContractError(
            "solver_candidate",
            "at least one candidate is required",
        ),
    )
    PRODUCTION_LEDGER_ARTIFACT_ID in artifact_ids ||
        throw(
        ReadinessContractError(
            "artifact",
            "missing authenticated production reconciliation candidate ledger",
        ),
    )
    ledger_artifact = only(
        artifact
            for artifact in contract.artifacts
            if artifact.artifact_id == PRODUCTION_LEDGER_ARTIFACT_ID
    )
    ledger_artifact.path ==
        "scripts/us/accounting/production_reconciliation_candidate_ledger.toml" ||
        throw(
        ReadinessContractError(
            "artifact.$PRODUCTION_LEDGER_ARTIFACT_ID.path",
            "changed",
        ),
    )
    ledger_artifact.role ==
        "AUTHENTICATED_PRODUCTION_SCHEMA_LINEAGE_AND_QUARANTINE_GATE" ||
        throw(
        ReadinessContractError(
            "artifact.$PRODUCTION_LEDGER_ARTIFACT_ID.role",
            "changed",
        ),
    )
    required_ledger_probe_ids =
        union(PRODUCTION_SCHEMA_PROBE_IDS, CANONICAL_LINEAGE_PROBE_IDS)
    issubset(required_ledger_probe_ids, probe_ids) ||
        throw(
        ReadinessContractError(
            "probe",
            "missing required production-ledger semantic probes",
        ),
    )
    probe_by_id = Dict(probe.probe_id => probe for probe in contract.probes)
    all(
        probe_by_id[probe_id].artifact_id == PRODUCTION_LEDGER_ARTIFACT_ID
            for probe_id in required_ledger_probe_ids
    ) ||
        throw(
        ReadinessContractError(
            "probe",
            "production-ledger readiness probes must bind the pinned ledger artifact",
        ),
    )
    artifact_by_id =
        Dict(artifact.artifact_id => artifact for artifact in contract.artifacts)
    haskey(artifact_by_id, ADMISSION_CONTRACT_ARTIFACT_ID) ||
        throw(
        ReadinessContractError(
            "artifact",
            "missing $ADMISSION_CONTRACT_ARTIFACT_ID",
        ),
    )
    admission_artifact = artifact_by_id[ADMISSION_CONTRACT_ARTIFACT_ID]
    admission_artifact.path == ADMISSION_CONTRACT_PATH ||
        throw(
        ReadinessContractError(
            "artifact.$ADMISSION_CONTRACT_ARTIFACT_ID.path",
            "changed",
        ),
    )
    admission_artifact.role == "AUTHENTICATED_ADMISSION_OVERLAY_CONTRACT" ||
        throw(
        ReadinessContractError(
            "artifact.$ADMISSION_CONTRACT_ARTIFACT_ID.role",
            "changed",
        ),
    )
    issubset(ADMISSION_REQUIRED_PROBE_IDS, probe_ids) ||
        throw(
        ReadinessContractError(
            "probe",
            "missing required admission-overlay semantic probes",
        ),
    )
    all(
        probe_by_id[probe_id].artifact_id ==
            ADMISSION_CONTRACT_ARTIFACT_ID
            for probe_id in ADMISSION_REQUIRED_PROBE_IDS
    ) ||
        throw(
        ReadinessContractError(
            "probe",
            "admission-overlay probes must bind the authenticated admission contract",
        ),
    )
    "PRODUCTION_SOLVER_ADMISSION_NOT_APPROVED" in blocker_ids ||
        throw(
        ReadinessContractError(
            "blocker",
            "missing fail-closed production solver-admission blocker",
        ),
    )
    isempty(
        intersect(
            blocker_ids,
            Set(
                [
                    "PRODUCTION_STONE_PROBLEM_SCHEMA_NOT_IMPLEMENTED",
                    "CANONICAL_SOURCE_LINEAGE_DEDUPLICATION_NOT_IMPLEMENTED",
                ],
            ),
        ),
    ) ||
        throw(
        ReadinessContractError(
            "blocker",
            "retired implementation blockers must not remain open",
        ),
    )
    criterion_by_id =
        Dict(criterion.criterion_id => criterion for criterion in contract.criteria)
    haskey(criterion_by_id, ADMISSION_CRITERION_ID) ||
        throw(
        ReadinessContractError(
            "criterion",
            "missing $ADMISSION_CRITERION_ID",
        ),
    )
    admission_criterion = criterion_by_id[ADMISSION_CRITERION_ID]
    admission_criterion.status == "PASS" &&
        isempty(admission_criterion.blocker_ids) ||
        throw(
        ReadinessContractError(
            "criterion.$ADMISSION_CRITERION_ID",
            "must pass without claiming solver admission",
        ),
    )
    issubset(
        ADMISSION_REQUIRED_PROBE_IDS,
        Set(admission_criterion.evidence_probe_ids),
    ) ||
        throw(
        ReadinessContractError(
            "criterion.$ADMISSION_CRITERION_ID.evidence_probe_ids",
            "must bind every required admission-overlay probe",
        ),
    )
    for (
            criterion_id,
            required_probes,
        ) in (
            (
                "production_problem_schema_ready",
                PRODUCTION_SCHEMA_PROBE_IDS,
            ),
            (
                "canonical_lineage_deduplicated",
                CANONICAL_LINEAGE_PROBE_IDS,
            ),
        )
        haskey(criterion_by_id, criterion_id) ||
            throw(
            ReadinessContractError(
                "criterion",
                "missing $criterion_id",
            ),
        )
        criterion = criterion_by_id[criterion_id]
        criterion.status == "PASS" && isempty(criterion.blocker_ids) ||
            throw(
            ReadinessContractError(
                "criterion.$criterion_id",
                "must pass without blockers",
            ),
        )
        issubset(required_probes, Set(criterion.evidence_probe_ids)) ||
            throw(
            ReadinessContractError(
                "criterion.$criterion_id.evidence_probe_ids",
                "does not bind every required production-ledger probe",
            ),
        )
    end

    for source in contract.source_families
        issubset(Set(source.artifact_ids), artifact_ids) ||
            throw(
            ReadinessContractError(
                "source_family.$(source.source_family_id).artifact_ids",
                "contains an unknown artifact",
            ),
        )
        issubset(Set(source.blocker_ids), blocker_ids) ||
            throw(
            ReadinessContractError(
                "source_family.$(source.source_family_id).blocker_ids",
                "contains an unknown blocker",
            ),
        )
        issubset(Set(source.literature_ids), citation_ids) ||
            throw(
            ReadinessContractError(
                "source_family.$(source.source_family_id).literature_ids",
                "contains an unknown citation",
            ),
        )
        source.solver_cell_count == 0 ||
            throw(
            ReadinessContractError(
                "source_family.$(source.source_family_id).solver_cell_count",
                "must be zero while blocked",
            ),
        )
        source.solver_control_count == 0 ||
            throw(
            ReadinessContractError(
                "source_family.$(source.source_family_id).solver_control_count",
                "must be zero while blocked",
            ),
        )
        occursin("ADMITTED", source.admission_status) &&
            !occursin("NOT_SOLVER_ADMITTED", source.admission_status) &&
            throw(
            ReadinessContractError(
                "source_family.$(source.source_family_id).admission_status",
                "must not claim admission",
            ),
        )
    end
    for blocker in contract.blockers
        blocker.status == "OPEN" ||
            throw(
            ReadinessContractError(
                "blocker.$(blocker.blocker_id).status",
                "must be OPEN",
            ),
        )
        blocker.required_for == "PRODUCTION_RECONCILIATION" ||
            throw(
            ReadinessContractError(
                "blocker.$(blocker.blocker_id).required_for",
                "changed",
            ),
        )
        issubset(Set(blocker.source_family_ids), source_ids) ||
            throw(
            ReadinessContractError(
                "blocker.$(blocker.blocker_id).source_family_ids",
                "contains an unknown source family",
            ),
        )
        issubset(Set(blocker.evidence_probe_ids), probe_ids) ||
            throw(
            ReadinessContractError(
                "blocker.$(blocker.blocker_id).evidence_probe_ids",
                "contains an unknown probe",
            ),
        )
        issubset(Set(blocker.literature_ids), citation_ids) ||
            throw(
            ReadinessContractError(
                "blocker.$(blocker.blocker_id).literature_ids",
                "contains an unknown citation",
            ),
        )
    end
    source_by_id = Dict(
        source.source_family_id => source
            for source in contract.source_families
    )
    blocker_by_id =
        Dict(blocker.blocker_id => blocker for blocker in contract.blockers)
    for source in contract.source_families
        for blocker_id in source.blocker_ids
            source.source_family_id in
                blocker_by_id[blocker_id].source_family_ids ||
                throw(
                ReadinessContractError(
                    "source_family.$(source.source_family_id).blocker_ids",
                    "$blocker_id is not reciprocally linked by the blocker",
                ),
            )
        end
    end
    for blocker in contract.blockers
        for source_family_id in blocker.source_family_ids
            blocker.blocker_id in
                source_by_id[source_family_id].blocker_ids ||
                throw(
                ReadinessContractError(
                    "blocker.$(blocker.blocker_id).source_family_ids",
                    "$source_family_id is not reciprocally linked by the source family",
                ),
            )
        end
    end
    used_blockers = Set{String}()
    for criterion in contract.criteria
        criterion.mandatory ||
            throw(
            ReadinessContractError(
                "criterion.$(criterion.criterion_id).mandatory",
                "all v2 criteria must be mandatory",
            ),
        )
        criterion.status in ("PASS", "BLOCKED") ||
            throw(
            ReadinessContractError(
                "criterion.$(criterion.criterion_id).status",
                "must be PASS or BLOCKED",
            ),
        )
        if criterion.status == "PASS"
            isempty(criterion.blocker_ids) ||
                throw(
                ReadinessContractError(
                    "criterion.$(criterion.criterion_id).blocker_ids",
                    "passing criterion cannot retain blockers",
                ),
            )
        else
            isempty(criterion.blocker_ids) &&
                throw(
                ReadinessContractError(
                    "criterion.$(criterion.criterion_id).blocker_ids",
                    "blocked criterion must name blockers",
                ),
            )
        end
        issubset(Set(criterion.blocker_ids), blocker_ids) ||
            throw(
            ReadinessContractError(
                "criterion.$(criterion.criterion_id).blocker_ids",
                "contains an unknown blocker",
            ),
        )
        union!(used_blockers, criterion.blocker_ids)
        issubset(Set(criterion.evidence_probe_ids), probe_ids) ||
            throw(
            ReadinessContractError(
                "criterion.$(criterion.criterion_id).evidence_probe_ids",
                "contains an unknown probe",
            ),
        )
    end
    used_blockers == blocker_ids ||
        throw(
        ReadinessContractError(
            "criterion.blocker_ids",
            "every open blocker must be assigned to a readiness criterion",
        ),
    )

    length(contract.solver_candidates) == 1 ||
        throw(
        ReadinessContractError(
            "solver_candidate",
            "v2 requires exactly one candidate",
        ),
    )
    candidate = only(contract.solver_candidates)
    candidate.method_id == contract.solver_method_id ||
        throw(
        ReadinessContractError(
            "solver_candidate.method_id",
            "does not match contract",
        ),
    )
    candidate.status == "NOT_RUN_BLOCKED" ||
        throw(
        ReadinessContractError(
            "solver_candidate.status",
            "must remain blocked",
        ),
    )
    Set(candidate.required_criterion_ids) == criterion_ids ||
        throw(
        ReadinessContractError(
            "solver_candidate.required_criterion_ids",
            "must contain every mandatory criterion exactly once",
        ),
    )
    Set(candidate.blocker_ids) == blocker_ids ||
        throw(
        ReadinessContractError(
            "solver_candidate.blocker_ids",
            "must contain every open blocker exactly once",
        ),
    )
    for field in (
            :admitted_solver_family_count,
            :solver_input_cell_count,
            :solver_input_control_count,
            :production_reliability_class_count,
            :production_covariance_class_count,
            :approved_exact_control_count,
            :approved_structural_zero_count,
            :reconciliation_run_count,
            :adjustment_record_count,
        )
        getfield(candidate, field) == 0 ||
            throw(
            ReadinessContractError(
                "solver_candidate.$field",
                "must be zero while blocked",
            ),
        )
    end
    for field in (
            :solver_invoked,
            :candidate_frozen,
            :adjustment_report_emitted,
            :forecast_origin_admissible,
            :promotion_ready,
            :model_state_write,
        )
        !getfield(candidate, field) ||
            throw(
            ReadinessContractError(
                "solver_candidate.$field",
                "must be false while blocked",
            ),
        )
    end
    candidate.accounting_gate_effect == "NONE" ||
        throw(
        ReadinessContractError(
            "solver_candidate.accounting_gate_effect",
            "must be NONE",
        ),
    )
    candidate.forecast_score_effect == "NONE" ||
        throw(
        ReadinessContractError(
            "solver_candidate.forecast_score_effect",
            "must be NONE",
        ),
    )

    observed_counts = Dict(
        "artifact_count" => length(contract.artifacts),
        "probe_count" => length(contract.probes),
        "source_family_count" => length(contract.source_families),
        "blocker_count" => length(contract.blockers),
        "criterion_count" => length(contract.criteria),
        "mandatory_criterion_count" =>
            count(criterion -> criterion.mandatory, contract.criteria),
        "passed_criterion_count" =>
            count(criterion -> criterion.status == "PASS", contract.criteria),
        "blocked_criterion_count" => count(
            criterion -> criterion.status == "BLOCKED",
            contract.criteria,
        ),
        "solver_candidate_count" => length(contract.solver_candidates),
    )
    for (key, value) in observed_counts
        contract.expected[key] == value ||
            throw(
            ReadinessContractError(
                "expected.$key",
                "expected $(contract.expected[key]), observed $value",
            ),
        )
    end
    for key in ZERO_EXPECTED_FIELDS
        contract.expected[key] == 0 ||
            throw(
            ReadinessContractError(
                "expected.$key",
                "must be zero while blocked",
            ),
        )
    end
    return nothing
end

function contained_artifact_path(
        repo_root::AbstractString,
        artifact::ArtifactBinding,
    )
    root = realpath(repo_root)
    candidate = normpath(joinpath(root, artifact.path))
    prefix = root * string(Base.Filesystem.path_separator)
    (candidate == root || startswith(candidate, prefix)) ||
        throw(
        ArtifactIntegrityError(
            artifact.artifact_id,
            "path escapes repository root",
        ),
    )
    ispath(candidate) ||
        throw(
        ArtifactIntegrityError(
            artifact.artifact_id,
            "path does not exist: $(artifact.path)",
        ),
    )
    islink(candidate) &&
        throw(
        ArtifactIntegrityError(
            artifact.artifact_id,
            "artifact must not be a symbolic link",
        ),
    )
    isfile(candidate) ||
        throw(
        ArtifactIntegrityError(
            artifact.artifact_id,
            "artifact must be a regular file",
        ),
    )
    resolved = realpath(candidate)
    (resolved == root || startswith(resolved, prefix)) ||
        throw(
        ArtifactIntegrityError(
            artifact.artifact_id,
            "resolved path escapes repository root",
        ),
    )
    return candidate
end

function validate_implementation(
        contract::ProductionReadinessContract,
        repo_root::AbstractString,
    )
    module_binding = ArtifactBinding(
        "readiness_module",
        contract.module_path,
        contract.module_normalized_sha256,
        "READINESS_IMPLEMENTATION",
    )
    runner_binding = ArtifactBinding(
        "readiness_runner",
        contract.runner_path,
        contract.runner_sha256,
        "READINESS_RUNNER",
    )
    module_path = contained_artifact_path(repo_root, module_binding)
    runner_path = contained_artifact_path(repo_root, runner_binding)
    observed_module = normalized_module_sha256(module_path)
    observed_module == contract.module_normalized_sha256 ||
        throw(
        ArtifactIntegrityError(
            module_binding.artifact_id,
            "expected normalized SHA-256 $(contract.module_normalized_sha256), got $observed_module",
        ),
    )
    observed_runner = file_sha256(runner_path)
    observed_runner == contract.runner_sha256 ||
        throw(
        ArtifactIntegrityError(
            runner_binding.artifact_id,
            "expected SHA-256 $(contract.runner_sha256), got $observed_runner",
        ),
    )
    return nothing
end

function build_authenticated_admission_overlay(
        contract::ProductionReadinessContract,
        contract_path::AbstractString,
        repo_root::AbstractString,
    )
    try
        admission_report =
            USProductionReconciliationAdmissionEvidence.build_production_reconciliation_admission_evidence(
            contract_path;
            repo_root,
        )
        admission_report.evidence_hash == contract.admission_evidence_hash ||
            throw(
            ArtifactIntegrityError(
                ADMISSION_CONTRACT_ARTIFACT_ID,
                "rebuilt evidence identity does not match readiness",
            ),
        )
        admission_report.contract_sha256 == file_sha256(contract_path) ||
            throw(
            ArtifactIntegrityError(
                ADMISSION_CONTRACT_ARTIFACT_ID,
                "rebuilt report does not bind the evaluated admission contract",
            ),
        )
        Set(admission_report.promotion_blockers) ==
            Set(
            mapping.admission_blocker_id
                for mapping in contract.admission_blocker_mappings
        ) ||
            throw(
            ArtifactIntegrityError(
                ADMISSION_CONTRACT_ARTIFACT_ID,
                "admission promotion blockers do not match the readiness mapping",
            ),
        )
        USProductionReconciliationAdmissionEvidence.production_reconciliation_admission_evidence_controls_pass(
            admission_report,
            contract_path;
            repo_root,
        ) ||
            throw(
            ArtifactIntegrityError(
                ADMISSION_CONTRACT_ARTIFACT_ID,
                "rebuilt admission controls do not pass",
            ),
        )
        return admission_report
    catch error
        error isa ArtifactIntegrityError && rethrow()
        throw(
            ArtifactIntegrityError(
                ADMISSION_CONTRACT_ARTIFACT_ID,
                "in-process admission rebuild failed: $(sprint(showerror, error))",
            ),
        )
    end
end

function resolve_field(document, field_path::Vector{String}, probe_id::String)
    value = document
    for field in field_path
        value isa AbstractDict ||
            throw(
            EvidenceProbeError(
                probe_id,
                "path $(join(field_path, ".")) traverses a non-table at $field",
            ),
        )
        haskey(value, field) ||
            throw(
            EvidenceProbeError(
                probe_id,
                "missing field $(join(field_path, "."))",
            ),
        )
        value = value[field]
    end
    return value
end

function probe_matches(probe::EvidenceProbe, observed)
    if probe.expected_type == "STRING"
        return observed isa String && observed == probe.expected_value
    elseif probe.expected_type == "STRING_ARRAY"
        return observed isa AbstractVector &&
            all(item -> item isa String, observed) &&
            String.(observed) == probe.expected_value
    elseif probe.expected_type == "BOOLEAN"
        return observed isa Bool && observed == probe.expected_value
    elseif probe.expected_type == "INTEGER"
        return observed isa Integer &&
            !(observed isa Bool) &&
            Int(observed) == probe.expected_value
    elseif probe.expected_type == "NUMBER"
        return observed isa Real &&
            !(observed isa Bool) &&
            Float64(observed) == probe.expected_value
    end
    return false
end

function render_scalar(value)
    value isa Bool && return value ? "true" : "false"
    value isa AbstractFloat && return string(Float64(value))
    return string(value)
end

function _evaluate_production_readiness_unsealed(
        contract::ProductionReadinessContract;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    validate_production_readiness_contract(contract)
    validate_implementation(contract, repo_root)
    sorted_artifacts =
        sort!(copy(contract.artifacts); by = artifact -> artifact.artifact_id)
    paths = Dict{String, String}()
    before_hashes = Dict{String, String}()
    documents = Dict{String, Dict{String, Any}}()
    probed_artifact_ids =
        Set(probe.artifact_id for probe in contract.probes)
    for artifact in sorted_artifacts
        path = contained_artifact_path(repo_root, artifact)
        observed = file_sha256(path)
        observed == artifact.sha256 ||
            throw(
            ArtifactIntegrityError(
                artifact.artifact_id,
                "expected SHA-256 $(artifact.sha256), got $observed",
            ),
        )
        paths[artifact.artifact_id] = path
        before_hashes[artifact.artifact_id] = observed
        if artifact.artifact_id in probed_artifact_ids
            documents[artifact.artifact_id] = TOML.parsefile(path)
        end
    end

    probe_results = EvidenceProbeResult[]
    for probe in sort!(copy(contract.probes); by = item -> item.probe_id)
        observed = resolve_field(
            documents[probe.artifact_id],
            probe.field_path,
            probe.probe_id,
        )
        probe_matches(probe, observed) ||
            throw(
            EvidenceProbeError(
                probe.probe_id,
                "expected $(render_scalar(probe.expected_value)) ($(probe.expected_type)), got $(render_scalar(observed)) ($(typeof(observed)))",
            ),
        )
        push!(
            probe_results,
            EvidenceProbeResult(
                probe.probe_id,
                probe.artifact_id,
                copy(probe.field_path),
                probe.expected_type,
                probe.expected_value,
                observed,
                "PASS",
            ),
        )
    end

    admission_report = build_authenticated_admission_overlay(
        contract,
        paths[ADMISSION_CONTRACT_ARTIFACT_ID],
        repo_root,
    )

    artifact_validations = ArtifactValidation[]
    for artifact in sorted_artifacts
        after_sha256 = file_sha256(paths[artifact.artifact_id])
        after_sha256 == before_hashes[artifact.artifact_id] ||
            throw(
            ArtifactIntegrityError(
                artifact.artifact_id,
                "artifact changed during semantic validation",
            ),
        )
        push!(
            artifact_validations,
            ArtifactValidation(
                artifact.artifact_id,
                artifact.path,
                artifact.role,
                artifact.sha256,
                before_hashes[artifact.artifact_id],
                after_sha256,
                "PASS",
            ),
        )
    end

    criteria =
        sort!(copy(contract.criteria); by = criterion -> criterion.criterion_id)
    blockers =
        sort!(copy(contract.blockers); by = blocker -> blocker.blocker_id)
    blocking_criterion_ids = String[
        criterion.criterion_id
            for criterion in criteria
            if criterion.mandatory && criterion.status != "PASS"
    ]
    blocker_ids = String[blocker.blocker_id for blocker in blockers]
    ready = isempty(blocking_criterion_ids) && isempty(blocker_ids)
    ready &&
        throw(
        ReadinessContractError(
            "result.ready",
            "v2 evidence unexpectedly claims readiness",
        ),
    )
    candidate = only(contract.solver_candidates)
    result = ProductionReadinessResult(
        contract.source_sha256,
        admission_report.evidence_hash,
        "NOT_RUN_BLOCKED",
        false,
        artifact_validations,
        probe_results,
        sort!(
            copy(contract.source_families);
            by = source -> source.source_family_id,
        ),
        blockers,
        criteria,
        candidate,
        blocking_criterion_ids,
        blocker_ids,
    )
    return result
end

function evaluate_production_readiness(
        contract::ProductionReadinessContract;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    contract.source_sha256 == APPROVED_CONTRACT_SHA256 ||
        throw(
        ReadinessContractError(
            "contract.sha256",
            "public evaluation requires the approved sealed contract",
        ),
    )
    return _evaluate_production_readiness_unsealed(
        contract;
        repo_root,
    )
end

function require_production_reconciliation_ready(
        result::ProductionReadinessResult,
    )
    result.ready ||
        throw(
        ProductionReconciliationBlockedError(copy(result.blocker_ids)),
    )
    return nothing
end

function csv_escape(value)
    rendered = render_scalar(value)
    if occursin(',', rendered) ||
            occursin('"', rendered) ||
            occursin('\n', rendered) ||
            occursin('\r', rendered)
        return "\"" * replace(rendered, "\"" => "\"\"") * "\""
    end
    return rendered
end

function write_csv(path::AbstractString, header::Vector{String}, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(
                io,
                join((csv_escape(value) for value in row), ","),
            )
        end
    end
    return path
end

function observed_probe_value(
        result::ProductionReadinessResult,
        probe_id::String,
    )
    return only(
        probe.observed_value
            for probe in result.probe_results
            if probe.probe_id == probe_id
    )
end

function write_admission_overlay(
        path::AbstractString,
        contract::ProductionReadinessContract,
        result::ProductionReadinessResult,
    )
    admission_contract_sha256 = only(
        validation.after_sha256
            for validation in result.artifact_validations
            if validation.artifact_id == ADMISSION_CONTRACT_ARTIFACT_ID
    )
    rows = [
        (
                result.admission_evidence_hash,
                admission_contract_sha256,
                observed_probe_value(
                    result,
                    "admission_candidate_problem_scope_hash",
                ),
                observed_probe_value(
                    result,
                    "admission_candidate_problem_hash",
                ),
                observed_probe_value(
                    result,
                    "admission_observation_loading_count",
                ),
                observed_probe_value(
                    result,
                    "admission_domestic_use_point_count",
                ),
                observed_probe_value(
                    result,
                    "admission_domestic_use_raw_evaluable_count",
                ),
                observed_probe_value(result, "admission_negative_cell_count"),
                observed_probe_value(
                    result,
                    "admission_source_mechanically_typed_negative_cell_count",
                ),
                observed_probe_value(
                    result,
                    "admission_literature_supported_negative_cell_count",
                ),
                observed_probe_value(
                    result,
                    "admission_unresolved_negative_cell_count",
                ),
                observed_probe_value(
                    result,
                    "admission_component_unresolved_signed_cell_count",
                ),
                observed_probe_value(
                    result,
                    "admission_dependence_group_count",
                ),
                observed_probe_value(
                    result,
                    "admission_revision_vintage_receipt_count",
                ),
                mapping.admission_blocker_id,
                join(mapping.readiness_blocker_ids, "|"),
                false,
                "OPEN_PRESERVED",
            )
            for mapping in sort!(
                copy(contract.admission_blocker_mappings);
                by = item -> item.admission_blocker_id,
            )
    ]
    return write_csv(
        path,
        [
            "admission_evidence_hash",
            "admission_contract_sha256",
            "candidate_problem_scope_hash",
            "candidate_problem_hash",
            "observation_loading_count",
            "domestic_use_point_count",
            "domestic_use_raw_evaluable_count",
            "negative_cell_count",
            "source_mechanically_typed_negative_cell_count",
            "literature_supported_negative_cell_count",
            "unresolved_negative_cell_count",
            "component_unresolved_signed_cell_count",
            "candidate_dependence_group_count",
            "revision_vintage_receipt_count",
            "admission_blocker_id",
            "readiness_blocker_ids",
            "solver_admissible",
            "mapping_status",
        ],
        rows,
    )
end

function toml_quote(value::String)
    escaped = replace(
        value,
        "\\" => "\\\\",
        "\"" => "\\\"",
        "\n" => "\\n",
        "\r" => "\\r",
        "\t" => "\\t",
    )
    return "\"" * escaped * "\""
end

function toml_string_array(values::Vector{String})
    return "[" *
        join((toml_quote(value) for value in values), ", ") *
        "]"
end

function write_status(
        path::AbstractString,
        contract::ProductionReadinessContract,
        result::ProductionReadinessResult,
    )
    candidate = result.candidate
    open(path, "w") do io
        println(io, "schema_version = ", toml_quote(STATUS_SCHEMA))
        println(io, "contract_id = ", toml_quote(contract.contract_id))
        println(io, "contract_sha256 = ", toml_quote(result.contract_sha256))
        println(
            io,
            "admission_evidence_hash = ",
            toml_quote(result.admission_evidence_hash),
        )
        println(
            io,
            "admission_promotion_blocker_count = ",
            length(contract.admission_blocker_mappings),
        )
        println(
            io,
            "admission_unresolved_negative_cell_count = ",
            observed_probe_value(
                result,
                "admission_unresolved_negative_cell_count",
            ),
        )
        println(io, "overall_status = ", toml_quote(result.overall_status))
        println(io, "ready = false")
        println(io, "target_country = ", toml_quote(contract.target_country))
        println(
            io,
            "target_reference_period = ",
            toml_quote(contract.target_reference_period),
        )
        println(
            io,
            "target_frequency = ",
            toml_quote(contract.target_frequency),
        )
        println(
            io,
            "target_time_basis = ",
            toml_quote(contract.target_time_basis),
        )
        println(
            io,
            "target_stock_flow_class = ",
            toml_quote(contract.target_stock_flow_class),
        )
        println(
            io,
            "target_currency = ",
            toml_quote(contract.target_currency),
        )
        println(io, "target_unit = ", toml_quote(contract.target_unit))
        println(
            io,
            "target_price_basis = ",
            toml_quote(contract.target_price_basis),
        )
        println(io, "target_axis = ", toml_quote(contract.target_axis))
        println(
            io,
            "solver_method_id = ",
            toml_quote(contract.solver_method_id),
        )
        println(
            io,
            "solver_invocation_status = ",
            toml_quote(contract.solver_invocation_status),
        )
        println(io, "artifact_count = ", length(result.artifact_validations))
        println(io, "probe_count = ", length(result.probe_results))
        println(io, "source_family_count = ", length(result.source_families))
        println(io, "criterion_count = ", length(result.criteria))
        println(
            io,
            "blocking_criterion_count = ",
            length(result.blocking_criterion_ids),
        )
        println(io, "blocker_count = ", length(result.blocker_ids))
        println(
            io,
            "blocking_criterion_ids = ",
            toml_string_array(result.blocking_criterion_ids),
        )
        println(
            io,
            "blocker_ids = ",
            toml_string_array(result.blocker_ids),
        )
        println(
            io,
            "candidate_id = ",
            toml_quote(candidate.candidate_id),
        )
        println(
            io,
            "admitted_solver_family_count = ",
            candidate.admitted_solver_family_count,
        )
        println(
            io,
            "solver_input_cell_count = ",
            candidate.solver_input_cell_count,
        )
        println(
            io,
            "solver_input_control_count = ",
            candidate.solver_input_control_count,
        )
        println(
            io,
            "production_reliability_class_count = ",
            candidate.production_reliability_class_count,
        )
        println(
            io,
            "production_covariance_class_count = ",
            candidate.production_covariance_class_count,
        )
        println(
            io,
            "approved_exact_control_count = ",
            candidate.approved_exact_control_count,
        )
        println(
            io,
            "approved_structural_zero_count = ",
            candidate.approved_structural_zero_count,
        )
        println(io, "solver_invoked = false")
        println(
            io,
            "reconciliation_run_count = ",
            candidate.reconciliation_run_count,
        )
        println(
            io,
            "adjustment_record_count = ",
            candidate.adjustment_record_count,
        )
        println(io, "candidate_frozen = false")
        println(io, "adjustment_report_emitted = false")
        println(io, "forecast_origin_admissible = false")
        println(io, "promotion_ready = false")
        println(io, "model_state_write = false")
        println(io, "accounting_gate_effect = \"NONE\"")
        println(io, "forecast_score_effect = \"NONE\"")
    end
    return path
end

function write_manifest(
        path::AbstractString,
        contract::ProductionReadinessContract,
        result::ProductionReadinessResult,
        output_rows,
    )
    open(path, "w") do io
        println(io, "schema_version = ", toml_quote(REPORT_MANIFEST_SCHEMA))
        println(io, "contract_id = ", toml_quote(contract.contract_id))
        println(io, "contract_sha256 = ", toml_quote(result.contract_sha256))
        println(
            io,
            "admission_evidence_hash = ",
            toml_quote(result.admission_evidence_hash),
        )
        println(
            io,
            "module_normalized_sha256 = ",
            toml_quote(contract.module_normalized_sha256),
        )
        println(io, "runner_sha256 = ", toml_quote(contract.runner_sha256))
        println(io, "julia_version = ", toml_quote(string(VERSION)))
        println(io, "machine = ", toml_quote(Sys.MACHINE))
        println(io, "word_size = ", Sys.WORD_SIZE)
        println(io, "overall_status = \"NOT_RUN_BLOCKED\"")
        println(io, "ready = false")
        for row in output_rows
            println(io)
            println(io, "[[output]]")
            println(io, "role = ", toml_quote(row.role))
            println(io, "path = ", toml_quote(row.path))
            println(io, "sha256 = ", toml_quote(row.sha256))
        end
    end
    return path
end

function assert_artifacts_unchanged(
        contract::ProductionReadinessContract,
        result::ProductionReadinessResult,
        repo_root::AbstractString,
    )
    contract.source_sha256 == result.contract_sha256 ||
        throw(
        ReadinessContractError(
            "result.contract_sha256",
            "does not match the loaded contract",
        ),
    )
    for validation in result.artifact_validations
        artifact = only(
            item
                for item in contract.artifacts
                if item.artifact_id == validation.artifact_id
        )
        path = contained_artifact_path(repo_root, artifact)
        observed = file_sha256(path)
        observed == validation.after_sha256 ||
            throw(
            ArtifactIntegrityError(
                artifact.artifact_id,
                "changed after readiness evaluation",
            ),
        )
    end
    return nothing
end

function prepare_output_directory(output_directory::AbstractString)
    output_path = abspath(output_directory)
    islink(output_path) &&
        throw(
        ReadinessContractError(
            "output_directory",
            "must not be a symbolic link",
        ),
    )
    if ispath(output_path)
        isdir(output_path) ||
            throw(
            ReadinessContractError(
                "output_directory",
                "must be a directory",
            ),
        )
    else
        mkpath(output_path)
    end
    islink(output_path) &&
        throw(
        ReadinessContractError(
            "output_directory",
            "became a symbolic link while preparing the report",
        ),
    )
    isempty(readdir(output_path)) ||
        throw(
        ReadinessContractError(
            "output_directory",
            "must be empty so a readiness report cannot overwrite or mix with existing evidence",
        ),
    )
    return output_path
end

function build_production_readiness_report(
        output_directory::AbstractString;
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH,
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    output_directory = prepare_output_directory(output_directory)
    contract = load_production_readiness_contract(contract_path)
    result = evaluate_production_readiness(contract; repo_root = repo_root)
    artifact_path =
        joinpath(output_directory, "production_reconciliation_artifacts.csv")
    probe_path =
        joinpath(output_directory, "production_reconciliation_probes.csv")
    source_path =
        joinpath(output_directory, "production_reconciliation_sources.csv")
    blocker_path =
        joinpath(output_directory, "production_reconciliation_blockers.csv")
    criterion_path =
        joinpath(output_directory, "production_reconciliation_criteria.csv")
    admission_overlay_path = joinpath(
        output_directory,
        "production_reconciliation_admission_overlay.csv",
    )
    status_path =
        joinpath(output_directory, "production_reconciliation_status.toml")
    manifest_path =
        joinpath(output_directory, "production_reconciliation_manifest.toml")

    write_csv(
        artifact_path,
        [
            "artifact_id",
            "path",
            "role",
            "expected_sha256",
            "before_sha256",
            "after_sha256",
            "status",
        ],
        (
            (
                    row.artifact_id,
                    row.path,
                    row.role,
                    row.expected_sha256,
                    row.before_sha256,
                    row.after_sha256,
                    row.status,
                )
                for row in result.artifact_validations
        ),
    )
    write_csv(
        probe_path,
        [
            "probe_id",
            "artifact_id",
            "field_path",
            "expected_type",
            "expected_value",
            "observed_value",
            "status",
        ],
        (
            (
                    row.probe_id,
                    row.artifact_id,
                    join(row.field_path, "."),
                    row.expected_type,
                    render_scalar(row.expected_value),
                    render_scalar(row.observed_value),
                    row.status,
                )
                for row in result.probe_results
        ),
    )
    write_csv(
        source_path,
        [
            "source_family_id",
            "artifact_ids",
            "source_namespace",
            "evidence_role",
            "country",
            "reference_period",
            "frequency",
            "time_basis",
            "stock_flow_class",
            "currency",
            "unit",
            "price_basis",
            "valuation_basis",
            "row_axis",
            "column_axis",
            "vintage_status",
            "release_identity",
            "cell_state_policy",
            "target_basis_compatible",
            "lineage_group",
            "admission_status",
            "solver_cell_count",
            "solver_control_count",
            "blocker_ids",
            "literature_ids",
        ],
        (
            (
                    source.source_family_id,
                    join(source.artifact_ids, "|"),
                    source.source_namespace,
                    source.evidence_role,
                    source.country,
                    source.reference_period,
                    source.frequency,
                    source.time_basis,
                    source.stock_flow_class,
                    source.currency,
                    source.unit,
                    source.price_basis,
                    source.valuation_basis,
                    source.row_axis,
                    source.column_axis,
                    source.vintage_status,
                    source.release_identity,
                    source.cell_state_policy,
                    source.target_basis_compatible,
                    source.lineage_group,
                    source.admission_status,
                    source.solver_cell_count,
                    source.solver_control_count,
                    join(source.blocker_ids, "|"),
                    join(source.literature_ids, "|"),
                )
                for source in result.source_families
        ),
    )
    write_csv(
        blocker_path,
        [
            "blocker_id",
            "status",
            "required_for",
            "source_family_ids",
            "blocking_fact",
            "required_evidence",
            "resolution_test",
            "evidence_probe_ids",
            "literature_ids",
        ],
        (
            (
                    blocker.blocker_id,
                    blocker.status,
                    blocker.required_for,
                    join(blocker.source_family_ids, "|"),
                    blocker.blocking_fact,
                    blocker.required_evidence,
                    blocker.resolution_test,
                    join(blocker.evidence_probe_ids, "|"),
                    join(blocker.literature_ids, "|"),
                )
                for blocker in result.blockers
        ),
    )
    write_csv(
        criterion_path,
        [
            "criterion_id",
            "category",
            "mandatory",
            "status",
            "blocker_ids",
            "evidence_probe_ids",
            "finding",
            "completion_requirement",
        ],
        (
            (
                    criterion.criterion_id,
                    criterion.category,
                    criterion.mandatory,
                    criterion.status,
                    join(criterion.blocker_ids, "|"),
                    join(criterion.evidence_probe_ids, "|"),
                    criterion.finding,
                    criterion.completion_requirement,
                )
                for criterion in result.criteria
        ),
    )
    write_admission_overlay(admission_overlay_path, contract, result)
    write_status(status_path, contract, result)

    assert_artifacts_unchanged(contract, result, repo_root)
    output_rows = [
        (
            role = "ARTIFACT_VALIDATION",
            path = basename(artifact_path),
            sha256 = file_sha256(artifact_path),
        ),
        (
            role = "EVIDENCE_PROBES",
            path = basename(probe_path),
            sha256 = file_sha256(probe_path),
        ),
        (
            role = "SOURCE_FAMILY_REGISTRY",
            path = basename(source_path),
            sha256 = file_sha256(source_path),
        ),
        (
            role = "READINESS_BLOCKERS",
            path = basename(blocker_path),
            sha256 = file_sha256(blocker_path),
        ),
        (
            role = "READINESS_CRITERIA",
            path = basename(criterion_path),
            sha256 = file_sha256(criterion_path),
        ),
        (
            role = "ADMISSION_OVERLAY",
            path = basename(admission_overlay_path),
            sha256 = file_sha256(admission_overlay_path),
        ),
        (
            role = "CANDIDATE_STATUS",
            path = basename(status_path),
            sha256 = file_sha256(status_path),
        ),
    ]
    write_manifest(manifest_path, contract, result, output_rows)
    return (
        contract = contract,
        result = result,
        artifact_path = artifact_path,
        artifact_sha256 = file_sha256(artifact_path),
        probe_path = probe_path,
        probe_sha256 = file_sha256(probe_path),
        source_path = source_path,
        source_sha256 = file_sha256(source_path),
        blocker_path = blocker_path,
        blocker_sha256 = file_sha256(blocker_path),
        criterion_path = criterion_path,
        criterion_sha256 = file_sha256(criterion_path),
        admission_overlay_path = admission_overlay_path,
        admission_overlay_sha256 = file_sha256(admission_overlay_path),
        status_path = status_path,
        status_sha256 = file_sha256(status_path),
        manifest_path = manifest_path,
        manifest_sha256 = file_sha256(manifest_path),
    )
end

end
