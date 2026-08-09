#!/usr/bin/env julia

using LinearAlgebra

include("USRevisedDataBenchmarkDiagnostic.jl")
using .USRevisedDataBenchmarkDiagnostic

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const FIXTURE_DIRECTORY = joinpath(@__DIR__, "revised_data", "fixtures")
const DEFAULT_OUTPUT_DIRECTORY =
    joinpath(REPOSITORY_ROOT, "output", "us_forecasting", "revised_data_diagnostic")

function main(args)
    length(args) <= 1 ||
        throw(
        ArgumentError(
            "usage: run_revised_data_benchmark_diagnostic.jl [output-directory]",
        ),
    )
    Threads.nthreads() == 1 ||
        throw(
        ArgumentError(
            "canonical diagnostic execution requires JULIA_NUM_THREADS=1",
        ),
    )
    BLAS.get_num_threads() == 1 ||
        throw(
        ArgumentError(
            "canonical diagnostic execution requires OPENBLAS_NUM_THREADS=1",
        ),
    )

    output_directory =
        isempty(args) ? DEFAULT_OUTPUT_DIRECTORY : abspath(only(args))
    panel = load_revised_quarterly_panel(
        joinpath(FIXTURE_DIRECTORY, "quarterly_panel.csv"),
        joinpath(FIXTURE_DIRECTORY, "manifest.toml"),
    )
    result = run_revised_benchmark_diagnostic(panel)
    written = write_revised_benchmark_diagnostic(result, output_directory)

    println("contract_id=$(result.contract_id)")
    println("information_track=$(result.information_track)")
    println("forecast_cells=$(length(result.forecast_cells))")
    println("model_origin_diagnostics=$(length(result.model_origin_diagnostics))")
    println("failures=$(length(result.failures))")
    println("score_summaries=$(length(result.summaries))")
    println("relative_scores=$(length(result.relative_scores))")
    println("weighted_relative_scores=$(length(result.weighted_relative_scores))")
    println("output_directory=$(abspath(output_directory))")
    for (name, digest) in sort!(collect(written.hashes); by = first)
        println("$(name)_sha256=$digest")
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
