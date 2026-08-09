using SHA
using Test
using TOML
using LinearAlgebra
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
)

include("USRevisedDataABMConstructorGateV3.jl")
using .USRevisedDataABMConstructorGateV3

const Gate = USRevisedDataABMConstructorGateV3
const PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_constructor_gate_v3.toml",
)
const STRICT_LOAD_PATH =
    get(ENV, "JULIA_LOAD_PATH", nothing) ==
    Gate.JULIA_LOAD_PATH_ENV &&
    Base.LOAD_PATH == Gate.SYMBOLIC_LOAD_PATH &&
    Base.load_path() == [Gate.SCRIPTS_PROJECT_PATH, Sys.STDLIB]
const CANONICAL_RUNTIME =
    Gate.ENV.current_execution_envelope() ==
    Gate.ENV.CANONICAL_EXECUTION_ENVELOPE &&
    STRICT_LOAD_PATH &&
    Base.active_project() isa AbstractString &&
    realpath(Base.active_project()) ==
    realpath(Gate.SCRIPTS_PROJECT_PATH)

function preflight_fixture()
    parameters = Dict{String, Any}(
        "G" => 2,
        "H_act" => 20.0,
        "H_inact" => 4.0,
        "I_s" => [2.0, 3.0],
        "J" => 1.0,
        "L" => 1.0,
    )
    initial_conditions = Dict{String, Any}(
        "N_s" => [4.0, 5.0],
    )
    return (; parameters, initial_conditions)
end

function fingerprint_digest(fingerprints)
    rows = [
        "$(path_id):$(fingerprints[path_id])" for
            path_id in eachindex(fingerprints)
    ]
    return bytes2hex(SHA.sha256(codeunits(join(rows, "\n"))))
end

struct FiniteFixture
    scalar::Float64
    vector::Vector{Float64}
    reference::Base.RefValue{Int}
end

@testset "v3 frozen protocol and fail-closed declarations" begin
    @test THIRD_PARTY_PRE_INCLUDE == (
        json = false,
        jld2 = false,
        beforeit = false,
        v2 = false,
    )
    @test validate_third_party_bootstrap_unloaded()
    @test !Gate.json_loaded()
    @test !Gate.beforeit_loaded()
    @test !Gate.jld2_loaded()
    @test !Gate.v2_loaded()
    protocol = validate_protocol()
    @test protocol.sha256 == protocol_sha256()
    @test protocol.sha256 ==
        bytes2hex(SHA.sha256(read(PROTOCOL_PATH)))
    document = protocol.document
    @test document["schema_version"] ==
        "beforeit-us-revised-data-abm-constructor-gate.v3"
    @test document["model_variant"] == "base"
    @test document["model_constructor_id"] == "BeforeIT.Model"
    @test document["path_count"] == 32
    @test document["deterministic_replay_count"] == 1
    @test document["artifact_sha256"] == Gate.ARTIFACT_SHA256
    @test document["v2_protocol_sha256"] ==
        Gate.V2_PROTOCOL_SHA256
    @test document["v2_qualified_input_sha256"] ==
        Gate.V2_QUALIFIED_INPUT_SHA256
    @test document["v2_seed_plan_sha256"] ==
        Gate.V2_SEED_PLAN_SHA256
    @test document["construction_seeds"] ==
        Gate.CONSTRUCTION_SEEDS
    @test length(unique(document["construction_seeds"])) == 32
    @test document["manifest_entry_count"] == 127
    @test document["dependency_source_count"] == 82
    @test document["manifest_path_dependency_count"] == 1
    @test document["package_entrypoint_count"] == 83
    @test document["package_entrypoint_digest"] ==
        Gate.PACKAGE_ENTRYPOINT_DIGEST
    @test document["julia_load_path_env"] == "@:@stdlib"
    @test document["symbolic_load_path"] == ["@", "@stdlib"]
    @test document["expanded_load_path_roles"] ==
        ["active_project", "julia_stdlib"]
    @test document["default_rng_type"] == "Random.TaskLocalRNG"
    @test document["dependency_manifest_digest"] ==
        Gate.DEPENDENCY_MANIFEST_DIGEST
    @test document["execution_envelope"] ==
        Gate.ENV.CANONICAL_EXECUTION_ENVELOPE
    @test document["constructor_preflight"]["sector_firm_floor"] ==
        "N_s[g]>=I_s[g]"
    @test document["constructor_preflight"]["worker_capacity_rule"] ==
        "H_act-sum(I_s)-1>=sum(N_s)"
    @test document["attestation_limits"]["binary_artifacts_attested"] ===
        false
    @test document["attestation_limits"]["effective_depot_path_enumerated"] ===
        true
    @test document["attestation_limits"]["artifact_overrides_required_absent"] ===
        true
    @test document["attestation_limits"]["effective_load_path_attested"] ===
        true
    @test document["attestation_limits"]["package_entrypoints_preresolved"] ===
        true
    @test document["attestation_limits"]["depot_contents_attested"] ===
        false
    @test document["attestation_limits"]["global_preferences_attested"] ===
        false
    for key in (
            "binary_jll_payloads_attested",
            "compiled_caches_attested",
            "julia_executable_bytes_attested",
            "sysimage_bytes_attested",
            "same_user_filesystem_race_resistance_attested",
        )
        @test document["attestation_limits"][key] === false
    end
    for key in (
            "diagnostic_only",
            "runner_implemented",
            "model_constructed",
            "period_axis_integrity_bound_to_artifact",
            "v2_raw_requalification_performed",
            "constructor_domain_admissibility_validated",
            "runtime_numeric_types_validated",
            "repository_source_closure_validated",
            "manifest_source_trees_validated",
            "effective_load_path_attested",
            "package_entrypoints_preresolved",
            "effective_depot_path_enumerated",
            "artifact_overrides_absent",
            "ephemeral_jld2_snapshot_written",
        )
        @test document["declarations"][key] === true
    end
    for key in (
            "model_stepped",
            "forecast_emitted",
            "forecast_serialized",
            "truth_accessed",
            "score_computed",
            "inference_run",
            "origin_admissible",
            "promotion_eligible",
            "production_registry_allowed",
            "class_h_allowed",
            "input_lineage_verified",
            "source_period_labels_authenticated",
            "zero_filesystem_writes_claimed",
            "binary_artifacts_attested",
            "binary_jll_payloads_attested",
            "compiled_caches_attested",
            "depot_contents_attested",
            "global_preferences_attested",
            "julia_executable_bytes_attested",
            "sysimage_bytes_attested",
            "same_user_filesystem_race_resistance_attested",
            "full_runtime_attestation",
            "empirical_evidence_produced",
        )
        @test document["declarations"][key] === false
    end
    @test Set(document["prohibited_actions"]) ==
        String.(Gate.PROHIBITED_ACTIONS) |> Set
    @test length(document["pinned_files"]) == 9
    @test length(document["method_origins"]) == 18
    @test all(
        pin -> occursin(r"^[0-9a-f]{64}$", pin["sha256"]),
        document["pinned_files"],
    )

    mutation = deepcopy(document)
    mutation["path_count"] = 31
    @test_throws Gate.ABMConstructorGateV3Error begin
        Gate.validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["declarations"]["score_computed"] = true
    @test_throws Gate.ABMConstructorGateV3Error begin
        Gate.validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["construction_seeds"][1] += 1
    @test_throws Gate.ABMConstructorGateV3Error begin
        Gate.validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    push!(mutation["method_origins"], deepcopy(first(mutation["method_origins"])))
    @test_throws Gate.ABMConstructorGateV3Error begin
        Gate.validate_protocol_semantics(mutation)
    end
    mutation = deepcopy(document)
    mutation["attestation_limits"]["binary_artifacts_attested"] = true
    @test_throws Gate.ABMConstructorGateV3Error begin
        Gate.validate_protocol_semantics(mutation)
    end
end

@testset "v3 exact execution environment and fresh-process boundary" begin
    protocol = validate_protocol()
    exact_environment = Dict(
        "JULIA_LOAD_PATH" => Gate.JULIA_LOAD_PATH_ENV,
    )
    exact_symbolic = copy(Gate.SYMBOLIC_LOAD_PATH)
    exact_expanded = [Gate.SCRIPTS_PROJECT_PATH, Sys.STDLIB]
    injected_load_path = validate_load_path_environment(
        protocol.document;
        environment = exact_environment,
        symbolic = exact_symbolic,
        expanded = exact_expanded,
    )
    @test injected_load_path.symbolic == exact_symbolic
    @test injected_load_path.expanded == exact_expanded
    @test occursin(
        r"^[0-9a-f]{64}$",
        injected_load_path.symbolic_sha256,
    )
    @test occursin(
        r"^[0-9a-f]{64}$",
        injected_load_path.expanded_sha256,
    )
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_load_path_environment(
            protocol.document;
            environment = Dict(
                "JULIA_LOAD_PATH" => "@:@v#.#:@stdlib",
            ),
            symbolic = ["@", "@v#.#", "@stdlib"],
            expanded = exact_expanded,
        )
    end
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_load_path_environment(
            protocol.document;
            environment = exact_environment,
            symbolic = ["@", "@v#.#", "@stdlib"],
            expanded = exact_expanded,
        )
    end
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_load_path_environment(
            protocol.document;
            environment = exact_environment,
            symbolic = exact_symbolic,
            expanded = [
                Gate.SCRIPTS_PROJECT_PATH,
                dirname(Gate.SCRIPTS_PROJECT_PATH),
                Sys.STDLIB,
            ],
        )
    end
    @test validate_beforeit_unloaded(false)
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_beforeit_unloaded(true)
    end
    @test realpath(Base.active_project()) ==
        realpath(Gate.SCRIPTS_PROJECT_PATH)
    if CANONICAL_RUNTIME
        digest = validate_execution_environment(protocol.document)
        @test occursin(r"^[0-9a-f]{64}$", digest)
        @test Base.JLOptions().startupfile == 2
        @test Base.JLOptions().check_bounds == 0
        @test Threads.nthreads() == 1
        @test LinearAlgebra.BLAS.get_num_threads() == 1
    else
        @test_throws Gate.ABMConstructorGateV3Error begin
            validate_execution_environment(protocol.document)
        end
        @test !Gate.beforeit_loaded()
        @test !Gate.jld2_loaded()
    end
    @test validate_rng_runtime() == "Random.TaskLocalRNG"
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_rng_runtime("Random.MersenneTwister")
    end
    @test validate_execution_environment(
        protocol.document;
        active_project = Gate.SCRIPTS_PROJECT_PATH,
        runtime_envelope =
            Gate.ENV.CANONICAL_EXECUTION_ENVELOPE,
        environment = exact_environment,
        symbolic_load_path = exact_symbolic,
        expanded_load_path = exact_expanded,
    ) isa String
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_execution_environment(
            protocol.document;
            active_project = tempname(),
            runtime_envelope =
                Gate.ENV.CANONICAL_EXECUTION_ENVELOPE,
            environment = exact_environment,
            symbolic_load_path = exact_symbolic,
            expanded_load_path = exact_expanded,
        )
    end
    altered = deepcopy(Gate.ENV.CANONICAL_EXECUTION_ENVELOPE)
    altered["julia_thread_count"] = 2
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_execution_environment(
            protocol.document;
            active_project = Gate.SCRIPTS_PROJECT_PATH,
            runtime_envelope = altered,
            environment = exact_environment,
            symbolic_load_path = exact_symbolic,
            expanded_load_path = exact_expanded,
        )
    end
    altered = deepcopy(Gate.ENV.CANONICAL_EXECUTION_ENVELOPE)
    altered["bounds_check_mode"] = "yes"
    altered["bounds_check_code"] = 1
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_execution_environment(
            protocol.document;
            active_project = Gate.SCRIPTS_PROJECT_PATH,
            runtime_envelope = altered,
            environment = exact_environment,
            symbolic_load_path = exact_symbolic,
            expanded_load_path = exact_expanded,
        )
    end
end

@testset "v3 benign pre-resolved package load boundary" begin
    protocol = validate_protocol()
    source_attestation = Gate.DependencySourceAttestation(
        protocol.document["manifest_entry_count"],
        protocol.document["manifest_path_dependency_count"],
        protocol.document["dependency_source_count"],
        protocol.document["dependency_manifest_digest"],
        protocol.document["dependency_manifest_digest"],
        true,
        false,
        false,
        false,
    )
    entrypoints = validate_package_entrypoint_resolutions(
        protocol.document,
        source_attestation,
    )
    @test entrypoints.package_entrypoint_count == 83
    @test entrypoints.expected_digest ==
        Gate.PACKAGE_ENTRYPOINT_DIGEST
    @test entrypoints.actual_digest ==
        Gate.PACKAGE_ENTRYPOINT_DIGEST
    @test entrypoints.all_entrypoints_match
    @test !Gate.json_loaded()
    @test !Gate.jld2_loaded()
    @test !Gate.beforeit_loaded()
    @test !Gate.v2_loaded()

    for package_id in (Gate.JSON_PKGID, Gate.JLD2_PKGID)
        loader_invoked = Ref(false)
        @test_throws Gate.ABMConstructorGateV3Error begin
            require_preresolved_package(
                package_id,
                source_attestation,
                entrypoints;
                locate_package = _ -> Gate.SCRIPTS_PROJECT_PATH,
                loader = _ -> begin
                    loader_invoked[] = true
                    nothing
                end,
            )
        end
        @test !loader_invoked[]
        @test !Gate.json_loaded()
        @test !Gate.jld2_loaded()
        @test !Gate.beforeit_loaded()
        @test !Gate.v2_loaded()
    end

    for package_id in (Gate.JSON_PKGID, Gate.JLD2_PKGID)
        loader_invoked = Ref(false)
        loaded_id = require_preresolved_package(
            package_id,
            source_attestation,
            entrypoints;
            loader = candidate -> begin
                loader_invoked[] = true
                candidate
            end,
        )
        @test loader_invoked[]
        @test loaded_id == package_id
        @test !Gate.json_loaded()
        @test !Gate.jld2_loaded()
        @test !Gate.beforeit_loaded()
        @test !Gate.v2_loaded()
    end
end

@testset "v3 depot artifact-override firewall" begin
    actual = validate_artifact_overrides_absent()
    @test actual.path_count == length(Base.DEPOT_PATH)
    @test actual.paths == Base.DEPOT_PATH
    @test actual.artifact_overrides_absent
    @test occursin(r"^[0-9a-f]{64}$", actual.paths_sha256)
    mktempdir(Gate.REPOSITORY_ROOT) do directory
        clean = validate_artifact_overrides_absent([directory])
        @test clean.path_count == 1
        @test clean.artifact_overrides_absent
        artifacts = joinpath(directory, "artifacts")
        mkpath(artifacts)
        override = joinpath(artifacts, "Overrides.toml")
        write(override, "")
        @test_throws Gate.ABMConstructorGateV3Error begin
            validate_artifact_overrides_absent([directory])
        end
        rm(override)
        @test_throws Gate.ABMConstructorGateV3Error begin
            validate_artifact_overrides_absent(
                [directory, directory],
            )
        end
        @test_throws Gate.ABMConstructorGateV3Error begin
            validate_artifact_overrides_absent(["relative/depot"])
        end
        rm(artifacts; recursive = true)
        target = mktempdir(Gate.REPOSITORY_ROOT)
        try
            symlink(target, artifacts)
            @test_throws Gate.ABMConstructorGateV3Error begin
                validate_artifact_overrides_absent([directory])
            end
        finally
            islink(artifacts) && rm(artifacts)
            isdir(target) && rm(target; recursive = true)
        end
    end
end

@testset "v3 pinned snapshots and TOCTOU adversaries" begin
    mktempdir() do directory
        path = joinpath(directory, "input.bin")
        write(path, "frozen")
        digest = bytes2hex(SHA.sha256(read(path)))
        first_snapshot = read_pinned_snapshot(
            "input.bin",
            digest;
            repository_root = directory,
        )
        second_snapshot = read_pinned_snapshot(
            "input.bin",
            digest;
            repository_root = directory,
        )
        @test validate_snapshot_unchanged(
            first_snapshot,
            second_snapshot,
        )
        write(path, "changed")
        changed_digest = bytes2hex(SHA.sha256(read(path)))
        changed_snapshot = read_pinned_snapshot(
            "input.bin",
            changed_digest;
            repository_root = directory,
        )
        @test_throws Gate.ABMConstructorGateV3Error begin
            validate_snapshot_unchanged(
                first_snapshot,
                changed_snapshot,
            )
        end
        @test_throws Gate.ABMConstructorGateV3Error begin
            read_pinned_snapshot(
                "input.bin",
                digest;
                repository_root = directory,
            )
        end
        symlink(path, joinpath(directory, "linked.bin"))
        @test_throws Gate.ABMConstructorGateV3Error begin
            read_pinned_snapshot(
                "linked.bin",
                changed_digest;
                repository_root = directory,
            )
        end
        hardlink = joinpath(directory, "hardlinked.bin")
        @test ccall(
            :link,
            Cint,
            (Cstring, Cstring),
            path,
            hardlink,
        ) == 0
        @test_throws Gate.ABMConstructorGateV3Error begin
            read_pinned_snapshot(
                "input.bin",
                changed_digest;
                repository_root = directory,
            )
        end
        rm(hardlink)
        @test_throws Gate.ABMConstructorGateV3Error begin
            read_pinned_snapshot(
                "../escape.bin",
                changed_digest;
                repository_root = directory,
            )
        end
    end
end

@testset "v3 checked constructor-domain preflight" begin
    fixture = preflight_fixture()
    counts = preflight_constructor_domain(
        fixture.parameters,
        fixture.initial_conditions,
    )
    @test counts.sector_count == 2
    @test counts.active_population == 20
    @test counts.inactive_workers == 4
    @test counts.government_entities == 1
    @test counts.foreign_consumers == 1
    @test counts.firm_count == 5
    @test counts.active_worker_count == 14
    @test counts.employed_worker_count == 9
    @test counts.unemployed_worker_count == 5
    @test counts.sector_firm_counts == [2, 3]
    @test counts.sector_employment_counts == [4, 5]

    bad = deepcopy(fixture)
    bad.initial_conditions["N_s"][1] = 1.0
    @test_throws Gate.ABMConstructorGateV3Error begin
        preflight_constructor_domain(
            bad.parameters,
            bad.initial_conditions,
        )
    end
    bad = deepcopy(fixture)
    bad.parameters["H_act"] = 14.0
    @test_throws Gate.ABMConstructorGateV3Error begin
        preflight_constructor_domain(
            bad.parameters,
            bad.initial_conditions,
        )
    end
    bad = deepcopy(fixture)
    bad.parameters["H_act"] = 20.5
    @test_throws Gate.ABMConstructorGateV3Error begin
        preflight_constructor_domain(
            bad.parameters,
            bad.initial_conditions,
        )
    end
    bad = deepcopy(fixture)
    bad.parameters["H_act"] = true
    @test_throws Gate.ABMConstructorGateV3Error begin
        preflight_constructor_domain(
            bad.parameters,
            bad.initial_conditions,
        )
    end
    bad = deepcopy(fixture)
    bad.parameters["I_s"][1] = 0.0
    @test_throws Gate.ABMConstructorGateV3Error begin
        preflight_constructor_domain(
            bad.parameters,
            bad.initial_conditions,
        )
    end
    bad = deepcopy(fixture)
    bad.parameters["H_act"] = BigInt(2)^53 + 1
    @test_throws Gate.ABMConstructorGateV3Error begin
        preflight_constructor_domain(
            bad.parameters,
            bad.initial_conditions,
        )
    end
    bad = deepcopy(fixture)
    bad.parameters["G"] = 2
    bad.parameters["I_s"] = [typemax(Int), 1]
    bad.initial_conditions["N_s"] = [typemax(Int), 1]
    bad.parameters["H_act"] = typemax(Int)
    @test_throws Gate.ABMConstructorGateV3Error begin
        preflight_constructor_domain(
            bad.parameters,
            bad.initial_conditions,
        )
    end
    bad = deepcopy(fixture)
    bad.initial_conditions["N_s"][2] = Inf
    @test_throws Gate.ABMConstructorGateV3Error begin
        preflight_constructor_domain(
            bad.parameters,
            bad.initial_conditions,
        )
    end
end

@testset "v3 seed adjacency, state finiteness, and fingerprints" begin
    constructor(parameters, initial_conditions) = (
        draw = rand(8),
        parameter_count = length(parameters),
        initial_count = length(initial_conditions),
    )
    parameters = Dict{String, Any}("x" => 1)
    initial_conditions = Dict{String, Any}("y" => 2)
    first_state = construct_with_seed(
        constructor,
        123,
        parameters,
        initial_conditions,
    )
    second_state = construct_with_seed(
        constructor,
        123,
        parameters,
        initial_conditions,
    )
    third_state = construct_with_seed(
        constructor,
        124,
        parameters,
        initial_conditions,
    )
    @test first_state == second_state
    @test first_state != third_state
    source = read(
        joinpath(
            @__DIR__,
            "USRevisedDataABMConstructorGateV3.jl",
        ),
        String,
    )
    @test occursin(
        r"Random\.seed!\(seed\)\s+return Base\.invokelatest",
        source,
    )

    finite = FiniteFixture(1.0, [2.0, 3.0], Ref(4))
    @test validate_numeric_finiteness(finite) == 4
    @test full_state_sha256(finite) ==
        full_state_sha256(deepcopy(finite))
    changed = FiniteFixture(1.0, [2.0, 4.0], Ref(4))
    @test full_state_sha256(finite) != full_state_sha256(changed)
    @test full_state_sha256(Float32[1]) !=
        full_state_sha256(Float64[1])
    @test full_state_sha256(Int32[1]) !=
        full_state_sha256(Int64[1])
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_numeric_finiteness(
            FiniteFixture(NaN, [2.0, 3.0], Ref(4)),
        )
    end
    @test_throws Gate.ABMConstructorGateV3Error begin
        full_state_sha256(
            FiniteFixture(1.0, [2.0, Inf], Ref(4)),
        )
    end

    fingerprints = [
        bytes2hex(SHA.sha256(codeunits("path-$path_id"))) for
            path_id in 1:32
    ]
    digest = fingerprint_digest(fingerprints)
    @test validate_stochastic_fingerprints(
        fingerprints,
        first(fingerprints),
        digest,
    ) == digest
    duplicates = copy(fingerprints)
    duplicates[2] = duplicates[1]
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_stochastic_fingerprints(
            duplicates,
            first(duplicates),
            fingerprint_digest(duplicates),
        )
    end
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_stochastic_fingerprints(
            fingerprints,
            fingerprints[2],
            digest,
        )
    end
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_stochastic_fingerprints(
            fingerprints,
            first(fingerprints),
            repeat("0", 64),
        )
    end
end

@testset "v3 method-origin and prohibited-action adversaries" begin
    records = [
        Gate.MethodOriginRecord(id, path, "BeforeIT") for
            (id, path) in Gate.METHOD_ORIGIN_PATHS
    ]
    @test validate_method_origin_records(records) === records
    changed = copy(records)
    first_record = first(changed)
    changed[1] = Gate.MethodOriginRecord(
        first_record.id,
        "src/other.jl",
        first_record.defining_module,
    )
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_method_origin_records(changed)
    end
    changed = copy(records)
    first_record = first(changed)
    changed[1] = Gate.MethodOriginRecord(
        first_record.id,
        first_record.relative_path,
        "Main",
    )
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_method_origin_records(changed)
    end
    @test_throws Gate.ABMConstructorGateV3Error begin
        validate_method_origin_records(records[1:(end - 1)])
    end
    for action in Gate.PROHIBITED_ACTIONS
        @test_throws Gate.ABMConstructorGateV3Error begin
            refuse_prohibited_action(action)
        end
    end
    @test_throws Gate.ABMConstructorGateV3Error begin
        refuse_prohibited_action(:construct_model)
    end
    @test_throws Gate.ABMConstructorGateV3Error begin
        refuse_prohibited_action(:unknown)
    end
end

@testset "installed v3 constructor-only qualification" begin
    @test !Gate.json_loaded()
    @test !Gate.beforeit_loaded()
    @test !Gate.jld2_loaded()
    @test !Gate.v2_loaded()
    if !CANONICAL_RUNTIME
        @test_throws Gate.ABMConstructorGateV3Error begin
            run_installed_constructor_gate()
        end
        @test !Gate.json_loaded()
        @test !Gate.beforeit_loaded()
        @test !Gate.jld2_loaded()
        @test !Gate.v2_loaded()
    else
        result = run_installed_constructor_gate()
        @test Gate.json_loaded()
        @test Gate.beforeit_loaded()
        @test Gate.jld2_loaded()
        @test Gate.v2_loaded()
        @test result.schema_version ==
            "beforeit-us-revised-data-abm-constructor-gate.v3"
        @test result.protocol_sha256 == protocol_sha256()
        @test result.artifact_sha256 == Gate.ARTIFACT_SHA256
        @test result.v2_protocol_sha256 == Gate.V2_PROTOCOL_SHA256
        @test result.qualified_input_sha256 ==
            Gate.V2_QUALIFIED_INPUT_SHA256
        @test result.qualified_partition_sha256 == Dict(
            "parameters" => Gate.V2_PARAMETER_SHA256,
            "static" => Gate.V2_STATIC_SHA256,
            "dynamic" => Gate.V2_DYNAMIC_SHA256,
        )
        @test result.construction_seed_plan_sha256 ==
            Gate.V2_SEED_PLAN_SHA256
        @test result.dependency_source_tree_count == 82
        @test result.dependency_source_tree_digest ==
            Gate.DEPENDENCY_MANIFEST_DIGEST
        @test result.package_entrypoint_count == 83
        @test result.package_entrypoint_digest ==
            Gate.PACKAGE_ENTRYPOINT_DIGEST
        @test result.symbolic_load_path_sha256 ==
            Gate.semantic_sha256(Gate.SYMBOLIC_LOAD_PATH)
        @test result.expanded_load_path_sha256 ==
            Gate.semantic_sha256(
                [Gate.SCRIPTS_PROJECT_PATH, Sys.STDLIB],
            )
        @test result.depot_path_count == length(Base.DEPOT_PATH)
        @test occursin(r"^[0-9a-f]{64}$", result.depot_paths_sha256)
        @test result.artifact_overrides_absent
        @test result.path_count == 32
        @test result.default_rng_type == "Random.TaskLocalRNG"
        @test result.deterministic_replay_count == 1
        @test result.model_construction_count == 33
        @test result.counts.sector_count == 68
        @test result.counts.firm_count == 130
        @test result.counts.active_worker_count == 1695
        @test result.counts.employed_worker_count == 1627
        @test result.counts.unemployed_worker_count == 68
        @test length(result.path_state_sha256) == 32
        @test length(unique(result.path_state_sha256)) == 32
        @test all(
            fingerprint -> occursin(r"^[0-9a-f]{64}$", fingerprint),
            result.path_state_sha256,
        )
        @test result.path_fingerprint_set_sha256 ==
            Gate.EXPECTED_PATH_FINGERPRINT_SET_SHA256
        @test result.replay_state_sha256 ==
            first(result.path_state_sha256)
        @test result.deterministic_replay_equal
        @test result.distinct_stochastic_paths
        @test result.input_hashes_unchanged
        @test result.source_snapshots_unchanged
        @test result.model_constructed
        @test result.diagnostic_only
        for field in (
                :model_stepped,
                :forecast_emitted,
                :forecast_serialized,
                :truth_accessed,
                :score_computed,
                :inference_run,
                :origin_admissible,
                :promotion_eligible,
                :binary_artifacts_attested,
                :depot_contents_attested,
                :global_preferences_attested,
                :full_runtime_attestation,
            )
            @test getfield(result, field) === false
        end
        @test occursin(r"^[0-9a-f]{64}$", result.method_origin_digest)
        @test occursin(
            r"^[0-9a-f]{64}$",
            result.execution_envelope_sha256,
        )
        @test occursin(r"^[0-9a-f]{64}$", result.result_sha256)
        if get(
                ENV,
                "ABM_CONSTRUCTOR_GATE_V3_REPORT",
                "",
            ) == "1"
            println("v3_protocol_sha256=", result.protocol_sha256)
            println("v3_result_sha256=", result.result_sha256)
            println(
                "v3_execution_envelope_sha256=",
                result.execution_envelope_sha256,
            )
            println(
                "v3_method_origin_sha256=",
                result.method_origin_digest,
            )
            println(
                "v3_dependency_source_sha256=",
                result.dependency_source_tree_digest,
            )
            println(
                "v3_package_entrypoint_sha256=",
                result.package_entrypoint_digest,
            )
            println(
                "v3_symbolic_load_path_sha256=",
                result.symbolic_load_path_sha256,
            )
            println(
                "v3_expanded_load_path_sha256=",
                result.expanded_load_path_sha256,
            )
            println(
                "v3_depot_path_sha256=",
                result.depot_paths_sha256,
            )
            println(
                "v3_path_fingerprint_set_sha256=",
                result.path_fingerprint_set_sha256,
            )
            println(
                "v3_replay_state_sha256=",
                result.replay_state_sha256,
            )
            println(
                "v3_numeric_values_per_path=",
                result.numeric_values_checked_per_path,
            )
        end
    end
end
