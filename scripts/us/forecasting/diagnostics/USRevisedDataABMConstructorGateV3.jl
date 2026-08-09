module USRevisedDataABMConstructorGateV3

using LinearAlgebra
using Pkg
using Random
using SHA
using TOML
using UUIDs

export ABMConstructorGateV3Error,
    ConstructorDomainCounts,
    ConstructorGateV3Result,
    DependencySourceAttestation,
    PackageEntrypointAttestation,
    MethodOriginRecord,
    construct_with_seed,
    full_state_sha256,
    preflight_constructor_domain,
    protocol_sha256,
    read_pinned_snapshot,
    refuse_prohibited_action,
    run_installed_constructor_gate,
    validate_artifact_overrides_absent,
    validate_beforeit_unloaded,
    validate_dependency_source_trees,
    validate_execution_environment,
    validate_load_path_environment,
    validate_method_origin_records,
    validate_numeric_finiteness,
    validate_package_entrypoint_resolutions,
    require_preresolved_package,
    validate_protocol,
    validate_protocol_semantics,
    validate_rng_runtime,
    validate_snapshot_unchanged,
    validate_stochastic_fingerprints,
    validate_third_party_bootstrap_unloaded

const SCHEMA_VERSION =
    "beforeit-us-revised-data-abm-constructor-gate.v3"
const CONTRACT_ID =
    "beforeit-us-revised-data-abm-base-constructor-qualification.v3"
const INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
const DIAGNOSTIC_CLASS = "constructor_only_no_step_qualification"
const MODEL_VARIANT = "base"
const MODEL_CONSTRUCTOR_ID = "BeforeIT.Model"
const ORIGIN_PERIOD = "2026Q1"
const ARTIFACT_PERIOD = "2026-Q1"
const PATH_COUNT = 32
const REPLAY_COUNT = 1
const MASTER_SEED = 20260807
const EXPERIMENT_ID = "us-abm-constructor-gate-v3"
const MODEL_ID = "beforeit-us-abm-base"
const DEFAULT_RNG_TYPE = "Random.TaskLocalRNG"
const BEFOREIT_UUID =
    UUID("ca9fcad7-41d0-4f76-b1e5-366c28bce52e")
const BEFOREIT_PKGID = Base.PkgId(BEFOREIT_UUID, "BeforeIT")
const JLD2_UUID =
    UUID("033835bb-8acc-5ee8-8aae-3f567f8a3819")
const JLD2_PKGID = Base.PkgId(JLD2_UUID, "JLD2")
const JSON_UUID =
    UUID("682c06a0-de6a-54ab-a142-c8b1cf79cde6")
const JSON_PKGID = Base.PkgId(JSON_UUID, "JSON")
const JULIA_LOAD_PATH_ENV = "@:@stdlib"
const SYMBOLIC_LOAD_PATH = ["@", "@stdlib"]
const ARTIFACT_SHA256 =
    "eb8d28f6b2aef9b36cf294be8906d2d5481f1c8db66ea3d034b1a96f9194b0de"
const V2_MODULE_SHA256 =
    "817910109d03c8f0cbadd2c8f91dc55f28eda4051ef42993a2377f71d7dd34e3"
const V2_PROTOCOL_SHA256 =
    "efcdce3fb08e0b7496f9293c299787994eda85f2d7f750603a7f5a8b0856cab4"
const V2_QUALIFIED_INPUT_SHA256 =
    "bd9ac9c9054ef51289e5dfb51281e9f259684f19230e8c1a34c47f84d8062011"
const V2_PARAMETER_SHA256 =
    "2332724a2600198186e584fec04ad5bdf889fefd66818205e19b5d9580ac58f2"
const V2_STATIC_SHA256 =
    "feffe564fac157a5ddd0e8d3a112c028f588e697b243e0bd5ef02d62bcd4a808"
const V2_DYNAMIC_SHA256 =
    "29a0fcc671e6e067db846ce77ce556cee599c863108b6e56eb0c16ae2911328e"
const V2_SEED_PLAN_SHA256 =
    "7b42c8280d4ce398d9e426940480a635960817d1befddb9c801dbb1fcc94ec2c"
const DEPENDENCY_SOURCE_COUNT = 82
const MANIFEST_ENTRY_COUNT = 127
const MANIFEST_PATH_DEPENDENCY_COUNT = 1
const DEPENDENCY_MANIFEST_DIGEST =
    "6192d8216ea69f512df51e086a32c589f0677e81c1a7683b118a9b32ceecee0c"
const PACKAGE_ENTRYPOINT_COUNT = 83
const PACKAGE_ENTRYPOINT_DIGEST =
    "a98c02ba04a38a3fc1665fa4fb4e68516093c8d8a92cad738b30cf4623dd2146"
const EXPECTED_PATH_FINGERPRINT_SET_SHA256 =
    "2f359965fa08785101870a46332cdd66c91e744a664e9803fc198ef53e024a18"

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const SCRIPTS_PROJECT_PATH =
    joinpath(REPOSITORY_ROOT, "scripts", "us", "Project.toml")
const SCRIPTS_MANIFEST_PATH =
    joinpath(REPOSITORY_ROOT, "scripts", "us", "Manifest.toml")
const ARTIFACT_PATH = joinpath(
    REPOSITORY_ROOT,
    "data",
    "us",
    "baselines",
    "US_2026Q1_nowcast.jld2",
)
const PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_constructor_gate_v3.toml",
)
const PROTOCOL_SHA256 =
    "9bea1d110879275e33cc58d87a802c5e51e2b2f3d33929d7db073e81bd07166d"
const EXECUTION_ENVELOPE_PATH = joinpath(
    REPOSITORY_ROOT,
    "scripts",
    "us",
    "accounting",
    "USJuliaExecutionEnvelope.jl",
)
const V2_MODULE_PATH =
    joinpath(@__DIR__, "USRevisedDataABMOriginFirewallV2.jl")
const V2_PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_origin_firewall_v2.toml",
)
const REGISTRY_PATH = joinpath(
    REPOSITORY_ROOT,
    "scripts",
    "us",
    "forecasting",
    "registry",
    "USForecastRegistry.jl",
)

const PRELOAD_FILE_PINS = Dict(
    EXECUTION_ENVELOPE_PATH =>
        "53f5352818ed9ad51fc30d62f88924d1cde5875b96abe50b06f319e41803b295",
    V2_MODULE_PATH => V2_MODULE_SHA256,
    V2_PROTOCOL_PATH => V2_PROTOCOL_SHA256,
    REGISTRY_PATH =>
        "f1729f0d7bb06fd9cd11eaaad9d53c699896783f7634ffa4566674d13a463486",
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function include_pinned_source(path, expected_sha256)
    isfile(path) ||
        error("required constructor-gate source is missing: $path")
    islink(path) &&
        error("required constructor-gate source is a symbolic link: $path")
    bytes = read(path)
    sha256_hex(bytes) == expected_sha256 ||
        error("required constructor-gate source SHA-256 changed: $path")
    return Base.include_string(@__MODULE__, String(bytes), path)
end

for (path, expected_sha256) in PRELOAD_FILE_PINS
    bytes = read(path)
    sha256_hex(bytes) == expected_sha256 ||
        error("preload source SHA-256 changed: $path")
end
include_pinned_source(
    EXECUTION_ENVELOPE_PATH,
    PRELOAD_FILE_PINS[EXECUTION_ENVELOPE_PATH],
)

const ENV = USJuliaExecutionEnvelope
const V2_MODULE_REF = Ref{Union{Nothing, Module}}(nothing)

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

const PINNED_FILES = [
    Dict(
        "path" => "Project.toml",
        "sha256" =>
            "b68e5fcdd48d08abc2508a07e3b28bac382e8d53782d5868929638e9c4b76903",
        "role" => "beforeit_package_definition",
    ),
    Dict(
        "path" => "scripts/us/Project.toml",
        "sha256" =>
            "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c",
        "role" => "exact_active_project",
    ),
    Dict(
        "path" => "scripts/us/Manifest.toml",
        "sha256" =>
            "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263",
        "role" => "dependency_lock",
    ),
    Dict(
        "path" => "scripts/us/accounting/USJuliaExecutionEnvelope.jl",
        "sha256" =>
            "53f5352818ed9ad51fc30d62f88924d1cde5875b96abe50b06f319e41803b295",
        "role" => "canonical_local_execution_envelope",
    ),
    Dict(
        "path" =>
            "scripts/us/forecasting/diagnostics/USRevisedDataABMOriginFirewallV2.jl",
        "sha256" => V2_MODULE_SHA256,
        "role" => "frozen_v2_qualification_implementation",
    ),
    Dict(
        "path" =>
            "scripts/us/forecasting/diagnostics/revised_data/abm_origin_firewall_v2.toml",
        "sha256" => V2_PROTOCOL_SHA256,
        "role" => "frozen_v2_qualification_contract",
    ),
    Dict(
        "path" =>
            "scripts/us/forecasting/registry/USForecastRegistry.jl",
        "sha256" =>
            "f1729f0d7bb06fd9cd11eaaad9d53c699896783f7634ffa4566674d13a463486",
        "role" => "domain_separated_seed_derivation",
    ),
    Dict(
        "path" => "src/BeforeIT.jl",
        "sha256" =>
            "896578a133edcafa7b191e2869e6b6a01f948fb29201defc5d177ccc010e99c8",
        "role" => "resolved_beforeit_package_entrypoint",
    ),
    Dict(
        "path" => "data/us/baselines/US_2026Q1_nowcast.jld2",
        "sha256" => ARTIFACT_SHA256,
        "role" => "installed_revised_data_diagnostic_input",
    ),
]

const METHOD_ORIGIN_PATHS = Dict(
    "Model_dict" => "src/model_init/init.jl",
    "Model_tuple" => "src/model_init/agents.jl",
    "Properties" => "src/model_init/init_properties.jl",
    "Firms" => "src/model_init/init_firms.jl",
    "Workers" => "src/model_init/init_workers.jl",
    "Bank" => "src/model_init/init_banks.jl",
    "CentralBank" => "src/model_init/init_banks.jl",
    "Government" => "src/model_init/init_government.jl",
    "RestOfTheWorld" =>
        "src/model_init/init_rest_of_the_world.jl",
    "Aggregates" => "src/model_init/init_aggregates.jl",
    "Data" => "src/model_init/object_macro.jl",
    "randpl" => "src/utils/randpl.jl",
    "allocate_sector_initial_inventories" =>
        "src/model_init/init_firms.jl",
    "update_variables_with_totals!" => "src/model_init/init.jl",
    "collect_data!" => "src/utils/data.jl",
    "allocate_new_data!" => "src/utils/data.jl",
    "update_data_init!" => "src/utils/data.jl",
    "model_implied_opening_macro" => "src/utils/data.jl",
)

const PROHIBITED_ACTIONS = Set(
    [
        :step_model,
        :run_model,
        :solve_model,
        :simulate_model,
        :emit_forecast,
        :serialize_forecast,
        :truth_access,
        :score,
        :inference,
        :origin_admission,
        :promotion,
        :production_registry,
        :class_h,
    ],
)

const DECLARATIONS = Dict{String, Any}(
    "diagnostic_only" => true,
    "runner_implemented" => true,
    "model_constructed" => true,
    "model_stepped" => false,
    "forecast_emitted" => false,
    "forecast_serialized" => false,
    "truth_accessed" => false,
    "score_computed" => false,
    "inference_run" => false,
    "origin_admissible" => false,
    "promotion_eligible" => false,
    "production_registry_allowed" => false,
    "class_h_allowed" => false,
    "input_lineage_verified" => false,
    "source_period_labels_authenticated" => false,
    "period_axis_integrity_bound_to_artifact" => true,
    "v2_raw_requalification_performed" => true,
    "constructor_domain_admissibility_validated" => true,
    "runtime_numeric_types_validated" => true,
    "repository_source_closure_validated" => true,
    "manifest_source_trees_validated" => true,
    "effective_load_path_attested" => true,
    "package_entrypoints_preresolved" => true,
    "effective_depot_path_enumerated" => true,
    "artifact_overrides_absent" => true,
    "ephemeral_jld2_snapshot_written" => true,
    "zero_filesystem_writes_claimed" => false,
    "binary_artifacts_attested" => false,
    "binary_jll_payloads_attested" => false,
    "compiled_caches_attested" => false,
    "depot_contents_attested" => false,
    "global_preferences_attested" => false,
    "julia_executable_bytes_attested" => false,
    "sysimage_bytes_attested" => false,
    "same_user_filesystem_race_resistance_attested" => false,
    "full_runtime_attestation" => false,
    "empirical_evidence_produced" => false,
)

struct ABMConstructorGateV3Error <: Exception
    message::String
end

Base.showerror(io::IO, error::ABMConstructorGateV3Error) =
    print(io, error.message)

fail(message) =
    throw(ABMConstructorGateV3Error(String(message)))

struct PinnedSnapshot
    relative_path::String
    sha256::String
    bytes::Vector{UInt8}
    device::UInt64
    inode::UInt64
    size::Int64
    mtime::Float64
    ctime::Float64
end

struct DependencySourceAttestation
    manifest_entry_count::Int
    path_dependency_count::Int
    source_tree_count::Int
    manifest_digest::String
    actual_digest::String
    all_source_trees_match::Bool
    binary_artifacts_attested::Bool
    depot_contents_attested::Bool
    global_preferences_attested::Bool
end

struct PackageEntrypointAttestation
    package_entrypoint_count::Int
    expected_digest::String
    actual_digest::String
    all_entrypoints_match::Bool
end

struct ConstructorDomainCounts
    sector_count::Int
    active_population::Int
    inactive_workers::Int
    government_entities::Int
    foreign_consumers::Int
    firm_count::Int
    active_worker_count::Int
    employed_worker_count::Int
    unemployed_worker_count::Int
    sector_firm_counts::Vector{Int}
    sector_employment_counts::Vector{Int}
end

struct MethodOriginRecord
    id::String
    relative_path::String
    defining_module::String
end

struct ConstructorGateV3Result
    schema_version::String
    contract_id::String
    protocol_sha256::String
    artifact_sha256::String
    v2_protocol_sha256::String
    qualified_input_sha256::String
    qualified_partition_sha256::Dict{String, String}
    construction_seed_plan_sha256::String
    dependency_source_tree_count::Int
    dependency_source_tree_digest::String
    package_entrypoint_count::Int
    package_entrypoint_digest::String
    symbolic_load_path_sha256::String
    expanded_load_path_sha256::String
    depot_path_count::Int
    depot_paths_sha256::String
    artifact_overrides_absent::Bool
    method_origin_digest::String
    execution_envelope_sha256::String
    default_rng_type::String
    path_count::Int
    deterministic_replay_count::Int
    model_construction_count::Int
    numeric_values_checked_per_path::Int
    counts::ConstructorDomainCounts
    path_state_sha256::Vector{String}
    path_fingerprint_set_sha256::String
    replay_state_sha256::String
    deterministic_replay_equal::Bool
    distinct_stochastic_paths::Bool
    input_hashes_unchanged::Bool
    source_snapshots_unchanged::Bool
    model_constructed::Bool
    model_stepped::Bool
    forecast_emitted::Bool
    forecast_serialized::Bool
    truth_accessed::Bool
    score_computed::Bool
    inference_run::Bool
    origin_admissible::Bool
    promotion_eligible::Bool
    diagnostic_only::Bool
    binary_artifacts_attested::Bool
    depot_contents_attested::Bool
    global_preferences_attested::Bool
    full_runtime_attestation::Bool
    result_sha256::String
end

protocol_sha256() = PROTOCOL_SHA256

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
        normalized = String.(raw_keys)
        length(unique(normalized)) == length(normalized) ||
            fail("canonical dictionary contains duplicate normalized keys")
        entries = sort!(collect(zip(normalized, raw_keys)); by = first)
        encoded = String[]
        for (key, raw_key) in entries
            item = canonical(value[raw_key])
            push!(
                encoded,
                "$(ncodeunits(key)):$key$(ncodeunits(item)):$item",
            )
        end
        return "dict:$(length(encoded)):" * join(encoded, "")
    elseif value isa ConstructorDomainCounts
        return canonical(
            Dict(
                String(field) => getfield(value, field) for
                    field in fieldnames(ConstructorDomainCounts)
            ),
        )
    end
    return fail("cannot canonicalize $(typeof(value))")
end

semantic_sha256(value) = sha256_hex(codeunits(canonical(value)))

function expect_exact_keys(value, expected, location)
    value isa AbstractDict || fail("$location must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail("$location must use string keys")
    actual = String.(collect(keys(value)))
    length(actual) == length(expected) ||
        fail("$location must contain exactly $(length(expected)) entries")
    length(unique(actual)) == length(actual) ||
        fail("$location contains duplicate normalized string keys")
    Set(actual) == Set(String.(expected)) ||
        fail("$location keys differ from the frozen v3 contract")
    return value
end

function expect_hash(value, location)
    value isa AbstractString ||
        fail("$location must be a lowercase SHA-256")
    text = String(value)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail("$location must be 64 lowercase hexadecimal characters")
    return text
end

function expect_equal(actual, expected, location)
    canonical(actual) == canonical(expected) ||
        fail("$location changed from the frozen v3 contract")
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
    expect_exact_keys(
        document,
        (
            "schema_version",
            "contract_id",
            "information_track",
            "diagnostic_class",
            "model_variant",
            "model_constructor_id",
            "origin_period",
            "artifact_period",
            "artifact_sha256",
            "path_count",
            "deterministic_replay_count",
            "master_seed",
            "experiment_id",
            "model_id",
            "v2_protocol_sha256",
            "v2_qualified_input_sha256",
            "v2_parameter_sha256",
            "v2_static_sha256",
            "v2_dynamic_sha256",
            "v2_seed_plan_sha256",
            "construction_seeds",
            "expected_path_fingerprint_set_sha256",
            "manifest_entry_count",
            "manifest_path_dependency_count",
            "dependency_source_count",
            "dependency_manifest_digest",
            "package_entrypoint_count",
            "package_entrypoint_digest",
            "active_project_relative_path",
            "beforeit_resolved_relative_path",
            "beforeit_uuid",
            "beforeit_manifest_path",
            "julia_load_path_env",
            "symbolic_load_path",
            "expanded_load_path_roles",
            "default_rng_type",
            "execution_envelope",
            "constructor_preflight",
            "attestation_limits",
            "declarations",
            "pinned_files",
            "method_origins",
            "prohibited_actions",
        ),
        "v3 constructor-gate protocol",
    )
    scalar_expectations = Dict{String, Any}(
        "schema_version" => SCHEMA_VERSION,
        "contract_id" => CONTRACT_ID,
        "information_track" => INFORMATION_TRACK,
        "diagnostic_class" => DIAGNOSTIC_CLASS,
        "model_variant" => MODEL_VARIANT,
        "model_constructor_id" => MODEL_CONSTRUCTOR_ID,
        "origin_period" => ORIGIN_PERIOD,
        "artifact_period" => ARTIFACT_PERIOD,
        "artifact_sha256" => ARTIFACT_SHA256,
        "path_count" => PATH_COUNT,
        "deterministic_replay_count" => REPLAY_COUNT,
        "master_seed" => MASTER_SEED,
        "experiment_id" => EXPERIMENT_ID,
        "model_id" => MODEL_ID,
        "v2_protocol_sha256" => V2_PROTOCOL_SHA256,
        "v2_qualified_input_sha256" =>
            V2_QUALIFIED_INPUT_SHA256,
        "v2_parameter_sha256" => V2_PARAMETER_SHA256,
        "v2_static_sha256" => V2_STATIC_SHA256,
        "v2_dynamic_sha256" => V2_DYNAMIC_SHA256,
        "v2_seed_plan_sha256" => V2_SEED_PLAN_SHA256,
        "expected_path_fingerprint_set_sha256" =>
            EXPECTED_PATH_FINGERPRINT_SET_SHA256,
        "manifest_entry_count" => MANIFEST_ENTRY_COUNT,
        "manifest_path_dependency_count" =>
            MANIFEST_PATH_DEPENDENCY_COUNT,
        "dependency_source_count" => DEPENDENCY_SOURCE_COUNT,
        "dependency_manifest_digest" =>
            DEPENDENCY_MANIFEST_DIGEST,
        "package_entrypoint_count" => PACKAGE_ENTRYPOINT_COUNT,
        "package_entrypoint_digest" =>
            PACKAGE_ENTRYPOINT_DIGEST,
        "active_project_relative_path" =>
            "scripts/us/Project.toml",
        "beforeit_resolved_relative_path" => "src/BeforeIT.jl",
        "beforeit_uuid" => string(BEFOREIT_UUID),
        "beforeit_manifest_path" => "../..",
        "julia_load_path_env" => JULIA_LOAD_PATH_ENV,
        "default_rng_type" => DEFAULT_RNG_TYPE,
    )
    for (key, expected) in scalar_expectations
        expect_equal(document[key], expected, "protocol $key")
    end
    expect_equal(
        document["construction_seeds"],
        CONSTRUCTION_SEEDS,
        "construction seed vector",
    )
    expect_equal(
        document["execution_envelope"],
        ENV.CANONICAL_EXECUTION_ENVELOPE,
        "execution envelope",
    )
    expect_equal(
        document["symbolic_load_path"],
        SYMBOLIC_LOAD_PATH,
        "symbolic LOAD_PATH",
    )
    expect_equal(
        document["expanded_load_path_roles"],
        ["active_project", "julia_stdlib"],
        "expanded LOAD_PATH roles",
    )
    preflight = Dict{String, Any}(
        "integer_rule" =>
            "nonboolean_exact_Int_value_preserved_by_Float64_projection",
        "aggregate_rule" =>
            "BigInt_then_checked_Int_and_exact_Float64_projection",
        "sector_firm_floor" => "N_s[g]>=I_s[g]",
        "worker_capacity_rule" =>
            "H_act-sum(I_s)-1>=sum(N_s)",
        "known_nontermination_blocked" => "randpl_N_less_than_n",
        "known_bounds_failure_blocked" =>
            "worker_assignment_exceeds_active_worker_vector",
    )
    expect_equal(
        document["constructor_preflight"],
        preflight,
        "constructor preflight",
    )
    limits = Dict{String, Any}(
        "manifest_source_tree_sha1_validated" => true,
        "repository_source_closure_sha256_validated" => true,
        "jll_wrapper_source_trees_validated" => true,
        "effective_load_path_attested" => true,
        "package_entrypoints_preresolved" => true,
        "effective_depot_path_enumerated" => true,
        "artifact_overrides_required_absent" => true,
        "binary_artifacts_attested" => false,
        "binary_jll_payloads_attested" => false,
        "compiled_caches_attested" => false,
        "depot_contents_attested" => false,
        "global_preferences_attested" => false,
        "julia_executable_bytes_attested" => false,
        "sysimage_bytes_attested" => false,
        "same_user_filesystem_race_resistance_attested" => false,
        "effective_beforeit_numeric_types_checked" => true,
        "scope" =>
            "same_frozen_local_execution_envelope_diagnostic_only",
    )
    expect_equal(
        document["attestation_limits"],
        limits,
        "attestation limits",
    )
    expect_equal(document["declarations"], DECLARATIONS, "declarations")
    expect_equal(document["pinned_files"], PINNED_FILES, "pinned files")
    expect_equal(
        document["method_origins"],
        method_origin_tables(),
        "method origins",
    )
    expect_equal(
        document["prohibited_actions"],
        sort!(String.(collect(PROHIBITED_ACTIONS))),
        "prohibited actions",
    )
    expect_hash(
        document["expected_path_fingerprint_set_sha256"],
        "expected path fingerprint-set SHA-256",
    )
    return document
end

function validate_protocol(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || fail("v3 constructor-gate protocol is missing: $path")
    islink(path) &&
        fail("v3 constructor-gate protocol must not be a symbolic link")
    bytes = read(path)
    digest = sha256_hex(bytes)
    digest == PROTOCOL_SHA256 ||
        fail("v3 constructor-gate protocol SHA-256 changed")
    document = try
        TOML.parse(String(bytes))
    catch error
        fail(
            "v3 constructor-gate protocol is invalid TOML: " *
                sprint(showerror, error),
        )
    end
    validate_protocol_semantics(document)
    return (document = document, sha256 = digest)
end

function secure_relative_path(repository_root, relative_path)
    isabspath(relative_path) &&
        fail("pinned path must be repository-relative")
    components = splitpath(normpath(String(relative_path)))
    any(==(".."), components) &&
        fail("pinned path must not contain parent traversal")
    root = realpath(repository_root)
    current = root
    for component in components
        component in ("", ".") && continue
        current = joinpath(current, component)
        islink(current) &&
            fail("pinned path contains a symbolic link: $relative_path")
    end
    isfile(current) || fail("pinned file is missing: $relative_path")
    resolved = realpath(current)
    prefix = root * string(Base.Filesystem.path_separator)
    (resolved == root || startswith(resolved, prefix)) ||
        fail("pinned path escapes the repository: $relative_path")
    return resolved
end

function read_pinned_snapshot(
        relative_path::AbstractString,
        expected_sha256::AbstractString;
        repository_root::AbstractString = REPOSITORY_ROOT,
        require_single_link::Bool = true,
    )
    expect_hash(expected_sha256, "expected pinned-file SHA-256")
    path = secure_relative_path(repository_root, relative_path)
    before = stat(path)
    require_single_link && before.nlink == 1 ||
        !require_single_link ||
        fail("pinned file must have exactly one hard link: $relative_path")
    bytes = read(path)
    after = stat(path)
    identity_before = (
        before.device,
        before.inode,
        before.size,
        before.mtime,
        before.ctime,
    )
    identity_after = (
        after.device,
        after.inode,
        after.size,
        after.mtime,
        after.ctime,
    )
    identity_before == identity_after ||
        fail("pinned file changed while it was read: $relative_path")
    digest = sha256_hex(bytes)
    digest == expected_sha256 ||
        fail("pinned file SHA-256 changed: $relative_path")
    return PinnedSnapshot(
        String(relative_path),
        digest,
        bytes,
        before.device,
        before.inode,
        before.size,
        before.mtime,
        before.ctime,
    )
end

function validate_snapshot_unchanged(
        before::PinnedSnapshot,
        after::PinnedSnapshot,
    )
    before.relative_path == after.relative_path ||
        fail("snapshot paths differ")
    before.sha256 == after.sha256 ||
        fail("snapshot bytes changed: $(before.relative_path)")
    before.device == after.device ||
        fail("snapshot device changed: $(before.relative_path)")
    before.inode == after.inode ||
        fail("snapshot inode changed: $(before.relative_path)")
    before.size == after.size ||
        fail("snapshot size changed: $(before.relative_path)")
    return true
end

function validate_pinned_files(document)
    expect_equal(document["pinned_files"], PINNED_FILES, "pinned files")
    return Dict(
        pin["path"] => read_pinned_snapshot(
                pin["path"],
                pin["sha256"],
            ) for pin in PINNED_FILES
    )
end

function package_loaded(package_id, expected_name)
    haskey(Base.loaded_modules, package_id) && return true
    for loaded_module in values(Base.loaded_modules)
        String(nameof(loaded_module)) == expected_name && return true
    end
    return isdefined(Main, Symbol(expected_name))
end

beforeit_loaded() = package_loaded(BEFOREIT_PKGID, "BeforeIT")
jld2_loaded() = package_loaded(JLD2_PKGID, "JLD2")
json_loaded() = package_loaded(JSON_PKGID, "JSON")
v2_loaded() = V2_MODULE_REF[] !== nothing ||
    isdefined(@__MODULE__, :USRevisedDataABMOriginFirewallV2)

function validate_beforeit_unloaded(loaded::Bool = beforeit_loaded())
    loaded &&
        fail("BeforeIT was loaded before v3 source validation")
    return true
end

function validate_jld2_unloaded(loaded::Bool = jld2_loaded())
    loaded &&
        fail("JLD2 was loaded before dependency source-tree validation")
    return true
end

function validate_third_party_bootstrap_unloaded(;
        json_is_loaded::Bool = json_loaded(),
        jld2_is_loaded::Bool = jld2_loaded(),
        beforeit_is_loaded::Bool = beforeit_loaded(),
        v2_is_loaded::Bool = v2_loaded(),
    )
    json_is_loaded &&
        fail("JSON was loaded before v3 bootstrap attestation")
    jld2_is_loaded &&
        fail("JLD2 was loaded before v3 bootstrap attestation")
    beforeit_is_loaded &&
        fail("BeforeIT was loaded before v3 bootstrap attestation")
    v2_is_loaded &&
        fail("frozen v2 was loaded before v3 bootstrap attestation")
    return true
end

function validate_load_path_environment(
        document;
        environment = Base.ENV,
        symbolic = Base.LOAD_PATH,
        expanded = Base.load_path(),
    )
    get(environment, "JULIA_LOAD_PATH", nothing) ==
        document["julia_load_path_env"] ||
        fail("JULIA_LOAD_PATH must be exactly $JULIA_LOAD_PATH_ENV")
    typeof(symbolic) === Vector{String} ||
        fail("symbolic LOAD_PATH must be exactly Vector{String}")
    symbolic == document["symbolic_load_path"] ||
        fail("symbolic LOAD_PATH differs from the closed v3 stack")
    typeof(expanded) === Vector{String} ||
        fail("expanded Base.load_path() must be exactly Vector{String}")
    expected_expanded = [SCRIPTS_PROJECT_PATH, Sys.STDLIB]
    expanded == expected_expanded ||
        fail("expanded Base.load_path() differs from active-project/stdlib")
    for (index, path) in enumerate(expanded)
        typeof(path) === String ||
            fail("expanded LOAD_PATH[$index] must be exactly String")
        isabspath(path) ||
            fail("expanded LOAD_PATH[$index] must be absolute")
        path == normpath(path) ||
            fail("expanded LOAD_PATH[$index] must be normalized")
        ispath(path) ||
            fail("expanded LOAD_PATH[$index] does not exist")
    end
    return (
        symbolic = copy(symbolic),
        expanded = copy(expanded),
        symbolic_sha256 = semantic_sha256(symbolic),
        expanded_sha256 = semantic_sha256(expanded),
    )
end

function validate_execution_environment(
        document;
        active_project = Base.active_project(),
        runtime_envelope = ENV.current_execution_envelope(),
        environment = Base.ENV,
        symbolic_load_path = Base.LOAD_PATH,
        expanded_load_path = Base.load_path(),
    )
    validate_load_path_environment(
        document;
        environment,
        symbolic = symbolic_load_path,
        expanded = expanded_load_path,
    )
    active_project isa AbstractString ||
        fail("an active Julia project is required")
    isfile(active_project) ||
        fail("active Julia project is missing")
    realpath(active_project) == realpath(SCRIPTS_PROJECT_PATH) ||
        fail("active project must be exactly scripts/us/Project.toml")
    config = Dict{String, Any}(
        "execution_envelope" => document["execution_envelope"],
    )
    try
        ENV.validate_build_environment(config, runtime_envelope)
    catch error
        fail(
            "canonical local execution envelope mismatch: " *
                sprint(showerror, error),
        )
    end
    return semantic_sha256(runtime_envelope)
end

function validate_path_components_no_symlink(path, location)
    path isa AbstractString ||
        fail("$location must be a filesystem path")
    text = String(path)
    isabspath(text) || fail("$location must be absolute")
    text == normpath(text) ||
        fail("$location must be lexically normalized")
    chain = String[]
    current = text
    while true
        push!(chain, current)
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    for component_path in reverse(chain)
        islink(component_path) &&
            fail("$location contains a symbolic-link component")
        if ispath(component_path) &&
                component_path != text &&
                !isdir(component_path)
            fail("$location has a nondirectory ancestor")
        end
    end
    ispath(text) && !isdir(text) &&
        fail("$location exists but is not a directory")
    return text
end

function validate_file_path_no_symlink(path, location)
    path isa AbstractString ||
        fail("$location must be a filesystem path")
    text = String(path)
    isabspath(text) || fail("$location must be absolute")
    text == normpath(text) ||
        fail("$location must be lexically normalized")
    chain = String[]
    current = text
    while true
        push!(chain, current)
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    for component_path in reverse(chain)
        islink(component_path) &&
            fail("$location contains a symbolic-link component")
        if ispath(component_path) &&
                component_path != text &&
                !isdir(component_path)
            fail("$location has a nondirectory ancestor")
        end
    end
    isfile(text) || fail("$location is not a regular file")
    return text
end

function validate_artifact_overrides_absent(
        depot_paths = Base.DEPOT_PATH,
    )
    depot_paths isa AbstractVector ||
        fail("effective DEPOT_PATH must be a vector")
    isempty(depot_paths) &&
        fail("effective DEPOT_PATH must not be empty")
    normalized = String[]
    identities = String[]
    for (index, depot) in enumerate(depot_paths)
        path = validate_path_components_no_symlink(
            depot,
            "DEPOT_PATH[$index]",
        )
        push!(normalized, path)
        identity = isdir(path) ? realpath(path) : path
        identity in identities &&
            fail("effective DEPOT_PATH contains duplicate locations")
        push!(identities, identity)
        artifacts_path = joinpath(path, "artifacts")
        validate_path_components_no_symlink(
            artifacts_path,
            "DEPOT_PATH[$index]/artifacts",
        )
        override_path = joinpath(artifacts_path, "Overrides.toml")
        (ispath(override_path) || islink(override_path)) &&
            fail(
            "artifact override file must be absent: " *
                override_path,
        )
    end
    return (
        paths = normalized,
        path_count = length(normalized),
        paths_sha256 = semantic_sha256(normalized),
        artifact_overrides_absent = true,
    )
end

function validate_rng_runtime(
        expected_type::AbstractString = DEFAULT_RNG_TYPE,
    )
    String(expected_type) == DEFAULT_RNG_TYPE ||
        fail("protocol default RNG type changed")
    actual_type = typeof(Random.default_rng())
    actual_type === Random.TaskLocalRNG ||
        fail(
        "default RNG type must be exactly Random.TaskLocalRNG",
    )
    actual =
        "$(parentmodule(actual_type)).$(nameof(actual_type))"
    actual == DEFAULT_RNG_TYPE ||
        fail("default RNG canonical type identity changed")
    return actual
end

function manifest_entries(manifest)
    haskey(manifest, "deps") ||
        fail("scripts/us Manifest.toml has no deps table")
    result = Dict{UUID, Tuple{String, Dict{String, Any}}}()
    for (name, raw_entries) in manifest["deps"]
        raw_entries isa AbstractVector ||
            fail("manifest dependency $name is not an array of tables")
        length(raw_entries) == 1 ||
            fail("manifest dependency $name must have one locked entry")
        raw_entry = only(raw_entries)
        entry = Dict{String, Any}(
            String(key) => value for (key, value) in raw_entry
        )
        uuid = try
            UUID(entry["uuid"])
        catch
            fail("manifest dependency $name has an invalid UUID")
        end
        haskey(result, uuid) &&
            fail("manifest contains duplicate dependency UUID $uuid")
        result[uuid] = (String(name), entry)
    end
    return result
end

function validate_dependency_source_trees(document)
    manifest_snapshot = read_pinned_snapshot(
        "scripts/us/Manifest.toml",
        PINNED_FILES[3]["sha256"],
    )
    manifest = try
        TOML.parse(String(manifest_snapshot.bytes))
    catch error
        fail("pinned manifest is invalid TOML: $(sprint(showerror, error))")
    end
    entries = manifest_entries(manifest)
    length(entries) == document["manifest_entry_count"] ||
        fail("manifest entry count changed")
    package_info = Pkg.dependencies()
    length(package_info) == length(entries) ||
        fail("active dependency graph differs from the pinned manifest")
    expected_rows = String[]
    actual_rows = String[]
    source_count = 0
    path_count = 0
    for (uuid, (name, entry)) in entries
        haskey(package_info, uuid) ||
            fail("active dependency graph is missing $name")
        info = package_info[uuid]
        info.name == name ||
            fail("active dependency name differs for UUID $uuid")
        if haskey(entry, "path")
            path_count += 1
            name == "BeforeIT" ||
                fail("unexpected path dependency $name")
            entry["path"] == document["beforeit_manifest_path"] ||
                fail("BeforeIT manifest path changed")
            info.is_tracking_path ||
                fail("BeforeIT is not resolved as a path dependency")
            info.source isa AbstractString ||
                fail("BeforeIT dependency source path is missing")
            realpath(info.source) == realpath(REPOSITORY_ROOT) ||
                fail("BeforeIT path dependency does not resolve to the repository")
        end
        haskey(entry, "git-tree-sha1") || continue
        source_count += 1
        expected = String(entry["git-tree-sha1"])
        occursin(r"^[0-9a-f]{40}$", expected) ||
            fail("manifest tree hash is invalid for $name")
        info.tree_hash === nothing &&
            fail("active dependency $name has no tree hash")
        string(info.tree_hash) == expected ||
            fail("active dependency tree record differs for $name")
        info.source isa AbstractString ||
            fail("active dependency $name has no source directory")
        source_root = validate_path_components_no_symlink(
            normpath(abspath(info.source)),
            "active dependency source directory for $name",
        )
        isdir(source_root) ||
            fail("active dependency source directory is missing for $name")
        actual = try
            bytes2hex(Pkg.GitTools.tree_hash(source_root))
        catch error
            fail(
                "could not hash active dependency source tree $name: " *
                    sprint(showerror, error),
            )
        end
        actual == expected ||
            fail("installed dependency source tree changed for $name")
        push!(expected_rows, "$(uuid):$name:$expected")
        push!(actual_rows, "$(uuid):$name:$actual")
    end
    source_count == document["dependency_source_count"] ||
        fail("dependency source-tree count changed")
    path_count == document["manifest_path_dependency_count"] ||
        fail("manifest path-dependency count changed")
    expected_digest =
        sha256_hex(codeunits(join(sort!(expected_rows), "\n")))
    actual_digest =
        sha256_hex(codeunits(join(sort!(actual_rows), "\n")))
    expected_digest == document["dependency_manifest_digest"] ||
        fail("manifest dependency-tree digest changed")
    actual_digest == expected_digest ||
        fail("installed dependency source-tree digest changed")
    return DependencySourceAttestation(
        length(entries),
        path_count,
        source_count,
        expected_digest,
        actual_digest,
        true,
        false,
        false,
        false,
    )
end

function validate_package_entrypoint_resolutions(
        document,
        source_attestation::DependencySourceAttestation;
        package_info = Pkg.dependencies(),
        locate_package = Base.locate_package,
    )
    source_attestation.all_source_trees_match ||
        fail("package entrypoints require matching dependency source trees")
    source_attestation.source_tree_count ==
        document["dependency_source_count"] ||
        fail("package entrypoints received the wrong source attestation")
    source_attestation.actual_digest ==
        document["dependency_manifest_digest"] ||
        fail("package entrypoints received a changed source-tree digest")
    manifest_snapshot = read_pinned_snapshot(
        "scripts/us/Manifest.toml",
        PINNED_FILES[3]["sha256"],
    )
    manifest = try
        TOML.parse(String(manifest_snapshot.bytes))
    catch error
        fail("pinned manifest is invalid TOML: $(sprint(showerror, error))")
    end
    entries = manifest_entries(manifest)
    candidates = Tuple{UUID, String, Dict{String, Any}}[]
    for (uuid, (name, entry)) in entries
        (haskey(entry, "git-tree-sha1") || haskey(entry, "path")) ||
            continue
        push!(candidates, (uuid, name, entry))
    end
    sort!(candidates; by = item -> (item[2], string(item[1])))
    expected_rows = String[]
    actual_rows = String[]
    for (uuid, name, entry) in candidates
        haskey(package_info, uuid) ||
            fail("active dependency graph is missing entrypoint package $name")
        info = package_info[uuid]
        info.name == name ||
            fail("entrypoint package name differs for UUID $uuid")
        info.source isa AbstractString ||
            fail("entrypoint package $name has no source directory")
        source_root = validate_path_components_no_symlink(
            normpath(abspath(info.source)),
            "entrypoint package source directory for $name",
        )
        relative_entrypoint = String(
            get(entry, "entryfile", joinpath("src", "$name.jl")),
        )
        isabspath(relative_entrypoint) &&
            fail("manifest entrypoint must be relative for $name")
        any(==(".."), splitpath(normpath(relative_entrypoint))) &&
            fail("manifest entrypoint traverses outside $name")
        expected = validate_file_path_no_symlink(
            normpath(joinpath(source_root, relative_entrypoint)),
            "expected package entrypoint for $name",
        )
        source_prefix =
            realpath(source_root) *
            string(Base.Filesystem.path_separator)
        startswith(realpath(expected), source_prefix) ||
            fail("expected package entrypoint escapes source tree for $name")
        located = try
            locate_package(Base.PkgId(uuid, name))
        catch error
            fail(
                "could not pre-resolve package entrypoint $name: " *
                    sprint(showerror, error),
            )
        end
        located isa AbstractString ||
            fail("Base.locate_package could not pre-resolve $name")
        isabspath(located) ||
            fail("pre-resolved package entrypoint is not absolute for $name")
        validate_file_path_no_symlink(
            normpath(String(located)),
            "pre-resolved package entrypoint for $name",
        )
        realpath(located) == realpath(expected) ||
            fail(
                "pre-resolved package entrypoint differs from the " *
                    "source-tree-hashed $name entrypoint",
            )
        source_record = haskey(entry, "path") ?
            "path:$(entry["path"])" :
            "tree:$(entry["git-tree-sha1"])"
        row =
            "$(uuid):$name:$source_record:" *
            replace(relative_entrypoint, '\\' => '/')
        push!(expected_rows, row)
        push!(actual_rows, row)
    end
    length(candidates) == document["package_entrypoint_count"] ||
        fail("package entrypoint count changed")
    expected_digest =
        sha256_hex(codeunits(join(sort!(expected_rows), "\n")))
    actual_digest =
        sha256_hex(codeunits(join(sort!(actual_rows), "\n")))
    expected_digest == document["package_entrypoint_digest"] ||
        fail("package entrypoint contract digest changed")
    actual_digest == expected_digest ||
        fail("pre-resolved package entrypoint digest changed")
    return PackageEntrypointAttestation(
        length(candidates),
        expected_digest,
        actual_digest,
        true,
    )
end

function require_preresolved_package(
        package_id::Base.PkgId,
        source_attestation::DependencySourceAttestation,
        entrypoint_attestation::PackageEntrypointAttestation;
        package_info = Pkg.dependencies(),
        locate_package = Base.locate_package,
        loader = Base.require,
    )
    source_attestation.all_source_trees_match ||
        fail("package load requires matching dependency source trees")
    source_attestation.source_tree_count == DEPENDENCY_SOURCE_COUNT ||
        fail("package load received the wrong source-tree count")
    source_attestation.actual_digest == DEPENDENCY_MANIFEST_DIGEST ||
        fail("package load received a changed source-tree digest")
    entrypoint_attestation.all_entrypoints_match ||
        fail("package load requires matching entrypoints")
    entrypoint_attestation.package_entrypoint_count ==
        PACKAGE_ENTRYPOINT_COUNT ||
        fail("package load received the wrong entrypoint count")
    entrypoint_attestation.actual_digest == PACKAGE_ENTRYPOINT_DIGEST ||
        fail("package load received a changed entrypoint digest")
    expected = expected_package_entrypoint(
        package_info,
        package_id.uuid,
        package_id.name,
    )
    located = try
        locate_package(package_id)
    catch error
        fail(
            "could not resolve $(package_id.name) immediately before load: " *
                sprint(showerror, error),
        )
    end
    located isa AbstractString ||
        fail(
            "Base.locate_package could not resolve $(package_id.name) " *
                "immediately before load",
        )
    isabspath(located) ||
        fail(
            "pre-load $(package_id.name) entrypoint is not absolute",
        )
    validate_file_path_no_symlink(
        normpath(String(located)),
        "pre-load $(package_id.name) entrypoint",
    )
    realpath(located) == expected ||
        fail(
            "pre-load $(package_id.name) entrypoint differs from its " *
                "source-tree-validated manifest location",
        )
    return loader(package_id)
end

function expected_package_entrypoint(
        package_info,
        uuid::UUID,
        name::AbstractString,
    )
    haskey(package_info, uuid) ||
        fail("active dependency graph is missing $name")
    info = package_info[uuid]
    info.name == name ||
        fail("active dependency name differs for UUID $uuid")
    info.source isa AbstractString ||
        fail("active dependency $name has no source directory")
    source_root = validate_path_components_no_symlink(
        normpath(abspath(info.source)),
        "active dependency source directory for $name",
    )
    expected = validate_file_path_no_symlink(
        normpath(joinpath(source_root, "src", "$(String(name)).jl")),
        "active dependency $name entrypoint",
    )
    return realpath(expected)
end

function validate_loaded_package_entrypoint(
        loaded_module,
        package_id::Base.PkgId,
        package_info = Pkg.dependencies(),
    )
    haskey(Base.loaded_modules, package_id) ||
        fail("$(package_id.name) did not register under its pinned UUID")
    Base.loaded_modules[package_id] === loaded_module ||
        fail("loaded $(package_id.name) module identity changed")
    Base.PkgId(loaded_module) == package_id ||
        fail("loaded $(package_id.name) package identity changed")
    entrypoint = Base.pathof(loaded_module)
    entrypoint isa AbstractString ||
        fail("loaded $(package_id.name) module has no source entrypoint")
    validate_file_path_no_symlink(
        normpath(String(entrypoint)),
        "loaded $(package_id.name) entrypoint",
    )
    expected = expected_package_entrypoint(
        package_info,
        package_id.uuid,
        package_id.name,
    )
    realpath(entrypoint) == expected ||
        fail(
            "loaded $(package_id.name) module differs from its " *
                "pre-resolved source-tree entrypoint",
        )
    return expected
end

function validate_beforeit_resolution(package_info = Pkg.dependencies())
    expected = expected_package_entrypoint(
        package_info,
        BEFOREIT_UUID,
        "BeforeIT",
    )
    resolved = Base.locate_package(BEFOREIT_PKGID)
    resolved isa AbstractString ||
        fail("Base.locate_package could not resolve BeforeIT")
    realpath(resolved) == expected ||
        fail("BeforeIT PkgId does not resolve repository src/BeforeIT.jl")
    return expected
end

function load_frozen_v2_after_attestation(
        document,
        source_attestation::DependencySourceAttestation,
        entrypoint_attestation::PackageEntrypointAttestation,
    )
    validate_third_party_bootstrap_unloaded()
    validate_load_path_environment(document)
    source_attestation.all_source_trees_match ||
        fail("frozen v2 load requires matching dependency source trees")
    entrypoint_attestation.all_entrypoints_match ||
        fail("frozen v2 load requires matching package entrypoints")
    current_sources = validate_dependency_source_trees(document)
    current_sources.actual_digest == source_attestation.actual_digest ||
        fail("dependency source trees changed before loading frozen v2")
    current_entrypoints = validate_package_entrypoint_resolutions(
        document,
        current_sources,
    )
    current_entrypoints.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed before loading frozen v2")
    bytes = read(V2_MODULE_PATH)
    sha256_hex(bytes) == V2_MODULE_SHA256 ||
        fail("frozen v2 source changed before its delayed include")
    loaded = try
        Base.include_string(
            @__MODULE__,
            String(bytes),
            V2_MODULE_PATH,
        )
    catch error
        fail("delayed frozen v2 include failed: $(sprint(showerror, error))")
    end
    isdefined(@__MODULE__, :USRevisedDataABMOriginFirewallV2) ||
        fail("delayed frozen v2 include did not define its module")
    v2 = getfield(@__MODULE__, :USRevisedDataABMOriginFirewallV2)
    v2 isa Module ||
        fail("delayed frozen v2 binding is not a module")
    loaded === v2 ||
        fail("delayed frozen v2 include returned a different binding")
    V2_MODULE_REF[] = v2
    haskey(Base.loaded_modules, JSON_PKGID) ||
        fail("frozen v2 did not load JSON under the pinned UUID")
    json = Base.loaded_modules[JSON_PKGID]
    validate_loaded_package_entrypoint(json, JSON_PKGID)
    validate_load_path_environment(document)
    jld2_loaded() &&
        fail("delayed frozen v2 include unexpectedly loaded JLD2")
    beforeit_loaded() &&
        fail("delayed frozen v2 include unexpectedly loaded BeforeIT")
    Base.invokelatest(getfield(v2, :validate_protocol))
    Base.invokelatest(getfield(v2, :validate_source_pins))
    return v2
end

function v2_call(v2::Module, name::Symbol, args...; kwargs...)
    isdefined(v2, name) ||
        fail("frozen v2 does not define $(String(name))")
    return Base.invokelatest(getfield(v2, name), args...; kwargs...)
end

function validate_jld2_module(jld2)
    package_info = Pkg.dependencies()
    validate_loaded_package_entrypoint(
        jld2,
        JLD2_PKGID,
        package_info,
    )
    info = package_info[JLD2_UUID]
    jldopen_method = try
        which(getfield(jld2, :jldopen), (String, String))
    catch error
        fail("could not resolve JLD2.jldopen: $(sprint(showerror, error))")
    end
    method_file = String(jldopen_method.file)
    isabspath(method_file) ||
        fail("JLD2.jldopen does not report an absolute source path")
    source_root = realpath(info.source)
    source_prefix =
        source_root * string(Base.Filesystem.path_separator)
    startswith(realpath(method_file), source_prefix) ||
        fail("JLD2.jldopen resolves outside its pinned source tree")
    return (
        module_identity = string(Base.PkgId(jld2)),
        source = source_root,
        method_file = relpath(realpath(method_file), source_root),
    )
end

function exact_constructor_integer(value, location; minimum = nothing)
    value isa Real && !(value isa Bool) ||
        fail("$location must be a real number, not Bool")
    if value isa AbstractFloat
        isfinite(value) || fail("$location must be finite")
        isinteger(value) || fail("$location must be integer-valued")
    end
    source_big = try
        BigInt(value)
    catch
        fail("$location must be exactly integer-valued")
    end
    value == source_big ||
        fail("$location must be exactly integer-valued")
    minimum === nothing || source_big >= BigInt(minimum) ||
        fail("$location must be at least $minimum")
    typemin(Int) <= source_big <= typemax(Int) ||
        fail("$location is outside the constructor Int range")
    projected = try
        Float64(value)
    catch
        fail("$location cannot be projected to Float64")
    end
    isfinite(projected) ||
        fail("$location has a nonfinite Float64 projection")
    projected_big = try
        BigInt(projected)
    catch
        fail("$location has an inexact Float64 projection")
    end
    projected_big == source_big ||
        fail("$location changes value in the Float64 projection")
    converted = Int(source_big)
    Int(projected) == converted ||
        fail("$location changes value in the constructor Int conversion")
    return (int = converted, big = source_big, projected = projected)
end

function exact_aggregate(values, location)
    total_big = sum((value.big for value in values); init = BigInt(0))
    typemin(Int) <= total_big <= typemax(Int) ||
        fail("$location is outside the constructor Int range")
    projected_total = Float64(total_big)
    isfinite(projected_total) ||
        fail("$location has a nonfinite Float64 projection")
    BigInt(projected_total) == total_big ||
        fail("$location changes value in the Float64 projection")
    projected_sum = sum(value.projected for value in values)
    projected_sum == projected_total ||
        fail("$location changes under the constructor Float64 sum")
    Int(projected_sum) == Int(total_big) ||
        fail("$location changes under the constructor Int conversion")
    return (int = Int(total_big), big = total_big, projected = projected_total)
end

function preflight_constructor_domain(parameters, initial_conditions)
    parameters isa AbstractDict ||
        fail("constructor parameters must be a dictionary")
    initial_conditions isa AbstractDict ||
        fail("constructor initial_conditions must be a dictionary")
    required_parameters =
        ("G", "H_act", "H_inact", "I_s", "J", "L")
    all(haskey(parameters, key) for key in required_parameters) ||
        fail("constructor preflight parameters are incomplete")
    haskey(initial_conditions, "N_s") ||
        fail("constructor preflight requires initial_conditions.N_s")
    G = exact_constructor_integer(
        parameters["G"],
        "parameters.G";
        minimum = 1,
    )
    H_act = exact_constructor_integer(
        parameters["H_act"],
        "parameters.H_act";
        minimum = 1,
    )
    H_inact = exact_constructor_integer(
        parameters["H_inact"],
        "parameters.H_inact";
        minimum = 1,
    )
    J = exact_constructor_integer(
        parameters["J"],
        "parameters.J";
        minimum = 1,
    )
    L = exact_constructor_integer(
        parameters["L"],
        "parameters.L";
        minimum = 1,
    )
    I_s_raw = parameters["I_s"]
    N_s_raw = initial_conditions["N_s"]
    I_s_raw isa AbstractVector ||
        fail("parameters.I_s must be a vector")
    N_s_raw isa AbstractVector ||
        fail("initial_conditions.N_s must be a vector")
    Base.require_one_based_indexing(I_s_raw, N_s_raw)
    length(I_s_raw) == G.int ||
        fail("parameters.I_s length must equal G")
    length(N_s_raw) == G.int ||
        fail("initial_conditions.N_s length must equal G")
    I_s = [
        exact_constructor_integer(
                value,
                "parameters.I_s[$index]";
                minimum = 1,
            ) for (index, value) in enumerate(I_s_raw)
    ]
    N_s = [
        exact_constructor_integer(
                value,
                "initial_conditions.N_s[$index]";
                minimum = 0,
            ) for (index, value) in enumerate(N_s_raw)
    ]
    total_firms = exact_aggregate(I_s, "sum(parameters.I_s)")
    total_employment =
        exact_aggregate(N_s, "sum(initial_conditions.N_s)")
    for g in 1:G.int
        N_s[g].big >= I_s[g].big ||
            fail(
            "initial_conditions.N_s[$g] must be at least " *
                "parameters.I_s[$g] to make randpl terminate",
        )
    end
    active_worker_big =
        H_act.big - total_firms.big - BigInt(1)
    typemin(Int) <= active_worker_big <= typemax(Int) ||
        fail("H_act-sum(I_s)-1 is outside the constructor Int range")
    active_worker_projected = Float64(active_worker_big)
    BigInt(active_worker_projected) == active_worker_big ||
        fail("H_act-sum(I_s)-1 changes in the Float64 projection")
    active_worker_big >= total_employment.big ||
        fail(
        "H_act-sum(I_s)-1 must be at least sum(N_s) " *
            "to prevent worker-assignment bounds failure",
    )
    unemployed_big = active_worker_big - total_employment.big
    typemin(Int) <= unemployed_big <= typemax(Int) ||
        fail("constructor unemployed-worker count exceeds Int range")
    return ConstructorDomainCounts(
        G.int,
        H_act.int,
        H_inact.int,
        J.int,
        L.int,
        total_firms.int,
        Int(active_worker_big),
        total_employment.int,
        Int(unemployed_big),
        getfield.(I_s, :int),
        getfield.(N_s, :int),
    )
end

function quarter_ordinal(value)
    value isa AbstractString ||
        fail("artifact period must be a quarterly string")
    matched = match(r"^([1-9][0-9]{3})-?Q([1-4])$", String(value))
    matched === nothing &&
        fail("artifact period is not a valid quarterly label")
    return 4parse(Int, matched.captures[1]) +
        parse(Int, matched.captures[2])
end

function quarter_string(ordinal)
    quarter = mod(ordinal - 1, 4) + 1
    year = (ordinal - quarter) ÷ 4
    return "$(year)Q$(quarter)"
end

function decode_artifact(snapshot::PinnedSnapshot, jld2)
    path, io = mktemp()
    try
        write(io, snapshot.bytes)
        flush(io)
        close(io)
        sha256_hex(read(path)) == snapshot.sha256 ||
            fail("temporary artifact snapshot changed before JLD2 decode")
        artifact = try
            Base.invokelatest(getfield(jld2, :load), path)
        catch error
            fail("pinned artifact could not be decoded: $(sprint(showerror, error))")
        end
        sha256_hex(read(path)) == snapshot.sha256 ||
            fail("temporary artifact snapshot changed during JLD2 decode")
        return artifact
    finally
        isopen(io) && close(io)
        isfile(path) && rm(path)
    end
end

function reconstruct_period_axes(artifact, v2::Module)
    expect_exact_keys(
        artifact,
        ("parameters", "initial_conditions", "metadata"),
        "installed artifact",
    )
    parameters = artifact["parameters"]
    initial_conditions = artifact["initial_conditions"]
    metadata = artifact["metadata"]
    parameters isa AbstractDict ||
        fail("artifact parameters must be a dictionary")
    initial_conditions isa AbstractDict ||
        fail("artifact initial_conditions must be a dictionary")
    metadata isa AbstractDict ||
        fail("artifact metadata must be a dictionary")
    get(metadata, "period", nothing) == ARTIFACT_PERIOD ||
        fail("artifact frozen period changed")
    origin_ordinal = quarter_ordinal(metadata["period"])
    quarter_string(origin_ordinal) == ORIGIN_PERIOD ||
        fail("artifact period does not normalize to the v3 origin")
    T_prime = exact_constructor_integer(
        get(parameters, "T_prime", nothing),
        "artifact parameters.T_prime";
        minimum = 1,
    ).int
    periods = Dict{String, Vector{String}}()
    for key in getfield(v2, :DYNAMIC_HISTORY_KEYS)
        haskey(initial_conditions, key) ||
            fail("artifact is missing dynamic history $key")
        value = initial_conditions[key]
        value isa AbstractArray ||
            fail("artifact dynamic history $key must be an array")
        Base.require_one_based_indexing(value)
        length_axis = size(value, 1)
        length_axis >= T_prime ||
            fail("artifact dynamic history $key is shorter than T_prime")
        periods[key] = [
            quarter_string(origin_ordinal - T_prime + index) for
                index in 1:length_axis
        ]
        periods[key][T_prime] == ORIGIN_PERIOD ||
            fail("reconstructed period axis does not place origin at T_prime")
    end
    return periods
end

function qualify_artifact(artifact, document, v2::Module)
    periods = reconstruct_period_axes(artifact, v2)
    qualified = v2_call(
        v2,
        :qualify_base_origin_inputs,
        artifact["parameters"],
        artifact["initial_conditions"],
        periods;
        model_variant = MODEL_VARIANT,
        model_constructor_id = MODEL_CONSTRUCTOR_ID,
        class_h_used = false,
    )
    qualified.protocol_sha256 == document["v2_protocol_sha256"] ||
        fail("installed v2 protocol binding changed")
    qualified.qualified_input_sha256 ==
        document["v2_qualified_input_sha256"] ||
        fail("installed v2 qualified-input SHA-256 changed")
    expected_partitions = Dict(
        "parameters" => document["v2_parameter_sha256"],
        "static" => document["v2_static_sha256"],
        "dynamic" => document["v2_dynamic_sha256"],
    )
    qualified.partition_sha256 == expected_partitions ||
        fail("installed v2 qualified-input partition hashes changed")
    seed_plan = v2_call(
        v2,
        :derive_base_path_seed_plan,
        MASTER_SEED,
        qualified;
        experiment_id = EXPERIMENT_ID,
        model_id = MODEL_ID,
    )
    v2_call(v2, :path_seed_plan_sha256, seed_plan, qualified) ==
        document["v2_seed_plan_sha256"] ||
        fail("v2 construction seed plan changed")
    getfield.(seed_plan, :construction_seed) ==
        document["construction_seeds"] ||
        fail("v2 construction seeds changed")
    return qualified, seed_plan
end

function method_record(method, id, expected_relative_path, beforeit)
    method.module === beforeit ||
        fail("method $id is not defined by BeforeIT")
    file = String(method.file)
    isabspath(file) ||
        fail("method $id does not report an absolute source path")
    expected = joinpath(REPOSITORY_ROOT, expected_relative_path)
    realpath(file) == realpath(expected) ||
        fail("method $id resolves outside its pinned repository source")
    return MethodOriginRecord(
        String(id),
        String(expected_relative_path),
        string(nameof(method.module)),
    )
end

function collect_method_origin_records(beforeit)
    DictType = Dict{String, Any}
    specifications = [
        (
            "Model_dict",
            getfield(beforeit, :Model),
            (DictType, DictType),
        ),
        (
            "Model_tuple",
            getfield(beforeit, :Model),
            (Tuple,),
        ),
        (
            "Properties",
            getfield(beforeit, :Properties),
            (DictType, DictType),
        ),
        (
            "Firms",
            getfield(beforeit, :Firms),
            (DictType, DictType),
        ),
        (
            "Workers",
            getfield(beforeit, :Workers),
            (DictType, DictType),
        ),
        (
            "Bank",
            getfield(beforeit, :Bank),
            (DictType, DictType),
        ),
        (
            "CentralBank",
            getfield(beforeit, :CentralBank),
            (DictType, DictType),
        ),
        (
            "Government",
            getfield(beforeit, :Government),
            (DictType, DictType),
        ),
        (
            "RestOfTheWorld",
            getfield(beforeit, :RestOfTheWorld),
            (DictType, DictType),
        ),
        (
            "Aggregates",
            getfield(beforeit, :Aggregates),
            (DictType, DictType),
        ),
        ("Data", getfield(beforeit, :Data), ()),
        (
            "randpl",
            getfield(beforeit, :randpl),
            (Int, Float64, Int),
        ),
        (
            "allocate_sector_initial_inventories",
            getfield(beforeit, :allocate_sector_initial_inventories),
            (Vector{Float64}, Vector{Int}, Vector{Float64}, Int),
        ),
        (
            "update_variables_with_totals!",
            getfield(beforeit, :update_variables_with_totals!),
            (getfield(beforeit, :Model),),
        ),
        (
            "collect_data!",
            getfield(beforeit, :collect_data!),
            (getfield(beforeit, :Model),),
        ),
        (
            "allocate_new_data!",
            getfield(beforeit, :allocate_new_data!),
            (getfield(beforeit, :Model),),
        ),
        (
            "update_data_init!",
            getfield(beforeit, :update_data_init!),
            (getfield(beforeit, :Model),),
        ),
        (
            "model_implied_opening_macro",
            getfield(beforeit, :model_implied_opening_macro),
            (getfield(beforeit, :Model),),
        ),
    ]
    records = MethodOriginRecord[]
    for (id, callable, signature) in specifications
        method = try
            which(callable, signature)
        catch error
            fail("could not resolve pinned method $id: $(sprint(showerror, error))")
        end
        push!(
            records,
            method_record(
                method,
                id,
                METHOD_ORIGIN_PATHS[id],
                beforeit,
            ),
        )
    end
    return validate_method_origin_records(records)
end

function validate_method_origin_records(records)
    records isa AbstractVector ||
        fail("method-origin records must be a vector")
    length(records) == length(METHOD_ORIGIN_PATHS) ||
        fail("method-origin record count changed")
    by_id = Dict{String, MethodOriginRecord}()
    for record in records
        record isa MethodOriginRecord ||
            fail("unsupported method-origin record type")
        haskey(by_id, record.id) &&
            fail("duplicate method-origin record $(record.id)")
        haskey(METHOD_ORIGIN_PATHS, record.id) ||
            fail("unknown method-origin record $(record.id)")
        record.relative_path == METHOD_ORIGIN_PATHS[record.id] ||
            fail("method-origin path changed for $(record.id)")
        record.defining_module == "BeforeIT" ||
            fail("method-origin module changed for $(record.id)")
        by_id[record.id] = record
    end
    Set(keys(by_id)) == Set(keys(METHOD_ORIGIN_PATHS)) ||
        fail("method-origin records are incomplete")
    return records
end

function method_origin_digest(records)
    validate_method_origin_records(records)
    rows = sort!(
        [
            "$(record.id):$(record.relative_path):$(record.defining_module)"
                for record in records
        ],
    )
    return sha256_hex(codeunits(join(rows, "\n")))
end

@noinline function construct_with_seed(
        constructor,
        seed::Int,
        parameters::Dict{String, Any},
        initial_conditions::Dict{String, Any},
    )
    validate_rng_runtime()
    Random.seed!(seed)
    return Base.invokelatest(
        constructor,
        parameters,
        initial_conditions,
    )
end

function validate_numeric_finiteness(value)
    seen = IdDict{Any, Nothing}()
    return validate_numeric_finiteness(value, "model", seen)
end

function validate_numeric_finiteness(value, location, seen)
    if value isa Bool
        return 1
    elseif value isa Real
        isfinite(value) || fail("$location contains a nonfinite numeric value")
        return 1
    elseif value isa AbstractString || value isa Symbol || value === nothing
        return 0
    end
    mutable = value isa AbstractArray ||
        value isa AbstractDict ||
        value isa Base.RefValue ||
        ismutabletype(typeof(value))
    if mutable
        haskey(seen, value) && return 0
        seen[value] = nothing
    end
    count = 0
    if value isa AbstractArray
        Base.require_one_based_indexing(value)
        for (index, item) in enumerate(value)
            count += validate_numeric_finiteness(
                item,
                "$location[$index]",
                seen,
            )
        end
    elseif value isa AbstractDict
        for (key, item) in pairs(value)
            count += validate_numeric_finiteness(
                key,
                "$location dictionary key",
                seen,
            )
            count += validate_numeric_finiteness(
                item,
                "$location dictionary value",
                seen,
            )
        end
    elseif value isa Base.RefValue
        count += validate_numeric_finiteness(
            value[],
            "$location[]",
            seen,
        )
    elseif isstructtype(typeof(value))
        for field in fieldnames(typeof(value))
            count += validate_numeric_finiteness(
                getfield(value, field),
                "$location.$field",
                seen,
            )
        end
    end
    return count
end

function state_type_name(value)
    return string(typeof(value))
end

function encode_state!(io, value, seen)
    if value === nothing
        write(io, "nothing;")
    elseif value isa Bool
        write(io, value ? "bool:1;" : "bool:0;")
    elseif value isa Integer
        write(
            io,
            "integer:",
            string(typeof(value)),
            ":",
            string(value),
            ";",
        )
    elseif value isa AbstractFloat
        isfinite(value) || fail("model state contains a nonfinite float")
        write(
            io,
            "float:",
            string(typeof(value)),
            ":",
            bitstring(value),
            ";",
        )
    elseif value isa AbstractString
        text = String(value)
        write(io, "string:", string(ncodeunits(text)), ":", text, ";")
    elseif value isa Symbol
        text = String(value)
        write(io, "symbol:", string(ncodeunits(text)), ":", text, ";")
    else
        mutable = value isa AbstractArray ||
            value isa AbstractDict ||
            value isa Base.RefValue ||
            ismutabletype(typeof(value))
        if mutable && haskey(seen, value)
            write(io, "reference:", string(seen[value]), ";")
            return io
        elseif mutable
            seen[value] = length(seen) + 1
        end
        if value isa AbstractArray
            Base.require_one_based_indexing(value)
            write(
                io,
                "array:",
                state_type_name(value),
                ":",
                join(size(value), ","),
                ":",
            )
            for item in value
                encode_state!(io, item, seen)
            end
            write(io, ";")
        elseif value isa AbstractDict
            encoded = Tuple{String, Any}[]
            for key in keys(value)
                key_io = IOBuffer()
                encode_state!(key_io, key, IdDict{Any, Int}())
                push!(encoded, (bytes2hex(take!(key_io)), key))
            end
            sort!(encoded; by = first)
            write(
                io,
                "dict:",
                state_type_name(value),
                ":",
                string(length(encoded)),
                ":",
            )
            for (_, key) in encoded
                encode_state!(io, key, seen)
                encode_state!(io, value[key], seen)
            end
            write(io, ";")
        elseif value isa Base.RefValue
            write(io, "ref:", state_type_name(value), ":")
            encode_state!(io, value[], seen)
            write(io, ";")
        elseif isstructtype(typeof(value))
            write(io, "struct:", state_type_name(value), ":")
            for field in fieldnames(typeof(value))
                name = String(field)
                write(io, string(ncodeunits(name)), ":", name, ":")
                encode_state!(io, getfield(value, field), seen)
            end
            write(io, ";")
        else
            fail("unsupported model-state value $(typeof(value))")
        end
    end
    return io
end

function full_state_sha256(model)
    validate_numeric_finiteness(model)
    io = IOBuffer()
    encode_state!(io, model, IdDict{Any, Int}())
    return sha256_hex(take!(io))
end

function validate_model_structure(model, beforeit, counts)
    model isa getfield(beforeit, :Model) ||
        fail("constructor did not return base BeforeIT.Model")
    property = model.prop
    property.G == counts.sector_count ||
        fail("constructed sector count changed")
    property.H_act == counts.active_population ||
        fail("constructed active-population count changed")
    property.H_inact == counts.inactive_workers ||
        fail("constructed inactive-worker count changed")
    property.J == counts.government_entities ||
        fail("constructed government-entity count changed")
    property.L == counts.foreign_consumers ||
        fail("constructed foreign-consumer count changed")
    property.I == counts.firm_count ||
        fail("constructed firm count changed")
    length(model.firms.G_i) == counts.firm_count ||
        fail("constructed firms vector length changed")
    length(model.w_act.Y_h) == counts.active_worker_count ||
        fail("constructed active-worker vector length changed")
    length(model.w_inact.Y_h) == counts.inactive_workers ||
        fail("constructed inactive-worker vector length changed")
    length(model.gov.C_d_j) == counts.government_entities ||
        fail("constructed government vector length changed")
    length(model.rotw.C_d_l) == counts.foreign_consumers ||
        fail("constructed foreign-consumer vector length changed")
    for field in (:Y_m, :Q_m, :Q_d_m, :P_m)
        length(getfield(model.rotw, field)) == counts.sector_count ||
            fail("constructed rest-of-world sector vector changed")
    end
    length(model.agg.P_bar_g) == counts.sector_count ||
        fail("constructed aggregate sector vector changed")
    length(model.agg.Y) == property.T_prime ||
        fail("constructed GDP history length changed")
    length(model.agg.pi_) == property.T_prime ||
        fail("constructed inflation history length changed")
    I_s = Int.(property.I_s)
    length(I_s) == counts.sector_count ||
        fail("constructed I_s length changed")
    length(model.firms.G_i) == counts.firm_count ||
        fail("constructed firm-sector vector length changed")
    sum(model.firms.N_i) == counts.employed_worker_count ||
        fail("constructed firm employment total changed")
    all(>(0), model.firms.N_i) ||
        fail("constructed firm employment must be positive")
    all(iszero, model.firms.V_i) ||
        fail("constructor did not consume all opening vacancies")
    for g in 1:counts.sector_count
        sector_firms = findall(==(g), model.firms.G_i)
        length(sector_firms) == I_s[g] ||
            fail("constructed sector-$g firm count changed")
        sum(model.firms.N_i[sector_firms]) ==
            counts.sector_employment_counts[g] ||
            fail("constructed sector-$g employment is invalid")
    end
    occupations = model.w_act.O_h
    count(!=(0), occupations) == counts.employed_worker_count ||
        fail("constructed employed-worker count changed")
    count(==(0), occupations) == counts.unemployed_worker_count ||
        fail("constructed unemployed-worker count changed")
    all(occupation -> 0 <= occupation <= counts.firm_count, occupations) ||
        fail("constructed worker occupation is outside the firm range")
    for firm in 1:counts.firm_count
        count(==(firm), occupations) == model.firms.N_i[firm] ||
            fail("constructed worker-to-firm assignment changed")
    end
    all(==(-1), model.w_inact.O_h) ||
        fail("constructed inactive-worker occupations changed")
    length(model.data.collection_time) == 1 ||
        fail("constructor must produce exactly one opening data row")
    model.data.collection_time[1] == 1 ||
        fail("constructor opening data row has an unexpected index")
    return validate_numeric_finiteness(model)
end

function validate_stochastic_fingerprints(
        fingerprints::AbstractVector{<:AbstractString},
        replay::AbstractString,
        expected_set_sha256::AbstractString,
    )
    length(fingerprints) == PATH_COUNT ||
        fail("constructor path fingerprint count changed")
    all(
        fingerprint -> occursin(r"^[0-9a-f]{64}$", fingerprint),
        fingerprints,
    ) || fail("constructor path fingerprint is not a SHA-256")
    length(unique(fingerprints)) == PATH_COUNT ||
        fail("construction paths did not produce distinct stochastic states")
    replay == first(fingerprints) ||
        fail("same-seed constructor replay was not deterministic")
    rows = [
        "$(path_id):$(fingerprints[path_id])" for
            path_id in eachindex(fingerprints)
    ]
    digest = sha256_hex(codeunits(join(rows, "\n")))
    digest == expected_set_sha256 ||
        fail(
        "constructor path fingerprint set changed: actual $digest",
    )
    return digest
end

function refuse_prohibited_action(action::Symbol)
    action in PROHIBITED_ACTIONS ||
        fail("unknown v3 constructor-gate action $action")
    return fail(
        "v3 constructor gate forbids $(String(action)); " *
            "only base-model construction is allowed",
    )
end

function result_payload(result::ConstructorGateV3Result)
    return Dict{String, Any}(
        String(field) => getfield(result, field) for
            field in fieldnames(ConstructorGateV3Result) if
            field != :result_sha256
    )
end

function with_result_hash(result::ConstructorGateV3Result)
    digest = semantic_sha256(result_payload(result))
    return ConstructorGateV3Result(
        (
            getfield(result, field) for
                field in fieldnames(ConstructorGateV3Result) if
                field != :result_sha256
        )...,
        digest,
    )
end

function run_installed_constructor_gate()
    validate_third_party_bootstrap_unloaded()
    protocol = validate_protocol()
    load_path_attestation =
        validate_load_path_environment(protocol.document)
    execution_digest =
        validate_execution_environment(protocol.document)
    rng_type = validate_rng_runtime(
        protocol.document["default_rng_type"],
    )
    depot_attestation = validate_artifact_overrides_absent()
    initial_snapshots = validate_pinned_files(protocol.document)
    validate_third_party_bootstrap_unloaded()
    dependency_attestation =
        validate_dependency_source_trees(protocol.document)
    validate_third_party_bootstrap_unloaded()
    entrypoint_attestation =
        validate_package_entrypoint_resolutions(
            protocol.document,
            dependency_attestation,
        )
    validate_third_party_bootstrap_unloaded()
    v2 = load_frozen_v2_after_attestation(
        protocol.document,
        dependency_attestation,
        entrypoint_attestation,
    )

    # JSON is first loaded by the frozen v2 module only after the complete
    # manifest source-tree and entrypoint checks above. JLD2 and BeforeIT
    # remain absent until their separately checked load boundaries below.
    v2_call(v2, :validate_protocol)
    v2_call(v2, :validate_source_pins)
    validate_load_path_environment(protocol.document)
    validate_jld2_unloaded()
    validate_beforeit_unloaded()
    pre_jld2_sources =
        validate_dependency_source_trees(protocol.document)
    pre_jld2_sources.actual_digest ==
        dependency_attestation.actual_digest ||
        fail("dependency source trees changed before loading JLD2")
    pre_jld2_entrypoints =
        validate_package_entrypoint_resolutions(
            protocol.document,
            pre_jld2_sources,
        )
    pre_jld2_entrypoints.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed before loading JLD2")
    validate_jld2_unloaded()
    validate_beforeit_unloaded()
    jld2 = require_preresolved_package(
        JLD2_PKGID,
        pre_jld2_sources,
        pre_jld2_entrypoints,
    )
    jld2_identity = validate_jld2_module(jld2)
    validate_load_path_environment(protocol.document)
    validate_beforeit_unloaded()
    artifact = decode_artifact(
        initial_snapshots[
            "data/us/baselines/US_2026Q1_nowcast.jld2",
        ],
        jld2,
    )
    qualified, seed_plan =
        qualify_artifact(artifact, protocol.document, v2)
    reassembled = v2_call(v2, :reassemble_model_inputs, qualified)
    counts = preflight_constructor_domain(
        reassembled.parameters,
        reassembled.initial_conditions,
    )

    # This is the final source/environment check immediately before the
    # package is loaded. Nothing in between may load or execute BeforeIT.
    validate_beforeit_unloaded()
    validate_execution_environment(protocol.document)
    validate_pinned_files(protocol.document)
    v2_call(v2, :validate_protocol)
    v2_call(v2, :validate_source_pins)
    pre_beforeit_sources =
        validate_dependency_source_trees(protocol.document)
    pre_beforeit_sources.actual_digest ==
        dependency_attestation.actual_digest ||
        fail("dependency source trees changed before loading BeforeIT")
    pre_beforeit_entrypoints =
        validate_package_entrypoint_resolutions(
            protocol.document,
            pre_beforeit_sources,
        )
    pre_beforeit_entrypoints.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed before loading BeforeIT")
    current_depot_attestation =
        validate_artifact_overrides_absent()
    current_depot_attestation.path_count ==
        depot_attestation.path_count ||
        fail("effective DEPOT_PATH count changed before loading BeforeIT")
    current_depot_attestation.paths_sha256 ==
        depot_attestation.paths_sha256 ||
        fail("effective DEPOT_PATH changed before loading BeforeIT")
    validate_jld2_module(jld2) == jld2_identity ||
        fail("JLD2 module identity changed before loading BeforeIT")
    validate_beforeit_resolution()
    validate_beforeit_unloaded()
    beforeit = require_preresolved_package(
        BEFOREIT_PKGID,
        pre_beforeit_sources,
        pre_beforeit_entrypoints,
    )

    validate_loaded_package_entrypoint(beforeit, BEFOREIT_PKGID)
    validate_load_path_environment(protocol.document)
    getfield(beforeit, :typeFloat) === Float64 ||
        fail("BeforeIT.typeFloat must be exactly Float64")
    getfield(beforeit, :typeInt) === Int ||
        fail("BeforeIT.typeInt must be exactly Int")
    method_records = collect_method_origin_records(beforeit)
    methods_digest = method_origin_digest(method_records)

    constructor = getfield(beforeit, :Model)
    path_fingerprints = String[]
    numeric_count = nothing
    input_hashes_unchanged = true
    for record in seed_plan
        v2_call(v2, :validate_qualified_inputs, qualified)
        inputs = v2_call(v2, :reassemble_model_inputs, qualified)
        parameter_hash_before =
            v2_call(v2, :semantic_sha256, inputs.parameters)
        initial_hash_before =
            v2_call(v2, :semantic_sha256, inputs.initial_conditions)
        model = try
            construct_with_seed(
                constructor,
                record.construction_seed,
                inputs.parameters,
                inputs.initial_conditions,
            )
        catch error
            fail(
                "BeforeIT.Model construction failed for path " *
                    "$(record.path_id): $(sprint(showerror, error))",
            )
        end
        parameter_hash_after =
            v2_call(v2, :semantic_sha256, inputs.parameters)
        initial_hash_after =
            v2_call(v2, :semantic_sha256, inputs.initial_conditions)
        unchanged = parameter_hash_before == parameter_hash_after &&
            initial_hash_before == initial_hash_after
        input_hashes_unchanged &= unchanged
        unchanged ||
            fail("BeforeIT.Model mutated constructor inputs")
        checked = validate_model_structure(model, beforeit, counts)
        numeric_count === nothing && (numeric_count = checked)
        checked == numeric_count ||
            fail("numeric model-state cardinality changed across paths")
        push!(path_fingerprints, full_state_sha256(model))
        v2_call(v2, :validate_qualified_inputs, qualified)
    end

    replay_inputs = v2_call(v2, :reassemble_model_inputs, qualified)
    replay_parameter_hash =
        v2_call(v2, :semantic_sha256, replay_inputs.parameters)
    replay_initial_hash =
        v2_call(v2, :semantic_sha256, replay_inputs.initial_conditions)
    replay_model = try
        construct_with_seed(
            constructor,
            first(seed_plan).construction_seed,
            replay_inputs.parameters,
            replay_inputs.initial_conditions,
        )
    catch error
        fail(
            "BeforeIT.Model deterministic replay failed: " *
                sprint(showerror, error),
        )
    end
    replay_parameter_hash ==
        v2_call(v2, :semantic_sha256, replay_inputs.parameters) ||
        fail("deterministic replay mutated constructor parameters")
    replay_initial_hash ==
        v2_call(v2, :semantic_sha256, replay_inputs.initial_conditions) ||
        fail("deterministic replay mutated constructor initial conditions")
    validate_model_structure(replay_model, beforeit, counts) ==
        numeric_count ||
        fail("deterministic replay numeric-state cardinality changed")
    replay_fingerprint = full_state_sha256(replay_model)
    fingerprint_set_digest = validate_stochastic_fingerprints(
        path_fingerprints,
        replay_fingerprint,
        protocol.document[
            "expected_path_fingerprint_set_sha256",
        ],
    )

    validate_execution_environment(protocol.document)
    v2_call(v2, :validate_protocol)
    v2_call(v2, :validate_source_pins)
    final_snapshots = validate_pinned_files(protocol.document)
    for path in keys(initial_snapshots)
        validate_snapshot_unchanged(
            initial_snapshots[path],
            final_snapshots[path],
        )
    end
    final_dependency_attestation =
        validate_dependency_source_trees(protocol.document)
    final_dependency_attestation.actual_digest ==
        dependency_attestation.actual_digest ||
        fail("dependency source trees changed during construction")
    final_entrypoint_attestation =
        validate_package_entrypoint_resolutions(
            protocol.document,
            final_dependency_attestation,
        )
    final_entrypoint_attestation.actual_digest ==
        entrypoint_attestation.actual_digest ||
        fail("package entrypoints changed during construction")
    final_depot_attestation =
        validate_artifact_overrides_absent()
    final_depot_attestation.path_count ==
        depot_attestation.path_count ||
        fail("effective DEPOT_PATH count changed during construction")
    final_depot_attestation.paths_sha256 ==
        depot_attestation.paths_sha256 ||
        fail("effective DEPOT_PATH changed during construction")
    validate_jld2_module(jld2) == jld2_identity ||
        fail("JLD2 module identity changed during construction")
    method_origin_digest(collect_method_origin_records(beforeit)) ==
        methods_digest ||
        fail("BeforeIT method origins changed during construction")
    validate_loaded_package_entrypoint(beforeit, BEFOREIT_PKGID)
    v2_call(v2, :validate_qualified_inputs, qualified)
    qualified.qualified_input_sha256 ==
        V2_QUALIFIED_INPUT_SHA256 ||
        fail("qualified input hash changed during construction")

    result = ConstructorGateV3Result(
        SCHEMA_VERSION,
        CONTRACT_ID,
        protocol.sha256,
        ARTIFACT_SHA256,
        qualified.protocol_sha256,
        qualified.qualified_input_sha256,
        copy(qualified.partition_sha256),
        v2_call(v2, :path_seed_plan_sha256, seed_plan, qualified),
        dependency_attestation.source_tree_count,
        dependency_attestation.actual_digest,
        entrypoint_attestation.package_entrypoint_count,
        entrypoint_attestation.actual_digest,
        load_path_attestation.symbolic_sha256,
        load_path_attestation.expanded_sha256,
        depot_attestation.path_count,
        depot_attestation.paths_sha256,
        depot_attestation.artifact_overrides_absent,
        methods_digest,
        execution_digest,
        rng_type,
        PATH_COUNT,
        REPLAY_COUNT,
        PATH_COUNT + REPLAY_COUNT,
        something(numeric_count),
        counts,
        path_fingerprints,
        fingerprint_set_digest,
        replay_fingerprint,
        replay_fingerprint == first(path_fingerprints),
        length(unique(path_fingerprints)) == PATH_COUNT,
        input_hashes_unchanged,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        dependency_attestation.binary_artifacts_attested,
        dependency_attestation.depot_contents_attested,
        dependency_attestation.global_preferences_attested,
        false,
        "",
    )
    return with_result_hash(result)
end

end # module
