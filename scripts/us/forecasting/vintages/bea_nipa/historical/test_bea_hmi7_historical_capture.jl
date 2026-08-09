using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "BEAHMI7HistoricalCapture.jl"))
using .BEAHMI7HistoricalCapture

const INVENTORY_PATH =
    normpath(joinpath(@__DIR__, "..", "..", "current_inventory.toml"))
const PINNED_INVENTORY_SHA256 =
    "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"
const FIXED_DATE = Date(2026, 8, 7)
const CAPTURE_START = DateTime(2026, 8, 7, 1, 0, 0)
const SECTION1_START = DateTime(2026, 8, 7, 1, 0, 1)
const SECTION1_HEADERS = DateTime(2026, 8, 7, 1, 0, 2)
const SECTION1_COMPLETE = DateTime(2026, 8, 7, 1, 0, 3)
const SECTION2_START = DateTime(2026, 8, 7, 1, 0, 4)
const SECTION2_HEADERS = DateTime(2026, 8, 7, 1, 0, 5)
const SECTION2_COMPLETE = DateTime(2026, 8, 7, 1, 0, 6)
const CAPTURE_COMPLETE = DateTime(2026, 8, 7, 1, 0, 7)
const FIXTURE_SECTION1 = vcat(
    UInt8[0x50, 0x4b, 0x03, 0x04],
    Vector{UInt8}(codeunits("synthetic-section-one")),
)
const FIXTURE_SECTION2 = vcat(
    UInt8[0x50, 0x4b, 0x03, 0x04],
    Vector{UInt8}(codeunits("synthetic-section-two")),
)

sha(bytes) = bytes2hex(SHA.sha256(bytes))

function fixture_expectation()
    archive = "Files/Releases/GDP_and_PI/2030/Q1/Advance_April-30-2030"
    prefix = "https://apps.bea.gov/HistData/$archive/"
    return CaptureExpectation(
        "bea_hmi7_synthetic_contract_fixture",
        "2030Q1",
        "advance",
        "999999",
        archive,
        "BEA TEST-00",
        "https://www.bea.gov/news/2030/synthetic-contract-fixture",
        "2030-04-29T12:30:00.000Z",
        "SYNTHETIC_FIXTURE_NO_SOURCE_SEMANTICS",
        (
            WorkbookExpectation(
                "1",
                "Section1all_xls.xlsx",
                prefix * "Section1all_xls.xlsx",
                sha(FIXTURE_SECTION1),
                length(FIXTURE_SECTION1),
                "\"0abc:0\"",
                "Fri, 31 Jan 2020 14:41:20 GMT",
            ),
            WorkbookExpectation(
                "2",
                "Section2all_xls.xlsx",
                prefix * "Section2all_xls.xlsx",
                sha(FIXTURE_SECTION2),
                length(FIXTURE_SECTION2),
                "\"0def:0\"",
                "Fri, 30 Jul 2021 13:32:50 GMT",
            ),
        ),
    )
end

function fixture_fetched(expectation = fixture_expectation())
    timestamps = (
        (SECTION1_START, SECTION1_HEADERS, SECTION1_COMPLETE),
        (SECTION2_START, SECTION2_HEADERS, SECTION2_COMPLETE),
    )
    bytes = (FIXTURE_SECTION1, FIXTURE_SECTION2)
    return FetchedWorkbook[
        FetchedWorkbook(
                copy(bytes[index]),
                200,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                string(length(bytes[index])),
                workbook.source_url,
                workbook.source_url,
                "Fri, 07 Aug 2026 01:00:0$(index) GMT",
                workbook.expected_etag,
                workbook.expected_last_modified,
                timestamps[index]...,
            )
            for (index, workbook) in enumerate(expectation.workbooks)
    ]
end

function replace_fetched(fetched; kwargs...)
    replacements = Dict{Symbol, Any}(kwargs)
    return FetchedWorkbook(
        (
            get(replacements, name, getfield(fetched, name)) for
                name in fieldnames(FetchedWorkbook)
        )...,
    )
end

function replace_expectation(expectation; kwargs...)
    replacements = Dict{Symbol, Any}(kwargs)
    return CaptureExpectation(
        (
            get(replacements, name, getfield(expectation, name)) for
                name in fieldnames(CaptureExpectation)
        )...,
    )
end

function capture_fixture(raw_root; expectation = fixture_expectation(), fetched = nothing)
    responses = fetched === nothing ? fixture_fetched(expectation) : fetched
    return BEAHMI7HistoricalCapture._capture_from_fetched(
        expectation,
        responses,
        raw_root;
        live = true,
        terms_reviewed_local_date = FIXED_DATE,
        capture_local_date = FIXED_DATE,
        capture_started_at_utc = CAPTURE_START,
        capture_completed_at_utc = CAPTURE_COMPLETE,
    )
end

function make_writable(path)
    isdir(path) ? chmod(path, 0o755) : chmod(path, 0o644)
    return path
end

function rewrite_receipt(path, mutate)
    document = TOML.parsefile(path)
    mutate(document)
    document["artifact"]["receipt_sha256"] = repeat("0", 64)
    document["artifact"]["receipt_sha256"] = receipt_sha256(document)
    bytes = BEAHMI7HistoricalCapture._toml_bytes(document)
    make_writable(path)
    open(path, "w") do io
        write(io, bytes)
    end
    chmod(path, 0o444)
    return document
end

@testset "sealed identities and evidence boundary" begin
    @test length(EXPECTATIONS) == 2
    @test Set(
        expectation_for(id).capture_id for id in keys(
                Dict(expectation.capture_id => true for expectation in EXPECTATIONS),
            )
    ) == Set(expectation.capture_id for expectation in EXPECTATIONS)
    @test_throws BEAHMI7HistoricalCaptureError expectation_for("other")

    first, second = EXPECTATIONS
    @test first.archive_directory_id == "13075"
    @test first.reference_period == "2019Q4"
    @test first.release_number == "BEA 20-04"
    @test first.release_page_url ==
        "https://www.bea.gov/news/2020/gross-domestic-product-fourth-quarter-and-year-2019-advance-estimate"
    @test first.release_event_timestamp_utc ==
        "2020-01-30T13:30:00.000Z"
    @test first.archive_relative_path ==
        "Files/Releases/GDP_and_PI/2019/Q4/Advance_January-31-2020"
    @test first.workbooks[1].expected_raw_sha256 ==
        "35b170c5c82980a0dfea5cb6db45f2851fc3a3e4dfbbb37773ec71f23b44501a"
    @test first.workbooks[1].expected_byte_count == 3_743_559
    @test first.workbooks[2].expected_raw_sha256 ==
        "8f3935eb2ae44fea9066cdac632f38b858cfbd74731756db2461123726fb6028"
    @test first.workbooks[2].expected_byte_count == 1_759_752
    @test all(
        workbook.expected_etag == "\"028598044d8d51:0\"" for
            workbook in first.workbooks
    )
    @test all(
        workbook.expected_last_modified ==
            "Fri, 31 Jan 2020 14:41:20 GMT" for
            workbook in first.workbooks
    )

    @test second.archive_directory_id == "13091"
    @test second.reference_period == "2021Q2"
    @test second.release_number == "BEA 21-36"
    @test second.release_page_url ==
        "https://www.bea.gov/news/2021/gross-domestic-product-second-quarter-2021-advance-estimate-and-annual-update"
    @test second.release_event_timestamp_utc ==
        "2021-07-29T12:30:00.000Z"
    @test second.archive_relative_path ==
        "Files/Releases/GDP_and_PI/2021/Q2/Advance_July-30-2021"
    @test occursin("ANNUAL_UPDATE", second.annual_update_caveat)
    @test second.workbooks[1].expected_raw_sha256 ==
        "ccc7a5cf63de4022613404d05bcb2a0a1689875d5c45bcc5f3386ae09eec9ffb"
    @test second.workbooks[1].expected_byte_count == 3_816_200
    @test second.workbooks[2].expected_raw_sha256 ==
        "84dff5de137cd3043e0392798875c1bb80a9190c4bddfdb76f495163cdf1ff9a"
    @test second.workbooks[2].expected_byte_count == 1_784_998
    @test all(
        workbook.expected_etag == "\"06d24644785d71:0\"" for
            workbook in second.workbooks
    )
    @test all(
        workbook.expected_last_modified ==
            "Fri, 30 Jul 2021 13:32:50 GMT" for
            workbook in second.workbooks
    )
    @test all(
        startswith(workbook.source_url, "https://apps.bea.gov/HistData/") for
            expectation in EXPECTATIONS for workbook in expectation.workbooks
    )
end

@testset "complete-pair byte and header validation" begin
    @test isnothing(
        BEAHMI7HistoricalCapture._enforce_download_limit(
            25_000_000,
            25_000_000,
            0,
            0,
        ),
    )
    @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._enforce_download_limit(
        25_000_001,
        0,
        0,
        0,
    )
    @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._enforce_download_limit(
        0,
        25_000_001,
        0,
        0,
    )
    @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._enforce_download_limit(
        0,
        0,
        1,
        0,
    )
    expectation = fixture_expectation()
    fetched = fixture_fetched(expectation)
    validated = validate_fetched_pair(fetched, expectation)
    @test length(validated) == 2
    @test validated[1].raw_sha256 == sha(FIXTURE_SECTION1)
    @test validated[2].raw_sha256 == sha(FIXTURE_SECTION2)
    @test pair_sha256(fetched, expectation) ==
        pair_sha256(deepcopy(fetched), expectation)

    @test_throws BEAHMI7HistoricalCaptureError validate_fetched_pair(
        fetched[1:1],
        expectation,
    )
    @test_throws BEAHMI7HistoricalCaptureError validate_fetched_pair(
        [fetched[1], fetched[1]],
        expectation,
    )
    @test_throws BEAHMI7HistoricalCaptureError validate_fetched_pair(
        reverse(fetched),
        expectation,
    )

    tampered_bytes = copy(fetched[1].raw_bytes)
    tampered_bytes[end] = xor(tampered_bytes[end], 0x01)
    @test_throws BEAHMI7HistoricalCaptureError validate_fetched_pair(
        [replace_fetched(fetched[1]; raw_bytes = tampered_bytes), fetched[2]],
        expectation,
    )
    @test_throws BEAHMI7HistoricalCaptureError validate_fetched_pair(
        [
            replace_fetched(
                fetched[1];
                raw_bytes = fetched[1].raw_bytes[1:(end - 1)],
                content_length = string(length(fetched[1].raw_bytes) - 1),
            ),
            fetched[2],
        ],
        expectation,
    )
    bad_magic = copy(fetched[1].raw_bytes)
    bad_magic[1] = 0x00
    bad_magic_expectation = replace_expectation(
        expectation;
        workbooks = (
            WorkbookExpectation(
                "1",
                expectation.workbooks[1].filename,
                expectation.workbooks[1].source_url,
                sha(bad_magic),
                length(bad_magic),
                expectation.workbooks[1].expected_etag,
                expectation.workbooks[1].expected_last_modified,
            ),
            expectation.workbooks[2],
        ),
    )
    @test_throws BEAHMI7HistoricalCaptureError validate_fetched_pair(
        [
            replace_fetched(
                fetched[1];
                raw_bytes = bad_magic,
            ),
            fetched[2],
        ],
        bad_magic_expectation,
    )
    for changed in (
            replace_fetched(fetched[1]; http_status = 206),
            replace_fetched(fetched[1]; content_type = "text/html"),
            replace_fetched(fetched[1]; content_length = "999"),
            replace_fetched(fetched[1]; effective_url = fetched[1].effective_url * "?x=1"),
            replace_fetched(fetched[1]; etag = "\"different:0\""),
            replace_fetched(fetched[1]; last_modified = "NOT_PROVIDED"),
            replace_fetched(fetched[1]; response_date = "NOT_PROVIDED"),
            replace_fetched(
                fetched[1];
                response_date = "Mon, 99 Abc 9999 99:99:99 GMT",
            ),
            replace_fetched(
                fetched[1];
                response_date = "Mon, 07 Aug 2026 01:00:01 GMT",
            ),
            replace_fetched(
                fetched[1];
                response_date = "Fri, 07 Aug 2020 01:00:01 GMT",
            ),
            replace_fetched(
                fetched[1];
                response_returned_at_utc =
                    SECTION1_START - Millisecond(1),
            ),
            replace_fetched(
                fetched[1];
                acquisition_completed_at_utc =
                    SECTION1_HEADERS - Millisecond(1),
            ),
        )
        @test_throws BEAHMI7HistoricalCaptureError validate_fetched_pair(
            [changed, fetched[2]],
            expectation,
        )
    end

    aliased_workbooks = (
        expectation.workbooks[1],
        WorkbookExpectation(
            "2",
            "Section2all_xls.xlsx",
            expectation.workbooks[2].source_url,
            expectation.workbooks[1].expected_raw_sha256,
            expectation.workbooks[1].expected_byte_count,
            expectation.workbooks[2].expected_etag,
            expectation.workbooks[2].expected_last_modified,
        ),
    )
    @test_throws BEAHMI7HistoricalCaptureError validate_fetched_pair(
        fetched,
        replace_expectation(expectation; workbooks = aliased_workbooks),
    )
end

@testset "exclusive atomic rename never replaces a racing target" begin
    mktempdir() do temporary
        directory = realpath(temporary)
        source = joinpath(directory, "source")
        target = joinpath(directory, "target")
        mkdir(source)
        open(joinpath(source, "source-only"), "w") do io
            write(io, "source")
        end
        mkdir(target)
        @test !BEAHMI7HistoricalCapture._rename_exclusive(source, target)
        @test read(joinpath(source, "source-only"), String) == "source"
        @test isdir(target)
        @test isempty(readdir(target))
        @test !ispath(joinpath(target, "source-only"))
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        source = joinpath(directory, "source")
        target = joinpath(directory, "target")
        outside = joinpath(directory, "outside")
        mkdir(source)
        mkdir(outside)
        symlink(outside, target)
        outside_mode = stat(outside).mode
        @test !BEAHMI7HistoricalCapture._rename_exclusive(source, target)
        @test isdir(source)
        @test islink(target)
        @test stat(outside).mode == outside_mode
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        source = joinpath(directory, "source")
        target = joinpath(directory, "target")
        mkdir(source)
        open(joinpath(source, "payload"), "w") do io
            write(io, "payload")
        end
        chmod(source, 0o555)
        @test BEAHMI7HistoricalCapture._rename_exclusive(source, target)
        @test !ispath(source)
        @test stat(target).mode & 0o222 == 0
        @test read(joinpath(target, "payload"), String) == "payload"
        chmod(target, 0o755)
    end
end

@testset "atomic content-addressed install and immutable receipt" begin
    inventory_before = read(INVENTORY_PATH)
    @test sha(inventory_before) == PINNED_INVENTORY_SHA256
    mktempdir() do temporary
        directory = realpath(temporary)
        raw_root = joinpath(directory, "raw")
        result = capture_fixture(raw_root)

        @test isdir(result.bundle_path)
        @test !islink(result.bundle_path)
        @test basename(result.bundle_path) ==
            "receipt-self-sha256-$(result.receipt_sha256)"
        @test basename(dirname(result.bundle_path)) ==
            "pair-sha256-$(result.pair_sha256)"
        @test basename(result.receipt_path) ==
            "receipt-self-sha256-$(result.receipt_sha256).toml"
        @test sha(read(result.receipt_path)) ==
            result.receipt_file_sha256
        @test stat(result.bundle_path).mode & 0o222 == 0
        @test stat(result.receipt_path).mode & 0o222 == 0
        @test sort(readdir(result.bundle_path)) ==
            sort(
            vcat(
                [
                    BEAHMI7HistoricalCapture._raw_filename(workbook) for
                        workbook in fixture_expectation().workbooks
                ],
                [basename(result.receipt_path)],
            ),
        )
        @test !result.historical_first_state_verified
        @test !result.historical_availability_verified
        @test !result.origin_admissible
        @test !result.empirical_execution_allowed
        @test !result.inventory_mutation_authorized
        @test !result.production_authorized
        @test !result.ready

        receipt = TOML.parsefile(result.receipt_path)
        @test receipt_sha256(receipt) == result.receipt_sha256
        @test receipt_file_sha256(receipt) ==
            result.receipt_file_sha256
        @test receipt["capture_scope"]["archive_directory_id"] == "999999"
        @test receipt["capture_scope"]["archive_relative_path"] ==
            "Files/Releases/GDP_and_PI/2030/Q1/Advance_April-30-2030"
        @test occursin(
            "/getPath/999999",
            receipt["capture_scope"]["resolved_path_locator"],
        )
        @test receipt["capture_scope"]["directory_id_locator"] ==
            "https://apps.bea.gov/histdata/core/data/UrlPath_getID/" *
            "?UrlPath=%2FInetpub%2Fwwwroot%2Fwebsite%2Fwebsite%2FHistData" *
            "%2FFiles%2FReleases%2FGDP_and_PI%5C2030%5CQ1%5C" *
            "Advance_April-30-2030"
        @test receipt["release_event"]["release_event_timestamp_utc"] ==
            "2030-04-29T12:30:00.000Z"
        @test !receipt["release_event"]["release_event_is_workbook_snapshot"]
        boundary = receipt["workbook_snapshot_boundary"]
        @test boundary["monthly_table_snapshot_is_next_calendar_day"]
        @test !boundary["exact_release_time_capture"]
        @test boundary["historical_first_state_status"] ==
            "UNKNOWN_NOT_ESTABLISHED"
        @test boundary["historical_availability_status"] ==
            "UNKNOWN_NOT_ESTABLISHED"
        @test !boundary["archive_label_date_is_availability_evidence"]
        @test !boundary[
            "current_http_headers_are_historical_availability_evidence",
        ]
        @test receipt["terms"]["terms_locator"] ==
            "https://www.bea.gov/index.php/help/faq/145"
        @test receipt["terms"]["terms_reviewed_local_date"] == "2026-08-07"
        @test receipt["terms"]["source_attribution"] ==
            "Source: U.S. Bureau of Economic Analysis"
        @test !receipt["terms"]["bea_logo_reuse_authorized"]
        @test !receipt["terms"][
            "redistribution_authorized_by_capture_contract",
        ]
        @test all(value === false for value in values(receipt["gates"]))

        repeated = capture_fixture(raw_root)
        @test repeated.bundle_path == result.bundle_path
        @test repeated.receipt_path == result.receipt_path
        @test repeated.receipt_sha256 == result.receipt_sha256
        @test_throws BEAHMI7HistoricalCaptureError validate_capture_bundle(
            result.bundle_path,
        )
        validated = BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
        @test validated.pair_sha256 == result.pair_sha256
    end
    @test read(INVENTORY_PATH) == inventory_before
    @test sha(read(INVENTORY_PATH)) == PINNED_INVENTORY_SHA256
end

@testset "unchanged bytes preserve distinct capture evidence" begin
    mktempdir() do temporary
        directory = realpath(temporary)
        raw_root = joinpath(directory, "raw")
        expectation = fixture_expectation()
        first = capture_fixture(
            raw_root;
            expectation,
            fetched = fixture_fetched(expectation),
        )
        shifted = FetchedWorkbook[
            replace_fetched(
                    fetched;
                    response_date =
                    "Sat, 08 Aug 2026 01:00:0$(index) GMT",
                    acquisition_started_at_utc =
                    fetched.acquisition_started_at_utc + Day(1),
                    response_returned_at_utc =
                    fetched.response_returned_at_utc + Day(1),
                    acquisition_completed_at_utc =
                    fetched.acquisition_completed_at_utc + Day(1),
                )
                for (index, fetched) in
                enumerate(fixture_fetched(expectation))
        ]
        second = BEAHMI7HistoricalCapture._capture_from_fetched(
            expectation,
            shifted,
            raw_root;
            live = true,
            terms_reviewed_local_date = FIXED_DATE + Day(1),
            capture_local_date = FIXED_DATE + Day(1),
            capture_started_at_utc = CAPTURE_START + Day(1),
            capture_completed_at_utc = CAPTURE_COMPLETE + Day(1),
        )

        @test first.pair_sha256 == second.pair_sha256
        @test first.receipt_sha256 != second.receipt_sha256
        @test first.bundle_path != second.bundle_path
        @test dirname(first.bundle_path) == dirname(second.bundle_path)
        @test isdir(first.bundle_path)
        @test isdir(second.bundle_path)
        @test BEAHMI7HistoricalCapture._validate_capture_bundle(
            first.bundle_path,
            expectation,
        ).receipt_sha256 == first.receipt_sha256
        @test BEAHMI7HistoricalCapture._validate_capture_bundle(
            second.bundle_path,
            expectation,
        ).receipt_sha256 == second.receipt_sha256
    end
end

@testset "receipt resealing cannot promote or rewrite evidence" begin
    for mutation in (
            document ->
            (document["gates"]["origin_admissible"] = true),
            document ->
            (document["gates"]["historical_first_state_verified"] = true),
            document ->
            (document["gates"]["historical_availability_verified"] = true),
            document ->
            (document["gates"]["empirical_execution_allowed"] = true),
            document ->
            (document["gates"]["inventory_mutation_authorized"] = true),
            document ->
            (document["gates"]["production_authorized"] = true),
            document -> (document["gates"]["ready"] = true),
            document -> (
                document["workbook_snapshot_boundary"][
                    "exact_release_time_capture",
                ] = true
            ),
            document -> (
                document["release_event"][
                    "release_event_is_workbook_snapshot",
                ] = true
            ),
            document -> (
                document["terms"]["bea_logo_reuse_authorized"] = true
            ),
            document -> (
                document["workbooks"][1]["source_url"] =
                    "https://apps.bea.gov/HistData/wrong.xlsx"
            ),
            document -> (
                document["capture_scope"]["archive_directory_id"] = "1"
            ),
            document -> (
                document["workbook_snapshot_boundary"][
                    "historical_first_state_status",
                ] = "VERIFIED"
            ),
        )
        mktempdir() do temporary
            result = capture_fixture(joinpath(realpath(temporary), "raw"))
            rewrite_receipt(result.receipt_path, mutation)
            @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
                result.bundle_path,
                fixture_expectation(),
            )
        end
    end
end

@testset "filesystem aliases, unexpected files, and tampering fail closed" begin
    inventory_before = read(INVENTORY_PATH)
    mktempdir() do temporary
        directory = realpath(temporary)
        real_raw = joinpath(directory, "real-raw")
        mkdir(real_raw)
        symlink(real_raw, joinpath(directory, "raw-alias"))
        @test_throws BEAHMI7HistoricalCaptureError capture_fixture(
            joinpath(directory, "raw-alias"),
        )
        @test_throws BEAHMI7HistoricalCaptureError capture_fixture(
            joinpath(directory, "a", "..", "raw"),
        )
        @test_throws BEAHMI7HistoricalCaptureError capture_fixture(
            "relative/raw",
        )
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        result = capture_fixture(joinpath(directory, "raw"))
        make_writable(result.bundle_path)
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
        chmod(result.bundle_path, 0o555)
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        result = capture_fixture(joinpath(directory, "raw"))
        make_writable(result.receipt_path)
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
        chmod(result.receipt_path, 0o444)
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        result = capture_fixture(joinpath(directory, "raw"))
        raw_name = BEAHMI7HistoricalCapture._raw_filename(
            fixture_expectation().workbooks[1],
        )
        raw_path = joinpath(result.bundle_path, raw_name)
        make_writable(raw_path)
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
        chmod(raw_path, 0o444)
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        result = capture_fixture(joinpath(directory, "raw"))
        canonical = read(result.receipt_path)
        make_writable(result.receipt_path)
        open(result.receipt_path, "w") do io
            write(io, UInt8('\n'))
            write(io, canonical)
        end
        chmod(result.receipt_path, 0o444)
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        result = capture_fixture(joinpath(directory, "raw"))
        raw_name = BEAHMI7HistoricalCapture._raw_filename(
            fixture_expectation().workbooks[1],
        )
        raw_path = joinpath(result.bundle_path, raw_name)
        make_writable(result.bundle_path)
        make_writable(raw_path)
        outside = joinpath(directory, "outside-hardlink.xlsx")
        hardlink(raw_path, outside)
        chmod(raw_path, 0o444)
        chmod(result.bundle_path, 0o555)
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        result = capture_fixture(joinpath(directory, "raw"))
        make_writable(result.bundle_path)
        open(joinpath(result.bundle_path, "unexpected.txt"), "w") do io
            write(io, "unexpected")
        end
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        result = capture_fixture(joinpath(directory, "raw"))
        raw_name = BEAHMI7HistoricalCapture._raw_filename(
            fixture_expectation().workbooks[1],
        )
        raw_path = joinpath(result.bundle_path, raw_name)
        make_writable(raw_path)
        bytes = read(raw_path)
        bytes[end] = xor(bytes[end], 0x01)
        open(raw_path, "w") do io
            write(io, bytes)
        end
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        result = capture_fixture(joinpath(directory, "raw"))
        raw_name = BEAHMI7HistoricalCapture._raw_filename(
            fixture_expectation().workbooks[1],
        )
        raw_path = joinpath(result.bundle_path, raw_name)
        outside = joinpath(directory, "outside.xlsx")
        open(outside, "w") do io
            write(io, FIXTURE_SECTION1)
        end
        make_writable(result.bundle_path)
        make_writable(raw_path)
        rm(raw_path)
        symlink(outside, raw_path)
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._validate_capture_bundle(
            result.bundle_path,
            fixture_expectation(),
        )
    end

    mktempdir() do temporary
        directory = realpath(temporary)
        raw_root = joinpath(directory, "raw")
        expectation = fixture_expectation()
        fetched = fixture_fetched(expectation)
        pair_digest = pair_sha256(fetched, expectation)
        receipt = BEAHMI7HistoricalCapture._build_receipt(
            expectation,
            fetched;
            capture_started_at_utc = CAPTURE_START,
            capture_completed_at_utc = CAPTURE_COMPLETE,
            capture_local_date = FIXED_DATE,
            terms_reviewed_local_date = FIXED_DATE,
        )
        receipt_digest = receipt["artifact"]["receipt_sha256"]
        target = joinpath(
            raw_root,
            "bea_nipa",
            "hmi7",
            "historical",
            "captures",
            "pair-sha256-$pair_digest",
            "receipt-self-sha256-$receipt_digest",
        )
        mkpath(target)
        open(joinpath(target, "partial.xlsx"), "w") do io
            write(io, FIXTURE_SECTION1)
        end
        @test_throws BEAHMI7HistoricalCaptureError capture_fixture(raw_root)
    end
    @test read(INVENTORY_PATH) == inventory_before
end

@testset "clock and explicit-live gates" begin
    @test BEAHMI7HistoricalCapture._require_same_host_local_date(
        FIXED_DATE,
        FIXED_DATE,
    ) == FIXED_DATE
    @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._require_same_host_local_date(
        FIXED_DATE,
        FIXED_DATE + Day(1),
    )
    expectation = fixture_expectation()
    fetched = fixture_fetched(expectation)
    mktempdir() do temporary
        raw_root = joinpath(realpath(temporary), "raw")
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._capture_from_fetched(
            expectation,
            fetched,
            raw_root;
            live = false,
            terms_reviewed_local_date = FIXED_DATE,
            capture_local_date = FIXED_DATE,
            capture_started_at_utc = CAPTURE_START,
            capture_completed_at_utc = CAPTURE_COMPLETE,
        )
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._capture_from_fetched(
            expectation,
            fetched,
            raw_root;
            live = true,
            terms_reviewed_local_date = FIXED_DATE - Day(1),
            capture_local_date = FIXED_DATE,
            capture_started_at_utc = CAPTURE_START,
            capture_completed_at_utc = CAPTURE_COMPLETE,
        )
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._capture_from_fetched(
            expectation,
            fetched,
            raw_root;
            live = true,
            terms_reviewed_local_date = FIXED_DATE,
            capture_local_date = FIXED_DATE,
            capture_started_at_utc = CAPTURE_COMPLETE,
            capture_completed_at_utc = CAPTURE_START,
        )
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._capture_from_fetched(
            expectation,
            fetched,
            raw_root;
            live = true,
            terms_reviewed_local_date = FIXED_DATE,
            capture_local_date = FIXED_DATE,
            capture_started_at_utc = SECTION1_START + Millisecond(1),
            capture_completed_at_utc = CAPTURE_COMPLETE,
        )
        @test_throws BEAHMI7HistoricalCaptureError BEAHMI7HistoricalCapture._capture_from_fetched(
            expectation,
            fetched,
            raw_root;
            live = true,
            terms_reviewed_local_date = FIXED_DATE,
            capture_local_date = FIXED_DATE,
            capture_started_at_utc = CAPTURE_START,
            capture_completed_at_utc = SECTION2_COMPLETE - Millisecond(1),
        )
    end
end
