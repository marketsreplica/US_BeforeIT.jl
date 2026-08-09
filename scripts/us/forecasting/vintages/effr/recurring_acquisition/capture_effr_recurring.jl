#!/usr/bin/env julia

include(joinpath(@__DIR__, "USEFFRRecurringAcquisition.jl"))
using .USEFFRRecurringAcquisition

function usage(io::IO = stdout)
    return println(
        io,
        """
        Usage:
          capture_effr_recurring.jl \\
            --publication-date YYYY-MM-DD \\
            --phase first|revision-check \\
            --output-root PATH \\
            [--execute-live]

        Without --execute-live this command is network-free and write-free.
        The flag is a separate bounded operator authorization for exactly one
        campaign slot and exactly six built-in direct GETs; it does not change
        any frozen campaign gate. The persisted operator flag, transport label,
        and downloader-invocation count are local unauthenticated assertions,
        not an independent network or identity witness. This CLI never exposes
        the injected synthetic test transport or test clock accepted by the
        module's test-only path.
        Dates, effective dates, windows, transaction IDs, paths, and predecessors
        are derived from the frozen campaign schedule and cannot be overridden.
        """,
    )
end

function parse_args(args)
    publication_date = nothing
    phase = nothing
    output_root = nothing
    execute_live = false
    index = 1
    while index <= length(args)
        argument = args[index]
        if argument == "--execute-live"
            execute_live && error("duplicate --execute-live")
            execute_live = true
            index += 1
        elseif argument in (
                "--publication-date",
                "--phase",
                "--output-root",
            )
            index < length(args) ||
                error("$argument requires a value")
            value = args[index + 1]
            startswith(value, "--") &&
                error("$argument requires a value")
            if argument == "--publication-date"
                publication_date === nothing ||
                    error("duplicate --publication-date")
                publication_date = value
            elseif argument == "--phase"
                phase === nothing || error("duplicate --phase")
                phase = value
            else
                output_root === nothing ||
                    error("duplicate --output-root")
                output_root = value
            end
            index += 2
        elseif argument in ("--help", "-h")
            return (; help = true)
        else
            error("unknown argument: $argument")
        end
    end
    publication_date === nothing &&
        error("--publication-date is required")
    phase === nothing && error("--phase is required")
    output_root === nothing && error("--output-root is required")
    return (;
        help = false,
        publication_date,
        phase,
        output_root,
        execute_live,
    )
end

function print_plan(plan)
    println("EFFR recurring acquisition plan")
    println("  Dry run: ", plan.dry_run)
    println("  Publication date: ", plan.authorization.publication_date)
    println("  Effective date: ", plan.authorization.effective_date)
    println("  Phase: ", plan.authorization.phase)
    println("  Window start UTC: ", plan.authorization.window_start_utc)
    println("  Window deadline UTC: ", plan.authorization.window_deadline_utc)
    println("  Transaction ID: ", plan.transaction_id)
    println("  Final path: ", plan.final_path)
    println("  Journal path: ", plan.journal_path)
    println("  Predecessor path: ", plan.predecessor_path)
    println("  Request count: ", length(plan.requests))
    for (index, request) in enumerate(plan.requests)
        println("    ", index, ". ", request.object_id, " ", request.requested_url)
    end
    println("  Network requests made: ", plan.network_requests_made)
    println("  Filesystem writes made: ", plan.filesystem_writes_made)
    println(
        "  Operator live authorization: ",
        plan.operator_authorization[
            "operator_network_execution_authorized",
        ],
    )
    return println(
        "  Frozen campaign network gate: ",
        plan.operator_authorization[
            "campaign_network_execution_authorized",
        ],
    )
end

function main(args = ARGS)
    parsed = try
        parse_args(args)
    catch error
        println(stderr, "Argument error: ", sprint(showerror, error))
        usage(stderr)
        return 2
    end
    if parsed.help
        usage()
        return 0
    end
    try
        result = acquire_recurring(
            parsed.publication_date,
            parsed.phase;
            output_root = parsed.output_root,
            execute_live = parsed.execute_live,
        )
        if parsed.execute_live
            println("EFFR recurring acquisition completed")
            println("  Bundle: ", result.bundle_path)
            println(
                "  Transport provenance: ",
                result.manifest["capture"]["transport_provenance"],
            )
            println(
                "  Transport provenance externally authenticated: ",
                result.manifest["capture"][
                    "persisted_transport_provenance_authenticated",
                ],
            )
            println(
                "  Network exchange count externally witnessed: ",
                result.manifest["capture"][
                    "network_exchange_count_externally_witnessed",
                ],
            )
            println(
                "  Operator authorization externally authenticated: ",
                result.manifest["capture"][
                    "operator_authorization_externally_authenticated",
                ],
            )
            println("  Status: ", result.manifest["result"]["status"])
            println(
                "  Manifest SHA-256: ",
                result.manifest["artifact"]["manifest_sha256"],
            )
            println("  Origin admissible: false")
        else
            print_plan(result)
        end
        return 0
    catch error
        println(stderr, "Acquisition error: ", sprint(showerror, error))
        return 1
    end
end

exit(main())
