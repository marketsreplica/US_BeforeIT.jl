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

using .USProductionReconciliationLedger

length(ARGS) == 1 ||
    error(
    "usage: julia --project=scripts/us " *
        "scripts/us/accounting/run_production_reconciliation_candidate_ledger.jl " *
        "OUTPUT_DIRECTORY",
)

result = write_production_reconciliation_ledger_report(ARGS[1])
println("problem_hash=", result.report.problem_hash)
println("cells=", length(result.report.cells))
println("controls=", length(result.report.controls))
println(
    "source_lineage_members=",
    length(result.report.source_lineage_members),
)
println(
    "target_raw_source_leaves=",
    sum(
        length(lineage.parent_source_keys)
            for lineage in result.report.target_lineages
    ),
)
println(
    "control_raw_source_leaves=",
    sum(
        length(lineage.parent_source_keys)
            for lineage in result.report.control_lineages
    ),
)
println("solver_input_cells=", result.report.solver_input_cell_count)
println("solver_input_controls=", result.report.solver_input_control_count)
println("manifest_sha256=", result.manifest_sha256)
