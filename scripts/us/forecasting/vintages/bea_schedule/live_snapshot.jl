#!/usr/bin/env julia

include(joinpath(@__DIR__, "BEAScheduleMonitor.jl"))
using .BEAScheduleMonitor

function usage()
    return """
    Usage:
      julia --startup-file=no --project=scripts/us \\
        scripts/us/forecasting/vintages/bea_schedule/live_snapshot.jl \\
        --live OUTPUT_DIR

    This opt-in command fetches the mutable official BEA schedule, requires the
    expected 2026Q3 advance-GDP row, and writes exact response-body bytes plus
    hash-addressed metadata under an existing caller-supplied directory.

    The output is mutable schedule evidence only. It is not release-byte,
    release-event, origin-availability, admission, or READY evidence, and it
    does not update any forecasting inventory or contract.
    """
end

function main(arguments)
    length(arguments) == 2 && arguments[1] == "--live" ||
        error(usage())
    output_dir = arguments[2]
    result = capture_live_snapshot(output_dir)
    println("validated mutable BEA schedule row:")
    println("  date: ", result.event.date_text)
    println("  time: ", result.event.time_text)
    println("  title: ", result.event.title)
    println("exact raw response:")
    println("  path: ", result.raw_path)
    println("  sha256: ", result.raw_sha256)
    println("hash-addressed metadata:")
    println("  path: ", result.metadata_path)
    println("  sha256: ", result.metadata_sha256)
    println(
        "scope: mutable schedule snapshot only; not release/origin evidence",
    )
    return nothing
end

try
    main(ARGS)
catch error
    println(stderr, sprint(showerror, error))
    exit(2)
end
