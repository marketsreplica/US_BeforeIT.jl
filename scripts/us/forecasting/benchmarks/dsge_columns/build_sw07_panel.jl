# ---------------------------------------------------------------------------
# Build the SW07 observable panel from the fixed FRED retrieval in
# `data/us/stage2b_external/raw/` (retrieval timestamp and SHA-256 sums are
# committed beside the raws).
#
# Observable construction follows the Smets–Wouters (2007) replication
# dataset conventions:
#   pop        = CNP16OV, quarterly mean of monthly levels
#   dy         = 100*dln(GDPC1 / pop)
#   dc         = 100*dln((PCEC/GDPDEF) / pop)
#   dinve      = 100*dln((FPI/GDPDEF) / pop)
#   dw         = 100*dln(COMPNFB/GDPDEF)
#   labobs_raw = 100*ln((PRS85006023 * CE16OV / 100) / pop)   (demeaned per origin)
#   pinfobs    = 100*dln(GDPDEF)
#   robs       = quarterly mean FEDFUNDS / 4
#   dpop       = 100*dln(pop)
#
# Splice: from 2000Q3 the frozen revised-data panel supplies dy, pinfobs and
# robs exactly (dy = real_gdp/4 - dpop, pinfobs = gdp_deflator/4,
# robs = effective_federal_funds_rate/4), so the SW07 estimation data agree
# with the scored truth panel wherever the panel covers the series. The four
# observables the frozen panel does not carry (dc, dinve, dw, labobs) and all
# pre-2000Q3 history come from the FRED retrieval; the small vintage skew this
# creates is disclosed in the model card.
#
# Run:  julia --startup-file=no --project=scripts/us \
#         scripts/us/forecasting/benchmarks/dsge_columns/build_sw07_panel.jl
# ---------------------------------------------------------------------------

import SHA

const HERE = @__DIR__
const REPOSITORY_ROOT = normpath(joinpath(HERE, "..", "..", "..", "..", ".."))
const RAW_DIR = normpath(
    joinpath(HERE, "..", "..", "..", "..", "..", "data", "us", "stage2b_external", "raw"),
)
const RAW_DIR_FALLBACK = RAW_DIR
const PANEL_PATH = normpath(
    joinpath(
        HERE, "..", "..", "diagnostics", "revised_data", "fixtures", "quarterly_panel.csv",
    )
)
const OUTPUT_PATH = joinpath(HERE, "sw07_panel.csv")
const PROVENANCE_PATH = joinpath(HERE, "sw07_panel_provenance.toml")
const PANEL_START = "1955Q1"

raw_dir() = isdir(RAW_DIR) ? RAW_DIR : RAW_DIR_FALLBACK

function read_fred_csv(name::AbstractString)
    path = joinpath(raw_dir(), name * ".csv")
    lines = readlines(path)
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

function quarterly_mean(dates::Vector{String}, values::Vector{Float64})
    order = Dict{String, Vector{Float64}}()
    sequence = String[]
    for (date, value) in zip(dates, values)
        quarter = quarter_of_date(date)
        if !haskey(order, quarter)
            order[quarter] = Float64[]
            push!(sequence, quarter)
        end
        push!(order[quarter], value)
    end
    # keep only complete quarters (3 monthly observations) except for
    # quarterly-native series (1 observation per quarter)
    periods = String[]
    means = Float64[]
    for quarter in sequence
        sample = order[quarter]
        length(sample) in (1, 3) || continue
        push!(periods, quarter)
        push!(means, sum(sample) / length(sample))
    end
    return periods, means
end

function as_map(periods::Vector{String}, values::Vector{Float64})
    return Dict(p => v for (p, v) in zip(periods, values))
end

function quarter_add_local(period::AbstractString, quarters::Int)
    year = parse(Int, period[1:4])
    quarter = parse(Int, period[6:6])
    total = year * 4 + (quarter - 1) + quarters
    return string(div(total, 4), "Q", mod(total, 4) + 1)
end

function main()
    gdpc1 = as_map(quarterly_mean(read_fred_csv("GDPC1")...)...)
    gdpdef = as_map(quarterly_mean(read_fred_csv("GDPDEF")...)...)
    pcec = as_map(quarterly_mean(read_fred_csv("PCEC")...)...)
    fpi = as_map(quarterly_mean(read_fred_csv("FPI")...)...)
    compnfb = as_map(quarterly_mean(read_fred_csv("COMPNFB")...)...)
    hours_index = as_map(quarterly_mean(read_fred_csv("PRS85006023")...)...)
    ce16 = as_map(quarterly_mean(read_fred_csv("CE16OV")...)...)
    pop = as_map(quarterly_mean(read_fred_csv("CNP16OV")...)...)
    fedfunds = as_map(quarterly_mean(read_fred_csv("FEDFUNDS")...)...)

    # frozen panel splice inputs
    panel_lines = readlines(PANEL_PATH)
    header = split(strip(panel_lines[1]), ',')
    column = Dict(String(name) => i for (i, name) in enumerate(header))
    panel_real = Dict{String, Float64}()
    panel_deflator = Dict{String, Float64}()
    panel_effr = Dict{String, Float64}()
    for line in panel_lines[2:end]
        isempty(strip(line)) && continue
        fields = split(strip(line), ',')
        period = String(fields[column["period"]])
        panel_real[period] = parse(Float64, fields[column["real_gdp"]])
        panel_deflator[period] = parse(Float64, fields[column["gdp_deflator"]])
        panel_effr[period] =
            parse(Float64, fields[column["effective_federal_funds_rate"]])
    end

    output_lines = ["period,dy,dc,dinve,dw,labobs_raw,pinfobs,robs,dpop"]
    period = PANEL_START
    count_spliced = 0
    while true
        previous = quarter_add_local(period, -1)
        needed = (gdpc1, gdpdef, pcec, fpi, compnfb, hours_index, ce16, pop, fedfunds)
        all(map -> haskey(map, period), needed) || break
        all(map -> haskey(map, previous), needed) || begin
            period = quarter_add_local(period, 1)
            continue
        end
        dln = (map, p, q) -> 100.0 * log(map[p] / map[q])
        dpop = dln(pop, period, previous)
        dy_fred = dln(gdpc1, period, previous) - dpop
        dc = 100.0 * log(
            (pcec[period] / gdpdef[period]) / pop[period] /
                ((pcec[previous] / gdpdef[previous]) / pop[previous]),
        )
        dinve = 100.0 * log(
            (fpi[period] / gdpdef[period]) / pop[period] /
                ((fpi[previous] / gdpdef[previous]) / pop[previous]),
        )
        dw = 100.0 * log(
            (compnfb[period] / gdpdef[period]) /
                (compnfb[previous] / gdpdef[previous]),
        )
        labobs_raw = 100.0 * log(
            (hours_index[period] * ce16[period] / 100.0) / pop[period],
        )
        pinfobs_fred = dln(gdpdef, period, previous)
        robs_fred = fedfunds[period] / 4.0
        # splice with the frozen panel where it covers the series
        if haskey(panel_real, period)
            dy = panel_real[period] / 4.0 - dpop
            pinfobs = panel_deflator[period] / 4.0
            robs = panel_effr[period] / 4.0
            count_spliced += 1
        else
            dy = dy_fred
            pinfobs = pinfobs_fred
            robs = robs_fred
        end
        push!(
            output_lines,
            join(
                [
                    period,
                    string(round(dy; digits = 12)),
                    string(round(dc; digits = 12)),
                    string(round(dinve; digits = 12)),
                    string(round(dw; digits = 12)),
                    string(round(labobs_raw; digits = 12)),
                    string(round(pinfobs; digits = 12)),
                    string(round(robs; digits = 12)),
                    string(round(dpop; digits = 12)),
                ],
                ",",
            ),
        )
        period = quarter_add_local(period, 1)
    end

    open(OUTPUT_PATH, "w") do io
        for line in output_lines
            println(io, line)
        end
    end
    panel_sha = bytes2hex(SHA.sha256(read(OUTPUT_PATH)))
    raw_files = sort(filter(f -> endswith(f, ".csv"), readdir(raw_dir())))
    open(PROVENANCE_PATH, "w") do io
        println(io, "schema = \"beforeit-us-sw07-panel-provenance.v1\"")
        println(io, "panel_file = \"sw07_panel.csv\"")
        println(io, "panel_sha256 = \"$panel_sha\"")
        println(io, "panel_rows = $(length(output_lines) - 1)")
        println(io, "panel_start = \"$(split(output_lines[2], ',')[1])\"")
        println(io, "panel_end = \"$(split(output_lines[end], ',')[1])\"")
        println(io, "spliced_rows_from_frozen_panel = $count_spliced")
        println(io, "frozen_panel_path = \"scripts/us/forecasting/diagnostics/revised_data/fixtures/quarterly_panel.csv\"")
        println(io, "raw_retrieval_dir = \"data/us/stage2b_external/raw\"")
        retrieved_at = strip(read(joinpath(raw_dir(), "RETRIEVED_AT.txt"), String))
        println(io, "raw_retrieved_at_utc = \"$retrieved_at\"")
        println(io, "")
        println(io, "[raw_sha256]")
        for file in raw_files
            digest = bytes2hex(SHA.sha256(read(joinpath(raw_dir(), file))))
            println(io, "\"$file\" = \"$digest\"")
        end
    end
    println("wrote $(OUTPUT_PATH): $(length(output_lines) - 1) rows, sha256 $panel_sha")
    return println("spliced from frozen panel: $count_spliced rows")
end

main()
