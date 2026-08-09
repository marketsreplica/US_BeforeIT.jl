#!/usr/bin/env julia

using Dates
using SHA
using TOML

include(joinpath(@__DIR__, "BEANIPADiscovery.jl"))
include(joinpath(@__DIR__, "BEANIPAAcquisition.jl"))
include(joinpath(@__DIR__, "BEANIPAPilotReceipt.jl"))
using .BEANIPAAcquisition
using .BEANIPAPilotReceipt

const REPO_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const DEFAULT_RAW_ROOT = joinpath(REPO_ROOT, "data", "us", "raw")
const BACKFILL_PLAN_PATH =
    normpath(joinpath(@__DIR__, "..", "historical_backfill_plan.toml"))
const CURRENT_INVENTORY_PATH =
    normpath(joinpath(@__DIR__, "..", "current_inventory.toml"))
const FINGERPRINT_SCRIPT =
    joinpath(@__DIR__, "fingerprint_2026q2_pilot.py")
const BEA_TERMS_LOCATOR =
    "https://www.bea.gov/index.php/help/faq/145"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"

function usage(io = stdout)
    return println(
        io,
        """
        Usage:
          julia --startup-file=no --project=scripts/us \\
            scripts/us/forecasting/vintages/bea_nipa/live_acquire_2026q2_pilot.jl \\
            --live --terms-reviewed-on YYYY-MM-DD [--raw-root PATH]

        This opt-in command downloads and content-addresses the two pinned
        2026Q2 advance HMI7 workbooks, parses their exact target content, and
        atomically persists a receipt bundle. It creates only a present-day
        observation. It does not mutate the release inventory, prove historical
        availability, admit an origin, or emit READY.
        """,
    )
end

function parse_arguments(args)
    live = false
    terms_reviewed_on = nothing
    raw_root = DEFAULT_RAW_ROOT
    index = 1
    while index <= length(args)
        argument = args[index]
        if argument == "--live"
            live = true
            index += 1
        elseif argument == "--terms-reviewed-on"
            index < length(args) ||
                error("--terms-reviewed-on requires YYYY-MM-DD")
            terms_reviewed_on = try
                Date(args[index + 1])
            catch
                error("--terms-reviewed-on must use a valid YYYY-MM-DD date")
            end
            index += 2
        elseif argument == "--raw-root"
            index < length(args) ||
                error("--raw-root requires a path")
            raw_root = abspath(args[index + 1])
            index += 2
        elseif argument in ("--help", "-h")
            usage()
            exit(0)
        else
            error("unsupported argument: $argument")
        end
    end
    live ||
        error("network acquisition requires the explicit --live flag")
    terms_reviewed_on === nothing &&
        error("a same-day BEA terms recheck is required")
    utc_date = Date(now(UTC))
    terms_reviewed_on == utc_date ||
        error(
        "BEA terms must be rechecked on the current UTC date " *
            "($utc_date); received $terms_reviewed_on",
    )
    return (; terms_reviewed_on, raw_root)
end

function validate_plan_policy(terms_reviewed_on)
    plan = TOML.parsefile(BACKFILL_PLAN_PATH)
    licensing = plan["licensing"]
    licensing["bea_terms_locator"] == BEA_TERMS_LOCATOR ||
        error("backfill plan BEA terms locator drifted")
    licensing["bea_terms_recheck_before_acquisition"] ||
        error("backfill plan no longer requires a BEA terms recheck")
    licensing["bea_public_domain_status"] ==
        "PUBLIC_DOMAIN_UNLESS_OTHERWISE_STATED" ||
        error("backfill plan BEA reuse status drifted")
    licensing["bea_attribution_policy"] ==
        "SOURCE_ATTRIBUTION_APPRECIATED_AND_REQUIRED_BY_THIS_PLAN" ||
        error("backfill plan BEA attribution policy drifted")

    route = only(
        filter(
            row -> row["route_id"] == "bea_nipa_hmi7",
            plan["source_routes"],
        ),
    )
    route["terms_locator"] == BEA_TERMS_LOCATOR ||
        error("HMI7 route terms locator drifted")
    route["attribution_requirement"] ==
        "PRESERVE_BEA_SOURCE_AND_RELEASE_IDENTIFIERS_ATTRIBUTION_APPRECIATED" ||
        error("HMI7 route attribution requirement drifted")
    occursin(
        string(terms_reviewed_on),
        route["terms_review_status"],
    ) ||
        error(
        "HMI7 route plan review date does not match the asserted recheck",
    )
    return route
end

function timestamp(value)
    return Dates.format(value, RFC3339_SECONDS_FORMAT) * "Z"
end

function build_content_fingerprint(raw_root, acquisition)
    output_directory =
        joinpath(raw_root, "bea_nipa", "hmi7", "content")
    command = `python3 $FINGERPRINT_SCRIPT
        --raw-root $raw_root
        --section-1 $(acquisition.workbook_paths["r2026q2_advance_s1"])
        --section-2 $(acquisition.workbook_paths["r2026q2_advance_s2"])
        --output-dir $output_directory`
    output = read(command, String)
    lines = split(chomp(output), '\n')
    length(lines) == 6 ||
        error("content-fingerprint parser returned an unexpected response")
    fingerprint_path = abspath(lines[1])
    dirname(fingerprint_path) == abspath(output_directory) ||
        error("content-fingerprint parser returned a path outside raw storage")
    isfile(fingerprint_path) ||
        error("content-fingerprint parser did not persist its artifact")
    digest = bytes2hex(SHA.sha256(read(fingerprint_path)))
    lines[2] == "sha256=$digest" ||
        error("content-fingerprint parser digest output does not match bytes")
    lines[3:6] == [
        "targets=5",
        "historical_availability_verified=false",
        "origin_admissible=false",
        "ready=false",
    ] || error("content-fingerprint parser state output drifted")
    return fingerprint_path
end

function main(args = ARGS)
    options = parse_arguments(args)
    route = validate_plan_policy(options.terms_reviewed_on)
    inventory_before = read(CURRENT_INVENTORY_PATH)
    started_at_utc = now(UTC)
    acquisition = acquire_pilot(options.raw_root)
    fingerprint_path =
        build_content_fingerprint(options.raw_root, acquisition)
    receipt = install_pilot_receipt(
        options.raw_root,
        acquisition;
        content_fingerprint_path = fingerprint_path,
    )
    completed_at_utc = now(UTC)
    read(CURRENT_INVENTORY_PATH) == inventory_before ||
        error("live pilot mutated the source-release inventory")

    println("BEA HMI7 present-day exact-byte pilot captured")
    println("  source: U.S. Bureau of Economic Analysis")
    println("  terms: ", BEA_TERMS_LOCATOR)
    println("  terms reviewed on: ", options.terms_reviewed_on)
    println("  route status before acquisition: ", route["route_status"])
    println("  started at UTC: ", timestamp(started_at_utc))
    println("  completed at UTC: ", timestamp(completed_at_utc))
    println("  release ID: ", acquisition.release_id)
    println("  mapping profile: ", acquisition.mapping_profile_id)
    println("  raw bundle SHA-256: ", acquisition.bundle_sha256)
    println("  raw bundle path: ", acquisition.bundle_path)
    println("  content fingerprint path: ", fingerprint_path)
    println(
        "  content fingerprint SHA-256: ",
        receipt.content_fingerprint_file_sha256,
    )
    println(
        "  receipt content SHA-256: ",
        receipt.receipt_content_sha256,
    )
    println("  receipt file SHA-256: ", receipt.receipt_file_sha256)
    println("  receipt path: ", receipt.receipt_path)
    for (expectation, fetched) in
        zip(PILOT_EXPECTATIONS, acquisition.fetched_workbooks)
        println("  ", expectation.workbook_id)
        println("    requested URL: ", fetched.requested_locator)
        println("    effective URL: ", fetched.effective_locator)
        println("    HTTP status: ", fetched.http_status)
        println("    response Date: ", fetched.response_date)
        println("    Last-Modified: ", fetched.last_modified)
        println("    ETag: ", fetched.etag)
        println("    bytes: ", length(fetched.raw_bytes))
        println("    SHA-256: ", expectation.expected_sha256)
        println(
            "    path: ",
            acquisition.workbook_paths[expectation.workbook_id],
        )
    end
    println("  historical availability verified: false")
    println("  origin admissible: false")
    println("  ready: false")
    println("  inventory mutated: false")
    return (; acquisition, fingerprint_path, receipt)
end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        main()
    catch error
        usage(stderr)
        rethrow(error)
    end
end
