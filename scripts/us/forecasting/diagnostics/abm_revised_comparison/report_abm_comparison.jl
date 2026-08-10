#!/usr/bin/env julia

# Render the markdown tables in RESULTS.md from the comparison outputs.
#
#   usage: report_abm_comparison.jl <headline-dir> <burnin-dir> <outlook-dir>
#
# Everything printed here is derived from the CSVs those runs wrote; no number
# is recomputed from a separate simulation.

using Printf
using Statistics

include("USRevisedDataABMComparison.jl")
using .USRevisedDataABMComparison

const ABM = USRevisedDataABMComparison
const BASE = USRevisedDataABMComparison.BASE

const ANCHOR = "beforeit_var_p1_constant"
const HEADLINE_SET = "headline_real_gdp_gdp_deflator"
const SECONDARY_SET = "secondary_nominal_gdp_effective_federal_funds_rate"

struct RunTables
    directory::String
    summaries::Vector{BASE.ScoreSummary}
    relative::Vector{BASE.RelativeScore}
    weighted::Vector{ABM.ABMWeightedScore}
    monte_carlo::Vector{ABM.MonteCarloError}
    ensembles::Vector{ABM.EnsembleSummary}
    cells::Vector{BASE.ForecastCell}
    mean_model_id::String
    median_model_id::String
end

function load_run(directory, mean_model_id, median_model_id)
    return RunTables(
        directory,
        ABM.read_struct_csv(joinpath(directory, "score_summaries.csv"), BASE.ScoreSummary),
        ABM.read_struct_csv(joinpath(directory, "relative_scores.csv"), BASE.RelativeScore),
        ABM.read_struct_csv(
            joinpath(directory, "weighted_relative_scores.csv"),
            ABM.ABMWeightedScore,
        ),
        ABM.read_struct_csv(
            joinpath(directory, "monte_carlo_errors.csv"),
            ABM.MonteCarloError,
        ),
        ABM.read_struct_csv(
            joinpath(directory, "abm_ensemble_summaries.csv"),
            ABM.EnsembleSummary,
        ),
        ABM.read_struct_csv(joinpath(directory, "forecast_cells.csv"), BASE.ForecastCell),
        mean_model_id,
        median_model_id,
    )
end

statistical_models(run) = sort(
    unique(
        row.model_id for row in run.summaries if
            !startswith(row.model_id, "beforeit_abm_us_v1")
    ),
)

function summary_lookup(run, track)
    return Dict(
        (row.model_id, row.target_id, row.horizon) => row for
            row in run.summaries if row.sample_track == track
    )
end

short_name(model_id) = replace(
    model_id,
    "beforeit_" => "",
    "_constant" => "",
    "univariate_" => "",
    r"_hyperparameters.*" => "",
)

# --------------------------------------------------------------------------
# weighted ranking tables
# --------------------------------------------------------------------------

function print_weighted_table(run, track, target_set, title)
    rows = filter(
        row -> row.sample_track == track && row.target_set == target_set,
        run.weighted,
    )
    sort!(rows; by = row -> row.weighted_macro_average_cellwise_rmse_ratio)
    println("\n**$title**\n")
    println("| rank | model | status | weighted RMSE ratio | weighted MAE ratio |")
    println("|---:|---|---|---:|---:|")
    for (rank, row) in enumerate(rows)
        marker = startswith(row.model_id, "beforeit_abm_us_v1") ? " **<- ABM**" : ""
        @printf(
            "| %d | `%s`%s | %s | %.4f | %.4f |\n",
            rank,
            row.model_id,
            marker,
            row.status == "COMPLETE_MATCHED" ? "ranked" : row.status,
            row.weighted_macro_average_cellwise_rmse_ratio,
            row.weighted_macro_average_cellwise_mae_ratio,
        )
    end
    return rows
end

# --------------------------------------------------------------------------
# per target/horizon table
# --------------------------------------------------------------------------

function print_cell_table(run, track, model_id, label)
    lookup = summary_lookup(run, track)
    models = statistical_models(run)
    println("\n**$label**\n")
    println(
        "| target | h | n | ABM RMSE | VAR(1) RMSE | best statistical RMSE | ABM/VAR(1) | rank | ABM bias | best statistical model |",
    )
    println("|---|---:|---:|---:|---:|---:|---:|---:|---:|---|")
    for target in ABM.ABM_TARGET_IDS
        for horizon in BASE.HORIZONS
            haskey(lookup, (model_id, target, horizon)) || continue
            abm = lookup[(model_id, target, horizon)]
            anchor = lookup[(ANCHOR, target, horizon)]
            candidates = [
                (model, lookup[(model, target, horizon)].rmse) for
                    model in models if haskey(lookup, (model, target, horizon))
            ]
            best_model, best_rmse = candidates[argmin([entry[2] for entry in candidates])]
            rank = 1 + count(entry -> entry[2] < abm.rmse, candidates)
            @printf(
                "| `%s` | %d | %d | %.4f | %.4f | %.4f | %.4f | %d/%d | %+.2f | `%s` |\n",
                target,
                horizon,
                abm.observation_count,
                abm.rmse,
                anchor.rmse,
                best_rmse,
                abm.rmse / anchor.rmse,
                rank,
                length(candidates) + 1,
                abm.mean_error,
                short_name(best_model),
            )
        end
    end
    return nothing
end

# --------------------------------------------------------------------------
# monte carlo error
# --------------------------------------------------------------------------

function print_monte_carlo_table(run, track)
    lookup = summary_lookup(run, track)
    println("\n**Monte-Carlo precision of the ensemble mean**\n")
    println(
        "| target | h | origins | paths | mean ensemble sd | mean MC s.e. | max MC s.e. | mean MC s.e. / RMSE |",
    )
    println("|---|---:|---:|---:|---:|---:|---:|---:|")
    for row in run.monte_carlo
        rmse = lookup[(run.mean_model_id, row.target_id, row.horizon)].rmse
        @printf(
            "| `%s` | %d | %d | %d | %.3f | %.4f | %.4f | %.4f |\n",
            row.target_id,
            row.horizon,
            row.origin_count,
            row.monte_carlo_paths,
            row.mean_ensemble_sd,
            row.mean_monte_carlo_standard_error,
            row.maximum_monte_carlo_standard_error,
            row.mean_monte_carlo_standard_error / rmse,
        )
    end
    return nothing
end

# --------------------------------------------------------------------------
# gap decomposition
# --------------------------------------------------------------------------

"""
    mean_squared_monte_carlo_error(run, track_origins, target, horizon)

Average of the squared Monte-Carlo standard error of the ensemble mean over the
scored origins, which is the amount by which finite-path noise inflates the
measured mean squared error.
"""
function mean_squared_monte_carlo_error(run, scored_origins, target, horizon)
    selected = [
        row.monte_carlo_standard_error^2 for row in run.ensembles if
            row.target_id == target && row.horizon == horizon &&
                row.origin_index in scored_origins
    ]
    return isempty(selected) ? 0.0 : mean(selected)
end

function scored_origin_set(run, track, model_id, target, horizon)
    return Set(
        row.origin_index for row in run.cells if
            row.model_id == model_id && row.target_id == target &&
                row.horizon == horizon
    )
end

function print_gap_ranking(headline, burn_in_runs, track)
    lookup = summary_lookup(headline, track)
    weighted = filter(
        row ->
        row.sample_track == track && row.target_set == HEADLINE_SET &&
            row.status == "COMPLETE_MATCHED",
        headline.weighted,
    )
    sort!(weighted; by = row -> row.weighted_macro_average_cellwise_rmse_ratio)
    best_statistical = first(
        row for row in weighted if !startswith(row.model_id, "beforeit_abm_us_v1")
    )
    abm = only(
        row for row in weighted if row.model_id == headline.mean_model_id
    )
    targets = ABM.HEADLINE_TARGET_IDS
    target_weight = 1.0 / length(targets)

    println(
        "\nBest statistical model on this set: `$(best_statistical.model_id)` " *
            "at $(round(best_statistical.weighted_macro_average_cellwise_rmse_ratio, digits = 4)); " *
            "ABM mean column at $(round(abm.weighted_macro_average_cellwise_rmse_ratio, digits = 4)); " *
            "gap $(round(abm.weighted_macro_average_cellwise_rmse_ratio - best_statistical.weighted_macro_average_cellwise_rmse_ratio, digits = 4)).",
    )

    println("\n**Cell-by-cell contribution to the weighted gap**\n")
    println(
        "| target | h | weight | ABM ratio | best-model ratio | weighted contribution to gap |",
    )
    println("|---|---:|---:|---:|---:|---:|")
    contributions = Tuple{String, Int, Float64}[]
    for target in targets
        for horizon in BASE.HORIZONS
            weight = target_weight * BASE.HORIZON_WEIGHTS[horizon]
            abm_ratio =
                lookup[(headline.mean_model_id, target, horizon)].rmse /
                lookup[(ANCHOR, target, horizon)].rmse
            best_ratio =
                lookup[(best_statistical.model_id, target, horizon)].rmse /
                lookup[(ANCHOR, target, horizon)].rmse
            contribution = weight * (abm_ratio - best_ratio)
            push!(contributions, (target, horizon, contribution))
            @printf(
                "| `%s` | %d | %.3f | %.4f | %.4f | %+.4f |\n",
                target,
                horizon,
                weight,
                abm_ratio,
                best_ratio,
                contribution,
            )
        end
    end

    # counterfactual weighted ratios
    baseline = abm.weighted_macro_average_cellwise_rmse_ratio
    debiased = 0.0
    mc_corrected = 0.0
    burn_in_swaps = Dict(label => 0.0 for (label, _) in burn_in_runs)
    for target in targets
        for horizon in BASE.HORIZONS
            weight = target_weight * BASE.HORIZON_WEIGHTS[horizon]
            row = lookup[(headline.mean_model_id, target, horizon)]
            anchor_rmse = lookup[(ANCHOR, target, horizon)].rmse
            debiased += weight * sqrt(max(row.rmse^2 - row.mean_error^2, 0.0)) / anchor_rmse
            origins = scored_origin_set(
                headline,
                track,
                headline.mean_model_id,
                target,
                horizon,
            )
            noise = mean_squared_monte_carlo_error(headline, origins, target, horizon)
            mc_corrected += weight * sqrt(max(row.rmse^2 - noise, 0.0)) / anchor_rmse
            for (label, run) in burn_in_runs
                run_lookup = summary_lookup(run, track)
                burn_in_row =
                    get(run_lookup, (run.mean_model_id, target, horizon), nothing)
                burn_in_swaps[label] += weight *
                    (burn_in_row === nothing ? row.rmse : burn_in_row.rmse) / anchor_rmse
            end
        end
    end

    println("\n**Counterfactual weighted RMSE ratios (headline pair, ABM mean column)**\n")
    println("| variant | weighted RMSE ratio | change vs measured |")
    println("|---|---:|---:|")
    @printf(
        "| measured (%d paths) | %.4f | - |\n",
        first(headline.monte_carlo).monte_carlo_paths,
        baseline,
    )
    @printf(
        "| remove systematic bias in every cell | %.4f | %+.4f |\n",
        debiased,
        debiased - baseline,
    )
    @printf(
        "| remove finite-path Monte-Carlo noise | %.4f | %+.4f |\n",
        mc_corrected,
        mc_corrected - baseline,
    )
    for (label, _) in burn_in_runs
        @printf(
            "| substitute the %s cells | %.4f | %+.4f |\n",
            label,
            burn_in_swaps[label],
            burn_in_swaps[label] - baseline,
        )
    end
    sort!(contributions; by = entry -> -entry[3])
    println(
        "\nLargest single-cell gap contributions: " *
            join(
            (
                "`$(entry[1])` h=$(entry[2]) $(round(entry[3], digits = 4))" for
                    entry in contributions[1:min(4, end)]
            ),
            ", ",
        ) * ".",
    )
    return nothing
end

# --------------------------------------------------------------------------
# burn-in comparison
# --------------------------------------------------------------------------

function print_burn_in_table(headline, burnin, label, track)
    headline_lookup = summary_lookup(headline, track)
    burnin_lookup = summary_lookup(burnin, track)
    println("\n**$label sensitivity, ABM mean column, `$track`**\n")
    println(
        "| target | h | headline RMSE | burn-in RMSE | headline bias | burn-in bias | RMSE change |",
    )
    println("|---|---:|---:|---:|---:|---:|---:|")
    for target in ABM.HEADLINE_TARGET_IDS
        for horizon in BASE.HORIZONS
            a = headline_lookup[(headline.mean_model_id, target, horizon)]
            b = get(burnin_lookup, (burnin.mean_model_id, target, horizon), nothing)
            b === nothing && continue
            @printf(
                "| `%s` | %d | %.4f | %.4f | %+.2f | %+.2f | %+.4f |\n",
                target,
                horizon,
                a.rmse,
                b.rmse,
                a.mean_error,
                b.mean_error,
                b.rmse - a.rmse,
            )
        end
    end
    return nothing
end

# --------------------------------------------------------------------------
# unemployment appendix
# --------------------------------------------------------------------------

function print_unemployment_appendix(run, track)
    cells = filter(
        row ->
        row.model_id == run.mean_model_id && row.target_id == "unemployment_rate" &&
            row.horizon == 1,
        run.cells,
    )
    sort!(cells; by = row -> row.origin_index)
    forecasts = getfield.(cells, :point_forecast)
    actuals = getfield.(cells, :actual)
    println(
        "\nABM h=1 unemployment forecast across $(length(cells)) origins: " *
            "range $(round(minimum(forecasts), digits = 3))-$(round(maximum(forecasts), digits = 3)) pp, " *
            "sd $(round(std(forecasts), digits = 3)) pp. " *
            "Realized truth over the same origins: range $(round(minimum(actuals), digits = 3))-$(round(maximum(actuals), digits = 3)) pp, " *
            "sd $(round(std(actuals), digits = 3)) pp. " *
            "Correlation forecast/actual $(round(cor(forecasts, actuals), digits = 3)).",
    )
    println("\n| origin | ABM h=1 forecast | actual |")
    println("|---|---:|---:|")
    for row in cells
        row.origin_period in
            ("2010Q2", "2013Q2", "2017Q4", "2020Q2", "2020Q4", "2025Q2") || continue
        @printf(
            "| %s | %.3f | %.3f |\n",
            row.origin_period,
            row.point_forecast,
            row.actual,
        )
    end
    return nothing
end

# --------------------------------------------------------------------------
# outlook
# --------------------------------------------------------------------------

function print_outlook(directory, origin_period, targets)
    rows = ABM.read_struct_csv(
        joinpath(directory, "current_outlook.csv"),
        ABM.EnsembleSummary,
    )
    for target in targets
        selected = sort(
            filter(
                row -> row.origin_period == origin_period && row.target_id == target,
                rows,
            );
            by = row -> row.horizon,
        )
        isempty(selected) && continue
        println("\n**Origin $origin_period, `$target` (unscored, out of sample)**\n")
        println("| h | quarter | mean | median | p5 | p10 | p25 | p75 | p90 | p95 | MC s.e. |")
        println("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for row in selected
            @printf(
                "| %d | %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.3f |\n",
                row.horizon,
                row.target_period,
                row.ensemble_mean,
                row.ensemble_median,
                row.percentile_05,
                row.percentile_10,
                row.percentile_25,
                row.percentile_75,
                row.percentile_90,
                row.percentile_95,
                row.monte_carlo_standard_error,
            )
        end
    end
    return nothing
end

function main(args)
    3 <= length(args) <= 4 || throw(
        ArgumentError(
            "usage: report_abm_comparison.jl <headline-dir> <burnin-dir> <outlook-dir> [long-burnin-dir]",
        ),
    )
    headline = load_run(
        args[1],
        ABM.HEADLINE_VARIANT.mean_model_id,
        ABM.HEADLINE_VARIANT.median_model_id,
    )
    burnin = load_run(
        args[2],
        ABM.BURN_IN_VARIANT.mean_model_id,
        ABM.BURN_IN_VARIANT.median_model_id,
    )
    burn_in_runs = [("one-quarter burn-in", burnin)]
    if length(args) == 4
        push!(
            burn_in_runs,
            (
                "four-quarter burn-in",
                load_run(
                    args[4],
                    "beforeit_abm_us_v1_mean_burnin4",
                    "beforeit_abm_us_v1_median_burnin4",
                ),
            ),
        )
    end

    println("## Weighted rankings")
    print_weighted_table(
        headline,
        ABM.ALL_AVAILABLE_TRACK,
        HEADLINE_SET,
        "Headline pair {real_gdp, gdp_deflator}, all-available track",
    )
    print_weighted_table(
        headline,
        ABM.BALANCED_H12_TRACK,
        HEADLINE_SET,
        "Headline pair {real_gdp, gdp_deflator}, balanced-h12 track",
    )
    print_weighted_table(
        headline,
        ABM.PANDEMIC_MASKED_TRACK,
        HEADLINE_SET,
        "Headline pair {real_gdp, gdp_deflator}, pandemic-masked track",
    )
    print_weighted_table(
        headline,
        ABM.ALL_AVAILABLE_TRACK,
        SECONDARY_SET,
        "Secondary pair {nominal_gdp, effective_federal_funds_rate}, all-available track",
    )

    println("\n## Per target and horizon")
    print_cell_table(
        headline,
        ABM.ALL_AVAILABLE_TRACK,
        headline.mean_model_id,
        "ABM ensemble mean, all-available track",
    )
    print_cell_table(
        headline,
        ABM.ALL_AVAILABLE_TRACK,
        headline.median_model_id,
        "ABM ensemble median, all-available track",
    )

    println("\n## Monte-Carlo precision")
    print_monte_carlo_table(headline, ABM.ALL_AVAILABLE_TRACK)

    println("\n## Burn-in sensitivity")
    for (label, run) in burn_in_runs
        print_burn_in_table(headline, run, label, ABM.ALL_AVAILABLE_TRACK)
        print_weighted_table(
            run,
            ABM.ALL_AVAILABLE_TRACK,
            HEADLINE_SET,
            "$label variant, headline pair, all-available track",
        )
    end

    println("\n## Gap ranking")
    print_gap_ranking(headline, burn_in_runs, ABM.ALL_AVAILABLE_TRACK)

    println("\n## Unemployment appendix")
    print_unemployment_appendix(headline, ABM.ALL_AVAILABLE_TRACK)

    println("\n## Current outlook")
    print_outlook(args[3], "2026Q1", ["real_gdp", "gdp_deflator", "effective_federal_funds_rate"])
    print_outlook(args[3], "2025Q4", ["real_gdp", "gdp_deflator"])
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
