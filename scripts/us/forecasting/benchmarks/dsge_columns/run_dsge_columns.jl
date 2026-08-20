# ---------------------------------------------------------------------------
# Generate the Stage-2b DSGE scored columns (dsge_small_nk, dsge_sw07) over
# the full 61-origin grid of the revised-data comparison.
#
# Usage:
#   JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
#     julia --startup-file=no --project=scripts/us \
#     scripts/us/forecasting/benchmarks/dsge_columns/run_dsge_columns.jl \
#     <output-dir> [column] [max-origins] [paths]
#
#   column ∈ {both, dsge_small_nk, dsge_sw07}; default both.
#
# Outputs per column directory <output-dir>/<column>/:
#   dsge_ensemble_summaries.csv  (schema-compatible with abm_ensemble_summaries)
#   dsge_origin_status.csv       (per-origin estimation/solution status)
#   dsge_parameter_modes.csv     (per-origin posterior modes)
#   dsge_predictive_draws.jld2   (raw 500-path predictive draws, for CRPS)
#   provenance.toml
# ---------------------------------------------------------------------------

import JLD2
import SHA

include(joinpath(@__DIR__, "USDSGEColumns.jl"))
using .USDSGEColumns
const D = USDSGEColumns

const REPO = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const PANEL_PATH = joinpath(
    REPO, "scripts", "us", "forecasting", "diagnostics", "revised_data",
    "fixtures", "quarterly_panel.csv",
)
const EXPECTED_PANEL_SHA256 =
    "f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe"
const SW07_PANEL_PATH = joinpath(@__DIR__, "sw07_panel.csv")
const MINIMUM_TRAINING_QUARTERS = 40

function load_frozen_panel()
    content = read(PANEL_PATH)
    digest = bytes2hex(SHA.sha256(content))
    digest == EXPECTED_PANEL_SHA256 ||
        error("frozen panel hash mismatch: $digest")
    lines = split(String(content), '\n')
    header = split(strip(lines[1]), ',')
    periods = String[]
    rows = Vector{Float64}[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(strip(line), ',')
        push!(periods, String(fields[1]))
        push!(rows, [parse(Float64, x) for x in fields[2:end]])
    end
    values = Matrix{Float64}(reduce(vcat, (r' for r in rows)))
    return periods, values, String.(header[2:end]), digest
end

function write_csv(path::AbstractString, header::Vector{String}, rows)
    return open(path, "w") do io
        println(io, join(header, ','))
        for row in rows
            println(io, join(string.(row), ','))
        end
    end
end

function main(args)
    length(args) >= 1 || error("usage: run_dsge_columns.jl <output-dir> [column] [max-origins] [paths]")
    output_root = args[1]
    column_request = length(args) >= 2 ? args[2] : "both"
    max_origins = length(args) >= 3 ? parse(Int, args[3]) : typemax(Int)
    paths = length(args) >= 4 ? parse(Int, args[4]) : D.PREDICTIVE_PATHS
    periods, values, targets, panel_sha = load_frozen_panel()
    origin_indices = collect(MINIMUM_TRAINING_QUARTERS:(length(periods) - 1))
    length(origin_indices) > max_origins &&
        (origin_indices = origin_indices[1:max_origins])
    columns = column_request == "both" ?
        [D.SMALL_NK_COLUMN, D.SW07_COLUMN] : [column_request]
    sw07_panel = D.sw07_load_panel(SW07_PANEL_PATH)
    module_sha = bytes2hex(SHA.sha256(read(joinpath(@__DIR__, "USDSGEColumns.jl"))))
    kernel_sha = bytes2hex(SHA.sha256(read(joinpath(@__DIR__, "estimation_kernel.jl"))))
    sw07_model_sha = bytes2hex(SHA.sha256(read(joinpath(@__DIR__, "sw07_model.jl"))))
    sw07_panel_sha = bytes2hex(SHA.sha256(read(SW07_PANEL_PATH)))

    for column in columns
        started = time()
        result = D.generate_dsge_column(
            column, periods, values, targets;
            origin_indices = origin_indices,
            sw07_panel = column == D.SW07_COLUMN ? sw07_panel : nothing,
            paths = paths,
        )
        directory = joinpath(output_root, column)
        mkpath(directory)
        write_csv(
            joinpath(directory, "dsge_ensemble_summaries.csv"),
            [
                "variant", "origin_index", "origin_period", "target_period",
                "target_id", "horizon", "paths_used", "ensemble_mean",
                "ensemble_median", "ensemble_sd", "monte_carlo_standard_error",
                "percentile_05", "percentile_10", "percentile_25",
                "percentile_75", "percentile_90", "percentile_95",
            ],
            [
                (
                        r.variant, r.origin_index, r.origin_period, r.target_period,
                        r.target_id, r.horizon, r.paths_used, r.ensemble_mean,
                        r.ensemble_median, r.ensemble_sd,
                        r.monte_carlo_standard_error, r.percentile_05,
                        r.percentile_10, r.percentile_25, r.percentile_75,
                        r.percentile_90, r.percentile_95,
                    ) for r in result.rows
            ],
        )
        write_csv(
            joinpath(directory, "dsge_origin_status.csv"),
            [
                "variant", "origin_index", "origin_period",
                "training_observations", "estimation_status", "determinate",
                "eu_existence", "eu_uniqueness", "loglikelihood",
                "log_posterior", "function_evaluations", "okun_intercept",
                "okun_slope", "okun_sigma", "auxiliary_growth_projection",
                "seconds",
            ],
            [
                (
                        s.variant, s.origin_index, s.origin_period,
                        s.training_observations, s.estimation_status, s.determinate,
                        s.eu_existence, s.eu_uniqueness, s.loglikelihood,
                        s.log_posterior, s.function_evaluations, s.okun_intercept,
                        s.okun_slope, s.okun_sigma, s.auxiliary_growth_projection,
                        s.seconds,
                    ) for s in result.statuses
            ],
        )
        write_csv(
            joinpath(directory, "dsge_parameter_modes.csv"),
            ["origin_index", "parameter", "mode_value"],
            result.parameter_modes,
        )
        draw_keys = sort(collect(keys(result.draws)))
        JLD2.jldopen(joinpath(directory, "dsge_predictive_draws.jld2"), "w") do file
            for key in draw_keys
                origin_index, target, horizon = key
                file["draws/$origin_index/$target/$horizon"] = result.draws[key]
            end
            file["origin_indices"] = origin_indices
            file["column"] = column
        end
        open(joinpath(directory, "provenance.toml"), "w") do io
            println(io, "schema = \"beforeit-us-stage2b-dsge-column.v1\"")
            println(io, "column = \"$column\"")
            println(io, "panel_sha256 = \"$panel_sha\"")
            println(io, "module_sha256 = \"$module_sha\"")
            println(io, "estimation_kernel_sha256 = \"$kernel_sha\"")
            println(io, "sw07_model_sha256 = \"$sw07_model_sha\"")
            println(io, "sw07_panel_sha256 = \"$sw07_panel_sha\"")
            println(io, "sealed_small_nk_module_sha256 = \"$(D.SMALL_NK_MODULE_SHA256)\"")
            println(io, "origins = $(length(origin_indices))")
            println(io, "paths = $paths")
            println(io, "julia_version = \"$(VERSION)\"")
            println(io, "information_track = \"revised_mixed_vintage_diagnostic\"")
            println(io, "real_time = false")
            println(io, "origin_admissible = false")
            println(io, "promotion_eligible = false")
            println(io, "parameter_uncertainty_in_densities = false")
            println(io, "unemployment_rate_source = \"auxiliary_okun_bridge_per_origin_ols\"")
            println(io, "effr_lower_bound_truncation = $(D.EFFR_LOWER_BOUND)")
            println(io, "seconds = $(round(time() - started; digits = 1))")
        end
        println("column $column complete in $(round(time() - started; digits = 1))s -> $directory")
    end
    return
end

main(ARGS)
