using LinearAlgebra
using Random
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

include("USRevisedDataABMMultiStepGateV5.jl")
using .USRevisedDataABMMultiStepGateV5

const Gate = USRevisedDataABMMultiStepGateV5
const V4 = Gate.V4
const V3 = Gate.V3
const PROTOCOL_PATH = joinpath(@__DIR__, "abm_multi_step_gate_v5.toml")
const STRICT_LOAD_PATH =
    get(ENV, "JULIA_LOAD_PATH", nothing) == V4.JULIA_LOAD_PATH_ENV &&
    Base.LOAD_PATH == V4.SYMBOLIC_LOAD_PATH &&
    Base.load_path() == [V3.SCRIPTS_PROJECT_PATH, Sys.STDLIB]
const CANONICAL_RUNTIME =
    V3.ENV.current_execution_envelope() ==
    V3.ENV.CANONICAL_EXECUTION_ENVELOPE &&
    STRICT_LOAD_PATH &&
    Base.active_project() isa AbstractString &&
    realpath(Base.active_project()) == realpath(V3.SCRIPTS_PROJECT_PATH)

mutable struct FakeFourStepModel
    t::Int
    collection_time::Vector{Int}
    draws::Vector{Float64}
    events::Vector{String}
end

function fake_step!(
        model::FakeFourStepModel;
        parallel,
        shock!,
        transaction_logger,
        transaction_markets,
        opening_state_logger,
    )
    parallel === false || error("fake step must be serial")
    shock! === nothing || error("fake shock must be nothing")
    transaction_logger === nothing || error("unexpected transaction logger")
    transaction_markets == (:business_goods, :final_demand) ||
        error("unexpected transaction markets")
    opening_state_logger === nothing || error("unexpected opening logger")
    push!(model.events, "step-$(model.t)")
    push!(model.draws, rand())
    model.t += 1
    return model
end

function fake_collect!(model::FakeFourStepModel)
    push!(model.events, "collect-$(model.t)")
    push!(model.collection_time, model.t)
    return model
end

function fake_trace(model::FakeFourStepModel, horizon, phase)
    expected_time = horizon + 1
    model.t == expected_time || error("fake model time changed")
    if phase === :post_step
        model.collection_time == collect(1:horizon) ||
            error("fake pre-collection trace changed")
    elseif phase === :post_collection
        model.collection_time == collect(1:(horizon + 1)) ||
            error("fake post-collection trace changed")
    else
        error("unknown fake trace phase")
    end
    push!(model.events, "trace-$horizon-$(String(phase))")
    return true
end

function fake_state_hash(model::FakeFourStepModel)
    push!(model.events, "hash-$(model.t)-$(length(model.collection_time))")
    payload = join(bitstring.(model.draws), ":") *
        ":$(model.t):$(join(model.collection_time, ','))"
    return bytes2hex(SHA.sha256(codeunits(payload)))
end

function fake_path(path_id; perturb = 0.0)
    base = Float64(path_id) + perturb
    digest(label, index = 0) = bytes2hex(
        SHA.sha256(codeunits("$label-$path_id-$index-$perturb")),
    )
    nominal = [100.0 + base * index for index in 0:4]
    real = [100.0 + (base + 1.0) * index for index in 0:4]
    operators = compute_raw_four_quarter_operators(
        RawFourQuarterGDPLevels(nominal, real),
    )
    return MultiStepPathResult(
        path_id,
        Gate.CONSTRUCTION_SEEDS[path_id],
        Gate.SIMULATION_SEEDS[path_id],
        Gate.ORIGIN_PERIOD,
        copy(Gate.TARGET_PERIODS),
        copy(Gate.HORIZONS),
        collect(1:5),
        nominal,
        real,
        operators.real_gdp_growth,
        operators.gdp_deflator_inflation,
        digest("opening"),
        [digest("post-step", horizon) for horizon in 1:4],
        [digest("post-collection", horizon) for horizon in 1:4],
        digest("parameters"),
        digest("initial"),
        true,
        [1000 + path_id + horizon for horizon in 1:4],
    )
end

@testset "v5 fresh bootstrap and closed protocol" begin
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
    @test V4.validate_precompiletools_unloaded()
    package_envelope = V4.validate_uncompiled_package_load_envelope()
    @test package_envelope.compiled_modules_disabled
    @test package_envelope.pkgimages_disabled
    @test !package_envelope.generating_output
    protocol = validate_protocol()
    @test protocol.sha256 == protocol_sha256()
    @test protocol.sha256 == bytes2hex(SHA.sha256(read(PROTOCOL_PATH)))
    document = protocol.document
    @test document["schema_version"] ==
        "beforeit-us-revised-data-abm-multi-step-gate.v5"
    @test document["diagnostic_class"] ==
        "quarantined_four_quarter_free_running_software_qualification"
    @test document["origin_period"] == "2026Q1"
    @test document["target_periods"] ==
        ["2026Q2", "2026Q3", "2026Q4", "2027Q1"]
    @test document["horizons"] == collect(1:4)
    @test document["horizon_measurement_basis"] == [
        "model_implied_opening_to_post_step_flow",
        "post_step_flow_to_post_step_flow",
        "post_step_flow_to_post_step_flow",
        "post_step_flow_to_post_step_flow",
    ]
    @test document["seed_namespace_experiment_id"] ==
        "us-abm-constructor-gate-v3"
    @test document["construction_seeds"] == V4.CONSTRUCTION_SEEDS
    @test document["simulation_seeds"] == V4.SIMULATION_SEEDS
    @test document["v4_module_sha256"] == Gate.V4_MODULE_SHA256
    @test document["v4_protocol_sha256"] == Gate.V4_PROTOCOL_SHA256
    @test document["v4_accepted_result_sha256"] ==
        Gate.V4_ACCEPTED_RESULT_SHA256
    @test document["v4_one_step_path_set_sha256"] ==
        Gate.V4_ONE_STEP_PATH_SET_SHA256
    @test document["v4_opening_fingerprint_set_sha256"] ==
        Gate.V4_OPENING_FINGERPRINT_SET_SHA256
    @test document["v4_path_one_h1_post_collection_sha256"] ==
        Gate.V4_PATH_ONE_H1_POST_COLLECTION_SHA256
    @test document["expected_method_origin_sha256"] ==
        Gate.METHOD_ORIGIN_SHA256
    @test document["path_evaluation_rule"] ==
        "transform_each_raw_path_and_horizon_before_any_ensemble_summary"
    @test document["step_rule"] ==
        "seed_simulation_once_then_four_direct_one_argument_serial_step_calls_each_followed_by_one_collect_data_call"
    @test length(document["pinned_files"]) ==
        length(Gate.DIRECT_PIN_HASHES)
    @test length(document["method_origins"]) == 7

    counts = document["execution_counts"]
    @test counts["primary_constructions"] == 32
    @test counts["primary_steps"] == 128
    @test counts["primary_constructor_opening_collections"] == 32
    @test counts["primary_post_step_collections"] == 128
    @test counts["primary_total_collection_events"] == 160
    @test counts["reverse_constructions"] == 32
    @test counts["reverse_steps"] == 128
    @test counts["reverse_constructor_opening_collections"] == 32
    @test counts["reverse_post_step_collections"] == 128
    @test counts["reverse_total_collection_events"] == 160
    @test counts["replay_constructions"] == 1
    @test counts["replay_steps"] == 4
    @test counts["replay_constructor_opening_collections"] == 1
    @test counts["replay_post_step_collections"] == 4
    @test counts["replay_total_collection_events"] == 5
    @test counts["total_constructions"] == 65
    @test counts["total_steps"] == 260
    @test counts["total_constructor_opening_collections"] == 65
    @test counts["total_post_step_collections"] == 260
    @test counts["total_collection_events"] == 325

    for key in Gate.TRUE_DECLARATIONS
        @test document["declarations"][key] === true
    end
    for key in Gate.FALSE_DECLARATIONS
        @test document["declarations"][key] === false
    end
    for key in Gate.TRUE_ATTESTATION_LIMITS
        @test document["attestation_limits"][key] === true
    end
    for key in Gate.FALSE_ATTESTATION_LIMITS
        @test document["attestation_limits"][key] === false
    end
    @test "OPENING_MEASUREMENT_BASIS_DISCONTINUITY_PRESERVED" in
        document["blockers"]

    mutation = deepcopy(document)
    mutation["target_periods"][3] = "2027Q1"
    @test_throws Gate.ABMMultiStepGateV5Error begin
        validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["horizon_measurement_basis"][2] =
        "model_implied_opening_to_post_step_flow"
    @test_throws Gate.ABMMultiStepGateV5Error begin
        validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["execution_counts"]["total_steps"] = 259
    @test_throws Gate.ABMMultiStepGateV5Error begin
        validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["declarations"]["origin_admissible"] = true
    @test_throws Gate.ABMMultiStepGateV5Error begin
        validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["simulation_seeds"][1] += 1
    @test_throws Gate.ABMMultiStepGateV5Error begin
        validate_protocol_semantics(mutation)
    end
end

@testset "v5 direct pins and inherited v4 closure" begin
    snapshots = validate_source_pins()
    @test Set(keys(snapshots)) == Set(keys(Gate.DIRECT_PIN_HASHES))
    @test V4.validate_protocol().sha256 == Gate.V4_PROTOCOL_SHA256
    @test V4.protocol_sha256() == Gate.V4_PROTOCOL_SHA256
    @test V4.side_data_manifest_sha256() ==
        Gate.SIDE_DATA_MANIFEST_SHA256
    @test V4.V3_MODULE_SHA256 ==
        "e035a8b35e65ea383d28ceef6673ae311e6fe74a5394a2c45bf576e0b0600815"
    @test V4.V2_QUALIFIED_INPUT_SHA256 ==
        Gate.V2_QUALIFIED_INPUT_SHA256
    @test V4.V2_SEED_PLAN_SHA256 == Gate.V2_SEED_PLAN_SHA256

    v3_protocol = V3.validate_protocol()
    source_attestation =
        V3.validate_dependency_source_trees(v3_protocol.document)
    entrypoints = V3.validate_package_entrypoint_resolutions(
        v3_protocol.document,
        source_attestation,
    )
    @test source_attestation.source_tree_count == 82
    @test entrypoints.package_entrypoint_count == 83
    @test !V3.json_loaded()
    @test !V3.jld2_loaded()
    @test !V3.beforeit_loaded()
    @test !V3.v2_loaded()
end

@testset "v5 four-quarter raw GDP kernel" begin
    levels = RawFourQuarterGDPLevels(
        [100.0, 106.0, 111.0, 109.0, 119.0],
        [100.0, 104.0, 108.0, 105.0, 112.0],
    )
    result = compute_raw_four_quarter_operators(levels)
    @test length(result.real_gdp_growth) == 4
    @test length(result.gdp_deflator_inflation) == 4
    for horizon in 1:4
        @test result.real_gdp_growth[horizon] == 400.0 * (
            log(levels.real_gdp[horizon + 1]) -
                log(levels.real_gdp[horizon])
        )
        @test result.gdp_deflator_inflation[horizon] == 400.0 * (
            (
                log(levels.nominal_gdp[horizon + 1]) -
                    log(levels.real_gdp[horizon + 1])
            ) -
                (
                log(levels.nominal_gdp[horizon]) -
                    log(levels.real_gdp[horizon])
            )
        )
    end
    @test_throws Gate.ABMMultiStepGateV5Error begin
        compute_raw_four_quarter_operators(
            RawFourQuarterGDPLevels(
                [100.0, 101.0, 102.0, 103.0],
                [100.0, 101.0, 102.0, 103.0],
            ),
        )
    end
    @test_throws Gate.ABMMultiStepGateV5Error begin
        compute_raw_four_quarter_operators(
            RawFourQuarterGDPLevels(
                [100.0, 101.0, 0.0, 103.0, 104.0],
                [100.0, 101.0, 102.0, 103.0, 104.0],
            ),
        )
    end
    @test_throws Gate.ABMMultiStepGateV5Error begin
        compute_raw_four_quarter_operators(
            RawFourQuarterGDPLevels(
                [100.0, 101.0, Inf, 103.0, 104.0],
                [100.0, 101.0, 102.0, 103.0, 104.0],
            ),
        )
    end
    valid_nominal = [100.0, 101.0, 102.0, 103.0, 104.0]
    for invalid_real in (
            [100.0, 101.0, 102.0, 103.0],
            [100.0, 101.0, 0.0, 103.0, 104.0],
            [100.0, 101.0, Inf, 103.0, 104.0],
            [100.0, 101.0, NaN, 103.0, 104.0],
        )
        @test_throws Gate.ABMMultiStepGateV5Error begin
            compute_raw_four_quarter_operators(
                RawFourQuarterGDPLevels(copy(valid_nominal), invalid_real),
            )
        end
    end
    @test_throws Gate.ABMMultiStepGateV5Error begin
        compute_raw_four_quarter_operators(
            RawFourQuarterGDPLevels(
                [100.0, 101.0, NaN, 103.0, 104.0],
                copy(valid_nominal),
            ),
        )
    end
    @test_throws Gate.ABMMultiStepGateV5Error begin
        RawFourQuarterGDPLevels(fill(true, 5), copy(valid_nominal))
    end
    @test_throws Gate.ABMMultiStepGateV5Error begin
        RawFourQuarterGDPLevels(Float32.(valid_nominal), copy(valid_nominal))
    end
    oracle_digest = validate_synthetic_formula_oracle()
    @test occursin(r"^[0-9a-f]{64}$", oracle_digest)

    @test_throws Gate.SyntheticOperator.GDPOperatorQualificationError begin
        Gate.SyntheticOperator.compute_synthetic_operators(
            ["2026Q1", "2026Q2", "2026Q4", "2027Q1", "2027Q2"],
            [1],
            reshape([100.0, 101.0, 102.0, 103.0, 104.0], 5, 1),
            reshape([100.0, 101.0, 102.0, 103.0, 104.0], 5, 1);
            fixture_class = "SYNTHETIC_OPERATOR_TEST_FIXTURE",
            fixture_id = "synthetic-v5-period-gap",
            path_kind = "RAW_MODEL_UNCORRECTED_SYNTHETIC",
            truth_accessed = false,
            empirical_path = false,
            class_h_used = false,
            bridge_adjusted = false,
            origin_reanchored = false,
        )
    end
end

@testset "v5 seed-once trace and exact helper counts" begin
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

    failing_constructor_counter = Gate.PhaseCounter()
    failing_constructor(_, _) = error("injected constructor failure")
    @test_throws ErrorException begin
        construct_fresh_with_seed(
            failing_constructor,
            123,
            parameters,
            initial_conditions,
            failing_constructor_counter,
        )
    end
    @test failing_constructor_counter.constructions == 1
    @test failing_constructor_counter.steps == 0
    @test failing_constructor_counter.constructor_opening_collections == 0
    @test failing_constructor_counter.post_step_collections == 0

    model = FakeFourStepModel(1, [1], Float64[], String[])
    counter = Gate.PhaseCounter()
    input_events = String[]
    input_guard(horizon, phase) = begin
        push!(input_events, "$horizon-$(String(phase))")
        true
    end
    transition = serial_four_step_collect_with_seed!(
        fake_step!,
        fake_collect!,
        fake_state_hash,
        fake_trace,
        input_guard,
        fake -> length(fake.draws),
        model,
        456,
        nothing,
        (:business_goods, :final_demand),
        counter,
    )
    Random.seed!(456)
    expected_draws = rand(4)
    @test model.draws == expected_draws
    @test length(unique(model.draws)) == 4
    @test model.t == 5
    @test model.collection_time == collect(1:5)
    @test length(transition.post_step_hashes) == 4
    @test length(transition.post_collection_hashes) == 4
    @test transition.numeric_counts == collect(1:4)
    @test counter.constructions == 0
    @test counter.steps == 4
    @test counter.constructor_opening_collections == 0
    @test counter.post_step_collections == 4
    @test input_events == [
        "1-post_step",
        "1-post_collection",
        "2-post_step",
        "2-post_collection",
        "3-post_step",
        "3-post_collection",
        "4-post_step",
        "4-post_collection",
    ]
    @test model.events == [
        "step-1",
        "trace-1-post_step",
        "hash-2-1",
        "collect-2",
        "trace-1-post_collection",
        "hash-2-2",
        "step-2",
        "trace-2-post_step",
        "hash-3-2",
        "collect-3",
        "trace-2-post_collection",
        "hash-3-3",
        "step-3",
        "trace-3-post_step",
        "hash-4-3",
        "collect-4",
        "trace-3-post_collection",
        "hash-4-4",
        "step-4",
        "trace-4-post_step",
        "hash-5-4",
        "collect-5",
        "trace-4-post_collection",
        "hash-5-5",
    ]

    asymmetric = Gate.AttemptCounters(
        Gate.PhaseCounter(2, 3, 5, 7),
        Gate.PhaseCounter(11, 13, 17, 19),
        Gate.PhaseCounter(23, 29, 31, 37),
    )
    asymmetric_counts = Gate.execution_counts(asymmetric)
    @test asymmetric_counts.total_constructions == 36
    @test asymmetric_counts.total_steps == 45
    @test asymmetric_counts.total_constructor_opening_collections == 53
    @test asymmetric_counts.total_post_step_collections == 63
    @test asymmetric_counts.total_collection_events == 116

    failing_model = FakeFourStepModel(1, [1], Float64[], String[])
    failing_counter = Gate.PhaseCounter()
    function fail_on_second_collect(model)
        model.t == 3 && error("injected collection failure")
        return fake_collect!(model)
    end
    @test_throws ErrorException begin
        serial_four_step_collect_with_seed!(
            fake_step!,
            fail_on_second_collect,
            fake_state_hash,
            fake_trace,
            (_, _) -> true,
            fake -> length(fake.draws),
            failing_model,
            789,
            nothing,
            (:business_goods, :final_demand),
            failing_counter,
        )
    end
    @test failing_counter.steps == 2
    @test failing_counter.post_step_collections == 1
    @test failing_counter.constructions == 0
    @test failing_model.t == 3
    @test failing_model.collection_time == [1, 2]

    failing_step_model = FakeFourStepModel(1, [1], Float64[], String[])
    failing_step_counter = Gate.PhaseCounter()
    function fail_on_second_step(model; kwargs...)
        model.t == 2 && error("injected step failure")
        return fake_step!(model; kwargs...)
    end
    @test_throws ErrorException begin
        serial_four_step_collect_with_seed!(
            fail_on_second_step,
            fake_collect!,
            fake_state_hash,
            fake_trace,
            (_, _) -> true,
            fake -> length(fake.draws),
            failing_step_model,
            789,
            nothing,
            (:business_goods, :final_demand),
            failing_step_counter,
        )
    end
    @test failing_step_counter.steps == 2
    @test failing_step_counter.post_step_collections == 1
    @test failing_step_counter.constructions == 0
    @test failing_step_model.t == 2
    @test failing_step_model.collection_time == [1, 2]
    @test length(failing_step_model.draws) == 1
end

@testset "v5 path hashes, replay, and v4 prefix projection" begin
    primary = [fake_path(path_id) for path_id in 1:32]
    reverse_paths = reverse(primary)
    primary_digest = multi_step_path_set_sha256(primary)
    @test multi_step_path_set_sha256(reverse_paths) == primary_digest
    @test Gate.same_path_result(primary[1], deepcopy(primary[1]))
    @test !Gate.same_path_result(primary[1], fake_path(1; perturb = 0.5))
    changed = copy(primary)
    changed[1] = fake_path(1; perturb = 0.5)
    @test multi_step_path_set_sha256(changed) != primary_digest
    prefix = Gate.v4_h1_prefix(primary[1])
    @test prefix isa V4.OneStepPathResult
    @test prefix.collection_time == [1, 2]
    @test prefix.post_collection_state_sha256 ==
        primary[1].post_collection_state_sha256[1]
    @test prefix.numeric_values_checked_after_collection ==
        primary[1].numeric_values_checked_after_collection[1]
end

@testset "v5 static call boundary and prohibited actions" begin
    source = read(
        joinpath(@__DIR__, "USRevisedDataABMMultiStepGateV5.jl"),
        String,
    )
    @test occursin(
        r"Random\.seed!\(seed\)\s+for horizon in HORIZONS",
        source,
    )
    @test length(collect(eachmatch(r"Random\.seed!\(seed\)", source))) == 2
    @test occursin(
        r"Base\.invokelatest\(\s*step_function,\s*model;\s*parallel = false,",
        source,
    )
    @test occursin(r"shock! = shock", source)
    @test occursin(r"transaction_logger = nothing", source)
    @test occursin(r"opening_state_logger = nothing", source)
    @test occursin(
        r"transaction_markets = transaction_markets",
        source,
    )
    for forbidden in (
            "getfield(beforeit, :run!)",
            "getfield(beforeit, :ensemblerun!)",
            "run_installed_one_step_gate",
            "get_predictions_from_sims",
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
    @test !occursin("four_quarter_growth", source)
    @test !occursin("warmup", lowercase(source))
    @test !occursin("winsor", lowercase(source))
    @test !occursin("resample", lowercase(source))
    @test !occursin("clamp", lowercase(source))
    for action in Gate.PROHIBITED_ACTIONS
        @test_throws Gate.ABMMultiStepGateV5Error begin
            refuse_prohibited_action(action)
        end
    end
    @test_throws Gate.ABMMultiStepGateV5Error begin
        refuse_prohibited_action(:unknown)
    end
end

@testset "v5 portable fail-closed runner boundary" begin
    @test STRICT_LOAD_PATH
    @test !V3.json_loaded()
    @test !V3.jld2_loaded()
    @test !V3.beforeit_loaded()
    @test !V3.v2_loaded()
    @test V4.validate_precompiletools_unloaded()
    if !CANONICAL_RUNTIME
        @test_throws Gate.ABMMultiStepGateV5Error begin
            run_installed_multi_step_gate()
        end
        counts = attempt_execution_counts()
        @test all(
            field -> getfield(counts, field) == 0,
            fieldnames(MultiStepExecutionCounts),
        )
        @test !V3.json_loaded()
        @test !V3.jld2_loaded()
        @test !V3.beforeit_loaded()
        @test !V3.v2_loaded()
        @test V4.validate_precompiletools_unloaded()
    else
        result = run_installed_multi_step_gate()
        @test result.schema_version ==
            "beforeit-us-revised-data-abm-multi-step-gate.v5"
        @test result.protocol_sha256 == protocol_sha256()
        @test result.v4_module_sha256 == Gate.V4_MODULE_SHA256
        @test result.v4_protocol_sha256 == Gate.V4_PROTOCOL_SHA256
        @test result.v4_accepted_result_sha256 ==
            Gate.V4_ACCEPTED_RESULT_SHA256
        @test !result.v4_runner_reexecuted
        @test result.qualified_input_sha256 ==
            Gate.V2_QUALIFIED_INPUT_SHA256
        @test result.seed_plan_sha256 == Gate.V2_SEED_PLAN_SHA256
        @test result.multi_step_path_set_sha256 ==
            validate_protocol().document[
            "expected_multi_step_path_set_sha256",
        ]
        @test result.replay_path.post_collection_state_sha256[4] ==
            validate_protocol().document[
            "expected_path_one_h4_post_collection_sha256",
        ]
        @test result.v4_h1_prefix_path_set_sha256 ==
            Gate.V4_ONE_STEP_PATH_SET_SHA256
        @test result.opening_fingerprint_set_sha256 ==
            Gate.V4_OPENING_FINGERPRINT_SET_SHA256
        @test result.replay_path.post_collection_state_sha256[1] ==
            Gate.V4_PATH_ONE_H1_POST_COLLECTION_SHA256
        @test result.multi_step_method_origin_sha256 ==
            Gate.METHOD_ORIGIN_SHA256
        @test result.package_import_side_data_manifest_sha256 ==
            Gate.SIDE_DATA_MANIFEST_SHA256
        @test result.selective_decode_contract ==
            Gate.SELECTIVE_DECODE_CONTRACT
        @test result.multi_step_execution_envelope_sha256 ==
            validate_protocol().document[
            "expected_multi_step_execution_envelope_sha256",
        ]
        @test result.result_sha256 == Gate.EXPECTED_RESULT_SHA256
        @test result.execution_count_scope == Gate.EXECUTION_COUNT_SCOPE
        @test result.horizon_measurement_basis ==
            Gate.HORIZON_MEASUREMENT_BASIS
        @test result.execution_counts.total_constructions == 65
        @test result.execution_counts.total_steps == 260
        @test result.execution_counts.total_constructor_opening_collections ==
            65
        @test result.execution_counts.total_post_step_collections == 260
        @test result.execution_counts.total_collection_events == 325
        @test length(result.primary_paths) == 32
        @test length(result.reverse_paths) == 32
        @test result.replay_path.path_id == 1
        @test getfield.(result.primary_paths, :path_id) == collect(1:32)
        @test getfield.(result.reverse_paths, :path_id) == collect(32:-1:1)
        @test all(
            path -> path.origin_period == "2026Q1" &&
                path.target_periods == Gate.TARGET_PERIODS &&
                path.horizons == collect(1:4) &&
                path.collection_time == collect(1:5) &&
                length(path.nominal_gdp_levels) == 5 &&
                length(path.real_gdp_levels) == 5 &&
                length(path.real_gdp_growth) == 4 &&
                length(path.gdp_deflator_inflation) == 4 &&
                length(path.post_step_state_sha256) == 4 &&
                length(path.post_collection_state_sha256) == 4 &&
                length(path.numeric_values_checked_after_collection) == 4,
            result.primary_paths,
        )
        @test all(
            path -> all(>(0), path.nominal_gdp_levels) &&
                all(>(0), path.real_gdp_levels) &&
                all(isfinite, path.real_gdp_growth) &&
                all(isfinite, path.gdp_deflator_inflation),
            result.primary_paths,
        )
        @test all(path -> path.input_hashes_unchanged, result.primary_paths)
        @test result.deterministic_replay_equal
        @test result.path_order_invariant
        @test result.input_hashes_unchanged
        @test result.software_four_quarter_path_verified
        @test result.free_running_without_intermediate_reanchoring
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
        @test !result.package_import_side_data_passed_to_v5_constructor_or_gdp_operator
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
                :input_lineage_verified,
                :source_period_labels_authenticated,
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
        if get(ENV, "ABM_MULTI_STEP_GATE_V5_REPORT", "") == "1"
            println("v5_protocol_sha256=", result.protocol_sha256)
            println("v5_result_sha256=", result.result_sha256)
            println(
                "v5_execution_envelope_sha256=",
                result.multi_step_execution_envelope_sha256,
            )
            println(
                "v5_multi_step_path_set_sha256=",
                result.multi_step_path_set_sha256,
            )
            println(
                "v5_path_one_h4_post_collection_sha256=",
                result.replay_path.post_collection_state_sha256[4],
            )
        end
    end
end
