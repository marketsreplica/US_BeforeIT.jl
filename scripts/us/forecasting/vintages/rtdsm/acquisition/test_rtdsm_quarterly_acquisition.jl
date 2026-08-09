#!/usr/bin/env julia

using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "RTDSMQuarterlyAcquisition.jl"))
using .RTDSMQuarterlyAcquisition

const M = RTDSMQuarterlyAcquisition
const FIXED_START = DateTime(2026, 8, 7, 14, 0, 0)
const FIXED_END = DateTime(2026, 8, 7, 14, 1, 0)
const FIXED_REVIEW_DATE = Date(2026, 8, 7)
const FIXED_HTTP_DATE = "Fri, 07 Aug 2026 14:00:00 GMT"

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

function append_bytes!(bytes, values)
    append!(bytes, Vector{UInt8}(values))
    return bytes
end

function signature_position(bytes, signature)
    for position in 1:(length(bytes) - length(signature) + 1)
        bytes[position:(position + length(signature) - 1)] == signature &&
            return position
    end
    return nothing
end

function minimal_xlsx(marker::String; names = nothing, encrypted = false)
    entries = names === nothing ?
        [
            "[Content_Types].xml" => "<Types>$marker</Types>",
            "_rels/.rels" => "<Relationships>$marker</Relationships>",
            "xl/workbook.xml" => "<workbook>$marker</workbook>",
            "xl/worksheets/sheet1.xml" => "<sheet>$marker</sheet>",
        ] :
        [String(name) => "$marker-$index" for (index, name) in enumerate(names)]
    bytes = UInt8[]
    offsets = Int[]
    for (name, payload) in entries
        push!(offsets, length(bytes))
        name_bytes = Vector{UInt8}(codeunits(name))
        payload_bytes = Vector{UInt8}(codeunits(payload))
        append_bytes!(bytes, UInt8[0x50, 0x4b, 0x03, 0x04])
        push_u16!(bytes, 20)
        push_u16!(bytes, encrypted ? 1 : 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u16!(bytes, 0)
        push_u32!(bytes, 0)
        push_u32!(bytes, length(payload_bytes))
        push_u32!(bytes, length(payload_bytes))
        push_u16!(bytes, length(name_bytes))
        push_u16!(bytes, 0)
        append_bytes!(bytes, name_bytes)
        append_bytes!(bytes, payload_bytes)
    end
    central_offset = length(bytes)
    for ((name, payload), offset) in zip(entries, offsets)
        name_bytes = Vector{UInt8}(codeunits(name))
        payload_bytes = Vector{UInt8}(codeunits(payload))
        append_bytes!(bytes, UInt8[0x50, 0x4b, 0x01, 0x02])
        push_u16!(bytes, 20)
        push_u16!(bytes, 20)
        push_u16!(bytes, encrypted ? 1 : 0)
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
        append_bytes!(bytes, name_bytes)
    end
    central_size = length(bytes) - central_offset
    append_bytes!(bytes, UInt8[0x50, 0x4b, 0x05, 0x06])
    push_u16!(bytes, 0)
    push_u16!(bytes, 0)
    push_u16!(bytes, length(entries))
    push_u16!(bytes, length(entries))
    push_u32!(bytes, central_size)
    push_u32!(bytes, central_offset)
    push_u16!(bytes, 0)
    return bytes
end

function fetched_fixture(index; bytes = minimal_xlsx("series-$index"))
    expectation = M.PROFILE.series[index]
    return FetchedMatrix(
        bytes,
        200,
        M.EXPECTED_CONTENT_TYPE,
        string(length(bytes)),
        "NOT_PROVIDED",
        expectation.canonical_url,
        expectation.canonical_url,
        FIXED_HTTP_DATE,
        "\"fixture-$index\"",
        "Fri, 31 Jul 2026 00:00:00 GMT",
        FIXED_START + Second(4 * index),
        FIXED_START + Second(4 * index + 1),
        FIXED_START + Second(4 * index + 2),
    )
end

fetched_set() = FetchedMatrix[fetched_fixture(index) for index in 1:5]

function replace_fetched(
        fetched::FetchedMatrix;
        raw_bytes = fetched.raw_bytes,
        http_status = fetched.http_status,
        content_type = fetched.content_type,
        content_length = fetched.content_length,
        content_encoding = fetched.content_encoding,
        requested_url = fetched.requested_url,
        effective_url = fetched.effective_url,
        response_date = fetched.response_date,
        etag = fetched.etag,
        last_modified = fetched.last_modified,
        acquisition_started_at_utc = fetched.acquisition_started_at_utc,
        response_returned_at_utc = fetched.response_returned_at_utc,
        acquisition_completed_at_utc = fetched.acquisition_completed_at_utc,
    )
    return FetchedMatrix(
        raw_bytes,
        http_status,
        content_type,
        content_length,
        content_encoding,
        requested_url,
        effective_url,
        response_date,
        etag,
        last_modified,
        acquisition_started_at_utc,
        response_returned_at_utc,
        acquisition_completed_at_utc,
    )
end

function build_receipt(fetched = fetched_set(); start = FIXED_START, stop = FIXED_END)
    return M._build_receipt(
        fetched,
        M.PROFILE;
        terms_reviewed_local_date = FIXED_REVIEW_DATE,
        capture_local_date = FIXED_REVIEW_DATE,
        capture_started_at_utc = start,
        capture_completed_at_utc = stop,
    )
end

function reseal!(receipt)
    receipt["artifact"]["receipt_sha256"] = receipt_sha256(receipt)
    return receipt
end

function capture_fixture(
        root,
        fetched = fetched_set();
        start = FIXED_START,
        stop = FIXED_END,
        rename_exclusive = M._rename_exclusive,
    )
    return M._capture_from_fetched(
        fetched,
        root;
        live = true,
        terms_reviewed_local_date = FIXED_REVIEW_DATE,
        research_purpose_attestation = RESEARCH_PURPOSE_ATTESTATION,
        capture_started_at_utc = start,
        capture_completed_at_utc = stop,
        rename_exclusive = rename_exclusive,
    )
end

@testset "sealed authoritative profile" begin
    @test PROFILE_SHA256 ==
        "6eb3a722dc6cfed72f16782f6f065a85de1bc0a3b2c1b733695c6338db1b593c"
    @test bytes2hex(sha256(read(PROFILE_PATH))) == PROFILE_SHA256
    @test M.PROFILE.schema_version ==
        "beforeit-us-rtdsm-quarterly-source-profile.v1"
    @test M.PROFILE.expected_file_count == 5
    @test M.PROFILE.maximum_file_bytes == 10_000_000
    @test M.PROFILE.terms_timezone == "America/New_York"
    @test M.PROFILE.terms_url == M.TERMS_URL
    @test [value.series_id for value in M.PROFILE.series] ==
        ["NOUTPUT", "ROUTPUT", "P", "PCON", "PCONX"]
    @test [value.filename for value in M.PROFILE.series] ==
        [
        "NOUTPUTQvQd.xlsx",
        "ROUTPUTQvQd.xlsx",
        "PQvQd.xlsx",
        "pconQvQd.xlsx",
        "PCONXQvQd.xlsx",
    ]
    @test [value.forbidden_direct_mapping for value in M.PROFILE.series] ==
        [false, false, true, true, false]
    @test M.PROFILE.required_false_gates == M.REQUIRED_FALSE_GATES
    @test expectation_for("PCONX").sheet_name == "PCONX"
    @test_throws RTDSMAcquisitionError expectation_for("EMPLOY")
    mktempdir() do root
        root = realpath(root)
        copied = joinpath(root, "profile.json")
        write(copied, read(PROFILE_PATH))
        @test load_profile(copied).dataset_id == M.PROFILE.dataset_id
        write(copied, vcat(read(PROFILE_PATH), UInt8(' ')))
        @test_throws RTDSMAcquisitionError load_profile(copied)
        rm(copied)
        symlink(PROFILE_PATH, copied)
        @test_throws RTDSMAcquisitionError load_profile(copied)
    end
    @test_throws RTDSMAcquisitionError load_profile("relative.json")
    acquisition_source = read(
        joinpath(@__DIR__, "RTDSMQuarterlyAcquisition.jl"),
        String,
    )
    @test occursin("response_body = IOBuffer()", acquisition_source)
    @test !occursin("temporary_path, temporary_io = mktemp()", acquisition_source)
end

@testset "URL, rights, attestation, and timezone gates" begin
    for expectation in M.PROFILE.series
        @test validate_source_url(expectation.canonical_url, expectation) ==
            expectation.canonical_url
        for mutation in (
                expectation.canonical_url * "?hash=abc",
                replace(
                    expectation.canonical_url,
                    "https://" => "http://",
                ),
                replace(
                    expectation.canonical_url,
                    "www.philadelphiafed.org" => "evil.example",
                ),
                expectation.canonical_url * "#fragment",
            )
            @test_throws RTDSMAcquisitionError validate_source_url(
                mutation,
                expectation,
            )
        end
    end
    gates = research_gates()
    @test Set(keys(gates)) == M.GATE_KEYS
    @test gates["research_diagnostic_allowed"] === true
    @test all(
        gates[key] === false for key in
            setdiff(M.GATE_KEYS, Set(["research_diagnostic_allowed"]))
    )
    @test research_gates(research_diagnostic_allowed = false)[
        "research_diagnostic_allowed",
    ] === false
    @test_throws RTDSMAcquisitionError research_gates(
        research_diagnostic_allowed = 1,
    )
    @test new_york_local_date(DateTime(2026, 1, 1, 4, 59)) ==
        Date(2025, 12, 31)
    @test new_york_local_date(DateTime(2026, 1, 1, 5, 0)) ==
        Date(2026, 1, 1)
    @test new_york_local_date(DateTime(2026, 8, 7, 3, 59)) ==
        Date(2026, 8, 6)
    @test new_york_local_date(DateTime(2026, 8, 7, 4, 0)) ==
        Date(2026, 8, 7)
    @test M._validate_live_attestations(
        true,
        FIXED_REVIEW_DATE,
        RESEARCH_PURPOSE_ATTESTATION,
        FIXED_START,
    ) == (FIXED_REVIEW_DATE, FIXED_REVIEW_DATE)
    @test_throws RTDSMAcquisitionError M._validate_live_attestations(
        false,
        FIXED_REVIEW_DATE,
        RESEARCH_PURPOSE_ATTESTATION,
        FIXED_START,
    )
    @test_throws RTDSMAcquisitionError M._validate_live_attestations(
        true,
        FIXED_REVIEW_DATE - Day(1),
        RESEARCH_PURPOSE_ATTESTATION,
        FIXED_START,
    )
    @test_throws RTDSMAcquisitionError M._validate_live_attestations(
        true,
        FIXED_REVIEW_DATE,
        "yes",
        FIXED_START,
    )
end

@testset "ZIP/XLSX envelope and progress bounds" begin
    valid = minimal_xlsx("valid")
    result = M._validate_xlsx_zip(valid, "fixture")
    @test result.entry_count == 4
    @test result.required_entries_verified
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        valid[2:end],
        "fixture",
    )
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        valid[1:(end - 22)],
        "fixture",
    )
    missing = minimal_xlsx(
        "missing";
        names = ["[Content_Types].xml", "_rels/.rels", "xl/not-workbook.xml"],
    )
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        missing,
        "fixture",
    )
    duplicate = minimal_xlsx(
        "duplicate";
        names = [
            "[Content_Types].xml",
            "_rels/.rels",
            "xl/workbook.xml",
            "xl/workbook.xml",
        ],
    )
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        duplicate,
        "fixture",
    )
    encrypted = minimal_xlsx("encrypted"; encrypted = true)
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        encrypted,
        "fixture",
    )
    traversal = minimal_xlsx(
        "traversal";
        names = [
            "[Content_Types].xml",
            "_rels/.rels",
            "xl/workbook.xml",
            "../escape",
        ],
    )
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        traversal,
        "fixture",
    )
    multi_disk = copy(valid)
    eocd = signature_position(
        multi_disk,
        UInt8[0x50, 0x4b, 0x05, 0x06],
    )
    @test eocd !== nothing
    multi_disk[something(eocd) + 4] = 0x01
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        multi_disk,
        "fixture",
    )
    trailing = vcat(valid, UInt8[0x00])
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        trailing,
        "fixture",
    )
    bad_local_offset = copy(valid)
    central = signature_position(
        bad_local_offset,
        UInt8[0x50, 0x4b, 0x01, 0x02],
    )
    @test central !== nothing
    for offset in 42:45
        bad_local_offset[something(central) + offset] = 0xff
    end
    @test_throws RTDSMAcquisitionError M._validate_xlsx_zip(
        bad_local_offset,
        "fixture",
    )
    @test M._enforce_download_limit(0, 0, 0, 0) === nothing
    @test M._enforce_download_limit(10_000_000, 10_000_000, 0, 0) ===
        nothing
    for values in (
            (-1, 0, 0, 0),
            (10_000_001, 0, 0, 0),
            (0, 10_000_001, 0, 0),
            (0, 0, 1, 0),
            (0, 0, 0, 1),
            (1.0, 0, 0, 0),
        )
        @test_throws RTDSMAcquisitionError M._enforce_download_limit(
            values...,
        )
    end
end

@testset "complete fetched transaction validation" begin
    fetched = fetched_set()
    results = validate_fetched_set(fetched)
    @test length(results) == 5
    @test all(result.raw_byte_count > 0 for result in results)
    @test length(unique(result.raw_sha256 for result in results)) == 5
    digest = bundle_sha256(fetched)
    @test occursin(M.HASH_PATTERN, digest)
    @test digest == bundle_sha256(fetched)
    @test_throws RTDSMAcquisitionError validate_fetched_set(fetched[1:4])
    @test_throws RTDSMAcquisitionError validate_fetched_set(
        vcat(fetched, fetched[1:1]),
    )
    aliased = copy(fetched)
    aliased[2] = aliased[1]
    @test_throws RTDSMAcquisitionError validate_fetched_set(aliased)
    raw_aliased = copy(fetched)
    raw_aliased[2] = fetched_fixture(2; bytes = fetched[1].raw_bytes)
    @test_throws RTDSMAcquisitionError validate_fetched_set(raw_aliased)
    for (field, changed) in (
            :http_status => replace_fetched(fetched[1]; http_status = 206),
            :content_type =>
                replace_fetched(fetched[1]; content_type = "text/html"),
            :content_length => replace_fetched(
                fetched[1];
                content_length = string(length(fetched[1].raw_bytes) + 1),
            ),
            :content_encoding =>
                replace_fetched(fetched[1]; content_encoding = "gzip"),
            :requested_url => replace_fetched(
                fetched[1];
                requested_url = fetched[1].requested_url * "?hash=x",
            ),
            :effective_url => replace_fetched(
                fetched[1];
                effective_url = "https://evil.example/file.xlsx",
            ),
            :response_date => replace_fetched(
                fetched[1];
                response_date = "Thu, 07 Aug 2026 14:00:00 GMT",
            ),
            :timestamp_order => replace_fetched(
                fetched[1];
                response_returned_at_utc =
                    fetched[1].acquisition_started_at_utc - Second(1),
            ),
            :body => replace_fetched(fetched[1]; raw_bytes = UInt8[1, 2, 3]),
        )
        candidate = copy(fetched)
        candidate[1] = changed
        @test_throws RTDSMAcquisitionError validate_fetched_set(candidate)
    end
end

@testset "canonical receipt and research-only classification" begin
    fetched = fetched_set()
    receipt = build_receipt(fetched)
    validated = M._validate_receipt(receipt)
    @test validated.bundle_sha256 == bundle_sha256(fetched)
    @test validated.receipt_sha256 == receipt_sha256(receipt)
    @test validated.research_diagnostic_allowed
    @test !validated.ready
    @test receipt_file_sha256(receipt) ==
        bytes2hex(sha256(M._toml_bytes(receipt)))
    @test TOML.parse(String(M._toml_bytes(receipt))) == receipt
    @test length(receipt["matrices"]) == 5
    @test receipt["profile"]["profile_sha256"] == PROFILE_SHA256
    @test receipt["terms"]["research_use_only"] === true
    for key in (
            "redistribution_authorized",
            "raw_git_commit_authorized",
            "commercial_use_authorized",
            "logo_reuse_authorized",
            "model_training_authorized_by_contract",
            "fred_alfred_service_used",
        )
        @test receipt["terms"][key] === false
    end
    @test receipt["raw_bundle"]["raw_git_commit_authorized"] === false
    @test receipt["capture"]["historical_availability_evidence"] === false
    @test receipt["capture"]["intraday_availability_evidence"] === false
    @test receipt["gates"]["research_diagnostic_allowed"] === true
    @test all(
        receipt["gates"][key] === false for key in
            setdiff(M.GATE_KEYS, Set(["research_diagnostic_allowed"]))
    )
    tampered = deepcopy(receipt)
    tampered["gates"]["ready"] = true
    reseal!(tampered)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
    tampered = deepcopy(receipt)
    tampered["terms"]["model_training_authorized_by_contract"] = true
    reseal!(tampered)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
    tampered = deepcopy(receipt)
    tampered["matrices"][1]["effective_url"] *= "?redirected=1"
    reseal!(tampered)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
    tampered = deepcopy(receipt)
    tampered["artifact"]["receipt_sha256"] = repeat("0", 64)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
    tampered = deepcopy(receipt)
    tampered["artifact"]["receipt_id"] = "forged"
    reseal!(tampered)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
    tampered = deepcopy(receipt)
    tampered["matrices"][1]["etag"] = 1
    reseal!(tampered)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
    tampered = deepcopy(receipt)
    tampered["matrices"][2]["acquisition_started_at_utc"] =
        tampered["matrices"][1]["acquisition_started_at_utc"]
    reseal!(tampered)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
    tampered = deepcopy(receipt)
    first_hash = tampered["matrices"][1]["observed_raw_sha256"]
    tampered["matrices"][2]["observed_raw_sha256"] = first_hash
    tampered["matrices"][2]["stored_filename"] =
        M._raw_filename("ROUTPUT", first_hash)
    reseal!(tampered)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
    tampered = deepcopy(receipt)
    tampered["terms"]["terms_reviewed_local_date"] = "2026-08-06"
    reseal!(tampered)
    @test_throws RTDSMAcquisitionError M._validate_receipt(tampered)
end

@testset "atomic immutable receipt-specific storage" begin
    mktempdir() do root
        root = realpath(root)
        fetched = fetched_set()
        first = capture_fixture(root, fetched)
        @test isdir(first.bundle_path)
        @test isfile(first.receipt_path)
        @test first.bundle_sha256 == bundle_sha256(fetched)
        @test first.receipt_sha256 == receipt_sha256(build_receipt(fetched))
        @test validate_capture_bundle(first.bundle_path) == first
        @test stat(first.bundle_path).mode & 0o777 == 0o555
        @test length(readdir(first.bundle_path)) == 6
        for name in readdir(first.bundle_path)
            path = joinpath(first.bundle_path, name)
            @test !islink(path)
            @test stat(path).mode & 0o777 == 0o444
            @test stat(path).nlink == 1
        end
        second = capture_fixture(root, fetched)
        @test second.bundle_path == first.bundle_path
        @test second.receipt_file_sha256 == first.receipt_file_sha256
        later_fetched = FetchedMatrix[
            replace_fetched(
                    value;
                    acquisition_started_at_utc =
                    value.acquisition_started_at_utc + Minute(10),
                    response_returned_at_utc =
                    value.response_returned_at_utc + Minute(10),
                    acquisition_completed_at_utc =
                    value.acquisition_completed_at_utc + Minute(10),
                    response_date = "Fri, 07 Aug 2026 14:10:00 GMT",
                ) for value in fetched
        ]
        later = capture_fixture(
            root,
            later_fetched;
            start = FIXED_START + Minute(10),
            stop = FIXED_END + Minute(10),
        )
        @test later.bundle_sha256 == first.bundle_sha256
        @test later.receipt_sha256 != first.receipt_sha256
        @test dirname(later.bundle_path) == dirname(first.bundle_path)
        @test later.bundle_path != first.bundle_path
        @test validate_capture_bundle(later.bundle_path) == later
    end
end

@testset "tamper, aliases, and no-clobber races fail closed" begin
    mktempdir() do root
        root = realpath(root)
        result = capture_fixture(root)
        receipt = TOML.parsefile(result.receipt_path)
        raw_name = receipt["matrices"][1]["stored_filename"]
        raw_path = joinpath(result.bundle_path, raw_name)
        chmod(result.bundle_path, 0o755)
        chmod(raw_path, 0o644)
        original = read(raw_path)
        write(raw_path, vcat(original, UInt8(0)))
        chmod(raw_path, 0o444)
        chmod(result.bundle_path, 0o555)
        @test_throws RTDSMAcquisitionError validate_capture_bundle(
            result.bundle_path,
        )
        chmod(result.bundle_path, 0o755)
    end
    mktempdir() do root
        root = realpath(root)
        result = capture_fixture(root)
        receipt = TOML.parsefile(result.receipt_path)
        raw_path =
            joinpath(result.bundle_path, receipt["matrices"][1]["stored_filename"])
        alias_path = joinpath(root, "alias.xlsx")
        hardlink(raw_path, alias_path)
        @test stat(raw_path).nlink == 2
        @test_throws RTDSMAcquisitionError validate_capture_bundle(
            result.bundle_path,
        )
        chmod(result.bundle_path, 0o755)
    end
    mktempdir() do root
        root = realpath(root)
        result = capture_fixture(root)
        receipt = TOML.parsefile(result.receipt_path)
        raw_path =
            joinpath(result.bundle_path, receipt["matrices"][1]["stored_filename"])
        chmod(raw_path, 0o400)
        @test_throws RTDSMAcquisitionError validate_capture_bundle(
            result.bundle_path,
        )
        chmod(result.bundle_path, 0o755)
        chmod(raw_path, 0o444)
        chmod(result.bundle_path, 0o500)
        @test_throws RTDSMAcquisitionError validate_capture_bundle(
            result.bundle_path,
        )
        chmod(result.bundle_path, 0o755)
    end
    mktempdir() do root
        root = realpath(root)
        result = capture_fixture(root)
        chmod(result.bundle_path, 0o755)
        extra = joinpath(result.bundle_path, "extra")
        write(extra, "unexpected")
        chmod(extra, 0o444)
        chmod(result.bundle_path, 0o555)
        @test_throws RTDSMAcquisitionError validate_capture_bundle(
            result.bundle_path,
        )
        chmod(result.bundle_path, 0o755)
        chmod(extra, 0o644)
    end
    mktempdir() do root
        root = realpath(root)
        fetched = fetched_set()
        receipt = build_receipt(fetched)
        function exact_racing_rename(source, target)
            @test M._rename_exclusive(source, target)
            return false
        end
        result = M._install_bundle(
            root,
            fetched,
            receipt;
            rename_exclusive = exact_racing_rename,
        )
        @test validate_capture_bundle(result.bundle_path) == result
    end
    mktempdir() do root
        root = realpath(root)
        fetched = fetched_set()
        receipt = build_receipt(fetched)
        target_created = Ref("")
        function racing_rename(source, target)
            target_created[] = target
            mkpath(target)
            write(joinpath(target, "concurrent-marker"), "preserve")
            return false
        end
        @test_throws RTDSMAcquisitionError M._install_bundle(
            root,
            fetched,
            receipt;
            rename_exclusive = racing_rename,
        )
        @test read(joinpath(target_created[], "concurrent-marker"), String) ==
            "preserve"
        @test isempty(
            filter(
                name -> startswith(name, ".capture-staging-"),
                readdir(dirname(target_created[])),
            ),
        )
    end
    mktempdir() do root
        root = realpath(root)
        fetched = fetched_set()
        receipt = build_receipt(fetched)
        target_created = Ref("")
        function symlink_race(source, target)
            target_created[] = target
            symlink(root, target)
            return false
        end
        @test_throws RTDSMAcquisitionError M._install_bundle(
            root,
            fetched,
            receipt;
            rename_exclusive = symlink_race,
        )
        @test islink(target_created[])
    end
end

@testset "transaction and canonical raw-root refusal" begin
    @test_throws RTDSMAcquisitionError M._canonical_raw_root(@__DIR__)
    ignored_root = realpath(
        joinpath(M.REPOSITORY_ROOT, "data", "us", "raw"),
    )
    @test M._canonical_raw_root(ignored_root) == ignored_root
    mktempdir() do root
        root = realpath(root)
        invalid = fetched_set()
        invalid[5] = replace_fetched(invalid[5]; http_status = 500)
        @test_throws RTDSMAcquisitionError capture_fixture(root, invalid)
        @test isempty(readdir(root))
    end
    mktempdir() do root
        root = realpath(root)
        alias = joinpath(dirname(root), basename(root) * "-alias")
        symlink(root, alias)
        @test_throws RTDSMAcquisitionError capture_fixture(alias)
        rm(alias)
    end
    @test_throws RTDSMAcquisitionError capture_fixture("relative")
    mktempdir() do root
        root = realpath(root)
        @test_throws RTDSMAcquisitionError capture_research_snapshot(root)
        @test_throws RTDSMAcquisitionError capture_research_snapshot(
            root;
            live = true,
            terms_reviewed_local_date = FIXED_REVIEW_DATE,
            research_purpose_attestation = "wrong",
        )
        @test isempty(readdir(root))
        @test_throws RTDSMAcquisitionError M._capture_from_fetched(
            fetched_set(),
            root;
            live = false,
            terms_reviewed_local_date = FIXED_REVIEW_DATE,
            research_purpose_attestation = RESEARCH_PURPOSE_ATTESTATION,
            capture_started_at_utc = FIXED_START,
            capture_completed_at_utc = FIXED_END,
        )
        @test isempty(readdir(root))
        @test_throws RTDSMAcquisitionError M._capture_from_fetched(
            fetched_set(),
            root;
            live = true,
            terms_reviewed_local_date = FIXED_REVIEW_DATE,
            research_purpose_attestation = "wrong",
            capture_started_at_utc = FIXED_START,
            capture_completed_at_utc = FIXED_END,
        )
        @test isempty(readdir(root))
    end
end

include(joinpath(@__DIR__, "capture_rtdsm_quarterly.jl"))

@testset "opt-in CLI parser has no implicit live path" begin
    @test parse_cli(["--help"]) == Dict("help" => true)
    options = parse_cli(
        [
            "--live",
            "--raw-root",
            "/absolute/raw",
            "--terms-reviewed-local-date",
            "2026-08-07",
            "--research-purpose-attestation",
            RESEARCH_PURPOSE_ATTESTATION,
        ],
    )
    @test options["live"] === true
    @test options["--raw-root"] == "/absolute/raw"
    @test options["--terms-reviewed-local-date"] == "2026-08-07"
    @test options["--research-purpose-attestation"] ==
        RESEARCH_PURPOSE_ATTESTATION
    for arguments in (
            String[],
            ["--raw-root", "/absolute/raw"],
            ["--live"],
            ["--live", "--unknown"],
            ["--live", "--raw-root"],
            [
                "--live",
                "--live",
                "--raw-root",
                "/absolute/raw",
                "--terms-reviewed-local-date",
                "2026-08-07",
                "--research-purpose-attestation",
                RESEARCH_PURPOSE_ATTESTATION,
            ],
        )
        @test_throws ArgumentError parse_cli(arguments)
    end
    @test cli_main(["--help"]) == 0
    @test cli_main(String[]) == 2
end
