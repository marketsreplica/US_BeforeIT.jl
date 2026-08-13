#!/usr/bin/env julia

length(ARGS) == 1 ||
    error(
    "usage: run_accounting_transition_harness.jl OUTPUT_DIRECTORY",
)

include(joinpath(@__DIR__, "USAccountingTransitionHarness.jl"))
using .USAccountingTransitionHarness

contract = load_contract()
report = run_harness(contract)
written = write_report(report, contract, only(ARGS))

println("record_count=$(written.record_count)")
println("records_sha256=$(written.records_sha256)")
println("manifest_sha256=$(written.manifest_sha256)")
println("origin_admissible=$(report.origin_admissible)")
println("promotion_eligible=$(report.promotion_eligible)")
println(
    "accuracy_selection_eligible=$(report.accuracy_selection_eligible)",
)
println(
    "runtime_selection_eligible=$(report.runtime_selection_eligible)",
)
