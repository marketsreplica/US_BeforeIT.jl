using SHA
using Test

include("USStructuralAsOfSelector.jl")
using .USStructuralAsOfSelector

const Selector = USStructuralAsOfSelector

digest(label) = bytes2hex(SHA.sha256(codeunits(label)))

function release_record(
        component,
        generation;
        observation_start,
        observation_end,
        release_timestamp,
        availability_timestamp,
    )
    return Dict{String, Any}(
        "component_id" => component,
        "release_event_id" => "$component-release-$generation",
        "source_id" => "$component-source",
        "dataset_id" => "$component-dataset",
        "source_release_id" => "$component-source-release-$generation",
        "observation_period_start" => observation_start,
        "observation_period_end" => observation_end,
        "release_timestamp_utc" => release_timestamp,
        "availability_timestamp_utc" => availability_timestamp,
        "raw_sha256" => digest("$component-$generation"),
        "mapping_version" => "$component-map-$generation",
        "classification_system" => "$component-classification",
        "classification_version" => "$component-class-$generation",
        "quality_status" => "APPROVED",
    )
end

function fixture_releases(; include_future = true)
    rows = Dict{String, Any}[]
    for (index, component) in enumerate(Selector.REQUIRED_COMPONENTS)
        day = lpad(string(10 + index), 2, '0')
        push!(
            rows,
            release_record(
                component,
                "old";
                observation_start = "2018-01-01",
                observation_end = "2018-12-31",
                release_timestamp = "2019-09-$(day)T10:00:00Z",
                availability_timestamp = "2019-09-$(day)T11:00:00Z",
            ),
        )
        push!(
            rows,
            release_record(
                component,
                "new";
                observation_start = "2019-01-01",
                observation_end = "2019-12-31",
                release_timestamp = "2020-06-30T10:00:00Z",
                availability_timestamp = "2020-06-30T12:00:00Z",
            ),
        )
        include_future || continue
        push!(
            rows,
            release_record(
                component,
                "future";
                observation_start = "2024-01-01",
                observation_end = "2024-12-31",
                release_timestamp = "2025-06-30T10:00:00Z",
                availability_timestamp = "2025-06-30T12:00:00Z",
            ),
        )
    end
    return rows
end

function component_by_id(receipt, component_id)
    return only(
        filter(
            component -> component["component_id"] == component_id,
            receipt["components"],
        ),
    )
end

function restamp!(receipt)
    payload = deepcopy(receipt)
    pop!(payload, "content_sha256", nothing)
    receipt["content_sha256"] = canonical_sha256(payload)
    return receipt
end

@testset "registry binding and exact closed components" begin
    @test validate_registry_binding()
    @test Selector.Registry.canonical_sha256(Dict("a" => 1)) ==
        canonical_sha256(Dict("a" => 1))
    @test Selector.REQUIRED_COMPONENTS == [
        "io_or_supply_use",
        "fixed_assets",
        "firm_counts",
        "qcew_or_labor",
        "sector_or_financial_accounts",
        "classification_maps",
    ]
    normalized = validate_release_set(fixture_releases())
    @test length(normalized) == 18
    @test Set(release["component_id"] for release in normalized) ==
        Set(Selector.REQUIRED_COMPONENTS)
end

@testset "origin-eligible selection and exclusive carry boundary" begin
    releases = fixture_releases()
    before = build_structural_asof_receipt(
        releases,
        "2020-06-30T11:59:59Z",
    )
    @test validate_receipt(before, releases) === before
    @test before["selection_track"] == "ORIGIN_ELIGIBLE_AS_OF"
    @test before["structural_information_set_eligible"] === true
    @test before["retrospective_hindsight_selected"] === false
    @test before["future_period_structure_present"] === false
    @test before["pseudo_oos_structural_compatibility"] ==
        "COMPATIBLE_PENDING_ALL_OTHER_GATES"
    @test before["receipt_nonadmitting"] === true
    @test before["origin_admissible"] === false
    @test before["promotion_eligible"] === false
    @test before["accuracy_evidence"] === false
    @test all(
        component -> endswith(component["release_event_id"], "-old"),
        before["components"],
    )
    @test all(component -> component["eligible_at_origin"], before["components"])
    @test all(
        component -> component["carry_until_rule"] ==
            "EXCLUSIVE_NEXT_ORIGIN_ELIGIBLE_RELEASE_FOR_COMPONENT",
        before["components"],
    )

    at_boundary = build_structural_asof_receipt(
        releases,
        "2020-06-30T12:00:00Z",
    )
    @test all(
        component -> endswith(component["release_event_id"], "-new"),
        at_boundary["components"],
    )
    first_component = first(at_boundary["components"])
    @test first_component["structural_age_days_signed"] == 182
    @test first_component["structural_age_seconds_signed"] == 15_681_601
    @test first_component["release_age_seconds_signed"] == 7200
    @test first_component["availability_age_seconds_signed"] == 0
    @test first_component["mapping_version"] ==
        "io_or_supply_use-map-new"
    @test first_component["classification_version"] ==
        "io_or_supply_use-class-new"

    released_but_unavailable = deepcopy(releases)
    for release in released_but_unavailable
        endswith(release["release_event_id"], "-new") || continue
        release["release_timestamp_utc"] = "2020-06-30T09:00:00Z"
        release["availability_timestamp_utc"] = "2020-07-01T12:00:00Z"
    end
    waiting = build_structural_asof_receipt(
        released_but_unavailable,
        "2020-06-30T23:59:59Z",
    )
    @test all(
        component -> endswith(component["release_event_id"], "-old"),
        waiting["components"],
    )
    available = build_structural_asof_receipt(
        released_but_unavailable,
        "2020-07-01T12:00:00Z",
    )
    @test all(
        component -> endswith(component["release_event_id"], "-new"),
        available["components"],
    )
end

@testset "origin receipt is invariant to post-origin catalog growth" begin
    without_future = fixture_releases(; include_future = false)
    with_future = fixture_releases()
    origin = "2020-06-30T12:00:00Z"
    first_receipt = build_structural_asof_receipt(without_future, origin)
    later_catalog_receipt = build_structural_asof_receipt(with_future, origin)
    @test first_receipt == later_catalog_receipt
    @test first_receipt["considered_evidence_sha256"] ==
        later_catalog_receipt["considered_evidence_sha256"]
    @test first_receipt["content_sha256"] ==
        later_catalog_receipt["content_sha256"]

    shuffled = reverse(with_future)
    @test build_structural_asof_receipt(shuffled, origin) ==
        later_catalog_receipt

    future_tie = deepcopy(with_future)
    tied = deepcopy(
        only(
            filter(
                release -> release["release_event_id"] ==
                    "io_or_supply_use-release-future",
                future_tie,
            ),
        ),
    )
    tied["release_event_id"] = "io_or_supply_use-release-future-tie"
    tied["source_release_id"] =
        "io_or_supply_use-source-release-future-tie"
    tied["raw_sha256"] = digest("io-or-supply-use-future-tie")
    push!(future_tie, tied)
    @test build_structural_asof_receipt(future_tie, origin) ==
        later_catalog_receipt
end

@testset "hindsight selection is permanently nonpromotable" begin
    releases = fixture_releases()
    @test_throws StructuralAsOfError build_structural_asof_receipt(
        releases,
        "2020-06-30T12:00:00Z";
        selection_track = true,
    )
    @test_throws StructuralAsOfError build_structural_asof_receipt(
        releases,
        "2020-06-30T12:00:00Z";
        selection_track = "OTHER",
    )
    receipt = build_structural_asof_receipt(
        releases,
        "2020-06-30T12:00:00Z";
        selection_track = "RETROSPECTIVE_HINDSIGHT_SELECTED",
    )
    @test validate_receipt(receipt, releases) === receipt
    @test receipt["retrospective_hindsight_selected"] === true
    @test receipt["structural_information_set_eligible"] === false
    @test receipt["future_period_structure_present"] === true
    @test receipt["pseudo_oos_structural_compatibility"] == "FORBIDDEN"
    @test receipt["origin_admissible"] === false
    @test receipt["promotion_eligible"] === false
    @test "RETROSPECTIVE_HINDSIGHT_SELECTION_NONPROMOTABLE" in
        receipt["blockers"]
    @test "FUTURE_OBSERVATION_PERIOD_RELATIVE_TO_ORIGIN" in
        receipt["blockers"]
    @test "POST_ORIGIN_RELEASE_SELECTED" in receipt["blockers"]
    @test "POST_ORIGIN_AVAILABILITY_SELECTED" in receipt["blockers"]
    @test all(
        component -> endswith(component["release_event_id"], "-future"),
        receipt["components"],
    )
    @test all(
        component -> component["future_observation_period_relative_to_origin"] &&
            component["released_after_origin"] &&
            component["available_after_origin"] &&
            !component["eligible_at_origin"] &&
            component["structural_age_days_signed"] < 0,
        receipt["components"],
    )
end

@testset "unique latest and observation/release cutoffs fail closed" begin
    releases = fixture_releases()
    missing = filter(
        release -> release["component_id"] != "classification_maps",
        releases,
    )
    @test_throws StructuralAsOfError validate_release_set(missing)

    unknown = deepcopy(releases)
    unknown[1]["component_id"] = "other"
    @test_throws StructuralAsOfError validate_release_set(unknown)

    duplicate_id = deepcopy(releases)
    duplicate_id[2]["release_event_id"] =
        duplicate_id[1]["release_event_id"]
    @test_throws StructuralAsOfError validate_release_set(duplicate_id)

    ambiguous = deepcopy(releases)
    copy_release = deepcopy(first(ambiguous))
    copy_release["release_event_id"] = "io_or_supply_use-release-ambiguous"
    copy_release["source_release_id"] =
        "io_or_supply_use-source-release-ambiguous"
    copy_release["raw_sha256"] = digest("ambiguous")
    push!(ambiguous, copy_release)
    @test length(validate_release_set(ambiguous)) == length(ambiguous)
    @test_throws StructuralAsOfError build_structural_asof_receipt(
        ambiguous,
        "2019-12-31T23:59:59Z",
    )
    @test build_structural_asof_receipt(
        ambiguous,
        "2020-06-30T12:00:00Z",
    )["structural_information_set_eligible"]

    no_old = filter(
        release -> !endswith(release["release_event_id"], "-old"),
        releases,
    )
    @test_throws StructuralAsOfError build_structural_asof_receipt(
        no_old,
        "2020-01-01T00:00:00Z",
    )

    future_period_released_early = deepcopy(releases)
    future_period_released_early[1]["observation_period_end"] = "2020-12-31"
    @test_throws StructuralAsOfError validate_release_set(
        future_period_released_early,
    )

    same_day_period = deepcopy(releases)
    for release in same_day_period
        endswith(release["release_event_id"], "-new") || continue
        release["observation_period_start"] = "2020-06-30"
        release["observation_period_end"] = "2020-06-30"
        release["release_timestamp_utc"] = "2020-06-30T23:59:59Z"
        release["availability_timestamp_utc"] = "2020-06-30T23:59:59Z"
    end
    before_period_end = build_structural_asof_receipt(
        same_day_period,
        "2020-06-30T12:00:00Z",
    )
    @test all(
        component -> endswith(component["release_event_id"], "-old"),
        before_period_end["components"],
    )
    at_period_end = build_structural_asof_receipt(
        same_day_period,
        "2020-06-30T23:59:59Z",
    )
    @test all(
        component -> endswith(component["release_event_id"], "-new"),
        at_period_end["components"],
    )

    release_after_origin = deepcopy(releases)
    for release in release_after_origin
        endswith(release["release_event_id"], "-new") || continue
        release["release_timestamp_utc"] = "2020-07-01T10:00:00Z"
        release["availability_timestamp_utc"] = "2020-07-01T12:00:00Z"
    end
    selected = build_structural_asof_receipt(
        release_after_origin,
        "2020-06-30T23:59:59Z",
    )
    @test all(
        component -> endswith(component["release_event_id"], "-old"),
        selected["components"],
    )
end

@testset "strict field, timestamp, date, hash, and quality grammar" begin
    base = fixture_releases()
    for (key, value) in (
            ("release_timestamp_utc", "2020-06-30T10:00Z"),
            ("release_timestamp_utc", "2020-06-30T10:00:00.0Z"),
            ("release_timestamp_utc", "2020-06-30T12:00:00+02:00"),
            ("availability_timestamp_utc", "2020-02-30T10:00:00Z"),
            ("observation_period_end", "2019-02-29"),
            ("raw_sha256", uppercase(digest("bad"))),
            ("quality_status", "OTHER"),
            ("mapping_version", " map-v1"),
            ("classification_version", true),
        )
        changed = deepcopy(base)
        changed[1][key] = value
        @test_throws StructuralAsOfError validate_release_set(changed)
    end

    origin = "2020-06-30T12:00:00Z"
    baseline = build_structural_asof_receipt(
        fixture_releases(; include_future = false),
        origin,
    )
    for quality_status in ("DUBIOUS", "REJECTED")
        future_nonapproved = fixture_releases()
        for release in future_nonapproved
            endswith(release["release_event_id"], "-future") || continue
            release["quality_status"] = quality_status
        end
        @test build_structural_asof_receipt(future_nonapproved, origin) ==
            baseline

        latest_nonapproved = fixture_releases()
        for release in latest_nonapproved
            endswith(release["release_event_id"], "-new") || continue
            release["quality_status"] = quality_status
        end
        @test_throws StructuralAsOfError build_structural_asof_receipt(
            latest_nonapproved,
            origin,
        )
    end

    availability_before_release = deepcopy(base)
    availability_before_release[1]["availability_timestamp_utc"] =
        "2019-09-10T09:00:00Z"
    @test_throws StructuralAsOfError validate_release_set(
        availability_before_release,
    )

    missing_key = deepcopy(base)
    pop!(missing_key[1], "mapping_version")
    @test_throws StructuralAsOfError validate_release_set(missing_key)

    extra_key = deepcopy(base)
    extra_key[1]["other"] = "x"
    @test_throws StructuralAsOfError validate_release_set(extra_key)
end

@testset "self-hash and evidence-bound replay reject mutation" begin
    releases = fixture_releases()
    receipt = build_structural_asof_receipt(
        releases,
        "2020-06-30T12:00:00Z",
    )
    @test occursin(r"^[0-9a-f]{64}$", receipt["content_sha256"])

    changed = deepcopy(receipt)
    changed["components"][1]["mapping_version"] = "forged-map"
    @test_throws StructuralAsOfError validate_receipt(changed, releases)

    rehashed = deepcopy(changed)
    restamp!(rehashed)
    @test_throws StructuralAsOfError validate_receipt(rehashed, releases)

    elevated = deepcopy(receipt)
    elevated["origin_admissible"] = true
    restamp!(elevated)
    @test_throws StructuralAsOfError validate_receipt(elevated, releases)

    relabeled = deepcopy(receipt)
    relabeled["selection_track"] = "RETROSPECTIVE_HINDSIGHT_SELECTED"
    restamp!(relabeled)
    @test_throws StructuralAsOfError validate_receipt(relabeled, releases)

    evidence_changed = deepcopy(releases)
    target = only(
        filter(
            release -> release["release_event_id"] ==
                "io_or_supply_use-release-new",
            evidence_changed,
        ),
    )
    target["mapping_version"] = "io_or_supply_use-map-rewritten"
    @test_throws StructuralAsOfError validate_receipt(receipt, evidence_changed)
end

@testset "prohibited actions and static pure-data boundary" begin
    for action in Selector.PROHIBITED_ACTIONS
        @test_throws StructuralAsOfError refuse_prohibited_action(action)
    end
    @test_throws StructuralAsOfError refuse_prohibited_action(:unknown)

    source = read(
        joinpath(@__DIR__, "USStructuralAsOfSelector.jl"),
        String,
    )
    for forbidden in (
            "Downloads",
            "HTTP.",
            "Sockets",
            "run(`",
            "open(",
            "mktemp",
            "write(",
            "rm(",
        )
        @test !occursin(forbidden, source)
    end
    @test !occursin("USSourceReleaseRegistry.asof_releases", source)
    @test occursin("Registry.canonical_sha256", source)
end
