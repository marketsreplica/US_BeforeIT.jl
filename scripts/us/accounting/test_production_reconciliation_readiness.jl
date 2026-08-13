using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USProductionReconciliationReadiness.jl"))

using .USProductionReconciliationReadiness

const READINESS_CONTRACT_PATH =
    joinpath(@__DIR__, "production_reconciliation_readiness.toml")
const READINESS_REPO_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", ".."))

function only_source(result, source_family_id)
    return only(
        source
            for source in result.source_families
            if source.source_family_id == source_family_id
    )
end

function only_criterion(result, criterion_id)
    return only(
        criterion
            for criterion in result.criteria
            if criterion.criterion_id == criterion_id
    )
end

function only_probe(result, probe_id)
    return only(
        probe
            for probe in result.probe_results
            if probe.probe_id == probe_id
    )
end

function copy_bound_tree(
        temporary_root::AbstractString,
        contract::ProductionReadinessContract,
    )
    paths = String[
        artifact.path for artifact in contract.artifacts
    ]
    append!(paths, [contract.module_path, contract.runner_path])
    for nested_contract_path in (
            "scripts/us/accounting/production_reconciliation_admission_evidence.toml",
            "scripts/us/accounting/production_reconciliation_candidate_ledger.toml",
        )
        document = TOML.parsefile(
            joinpath(READINESS_REPO_ROOT, nested_contract_path),
        )
        append!(
            paths,
            String[
                artifact["path"] for artifact in document["artifact"]
            ],
        )
        implementation = document["implementation"]
        append!(
            paths,
            String[
                implementation["module_path"],
                implementation["runner_path"],
            ],
        )
    end
    for relative_path in unique(paths)
        destination = joinpath(temporary_root, relative_path)
        mkpath(dirname(destination))
        cp(
            joinpath(READINESS_REPO_ROOT, relative_path),
            destination;
            force = true,
        )
    end
    return nothing
end

function write_changed_contract(
        directory::AbstractString,
        replacement::Pair{String, String},
    )
    source = read(READINESS_CONTRACT_PATH, String)
    changed = replace(source, replacement; count = 1)
    changed == source && error("test replacement did not change the contract")
    path = joinpath(directory, "changed_contract.toml")
    write(path, changed)
    return path
end

@testset "WS-2C production reconciliation readiness gate" begin
    contract = load_production_readiness_contract(READINESS_CONTRACT_PATH)
    result = evaluate_production_readiness(contract)
    candidate = result.candidate

    @testset "Pinned contract, implementation, and declared target" begin
        ledger_artifact = only(
            artifact
                for artifact in contract.artifacts
                if artifact.artifact_id ==
                "production_reconciliation_candidate_ledger"
        )
        ledger_document = TOML.parsefile(
            joinpath(READINESS_REPO_ROOT, ledger_artifact.path),
        )
        admission_artifact = only(
            artifact
                for artifact in contract.artifacts
                if artifact.artifact_id ==
                "production_reconciliation_admission_evidence"
        )
        admission_document = TOML.parsefile(
            joinpath(READINESS_REPO_ROOT, admission_artifact.path),
        )
        @test file_sha256(READINESS_CONTRACT_PATH) ==
            APPROVED_CONTRACT_SHA256
        @test contract.source_sha256 == APPROVED_CONTRACT_SHA256
        @test contract.schema_version == CONTRACT_SCHEMA
        @test contract.contract_id ==
            "us-ws2c-production-reconciliation-readiness-v2"
        @test contract.classification ==
            "CURRENT_VINTAGE_FAIL_CLOSED_READINESS_GATE_NOT_ORIGIN_ELIGIBLE"
        @test contract.promotion_status == "NOT_READY_NOT_PROMOTED"
        @test contract.admission_evidence_hash ==
            "admission1:824a0cf2efae13c1b55966a40dd0edef49cb50d9b0c82f63f05952baf568d0a3"
        @test result.admission_evidence_hash ==
            contract.admission_evidence_hash
        @test admission_artifact.sha256 ==
            file_sha256(
            joinpath(READINESS_REPO_ROOT, admission_artifact.path),
        )
        @test admission_document["candidate_problem_scope_hash"] ==
            ledger_document["problem_scope_hash"]
        @test length(contract.admission_blocker_mappings) == 13
        @test Set(
            mapping.admission_blocker_id
                for mapping in contract.admission_blocker_mappings
        ) == Set(String.(admission_document["promotion_blockers"]))
        @test contract.target_country == "USA"
        @test contract.target_reference_period == "CALENDAR_YEAR_2024"
        @test contract.target_frequency == "ANNUAL"
        @test contract.target_time_basis ==
            "CALENDAR_YEAR_ACCOUNTING_FLOW"
        @test contract.target_stock_flow_class == "FLOW"
        @test contract.target_currency == "USD"
        @test contract.target_unit == "MILLIONS_CURRENT_DOLLARS"
        @test contract.target_price_basis == "PRODUCERS_PRICES"
        @test contract.target_axis ==
            "BEA_AFTER_REDEFINITIONS_68_CORE_PLUS_EXPLICIT_USED_OTHER_CLOSURE"
        @test contract.solver_method_id == "CONSTRAINED_STONE_GLS"
        @test contract.solver_invocation_status == "NOT_RUN_BLOCKED"
        @test normalized_module_sha256(
            joinpath(READINESS_REPO_ROOT, contract.module_path),
        ) == contract.module_normalized_sha256
        @test file_sha256(
            joinpath(READINESS_REPO_ROOT, contract.runner_path),
        ) == contract.runner_sha256
        @test !contract.forecast_origin_admissible
        @test !contract.promotion_ready
        @test !contract.model_state_write
        @test contract.accounting_gate_effect == "NONE"
        @test contract.forecast_score_effect == "NONE"
        @test !("truth_value" in contract.production_cell_schema_fields)
        @test !("benchmark_role" in contract.production_cell_schema_fields)
        @test "canonical_source_key" in
            contract.production_cell_schema_fields
        @test "release_id" in contract.production_cell_schema_fields
        @test "stock_flow_class" in contract.production_cell_schema_fields
        @test "cell_state" in contract.production_cell_schema_fields
        @test "negative_economic_type" in
            contract.production_cell_schema_fields
        @test "structural_zero_evidence_id" in
            contract.production_cell_schema_fields
        @test length(contract.production_cell_schema_fields) == 35
        @test contract.production_cell_schema_fields ==
            String.(ledger_document["production_cell_schema_fields"])
        @test "economic_type" in contract.production_cell_schema_fields
        @test "counterpart_group_id" in
            contract.production_cell_schema_fields
        @test "problem_scope_hash" in
            contract.production_cell_schema_fields
        @test "rounding_or_measurement_model" in
            contract.production_control_schema_fields
        @test length(contract.production_control_schema_fields) == 28
        @test contract.production_control_schema_fields ==
            String.(ledger_document["production_control_schema_fields"])
        @test "rhs_state" in contract.production_control_schema_fields
        @test "canonical_control_key" in
            contract.production_control_schema_fields
        @test "lineage_hash" in contract.production_control_schema_fields
        @test ledger_artifact.sha256 ==
            file_sha256(joinpath(READINESS_REPO_ROOT, ledger_artifact.path))
        @test ledger_document["classification"] ==
            "CURRENT_VINTAGE_CANDIDATE_LEDGER_NOT_SOLVER_ADMITTED"
        @test ledger_document["solver_input_cell_count"] == 0
        @test ledger_document["solver_input_control_count"] == 0
        @test Set(contract.allowed_control_kinds) == Set(
            [
                "EXACT_ACCOUNTING_IDENTITY",
                "MEASURED_PUBLISHED_MARGIN",
                "FIXED_PUBLISHED_CONTROL_APPROVED",
            ],
        )
    end

    @testset "Authenticated evidence without solver admission" begin
        @test result.overall_status == "NOT_RUN_BLOCKED"
        @test !result.ready
        @test length(result.artifact_validations) == 11
        @test length(result.probe_results) == 117
        @test length(result.source_families) == 9
        @test length(result.blockers) == 23
        @test length(result.criteria) == 21
        @test length(result.blocking_criterion_ids) == 14
        @test length(result.blocker_ids) == 23
        @test count(
            criterion -> criterion.status == "PASS",
            result.criteria,
        ) == 7
        @test count(
            criterion -> criterion.status == "BLOCKED",
            result.criteria,
        ) == 14
        @test Set(
            criterion.criterion_id
                for criterion in result.criteria
                if criterion.status == "PASS"
        ) == Set(
            [
                "authenticated_artifact_integrity",
                "upstream_semantic_probe_consistency",
                "target_semantic_tuple_declared",
                "synthetic_stone_algebra_qualified",
                "production_problem_schema_ready",
                "production_admission_evidence_authenticated",
                "canonical_lineage_deduplicated",
            ],
        )
        @test all(
            validation.status == "PASS" &&
                validation.expected_sha256 ==
                validation.before_sha256 ==
                validation.after_sha256
                for validation in result.artifact_validations
        )
        @test all(probe.status == "PASS" for probe in result.probe_results)
        @test all(
            source.solver_cell_count == 0 &&
                source.solver_control_count == 0
                for source in result.source_families
        )
        @test all(
            !occursin(
                    r"^ADMITTED",
                    source.admission_status,
                )
                for source in result.source_families
        )
        @test candidate.status == "NOT_RUN_BLOCKED"
        @test candidate.admitted_solver_family_count == 0
        @test candidate.solver_input_cell_count == 0
        @test candidate.solver_input_control_count == 0
        @test candidate.production_reliability_class_count == 0
        @test candidate.production_covariance_class_count == 0
        @test candidate.approved_exact_control_count == 0
        @test candidate.approved_structural_zero_count == 0
        @test !candidate.solver_invoked
        @test candidate.reconciliation_run_count == 0
        @test candidate.adjustment_record_count == 0
        @test !candidate.candidate_frozen
        @test !candidate.adjustment_report_emitted
        @test !candidate.forecast_origin_admissible
        @test !candidate.promotion_ready
        @test !candidate.model_state_write
        @test candidate.accounting_gate_effect == "NONE"
        @test candidate.forecast_score_effect == "NONE"
        @test only_probe(
            result,
            "admission_negative_cell_count",
        ).observed_value == 129
        @test only_probe(
            result,
            "admission_source_mechanically_typed_negative_cell_count",
        ).observed_value == 106
        @test only_probe(
            result,
            "admission_source_unresolved_negative_cell_count",
        ).observed_value == 23
        @test only_probe(
            result,
            "admission_literature_supported_negative_cell_count",
        ).observed_value == 16
        @test only_probe(
            result,
            "admission_unresolved_negative_cell_count",
        ).observed_value == 7
        @test only_probe(
            result,
            "admission_component_unresolved_signed_cell_count",
        ).observed_value == 12
        @test only_probe(
            result,
            "admission_domestic_use_point_count",
        ).observed_value == 6_160
        @test only_probe(
            result,
            "admission_domestic_use_raw_evaluable_count",
        ).observed_value == 2_480
        @test only_probe(
            result,
            "admission_numerical_reliability_receipt_count",
        ).observed_value == 0
        @test only_probe(
            result,
            "admission_numerical_covariance_receipt_count",
        ).observed_value == 0
        @test Set(candidate.blocker_ids) == Set(result.blocker_ids)
        @test Set(candidate.required_criterion_ids) ==
            Set(criterion.criterion_id for criterion in result.criteria)
        blocked_error = try
            require_production_reconciliation_ready(result)
            nothing
        catch error
            error
        end
        @test blocked_error isa ProductionReconciliationBlockedError
        @test blocked_error.blocker_ids == sort(result.blocker_ids)
        @test occursin(
            "PRODUCTION_SOLVER_ADMISSION_NOT_APPROVED",
            sprint(showerror, blocked_error),
        )
        @test !(
            "PRODUCTION_STONE_PROBLEM_SCHEMA_NOT_IMPLEMENTED" in
                result.blocker_ids
        )
        @test !(
            "CANONICAL_SOURCE_LINEAGE_DEDUPLICATION_NOT_IMPLEMENTED" in
                result.blocker_ids
        )
    end

    @testset "Dubious and unknown boundaries remain quarantined" begin
        core = only_source(result, "bea_after_redefinitions_2024_core")
        closure = only_source(
            result,
            "bea_after_redefinitions_2024_used_other_summary",
        )
        oecd = only_source(result, "oecd_usa_2024_valuation")
        cipi = only_source(result, "bea_t10105_2024_cipi")
        holder = only_source(
            result,
            "bea_t50805b_2026q1_holder_stock",
        )
        m3 = only_source(result, "census_m3_current_inventory_stages")
        special_2017 =
            only_source(result, "bea_2017_special_account_detail")
        stone = only_source(result, "stone_synthetic_benchmark")

        @test core.target_basis_compatible
        @test core.admission_status ==
            "EVIDENCE_VALIDATED_NOT_SOLVER_ADMITTED"
        @test "IMPORT_BOUNDARY_NOT_SELECTED" in core.blocker_ids
        @test closure.target_basis_compatible
        @test "USED_OTHER_2024_COMPONENT_AND_SERVICE_BRIDGE_UNRESOLVED" in
            closure.blocker_ids
        @test !oecd.target_basis_compatible
        @test occursin("DUBIOUS", oecd.admission_status)
        @test "OECD_TO_BEA_MAPPING_AND_RESIDUALS_UNRESOLVED" in
            oecd.blocker_ids
        @test !cipi.target_basis_compatible
        @test cipi.stock_flow_class == "FLOW"
        @test cipi.frequency == "QUARTERLY"
        @test !holder.target_basis_compatible
        @test holder.stock_flow_class == "STOCK"
        @test holder.reference_period == "2026Q1"
        @test !m3.target_basis_compatible
        @test m3.frequency == "MONTHLY"
        @test m3.time_basis == "END_OF_MONTH_LEVEL"
        @test "M3_CONTROLLED_STAGE_OBSERVATION_OPERATOR_UNRESOLVED" in
            m3.blocker_ids
        @test !special_2017.target_basis_compatible
        @test special_2017.reference_period == "CALENDAR_YEAR_2017"
        @test special_2017.admission_status ==
            "SEMANTIC_ONLY_2017_TO_2024_PROJECTION_PROHIBITED"
        @test !stone.target_basis_compatible
        @test stone.evidence_role ==
            "ALGEBRAIC_METHOD_QUALIFICATION_NOT_ECONOMIC_SOURCE"
        @test "PRODUCTION_SOLVER_ADMISSION_NOT_APPROVED" in
            stone.blocker_ids

        @test only_criterion(
            result,
            "synthetic_stone_algebra_qualified",
        ).status == "PASS"
        @test only_criterion(
            result,
            "production_problem_schema_ready",
        ).status == "PASS"
        @test only_criterion(
            result,
            "production_admission_evidence_authenticated",
        ).status == "PASS"
        @test only_criterion(
            result,
            "canonical_lineage_deduplicated",
        ).status == "PASS"
        @test only_criterion(
            result,
            "cell_level_valuation_bridge",
        ).status == "BLOCKED"
        @test only_criterion(
            result,
            "used_other_closure_resolved",
        ).status == "BLOCKED"
        @test only_criterion(
            result,
            "inventory_observation_bridge_resolved",
        ).status == "BLOCKED"
        @test only_criterion(
            result,
            "production_covariance_and_dependence_ready",
        ).status == "BLOCKED"
        @test only_criterion(
            result,
            "forecast_origin_vintage_ready",
        ).status == "BLOCKED"
    end

    @testset "Strict contract and fail-closed mutation rejection" begin
        mktempdir() do temporary_directory
            unexpected = joinpath(temporary_directory, "unexpected.toml")
            write(
                unexpected,
                read(READINESS_CONTRACT_PATH),
                codeunits("\nunexpected_key = true\n"),
            )
            @test_throws ReadinessContractError load_production_readiness_contract(
                unexpected;
                verify_hash = false,
            )

            promoted = write_changed_contract(
                temporary_directory,
                "solver_invoked = false" => "solver_invoked = true",
            )
            @test_throws ReadinessContractError load_production_readiness_contract(
                promoted;
                verify_hash = false,
            )

            admitted = write_changed_contract(
                temporary_directory,
                "solver_cell_count = 0" => "solver_cell_count = 1",
            )
            @test_throws ReadinessContractError load_production_readiness_contract(
                admitted;
                verify_hash = false,
            )

            false_solver_admission = write_changed_contract(
                temporary_directory,
                "admission_status = \"EVIDENCE_VALIDATED_NOT_SOLVER_ADMITTED\"" =>
                    "admission_status = \"EVIDENCE_VALIDATED_SOLVER_ADMITTED\"",
            )
            @test_throws ReadinessContractError load_production_readiness_contract(
                false_solver_admission;
                verify_hash = false,
            )

            truth_field = write_changed_contract(
                temporary_directory,
                "\"cell_id\"," => "\"truth_value\",",
            )
            @test_throws ReadinessContractError load_production_readiness_contract(
                truth_field;
                verify_hash = false,
            )

            path_escape = write_changed_contract(
                temporary_directory,
                "path = \"scripts/us/accounting/after_redefinitions_model_core_mapping.toml\"" =>
                    "path = \"../outside.toml\"",
            )
            @test_throws ReadinessContractError load_production_readiness_contract(
                path_escape;
                verify_hash = false,
            )

            false_pass = write_changed_contract(
                temporary_directory,
                "status = \"BLOCKED\"" => "status = \"PASS\"",
            )
            @test_throws ReadinessContractError load_production_readiness_contract(
                false_pass;
                verify_hash = false,
            )

            duplicate_admission_blocker = write_changed_contract(
                temporary_directory,
                "admission_blocker_id = \"NEAREST_INTEGER_ROUNDING_RULE_NOT_SOURCE_CERTIFIED\"" =>
                    "admission_blocker_id = \"DISPLAY_RESOLUTION_ENVELOPE_IS_NOT_STATISTICAL_UNCERTAINTY\"",
            )
            @test_throws ReadinessContractError load_production_readiness_contract(
                duplicate_admission_blocker;
                verify_hash = false,
            )

            changed_evidence_hash = write_changed_contract(
                temporary_directory,
                contract.admission_evidence_hash =>
                    "admission1:6291bdc8101d9984039cd804483d6fe5962a133ecf281794ba109045877f51df",
            )
            changed_evidence_contract =
                load_production_readiness_contract(
                changed_evidence_hash;
                verify_hash = false,
            )
            @test_throws ReadinessContractError evaluate_production_readiness(
                changed_evidence_contract,
            )
            @test_throws ArtifactIntegrityError USProductionReconciliationReadiness._evaluate_production_readiness_unsealed(
                changed_evidence_contract,
            )
        end
    end

    @testset "Artifact hash, symlink, and semantic-probe attacks" begin
        mktempdir() do temporary_root
            copy_bound_tree(temporary_root, contract)
            target = joinpath(
                temporary_root,
                first(contract.artifacts).path,
            )
            write(target, read(target), codeunits("\ntampered = true\n"))
            @test_throws ArtifactIntegrityError evaluate_production_readiness(
                contract;
                repo_root = temporary_root,
            )
        end

        mktempdir() do temporary_root
            copy_bound_tree(temporary_root, contract)
            ledger_artifact = only(
                artifact
                    for artifact in contract.artifacts
                    if artifact.artifact_id ==
                    "production_reconciliation_candidate_ledger"
            )
            target = joinpath(temporary_root, ledger_artifact.path)
            write(target, read(target), codeunits("\ntampered = true\n"))
            @test_throws ArtifactIntegrityError evaluate_production_readiness(
                contract;
                repo_root = temporary_root,
            )
        end

        mktempdir() do temporary_root
            copy_bound_tree(temporary_root, contract)
            artifact = first(contract.artifacts)
            target = joinpath(temporary_root, artifact.path)
            rm(target)
            symlink(
                joinpath(READINESS_REPO_ROOT, artifact.path),
                target,
            )
            @test_throws ArtifactIntegrityError evaluate_production_readiness(
                contract;
                repo_root = temporary_root,
            )
        end

        mktempdir() do temporary_root
            copy_bound_tree(temporary_root, contract)
            admission_document = TOML.parsefile(
                joinpath(
                    temporary_root,
                    "scripts/us/accounting/production_reconciliation_admission_evidence.toml",
                ),
            )
            nested_artifact = only(
                artifact
                    for artifact in admission_document["artifact"]
                    if artifact["artifact_id"] ==
                    "negative_cell_semantics_fixture"
            )
            target = joinpath(temporary_root, nested_artifact["path"])
            write(target, read(target), codeunits("\n"))
            @test_throws ArtifactIntegrityError evaluate_production_readiness(
                contract;
                repo_root = temporary_root,
            )
        end

        mktempdir() do temporary_root
            copy_bound_tree(temporary_root, contract)
            admission_document = TOML.parsefile(
                joinpath(
                    temporary_root,
                    "scripts/us/accounting/production_reconciliation_admission_evidence.toml",
                ),
            )
            nested_artifact = only(
                artifact
                    for artifact in admission_document["artifact"]
                    if artifact["artifact_id"] ==
                    "negative_cell_semantics_fixture"
            )
            target = joinpath(temporary_root, nested_artifact["path"])
            outside_directory = mktempdir()
            outside_target = joinpath(outside_directory, basename(target))
            cp(target, outside_target)
            rm(dirname(target); recursive = true)
            symlink(outside_directory, dirname(target))
            @test_throws ArtifactIntegrityError evaluate_production_readiness(
                contract;
                repo_root = temporary_root,
            )
        end

        mktempdir() do temporary_root
            copy_bound_tree(temporary_root, contract)
            admission_document = TOML.parsefile(
                joinpath(
                    temporary_root,
                    "scripts/us/accounting/production_reconciliation_admission_evidence.toml",
                ),
            )
            target = joinpath(
                temporary_root,
                admission_document["implementation"]["module_path"],
            )
            write(target, read(target), codeunits("\n"))
            @test_throws ArtifactIntegrityError evaluate_production_readiness(
                contract;
                repo_root = temporary_root,
            )
        end

        mktempdir() do temporary_root
            copy_bound_tree(temporary_root, contract)
            artifact = only(
                item
                    for item in contract.artifacts
                    if item.artifact_id == "bea_model_core_mapping"
            )
            target = joinpath(temporary_root, artifact.path)
            changed = replace(
                read(target, String),
                "source_year = 2024" => "source_year = 2023";
                count = 1,
            )
            write(target, changed)
            changed_sha256 = file_sha256(target)
            contract_source = replace(
                read(READINESS_CONTRACT_PATH, String),
                artifact.sha256 => changed_sha256;
                count = 1,
            )
            changed_contract_path =
                joinpath(temporary_root, "changed_contract.toml")
            write(changed_contract_path, contract_source)
            changed_contract = load_production_readiness_contract(
                changed_contract_path;
                verify_hash = false,
            )
            @test_throws ReadinessContractError evaluate_production_readiness(
                changed_contract;
                repo_root = temporary_root,
            )
            @test_throws EvidenceProbeError USProductionReconciliationReadiness._evaluate_production_readiness_unsealed(
                changed_contract;
                repo_root = temporary_root,
            )
        end

        mktempdir() do temporary_root
            copy_bound_tree(temporary_root, contract)
            ledger_artifact = only(
                artifact
                    for artifact in contract.artifacts
                    if artifact.artifact_id ==
                    "production_reconciliation_candidate_ledger"
            )
            target = joinpath(temporary_root, ledger_artifact.path)
            changed = replace(
                read(target, String),
                "solver_input_cell_count = 0" =>
                    "solver_input_cell_count = 1";
                count = 1,
            )
            write(target, changed)
            changed_sha256 = file_sha256(target)
            contract_source = replace(
                read(READINESS_CONTRACT_PATH, String),
                ledger_artifact.sha256 => changed_sha256;
                count = 1,
            )
            changed_contract_path =
                joinpath(temporary_root, "changed_contract.toml")
            write(changed_contract_path, contract_source)
            changed_contract = load_production_readiness_contract(
                changed_contract_path;
                verify_hash = false,
            )
            @test_throws ReadinessContractError evaluate_production_readiness(
                changed_contract;
                repo_root = temporary_root,
            )
            @test_throws EvidenceProbeError USProductionReconciliationReadiness._evaluate_production_readiness_unsealed(
                changed_contract;
                repo_root = temporary_root,
            )
        end
    end

    @testset "Report output path is fresh and fail closed" begin
        mktempdir() do nonempty_directory
            write(joinpath(nonempty_directory, "preexisting.txt"), "occupied")
            @test_throws ReadinessContractError build_production_readiness_report(
                nonempty_directory,
            )
            @test !isfile(
                joinpath(
                    nonempty_directory,
                    "production_reconciliation_manifest.toml",
                ),
            )
        end

        mktempdir() do parent_directory
            mktempdir() do linked_directory
                output_link = joinpath(parent_directory, "linked-report")
                symlink(linked_directory, output_link)
                @test_throws ReadinessContractError build_production_readiness_report(
                    output_link,
                )
                @test isempty(readdir(linked_directory))
            end
        end
    end

    @testset "Deterministic blocked-readiness report" begin
        mktempdir() do first_directory
            mktempdir() do second_directory
                first_report =
                    build_production_readiness_report(first_directory)
                second_report =
                    build_production_readiness_report(second_directory)
                first_files = sort!(readdir(first_directory))
                second_files = sort!(readdir(second_directory))
                @test first_files == second_files
                @test first_files == [
                    "production_reconciliation_admission_overlay.csv",
                    "production_reconciliation_artifacts.csv",
                    "production_reconciliation_blockers.csv",
                    "production_reconciliation_criteria.csv",
                    "production_reconciliation_manifest.toml",
                    "production_reconciliation_probes.csv",
                    "production_reconciliation_sources.csv",
                    "production_reconciliation_status.toml",
                ]
                @test all(
                    read(joinpath(first_directory, file)) ==
                        read(joinpath(second_directory, file))
                        for file in first_files
                )
                @test first_report.artifact_sha256 ==
                    second_report.artifact_sha256
                @test first_report.probe_sha256 ==
                    second_report.probe_sha256
                @test first_report.source_sha256 ==
                    second_report.source_sha256
                @test first_report.blocker_sha256 ==
                    second_report.blocker_sha256
                @test first_report.criterion_sha256 ==
                    second_report.criterion_sha256
                @test first_report.admission_overlay_sha256 ==
                    second_report.admission_overlay_sha256
                @test first_report.status_sha256 ==
                    second_report.status_sha256
                @test first_report.manifest_sha256 ==
                    second_report.manifest_sha256

                status = TOML.parsefile(first_report.status_path)
                manifest = TOML.parsefile(first_report.manifest_path)
                @test status["schema_version"] == STATUS_SCHEMA
                @test status["overall_status"] == "NOT_RUN_BLOCKED"
                @test !status["ready"]
                @test status["artifact_count"] == 11
                @test status["probe_count"] == 117
                @test status["source_family_count"] == 9
                @test status["criterion_count"] == 21
                @test status["blocking_criterion_count"] == 14
                @test status["blocker_count"] == 23
                @test status["admission_evidence_hash"] ==
                    contract.admission_evidence_hash
                @test status["admission_promotion_blocker_count"] == 13
                @test status["admission_unresolved_negative_cell_count"] ==
                    7
                @test status["admitted_solver_family_count"] == 0
                @test status["solver_input_cell_count"] == 0
                @test status["solver_input_control_count"] == 0
                @test status["production_reliability_class_count"] == 0
                @test status["production_covariance_class_count"] == 0
                @test status["approved_exact_control_count"] == 0
                @test status["approved_structural_zero_count"] == 0
                @test !status["solver_invoked"]
                @test status["reconciliation_run_count"] == 0
                @test status["adjustment_record_count"] == 0
                @test !status["candidate_frozen"]
                @test !status["adjustment_report_emitted"]
                @test !status["forecast_origin_admissible"]
                @test !status["promotion_ready"]
                @test !status["model_state_write"]
                @test status["accounting_gate_effect"] == "NONE"
                @test status["forecast_score_effect"] == "NONE"
                @test manifest["schema_version"] ==
                    REPORT_MANIFEST_SCHEMA
                @test manifest["contract_sha256"] ==
                    APPROVED_CONTRACT_SHA256
                @test manifest["overall_status"] == "NOT_RUN_BLOCKED"
                @test !manifest["ready"]
                @test manifest["admission_evidence_hash"] ==
                    contract.admission_evidence_hash
                @test length(manifest["output"]) == 7
                @test Dict(
                    output["path"] => (
                            role = output["role"],
                            sha256 = output["sha256"],
                        )
                        for output in manifest["output"]
                ) == Dict(
                    "production_reconciliation_artifacts.csv" => (
                        role = "ARTIFACT_VALIDATION",
                        sha256 = first_report.artifact_sha256,
                    ),
                    "production_reconciliation_probes.csv" => (
                        role = "EVIDENCE_PROBES",
                        sha256 = first_report.probe_sha256,
                    ),
                    "production_reconciliation_sources.csv" => (
                        role = "SOURCE_FAMILY_REGISTRY",
                        sha256 = first_report.source_sha256,
                    ),
                    "production_reconciliation_blockers.csv" => (
                        role = "READINESS_BLOCKERS",
                        sha256 = first_report.blocker_sha256,
                    ),
                    "production_reconciliation_criteria.csv" => (
                        role = "READINESS_CRITERIA",
                        sha256 = first_report.criterion_sha256,
                    ),
                    "production_reconciliation_admission_overlay.csv" => (
                        role = "ADMISSION_OVERLAY",
                        sha256 = first_report.admission_overlay_sha256,
                    ),
                    "production_reconciliation_status.toml" => (
                        role = "CANDIDATE_STATUS",
                        sha256 = first_report.status_sha256,
                    ),
                )
                @test split(readline(first_report.source_path), ",") == [
                    "source_family_id",
                    "artifact_ids",
                    "source_namespace",
                    "evidence_role",
                    "country",
                    "reference_period",
                    "frequency",
                    "time_basis",
                    "stock_flow_class",
                    "currency",
                    "unit",
                    "price_basis",
                    "valuation_basis",
                    "row_axis",
                    "column_axis",
                    "vintage_status",
                    "release_identity",
                    "cell_state_policy",
                    "target_basis_compatible",
                    "lineage_group",
                    "admission_status",
                    "solver_cell_count",
                    "solver_control_count",
                    "blocker_ids",
                    "literature_ids",
                ]
                @test split(readline(first_report.blocker_path), ",") == [
                    "blocker_id",
                    "status",
                    "required_for",
                    "source_family_ids",
                    "blocking_fact",
                    "required_evidence",
                    "resolution_test",
                    "evidence_probe_ids",
                    "literature_ids",
                ]
                @test countlines(first_report.artifact_path) == 12
                @test countlines(first_report.probe_path) == 118
                @test countlines(first_report.source_path) == 10
                @test countlines(first_report.blocker_path) == 24
                @test countlines(first_report.criterion_path) == 22
                @test countlines(first_report.admission_overlay_path) == 14
                @test !any(
                    occursin("adjustment", lowercase(file)) &&
                        file != "production_reconciliation_status.toml"
                        for file in first_files
                )
            end
        end
    end
end
