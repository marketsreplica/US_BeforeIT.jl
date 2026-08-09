using CSV
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USUsedOtherEvidenceLedger.jl"))
using .USUsedOtherEvidenceLedger

const USED_OTHER_CONTRACT_PATH =
    joinpath(@__DIR__, "used_other_evidence_ledger.toml")
const USED_OTHER_CONTRACT_SHA256 =
    "326dc50276692c5623e23fe63085cb82742435b6c6b3d0a04676451426d9d128"

file_sha256(path) = bytes2hex(SHA.sha256(read(path)))

function component_by_code(report, code)
    return only(
        item for item in report.components if item.component_code == code
    )
end

function check_by_id(report, check_id)
    return only(item for item in report.checks if item.check_id == check_id)
end

function decision_by_id(report, decision_id)
    return only(
        item for item in report.decisions if item.decision_id == decision_id
    )
end

function observation_by_id(report, record_id)
    return only(
        item for item in report.observations if item.record_id == record_id
    )
end

function directory_bytes(directory)
    filenames = sort(readdir(directory))
    return Dict(filename => read(joinpath(directory, filename)) for filename in filenames)
end

@testset "Fail-closed Used/Other evidence and decision ledger" begin
    contract =
        load_used_other_evidence_contract(USED_OTHER_CONTRACT_PATH)
    report = build_used_other_evidence(contract)

    @testset "Pinned contract, exact endpoint, and negative detail finding" begin
        @test file_sha256(USED_OTHER_CONTRACT_PATH) ==
            USED_OTHER_CONTRACT_SHA256
        @test APPROVED_CONTRACT_SHA256 == USED_OTHER_CONTRACT_SHA256
        @test contract.classification ==
            "VINTAGE_SEPARATED_ACCOUNTING_EVIDENCE_NOT_ORIGIN_ELIGIBLE"
        @test contract.promotion_status == "RESEARCH_ONLY_NOT_PROMOTED"
        @test length(contract.artifacts) == 13
        @test all(
            item.sha256 == file_sha256(item.path)
                for item in values(contract.artifacts)
        )
        @test contract.detail_vintage_scope["source_endpoint"] ==
            "https://apps.bea.gov/industry/release/zip/MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip"
        @test contract.detail_vintage_scope["source_zip_sha256"] ==
            "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
        @test contract.detail_vintage_scope[
            "producer_detail_sheet_names",
        ] == ["NAICS Codes", "2007", "2012", "2017"]
        @test contract.detail_vintage_scope[
            "producer_summary_year_span",
        ] == "1997_THROUGH_2024"
        @test contract.detail_vintage_scope["latest_detail_year"] == 2017
        @test contract.detail_vintage_scope["latest_summary_year"] == 2024
        @test !contract.detail_vintage_scope[
            "newer_than_2017_detail_available",
        ]
        @test occursin(
            "no 2022 or 2024 detailed",
            contract.detail_vintage_scope["finding"],
        )
        @test check_by_id(
            report,
            "newer_than_2017_detail_vintage_absence",
        ).residual == 0.0
        @test report.summary["newer_than_2017_detail_vintage_count"] == 0
        @test !contract.forecast_origin_admissible
        @test !contract.promotion_ready
        @test !contract.model_state_write
        @test contract.accounting_gate_effect == :none
        @test !contract.forecast_score_write
        scope_inventory = TOML.parsefile(
            contract.artifacts[
                "after_redefinitions_workbook_sheet_inventory",
            ].path,
        )
        @test scope_inventory["source_zip_sha256"] ==
            contract.detail_vintage_scope["source_zip_sha256"]
        @test scope_inventory["detail_years"] == [2007, 2012, 2017]
        @test scope_inventory["summary_years"] == collect(1997:2024)
        @test all(
            workbook["sheet_names"] ==
                ["NAICS Codes", "2007", "2012", "2017"]
                for workbook in scope_inventory["workbook"]
                if workbook["level"] == "DETAIL"
        )
        @test occursin(
            "ARCHIVE_DERIVED_WORKBOOK_SHEET_INVENTORY",
            check_by_id(
                report,
                "newer_than_2017_detail_vintage_absence",
            ).evidence_scope,
        )

        mktempdir() do directory
            changed = joinpath(directory, "changed.toml")
            write(changed, read(USED_OTHER_CONTRACT_PATH), UInt8('\n'))
            @test_throws ArgumentError load_used_other_evidence_contract(
                changed,
            )
        end
    end

    @testset "Vintages and all source cell states remain distinct" begin
        @test length(report.observations) == 4_162
        @test count(item -> item.year == 2017, report.observations) == 3_644
        @test count(
            item -> item.year == 2017 && item.source_level == "detail",
            report.observations,
        ) == 3_312
        @test count(
            item -> item.year == 2017 && item.source_level == "summary",
            report.observations,
        ) == 332
        @test count(item -> item.year == 2024, report.observations) == 518
        @test count(item -> item.numeric_mask, report.observations) == 952
        @test count(item -> item.native_blank_mask, report.observations) ==
            2_748
        @test count(
            item -> item.native_ellipsis_mask,
            report.observations,
        ) == 188
        @test count(
            item -> item.selected_zero_not_shown_mask,
            report.observations,
        ) == 3_210
        @test count(
            item -> item.explicit_numeric_zero,
            report.observations,
        ) == 66
        @test count(
            item -> item.value_millions < 0,
            report.observations,
        ) == 56
        @test all(
            item ->
            item.selected_zero_not_shown_mask ?
                iszero(item.value_millions) : true,
            report.observations,
        )
        @test all(!item.structural_zero_claimed for item in report.observations)
        @test all(!item.mapping_applied for item in report.observations)
        @test all(
            !item.source_make_placement_is_producer_inference
                for item in report.observations
        )

        detail_2017 = filter(
            item -> item.year == 2017 && item.source_level == "detail",
            report.observations,
        )
        summary_2017 = filter(
            item -> item.year == 2017 && item.source_level == "summary",
            report.observations,
        )
        summary_2024 =
            filter(item -> item.year == 2024, report.observations)
        @test Set(getfield.(detail_2017, :account_code)) ==
            Set(["S00401", "S00402", "S00300", "S00900"])
        @test Set(getfield.(summary_2017, :account_code)) ==
            Set(["Used", "Other"])
        @test Set(getfield.(summary_2024, :account_code)) ==
            Set(["Used", "Other"])
        @test all(isempty(item.component_code) for item in summary_2024)
        @test all(
            item.economic_type ==
                "UNRESOLVED_VINTAGE_SPECIFIC_COMPOSITE"
                for item in summary_2024
        )
        @test count(
            item -> item.account_code == "Used",
            summary_2024,
        ) == 259
        @test count(
            item -> item.account_code == "Other",
            summary_2024,
        ) == 259

        native_blank = only(
            Iterators.take(
                (
                    item for item in report.observations
                        if item.native_blank_mask
                ),
                1,
            ),
        )
        @test native_blank.native_cell_kind == "blank"
        @test native_blank.selected_zero_not_shown_mask
        @test !native_blank.numeric_mask

        native_ellipsis = only(
            Iterators.take(
                (
                    item for item in report.observations
                        if item.native_ellipsis_mask
                ),
                1,
            ),
        )
        @test native_ellipsis.native_cell_kind == "ellipsis"
        @test native_ellipsis.selected_zero_not_shown_mask
        @test !native_ellipsis.native_blank_mask

        explicit_zero = only(
            Iterators.take(
                (
                    item for item in report.observations
                        if item.explicit_numeric_zero
                ),
                1,
            ),
        )
        @test explicit_zero.native_cell_kind == "numeric"
        @test explicit_zero.numeric_mask
        @test !explicit_zero.selected_zero_not_shown_mask

        selected_2024 = only(
            Iterators.take(
                (
                    item for item in report.observations
                        if item.year == 2024 &&
                        item.native_cell_kind ==
                        "selected_zero_not_shown"
                ),
                1,
            ),
        )
        @test selected_2024.selected_zero_not_shown_mask
        @test !selected_2024.native_blank_mask
        @test !selected_2024.native_ellipsis_mask
    end

    @testset "Four economic components and source make/use roles" begin
        scrap = component_by_code(report, "S00401")
        used = component_by_code(report, "S00402")
        noncomparable = component_by_code(report, "S00300")
        row_adjustment = component_by_code(report, "S00900")

        @test scrap.economic_type ==
            "MIXED_SCRAP_CURRENT_BYPRODUCT_AND_EXISTING_ASSET_DISPOSAL"
        @test scrap.current_production_output
        @test scrap.existing_asset_transfer
        @test scrap.observed_2017_intermediate_millions == 30_485.0
        @test scrap.observed_2017_final_use_millions == -19_722.0
        @test scrap.observed_2017_output_millions == 10_763.0
        @test scrap.observed_2017_make_placement_count == 79
        @test scrap.observed_2017_make_placement_sum_millions == 10_761.0
        @test occursin("BYPRODUCT", scrap.source_make_role)

        @test used.economic_type == "EXISTING_GOOD_OR_ASSET_TRANSFER"
        @test used.existing_asset_transfer
        @test !used.current_production_output
        @test used.observed_2017_intermediate_millions == 27_562.0
        @test used.observed_2017_final_use_millions == -27_562.0
        @test used.observed_2017_output_millions == 0.0
        @test used.observed_2017_output_cell_kind == "blank"
        @test used.observed_2017_make_placement_count == 0
        @test !used.structural_zero_claimed
        @test occursin("TRANSFER", used.source_use_role)

        @test noncomparable.economic_type ==
            "IMPORT_BOUNDARY_NONCOMPARABLE_SERVICES_OR_RIGHTS"
        @test noncomparable.import_boundary
        @test !noncomparable.current_production_output
        @test noncomparable.observed_2017_intermediate_millions ==
            142_489.0
        @test noncomparable.observed_2017_final_use_millions ==
            -142_489.0
        @test noncomparable.observed_2017_output_millions == 0.0
        @test noncomparable.observed_2017_output_cell_kind == "blank"

        @test row_adjustment.economic_type ==
            "FINAL_USE_RESIDENCE_RECLASSIFICATION_ADJUSTMENT"
        @test row_adjustment.import_boundary
        @test row_adjustment.reclassification
        @test !row_adjustment.current_production_output
        @test row_adjustment.observed_2017_intermediate_millions == 0.0
        @test row_adjustment.observed_2017_final_use_millions == 3_468.0
        @test row_adjustment.observed_2017_output_millions == 3_468.0
        @test row_adjustment.observed_2017_make_placement_count == 1
        @test occursin(
            "NOT_PRODUCER_IDENTIFICATION",
            row_adjustment.source_make_role,
        )

        @test all(
            item.allocation_2024_status == "NOT_RUN_BLOCKED"
                for item in report.components
        )
        @test all(isempty(item.runtime_target_namespace) for item in report.components)
        @test all(
            !item.source_make_placement_is_producer_inference
                for item in report.components
        )
        @test all(!item.mapping_applied for item in report.components)

        s009_placement = only(
            item for item in report.observations
                if item.projection_id == "detail_make_components_2017" &&
                item.account_code == "S00900" &&
                !iszero(item.value_millions)
        )
        @test s009_placement.row_code == "S00600"
        @test s009_placement.value_millions == 3_468.0
        @test !s009_placement.source_make_placement_is_producer_inference

        summary_other_placement = only(
            item for item in report.observations
                if item.projection_id == "summary_make_components_2017" &&
                item.account_code == "Other" &&
                !iszero(item.value_millions)
        )
        @test summary_other_placement.row_code == "GFGN"
        @test summary_other_placement.value_millions == 3_468.0
        @test !summary_other_placement.source_make_placement_is_producer_inference
    end

    @testset "Code-keyed reconstruction and transfer/output semantics" begin
        for id in (
                "2017_used_t001_reconstruction",
                "2017_used_t004_reconstruction",
                "2017_used_t007_reconstruction",
                "2017_other_t001_reconstruction",
                "2017_other_t004_reconstruction",
                "2017_other_t007_reconstruction",
            )
            check = check_by_id(report, id)
            @test check.status == "PASS_SOURCE_EVIDENCE"
            @test check.residual == 0.0
            @test check.tolerance == 0.0
        end
        @test check_by_id(
            report,
            "2017_used_final_cell_maximum_residual",
        ).absolute_residual == 1.0
        @test check_by_id(
            report,
            "2017_other_final_cell_maximum_residual",
        ).absolute_residual == 1.0
        @test check_by_id(
            report,
            "2017_s00402_use_output_identity",
        ).lhs == 0.0
        @test check_by_id(
            report,
            "2017_s00402_use_output_identity",
        ).rhs == 0.0
        @test occursin(
            "EXISTING_GOOD_TRANSFER",
            check_by_id(
                report,
                "2017_s00402_use_output_identity",
            ).evidence_scope,
        )
        @test check_by_id(
            report,
            "2017_s00401_use_output_identity",
        ).lhs == 10_763.0
        @test check_by_id(
            report,
            "2017_s00401_use_output_identity",
        ).rhs == 10_763.0
        @test occursin(
            "MIXED_SCRAP",
            check_by_id(
                report,
                "2017_s00401_use_output_identity",
            ).evidence_scope,
        )
        @test check_by_id(
            report,
            "2017_s00401_make_to_output",
        ).residual == -2.0
        @test check_by_id(
            report,
            "2017_s00401_make_to_output",
        ).tolerance == 2.0
        @test check_by_id(
            report,
            "2017_s00900_make_to_output",
        ).residual == 0.0
        @test all(
            item.absolute_residual <= item.tolerance for item in report.checks
        )
        @test all(!item.correction_applied for item in report.checks)
        @test all(!item.mapping_applied for item in report.checks)
    end

    @testset "2024 summary preservation and blocked allocations" begin
        @test check_by_id(
            report,
            "2024_used_make_to_output",
        ).residual == 0.0
        @test check_by_id(
            report,
            "2024_other_make_to_output",
        ).residual == 0.0
        @test check_by_id(
            report,
            "2024_other_producer_control_identity",
        ).residual == -1.0
        @test check_by_id(
            report,
            "2024_other_producer_intermediate_to_control",
        ).residual == 4.0
        @test check_by_id(
            report,
            "2024_other_import_intermediate_to_control",
        ).residual == 4.0

        @test length(report.decisions) == 9
        @test all(
            item ->
            item.status == "NOT_RUN_BLOCKED" &&
                ismissing(item.diagnostic_value) &&
                ismissing(item.tolerance) &&
                !item.mapping_applied &&
                !item.output_emitted &&
                isempty(item.target_namespace) &&
                !item.forecast_origin_admissible,
            report.decisions,
        )
        @test occursin(
            "dealer",
            lowercase(
                decision_by_id(
                    report,
                    "dealer_service_allocation",
                ).blocker,
            ),
        )
        @test occursin(
            "separately invoiced",
            decision_by_id(
                report,
                "transport_service_allocation",
            ).blocker,
        )
        @test occursin(
            "does not identify S00401 versus S00402",
            decision_by_id(
                report,
                "used_2024_component_allocation",
            ).blocker,
        )
        @test occursin(
            "does not identify S00300 versus S00900",
            decision_by_id(
                report,
                "other_2024_component_allocation",
            ).blocker,
        )
        @test_throws ArgumentError allocate_2024_components(report)
        @test_throws ArgumentError project_2017_component_shares_to_2024(
            report,
        )
        @test_throws ArgumentError materialize_used_other_model_state(
            report,
        )
        @test report.summary["projected_2017_share_count"] == 0
        @test report.summary["dealer_margin_allocation_count"] == 0
        @test report.summary["transport_service_allocation_count"] == 0
        @test report.summary["component_allocation_2024_count"] == 0
        @test report.summary["core_absorption_count"] == 0
        @test report.summary["model_absorption_count"] == 0
        @test report.summary["government_producer_inference_count"] == 0
        @test report.summary["row_behavior_inference_count"] == 0
        @test report.summary["model_state_write_count"] == 0
        @test report.summary["gate_effect_count"] == 0
        @test report.summary["origin_admissible_output_count"] == 0
        @test report.summary["forecast_score_write_count"] == 0
    end

    @testset "Code beats labels and adversarial absorption fails closed" begin
        mislabeled_scrap = classify_special_account(
            "S00401",
            "Rest of the world adjustment",
        )
        @test mislabeled_scrap.component_code == "S00401"
        @test mislabeled_scrap.aggregate_account_code == "Used"
        @test mislabeled_scrap.economic_type ==
            "MIXED_SCRAP_CURRENT_BYPRODUCT_AND_EXISTING_ASSET_DISPOSAL"

        mislabeled_used = classify_special_account("Used", "Other")
        @test mislabeled_used.account_code == "Used"
        @test isempty(mislabeled_used.component_code)
        @test mislabeled_used.economic_type ==
            "UNRESOLVED_VINTAGE_SPECIFIC_COMPOSITE"
        @test_throws ArgumentError classify_special_account(
            "MODEL_CORE_01",
            "Used",
        )

        sign_mutation = deepcopy(report)
        sign_index = findfirst(
            item -> item.value_millions < 0,
            sign_mutation.observations,
        )
        sign_mutation.observations[sign_index].value_millions *= -1
        sign_mutation.observations[sign_index].sign_class = "POSITIVE"
        @test_throws ArgumentError validate_used_other_evidence(
            sign_mutation,
            contract,
        )

        mask_mutation = deepcopy(report)
        mask_index = findfirst(
            item -> item.native_ellipsis_mask,
            mask_mutation.observations,
        )
        mask_mutation.observations[mask_index].native_ellipsis_mask = false
        mask_mutation.observations[mask_index].numeric_mask = true
        mask_mutation.observations[
            mask_index,
        ].selected_zero_not_shown_mask = false
        mask_mutation.observations[mask_index].explicit_numeric_zero = true
        mask_mutation.observations[mask_index].native_cell_kind = "numeric"
        @test_throws ArgumentError validate_used_other_evidence(
            mask_mutation,
            contract,
        )

        label_mutation = deepcopy(report)
        label_mutation.observations[1].row_description = "Used"
        @test_throws ArgumentError validate_used_other_evidence(
            label_mutation,
            contract,
        )

        allocation_mutation = deepcopy(report)
        allocation_index = findfirst(
            item -> item.year == 2024,
            allocation_mutation.observations,
        )
        allocation_mutation.observations[
            allocation_index,
        ].component_code = "S00401"
        allocation_mutation.observations[
            allocation_index,
        ].economic_type =
            "MIXED_SCRAP_CURRENT_BYPRODUCT_AND_EXISTING_ASSET_DISPOSAL"
        @test_throws ArgumentError validate_used_other_evidence(
            allocation_mutation,
            contract,
        )

        injected_source_mutation = deepcopy(report)
        injected_source_mutation.observations[1].value_millions += 1.0
        @test_throws MethodError validate_used_other_evidence(
            injected_source_mutation,
            contract;
            source_observations = injected_source_mutation.observations,
        )

        contract_mutation = deepcopy(contract)
        contract_mutation.literature[1].source_fact = "FABRICATED"
        contract_report_mutation = deepcopy(report)
        contract_report_mutation.literature[1].source_fact = "FABRICATED"
        @test_throws ArgumentError validate_used_other_evidence(
            contract_report_mutation,
            contract_mutation,
        )

        component_mutation = deepcopy(report)
        component_mutation.components[4].runtime_target_namespace =
            "GOVERNMENT"
        component_mutation.components[4].mapping_applied = true
        @test_throws ArgumentError validate_used_other_evidence(
            component_mutation,
            contract,
        )

        producer_mutation = deepcopy(report)
        producer_mutation.components[
            4,
        ].source_make_placement_is_producer_inference = true
        @test_throws ArgumentError validate_used_other_evidence(
            producer_mutation,
            contract,
        )

        decision_mutation = deepcopy(report)
        decision_mutation.decisions[1].status = "PASS"
        decision_mutation.decisions[1].diagnostic_value = 0.0
        decision_mutation.decisions[1].tolerance = 0.0
        @test_throws ArgumentError validate_used_other_evidence(
            decision_mutation,
            contract,
        )

        absorption_mutation = deepcopy(report)
        absorption = decision_by_id(
            absorption_mutation,
            "label_based_core_or_model_absorption",
        )
        absorption.mapping_applied = true
        absorption.output_emitted = true
        absorption.target_namespace = "MODEL_CORE"
        @test_throws ArgumentError validate_used_other_evidence(
            absorption_mutation,
            contract,
        )

        check_mutation = deepcopy(report)
        check_mutation.checks[1].correction_applied = true
        @test_throws ArgumentError validate_used_other_evidence(
            check_mutation,
            contract,
        )

        literature_mutation = deepcopy(report)
        literature_mutation.literature[1].url = "https://example.invalid/"
        @test_throws ArgumentError validate_used_other_evidence(
            literature_mutation,
            contract,
        )

        summary_mutation = deepcopy(report)
        summary_mutation.summary["component_allocation_2024_count"] = 1
        @test_throws ArgumentError validate_used_other_evidence(
            summary_mutation,
            contract,
        )

        state_mutation = deepcopy(report)
        state_mutation.model_state_write = true
        @test_throws ArgumentError validate_used_other_evidence(
            state_mutation,
            contract,
        )
    end

    @testset "Cited decisions and deterministic isolated outputs" begin
        @test length(report.literature) == 13
        @test all(
            item -> startswith(item.url, "https://") &&
                !isempty(item.locator) &&
                length(item.document_sha256) == 64 &&
                item.accessed_on == "2026-08-06",
            report.literature,
        )
        @test Set(getfield.(report.literature, :authority)) ⊇
            Set(
            [
                "U.S. Bureau of Economic Analysis",
                "United Nations",
                "Eurostat",
                "OECD and European Union",
            ],
        )
        current_scope = only(
            item for item in report.literature
                if item.literature_id == "bea_current_archive_detail_scope"
        )
        @test current_scope.document_sha256 ==
            "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
        @test occursin("2007, 2012, and 2017", current_scope.source_fact)
        @test occursin("zero newer-than-2017", current_scope.project_decision)

        mktempdir() do directory
            first_directory = joinpath(directory, "first")
            second_directory = joinpath(directory, "second")
            first_written = write_used_other_evidence(
                report,
                contract,
                first_directory,
            )
            second_written = write_used_other_evidence(
                report,
                contract,
                second_directory,
            )
            @test directory_bytes(first_directory) ==
                directory_bytes(second_directory)
            @test first_written.observations_sha256 ==
                second_written.observations_sha256
            @test first_written.components_sha256 ==
                second_written.components_sha256
            @test first_written.checks_sha256 ==
                second_written.checks_sha256
            @test first_written.decisions_sha256 ==
                second_written.decisions_sha256
            @test first_written.literature_sha256 ==
                second_written.literature_sha256
            @test first_written.manifest_sha256 ==
                second_written.manifest_sha256
            @test first_written.observation_count == 4_162
            @test first_written.component_count == 4
            @test first_written.source_check_count == 35
            @test first_written.blocked_decision_count == 9
            @test first_written.literature_count == 13

            @test length(
                CSV.File(
                    joinpath(
                        first_directory,
                        "used_other_observations.csv",
                    ),
                ),
            ) == 4_162
            @test length(
                CSV.File(
                    joinpath(
                        first_directory,
                        "used_other_components.csv",
                    ),
                ),
            ) == 4
            @test length(
                CSV.File(
                    joinpath(
                        first_directory,
                        "used_other_source_checks.csv",
                    ),
                ),
            ) == 35
            @test length(
                CSV.File(
                    joinpath(
                        first_directory,
                        "used_other_decisions.csv",
                    ),
                ),
            ) == 9
            @test length(
                CSV.File(
                    joinpath(
                        first_directory,
                        "used_other_literature.csv",
                    ),
                ),
            ) == 13

            manifest =
                TOML.parsefile(joinpath(first_directory, "manifest.toml"))
            @test manifest["contract_sha256"] == USED_OTHER_CONTRACT_SHA256
            @test manifest["observation_count"] == 4_162
            @test manifest["component_count"] == 4
            @test manifest["source_check_count"] == 35
            @test manifest["blocked_decision_count"] == 9
            @test manifest["literature_count"] == 13
            @test manifest["detail_vintage_scope"][
                "newer_than_2017_detail_available",
            ] === false
            @test manifest["projected_2017_share_count"] == 0
            @test manifest["component_allocation_2024_count"] == 0
            @test manifest["model_state_write"] === false
            @test manifest["accounting_gate_effect"] == "NONE"
            @test manifest["forecast_origin_admissible"] === false
            @test manifest["forecast_score_write"] === false
            @test all(
                !occursin(
                        r"(state|gate|origin|score)",
                        lowercase(filename),
                    )
                    for filename in readdir(first_directory)
                    if filename != "manifest.toml"
            )
            @test_throws ArgumentError write_used_other_evidence(
                report,
                contract,
                first_directory,
            )

            mutated_contract = deepcopy(contract)
            mutated_contract.policies["mapping_policy"] = "FABRICATED"
            rejected_directory = joinpath(directory, "rejected")
            @test_throws ArgumentError write_used_other_evidence(
                report,
                mutated_contract,
                rejected_directory,
            )
            @test !ispath(rejected_directory)
        end
    end
end
