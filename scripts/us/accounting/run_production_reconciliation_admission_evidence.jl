#!/usr/bin/env julia

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

length(ARGS) == 1 ||
    error(
    "usage: julia --project=scripts/us " *
        "scripts/us/accounting/" *
        "run_production_reconciliation_admission_evidence.jl " *
        "OUTPUT_DIRECTORY",
)

written = write_production_reconciliation_admission_evidence_report(ARGS[1])
report = written.report
println("evidence_hash=", report.evidence_hash)
println("source_display_records=", length(report.source_display_records))
println(
    "release_marker_receipts=",
    length(report.release_marker_receipts),
)
println(
    "valuation_import_boundaries=",
    length(report.valuation_import_boundaries),
)
println("domestic_use_points=", length(report.domestic_use_points))
println("observation_loadings=", length(report.observation_loadings))
println("control_diagnostics=", length(report.control_diagnostics))
println("negative_cells=", length(report.negative_cells))
println("dependence_groups=", length(report.dependence_groups))
println("revision_vintages=", length(report.revision_vintages))
println("solver_input_cells=", report.solver_input_cell_count)
println("solver_input_controls=", report.solver_input_control_count)
println("forecast_origin_admissible=", report.forecast_origin_admissible)
println("promotion_ready=", report.promotion_ready)
println("manifest_sha256=", written.manifest_sha256)
