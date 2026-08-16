#!/usr/bin/env julia

# First-pass comparison of the BeforeIT U.S. agent-based model against the ten
# statistical benchmark models on the revised-data panel.
#
#   usage: run_revised_data_abm_comparison.jl <output-directory> [paths] [variant] [max-origins]
#                                             [--calibration=<path>] [--also-score=<dir>]
#                                             [--force-recompute] [--adopt-cache-identity]
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
using SHA

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
    load_extra_abm_column(directory, own_identity)

Read another run's cached ensemble summaries so its ABM columns can be scored beside
this run's. The sourced cache is only admitted after its own identity document
agrees with this run on every field that would change a forecast: the scoring panel,
the requested path count, the seed contract and the code that produced it. A variant
label alone is not provenance.
"""
function load_extra_abm_column(directory, own_identity, own_origin_indices)
    cache = joinpath(directory, "abm_ensemble_summaries.csv")
    isfile(cache) || throw(ArgumentError("no abm_ensemble_summaries.csv in $directory"))
    identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME)
    stored = ABM.read_cache_identity(identity_path)

    # (c) Identity parity. comparison_code_sha256 and julia_version are included:
    # a matched-seed contrast between columns produced by different implementations
    # or different RNG versions is not a contrast at all.
    for field in (
            "panel_sha256",
            "panel_manifest_sha256",
            "paths_requested",
            "seed_contract_id",
            "contract_id",
            "base_diagnostic_code_sha256",
            "comparison_code_sha256",
            "runtime_source_tree_sha256",
            "julia_version",
            "model_scale",
            "simulated_quarters",
        )
        haskey(own_identity, field) || continue
        want = own_identity[field]
        got = get(stored, field, nothing)
        got === nothing && throw(
            ABM.CacheIdentityError(
                field,
                "--also-score source $directory has no $field; its columns cannot " *
                    "be shown to be comparable with this run",
            ),
        )
        matched = (want isa Real && got isa Real) ? want == got :
            string(want) == string(got)
        matched || throw(
            ABM.CacheIdentityError(
                field,
                "--also-score source $directory has $(repr(got)) but this run has " *
                    "$(repr(want)); the two columns would not be comparable",
            ),
        )
    end

    # (b) Diagnostics are mandatory: without them the companion's path accounting
    # and origin coverage cannot be established at all.
    diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv")
    isfile(diagnostics_path) || throw(
        ABM.CacheIdentityError(
            "abm_origin_diagnostics.csv",
            "--also-score source $directory has no origin diagnostics; its origin " *
                "coverage and path accounting cannot be established",
        ),
    )
    other_diagnostics =
        ABM.read_struct_csv(diagnostics_path, ABM.ABMOriginDiagnostic)
    isempty(other_diagnostics) && throw(
        ABM.CacheIdentityError(
            "abm_origin_diagnostics.csv",
            "--also-score source $directory has empty origin diagnostics",
        ),
    )
    unresolved = count(row -> row.paths_used != row.paths_requested, other_diagnostics)
    unresolved == 0 || throw(
        ABM.CacheIdentityError(
            "paths_used",
            "--also-score source $directory has $unresolved origin(s) with " *
                "unresolved path failures; its columns are smaller ensembles",
        ),
    )
    for row in other_diagnostics
        row.paths_requested == own_identity["paths_requested"] || throw(
            ABM.CacheIdentityError(
                "paths_requested",
                "--also-score source $directory origin $(row.origin_period) used " *
                    "$(row.paths_requested) paths but this run requests " *
                    "$(own_identity["paths_requested"])",
            ),
        )
    end

    summaries = ABM.read_struct_csv(cache, ABM.EnsembleSummary)
    isempty(summaries) && throw(ArgumentError("empty ensemble cache in $directory"))
    names = unique(getfield.(summaries, :variant))
    length(names) == 1 ||
        throw(ArgumentError("cache in $directory mixes variants $(names)"))

    # (d) Three-way consistency: identity, diagnostics and summaries must agree on
    # the variant, the origin set and the row counts. A forged identity that claims
    # origins its diagnostics and rows do not carry is refused here.
    identity_origins = Set(Int.(stored["origin_indices"]))
    diagnostic_origins = Set(getfield.(other_diagnostics, :origin_index))
    summary_origins = Set(getfield.(summaries, :origin_index))
    diagnostic_variants = unique(getfield.(other_diagnostics, :variant))
    (
        length(diagnostic_variants) == 1 && only(diagnostic_variants) == only(names) &&
            String(stored["variant"]) == only(names)
    ) || throw(
        ABM.CacheIdentityError(
            "variant",
            "--also-score source $directory disagrees on its own variant: identity " *
                "$(repr(stored["variant"])), diagnostics $(diagnostic_variants), " *
                "summaries $(names)",
        ),
    )
    diagnostic_origins == summary_origins || throw(
        ABM.CacheIdentityError(
            "origin_indices",
            "--also-score source $directory has diagnostics for " *
                "$(length(diagnostic_origins)) origin(s) but ensemble rows for " *
                "$(length(summary_origins)); the cache is internally inconsistent",
        ),
    )
    identity_origins == diagnostic_origins || throw(
        ABM.CacheIdentityError(
            "origin_indices",
            "--also-score source $directory identity claims " *
                "$(length(identity_origins)) origin(s) but carries " *
                "$(length(diagnostic_origins)); the identity does not describe the cache",
        ),
    )
    row_counts = Dict{Int, Int}()
    for row in summaries
        row_counts[row.origin_index] = get(row_counts, row.origin_index, 0) + 1
    end
    bad_rows = sort!(
        [
            index for (index, count) in row_counts
                if count != ABM.ENSEMBLE_ROWS_PER_ORIGIN
        ],
    )
    isempty(bad_rows) || throw(
        ABM.CacheIdentityError(
            "ensemble_row_count",
            "--also-score source $directory has origin(s) $bad_rows with a row " *
                "count other than $(ABM.ENSEMBLE_ROWS_PER_ORIGIN)",
        ),
    )

    # (a) Exact origin-set equality with the primary run. A one-origin companion
    # scored beside a 61-origin primary is not a comparison; it silently shrinks
    # the common cell set while the combined output still claims canonical coverage.
    own_set = Set(own_origin_indices)
    own_set == diagnostic_origins || throw(
        ABM.CacheIdentityError(
            "origin_indices",
            "--also-score source $directory covers $(length(diagnostic_origins)) " *
                "origin(s) but this run covers $(length(own_set)); a companion column " *
                "must cover exactly the same origins",
        ),
    )

    provenance = Dict{String, Any}(
        "source_directory" =>
            relpath(abspath(directory), ABM.REPOSITORY_ROOT),
        "variant" => stored["variant"],
        "paths_requested" => stored["paths_requested"],
        "origin_count" => length(diagnostic_origins),
        "calibration_object_path" => stored["calibration_object_path"],
        "calibration_object_sha256" => stored["calibration_object_sha256"],
        "comparison_code_sha256" => stored["comparison_code_sha256"],
        "runtime_source_tree_sha256" => get(stored, "runtime_source_tree_sha256", "absent"),
        "panel_sha256" => stored["panel_sha256"],
        "julia_version" => stored["julia_version"],
        "adopted_from_legacy_cache" =>
            get(stored, "adopted_from_legacy_cache", false),
        "ensemble_cache_sha256" => bytes2hex(SHA.sha256(read(cache))),
        "identity_sha256" => bytes2hex(SHA.sha256(read(identity_path))),
    )
    return (select_variant(only(names)), summaries, provenance, diagnostic_origins)
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
                "[max-origins] [--calibration=<path>] [--also-score=<dir>] " *
                "[--force-recompute] [--adopt-cache-identity]",
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
    force_recompute = "--force-recompute" in raw_args
    adopt_cache_identity = "--adopt-cache-identity" in raw_args
    upgrade_cache_identity = "--upgrade-cache-identity" in raw_args

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

    identity_path = joinpath(output_directory, ABM.CACHE_IDENTITY_FILENAME)
    identity = ABM.build_cache_identity(
        variant,
        origins;
        paths = paths,
        calibration_path = calibration_path,
        panel = panel,
    )

    simulated = ABM.simulate_abm_ensembles(
        variant,
        origins;
        paths = paths,
        cache_path = cache_path,
        diagnostics_path = diagnostics_path,
        calibration_path = calibration_path,
        path_failures_path = path_failures_path,
        identity_path = identity_path,
        identity = identity,
        force_recompute = force_recompute,
        adopt_legacy_identity = adopt_cache_identity,
        upgrade_identity_schema = upgrade_cache_identity,
    )
    check_cached_path_count(simulated.diagnostics, paths)
    println("cache_identity=$(relpath(identity_path, ABM.REPOSITORY_ROOT))")
    println("cache_identity_adopted_from_legacy=$(simulated.identity_adopted)")
    println("cache_identity_upgraded_to_schema_2=$(simulated.identity_upgraded)")

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
    extra_provenance = Dict{String, Any}[]
    extra_origin_sets = Set{Int}[]
    if also_score_directory !== nothing
        other = load_extra_abm_column(
            abspath(also_score_directory),
            identity,
            [entry[1] for entry in origins],
        )
        push!(extra_columns, (other[1], other[2]))
        push!(extra_provenance, other[3])
        push!(extra_origin_sets, other[4])
        println("also_scored_variant=$(other[1].name)")
        println("also_scored_rows=$(length(other[2]))")
        println("also_scored_origins=$(length(other[4]))")
        println("also_scored_source=$(other[3]["source_directory"])")
    end

    result = ABM.run_abm_comparison(
        panel,
        simulated.summaries,
        simulated.diagnostics,
        variant;
        paths = paths,
        extra_columns = extra_columns,
        extra_column_provenance = extra_provenance,
        extra_origin_sets = extra_origin_sets,
    )
    written = ABM.write_abm_comparison(result, output_directory)

    println("contract_id=$(result.contract_id)")
    println("canonical_origin_count=$(result.canonical_origin_count)")
    println("observed_origin_count=$(result.observed_origin_count)")
    println("path_incomplete_origin_count=$(result.path_incomplete_origin_count)")
    println("minimum_paths_used=$(result.minimum_paths_used)")
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
