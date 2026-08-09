using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "BEANIPADiscovery.jl"))
include(joinpath(@__DIR__, "BEANIPAAcquisition.jl"))
include(joinpath(@__DIR__, "BEANIPAPilotReceipt.jl"))
using .BEANIPAAcquisition
using .BEANIPAPilotReceipt

const SUMMARY_PATH =
    joinpath(@__DIR__, "pilot_2026q2_present_day_receipt.toml")
const PROFILE_PATH =
    joinpath(@__DIR__, "pilot_2026q2_target_profile.toml")
const AVAILABILITY_AUDIT_PATH =
    joinpath(@__DIR__, "pilot_2026q2_availability_audit.toml")
const INVENTORY_PATH =
    normpath(joinpath(@__DIR__, "..", "current_inventory.toml"))
const RAW_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", "..", "data", "us", "raw"))
const RFC3339_SECONDS = dateformat"yyyy-mm-ddTHH:MM:SS"

utc_timestamp(value) =
    DateTime(only(match(r"^(.+)Z$", value).captures), RFC3339_SECONDS)

@testset "2026Q2 present-day exact-byte receipt summary" begin
    summary_bytes = read(SUMMARY_PATH)
    @test bytes2hex(SHA.sha256(summary_bytes)) ==
        "a5237d6d3588468bf778fb337a7f2e5ad2a9f32e832938920b4f4f6332b7b2a2"
    summary = TOML.parse(String(summary_bytes))
    artifact = summary["artifact"]
    @test artifact["schema_version"] ==
        "beforeit-us-bea-nipa-present-day-receipt-summary.v1"
    @test artifact["release_id"] == PILOT_RELEASE_ID
    @test artifact["present_day_acquisition_observed"]
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

    @test summary["archive_discovery"]["archive_directory_id"] ==
        PILOT_ARCHIVE_DIRECTORY_ID
    @test !summary["archive_discovery"]["historical_availability_inferred"]

    capture = summary["capture"]
    pair_started = utc_timestamp(capture["pair_started_at_utc"])
    pair_completed = utc_timestamp(capture["pair_completed_at_utc"])
    @test capture["observed_pair_span_seconds"] ==
        div(Dates.value(pair_completed - pair_started), 1000) == 2
    @test !capture["external_timestamp_attestation"]

    raw_pair = summary["raw_pair"]
    @test raw_pair["raw_bundle_sha256"] == bundle_sha256()
    @test raw_pair["atomic_pair_complete"]
    @test raw_pair["all_or_nothing_validation"]
    workbooks = summary["workbooks"]
    @test [row["section_id"] for row in workbooks] == ["1", "2"]
    @test sum(row["byte_count"] for row in workbooks) ==
        sum(row.expected_byte_count for row in PILOT_EXPECTATIONS)
    for (row, expectation) in zip(workbooks, PILOT_EXPECTATIONS)
        @test row["url"] == expectation.requested_locator
        @test row["effective_url"] == expectation.requested_locator
        @test row["sha256"] == expectation.expected_sha256
        @test row["byte_count"] == expectation.expected_byte_count
        @test row["http_status"] == 200
        @test row["redirect_count"] == 0
        @test pair_started <=
            utc_timestamp(row["acquisition_started_at_utc"]) <=
            utc_timestamp(row["response_headers_at_utc"]) <=
            utc_timestamp(row["acquisition_completed_at_utc"]) <=
            pair_completed
    end

    semantic = summary["semantic_linkage"]
    @test semantic["target_profile_file_sha256"] ==
        bytes2hex(SHA.sha256(read(PROFILE_PATH))) ==
        PILOT_PROFILE_FILE_SHA256
    @test semantic["content_fingerprint_schema_version"] ==
        PILOT_CONTENT_FINGERPRINT_SCHEMA
    @test semantic["content_fingerprint_parser_sha256"] ==
        PILOT_CONTENT_FINGERPRINT_PARSER_SHA256
    @test semantic["content_fingerprint_file_sha256"] ==
        PILOT_CONTENT_FINGERPRINT_FILE_SHA256
    @test semantic["exact_mapping_count"] == 5
    @test semantic["reference_period_count_per_target"] == 318
    @test !semantic["execution_environment_in_semantic_identity"]
    @test !semantic["repository_state_in_semantic_identity"]

    receipt = summary["receipt"]
    @test receipt["receipt_content_sha256"] ==
        "9265bc33d7e6ff71eb32e72f792104f982701321a7be16cedf92318aedeccedd"
    @test receipt["receipt_file_sha256"] ==
        "0547b1f480325005a961fe9dbf6a1a816cdb784e47398cf90afc8f0e4bdd51d1"
    @test receipt["local_exact_byte_validation_passed"]
    @test !receipt["tracked_summary_is_substitute_for_receipt"]

    historical = summary["historical_availability"]
    @test historical["audit_file_sha256"] ==
        bytes2hex(SHA.sha256(read(AVAILABILITY_AUDIT_PATH)))
    @test !historical["exact_pair_bound_to_independent_pre_origin_evidence"]
    @test historical["outcome"] ==
        "EXACT_WORKBOOK_BYTE_AVAILABILITY_AT_ORIGIN_NOT_PROVEN"

    inventory = summary["inventory"]
    @test inventory["inventory_file_sha256_before_and_after"] ==
        bytes2hex(SHA.sha256(read(INVENTORY_PATH)))
    @test !inventory["inventory_mutated"]
    @test inventory["registered_release_event_count"] == 0
    @test inventory["admissible_origin_count"] == 0

    local_receipt_path =
        joinpath(RAW_ROOT, receipt["receipt_relative_path"])
    local_receipt_valid = if isfile(local_receipt_path)
        result =
            BEANIPAPilotReceipt.BEAWorkbookReceipts.validate_receipt_file(
            local_receipt_path,
        )
        result.content_sha256 == receipt["receipt_content_sha256"] &&
            result.content_fingerprint_file_sha256 ==
            semantic["content_fingerprint_file_sha256"] &&
            !result.origin_admissible &&
            !result.ready
    else
        true
    end
    @test local_receipt_valid
end
