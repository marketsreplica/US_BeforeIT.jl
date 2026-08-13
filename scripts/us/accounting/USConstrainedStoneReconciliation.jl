module USConstrainedStoneReconciliation

using LinearAlgebra
using SHA
using TOML

export CONTRACT_SCHEMA,
    FIXTURE_SCHEMA,
    ADJUSTMENT_SCHEMA,
    CONTROL_DIAGNOSTIC_SCHEMA,
    BENCHMARK_METRICS_SCHEMA,
    COMPARATOR_SCHEMA,
    REPORT_MANIFEST_SCHEMA,
    APPROVED_CONTRACT_SHA256,
    APPROVED_FIXTURE_SHA256,
    ReconciliationContractError,
    MissingReliabilityClassError,
    MissingCovarianceClassError,
    CovarianceValidationError,
    InfeasibleControlsError,
    SignMutationError,
    StructuralZeroMutationError,
    MixedPriceBasisError,
    CovarianceClass,
    ReliabilityClass,
    ComparatorSpec,
    LiteratureCitation,
    StoneContract,
    LedgerCell,
    LinearControl,
    StoneProblem,
    AdjustmentRecord,
    ControlDiagnostic,
    StoneResult,
    BenchmarkMetrics,
    ComparatorAssessment,
    file_sha256,
    load_stone_contract,
    load_synthetic_benchmark,
    validate_stone_contract,
    validate_stone_problem,
    authenticate_pinned_synthetic_benchmark,
    build_prior_covariance,
    reconcile_stone,
    benchmark_metrics,
    validate_benchmark_qualification,
    assess_ordinary_ras,
    benchmark_comparator_assessments,
    run_synthetic_benchmark,
    write_stone_reconciliation_report

const CONTRACT_SCHEMA =
    "beforeit-us-constrained-stone-reconciliation-contract.v1"
const FIXTURE_SCHEMA = "beforeit-us-stone-synthetic-benchmark.v1"
const ADJUSTMENT_SCHEMA = "beforeit-us-stone-adjustment-ledger.v1"
const CONTROL_DIAGNOSTIC_SCHEMA =
    "beforeit-us-stone-control-diagnostic.v1"
const BENCHMARK_METRICS_SCHEMA =
    "beforeit-us-stone-benchmark-metrics.v1"
const COMPARATOR_SCHEMA =
    "beforeit-us-reconciliation-comparator-status.v1"
const REPORT_MANIFEST_SCHEMA =
    "beforeit-us-stone-reconciliation-report-manifest.v1"

const APPROVED_CONTRACT_SHA256 =
    "70855d3ea351c98410b7266a516d991a389c9ef6ca926c7024634945d53fd01e"
const APPROVED_FIXTURE_SHA256 =
    "f9fd56a5c070fd290936a9e77094da50dde16e6a911b8012ad3b32be439caf82"
const APPROVED_FIXTURE_ID = "stone-signed-ledger-noised-v1"
const APPROVED_FIXTURE_CLASSIFICATION =
    "SYNTHETIC_NON_EVIDENTIARY_RESEARCH_ONLY"
const APPROVED_FIXTURE_VALUE_UNIT = "synthetic_millions_usd"
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "constrained_stone_reconciliation.toml")
const DEFAULT_REPO_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", ".."))

const CONTRACT_KEYS = Set(
    [
        "schema_version",
        "contract_id",
        "method_id",
        "method_version",
        "classification",
        "promotion_status",
        "scientific_scope",
        "estimator",
        "solution",
        "posterior_covariance",
        "ledger_price_basis",
        "reliability_schema_version",
        "covariance_schema_version",
        "comparator_schema_version",
        "rank_relative_tolerance",
        "rank_absolute_tolerance",
        "control_absolute_tolerance",
        "sign_tolerance",
        "covariance_symmetry_tolerance",
        "covariance_positive_definite_tolerance",
        "benchmark_fixture_path",
        "benchmark_fixture_sha256",
        "forecast_origin_admissible",
        "promotion_ready",
        "model_state_write",
        "accounting_gate_effect",
        "expected_benchmark",
        "covariance_class",
        "reliability_class",
        "comparator",
        "citation",
    ],
)
const EXPECTED_BENCHMARK_KEYS = Set(
    [
        "cell_count",
        "adjustable_cell_count",
        "predetermined_cell_count",
        "structural_zero_count",
        "negative_cell_count",
        "control_count",
        "adjustable_constraint_rank",
        "adjustable_control_count",
        "fixed_only_control_count",
        "dependent_adjustable_control_count",
        "high_confidence_adjustment",
        "low_confidence_adjustment",
        "low_to_high_absolute_adjustment_ratio",
        "objective_value",
        "raw_vs_truth_rmse",
        "reconciled_vs_truth_rmse",
        "rmse_improvement",
        "raw_vs_truth_mae",
        "reconciled_vs_truth_mae",
        "mae_improvement",
        "maximum_balanced_control_residual",
        "sign_violation_count",
        "structural_zero_violation_count",
    ],
)
const COVARIANCE_CLASS_KEYS = Set(
    [
        "class_id",
        "version",
        "structure",
        "correlation",
        "group_required",
        "scientific_basis",
    ],
)
const RELIABILITY_CLASS_KEYS = Set(
    [
        "class_id",
        "version",
        "adjustable",
        "prior_standard_uncertainty",
        "covariance_class_id",
        "confidence_rank",
        "scientific_basis",
    ],
)
const COMPARATOR_KEYS = Set(
    [
        "method_id",
        "status",
        "eligible",
        "blockers",
        "citation_ids",
        "scientific_basis",
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
        "access_date",
        "relevance",
    ],
)
const FIXTURE_KEYS = Set(
    [
        "schema_version",
        "fixture_id",
        "classification",
        "description",
        "value_unit",
        "price_basis",
        "noised",
        "masked",
        "production_source",
        "forecast_origin_admissible",
        "model_state_write",
        "cell",
        "control",
    ],
)
const CELL_KEYS = Set(
    [
        "cell_id",
        "row_code",
        "column_code",
        "raw_value",
        "truth_value",
        "reliability_class_id",
        "covariance_group",
        "predetermined",
        "structural_zero",
        "cell_state",
        "sign_policy",
        "negative_economic_type",
        "benchmark_role",
        "price_basis",
        "provenance",
    ],
)
const CONTROL_KEYS = Set(
    [
        "control_id",
        "rhs",
        "cell_ids",
        "coefficients",
        "exact",
        "price_basis",
        "provenance",
    ],
)

abstract type AbstractStoneReconciliationError <: Exception end

struct ReconciliationContractError <: AbstractStoneReconciliationError
    location::String
    detail::String
end

struct MissingReliabilityClassError <: AbstractStoneReconciliationError
    cell_id::String
    reliability_class_id::String
end

struct MissingCovarianceClassError <: AbstractStoneReconciliationError
    owner_id::String
    covariance_class_id::String
end

struct CovarianceValidationError <: AbstractStoneReconciliationError
    detail::String
end

struct InfeasibleControlsError <: AbstractStoneReconciliationError
    maximum_residual::Float64
    tolerance::Float64
    control_ids::Vector{String}
end

struct SignMutationError <: AbstractStoneReconciliationError
    cell_id::String
    raw_value::Float64
    reconciled_value::Float64
end

struct StructuralZeroMutationError <: AbstractStoneReconciliationError
    cell_id::String
    value::Float64
    stage::String
end

struct MixedPriceBasisError <: AbstractStoneReconciliationError
    expected::String
    observed::Vector{String}
end

function Base.showerror(io::IO, error::ReconciliationContractError)
    return print(io, error.location, ": ", error.detail)
end

function Base.showerror(io::IO, error::MissingReliabilityClassError)
    return print(
        io,
        "cell ",
        error.cell_id,
        " has unknown reliability class ",
        error.reliability_class_id,
    )
end

function Base.showerror(io::IO, error::MissingCovarianceClassError)
    return print(
        io,
        error.owner_id,
        " has unknown covariance class ",
        error.covariance_class_id,
    )
end

Base.showerror(io::IO, error::CovarianceValidationError) =
    print(io, "invalid prior covariance: ", error.detail)

function Base.showerror(io::IO, error::InfeasibleControlsError)
    return print(
        io,
        "exact controls are infeasible: maximum residual ",
        error.maximum_residual,
        " exceeds ",
        error.tolerance,
        " for ",
        join(error.control_ids, ","),
    )
end

function Base.showerror(io::IO, error::SignMutationError)
    return print(
        io,
        "reconciliation changes the allowed sign of ",
        error.cell_id,
        " from ",
        error.raw_value,
        " to ",
        error.reconciled_value,
    )
end

function Base.showerror(io::IO, error::StructuralZeroMutationError)
    return print(
        io,
        "structural zero ",
        error.cell_id,
        " is ",
        error.value,
        " at ",
        error.stage,
    )
end

function Base.showerror(io::IO, error::MixedPriceBasisError)
    return print(
        io,
        "ledger requires price basis ",
        error.expected,
        " but observed ",
        join(error.observed, ","),
    )
end

struct CovarianceClass
    class_id::String
    version::String
    structure::String
    correlation::Float64
    group_required::Bool
    scientific_basis::String
end

struct ReliabilityClass
    class_id::String
    version::String
    adjustable::Bool
    prior_standard_uncertainty::Float64
    covariance_class_id::String
    confidence_rank::Int
    scientific_basis::String
end

struct ComparatorSpec
    method_id::String
    status::String
    eligible::Bool
    blockers::Vector{String}
    citation_ids::Vector{String}
    scientific_basis::String
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
    access_date::String
    relevance::String
end

struct StoneContract
    schema_version::String
    contract_id::String
    method_id::String
    method_version::String
    classification::String
    promotion_status::String
    scientific_scope::String
    estimator::String
    solution::String
    posterior_covariance_formula::String
    ledger_price_basis::String
    reliability_schema_version::String
    covariance_schema_version::String
    comparator_schema_version::String
    rank_relative_tolerance::Float64
    rank_absolute_tolerance::Float64
    control_absolute_tolerance::Float64
    sign_tolerance::Float64
    covariance_symmetry_tolerance::Float64
    covariance_positive_definite_tolerance::Float64
    benchmark_fixture_path::String
    benchmark_fixture_sha256::String
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_state_write::Bool
    accounting_gate_effect::String
    expected_benchmark::Dict{String, Any}
    covariance_classes::Dict{String, CovarianceClass}
    reliability_classes::Dict{String, ReliabilityClass}
    comparators::Vector{ComparatorSpec}
    citations::Vector{LiteratureCitation}
    source_sha256::String
end

struct LedgerCell
    cell_id::String
    row_code::String
    column_code::String
    raw_value::Float64
    truth_value::Float64
    reliability_class_id::String
    covariance_group::String
    predetermined::Bool
    structural_zero::Bool
    cell_state::String
    sign_policy::String
    negative_economic_type::String
    benchmark_role::String
    price_basis::String
    provenance::String
end

struct LinearControl
    control_id::String
    rhs::Float64
    cell_ids::Vector{String}
    coefficients::Vector{Float64}
    exact::Bool
    price_basis::String
    provenance::String
end

struct StoneProblem
    schema_version::String
    fixture_id::String
    classification::String
    description::String
    value_unit::String
    price_basis::String
    noised::Bool
    masked::Bool
    production_source::Bool
    forecast_origin_admissible::Bool
    model_state_write::Bool
    cells::Vector{LedgerCell}
    controls::Vector{LinearControl}
    source_sha256::String
end

struct AdjustmentRecord
    schema_version::String
    cell_id::String
    row_code::String
    column_code::String
    raw_value::Float64
    truth_value::Float64
    reconciled_value::Float64
    adjustment::Float64
    absolute_adjustment::Float64
    relative_adjustment::Union{Nothing, Float64}
    prior_standard_uncertainty::Float64
    posterior_standard_uncertainty::Float64
    standardized_adjustment::Float64
    reliability_class_id::String
    covariance_class_id::String
    covariance_group::String
    predetermined::Bool
    structural_zero::Bool
    cell_state::String
    sign_policy::String
    negative_economic_type::String
    price_basis::String
    value_unit::String
    binding_control_ids::Vector{String}
    method_id::String
    method_version::String
    provenance::String
end

struct ControlDiagnostic
    schema_version::String
    control_id::String
    rhs::Float64
    raw_achieved::Float64
    raw_residual::Float64
    reconciled_achieved::Float64
    reconciled_residual::Float64
    exact::Bool
    adjustable_coefficient_norm::Float64
    price_basis::String
    provenance::String
end

struct StoneResult
    fixture_id::String
    method_id::String
    method_version::String
    cell_ids::Vector{String}
    raw_values::Vector{Float64}
    reconciled_values::Vector{Float64}
    prior_covariance::Matrix{Float64}
    posterior_covariance::Matrix{Float64}
    adjustment_records::Vector{AdjustmentRecord}
    control_diagnostics::Vector{ControlDiagnostic}
    adjustable_cell_count::Int
    exact_control_count::Int
    adjustable_constraint_rank::Int
    adjustable_control_count::Int
    fixed_only_control_count::Int
    dependent_adjustable_control_count::Int
    rank_threshold::Float64
    objective_value::Float64
    maximum_raw_control_residual::Float64
    maximum_reconciled_control_residual::Float64
    predetermined_cells_fixed::Bool
    structural_zeros_preserved::Bool
    signs_preserved::Bool
    deterministic_ordering::Bool
    promotion_ready::Bool
    model_state_write::Bool
    accounting_gate_effect::String
end

struct BenchmarkMetrics
    schema_version::String
    fixture_id::String
    raw_root_mean_square_error::Float64
    reconciled_root_mean_square_error::Float64
    root_mean_square_error_improvement::Float64
    raw_mean_absolute_error::Float64
    reconciled_mean_absolute_error::Float64
    mean_absolute_error_improvement::Float64
    raw_covariance_weighted_root_mean_square_error::Float64
    reconciled_covariance_weighted_root_mean_square_error::Float64
    maximum_absolute_adjustment::Float64
    high_confidence_adjustment::Float64
    low_confidence_adjustment::Float64
    low_to_high_absolute_adjustment_ratio::Float64
    lower_confidence_absorbs_more::Bool
    truth_control_maximum_residual::Float64
    raw_control_maximum_residual::Float64
    reconciled_control_maximum_residual::Float64
    sign_violation_count::Int
    structural_zero_violation_count::Int
    predetermined_violation_count::Int
end

struct ComparatorAssessment
    schema_version::String
    method_id::String
    status::String
    eligible::Bool
    blockers::Vector{String}
    citation_ids::Vector{String}
    scientific_basis::String
end

file_sha256(file_path::AbstractString) =
    bytes2hex(SHA.sha256(read(file_path)))

function require_exact_keys(table, expected::Set{String}, location::String)
    observed = Set(String(key) for key in keys(table))
    missing = sort!(collect(setdiff(expected, observed)))
    extra = sort!(collect(setdiff(observed, expected)))
    isempty(missing) && isempty(extra) && return nothing
    detail_parts = String[]
    isempty(missing) ||
        push!(detail_parts, "missing keys " * join(missing, ","))
    isempty(extra) ||
        push!(detail_parts, "unexpected keys " * join(extra, ","))
    throw(ReconciliationContractError(location, join(detail_parts, "; ")))
end

function required_string(table, key::String, location::String)
    value = table[key]
    value isa String ||
        throw(ReconciliationContractError(location * "." * key, "must be a string"))
    return value
end

function required_bool(table, key::String, location::String)
    value = table[key]
    value isa Bool ||
        throw(ReconciliationContractError(location * "." * key, "must be a boolean"))
    return value
end

function required_float(table, key::String, location::String)
    value = table[key]
    value isa Real ||
        throw(ReconciliationContractError(location * "." * key, "must be numeric"))
    result = Float64(value)
    isfinite(result) ||
        throw(ReconciliationContractError(location * "." * key, "must be finite"))
    return result
end

function required_int(table, key::String, location::String)
    value = table[key]
    value isa Integer ||
        throw(ReconciliationContractError(location * "." * key, "must be an integer"))
    return Int(value)
end

function required_string_vector(table, key::String, location::String)
    value = table[key]
    value isa Vector ||
        throw(ReconciliationContractError(location * "." * key, "must be an array"))
    all(item -> item isa String, value) ||
        throw(
        ReconciliationContractError(
            location * "." * key,
            "must contain only strings",
        ),
    )
    return String[String(item) for item in value]
end

function required_float_vector(table, key::String, location::String)
    value = table[key]
    value isa Vector ||
        throw(ReconciliationContractError(location * "." * key, "must be an array"))
    all(item -> item isa Real && isfinite(Float64(item)), value) ||
        throw(
        ReconciliationContractError(
            location * "." * key,
            "must contain only finite numbers",
        ),
    )
    return Float64[Float64(item) for item in value]
end

function unique_dictionary(items, identifier, location)
    result = Dict{String, eltype(items)}()
    for item in items
        item_id = identifier(item)
        haskey(result, item_id) &&
            throw(
            ReconciliationContractError(
                location,
                "duplicate identifier " * item_id,
            ),
        )
        result[item_id] = item
    end
    return result
end

function parse_covariance_classes(raw_items)
    parsed = CovarianceClass[]
    for (index, raw) in enumerate(raw_items)
        location = "covariance_class[$index]"
        require_exact_keys(raw, COVARIANCE_CLASS_KEYS, location)
        push!(
            parsed,
            CovarianceClass(
                required_string(raw, "class_id", location),
                required_string(raw, "version", location),
                required_string(raw, "structure", location),
                required_float(raw, "correlation", location),
                required_bool(raw, "group_required", location),
                required_string(raw, "scientific_basis", location),
            ),
        )
    end
    return unique_dictionary(parsed, item -> item.class_id, "covariance_class")
end

function parse_reliability_classes(raw_items)
    parsed = ReliabilityClass[]
    for (index, raw) in enumerate(raw_items)
        location = "reliability_class[$index]"
        require_exact_keys(raw, RELIABILITY_CLASS_KEYS, location)
        push!(
            parsed,
            ReliabilityClass(
                required_string(raw, "class_id", location),
                required_string(raw, "version", location),
                required_bool(raw, "adjustable", location),
                required_float(raw, "prior_standard_uncertainty", location),
                required_string(raw, "covariance_class_id", location),
                required_int(raw, "confidence_rank", location),
                required_string(raw, "scientific_basis", location),
            ),
        )
    end
    return unique_dictionary(parsed, item -> item.class_id, "reliability_class")
end

function parse_comparators(raw_items)
    parsed = ComparatorSpec[]
    for (index, raw) in enumerate(raw_items)
        location = "comparator[$index]"
        require_exact_keys(raw, COMPARATOR_KEYS, location)
        push!(
            parsed,
            ComparatorSpec(
                required_string(raw, "method_id", location),
                required_string(raw, "status", location),
                required_bool(raw, "eligible", location),
                required_string_vector(raw, "blockers", location),
                required_string_vector(raw, "citation_ids", location),
                required_string(raw, "scientific_basis", location),
            ),
        )
    end
    ids = String[item.method_id for item in parsed]
    length(ids) == length(unique(ids)) ||
        throw(ReconciliationContractError("comparator", "duplicate method_id"))
    return sort!(parsed; by = item -> item.method_id)
end

function parse_citations(raw_items)
    parsed = LiteratureCitation[]
    for (index, raw) in enumerate(raw_items)
        location = "citation[$index]"
        require_exact_keys(raw, CITATION_KEYS, location)
        push!(
            parsed,
            LiteratureCitation(
                required_string(raw, "citation_id", location),
                required_string(raw, "kind", location),
                required_string(raw, "authors", location),
                required_int(raw, "year", location),
                required_string(raw, "title", location),
                required_string(raw, "locator", location),
                required_string(raw, "url", location),
                required_string(raw, "doi", location),
                required_string(raw, "access_date", location),
                required_string(raw, "relevance", location),
            ),
        )
    end
    ids = String[item.citation_id for item in parsed]
    length(ids) == length(unique(ids)) ||
        throw(ReconciliationContractError("citation", "duplicate citation_id"))
    return sort!(parsed; by = item -> item.citation_id)
end

function load_stone_contract(
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
        verify_hash::Bool = true,
    )
    isfile(contract_path) ||
        throw(ReconciliationContractError("contract", "file not found"))
    source_sha256 = file_sha256(contract_path)
    verify_hash && source_sha256 != APPROVED_CONTRACT_SHA256 &&
        throw(
        ReconciliationContractError(
            "contract.sha256",
            "expected $APPROVED_CONTRACT_SHA256, got $source_sha256",
        ),
    )
    raw = TOML.parsefile(contract_path)
    require_exact_keys(raw, CONTRACT_KEYS, "contract")
    expected = raw["expected_benchmark"]
    require_exact_keys(
        expected,
        EXPECTED_BENCHMARK_KEYS,
        "expected_benchmark",
    )
    raw_fixture_path =
        required_string(raw, "benchmark_fixture_path", "contract")
    fixture_path = isabspath(raw_fixture_path) ?
        normpath(raw_fixture_path) :
        normpath(joinpath(repo_root, raw_fixture_path))
    contract = StoneContract(
        required_string(raw, "schema_version", "contract"),
        required_string(raw, "contract_id", "contract"),
        required_string(raw, "method_id", "contract"),
        required_string(raw, "method_version", "contract"),
        required_string(raw, "classification", "contract"),
        required_string(raw, "promotion_status", "contract"),
        required_string(raw, "scientific_scope", "contract"),
        required_string(raw, "estimator", "contract"),
        required_string(raw, "solution", "contract"),
        required_string(raw, "posterior_covariance", "contract"),
        required_string(raw, "ledger_price_basis", "contract"),
        required_string(raw, "reliability_schema_version", "contract"),
        required_string(raw, "covariance_schema_version", "contract"),
        required_string(raw, "comparator_schema_version", "contract"),
        required_float(raw, "rank_relative_tolerance", "contract"),
        required_float(raw, "rank_absolute_tolerance", "contract"),
        required_float(raw, "control_absolute_tolerance", "contract"),
        required_float(raw, "sign_tolerance", "contract"),
        required_float(raw, "covariance_symmetry_tolerance", "contract"),
        required_float(
            raw,
            "covariance_positive_definite_tolerance",
            "contract",
        ),
        fixture_path,
        required_string(raw, "benchmark_fixture_sha256", "contract"),
        required_bool(raw, "forecast_origin_admissible", "contract"),
        required_bool(raw, "promotion_ready", "contract"),
        required_bool(raw, "model_state_write", "contract"),
        required_string(raw, "accounting_gate_effect", "contract"),
        Dict{String, Any}(String(key) => value for (key, value) in expected),
        parse_covariance_classes(raw["covariance_class"]),
        parse_reliability_classes(raw["reliability_class"]),
        parse_comparators(raw["comparator"]),
        parse_citations(raw["citation"]),
        source_sha256,
    )
    validate_stone_contract(contract)
    return contract
end

function validate_stone_contract(contract::StoneContract)
    contract.schema_version == CONTRACT_SCHEMA ||
        throw(
        ReconciliationContractError(
            "contract.schema_version",
            "must equal $CONTRACT_SCHEMA",
        ),
    )
    contract.method_id == "CONSTRAINED_STONE_GLS" ||
        throw(
        ReconciliationContractError(
            "contract.method_id",
            "unexpected method",
        ),
    )
    occursin("RESEARCH_ONLY", contract.classification) ||
        throw(
        ReconciliationContractError(
            "contract.classification",
            "must remain research-only",
        ),
    )
    contract.promotion_status == "NOT_PROMOTED" ||
        throw(
        ReconciliationContractError(
            "contract.promotion_status",
            "must remain NOT_PROMOTED",
        ),
    )
    !contract.forecast_origin_admissible ||
        throw(
        ReconciliationContractError(
            "contract.forecast_origin_admissible",
            "must be false",
        ),
    )
    !contract.promotion_ready ||
        throw(
        ReconciliationContractError(
            "contract.promotion_ready",
            "must be false",
        ),
    )
    !contract.model_state_write ||
        throw(
        ReconciliationContractError(
            "contract.model_state_write",
            "must be false",
        ),
    )
    contract.accounting_gate_effect == "NONE" ||
        throw(
        ReconciliationContractError(
            "contract.accounting_gate_effect",
            "must be NONE",
        ),
    )
    contract.benchmark_fixture_sha256 == APPROVED_FIXTURE_SHA256 ||
        throw(
        ReconciliationContractError(
            "contract.benchmark_fixture_sha256",
            "does not pin the approved synthetic fixture",
        ),
    )
    all(
        value -> isfinite(value) && value > 0,
        [
            contract.rank_relative_tolerance,
            contract.rank_absolute_tolerance,
            contract.control_absolute_tolerance,
            contract.sign_tolerance,
            contract.covariance_symmetry_tolerance,
            contract.covariance_positive_definite_tolerance,
        ],
    ) ||
        throw(
        ReconciliationContractError(
            "contract.tolerances",
            "must all be positive and finite",
        ),
    )
    allowed_covariance_structures =
        Set(["INDEPENDENT", "EQUICORRELATED", "EXACT_FIXED"])
    for covariance_class in values(contract.covariance_classes)
        covariance_class.structure in allowed_covariance_structures ||
            throw(
            ReconciliationContractError(
                "covariance_class." * covariance_class.class_id,
                "unsupported structure " * covariance_class.structure,
            ),
        )
        -1.0 < covariance_class.correlation < 1.0 ||
            throw(
            ReconciliationContractError(
                "covariance_class." * covariance_class.class_id,
                "correlation must be strictly between -1 and 1",
            ),
        )
        covariance_class.structure == "INDEPENDENT" &&
            covariance_class.correlation != 0.0 &&
            throw(
            ReconciliationContractError(
                "covariance_class." * covariance_class.class_id,
                "independent correlation must be zero",
            ),
        )
        covariance_class.structure == "EXACT_FIXED" &&
            covariance_class.correlation != 0.0 &&
            throw(
            ReconciliationContractError(
                "covariance_class." * covariance_class.class_id,
                "fixed correlation must be zero",
            ),
        )
    end
    for reliability_class in values(contract.reliability_classes)
        haskey(
            contract.covariance_classes,
            reliability_class.covariance_class_id,
        ) ||
            throw(
            MissingCovarianceClassError(
                reliability_class.class_id,
                reliability_class.covariance_class_id,
            ),
        )
        reliability_class.confidence_rank >= 0 ||
            throw(
            ReconciliationContractError(
                "reliability_class." * reliability_class.class_id,
                "confidence_rank must be nonnegative",
            ),
        )
        if reliability_class.adjustable
            reliability_class.prior_standard_uncertainty > 0 ||
                throw(
                ReconciliationContractError(
                    "reliability_class." * reliability_class.class_id,
                    "adjustable class must have positive uncertainty",
                ),
            )
            contract.covariance_classes[
                reliability_class.covariance_class_id,
            ].structure != "EXACT_FIXED" ||
                throw(
                ReconciliationContractError(
                    "reliability_class." * reliability_class.class_id,
                    "adjustable class cannot use exact covariance",
                ),
            )
        else
            reliability_class.prior_standard_uncertainty == 0 ||
                throw(
                ReconciliationContractError(
                    "reliability_class." * reliability_class.class_id,
                    "fixed class must have zero uncertainty",
                ),
            )
            contract.covariance_classes[
                reliability_class.covariance_class_id,
            ].structure == "EXACT_FIXED" ||
                throw(
                ReconciliationContractError(
                    "reliability_class." * reliability_class.class_id,
                    "fixed class must use exact covariance",
                ),
            )
        end
    end
    citation_ids = Set(citation.citation_id for citation in contract.citations)
    required_citation_ids = Set(
        [
            "UN_SUT_IOT_2018",
            "STONE_CHAMPERNOWNE_MEADE_1942",
            "BYRON_1978",
            "ROBINSON_CATTANEO_ELSAID_2001",
            "LENZEN_WOOD_GALLEGO_2007",
        ],
    )
    issubset(required_citation_ids, citation_ids) ||
        throw(
        ReconciliationContractError(
            "citation",
            "required primary method citations are missing",
        ),
    )
    comparator_ids = Set(comparator.method_id for comparator in contract.comparators)
    comparator_ids == Set(
        [
            "ORDINARY_RAS",
            "CROSS_ENTROPY_ROBINSON_2001",
            "CORRECTED_GRAS_LENZEN_2007",
        ],
    ) ||
        throw(
        ReconciliationContractError(
            "comparator",
            "must preregister ordinary RAS, cross-entropy, and corrected GRAS",
        ),
    )
    for comparator in contract.comparators
        comparator.status == "NOT_RUN_BLOCKED" ||
            throw(
            ReconciliationContractError(
                "comparator." * comparator.method_id,
                "must remain NOT_RUN_BLOCKED",
            ),
        )
        !comparator.eligible ||
            throw(
            ReconciliationContractError(
                "comparator." * comparator.method_id,
                "must remain ineligible for this benchmark",
            ),
        )
        isempty(comparator.blockers) &&
            throw(
            ReconciliationContractError(
                "comparator." * comparator.method_id,
                "must name at least one blocker",
            ),
        )
        issubset(Set(comparator.citation_ids), citation_ids) ||
            throw(
            ReconciliationContractError(
                "comparator." * comparator.method_id,
                "references an unknown citation",
            ),
        )
    end
    return nothing
end

function parse_cells(raw_items)
    parsed = LedgerCell[]
    for (index, raw) in enumerate(raw_items)
        location = "cell[$index]"
        require_exact_keys(raw, CELL_KEYS, location)
        push!(
            parsed,
            LedgerCell(
                required_string(raw, "cell_id", location),
                required_string(raw, "row_code", location),
                required_string(raw, "column_code", location),
                required_float(raw, "raw_value", location),
                required_float(raw, "truth_value", location),
                required_string(raw, "reliability_class_id", location),
                required_string(raw, "covariance_group", location),
                required_bool(raw, "predetermined", location),
                required_bool(raw, "structural_zero", location),
                required_string(raw, "cell_state", location),
                required_string(raw, "sign_policy", location),
                required_string(raw, "negative_economic_type", location),
                required_string(raw, "benchmark_role", location),
                required_string(raw, "price_basis", location),
                required_string(raw, "provenance", location),
            ),
        )
    end
    return parsed
end

function parse_controls(raw_items)
    parsed = LinearControl[]
    for (index, raw) in enumerate(raw_items)
        location = "control[$index]"
        require_exact_keys(raw, CONTROL_KEYS, location)
        push!(
            parsed,
            LinearControl(
                required_string(raw, "control_id", location),
                required_float(raw, "rhs", location),
                required_string_vector(raw, "cell_ids", location),
                required_float_vector(raw, "coefficients", location),
                required_bool(raw, "exact", location),
                required_string(raw, "price_basis", location),
                required_string(raw, "provenance", location),
            ),
        )
    end
    return parsed
end

function load_synthetic_benchmark(
        contract::StoneContract;
        fixture_path::AbstractString = contract.benchmark_fixture_path,
        verify_hash::Bool = true,
    )
    isfile(fixture_path) ||
        throw(ReconciliationContractError("fixture", "file not found"))
    source_sha256 = file_sha256(fixture_path)
    verify_hash && source_sha256 != contract.benchmark_fixture_sha256 &&
        throw(
        ReconciliationContractError(
            "fixture.sha256",
            "expected $(contract.benchmark_fixture_sha256), got $source_sha256",
        ),
    )
    raw = TOML.parsefile(fixture_path)
    require_exact_keys(raw, FIXTURE_KEYS, "fixture")
    problem = StoneProblem(
        required_string(raw, "schema_version", "fixture"),
        required_string(raw, "fixture_id", "fixture"),
        required_string(raw, "classification", "fixture"),
        required_string(raw, "description", "fixture"),
        required_string(raw, "value_unit", "fixture"),
        required_string(raw, "price_basis", "fixture"),
        required_bool(raw, "noised", "fixture"),
        required_bool(raw, "masked", "fixture"),
        required_bool(raw, "production_source", "fixture"),
        required_bool(raw, "forecast_origin_admissible", "fixture"),
        required_bool(raw, "model_state_write", "fixture"),
        parse_cells(raw["cell"]),
        parse_controls(raw["control"]),
        source_sha256,
    )
    validate_stone_problem(problem, contract)
    return problem
end

function reliability_for(cell::LedgerCell, contract::StoneContract)
    haskey(contract.reliability_classes, cell.reliability_class_id) ||
        throw(
        MissingReliabilityClassError(
            cell.cell_id,
            cell.reliability_class_id,
        ),
    )
    return contract.reliability_classes[cell.reliability_class_id]
end

function validate_price_bases(problem::StoneProblem, contract::StoneContract)
    observed = sort!(
        unique(
            vcat(
                [problem.price_basis],
                String[cell.price_basis for cell in problem.cells],
                String[control.price_basis for control in problem.controls],
            ),
        ),
    )
    observed == [contract.ledger_price_basis] ||
        throw(MixedPriceBasisError(contract.ledger_price_basis, observed))
    return nothing
end

function validate_stone_problem(
        problem::StoneProblem,
        contract::StoneContract,
    )
    problem.schema_version == FIXTURE_SCHEMA ||
        throw(
        ReconciliationContractError(
            "fixture.schema_version",
            "must equal $FIXTURE_SCHEMA",
        ),
    )
    problem.fixture_id == APPROVED_FIXTURE_ID ||
        throw(
        ReconciliationContractError(
            "fixture.fixture_id",
            "must equal $APPROVED_FIXTURE_ID",
        ),
    )
    problem.classification == APPROVED_FIXTURE_CLASSIFICATION ||
        throw(
        ReconciliationContractError(
            "fixture.classification",
            "must equal $APPROVED_FIXTURE_CLASSIFICATION",
        ),
    )
    problem.value_unit == APPROVED_FIXTURE_VALUE_UNIT ||
        throw(
        ReconciliationContractError(
            "fixture.value_unit",
            "must equal $APPROVED_FIXTURE_VALUE_UNIT",
        ),
    )
    problem.source_sha256 == APPROVED_FIXTURE_SHA256 ||
        throw(
        ReconciliationContractError(
            "fixture.source_sha256",
            "must equal the approved fixture SHA-256",
        ),
    )
    problem.noised ||
        throw(
        ReconciliationContractError(
            "fixture.noised",
            "benchmark must retain its frozen noise",
        ),
    )
    !problem.production_source ||
        throw(
        ReconciliationContractError(
            "fixture.production_source",
            "must be false",
        ),
    )
    !problem.forecast_origin_admissible ||
        throw(
        ReconciliationContractError(
            "fixture.forecast_origin_admissible",
            "must be false",
        ),
    )
    !problem.model_state_write ||
        throw(
        ReconciliationContractError(
            "fixture.model_state_write",
            "must be false",
        ),
    )
    isempty(problem.cells) &&
        throw(ReconciliationContractError("fixture.cell", "must not be empty"))
    isempty(problem.controls) &&
        throw(
        ReconciliationContractError(
            "fixture.control",
            "must not be empty",
        ),
    )
    validate_price_bases(problem, contract)

    cell_ids = String[cell.cell_id for cell in problem.cells]
    length(cell_ids) == length(unique(cell_ids)) ||
        throw(ReconciliationContractError("fixture.cell", "duplicate cell_id"))
    allowed_cell_states =
        Set(["MEASURED_NONZERO", "MEASURED_ZERO", "STRUCTURAL_ZERO"])
    allowed_sign_policies =
        Set(["PRESERVE_OBSERVED_SIGN", "ALLOW_SIGN_CHANGE"])
    for cell in problem.cells
        reliability = reliability_for(cell, contract)
        haskey(
            contract.covariance_classes,
            reliability.covariance_class_id,
        ) ||
            throw(
            MissingCovarianceClassError(
                reliability.class_id,
                reliability.covariance_class_id,
            ),
        )
        cell.cell_state in allowed_cell_states ||
            throw(
            ReconciliationContractError(
                "cell." * cell.cell_id * ".cell_state",
                "unsupported state " * cell.cell_state,
            ),
        )
        cell.sign_policy in allowed_sign_policies ||
            throw(
            ReconciliationContractError(
                "cell." * cell.cell_id * ".sign_policy",
                "unsupported policy " * cell.sign_policy,
            ),
        )
        if cell.structural_zero
            abs(cell.raw_value) <= contract.sign_tolerance ||
                throw(
                StructuralZeroMutationError(
                    cell.cell_id,
                    cell.raw_value,
                    "raw input",
                ),
            )
            cell.predetermined ||
                throw(
                ReconciliationContractError(
                    "cell." * cell.cell_id,
                    "structural zero must be predetermined",
                ),
            )
            cell.cell_state == "STRUCTURAL_ZERO" ||
                throw(
                ReconciliationContractError(
                    "cell." * cell.cell_id,
                    "structural zero must retain STRUCTURAL_ZERO state",
                ),
            )
        elseif cell.cell_state == "STRUCTURAL_ZERO"
            throw(
                ReconciliationContractError(
                    "cell." * cell.cell_id,
                    "STRUCTURAL_ZERO state requires structural_zero=true",
                ),
            )
        end
        if cell.predetermined
            !reliability.adjustable ||
                throw(
                ReconciliationContractError(
                    "cell." * cell.cell_id,
                    "predetermined cell must use a fixed reliability class",
                ),
            )
        else
            reliability.adjustable ||
                throw(
                ReconciliationContractError(
                    "cell." * cell.cell_id,
                    "adjustable cell must use an adjustable reliability class",
                ),
            )
        end
        if cell.raw_value < -contract.sign_tolerance
            isempty(cell.negative_economic_type) &&
                throw(
                ReconciliationContractError(
                    "cell." * cell.cell_id * ".negative_economic_type",
                    "negative cell must name its economic type",
                ),
            )
        elseif !isempty(cell.negative_economic_type)
            throw(
                ReconciliationContractError(
                    "cell." * cell.cell_id * ".negative_economic_type",
                    "nonnegative cell cannot carry a negative economic type",
                ),
            )
        end
        covariance_class =
            contract.covariance_classes[reliability.covariance_class_id]
        covariance_class.group_required &&
            isempty(cell.covariance_group) &&
            throw(
            ReconciliationContractError(
                "cell." * cell.cell_id * ".covariance_group",
                "is required by " * covariance_class.class_id,
            ),
        )
    end

    cell_id_set = Set(cell_ids)
    control_ids = String[control.control_id for control in problem.controls]
    length(control_ids) == length(unique(control_ids)) ||
        throw(
        ReconciliationContractError(
            "fixture.control",
            "duplicate control_id",
        ),
    )
    for control in problem.controls
        control.exact ||
            throw(
            ReconciliationContractError(
                "control." * control.control_id,
                "only exact linear controls are supported",
            ),
        )
        length(control.cell_ids) == length(control.coefficients) ||
            throw(
            ReconciliationContractError(
                "control." * control.control_id,
                "cell_ids and coefficients must have equal length",
            ),
        )
        isempty(control.cell_ids) &&
            throw(
            ReconciliationContractError(
                "control." * control.control_id,
                "must contain at least one term",
            ),
        )
        length(control.cell_ids) == length(unique(control.cell_ids)) ||
            throw(
            ReconciliationContractError(
                "control." * control.control_id,
                "contains a duplicate cell term",
            ),
        )
        issubset(Set(control.cell_ids), cell_id_set) ||
            throw(
            ReconciliationContractError(
                "control." * control.control_id,
                "references an unknown cell",
            ),
        )
        any(coefficient -> coefficient != 0.0, control.coefficients) ||
            throw(
            ReconciliationContractError(
                "control." * control.control_id,
                "all coefficients are zero",
            ),
        )
    end
    return nothing
end

function canonical_cells(problem::StoneProblem)
    return sort!(copy(problem.cells); by = cell -> cell.cell_id)
end

function canonical_controls(problem::StoneProblem)
    return sort!(copy(problem.controls); by = control -> control.control_id)
end

function structurally_equal(left, right)
    typeof(left) === typeof(right) || return false
    if left isa AbstractArray
        axes(left) == axes(right) || return false
        return all(
            structurally_equal(left[index], right[index])
                for index in eachindex(left)
        )
    elseif left isa AbstractDict
        Set(keys(left)) == Set(keys(right)) || return false
        return all(
            structurally_equal(left[key], right[key])
                for key in keys(left)
        )
    elseif left isa Tuple
        return length(left) == length(right) && all(
            structurally_equal(left[index], right[index])
                for index in eachindex(left)
        )
    elseif left isa Union{AbstractString, Number, Symbol, Bool, Nothing}
        return isequal(left, right)
    elseif isstructtype(typeof(left))
        return all(
            structurally_equal(
                    getfield(left, field),
                    getfield(right, field),
                )
                for field in fieldnames(typeof(left))
        )
    end
    return isequal(left, right)
end

function canonical_control_identity(control::LinearControl)
    term_order = sortperm(control.cell_ids)
    return (
        control_id = control.control_id,
        rhs = control.rhs,
        cell_ids = control.cell_ids[term_order],
        coefficients = control.coefficients[term_order],
        exact = control.exact,
        price_basis = control.price_basis,
        provenance = control.provenance,
    )
end

function same_pinned_problem(
        problem::StoneProblem,
        pinned::StoneProblem,
    )
    scalar_fields = (
        :schema_version,
        :fixture_id,
        :classification,
        :description,
        :value_unit,
        :price_basis,
        :noised,
        :masked,
        :production_source,
        :forecast_origin_admissible,
        :model_state_write,
        :source_sha256,
    )
    all(
        structurally_equal(
                getfield(problem, field),
                getfield(pinned, field),
            )
            for field in scalar_fields
    ) || return false
    structurally_equal(
        canonical_cells(problem),
        canonical_cells(pinned),
    ) || return false
    problem_controls =
        canonical_control_identity.(canonical_controls(problem))
    pinned_controls =
        canonical_control_identity.(canonical_controls(pinned))
    return structurally_equal(problem_controls, pinned_controls)
end

"""
    authenticate_pinned_synthetic_benchmark(problem, contract)

Fail closed unless `contract` is exactly the authenticated Stone qualification
contract and `problem` is semantically identical to its hash-pinned synthetic
fixture. Cell, control, and control-term ordering are deliberately ignored;
all metadata, values, reliability assignments, controls, and provenance are
otherwise exact. Return freshly loaded trusted objects so the solver never
uses mutable caller-owned vectors or dictionaries after authentication.
"""
function authenticate_pinned_synthetic_benchmark(
        problem::StoneProblem,
        contract::StoneContract,
    )
    contract.source_sha256 == APPROVED_CONTRACT_SHA256 ||
        throw(
        ReconciliationContractError(
            "solver.contract_authentication",
            "contract source SHA-256 is not approved",
        ),
    )
    problem.source_sha256 == APPROVED_FIXTURE_SHA256 ||
        throw(
        ReconciliationContractError(
            "solver.fixture_authentication",
            "problem source SHA-256 is not approved",
        ),
    )
    pinned_contract = load_stone_contract(
        DEFAULT_CONTRACT_PATH;
        repo_root = DEFAULT_REPO_ROOT,
        verify_hash = true,
    )
    structurally_equal(contract, pinned_contract) ||
        throw(
        ReconciliationContractError(
            "solver.contract_authentication",
            "contract semantics differ from the approved contract",
        ),
    )
    pinned_problem = load_synthetic_benchmark(
        pinned_contract;
        fixture_path = pinned_contract.benchmark_fixture_path,
        verify_hash = true,
    )
    same_pinned_problem(problem, pinned_problem) ||
        throw(
        ReconciliationContractError(
            "solver.fixture_authentication",
            "problem semantics differ from the approved synthetic fixture",
        ),
    )
    return (problem = pinned_problem, contract = pinned_contract)
end

function build_prior_covariance(
        cells::Vector{LedgerCell},
        contract::StoneContract,
    )
    covariance = zeros(Float64, length(cells), length(cells))
    reliabilities =
        ReliabilityClass[reliability_for(cell, contract) for cell in cells]
    covariance_classes = CovarianceClass[
        contract.covariance_classes[reliability.covariance_class_id]
            for reliability in reliabilities
    ]
    for index in eachindex(cells)
        reliability = reliabilities[index]
        reliability.adjustable ||
            throw(
            CovarianceValidationError(
                "fixed cell $(cells[index].cell_id) entered adjustable covariance",
            ),
        )
        covariance[index, index] =
            reliability.prior_standard_uncertainty^2
    end
    for left in eachindex(cells)
        for right in (left + 1):length(cells)
            left_class = covariance_classes[left]
            right_class = covariance_classes[right]
            left_class.class_id == right_class.class_id || continue
            left_class.structure == "EQUICORRELATED" || continue
            cells[left].covariance_group == cells[right].covariance_group ||
                continue
            covariance_value =
                left_class.correlation *
                reliabilities[left].prior_standard_uncertainty *
                reliabilities[right].prior_standard_uncertainty
            covariance[left, right] = covariance_value
            covariance[right, left] = covariance_value
        end
    end
    symmetry_error = maximum(abs.(covariance - transpose(covariance)); init = 0.0)
    symmetry_error <= contract.covariance_symmetry_tolerance ||
        throw(
        CovarianceValidationError(
            "symmetry error $symmetry_error exceeds tolerance",
        ),
    )
    isempty(cells) && return covariance
    eigenvalues = eigvals(Symmetric(covariance))
    scale = max(maximum(diag(covariance)), 1.0)
    minimum(eigenvalues) >
        contract.covariance_positive_definite_tolerance * scale ||
        throw(
        CovarianceValidationError(
            "minimum eigenvalue $(minimum(eigenvalues)) is not positive at the configured tolerance",
        ),
    )
    return covariance
end

maxabs(values) = isempty(values) ? 0.0 : maximum(abs.(values))

function matrix_representation(
        cells::Vector{LedgerCell},
        controls::Vector{LinearControl},
    )
    cell_index =
        Dict(cell.cell_id => index for (index, cell) in enumerate(cells))
    coefficients = zeros(Float64, length(controls), length(cells))
    rhs = zeros(Float64, length(controls))
    for (row, control) in enumerate(controls)
        rhs[row] = control.rhs
        for (cell_id, coefficient) in
            zip(control.cell_ids, control.coefficients)
            coefficients[row, cell_index[cell_id]] = coefficient
        end
    end
    return coefficients, rhs
end

function sign_is_preserved(
        raw_value::Float64,
        reconciled_value::Float64,
        sign_policy::String,
        tolerance::Float64,
    )
    sign_policy == "ALLOW_SIGN_CHANGE" && return true
    raw_value > tolerance && return reconciled_value >= -tolerance
    raw_value < -tolerance && return reconciled_value <= tolerance
    return abs(reconciled_value) <= tolerance
end

"""
    reconcile_stone(problem, contract)

Authenticate the exact hash-pinned synthetic qualification fixture and
contract, then solve its equality-constrained Stone/GLS problem. Arbitrary
`StoneProblem` values are rejected even if they copy the approved source hash
and synthetic flags. Predetermined cells and structural zeros are substituted
at their raw values.
For adjustable observations `y`, covariance `Σ`, and reduced exact controls
`A * x = b`, the unique primal estimate is

    x̂ = y + Σ * A' * (A * Σ * A')⁺ * (b - A * y).

The tolerance-ranked Moore–Penrose inverse accepts consistent redundant
controls while exposing their rank. A residual above the exact-control
tolerance is hard infeasibility. Sign policy is a post-estimation admissibility
gate: this checkpoint does not silently turn the equality problem into a
different inequality-constrained estimator.
"""
function reconcile_stone(
        problem::StoneProblem,
        contract::StoneContract,
    )
    validate_stone_contract(contract)
    validate_stone_problem(problem, contract)
    authenticated =
        authenticate_pinned_synthetic_benchmark(problem, contract)
    return _reconcile_stone_fixture_variant(
        authenticated.problem,
        authenticated.contract,
    )
end

# Qualification tests exercise failure modes on deliberately altered versions
# of the frozen fixture through this unexported helper. Production callers must
# use `reconcile_stone`, whose authenticated boundary rejects every alteration.
function _reconcile_stone_fixture_variant(
        problem::StoneProblem,
        contract::StoneContract,
    )
    validate_stone_contract(contract)
    validate_stone_problem(problem, contract)
    cells = canonical_cells(problem)
    controls = canonical_controls(problem)
    coefficients, rhs = matrix_representation(cells, controls)
    raw_values = Float64[cell.raw_value for cell in cells]
    adjustable_indices = Int[]
    fixed_indices = Int[]
    for (index, cell) in enumerate(cells)
        reliability = reliability_for(cell, contract)
        if reliability.adjustable
            push!(adjustable_indices, index)
        else
            push!(fixed_indices, index)
        end
    end
    adjustable_cells = cells[adjustable_indices]
    adjustable_coefficients = coefficients[:, adjustable_indices]
    adjustable_control_mask = Bool[
        any(!iszero, adjustable_coefficients[row, :])
            for row in axes(adjustable_coefficients, 1)
    ]
    adjustable_control_count = count(identity, adjustable_control_mask)
    fixed_only_control_count =
        length(controls) - adjustable_control_count
    prior_adjustable =
        build_prior_covariance(adjustable_cells, contract)
    raw_residuals = coefficients * raw_values - rhs
    discrepancy = -raw_residuals
    gram =
        adjustable_coefficients *
        prior_adjustable *
        transpose(adjustable_coefficients)
    gram_svd = svd(gram)
    maximum_singular_value =
        isempty(gram_svd.S) ? 0.0 : maximum(gram_svd.S)
    rank_threshold = max(
        contract.rank_absolute_tolerance,
        contract.rank_relative_tolerance * maximum_singular_value,
    )
    inverse_singular_values = Float64[
        singular_value > rank_threshold ? inv(singular_value) : 0.0
            for singular_value in gram_svd.S
    ]
    constraint_rank =
        count(singular_value -> singular_value > rank_threshold, gram_svd.S)
    gram_pseudoinverse =
        transpose(gram_svd.Vt) *
        Diagonal(inverse_singular_values) *
        transpose(gram_svd.U)
    adjustable_adjustment =
        prior_adjustable *
        transpose(adjustable_coefficients) *
        gram_pseudoinverse *
        discrepancy
    reconciled_values = copy(raw_values)
    reconciled_values[adjustable_indices] .+= adjustable_adjustment
    reconciled_residuals = coefficients * reconciled_values - rhs
    maximum_reconciled_residual = maxabs(reconciled_residuals)
    if maximum_reconciled_residual > contract.control_absolute_tolerance
        failing = String[
            controls[index].control_id
                for index in eachindex(controls)
                if abs(reconciled_residuals[index]) >
                contract.control_absolute_tolerance
        ]
        throw(
            InfeasibleControlsError(
                maximum_reconciled_residual,
                contract.control_absolute_tolerance,
                failing,
            ),
        )
    end

    for (index, cell) in enumerate(cells)
        if cell.structural_zero &&
                abs(reconciled_values[index]) > contract.sign_tolerance
            throw(
                StructuralZeroMutationError(
                    cell.cell_id,
                    reconciled_values[index],
                    "reconciled output",
                ),
            )
        end
        sign_is_preserved(
            cell.raw_value,
            reconciled_values[index],
            cell.sign_policy,
            contract.sign_tolerance,
        ) ||
            throw(
            SignMutationError(
                cell.cell_id,
                cell.raw_value,
                reconciled_values[index],
            ),
        )
    end

    posterior_adjustable =
        prior_adjustable -
        prior_adjustable *
        transpose(adjustable_coefficients) *
        gram_pseudoinverse *
        adjustable_coefficients *
        prior_adjustable
    posterior_adjustable =
        Matrix(Symmetric((posterior_adjustable + transpose(posterior_adjustable)) / 2))
    for index in axes(posterior_adjustable, 1)
        value = posterior_adjustable[index, index]
        value >= -contract.covariance_symmetry_tolerance ||
            throw(
            CovarianceValidationError(
                "posterior variance for $(adjustable_cells[index].cell_id) is $value",
            ),
        )
        value < 0 && (posterior_adjustable[index, index] = 0.0)
    end
    prior_covariance = zeros(Float64, length(cells), length(cells))
    posterior_covariance = zeros(Float64, length(cells), length(cells))
    prior_covariance[adjustable_indices, adjustable_indices] =
        prior_adjustable
    posterior_covariance[adjustable_indices, adjustable_indices] =
        posterior_adjustable
    objective_value = isempty(adjustable_adjustment) ?
        0.0 :
        0.5 *
        dot(
            adjustable_adjustment,
            prior_adjustable \ adjustable_adjustment,
        )

    adjustment_records = AdjustmentRecord[]
    for (index, cell) in enumerate(cells)
        reliability = reliability_for(cell, contract)
        covariance_class =
            contract.covariance_classes[reliability.covariance_class_id]
        adjustment = reconciled_values[index] - raw_values[index]
        relative_adjustment =
            abs(raw_values[index]) <= contract.sign_tolerance ?
            nothing :
            adjustment / raw_values[index]
        prior_standard_uncertainty =
            sqrt(max(prior_covariance[index, index], 0.0))
        posterior_standard_uncertainty =
            sqrt(max(posterior_covariance[index, index], 0.0))
        standardized_adjustment =
            prior_standard_uncertainty == 0.0 ?
            0.0 :
            adjustment / prior_standard_uncertainty
        binding_control_ids = sort!(
            String[
                controls[row].control_id
                    for row in eachindex(controls)
                    if coefficients[row, index] != 0.0
            ],
        )
        push!(
            adjustment_records,
            AdjustmentRecord(
                ADJUSTMENT_SCHEMA,
                cell.cell_id,
                cell.row_code,
                cell.column_code,
                cell.raw_value,
                cell.truth_value,
                reconciled_values[index],
                adjustment,
                abs(adjustment),
                relative_adjustment,
                prior_standard_uncertainty,
                posterior_standard_uncertainty,
                standardized_adjustment,
                reliability.class_id,
                covariance_class.class_id,
                cell.covariance_group,
                cell.predetermined,
                cell.structural_zero,
                cell.cell_state,
                cell.sign_policy,
                cell.negative_economic_type,
                cell.price_basis,
                problem.value_unit,
                binding_control_ids,
                contract.method_id,
                contract.method_version,
                cell.provenance,
            ),
        )
    end

    control_diagnostics = ControlDiagnostic[]
    raw_achieved = coefficients * raw_values
    reconciled_achieved = coefficients * reconciled_values
    for (row, control) in enumerate(controls)
        push!(
            control_diagnostics,
            ControlDiagnostic(
                CONTROL_DIAGNOSTIC_SCHEMA,
                control.control_id,
                control.rhs,
                raw_achieved[row],
                raw_residuals[row],
                reconciled_achieved[row],
                reconciled_residuals[row],
                control.exact,
                norm(adjustable_coefficients[row, :]),
                control.price_basis,
                control.provenance,
            ),
        )
    end

    return StoneResult(
        problem.fixture_id,
        contract.method_id,
        contract.method_version,
        String[cell.cell_id for cell in cells],
        raw_values,
        reconciled_values,
        prior_covariance,
        posterior_covariance,
        adjustment_records,
        control_diagnostics,
        length(adjustable_indices),
        length(controls),
        constraint_rank,
        adjustable_control_count,
        fixed_only_control_count,
        adjustable_control_count - constraint_rank,
        rank_threshold,
        objective_value,
        maxabs(raw_residuals),
        maximum_reconciled_residual,
        all(
            reconciled_values[index] == raw_values[index]
                for index in fixed_indices
        ),
        all(
            !cell.structural_zero ||
                abs(reconciled_values[index]) <= contract.sign_tolerance
                for (index, cell) in enumerate(cells)
        ),
        all(
            sign_is_preserved(
                    cell.raw_value,
                    reconciled_values[index],
                    cell.sign_policy,
                    contract.sign_tolerance,
                )
                for (index, cell) in enumerate(cells)
        ),
        issorted(String[cell.cell_id for cell in cells]) &&
            issorted(String[control.control_id for control in controls]),
        false,
        false,
        "NONE",
    )
end

function covariance_weighted_rmse(
        errors::Vector{Float64},
        covariance::Matrix{Float64},
    )
    isempty(errors) && return 0.0
    value = dot(errors, covariance \ errors) / length(errors)
    return sqrt(max(value, 0.0))
end

function benchmark_metrics(
        problem::StoneProblem,
        result::StoneResult,
        contract::StoneContract,
    )
    cells = canonical_cells(problem)
    truth_values = Float64[cell.truth_value for cell in cells]
    raw_errors = result.raw_values - truth_values
    reconciled_errors = result.reconciled_values - truth_values
    raw_rmse = sqrt(sum(abs2, raw_errors) / length(raw_errors))
    reconciled_rmse =
        sqrt(sum(abs2, reconciled_errors) / length(reconciled_errors))
    raw_mae = sum(abs, raw_errors) / length(raw_errors)
    reconciled_mae =
        sum(abs, reconciled_errors) / length(reconciled_errors)
    adjustable_indices = Int[
        index
            for (index, cell) in enumerate(cells)
            if reliability_for(cell, contract).adjustable
    ]
    adjustable_covariance =
        result.prior_covariance[adjustable_indices, adjustable_indices]
    raw_weighted_rmse = covariance_weighted_rmse(
        raw_errors[adjustable_indices],
        adjustable_covariance,
    )
    reconciled_weighted_rmse = covariance_weighted_rmse(
        reconciled_errors[adjustable_indices],
        adjustable_covariance,
    )
    record_by_role = Dict(
        cells[index].benchmark_role => result.adjustment_records[index]
            for index in eachindex(cells)
    )
    high_adjustment =
        record_by_role["HIGH_CONFIDENCE_ADJUSTMENT"].adjustment
    low_adjustment =
        record_by_role["LOW_CONFIDENCE_ADJUSTMENT"].adjustment
    adjustment_ratio =
        abs(high_adjustment) <= contract.sign_tolerance ?
        Inf :
        abs(low_adjustment) / abs(high_adjustment)
    controls = canonical_controls(problem)
    coefficients, rhs = matrix_representation(cells, controls)
    truth_residuals = coefficients * truth_values - rhs
    sign_violation_count = count(
        index -> !sign_is_preserved(
            cells[index].raw_value,
            result.reconciled_values[index],
            cells[index].sign_policy,
            contract.sign_tolerance,
        ),
        eachindex(cells),
    )
    structural_zero_violation_count = count(
        index -> cells[index].structural_zero &&
            abs(result.reconciled_values[index]) >
            contract.sign_tolerance,
        eachindex(cells),
    )
    predetermined_violation_count = count(
        index -> cells[index].predetermined &&
            result.reconciled_values[index] !=
            result.raw_values[index],
        eachindex(cells),
    )
    return BenchmarkMetrics(
        BENCHMARK_METRICS_SCHEMA,
        problem.fixture_id,
        raw_rmse,
        reconciled_rmse,
        raw_rmse - reconciled_rmse,
        raw_mae,
        reconciled_mae,
        raw_mae - reconciled_mae,
        raw_weighted_rmse,
        reconciled_weighted_rmse,
        maximum(
            record.absolute_adjustment
                for record in result.adjustment_records
        ),
        high_adjustment,
        low_adjustment,
        adjustment_ratio,
        abs(low_adjustment) > abs(high_adjustment),
        maxabs(truth_residuals),
        result.maximum_raw_control_residual,
        result.maximum_reconciled_control_residual,
        sign_violation_count,
        structural_zero_violation_count,
        predetermined_violation_count,
    )
end

function expected_int(contract::StoneContract, key::String)
    value = contract.expected_benchmark[key]
    value isa Integer ||
        throw(
        ReconciliationContractError(
            "expected_benchmark.$key",
            "must be an integer",
        ),
    )
    return Int(value)
end

function expected_float(contract::StoneContract, key::String)
    value = contract.expected_benchmark[key]
    value isa Real ||
        throw(
        ReconciliationContractError(
            "expected_benchmark.$key",
            "must be numeric",
        ),
    )
    return Float64(value)
end

function require_benchmark_close(
        observed::Float64,
        expected::Float64,
        key::String,
        tolerance::Float64,
    )
    return abs(observed - expected) <= tolerance ||
        throw(
        ReconciliationContractError(
            "benchmark.$key",
            "expected $expected, got $observed",
        ),
    )
end

function validate_benchmark_qualification(
        problem::StoneProblem,
        result::StoneResult,
        metrics::BenchmarkMetrics,
        contract::StoneContract,
    )
    length(problem.cells) == expected_int(contract, "cell_count") ||
        throw(ReconciliationContractError("benchmark.cell_count", "changed"))
    result.adjustable_cell_count ==
        expected_int(contract, "adjustable_cell_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.adjustable_cell_count",
            "changed",
        ),
    )
    count(cell -> cell.predetermined, problem.cells) ==
        expected_int(contract, "predetermined_cell_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.predetermined_cell_count",
            "changed",
        ),
    )
    count(cell -> cell.structural_zero, problem.cells) ==
        expected_int(contract, "structural_zero_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.structural_zero_count",
            "changed",
        ),
    )
    count(cell -> cell.raw_value < 0, problem.cells) ==
        expected_int(contract, "negative_cell_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.negative_cell_count",
            "changed",
        ),
    )
    result.exact_control_count == expected_int(contract, "control_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.control_count",
            "changed",
        ),
    )
    result.adjustable_constraint_rank ==
        expected_int(contract, "adjustable_constraint_rank") ||
        throw(
        ReconciliationContractError(
            "benchmark.adjustable_constraint_rank",
            "changed",
        ),
    )
    result.adjustable_control_count ==
        expected_int(contract, "adjustable_control_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.adjustable_control_count",
            "changed",
        ),
    )
    result.fixed_only_control_count ==
        expected_int(contract, "fixed_only_control_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.fixed_only_control_count",
            "changed",
        ),
    )
    result.dependent_adjustable_control_count ==
        expected_int(contract, "dependent_adjustable_control_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.dependent_adjustable_control_count",
            "changed",
        ),
    )
    comparison_tolerance = 100 * eps(Float64)
    require_benchmark_close(
        metrics.high_confidence_adjustment,
        expected_float(contract, "high_confidence_adjustment"),
        "high_confidence_adjustment",
        comparison_tolerance,
    )
    require_benchmark_close(
        metrics.low_confidence_adjustment,
        expected_float(contract, "low_confidence_adjustment"),
        "low_confidence_adjustment",
        comparison_tolerance,
    )
    require_benchmark_close(
        metrics.low_to_high_absolute_adjustment_ratio,
        expected_float(
            contract,
            "low_to_high_absolute_adjustment_ratio",
        ),
        "low_to_high_absolute_adjustment_ratio",
        comparison_tolerance,
    )
    require_benchmark_close(
        result.objective_value,
        expected_float(contract, "objective_value"),
        "objective_value",
        comparison_tolerance,
    )
    require_benchmark_close(
        metrics.raw_root_mean_square_error,
        expected_float(contract, "raw_vs_truth_rmse"),
        "raw_vs_truth_rmse",
        comparison_tolerance,
    )
    require_benchmark_close(
        metrics.reconciled_root_mean_square_error,
        expected_float(contract, "reconciled_vs_truth_rmse"),
        "reconciled_vs_truth_rmse",
        comparison_tolerance,
    )
    require_benchmark_close(
        metrics.root_mean_square_error_improvement,
        expected_float(contract, "rmse_improvement"),
        "rmse_improvement",
        comparison_tolerance,
    )
    require_benchmark_close(
        metrics.raw_mean_absolute_error,
        expected_float(contract, "raw_vs_truth_mae"),
        "raw_vs_truth_mae",
        comparison_tolerance,
    )
    require_benchmark_close(
        metrics.reconciled_mean_absolute_error,
        expected_float(contract, "reconciled_vs_truth_mae"),
        "reconciled_vs_truth_mae",
        comparison_tolerance,
    )
    require_benchmark_close(
        metrics.mean_absolute_error_improvement,
        expected_float(contract, "mae_improvement"),
        "mae_improvement",
        comparison_tolerance,
    )
    result.maximum_reconciled_control_residual <=
        expected_float(
        contract,
        "maximum_balanced_control_residual",
    ) ||
        throw(
        ReconciliationContractError(
            "benchmark.maximum_balanced_control_residual",
            "exceeds the frozen bound",
        ),
    )
    metrics.sign_violation_count ==
        expected_int(contract, "sign_violation_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.sign_violation_count",
            "changed",
        ),
    )
    metrics.structural_zero_violation_count ==
        expected_int(contract, "structural_zero_violation_count") ||
        throw(
        ReconciliationContractError(
            "benchmark.structural_zero_violation_count",
            "changed",
        ),
    )
    metrics.lower_confidence_absorbs_more ||
        throw(
        ReconciliationContractError(
            "benchmark.reliability_behavior",
            "lower-confidence cell did not absorb more adjustment",
        ),
    )
    metrics.reconciled_root_mean_square_error <
        metrics.raw_root_mean_square_error ||
        throw(
        ReconciliationContractError(
            "benchmark.recovery",
            "reconciliation did not improve RMSE",
        ),
    )
    metrics.reconciled_covariance_weighted_root_mean_square_error <
        metrics.raw_covariance_weighted_root_mean_square_error ||
        throw(
        ReconciliationContractError(
            "benchmark.weighted_recovery",
            "reconciliation did not improve covariance-weighted RMSE",
        ),
    )
    result.predetermined_cells_fixed ||
        throw(
        ReconciliationContractError(
            "benchmark.predetermined_cells_fixed",
            "failed",
        ),
    )
    result.structural_zeros_preserved ||
        throw(
        ReconciliationContractError(
            "benchmark.structural_zeros_preserved",
            "failed",
        ),
    )
    result.signs_preserved ||
        throw(
        ReconciliationContractError(
            "benchmark.signs_preserved",
            "failed",
        ),
    )
    !result.promotion_ready ||
        throw(ReconciliationContractError("benchmark", "became promotable"))
    !result.model_state_write ||
        throw(ReconciliationContractError("benchmark", "writes model state"))
    result.accounting_gate_effect == "NONE" ||
        throw(
        ReconciliationContractError(
            "benchmark",
            "changes an accounting gate",
        ),
    )
    return nothing
end

"""
    assess_ordinary_ras(values; row_margins, column_margins, price_bases)

Return a non-mutating eligibility assessment; this function never runs RAS.
Negative cells, absent margins, inconsistent margin totals, and mixed or
unknown price bases make ordinary RAS ineligible. Even an otherwise eligible
nonnegative block remains `NOT_RUN_BLOCKED` because this research checkpoint
does not include an ordinary RAS implementation.
"""
function assess_ordinary_ras(
        values::AbstractMatrix{<:Real};
        row_margins = nothing,
        column_margins = nothing,
        price_bases::Vector{String} = String[],
        tolerance::Float64 = 1.0e-10,
    )
    blockers = String[]
    any(value -> value < 0, values) &&
        push!(blockers, "SIGNED_CELLS_PRESENT")
    if row_margins === nothing || column_margins === nothing
        push!(blockers, "UNKNOWN_MARGINS")
    else
        length(row_margins) == size(values, 1) ||
            push!(blockers, "ROW_MARGIN_DIMENSION_MISMATCH")
        length(column_margins) == size(values, 2) ||
            push!(blockers, "COLUMN_MARGIN_DIMENSION_MISMATCH")
        if length(row_margins) == size(values, 1) &&
                length(column_margins) == size(values, 2)
            all(isfinite, row_margins) &&
                all(isfinite, column_margins) ||
                push!(blockers, "NONFINITE_MARGINS")
            abs(sum(row_margins) - sum(column_margins)) > tolerance &&
                push!(blockers, "CONFLICTING_MARGIN_TOTALS")
        end
    end
    isempty(price_bases) &&
        push!(blockers, "UNKNOWN_PRICE_BASIS")
    length(unique(price_bases)) > 1 &&
        push!(blockers, "MIXED_PRICE_BASES")
    eligible = isempty(blockers)
    push!(blockers, "ORDINARY_RAS_IMPLEMENTATION_NOT_INCLUDED")
    return ComparatorAssessment(
        COMPARATOR_SCHEMA,
        "ORDINARY_RAS",
        "NOT_RUN_BLOCKED",
        eligible,
        blockers,
        ["UN_SUT_IOT_2018"],
        "Ordinary RAS is fail-closed outside a homogeneous nonnegative block with known, consistent row and column margins on one price basis.",
    )
end

function benchmark_comparator_assessments(
        problem::StoneProblem,
        contract::StoneContract,
    )
    cells = canonical_cells(problem)
    raw_matrix = reshape(
        Float64[cell.raw_value for cell in cells],
        2,
        3,
    )
    assessments = ComparatorAssessment[
        assess_ordinary_ras(
            raw_matrix;
            row_margins = nothing,
            column_margins = nothing,
            price_bases = [problem.price_basis],
            tolerance = contract.control_absolute_tolerance,
        ),
    ]
    for comparator in contract.comparators
        comparator.method_id == "ORDINARY_RAS" && continue
        push!(
            assessments,
            ComparatorAssessment(
                COMPARATOR_SCHEMA,
                comparator.method_id,
                comparator.status,
                comparator.eligible,
                copy(comparator.blockers),
                copy(comparator.citation_ids),
                comparator.scientific_basis,
            ),
        )
    end
    return sort!(assessments; by = assessment -> assessment.method_id)
end

function run_synthetic_benchmark(
        contract::StoneContract = load_stone_contract(),
    )
    problem = load_synthetic_benchmark(contract)
    result = reconcile_stone(problem, contract)
    metrics = benchmark_metrics(problem, result, contract)
    validate_benchmark_qualification(problem, result, metrics, contract)
    comparators = benchmark_comparator_assessments(problem, contract)
    all(comparator.status == "NOT_RUN_BLOCKED" for comparator in comparators) ||
        throw(
        ReconciliationContractError(
            "benchmark.comparators",
            "all comparators must remain NOT_RUN_BLOCKED",
        ),
    )
    return (
        contract = contract,
        problem = problem,
        result = result,
        metrics = metrics,
        comparators = comparators,
    )
end

format_float(value::Float64) = value == 0.0 ? "0" : repr(value)
format_csv_value(::Nothing) = ""
format_csv_value(value::Float64) = format_float(value)
format_csv_value(value::Integer) = string(value)
format_csv_value(value::Bool) = value ? "true" : "false"
format_csv_value(value::AbstractString) = String(value)

function csv_escape(value)
    text = format_csv_value(value)
    if occursin(',', text) ||
            occursin('"', text) ||
            occursin('\n', text) ||
            occursin('\r', text)
        return "\"" * replace(text, "\"" => "\"\"") * "\""
    end
    return text
end

function write_csv(file_path::AbstractString, header, rows)
    open(file_path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join((csv_escape(value) for value in row), ","))
        end
    end
    return file_path
end

function toml_quote(value::AbstractString)
    escaped = replace(
        String(value),
        "\\" => "\\\\",
        "\"" => "\\\"",
        "\n" => "\\n",
        "\r" => "\\r",
        "\t" => "\\t",
    )
    return "\"" * escaped * "\""
end

function write_metrics(
        file_path::AbstractString,
        metrics::BenchmarkMetrics,
        result::StoneResult,
    )
    open(file_path, "w") do io
        println(io, "schema_version = ", toml_quote(metrics.schema_version))
        println(io, "fixture_id = ", toml_quote(metrics.fixture_id))
        println(
            io,
            "raw_root_mean_square_error = ",
            format_float(metrics.raw_root_mean_square_error),
        )
        println(
            io,
            "reconciled_root_mean_square_error = ",
            format_float(metrics.reconciled_root_mean_square_error),
        )
        println(
            io,
            "root_mean_square_error_improvement = ",
            format_float(metrics.root_mean_square_error_improvement),
        )
        println(
            io,
            "raw_mean_absolute_error = ",
            format_float(metrics.raw_mean_absolute_error),
        )
        println(
            io,
            "reconciled_mean_absolute_error = ",
            format_float(metrics.reconciled_mean_absolute_error),
        )
        println(
            io,
            "mean_absolute_error_improvement = ",
            format_float(metrics.mean_absolute_error_improvement),
        )
        println(
            io,
            "raw_covariance_weighted_root_mean_square_error = ",
            format_float(
                metrics.raw_covariance_weighted_root_mean_square_error,
            ),
        )
        println(
            io,
            "reconciled_covariance_weighted_root_mean_square_error = ",
            format_float(
                metrics.reconciled_covariance_weighted_root_mean_square_error,
            ),
        )
        println(
            io,
            "maximum_absolute_adjustment = ",
            format_float(metrics.maximum_absolute_adjustment),
        )
        println(
            io,
            "high_confidence_adjustment = ",
            format_float(metrics.high_confidence_adjustment),
        )
        println(
            io,
            "low_confidence_adjustment = ",
            format_float(metrics.low_confidence_adjustment),
        )
        println(
            io,
            "low_to_high_absolute_adjustment_ratio = ",
            format_float(metrics.low_to_high_absolute_adjustment_ratio),
        )
        println(
            io,
            "lower_confidence_absorbs_more = ",
            metrics.lower_confidence_absorbs_more,
        )
        println(
            io,
            "truth_control_maximum_residual = ",
            format_float(metrics.truth_control_maximum_residual),
        )
        println(
            io,
            "raw_control_maximum_residual = ",
            format_float(metrics.raw_control_maximum_residual),
        )
        println(
            io,
            "reconciled_control_maximum_residual = ",
            format_float(metrics.reconciled_control_maximum_residual),
        )
        println(io, "sign_violation_count = ", metrics.sign_violation_count)
        println(
            io,
            "structural_zero_violation_count = ",
            metrics.structural_zero_violation_count,
        )
        println(
            io,
            "predetermined_violation_count = ",
            metrics.predetermined_violation_count,
        )
        println(io, "objective_value = ", format_float(result.objective_value))
        println(
            io,
            "adjustable_constraint_rank = ",
            result.adjustable_constraint_rank,
        )
        println(
            io,
            "adjustable_control_count = ",
            result.adjustable_control_count,
        )
        println(
            io,
            "fixed_only_control_count = ",
            result.fixed_only_control_count,
        )
        println(
            io,
            "dependent_adjustable_control_count = ",
            result.dependent_adjustable_control_count,
        )
        println(
            io,
            "maximum_reconciled_control_residual = ",
            format_float(result.maximum_reconciled_control_residual),
        )
        println(io, "promotion_ready = false")
        println(io, "model_state_write = false")
        println(io, "accounting_gate_effect = \"NONE\"")
    end
    return file_path
end

function write_manifest(
        file_path::AbstractString,
        contract::StoneContract,
        problem::StoneProblem,
        artifact_rows,
    )
    open(file_path, "w") do io
        println(io, "schema_version = ", toml_quote(REPORT_MANIFEST_SCHEMA))
        println(io, "report_id = \"us-ws2c-stone-method-qualification-v1\"")
        println(
            io,
            "classification = \"RESEARCH_ONLY_METHOD_QUALIFICATION_NOT_ORIGIN_ELIGIBLE\"",
        )
        println(io, "method_id = ", toml_quote(contract.method_id))
        println(io, "method_version = ", toml_quote(contract.method_version))
        println(io, "contract_sha256 = ", toml_quote(contract.source_sha256))
        println(io, "fixture_sha256 = ", toml_quote(problem.source_sha256))
        println(io, "artifact_count = ", length(artifact_rows))
        println(io, "forecast_origin_admissible = false")
        println(io, "promotion_ready = false")
        println(io, "model_state_write = false")
        println(io, "accounting_gate_effect = \"NONE\"")
        for artifact in artifact_rows
            println(io)
            println(io, "[[artifact]]")
            println(io, "artifact_id = ", toml_quote(artifact.artifact_id))
            println(io, "file_name = ", toml_quote(artifact.file_name))
            println(io, "sha256 = ", toml_quote(artifact.sha256))
            println(io, "role = ", toml_quote(artifact.role))
        end
    end
    return file_path
end

function write_stone_reconciliation_report(
        output_directory::AbstractString,
        contract::StoneContract,
        problem::StoneProblem,
        result::StoneResult,
        metrics::BenchmarkMetrics,
        comparators::Vector{ComparatorAssessment},
    )
    validate_benchmark_qualification(problem, result, metrics, contract)
    mkpath(output_directory)
    adjustment_path =
        joinpath(output_directory, "stone_adjustment_ledger.csv")
    control_path =
        joinpath(output_directory, "stone_control_diagnostics.csv")
    metrics_path =
        joinpath(output_directory, "stone_benchmark_metrics.toml")
    comparator_path =
        joinpath(output_directory, "stone_comparator_status.csv")
    manifest_path =
        joinpath(output_directory, "stone_report_manifest.toml")

    adjustment_header = [
        "schema_version",
        "cell_id",
        "row_code",
        "column_code",
        "raw_value",
        "truth_value",
        "reconciled_value",
        "adjustment",
        "absolute_adjustment",
        "relative_adjustment",
        "prior_standard_uncertainty",
        "posterior_standard_uncertainty",
        "standardized_adjustment",
        "reliability_class_id",
        "covariance_class_id",
        "covariance_group",
        "predetermined",
        "structural_zero",
        "cell_state",
        "sign_policy",
        "negative_economic_type",
        "price_basis",
        "value_unit",
        "binding_control_ids",
        "method_id",
        "method_version",
        "provenance",
    ]
    adjustment_rows = [
        (
                record.schema_version,
                record.cell_id,
                record.row_code,
                record.column_code,
                record.raw_value,
                record.truth_value,
                record.reconciled_value,
                record.adjustment,
                record.absolute_adjustment,
                record.relative_adjustment,
                record.prior_standard_uncertainty,
                record.posterior_standard_uncertainty,
                record.standardized_adjustment,
                record.reliability_class_id,
                record.covariance_class_id,
                record.covariance_group,
                record.predetermined,
                record.structural_zero,
                record.cell_state,
                record.sign_policy,
                record.negative_economic_type,
                record.price_basis,
                record.value_unit,
                join(record.binding_control_ids, "|"),
                record.method_id,
                record.method_version,
                record.provenance,
            ) for record in result.adjustment_records
    ]
    write_csv(adjustment_path, adjustment_header, adjustment_rows)

    control_header = [
        "schema_version",
        "control_id",
        "rhs",
        "raw_achieved",
        "raw_residual",
        "reconciled_achieved",
        "reconciled_residual",
        "exact",
        "adjustable_coefficient_norm",
        "price_basis",
        "provenance",
    ]
    control_rows = [
        (
                diagnostic.schema_version,
                diagnostic.control_id,
                diagnostic.rhs,
                diagnostic.raw_achieved,
                diagnostic.raw_residual,
                diagnostic.reconciled_achieved,
                diagnostic.reconciled_residual,
                diagnostic.exact,
                diagnostic.adjustable_coefficient_norm,
                diagnostic.price_basis,
                diagnostic.provenance,
            ) for diagnostic in result.control_diagnostics
    ]
    write_csv(control_path, control_header, control_rows)
    write_metrics(metrics_path, metrics, result)

    comparator_header = [
        "schema_version",
        "method_id",
        "status",
        "eligible",
        "blockers",
        "citation_ids",
        "scientific_basis",
    ]
    comparator_rows = [
        (
                assessment.schema_version,
                assessment.method_id,
                assessment.status,
                assessment.eligible,
                join(assessment.blockers, "|"),
                join(assessment.citation_ids, "|"),
                assessment.scientific_basis,
            ) for assessment in sort!(
                copy(comparators);
                by = assessment -> assessment.method_id,
            )
    ]
    write_csv(comparator_path, comparator_header, comparator_rows)

    artifacts = [
        (
            artifact_id = "adjustment_ledger",
            file_name = basename(adjustment_path),
            sha256 = file_sha256(adjustment_path),
            role = "RAW_BALANCED_UNCERTAINTY_AND_ADJUSTMENT_LEDGER",
        ),
        (
            artifact_id = "control_diagnostics",
            file_name = basename(control_path),
            sha256 = file_sha256(control_path),
            role = "EXACT_LINEAR_CONTROL_RESIDUALS",
        ),
        (
            artifact_id = "benchmark_metrics",
            file_name = basename(metrics_path),
            sha256 = file_sha256(metrics_path),
            role = "FROZEN_SYNTHETIC_RECOVERY_METRICS",
        ),
        (
            artifact_id = "comparator_status",
            file_name = basename(comparator_path),
            sha256 = file_sha256(comparator_path),
            role = "PREREGISTERED_NOT_RUN_BLOCKED_COMPARATORS",
        ),
    ]
    write_manifest(manifest_path, contract, problem, artifacts)
    return (
        adjustment_path = adjustment_path,
        adjustment_sha256 = file_sha256(adjustment_path),
        control_path = control_path,
        control_sha256 = file_sha256(control_path),
        metrics_path = metrics_path,
        metrics_sha256 = file_sha256(metrics_path),
        comparator_path = comparator_path,
        comparator_sha256 = file_sha256(comparator_path),
        manifest_path = manifest_path,
        manifest_sha256 = file_sha256(manifest_path),
    )
end

end
