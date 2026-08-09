using SHA
using Test
using TOML

include("USRevisedDataABMEngineeringDiagnostic.jl")
using .USRevisedDataABMEngineeringDiagnostic

const ABM = USRevisedDataABMEngineeringDiagnostic
const PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_engineering_protocol.toml",
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function fixture_inputs()
    periods = [
        "2025Q1",
        "2025Q2",
        "2025Q3",
        "2025Q4",
        "2026Q1",
        "2026Q2",
        "2026Q3",
        "2026Q4",
    ]
    parameters = Dict{String, Any}(
        "alpha_s" => [1.0, 2.0],
        "a_sg" => [0.7 0.2; 0.3 0.8],
        "T" => 12,
        "use_growth_rate_ar1" => false,
    )
    initial_conditions = Dict{String, Any}(
        "C_G" => collect(101.0:108.0),
        "C_E" => reshape(collect(201.0:208.0), :, 1),
        "Y_I" => collect(301.0:308.0),
        "D_H" => 400.0,
        "N_s" => [10, 20],
        "opening_label" => "synthetic_engineering_fixture",
    )
    periods_by_series = Dict(
        key => copy(periods) for key in ("C_G", "C_E", "Y_I")
    )
    return (; parameters, initial_conditions, periods_by_series, periods)
end

function qualify(fixture = fixture_inputs())
    return sanitize_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        class_h_used = false,
    )
end

function semantic_mutation_throws(mutator)
    document = TOML.parsefile(PROTOCOL_PATH)
    mutator(document)
    return @test_throws ABMEngineeringContractError begin
        ABM.validate_protocol_semantics(document)
    end
end

@testset "ABM engineering protocol pin and semantic closure" begin
    protocol = validate_protocol()
    @test protocol.sha256 == protocol_sha256()
    @test protocol.sha256 == sha256_hex(read(PROTOCOL_PATH))
    @test protocol.document["schema_version"] ==
        "beforeit-us-revised-data-abm-engineering-protocol.v1"
    @test protocol.document["contract_id"] ==
        "beforeit-us-revised-data-abm-engineering-qualification.v1"
    @test protocol.document["information_track"] ==
        "revised_mixed_vintage_diagnostic"
    @test protocol.document["diagnostic_class"] ==
        "engineering_input_qualification_only"
    @test protocol.document["origin_period"] == "2026Q1"
    @test protocol.document["forecast_start_period"] == "2026Q2"
    @test protocol.document["forecast_end_period"] == "2027Q1"
    @test protocol.document["horizons"] == [1, 2, 3, 4]
    @test protocol.document["path_count"] == 32
    @test protocol.document["runner_implemented"] === false
    @test protocol.document["ensemble_executed"] === false

    declarations = protocol.document["declarations"]
    for key in (
            "origin_admissible",
            "promotion_eligible",
            "confirmatory",
            "truth_blind",
            "class_h_allowed",
            "production_registry_allowed",
            "scoring_allowed",
            "inference_allowed",
            "input_truth_isolation_verified",
            "input_lineage_verified",
            "truth_values_emitted",
            "forecast_values_emitted",
            "distribution_artifacts_emitted",
        )
        @test haskey(declarations, key)
        @test declarations[key] === false
        semantic_mutation_throws(
            document -> document["declarations"][key] = true,
        )
    end

    @test protocol.document["blockers"] == [
        "FULL_ACCOUNTING_BRIDGE_UNRESOLVED",
        "OUTPUT_SCALE_BRIDGE_UNVALIDATED",
        "TIER1_TARGET_OPERATOR_COVERAGE_ZERO_OF_EIGHT",
        "HISTORICAL_ORIGIN_COUNT_ZERO",
    ]
    @test protocol.document["sanitization"]["required_past_only_series"] ==
        ["C_G", "C_E", "Y_I"]
    @test protocol.document["sanitization"]["declared_dynamic_future_values_in_qualified_hash"] ===
        false
    @test protocol.document["sanitization"]["class_h_inputs_rejected"] ===
        true
    @test protocol.document["execution"]["serial_only"] === true
    @test protocol.document["execution"]["parallel_allowed"] === false
    @test protocol.document["execution"]["julia_threads"] == 1
    @test protocol.document["execution"]["openblas_threads"] == 1
    @test protocol.document["execution"]["process_global_rng_assumed"] ===
        true
    @test protocol.document["execution"]["seed_before_model_construction"] ===
        true
    @test protocol.document["execution"]["seed_before_simulation"] === true
    @test protocol.document["execution"]["construction_path_purpose"] ==
        "abm_engineering_model_construction"
    @test protocol.document["execution"]["simulation_path_purpose"] ==
        "abm_engineering_simulation"

    input_series = protocol.document["input_series"]
    @test getindex.(input_series, "id") == ["C_G", "C_E", "Y_I"]
    @test all(
        row ->
        row["unit"] ==
            "annualized_model_currency_flow_at_calibration_scale",
        input_series,
    )
    @test all(row -> row["frequency"] == "quarterly", input_series)
    @test all(
        row -> row["time_semantics"] == "history_through_origin_only",
        input_series,
    )
    operators = protocol.document["candidate_output_operators"]
    @test getindex.(operators, "id") ==
        ["real_gdp_growth", "gdp_deflator_inflation"]
    @test all(row -> row["unit"] == "annualized_log_percent", operators)
    @test all(row -> row["frequency"] == "quarterly", operators)
    @test all(row -> row["status"] == "NOT_VALIDATED", operators)

    mktemp() do path, io
        write(io, read(PROTOCOL_PATH))
        write(io, UInt8('\n'))
        close(io)
        @test_throws ABMEngineeringContractError validate_protocol(path)
    end
    @test_throws ABMEngineeringContractError validate_protocol(
        joinpath(@__DIR__, "absent_protocol.toml"),
    )
    semantic_mutation_throws(
        document ->
        document["information_track"] = "prospective",
    )
    semantic_mutation_throws(
        document -> document["diagnostic_class"] = "accuracy",
    )
    semantic_mutation_throws(
        document -> document["origin_period"] = "2026Q2",
    )
    semantic_mutation_throws(
        document -> document["forecast_start_period"] = "2026Q3",
    )
    semantic_mutation_throws(
        document -> document["forecast_end_period"] = "2026Q4",
    )
    semantic_mutation_throws(document -> document["horizons"] = [1, 2, 4])
    semantic_mutation_throws(document -> document["path_count"] = 500)
    semantic_mutation_throws(document -> document["runner_implemented"] = true)
    semantic_mutation_throws(document -> document["ensemble_executed"] = true)
    semantic_mutation_throws(document -> pop!(document, "blockers"))
    semantic_mutation_throws(
        document -> popfirst!(document["blockers"]),
    )
    semantic_mutation_throws(
        document -> reverse!(document["blockers"]),
    )
    semantic_mutation_throws(
        document -> document["sanitization"]["time_dimension"] = 2,
    )
    semantic_mutation_throws(
        document ->
        document["sanitization"]["declared_dynamic_future_values_in_qualified_hash"] =
            true,
    )
    semantic_mutation_throws(
        document ->
        document["sanitization"]["required_past_only_series"] =
            ["C_G", "C_E"],
    )
    semantic_mutation_throws(
        document -> document["execution"]["parallel_allowed"] = true,
    )
    semantic_mutation_throws(
        document -> document["execution"]["julia_threads"] = 2,
    )
    semantic_mutation_throws(
        document -> document["execution"]["openblas_threads"] = 2,
    )
    semantic_mutation_throws(
        document ->
        document["execution"]["seed_before_model_construction"] = false,
    )
    semantic_mutation_throws(
        document ->
        document["execution"]["seed_before_simulation"] = false,
    )
    semantic_mutation_throws(
        document ->
        document["input_series"][1]["formula"] = "future_value",
    )
    semantic_mutation_throws(
        document ->
        document["input_series"][2]["unit"] = "unknown",
    )
    semantic_mutation_throws(
        document ->
        document["candidate_output_operators"][1]["formula"] =
            "100*growth",
    )
    semantic_mutation_throws(
        document ->
        document["candidate_output_operators"][2]["unit"] = "level",
    )
    semantic_mutation_throws(
        document ->
        document["candidate_output_operators"][1]["status"] = "READY",
    )
    semantic_mutation_throws(document -> document["unknown"] = "field")
end

@testset "past-only slicing and partition integrity" begin
    fixture = fixture_inputs()
    qualified = qualify(fixture)

    @test qualified.origin_period == "2026Q1"
    @test qualified.protocol_sha256 == protocol_sha256()
    @test sort!(collect(keys(qualified.structural))) ==
        sort!(collect(keys(fixture.parameters)))
    @test sort!(collect(keys(qualified.dynamic))) ==
        ["C_E", "C_G", "Y_I"]
    @test sort!(collect(keys(qualified.state))) ==
        ["D_H", "N_s", "opening_label"]
    @test qualified.dynamic["C_G"] == collect(101.0:105.0)
    @test qualified.dynamic["C_E"] ==
        reshape(collect(201.0:205.0), :, 1)
    @test qualified.dynamic["Y_I"] == collect(301.0:305.0)
    @test size(qualified.dynamic["C_G"]) == (5,)
    @test size(qualified.dynamic["C_E"]) == (5, 1)
    @test size(qualified.dynamic["Y_I"]) == (5,)
    for key in ("C_G", "C_E", "Y_I")
        @test qualified.dynamic_periods[key] ==
            fixture.periods[1:5]
        @test last(qualified.dynamic_periods[key]) == "2026Q1"
        @test !("2026Q2" in qualified.dynamic_periods[key])
    end
    @test qualified.structural_members == [
        "parameters.T",
        "parameters.a_sg",
        "parameters.alpha_s",
        "parameters.use_growth_rate_ar1",
    ]
    @test qualified.dynamic_members == [
        "initial_conditions.C_E",
        "initial_conditions.C_G",
        "initial_conditions.Y_I",
    ]
    @test qualified.state_members == [
        "initial_conditions.D_H",
        "initial_conditions.N_s",
        "initial_conditions.opening_label",
    ]
    all_members = [
        qualified.structural_members
        qualified.dynamic_members
        qualified.state_members
    ]
    @test length(all_members) == 10
    @test length(unique(all_members)) == 10
    @test all(
        hash -> occursin(r"^[0-9a-f]{64}$", hash),
        values(qualified.partition_sha256),
    )
    @test occursin(
        r"^[0-9a-f]{64}$",
        qualified.qualified_input_sha256,
    )
    @test validate_partitions(qualified) === qualified

    reassembled = reassemble_inputs(qualified)
    @test reassembled.parameters == qualified.structural
    @test Set(keys(reassembled.initial_conditions)) ==
        Set(keys(fixture.initial_conditions))
    @test reassembled.initial_conditions["C_G"] == collect(101.0:105.0)
    @test reassembled.initial_conditions["C_E"] ==
        reshape(collect(201.0:205.0), :, 1)
    @test reassembled.initial_conditions["Y_I"] == collect(301.0:305.0)
    @test reassembled.initial_conditions["D_H"] == 400.0
    @test reassembled.periods_by_series == qualified.dynamic_periods

    for key in ("C_G", "C_E", "Y_I")
        changed = deepcopy(fixture)
        changed.initial_conditions[key][end] += 999.0
        future_mutation = qualify(changed)
        @test future_mutation.qualified_input_sha256 ==
            qualified.qualified_input_sha256
        @test future_mutation.partition_sha256 ==
            qualified.partition_sha256
        @test future_mutation.dynamic == qualified.dynamic
    end
    future_padding = deepcopy(fixture)
    future_padding.initial_conditions["C_G"][end] = NaN
    future_padding.initial_conditions["C_E"] =
        Matrix{Any}(fixture.initial_conditions["C_E"])
    future_padding.initial_conditions["C_E"][end] = missing
    future_padding.initial_conditions["Y_I"] =
        Any[fixture.initial_conditions["Y_I"]...]
    future_padding.initial_conditions["Y_I"][end] = nothing
    padded_qualified = qualify(future_padding)
    @test padded_qualified.qualified_input_sha256 ==
        qualified.qualified_input_sha256
    @test padded_qualified.partition_sha256 ==
        qualified.partition_sha256
    @test padded_qualified.dynamic == qualified.dynamic
    for key in ("C_G", "C_E", "Y_I")
        changed = deepcopy(fixture)
        changed.initial_conditions[key][2] += 1.0
        past_mutation = qualify(changed)
        @test past_mutation.qualified_input_sha256 !=
            qualified.qualified_input_sha256
        @test past_mutation.partition_sha256["dynamic"] !=
            qualified.partition_sha256["dynamic"]
        @test past_mutation.partition_sha256["structural"] ==
            qualified.partition_sha256["structural"]
        @test past_mutation.partition_sha256["state"] ==
            qualified.partition_sha256["state"]
    end
    origin_changed = deepcopy(fixture)
    origin_changed.initial_conditions["C_G"][5] += 1.0
    origin_mutation = qualify(origin_changed)
    @test origin_mutation.qualified_input_sha256 !=
        qualified.qualified_input_sha256
    @test origin_mutation.partition_sha256["dynamic"] !=
        qualified.partition_sha256["dynamic"]

    structural_changed = deepcopy(fixture)
    structural_changed.parameters["alpha_s"][1] += 1.0
    structural_mutation = qualify(structural_changed)
    @test structural_mutation.qualified_input_sha256 !=
        qualified.qualified_input_sha256
    @test structural_mutation.partition_sha256["structural"] !=
        qualified.partition_sha256["structural"]
    @test structural_mutation.partition_sha256["dynamic"] ==
        qualified.partition_sha256["dynamic"]
    @test structural_mutation.partition_sha256["state"] ==
        qualified.partition_sha256["state"]

    state_changed = deepcopy(fixture)
    state_changed.initial_conditions["D_H"] += 1.0
    state_mutation = qualify(state_changed)
    @test state_mutation.qualified_input_sha256 !=
        qualified.qualified_input_sha256
    @test state_mutation.partition_sha256["state"] !=
        qualified.partition_sha256["state"]
    @test state_mutation.partition_sha256["structural"] ==
        qualified.partition_sha256["structural"]
    @test state_mutation.partition_sha256["dynamic"] ==
        qualified.partition_sha256["dynamic"]

    reordered = (
        parameters = Dict(
            reverse(collect(pairs(fixture.parameters))),
        ),
        initial_conditions = Dict(
            reverse(collect(pairs(fixture.initial_conditions))),
        ),
        periods_by_series = Dict(
            reverse(collect(pairs(fixture.periods_by_series))),
        ),
        periods = copy(fixture.periods),
    )
    reordered_qualified = qualify(reordered)
    @test reordered_qualified.qualified_input_sha256 ==
        qualified.qualified_input_sha256
    @test reordered_qualified.partition_sha256 ==
        qualified.partition_sha256

    shape_changed = deepcopy(fixture)
    shape_changed.parameters["a_sg"] =
        reshape(vec(shape_changed.parameters["a_sg"]), 1, 4)
    shape_mutation = qualify(shape_changed)
    @test shape_mutation.partition_sha256["structural"] !=
        qualified.partition_sha256["structural"]

    additional = deepcopy(fixture)
    additional.initial_conditions["Y"] = collect(401.0:408.0)
    additional.periods_by_series["Y"] = copy(additional.periods)
    with_additional = sanitize_origin_inputs(
        additional.parameters,
        additional.initial_conditions,
        additional.periods_by_series;
        dynamic_keys = ["Y_I", "Y", "C_G", "C_E"],
        class_h_used = false,
    )
    @test haskey(with_additional.dynamic, "Y")
    @test !haskey(with_additional.state, "Y")
    @test with_additional.dynamic["Y"] == collect(401.0:405.0)
    @test last(with_additional.dynamic_periods["Y"]) == "2026Q1"

    undeclared_array = deepcopy(fixture)
    undeclared_array.initial_conditions["unclassified_array"] =
        collect(501.0:508.0)
    undeclared_qualified = qualify(undeclared_array)
    @test haskey(undeclared_qualified.state, "unclassified_array")
    changed_undeclared_array = deepcopy(undeclared_array)
    changed_undeclared_array.initial_conditions["unclassified_array"][end] +=
        1.0
    changed_undeclared_qualified = qualify(changed_undeclared_array)
    @test changed_undeclared_qualified.qualified_input_sha256 !=
        undeclared_qualified.qualified_input_sha256
    @test changed_undeclared_qualified.partition_sha256["state"] !=
        undeclared_qualified.partition_sha256["state"]

    mutated_value = deepcopy(qualified)
    mutated_value.dynamic["C_G"][1] += 1.0
    @test_throws ABMEngineeringContractError validate_partitions(mutated_value)
    mutated_member = deepcopy(qualified)
    pop!(mutated_member.state_members)
    @test_throws ABMEngineeringContractError validate_partitions(mutated_member)
    mutated_period = deepcopy(qualified)
    mutated_period.dynamic_periods["C_G"][end] = "2026Q2"
    @test_throws ABMEngineeringContractError validate_partitions(mutated_period)
    mutated_hash = deepcopy(qualified)
    mutated_hash.partition_sha256["state"] = repeat("0", 64)
    @test_throws ABMEngineeringContractError validate_partitions(mutated_hash)
end

@testset "sanitizer fail-closed cases" begin
    fixture = fixture_inputs()
    @test_throws UndefKeywordError sanitize_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series,
    )
    @test_throws ABMEngineeringContractError sanitize_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        origin_period = "2026Q2",
        class_h_used = false,
    )
    @test_throws ABMEngineeringContractError sanitize_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        class_h_used = true,
    )
    @test_throws ABMEngineeringContractError sanitize_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        dynamic_keys = ["C_G", "C_E"],
        class_h_used = false,
    )
    @test_throws ABMEngineeringContractError sanitize_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        dynamic_keys = ["C_G", "C_E", "Y_I", "C_G"],
        class_h_used = false,
    )

    missing_initial = deepcopy(fixture)
    pop!(missing_initial.initial_conditions, "C_G")
    @test_throws ABMEngineeringContractError qualify(missing_initial)

    missing_periods = deepcopy(fixture)
    pop!(missing_periods.periods_by_series, "C_G")
    @test_throws ABMEngineeringContractError qualify(missing_periods)
    extra_periods = deepcopy(fixture)
    extra_periods.periods_by_series["Y"] = copy(extra_periods.periods)
    @test_throws ABMEngineeringContractError qualify(extra_periods)

    noncontiguous = deepcopy(fixture)
    noncontiguous.periods_by_series["C_G"][3] = "2025Q4"
    @test_throws ABMEngineeringContractError qualify(noncontiguous)
    duplicate_period = deepcopy(fixture)
    duplicate_period.periods_by_series["C_G"][4] = "2025Q3"
    @test_throws ABMEngineeringContractError qualify(duplicate_period)
    invalid_period = deepcopy(fixture)
    invalid_period.periods_by_series["C_G"][1] = "2025-Q1"
    @test_throws ABMEngineeringContractError qualify(invalid_period)
    missing_origin = deepcopy(fixture)
    missing_origin.periods_by_series["C_G"] =
        ["2024Q1", "2024Q2", "2024Q3", "2024Q4", "2025Q1", "2025Q2", "2025Q3", "2025Q4"]
    @test_throws ABMEngineeringContractError qualify(missing_origin)

    length_mismatch = deepcopy(fixture)
    pop!(length_mismatch.initial_conditions["C_G"])
    @test_throws ABMEngineeringContractError qualify(length_mismatch)
    scalar_dynamic = deepcopy(fixture)
    scalar_dynamic.initial_conditions["C_G"] = 1.0
    @test_throws ABMEngineeringContractError qualify(scalar_dynamic)

    empty_parameters = deepcopy(fixture)
    empty!(empty_parameters.parameters)
    @test_throws ABMEngineeringContractError qualify(empty_parameters)
    empty_initial = deepcopy(fixture)
    empty!(empty_initial.initial_conditions)
    @test_throws ABMEngineeringContractError qualify(empty_initial)

    missing_value = deepcopy(fixture)
    missing_value.initial_conditions["D_H"] = missing
    @test_throws ABMEngineeringContractError qualify(missing_value)
    nothing_value = deepcopy(fixture)
    nothing_value.parameters["alpha_s"] = nothing
    @test_throws ABMEngineeringContractError qualify(nothing_value)
    nan_value = deepcopy(fixture)
    nan_value.initial_conditions["C_G"][2] = NaN
    @test_throws ABMEngineeringContractError qualify(nan_value)
    inf_value = deepcopy(fixture)
    inf_value.parameters["alpha_s"][1] = Inf
    @test_throws ABMEngineeringContractError qualify(inf_value)
    truth_key = deepcopy(fixture)
    truth_key.parameters["truth_value"] = 1.0
    @test_throws ABMEngineeringContractError qualify(truth_key)
    nested_score_key = deepcopy(fixture)
    nested_score_key.parameters["settings"] =
        Dict("score_weight" => 1.0)
    @test_throws ABMEngineeringContractError qualify(nested_score_key)

    nonstring_parameter_key = Dict{Any, Any}(fixture.parameters)
    nonstring_parameter_key[1] = 2.0
    @test_throws ABMEngineeringContractError sanitize_origin_inputs(
        nonstring_parameter_key,
        fixture.initial_conditions,
        fixture.periods_by_series;
        class_h_used = false,
    )
    nonstring_period_key = Dict{Any, Any}(fixture.periods_by_series)
    nonstring_period_key[1] = copy(fixture.periods)
    @test_throws ABMEngineeringContractError sanitize_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        nonstring_period_key;
        class_h_used = false,
    )
end

@testset "registry-derived path seeds and serial execution guard" begin
    qualified = qualify()
    plan = derive_path_seed_plan(
        20260807,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
    )
    reversed_plan = derive_path_seed_plan(
        20260807,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
        path_ids = reverse(collect(1:32)),
    )
    @test length(plan) == 32
    @test getfield.(plan, :path_id) == collect(1:32)
    @test getfield.(plan, :path_id) ==
        getfield.(reversed_plan, :path_id)
    @test getfield.(plan, :construction_seed) ==
        getfield.(reversed_plan, :construction_seed)
    @test getfield.(plan, :simulation_seed) ==
        getfield.(reversed_plan, :simulation_seed)
    @test getfield.(plan, :construction_seed_key_sha256) ==
        getfield.(reversed_plan, :construction_seed_key_sha256)
    @test getfield.(plan, :simulation_seed_key_sha256) ==
        getfield.(reversed_plan, :simulation_seed_key_sha256)
    @test path_seed_plan_sha256(plan) ==
        path_seed_plan_sha256(reversed_plan)
    construction_seeds = getfield.(plan, :construction_seed)
    simulation_seeds = getfield.(plan, :simulation_seed)
    construction_keys =
        getfield.(plan, :construction_seed_key_sha256)
    simulation_keys =
        getfield.(plan, :simulation_seed_key_sha256)
    @test length(unique(construction_seeds)) == 32
    @test length(unique(simulation_seeds)) == 32
    @test length(unique([construction_seeds; simulation_seeds])) == 64
    @test length(unique(construction_keys)) == 32
    @test length(unique(simulation_keys)) == 32
    @test length(unique([construction_keys; simulation_keys])) == 64
    @test all(record -> record.construction_seed >= 0, plan)
    @test all(record -> record.simulation_seed >= 0, plan)
    @test all(
        record -> occursin(
            r"^[0-9a-f]{64}$",
            record.construction_seed_key_sha256,
        ),
        plan,
    )
    @test all(
        record -> occursin(
            r"^[0-9a-f]{64}$",
            record.simulation_seed_key_sha256,
        ),
        plan,
    )
    @test all(
        record ->
        record.origin_manifest_sha256 ==
            qualified.qualified_input_sha256,
        plan,
    )
    @test all(
        record ->
        record.construction_seed_key_sha256 !=
            record.simulation_seed_key_sha256,
        plan,
    )
    @test all(
        record ->
        record.construction_seed != record.simulation_seed,
        plan,
    )

    other_master = derive_path_seed_plan(
        20260808,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
    )
    @test getfield.(other_master, :construction_seed) !=
        getfield.(plan, :construction_seed)
    @test getfield.(other_master, :simulation_seed) !=
        getfield.(plan, :simulation_seed)
    other_experiment = derive_path_seed_plan(
        20260807,
        qualified;
        experiment_id = "us-abm-engineering-2026q1-alt",
        model_id = "beforeit-us-abm",
    )
    @test getfield.(other_experiment, :construction_seed) !=
        getfield.(plan, :construction_seed)
    @test getfield.(other_experiment, :simulation_seed) !=
        getfield.(plan, :simulation_seed)
    other_model = derive_path_seed_plan(
        20260807,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm-alt",
    )
    @test getfield.(other_model, :construction_seed) !=
        getfield.(plan, :construction_seed)
    @test getfield.(other_model, :simulation_seed) !=
        getfield.(plan, :simulation_seed)

    @test_throws ABMEngineeringContractError derive_path_seed_plan(
        -1,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
    )
    @test_throws ABMEngineeringContractError derive_path_seed_plan(
        true,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
    )
    @test_throws ABMEngineeringContractError derive_path_seed_plan(
        1,
        qualified;
        experiment_id = "bad id",
        model_id = "beforeit-us-abm",
    )
    @test_throws ABMEngineeringContractError derive_path_seed_plan(
        1,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "bad id",
    )
    @test_throws ABMEngineeringContractError derive_path_seed_plan(
        1,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
        path_ids = collect(1:31),
    )
    @test_throws ABMEngineeringContractError derive_path_seed_plan(
        1,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
        path_ids = [collect(1:31); 31],
    )
    @test_throws ABMEngineeringContractError derive_path_seed_plan(
        1,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
        path_ids = [0; collect(2:32)],
    )
    boolean_paths = Any[collect(1:31); true]
    @test_throws ABMEngineeringContractError derive_path_seed_plan(
        1,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
        path_ids = boolean_paths,
    )

    forged_seed = copy(plan)
    original = forged_seed[1]
    forged_seed[1] = PathSeedRecord(
        original.master_seed,
        original.experiment_id,
        original.origin_manifest_sha256,
        original.model_id,
        original.path_id,
        original.construction_seed + 1,
        original.construction_seed_key_sha256,
        original.simulation_seed,
        original.simulation_seed_key_sha256,
    )
    @test_throws ABMEngineeringContractError path_seed_plan_sha256(
        forged_seed,
    )
    mixed_experiment = copy(plan)
    original = mixed_experiment[2]
    mixed_experiment[2] = PathSeedRecord(
        original.master_seed,
        "other-experiment",
        original.origin_manifest_sha256,
        original.model_id,
        original.path_id,
        original.construction_seed,
        original.construction_seed_key_sha256,
        original.simulation_seed,
        original.simulation_seed_key_sha256,
    )
    @test_throws ABMEngineeringContractError path_seed_plan_sha256(
        mixed_experiment,
    )

    guard = execution_guard(
        parallel = false,
        julia_threads = 1,
        openblas_threads = 1,
        process_global_rng_assumed = true,
        seed_before_model_construction = true,
        seed_before_simulation = true,
    )
    @test guard.parallel === false
    @test guard.julia_threads == 1
    @test guard.openblas_threads == 1
    @test guard.process_global_rng_assumed === true
    @test guard.seed_before_model_construction === true
    @test guard.seed_before_simulation === true
    @test_throws ABMEngineeringContractError execution_guard(
        parallel = true,
        julia_threads = 1,
        openblas_threads = 1,
    )
    @test_throws ABMEngineeringContractError execution_guard(
        julia_threads = 2,
        openblas_threads = 1,
    )
    @test_throws ABMEngineeringContractError execution_guard(
        julia_threads = 1,
        openblas_threads = 2,
    )
    @test_throws ABMEngineeringContractError execution_guard(
        julia_threads = 1,
        openblas_threads = 1,
        process_global_rng_assumed = false,
    )
    @test_throws ABMEngineeringContractError execution_guard(
        julia_threads = 1,
        openblas_threads = 1,
        seed_before_model_construction = false,
    )
    @test_throws ABMEngineeringContractError execution_guard(
        julia_threads = 1,
        openblas_threads = 1,
        seed_before_simulation = false,
    )
    @test_throws ABMEngineeringContractError execution_guard(
        julia_threads = true,
        openblas_threads = 1,
    )
    @test_throws ABMEngineeringContractError execution_guard(
        julia_threads = 1,
        openblas_threads = true,
    )
end

@testset "failure records preserve engineering blockers" begin
    qualified = qualify()
    plan = derive_path_seed_plan(
        7,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
    )
    expected_codes = Dict(
        :model_construction => "MODEL_CONSTRUCTION_FAILURE",
        :simulation => "SIMULATION_FAILURE",
        :accounting_gate => "ACCOUNTING_GATE_FAILURE",
        :scale_gate => "SCALE_GATE_FAILURE",
        :target_operator => "TARGET_OPERATOR_FAILURE",
        :nonfinite_output => "NONFINITE_OUTPUT_FAILURE",
        :unexpected => "UNEXPECTED_FAILURE",
    )
    failures = EngineeringFailure[]
    for (path_id, stage) in enumerate(keys(expected_codes))
        failure = record_engineering_failure(
            plan,
            path_id,
            stage,
            ErrorException("synthetic $stage failure"),
        )
        push!(failures, failure)
        @test failure.path_id == path_id
        expected_substream = stage == :model_construction ?
            "abm_engineering_model_construction" :
            "abm_engineering_simulation"
        @test failure.substream == expected_substream
        expected_seed_key = stage == :model_construction ?
            plan[path_id].construction_seed_key_sha256 :
            plan[path_id].simulation_seed_key_sha256
        @test failure.seed_key_sha256 ==
            expected_seed_key
        @test failure.stage == String(stage)
        @test failure.code == expected_codes[stage]
        @test failure.exception_type == "ErrorException"
        @test occursin("synthetic", failure.message)
    end
    @test ABM.validate_failures(failures, plan) === failures
    @test expected_codes[:accounting_gate] != expected_codes[:scale_gate]
    @test_throws ABMEngineeringContractError record_engineering_failure(
        plan,
        33,
        :simulation,
        ErrorException("no path"),
    )
    @test_throws ABMEngineeringContractError record_engineering_failure(
        plan,
        1,
        :score,
        ErrorException("forbidden"),
    )
    @test_throws ABMEngineeringContractError record_engineering_failure(
        plan,
        true,
        :simulation,
        ErrorException("Bool path"),
    )

    unicode_failure = record_engineering_failure(
        plan,
        8,
        :unexpected,
        ErrorException(repeat("é", 3000)),
    )
    @test ncodeunits(unicode_failure.message) <= 4096
    @test isvalid(unicode_failure.message)
    @test ABM.validate_failures([unicode_failure], plan) ==
        [unicode_failure]

    duplicate = [failures; failures[1]]
    @test_throws ABMEngineeringContractError ABM.validate_failures(
        duplicate,
        plan,
    )
    wrong_hash = deepcopy(failures)
    wrong_hash[1] = EngineeringFailure(
        wrong_hash[1].path_id,
        wrong_hash[1].substream,
        repeat("0", 64),
        wrong_hash[1].stage,
        wrong_hash[1].code,
        wrong_hash[1].exception_type,
        wrong_hash[1].message,
    )
    @test_throws ABMEngineeringContractError ABM.validate_failures(
        wrong_hash,
        plan,
    )
    wrong_substream = deepcopy(failures)
    wrong_substream[1] = EngineeringFailure(
        wrong_substream[1].path_id,
        wrong_substream[1].substream ==
            "abm_engineering_simulation" ?
            "abm_engineering_model_construction" :
            "abm_engineering_simulation",
        wrong_substream[1].seed_key_sha256,
        wrong_substream[1].stage,
        wrong_substream[1].code,
        wrong_substream[1].exception_type,
        wrong_substream[1].message,
    )
    @test_throws ABMEngineeringContractError ABM.validate_failures(
        wrong_substream,
        plan,
    )
    wrong_code = deepcopy(failures)
    wrong_code[1] = EngineeringFailure(
        wrong_code[1].path_id,
        wrong_code[1].substream,
        wrong_code[1].seed_key_sha256,
        wrong_code[1].stage,
        "SCORE_FAILURE",
        wrong_code[1].exception_type,
        wrong_code[1].message,
    )
    @test_throws ABMEngineeringContractError ABM.validate_failures(
        wrong_code,
        plan,
    )
    empty_message = deepcopy(failures)
    empty_message[1] = EngineeringFailure(
        empty_message[1].path_id,
        empty_message[1].substream,
        empty_message[1].seed_key_sha256,
        empty_message[1].stage,
        empty_message[1].code,
        empty_message[1].exception_type,
        "",
    )
    @test_throws ABMEngineeringContractError ABM.validate_failures(
        empty_message,
        plan,
    )
    raw_exception_type = deepcopy(failures)
    raw_exception_type[1] = EngineeringFailure(
        raw_exception_type[1].path_id,
        raw_exception_type[1].substream,
        raw_exception_type[1].seed_key_sha256,
        raw_exception_type[1].stage,
        raw_exception_type[1].code,
        "ErrorException actual=123.0",
        raw_exception_type[1].message,
    )
    @test_throws ABMEngineeringContractError ABM.validate_failures(
        raw_exception_type,
        plan,
    )
end

@testset "no-output manifest and prohibited actions" begin
    qualified = qualify()
    plan = derive_path_seed_plan(
        42,
        qualified;
        experiment_id = "us-abm-engineering-2026q1",
        model_id = "beforeit-us-abm",
    )
    guard = execution_guard(
        julia_threads = 1,
        openblas_threads = 1,
    )
    manifest = build_qualification_manifest(qualified, plan, guard)
    @test validate_qualification_manifest(
        manifest,
        qualified,
        plan,
        guard,
    ) === manifest
    @test manifest["schema_version"] ==
        "beforeit-us-revised-data-abm-engineering-manifest.v1"
    @test manifest["information_track"] ==
        "revised_mixed_vintage_diagnostic"
    @test manifest["qualification_status"] ==
        "CONTRACT_ONLY_NOT_RUN_BLOCKED"
    @test manifest["origin_period"] == "2026Q1"
    @test manifest["forecast_start_period"] == "2026Q2"
    @test manifest["forecast_end_period"] == "2027Q1"
    @test manifest["horizons"] == [1, 2, 3, 4]
    @test manifest["declarations"]["origin_admissible"] === false
    @test manifest["declarations"]["promotion_eligible"] === false
    @test manifest["declarations"]["confirmatory"] === false
    @test manifest["declarations"]["truth_blind"] === false
    @test manifest["declarations"]["class_h_allowed"] === false
    @test manifest["declarations"]["production_registry_allowed"] ===
        false
    @test manifest["declarations"]["scoring_allowed"] === false
    @test manifest["declarations"]["inference_allowed"] === false
    @test manifest["execution"]["runner_implemented"] === false
    @test manifest["execution"]["ensemble_executed"] === false
    @test manifest["execution"]["parallel"] === false
    @test length(manifest["path_seed_plan"]) == 32
    @test isempty(manifest["failures"])
    @test manifest["blockers"] == [
        "FULL_ACCOUNTING_BRIDGE_UNRESOLVED",
        "OUTPUT_SCALE_BRIDGE_UNVALIDATED",
        "TIER1_TARGET_OPERATOR_COVERAGE_ZERO_OF_EIGHT",
        "HISTORICAL_ORIGIN_COUNT_ZERO",
    ]
    @test all(
        row -> row["status"] == "NOT_VALIDATED",
        manifest["candidate_output_operators"],
    )
    @test Set(keys(manifest["input"])) == Set(
        [
            "qualified_input_sha256",
            "partition_sha256",
            "partition_members",
            "dynamic_period_bounds",
        ],
    )
    @test !haskey(manifest, "actual")
    @test !haskey(manifest, "truth")
    @test !haskey(manifest, "forecast_values")
    @test !haskey(manifest, "scores")
    @test !haskey(manifest, "inference")
    @test !haskey(manifest["input"], "values")

    accounting_failure = record_engineering_failure(
        plan,
        1,
        :accounting_gate,
        ErrorException("identity residual exceeds unqualified tolerance"),
    )
    failed_manifest = build_qualification_manifest(
        qualified,
        plan,
        guard;
        failures = [accounting_failure],
    )
    @test length(failed_manifest["failures"]) == 1
    @test failed_manifest["failures"][1]["code"] ==
        "ACCOUNTING_GATE_FAILURE"
    @test !haskey(failed_manifest["failures"][1], "message")
    @test !haskey(
        failed_manifest["failures"][1],
        "exception_type",
    )
    @test occursin(
        r"^[0-9a-f]{64}$",
        failed_manifest["failures"][1]["message_sha256"],
    )
    @test occursin(
        r"^[0-9a-f]{64}$",
        failed_manifest["failures"][1]["exception_type_sha256"],
    )
    @test validate_qualification_manifest(
        failed_manifest,
        qualified,
        plan,
        guard;
        failures = [accounting_failure],
    ) === failed_manifest

    mutations = Function[
        value -> value["declarations"]["promotion_eligible"] = true,
        value -> value["declarations"]["origin_admissible"] = true,
        value -> value["declarations"]["class_h_allowed"] = true,
        value -> value["execution"]["runner_implemented"] = true,
        value -> value["execution"]["ensemble_executed"] = true,
        value -> value["execution"]["parallel"] = true,
        value -> popfirst!(value["blockers"]),
        value ->
        value["candidate_output_operators"][1]["status"] = "READY",
        value -> value["input"]["qualified_input_sha256"] = repeat("0", 64),
        value ->
        value["path_seed_plan"][1]["construction_seed"] += 1,
        value -> value["horizons"] = [1, 2, 4],
        value -> value["qualification_status"] = "READY",
        value -> value["actual"] = 1.0,
        value -> value["scores"] = Dict("rmse" => 0.0),
        value -> value["unknown"] = true,
    ]
    for mutate in mutations
        changed = deepcopy(manifest)
        mutate(changed)
        @test_throws ABMEngineeringContractError validate_qualification_manifest(
            changed,
            qualified,
            plan,
            guard,
        )
    end

    for action in (
            :score,
            :inference,
            :promotion,
            :origin_admission,
            :production_registry,
            :class_h,
            :truth_access,
            :forecast_emission,
        )
        @test_throws ABMEngineeringContractError refuse_prohibited_action(
            action,
        )
    end
    @test_throws ABMEngineeringContractError refuse_prohibited_action(
        :unknown,
    )
end
