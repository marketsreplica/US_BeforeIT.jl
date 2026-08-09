#!/usr/bin/env julia

using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USBLS202607RehearsalReceipt.jl"))
using .USBLS202607RehearsalReceipt

const HASH_A = repeat("a", 64)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function write_bytes(path, bytes)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, bytes)
    end
    return path
end

function toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    bytes = take!(io)
    isempty(bytes) || bytes[end] == UInt8('\n') ||
        push!(bytes, UInt8('\n'))
    return bytes
end

function source_bytes(; include_july = true)
    html = codeunits(
        """
        <!doctype html>
        <html>
        <head><title>Employment Situation Summary - 2026 M07 Results</title></head>
        <body>
        <p>Transmission of material in this release is embargoed until Friday, August 7, 2026.</p>
        <h1>THE EMPLOYMENT SITUATION &mdash; JULY 2026</h1>
        <table>
        <tr><th>Total nonfarm</th><td>159123</td></tr>
        <tr><th>Unemployment rate</th><td>4.2</td></tr>
        </table>
        </body>
        </html>
        """,
    )
    july_ces = include_july ?
        """{"year":"2026","period":"M07","periodName":"July","value":"159123","footnotes":[{"code":"P","text":"Preliminary."}]},""" :
        ""
    july_cps = include_july ?
        """{"year":"2026","period":"M07","periodName":"July","value":"4.2","footnotes":[{"code":"P","text":"Preliminary."}]},""" :
        ""
    api = codeunits(
        """
        {"status":"REQUEST_SUCCEEDED","responseTime":1,"message":[],"Results":{"series":[{"seriesID":"CES0000000001","data":[$july_ces{"year":"2026","period":"M06","periodName":"June","value":"159000","footnotes":[]}]},{"seriesID":"LNS14000000","data":[$july_cps{"year":"2026","period":"M06","periodName":"June","value":"4.1","footnotes":[]}] }]}}
        """,
    )
    return Dict(
        "employment_situation_release_html" => Vector{UInt8}(html),
        "employment_situation_release_pdf" =>
            Vector{UInt8}(codeunits("%PDF-1.7\nsynthetic fixture\n%%EOF\n")),
        "bls_v2_endpoint_unregistered_response" => Vector{UInt8}(api),
    )
end

function object_fixture(
        object_id,
        bytes,
        started,
        headers,
        completed,
    )
    routes = Dict(
        "employment_situation_release_html" => (
            role = "release_news_file",
            url = "https://www.bls.gov/news.release/empsit.nr0.htm",
            content_type = "text/html; charset=utf-8",
            extension = "html",
            method = "GET",
            request_body = "NOT_APPLICABLE",
        ),
        "employment_situation_release_pdf" => (
            role = "release_news_pdf_opaque_signature_only",
            url =
                "https://www.bls.gov/news.release/pdf/empsit.pdf",
            content_type = "application/pdf",
            extension = "pdf",
            method = "GET",
            request_body = "NOT_APPLICABLE",
        ),
        "bls_v2_endpoint_unregistered_response" => (
            role =
                "v2_endpoint_unregistered_v1_compatible_history_as_known_at_capture",
            url =
                "https://api.bls.gov/publicAPI/v2/timeseries/data/",
            content_type = "application/json",
            extension = "json",
            method = "POST",
            request_body =
            """{"seriesid":["CES0000000001","LNS14000000"],"startyear":"2026","endyear":"2026"}""",
        ),
    )
    route = routes[object_id]
    digest = sha256_hex(bytes)
    name = "raw-sha256-$digest.$(route.extension)"
    return Dict{String, Any}(
        "object_id" => object_id,
        "role" => route.role,
        "requested_url" => route.url,
        "effective_url" => route.url,
        "http_method" => route.method,
        "request_body" => route.request_body,
        "request_body_sha256" =>
            route.method == "POST" ?
            sha256_hex(codeunits(route.request_body)) : "NOT_APPLICABLE",
        "status_code" => 200,
        "content_type" => route.content_type,
        "response_headers" => [
            "content-type: $(route.content_type)",
            "date: Fri, 07 Aug 2026 12:30:02 GMT",
        ],
        "acquisition_started_at_utc" => started,
        "response_metadata_observed_at_utc" => headers,
        "acquisition_completed_at_utc" => completed,
        "raw_sha256" => digest,
        "raw_byte_count" => length(bytes),
        "primary_path" => "replica-a/$name",
        "replica_path" => "replica-b/$name",
    )
end

function receipt_fixture(bytes_by_id; api_only = false)
    api_object = object_fixture(
        "bls_v2_endpoint_unregistered_response",
        bytes_by_id["bls_v2_endpoint_unregistered_response"],
        "2026-08-07T12:30:01Z",
        "2026-08-07T12:30:02Z",
        "2026-08-07T12:30:03Z",
    )
    objects = api_only ? [api_object] : [
            api_object,
            object_fixture(
                "employment_situation_release_html",
                bytes_by_id["employment_situation_release_html"],
                "2026-08-07T12:30:03Z",
                "2026-08-07T12:30:04Z",
                "2026-08-07T12:30:05Z",
            ),
            object_fixture(
                "employment_situation_release_pdf",
                bytes_by_id["employment_situation_release_pdf"],
                "2026-08-07T12:30:05Z",
                "2026-08-07T12:30:06Z",
                "2026-08-07T12:30:07Z",
            ),
        ]
    capture_completed_at =
        api_only ? "2026-08-07T12:30:03Z" : "2026-08-07T12:30:07Z"
    observed_span_seconds = api_only ? 2 : 6
    receipt = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-bls-employment-rehearsal-receipt.v1",
            "receipt_id" =>
                "bls-employment-situation-2026-07-rehearsal.synthetic." *
                (
                api_only ?
                    "api-only-checkpoint" : "api-plus-news"
            ),
            "scope" =>
                "BLS_2026_07_CAPTURE_REHEARSAL_LOCAL_INTEGRITY_ONLY",
            "canonicalization" =>
                "sorted_typed_v1_excluding_artifact_content_sha256",
            "digest_algorithm" => "sha256",
            "content_sha256" => HASH_A,
        ),
        "contract_binding" => Dict{String, Any}(
            "contract_id" =>
                "beforeit-us-prospective-2026q3-acquisition.v2",
            "contract_file_sha256" =>
                EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256,
            "contract_content_sha256" =>
                "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a",
            "event_id" => "bls_employment_situation_2026_07",
        ),
        "event" => Dict{String, Any}(
            "source_id" => "bls_employment_situation",
            "reference_period" => "2026-07",
            "scheduled_timestamp_utc" => "2026-08-07T12:30:00Z",
            "capture_not_before_utc" => "2026-08-07T12:30:00Z",
            "capture_deadline_utc" => "2026-08-07T12:45:00Z",
            "event_purpose" => "capture_rehearsal",
            "required_for_complete_origin" => false,
        ),
        "capture" => Dict{String, Any}(
            "transaction_id" => "synthetic",
            "observer_id" => "beforeit-us-forecasting.synthetic",
            "capture_agent" => "beforeit-bls-employment-rehearsal",
            "capture_agent_version" => "1.0.0",
            "capture_agent_source_sha256" =>
                USBLS202607RehearsalReceipt.capture_agent_source_sha256(),
            "receipt_verifier_source_sha256" =>
                USBLS202607RehearsalReceipt.receipt_verifier_source_sha256(),
            "source_revision" => "UNVERIFIED_LOCAL_WORKTREE",
            "acquisition_mode" => api_only ?
                "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK" :
                "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_PLUS_NEWS_BYTES",
            "capture_started_at_utc" => "2026-08-07T12:30:01Z",
            "capture_completed_at_utc" => capture_completed_at,
            "maximum_span_seconds" => 900,
            "observed_span_seconds" => observed_span_seconds,
            "clock_basis" => "CAPTURE_HOST_UTC_CLOCK_ONLY",
            "api_attempt_count" => 1,
            "accepted_api_attempt_number" => 1,
        ),
        "attempts" => [
            Dict{String, Any}(
                "attempt_number" => 1,
                "object_id" => "bls_v2_endpoint_unregistered_response",
                "attempted_at_utc" => "2026-08-07T12:30:01Z",
                "status_code" => 200,
                "response_sha256" =>
                    sha256_hex(
                    bytes_by_id["bls_v2_endpoint_unregistered_response"],
                ),
                "outcome" => "ACCEPTED_M07",
                "detail" => "CES_AND_CPS_M07_PRESENT",
                "accepted" => true,
            ),
        ],
        "attempt_objects" => Dict{String, Any}[],
        "objects" => objects,
        "fingerprint" => Dict{String, Any}(
            "reference_period" => "2026-07",
            "release_html_marker" => api_only ?
                "NOT_CAPTURED_API_ONLY_FALLBACK" :
                "Employment Situation Summary - 2026 M07 Results",
            "ces_series_id" => "CES0000000001",
            "ces_year" => "2026",
            "ces_period" => "M07",
            "ces_value" => "159123",
            "cps_series_id" => "LNS14000000",
            "cps_year" => "2026",
            "cps_period" => "M07",
            "cps_value" => "4.2",
        ),
        "storage" => Dict{String, Any}(
            "policy" =>
                "TWO_DISTINCT_LOCAL_CONTENT_ADDRESSED_REPLICAS_PLUS_RECEIPT_COPIES",
            "copy_ids" => ["replica-a", "replica-b"],
            "minimum_local_copy_count" => 2,
            "receipt_replica_required" => true,
            "external_durable_storage_attestation_status" =>
                "NOT_VERIFIED",
        ),
        "attestation" => Dict{String, Any}(
            "capture_clock_attestation_status" =>
                "HOST_CLOCK_OBSERVATION_ONLY",
            "source_transport_attestation_status" =>
                "HOST_REPORTED_HTTP_METADATA_ONLY",
            "external_timestamp_attestation_status" => "NOT_VERIFIED",
            "production_prospective_verifier_status" => "NOT_ACTIVATED",
            "cryptographic_signoff_status" => "UNSIGNED",
        ),
        "disposition" => Dict{String, Any}(
            "rehearsal_only" => true,
            "origin_evidence" => false,
            "origin_admissible" => false,
            "ready" => false,
            "inventory_mutation_authorized" => false,
            "accuracy_evaluation_allowed" => false,
        ),
    )
    stamp_receipt_sha256!(receipt)
    return receipt
end

function install_bundle(
        directory;
        mutate_receipt = identity,
        mutate_bytes = identity,
        api_only = false,
        include_july = true,
    )
    bytes_by_id = source_bytes(; include_july)
    mutate_bytes(bytes_by_id)
    receipt = receipt_fixture(bytes_by_id; api_only)
    mutate_receipt(receipt)
    stamp_receipt_sha256!(receipt)
    for object in receipt["objects"]
        bytes = bytes_by_id[object["object_id"]]
        write_bytes(joinpath(directory, object["primary_path"]), bytes)
        write_bytes(joinpath(directory, object["replica_path"]), bytes)
    end
    receipt_bytes = toml_bytes(receipt)
    name =
        "receipt-content-sha256-$(receipt["artifact"]["content_sha256"]).toml"
    path = write_bytes(joinpath(directory, name), receipt_bytes)
    for copy_id in ("replica-a", "replica-b")
        write_bytes(joinpath(directory, copy_id, name), receipt_bytes)
    end
    return (; path, receipt, bytes_by_id, name)
end

function mutate_and_expect_failure(mutation)
    return mktempdir() do directory
        bundle = install_bundle(directory; mutate_receipt = mutation)
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end
end

@testset "BLS July 2026 rehearsal bundle verifies locally and never admits" begin
    @test bytes2hex(
        SHA.sha256(read(DEFAULT_PROSPECTIVE_CONTRACT_PATH)),
    ) == EXPECTED_PROSPECTIVE_CONTRACT_FILE_SHA256

    mktempdir() do directory
        bundle = install_bundle(directory)
        result = validate_rehearsal_receipt_file(bundle.path)
        @test result.status ==
            "LOCAL_REHEARSAL_INTEGRITY_VERIFIED_NONADMITTING"
        @test result.verification_scope ==
            "local_rehearsal_bundle_integrity_only"
        @test result.content_sha256 ==
            bundle.receipt["artifact"]["content_sha256"]
        @test result.acquisition_mode ==
            "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_PLUS_NEWS_BYTES"
        @test result.ces_value == "159123"
        @test result.cps_value == "4.2"
        @test result.source_object_count == 3
        @test result.api_attempt_count == 1
        @test result.accepted_api_attempt_number == 1
        @test result.local_copy_count == 2
        @test result.news_release_bytes_captured
        @test !result.news_release_pdf_semantics_verified
        @test result.api_response_captured
        @test result.api_response_semantics ==
            "v2_endpoint_unregistered_v1_compatible_history_as_known_at_capture"
        @test result.blockers == [
            "API_HOST_NOT_PRODUCTION_CONTRACT_ALLOWLISTED",
            "API_RESPONSE_IS_HISTORY_AS_KNOWN_AT_CAPTURE_ONLY",
            "BLS_DAILY_API_QUOTA_REMAINDER_NOT_ATTESTED",
            "CAPTURE_AGENT_SOURCE_NOT_EXTERNALLY_ATTESTED",
            "DURABLE_STORAGE_NOT_EXTERNALLY_ATTESTED",
            "EXTERNAL_TIMESTAMP_NOT_VERIFIED",
            "PRODUCTION_PROSPECTIVE_VERIFIER_NOT_ACTIVATED",
            "REHEARSAL_EVENT_NOT_REQUIRED_FOR_COMPLETE_ORIGIN",
            "SOURCE_TRANSPORT_NOT_INDEPENDENTLY_ATTESTED",
            "NEWS_RELEASE_PDF_SEMANTICS_NOT_VALIDATED",
        ]
        @test !result.external_timestamp_verified
        @test !result.source_transport_verified
        @test !result.durable_storage_verified
        @test !result.production_verifier_attested
        @test !result.origin_evidence
        @test !result.origin_admissible
        @test !result.ready
        @test !result.inventory_mutation_authorized
        @test !result.accuracy_evaluation_allowed

        parsed = TOML.parsefile(bundle.path)
        @test computed_receipt_sha256(parsed) ==
            parsed["artifact"]["content_sha256"]
        reversed = Dict(reverse(collect(parsed)))
        @test computed_receipt_sha256(reversed) ==
            parsed["artifact"]["content_sha256"]
    end
end

@testset "unregistered v1-compatible request to v2 endpoint is explicit" begin
    mktempdir() do directory
        bundle = install_bundle(directory; api_only = true)
        result = validate_rehearsal_receipt_file(bundle.path)
        @test result.status ==
            "LOCAL_REHEARSAL_INTEGRITY_VERIFIED_NONADMITTING"
        @test result.acquisition_mode ==
            "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK"
        @test result.ces_value == "159123"
        @test result.cps_value == "4.2"
        @test result.source_object_count == 1
        @test result.local_copy_count == 2
        @test !result.news_release_bytes_captured
        @test !result.news_release_pdf_semantics_verified
        @test result.api_response_captured
        @test result.api_response_semantics ==
            "v2_endpoint_unregistered_v1_compatible_history_as_known_at_capture"
        @test result.blockers == [
            "API_HOST_NOT_PRODUCTION_CONTRACT_ALLOWLISTED",
            "API_RESPONSE_IS_HISTORY_AS_KNOWN_AT_CAPTURE_ONLY",
            "BLS_DAILY_API_QUOTA_REMAINDER_NOT_ATTESTED",
            "CAPTURE_AGENT_SOURCE_NOT_EXTERNALLY_ATTESTED",
            "DURABLE_STORAGE_NOT_EXTERNALLY_ATTESTED",
            "EXTERNAL_TIMESTAMP_NOT_VERIFIED",
            "PRODUCTION_PROSPECTIVE_VERIFIER_NOT_ACTIVATED",
            "REHEARSAL_EVENT_NOT_REQUIRED_FOR_COMPLETE_ORIGIN",
            "SOURCE_TRANSPORT_NOT_INDEPENDENTLY_ATTESTED",
            "NEWS_RELEASE_BYTES_NOT_CAPTURED",
        ]
        @test !result.origin_evidence
        @test !result.origin_admissible
        @test !result.ready
        @test !result.inventory_mutation_authorized
        @test !result.accuracy_evaluation_allowed
    end
end

@testset "receipt, contract, event, and fail-closed claims are pinned" begin
    mutate_and_expect_failure() do receipt
        receipt["artifact"]["scope"] = "PRODUCTION_ORIGIN_EVIDENCE"
    end
    mutate_and_expect_failure() do receipt
        receipt["artifact"]["receipt_id"] = "unrelated-receipt"
    end
    mutate_and_expect_failure() do receipt
        receipt["contract_binding"]["contract_file_sha256"] = HASH_A
    end
    mutate_and_expect_failure() do receipt
        receipt["event"]["required_for_complete_origin"] = true
    end
    mutate_and_expect_failure() do receipt
        receipt["event"]["capture_deadline_utc"] =
            "2026-08-07T13:00:00Z"
    end
    mutate_and_expect_failure() do receipt
        receipt["attestation"]["external_timestamp_attestation_status"] =
            "VERIFIED"
    end
    mutate_and_expect_failure() do receipt
        receipt["capture"]["capture_agent"] = "unrelated-agent"
    end
    mutate_and_expect_failure() do receipt
        receipt["capture"]["capture_agent_version"] = "9.9.9"
    end
    mutate_and_expect_failure() do receipt
        receipt["capture"]["capture_agent_source_sha256"] = HASH_A
    end
    mutate_and_expect_failure() do receipt
        receipt["capture"]["receipt_verifier_source_sha256"] = HASH_A
    end
    mutate_and_expect_failure() do receipt
        receipt["capture"]["source_revision"] = "mutable-branch-name"
    end
    mutate_and_expect_failure() do receipt
        receipt["storage"][
            "external_durable_storage_attestation_status",
        ] = "VERIFIED"
    end
    for field in (
            "origin_evidence",
            "origin_admissible",
            "ready",
            "inventory_mutation_authorized",
            "accuracy_evaluation_allowed",
        )
        mutate_and_expect_failure() do receipt
            receipt["disposition"][field] = true
        end
    end
    mutate_and_expect_failure() do receipt
        receipt["unexpected"] = Dict("claim" => true)
    end
    mutate_and_expect_failure() do receipt
        receipt["capture"]["api_attempt_count"] = 2
    end
    mutate_and_expect_failure() do receipt
        receipt["capture"]["api_attempt_count"] = 26
        receipt["attempts"] = [
            merge(
                    deepcopy(receipt["attempts"][1]),
                    Dict("attempt_number" => index),
                ) for index in 1:26
        ]
        for attempt in receipt["attempts"][1:25]
            attempt["outcome"] = "M07_NOT_AVAILABLE"
            attempt["detail"] = "EXPECTED_SERIES_WITHOUT_COMPLETE_M07"
            attempt["accepted"] = false
        end
        receipt["capture"]["accepted_api_attempt_number"] = 26
    end
    mutate_and_expect_failure() do receipt
        receipt["attempts"][1]["response_sha256"] = HASH_A
    end
    mutate_and_expect_failure() do receipt
        receipt["attempts"][1]["outcome"] = "M07_NOT_AVAILABLE"
    end
    mutate_and_expect_failure() do receipt
        accepted = deepcopy(receipt["attempts"][1])
        accepted["attempt_number"] = 2
        stale = deepcopy(receipt["attempts"][1])
        stale["outcome"] = "M07_NOT_AVAILABLE"
        stale["detail"] = "EXPECTED_SERIES_WITHOUT_COMPLETE_M07"
        stale["accepted"] = false
        receipt["attempts"] = [stale, accepted]
        receipt["capture"]["api_attempt_count"] = 2
        receipt["capture"]["accepted_api_attempt_number"] = 2
    end
end

@testset "source routes, timing, fingerprints, and object sets fail closed" begin
    mutate_and_expect_failure() do receipt
        receipt["objects"][1]["effective_url"] =
            "https://example.invalid/empsit"
    end
    mutate_and_expect_failure() do receipt
        receipt["objects"][1]["request_body"] *= " "
    end
    mutate_and_expect_failure() do receipt
        pop!(receipt["objects"][1]["response_headers"])
    end
    mutate_and_expect_failure() do receipt
        push!(
            receipt["objects"][1]["response_headers"],
            "set-cookie: JSESSIONID=must-not-be-retained",
        )
    end
    for (index, invalid_type) in (
            (1, "application/jsonp"),
            (2, "text/htmlx"),
            (3, "application/pdf-malformed"),
        )
        mutate_and_expect_failure() do receipt
            receipt["objects"][index]["content_type"] = invalid_type
            receipt["objects"][index]["response_headers"][1] =
                "content-type: $invalid_type"
        end
    end
    mutate_and_expect_failure() do receipt
        receipt["objects"][1]["response_headers"][2] =
            "date: Fri, 99 Xxx 9999 99:99:99 GMT"
    end
    mutate_and_expect_failure() do receipt
        receipt["objects"][1]["response_headers"][2] =
            "date: Thu, 07 Aug 2026 12:30:02 GMT"
    end
    for noncanonical in (
            "Fri, 7 Aug 2026 12:30:02 GMT",
            "Fri, 07 AUG 2026 12:30:02 GMT",
            "Fri, 07 Aug 2026 2:30:02 GMT",
        )
        mutate_and_expect_failure() do receipt
            receipt["objects"][1]["response_headers"][2] =
                "date: $noncanonical"
        end
    end
    mutate_and_expect_failure() do receipt
        receipt["objects"][2]["content_type"] = "text/html"
    end
    mutate_and_expect_failure() do receipt
        receipt["objects"][3]["status_code"] = 304
    end
    mutate_and_expect_failure() do receipt
        receipt["capture"]["capture_started_at_utc"] =
            "2026-08-07T12:29:59Z"
    end
    mutate_and_expect_failure() do receipt
        receipt["objects"][3]["acquisition_completed_at_utc"] =
            "2026-08-07T12:45:01Z"
        receipt["capture"]["capture_completed_at_utc"] =
            "2026-08-07T12:45:01Z"
        receipt["capture"]["observed_span_seconds"] = 900
    end
    mutate_and_expect_failure() do receipt
        receipt["fingerprint"]["ces_value"] = "159124"
    end
    mutate_and_expect_failure() do receipt
        receipt["fingerprint"]["cps_period"] = "M06"
    end
    mutate_and_expect_failure() do receipt
        receipt["objects"][3]["object_id"] =
            "employment_situation_release_html"
    end
end

@testset "local bytes, content addressing, replicas, and paths fail closed" begin
    mktempdir() do directory
        bundle = install_bundle(directory)
        open(bundle.receipt["objects"][1]["primary_path"] |> path -> joinpath(directory, path), "a") do io
            write(io, UInt8[0x00])
        end
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end

    mktempdir() do directory
        bundle = install_bundle(directory)
        replica = joinpath(directory, "replica-b", bundle.name)
        open(replica, "a") do io
            write(io, UInt8[0x00])
        end
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end

    mutate_and_expect_failure() do receipt
        receipt["objects"][1]["replica_path"] =
            receipt["objects"][1]["primary_path"]
    end
    mutate_and_expect_failure() do receipt
        receipt["objects"][1]["primary_path"] =
            "../escaped/raw.html"
    end

    mktempdir() do directory
        bundle = install_bundle(directory)
        wrong_name = joinpath(directory, "receipt.toml")
        cp(bundle.path, wrong_name)
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            wrong_name,
        )
    end

    mktempdir() do directory
        bundle = install_bundle(directory)
        rm(joinpath(directory, "replica-b", bundle.name))
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end

    mktempdir() do directory
        bundle = install_bundle(directory)
        object = bundle.receipt["objects"][2]
        target = joinpath(directory, object["primary_path"])
        raw = read(target)
        rm(target)
        external = write_bytes(joinpath(mktempdir(), "outside.tsv"), raw)
        symlink(external, target)
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end

    mktempdir() do directory
        bundle = install_bundle(directory)
        object = bundle.receipt["objects"][1]
        primary = joinpath(directory, object["primary_path"])
        replica = joinpath(directory, object["replica_path"])
        rm(replica)
        hardlink(primary, replica)
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end

    mktempdir() do directory
        bundle = install_bundle(directory)
        replica = joinpath(directory, "replica-b", bundle.name)
        rm(replica)
        hardlink(bundle.path, replica)
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end
end

@testset "API-period ambiguity and release identity are rejected" begin
    mktempdir() do directory
        bundle = install_bundle(
            directory;
            mutate_bytes = bytes_by_id -> begin
                api = String(
                    bytes_by_id["bls_v2_endpoint_unregistered_response"],
                )
                duplicate =
                """{"year":"2026","period":"M07","periodName":"July","value":"159124","footnotes":[]},"""
                bytes_by_id["bls_v2_endpoint_unregistered_response"] =
                    Vector{UInt8}(
                    codeunits(
                        replace(
                            api,
                            """"seriesID":"CES0000000001","data":[""" =>
                                """"seriesID":"CES0000000001","data":[$duplicate""",
                        ),
                    ),
                )
            end,
        )
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end

    mktempdir() do directory
        bundle = install_bundle(
            directory;
            api_only = true,
            include_july = false,
        )
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end

    mktempdir() do directory
        bundle = install_bundle(
            directory;
            mutate_bytes = bytes_by_id -> begin
                html = String(
                    bytes_by_id["employment_situation_release_html"],
                )
                bytes_by_id["employment_situation_release_html"] =
                    Vector{UInt8}(
                    codeunits(replace(html, "August 7, 2026" => "August 8, 2026")),
                )
            end,
        )
        @test_throws RehearsalReceiptError validate_rehearsal_receipt_file(
            bundle.path,
        )
    end
end
