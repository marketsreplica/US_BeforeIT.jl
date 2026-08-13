module USProductionReconciliationLedger

using CSV
using SHA
using TOML

using ..USAfterRedefinitionsCommonBasis:
    load_after_redefinitions_fixture
using ..USAfterRedefinitionsProducerPriceAdapterCandidate:
    build_producer_price_adapter_candidate,
    producer_price_adapter_candidate_controls_pass

export CONTRACT_SCHEMA,
    CELL_SCHEMA_FIELDS,
    CONTROL_SCHEMA_FIELDS,
    APPROVED_CONTRACT_SHA256,
    ProductionLedgerContractError,
    ProductionSolverBlockedError,
    ProductionCellRecord,
    ProductionControlRecord,
    SourceLineageMember,
    TargetLineage,
    ControlLineage,
    SemanticOverlay,
    LineageRelation,
    ProductionReconciliationLedger,
    build_production_reconciliation_ledger,
    production_reconciliation_ledger_internal_controls_pass,
    production_reconciliation_ledger_source_controls_pass,
    production_reconciliation_ledger_controls_pass,
    materialize_production_reconciliation_solver_input,
    write_production_reconciliation_ledger_report,
    normalized_module_sha256

const CONTRACT_SCHEMA =
    "beforeit-us-production-reconciliation-candidate-ledger-contract.v1"
const REPORT_SCHEMA =
    "beforeit-us-production-reconciliation-candidate-ledger-report.v1"
const STATUS_SCHEMA =
    "beforeit-us-production-reconciliation-candidate-ledger-status.v1"
const MANIFEST_SCHEMA =
    "beforeit-us-production-reconciliation-candidate-ledger-manifest.v1"
const APPROVED_CONTRACT_SHA256 =
    "79a029665e45f5b981b6333e278d4ee35486980f39037de4e921e066695292c5"
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "production_reconciliation_candidate_ledger.toml")
const DEFAULT_REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const ZERO_SHA256 = repeat("0", 64)

const CELL_SCHEMA_FIELDS = [
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

const CONTROL_SCHEMA_FIELDS = [
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

const PRIMARY_PROJECTION_IDS = [
    "producer_intermediate_use_2024",
    "producer_final_use_2024",
    "producer_value_added_2024",
    "producer_make_2024",
    "producer_make_commodity_output_2024",
    "producer_make_industry_output_2024",
    "import_intermediate_use_2024",
    "import_final_use_2024",
]
const CONTROL_PROJECTION_IDS = [
    "producer_use_commodity_controls_2024",
    "producer_use_industry_controls_2024",
    "producer_use_grand_controls_2024",
    "producer_make_grand_output_2024",
    "import_commodity_controls_2024",
]
const RELEVANT_PROJECTION_IDS =
    Set(vcat(PRIMARY_PROJECTION_IDS, CONTROL_PROJECTION_IDS))
const CLOSURE_CODES = Set(["Used", "Other"])
const RETAIL_SOURCE_CODES = Set(["441", "445", "452", "4A0"])
const SELECTED_ZERO_STATE = "SOURCE_SELECTED_ZERO_NOT_SHOWN"
const NUMERIC_STATE = "SOURCE_NUMERIC"
const EXPLICIT_ZERO_STATE = "SOURCE_EXPLICIT_NUMERIC_ZERO"
const DERIVED_ZERO_STATE = "DERIVED_EXACT_IDENTITY_ZERO"
const QUARANTINED_SOLVER_ROLE = "QUARANTINED_NOT_SOLVER_ADMITTED"
const RELEASE_PREFIX = "CONTENT_SHA256:"
const SOURCE_FAMILY_CORE =
    "BEA_AFTER_REDEFINITIONS_2024_PRODUCER_CORE"
const SOURCE_FAMILY_CLOSURE =
    "BEA_AFTER_REDEFINITIONS_2024_USED_OTHER_SUMMARY"
const SOURCE_FAMILY_IMPORT =
    "BEA_AFTER_REDEFINITIONS_2024_IMPUTED_IMPORT_ALLOCATION"

const TOP_LEVEL_KEYS = Set(
    [
        "schema_version",
        "contract_id",
        "classification",
        "artifact_role",
        "promotion_status",
        "scientific_scope",
        "target_country",
        "target_reference_period",
        "target_frequency",
        "target_time_basis",
        "target_stock_flow_class",
        "target_currency",
        "target_unit",
        "target_price_basis",
        "target_axis",
        "problem_scope_hash",
        "source_fixture_sha256",
        "source_manifest_sha256",
        "source_zip_sha256",
        "source_metadata_sha256",
        "model_mapping_sha256",
        "sector_mapping_sha256",
        "producer_adapter_contract_sha256",
        "inventory_evidence_contract_sha256",
        "used_other_evidence_contract_sha256",
        "canonical_key_policy",
        "lineage_policy",
        "selected_zero_policy",
        "overlay_policy",
        "control_policy",
        "solver_policy",
        "production_cell_schema_fields",
        "production_control_schema_fields",
        "forecast_origin_admissible",
        "promotion_ready",
        "model_state_write",
        "accounting_gate_effect",
        "forecast_score_effect",
        "solver_invocation_count",
        "solver_input_cell_count",
        "solver_input_control_count",
        "approved_exact_control_count",
        "approved_structural_zero_count",
        "adjustment_record_count",
        "promotion_blockers",
        "implementation",
        "expected",
        "artifact",
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
        "target_raw_source_leaf_count",
        "control_raw_source_leaf_count",
        "source_lineage_member_count",
        "candidate_cell_count",
        "producer_system_cell_count",
        "import_evidence_cell_count",
        "core_cell_count",
        "used_other_cell_count",
        "numeric_nonzero_cell_count",
        "explicit_numeric_zero_cell_count",
        "selected_zero_not_shown_cell_count",
        "negative_cell_count",
        "candidate_control_count",
        "candidate_identity_count",
        "candidate_identity_term_count",
        "candidate_identity_structural_rank",
        "published_control_count",
        "numeric_control_count",
        "selected_zero_not_shown_control_count",
        "used_other_control_count",
        "f030_overlay_count",
        "used_other_overlay_count",
        "overlay_count",
        "unique_overlay_owner_count",
        "lineage_relation_count",
        "solver_input_cell_count",
        "solver_input_control_count",
        "approved_exact_control_count",
        "approved_structural_zero_count",
        "adjustment_record_count",
    ],
)
const ARTIFACT_KEYS = Set(["artifact_id", "path", "sha256", "role"])

struct ProductionLedgerContractError <: Exception
    location::String
    detail::String
end

struct ProductionSolverBlockedError <: Exception
    blocker_ids::Vector{String}
end

function Base.showerror(io::IO, error::ProductionLedgerContractError)
    return print(io, error.location, ": ", error.detail)
end

function Base.showerror(io::IO, error::ProductionSolverBlockedError)
    return print(
        io,
        "production solver materialization is blocked by: ",
        join(error.blocker_ids, ", "),
    )
end

struct ArtifactBinding
    artifact_id::String
    relative_path::String
    path::String
    sha256::String
    role::String
end

struct ProductionLedgerContract
    path::String
    repo_root::String
    source_sha256::String
    contract_id::String
    classification::String
    artifact_role::String
    promotion_status::String
    problem_scope_hash::String
    source_fixture_sha256::String
    source_manifest_sha256::String
    source_zip_sha256::String
    source_metadata_sha256::String
    model_mapping_sha256::String
    sector_mapping_sha256::String
    producer_adapter_contract_sha256::String
    inventory_evidence_contract_sha256::String
    used_other_evidence_contract_sha256::String
    module_path::String
    module_normalized_sha256::String
    runner_path::String
    runner_sha256::String
    expected::Dict{String, Int}
    artifacts::Dict{String, ArtifactBinding}
    promotion_blockers::Vector{String}
end

"""
Production observation candidate. Nullable fields remain unresolved; there is
no benchmark-answer field and no synthetic-fixture flag in this type.
"""
struct ProductionCellRecord
    cell_id::String
    canonical_source_key::String
    lineage_hash::String
    source_family_id::String
    source_artifact_sha256::String
    source_projection_sha256::String
    release_id::String
    retrieved_at_utc::String
    reference_period::String
    frequency::String
    time_basis::String
    stock_flow_class::String
    country::String
    currency::String
    unit::String
    price_basis::String
    valuation_basis::String
    row_namespace::String
    row_code::String
    column_namespace::String
    column_code::String
    raw_value::Union{Nothing, Float64}
    cell_state::String
    economic_type::String
    negative_economic_type::String
    sign_domain::String
    counterpart_group_id::Union{Nothing, String}
    structural_zero_evidence_id::Union{Nothing, String}
    transformation_ids::Vector{String}
    reliability_class_id::Union{Nothing, String}
    covariance_group_id::Union{Nothing, String}
    solver_role::String
    problem_scope_hash::String
    approval_id::Union{Nothing, String}
    provenance::String
end

"""
Production control candidate. A missing RHS is a retained source state, not
numeric zero. Source hashes are plural because definitional candidates span
more than one source projection.
"""
struct ProductionControlRecord
    control_id::String
    control_kind::String
    term_cell_ids::Vector{String}
    coefficients::Vector{Float64}
    rhs::Union{Nothing, Float64}
    rhs_state::String
    country::String
    reference_period::String
    frequency::String
    time_basis::String
    stock_flow_class::String
    currency::String
    unit::String
    price_basis::String
    valuation_basis::String
    source_artifact_sha256s::Vector{String}
    source_projection_sha256s::Vector{String}
    release_id::String
    retrieved_at_utc::String
    canonical_control_key::String
    lineage_hash::String
    transformation_ids::Vector{String}
    rounding_or_measurement_model::String
    independence_status::String
    fixed_status::String
    problem_scope_hash::String
    approval_id::Union{Nothing, String}
    provenance::String
end

struct SourceLineageMember
    canonical_source_key::String
    lineage_hash::String
    projection_id::String
    projection_sha256::String
    source_member::String
    source_workbook_sha256::String
    row_position::Int
    row_type::String
    row_code::String
    column_position::Int
    column_type::String
    column_code::String
    source_value_token::String
    source_cell_state::String
end

struct TargetLineage
    owner_id::String
    canonical_source_key::String
    lineage_hash::String
    transformation_id::String
    parent_source_keys::Vector{String}
    parent_lineage_hashes::Vector{String}
end

struct ControlLineage
    owner_id::String
    canonical_control_key::String
    lineage_hash::String
    transformation_id::String
    parent_source_keys::Vector{String}
    parent_lineage_hashes::Vector{String}
    term_cell_ids::Vector{String}
end

"""
Value-free reference from an existing diagnostic view to one canonical owner.
"""
struct SemanticOverlay
    overlay_id::String
    view_id::String
    owner_kind::String
    owner_id::String
    source_view_record_id::String
    annotation_kind::String
    annotation::String
end

struct LineageRelation
    relation_id::String
    relation_kind::String
    source_owner_ids::Vector{String}
    descendant_owner_ids::Vector{String}
    independence_status::String
    solver_weight_contribution::Int
    provenance::String
end

struct ProductionReconciliationLedger
    schema_version::String
    contract_sha256::String
    problem_scope_hash::String
    problem_hash::String
    cells::Vector{ProductionCellRecord}
    controls::Vector{ProductionControlRecord}
    source_lineage_members::Vector{SourceLineageMember}
    target_lineages::Vector{TargetLineage}
    control_lineages::Vector{ControlLineage}
    overlays::Vector{SemanticOverlay}
    relations::Vector{LineageRelation}
    unresolved_negative_cell_ids::Vector{String}
    promotion_blockers::Vector{String}
    candidate_materialized::Bool
    canonical_lineage_deduplicated::Bool
    solver_invocation_count::Int
    solver_input_cell_count::Int
    solver_input_control_count::Int
    approved_exact_control_count::Int
    approved_structural_zero_count::Int
    adjustment_record_count::Int
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_state_write::Bool
    accounting_gate_effect::String
    forecast_score_effect::String
end

struct RawCell
    projection_id::String
    year::Int
    row_position::Int
    row_code::String
    row_type::String
    column_position::Int
    column_code::String
    column_type::String
    value::Float64
    source_cell_kind::String
end

struct ProjectionData
    projection_id::String
    year::Int
    row_type::String
    column_type::String
    source_member::String
    source_workbook_sha256::String
    projection_sha256::String
    source_ranges::Vector{String}
    row_codes::Vector{String}
    column_codes::Vector{String}
    cells::Dict{Tuple{String, String}, RawCell}
end

file_sha256(path::AbstractString) = bytes2hex(SHA.sha256(read(path)))

function is_sha256(value)
    return value isa String &&
        occursin(r"^[0-9a-f]{64}$", value)
end

function normalized_module_sha256(path::AbstractString)
    source = read(path, String)
    needle = "const APPROVED_CONTRACT_SHA256 =\n    \"" *
        APPROVED_CONTRACT_SHA256 * "\""
    count(needle, source) == 1 ||
        throw(
        ProductionLedgerContractError(
            "implementation.module",
            "approved contract hash literal is not unique",
        ),
    )
    normalized = replace(
        source,
        needle =>
            "const APPROVED_CONTRACT_SHA256 =\n    \"" * ZERO_SHA256 * "\"",
    )
    return bytes2hex(SHA.sha256(codeunits(normalized)))
end

function exact_keys(table, expected, location)
    observed = Set(String(key) for key in keys(table))
    observed == expected ||
        throw(
        ProductionLedgerContractError(
            location,
            "unexpected keys; missing=$(sort!(collect(setdiff(expected, observed)))), extra=$(sort!(collect(setdiff(observed, expected))))",
        ),
    )
    return nothing
end

function required_string(table, key, location)
    value = get(table, key, nothing)
    value isa String && !isempty(value) ||
        throw(
        ProductionLedgerContractError(
            "$location.$key",
            "must be a nonempty string",
        ),
    )
    return value
end

function required_bool(table, key, location)
    value = get(table, key, nothing)
    value isa Bool ||
        throw(
        ProductionLedgerContractError(
            "$location.$key",
            "must be Boolean",
        ),
    )
    return value
end

function required_int(table, key, location)
    value = get(table, key, nothing)
    value isa Integer && !(value isa Bool) ||
        throw(
        ProductionLedgerContractError(
            "$location.$key",
            "must be an integer",
        ),
    )
    return Int(value)
end

function required_strings(table, key, location; allow_empty = false)
    value = get(table, key, nothing)
    value isa AbstractVector && all(item -> item isa String, value) ||
        throw(
        ProductionLedgerContractError(
            "$location.$key",
            "must be a string array",
        ),
    )
    result = String.(value)
    (!allow_empty && isempty(result)) &&
        throw(
        ProductionLedgerContractError(
            "$location.$key",
            "cannot be empty",
        ),
    )
    return result
end

function contained_path(repo_root, relative_path, location)
    isabspath(relative_path) &&
        throw(ProductionLedgerContractError(location, "must be relative"))
    normalized = normpath(joinpath(repo_root, relative_path))
    prefix = string(normpath(repo_root), Base.Filesystem.path_separator)
    startswith(normalized, prefix) ||
        throw(ProductionLedgerContractError(location, "escapes repository"))
    return normalized
end

function declared_scope_hash(raw)
    parts = String[
        "beforeit.production-problem-scope.v1",
        String(raw["contract_id"]),
        String(raw["target_country"]),
        String(raw["target_reference_period"]),
        String(raw["target_frequency"]),
        String(raw["target_time_basis"]),
        String(raw["target_stock_flow_class"]),
        String(raw["target_currency"]),
        String(raw["target_unit"]),
        String(raw["target_price_basis"]),
        String(raw["target_axis"]),
        String(raw["source_fixture_sha256"]),
        String(raw["source_manifest_sha256"]),
        String(raw["source_zip_sha256"]),
        String(raw["source_metadata_sha256"]),
        String(raw["model_mapping_sha256"]),
        String(raw["sector_mapping_sha256"]),
        String(raw["producer_adapter_contract_sha256"]),
        String(raw["inventory_evidence_contract_sha256"]),
        String(raw["used_other_evidence_contract_sha256"]),
    ]
    append!(parts, String.(raw["production_cell_schema_fields"]))
    append!(parts, String.(raw["production_control_schema_fields"]))
    return "scope1:" * digest(parts...)
end

function load_contract(
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    isfile(contract_path) ||
        throw(
        ProductionLedgerContractError(
            "contract.path",
            "file is missing",
        ),
    )
    islink(contract_path) &&
        throw(
        ProductionLedgerContractError(
            "contract.path",
            "symbolic links are prohibited",
        ),
    )
    contract_hash = file_sha256(contract_path)
    contract_hash == APPROVED_CONTRACT_SHA256 ||
        throw(
        ProductionLedgerContractError(
            "contract.sha256",
            "expected $APPROVED_CONTRACT_SHA256, got $contract_hash",
        ),
    )
    raw = TOML.parsefile(contract_path)
    exact_keys(raw, TOP_LEVEL_KEYS, "contract")
    required_string(raw, "schema_version", "contract") == CONTRACT_SCHEMA ||
        throw(
        ProductionLedgerContractError(
            "contract.schema_version",
            "unsupported schema",
        ),
    )
    required_string(raw, "classification", "contract") ==
        "CURRENT_VINTAGE_CANDIDATE_LEDGER_NOT_SOLVER_ADMITTED" ||
        throw(
        ProductionLedgerContractError(
            "contract.classification",
            "changed",
        ),
    )
    required_string(raw, "artifact_role", "contract") ==
        "AUTHENTICATED_PRODUCTION_SCHEMA_AND_LINEAGE_CANDIDATE" ||
        throw(
        ProductionLedgerContractError(
            "contract.artifact_role",
            "changed",
        ),
    )
    required_string(raw, "promotion_status", "contract") ==
        "RESEARCH_ONLY_NOT_PROMOTED" ||
        throw(
        ProductionLedgerContractError(
            "contract.promotion_status",
            "changed",
        ),
    )
    for (key, expected) in (
            ("target_country", "USA"),
            ("target_reference_period", "CALENDAR_YEAR_2024"),
            ("target_frequency", "ANNUAL"),
            ("target_time_basis", "CALENDAR_YEAR_ACCOUNTING_FLOW"),
            ("target_stock_flow_class", "FLOW"),
            ("target_currency", "USD"),
            ("target_unit", "MILLIONS_CURRENT_DOLLARS"),
            ("target_price_basis", "PRODUCERS_PRICES"),
            (
                "target_axis",
                "BEA_AFTER_REDEFINITIONS_68_CORE_PLUS_EXPLICIT_USED_OTHER_CLOSURE",
            ),
        )
        required_string(raw, key, "contract") == expected ||
            throw(
            ProductionLedgerContractError(
                "contract.$key",
                "changed",
            ),
        )
    end
    required_strings(raw, "production_cell_schema_fields", "contract") ==
        CELL_SCHEMA_FIELDS ||
        throw(
        ProductionLedgerContractError(
            "contract.production_cell_schema_fields",
            "changed",
        ),
    )
    required_strings(raw, "production_control_schema_fields", "contract") ==
        CONTROL_SCHEMA_FIELDS ||
        throw(
        ProductionLedgerContractError(
            "contract.production_control_schema_fields",
            "changed",
        ),
    )
    for key in (
            "forecast_origin_admissible",
            "promotion_ready",
            "model_state_write",
        )
        required_bool(raw, key, "contract") &&
            throw(
            ProductionLedgerContractError(
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
            "adjustment_record_count",
        )
        required_int(raw, key, "contract") == 0 ||
            throw(
            ProductionLedgerContractError(
                "contract.$key",
                "must remain zero",
            ),
        )
    end
    required_string(raw, "accounting_gate_effect", "contract") == "NONE" ||
        throw(
        ProductionLedgerContractError(
            "contract.accounting_gate_effect",
            "must remain NONE",
        ),
    )
    required_string(raw, "forecast_score_effect", "contract") == "NONE" ||
        throw(
        ProductionLedgerContractError(
            "contract.forecast_score_effect",
            "must remain NONE",
        ),
    )

    implementation = raw["implementation"]
    implementation isa AbstractDict ||
        throw(
        ProductionLedgerContractError(
            "contract.implementation",
            "must be a table",
        ),
    )
    exact_keys(implementation, IMPLEMENTATION_KEYS, "implementation")
    expected_raw = raw["expected"]
    expected_raw isa AbstractDict ||
        throw(
        ProductionLedgerContractError(
            "contract.expected",
            "must be a table",
        ),
    )
    exact_keys(expected_raw, EXPECTED_KEYS, "expected")
    expected = Dict(
        key => required_int(expected_raw, key, "expected")
            for key in sort!(collect(EXPECTED_KEYS))
    )

    normalized_root = rstrip(normpath(repo_root), '/')
    artifacts = Dict{String, ArtifactBinding}()
    artifact_rows = raw["artifact"]
    artifact_rows isa AbstractVector ||
        throw(
        ProductionLedgerContractError(
            "contract.artifact",
            "must be an array of tables",
        ),
    )
    for (index, row) in enumerate(artifact_rows)
        location = "artifact[$index]"
        exact_keys(row, ARTIFACT_KEYS, location)
        artifact_id = required_string(row, "artifact_id", location)
        haskey(artifacts, artifact_id) &&
            throw(
            ProductionLedgerContractError(
                location,
                "duplicate artifact_id",
            ),
        )
        relative_path = required_string(row, "path", location)
        path = contained_path(normalized_root, relative_path, "$location.path")
        isfile(path) ||
            throw(
            ProductionLedgerContractError(
                "$location.path",
                "artifact is missing",
            ),
        )
        islink(path) &&
            throw(
            ProductionLedgerContractError(
                "$location.path",
                "symbolic links are prohibited",
            ),
        )
        expected_hash = required_string(row, "sha256", location)
        is_sha256(expected_hash) ||
            throw(
            ProductionLedgerContractError(
                "$location.sha256",
                "invalid SHA-256",
            ),
        )
        observed_hash = file_sha256(path)
        observed_hash == expected_hash ||
            throw(
            ProductionLedgerContractError(
                "$location.sha256",
                "expected $expected_hash, got $observed_hash",
            ),
        )
        artifacts[artifact_id] = ArtifactBinding(
            artifact_id,
            relative_path,
            path,
            expected_hash,
            required_string(row, "role", location),
        )
    end
    Set(keys(artifacts)) == Set(
        [
            "after_redefinitions_cells",
            "after_redefinitions_manifest",
            "model_core_mapping",
            "sector_mapping",
            "producer_adapter_contract",
            "inventory_evidence_contract",
            "used_other_evidence_contract",
            "valuation_contract",
            "final_use_contract",
            "supply_cells",
            "supply_manifest",
            "methodology_pdf",
            "methodology_receipt",
        ],
    ) ||
        throw(
        ProductionLedgerContractError(
            "contract.artifact",
            "artifact set changed",
        ),
    )

    for (field, artifact_id) in (
            ("source_fixture_sha256", "after_redefinitions_cells"),
            ("source_manifest_sha256", "after_redefinitions_manifest"),
            ("model_mapping_sha256", "model_core_mapping"),
            ("sector_mapping_sha256", "sector_mapping"),
            ("producer_adapter_contract_sha256", "producer_adapter_contract"),
            (
                "inventory_evidence_contract_sha256",
                "inventory_evidence_contract",
            ),
            (
                "used_other_evidence_contract_sha256",
                "used_other_evidence_contract",
            ),
        )
        required_string(raw, field, "contract") ==
            artifacts[artifact_id].sha256 ||
            throw(
            ProductionLedgerContractError(
                "contract.$field",
                "does not match artifact",
            ),
        )
    end
    source_zip_sha256 =
        required_string(raw, "source_zip_sha256", "contract")
    source_metadata_sha256 =
        required_string(raw, "source_metadata_sha256", "contract")
    is_sha256(source_zip_sha256) && is_sha256(source_metadata_sha256) ||
        throw(
        ProductionLedgerContractError(
            "contract.source",
            "source identity is invalid",
        ),
    )
    scope_hash = required_string(raw, "problem_scope_hash", "contract")
    startswith(scope_hash, "scope1:") ||
        throw(
        ProductionLedgerContractError(
            "contract.problem_scope_hash",
            "invalid scope hash",
        ),
    )
    length(scope_hash) == 71 ||
        throw(
        ProductionLedgerContractError(
            "contract.problem_scope_hash",
            "must contain a SHA-256 digest",
        ),
    )
    scope_hash == declared_scope_hash(raw) ||
        throw(
        ProductionLedgerContractError(
            "contract.problem_scope_hash",
            "does not bind the declared semantic scope",
        ),
    )
    module_path =
        required_string(implementation, "module_path", "implementation")
    runner_path =
        required_string(implementation, "runner_path", "implementation")
    module_absolute =
        contained_path(normalized_root, module_path, "implementation.module_path")
    runner_absolute =
        contained_path(normalized_root, runner_path, "implementation.runner_path")
    isfile(module_absolute) && !islink(module_absolute) ||
        throw(
        ProductionLedgerContractError(
            "implementation.module_path",
            "must be a regular non-symlink file",
        ),
    )
    isfile(runner_absolute) && !islink(runner_absolute) ||
        throw(
        ProductionLedgerContractError(
            "implementation.runner_path",
            "must be a regular non-symlink file",
        ),
    )
    module_hash = required_string(
        implementation,
        "module_normalized_sha256",
        "implementation",
    )
    runner_hash =
        required_string(implementation, "runner_sha256", "implementation")
    normalized_module_sha256(module_absolute) == module_hash ||
        throw(
        ProductionLedgerContractError(
            "implementation.module_normalized_sha256",
            "module bytes changed",
        ),
    )
    file_sha256(runner_absolute) == runner_hash ||
        throw(
        ProductionLedgerContractError(
            "implementation.runner_sha256",
            "runner bytes changed",
        ),
    )

    return ProductionLedgerContract(
        normpath(contract_path),
        normalized_root,
        contract_hash,
        required_string(raw, "contract_id", "contract"),
        required_string(raw, "classification", "contract"),
        required_string(raw, "artifact_role", "contract"),
        required_string(raw, "promotion_status", "contract"),
        scope_hash,
        artifacts["after_redefinitions_cells"].sha256,
        artifacts["after_redefinitions_manifest"].sha256,
        source_zip_sha256,
        source_metadata_sha256,
        artifacts["model_core_mapping"].sha256,
        artifacts["sector_mapping"].sha256,
        artifacts["producer_adapter_contract"].sha256,
        artifacts["inventory_evidence_contract"].sha256,
        artifacts["used_other_evidence_contract"].sha256,
        module_path,
        module_hash,
        runner_path,
        runner_hash,
        expected,
        artifacts,
        sort!(required_strings(raw, "promotion_blockers", "contract")),
    )
end

function framed(parts)
    io = IOBuffer()
    for item in parts
        text = String(item)
        bytes = codeunits(text)
        print(io, length(bytes), ':')
        write(io, bytes)
    end
    return take!(io)
end

digest(parts...) = bytes2hex(SHA.sha256(framed(parts)))

function source_state(cell::RawCell)
    if cell.source_cell_kind == "selected_zero_not_shown"
        cell.value == 0.0 ||
            throw(
            ProductionLedgerContractError(
                "source.$(cell.projection_id)",
                "selected-zero leaf is nonzero",
            ),
        )
        return SELECTED_ZERO_STATE
    elseif cell.source_cell_kind == "numeric"
        return cell.value == 0.0 ? EXPLICIT_ZERO_STATE : NUMERIC_STATE
    end
    throw(
        ProductionLedgerContractError(
            "source.$(cell.projection_id)",
            "unsupported source-cell kind",
        ),
    )
end

function integer_token(value::Float64)
    isfinite(value) && isinteger(value) ||
        throw(
        ProductionLedgerContractError(
            "source.value",
            "after-redefinitions value is not a whole million",
        ),
    )
    integer = round(Int, value)
    return string(integer == 0 ? 0 : integer)
end

function raw_source_key(
        cell::RawCell,
        projection::ProjectionData,
    )
    return "csk1:" * digest(
        "beforeit.canonical-source.v1",
        "US_BEA",
        "INDUSTRY_ACCOUNTS_MAKE_USE_IMPORTS_AFTER_REDEFINITIONS",
        projection.source_member,
        "CY$(cell.year)",
        projection.projection_id,
        cell.row_type,
        cell.row_code,
        cell.column_type,
        cell.column_code,
        "MILLIONS_CURRENT_DOLLARS",
        "PRODUCERS_PRICES",
    )
end

function raw_lineage_hash(
        source_key,
        cell::RawCell,
        projection::ProjectionData,
        contract::ProductionLedgerContract,
    )
    return "lin1:" * digest(
        "beforeit.lineage.raw.v1",
        source_key,
        contract.source_zip_sha256,
        projection.source_workbook_sha256,
        contract.source_fixture_sha256,
        projection.projection_sha256,
        string(cell.row_position),
        string(cell.column_position),
        integer_token(cell.value),
        source_state(cell),
    )
end

function source_member(
        cell::RawCell,
        projection::ProjectionData,
        contract::ProductionLedgerContract,
    )
    key = raw_source_key(cell, projection)
    return SourceLineageMember(
        key,
        raw_lineage_hash(key, cell, projection, contract),
        projection.projection_id,
        projection.projection_sha256,
        projection.source_member,
        projection.source_workbook_sha256,
        cell.row_position,
        cell.row_type,
        cell.row_code,
        cell.column_position,
        cell.column_type,
        cell.column_code,
        integer_token(cell.value),
        source_state(cell),
    )
end

function source_member_key(member::SourceLineageMember)
    return "csk1:" * digest(
        "beforeit.canonical-source.v1",
        "US_BEA",
        "INDUSTRY_ACCOUNTS_MAKE_USE_IMPORTS_AFTER_REDEFINITIONS",
        member.source_member,
        "CY2024",
        member.projection_id,
        member.row_type,
        member.row_code,
        member.column_type,
        member.column_code,
        "MILLIONS_CURRENT_DOLLARS",
        "PRODUCERS_PRICES",
    )
end

function source_member_lineage_hash(
        member::SourceLineageMember,
        contract::ProductionLedgerContract,
    )
    return "lin1:" * digest(
        "beforeit.lineage.raw.v1",
        member.canonical_source_key,
        contract.source_zip_sha256,
        member.source_workbook_sha256,
        contract.source_fixture_sha256,
        member.projection_sha256,
        string(member.row_position),
        string(member.column_position),
        member.source_value_token,
        member.source_cell_state,
    )
end

function projection_workbook_hash(manifest, member)
    if member == manifest["producer_use_workbook_member"]
        return String(manifest["producer_use_workbook_sha256"])
    elseif member == manifest["producer_make_workbook_member"]
        return String(manifest["producer_make_workbook_sha256"])
    elseif member == manifest["import_workbook_member"]
        return String(manifest["import_workbook_sha256"])
    end
    throw(
        ProductionLedgerContractError(
            "manifest.projection.source_member",
            "unsupported workbook member",
        ),
    )
end

function load_projections(contract::ProductionLedgerContract)
    manifest_path =
        contract.artifacts["after_redefinitions_manifest"].path
    cells_path = contract.artifacts["after_redefinitions_cells"].path
    manifest = TOML.parsefile(manifest_path)
    manifest["fixture_sha256"] == contract.source_fixture_sha256 ||
        throw(
        ProductionLedgerContractError(
            "manifest.fixture_sha256",
            "changed",
        ),
    )
    manifest["source_zip_sha256"] == contract.source_zip_sha256 ||
        throw(
        ProductionLedgerContractError(
            "manifest.source_zip_sha256",
            "changed",
        ),
    )
    manifest["source_metadata_sha256"] == contract.source_metadata_sha256 ||
        throw(
        ProductionLedgerContractError(
            "manifest.source_metadata_sha256",
            "changed",
        ),
    )
    manifest["source_retrieved_at_utc"] ==
        "2026-08-06T05:03:02.322Z" ||
        throw(
        ProductionLedgerContractError(
            "manifest.source_retrieved_at_utc",
            "changed",
        ),
    )
    metadata = Dict{String, Any}()
    for row in manifest["projection"]
        projection_id = String(row["matrix_id"])
        projection_id in RELEVANT_PROJECTION_IDS || continue
        metadata[projection_id] = row
    end
    Set(keys(metadata)) == RELEVANT_PROJECTION_IDS ||
        throw(
        ProductionLedgerContractError(
            "manifest.projection",
            "required projection set changed",
        ),
    )

    rows_by_projection = Dict(
        projection_id => RawCell[]
            for projection_id in RELEVANT_PROJECTION_IDS
    )
    table = CSV.File(
        cells_path;
        missingstring = nothing,
        types = Dict(
            :matrix_id => String,
            :year => Int,
            :row_position => Int,
            :row_code => String,
            :row_description => String,
            :row_type => String,
            :column_position => Int,
            :column_code => String,
            :column_description => String,
            :column_type => String,
            :value => Float64,
            :source_cell_kind => String,
        ),
    )
    for row in table
        projection_id = String(row.matrix_id)
        projection_id in RELEVANT_PROJECTION_IDS || continue
        push!(
            rows_by_projection[projection_id],
            RawCell(
                projection_id,
                Int(row.year),
                Int(row.row_position),
                String(row.row_code),
                String(row.row_type),
                Int(row.column_position),
                String(row.column_code),
                String(row.column_type),
                Float64(row.value),
                String(row.source_cell_kind),
            ),
        )
    end

    projections = Dict{String, ProjectionData}()
    for projection_id in sort!(collect(RELEVANT_PROJECTION_IDS))
        raw_rows = sort!(
            rows_by_projection[projection_id];
            by = row -> (row.row_position, row.column_position),
        )
        meta = metadata[projection_id]
        expected_count =
            Int(meta["row_count"]) * Int(meta["column_count"])
        length(raw_rows) == expected_count ||
            throw(
            ProductionLedgerContractError(
                "projection.$projection_id",
                "cell count changed",
            ),
        )
        row_codes = Vector{String}(undef, Int(meta["row_count"]))
        column_codes = Vector{String}(undef, Int(meta["column_count"]))
        cells = Dict{Tuple{String, String}, RawCell}()
        for row in raw_rows
            row.year == 2024 ||
                throw(
                ProductionLedgerContractError(
                    "projection.$projection_id.year",
                    "must be 2024",
                ),
            )
            row_codes[row.row_position] = row.row_code
            column_codes[row.column_position] = row.column_code
            key = (row.row_code, row.column_code)
            haskey(cells, key) &&
                throw(
                ProductionLedgerContractError(
                    "projection.$projection_id",
                    "duplicate coordinate",
                ),
            )
            cells[key] = row
        end
        length(unique(row_codes)) == length(row_codes) ||
            throw(
            ProductionLedgerContractError(
                "projection.$projection_id",
                "row codes are not unique",
            ),
        )
        length(unique(column_codes)) == length(column_codes) ||
            throw(
            ProductionLedgerContractError(
                "projection.$projection_id",
                "column codes are not unique",
            ),
        )
        source_member_name = String(meta["source_member"])
        projections[projection_id] = ProjectionData(
            projection_id,
            2024,
            String(meta["row_type"]),
            String(meta["column_type"]),
            source_member_name,
            projection_workbook_hash(manifest, source_member_name),
            String(meta["projection_sha256"]),
            String.(meta["source_ranges"]),
            row_codes,
            column_codes,
            cells,
        )
    end
    return (
        projections = projections,
        manifest = manifest,
        retrieved_at_utc = String(manifest["source_retrieved_at_utc"]),
    )
end

function reverse_mapping(source_codes, mapping, target_codes, location)
    result = Dict(code => String[] for code in target_codes)
    for source_code in source_codes
        haskey(mapping, source_code) ||
            throw(
            ProductionLedgerContractError(
                location,
                "missing source code $source_code",
            ),
        )
        target_code = mapping[source_code]
        haskey(result, target_code) ||
            throw(
            ProductionLedgerContractError(
                location,
                "unknown target code $target_code",
            ),
        )
        push!(result[target_code], source_code)
    end
    for code in target_codes
        isempty(result[code]) &&
            throw(
            ProductionLedgerContractError(
                location,
                "target code $code has no source",
            ),
        )
        sort!(result[code])
    end
    return result
end

identity_reverse(codes) = Dict(code => [code] for code in codes)

function raw_parent_members(
        projection::ProjectionData,
        source_rows,
        source_columns,
        all_members,
    )
    parents = SourceLineageMember[]
    for row_code in source_rows, column_code in source_columns
        key = (projection.projection_id, row_code, column_code)
        haskey(all_members, key) ||
            throw(
            ProductionLedgerContractError(
                "lineage.$(projection.projection_id)",
                "missing raw parent",
            ),
        )
        push!(parents, all_members[key])
    end
    return canonical_parent_members(
        parents,
        "lineage.$(projection.projection_id)",
    )
end

function canonical_parent_members(parents, location)
    ordered = sort!(
        collect(parents);
        by = item -> (item.canonical_source_key, item.lineage_hash),
    )
    isempty(ordered) &&
        throw(
        ProductionLedgerContractError(
            location,
            "parent set is empty",
        ),
    )
    keys = getfield.(ordered, :canonical_source_key)
    length(keys) == length(unique(keys)) ||
        throw(
        ProductionLedgerContractError(
            location,
            "duplicate parent",
        ),
    )
    return ordered
end

function target_lineage(
        owner_id,
        parents,
        transformation_id,
        contract::ProductionLedgerContract,
    )
    ordered_parents =
        canonical_parent_members(parents, "lineage.$owner_id")
    if length(ordered_parents) == 1
        parent = only(ordered_parents)
        return TargetLineage(
            owner_id,
            parent.canonical_source_key,
            parent.lineage_hash,
            "SOURCE_SELECT_IDENTITY",
            [parent.canonical_source_key],
            [parent.lineage_hash],
        )
    end
    parent_keys = getfield.(ordered_parents, :canonical_source_key)
    parent_hashes = getfield.(ordered_parents, :lineage_hash)
    key_parts = String[
        "beforeit.canonical-source.linear.v1",
        transformation_id,
        contract.model_mapping_sha256,
        contract.sector_mapping_sha256,
    ]
    for parent_key in parent_keys
        append!(key_parts, ["1", parent_key])
    end
    canonical_key = "csk1:" * digest(key_parts...)
    lineage_parts = String[
        "beforeit.lineage.linear.v1",
        canonical_key,
        transformation_id,
        contract.model_mapping_sha256,
        contract.sector_mapping_sha256,
    ]
    for (parent_key, parent_hash) in zip(parent_keys, parent_hashes)
        append!(lineage_parts, ["1", parent_key, parent_hash])
    end
    return TargetLineage(
        owner_id,
        canonical_key,
        "lin1:" * digest(lineage_parts...),
        transformation_id,
        parent_keys,
        parent_hashes,
    )
end

account_scope(code) = code in CLOSURE_CODES ? "CLOSURE" : "CORE"

function cell_id(block, row_code, column_code)
    if block == "PRODUCER_INTERMEDIATE_USE"
        return "AR24:$block:$(account_scope(row_code)):$row_code:$column_code"
    elseif block == "PRODUCER_FINAL_USE"
        return "AR24:$block:$(account_scope(row_code)):$row_code:$column_code"
    elseif block == "PRODUCER_VALUE_ADDED"
        return "AR24:$block:$row_code:$column_code"
    elseif block == "PRODUCER_MAKE"
        return "AR24:$block:$row_code:$(account_scope(column_code)):$column_code"
    elseif block == "COMMODITY_OUTPUT"
        return "AR24:$block:$(account_scope(row_code)):$row_code"
    elseif block == "INDUSTRY_OUTPUT"
        return "AR24:$block:$row_code"
    elseif block == "IMPORT_INTERMEDIATE_USE"
        return "AR24:$block:$(account_scope(row_code)):$row_code:$column_code"
    elseif block == "IMPORT_FINAL_USE"
        return "AR24:$block:$(account_scope(row_code)):$row_code:$column_code"
    end
    throw(ArgumentError("unsupported cell block $block"))
end

function target_cell_state(parents)
    states = getfield.(parents, :source_cell_state)
    if all(==(SELECTED_ZERO_STATE), states)
        return SELECTED_ZERO_STATE
    end
    total = sum(parse(Int, parent.source_value_token) for parent in parents)
    return total == 0 ? EXPLICIT_ZERO_STATE : NUMERIC_STATE
end

function target_raw_value(parents, state)
    state == SELECTED_ZERO_STATE && return nothing
    return Float64(
        sum(parse(Int, parent.source_value_token) for parent in parents),
    )
end

function cell_semantics(block, row_code, column_code, raw_value)
    closure_code = row_code in CLOSURE_CODES ?
        row_code : column_code in CLOSURE_CODES ? column_code : nothing
    economic_type = if block == "PRODUCER_INTERMEDIATE_USE"
        closure_code === nothing ?
            "PRODUCER_PRICE_INTERMEDIATE_USE" :
            "$(uppercase(closure_code))_SPECIAL_ACCOUNT_INTERMEDIATE_USE"
    elseif block == "PRODUCER_FINAL_USE"
        base = column_code == "F030" ?
            "INVENTORY_CHANGE" :
            column_code == "F050" ?
            "IMPORT_ACCOUNTING_OFFSET" :
            column_code == "F02R" ?
            "RESIDENTIAL_FIXED_INVESTMENT_FLOW" :
            "PRODUCER_PRICE_FINAL_USE"
        closure_code === nothing ?
            base :
            "$(uppercase(closure_code))_SPECIAL_ACCOUNT_$base"
    elseif block == "PRODUCER_VALUE_ADDED"
        row_code == "V001" ?
            "COMPENSATION_OF_EMPLOYEES" :
            row_code == "V002" ?
            "NET_TAXES_LESS_SUBSIDIES_ON_PRODUCTION_AND_IMPORTS" :
            "GROSS_OPERATING_SURPLUS"
    elseif block == "PRODUCER_MAKE"
        closure_code === nothing ?
            "INDUSTRY_COMMODITY_MAKE" :
            "$(uppercase(closure_code))_SPECIAL_ACCOUNT_SECONDARY_OUTPUT"
    elseif block == "COMMODITY_OUTPUT"
        closure_code === nothing ?
            "COMMODITY_OUTPUT" :
            "$(uppercase(closure_code))_SPECIAL_ACCOUNT_OUTPUT"
    elseif block == "INDUSTRY_OUTPUT"
        "INDUSTRY_OUTPUT"
    elseif block == "IMPORT_INTERMEDIATE_USE"
        closure_code === nothing ?
            "IMPUTED_IMPORT_ALLOCATION_TO_INTERMEDIATE_USE" :
            "$(uppercase(closure_code))_IMPUTED_IMPORT_INTERMEDIATE_ALLOCATION"
    elseif block == "IMPORT_FINAL_USE"
        base = column_code == "F050" ?
            "IMPUTED_IMPORT_F050_ACCOUNTING_OFFSET" :
            "IMPUTED_IMPORT_ALLOCATION_TO_FINAL_USE"
        closure_code === nothing ?
            base :
            "$(uppercase(closure_code))_$base"
    else
        "UNRESOLVED"
    end

    signed_known =
        (block == "PRODUCER_FINAL_USE" && column_code in ("F030", "F050")) ||
        (block == "IMPORT_FINAL_USE" && column_code == "F050") ||
        (block == "PRODUCER_VALUE_ADDED" && row_code in ("V002", "V003")) ||
        closure_code !== nothing
    negative = raw_value !== nothing && raw_value < 0.0
    mechanically_typed_negative =
        negative &&
        (
        (block == "PRODUCER_FINAL_USE" && column_code in ("F030", "F050")) ||
            (block == "IMPORT_FINAL_USE" && column_code == "F050") ||
            (block == "PRODUCER_VALUE_ADDED" && row_code == "V002")
    )
    negative_type = if !negative
        "NOT_APPLICABLE"
    elseif mechanically_typed_negative
        economic_type
    else
        "UNRESOLVED_$economic_type"
    end
    sign_domain = if signed_known
        "SIGNED_FLOW"
    elseif negative
        "UNRESOLVED_BLOCKED"
    else
        "NONNEGATIVE"
    end
    return (; economic_type, negative_type, sign_domain)
end

function source_family(block, row_code, column_code)
    (row_code in CLOSURE_CODES || column_code in CLOSURE_CODES) &&
        return SOURCE_FAMILY_CLOSURE
    startswith(block, "IMPORT_") && return SOURCE_FAMILY_IMPORT
    return SOURCE_FAMILY_CORE
end

function row_namespace(block, code)
    if block in (
            "PRODUCER_INTERMEDIATE_USE",
            "PRODUCER_FINAL_USE",
            "IMPORT_INTERMEDIATE_USE",
            "IMPORT_FINAL_USE",
            "COMMODITY_OUTPUT",
        )
        return code in CLOSURE_CODES ?
            "BEA_IO_2024_CLOSURE_COMMODITY" :
            "BEA_IO_2024_CORE_COMMODITY"
    elseif block in ("PRODUCER_MAKE", "INDUSTRY_OUTPUT")
        return "BEA_IO_2024_MODEL_INDUSTRY"
    elseif block == "PRODUCER_VALUE_ADDED"
        return "BEA_IO_2024_VALUE_ADDED"
    end
    throw(ArgumentError("unsupported row namespace block"))
end

function column_namespace(block, code)
    if block in ("PRODUCER_INTERMEDIATE_USE", "IMPORT_INTERMEDIATE_USE")
        return "BEA_IO_2024_MODEL_INDUSTRY"
    elseif block in ("PRODUCER_FINAL_USE", "IMPORT_FINAL_USE")
        return "BEA_IO_2024_FINAL_USE"
    elseif block == "PRODUCER_VALUE_ADDED"
        return "BEA_IO_2024_MODEL_INDUSTRY"
    elseif block == "PRODUCER_MAKE"
        return code in CLOSURE_CODES ?
            "BEA_IO_2024_CLOSURE_COMMODITY" :
            "BEA_IO_2024_CORE_COMMODITY"
    elseif block in ("COMMODITY_OUTPUT", "INDUSTRY_OUTPUT")
        return "BEA_IO_2024_OUTPUT_MEASURE"
    end
    throw(ArgumentError("unsupported column namespace block"))
end

function valuation_basis(block)
    startswith(block, "IMPORT_") &&
        return "IMPUTED_IMPORT_ALLOCATION_CURRENT_DOLLARS"
    return "PRODUCER_PRICE_SUPPLY_USE_CURRENT_DOLLARS"
end

function add_projection_cells!(
        cells,
        lineages,
        block,
        projection::ProjectionData,
        target_rows,
        target_columns,
        row_sources,
        column_sources,
        all_members,
        contract,
        retrieved_at_utc,
    )
    for row_code in target_rows, column_code in target_columns
        owner_id = cell_id(block, row_code, column_code)
        parents = raw_parent_members(
            projection,
            row_sources[row_code],
            column_sources[column_code],
            all_members,
        )
        lineage = target_lineage(
            owner_id,
            parents,
            "CODE_KEYED_RETAIL_SUM_V1",
            contract,
        )
        state = target_cell_state(parents)
        raw_value = target_raw_value(parents, state)
        semantics =
            cell_semantics(block, row_code, column_code, raw_value)
        transforms = if length(parents) == 1
            ["SOURCE_SELECT_IDENTITY", projection.projection_id]
        else
            [
                "CODE_KEYED_RETAIL_SUM_V1",
                "MODEL_MAPPING_SHA256:$(contract.model_mapping_sha256)",
                "SECTOR_MAPPING_SHA256:$(contract.sector_mapping_sha256)",
                projection.projection_id,
            ]
        end
        push!(
            cells,
            ProductionCellRecord(
                owner_id,
                lineage.canonical_source_key,
                lineage.lineage_hash,
                source_family(block, row_code, column_code),
                contract.source_fixture_sha256,
                projection.projection_sha256,
                RELEASE_PREFIX * contract.source_zip_sha256,
                retrieved_at_utc,
                "CALENDAR_YEAR_2024",
                "ANNUAL",
                "CALENDAR_YEAR_ACCOUNTING_FLOW",
                "FLOW",
                "USA",
                "USD",
                "MILLIONS_CURRENT_DOLLARS",
                "PRODUCERS_PRICES",
                valuation_basis(block),
                row_namespace(block, row_code),
                row_code,
                column_namespace(block, column_code),
                column_code,
                raw_value,
                state,
                semantics.economic_type,
                semantics.negative_type,
                semantics.sign_domain,
                nothing,
                nothing,
                transforms,
                nothing,
                nothing,
                QUARANTINED_SOLVER_ROLE,
                contract.problem_scope_hash,
                nothing,
                "target-lineage:$(lineage.lineage_hash)",
            ),
        )
        push!(lineages, lineage)
    end
    return nothing
end

function artifact_paths(contract)
    return Dict(
        id => binding.path for (id, binding) in contract.artifacts
    )
end

function build_adapter(contract)
    paths = artifact_paths(contract)
    after_directory = dirname(paths["after_redefinitions_cells"])
    supply_directory = dirname(paths["supply_cells"])
    report = build_producer_price_adapter_candidate(
        paths["producer_adapter_contract"];
        after_directory,
        supply_directory,
        model_mapping_path = paths["model_core_mapping"],
        sector_mapping_path = paths["sector_mapping"],
        valuation_contract_path = paths["valuation_contract"],
        final_use_contract_path = paths["final_use_contract"],
        methodology_pdf_path = paths["methodology_pdf"],
        methodology_receipt_path = paths["methodology_receipt"],
    )
    producer_price_adapter_candidate_controls_pass(
        report,
        paths["producer_adapter_contract"];
        after_directory,
        supply_directory,
        model_mapping_path = paths["model_core_mapping"],
        sector_mapping_path = paths["sector_mapping"],
        valuation_contract_path = paths["valuation_contract"],
        final_use_contract_path = paths["final_use_contract"],
        methodology_pdf_path = paths["methodology_pdf"],
        methodology_receipt_path = paths["methodology_receipt"],
    ) ||
        throw(
        ProductionLedgerContractError(
            "upstream.adapter",
            "source-aware controls do not pass",
        ),
    )
    return report
end

function build_raw_members(projections, contract)
    all_members =
        Dict{Tuple{String, String, String}, SourceLineageMember}()
    for projection_id in sort!(collect(keys(projections)))
        projection = projections[projection_id]
        for cell in values(projection.cells)
            member = source_member(cell, projection, contract)
            key = (projection_id, cell.row_code, cell.column_code)
            haskey(all_members, key) &&
                throw(
                ProductionLedgerContractError(
                    "lineage.raw",
                    "duplicate coordinate",
                ),
            )
            all_members[key] = member
        end
    end
    return all_members
end

function expected_matrix(adapter, block)
    if block == "PRODUCER_INTERMEDIATE_USE"
        return (
            vcat(
                adapter.core_intermediate_use.values,
                adapter.closure_intermediate_use.values,
            ),
            vcat(
                adapter.core_intermediate_use.explicit,
                adapter.closure_intermediate_use.explicit,
            ),
        )
    elseif block == "PRODUCER_FINAL_USE"
        return (
            vcat(
                adapter.core_final_use.values,
                adapter.closure_final_use.values,
            ),
            vcat(
                adapter.core_final_use.explicit,
                adapter.closure_final_use.explicit,
            ),
        )
    elseif block == "PRODUCER_VALUE_ADDED"
        return (
            adapter.producer_value_added.values,
            adapter.producer_value_added.explicit,
        )
    elseif block == "PRODUCER_MAKE"
        return (
            hcat(
                adapter.producer_make.values,
                adapter.closure_producer_make.values,
            ),
            hcat(
                adapter.producer_make.explicit,
                adapter.closure_producer_make.explicit,
            ),
        )
    elseif block == "COMMODITY_OUTPUT"
        return (
            reshape(
                vcat(
                    adapter.commodity_output.values,
                    adapter.closure_commodity_output.values,
                ),
                :,
                1,
            ),
            reshape(
                vcat(
                    adapter.commodity_output_explicit,
                    adapter.closure_commodity_output_explicit,
                ),
                :,
                1,
            ),
        )
    elseif block == "INDUSTRY_OUTPUT"
        return (
            reshape(adapter.industry_output.values, :, 1),
            reshape(adapter.industry_output_explicit, :, 1),
        )
    elseif block == "IMPORT_INTERMEDIATE_USE"
        return (
            vcat(
                adapter.import_evidence.imputed_intermediate_model.values,
                adapter.import_evidence.imputed_intermediate_closure.values,
            ),
            vcat(
                adapter.import_evidence.imputed_intermediate_model.explicit,
                adapter.import_evidence.imputed_intermediate_closure.explicit,
            ),
        )
    elseif block == "IMPORT_FINAL_USE"
        return (
            vcat(
                adapter.import_evidence.imputed_final_model.values,
                adapter.import_evidence.imputed_final_closure.values,
            ),
            vcat(
                adapter.import_evidence.imputed_final_model.explicit,
                adapter.import_evidence.imputed_final_closure.explicit,
            ),
        )
    end
    throw(ArgumentError("unsupported expected matrix block"))
end

function validate_cells_against_adapter(
        cells,
        adapter,
        target_accounts,
        final_codes,
        va_codes,
    )
    cell_map = Dict(cell.cell_id => cell for cell in cells)
    specs = [
        (
            "PRODUCER_INTERMEDIATE_USE",
            target_accounts,
            adapter.model_codes,
        ),
        ("PRODUCER_FINAL_USE", target_accounts, final_codes),
        ("PRODUCER_VALUE_ADDED", va_codes, adapter.model_codes),
        ("PRODUCER_MAKE", adapter.model_codes, target_accounts),
        ("COMMODITY_OUTPUT", target_accounts, ["T007"]),
        ("INDUSTRY_OUTPUT", adapter.model_codes, ["T017"]),
        ("IMPORT_INTERMEDIATE_USE", target_accounts, adapter.model_codes),
        ("IMPORT_FINAL_USE", target_accounts, final_codes),
    ]
    for (block, rows, columns) in specs
        expected_values, expected_explicit = expected_matrix(adapter, block)
        size(expected_values) == (length(rows), length(columns)) ||
            return false
        for (row_position, row_code) in pairs(rows)
            for (column_position, column_code) in pairs(columns)
                id = cell_id(block, row_code, column_code)
                haskey(cell_map, id) || return false
                cell = cell_map[id]
                expected_value =
                    expected_values[row_position, column_position]
                explicit =
                    expected_explicit[row_position, column_position]
                if explicit
                    cell.raw_value === nothing && return false
                    cell.raw_value == expected_value || return false
                else
                    expected_value == 0.0 || return false
                    cell.raw_value === nothing || return false
                    cell.cell_state == SELECTED_ZERO_STATE || return false
                end
            end
        end
    end
    return true
end

function control_state(parents)
    return target_cell_state(parents)
end

function control_rhs(parents, state)
    return target_raw_value(parents, state)
end

function control_key_and_hash(
        control_id,
        parents,
        transformation_id,
        contract,
    )
    ordered_parents =
        canonical_parent_members(parents, "control-lineage.$control_id")
    parent_keys = getfield.(ordered_parents, :canonical_source_key)
    parent_hashes = getfield.(ordered_parents, :lineage_hash)
    key_parts = String[
        "beforeit.canonical-control.published.v1",
        transformation_id,
        contract.model_mapping_sha256,
        contract.sector_mapping_sha256,
    ]
    for key in parent_keys
        append!(key_parts, ["1", key])
    end
    key = "cck1:" * digest(key_parts...)
    lineage_parts = String[
        "beforeit.control-lineage.published.v1",
        key,
        control_id,
        transformation_id,
    ]
    for (parent_key, parent_hash) in zip(parent_keys, parent_hashes)
        append!(lineage_parts, ["1", parent_key, parent_hash])
    end
    return (
        key,
        "lin1:" * digest(lineage_parts...),
        parent_keys,
        parent_hashes,
    )
end

function add_measured_control!(
        controls,
        lineages,
        control_id,
        term_cell_ids,
        coefficients,
        projection,
        source_rows,
        source_columns,
        all_members,
        transformation_id,
        valuation,
        contract,
        retrieved_at_utc,
    )
    parents = raw_parent_members(
        projection,
        source_rows,
        source_columns,
        all_members,
    )
    state = control_state(parents)
    rhs = control_rhs(parents, state)
    key, lineage_hash, parent_keys, parent_hashes =
        control_key_and_hash(
        control_id,
        parents,
        transformation_id,
        contract,
    )
    push!(
        controls,
        ProductionControlRecord(
            control_id,
            "MEASURED_PUBLISHED_MARGIN",
            term_cell_ids,
            coefficients,
            rhs,
            state,
            "USA",
            "CALENDAR_YEAR_2024",
            "ANNUAL",
            "CALENDAR_YEAR_ACCOUNTING_FLOW",
            "FLOW",
            "USD",
            "MILLIONS_CURRENT_DOLLARS",
            "PRODUCERS_PRICES",
            valuation,
            [contract.source_fixture_sha256],
            [projection.projection_sha256],
            RELEASE_PREFIX * contract.source_zip_sha256,
            retrieved_at_utc,
            key,
            lineage_hash,
            [
                transformation_id,
                projection.projection_id,
                "MODEL_MAPPING_SHA256:$(contract.model_mapping_sha256)",
                "SECTOR_MAPPING_SHA256:$(contract.sector_mapping_sha256)",
            ],
            "SOURCE_WHOLE_MILLION_ROUNDING_UNCERTAINTY_NOT_APPROVED",
            "SHARED_RELEASE_AND_AGGREGATE_DEPENDENCE_UNRESOLVED",
            "NOT_APPROVED_NOT_SOLVER_ADMITTED",
            contract.problem_scope_hash,
            nothing,
            "control-lineage:$lineage_hash",
        ),
    )
    push!(
        lineages,
        ControlLineage(
            control_id,
            key,
            lineage_hash,
            transformation_id,
            parent_keys,
            parent_hashes,
            copy(term_cell_ids),
        ),
    )
    return nothing
end

function identity_control_key_and_hash(
        control_id,
        term_cell_ids,
        coefficients,
        cell_map,
    )
    terms = sort!(
        collect(zip(term_cell_ids, coefficients));
        by = item -> item[1],
    )
    key_parts = String[
        "beforeit.canonical-control.identity.v1",
        control_id,
    ]
    lineage_parts = String[
        "beforeit.control-lineage.identity.v1",
        control_id,
    ]
    for (cell_id_value, coefficient) in terms
        coefficient_token = isinteger(coefficient) ?
            string(round(Int, coefficient)) : string(coefficient)
        append!(key_parts, [coefficient_token, cell_id_value])
        cell = cell_map[cell_id_value]
        append!(
            lineage_parts,
            [
                coefficient_token,
                cell_id_value,
                cell.canonical_source_key,
                cell.lineage_hash,
            ],
        )
    end
    key = "cck1:" * digest(key_parts...)
    return key, "lin1:" * digest(vcat([key], lineage_parts)...)
end

function identity_structural_rank(controls)
    identities = sort!(
        [
            control
                for control in controls
                if control.control_kind == "EXACT_ACCOUNTING_IDENTITY"
        ];
        by = control -> control.control_id,
    )
    isempty(identities) && return 0
    all_cell_ids = sort!(
        unique(
            reduce(
                vcat,
                getfield.(identities, :term_cell_ids);
                init = String[],
            ),
        ),
    )
    cell_index =
        Dict(
        cell_id_value => index for (index, cell_id_value) in
            enumerate(all_cell_ids)
    )
    adjacency = [
        sort!(unique(cell_index[id] for id in control.term_cell_ids))
            for control in identities
    ]
    matched_row = zeros(Int, length(all_cell_ids))

    function augment(row, seen)
        for column in adjacency[row]
            seen[column] && continue
            seen[column] = true
            if matched_row[column] == 0 ||
                    augment(matched_row[column], seen)
                matched_row[column] = row
                return true
            end
        end
        return false
    end

    structural_rank = 0
    for row in eachindex(identities)
        structural_rank += augment(row, falses(length(all_cell_ids)))
    end
    return structural_rank
end

function add_identity_control!(
        controls,
        lineages,
        control_id,
        term_cell_ids,
        coefficients,
        cell_map,
        contract,
        retrieved_at_utc,
    )
    key, lineage_hash = identity_control_key_and_hash(
        control_id,
        term_cell_ids,
        coefficients,
        cell_map,
    )
    projection_hashes = sort!(
        unique(
            cell_map[id].source_projection_sha256
                for id in term_cell_ids
        ),
    )
    push!(
        controls,
        ProductionControlRecord(
            control_id,
            "EXACT_ACCOUNTING_IDENTITY",
            term_cell_ids,
            coefficients,
            0.0,
            DERIVED_ZERO_STATE,
            "USA",
            "CALENDAR_YEAR_2024",
            "ANNUAL",
            "CALENDAR_YEAR_ACCOUNTING_FLOW",
            "FLOW",
            "USD",
            "MILLIONS_CURRENT_DOLLARS",
            "PRODUCERS_PRICES",
            "LATENT_PRODUCER_PRICE_ACCOUNTING_IDENTITY",
            [contract.source_fixture_sha256],
            projection_hashes,
            RELEASE_PREFIX * contract.source_zip_sha256,
            retrieved_at_utc,
            key,
            lineage_hash,
            ["LATENT_ACCOUNTING_IDENTITY_CANDIDATE_V1"],
            "NOT_APPLICABLE_LATENT_IDENTITY_CANDIDATE",
            "CANDIDATE_RANK_VERIFIED_NOT_INDEPENDENTLY_APPROVED",
            "CANDIDATE_UNAPPROVED_NOT_SOLVER_ADMITTED",
            contract.problem_scope_hash,
            nothing,
            "control-lineage:$lineage_hash",
        ),
    )
    push!(
        lineages,
        ControlLineage(
            control_id,
            key,
            lineage_hash,
            "LATENT_ACCOUNTING_IDENTITY_CANDIDATE_V1",
            String[],
            String[],
            copy(term_cell_ids),
        ),
    )
    return nothing
end

function producer_u_ids(account, industries)
    return [
        cell_id("PRODUCER_INTERMEDIATE_USE", account, industry)
            for industry in industries
    ]
end

function producer_f_ids(account, finals)
    return [
        cell_id("PRODUCER_FINAL_USE", account, final)
            for final in finals
    ]
end

function producer_v_column_ids(industries, account)
    return [
        cell_id("PRODUCER_MAKE", industry, account)
            for industry in industries
    ]
end

function producer_v_row_ids(industry, accounts)
    return [
        cell_id("PRODUCER_MAKE", industry, account)
            for account in accounts
    ]
end

function import_u_ids(account, industries)
    return [
        cell_id("IMPORT_INTERMEDIATE_USE", account, industry)
            for industry in industries
    ]
end

function import_f_ids(account, finals)
    return [
        cell_id("IMPORT_FINAL_USE", account, final)
            for final in finals
    ]
end

function build_controls(
        projections,
        all_members,
        cells,
        adapter,
        target_accounts,
        final_codes,
        va_codes,
        commodity_sources,
        industry_sources,
        contract,
        retrieved_at_utc,
    )
    controls = ProductionControlRecord[]
    lineages = ControlLineage[]
    cell_map = Dict(cell.cell_id => cell for cell in cells)

    producer_commodity =
        projections["producer_use_commodity_controls_2024"]
    for account in target_accounts
        source_rows = commodity_sources[account]
        for control_code in ["T001", "T004", "T007"]
            terms = if control_code == "T001"
                producer_u_ids(account, adapter.model_codes)
            elseif control_code == "T004"
                producer_f_ids(account, final_codes)
            else
                vcat(
                    producer_u_ids(account, adapter.model_codes),
                    producer_f_ids(account, final_codes),
                )
            end
            add_measured_control!(
                controls,
                lineages,
                "AR24:CONTROL:PRODUCER_USE_COMMODITY:$account:$control_code",
                terms,
                ones(length(terms)),
                producer_commodity,
                source_rows,
                [control_code],
                all_members,
                "PUBLISHED_PRODUCER_COMMODITY_MARGIN_V1",
                "PRODUCER_PRICE_SUPPLY_USE_CURRENT_DOLLARS",
                contract,
                retrieved_at_utc,
            )
        end
    end

    producer_industry =
        projections["producer_use_industry_controls_2024"]
    for industry in adapter.model_codes
        source_columns = industry_sources[industry]
        for control_code in ["T001", "V004", "T017"]
            terms = if control_code == "T001"
                [
                    cell_id(
                            "PRODUCER_INTERMEDIATE_USE",
                            account,
                            industry,
                        )
                        for account in target_accounts
                ]
            elseif control_code == "V004"
                [
                    cell_id("PRODUCER_VALUE_ADDED", va, industry)
                        for va in va_codes
                ]
            else
                vcat(
                    [
                        cell_id(
                                "PRODUCER_INTERMEDIATE_USE",
                                account,
                                industry,
                            )
                            for account in target_accounts
                    ],
                    [
                        cell_id("PRODUCER_VALUE_ADDED", va, industry)
                            for va in va_codes
                    ],
                )
            end
            add_measured_control!(
                controls,
                lineages,
                "AR24:CONTROL:PRODUCER_USE_INDUSTRY:$industry:$control_code",
                terms,
                ones(length(terms)),
                producer_industry,
                [control_code],
                source_columns,
                all_members,
                "PUBLISHED_PRODUCER_INDUSTRY_MARGIN_V1",
                "PRODUCER_PRICE_SUPPLY_USE_CURRENT_DOLLARS",
                contract,
                retrieved_at_utc,
            )
        end
    end

    grand = projections["producer_use_grand_controls_2024"]
    for control_code in grand.column_codes
        terms = if control_code == "T001"
            [
                cell_id("PRODUCER_INTERMEDIATE_USE", account, industry)
                    for account in target_accounts
                    for industry in adapter.model_codes
            ]
        elseif control_code == "V004"
            [
                cell_id("PRODUCER_VALUE_ADDED", va, industry)
                    for va in va_codes
                    for industry in adapter.model_codes
            ]
        elseif control_code == "T007"
            vcat(
                [
                    cell_id(
                            "PRODUCER_INTERMEDIATE_USE",
                            account,
                            industry,
                        )
                        for account in target_accounts
                        for industry in adapter.model_codes
                ],
                [
                    cell_id("PRODUCER_FINAL_USE", account, final)
                        for account in target_accounts
                        for final in final_codes
                ],
            )
        else
            [
                cell_id("PRODUCER_FINAL_USE", account, control_code)
                    for account in target_accounts
            ]
        end
        add_measured_control!(
            controls,
            lineages,
            "AR24:CONTROL:PRODUCER_USE_GRAND:$control_code",
            terms,
            ones(length(terms)),
            grand,
            ["GrandTotal"],
            [control_code],
            all_members,
            "PUBLISHED_PRODUCER_GRAND_MARGIN_V1",
            "PRODUCER_PRICE_SUPPLY_USE_CURRENT_DOLLARS",
            contract,
            retrieved_at_utc,
        )
    end

    make_grand = projections["producer_make_grand_output_2024"]
    make_terms = [
        cell_id("PRODUCER_MAKE", industry, account)
            for industry in adapter.model_codes
            for account in target_accounts
    ]
    add_measured_control!(
        controls,
        lineages,
        "AR24:CONTROL:PRODUCER_MAKE_GRAND:T017",
        make_terms,
        ones(length(make_terms)),
        make_grand,
        ["GrandTotal"],
        ["T017"],
        all_members,
        "PUBLISHED_PRODUCER_MAKE_GRAND_MARGIN_V1",
        "PRODUCER_PRICE_SUPPLY_USE_CURRENT_DOLLARS",
        contract,
        retrieved_at_utc,
    )

    import_controls = projections["import_commodity_controls_2024"]
    for account in target_accounts
        for control_code in ["T001", "T004"]
            terms = control_code == "T001" ?
                import_u_ids(account, adapter.model_codes) :
                import_f_ids(account, final_codes)
            add_measured_control!(
                controls,
                lineages,
                "AR24:CONTROL:IMPORT_COMMODITY:$account:$control_code",
                terms,
                ones(length(terms)),
                import_controls,
                commodity_sources[account],
                [control_code],
                all_members,
                "PUBLISHED_IMPORT_COMMODITY_MARGIN_V1",
                "IMPUTED_IMPORT_ALLOCATION_CURRENT_DOLLARS",
                contract,
                retrieved_at_utc,
            )
        end
    end

    # Unapproved definitional candidates.
    for account in target_accounts
        use_terms = vcat(
            producer_u_ids(account, adapter.model_codes),
            producer_f_ids(account, final_codes),
            [cell_id("COMMODITY_OUTPUT", account, "T007")],
        )
        use_coefficients =
            vcat(ones(length(use_terms) - 1), [-1.0])
        add_identity_control!(
            controls,
            lineages,
            "AR24:IDENTITY:COMMODITY_USE:$account",
            use_terms,
            use_coefficients,
            cell_map,
            contract,
            retrieved_at_utc,
        )
        make_terms = vcat(
            producer_v_column_ids(adapter.model_codes, account),
            [cell_id("COMMODITY_OUTPUT", account, "T007")],
        )
        make_coefficients =
            vcat(ones(length(make_terms) - 1), [-1.0])
        add_identity_control!(
            controls,
            lineages,
            "AR24:IDENTITY:COMMODITY_MAKE:$account",
            make_terms,
            make_coefficients,
            cell_map,
            contract,
            retrieved_at_utc,
        )
        import_terms = vcat(
            import_u_ids(account, adapter.model_codes),
            import_f_ids(account, final_codes),
        )
        add_identity_control!(
            controls,
            lineages,
            "AR24:IDENTITY:IMPORT_ALLOCATION:$account",
            import_terms,
            ones(length(import_terms)),
            cell_map,
            contract,
            retrieved_at_utc,
        )
    end
    for industry in adapter.model_codes
        use_terms = vcat(
            [
                cell_id(
                        "PRODUCER_INTERMEDIATE_USE",
                        account,
                        industry,
                    )
                    for account in target_accounts
            ],
            [
                cell_id("PRODUCER_VALUE_ADDED", va, industry)
                    for va in va_codes
            ],
            [cell_id("INDUSTRY_OUTPUT", industry, "T017")],
        )
        use_coefficients =
            vcat(ones(length(use_terms) - 1), [-1.0])
        add_identity_control!(
            controls,
            lineages,
            "AR24:IDENTITY:INDUSTRY_USE:$industry",
            use_terms,
            use_coefficients,
            cell_map,
            contract,
            retrieved_at_utc,
        )
        make_terms = vcat(
            producer_v_row_ids(industry, target_accounts),
            [cell_id("INDUSTRY_OUTPUT", industry, "T017")],
        )
        make_coefficients =
            vcat(ones(length(make_terms) - 1), [-1.0])
        add_identity_control!(
            controls,
            lineages,
            "AR24:IDENTITY:INDUSTRY_MAKE:$industry",
            make_terms,
            make_coefficients,
            cell_map,
            contract,
            retrieved_at_utc,
        )
    end

    sort!(controls; by = control -> control.control_id)
    sort!(lineages; by = lineage -> lineage.owner_id)
    return controls, lineages
end

function used_other_owner_id(
        raw::RawCell,
        adapter,
    )
    projection_id = raw.projection_id
    # BEA industry and commodity codes overlap. Ownership therefore follows
    # each projection's authenticated axis types rather than code membership.
    if projection_id == "producer_intermediate_use_2024"
        commodity_target =
            adapter.source_commodity_mapping[raw.row_code]
        industry_target =
            adapter.source_industry_mapping[raw.column_code]
        return (
            "CELL",
            cell_id(
                "PRODUCER_INTERMEDIATE_USE",
                commodity_target,
                industry_target,
            ),
        )
    elseif projection_id == "producer_final_use_2024"
        commodity_target =
            adapter.source_commodity_mapping[raw.row_code]
        return (
            "CELL",
            cell_id(
                "PRODUCER_FINAL_USE",
                commodity_target,
                raw.column_code,
            ),
        )
    elseif projection_id == "producer_use_commodity_controls_2024"
        commodity_target =
            adapter.source_commodity_mapping[raw.row_code]
        return (
            "CONTROL",
            "AR24:CONTROL:PRODUCER_USE_COMMODITY:$commodity_target:$(raw.column_code)",
        )
    elseif projection_id == "producer_make_2024"
        industry_target =
            adapter.source_industry_mapping[raw.row_code]
        commodity_target =
            adapter.source_commodity_mapping[raw.column_code]
        return (
            "CELL",
            cell_id("PRODUCER_MAKE", industry_target, commodity_target),
        )
    elseif projection_id == "producer_make_commodity_output_2024"
        commodity_target =
            adapter.source_commodity_mapping[raw.row_code]
        return (
            "CELL",
            cell_id("COMMODITY_OUTPUT", commodity_target, "T007"),
        )
    elseif projection_id == "import_intermediate_use_2024"
        commodity_target =
            adapter.source_commodity_mapping[raw.row_code]
        industry_target =
            adapter.source_industry_mapping[raw.column_code]
        return (
            "CELL",
            cell_id(
                "IMPORT_INTERMEDIATE_USE",
                commodity_target,
                industry_target,
            ),
        )
    elseif projection_id == "import_final_use_2024"
        commodity_target =
            adapter.source_commodity_mapping[raw.row_code]
        return (
            "CELL",
            cell_id(
                "IMPORT_FINAL_USE",
                commodity_target,
                raw.column_code,
            ),
        )
    elseif projection_id == "import_commodity_controls_2024"
        commodity_target =
            adapter.source_commodity_mapping[raw.row_code]
        return (
            "CONTROL",
            "AR24:CONTROL:IMPORT_COMMODITY:$commodity_target:$(raw.column_code)",
        )
    end
    throw(
        ProductionLedgerContractError(
            "overlay.used_other",
            "unsupported projection $projection_id",
        ),
    )
end

function build_overlays(
        projections,
        adapter,
        target_accounts,
        cells,
        controls,
        all_members,
        contract,
    )
    overlays = SemanticOverlay[]
    cell_map = Dict(cell.cell_id => cell for cell in cells)
    control_map =
        Dict(control.control_id => control for control in controls)

    for account in target_accounts
        owner_id = cell_id("PRODUCER_FINAL_USE", account, "F030")
        record_id = account in CLOSURE_CODES ?
            "f030_closure_$(lowercase(account))" :
            "f030_core_$account"
        push!(
            overlays,
            SemanticOverlay(
                "OVERLAY:F030:$record_id",
                "INVENTORY_EVIDENCE_CONTRACT:$(contract.inventory_evidence_contract_sha256)",
                "CELL",
                owner_id,
                record_id,
                "ANNUAL_INVENTORY_FLOW_VIEW",
                "Target-cell reference only; no copied value or statistical weight.",
            ),
        )
    end

    used_other_projection_ids = [
        "producer_intermediate_use_2024",
        "producer_final_use_2024",
        "producer_use_commodity_controls_2024",
        "producer_make_2024",
        "producer_make_commodity_output_2024",
        "import_intermediate_use_2024",
        "import_final_use_2024",
        "import_commodity_controls_2024",
    ]
    for projection_id in used_other_projection_ids
        projection = projections[projection_id]
        raw_cells = sort!(
            collect(values(projection.cells));
            by = cell -> (cell.row_position, cell.column_position),
        )
        for raw in raw_cells
            (
                raw.row_code in CLOSURE_CODES ||
                    raw.column_code in CLOSURE_CODES
            ) || continue
            owner_kind, owner_id = used_other_owner_id(raw, adapter)
            owner_kind == "CELL" ?
                haskey(cell_map, owner_id) :
                haskey(control_map, owner_id) ||
                throw(
                    ProductionLedgerContractError(
                        "overlay.used_other",
                        "owner is absent",
                    ),
                )
            record_id = "bea_2024_$projection_id" *
                "_r$(lpad(raw.row_position, 3, '0'))" *
                "_c$(lpad(raw.column_position, 3, '0'))"
            push!(
                overlays,
                SemanticOverlay(
                    "OVERLAY:USED_OTHER:$record_id",
                    "USED_OTHER_EVIDENCE_CONTRACT:$(contract.used_other_evidence_contract_sha256)",
                    owner_kind,
                    owner_id,
                    record_id,
                    "USED_OTHER_2024_SOURCE_VIEW",
                    "Source-coordinate annotation only; no component allocation or copied observation.",
                ),
            )
        end
    end
    sort!(overlays; by = overlay -> overlay.overlay_id)
    return overlays
end

function build_relations(controls, contract)
    relations = LineageRelation[]
    for control in controls
        relation_kind = control.control_kind == "EXACT_ACCOUNTING_IDENTITY" ?
            "UNAPPROVED_IDENTITY_CANDIDATE_OF" :
            "PUBLISHED_CONTROL_OF"
        push!(
            relations,
            LineageRelation(
                "RELATION:$(control.control_id)",
                relation_kind,
                [control.control_id],
                copy(control.term_cell_ids),
                control.independence_status,
                0,
                control.provenance,
            ),
        )
    end
    f030_control = "AR24:CONTROL:PRODUCER_USE_GRAND:F030"
    push!(
        relations,
        LineageRelation(
            "RELATION:F030_IO_CONTROL_TO_T10105_2024_SUM",
            "COMMON_ESTIMAND_INDEPENDENCE_UNRESOLVED",
            [f030_control],
            ["INVENTORY_EVIDENCE:T10105:CALENDAR_YEAR_2024_SUM"],
            "DISTINCT_SOURCE_LINEAGE_EQUAL_ESTIMAND_NOT_INDEPENDENCE",
            0,
            "inventory-contract:$(contract.inventory_evidence_contract_sha256)",
        ),
    )
    sort!(relations; by = relation -> relation.relation_id)
    return relations
end

function canonical_cell_row(cell)
    values = Any[getfield(cell, Symbol(field)) for field in CELL_SCHEMA_FIELDS]
    return String[
        value === nothing ?
            "<NULL>" :
            value isa AbstractVector ?
            join(string.(value), "\u001f") : string(value)
            for value in values
    ]
end

function canonical_control_row(control)
    values =
        Any[getfield(control, Symbol(field)) for field in CONTROL_SCHEMA_FIELDS]
    return String[
        value === nothing ?
            "<NULL>" :
            value isa AbstractVector ?
            join(string.(value), "\u001f") : string(value)
            for value in values
    ]
end

function canonical_struct_row(value)
    return String[
        field_value === nothing ?
            "<NULL>" :
            field_value isa AbstractVector ?
            join(string.(field_value), "\u001f") : string(field_value)
            for field_value in (
                getfield(value, field) for field in fieldnames(typeof(value))
            )
    ]
end

function ledger_problem_hash(
        cells,
        controls,
        source_lineage_members,
        target_lineages,
        control_lineages,
        overlays,
        relations,
        scope_hash,
    )
    parts = String["beforeit.production-candidate-ledger.v1", scope_hash]
    push!(parts, "PRODUCTION_CELLS")
    for cell in sort!(copy(cells); by = item -> item.cell_id)
        append!(parts, canonical_cell_row(cell))
    end
    push!(parts, "PRODUCTION_CONTROLS")
    for control in sort!(copy(controls); by = item -> item.control_id)
        append!(parts, canonical_control_row(control))
    end
    push!(parts, "SOURCE_LINEAGE_MEMBERS")
    for member in sort!(
            copy(source_lineage_members);
            by = item -> item.canonical_source_key,
        )
        append!(parts, canonical_struct_row(member))
    end
    push!(parts, "TARGET_LINEAGES")
    for lineage in sort!(
            copy(target_lineages);
            by = item -> item.owner_id,
        )
        append!(parts, canonical_struct_row(lineage))
    end
    push!(parts, "CONTROL_LINEAGES")
    for lineage in sort!(
            copy(control_lineages);
            by = item -> item.owner_id,
        )
        append!(parts, canonical_struct_row(lineage))
    end
    push!(parts, "SEMANTIC_OVERLAYS")
    for overlay in sort!(copy(overlays); by = item -> item.overlay_id)
        append!(parts, canonical_struct_row(overlay))
    end
    push!(parts, "LINEAGE_RELATIONS")
    for relation in sort!(copy(relations); by = item -> item.relation_id)
        append!(parts, canonical_struct_row(relation))
    end
    return "problem1:" * digest(parts...)
end

function build_primary_cells(
        projections,
        all_members,
        adapter,
        contract,
        retrieved_at_utc,
    )
    target_accounts = vcat(adapter.model_codes, adapter.closure_codes)
    final_codes = adapter.final_use_codes
    va_codes = adapter.value_added_codes
    commodity_sources = reverse_mapping(
        projections["producer_intermediate_use_2024"].row_codes,
        adapter.source_commodity_mapping,
        target_accounts,
        "mapping.commodity",
    )
    industry_sources = reverse_mapping(
        projections["producer_intermediate_use_2024"].column_codes,
        adapter.source_industry_mapping,
        adapter.model_codes,
        "mapping.industry",
    )
    final_sources = identity_reverse(final_codes)
    va_sources = identity_reverse(va_codes)
    control_t007 = Dict("T007" => ["T007"])
    control_t017 = Dict("T017" => ["T017"])

    cells = ProductionCellRecord[]
    lineages = TargetLineage[]
    specs = [
        (
            "PRODUCER_INTERMEDIATE_USE",
            "producer_intermediate_use_2024",
            target_accounts,
            adapter.model_codes,
            commodity_sources,
            industry_sources,
        ),
        (
            "PRODUCER_FINAL_USE",
            "producer_final_use_2024",
            target_accounts,
            final_codes,
            commodity_sources,
            final_sources,
        ),
        (
            "PRODUCER_VALUE_ADDED",
            "producer_value_added_2024",
            va_codes,
            adapter.model_codes,
            va_sources,
            industry_sources,
        ),
        (
            "PRODUCER_MAKE",
            "producer_make_2024",
            adapter.model_codes,
            target_accounts,
            industry_sources,
            commodity_sources,
        ),
        (
            "COMMODITY_OUTPUT",
            "producer_make_commodity_output_2024",
            target_accounts,
            ["T007"],
            commodity_sources,
            control_t007,
        ),
        (
            "INDUSTRY_OUTPUT",
            "producer_make_industry_output_2024",
            adapter.model_codes,
            ["T017"],
            industry_sources,
            control_t017,
        ),
        (
            "IMPORT_INTERMEDIATE_USE",
            "import_intermediate_use_2024",
            target_accounts,
            adapter.model_codes,
            commodity_sources,
            industry_sources,
        ),
        (
            "IMPORT_FINAL_USE",
            "import_final_use_2024",
            target_accounts,
            final_codes,
            commodity_sources,
            final_sources,
        ),
    ]
    for (
            block,
            projection_id,
            rows,
            columns,
            row_sources,
            column_sources,
        ) in specs
        add_projection_cells!(
            cells,
            lineages,
            block,
            projections[projection_id],
            rows,
            columns,
            row_sources,
            column_sources,
            all_members,
            contract,
            retrieved_at_utc,
        )
    end
    sort!(cells; by = cell -> cell.cell_id)
    sort!(lineages; by = lineage -> lineage.owner_id)
    return (
        cells,
        lineages,
        target_accounts,
        final_codes,
        va_codes,
        commodity_sources,
        industry_sources,
    )
end

function _build_production_reconciliation_ledger(
        contract::ProductionLedgerContract,
    )
    source = load_projections(contract)
    # The pinned fixture loader independently revalidates the canonical cells,
    # manifest, projection grid, masks, and release metadata.
    load_after_redefinitions_fixture(
        dirname(contract.artifacts["after_redefinitions_cells"].path),
    )
    adapter = build_adapter(contract)
    all_members = build_raw_members(source.projections, contract)
    primary = build_primary_cells(
        source.projections,
        all_members,
        adapter,
        contract,
        source.retrieved_at_utc,
    )
    cells = primary[1]
    target_lineages = primary[2]
    target_accounts = primary[3]
    final_codes = primary[4]
    va_codes = primary[5]
    commodity_sources = primary[6]
    industry_sources = primary[7]

    validate_cells_against_adapter(
        cells,
        adapter,
        target_accounts,
        final_codes,
        va_codes,
    ) ||
        throw(
        ProductionLedgerContractError(
            "cells.adapter_roundtrip",
            "canonical cells do not match the source-aware adapter",
        ),
    )

    controls, control_lineages = build_controls(
        source.projections,
        all_members,
        cells,
        adapter,
        target_accounts,
        final_codes,
        va_codes,
        commodity_sources,
        industry_sources,
        contract,
        source.retrieved_at_utc,
    )
    overlays = build_overlays(
        source.projections,
        adapter,
        target_accounts,
        cells,
        controls,
        all_members,
        contract,
    )
    relations = build_relations(controls, contract)
    source_members = collect(values(all_members))
    sort!(
        source_members;
        by = member -> (
            member.projection_id,
            member.row_position,
            member.column_position,
        ),
    )
    unresolved_negative_ids = sort!(
        [
            cell.cell_id
                for cell in cells
                if cell.raw_value !== nothing &&
                cell.raw_value < 0.0 &&
                startswith(
                    cell.negative_economic_type,
                    "UNRESOLVED_",
                )
        ],
    )
    problem_hash = ledger_problem_hash(
        cells,
        controls,
        source_members,
        target_lineages,
        control_lineages,
        overlays,
        relations,
        contract.problem_scope_hash,
    )
    report = ProductionReconciliationLedger(
        REPORT_SCHEMA,
        contract.source_sha256,
        contract.problem_scope_hash,
        problem_hash,
        cells,
        controls,
        source_members,
        target_lineages,
        control_lineages,
        overlays,
        relations,
        unresolved_negative_ids,
        copy(contract.promotion_blockers),
        true,
        true,
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
    !production_reconciliation_ledger_internal_controls_pass(
        report,
        contract,
    ) &&
        throw(
        ProductionLedgerContractError(
            "report",
            "internal controls do not pass; " *
                "cells=$(length(cells)), " *
                "states=$(count(cell -> cell.cell_state == NUMERIC_STATE, cells))/" *
                "$(count(cell -> cell.cell_state == EXPLICIT_ZERO_STATE, cells))/" *
                "$(count(cell -> cell.cell_state == SELECTED_ZERO_STATE, cells)), " *
                "negatives=$(count(cell -> cell.raw_value !== nothing && cell.raw_value < 0.0, cells)), " *
                "unresolved_negatives=$(length(unresolved_negative_ids)), " *
                "controls=$(length(controls)), " *
                "identities=$(count(control -> control.control_kind == "EXACT_ACCOUNTING_IDENTITY", controls)), " *
                "identity_terms=$(sum(length(control.term_cell_ids) for control in controls if control.control_kind == "EXACT_ACCOUNTING_IDENTITY")), " *
                "margins=$(count(control -> control.control_kind == "MEASURED_PUBLISHED_MARGIN", controls)), " *
                "selected_margins=$(count(control -> control.rhs_state == SELECTED_ZERO_STATE, controls)), " *
                "overlays=$(length(overlays)), relations=$(length(relations))",
        ),
    )
    return report
end

function structurally_equal(lhs, rhs)
    typeof(lhs) === typeof(rhs) || return false
    if lhs isa AbstractArray
        axes(lhs) == axes(rhs) || return false
        return all(
            structurally_equal(lhs[index], rhs[index])
                for index in eachindex(lhs)
        )
    elseif lhs isa AbstractDict
        Set(keys(lhs)) == Set(keys(rhs)) || return false
        return all(
            structurally_equal(lhs[key], rhs[key]) for key in keys(lhs)
        )
    elseif lhs isa Number ||
            lhs isa AbstractString ||
            lhs isa Symbol ||
            lhs isa Bool ||
            lhs === nothing
        return isequal(lhs, rhs)
    elseif isstructtype(typeof(lhs))
        return all(
            structurally_equal(getfield(lhs, field), getfield(rhs, field))
                for field in fieldnames(typeof(lhs))
        )
    end
    return isequal(lhs, rhs)
end

function production_reconciliation_ledger_internal_controls_pass(
        report::ProductionReconciliationLedger,
        contract::ProductionLedgerContract,
    )
    try
        report.schema_version == REPORT_SCHEMA || return false
        report.contract_sha256 == contract.source_sha256 || return false
        report.problem_scope_hash == contract.problem_scope_hash ||
            return false
        collect(String.(fieldnames(ProductionCellRecord))) ==
            CELL_SCHEMA_FIELDS ||
            return false
        collect(String.(fieldnames(ProductionControlRecord))) ==
            CONTROL_SCHEMA_FIELDS ||
            return false
        length(report.cells) ==
            contract.expected["candidate_cell_count"] || return false
        length(report.controls) ==
            contract.expected["candidate_control_count"] || return false
        length(report.source_lineage_members) ==
            contract.expected["source_lineage_member_count"] || return false
        length(report.target_lineages) == length(report.cells) || return false
        length(report.control_lineages) == length(report.controls) ||
            return false
        length(report.overlays) == contract.expected["overlay_count"] ||
            return false
        length(report.relations) ==
            contract.expected["lineage_relation_count"] || return false

        cell_ids = getfield.(report.cells, :cell_id)
        source_keys = getfield.(report.cells, :canonical_source_key)
        lineage_hashes = getfield.(report.cells, :lineage_hash)
        length(unique(cell_ids)) == length(cell_ids) || return false
        length(unique(source_keys)) == length(source_keys) || return false
        length(unique(lineage_hashes)) == length(lineage_hashes) || return false
        issorted(cell_ids) || return false
        cell_map = Dict(cell.cell_id => cell for cell in report.cells)
        lineage_map =
            Dict(lineage.owner_id => lineage for lineage in report.target_lineages)
        Set(keys(lineage_map)) == Set(cell_ids) || return false
        for cell in report.cells
            lineage = lineage_map[cell.cell_id]
            cell.canonical_source_key == lineage.canonical_source_key ||
                return false
            cell.lineage_hash == lineage.lineage_hash || return false
            startswith(cell.canonical_source_key, "csk1:") || return false
            startswith(cell.lineage_hash, "lin1:") || return false
            cell.source_artifact_sha256 == contract.source_fixture_sha256 ||
                return false
            cell.release_id == RELEASE_PREFIX * contract.source_zip_sha256 ||
                return false
            cell.reference_period == "CALENDAR_YEAR_2024" || return false
            cell.frequency == "ANNUAL" || return false
            cell.time_basis == "CALENDAR_YEAR_ACCOUNTING_FLOW" ||
                return false
            cell.stock_flow_class == "FLOW" || return false
            cell.country == "USA" || return false
            cell.currency == "USD" || return false
            cell.unit == "MILLIONS_CURRENT_DOLLARS" || return false
            cell.price_basis == "PRODUCERS_PRICES" || return false
            cell.problem_scope_hash == contract.problem_scope_hash ||
                return false
            cell.solver_role == QUARANTINED_SOLVER_ROLE || return false
            cell.reliability_class_id === nothing || return false
            cell.covariance_group_id === nothing || return false
            cell.structural_zero_evidence_id === nothing || return false
            cell.approval_id === nothing || return false
            if cell.cell_state == SELECTED_ZERO_STATE
                cell.raw_value === nothing || return false
            elseif cell.cell_state == EXPLICIT_ZERO_STATE
                cell.raw_value === nothing && return false
                cell.raw_value == 0.0 || return false
            elseif cell.cell_state == NUMERIC_STATE
                cell.raw_value === nothing && return false
                isfinite(cell.raw_value) && cell.raw_value != 0.0 ||
                    return false
            else
                return false
            end
            if cell.raw_value !== nothing && cell.raw_value < 0.0
                cell.sign_domain == "NONNEGATIVE" && return false
                cell.negative_economic_type == "NOT_APPLICABLE" &&
                    return false
            else
                cell.negative_economic_type == "NOT_APPLICABLE" ||
                    return false
            end
        end
        count(
            cell -> cell.cell_state == NUMERIC_STATE,
            report.cells,
        ) == contract.expected["numeric_nonzero_cell_count"] || return false
        count(
            cell -> cell.cell_state == EXPLICIT_ZERO_STATE,
            report.cells,
        ) == contract.expected["explicit_numeric_zero_cell_count"] ||
            return false
        count(
            cell -> cell.cell_state == SELECTED_ZERO_STATE,
            report.cells,
        ) == contract.expected["selected_zero_not_shown_cell_count"] ||
            return false
        count(
            cell -> cell.raw_value !== nothing && cell.raw_value < 0.0,
            report.cells,
        ) == contract.expected["negative_cell_count"] || return false
        count(
            cell -> cell.source_family_id == SOURCE_FAMILY_CLOSURE,
            report.cells,
        ) == contract.expected["used_other_cell_count"] || return false
        count(
            cell -> !startswith(cell.cell_id, "AR24:IMPORT_"),
            report.cells,
        ) == contract.expected["producer_system_cell_count"] || return false
        count(
            cell -> startswith(cell.cell_id, "AR24:IMPORT_"),
            report.cells,
        ) == contract.expected["import_evidence_cell_count"] || return false
        count(
            cell -> cell.source_family_id != SOURCE_FAMILY_CLOSURE,
            report.cells,
        ) == contract.expected["core_cell_count"] || return false
        length(report.unresolved_negative_cell_ids) == 23 || return false
        all(id -> haskey(cell_map, id), report.unresolved_negative_cell_ids) ||
            return false

        raw_keys =
            getfield.(report.source_lineage_members, :canonical_source_key)
        raw_hashes = getfield.(report.source_lineage_members, :lineage_hash)
        length(unique(raw_keys)) == length(raw_keys) || return false
        length(unique(raw_hashes)) == length(raw_hashes) || return false
        issorted(
            report.source_lineage_members;
            by = member -> (
                member.projection_id,
                member.row_position,
                member.column_position,
            ),
        ) || return false
        for member in report.source_lineage_members
            member.projection_id in RELEVANT_PROJECTION_IDS || return false
            member.row_position > 0 || return false
            member.column_position > 0 || return false
            source_member_key(member) == member.canonical_source_key ||
                return false
            source_member_lineage_hash(member, contract) ==
                member.lineage_hash || return false
            value = tryparse(Int, member.source_value_token)
            value === nothing && return false
            string(value == 0 ? 0 : value) == member.source_value_token ||
                return false
            if member.source_cell_state == SELECTED_ZERO_STATE
                value == 0 || return false
            elseif member.source_cell_state == EXPLICIT_ZERO_STATE
                value == 0 || return false
            elseif member.source_cell_state == NUMERIC_STATE
                value != 0 || return false
            else
                return false
            end
        end
        raw_member_map = Dict(
            member.canonical_source_key => member
                for member in report.source_lineage_members
        )
        issorted(getfield.(report.target_lineages, :owner_id)) ||
            return false
        parent_keys = reduce(
            vcat,
            getfield.(report.target_lineages, :parent_source_keys);
            init = String[],
        )
        length(parent_keys) ==
            contract.expected["target_raw_source_leaf_count"] || return false
        length(unique(parent_keys)) == length(parent_keys) || return false
        issubset(Set(parent_keys), Set(raw_keys)) || return false
        for lineage in report.target_lineages
            issorted(lineage.parent_source_keys) || return false
            length(lineage.parent_source_keys) ==
                length(lineage.parent_lineage_hashes) || return false
            parents = SourceLineageMember[
                raw_member_map[key] for key in lineage.parent_source_keys
            ]
            getfield.(parents, :lineage_hash) ==
                lineage.parent_lineage_hashes || return false
            structurally_equal(
                lineage,
                target_lineage(
                    lineage.owner_id,
                    parents,
                    lineage.transformation_id,
                    contract,
                ),
            ) || return false
        end

        control_ids = getfield.(report.controls, :control_id)
        control_keys = getfield.(report.controls, :canonical_control_key)
        control_hashes = getfield.(report.controls, :lineage_hash)
        length(unique(control_ids)) == length(control_ids) || return false
        length(unique(control_keys)) == length(control_keys) || return false
        length(unique(control_hashes)) == length(control_hashes) || return false
        issorted(control_ids) || return false
        control_map =
            Dict(control.control_id => control for control in report.controls)
        control_lineage_ids =
            getfield.(report.control_lineages, :owner_id)
        length(unique(control_lineage_ids)) ==
            length(control_lineage_ids) || return false
        issorted(control_lineage_ids) || return false
        Set(control_lineage_ids) == Set(control_ids) || return false
        control_lineage_map = Dict(
            lineage.owner_id => lineage
                for lineage in report.control_lineages
        )
        for control in report.controls
            lineage = control_lineage_map[control.control_id]
            lineage.term_cell_ids == control.term_cell_ids || return false
            length(control.term_cell_ids) == length(control.coefficients) ||
                return false
            isempty(control.term_cell_ids) && return false
            length(unique(control.term_cell_ids)) ==
                length(control.term_cell_ids) || return false
            all(id -> haskey(cell_map, id), control.term_cell_ids) ||
                return false
            all(value -> isfinite(value) && value != 0.0, control.coefficients) ||
                return false
            control.country == "USA" || return false
            control.reference_period == "CALENDAR_YEAR_2024" || return false
            control.frequency == "ANNUAL" || return false
            control.time_basis == "CALENDAR_YEAR_ACCOUNTING_FLOW" ||
                return false
            control.stock_flow_class == "FLOW" || return false
            control.currency == "USD" || return false
            control.unit == "MILLIONS_CURRENT_DOLLARS" || return false
            control.price_basis == "PRODUCERS_PRICES" || return false
            control.release_id ==
                RELEASE_PREFIX * contract.source_zip_sha256 || return false
            control.problem_scope_hash == contract.problem_scope_hash ||
                return false
            control.approval_id === nothing || return false
            occursin("NOT_SOLVER_ADMITTED", control.fixed_status) ||
                return false
            if control.control_kind == "MEASURED_PUBLISHED_MARGIN"
                length(lineage.parent_source_keys) ==
                    length(lineage.parent_lineage_hashes) || return false
                issorted(lineage.parent_source_keys) || return false
                parents = SourceLineageMember[
                    raw_member_map[key]
                        for key in lineage.parent_source_keys
                ]
                getfield.(parents, :lineage_hash) ==
                    lineage.parent_lineage_hashes || return false
                expected_control_lineage =
                    control_key_and_hash(
                    control.control_id,
                    parents,
                    lineage.transformation_id,
                    contract,
                )
                control.canonical_control_key ==
                    expected_control_lineage[1] || return false
                control.lineage_hash == expected_control_lineage[2] ||
                    return false
                lineage.canonical_control_key ==
                    expected_control_lineage[1] || return false
                lineage.lineage_hash == expected_control_lineage[2] ||
                    return false
                lineage.parent_source_keys ==
                    expected_control_lineage[3] || return false
                lineage.parent_lineage_hashes ==
                    expected_control_lineage[4] || return false
                if control.rhs_state == SELECTED_ZERO_STATE
                    control.rhs === nothing || return false
                elseif control.rhs_state == EXPLICIT_ZERO_STATE
                    control.rhs == 0.0 || return false
                elseif control.rhs_state == NUMERIC_STATE
                    control.rhs === nothing && return false
                    isfinite(control.rhs) && control.rhs != 0.0 ||
                        return false
                else
                    return false
                end
                control.fixed_status == "NOT_APPROVED_NOT_SOLVER_ADMITTED" ||
                    return false
            elseif control.control_kind == "EXACT_ACCOUNTING_IDENTITY"
                isempty(lineage.parent_source_keys) || return false
                isempty(lineage.parent_lineage_hashes) || return false
                expected_identity =
                    identity_control_key_and_hash(
                    control.control_id,
                    control.term_cell_ids,
                    control.coefficients,
                    cell_map,
                )
                control.canonical_control_key == expected_identity[1] ||
                    return false
                control.lineage_hash == expected_identity[2] ||
                    return false
                lineage.canonical_control_key == expected_identity[1] ||
                    return false
                lineage.lineage_hash == expected_identity[2] ||
                    return false
                control.rhs == 0.0 || return false
                control.rhs_state == DERIVED_ZERO_STATE || return false
                control.fixed_status ==
                    "CANDIDATE_UNAPPROVED_NOT_SOLVER_ADMITTED" ||
                    return false
            else
                return false
            end
        end
        control_parent_keys = reduce(
            vcat,
            (
                lineage.parent_source_keys
                    for lineage in report.control_lineages
                    if !isempty(lineage.parent_source_keys)
            );
            init = String[],
        )
        length(control_parent_keys) ==
            contract.expected["control_raw_source_leaf_count"] ||
            return false
        length(unique(control_parent_keys)) ==
            length(control_parent_keys) || return false
        isempty(intersect(Set(parent_keys), Set(control_parent_keys))) ||
            return false
        union(Set(parent_keys), Set(control_parent_keys)) ==
            Set(raw_keys) || return false
        identities = filter(
            control -> control.control_kind == "EXACT_ACCOUNTING_IDENTITY",
            report.controls,
        )
        margins = filter(
            control -> control.control_kind == "MEASURED_PUBLISHED_MARGIN",
            report.controls,
        )
        length(identities) ==
            contract.expected["candidate_identity_count"] || return false
        sum(length(control.term_cell_ids) for control in identities) ==
            contract.expected["candidate_identity_term_count"] || return false
        identity_structural_rank(identities) ==
            contract.expected["candidate_identity_structural_rank"] ||
            return false
        length(margins) == contract.expected["published_control_count"] ||
            return false
        count(control -> control.rhs !== nothing, margins) ==
            contract.expected["numeric_control_count"] || return false
        count(
            control -> control.rhs_state == SELECTED_ZERO_STATE,
            margins,
        ) == contract.expected["selected_zero_not_shown_control_count"] ||
            return false

        overlay_ids = getfield.(report.overlays, :overlay_id)
        length(unique(overlay_ids)) == length(overlay_ids) || return false
        issorted(overlay_ids) || return false
        f030_overlays = filter(
            overlay -> overlay.annotation_kind == "ANNUAL_INVENTORY_FLOW_VIEW",
            report.overlays,
        )
        used_other_overlays = filter(
            overlay -> overlay.annotation_kind == "USED_OTHER_2024_SOURCE_VIEW",
            report.overlays,
        )
        length(f030_overlays) == contract.expected["f030_overlay_count"] ||
            return false
        length(used_other_overlays) ==
            contract.expected["used_other_overlay_count"] || return false
        length(unique(overlay.owner_id for overlay in report.overlays)) ==
            contract.expected["unique_overlay_owner_count"] || return false
        count(
            overlay ->
            overlay.owner_kind == "CONTROL" &&
                overlay.annotation_kind == "USED_OTHER_2024_SOURCE_VIEW",
            report.overlays,
        ) == contract.expected["used_other_control_count"] || return false
        for overlay in report.overlays
            overlay.owner_kind in ("CELL", "CONTROL") || return false
            (
                overlay.owner_kind == "CELL" ?
                    haskey(cell_map, overlay.owner_id) :
                    haskey(control_map, overlay.owner_id)
            ) || return false
        end
        length(
            intersect(
                Set(overlay.owner_id for overlay in f030_overlays),
                Set(overlay.owner_id for overlay in used_other_overlays),
            ),
        ) == 2 || return false

        relation_ids = getfield.(report.relations, :relation_id)
        length(unique(relation_ids)) == length(relation_ids) || return false
        all(relation -> relation.solver_weight_contribution == 0, report.relations) ||
            return false
        report.problem_hash == ledger_problem_hash(
            report.cells,
            report.controls,
            report.source_lineage_members,
            report.target_lineages,
            report.control_lineages,
            report.overlays,
            report.relations,
            report.problem_scope_hash,
        ) || return false
        report.candidate_materialized || return false
        report.canonical_lineage_deduplicated || return false
        report.solver_invocation_count == 0 || return false
        report.solver_input_cell_count == 0 || return false
        report.solver_input_control_count == 0 || return false
        report.approved_exact_control_count == 0 || return false
        report.approved_structural_zero_count == 0 || return false
        report.adjustment_record_count == 0 || return false
        !report.forecast_origin_admissible || return false
        !report.promotion_ready || return false
        !report.model_state_write || return false
        report.accounting_gate_effect == "NONE" || return false
        report.forecast_score_effect == "NONE" || return false
        report.promotion_blockers == contract.promotion_blockers ||
            return false
    catch
        return false
    end
    return true
end

function production_reconciliation_ledger_source_controls_pass(
        report::ProductionReconciliationLedger,
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    try
        contract = load_contract(contract_path; repo_root)
        expected = _build_production_reconciliation_ledger(contract)
        return structurally_equal(report, expected)
    catch
        return false
    end
end

function production_reconciliation_ledger_controls_pass(
        report::ProductionReconciliationLedger,
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    return production_reconciliation_ledger_source_controls_pass(
        report,
        contract_path;
        repo_root,
    )
end

function build_production_reconciliation_ledger(
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    contract = load_contract(contract_path; repo_root)
    before_hashes = Dict(
        id => file_sha256(binding.path)
            for (id, binding) in contract.artifacts
    )
    report = _build_production_reconciliation_ledger(contract)
    for (id, binding) in contract.artifacts
        file_sha256(binding.path) == before_hashes[id] ||
            throw(
            ProductionLedgerContractError(
                "artifact.$id",
                "changed during construction",
            ),
        )
    end
    production_reconciliation_ledger_controls_pass(
        report,
        contract_path;
        repo_root,
    ) ||
        throw(
        ProductionLedgerContractError(
            "report",
            "source-aware controls do not pass",
        ),
    )
    return report
end

function materialize_production_reconciliation_solver_input(
        report::ProductionReconciliationLedger,
    )
    throw(
        ProductionSolverBlockedError(copy(report.promotion_blockers)),
    )
end

function render_csv_value(value)
    value === nothing && return ""
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
    open(path, "w") do io
        println(io, "schema_version = ", toml_quote(STATUS_SCHEMA))
        println(io, "contract_id = ", toml_quote(contract.contract_id))
        println(io, "contract_sha256 = ", toml_quote(report.contract_sha256))
        println(io, "problem_scope_hash = ", toml_quote(report.problem_scope_hash))
        println(io, "problem_hash = ", toml_quote(report.problem_hash))
        println(io, "classification = ", toml_quote(contract.classification))
        println(io, "candidate_materialized = true")
        println(io, "canonical_lineage_deduplicated = true")
        println(io, "candidate_cell_count = ", length(report.cells))
        println(
            io,
            "source_lineage_member_count = ",
            length(report.source_lineage_members),
        )
        println(
            io,
            "target_raw_source_leaf_count = ",
            sum(
                length(lineage.parent_source_keys)
                    for lineage in report.target_lineages
            ),
        )
        println(
            io,
            "control_raw_source_leaf_count = ",
            sum(
                length(lineage.parent_source_keys)
                    for lineage in report.control_lineages
            ),
        )
        println(
            io,
            "target_lineage_count = ",
            length(report.target_lineages),
        )
        println(io, "candidate_control_count = ", length(report.controls))
        println(
            io,
            "control_lineage_count = ",
            length(report.control_lineages),
        )
        println(
            io,
            "candidate_identity_count = ",
            count(
                control ->
                control.control_kind == "EXACT_ACCOUNTING_IDENTITY",
                report.controls,
            ),
        )
        println(
            io,
            "candidate_identity_structural_rank = ",
            identity_structural_rank(report.controls),
        )
        println(
            io,
            "published_control_count = ",
            count(
                control ->
                control.control_kind == "MEASURED_PUBLISHED_MARGIN",
                report.controls,
            ),
        )
        println(io, "overlay_count = ", length(report.overlays))
        println(
            io,
            "unique_overlay_owner_count = ",
            length(unique(overlay.owner_id for overlay in report.overlays)),
        )
        println(io, "lineage_relation_count = ", length(report.relations))
        println(
            io,
            "selected_zero_not_shown_cell_count = ",
            count(
                cell -> cell.cell_state == SELECTED_ZERO_STATE,
                report.cells,
            ),
        )
        println(
            io,
            "selected_zero_not_shown_control_count = ",
            count(
                control -> control.rhs_state == SELECTED_ZERO_STATE,
                report.controls,
            ),
        )
        println(
            io,
            "unresolved_negative_cell_count = ",
            length(report.unresolved_negative_cell_ids),
        )
        println(io, "solver_invocation_count = 0")
        println(io, "solver_input_cell_count = 0")
        println(io, "solver_input_control_count = 0")
        println(io, "approved_exact_control_count = 0")
        println(io, "approved_structural_zero_count = 0")
        println(io, "adjustment_record_count = 0")
        println(io, "forecast_origin_admissible = false")
        println(io, "promotion_ready = false")
        println(io, "model_state_write = false")
        println(io, "accounting_gate_effect = \"NONE\"")
        println(io, "forecast_score_effect = \"NONE\"")
        println(
            io,
            "promotion_blockers = [",
            join((toml_quote(item) for item in report.promotion_blockers), ", "),
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
        println(io, "problem_scope_hash = ", toml_quote(report.problem_scope_hash))
        println(io, "problem_hash = ", toml_quote(report.problem_hash))
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

function write_production_reconciliation_ledger_report(
        output_directory::AbstractString,
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    contract = load_contract(contract_path; repo_root)
    before_hashes = Dict(
        id => file_sha256(binding.path)
            for (id, binding) in contract.artifacts
    )
    report = _build_production_reconciliation_ledger(contract)
    mkpath(output_directory)
    cell_path = joinpath(output_directory, "production_cells.csv")
    control_path = joinpath(output_directory, "production_controls.csv")
    source_lineage_path =
        joinpath(output_directory, "source_lineage_members.csv")
    target_lineage_path = joinpath(output_directory, "target_lineages.csv")
    control_lineage_path =
        joinpath(output_directory, "control_lineages.csv")
    overlay_path = joinpath(output_directory, "semantic_overlays.csv")
    relation_path = joinpath(output_directory, "lineage_relations.csv")
    status_path =
        joinpath(output_directory, "production_candidate_status.toml")
    manifest_path =
        joinpath(output_directory, "production_candidate_manifest.toml")

    write_csv(
        cell_path,
        CELL_SCHEMA_FIELDS,
        (
            Any[getfield(cell, Symbol(field)) for field in CELL_SCHEMA_FIELDS]
                for cell in report.cells
        ),
    )
    write_csv(
        control_path,
        CONTROL_SCHEMA_FIELDS,
        (
            Any[
                    getfield(control, Symbol(field))
                    for field in CONTROL_SCHEMA_FIELDS
                ]
                for control in report.controls
        ),
    )
    write_csv(
        source_lineage_path,
        String.(fieldnames(SourceLineageMember)),
        (
            Any[getfield(member, field) for field in fieldnames(SourceLineageMember)]
                for member in report.source_lineage_members
        ),
    )
    write_csv(
        target_lineage_path,
        String.(fieldnames(TargetLineage)),
        (
            Any[getfield(lineage, field) for field in fieldnames(TargetLineage)]
                for lineage in report.target_lineages
        ),
    )
    write_csv(
        control_lineage_path,
        String.(fieldnames(ControlLineage)),
        (
            Any[getfield(lineage, field) for field in fieldnames(ControlLineage)]
                for lineage in report.control_lineages
        ),
    )
    write_csv(
        overlay_path,
        String.(fieldnames(SemanticOverlay)),
        (
            Any[getfield(overlay, field) for field in fieldnames(SemanticOverlay)]
                for overlay in report.overlays
        ),
    )
    write_csv(
        relation_path,
        String.(fieldnames(LineageRelation)),
        (
            Any[getfield(relation, field) for field in fieldnames(LineageRelation)]
                for relation in report.relations
        ),
    )
    write_status(status_path, report, contract)

    for (id, binding) in contract.artifacts
        file_sha256(binding.path) == before_hashes[id] ||
            throw(
            ProductionLedgerContractError(
                "artifact.$id",
                "changed during report construction",
            ),
        )
    end
    outputs = [
        (
            role = "PRODUCTION_CELLS",
            path = basename(cell_path),
            sha256 = file_sha256(cell_path),
        ),
        (
            role = "PRODUCTION_CONTROLS",
            path = basename(control_path),
            sha256 = file_sha256(control_path),
        ),
        (
            role = "SOURCE_LINEAGE_MEMBERS",
            path = basename(source_lineage_path),
            sha256 = file_sha256(source_lineage_path),
        ),
        (
            role = "TARGET_LINEAGES",
            path = basename(target_lineage_path),
            sha256 = file_sha256(target_lineage_path),
        ),
        (
            role = "CONTROL_LINEAGES",
            path = basename(control_lineage_path),
            sha256 = file_sha256(control_lineage_path),
        ),
        (
            role = "SEMANTIC_OVERLAYS",
            path = basename(overlay_path),
            sha256 = file_sha256(overlay_path),
        ),
        (
            role = "LINEAGE_RELATIONS",
            path = basename(relation_path),
            sha256 = file_sha256(relation_path),
        ),
        (
            role = "CANDIDATE_STATUS",
            path = basename(status_path),
            sha256 = file_sha256(status_path),
        ),
    ]
    write_manifest(manifest_path, report, contract, outputs)
    return (
        report = report,
        cell_path = cell_path,
        cell_sha256 = file_sha256(cell_path),
        control_path = control_path,
        control_sha256 = file_sha256(control_path),
        source_lineage_path = source_lineage_path,
        source_lineage_sha256 = file_sha256(source_lineage_path),
        target_lineage_path = target_lineage_path,
        target_lineage_sha256 = file_sha256(target_lineage_path),
        control_lineage_path = control_lineage_path,
        control_lineage_sha256 = file_sha256(control_lineage_path),
        overlay_path = overlay_path,
        overlay_sha256 = file_sha256(overlay_path),
        relation_path = relation_path,
        relation_sha256 = file_sha256(relation_path),
        status_path = status_path,
        status_sha256 = file_sha256(status_path),
        manifest_path = manifest_path,
        manifest_sha256 = file_sha256(manifest_path),
    )
end

end
