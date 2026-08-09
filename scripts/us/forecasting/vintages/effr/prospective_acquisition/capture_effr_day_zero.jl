#!/usr/bin/env julia

include(joinpath(@__DIR__, "USEFFRDayZeroAcquisition.jl"))
using .USEFFRDayZeroAcquisition

function usage()
    println(
        stderr,
        """
usage:
  capture_effr_day_zero.jl --phase first|revision-check \\
    --transaction-id ID --output-root DIRECTORY [--predecessor-bundle DIRECTORY] \\
    [--execute-live]

Without --execute-live the command is a network-free, write-free dry run.
The revision-check phase always requires --predecessor-bundle.
""",
    )
    return 2
end

function parse_args(arguments)
    values = Dict{String, String}()
    execute_live = false
    index = 1
    while index <= length(arguments)
        argument = arguments[index]
        if argument == "--execute-live"
            execute_live && return nothing
            execute_live = true
            index += 1
            continue
        end
        argument in (
            "--phase",
            "--transaction-id",
            "--output-root",
            "--predecessor-bundle",
        ) || return nothing
        index == length(arguments) && return nothing
        haskey(values, argument) && return nothing
        values[argument] = arguments[index + 1]
        index += 2
    end
    all(
        key -> haskey(values, key),
        ("--phase", "--transaction-id", "--output-root"),
    ) || return nothing
    return (;
        phase = values["--phase"],
        transaction_id = values["--transaction-id"],
        output_root = values["--output-root"],
        predecessor_bundle =
            get(values, "--predecessor-bundle", nothing),
        execute_live,
    )
end

function print_plan(plan)
    println("Mode: ", plan.mode)
    println("Phase: ", plan.phase)
    println("State candidate: ", plan.state_class)
    println("Effective date: ", plan.effective_date)
    println("Publication date: ", plan.publication_date)
    println(
        "Window: ",
        plan.capture_not_before_utc,
        " through ",
        plan.capture_deadline_utc,
    )
    for (index, request) in enumerate(plan.ordered_requests)
        println(
            "Request ",
            index,
            ": ",
            request.object_id,
            " ",
            request.requested_url,
        )
    end
    println("Output bundle: ", plan.output_bundle)
    println("Predecessor: ", plan.predecessor_bundle)
    println("Origin admissible: ", plan.gates["origin_admissible"])
    println("Promotion eligible: ", plan.gates["promotion_eligible"])
    return nothing
end

parsed = parse_args(ARGS)
parsed === nothing && exit(usage())

if !parsed.execute_live
    plan = dry_run_plan(
        parsed.phase;
        transaction_id = parsed.transaction_id,
        output_root = parsed.output_root,
        predecessor_bundle = parsed.predecessor_bundle,
    )
    print_plan(plan)
    exit(0)
end

result = acquire_day_zero(
    parsed.output_root;
    phase = parsed.phase,
    transaction_id = parsed.transaction_id,
    predecessor_bundle = parsed.predecessor_bundle,
)
println("Bundle: ", result.bundle_path)
println("Manifest: ", result.manifest_path)
println("Status: ", result.status)
println("Phase completed: ", result.success)
println("Raw capture installed: ", result.raw_capture_installed)
println("Raw capture complete: ", result.raw_capture_complete)
println(
    "One-date receipt validated: ",
    result.one_date_receipt_validated,
)
println("Failure code: ", result.failure_code)
println("Origin admissible: false")
println("Promotion eligible: false")
result.success || exit(1)
