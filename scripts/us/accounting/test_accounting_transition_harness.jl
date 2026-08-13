using CSV
using JLD2
using Random
using SHA
using Test
using TOML

import BeforeIT as Bit

include(joinpath(@__DIR__, "USAccountingTransitionHarness.jl"))
using .USAccountingTransitionHarness

const REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const CONTRACT_PATH =
    joinpath(@__DIR__, "accounting_transition_harness.toml")

file_sha256(path) = bytes2hex(SHA.sha256(read(path)))

function rewritten_record(
        record;
        origin_admissible = record.origin_admissible,
        status = record.status,
    )
    return IdentityRecord(
        record.schema_version,
        record.candidate_id,
        record.candidate_semantic_sha256,
        record.seed,
        record.requested_horizon,
        record.realized_period,
        record.realized_date,
        record.identity_id,
        record.layer,
        status,
        record.diagnostic_value,
        record.absolute_diagnostic_value,
        record.tolerance,
        record.blocker,
        record.basis,
        origin_admissible,
        record.promotion_eligible,
        record.accuracy_selection_eligible,
        record.runtime_selection_eligible,
    )
end

function rewritten_report(report, records)
    return TransitionHarnessReport(
        report.schema_version,
        report.contract_path,
        report.contract_sha256,
        report.classification,
        report.information_track,
        report.promotion_status,
        report.horizons,
        report.seeds,
        report.candidate_ids,
        report.record_semantic_sha256,
        records,
        report.runtime_source_tree_sha256,
        report.runtime_source_tree_file_count,
        report.julia_version,
        report.julia_thread_count,
        report.blas_thread_count,
        report.blas_vendor,
        report.origin_admissible,
        report.promotion_eligible,
        report.accuracy_selection_eligible,
        report.runtime_selection_eligible,
    )
end

@testset "Accounting-transition harness contract" begin
    contract = load_contract(CONTRACT_PATH; repo_root = REPO_ROOT)
    @test contract.horizons == [1, 4, 12]
    @test contract.seeds == [20261003, 20261004]
    @test getfield.(contract.candidates, :candidate_id) == [
        "nowcast_2026Q1_opening_accounting_v1",
        "structural_2024Q4_opening_accounting_v1",
    ]
    @test contract.classification ==
        "REVISED_MIXED_VINTAGE_DIAGNOSTIC"
    @test contract.promotion_status ==
        "RESEARCH_ONLY_NOT_PROMOTED"
    @test !contract.origin_admissible
    @test !contract.accuracy_selection_eligible
    @test !contract.runtime_selection_eligible
    @test !contract.runtime_parallel
    @test contract.execution_envelope ==
        USAccountingTransitionHarness.USOpeningAccountingCandidate.USJuliaExecutionEnvelope.CANONICAL_EXECUTION_ENVELOPE
    @test contract.byte_reproducibility_scope ==
        "same_frozen_local_execution_envelope_only"
    @test !contract.cross_machine_byte_determinism_claimed
    @test contract.runtime_source_tree_file_count > 0
    @test contract.runtime_source_tree_digest_algorithm ==
        "sha256(sorted_posix_relative_path + NUL + lowercase_file_sha256 + LF)"
    @test source_tree_digest(joinpath(REPO_ROOT, "src")).sha256 ==
        contract.runtime_source_tree_sha256
    payload = JLD2.load(
        joinpath(REPO_ROOT, first(contract.candidates).artifact_path),
    )
    Random.seed!(first(contract.seeds))
    model = Bit.Model(
        deepcopy(payload["parameters"]),
        deepcopy(payload["initial_conditions"]),
    )
    @test USAccountingTransitionHarness.AGENT_STATE_FIELDS ==
        fieldnames(typeof(model))
    state_hash_before =
        USAccountingTransitionHarness.state_hash(model)
    model.prop.a_sg[1] += 1.0
    @test USAccountingTransitionHarness.state_hash(model) !=
        state_hash_before
    @test Set(keys(contract.blocked_variants)) == Set(
        [
            "observed_tax_income_production_variant",
            "explicit_inventory_stock_flow_variant",
            "confidence_weighted_accounting_variant",
        ],
    )

    raw = TOML.parsefile(CONTRACT_PATH)
    mktempdir() do directory
        bad_horizons = deepcopy(raw)
        bad_horizons["horizons"] = [1, 12]
        bad_horizons_path = joinpath(directory, "bad_horizons.toml")
        open(bad_horizons_path, "w") do io
            TOML.print(io, bad_horizons; sorted = true)
        end
        @test_throws ArgumentError load_contract(
            bad_horizons_path;
            repo_root = REPO_ROOT,
        )

        bad_module_hash = deepcopy(raw)
        bad_module_hash["harness_module_sha256"] = repeat("0", 64)
        bad_module_hash_path =
            joinpath(directory, "bad_module_hash.toml")
        open(bad_module_hash_path, "w") do io
            TOML.print(io, bad_module_hash; sorted = true)
        end
        @test_throws ArgumentError load_contract(
            bad_module_hash_path;
            repo_root = REPO_ROOT,
        )

        bad_dependency_hash = deepcopy(raw)
        bad_dependency_hash[
            "candidate_supply_make_dependency_sha256",
        ] = repeat("0", 64)
        bad_dependency_hash_path =
            joinpath(directory, "bad_dependency_hash.toml")
        open(bad_dependency_hash_path, "w") do io
            TOML.print(io, bad_dependency_hash; sorted = true)
        end
        @test_throws ArgumentError load_contract(
            bad_dependency_hash_path;
            repo_root = REPO_ROOT,
        )

        bad_envelope_dependency_hash = deepcopy(raw)
        bad_envelope_dependency_hash[
            "candidate_execution_envelope_dependency_sha256",
        ] = repeat("0", 64)
        bad_envelope_dependency_hash_path =
            joinpath(directory, "bad_envelope_dependency_hash.toml")
        open(bad_envelope_dependency_hash_path, "w") do io
            TOML.print(io, bad_envelope_dependency_hash; sorted = true)
        end
        @test_throws ArgumentError load_contract(
            bad_envelope_dependency_hash_path;
            repo_root = REPO_ROOT,
        )

        bad_envelope_dependency_binding = deepcopy(raw)
        bad_envelope_dependency_binding[
            "candidate_execution_envelope_dependency_path",
        ] = raw["candidate_builder_path"]
        bad_envelope_dependency_binding[
            "candidate_execution_envelope_dependency_sha256",
        ] = raw["candidate_builder_sha256"]
        bad_envelope_dependency_binding_path =
            joinpath(directory, "bad_envelope_dependency_binding.toml")
        open(bad_envelope_dependency_binding_path, "w") do io
            TOML.print(
                io,
                bad_envelope_dependency_binding;
                sorted = true,
            )
        end
        @test_throws ArgumentError load_contract(
            bad_envelope_dependency_binding_path;
            repo_root = REPO_ROOT,
        )

        zero_tolerance = deepcopy(raw)
        zero_tolerance["model_numeric_tolerance"] = 0.0
        zero_tolerance_path =
            joinpath(directory, "zero_tolerance.toml")
        open(zero_tolerance_path, "w") do io
            TOML.print(io, zero_tolerance; sorted = true)
        end
        @test_throws ArgumentError load_contract(
            zero_tolerance_path;
            repo_root = REPO_ROOT,
        )

        unsafe = deepcopy(raw)
        unsafe["origin_admissible"] = true
        unsafe_path = joinpath(directory, "unsafe.toml")
        open(unsafe_path, "w") do io
            TOML.print(io, unsafe; sorted = true)
        end
        @test_throws ArgumentError load_contract(
            unsafe_path;
            repo_root = REPO_ROOT,
        )

        bad_envelope = deepcopy(raw)
        bad_envelope["execution_envelope"]["bounds_check_mode"] =
            "yes"
        bad_envelope_path =
            joinpath(directory, "bad_envelope.toml")
        open(bad_envelope_path, "w") do io
            TOML.print(io, bad_envelope; sorted = true)
        end
        @test_throws ArgumentError load_contract(
            bad_envelope_path;
            repo_root = REPO_ROOT,
        )

        copied_source = joinpath(directory, "src")
        cp(joinpath(REPO_ROOT, "src"), copied_source)
        copied_digest = source_tree_digest(copied_source)
        @test copied_digest.sha256 ==
            contract.runtime_source_tree_sha256
        @test copied_digest.file_count ==
            contract.runtime_source_tree_file_count
        first_source = joinpath(
            copied_source,
            first(copied_digest.relative_paths),
        )
        open(first_source, "a") do io
            println(io)
        end
        @test source_tree_digest(copied_source).sha256 !=
            contract.runtime_source_tree_sha256
    end
end

@testset "Accounting-transition identity rows" begin
    contract = load_contract(CONTRACT_PATH; repo_root = REPO_ROOT)
    canonical_envelope =
        USAccountingTransitionHarness.USOpeningAccountingCandidate.current_execution_envelope() ==
        contract.execution_envelope
    if !canonical_envelope
        captured = try
            run_harness(contract)
            nothing
        catch error
            error
        end
        @test captured isa
            USAccountingTransitionHarness.USOpeningAccountingCandidate.ExecutionEnvelopeMismatch
        if captured isa
                USAccountingTransitionHarness.USOpeningAccountingCandidate.ExecutionEnvelopeMismatch
            @test captured.expected == contract.execution_envelope
            @test captured.actual ==
                USAccountingTransitionHarness.USOpeningAccountingCandidate.current_execution_envelope()
            @test !isempty(captured.mismatches)
        end
    else
        report = run_harness(contract)
        @test validate_report(report, contract) === report
        @test report.horizons == [1, 4, 12]
        @test report.seeds == [20261003, 20261004]
        @test length(report.records) == 1_508
        @test length(
            Set(
                (
                        record.candidate_id,
                        record.seed,
                        record.requested_horizon,
                        record.realized_period,
                        record.identity_id,
                    ) for record in report.records
            ),
        ) == length(report.records)

        statuses = Dict(
            status => count(record -> record.status == status, report.records)
                for status in unique(getfield.(report.records, :status))
        )
        @test statuses == Dict(
            "PASS" => 1_232,
            "PASS_AT_SOURCE_ROUNDING" => 24,
            "FAIL_EXPECTED_LATENT_WEDGE" => 12,
            "NOT_RUN_BLOCKED" => 240,
        )

        blocked = filter(
            record -> record.status == "NOT_RUN_BLOCKED",
            report.records,
        )
        @test length(blocked) == 240
        @test all(ismissing(record.diagnostic_value) for record in blocked)
        @test Set(getfield.(blocked, :blocker)) == Set(
            [
                "OBSERVED_TAX_MAPPING_NOT_AVAILABLE",
                "EXPLICIT_INVENTORY_MAPPING_NOT_AVAILABLE",
                "CONFIDENCE_WEIGHT_MAPPING_NOT_AVAILABLE",
            ],
        )

        replay = filter(
            record -> record.identity_id == "same_seed_exact_replay",
            report.records,
        )
        prefix = filter(
            record ->
            record.identity_id == "same_seed_cross_horizon_prefix",
            report.records,
        )
        @test length(replay) == 80
        @test length(prefix) == 80
        @test all(record.diagnostic_value == 0.0 for record in replay)
        @test all(record.diagnostic_value == 0.0 for record in prefix)

        opening_observation = filter(
            record ->
            record.identity_id ==
                "opening_observation_nominal_expenditure",
            report.records,
        )
        opening_latent = filter(
            record ->
            record.identity_id ==
                "opening_latent_nominal_expenditure",
            report.records,
        )
        @test length(opening_observation) == 12
        @test length(opening_latent) == 12
        expected_observed = Dict(
            candidate.candidate_id =>
                candidate.observed_expenditure_residual
                for candidate in contract.candidates
        )
        expected_latent = Dict(
            candidate.candidate_id =>
                candidate.latent_expenditure_residual
                for candidate in contract.candidates
        )
        @test all(
            record.diagnostic_value ==
                expected_observed[record.candidate_id]
                for record in opening_observation
        )
        @test all(
            isapprox(
                    record.diagnostic_value,
                    expected_latent[record.candidate_id];
                    atol = contract.model_numeric_tolerance,
                    rtol = 0.0,
                ) for record in opening_latent
        )
        @test all(
            record.status == "FAIL_EXPECTED_LATENT_WEDGE"
                for record in opening_latent
        )

        internal_identity_ids = Set(
            [
                "nominal_income_production",
                "nominal_expenditure_transition",
                "real_expenditure",
                "central_bank_balance_sheet",
                "commercial_bank_balance_sheet",
                "nominal_inventory_flow_decomposition",
                "real_inventory_flow_decomposition",
                "final_goods_inventory_stock_flow",
                "intermediate_goods_inventory_stock_flow",
            ],
        )
        internal = filter(
            record -> record.identity_id in internal_identity_ids,
            report.records,
        )
        @test all(
            record.absolute_diagnostic_value <= record.tolerance
                for record in internal
        )
        @test all(!record.origin_admissible for record in report.records)
        @test all(!record.promotion_eligible for record in report.records)
        @test all(
            !record.accuracy_selection_eligible for record in report.records
        )
        @test all(
            !record.runtime_selection_eligible for record in report.records
        )
        @test !report.origin_admissible
        @test !report.promotion_eligible
        @test !report.accuracy_selection_eligible
        @test !report.runtime_selection_eligible
        @test report.runtime_source_tree_sha256 ==
            contract.runtime_source_tree_sha256
        @test report.runtime_source_tree_file_count ==
            contract.runtime_source_tree_file_count
        @test report.julia_version == string(VERSION)
        @test report.julia_thread_count == 1
        @test report.blas_thread_count == 1
        @test !isempty(report.blas_vendor)

        bad_records = copy(report.records)
        bad_records[1] =
            rewritten_record(bad_records[1]; origin_admissible = true)
        @test_throws ArgumentError validate_report(
            rewritten_report(report, bad_records),
            contract,
        )

        duplicate_records = copy(report.records)
        duplicate_records[end] = duplicate_records[1]
        @test_throws ArgumentError validate_report(
            rewritten_report(report, duplicate_records),
            contract,
        )

        mktempdir() do directory
            first_output = joinpath(directory, "first")
            second_output = joinpath(directory, "second")
            first_written =
                write_report(report, contract, first_output)
            second_written =
                write_report(report, contract, second_output)
            @test first_written.record_count == 1_508
            @test first_written.records_sha256 ==
                second_written.records_sha256
            @test first_written.manifest_sha256 ==
                second_written.manifest_sha256
            @test length(CSV.File(first_written.records_path)) == 1_508
            manifest = TOML.parsefile(first_written.manifest_path)
            @test manifest["record_count"] == 1_508
            @test manifest["records_csv_sha256"] ==
                file_sha256(first_written.records_path)
            @test manifest["origin_admissible"] === false
            @test manifest["promotion_eligible"] === false
            @test manifest["accuracy_selection_eligible"] === false
            @test manifest["runtime_selection_eligible"] === false
            @test manifest["runtime_source_tree_sha256"] ==
                contract.runtime_source_tree_sha256
            @test manifest["runtime_source_tree_file_count"] ==
                contract.runtime_source_tree_file_count
            @test manifest["execution_envelope"] ==
                contract.execution_envelope
            @test manifest["byte_reproducibility_scope"] ==
                contract.byte_reproducibility_scope
            @test manifest["cross_machine_byte_determinism_claimed"] ===
                false
            @test manifest["julia_version"] == string(VERSION)
            @test manifest["julia_thread_count"] == 1
            @test manifest["blas_thread_count"] == 1
            @test !isempty(manifest["blas_vendor"])
            @test manifest["thread_contract"] ==
                "single_thread_julia_and_blas"
            @test manifest["candidate_manifest_sha256"] ==
                contract.candidate_manifest_sha256
            @test manifest["candidate_builder_sha256"] ==
                contract.candidate_builder_sha256
            @test manifest[
                "candidate_execution_envelope_dependency_path",
            ] == contract.candidate_execution_envelope_dependency_path
            @test manifest[
                "candidate_execution_envelope_dependency_sha256",
            ] == contract.candidate_execution_envelope_dependency_sha256
            @test manifest["candidate_supply_make_dependency_sha256"] ==
                contract.candidate_supply_make_dependency_sha256
            @test manifest["candidate_t10105_dependency_sha256"] ==
                contract.candidate_t10105_dependency_sha256
            @test manifest["harness_module_sha256"] ==
                contract.harness_module_sha256
            @test manifest["julia_project_sha256"] ==
                contract.julia_project_sha256
            @test manifest["julia_manifest_sha256"] ==
                contract.julia_manifest_sha256
            @test Dict(
                candidate["candidate_id"] => (
                        artifact_sha256 = candidate["artifact_sha256"],
                        semantic_sha256 = candidate["semantic_sha256"],
                    ) for candidate in manifest["candidate"]
            ) == Dict(
                candidate.candidate_id => (
                        artifact_sha256 = candidate.artifact_sha256,
                        semantic_sha256 = candidate.semantic_sha256,
                    ) for candidate in contract.candidates
            )
            @test_throws ArgumentError write_report(
                report,
                contract,
                first_output,
            )
        end
    end
end
