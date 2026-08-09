module USRevisedDataABMOneStepGateV4

using Pkg
using Random
using SHA
using TOML
using UUIDs

export ABMOneStepGateV4Error,
    OneStepExecutionCounts,
    OneStepGateV4Result,
    OneStepMethodOriginRecord,
    OneStepPathResult,
    RawEngineeringGDPOperators,
    RawEngineeringGDPLevels,
    attempt_execution_counts,
    collect_one_step_method_origins,
    compute_raw_engineering_operators,
    construct_fresh_with_seed,
    one_step_method_origin_digest,
    path_result_set_sha256,
    protocol_sha256,
    refuse_prohibited_action,
    run_installed_one_step_gate,
    serial_step_collect_with_seed!,
    validate_one_step_method_origins,
    validate_protocol,
    validate_protocol_semantics,
    validate_source_pins,
    validate_synthetic_formula_oracle,
    validate_uncompiled_package_load_envelope,
    validate_precompiletools_unloaded,
    validate_loaded_precompiletools

const SCHEMA_VERSION =
    "beforeit-us-revised-data-abm-one-step-gate.v4"
const CONTRACT_ID =
    "beforeit-us-revised-data-abm-base-one-step-qualification.v4"
const INFORMATION_TRACK = "revised_mixed_vintage"
const DIAGNOSTIC_CLASS =
    "quarantined_initial_transition_software_qualification"
const MODEL_VARIANT = "base"
const MODEL_CONSTRUCTOR_ID = "BeforeIT.Model"
const ORIGIN_PERIOD = "2026Q1"
const TARGET_PERIOD = "2026Q2"
const HORIZON = 1
const PATH_COUNT = 32
const MASTER_SEED = 20260807
const SEED_NAMESPACE_EXPERIMENT_ID =
    "us-abm-constructor-gate-v3"
const MODEL_ID = "beforeit-us-abm-base"
const PATH_KIND =
    "RAW_MODEL_UNCORRECTED_REVISED_MIXED_VINTAGE_DIAGNOSTIC"
const JULIA_LOAD_PATH_ENV = "@:@stdlib"
const SYMBOLIC_LOAD_PATH = ["@", "@stdlib"]
const V3_MODULE_SHA256 =
    "e035a8b35e65ea383d28ceef6673ae311e6fe74a5394a2c45bf576e0b0600815"
const V3_PROTOCOL_SHA256 =
    "9bea1d110879275e33cc58d87a802c5e51e2b2f3d33929d7db073e81bd07166d"
const WITHDRAWN_V3_REFERENCE_RESULT_SHA256 =
    "68df3185b7159ac4b9fadcdb82ffb2e674ff5fdf6a89aa8d78585b4e4cf3105b"
const V3_OPENING_FINGERPRINT_SET_SHA256 =
    "2f359965fa08785101870a46332cdd66c91e744a664e9803fc198ef53e024a18"
const V2_PROTOCOL_SHA256 =
    "efcdce3fb08e0b7496f9293c299787994eda85f2d7f750603a7f5a8b0856cab4"
const V2_QUALIFIED_INPUT_SHA256 =
    "bd9ac9c9054ef51289e5dfb51281e9f259684f19230e8c1a34c47f84d8062011"
const V2_SEED_PLAN_SHA256 =
    "7b42c8280d4ce398d9e426940480a635960817d1befddb9c801dbb1fcc94ec2c"
const OPERATOR_MODULE_SHA256 =
    "28ae259cecbe20a6d2d6c91de4bed6eab86f676864f9476b0977e6bcc0cd7492"
const OPERATOR_PROTOCOL_SHA256 =
    "c94de45ad463db87d93a6002ca4c6ee9ca5e908423bd793396db5c87d52ae148"
const ONE_STEP_METHOD_ORIGIN_SHA256 =
    "c01f4283b344992f9f6c3590dbd702a0860cfd6f86647e8af88d2b96ba11fe36"
const PRECOMPILETOOLS_UUID =
    UUID("aea7be01-6a6a-4083-8856-8a6e6704d82a")
const PRECOMPILETOOLS_PKGID =
    Base.PkgId(PRECOMPILETOOLS_UUID, "PrecompileTools")
const ZERO_SHA256 = repeat("0", 64)
const REAL_GDP_FORMULA =
    "400*(log(real_gdp_row_2)-log(real_gdp_row_1))"
const GDP_DEFLATOR_FORMULA =
    "400*((log(nominal_gdp_row_2)-log(real_gdp_row_2))-(log(nominal_gdp_row_1)-log(real_gdp_row_1)))"
const EXECUTION_COUNT_SCOPE =
    "gate_owned_calls_after_beforeit_require_excludes_package_import_and_precompile_workloads"
const SIDE_DATA_FILE_COUNT = 10
const SIDE_DATA_MANIFEST_SHA256 =
    "646fd7727a5885fd9514d0ebf9e722a0b63295f785c52f2a42498d757214ec0a"
const SELECTIVE_DECODE_CONTRACT =
    "jld2_named_datasets_parameters_and_initial_conditions_only_period_axis_from_frozen_v3_protocol"
const EXPECTED_V4_EXECUTION_ENVELOPE_SHA256 =
    "ee71160c99b187883eb67769d17fa87829b6a58bda6e23102e97c122fe09005d"
const EXPECTED_RESULT_SHA256 =
    "1ac4efc78236d0dfafb11d78b35597b1106cd374488b4f0c9ddf8fd70b1782a2"

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_one_step_gate_v4.toml",
)
const PROTOCOL_SHA256 =
    "d15fdef2c5fa7142c7658318d2bd726953b9a4569f3f7d50762e14965f9c3ef7"
const V3_MODULE_PATH =
    joinpath(@__DIR__, "USRevisedDataABMConstructorGateV3.jl")
const V3_PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_constructor_gate_v3.toml",
)
const OPERATOR_MODULE_PATH = joinpath(
    @__DIR__,
    "..",
    "targets",
    "abm_gdp_operator",
    "USABMGDPOperatorQualification.jl",
)
const OPERATOR_PROTOCOL_PATH = joinpath(
    @__DIR__,
    "..",
    "targets",
    "abm_gdp_operator",
    "operator_qualification.toml",
)

struct ABMOneStepGateV4Error <: Exception
    message::String
end

Base.showerror(io::IO, error::ABMOneStepGateV4Error) =
    print(io, error.message)

fail(message) =
    throw(ABMOneStepGateV4Error(String(message)))

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function include_pinned_module(path, expected_sha256, label)
    isfile(path) || fail("$label source is missing")
    islink(path) && fail("$label source must not be a symbolic link")
    bytes = read(path)
    sha256_hex(bytes) == expected_sha256 ||
        fail("$label source SHA-256 changed")
    loaded = try
        Base.include_string(@__MODULE__, String(bytes), path)
    catch error
        fail("$label include failed: $(sprint(showerror, error))")
    end
    loaded isa Module || fail("$label include did not return a module")
    return loaded
end

const V3 = include_pinned_module(
    V3_MODULE_PATH,
    V3_MODULE_SHA256,
    "withdrawn v3 constructor-gate scaffolding",
)
const SyntheticOperator = include_pinned_module(
    OPERATOR_MODULE_PATH,
    OPERATOR_MODULE_SHA256,
    "accepted synthetic GDP operator",
)

const CONSTRUCTION_SEEDS = Int[
    5031910127460406113,
    1800640781086547184,
    2303797836613292799,
    4317343911030018305,
    3702634746480464642,
    2648785862302636204,
    4414831013187652133,
    3936483942940814467,
    1585554234299344068,
    2799410045535767552,
    6288098778649103898,
    6961787840163358977,
    2129679152141147343,
    576547306833785497,
    3517472245011203844,
    6970498931470826593,
    3997766355651258578,
    1817892351882332218,
    6265799985698961596,
    7367482620586229882,
    3713379603860054506,
    5274302999252310238,
    1772833175495004234,
    760488549960904242,
    8790891562094926257,
    6649939104001475074,
    8449263315430857112,
    6608274874320083222,
    9137224925166801550,
    1484872645837357300,
    7179219274923512899,
    688411321486256431,
]

const SIMULATION_SEEDS = Int[
    2266917128577262934,
    4444760012277186539,
    3651174077807036556,
    2146669136077857564,
    46979147683037833,
    8553739648962259384,
    900358092944529194,
    7707664230584547405,
    3989794215397469049,
    3240280513414763330,
    1263509336207037935,
    7637340455438254344,
    7796462805545082083,
    2210936597111188594,
    2558470289426878386,
    7043570254294128523,
    4872794908088545657,
    1861119675183012121,
    2312206511568207185,
    85612170991494991,
    5859468785594321252,
    990102903587970797,
    7379468772804241650,
    7592386135322825472,
    7864611730695461658,
    2168010041185039217,
    1149255264383777742,
    7979128297625096098,
    4823780517559225600,
    8009638346654334670,
    3102192835628747375,
    19091115084160725,
]

const PRIMARY_PATH_ORDER = collect(1:PATH_COUNT)
const REVERSE_PATH_ORDER = reverse(PRIMARY_PATH_ORDER)
const REPLAY_PATH_IDS = [1]

const METHOD_ORIGIN_PATHS = Dict(
    "CommonSolve.step!_serial" => "src/one_step.jl",
    "NoShock_call" => "src/shocks/shocks.jl",
    "NoShock_constructor" => "src/shocks/shocks.jl",
    "collect_data!" => "src/utils/data.jl",
    "set_gross_domestic_product!" =>
        "src/agent_actions/aggregates.jl",
    "set_time!" => "src/agent_actions/aggregates.jl",
    "update_data_step!" => "src/utils/data.jl",
)

const PINNED_FILES = [
    Dict(
        "path" =>
            "scripts/us/forecasting/diagnostics/USRevisedDataABMConstructorGateV3.jl",
        "sha256" => V3_MODULE_SHA256,
        "role" =>
            "withdrawn_v3_constructor_gate_scaffolding_implementation",
    ),
    Dict(
        "path" =>
            "scripts/us/forecasting/diagnostics/revised_data/abm_constructor_gate_v3.toml",
        "sha256" => V3_PROTOCOL_SHA256,
        "role" =>
            "withdrawn_v3_constructor_gate_scaffolding_protocol",
    ),
    Dict(
        "path" =>
            "scripts/us/forecasting/targets/abm_gdp_operator/USABMGDPOperatorQualification.jl",
        "sha256" => OPERATOR_MODULE_SHA256,
        "role" => "accepted_synthetic_gdp_formula_oracle_implementation",
    ),
    Dict(
        "path" =>
            "scripts/us/forecasting/targets/abm_gdp_operator/operator_qualification.toml",
        "sha256" => OPERATOR_PROTOCOL_SHA256,
        "role" => "accepted_synthetic_gdp_formula_oracle_protocol",
    ),
    Dict(
        "path" => "src/one_step.jl",
        "sha256" =>
            "1446053cf507aeb76263114c7a721a1377b787657829ff28409318173d19f905",
        "role" => "serial_one_step_method_source",
    ),
    Dict(
        "path" => "src/utils/data.jl",
        "sha256" =>
            "3b42bcc124e5242c2a9b7303d9feddbfa7d6e54b07e62961ef646bf06ff8b5b8",
        "role" => "native_data_collection_and_gdp_measurement_source",
    ),
    Dict(
        "path" => "src/shocks/shocks.jl",
        "sha256" =>
            "80ed969e8af62a29c894023356efbffc04bc00585aae977fe60c17e0e6e0c0d6",
        "role" => "no_shock_constructor_and_call_source",
    ),
    Dict(
        "path" => "src/agent_actions/aggregates.jl",
        "sha256" =>
            "b8839ce9a624e25c94b1d039747dbd3cb882a4bb4efa4187642631544b440843",
        "role" => "gdp_and_model_time_transition_source",
    ),
    Dict(
        "path" => "data/austria/parameters/2010Q1.jld2",
        "sha256" =>
            "137b9b6c9968b902704026751390cbb93666768bf5b8a92dcb8782e465c257a2",
        "role" =>
            "beforeit_eager_import_side_data_austria_parameters",
    ),
    Dict(
        "path" =>
            "data/austria/initial_conditions/2010Q1.jld2",
        "sha256" =>
            "b47bdcb8cd36e2b57869f25a85bc6ab730feeccb3cd8dac236bf6807545fd087",
        "role" =>
            "beforeit_eager_import_side_data_austria_initial_conditions",
    ),
    Dict(
        "path" => "data/italy/parameters/2010Q1.jld2",
        "sha256" =>
            "e687fe848061f0c1847faadb723a0f370e45f7a555eba95e11b85dc58af93113",
        "role" =>
            "beforeit_eager_import_side_data_italy_parameters",
    ),
    Dict(
        "path" => "data/italy/initial_conditions/2010Q1.jld2",
        "sha256" =>
            "45660c8d3fcc2443cd510dbfcbc395b7f5a0607b4f5e1b75d5b35f820dd911f9",
        "role" =>
            "beforeit_eager_import_side_data_italy_initial_conditions",
    ),
    Dict(
        "path" => "data/steady_state/parameters/2010Q1.jld2",
        "sha256" =>
            "9204c044442d7f0f209aee957a5e11828939538bfd3e3bc8cc419237f73fcf85",
        "role" =>
            "beforeit_eager_import_side_data_steady_state_parameters",
    ),
    Dict(
        "path" =>
            "data/steady_state/initial_conditions/2010Q1.jld2",
        "sha256" =>
            "4b402e9d3e9aa5efc166e853be529a0ce09a40cce9033b6907f1c452582a923d",
        "role" =>
            "beforeit_eager_import_side_data_steady_state_initial_conditions",
    ),
    Dict(
        "path" =>
            "data/italy/calibration/calibration/2010Q1.jld2",
        "sha256" =>
            "49dc1a59ab9e73547463108556ca8bc1b30c72130365c63d7ca1cb49e84e276e",
        "role" =>
            "beforeit_eager_import_side_data_italy_calibration",
    ),
    Dict(
        "path" => "data/italy/calibration/figaro/2010.jld2",
        "sha256" =>
            "963de7c2fe2d2e89ae15a165ccea800d8af42380d9133eb2d310de588c19e1e6",
        "role" => "beforeit_eager_import_side_data_italy_figaro",
    ),
    Dict(
        "path" => "data/italy/calibration/data/1996.jld2",
        "sha256" =>
            "8fc52d9741af911cb035584f3df0fbcff4ae4487ed502b7470ce04a8402ef09f",
        "role" =>
            "beforeit_eager_import_side_data_italy_historical_data",
    ),
    Dict(
        "path" => "data/italy/calibration/ea/1996.jld2",
        "sha256" =>
            "2a60c7b7edeb00a08c6c2d03b7ecf71d7ad8e9f4ca15da9844f906ba851c8f3d",
        "role" =>
            "beforeit_eager_import_side_data_italy_ea_history",
    ),
]

const EXECUTION_COUNTS = Dict{String, Int}(
    "primary_constructions" => 32,
    "primary_steps" => 32,
    "primary_constructor_opening_collections" => 32,
    "primary_post_step_collections" => 32,
    "primary_total_collection_events" => 64,
    "reverse_constructions" => 32,
    "reverse_steps" => 32,
    "reverse_constructor_opening_collections" => 32,
    "reverse_post_step_collections" => 32,
    "reverse_total_collection_events" => 64,
    "replay_constructions" => 1,
    "replay_steps" => 1,
    "replay_constructor_opening_collections" => 1,
    "replay_post_step_collections" => 1,
    "replay_total_collection_events" => 2,
    "total_constructions" => 65,
    "total_steps" => 65,
    "total_constructor_opening_collections" => 65,
    "total_post_step_collections" => 65,
    "total_collection_events" => 130,
)

const DECLARATIONS = Dict{String, Bool}(
    "diagnostic_only" => true,
    "runner_implemented" => true,
    "revised_mixed_vintage" => true,
    "model_constructed" => true,
    "model_stepped_once_per_construction" => true,
    "software_one_step_verified" => true,
    "initial_transition_characterized" => true,
    "raw_opening_and_post_step_levels_preserved" => true,
    "opening_row_is_model_implied_unanchored" => true,
    "opening_row_is_official_truth" => false,
    "opening_macro_controls_used" => false,
    "path_order_invariance_executed" => true,
    "same_seed_replay_executed" => true,
    "v3_bootstrap_reexecuted" => true,
    "v3_acceptance_relied_upon" => false,
    "v2_raw_requalification_performed" => true,
    "synthetic_formula_oracle_used_only_on_pure_fixture" => true,
    "raw_diagnostic_path_values_returned" => true,
    "measurement_basis_discontinuity_preserved" => true,
    "truth_bearing_metadata_present_in_pinned_artifact" => true,
    "truth_bearing_raw_artifact_bytes_hashed" => true,
    "truth_bearing_metadata_deserialized" => false,
    "truth_values_consumed_by_model_or_operator" => false,
    "truth_values_used_for_scoring" => false,
    "us_evaluation_truth_used" => false,
    "us_nowcast_parameters_initial_conditions_selectively_deserialized" =>
        true,
    "package_import_side_data_deserialized" => true,
    "package_import_side_data_attested" => true,
    "package_import_side_data_passed_to_v4_constructor_or_gdp_operator" =>
        false,
    "package_precompile_workload_execution_guard_attested" => true,
    "package_precompile_workload_executed" => false,
    "precompiletools_clean_bootstrap_verified" => true,
    "precompiletools_verbose_false" => true,
    "ephemeral_jld2_snapshot_written" => true,
    "zero_filesystem_writes_claimed" => false,
    "independent_streams_established" => false,
    "input_lineage_verified" => false,
    "source_period_labels_authenticated" => false,
    "empirical_forecast_validated" => false,
    "forecast_artifact_emitted" => false,
    "forecast_artifact_serialized" => false,
    "score_computed" => false,
    "inference_run" => false,
    "origin_admissible" => false,
    "registry_write_allowed" => false,
    "promotion_eligible" => false,
    "class_h_allowed" => false,
    "production_allowed" => false,
    "reanchoring_used" => false,
    "bridge_adjustment_used" => false,
    "tier1_operator_approved" => false,
    "full_runtime_attestation" => false,
)

const ATTESTATION_LIMITS = Dict{String, Bool}(
    "repository_source_closure_validated" => true,
    "manifest_source_trees_validated" => true,
    "package_entrypoints_preresolved" => true,
    "effective_load_path_attested" => true,
    "effective_depot_path_enumerated" => true,
    "artifact_overrides_required_absent" => true,
    "method_origins_rechecked_after_execution" => true,
    "package_import_side_data_attested" => true,
    "compiled_modules_disabled" => true,
    "pkgimages_disabled" => true,
    "generating_output_required_false" => true,
    "package_precompile_workload_execution_guard_attested" => true,
    "precompiletools_clean_bootstrap_verified" => true,
    "precompiletools_verbose_required_false" => true,
    "binary_artifacts_attested" => false,
    "binary_jll_payloads_attested" => false,
    "compiled_caches_attested" => false,
    "depot_contents_attested" => false,
    "global_preferences_attested" => false,
    "julia_executable_bytes_attested" => false,
    "sysimage_bytes_attested" => false,
    "same_user_filesystem_race_resistance_attested" => false,
    "official_concept_bridge_validated" => false,
    "historical_origin_validated" => false,
    "empirical_accuracy_established" => false,
)

const BLOCKERS = [
    "REVISED_MIXED_VINTAGE_ORIGIN_NONADMISSIBLE",
    "HISTORICAL_ORIGIN_COUNT_ZERO",
    "US_EVALUATION_TRUTH_NOT_USED",
    "V3_CANONICAL_DISPOSITION_WITHDRAWN",
    "EMPIRICAL_FORECAST_NOT_VALIDATED",
    "OFFICIAL_CONCEPT_BRIDGE_UNVALIDATED",
    "INDEPENDENT_RNG_STREAMS_NOT_ESTABLISHED",
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

struct RawEngineeringGDPLevels
    opening_nominal_gdp::Float64
    post_nominal_gdp::Float64
    opening_real_gdp::Float64
    post_real_gdp::Float64
end

struct RawEngineeringGDPOperators
    real_gdp_growth::Float64
    gdp_deflator_inflation::Float64
end

struct OneStepMethodOriginRecord
    id::String
    relative_path::String
    defining_module::String
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

struct OneStepExecutionCounts
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
    return OneStepExecutionCounts(
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

attempt_execution_counts() =
    execution_counts(LAST_ATTEMPT_COUNTERS[])

struct OneStepPathResult
    path_id::Int
    construction_seed::Int
    simulation_seed::Int
    origin_period::String
    target_period::String
    collection_time::Vector{Int}
    opening_nominal_gdp::Float64
    post_nominal_gdp::Float64
    opening_real_gdp::Float64
    post_real_gdp::Float64
    real_gdp_growth::Float64
    gdp_deflator_inflation::Float64
    opening_state_sha256::String
    post_step_state_sha256::String
    post_collection_state_sha256::String
    input_parameter_sha256::String
    input_initial_conditions_sha256::String
    input_hashes_unchanged::Bool
    numeric_values_checked_after_collection::Int
end

Base.@kwdef struct OneStepGateV4Result
    schema_version::String
    contract_id::String
    information_track::String
    protocol_sha256::String
    v3_module_sha256::String
    v3_protocol_sha256::String
    withdrawn_v3_reference_result_sha256::String
    v3_acceptance_relied_upon::Bool
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
    v4_execution_envelope_sha256::String
    package_import_side_data_manifest_sha256::String
    selective_decode_contract::String
    constructor_method_origin_sha256::String
    one_step_method_origin_sha256::String
    compiled_modules_disabled::Bool
    pkgimages_disabled::Bool
    generating_output::Bool
    execution_count_scope::String
    execution_counts::OneStepExecutionCounts
    primary_paths::Vector{OneStepPathResult}
    reverse_paths::Vector{OneStepPathResult}
    replay_path::OneStepPathResult
    one_step_path_set_sha256::String
    opening_fingerprint_set_sha256::String
    deterministic_replay_equal::Bool
    path_order_invariant::Bool
    input_hashes_unchanged::Bool
    software_one_step_verified::Bool
    initial_transition_characterized::Bool
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
    package_import_side_data_passed_to_v4_constructor_or_gdp_operator::Bool
    package_precompile_workload_execution_guard_attested::Bool
    package_precompile_workload_executed::Bool
    precompiletools_clean_bootstrap_verified::Bool
    precompiletools_verbose_false::Bool
    ephemeral_jld2_snapshot_written::Bool
    zero_filesystem_writes_claimed::Bool
    independent_streams_established::Bool
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

function canonical(value)
    if value === nothing
        return "nothing:"
    elseif value isa Bool
        return value ? "bool:true" : "bool:false"
    elseif value isa Integer
        return "integer:" * string(value)
    elseif value isa AbstractFloat
        isfinite(value) || fail("cannot canonicalize a nonfinite number")
        return "float64:" * bitstring(Float64(value))
    elseif value isa AbstractString
        text = String(value)
        return "string:$(ncodeunits(text)):$text"
    elseif value isa AbstractVector
        encoded = canonical.(value)
        return "vector:$(length(encoded)):" * join(
            ("$(ncodeunits(item)):$item" for item in encoded),
            "",
        )
    elseif value isa AbstractDict
        all(key -> key isa AbstractString, keys(value)) ||
            fail("canonical dictionaries must use string keys")
        raw_keys = collect(keys(value))
        keys_as_strings = String.(raw_keys)
        length(unique(keys_as_strings)) == length(keys_as_strings) ||
            fail("canonical dictionary contains duplicate normalized keys")
        entries = sort!(collect(zip(keys_as_strings, raw_keys)); by = first)
        encoded = String[]
        for (key, raw_key) in entries
            item = canonical(value[raw_key])
            push!(
                encoded,
                "$(ncodeunits(key)):$key$(ncodeunits(item)):$item",
            )
        end
        return "dict:$(length(encoded)):" * join(encoded, "")
    elseif value isa RawEngineeringGDPLevels ||
            value isa RawEngineeringGDPOperators ||
            value isa OneStepMethodOriginRecord ||
            value isa OneStepExecutionCounts ||
            value isa OneStepPathResult ||
            value isa OneStepGateV4Result
        return canonical(
            Dict(
                String(field) => getfield(value, field) for
                    field in fieldnames(typeof(value))
            ),
        )
    end
    return fail("cannot canonicalize $(typeof(value))")
end

semantic_sha256(value) =
    sha256_hex(codeunits(canonical(value)))

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
        fail("$location keys differ from the frozen v4 contract")
    return value
end

function exact_hash(value, location)
    value isa AbstractString || fail("$location must be a SHA-256")
    text = String(value)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail("$location must be 64 lowercase hexadecimal characters")
    return text
end

function exact_integer(value, expected, location)
    typeof(value) === Int64 ||
        fail("$location must be exactly Int64")
    value == expected || fail("$location changed")
    return Int(value)
end

function exact_string(value, expected, location)
    typeof(value) === String ||
        fail("$location must be exactly String")
    value == expected || fail("$location changed")
    return String(value)
end

function exact_value(actual, expected, location)
    canonical(actual) == canonical(expected) ||
        fail("$location changed from the frozen v4 contract")
    return actual
end

function method_origin_tables()
    return [
        Dict(
                "id" => id,
                "relative_path" => METHOD_ORIGIN_PATHS[id],
                "defining_module" => "BeforeIT",
            ) for id in sort!(collect(keys(METHOD_ORIGIN_PATHS)))
    ]
end

function validate_protocol_semantics(document)
    exact_keys(
        document,
        (
            "schema_version",
            "contract_id",
            "information_track",
            "diagnostic_class",
            "model_variant",
            "model_constructor_id",
            "origin_period",
            "target_period",
            "horizon",
            "path_count",
            "master_seed",
            "seed_namespace_experiment_id",
            "model_id",
            "path_kind",
            "v3_module_sha256",
            "v3_protocol_sha256",
            "withdrawn_v3_reference_result_sha256",
            "v3_opening_fingerprint_set_sha256",
            "v2_protocol_sha256",
            "v2_qualified_input_sha256",
            "v2_seed_plan_sha256",
            "synthetic_operator_module_sha256",
            "synthetic_operator_protocol_sha256",
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
            "expected_one_step_path_set_sha256",
            "expected_path_one_post_collection_state_sha256",
            "expected_one_step_method_origin_sha256",
            "real_gdp_formula",
            "gdp_deflator_formula",
            "path_evaluation_rule",
            "origin_row_rule",
            "one_step_rule",
            "construction_input_rule",
            "synthetic_oracle_rule",
            "execution_count_scope",
            "primary_path_order",
            "reverse_path_order",
            "replay_path_ids",
            "construction_seeds",
            "simulation_seeds",
            "execution_counts",
            "declarations",
            "attestation_limits",
            "blockers",
            "prohibited_actions",
            "pinned_files",
            "method_origins",
        ),
        "v4 one-step protocol",
    )
    scalar_strings = Dict(
        "schema_version" => SCHEMA_VERSION,
        "contract_id" => CONTRACT_ID,
        "information_track" => INFORMATION_TRACK,
        "diagnostic_class" => DIAGNOSTIC_CLASS,
        "model_variant" => MODEL_VARIANT,
        "model_constructor_id" => MODEL_CONSTRUCTOR_ID,
        "origin_period" => ORIGIN_PERIOD,
        "target_period" => TARGET_PERIOD,
        "seed_namespace_experiment_id" =>
            SEED_NAMESPACE_EXPERIMENT_ID,
        "model_id" => MODEL_ID,
        "path_kind" => PATH_KIND,
        "v3_module_sha256" => V3_MODULE_SHA256,
        "v3_protocol_sha256" => V3_PROTOCOL_SHA256,
        "withdrawn_v3_reference_result_sha256" =>
            WITHDRAWN_V3_REFERENCE_RESULT_SHA256,
        "v3_opening_fingerprint_set_sha256" =>
            V3_OPENING_FINGERPRINT_SET_SHA256,
        "v2_protocol_sha256" => V2_PROTOCOL_SHA256,
        "v2_qualified_input_sha256" =>
            V2_QUALIFIED_INPUT_SHA256,
        "v2_seed_plan_sha256" => V2_SEED_PLAN_SHA256,
        "synthetic_operator_module_sha256" =>
            OPERATOR_MODULE_SHA256,
        "synthetic_operator_protocol_sha256" =>
            OPERATOR_PROTOCOL_SHA256,
        "julia_load_path_env" => JULIA_LOAD_PATH_ENV,
        "compiled_modules_mode" => "no",
        "pkgimages_mode" => "no",
        "precompiletools_uuid" => string(PRECOMPILETOOLS_UUID),
        "package_import_side_data_manifest_sha256" =>
            SIDE_DATA_MANIFEST_SHA256,
        "selective_decode_contract" => SELECTIVE_DECODE_CONTRACT,
        "expected_one_step_method_origin_sha256" =>
            ONE_STEP_METHOD_ORIGIN_SHA256,
        "real_gdp_formula" => REAL_GDP_FORMULA,
        "gdp_deflator_formula" => GDP_DEFLATOR_FORMULA,
        "path_evaluation_rule" =>
            "transform_each_raw_path_before_any_ensemble_summary",
        "origin_row_rule" =>
            "row_1_is_model_implied_unanchored_2026Q1_labeled_opening_and_row_2_is_h1_2026Q2",
        "one_step_rule" =>
            "seed_then_exactly_one_explicit_serial_step_then_exactly_one_collect_data",
        "construction_input_rule" =>
            "reassemble_fresh_qualified_inputs_for_every_construction",
        "synthetic_oracle_rule" =>
            "pure_formula_fixture_only_never_empirical_model_paths",
        "execution_count_scope" => EXECUTION_COUNT_SCOPE,
    )
    for (key, expected) in scalar_strings
        exact_string(document[key], expected, key)
    end
    for key in (
            "v3_module_sha256",
            "v3_protocol_sha256",
            "withdrawn_v3_reference_result_sha256",
            "v3_opening_fingerprint_set_sha256",
            "v2_protocol_sha256",
            "v2_qualified_input_sha256",
            "v2_seed_plan_sha256",
            "synthetic_operator_module_sha256",
            "synthetic_operator_protocol_sha256",
            "expected_one_step_path_set_sha256",
            "expected_path_one_post_collection_state_sha256",
            "expected_one_step_method_origin_sha256",
            "package_import_side_data_manifest_sha256",
        )
        exact_hash(document[key], key)
    end
    exact_integer(document["horizon"], HORIZON, "horizon")
    exact_integer(document["path_count"], PATH_COUNT, "path_count")
    exact_integer(document["master_seed"], MASTER_SEED, "master_seed")
    exact_integer(
        document["package_import_side_data_file_count"],
        SIDE_DATA_FILE_COUNT,
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
    exact_value(
        document["symbolic_load_path"],
        SYMBOLIC_LOAD_PATH,
        "symbolic_load_path",
    )
    exact_value(
        document["primary_path_order"],
        PRIMARY_PATH_ORDER,
        "primary_path_order",
    )
    exact_value(
        document["reverse_path_order"],
        REVERSE_PATH_ORDER,
        "reverse_path_order",
    )
    exact_value(
        document["replay_path_ids"],
        REPLAY_PATH_IDS,
        "replay_path_ids",
    )
    exact_value(
        document["construction_seeds"],
        CONSTRUCTION_SEEDS,
        "construction_seeds",
    )
    exact_value(
        document["simulation_seeds"],
        SIMULATION_SEEDS,
        "simulation_seeds",
    )
    length(unique([CONSTRUCTION_SEEDS; SIMULATION_SEEDS])) ==
        2PATH_COUNT ||
        fail("construction/simulation numeric seeds are not distinct")
    exact_value(
        document["execution_counts"],
        EXECUTION_COUNTS,
        "execution_counts",
    )
    exact_value(
        document["declarations"],
        DECLARATIONS,
        "declarations",
    )
    exact_value(
        document["attestation_limits"],
        ATTESTATION_LIMITS,
        "attestation_limits",
    )
    exact_value(document["blockers"], BLOCKERS, "blockers")
    exact_value(
        document["prohibited_actions"],
        String.(PROHIBITED_ACTION_LIST),
        "prohibited_actions",
    )
    exact_value(document["pinned_files"], PINNED_FILES, "pinned_files")
    exact_value(
        document["method_origins"],
        method_origin_tables(),
        "method_origins",
    )
    return document
end

function validate_protocol(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || fail("v4 one-step protocol is missing: $path")
    islink(path) &&
        fail("v4 one-step protocol must not be a symbolic link")
    bytes = read(path)
    digest = sha256_hex(bytes)
    digest == PROTOCOL_SHA256 ||
        fail("v4 one-step protocol SHA-256 changed: actual $digest")
    document = try
        TOML.parse(String(bytes))
    catch error
        fail(
            "v4 one-step protocol is invalid TOML: " *
                sprint(showerror, error),
        )
    end
    validate_protocol_semantics(document)
    return (; document, sha256 = digest)
end

protocol_sha256() = PROTOCOL_SHA256

function side_data_manifest_sha256()
    pins = filter(
        pin -> startswith(
            pin["role"],
            "beforeit_eager_import_side_data_",
        ),
        PINNED_FILES,
    )
    length(pins) == SIDE_DATA_FILE_COUNT ||
        fail("package import-side-data pin count changed")
    rows = sort!(
        ["$(pin["path"]):$(pin["sha256"])" for pin in pins],
    )
    digest = sha256_hex(codeunits(join(rows, "\n")))
    digest == SIDE_DATA_MANIFEST_SHA256 ||
        fail("package import-side-data manifest digest changed")
    return digest
end

function validate_source_pins(document = validate_protocol().document)
    exact_value(document["pinned_files"], PINNED_FILES, "pinned_files")
    snapshots = Dict{String, Any}()
    for pin in PINNED_FILES
        snapshots[pin["path"]] = V3.read_pinned_snapshot(
            pin["path"],
            pin["sha256"],
        )
    end
    V3.protocol_sha256() == V3_PROTOCOL_SHA256 ||
        fail("loaded v3 protocol identity changed")
    SyntheticOperator.validate_protocol().sha256 ==
        OPERATOR_PROTOCOL_SHA256 ||
        fail("loaded synthetic-operator protocol identity changed")
    Base.invokelatest(
        getfield(SyntheticOperator, :validate_source_pins),
    )
    side_data_manifest_sha256() ==
        document["package_import_side_data_manifest_sha256"] ||
        fail("protocol package import-side-data digest changed")
    return snapshots
end

function validate_uncompiled_package_load_envelope(
        document = validate_protocol().document;
        options = Base.JLOptions(),
        generating_output::Integer =
            ccall(:jl_generating_output, Cint, ()),
    )
    options.use_compiled_modules ==
        document["julia_use_compiled_modules_code"] ||
        fail(
        "v4 requires --compiled-modules=no before package load",
    )
    options.use_pkgimages ==
        document["julia_use_pkgimages_code"] ||
        fail("v4 requires --pkgimages=no before package load")
    typeof(generating_output) <: Integer &&
        !(generating_output isa Bool) ||
        fail("jl_generating_output must return an integer code")
    Int(generating_output) ==
        document["julia_generating_output_code"] ||
        fail("v4 requires jl_generating_output == 0")
    return (
        compiled_modules_disabled = true,
        pkgimages_disabled = true,
        generating_output = false,
    )
end

precompiletools_loaded() =
    V3.package_loaded(PRECOMPILETOOLS_PKGID, "PrecompileTools")

function validate_precompiletools_unloaded(
        loaded::Bool = precompiletools_loaded(),
    )
    loaded &&
        fail(
        "PrecompileTools must be absent at the clean v4 " *
            "package-load bootstrap",
    )
    return true
end

function validate_loaded_precompiletools()
    haskey(Base.loaded_modules, PRECOMPILETOOLS_PKGID) ||
        fail("BeforeIT did not load pinned PrecompileTools")
    precompiletools = Base.loaded_modules[PRECOMPILETOOLS_PKGID]
    V3.validate_loaded_package_entrypoint(
        precompiletools,
        PRECOMPILETOOLS_PKGID,
    )
    isdefined(precompiletools, :verbose) ||
        fail("loaded PrecompileTools has no verbose guard")
    verbose = getfield(precompiletools, :verbose)
    verbose isa Base.RefValue{Bool} ||
        fail("PrecompileTools.verbose must be RefValue{Bool}")
    verbose[] === false ||
        fail("PrecompileTools.verbose must remain false")
    return precompiletools
end

function validated_positive_level(value, location)
    typeof(value) === Float64 ||
        fail("$location must be native Float64")
    isfinite(value) || fail("$location must be finite")
    value > 0 || fail("$location must be strictly positive")
    return value
end

function validate_raw_levels(levels::RawEngineeringGDPLevels)
    for field in fieldnames(RawEngineeringGDPLevels)
        validated_positive_level(
            getfield(levels, field),
            "raw engineering $(String(field))",
        )
    end
    return levels
end

function compute_raw_engineering_operators(
        levels::RawEngineeringGDPLevels,
    )
    validate_raw_levels(levels)
    real_growth = 400.0 * (
        log(levels.post_real_gdp) -
            log(levels.opening_real_gdp)
    )
    deflator_inflation = 400.0 * (
        (
            log(levels.post_nominal_gdp) -
                log(levels.post_real_gdp)
        ) -
            (
            log(levels.opening_nominal_gdp) -
                log(levels.opening_real_gdp)
        )
    )
    isfinite(real_growth) ||
        fail("raw real-GDP operator produced a nonfinite value")
    isfinite(deflator_inflation) ||
        fail("raw GDP-deflator operator produced a nonfinite value")
    return RawEngineeringGDPOperators(
        real_growth,
        deflator_inflation,
    )
end

function validate_synthetic_formula_oracle()
    SyntheticOperator.validate_protocol().sha256 ==
        OPERATOR_PROTOCOL_SHA256 ||
        fail("synthetic formula-oracle protocol changed")
    SyntheticOperator.validate_source_pins()
    periods = [ORIGIN_PERIOD, TARGET_PERIOD]
    path_ids = [1, 2, 3]
    real = [100.0 100.0 100.0; 104.0 111.0 127.0]
    nominal = [100.0 100.0 100.0; 106.08 116.55 139.7]
    oracle = SyntheticOperator.compute_synthetic_operators(
        periods,
        path_ids,
        real,
        nominal;
        fixture_class = "SYNTHETIC_OPERATOR_TEST_FIXTURE",
        fixture_id = "synthetic-v4-pure-formula-oracle",
        path_kind = "RAW_MODEL_UNCORRECTED_SYNTHETIC",
        truth_accessed = false,
        empirical_path = false,
        class_h_used = false,
        bridge_adjusted = false,
        origin_reanchored = false,
    )
    raw_results = RawEngineeringGDPOperators[]
    for path_id in path_ids
        levels = RawEngineeringGDPLevels(
            nominal[1, path_id],
            nominal[2, path_id],
            real[1, path_id],
            real[2, path_id],
        )
        push!(
            raw_results,
            compute_raw_engineering_operators(levels),
        )
        isapprox(
            raw_results[end].real_gdp_growth,
            oracle.real_gdp_growth[1, path_id];
            rtol = 0,
            atol = 8eps(Float64),
        ) || fail("raw real-GDP kernel differs from synthetic oracle")
        isapprox(
            raw_results[end].gdp_deflator_inflation,
            oracle.gdp_deflator_inflation[1, path_id];
            rtol = 0,
            atol = 8eps(Float64),
        ) || fail("raw deflator kernel differs from synthetic oracle")
    end

    # At h=1 these fixtures deliberately share a common opening denominator.
    # Mean pathwise log growth therefore differs from the log transform of the
    # arithmetic mean post-step level solely through the numerator's Jensen
    # gap; no path-specific opening-level difference is needed.
    mean_pathwise_real =
        sum(result.real_gdp_growth for result in raw_results) /
        length(raw_results)
    transform_of_mean_real = 400.0 * (
        log(sum(real[2, :]) / length(path_ids)) -
            log(real[1, 1])
    )
    mean_pathwise_real != transform_of_mean_real ||
        fail("varying synthetic fixture did not expose pathwise-transform order")
    return semantic_sha256(
        Dict{String, Any}(
            "periods" => periods,
            "path_ids" => path_ids,
            "real" => vec(real),
            "nominal" => vec(nominal),
            "raw_results" => raw_results,
            "mean_pathwise_real" => mean_pathwise_real,
            "transform_of_mean_real" => transform_of_mean_real,
            "h1_common_opening_denominator" => true,
        ),
    )
end

function method_origin_record(
        method,
        id,
        expected_relative_path,
        beforeit,
    )
    method.module === beforeit ||
        fail("one-step method $id is not defined by BeforeIT")
    file = String(method.file)
    isabspath(file) ||
        fail("one-step method $id does not report an absolute path")
    expected = joinpath(REPOSITORY_ROOT, expected_relative_path)
    realpath(file) == realpath(expected) ||
        fail("one-step method $id resolves outside its pinned source")
    return OneStepMethodOriginRecord(
        String(id),
        String(expected_relative_path),
        string(nameof(method.module)),
    )
end

function collect_one_step_method_origins(beforeit)
    abstract_model = getfield(beforeit, :AbstractModel)
    no_shock_type = getfield(beforeit, :NoShock)
    no_shock = Base.invokelatest(no_shock_type)
    specifications = (
        (
            "CommonSolve.step!_serial",
            getfield(beforeit, :step!),
            (abstract_model,),
        ),
        ("NoShock_constructor", no_shock_type, ()),
        ("NoShock_call", no_shock, (abstract_model,)),
        (
            "collect_data!",
            getfield(beforeit, :collect_data!),
            (abstract_model,),
        ),
        (
            "set_gross_domestic_product!",
            getfield(beforeit, :set_gross_domestic_product!),
            (abstract_model,),
        ),
        (
            "set_time!",
            getfield(beforeit, :set_time!),
            (abstract_model,),
        ),
        (
            "update_data_step!",
            getfield(beforeit, :update_data_step!),
            (abstract_model,),
        ),
    )
    records = OneStepMethodOriginRecord[]
    for (id, callable, signature) in specifications
        method = try
            which(callable, signature)
        catch error
            fail(
                "could not resolve one-step method $id: " *
                    sprint(showerror, error),
            )
        end
        push!(
            records,
            method_origin_record(
                method,
                id,
                METHOD_ORIGIN_PATHS[id],
                beforeit,
            ),
        )
    end
    return validate_one_step_method_origins(records)
end

function validate_one_step_method_origins(records)
    records isa AbstractVector ||
        fail("one-step method origins must be a vector")
    length(records) == length(METHOD_ORIGIN_PATHS) ||
        fail("one-step method-origin count changed")
    by_id = Dict{String, OneStepMethodOriginRecord}()
    for record in records
        record isa OneStepMethodOriginRecord ||
            fail("unsupported one-step method-origin record")
        haskey(by_id, record.id) &&
            fail("duplicate one-step method origin $(record.id)")
        haskey(METHOD_ORIGIN_PATHS, record.id) ||
            fail("unknown one-step method origin $(record.id)")
        record.relative_path == METHOD_ORIGIN_PATHS[record.id] ||
            fail("one-step method-origin path changed for $(record.id)")
        record.defining_module == "BeforeIT" ||
            fail("one-step method-origin module changed for $(record.id)")
        by_id[record.id] = record
    end
    Set(keys(by_id)) == Set(keys(METHOD_ORIGIN_PATHS)) ||
        fail("one-step method-origin records are incomplete")
    return records
end

function one_step_method_origin_digest(records)
    validate_one_step_method_origins(records)
    rows = sort!(
        [
            "$(record.id):$(record.relative_path):$(record.defining_module)"
                for record in records
        ],
    )
    return sha256_hex(codeunits(join(rows, "\n")))
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
    return Base.invokelatest(
        constructor,
        parameters,
        initial_conditions,
    )
end

@noinline function serial_step_collect_with_seed!(
        step_function,
        collect_function,
        state_hasher,
        model,
        seed::Int,
        shock,
        transaction_markets::Tuple{Symbol, Symbol},
        counter::PhaseCounter,
    )
    V3.validate_rng_runtime()
    counter.steps += 1
    Random.seed!(seed)
    Base.invokelatest(
        step_function,
        model;
        parallel = false,
        shock! = shock,
        transaction_logger = nothing,
        transaction_markets = transaction_markets,
        opening_state_logger = nothing,
    )
    post_step_state_sha256 = state_hasher(model)
    counter.post_step_collections += 1
    Base.invokelatest(collect_function, model)
    return post_step_state_sha256
end

function exact_model_time(model, expected, location)
    typeof(model.agg.t) === Int ||
        fail("$location model time must be exactly Int")
    model.agg.t == expected ||
        fail("$location model time changed")
    return model.agg.t
end

function exact_collection_time(model, expected, location)
    typeof(model.data.collection_time) === Vector{Int} ||
        fail("$location collection_time must be exactly Vector{Int}")
    model.data.collection_time == expected ||
        fail("$location collection_time changed")
    return copy(model.data.collection_time)
end

function post_step_state_sha256(model)
    exact_model_time(model, 2, "post-step/pre-collection")
    exact_collection_time(
        model,
        [1],
        "post-step/pre-collection",
    )
    return V3.full_state_sha256(model)
end

function decode_model_inputs_selectively(snapshot, jld2)
    path, io = mktemp()
    try
        write(io, snapshot.bytes)
        flush(io)
        close(io)
        sha256_hex(read(path)) == snapshot.sha256 ||
            fail(
            "temporary selective-decode snapshot changed " *
                "before JLD2 read",
        )
        selected = try
            Base.invokelatest(
                getfield(jld2, :load),
                path,
                "parameters",
                "initial_conditions",
            )
        catch error
            fail(
                "pinned artifact selective JLD2 read failed: " *
                    sprint(showerror, error),
            )
        end
        selected isa Tuple && length(selected) == 2 ||
            fail(
            "selective JLD2 read must return exactly the two " *
                "requested objects",
        )
        parameters, initial_conditions = selected
        parameters isa AbstractDict ||
            fail("selectively decoded parameters must be a dictionary")
        initial_conditions isa AbstractDict ||
            fail(
            "selectively decoded initial_conditions must be a dictionary",
        )
        sha256_hex(read(path)) == snapshot.sha256 ||
            fail(
            "temporary selective-decode snapshot changed " *
                "during JLD2 read",
        )
        return (
            parameters = parameters,
            initial_conditions = initial_conditions,
        )
    finally
        isopen(io) && close(io)
        isfile(path) && rm(path)
    end
end

function reconstruct_frozen_period_axes(
        parameters,
        initial_conditions,
        v2,
    )
    origin_ordinal = V3.quarter_ordinal(V3.ARTIFACT_PERIOD)
    V3.quarter_string(origin_ordinal) == ORIGIN_PERIOD ||
        fail("frozen v3 artifact-period label no longer maps to 2026Q1")
    T_prime = V3.exact_constructor_integer(
        get(parameters, "T_prime", nothing),
        "selectively decoded parameters.T_prime";
        minimum = 1,
    ).int
    periods = Dict{String, Vector{String}}()
    for key in getfield(v2, :DYNAMIC_HISTORY_KEYS)
        haskey(initial_conditions, key) ||
            fail("selectively decoded inputs are missing $key")
        value = initial_conditions[key]
        value isa AbstractArray ||
            fail("selectively decoded dynamic history $key is not an array")
        Base.require_one_based_indexing(value)
        size(value, 1) >= T_prime ||
            fail("selectively decoded $key is shorter than T_prime")
        periods[key] = [
            V3.quarter_string(origin_ordinal - T_prime + index) for
                index in 1:size(value, 1)
        ]
        periods[key][T_prime] == ORIGIN_PERIOD ||
            fail("frozen period axis does not place origin at T_prime")
    end
    return periods
end

function qualify_selectively_decoded_inputs(
        selected,
        document,
        v2,
    )
    periods = reconstruct_frozen_period_axes(
        selected.parameters,
        selected.initial_conditions,
        v2,
    )
    qualified = V3.v2_call(
        v2,
        :qualify_base_origin_inputs,
        selected.parameters,
        selected.initial_conditions,
        periods;
        model_variant = MODEL_VARIANT,
        model_constructor_id = MODEL_CONSTRUCTOR_ID,
        class_h_used = false,
    )
    qualified.protocol_sha256 == document["v2_protocol_sha256"] ||
        fail("selective v2 protocol binding changed")
    qualified.qualified_input_sha256 ==
        document["v2_qualified_input_sha256"] ||
        fail("selective qualified-input SHA-256 changed")
    qualified.partition_sha256 == Dict(
        "parameters" => V3.V2_PARAMETER_SHA256,
        "static" => V3.V2_STATIC_SHA256,
        "dynamic" => V3.V2_DYNAMIC_SHA256,
    ) || fail("selective qualified-input partitions changed")
    seed_plan = V3.v2_call(
        v2,
        :derive_base_path_seed_plan,
        MASTER_SEED,
        qualified;
        experiment_id = SEED_NAMESPACE_EXPERIMENT_ID,
        model_id = MODEL_ID,
    )
    V3.v2_call(v2, :path_seed_plan_sha256, seed_plan, qualified) ==
        document["v2_seed_plan_sha256"] ||
        fail("selective qualification seed plan changed")
    getfield.(seed_plan, :construction_seed) ==
        document["construction_seeds"] ||
        fail("selective qualification construction seeds changed")
    getfield.(seed_plan, :simulation_seed) ==
        document["simulation_seeds"] ||
        fail("selective qualification simulation seeds changed")
    return qualified, seed_plan
end

function raw_levels_from_model(model)
    exact_collection_time(model, [1, 2], "post-collection")
    length(model.data.nominal_gdp) == 2 ||
        fail("native nominal_gdp must contain exactly two rows")
    length(model.data.real_gdp) == 2 ||
        fail("native real_gdp must contain exactly two rows")
    levels = RawEngineeringGDPLevels(
        model.data.nominal_gdp[1],
        model.data.nominal_gdp[2],
        model.data.real_gdp[1],
        model.data.real_gdp[2],
    )
    return validate_raw_levels(levels)
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
    parameter_hash =
        V3.v2_call(v2, :semantic_sha256, inputs.parameters)
    initial_hash =
        V3.v2_call(v2, :semantic_sha256, inputs.initial_conditions)
    model = try
        construct_fresh_with_seed(
            getfield(beforeit, :Model),
            record.construction_seed,
            inputs.parameters,
            inputs.initial_conditions,
            counter,
        )
    catch error
        error isa ABMOneStepGateV4Error && rethrow()
        fail(
            "BeforeIT.Model construction failed for path " *
                "$(record.path_id): $(sprint(showerror, error))",
        )
    end
    parameter_hash ==
        V3.v2_call(v2, :semantic_sha256, inputs.parameters) ||
        fail("constructor mutated path $(record.path_id) parameters")
    initial_hash ==
        V3.v2_call(
        v2,
        :semantic_sha256,
        inputs.initial_conditions,
    ) ||
        fail("constructor mutated path $(record.path_id) initial conditions")
    numeric_opening =
        V3.validate_model_structure(model, beforeit, counts)
    model.prop.use_opening_macro_controls === false ||
        fail("v4 forbids artifact opening-macro controls")
    exact_model_time(model, 1, "constructor opening")
    exact_collection_time(model, [1], "constructor opening")
    counter.constructor_opening_collections += 1
    opening_state_sha256 = V3.full_state_sha256(model)
    opening_levels = RawEngineeringGDPLevels(
        model.data.nominal_gdp[1],
        model.data.nominal_gdp[1],
        model.data.real_gdp[1],
        model.data.real_gdp[1],
    )
    validate_raw_levels(opening_levels)

    shock = Base.invokelatest(getfield(beforeit, :NoShock))
    transaction_markets = (:business_goods, :final_demand)
    post_step_sha256 = try
        serial_step_collect_with_seed!(
            getfield(beforeit, :step!),
            getfield(beforeit, :collect_data!),
            post_step_state_sha256,
            model,
            record.simulation_seed,
            shock,
            transaction_markets,
            counter,
        )
    catch error
        error isa ABMOneStepGateV4Error && rethrow()
        fail(
            "serial one-step execution failed for path " *
                "$(record.path_id): $(sprint(showerror, error))",
        )
    end
    exact_model_time(model, 2, "post-collection")
    collection_time =
        exact_collection_time(model, [1, 2], "post-collection")
    levels = raw_levels_from_model(model)
    operators = compute_raw_engineering_operators(levels)
    numeric_after = V3.validate_numeric_finiteness(model)
    numeric_after >= numeric_opening ||
        fail("numeric state cardinality unexpectedly shrank after one step")
    post_collection_sha256 = V3.full_state_sha256(model)
    parameters_unchanged = parameter_hash ==
        V3.v2_call(v2, :semantic_sha256, inputs.parameters)
    initial_unchanged = initial_hash ==
        V3.v2_call(
        v2,
        :semantic_sha256,
        inputs.initial_conditions,
    )
    parameters_unchanged && initial_unchanged ||
        fail("one-step execution mutated reconstructed input dictionaries")
    V3.v2_call(v2, :validate_qualified_inputs, qualified)
    return OneStepPathResult(
        record.path_id,
        record.construction_seed,
        record.simulation_seed,
        ORIGIN_PERIOD,
        TARGET_PERIOD,
        collection_time,
        levels.opening_nominal_gdp,
        levels.post_nominal_gdp,
        levels.opening_real_gdp,
        levels.post_real_gdp,
        operators.real_gdp_growth,
        operators.gdp_deflator_inflation,
        opening_state_sha256,
        post_step_sha256,
        post_collection_sha256,
        parameter_hash,
        initial_hash,
        true,
        numeric_after,
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
    path_order isa AbstractVector ||
        fail("path order must be a vector")
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

function path_payload(path::OneStepPathResult)
    return Dict(
        String(field) => getfield(path, field) for
            field in fieldnames(OneStepPathResult)
    )
end

function path_result_set_sha256(paths)
    paths isa AbstractVector ||
        fail("one-step paths must be a vector")
    length(paths) == PATH_COUNT ||
        fail("one-step path set must contain $PATH_COUNT paths")
    all(path -> path isa OneStepPathResult, paths) ||
        fail("one-step path set contains an unsupported record")
    normalized = sort!(collect(paths); by = path -> path.path_id)
    getfield.(normalized, :path_id) == collect(1:PATH_COUNT) ||
        fail("one-step path set IDs changed")
    return semantic_sha256(path_payload.(normalized))
end

function same_path_result(first::OneStepPathResult, second::OneStepPathResult)
    return canonical(first) == canonical(second)
end

function validate_execution_counts(
        counts::OneStepExecutionCounts,
        document,
    )
    expected = document["execution_counts"]
    for field in fieldnames(OneStepExecutionCounts)
        getfield(counts, field) == expected[String(field)] ||
            fail("execution count $(String(field)) changed")
    end
    return counts
end

function v4_execution_envelope_sha256(
        v3_execution_digest,
        load_path_attestation,
        document,
    )
    exact_hash(v3_execution_digest, "v3 execution-envelope SHA-256")
    return semantic_sha256(
        Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-abm-one-step-execution-envelope.v4",
            "v3_execution_envelope_sha256" =>
                v3_execution_digest,
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
                side_data_manifest_sha256(),
            "selective_decode_contract" =>
                document["selective_decode_contract"],
        ),
    )
end

function result_payload(result::OneStepGateV4Result)
    return Dict(
        String(field) => getfield(result, field) for
            field in fieldnames(OneStepGateV4Result) if
            field != :result_sha256
    )
end

function with_result_hash(result::OneStepGateV4Result)
    digest = semantic_sha256(result_payload(result))
    return OneStepGateV4Result(
        (
            getfield(result, field) for
                field in fieldnames(OneStepGateV4Result) if
                field != :result_sha256
        )...,
        digest,
    )
end

function _run_installed_one_step_gate()
    counters = AttemptCounters()
    LAST_ATTEMPT_COUNTERS[] = counters
    V3.validate_third_party_bootstrap_unloaded()
    validate_precompiletools_unloaded()
    protocol = validate_protocol()
    package_load_envelope =
        validate_uncompiled_package_load_envelope(protocol.document)
    initial_v4_snapshots = validate_source_pins(protocol.document)
    v3_protocol = V3.validate_protocol()
    v3_protocol.sha256 == protocol.document["v3_protocol_sha256"] ||
        fail("v4 did not bind the withdrawn v3 scaffolding protocol")
    load_path_attestation =
        V3.validate_load_path_environment(v3_protocol.document)
    execution_digest =
        V3.validate_execution_environment(v3_protocol.document)
    v4_execution_digest = v4_execution_envelope_sha256(
        execution_digest,
        load_path_attestation,
        protocol.document,
    )
    v4_execution_digest ==
        EXPECTED_V4_EXECUTION_ENVELOPE_SHA256 ||
        fail(
        "v4 execution-envelope digest changed: actual " *
            v4_execution_digest,
    )
    V3.validate_rng_runtime(v3_protocol.document["default_rng_type"])
    depot_attestation = V3.validate_artifact_overrides_absent()
    initial_v3_snapshots =
        V3.validate_pinned_files(v3_protocol.document)
    V3.validate_third_party_bootstrap_unloaded()
    dependency_attestation =
        V3.validate_dependency_source_trees(v3_protocol.document)
    V3.validate_third_party_bootstrap_unloaded()
    entrypoint_attestation =
        V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        dependency_attestation,
    )
    V3.validate_third_party_bootstrap_unloaded()
    synthetic_oracle_sha256 = validate_synthetic_formula_oracle()
    V3.validate_third_party_bootstrap_unloaded()
    validate_precompiletools_unloaded()
    validate_uncompiled_package_load_envelope(protocol.document)
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
    pre_jld2_sources =
        V3.validate_dependency_source_trees(v3_protocol.document)
    pre_jld2_sources.actual_digest ==
        dependency_attestation.actual_digest ||
        fail("dependency source trees changed before loading JLD2")
    pre_jld2_entrypoints =
        V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        pre_jld2_sources,
    )
    pre_jld2_entrypoints.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed before loading JLD2")
    V3.validate_jld2_unloaded()
    V3.validate_beforeit_unloaded()
    precompiletools = validate_loaded_precompiletools()
    validate_uncompiled_package_load_envelope(protocol.document)
    jld2 = V3.require_preresolved_package(
        V3.JLD2_PKGID,
        pre_jld2_sources,
        pre_jld2_entrypoints,
    )
    jld2_identity = V3.validate_jld2_module(jld2)
    V3.validate_load_path_environment(v3_protocol.document)
    V3.validate_beforeit_unloaded()
    selected = decode_model_inputs_selectively(
        initial_v3_snapshots[
            "data/us/baselines/US_2026Q1_nowcast.jld2",
        ],
        jld2,
    )
    qualified, seed_plan =
        qualify_selectively_decoded_inputs(
        selected,
        protocol.document,
        v2,
    )
    qualified.qualified_input_sha256 ==
        protocol.document["v2_qualified_input_sha256"] ||
        fail("v4 qualified-input identity changed")
    V3.v2_call(v2, :path_seed_plan_sha256, seed_plan, qualified) ==
        protocol.document["v2_seed_plan_sha256"] ||
        fail("v4 seed-plan identity changed")
    getfield.(seed_plan, :construction_seed) ==
        protocol.document["construction_seeds"] ||
        fail("v4 construction seeds changed")
    getfield.(seed_plan, :simulation_seed) ==
        protocol.document["simulation_seeds"] ||
        fail("v4 simulation seeds changed")
    reassembled =
        V3.v2_call(v2, :reassemble_model_inputs, qualified)
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
    pre_beforeit_sources.actual_digest ==
        dependency_attestation.actual_digest ||
        fail("dependency source trees changed before loading BeforeIT")
    pre_beforeit_entrypoints =
        V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        pre_beforeit_sources,
    )
    pre_beforeit_entrypoints.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed before loading BeforeIT")
    current_depot_attestation = V3.validate_artifact_overrides_absent()
    current_depot_attestation.path_count ==
        depot_attestation.path_count ||
        fail("DEPOT_PATH count changed before loading BeforeIT")
    current_depot_attestation.paths_sha256 ==
        depot_attestation.paths_sha256 ||
        fail("DEPOT_PATH changed before loading BeforeIT")
    V3.validate_jld2_module(jld2) == jld2_identity ||
        fail("JLD2 identity changed before loading BeforeIT")
    V3.validate_beforeit_resolution()
    V3.validate_beforeit_unloaded()
    validate_loaded_precompiletools() === precompiletools ||
        fail("PrecompileTools identity changed before BeforeIT load")
    validate_uncompiled_package_load_envelope(protocol.document)
    beforeit = V3.require_preresolved_package(
        V3.BEFOREIT_PKGID,
        pre_beforeit_sources,
        pre_beforeit_entrypoints,
    )

    V3.validate_loaded_package_entrypoint(
        beforeit,
        V3.BEFOREIT_PKGID,
    )
    validate_loaded_precompiletools() === precompiletools ||
        fail("PrecompileTools identity changed while loading BeforeIT")
    V3.validate_load_path_environment(v3_protocol.document)
    getfield(beforeit, :typeFloat) === Float64 ||
        fail("BeforeIT.typeFloat must be exactly Float64")
    getfield(beforeit, :typeInt) === Int ||
        fail("BeforeIT.typeInt must be exactly Int")
    constructor_method_records =
        V3.collect_method_origin_records(beforeit)
    constructor_method_digest =
        V3.method_origin_digest(constructor_method_records)
    one_step_method_records =
        collect_one_step_method_origins(beforeit)
    one_step_method_digest =
        one_step_method_origin_digest(one_step_method_records)
    one_step_method_digest ==
        protocol.document["expected_one_step_method_origin_sha256"] ||
        fail("one-step method-origin digest changed")

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

    primary_by_id =
        Dict(path.path_id => path for path in primary_paths)
    reverse_by_id =
        Dict(path.path_id => path for path in reverse_paths)
    Set(keys(primary_by_id)) == Set(1:PATH_COUNT) ||
        fail("primary one-step path IDs changed")
    Set(keys(reverse_by_id)) == Set(1:PATH_COUNT) ||
        fail("reverse one-step path IDs changed")
    path_order_invariant = all(
        same_path_result(primary_by_id[path_id], reverse_by_id[path_id])
            for path_id in 1:PATH_COUNT
    )
    path_order_invariant ||
        fail("one-step results changed under reverse path execution")
    deterministic_replay_equal =
        same_path_result(primary_by_id[1], replay_path)
    deterministic_replay_equal ||
        fail("same-seed one-step replay changed")

    opening_fingerprints =
        getfield.(primary_paths, :opening_state_sha256)
    opening_digest = V3.validate_stochastic_fingerprints(
        opening_fingerprints,
        replay_path.opening_state_sha256,
        protocol.document["v3_opening_fingerprint_set_sha256"],
    )
    getfield.(reverse_paths, :opening_state_sha256) ==
        reverse(opening_fingerprints) ||
        fail("reverse opening constructor fingerprints changed")
    one_step_digest = path_result_set_sha256(primary_paths)
    path_result_set_sha256(reverse_paths) == one_step_digest ||
        fail("reverse one-step path-set digest changed")
    expected_one_step_digest =
        protocol.document["expected_one_step_path_set_sha256"]
    expected_replay_state = protocol.document[
        "expected_path_one_post_collection_state_sha256",
    ]
    if expected_one_step_digest == ZERO_SHA256 ||
            expected_replay_state == ZERO_SHA256
        fail(
            "v4 one-step outputs remain unfrozen: " *
                "one_step_path_set_sha256=$one_step_digest " *
                "path_one_post_collection_state_sha256=" *
                replay_path.post_collection_state_sha256,
        )
    end
    one_step_digest == expected_one_step_digest ||
        fail(
        "one-step path-set digest changed: actual $one_step_digest",
    )
    replay_path.post_collection_state_sha256 ==
        expected_replay_state ||
        fail("path-one post-collection state digest changed")
    run_counts = validate_execution_counts(
        execution_counts(counters),
        protocol.document,
    )
    input_hashes_unchanged = all(
        path.input_hashes_unchanged for
            path in [primary_paths; reverse_paths; [replay_path]]
    )
    input_hashes_unchanged ||
        fail("one-step qualification mutated reconstructed inputs")

    V3.validate_execution_environment(v3_protocol.document)
    V3.v2_call(v2, :validate_protocol)
    V3.v2_call(v2, :validate_source_pins)
    final_v4_snapshots = validate_source_pins(protocol.document)
    for path in keys(initial_v4_snapshots)
        V3.validate_snapshot_unchanged(
            initial_v4_snapshots[path],
            final_v4_snapshots[path],
        )
    end
    final_v3_snapshots =
        V3.validate_pinned_files(v3_protocol.document)
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
        fail("dependency source trees changed during one-step execution")
    final_entrypoint_attestation =
        V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        final_dependency_attestation,
    )
    final_entrypoint_attestation.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed during one-step execution")
    final_depot_attestation = V3.validate_artifact_overrides_absent()
    final_depot_attestation.path_count ==
        depot_attestation.path_count ||
        fail("DEPOT_PATH count changed during one-step execution")
    final_depot_attestation.paths_sha256 ==
        depot_attestation.paths_sha256 ||
        fail("DEPOT_PATH changed during one-step execution")
    V3.validate_jld2_module(jld2) == jld2_identity ||
        fail("JLD2 identity changed during one-step execution")
    V3.method_origin_digest(
        V3.collect_method_origin_records(beforeit),
    ) == constructor_method_digest ||
        fail("constructor method origins changed during one-step execution")
    one_step_method_origin_digest(
        collect_one_step_method_origins(beforeit),
    ) == one_step_method_digest ||
        fail("one-step method origins changed during execution")
    V3.validate_loaded_package_entrypoint(
        beforeit,
        V3.BEFOREIT_PKGID,
    )
    validate_loaded_precompiletools() === precompiletools ||
        fail("PrecompileTools module identity changed")
    V3.v2_call(v2, :validate_qualified_inputs, qualified)
    qualified.qualified_input_sha256 ==
        V2_QUALIFIED_INPUT_SHA256 ||
        fail("qualified input changed during one-step execution")
    validate_protocol().sha256 == protocol.sha256 ||
        fail("v4 protocol changed during one-step execution")
    final_package_load_envelope =
        validate_uncompiled_package_load_envelope(protocol.document)
    final_package_load_envelope == package_load_envelope ||
        fail("uncompiled package-load envelope changed")

    result = OneStepGateV4Result(
        schema_version = SCHEMA_VERSION,
        contract_id = CONTRACT_ID,
        information_track = INFORMATION_TRACK,
        protocol_sha256 = protocol.sha256,
        v3_module_sha256 = V3_MODULE_SHA256,
        v3_protocol_sha256 = V3_PROTOCOL_SHA256,
        withdrawn_v3_reference_result_sha256 =
            WITHDRAWN_V3_REFERENCE_RESULT_SHA256,
        v3_acceptance_relied_upon = false,
        v2_protocol_sha256 = qualified.protocol_sha256,
        qualified_input_sha256 =
            qualified.qualified_input_sha256,
        seed_plan_sha256 = V3.v2_call(
            v2,
            :path_seed_plan_sha256,
            seed_plan,
            qualified,
        ),
        synthetic_operator_module_sha256 =
            OPERATOR_MODULE_SHA256,
        synthetic_operator_protocol_sha256 =
            OPERATOR_PROTOCOL_SHA256,
        synthetic_formula_oracle_sha256 =
            synthetic_oracle_sha256,
        dependency_source_tree_count =
            dependency_attestation.source_tree_count,
        dependency_source_tree_digest =
            dependency_attestation.actual_digest,
        package_entrypoint_count =
            entrypoint_attestation.package_entrypoint_count,
        package_entrypoint_digest =
            entrypoint_attestation.actual_digest,
        symbolic_load_path_sha256 =
            load_path_attestation.symbolic_sha256,
        expanded_load_path_sha256 =
            load_path_attestation.expanded_sha256,
        depot_path_count = depot_attestation.path_count,
        depot_paths_sha256 = depot_attestation.paths_sha256,
        v3_execution_envelope_sha256 = execution_digest,
        v4_execution_envelope_sha256 = v4_execution_digest,
        package_import_side_data_manifest_sha256 =
            side_data_manifest_sha256(),
        selective_decode_contract = SELECTIVE_DECODE_CONTRACT,
        constructor_method_origin_sha256 =
            constructor_method_digest,
        one_step_method_origin_sha256 = one_step_method_digest,
        compiled_modules_disabled =
            package_load_envelope.compiled_modules_disabled,
        pkgimages_disabled =
            package_load_envelope.pkgimages_disabled,
        generating_output =
            package_load_envelope.generating_output,
        execution_count_scope = EXECUTION_COUNT_SCOPE,
        execution_counts = run_counts,
        primary_paths = primary_paths,
        reverse_paths = reverse_paths,
        replay_path = replay_path,
        one_step_path_set_sha256 = one_step_digest,
        opening_fingerprint_set_sha256 = opening_digest,
        deterministic_replay_equal = deterministic_replay_equal,
        path_order_invariant = path_order_invariant,
        input_hashes_unchanged = input_hashes_unchanged,
        software_one_step_verified = true,
        initial_transition_characterized = true,
        raw_diagnostic_path_values_returned = true,
        measurement_basis_discontinuity_preserved = true,
        truth_bearing_metadata_present_in_pinned_artifact = true,
        truth_bearing_raw_artifact_bytes_hashed = true,
        truth_bearing_metadata_deserialized = false,
        truth_values_consumed_by_model_or_operator = false,
        truth_values_used_for_scoring = false,
        us_evaluation_truth_used = false,
        us_nowcast_parameters_initial_conditions_selectively_deserialized =
            true,
        package_import_side_data_deserialized = true,
        package_import_side_data_attested = true,
        package_import_side_data_passed_to_v4_constructor_or_gdp_operator =
            false,
        package_precompile_workload_execution_guard_attested = true,
        package_precompile_workload_executed = false,
        precompiletools_clean_bootstrap_verified = true,
        precompiletools_verbose_false = true,
        ephemeral_jld2_snapshot_written = true,
        zero_filesystem_writes_claimed = false,
        independent_streams_established = false,
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
        fail(
            "v4 result identity remains unfrozen: " *
                "result_sha256=$(with_hash.result_sha256)",
        )
    end
    with_hash.result_sha256 == EXPECTED_RESULT_SHA256 ||
        fail(
        "v4 result identity changed: actual " *
            with_hash.result_sha256,
    )
    return with_hash
end

function run_installed_one_step_gate()
    try
        return _run_installed_one_step_gate()
    catch error
        error isa ABMOneStepGateV4Error && rethrow()
        fail(
            "v4 one-step qualification failed closed: " *
                sprint(showerror, error),
        )
    end
end

function refuse_prohibited_action(action::Symbol)
    action in PROHIBITED_ACTIONS ||
        fail("unknown v4 one-step-gate action $(String(action))")
    return fail(
        "v4 one-step gate forbids $(String(action)); " *
            "the boundary is a nonadmitting software diagnostic",
    )
end

end # module
