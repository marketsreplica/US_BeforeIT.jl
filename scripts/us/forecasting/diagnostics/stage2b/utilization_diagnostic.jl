# ---------------------------------------------------------------------------
# 2b-3 gate evidence: long-run utilization and capacity under v2 vs v3.
#
# Matched-seed 24-quarter simulations at selected origins; records aggregate
# utilization Y/(K·kappa), the capacity index K·kappa, book capital K, the
# unemployment rate, and annualized real growth per quarter. The 24-quarter
# horizon deliberately exceeds the 12-quarter scoring window: the question is
# whether utilization drifts to its ceiling (the v2 drainage mechanism) or
# stabilizes (the v3 balanced-supply mechanism).
#
# Usage: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
#   julia --startup-file=no --project=scripts/us \
#   scripts/us/forecasting/diagnostics/stage2b/utilization_diagnostic.jl <out.csv>
# ---------------------------------------------------------------------------

using Random
using Statistics
import BeforeIT as Bit

include(
    joinpath(
        @__DIR__, "..", "abm_revised_comparison", "USRevisedDataABMComparison.jl",
    )
)
using .USRevisedDataABMComparison
const ABM = USRevisedDataABMComparison

const ORIGINS = [("2012Q4", 50), ("2016Q4", 66), ("2022Q4", 90)]
const QUARTERS = 24
const PATHS = 16

function simulate_recorded(variant_name, origin_period, path, calibration_path)
    calibration_object = ABM.load_calibration_object(calibration_path)
    calibration_date = ABM.period_to_quarter_end(origin_period)
    parameters, initial_conditions = ABM.abm_origin_inputs(
        calibration_object, calibration_date;
        variant_name = variant_name, origin_period = origin_period,
    )
    seed = ABM.path_seed(ABM.seed_stream_name(variant_name), origin_period, path)
    Random.seed!(seed)
    model = Bit.Model(parameters, initial_conditions)
    rows = NamedTuple[]
    previous_real_gdp = nothing
    for quarter in 0:QUARTERS
        if quarter > 0
            Bit.step!(model; parallel = false)
            Bit.collect_data!(model)
        end
        firms = model.firms
        capacity = sum(firms.K_i .* firms.kappa_i)
        output = sum(firms.Y_i)
        capital = sum(firms.K_i)
        unemployment =
            100.0 * count(==(0), model.w_act.O_h) / Int(model.prop.H_act)
        real_gdp = model.data.real_gdp[end]
        growth = quarter > 0 && previous_real_gdp !== nothing ?
            400.0 * (log(real_gdp) - log(previous_real_gdp)) : NaN
        previous_real_gdp = real_gdp
        push!(
            rows, (
                variant = variant_name, origin = origin_period, path = path,
                quarter = quarter, utilization = output / capacity,
                capacity_index = capacity, book_capital = capital,
                unemployment_rate = unemployment,
                annualized_real_growth = growth,
            ),
        )
    end
    return rows
end

function main(args)
    output_path = isempty(args) ?
        joinpath(@__DIR__, "utilization_diagnostic.csv") : args[1]
    calibration_path = ABM.RECONCILED_CALIBRATION_OBJECT_PATH
    rows = NamedTuple[]
    for (origin, _) in ORIGINS
        for variant in ("headline_v2", "headline_v3")
            for path in 1:PATHS
                try
                    append!(
                        rows,
                        simulate_recorded(variant, origin, path, calibration_path),
                    )
                catch exception
                    println(
                        "failed $variant $origin path $path: " *
                            first(split(sprint(showerror, exception), "\n")),
                    )
                end
            end
        end
        println("origin $origin complete")
    end
    open(output_path, "w") do io
        println(
            io,
            "variant,origin,path,quarter,utilization,capacity_index," *
                "book_capital,unemployment_rate,annualized_real_growth",
        )
        for row in rows
            println(io, join(string.(values(row)), ','))
        end
    end
    # summary to stdout
    for (origin, _) in ORIGINS, variant in ("headline_v2", "headline_v3")
        selected = [
            r for r in rows if r.variant == variant && r.origin == origin
        ]
        isempty(selected) && continue
        by_quarter = q -> [r for r in selected if r.quarter == q]
        u0 = mean(getfield.(by_quarter(0), :utilization))
        u12 = mean(getfield.(by_quarter(12), :utilization))
        u24 = mean(getfield.(by_quarter(24), :utilization))
        c24 = mean(
            r.capacity_index for r in by_quarter(24)
        ) / mean(r.capacity_index for r in by_quarter(0))
        un24 = mean(getfield.(by_quarter(24), :unemployment_rate))
        println(
            "$origin $variant: utilization $(round(u0; digits = 3)) -> " *
                "$(round(u12; digits = 3)) (q12) -> $(round(u24; digits = 3)) (q24); " *
                "capacity growth q0->q24 $(round(100 * (c24 - 1); digits = 1))%; " *
                "unemployment(q24) $(round(un24; digits = 2))%",
        )
    end
    return println("wrote $output_path")
end

main(ARGS)
