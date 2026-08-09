#!/usr/bin/env julia

using Test

include(joinpath(@__DIR__, "USSourceReleaseRegistry.jl"))
using .USSourceReleaseRegistry

const NULL_HASH = repeat("0", 64)

function release_event(;
        retrieval_event_id,
        release_event_id,
        source_id,
        source_family,
        dataset_id,
        series_id,
        release_timestamp_utc,
        availability_timestamp_utc = release_timestamp_utc,
        retrieved_at_utc,
        raw_sha256,
        source_release_id,
        reference_period_start,
        reference_period_end,
        realtime_start_utc = availability_timestamp_utc,
        realtime_end_utc = "9999-12-31T23:59:59Z",
        frequency,
        unit,
        seasonal_adjustment,
        annual_rate_flag,
        stock_flow_index_rate,
        price_basis,
        transformation_version,
        classification,
        classification_vintage,
        quality_status = "APPROVED",
        retrieval_locator = "fixture:$retrieval_event_id",
    )
    return Dict{String, Any}(
        "retrieval_event_id" => retrieval_event_id,
        "release_event_id" => release_event_id,
        "source_id" => source_id,
        "source_family" => source_family,
        "dataset_id" => dataset_id,
        "series_id" => series_id,
        "release_timestamp_utc" => release_timestamp_utc,
        "availability_timestamp_utc" => availability_timestamp_utc,
        "availability_basis" => "fixture_official_release_evidence",
        "availability_evidence_locator" =>
            "fixture:evidence/$source_release_id",
        "retrieved_at_utc" => retrieved_at_utc,
        "raw_sha256" => raw_sha256,
        "source_release_id" => source_release_id,
        "source_locator" => "fixture:source/$source_release_id",
        "retrieval_locator" => retrieval_locator,
        "reference_period_start" => reference_period_start,
        "reference_period_end" => reference_period_end,
        "realtime_start_utc" => realtime_start_utc,
        "realtime_end_utc" => realtime_end_utc,
        "frequency" => frequency,
        "unit" => unit,
        "seasonal_adjustment" => seasonal_adjustment,
        "annual_rate_flag" => annual_rate_flag,
        "stock_flow_index_rate" => stock_flow_index_rate,
        "price_basis" => price_basis,
        "transformation_version" => transformation_version,
        "classification" => classification,
        "classification_vintage" => classification_vintage,
        "quality_status" => quality_status,
    )
end

function fixture_inventory()
    gdp_advance = release_event(
        retrieval_event_id = "retrieval-gdp-advance-1",
        release_event_id = "release-gdp-advance",
        source_id = "bea",
        source_family = "nipa",
        dataset_id = "T10101",
        series_id = "real_gdp",
        release_timestamp_utc = "2020-04-29T12:30:00Z",
        retrieved_at_utc = "2020-04-29T13:00:00Z",
        raw_sha256 = repeat("a", 64),
        source_release_id = "bea-gdp-2020q1-advance",
        reference_period_start = "2020-01-01",
        reference_period_end = "2020-03-31",
        realtime_end_utc = "2020-06-25T12:30:00Z",
        frequency = "quarterly",
        unit = "millions_chained_2017_dollars_saar",
        seasonal_adjustment = "SA",
        annual_rate_flag = true,
        stock_flow_index_rate = "flow",
        price_basis = "real_chain_type",
        transformation_version = "bea-real-gdp.v1",
        classification = "nipa_line",
        classification_vintage = "T10101-2020",
    )
    source_rate = release_event(
        retrieval_event_id = "retrieval-effr-april-1",
        release_event_id = "release-effr-april",
        source_id = "frb",
        source_family = "policy_rates",
        dataset_id = "DFF",
        series_id = "effective_federal_funds_rate",
        release_timestamp_utc = "2020-05-01T12:00:00Z",
        retrieved_at_utc = "2020-05-01T12:05:00Z",
        raw_sha256 = repeat("b", 64),
        source_release_id = "frb-effr-2020-04",
        reference_period_start = "2020-01-01",
        reference_period_end = "2020-04-30",
        frequency = "daily",
        unit = "percent",
        seasonal_adjustment = "NSA",
        annual_rate_flag = false,
        stock_flow_index_rate = "rate",
        price_basis = "not_applicable",
        transformation_version = "frb-effr-quarterly-average.v1",
        classification = "aggregate",
        classification_vintage = "not_applicable",
    )
    structural = release_event(
        retrieval_event_id = "retrieval-io-2019-1",
        release_event_id = "release-io-2019",
        source_id = "bea",
        source_family = "input_output",
        dataset_id = "use_make",
        series_id = "annual_use_make",
        release_timestamp_utc = "2020-05-15T12:00:00Z",
        retrieved_at_utc = "2020-05-15T12:10:00Z",
        raw_sha256 = repeat("c", 64),
        source_release_id = "bea-io-2019-release",
        reference_period_start = "2019-01-01",
        reference_period_end = "2019-12-31",
        frequency = "annual",
        unit = "millions_current_dollars",
        seasonal_adjustment = "NSA",
        annual_rate_flag = false,
        stock_flow_index_rate = "flow",
        price_basis = "purchasers_prices",
        transformation_version = "bea-use-make.v1",
        classification = "bea_io",
        classification_vintage = "2017_naics",
    )
    gdp_refetch = deepcopy(gdp_advance)
    gdp_refetch["retrieval_event_id"] = "retrieval-gdp-advance-2"
    gdp_refetch["retrieved_at_utc"] = "2020-06-01T09:00:00Z"
    gdp_refetch["retrieval_locator"] =
        "fixture:mirror/retrieval-gdp-advance-2"
    gdp_third = release_event(
        retrieval_event_id = "retrieval-gdp-third-1",
        release_event_id = "release-gdp-third",
        source_id = "bea",
        source_family = "nipa",
        dataset_id = "T10101",
        series_id = "real_gdp",
        release_timestamp_utc = "2020-06-25T12:30:00Z",
        retrieved_at_utc = "2020-06-25T13:00:00Z",
        raw_sha256 = repeat("d", 64),
        source_release_id = "bea-gdp-2020q1-third",
        reference_period_start = "2020-01-01",
        reference_period_end = "2020-03-31",
        frequency = "quarterly",
        unit = "millions_chained_2017_dollars_saar",
        seasonal_adjustment = "SA",
        annual_rate_flag = true,
        stock_flow_index_rate = "flow",
        price_basis = "real_chain_type",
        transformation_version = "bea-real-gdp.v1",
        classification = "nipa_line",
        classification_vintage = "T10101-2020",
    )
    inventory = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-source-release-inventory.v1",
            "inventory_id" => "synthetic-release-inventory.v1",
            "status" => "COMPLETE",
            "evidence_verifier_status" =>
                "NOT_IMPLEMENTED_FAIL_CLOSED",
            "canonicalization" =>
                "utf8-length-prefixed-sorted-map-array-order.v1",
            "digest_algorithm" => "sha256",
            "content_sha256" => NULL_HASH,
        ),
        "release_events" => [
            gdp_advance,
            source_rate,
            structural,
            gdp_refetch,
            gdp_third,
        ],
        "admissible_origin_timestamps_utc" =>
            ["2020-05-15T13:00:00Z"],
        "audit_facts" => Any[],
    )
    return stamp_inventory_sha256!(inventory)
end

function requirement_block(;
        block_id,
        block_kind,
        source_id,
        source_family,
        dataset_id,
        series_id,
        frequency,
        unit,
        seasonal_adjustment,
        annual_rate_flag,
        stock_flow_index_rate,
        price_basis,
        transformation_version,
        classification,
        classification_vintage,
        required_reference_period_start,
        required_reference_period_end,
        allowed_quality_statuses = ["APPROVED"],
    )
    return Dict{String, Any}(
        "block_id" => block_id,
        "block_kind" => block_kind,
        "source_id" => source_id,
        "source_family" => source_family,
        "dataset_id" => dataset_id,
        "series_id" => series_id,
        "frequency" => frequency,
        "unit" => unit,
        "seasonal_adjustment" => seasonal_adjustment,
        "annual_rate_flag" => annual_rate_flag,
        "stock_flow_index_rate" => stock_flow_index_rate,
        "price_basis" => price_basis,
        "transformation_version" => transformation_version,
        "classification" => classification,
        "classification_vintage" => classification_vintage,
        "required_reference_period_start" =>
            required_reference_period_start,
        "required_reference_period_end" => required_reference_period_end,
        "allowed_quality_statuses" => allowed_quality_statuses,
    )
end

function fixture_requirements()
    source = requirement_block(
        block_id = "source_effr",
        block_kind = "source",
        source_id = "frb",
        source_family = "policy_rates",
        dataset_id = "DFF",
        series_id = "effective_federal_funds_rate",
        frequency = "daily",
        unit = "percent",
        seasonal_adjustment = "NSA",
        annual_rate_flag = false,
        stock_flow_index_rate = "rate",
        price_basis = "not_applicable",
        transformation_version = "frb-effr-quarterly-average.v1",
        classification = "aggregate",
        classification_vintage = "not_applicable",
        required_reference_period_start = "2020-01-01",
        required_reference_period_end = "2020-04-30",
    )
    structural = requirement_block(
        block_id = "structural_io",
        block_kind = "structural",
        source_id = "bea",
        source_family = "input_output",
        dataset_id = "use_make",
        series_id = "annual_use_make",
        frequency = "annual",
        unit = "millions_current_dollars",
        seasonal_adjustment = "NSA",
        annual_rate_flag = false,
        stock_flow_index_rate = "flow",
        price_basis = "purchasers_prices",
        transformation_version = "bea-use-make.v1",
        classification = "bea_io",
        classification_vintage = "2017_naics",
        required_reference_period_start = "2019-01-01",
        required_reference_period_end = "2019-12-31",
    )
    target = requirement_block(
        block_id = "target_real_gdp",
        block_kind = "target",
        source_id = "bea",
        source_family = "nipa",
        dataset_id = "T10101",
        series_id = "real_gdp",
        frequency = "quarterly",
        unit = "millions_chained_2017_dollars_saar",
        seasonal_adjustment = "SA",
        annual_rate_flag = true,
        stock_flow_index_rate = "flow",
        price_basis = "real_chain_type",
        transformation_version = "bea-real-gdp.v1",
        classification = "nipa_line",
        classification_vintage = "T10101-2020",
        required_reference_period_start = "2020-01-01",
        required_reference_period_end = "2020-03-31",
    )
    requirements = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-source-completeness-requirements.v1",
            "requirements_id" => "synthetic-origin-requirements.v1",
            "protocol_sha256" =>
                "88519e5b04936f528396cf5243ff270844d0d38651fd84fc3b1c76fef997b584",
            "approval_status" => "DRAFT_UNAPPROVED",
            "canonicalization" =>
                "utf8-length-prefixed-sorted-map-array-order.v1",
            "digest_algorithm" => "sha256",
            "content_sha256" => NULL_HASH,
        ),
        "blocks" => [source, structural, target],
    )
    return stamp_requirements_sha256!(requirements)
end

function restamp!(inventory)
    stamp_inventory_sha256!(inventory)
    return inventory
end

@testset "current inventory is explicit and empty" begin
    path = joinpath(@__DIR__, "current_inventory.toml")
    current = load_inventory(path)
    @test current["artifact"]["status"] == "INCOMPLETE"
    @test isempty(current["release_events"])
    @test isempty(current["admissible_origin_timestamps_utc"])
    @test length(current["audit_facts"]) == 3
    @test all(
        fact["distribution_status"] != "TRACKED_DISTRIBUTABLE" for
            fact in current["audit_facts"]
    )
    @test occursin(
        r"^[0-9a-f]{64}$",
        current["artifact"]["content_sha256"],
    )
end

@testset "inventory schema and canonical digest fail closed" begin
    inventory = fixture_inventory()
    @test validate_inventory(inventory) === inventory
    @test inventory_sha256(inventory) ==
        inventory["artifact"]["content_sha256"]

    reordered = Dict{String, Any}(
        key => deepcopy(inventory[key]) for
            key in reverse(collect(keys(inventory)))
    )
    @test inventory_sha256(reordered) == inventory_sha256(inventory)

    tampered = deepcopy(inventory)
    tampered["release_events"][1]["raw_sha256"] = repeat("f", 64)
    @test_throws SourceReleaseValidationError validate_inventory(tampered)

    missing_field = deepcopy(inventory)
    delete!(
        missing_field["release_events"][1],
        "availability_timestamp_utc",
    )
    restamp!(missing_field)
    @test_throws SourceReleaseValidationError validate_inventory(missing_field)

    unknown_field = deepcopy(inventory)
    unknown_field["release_events"][1]["inferred_release_hour"] = 8
    restamp!(unknown_field)
    @test_throws SourceReleaseValidationError validate_inventory(unknown_field)

    bad_hash = deepcopy(inventory)
    bad_hash["release_events"][1]["raw_sha256"] = "not-a-hash"
    restamp!(bad_hash)
    @test_throws SourceReleaseValidationError validate_inventory(bad_hash)

    self_verified = deepcopy(inventory)
    self_verified["artifact"]["evidence_verifier_status"] =
        "IMPLEMENTED_AND_VERIFIED"
    restamp!(self_verified)
    @test_throws SourceReleaseValidationError validate_inventory(self_verified)
end

@testset "all event times require exact evidenced UTC seconds" begin
    for (field, bad_value) in (
            ("release_timestamp_utc", "2020-04-29"),
            ("availability_timestamp_utc", "2020-04-29T12:30Z"),
            ("retrieved_at_utc", "2020-04-29T13:00:00.000Z"),
            ("realtime_start_utc", "2020-04-29T12:30:00"),
            ("realtime_end_utc", "not-known"),
        )
        inventory = fixture_inventory()
        inventory["release_events"][1][field] = bad_value
        restamp!(inventory)
        @test_throws SourceReleaseValidationError validate_inventory(
            inventory,
        )
    end

    before_release = fixture_inventory()
    before_release["release_events"][1]["availability_timestamp_utc"] =
        "2020-04-29T12:29:59Z"
    restamp!(before_release)
    @test_throws SourceReleaseValidationError validate_inventory(
        before_release,
    )

    before_available = fixture_inventory()
    before_available["release_events"][1]["retrieved_at_utc"] =
        "2020-04-29T12:29:59Z"
    restamp!(before_available)
    @test_throws SourceReleaseValidationError validate_inventory(
        before_available,
    )

    mismatched_realtime_start = fixture_inventory()
    for event in mismatched_realtime_start["release_events"]
        if event["release_event_id"] == "release-gdp-advance"
            event["realtime_start_utc"] = "2020-04-29T12:29:59Z"
        end
    end
    restamp!(mismatched_realtime_start)
    @test_throws SourceReleaseValidationError validate_inventory(
        mismatched_realtime_start,
    )
end

@testset "retrieval provenance allows refetches but rejects duplicates" begin
    inventory = fixture_inventory()
    advance_events = filter(
        event ->
        event["release_event_id"] == "release-gdp-advance",
        inventory["release_events"],
    )
    @test length(advance_events) == 2
    @test only(unique(event["raw_sha256"] for event in advance_events)) ==
        repeat("a", 64)

    new_refetch = deepcopy(first(advance_events))
    new_refetch["retrieval_event_id"] = "retrieval-gdp-advance-3"
    new_refetch["retrieved_at_utc"] = "2020-07-01T09:00:00Z"
    new_refetch["retrieval_locator"] =
        "fixture:mirror/retrieval-gdp-advance-3"
    old_hash = inventory_sha256(inventory)
    @test append_retrieval_event!(inventory, new_refetch) === inventory
    @test inventory_sha256(inventory) != old_hash
    @test validate_inventory(inventory) === inventory

    selected =
        asof_releases(inventory, "2020-05-15T13:00:00Z")
    gdp = only(
        release for release in selected if
            release["series_id"] == "real_gdp"
    )
    @test gdp["archive_retrieval_event_id"] ==
        "retrieval-gdp-advance-1"

    duplicate_id = fixture_inventory()
    pushed = deepcopy(duplicate_id["release_events"][end])
    pushed["retrieved_at_utc"] = "2020-07-01T09:00:00Z"
    pushed["retrieval_locator"] = "fixture:new-location"
    restamp!(duplicate_id)
    @test_throws SourceReleaseValidationError append_retrieval_event!(
        duplicate_id,
        pushed,
    )

    conflicting_refetch = fixture_inventory()
    conflict = deepcopy(conflicting_refetch["release_events"][1])
    conflict["retrieval_event_id"] = "retrieval-gdp-advance-conflict"
    conflict["retrieved_at_utc"] = "2020-07-01T09:00:00Z"
    conflict["retrieval_locator"] = "fixture:conflicting-content"
    conflict["raw_sha256"] = repeat("e", 64)
    @test_throws SourceReleaseValidationError append_retrieval_event!(
        conflicting_refetch,
        conflict,
    )

    duplicate_provenance = fixture_inventory()
    duplicate = deepcopy(duplicate_provenance["release_events"][1])
    duplicate["retrieval_event_id"] = "retrieval-gdp-advance-copy-id"
    insert!(duplicate_provenance["release_events"], 2, duplicate)
    restamp!(duplicate_provenance)
    @test_throws SourceReleaseValidationError validate_inventory(
        duplicate_provenance,
    )
end

@testset "ambiguous official events and append reordering are rejected" begin
    inventory = fixture_inventory()
    ambiguous = deepcopy(inventory["release_events"][1])
    ambiguous["retrieval_event_id"] = "retrieval-gdp-alternate"
    ambiguous["release_event_id"] = "release-gdp-alternate"
    ambiguous["source_release_id"] = "bea-gdp-2020q1-alternate"
    ambiguous["retrieved_at_utc"] = "2020-07-01T09:00:00Z"
    ambiguous["retrieval_locator"] = "fixture:alternate"
    push!(inventory["release_events"], ambiguous)
    restamp!(inventory)
    @test_throws SourceReleaseValidationError validate_inventory(inventory)

    out_of_order = fixture_inventory()
    reverse!(out_of_order["release_events"])
    restamp!(out_of_order)
    @test_throws SourceReleaseValidationError validate_inventory(
        out_of_order,
    )

end

@testset "exact as-of selection enforces intraday boundaries" begin
    inventory = fixture_inventory()
    @test isempty(
        asof_releases(inventory, "2020-04-29T12:29:59Z"),
    )
    at_release =
        asof_releases(inventory, "2020-04-29T12:30:00Z")
    @test only(at_release)["release_event_id"] ==
        "release-gdp-advance"

    before_revision =
        asof_releases(inventory, "2020-06-25T12:29:59Z")
    gdp_before = only(
        release for release in before_revision if
            release["series_id"] == "real_gdp"
    )
    @test gdp_before["release_event_id"] == "release-gdp-advance"

    at_revision =
        asof_releases(inventory, "2020-06-25T12:30:00Z")
    gdp_after = only(
        release for release in at_revision if
            release["series_id"] == "real_gdp"
    )
    @test gdp_after["release_event_id"] == "release-gdp-third"
    @test all(
        release["availability_timestamp_utc"] <=
            "2020-06-25T12:30:00Z" for release in at_revision
    )
    @test_throws SourceReleaseValidationError asof_releases(
        inventory,
        "2020-06-25",
    )
    @test_throws SourceReleaseValidationError asof_releases(
        inventory,
        "2020-06-25T12:30:00Z";
        allowed_quality_statuses = Set(["UNKNOWN"]),
    )
end

@testset "revisions append without future knowledge or past hash churn" begin
    inventory = fixture_inventory()
    revision = only(
        deepcopy(event) for event in inventory["release_events"] if
            event["release_event_id"] == "release-gdp-third"
    )
    inventory["release_events"] = filter(
        event -> event["release_event_id"] != "release-gdp-third",
        inventory["release_events"],
    )
    for event in inventory["release_events"]
        if event["release_event_id"] == "release-gdp-advance"
            event["realtime_end_utc"] = "9999-12-31T23:59:59Z"
        end
    end
    restamp!(inventory)
    requirements = fixture_requirements()
    past_origin = "2020-05-15T13:00:00Z"
    before_inventory_hash = inventory_sha256(inventory)
    before_evaluation =
        evaluate_completeness(inventory, requirements, past_origin)
    before_record =
        build_cannot_run_record(inventory, requirements, past_origin)

    @test append_retrieval_event!(inventory, revision) === inventory
    @test inventory_sha256(inventory) != before_inventory_hash
    after_revision =
        asof_releases(inventory, "2020-06-25T12:30:00Z")
    @test only(
        release for release in after_revision if
            release["series_id"] == "real_gdp"
    )["release_event_id"] == "release-gdp-third"
    @test evaluate_completeness(inventory, requirements, past_origin) ==
        before_evaluation
    @test build_cannot_run_record(inventory, requirements, past_origin) ==
        before_record

    refetch = deepcopy(revision)
    refetch["retrieval_event_id"] = "retrieval-gdp-third-2"
    refetch["retrieved_at_utc"] = "2020-07-01T09:00:00Z"
    refetch["retrieval_locator"] = "fixture:mirror/retrieval-gdp-third-2"
    before_refetch_hash = inventory_sha256(inventory)
    append_retrieval_event!(inventory, refetch)
    @test inventory_sha256(inventory) != before_refetch_hash
    @test evaluate_completeness(inventory, requirements, past_origin) ==
        before_evaluation
    @test build_cannot_run_record(inventory, requirements, past_origin) ==
        before_record
end

@testset "expired wider revisions cannot resurrect older coverage" begin
    inventory = fixture_inventory()
    inventory["release_events"] = filter(
        event -> event["release_event_id"] != "release-gdp-third",
        inventory["release_events"],
    )
    for event in inventory["release_events"]
        if event["release_event_id"] == "release-gdp-advance"
            event["realtime_end_utc"] = "9999-12-31T23:59:59Z"
        end
    end
    wider = deepcopy(inventory["release_events"][1])
    wider["retrieval_event_id"] = "retrieval-gdp-wider-revision"
    wider["release_event_id"] = "release-gdp-wider-revision"
    wider["source_release_id"] = "bea-gdp-wider-revision"
    wider["release_timestamp_utc"] = "2020-06-25T12:30:00Z"
    wider["availability_timestamp_utc"] = "2020-06-25T12:30:00Z"
    wider["retrieved_at_utc"] = "2020-06-25T13:00:00Z"
    wider["retrieval_locator"] = "fixture:gdp-wider-revision"
    wider["reference_period_start"] = "2019-10-01"
    wider["realtime_start_utc"] = "2020-06-25T12:30:00Z"
    wider["realtime_end_utc"] = "2020-07-01T00:00:00Z"
    wider["raw_sha256"] = repeat("e", 64)
    restamp!(inventory)
    append_retrieval_event!(inventory, wider)

    requirements = fixture_requirements()
    during = evaluate_completeness(
        inventory,
        requirements,
        "2020-06-26T12:00:00Z",
    )
    during_target = only(
        result for result in during["block_results"] if
            result["block_id"] == "target_real_gdp"
    )
    @test during_target["status"] == "AVAILABLE"
    @test during_target["selected_release_event_id"] ==
        "release-gdp-wider-revision"

    after = evaluate_completeness(
        inventory,
        requirements,
        "2020-07-02T12:00:00Z",
    )
    after_target = only(
        result for result in after["block_results"] if
            result["block_id"] == "target_real_gdp"
    )
    @test after_target["status"] == "MISSING"
    @test after_target["reason_code"] ==
        "LATEST_RELEASE_REALTIME_INTERVAL_EXPIRED"
    @test after_target["selected_release_event_id"] == "not_available"
    @test after_target["candidate_release_event_ids"] ==
        ["release-gdp-wider-revision"]
end

@testset "candidate completeness remains fail-closed" begin
    inventory = fixture_inventory()
    requirements = fixture_requirements()
    @test validate_requirements(requirements) === requirements
    @test requirements_sha256(requirements) ==
        requirements["artifact"]["content_sha256"]

    evaluation = evaluate_completeness(
        inventory,
        requirements,
        "2020-05-15T13:00:00Z",
    )
    @test evaluation["schema_version"] ==
        "beforeit-us-source-completeness-evaluation.v1"
    @test evaluation["status"] == "CANNOT_RUN"
    @test !evaluation["complete"]
    @test evaluation["candidate_complete"]
    @test evaluation["status_counts"]["AVAILABLE"] == 5
    @test evaluation["status_counts"]["MISSING"] == 2
    @test Set(
        result["block_id"] for result in evaluation["block_results"] if
            result["status"] != "AVAILABLE"
    ) == Set(
        [
            "registry_evidence_verifier",
            "registry_requirements_approved",
        ]
    )
    @test occursin(
        r"^[0-9a-f]{64}$",
        evaluation["origin_evidence_sha256"],
    )
    @test validate_cannot_run_record(
        build_cannot_run_record(
            inventory,
            requirements,
            "2020-05-15T13:00:00Z",
        ),
        inventory,
        requirements,
    ) isa AbstractDict

    unlisted = evaluate_completeness(
        inventory,
        requirements,
        "2020-05-16T13:00:00Z",
    )
    @test !unlisted["complete"]
    @test any(
        result ->
        result["block_id"] == "registry_origin_declared" &&
            result["status"] == "MISSING",
        unlisted["block_results"],
    )

    incomplete_inventory = deepcopy(inventory)
    incomplete_inventory["artifact"]["status"] = "INCOMPLETE"
    restamp!(incomplete_inventory)
    incomplete = evaluate_completeness(
        incomplete_inventory,
        requirements,
        "2020-05-15T13:00:00Z",
    )
    @test any(
        result ->
        result["block_id"] == "registry_inventory_complete" &&
            result["status"] == "MISSING",
        incomplete["block_results"],
    )

    missing_kind = fixture_requirements()
    pop!(missing_kind["blocks"])
    stamp_requirements_sha256!(missing_kind)
    @test_throws SourceReleaseValidationError validate_requirements(
        missing_kind,
    )

    duplicate_selector = fixture_requirements()
    duplicate = deepcopy(duplicate_selector["blocks"][1])
    duplicate["block_id"] = "source_effr_duplicate"
    insert!(duplicate_selector["blocks"], 2, duplicate)
    stamp_requirements_sha256!(duplicate_selector)
    @test_throws SourceReleaseValidationError validate_requirements(
        duplicate_selector,
    )

    rejected_allowed = fixture_requirements()
    rejected_allowed["blocks"][1]["allowed_quality_statuses"] =
        ["REJECTED"]
    stamp_requirements_sha256!(rejected_allowed)
    @test_throws SourceReleaseValidationError validate_requirements(
        rejected_allowed,
    )

    wrong_protocol = fixture_requirements()
    wrong_protocol["artifact"]["protocol_sha256"] = repeat("f", 64)
    stamp_requirements_sha256!(wrong_protocol)
    @test_throws SourceReleaseValidationError validate_requirements(
        wrong_protocol,
    )

    self_approved = fixture_requirements()
    self_approved["artifact"]["approval_status"] = "APPROVED"
    stamp_requirements_sha256!(self_approved)
    @test_throws SourceReleaseValidationError validate_requirements(
        self_approved,
    )
end

@testset "incomplete origins emit deterministic cannot-run records" begin
    inventory = fixture_inventory()
    inventory["release_events"] = filter(
        event -> event["series_id"] != "effective_federal_funds_rate",
        inventory["release_events"],
    )
    restamp!(inventory)
    requirements = fixture_requirements()
    origin = "2020-05-15T13:00:00Z"
    evaluation = evaluate_completeness(inventory, requirements, origin)
    @test !evaluation["complete"]
    @test evaluation["status"] == "CANNOT_RUN"
    @test !evaluation["candidate_complete"]
    @test evaluation["status_counts"]["MISSING"] == 3

    record = build_cannot_run_record(inventory, requirements, origin)
    @test validate_cannot_run_record(record) === record
    @test validate_cannot_run_record(record, inventory, requirements) ===
        record
    @test record["status"] == "CANNOT_RUN"
    @test record["unavailable_block_ids"] == [
        "registry_evidence_verifier",
        "registry_requirements_approved",
        "source_effr",
    ]
    @test record["reason_codes"] == [
        "EVIDENCE_ARTIFACT_VERIFIER_NOT_IMPLEMENTED",
        "NO_ELIGIBLE_RELEASE_COVERS_REQUIRED_REFERENCE_INTERVAL",
        "REQUIREMENTS_NOT_APPROVED",
    ]
    @test record ==
        build_cannot_run_record(inventory, requirements, origin)
    @test occursin(r"^[0-9a-f]{64}$", record["content_sha256"])

    tampered = deepcopy(record)
    tampered["unavailable_block_ids"] = ["target_real_gdp"]
    @test_throws SourceReleaseValidationError validate_cannot_run_record(
        tampered,
    )

    bad_id = deepcopy(record)
    bad_id["record_id"] = "cannot-run-0000000000000000"
    canonical = deepcopy(bad_id)
    delete!(canonical, "content_sha256")
    bad_id["content_sha256"] = canonical_sha256(canonical)
    @test_throws SourceReleaseValidationError validate_cannot_run_record(
        bad_id,
    )

    forged = deepcopy(record)
    forged["evaluation_sha256"] = repeat("f", 64)
    forged["record_id"] = "cannot-run-" * repeat("f", 16)
    canonical = deepcopy(forged)
    delete!(canonical, "content_sha256")
    forged["content_sha256"] = canonical_sha256(canonical)
    @test validate_cannot_run_record(forged) === forged
    @test_throws SourceReleaseValidationError validate_cannot_run_record(
        forged,
        inventory,
        requirements,
    )
end

@testset "quality and coverage ambiguity cannot silently pass" begin
    dubious = fixture_inventory()
    for event in dubious["release_events"]
        if event["release_event_id"] == "release-gdp-advance"
            event["quality_status"] = "DUBIOUS"
        end
    end
    restamp!(dubious)
    quality_evaluation = evaluate_completeness(
        dubious,
        fixture_requirements(),
        "2020-05-15T13:00:00Z",
    )
    target = only(
        result for result in quality_evaluation["block_results"] if
            result["block_id"] == "target_real_gdp"
    )
    @test target["status"] == "UNACCEPTABLE_QUALITY"
    quality_record = build_cannot_run_record(
        dubious,
        fixture_requirements(),
        "2020-05-15T13:00:00Z",
    )
    @test "LATEST_RELEASE_QUALITY_NOT_ALLOWED" in
        quality_record["reason_codes"]

    ambiguous = fixture_inventory()
    wider = deepcopy(ambiguous["release_events"][1])
    wider["retrieval_event_id"] = "retrieval-gdp-wider-coverage"
    wider["release_event_id"] = "release-gdp-wider-coverage"
    wider["source_release_id"] = "bea-gdp-wider-coverage"
    wider["reference_period_start"] = "2019-10-01"
    wider["retrieved_at_utc"] = "2020-07-01T09:00:00Z"
    wider["retrieval_locator"] = "fixture:wider-coverage"
    push!(ambiguous["release_events"], wider)
    restamp!(ambiguous)
    @test validate_inventory(ambiguous) === ambiguous
    ambiguous_evaluation = evaluate_completeness(
        ambiguous,
        fixture_requirements(),
        "2020-05-15T13:00:00Z",
    )
    ambiguous_target = only(
        result for result in ambiguous_evaluation["block_results"] if
            result["block_id"] == "target_real_gdp"
    )
    @test ambiguous_target["status"] == "AMBIGUOUS"
    @test length(ambiguous_target["candidate_release_event_ids"]) == 2
end

@testset "an empty audited inventory cannot produce a runnable origin" begin
    current = load_inventory(joinpath(@__DIR__, "current_inventory.toml"))
    requirements = fixture_requirements()
    origin = "2020-05-15T13:00:00Z"
    evaluation = evaluate_completeness(current, requirements, origin)
    @test evaluation["status"] == "CANNOT_RUN"
    @test !evaluation["candidate_complete"]
    @test evaluation["status_counts"]["MISSING"] == 7
    record = build_cannot_run_record(current, requirements, origin)
    @test validate_cannot_run_record(record) === record
    @test record["unavailable_block_ids"] ==
        [
        "registry_evidence_verifier",
        "registry_inventory_complete",
        "registry_origin_declared",
        "registry_requirements_approved",
        "source_effr",
        "structural_io",
        "target_real_gdp",
    ]
end
