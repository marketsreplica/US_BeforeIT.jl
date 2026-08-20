# ---------------------------------------------------------------------------
# Stage-2b composite scorecard (frozen protocol: STAGE2B_PROTOCOL.md)
#
# Assembles the full Stage-2b scored field on identical common cells:
#   10 statistical columns (frozen registry family, re-run in-process)
#    4 DSGE columns   (dsge_small_nk{,_median}, dsge_sw07{,_median})
#    6 ABM columns    (v1, v2, v3 × mean/median)
# over the 61-origin revised-data grid, three tracks, target sets
# {headline, secondary, labour_unemployment_rate}; point scores, density
# scores (CRPS + central-interval coverage from persisted draws), the
# unemployment dispersion gate, and matched per-cell loss tables for the
# inference stage.
#
# Usage:
#   JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
#     julia --startup-file=no --project=scripts/us \
#     scripts/us/forecasting/diagnostics/stage2b/run_stage2b_scorecard.jl \
#     <output-dir> --v1=<dir> --v2=<dir> --v3=<dir> --dsge=<dir> [--extra=<name>:<dir> ...]
# ---------------------------------------------------------------------------

import JLD2
import SHA
using Statistics

include(
    joinpath(
        @__DIR__, "..", "abm_revised_comparison", "USRevisedDataABMComparison.jl",
    )
)
using .USRevisedDataABMComparison
const ABM = USRevisedDataABMComparison
const BASE = ABM.USRevisedDataBenchmarkDiagnostic

include(joinpath(@__DIR__, "..", "..", "scoring", "USForecastScores.jl"))
using .USForecastScores

const SCORED_TARGET_SETS_2B = [
    ("headline_real_gdp_gdp_deflator", ["real_gdp", "gdp_deflator"]),
    (
        "secondary_nominal_gdp_effective_federal_funds_rate",
        ["nominal_gdp", "effective_federal_funds_rate"],
    ),
    ("labour_unemployment_rate", ["unemployment_rate"]),
]
const DENSITY_COLUMN_SOURCES = Dict{String, String}()   # model_id => draws dir
const COVERAGE_LEVELS = [0.5, 0.8, 0.9]

function cli_option(args, name)
    prefix = "--" * name * "="
    for argument in args
        startswith(argument, prefix) && return argument[(length(prefix) + 1):end]
    end
    return nothing
end

function load_column_ensembles(directory, filename)
    path = joinpath(directory, filename)
    isfile(path) || error("missing $path")
    return ABM.read_struct_csv(path, ABM.EnsembleSummary)
end

function scored_origin_indices(panel)
    return collect(BASE.MINIMUM_TRAINING_QUARTERS:(length(panel.periods) - 1))
end

function main(raw_args)
    positional = [a for a in raw_args if !startswith(a, "--")]
    length(positional) >= 1 || error("usage: run_stage2b_scorecard.jl <output-dir> --v1= --v2= --v3= --dsge=")
    output_dir = positional[1]
    mkpath(output_dir)
    v1_dir = cli_option(raw_args, "v1")
    v2_dir = cli_option(raw_args, "v2")
    v3_dir = cli_option(raw_args, "v3")
    dsge_dir = cli_option(raw_args, "dsge")
    all(!isnothing, (v1_dir, v2_dir, v3_dir, dsge_dir)) ||
        error("--v1/--v2/--v3/--dsge are all required")

    fixtures = joinpath(
        @__DIR__, "..", "revised_data", "fixtures",
    )
    panel = BASE.load_revised_quarterly_panel(
        joinpath(fixtures, "quarterly_panel.csv"),
        joinpath(fixtures, "manifest.toml"),
    )
    BASE.validate_panel(panel)
    origin_indices = scored_origin_indices(panel)
    # Pilot mode: score only the first N origins (integration smoke test; the
    # manifest records the truncation so a smoke run can never be quoted as
    # the canonical comparison).
    max_origins_option = cli_option(raw_args, "max-origins")
    pilot_truncated = false
    if max_origins_option !== nothing
        limit = parse(Int, max_origins_option)
        if limit < length(origin_indices)
            origin_indices = origin_indices[1:limit]
            pilot_truncated = true
        end
    end

    # ------------------------------------------------------------------ columns
    columns = Tuple{ABM.ABMVariant, Vector{ABM.EnsembleSummary}, String}[]
    push!(
        columns, (
            ABM.HEADLINE_V3_VARIANT,
            load_column_ensembles(v3_dir, "abm_ensemble_summaries.csv"),
            joinpath(v3_dir, "abm_predictive_draws.jld2"),
        ),
    )
    push!(
        columns, (
            ABM.HEADLINE_V2_VARIANT,
            load_column_ensembles(v2_dir, "abm_ensemble_summaries.csv"),
            joinpath(v2_dir, "abm_predictive_draws.jld2"),
        ),
    )
    push!(
        columns, (
            ABM.HEADLINE_VARIANT,
            load_column_ensembles(v1_dir, "abm_ensemble_summaries.csv"),
            joinpath(v1_dir, "abm_predictive_draws.jld2"),
        ),
    )
    for (column, mean_id, median_id) in (
            ("dsge_small_nk", "dsge_small_nk", "dsge_small_nk_median"),
            ("dsge_sw07", "dsge_sw07", "dsge_sw07_median"),
        )
        variant = ABM.ABMVariant(column, mean_id, median_id, 0, 500)
        ensembles = load_column_ensembles(
            joinpath(dsge_dir, column), "dsge_ensemble_summaries.csv",
        )
        push!(
            columns,
            (variant, ensembles, joinpath(dsge_dir, column, "dsge_predictive_draws.jld2")),
        )
    end
    # optional extra ablation columns: --extra=<variant_name>:<dir>
    for argument in raw_args
        startswith(argument, "--extra=") || continue
        spec = argument[(length("--extra=") + 1):end]
        parts = split(spec, ':'; limit = 2)
        length(parts) == 2 || error("--extra expects <variant_name>:<dir>")
        name, directory = String(parts[1]), String(parts[2])
        variant = ABM.ABMVariant(
            name, "beforeit_abm_us_$(name)_mean", "beforeit_abm_us_$(name)_median",
            0, 500,
        )
        push!(
            columns, (
                variant,
                load_column_ensembles(directory, "abm_ensemble_summaries.csv"),
                joinpath(directory, "abm_predictive_draws.jld2"),
            ),
        )
    end

    # coverage/completeness assertions: no origin silently dropped
    for (variant, ensembles, _) in columns
        covered = sort(unique(row.origin_index for row in ensembles))
        missing_origins = setdiff(origin_indices, covered)
        isempty(missing_origins) || error(
            "column $(variant.name) is missing origins $missing_origins",
        )
    end

    # ------------------------------------------------------------- point cells
    base_result = BASE.run_revised_benchmark_diagnostic(panel)
    forecast_cells = filter(
        row -> row.target_id in ABM.ABM_TARGET_IDS,
        base_result.forecast_cells,
    )
    model_ids = copy(base_result.model_ids)
    for (variant, ensembles, draws_path) in columns
        append!(forecast_cells, ABM.abm_forecast_cells(panel, ensembles, variant))
        push!(model_ids, variant.mean_model_id)
        push!(model_ids, variant.median_model_id)
        DENSITY_COLUMN_SOURCES[variant.mean_model_id] = draws_path
    end

    common_keys = BASE.common_cell_keys(forecast_cells, model_ids)
    common_rows = filter(row -> BASE.cell_key(row) in common_keys, forecast_cells)
    balanced_last_origin = length(panel.periods) - BASE.MAXIMUM_HORIZON
    tracks = [
        (ABM.ALL_AVAILABLE_TRACK, common_rows),
        (
            ABM.BALANCED_H12_TRACK,
            filter(row -> row.origin_index <= balanced_last_origin, common_rows),
        ),
        (
            ABM.PANDEMIC_MASKED_TRACK,
            filter(
                row -> !ABM.is_acute_pandemic_target(row.target_period),
                common_rows,
            ),
        ),
    ]

    summaries = ABM.ScoreSummary[]
    for (track, rows) in tracks
        append!(
            summaries,
            BASE.summarize_rows(track, rows, model_ids, ABM.ABM_TARGET_IDS),
        )
    end

    benchmark_model_id = base_result.benchmark_model_id
    by_key = Dict(
        (row.sample_track, row.model_id, row.target_id, row.horizon) => row
            for row in summaries
    )
    relative = NamedTuple[]
    for (track, _) in tracks, model in model_ids,
            target in ABM.ABM_TARGET_IDS, horizon in BASE.HORIZONS

        key = (track, model, target, horizon)
        anchor_key = (track, benchmark_model_id, target, horizon)
        (haskey(by_key, key) && haskey(by_key, anchor_key)) || continue
        row = by_key[key]
        anchor = by_key[anchor_key]
        row.observation_count == anchor.observation_count ||
            error("unmatched samples for $key")
        push!(
            relative, (
                sample_track = track, model_id = model,
                benchmark_model_id = benchmark_model_id, target_id = target,
                horizon = horizon, observation_count = row.observation_count,
                rmse = row.rmse, mae = row.mae,
                rmse_ratio = row.rmse / anchor.rmse,
                mae_ratio = row.mae / anchor.mae,
            ),
        )
    end

    weighted = NamedTuple[]
    for (track, _) in tracks, (set_name, target_ids) in SCORED_TARGET_SETS_2B
        target_weight = 1.0 / length(target_ids)
        expected = length(target_ids) * length(BASE.HORIZONS)
        for model in model_ids
            selected = [
                row for row in relative if
                    row.sample_track == track && row.model_id == model &&
                    row.target_id in target_ids
            ]
            complete = length(selected) == expected
            weighted_rmse = complete ?
                sum(
                    target_weight * BASE.HORIZON_WEIGHTS[row.horizon] *
                    row.rmse_ratio for row in selected
                ) : NaN
            weighted_mae = complete ?
                sum(
                    target_weight * BASE.HORIZON_WEIGHTS[row.horizon] *
                    row.mae_ratio for row in selected
                ) : NaN
            push!(
                weighted, (
                    sample_track = track, target_set = set_name,
                    model_id = model, benchmark_model_id = benchmark_model_id,
                    status = complete ? "COMPLETE_MATCHED" : "INCOMPLETE",
                    cell_count = length(selected),
                    expected_cell_count = expected,
                    weighted_rmse_ratio = weighted_rmse,
                    weighted_mae_ratio = weighted_mae,
                ),
            )
        end
    end

    # ------------------------------------------------------------ density part
    actual_by_cell = Dict(
        (row.model_id, row.origin_index, row.target_id, row.horizon) => row
            for row in common_rows
    )
    common_by_cell = Dict{Tuple{Int, String, Int}, Float64}()
    for row in common_rows
        common_by_cell[(row.origin_index, row.target_id, row.horizon)] = row.actual
    end
    density_rows = NamedTuple[]
    coverage_rows = NamedTuple[]
    for (variant, _, draws_path) in columns
        isfile(draws_path) || error("missing draws file $draws_path")
        draws_file = JLD2.jldopen(draws_path, "r")
        for (track, rows) in tracks
            cells = unique(
                (row.origin_index, row.target_id, row.horizon)
                    for row in rows if row.model_id == variant.mean_model_id
            )
            per_cell = Dict{Tuple{String, Int}, Vector{Float64}}()
            interval_actuals = Dict{Tuple{String, Int, Float64}, Vector{Float64}}()
            interval_lowers = Dict{Tuple{String, Int, Float64}, Vector{Float64}}()
            interval_uppers = Dict{Tuple{String, Int, Float64}, Vector{Float64}}()
            for (origin_index, target_id, horizon) in cells
                key = "draws/$origin_index/$target_id/$horizon"
                haskey(draws_file, key) || error(
                    "column $(variant.name) missing draws at $key",
                )
                sample = draws_file[key]
                actual = common_by_cell[(origin_index, target_id, horizon)]
                crps = USForecastScores.ensemble_crps(actual, sample)
                push!(get!(per_cell, (target_id, horizon), Float64[]), crps)
                sorted = sort(sample)
                for level in COVERAGE_LEVELS
                    tail = (1.0 - level) / 2.0
                    n = length(sorted)
                    quantile_at = q -> begin
                        position = clamp(q * (n - 1) + 1.0, 1.0, Float64(n))
                        lower_i = Int(floor(position)); upper_i = Int(ceil(position))
                        w = position - lower_i
                        (1.0 - w) * sorted[lower_i] + w * sorted[upper_i]
                    end
                    push!(
                        get!(interval_actuals, (target_id, horizon, level), Float64[]),
                        actual,
                    )
                    push!(
                        get!(interval_lowers, (target_id, horizon, level), Float64[]),
                        quantile_at(tail),
                    )
                    push!(
                        get!(interval_uppers, (target_id, horizon, level), Float64[]),
                        quantile_at(1.0 - tail),
                    )
                end
            end
            for ((target_id, horizon), values) in per_cell
                push!(
                    density_rows, (
                        sample_track = track, model_id = variant.mean_model_id,
                        target_id = target_id, horizon = horizon,
                        observation_count = length(values),
                        mean_crps = mean(values),
                    ),
                )
            end
            for level in COVERAGE_LEVELS
                for ((target_id, horizon, l), actuals) in interval_actuals
                    l == level || continue
                    summary = USForecastScores.coverage_summary(
                        actuals,
                        interval_lowers[(target_id, horizon, level)],
                        interval_uppers[(target_id, horizon, level)],
                    )
                    push!(
                        coverage_rows, (
                            sample_track = track,
                            model_id = variant.mean_model_id,
                            target_id = target_id, horizon = horizon,
                            nominal_level = level,
                            observation_count = summary.n,
                            empirical_coverage = summary.coverage,
                            mean_width = summary.mean_width,
                            below_rate = summary.below_rate,
                            above_rate = summary.above_rate,
                        ),
                    )
                end
            end
        end
        close(draws_file)
    end

    # ------------------------------------------ unemployment dispersion gate
    dispersion_rows = NamedTuple[]
    for (variant, ensembles, _) in columns
        ensemble_by_cell = Dict(
            (row.origin_index, row.target_id, row.horizon) => row
                for row in ensembles
        )
        for (track, rows) in tracks
            for horizon in BASE.HORIZONS
                cells = [
                    row for row in rows if
                        row.model_id == variant.mean_model_id &&
                        row.target_id == "unemployment_rate" &&
                        row.horizon == horizon
                ]
                isempty(cells) && continue
                actuals = [row.actual for row in cells]
                spreads = [
                    ensemble_by_cell[(row.origin_index, row.target_id, horizon)].ensemble_sd
                        for row in cells
                ]
                push!(
                    dispersion_rows, (
                        sample_track = track, model_id = variant.mean_model_id,
                        horizon = horizon, observation_count = length(cells),
                        mean_forecast_dispersion = mean(spreads),
                        realized_dispersion = std(actuals),
                        dispersion_ratio = mean(spreads) / std(actuals),
                    ),
                )
            end
        end
    end

    # -------------------------------------------------- per-cell loss export
    loss_rows = NamedTuple[]
    for row in common_rows
        push!(
            loss_rows, (
                sample_track = "all", model_id = row.model_id,
                origin_index = row.origin_index,
                origin_period = row.origin_period,
                target_period = row.target_period, target_id = row.target_id,
                horizon = row.horizon, error = row.error,
                squared_error = row.squared_error,
                absolute_error = row.absolute_error,
            ),
        )
    end

    # -------------------------------------------------------------- write out
    function write_rows(path, rows)
        isempty(rows) && error("no rows for $path")
        header = collect(string.(keys(rows[1])))
        return open(path, "w") do io
            println(io, join(header, ','))
            for row in rows
                println(io, join(string.(values(row)), ','))
            end
        end
    end
    write_rows(joinpath(output_dir, "stage2b_weighted_scores.csv"), weighted)
    write_rows(joinpath(output_dir, "stage2b_relative_scores.csv"), relative)
    write_rows(joinpath(output_dir, "stage2b_density_crps.csv"), density_rows)
    write_rows(joinpath(output_dir, "stage2b_density_coverage.csv"), coverage_rows)
    write_rows(
        joinpath(output_dir, "stage2b_unemployment_dispersion.csv"),
        dispersion_rows,
    )
    write_rows(joinpath(output_dir, "stage2b_cell_losses.csv"), loss_rows)
    summary_rows = [
        (
                sample_track = row.sample_track, model_id = row.model_id,
                target_id = row.target_id, horizon = row.horizon,
                observation_count = row.observation_count, rmse = row.rmse,
                mae = row.mae,
            ) for row in summaries
    ]
    write_rows(joinpath(output_dir, "stage2b_score_summaries.csv"), summary_rows)

    open(joinpath(output_dir, "stage2b_manifest.toml"), "w") do io
        println(io, "schema = \"beforeit-us-stage2b-scorecard.v1\"")
        println(io, "panel_sha256 = \"$(panel.panel_sha256)\"")
        println(io, "information_track = \"revised_mixed_vintage_diagnostic\"")
        println(io, "real_time = false")
        println(io, "origin_admissible = false")
        println(io, "promotion_eligible = false")
        println(io, "benchmark_model_id = \"$benchmark_model_id\"")
        println(io, "model_ids = [$(join(map(id -> "\"$id\"", model_ids), ", "))]")
        println(io, "origins = $(length(origin_indices))")
        println(io, "common_cells = $(length(common_keys))")
        println(io, "pilot_truncated_smoke_only = $pilot_truncated")
        println(io, "protocol = \"STAGE2B_PROTOCOL.md\"")
        for (label, directory) in (
                ("v1", v1_dir), ("v2", v2_dir), ("v3", v3_dir), ("dsge", dsge_dir),
            )
            println(io, "input_$label = \"$directory\"")
        end
    end
    println("stage2b scorecard written to $output_dir")
    println("model_ids: $(join(model_ids, ", "))")
    return println("common cells: $(length(common_keys))")
end

main(ARGS)
