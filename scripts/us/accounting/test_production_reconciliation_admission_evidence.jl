using CSV
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsValuationEnvelope.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsFinalUseEnvelope.jl"))
include(
    joinpath(
        @__DIR__,
        "USAfterRedefinitionsProducerPriceAdapterCandidate.jl",
    ),
)
include(joinpath(@__DIR__, "USProductionReconciliationLedger.jl"))
include(joinpath(@__DIR__, "USProductionReconciliationAdmissionEvidence.jl"))

using .USProductionReconciliationAdmissionEvidence

const ADMISSION_CONTRACT_PATH =
    joinpath(@__DIR__, "production_reconciliation_admission_evidence.toml")
const ADMISSION_MODULE_PATH =
    joinpath(@__DIR__, "USProductionReconciliationAdmissionEvidence.jl")
const ADMISSION_REPO_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", ".."))

function replace_struct_field(value, field::Symbol, replacement)
    type = typeof(value)
    fields = fieldnames(type)
    field in fields || error("unknown field $field for $type")
    values = ntuple(
        index ->
        fields[index] == field ?
            replacement :
            getfield(value, fields[index]),
        fieldcount(type),
    )
    return type(values...)
end

function copy_admission_bound_tree(temporary_root, contract)
    relative_paths = String[
        artifact.relative_path for artifact in values(contract.artifacts)
    ]
    append!(
        relative_paths,
        [contract.module_path, contract.runner_path],
    )
    for relative_path in unique(relative_paths)
        destination = joinpath(temporary_root, relative_path)
        mkpath(dirname(destination))
        cp(
            joinpath(ADMISSION_REPO_ROOT, relative_path),
            destination;
            force = true,
        )
    end
    contract_destination =
        joinpath(temporary_root, relpath(ADMISSION_CONTRACT_PATH, ADMISSION_REPO_ROOT))
    mkpath(dirname(contract_destination))
    cp(ADMISSION_CONTRACT_PATH, contract_destination; force = true)
    return contract_destination
end

function captured_error(function_call)
    return try
        function_call()
        nothing
    catch error
        error
    end
end

@testset "WS-2C production reconciliation admission evidence" begin
    contract = load_admission_evidence_contract(ADMISSION_CONTRACT_PATH)
    output_directory = mktempdir()
    written = write_production_reconciliation_admission_evidence_report(
        output_directory,
        ADMISSION_CONTRACT_PATH,
    )
    report = written.report

    @testset "Pinned evidence contract and hard boundary" begin
        @test bytes2hex(SHA.sha256(read(ADMISSION_CONTRACT_PATH))) ==
            APPROVED_CONTRACT_SHA256
        @test contract.source_sha256 == APPROVED_CONTRACT_SHA256
        @test contract.contract_id ==
            "us-ws2c-production-reconciliation-admission-evidence-v1"
        @test contract.classification ==
            "CURRENT_VINTAGE_SOLVER_ADMISSION_EVIDENCE_NOT_APPROVAL"
        @test contract.promotion_status == "RESEARCH_ONLY_NOT_PROMOTED"
        @test normalized_module_sha256(ADMISSION_MODULE_PATH) ==
            contract.module_normalized_sha256
        @test contract.candidate_problem_scope_hash ==
            "scope1:9b41bd41ba5ba7f421aac0a3244cd58bf663fef36dcd507628af4d009cb69088"
        @test contract.candidate_problem_hash ==
            "problem1:07607869be848a0016e5de1ea861b6350593369b92f973eac8b417648803a3d3"
        @test length(contract.artifacts) == 12
        @test contract.artifacts["itable_canonical_grid"].sha256 ==
            "2a7c2eb3a809ff9b2e9805569692a095adf590a959017d99911e7f11450ab4e8"
        @test length(contract.literature) >= 8
        @test !isempty(contract.promotion_blockers)
        @test !(
            "IMPORT_ELLIPSIS_RELEASE_FAMILY_CONVENTION_NOT_APPROVED" in
                contract.promotion_blockers
        )
        @test "SOURCE_STRUCTURAL_ZERO_EVIDENCE_INCOMPLETE" in
            contract.promotion_blockers
        @test "PRODUCTION_RELIABILITY_CLASSES_NOT_APPROVED" in
            contract.promotion_blockers
        @test "PRODUCTION_COVARIANCE_MODEL_NOT_APPROVED" in
            contract.promotion_blockers
    end

    @testset "Release-scoped display semantics" begin
        @test length(report.source_display_records) == 12
        @test length(report.release_marker_receipts) == 2
        @test Set(item.table_key for item in report.release_marker_receipts) ==
            Set(["MakeAR", "UIMARI"])
        import_receipt = only(
            item
                for item in report.release_marker_receipts
                if item.table_key == "UIMARI"
        )
        make_receipt = only(
            item
                for item in report.release_marker_receipts
                if item.table_key == "MakeAR"
        )
        @test (
            import_receipt.api_row_count,
            import_receipt.api_column_count,
            import_receipt.projection_row_count,
            import_receipt.projection_column_count,
            import_receipt.projection_cell_count,
            import_receipt.marker_count,
            import_receipt.literal_zero_count,
            import_receipt.full_grid_exact_match_count,
            import_receipt.full_grid_mismatch_count,
            import_receipt.full_grid_maximum_absolute_difference_millions,
        ) == (73, 93, 73, 93, 6_789, 4_102, 369, 6_789, 0, 0)
        @test (
            make_receipt.api_row_count,
            make_receipt.api_column_count,
            make_receipt.projection_row_count,
            make_receipt.projection_column_count,
            make_receipt.projection_cell_count,
            make_receipt.marker_count,
            make_receipt.literal_zero_count,
            make_receipt.full_grid_exact_match_count,
            make_receipt.full_grid_mismatch_count,
            make_receipt.full_grid_maximum_absolute_difference_millions,
        ) == (72, 74, 71, 73, 5_183, 4_682, 84, 5_183, 0, 0)
        @test all(
            item ->
            item.exact_common_basis_coordinate_match &&
                item.exact_common_basis_full_grid_match &&
                occursin(
                r"^[0-9a-f]{64}$",
                item.canonical_full_grid_sha256,
            ) &&
                !item.solver_admissible,
            report.release_marker_receipts,
        )
        @test import_receipt.semantic_scope ==
            "PINNED_2025_ANNUAL_RELEASE_2024_SUMMARY_TABLE_ONLY"
        @test all(
            occursin(r"^[0-9a-f]{64}$", item.request_sha256)
                for item in report.release_marker_receipts
        )
        import_witness = only(
            item
                for item in report.source_display_records
                if item.record_id == "IMPORT_2024_ELLIPSIS_WITNESS"
        )
        @test import_witness.source_token == "..."
        @test import_witness.semantic_class ==
            "RELEASE_SCOPED_CORROBORATED_SELECTED_ZERO_DISPLAY_TOKEN"
    end

    @testset "Observation loading and residual diagnostics" begin
        @test length(report.valuation_import_boundaries) == 6
        @test length(report.domestic_use_points) == 6_160
        @test count(
            item -> item.raw_numeric_residual_millions !== nothing,
            report.domestic_use_points,
        ) == 2_480
        @test count(
            item ->
            item.boundary_role ==
                "IMPORT_ACCOUNTING_OFFSET_DIAGNOSTIC_ONLY",
            report.domestic_use_points,
        ) == 70
        @test all(
            item ->
            (
                item.input_selected_zero_count == 0 &&
                    item.raw_numeric_residual_millions !== nothing
            ) ||
                (
                item.input_selected_zero_count > 0 &&
                    item.raw_numeric_residual_millions === nothing
            ),
            report.domestic_use_points,
        )
        @test all(
            item ->
            item.display_scenario_id ==
                "AUTHENTICATED_RELEASE_SCOPED_DISPLAY_ZERO" &&
                !item.independent_observation &&
                !item.solver_admissible,
            report.domestic_use_points,
        )
        domestic_witness = only(
            item
                for item in report.domestic_use_points
                if item.cell_id ==
                "AR24:DOMESTIC_FINAL_USE:CORE:113FF:F030"
        )
        @test domestic_witness.producer_use_cell_id ==
            "AR24:PRODUCER_FINAL_USE:CORE:113FF:F030"
        @test domestic_witness.imputed_import_cell_id ==
            "AR24:IMPORT_FINAL_USE:CORE:113FF:F030"
        @test domestic_witness.display_point_value_millions == 365.0
        @test domestic_witness.raw_numeric_residual_millions == 365.0
        @test domestic_witness.input_selected_zero_count == 0
        @test startswith(domestic_witness.lineage_hash, "domestic1:")
        positive_import_witness = only(
            item
                for item in report.domestic_use_points
                if item.cell_id ==
                "AR24:DOMESTIC_INTERMEDIATE_USE:CORE:113FF:111CA"
        )
        @test positive_import_witness.display_point_value_millions == 31_362.0
        @test positive_import_witness.raw_numeric_residual_millions == 31_362.0
        @test positive_import_witness.input_selected_zero_count == 0
        mixed_ellipsis_witness = only(
            item
                for item in report.domestic_use_points
                if item.cell_id ==
                "AR24:DOMESTIC_INTERMEDIATE_USE:CORE:113FF:4A0"
        )
        @test mixed_ellipsis_witness.input_selected_zero_count == 6
        @test mixed_ellipsis_witness.display_point_value_millions == 44.0
        @test mixed_ellipsis_witness.raw_numeric_residual_millions === nothing
        @test length(report.observation_loadings) == 19_428
        @test length(
            unique(
                item.canonical_source_key for item in report.observation_loadings
            )
        ) == 19_428
        @test count(
            item -> item.owner_kind == "TARGET_CELL",
            report.observation_loadings,
        ) == 18_826
        @test count(
            item -> item.owner_kind == "MEASURED_PUBLISHED_MARGIN_RHS",
            report.observation_loadings,
        ) == 602
        @test length(
            unique(
                item.owner_id
                    for item in report.observation_loadings
                    if item.owner_kind == "TARGET_CELL"
            )
        ) == 17_422
        @test length(
            unique(
                item.owner_id
                    for item in report.observation_loadings
                    if item.owner_kind == "MEASURED_PUBLISHED_MARGIN_RHS"
            )
        ) == 578
        @test all(
            item ->
            item.coefficient == 1.0 &&
                item.numerical_reliability_receipt_id === nothing &&
                item.numerical_covariance_receipt_id === nothing &&
                !item.solver_admissible,
            report.observation_loadings,
        )

        primary = filter(
            item ->
            item.scenario_id ==
                "AUTHENTICATED_RELEASE_SCOPED_DISPLAY_ZERO",
            report.control_diagnostics,
        )
        counterfactual = filter(
            item ->
            item.scenario_id ==
                "WORKBOOK_LOCAL_NOTE_ONLY_COUNTERFACTUAL",
            report.control_diagnostics,
        )
        @test length(primary) == 924
        @test length(counterfactual) == 924
        @test count(
            item -> item.point_residual_millions !== nothing,
            primary,
        ) == 924
        @test count(
            item -> item.point_residual_zero === true,
            primary,
        ) == 378
        @test count(
            item -> item.point_residual_zero === false,
            primary,
        ) == 546
        @test count(
            item -> item.point_residual_millions !== nothing,
            counterfactual,
        ) == 722
        @test count(
            item -> item.point_residual_millions === nothing,
            counterfactual,
        ) == 202
        @test maximum(
            abs(item.point_residual_millions)
                for item in primary
                if item.control_kind == "EXACT_ACCOUNTING_IDENTITY"
        ) == 7.0
        @test maximum(
            abs(item.point_residual_millions)
                for item in primary
                if item.control_kind == "MEASURED_PUBLISHED_MARGIN"
        ) == 27.0
        @test all(
            item ->
            item.sensitivity_status ==
                "WITHIN_UNAPPROVED_NEAREST_INTEGER_SENSITIVITY_ENVELOPE",
            primary,
        )
        @test all(!item.solver_admissible for item in primary)
    end

    @testset "Evidence-only uncertainty and negative-cell boundary" begin
        @test length(report.negative_cells) == 129
        @test count(
            item ->
            startswith(
                item.source_negative_economic_type,
                "UNRESOLVED_",
            ),
            report.negative_cells,
        ) == 23
        @test count(
            item ->
            startswith(
                item.classification_status,
                "LITERATURE_SUPPORTED_",
            ),
            report.negative_cells,
        ) == 16
        @test count(
            item ->
            item.classification_status == "UNRESOLVED_SEMANTIC_BLOCKER",
            report.negative_cells,
        ) == 7
        registered_literature_ids =
            Set(item.literature_id for item in contract.literature)
        @test all(
            item ->
            all(
                id -> id in registered_literature_ids,
                split(item.evidence_ids, '|'),
            ),
            filter(
                item ->
                startswith(
                    item.source_negative_economic_type,
                    "UNRESOLVED_",
                ),
                report.negative_cells,
            ),
        )
        @test only(
            item
                for item in report.negative_cells
                if item.cell_id ==
                "AR24:PRODUCER_FINAL_USE:CLOSURE:Other:F010"
        ).evidence_negative_economic_type ==
            "OTHER_NONCOMPARABLE_IMPORTS_ROW_ADJUSTMENT_COMPOSITE_SIGNED_FINAL_USE_RECLASSIFICATION"
        @test only(
            item
                for item in report.negative_cells
                if item.cell_id == "AR24:PRODUCER_MAKE:GFGN:CORE:22"
        ).evidence_sign_domain == "UNRESOLVED_BLOCKED"
        @test length(report.dependence_groups) == 17
        @test length(report.revision_vintages) == 2
        @test all(
            item ->
            item.numerical_parameter_status ==
                "NO_NUMERICAL_CORRELATION_RECEIPT" &&
                !item.solver_admissible,
            report.dependence_groups,
        )
        @test all(
            item ->
            item.numerical_reliability_receipt_count == 0 &&
                item.numerical_covariance_receipt_count == 0 &&
                !item.checked_in_cell_fixture &&
                !item.solver_admissible,
            report.revision_vintages,
        )
        @test report.solver_invocation_count == 0
        @test report.solver_input_cell_count == 0
        @test report.solver_input_control_count == 0
        @test report.approved_exact_control_count == 0
        @test report.approved_structural_zero_count == 0
        @test report.numerical_reliability_receipt_count == 0
        @test report.numerical_covariance_receipt_count == 0
        @test report.adjustment_record_count == 0
        @test !report.forecast_origin_admissible
        @test !report.promotion_ready
        @test !report.model_state_write
        @test report.accounting_gate_effect == "NONE"
        @test report.forecast_score_effect == "NONE"
        @test_throws AdmissionSolverBlockedError materialize_production_reconciliation_admission_solver_input(
            report,
        )
    end

    @testset "Controls, output, and mutation rejection" begin
        @test production_reconciliation_admission_evidence_internal_controls_pass(
            report,
            contract,
        )
        @test production_reconciliation_admission_evidence_controls_pass(
            report,
            ADMISSION_CONTRACT_PATH,
        )
        @test startswith(report.evidence_hash, "admission1:")
        @test isfile(written.manifest_path)
        manifest = TOML.parsefile(written.manifest_path)
        @test manifest["evidence_hash"] == report.evidence_hash
        @test length(manifest["output"]) == 10
        @test all(
            bytes2hex(SHA.sha256(read(joinpath(output_directory, item["path"])))) ==
                item["sha256"]
                for item in manifest["output"]
        )
        status = TOML.parsefile(
            joinpath(output_directory, "admission_evidence_status.toml"),
        )
        @test status["primary_evaluable_control_count"] == 924
        @test status["counterfactual_evaluable_control_count"] == 722
        @test status["release_marker_receipt_count"] == 2
        @test status["valuation_import_boundary_count"] == 6
        @test status["domestic_use_point_count"] == 6_160
        @test status["domestic_use_raw_evaluable_count"] == 2_480
        @test status["literature_supported_negative_cell_count"] == 16
        @test !status["forecast_origin_admissible"]
        @test !status["promotion_ready"]
        @test status["accounting_gate_effect"] == "NONE"
        @test status["forecast_score_effect"] == "NONE"

        changed_count =
            replace_struct_field(report, :solver_input_cell_count, 1)
        @test !production_reconciliation_admission_evidence_internal_controls_pass(
            changed_count,
            contract,
        )
        changed_receipt = replace_struct_field(
            first(report.release_marker_receipts),
            :exact_common_basis_coordinate_match,
            false,
        )
        changed_receipts = copy(report.release_marker_receipts)
        changed_receipts[1] = changed_receipt
        changed_report = replace_struct_field(
            report,
            :release_marker_receipts,
            changed_receipts,
        )
        @test !production_reconciliation_admission_evidence_internal_controls_pass(
            changed_report,
            contract,
        )
        numeric_domestic_index = findfirst(
            item -> item.raw_numeric_residual_millions !== nothing,
            report.domestic_use_points,
        )
        changed_domestic = replace_struct_field(
            report.domestic_use_points[numeric_domestic_index],
            :display_point_value_millions,
            report.domestic_use_points[numeric_domestic_index].
            display_point_value_millions + 1.0,
        )
        changed_domestic_points = copy(report.domestic_use_points)
        changed_domestic_points[numeric_domestic_index] = changed_domestic
        changed_domestic_report = replace_struct_field(
            report,
            :domestic_use_points,
            changed_domestic_points,
        )
        @test !production_reconciliation_admission_evidence_internal_controls_pass(
            changed_domestic_report,
            contract,
        )

        temporary_root = mktempdir()
        copied_contract =
            copy_admission_bound_tree(temporary_root, contract)
        @test load_admission_evidence_contract(
            copied_contract;
            repo_root = temporary_root,
        ).source_sha256 == contract.source_sha256
        copied_receipt = joinpath(
            temporary_root,
            contract.artifacts["itable_marker_receipt"].relative_path,
        )
        open(copied_receipt, "a") do io
            write(io, '\n')
        end
        error = captured_error() do
            load_admission_evidence_contract(
                copied_contract;
                repo_root = temporary_root,
            )
        end
        @test error isa AdmissionEvidenceContractError

        mktempdir() do symlink_root
            symlinked_contract =
                copy_admission_bound_tree(symlink_root, contract)
            artifact =
                contract.artifacts["negative_cell_semantics_fixture"]
            target = joinpath(symlink_root, artifact.relative_path)
            rm(target)
            symlink(
                joinpath(ADMISSION_REPO_ROOT, artifact.relative_path),
                target,
            )
            symlink_error = captured_error() do
                load_admission_evidence_contract(
                    symlinked_contract;
                    repo_root = symlink_root,
                )
            end
            @test symlink_error isa AdmissionEvidenceContractError
            @test occursin(
                "symbolic link",
                sprint(showerror, symlink_error),
            )
        end

        mktempdir() do parent_symlink_root
            symlinked_contract =
                copy_admission_bound_tree(parent_symlink_root, contract)
            artifact =
                contract.artifacts["negative_cell_semantics_fixture"]
            target = joinpath(
                parent_symlink_root,
                artifact.relative_path,
            )
            parent = dirname(target)
            rm(parent; recursive = true)
            symlink(
                dirname(
                    joinpath(
                        ADMISSION_REPO_ROOT,
                        artifact.relative_path,
                    ),
                ),
                parent,
            )
            escape_error = captured_error() do
                load_admission_evidence_contract(
                    symlinked_contract;
                    repo_root = parent_symlink_root,
                )
            end
            @test escape_error isa AdmissionEvidenceContractError
            @test occursin(
                "resolved path escapes repository root",
                sprint(showerror, escape_error),
            )
        end
    end
end
