#!/usr/bin/env julia

using Dates

include(joinpath(@__DIR__, "BEAHMI7HistoricalCapture.jl"))
using .BEAHMI7HistoricalCapture

function usage(io = stdout)
    return println(
        io,
        """
        Usage:
          julia --startup-file=no --project=scripts/us \\
            scripts/us/forecasting/vintages/bea_nipa/historical/capture_present_day.jl \\
            --capture-id ID \\
            --raw-root /absolute/canonical/path/to/data/us/raw \\
            --terms-reviewed-local-date YYYY-MM-DD \\
            --live

        Sealed capture IDs:
          bea_hmi7_2019q4_advance_monthly_snapshot
          bea_hmi7_2021q2_advance_annual_update_monthly_snapshot

        This performs a live network request for one exact Section 1/Section 2
        pair. It cannot mutate the forecast inventory or authorize empirical use.
        """,
    )
end

function parse_arguments(arguments)
    values = Dict{String, String}()
    live = false
    index = 1
    while index <= length(arguments)
        argument = arguments[index]
        if argument == "--live"
            live && error("--live must not be repeated")
            live = true
            index += 1
        elseif argument in (
                "--capture-id",
                "--raw-root",
                "--terms-reviewed-local-date",
            )
            haskey(values, argument) &&
                error("$argument must not be repeated")
            index < length(arguments) ||
                error("$argument requires one value")
            value = arguments[index + 1]
            startswith(value, "--") &&
                error("$argument requires one value")
            values[argument] = value
            index += 2
        elseif argument in ("--help", "-h")
            usage()
            return nothing
        else
            error("unknown argument: $argument")
        end
    end
    live || error("--live is required")
    for required in (
            "--capture-id",
            "--raw-root",
            "--terms-reviewed-local-date",
        )
        haskey(values, required) || error("$required is required")
    end
    return (
        capture_id = values["--capture-id"],
        raw_root = values["--raw-root"],
        terms_reviewed_local_date =
            values["--terms-reviewed-local-date"],
        live = live,
    )
end

function main(arguments)
    options = try
        parse_arguments(arguments)
    catch error
        println(stderr, "argument error: ", sprint(showerror, error))
        usage(stderr)
        return 2
    end
    options === nothing && return 0
    result = try
        capture_present_day(
            options.capture_id,
            options.raw_root;
            live = options.live,
            terms_reviewed_local_date =
                options.terms_reviewed_local_date,
        )
    catch error
        println(stderr, "capture refused: ", sprint(showerror, error))
        return 1
    end
    println("bundle_path = ", result.bundle_path)
    println("pair_sha256 = ", result.pair_sha256)
    println("receipt_path = ", result.receipt_path)
    println("receipt_sha256 = ", result.receipt_sha256)
    println("receipt_file_sha256 = ", result.receipt_file_sha256)
    println(
        "historical_first_state_verified = ",
        result.historical_first_state_verified,
    )
    println(
        "historical_availability_verified = ",
        result.historical_availability_verified,
    )
    println("origin_admissible = ", result.origin_admissible)
    println(
        "empirical_execution_allowed = ",
        result.empirical_execution_allowed,
    )
    println(
        "inventory_mutation_authorized = ",
        result.inventory_mutation_authorized,
    )
    println("production_authorized = ", result.production_authorized)
    println("ready = ", result.ready)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
