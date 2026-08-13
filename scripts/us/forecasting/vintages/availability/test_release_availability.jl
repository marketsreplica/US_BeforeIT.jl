#!/usr/bin/env julia

using Dates
using Test

include(joinpath(@__DIR__, "USReleaseAvailability.jl"))
using .USReleaseAvailability

const POLICY_PATH =
    joinpath(@__DIR__, "release_availability_policy.toml")
const POLICY_SHA256 =
    "6af185c5fa8be4404a064294a0053eec093ca1a59cbc29f1a0566ada3364de11"
const TIMEZONE_SEMANTICS_SHA256 =
    "8ed940e6deb1a1aa0922369eb8b0ad327ecf52def3c37c7317f81b87afe7a174"
const ZERO_SHA256 = repeat("0", 64)

function common_evidence(assertion_basis)
    return Dict{String, Any}(
        "schema_version" =>
            "beforeit-us-release-availability-evidence.v2",
        "evidence_id" => "evidence-bea-gdp-2026q1",
        "release_event_id" => "release-bea-gdp-2026q1-advance",
        "source_id" => "bea",
        "assertion_basis" => assertion_basis,
        "availability_evidence_locator" =>
            "https://example.test/official-release-notice",
        "availability_evidence_sha256" => repeat("a", 64),
        "release_byte_evidence_locator" =>
            "urn:sha256:release-byte-fixture",
        "release_byte_evidence_sha256" => repeat("b", 64),
        "vintage_evidence_locator" =>
            "urn:sha256:vintage-manifest-fixture",
        "vintage_evidence_sha256" => repeat("c", 64),
        "evidence_scope" => "retrospective_research",
        "empirical_forecast_execution_allowed" => false,
        "production_scoring_allowed" => false,
        "origin_admission_authorized" => false,
        "inventory_mutation_authorized" => false,
        "content_sha256" => ZERO_SHA256,
    )
end

function exact_evidence(;
        timestamp = "2026-04-30T12:30:00Z",
        assertion_basis = "actual_public_timestamp",
    )
    evidence = common_evidence(assertion_basis)
    evidence["actual_public_timestamp_utc"] = timestamp
    return stamp_evidence_sha256!(evidence)
end

function date_evidence(;
        assertion_basis = "official_actual_release_date",
        start_date = "2026-01-15",
        end_date = start_date,
        source_timezone = "America/New_York",
        start_offset = "-05:00",
        end_offset = start_offset,
    )
    evidence = common_evidence(assertion_basis)
    evidence["local_start_date"] = start_date
    evidence["local_end_date"] = end_date
    evidence["source_timezone"] = source_timezone
    evidence["start_utc_offset"] = start_offset
    evidence["end_utc_offset"] = end_offset
    policy = load_policy()
    evidence["timezone_rules_evidence_locator"] =
        policy["timezone"]["semantics_artifact_locator"]
    evidence["timezone_rules_evidence_sha256"] =
        policy["timezone"]["semantics_artifact_sha256"]
    return stamp_evidence_sha256!(evidence)
end

function sealed_offset(source_timezone, local_date)
    semantics = load_timezone_semantics()
    offset, _ = USReleaseAvailability.sealed_offset_at_local_midnight(
        semantics,
        source_timezone,
        Date(local_date),
    )
    return offset
end

function semantically_valid_date_evidence(;
        assertion_basis = "official_actual_release_date",
        start_date = "2026-01-15",
        end_date = start_date,
        source_timezone = "America/New_York",
    )
    return date_evidence(
        assertion_basis = assertion_basis,
        start_date = start_date,
        end_date = end_date,
        source_timezone = source_timezone,
        start_offset = sealed_offset(source_timezone, start_date),
        end_offset = sealed_offset(
            source_timezone,
            Date(end_date) + Day(1),
        ),
    )
end

function changed(evidence, field, value; reseal = true)
    candidate = deepcopy(evidence)
    candidate[field] = value
    reseal && stamp_evidence_sha256!(candidate)
    return candidate
end

function without(evidence, field)
    candidate = deepcopy(evidence)
    delete!(candidate, field)
    return candidate
end

function thrown_message(call)
    try
        call()
    catch error
        return sprint(showerror, error)
    end
    return nothing
end

@testset "sealed release-availability policy" begin
    policy = load_policy(POLICY_PATH)

    @test validate_policy(policy) === policy
    @test policy_sha256(policy) == POLICY_SHA256
    @test load_policy() == policy
    @test canonical_sha256(Dict("b" => 2, "a" => 1)) ==
        canonical_sha256(Dict("a" => 1, "b" => 2))
    @test canonical_sha256(["a", "b"]) != canonical_sha256(["b", "a"])

    stale = deepcopy(policy)
    stale["scope"]["production_scoring_allowed"] = true
    @test_throws AvailabilityValidationError validate_policy(stale)

    restamped = deepcopy(stale)
    restamped["artifact"]["content_sha256"] = policy_sha256(restamped)
    @test_throws AvailabilityValidationError validate_policy(restamped)

    missing = deepcopy(policy)
    delete!(missing["interval"], "safe_not_before_rule")
    @test_throws AvailabilityValidationError validate_policy(missing)

    unknown = deepcopy(policy)
    unknown["scope"]["admission_mode"] = "none"
    @test_throws AvailabilityValidationError validate_policy(unknown)

    legacy_policy = deepcopy(policy)
    legacy_policy["artifact"]["schema_version"] =
        "beforeit-us-release-availability-policy.v1"
    legacy_policy["artifact"]["policy_id"] =
        "beforeit-us-retrospective-release-availability.v1"
    legacy_policy["artifact"]["content_sha256"] =
        policy_sha256(legacy_policy)
    @test_throws AvailabilityValidationError validate_policy(legacy_policy)

    zero_hash = deepcopy(policy)
    zero_hash["artifact"]["content_sha256"] = ZERO_SHA256
    @test_throws AvailabilityValidationError validate_policy(zero_hash)

    uppercase_hash = deepcopy(policy)
    uppercase_hash["artifact"]["content_sha256"] = uppercase(POLICY_SHA256)
    @test_throws AvailabilityValidationError validate_policy(uppercase_hash)

    for (section, field) in (
            ("scope", "empirical_forecast_execution_allowed"),
            ("scope", "production_scoring_allowed"),
            ("scope", "origin_admission_authorized"),
            ("scope", "inventory_mutation_authorized"),
            ("interval", "same_local_day_origin_allowed"),
            ("timezone", "runtime_tzdb_dependency_allowed"),
        )
        tampered = deepcopy(policy)
        tampered[section][field] = true
        tampered["artifact"]["content_sha256"] = policy_sha256(tampered)
        @test_throws AvailabilityValidationError validate_policy(tampered)
    end

    for (section, field) in (
            ("scope", "temporal_gate_only"),
            ("interval", "origin_at_upper_bound_temporal_gate_allowed"),
            ("timezone", "source_timezone_required"),
            ("timezone", "timezone_rules_evidence_required"),
            (
                "evidence",
                "availability_release_byte_and_vintage_evidence_must_be_pairwise_distinct",
            ),
        )
        tampered = deepcopy(policy)
        tampered[section][field] = false
        tampered["artifact"]["content_sha256"] = policy_sha256(tampered)
        @test_throws AvailabilityValidationError validate_policy(tampered)
    end
end

@testset "pinned IANA TZDB local-midnight semantics" begin
    semantics = load_timezone_semantics()
    @test validate_timezone_semantics(semantics) === semantics
    @test timezone_semantics_sha256(semantics) == TIMEZONE_SEMANTICS_SHA256
    @test semantics["artifact"]["content_sha256"] == TIMEZONE_SEMANTICS_SHA256
    @test semantics["source"]["iana_tzdb_version"] == "2026c"
    @test semantics["coverage"]["local_date_start_inclusive"] == "1997-01-01"
    @test semantics["coverage"]["local_date_end_inclusive"] == "2036-01-01"

    for timezone in ("UTC", "America/New_York", "America/Chicago")
        segments = semantics["zones"][timezone]["segments"]
        for (index, segment) in enumerate(segments)
            local_date = Date(segment["local_date_start"])
            @test sealed_offset(timezone, local_date) == segment["utc_offset"]
            if index > 1
                @test sealed_offset(timezone, local_date - Day(1)) ==
                    segments[index - 1]["utc_offset"]
            end
        end
    end
    @test sealed_offset("UTC", "2026-03-08") == "+00:00"
    @test sealed_offset("America/New_York", "2026-03-08") == "-05:00"
    @test sealed_offset("America/New_York", "2026-03-09") == "-04:00"
    @test sealed_offset("America/New_York", "2026-11-01") == "-04:00"
    @test sealed_offset("America/New_York", "2026-11-02") == "-05:00"
    @test sealed_offset("America/Chicago", "2026-03-08") == "-06:00"
    @test sealed_offset("America/Chicago", "2026-03-09") == "-05:00"
    @test sealed_offset("America/Chicago", "2026-11-02") == "-06:00"

    tampered = deepcopy(semantics)
    tampered["zones"]["America/New_York"]["segments"][1]["utc_offset"] =
        "-04:00"
    @test_throws AvailabilityValidationError validate_timezone_semantics(tampered)
    tampered["artifact"]["content_sha256"] = timezone_semantics_sha256(tampered)
    @test_throws AvailabilityValidationError validate_timezone_semantics(tampered)

    missing = deepcopy(semantics)
    delete!(missing["source"], "generation_method")
    @test_throws AvailabilityValidationError validate_timezone_semantics(missing)

    nonmonotonic = deepcopy(semantics)
    nonmonotonic["zones"]["America/New_York"]["segments"][2]["local_date_start"] =
        "1997-01-01"
    @test_throws AvailabilityValidationError validate_timezone_semantics(nonmonotonic)
end

@testset "exact actual-public timestamps" begin
    policy = load_policy()
    evidence = exact_evidence()
    @test validate_evidence(policy, evidence) === evidence
    @test evidence_sha256(evidence) == evidence["content_sha256"]

    window = derive_availability_window(policy, evidence)
    expected = DateTime(2026, 4, 30, 12, 30)
    @test window.assertion_basis == "actual_public_timestamp"
    @test window.lower_bound_utc == expected
    @test window.upper_bound_utc == expected
    @test window.safe_not_before_utc == expected
    @test window.interval_hours == 0
    @test isnothing(window.source_timezone)

    before =
        evaluate_temporal_gate(policy, evidence, "2026-04-30T12:29:59Z")
    equal =
        evaluate_temporal_gate(policy, evidence, "2026-04-30T12:30:00Z")
    after =
        evaluate_temporal_gate(policy, evidence, "2026-04-30T12:30:01Z")
    @test !before.temporal_gate_pass
    @test before.reason_code == "ORIGIN_BEFORE_SAFE_NOT_BEFORE"
    @test equal.temporal_gate_pass
    @test after.temporal_gate_pass
    @test equal.reason_code ==
        "TEMPORAL_GATE_SATISFIED_NO_ADMISSION"
    @test equal.schema_version ==
        "beforeit-us-release-temporal-gate-result.v2"
    @test equal.evidence_id == evidence["evidence_id"]
    @test equal.release_event_id == evidence["release_event_id"]
    @test equal.policy_sha256 == POLICY_SHA256
    @test equal.evidence_sha256 == evidence["content_sha256"]
    @test equal.evidence_scope == "retrospective_research"
    @test equal.temporal_gate_only
    @test !equal.origin_admission_authorized
    @test !equal.empirical_forecast_execution_allowed
    @test !equal.production_scoring_allowed
    @test !equal.inventory_mutation_authorized

    again =
        evaluate_temporal_gate(policy, evidence, "2026-04-30T12:30:00Z")
    @test again == equal

    legacy_evidence = deepcopy(evidence)
    legacy_evidence["schema_version"] =
        "beforeit-us-release-availability-evidence.v1"
    stamp_evidence_sha256!(legacy_evidence)
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        legacy_evidence,
    )

    for invalid in (
            "2026-04-30",
            "2026-04-30T12:30Z",
            "2026-04-30T12:30:00",
            "2026-04-30T12:30:00+00:00",
            "2026-04-30T12:30:00.000Z",
            "2026-02-30T12:30:00Z",
            " 2026-04-30T12:30:00Z",
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            exact_evidence(timestamp = invalid),
        )
    end
    @test_throws AvailabilityValidationError evaluate_temporal_gate(
        policy,
        evidence,
        "2026-04-30",
    )

    extra = deepcopy(evidence)
    extra["local_start_date"] = "2026-04-30"
    stamp_evidence_sha256!(extra)
    @test_throws AvailabilityValidationError validate_evidence(policy, extra)
end

@testset "explicitly rejected and unknown bases" begin
    policy = load_policy()
    for assertion_basis in (
            "schedule_only",
            "planned_release_date",
            "retrieval_timestamp",
            "unexplained_vintage_date",
            "route_level_claim",
            "unknown_timezone",
            "scheduled_release_date",
            "retrieval_date",
            "inferred_publication_time",
            "vintage_date",
        )
        evidence = exact_evidence(assertion_basis = assertion_basis)
        message = thrown_message() do
            validate_evidence(policy, evidence)
        end
        @test message !== nothing
        @test occursin("evidence.assertion_basis", message)
    end
end

@testset "official actual dates and DST boundaries" begin
    policy = load_policy()

    normal = date_evidence()
    normal_window = derive_availability_window(policy, normal)
    @test normal_window.lower_bound_utc ==
        DateTime(2026, 1, 15, 5)
    @test normal_window.upper_bound_utc ==
        DateTime(2026, 1, 16, 5)
    @test normal_window.safe_not_before_utc ==
        DateTime(2026, 1, 16, 5)
    @test normal_window.interval_hours == 24
    @test normal_window.source_timezone == "America/New_York"

    spring = date_evidence(
        start_date = "2026-03-08",
        start_offset = "-05:00",
        end_offset = "-04:00",
    )
    spring_window = derive_availability_window(policy, spring)
    @test spring_window.lower_bound_utc ==
        DateTime(2026, 3, 8, 5)
    @test spring_window.upper_bound_utc ==
        DateTime(2026, 3, 9, 4)
    @test spring_window.interval_hours == 23

    fall = date_evidence(
        start_date = "2026-11-01",
        start_offset = "-04:00",
        end_offset = "-05:00",
    )
    fall_window = derive_availability_window(policy, fall)
    @test fall_window.lower_bound_utc ==
        DateTime(2026, 11, 1, 4)
    @test fall_window.upper_bound_utc ==
        DateTime(2026, 11, 2, 5)
    @test fall_window.interval_hours == 25

    same_local_day =
        evaluate_temporal_gate(policy, spring, "2026-03-09T03:59:59Z")
    at_upper =
        evaluate_temporal_gate(policy, spring, "2026-03-09T04:00:00Z")
    later =
        evaluate_temporal_gate(policy, spring, "2026-03-09T04:00:01Z")
    @test !same_local_day.temporal_gate_pass
    @test at_upper.temporal_gate_pass
    @test later.temporal_gate_pass
    @test at_upper.temporal_gate_only
    @test !at_upper.origin_admission_authorized
    @test !at_upper.empirical_forecast_execution_allowed
    @test !at_upper.production_scoring_allowed

    utc_leap_day = date_evidence(
        start_date = "2024-02-29",
        source_timezone = "UTC",
        start_offset = "+00:00",
        end_offset = "+00:00",
    )
    leap_window = derive_availability_window(policy, utc_leap_day)
    @test leap_window.lower_bound_utc == DateTime(2024, 2, 29)
    @test leap_window.upper_bound_utc == DateTime(2024, 3, 1)
    @test leap_window.interval_hours == 24

    year_end = date_evidence(
        start_date = "2026-12-31",
        source_timezone = "UTC",
        start_offset = "+00:00",
        end_offset = "+00:00",
    )
    year_window = derive_availability_window(policy, year_end)
    @test year_window.lower_bound_utc == DateTime(2026, 12, 31)
    @test year_window.upper_bound_utc == DateTime(2027, 1, 1)

    before_2007_rule_change = semantically_valid_date_evidence(
        start_date = "2006-03-12",
        source_timezone = "America/New_York",
    )
    old_rule_spring = semantically_valid_date_evidence(
        start_date = "2006-04-02",
        source_timezone = "America/New_York",
    )
    new_rule_spring = semantically_valid_date_evidence(
        start_date = "2007-03-11",
        source_timezone = "America/New_York",
    )
    @test derive_availability_window(
        policy,
        before_2007_rule_change,
    ).interval_hours == 24
    @test derive_availability_window(
        policy,
        old_rule_spring,
    ).interval_hours == 23
    @test derive_availability_window(
        policy,
        new_rule_spring,
    ).interval_hours == 23
end

@testset "official actual date ranges" begin
    policy = load_policy()

    normal = date_evidence(
        assertion_basis = "official_actual_release_date_range",
        start_date = "2026-01-15",
        end_date = "2026-01-16",
    )
    normal_window = derive_availability_window(policy, normal)
    @test normal_window.lower_bound_utc ==
        DateTime(2026, 1, 15, 5)
    @test normal_window.upper_bound_utc ==
        DateTime(2026, 1, 17, 5)
    @test normal_window.interval_hours == 48

    spring = date_evidence(
        assertion_basis = "official_actual_release_date_range",
        start_date = "2026-03-07",
        end_date = "2026-03-08",
        start_offset = "-05:00",
        end_offset = "-04:00",
    )
    spring_window = derive_availability_window(policy, spring)
    @test spring_window.lower_bound_utc ==
        DateTime(2026, 3, 7, 5)
    @test spring_window.upper_bound_utc ==
        DateTime(2026, 3, 9, 4)
    @test spring_window.interval_hours == 47

    fall = date_evidence(
        assertion_basis = "official_actual_release_date_range",
        start_date = "2026-10-31",
        end_date = "2026-11-01",
        start_offset = "-04:00",
        end_offset = "-05:00",
    )
    fall_window = derive_availability_window(policy, fall)
    @test fall_window.lower_bound_utc ==
        DateTime(2026, 10, 31, 4)
    @test fall_window.upper_bound_utc ==
        DateTime(2026, 11, 2, 5)
    @test fall_window.interval_hours == 49

    @test !evaluate_temporal_gate(
        policy,
        spring,
        "2026-03-09T03:59:59Z",
    ).temporal_gate_pass
    @test evaluate_temporal_gate(
        policy,
        spring,
        "2026-03-09T04:00:00Z",
    ).temporal_gate_pass

    same_date_range = date_evidence(
        assertion_basis = "official_actual_release_date_range",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        same_date_range,
    )

    reversed_range = date_evidence(
        assertion_basis = "official_actual_release_date_range",
        start_date = "2026-01-16",
        end_date = "2026-01-15",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        reversed_range,
    )

    noncanonical_single = date_evidence(end_date = "2026-01-16")
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        noncanonical_single,
    )
end

@testset "timezone and sealed-offset failures" begin
    policy = load_policy()
    valid = date_evidence()

    for unknown_timezone in (
            "unknown",
            "Mars/Olympus",
            "EST",
            "America/Phoenix",
            "",
        )
        candidate = changed(
            valid,
            "source_timezone",
            unknown_timezone,
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            candidate,
        )
    end

    for invalid_offset in (
            "-5:00",
            "05:00",
            "-05",
            "-05:60",
            "-14:01",
            "+99:00",
            "unknown",
        )
        candidate = changed(valid, "start_utc_offset", invalid_offset)
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            candidate,
        )
    end

    wrong_zone_offset = changed(valid, "start_utc_offset", "-06:00")
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        wrong_zone_offset,
    )

    utc_with_dst = date_evidence(
        source_timezone = "UTC",
        start_offset = "+00:00",
        end_offset = "+01:00",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        utc_with_dst,
    )

    impossible_22_hour_day = changed(valid, "end_utc_offset", "-03:00")
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        impossible_22_hour_day,
    )

    for field in (
            "source_timezone",
            "start_utc_offset",
            "end_utc_offset",
            "timezone_rules_evidence_locator",
            "timezone_rules_evidence_sha256",
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            without(valid, field),
        )
    end

    # Both values are individually allowed for New York, but January has no
    # DST transition. This is the prior fictitious-January-DST counterexample.
    fictitious_january_dst = date_evidence(end_offset = "-04:00")
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        fictitious_january_dst,
    )
    fictitious_chicago_january_dst = date_evidence(
        source_timezone = "America/Chicago",
        start_offset = "-06:00",
        end_offset = "-05:00",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        fictitious_chicago_january_dst,
    )

    wrong_transition_day = date_evidence(
        start_date = "2026-03-08",
        start_offset = "-04:00",
        end_offset = "-04:00",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        wrong_transition_day,
    )

    unbound_semantics = changed(
        valid,
        "timezone_rules_evidence_locator",
        "urn:beforeit:iana-tzdb:some-other-artifact",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        unbound_semantics,
    )
    wrong_semantics_hash = changed(
        valid,
        "timezone_rules_evidence_sha256",
        repeat("e", 64),
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        wrong_semantics_hash,
    )
end

@testset "semantic date, range, and coverage boundaries" begin
    policy = load_policy()
    for (timezone, normal_date) in (
            ("UTC", "2026-01-15"),
            ("America/New_York", "2026-01-15"),
            ("America/Chicago", "2026-07-15"),
        )
        evidence = semantically_valid_date_evidence(
            start_date = normal_date,
            source_timezone = timezone,
        )
        @test validate_evidence(policy, evidence) === evidence
        window = derive_availability_window(policy, evidence)
        @test window.upper_bound_utc > window.lower_bound_utc
        @test !evaluate_temporal_gate(
            policy,
            evidence,
            Dates.format(
                window.upper_bound_utc - Second(1),
                dateformat"yyyy-mm-ddTHH:MM:SS",
            ) * "Z",
        ).temporal_gate_pass
        @test evaluate_temporal_gate(
            policy,
            evidence,
            Dates.format(
                window.upper_bound_utc,
                dateformat"yyyy-mm-ddTHH:MM:SS",
            ) * "Z",
        ).temporal_gate_pass
    end

    for timezone in ("America/New_York", "America/Chicago")
        spring = semantically_valid_date_evidence(
            start_date = "2026-03-08",
            source_timezone = timezone,
        )
        fall = semantically_valid_date_evidence(
            start_date = "2026-11-01",
            source_timezone = timezone,
        )
        @test derive_availability_window(policy, spring).interval_hours == 23
        @test derive_availability_window(policy, fall).interval_hours == 25
        crossing_spring = semantically_valid_date_evidence(
            assertion_basis = "official_actual_release_date_range",
            start_date = "2026-03-07",
            end_date = "2026-03-08",
            source_timezone = timezone,
        )
        crossing_fall = semantically_valid_date_evidence(
            assertion_basis = "official_actual_release_date_range",
            start_date = "2026-10-31",
            end_date = "2026-11-01",
            source_timezone = timezone,
        )
        @test derive_availability_window(policy, crossing_spring).interval_hours == 47
        @test derive_availability_window(policy, crossing_fall).interval_hours == 49
    end

    first_supported = semantically_valid_date_evidence(
        start_date = "1997-01-01",
        source_timezone = "America/New_York",
    )
    last_supported = semantically_valid_date_evidence(
        start_date = "2035-12-31",
        source_timezone = "America/New_York",
    )
    @test validate_evidence(policy, first_supported) === first_supported
    @test validate_evidence(policy, last_supported) === last_supported

    before_coverage = date_evidence(
        start_date = "1996-12-31",
        end_date = "1996-12-31",
        start_offset = "-05:00",
        end_offset = "-05:00",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        before_coverage,
    )
    beyond_coverage = date_evidence(
        start_date = "2036-01-01",
        end_date = "2036-01-01",
        start_offset = "-05:00",
        end_offset = "-05:00",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        beyond_coverage,
    )
    range_beyond_coverage = date_evidence(
        assertion_basis = "official_actual_release_date_range",
        start_date = "2035-12-30",
        end_date = "2036-01-01",
        start_offset = "-05:00",
        end_offset = "-05:00",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        range_beyond_coverage,
    )
end

@testset "hash, evidence-class, topology, and scope failures" begin
    policy = load_policy()
    exact = exact_evidence()
    date = date_evidence()

    for field in (
            "availability_evidence_sha256",
            "release_byte_evidence_sha256",
            "vintage_evidence_sha256",
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            without(exact, field),
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            changed(exact, field, ZERO_SHA256; reseal = false),
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            changed(exact, field, repeat("A", 64); reseal = false),
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            changed(exact, field, repeat("a", 63); reseal = false),
        )
    end

    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        changed(date, "timezone_rules_evidence_sha256", ZERO_SHA256),
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        changed(date, "timezone_rules_evidence_sha256", repeat("D", 64)),
    )

    zero_content = changed(exact, "content_sha256", ZERO_SHA256; reseal = false)
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        zero_content,
    )

    stale_content = deepcopy(exact)
    stale_content["source_id"] = "bls"
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        stale_content,
    )

    same_byte_and_vintage_hash = changed(
        exact,
        "vintage_evidence_sha256",
        exact["release_byte_evidence_sha256"],
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        same_byte_and_vintage_hash,
    )

    same_byte_and_vintage_locator = changed(
        exact,
        "vintage_evidence_locator",
        exact["release_byte_evidence_locator"],
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        same_byte_and_vintage_locator,
    )

    for (availability_field, aliased_field) in (
            (
                "availability_evidence_locator",
                "release_byte_evidence_locator",
            ),
            (
                "availability_evidence_locator",
                "vintage_evidence_locator",
            ),
            (
                "availability_evidence_sha256",
                "release_byte_evidence_sha256",
            ),
            (
                "availability_evidence_sha256",
                "vintage_evidence_sha256",
            ),
        )
        aliased = changed(
            exact,
            availability_field,
            exact[aliased_field],
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            aliased,
        )
    end

    same_timezone_and_byte_hash = changed(
        date,
        "timezone_rules_evidence_sha256",
        date["release_byte_evidence_sha256"],
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        same_timezone_and_byte_hash,
    )

    same_timezone_and_availability_locator = changed(
        date,
        "timezone_rules_evidence_locator",
        date["availability_evidence_locator"],
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        same_timezone_and_availability_locator,
    )

    for field in (
            "evidence_id",
            "release_event_id",
            "source_id",
            "availability_evidence_locator",
            "release_byte_evidence_locator",
            "vintage_evidence_locator",
            "content_sha256",
        )
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            without(exact, field),
        )
    end

    for (field, value) in (
            ("evidence_scope", "prospective"),
            ("empirical_forecast_execution_allowed", true),
            ("production_scoring_allowed", true),
            ("origin_admission_authorized", true),
            ("inventory_mutation_authorized", true),
        )
        candidate = changed(exact, field, value)
        @test_throws AvailabilityValidationError validate_evidence(
            policy,
            candidate,
        )
    end

    unknown = deepcopy(exact)
    unknown["ready"] = false
    stamp_evidence_sha256!(unknown)
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        unknown,
    )

    wrong_type = changed(
        exact,
        "production_scoring_allowed",
        0,
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        wrong_type,
    )

    invalid_locator = changed(
        exact,
        "release_byte_evidence_locator",
        "relative/path",
    )
    @test_throws AvailabilityValidationError validate_evidence(
        policy,
        invalid_locator,
    )
end
