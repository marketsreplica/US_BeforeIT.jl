#!/usr/bin/env julia

length(ARGS) == 1 ||
    error(
    "usage: run_production_reconciliation_readiness.jl OUTPUT_DIRECTORY",
)

include(joinpath(@__DIR__, "USProductionReconciliationReadiness.jl"))

using .USProductionReconciliationReadiness

written = build_production_readiness_report(only(ARGS))
result = written.result
candidate = result.candidate

println("overall_status=$(result.overall_status)")
println("ready=$(result.ready)")
println("admission_evidence_hash=$(result.admission_evidence_hash)")
println("artifact_count=$(length(result.artifact_validations))")
println("probe_count=$(length(result.probe_results))")
println("source_family_count=$(length(result.source_families))")
println("criterion_count=$(length(result.criteria))")
println(
    "blocking_criterion_count=$(length(result.blocking_criterion_ids))",
)
println("blocker_count=$(length(result.blocker_ids))")
println(
    "admitted_solver_family_count=$(candidate.admitted_solver_family_count)",
)
println("solver_input_cell_count=$(candidate.solver_input_cell_count)")
println(
    "solver_input_control_count=$(candidate.solver_input_control_count)",
)
println("solver_invoked=$(candidate.solver_invoked)")
println("reconciliation_run_count=$(candidate.reconciliation_run_count)")
println("adjustment_record_count=$(candidate.adjustment_record_count)")
println("artifact_report_sha256=$(written.artifact_sha256)")
println("probe_report_sha256=$(written.probe_sha256)")
println("source_registry_sha256=$(written.source_sha256)")
println("blocker_report_sha256=$(written.blocker_sha256)")
println("criterion_report_sha256=$(written.criterion_sha256)")
println("admission_overlay_sha256=$(written.admission_overlay_sha256)")
println("status_sha256=$(written.status_sha256)")
println("manifest_sha256=$(written.manifest_sha256)")
println("forecast_origin_admissible=false")
println("promotion_ready=false")
println("model_state_write=false")
println("accounting_gate_effect=NONE")
println("forecast_score_effect=NONE")
