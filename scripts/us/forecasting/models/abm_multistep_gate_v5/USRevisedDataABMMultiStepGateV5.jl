module USRevisedDataABMMultiStepGateV5

using Random
using SHA
using TOML

export ABMMultiStepGateV5Error,
    MultiStepExecutionCounts,
    MultiStepGateV5Result,
    MultiStepPathResult,
    RawFourQuarterGDPOperators,
    RawFourQuarterGDPLevels,
    attempt_execution_counts,
    compute_raw_four_quarter_operators,
    construct_fresh_with_seed,
    multi_step_path_set_sha256,
    protocol_sha256,
    refuse_prohibited_action,
    run_installed_multi_step_gate,
    serial_four_step_collect_with_seed!,
    validate_protocol,
    validate_protocol_semantics,
    validate_source_pins,
    validate_synthetic_formula_oracle

const REPOSITORY_ROOT = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", ".."),
)
const V4_MODULE_PATH = joinpath(
    REPOSITORY_ROOT,
    "scripts",
    "us",
    "forecasting",
    "diagnostics",
    "USRevisedDataABMOneStepGateV4.jl",
)
const V4_MODULE_SHA256 =
    "ab16f7a0fb9abe6fc0d066d2b8649e816155f0c34375a8cab7adb8af80233e5b"

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function include_pinned_v4()
    isfile(V4_MODULE_PATH) || error("accepted v4 module is missing")
    islink(V4_MODULE_PATH) &&
        error("accepted v4 module must not be a symbolic link")
    bytes = read(V4_MODULE_PATH)
    sha256_hex(bytes) == V4_MODULE_SHA256 ||
        error("accepted v4 module SHA-256 changed")
    loaded = Base.include_string(@__MODULE__, String(bytes), V4_MODULE_PATH)
    loaded isa Module || error("accepted v4 include did not return a module")
    return loaded
end

const V4 = include_pinned_v4()
const V3 = V4.V3
const SyntheticOperator = V4.SyntheticOperator

const SCHEMA_VERSION =
    "beforeit-us-revised-data-abm-multi-step-gate.v5"
const CONTRACT_ID =
    "beforeit-us-revised-data-abm-base-four-quarter-qualification.v5"
const INFORMATION_TRACK = "revised_mixed_vintage"
const DIAGNOSTIC_CLASS =
    "quarantined_four_quarter_free_running_software_qualification"
const MODEL_VARIANT = "base"
const MODEL_CONSTRUCTOR_ID = "BeforeIT.Model"
const ORIGIN_PERIOD = "2026Q1"
const TARGET_PERIODS = ["2026Q2", "2026Q3", "2026Q4", "2027Q1"]
const ALL_PERIODS = [ORIGIN_PERIOD; TARGET_PERIODS]
const HORIZONS = collect(1:4)
const HORIZON_MEASUREMENT_BASIS = [
    "model_implied_opening_to_post_step_flow",
    "post_step_flow_to_post_step_flow",
    "post_step_flow_to_post_step_flow",
    "post_step_flow_to_post_step_flow",
]
const PATH_COUNT = 32
const MASTER_SEED = 20260807
const SEED_NAMESPACE_EXPERIMENT_ID = "us-abm-constructor-gate-v3"
const SEED_NAMESPACE_DISPOSITION =
    "inherited_exactly_from_accepted_v4_for_h1_prefix_continuity"
const MODEL_ID = "beforeit-us-abm-base"
const PATH_KIND =
    "RAW_MODEL_UNCORRECTED_REVISED_MIXED_VINTAGE_DIAGNOSTIC"
const V4_TEST_SHA256 =
    "dd104d943f23b408d0d223938ec5b7ad8c0169ec07656cff055d97c03116a2a9"
const V4_PROTOCOL_SHA256 =
    "d15fdef2c5fa7142c7658318d2bd726953b9a4569f3f7d50762e14965f9c3ef7"
const V4_README_SHA256 =
    "b1f4bc13f9e313186eeddea38f1da685ed0691c5025c53d6c12b9710cac84e17"
const V4_ACCEPTED_RESULT_SHA256 =
    "1ac4efc78236d0dfafb11d78b35597b1106cd374488b4f0c9ddf8fd70b1782a2"
const V4_ONE_STEP_PATH_SET_SHA256 =
    "a9e8e6c9d22e5284d163da21477d8726a663590e2e8e3735e54018daac671199"
const V4_OPENING_FINGERPRINT_SET_SHA256 =
    "2f359965fa08785101870a46332cdd66c91e744a664e9803fc198ef53e024a18"
const V4_PATH_ONE_H1_POST_COLLECTION_SHA256 =
    "ce48b0f392ea3be58f392d8be77c647e5e5738dd841194af9422ca5608d5a525"
const V2_QUALIFIED_INPUT_SHA256 = V4.V2_QUALIFIED_INPUT_SHA256
const V2_SEED_PLAN_SHA256 = V4.V2_SEED_PLAN_SHA256
const METHOD_ORIGIN_SHA256 = V4.ONE_STEP_METHOD_ORIGIN_SHA256
const SIDE_DATA_MANIFEST_SHA256 = V4.SIDE_DATA_MANIFEST_SHA256
const SELECTIVE_DECODE_CONTRACT = V4.SELECTIVE_DECODE_CONTRACT
const EXECUTION_COUNT_SCOPE =
    "gate_owned_calls_after_beforeit_require_excludes_package_import_precompile_and_pure_oracle_calls"
const ZERO_SHA256 = repeat("0", 64)
const EXPECTED_MULTI_STEP_PATH_SET_SHA256 =
    "33294f6f1eb3a98b2cfb4184b95adae44673b3de8fb1c64638bcb9af58f9a7b3"
const EXPECTED_PATH_ONE_H4_POST_COLLECTION_SHA256 =
    "85a4ebd2a11c73713b9e43c63db71dd732eb2332d0130b19e0eaf921e833819f"
const EXPECTED_MULTI_STEP_EXECUTION_ENVELOPE_SHA256 =
    "6b52a0fa8d1b0548dd51d9930d34df74290bc33d9d1654ecf9d32d4c1265b0de"
const EXPECTED_RESULT_SHA256 =
    "736ac1683df46f1ef856375ef8036b6ab6b8e858fbfd84fc7a366e879855d9b4"

const PROTOCOL_PATH = joinpath(@__DIR__, "abm_multi_step_gate_v5.toml")
const PROTOCOL_SHA256 =
    "e3f18b132ac65b2c3f985d17e6b850ae3fef4572047b0893acaca2d0f8132ac8"

const PRIMARY_PATH_ORDER = collect(1:PATH_COUNT)
const REVERSE_PATH_ORDER = reverse(PRIMARY_PATH_ORDER)
const REPLAY_PATH_IDS = [1]
const CONSTRUCTION_SEEDS = copy(V4.CONSTRUCTION_SEEDS)
const SIMULATION_SEEDS = copy(V4.SIMULATION_SEEDS)

const EXECUTION_COUNTS = Dict{String, Int}(
    "primary_constructions" => 32,
    "primary_steps" => 128,
    "primary_constructor_opening_collections" => 32,
    "primary_post_step_collections" => 128,
    "primary_total_collection_events" => 160,
    "reverse_constructions" => 32,
    "reverse_steps" => 128,
    "reverse_constructor_opening_collections" => 32,
    "reverse_post_step_collections" => 128,
    "reverse_total_collection_events" => 160,
    "replay_constructions" => 1,
    "replay_steps" => 4,
    "replay_constructor_opening_collections" => 1,
    "replay_post_step_collections" => 4,
    "replay_total_collection_events" => 5,
    "total_constructions" => 65,
    "total_steps" => 260,
    "total_constructor_opening_collections" => 65,
    "total_post_step_collections" => 260,
    "total_collection_events" => 325,
)

const TRUE_DECLARATIONS = Set(
    [
        "diagnostic_only",
        "runner_implemented",
        "revised_mixed_vintage",
        "model_constructed",
        "model_stepped_four_times_per_construction",
        "software_four_quarter_path_verified",
        "free_running_without_intermediate_reanchoring",
        "raw_rows_one_through_five_preserved",
        "pathwise_h1_through_h4_operators_computed",
        "opening_row_is_model_implied_unanchored",
        "path_order_invariance_executed",
        "same_seed_replay_executed",
        "v4_h1_prefix_continuity_verified",
        "v4_acceptance_relied_upon_only_for_pinned_dependencies",
        "v2_raw_requalification_performed",
        "synthetic_formula_oracle_used_only_on_pure_fixture",
        "raw_diagnostic_path_values_returned",
        "measurement_basis_discontinuity_preserved",
        "truth_bearing_metadata_present_in_pinned_artifact",
        "truth_bearing_raw_artifact_bytes_hashed",
        "us_nowcast_parameters_initial_conditions_selectively_deserialized",
        "package_import_side_data_deserialized",
        "package_import_side_data_attested",
        "package_precompile_workload_execution_guard_attested",
        "precompiletools_clean_bootstrap_verified",
        "precompiletools_verbose_false",
        "ephemeral_jld2_snapshot_written",
    ]
)
const FALSE_DECLARATIONS = Set(
    [
        "opening_row_is_official_truth",
        "opening_macro_controls_used",
        "v4_runner_reexecuted",
        "truth_bearing_metadata_deserialized",
        "truth_values_consumed_by_model_or_operator",
        "truth_values_used_for_scoring",
        "us_evaluation_truth_used",
        "package_import_side_data_passed_to_v5_constructor_or_gdp_operator",
        "package_precompile_workload_executed",
        "zero_filesystem_writes_claimed",
        "independent_streams_established",
        "input_lineage_verified",
        "source_period_labels_authenticated",
        "empirical_forecast_validated",
        "forecast_artifact_emitted",
        "forecast_artifact_serialized",
        "score_computed",
        "inference_run",
        "origin_admissible",
        "registry_write_allowed",
        "promotion_eligible",
        "class_h_allowed",
        "production_allowed",
        "reanchoring_used",
        "bridge_adjustment_used",
        "tier1_operator_approved",
        "full_runtime_attestation",
    ]
)

const TRUE_ATTESTATION_LIMITS = Set(
    [
        "accepted_v4_bytes_pinned",
        "repository_source_closure_validated",
        "manifest_source_trees_validated",
        "package_entrypoints_preresolved",
        "effective_load_path_attested",
        "effective_depot_path_enumerated",
        "artifact_overrides_required_absent",
        "method_origins_rechecked_after_execution",
        "package_import_side_data_attested",
        "compiled_modules_disabled",
        "pkgimages_disabled",
        "generating_output_required_false",
        "package_precompile_workload_execution_guard_attested",
        "precompiletools_clean_bootstrap_verified",
        "precompiletools_verbose_required_false",
    ]
)
const FALSE_ATTESTATION_LIMITS = Set(
    [
        "binary_artifacts_attested",
        "binary_jll_payloads_attested",
        "compiled_caches_attested",
        "depot_contents_attested",
        "global_preferences_attested",
        "julia_executable_bytes_attested",
        "sysimage_bytes_attested",
        "same_user_filesystem_race_resistance_attested",
        "official_concept_bridge_validated",
        "historical_origin_validated",
        "empirical_accuracy_established",
    ]
)

const BLOCKERS = [
    "REVISED_MIXED_VINTAGE_ORIGIN_NONADMISSIBLE",
    "HISTORICAL_ORIGIN_COUNT_ZERO",
    "US_EVALUATION_TRUTH_NOT_USED",
    "EMPIRICAL_FORECAST_NOT_VALIDATED",
    "OFFICIAL_CONCEPT_BRIDGE_UNVALIDATED",
    "INDEPENDENT_RNG_STREAMS_NOT_ESTABLISHED",
    "OPENING_MEASUREMENT_BASIS_DISCONTINUITY_PRESERVED",
    "FULL_RUNTIME_ATTESTATION_NOT_ESTABLISHED",
    "TIER1_PROMOTION_FORBIDDEN",
]

const PROHIBITED_ACTION_LIST = [
    :truth_access,
    :emit_forecast,
    :serialize_forecast,
    :score,
    :inference,
    :origin_admission,
    :registry_write,
    :promotion,
    :class_h,
    :production,
    :reanchor,
    :bridge_adjust,
]
const PROHIBITED_ACTIONS = Set(PROHIBITED_ACTION_LIST)

const DIRECT_PIN_HASHES = Dict(
    "scripts/us/forecasting/diagnostics/USRevisedDataABMOneStepGateV4.jl" =>
        V4_MODULE_SHA256,
    "scripts/us/forecasting/diagnostics/test_revised_data_abm_one_step_gate_v4.jl" =>
        V4_TEST_SHA256,
    "scripts/us/forecasting/diagnostics/revised_data/abm_one_step_gate_v4.toml" =>
        V4_PROTOCOL_SHA256,
    "scripts/us/forecasting/diagnostics/revised_data/ABM_ONE_STEP_GATE_V4.md" =>
        V4_README_SHA256,
    "scripts/us/forecasting/diagnostics/USRevisedDataABMConstructorGateV3.jl" =>
        V4.V3_MODULE_SHA256,
    "scripts/us/forecasting/diagnostics/revised_data/abm_constructor_gate_v3.toml" =>
        V4.V3_PROTOCOL_SHA256,
    "scripts/us/forecasting/diagnostics/USRevisedDataABMOriginFirewallV2.jl" =>
        "817910109d03c8f0cbadd2c8f91dc55f28eda4051ef42993a2377f71d7dd34e3",
    "scripts/us/forecasting/diagnostics/revised_data/abm_origin_firewall_v2.toml" =>
        V4.V2_PROTOCOL_SHA256,
    "scripts/us/forecasting/targets/abm_gdp_operator/USABMGDPOperatorQualification.jl" =>
        V4.OPERATOR_MODULE_SHA256,
    "scripts/us/forecasting/targets/abm_gdp_operator/operator_qualification.toml" =>
        V4.OPERATOR_PROTOCOL_SHA256,
    "data/us/baselines/US_2026Q1_nowcast.jld2" =>
        "eb8d28f6b2aef9b36cf294be8906d2d5481f1c8db66ea3d034b1a96f9194b0de",
    "scripts/us/Project.toml" =>
        "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c",
    "scripts/us/Manifest.toml" =>
        "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263",
    "src/one_step.jl" =>
        "1446053cf507aeb76263114c7a721a1377b787657829ff28409318173d19f905",
    "src/utils/data.jl" =>
        "3b42bcc124e5242c2a9b7303d9feddbfa7d6e54b07e62961ef646bf06ff8b5b8",
    "src/shocks/shocks.jl" =>
        "80ed969e8af62a29c894023356efbffc04bc00585aae977fe60c17e0e6e0c0d6",
    "src/agent_actions/aggregates.jl" =>
        "b8839ce9a624e25c94b1d039747dbd3cb882a4bb4efa4187642631544b440843",
    "data/austria/parameters/2010Q1.jld2" =>
        "137b9b6c9968b902704026751390cbb93666768bf5b8a92dcb8782e465c257a2",
    "data/austria/initial_conditions/2010Q1.jld2" =>
        "b47bdcb8cd36e2b57869f25a85bc6ab730feeccb3cd8dac236bf6807545fd087",
    "data/italy/parameters/2010Q1.jld2" =>
        "e687fe848061f0c1847faadb723a0f370e45f7a555eba95e11b85dc58af93113",
    "data/italy/initial_conditions/2010Q1.jld2" =>
        "45660c8d3fcc2443cd510dbfcbc395b7f5a0607b4f5e1b75d5b35f820dd911f9",
    "data/steady_state/parameters/2010Q1.jld2" =>
        "9204c044442d7f0f209aee957a5e11828939538bfd3e3bc8cc419237f73fcf85",
    "data/steady_state/initial_conditions/2010Q1.jld2" =>
        "4b402e9d3e9aa5efc166e853be529a0ce09a40cce9033b6907f1c452582a923d",
    "data/italy/calibration/calibration/2010Q1.jld2" =>
        "49dc1a59ab9e73547463108556ca8bc1b30c72130365c63d7ca1cb49e84e276e",
    "data/italy/calibration/figaro/2010.jld2" =>
        "963de7c2fe2d2e89ae15a165ccea800d8af42380d9133eb2d310de588c19e1e6",
    "data/italy/calibration/data/1996.jld2" =>
        "8fc52d9741af911cb035584f3df0fbcff4ae4487ed502b7470ce04a8402ef09f",
    "data/italy/calibration/ea/1996.jld2" =>
        "2a60c7b7edeb00a08c6c2d03b7ecf71d7ad8e9f4ca15da9844f906ba851c8f3d",
)

struct ABMMultiStepGateV5Error <: Exception
    message::String
end

Base.showerror(io::IO, error::ABMMultiStepGateV5Error) =
    print(io, error.message)

fail(message) = throw(ABMMultiStepGateV5Error(String(message)))

struct RawFourQuarterGDPLevels
    nominal_gdp::Vector{Float64}
    real_gdp::Vector{Float64}

    function RawFourQuarterGDPLevels(nominal_gdp, real_gdp)
        typeof(nominal_gdp) === Vector{Float64} ||
            fail("nominal_gdp must be exactly Vector{Float64}")
        typeof(real_gdp) === Vector{Float64} ||
            fail("real_gdp must be exactly Vector{Float64}")
        return new(nominal_gdp, real_gdp)
    end
end

struct RawFourQuarterGDPOperators
    real_gdp_growth::Vector{Float64}
    gdp_deflator_inflation::Vector{Float64}
end

mutable struct PhaseCounter
    constructions::Int
    steps::Int
    constructor_opening_collections::Int
    post_step_collections::Int
end

PhaseCounter() = PhaseCounter(0, 0, 0, 0)

mutable struct AttemptCounters
    primary::PhaseCounter
    reverse::PhaseCounter
    replay::PhaseCounter
end

AttemptCounters() =
    AttemptCounters(PhaseCounter(), PhaseCounter(), PhaseCounter())

struct MultiStepExecutionCounts
    primary_constructions::Int
    primary_steps::Int
    primary_constructor_opening_collections::Int
    primary_post_step_collections::Int
    primary_total_collection_events::Int
    reverse_constructions::Int
    reverse_steps::Int
    reverse_constructor_opening_collections::Int
    reverse_post_step_collections::Int
    reverse_total_collection_events::Int
    replay_constructions::Int
    replay_steps::Int
    replay_constructor_opening_collections::Int
    replay_post_step_collections::Int
    replay_total_collection_events::Int
    total_constructions::Int
    total_steps::Int
    total_constructor_opening_collections::Int
    total_post_step_collections::Int
    total_collection_events::Int
end

struct MultiStepPathResult
    path_id::Int
    construction_seed::Int
    simulation_seed::Int
    origin_period::String
    target_periods::Vector{String}
    horizons::Vector{Int}
    collection_time::Vector{Int}
    nominal_gdp_levels::Vector{Float64}
    real_gdp_levels::Vector{Float64}
    real_gdp_growth::Vector{Float64}
    gdp_deflator_inflation::Vector{Float64}
    opening_state_sha256::String
    post_step_state_sha256::Vector{String}
    post_collection_state_sha256::Vector{String}
    input_parameter_sha256::String
    input_initial_conditions_sha256::String
    input_hashes_unchanged::Bool
    numeric_values_checked_after_collection::Vector{Int}
end

Base.@kwdef struct MultiStepGateV5Result
    schema_version::String
    contract_id::String
    information_track::String
    protocol_sha256::String
    v4_module_sha256::String
    v4_protocol_sha256::String
    v4_accepted_result_sha256::String
    v4_runner_reexecuted::Bool
    v2_protocol_sha256::String
    qualified_input_sha256::String
    seed_plan_sha256::String
    synthetic_operator_module_sha256::String
    synthetic_operator_protocol_sha256::String
    synthetic_formula_oracle_sha256::String
    dependency_source_tree_count::Int
    dependency_source_tree_digest::String
    package_entrypoint_count::Int
    package_entrypoint_digest::String
    symbolic_load_path_sha256::String
    expanded_load_path_sha256::String
    depot_path_count::Int
    depot_paths_sha256::String
    v3_execution_envelope_sha256::String
    multi_step_execution_envelope_sha256::String
    package_import_side_data_manifest_sha256::String
    selective_decode_contract::String
    constructor_method_origin_sha256::String
    multi_step_method_origin_sha256::String
    compiled_modules_disabled::Bool
    pkgimages_disabled::Bool
    generating_output::Bool
    execution_count_scope::String
    horizon_measurement_basis::Vector{String}
    execution_counts::MultiStepExecutionCounts
    primary_paths::Vector{MultiStepPathResult}
    reverse_paths::Vector{MultiStepPathResult}
    replay_path::MultiStepPathResult
    multi_step_path_set_sha256::String
    v4_h1_prefix_path_set_sha256::String
    opening_fingerprint_set_sha256::String
    deterministic_replay_equal::Bool
    path_order_invariant::Bool
    input_hashes_unchanged::Bool
    software_four_quarter_path_verified::Bool
    free_running_without_intermediate_reanchoring::Bool
    raw_diagnostic_path_values_returned::Bool
    measurement_basis_discontinuity_preserved::Bool
    truth_bearing_metadata_present_in_pinned_artifact::Bool
    truth_bearing_raw_artifact_bytes_hashed::Bool
    truth_bearing_metadata_deserialized::Bool
    truth_values_consumed_by_model_or_operator::Bool
    truth_values_used_for_scoring::Bool
    us_evaluation_truth_used::Bool
    us_nowcast_parameters_initial_conditions_selectively_deserialized::Bool
    package_import_side_data_deserialized::Bool
    package_import_side_data_attested::Bool
    package_import_side_data_passed_to_v5_constructor_or_gdp_operator::Bool
    package_precompile_workload_execution_guard_attested::Bool
    package_precompile_workload_executed::Bool
    precompiletools_clean_bootstrap_verified::Bool
    precompiletools_verbose_false::Bool
    ephemeral_jld2_snapshot_written::Bool
    zero_filesystem_writes_claimed::Bool
    independent_streams_established::Bool
    input_lineage_verified::Bool
    source_period_labels_authenticated::Bool
    empirical_forecast_validated::Bool
    forecast_artifact_emitted::Bool
    forecast_artifact_serialized::Bool
    score_computed::Bool
    inference_run::Bool
    origin_admissible::Bool
    registry_write_allowed::Bool
    promotion_eligible::Bool
    class_h_allowed::Bool
    production_allowed::Bool
    reanchoring_used::Bool
    bridge_adjustment_used::Bool
    diagnostic_only::Bool
    full_runtime_attestation::Bool
    result_sha256::String
end

const LAST_ATTEMPT_COUNTERS = Ref(AttemptCounters())

function execution_counts(counters::AttemptCounters)
    primary_events =
        counters.primary.constructor_opening_collections +
        counters.primary.post_step_collections
    reverse_events =
        counters.reverse.constructor_opening_collections +
        counters.reverse.post_step_collections
    replay_events =
        counters.replay.constructor_opening_collections +
        counters.replay.post_step_collections
    return MultiStepExecutionCounts(
        counters.primary.constructions,
        counters.primary.steps,
        counters.primary.constructor_opening_collections,
        counters.primary.post_step_collections,
        primary_events,
        counters.reverse.constructions,
        counters.reverse.steps,
        counters.reverse.constructor_opening_collections,
        counters.reverse.post_step_collections,
        reverse_events,
        counters.replay.constructions,
        counters.replay.steps,
        counters.replay.constructor_opening_collections,
        counters.replay.post_step_collections,
        replay_events,
        counters.primary.constructions +
            counters.reverse.constructions +
            counters.replay.constructions,
        counters.primary.steps +
            counters.reverse.steps +
            counters.replay.steps,
        counters.primary.constructor_opening_collections +
            counters.reverse.constructor_opening_collections +
            counters.replay.constructor_opening_collections,
        counters.primary.post_step_collections +
            counters.reverse.post_step_collections +
            counters.replay.post_step_collections,
        primary_events + reverse_events + replay_events,
    )
end

attempt_execution_counts() = execution_counts(LAST_ATTEMPT_COUNTERS[])

function struct_payload(value)
    return Dict(
        String(field) => getfield(value, field) for
            field in fieldnames(typeof(value))
    )
end

function base_canonical_value(value)
    if value isa RawFourQuarterGDPLevels ||
            value isa RawFourQuarterGDPOperators ||
            value isa MultiStepExecutionCounts ||
            value isa MultiStepPathResult ||
            value isa MultiStepGateV5Result
        return base_canonical_value(struct_payload(value))
    elseif value isa AbstractVector
        return [base_canonical_value(item) for item in value]
    elseif value isa AbstractDict
        return Dict(
            String(key) => base_canonical_value(item) for
                (key, item) in value
        )
    end
    return value
end

canonical(value) = V4.canonical(base_canonical_value(value))

semantic_sha256(value) = sha256_hex(codeunits(canonical(value)))

function exact_keys(value, expected, location)
    value isa AbstractDict || fail("$location must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail("$location must use string keys")
    actual = String.(collect(keys(value)))
    length(actual) == length(expected) ||
        fail("$location entry count changed")
    length(unique(actual)) == length(actual) ||
        fail("$location contains duplicate normalized keys")
    Set(actual) == Set(String.(expected)) ||
        fail("$location keys changed")
    return value
end

function exact_string(value, expected, location)
    typeof(value) === String || fail("$location must be exactly String")
    value == expected || fail("$location changed")
    return value
end

function exact_integer(value, expected, location)
    typeof(value) === Int64 || fail("$location must be exactly Int64")
    value == expected || fail("$location changed")
    return value
end

function exact_hash(value, location)
    value isa AbstractString || fail("$location must be a SHA-256")
    occursin(r"^[0-9a-f]{64}$", value) ||
        fail("$location must be lowercase hexadecimal SHA-256")
    return String(value)
end

function validate_boolean_table(table, true_keys, false_keys, location)
    expected = union(true_keys, false_keys)
    exact_keys(table, expected, location)
    for key in true_keys
        table[key] === true || fail("$location.$key must remain true")
    end
    for key in false_keys
        table[key] === false || fail("$location.$key must remain false")
    end
    return table
end

function validate_pinned_file_tables(tables)
    tables isa AbstractVector || fail("pinned_files must be an array")
    length(tables) == length(DIRECT_PIN_HASHES) ||
        fail("pinned_files count changed")
    by_path = Dict{String, Dict{String, Any}}()
    for (index, table) in enumerate(tables)
        exact_keys(table, ("path", "sha256", "role"), "pinned_files[$index]")
        path = exact_string(table["path"], table["path"], "pinned path")
        haskey(by_path, path) && fail("duplicate pinned path $path")
        haskey(DIRECT_PIN_HASHES, path) || fail("unknown pinned path $path")
        exact_string(
            table["sha256"],
            DIRECT_PIN_HASHES[path],
            "pinned_files[$index].sha256",
        )
        exact_hash(table["sha256"], "pinned_files[$index].sha256")
        role = table["role"]
        typeof(role) === String && !isempty(role) ||
            fail("pinned_files[$index].role must be a nonempty String")
        by_path[path] = table
    end
    Set(keys(by_path)) == Set(keys(DIRECT_PIN_HASHES)) ||
        fail("pinned_files set changed")
    return tables
end

function validate_protocol_semantics(document)
    expected_keys = (
        "schema_version",
        "contract_id",
        "information_track",
        "diagnostic_class",
        "model_variant",
        "model_constructor_id",
        "origin_period",
        "target_periods",
        "horizons",
        "path_count",
        "master_seed",
        "seed_namespace_experiment_id",
        "seed_namespace_disposition",
        "model_id",
        "path_kind",
        "v4_module_sha256",
        "v4_test_sha256",
        "v4_protocol_sha256",
        "v4_readme_sha256",
        "v4_accepted_result_sha256",
        "v4_one_step_path_set_sha256",
        "v4_opening_fingerprint_set_sha256",
        "v4_path_one_h1_post_collection_sha256",
        "v3_module_sha256",
        "v3_protocol_sha256",
        "v2_module_sha256",
        "v2_protocol_sha256",
        "v2_qualified_input_sha256",
        "v2_seed_plan_sha256",
        "synthetic_operator_module_sha256",
        "synthetic_operator_protocol_sha256",
        "us_2026q1_artifact_sha256",
        "julia_load_path_env",
        "symbolic_load_path",
        "compiled_modules_mode",
        "pkgimages_mode",
        "julia_use_compiled_modules_code",
        "julia_use_pkgimages_code",
        "julia_generating_output_code",
        "precompiletools_uuid",
        "package_import_side_data_file_count",
        "package_import_side_data_manifest_sha256",
        "selective_decode_contract",
        "expected_multi_step_path_set_sha256",
        "expected_path_one_h4_post_collection_sha256",
        "expected_multi_step_execution_envelope_sha256",
        "expected_method_origin_sha256",
        "real_gdp_formula",
        "gdp_deflator_formula",
        "path_evaluation_rule",
        "row_rule",
        "horizon_measurement_basis",
        "step_rule",
        "construction_input_rule",
        "synthetic_oracle_rule",
        "h1_prefix_rule",
        "execution_count_scope",
        "blockers",
        "prohibited_actions",
        "primary_path_order",
        "reverse_path_order",
        "replay_path_ids",
        "construction_seeds",
        "simulation_seeds",
        "execution_counts",
        "declarations",
        "attestation_limits",
        "pinned_files",
        "method_origins",
    )
    exact_keys(document, expected_keys, "v5 multi-step protocol")
    scalar_strings = Dict(
        "schema_version" => SCHEMA_VERSION,
        "contract_id" => CONTRACT_ID,
        "information_track" => INFORMATION_TRACK,
        "diagnostic_class" => DIAGNOSTIC_CLASS,
        "model_variant" => MODEL_VARIANT,
        "model_constructor_id" => MODEL_CONSTRUCTOR_ID,
        "origin_period" => ORIGIN_PERIOD,
        "seed_namespace_experiment_id" => SEED_NAMESPACE_EXPERIMENT_ID,
        "seed_namespace_disposition" => SEED_NAMESPACE_DISPOSITION,
        "model_id" => MODEL_ID,
        "path_kind" => PATH_KIND,
        "v4_module_sha256" => V4_MODULE_SHA256,
        "v4_test_sha256" => V4_TEST_SHA256,
        "v4_protocol_sha256" => V4_PROTOCOL_SHA256,
        "v4_readme_sha256" => V4_README_SHA256,
        "v4_accepted_result_sha256" => V4_ACCEPTED_RESULT_SHA256,
        "v4_one_step_path_set_sha256" => V4_ONE_STEP_PATH_SET_SHA256,
        "v4_opening_fingerprint_set_sha256" =>
            V4_OPENING_FINGERPRINT_SET_SHA256,
        "v4_path_one_h1_post_collection_sha256" =>
            V4_PATH_ONE_H1_POST_COLLECTION_SHA256,
        "v3_module_sha256" => V4.V3_MODULE_SHA256,
        "v3_protocol_sha256" => V4.V3_PROTOCOL_SHA256,
        "v2_module_sha256" =>
            "817910109d03c8f0cbadd2c8f91dc55f28eda4051ef42993a2377f71d7dd34e3",
        "v2_protocol_sha256" => V4.V2_PROTOCOL_SHA256,
        "v2_qualified_input_sha256" => V2_QUALIFIED_INPUT_SHA256,
        "v2_seed_plan_sha256" => V2_SEED_PLAN_SHA256,
        "synthetic_operator_module_sha256" => V4.OPERATOR_MODULE_SHA256,
        "synthetic_operator_protocol_sha256" => V4.OPERATOR_PROTOCOL_SHA256,
        "us_2026q1_artifact_sha256" =>
            DIRECT_PIN_HASHES["data/us/baselines/US_2026Q1_nowcast.jld2"],
        "julia_load_path_env" => V4.JULIA_LOAD_PATH_ENV,
        "compiled_modules_mode" => "no",
        "pkgimages_mode" => "no",
        "precompiletools_uuid" => string(V4.PRECOMPILETOOLS_UUID),
        "package_import_side_data_manifest_sha256" =>
            SIDE_DATA_MANIFEST_SHA256,
        "selective_decode_contract" => SELECTIVE_DECODE_CONTRACT,
        "expected_multi_step_path_set_sha256" =>
            EXPECTED_MULTI_STEP_PATH_SET_SHA256,
        "expected_path_one_h4_post_collection_sha256" =>
            EXPECTED_PATH_ONE_H4_POST_COLLECTION_SHA256,
        "expected_multi_step_execution_envelope_sha256" =>
            EXPECTED_MULTI_STEP_EXECUTION_ENVELOPE_SHA256,
        "expected_method_origin_sha256" => METHOD_ORIGIN_SHA256,
        "real_gdp_formula" =>
            "for_h_in_1_to_4:400*(log(real_gdp_row_h_plus_1)-log(real_gdp_row_h))",
        "gdp_deflator_formula" =>
            "for_h_in_1_to_4:400*((log(nominal_gdp_row_h_plus_1)-log(real_gdp_row_h_plus_1))-(log(nominal_gdp_row_h)-log(real_gdp_row_h)))",
        "path_evaluation_rule" =>
            "transform_each_raw_path_and_horizon_before_any_ensemble_summary",
        "row_rule" =>
            "rows_1_to_5_map_to_2026Q1_2026Q2_2026Q3_2026Q4_2027Q1",
        "step_rule" =>
            "seed_simulation_once_then_four_direct_one_argument_serial_step_calls_each_followed_by_one_collect_data_call",
        "construction_input_rule" =>
            "reassemble_fresh_qualified_inputs_for_every_construction",
        "synthetic_oracle_rule" =>
            "pure_formula_fixture_only_never_empirical_model_paths_and_excluded_from_model_call_counts",
        "h1_prefix_rule" =>
            "derive_v4_compatible_payload_without_rerunning_v4_and_require_exact_accepted_v4_h1_hashes",
        "execution_count_scope" => EXECUTION_COUNT_SCOPE,
    )
    for (key, expected) in scalar_strings
        exact_string(document[key], expected, key)
    end
    for key in (
            "v4_module_sha256",
            "v4_test_sha256",
            "v4_protocol_sha256",
            "v4_readme_sha256",
            "v4_accepted_result_sha256",
            "v4_one_step_path_set_sha256",
            "v4_opening_fingerprint_set_sha256",
            "v4_path_one_h1_post_collection_sha256",
            "v3_module_sha256",
            "v3_protocol_sha256",
            "v2_module_sha256",
            "v2_protocol_sha256",
            "v2_qualified_input_sha256",
            "v2_seed_plan_sha256",
            "synthetic_operator_module_sha256",
            "synthetic_operator_protocol_sha256",
            "us_2026q1_artifact_sha256",
            "package_import_side_data_manifest_sha256",
            "expected_multi_step_path_set_sha256",
            "expected_path_one_h4_post_collection_sha256",
            "expected_multi_step_execution_envelope_sha256",
            "expected_method_origin_sha256",
        )
        exact_hash(document[key], key)
    end
    exact_integer(document["path_count"], PATH_COUNT, "path_count")
    exact_integer(document["master_seed"], MASTER_SEED, "master_seed")
    exact_integer(
        document["package_import_side_data_file_count"],
        10,
        "package_import_side_data_file_count",
    )
    exact_integer(
        document["julia_use_compiled_modules_code"],
        0,
        "julia_use_compiled_modules_code",
    )
    exact_integer(
        document["julia_use_pkgimages_code"],
        0,
        "julia_use_pkgimages_code",
    )
    exact_integer(
        document["julia_generating_output_code"],
        0,
        "julia_generating_output_code",
    )
    document["target_periods"] == TARGET_PERIODS ||
        fail("target_periods changed")
    document["horizons"] == HORIZONS || fail("horizons changed")
    document["horizon_measurement_basis"] == HORIZON_MEASUREMENT_BASIS ||
        fail("horizon_measurement_basis changed")
    document["symbolic_load_path"] == V4.SYMBOLIC_LOAD_PATH ||
        fail("symbolic_load_path changed")
    document["primary_path_order"] == PRIMARY_PATH_ORDER ||
        fail("primary_path_order changed")
    document["reverse_path_order"] == REVERSE_PATH_ORDER ||
        fail("reverse_path_order changed")
    document["replay_path_ids"] == REPLAY_PATH_IDS ||
        fail("replay_path_ids changed")
    document["construction_seeds"] == CONSTRUCTION_SEEDS ||
        fail("construction seeds differ from accepted v4")
    document["simulation_seeds"] == SIMULATION_SEEDS ||
        fail("simulation seeds differ from accepted v4")
    length(unique([CONSTRUCTION_SEEDS; SIMULATION_SEEDS])) == 2PATH_COUNT ||
        fail("construction/simulation seed values are not distinct")
    document["execution_counts"] == EXECUTION_COUNTS ||
        fail("execution_counts changed")
    validate_boolean_table(
        document["declarations"],
        TRUE_DECLARATIONS,
        FALSE_DECLARATIONS,
        "declarations",
    )
    validate_boolean_table(
        document["attestation_limits"],
        TRUE_ATTESTATION_LIMITS,
        FALSE_ATTESTATION_LIMITS,
        "attestation_limits",
    )
    document["blockers"] == BLOCKERS || fail("blockers changed")
    document["prohibited_actions"] == String.(PROHIBITED_ACTION_LIST) ||
        fail("prohibited_actions changed")
    validate_pinned_file_tables(document["pinned_files"])
    document["method_origins"] == V4.method_origin_tables() ||
        fail("method_origins changed")
    return document
end

function validate_protocol(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || fail("v5 multi-step protocol is missing")
    islink(path) && fail("v5 multi-step protocol must not be a symbolic link")
    bytes = read(path)
    digest = sha256_hex(bytes)
    digest == PROTOCOL_SHA256 ||
        fail("v5 multi-step protocol SHA-256 changed: actual $digest")
    document = try
        TOML.parse(String(bytes))
    catch error
        fail("v5 multi-step protocol is invalid TOML: $(sprint(showerror, error))")
    end
    validate_protocol_semantics(document)
    return (; document, sha256 = digest)
end

protocol_sha256() = PROTOCOL_SHA256

function validate_source_pins(document = validate_protocol().document)
    validate_pinned_file_tables(document["pinned_files"])
    snapshots = Dict{String, Any}()
    for table in document["pinned_files"]
        snapshots[table["path"]] = V3.read_pinned_snapshot(
            table["path"],
            table["sha256"],
        )
    end
    V4.validate_protocol().sha256 == V4_PROTOCOL_SHA256 ||
        fail("accepted v4 protocol identity changed")
    V4.validate_source_pins()
    V4.side_data_manifest_sha256() == SIDE_DATA_MANIFEST_SHA256 ||
        fail("accepted v4 side-data manifest identity changed")
    return snapshots
end

function validate_levels(levels::RawFourQuarterGDPLevels)
    typeof(levels.nominal_gdp) === Vector{Float64} ||
        fail("nominal_gdp must be exactly Vector{Float64}")
    typeof(levels.real_gdp) === Vector{Float64} ||
        fail("real_gdp must be exactly Vector{Float64}")
    length(levels.nominal_gdp) == 5 ||
        fail("nominal_gdp must contain exactly rows 1 through 5")
    length(levels.real_gdp) == 5 ||
        fail("real_gdp must contain exactly rows 1 through 5")
    for (name, values) in
        (("nominal_gdp", levels.nominal_gdp), ("real_gdp", levels.real_gdp))
        all(isfinite, values) || fail("$name contains a nonfinite level")
        all(value -> value > 0, values) ||
            fail("$name levels must be strictly positive")
    end
    return levels
end

function compute_raw_four_quarter_operators(levels::RawFourQuarterGDPLevels)
    validate_levels(levels)
    real_growth = Vector{Float64}(undef, 4)
    deflator_inflation = Vector{Float64}(undef, 4)
    for horizon in HORIZONS
        previous = horizon
        current = horizon + 1
        real_growth[horizon] = 400.0 * (
            log(levels.real_gdp[current]) - log(levels.real_gdp[previous])
        )
        deflator_inflation[horizon] = 400.0 * (
            (
                log(levels.nominal_gdp[current]) -
                    log(levels.real_gdp[current])
            ) -
                (
                log(levels.nominal_gdp[previous]) -
                    log(levels.real_gdp[previous])
            )
        )
    end
    all(isfinite, real_growth) ||
        fail("raw real-GDP operators produced a nonfinite value")
    all(isfinite, deflator_inflation) ||
        fail("raw GDP-deflator operators produced a nonfinite value")
    return RawFourQuarterGDPOperators(real_growth, deflator_inflation)
end

function validate_synthetic_formula_oracle()
    SyntheticOperator.validate_protocol().sha256 ==
        V4.OPERATOR_PROTOCOL_SHA256 ||
        fail("synthetic formula-oracle protocol changed")
    SyntheticOperator.validate_source_pins()
    path_ids = [1, 2, 3]
    real = [
        100.0 100.0 100.0
        104.0 111.0 127.0
        106.0 117.0 121.0
        103.0 124.0 133.0
        109.0 120.0 147.0
    ]
    nominal = [
        100.0 100.0 100.0
        106.08 116.55 139.7
        110.24 124.02 137.94
        109.18 133.92 155.61
        118.81 132.0 176.4
    ]
    oracle = SyntheticOperator.compute_synthetic_operators(
        ALL_PERIODS,
        path_ids,
        real,
        nominal;
        fixture_class = "SYNTHETIC_OPERATOR_TEST_FIXTURE",
        fixture_id = "synthetic-v5-four-quarter-formula-oracle",
        path_kind = "RAW_MODEL_UNCORRECTED_SYNTHETIC",
        truth_accessed = false,
        empirical_path = false,
        class_h_used = false,
        bridge_adjusted = false,
        origin_reanchored = false,
    )
    raw_results = RawFourQuarterGDPOperators[]
    for path in path_ids
        result = compute_raw_four_quarter_operators(
            RawFourQuarterGDPLevels(
                copy(nominal[:, path]),
                copy(real[:, path]),
            ),
        )
        push!(raw_results, result)
        result.real_gdp_growth == oracle.real_gdp_growth[:, path] ||
            fail("raw real-GDP kernel differs bitwise from synthetic oracle")
        result.gdp_deflator_inflation ==
            oracle.gdp_deflator_inflation[:, path] ||
            fail("raw deflator kernel differs bitwise from synthetic oracle")
    end
    for horizon in HORIZONS
        mean_pathwise = sum(
            result.real_gdp_growth[horizon] for result in raw_results
        ) / length(raw_results)
        transform_of_mean = 400.0 * (
            log(sum(real[horizon + 1, :]) / length(path_ids)) -
                log(sum(real[horizon, :]) / length(path_ids))
        )
        mean_pathwise != transform_of_mean ||
            fail("synthetic fixture did not expose pathwise order at h=$horizon")
    end
    rebased = compute_raw_four_quarter_operators(
        RawFourQuarterGDPLevels(
            17.0 .* nominal[:, 1],
            17.0 .* real[:, 1],
        ),
    )
    all(
        isapprox.(
            rebased.real_gdp_growth,
            raw_results[1].real_gdp_growth;
            rtol = 0,
            atol = 4096eps(Float64),
        ),
    ) ||
        fail("real-GDP formula is not path-rebase invariant")
    all(
        isapprox.(
            rebased.gdp_deflator_inflation,
            raw_results[1].gdp_deflator_inflation;
            rtol = 0,
            atol = 4096eps(Float64),
        ),
    ) ||
        fail("deflator formula is not path-rebase invariant")
    return semantic_sha256(
        Dict{String, Any}(
            "periods" => ALL_PERIODS,
            "path_ids" => path_ids,
            "real" => vec(real),
            "nominal" => vec(nominal),
            "raw_results" => [struct_payload(result) for result in raw_results],
            "pathwise_before_ensemble" => true,
            "rebase_invariant" => true,
        ),
    )
end

@noinline function construct_fresh_with_seed(
        constructor,
        seed::Int,
        parameters::Dict{String, Any},
        initial_conditions::Dict{String, Any},
        counter::PhaseCounter,
    )
    V3.validate_rng_runtime()
    counter.constructions += 1
    Random.seed!(seed)
    return Base.invokelatest(constructor, parameters, initial_conditions)
end

@noinline function serial_four_step_collect_with_seed!(
        step_function,
        collect_function,
        state_hasher,
        trace_validator,
        input_guard,
        numeric_checker,
        model,
        seed::Int,
        shock,
        transaction_markets::Tuple{Symbol, Symbol},
        counter::PhaseCounter,
    )
    V3.validate_rng_runtime()
    post_step_hashes = String[]
    post_collection_hashes = String[]
    numeric_counts = Int[]
    Random.seed!(seed)
    for horizon in HORIZONS
        counter.steps += 1
        Base.invokelatest(
            step_function,
            model;
            parallel = false,
            shock! = shock,
            transaction_logger = nothing,
            transaction_markets = transaction_markets,
            opening_state_logger = nothing,
        )
        trace_validator(model, horizon, :post_step)
        push!(post_step_hashes, state_hasher(model))
        input_guard(horizon, :post_step)
        Base.invokelatest(collect_function, model)
        counter.post_step_collections += 1
        trace_validator(model, horizon, :post_collection)
        push!(post_collection_hashes, state_hasher(model))
        input_guard(horizon, :post_collection)
        numeric = numeric_checker(model)
        typeof(numeric) === Int ||
            fail("numeric state cardinality must be exactly Int")
        push!(numeric_counts, numeric)
    end
    return (; post_step_hashes, post_collection_hashes, numeric_counts)
end

function exact_model_time(model, expected, location)
    typeof(model.agg.t) === Int || fail("$location model time must be Int")
    model.agg.t == expected || fail("$location model time changed")
    return model.agg.t
end

function exact_collection_time(model, expected, location)
    typeof(model.data.collection_time) === Vector{Int} ||
        fail("$location collection_time must be Vector{Int}")
    model.data.collection_time == expected ||
        fail("$location collection_time changed")
    return copy(model.data.collection_time)
end

function validate_transition_trace(model, horizon, phase)
    horizon in HORIZONS || fail("trace horizon is outside 1:4")
    expected_time = horizon + 1
    if phase === :post_step
        exact_model_time(model, expected_time, "h$horizon post-step")
        exact_collection_time(
            model,
            collect(1:horizon),
            "h$horizon post-step",
        )
    elseif phase === :post_collection
        exact_model_time(model, expected_time, "h$horizon post-collection")
        exact_collection_time(
            model,
            collect(1:(horizon + 1)),
            "h$horizon post-collection",
        )
    else
        fail("unknown transition-trace phase")
    end
    return true
end

function levels_from_model(model)
    exact_model_time(model, 5, "four-quarter final")
    exact_collection_time(model, collect(1:5), "four-quarter final")
    typeof(model.data.nominal_gdp) === Vector{Float64} ||
        fail("native nominal_gdp must be Vector{Float64}")
    typeof(model.data.real_gdp) === Vector{Float64} ||
        fail("native real_gdp must be Vector{Float64}")
    levels = RawFourQuarterGDPLevels(
        copy(model.data.nominal_gdp),
        copy(model.data.real_gdp),
    )
    return validate_levels(levels)
end

function execute_one_path(
        record,
        qualified,
        v2,
        beforeit,
        counts,
        counter::PhaseCounter,
    )
    V3.v2_call(v2, :validate_qualified_inputs, qualified)
    inputs = V3.v2_call(v2, :reassemble_model_inputs, qualified)
    parameter_hash = V3.v2_call(v2, :semantic_sha256, inputs.parameters)
    initial_hash =
        V3.v2_call(v2, :semantic_sha256, inputs.initial_conditions)
    function input_guard(horizon, phase)
        parameter_hash ==
            V3.v2_call(v2, :semantic_sha256, inputs.parameters) ||
            fail("h$horizon $phase mutated reconstructed parameters")
        initial_hash ==
            V3.v2_call(v2, :semantic_sha256, inputs.initial_conditions) ||
            fail("h$horizon $phase mutated reconstructed initial conditions")
        V3.v2_call(v2, :validate_qualified_inputs, qualified)
        return true
    end
    model = try
        construct_fresh_with_seed(
            getfield(beforeit, :Model),
            record.construction_seed,
            inputs.parameters,
            inputs.initial_conditions,
            counter,
        )
    catch error
        error isa ABMMultiStepGateV5Error && rethrow()
        fail(
            "BeforeIT.Model construction failed for path $(record.path_id): " *
                sprint(showerror, error),
        )
    end
    input_guard(0, :post_constructor)
    numeric_opening = V3.validate_model_structure(model, beforeit, counts)
    model.prop.use_opening_macro_controls === false ||
        fail("v5 forbids artifact opening-macro controls")
    exact_model_time(model, 1, "constructor opening")
    exact_collection_time(model, [1], "constructor opening")
    counter.constructor_opening_collections += 1
    opening_state_sha256 = V3.full_state_sha256(model)
    shock = Base.invokelatest(getfield(beforeit, :NoShock))
    transition = try
        serial_four_step_collect_with_seed!(
            getfield(beforeit, :step!),
            getfield(beforeit, :collect_data!),
            V3.full_state_sha256,
            validate_transition_trace,
            input_guard,
            V3.validate_numeric_finiteness,
            model,
            record.simulation_seed,
            shock,
            (:business_goods, :final_demand),
            counter,
        )
    catch error
        error isa ABMMultiStepGateV5Error && rethrow()
        fail(
            "serial four-step execution failed for path $(record.path_id): " *
                sprint(showerror, error),
        )
    end
    all(value -> value >= numeric_opening, transition.numeric_counts) ||
        fail("numeric state cardinality unexpectedly shrank")
    levels = levels_from_model(model)
    operators = compute_raw_four_quarter_operators(levels)
    input_guard(4, :final)
    return MultiStepPathResult(
        record.path_id,
        record.construction_seed,
        record.simulation_seed,
        ORIGIN_PERIOD,
        copy(TARGET_PERIODS),
        copy(HORIZONS),
        collect(1:5),
        levels.nominal_gdp,
        levels.real_gdp,
        operators.real_gdp_growth,
        operators.gdp_deflator_inflation,
        opening_state_sha256,
        transition.post_step_hashes,
        transition.post_collection_hashes,
        parameter_hash,
        initial_hash,
        true,
        transition.numeric_counts,
    )
end

function execute_path_order(
        path_order,
        seed_plan,
        qualified,
        v2,
        beforeit,
        counts,
        counter,
    )
    path_order isa AbstractVector || fail("path order must be a vector")
    all(path_id -> typeof(path_id) === Int, path_order) ||
        fail("path order must contain exact Int values")
    all(path_id -> 1 <= path_id <= PATH_COUNT, path_order) ||
        fail("path order contains an out-of-range path")
    length(unique(path_order)) == length(path_order) ||
        fail("path order contains a duplicate")
    by_path = Dict(record.path_id => record for record in seed_plan)
    Set(keys(by_path)) == Set(1:PATH_COUNT) ||
        fail("seed plan path IDs changed")
    return [
        execute_one_path(
                by_path[path_id],
                qualified,
                v2,
                beforeit,
                counts,
                counter,
            ) for path_id in path_order
    ]
end

path_payload(path::MultiStepPathResult) = struct_payload(path)

function multi_step_path_set_sha256(paths)
    paths isa AbstractVector || fail("multi-step paths must be a vector")
    length(paths) == PATH_COUNT ||
        fail("multi-step path set must contain $PATH_COUNT paths")
    all(path -> path isa MultiStepPathResult, paths) ||
        fail("multi-step path set contains an unsupported record")
    normalized = sort!(collect(paths); by = path -> path.path_id)
    getfield.(normalized, :path_id) == collect(1:PATH_COUNT) ||
        fail("multi-step path set IDs changed")
    return semantic_sha256(path_payload.(normalized))
end

same_path_result(first::MultiStepPathResult, second::MultiStepPathResult) =
    canonical(first) == canonical(second)

function v4_h1_prefix(path::MultiStepPathResult)
    return V4.OneStepPathResult(
        path.path_id,
        path.construction_seed,
        path.simulation_seed,
        path.origin_period,
        path.target_periods[1],
        [1, 2],
        path.nominal_gdp_levels[1],
        path.nominal_gdp_levels[2],
        path.real_gdp_levels[1],
        path.real_gdp_levels[2],
        path.real_gdp_growth[1],
        path.gdp_deflator_inflation[1],
        path.opening_state_sha256,
        path.post_step_state_sha256[1],
        path.post_collection_state_sha256[1],
        path.input_parameter_sha256,
        path.input_initial_conditions_sha256,
        path.input_hashes_unchanged,
        path.numeric_values_checked_after_collection[1],
    )
end

function validate_execution_counts(counts, document)
    for field in fieldnames(MultiStepExecutionCounts)
        getfield(counts, field) ==
            document["execution_counts"][String(field)] ||
            fail("execution count $(String(field)) changed")
    end
    return counts
end

function multi_step_execution_envelope_sha256(
        v3_execution_digest,
        load_path_attestation,
        document,
    )
    return semantic_sha256(
        Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-abm-multi-step-execution-envelope.v5",
            "v4_module_sha256" => V4_MODULE_SHA256,
            "v4_protocol_sha256" => V4_PROTOCOL_SHA256,
            "v4_accepted_result_sha256" => V4_ACCEPTED_RESULT_SHA256,
            "v3_execution_envelope_sha256" => v3_execution_digest,
            "julia_use_compiled_modules_code" =>
                document["julia_use_compiled_modules_code"],
            "julia_use_pkgimages_code" =>
                document["julia_use_pkgimages_code"],
            "julia_generating_output_code" =>
                document["julia_generating_output_code"],
            "symbolic_load_path_sha256" =>
                load_path_attestation.symbolic_sha256,
            "expanded_load_path_sha256" =>
                load_path_attestation.expanded_sha256,
            "package_import_side_data_manifest_sha256" =>
                SIDE_DATA_MANIFEST_SHA256,
            "selective_decode_contract" => SELECTIVE_DECODE_CONTRACT,
            "horizons" => HORIZONS,
            "target_periods" => TARGET_PERIODS,
            "step_rule" => document["step_rule"],
            "execution_counts" => EXECUTION_COUNTS,
        ),
    )
end

function result_payload(result::MultiStepGateV5Result)
    return Dict(
        String(field) => getfield(result, field) for
            field in fieldnames(MultiStepGateV5Result) if
            field != :result_sha256
    )
end

function with_result_hash(result::MultiStepGateV5Result)
    digest = semantic_sha256(result_payload(result))
    return MultiStepGateV5Result(
        (
            getfield(result, field) for
                field in fieldnames(MultiStepGateV5Result) if
                field != :result_sha256
        )...,
        digest,
    )
end

function _run_installed_multi_step_gate()
    counters = AttemptCounters()
    LAST_ATTEMPT_COUNTERS[] = counters
    V3.validate_third_party_bootstrap_unloaded()
    V4.validate_precompiletools_unloaded()
    protocol = validate_protocol()
    package_load_envelope =
        V4.validate_uncompiled_package_load_envelope(protocol.document)
    initial_v5_snapshots = validate_source_pins(protocol.document)
    v4_protocol = V4.validate_protocol()
    v4_protocol.sha256 == V4_PROTOCOL_SHA256 ||
        fail("v5 did not bind the accepted v4 protocol")
    v3_protocol = V3.validate_protocol()
    load_path_attestation =
        V3.validate_load_path_environment(v3_protocol.document)
    execution_digest = V3.validate_execution_environment(v3_protocol.document)
    multi_step_execution_digest = multi_step_execution_envelope_sha256(
        execution_digest,
        load_path_attestation,
        protocol.document,
    )
    if protocol.document["expected_multi_step_execution_envelope_sha256"] ==
            ZERO_SHA256
        fail(
            "v5 execution envelope remains unfrozen: " *
                "multi_step_execution_envelope_sha256=$multi_step_execution_digest",
        )
    end
    multi_step_execution_digest ==
        protocol.document["expected_multi_step_execution_envelope_sha256"] ||
        fail("v5 execution-envelope digest changed")
    V3.validate_rng_runtime(v3_protocol.document["default_rng_type"])
    depot_attestation = V3.validate_artifact_overrides_absent()
    initial_v3_snapshots = V3.validate_pinned_files(v3_protocol.document)
    V3.validate_third_party_bootstrap_unloaded()
    dependency_attestation =
        V3.validate_dependency_source_trees(v3_protocol.document)
    V3.validate_third_party_bootstrap_unloaded()
    entrypoint_attestation = V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        dependency_attestation,
    )
    V3.validate_third_party_bootstrap_unloaded()
    synthetic_oracle_sha256 = validate_synthetic_formula_oracle()
    V3.validate_third_party_bootstrap_unloaded()
    V4.validate_precompiletools_unloaded()
    V4.validate_uncompiled_package_load_envelope(protocol.document)
    v2 = V3.load_frozen_v2_after_attestation(
        v3_protocol.document,
        dependency_attestation,
        entrypoint_attestation,
    )
    V3.v2_call(v2, :validate_protocol)
    V3.v2_call(v2, :validate_source_pins)
    V3.validate_load_path_environment(v3_protocol.document)
    V3.validate_jld2_unloaded()
    V3.validate_beforeit_unloaded()
    pre_jld2_sources = V3.validate_dependency_source_trees(v3_protocol.document)
    pre_jld2_sources.actual_digest == dependency_attestation.actual_digest ||
        fail("dependency source trees changed before loading JLD2")
    pre_jld2_entrypoints = V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        pre_jld2_sources,
    )
    pre_jld2_entrypoints.actual_digest == entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed before loading JLD2")
    V3.validate_jld2_unloaded()
    V3.validate_beforeit_unloaded()
    precompiletools = V4.validate_loaded_precompiletools()
    V4.validate_uncompiled_package_load_envelope(protocol.document)
    jld2 = V3.require_preresolved_package(
        V3.JLD2_PKGID,
        pre_jld2_sources,
        pre_jld2_entrypoints,
    )
    jld2_identity = V3.validate_jld2_module(jld2)
    V3.validate_load_path_environment(v3_protocol.document)
    V3.validate_beforeit_unloaded()
    selected = V4.decode_model_inputs_selectively(
        initial_v3_snapshots[
            "data/us/baselines/US_2026Q1_nowcast.jld2",
        ],
        jld2,
    )
    qualified, seed_plan = V4.qualify_selectively_decoded_inputs(
        selected,
        v4_protocol.document,
        v2,
    )
    qualified.qualified_input_sha256 == V2_QUALIFIED_INPUT_SHA256 ||
        fail("v5 qualified-input identity changed")
    V3.v2_call(v2, :path_seed_plan_sha256, seed_plan, qualified) ==
        V2_SEED_PLAN_SHA256 || fail("v5 seed-plan identity changed")
    getfield.(seed_plan, :construction_seed) == CONSTRUCTION_SEEDS ||
        fail("v5 construction seeds changed")
    getfield.(seed_plan, :simulation_seed) == SIMULATION_SEEDS ||
        fail("v5 simulation seeds changed")
    reassembled = V3.v2_call(v2, :reassemble_model_inputs, qualified)
    domain_counts = V3.preflight_constructor_domain(
        reassembled.parameters,
        reassembled.initial_conditions,
    )

    V3.validate_beforeit_unloaded()
    V3.validate_execution_environment(v3_protocol.document)
    V3.validate_pinned_files(v3_protocol.document)
    validate_source_pins(protocol.document)
    V3.v2_call(v2, :validate_protocol)
    V3.v2_call(v2, :validate_source_pins)
    pre_beforeit_sources =
        V3.validate_dependency_source_trees(v3_protocol.document)
    pre_beforeit_sources.actual_digest == dependency_attestation.actual_digest ||
        fail("dependency source trees changed before loading BeforeIT")
    pre_beforeit_entrypoints = V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        pre_beforeit_sources,
    )
    pre_beforeit_entrypoints.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed before loading BeforeIT")
    current_depot_attestation = V3.validate_artifact_overrides_absent()
    current_depot_attestation == depot_attestation ||
        fail("DEPOT_PATH changed before loading BeforeIT")
    V3.validate_jld2_module(jld2) == jld2_identity ||
        fail("JLD2 identity changed before loading BeforeIT")
    V3.validate_beforeit_resolution()
    V3.validate_beforeit_unloaded()
    V4.validate_loaded_precompiletools() === precompiletools ||
        fail("PrecompileTools identity changed before BeforeIT load")
    V4.validate_uncompiled_package_load_envelope(protocol.document)
    beforeit = V3.require_preresolved_package(
        V3.BEFOREIT_PKGID,
        pre_beforeit_sources,
        pre_beforeit_entrypoints,
    )
    V3.validate_loaded_package_entrypoint(beforeit, V3.BEFOREIT_PKGID)
    V4.validate_loaded_precompiletools() === precompiletools ||
        fail("PrecompileTools identity changed while loading BeforeIT")
    V3.validate_load_path_environment(v3_protocol.document)
    getfield(beforeit, :typeFloat) === Float64 ||
        fail("BeforeIT.typeFloat must be Float64")
    getfield(beforeit, :typeInt) === Int ||
        fail("BeforeIT.typeInt must be Int")
    constructor_method_records = V3.collect_method_origin_records(beforeit)
    constructor_method_digest = V3.method_origin_digest(constructor_method_records)
    multi_step_method_records = V4.collect_one_step_method_origins(beforeit)
    multi_step_method_digest =
        V4.one_step_method_origin_digest(multi_step_method_records)
    multi_step_method_digest == METHOD_ORIGIN_SHA256 ||
        fail("multi-step method-origin digest changed")

    primary_paths = execute_path_order(
        protocol.document["primary_path_order"],
        seed_plan,
        qualified,
        v2,
        beforeit,
        domain_counts,
        counters.primary,
    )
    reverse_paths = execute_path_order(
        protocol.document["reverse_path_order"],
        seed_plan,
        qualified,
        v2,
        beforeit,
        domain_counts,
        counters.reverse,
    )
    replay_path = only(
        execute_path_order(
            protocol.document["replay_path_ids"],
            seed_plan,
            qualified,
            v2,
            beforeit,
            domain_counts,
            counters.replay,
        ),
    )
    primary_by_id = Dict(path.path_id => path for path in primary_paths)
    reverse_by_id = Dict(path.path_id => path for path in reverse_paths)
    Set(keys(primary_by_id)) == Set(1:PATH_COUNT) ||
        fail("primary multi-step path IDs changed")
    Set(keys(reverse_by_id)) == Set(1:PATH_COUNT) ||
        fail("reverse multi-step path IDs changed")
    path_order_invariant = all(
        same_path_result(primary_by_id[path_id], reverse_by_id[path_id]) for
            path_id in 1:PATH_COUNT
    )
    path_order_invariant ||
        fail("multi-step results changed under reverse path execution")
    deterministic_replay_equal = same_path_result(primary_by_id[1], replay_path)
    deterministic_replay_equal || fail("same-seed multi-step replay changed")
    opening_fingerprints = getfield.(primary_paths, :opening_state_sha256)
    opening_digest = V3.validate_stochastic_fingerprints(
        opening_fingerprints,
        replay_path.opening_state_sha256,
        V4_OPENING_FINGERPRINT_SET_SHA256,
    )
    getfield.(reverse_paths, :opening_state_sha256) ==
        reverse(opening_fingerprints) ||
        fail("reverse opening constructor fingerprints changed")
    h1_prefixes = v4_h1_prefix.(primary_paths)
    h1_prefix_digest = V4.path_result_set_sha256(h1_prefixes)
    h1_prefix_digest == V4_ONE_STEP_PATH_SET_SHA256 ||
        fail("v5 h1 prefix differs from accepted v4")
    V4.path_result_set_sha256(v4_h1_prefix.(reverse_paths)) ==
        h1_prefix_digest || fail("reverse h1 prefix differs")
    replay_path.post_collection_state_sha256[1] ==
        V4_PATH_ONE_H1_POST_COLLECTION_SHA256 ||
        fail("path-one h1 state differs from accepted v4")
    one_path_digest = multi_step_path_set_sha256(primary_paths)
    multi_step_path_set_sha256(reverse_paths) == one_path_digest ||
        fail("reverse multi-step path-set digest changed")
    expected_path_digest =
        protocol.document["expected_multi_step_path_set_sha256"]
    expected_path_one_h4 =
        protocol.document["expected_path_one_h4_post_collection_sha256"]
    if expected_path_digest == ZERO_SHA256 || expected_path_one_h4 == ZERO_SHA256
        fail(
            "v5 outputs remain unfrozen: multi_step_path_set_sha256=" *
                "$one_path_digest path_one_h4_post_collection_sha256=" *
                replay_path.post_collection_state_sha256[4],
        )
    end
    one_path_digest == expected_path_digest ||
        fail("multi-step path-set digest changed")
    replay_path.post_collection_state_sha256[4] == expected_path_one_h4 ||
        fail("path-one h4 post-collection state changed")
    run_counts =
        validate_execution_counts(execution_counts(counters), protocol.document)
    input_hashes_unchanged = all(
        path.input_hashes_unchanged for
            path in [primary_paths; reverse_paths; [replay_path]]
    )
    input_hashes_unchanged ||
        fail("multi-step qualification mutated reconstructed inputs")

    V3.validate_execution_environment(v3_protocol.document)
    V3.v2_call(v2, :validate_protocol)
    V3.v2_call(v2, :validate_source_pins)
    final_v5_snapshots = validate_source_pins(protocol.document)
    for path in keys(initial_v5_snapshots)
        V3.validate_snapshot_unchanged(
            initial_v5_snapshots[path],
            final_v5_snapshots[path],
        )
    end
    final_v3_snapshots = V3.validate_pinned_files(v3_protocol.document)
    for path in keys(initial_v3_snapshots)
        V3.validate_snapshot_unchanged(
            initial_v3_snapshots[path],
            final_v3_snapshots[path],
        )
    end
    final_dependency_attestation =
        V3.validate_dependency_source_trees(v3_protocol.document)
    final_dependency_attestation.actual_digest ==
        dependency_attestation.actual_digest ||
        fail("dependency source trees changed during multi-step execution")
    final_entrypoint_attestation = V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        final_dependency_attestation,
    )
    final_entrypoint_attestation.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed during multi-step execution")
    V3.validate_artifact_overrides_absent() == depot_attestation ||
        fail("DEPOT_PATH changed during multi-step execution")
    V3.validate_jld2_module(jld2) == jld2_identity ||
        fail("JLD2 identity changed during multi-step execution")
    V3.method_origin_digest(V3.collect_method_origin_records(beforeit)) ==
        constructor_method_digest ||
        fail("constructor method origins changed during multi-step execution")
    V4.one_step_method_origin_digest(
        V4.collect_one_step_method_origins(beforeit),
    ) == multi_step_method_digest ||
        fail("transition method origins changed during execution")
    V3.validate_loaded_package_entrypoint(beforeit, V3.BEFOREIT_PKGID)
    V4.validate_loaded_precompiletools() === precompiletools ||
        fail("PrecompileTools module identity changed")
    V3.v2_call(v2, :validate_qualified_inputs, qualified)
    qualified.qualified_input_sha256 == V2_QUALIFIED_INPUT_SHA256 ||
        fail("qualified input changed during multi-step execution")
    validate_protocol().sha256 == protocol.sha256 ||
        fail("v5 protocol changed during execution")
    V4.validate_uncompiled_package_load_envelope(protocol.document) ==
        package_load_envelope ||
        fail("uncompiled package-load envelope changed")

    result = MultiStepGateV5Result(
        schema_version = SCHEMA_VERSION,
        contract_id = CONTRACT_ID,
        information_track = INFORMATION_TRACK,
        protocol_sha256 = protocol.sha256,
        v4_module_sha256 = V4_MODULE_SHA256,
        v4_protocol_sha256 = V4_PROTOCOL_SHA256,
        v4_accepted_result_sha256 = V4_ACCEPTED_RESULT_SHA256,
        v4_runner_reexecuted = false,
        v2_protocol_sha256 = qualified.protocol_sha256,
        qualified_input_sha256 = qualified.qualified_input_sha256,
        seed_plan_sha256 = V3.v2_call(
            v2,
            :path_seed_plan_sha256,
            seed_plan,
            qualified,
        ),
        synthetic_operator_module_sha256 = V4.OPERATOR_MODULE_SHA256,
        synthetic_operator_protocol_sha256 = V4.OPERATOR_PROTOCOL_SHA256,
        synthetic_formula_oracle_sha256 = synthetic_oracle_sha256,
        dependency_source_tree_count =
            dependency_attestation.source_tree_count,
        dependency_source_tree_digest = dependency_attestation.actual_digest,
        package_entrypoint_count =
            entrypoint_attestation.package_entrypoint_count,
        package_entrypoint_digest = entrypoint_attestation.actual_digest,
        symbolic_load_path_sha256 = load_path_attestation.symbolic_sha256,
        expanded_load_path_sha256 = load_path_attestation.expanded_sha256,
        depot_path_count = depot_attestation.path_count,
        depot_paths_sha256 = depot_attestation.paths_sha256,
        v3_execution_envelope_sha256 = execution_digest,
        multi_step_execution_envelope_sha256 = multi_step_execution_digest,
        package_import_side_data_manifest_sha256 = SIDE_DATA_MANIFEST_SHA256,
        selective_decode_contract = SELECTIVE_DECODE_CONTRACT,
        constructor_method_origin_sha256 = constructor_method_digest,
        multi_step_method_origin_sha256 = multi_step_method_digest,
        compiled_modules_disabled =
            package_load_envelope.compiled_modules_disabled,
        pkgimages_disabled = package_load_envelope.pkgimages_disabled,
        generating_output = package_load_envelope.generating_output,
        execution_count_scope = EXECUTION_COUNT_SCOPE,
        horizon_measurement_basis = copy(HORIZON_MEASUREMENT_BASIS),
        execution_counts = run_counts,
        primary_paths = primary_paths,
        reverse_paths = reverse_paths,
        replay_path = replay_path,
        multi_step_path_set_sha256 = one_path_digest,
        v4_h1_prefix_path_set_sha256 = h1_prefix_digest,
        opening_fingerprint_set_sha256 = opening_digest,
        deterministic_replay_equal = deterministic_replay_equal,
        path_order_invariant = path_order_invariant,
        input_hashes_unchanged = input_hashes_unchanged,
        software_four_quarter_path_verified = true,
        free_running_without_intermediate_reanchoring = true,
        raw_diagnostic_path_values_returned = true,
        measurement_basis_discontinuity_preserved = true,
        truth_bearing_metadata_present_in_pinned_artifact = true,
        truth_bearing_raw_artifact_bytes_hashed = true,
        truth_bearing_metadata_deserialized = false,
        truth_values_consumed_by_model_or_operator = false,
        truth_values_used_for_scoring = false,
        us_evaluation_truth_used = false,
        us_nowcast_parameters_initial_conditions_selectively_deserialized = true,
        package_import_side_data_deserialized = true,
        package_import_side_data_attested = true,
        package_import_side_data_passed_to_v5_constructor_or_gdp_operator = false,
        package_precompile_workload_execution_guard_attested = true,
        package_precompile_workload_executed = false,
        precompiletools_clean_bootstrap_verified = true,
        precompiletools_verbose_false = true,
        ephemeral_jld2_snapshot_written = true,
        zero_filesystem_writes_claimed = false,
        independent_streams_established = false,
        input_lineage_verified = false,
        source_period_labels_authenticated = false,
        empirical_forecast_validated = false,
        forecast_artifact_emitted = false,
        forecast_artifact_serialized = false,
        score_computed = false,
        inference_run = false,
        origin_admissible = false,
        registry_write_allowed = false,
        promotion_eligible = false,
        class_h_allowed = false,
        production_allowed = false,
        reanchoring_used = false,
        bridge_adjustment_used = false,
        diagnostic_only = true,
        full_runtime_attestation = false,
        result_sha256 = "",
    )
    with_hash = with_result_hash(result)
    if EXPECTED_RESULT_SHA256 == ZERO_SHA256
        fail("v5 result identity remains unfrozen: result_sha256=$(with_hash.result_sha256)")
    end
    with_hash.result_sha256 == EXPECTED_RESULT_SHA256 ||
        fail("v5 result identity changed: actual $(with_hash.result_sha256)")
    return with_hash
end

function run_installed_multi_step_gate()
    try
        return _run_installed_multi_step_gate()
    catch error
        error isa ABMMultiStepGateV5Error && rethrow()
        fail(
            "v5 multi-step qualification failed closed: " *
                sprint(showerror, error),
        )
    end
end

function refuse_prohibited_action(action::Symbol)
    action in PROHIBITED_ACTIONS ||
        fail("unknown v5 multi-step-gate action $(String(action))")
    return fail(
        "v5 multi-step gate forbids $(String(action)); " *
            "the boundary is a nonadmitting software diagnostic",
    )
end

end # module
