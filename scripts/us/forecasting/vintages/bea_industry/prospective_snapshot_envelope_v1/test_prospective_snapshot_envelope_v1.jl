using Test
using SHA
using TOML

include(joinpath(@__DIR__, "USProspectiveSnapshotEnvelopeV1.jl"))
using .USProspectiveSnapshotEnvelopeV1

const M = USProspectiveSnapshotEnvelopeV1

push_u16!(bytes, value) = append!(
    bytes,
    UInt8[UInt16(value) & 0xff, (UInt16(value) >> 8) & 0xff],
)

push_u32!(bytes, value) = append!(
    bytes,
    UInt8[
        UInt32(value) & 0xff,
        (UInt32(value) >> 8) & 0xff,
        (UInt32(value) >> 16) & 0xff,
        (UInt32(value) >> 24) & 0xff,
    ],
)

function stored_zip(entries)
    bytes = UInt8[]
    directory = NamedTuple[]
    for (name_value, payload_value) in entries
        name = Vector{UInt8}(codeunits(String(name_value)))
        payload = UInt8[byte for byte in payload_value]
        offset = length(bytes)
        crc = parse(UInt32, M.crc32_hex(payload); base = 16)
        push_u32!(bytes, 0x04034b50)
        push_u16!(bytes, 20)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u32!(bytes, crc)
        push_u32!(bytes, length(payload))
        push_u32!(bytes, length(payload))
        push_u16!(bytes, length(name))
        push_u16!(bytes, 0)
        append!(bytes, name)
        append!(bytes, payload)
        push!(directory, (; name, payload, offset, crc))
    end
    central_offset = length(bytes)
    for row in directory
        push_u32!(bytes, 0x02014b50)
        push_u16!(bytes, 20)
        push_u16!(bytes, 20)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u32!(bytes, row.crc)
        push_u32!(bytes, length(row.payload))
        push_u32!(bytes, length(row.payload))
        push_u16!(bytes, length(row.name))
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u32!(bytes, 0)
        push_u32!(bytes, row.offset)
        append!(bytes, row.name)
    end
    central_size = length(bytes) - central_offset
    push_u32!(bytes, 0x06054b50)
    push_u16!(bytes, 0)
    push_u16!(bytes, 0)
    push_u16!(bytes, length(directory))
    push_u16!(bytes, length(directory))
    push_u32!(bytes, central_size)
    push_u32!(bytes, central_offset)
    push_u16!(bytes, 0)
    return bytes
end

function policy_for(body; kwargs...)
    values = Dict{Symbol, Any}(
        :policy_id => "synthetic-policy-v1",
        :source_id => "synthetic-source",
        :campaign_id => "synthetic-campaign",
        :artifact_id => "synthetic-artifact",
        :requested_url => "https://example.gov/releases/fixed.zip",
        :expected_host => "example.gov",
        :media_types => ["application/zip"],
        :extension => "zip",
        :minimum_body_bytes => 1,
        :maximum_body_bytes => 1_000_000,
        :maximum_duration_seconds => 10,
        :maximum_header_count => 8,
        :maximum_header_bytes => 8_192,
        :not_before_utc => "2026-08-08T00:00:00.000Z",
        :deadline_utc => "2026-08-08T23:59:59.000Z",
        :expected_body_sha256 => bytes2hex(sha256(body)),
        :request_headers => [
            "Accept" => "application/zip",
            "Accept-Encoding" => "identity",
            "User-Agent" => "Synthetic-Test/1.0",
        ],
        :source_bindings => Dict("test_source" => repeat("1", 64)),
        :blockers => ["SYNTHETIC_TEST_ONLY"],
    )
    merge!(values, Dict(kwargs))
    return M.CapturePolicy(; values...)
end

function response_for(policy, body; kwargs...)
    values = Dict{Symbol, Any}(
        :body => body,
        :http_status => 200,
        :requested_url => policy.requested_url,
        :effective_url => policy.requested_url,
        :request_headers => copy(policy.request_headers),
        :response_headers => [
            "Content-Type" => "application/zip",
            "Content-Length" => string(length(body)),
        ],
        :response_headers_complete => true,
        :parsed_header_order_preserved => true,
        :raw_wire_headers_preserved => false,
        :redirect_chain => Tuple{Int, String, String}[],
        :request_started_at_utc => "2026-08-08T12:00:00.000Z",
        :response_headers_at_utc => "2026-08-08T12:00:00.100Z",
        :response_body_completed_at_utc => "2026-08-08T12:00:00.200Z",
        :proxy_used => false,
        :netrc_used => false,
        :cookies_used => false,
        :retry_count => 0,
    )
    merge!(values, Dict(kwargs))
    return M.FetchResponse(; values...)
end

fixed_clock(value = "2026-08-08T11:59:59.900Z") =
    M.ClockSource(() -> M.ClockSample(value))

function sequence_clock(values)
    samples = M.ClockSample[M.ClockSample(value) for value in values]
    index = Ref(0)
    return M.ClockSource(
        function ()
            index[] += 1
            index[] <= length(samples) || error("clock sequence exhausted")
            return samples[index[]]
        end
    )
end

function make_writable(path)
    ispath(path) || return
    for (root, directories, files) in walkdir(path; topdown = false)
        for file in files
            chmod(joinpath(root, file), 0o600)
        end
        for directory in directories
            chmod(joinpath(root, directory), 0o700)
        end
        chmod(root, 0o700)
    end
    return
end

function make_read_only(path)
    for (root, directories, files) in walkdir(path; topdown = false)
        for file in files
            chmod(joinpath(root, file), 0o400)
        end
        for directory in directories
            chmod(joinpath(root, directory), 0o500)
        end
        chmod(root, 0o500)
    end
    return
end

function expect_error(f, pattern)
    error = try
        f()
        nothing
    catch caught
        caught
    end
    @test error isa M.EnvelopeError
    return @test occursin(pattern, sprint(showerror, error))
end

@testset "USProspectiveSnapshotEnvelopeV1" begin
    payload = Vector{UInt8}(codeunits("selector payload"))
    archive = stored_zip(["payload.txt" => payload])
    policy = policy_for(archive)

    @testset "closed policy and dry run" begin
        plan = M.dry_run_plan(policy, "synthetic-transaction")
        @test plan.network_request_count == 0
        @test plan.filesystem_write_count == 0
        @test plan.request_count_if_live == 1
        @test all(value === false for value in values(plan.gates))
        called = Ref(0)
        result = M.capture_with_fetcher(
            policy;
            raw_root = "/path/not/inspected/in/dry/run",
            transaction_id = "synthetic-transaction",
            actor = "nobody",
            terms_reviewed_local_date = "2026-08-08",
            execute_live = false,
            fetcher = (_...) -> (called[] += 1),
        )
        @test result isa M.CapturePlan
        @test called[] == 0
        expect_error(
            () -> policy_for(archive; requested_url = "http://example.gov/x.zip"),
            "HTTPS URL",
        )
        expect_error(
            () -> policy_for(
                archive;
                request_headers = [
                    "Accept" => "application/zip",
                    "Accept-Encoding" => "gzip",
                    "User-Agent" => "x",
                ],
            ),
            "identity",
        )
        expect_error(
            () -> policy_for(
                archive;
                request_headers = [
                    "Accept" => "application/zip",
                    "Accept-Encoding" => "identity",
                    "User-Agent" => "x",
                    "Cookie" => "secret",
                ],
            ),
            "credential-bearing",
        )
    end

    @testset "response and header adversaries" begin
        valid = M.validate_response(policy, response_for(policy, archive))
        @test valid.body_sha256 == bytes2hex(sha256(archive))
        @test valid.body_byte_count == length(archive)
        expect_error(
            () -> M._receipt_document(
                policy,
                "synthetic-transaction",
                "synthetic tester",
                "2026-08-07",
                valid,
                Dict{String, Any}(
                    "all_profiles_verified" => false,
                    "profile_count" => 0,
                ),
                M._timestamp_document(nothing, nothing, valid.body_sha256),
                M.ClockSample("2026-08-08T11:59:59.800Z"),
                M.ClockSample("2026-08-08T11:59:59.900Z"),
            ),
            "UTC request-start date",
        )
        duplicate_exact = response_for(
            policy,
            archive;
            response_headers = [
                "Content-Type" => "application/zip",
                "content-type" => "application/zip",
                "Content-Length" => string(length(archive)),
            ],
        )
        @test M.validate_response(policy, duplicate_exact).content_type == "application/zip"
        cases = [
            (
                "conflicting", (;
                    response_headers = [
                        "Content-Type" => "application/zip",
                        "content-type" => "text/plain",
                    ],
                ),
            ),
            ("invalid HTTP token", (; response_headers = ["Bad Name" => "x", "Content-Type" => "application/zip"])),
            ("surrounding whitespace", (; response_headers = ["Content-Type" => " application/zip"])),
            ("control character", (; response_headers = ["Content-Type" => "application/zip", "X-Test" => "x\0y"])),
            ("media type", (; response_headers = ["Content-Type" => "text/plain"])),
            ("identity", (; response_headers = ["Content-Type" => "application/zip", "Content-Encoding" => "gzip"])),
            ("redirect", (; redirect_chain = [(302, policy.requested_url, "https://example.gov/other")], effective_url = "https://example.gov/other")),
            ("must be false", (; proxy_used = true)),
            ("must be false", (; netrc_used = true)),
            ("must be false", (; cookies_used = true)),
            ("must equal zero", (; retry_count = 1)),
            ("must be true", (; response_headers_complete = false)),
            ("must be true", (; parsed_header_order_preserved = false)),
            ("cannot claim raw-wire", (; raw_wire_headers_preserved = true)),
            ("does not equal body", (; response_headers = ["Content-Type" => "application/zip", "Content-Length" => "1"])),
            ("monotone", (; response_headers_at_utc = "2026-08-08T11:59:59.000Z")),
            ("after capture deadline", (; request_started_at_utc = "2026-08-08T23:59:55.000Z", response_headers_at_utc = "2026-08-08T23:59:55.100Z", response_body_completed_at_utc = "2026-08-09T00:00:00.000Z")),
        ]
        for (pattern, changes) in cases
            expect_error(
                () -> M.validate_response(policy, response_for(policy, archive; changes...)),
                pattern,
            )
        end
        changed = copy(archive)
        changed[1] = xor(changed[1], 0x01)
        expect_error(
            () -> M.validate_response(policy, response_for(policy, changed)),
            "SHA-256",
        )
    end

    @testset "ZIP and OOXML adversaries" begin
        entries = M.inspect_zip(archive)
        @test length(entries) == 1
        evidence = M.verify_member_payload(
            entries,
            "payload.txt",
            payload;
            expected_sha256 = bytes2hex(sha256(payload)),
        )
        @test evidence.member_crc32 == M.crc32_hex(payload)
        @test M.crc32_hex(Vector{UInt8}(codeunits("123456789"))) == "cbf43926"
        expect_error(
            () -> M.verify_member_payload(entries, "payload.txt", UInt8[0x00]),
            "size mismatch",
        )
        expect_error(
            () -> M.inspect_zip(stored_zip(["same" => UInt8[1], "same" => UInt8[2]])),
            "duplicate",
        )
        expect_error(
            () -> M.inspect_zip(stored_zip(["../escape" => UInt8[1]])),
            "non-canonical",
        )
        trailing = vcat(archive, UInt8[0x00])
        expect_error(() -> M.inspect_zip(trailing), "terminal EOCD")
        expect_error(
            () -> M.inspect_zip(archive; maximum_uncompressed_bytes = 1),
            "uncompressed bytes",
        )

        xml = Vector{UInt8}(
            codeunits(
                "<?xml version=\"1.0\"?><workbook><sheets>" *
                    "<sheet name=\"2017\"/><sheet name=\"A&amp;B\"/>" *
                    "</sheets></workbook>",
            )
        )
        workbook = stored_zip(
            [
                "[Content_Types].xml" => Vector{UInt8}(codeunits("<Types/>")),
                "_rels/.rels" => Vector{UInt8}(codeunits("<Relationships/>")),
                "xl/workbook.xml" => xml,
            ]
        )
        ooxml = M.verify_ooxml_workbook(
            workbook,
            xml;
            expected_workbook_sha256 = bytes2hex(sha256(workbook)),
            expected_workbook_xml_sha256 = bytes2hex(sha256(xml)),
            required_sheets = ["2017", "A&B"],
        )
        @test ooxml.sheets == ["2017", "A&B"]
        missing = stored_zip(["xl/workbook.xml" => xml])
        expect_error(() -> M.verify_ooxml_workbook(missing, xml), "missing required")
        duplicate_xml = Vector{UInt8}(
            codeunits(
                "<workbook><sheet name=\"2017\"/><sheet name=\"2017\"/></workbook>",
            )
        )
        duplicate_workbook = stored_zip(
            [
                "[Content_Types].xml" => UInt8[1],
                "_rels/.rels" => UInt8[2],
                "xl/workbook.xml" => duplicate_xml,
            ]
        )
        expect_error(
            () -> M.verify_ooxml_workbook(duplicate_workbook, duplicate_xml),
            "duplicate decoded",
        )
        dtd_xml = Vector{UInt8}(
            codeunits(
                "<!DOCTYPE x [<!ENTITY e SYSTEM \"file:///etc/passwd\">]>" *
                    "<workbook><sheet name=\"2017\"/></workbook>",
            )
        )
        dtd_workbook = stored_zip(
            [
                "[Content_Types].xml" => UInt8[1],
                "_rels/.rels" => UInt8[2],
                "xl/workbook.xml" => dtd_xml,
            ]
        )
        expect_error(() -> M.verify_ooxml_workbook(dtd_workbook, dtd_xml), "DOCTYPE")
    end

    @testset "dual pre-callback clock gates" begin
        fetch_calls = Ref(0)
        fetcher = function (_...)
            fetch_calls[] += 1
            return response_for(policy, archive)
        end
        for (label, clock_value) in (
                ("initial-early", "2026-08-07T23:59:59.999Z"),
                ("initial-late", "2026-08-09T00:00:00.000Z"),
            )
            parent = mktempdir()
            try
                root = realpath(parent)
                expect_error(
                    () -> M.capture_with_fetcher(
                        policy;
                        raw_root = root,
                        transaction_id = label,
                        actor = "synthetic tester",
                        terms_reviewed_local_date = "2026-08-08",
                        execute_live = true,
                        fetcher = fetcher,
                        clock_source = fixed_clock(clock_value),
                    ),
                    "callback remains unreachable",
                )
                @test isempty(readdir(root))
                @test fetch_calls[] == 0
            finally
                make_writable(parent)
                rm(parent; recursive = true, force = true)
            end
        end
        for (label, second_value) in (
                ("post-journal-early", "2026-08-07T23:59:59.999Z"),
                ("post-journal-late", "2026-08-09T00:00:00.000Z"),
            )
            parent = mktempdir()
            try
                root = realpath(parent)
                expect_error(
                    () -> M.capture_with_fetcher(
                        policy;
                        raw_root = root,
                        transaction_id = label,
                        actor = "synthetic tester",
                        terms_reviewed_local_date = "2026-08-08",
                        execute_live = true,
                        fetcher = fetcher,
                        clock_source = sequence_clock(
                            [
                                "2026-08-08T11:59:59.800Z",
                                second_value,
                            ]
                        ),
                    ),
                    "callback remains unreachable",
                )
                @test fetch_calls[] == 0
                @test isdir(joinpath(root, ".$label.exactly-once.lock"))
                journal = TOML.parsefile(joinpath(root, ".$label.private-recovery.toml"))
                @test journal["state"] == "REQUEST_AUTHORIZED"
                @test journal["request_may_have_begun"] === true
            finally
                make_writable(parent)
                rm(parent; recursive = true, force = true)
            end
        end
    end

    @testset "received-invalid response quarantine" begin
        selector = body -> Dict{String, Any}(
            "all_profiles_verified" => true,
            "body_sha256" => bytes2hex(sha256(body)),
            "profile_count" => 1,
            "status" => "SYNTHETIC_VERIFIED",
        )
        cases = [
            (
                transaction_id = "wrong-hash",
                case_policy = policy_for(archive; expected_body_sha256 = repeat("0", 64)),
                response_builder = response_for,
                selector_builder = selector,
                failure_code = "RESPONSE_VALIDATION_FAILED",
                error_type = M.EnvelopeError,
            ),
            (
                transaction_id = "wrong-content-type",
                case_policy = policy,
                response_builder = (p, b) -> response_for(
                    p,
                    b;
                    response_headers = [
                        "Content-Type" => "text/plain",
                        "Content-Length" => string(length(b)),
                    ],
                ),
                selector_builder = selector,
                failure_code = "RESPONSE_VALIDATION_FAILED",
                error_type = M.EnvelopeError,
            ),
            (
                transaction_id = "selector-failure",
                case_policy = policy,
                response_builder = response_for,
                selector_builder = _body -> error("synthetic selector failure"),
                failure_code = "SELECTOR_VALIDATION_FAILED",
                error_type = ErrorException,
            ),
        ]
        for case in cases
            parent = mktempdir()
            try
                root = realpath(parent)
                calls = Ref(0)
                fetcher = function (_...)
                    calls[] += 1
                    return case.response_builder(case.case_policy, archive)
                end
                caught = try
                    M.capture_with_fetcher(
                        case.case_policy;
                        raw_root = root,
                        transaction_id = case.transaction_id,
                        actor = "synthetic tester",
                        terms_reviewed_local_date = "2026-08-08",
                        execute_live = true,
                        fetcher = fetcher,
                        selector_builder = case.selector_builder,
                        clock_source = fixed_clock(),
                    )
                    nothing
                catch error
                    error
                end
                @test caught isa case.error_type
                @test calls[] == 1
                quarantine_path = joinpath(root, case.transaction_id * ".quarantine")
                @test isdir(quarantine_path)
                @test !isfile(joinpath(quarantine_path, "receipt.toml"))
                @test !isfile(joinpath(quarantine_path, "manifest.toml"))
                validated_quarantine = M.validate_quarantine(case.case_policy, quarantine_path)
                @test validated_quarantine.status ==
                    "VALIDATED_NONADMITTING_QUARANTINE_NO_RETRY"
                @test validated_quarantine.failure_code == case.failure_code
                @test validated_quarantine.completion_receipt_created === false
                @test validated_quarantine.selector_completion_claimed === false
                @test all(value === false for value in values(validated_quarantine.gates))
                @test stat(joinpath(quarantine_path, "replica-a", "raw.zip")).inode !=
                    stat(joinpath(quarantine_path, "replica-b", "raw.zip")).inode
                failure = TOML.parsefile(joinpath(quarantine_path, "failure.toml"))
                @test failure["profile_count"] == 0
                @test failure["retry_allowed"] === false
                if case.transaction_id == "wrong-hash"
                    failure_path = joinpath(quarantine_path, "failure.toml")
                    manifest_path = joinpath(quarantine_path, "quarantine-manifest.toml")
                    original_failure = read(failure_path)
                    original_manifest = read(manifest_path)
                    for (mutator, pattern) in (
                            (
                                document -> (document["completion_receipt_created"] = true),
                                "completion receipt claim must be false",
                            ),
                            (
                                document -> (document["profile_count"] = false),
                                "profile_count: must be an integer",
                            ),
                        )
                        make_writable(quarantine_path)
                        tampered_failure = TOML.parse(String(copy(original_failure)))
                        mutator(tampered_failure)
                        open(failure_path, "w") do io
                            TOML.print(io, tampered_failure; sorted = true)
                        end
                        tampered_manifest = TOML.parse(String(copy(original_manifest)))
                        for record in tampered_manifest["files"]
                            if record["path"] == "failure.toml"
                                bytes = read(failure_path)
                                record["byte_count"] = length(bytes)
                                record["sha256"] = bytes2hex(sha256(bytes))
                            end
                        end
                        tampered_manifest["artifact"]["manifest_sha256"] =
                            M._manifest_hash(tampered_manifest)
                        open(manifest_path, "w") do io
                            TOML.print(io, tampered_manifest; sorted = true)
                        end
                        make_read_only(quarantine_path)
                        expect_error(
                            () -> M.validate_quarantine(case.case_policy, quarantine_path),
                            pattern,
                        )
                        make_writable(quarantine_path)
                        open(failure_path, "w") do io
                            write(io, original_failure)
                        end
                        open(manifest_path, "w") do io
                            write(io, original_manifest)
                        end
                    end
                    make_read_only(quarantine_path)
                    @test M.validate_quarantine(case.case_policy, quarantine_path).failure_code ==
                        case.failure_code
                    paths = M._transaction_paths(root, case.transaction_id)
                    M._write_journal(
                        paths.journal,
                        case.case_policy,
                        case.transaction_id,
                        "QUARANTINE_SEALED",
                        true,
                    )
                    expect_error(
                        () -> M.validate_quarantine(case.case_policy, quarantine_path),
                        "publication state",
                    )
                end
                second = M.capture_with_fetcher(
                    case.case_policy;
                    raw_root = root,
                    transaction_id = case.transaction_id,
                    actor = "ignored",
                    terms_reviewed_local_date = "2026-08-08",
                    execute_live = true,
                    fetcher = fetcher,
                    selector_builder = case.selector_builder,
                    clock_source = fixed_clock("2026-08-09T00:00:00.000Z"),
                )
                @test second.status == "VALIDATED_NONADMITTING_QUARANTINE_NO_RETRY"
                @test calls[] == 1
                if case.transaction_id == "wrong-hash"
                    @test TOML.parsefile(
                        joinpath(root, ".wrong-hash.private-recovery.toml"),
                    )["state"] == "QUARANTINED_NONADMITTING"
                end
            finally
                make_writable(parent)
                rm(parent; recursive = true, force = true)
            end
        end
    end

    @testset "exactly once, replicas, reconstruction, and recovery" begin
        temporary_parent = mktempdir()
        try
            root = realpath(temporary_parent)
            calls = Ref(0)
            fetcher = function (_url, _headers, _max_bytes, _timeout)
                calls[] += 1
                return response_for(policy, archive)
            end
            selector = body -> Dict{String, Any}(
                "all_profiles_verified" => true,
                "body_sha256" => bytes2hex(sha256(body)),
                "profile_count" => 1,
                "status" => "SYNTHETIC_VERIFIED",
            )
            result = M.capture_with_fetcher(
                policy;
                raw_root = root,
                transaction_id = "successful-transaction",
                actor = "synthetic tester",
                terms_reviewed_local_date = "2026-08-08",
                execute_live = true,
                fetcher = fetcher,
                selector_builder = selector,
                clock_source = fixed_clock(),
            )
            @test calls[] == 1
            @test result.status == "VALIDATED_NONADMITTING_PROSPECTIVE_SNAPSHOT_BUNDLE"
            @test result.external_timestamp_established === false
            @test all(value === false for value in values(result.gates))
            bundle = joinpath(root, "successful-transaction")
            @test isdir(bundle)
            @test isfile(joinpath(root, ".successful-transaction.private-recovery.toml"))
            success_paths = M._transaction_paths(root, "successful-transaction")
            M._write_journal(
                success_paths.journal,
                policy,
                "successful-transaction",
                "REPLICAS_SEALED",
                true,
            )
            expect_error(
                () -> M.validate_bundle(policy, bundle; selector_builder = selector),
                "publication state",
            )
            second = M.capture_with_fetcher(
                policy;
                raw_root = root,
                transaction_id = "successful-transaction",
                actor = "ignored because no request",
                terms_reviewed_local_date = "2026-08-08",
                execute_live = true,
                fetcher = fetcher,
                selector_builder = selector,
                clock_source = fixed_clock(),
            )
            @test calls[] == 1
            @test second.body_sha256 == result.body_sha256
            @test TOML.parsefile(success_paths.journal)["state"] == "PUBLISHED"
            receipt = TOML.parsefile(joinpath(bundle, "receipt.toml"))
            @test receipt["external_timestamp"]["established"] === false
            @test receipt["transport"]["raw_wire_headers_preserved"] === false
            @test receipt["gates"] == M.ALWAYS_FALSE_GATES
            @test receipt["issue_authorization"]["clock_authentication"] ==
                M.CLOCK_AUTHENTICATION
            @test receipt["issue_authorization"]["window_gate_status"] ==
                "PASSED_TWICE_BEFORE_FETCH_CALLBACK"
            @test receipt["issue_authorization"]["post_journal_issue_clock_observed_at_utc"] ==
                "2026-08-08T11:59:59.900Z"
            @test stat(joinpath(bundle, "replica-a", "raw.zip")).inode !=
                stat(joinpath(bundle, "replica-b", "raw.zip")).inode

            manifest_path = joinpath(bundle, "manifest.toml")
            receipt_path = joinpath(bundle, "receipt.toml")
            transport_a_path = joinpath(bundle, "replica-a", "transport.toml")
            transport_b_path = joinpath(bundle, "replica-b", "transport.toml")
            original_manifest = read(manifest_path)
            original_receipt = read(receipt_path)
            original_transport_a = read(transport_a_path)
            original_transport_b = read(transport_b_path)

            make_writable(bundle)
            alias_manifest = TOML.parse(String(copy(original_manifest)))
            alias_manifest["replica_count"] = 2.0
            alias_manifest["artifact"]["manifest_sha256"] = M._manifest_hash(alias_manifest)
            open(manifest_path, "w") do io
                TOML.print(io, alias_manifest; sorted = true)
            end
            make_read_only(bundle)
            expect_error(
                () -> M.validate_bundle(policy, bundle; selector_builder = selector),
                "replica_count: must be an integer",
            )

            make_writable(bundle)
            open(manifest_path, "w") do io
                write(io, original_manifest)
            end
            alias_receipt = TOML.parse(String(copy(original_receipt)))
            alias_receipt["limits"]["request_count"] = true
            alias_receipt["artifact"]["receipt_sha256"] = M._receipt_hash(alias_receipt)
            open(receipt_path, "w") do io
                TOML.print(io, alias_receipt; sorted = true)
            end
            receipt_manifest = TOML.parse(String(copy(original_manifest)))
            receipt_manifest["receipt_sha256"] = alias_receipt["artifact"]["receipt_sha256"]
            for record in receipt_manifest["files"]
                if record["path"] == "receipt.toml"
                    bytes = read(receipt_path)
                    record["byte_count"] = length(bytes)
                    record["sha256"] = bytes2hex(sha256(bytes))
                end
            end
            receipt_manifest["artifact"]["manifest_sha256"] = M._manifest_hash(receipt_manifest)
            open(manifest_path, "w") do io
                TOML.print(io, receipt_manifest; sorted = true)
            end
            make_read_only(bundle)
            expect_error(
                () -> M.validate_bundle(policy, bundle; selector_builder = selector),
                "request_count: must be an integer",
            )

            make_writable(bundle)
            open(receipt_path, "w") do io
                write(io, original_receipt)
            end
            alias_transport = TOML.parse(String(copy(original_transport_a)))
            alias_transport["request_headers"][1]["sequence"] = 1.0
            for path in (transport_a_path, transport_b_path)
                open(path, "w") do io
                    TOML.print(io, alias_transport; sorted = true)
                end
            end
            transport_manifest = TOML.parse(String(copy(original_manifest)))
            for record in transport_manifest["files"]
                if record["path"] in (
                        joinpath("replica-a", "transport.toml"),
                        joinpath("replica-b", "transport.toml"),
                    )
                    bytes = read(joinpath(bundle, record["path"]))
                    record["byte_count"] = length(bytes)
                    record["sha256"] = bytes2hex(sha256(bytes))
                end
            end
            transport_manifest["artifact"]["manifest_sha256"] =
                M._manifest_hash(transport_manifest)
            open(manifest_path, "w") do io
                TOML.print(io, transport_manifest; sorted = true)
            end
            make_read_only(bundle)
            expect_error(
                () -> M.validate_bundle(policy, bundle; selector_builder = selector),
                "sequence: must be an integer",
            )

            make_writable(bundle)
            open(manifest_path, "w") do io
                write(io, original_manifest)
            end
            open(receipt_path, "w") do io
                write(io, original_receipt)
            end
            open(transport_a_path, "w") do io
                write(io, original_transport_a)
            end
            open(transport_b_path, "w") do io
                write(io, original_transport_b)
            end
            make_read_only(bundle)
            @test M.validate_bundle(policy, bundle; selector_builder = selector).body_sha256 ==
                result.body_sha256

            make_writable(bundle)
            malicious_link = joinpath(bundle, "replica-link")
            symlink(joinpath(bundle, "replica-a"), malicious_link)
            make_read_only(bundle)
            expect_error(
                () -> M.validate_bundle(policy, bundle; selector_builder = selector),
                "symbolic-link path",
            )
            chmod(bundle, 0o700)
            rm(malicious_link)
            make_read_only(bundle)

            make_writable(bundle)
            raw_a = joinpath(bundle, "replica-a", "raw.zip")
            raw_b = joinpath(bundle, "replica-b", "raw.zip")
            raw_b_bytes = read(raw_b)
            rm(raw_b)
            hardlink(raw_a, raw_b)
            make_read_only(bundle)
            expect_error(
                () -> M.validate_bundle(policy, bundle; selector_builder = selector),
                "hard-linked",
            )
            make_writable(bundle)
            rm(raw_b)
            open(raw_b, "w") do io
                write(io, raw_b_bytes)
            end
            make_read_only(bundle)
            @test M.validate_bundle(policy, bundle; selector_builder = selector).body_sha256 ==
                result.body_sha256

            timestamp_token = Vector{UInt8}(codeunits("synthetic timestamp token"))
            timestamp_provider = (_hash, completed) ->
            M.TimestampEvidence("synthetic-tsa", completed, timestamp_token)
            timestamp_verifier = (evidence, _hash) ->
            evidence.provider == "synthetic-tsa" && evidence.token == timestamp_token
            timestamped = M.capture_with_fetcher(
                policy;
                raw_root = root,
                transaction_id = "timestamped-transaction",
                actor = "synthetic tester",
                terms_reviewed_local_date = "2026-08-08",
                execute_live = true,
                fetcher = fetcher,
                selector_builder = selector,
                timestamp_provider = timestamp_provider,
                timestamp_verifier = timestamp_verifier,
                clock_source = fixed_clock(),
            )
            @test timestamped.external_timestamp_established === true
            @test isfile(
                joinpath(
                    root,
                    "timestamped-transaction",
                    "replica-a",
                    "external-timestamp-token.bin",
                ),
            )
            @test M.validate_bundle(
                policy,
                joinpath(root, "timestamped-transaction");
                selector_builder = selector,
                timestamp_verifier = timestamp_verifier,
            ).external_timestamp_established === true
            expect_error(
                () -> M.validate_bundle(
                    policy,
                    joinpath(root, "timestamped-transaction");
                    selector_builder = selector,
                    timestamp_verifier = (_evidence, _hash) -> false,
                ),
                "verification failed",
            )

            make_writable(bundle)
            open(raw_a, "w") do io
                write(io, UInt8[0x00])
            end
            make_read_only(bundle)
            expect_error(
                () -> M.validate_bundle(policy, bundle; selector_builder = selector),
                "size mismatch",
            )

            failed_calls = Ref(0)
            failing = function (_...)
                failed_calls[] += 1
                error("synthetic transport failure")
            end
            @test_throws ErrorException M.capture_with_fetcher(
                policy;
                raw_root = root,
                transaction_id = "uncertain-request-transaction",
                actor = "synthetic tester",
                terms_reviewed_local_date = "2026-08-08",
                execute_live = true,
                fetcher = failing,
                selector_builder = selector,
                clock_source = fixed_clock(),
            )
            @test failed_calls[] == 1
            expect_error(
                () -> M.capture_with_fetcher(
                    policy;
                    raw_root = root,
                    transaction_id = "uncertain-request-transaction",
                    actor = "synthetic tester",
                    terms_reviewed_local_date = "2026-08-08",
                    execute_live = true,
                    fetcher = failing,
                    selector_builder = selector,
                    clock_source = fixed_clock(),
                ),
                "no retry allowed",
            )
            @test failed_calls[] == 1

            symlink_root = joinpath(dirname(root), basename(root) * "-symlink")
            symlink(root, symlink_root)
            expect_error(
                () -> M.capture_with_fetcher(
                    policy;
                    raw_root = symlink_root,
                    transaction_id = "symlink-root",
                    actor = "synthetic tester",
                    terms_reviewed_local_date = "2026-08-08",
                    execute_live = true,
                    fetcher = fetcher,
                    selector_builder = selector,
                    clock_source = fixed_clock(),
                ),
                "symbolic",
            )
            rm(symlink_root)
        finally
            make_writable(temporary_parent)
            rm(temporary_parent; recursive = true, force = true)
        end
    end
end
