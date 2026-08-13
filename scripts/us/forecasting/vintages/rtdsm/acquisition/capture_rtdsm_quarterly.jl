#!/usr/bin/env julia

if !isdefined(@__MODULE__, :RTDSMQuarterlyAcquisition)
    include(joinpath(@__DIR__, "RTDSMQuarterlyAcquisition.jl"))
end
using .RTDSMQuarterlyAcquisition

const USAGE = """
Usage:
  julia capture_rtdsm_quarterly.jl \\
    --live \\
    --raw-root /absolute/canonical/ignored/raw/root \\
    --terms-reviewed-local-date YYYY-MM-DD \\
    --research-purpose-attestation RESEARCH_DIAGNOSTIC_ONLY

This command performs a live five-file research-only RTDSM acquisition.
Without every option exactly as shown, it does not access the network.
"""

function parse_cli(arguments)
    arguments == ["--help"] && return Dict("help" => true)
    result = Dict{String, Any}(
        "help" => false,
        "live" => false,
    )
    index = 1
    while index <= length(arguments)
        option = arguments[index]
        if option == "--live"
            result["live"] == false ||
                throw(ArgumentError("--live may appear only once"))
            result["live"] = true
            index += 1
            continue
        end
        option in (
            "--raw-root",
            "--terms-reviewed-local-date",
            "--research-purpose-attestation",
        ) || throw(ArgumentError("unknown option: $option"))
        haskey(result, option) &&
            throw(ArgumentError("$option may appear only once"))
        index < length(arguments) ||
            throw(ArgumentError("$option requires a value"))
        value = arguments[index + 1]
        startswith(value, "--") &&
            throw(ArgumentError("$option requires a value"))
        result[option] = value
        index += 2
    end
    result["live"] === true ||
        throw(ArgumentError("--live is required"))
    for option in (
            "--raw-root",
            "--terms-reviewed-local-date",
            "--research-purpose-attestation",
        )
        haskey(result, option) ||
            throw(ArgumentError("$option is required"))
    end
    return result
end

function cli_main(arguments = ARGS)
    options = try
        parse_cli(arguments)
    catch error
        println(stderr, "error: ", sprint(showerror, error))
        println(stderr, USAGE)
        return 2
    end
    if options["help"]
        println(USAGE)
        return 0
    end
    result = try
        capture_research_snapshot(
            options["--raw-root"];
            live = options["live"],
            terms_reviewed_local_date =
                options["--terms-reviewed-local-date"],
            research_purpose_attestation =
                options["--research-purpose-attestation"],
        )
    catch error
        println(stderr, "error: ", sprint(showerror, error))
        return 1
    end
    println("bundle_path=", result.bundle_path)
    println("receipt_path=", result.receipt_path)
    println("bundle_sha256=", result.bundle_sha256)
    println("receipt_sha256=", result.receipt_sha256)
    println("receipt_file_sha256=", result.receipt_file_sha256)
    println("research_diagnostic_allowed=true")
    println("training_use_allowed=false")
    println("strict_origin_admissible=false")
    println("truth_admissible=false")
    println("inventory_mutation_authorized=false")
    println("production_authorized=false")
    println("ready=false")
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(cli_main())
end
