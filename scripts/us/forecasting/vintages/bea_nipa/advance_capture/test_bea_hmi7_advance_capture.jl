using Dates
using Test
using TOML

include(joinpath(@__DIR__, "BEAHMI7AdvanceCapture.jl"))
using .BEAHMI7AdvanceCapture

function set_u32!(bytes, position, value)
    for (offset, shift) in enumerate((0, 8, 16, 24))
        bytes[position + offset - 1] = UInt8((value >> shift) & 0xff)
    end
    return bytes
end

function synthetic_xls(tag::UInt8)
    bytes = zeros(UInt8, 1_536)
    bytes[1:8] =
        UInt8[0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]
    bytes[27:28] = UInt8[0x03, 0x00]
    bytes[29:30] = UInt8[0xfe, 0xff]
    bytes[31:32] = UInt8[0x09, 0x00]
    bytes[33:34] = UInt8[0x06, 0x00]
    set_u32!(bytes, 45, 1)
    set_u32!(bytes, 49, 0)
    set_u32!(bytes, 57, 4_096)
    set_u32!(bytes, 61, 0xfffffffe)
    set_u32!(bytes, 65, 0)
    set_u32!(bytes, 69, 0xfffffffe)
    set_u32!(bytes, 73, 0)
    bytes[77:512] .= 0xff
    set_u32!(bytes, 77, 1)
    bytes[600] = tag
    return bytes
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

function synthetic_xlsx(tag::UInt8; names = nothing)
    marker = string(tag)
    entries = if names === nothing
        [
            "[Content_Types].xml" => repeat("types-$marker", 16),
            "_rels/.rels" => repeat("rels-$marker", 16),
            "xl/workbook.xml" => repeat("workbook-$marker", 16),
            "xl/worksheets/sheet1.xml" => repeat("sheet-$marker", 16),
        ]
    else
        [
            String(name) => repeat("$marker-$index", 16) for
                (index, name) in enumerate(names)
        ]
    end
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

function response_for(
        target,
        index;
        raw_bytes = target.extension == "xls" ?
            synthetic_xls(UInt8(index)) :
            synthetic_xlsx(UInt8(index)),
        status = 200,
        request_headers = collect(target.request_headers),
        response_headers = [
            "Content-Type" => target.media_type,
            "Content-Length" => string(length(raw_bytes)),
            "X-Synthetic-Sequence" => string(index),
        ],
        headers_complete = true,
        requested_url = target.url,
        effective_url = target.url,
        redirect_chain = Tuple[],
        started = "2026-08-07T10:00:00.000Z",
        headers_at = "2026-08-07T10:00:00.100Z",
        completed = "2026-08-07T10:00:00.200Z",
    )
    return FetchResponse(
        raw_bytes,
        status,
        request_headers,
        response_headers,
        headers_complete,
        requested_url,
        effective_url,
        redirect_chain,
        started,
        headers_at,
        completed,
    )
end

responses_for(plan) = FetchResponse[
    response_for(target, index) for
        (index, target) in enumerate(plan.workbooks)
]

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

function with_capture_root(function_to_run)
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

function error_message(function_to_run)
    try
        function_to_run()
    catch error
        return sprint(showerror, error)
    end
    return "NO_ERROR"
end

function write_canonical_toml(path, document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    bytes = take!(io)
    bytes[end] == UInt8('\n') || push!(bytes, UInt8('\n'))
    open(path, "w") do stream
        write(stream, bytes)
    end
    return bytes
end

@testset "sealed metadata-driven capture plans" begin
    plans = [capture_plan(sequence) for sequence in 1:40]
    @test getproperty.(getproperty.(plans, :release), :sequence) ==
        collect(1:40)
    @test all(length(plan.workbooks) == 2 for plan in plans)
    @test all(
        startswith(
                workbook.url,
                "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/",
            ) for plan in plans for workbook in plan.workbooks
    )
    @test all(
        !occursin('\\', workbook.url) for
            plan in plans for workbook in plan.workbooks
    )
    @test plans[13].release.reference_period == "2014Q3"
    @test occursin("/2014/q3/", plans[13].workbooks[1].url)
    @test !occursin("/2014/Q3/", plans[13].workbooks[1].url)
    @test all(
        workbook.extension == "xls" for
            plan in plans[1:24] for workbook in plan.workbooks
    )
    @test all(
        workbook.extension == "xlsx" for
            plan in plans[25:40] for workbook in plan.workbooks
    )
    @test length(
        Set(
            workbook.url for plan in plans for workbook in plan.workbooks
        ),
    ) == 80
    @test plans[1].workbooks[1].request_headers[2] ==
        ("Accept-Encoding" => "identity")
    @test_throws BEAHMI7AdvanceCaptureError capture_plan(0)
    @test_throws BEAHMI7AdvanceCaptureError capture_plan(41)
    @test_throws BEAHMI7AdvanceCaptureError capture_plan(true)
    malicious_release = (;
        archive_path =
            "/Inetpub/wwwroot/website/website/HistData/Files/" *
            "Releases/GDP_and_PI/2014/../q3/Advance_October-30-2014",
    )
    @test_throws BEAHMI7AdvanceCaptureError derive_workbook_url(
        malicious_release,
        "Section1all_xls.xls",
    )
end

@testset "local-import bundles are self-hashed and immutable" begin
    with_capture_root() do root
        plan = capture_plan(1)
        responses = responses_for(plan)
        captured = import_present_day_pair(
            1,
            root,
            responses;
            observed_local_date = Date(2026, 8, 7),
            importer = "synthetic fixture suite",
        )
        @test captured.installed
        @test isdir(captured.bundle_path)
        @test occursin(captured.receipt_sha256, basename(captured.bundle_path))
        @test captured.capture.source_mode_attested == "LOCAL_IMPORT"
        @test captured.capture.attestation_authentication ==
            "UNAUTHENTICATED_LOCAL_PROCESS_ASSERTION"
        @test !captured.capture.network_transport_verified
        @test captured.capture.present_day_retrieval_only
        @test captured.release.reference_period == "2011Q3"
        @test captured.workbooks isa Tuple
        @test captured.workbooks[1].request_headers isa Tuple
        @test captured.workbooks[1].response_headers ==
            (
            "Content-Type" => XLS_MEDIA_TYPE,
            "Content-Length" => "1536",
            "X-Synthetic-Sequence" => "1",
        )
        @test all(!value for value in values(captured.gates))
        @test (uperm(captured.bundle_path) & 0x02) == 0
        @test (uperm(captured.receipt_path) & 0x02) == 0
        @test all(
            (uperm(workbook.object_path) & 0x02) == 0 for
                workbook in captured.workbooks
        )

        document = TOML.parsefile(captured.receipt_path)
        @test receipt_sha256(document) == captured.receipt_sha256
        @test receipt_file_sha256(document) ==
            captured.receipt_file_sha256
        @test document["capture"]["terms_review_attested"] == false
        @test document["capture"]["terms_review_attested_local_date"] ==
            "NOT_APPLICABLE_NONLIVE_IMPORT"
        @test !document["capture"]["network_transport_verified"]
        @test document["release"]["snapshot_boundary"] ==
            "PRESENT_DAY_HMI7_ARCHIVE_RETRIEVAL_NOT_HISTORICAL_FIRST_STATE"
        @test document["limits"]["max_total_uncompressed_bytes"] ==
            250_000_000

        repeated = import_present_day_pair(
            1,
            root,
            responses;
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        @test !repeated.installed
        @test repeated.bundle_path == captured.bundle_path
        @test repeated.receipt_sha256 == captured.receipt_sha256
        @test length(readdir(root)) == 1
    end

    with_capture_root() do root
        plan = capture_plan(25)
        captured = import_present_day_pair(
            25,
            root,
            responses_for(plan);
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        @test captured.release.reference_period == "2017Q3"
        @test all(
            workbook.extension == "xlsx" for workbook in captured.workbooks
        )
        @test all(
            occursin("/2017/Q3/", workbook.url) for
                workbook in captured.workbooks
        )
        @test all(
            length(read(workbook.object_path)) ==
                length(synthetic_xlsx(0x01)) for
                workbook in captured.workbooks
        )
        revalidated = validate_capture_bundle(captured.bundle_path)
        @test revalidated == Base.structdiff(captured, NamedTuple{(:installed,)})
    end
end

@testset "response and schema limits reject dubious material" begin
    plan = capture_plan(1)
    base = responses_for(plan)
    @test_throws BEAHMI7AdvanceCaptureError response_for(
        plan.workbooks[1],
        1;
        status = 200.0,
    )
    @test_throws BEAHMI7AdvanceCaptureError response_for(
        plan.workbooks[1],
        1;
        headers_complete = 1,
    )

    cases = [
        (
            "http status",
            response_for(plan.workbooks[1], 1; status = 404),
            "http_status",
        ),
        (
            "incomplete headers",
            response_for(
                plan.workbooks[1],
                1;
                headers_complete = false,
            ),
            "response_headers_complete",
        ),
        (
            "request header drift",
            response_for(
                plan.workbooks[1],
                1;
                request_headers = ["Accept" => "*/*"],
            ),
            "request_headers",
        ),
        (
            "media type",
            response_for(
                plan.workbooks[1],
                1;
                response_headers = [
                    "Content-Type" => "text/html",
                    "Content-Length" => "1536",
                ],
            ),
            "Content-Type",
        ),
        (
            "content length",
            response_for(
                plan.workbooks[1],
                1;
                response_headers = [
                    "Content-Type" => XLS_MEDIA_TYPE,
                    "Content-Length" => "1535",
                ],
            ),
            "Content-Length",
        ),
        (
            "encoded body",
            response_for(
                plan.workbooks[1],
                1;
                response_headers = [
                    "Content-Type" => XLS_MEDIA_TYPE,
                    "Content-Length" => "1536",
                    "Content-Encoding" => "gzip",
                ],
            ),
            "Content-Encoding",
        ),
        (
            "header control character",
            response_for(
                plan.workbooks[1],
                1;
                response_headers = [
                    "Content-Type" => XLS_MEDIA_TYPE,
                    "Content-Length" => "1536",
                    "X-Dubious" => "bad\u0001value",
                ],
            ),
            "forbidden control",
        ),
        (
            "redirect",
            response_for(
                plan.workbooks[1],
                1;
                redirect_chain = [
                    (
                        302,
                        plan.workbooks[1].url,
                        plan.workbooks[1].url * "?copy=1",
                    ),
                ],
            ),
            "redirect",
        ),
        (
            "effective URL",
            response_for(
                plan.workbooks[1],
                1;
                effective_url = plan.workbooks[1].url * "?copy=1",
            ),
            "effective_url",
        ),
        (
            "short body",
            response_for(
                plan.workbooks[1],
                1;
                raw_bytes = zeros(UInt8, 511),
                response_headers = [
                    "Content-Type" => XLS_MEDIA_TYPE,
                    "Content-Length" => "511",
                ],
            ),
            "raw_bytes",
        ),
        (
            "bad OLE byte order",
            response_for(
                plan.workbooks[1],
                1;
                raw_bytes = begin
                    bytes = synthetic_xls(0x01)
                    bytes[29] = 0x00
                    bytes
                end,
            ),
            "little-endian",
        ),
        (
            "unordered timestamps",
            response_for(
                plan.workbooks[1],
                1;
                headers_at = "2026-08-07T09:59:59.999Z",
            ),
            "timestamps",
        ),
    ]

    for (label, bad_first, expected_message) in cases
        with_capture_root() do root
            message = error_message() do
                import_present_day_pair(
                    1,
                    root,
                    [bad_first, base[2]];
                    observed_local_date = "2026-08-07",
                    importer = "synthetic fixture suite",
                )
            end
            @test occursin(expected_message, message)
            @test isempty(readdir(root))
        end
    end

    with_capture_root() do root
        fake_ole = zeros(UInt8, 640)
        fake_ole[1:8] =
            UInt8[0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]
        fake_ole[27:28] = UInt8[0x03, 0x00]
        fake_ole[29:30] = UInt8[0xfe, 0xff]
        fake_ole[31:32] = UInt8[0x09, 0x00]
        fake_ole[33:34] = UInt8[0x06, 0x00]
        bad = response_for(
            plan.workbooks[1],
            1;
            raw_bytes = fake_ole,
        )
        @test occursin(
            "aligned",
            error_message() do
                import_present_day_pair(
                    1,
                    root,
                    [bad, base[2]];
                    observed_local_date = "2026-08-07",
                    importer = "synthetic fixture suite",
                )
            end,
        )
    end

    xlsx_plan = capture_plan(25)
    with_capture_root() do root
        bad_bytes = zeros(UInt8, 800)
        bad_bytes[1:4] = UInt8[0x50, 0x4b, 0x03, 0x04]
        for (position, name) in (
                50 => "[Content_Types].xml",
                100 => "_rels/.rels",
                150 => "xl/workbook.xml",
            )
            name_bytes = Vector{UInt8}(codeunits(name))
            bad_bytes[position:(position + length(name_bytes) - 1)] =
                name_bytes
        end
        bad = response_for(
            xlsx_plan.workbooks[1],
            1;
            raw_bytes = bad_bytes,
        )
        @test occursin(
            "terminal ZIP EOCD",
            error_message() do
                import_present_day_pair(
                    25,
                    root,
                    [bad, response_for(xlsx_plan.workbooks[2], 2)];
                    observed_local_date = "2026-08-07",
                    importer = "synthetic fixture suite",
                )
            end,
        )
    end

    with_capture_root() do root
        missing_workbook = synthetic_xlsx(
            0x01;
            names = [
                "[Content_Types].xml",
                "_rels/.rels",
                "xl/not-workbook.xml",
                "xl/worksheets/sheet1.xml",
            ],
        )
        bad = response_for(
            xlsx_plan.workbooks[1],
            1;
            raw_bytes = missing_workbook,
        )
        @test occursin(
            "required XLSX",
            error_message() do
                import_present_day_pair(
                    25,
                    root,
                    [bad, response_for(xlsx_plan.workbooks[2], 2)];
                    observed_local_date = "2026-08-07",
                    importer = "synthetic fixture suite",
                )
            end,
        )
    end

    with_capture_root() do root
        @test_throws BEAHMI7AdvanceCaptureError import_present_day_pair(
            1,
            root,
            [base[1]];
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        duplicate = response_for(
            plan.workbooks[2],
            2;
            raw_bytes = synthetic_xls(0x01),
        )
        @test_throws BEAHMI7AdvanceCaptureError import_present_day_pair(
            1,
            root,
            [base[1], duplicate];
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        @test_throws BEAHMI7AdvanceCaptureError import_present_day_pair(
            1,
            root,
            base;
            observed_local_date = "2026-08-07",
            importer = " ",
        )
        @test_throws BEAHMI7AdvanceCaptureError import_present_day_pair(
            1,
            root,
            base;
            observed_local_date = "2025-01-01",
            importer = "synthetic fixture suite",
        )
    end
end

# The former "live seam requires same-day terms review" testset was removed:
# it asserted that capture_started_at_utc falls within one UTC date of
# capture_local_date, so it passed or failed depending on the wall clock.
# CI must be deterministic, and the prospective-capture programme it served
# was retired in this release.

@testset "bundle validator detects filesystem and receipt tampering" begin
    with_capture_root() do root
        plan = capture_plan(1)
        captured = import_present_day_pair(
            1,
            root,
            responses_for(plan);
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        object_path = captured.workbooks[1].object_path
        chmod(object_path, 0o644)
        @test occursin(
            "owner-writable",
            error_message(
                () -> validate_capture_bundle(captured.bundle_path),
            ),
        )
        chmod(object_path, 0o444)
        @test validate_capture_bundle(captured.bundle_path).receipt_sha256 ==
            captured.receipt_sha256
    end

    with_capture_root() do root
        plan = capture_plan(1)
        captured = import_present_day_pair(
            1,
            root,
            responses_for(plan);
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        outside_alias = joinpath(root, "outside-object-hardlink.xls")
        hardlink(captured.workbooks[1].object_path, outside_alias)
        @test occursin(
            "hard-link aliases",
            error_message(
                () -> validate_capture_bundle(captured.bundle_path),
            ),
        )
    end

    with_capture_root() do root
        plan = capture_plan(1)
        captured = import_present_day_pair(
            1,
            root,
            responses_for(plan);
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        outside_alias = joinpath(root, "outside-receipt-hardlink.toml")
        hardlink(captured.receipt_path, outside_alias)
        @test occursin(
            "hard-link aliases",
            error_message(
                () -> validate_capture_bundle(captured.bundle_path),
            ),
        )
    end

    with_capture_root() do root
        plan = capture_plan(1)
        captured = import_present_day_pair(
            1,
            root,
            responses_for(plan);
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        make_writable(captured.bundle_path)
        document = TOML.parsefile(captured.receipt_path)
        document["gates"]["ready"] = true
        new_digest = receipt_sha256(document)
        document["artifact"]["receipt_sha256"] = new_digest
        new_receipt =
            joinpath(captured.bundle_path, "receipt-self-sha256-$new_digest.toml")
        rm(captured.receipt_path)
        write_canonical_toml(new_receipt, document)
        chmod(new_receipt, 0o444)
        chmod(joinpath(captured.bundle_path, "objects"), 0o555)
        for object in readdir(joinpath(captured.bundle_path, "objects"))
            chmod(joinpath(captured.bundle_path, "objects", object), 0o444)
        end
        old_bundle = captured.bundle_path
        new_bundle = joinpath(root, "receipt-sha256-$new_digest")
        mv(old_bundle, new_bundle)
        chmod(new_bundle, 0o555)
        @test occursin(
            "receipt.gates.ready",
            error_message(() -> validate_capture_bundle(new_bundle)),
        )
    end

    with_capture_root() do root
        plan = capture_plan(1)
        captured = import_present_day_pair(
            1,
            root,
            responses_for(plan);
            observed_local_date = "2026-08-07",
            importer = "synthetic fixture suite",
        )
        make_writable(captured.bundle_path)
        document = TOML.parsefile(captured.receipt_path)
        document["capture"]["network_transport_verified"] = true
        new_digest = receipt_sha256(document)
        document["artifact"]["receipt_sha256"] = new_digest
        new_receipt =
            joinpath(captured.bundle_path, "receipt-self-sha256-$new_digest.toml")
        rm(captured.receipt_path)
        write_canonical_toml(new_receipt, document)
        chmod(new_receipt, 0o444)
        objects_path = joinpath(captured.bundle_path, "objects")
        chmod(objects_path, 0o555)
        for object in readdir(objects_path)
            chmod(joinpath(objects_path, object), 0o444)
        end
        new_bundle = joinpath(root, "receipt-sha256-$new_digest")
        mv(captured.bundle_path, new_bundle)
        chmod(new_bundle, 0o555)
        @test occursin(
            "network_transport_verified",
            error_message(() -> validate_capture_bundle(new_bundle)),
        )
    end
end
