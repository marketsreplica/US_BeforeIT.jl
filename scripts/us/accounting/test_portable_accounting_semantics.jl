using Test

include(joinpath(@__DIR__, "USPortableAccountingSemantics.jl"))
using .USPortableAccountingSemantics

@testset "Platform-neutral opening construction and transitions" begin
    report = run_portable_semantic_validation()

    @test length(report.construction) == 2
    @test length(report.transitions) == 4
    @test report.runtime_source_tree_file_count > 0
    @test occursin(r"^[0-9a-f]{64}$", report.runtime_source_tree_sha256)
    @test report.actual_execution_envelope["julia_thread_count"] == 1
    @test report.actual_execution_envelope["blas_thread_count"] == 1
    @test !report.byte_identity_asserted
    @test !report.origin_admissible
    @test !report.promotion_eligible
    @test !report.accuracy_selection_eligible
    @test !report.runtime_selection_eligible

    @test all(
        summary ->
        !summary.origin_admissible &&
            !summary.promotion_eligible &&
            abs(summary.observed_expenditure_residual) <= 1.0 &&
            abs(summary.latent_expenditure_residual) > 1.0e-6 &&
            summary.maximum_simulated_nominal_residual <= 1.0e-6 &&
            summary.maximum_simulated_real_residual <= 1.0e-6 &&
            summary.maximum_simulated_income_residual <= 1.0e-6,
        report.construction,
    )
    @test all(
        summary ->
        summary.horizon == 12 &&
            !summary.origin_admissible &&
            !summary.promotion_eligible &&
            summary.maximum_nominal_transition_residual <= 1.0e-6 &&
            summary.maximum_real_transition_residual <= 1.0e-6 &&
            summary.maximum_income_residual <= 1.0e-6 &&
            summary.maximum_central_bank_residual <= 1.0e-6 &&
            summary.maximum_commercial_bank_residual <= 1.0e-6 &&
            summary.maximum_final_inventory_stock_flow_residual <=
            1.0e-6 &&
            summary.maximum_intermediate_inventory_stock_flow_residual <=
            1.0e-6 &&
            summary.minimum_price > 0 &&
            summary.minimum_final_inventory >= -1.0e-10 &&
            summary.minimum_intermediate_inventory >= -1.0e-10 &&
            summary.nonfinite_value_count == 0,
        report.transitions,
    )

    actual_bounds_mode =
        report.actual_execution_envelope["bounds_check_mode"]
    if actual_bounds_mode == "yes"
        @test !report.canonical_execution_envelope_match
        @test any(
            occursin("bounds_check_mode", mismatch)
                for mismatch in report.execution_envelope_mismatches
        )
        @test all(
            !summary.canonical_execution_envelope_match
                for summary in report.construction
        )
    end

    malformed = (
        parameters = Dict{Symbol, Any}(),
        initial_conditions = Dict{String, Any}(),
        metadata = Dict{String, Any}(),
        semantic_sha256 = "",
    )
    captured = try
        validate_portable_candidate(malformed)
        nothing
    catch error
        error
    end
    @test captured isa SemanticInvariantMismatch
    if captured isa SemanticInvariantMismatch
        @test captured.phase == "candidate construction"
        @test any(
            occursin("parameters must be Dict{String, Any}", mismatch)
                for mismatch in captured.mismatches
        )
    end
end
