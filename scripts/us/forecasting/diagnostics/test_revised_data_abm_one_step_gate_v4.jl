using LinearAlgebra
using SHA
using Test
using TOML
using UUIDs

const JSON_PROBE_PKGID = Base.PkgId(
    UUID("682c06a0-de6a-54ab-a142-c8b1cf79cde6"),
    "JSON",
)
const JLD2_PROBE_PKGID = Base.PkgId(
    UUID("033835bb-8acc-5ee8-8aae-3f567f8a3819"),
    "JLD2",
)
const BEFOREIT_PROBE_PKGID = Base.PkgId(
    UUID("ca9fcad7-41d0-4f76-b1e5-366c28bce52e"),
    "BeforeIT",
)
const PRECOMPILETOOLS_PROBE_PKGID = Base.PkgId(
    UUID("aea7be01-6a6a-4083-8856-8a6e6704d82a"),
    "PrecompileTools",
)

loaded_module_name(name) = any(
    loaded -> String(nameof(loaded)) == name,
    values(Base.loaded_modules),
)

const THIRD_PARTY_PRE_INCLUDE = (
    json = haskey(Base.loaded_modules, JSON_PROBE_PKGID) ||
        loaded_module_name("JSON") ||
        isdefined(Main, :JSON),
    jld2 = haskey(Base.loaded_modules, JLD2_PROBE_PKGID) ||
        loaded_module_name("JLD2") ||
        isdefined(Main, :JLD2),
    beforeit = haskey(Base.loaded_modules, BEFOREIT_PROBE_PKGID) ||
        loaded_module_name("BeforeIT") ||
        isdefined(Main, :BeforeIT),
    v2 = isdefined(Main, :USRevisedDataABMOriginFirewallV2),
    precompiletools =
        haskey(Base.loaded_modules, PRECOMPILETOOLS_PROBE_PKGID) ||
        loaded_module_name("PrecompileTools") ||
        isdefined(Main, :PrecompileTools),
)

include("USRevisedDataABMOneStepGateV4.jl")
using .USRevisedDataABMOneStepGateV4

const Gate = USRevisedDataABMOneStepGateV4
const V3 = Gate.V3
const PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_one_step_gate_v4.toml",
)
const STRICT_LOAD_PATH =
    get(ENV, "JULIA_LOAD_PATH", nothing) ==
    Gate.JULIA_LOAD_PATH_ENV &&
    Base.LOAD_PATH == Gate.SYMBOLIC_LOAD_PATH &&
    Base.load_path() == [V3.SCRIPTS_PROJECT_PATH, Sys.STDLIB]
const CANONICAL_RUNTIME =
    V3.ENV.current_execution_envelope() ==
    V3.ENV.CANONICAL_EXECUTION_ENVELOPE &&
    STRICT_LOAD_PATH &&
    Base.active_project() isa AbstractString &&
    realpath(Base.active_project()) ==
    realpath(V3.SCRIPTS_PROJECT_PATH)

mutable struct FakeOneStepModel
    value::Float64
    collections::Int
end

function fake_step!(
        model::FakeOneStepModel;
        parallel,
        shock!,
        transaction_logger,
        transaction_markets,
        opening_state_logger,
    )
    parallel === false || error("fake step must be serial")
    transaction_logger === nothing || error("unexpected logger")
    transaction_markets == (:business_goods, :final_demand) ||
        error("unexpected market tuple")
    opening_state_logger === nothing || error("unexpected logger")
    shock! isa Nothing || error("fake shock must be preconstructed")
    model.value = rand()
    return model
end

function fake_collect!(model::FakeOneStepModel)
    model.collections += 1
    return model
end

fake_state_hash(model::FakeOneStepModel) =
    bytes2hex(SHA.sha256(codeunits(bitstring(model.value))))

function fake_path(path_id; perturb = 0.0)
    number = Float64(path_id) + perturb
    digest(label) = bytes2hex(
        SHA.sha256(codeunits("$label-$path_id-$perturb")),
    )
    return OneStepPathResult(
        path_id,
        Gate.CONSTRUCTION_SEEDS[path_id],
        Gate.SIMULATION_SEEDS[path_id],
        Gate.ORIGIN_PERIOD,
        Gate.TARGET_PERIOD,
        [1, 2],
        100.0,
        100.0 + number,
        100.0,
        101.0 + number,
        1.0 + number,
        2.0 + number,
        digest("opening"),
        digest("post-step"),
        digest("post-collection"),
        digest("parameters"),
        digest("initial"),
        true,
        1000 + path_id,
    )
end

@testset "v4 fresh bootstrap and closed protocol" begin
    @test THIRD_PARTY_PRE_INCLUDE == (
        json = false,
        jld2 = false,
        beforeit = false,
        v2 = false,
        precompiletools = false,
    )
    @test V3.validate_third_party_bootstrap_unloaded()
    @test !V3.json_loaded()
    @test !V3.jld2_loaded()
    @test !V3.beforeit_loaded()
    @test !V3.v2_loaded()
    @test validate_precompiletools_unloaded()
    package_envelope =
        validate_uncompiled_package_load_envelope()
    @test package_envelope.compiled_modules_disabled
    @test package_envelope.pkgimages_disabled
    @test !package_envelope.generating_output
    protocol = validate_protocol()
    @test protocol.sha256 == protocol_sha256()
    @test protocol.sha256 ==
        bytes2hex(SHA.sha256(read(PROTOCOL_PATH)))
    document = protocol.document
    @test document["schema_version"] ==
        "beforeit-us-revised-data-abm-one-step-gate.v4"
    @test document["information_track"] ==
        "revised_mixed_vintage"
    @test document["diagnostic_class"] ==
        "quarantined_initial_transition_software_qualification"
    @test document["origin_period"] == "2026Q1"
    @test document["target_period"] == "2026Q2"
    @test document["horizon"] == 1
    @test document["path_count"] == 32
    @test document["seed_namespace_experiment_id"] ==
        "us-abm-constructor-gate-v3"
    @test document["primary_path_order"] == collect(1:32)
    @test document["reverse_path_order"] == collect(32:-1:1)
    @test document["replay_path_ids"] == [1]
    @test document["construction_seeds"] ==
        Gate.CONSTRUCTION_SEEDS
    @test document["simulation_seeds"] ==
        Gate.SIMULATION_SEEDS
    @test length(
        unique(
            [
                document["construction_seeds"];
                document["simulation_seeds"];
            ]
        ),
    ) == 64
    @test document["v3_module_sha256"] ==
        Gate.V3_MODULE_SHA256
    @test document["v3_protocol_sha256"] ==
        Gate.V3_PROTOCOL_SHA256
    @test document["withdrawn_v3_reference_result_sha256"] ==
        Gate.WITHDRAWN_V3_REFERENCE_RESULT_SHA256
    @test document["v3_opening_fingerprint_set_sha256"] ==
        Gate.V3_OPENING_FINGERPRINT_SET_SHA256
    @test document["synthetic_operator_module_sha256"] ==
        Gate.OPERATOR_MODULE_SHA256
    @test document["synthetic_operator_protocol_sha256"] ==
        Gate.OPERATOR_PROTOCOL_SHA256
    @test document["julia_load_path_env"] == "@:@stdlib"
    @test document["symbolic_load_path"] == ["@", "@stdlib"]
    @test document["compiled_modules_mode"] == "no"
    @test document["pkgimages_mode"] == "no"
    @test document["julia_use_compiled_modules_code"] == 0
    @test document["julia_use_pkgimages_code"] == 0
    @test document["julia_generating_output_code"] == 0
    @test document["precompiletools_uuid"] ==
        string(Gate.PRECOMPILETOOLS_UUID)
    @test Gate.EXPECTED_V4_EXECUTION_ENVELOPE_SHA256 ==
        "ee71160c99b187883eb67769d17fa87829b6a58bda6e23102e97c122fe09005d"
    @test document["execution_count_scope"] ==
        Gate.EXECUTION_COUNT_SCOPE
    counts = document["execution_counts"]
    @test counts["primary_constructions"] == 32
    @test counts["primary_steps"] == 32
    @test counts["primary_constructor_opening_collections"] == 32
    @test counts["primary_post_step_collections"] == 32
    @test counts["primary_total_collection_events"] == 64
    @test counts["reverse_constructions"] == 32
    @test counts["reverse_steps"] == 32
    @test counts["reverse_constructor_opening_collections"] == 32
    @test counts["reverse_post_step_collections"] == 32
    @test counts["reverse_total_collection_events"] == 64
    @test counts["replay_constructions"] == 1
    @test counts["replay_steps"] == 1
    @test counts["replay_constructor_opening_collections"] == 1
    @test counts["replay_post_step_collections"] == 1
    @test counts["replay_total_collection_events"] == 2
    @test counts["total_constructions"] == 65
    @test counts["total_steps"] == 65
    @test counts["total_constructor_opening_collections"] == 65
    @test counts["total_post_step_collections"] == 65
    @test counts["total_collection_events"] == 130

    declarations = document["declarations"]
    for key in (
            "diagnostic_only",
            "runner_implemented",
            "revised_mixed_vintage",
            "model_constructed",
            "model_stepped_once_per_construction",
            "software_one_step_verified",
            "initial_transition_characterized",
            "raw_opening_and_post_step_levels_preserved",
            "opening_row_is_model_implied_unanchored",
            "path_order_invariance_executed",
            "same_seed_replay_executed",
            "v3_bootstrap_reexecuted",
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
        )
        @test declarations[key] === true
    end
    for key in (
            "opening_row_is_official_truth",
            "opening_macro_controls_used",
            "v3_acceptance_relied_upon",
            "truth_bearing_metadata_deserialized",
            "truth_values_consumed_by_model_or_operator",
            "truth_values_used_for_scoring",
            "us_evaluation_truth_used",
            "package_import_side_data_passed_to_v4_constructor_or_gdp_operator",
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
        )
        @test declarations[key] === false
    end
    @test document["attestation_limits"][
        "package_import_side_data_attested",
    ] === true
    @test document["attestation_limits"][
        "package_precompile_workload_execution_guard_attested",
    ] === true
    @test "V3_CANONICAL_DISPOSITION_WITHDRAWN" in
        document["blockers"]
    @test document["origin_row_rule"] ==
        "row_1_is_model_implied_unanchored_2026Q1_labeled_opening_and_row_2_is_h1_2026Q2"
    @test document["path_evaluation_rule"] ==
        "transform_each_raw_path_before_any_ensemble_summary"
    @test length(document["pinned_files"]) == 18
    @test length(document["method_origins"]) == 7
    @test all(
        pin -> occursin(r"^[0-9a-f]{64}$", pin["sha256"]),
        document["pinned_files"],
    )

    mutation = deepcopy(document)
    mutation["path_count"] = 31
    @test_throws Gate.ABMOneStepGateV4Error begin
        validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["declarations"]["origin_admissible"] = true
    @test_throws Gate.ABMOneStepGateV4Error begin
        validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["declarations"]["truth_values_used_for_scoring"] = true
    @test_throws Gate.ABMOneStepGateV4Error begin
        validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["execution_counts"]["total_collection_events"] = 65
    @test_throws Gate.ABMOneStepGateV4Error begin
        validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["simulation_seeds"][1] += 1
    @test_throws Gate.ABMOneStepGateV4Error begin
        validate_protocol_semantics(mutation)
    end
end

@testset "v4 source pins and benign pre-resolution rejection" begin
    protocol = validate_protocol()
    snapshots = validate_source_pins(protocol.document)
    @test Set(keys(snapshots)) ==
        Set(pin["path"] for pin in protocol.document["pinned_files"])
    @test V3.protocol_sha256() == Gate.V3_PROTOCOL_SHA256
    @test Gate.SyntheticOperator.validate_protocol().sha256 ==
        Gate.OPERATOR_PROTOCOL_SHA256

    v3_protocol = V3.validate_protocol()
    source_attestation = V3.validate_dependency_source_trees(
        v3_protocol.document,
    )
    entrypoints = V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        source_attestation,
    )
    @test entrypoints.package_entrypoint_count == 83
    @test !V3.json_loaded()
    @test !V3.jld2_loaded()
    @test !V3.beforeit_loaded()
    @test !V3.v2_loaded()
    loader_invoked = Ref(false)
    @test_throws V3.ABMConstructorGateV3Error begin
        V3.require_preresolved_package(
            V3.JLD2_PKGID,
            source_attestation,
            entrypoints;
            locate_package = _ -> V3.SCRIPTS_PROJECT_PATH,
            loader = _ -> begin
                loader_invoked[] = true
                nothing
            end,
        )
    end
    @test !loader_invoked[]
    @test !V3.json_loaded()
    @test !V3.jld2_loaded()
    @test !V3.beforeit_loaded()
    @test !V3.v2_loaded()
end

@testset "v4 raw GDP kernel and synthetic-only formula oracle" begin
    levels = RawEngineeringGDPLevels(
        100.0,
        115.0,
        100.0,
        110.0,
    )
    result = compute_raw_engineering_operators(levels)
    @test result.real_gdp_growth ==
        400.0 * (log(110.0) - log(100.0))
    @test result.gdp_deflator_inflation ==
        400.0 * (
        (log(115.0) - log(110.0)) -
            (log(100.0) - log(100.0))
    )
    @test_throws Gate.ABMOneStepGateV4Error begin
        compute_raw_engineering_operators(
            RawEngineeringGDPLevels(100.0, 115.0, 0.0, 110.0),
        )
    end
    @test_throws Gate.ABMOneStepGateV4Error begin
        compute_raw_engineering_operators(
            RawEngineeringGDPLevels(100.0, Inf, 100.0, 110.0),
        )
    end
    oracle_digest = validate_synthetic_formula_oracle()
    @test occursin(r"^[0-9a-f]{64}$", oracle_digest)

    common_opening = 100.0
    posts = [104.0, 111.0, 127.0]
    pathwise = [
        compute_raw_engineering_operators(
                RawEngineeringGDPLevels(
                    common_opening,
                    post,
                    common_opening,
                    post,
                ),
            ).real_gdp_growth for post in posts
    ]
    mean_pathwise = sum(pathwise) / length(pathwise)
    transform_of_mean = 400.0 * (
        log(sum(posts) / length(posts)) - log(common_opening)
    )
    @test mean_pathwise != transform_of_mean
end

@testset "v4 seed adjacency and exact gate-owned call instrumentation" begin
    constructor_counter = Gate.PhaseCounter()
    constructor(parameters, initial_conditions) = (
        draw = rand(),
        parameters = deepcopy(parameters),
        initial_conditions = deepcopy(initial_conditions),
    )
    parameters = Dict{String, Any}("x" => 1)
    initial_conditions = Dict{String, Any}("y" => 2)
    first = construct_fresh_with_seed(
        constructor,
        123,
        parameters,
        initial_conditions,
        constructor_counter,
    )
    second = construct_fresh_with_seed(
        constructor,
        123,
        parameters,
        initial_conditions,
        constructor_counter,
    )
    @test first == second
    @test constructor_counter.constructions == 2
    @test parameters == Dict{String, Any}("x" => 1)
    @test initial_conditions == Dict{String, Any}("y" => 2)

    first_model = FakeOneStepModel(0.0, 0)
    first_counter = Gate.PhaseCounter()
    first_hash = serial_step_collect_with_seed!(
        fake_step!,
        fake_collect!,
        fake_state_hash,
        first_model,
        456,
        nothing,
        (:business_goods, :final_demand),
        first_counter,
    )
    second_model = FakeOneStepModel(0.0, 0)
    second_counter = Gate.PhaseCounter()
    second_hash = serial_step_collect_with_seed!(
        fake_step!,
        fake_collect!,
        fake_state_hash,
        second_model,
        456,
        nothing,
        (:business_goods, :final_demand),
        second_counter,
    )
    @test first_hash == second_hash
    @test first_model.value == second_model.value
    @test first_model.collections == 1
    @test second_model.collections == 1
    @test first_counter.steps == 1
    @test first_counter.post_step_collections == 1
    @test first_counter.constructions == 0
    @test first_counter.constructor_opening_collections == 0

    source = read(
        joinpath(
            @__DIR__,
            "USRevisedDataABMOneStepGateV4.jl",
        ),
        String,
    )
    @test occursin(
        r"Random\.seed!\(seed\)\s+return Base\.invokelatest\(",
        source,
    )
    @test occursin(
        r"Random\.seed!\(seed\)\s+Base\.invokelatest\(\s*step_function,\s*model;\s*parallel = false,",
        source,
    )
    @test occursin(r"shock! = shock", source)
    @test occursin(
        "transaction_markets = (:business_goods, :final_demand)",
        source,
    )
    @test occursin(
        r"transaction_markets = transaction_markets",
        source,
    )
    @test occursin(r"transaction_logger = nothing", source)
    @test occursin(r"opening_state_logger = nothing", source)
    @test !occursin("getfield(beforeit, :run!)", source)
    for forbidden_global in (
            "getfield(beforeit, :AUSTRIA2010Q1)",
            "getfield(beforeit, :ITALY2010Q1)",
            "getfield(beforeit, :STEADY_STATE2010Q1)",
            "getfield(beforeit, :ITALY_CALIBRATION)",
        )
        @test !occursin(forbidden_global, source)
    end
    for forbidden in (
            "V3.decode_artifact",
            "V3.qualify_artifact",
            "load_us_baseline",
            "[\"output_measurement\"]",
            "[\"metadata\"]",
        )
        @test !occursin(forbidden, source)
    end
    @test !occursin(
        r"getfield\(jld2, :load\),\s*path\s*\)",
        source,
    )
    @test occursin(
        r"getfield\(jld2, :load\),\s*path,\s*\"parameters\",\s*\"initial_conditions\"",
        source,
    )
end

@testset "v4 path ordering, replay identity, and Float64-bit hashing" begin
    primary = [fake_path(path_id) for path_id in 1:32]
    reverse_paths = reverse(primary)
    primary_digest = path_result_set_sha256(primary)
    @test path_result_set_sha256(reverse_paths) == primary_digest
    @test Gate.same_path_result(primary[1], deepcopy(primary[1]))
    @test !Gate.same_path_result(primary[1], fake_path(1; perturb = 0.5))
    changed = copy(primary)
    changed[1] = fake_path(1; perturb = 0.5)
    @test path_result_set_sha256(changed) != primary_digest
    zero_levels = RawEngineeringGDPLevels(0.0, 1.0, 1.0, 1.0)
    negative_zero_levels =
        RawEngineeringGDPLevels(-0.0, 1.0, 1.0, 1.0)
    @test Gate.semantic_sha256(zero_levels) !=
        Gate.semantic_sha256(negative_zero_levels)
end

@testset "v4 method-origin records and prohibited actions" begin
    records = [
        OneStepMethodOriginRecord(id, path, "BeforeIT") for
            (id, path) in Gate.METHOD_ORIGIN_PATHS
    ]
    @test validate_one_step_method_origins(records) === records
    @test one_step_method_origin_digest(records) ==
        Gate.ONE_STEP_METHOD_ORIGIN_SHA256
    changed = copy(records)
    first_record = first(changed)
    changed[1] = OneStepMethodOriginRecord(
        first_record.id,
        "src/other.jl",
        first_record.defining_module,
    )
    @test_throws Gate.ABMOneStepGateV4Error begin
        validate_one_step_method_origins(changed)
    end
    changed = copy(records)
    first_record = first(changed)
    changed[1] = OneStepMethodOriginRecord(
        first_record.id,
        first_record.relative_path,
        "Main",
    )
    @test_throws Gate.ABMOneStepGateV4Error begin
        validate_one_step_method_origins(changed)
    end
    @test_throws Gate.ABMOneStepGateV4Error begin
        validate_one_step_method_origins(records[1:(end - 1)])
    end
    for action in Gate.PROHIBITED_ACTIONS
        @test_throws Gate.ABMOneStepGateV4Error begin
            refuse_prohibited_action(action)
        end
    end
    @test_throws Gate.ABMOneStepGateV4Error begin
        refuse_prohibited_action(:unknown)
    end
end

@testset "v4 portable fail-closed runner boundary" begin
    @test STRICT_LOAD_PATH
    @test !V3.json_loaded()
    @test !V3.jld2_loaded()
    @test !V3.beforeit_loaded()
    @test !V3.v2_loaded()
    @test validate_precompiletools_unloaded()
    if !CANONICAL_RUNTIME
        @test_throws Gate.ABMOneStepGateV4Error begin
            run_installed_one_step_gate()
        end
        counts = attempt_execution_counts()
        @test all(
            field -> getfield(counts, field) == 0,
            fieldnames(OneStepExecutionCounts),
        )
        @test !V3.json_loaded()
        @test !V3.jld2_loaded()
        @test !V3.beforeit_loaded()
        @test !V3.v2_loaded()
        @test validate_precompiletools_unloaded()
    else
        result = run_installed_one_step_gate()
        @test result.schema_version ==
            "beforeit-us-revised-data-abm-one-step-gate.v4"
        @test result.protocol_sha256 == protocol_sha256()
        @test result.v3_acceptance_relied_upon === false
        @test result.qualified_input_sha256 ==
            Gate.V2_QUALIFIED_INPUT_SHA256
        @test result.seed_plan_sha256 == Gate.V2_SEED_PLAN_SHA256
        @test result.one_step_path_set_sha256 ==
            validate_protocol().document[
            "expected_one_step_path_set_sha256",
        ]
        @test result.replay_path.post_collection_state_sha256 ==
            validate_protocol().document[
            "expected_path_one_post_collection_state_sha256",
        ]
        @test result.opening_fingerprint_set_sha256 ==
            Gate.V3_OPENING_FINGERPRINT_SET_SHA256
        @test result.one_step_method_origin_sha256 ==
            Gate.ONE_STEP_METHOD_ORIGIN_SHA256
        @test result.package_import_side_data_manifest_sha256 ==
            Gate.SIDE_DATA_MANIFEST_SHA256
        @test result.selective_decode_contract ==
            Gate.SELECTIVE_DECODE_CONTRACT
        @test occursin(
            r"^[0-9a-f]{64}$",
            result.v4_execution_envelope_sha256,
        )
        @test result.v4_execution_envelope_sha256 ==
            Gate.EXPECTED_V4_EXECUTION_ENVELOPE_SHA256
        @test result.result_sha256 == Gate.EXPECTED_RESULT_SHA256
        @test result.execution_count_scope ==
            Gate.EXECUTION_COUNT_SCOPE
        @test result.execution_counts.total_constructions == 65
        @test result.execution_counts.total_steps == 65
        @test result.execution_counts.total_constructor_opening_collections ==
            65
        @test result.execution_counts.total_post_step_collections == 65
        @test result.execution_counts.total_collection_events == 130
        @test length(result.primary_paths) == 32
        @test length(result.reverse_paths) == 32
        @test result.replay_path.path_id == 1
        @test getfield.(result.primary_paths, :path_id) == collect(1:32)
        @test getfield.(result.reverse_paths, :path_id) == collect(32:-1:1)
        @test all(
            path -> path.origin_period == "2026Q1" &&
                path.target_period == "2026Q2" &&
                path.collection_time == [1, 2],
            result.primary_paths,
        )
        @test all(
            path -> path.opening_nominal_gdp > 0 &&
                path.post_nominal_gdp > 0 &&
                path.opening_real_gdp > 0 &&
                path.post_real_gdp > 0 &&
                isfinite(path.real_gdp_growth) &&
                isfinite(path.gdp_deflator_inflation),
            result.primary_paths,
        )
        @test all(
            path -> path.input_hashes_unchanged,
            result.primary_paths,
        )
        @test result.deterministic_replay_equal
        @test result.path_order_invariant
        @test result.input_hashes_unchanged
        @test result.software_one_step_verified
        @test result.initial_transition_characterized
        @test result.raw_diagnostic_path_values_returned
        @test result.measurement_basis_discontinuity_preserved
        @test result.truth_bearing_metadata_present_in_pinned_artifact
        @test result.truth_bearing_raw_artifact_bytes_hashed
        @test !result.truth_bearing_metadata_deserialized
        @test !result.truth_values_consumed_by_model_or_operator
        @test !result.truth_values_used_for_scoring
        @test !result.us_evaluation_truth_used
        @test result.us_nowcast_parameters_initial_conditions_selectively_deserialized
        @test result.package_import_side_data_deserialized
        @test result.package_import_side_data_attested
        @test !result.package_import_side_data_passed_to_v4_constructor_or_gdp_operator
        @test result.package_precompile_workload_execution_guard_attested
        @test !result.package_precompile_workload_executed
        @test result.precompiletools_clean_bootstrap_verified
        @test result.precompiletools_verbose_false
        @test result.compiled_modules_disabled
        @test result.pkgimages_disabled
        @test !result.generating_output
        @test result.ephemeral_jld2_snapshot_written
        @test !result.zero_filesystem_writes_claimed
        for field in (
                :independent_streams_established,
                :empirical_forecast_validated,
                :forecast_artifact_emitted,
                :forecast_artifact_serialized,
                :score_computed,
                :inference_run,
                :origin_admissible,
                :registry_write_allowed,
                :promotion_eligible,
                :class_h_allowed,
                :production_allowed,
                :reanchoring_used,
                :bridge_adjustment_used,
                :full_runtime_attestation,
            )
            @test getfield(result, field) === false
        end
        @test result.diagnostic_only
        if get(ENV, "ABM_ONE_STEP_GATE_V4_REPORT", "") == "1"
            println("v4_protocol_sha256=", result.protocol_sha256)
            println("v4_result_sha256=", result.result_sha256)
            println(
                "v4_execution_envelope_sha256=",
                result.v4_execution_envelope_sha256,
            )
            println(
                "v4_one_step_path_set_sha256=",
                result.one_step_path_set_sha256,
            )
        end
    end
end
