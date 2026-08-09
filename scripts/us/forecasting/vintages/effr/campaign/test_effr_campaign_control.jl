using Dates
using SHA
using Test

include(joinpath(@__DIR__, "USEFFRCampaignControl.jl"))
using .USEFFRCampaignControl

digest(value) = bytes2hex(sha256(String(value)))

timestamp(value::DateTime) = string(value) * ".000Z"

function fixture_validation(
        schedule,
        publication_date,
        phase;
        current_state_absent = false,
        revision_candidate = false,
        predecessor_bundle = "NOT_APPLICABLE",
        predecessor_rate_receipt_sha256 = "NONE",
        predecessor_volume_receipt_sha256 = "NONE",
        identity_tag = "$publication_date-$phase",
    )
    authorization = USEFFRCampaignControl._capture_authorization(
        schedule,
        publication_date,
        phase,
    )
    first = authorization.phase == "first"
    status = if current_state_absent && first
        "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
    elseif first
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
    elseif revision_candidate
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE"
    elseif current_state_absent
        "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
    else
        "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
    end
    receipt_created = status in (
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE",
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE",
    )
    rate_receipt_sha256 =
        receipt_created ? digest("$identity_tag-rate-receipt") : "NONE"
    volume_receipt_sha256 =
        receipt_created ? digest("$identity_tag-volume-receipt") : "NONE"
    failure_code =
        status ==
        "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE" ?
        "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT" :
        "NONE"
    blockers = [
        "CAPTURE_CLOCK_HOST_OBSERVATION_ONLY",
        "ORIGIN_ADMISSION_FORBIDDEN",
    ]
    failure_code == "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT" &&
        push!(
        blockers,
        "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT",
    )
    effective = string(authorization.effective_date)
    state_source = current_state_absent ?
        "ABSENT_FROM_RAW_RESPONSE_NOT_DERIVED" :
        "RAW_FIELD_FALSE"
    state_value = current_state_absent ? "ABSENT" : "false"
    manifest = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-effr-synthetic-campaign-fixture.v1",
            "manifest_id" => "fixture.$identity_tag",
            "manifest_sha256" => digest("$identity_tag-manifest"),
        ),
        "contract_binding" => Dict{String, Any}(
            "prospective_contract_id" =>
                "beforeit-us-prospective-2026q3-acquisition.v2",
            "prospective_contract_content_sha256" =>
                "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a",
            "prospective_contract_file_sha256" =>
                "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f",
            "prospective_contract_status" =>
                "DRAFT_UNAPPROVED_FAIL_CLOSED",
        ),
        "event" => Dict{String, Any}(
            "campaign_id" =>
                "frbny_effr_daily_first_state_and_revision_check",
            "phase" => authorization.phase,
            "publication_date" => string(authorization.publication_date),
            "effective_date" => effective,
            "scheduled_time_utc" =>
                timestamp(authorization.window_start_utc),
            "capture_deadline_utc" =>
                timestamp(authorization.window_deadline_utc),
            "state_class_candidate" =>
                authorization.state_class_candidate,
        ),
        "capture" => Dict{String, Any}(
            "transaction_id" => "fixture-$identity_tag",
        ),
        "objects" => [
            Dict{String, Any}(
                    "object_id" => "$(report_type)_response",
                    "canonical_query" =>
                    "endDate=$effective&startDate=$effective&type=$report_type",
                    "requested_url" =>
                    "https://markets.newyorkfed.org/api/rates/all/search.json?endDate=$effective&startDate=$effective&type=$report_type",
                ) for report_type in ("rate", "volume")
        ],
        "row_identity" => [
            Dict{String, Any}(
                    "report_type" => report_type,
                    "raw_current_state_present" => !current_state_absent,
                    "raw_current_state_value" => state_value,
                    "current_state_source" => state_source,
                    "alias_or_first_row_fallback_used" => false,
                ) for report_type in ("rate", "volume")
        ],
        "result" => Dict{String, Any}(
            "status" => status,
            "success" => true,
            "raw_capture_complete" => true,
            "failure_code" => failure_code,
            "rate_receipt_file" =>
                rate_receipt_sha256 == "NONE" ?
                "NONE" :
                "rate-receipt.toml",
            "volume_receipt_file" =>
                volume_receipt_sha256 == "NONE" ?
                "NONE" :
                "volume-receipt.toml",
            "rate_receipt_sha256" => rate_receipt_sha256,
            "volume_receipt_sha256" => volume_receipt_sha256,
            "predecessor_bundle" => predecessor_bundle,
            "predecessor_rate_receipt_sha256" =>
                predecessor_rate_receipt_sha256,
            "predecessor_volume_receipt_sha256" =>
                predecessor_volume_receipt_sha256,
            "revision_observed" => revision_candidate,
            "revision_receipt_created" => revision_candidate,
            "one_date_receipt_validated" => receipt_created,
        ),
        "blockers" => blockers,
        "gates" => Dict{String, Any}(
            "accuracy_evaluation_allowed" => false,
            "empirical_forecast_allowed" => false,
            "historical_first_byte_proven" => false,
            "origin_admissible" => false,
            "production_scoring_allowed" => false,
            "promotion_eligible" => false,
            "readiness" => false,
            "source_inventory_mutation_allowed" => false,
        ),
    )
    bundle_path =
        abspath(joinpath("/fixture", publication_date, phase, identity_tag))
    return validated_bundle_manifest((; bundle_path, manifest))
end

function full_campaign(schedule; current_state_absent = false)
    bundles = ValidatedBundleManifest[]
    for row in schedule["days"]
        publication = row["publication_date"]
        first = fixture_validation(
            schedule,
            publication,
            "first";
            current_state_absent,
        )
        push!(bundles, first)
        row["revision_check_required"] || continue
        first_result = first.manifest["result"]
        push!(
            bundles,
            fixture_validation(
                schedule,
                publication,
                "revision-check";
                current_state_absent,
                predecessor_bundle = first.bundle_path,
                predecessor_rate_receipt_sha256 =
                    first_result["rate_receipt_sha256"],
                predecessor_volume_receipt_sha256 =
                    first_result["volume_receipt_sha256"],
            ),
        )
    end
    return bundles
end

@testset "frozen schedule and authorization" begin
    schedule = load_schedule()
    validation = validate_schedule(schedule)
    @test validation.schedule_id ==
        "beforeit-us-effr-2026q3-prospective-campaign.v1"
    @test validation.content_sha256 ==
        "fb984becfc5608922cd4acffd7e3e3bdf997022935f816acad221ec32dcd0383"
    @test validation.first_state_count == 59
    @test validation.revision_check_count == 58
    @test validation.slot_count == 117
    @test length(schedule["days"]) == 59
    @test first(schedule["days"])["publication_date"] == "2026-08-07"
    @test first(schedule["days"])["effective_date"] == "2026-08-06"
    @test last(schedule["days"])["publication_date"] == "2026-10-30"
    @test last(schedule["days"])["effective_date"] == "2026-10-29"
    @test last(schedule["days"])["revision_check_required"] === false
    @test !any(
        row["publication_date"] in ("2026-09-07", "2026-10-12") for
            row in schedule["days"]
    )
    @test all(
        dayofweek(Date(row["publication_date"])) <= 5 for
            row in schedule["days"]
    )
    labor_day = capture_authorization(schedule, "2026-09-08", "first")
    @test labor_day.sequence == 22
    @test labor_day.effective_date == Date(2026, 9, 4)
    @test labor_day.window_start_utc == DateTime(2026, 9, 8, 13)
    @test labor_day.window_deadline_utc ==
        DateTime(2026, 9, 8, 13, 15)
    @test labor_day.network_execution_authorized === false
    @test labor_day.raw_data_write_authorized === false
    @test labor_day.inventory_mutation_authorized === false
    @test labor_day.origin_admissible === false
    october = capture_authorization(schedule, "2026-10-13", "revision-check")
    @test october.effective_date == Date(2026, 10, 9)
    @test october.window_start_utc == DateTime(2026, 10, 13, 18, 30)
    @test capture_authorization(
        schedule,
        "2026-08-10",
        "first";
        observed_at_utc = "2026-08-10T13:15:00Z",
    ).publication_date == Date(2026, 8, 10)
    @test_throws CampaignControlError capture_authorization(
        schedule,
        "2026-08-08",
        "first",
    )
    @test_throws CampaignControlError capture_authorization(
        schedule,
        "2026-09-07",
        "first",
    )
    @test_throws CampaignControlError capture_authorization(
        schedule,
        "2026-10-30",
        "revision-check",
    )
    @test_throws CampaignControlError capture_authorization(
        schedule,
        "2026-08-10",
        "first";
        observed_at_utc = "2026-08-10T12:59:59Z",
    )
    @test_throws CampaignControlError capture_authorization(
        schedule,
        "2026-08-10",
        "first";
        observed_at_utc = "2026-08-10T13:15:01Z",
    )
    @test_throws CampaignControlError capture_authorization(
        schedule,
        "2026-08-10",
        1,
    )

    tampered = deepcopy(schedule)
    tampered["policy"]["first_scheduled_time_utc"] = "13:01:00Z"
    tampered["policy"]["first_deadline_time_utc"] = "13:16:00Z"
    tampered["artifact"]["content_sha256"] =
        computed_schedule_sha256(tampered)
    @test_throws CampaignControlError validate_schedule(tampered)

    broken_chain = deepcopy(schedule)
    broken_chain["days"][22]["effective_date"] = "2026-09-07"
    broken_chain["artifact"]["content_sha256"] =
        computed_schedule_sha256(broken_chain)
    @test_throws CampaignControlError validate_schedule(broken_chain)

    invented_holiday = deepcopy(schedule)
    invented_holiday["policy"]["excluded_dates"] =
        ["2026-09-07", "2026-10-12", "2026-10-19"]
    invented_holiday["artifact"]["content_sha256"] =
        computed_schedule_sha256(invented_holiday)
    @test_throws CampaignControlError validate_schedule(invented_holiday)
end

@testset "manifest semantics remain fail closed" begin
    schedule = load_schedule()
    first = fixture_validation(
        schedule,
        "2026-08-07",
        "first";
        current_state_absent = true,
    )
    result = evaluate_campaign(schedule, [first])
    @test result.status == "CAMPAIGN_CONTROL_INCOMPLETE"
    @test result.accepted_slot_count == 1
    @test length(result.missing_slot_ids) == 116
    @test result.compatibility_blocker_slot_ids == ["2026-08-07:first"]
    @test result.raw_capture_coverage_complete === false
    @test result.receipt_semantics_complete === false
    @test result.profile_complete === false
    @test result.profile_completion_authorized === false
    @test result.inventory_mutation_authorized === false
    @test result.origin_admissible === false
    @test result.accuracy_evaluation_allowed === false
    @test result.promotion_eligible === false
    @test result.production_scoring_allowed === false
    @test result.ready === false

    fabricated = deepcopy(first)
    fabricated.manifest["row_identity"][1][
        "raw_current_state_value",
    ] = "false"
    fabricated_result = evaluate_campaign(schedule, [fabricated])
    @test fabricated_result.status == "CAMPAIGN_CONTROL_INVALID"
    @test length(fabricated_result.rejected_bundles) == 1
    @test occursin(
        "expected \"ABSENT\", got \"false\"",
        only(fabricated_result.rejected_bundles),
    )

    relabeled = deepcopy(first)
    relabeled.manifest["result"]["status"] =
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
    relabeled.manifest["result"]["failure_code"] = "NONE"
    filter!(
        !=("ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT"),
        relabeled.manifest["blockers"],
    )
    relabeled_result = evaluate_campaign(schedule, [relabeled])
    @test relabeled_result.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "may not derive absent currentState as false",
        only(relabeled_result.rejected_bundles),
    )

    wrong_effective = deepcopy(first)
    wrong_effective.manifest["event"]["effective_date"] = "2026-08-05"
    @test evaluate_campaign(
        schedule,
        [wrong_effective],
    ).status == "CAMPAIGN_CONTROL_INVALID"

    wrong_query = deepcopy(first)
    wrong_query.manifest["objects"][1]["canonical_query"] =
        "endDate=2026-08-05&startDate=2026-08-05&type=rate"
    @test evaluate_campaign(
        schedule,
        [wrong_query],
    ).status == "CAMPAIGN_CONTROL_INVALID"

    wrong_contract = deepcopy(first)
    wrong_contract.manifest["contract_binding"][
        "prospective_contract_content_sha256",
    ] = digest("wrong")
    @test evaluate_campaign(
        schedule,
        [wrong_contract],
    ).status == "CAMPAIGN_CONTROL_INVALID"

    opened_gate = deepcopy(first)
    opened_gate.manifest["gates"]["origin_admissible"] = true
    @test evaluate_campaign(
        schedule,
        [opened_gate],
    ).status == "CAMPAIGN_CONTROL_INVALID"
end

@testset "frozen status and result matrix" begin
    schedule = load_schedule()
    first = fixture_validation(schedule, "2026-08-07", "first")
    first_result = first.manifest["result"]
    revision = fixture_validation(
        schedule,
        "2026-08-07",
        "revision-check";
        predecessor_bundle = first.bundle_path,
        predecessor_rate_receipt_sha256 =
            first_result["rate_receipt_sha256"],
        predecessor_volume_receipt_sha256 =
            first_result["volume_receipt_sha256"],
    )
    valid_no_revision = evaluate_campaign(schedule, [first, revision])
    @test valid_no_revision.status == "CAMPAIGN_CONTROL_INCOMPLETE"
    @test valid_no_revision.accepted_slot_count == 2
    @test isempty(valid_no_revision.rejected_bundles)
    @test isempty(valid_no_revision.predecessor_failures)

    revision_candidate = fixture_validation(
        schedule,
        "2026-08-07",
        "revision-check";
        revision_candidate = true,
        predecessor_bundle = first.bundle_path,
        predecessor_rate_receipt_sha256 =
            first_result["rate_receipt_sha256"],
        predecessor_volume_receipt_sha256 =
            first_result["volume_receipt_sha256"],
        identity_tag = "valid-revision-candidate",
    )
    valid_revision =
        evaluate_campaign(schedule, [first, revision_candidate])
    @test valid_revision.accepted_slot_count == 2
    @test isempty(valid_revision.rejected_bundles)
    @test isempty(valid_revision.predecessor_failures)

    first_on_revision = deepcopy(revision)
    result = first_on_revision.manifest["result"]
    result["status"] =
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
    result["one_date_receipt_validated"] = true
    result["rate_receipt_file"] = "rate-receipt.toml"
    result["volume_receipt_file"] = "volume-receipt.toml"
    result["rate_receipt_sha256"] = digest("first-on-revision-rate")
    result["volume_receipt_sha256"] = digest("first-on-revision-volume")
    rejected = evaluate_campaign(schedule, [first_on_revision])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "first-state candidate requires phase first",
        only(rejected.rejected_bundles),
    )

    revision_on_first = deepcopy(first)
    result = revision_on_first.manifest["result"]
    result["status"] =
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE"
    result["revision_observed"] = true
    result["revision_receipt_created"] = true
    rejected = evaluate_campaign(schedule, [revision_on_first])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "revision candidate requires phase revision-check",
        only(rejected.rejected_bundles),
    )

    wrong_present_source = deepcopy(first)
    wrong_present_source.manifest["row_identity"][1][
        "current_state_source",
    ] = "RAW_RESPONSE_FIELD"
    rejected = evaluate_campaign(schedule, [wrong_present_source])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "expected \"RAW_FIELD_FALSE\"",
        only(rejected.rejected_bundles),
    )

    byte_with_receipt = deepcopy(revision)
    byte_with_receipt.manifest["result"]["rate_receipt_file"] =
        "invented.toml"
    rejected = evaluate_campaign(schedule, [byte_with_receipt])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "rate_receipt_file",
        only(rejected.rejected_bundles),
    )

    byte_with_hash = deepcopy(revision)
    byte_with_hash.manifest["result"]["rate_receipt_sha256"] =
        digest("invented")
    rejected = evaluate_campaign(schedule, [byte_with_hash])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "rate_receipt_sha256",
        only(rejected.rejected_bundles),
    )

    byte_observed_revision = deepcopy(revision)
    byte_observed_revision.manifest["result"]["revision_observed"] = true
    rejected = evaluate_campaign(schedule, [byte_observed_revision])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "cannot observe a revision",
        only(rejected.rejected_bundles),
    )

    byte_with_one_date = deepcopy(revision)
    byte_with_one_date.manifest["result"][
        "one_date_receipt_validated",
    ] = true
    rejected = evaluate_campaign(schedule, [byte_with_one_date])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "one_date_receipt_validated",
        only(rejected.rejected_bundles),
    )

    first_without_one_date = deepcopy(first)
    first_without_one_date.manifest["result"][
        "one_date_receipt_validated",
    ] = false
    rejected = evaluate_campaign(schedule, [first_without_one_date])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "requires one-date receipts",
        only(rejected.rejected_bundles),
    )

    first_with_revision = deepcopy(first)
    first_with_revision.manifest["result"]["revision_receipt_created"] =
        true
    rejected = evaluate_campaign(schedule, [first_with_revision])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "cannot create revision receipts",
        only(rejected.rejected_bundles),
    )

    first_without_hash = deepcopy(first)
    first_without_hash.manifest["result"]["rate_receipt_sha256"] = "NONE"
    rejected = evaluate_campaign(schedule, [first_without_hash])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "lowercase SHA-256",
        only(rejected.rejected_bundles),
    )

    revision_without_predecessor_hash = deepcopy(revision_candidate)
    revision_without_predecessor_hash.manifest["result"][
        "predecessor_rate_receipt_sha256",
    ] = "NONE"
    rejected =
        evaluate_campaign(schedule, [revision_without_predecessor_hash])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "lowercase SHA-256",
        only(rejected.rejected_bundles),
    )

    incompatible = fixture_validation(
        schedule,
        "2026-08-07",
        "first";
        current_state_absent = true,
    )
    incompatible.manifest["result"]["rate_receipt_sha256"] =
        digest("invented-incompatible-receipt")
    rejected = evaluate_campaign(schedule, [incompatible])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "rate_receipt_sha256",
        only(rejected.rejected_bundles),
    )

    numeric_manifest_phase = deepcopy(first)
    numeric_manifest_phase.manifest["event"]["phase"] = 1
    rejected = evaluate_campaign(schedule, [numeric_manifest_phase])
    @test rejected.status == "CAMPAIGN_CONTROL_INVALID"
    @test occursin(
        "must be the string first or revision-check",
        only(rejected.rejected_bundles),
    )
end

@testset "duplicates, identities, and predecessor chain" begin
    schedule = load_schedule()
    first = fixture_validation(schedule, "2026-08-07", "first")
    duplicate = evaluate_campaign(schedule, [first, deepcopy(first)])
    @test duplicate.status == "CAMPAIGN_CONTROL_INVALID"
    @test duplicate.duplicate_slot_ids == ["2026-08-07:first"]
    @test duplicate.accepted_slot_count == 0

    revision_without_first = fixture_validation(
        schedule,
        "2026-08-07",
        "revision-check";
        predecessor_bundle = first.bundle_path,
        predecessor_rate_receipt_sha256 =
            first.manifest["result"]["rate_receipt_sha256"],
        predecessor_volume_receipt_sha256 =
            first.manifest["result"]["volume_receipt_sha256"],
    )
    orphan = evaluate_campaign(schedule, [revision_without_first])
    @test orphan.status == "CAMPAIGN_CONTROL_INVALID"
    @test orphan.predecessor_failures ==
        ["2026-08-07:revision-check:MISSING_FIRST_STATE"]

    wrong_predecessor = deepcopy(revision_without_first)
    wrong_predecessor.manifest["result"]["predecessor_bundle"] =
        "/fixture/wrong"
    linked = evaluate_campaign(schedule, [first, wrong_predecessor])
    @test linked.status == "CAMPAIGN_CONTROL_INVALID"
    @test linked.predecessor_failures ==
        ["2026-08-07:revision-check:PREDECESSOR_PATH_MISMATCH"]

    alias = fixture_validation(schedule, "2026-08-10", "first")
    alias.manifest["artifact"]["manifest_sha256"] =
        first.manifest["artifact"]["manifest_sha256"]
    alias_result = evaluate_campaign(schedule, [first, alias])
    @test alias_result.status == "CAMPAIGN_CONTROL_INVALID"
    @test length(alias_result.identity_failures) == 1
    @test occursin("manifest_sha256", only(alias_result.identity_failures))
end

@testset "full offline coverage never admits an origin" begin
    schedule = load_schedule()
    complete = evaluate_campaign(schedule, full_campaign(schedule))
    @test complete.status ==
        "LOCAL_RECEIPT_COVERAGE_CANDIDATE_NONADMITTING"
    @test complete.expected_slot_count == 117
    @test complete.accepted_slot_count == 117
    @test isempty(complete.missing_slot_ids)
    @test isempty(complete.unexpected_slot_ids)
    @test isempty(complete.duplicate_slot_ids)
    @test isempty(complete.rejected_bundles)
    @test isempty(complete.identity_failures)
    @test isempty(complete.predecessor_failures)
    @test isempty(complete.compatibility_blocker_slot_ids)
    @test complete.raw_capture_coverage_complete === true
    @test complete.receipt_semantics_complete === true
    @test complete.profile_complete === false
    @test complete.profile_completion_authorized === false
    @test complete.inventory_mutation_authorized === false
    @test complete.origin_admissible === false
    @test complete.accuracy_evaluation_allowed === false
    @test complete.promotion_eligible === false
    @test complete.production_scoring_allowed === false
    @test complete.ready === false

    blocked = evaluate_campaign(
        schedule,
        full_campaign(schedule; current_state_absent = true),
    )
    @test blocked.status ==
        "RAW_CAPTURE_COVERAGE_COMPLETE_RECEIPT_SEMANTICS_BLOCKED"
    @test blocked.accepted_slot_count == 117
    @test length(blocked.compatibility_blocker_slot_ids) == 117
    @test blocked.raw_capture_coverage_complete === true
    @test blocked.receipt_semantics_complete === false
    @test blocked.profile_complete === false
    @test blocked.origin_admissible === false
    @test blocked.ready === false
end
