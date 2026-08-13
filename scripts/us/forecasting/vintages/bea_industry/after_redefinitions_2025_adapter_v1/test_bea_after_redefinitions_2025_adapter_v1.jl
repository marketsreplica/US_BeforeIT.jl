using Test
using SHA
using TOML

include(joinpath(@__DIR__, "USBEAAfterRedefinitions2025AdapterV1.jl"))
using .USBEAAfterRedefinitions2025AdapterV1

const A = USBEAAfterRedefinitions2025AdapterV1
const E = A.Envelope
const DEFAULT_ARCHIVE =
    "/private/tmp/beforeit-after-redefinitions.rwZkrt/MAKE-USE-IMPORTS_AFTER_REDEFINITIONS.zip"

function expect_adapter_error(f, pattern)
    error = try
        f()
        nothing
    catch caught
        caught
    end
    @test error isa A.AdapterError
    return @test occursin(pattern, sprint(showerror, error))
end

function expect_envelope_error(f, pattern)
    error = try
        f()
        nothing
    catch caught
        caught
    end
    @test error isa E.EnvelopeError
    return @test occursin(pattern, sprint(showerror, error))
end

function with_profile_mutation(test_function, mutator)
    document = TOML.parsefile(A.PROFILE_PATH)
    mutator(document)
    return mktempdir() do directory
        path = joinpath(directory, "profile.toml")
        open(path, "w") do io
            TOML.print(io, document; sorted = true)
        end
        test_function(path)
    end
end

function extracted_material(archive_path)
    members = sort!(collect(A.REQUIRED_WORKBOOK_MEMBERS))
    payloads = Dict{String, Vector{UInt8}}()
    xmls = Dict{String, Vector{UInt8}}()
    for member in members
        payload = read(pipeline(`unzip -p $archive_path $member`))
        payloads[member] = payload
        mktempdir() do directory
            workbook_path = joinpath(directory, "workbook.xlsx")
            open(workbook_path, "w") do io
                write(io, payload)
            end
            xmls[member] = read(pipeline(`unzip -p $workbook_path xl/workbook.xml`))
        end
    end
    return (; workbook_payloads = payloads, workbook_xml_payloads = xmls)
end

fixed_clock(value = "2026-08-08T11:59:59.900Z") =
    E.ClockSource(() -> E.ClockSample(value))

function sequence_clock(values)
    samples = E.ClockSample[E.ClockSample(value) for value in values]
    index = Ref(0)
    return E.ClockSource(
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

@testset "USBEAAfterRedefinitions2025AdapterV1" begin
    @testset "frozen source and prospective contract" begin
        bindings = A.validate_repository_bindings()
        @test bindings["envelope_file_sha256"] == A.ENVELOPE_FILE_SHA256
        @test bindings["profile_file_sha256"] == A.PROFILE_FILE_SHA256
        @test bindings["prospective_file_sha256"] == A.PROSPECTIVE_FILE_SHA256
        @test bindings["inventory_file_sha256"] == A.INVENTORY_FILE_SHA256
        profile = A.load_and_validate_profile()
        @test profile["current_status"] == "CANNOT_RUN_NO_NEW_PROSPECTIVE_BUNDLE"
        @test profile["required_profile_count"] == 6
        @test profile["excluded_other_slow_structural_profile_count"] == 27
        @test profile["excluded_other_profile_relabel_allowed"] === false
        @test Set(row["profile_id"] for row in profile["profiles"]) ==
            A.REQUIRED_PROFILE_IDS
        @test Set(row["member"] for row in profile["workbooks"]) ==
            A.REQUIRED_WORKBOOK_MEMBERS
        @test length(profile["archive_entries"]) == 12
        @test profile["source"]["requested_url"] == A.ARCHIVE_URL
        @test profile["source"]["archive_sha256"] == A.ARCHIVE_SHA256
        @test profile["source"]["archive_byte_count"] == A.ARCHIVE_BYTE_COUNT
        @test profile["policy_review"]["access_date"] == "2026-08-08"
        @test profile["policy_review"]["same_day_policy_authorization_claimed"] === false
        @test profile["policy_review"]["source_attribution"] ==
            "Source: U.S. Bureau of Economic Analysis"
        @test profile["policy_review"]["endorsement_claim"] == "NONE"
        for gate in (
                "origin_admissible",
                "source_inventory_mutation_allowed",
                "model_state_write_allowed",
                "empirical_forecast_allowed",
                "accuracy_evaluation_allowed",
                "promotion_eligible",
                "production_scoring_allowed",
            )
            @test profile[gate] === false
        end
        plan = A.dry_run_plan("bea-static-dry-run")
        @test plan.status == "CANNOT_RUN_NO_NEW_PROSPECTIVE_BUNDLE_DRY_RUN_ONLY"
        @test plan.network_request_count == 0
        @test plan.filesystem_write_count == 0
        @test plan.request_count_if_live == 1
        @test plan.profile_count == 6
        @test plan.excluded_other_profile_count == 27
        @test all(value === false for value in values(plan.gates))
        calls = Ref(0)
        dry = A.capture_after_redefinitions_with_fetcher(
            raw_root = "/not/inspected/on/dry/run",
            transaction_id = "bea-adapter-dry",
            actor = "nobody",
            terms_reviewed_local_date = "2026-08-08",
            execute_live = false,
            fetcher = (_...) -> (calls[] += 1),
        )
        @test dry isa E.CapturePlan
        @test calls[] == 0
        expect_envelope_error(
            () -> A.capture_after_redefinitions_with_fetcher(
                raw_root = "/not/used",
                transaction_id = "missing-fetcher",
                actor = "nobody",
                terms_reviewed_local_date = "2026-08-08",
                execute_live = true,
                fetcher = nothing,
            ),
            "required only for explicit live execution",
        )
        fetch_calls = Ref(0)
        unreachable_fetcher = (_...) -> (fetch_calls[] += 1)
        for (transaction_id, clock_source) in (
                (
                    "adapter-initial-clock-early",
                    fixed_clock("2026-08-05T23:59:59.999Z"),
                ),
                (
                    "adapter-post-journal-clock-late",
                    sequence_clock(
                        [
                            "2026-08-08T11:59:59.800Z",
                            "2026-09-01T00:00:00.000Z",
                        ]
                    ),
                ),
            )
            parent = mktempdir()
            try
                expect_envelope_error(
                    () -> A.capture_after_redefinitions_with_fetcher(
                        raw_root = realpath(parent),
                        transaction_id = transaction_id,
                        actor = "synthetic tester",
                        terms_reviewed_local_date = "2026-08-08",
                        execute_live = true,
                        fetcher = unreachable_fetcher,
                        clock_source = clock_source,
                    ),
                    "callback remains unreachable",
                )
                @test fetch_calls[] == 0
            finally
                make_writable(parent)
                rm(parent; recursive = true, force = true)
            end
        end
    end

    @testset "profile tamper refusal" begin
        cases = [
            (document -> (document["current_status"] = "READY"), "status"),
            (document -> (document["required_profile_count"] = 6.0), "must be an integer"),
            (
                document -> (document["excluded_other_slow_structural_profile_count"] = true),
                "must be an integer",
            ),
            (document -> (document["excluded_other_slow_structural_profile_count"] = 26), "excluded_count"),
            (document -> (document["excluded_other_profile_relabel_allowed"] = true), "relabel"),
            (document -> (document["origin_admissible"] = true), "origin_admissible"),
            (document -> (document["source"]["requested_url"] = replace(A.ARCHIVE_URL, "https" => "http")), "requested_url"),
            (document -> (document["source"]["archive_sha256"] = repeat("0", 64)), "archive_sha256"),
            (
                document -> (document["source"]["archive_byte_count"] = Float64(A.ARCHIVE_BYTE_COUNT)),
                "must be an integer",
            ),
            (document -> (document["source"]["terms_review_timezone"] = "America/New_York"), "terms_review_timezone"),
            (document -> (document["policy_review"]["page_content_sha256_status"] = "HASHED"), "page_content_sha256_status"),
            (document -> (document["policy_review"]["endorsement_claim"] = "IMPLIED"), "endorsement"),
            (document -> push!(document["profiles"], deepcopy(document["profiles"][1])), "duplicate ID"),
            (document -> (document["profiles"][1]["selector"] = "DRIFT"), "selector"),
            (document -> (document["profiles"][2]["member"] = "unknown.xlsx"), "unknown member"),
            (document -> empty!(document["workbooks"][1]["sheet_names"]), "required sheet absent"),
            (document -> (document["archive_entries"][1]["crc32"] = "00000000"), "crc"),
            (
                document -> (document["archive_entries"][1]["compression_method"] = 8.0),
                "must be an integer",
            ),
            (
                document -> (document["request_headers"][1]["sequence"] = false),
                "must be an integer",
            ),
            (
                document -> (document["workbooks"][1]["byte_count"] = true),
                "must be an integer",
            ),
        ]
        for (mutator, pattern) in cases
            with_profile_mutation(mutator) do path
                expect_adapter_error(() -> A.load_and_validate_profile(path), pattern)
            end
        end
    end

    @testset "real archive ZIP, selectors, CRC, member and OOXML evidence" begin
        archive_path = get(ENV, "BEA_AFTER_REDEFINITIONS_ARCHIVE", DEFAULT_ARCHIVE)
        if !isfile(archive_path)
            @test_skip "preserved exact archive is unavailable"
        else
            archive = read(archive_path)
            @test length(archive) == A.ARCHIVE_BYTE_COUNT
            @test bytes2hex(sha256(archive)) == A.ARCHIVE_SHA256
            selector = A.selector_receipt(archive)
            @test selector["status"] == "ALL_SIX_VALUATION_PROFILES_VERIFIED_NONADMITTING"
            @test selector["all_profiles_verified"] === true
            @test selector["profile_count"] == 6
            @test selector["archive_entry_count"] == 12
            @test selector["archive_zip_directory_valid"] === true
            @test selector["excluded_other_profile_count"] == 27
            @test selector["excluded_other_profile_relabel_allowed"] === false
            @test selector["independent_extracted_payload_verification_performed"] === false
            @test Set(row["profile_id"] for row in selector["profiles"]) ==
                A.REQUIRED_PROFILE_IDS
            @test all(row["verified"] === true for row in selector["profiles"])
            @test all(row["required_sheet_present"] === true for row in selector["profiles"])
            @test all(row["archive_zip_directory_valid"] === true for row in selector["profiles"])
            for row in selector["profiles"]
                if !isempty(row["member"])
                    @test occursin(r"^[0-9a-f]{64}$", row["member_sha256"])
                    @test occursin(r"^[0-9a-f]{8}$", row["member_crc32"])
                    @test occursin(r"^[0-9a-f]{64}$", row["workbook_xml_sha256"])
                    @test occursin(r"^[0-9a-f]{8}$", row["workbook_xml_crc32"])
                end
            end
            material = extracted_material(archive_path)
            extracted = A.validate_extracted_evidence(
                archive,
                material.workbook_payloads,
                material.workbook_xml_payloads,
            )
            @test Set(keys(extracted)) == A.REQUIRED_WORKBOOK_MEMBERS
            independent = A.selector_receipt(
                archive;
                workbook_payloads = material.workbook_payloads,
                workbook_xml_payloads = material.workbook_xml_payloads,
            )
            @test independent["independent_extracted_payload_verification_performed"] === true
            @test independent["all_profiles_verified"] === true
            @test independent["profile_count"] == 6
            parent = mktempdir()
            try
                root = realpath(parent)
                capture_calls = Ref(0)
                valid_fetcher = function (url, headers, _maximum_bytes, _timeout)
                    capture_calls[] += 1
                    return E.FetchResponse(
                        body = archive,
                        http_status = 200,
                        requested_url = url,
                        effective_url = url,
                        request_headers = headers,
                        response_headers = [
                            "Content-Type" => "application/x-zip-compressed",
                            "Content-Length" => string(length(archive)),
                        ],
                        response_headers_complete = true,
                        parsed_header_order_preserved = true,
                        raw_wire_headers_preserved = false,
                        redirect_chain = Tuple{Int, String, String}[],
                        request_started_at_utc = "2026-08-08T12:00:00.000Z",
                        response_headers_at_utc = "2026-08-08T12:00:00.100Z",
                        response_body_completed_at_utc = "2026-08-08T12:00:00.200Z",
                        proxy_used = false,
                        netrc_used = false,
                        cookies_used = false,
                        retry_count = 0,
                    )
                end
                captured = A.capture_after_redefinitions_with_fetcher(
                    raw_root = root,
                    transaction_id = "adapter-offline-injected-valid",
                    actor = "synthetic tester",
                    terms_reviewed_local_date = "2026-08-08",
                    execute_live = true,
                    fetcher = valid_fetcher,
                    clock_source = fixed_clock(),
                )
                @test capture_calls[] == 1
                @test captured.status == "VALIDATED_NONADMITTING_PROSPECTIVE_SNAPSHOT_BUNDLE"
                @test captured.selector["profile_count"] == 6
                @test captured.selector["excluded_other_profile_count"] == 27
                @test all(value === false for value in values(captured.gates))

                bundle = joinpath(root, "adapter-offline-injected-valid")
                receipt_path = joinpath(bundle, "receipt.toml")
                manifest_path = joinpath(bundle, "manifest.toml")
                original_receipt = read(receipt_path)
                original_manifest = read(manifest_path)
                for (mutator, pattern) in (
                        (
                            document -> (document["selector"]["profile_count"] = 6.0),
                            "profile_count: must be an integer",
                        ),
                        (
                            document ->
                            (document["selector"]["profiles"][1]["archive_entry_count"] = true),
                            "archive_entry_count: must be an integer",
                        ),
                    )
                    make_writable(bundle)
                    tampered_receipt = TOML.parse(String(copy(original_receipt)))
                    mutator(tampered_receipt)
                    tampered_receipt["artifact"]["receipt_sha256"] =
                        E._receipt_hash(tampered_receipt)
                    open(receipt_path, "w") do io
                        TOML.print(io, tampered_receipt; sorted = true)
                    end
                    tampered_manifest = TOML.parse(String(copy(original_manifest)))
                    tampered_manifest["receipt_sha256"] =
                        tampered_receipt["artifact"]["receipt_sha256"]
                    for record in tampered_manifest["files"]
                        if record["path"] == "receipt.toml"
                            bytes = read(receipt_path)
                            record["byte_count"] = length(bytes)
                            record["sha256"] = bytes2hex(sha256(bytes))
                        end
                    end
                    tampered_manifest["artifact"]["manifest_sha256"] =
                        E._manifest_hash(tampered_manifest)
                    open(manifest_path, "w") do io
                        TOML.print(io, tampered_manifest; sorted = true)
                    end
                    make_read_only(bundle)
                    expect_envelope_error(
                        () -> A.validate_capture_bundle(bundle),
                        pattern,
                    )
                    make_writable(bundle)
                    open(receipt_path, "w") do io
                        write(io, original_receipt)
                    end
                    open(manifest_path, "w") do io
                        write(io, original_manifest)
                    end
                    make_read_only(bundle)
                end
                @test A.validate_capture_bundle(bundle).selector["profile_count"] == 6

                invalid_fetcher = function (url, headers, maximum_bytes, timeout)
                    response = valid_fetcher(url, headers, maximum_bytes, timeout)
                    return E.FetchResponse(
                        body = response.body,
                        http_status = response.http_status,
                        requested_url = response.requested_url,
                        effective_url = response.effective_url,
                        request_headers = response.request_headers,
                        response_headers = ["Content-Type" => "text/plain"],
                        response_headers_complete = response.response_headers_complete,
                        parsed_header_order_preserved = response.parsed_header_order_preserved,
                        raw_wire_headers_preserved = response.raw_wire_headers_preserved,
                        redirect_chain = response.redirect_chain,
                        request_started_at_utc = response.request_started_at_utc,
                        response_headers_at_utc = response.response_headers_at_utc,
                        response_body_completed_at_utc = response.response_body_completed_at_utc,
                        proxy_used = response.proxy_used,
                        netrc_used = response.netrc_used,
                        cookies_used = response.cookies_used,
                        retry_count = response.retry_count,
                    )
                end
                expect_envelope_error(
                    () -> A.capture_after_redefinitions_with_fetcher(
                        raw_root = root,
                        transaction_id = "adapter-offline-injected-invalid",
                        actor = "synthetic tester",
                        terms_reviewed_local_date = "2026-08-08",
                        execute_live = true,
                        fetcher = invalid_fetcher,
                        clock_source = fixed_clock(),
                    ),
                    "media type is not allowed",
                )
                quarantine = A.validate_capture_quarantine(
                    joinpath(
                        root,
                        "adapter-offline-injected-invalid.quarantine",
                    )
                )
                @test quarantine.failure_code == "RESPONSE_VALIDATION_FAILED"
                @test quarantine.body_sha256 == A.ARCHIVE_SHA256
                @test quarantine.completion_receipt_created === false
                @test capture_calls[] == 2
            finally
                make_writable(parent)
                rm(parent; recursive = true, force = true)
            end
            changed = copy(archive)
            changed[100] = xor(changed[100], 0x01)
            expect_adapter_error(() -> A.selector_receipt(changed), "SHA-256")
            missing = copy(material.workbook_payloads)
            delete!(missing, first(keys(missing)))
            expect_adapter_error(
                () -> A.validate_extracted_evidence(
                    archive,
                    missing,
                    material.workbook_xml_payloads,
                ),
                "member set mismatch",
            )
            bad_payloads = copy(material.workbook_payloads)
            member = first(keys(bad_payloads))
            bad_payloads[member] = copy(bad_payloads[member])
            bad_payloads[member][1] = xor(bad_payloads[member][1], 0x01)
            expect_envelope_error(
                () -> A.validate_extracted_evidence(
                    archive,
                    bad_payloads,
                    material.workbook_xml_payloads,
                ),
                "CRC-32 mismatch",
            )
            bad_xmls = copy(material.workbook_xml_payloads)
            bad_xmls[member] = copy(bad_xmls[member])
            bad_xmls[member][1] = xor(bad_xmls[member][1], 0x01)
            expect_envelope_error(
                () -> A.validate_extracted_evidence(
                    archive,
                    material.workbook_payloads,
                    bad_xmls,
                ),
                "CRC-32 mismatch",
            )
        end
    end
end
