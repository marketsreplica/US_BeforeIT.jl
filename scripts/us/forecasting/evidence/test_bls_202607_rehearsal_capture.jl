#!/usr/bin/env julia

using Dates
using Downloads
using HTTP
using SHA
using Sockets
using Test
using TOML

include(joinpath(@__DIR__, "USBLS202607RehearsalCapture.jl"))
using .USBLS202607RehearsalCapture

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function api_bytes(; include_july = true)
    july_ces = include_july ?
        """{"year":"2026","period":"M07","periodName":"July","value":"159123","footnotes":[{"code":"P","text":"Preliminary."}]},""" :
        ""
    july_cps = include_july ?
        """{"year":"2026","period":"M07","periodName":"July","value":"4.2","footnotes":[{"code":"P","text":"Preliminary."}]},""" :
        ""
    return Vector{UInt8}(
        codeunits(
            """
            {"status":"REQUEST_SUCCEEDED","responseTime":1,"message":[],"Results":{"series":[{"seriesID":"CES0000000001","data":[$july_ces{"year":"2026","period":"M06","value":"159000","footnotes":[]}]},{"seriesID":"LNS14000000","data":[$july_cps{"year":"2026","period":"M06","value":"4.1","footnotes":[]}] }]}}
            """,
        ),
    )
end

invalid_api_bytes() = Vector{UInt8}(
    codeunits(
        """{"status":"REQUEST_FAILED","message":["Daily threshold exceeded"],"Results":{}}""",
    ),
)

function html_bytes(; valid = true)
    title = valid ?
        "Employment Situation Summary - 2026 M07 Results" :
        "Access Denied"
    body = valid ?
        """
        <p>Transmission of material in this release is embargoed until Friday, August 7, 2026.</p>
        <h1>THE EMPLOYMENT SITUATION &mdash; JULY 2026</h1>
        <p>Total nonfarm</p><p>Unemployment rate</p>
        """ : "<p>Request rejected.</p>"
    return Vector{UInt8}(
        codeunits(
            "<!doctype html><html><head><title>$title</title></head><body>$body</body></html>",
        ),
    )
end

pdf_bytes() =
    Vector{UInt8}(codeunits("%PDF-1.7\nsynthetic fixture\n%%EOF\n"))

function response(
        object_id;
        body,
        status_code = 200,
        started = DateTime(2026, 8, 7, 12, 30, 1),
        headers_at = DateTime(2026, 8, 7, 12, 30, 2),
        completed = DateTime(2026, 8, 7, 12, 30, 3),
        content_type = nothing,
    )
    route = Dict(
        "bls_v2_endpoint_unregistered_response" => (
            url = "https://api.bls.gov/publicAPI/v2/timeseries/data/",
            content_type = "application/json",
        ),
        "employment_situation_release_html" => (
            url = "https://www.bls.gov/news.release/empsit.nr0.htm",
            content_type = "text/html; charset=utf-8",
        ),
        "employment_situation_release_pdf" => (
            url = "https://www.bls.gov/news.release/pdf/empsit.pdf",
            content_type = "application/pdf",
        ),
    )[object_id]
    declared_content_type =
        content_type === nothing ? route.content_type : String(content_type)
    return CapturedResponse(
        object_id = object_id,
        body = body,
        requested_url = route.url,
        status_code = status_code,
        content_type = declared_content_type,
        response_headers = [
            "content-type: $declared_content_type",
            "date: Fri, 07 Aug 2026 12:30:02 GMT",
        ],
        acquisition_started_at_utc = started,
        response_metadata_observed_at_utc = headers_at,
        acquisition_completed_at_utc = completed,
    )
end

function api_response(; include_july = true, kwargs...)
    return response(
        "bls_v2_endpoint_unregistered_response";
        body = api_bytes(; include_july),
        kwargs...,
    )
end

function full_responses(; valid_html = true)
    return [
        api_response(),
        response(
            "employment_situation_release_html";
            body = html_bytes(; valid = valid_html),
            started = DateTime(2026, 8, 7, 12, 30, 3),
            headers_at = DateTime(2026, 8, 7, 12, 30, 4),
            completed = DateTime(2026, 8, 7, 12, 30, 5),
        ),
        response(
            "employment_situation_release_pdf";
            body = pdf_bytes(),
            started = DateTime(2026, 8, 7, 12, 30, 5),
            headers_at = DateTime(2026, 8, 7, 12, 30, 6),
            completed = DateTime(2026, 8, 7, 12, 30, 7),
        ),
    ]
end

function queued_clock(values)
    index = Ref(1)
    return () -> begin
        index[] <= length(values) ||
            error("synthetic clock exhausted")
        value = values[index[]]
        index[] += 1
        return value
    end
end

function all_files(root)
    paths = String[]
    for (directory, _, files) in walkdir(root)
        append!(paths, [joinpath(directory, file) for file in files])
    end
    return paths
end

function root_journal_paths(root)
    return sort!(
        [
            path for path in all_files(root) if
                startswith(basename(path), "journal-content-sha256-") &&
                !occursin("/replica-", relpath(path, root))
        ],
    )
end

function root_news_diagnostic_paths(root)
    return sort!(
        [
            path for path in all_files(root) if
                startswith(
                    basename(path),
                    "diagnostic-content-sha256-",
                ) &&
                !occursin("/replica-", relpath(path, root))
        ],
    )
end

function with_test_http_server(body, handler)
    server = HTTP.serve!(handler, ip"127.0.0.1", 0; verbose = false)
    port = Int(last(Sockets.getsockname(server.listener.server)))
    try
        return body("http://127.0.0.1:$port")
    finally
        close(server)
    end
end

@testset "transaction IDs are collision-resistant and injectable" begin
    deterministic =
        USBLS202607RehearsalCapture._default_transaction_id(
        clock = () -> DateTime(2026, 8, 7, 12, 30),
        nonce_bytes = () -> fill(0xab, 16),
    )
    @test deterministic ==
        "host-20260807t123000-" * repeat("ab", 16)
    @test USBLS202607RehearsalCapture._default_transaction_id() !=
        USBLS202607RehearsalCapture._default_transaction_id()
end

@testset "live response metadata excludes cookies and credentials" begin
    normalized = USBLS202607RehearsalCapture._normalized_headers(
        (
            headers = [
                "Content-Type" => "application/json",
                "Date" => "Fri, 07 Aug 2026 12:30:02 GMT",
                "ETag" => "\"fixture\"",
                "Set-Cookie" => "JSESSIONID=secret",
                "Authorization" => "Bearer secret",
                "Proxy-Authenticate" => "secret",
            ],
        ),
    )
    @test normalized == [
        "content-type: application/json",
        "date: Fri, 07 Aug 2026 12:30:02 GMT",
        "etag: \"fixture\"",
    ]
    @test all(!occursin("secret", header) for header in normalized)
end

@testset "live transport is direct, isolated, bounded, and does not redirect" begin
    redirected_target_hits = Ref(0)
    observed_authorization = Ref("")
    observed_cookie = Ref("")
    handler = request -> begin
        path = HTTP.URI(request.target).path
        if path == "/redirect"
            return HTTP.Response(302, ["Location" => "/redirect-target"], "moved")
        elseif path == "/redirect-target"
            redirected_target_hits[] += 1
            return HTTP.Response(200, "followed")
        elseif path == "/set-cookie"
            return HTTP.Response(
                200,
                ["Set-Cookie" => "ambient-secret=must-not-return"],
                "set",
            )
        elseif path == "/inspect"
            for (name, value) in request.headers
                lowercase(String(name)) == "authorization" &&
                    (observed_authorization[] = String(value))
                lowercase(String(name)) == "cookie" &&
                    (observed_cookie[] = String(value))
            end
            return HTTP.Response(200, "direct")
        elseif path == "/oversize"
            return HTTP.Response(200, repeat("x", 256))
        elseif path == "/slow"
            sleep(0.25)
            return HTTP.Response(200, "late")
        end
        return HTTP.Response(404)
    end
    with_test_http_server(handler) do base_url
        redirect = USBLS202607RehearsalCapture._bounded_request(
            "$base_url/redirect";
            method = "GET",
            headers = Pair{String, String}[],
            body_limit = 128,
        )
        @test redirect.response.status == 302
        @test redirected_target_hits[] == 0

        USBLS202607RehearsalCapture._bounded_request(
            "$base_url/set-cookie";
            method = "GET",
            headers = Pair{String, String}[],
            body_limit = 128,
        )

        mktempdir() do directory
            netrc_path = joinpath(directory, "ambient.netrc")
            open(netrc_path, "w") do io
                write(
                    io,
                    "machine 127.0.0.1 login ambient-user password ambient-secret\n",
                )
            end
            previous_hook = Downloads.EASY_HOOK[]
            Downloads.EASY_HOOK[] = (easy, _) -> begin
                curl = Downloads.Curl
                curl.setopt(
                    easy,
                    curl.CURLOPT_NETRC,
                    curl.CURL_NETRC_REQUIRED,
                )
                curl.setopt(easy, curl.CURLOPT_NETRC_FILE, netrc_path)
                curl.setopt(easy, curl.CURLOPT_COOKIE, "ambient=secret")
                curl.setopt(easy, curl.CURLOPT_PROXY, "http://127.0.0.1:1")
            end
            try
                direct = withenv(
                    "HTTP_PROXY" => "http://127.0.0.1:1",
                    "HTTPS_PROXY" => "http://127.0.0.1:1",
                    "ALL_PROXY" => "http://127.0.0.1:1",
                    "NO_PROXY" => "",
                    "http_proxy" => "http://127.0.0.1:1",
                    "https_proxy" => "http://127.0.0.1:1",
                    "all_proxy" => "http://127.0.0.1:1",
                    "no_proxy" => "",
                ) do
                    USBLS202607RehearsalCapture._bounded_request(
                        "$base_url/inspect";
                        method = "GET",
                        headers = Pair{String, String}[],
                        body_limit = 128,
                    )
                end
                @test direct.body == codeunits("direct")
            finally
                Downloads.EASY_HOOK[] = previous_hook
            end
        end
        @test isempty(observed_authorization[])
        @test isempty(observed_cookie[])

        @test_throws RehearsalCaptureError USBLS202607RehearsalCapture._bounded_request(
            "$base_url/oversize";
            method = "GET",
            headers = Pair{String, String}[],
            body_limit = 32,
        )
        @test_throws RehearsalCaptureError USBLS202607RehearsalCapture._bounded_request(
            "$base_url/slow";
            method = "GET",
            headers = Pair{String, String}[],
            body_limit = 32,
            timeout_seconds = 0.05,
        )
    end
end

@testset "attempt journals are content-addressed, nonadmitting, and independent" begin
    attempts = [
        (
            attempt_number = 1,
            attempted_at_utc = "2026-08-07T12:30:01Z",
            status_code = 200,
            response_sha256 =
                sha256_hex(api_bytes(; include_july = false)),
            outcome = "M07_NOT_AVAILABLE",
            detail = "EXPECTED_SERIES_WITHOUT_COMPLETE_M07",
        ),
    ]
    attempt_bodies = Dict(
        attempts[1].response_sha256 => api_bytes(; include_july = false),
    )
    mktempdir() do directory
        installed = install_rehearsal_attempt_journal(
            directory,
            attempts;
            api_attempt_bodies = attempt_bodies,
            transaction_id = "journal-polling",
            recorded_at = DateTime(2026, 8, 7, 12, 30, 3),
            state = "POLLING",
        )
        @test installed.validation.status ==
            "LOCAL_REHEARSAL_ATTEMPT_JOURNAL_VERIFIED_NONADMITTING"
        @test installed.validation.state == "POLLING"
        @test !installed.validation.terminal
        @test installed.validation.attempt_count == 1
        @test installed.validation.attempt_object_count == 1
        @test isnothing(installed.validation.accepted_attempt_number)
        @test !installed.validation.origin_evidence
        @test !installed.validation.origin_admissible
        @test !installed.validation.ready

        name = basename(installed.journal_path)
        replica =
            joinpath(installed.bundle_path, "replica-b", name)
        rm(replica)
        hardlink(installed.journal_path, replica)
        @test_throws USBLS202607RehearsalCapture.ReceiptVerifier.RehearsalReceiptError validate_rehearsal_attempt_journal_file(
            installed.journal_path,
        )
    end

    mktempdir() do directory
        installed = install_rehearsal_attempt_journal(
            directory,
            attempts;
            api_attempt_bodies = attempt_bodies,
            transaction_id = "journal-symlink",
            recorded_at = DateTime(2026, 8, 7, 12, 30, 3),
            state = "POLLING",
        )
        name = basename(installed.journal_path)
        replica_directory =
            joinpath(installed.bundle_path, "replica-a")
        external = mktempdir()
        cp(
            joinpath(replica_directory, name),
            joinpath(external, name),
        )
        rm(replica_directory; recursive = true)
        symlink(external, replica_directory)
        @test_throws USBLS202607RehearsalCapture.ReceiptVerifier.RehearsalReceiptError validate_rehearsal_attempt_journal_file(
            installed.journal_path,
        )
    end
end

@testset "installer publishes verified nonadmitting API and news bundles" begin
    mktempdir() do directory
        full = install_rehearsal_capture(
            directory,
            full_responses();
            transaction_id = "synthetic-full",
        )
        @test full.installed
        @test isdir(full.bundle_path)
        @test isfile(full.receipt_path)
        @test full.validation.acquisition_mode ==
            "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_PLUS_NEWS_BYTES"
        @test full.validation.source_object_count == 3
        @test full.validation.news_release_bytes_captured
        @test !full.validation.origin_evidence
        @test !full.validation.origin_admissible
        @test !full.validation.ready

        repeated = install_rehearsal_capture(
            directory,
            full_responses();
            transaction_id = "synthetic-full",
        )
        @test !repeated.installed
        @test repeated.bundle_path == full.bundle_path
        @test repeated.validation.content_sha256 ==
            full.validation.content_sha256
    end

    mktempdir() do directory
        fallback = install_rehearsal_capture(
            directory,
            [api_response()];
            transaction_id = "synthetic-api",
        )
        @test fallback.validation.acquisition_mode ==
            "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK"
        @test fallback.validation.source_object_count == 1
        @test !fallback.validation.news_release_bytes_captured
        @test fallback.validation.api_response_captured
        @test !fallback.validation.origin_admissible
    end

    mktempdir() do directory
        accepted = api_response()
        stale_hash = sha256_hex(api_bytes(; include_july = false))
        attempts = [
            (
                attempt_number = 1,
                attempted_at_utc = "2026-08-07T12:30:00Z",
                status_code = 200,
                response_sha256 = stale_hash,
                outcome = "M07_NOT_AVAILABLE",
                detail = "EXPECTED_SERIES_WITHOUT_COMPLETE_M07",
            ),
            (
                attempt_number = 2,
                attempted_at_utc = "2026-08-07T12:30:00Z",
                status_code = 200,
                response_sha256 = stale_hash,
                outcome = "M07_NOT_AVAILABLE",
                detail = "EXPECTED_SERIES_WITHOUT_COMPLETE_M07",
            ),
            (
                attempt_number = 3,
                attempted_at_utc = "2026-08-07T12:30:01Z",
                status_code = 200,
                response_sha256 = sha256_hex(accepted.body),
                outcome = "ACCEPTED_M07",
                detail = "CES_AND_CPS_M07_PRESENT",
            ),
        ]
        repeated_stale = install_rehearsal_capture(
            directory,
            [accepted];
            transaction_id = "repeated-stale",
            api_attempts = attempts,
            api_attempt_bodies = Dict(
                stale_hash => api_bytes(; include_july = false),
            ),
        )
        @test repeated_stale.validation.api_attempt_count == 3
        @test repeated_stale.validation.accepted_api_attempt_number == 3
    end
end

@testset "sub-second timestamps use the serialized receipt span" begin
    mktempdir() do directory
        subsecond = api_response(
            started = DateTime(2026, 8, 7, 12, 30, 0, 900),
            headers_at = DateTime(2026, 8, 7, 12, 30, 0, 950),
            completed = DateTime(2026, 8, 7, 12, 30, 1, 100),
        )
        result = install_rehearsal_capture(
            directory,
            [subsecond];
            transaction_id = "subsecond",
        )
        receipt = TOML.parsefile(result.receipt_path)
        @test receipt["capture"]["observed_span_seconds"] == 1
        @test result.validation.api_attempt_count == 1
    end
end

@testset "installer rejects ambiguous and out-of-window captures" begin
    mktempdir() do directory
        duplicate = [api_response(), api_response()]
        @test_throws RehearsalCaptureError install_rehearsal_capture(
            directory,
            duplicate;
            transaction_id = "duplicate",
        )
    end
    mktempdir() do directory
        late = api_response(
            started = DateTime(2026, 8, 7, 12, 45, 1),
            headers_at = DateTime(2026, 8, 7, 12, 45, 2),
            completed = DateTime(2026, 8, 7, 12, 45, 3),
        )
        @test_throws RehearsalCaptureError install_rehearsal_capture(
            directory,
            [late];
            transaction_id = "late",
        )
    end
end

@testset "live polling waits for M07 and retains stale response evidence" begin
    mktempdir() do directory
        api_count = Ref(0)
        stale = api_response(; include_july = false)
        accepted = api_response(
            started = DateTime(2026, 8, 7, 12, 30, 16),
            headers_at = DateTime(2026, 8, 7, 12, 30, 17),
            completed = DateTime(2026, 8, 7, 12, 30, 18),
        )
        fetch = object_id -> begin
            if object_id == "bls_v2_endpoint_unregistered_response"
                api_count[] += 1
                return api_count[] == 1 ? stale : accepted
            end
            return response(
                object_id;
                body = html_bytes(; valid = false),
                status_code = 403,
                started = DateTime(2026, 8, 7, 12, 30, 19),
                headers_at = DateTime(2026, 8, 7, 12, 30, 20),
                completed = DateTime(2026, 8, 7, 12, 30, 21),
            )
        end
        waited = Int[]
        result = acquire_live_rehearsal(
            directory;
            transaction_id = "delayed-api",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 30, 1),
                    DateTime(2026, 8, 7, 12, 30, 2),
                    DateTime(2026, 8, 7, 12, 30, 16),
                ],
            ),
            fetch,
            wait = seconds -> push!(waited, seconds),
            poll_interval_seconds = 15,
        )
        @test waited == [15]
        @test length(result.api_attempts) == 2
        @test result.api_attempts[1].outcome ==
            "M07_NOT_AVAILABLE"
        @test result.api_attempts[2].outcome == "ACCEPTED_M07"
        @test result.validation.acquisition_mode ==
            "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK"
        receipt = TOML.parsefile(result.receipt_path)
        @test receipt["capture"]["api_attempt_count"] == 2
        @test receipt["capture"]["accepted_api_attempt_number"] == 2
        @test receipt["capture"]["capture_started_at_utc"] ==
            "2026-08-07T12:30:01Z"
        @test receipt["capture"]["observed_span_seconds"] == 17
        @test length(receipt["attempts"]) == 2
        @test receipt["attempts"][1]["attempt_number"] == 1
        @test receipt["attempts"][1]["response_sha256"] ==
            sha256_hex(stale.body)
        @test receipt["attempts"][1]["outcome"] ==
            "M07_NOT_AVAILABLE"
        @test !receipt["attempts"][1]["accepted"]
        @test receipt["attempts"][2]["attempt_number"] == 2
        @test receipt["attempts"][2]["response_sha256"] ==
            sha256_hex(accepted.body)
        @test receipt["attempts"][2]["outcome"] == "ACCEPTED_M07"
        @test receipt["attempts"][2]["accepted"]
        @test result.validation.api_attempt_count == 2
        @test result.validation.attempt_response_object_count == 1
        @test result.validation.accepted_api_attempt_number == 2
        @test length(result.journal_snapshots) == 3
        journal_ids = [
            TOML.parsefile(snapshot.journal_path)["artifact"]["journal_id"]
                for snapshot in result.journal_snapshots
        ]
        @test length(journal_ids) == length(unique(journal_ids))
        @test result.journal_snapshots[end].validation.state ==
            "BUNDLE_INSTALLED"
        @test result.journal_snapshots[end].validation.terminal
        @test result.api_bundle_path == result.bundle_path
        stale_paths = filter(
            path -> occursin(sha256_hex(stale.body), path),
            all_files(result.bundle_path),
        )
        @test length(stale_paths) == 2
        @test all(read(path) == stale.body for path in stale_paths)
        @test result.journal_snapshots[end].validation.attempt_object_count == 2
        @test !result.validation.origin_admissible
    end
end

@testset "invalid HTTP-200 API bytes are distinct from M07 unavailability" begin
    mktempdir() do directory
        api_count = Ref(0)
        fetch = object_id -> begin
            if object_id == "bls_v2_endpoint_unregistered_response"
                api_count[] += 1
                return api_count[] == 1 ?
                    response(
                        object_id;
                        body = invalid_api_bytes(),
                    ) :
                    api_response(
                        started = DateTime(2026, 8, 7, 12, 30, 16),
                        headers_at = DateTime(2026, 8, 7, 12, 30, 17),
                        completed = DateTime(2026, 8, 7, 12, 30, 18),
                    )
            end
            return response(
                object_id;
                body = html_bytes(; valid = false),
                status_code = 403,
                started = DateTime(2026, 8, 7, 12, 30, 19),
                headers_at = DateTime(2026, 8, 7, 12, 30, 20),
                completed = DateTime(2026, 8, 7, 12, 30, 21),
            )
        end
        result = acquire_live_rehearsal(
            directory;
            transaction_id = "invalid-then-accepted",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 30, 1),
                    DateTime(2026, 8, 7, 12, 30, 2),
                    DateTime(2026, 8, 7, 12, 30, 16),
                ],
            ),
            fetch,
            wait = _ -> nothing,
            poll_interval_seconds = 15,
        )
        @test result.api_attempts[1].outcome == "INVALID_API_RESPONSE"
        @test result.api_attempts[1].detail ==
            "CANONICAL_RESPONSE_VALIDATION_FAILED"
        @test result.api_attempts[2].outcome == "ACCEPTED_M07"
        receipt = TOML.parsefile(result.receipt_path)
        @test receipt["attempts"][1]["outcome"] ==
            "INVALID_API_RESPONSE"
        @test result.validation.api_attempt_count == 2
    end
end

@testset "accepted API bytes are installed before slow or failed news routes" begin
    mktempdir() do directory
        news_saw_api_bundle = Ref(false)
        recorded_after_bundle = Ref(false)
        fetch = object_id -> begin
            if object_id == "bls_v2_endpoint_unregistered_response"
                return api_response()
            end
            news_saw_api_bundle[] |= any(
                startswith(basename(path), "receipt-content-sha256-")
                    for path in all_files(directory)
            )
            return response(
                object_id;
                body = html_bytes(; valid = false),
                status_code = 403,
                started = DateTime(2026, 8, 7, 12, 30, 20),
                headers_at = DateTime(2026, 8, 7, 12, 30, 21),
                completed = DateTime(2026, 8, 7, 12, 30, 22),
            )
        end
        result = acquire_live_rehearsal(
            directory;
            transaction_id = "api-before-news",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 30, 1),
                ],
            ),
            fetch,
            wait = _ -> nothing,
            recorded_clock = () -> begin
                recorded_after_bundle[] = any(
                    startswith(basename(path), "receipt-content-sha256-")
                        for path in all_files(directory)
                )
                return DateTime(2026, 8, 7, 12, 30, 10)
            end,
        )
        @test news_saw_api_bundle[]
        @test recorded_after_bundle[]
        @test isdir(result.api_bundle_path)
        terminal = only(
            filter(
                snapshot -> snapshot.validation.terminal,
                result.journal_snapshots,
            ),
        )
        parsed = TOML.parsefile(terminal.journal_path)
        @test parsed["journal"]["recorded_at_utc"] ==
            "2026-08-07T12:30:10Z"
        @test terminal.validation.state == "BUNDLE_INSTALLED"
    end

    mktempdir() do directory
        responses = Dict(
            response.object_id => response for response in full_responses()
        )
        result = acquire_live_rehearsal(
            directory;
            transaction_id = "stage-identity",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 30, 1),
                ],
            ),
            fetch = object_id -> responses[object_id],
            wait = _ -> nothing,
            recorded_clock =
                () -> DateTime(2026, 8, 7, 12, 30, 10),
        )
        checkpoint = TOML.parsefile(result.api_receipt_path)
        completed = TOML.parsefile(result.receipt_path)
        @test checkpoint["capture"]["transaction_id"] ==
            completed["capture"]["transaction_id"] ==
            "stage-identity"
        @test checkpoint["artifact"]["receipt_id"] !=
            completed["artifact"]["receipt_id"]
        @test endswith(
            checkpoint["artifact"]["receipt_id"],
            ".api-only-checkpoint",
        )
        @test endswith(
            completed["artifact"]["receipt_id"],
            ".api-plus-news",
        )
    end
end

@testset "validated news cannot hide full-bundle installation failure" begin
    mktempdir() do directory
        responses = full_responses()
        preexisting = install_rehearsal_capture(
            directory,
            responses;
            transaction_id = "full-install-collision",
        )
        open(preexisting.receipt_path, "a") do io
            write(io, UInt8[0x00])
        end
        response_lookup =
            Dict(response.object_id => response for response in responses)
        @test_throws USBLS202607RehearsalCapture.ReceiptVerifier.RehearsalReceiptError acquire_live_rehearsal(
            directory;
            transaction_id = "full-install-collision",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 30, 1),
                ],
            ),
            fetch = object_id -> response_lookup[object_id],
            wait = _ -> nothing,
            recorded_clock =
                () -> DateTime(2026, 8, 7, 12, 30, 10),
        )
        diagnostics = root_news_diagnostic_paths(directory)
        @test length(diagnostics) == 1
        validation =
            validate_rehearsal_news_diagnostic_file(only(diagnostics))
        @test validation.outcomes ==
            fill("VALIDATED_COMPLETE_NEWS_SET", 2)
        @test !validation.origin_admissible
        api_receipts = filter(
            path -> begin
                startswith(basename(path), "receipt-content-sha256-") ||
                    return false
                !occursin("/replica-", relpath(path, directory)) ||
                    return false
                try
                    TOML.parsefile(path)["capture"]["acquisition_mode"] ==
                        "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK"
                catch
                    false
                end
            end,
            all_files(directory),
        )
        @test length(api_receipts) == 1
    end
end

@testset "unregistered polling cannot exceed the official daily limit" begin
    mktempdir() do directory
        @test_throws RehearsalCaptureError acquire_live_rehearsal(
            directory;
            transaction_id = "over-quota",
            clock = () -> DateTime(2026, 8, 7, 12, 30),
            fetch = _ -> error("must not fetch"),
            wait = _ -> error("must not wait"),
            maximum_api_attempts = 26,
        )
        @test isempty(readdir(directory))
    end
end

@testset "live clock and polling exhaustion fail before installation" begin
    for outside in (
            DateTime(2026, 8, 7, 12, 29, 59),
            DateTime(2026, 8, 7, 12, 45, 1),
        )
        mktempdir() do directory
            @test_throws RehearsalCaptureError acquire_live_rehearsal(
                directory;
                transaction_id = "outside",
                clock = () -> outside,
                fetch = _ -> error("must not fetch"),
                wait = _ -> error("must not wait"),
            )
            journals = root_journal_paths(directory)
            @test length(journals) == 1
            validation =
                validate_rehearsal_attempt_journal_file(only(journals))
            @test validation.state == "FAILED"
            @test validation.failure_reason == "OUTSIDE_EVENT_WINDOW"
            @test validation.attempt_count == 0
        end
    end

    mktempdir() do directory
        stale = api_response(; include_july = false)
        @test_throws RehearsalCaptureError acquire_live_rehearsal(
            directory;
            transaction_id = "deadline",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 44, 59),
                    DateTime(2026, 8, 7, 12, 45, 0),
                ],
            ),
            fetch = _ -> stale,
            wait = _ -> error("must not wait at deadline"),
        )
        journals = root_journal_paths(directory)
        @test length(journals) == 2
        validations =
            validate_rehearsal_attempt_journal_file.(journals)
        terminal = only(filter(result -> result.terminal, validations))
        @test terminal.state == "FAILED"
        @test terminal.failure_reason == "API_DEADLINE_REACHED"
        @test terminal.attempt_count == 1
    end

    mktempdir() do directory
        @test_throws RehearsalCaptureError acquire_live_rehearsal(
            directory;
            transaction_id = "invalid-attempt-clock",
            clock = queued_clock(
                Any[
                    DateTime(2026, 8, 7, 12, 30, 0),
                    "not-a-datetime",
                ],
            ),
            fetch = _ -> error("must not fetch"),
            wait = _ -> error("must not wait"),
        )
        journal = only(root_journal_paths(directory))
        validation = validate_rehearsal_attempt_journal_file(journal)
        @test validation.failure_reason == "CLOCK_FAILURE"
        @test validation.attempt_count == 0
    end

    mktempdir() do directory
        stale = api_response(; include_july = false)
        @test_throws RehearsalCaptureError acquire_live_rehearsal(
            directory;
            transaction_id = "subsecond-deadline",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 44, 59, 500),
                    DateTime(2026, 8, 7, 12, 44, 59, 600),
                ],
            ),
            fetch = _ -> stale,
            wait = _ -> error("must not wait"),
        )
        validations = validate_rehearsal_attempt_journal_file.(
            root_journal_paths(directory),
        )
        terminal = only(filter(result -> result.terminal, validations))
        @test terminal.failure_reason == "API_DEADLINE_REACHED"
        @test terminal.attempt_count == 1
    end
end

@testset "invalid full news bytes downgrade to API-only receipt" begin
    mktempdir() do directory
        fetch = object_id -> begin
            if object_id == "bls_v2_endpoint_unregistered_response"
                return api_response()
            elseif object_id == "employment_situation_release_html"
                return response(
                    object_id;
                    body = html_bytes(; valid = false),
                    started = DateTime(2026, 8, 7, 12, 30, 3),
                    headers_at = DateTime(2026, 8, 7, 12, 30, 4),
                    completed = DateTime(2026, 8, 7, 12, 30, 5),
                )
            end
            return response(
                object_id;
                body = pdf_bytes(),
                started = DateTime(2026, 8, 7, 12, 30, 5),
                headers_at = DateTime(2026, 8, 7, 12, 30, 6),
                completed = DateTime(2026, 8, 7, 12, 30, 7),
            )
        end
        result = acquire_live_rehearsal(
            directory;
            transaction_id = "invalid-news",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 30, 1),
                ],
            ),
            fetch,
            wait = _ -> nothing,
        )
        @test result.validation.acquisition_mode ==
            "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK"
        @test !result.validation.news_release_bytes_captured
        @test result.validation.api_response_captured
        @test !result.validation.origin_admissible
    end
end

@testset "invalid news metadata and timing downgrade to API-only receipt" begin
    for defect in (:content_type, :late)
        mktempdir() do directory
            fetch = object_id -> begin
                if object_id == "bls_v2_endpoint_unregistered_response"
                    return api_response()
                elseif object_id == "employment_situation_release_html"
                    return response(
                        object_id;
                        body = html_bytes(),
                        content_type = defect == :content_type ?
                            "application/json" : nothing,
                        started = DateTime(2026, 8, 7, 12, 30, 3),
                        headers_at = DateTime(2026, 8, 7, 12, 30, 4),
                        completed = DateTime(2026, 8, 7, 12, 30, 5),
                    )
                end
                return response(
                    object_id;
                    body = pdf_bytes(),
                    started = defect == :late ?
                        DateTime(2026, 8, 7, 12, 44, 59) :
                        DateTime(2026, 8, 7, 12, 30, 5),
                    headers_at = defect == :late ?
                        DateTime(2026, 8, 7, 12, 45, 0) :
                        DateTime(2026, 8, 7, 12, 30, 6),
                    completed = defect == :late ?
                        DateTime(2026, 8, 7, 12, 45, 1) :
                        DateTime(2026, 8, 7, 12, 30, 7),
                )
            end
            result = acquire_live_rehearsal(
                directory;
                transaction_id = "invalid-news-$defect",
                clock = queued_clock(
                    [
                        DateTime(2026, 8, 7, 12, 30, 0),
                        DateTime(2026, 8, 7, 12, 30, 1),
                    ],
                ),
                fetch,
                wait = _ -> nothing,
            )
            @test result.validation.acquisition_mode ==
                "BLS_V2_ENDPOINT_UNREGISTERED_SIGNATURE_ONLY_FALLBACK"
            @test result.validation.api_attempt_count == 1
            @test !result.validation.origin_admissible
        end
    end
end

@testset "news downgrade diagnostics retain sanitized evidence" begin
    mktempdir() do directory
        fetch = object_id -> begin
            if object_id == "bls_v2_endpoint_unregistered_response"
                return api_response()
            elseif object_id == "employment_situation_release_pdf"
                error("request failed with credential=must-not-survive")
            end
            base = response(
                object_id;
                body = html_bytes(; valid = false),
                started = DateTime(2026, 8, 7, 12, 30, 3),
                headers_at = DateTime(2026, 8, 7, 12, 30, 4),
                completed = DateTime(2026, 8, 7, 12, 30, 5),
            )
            return CapturedResponse(
                object_id = base.object_id,
                body = base.body,
                requested_url = base.requested_url,
                effective_url = base.effective_url,
                status_code = base.status_code,
                content_type = base.content_type,
                response_headers = vcat(
                    base.response_headers,
                    [
                        "set-cookie: session=must-not-survive",
                        "authorization: Bearer must-not-survive",
                    ],
                ),
                acquisition_started_at_utc =
                    base.acquisition_started_at_utc,
                response_metadata_observed_at_utc =
                    base.response_metadata_observed_at_utc,
                acquisition_completed_at_utc =
                    base.acquisition_completed_at_utc,
            )
        end
        result = acquire_live_rehearsal(
            directory;
            transaction_id = "news-diagnostic",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 30, 1),
                ],
            ),
            fetch,
            wait = _ -> nothing,
        )
        @test isfile(result.news_diagnostic_path)
        @test result.news_diagnostic_validation.status ==
            "LOCAL_REHEARSAL_NEWS_DIAGNOSTIC_VERIFIED_NONADMITTING"
        @test result.news_diagnostic_validation.raw_response_count == 1
        @test !result.news_diagnostic_validation.origin_evidence
        @test !result.news_diagnostic_validation.origin_admissible
        @test !result.news_diagnostic_validation.ready
        @test result.news_attempts[1].outcome ==
            "REJECTED_RELEASE_IDENTITY"
        @test result.news_attempts[2].outcome == "REQUEST_FAILED"
        parsed = TOML.parsefile(result.news_diagnostic_path)
        @test parsed["diagnostic"]["api_checkpoint_binding_status"] ==
            "UNBOUND_CALLER_REPORTED_TRANSACTION_ID_ONLY"
        @test parsed["attempts"][1]["raw_sha256"] ==
            sha256_hex(html_bytes(; valid = false))
        @test parsed["attempts"][2]["raw_sha256"] == "unavailable"
        diagnostic_text = read(result.news_diagnostic_path, String)
        @test !occursin("must-not-survive", diagnostic_text)
        @test !occursin("credential", diagnostic_text)
        raw_paths = [
            joinpath(
                    result.news_diagnostic_bundle_path,
                    parsed["attempts"][1][field],
                ) for field in ("primary_path", "replica_path")
        ]
        @test all(
            read(path) == html_bytes(; valid = false) for path in raw_paths
        )

        rm(raw_paths[2])
        hardlink(raw_paths[1], raw_paths[2])
        @test_throws USBLS202607RehearsalCapture.ReceiptVerifier.RehearsalReceiptError validate_rehearsal_news_diagnostic_file(
            result.news_diagnostic_path,
        )
    end
end

@testset "API metadata failures retain response bytes and continue polling" begin
    mktempdir() do directory
        first = api_response()
        metadata_body = Vector{UInt8}(
            codeunits(replace(String(first.body), "159123" => "159122")),
        )
        missing_headers = CapturedResponse(
            object_id = first.object_id,
            body = metadata_body,
            requested_url = first.requested_url,
            effective_url = first.effective_url,
            status_code = first.status_code,
            content_type = first.content_type,
            response_headers = String[],
            acquisition_started_at_utc = first.acquisition_started_at_utc,
            response_metadata_observed_at_utc =
                first.response_metadata_observed_at_utc,
            acquisition_completed_at_utc =
                first.acquisition_completed_at_utc,
        )
        accepted = api_response(
            started = DateTime(2026, 8, 7, 12, 30, 16),
            headers_at = DateTime(2026, 8, 7, 12, 30, 17),
            completed = DateTime(2026, 8, 7, 12, 30, 18),
        )
        count = Ref(0)
        fetch = object_id -> begin
            object_id == "bls_v2_endpoint_unregistered_response" ||
                error("news unavailable")
            count[] += 1
            return count[] == 1 ? missing_headers : accepted
        end
        result = acquire_live_rehearsal(
            directory;
            transaction_id = "metadata-then-accepted",
            clock = queued_clock(
                [
                    DateTime(2026, 8, 7, 12, 30, 0),
                    DateTime(2026, 8, 7, 12, 30, 1),
                    DateTime(2026, 8, 7, 12, 30, 2),
                    DateTime(2026, 8, 7, 12, 30, 16),
                ],
            ),
            fetch,
            wait = _ -> nothing,
            poll_interval_seconds = 15,
        )
        @test result.api_attempts[1].outcome ==
            "INVALID_API_RESPONSE_METADATA_REPORTED"
        @test result.api_attempts[2].outcome == "ACCEPTED_M07"
        receipt = TOML.parsefile(result.receipt_path)
        @test receipt["capture"]["capture_started_at_utc"] ==
            "2026-08-07T12:30:01Z"
        @test receipt["capture"]["observed_span_seconds"] == 17
        @test length(receipt["attempt_objects"]) == 1
        @test result.validation.attempt_response_object_count == 1
    end
end
