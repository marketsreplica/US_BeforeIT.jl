using SHA
using Test
using TOML
using JLD2

include("USRevisedDataABMOriginFirewallV2.jl")
using .USRevisedDataABMOriginFirewallV2

const FW = USRevisedDataABMOriginFirewallV2
const PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_origin_firewall_v2.toml",
)
const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))

struct ZeroBasedVector{T} <: AbstractVector{T}
    parent::Vector{T}
end

Base.size(value::ZeroBasedVector) = size(value.parent)
Base.axes(value::ZeroBasedVector) =
    (0:(length(value.parent) - 1),)
Base.getindex(value::ZeroBasedVector, index::Int) =
    value.parent[index + 1]
Base.IndexStyle(::Type{<:ZeroBasedVector}) = IndexLinear()

struct ZeroBasedMatrix{T} <: AbstractMatrix{T}
    parent::Matrix{T}
end

Base.size(value::ZeroBasedMatrix) = size(value.parent)
Base.axes(value::ZeroBasedMatrix) = (
    0:(size(value.parent, 1) - 1),
    axes(value.parent, 2),
)
Base.getindex(
    value::ZeroBasedMatrix,
    row::Int,
    column::Int,
) = value.parent[row + 1, column]
Base.IndexStyle(::Type{<:ZeroBasedMatrix}) = IndexCartesian()

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
        key => 0.25 for key in FW.MODEL_PARAMETER_KEYS
    )
    parameters["G"] = 2
    parameters["T_prime"] = 5
    parameters["H_act"] = 20.0
    parameters["H_inact"] = 8.0
    parameters["J"] = 2.0
    parameters["L"] = 3.0
    parameters["C"] = [
        1.0 0.0 0.0
        0.0 1.0 0.0
        0.0 0.0 1.0
    ]
    parameters["a_sg"] = [0.8 0.1; 0.2 0.9]
    parameters["beta_s"] = reshape([2.0, 3.0], 2, 1)
    for key in FW.PARAMETER_VECTOR_KEYS
        parameters[key] = key == "I_s" ? [2.0, 3.0] : [0.5, 0.75]
    end
    parameters["S"] = 2
    parameters["T"] = 4
    parameters["T_max"] = 3
    parameters["use_commodity_balance_inventory"] = true
    parameters["use_growth_rate_ar1"] = false
    parameters["use_product_tax_netting"] = true

    initial_conditions = Dict{String, Any}(
        key => 1.0 for key in FW.STATIC_STATE_KEYS
    )
    initial_conditions["N_s"] = [10.0, 20.0]
    initial_conditions["S_s"] = [0.0, 4.0]
    initial_conditions["sb_other"] = -0.5
    initial_conditions["C_E"] =
        reshape(collect(201.0:208.0), :, 1)
    initial_conditions["C_G"] =
        reshape(collect(101.0:108.0), :, 1)
    initial_conditions["Y_I"] =
        reshape(collect(301.0:308.0), :, 1)
    initial_conditions["Y"] = collect(401.0:408.0)
    initial_conditions["pi"] = collect(0.01:0.01:0.08)
    initial_conditions["Y_EA_series"] = collect(501.0:505.0)
    initial_conditions["pi_EA_series"] = collect(0.11:0.01:0.15)
    initial_conditions["r_bar_series"] = collect(0.21:0.01:0.25)
    for key in FW.EXCLUDED_DIAGNOSTIC_VECTOR_KEYS
        initial_conditions[key] = [1.0, 2.0]
    end
    for key in FW.EXCLUDED_DIAGNOSTIC_SCALAR_KEYS
        initial_conditions[key] = 3.0
    end
    periods_by_series = Dict(
        key => copy(periods) for key in FW.DYNAMIC_HISTORY_KEYS
    )
    return (; parameters, initial_conditions, periods_by_series, periods)
end

function qualify(fixture = fixture_inputs())
    return qualify_base_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        model_variant = "base",
        model_constructor_id = "BeforeIT.Model",
        class_h_used = false,
    )
end

function seed_plan(inputs = qualify())
    return derive_base_path_seed_plan(
        20260807,
        inputs;
        experiment_id = "us-abm-firewall-v2",
        model_id = "beforeit-us-abm-base",
    )
end

function semantic_mutation_throws(mutator)
    document = TOML.parsefile(PROTOCOL_PATH)
    mutator(document)
    return @test_throws ABMOriginFirewallV2Error begin
        FW.validate_protocol_semantics(document)
    end
end

function quarter_string(ordinal)
    quarter = mod(ordinal - 1, 4) + 1
    year = (ordinal - quarter) ÷ 4
    return "$(year)Q$(quarter)"
end

function copy_source_pin_closure(protocol, destination_root)
    for source in protocol.document["source_files"]
        destination = joinpath(destination_root, source["path"])
        mkpath(dirname(destination))
        cp(
            joinpath(REPOSITORY_ROOT, source["path"]),
            destination;
            force = true,
        )
    end
    for closure in protocol.document["source_closures"]
        for relative_root in closure["roots"]
            source_root = joinpath(REPOSITORY_ROOT, relative_root)
            for (current, _, files) in walkdir(source_root)
                for name in files
                    endswith(name, closure["suffix"]) || continue
                    source_path = joinpath(current, name)
                    relative = relpath(source_path, REPOSITORY_ROOT)
                    destination =
                        joinpath(destination_root, relative)
                    mkpath(dirname(destination))
                    cp(source_path, destination; force = true)
                end
            end
        end
    end
    return destination_root
end

function duplicate_normalized_key_dictionary(
        dictionary,
        key,
    )
    result = IdDict{AbstractString, Any}()
    for (member, value) in pairs(dictionary)
        result[String(member)] = deepcopy(value)
    end
    parent = "x" * key
    duplicate = SubString(parent, 2:lastindex(parent))
    result[duplicate] = deepcopy(dictionary[key])
    return result
end

@testset "v2 protocol, source pins, and frozen base scope" begin
    protocol = validate_protocol()
    @test protocol.sha256 == protocol_sha256()
    @test protocol.sha256 == bytes2hex(SHA.sha256(read(PROTOCOL_PATH)))
    @test protocol.document["schema_version"] ==
        "beforeit-us-revised-data-abm-origin-firewall.v2"
    @test protocol.document["model_variant"] == "base"
    @test protocol.document["model_constructor_id"] == "BeforeIT.Model"
    @test protocol.document["path_count"] == 32
    @test Sys.WORD_SIZE == FW.INTEGER_WORD_SIZE_BITS == 64
    @test protocol.document["execution"]["integer_word_size_bits"] == 64
    @test protocol.document["execution"]["seed_modulus_rule"] ==
        "UInt64_digest_prefix_mod_typemax_Int"
    @test protocol.document["runner_implemented"] === false
    @test protocol.document["model_constructed"] === false
    @test protocol.document["model_stepped"] === false
    @test protocol.document["forecast_emitted"] === false
    @test protocol.document["projection"]["external_run_horizon"] == 4
    @test protocol.document["projection"]["array_indexing_rule"] ==
        "one_based_axes_required_before_projection"
    @test protocol.document["projection"]["run_length_source"] ==
        "maximum_frozen_protocol_horizon_not_source_T"
    member_counts = (
        (
            "raw_source_parameter_keys",
            FW.RAW_PARAMETER_KEYS,
            FW.RAW_PARAMETER_COUNT,
        ),
        (
            "excluded_source_parameter_keys",
            FW.EXCLUDED_PARAMETER_KEYS,
            FW.EXCLUDED_PARAMETER_COUNT,
        ),
        (
            "qualified_model_parameter_keys",
            FW.MODEL_PARAMETER_KEYS,
            FW.MODEL_PARAMETER_COUNT,
        ),
        (
            "raw_source_initial_condition_keys",
            FW.RAW_INITIAL_CONDITION_KEYS,
            FW.RAW_INITIAL_CONDITION_COUNT,
        ),
        (
            "qualified_static_state_keys",
            FW.STATIC_STATE_KEYS,
            FW.STATIC_STATE_COUNT,
        ),
        (
            "qualified_dynamic_history_keys",
            FW.DYNAMIC_HISTORY_KEYS,
            FW.DYNAMIC_HISTORY_COUNT,
        ),
        (
            "excluded_source_initial_condition_keys",
            FW.EXCLUDED_INITIAL_CONDITION_KEYS,
            FW.EXCLUDED_INITIAL_CONDITION_COUNT,
        ),
    )
    for (field, compiled, expected_count) in member_counts
        @test length(compiled) == expected_count
        @test length(unique(compiled)) == expected_count
        @test length(protocol.document[field]) == expected_count
        @test length(unique(protocol.document[field])) == expected_count
    end
    @test protocol.document["projection"]["raw_source_parameter_count"] ==
        FW.RAW_PARAMETER_COUNT
    @test protocol.document["projection"]["excluded_parameter_count"] ==
        FW.EXCLUDED_PARAMETER_COUNT
    @test protocol.document["projection"]["model_parameter_projection_count"] ==
        FW.MODEL_PARAMETER_COUNT
    @test protocol.document["projection"]["raw_source_initial_condition_count"] ==
        FW.RAW_INITIAL_CONDITION_COUNT
    @test protocol.document["projection"]["static_state_projection_count"] ==
        FW.STATIC_STATE_COUNT
    @test protocol.document["projection"]["dynamic_history_projection_count"] ==
        FW.DYNAMIC_HISTORY_COUNT
    @test protocol.document["projection"]["excluded_initial_condition_count"] ==
        FW.EXCLUDED_INITIAL_CONDITION_COUNT
    @test protocol.document["excluded_source_parameter_keys"] ==
        collect(FW.EXCLUDED_PARAMETER_KEYS)
    @test protocol.document["excluded_source_initial_condition_keys"] ==
        collect(FW.EXCLUDED_INITIAL_CONDITION_KEYS)
    @test all(
        variant["status"] == "NOT_ALLOWED_BY_V2"
            for variant in protocol.document["future_variants"]
    )
    @test getindex.(
        protocol.document["future_variants"],
        "model_variant",
    ) == ["growth_rate_ar1", "canvas"]
    @test protocol.document["declarations"]["source_schema_validated"] ===
        true
    @test protocol.document["declarations"]["runtime_projection_schema_validated"] ===
        true
    @test protocol.document["declarations"]["constructor_integer_conversion_validated"] ===
        true
    @test protocol.document["declarations"]["qualified_input_integrity_binding_only"] ===
        true
    @test protocol.document["declarations"]["downstream_raw_requalification_or_authenticated_receipt_required"] ===
        true
    @test protocol.document["declarations"]["repository_preference_files_required_absent"] ===
        true
    for key in (
            "constructor_domain_admissibility_validated",
            "qualified_input_authentication_proof",
            "origin_admissible",
            "promotion_eligible",
            "confirmatory",
            "truth_blind",
            "class_h_allowed",
            "input_lineage_verified",
            "source_period_labels_authenticated",
            "runtime_numeric_preferences_validated",
            "runtime_julia_version_validated",
            "external_dependency_source_artifact_closure_validated",
            "production_registry_allowed",
            "scoring_allowed",
            "inference_allowed",
            "truth_values_emitted",
            "forecast_values_emitted",
            "distribution_artifacts_emitted",
        )
        @test protocol.document["declarations"][key] === false
    end
    @test protocol.document["projection"]["constructor_integer_fields"] ==
        ["H_act", "H_inact", "I_s", "J", "L", "N_s"]
    @test protocol.document["projection"]["constructor_integer_rule"] ==
        "finite_nonboolean_exact_Int_value_preserved_by_Float64_projection"
    @test protocol.document["projection"]["constructor_runtime_type_check"] ==
        "v3_must_require_BeforeIT.typeFloat_Float64_and_typeInt_Int64"
    @test protocol.document["projection"]["constructor_runtime_julia_version_check"] ==
        "v3_must_require_VERSION_1.10.3"
    @test protocol.document["projection"]["constructor_external_dependency_check"] ==
        "v3_must_bind_installed_dependency_trees_artifacts_and_runtime"
    @test protocol.document["required_absent_files"] ==
        collect(FW.REQUIRED_ABSENT_FILES)
    @test all(
        relative_path ->
        !ispath(joinpath(REPOSITORY_ROOT, relative_path)),
        FW.REQUIRED_ABSENT_FILES,
    )
    source_paths = getindex.(protocol.document["source_files"], "path")
    @test length(source_paths) == 22
    @test length(unique(source_paths)) == 22
    for consumer_path in (
            "src/BeforeIT.jl",
            "src/model_init/agents.jl",
            "src/model_init/init.jl",
            "src/model_init/init_firms.jl",
            "src/model_init/init_workers.jl",
            "src/utils/randpl.jl",
            "src/utils/data.jl",
            "src/model_extensions/init_growth_rate_model.jl",
            "src/model_extensions/init_CANVAS.jl",
        )
        @test consumer_path in source_paths
    end
    @test length(protocol.document["source_closures"]) == 1
    source_closure = only(protocol.document["source_closures"])
    @test source_closure["roots"] == ["src", "ext"]
    @test source_closure["suffix"] == ".jl"
    @test source_closure["member_count"] == 60
    @test source_closure["sha256"] ==
        FW.source_closure_sha256(REPOSITORY_ROOT, FW.SOURCE_CLOSURES[1])
    @test validate_source_pins()
    @test bytes2hex(
        SHA.sha256(
            read(
                joinpath(
                    REPOSITORY_ROOT,
                    "scripts",
                    "us",
                    "forecasting",
                    "diagnostics",
                    "USRevisedDataABMEngineeringDiagnostic.jl",
                ),
            ),
        ),
    ) == "052343cefac1e286a3a93f8de2d60b2d232316a9b0c2a847cf68225bce224147"
    @test bytes2hex(
        SHA.sha256(
            read(
                joinpath(
                    REPOSITORY_ROOT,
                    "scripts",
                    "us",
                    "forecasting",
                    "diagnostics",
                    "revised_data",
                    "abm_engineering_protocol.toml",
                ),
            ),
        ),
    ) == "34461f24ff09e1aa1eed7bf9bad5d8b415eab011bd82b8f7e7a114d0e2246743"

    semantic_mutation_throws(
        document -> document["model_variant"] = "canvas",
    )
    semantic_mutation_throws(
        document -> document["model_constructor_id"] = "BeforeIT.ModelGR",
    )
    semantic_mutation_throws(
        document -> document["runner_implemented"] = true,
    )
    semantic_mutation_throws(
        document -> document["projection"]["external_run_horizon"] = 12,
    )
    semantic_mutation_throws(
        document -> pop!(document["qualified_model_parameter_keys"]),
    )
    semantic_mutation_throws(
        document -> push!(
            document["raw_source_initial_condition_keys"],
            "basic_price_household_control",
        ),
    )
    semantic_mutation_throws(
        document -> reverse!(
            document["excluded_source_initial_condition_keys"],
        ),
    )
    semantic_mutation_throws(
        document ->
        document["future_variants"][2]["status"] = "ALLOWED",
    )
    semantic_mutation_throws(
        document -> document["declarations"]["origin_admissible"] = true,
    )
    semantic_mutation_throws(
        document ->
        document["declarations"]["constructor_domain_admissibility_validated"] =
            true,
    )
    semantic_mutation_throws(
        document ->
        document["execution"]["integer_word_size_bits"] = 32,
    )
    semantic_mutation_throws(
        document ->
        document["source_files"][1]["sha256"] = repeat("0", 64),
    )
    semantic_mutation_throws(
        document ->
        document["source_closures"][1]["member_count"] -= 1,
    )
    semantic_mutation_throws(document -> document["unknown"] = true)
    protocol_collision = duplicate_normalized_key_dictionary(
        protocol.document,
        "model_variant",
    )
    @test_throws ABMOriginFirewallV2Error FW.validate_protocol_semantics(
        protocol_collision,
    )
    @test_throws ABMOriginFirewallV2Error FW.canonical(
        protocol_collision,
    )

    mktemp() do path, io
        write(io, read(PROTOCOL_PATH))
        write(io, UInt8('\n'))
        close(io)
        @test_throws ABMOriginFirewallV2Error validate_protocol(path)
    end
    consumer_source_path = "src/utils/extensions.jl"
    mktempdir() do root
        copy_source_pin_closure(protocol, root)
        open(
            joinpath(
                root,
                consumer_source_path,
            ),
            "a",
        ) do io
            write(io, '\n')
        end
        @test_throws ABMOriginFirewallV2Error validate_source_pins(root)
    end
    mktempdir() do root
        copy_source_pin_closure(protocol, root)
        preference_path = joinpath(root, "scripts", "us", "LocalPreferences.toml")
        open(preference_path, "w") do io
            write(io, "[BeforeIT]\ntypeInt = \"Int32\"\n")
        end
        @test_throws ABMOriginFirewallV2Error validate_source_pins(root)
    end
    mktempdir() do root
        copy_source_pin_closure(protocol, root)
        rm(joinpath(root, consumer_source_path))
        @test_throws ABMOriginFirewallV2Error validate_source_pins(root)
    end
    mktempdir() do root
        copy_source_pin_closure(protocol, root)
        extra = joinpath(
            root,
            "src",
            "utils",
            "constructor_override.jl",
        )
        open(extra, "w") do io
            write(io, "nothing\n")
        end
        @test_throws ABMOriginFirewallV2Error validate_source_pins(root)
    end
    mktempdir() do root
        for source in protocol.document["source_files"]
            destination = joinpath(root, source["path"])
            mkpath(dirname(destination))
            cp(joinpath(REPOSITORY_ROOT, source["path"]), destination)
        end
        @test_throws ABMOriginFirewallV2Error validate_source_pins(root)
    end
    if !Sys.iswindows()
        mktempdir() do root
            mktempdir() do outside
                copy_source_pin_closure(protocol, root)
                pinned = joinpath(
                    root,
                    consumer_source_path,
                )
                external = joinpath(outside, "extensions.jl")
                cp(pinned, external)
                rm(pinned)
                symlink(external, pinned)
                @test_throws ABMOriginFirewallV2Error validate_source_pins(
                    root,
                )
            end
        end
    end
end

@testset "installed 2026Q1 envelope projects without model construction" begin
    baseline_path = joinpath(
        REPOSITORY_ROOT,
        "data",
        "us",
        "baselines",
        "US_2026Q1_nowcast.jld2",
    )
    @test isfile(baseline_path)
    artifact = JLD2.load(baseline_path)
    @test Set(keys(artifact)) ==
        Set(["parameters", "initial_conditions", "metadata"])
    parameters = artifact["parameters"]
    initial_conditions = artifact["initial_conditions"]
    @test Set(keys(parameters)) == Set(FW.RAW_PARAMETER_KEYS)
    @test Set(keys(initial_conditions)) ==
        Set(FW.RAW_INITIAL_CONDITION_KEYS)
    @test parameters["T"] == 12
    @test parameters["T_max"] == 1
    @test parameters["T_prime"] == 117
    @test size(initial_conditions["C_G"]) == (129, 1)
    @test size(initial_conditions["C_E"]) == (129, 1)
    @test size(initial_conditions["Y_I"]) == (129, 1)
    @test length(initial_conditions["Y"]) == 117
    @test length(initial_conditions["pi"]) == 117
    @test all(
        key -> Int(parameters[key]) isa Int,
        FW.INTEGER_LIKE_PARAMETER_KEYS,
    )
    @test all(value -> Int(value) isa Int, parameters["I_s"])
    @test all(value -> Int(value) isa Int, initial_conditions["N_s"])

    first_ordinal = 4 * 1997 + 1
    periods_by_series = Dict{String, Vector{String}}()
    for key in FW.DYNAMIC_HISTORY_KEYS
        observation_count = size(initial_conditions[key], 1)
        periods_by_series[key] = quarter_string.(
            first_ordinal:(first_ordinal + observation_count - 1),
        )
    end
    qualified = qualify_base_origin_inputs(
        parameters,
        initial_conditions,
        periods_by_series;
        model_variant = "base",
        model_constructor_id = "BeforeIT.Model",
        class_h_used = false,
    )
    @test qualified.integer_word_size_bits == 64
    @test qualified.parameters["T_prime"] == 117
    @test length(qualified.parameters) == 60
    @test length(qualified.static) == 17
    @test length(qualified.dynamic) == 5
    @test all(
        length(periods) == 117
            for periods in values(qualified.dynamic_periods)
    )
    @test all(
        last(periods) == "2026Q1"
            for periods in values(qualified.dynamic_periods)
    )
    @test !haskey(qualified.parameters, "T_max")
    @test !haskey(qualified.static, "Y_EA_series")
    @test occursin(
        r"^[0-9a-f]{64}$",
        qualified.qualified_input_sha256,
    )
    @test validate_qualified_inputs(qualified) === qualified
end

@testset "exact source projection and retained-history firewall" begin
    fixture = fixture_inputs()
    qualified = qualify(fixture)
    @test validate_qualified_inputs(qualified) === qualified
    @test qualified.model_variant == "base"
    @test qualified.model_constructor_id == "BeforeIT.Model"
    @test qualified.origin_period == "2026Q1"
    @test qualified.integer_word_size_bits == 64
    @test Set(keys(qualified.parameters)) ==
        Set(FW.MODEL_PARAMETER_KEYS)
    @test Set(keys(qualified.static)) == Set(FW.STATIC_STATE_KEYS)
    @test Set(keys(qualified.dynamic)) == Set(FW.DYNAMIC_HISTORY_KEYS)
    @test Set(keys(qualified.dynamic_periods)) ==
        Set(FW.DYNAMIC_HISTORY_KEYS)
    @test qualified.excluded_source_parameter_members ==
        collect(FW.EXCLUDED_PARAMETER_KEYS)
    @test qualified.excluded_source_initial_condition_members ==
        collect(FW.EXCLUDED_INITIAL_CONDITION_KEYS)
    @test !haskey(qualified.parameters, "T")
    @test !haskey(qualified.parameters, "T_max")
    @test !haskey(qualified.parameters, "S")
    @test !haskey(qualified.parameters, "use_growth_rate_ar1")
    @test !haskey(qualified.static, "Y_EA_series")
    @test !haskey(
        qualified.static,
        "basic_price_intermediate_controls_s",
    )
    @test qualified.parameters["T_prime"] == 5
    for key in FW.DYNAMIC_HISTORY_KEYS
        @test qualified.dynamic_periods[key] == fixture.periods[1:5]
        @test last(qualified.dynamic_periods[key]) == "2026Q1"
        @test size(qualified.dynamic[key], 1) == 5
    end
    for key in FW.COLUMN_HISTORY_KEYS
        @test size(qualified.dynamic[key]) == (5, 1)
    end
    for key in ("Y", "pi")
        @test size(qualified.dynamic[key]) == (5,)
    end
    @test qualified.dynamic["C_G"] ==
        reshape(collect(101.0:105.0), :, 1)
    @test qualified.dynamic["C_E"] ==
        reshape(collect(201.0:205.0), :, 1)
    @test qualified.dynamic["Y_I"] ==
        reshape(collect(301.0:305.0), :, 1)
    @test qualified.dynamic["Y"] == collect(401.0:405.0)
    @test qualified.dynamic["pi"] == collect(0.01:0.01:0.05)
    @test Set(keys(qualified.partition_sha256)) ==
        Set(["parameters", "dynamic", "static"])
    @test all(
        digest -> occursin(r"^[0-9a-f]{64}$", digest),
        values(qualified.partition_sha256),
    )
    @test occursin(
        r"^[0-9a-f]{64}$",
        qualified.qualified_input_sha256,
    )

    reassembled = reassemble_model_inputs(qualified)
    @test Set(keys(reassembled.parameters)) == Set(FW.MODEL_PARAMETER_KEYS)
    @test Set(keys(reassembled.initial_conditions)) ==
        union(Set(FW.STATIC_STATE_KEYS), Set(FW.DYNAMIC_HISTORY_KEYS))
    @test !haskey(reassembled.parameters, "T")
    @test !haskey(reassembled.parameters, "T_max")
    @test !haskey(
        reassembled.initial_conditions,
        "basic_price_fixed_capital_control",
    )
    @test reassembled.periods_by_series == qualified.dynamic_periods
    @test reassembled.model_variant == "base"
    @test reassembled.model_constructor_id == "BeforeIT.Model"
    @test reassembled.integer_word_size_bits == 64

    reordered = (
        parameters = Dict(reverse(collect(pairs(fixture.parameters)))),
        initial_conditions =
            Dict(reverse(collect(pairs(fixture.initial_conditions)))),
        periods_by_series =
            Dict(reverse(collect(pairs(fixture.periods_by_series)))),
        periods = copy(fixture.periods),
    )
    reordered_qualified = qualify(reordered)
    @test reordered_qualified.qualified_input_sha256 ==
        qualified.qualified_input_sha256
    @test reordered_qualified.partition_sha256 ==
        qualified.partition_sha256

    for key in FW.DYNAMIC_HISTORY_KEYS
        changed = deepcopy(fixture)
        if key in FW.COLUMN_HISTORY_KEYS
            changed.initial_conditions[key][end, 1] += 999.0
        else
            changed.initial_conditions[key][end] += 999.0
        end
        future_changed = qualify(changed)
        @test future_changed.qualified_input_sha256 ==
            qualified.qualified_input_sha256
        @test future_changed.partition_sha256 ==
            qualified.partition_sha256

        changed = deepcopy(fixture)
        if key in FW.COLUMN_HISTORY_KEYS
            changed.initial_conditions[key][2, 1] += 1.0
        else
            changed.initial_conditions[key][2] += 1.0
        end
        retained_changed = qualify(changed)
        @test retained_changed.qualified_input_sha256 !=
            qualified.qualified_input_sha256
        @test retained_changed.partition_sha256["dynamic"] !=
            qualified.partition_sha256["dynamic"]
    end

    padded = deepcopy(fixture)
    padded.initial_conditions["C_G"] =
        Matrix{Any}(padded.initial_conditions["C_G"])
    padded.initial_conditions["C_G"][end, 1] = missing
    padded.initial_conditions["C_E"] =
        Matrix{Any}(padded.initial_conditions["C_E"])
    padded.initial_conditions["C_E"][end, 1] = nothing
    padded.initial_conditions["Y_I"][end, 1] = NaN
    padded.initial_conditions["Y"] =
        Any[padded.initial_conditions["Y"]...]
    padded.initial_conditions["Y"][end] = missing
    padded.initial_conditions["pi"] =
        Any[padded.initial_conditions["pi"]...]
    padded.initial_conditions["pi"][end] = nothing
    padded_qualified = qualify(padded)
    @test padded_qualified.qualified_input_sha256 ==
        qualified.qualified_input_sha256
    @test padded_qualified.partition_sha256 ==
        qualified.partition_sha256

    excluded_mutations = Function[
        value -> value.parameters["T"] = 5,
        value -> value.parameters["T_max"] = 2,
        value ->
        value.parameters["use_commodity_balance_inventory"] = false,
        value -> value.parameters["use_product_tax_netting"] = false,
        value -> value.initial_conditions[
            "basic_price_fixed_capital_control",
        ] += 1.0,
        value -> value.initial_conditions[
            "basic_price_intermediate_controls_s",
        ][1] += 1.0,
        value -> value.initial_conditions["Y_EA_series"][1] += 1.0,
        value -> value.initial_conditions["pi_EA_series"][1] += 1.0,
        value -> value.initial_conditions["r_bar_series"][1] += 1.0,
    ]
    reference_plan = seed_plan(qualified)
    for mutate in excluded_mutations
        changed = deepcopy(fixture)
        mutate(changed)
        projected = qualify(changed)
        @test projected.qualified_input_sha256 ==
            qualified.qualified_input_sha256
        @test projected.partition_sha256 == qualified.partition_sha256
        changed_plan = seed_plan(projected)
        @test getfield.(changed_plan, :construction_seed) ==
            getfield.(reference_plan, :construction_seed)
        @test getfield.(changed_plan, :simulation_seed) ==
            getfield.(reference_plan, :simulation_seed)
    end

    structural_changed = deepcopy(fixture)
    structural_changed.parameters["alpha_G"] += 1.0
    changed_structural = qualify(structural_changed)
    @test changed_structural.partition_sha256["parameters"] !=
        qualified.partition_sha256["parameters"]
    @test changed_structural.qualified_input_sha256 !=
        qualified.qualified_input_sha256
    state_changed = deepcopy(fixture)
    state_changed.initial_conditions["D_H"] += 1.0
    changed_state = qualify(state_changed)
    @test changed_state.partition_sha256["static"] !=
        qualified.partition_sha256["static"]
    @test changed_state.qualified_input_sha256 !=
        qualified.qualified_input_sha256

    mutated = deepcopy(qualified)
    mutated.dynamic["Y"][1] += 1.0
    @test_throws ABMOriginFirewallV2Error validate_qualified_inputs(mutated)
    mutated = deepcopy(qualified)
    mutated.static["D_H"] += 1.0
    @test_throws ABMOriginFirewallV2Error validate_qualified_inputs(mutated)
    mutated = deepcopy(qualified)
    mutated.parameters["alpha_G"] += 1.0
    @test_throws ABMOriginFirewallV2Error validate_qualified_inputs(mutated)
    mutated = deepcopy(qualified)
    pop!(mutated.excluded_source_parameter_members)
    @test_throws ABMOriginFirewallV2Error validate_qualified_inputs(mutated)
end

@testset "source-envelope and axis fail-closed cases" begin
    fixture = fixture_inputs()
    duplicate_parameters = merge(
        deepcopy(fixture),
        (
            parameters = duplicate_normalized_key_dictionary(
                fixture.parameters,
                "H_act",
            ),
        ),
    )
    @test_throws ABMOriginFirewallV2Error qualify(duplicate_parameters)
    duplicate_initial_conditions = merge(
        deepcopy(fixture),
        (
            initial_conditions = duplicate_normalized_key_dictionary(
                fixture.initial_conditions,
                "D_H",
            ),
        ),
    )
    @test_throws ABMOriginFirewallV2Error qualify(
        duplicate_initial_conditions,
    )
    duplicate_periods = merge(
        deepcopy(fixture),
        (
            periods_by_series = duplicate_normalized_key_dictionary(
                fixture.periods_by_series,
                "Y",
            ),
        ),
    )
    @test_throws ABMOriginFirewallV2Error qualify(duplicate_periods)
    qualified_for_key_tests = qualify(fixture)
    qualified_collision_cases = (
        (
            qualified_for_key_tests.parameters,
            FW.MODEL_PARAMETER_KEYS,
            "H_act",
        ),
        (
            qualified_for_key_tests.static,
            FW.STATIC_STATE_KEYS,
            "D_H",
        ),
        (
            qualified_for_key_tests.dynamic,
            FW.DYNAMIC_HISTORY_KEYS,
            "Y",
        ),
        (
            qualified_for_key_tests.dynamic_periods,
            FW.DYNAMIC_HISTORY_KEYS,
            "Y",
        ),
    )
    for (
            dictionary,
            expected,
            duplicate_key,
        ) in qualified_collision_cases
        collision = duplicate_normalized_key_dictionary(
            dictionary,
            duplicate_key,
        )
        @test_throws ABMOriginFirewallV2Error FW.expect_exact_keys(
            collision,
            expected,
            "qualified collision probe",
        )
        @test_throws ABMOriginFirewallV2Error FW.canonical(collision)
    end
    one_key_collision = duplicate_normalized_key_dictionary(
        Dict("Y" => 1.0),
        "Y",
    )
    @test length(one_key_collision) == 2
    @test Set(String.(keys(one_key_collision))) == Set(["Y"])
    @test_throws ABMOriginFirewallV2Error FW.expect_exact_keys(
        one_key_collision,
        ("Y",),
        "one-key normalized collision probe",
    )
    @test_throws ABMOriginFirewallV2Error FW.canonical(
        one_key_collision,
    )

    @test_throws ABMOriginFirewallV2Error FW.canonical(
        ZeroBasedVector(copy(fixture.periods)),
    )
    @test_throws ABMOriginFirewallV2Error FW.validate_periods(
        ZeroBasedVector(copy(fixture.periods)),
        "zero-based period probe",
    )

    offset_parameter = deepcopy(fixture)
    offset_parameter.parameters["I_s"] = ZeroBasedVector(
        copy(offset_parameter.parameters["I_s"]),
    )
    @test_throws ABMOriginFirewallV2Error qualify(offset_parameter)

    for key in ("N_s", "S_s")
        offset_static = deepcopy(fixture)
        offset_static.initial_conditions[key] = ZeroBasedVector(
            copy(offset_static.initial_conditions[key]),
        )
        @test_throws ABMOriginFirewallV2Error qualify(offset_static)
    end

    offset_dynamic = deepcopy(fixture)
    offset_Y = copy(offset_dynamic.initial_conditions["Y"])
    offset_Y[6] = 9.87654321e12
    offset_dynamic.initial_conditions["Y"] =
        ZeroBasedVector(offset_Y)
    @test_throws ABMOriginFirewallV2Error qualify(offset_dynamic)

    offset_column_dynamic = deepcopy(fixture)
    offset_C_G =
        copy(offset_column_dynamic.initial_conditions["C_G"])
    offset_C_G[6, 1] = 9.87654321e12
    offset_column_dynamic.initial_conditions["C_G"] =
        ZeroBasedMatrix(offset_C_G)
    @test_throws ABMOriginFirewallV2Error qualify(
        offset_column_dynamic,
    )

    offset_period_map = Dict{String, Any}(
        key => copy(value) for
            (key, value) in fixture.periods_by_series
    )
    offset_period_map["Y"] = ZeroBasedVector(
        copy(fixture.periods_by_series["Y"]),
    )
    offset_period_fixture = merge(
        deepcopy(fixture),
        (periods_by_series = offset_period_map,),
    )
    @test_throws ABMOriginFirewallV2Error qualify(
        offset_period_fixture,
    )

    qualified_with_offsets = qualify(fixture)
    qualified_with_offsets.parameters["I_s"] = ZeroBasedVector(
        copy(qualified_with_offsets.parameters["I_s"]),
    )
    @test_throws ABMOriginFirewallV2Error validate_qualified_inputs(
        qualified_with_offsets,
    )
    qualified_with_offsets = qualify(fixture)
    qualified_with_offsets.static["N_s"] = ZeroBasedVector(
        copy(qualified_with_offsets.static["N_s"]),
    )
    @test_throws ABMOriginFirewallV2Error validate_qualified_inputs(
        qualified_with_offsets,
    )
    qualified_with_offsets = qualify(fixture)
    qualified_Y = copy(qualified_with_offsets.dynamic["Y"])
    qualified_Y[end] = 9.87654321e12
    qualified_with_offsets.dynamic["Y"] =
        ZeroBasedVector(qualified_Y)
    @test_throws ABMOriginFirewallV2Error validate_qualified_inputs(
        qualified_with_offsets,
    )
    qualified_with_offsets = qualify(fixture)
    qualified_with_offsets.parameters["C"] = ZeroBasedMatrix(
        copy(qualified_with_offsets.parameters["C"]),
    )
    @test_throws ABMOriginFirewallV2Error validate_qualified_inputs(
        qualified_with_offsets,
    )
    @test_throws UndefKeywordError qualify_base_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series,
    )
    @test_throws ABMOriginFirewallV2Error qualify_base_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        model_variant = "canvas",
        model_constructor_id = "BeforeIT.Model",
        class_h_used = false,
    )
    @test_throws ABMOriginFirewallV2Error qualify_base_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        model_variant = "base",
        model_constructor_id = "BeforeIT.ModelGR",
        class_h_used = false,
    )
    @test_throws ABMOriginFirewallV2Error qualify_base_origin_inputs(
        fixture.parameters,
        fixture.initial_conditions,
        fixture.periods_by_series;
        model_variant = "base",
        model_constructor_id = "BeforeIT.Model",
        class_h_used = true,
    )

    for key in ("T", "T_max", "S", "alpha_G")
        changed = deepcopy(fixture)
        pop!(changed.parameters, key)
        @test_throws ABMOriginFirewallV2Error qualify(changed)
    end
    unknown_parameter = deepcopy(fixture)
    unknown_parameter.parameters["future_panel_length"] = 12
    @test_throws ABMOriginFirewallV2Error qualify(unknown_parameter)
    nonstring_dictionary =
        Dict{Any, Any}(deepcopy(fixture.parameters))
    nonstring_dictionary[1] = 2
    nonstring_parameter =
        merge(deepcopy(fixture), (parameters = nonstring_dictionary,))
    @test_throws ABMOriginFirewallV2Error qualify(nonstring_parameter)

    for key in ("D_H", "C_G", "Y_EA_series")
        changed = deepcopy(fixture)
        pop!(changed.initial_conditions, key)
        @test_throws ABMOriginFirewallV2Error qualify(changed)
    end
    unknown_initial = deepcopy(fixture)
    unknown_initial.initial_conditions["unclassified_time_array"] =
        collect(1.0:8.0)
    @test_throws ABMOriginFirewallV2Error qualify(unknown_initial)
    opening_controls = deepcopy(fixture)
    opening_controls.initial_conditions["use_opening_macro_controls"] = true
    @test_throws ABMOriginFirewallV2Error qualify(opening_controls)

    invalid_parameter_mutations = Function[
        value -> value.parameters["T"] = true,
        value -> value.parameters["T"] = 3,
        value -> value.parameters["T_max"] = true,
        value -> value.parameters["T_max"] = -1,
        value -> value.parameters["T_max"] = 5,
        value -> value.parameters["S"] = 3,
        value -> value.parameters["use_growth_rate_ar1"] = true,
        value -> value.parameters["use_product_tax_netting"] = 1,
        value -> value.parameters["use_commodity_balance_inventory"] = 1,
        value -> value.parameters["T_prime"] = true,
        value -> value.parameters["T_prime"] = 5.0,
        value -> value.parameters["G"] = true,
        value -> value.parameters["H_act"] = 20.5,
        value -> value.parameters["alpha_G"] = NaN,
        value -> value.parameters["I_s"][1] = 1.5,
        value -> value.parameters["C"] = ones(2, 2),
        value -> value.parameters["a_sg"] = ones(2, 3),
        value -> value.parameters["beta_s"] = ones(2),
        value -> value.parameters["alpha_s"] = ones(3),
    ]
    for mutate in invalid_parameter_mutations
        changed = deepcopy(fixture)
        mutate(changed)
        @test_throws ABMOriginFirewallV2Error qualify(changed)
    end
    for key in FW.INTEGER_LIKE_PARAMETER_KEYS
        for invalid in (true, 1.0e20, -1.0e20)
            changed = deepcopy(fixture)
            changed.parameters[key] = invalid
            @test_throws ABMOriginFirewallV2Error qualify(changed)
        end
    end
    for invalid in (true, 1.0e20, -1.0e20)
        changed = deepcopy(fixture)
        changed.parameters["I_s"] = Any[invalid, 3.0]
        @test_throws ABMOriginFirewallV2Error qualify(changed)
    end
    exact_float_integer = big(2)^53
    exact_near_int_max = big(typemax(Int)) - 1023
    inexact_float_integer = exact_float_integer + 1
    integer_bound_failures = (
        inexact_float_integer,
        big(typemax(Int)),
        big(typemax(Int)) + 1,
        big(typemin(Int)),
        big(typemin(Int)) - 1,
    )
    for key in FW.INTEGER_LIKE_PARAMETER_KEYS
        for valid in (exact_float_integer, exact_near_int_max)
            changed = deepcopy(fixture)
            changed.parameters[key] = valid
            projected = qualify(changed)
            @test Int(projected.parameters[key]) == Int(valid)
        end
        for invalid in integer_bound_failures
            changed = deepcopy(fixture)
            changed.parameters[key] = invalid
            @test_throws ABMOriginFirewallV2Error qualify(changed)
        end
    end
    for valid in (exact_float_integer, exact_near_int_max)
        changed = deepcopy(fixture)
        changed.parameters["I_s"] = Any[valid, 3.0]
        projected = qualify(changed)
        @test Int(projected.parameters["I_s"][1]) == Int(valid)
    end
    for invalid in integer_bound_failures
        changed = deepcopy(fixture)
        changed.parameters["I_s"] = Any[invalid, 3.0]
        @test_throws ABMOriginFirewallV2Error qualify(changed)
    end

    invalid_initial_mutations = Function[
        value -> value.initial_conditions["N_s"] = [1.0],
        value -> value.initial_conditions["N_s"][1] = 1.5,
        value -> value.initial_conditions["S_s"] = [1.0],
        value -> value.initial_conditions["S_s"][1] = -1.0,
        value ->
        value.initial_conditions["basic_price_intermediate_controls_s"] =
            [1.0],
        value -> value.initial_conditions["Y_EA_series"] = ones(4),
        value -> value.initial_conditions["D_H"] = missing,
        value -> value.initial_conditions["D_I"] = true,
        value -> value.initial_conditions["C_G"] = ones(8, 2),
        value -> value.initial_conditions["C_E"] = ones(1, 8),
        value -> value.initial_conditions["Y"] = ones(8, 1),
        value -> value.initial_conditions["C_G"][2, 1] = NaN,
        value -> value.initial_conditions["Y"][2] = Inf,
        value -> value.initial_conditions["Y_I"][2, 1] = 0.0,
    ]
    for mutate in invalid_initial_mutations
        changed = deepcopy(fixture)
        mutate(changed)
        @test_throws ABMOriginFirewallV2Error qualify(changed)
    end
    for invalid in (true, 1.0e20, -1.0e20)
        changed = deepcopy(fixture)
        changed.initial_conditions["N_s"] = Any[invalid, 20.0]
        @test_throws ABMOriginFirewallV2Error qualify(changed)
    end
    for valid in (exact_float_integer, exact_near_int_max)
        changed = deepcopy(fixture)
        changed.initial_conditions["N_s"] = Any[valid, 20.0]
        projected = qualify(changed)
        @test Int(projected.static["N_s"][1]) == Int(valid)
    end
    for invalid in integer_bound_failures
        changed = deepcopy(fixture)
        changed.initial_conditions["N_s"] = Any[invalid, 20.0]
        @test_throws ABMOriginFirewallV2Error qualify(changed)
    end

    missing_period = deepcopy(fixture)
    pop!(missing_period.periods_by_series, "Y")
    @test_throws ABMOriginFirewallV2Error qualify(missing_period)
    extra_period = deepcopy(fixture)
    extra_period.periods_by_series["Y_EA_series"] =
        copy(extra_period.periods)
    @test_throws ABMOriginFirewallV2Error qualify(extra_period)
    gap = deepcopy(fixture)
    gap.periods_by_series["Y"][3] = "2025Q4"
    @test_throws ABMOriginFirewallV2Error qualify(gap)
    duplicate = deepcopy(fixture)
    duplicate.periods_by_series["Y"][4] = "2025Q3"
    @test_throws ABMOriginFirewallV2Error qualify(duplicate)
    invalid_label = deepcopy(fixture)
    invalid_label.periods_by_series["Y"][1] = "2025-Q1"
    @test_throws ABMOriginFirewallV2Error qualify(invalid_label)
    no_origin = deepcopy(fixture)
    no_origin.periods_by_series["Y"] =
        ["2024Q4", "2025Q1", "2025Q2", "2025Q3", "2025Q4", "2026Q2", "2026Q3", "2026Q4"]
    @test_throws ABMOriginFirewallV2Error qualify(no_origin)
    wrong_origin_index = deepcopy(fixture)
    wrong_origin_index.periods_by_series["Y"] =
        fixture.periods[2:end]
    wrong_origin_index.initial_conditions["Y"] =
        wrong_origin_index.initial_conditions["Y"][2:end]
    @test_throws ABMOriginFirewallV2Error qualify(wrong_origin_index)
    length_mismatch = deepcopy(fixture)
    pop!(length_mismatch.initial_conditions["pi"])
    @test_throws ABMOriginFirewallV2Error qualify(length_mismatch)
    t_prime_mismatch = deepcopy(fixture)
    t_prime_mismatch.parameters["T_prime"] = 4
    @test_throws ABMOriginFirewallV2Error qualify(t_prime_mismatch)
end

@testset "qualified-input-bound deterministic seed plan" begin
    fixture = fixture_inputs()
    qualified = qualify(fixture)
    plan = seed_plan(qualified)
    reversed_plan = derive_base_path_seed_plan(
        20260807,
        qualified;
        experiment_id = "us-abm-firewall-v2",
        model_id = "beforeit-us-abm-base",
        path_ids = reverse(collect(1:32)),
    )
    @test length(plan) == 32
    @test getfield.(plan, :path_id) == collect(1:32)
    @test getfield.(plan, :construction_seed) ==
        getfield.(reversed_plan, :construction_seed)
    @test getfield.(plan, :simulation_seed) ==
        getfield.(reversed_plan, :simulation_seed)
    @test all(
        record ->
        record.origin_manifest_sha256 ==
            qualified.qualified_input_sha256,
        plan,
    )
    @test length(unique(getfield.(plan, :construction_seed))) == 32
    @test length(unique(getfield.(plan, :simulation_seed))) == 32
    @test length(
        unique(getfield.(plan, :construction_seed_key_sha256)),
    ) == 32
    @test length(
        unique(getfield.(plan, :simulation_seed_key_sha256)),
    ) == 32
    @test length(
        unique(
            vcat(
                getfield.(plan, :construction_seed_key_sha256),
                getfield.(plan, :simulation_seed_key_sha256),
            ),
        ),
    ) == 64
    @test length(
        unique(
            vcat(
                getfield.(plan, :construction_seed),
                getfield.(plan, :simulation_seed),
            ),
        ),
    ) == 64
    @test all(
        record ->
        record.construction_seed_key_sha256 !=
            record.simulation_seed_key_sha256,
        plan,
    )
    @test occursin(
        r"^[0-9a-f]{64}$",
        path_seed_plan_sha256(plan, qualified),
    )
    @test path_seed_plan_sha256(plan, qualified) ==
        path_seed_plan_sha256(reversed_plan, qualified)

    consumed = deepcopy(fixture)
    consumed.initial_conditions["Y"][1] += 1.0
    consumed_qualified = qualify(consumed)
    consumed_plan = seed_plan(consumed_qualified)
    @test getfield.(consumed_plan, :construction_seed) !=
        getfield.(plan, :construction_seed)
    @test getfield.(consumed_plan, :simulation_seed) !=
        getfield.(plan, :simulation_seed)

    excluded = deepcopy(fixture)
    excluded.parameters["T_max"] = 2
    excluded.initial_conditions[
        "commodity_balance_residual_s",
    ][1] += 99.0
    excluded_qualified = qualify(excluded)
    excluded_plan = seed_plan(excluded_qualified)
    @test getfield.(excluded_plan, :construction_seed) ==
        getfield.(plan, :construction_seed)
    @test getfield.(excluded_plan, :simulation_seed) ==
        getfield.(plan, :simulation_seed)

    @test_throws ABMOriginFirewallV2Error derive_base_path_seed_plan(
        true,
        qualified;
        experiment_id = "us-abm-firewall-v2",
        model_id = "beforeit-us-abm-base",
    )
    @test_throws ABMOriginFirewallV2Error derive_base_path_seed_plan(
        -1,
        qualified;
        experiment_id = "us-abm-firewall-v2",
        model_id = "beforeit-us-abm-base",
    )
    @test_throws ABMOriginFirewallV2Error derive_base_path_seed_plan(
        1,
        qualified;
        experiment_id = "bad id",
        model_id = "beforeit-us-abm-base",
    )
    @test_throws ABMOriginFirewallV2Error derive_base_path_seed_plan(
        1,
        qualified;
        experiment_id = "us-abm-firewall-v2",
        model_id = "beforeit-us-abm-base",
        path_ids = collect(1:31),
    )
    @test_throws ABMOriginFirewallV2Error derive_base_path_seed_plan(
        1,
        qualified;
        experiment_id = "us-abm-firewall-v2",
        model_id = "beforeit-us-abm-base",
        path_ids = Any[collect(1:31); true],
    )

    key_collision = copy(plan)
    collision_record = key_collision[1]
    key_collision[1] = BasePathSeedRecord(
        collision_record.master_seed,
        collision_record.experiment_id,
        collision_record.origin_manifest_sha256,
        collision_record.model_id,
        collision_record.path_id,
        collision_record.construction_seed,
        collision_record.construction_seed_key_sha256,
        collision_record.simulation_seed,
        collision_record.construction_seed_key_sha256,
    )
    @test_throws ABMOriginFirewallV2Error path_seed_plan_sha256(
        key_collision,
        qualified,
    )

    numeric_collision = copy(plan)
    collision_record = numeric_collision[1]
    numeric_collision[1] = BasePathSeedRecord(
        collision_record.master_seed,
        collision_record.experiment_id,
        collision_record.origin_manifest_sha256,
        collision_record.model_id,
        collision_record.path_id,
        collision_record.construction_seed,
        collision_record.construction_seed_key_sha256,
        collision_record.construction_seed,
        collision_record.simulation_seed_key_sha256,
    )
    @test_throws ABMOriginFirewallV2Error path_seed_plan_sha256(
        numeric_collision,
        qualified,
    )

    forged = copy(plan)
    record = forged[1]
    forged[1] = BasePathSeedRecord(
        record.master_seed,
        record.experiment_id,
        record.origin_manifest_sha256,
        record.model_id,
        record.path_id,
        record.construction_seed + 1,
        record.construction_seed_key_sha256,
        record.simulation_seed,
        record.simulation_seed_key_sha256,
    )
    @test_throws ABMOriginFirewallV2Error path_seed_plan_sha256(
        forged,
        qualified,
    )
end

@testset "prohibited execution and empirical actions" begin
    for action in (
            :construct_model,
            :step_model,
            :run_model,
            :emit_forecast,
            :truth_access,
            :score,
            :inference,
            :origin_admission,
            :promotion,
            :production_registry,
            :class_h,
        )
        @test_throws ABMOriginFirewallV2Error refuse_prohibited_action(
            action,
        )
    end
    @test_throws ABMOriginFirewallV2Error refuse_prohibited_action(
        :unknown,
    )
end
