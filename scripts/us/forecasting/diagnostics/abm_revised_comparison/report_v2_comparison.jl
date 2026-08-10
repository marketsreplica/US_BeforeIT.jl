#!/usr/bin/env julia

# Render the v1-vs-v2 tables from a joint comparison run, plus the empirical interval
# coverage of the v2 ensemble.
#
#   usage: report_v2_comparison.jl <joint-comparison-dir> [outlook-dir]
#
# The joint directory must have been produced by
#   run_revised_data_abm_comparison.jl <dir> <paths> headline_v2 --also-score=<v1 dir>
# so that both ABM columns were scored on identical common cells. Every number below is
# derived from the CSVs that run wrote; nothing is recomputed from a fresh simulation.
# Coverage is the one exception and is computed from the cached ensemble percentiles and
# the panel actuals, which are also both on disk.

using Printf
using Statistics

include("USRevisedDataABMComparison.jl")
using .USRevisedDataABMComparison

const ABM = USRevisedDataABMComparison
const BASE = USRevisedDataABMComparison.BASE

const ANCHOR = "beforeit_var_p1_constant"
const HEADLINE_SET = "headline_real_gdp_gdp_deflator"
const SECONDARY_SET = "secondary_nominal_gdp_effective_federal_funds_rate"
const V1_MEAN = "beforeit_abm_us_v1_mean"
const V1_MEDIAN = "beforeit_abm_us_v1_median"
const V2_MEAN = "beforeit_abm_us_v2_mean"
const V2_MEDIAN = "beforeit_abm_us_v2_median"
const SCORED_HORIZONS = BASE.HORIZONS
const FIXTURE_DIRECTORY = normpath(
    joinpath(@__DIR__, "..", "revised_data", "fixtures"),
)

read_csv(directory, name, T) =
    ABM.read_struct_csv(joinpath(directory, name), T)

function track_label(track)
    track == ABM.ALL_AVAILABLE_TRACK && return "all-available"
    track == ABM.BALANCED_H12_TRACK && return "balanced h=12"
    track == ABM.PANDEMIC_MASKED_TRACK && return "pandemic-masked"
    return track
end

# ---------------------------------------------------------------------------
# 1. weighted standings
# ---------------------------------------------------------------------------
function print_weighted_standings(weighted, track, target_set, title)
    rows = filter(
        row -> row.sample_track == track && row.target_set == target_set,
        weighted,
    )
    isempty(rows) && return nothing
    ranked = sort(rows; by = row -> row.weighted_macro_average_cellwise_rmse_ratio)
    println("\n**$title — `$(track_label(track))`**\n")
    println("| rank | model | status | weighted RMSE ratio | weighted MAE ratio |")
    println("|---:|---|---|---:|---:|")
    for (rank, row) in enumerate(ranked)
        marker =
            row.model_id in (V2_MEAN, V2_MEDIAN) ? "**" :
            row.model_id in (V1_MEAN, V1_MEDIAN) ? "_" : ""
        @printf(
            "| %d | %s%s%s | %s | %.4f | %.4f |\n",
            rank, marker, row.model_id, marker, row.status,
            row.weighted_macro_average_cellwise_rmse_ratio,
            row.weighted_macro_average_cellwise_mae_ratio,
        )
    end
    return nothing
end

# ---------------------------------------------------------------------------
# 2. per-cell RMSE ratio, rank, and the v1 -> v2 delta
# ---------------------------------------------------------------------------
function print_cell_delta(relative, summaries, track, targets)
    println("\n**Per-cell RMSE ratio vs `$ANCHOR` and rank among all scored models — `$(track_label(track))`**\n")
    println(
        "| target | h | n | v1 RMSE | v2 RMSE | v1 ratio | v2 ratio | v1 rank | v2 rank | ratio delta |",
    )
    println("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for target in targets, horizon in SCORED_HORIZONS
        cell = filter(
            row -> row.sample_track == track && row.target_id == target &&
                row.horizon == horizon,
            relative,
        )
        isempty(cell) && continue
        ordered = sort(cell; by = row -> row.rmse_ratio)
        ids = getfield.(ordered, :model_id)
        index_of(id) = something(findfirst(==(id), ids), 0)
        get_ratio(id) = begin
            hit = findfirst(row -> row.model_id == id, cell)
            hit === nothing ? NaN : cell[hit].rmse_ratio
        end
        get_rmse(id) = begin
            hit = findfirst(
                row -> row.sample_track == track && row.model_id == id &&
                    row.target_id == target && row.horizon == horizon,
                summaries,
            )
            hit === nothing ? NaN : summaries[hit].rmse
        end
        n = first(cell).observation_count
        @printf(
            "| `%s` | %d | %d | %.4f | %.4f | %.4f | %.4f | %d/%d | %d/%d | %+.4f |\n",
            target, horizon, n, get_rmse(V1_MEAN), get_rmse(V2_MEAN),
            get_ratio(V1_MEAN), get_ratio(V2_MEAN),
            index_of(V1_MEAN), length(ids), index_of(V2_MEAN), length(ids),
            get_ratio(V2_MEAN) - get_ratio(V1_MEAN),
        )
    end
    return nothing
end

# ---------------------------------------------------------------------------
# 3. bias by horizon (mean_error = forecast minus truth)
# ---------------------------------------------------------------------------
function print_bias_by_horizon(summaries, track, targets)
    println("\n**Bias by horizon (`mean_error` = forecast − truth, pp) — `$(track_label(track))`**\n")
    println("| target | h | n | v1 bias | v2 bias | v1 RMSE | v2 RMSE | v1 MASE | v2 MASE |")
    println("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for target in targets, horizon in SCORED_HORIZONS
        pick(id) = begin
            hit = findfirst(
                row -> row.sample_track == track && row.model_id == id &&
                    row.target_id == target && row.horizon == horizon,
                summaries,
            )
            hit === nothing ? nothing : summaries[hit]
        end
        v1 = pick(V1_MEAN)
        v2 = pick(V2_MEAN)
        (v1 === nothing || v2 === nothing) && continue
        @printf(
            "| `%s` | %d | %d | %+.3f | %+.3f | %.3f | %.3f | %.3f | %.3f |\n",
            target, horizon, v2.observation_count, v1.mean_error, v2.mean_error,
            v1.rmse, v2.rmse, v1.mase, v2.mase,
        )
    end
    return nothing
end

# ---------------------------------------------------------------------------
# 4. empirical interval coverage
# ---------------------------------------------------------------------------
"""
    coverage_table(ensembles, panel, model_label)

Share of realized values that fall inside the ensemble's 5–95 % and 10–90 % bands, per
target per horizon, across every origin whose target period exists in the panel. This is a
density-calibration statement about the raw ensemble, not about a scored point forecast:
nominal coverage is 90 % and 80 % respectively.
"""
function coverage_table(ensembles, panel, model_label)
    column_of = Dict(name => index for (index, name) in enumerate(panel.target_names))
    period_row = Dict(period => index for (index, period) in enumerate(panel.periods))
    rows = NamedTuple[]
    for target in ABM.ABM_TARGET_IDS, horizon in SCORED_HORIZONS
        inside_90 = 0
        inside_80 = 0
        inside_50 = 0
        total = 0
        for row in ensembles
            row.target_id == target && row.horizon == horizon || continue
            haskey(period_row, row.target_period) || continue
            haskey(column_of, target) || continue
            actual = panel.values[period_row[row.target_period], column_of[target]]
            isfinite(actual) || continue
            total += 1
            inside_90 += (row.percentile_05 <= actual <= row.percentile_95)
            inside_80 += (row.percentile_10 <= actual <= row.percentile_90)
            inside_50 += (row.percentile_25 <= actual <= row.percentile_75)
        end
        total == 0 && continue
        push!(
            rows,
            (;
                target, horizon, total,
                c90 = inside_90 / total, c80 = inside_80 / total, c50 = inside_50 / total,
            ),
        )
    end
    println("\n**Empirical interval coverage of the $model_label ensemble** (nominal 90 / 80 / 50 %)\n")
    println("| target | h | n | 5–95 % | 10–90 % | 25–75 % |")
    println("|---|---:|---:|---:|---:|---:|")
    for row in rows
        @printf(
            "| `%s` | %d | %d | %.3f | %.3f | %.3f |\n",
            row.target, row.horizon, row.total, row.c90, row.c80, row.c50,
        )
    end
    for target in unique(getfield.(rows, :target))
        subset = filter(row -> row.target == target, rows)
        @printf(
            "| `%s` **all h** | — | %d | **%.3f** | **%.3f** | **%.3f** |\n",
            target, sum(getfield.(subset, :total)),
            sum(row.c90 * row.total for row in subset) / sum(getfield.(subset, :total)),
            sum(row.c80 * row.total for row in subset) / sum(getfield.(subset, :total)),
            sum(row.c50 * row.total for row in subset) / sum(getfield.(subset, :total)),
        )
    end
    return rows
end

function write_coverage_csv(path, rows, model_id)
    open(path, "w") do io
        println(io, "model_id,target_id,horizon,observation_count,coverage_05_95,coverage_10_90,coverage_25_75")
        for row in rows
            @printf(
                io, "%s,%s,%d,%d,%.6f,%.6f,%.6f\n",
                model_id, row.target, row.horizon, row.total, row.c90, row.c80, row.c50,
            )
        end
    end
    return path
end

# ---------------------------------------------------------------------------
# 5. outlook
# ---------------------------------------------------------------------------
function print_outlook(directory)
    isdir(directory) || return nothing
    file = joinpath(directory, "current_outlook.csv")
    isfile(file) || return nothing
    ensembles = ABM.read_struct_csv(file, ABM.EnsembleSummary)
    for origin in unique(getfield.(ensembles, :origin_period))
        for target in ("real_gdp", "gdp_deflator", "unemployment_rate", "effective_federal_funds_rate")
            rows = sort(
                filter(
                    row -> row.origin_period == origin && row.target_id == target,
                    ensembles,
                );
                by = row -> row.horizon,
            )
            isempty(rows) && continue
            println("\n**Outlook, origin $origin, `$target`** (unscored, out of sample)\n")
            println("| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |")
            println("|---:|---|---:|---:|---:|---:|---:|---:|---:|")
            for row in rows
                row.horizon in (1, 2, 3, 4, 8, 12) || continue
                @printf(
                    "| %d | %s | %+.3f | %+.3f | %.3f | %+.3f | %+.3f | %+.3f | %+.3f |\n",
                    row.horizon, row.target_period, row.ensemble_mean, row.ensemble_median,
                    row.ensemble_sd, row.percentile_05, row.percentile_25,
                    row.percentile_75, row.percentile_95,
                )
            end
        end
    end
    return nothing
end

function main(args)
    1 <= length(args) <= 3 || throw(
        ArgumentError(
            "usage: report_v2_comparison.jl <joint-dir> [outlook-dir] [v1-dir]",
        ),
    )
    directory = abspath(args[1])
    outlook_directory = length(args) >= 2 ? abspath(args[2]) : nothing
    v1_directory = length(args) >= 3 ? abspath(args[3]) : nothing

    weighted = read_csv(directory, "weighted_relative_scores.csv", ABM.ABMWeightedScore)
    relative = read_csv(directory, "relative_scores.csv", BASE.RelativeScore)
    summaries = read_csv(directory, "score_summaries.csv", BASE.ScoreSummary)
    ensembles = read_csv(directory, "abm_ensemble_summaries.csv", ABM.EnsembleSummary)
    panel = BASE.load_revised_quarterly_panel(
        joinpath(FIXTURE_DIRECTORY, "quarterly_panel.csv"),
        joinpath(FIXTURE_DIRECTORY, "manifest.toml"),
    )

    println("# v1 vs v2 ABM comparison tables")
    println("\nSource: `$(relpath(directory))`")

    for track in ABM.TRACKS
        print_weighted_standings(
            weighted, track, HEADLINE_SET,
            "Headline pair {real_gdp, gdp_deflator}",
        )
    end
    for track in ABM.TRACKS
        print_weighted_standings(
            weighted, track, SECONDARY_SET,
            "Secondary pair {nominal_gdp, effective_federal_funds_rate}",
        )
    end
    print_cell_delta(
        relative, summaries, ABM.ALL_AVAILABLE_TRACK,
        ["real_gdp", "gdp_deflator", "nominal_gdp", "effective_federal_funds_rate"],
    )
    print_bias_by_horizon(
        summaries, ABM.ALL_AVAILABLE_TRACK,
        ["real_gdp", "gdp_deflator", "nominal_gdp", "unemployment_rate"],
    )

    v2_rows = coverage_table(ensembles, panel, "v2")
    coverage_path = joinpath(directory, "abm_v2_interval_coverage.csv")
    write_coverage_csv(coverage_path, v2_rows, V2_MEAN)
    if v1_directory !== nothing
        v1_ensembles =
            read_csv(v1_directory, "abm_ensemble_summaries.csv", ABM.EnsembleSummary)
        v1_rows = coverage_table(v1_ensembles, panel, "v1")
        open(coverage_path, "a") do io
            for row in v1_rows
                @printf(
                    io, "%s,%s,%d,%d,%.6f,%.6f,%.6f\n",
                    V1_MEAN, row.target, row.horizon, row.total, row.c90, row.c80, row.c50,
                )
            end
        end
    end
    println("\nwrote `abm_v2_interval_coverage.csv`")

    print_outlook(outlook_directory === nothing ? "" : outlook_directory)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
