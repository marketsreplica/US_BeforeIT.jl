# ---------------------------------------------------------------------------
# Build the trend-growth calibration series for the v3 balanced-growth repair.
#
# Two observed quarterly series from the fixed FRED retrieval in
# `data/us/stage2b_external/raw/` (SHA-256 sums and retrieval timestamp are
# committed beside the raws):
#
#   dlnprod = 100 * dln( GDPC1 / quarterly-mean CE16OV )   labour productivity
#                                                          (output per employed
#                                                          person)
#   dlnlf   = 100 * dln( quarterly-mean CLF16OV )          labour force
#                                                          (demographics and
#                                                          immigration margin)
#
# The v3 kernel computes, at each origin, the trailing-40-quarter mean of each
# series ending at the origin quarter and registers
#   trend_growth_rate = (mean(dlnprod) + mean(dlnlf)) / 100
# on the per-origin calibration copy. The rule is frozen before any scored
# run; no forecast error can reach it.
#
# Run:  julia --startup-file=no --project=scripts/us \
#   scripts/us/forecasting/diagnostics/abm_revised_comparison/build_trend_growth_series.jl
# ---------------------------------------------------------------------------

import SHA

const HERE = @__DIR__
const RAW_DIR = normpath(
    joinpath(HERE, "..", "..", "..", "..", "..", "data", "us", "stage2b_external", "raw"),
)
const OUTPUT_PATH = joinpath(HERE, "trend_growth_series.csv")
const PROVENANCE_PATH = joinpath(HERE, "trend_growth_series_provenance.toml")

function read_fred_csv(name::AbstractString)
    lines = readlines(joinpath(RAW_DIR, name * ".csv"))
    dates = String[]
    values = Float64[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(strip(line), ',')
        raw_value = strip(fields[2])
        (raw_value == "." || isempty(raw_value)) && continue
        push!(dates, String(strip(fields[1])))
        push!(values, parse(Float64, raw_value))
    end
    return dates, values
end

quarter_of_date(date::AbstractString) =
    string(date[1:4], "Q", div(parse(Int, date[6:7]) - 1, 3) + 1)

function quarterly_mean(dates, values)
    sums = Dict{String, Float64}()
    counts = Dict{String, Int}()
    sequence = String[]
    for (date, value) in zip(dates, values)
        quarter = quarter_of_date(date)
        if !haskey(sums, quarter)
            sums[quarter] = 0.0
            counts[quarter] = 0
            push!(sequence, quarter)
        end
        sums[quarter] += value
        counts[quarter] += 1
    end
    periods = String[]
    means = Float64[]
    for quarter in sequence
        counts[quarter] in (1, 3) || continue
        push!(periods, quarter)
        push!(means, sums[quarter] / counts[quarter])
    end
    return Dict(p => v for (p, v) in zip(periods, means)), periods
end

function quarter_add_local(period, quarters)
    year = parse(Int, period[1:4])
    quarter = parse(Int, period[6:6])
    total = year * 4 + (quarter - 1) + quarters
    return string(div(total, 4), "Q", mod(total, 4) + 1)
end

function main()
    gdp, _ = quarterly_mean(read_fred_csv("GDPC1")...)
    employment, _ = quarterly_mean(read_fred_csv("CE16OV")...)
    labour_force, _ = quarterly_mean(read_fred_csv("CLF16OV")...)
    lines = ["period,dlnprod,dlnlf"]
    period = "1990Q1"
    while true
        previous = quarter_add_local(period, -1)
        needed = (gdp, employment, labour_force)
        all(m -> haskey(m, period) && haskey(m, previous), needed) || break
        productivity = 100.0 * log(
            (gdp[period] / employment[period]) /
                (gdp[previous] / employment[previous]),
        )
        force = 100.0 * log(labour_force[period] / labour_force[previous])
        push!(
            lines,
            join(
                [
                    period,
                    string(round(productivity; digits = 12)),
                    string(round(force; digits = 12)),
                ], ",",
            ),
        )
        period = quarter_add_local(period, 1)
    end
    open(OUTPUT_PATH, "w") do io
        for line in lines
            println(io, line)
        end
    end
    digest = bytes2hex(SHA.sha256(read(OUTPUT_PATH)))
    open(PROVENANCE_PATH, "w") do io
        println(io, "schema = \"beforeit-us-trend-growth-series.v1\"")
        println(io, "file = \"trend_growth_series.csv\"")
        println(io, "sha256 = \"$digest\"")
        println(io, "rows = $(length(lines) - 1)")
        println(io, "first_period = \"$(split(lines[2], ',')[1])\"")
        println(io, "last_period = \"$(split(lines[end], ',')[1])\"")
        println(io, "raw_retrieval_dir = \"data/us/stage2b_external/raw\"")
        retrieved = strip(read(joinpath(RAW_DIR, "RETRIEVED_AT.txt"), String))
        println(io, "raw_retrieved_at_utc = \"$retrieved\"")
        println(io, "estimation_rule = \"trailing_40_quarter_mean_through_origin\"")
        println(io, "series = [\"dlnprod = 100*dln(GDPC1/CE16OV_q)\", \"dlnlf = 100*dln(CLF16OV_q)\"]")
        for name in ("GDPC1", "CE16OV", "CLF16OV")
            file_digest = bytes2hex(SHA.sha256(read(joinpath(RAW_DIR, name * ".csv"))))
            println(io, "raw_sha256_$name = \"$file_digest\"")
        end
    end
    return println("wrote $OUTPUT_PATH ($(length(lines) - 1) rows), sha256 $digest")
end

main()
