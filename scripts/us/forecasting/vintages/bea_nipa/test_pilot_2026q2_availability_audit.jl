using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "BEANIPADiscovery.jl"))
include(joinpath(@__DIR__, "BEANIPAAcquisition.jl"))
using .BEANIPAAcquisition

const AUDIT_PATH =
    joinpath(@__DIR__, "pilot_2026q2_availability_audit.toml")
const PROFILE_PATH =
    joinpath(@__DIR__, "pilot_2026q2_target_profile.toml")
const INVENTORY_PATH =
    normpath(joinpath(@__DIR__, "..", "current_inventory.toml"))
const RFC3339_SECONDS = dateformat"yyyy-mm-ddTHH:MM:SS"

utc_timestamp(value) =
    DateTime(only(match(r"^(.+)Z$", value).captures), RFC3339_SECONDS)

@testset "2026Q2 exact-byte historical availability audit" begin
    inventory_before = read(INVENTORY_PATH)
    audit_bytes = read(AUDIT_PATH)
    @test bytes2hex(SHA.sha256(audit_bytes)) ==
        "2505a2aec7dc50f4d0fdae6d7aaa143932fe49398f8fa0ce10cccef06e24bcd2"
    audit = TOML.parse(String(audit_bytes))

    artifact = audit["artifact"]
    @test artifact["schema_version"] ==
        "beforeit-us-bea-nipa-historical-availability-audit.v1"
    @test artifact["release_id"] == PILOT_RELEASE_ID
    @test artifact["outcome"] ==
        "EXACT_WORKBOOK_BYTE_AVAILABILITY_AT_ORIGIN_NOT_PROVEN"
    for key in (
            "historical_release_availability_verified",
            "release_event_timestamp_verified_for_exact_workbook_bytes",
            "first_state_verified",
            "origin_admissible",
            "inventory_registered",
            "ready",
        )
        @test artifact[key] === false
    end

    cutoff = utc_timestamp(
        audit["candidate_origin"]["origin_cutoff_utc"],
    )
    @test cutoff == DateTime(2026, 7, 31, 14)
    @test audit["candidate_origin"]["requirement_satisfied"] === false

    pair = audit["exact_pair"]
    @test pair["raw_bundle_sha256"] == bundle_sha256()
    expectations = Dict(
        row.section_id => row for row in PILOT_EXPECTATIONS
    )
    for section in ("1", "2")
        @test pair["section_$(section)_sha256"] ==
            expectations[section].expected_sha256
        @test pair["section_$(section)_bytes"] ==
            expectations[section].expected_byte_count
    end
    @test pair["exact_byte_identity_bound_to_pre_origin_evidence"] ===
        false

    profile = TOML.parsefile(PROFILE_PATH)
    profile_workbooks = Dict(
        row["section_id"] => row for row in profile["workbooks"]
    )
    for section in ("1", "2")
        @test profile_workbooks[section]["raw_sha256"] ==
            expectations[section].expected_sha256
    end

    release_page = audit["official_release_page"]
    @test utc_timestamp(release_page["stated_embargoed_release_utc"]) <
        cutoff
    @test release_page["exact_pair_hashes_present"] === false
    @test release_page["exact_pair_availability_proven"] === false

    independent = audit["independent_evidence"]
    @test length(independent) == 2
    @test all(
        row -> utc_timestamp(row["memento_datetime_utc"]) < cutoff,
        independent,
    )
    @test all(row -> row["current_official_copy_same_sha256"], independent)
    @test all(row -> !row["contains_exact_pair_hashes"], independent)
    @test all(row -> !row["binds_exact_pair_bytes"], independent)
    @test all(
        row -> !row["satisfies_exact_pair_availability_requirement"],
        independent,
    )

    searches = audit["exact_workbook_archive_searches"]
    @test [row["section_id"] for row in searches] == ["1", "2"]
    @test all(row -> row["matching_capture_count"] == 0, searches)
    @test all(row -> !row["absence_is_availability_evidence"], searches)

    observations = audit["present_day_server_observations"]
    @test [row["section_id"] for row in observations] == ["1", "2"]
    @test all(row -> row["observation_occurred_after_origin"], observations)
    @test all(
        row -> !row["server_metadata_is_independent_pre_origin_evidence"],
        observations,
    )
    @test all(
        row -> !row["proves_pre_origin_exact_byte_availability"],
        observations,
    )
    @test audit["remaining_requirement"]["current_evidence_is_sufficient"] ===
        false
    @test read(INVENTORY_PATH) == inventory_before
end
