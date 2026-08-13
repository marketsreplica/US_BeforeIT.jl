#!/usr/bin/env julia

using Test
using Dates
using TOML

include(joinpath(@__DIR__, "USProspectiveAcquisitionContract.jl"))
using .USProspectiveAcquisitionContract
include(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "contracts",
        "USForecastProtocol.jl",
    ),
)
include(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "targets",
        "USTier1TargetCoverage.jl",
    ),
)

const CONTRACT_PATH =
    joinpath(@__DIR__, "prospective_2026q3_contract.toml")
const V1_INVENTORY_PATH = joinpath(@__DIR__, "..", "current_inventory.toml")
const PROTOCOL_PATH =
    joinpath(@__DIR__, "..", "..", "protocol.toml")
const TIER1_TARGETS_PATH =
    joinpath(@__DIR__, "..", "..", "targets", "tier1_targets.toml")

checked_contract() = load_contract(CONTRACT_PATH)

function restamp!(contract)
    stamp_contract_sha256!(contract)
    return contract
end

function candidate_receipt(;
        event_id = "bea_gdp_2026q3_advance",
        requirement_id = "bea_nipa_tier1",
        retrieved_at_utc = "2026-10-29T12:30:01Z",
        receipt_completed_at_utc = "2026-10-29T12:30:05Z",
        availability_upper_bound_utc = receipt_completed_at_utc,
        receipt_artifact_status = "VERIFIED",
        durable_storage_status = "VERIFIED",
        retain_until_utc = "2032-10-30T14:00:00Z",
    )
    return Dict{String, Any}(
        "receipt_id" => "synthetic-test-receipt",
        "event_id" => event_id,
        "requirement_id" => requirement_id,
        "retrieved_at_utc" => retrieved_at_utc,
        "receipt_completed_at_utc" => receipt_completed_at_utc,
        "availability_upper_bound_utc" =>
            availability_upper_bound_utc,
        "availability_basis" =>
            "VERIFIED_PRE_ORIGIN_RECEIPT_COMPLETION",
        "raw_sha256" => repeat("a", 64),
        "receipt_sha256" => repeat("b", 64),
        "receipt_artifact_status" => receipt_artifact_status,
        "durable_storage_status" => durable_storage_status,
        "retain_until_utc" => retain_until_utc,
    )
end

@testset "checked-in prospective contract is valid and fail closed" begin
    contract = checked_contract()
    governance = evaluate_governance(contract)
    v1_inventory = TOML.parsefile(V1_INVENTORY_PATH)

    @test validate_contract(contract) === contract
    @test contract["artifact"]["content_sha256"] ==
        contract_sha256(contract)
    @test contract["artifact"]["protocol_sha256"] ==
        USForecastProtocol.protocol_sha256(
        USForecastProtocol.load_protocol(PROTOCOL_PATH),
    )
    @test contract["artifact"]["tier1_targets_sha256"] ==
        USTier1TargetCoverage.inventory_sha256(
        USTier1TargetCoverage.load_inventory(TIER1_TARGETS_PATH),
    )
    @test contract["artifact"]["status"] ==
        "DRAFT_UNAPPROVED_FAIL_CLOSED"
    @test !governance.verifier_ready
    @test !governance.approval_ready
    @test !governance.activation_ready
    @test contract["verifier"]["implementation_status"] ==
        "NOT_IMPLEMENTED_FAIL_CLOSED"
    @test contract["approval"]["artifact_approval_status"] ==
        "DRAFT_UNAPPROVED"
    @test contract["origin"]["admission_status"] ==
        "PLANNED_NOT_CAPTURED_NOT_ADMITTED"
    @test !contract["origin"]["inventory_mutation_authorized"]
    @test !contract["origin"]["origin_admissible"]
    @test !contract["origin"]["ready"]
    @test !contract["origin"]["accuracy_evaluation_allowed"]
    @test isempty(v1_inventory["release_events"])
    @test isempty(v1_inventory["admissible_origin_timestamps_utc"])
    @test v1_inventory["artifact"]["content_sha256"] ==
        "6b1fc42b1d645d43f9be6e215d42ab662924d6bb51249760aa2992d143031d74"
end

@testset "availability upper bound is conservative prospective evidence" begin
    contract = checked_contract()
    receipt = candidate_receipt()
    evaluation = evaluate_receipt_evidence(contract, receipt)

    @test validate_receipt(contract, receipt).upper_bound ==
        DateTime(2026, 10, 29, 12, 30, 5)
    @test evaluation.temporal_candidate_eligible
    @test !evaluation.verifier_ready
    @test !evaluation.requirements_approved
    @test !evaluation.contract_usable
    @test !evaluation.origin_admissible
    @test !evaluation.ready
    @test evaluation.reason_codes ==
        ["REQUIREMENTS_NOT_APPROVED", "VERIFIER_NOT_IMPLEMENTED"]

    snapshot_receipt = candidate_receipt(
        event_id = "slow_structural_pre_origin",
        requirement_id = "bea_fixed_assets_structural",
        retrieved_at_utc = "2026-08-06T12:00:00Z",
        receipt_completed_at_utc = "2026-08-06T12:00:03Z",
    )
    @test evaluate_receipt_evidence(
        contract,
        snapshot_receipt,
    ).temporal_candidate_eligible
    historical_snapshot = candidate_receipt(
        event_id = "slow_structural_pre_origin",
        requirement_id = "bea_fixed_assets_structural",
        retrieved_at_utc = "2026-08-05T23:59:55Z",
        receipt_completed_at_utc = "2026-08-05T23:59:59Z",
    )
    historical_snapshot_evaluation =
        evaluate_receipt_evidence(contract, historical_snapshot)
    @test !historical_snapshot_evaluation.temporal_candidate_eligible
    @test "OUTSIDE_CONTRACT_CAPTURE_WINDOW" in
        historical_snapshot_evaluation.reason_codes

    recurring_receipt = candidate_receipt(
        event_id = "frbny_effr_daily_first_state",
        requirement_id = "frbny_effr_tier1",
        retrieved_at_utc = "2026-08-07T13:00:01Z",
        receipt_completed_at_utc = "2026-08-07T13:00:03Z",
    )
    @test evaluate_receipt_evidence(
        contract,
        recurring_receipt,
    ).temporal_candidate_eligible

    final_effr_receipt = candidate_receipt(
        event_id = "frbny_effr_2026_10_29_first_state",
        requirement_id = "frbny_effr_tier1",
        retrieved_at_utc = "2026-10-30T13:00:01Z",
        receipt_completed_at_utc = "2026-10-30T13:00:03Z",
    )
    @test evaluate_receipt_evidence(
        contract,
        final_effr_receipt,
    ).temporal_candidate_eligible
end

@testset "verifier readiness and requirements approval are independent" begin
    verifier_only = checked_contract()
    verifier_only["verifier"]["implementation_status"] =
        "IMPLEMENTED_AND_VERIFIED"
    verifier_only["verifier"]["implementation_artifact_sha256"] =
        repeat("c", 64)
    verifier_only["verifier"]["receipt_artifact_verification_status"] =
        "VERIFIED"
    verifier_only["artifact"]["status"] =
        "VERIFIER_READY_REQUIREMENTS_UNAPPROVED"
    restamp!(verifier_only)
    @test validate_contract(verifier_only) === verifier_only
    verifier_governance = evaluate_governance(verifier_only)
    @test verifier_governance.verifier_ready
    @test !verifier_governance.approval_ready
    @test !verifier_governance.activation_ready
    verifier_receipt =
        evaluate_receipt_evidence(verifier_only, candidate_receipt())
    @test verifier_receipt.temporal_candidate_eligible
    @test !verifier_receipt.contract_usable
    @test verifier_receipt.reason_codes == ["REQUIREMENTS_NOT_APPROVED"]

    approval_only = checked_contract()
    approval_only["approval"]["artifact_approval_status"] = "APPROVED"
    approval_only["approval"]["model_owner"] = "synthetic-test-model-owner"
    approval_only["approval"]["model_owner_signature"] = repeat("d", 64)
    approval_only["approval"]["independent_validator"] =
        "synthetic-test-independent-validator"
    approval_only["approval"]["independent_validator_signature"] =
        repeat("e", 64)
    approval_only["artifact"]["status"] =
        "APPROVED_REQUIREMENTS_VERIFIER_BLOCKED"
    restamp!(approval_only)
    @test validate_contract(approval_only) === approval_only
    approval_governance = evaluate_governance(approval_only)
    @test !approval_governance.verifier_ready
    @test approval_governance.approval_ready
    @test !approval_governance.activation_ready
    approval_receipt =
        evaluate_receipt_evidence(approval_only, candidate_receipt())
    @test approval_receipt.temporal_candidate_eligible
    @test !approval_receipt.contract_usable
    @test approval_receipt.reason_codes == ["VERIFIER_NOT_IMPLEMENTED"]
end

@testset "fixed and recurring 2026Q3 calendar is pinned" begin
    contract = checked_contract()
    fixed = contract["fixed_events"]
    recurring = contract["recurring_windows"]

    @test [
        event["event_id"] for event in fixed
    ] == [
        "bls_employment_situation_2026_07",
        "bls_qcew_2026q1",
        "bls_employment_situation_2026_08",
        "frb_z1_2026q2",
        "bea_annual_update_2026",
        "bls_employment_situation_2026_09",
        "bea_gdp_2026q3_advance",
        "frbny_effr_2026_10_29_first_state",
    ]
    @test fixed[end]["capture_deadline_utc"] ==
        "2026-10-30T13:15:00Z"
    @test contract["origin"]["origin_timestamp_utc"] ==
        "2026-10-30T14:00:00Z"
    @test all(event["receipt_count"] == 0 for event in fixed)
    @test all(!event["origin_eligible"] for event in fixed)
    @test [
        window["scheduled_time_utc"] for window in recurring
    ] == ["13:00:00Z", "18:30:00Z"]
    @test recurring[1]["campaign_end_date"] == "2026-10-30"
    @test recurring[2]["campaign_end_date"] == "2026-10-29"
    @test all(window["receipt_count"] == 0 for window in recurring)
end

@testset "retention and source requirements are complete but uncaptured" begin
    contract = checked_contract()
    retention = contract["retention"]
    requirements = contract["requirements"]

    @test retention["minimum_retain_until_utc"] ==
        "2031-10-30T14:00:00Z"
    @test retention["origin_plus_mature_truth_months"] == 60
    @test retention["minimum_durable_copy_count"] == 2
    @test retention["content_addressed_storage_required"]
    @test retention["write_once_or_versioned_storage_required"]
    @test retention["raw_and_receipt_bytes_co_retained"]
    @test retention["external_timestamp_receipt_required"]
    @test !retention["github_actions_artifact_only_allowed"]
    @test !retention["short_retention_artifact_is_origin_evidence"]
    @test length(requirements) == 11
    @test all(
        requirement["evidence_status"] == "MISSING_NOT_CAPTURED"
            for requirement in requirements
    )
    @test all(
        requirement["registered_raw_artifact_count"] == 0
            for requirement in requirements
    )
    @test Set(
        target for requirement in requirements
            for target in requirement["target_ids"]
    ) == Set(
        [
            "core_pce_price_index",
            "effective_federal_funds_rate",
            "gdp_deflator",
            "nominal_gdp",
            "payroll_employment",
            "pce_price_index",
            "real_gdp",
            "unemployment_rate",
        ],
    )
end

@testset "post-origin, unverified, and short-lived receipts stay ineligible" begin
    contract = checked_contract()

    post_origin = candidate_receipt(
        retrieved_at_utc = "2026-10-30T14:00:01Z",
        receipt_completed_at_utc = "2026-10-30T14:00:02Z",
    )
    post_origin_eval = evaluate_receipt_evidence(contract, post_origin)
    @test !post_origin_eval.temporal_candidate_eligible
    @test "NOT_PROVEN_BEFORE_ORIGIN" in post_origin_eval.reason_codes
    @test "OUTSIDE_CONTRACT_CAPTURE_WINDOW" in
        post_origin_eval.reason_codes

    mismatched_upper_bound = candidate_receipt(
        availability_upper_bound_utc = "2026-10-29T12:30:04Z",
    )
    mismatch_eval =
        evaluate_receipt_evidence(contract, mismatched_upper_bound)
    @test !mismatch_eval.temporal_candidate_eligible
    @test "UPPER_BOUND_NOT_RECEIPT_COMPLETION" in
        mismatch_eval.reason_codes

    unverified =
        candidate_receipt(receipt_artifact_status = "NOT_VERIFIED")
    unverified_eval = evaluate_receipt_evidence(contract, unverified)
    @test !unverified_eval.temporal_candidate_eligible
    @test "RECEIPT_ARTIFACT_NOT_VERIFIED" in
        unverified_eval.reason_codes

    ephemeral =
        candidate_receipt(durable_storage_status = "NOT_VERIFIED")
    ephemeral_eval = evaluate_receipt_evidence(contract, ephemeral)
    @test !ephemeral_eval.temporal_candidate_eligible
    @test "DURABLE_STORAGE_NOT_VERIFIED" in
        ephemeral_eval.reason_codes

    short_retention =
        candidate_receipt(retain_until_utc = "2026-11-30T00:00:00Z")
    short_eval = evaluate_receipt_evidence(contract, short_retention)
    @test !short_eval.temporal_candidate_eligible
    @test "RETENTION_DOES_NOT_COVER_MATURE_TRUTH" in
        short_eval.reason_codes

    before_release = candidate_receipt(
        retrieved_at_utc = "2026-10-29T12:29:59Z",
        receipt_completed_at_utc = "2026-10-29T12:30:01Z",
    )
    before_release_eval =
        evaluate_receipt_evidence(contract, before_release)
    @test !before_release_eval.temporal_candidate_eligible
    @test "OUTSIDE_CONTRACT_CAPTURE_WINDOW" in
        before_release_eval.reason_codes
end

@testset "contract and receipt tampering fail closed" begin
    ready = checked_contract()
    ready["origin"]["ready"] = true
    restamp!(ready)
    @test_throws ProspectiveContractValidationError validate_contract(ready)

    inventory_mutation = checked_contract()
    inventory_mutation["origin"]["inventory_mutation_authorized"] = true
    restamp!(inventory_mutation)
    @test_throws ProspectiveContractValidationError validate_contract(
        inventory_mutation,
    )

    fake_capture = checked_contract()
    fake_capture["fixed_events"][end]["receipt_count"] = 1
    restamp!(fake_capture)
    @test_throws ProspectiveContractValidationError validate_contract(
        fake_capture,
    )

    fake_evidence = checked_contract()
    fake_evidence["requirements"][1]["evidence_status"] = "AVAILABLE"
    restamp!(fake_evidence)
    @test_throws ProspectiveContractValidationError validate_contract(
        fake_evidence,
    )

    schedule_only = checked_contract()
    schedule_only["availability_policy"]["schedule_or_route_only_eligible"] =
        true
    restamp!(schedule_only)
    @test_throws ProspectiveContractValidationError validate_contract(
        schedule_only,
    )

    short_actions = checked_contract()
    short_actions["retention"]["github_actions_artifact_only_allowed"] = true
    restamp!(short_actions)
    @test_throws ProspectiveContractValidationError validate_contract(
        short_actions,
    )

    calendar_drift = checked_contract()
    calendar_drift["fixed_events"][4]["scheduled_timestamp_utc"] =
        "2026-09-11T16:00:01Z"
    calendar_drift["fixed_events"][4]["capture_not_before_utc"] =
        "2026-09-11T16:00:01Z"
    restamp!(calendar_drift)
    @test_throws ProspectiveContractValidationError validate_contract(
        calendar_drift,
    )

    deadline_drift = checked_contract()
    deadline_drift["fixed_events"][7]["capture_deadline_utc"] =
        "2026-10-29T13:01:00Z"
    restamp!(deadline_drift)
    @test_throws ProspectiveContractValidationError validate_contract(
        deadline_drift,
    )

    requirement_drift = checked_contract()
    requirement_drift["fixed_events"][7]["requirement_ids"] =
        ["bls_employment_tier1"]
    restamp!(requirement_drift)
    @test_throws ProspectiveContractValidationError validate_contract(
        requirement_drift,
    )

    completeness_drift = checked_contract()
    completeness_drift["fixed_events"][7][
        "required_for_complete_origin",
    ] = false
    restamp!(completeness_drift)
    @test_throws ProspectiveContractValidationError validate_contract(
        completeness_drift,
    )

    wrong_status = checked_contract()
    wrong_status["artifact"]["status"] =
        "GOVERNANCE_ACTIVE_ORIGIN_NOT_ADMITTED"
    restamp!(wrong_status)
    @test_throws ProspectiveContractValidationError validate_contract(
        wrong_status,
    )

    wrong_requirement = candidate_receipt(
        requirement_id = "bls_employment_tier1",
    )
    @test_throws ProspectiveContractValidationError validate_receipt(
        checked_contract(),
        wrong_requirement,
    )

    post_origin_revision_window = candidate_receipt(
        event_id = "frbny_effr_daily_revision_check",
        requirement_id = "frbny_effr_tier1",
        retrieved_at_utc = "2026-10-30T18:30:01Z",
        receipt_completed_at_utc = "2026-10-30T18:30:03Z",
    )
    @test_throws ProspectiveContractValidationError validate_receipt(
        checked_contract(),
        post_origin_revision_window,
    )

    route_only_receipt = candidate_receipt()
    route_only_receipt["availability_basis"] = "OFFICIAL_SCHEDULE_ONLY"
    @test_throws ProspectiveContractValidationError validate_receipt(
        checked_contract(),
        route_only_receipt,
    )

    bad_hash = candidate_receipt()
    bad_hash["raw_sha256"] = "not-a-hash"
    @test_throws ProspectiveContractValidationError validate_receipt(
        checked_contract(),
        bad_hash,
    )
end
