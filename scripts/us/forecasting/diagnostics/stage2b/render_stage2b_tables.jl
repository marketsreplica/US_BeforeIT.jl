# ---------------------------------------------------------------------------
# Render the Stage-2b scorecard CSVs as markdown tables for the evidence
# report. Reads the outputs of run_stage2b_scorecard.jl and
# run_stage2b_inference.jl; writes STAGE2B_TABLES.md into the scorecard dir.
#
# Usage: julia --startup-file=no --project=scripts/us \
#   scripts/us/forecasting/diagnostics/stage2b/render_stage2b_tables.jl <dir>
# ---------------------------------------------------------------------------

using Statistics

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

fmt(x; digits = 3) = string(round(parse(Float64, x); digits = digits))

function main(args)
    directory = args[1]
    output = joinpath(directory, "STAGE2B_TABLES.md")
    weighted = read_csv_rows(joinpath(directory, "stage2b_weighted_scores.csv"))
    tracks = unique(row["sample_track"] for row in weighted)
    sets = unique(row["target_set"] for row in weighted)
    io = IOBuffer()
    println(io, "# Stage-2b scorecard tables (auto-rendered)\n")

    for set in sets
        println(io, "## Target set: $set\n")
        println(io, "Weighted macro-average cellwise RMSE ratio vs VAR(1); rank in parentheses; MAE ratio second line block.\n")
        models = sort(
            unique(row["model_id"] for row in weighted if row["target_set"] == set),
        )
        println(io, "| model | " * join(tracks, " | ") * " |")
        println(io, "|---|" * repeat("---:|", length(tracks)))
        # rank per track
        ranks = Dict{Tuple{String, String}, Int}()
        for track in tracks
            in_track = [
                (row["model_id"], parse(Float64, row["weighted_rmse_ratio"]))
                    for row in weighted if row["target_set"] == set &&
                    row["sample_track"] == track &&
                    row["status"] == "COMPLETE_MATCHED"
            ]
            sort!(in_track; by = last)
            for (position, (model, _)) in enumerate(in_track)
                ranks[(track, model)] = position
            end
        end
        for model in models
            cells = String[]
            for track in tracks
                matches = [
                    row for row in weighted if row["target_set"] == set &&
                        row["sample_track"] == track && row["model_id"] == model
                ]
                if isempty(matches) || matches[1]["status"] != "COMPLETE_MATCHED"
                    push!(cells, "—")
                else
                    value = fmt(matches[1]["weighted_rmse_ratio"])
                    rank = get(ranks, (track, model), 0)
                    push!(cells, "$value ($rank)")
                end
            end
            println(io, "| `$model` | " * join(cells, " | ") * " |")
        end
        println(io)
    end

    dm_path = joinpath(directory, "stage2b_dm_tests.csv")
    if isfile(dm_path)
        dm = read_csv_rows(dm_path)
        println(io, "## HLN Diebold–Mariano: v3 ABM vs non-ABM columns (headline targets)\n")
        println(io, "Negative mean differential favors v3. p-values two-sided.\n")
        println(io, "| track | comparator | target | h | mean diff | DM stat | p |")
        println(io, "|---|---|---|--:|--:|--:|--:|")
        for row in dm
            row["model_id"] == "beforeit_abm_us_v3_mean" || continue
            row["target_id"] in ("real_gdp", "gdp_deflator") || continue
            println(
                io,
                "| $(replace(row["sample_track"], "abm_" => "", "_common_cells" => "")) " *
                    "| `$(row["comparator_id"])` | $(row["target_id"]) | $(row["horizon"]) " *
                    "| $(fmt(row["mean_differential"])) | $(fmt(row["dm_statistic"]; digits = 2)) " *
                    "| $(fmt(row["p_value"])) |",
            )
        end
        println(io)
    end

    rw_path = joinpath(directory, "stage2b_romano_wolf.csv")
    if isfile(rw_path)
        rw = read_csv_rows(rw_path)
        println(io, "## Romano–Wolf stepdown: v3 vs non-ABM family (weighted losses, complete origins)\n")
        println(io, "| track | target set | comparator | mean diff | adj. p | rejected@5% |")
        println(io, "|---|---|---|--:|--:|:--|")
        for row in rw
            println(
                io,
                "| $(replace(row["sample_track"], "abm_" => "", "_common_cells" => "")) " *
                    "| $(row["target_set"]) | `$(row["comparator"])` " *
                    "| $(fmt(row["mean_differential"]; digits = 4)) " *
                    "| $(fmt(row["adjusted_p_value"])) | $(row["rejected_at_5pct"]) |",
            )
        end
        println(io)
    end

    mcs_path = joinpath(directory, "stage2b_mcs.csv")
    if isfile(mcs_path)
        mcs = read_csv_rows(mcs_path)
        println(io, "## Model Confidence Set (alpha = 0.10, weighted losses)\n")
        println(io, "| track | target set | model | mean loss | MCS p | in MCS |")
        println(io, "|---|---|---|--:|--:|:--|")
        for row in sort(
                mcs;
                by = r -> (
                    r["sample_track"], r["target_set"],
                    parse(Float64, r["mean_weighted_loss"]),
                ),
            )
            println(
                io,
                "| $(replace(row["sample_track"], "abm_" => "", "_common_cells" => "")) " *
                    "| $(row["target_set"]) | `$(row["model_id"])` " *
                    "| $(fmt(row["mean_weighted_loss"]; digits = 2)) " *
                    "| $(fmt(row["mcs_p_value"])) | $(row["in_mcs_alpha10"]) |",
            )
        end
        println(io)
    end

    crps_path = joinpath(directory, "stage2b_density_crps.csv")
    if isfile(crps_path)
        crps = read_csv_rows(crps_path)
        println(io, "## Density: mean CRPS by track and model (headline targets, horizon-weighted)\n")
        weights = Dict("1" => 0.3, "2" => 0.25, "4" => 0.2, "8" => 0.15, "12" => 0.1)
        combos = unique((row["sample_track"], row["model_id"]) for row in crps)
        println(io, "| track | model | weighted CRPS real_gdp | weighted CRPS gdp_deflator |")
        println(io, "|---|---|--:|--:|")
        for (track, model) in sort(collect(combos))
            values = Dict{String, Float64}()
            for target in ("real_gdp", "gdp_deflator")
                selected = [
                    row for row in crps if row["sample_track"] == track &&
                        row["model_id"] == model && row["target_id"] == target &&
                        haskey(weights, row["horizon"])
                ]
                length(selected) == length(weights) || continue
                values[target] = sum(
                    weights[row["horizon"]] * parse(Float64, row["mean_crps"])
                        for row in selected
                )
            end
            length(values) == 2 || continue
            println(
                io,
                "| $(replace(track, "abm_" => "", "_common_cells" => "")) | `$model` " *
                    "| $(round(values["real_gdp"]; digits = 3)) " *
                    "| $(round(values["gdp_deflator"]; digits = 3)) |",
            )
        end
        println(io)
    end

    coverage_path = joinpath(directory, "stage2b_density_coverage.csv")
    if isfile(coverage_path)
        coverage = read_csv_rows(coverage_path)
        println(io, "## 90% central-interval coverage (headline targets, all horizons pooled by mean)\n")
        combos = unique((row["sample_track"], row["model_id"]) for row in coverage)
        println(io, "| track | model | real_gdp coverage | gdp_deflator coverage |")
        println(io, "|---|---|--:|--:|")
        for (track, model) in sort(collect(combos))
            values = Dict{String, Float64}()
            for target in ("real_gdp", "gdp_deflator")
                selected = [
                    parse(Float64, row["empirical_coverage"])
                        for row in coverage if row["sample_track"] == track &&
                        row["model_id"] == model && row["target_id"] == target &&
                        row["nominal_level"] == "0.9"
                ]
                isempty(selected) && continue
                values[target] = mean(selected)
            end
            length(values) == 2 || continue
            println(
                io,
                "| $(replace(track, "abm_" => "", "_common_cells" => "")) | `$model` " *
                    "| $(round(values["real_gdp"]; digits = 3)) " *
                    "| $(round(values["gdp_deflator"]; digits = 3)) |",
            )
        end
        println(io)
    end

    dispersion_path = joinpath(directory, "stage2b_unemployment_dispersion.csv")
    if isfile(dispersion_path)
        dispersion = read_csv_rows(dispersion_path)
        println(io, "## Unemployment dispersion gate (2b-2): forecast vs realized dispersion\n")
        println(io, "| track | model | h | mean ens. sd | realized sd | ratio |")
        println(io, "|---|---|--:|--:|--:|--:|")
        for row in dispersion
            startswith(row["model_id"], "beforeit_abm") || continue
            println(
                io,
                "| $(replace(row["sample_track"], "abm_" => "", "_common_cells" => "")) " *
                    "| `$(row["model_id"])` | $(row["horizon"]) " *
                    "| $(fmt(row["mean_forecast_dispersion"]; digits = 2)) " *
                    "| $(fmt(row["realized_dispersion"]; digits = 2)) " *
                    "| $(fmt(row["dispersion_ratio"]; digits = 2)) |",
            )
        end
        println(io)
    end

    write(output, String(take!(io)))
    return println("rendered $output")
end

main(ARGS)
