module USInventoryTransitionEvidenceLedger

using CSV
using Dates
using SHA
using TOML

using ..UST10105Controls:
    load_t10105_fixture
using ..USBEAInventoryStockDiagnostic:
    diagnose_bea_inventory_stocks,
    load_bea_inventory_stock_fixture,
    published_identities_pass,
    published_ratios_pass
using ..USAfterRedefinitionsCommonBasis:
    load_after_redefinitions_fixture
using ..USAfterRedefinitionsModelCore:
    build_model_core_aggregation
using ..USInventoryStockLedger:
    load_inventory_stock_fixture,
    stage_additivity_pass,
    validate_inventory_stock_ledger

export CONTRACT_SCHEMA,
    OBSERVATION_SCHEMA,
    CHECK_SCHEMA,
    TRANSITION_SCHEMA,
    APPROVED_CONTRACT_SHA256,
    PinnedArtifact,
    EvidenceSourceSpec,
    BlockedTransitionSpec,
    InventoryTransitionContract,
    InventoryEvidenceObservation,
    InventoryEvidenceCheck,
    InventoryTransitionAssessment,
    InventoryEvidenceSummary,
    InventoryTransitionEvidenceReport,
    build_inventory_transition_evidence,
    normalized_module_sha256,
    load_inventory_transition_contract,
    reject_stock_difference_equals_cipi,
    validate_inventory_transition_evidence,
    write_inventory_transition_evidence

const CONTRACT_SCHEMA =
    "beforeit-us-inventory-transition-evidence-ledger-contract.v1"
const OBSERVATION_SCHEMA =
    "beforeit-us-inventory-evidence-observation.v1"
const CHECK_SCHEMA =
    "beforeit-us-inventory-evidence-check.v1"
const TRANSITION_SCHEMA =
    "beforeit-us-inventory-transition-assessment.v1"
const REPORT_SCHEMA =
    "beforeit-us-inventory-transition-evidence-report.v1"
const APPROVED_CONTRACT_SHA256 =
    "4714723961175ae7b6acbd9504ce6a1fb8931ab925b64064fe785e932b9a8767"
const EMPTY_SHA256 =
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "inventory_transition_evidence_ledger.toml")
const DEFAULT_REPO_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", ".."))

const EXPECTED_ARTIFACT_IDS = Set(
    [
        "t10105_manifest",
        "t10105_cells",
        "t50805b_manifest",
        "t50805b_cells",
        "after_redefinitions_manifest",
        "after_redefinitions_cells",
        "model_core_mapping",
        "sector_mapping",
        "synthetic_stage_manifest",
        "synthetic_stage_cells",
        "reader_t10105",
        "reader_t50805b",
        "reader_supply_make",
        "reader_symmetric_supply_use",
        "reader_requirements",
        "reader_after_redefinitions",
        "reader_model_core",
        "reader_synthetic_stage",
        "scripts_us_project",
        "scripts_us_manifest",
    ],
)
const EXPECTED_SOURCE_IDS = Set(
    [
        "bea_nipa_t10105_cipi",
        "bea_nipa_t50805b_holder_stocks",
        "bea_after_redefinitions_producer_price_2024_f030",
        "synthetic_inventory_stage_comparator",
    ],
)
const EXPECTED_TRANSITION_IDS = [
    "t50805b_prior_stock_transition",
    "t50805b_stock_difference_to_t10105_cipi",
    "t50805b_holder_to_f030_commodity",
    "f030_annual_to_t10105_quarterly",
    "observed_holder_to_inventory_stage",
    "used_other_closure_transition",
    "current_vintage_to_forecast_origin",
    "evidence_to_model_inventory_state",
]
const TOP_LEVEL_KEYS = Set(
    [
        "schema_version",
        "contract_id",
        "classification",
        "promotion_status",
        "scientific_role",
        "observation_schema_version",
        "check_schema_version",
        "transition_schema_version",
        "missing_value_policy",
        "zero_policy",
        "duplicate_policy",
        "namespace_policy",
        "stock_transition_policy",
        "t10105_conversion_policy",
        "f030_frequency_policy",
        "forecast_origin_admissible",
        "promotion_ready",
        "model_inventory_vector_emitted",
        "s_s_emitted",
        "model_state_write",
        "accounting_gate_effect",
        "expected",
        "rounding",
        "namespaces",
        "f030_aggregation",
        "implementation",
        "artifact",
        "source",
        "blocked_transition",
    ],
)
const ARTIFACT_KEYS = Set(["artifact_id", "path", "sha256", "role"])
const SOURCE_KEYS = Set(
    [
        "source_id",
        "evidence_role",
        "manifest_artifact_id",
        "data_artifact_id",
        "source_status",
        "source_sha256",
        "metadata_sha256",
        "stock_flow_class",
        "frequency",
        "reference_scope",
        "time_basis",
        "price_basis",
        "valuation_basis",
        "published_rate_basis",
        "forecast_origin_admissible",
    ],
)
const BLOCKED_TRANSITION_KEYS =
    Set(["transition_id", "blocker", "required_evidence", "basis"])
const EXPECTED_KEYS = Set(
    [
        "observation_count",
        "evidentiary_observation_count",
        "non_evidentiary_observation_count",
        "source_check_count",
        "blocked_transition_count",
        "t10105_period_count",
        "t10105_positive_count",
        "t10105_negative_count",
        "t10105_zero_count",
        "t10105_maximum_gpdi_residual_millions",
        "t10105_maximum_expenditure_residual_millions",
        "t10105_2024_total_millions",
        "t50805b_published_row_count",
        "t50805b_stock_row_count",
        "t50805b_reference_period_count",
        "t50805b_private_total_millions",
        "t50805b_duplicate_total_millions",
        "f030_core_count",
        "f030_closure_count",
        "f030_core_total_millions",
        "f030_closure_total_millions",
        "f030_core_closure_cell_total_millions",
        "f030_published_column_control_millions",
        "f030_cell_minus_published_control_millions",
        "f030_core_negative_count",
        "f030_closure_negative_count",
        "f030_explicit_count",
        "f030_published_control_minus_t10105_2024_millions",
        "synthetic_comparator_count",
        "model_vector_output_count",
        "s_s_output_count",
        "state_write_count",
        "gate_effect_count",
        "origin_admissible_output_count",
    ],
)
const ROUNDING_KEYS = Set(
    [
        "f030_published_annual_control_tolerance_millions",
        "f030_source_cell_count",
        "f030_cells_to_control_tolerance_millions",
        "t10105_converted_quarter_tolerance_millions",
        "t10105_2024_quarter_count",
        "t10105_2024_sum_tolerance_millions",
        "combined_cross_source_tolerance_millions",
        "cross_source_correction_applied",
    ],
)
const NAMESPACE_KEYS =
    Set(["holder", "commodity", "stage", "axes_disjoint", "other_label_policy"])
const F030_AGGREGATION_KEYS = Set(
    [
        "source_projection_id",
        "source_projection_sha256",
        "source_column_code",
        "source_year",
        "source_frequency",
        "source_price_basis",
        "aggregation_policy",
        "retail_source_codes",
        "retail_target_code",
        "closure_codes",
        "quarterly_conversion_applied",
        "clipping_applied",
        "balancing_applied",
        "closure_allocation_applied",
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
const MODULE_HASH_POLICY =
    "SHA256_AFTER_REPLACING_SINGLE_APPROVED_CONTRACT_HASH_LITERAL_WITH_64_ZEROES"
const EVIDENTIARY_SOURCE_IDS = Set(
    [
        "bea_nipa_t10105_cipi",
        "bea_nipa_t50805b_holder_stocks",
        "bea_after_redefinitions_producer_price_2024_f030",
    ],
)
const ALLOWED_CELL_STATES = Set(
    [
        "SOURCE_NUMERIC_TRANSFORMED_EXACT",
        "SOURCE_NUMERIC",
        "SOURCE_EXPLICIT_NUMERIC",
        "SOURCE_SELECTED_ZERO_NOT_SHOWN",
        "SYNTHETIC_NUMERIC",
    ],
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
file_sha256(path) = sha256_hex(read(path))

function normalized_module_sha256(path::AbstractString)
    source = read(path, String)
    contract_hash_literal = "\"$APPROVED_CONTRACT_SHA256\""
    locations = findall(contract_hash_literal, source)
    length(locations) == 1 ||
        fail(
        "implementation.module",
        "must contain exactly one approved-contract hash literal",
    )
    normalized = replace(
        source,
        contract_hash_literal => "\"$(repeat("0", 64))\"";
        count = 1,
    )
    return sha256_hex(codeunits(normalized))
end

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
    return value
end

function nonempty_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    isempty(strip(text)) && fail(location, "must be nonempty")
    return text
end

function sha256_string(value, location)
    text = lowercase(nonempty_string(value, location))
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail(location, "must be a lowercase SHA-256")
    return text
end

function false_boolean(value, location)
    value === false || fail(location, "must remain false")
    return false
end

function finite_number(value, location)
    value isa Real && !(value isa Bool) ||
        fail(location, "must be numeric")
    number = Float64(value)
    isfinite(number) || fail(location, "must be finite")
    return number
end

function nonnegative_integer(value, location)
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    Int(value) >= 0 || fail(location, "must be nonnegative")
    return Int(value)
end

function safe_path(repo_root::AbstractString, relative_path, location)
    text = nonempty_string(relative_path, location)
    isabspath(text) && fail(location, "must be repository-relative")
    root = dirname(
        joinpath(
            abspath(normpath(String(repo_root))),
            ".inventory-transition-root",
        ),
    )
    resolved = abspath(normpath(joinpath(root, text)))
    prefix = root * Base.Filesystem.path_separator
    (resolved == root || startswith(resolved, prefix)) ||
        fail(location, "escapes repository root")
    return resolved
end

struct PinnedArtifact
    artifact_id::String
    relative_path::String
    path::String
    sha256::String
    role::String
end

struct EvidenceSourceSpec
    source_id::String
    evidence_role::String
    manifest_artifact_id::String
    data_artifact_id::String
    source_status::String
    source_sha256::String
    metadata_sha256::String
    stock_flow_class::String
    frequency::String
    reference_scope::String
    time_basis::String
    price_basis::String
    valuation_basis::String
    published_rate_basis::String
    forecast_origin_admissible::Bool
end

struct BlockedTransitionSpec
    transition_id::String
    blocker::String
    required_evidence::String
    basis::String
end

struct InventoryTransitionContract
    path::String
    sha256::String
    repo_root::String
    contract_id::String
    classification::String
    promotion_status::String
    scientific_role::String
    artifacts::Dict{String, PinnedArtifact}
    sources::Dict{String, EvidenceSourceSpec}
    blocked_transitions::Vector{BlockedTransitionSpec}
    expected::Dict{String, Any}
    rounding::Dict{String, Any}
    namespaces::Dict{String, Any}
    f030_aggregation::Dict{String, Any}
    implementation::Dict{String, Any}
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_inventory_vector_emitted::Bool
    s_s_emitted::Bool
    model_state_write::Bool
    accounting_gate_effect::Symbol
end

struct InventoryEvidenceObservation
    schema_version::String
    record_id::String
    source_id::String
    evidence_role::String
    source_record_key::String
    description::String
    reference_period::String
    stock_flow_class::String
    frequency::String
    time_basis::String
    price_basis::String
    valuation_basis::String
    published_rate_basis::String
    economic_unit::String
    holder_namespace::String
    holder_code::String
    commodity_namespace::String
    commodity_code::String
    stage_namespace::String
    stage_code::String
    value::Float64
    cell_state::String
    source_manifest_sha256::String
    source_data_sha256::String
    upstream_source_sha256::String
    source_status::String
    forecast_origin_admissible::Bool
end

struct InventoryEvidenceCheck
    schema_version::String
    check_id::String
    evidence_role::String
    status::String
    diagnostic_value::Float64
    absolute_diagnostic_value::Float64
    tolerance::Float64
    basis::String
    correction_applied::Bool
    forecast_origin_admissible::Bool
end

struct InventoryTransitionAssessment
    schema_version::String
    transition_id::String
    status::String
    diagnostic_value::Union{Missing, Float64}
    absolute_diagnostic_value::Union{Missing, Float64}
    tolerance::Union{Missing, Float64}
    blocker::String
    required_evidence::String
    basis::String
    mapping_applied::Bool
    model_output_emitted::Bool
    forecast_origin_admissible::Bool
end

struct InventoryEvidenceSummary
    observation_count::Int
    evidentiary_observation_count::Int
    non_evidentiary_observation_count::Int
    t10105_period_count::Int
    t10105_positive_count::Int
    t10105_negative_count::Int
    t10105_zero_count::Int
    t10105_maximum_gpdi_residual_millions::Float64
    t10105_maximum_expenditure_residual_millions::Float64
    t10105_2024_total_millions::Float64
    t50805b_published_row_count::Int
    t50805b_stock_row_count::Int
    t50805b_reference_period_count::Int
    t50805b_private_total_millions::Float64
    t50805b_duplicate_total_millions::Float64
    f030_core_count::Int
    f030_closure_count::Int
    f030_core_total_millions::Float64
    f030_closure_total_millions::Float64
    f030_core_closure_cell_total_millions::Float64
    f030_published_column_control_millions::Float64
    f030_cell_minus_published_control_millions::Float64
    f030_core_negative_count::Int
    f030_closure_negative_count::Int
    f030_explicit_count::Int
    f030_published_control_minus_t10105_2024_millions::Float64
    synthetic_comparator_count::Int
    model_vector_output_count::Int
    s_s_output_count::Int
    state_write_count::Int
    gate_effect_count::Int
    origin_admissible_output_count::Int
end

struct InventoryTransitionEvidenceReport
    schema_version::String
    contract_path::String
    contract_sha256::String
    classification::String
    promotion_status::String
    observations::Vector{InventoryEvidenceObservation}
    checks::Vector{InventoryEvidenceCheck}
    transitions::Vector{InventoryTransitionAssessment}
    summary::InventoryEvidenceSummary
    forecast_origin_admissible::Bool
    promotion_ready::Bool
    model_inventory_vector_emitted::Bool
    s_s_emitted::Bool
    model_state_write::Bool
    accounting_gate_effect::Symbol
end

function parse_artifacts(rows, repo_root)
    rows isa AbstractVector ||
        fail("contract.artifact", "must be an array of tables")
    artifacts = Dict{String, PinnedArtifact}()
    for (index, row) in enumerate(rows)
        location = "contract.artifact[$index]"
        exact_keys(row, ARTIFACT_KEYS, location)
        artifact_id =
            nonempty_string(row["artifact_id"], "$location.artifact_id")
        haskey(artifacts, artifact_id) &&
            fail(location, "duplicates artifact_id $artifact_id")
        relative_path = nonempty_string(row["path"], "$location.path")
        path = safe_path(repo_root, relative_path, "$location.path")
        isfile(path) || fail(location, "artifact is missing: $relative_path")
        islink(path) && fail(location, "artifact cannot be a symbolic link")
        expected_sha256 =
            sha256_string(row["sha256"], "$location.sha256")
        actual_sha256 = file_sha256(path)
        actual_sha256 == expected_sha256 ||
            fail(
            location,
            "SHA-256 mismatch; expected $expected_sha256, got $actual_sha256",
        )
        artifacts[artifact_id] = PinnedArtifact(
            artifact_id,
            relative_path,
            path,
            expected_sha256,
            nonempty_string(row["role"], "$location.role"),
        )
    end
    Set(keys(artifacts)) == EXPECTED_ARTIFACT_IDS ||
        fail("contract.artifact", "artifact identifier set changed")
    return artifacts
end

function parse_sources(rows, artifacts)
    rows isa AbstractVector ||
        fail("contract.source", "must be an array of tables")
    sources = Dict{String, EvidenceSourceSpec}()
    for (index, row) in enumerate(rows)
        location = "contract.source[$index]"
        exact_keys(row, SOURCE_KEYS, location)
        source_id = nonempty_string(row["source_id"], "$location.source_id")
        haskey(sources, source_id) &&
            fail(location, "duplicates source_id $source_id")
        manifest_artifact_id = nonempty_string(
            row["manifest_artifact_id"],
            "$location.manifest_artifact_id",
        )
        data_artifact_id = nonempty_string(
            row["data_artifact_id"],
            "$location.data_artifact_id",
        )
        haskey(artifacts, manifest_artifact_id) ||
            fail(location, "references an unknown manifest artifact")
        haskey(artifacts, data_artifact_id) ||
            fail(location, "references an unknown data artifact")
        false_boolean(
            row["forecast_origin_admissible"],
            "$location.forecast_origin_admissible",
        )
        sources[source_id] = EvidenceSourceSpec(
            source_id,
            nonempty_string(row["evidence_role"], "$location.evidence_role"),
            manifest_artifact_id,
            data_artifact_id,
            nonempty_string(row["source_status"], "$location.source_status"),
            sha256_string(row["source_sha256"], "$location.source_sha256"),
            sha256_string(
                row["metadata_sha256"],
                "$location.metadata_sha256",
            ),
            nonempty_string(
                row["stock_flow_class"],
                "$location.stock_flow_class",
            ),
            nonempty_string(row["frequency"], "$location.frequency"),
            nonempty_string(
                row["reference_scope"],
                "$location.reference_scope",
            ),
            nonempty_string(row["time_basis"], "$location.time_basis"),
            nonempty_string(row["price_basis"], "$location.price_basis"),
            nonempty_string(
                row["valuation_basis"],
                "$location.valuation_basis",
            ),
            nonempty_string(
                row["published_rate_basis"],
                "$location.published_rate_basis",
            ),
            false,
        )
    end
    Set(keys(sources)) == EXPECTED_SOURCE_IDS ||
        fail("contract.source", "source identifier set changed")
    sources["synthetic_inventory_stage_comparator"].source_sha256 ==
        EMPTY_SHA256 ||
        fail("contract.source.synthetic", "must retain empty synthetic source hash")
    sources["synthetic_inventory_stage_comparator"].metadata_sha256 ==
        EMPTY_SHA256 ||
        fail(
        "contract.source.synthetic",
        "must retain empty synthetic metadata hash",
    )
    return sources
end

function parse_blocked_transitions(rows)
    rows isa AbstractVector ||
        fail("contract.blocked_transition", "must be an array of tables")
    result = BlockedTransitionSpec[]
    for (index, row) in enumerate(rows)
        location = "contract.blocked_transition[$index]"
        exact_keys(row, BLOCKED_TRANSITION_KEYS, location)
        push!(
            result,
            BlockedTransitionSpec(
                nonempty_string(
                    row["transition_id"],
                    "$location.transition_id",
                ),
                nonempty_string(row["blocker"], "$location.blocker"),
                nonempty_string(
                    row["required_evidence"],
                    "$location.required_evidence",
                ),
                nonempty_string(row["basis"], "$location.basis"),
            ),
        )
    end
    getfield.(result, :transition_id) == EXPECTED_TRANSITION_IDS ||
        fail(
        "contract.blocked_transition",
        "transition identifier order changed",
    )
    length(unique(getfield.(result, :transition_id))) == length(result) ||
        fail("contract.blocked_transition", "transition identifiers duplicate")
    return result
end

function validate_expected_table(expected)
    exact_keys(expected, EXPECTED_KEYS, "contract.expected")
    for key in setdiff(
            EXPECTED_KEYS, Set(
                [
                    "t10105_maximum_gpdi_residual_millions",
                    "t10105_maximum_expenditure_residual_millions",
                    "t10105_2024_total_millions",
                    "t50805b_private_total_millions",
                    "t50805b_duplicate_total_millions",
                    "f030_core_total_millions",
                    "f030_closure_total_millions",
                    "f030_core_closure_cell_total_millions",
                    "f030_published_column_control_millions",
                    "f030_cell_minus_published_control_millions",
                    "f030_published_control_minus_t10105_2024_millions",
                ]
            )
        )
        nonnegative_integer(expected[key], "contract.expected.$key")
    end
    for key in (
            "t10105_maximum_gpdi_residual_millions",
            "t10105_maximum_expenditure_residual_millions",
            "t10105_2024_total_millions",
            "t50805b_private_total_millions",
            "t50805b_duplicate_total_millions",
            "f030_core_total_millions",
            "f030_closure_total_millions",
            "f030_core_closure_cell_total_millions",
            "f030_published_column_control_millions",
            "f030_cell_minus_published_control_millions",
            "f030_published_control_minus_t10105_2024_millions",
        )
        finite_number(expected[key], "contract.expected.$key")
    end
    return expected
end

function validate_rounding_table(rounding)
    exact_keys(rounding, ROUNDING_KEYS, "contract.rounding")
    false_boolean(
        rounding["cross_source_correction_applied"],
        "contract.rounding.cross_source_correction_applied",
    )
    finite_number(
        rounding["f030_published_annual_control_tolerance_millions"],
        "contract.rounding.f030_published_annual_control_tolerance_millions",
    ) == 0.5 ||
        fail("contract.rounding", "F030 control tolerance changed")
    nonnegative_integer(
        rounding["f030_source_cell_count"],
        "contract.rounding.f030_source_cell_count",
    ) == 73 ||
        fail("contract.rounding", "F030 source-cell count changed")
    finite_number(
        rounding["f030_cells_to_control_tolerance_millions"],
        "contract.rounding.f030_cells_to_control_tolerance_millions",
    ) == 37.0 ||
        fail("contract.rounding", "F030 cell-sum tolerance changed")
    finite_number(
        rounding["t10105_converted_quarter_tolerance_millions"],
        "contract.rounding.t10105_converted_quarter_tolerance_millions",
    ) == 0.125 ||
        fail("contract.rounding", "T10105 quarter tolerance changed")
    nonnegative_integer(
        rounding["t10105_2024_quarter_count"],
        "contract.rounding.t10105_2024_quarter_count",
    ) == 4 ||
        fail("contract.rounding", "T10105 annual quarter count changed")
    finite_number(
        rounding["t10105_2024_sum_tolerance_millions"],
        "contract.rounding.t10105_2024_sum_tolerance_millions",
    ) == 0.5 ||
        fail("contract.rounding", "T10105 annual tolerance changed")
    finite_number(
        rounding["combined_cross_source_tolerance_millions"],
        "contract.rounding.combined_cross_source_tolerance_millions",
    ) == 1.0 ||
        fail("contract.rounding", "combined tolerance changed")
    return rounding
end

function validate_namespaces(namespaces)
    exact_keys(namespaces, NAMESPACE_KEYS, "contract.namespaces")
    namespaces["axes_disjoint"] === true ||
        fail("contract.namespaces", "axes must remain disjoint")
    holders = String.(namespaces["holder"])
    commodities = String.(namespaces["commodity"])
    stages = String.(namespaces["stage"])
    length(unique(holders)) == length(holders) ||
        fail("contract.namespaces.holder", "contains duplicates")
    length(unique(commodities)) == length(commodities) ||
        fail("contract.namespaces.commodity", "contains duplicates")
    length(unique(stages)) == length(stages) ||
        fail("contract.namespaces.stage", "contains duplicates")
    isempty(intersect(Set(holders), Set(commodities))) ||
        fail("contract.namespaces", "holder and commodity names collide")
    isempty(intersect(Set(holders), Set(stages))) ||
        fail("contract.namespaces", "holder and stage names collide")
    isempty(intersect(Set(commodities), Set(stages))) ||
        fail("contract.namespaces", "commodity and stage names collide")
    nonempty_string(
        namespaces["other_label_policy"],
        "contract.namespaces.other_label_policy",
    )
    return namespaces
end

function validate_f030_aggregation(aggregation)
    exact_keys(
        aggregation,
        F030_AGGREGATION_KEYS,
        "contract.f030_aggregation",
    )
    aggregation["source_projection_id"] == "producer_final_use_2024" ||
        fail("contract.f030_aggregation", "projection changed")
    sha256_string(
        aggregation["source_projection_sha256"],
        "contract.f030_aggregation.source_projection_sha256",
    ) ==
        "205d6c126efc27ba07e89b262e27f81f9bcb7200d679ce039a5aaa7a889e6fbb" ||
        fail("contract.f030_aggregation", "projection hash changed")
    aggregation["source_column_code"] == "F030" ||
        fail("contract.f030_aggregation", "source column changed")
    aggregation["source_year"] == 2024 ||
        fail("contract.f030_aggregation", "source year changed")
    String.(aggregation["closure_codes"]) == ["Used", "Other"] ||
        fail("contract.f030_aggregation", "closure code order changed")
    String.(aggregation["retail_source_codes"]) ==
        ["441", "445", "452", "4A0"] ||
        fail("contract.f030_aggregation", "retail sources changed")
    aggregation["retail_target_code"] == "4A0" ||
        fail("contract.f030_aggregation", "retail target changed")
    for key in (
            "quarterly_conversion_applied",
            "clipping_applied",
            "balancing_applied",
            "closure_allocation_applied",
        )
        false_boolean(
            aggregation[key],
            "contract.f030_aggregation.$key",
        )
    end
    return aggregation
end

function validate_implementation(implementation, repo_root)
    exact_keys(
        implementation,
        IMPLEMENTATION_KEYS,
        "contract.implementation",
    )
    implementation["module_path"] ==
        "scripts/us/accounting/USInventoryTransitionEvidenceLedger.jl" ||
        fail("contract.implementation.module_path", "changed")
    implementation["runner_path"] ==
        "scripts/us/accounting/run_inventory_transition_evidence_ledger.jl" ||
        fail("contract.implementation.runner_path", "changed")
    implementation["module_hash_policy"] == MODULE_HASH_POLICY ||
        fail("contract.implementation.module_hash_policy", "changed")
    module_path = safe_path(
        repo_root,
        implementation["module_path"],
        "contract.implementation.module_path",
    )
    runner_path = safe_path(
        repo_root,
        implementation["runner_path"],
        "contract.implementation.runner_path",
    )
    for (path, location) in (
            (module_path, "contract.implementation.module_path"),
            (runner_path, "contract.implementation.runner_path"),
        )
        isfile(path) || fail(location, "file is missing")
        islink(path) && fail(location, "cannot be a symbolic link")
    end
    expected_module_hash = sha256_string(
        implementation["module_normalized_sha256"],
        "contract.implementation.module_normalized_sha256",
    )
    actual_module_hash = normalized_module_sha256(module_path)
    actual_module_hash == expected_module_hash ||
        fail(
        "contract.implementation.module_normalized_sha256",
        "SHA-256 mismatch; expected $expected_module_hash, got $actual_module_hash",
    )
    expected_runner_hash = sha256_string(
        implementation["runner_sha256"],
        "contract.implementation.runner_sha256",
    )
    actual_runner_hash = file_sha256(runner_path)
    actual_runner_hash == expected_runner_hash ||
        fail(
        "contract.implementation.runner_sha256",
        "SHA-256 mismatch; expected $expected_runner_hash, got $actual_runner_hash",
    )
    return Dict{String, Any}(
        "module_path" => String(implementation["module_path"]),
        "module_hash_policy" => String(implementation["module_hash_policy"]),
        "module_normalized_sha256" => expected_module_hash,
        "module_sha256" => file_sha256(module_path),
        "runner_path" => String(implementation["runner_path"]),
        "runner_sha256" => expected_runner_hash,
    )
end

function load_inventory_transition_contract(
        path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = DEFAULT_REPO_ROOT,
    )
    contract_path = abspath(normpath(String(path)))
    isfile(contract_path) || fail("contract", "file is missing")
    contract_sha256 = file_sha256(contract_path)
    contract_sha256 == APPROVED_CONTRACT_SHA256 ||
        fail(
        "contract",
        "SHA-256 mismatch; expected $APPROVED_CONTRACT_SHA256, got $contract_sha256",
    )
    raw = TOML.parsefile(contract_path)
    exact_keys(raw, TOP_LEVEL_KEYS, "contract")
    raw["schema_version"] == CONTRACT_SCHEMA ||
        fail("contract.schema_version", "is unsupported")
    raw["observation_schema_version"] == OBSERVATION_SCHEMA ||
        fail("contract.observation_schema_version", "is unsupported")
    raw["check_schema_version"] == CHECK_SCHEMA ||
        fail("contract.check_schema_version", "is unsupported")
    raw["transition_schema_version"] == TRANSITION_SCHEMA ||
        fail("contract.transition_schema_version", "is unsupported")
    raw["classification"] ==
        "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE" ||
        fail("contract.classification", "is unsafe")
    raw["promotion_status"] == "RESEARCH_ONLY_NOT_PROMOTED" ||
        fail("contract.promotion_status", "is unsafe")
    raw["missing_value_policy"] ==
        "ABSENT_IS_STRUCTURALLY_MISSING_NOT_NUMERIC_ZERO" ||
        fail("contract.missing_value_policy", "changed")
    raw["zero_policy"] ==
        "PRESERVE_SOURCE_EXPLICIT_NUMERIC_ZERO_SEPARATELY_FROM_SELECTED_ZERO_NOT_SHOWN" ||
        fail("contract.zero_policy", "changed")
    raw["duplicate_policy"] ==
        "PRESERVE_PUBLISHED_T50805B_DUPLICATES_BY_LINE_AND_NEVER_SUM_HIERARCHIES" ||
        fail("contract.duplicate_policy", "changed")
    raw["namespace_policy"] ==
        "HOLDER_COMMODITY_AND_STAGE_AXES_ARE_DISJOINT_AND_FULLY_QUALIFIED" ||
        fail("contract.namespace_policy", "changed")
    raw["stock_transition_policy"] ==
        "NEVER_EQUATE_END_OF_PERIOD_CURRENT_DOLLAR_STOCK_DIFFERENCES_TO_CIPI_WITHOUT_PRIOR_STOCK_AND_VALUATION_TERMS" ||
        fail("contract.stock_transition_policy", "changed")
    raw["t10105_conversion_policy"] ==
        "COPY_PINNED_QUARTERLY_FIXTURE_VALUES_ALREADY_DIVIDED_FROM_SAAR_BY_4_EXACTLY_ONCE" ||
        fail("contract.t10105_conversion_policy", "changed")
    raw["f030_frequency_policy"] ==
        "PRESERVE_SIGNED_2024_ANNUAL_PRODUCER_PRICE_FLOW_WITHOUT_DIVISION_BY_4" ||
        fail("contract.f030_frequency_policy", "changed")
    for key in (
            "forecast_origin_admissible",
            "promotion_ready",
            "model_inventory_vector_emitted",
            "s_s_emitted",
            "model_state_write",
        )
        false_boolean(raw[key], "contract.$key")
    end
    raw["accounting_gate_effect"] == "NONE" ||
        fail("contract.accounting_gate_effect", "must remain NONE")

    resolved_root = dirname(
        joinpath(
            abspath(normpath(String(repo_root))),
            ".inventory-transition-root",
        ),
    )
    artifacts = parse_artifacts(raw["artifact"], resolved_root)
    sources = parse_sources(raw["source"], artifacts)
    blocked = parse_blocked_transitions(raw["blocked_transition"])
    expected = validate_expected_table(raw["expected"])
    rounding = validate_rounding_table(raw["rounding"])
    namespaces = validate_namespaces(raw["namespaces"])
    f030_aggregation =
        validate_f030_aggregation(raw["f030_aggregation"])
    implementation =
        validate_implementation(raw["implementation"], resolved_root)
    Int(expected["observation_count"]) ==
        Int(expected["evidentiary_observation_count"]) +
        Int(expected["non_evidentiary_observation_count"]) ||
        fail("contract.expected", "observation counts do not add")
    Int(expected["blocked_transition_count"]) == length(blocked) ||
        fail("contract.expected", "blocked transition count differs")
    return InventoryTransitionContract(
        contract_path,
        contract_sha256,
        resolved_root,
        nonempty_string(raw["contract_id"], "contract.contract_id"),
        String(raw["classification"]),
        String(raw["promotion_status"]),
        nonempty_string(raw["scientific_role"], "contract.scientific_role"),
        artifacts,
        sources,
        blocked,
        expected,
        rounding,
        namespaces,
        f030_aggregation,
        implementation,
        false,
        false,
        false,
        false,
        false,
        :none,
    )
end

artifact(contract, artifact_id) = contract.artifacts[String(artifact_id)]
source_spec(contract, source_id) = contract.sources[String(source_id)]

function load_source_bundle(contract::InventoryTransitionContract)
    t10105_directory =
        dirname(artifact(contract, "t10105_manifest").path)
    t50805b_directory =
        dirname(artifact(contract, "t50805b_manifest").path)
    after_directory =
        dirname(artifact(contract, "after_redefinitions_manifest").path)
    synthetic_directory =
        dirname(artifact(contract, "synthetic_stage_manifest").path)

    t10105 = load_t10105_fixture(t10105_directory)
    t10105.manifest["transformation"] ==
        "BEA current-dollar seasonally adjusted annual-rate level divided by four exactly once" ||
        fail("t10105", "upstream exact conversion contract changed")
    t10105.manifest["source"]["source_sha256"] ==
        source_spec(contract, "bea_nipa_t10105_cipi").source_sha256 ||
        fail("t10105", "upstream source SHA-256 changed")

    t50805b_fixture = load_bea_inventory_stock_fixture(t50805b_directory)
    t50805b = diagnose_bea_inventory_stocks(t50805b_fixture)
    published_identities_pass(t50805b) ||
        fail("t50805b", "published holder-stock identities fail")
    published_ratios_pass(t50805b) ||
        fail("t50805b", "published ratios fail")
    !t50805b.annual_rate_division_applied ||
        fail("t50805b", "stock level was divided as an annual rate")
    !t50805b.flow_conversion_applied ||
        fail("t50805b", "stock level was converted to a flow")
    t50805b.duplicate_rows_preserved &&
        !t50805b.duplicate_rows_double_counted ||
        fail("t50805b", "published duplicate semantics changed")

    after_fixture = load_after_redefinitions_fixture(after_directory)
    model_core = build_model_core_aggregation(
        after_fixture,
        artifact(contract, "model_core_mapping").path;
        sector_mapping_path = artifact(contract, "sector_mapping").path,
    )
    model_core.year == 2024 ||
        fail("f030", "source year changed")
    model_core.price_basis == :producers_prices ||
        fail("f030", "price basis changed")
    model_core.closure_codes == ["Used", "Other"] ||
        fail("f030", "closure axis changed")
    !model_core.valuation_bridge_applied &&
        !model_core.balancing_applied &&
        !model_core.clipping_applied &&
        !model_core.model_state_write &&
        !model_core.forecast_origin_admissible ||
        fail("f030", "upstream model-core diagnostic is not fail-closed")

    synthetic = load_inventory_stock_fixture(synthetic_directory)
    validate_inventory_stock_ledger(synthetic)
    stage_additivity_pass(synthetic) ||
        fail("synthetic_stage", "synthetic stage identity fails")
    synthetic.manifest["classification"] ==
        "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE" ||
        fail("synthetic_stage", "synthetic evidence role changed")
    return (; t10105, t50805b, after_fixture, model_core, synthetic)
end

function provenance_fields(contract, source_id)
    source = source_spec(contract, source_id)
    manifest = artifact(contract, source.manifest_artifact_id)
    data = artifact(contract, source.data_artifact_id)
    return (
        source,
        manifest_sha256 = manifest.sha256,
        data_sha256 = data.sha256,
    )
end

function make_observation(
        contract,
        source_id;
        record_id,
        source_record_key,
        description,
        reference_period,
        economic_unit,
        holder_namespace = "",
        holder_code = "",
        commodity_namespace = "",
        commodity_code = "",
        stage_namespace = "",
        stage_code = "",
        value,
        cell_state,
    )
    provenance = provenance_fields(contract, source_id)
    source = provenance.source
    number = finite_number(value, "observation.$record_id.value")
    state = nonempty_string(cell_state, "observation.$record_id.cell_state")
    state in ALLOWED_CELL_STATES ||
        fail("observation.$record_id.cell_state", "is unsupported")
    return InventoryEvidenceObservation(
        OBSERVATION_SCHEMA,
        String(record_id),
        String(source_id),
        source.evidence_role,
        String(source_record_key),
        String(description),
        String(reference_period),
        source.stock_flow_class,
        source.frequency,
        source.time_basis,
        source.price_basis,
        source.valuation_basis,
        source.published_rate_basis,
        String(economic_unit),
        String(holder_namespace),
        String(holder_code),
        String(commodity_namespace),
        String(commodity_code),
        String(stage_namespace),
        String(stage_code),
        number,
        state,
        provenance.manifest_sha256,
        provenance.data_sha256,
        source.source_sha256,
        source.source_status,
        false,
    )
end

function build_t10105_observations(contract, source)
    observations = InventoryEvidenceObservation[]
    for row in eachrow(source.frame)
        period = string(row.period)
        push!(
            observations,
            make_observation(
                contract,
                "bea_nipa_t10105_cipi";
                record_id = "t10105_cipi_$period",
                source_record_key = "A014RC|$period",
                description = "Change in private inventories",
                reference_period = period,
                economic_unit = "millions_current_usd_per_quarter",
                holder_namespace =
                    "BEA_NIPA_PRIVATE_INVENTORY_AGGREGATE",
                holder_code = "PRIVATE",
                value = row.nominal_inventory_investment_quarterly,
                cell_state = "SOURCE_NUMERIC_TRANSFORMED_EXACT",
            ),
        )
    end
    return observations
end

function build_t50805b_observations(contract, source)
    observations = InventoryEvidenceObservation[]
    for line_number in source.stock_line_numbers
        item = source.observations[source.observation_index[line_number]]
        line_code = lpad(string(line_number), 3, '0')
        push!(
            observations,
            make_observation(
                contract,
                "bea_nipa_t50805b_holder_stocks";
                record_id = "t50805b_stock_line_$line_code",
                source_record_key =
                    "line=$line_number|series=$(item.series_code)",
                description = item.line_description,
                reference_period = string(item.reference_period),
                economic_unit = "millions_current_usd",
                holder_namespace = "BEA_NIPA_T50805B_HOLDER_LINE",
                holder_code = "L$line_code:$(item.series_code)",
                value = item.numeric_value,
                cell_state = "SOURCE_NUMERIC",
            ),
        )
    end
    return observations
end

function f030_vectors(source)
    final_use_position =
        source.model_core.producer_final_use.column_index["F030"]
    core_values =
        source.model_core.producer_final_use.values[:, final_use_position]
    core_explicit =
        source.model_core.producer_final_use.explicit[:, final_use_position]
    closure_values =
        source.model_core.closure.producer_final_use.values[
        :,
        final_use_position,
    ]
    closure_explicit =
        source.model_core.closure.producer_final_use.explicit[
        :,
        final_use_position,
    ]
    return (; core_values, core_explicit, closure_values, closure_explicit)
end

f030_cell_state(explicit) =
    explicit ? "SOURCE_EXPLICIT_NUMERIC" : "SOURCE_SELECTED_ZERO_NOT_SHOWN"

function build_f030_observations(contract, source)
    vectors = f030_vectors(source)
    observations = InventoryEvidenceObservation[]
    for (position, code) in pairs(source.model_core.model_codes)
        push!(
            observations,
            make_observation(
                contract,
                "bea_after_redefinitions_producer_price_2024_f030";
                record_id = "f030_core_$code",
                source_record_key = "F030|CORE|$code",
                description =
                    "2024 producer-price inventory change for core commodity $code",
                reference_period = "2024",
                economic_unit = "millions_current_usd_per_year",
                commodity_namespace = "BEA_IO_2024_CORE_COMMODITY",
                commodity_code = code,
                value = vectors.core_values[position],
                cell_state =
                    f030_cell_state(vectors.core_explicit[position]),
            ),
        )
    end
    for (position, code) in pairs(source.model_core.closure_codes)
        push!(
            observations,
            make_observation(
                contract,
                "bea_after_redefinitions_producer_price_2024_f030";
                record_id = "f030_closure_$(lowercase(code))",
                source_record_key = "F030|CLOSURE|$code",
                description =
                    "2024 producer-price inventory change for closure commodity $code",
                reference_period = "2024",
                economic_unit = "millions_current_usd_per_year",
                commodity_namespace = "BEA_IO_2024_CLOSURE_COMMODITY",
                commodity_code = code,
                value = vectors.closure_values[position],
                cell_state =
                    f030_cell_state(vectors.closure_explicit[position]),
            ),
        )
    end
    return observations
end

function synthetic_namespaces(item)
    if item.source_id == "census_m3_contract"
        return (
            holder_namespace = "SYNTHETIC_M3_HOLDER",
            holder_code = item.holder_code,
            stage_namespace = "SYNTHETIC_INVENTORY_STAGE",
            stage_code = uppercase(String(item.inventory_stage)),
        )
    elseif item.source_id == "bea_nipa_t50805b_contract"
        return (
            holder_namespace = "SYNTHETIC_PRIVATE_HOLDER",
            holder_code = item.holder_code,
            stage_namespace = "SYNTHETIC_INVENTORY_STAGE",
            stage_code = uppercase(String(item.inventory_stage)),
        )
    end
    return fail("synthetic_stage", "contains an unsupported inner source")
end

function build_synthetic_observations(contract, source)
    observations = InventoryEvidenceObservation[]
    for item in source.observations
        axes = synthetic_namespaces(item)
        push!(
            observations,
            make_observation(
                contract,
                "synthetic_inventory_stage_comparator";
                record_id = "synthetic_$(item.observation_id)",
                source_record_key =
                    "$(item.source_id)|$(item.observation_id)",
                description =
                    "Synthetic non-evidentiary comparator $(item.series_id)",
                reference_period = string(item.reference_period),
                economic_unit = "millions_current_usd",
                holder_namespace = axes.holder_namespace,
                holder_code = axes.holder_code,
                stage_namespace = axes.stage_namespace,
                stage_code = axes.stage_code,
                value = item.value_millions_current_usd,
                cell_state = "SYNTHETIC_NUMERIC",
            ),
        )
    end
    return observations
end

function make_check(
        check_id,
        evidence_role,
        status,
        diagnostic_value,
        tolerance,
        basis,
    )
    diagnostic =
        finite_number(diagnostic_value, "check.$check_id.diagnostic_value")
    allowed =
        finite_number(tolerance, "check.$check_id.tolerance")
    allowed >= 0 || fail("check.$check_id.tolerance", "must be nonnegative")
    abs(diagnostic) <= allowed ||
        fail("check.$check_id", "does not pass its declared tolerance")
    return InventoryEvidenceCheck(
        CHECK_SCHEMA,
        String(check_id),
        String(evidence_role),
        String(status),
        diagnostic,
        abs(diagnostic),
        allowed,
        String(basis),
        false,
        false,
    )
end

function build_checks(contract, source, summary)
    checks = InventoryEvidenceCheck[]
    push!(
        checks,
        make_check(
            "t10105_gpdi_identity_maximum_absolute_residual",
            "SOURCE_INTERNAL_CONTROL",
            "PASS_AT_SOURCE_ROUNDING",
            source.t10105.validation.maximum_investment_residual,
            Float64(source.t10105.manifest["identity_tolerance"]),
            "Maximum absolute quarterly GPDI minus fixed investment minus CIPI residual after the pinned SAAR/4 conversion.",
        ),
    )
    push!(
        checks,
        make_check(
            "t10105_expenditure_identity_maximum_absolute_residual",
            "SOURCE_INTERNAL_CONTROL",
            "PASS_AT_SOURCE_ROUNDING",
            source.t10105.validation.maximum_expenditure_residual,
            Float64(source.t10105.manifest["identity_tolerance"]),
            "Maximum absolute quarterly GDP expenditure residual in the pinned T10105 control fixture.",
        ),
    )
    for residual in source.t50805b.identity_residuals
        push!(
            checks,
            make_check(
                "t50805b_identity_$(residual.identity_id)",
                "SOURCE_INTERNAL_CONTROL",
                "PASS_AT_SOURCE_ROUNDING",
                residual.residual_millions,
                residual.tolerance_millions,
                "Published T50805B holder-stock partition identity; duplicate controls remain addressed by line.",
            ),
        )
    end
    for residual in source.t50805b.ratio_residuals
        push!(
            checks,
            make_check(
                "t50805b_ratio_$(residual.identity_id)",
                "SOURCE_INTERNAL_CONTROL",
                "PASS_AT_SOURCE_ROUNDING",
                residual.residual,
                residual.tolerance,
                "Published T50805B inventory-to-final-sales ratio check; the ratio and denominator rows are excluded from stock evidence.",
            ),
        )
    end
    f030_published =
        source.after_fixture.producer_final_use_column_controls["F030"]
    push!(
        checks,
        make_check(
            "f030_core_plus_closure_to_published_column_control",
            "SOURCE_INTERNAL_CONTROL",
            "PASS_AT_DERIVED_SOURCE_ROUNDING",
            summary.f030_cell_minus_published_control_millions,
            Float64(
                contract.rounding[
                    "f030_cells_to_control_tolerance_millions",
                ],
            ),
            "Signed sum of 73 source cells, after code-keyed retail aggregation to 68 core plus Used/Other closure, minus the separately published F030 column control. The ±37.0 million tolerance is (73 source cells + 1 control) × ±0.5 million. The observed residual is retained without clipping, balancing, or correction.",
        ),
    )
    push!(
        checks,
        make_check(
            "f030_published_control_minus_t10105_2024_aggregate",
            "DERIVED_CROSS_SOURCE_COMPARATOR",
            "PASS_AT_DERIVED_SOURCE_ROUNDING",
            summary.f030_published_control_minus_t10105_2024_millions,
            Float64(
                contract.rounding[
                    "combined_cross_source_tolerance_millions",
                ],
            ),
            "Separately published annual F030 column control minus the sum of four quarterized 2024 T10105 CIPI observations. The ±1.0 million tolerance is the sum of ±0.5 million on the published annual F030 control and four × ±0.125 million after dividing whole-million quarterly SAAR controls by four. The 73-cell derived total is tested separately against the published F030 control with its own ±37.0 million envelope and is not used in this numerator. No correction or allocation is applied.",
        ),
    )
    synthetic_residual = only(source.synthetic.residuals)
    push!(
        checks,
        make_check(
            "synthetic_manufacturing_stage_additivity",
            "SYNTHETIC_NON_EVIDENTIARY_COMPARATOR",
            "PASS_NON_EVIDENTIARY_COMPARATOR",
            synthetic_residual.residual,
            synthetic_residual.tolerance_millions_usd,
            "Synthetic manufacturing total equals synthetic materials plus work-in-process plus finished goods; this is a contract comparator, not empirical transition evidence.",
        ),
    )
    return checks
end

function build_transitions(contract)
    return [
        InventoryTransitionAssessment(
                TRANSITION_SCHEMA,
                specification.transition_id,
                "NOT_RUN_BLOCKED",
                missing,
                missing,
                missing,
                specification.blocker,
                specification.required_evidence,
                specification.basis,
                false,
                false,
                false,
            ) for specification in contract.blocked_transitions
    ]
end

function build_summary(contract, source, observations)
    t10105_values =
        source.t10105.frame.nominal_inventory_investment_quarterly
    t10105_2024 = sum(
        source.t10105.frame.nominal_inventory_investment_quarterly[
            year.(source.t10105.frame.period) .== 2024,
        ],
    )
    vectors = f030_vectors(source)
    f030_core_total = sum(vectors.core_values)
    f030_closure_total = sum(vectors.closure_values)
    evidentiary_count =
        count(item -> item.source_id in EVIDENTIARY_SOURCE_IDS, observations)
    non_evidentiary_count = length(observations) - evidentiary_count
    return InventoryEvidenceSummary(
        length(observations),
        evidentiary_count,
        non_evidentiary_count,
        length(t10105_values),
        count(>(0), t10105_values),
        count(<(0), t10105_values),
        count(iszero, t10105_values),
        source.t10105.validation.maximum_investment_residual,
        source.t10105.validation.maximum_expenditure_residual,
        t10105_2024,
        length(source.t50805b.observations),
        length(source.t50805b.stock_line_numbers),
        length(unique(item.reference_period for item in source.t50805b.observations)),
        source.t50805b.private_inventory_total_millions,
        source.t50805b.duplicate_private_inventory_total_millions,
        length(vectors.core_values),
        length(vectors.closure_values),
        f030_core_total,
        f030_closure_total,
        f030_core_total + f030_closure_total,
        source.after_fixture.producer_final_use_column_controls["F030"],
        f030_core_total +
            f030_closure_total -
            source.after_fixture.producer_final_use_column_controls["F030"],
        count(<(0), vectors.core_values),
        count(<(0), vectors.closure_values),
        count(vectors.core_explicit) + count(vectors.closure_explicit),
        source.after_fixture.producer_final_use_column_controls["F030"] -
            t10105_2024,
        length(source.synthetic.observations),
        0,
        0,
        0,
        0,
        0,
    )
end

function _build_inventory_transition_evidence(contract, source)
    observations = vcat(
        build_t10105_observations(contract, source.t10105),
        build_t50805b_observations(contract, source.t50805b),
        build_f030_observations(contract, source),
        build_synthetic_observations(contract, source.synthetic),
    )
    summary = build_summary(contract, source, observations)
    checks = build_checks(contract, source, summary)
    transitions = build_transitions(contract)
    return InventoryTransitionEvidenceReport(
        REPORT_SCHEMA,
        contract.path,
        contract.sha256,
        contract.classification,
        contract.promotion_status,
        observations,
        checks,
        transitions,
        summary,
        false,
        false,
        false,
        false,
        false,
        :none,
    )
end

observation_payload(item) = (
    schema_version = item.schema_version,
    record_id = item.record_id,
    source_id = item.source_id,
    evidence_role = item.evidence_role,
    source_record_key = item.source_record_key,
    description = item.description,
    reference_period = item.reference_period,
    stock_flow_class = item.stock_flow_class,
    frequency = item.frequency,
    time_basis = item.time_basis,
    price_basis = item.price_basis,
    valuation_basis = item.valuation_basis,
    published_rate_basis = item.published_rate_basis,
    economic_unit = item.economic_unit,
    holder_namespace = item.holder_namespace,
    holder_code = item.holder_code,
    commodity_namespace = item.commodity_namespace,
    commodity_code = item.commodity_code,
    stage_namespace = item.stage_namespace,
    stage_code = item.stage_code,
    value = item.value,
    cell_state = item.cell_state,
    source_manifest_sha256 = item.source_manifest_sha256,
    source_data_sha256 = item.source_data_sha256,
    upstream_source_sha256 = item.upstream_source_sha256,
    source_status = item.source_status,
    forecast_origin_admissible = item.forecast_origin_admissible,
)

check_payload(item) = (
    schema_version = item.schema_version,
    check_id = item.check_id,
    evidence_role = item.evidence_role,
    status = item.status,
    diagnostic_value = item.diagnostic_value,
    absolute_diagnostic_value = item.absolute_diagnostic_value,
    tolerance = item.tolerance,
    basis = item.basis,
    correction_applied = item.correction_applied,
    forecast_origin_admissible = item.forecast_origin_admissible,
)

transition_payload(item) = (
    schema_version = item.schema_version,
    transition_id = item.transition_id,
    status = item.status,
    diagnostic_value = item.diagnostic_value,
    absolute_diagnostic_value = item.absolute_diagnostic_value,
    tolerance = item.tolerance,
    blocker = item.blocker,
    required_evidence = item.required_evidence,
    basis = item.basis,
    mapping_applied = item.mapping_applied,
    model_output_emitted = item.model_output_emitted,
    forecast_origin_admissible = item.forecast_origin_admissible,
)

summary_payload(item) = (
    observation_count = item.observation_count,
    evidentiary_observation_count = item.evidentiary_observation_count,
    non_evidentiary_observation_count =
        item.non_evidentiary_observation_count,
    t10105_period_count = item.t10105_period_count,
    t10105_positive_count = item.t10105_positive_count,
    t10105_negative_count = item.t10105_negative_count,
    t10105_zero_count = item.t10105_zero_count,
    t10105_maximum_gpdi_residual_millions =
        item.t10105_maximum_gpdi_residual_millions,
    t10105_maximum_expenditure_residual_millions =
        item.t10105_maximum_expenditure_residual_millions,
    t10105_2024_total_millions = item.t10105_2024_total_millions,
    t50805b_published_row_count = item.t50805b_published_row_count,
    t50805b_stock_row_count = item.t50805b_stock_row_count,
    t50805b_reference_period_count = item.t50805b_reference_period_count,
    t50805b_private_total_millions = item.t50805b_private_total_millions,
    t50805b_duplicate_total_millions =
        item.t50805b_duplicate_total_millions,
    f030_core_count = item.f030_core_count,
    f030_closure_count = item.f030_closure_count,
    f030_core_total_millions = item.f030_core_total_millions,
    f030_closure_total_millions = item.f030_closure_total_millions,
    f030_core_closure_cell_total_millions =
        item.f030_core_closure_cell_total_millions,
    f030_published_column_control_millions =
        item.f030_published_column_control_millions,
    f030_cell_minus_published_control_millions =
        item.f030_cell_minus_published_control_millions,
    f030_core_negative_count = item.f030_core_negative_count,
    f030_closure_negative_count = item.f030_closure_negative_count,
    f030_explicit_count = item.f030_explicit_count,
    f030_published_control_minus_t10105_2024_millions =
        item.f030_published_control_minus_t10105_2024_millions,
    synthetic_comparator_count = item.synthetic_comparator_count,
    model_vector_output_count = item.model_vector_output_count,
    s_s_output_count = item.s_s_output_count,
    state_write_count = item.state_write_count,
    gate_effect_count = item.gate_effect_count,
    origin_admissible_output_count = item.origin_admissible_output_count,
)

function validate_axis_namespaces(observations, contract)
    allowed_holders = Set(String.(contract.namespaces["holder"]))
    allowed_commodities = Set(String.(contract.namespaces["commodity"]))
    allowed_stages = Set(String.(contract.namespaces["stage"]))
    for item in observations
        holder_present = !isempty(item.holder_namespace)
        commodity_present = !isempty(item.commodity_namespace)
        stage_present = !isempty(item.stage_namespace)
        holder_present == !isempty(item.holder_code) ||
            fail("observation.$(item.record_id)", "holder axis is partial")
        commodity_present == !isempty(item.commodity_code) ||
            fail("observation.$(item.record_id)", "commodity axis is partial")
        stage_present == !isempty(item.stage_code) ||
            fail("observation.$(item.record_id)", "stage axis is partial")
        !holder_present || item.holder_namespace in allowed_holders ||
            fail("observation.$(item.record_id)", "holder namespace is unknown")
        !commodity_present ||
            item.commodity_namespace in allowed_commodities ||
            fail(
            "observation.$(item.record_id)",
            "commodity namespace is unknown",
        )
        !stage_present || item.stage_namespace in allowed_stages ||
            fail("observation.$(item.record_id)", "stage namespace is unknown")

        if item.source_id == "bea_nipa_t10105_cipi"
            holder_present && !commodity_present && !stage_present ||
                fail("observation.$(item.record_id)", "T10105 axes changed")
        elseif item.source_id == "bea_nipa_t50805b_holder_stocks"
            holder_present && !commodity_present && !stage_present ||
                fail("observation.$(item.record_id)", "T50805B axes changed")
        elseif item.source_id ==
                "bea_after_redefinitions_producer_price_2024_f030"
            !holder_present && commodity_present && !stage_present ||
                fail("observation.$(item.record_id)", "F030 axes changed")
        elseif item.source_id == "synthetic_inventory_stage_comparator"
            holder_present && !commodity_present && stage_present ||
                fail("observation.$(item.record_id)", "synthetic axes changed")
        else
            fail("observation.$(item.record_id)", "source is unknown")
        end
        if item.commodity_code == "Other"
            item.commodity_namespace ==
                "BEA_IO_2024_CLOSURE_COMMODITY" ||
                fail(
                "observation.$(item.record_id)",
                "Other crossed out of the closure commodity namespace",
            )
            !holder_present && !stage_present ||
                fail(
                "observation.$(item.record_id)",
                "Other collided with a holder or stage namespace",
            )
        end
    end
    count(item -> item.commodity_code == "Other", observations) == 1 ||
        fail("observations", "must contain exactly one qualified Other commodity")
    return nothing
end

function validate_observation_provenance(observations, contract)
    for item in observations
        item.schema_version == OBSERVATION_SCHEMA ||
            fail("observation.$(item.record_id)", "schema changed")
        isfinite(item.value) ||
            fail("observation.$(item.record_id)", "value is nonfinite")
        item.cell_state in ALLOWED_CELL_STATES ||
            fail("observation.$(item.record_id)", "cell state changed")
        item.forecast_origin_admissible &&
            fail("observation.$(item.record_id)", "cannot admit an origin")
        source = source_spec(contract, item.source_id)
        item.evidence_role == source.evidence_role ||
            fail("observation.$(item.record_id)", "evidence role changed")
        item.source_status == source.source_status ||
            fail("observation.$(item.record_id)", "source status changed")
        item.stock_flow_class == source.stock_flow_class ||
            fail("observation.$(item.record_id)", "stock/flow class changed")
        item.frequency == source.frequency ||
            fail("observation.$(item.record_id)", "frequency changed")
        item.time_basis == source.time_basis ||
            fail("observation.$(item.record_id)", "time basis changed")
        item.price_basis == source.price_basis ||
            fail("observation.$(item.record_id)", "price basis changed")
        item.valuation_basis == source.valuation_basis ||
            fail("observation.$(item.record_id)", "valuation basis changed")
        item.published_rate_basis == source.published_rate_basis ||
            fail("observation.$(item.record_id)", "rate basis changed")
        item.source_manifest_sha256 ==
            artifact(contract, source.manifest_artifact_id).sha256 ||
            fail("observation.$(item.record_id)", "manifest provenance changed")
        item.source_data_sha256 ==
            artifact(contract, source.data_artifact_id).sha256 ||
            fail("observation.$(item.record_id)", "data provenance changed")
        item.upstream_source_sha256 == source.source_sha256 ||
            fail("observation.$(item.record_id)", "source provenance changed")
    end
    return nothing
end

function expected_summary_matches(summary, expected)
    payload = summary_payload(summary)
    return all(
        getproperty(payload, Symbol(key)) == value
            for (key, value) in expected if
            hasproperty(payload, Symbol(key))
    )
end

function validate_inventory_transition_evidence(
        report::InventoryTransitionEvidenceReport,
        contract::InventoryTransitionContract;
        source_bundle = nothing,
    )
    report.schema_version == REPORT_SCHEMA ||
        fail("report.schema_version", "is unsupported")
    report.contract_path == contract.path ||
        fail("report.contract_path", "changed")
    report.contract_sha256 == contract.sha256 ||
        fail("report.contract_sha256", "changed")
    report.classification == contract.classification ||
        fail("report.classification", "changed")
    report.promotion_status == contract.promotion_status ||
        fail("report.promotion_status", "changed")
    for (value, location) in (
            (report.forecast_origin_admissible, "report.forecast_origin_admissible"),
            (report.promotion_ready, "report.promotion_ready"),
            (
                report.model_inventory_vector_emitted,
                "report.model_inventory_vector_emitted",
            ),
            (report.s_s_emitted, "report.s_s_emitted"),
            (report.model_state_write, "report.model_state_write"),
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
        fail("report.observations", "record identifiers duplicate")
    length(
        unique(
            (item.source_id, item.source_record_key)
                for item in report.observations
        ),
    ) == length(report.observations) ||
        fail("report.observations", "source record keys duplicate")
    validate_axis_namespaces(report.observations, contract)
    validate_observation_provenance(report.observations, contract)

    length(report.checks) == Int(contract.expected["source_check_count"]) ||
        fail("report.checks", "count changed")
    length(unique(getfield.(report.checks, :check_id))) ==
        length(report.checks) ||
        fail("report.checks", "identifiers duplicate")
    for check in report.checks
        check.schema_version == CHECK_SCHEMA ||
            fail("check.$(check.check_id)", "schema changed")
        check.absolute_diagnostic_value == abs(check.diagnostic_value) ||
            fail("check.$(check.check_id)", "absolute value changed")
        check.tolerance >= 0 && isfinite(check.tolerance) ||
            fail("check.$(check.check_id)", "tolerance is invalid")
        abs(check.diagnostic_value) <= check.tolerance ||
            fail("check.$(check.check_id)", "does not pass")
        check.correction_applied &&
            fail("check.$(check.check_id)", "cannot apply a correction")
        check.forecast_origin_admissible &&
            fail("check.$(check.check_id)", "cannot admit an origin")
    end

    length(report.transitions) ==
        Int(contract.expected["blocked_transition_count"]) ||
        fail("report.transitions", "count changed")
    getfield.(report.transitions, :transition_id) ==
        EXPECTED_TRANSITION_IDS ||
        fail("report.transitions", "identifier order changed")
    for transition in report.transitions
        transition.schema_version == TRANSITION_SCHEMA ||
            fail("transition.$(transition.transition_id)", "schema changed")
        transition.status == "NOT_RUN_BLOCKED" ||
            fail(
            "transition.$(transition.transition_id)",
            "must remain NOT_RUN_BLOCKED",
        )
        ismissing(transition.diagnostic_value) ||
            fail(
            "transition.$(transition.transition_id)",
            "diagnostic must be structurally missing",
        )
        ismissing(transition.absolute_diagnostic_value) ||
            fail(
            "transition.$(transition.transition_id)",
            "absolute diagnostic must be structurally missing",
        )
        ismissing(transition.tolerance) ||
            fail(
            "transition.$(transition.transition_id)",
            "tolerance must be structurally missing",
        )
        transition.mapping_applied &&
            fail("transition.$(transition.transition_id)", "mapping claimed")
        transition.model_output_emitted &&
            fail(
            "transition.$(transition.transition_id)",
            "model output claimed",
        )
        transition.forecast_origin_admissible &&
            fail("transition.$(transition.transition_id)", "origin claimed")
    end

    expected_summary_matches(report.summary, contract.expected) ||
        fail("report.summary", "differs from the frozen contract")
    report.summary.model_vector_output_count == 0 ||
        fail("report.summary", "model vector output is nonzero")
    report.summary.s_s_output_count == 0 ||
        fail("report.summary", "S_s output is nonzero")
    report.summary.state_write_count == 0 ||
        fail("report.summary", "state-write output is nonzero")
    report.summary.gate_effect_count == 0 ||
        fail("report.summary", "gate effect output is nonzero")
    report.summary.origin_admissible_output_count == 0 ||
        fail("report.summary", "origin output is nonzero")

    source =
        source_bundle === nothing ? load_source_bundle(contract) : source_bundle
    expected_report = _build_inventory_transition_evidence(contract, source)
    observation_payload.(report.observations) ==
        observation_payload.(expected_report.observations) ||
        fail("report.observations", "differ from pinned source reconstruction")
    check_payload.(report.checks) == check_payload.(expected_report.checks) ||
        fail("report.checks", "differ from pinned source reconstruction")
    isequal(
        transition_payload.(report.transitions),
        transition_payload.(expected_report.transitions),
    ) ||
        fail("report.transitions", "differ from the frozen blocker contract")
    summary_payload(report.summary) ==
        summary_payload(expected_report.summary) ||
        fail("report.summary", "differs from pinned source reconstruction")
    return report
end

function build_inventory_transition_evidence(
        contract::InventoryTransitionContract =
            load_inventory_transition_contract(),
    )
    source = load_source_bundle(contract)
    report = _build_inventory_transition_evidence(contract, source)
    return validate_inventory_transition_evidence(
        report,
        contract;
        source_bundle = source,
    )
end

function reject_stock_difference_equals_cipi(
        ::InventoryTransitionEvidenceReport,
    )
    throw(
        ArgumentError(
            "stock difference = CIPI is NOT_RUN_BLOCKED: the pinned ledger has one T50805B end-of-quarter stock period and no revaluation, physical-volume, or average-quarter/end-quarter timing terms",
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
        "observations_csv" => "inventory_evidence_observations.csv",
        "observations_csv_sha256" => hashes.observations,
        "source_check_count" => length(report.checks),
        "source_checks_csv" => "inventory_source_checks.csv",
        "source_checks_csv_sha256" => hashes.checks,
        "blocked_transition_count" => length(report.transitions),
        "transition_assessments_csv" =>
            "inventory_transition_assessments.csv",
        "transition_assessments_csv_sha256" => hashes.transitions,
        "summary" => Dict{String, Any}(
            String(key) => value
                for (key, value) in pairs(summary_payload(report.summary))
        ),
        "rounding" => deepcopy(contract.rounding),
        "implementation" => deepcopy(contract.implementation),
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
        "missing_value_policy" =>
            "ABSENT_IS_STRUCTURALLY_MISSING_NOT_NUMERIC_ZERO",
        "cross_source_correction_applied" => false,
        "forecast_origin_admissible" => false,
        "promotion_ready" => false,
        "model_inventory_vector_emitted" => false,
        "s_s_emitted" => false,
        "model_state_write" => false,
        "accounting_gate_effect" => "NONE",
    )
end

function write_inventory_transition_evidence(
        report::InventoryTransitionEvidenceReport,
        contract::InventoryTransitionContract,
        output_directory::AbstractString,
    )
    validate_inventory_transition_evidence(report, contract)
    target = abspath(normpath(String(output_directory)))
    ispath(target) &&
        fail("output_directory", "refusing to overwrite existing path $target")
    parent = dirname(target)
    mkpath(parent)
    temporary = mktempdir(parent)
    observations_path =
        joinpath(temporary, "inventory_evidence_observations.csv")
    checks_path = joinpath(temporary, "inventory_source_checks.csv")
    transitions_path =
        joinpath(temporary, "inventory_transition_assessments.csv")
    manifest_path = joinpath(temporary, "manifest.toml")
    try
        CSV.write(
            observations_path,
            observation_payload.(report.observations),
        )
        CSV.write(checks_path, check_payload.(report.checks))
        CSV.write(
            transitions_path,
            transition_payload.(report.transitions),
        )
        hashes = (
            observations = file_sha256(observations_path),
            checks = file_sha256(checks_path),
            transitions = file_sha256(transitions_path),
        )
        manifest = report_manifest(report, contract, hashes)
        open(manifest_path, "w") do io
            TOML.print(io, manifest; sorted = true)
        end
        mv(temporary, target)
    finally
        isdir(temporary) && rm(temporary; recursive = true)
    end
    installed_observations =
        joinpath(target, "inventory_evidence_observations.csv")
    installed_checks = joinpath(target, "inventory_source_checks.csv")
    installed_transitions =
        joinpath(target, "inventory_transition_assessments.csv")
    installed_manifest = joinpath(target, "manifest.toml")
    return (
        directory = target,
        observation_count = length(report.observations),
        source_check_count = length(report.checks),
        blocked_transition_count = length(report.transitions),
        observations_sha256 = file_sha256(installed_observations),
        checks_sha256 = file_sha256(installed_checks),
        transitions_sha256 = file_sha256(installed_transitions),
        manifest_sha256 = file_sha256(installed_manifest),
    )
end

end # module
