#!/usr/bin/env julia

length(ARGS) == 1 ||
    error(
    "usage: run_inventory_transition_evidence_ledger.jl OUTPUT_DIRECTORY",
)

include(joinpath(@__DIR__, "UST10105Controls.jl"))
include(joinpath(@__DIR__, "USBEAInventoryStockDiagnostic.jl"))
include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"))
include(joinpath(@__DIR__, "USInventoryStockLedger.jl"))
include(joinpath(@__DIR__, "USInventoryTransitionEvidenceLedger.jl"))

using .USInventoryTransitionEvidenceLedger

contract = load_inventory_transition_contract()
report = build_inventory_transition_evidence(contract)
written = write_inventory_transition_evidence(
    report,
    contract,
    only(ARGS),
)

println("observation_count=$(written.observation_count)")
println("source_check_count=$(written.source_check_count)")
println("blocked_transition_count=$(written.blocked_transition_count)")
println("observations_sha256=$(written.observations_sha256)")
println("checks_sha256=$(written.checks_sha256)")
println("transitions_sha256=$(written.transitions_sha256)")
println("manifest_sha256=$(written.manifest_sha256)")
println(
    "f030_cell_minus_published_control_millions=" *
        "$(report.summary.f030_cell_minus_published_control_millions)",
)
println(
    "f030_published_control_minus_t10105_2024_millions=" *
        "$(report.summary.f030_published_control_minus_t10105_2024_millions)",
)
println("model_inventory_vector_emitted=false")
println("s_s_emitted=false")
println("model_state_write=false")
println("forecast_origin_admissible=false")
println("accounting_gate_effect=NONE")
