# ---------------------------------------------------------------------------
# Apply the preregistered Stage-2b success bar (plan addendum 2026-08-16;
# STAGE2B_PROTOCOL.md) mechanically to the scorecard outputs.
#
#   Bar: the repaired ABM (v3 mean column) is superior if
#   (a) its weighted headline-pair RMSE ratio beats the best non-ABM column
#       (including both DSGE columns) in >= 2 of 3 tracks, with DM
#       significance reported per horizon, and
#   (b) its density scores (weighted CRPS and 90% coverage on the headline
#       targets) are no worse than the best challenger's.
#
# Usage: julia --startup-file=no --project=scripts/us \
#   scripts/us/forecasting/diagnostics/stage2b/verdict_stage2b.jl <scorecard-dir>
# ---------------------------------------------------------------------------

using Statistics

const V3 = "beforeit_abm_us_v3_mean"
const ABM_PREFIX = "beforeit_abm_us_"
const HEADLINE = "headline_real_gdp_gdp_deflator"
const HORIZON_WEIGHTS = Dict("1" => 0.3, "2" => 0.25, "4" => 0.2, "8" => 0.15, "12" => 0.1)

function read_csv_rows(path)
    lines = readlines(path)
    header = String.(split(lines[1], ','))
    rows = Vector{Dict{String, String}}()
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ',')
        push!(rows, Dict(header[i] => String(fields[i]) for i in eachindex(header)))
    end
    return rows
end

function main(args)
    directory = args[1]
    weighted = read_csv_rows(joinpath(directory, "stage2b_weighted_scores.csv"))
    tracks = unique(row["sample_track"] for row in weighted)
    println("# Stage-2b preregistered verdict\n")
    point_wins = String[]
    for track in tracks
        rows = [
            row for row in weighted if row["target_set"] == HEADLINE &&
                row["sample_track"] == track &&
                row["status"] == "COMPLETE_MATCHED"
        ]
        v3_row = only(filter(row -> row["model_id"] == V3, rows))
        v3_ratio = parse(Float64, v3_row["weighted_rmse_ratio"])
        non_abm = [
            (row["model_id"], parse(Float64, row["weighted_rmse_ratio"]))
                for row in rows if !startswith(row["model_id"], ABM_PREFIX)
        ]
        sort!(non_abm; by = last)
        best_model, best_ratio = non_abm[1]
        win = v3_ratio < best_ratio
        win && push!(point_wins, track)
        println(
            "- $track: v3 = $(round(v3_ratio; digits = 3)); best non-ABM = " *
                "`$best_model` at $(round(best_ratio; digits = 3)) -> " *
                (win ? "**v3 wins**" : "**v3 does not win**"),
        )
    end
    condition_a = length(point_wins) >= 2
    println(
        "\nPoint condition (a): v3 beats the best non-ABM column in " *
            "$(length(point_wins)) of $(length(tracks)) tracks -> " *
            (condition_a ? "**MET**" : "**NOT MET**"),
    )

    # density condition on the all-available track (primary), reported for all
    crps = read_csv_rows(joinpath(directory, "stage2b_density_crps.csv"))
    coverage = read_csv_rows(joinpath(directory, "stage2b_density_coverage.csv"))
    density_ok = Bool[]
    for track in tracks
        v3_crps = 0.0
        challenger_crps = Dict{String, Float64}()
        complete = true
        for target in ("real_gdp", "gdp_deflator")
            rows = [
                row for row in crps if row["sample_track"] == track &&
                    row["target_id"] == target &&
                    haskey(HORIZON_WEIGHTS, row["horizon"])
            ]
            by_model = Dict{String, Vector{Dict{String, String}}}()
            for row in rows
                push!(get!(by_model, row["model_id"], Dict{String, String}[]), row)
            end
            for (model, model_rows) in by_model
                length(model_rows) == length(HORIZON_WEIGHTS) || continue
                value = sum(
                    HORIZON_WEIGHTS[row["horizon"]] *
                        parse(Float64, row["mean_crps"]) for row in model_rows
                )
                if model == V3
                    v3_crps += 0.5 * value
                elseif !startswith(model, ABM_PREFIX)
                    challenger_crps[model] =
                        get(challenger_crps, model, 0.0) + 0.5 * value
                end
            end
        end
        isempty(challenger_crps) && (complete = false)
        best_challenger = complete ?
            minimum(collect(values(challenger_crps))) : NaN
        best_name = complete ?
            argmin(challenger_crps) : "?"
        crps_ok = complete && v3_crps <= best_challenger + 1.0e-12
        # 90% coverage distance from nominal, headline targets pooled
        v3_coverage = mean(
            parse(Float64, row["empirical_coverage"])
                for row in coverage if row["sample_track"] == track &&
                row["model_id"] == V3 && row["nominal_level"] == "0.9" &&
                row["target_id"] in ("real_gdp", "gdp_deflator")
        )
        challenger_names = unique(
            row["model_id"] for row in coverage if
                !startswith(row["model_id"], ABM_PREFIX)
        )
        challenger_distance = Dict(
            name => abs(
                    mean(
                        parse(Float64, row["empirical_coverage"])
                        for row in coverage if row["sample_track"] == track &&
                        row["model_id"] == name &&
                        row["nominal_level"] == "0.9" &&
                        row["target_id"] in ("real_gdp", "gdp_deflator")
                    ) - 0.9,
                ) for name in challenger_names
        )
        best_coverage_distance = minimum(collect(values(challenger_distance)))
        coverage_ok = abs(v3_coverage - 0.9) <= best_coverage_distance + 1.0e-12
        push!(density_ok, crps_ok && coverage_ok)
        println(
            "- $track density: v3 weighted CRPS $(round(v3_crps; digits = 3)) vs best " *
                "challenger `$best_name` $(round(best_challenger; digits = 3)) " *
                "($(crps_ok ? "ok" : "worse")); v3 90% coverage " *
                "$(round(v3_coverage; digits = 3)) vs best challenger distance " *
                "$(round(best_coverage_distance; digits = 3)) " *
                "($(coverage_ok ? "ok" : "worse"))",
        )
    end
    condition_b = all(density_ok)
    println(
        "\nDensity condition (b): " * (
            condition_b ? "**MET** in every track" :
                "**NOT MET** in at least one track"
        ),
    )
    verdict_text = if condition_a && condition_b
        "the preregistered superiority bar is **MET**."
    elseif condition_a
        "point superiority holds but the density bar is **NOT MET** — the honest-success clause applies."
    else
        "the preregistered superiority bar is **NOT MET** — the negative result is published with the same tables."
    end
    println("\n## Verdict: " * verdict_text)
    return println("\n(DM significance per horizon: stage2b_dm_tests.csv; this verdict is invalid without it.)")
end

main(ARGS)
