#!/usr/bin/env julia

using Test
using Dates
using TOML

include(joinpath(@__DIR__, "USHistoricalBackfillPlan.jl"))
using .USHistoricalBackfillPlan
include(joinpath(@__DIR__, "..", "contracts", "USForecastProtocol.jl"))
include(joinpath(@__DIR__, "..", "targets", "USTier1TargetCoverage.jl"))

const PLAN_PATH = joinpath(@__DIR__, "historical_backfill_plan.toml")
const INVENTORY_PATH = joinpath(@__DIR__, "current_inventory.toml")
const PROTOCOL_PATH = joinpath(@__DIR__, "..", "protocol.toml")
const TIER1_TARGETS_PATH =
    joinpath(@__DIR__, "..", "targets", "tier1_targets.toml")

function checked_plan()
    return load_backfill_plan(PLAN_PATH)
end

function restamp!(plan)
    stamp_backfill_plan_sha256!(plan)
    return plan
end

function source_route(plan, route_id)
    return only(
        route for route in plan["source_routes"] if
            route["route_id"] == route_id
    )
end

function pilot_origin(plan, pilot_id)
    return only(
        pilot for pilot in plan["pilot_origins"] if
            pilot["pilot_id"] == pilot_id
    )
end

@testset "checked-in historical backfill plan is fail closed" begin
    plan = checked_plan()
    inventory = TOML.parsefile(INVENTORY_PATH)

    @test validate_backfill_plan(plan) === plan
    @test validate_inventory_alignment(plan, inventory) === inventory
    @test plan["artifact"]["status"] == "PLAN_ONLY_NOT_ACQUIRED"
    @test plan["artifact"]["content_sha256"] == backfill_plan_sha256(plan)
    @test validate_prospective_capture_deadline(
        plan,
        DateTime(2026, 8, 5, 22),
    ) == DateTime(2026, 8, 5, 22)
    @test validate_contract_alignment(
        plan,
        USForecastProtocol.protocol_sha256(
            USForecastProtocol.load_protocol(PROTOCOL_PATH),
        ),
        USTier1TargetCoverage.inventory_sha256(
            USTier1TargetCoverage.load_inventory(TIER1_TARGETS_PATH),
        ),
    ) === plan
    @test plan["artifact"]["protocol_sha256"] ==
        USForecastProtocol.protocol_sha256(
        USForecastProtocol.load_protocol(PROTOCOL_PATH),
    )
    @test plan["artifact"]["tier1_targets_sha256"] ==
        USTier1TargetCoverage.inventory_sha256(
        USTier1TargetCoverage.load_inventory(TIER1_TARGETS_PATH),
    )
    @test plan["admission"]["strict_retrospective_origin_count"] == 0
    @test isempty(
        plan["admission"]["strict_retrospective_origin_timestamps_utc"],
    )
    @test !plan["admission"]["accuracy_evaluation_allowed"]
    @test isempty(inventory["release_events"])
    @test isempty(inventory["admissible_origin_timestamps_utc"])
    @test plan["inventory_guard"]["expected_inventory_sha256"] ==
        inventory["artifact"]["content_sha256"]
end

@testset "reconstruction and planned prospective origin stay non-admissible" begin
    plan = checked_plan()
    reconstructed = pilot_origin(plan, "2026q2_reconstructed")
    prospective = pilot_origin(plan, "2026q3_prospective")

    @test reconstructed["origin_timestamp_utc"] == "2026-07-31T14:00:00Z"
    @test reconstructed["evidence_class"] == "reconstructed_after_origin"
    @test reconstructed["admission_status"] == "CANNOT_RUN"
    @test !reconstructed["runnable"]
    @test !reconstructed["promotion_eligible"]
    @test plan["admission"][
        "planned_first_prospective_trigger_release_timestamp_utc",
    ] == "2026-10-29T12:30:00Z"
    @test plan["admission"][
        "reconstruction_trigger_release_timestamp_utc",
    ] == "2026-07-30T12:30:00Z"
    @test plan["admission"][
        "reconstruction_trigger_release_timestamp_local",
    ] == "2026-07-30T08:30:00"
    @test plan["admission"]["reconstruction_only_origin_timestamp_local"] ==
        "2026-07-31T10:00:00"
    @test plan["admission"][
        "planned_first_prospective_trigger_release_timestamp_local",
    ] == "2026-10-29T08:30:00"
    @test plan["admission"][
        "planned_first_prospective_origin_timestamp_local",
    ] == "2026-10-30T10:00:00"
    @test prospective["origin_timestamp_utc"] == "2026-10-30T14:00:00Z"
    @test plan["admission"]["planned_first_prospective_origin_rule"] ==
        "FIRST_BUSINESS_DAY_AFTER_BEA_ADVANCE_AT_10:00_AMERICA/NEW_YORK"
    @test plan["admission"][
        "planned_first_prospective_schedule_locator",
    ] == "https://www.bea.gov/news/schedule"
    @test plan["admission"][
        "planned_first_prospective_schedule_locator_role",
    ] == "MUTABLE_OFFICIAL_DISCOVERY_ROUTE_NOT_IMMUTABLE_EVENT_EVIDENCE"
    @test plan["admission"][
        "planned_first_prospective_schedule_revalidation_required",
    ]
    @test plan["admission"]["timing_conversion_method"] ==
        "AUDITED_FIXED_UTC_OFFSET_NO_IANA_RUNTIME"
    @test plan["admission"]["timing_utc_offset_seconds"] == -14400
    @test prospective["admission_status"] ==
        "PLANNED_NOT_CAPTURED_NOT_ADMITTED"
    @test !prospective["runnable"]
    @test !prospective["promotion_eligible"]
    @test prospective["origin_timestamp_utc"] ∉
        plan["admission"]["strict_retrospective_origin_timestamps_utc"]

    for (pilot_id, quarter) in (
            ("2008q3_gap_probe", "2008Q3"),
            ("2019q4_reconstructed", "2019Q4"),
            ("2020q1_reconstructed", "2020Q1"),
            ("2021q2_reconstructed", "2021Q2"),
            ("2026q2_reconstructed", "2026Q2"),
            ("2026q3_prospective", "2026Q3"),
        )
        @test pilot_origin(plan, pilot_id)["reference_quarter"] == quarter
    end

    first_broad_diagnostic = pilot_origin(plan, "2019q4_reconstructed")
    @test first_broad_diagnostic["origin_timestamp_status"] ==
        "NOT_ESTABLISHED"
    @test first_broad_diagnostic["origin_timestamp_utc"] == "NOT_ESTABLISHED"
    @test first_broad_diagnostic["admission_status"] == "CANNOT_RUN"
    @test !first_broad_diagnostic["runnable"]
    @test !first_broad_diagnostic["promotion_eligible"]
end

@testset "prospective capture clock fails at both receipt boundaries" begin
    plan = checked_plan()
    @test USHistoricalBackfillPlan.next_business_day(
        Date(2026, 10, 9),
    ) == Date(2026, 10, 13)
    @test USHistoricalBackfillPlan.next_business_day(
        Date(2026, 10, 29),
    ) == Date(2026, 10, 30)
    @test validate_prospective_capture_deadline(
        plan,
        DateTime(2026, 10, 29, 12, 29, 59),
    ) == DateTime(2026, 10, 29, 12, 29, 59)
    @test_throws BackfillPlanValidationError validate_prospective_capture_deadline(
        plan,
        DateTime(2026, 10, 29, 12, 30),
    )
    @test_throws BackfillPlanValidationError validate_prospective_capture_deadline(
        plan,
        DateTime(2026, 10, 30, 13, 59, 59),
    )
    @test_throws BackfillPlanValidationError validate_prospective_capture_deadline(
        plan,
        DateTime(2026, 10, 30, 14),
    )
    @test_throws BackfillPlanValidationError validate_prospective_capture_deadline(
        plan,
        DateTime(2026, 10, 31),
    )

    fake_trigger_receipt = checked_plan()
    fake_trigger_receipt["admission"][
        "planned_first_prospective_trigger_capture_receipt_status",
    ] = "IMMUTABLE_TRIGGER_CAPTURE_RECEIPT_VERIFIED"
    fake_trigger_receipt["admission"][
        "planned_first_prospective_trigger_capture_receipt_count",
    ] = 1
    restamp!(fake_trigger_receipt)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        fake_trigger_receipt,
    )
end

@testset "all eight targets have explicit but uninstalled primary routes" begin
    plan = checked_plan()
    bea = source_route(plan, "bea_nipa_hmi7")
    ces = source_route(plan, "bls_ces_employment_situation")
    cps = source_route(plan, "bls_cps_employment_situation")
    effr = source_route(plan, "frbny_effr")

    @test Set(bea["target_ids"]) == Set(
        [
            "core_pce_price_index",
            "gdp_deflator",
            "nominal_gdp",
            "pce_price_index",
            "real_gdp",
        ],
    )
    @test bea["archive_start"] ==
        "2002Q2_FINAL_ONLY_2002Q3_FULL_SEQUENCE"
    @test ces["archive_start"] == "2003-05"
    @test ces["first_state_status"] ==
        "FIRST_PRELIMINARY_VALUES_DOCUMENTED_SINCE_2003-05"
    @test cps["target_ids"] == ["unemployment_rate"]
    @test effr["target_ids"] == ["effective_federal_funds_rate"]

    mapped_targets = String[]
    for route in plan["source_routes"]
        append!(mapped_targets, route["target_ids"])
        @test route["locator_role"] ==
            "OFFICIAL_DISCOVERY_ROUTE_NOT_EXACT_RELEASE_BYTE_IDENTITY"
        @test route["exact_release_byte_locator_status"] ==
            "UNRESOLVED_NOT_REGISTERED"
        @test route["registered_release_event_count"] == 0
        @test !route["release_bytes_registered"]
        @test !route["origin_admissible"]
    end
    @test sort(mapped_targets) == sort(
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
    @test length(unique(mapped_targets)) == 8
end

@testset "timestamp precision and structural blockers remain explicit" begin
    plan = checked_plan()
    classes = Dict(
        route["route_id"] => route["timestamp_evidence_class"] for
            route in plan["source_routes"]
    )

    @test classes["bea_nipa_hmi7"] == "exact_intraday_route_only"
    @test classes["frb_z1"] == "mixed_event_level"
    @test classes["bea_fixed_assets_hmi11"] == "date_only"
    @test classes["bls_qcew"] == "date_only"
    @test classes["census_susb"] == "no_time"
    @test classes["bls_cps_structural_controls"] == "no_time"
    @test classes["frbny_effr"] == "historical_first_state_unverified"
    @test !plan["precision_policy"]["date_only_origin_eligible"]
    @test !plan["precision_policy"]["no_time_origin_eligible"]
    @test !plan["precision_policy"][
        "mixed_precision_origin_eligible_without_event_resolution",
    ]
    @test !plan["precision_policy"][
        "retrieval_time_may_substitute_for_release_time",
    ]

    for route_id in (
            "bls_cps_structural_controls",
            "bls_qcew",
            "census_susb",
        )
        @test source_route(plan, route_id)["route_status"] ==
            "STRUCTURAL_BLOCKED"
    end

    z1 = source_route(plan, "frb_z1")
    @test z1["archive_start"] == "1996Q2"
    @test z1["published_artifact_formats"] ==
        ["csv_from_2016", "html_after_2004", "pdf_from_1996Q2"]

    effr = source_route(plan, "frbny_effr")
    @test effr["archive_start"] == "2000-07-03"
    @test effr["first_state_status"] ==
        "NO_COMPLETE_HISTORICAL_FIRST_STATE_ARCHIVE"
    @test effr["method_break"] == "2016-03-01_CALCULATION_METHOD_CHANGE"
    @test effr["route_status"] == "PROSPECTIVE_CAPTURE_REQUIRED"
    @test effr["series_identifiers"] == ["FRBNY:EFFR"]
    @test source_route(plan, "bea_nipa_hmi7")["archive_identifier"] ==
        "BEA_HMI_7"
    @test source_route(plan, "bea_nipa_hmi7")["discovery_schema"] ==
        "BEA_HISTDATA_FEA_DISPLAY_CHILDREN_C_JSON"
    @test source_route(plan, "bea_nipa_hmi7")["series_identifiers"] ==
        [
        "NIPA:T10105:line1:A191RC",
        "NIPA:T10106:line1:A191RX",
        "NIPA:T10109:line1:A191RD",
        "NIPA:T20304:line1:DPCERG",
        "NIPA:T20304:line25:DPCCRG",
    ]
end

@testset "source-use policies remain explicit and fail closed" begin
    licensing = checked_plan()["licensing"]
    @test licensing["fred_alfred_warehouse_status"] ==
        "EXCLUDED_PENDING_WRITTEN_CLEARANCE"
    @test licensing["written_clearance_required"]
    @test !licensing["cache_allowed_without_clearance"]
    @test !licensing["archive_allowed_without_clearance"]
    @test !licensing["software_or_ai_use_allowed_without_clearance"]
    @test licensing["rtdsm_role"] ==
        "CROSS_CHECK_ONLY_NOT_INTRADAY_AVAILABILITY_EVIDENCE"
    @test licensing["fred_alfred_terms_locator"] ==
        "https://fred.stlouisfed.org/legal/terms/"
    @test licensing["fred_alfred_terms_recheck_before_use"]
    @test licensing["bea_terms_locator"] ==
        "https://www.bea.gov/index.php/help/faq/145"
    @test licensing["bea_terms_review_as_of_date"] == "2026-08-05"
    @test licensing["bea_terms_recheck_before_acquisition"]
    @test licensing["bea_public_domain_status"] ==
        "PUBLIC_DOMAIN_UNLESS_OTHERWISE_STATED"
    @test licensing["bea_attribution_policy"] ==
        "SOURCE_ATTRIBUTION_APPRECIATED_AND_REQUIRED_BY_THIS_PLAN"
    @test licensing["bls_copyright_locator"] ==
        "https://www.bls.gov/opub/copyright-information.htm"
    @test licensing["bls_developer_terms_locator"] ==
        "https://www.bls.gov/developers/termsOfService.htm"
    @test licensing["bls_terms_review_as_of_date"] == "2026-08-06"
    @test licensing["bls_terms_recheck_before_acquisition"]
    @test licensing["bls_public_domain_status"] ==
        "PUBLIC_DOMAIN_EXCEPT_PREVIOUSLY_COPYRIGHTED_PHOTOGRAPHS_AND_ILLUSTRATIONS"
    @test licensing["bls_attribution_policy"] ==
        "CITE_BLS_SOURCE_ACCESS_DATE_AND_API_DISCLAIMER_WHEN_APPLICABLE_NO_EMBLEM"
    @test licensing["bls_api_access_date_required"]
    @test licensing["bls_api_disclaimer_required"]
    @test !licensing["bls_emblem_use_allowed"]
    @test licensing["bls_plan_authorizes_byte_acquisition"]
    @test licensing["frbny_reference_rates_terms_locator"] ==
        "https://www.newyorkfed.org/privacy/termsofuse"
    @test licensing["frbny_reference_rate_notice_required"]
    @test licensing["frbny_attribution_required"]
    @test licensing["frbny_terms_recheck_before_acquisition"]
    @test !licensing["frbny_plan_authorizes_byte_acquisition"]

    plan = checked_plan()
    for route in plan["source_routes"]
        @test route["terms_review_status"] in (
            "NOT_REVIEWED_BLOCKS_BYTE_ACQUISITION",
            "REVIEWED_AS_OF_2026-08-05_RECHECK_BEFORE_ACQUISITION",
            "REVIEWED_AS_OF_2026-08-06_RECHECK_BEFORE_ACQUISITION",
        )
        @test !isempty(route["redistribution_status"])
        @test !isempty(route["attribution_requirement"])
    end
    effr = source_route(plan, "frbny_effr")
    @test effr["terms_locator"] ==
        licensing["frbny_reference_rates_terms_locator"]
    @test effr["redistribution_status"] ==
        "PERMITTED_SUBJECT_TO_CURRENT_TERMS_AND_REFERENCE_RATE_NOTICE"

    for route_id in (
            "bea_fixed_assets_hmi11",
            "bea_industry_hmi8",
            "bea_nipa_hmi7",
        )
        route = source_route(plan, route_id)
        @test route["terms_locator"] == licensing["bea_terms_locator"]
        @test route["terms_review_status"] ==
            "REVIEWED_AS_OF_2026-08-05_RECHECK_BEFORE_ACQUISITION"
        @test route["redistribution_status"] ==
            "PUBLIC_DOMAIN_UNLESS_OTHERWISE_STATED_RECHECK_FILE_SPECIFIC_NOTICES"
        @test route["attribution_requirement"] ==
            "PRESERVE_BEA_SOURCE_AND_RELEASE_IDENTIFIERS_ATTRIBUTION_APPRECIATED"
        @test !route["release_bytes_registered"]
        @test route["registered_release_event_count"] == 0
        @test !route["origin_admissible"]
    end

    for route_id in (
            "bls_ces_employment_situation",
            "bls_cps_employment_situation",
            "bls_cps_structural_controls",
            "bls_qcew",
        )
        route = source_route(plan, route_id)
        @test route["terms_locator"] == licensing["bls_copyright_locator"]
        @test route["terms_review_status"] ==
            "REVIEWED_AS_OF_2026-08-06_RECHECK_BEFORE_ACQUISITION"
        @test route["redistribution_status"] ==
            "PUBLIC_DOMAIN_EXCEPT_PREVIOUSLY_COPYRIGHTED_PHOTOGRAPHS_AND_ILLUSTRATIONS_RECHECK_FILE_SPECIFIC_NOTICES"
        @test route["attribution_requirement"] ==
            "CITE_BLS_PRESERVE_SOURCE_ACCESS_AND_RELEASE_IDENTIFIERS_NO_EMBLEM"
        @test !route["release_bytes_registered"]
        @test route["registered_release_event_count"] == 0
        @test !route["origin_admissible"]
    end
end

@testset "semantic tampering cannot create an origin or READY claim" begin
    strict_origin = checked_plan()
    strict_origin["admission"]["strict_retrospective_origin_count"] = 1
    strict_origin["admission"]["strict_retrospective_origin_timestamps_utc"] =
        ["2026-07-31T14:00:00Z"]
    restamp!(strict_origin)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        strict_origin,
    )

    runnable_reconstruction = checked_plan()
    pilot_origin(
        runnable_reconstruction,
        "2026q2_reconstructed",
    )["runnable"] = true
    restamp!(runnable_reconstruction)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        runnable_reconstruction,
    )

    promoted_reconstruction = checked_plan()
    pilot_origin(
        promoted_reconstruction,
        "2026q2_reconstructed",
    )["promotion_eligible"] = true
    restamp!(promoted_reconstruction)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        promoted_reconstruction,
    )

    admitted_prospective = checked_plan()
    admitted_prospective["admission"][
        "planned_first_prospective_admitted",
    ] = true
    restamp!(admitted_prospective)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        admitted_prospective,
    )

    ready_prospective = checked_plan()
    ready_prospective["admission"]["planned_first_prospective_ready"] = true
    restamp!(ready_prospective)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        ready_prospective,
    )

    allowed_accuracy = checked_plan()
    allowed_accuracy["admission"]["accuracy_evaluation_allowed"] = true
    restamp!(allowed_accuracy)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        allowed_accuracy,
    )
end

@testset "date-only, no-time, and missing bytes cannot masquerade as evidence" begin
    qcew_exact = checked_plan()
    source_route(qcew_exact, "bls_qcew")["timestamp_evidence_class"] =
        "exact_intraday_route_only"
    restamp!(qcew_exact)
    @test_throws BackfillPlanValidationError validate_backfill_plan(qcew_exact)

    susb_admitted = checked_plan()
    source_route(susb_admitted, "census_susb")["origin_admissible"] = true
    restamp!(susb_admitted)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        susb_admitted,
    )

    fake_bytes = checked_plan()
    bea = source_route(fake_bytes, "bea_nipa_hmi7")
    bea["release_bytes_registered"] = true
    bea["registered_release_event_count"] = 1
    restamp!(fake_bytes)
    @test_throws BackfillPlanValidationError validate_backfill_plan(fake_bytes)

    retrieval_substitution = checked_plan()
    retrieval_substitution["precision_policy"][
        "retrieval_time_may_substitute_for_release_time",
    ] = true
    restamp!(retrieval_substitution)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        retrieval_substitution,
    )

    date_only_eligible = checked_plan()
    date_only_eligible["precision_policy"]["date_only_origin_eligible"] = true
    restamp!(date_only_eligible)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        date_only_eligible,
    )
end

@testset "source facts, target mappings, and acquisition order are pinned" begin
    wrong_method = checked_plan()
    source_route(wrong_method, "frbny_effr")["method_break"] =
        "NONE_IDENTIFIED_IN_THIS_PLAN"
    restamp!(wrong_method)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        wrong_method,
    )

    wrong_locator = checked_plan()
    source_route(wrong_locator, "bea_nipa_hmi7")["discovery_locator"] =
        "https://example.com/not-an-official-archive"
    restamp!(wrong_locator)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        wrong_locator,
    )

    missing_target = checked_plan()
    pop!(source_route(missing_target, "bea_nipa_hmi7")["target_ids"])
    restamp!(missing_target)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        missing_target,
    )

    wrong_pilot = checked_plan()
    pilot_origin(wrong_pilot, "2020q1_reconstructed")["reference_quarter"] =
        "2020Q2"
    restamp!(wrong_pilot)
    @test_throws BackfillPlanValidationError validate_backfill_plan(wrong_pilot)

    completed_stage = checked_plan()
    completed_stage["acquisition_stages"][1]["status"] = "COMPLETE"
    restamp!(completed_stage)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        completed_stage,
    )

    reordered_stage = checked_plan()
    reverse!(reordered_stage["acquisition_stages"][5]["route_ids"])
    restamp!(reordered_stage)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        reordered_stage,
    )

    changed_stage_text = checked_plan()
    changed_stage_text["acquisition_stages"][1]["entry_condition"] =
        "Looks good to proceed."
    restamp!(changed_stage_text)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        changed_stage_text,
    )

    series_drift = checked_plan()
    source_route(series_drift, "bea_nipa_hmi7")["series_identifiers"][1] =
        "NIPA:T10105:line1:WRONG"
    restamp!(series_drift)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        series_drift,
    )
end

@testset "licensing, digest, schema, and inventory guard fail closed" begin
    wrong_bea_terms = checked_plan()
    wrong_bea_terms["licensing"]["bea_terms_locator"] =
        "https://example.com/not-bea-policy"
    restamp!(wrong_bea_terms)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        wrong_bea_terms,
    )

    stale_bea_review = checked_plan()
    stale_bea_review["licensing"]["bea_terms_review_as_of_date"] =
        "2026-08-04"
    restamp!(stale_bea_review)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        stale_bea_review,
    )

    no_bea_recheck = checked_plan()
    no_bea_recheck["licensing"]["bea_terms_recheck_before_acquisition"] =
        false
    restamp!(no_bea_recheck)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        no_bea_recheck,
    )

    bea_route_overclaim = checked_plan()
    source_route(
        bea_route_overclaim,
        "bea_nipa_hmi7",
    )["redistribution_status"] = "UNCONDITIONALLY_PUBLIC_DOMAIN"
    restamp!(bea_route_overclaim)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        bea_route_overclaim,
    )

    wrong_bls_terms = checked_plan()
    wrong_bls_terms["licensing"]["bls_copyright_locator"] =
        "https://example.com/not-bls-policy"
    restamp!(wrong_bls_terms)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        wrong_bls_terms,
    )

    bls_emblem_allowed = checked_plan()
    bls_emblem_allowed["licensing"]["bls_emblem_use_allowed"] = true
    restamp!(bls_emblem_allowed)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        bls_emblem_allowed,
    )

    no_bls_recheck = checked_plan()
    no_bls_recheck["licensing"]["bls_terms_recheck_before_acquisition"] =
        false
    restamp!(no_bls_recheck)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        no_bls_recheck,
    )

    bls_route_overclaim = checked_plan()
    source_route(
        bls_route_overclaim,
        "bls_ces_employment_situation",
    )["redistribution_status"] = "UNCONDITIONALLY_PUBLIC_DOMAIN"
    restamp!(bls_route_overclaim)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        bls_route_overclaim,
    )

    warehouse_allowed = checked_plan()
    warehouse_allowed["licensing"]["cache_allowed_without_clearance"] = true
    restamp!(warehouse_allowed)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        warehouse_allowed,
    )

    clearance_removed = checked_plan()
    clearance_removed["licensing"]["written_clearance_required"] = false
    restamp!(clearance_removed)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        clearance_removed,
    )

    stale_digest = checked_plan()
    stale_digest["admission"]["reconstruction_status"] = "READY"
    @test_throws BackfillPlanValidationError validate_backfill_plan(stale_digest)

    unknown_field = checked_plan()
    unknown_field["artifact"]["ready"] = true
    restamp!(unknown_field)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        unknown_field,
    )

    missing_field = checked_plan()
    delete!(missing_field["admission"], "accuracy_evaluation_allowed")
    restamp!(missing_field)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        missing_field,
    )

    changed_as_of = checked_plan()
    changed_as_of["artifact"]["as_of_date"] = "2026-10-31"
    restamp!(changed_as_of)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        changed_as_of,
    )

    date_only_origin = checked_plan()
    date_only_origin["admission"][
        "reconstruction_only_origin_timestamp_utc",
    ] = "2026-07-31"
    restamp!(date_only_origin)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        date_only_origin,
    )

    local_utc_drift = checked_plan()
    local_utc_drift["admission"][
        "planned_first_prospective_origin_timestamp_local",
    ] = "2026-10-30T09:59:59"
    restamp!(local_utc_drift)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        local_utc_drift,
    )

    fixed_offset_drift = checked_plan()
    fixed_offset_drift["admission"]["timing_utc_offset_seconds"] = -18000
    restamp!(fixed_offset_drift)
    @test_throws BackfillPlanValidationError validate_backfill_plan(
        fixed_offset_drift,
    )

    live_protocol_drift = checked_plan()
    @test_throws BackfillPlanValidationError validate_contract_alignment(
        live_protocol_drift,
        repeat("f", 64),
        live_protocol_drift["artifact"]["tier1_targets_sha256"],
    )

    live_target_contract_drift = checked_plan()
    @test_throws BackfillPlanValidationError validate_contract_alignment(
        live_target_contract_drift,
        live_target_contract_drift["artifact"]["protocol_sha256"],
        repeat("f", 64),
    )

    changed_inventory = TOML.parsefile(INVENTORY_PATH)
    changed_inventory["admissible_origin_timestamps_utc"] =
        ["2026-07-31T14:00:00Z"]
    @test_throws BackfillPlanValidationError validate_inventory_alignment(
        checked_plan(),
        changed_inventory,
    )

    wrong_inventory_hash = TOML.parsefile(INVENTORY_PATH)
    wrong_inventory_hash["artifact"]["content_sha256"] = repeat("f", 64)
    @test_throws BackfillPlanValidationError validate_inventory_alignment(
        checked_plan(),
        wrong_inventory_hash,
    )
end
