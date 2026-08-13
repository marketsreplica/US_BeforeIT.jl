#!/usr/bin/env julia

using Dates

include(joinpath(@__DIR__, "BEAHMI7AdvanceLiveFetcher.jl"))
using .BEAHMI7AdvanceLiveFetcher

function usage(io::IO = stdout)
    return println(
        io,
        """
        Usage:
          capture_bea_hmi7_advance_pair.jl --sequence 1..40 [LIVE OPTIONS]

        Live options (all required with --execute-live):
          --raw-root /absolute/canonical/existing/directory
          --terms-reviewed-local-date YYYY-MM-DD
          --reviewer NONEMPTY_TEXT
          --execute-live

        Without --execute-live, this command verifies the frozen source pins
        and prints the exact release, two direct URLs, and ordered request
        headers. The default dry run makes no network call and writes no file.

        --execute-live authorizes exactly one Section 1/Section 2 pair through
        the built-in direct Downloads transport. It does not authorize a loop,
        retry, scheduler, source-inventory mutation, origin admission, empirical
        forecasting, scoring, promotion, or production use. Transport labels,
        reviewer identity, and the host-local/UTC clocks remain unauthenticated
        local-process assertions.
        """,
    )
end

function _one_value!(values, key, arguments, index)
    haskey(values, key) && error("duplicate $key")
    index < length(arguments) || error("$key requires one value")
    value = arguments[index + 1]
    startswith(value, "--") && error("$key requires one value")
    isempty(value) && error("$key requires a nonempty value")
    values[key] = value
    return index + 2
end

function _canonical_sequence(value)
    occursin(r"^[1-9][0-9]*$", value) ||
        error("--sequence must be a canonical integer in 1..40")
    sequence = tryparse(Int, value)
    sequence === nothing && error("--sequence does not fit in an Int")
    1 <= sequence <= 40 || error("--sequence must be in 1..40")
    return sequence
end

function _canonical_review_date(value)
    occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value) ||
        error("--terms-reviewed-local-date must use YYYY-MM-DD")
    parsed = tryparse(Date, value)
    parsed === nothing && error("--terms-reviewed-local-date is invalid")
    string(parsed) == value ||
        error("--terms-reviewed-local-date must be canonical")
    return parsed
end

function parse_arguments(arguments)
    values = Dict{String, String}()
    execute_live = false
    help = false
    index = 1
    while index <= length(arguments)
        argument = arguments[index]
        if argument == "--execute-live"
            execute_live && error("duplicate --execute-live")
            execute_live = true
            index += 1
        elseif argument in (
                "--sequence",
                "--raw-root",
                "--terms-reviewed-local-date",
                "--reviewer",
            )
            index = _one_value!(values, argument, arguments, index)
        elseif argument in ("--help", "-h")
            help && error("duplicate help flag")
            help = true
            index += 1
        else
            error("unknown argument: $argument")
        end
    end
    if help
        length(arguments) == 1 || error("help must be requested alone")
        return (; help = true)
    end
    haskey(values, "--sequence") || error("--sequence is required")
    sequence = _canonical_sequence(values["--sequence"])
    review_date = haskey(values, "--terms-reviewed-local-date") ?
        _canonical_review_date(values["--terms-reviewed-local-date"]) :
        nothing
    reviewer = get(values, "--reviewer", nothing)
    if reviewer !== nothing
        reviewer == strip(reviewer) ||
            error("--reviewer must not have surrounding whitespace")
        any(character -> Int(character) < 0x20 || Int(character) == 0x7f, reviewer) &&
            error("--reviewer contains a forbidden control character")
    end
    raw_root = get(values, "--raw-root", nothing)
    if execute_live
        raw_root === nothing && error("--raw-root is required with --execute-live")
        review_date === nothing &&
            error("--terms-reviewed-local-date is required with --execute-live")
        reviewer === nothing &&
            error("--reviewer is required with --execute-live")
    end
    return (;
        help = false,
        sequence,
        raw_root,
        terms_reviewed_local_date = review_date,
        reviewer,
        execute_live,
    )
end

function print_plan(io, plan)
    println(io, "BEA HMI7 one-release-pair dry run")
    println(io, "  Dry run: true")
    println(io, "  Sequence: ", plan.sequence)
    println(io, "  Reference period: ", plan.release.reference_period)
    println(io, "  Estimate family: ", plan.release.estimate_family)
    println(io, "  Release number: ", plan.release.bea_release_number)
    println(io, "  Event timestamp UTC: ", plan.release.event_timestamp_utc)
    println(io, "  Request count: ", plan.request_count)
    for (index, workbook) in enumerate(plan.workbooks)
        println(io, "  Request ", index, " section ", workbook.section_id)
        println(io, "    URL: ", workbook.url)
        println(io, "    Method: GET")
        for header in workbook.request_headers
            println(io, "    Header: ", first(header), ": ", last(header))
        end
    end
    println(io, "  Timeout seconds: ", plan.transport.timeout_seconds)
    println(io, "  Maximum redirects: ", plan.transport.maximum_redirects)
    println(io, "  Retry count: ", plan.transport.retry_count)
    println(io, "  Network callbacks invoked: 0")
    println(io, "  Network requests made: 0")
    println(io, "  Filesystem writes made: 0")
    println(io, "  Strict origin admissible: false")
    return println(io, "  Ready: false")
end

function print_result(io, result)
    println(io, "BEA HMI7 one-release-pair capture completed")
    println(io, "  Bundle: ", result.bundle_path)
    println(io, "  Newly installed: ", result.installed)
    println(io, "  Release sequence: ", result.release.sequence)
    println(io, "  Reference period: ", result.release.reference_period)
    println(io, "  Downloader invocations: ", result.downloader_invocation_count)
    println(io, "  Receipt SHA-256: ", result.receipt_sha256)
    println(io, "  Receipt file SHA-256: ", result.receipt_file_sha256)
    println(io, "  Pair SHA-256: ", result.pair_sha256)
    println(io, "  Transport provenance authenticated: false")
    println(io, "  Reviewer identity authenticated: false")
    println(io, "  Host clock authenticated: false")
    println(io, "  Strict origin admissible: false")
    return println(io, "  Ready: false")
end

function main(arguments = ARGS; stdout_io::IO = stdout, stderr_io::IO = stderr)
    options = try
        parse_arguments(arguments)
    catch error
        println(stderr_io, "Argument error: ", sprint(showerror, error))
        usage(stderr_io)
        return 2
    end
    if options.help
        usage(stdout_io)
        return 0
    end
    try
        if options.execute_live
            result = execute_live_pair(
                options.sequence,
                options.raw_root;
                terms_reviewed_local_date =
                    options.terms_reviewed_local_date,
                reviewer = options.reviewer,
            )
            print_result(stdout_io, result)
        else
            print_plan(stdout_io, dry_run_plan(options.sequence))
        end
        return 0
    catch error
        println(stderr_io, "Capture refused: ", sprint(showerror, error))
        return 1
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
