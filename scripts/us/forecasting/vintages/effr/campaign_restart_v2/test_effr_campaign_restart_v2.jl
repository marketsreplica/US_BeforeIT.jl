using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USEFFRCampaignRestartV2.jl"))
using .USEFFRCampaignRestartV2

const Restart = USEFFRCampaignRestartV2

function fresh_schedule()
    return TOML.parsefile(Restart.DEFAULT_SCHEDULE_PATH)
end

function restamp!(schedule)
    schedule["artifact"]["content_sha256"] =
        Restart.computed_schedule_sha256(schedule)
    return schedule
end

function validation_error(schedule; binding_path_overrides = Dict{String, String}())
    try
        Restart.validate_restart_schedule(schedule; binding_path_overrides)
        return nothing
    catch error
        error isa Restart.CampaignRestartError || rethrow()
        return sprint(showerror, error)
    end
end

function mutated(section, key, value)
    schedule = fresh_schedule()
    schedule[section][key] = value
    return restamp!(schedule)
end

@testset "EFFR additive restart-v2 campaign contract" begin
    @testset "frozen positive schedule" begin
        schedule = Restart.load_restart_schedule()
        result = Restart.validate_restart_schedule(schedule)
        @test result.schedule_id ==
            "beforeit-us-effr-2026q3-prospective-restart-20260810.v2"
        @test result.campaign_id ==
            "frbny_effr_daily_first_state_and_revision_check_restart_20260810"
        @test result.content_sha256 ==
            "cae7f463b752ff2c60c78751ca0186712a53fb1732c7970e8bb0e4368d9e477b"
        @test result.first_state_count == 58
        @test result.revision_check_count == 57
        @test result.slot_count == 115
        @test result.complete_pair_count == 57
        @test result.endpoint_only_claim_ceiling
        @test result.predecessor_withdrawn_incomplete
        @test result.observed_state_offline_acceptance_complete
        @test !result.runner_restart_binding_complete
        @test !result.network_execution_authorized
        @test !result.raw_data_write_authorized
        @test !result.origin_admissible
        @test !result.production_scoring_allowed
        @test !result.promotion_eligible
        @test !result.ready
        @test Restart.computed_schedule_sha256(schedule) ==
            schedule["artifact"]["content_sha256"]
        @test bytes2hex(sha256(read(Restart.DEFAULT_SCHEDULE_PATH))) ==
            bytes2hex(sha256(read(Restart.DEFAULT_SCHEDULE_PATH)))
    end

    @testset "calendar, paths, and timezone windows" begin
        schedule = fresh_schedule()
        slots = schedule["slots"]
        first_slots = filter(row -> row["phase"] == "first", slots)
        revision_slots = filter(row -> row["phase"] == "revision-check", slots)
        @test length(first_slots) == 58
        @test length(revision_slots) == 57
        @test length(unique(row["transaction_id"] for row in slots)) == 115
        @test length(unique(row["bundle_path"] for row in slots)) == 115
        @test length(unique(row["journal_path"] for row in slots)) == 115
        @test all(row -> dayofweek(Date(row["publication_date"])) <= 5, slots)
        @test !any(row -> row["publication_date"] == "2026-09-07", slots)
        @test !any(row -> row["publication_date"] == "2026-10-12", slots)
        @test !any(
            row -> row["publication_date"] == "2026-10-30" &&
                row["phase"] == "revision-check",
            slots,
        )

        first = Restart.planned_slot(schedule, "2026-08-10", "first")
        revision = Restart.planned_slot(
            schedule,
            Date(2026, 8, 10),
            "revision-check",
        )
        @test first.sequence == 1
        @test first.day_sequence == 1
        @test first.effective_date == Date(2026, 8, 7)
        @test first.state_class == "FIRST_0900_STATE"
        @test first.scheduled_at_utc == DateTime(2026, 8, 10, 13)
        @test first.deadline_at_utc == DateTime(2026, 8, 10, 13, 15)
        @test first.scheduled_at_new_york == "2026-08-10T09:00:00-04:00"
        @test first.scheduled_at_madrid == "2026-08-10T15:00:00+02:00"
        @test first.transaction_id == "effr-20260810-first-1300z"
        @test first.predecessor_bundle_path == "NOT_APPLICABLE"
        @test first.rate_query ==
            "endDate=2026-08-07&startDate=2026-08-07&type=rate"
        @test first.volume_query ==
            "endDate=2026-08-07&startDate=2026-08-07&type=volume"
        @test !first.network_execution_authorized
        @test !first.raw_data_write_authorized
        @test !first.origin_admissible
        @test revision.sequence == 2
        @test revision.predecessor_bundle_path == first.bundle_path
        @test revision.scheduled_at_new_york ==
            "2026-08-10T14:30:00-04:00"
        @test revision.scheduled_at_madrid ==
            "2026-08-10T20:30:00+02:00"

        after_labor_day = Restart.planned_slot(schedule, "2026-09-08", "first")
        after_columbus_day =
            Restart.planned_slot(schedule, "2026-10-13", "first")
        before_madrid_dst =
            Restart.planned_slot(schedule, "2026-10-23", "revision-check")
        after_madrid_dst =
            Restart.planned_slot(schedule, "2026-10-26", "revision-check")
        terminal = Restart.planned_slot(schedule, "2026-10-30", "first")
        @test after_labor_day.effective_date == Date(2026, 9, 4)
        @test after_columbus_day.effective_date == Date(2026, 10, 9)
        @test before_madrid_dst.scheduled_at_madrid ==
            "2026-10-23T20:30:00+02:00"
        @test after_madrid_dst.scheduled_at_madrid ==
            "2026-10-26T19:30:00+01:00"
        @test after_madrid_dst.scheduled_at_new_york ==
            "2026-10-26T14:30:00-04:00"
        @test terminal.sequence == 115
        @test terminal.effective_date == Date(2026, 10, 29)
        @test terminal.deadline_at_utc == DateTime(2026, 10, 30, 13, 15)
        @test terminal.deadline_at_utc < DateTime(2026, 10, 30, 14)

        @test_throws Restart.CampaignRestartError Restart.planned_slot(
            schedule,
            "2026-08-07",
            "first",
        )
        @test_throws Restart.CampaignRestartError Restart.planned_slot(
            schedule,
            "2026-09-07",
            "first",
        )
        @test_throws Restart.CampaignRestartError Restart.planned_slot(
            schedule,
            "2026-10-30",
            "revision-check",
        )
        @test_throws Restart.CampaignRestartError Restart.planned_slot(
            schedule,
            "2026-08-10",
            :first,
        )
    end

    @testset "closed artifact and amendment" begin
        schedule = fresh_schedule()
        schedule["artifact"]["content_sha256"] = repeat("0", 64)
        @test occursin("semantic self-hash mismatch", validation_error(schedule))

        for (key, value) in (
                "schema_version" => "beforeit-us-effr-campaign-restart-schedule.v3",
                "schedule_id" => "relabeled",
                "status" => "ADMITTED",
                "canonicalization" => "alternate",
                "digest_algorithm" => "sha512",
                "local_contract_authored_at_utc" => "2026-08-10T13:00:00Z",
                "authored_timestamp_status" => "EXTERNALLY_ATTESTED",
            )
            @test validation_error(mutated("artifact", key, value)) !== nothing
        end

        for (key, value) in (
                "amendment_type" => "RETROSPECTIVE_SELECTION",
                "trigger" => "VALUE_OUTCOME",
                "selection_basis" => "EFFR_LEVEL",
                "frozen_before_first_restart_value_observation" => false,
                "first_restart_value_observation_not_before_utc" =>
                    "2026-08-07T21:00:00Z",
                "effr_numeric_values_used_to_select_restart" => true,
                "revision_outcome_used_to_select_restart" => true,
                "outcome_driven_selection" => true,
                "retroactive_backfill_allowed" => true,
                "predecessor_files_mutated" => true,
                "predecessor_slots_relabelled" => true,
                "additive_successor_only" => false,
            )
            @test validation_error(mutated("amendment", key, value)) !== nothing
        end

        unknown = fresh_schedule()
        unknown["amendment"]["unknown"] = false
        @test occursin("unknown keys", validation_error(restamp!(unknown)))
        missing = fresh_schedule()
        pop!(missing["amendment"], "selection_basis")
        @test occursin("missing keys", validation_error(restamp!(missing)))
    end

    @testset "closed policy and endpoint-only claim ceiling" begin
        claims = fresh_schedule()["claim_ceiling"]
        @test claims["positive_claim"] ==
            "MARKETS_API_ENDPOINT_STATE_OBSERVED_AS_OF_CAPTURE_TIME_ONLY"
        @test claims["unchanged_revision_status"] ==
            "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
        for (key, value) in (
                "campaign_id" => "predecessor-id",
                "campaign_start_date" => "2026-08-07",
                "first_campaign_end_date" => "2026-10-29",
                "revision_campaign_end_date" => "2026-10-30",
                "initial_effective_date" => "2026-08-06",
                "excluded_dates" => ["2026-09-07"],
                "first_scheduled_time_utc" => "13:01:00Z",
                "first_deadline_time_utc" => "13:16:00Z",
                "revision_scheduled_time_utc" => "18:29:59Z",
                "revision_deadline_time_utc" => "18:46:00Z",
                "new_york_utc_offset" => "-05:00",
                "madrid_summer_utc_offset" => "+01:00",
                "madrid_standard_utc_offset" => "+02:00",
                "madrid_standard_time_start_date" => "2026-10-25",
                "capture_window_minutes" => 16,
                "capture_window_boundary" => "HALF_OPEN",
                "origin_cutoff_utc" => "2026-10-30T13:15:00Z",
                "output_root" => "data/us/raw/alternate",
                "expected_first_state_count" => 59,
                "expected_revision_check_count" => 58,
                "expected_slot_count" => 117,
            )
            @test validation_error(mutated("policy", key, value)) !== nothing
        end

        for key in (
                "proves_first_publication",
                "proves_historical_first_byte",
                "proves_no_later_same_day_revision",
                "proves_final_daily_state",
                "proves_transport_provenance",
                "proves_origin_admissibility",
            )
            @test validation_error(mutated("claim_ceiling", key, true)) !== nothing
        end
        @test validation_error(
            mutated(
                "claim_ceiling",
                "positive_claim",
                "FINAL_DAILY_STATE",
            ),
        ) !== nothing
        @test validation_error(
            mutated(
                "claim_ceiling",
                "unchanged_revision_status",
                "NO_REVISION_OCCURRED",
            ),
        ) !== nothing
    end

    @testset "exact source and predecessor bindings" begin
        schedule = fresh_schedule()
        source = schedule["source_bindings"]
        @test source["recurring_module_sha256"] ==
            "3685e0c0ca3d440bdf2816d3c3bc229656d4a2339d6009b34f2c754c4a7051de"
        @test source["capture_contract_module_sha256"] ==
            "6c4ee3ff95b92daf34899db64dbff7fc920eb33e5bc4bf17a6adf99bf3b3f651"
        @test source["project_sha256"] ==
            "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"
        @test source["manifest_sha256"] ==
            "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"
        @test source["current_inventory_sha256"] ==
            "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"
        @test source["predecessor_campaign_schedule_sha256"] ==
            "ddbc7a089a636d09f97e68e67da7f534ecca6c88d6b7dbc8bf78080ce7400e25"
        @test source["observed_state_readme_sha256"] ==
            "4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23"

        predecessor = schedule["predecessor_history"]
        @test predecessor["planned_slot_count"] == 117
        @test predecessor["captured_august7_first_state_slot_count"] == 1
        @test predecessor["captured_august7_first_state_status"] ==
            "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
        @test predecessor["missed_august7_revision_check_slot_count"] == 1
        @test predecessor["missed_august7_revision_check_status"] ==
            "OPERATIONAL_MISSINGNESS_WINDOW_MISSED_NO_LATE_REQUEST"
        @test predecessor["future_uncaptured_v1_slot_count"] == 115
        @test predecessor["theoretical_v1_total_maximum_after_miss_numerator"] == 116
        @test predecessor["theoretical_v1_total_maximum_after_miss_denominator"] == 117
        @test predecessor["theoretical_v1_total_maximum_status"] ==
            "V1_ONLY_NONCOMBINABLE_CEILING_NOT_OBSERVED_COVERAGE"
        @test !predecessor["theoretical_v1_maximum_contributes_to_restart_completion"]
        @test !predecessor["may_be_combined_to_claim_restart_completion"]

        changed_hash = fresh_schedule()
        changed_hash["source_bindings"]["recurring_module_sha256"] =
            repeat("0", 64)
        @test occursin("expected", validation_error(restamp!(changed_hash)))
        changed_path = fresh_schedule()
        changed_path["source_bindings"]["recurring_module_path"] =
            "alternate.jl"
        @test occursin("expected", validation_error(restamp!(changed_path)))

        mktemp() do path, io
            write(io, read(joinpath(@__DIR__, "..", "recurring_acquisition", "USEFFRRecurringAcquisition.jl")))
            write(io, "\n# exact-byte tamper\n")
            close(io)
            error = validation_error(
                fresh_schedule();
                binding_path_overrides = Dict("recurring_module" => path),
            )
            @test occursin("exact file SHA-256 changed", error)
        end
        @test occursin(
            "missing file",
            validation_error(
                fresh_schedule();
                binding_path_overrides = Dict(
                    "recurring_module" => joinpath(@__DIR__, "does-not-exist"),
                ),
            ),
        )

        for (key, value) in (
                "governance_status" => "COMPLETE",
                "captured_august7_first_state_slot_count" => 2,
                "captured_august7_first_state_status" => "ADMITTED",
                "missed_august7_revision_check_slot_count" => 0,
                "missed_august7_revision_check_status" => "CAPTURED",
                "future_uncaptured_v1_slot_count" => 116,
                "theoretical_v1_total_maximum_after_miss_numerator" => 117,
                "theoretical_v1_total_maximum_after_miss_denominator" => 116,
                "theoretical_v1_total_maximum_status" => "OBSERVED_COVERAGE",
                "theoretical_v1_maximum_contributes_to_restart_completion" => true,
                "coverage_accounting_status" => "IMPORTED_AS_COMPLETE",
                "complete" => true,
                "withdrawn_for_future_capture" => false,
                "eligible_for_restart_coverage" => true,
                "eligible_for_relabeling" => true,
                "eligible_for_mutation" => true,
                "may_be_combined_to_claim_restart_completion" => true,
            )
            @test validation_error(mutated("predecessor_history", key, value)) !==
                nothing
        end
    end

    @testset "observed-state acceptance remains narrow" begin
        acceptance = fresh_schedule()["observed_state_acceptance"]
        @test acceptance["independent_acceptance_required"]
        @test acceptance["independent_acceptance_completed"]
        @test acceptance["accepted_role"] ==
            "NARROW_OFFLINE_PERMANENTLY_NONADMITTING"
        @test acceptance["root_test_count"] == 253
        @test acceptance["unrelated_tmp_test_count"] == 253
        @test acceptance["module_sha256"] ==
            "3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6"
        @test acceptance["protocol_file_sha256"] ==
            "d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716"
        @test acceptance["tests_sha256"] ==
            "55bfbf5a4b252804f4e3b2e91100c83b8ff98bffbf10eec5bdd3bd83d96ad66c"
        @test acceptance["readme_sha256"] ==
            "4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23"
        @test acceptance["protocol_semantic_sha256"] ==
            "33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c"
        for key in (
                "unblocks_provenance",
                "unblocks_origin_admission",
                "unblocks_scoring",
                "unblocks_promotion",
                "unblocks_production",
            )
            @test !acceptance[key]
            @test validation_error(
                mutated("observed_state_acceptance", key, true),
            ) !== nothing
        end
        @test validation_error(
            mutated(
                "observed_state_acceptance",
                "independent_acceptance_required",
                false,
            ),
        ) !== nothing
        @test validation_error(
            mutated(
                "observed_state_acceptance",
                "independent_acceptance_completed",
                false,
            ),
        ) !== nothing
        @test validation_error(
            mutated(
                "observed_state_acceptance",
                "accepted_role",
                "PRODUCTION",
            ),
        ) !== nothing
    end

    @testset "operational missingness and maximum coverage semantics" begin
        operational = fresh_schedule()["operational_control"]
        @test operational["retry_policy"] == "NO_AUTOMATIC_RETRY"
        @test operational["duplicate_policy"] ==
            "FINAL_BUNDLE_OR_PRIVATE_JOURNAL_EXISTS_ISSUE_NO_REQUEST"
        @test operational["late_capture_policy"] ==
            "OUTSIDE_WINDOW_ISSUE_NO_REQUEST_RECORD_OPERATIONAL_MISSINGNESS"
        @test operational["one_slot_one_transaction"]
        @test operational["retroactive_fill_forbidden"]
        @test !operational["runner_restart_binding_complete"]
        @test !operational["automation_created_by_contract"]
        @test !operational["network_client_present_in_contract"]
        @test !operational["raw_writer_present_in_contract"]
        @test !operational["source_inventory_writer_present_in_contract"]

        for (key, value) in (
                "retry_policy" => "RETRY_ON_FAILURE",
                "duplicate_policy" => "OVERWRITE",
                "late_capture_policy" => "BACKFILL",
                "one_slot_one_transaction" => false,
                "retroactive_fill_forbidden" => false,
                "runner_restart_binding_complete" => true,
                "automation_created_by_contract" => true,
                "network_client_present_in_contract" => true,
                "raw_writer_present_in_contract" => true,
                "source_inventory_writer_present_in_contract" => true,
            )
            @test validation_error(mutated("operational_control", key, value)) !==
                nothing
        end

        coverage = fresh_schedule()["coverage"]
        @test coverage["restart_first_state_denominator"] == 58
        @test coverage["restart_revision_check_denominator"] == 57
        @test coverage["restart_slot_denominator"] == 115
        @test coverage["restart_complete_pair_denominator"] == 57
        @test coverage["maximum_restart_slot_coverage_numerator"] == 115
        @test coverage["maximum_restart_slot_coverage_denominator"] == 115
        @test coverage["restart_coverage_status"] ==
            "RESTART_ONLY_DENOMINATOR_NO_V1_CONTRIBUTIONS"
        @test coverage["restart_denominator_independent_of_v1"]
        @test !coverage["v1_slots_contribute_to_restart_completion"]
        @test !coverage["restart_slots_contribute_to_v1_completion"]
        @test !coverage["august7_first_state_included"]
        @test !coverage["august7_revision_check_included"]
        @test !coverage["october30_revision_check_included"]
        @test coverage["all_115_required_for_restart_completion"]
        @test !coverage["full_117_claim_allowed"]
        @test !coverage["cross_campaign_receipt_combination_allowed"]
        @test coverage["maximum_origin_admissible_slot_count"] == 0
        for (key, value) in (
                "restart_first_state_denominator" => 59,
                "restart_revision_check_denominator" => 58,
                "restart_slot_denominator" => 117,
                "restart_complete_pair_denominator" => 58,
                "restart_coverage_status" => "COMBINED_WITH_V1",
                "restart_denominator_independent_of_v1" => false,
                "v1_slots_contribute_to_restart_completion" => true,
                "restart_slots_contribute_to_v1_completion" => true,
                "august7_first_state_included" => true,
                "august7_revision_check_included" => true,
                "october30_revision_check_included" => true,
                "all_115_required_for_restart_completion" => false,
                "full_117_claim_allowed" => true,
                "cross_campaign_receipt_combination_allowed" => true,
                "maximum_origin_admissible_slot_count" => 115,
            )
            @test validation_error(mutated("coverage", key, value)) !== nothing
        end
    end

    @testset "permanent false gates" begin
        keys = (
            "network_execution_authorized",
            "raw_data_write_authorized",
            "inventory_mutation_authorized",
            "profile_completion_authorized",
            "origin_admissible",
            "accuracy_evaluation_allowed",
            "empirical_forecast_allowed",
            "production_scoring_allowed",
            "promotion_eligible",
            "production_use_allowed",
            "ready",
        )
        gates = fresh_schedule()["gates"]
        @test all(key -> gates[key] === false, keys)
        for key in keys
            @test validation_error(mutated("gates", key, true)) !== nothing
            @test validation_error(mutated("gates", key, 0)) !== nothing
        end
    end

    @testset "slot rows fail closed" begin
        cases = (
            "sequence" => 2,
            "day_sequence" => 2,
            "publication_date" => "2026-08-11",
            "effective_date" => "2026-08-06",
            "phase" => "revision-check",
            "state_class" => "CURRENT_STATE",
            "scheduled_at_utc" => "2026-08-10T13:00:01Z",
            "deadline_at_utc" => "2026-08-10T13:14:59Z",
            "scheduled_at_new_york" => "2026-08-10T08:00:00-05:00",
            "deadline_at_new_york" => "2026-08-10T09:16:00-04:00",
            "scheduled_at_madrid" => "2026-08-10T14:00:00+01:00",
            "deadline_at_madrid" => "2026-08-10T15:16:00+02:00",
            "transaction_id" => "effr-20260810-revision-1830z",
            "bundle_path" => "data/us/raw/alternate",
            "journal_path" => "data/us/raw/alternate-journal",
            "predecessor_bundle_path" => "fabricated",
            "rate_query" =>
                "endDate=2026-08-08&startDate=2026-08-07&type=rate",
            "volume_query" =>
                "endDate=2026-08-07&startDate=2026-08-07&type=rate",
        )
        for (key, value) in cases
            schedule = fresh_schedule()
            schedule["slots"][1][key] = value
            @test validation_error(restamp!(schedule)) !== nothing
        end

        typed = fresh_schedule()
        typed["slots"][1]["sequence"] = true
        @test validation_error(restamp!(typed)) !== nothing
        removed = fresh_schedule()
        pop!(removed["slots"][1], "rate_query")
        @test occursin("missing keys", validation_error(restamp!(removed)))
        unknown = fresh_schedule()
        unknown["slots"][1]["alias"] = "first"
        @test occursin("unknown keys", validation_error(restamp!(unknown)))
        short = fresh_schedule()
        pop!(short["slots"])
        @test occursin("exactly 115", validation_error(restamp!(short)))
        terminal_revision = fresh_schedule()
        terminal = deepcopy(last(terminal_revision["slots"]))
        terminal["sequence"] = 116
        terminal["phase"] = "revision-check"
        terminal["state_class"] = "SAME_DAY_1430_REVISION_CHECK"
        push!(terminal_revision["slots"], terminal)
        @test occursin("exactly 115", validation_error(restamp!(terminal_revision)))

        dst = fresh_schedule()
        index = findfirst(
            row -> row["publication_date"] == "2026-10-26" &&
                row["phase"] == "first",
            dst["slots"],
        )
        dst["slots"][index]["scheduled_at_madrid"] =
            "2026-10-26T15:00:00+02:00"
        @test validation_error(restamp!(dst)) !== nothing
    end

    @testset "TOML and filesystem loader rejection" begin
        duplicate = """
        [artifact]
        schema_version = "x"
        schema_version = "y"
        """
        @test_throws TOML.ParserError TOML.parse(duplicate)
        @test_throws Restart.CampaignRestartError Restart.load_restart_schedule(
            joinpath(@__DIR__, "missing.toml"),
        )
        mktemp() do path, io
            write(io, "not = [valid")
            close(io)
            @test_throws Restart.CampaignRestartError Restart.load_restart_schedule(path)
        end
    end
end
