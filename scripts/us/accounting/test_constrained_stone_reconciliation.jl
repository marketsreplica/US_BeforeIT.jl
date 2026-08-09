using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USConstrainedStoneReconciliation.jl"))

using .USConstrainedStoneReconciliation

const STONE_CONTRACT_PATH =
    joinpath(@__DIR__, "constrained_stone_reconciliation.toml")
const STONE_FIXTURE_PATH = joinpath(
    @__DIR__,
    "fixtures",
    "stone_reconciliation_synthetic_v1",
    "benchmark.toml",
)

function rewrite_cell(
        cell::LedgerCell;
        cell_id = cell.cell_id,
        row_code = cell.row_code,
        column_code = cell.column_code,
        raw_value = cell.raw_value,
        truth_value = cell.truth_value,
        reliability_class_id = cell.reliability_class_id,
        covariance_group = cell.covariance_group,
        predetermined = cell.predetermined,
        structural_zero = cell.structural_zero,
        cell_state = cell.cell_state,
        sign_policy = cell.sign_policy,
        negative_economic_type = cell.negative_economic_type,
        benchmark_role = cell.benchmark_role,
        price_basis = cell.price_basis,
        provenance = cell.provenance,
    )
    return LedgerCell(
        cell_id,
        row_code,
        column_code,
        raw_value,
        truth_value,
        reliability_class_id,
        covariance_group,
        predetermined,
        structural_zero,
        cell_state,
        sign_policy,
        negative_economic_type,
        benchmark_role,
        price_basis,
        provenance,
    )
end

function rewrite_control(
        control::LinearControl;
        control_id = control.control_id,
        rhs = control.rhs,
        cell_ids = control.cell_ids,
        coefficients = control.coefficients,
        exact = control.exact,
        price_basis = control.price_basis,
        provenance = control.provenance,
    )
    return LinearControl(
        control_id,
        rhs,
        copy(cell_ids),
        copy(coefficients),
        exact,
        price_basis,
        provenance,
    )
end

function rewrite_problem(
        problem::StoneProblem;
        schema_version = problem.schema_version,
        fixture_id = problem.fixture_id,
        classification = problem.classification,
        description = problem.description,
        value_unit = problem.value_unit,
        price_basis = problem.price_basis,
        noised = problem.noised,
        masked = problem.masked,
        production_source = problem.production_source,
        forecast_origin_admissible = problem.forecast_origin_admissible,
        model_state_write = problem.model_state_write,
        cells = problem.cells,
        controls = problem.controls,
        source_sha256 = problem.source_sha256,
    )
    return StoneProblem(
        schema_version,
        fixture_id,
        classification,
        description,
        value_unit,
        price_basis,
        noised,
        masked,
        production_source,
        forecast_origin_admissible,
        model_state_write,
        copy(cells),
        copy(controls),
        source_sha256,
    )
end

function replace_cell_by_id(problem, cell_id; kwargs...)
    cells = LedgerCell[
        cell.cell_id == cell_id ? rewrite_cell(cell; kwargs...) : cell
            for cell in problem.cells
    ]
    return rewrite_problem(problem; cells = cells)
end

function replace_control_by_id(problem, control_id; kwargs...)
    controls = LinearControl[
        control.control_id == control_id ?
            rewrite_control(control; kwargs...) :
            control
            for control in problem.controls
    ]
    return rewrite_problem(problem; controls = controls)
end

function adjustment_by_id(result, cell_id)
    return only(
        record
            for record in result.adjustment_records
            if record.cell_id == cell_id
    )
end

function reconcile_fixture_variant(problem, contract)
    return USConstrainedStoneReconciliation._reconcile_stone_fixture_variant(
        problem,
        contract,
    )
end

@testset "WS-2C constrained Stone/GLS research qualification" begin
    contract = load_stone_contract(STONE_CONTRACT_PATH)
    problem = load_synthetic_benchmark(
        contract;
        fixture_path = STONE_FIXTURE_PATH,
    )
    result = reconcile_stone(problem, contract)
    metrics = benchmark_metrics(problem, result, contract)
    comparators = benchmark_comparator_assessments(problem, contract)

    @testset "Pinned strict contract and primary literature" begin
        @test file_sha256(STONE_CONTRACT_PATH) ==
            APPROVED_CONTRACT_SHA256
        @test file_sha256(STONE_FIXTURE_PATH) ==
            APPROVED_FIXTURE_SHA256
        @test contract.source_sha256 == APPROVED_CONTRACT_SHA256
        @test problem.source_sha256 == APPROVED_FIXTURE_SHA256
        @test contract.schema_version == CONTRACT_SCHEMA
        @test problem.schema_version == FIXTURE_SCHEMA
        @test contract.method_id == "CONSTRAINED_STONE_GLS"
        @test contract.method_version == "stone-gls-equality-v1"
        @test occursin("Sigma^(-1)", contract.estimator)
        @test occursin("Moore-Penrose", contract.solution)
        @test occursin("Sigma_hat", contract.posterior_covariance_formula)
        @test contract.ledger_price_basis == "PRODUCERS_PRICES"
        @test contract.reliability_schema_version ==
            "beforeit-us-stone-reliability-class.v1"
        @test contract.covariance_schema_version ==
            "beforeit-us-stone-covariance-class.v1"
        @test all(
            endswith(reliability.version, "v1")
                for reliability in values(contract.reliability_classes)
        )
        @test Set(citation.citation_id for citation in contract.citations) ==
            Set(
            [
                "UN_SUT_IOT_2018",
                "STONE_CHAMPERNOWNE_MEADE_1942",
                "BYRON_1978",
                "ROBINSON_CATTANEO_ELSAID_2001",
                "LENZEN_WOOD_GALLEGO_2007",
            ],
        )
        @test only(
            citation
                for citation in contract.citations
                if citation.citation_id == "UN_SUT_IOT_2018"
        ).kind == "PRIMARY_OFFICIAL_GUIDANCE"
        @test only(
            citation
                for citation in contract.citations
                if citation.citation_id == "BYRON_1978"
        ).doi == "10.2307/2344807"
        @test all(citation.access_date == "2026-08-06" for citation in contract.citations)
        @test !contract.forecast_origin_admissible
        @test !contract.promotion_ready
        @test !contract.model_state_write
        @test contract.accounting_gate_effect == "NONE"
        @test !problem.production_source
        @test !problem.forecast_origin_admissible
        @test !problem.model_state_write

        mktempdir() do temporary_directory
            changed_contract =
                joinpath(temporary_directory, "changed_contract.toml")
            write(
                changed_contract,
                read(STONE_CONTRACT_PATH),
                codeunits("\nunexpected_key = true\n"),
            )
            @test_throws ReconciliationContractError load_stone_contract(
                changed_contract;
                verify_hash = false,
            )
            @test_throws ReconciliationContractError load_stone_contract(
                changed_contract;
                verify_hash = true,
            )

            changed_fixture =
                joinpath(temporary_directory, "changed_fixture.toml")
            write(
                changed_fixture,
                read(STONE_FIXTURE_PATH),
                codeunits("\nunexpected_key = true\n"),
            )
            @test_throws ReconciliationContractError load_synthetic_benchmark(
                contract;
                fixture_path = changed_fixture,
                verify_hash = false,
            )
            @test_throws ReconciliationContractError load_synthetic_benchmark(
                contract;
                fixture_path = changed_fixture,
                verify_hash = true,
            )
        end
    end

    @testset "Authenticated synthetic-only solver boundary" begin
        authenticated = authenticate_pinned_synthetic_benchmark(
            problem,
            contract,
        )
        @test authenticated.problem !== problem
        @test authenticated.contract !== contract
        @test authenticated.problem.source_sha256 ==
            APPROVED_FIXTURE_SHA256
        @test authenticated.contract.source_sha256 ==
            APPROVED_CONTRACT_SHA256
        @test :_reconcile_stone_fixture_variant ∉
            names(USConstrainedStoneReconciliation)

        forged_value = replace_cell_by_id(
            problem,
            "c01_high_confidence";
            raw_value = 10.1,
        )
        @test forged_value.source_sha256 == APPROVED_FIXTURE_SHA256
        @test validate_stone_problem(forged_value, contract) === nothing
        @test_throws ReconciliationContractError reconcile_stone(
            forged_value,
            contract,
        )

        forged_control = replace_control_by_id(
            problem,
            "k01_noised_pair_total";
            rhs = 35.0,
        )
        @test_throws ReconciliationContractError reconcile_stone(
            forged_control,
            contract,
        )

        forged_contract = deepcopy(contract)
        forged_contract.expected_benchmark["cell_count"] = 7
        @test forged_contract.source_sha256 == APPROVED_CONTRACT_SHA256
        @test_throws ReconciliationContractError reconcile_stone(
            problem,
            forged_contract,
        )

        @test_throws ReconciliationContractError validate_stone_problem(
            rewrite_problem(
                problem;
                classification = "PRODUCTION_SYNTHETIC",
            ),
            contract,
        )
        @test_throws ReconciliationContractError validate_stone_problem(
            rewrite_problem(problem; fixture_id = "forged-fixture"),
            contract,
        )
        @test_throws ReconciliationContractError validate_stone_problem(
            rewrite_problem(problem; value_unit = "millions_usd"),
            contract,
        )
        @test_throws ReconciliationContractError validate_stone_problem(
            rewrite_problem(problem; source_sha256 = repeat("0", 64)),
            contract,
        )
    end

    @testset "Equality-constrained GLS solution and uncertainty ledger" begin
        @test result.cell_ids == sort(result.cell_ids)
        @test result.reconciled_values ≈
            [10.6, 25.4, 5.0, -4.0, 0.0, 9.0]
        @test result.adjustable_cell_count == 4
        @test result.exact_control_count == 5
        @test result.adjustable_constraint_rank == 2
        @test result.adjustable_control_count == 3
        @test result.fixed_only_control_count == 2
        @test result.dependent_adjustable_control_count == 1
        @test result.objective_value ≈ 1.8 atol = 1.0e-14
        @test result.maximum_raw_control_residual == 6.0
        @test result.maximum_reconciled_control_residual <=
            contract.control_absolute_tolerance
        @test result.predetermined_cells_fixed
        @test result.structural_zeros_preserved
        @test result.signs_preserved
        @test result.deterministic_ordering
        @test !result.promotion_ready
        @test !result.model_state_write
        @test result.accounting_gate_effect == "NONE"

        high = adjustment_by_id(result, "c01_high_confidence")
        low = adjustment_by_id(result, "c02_low_confidence")
        fixed = adjustment_by_id(result, "c03_predetermined")
        signed = adjustment_by_id(result, "c04_signed_negative")
        structural = adjustment_by_id(result, "c05_structural_zero")
        @test high.adjustment ≈ 0.6 atol = 1.0e-14
        @test low.adjustment ≈ 5.4 atol = 1.0e-14
        @test abs(low.adjustment) / abs(high.adjustment) ≈
            9.0 atol = 1.0e-13
        @test high.reliability_class_id == "source_high_v1"
        @test low.reliability_class_id == "source_low_v1"
        @test high.prior_standard_uncertainty == 1.0
        @test low.prior_standard_uncertainty == 3.0
        @test high.posterior_standard_uncertainty ≈ sqrt(0.9)
        @test low.posterior_standard_uncertainty ≈ sqrt(0.9)
        @test fixed.adjustment == 0.0
        @test fixed.prior_standard_uncertainty == 0.0
        @test fixed.posterior_standard_uncertainty == 0.0
        @test signed.reconciled_value == -4.0
        @test signed.negative_economic_type ==
            "INVENTORY_WITHDRAWAL_SYNTHETIC"
        @test structural.reconciled_value == 0.0
        @test structural.cell_state == "STRUCTURAL_ZERO"
        @test structural.structural_zero
        @test all(
            !isempty(record.binding_control_ids)
                for record in result.adjustment_records
        )

        @test result.prior_covariance[1, 1] == 1.0
        @test result.prior_covariance[2, 2] == 9.0
        @test result.prior_covariance[4, 6] == 0.25
        @test result.prior_covariance[6, 4] == 0.25
        @test result.posterior_covariance[1, 1] ≈ 0.9
        @test result.posterior_covariance[2, 2] ≈ 0.9
        @test result.posterior_covariance[1, 2] ≈ -0.9
        @test result.posterior_covariance[3, 3] == 0.0
        @test result.posterior_covariance[5, 5] == 0.0
        @test all(
            diagnostic.exact &&
                abs(diagnostic.reconciled_residual) <=
                contract.control_absolute_tolerance
                for diagnostic in result.control_diagnostics
        )
    end

    @testset "Frozen recovery metrics" begin
        @test metrics.raw_root_mean_square_error ≈
            2.254624876411447 atol = 1.0e-14
        @test metrics.reconciled_root_mean_square_error ≈
            0.05773502691896288 atol = 1.0e-14
        @test metrics.root_mean_square_error_improvement ≈
            2.196889849492484 atol = 1.0e-14
        @test metrics.raw_mean_absolute_error == 1.0
        @test metrics.reconciled_mean_absolute_error ≈
            0.033333333333333215 atol = 1.0e-14
        @test metrics.mean_absolute_error_improvement ≈
            0.9666666666666668 atol = 1.0e-14
        @test metrics.reconciled_root_mean_square_error <
            metrics.raw_root_mean_square_error
        @test metrics.reconciled_mean_absolute_error <
            metrics.raw_mean_absolute_error
        @test metrics.reconciled_covariance_weighted_root_mean_square_error <
            metrics.raw_covariance_weighted_root_mean_square_error
        @test metrics.maximum_absolute_adjustment ≈ 5.4
        @test metrics.lower_confidence_absorbs_more
        @test metrics.low_to_high_absolute_adjustment_ratio ≈ 9.0
        @test metrics.truth_control_maximum_residual == 0.0
        @test metrics.raw_control_maximum_residual == 6.0
        @test metrics.reconciled_control_maximum_residual <=
            contract.control_absolute_tolerance
        @test metrics.sign_violation_count == 0
        @test metrics.structural_zero_violation_count == 0
        @test metrics.predetermined_violation_count == 0
        @test validate_benchmark_qualification(
            problem,
            result,
            metrics,
            contract,
        ) === nothing
    end

    @testset "Consistent redundancy and inconsistent infeasibility" begin
        independent_with_fixed_problem = rewrite_problem(
            problem;
            controls = LinearControl[
                control
                    for control in problem.controls
                    if control.control_id in (
                        "k01_noised_pair_total",
                        "k03_predetermined_cell",
                        "k04_structural_zero",
                    )
            ],
        )
        independent_with_fixed_result =
            reconcile_fixture_variant(independent_with_fixed_problem, contract)
        @test independent_with_fixed_result.exact_control_count == 3
        @test independent_with_fixed_result.adjustable_constraint_rank == 1
        @test independent_with_fixed_result.adjustable_control_count == 1
        @test independent_with_fixed_result.fixed_only_control_count == 2
        @test independent_with_fixed_result.dependent_adjustable_control_count ==
            0

        duplicate = LinearControl(
            "k06_consistent_duplicate",
            36.0,
            ["c01_high_confidence", "c02_low_confidence"],
            [1.0, 1.0],
            true,
            "PRODUCERS_PRICES",
            "ADVERSARIAL_CONSISTENT_REDUNDANCY",
        )
        redundant_problem = rewrite_problem(
            problem;
            controls = vcat(problem.controls, [duplicate]),
        )
        redundant_result =
            reconcile_fixture_variant(redundant_problem, contract)
        @test redundant_result.reconciled_values ≈
            result.reconciled_values atol = 1.0e-14
        @test redundant_result.adjustable_constraint_rank == 2
        @test redundant_result.exact_control_count == 6
        @test redundant_result.adjustable_control_count == 4
        @test redundant_result.fixed_only_control_count == 2
        @test redundant_result.dependent_adjustable_control_count == 2
        @test redundant_result.maximum_reconciled_control_residual <=
            contract.control_absolute_tolerance

        conflict = rewrite_control(
            duplicate;
            control_id = "k06_inconsistent_duplicate",
            rhs = 37.0,
            provenance = "ADVERSARIAL_INCONSISTENT_REDUNDANCY",
        )
        infeasible_problem = rewrite_problem(
            problem;
            controls = vcat(problem.controls, [conflict]),
        )
        @test_throws InfeasibleControlsError reconcile_fixture_variant(
            infeasible_problem,
            contract,
        )

        fixed_conflict = LinearControl(
            "k06_fixed_cell_conflict",
            6.0,
            ["c03_predetermined"],
            [1.0],
            true,
            "PRODUCERS_PRICES",
            "ADVERSARIAL_FIXED_CELL_CONFLICT",
        )
        @test_throws InfeasibleControlsError reconcile_fixture_variant(
            rewrite_problem(
                problem;
                controls = vcat(problem.controls, [fixed_conflict]),
            ),
            contract,
        )
    end

    @testset "Fail-closed reliability, covariance, sign, zero, and basis" begin
        missing_reliability = replace_cell_by_id(
            problem,
            "c01_high_confidence";
            reliability_class_id = "missing_reliability_v1",
        )
        @test_throws MissingReliabilityClassError reconcile_fixture_variant(
            missing_reliability,
            contract,
        )

        missing_covariance_contract = deepcopy(contract)
        delete!(
            missing_covariance_contract.covariance_classes,
            "independent_measurement_v1",
        )
        @test_throws MissingCovarianceClassError validate_stone_contract(
            missing_covariance_contract,
        )
        @test_throws MissingCovarianceClassError reconcile_fixture_variant(
            problem,
            missing_covariance_contract,
        )

        sign_mutation_problem =
            replace_control_by_id(problem, "k02_signed_pair_total"; rhs = 15.0)
        sign_mutation_problem = replace_control_by_id(
            sign_mutation_problem,
            "k05_grand_total_redundant";
            rhs = 56.0,
        )
        @test_throws SignMutationError reconcile_fixture_variant(
            sign_mutation_problem,
            contract,
        )

        zero_mutation_problem = replace_cell_by_id(
            problem,
            "c05_structural_zero";
            raw_value = 0.1,
        )
        @test_throws StructuralZeroMutationError reconcile_fixture_variant(
            zero_mutation_problem,
            contract,
        )

        unclassified_negative = replace_cell_by_id(
            problem,
            "c04_signed_negative";
            negative_economic_type = "",
        )
        @test_throws ReconciliationContractError reconcile_fixture_variant(
            unclassified_negative,
            contract,
        )

        mixed_basis_problem = replace_cell_by_id(
            problem,
            "c01_high_confidence";
            price_basis = "PURCHASERS_PRICES",
        )
        @test_throws MixedPriceBasisError reconcile_fixture_variant(
            mixed_basis_problem,
            contract,
        )
    end

    @testset "Ordinary RAS eligibility fails closed" begin
        signed = assess_ordinary_ras(
            [1.0 -1.0; 2.0 3.0];
            row_margins = [0.0, 5.0],
            column_margins = [3.0, 2.0],
            price_bases = ["PRODUCERS_PRICES"],
        )
        @test signed.status == "NOT_RUN_BLOCKED"
        @test !signed.eligible
        @test "SIGNED_CELLS_PRESENT" in signed.blockers

        unknown_margins = assess_ordinary_ras(
            [1.0 2.0; 3.0 4.0];
            price_bases = ["PRODUCERS_PRICES"],
        )
        @test !unknown_margins.eligible
        @test "UNKNOWN_MARGINS" in unknown_margins.blockers

        mixed_basis = assess_ordinary_ras(
            [1.0 2.0; 3.0 4.0];
            row_margins = [3.0, 7.0],
            column_margins = [4.0, 6.0],
            price_bases = ["PRODUCERS_PRICES", "PURCHASERS_PRICES"],
        )
        @test !mixed_basis.eligible
        @test "MIXED_PRICE_BASES" in mixed_basis.blockers

        conflicting = assess_ordinary_ras(
            [1.0 2.0; 3.0 4.0];
            row_margins = [3.0, 7.0],
            column_margins = [4.0, 7.0],
            price_bases = ["PRODUCERS_PRICES"],
        )
        @test !conflicting.eligible
        @test "CONFLICTING_MARGIN_TOTALS" in conflicting.blockers

        eligible_but_unimplemented = assess_ordinary_ras(
            [1.0 2.0; 3.0 4.0];
            row_margins = [3.0, 7.0],
            column_margins = [4.0, 6.0],
            price_bases = ["PRODUCERS_PRICES"],
        )
        @test eligible_but_unimplemented.eligible
        @test eligible_but_unimplemented.status == "NOT_RUN_BLOCKED"
        @test eligible_but_unimplemented.blockers ==
            ["ORDINARY_RAS_IMPLEMENTATION_NOT_INCLUDED"]
    end

    @testset "Preregistered comparators remain blocked" begin
        @test Set(assessment.method_id for assessment in comparators) ==
            Set(
            [
                "ORDINARY_RAS",
                "CROSS_ENTROPY_ROBINSON_2001",
                "CORRECTED_GRAS_LENZEN_2007",
            ],
        )
        @test all(
            assessment.status == "NOT_RUN_BLOCKED"
                for assessment in comparators
        )
        @test all(!assessment.eligible for assessment in comparators)
        cross_entropy = only(
            assessment
                for assessment in comparators
                if assessment.method_id ==
                "CROSS_ENTROPY_ROBINSON_2001"
        )
        corrected_gras = only(
            assessment
                for assessment in comparators
                if assessment.method_id ==
                "CORRECTED_GRAS_LENZEN_2007"
        )
        @test any(
            blocker -> occursin("PRIOR_ERROR_DISTRIBUTIONS", blocker),
            cross_entropy.blockers,
        )
        @test any(
            blocker -> occursin("ZERO_AND_SIGN_AWARE", blocker),
            corrected_gras.blockers,
        )
    end

    @testset "Permutation invariance and byte-deterministic report" begin
        permuted_problem = rewrite_problem(
            problem;
            cells = reverse(problem.cells),
            controls = LinearControl[
                rewrite_control(
                        control;
                        cell_ids = reverse(control.cell_ids),
                        coefficients = reverse(control.coefficients),
                    )
                    for control in reverse(problem.controls)
            ],
        )
        permuted_result = reconcile_stone(permuted_problem, contract)
        permuted_metrics =
            benchmark_metrics(permuted_problem, permuted_result, contract)
        permuted_comparators =
            benchmark_comparator_assessments(permuted_problem, contract)
        @test permuted_result.cell_ids == result.cell_ids
        @test permuted_result.raw_values == result.raw_values
        @test permuted_result.reconciled_values == result.reconciled_values
        @test permuted_result.prior_covariance == result.prior_covariance
        @test permuted_result.posterior_covariance ==
            result.posterior_covariance
        @test permuted_result.objective_value == result.objective_value
        @test permuted_metrics == metrics
        comparator_projection(items) = [
            (
                    item.schema_version,
                    item.method_id,
                    item.status,
                    item.eligible,
                    item.blockers,
                    item.citation_ids,
                    item.scientific_basis,
                ) for item in items
        ]
        @test comparator_projection(permuted_comparators) ==
            comparator_projection(comparators)

        mktempdir() do first_directory
            mktempdir() do second_directory
                first_written = write_stone_reconciliation_report(
                    first_directory,
                    contract,
                    problem,
                    result,
                    metrics,
                    comparators,
                )
                second_written = write_stone_reconciliation_report(
                    second_directory,
                    contract,
                    permuted_problem,
                    permuted_result,
                    permuted_metrics,
                    permuted_comparators,
                )
                @test first_written.adjustment_sha256 ==
                    second_written.adjustment_sha256
                @test first_written.control_sha256 ==
                    second_written.control_sha256
                @test first_written.metrics_sha256 ==
                    second_written.metrics_sha256
                @test first_written.comparator_sha256 ==
                    second_written.comparator_sha256
                @test first_written.manifest_sha256 ==
                    second_written.manifest_sha256
                @test read(first_written.adjustment_path) ==
                    read(second_written.adjustment_path)
                @test read(first_written.control_path) ==
                    read(second_written.control_path)
                @test read(first_written.metrics_path) ==
                    read(second_written.metrics_path)
                @test read(first_written.comparator_path) ==
                    read(second_written.comparator_path)
                @test read(first_written.manifest_path) ==
                    read(second_written.manifest_path)

                written_metrics = TOML.parsefile(first_written.metrics_path)
                @test written_metrics["raw_root_mean_square_error"] ==
                    metrics.raw_root_mean_square_error
                @test written_metrics[
                    "reconciled_root_mean_square_error",
                ] == metrics.reconciled_root_mean_square_error
                @test written_metrics[
                    "root_mean_square_error_improvement",
                ] == metrics.root_mean_square_error_improvement
                @test written_metrics["raw_mean_absolute_error"] ==
                    metrics.raw_mean_absolute_error
                @test written_metrics[
                    "reconciled_mean_absolute_error",
                ] == metrics.reconciled_mean_absolute_error
                @test written_metrics[
                    "mean_absolute_error_improvement",
                ] == metrics.mean_absolute_error_improvement
                @test !written_metrics["promotion_ready"]
                @test !written_metrics["model_state_write"]
                @test written_metrics["accounting_gate_effect"] == "NONE"

                manifest = TOML.parsefile(first_written.manifest_path)
                @test manifest["contract_sha256"] ==
                    APPROVED_CONTRACT_SHA256
                @test manifest["fixture_sha256"] ==
                    APPROVED_FIXTURE_SHA256
                @test manifest["artifact_count"] == 4
                @test !manifest["forecast_origin_admissible"]
                @test !manifest["promotion_ready"]
                @test !manifest["model_state_write"]
                @test manifest["accounting_gate_effect"] == "NONE"
                @test all(
                    artifact["sha256"] ==
                        file_sha256(
                            joinpath(
                                first_directory,
                                artifact["file_name"],
                            ),
                        )
                        for artifact in manifest["artifact"]
                )
            end
        end
    end
end
