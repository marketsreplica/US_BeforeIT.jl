using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "BLSQuarterEndMetadataManifest.jl"))
using .BLSQuarterEndMetadataManifest

const MANIFEST_PATH = DEFAULT_MANIFEST_PATH
const MODULE_PATH =
    joinpath(@__DIR__, "BLSQuarterEndMetadataManifest.jl")
const EXPECTED_RELEASE_KEYS = [
    "04032015",
    "07022015",
    "10022015",
    "01082016",
    "04012016",
    "07082016",
    "10072016",
    "01062017",
    "04072017",
    "07072017",
    "10062017",
    "01052018",
    "04062018",
    "07062018",
    "10052018",
    "01042019",
    "04052019",
    "07052019",
    "10042019",
    "01102020",
    "04032020",
    "07022020",
    "10022020",
    "01082021",
    "04022021",
    "07022021",
    "10082021",
    "01072022",
    "04012022",
    "07082022",
    "10072022",
    "01062023",
    "04072023",
    "07072023",
    "10062023",
    "01052024",
    "04052024",
    "07052024",
    "10042024",
    "01102025",
]

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
    @test error isa BLSQuarterEndMetadataError
    @test occursin(message_fragment, sprint(showerror, error))
    return error
end

function destroy_mutable_graph!(value)
    if value isa AbstractDict
        for entry in collect(values(value))
            destroy_mutable_graph!(entry)
        end
        empty!(value)
    elseif value isa AbstractVector
        for entry in collect(value)
            destroy_mutable_graph!(entry)
        end
        empty!(value)
    end
    return nothing
end

function mutable_nodes(value, path = "root")
    result = String[]
    if value isa AbstractDict ||
            value isa AbstractArray ||
            value isa IO
        push!(result, "$path::$(typeof(value))")
    elseif value isa NamedTuple
        for name in propertynames(value)
            append!(
                result,
                mutable_nodes(getproperty(value, name), "$path.$name"),
            )
        end
    elseif value isa Tuple
        for (index, entry) in enumerate(value)
            append!(result, mutable_nodes(entry, "$path[$index]"))
        end
    end
    return result
end

@testset "sealed BLS 40-event route manifest" begin
    source_before = read(MANIFEST_PATH)
    artifact = manifest_artifact()
    events = artifact.events

    @test artifact.content_sha256 == EXPECTED_CONTENT_SHA256
    @test artifact.content_sha256 ==
        computed_content_sha256(TOML.parsefile(MANIFEST_PATH))
    @test artifact.file_sha256 == bytes2hex(sha256(source_before))
    @test artifact.file_byte_count == length(source_before)
    @test artifact.canonical_content isa String
    @test length(artifact.canonical_content) > 30_000
    @test events isa Tuple
    @test length(events) == 40
    @test [event.sequence for event in events] == collect(1:40)
    @test first(events).quarter == "2015Q1"
    @test last(events).quarter == "2024Q4"
    @test artifact.contract.metadata_only === true
    @test artifact.contract.event_count == 40
    @test all(value -> value === false, values(artifact.gates))
    @test all(event -> !event.first_public_bytes_verified, events)
    @test all(event -> !event.strict_origin_available, events)
    @test read(MANIFEST_PATH) == source_before
end

@testset "independently enumerated exact quarter and route keys" begin
    manifest = load_manifest()
    events = manifest.events
    expected_quarters = [
        "$(year)Q$(quarter)"
            for year in 2015:2024 for quarter in 1:4
    ]
    @test [event.quarter for event in events] == expected_quarters
    @test [event.release_key for event in events] == EXPECTED_RELEASE_KEYS
    @test length(unique(EXPECTED_RELEASE_KEYS)) == 40

    for event in events
        @test event.html_url ==
            "https://www.bls.gov/news.release/archives/empsit_" *
            event.release_key *
            ".htm"
        @test event.pdf_url ==
            "https://www.bls.gov/news.release/archives/empsit_" *
            event.release_key *
            ".pdf"
        quarter_number = parse(Int, event.quarter[end:end])
        @test event.reference_month ==
            event.quarter[1:4] *
            "-" *
            lpad(string(3 * quarter_number), 2, '0')
        @test event.embargo_basis == "DOCUMENT_STATED_EMBARGO"
    end
end

@testset "America/New_York DST and UTC conversions" begin
    events = load_manifest().events
    @test count(
        event -> event.event_timezone_abbreviation == "EDT",
        events,
    ) == 30
    @test count(
        event -> event.event_timezone_abbreviation == "EST",
        events,
    ) == 10

    for event in events
        quarter_number = parse(Int, event.quarter[end:end])
        @test occursin("T08:30:00", event.event_timestamp_local)
        if quarter_number == 4
            @test endswith(event.event_timestamp_local, "-05:00")
            @test endswith(event.event_timestamp_utc, "13:30:00Z")
            @test event.event_timezone_abbreviation == "EST"
        else
            @test endswith(event.event_timestamp_local, "-04:00")
            @test endswith(event.event_timestamp_utc, "12:30:00Z")
            @test event.event_timezone_abbreviation == "EDT"
        end
    end

    offset = BLSQuarterEndMetadataManifest._new_york_offset_seconds
    @test offset(Date(2019, 3, 9)) == -5 * 60 * 60
    @test offset(Date(2019, 3, 10)) == -4 * 60 * 60
    @test offset(Date(2019, 11, 2)) == -4 * 60 * 60
    @test offset(Date(2019, 11, 3)) == -5 * 60 * 60
end

@testset "two-axis provenance and corrected 2019Q4 exception" begin
    events = load_manifest().events
    by_quarter = Dict(event.quarter => event for event in events)
    corrected = by_quarter["2019Q4"]

    @test all(
        event -> event.economic_vintage_state == "UNKNOWN_REVISION_STATE",
        events,
    )
    @test count(
        event ->
        event.artifact_provenance_state ==
            "OFFICIAL_ARCHIVE_RECONSTRUCTION",
        events,
    ) == 39
    @test count(
        event ->
        event.artifact_provenance_state == "REISSUED_CORRECTED",
        events,
    ) == 1
    @test corrected.reference_month == "2019-12"
    @test corrected.release_key == "01102020"
    @test corrected.release_date == "2020-01-10"
    @test corrected.event_timestamp_local ==
        "2020-01-10T08:30:00-05:00"
    @test corrected.event_timestamp_utc ==
        "2020-01-10T13:30:00Z"
    @test corrected.artifact_provenance_state == "REISSUED_CORRECTED"
    @test corrected.correction_scope_state ==
        "TARGET_SCOPE_STATED_UNAFFECTED"
    @test !corrected.first_public_bytes_verified
    @test !corrected.strict_origin_available

    @test all(
        event -> event.html_source_role == "PRIMARY_VALUE_SOURCE",
        events,
    )
    @test all(
        event ->
        event.pdf_source_role == "PRIMARY_ARTIFACT_EVIDENCE",
        events,
    )
    @test Set(ECONOMIC_VINTAGE_STATES) == Set(
        [
            "FIRST_PRELIMINARY",
            "SECOND_PRELIMINARY",
            "THIRD_SAMPLE_BASED",
            "ANNUAL_BENCHMARK_REVISED",
            "ANNUAL_SA_REVISED",
            "POPULATION_CONTROL_BREAK",
            "UNKNOWN_REVISION_STATE",
        ],
    )
    @test Set(ARTIFACT_PROVENANCE_STATES) == Set(
        [
            "FIRST_PUBLIC_BYTES_VERIFIED",
            "OFFICIAL_ARCHIVE_RECONSTRUCTION",
            "REISSUED_CORRECTED",
            "UNKNOWN_FIRST_STATE",
            "MISSING_ROUTE",
            "SKIPPED_NOT_PUBLISHED",
        ],
    )
    @test Set(SOURCE_ROLES) == Set(
        [
            "PRIMARY_VALUE_SOURCE",
            "PRIMARY_ARTIFACT_EVIDENCE",
            "CROSSCHECK_ONLY",
            "NOT_USED",
            "QUARANTINED",
        ],
    )
    @test !("Used" in ECONOMIC_VINTAGE_STATES)
    @test !("Other" in ECONOMIC_VINTAGE_STATES)
    @test !("Used" in ARTIFACT_PROVENANCE_STATES)
    @test !("Other" in ARTIFACT_PROVENANCE_STATES)
    @test !("Used" in SOURCE_ROLES)
    @test !("Other" in SOURCE_ROLES)
end

@testset "validated returns never alias caller-owned mutable state" begin
    input = TOML.parsefile(MANIFEST_PATH)
    validated = validate_manifest(input)
    @test !(:manifest in propertynames(validated))
    @test validated.events isa Tuple
    @test validated.events[1] isa NamedTuple
    @test isempty(mutable_nodes(validated))

    input["events"][1]["release_key"] = "01011999"
    input["events"][20]["artifact_provenance_state"] =
        "FIRST_PUBLIC_BYTES_VERIFIED"
    input["contract"]["metadata_only"] = false
    input["gates"]["ready"] = true

    @test validated.events[1].release_key == "04032015"
    @test validated.events[20].artifact_provenance_state ==
        "REISSUED_CORRECTED"
    @test validated.contract.metadata_only === true
    @test validated.gates.ready === false
    @test validated.content_sha256 == EXPECTED_CONTENT_SHA256

    destroy_mutable_graph!(input)
    @test isempty(input)
    @test length(validated.events) == 40
    @test validated.events[20].correction_scope_state ==
        "TARGET_SCOPE_STATED_UNAFFECTED"
    @test isempty(mutable_nodes(validated))

    @test_throws MethodError setindex!(
        validated.events,
        validated.events[2],
        1,
    )
    @test_throws ErrorException setproperty!(
        validated.events[1],
        :release_key,
        "01011999",
    )
end

@testset "artifact return graph and canonical text are immutable" begin
    artifact = manifest_artifact()
    @test isempty(mutable_nodes(artifact))
    @test artifact.canonical_content isa String
    @test !(:raw_bytes in propertynames(artifact))
    @test !(:document in propertynames(artifact))
    @test !(:manifest in propertynames(artifact))
    @test_throws MethodError setindex!(
        artifact.events,
        artifact.events[2],
        1,
    )
    @test_throws MethodError setindex!(
        artifact.canonical_content,
        'X',
        1,
    )
    @test !isdefined(
        BLSQuarterEndMetadataManifest,
        :restamp_content_sha256!,
    )
    @test !isdefined(
        BLSQuarterEndMetadataManifest,
        :stamp_content_sha256!,
    )
end

@testset "deterministic typed and length-aware canonicalization" begin
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

    reversed_events = deepcopy(original)
    reverse!(reversed_events["events"])
    @test computed_content_sha256(reversed_events) != expected

    typed_change = deepcopy(original)
    typed_change["events"][1]["sequence"] = true
    @test computed_content_sha256(typed_change) != expected

    length_boundary_change = deepcopy(original)
    length_boundary_change["contract"]["source_agency"] =
        "U.S. Bureau of Labor Statistic"
    length_boundary_change["contract"]["publication_name"] =
        "sEmployment Situation"
    @test computed_content_sha256(length_boundary_change) != expected
end

@testset "fail-closed schema, exact inventory, and mandatory pin" begin
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
        manifest -> pop!(manifest["events"]),
        "exactly 40 rows",
    )
    check_invalid(
        original,
        manifest -> (manifest["events"][1]["sequence"] = 2),
        "manifest.events[1].sequence",
    )
    check_invalid(
        original,
        manifest -> (manifest["events"][2]["quarter"] = "2015Q1"),
        "manifest.events[2].quarter",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][2]["release_key"] =
                manifest["events"][1]["release_key"]
        ),
        "manifest.events[2].release_key",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["reference_month"] = "2015-04"
        ),
        "reference_month",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["release_date"] = "2015-04-04"
        ),
        "release_date",
    )

    plausible_allowed_enum_change = deepcopy(original)
    plausible_allowed_enum_change["events"][1]["economic_vintage_state"] =
        "FIRST_PRELIMINARY"
    restamp_content_sha256!(plausible_allowed_enum_change)
    pin_error = captured_error() do
        validate_manifest(plausible_allowed_enum_change)
    end
    @test pin_error isa BLSQuarterEndMetadataError
    @test occursin(
        "compiled sealed-contract pin",
        sprint(showerror, pin_error),
    )

    wrong_declared_hash = deepcopy(original)
    wrong_declared_hash["artifact"]["content_sha256"] = repeat("0", 64)
    hash_error = captured_error() do
        validate_manifest(wrong_declared_hash)
    end
    @test hash_error isa BLSQuarterEndMetadataError
    @test occursin("does not match computed", sprint(showerror, hash_error))
end

@testset "fail-closed embargo, timezone, and URL identity" begin
    original = TOML.parsefile(MANIFEST_PATH)

    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["event_timestamp_local"] =
                "2015-04-03T08:30:00-05:00";
            manifest["events"][1]["event_timestamp_utc"] =
                "2015-04-03T13:30:00Z";
            manifest["events"][1]["event_timezone_abbreviation"] = "EST"
        ),
        "America/New_York DST rules",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["event_timestamp_local"] =
                "2015-04-03T08:31:00-04:00"
        ),
        "08:30:00 embargo",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["event_timestamp_utc"] =
                "2015-04-03T13:30:00Z"
        ),
        "offset-normalized",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["event_timezone_iana"] = "US/Eastern"
        ),
        "event_timezone_iana",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["event_timezone_abbreviation"] = "EST"
        ),
        "event_timezone_abbreviation",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["embargo_basis"] =
                "INFERRED_FROM_CURRENT_CALENDAR"
        ),
        "embargo_basis",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["html_url"] =
                "https://example.com/empsit_04032015.htm"
        ),
        "html_url",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["pdf_url"] =
                manifest["events"][1]["pdf_url"] * "?download=1"
        ),
        "pdf_url",
    )
end

@testset "closed enums reject bare Used, Other, and dubious states" begin
    original = TOML.parsefile(MANIFEST_PATH)

    for bad in ("Used", "Other", "USED", "other", "UNSCOPED_UNKNOWN")
        check_invalid(
            original,
            manifest -> (
                manifest["events"][1]["economic_vintage_state"] = bad
            ),
            "unsupported closed-enum value",
        )
        check_invalid(
            original,
            manifest -> (
                manifest["events"][1]["artifact_provenance_state"] = bad
            ),
            "unsupported closed-enum value",
        )
        check_invalid(
            original,
            manifest -> (
                manifest["events"][1]["html_source_role"] = bad
            ),
            "unsupported closed-enum value",
        )
        check_invalid(
            original,
            manifest -> (
                manifest["events"][1]["pdf_source_role"] = bad
            ),
            "unsupported closed-enum value",
        )
    end
end

@testset "reissue cannot be normalized to first-public state" begin
    original = TOML.parsefile(MANIFEST_PATH)
    corrected_index = 20

    check_invalid(
        original,
        manifest -> (
            manifest["events"][corrected_index][
                "artifact_provenance_state",
            ] = "OFFICIAL_ARCHIVE_RECONSTRUCTION"
        ),
        "artifact_provenance_state",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][corrected_index][
                "artifact_provenance_state",
            ] = "FIRST_PUBLIC_BYTES_VERIFIED"
        ),
        "artifact_provenance_state",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][corrected_index][
                "correction_scope_state",
            ] = "NO_CORRECTION_IDENTIFIED_IN_SURVEY"
        ),
        "correction_scope_state",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][corrected_index][
                "first_public_bytes_verified",
            ] = true
        ),
        "first_public_bytes_verified",
    )
    check_invalid(
        original,
        manifest -> (
            manifest["events"][1]["artifact_provenance_state"] =
                "REISSUED_CORRECTED"
        ),
        "artifact_provenance_state",
    )
end

@testset "all acquisition, admission, and production gates are hard false" begin
    original = TOML.parsefile(MANIFEST_PATH)
    false_contract_fields = (
        "network_access_allowed",
        "downloader_implemented",
        "parser_implemented",
        "html_bytes_acquired",
        "pdf_bytes_acquired",
        "values_extracted",
        "quarterly_aggregates_created",
        "origins_created",
        "source_inventory_mutation_authorized",
    )
    for key in false_contract_fields
        check_invalid(
            original,
            manifest -> (manifest["contract"][key] = true),
            "manifest.contract.$key",
        )
    end
    for key in keys(original["gates"])
        check_invalid(
            original,
            manifest -> (manifest["gates"][key] = true),
            "manifest.gates.$key",
        )
    end
    for field in ("first_public_bytes_verified", "strict_origin_available")
        check_invalid(
            original,
            manifest -> (manifest["events"][1][field] = true),
            "manifest.events[1].$field",
        )
    end
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
    @test missing_error isa BLSQuarterEndMetadataError
    @test occursin("file does not exist", sprint(showerror, missing_error))

    mktempdir() do temporary
        invalid_path = joinpath(temporary, "invalid.toml")
        write(invalid_path, "[not valid")
        parse_error = captured_error() do
            load_manifest(invalid_path)
        end
        @test parse_error isa BLSQuarterEndMetadataError
        @test occursin(
            "could not parse TOML",
            sprint(showerror, parse_error),
        )

        if !Sys.iswindows()
            link_path = joinpath(temporary, "manifest-link.toml")
            symlink(MANIFEST_PATH, link_path)
            link_error = captured_error() do
                load_manifest(link_path)
            end
            @test link_error isa BLSQuarterEndMetadataError
            @test occursin(
                "must not be a symbolic link",
                sprint(showerror, link_error),
            )
        end
    end
end
