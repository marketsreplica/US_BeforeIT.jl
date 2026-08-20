# ---------------------------------------------------------------------------
# Stage-2b formal inference (workstream 2b-5; frozen protocol STAGE2B_PROTOCOL.md)
#
# Consumes the composite scorecard's matched per-cell losses and produces:
#   1. HLN-corrected Diebold–Mariano tests, squared loss, per
#      (track, target, horizon), for every column against the VAR(1) anchor
#      and for the v3 ABM against every non-ABM column.
#   2. Romano–Wolf step-down (studentized stationary bootstrap) over the
#      family {v3 vs each non-ABM column} per (track, target set), on
#      per-origin weighted losses over complete-cell origins.
#   3. Hansen–Lunde–Nason Model Confidence Sets per (track, target set) over
#      all columns' per-origin weighted losses (T_max, block length 4,
#      2000 replications, alpha = 0.10, fixed seed).
#
# Usage:
#   julia --startup-file=no --project=scripts/us \
#     scripts/us/forecasting/diagnostics/stage2b/run_stage2b_inference.jl \
#     <scorecard-dir>
# ---------------------------------------------------------------------------

using Statistics

include(joinpath(@__DIR__, "..", "..", "inference", "USForecastInference.jl"))
using .USForecastInference

const HORIZONS = [1, 2, 4, 8, 12]
const HORIZON_WEIGHTS = Dict(1 => 0.3, 2 => 0.25, 4 => 0.2, 8 => 0.15, 12 => 0.1)
const TARGET_SETS = [
    ("headline_real_gdp_gdp_deflator", ["real_gdp", "gdp_deflator"]),
    (
        "secondary_nominal_gdp_effective_federal_funds_rate",
        ["nominal_gdp", "effective_federal_funds_rate"],
    ),
    ("labour_unemployment_rate", ["unemployment_rate"]),
]
const ACUTE_FIRST = "2020Q1"
const ACUTE_LAST = "2021Q4"
const V3_COLUMN = "beforeit_abm_us_v3_mean"
const ANCHOR = "beforeit_var_p1_constant"
const ABM_FAMILY_PREFIX = "beforeit_abm_us_"
const MCS_ALPHA = 0.1
const MCS_REPLICATIONS = 2000
const MCS_BLOCK_LENGTH = 4
const RW_REPLICATES = 4999
const INFERENCE_SEED = 20260817

quarter_ordinal(period) =
    4 * parse(Int, period[1:4]) + parse(Int, period[6:6])

function main(args)
    length(args) >= 1 || error("usage: run_stage2b_inference.jl <scorecard-dir>")
    directory = args[1]
    lines = readlines(joinpath(directory, "stage2b_cell_losses.csv"))
    header = split(lines[1], ',')
    column_of = Dict(String(h) => i for (i, h) in enumerate(header))
    rows = NamedTuple[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ',')
        push!(
            rows, (
                model_id = String(fields[column_of["model_id"]]),
                origin_index = parse(Int, fields[column_of["origin_index"]]),
                origin_period = String(fields[column_of["origin_period"]]),
                target_period = String(fields[column_of["target_period"]]),
                target_id = String(fields[column_of["target_id"]]),
                horizon = parse(Int, fields[column_of["horizon"]]),
                squared_error = parse(Float64, fields[column_of["squared_error"]]),
            ),
        )
    end
    model_ids = sort(unique(row.model_id for row in rows))
    max_origin = maximum(row.origin_index for row in rows)
    # panel length is max origin + 1 (last origin = length - 1)
    balanced_last = (max_origin + 1) - 12

    in_track = (row, track) -> begin
        if track == "abm_all_available_common_cells"
            true
        elseif track == "abm_balanced_h12_common_cells"
            row.origin_index <= balanced_last
        else
            !(
                quarter_ordinal(ACUTE_FIRST) <= quarter_ordinal(row.target_period) <=
                    quarter_ordinal(ACUTE_LAST)
            )
        end
    end
    tracks = [
        "abm_all_available_common_cells",
        "abm_balanced_h12_common_cells",
        "abm_pandemic_masked_common_cells",
    ]

    # index: (model, origin, target, horizon) -> squared error
    losses = Dict{Tuple{String, Int, String, Int}, Float64}()
    for row in rows
        losses[(row.model_id, row.origin_index, row.target_id, row.horizon)] =
            row.squared_error
    end
    cell_rows = Dict{Tuple{String, Int}, Vector{NamedTuple}}()
    for row in rows
        push!(get!(cell_rows, (row.model_id, row.horizon), NamedTuple[]), row)
    end

    # ------------------------------------------------------------- 1. HLN-DM
    dm_rows = NamedTuple[]
    non_abm = [m for m in model_ids if !startswith(m, ABM_FAMILY_PREFIX)]
    pairs = Tuple{String, String}[]
    for model in model_ids
        model == ANCHOR && continue
        push!(pairs, (model, ANCHOR))
    end
    for challenger in non_abm
        challenger == ANCHOR && continue
        push!(pairs, (V3_COLUMN, challenger))
    end
    for track in tracks
        for (model, comparator) in pairs
            for target in unique(row.target_id for row in rows)
                for horizon in HORIZONS
                    model_errors = Float64[]
                    comparator_errors = Float64[]
                    for row in rows
                        row.model_id == model || continue
                        row.target_id == target || continue
                        row.horizon == horizon || continue
                        in_track(row, track) || continue
                        comparator_key =
                            (comparator, row.origin_index, target, horizon)
                        haskey(losses, comparator_key) || continue
                        push!(model_errors, sqrt(row.squared_error))
                        push!(comparator_errors, sqrt(losses[comparator_key]))
                    end
                    length(model_errors) >= max(10, horizon + 2) || continue
                    differential = loss_differential(
                        model_errors, comparator_errors; loss = :squared,
                    )
                    all(iszero, differential) && continue
                    result = hln_dm(differential, horizon)
                    push!(
                        dm_rows, (
                            sample_track = track, model_id = model,
                            comparator_id = comparator, target_id = target,
                            horizon = horizon,
                            observation_count = length(differential),
                            mean_differential = mean(differential),
                            dm_statistic = result.statistic,
                            p_value = result.p_value,
                            favors_model = mean(differential) < 0.0,
                        ),
                    )
                end
            end
        end
    end

    # ------------------------------- per-origin weighted losses per target set
    weighted_losses = Dict{Tuple{String, String, String}, Dict{Int, Float64}}()
    for track in tracks
        for (set_name, target_ids) in TARGET_SETS
            target_weight = 1.0 / length(target_ids)
            for model in model_ids
                per_origin = Dict{Int, Float64}()
                complete = Dict{Int, Bool}()
                for origin in unique(row.origin_index for row in rows)
                    total = 0.0
                    ok = true
                    for target in target_ids, horizon in HORIZONS
                        key = (model, origin, target, horizon)
                        if !haskey(losses, key)
                            ok = false
                            break
                        end
                        # track filter applies at the cell level via target period
                        cell = filter(
                            r -> r.model_id == model &&
                                r.origin_index == origin &&
                                r.target_id == target && r.horizon == horizon,
                            rows,
                        )
                        if isempty(cell) || !in_track(cell[1], track)
                            ok = false
                            break
                        end
                        total += target_weight * HORIZON_WEIGHTS[horizon] *
                            losses[key]
                    end
                    if ok
                        per_origin[origin] = total
                    end
                end
                weighted_losses[(track, set_name, model)] = per_origin
            end
        end
    end

    # ------------------------------------------------ 2. Romano–Wolf families
    rw_rows = NamedTuple[]
    for track in tracks
        for (set_name, _) in TARGET_SETS
            family = [m for m in non_abm if m != V3_COLUMN]
            v3 = weighted_losses[(track, set_name, V3_COLUMN)]
            common_origins = sort(collect(keys(v3)))
            for model in family
                common_origins =
                    intersect(
                    common_origins,
                    sort(collect(keys(weighted_losses[(track, set_name, model)])))
                )
            end
            length(common_origins) >= 15 || continue
            differentials = Matrix{Float64}(
                undef, length(common_origins), length(family),
            )
            for (j, model) in enumerate(family)
                other = weighted_losses[(track, set_name, model)]
                for (i, origin) in enumerate(common_origins)
                    differentials[i, j] = v3[origin] - other[origin]
                end
            end
            degenerate = [
                j for j in 1:length(family) if
                    all(iszero, view(differentials, :, j))
            ]
            keep = setdiff(1:length(family), degenerate)
            isempty(keep) && continue
            bootstrap = studentized_stationary_bootstrap(
                differentials[:, keep], fill(12, length(keep));
                block_length = FixedBlockLength(MCS_BLOCK_LENGTH),
                horizon_floor_policy = :max_horizon,
                seed = INFERENCE_SEED,
                replicates = RW_REPLICATES,
            )
            stepdown = romano_wolf_stepdown(
                bootstrap;
                hypothesis_ids = family[keep],
                alternative = :less,
                alpha = 0.05,
            )
            for (j, model) in enumerate(family[keep])
                push!(
                    rw_rows, (
                        sample_track = track, target_set = set_name,
                        challenger = V3_COLUMN, comparator = model,
                        observation_count = length(common_origins),
                        mean_differential = mean(differentials[:, keep][:, j]),
                        adjusted_p_value = stepdown.adjusted_p_values[j],
                        rejected_at_5pct = stepdown.rejected[j],
                    ),
                )
            end
        end
    end

    # ------------------------------------------------------------- 3. MCS
    mcs_rows = NamedTuple[]
    for track in tracks
        for (set_name, _) in TARGET_SETS
            participating = String[]
            origin_sets = Vector{Vector{Int}}()
            for model in model_ids
                per_origin = weighted_losses[(track, set_name, model)]
                isempty(per_origin) && continue
                push!(participating, model)
                push!(origin_sets, sort(collect(keys(per_origin))))
            end
            isempty(participating) && continue
            common = reduce(intersect, origin_sets)
            length(common) >= 15 || continue
            loss_matrix = Matrix{Float64}(
                undef, length(common), length(participating),
            )
            for (j, model) in enumerate(participating)
                per_origin = weighted_losses[(track, set_name, model)]
                for (i, origin) in enumerate(common)
                    loss_matrix[i, j] = per_origin[origin]
                end
            end
            result = model_confidence_set(
                loss_matrix;
                block_length = FixedBlockLength(MCS_BLOCK_LENGTH),
                bootstrap_replications = MCS_REPLICATIONS,
                alpha = MCS_ALPHA,
                seed = INFERENCE_SEED,
            )
            for (j, model) in enumerate(participating)
                push!(
                    mcs_rows, (
                        sample_track = track, target_set = set_name,
                        model_id = model,
                        observation_count = length(common),
                        mean_weighted_loss = mean(loss_matrix[:, j]),
                        mcs_p_value = result.mcs_p_values[j],
                        in_mcs_alpha10 = j in result.included,
                    ),
                )
            end
        end
    end

    function write_rows(path, output_rows)
        isempty(output_rows) && (println("warning: no rows for $path"); return)
        header_names = collect(string.(keys(output_rows[1])))
        return open(path, "w") do io
            println(io, join(header_names, ','))
            for row in output_rows
                println(io, join(string.(values(row)), ','))
            end
        end
    end
    write_rows(joinpath(directory, "stage2b_dm_tests.csv"), dm_rows)
    write_rows(joinpath(directory, "stage2b_romano_wolf.csv"), rw_rows)
    write_rows(joinpath(directory, "stage2b_mcs.csv"), mcs_rows)
    return println(
        "inference written: $(length(dm_rows)) DM rows, " *
            "$(length(rw_rows)) RW rows, $(length(mcs_rows)) MCS rows",
    )
end

main(ARGS)
