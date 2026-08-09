using Test

length(ARGS) == 1 ||
    error(
    "usage: test_accounting_transition_runner.jl OUTPUT_DIRECTORY",
)

include(joinpath(@__DIR__, "USAccountingTransitionHarness.jl"))
using .USAccountingTransitionHarness

contract = load_contract()
actual_envelope =
    USAccountingTransitionHarness.USOpeningAccountingCandidate.current_execution_envelope()

if actual_envelope == contract.execution_envelope
    @testset "Canonical accounting-transition runner" begin
        report = run_harness(contract)
        written = write_report(report, contract, only(ARGS))
        @test written.record_count == 1_508
        @test isfile(written.records_path)
        @test isfile(written.manifest_path)
    end
else
    @testset "Off-envelope accounting-transition rejection" begin
        captured = try
            run_harness(contract)
            nothing
        catch error
            error
        end
        mismatch_type =
            USAccountingTransitionHarness.USOpeningAccountingCandidate.ExecutionEnvelopeMismatch
        @test captured isa mismatch_type
        if captured isa mismatch_type
            @test captured.expected == contract.execution_envelope
            @test captured.actual == actual_envelope
            @test !isempty(captured.mismatches)
        end
        @test !ispath(only(ARGS))
    end
end
