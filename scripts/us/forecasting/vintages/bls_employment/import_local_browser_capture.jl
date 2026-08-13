#!/usr/bin/env julia

using Dates

if !isdefined(Main, :BLSEmploymentArchiveCapture)
    include(joinpath(@__DIR__, "BLSEmploymentArchiveCapture.jl"))
end
using .BLSEmploymentArchiveCapture

function usage(io = stdout)
    return println(
        io,
        """
        Usage:
          julia --startup-file=no --project=scripts/us \\
            scripts/us/forecasting/vintages/bls_employment/import_local_browser_capture.jl \\
            --input PATH \\
            --raw-root PATH \\
            --terms-reviewed-local-date YYYY-MM-DD \\
            --browser-download-observed-at-utc YYYY-MM-DDTHH:MM:SSZ \\
            --live

        This imports only the pinned January 10, 2020 Employment Situation PDF.
        It performs no network request and cannot mutate the forecast inventory.
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
                "--input",
                "--raw-root",
                "--terms-reviewed-local-date",
                "--browser-download-observed-at-utc",
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
            exit(0)
        else
            error("unknown argument: $argument")
        end
    end
    live || error("--live is required")
    for required in (
            "--input",
            "--raw-root",
            "--terms-reviewed-local-date",
            "--browser-download-observed-at-utc",
        )
        haskey(values, required) || error("$required is required")
    end
    return (
        input = values["--input"],
        raw_root = values["--raw-root"],
        terms_reviewed_local_date =
            values["--terms-reviewed-local-date"],
        browser_download_observed_at_utc =
            values["--browser-download-observed-at-utc"],
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

    result = try
        import_browser_download(
            options.input,
            options.raw_root;
            live = options.live,
            terms_reviewed_local_date =
                options.terms_reviewed_local_date,
            browser_download_observed_at_utc =
                options.browser_download_observed_at_utc,
        )
    catch error
        println(stderr, "import refused: ", sprint(showerror, error))
        return 1
    end

    println("raw_object_path = ", result.raw_object_path)
    println("raw_sha256 = ", result.raw_sha256)
    println("raw_byte_count = ", result.raw_byte_count)
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
    println("ready = ", result.ready)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
