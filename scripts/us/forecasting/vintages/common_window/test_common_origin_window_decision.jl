using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USCommonOriginWindowDecision.jl"))
using .USCommonOriginWindowDecision

const DECISION_PATH = DEFAULT_DECISION_PATH
const MODULE_PATH =
    joinpath(@__DIR__, "USCommonOriginWindowDecision.jl")

function captured_error(callback)
    return try
        callback()
        nothing
    catch error
        error
    end
end

function restamp_for_negative_test!(decision)
    decision["artifact"]["content_sha256"] =
        computed_content_sha256(decision)
    return decision
end

function check_invalid(
        original,
        mutator,
        message_fragment;
        restamp = true,
    )
    candidate = deepcopy(original)
    mutator(candidate)
    restamp && restamp_for_negative_test!(candidate)
    error = captured_error() do
        validate_decision(candidate)
    end
    @test error isa USCommonOriginWindowError
    @test occursin(message_fragment, sprint(showerror, error))
    return error
end

@testset "sealed offline common-window decision" begin
    source_before = read(DECISION_PATH)
    artifact = decision_artifact()

    @test artifact.artifact.schema_version == SCHEMA_VERSION
    @test artifact.artifact.canonicalization == CANONICALIZATION
    @test artifact.artifact.content_sha256 == EXPECTED_CONTENT_SHA256
    @test artifact.artifact.content_sha256 ==
        computed_content_sha256(TOML.parsefile(DECISION_PATH))
    @test artifact.file_sha256 == bytes2hex(sha256(source_before))
    @test artifact.file_byte_count == length(source_before)
    @test artifact.canonical_content isa String
    @test length(artifact.canonical_content) > 15_000
    @test !(:manifest in propertynames(artifact))
    @test !(:document in propertynames(artifact))
    @test read(DECISION_PATH) == source_before

    decision = artifact.decision
    @test decision.inventory_sha256 ==
        "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"
    @test decision.admitted_origin_count == 0
    @test decision.promotion_passed == 0
    @test decision.promotion_total == 8
    @test decision.strict_all_three_intersection_count == 0
    @test decision.metadata_only === true
    for key in (
            :network_access_allowed,
            :raw_bytes_stored,
            :source_inventory_mutation_authorized,
            :empirical_results_stored,
            :production_claim_allowed,
        )
        @test getproperty(decision, key) === false
    end
    @test all(value -> value === false, values(artifact.gates))
    boundary = artifact.prospective_boundary
    @test boundary.public_and_inspected_through_quarter == "2026Q2"
    @test boundary.earliest_genuinely_prospective_quarter == "2026Q3"
    @test boundary.adjacent_reserve_id ==
        "ADJACENT_2026Q2_EVALUATION_RESERVE"
    @test boundary.adjacent_reserve_holdout_integrity == "UNVERIFIED"
    @test boundary.adjacent_reserve_is_prospective === false
    @test boundary.prospective_reserve_registered === false
end

@testset "source ranges and reproduced intersections" begin
    result = load_decision()
    windows = result.source_windows
    @test windows isa Tuple
    @test length(windows) == 3
    @test [
        (
                row.window_id,
                row.first_quarter,
                row.last_quarter,
                row.quarter_count,
            ) for row in windows
    ] == [
        ("BEA_HMI7_RELEASE_METADATA_40", "2011Q3", "2021Q2", 40),
        (
            "BLS_QUARTER_END_ARCHIVE_METADATA_40",
            "2015Q1",
            "2024Q4",
            40,
        ),
        (
            "EFFR_CLEAN_POST_BREAK_CANDIDATE_40",
            "2016Q2",
            "2026Q1",
            40,
        ),
    ]

    intersections = result.intersections
    @test [
        (
                row.intersection_id,
                row.first_quarter,
                row.last_quarter,
                row.quarter_count,
            ) for row in intersections
    ] == [
        ("BEA_X_BLS", "2015Q1", "2021Q2", 26),
        ("BEA_X_EFFR", "2016Q2", "2021Q2", 21),
        ("BLS_X_EFFR", "2016Q2", "2024Q4", 35),
        ("BEA_X_BLS_X_EFFR", "2016Q2", "2021Q2", 21),
    ]
    @test all(row.strict_admitted_origin_count == 0 for row in intersections)
    @test all(row.strict_admissible === false for row in intersections)
end

@testset "route-level 41, fixed 40, and adjacent reserve decomposition" begin
    roles = load_decision().effr_window_roles
    @test [
        (
                row.role_id,
                row.first_quarter,
                row.last_quarter,
                row.quarter_count,
            ) for row in roles
    ] == [
        ("ROUTE_LEVEL_CANDIDATE_41", "2016Q2", "2026Q2", 41),
        (
            "FROZEN_FIXED_40_RESEARCH_CANDIDATE",
            "2016Q2",
            "2026Q1",
            40,
        ),
        (
            "ADJACENT_2026Q2_EVALUATION_RESERVE",
            "2026Q2",
            "2026Q2",
            1,
        ),
    ]
    @test roles[2].included_in_fixed_40 === true
    @test roles[3].reserve_class ==
        "ADJACENT_2026Q2_EVALUATION_RESERVE"
    @test roles[3].holdout_integrity == "UNVERIFIED"
    @test roles[3].public_at_freeze === true
    @test roles[3].prospective_at_freeze === false
    @test all(row.reserve_class in RESERVE_CLASSES for row in roles)
    @test all(
        row.holdout_integrity in HOLDOUT_INTEGRITY_STATES for row in roles
    )
    @test all(row.origin_admitted === false for row in roles)
    @test all(row.empirical_execution_allowed === false for row in roles)
end

@testset "typed tracks and source governance" begin
    result = load_decision()
    @test getproperty.(result.tracks, :track_id) == TRACK_IDS
    @test getproperty.(result.tracks, :allowed_conclusion) ==
        ALLOWED_CONCLUSIONS
    @test all(
        row ->
        all(
            getproperty(row, key) === false for key in (
                    :source_coverage_proven,
                    :terms_authorization_complete,
                    :artifact_capture_complete,
                    :truth_maturity_proven,
                    :origin_admission_complete,
                    :empirical_execution_allowed,
                    :production_eligible,
                )
        ),
        result.tracks,
    )
    @test all(
        blocker in BLOCKER_STATES for row in result.tracks for
            blocker in row.blockers
    )

    routes = Dict(row.route_id => row for row in result.source_routes)
    @test routes["ALFRED_EFFR_DATE_LEVEL_VINTAGE"].terms_state ==
        "TERMS_LOCAL_GOVERNANCE_BLOCKED_PENDING_REVIEW"
    @test routes["ALFRED_EFFR_DATE_LEVEL_VINTAGE"].
    artifact_provenance_state == "DATE_LEVEL_VINTAGE"
    @test routes["NYFED_EFFR_CURRENT_API"].artifact_provenance_state ==
        "CURRENT_STATE_WITH_REVISION_FLAG_NOT_VINTAGE"
    @test routes["BOARD_H15_CURRENT_SERIES"].artifact_provenance_state ==
        "CURRENT_STATE_WITH_REVISION_FLAG_NOT_VINTAGE"
    @test routes["BOARD_H15_PRE_2016_ISSUE_ARCHIVE"].concept_state ==
        "CONCEPT_BREAK"
    @test routes["BOARD_H15_PRE_2016_ISSUE_ARCHIVE"].source_role ==
        "QUARANTINED"
    @test all(
        row ->
        all(
            getproperty(row, key) === false for key in (
                    :source_coverage_proven,
                    :terms_authorization_complete,
                    :artifact_capture_complete,
                    :truth_maturity_proven,
                    :origin_admission_complete,
                )
        ),
        values(routes),
    )
end

@testset "irregularities remain typed and non-admitted" begin
    irregularities = load_decision().irregularities
    @test length(irregularities) == 5
    @test count(
        row ->
        row.irregularity_state ==
            "INITIAL_REPLACES_ADVANCE_AND_SECOND",
        irregularities,
    ) == 2
    @test any(
        row ->
        row.period == "2019Q4" &&
            row.irregularity_state == "REISSUED_CORRECTED",
        irregularities,
    )
    @test any(
        row ->
        row.period == "2025Q3" &&
            row.agency == "BLS" &&
            row.irregularity_state == "DELAYED_BY_FEDERAL_LAPSE",
        irregularities,
    )
    skipped = only(
        filter(
            row ->
            row.irregularity_state ==
                "SKIPPED_NOT_PUBLISHED_NON_PANEL_MONTH",
            irregularities,
        ),
    )
    @test skipped.period == "2025-10"
    @test skipped.panel_relation == "NON_PANEL_MONTH"
    @test all(row.admitted === false for row in irregularities)
end

@testset "trusted returns do not alias caller mutation" begin
    parsed = TOML.parsefile(DECISION_PATH)
    validated = validate_decision(parsed)

    parsed["decision"]["admitted_origin_count"] = 21
    parsed["gates"]["ready"] = true
    parsed["prospective_boundary"]["adjacent_reserve_is_prospective"] = true
    parsed["source_windows"][1]["first_quarter"] = "2011Q4"
    parsed["tracks"][1]["blockers"][1] = "Other"
    parsed["citations"][1]["url"] = "https://example.invalid/"

    @test validated.decision.admitted_origin_count == 0
    @test validated.gates.ready === false
    @test validated.prospective_boundary.
    adjacent_reserve_is_prospective === false
    @test validated.source_windows[1].first_quarter == "2011Q3"
    @test validated.tracks[1].blockers[1] ==
        "SOURCE_COVERAGE_NOT_PROVEN"
    @test startswith(validated.citations[1].url, "https://apps.bea.gov/")
    @test_throws MethodError setindex!(
        validated.source_windows,
        validated.source_windows[2],
        1,
    )
    @test_throws ErrorException setproperty!(
        validated.source_windows[1],
        :first_quarter,
        "2011Q4",
    )
end

@testset "deterministic canonicalization and no stamping API" begin
    original = TOML.parsefile(DECISION_PATH)
    expected = computed_content_sha256(original)
    reordered = Dict(reverse(collect(pairs(deepcopy(original)))))
    @test computed_content_sha256(reordered) == expected

    with_comment = TOML.parse(
        "# non-semantic comment\n" * read(DECISION_PATH, String),
    )
    @test computed_content_sha256(with_comment) == expected

    changed_declared_hash = deepcopy(original)
    changed_declared_hash["artifact"]["content_sha256"] = repeat("f", 64)
    @test computed_content_sha256(changed_declared_hash) == expected

    reversed_tracks = deepcopy(original)
    reverse!(reversed_tracks["tracks"])
    @test computed_content_sha256(reversed_tracks) != expected

    typed_change = deepcopy(original)
    typed_change["decision"]["admitted_origin_count"] = false
    @test computed_content_sha256(typed_change) != expected

    @test !isdefined(
        USCommonOriginWindowDecision,
        :stamp_content_sha256!,
    )
    @test !isdefined(
        USCommonOriginWindowDecision,
        :restamp_content_sha256!,
    )
    module_source = read(MODULE_PATH, String)
    @test !occursin("function stamp", module_source)
    @test !occursin("function restamp", module_source)
end

@testset "fail closed on schema, gates, enums, and ranges" begin
    original = TOML.parsefile(DECISION_PATH)

    check_invalid(
        original,
        decision -> (decision["unknown"] = true),
        "unknown keys",
    )
    check_invalid(
        original,
        decision -> delete!(decision, "gates"),
        "missing keys",
    )
    check_invalid(
        original,
        decision -> (
            decision["decision"]["admitted_origin_count"] = true
        ),
        "admitted_origin_count",
    )
    check_invalid(
        original,
        decision -> (decision["gates"]["ready"] = true),
        "decision.gates.ready",
    )
    check_invalid(
        original,
        decision -> (
            decision["tracks"][1]["empirical_execution_allowed"] = true
        ),
        "empirical_execution_allowed",
    )
    check_invalid(
        original,
        decision -> (
            decision["tracks"][1]["production_eligible"] = true
        ),
        "production_eligible",
    )
    check_invalid(
        original,
        decision -> (
            decision["source_windows"][1]["origin_admission_complete"] =
                true
        ),
        "origin_admission_complete",
    )
    check_invalid(
        original,
        decision -> (
            decision["source_windows"][1]["artifact_provenance_state"] =
                "Other"
        ),
        "bare Used/Other",
    )
    check_invalid(
        original,
        decision -> (
            decision["source_routes"][1]["source_role"] = "Used"
        ),
        "bare Used/Other",
    )
    check_invalid(
        original,
        decision -> (
            decision["tracks"][1]["allowed_conclusion"] =
                "UNREVIEWED_CONCLUSION"
        ),
        "unsupported closed-enum",
    )
    check_invalid(
        original,
        decision -> (
            decision["source_windows"][1]["first_quarter"] = "2011Q4"
        ),
        "first_quarter",
    )
    check_invalid(
        original,
        decision -> (
            decision["source_windows"][1]["quarter_count"] = 39
        ),
        "quarter_count",
    )
    check_invalid(
        original,
        decision -> (
            decision["intersections"][1]["first_quarter"] = "2015Q2"
        ),
        "first_quarter",
    )
    check_invalid(
        original,
        decision -> (
            decision["intersections"][3]["quarter_count"] = 34
        ),
        "quarter_count",
    )
    check_invalid(
        original,
        decision -> (
            decision["effr_window_roles"][1]["last_quarter"] = "2026Q1"
        ),
        "last_quarter",
    )
    check_invalid(
        original,
        decision -> (
            decision["prospective_boundary"][
                "adjacent_reserve_is_prospective",
            ] = true
        ),
        "adjacent_reserve_is_prospective",
    )
    check_invalid(
        original,
        decision -> (
            decision["prospective_boundary"][
                "adjacent_reserve_holdout_integrity",
            ] = "VERIFIED"
        ),
        "unsupported closed-enum",
    )
    check_invalid(
        original,
        decision -> (
            decision["prospective_boundary"][
                "earliest_genuinely_prospective_quarter",
            ] = "2026Q2"
        ),
        "earliest_genuinely_prospective_quarter",
    )
    check_invalid(
        original,
        decision -> (
            decision["effr_window_roles"][3]["prospective_at_freeze"] =
                true
        ),
        "prospective_at_freeze",
    )
    check_invalid(
        original,
        decision -> (
            decision["effr_window_roles"][3]["public_at_freeze"] = false
        ),
        "public_at_freeze",
    )
    check_invalid(
        original,
        decision -> (
            decision["effr_window_roles"][3]["holdout_integrity"] =
                "VERIFIED"
        ),
        "holdout_integrity",
    )
    check_invalid(
        original,
        decision -> (
            decision["effr_window_roles"][3]["reserve_class"] =
                "PROSPECTIVE_HOLDOUT"
        ),
        "reserve_class",
    )
    check_invalid(
        original,
        decision -> (
            decision["irregularities"][5]["period"] = "2025Q4"
        ),
        "period",
    )
    check_invalid(
        original,
        decision -> (
            decision["citations"][1]["citation_class"] = "BLOG"
        ),
        "OFFICIAL or ACADEMIC",
    )
end

@testset "compiled pin defeats plausible self-rehash bypass" begin
    original = TOML.parsefile(DECISION_PATH)
    candidate = deepcopy(original)
    candidate["source_routes"][4]["allowed_use"] =
        "PROMOTED_CURRENT_STATE"
    restamp_for_negative_test!(candidate)
    error = captured_error() do
        validate_decision(candidate)
    end
    @test error isa USCommonOriginWindowError
    @test occursin(
        "compiled sealed-contract pin",
        sprint(showerror, error),
    )

    wrong_declared = deepcopy(original)
    wrong_declared["artifact"]["content_sha256"] = repeat("f", 64)
    error2 = captured_error() do
        validate_decision(wrong_declared)
    end
    @test error2 isa USCommonOriginWindowError
    @test occursin("does not match computed", sprint(showerror, error2))
end
