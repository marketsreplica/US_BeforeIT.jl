using Test
using Dates
using SHA
using TOML

const TEST_DIRECTORY = @__DIR__
const MODULE_PATH = joinpath(TEST_DIRECTORY, "USEFFRProspectiveEndpointProfileV1.jl")
include(MODULE_PATH)
using .USEFFRProspectiveEndpointProfileV1

const Profile = USEFFRProspectiveEndpointProfileV1

function error_code(callback)
    try
        callback()
        return nothing
    catch error
        error isa ProfileError || rethrow()
        return error.code
    end
end

function fresh_profile()
    return TOML.parsefile(PROFILE_PATH)
end

function restamp!(profile)
    profile["artifact"]["content_sha256"] = repeat("0", 64)
    profile["artifact"]["content_sha256"] = profile_semantic_sha256(profile)
    return profile
end

function expect_rejected(mutator; codes = nothing)
    candidate = fresh_profile()
    mutator(candidate)
    restamp!(candidate)
    code = error_code(
        () -> validate_profile_document(candidate; verify_sources = false),
    )
    @test code !== nothing
    codes === nothing || @test code in codes
    return code
end

@testset "exact checked-in profile and result" begin
    profile = validate_profile()
    @test profile["artifact"]["status"] == "CANNOT_RUN"
    @test profile["artifact"]["schema_version"] ==
        "beforeit-us-effr-prospective-endpoint-profile.v1"
    @test profile["artifact"]["content_sha256"] ==
        "4ed9a0f99c6c8490da35c290ce87c6051a6a1bf08da5eb2ee8ac601f75a4eaa5"
    @test profile_semantic_sha256(profile) ==
        profile["artifact"]["content_sha256"]
    @test bytes2hex(sha256(read(PROFILE_PATH))) ==
        "7de8e23e11d202a887e20d6e90616501562c9c3682db1200c753bb207ae4451b"

    result = compile_current_result()
    @test validate_current_result(result) === result
    @test result["artifact"]["content_sha256"] ==
        "35c422d6483cabfe17df0f3aac58ef1139573c78ef5d4b9ae5fc5de94ec732a4"
    @test result["preflight"]["status"] == "CANNOT_RUN"
    @test result["preflight"]["source_binding_count"] == 16
    @test result["preflight"]["false_condition_count"] == 26
    @test result["preflight"]["blocking_reason_count"] == 26
    @test result["preflight"]["model_input_profile_ready"] === false
    @test result["preflight"]["truth_loaded"] === false
    @test result["preflight"]["model_executed"] === false
    @test result["preflight"]["network_access_performed"] === false
    @test result["preflight"]["filesystem_write_performed"] === false
    @test all(!condition["satisfied"] for condition in result["readiness_conditions"])
    @test all(value === false for value in values(result["gates"]))
end

@testset "exact accepted source bindings" begin
    profile = validate_profile()
    sources = Dict(source["binding_id"] => source for source in profile["sources"])
    @test length(sources) == 16
    for spec in Profile.SOURCE_SPECS
        @test sources[spec.binding_id]["path"] == spec.path
        @test sources[spec.binding_id]["sha256"] == spec.sha256
        @test sources[spec.binding_id]["role"] == spec.role
        path = joinpath(Profile.REPOSITORY_ROOT, spec.path)
        @test isfile(path)
        @test !islink(path)
        @test stat(path).nlink == 1
        @test bytes2hex(sha256(read(path))) == spec.sha256
    end
    @test profile["source_semantics"]["observed_state_protocol_semantic_sha256"] ==
        "33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c"
    @test profile["source_semantics"]["prospective_v2_contract_semantic_sha256"] ==
        "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
    @test profile["source_semantics"]["restart_v2_schedule_semantic_sha256"] ==
        "cae7f463b752ff2c60c78751ca0186712a53fb1732c7970e8bb0e4368d9e477b"
end

@testset "endpoint estimand claim ceiling" begin
    profile = validate_profile()
    estimand = profile["estimand"]
    @test estimand["estimand_id"] == "PRE_ORIGIN_OBSERVED_ENDPOINT_VINTAGE"
    @test estimand["role"] == "MODEL_INPUT_ONLY"
    @test estimand["status"] == "DEFINED_NOT_APPROVED"
    @test estimand["claim_ceiling"] ==
        "MARKETS_API_EFFR_ENDPOINT_STATE_OBSERVED_AS_OF_CAPTURE_TIME_ONLY"
    @test estimand["accepted_observation_classes"] ==
        ["MORNING_WINDOW_ENDPOINT_OBSERVATION", "POST_REVISION_WINDOW_ENDPOINT_OBSERVATION"]
    @test estimand["accepted_transition_claims"] ==
        ["MARKED_SAME_DAY_REVISION_OBSERVED", "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"]
    for field in (
            "current_state",
            "current_state_derivation_allowed",
            "final_daily_state",
            "first_public_bytes",
            "forecast_output_role_allowed",
            "historical_first_byte",
            "no_later_correction",
            "no_later_same_day_revision",
            "publisher_provenance_authenticated",
            "rate_volume_pair_atomic",
            "transport_provenance_authenticated",
            "truth_role_allowed",
        )
        @test estimand[field] === false
    end
    @test profile["contract"]["local_hashes_authenticate_publisher"] === false
end

@testset "candidate history is not training history" begin
    coverage = validate_profile()["coverage"]
    @test coverage["q3_endpoint_history_candidate_start"] == "2026-07-01"
    @test coverage["q3_endpoint_history_candidate_end"] == "2026-10-29"
    @test coverage["q3_endpoint_history_candidate_row_count"] == 84
    @test coverage["q3_endpoint_history_candidate_excluded_dates"] ==
        ["2026-07-03", "2026-09-07", "2026-10-12"]
    @test coverage["q3_endpoint_history_candidate_approved"] === false
    @test coverage["q3_candidate_establishes_complete_effr_daily_history"] === false
    @test coverage["q3_candidate_establishes_training_history_sufficiency"] === false
    @test coverage["model_input_training_history_selector_start"] == "UNDECIDED"
    @test coverage["daily_history_selector_start_approved"] === false
    @test coverage["training_history_length_sufficient"] === false
    @test coverage["minimum_training_quarters"] == 60
    @test coverage["core3_revised_geometry_start"] == "2000Q3"
    dates = Profile._q3_endpoint_candidate_dates()
    @test length(dates) == 84
    @test string(first(dates)) == "2026-07-01"
    @test string(last(dates)) == "2026-10-29"
    @test all(dayofweek(date) <= 5 for date in dates)
    @test all(string(date) ∉ coverage["q3_endpoint_history_candidate_excluded_dates"] for date in dates)

    methodology = validate_profile()["methodology"]
    @test methodology["methodology_change_effective_date"] == "2016-03-01"
    @test methodology["pre_post_2016_regime_treatment_required"] === true
    @test methodology["pre_post_2016_regime_treatment_status"] ==
        "UNDECIDED_UNAPPROVED"
    @test methodology["methodology_break_may_be_ignored"] === false
end

@testset "restart diagnostic and predecessor missingness remain separate" begin
    profile = validate_profile()
    coverage = profile["coverage"]
    @test coverage["restart_required_first_observation_count"] == 58
    @test coverage["restart_required_revision_observation_count"] == 57
    @test coverage["restart_required_slot_count"] == 115
    @test coverage["restart_required_complete_pair_count"] == 57
    @test coverage["restart_does_not_establish_daily_history_coverage"] === true
    @test coverage["restart_does_not_establish_first_public_bytes"] === true
    @test coverage["october_30_revision_required"] === false
    @test coverage["cross_campaign_combination_allowed"] === false

    missingness = profile["predecessor_missingness"]
    @test missingness["predecessor_planned_slot_count"] == 117
    @test missingness["august_7_first_state_captured_count"] == 1
    @test missingness["august_7_revision_missed_count"] == 1
    @test missingness["v1_theoretical_maximum_numerator"] == 116
    @test missingness["v1_theoretical_maximum_denominator"] == 117
    @test missingness["predecessor_complete"] === false
    @test missingness["predecessor_recoverable"] === false
    @test missingness["old_117_slot_manifest_completion_claim_allowed"] === false
    @test missingness["predecessor_may_complete_restart"] === false
    @test missingness["restart_may_complete_predecessor"] === false
    @test missingness["cross_campaign_relabeling_allowed"] === false
end

@testset "parent semantic supersession remains unresolved" begin
    supersession = validate_profile()["parent_supersession"]
    @test supersession["legacy_profile_ids"] ==
        ["effr_daily_history", "effr_first_state_manifest", "effr_revision_manifest"]
    @test length(supersession["candidate_active_leaf_ids"]) == 4
    @test length(supersession["candidate_mapping_rules"]) == 3
    @test supersession["required_dispatch_schema"] ==
        "beforeit-us-prospective-profile-leaf-dispatch.v3"
    @test supersession["semantic_supersession_decision_required"] === true
    @test supersession["semantic_supersession_decision_status"] ==
        "MISSING_UNAPPROVED"
    @test supersession["qualified_leaf_dispatch_required"] === true
    @test supersession["qualified_leaf_dispatch_present"] === false
    @test supersession["parent_requirement_completion_authorized"] === false
    @test supersession["this_leaf_alone_satisfies_parent_requirement"] === false
    @test supersession["legacy_profile_relabeling_allowed"] === false
end

@testset "retention defect is explicit and correctly derived" begin
    retention = validate_profile()["retention"]
    @test retention["prospective_v2_retain_until_utc"] == "2031-10-30T14:00:00Z"
    @test retention["maximum_forecast_horizon_quarters"] == 12
    @test retention["h12_target_reference_period"] == "2029Q3"
    @test retention["h12_target_period_end_utc"] == "2029-09-30T23:59:59Z"
    @test retention["mature_truth_lag_months"] == 60
    @test retention["mathematical_minimum_retain_until_utc"] ==
        "2034-09-30T23:59:59Z"
    @test retention["conservative_custody_cushion_until_utc"] ==
        "2034-10-30T14:00:00Z"
    @test retention["operational_custody_rule"] ==
        "max(mathematical_minimum_retain_until_utc,verified_mature_receipt_completion_utc_plus_successor_audit_policy)"
    @test retention["successor_post_receipt_audit_policy_status"] == "UNDEFINED"
    @test retention["prospective_v2_retention_sufficient"] === false
    @test retention["successor_retention_contract_required"] === true
    @test retention["successor_retention_status"] == "MISSING"
end

@testset "exhaustive blockers and permanent nonmutation gates" begin
    result = compile_current_result()
    reasons = Set(blocker["reason_id"] for blocker in result["blocking_reasons"])
    @test length(reasons) == 26
    for reason in (
            "LEGACY_TO_ACTIVE_THREE_PROFILE_SUPERSESSION_DECISION_MISSING",
            "QUALIFIED_PARENT_V3_LEAF_DISPATCH_MISSING",
            "MODEL_INPUT_DAILY_HISTORY_SELECTOR_START_UNJUSTIFIED_UNAPPROVED",
            "MODEL_INPUT_TRAINING_HISTORY_LENGTH_NOT_ESTABLISHED_FOR_60_QUARTERS",
            "EFFR_PRE_POST_2016_METHODOLOGY_REGIME_TREATMENT_UNDECIDED",
            "RESTART_FIRST_OBSERVATION_COVERAGE_ZERO_OF_58",
            "RESTART_REVISION_OBSERVATION_COVERAGE_ZERO_OF_57",
            "RESTART_SLOT_COVERAGE_ZERO_OF_115",
            "RESTART_COMPLETE_PAIR_COVERAGE_ZERO_OF_57",
            "TWO_INDEPENDENT_DURABILITY_DOMAINS_NOT_VERIFIED",
            "PROSPECTIVE_V2_RETENTION_ENDS_BEFORE_H12_MATURE_TRUTH_MINIMUM",
            "VERIFIED_MATURE_RECEIPT_COMPLETION_PLUS_AUDIT_CUSTODY_NOT_COVERED",
        )
        @test reason in reasons
    end
    @test Set(result["prohibited_actions"]) == Set(Profile.PROHIBITED_ACTIONS)
    @test length(result["prohibited_actions"]) == length(Profile.PROHIBITED_ACTIONS)
    @test result["gates"]["source_inventory_mutation_allowed"] === false
    @test result["gates"]["origin_admissible"] === false
    @test result["gates"]["forecast_emission_allowed"] === false
    @test result["gates"]["truth_access_allowed"] === false
    @test result["gates"]["scoring_allowed"] === false
end

@testset "coordinated profile restamps cannot elevate claims" begin
    attacks = [
        profile -> profile["artifact"]["status"] =
            "READY_FOR_MODEL_INPUT_PROFILE_SEAL_NO_TRUTH_LOADED",
        profile -> profile["estimand"]["status"] = "APPROVED_FOR_MODEL_INPUT_ONLY",
        profile -> profile["estimand"]["current_state"] = true,
        profile -> profile["estimand"]["current_state_derivation_allowed"] = true,
        profile -> profile["estimand"]["first_public_bytes"] = true,
        profile -> profile["estimand"]["final_daily_state"] = true,
        profile -> profile["estimand"]["rate_volume_pair_atomic"] = true,
        profile -> profile["estimand"]["claim_ceiling"] = "FIRST_PUBLIC_BYTES",
        profile -> profile["coverage"]["q3_endpoint_history_candidate_approved"] = true,
        profile -> profile["coverage"]["q3_candidate_establishes_complete_effr_daily_history"] = true,
        profile -> profile["coverage"]["q3_candidate_establishes_training_history_sufficiency"] = true,
        profile -> profile["coverage"]["daily_history_selector_start_approved"] = true,
        profile -> profile["coverage"]["training_history_length_sufficient"] = true,
        profile -> profile["methodology"]["pre_post_2016_regime_treatment_status"] = "APPROVED",
        profile -> profile["methodology"]["methodology_break_may_be_ignored"] = true,
        profile -> profile["parent_supersession"]["semantic_supersession_decision_status"] = "APPROVED",
        profile -> profile["parent_supersession"]["qualified_leaf_dispatch_present"] = true,
        profile -> profile["parent_supersession"]["this_leaf_alone_satisfies_parent_requirement"] = true,
        profile -> profile["predecessor_missingness"]["predecessor_complete"] = true,
        profile -> profile["predecessor_missingness"]["predecessor_recoverable"] = true,
        profile -> profile["coverage"]["cross_campaign_combination_allowed"] = true,
        profile -> profile["lineage"]["self_rehashed_lineage_sufficient"] = true,
        profile -> profile["lineage"]["synthetic_fixture_eligible"] = true,
        profile -> profile["retention"]["prospective_v2_retention_sufficient"] = true,
        profile -> profile["retention"]["mathematical_minimum_retain_until_utc"] =
            "2031-10-30T14:00:00Z",
        profile -> profile["approval"]["current_status"] = "APPROVED",
        profile -> profile["approval"]["distinct_owner_validator_required"] = false,
        profile -> profile["contract"]["source_inventory_mutation_forbidden"] = false,
        profile -> profile["contract"]["local_hashes_authenticate_publisher"] = true,
        profile -> profile["gates"]["origin_admissible"] = true,
        profile -> profile["gates"]["model_input_profile_ready"] = true,
        profile -> profile["current_evidence"]["restart_slot_count_verified"] = 115,
    ]
    for attack in attacks
        @test expect_rejected(attack) !== nothing
    end
end

@testset "closed schema, source identity, and result replay attacks" begin
    expect_rejected(profile -> profile["unknown"] = true; codes = ["CLOSED_SCHEMA_MISMATCH"])
    expect_rejected(profile -> delete!(profile, "retention"); codes = ["CLOSED_SCHEMA_MISMATCH"])
    expect_rejected(
        profile -> profile["coverage"]["unknown"] = true;
        codes = ["CLOSED_SCHEMA_MISMATCH"],
    )
    expect_rejected(
        profile -> delete!(profile["lineage"], "external_receipt_pin_required");
        codes = ["CLOSED_SCHEMA_MISMATCH"],
    )
    expect_rejected(profile -> pop!(profile["sources"]); codes = ["SOURCE_COUNT_MISMATCH"])
    expect_rejected(
        profile -> profile["sources"][1]["binding_id"] =
            profile["sources"][2]["binding_id"];
        codes = ["DUPLICATE_SOURCE_BINDING"],
    )
    expect_rejected(
        profile -> profile["sources"][1]["path"] = "../escape";
        codes = ["SOURCE_PATH_MISMATCH"],
    )
    expect_rejected(
        profile -> profile["sources"][1]["sha256"] = repeat("a", 64);
        codes = ["SOURCE_PIN_MISMATCH"],
    )
    expect_rejected(
        profile -> profile["sources"][1]["role"] = "forged";
        codes = ["SOURCE_ROLE_MISMATCH"],
    )

    result = compile_current_result()
    forged = deepcopy(result)
    forged["preflight"]["status"] = "READY_FOR_MODEL_INPUT_PROFILE_SEAL_NO_TRUTH_LOADED"
    forged["artifact"]["content_sha256"] = Profile._result_semantic_sha256(forged)
    @test error_code(() -> validate_current_result(forged)) == "RESULT_REPLAY_MISMATCH"

    forged = deepcopy(result)
    forged["gates"]["origin_admissible"] = true
    forged["artifact"]["content_sha256"] = Profile._result_semantic_sha256(forged)
    @test error_code(() -> validate_current_result(forged)) == "RESULT_REPLAY_MISMATCH"
end

@testset "filesystem source boundary" begin
    mktempdir() do directory
        regular = joinpath(directory, "regular.txt")
        write(regular, "bound bytes")
        digest = bytes2hex(sha256(read(regular)))
        @test Profile._read_regular_bound_file(
            directory,
            "regular.txt",
            digest,
            "fixture",
        ) == Vector{UInt8}(codeunits("bound bytes"))
        @test error_code(
            () -> Profile._read_regular_bound_file(
                directory,
                "regular.txt",
                repeat("0", 64),
                "fixture",
            ),
        ) == "SOURCE_SHA256_MISMATCH"
        @test error_code(
            () -> Profile._read_regular_bound_file(
                directory,
                "../escape",
                digest,
                "fixture",
            ),
        ) == "PATH_ESCAPE"

        symlink(regular, joinpath(directory, "leaf-link"))
        @test error_code(
            () -> Profile._read_regular_bound_file(
                directory,
                "leaf-link",
                digest,
                "fixture",
            ),
        ) == "SYMLINK_REJECTED"

        mkdir(joinpath(directory, "real-parent"))
        write(joinpath(directory, "real-parent", "nested.txt"), "nested")
        nested_digest = bytes2hex(sha256(read(joinpath(directory, "real-parent", "nested.txt"))))
        symlink(joinpath(directory, "real-parent"), joinpath(directory, "parent-link"))
        @test error_code(
            () -> Profile._read_regular_bound_file(
                directory,
                "parent-link/nested.txt",
                nested_digest,
                "fixture",
            ),
        ) == "SYMLINK_REJECTED"

        hardlink = joinpath(directory, "hardlink.txt")
        Base.Filesystem.hardlink(regular, hardlink)
        @test error_code(
            () -> Profile._read_regular_bound_file(
                directory,
                "hardlink.txt",
                digest,
                "fixture",
            ),
        ) == "HARDLINK_REJECTED"
    end
end

@testset "isolated no-action surface" begin
    source = read(MODULE_PATH, String)
    @test !occursin(r"\bDownloads\b", source)
    @test !occursin(r"\bHTTP\b", source)
    @test !occursin(r"\bSockets\b", source)
    @test !occursin(r"\binclude\s*\(", source)
    @test !occursin(r"\beval\s*\(", source)
    @test !occursin(r"\brun\s*\(", source)
    @test !occursin(r"\bopen\s*\(", source)
    @test !occursin(r"\bwrite\s*\(", source)
    @test !occursin("append_retrieval_event!", source)
    @test !occursin("append_forecast!", source)
    @test !occursin("append_truth!", source)
    @test !occursin("append_score!", source)
    @test !occursin("step!", source)
    @test !occursin("forecast(", source)
    @test !occursin("score(", source)
end
