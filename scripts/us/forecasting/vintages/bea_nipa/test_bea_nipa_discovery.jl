using Dates
using JSON
using SHA
using TOML
using Test

include(
    normpath(
        joinpath(
            @__DIR__,
            "..",
            "..",
            "targets",
            "USTier1TargetCoverage.jl",
        ),
    ),
)
include(joinpath(@__DIR__, "BEANIPADiscovery.jl"))
using .USTier1TargetCoverage
using .BEANIPADiscovery

const FIXTURE_DIR = joinpath(@__DIR__, "fixtures")
const RELEASE_PATH =
    INTERNAL_RELEASE_ROOT * "\\2007\\Q1\\1. Advance_April-27-2007"
const PRE_2003_RELEASE_PATH =
    INTERNAL_RELEASE_ROOT * "\\2002\\Q2\\3. Final_September-27-2002"

fixture(name) = read(joinpath(FIXTURE_DIR, name), String)

function error_message(function_to_run)
    error = try
        function_to_run()
        nothing
    catch caught
        caught
    end
    @test error isa BEADiscoveryError
    return sprint(showerror, error)
end

@testset "BEA HMI7 discovery fixture integrity" begin
    manifest = TOML.parsefile(joinpath(FIXTURE_DIR, "fixture_manifest.toml"))
    artifact = manifest["artifact"]
    @test artifact["status"] == "HERMETIC_DISCOVERY_METADATA_ONLY"
    @test !artifact["raw_release_workbooks_included"]
    @test !artifact["availability_evidence_included"]
    @test !artifact["origin_admission_evidence_included"]

    entries = manifest["fixtures"]
    @test length(entries) == 5
    @test length(unique(entry["path"] for entry in entries)) == 5
    for entry in entries
        path = joinpath(FIXTURE_DIR, entry["path"])
        @test isfile(path)
        @test bytes2hex(sha256(read(path))) == entry["sha256"]
        @test entry["fixture_kind"] ==
            "normalized_official_response_subset"
        @test !entry["source_response_persisted"]
        @test !entry["release_workbook_bytes"]
    end
end

@testset "Release-directory discovery is structural, not temporal evidence" begin
    releases =
        discover_release_directories(fixture("release_directories_subset.json"))
    @test length(releases) == 7
    @test all(
        release ->
        release.internal_path !=
            RELEASE_PATH * "\\UND",
        releases,
    )
    @test count(
        release ->
        release.reference_year == 2002 &&
            release.reference_quarter == 2,
        releases,
    ) == 1
    @test count(
        release ->
        release.reference_year == 2002 &&
            release.reference_quarter == 3,
        releases,
    ) == 3

    advance = only(
        filter(release -> release.internal_path == RELEASE_PATH, releases),
    )
    @test advance.reference_year == 2007
    @test advance.reference_quarter == 1
    @test advance.archive_label == "1. Advance_April-27-2007"
    @test advance.archive_label_date_text == "April-27-2007"
    @test advance.archive_label_date == Date(2007, 4, 27)

    parsed = JSON.parse(fixture("release_directories_subset.json"))
    parsed["MainName"] = "Not BEA NIPA"
    @test occursin(
        "expected \"National Accounts (NIPA)\"",
        error_message(() -> discover_release_directories(parsed)),
    )

    parsed = JSON.parse(fixture("release_directories_subset.json"))
    parsed["FolderPattern"] = "different"
    @test occursin(
        "FolderPattern",
        error_message(() -> discover_release_directories(parsed)),
    )

    parsed = JSON.parse(fixture("release_directories_subset.json"))
    push!(parsed["FileArray"], RELEASE_PATH)
    @test occursin(
        "duplicates release path",
        error_message(() -> discover_release_directories(parsed)),
    )

    parsed = JSON.parse(fixture("release_directories_subset.json"))
    push!(
        parsed["FileArray"],
        INTERNAL_RELEASE_ROOT * "\\2007\\Q1\\arbitrary",
    )
    push!(
        parsed["FileArray"],
        INTERNAL_RELEASE_ROOT * "\\2007\\Q1\\Custom_April-27-2007",
    )
    @test length(discover_release_directories(parsed)) == 7
end

@testset "Directory response parsing is shape-only; live flow reverse-checks" begin
    directory_id =
        parse_directory_id(fixture("directory_id_2007q1_advance.json"))
    @test directory_id == "12921"
    resolved_path = parse_resolved_path(
        fixture("resolved_path_2007q1_advance.json"),
        directory_id,
    )
    @test resolved_path == RELEASE_PATH

    id_document = JSON.parse(fixture("directory_id_2007q1_advance.json"))
    id_document[1]["Theid"] = "arbitrary"
    @test occursin(
        "decimal digits",
        error_message(() -> parse_directory_id(id_document)),
    )

    path_document =
        JSON.parse(fixture("resolved_path_2007q1_advance.json"))
    path_document[1]["Thepath"] = "https://example.com"
    @test occursin(
        "not an HMI7 release directory",
        error_message(() -> parse_resolved_path(path_document, directory_id)),
    )
end

@testset "File discovery identifies section workbooks without acquiring them" begin
    workbooks = discover_release_workbooks(
        fixture("release_files_2007q1_advance.json"),
        RELEASE_PATH,
    )
    @test length(workbooks) == 13
    @test count(
        workbook -> workbook.publication_variant == "published_main",
        workbooks,
    ) == 8
    @test count(
        workbook -> workbook.publication_variant == "unadjusted",
        workbooks,
    ) == 5
    @test Set(
        workbook.section_id for workbook in workbooks if
            workbook.publication_variant == "published_main"
    ) == Set(string.(1:8))

    section1 = only(
        filter(
            workbook ->
            workbook.section_id == "1" &&
                workbook.publication_variant == "published_main",
            workbooks,
        ),
    )
    @test section1.filename == "Section1ALL_xls.xls"
    @test section1.official_locator ==
        "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/" *
        "2007/Q1/1.%20Advance_April-27-2007/Section1ALL_xls.xls"
    @test official_file_url(
        RELEASE_PATH * "\\Section 1 (copy).xls",
    ) == "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/" *
        "2007/Q1/1.%20Advance_April-27-2007/" *
        "Section%201%20%28copy%29.xls"
    @test occursin(
        "outside the official HMI7 release root",
        error_message(() -> official_file_url("/tmp/file.xls")),
    )
    @test occursin(
        "dot path segment",
        error_message(
            () -> official_file_url(RELEASE_PATH * "\\..\\escape.xls"),
        ),
    )
    @test occursin(
        "dot path segment",
        error_message(
            () -> official_file_url(RELEASE_PATH * "\\.\\escape.xls"),
        ),
    )
    @test occursin(
        "canonical HMI7 separator",
        error_message(
            () -> official_file_url(RELEASE_PATH * "/escape.xls"),
        ),
    )

    duplicate_document =
        JSON.parse(fixture("release_files_2007q1_advance.json"))
    push!(
        duplicate_document["Filearray3"],
        RELEASE_PATH * "\\section1all_xls.xlsx",
    )
    @test occursin(
        "duplicates section 1 published_main workbook",
        error_message(
            () -> discover_release_workbooks(
                duplicate_document,
                RELEASE_PATH,
            ),
        ),
    )
end

@testset "Pre-2003 workbook catalog does not inherit current sections" begin
    releases =
        discover_release_directories(fixture("release_directories_subset.json"))
    release = only(
        filter(
            item -> item.internal_path == PRE_2003_RELEASE_PATH,
            releases,
        ),
    )
    workbooks = discover_release_workbooks(
        fixture("release_files_2002q2_final.json"),
        PRE_2003_RELEASE_PATH,
    )
    @test length(workbooks) == 9
    @test all(
        workbook -> workbook.publication_variant == "published_main",
        workbooks,
    )
    @test Set(workbook.section_id for workbook in workbooks) ==
        Set(["1", "3", "4", "5", "6", "7", "8", "9", "S"])
    @test any(workbook -> workbook.section_id == "7", workbooks)
    @test any(workbook -> workbook.section_id == "S", workbooks)
    @test all(workbook -> workbook.section_id != "2", workbooks)

    catalog = build_tier1_catalog(
        release,
        "12829",
        PRE_2003_RELEASE_PATH,
        workbooks;
        directory_path_reverse_checked = false,
    )
    @test length(catalog.main_workbooks) == 9
    @test length(catalog.target_discoveries) == 5
    @test all(
        target ->
        target.historical_workbook_section_status ==
            "UNRESOLVED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION",
        catalog.target_discoveries,
    )

    section7_only =
        filter(workbook -> workbook.section_id == "7", workbooks)
    sparse_catalog = build_tier1_catalog(
        release,
        "12829",
        PRE_2003_RELEASE_PATH,
        section7_only,
    )
    @test length(sparse_catalog.main_workbooks) == 1
    @test only(sparse_catalog.main_workbooks).section_id == "7"
    @test length(sparse_catalog.target_discoveries) == 5
    @test all(
        target ->
        target.protocol_current_expected_hmi7_workbook_section in
            ("1", "2"),
        sparse_catalog.target_discoveries,
    )
    @test !sparse_catalog.origin_admissible
    @test !sparse_catalog.ready
end

@testset "Five target discoveries remain separate and fail-closed" begin
    mapping_contract = TOML.parsefile(
        joinpath(
            @__DIR__,
            "protocol_to_hmi7_workbook_mapping.toml",
        ),
    )
    @test mapping_contract["artifact"]["contract_id"] ==
        TIER1_MAPPING_CONTRACT_VERSION
    @test !mapping_contract["artifact"][
        "protocol_current_section_reuse_across_vintages_allowed",
    ]
    @test !mapping_contract["artifact"][
        "protocol_current_line_reuse_across_vintages_allowed",
    ]
    @test !mapping_contract["artifact"][
        "historical_workbook_section_mapping_verified",
    ]
    @test !mapping_contract["artifact"]["historical_row_mapping_verified"]

    target_contract_path = normpath(
        joinpath(
            @__DIR__,
            mapping_contract["artifact"][
                "target_coverage_contract_locator",
            ],
        ),
    )
    @test target_contract_path ==
        normpath(
        joinpath(
            @__DIR__,
            "..",
            "..",
            "targets",
            "tier1_targets.toml",
        ),
    )
    target_contract = TOML.parsefile(target_contract_path)
    target_validation =
        USTier1TargetCoverage.validate_inventory(target_contract)
    computed_target_sha =
        USTier1TargetCoverage.computed_content_sha256(target_contract)
    @test target_validation.sha256 == computed_target_sha
    @test mapping_contract["artifact"][
        "target_coverage_contract_content_sha256",
    ] == computed_target_sha
    expected_mapping = Set(
        (
                row.target_id,
                row.protocol_current_source_table_id,
                string(row.protocol_current_source_line_number),
                row.protocol_current_source_series_code,
                row.protocol_current_expected_hmi7_workbook_section,
            ) for row in tier1_table_map()
    )
    installed_mapping = Set(
        (
                target["target_id"],
                target["source_table_id"],
                target["source_line_number"],
                target["source_series_code"],
                split(target["source_table"], '.')[1][end:end],
            ) for target in target_contract["targets"] if
            target["target_id"] in Set(row[1] for row in expected_mapping)
    )
    @test length(installed_mapping) == 5
    @test installed_mapping == expected_mapping

    releases =
        discover_release_directories(fixture("release_directories_subset.json"))
    release =
        only(filter(item -> item.internal_path == RELEASE_PATH, releases))
    directory_id =
        parse_directory_id(fixture("directory_id_2007q1_advance.json"))
    resolved_path = parse_resolved_path(
        fixture("resolved_path_2007q1_advance.json"),
        directory_id,
    )
    workbooks = discover_release_workbooks(
        fixture("release_files_2007q1_advance.json"),
        resolved_path,
    )
    locally_unbound_catalog =
        build_tier1_catalog(release, directory_id, resolved_path, workbooks)
    @test !locally_unbound_catalog.directory_path_reverse_checked
    @test all(
        target -> !target.directory_path_reverse_checked,
        locally_unbound_catalog.target_discoveries,
    )
    catalog = build_tier1_catalog(
        release,
        directory_id,
        resolved_path,
        workbooks;
        directory_path_reverse_checked = true,
    )

    @test catalog isa Tier1DiscoveryCatalog
    @test length(catalog.target_discoveries) == 5
    @test length(catalog.main_workbooks) == 8
    @test Set(
        workbook.section_id for workbook in catalog.main_workbooks
    ) == Set(string.(1:8))
    @test Set(target.target_id for target in catalog.target_discoveries) == Set(
        [
            "core_pce_price_index",
            "gdp_deflator",
            "nominal_gdp",
            "pce_price_index",
            "real_gdp",
        ],
    )
    @test all(
        target ->
        target.mapping_contract_version ==
            TIER1_MAPPING_CONTRACT_VERSION,
        catalog.target_discoveries,
    )
    @test Set(
        target.protocol_current_source_observation_id for
            target in catalog.target_discoveries
    ) == Set(
        ["T10105:1", "T10106:1", "T10109:1", "T20304:1", "T20304:25"],
    )
    @test Set(
        target.protocol_current_expected_hmi7_workbook_section for
            target in catalog.target_discoveries
    ) == Set(["1", "2"])
    @test all(
        target -> target.archive_directory_id == "12921",
        catalog.target_discoveries,
    )
    @test catalog.directory_path_reverse_checked
    @test all(
        target -> target.directory_path_reverse_checked,
        catalog.target_discoveries,
    )
    @test all(
        target ->
        target.discovery_scope ==
            "official_archive_locator_metadata_only",
        catalog.target_discoveries,
    )
    @test all(
        target -> target.release_bytes_status == "NOT_ACQUIRED",
        catalog.target_discoveries,
    )
    @test all(
        target -> target.workbook_contents_status == "NOT_VERIFIED",
        catalog.target_discoveries,
    )
    @test all(
        target ->
        target.historical_workbook_section_status ==
            "UNRESOLVED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION",
        catalog.target_discoveries,
    )
    @test all(
        target ->
        target.historical_row_mapping_status ==
            "UNVERIFIED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION",
        catalog.target_discoveries,
    )
    @test all(
        target -> target.exact_availability_status == "NOT_VERIFIED",
        catalog.target_discoveries,
    )
    @test !catalog.origin_admissible
    @test !catalog.ready
    @test all(
        target -> !target.origin_admissible,
        catalog.target_discoveries,
    )
    @test all(target -> !target.ready, catalog.target_discoveries)
    core_pce = only(
        filter(
            target -> target.target_id == "core_pce_price_index",
            catalog.target_discoveries,
        ),
    )
    @test core_pce.protocol_current_source_observation_id == "T20304:25"
    @test core_pce.protocol_current_expected_hmi7_workbook_section == "2"
    @test core_pce.historical_workbook_section_status ==
        "UNRESOLVED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION"
    @test core_pce.historical_row_mapping_status ==
        "UNVERIFIED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION"
    @test :workbook_internal_path ∉ fieldnames(Tier1TargetDiscovery)
    @test :workbook_official_locator ∉ fieldnames(Tier1TargetDiscovery)
    @test :historical_workbook_section ∉ fieldnames(Tier1TargetDiscovery)
    forged_external = ReleaseWorkbook(
        "/tmp/not-bea.xls",
        "https://example.com/not-bea.xls",
        "not-bea.xls",
        "1",
        "published_main",
    )
    @test occursin(
        "is not a child of the resolved release path",
        error_message(
            () -> build_tier1_catalog(
                release,
                directory_id,
                resolved_path,
                [forged_external],
            ),
        ),
    )
    section1 = only(
        filter(
            workbook ->
            workbook.section_id == "1" &&
                workbook.publication_variant == "published_main",
            workbooks,
        ),
    )
    forged_section = ReleaseWorkbook(
        section1.internal_path,
        section1.official_locator,
        section1.filename,
        "7",
        section1.publication_variant,
    )
    @test occursin(
        "fields do not match the parsed official workbook path",
        error_message(
            () -> build_tier1_catalog(
                release,
                directory_id,
                resolved_path,
                [forged_section],
            ),
        ),
    )
    @test occursin(
        "does not equal the requested release path",
        error_message(
            () -> build_tier1_catalog(
                release,
                directory_id,
                INTERNAL_RELEASE_ROOT *
                    "\\2007\\Q1\\2. Preliminary_May-31-2007",
                workbooks,
                ;
                directory_path_reverse_checked = true,
            ),
        ),
    )
end

@testset "Live URLs are exact but no network call is part of this suite" begin
    @test directory_id_url(RELEASE_PATH) ==
        "https://apps.bea.gov/histdata/core/data/UrlPath_getID/" *
        "?UrlPath=%2FInetpub%2Fwwwroot%2Fwebsite%2Fwebsite%2FHistData" *
        "%2FFiles%2FReleases%2FGDP_and_PI%5C2007%5CQ1%5C1.%20" *
        "Advance_April-27-2007"
    @test resolved_path_url("12921") ==
        "https://apps.bea.gov/histdata/core/data/getPath/12921"
    @test release_files_url(RELEASE_PATH) ==
        "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/" *
        "?HistMainId=7&thePath=%2FInetpub%2Fwwwroot%2Fwebsite%2Fwebsite" *
        "%2FHistData%2FFiles%2FReleases%2FGDP_and_PI%5C2007%5CQ1%5C1." *
        "%20Advance_April-27-2007&getFiles=true&getDirs=false"
    for locator in (
            ROOT_DISCOVERY_URL,
            directory_id_url(RELEASE_PATH),
            resolved_path_url("12921"),
            release_files_url(RELEASE_PATH),
        )
        @test validate_effective_uri(locator) == locator
    end
    @test occursin(
        "must use HTTPS",
        error_message(
            () -> validate_effective_uri(
                "http://apps.bea.gov/histdata/",
            ),
        ),
    )
    for locator in (
            "https://example.com/histdata/",
            "https://apps.bea.gov.example.com/histdata/",
        )
        @test occursin(
            "exact apps.bea.gov host",
            error_message(() -> validate_effective_uri(locator)),
        )
    end
    @test occursin(
        "user information",
        error_message(
            () -> validate_effective_uri(
                "https://user@apps.bea.gov/histdata/",
            ),
        ),
    )
    @test occursin(
        "default HTTPS port",
        error_message(
            () -> validate_effective_uri(
                "https://apps.bea.gov:444/histdata/",
            ),
        ),
    )
    @test occursin(
        "fragment",
        error_message(
            () -> validate_effective_uri(
                "https://apps.bea.gov/histdata/#fragment",
            ),
        ),
    )
end
