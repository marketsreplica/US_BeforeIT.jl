#!/usr/bin/env julia

include(joinpath(@__DIR__, "BEANIPADiscovery.jl"))

using .BEANIPADiscovery
using JSON

function usage()
    return """
    Usage:
      julia --project=scripts/us \\
        scripts/us/forecasting/vintages/bea_nipa/live_probe.jl \\
        --live YEAR QUARTER ARCHIVE_LABEL_SUBSTRING

    Example:
      ... --live 2007 Q1 Advance

    This probe retrieves official BEA discovery JSON only. It does not download
    Excel release bytes, mutate current_inventory.toml, admit an origin, or
    produce READY evidence.
    """
end

function main(arguments)
    length(arguments) == 4 && arguments[1] == "--live" || error(usage())
    year = tryparse(Int, arguments[2])
    year === nothing && error("YEAR must be an integer\n\n$(usage())")
    quarter_match = match(r"^[Qq]([1-4])$", arguments[3])
    quarter_match === nothing &&
        error("QUARTER must be Q1, Q2, Q3, or Q4\n\n$(usage())")
    quarter = parse(Int, quarter_match.captures[1])
    result = live_discover(
        year,
        quarter;
        archive_label_contains = arguments[4],
    )
    println(JSON.json(result, 2))
    return nothing
end

try
    main(ARGS)
catch error
    println(stderr, sprint(showerror, error))
    exit(2)
end
