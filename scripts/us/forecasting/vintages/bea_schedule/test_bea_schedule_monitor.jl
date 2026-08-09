using Dates
using SHA
using TOML
using Test

include(joinpath(@__DIR__, "BEAScheduleMonitor.jl"))
using .BEAScheduleMonitor

const FIXTURE_DIR = joinpath(@__DIR__, "fixtures")
const FIXTURE_PATH =
    joinpath(FIXTURE_DIR, "schedule_2026q3_normalized.html")

fixture_bytes() = read(FIXTURE_PATH)
fixture_text() = read(FIXTURE_PATH, String)

function caught_message(function_to_run)
    caught = try
        function_to_run()
        nothing
    catch error
        error
    end
    @test caught isa ScheduleMonitorError
    return sprint(showerror, caught)
end

function fake_fetch(
        bytes = fixture_bytes();
        status = 200,
        content_type = "text/html; charset=UTF-8",
        locator = BEA_SCHEDULE_URL,
    )
    return FetchedSchedule(
        bytes,
        status,
        content_type,
        locator,
        "Thu, 06 Aug 2026 12:00:00 GMT",
        "\"fixture-etag\"",
        "Wed, 05 Aug 2026 20:00:07 GMT",
    )
end

@testset "normalized fixture integrity and evidence limits" begin
    manifest = TOML.parsefile(joinpath(FIXTURE_DIR, "fixture_manifest.toml"))
    artifact = manifest["artifact"]
    @test artifact["schema_version"] ==
        "beforeit-us-bea-schedule-fixtures.v1"
    @test artifact["status"] ==
        "HERMETIC_NORMALIZED_MUTABLE_SCHEDULE_FIXTURE"
    @test artifact["as_of_date"] == "2026-08-05"
    @test artifact["source_locator"] == BEA_SCHEDULE_URL
    @test artifact["source_locator_is_mutable"]
    @test !artifact["raw_source_response_included"]
    @test !artifact["release_bytes_included"]
    @test !artifact["release_event_evidence_included"]
    @test !artifact["origin_availability_evidence_included"]
    @test !artifact["origin_admission_evidence_included"]
    @test occursin("not a byte-identical HTTP response", artifact["normalization"])

    entries = manifest["fixtures"]
    @test length(entries) == 1
    entry = only(entries)
    @test entry["path"] == basename(FIXTURE_PATH)
    @test entry["sha256"] == bytes2hex(sha256(fixture_bytes()))
    @test entry["fixture_kind"] == "normalized_official_schedule_row"
    @test entry["expected_date_text"] == EXPECTED_DATE_TEXT
    @test entry["expected_time_text"] == EXPECTED_TIME_TEXT
    @test entry["expected_title"] == EXPECTED_TITLE
    @test entry["expected_strict_match_count"] == 1
    @test !entry["source_response_persisted"]
    @test !entry["release_bytes"]
    @test !entry["release_evidence"]
    @test !entry["origin_evidence"]
    @test !entry["origin_admissible"]
end

@testset "strict target row validates without admission claims" begin
    event = validate_expected_event(fixture_bytes())
    @test event.date_text == EXPECTED_DATE_TEXT
    @test event.time_text == EXPECTED_TIME_TEXT
    @test event.title == EXPECTED_TITLE
    @test event.match_count == 1
    @test event.evidence_class == "mutable_official_schedule_snapshot"
    @test !event.release_evidence
    @test !event.origin_evidence
    @test !event.origin_admissible

    string_event = validate_expected_event(fixture_text())
    @test string_event.date_text == event.date_text
    @test string_event.time_text == event.time_text
    @test string_event.title == event.title
end

@testset "moved, duplicated, and structurally changed rows fail closed" begin
    source = fixture_text()
    target_row = only(
        match(
            r"""(?is)(<tr class="scheduled-releases-type-press">.*?</tr>)""",
            source,
        ).captures,
    )
    distractor_row = replace(
        target_row,
        EXPECTED_TITLE => "Personal Income and Outlays, September 2026",
    )
    with_same_time_distractor = replace(
        source,
        "</tbody>" => distractor_row * "\n      </tbody>",
    )
    @test validate_expected_event(with_same_time_distractor).title ==
        EXPECTED_TITLE

    moved_date = replace(source, EXPECTED_DATE_TEXT => "October 30")
    @test occursin(
        "expected \"October 29\", found \"October 30\"",
        caught_message(() -> validate_expected_event(moved_date)),
    )
    moved_with_same_time_distractor = replace(
        moved_date,
        "</tbody>" => distractor_row * "\n      </tbody>",
    )
    @test occursin(
        "expected \"October 29\", found \"October 30\"",
        caught_message(
            () -> validate_expected_event(
                moved_with_same_time_distractor,
            ),
        ),
    )

    moved_time = replace(source, EXPECTED_TIME_TEXT => "10:00 AM")
    @test occursin(
        "expected \"8:30 AM\", found \"10:00 AM\"",
        caught_message(() -> validate_expected_event(moved_time)),
    )

    renamed = replace(
        source,
        EXPECTED_TITLE => "GDP (Second Estimate), 3rd Quarter 2026",
    )
    @test occursin(
        "schedule.expected_title",
        caught_message(() -> validate_expected_event(renamed)),
    )

    missing = replace(source, target_row => "")
    @test occursin(
        "schedule.expected_title",
        caught_message(() -> validate_expected_event(missing)),
    )

    duplicate = replace(
        source,
        "</tbody>" =>
            replace(
            target_row,
            "\n" => "\n        ",
        ) * "\n      </tbody>",
    )
    @test occursin(
        "must occur exactly once as literal text",
        caught_message(() -> validate_expected_event(duplicate)),
    )

    wrong_row_class = replace(
        source,
        "scheduled-releases-type-press" =>
            "scheduled-releases-type-data",
    )
    @test occursin(
        "strict press-release row; found 0",
        caught_message(() -> validate_expected_event(wrong_row_class)),
    )

    wrong_title_class = replace(
        source,
        "release-title views-field views-field-field-scheduled-releases-type" =>
            "views-field release-title",
    )
    @test occursin(
        "schedule.expected_row.title",
        caught_message(() -> validate_expected_event(wrong_title_class)),
    )

    no_canonical = replace(
        source,
        """    <link rel="canonical" href="$BEA_SCHEDULE_URL">\n""" => "",
    )
    @test occursin(
        "schedule.canonical",
        caught_message(() -> validate_expected_event(no_canonical)),
    )

    duplicate_canonical = replace(
        source,
        "</head>" =>
            """<link rel="canonical" href="$BEA_SCHEDULE_URL">\n  </head>""",
    )
    @test occursin(
        "schedule.canonical",
        caught_message(() -> validate_expected_event(duplicate_canonical)),
    )
end

@testset "malformed and oversized input fails closed" begin
    @test occursin(
        "must not be empty",
        caught_message(() -> validate_expected_event(UInt8[])),
    )
    @test occursin(
        "must be UTF-8 text or bytes",
        caught_message(() -> validate_expected_event(42)),
    )
    @test occursin(
        "not valid UTF-8",
        caught_message(() -> validate_expected_event(UInt8[0xff])),
    )
    @test occursin(
        "must not contain NUL",
        caught_message(
            () -> validate_expected_event(
                vcat(fixture_bytes(), UInt8[0x00]),
            ),
        ),
    )
    @test occursin(
        "parser limit",
        caught_message(
            () -> validate_expected_event(
                fill(UInt8('x'), BEAScheduleMonitor.MAX_RESPONSE_BYTES + 1),
            ),
        ),
    )
end

@testset "snapshot bytes and metadata are content addressed" begin
    mktempdir() do output_dir
        observed_at = DateTime(2026, 8, 6, 12, 34, 56)
        fetched = fake_fetch()
        result = write_validated_snapshot(
            output_dir,
            fetched;
            observed_at_utc = observed_at,
        )

        @test isfile(result.raw_path)
        @test isfile(result.metadata_path)
        @test read(result.raw_path) == fetched.raw_bytes
        @test basename(result.raw_path) ==
            "bea-schedule-raw-sha256-$(result.raw_sha256).html"
        @test result.raw_sha256 == sha256_hex(fetched.raw_bytes)
        @test basename(result.metadata_path) ==
            "bea-schedule-metadata-sha256-$(result.metadata_sha256).toml"
        @test result.metadata_sha256 ==
            sha256_hex(read(result.metadata_path))
        @test sort(readdir(output_dir)) ==
            sort([basename(result.raw_path), basename(result.metadata_path)])

        metadata = TOML.parsefile(result.metadata_path)
        artifact = metadata["artifact"]
        event = metadata["validated_event"]
        @test artifact["schema_version"] ==
            "beforeit-us-bea-schedule-snapshot.v1"
        @test artifact["status"] ==
            "MUTABLE_SCHEDULE_SNAPSHOT_ONLY_NOT_RELEASE_OR_ORIGIN_EVIDENCE"
        @test artifact["evidence_class"] ==
            "mutable_official_schedule_snapshot"
        @test artifact["observed_at_utc"] == "2026-08-06T12:34:56Z"
        @test artifact["source_locator"] == BEA_SCHEDULE_URL
        @test artifact["effective_locator"] == BEA_SCHEDULE_URL
        @test artifact["http_status"] == 200
        @test artifact["http_content_type"] ==
            "text/html; charset=UTF-8"
        @test artifact["http_response_date"] ==
            "Thu, 06 Aug 2026 12:00:00 GMT"
        @test artifact["http_etag"] == "\"fixture-etag\""
        @test artifact["http_last_modified"] ==
            "Wed, 05 Aug 2026 20:00:07 GMT"
        @test artifact["raw_response_filename"] ==
            basename(result.raw_path)
        @test artifact["raw_response_sha256"] == result.raw_sha256
        @test artifact["raw_response_bytes"] == length(fetched.raw_bytes)
        @test artifact["digest_algorithm"] == "sha256"
        @test artifact["metadata_addressing"] ==
            "SHA256_OF_EXACT_METADATA_TOML_BYTES_IN_FILENAME"
        @test artifact["persistence_scope"] ==
            "CALLER_SUPPLIED_OUTPUT_ONLY_NO_PERMANENCE_OR_AVAILABILITY_CLAIM"
        @test artifact["schedule_is_mutable"]
        @test !artifact["release_bytes_included"]
        @test !artifact["release_event_evidence"]
        @test !artifact["origin_availability_evidence"]
        @test !artifact["origin_admissible"]
        @test !artifact["inventory_mutated"]
        @test !artifact["admission_mutated"]
        @test !artifact["ready"]
        @test event["date_text"] == EXPECTED_DATE_TEXT
        @test event["time_text"] == EXPECTED_TIME_TEXT
        @test event["title"] == EXPECTED_TITLE
        @test event["strict_match_count"] == 1
        @test event["validation_status"] ==
            "EXPECTED_MUTABLE_SCHEDULE_ROW_PRESENT"
        @test !event["release_evidence"]
        @test !event["origin_evidence"]
        @test !event["origin_admissible"]

        repeated = write_validated_snapshot(
            output_dir,
            fetched;
            observed_at_utc = observed_at,
        )
        @test repeated.raw_path == result.raw_path
        @test repeated.metadata_path == result.metadata_path
        @test length(readdir(output_dir)) == 2
    end
end

@testset "snapshot boundaries reject nonofficial and failed fetches" begin
    mktempdir() do output_dir
        @test occursin(
            "expected 200",
            caught_message(
                () -> write_validated_snapshot(
                    output_dir,
                    fake_fetch(status = 503),
                ),
            ),
        )
        @test occursin(
            "http.effective_locator",
            caught_message(
                () -> write_validated_snapshot(
                    output_dir,
                    fake_fetch(locator = "https://example.com/schedule"),
                ),
            ),
        )
        @test occursin(
            "expected text/html",
            caught_message(
                () -> write_validated_snapshot(
                    output_dir,
                    fake_fetch(content_type = "application/json"),
                ),
            ),
        )
        @test isempty(readdir(output_dir))

        @test_throws ErrorException capture_live_snapshot(
            output_dir;
            fetcher = () -> error("simulated network failure"),
        )
        @test isempty(readdir(output_dir))

        result = capture_live_snapshot(
            output_dir;
            observed_at_utc = DateTime(2026, 8, 6),
            fetcher = () -> fake_fetch(),
        )
        @test isfile(result.raw_path)
        @test isfile(result.metadata_path)
    end

    mktempdir() do temporary_parent
        missing_dir = joinpath(temporary_parent, "missing-output")
        @test occursin(
            "must be an existing directory",
            caught_message(
                () -> write_validated_snapshot(
                    missing_dir,
                    fake_fetch(),
                ),
            ),
        )
    end
end
