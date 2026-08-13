#!/usr/bin/env julia

length(ARGS) == 1 ||
    error(
    "usage: run_constrained_stone_reconciliation.jl OUTPUT_DIRECTORY",
)

include(joinpath(@__DIR__, "USConstrainedStoneReconciliation.jl"))

using .USConstrainedStoneReconciliation

qualification = run_synthetic_benchmark()
written = write_stone_reconciliation_report(
    only(ARGS),
    qualification.contract,
    qualification.problem,
    qualification.result,
    qualification.metrics,
    qualification.comparators,
)

println("method_id=$(qualification.result.method_id)")
println("method_version=$(qualification.result.method_version)")
println("fixture_id=$(qualification.problem.fixture_id)")
println("cell_count=$(length(qualification.problem.cells))")
println("adjustable_cell_count=$(qualification.result.adjustable_cell_count)")
println("exact_control_count=$(qualification.result.exact_control_count)")
println(
    "adjustable_constraint_rank=" *
        "$(qualification.result.adjustable_constraint_rank)",
)
println(
    "adjustable_control_count=" *
        "$(qualification.result.adjustable_control_count)",
)
println(
    "fixed_only_control_count=" *
        "$(qualification.result.fixed_only_control_count)",
)
println(
    "dependent_adjustable_control_count=" *
        "$(qualification.result.dependent_adjustable_control_count)",
)
println("objective_value=$(qualification.result.objective_value)")
println(
    "raw_vs_truth_rmse=" *
        "$(qualification.metrics.raw_root_mean_square_error)",
)
println(
    "reconciled_vs_truth_rmse=" *
        "$(qualification.metrics.reconciled_root_mean_square_error)",
)
println(
    "rmse_improvement=" *
        "$(qualification.metrics.root_mean_square_error_improvement)",
)
println(
    "raw_vs_truth_mae=" *
        "$(qualification.metrics.raw_mean_absolute_error)",
)
println(
    "reconciled_vs_truth_mae=" *
        "$(qualification.metrics.reconciled_mean_absolute_error)",
)
println(
    "mae_improvement=" *
        "$(qualification.metrics.mean_absolute_error_improvement)",
)
println(
    "raw_covariance_weighted_rmse=" *
        "$(qualification.metrics.raw_covariance_weighted_root_mean_square_error)",
)
println(
    "reconciled_covariance_weighted_rmse=" *
        "$(qualification.metrics.reconciled_covariance_weighted_root_mean_square_error)",
)
println(
    "low_to_high_absolute_adjustment_ratio=" *
        "$(qualification.metrics.low_to_high_absolute_adjustment_ratio)",
)
println(
    "maximum_reconciled_control_residual=" *
        "$(qualification.result.maximum_reconciled_control_residual)",
)
println(
    "comparator_statuses=" *
        join(
        (
            assessment.method_id * ":" * assessment.status
                for assessment in qualification.comparators
        ),
        "|",
    ),
)
println("adjustment_ledger_sha256=$(written.adjustment_sha256)")
println("control_diagnostics_sha256=$(written.control_sha256)")
println("benchmark_metrics_sha256=$(written.metrics_sha256)")
println("comparator_status_sha256=$(written.comparator_sha256)")
println("report_manifest_sha256=$(written.manifest_sha256)")
println("forecast_origin_admissible=false")
println("promotion_ready=false")
println("model_state_write=false")
println("accounting_gate_effect=NONE")
