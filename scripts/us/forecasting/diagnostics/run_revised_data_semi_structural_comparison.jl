#!/usr/bin/env julia

using LinearAlgebra

include("USRevisedDataSemiStructuralComparison.jl")
using .USRevisedDataSemiStructuralComparison

const BASE =
    USRevisedDataSemiStructuralComparison.USRevisedDataBenchmarkDiagnostic
const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const FIXTURE_DIRECTORY = joinpath(@__DIR__, "revised_data", "fixtures")
const DEFAULT_OUTPUT_DIRECTORY = joinpath(
    REPOSITORY_ROOT,
    "output",
    "us_forecasting",
    "revised_data_semi_structural_comparison",
)

function main(args)
    length(args) <= 1 ||
        throw(
        ArgumentError(
            "usage: run_revised_data_semi_structural_comparison.jl [output-directory]",
        ),
    )
    Threads.nthreads() == 1 ||
        throw(
        ArgumentError(
            "canonical comparison execution requires JULIA_NUM_THREADS=1",
        ),
    )
    BLAS.get_num_threads() == 1 ||
        throw(
        ArgumentError(
            "canonical comparison execution requires OPENBLAS_NUM_THREADS=1",
        ),
    )

    output_directory =
        isempty(args) ? DEFAULT_OUTPUT_DIRECTORY : abspath(only(args))
    panel = BASE.load_revised_quarterly_panel(
        joinpath(FIXTURE_DIRECTORY, "quarterly_panel.csv"),
        joinpath(FIXTURE_DIRECTORY, "manifest.toml"),
    )
    result = run_revised_semi_structural_comparison(panel)
    written =
        write_revised_semi_structural_comparison(result, output_directory)

    println("contract_id=$(result.contract_id)")
    println("information_track=$(result.information_track)")
    println("comparison_targets=$(length(result.target_ids))")
    println("models=$(length(result.model_ids))")
    println("forecast_cells=$(length(result.forecast_cells))")
    println("model_origin_diagnostics=$(length(result.model_origin_diagnostics))")
    println("failures=$(length(result.failures))")
    println("score_summaries=$(length(result.summaries))")
    println("relative_scores=$(length(result.relative_scores))")
    println("weighted_relative_scores=$(length(result.weighted_relative_scores))")
    println("semi_structural_model_id=$(result.semi_structural_model_id)")
    println("dsge_benchmark_included=$(result.dsge_benchmark_included)")
    println("abm_forecast_included=$(result.abm_forecast_included)")
    println("output_directory=$(abspath(output_directory))")
    for (name, digest) in sort!(collect(written.hashes); by = first)
        println("$(name)_sha256=$digest")
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
