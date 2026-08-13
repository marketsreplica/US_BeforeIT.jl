using Dates
using Downloads
using Test

include(joinpath(@__DIR__, "capture_bea_hmi7_advance_pair.jl"))

const LiveFetcher = BEAHMI7AdvanceLiveFetcher
const CaptureBoundary = LiveFetcher.CaptureBoundary

struct InertResponse
    proto::String
    url::String
    status::Int
    headers::Vector{Pair{String, String}}
end

function push_u16!(bytes, value)
    push!(bytes, UInt8(value & 0xff), UInt8((value >> 8) & 0xff))
    return bytes
end

function push_u32!(bytes, value)
    for shift in (0, 8, 16, 24)
        push!(bytes, UInt8((value >> shift) & 0xff))
    end
    return bytes
end

function inert_xlsx(tag::UInt8)
    marker = string(tag)
    entries = [
        "[Content_Types].xml" => repeat("types-$marker", 16),
        "_rels/.rels" => repeat("rels-$marker", 16),
        "xl/workbook.xml" => repeat("workbook-$marker", 16),
        "xl/worksheets/sheet1.xml" => repeat("sheet-$marker", 16),
    ]
    bytes = UInt8[]
    offsets = Int[]
    for (name, payload) in entries
        push!(offsets, length(bytes))
        name_bytes = Vector{UInt8}(codeunits(name))
        payload_bytes = Vector{UInt8}(codeunits(payload))
        append!(bytes, UInt8[0x50, 0x4b, 0x03, 0x04])
        push_u16!(bytes, 20)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u32!(bytes, 0)
        push_u32!(bytes, length(payload_bytes))
        push_u32!(bytes, length(payload_bytes))
        push_u16!(bytes, length(name_bytes))
        push_u16!(bytes, 0)
        append!(bytes, name_bytes)
        append!(bytes, payload_bytes)
    end
    central_offset = length(bytes)
    for ((name, payload), offset) in zip(entries, offsets)
        name_bytes = Vector{UInt8}(codeunits(name))
        payload_bytes = Vector{UInt8}(codeunits(payload))
        append!(bytes, UInt8[0x50, 0x4b, 0x01, 0x02])
        push_u16!(bytes, 20)
        push_u16!(bytes, 20)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u32!(bytes, 0)
        push_u32!(bytes, length(payload_bytes))
        push_u32!(bytes, length(payload_bytes))
        push_u16!(bytes, length(name_bytes))
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u32!(bytes, 0)
        push_u32!(bytes, offset)
        append!(bytes, name_bytes)
    end
    central_size = length(bytes) - central_offset
    append!(bytes, UInt8[0x50, 0x4b, 0x05, 0x06])
    push_u16!(bytes, 0)
    push_u16!(bytes, 0)
    push_u16!(bytes, length(entries))
    push_u16!(bytes, length(entries))
    push_u32!(bytes, central_size)
    push_u32!(bytes, central_offset)
    push_u16!(bytes, 0)
    return bytes
end

function make_writable(path)
    ispath(path) || return
    if isfile(path)
        chmod(path, 0o644)
        return
    end
    for (root, directories, files) in walkdir(path; topdown = false)
        for file in files
            chmod(joinpath(root, file), 0o644)
        end
        for directory in directories
            chmod(joinpath(root, directory), 0o755)
        end
        chmod(root, 0o755)
    end
    return
end

function with_temp_root(function_to_run)
    root = realpath(mktempdir())
    try
        return function_to_run(root)
    finally
        if ispath(root)
            make_writable(root)
            rm(root; recursive = true)
        end
    end
end

function fixed_clock()
    base = DateTime(today()) + Hour(10)
    samples = [
        base + Millisecond(100),
        base + Millisecond(200),
        base + Second(1) + Millisecond(100),
        base + Second(1) + Millisecond(200),
    ]
    index = Ref(0)
    return () -> begin
        index[] += 1
        return samples[index[]]
    end
end

function inert_pair_executor(plan, counter; bodies = nothing)
    payloads = bodies === nothing ?
        [inert_xlsx(0x01), inert_xlsx(0x02)] :
        bodies
    return function (
            url;
            output,
            method,
            headers,
            timeout,
            progress,
            downloader,
            throw,
        )
        counter[] += 1
        index = counter[]
        index <= 2 || error("inert callback exceeded two calls")
        target = plan.workbooks[index]
        @test String(url) == target.url
        @test method == "GET"
        @test headers == collect(target.request_headers)
        @test timeout == LiveFetcher.LIVE_TIMEOUT_SECONDS
        @test downloader === nothing
        @test throw == false
        body = payloads[index]
        progress(length(body), 0, 0, 0)
        write(output, body)
        progress(length(body), length(body), 0, 0)
        response_headers = [
            "Content-Type" => target.media_type,
            "Content-Length" => string(length(body)),
            "X-Inert-Order" => string(index),
        ]
        return InertResponse("https", target.url, 200, response_headers)
    end
end

function capture_error(function_to_run)
    try
        function_to_run()
    catch error
        return sprint(showerror, error)
    end
    return "NO_ERROR"
end

@testset "frozen source identities and exact dry-run plans" begin
    bindings = LiveFetcher._validate_source_bindings()
    @test bindings.capture_source_sha256 == LiveFetcher.CAPTURE_SOURCE_SHA256
    @test bindings.metadata_source_sha256 == LiveFetcher.METADATA_SOURCE_SHA256
    @test bindings.metadata_manifest_file_sha256 ==
        LiveFetcher.METADATA_MANIFEST_FILE_SHA256
    @test bindings.metadata_manifest_content_sha256 ==
        LiveFetcher.METADATA_MANIFEST_CONTENT_SHA256
    @test bindings.project_file_sha256 == LiveFetcher.PROJECT_FILE_SHA256
    @test bindings.julia_manifest_file_sha256 ==
        LiveFetcher.JULIA_MANIFEST_FILE_SHA256

    plans = [dry_run_plan(sequence) for sequence in 1:40]
    @test getproperty.(plans, :sequence) == collect(1:40)
    @test all(plan.request_count == 2 for plan in plans)
    @test all(plan.network_callbacks_invoked == 0 for plan in plans)
    @test all(plan.network_requests_made == 0 for plan in plans)
    @test all(plan.filesystem_writes_made == 0 for plan in plans)
    @test all(
        workbook.request_headers == (
                "Accept" => workbook.media_type,
                "Accept-Encoding" => "identity",
                "User-Agent" => "BeforeIT-US-BEA-HMI7-Advance-Capture/1.0",
            ) for plan in plans for workbook in plan.workbooks
    )
    @test length(Set(workbook.url for plan in plans for workbook in plan.workbooks)) == 80
    @test occursin("/2014/q3/", plans[13].workbooks[1].url)
    @test all(!value for plan in plans for value in values(plan.gates))
    @test_throws LiveFetcher.BEAHMI7AdvanceLiveFetcherError dry_run_plan(true)
    @test_throws CaptureBoundary.BEAHMI7AdvanceCaptureError dry_run_plan(0)
    @test_throws CaptureBoundary.BEAHMI7AdvanceCaptureError dry_run_plan(41)
    @test_throws MethodError dry_run_plan(1.0)

    poison_count = Ref(0)
    previous_hook = Downloads.EASY_HOOK[]
    try
        Downloads.EASY_HOOK[] = (_, _) -> (poison_count[] += 1)
        dry_run_plan(1)
        @test poison_count[] == 0
    finally
        Downloads.EASY_HOOK[] = previous_hook
    end
end

@testset "CLI parsing and dry-run boundary" begin
    parsed = parse_arguments(["--sequence", "25"])
    @test parsed.sequence === 25
    @test !parsed.execute_live
    @test parsed.raw_root === nothing
    @test parse_arguments(["--help"]).help
    @test parse_arguments(["-h"]).help

    bad_arguments = [
        String[],
        ["--sequence", "0"],
        ["--sequence", "41"],
        ["--sequence", "01"],
        ["--sequence", "+1"],
        ["--sequence", "1.0"],
        ["--sequence", "true"],
        ["--sequence"],
        ["--sequence", "1", "--sequence", "2"],
        ["--sequence", "1", "--execute-live", "--execute-live"],
        ["--sequence", "1", "--unknown"],
        ["--sequence", "1", "--help"],
        ["--sequence", "1", "--reviewer", " reviewer "],
        ["--sequence", "1", "--reviewer", "bad\nreviewer"],
        ["--sequence", "1", "--terms-reviewed-local-date", "2026-02-30"],
        ["--sequence", "1", "--execute-live"],
        [
            "--sequence",
            "1",
            "--execute-live",
            "--raw-root",
            "/tmp/example",
        ],
    ]
    for arguments in bad_arguments
        @test_throws Exception parse_arguments(arguments)
    end

    output = IOBuffer()
    errors = IOBuffer()
    @test main(
        ["--sequence", "25"];
        stdout_io = output,
        stderr_io = errors,
    ) == 0
    rendered = String(take!(output))
    @test isempty(String(take!(errors)))
    @test occursin("Sequence: 25", rendered)
    @test occursin("Request count: 2", rendered)
    @test length(findall("Header: Accept-Encoding: identity", rendered)) == 2
    @test occursin("Network callbacks invoked: 0", rendered)
    @test occursin("Filesystem writes made: 0", rendered)

    @test !applicable(main, ["--sequence", "1"], identity)
    with_temp_root() do root
        @test !applicable(execute_live_pair, 25, root, identity)
        @test_throws MethodError execute_live_pair(
            25,
            root;
            terms_reviewed_local_date = today(),
            reviewer = "inert reviewer",
            request_executor = identity,
        )
    end
end

@testset "inspectable direct-only transport controls" begin
    policy = transport_policy()
    @test policy.method == "GET"
    @test policy.protocol == "HTTPS_ONLY"
    @test policy.host == "apps.bea.gov"
    @test !policy.follow_redirects
    @test policy.maximum_redirects == 0
    @test !policy.ambient_proxy_allowed
    @test !policy.netrc_allowed
    @test !policy.cookies_allowed
    @test policy.retry_count == 0
    @test policy.maximum_body_bytes == CaptureBoundary.MAX_WORKBOOK_BYTES
    @test policy.response_header_order_preserved
    @test !policy.response_headers_allowlisted
    @test !policy.transport_provenance_authenticated
    @test LiveFetcher._direct_only_downloader().easy_hook !== nothing

    source = read(joinpath(@__DIR__, "BEAHMI7AdvanceLiveFetcher.jl"), String)
    for token in (
            "CURLOPT_FOLLOWLOCATION, false",
            "CURLOPT_MAXREDIRS, 0",
            "CURLOPT_PROTOCOLS, curl.CURLPROTO_HTTPS",
            "CURLOPT_REDIR_PROTOCOLS, 0",
            "CURLOPT_NETRC, curl.CURL_NETRC_IGNORED",
            "CURLOPT_NETRC_FILE, C_NULL",
            "CURLOPT_COOKIEFILE, C_NULL",
            "CURLOPT_COOKIE, C_NULL",
            "CURLOPT_COOKIEJAR, C_NULL",
            "CURLOPT_PROXY, \"\"",
            "CURLOPT_NOPROXY, \"*\"",
            "CURLOPT_MAXFILESIZE_LARGE",
        )
        @test occursin(token, source)
    end
end

@testset "inert request seam preserves body, headers, URL, and conservative time" begin
    plan = CaptureBoundary.capture_plan(25)
    body = inert_xlsx(0x03)
    target = plan.workbooks[1]
    counter = Ref(0)
    executor = function (
            url;
            output,
            method,
            headers,
            timeout,
            progress,
            downloader,
            throw,
        )
        counter[] += 1
        @test downloader === nothing
        @test throw == false
        progress(length(body), 0, 0, 0)
        write(output, body)
        progress(length(body), length(body), 0, 0)
        return InertResponse(
            "https",
            String(url),
            200,
            [
                "X-First" => "one",
                "Content-Type" => target.media_type,
                "Content-Length" => string(length(body)),
                "X-Last" => "four",
            ],
        )
    end
    times = [
        DateTime(2026, 8, 8, 11, 0, 0, 1),
        DateTime(2026, 8, 8, 11, 0, 0, 9),
    ]
    time_index = Ref(0)
    fetched = LiveFetcher._fetch_target(
        target,
        executor,
        () -> nothing,
        () -> times[(time_index[] += 1)],
    )
    @test counter[] == 1
    @test fetched.raw_bytes == body
    @test fetched.requested_url == target.url
    @test fetched.effective_url == target.url
    @test fetched.request_headers == collect(target.request_headers)
    @test fetched.response_headers == [
        "X-First" => "one",
        "Content-Type" => target.media_type,
        "Content-Length" => string(length(body)),
        "X-Last" => "four",
    ]
    @test fetched.request_started_at_utc == "2026-08-08T11:00:00.001Z"
    @test fetched.response_headers_at_utc == "2026-08-08T11:00:00.009Z"
    @test fetched.response_body_completed_at_utc ==
        "2026-08-08T11:00:00.009Z"
end

@testset "one-pair ceiling and content-addressed duplicate handling" begin
    with_temp_root() do root
        plan = CaptureBoundary.capture_plan(25)
        first_count = Ref(0)
        first = LiveFetcher._execute_pair_impl(
            25,
            root,
            today(),
            "inert test reviewer",
            inert_pair_executor(plan, first_count),
            () -> nothing,
            fixed_clock(),
            LiveFetcher.DEFAULT_SOURCE_PATHS,
        )
        @test first_count[] == 2
        @test first.downloader_invocation_count == 2
        @test first.downloader_invocation_ceiling == 2
        @test first.installed
        @test isdir(first.bundle_path)
        @test first.capture.source_mode_attested == "INJECTED_FETCHER_OUTPUT"
        @test !first.capture.network_transport_verified
        @test !first.transport_provenance_authenticated
        @test !first.reviewer_identity_authenticated
        @test !first.host_clock_authenticated
        @test all(!value for value in values(first.gates))
        @test first.workbooks[1].response_headers[end] ==
            ("X-Inert-Order" => "1")
        @test first.workbooks[2].response_headers[end] ==
            ("X-Inert-Order" => "2")

        second_count = Ref(0)
        second = LiveFetcher._execute_pair_impl(
            25,
            root,
            today(),
            "inert test reviewer",
            inert_pair_executor(plan, second_count),
            () -> nothing,
            fixed_clock(),
            LiveFetcher.DEFAULT_SOURCE_PATHS,
        )
        @test second_count[] == 2
        @test !second.installed
        @test second.bundle_path == first.bundle_path
        @test second.receipt_sha256 == first.receipt_sha256
        @test length(readdir(root)) == 1
    end
end

@testset "size, time, response, and request failures are closed" begin
    plan = CaptureBoundary.capture_plan(25)
    target = plan.workbooks[1]
    body = inert_xlsx(0x04)

    oversized = function (url; output, method, headers, timeout, progress, downloader, throw)
        progress(CaptureBoundary.MAX_WORKBOOK_BYTES + 1, 0, 0, 0)
        return InertResponse("https", String(url), 200, Pair{String, String}[])
    end
    @test_throws LiveFetcher.BEAHMI7AdvanceLiveFetcherError LiveFetcher._fetch_target(
        target,
        oversized,
        () -> nothing,
        () -> DateTime(2026, 8, 8),
    )

    request_failure = function (url; kwargs...)
        error("inert transport failure")
    end
    message = capture_error() do
        LiveFetcher._fetch_target(
            target,
            request_failure,
            () -> nothing,
            () -> DateTime(2026, 8, 8),
        )
    end
    @test occursin("closed no-retry policy", message)
    @test !occursin("inert transport failure", message)

    function response_case(;
            proto = "https",
            url = target.url,
            status = 200,
            response_headers_value = nothing,
        )
        return function (
                requested_url;
                output,
                method,
                headers,
                timeout,
                progress,
                downloader,
                throw,
            )
            write(output, body)
            response_headers = response_headers_value === nothing ?
                Pair{String, String}[] :
                response_headers_value
            return InertResponse(proto, String(url), status, response_headers)
        end
    end

    valid_headers = [
        "Content-Type" => target.media_type,
        "Content-Length" => string(length(body)),
    ]
    for executor in (
            response_case(
                proto = "http",
                response_headers_value = valid_headers,
            ),
            response_case(
                url = target.url * "?redirected=1",
                response_headers_value = valid_headers,
            ),
            response_case(status = 302, response_headers_value = valid_headers),
            response_case(
                response_headers_value = [
                    "Content-Type" => target.media_type,
                    "Content-Type" => "text/plain",
                    "Content-Length" => string(length(body)),
                ],
            ),
            response_case(response_headers_value = Pair{String, String}[]),
        )
        @test_throws Exception LiveFetcher._fetch_target(
            target,
            executor,
            () -> nothing,
            fixed_clock(),
        )
    end

    backwards = let index = Ref(0), samples = [
            DateTime(2026, 8, 8, 1, 0, 1),
            DateTime(2026, 8, 8, 1, 0, 0),
        ]
        () -> samples[(index[] += 1)]
    end
    @test_throws LiveFetcher.BEAHMI7AdvanceLiveFetcherError LiveFetcher._fetch_target(
        target,
        response_case(response_headers_value = valid_headers),
        () -> nothing,
        backwards,
    )
    @test_throws LiveFetcher.BEAHMI7AdvanceLiveFetcherError LiveFetcher._fetch_target(
        target,
        response_case(response_headers_value = valid_headers),
        () -> nothing,
        () -> "not a DateTime",
    )

    @test_throws LiveFetcher.BEAHMI7AdvanceLiveFetcherError LiveFetcher._download_progress(
        1,
        1,
        1,
        0,
    )
    @test_throws LiveFetcher.BEAHMI7AdvanceLiveFetcherError LiveFetcher._download_progress(
        -1,
        0,
        0,
        0,
    )
    @test_throws LiveFetcher.BEAHMI7AdvanceLiveFetcherError LiveFetcher._download_progress(
        1.0,
        0,
        0,
        0,
    )
end

@testset "pre-request terms, root, reviewer, and tamper checks" begin
    plan = CaptureBoundary.capture_plan(25)
    with_temp_root() do root
        for (bad_root, bad_date, bad_reviewer) in (
                (joinpath(root, "missing"), today(), "reviewer"),
                (root * "/.", today(), "reviewer"),
                (root, today() - Day(1), "reviewer"),
                (root, today(), ""),
                (root, today(), " reviewer "),
                (root, today(), "bad\nreviewer"),
            )
            count = Ref(0)
            @test_throws Exception LiveFetcher._execute_pair_impl(
                25,
                bad_root,
                bad_date,
                bad_reviewer,
                inert_pair_executor(plan, count),
                () -> nothing,
                fixed_clock(),
                LiveFetcher.DEFAULT_SOURCE_PATHS,
            )
            @test count[] == 0
        end

        for field in keys(LiveFetcher.DEFAULT_SOURCE_PATHS)
            original = getproperty(LiveFetcher.DEFAULT_SOURCE_PATHS, field)
            source_copy = joinpath(root, "tampered_$(field)")
            cp(original, source_copy)
            open(source_copy, "a") do io
                write(io, "\n# inert tamper\n")
            end
            tampered_paths = merge(
                LiveFetcher.DEFAULT_SOURCE_PATHS,
                NamedTuple{(field,)}((realpath(source_copy),)),
            )
            count = Ref(0)
            @test_throws LiveFetcher.BEAHMI7AdvanceLiveFetcherError LiveFetcher._execute_pair_impl(
                25,
                root,
                today(),
                "reviewer",
                inert_pair_executor(plan, count),
                () -> nothing,
                fixed_clock(),
                tampered_paths,
            )
            @test count[] == 0
        end
    end

    callback_count = Ref(0)
    previous_hook = Downloads.EASY_HOOK[]
    try
        Downloads.EASY_HOOK[] = (_, _) -> (callback_count[] += 1)
        output = IOBuffer()
        errors = IOBuffer()
        with_temp_root() do root
            @test main(
                [
                    "--sequence",
                    "25",
                    "--raw-root",
                    root,
                    "--terms-reviewed-local-date",
                    string(today() - Day(1)),
                    "--reviewer",
                    "reviewer",
                    "--execute-live",
                ];
                stdout_io = output,
                stderr_io = errors,
            ) == 1
        end
        @test callback_count[] == 0
        @test isempty(String(take!(output)))
        @test occursin("must equal the current host-local date", String(take!(errors)))
    finally
        Downloads.EASY_HOOK[] = previous_hook
    end
end
