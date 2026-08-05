using Test
using BeforeITWeb

function valid_test_provenance()
    return Dict{String, Any}(
        "schema_version" => "run-provenance.v1",
        "digest_algorithm" => "sha256",
        "canonicalization" => "test",
        "producer_source_digest" => "sha256:producer",
        "model_source_digest" => "sha256:model",
        "trace_source_digest" => "sha256:trace",
        "dataset_digest" => "sha256:dataset",
        "calibration_digest" => "sha256:calibration",
        "initialization_contract_digest" => "sha256:contract",
        "initial_state_digest" => "sha256:state",
        "rng_policy" => Dict("name" => "implicit-default-rng"),
        "execution_environment" => Dict{String, Any}(
            "julia_version" => string(VERSION),
            "thread_count" => max(Threads.nthreads(), 1),
            "architecture" => string(Sys.ARCH),
            "kernel" => string(Sys.KERNEL),
            "word_size" => Sys.WORD_SIZE,
        ),
    )
end

provenance_wrapper(provenance) =
    Dict{String, Any}("provenance" => provenance)

function provenance_check(checks, name)
    index = findfirst(check -> check["name"] == name, checks)
    index === nothing && error("Missing provenance check $name")
    return checks[index]
end

@testset "Execution environment provenance fails closed" begin
    valid = valid_test_provenance()
    checks = BeforeITWeb._experiment_provenance_checks(
        provenance_wrapper(deepcopy(valid)),
        provenance_wrapper(deepcopy(valid)),
        provenance_wrapper(deepcopy(valid)),
        provenance_wrapper(deepcopy(valid)),
    )
    @test provenance_check(
        checks,
        "provenance_required_fields",
    )["passed"] === true
    @test provenance_check(
        checks,
        "provenance_pair_identity",
    )["passed"] === true

    for field in (
            "julia_version",
            "thread_count",
            "architecture",
            "kernel",
            "word_size",
        )
        incomplete = deepcopy(valid)
        delete!(incomplete["execution_environment"], field)
        incomplete_checks = BeforeITWeb._experiment_provenance_checks(
            provenance_wrapper(deepcopy(incomplete)),
            provenance_wrapper(deepcopy(incomplete)),
            provenance_wrapper(deepcopy(valid)),
            provenance_wrapper(deepcopy(valid)),
        )
        presence = provenance_check(
            incomplete_checks,
            "provenance_required_fields",
        )
        @test presence["passed"] === false
        @test "execution_environment.$field" in
            presence["evidence"]["sources"]["run_a_spec"]["missing_fields"]
    end

    invalid_values = Dict{String, Any}(
        "julia_version" => "not a Julia version",
        "thread_count" => 0,
        "architecture" => " ",
        "kernel" => "",
        "word_size" => 48,
    )
    for (field, value) in invalid_values
        invalid = deepcopy(valid)
        invalid["execution_environment"][field] = value
        invalid_checks = BeforeITWeb._experiment_provenance_checks(
            provenance_wrapper(deepcopy(invalid)),
            provenance_wrapper(deepcopy(invalid)),
            provenance_wrapper(deepcopy(valid)),
            provenance_wrapper(deepcopy(valid)),
        )
        presence = provenance_check(
            invalid_checks,
            "provenance_required_fields",
        )
        @test presence["passed"] === false
        @test "execution_environment.$field" in
            presence["evidence"]["sources"]["run_a_manifest"]["invalid_fields"]
    end

    different_environment = deepcopy(valid)
    different_environment["execution_environment"]["thread_count"] =
        valid["execution_environment"]["thread_count"] + 1
    mismatched_checks = BeforeITWeb._experiment_provenance_checks(
        provenance_wrapper(deepcopy(valid)),
        provenance_wrapper(deepcopy(valid)),
        provenance_wrapper(deepcopy(different_environment)),
        provenance_wrapper(deepcopy(different_environment)),
    )
    @test provenance_check(
        mismatched_checks,
        "provenance_required_fields",
    )["passed"] === true
    @test provenance_check(
        mismatched_checks,
        "provenance_spec_manifest_identity",
    )["passed"] === true
    @test provenance_check(
        mismatched_checks,
        "provenance_pair_identity",
    )["passed"] === false
end

@testset "Clone submission preserves source lineage and trace" begin
    node = Sys.which("node")
    if node === nothing
        @test_skip "Node.js is unavailable"
    else
        app_path =
            normpath(joinpath(@__DIR__, "..", "public", "app.js"))
        script = raw"""
        const assert = require("node:assert/strict");
        const app = require(process.argv[1]);
        const trace = {
          profile: "standard",
          realization_indices: [3],
          phase_detail: "none",
          checkpoints: false,
        };
        const spec = {
          run_id: "source-run",
          parent_run_id: "older-parent",
          trace,
        };
        const inherited = app.cloneInheritanceFromRunSpec(
          spec,
          { run_id: "directory-fallback" },
        );
        assert.equal(inherited.parentRunId, "source-run");
        assert.notEqual(inherited.parentRunId, spec.parent_run_id);
        assert.deepEqual(inherited.trace, trace);
        assert.notEqual(inherited.trace, trace);
        const submission = app.cloneSubmissionFields({
          cloneParentRunId: inherited.parentRunId,
          cloneTrace: inherited.trace,
        });
        assert.equal(submission.parent_run_id, "source-run");
        assert.deepEqual(submission.trace, trace);
        inherited.trace.realization_indices.push(4);
        assert.deepEqual(spec.trace.realization_indices, [3]);
        """
        @test success(Cmd([node, "-e", script, app_path]))
    end
end
