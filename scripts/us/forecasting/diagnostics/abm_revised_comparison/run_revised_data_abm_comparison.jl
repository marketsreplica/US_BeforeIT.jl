#!/usr/bin/env julia

# First-pass comparison of the BeforeIT U.S. agent-based model against the ten
# statistical benchmark models on the revised-data panel.
#
#   usage: run_revised_data_abm_comparison.jl <output-directory> [paths] [variant] [max-origins]
#                                             [--calibration=<path>] [--also-score=<dir>]
#
#   variant = headline | burnin | outlook | headline_v2 | outlook_v2  (default headline)
#   --calibration  calibration artifact to initialise the model from. Defaults to the
#                  shipped artifact for v1 variants and to the commodity-balance
#                  reconciled artifact for the *_v2 variants.
#   --also-score   directory holding another completed run''s abm_ensemble_summaries.csv;
#                  its ABM columns are scored on the same common cells, giving a v1-vs-v2
#                  side-by-side in one table.
#   paths       Monte-Carlo paths per origin (default: variant default)
#   max-origins truncate the origin list, for smoke runs (default: all)
#
# Ensemble simulation is appended to the output directory after every origin,
# so an interrupted run resumes from the cache instead of restarting.

using LinearAlgebra

include("USRevisedDataABMComparison.jl")
using .USRevisedDataABMComparison

const ABM = USRevisedDataABMComparison
const BASE = USRevisedDataABMComparison.BASE
const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const FIXTURE_DIRECTORY =
    joinpath(REPOSITORY_ROOT, "scripts", "us", "forecasting", "diagnostics", "revised_data", "fixtures")
const DEFAULT_OUTPUT_DIRECTORY = joinpath(
    REPOSITORY_ROOT,
    "output",
    "us_forecasting",
    "abm_revised_comparison",
)

# Origins beyond the end of the revised panel. Unscored by construction.
const OUTLOOK_ORIGIN_PERIODS = ["2025Q4", "2026Q1"]

function cli_option(name, default)
    prefix = "--" * name * "="
    for argument in ARGS
        startswith(argument, prefix) && return argument[(length(prefix) + 1):end]
    end
    return default
end

positional(args) = [argument for argument in args if !startswith(argument, "--")]

function select_variant(name)
    name == "headline" && return ABM.HEADLINE_VARIANT
    name == "burnin" && return ABM.BURN_IN_VARIANT
    name == "outlook" && return ABM.OUTLOOK_VARIANT
    name == "headline_v2" && return ABM.HEADLINE_V2_VARIANT
    name == "outlook_v2" && return ABM.OUTLOOK_V2_VARIANT
    # burninN builds the model N quarters before the origin and steps N times,
    # so the origin row is row N+1. A one-quarter burn-in only moves the opening
    # discontinuity from h=2 to h=1; longer burn-ins test whether it decays.
    matched = match(r"^burnin([1-9][0-9]*)$", name)
    matched === nothing && throw(ArgumentError("unknown variant $(repr(name))"))
    quarters = parse(Int, matched.captures[1])
    return ABM.ABMVariant(
        name,
        "beforeit_abm_us_v1_mean_$name",
        "beforeit_abm_us_v1_median_$name",
        quarters,
        128,
    )
end

"""
    load_extra_abm_column(directory)

Read a completed run's cached ensemble summaries and return the `(variant, summaries)`
pair so its ABM columns can be scored beside this run's on identical common cells.
"""
function load_extra_abm_column(directory)
    cache = joinpath(directory, "abm_ensemble_summaries.csv")
    isfile(cache) || throw(ArgumentError("no abm_ensemble_summaries.csv in $directory"))
    summaries = ABM.read_struct_csv(cache, ABM.EnsembleSummary)
    isempty(summaries) && throw(ArgumentError("empty ensemble cache in $directory"))
    names = unique(getfield.(summaries, :variant))
    length(names) == 1 ||
        throw(ArgumentError("cache in $directory mixes variants $(names)"))
    return (select_variant(only(names)), summaries)
end

function scored_origins(panel)
    return [
        (index, panel.periods[index]) for
            index in BASE.MINIMUM_TRAINING_QUARTERS:(length(panel.periods) - 1)
    ]
end

function outlook_origins()
    return [
        (ABM.origin_index_for_period(period), period) for
            period in OUTLOOK_ORIGIN_PERIODS
    ]
end

function check_cached_path_count(diagnostics, paths)
    for row in diagnostics
        row.paths_requested == paths || throw(
            ArgumentError(
                "cached origin $(row.origin_period) used $(row.paths_requested) paths " *
                    "but this run requests $paths; use a different output directory",
            ),
        )
    end
    return nothing
end

function main(raw_args)
    args = positional(raw_args)
    1 <= length(args) <= 4 || throw(
        ArgumentError(
            "usage: run_revised_data_abm_comparison.jl <output-directory> [paths] [variant] " *
                "[max-origins] [--calibration=<path>] [--also-score=<dir>]",
        ),
    )
    output_directory = abspath(args[1])
    variant_name = length(args) >= 3 ? args[3] : "headline"
    variant = select_variant(variant_name)
    paths = length(args) >= 2 ? parse(Int, args[2]) : variant.default_paths
    max_origins = length(args) >= 4 ? parse(Int, args[4]) : typemax(Int)

    default_calibration =
        endswith(variant.name, "_v2") ? ABM.RECONCILED_CALIBRATION_OBJECT_PATH :
        ABM.CALIBRATION_OBJECT_PATH
    calibration_path = abspath(cli_option("calibration", default_calibration))
    isfile(calibration_path) ||
        throw(ArgumentError("calibration artifact not found: $calibration_path"))
    ABM.ACTIVE_CALIBRATION_PATH[] = calibration_path
    also_score_directory = cli_option("also-score", nothing)

    Threads.nthreads() == 1 || @warn "JULIA_NUM_THREADS is not 1; statistical benchmark reproduction may differ"
    BLAS.get_num_threads() == 1 || @warn "OPENBLAS_NUM_THREADS is not 1; statistical benchmark reproduction may differ"

    mkpath(output_directory)
    cache_path = joinpath(output_directory, "abm_ensemble_summaries.csv")
    diagnostics_path =
        joinpath(output_directory, "abm_origin_diagnostics.csv")
    path_failures_path =
        joinpath(output_directory, "abm_path_failures.log")

    panel = BASE.load_revised_quarterly_panel(
        joinpath(FIXTURE_DIRECTORY, "quarterly_panel.csv"),
        joinpath(FIXTURE_DIRECTORY, "manifest.toml"),
    )

    is_outlook = startswith(variant.name, "outlook")
    origins = is_outlook ? outlook_origins() : scored_origins(panel)
    origins = origins[1:min(length(origins), max_origins)]

    println("variant=$(variant.name)")
    println("calibration_object=$calibration_path")
    println("monte_carlo_paths=$paths")
    println("origins=$(length(origins))")
    println("output_directory=$output_directory")

    simulated = ABM.simulate_abm_ensembles(
        variant,
        origins;
        paths = paths,
        cache_path = cache_path,
        diagnostics_path = diagnostics_path,
        calibration_path = calibration_path,
        path_failures_path = path_failures_path,
    )
    check_cached_path_count(simulated.diagnostics, paths)

    println("abm_origins_simulated=$(length(simulated.diagnostics))")
    println(
        "abm_path_failures=$(sum(getfield.(simulated.diagnostics, :paths_failed); init = 0))",
    )

    if is_outlook
        written = ABM.write_abm_outlook(
            simulated.summaries,
            simulated.diagnostics,
            output_directory;
            paths = paths,
        )
        println("scored=false")
        println("outlook_rows=$(length(simulated.summaries))")
        println("manifest=$(written.manifest_path)")
        return nothing
    end

    extra_columns = Tuple{ABM.ABMVariant, Vector{ABM.EnsembleSummary}}[]
    if also_score_directory !== nothing
        other = load_extra_abm_column(abspath(also_score_directory))
        push!(extra_columns, other)
        println("also_scored_variant=$(other[1].name)")
        println("also_scored_rows=$(length(other[2]))")
    end

    result = ABM.run_abm_comparison(
        panel,
        simulated.summaries,
        simulated.diagnostics,
        variant;
        paths = paths,
        extra_columns = extra_columns,
    )
    written = ABM.write_abm_comparison(result, output_directory)

    println("contract_id=$(result.contract_id)")
    println("information_track=$(result.information_track)")
    println("models=$(length(result.model_ids))")
    println("comparison_targets=$(length(result.target_ids))")
    println("forecast_cells=$(length(result.forecast_cells))")
    println("failures=$(length(result.failures))")
    println("score_summaries=$(length(result.summaries))")
    println("relative_scores=$(length(result.relative_scores))")
    println("weighted_relative_scores=$(length(result.weighted_relative_scores))")
    println("monte_carlo_errors=$(length(result.monte_carlo_errors))")
    for track in ABM.TRACKS
        counts = ABM.track_observation_counts(result, track)
        println("$(track)_observation_counts=$(counts)")
    end
    for (set_name, _) in ABM.SCORED_TARGET_SETS
        for model_id in (result.abm_mean_model_id, result.abm_median_model_id)
            for track in ABM.TRACKS
                score = ABM.weighted_score(result, track, set_name, model_id)
                score === nothing && continue
                println(
                    "$(model_id) $(set_name) $(track): " *
                        "status=$(score.status) " *
                        "rmse_ratio=$(score.weighted_macro_average_cellwise_rmse_ratio) " *
                        "mae_ratio=$(score.weighted_macro_average_cellwise_mae_ratio)",
                )
            end
        end
    end
    for (name, digest) in sort!(collect(written.hashes); by = first)
        println("$(name)_sha256=$digest")
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
