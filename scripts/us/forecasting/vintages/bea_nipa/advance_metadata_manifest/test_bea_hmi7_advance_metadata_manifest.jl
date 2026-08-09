using SHA
using Test
using TOML

include(joinpath(@__DIR__, "BEAHMI7AdvanceMetadataManifest.jl"))
using .BEAHMI7AdvanceMetadataManifest

const MANIFEST_PATH = DEFAULT_MANIFEST_PATH
const MODULE_PATH =
    joinpath(@__DIR__, "BEAHMI7AdvanceMetadataManifest.jl")

function captured_error(callback)
    return try
        callback()
        nothing
    catch error
        error
    end
end

function restamp_content_sha256!(manifest)
    manifest["artifact"]["content_sha256"] =
        computed_content_sha256(manifest)
    return manifest
end

function check_invalid(
        original,
        mutator,
        message_fragment;
        restamp = true,
    )
    candidate = deepcopy(original)
    mutator(candidate)
    restamp && restamp_content_sha256!(candidate)
    error = captured_error() do
        validate_manifest(candidate)
    end
    @test error isa MetadataManifestError
    @test occursin(message_fragment, sprint(showerror, error))
    return error
end

@testset "sealed BEA HMI7 40-release metadata manifest" begin
    source_before = read(MANIFEST_PATH)
    artifact = manifest_artifact()
    releases = artifact.releases

    @test artifact.content_sha256 == EXPECTED_CONTENT_SHA256
    @test artifact.content_sha256 ==
        computed_content_sha256(TOML.parsefile(MANIFEST_PATH))
    @test artifact.file_sha256 == bytes2hex(sha256(source_before))
    @test artifact.file_byte_count == length(source_before)
    @test artifact.canonical_content isa String
    @test length(artifact.canonical_content) > 40_000
    @test length(releases) == 40
    @test releases isa Tuple
    @test [row.sequence for row in releases] == collect(1:40)
    @test first(releases).reference_period == "2011Q3"
    @test last(releases).reference_period == "2021Q2"

    @test artifact.contract.metadata_only === true
    for key in (
            :network_access_allowed,
            :workbook_bytes_acquired,
            :pdf_bytes_acquired,
        )
        @test getproperty(artifact.contract, key) === false
    end
    @test all(value -> value === false, values(artifact.gates))
    @test all(row -> row.strict_origin_available === false, releases)
    @test all(
        row ->
        row.availability_status ==
            "HISTORICAL_EXACT_WORKBOOK_BYTE_AVAILABILITY_NOT_PROVEN",
        releases,
    )
    @test read(MANIFEST_PATH) == source_before
end

@testset "exact inventory boundaries and exceptions" begin
    manifest = load_manifest()
    by_reference =
        Dict(row.reference_period => row for row in manifest.releases)

    @test count(
        row -> row.workbook_extension == "xls",
        manifest.releases,
    ) == 24
    @test count(
        row -> row.workbook_extension == "xlsx",
        manifest.releases,
    ) == 16
    @test by_reference["2017Q2"].section1_filename ==
        "Section1all_xls.xls"
    @test by_reference["2017Q2"].section2_filename ==
        "Section2all_xls.xls"
    @test by_reference["2017Q3"].section1_filename ==
        "Section1all_xls.xlsx"
    @test by_reference["2017Q3"].section2_filename ==
        "Section2all_xls.xlsx"

    lower_case_path = by_reference["2014Q3"].archive_path
    @test occursin("\\2014\\q3\\", lower_case_path)
    @test !occursin("\\2014\\Q3\\", lower_case_path)
    @test by_reference["2014Q3"].directory_id == "13013"

    shutdown_delay = by_reference["2013Q3"]
    @test shutdown_delay.event_timestamp_local ==
        "2013-11-07T08:30:00-05:00"
    @test shutdown_delay.event_timestamp_utc ==
        "2013-11-07T13:30:00Z"
    @test shutdown_delay.event_timezone_abbreviation == "EST"
    @test shutdown_delay.irregular_flag == "shutdown_delayed"

    shutdown_initial = by_reference["2018Q4"]
    @test shutdown_initial.estimate_family == "initial"
    @test shutdown_initial.archive_label == "Initial_March-1-2019"
    @test shutdown_initial.event_timestamp_local ==
        "2019-02-28T08:30:00-05:00"
    @test shutdown_initial.irregular_flag ==
        "shutdown_initial_replaces_advance_and_second"

    @test count(
        row -> row.folder_lag_days > 0,
        manifest.releases,
    ) == 15
    @test maximum(row.folder_lag_days for row in manifest.releases) == 4
    @test by_reference["2017Q4"].folder_lag_days == 3
    @test by_reference["2019Q4"].folder_lag_days == 1
    @test by_reference["2021Q2"].folder_lag_days == 1

    @test count(
        row ->
        row.update_type in
            ("annual_revision", "annual_update"),
        manifest.releases,
    ) == 8
    @test count(
        row ->
        row.update_type in
            ("comprehensive_revision", "comprehensive_update"),
        manifest.releases,
    ) == 2
    @test by_reference["2013Q2"].update_type ==
        "comprehensive_revision"
    @test by_reference["2018Q2"].update_type ==
        "comprehensive_update"
end

@testset "validated return does not alias mutable TOML input" begin
    input = TOML.parsefile(MANIFEST_PATH)
    validated = validate_manifest(input)
    @test !(:manifest in propertynames(validated))
    @test validated.releases isa Tuple
    @test validated.releases[1] isa NamedTuple

    input["releases"][1]["directory_id"] = "99999"
    input["contract"]["metadata_only"] = false
    input["gates"]["ready"] = true

    @test validated.releases[1].directory_id == "12977"
    @test validated.contract.metadata_only === true
    @test validated.gates.ready === false
    @test validated.content_sha256 == EXPECTED_CONTENT_SHA256
    @test_throws MethodError setindex!(
        validated.releases,
        validated.releases[2],
        1,
    )
    @test_throws ErrorException setproperty!(
        validated.releases[1],
        :directory_id,
        "99999",
    )
end

@testset "deterministic typed canonicalization" begin
    original = TOML.parsefile(MANIFEST_PATH)
    expected = computed_content_sha256(original)

    reordered =
        Dict(reverse(collect(pairs(deepcopy(original)))))
    @test computed_content_sha256(reordered) == expected

    with_comment =
        TOML.parse("# non-semantic comment\n" * read(MANIFEST_PATH, String))
    @test computed_content_sha256(with_comment) == expected

    different_declared_hash = deepcopy(original)
    different_declared_hash["artifact"]["content_sha256"] = repeat("0", 64)
    @test computed_content_sha256(different_declared_hash) == expected

    reversed_rows = deepcopy(original)
    reverse!(reversed_rows["releases"])
    @test computed_content_sha256(reversed_rows) != expected

    typed_change = deepcopy(original)
    typed_change["releases"][1]["sequence"] = true
    @test computed_content_sha256(typed_change) != expected
end

@testset "fail-closed schema and sealed-content pin" begin
    original = TOML.parsefile(MANIFEST_PATH)

    check_invalid(
        original,
        manifest -> (manifest["unknown"] = true),
        "unknown keys",
    )
    check_invalid(
        original,
        manifest -> delete!(manifest, "gates"),
        "missing keys",
    )
    check_invalid(
        original,
        manifest -> pop!(manifest["releases"]),
        "exactly 40 rows",
    )
    check_invalid(
        original,
        manifest -> (manifest["releases"][1]["sequence"] = 2),
        "manifest.releases[1].sequence",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][2]["reference_period"] = "2011Q3"
        ),
        "manifest.releases[2].reference_period",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][2]["directory_id"] =
                manifest["releases"][1]["directory_id"]
        ),
        "directory_id values must be unique",
    )

    plausible_exact_row_change = deepcopy(original)
    plausible_exact_row_change["releases"][1]["directory_id"] = "99999"
    restamp_content_sha256!(plausible_exact_row_change)
    pin_error = captured_error() do
        validate_manifest(plausible_exact_row_change)
    end
    @test pin_error isa MetadataManifestError
    @test occursin(
        "compiled sealed-contract pin",
        sprint(showerror, pin_error),
    )

    wrong_declared_hash = deepcopy(original)
    wrong_declared_hash["artifact"]["content_sha256"] = repeat("0", 64)
    hash_error = captured_error() do
        validate_manifest(wrong_declared_hash)
    end
    @test hash_error isa MetadataManifestError
    @test occursin("does not match computed", sprint(showerror, hash_error))
end

@testset "fail-closed archive identity and event chronology" begin
    original = TOML.parsefile(MANIFEST_PATH)

    check_invalid(
        original,
        manifest -> (
            manifest["releases"][13]["archive_path"] = replace(
                manifest["releases"][13]["archive_path"],
                "\\q3\\" => "\\Q3\\",
            )
        ),
        "exact year/quarter path case",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["archive_label"] =
                "Advance_October-28-2011"
        ),
        "does not equal the date encoded",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["event_timestamp_local"] =
                "2011-10-27T08:30:00-05:00"
        ),
        "America/New_York rules",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["event_timestamp_utc"] =
                "2011-10-27T13:30:00Z"
        ),
        "offset-normalized",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["event_timezone_iana"] = "UTC"
        ),
        "event_timezone_iana",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["event_timezone_abbreviation"] = "EST"
        ),
        "event_timezone_abbreviation",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["bea_release_number"] = "12-52"
        ),
        "event year",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["event_page_url"] =
                "https://example.com/news/2011/release"
        ),
        "exact official prefix",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["event_pdf_url"] =
                "https://www.bea.gov/sites/default/files/release.txt"
        ),
        "identify a PDF",
    )
    check_invalid(
        original,
        manifest -> (manifest["releases"][26]["folder_lag_days"] = 0),
        "folder_lag_days",
    )
end

@testset "fail-closed workbook, update, and irregular classifications" begin
    original = TOML.parsefile(MANIFEST_PATH)

    check_invalid(
        original,
        manifest -> (
            manifest["releases"][24]["workbook_extension"] = "xlsx";
            manifest["releases"][24]["section1_filename"] =
                "Section1all_xls.xlsx";
            manifest["releases"][24]["section2_filename"] =
                "Section2all_xls.xlsx"
        ),
        "workbook_extension",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][25]["section1_filename"] =
                "Section01all_xls.xlsx"
        ),
        "section1_filename",
    )
    check_invalid(
        original,
        manifest -> (manifest["releases"][4]["update_type"] = "none"),
        "update_type",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][9]["irregular_flag"] = "none"
        ),
        "irregular_flag",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][30]["irregular_evidence_url"] = "none"
        ),
        "irregular_evidence_url",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][30]["estimate_family"] = "advance"
        ),
        "estimate_family",
    )
end

@testset "all admission and execution gates are irreversible by drift" begin
    original = TOML.parsefile(MANIFEST_PATH)
    for key in keys(original["gates"])
        check_invalid(
            original,
            manifest -> (manifest["gates"][key] = true),
            "manifest.gates.$key",
        )
    end
    check_invalid(
        original,
        manifest -> (
            manifest["releases"][1]["strict_origin_available"] = true
        ),
        "strict_origin_available",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["contract"]["network_access_allowed"] = true
        ),
        "network_access_allowed",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["contract"]["workbook_bytes_acquired"] = true
        ),
        "workbook_bytes_acquired",
    )
    check_invalid(
        original,
        manifest -> (manifest["contract"]["pdf_bytes_acquired"] = true),
        "pdf_bytes_acquired",
    )
end

@testset "official metadata anchors are immutable" begin
    original = TOML.parsefile(MANIFEST_PATH)

    check_invalid(
        original,
        manifest -> (
            manifest["anchors"]["hmi7_root"]["byte_count"] += 1
        ),
        "hmi7_root.byte_count",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["anchors"]["hmi7_root"]["sha256"] = repeat("0", 64)
        ),
        "hmi7_root.sha256",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["anchors"]["release_sitemap"]["url"] =
                "https://www.bea.gov/sitemap.xml"
        ),
        "release_sitemap.url",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["anchors"]["release_sitemap"]["body_stored"] = true
        ),
        "release_sitemap.body_stored",
    )
end

@testset "hermetic file loading" begin
    module_source = read(MODULE_PATH, String)
    @test !occursin("using Downloads", module_source)
    @test !occursin("using HTTP", module_source)
    @test !occursin("Sockets", module_source)
    @test !occursin("download(", module_source)

    missing_error = captured_error() do
        load_manifest(joinpath(@__DIR__, "does-not-exist.toml"))
    end
    @test missing_error isa MetadataManifestError
    @test occursin("file does not exist", sprint(showerror, missing_error))

    mktempdir() do temporary
        invalid_path = joinpath(temporary, "invalid.toml")
        write(invalid_path, "[not valid")
        parse_error = captured_error() do
            load_manifest(invalid_path)
        end
        @test parse_error isa MetadataManifestError
        @test occursin("could not parse TOML", sprint(showerror, parse_error))

        if !Sys.iswindows()
            link_path = joinpath(temporary, "manifest-link.toml")
            symlink(MANIFEST_PATH, link_path)
            link_error = captured_error() do
                load_manifest(link_path)
            end
            @test link_error isa MetadataManifestError
            @test occursin(
                "must not be a symbolic link",
                sprint(showerror, link_error),
            )
        end
    end
end
