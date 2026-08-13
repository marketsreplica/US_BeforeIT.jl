#!/usr/bin/env julia

length(ARGS) == 1 ||
    error(
    "usage: run_used_other_evidence_ledger.jl OUTPUT_DIRECTORY",
)

include(joinpath(@__DIR__, "USUsedOtherEvidenceLedger.jl"))
using .USUsedOtherEvidenceLedger

contract = load_used_other_evidence_contract()
report = build_used_other_evidence(contract)
written = write_used_other_evidence(
    report,
    contract,
    only(ARGS),
)

println("observation_count=$(written.observation_count)")
println("component_count=$(written.component_count)")
println("source_check_count=$(written.source_check_count)")
println("blocked_decision_count=$(written.blocked_decision_count)")
println("literature_count=$(written.literature_count)")
println("observations_sha256=$(written.observations_sha256)")
println("components_sha256=$(written.components_sha256)")
println("source_checks_sha256=$(written.checks_sha256)")
println("decisions_sha256=$(written.decisions_sha256)")
println("literature_sha256=$(written.literature_sha256)")
println("manifest_sha256=$(written.manifest_sha256)")
println(
    "latest_detail_year=$(contract.detail_vintage_scope["latest_detail_year"])",
)
println(
    "newer_than_2017_detail_available=" *
        "$(contract.detail_vintage_scope["newer_than_2017_detail_available"])",
)
println("projected_2017_share_count=0")
println("dealer_margin_allocation_count=0")
println("transport_service_allocation_count=0")
println("component_allocation_2024_count=0")
println("core_absorption_count=0")
println("model_absorption_count=0")
println("model_state_write=false")
println("forecast_origin_admissible=false")
println("accounting_gate_effect=NONE")
println("forecast_score_write=false")
