#!/usr/bin/env julia

include(joinpath(@__DIR__, "USBLS202607RehearsalCapture.jl"))
using .USBLS202607RehearsalCapture

function usage()
    println(
        stderr,
        "usage: capture_bls_202607_rehearsal.jl OUTPUT_DIRECTORY",
    )
    return 2
end

length(ARGS) == 1 || exit(usage())

transaction_id = get(ENV, "BLS_REHEARSAL_TRANSACTION_ID", "")
result = if isempty(transaction_id)
    acquire_live_rehearsal(only(ARGS))
else
    acquire_live_rehearsal(only(ARGS); transaction_id)
end
println("BLS rehearsal bundle: ", result.bundle_path)
println("Receipt: ", result.receipt_path)
println("Immediate API checkpoint: ", result.api_bundle_path)
println("Immediate API receipt: ", result.api_receipt_path)
println("News diagnostic: ", result.news_diagnostic_path)
println("Mode: ", result.validation.acquisition_mode)
println("Status: ", result.validation.status)
println("Origin admissible: ", result.validation.origin_admissible)
for attempt in result.api_attempts
    println(
        "API attempt ",
        attempt.attempt_number,
        " ",
        attempt.attempted_at_utc,
        ": ",
        attempt.status_code,
        " ",
        attempt.outcome,
        " ",
        attempt.response_sha256,
    )
end
for attempt in result.news_attempts
    println(
        "News attempt ",
        attempt.object_id,
        ": ",
        attempt.status_code,
        " ",
        attempt.outcome,
        " ",
        attempt.detail,
        " ",
        attempt.response_sha256,
    )
end
for snapshot in result.journal_snapshots
    println(
        "API journal ",
        snapshot.validation.state,
        ": ",
        snapshot.journal_path,
    )
end
