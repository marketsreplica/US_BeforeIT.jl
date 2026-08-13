#!/usr/bin/env julia

using Test
using TOML

include(joinpath(@__DIR__, "USTier1TargetCoverage.jl"))
using .USTier1TargetCoverage

include(joinpath(@__DIR__, "..", "contracts", "USForecastProtocol.jl"))

const TEST_HASH = repeat("a", 64)

function target_by_id(inventory, target_id)
    return only(
        target for target in inventory["targets"] if
            target["target_id"] == target_id
    )
end

function restamp!(inventory)
    stamp_content_sha256!(inventory)
    return inventory
end

function ready_fixture()
    inventory = deepcopy(load_inventory())
    for target in inventory["targets"]
        target["operator_status"] = "approved"
        target["installed_status"] = "exact"
        target["vintage_status"] = "historical_bitemporal"
        target["release_timestamp_status"] =
            "exact_historical_release_timestamps"
        target["historical_vintage_count"] = 40
        target["retrieval_vintages"] = String[]
        for layer in target["truth_layers"]
            layer["status"] = "available"
            layer["observation_count"] = 40
            layer["artifact_sha256"] = TEST_HASH
        end
    end
    inventory["contract"]["truth_matrix_count"] =
        length(EXPECTED_TARGET_IDS) * length(REQUIRED_TRUTH_LAYER_IDS)
    inventory["contract"]["approved_operator_bridge_count"] =
        length(EXPECTED_TARGET_IDS)
    return restamp!(inventory)
end

@testset "Parity with the frozen WS-0A target block" begin
    inventory = load_inventory()
    protocol =
        TOML.parsefile(normpath(joinpath(@__DIR__, "..", "protocol.toml")))
    @test USForecastProtocol.protocol_sha256(
        USForecastProtocol.validate_protocol(protocol),
    ) == inventory["contract"]["protocol_sha256"]
    protocol_targets =
        Dict(target["target_id"] => target for target in protocol["targets"])

    @test Set(keys(protocol_targets)) == Set(EXPECTED_TARGET_IDS)
    for target in inventory["targets"]
        protocol_target = protocol_targets[target["target_id"]]
        for field in (
                "target_version",
                "operator_version",
                "source_concept",
                "aggregation",
                "primary_transformation",
                "secondary_transformation",
                "output_unit",
                "truth_policy",
                "weight",
            )
            @test target[field] == protocol_target[field]
        end
        @test target["operator_status"] == protocol_target["bridge_status"]
    end
end

@testset "Tier-1 checked-in coverage audit" begin
    inventory = load_inventory()
    validation = validate_inventory(inventory)
    readiness = promotion_readiness(inventory)

    @test validation.inventory === inventory
    @test validation.target_count == 8
    @test Set(target["target_id"] for target in inventory["targets"]) ==
        Set(EXPECTED_TARGET_IDS)
    @test validation.weight_sum == 1.0
    @test validation.truth_matrix_count == 0
    @test validation.approved_operator_bridge_count == 0
    @test validation.sha256 ==
        "bdbbeb48a39c7fdd03972626cf7f1e421ba7c5dd254f5537a40dda0eb4ae1fcb"
    @test validation.sha256 == inventory_sha256(inventory)
    @test computed_content_sha256(inventory) == validation.sha256

    @test readiness.status == "NOT_READY"
    @test readiness.ready === false
    @test readiness.schema_ready === false
    @test readiness.evidence_verifier_status ==
        "NOT_IMPLEMENTED_FAIL_CLOSED"
    @test readiness.target_count == 8
    @test readiness.exact_target_count == 0
    @test readiness.approximate_target_count == 4
    @test readiness.absent_target_count == 4
    @test readiness.installed_or_approximate_target_count == 4
    @test readiness.historical_vintage_target_count == 0
    @test readiness.complete_truth_target_count == 0
    @test readiness.truth_matrix_count == 0
    @test readiness.approved_operator_bridge_count == 0
    @test readiness.weight_sum == 1.0
    @test length(readiness.blockers) == 33
    @test_throws TargetCoverageError require_promotion_ready(inventory)

    installed = Dict(
        target["target_id"] => target["installed_status"]
            for target in inventory["targets"]
    )
    @test installed["real_gdp"] == "approximate"
    @test installed["nominal_gdp"] == "approximate"
    @test installed["gdp_deflator"] == "approximate"
    @test installed["unemployment_rate"] == "approximate"
    @test installed["pce_price_index"] == "absent"
    @test installed["core_pce_price_index"] == "absent"
    @test installed["payroll_employment"] == "absent"
    @test installed["effective_federal_funds_rate"] == "absent"

    @test all(
        target["operator_status"] == "pending_validation"
            for target in inventory["targets"]
    )
    @test all(
        target["historical_vintage_count"] == 0
            for target in inventory["targets"]
    )
    @test all(
        layer["status"] == "missing"
            for target in inventory["targets"]
            for layer in target["truth_layers"]
    )

    machine_selectors = Dict(
        "real_gdp" => (
            "NIPA",
            "T10106",
            "1",
            "A191RX",
            "millions_chained_2017_dollars_saar",
            "seasonally_adjusted_at_annual_rates",
        ),
        "pce_price_index" => (
            "NIPA",
            "T20304",
            "1",
            "DPCERG",
            "index_2017_equals_100",
            "seasonally_adjusted",
        ),
        "core_pce_price_index" => (
            "NIPA",
            "T20304",
            "25",
            "DPCCRG",
            "index_2017_equals_100",
            "seasonally_adjusted",
        ),
        "gdp_deflator" => (
            "NIPA",
            "T10109",
            "1",
            "A191RD",
            "index_2017_equals_100",
            "seasonally_adjusted",
        ),
        "unemployment_rate" => (
            "BLS_CPS_PUBLIC_DATA_API",
            "LNS",
            "not_applicable",
            "LNS14000000",
            "percent_of_civilian_labor_force",
            "seasonally_adjusted",
        ),
        "payroll_employment" => (
            "BLS_CES_PUBLIC_DATA_API",
            "CES",
            "not_applicable",
            "CES0000000001",
            "thousands_of_payroll_jobs",
            "seasonally_adjusted",
        ),
        "effective_federal_funds_rate" => (
            "FRBNY_REFERENCE_RATES",
            "EFFR",
            "not_applicable",
            "EFFR",
            "percent_per_annum",
            "not_seasonally_adjusted",
        ),
        "nominal_gdp" => (
            "NIPA",
            "T10105",
            "1",
            "A191RC",
            "millions_current_dollars_saar",
            "seasonally_adjusted_at_annual_rates",
        ),
    )
    selector_fields = (
        "source_dataset_id",
        "source_table_id",
        "source_line_number",
        "source_series_code",
        "source_unit",
        "source_seasonal_adjustment",
    )
    for (target_id, expected) in machine_selectors
        target = target_by_id(inventory, target_id)
        for (field, value) in zip(selector_fields, expected)
            @test target[field] == value
        end
    end

    effr = target_by_id(inventory, "effective_federal_funds_rate")
    @test effr["provider"] == "Federal Reserve Bank of New York"
    @test effr["source_series"] == "EFFR"
    @test effr["frequency"] == "daily_business_day"
    @test effr["aggregation"] == "quarterly_average_daily"
    @test occursin("FEDFUNDS", only(effr["installed_evidence"]))

    reordered = Dict(reverse(collect(inventory)))
    reordered["artifact"] = Dict(reverse(collect(reordered["artifact"])))
    reordered["contract"] = Dict(reverse(collect(reordered["contract"])))
    @test computed_content_sha256(reordered) == validation.sha256
    @test validate_inventory(reordered).sha256 == validation.sha256
end

@testset "Schema-ready synthetic contract remains unverified" begin
    inventory = ready_fixture()
    validation = validate_inventory(inventory)
    readiness = promotion_readiness(inventory)

    @test validation.target_count == 8
    @test validation.truth_matrix_count == 24
    @test validation.approved_operator_bridge_count == 8
    @test validation.weight_sum == 1.0
    @test readiness.ready === false
    @test readiness.schema_ready === true
    @test readiness.status == "EVIDENCE_VERIFICATION_REQUIRED"
    @test readiness.evidence_verifier_status ==
        "NOT_IMPLEMENTED_FAIL_CLOSED"
    @test readiness.exact_target_count == 8
    @test readiness.approximate_target_count == 0
    @test readiness.absent_target_count == 0
    @test readiness.installed_or_approximate_target_count == 8
    @test readiness.historical_vintage_target_count == 8
    @test readiness.complete_truth_target_count == 8
    @test readiness.truth_matrix_count == 24
    @test readiness.approved_operator_bridge_count == 8
    @test readiness.blockers == [
        "resolved truth/operator artifact verification is not implemented",
    ]
    @test_throws TargetCoverageError require_promotion_ready(inventory)

    undersized = deepcopy(inventory)
    target_by_id(undersized, "real_gdp")["truth_layers"][1][
        "observation_count",
    ] = 39
    restamp!(undersized)
    undersized_readiness = promotion_readiness(undersized)
    @test !undersized_readiness.ready
    @test undersized_readiness.complete_truth_target_count == 7
    @test any(
        blocker -> occursin(
            "real_gdp truth incomplete: first_release (39/40)",
            blocker,
        ),
        undersized_readiness.blockers,
    )

    undersized_history = deepcopy(inventory)
    target_by_id(
        undersized_history,
        "real_gdp",
    )["historical_vintage_count"] = 39
    restamp!(undersized_history)
    undersized_history_readiness =
        promotion_readiness(undersized_history)
    @test !undersized_history_readiness.schema_ready
    @test undersized_history_readiness.historical_vintage_target_count == 7
    @test any(
        blocker -> occursin(
            "real_gdp historical vintage count is 39/40",
            blocker,
        ),
        undersized_history_readiness.blockers,
    )

    changed = deepcopy(inventory)
    target_by_id(changed, "real_gdp")["historical_vintage_count"] = 13
    restamp!(changed)
    @test inventory_sha256(changed) != inventory_sha256(inventory)
end

@testset "Exact target and weight failures" begin
    base = load_inventory()

    missing_target = deepcopy(base)
    pop!(missing_target["targets"])
    restamp!(missing_target)
    @test_throws TargetCoverageError validate_inventory(missing_target)

    duplicate_target = deepcopy(base)
    push!(
        duplicate_target["targets"],
        deepcopy(target_by_id(duplicate_target, "real_gdp")),
    )
    restamp!(duplicate_target)
    @test_throws TargetCoverageError validate_inventory(duplicate_target)

    renamed_target = deepcopy(base)
    target_by_id(renamed_target, "real_gdp")["target_id"] = "real_output"
    restamp!(renamed_target)
    @test_throws TargetCoverageError validate_inventory(renamed_target)

    wrong_source_concept = deepcopy(base)
    target_by_id(wrong_source_concept, "real_gdp")["source_concept"] =
        "generic_output"
    restamp!(wrong_source_concept)
    @test_throws TargetCoverageError validate_inventory(wrong_source_concept)

    wrong_series = deepcopy(base)
    target_by_id(wrong_series, "payroll_employment")["source_series"] =
        "LNS12000000"
    restamp!(wrong_series)
    @test_throws TargetCoverageError validate_inventory(wrong_series)

    wrong_machine_series = deepcopy(base)
    target_by_id(
        wrong_machine_series,
        "payroll_employment",
    )["source_series_code"] = "LNS12000000"
    restamp!(wrong_machine_series)
    @test_throws TargetCoverageError validate_inventory(wrong_machine_series)

    non_unit_weight = deepcopy(base)
    target_by_id(non_unit_weight, "nominal_gdp")["weight"] = 0.25
    restamp!(non_unit_weight)
    @test_throws TargetCoverageError validate_inventory(non_unit_weight)

    integer_weight = deepcopy(base)
    target_by_id(integer_weight, "nominal_gdp")["weight"] = 0
    restamp!(integer_weight)
    @test_throws TargetCoverageError validate_inventory(integer_weight)

    wrong_required_sum = deepcopy(base)
    wrong_required_sum["contract"]["required_weight_sum"] = 0.999
    restamp!(wrong_required_sum)
    @test_throws TargetCoverageError validate_inventory(wrong_required_sum)
end

@testset "Daily EFFR cannot be monthly FEDFUNDS" begin
    base = load_inventory()

    monthly_fedfunds = deepcopy(base)
    effr = target_by_id(monthly_fedfunds, "effective_federal_funds_rate")
    effr["provider"] = "Federal Reserve Bank of St. Louis"
    effr["source_table"] = "FRED"
    effr["source_series"] = "FEDFUNDS"
    effr["frequency"] = "monthly"
    restamp!(monthly_fedfunds)
    @test_throws TargetCoverageError validate_inventory(monthly_fedfunds)

    monthly_frequency = deepcopy(base)
    target_by_id(
        monthly_frequency,
        "effective_federal_funds_rate",
    )["frequency"] = "monthly"
    restamp!(monthly_frequency)
    @test_throws TargetCoverageError validate_inventory(monthly_frequency)

    wrong_aggregation = deepcopy(base)
    target_by_id(
        wrong_aggregation,
        "effective_federal_funds_rate",
    )["aggregation"] = "quarterly_average_monthly"
    restamp!(wrong_aggregation)
    @test_throws TargetCoverageError validate_inventory(wrong_aggregation)
end

@testset "Vintage labels fail closed" begin
    base = load_inventory()

    relabeled_retrieval = deepcopy(base)
    real_gdp = target_by_id(relabeled_retrieval, "real_gdp")
    real_gdp["vintage_status"] = "historical_bitemporal"
    restamp!(relabeled_retrieval)
    @test_throws TargetCoverageError validate_inventory(relabeled_retrieval)

    fake_historical_count = deepcopy(base)
    real_gdp = target_by_id(fake_historical_count, "real_gdp")
    real_gdp["installed_status"] = "exact"
    real_gdp["vintage_status"] = "historical_bitemporal"
    real_gdp["release_timestamp_status"] =
        "exact_historical_release_timestamps"
    real_gdp["historical_vintage_count"] = 0
    restamp!(fake_historical_count)
    @test_throws TargetCoverageError validate_inventory(fake_historical_count)

    historical_using_retrieval_dates = deepcopy(base)
    real_gdp = target_by_id(historical_using_retrieval_dates, "real_gdp")
    real_gdp["installed_status"] = "exact"
    real_gdp["vintage_status"] = "historical_bitemporal"
    real_gdp["release_timestamp_status"] =
        "exact_historical_release_timestamps"
    real_gdp["historical_vintage_count"] = 2
    restamp!(historical_using_retrieval_dates)
    @test_throws TargetCoverageError validate_inventory(
        historical_using_retrieval_dates,
    )

    current_with_release_timestamp = deepcopy(base)
    real_gdp = target_by_id(current_with_release_timestamp, "real_gdp")
    real_gdp["release_timestamp_status"] =
        "exact_historical_release_timestamps"
    restamp!(current_with_release_timestamp)
    @test_throws TargetCoverageError validate_inventory(
        current_with_release_timestamp,
    )

    current_with_historical_count = deepcopy(base)
    target_by_id(
        current_with_historical_count,
        "real_gdp",
    )["historical_vintage_count"] = 2
    restamp!(current_with_historical_count)
    @test_throws TargetCoverageError validate_inventory(
        current_with_historical_count,
    )

    current_without_retrieval = deepcopy(base)
    target_by_id(current_without_retrieval, "real_gdp")["retrieval_vintages"] =
        String[]
    restamp!(current_without_retrieval)
    @test_throws TargetCoverageError validate_inventory(
        current_without_retrieval,
    )

    absent_with_retrieval = deepcopy(base)
    target_by_id(absent_with_retrieval, "pce_price_index")[
        "retrieval_vintages",
    ] = ["2026-08-04"]
    restamp!(absent_with_retrieval)
    @test_throws TargetCoverageError validate_inventory(absent_with_retrieval)

    malformed_date = deepcopy(base)
    target_by_id(malformed_date, "real_gdp")["retrieval_vintages"] =
        ["2026Q3"]
    restamp!(malformed_date)
    @test_throws TargetCoverageError validate_inventory(malformed_date)

    invalid_calendar_date = deepcopy(base)
    target_by_id(
        invalid_calendar_date,
        "real_gdp",
    )["retrieval_vintages"] = ["2026-02-31"]
    restamp!(invalid_calendar_date)
    @test_throws TargetCoverageError validate_inventory(invalid_calendar_date)

    unsorted_retrieval = deepcopy(base)
    target_by_id(
        unsorted_retrieval,
        "real_gdp",
    )["retrieval_vintages"] = ["2026-08-04", "2026-08-02"]
    restamp!(unsorted_retrieval)
    @test_throws TargetCoverageError validate_inventory(unsorted_retrieval)

    duplicate_retrieval = deepcopy(base)
    target_by_id(duplicate_retrieval, "real_gdp")["retrieval_vintages"] =
        ["2026-08-04", "2026-08-04"]
    restamp!(duplicate_retrieval)
    @test_throws TargetCoverageError validate_inventory(duplicate_retrieval)
end

@testset "Truth layers fail closed" begin
    base = load_inventory()

    missing_layer = deepcopy(base)
    pop!(target_by_id(missing_layer, "real_gdp")["truth_layers"])
    restamp!(missing_layer)
    @test_throws TargetCoverageError validate_inventory(missing_layer)

    duplicate_layer = deepcopy(base)
    truth_layers =
        target_by_id(duplicate_layer, "real_gdp")["truth_layers"]
    push!(truth_layers, deepcopy(first(truth_layers)))
    restamp!(duplicate_layer)
    @test_throws TargetCoverageError validate_inventory(duplicate_layer)

    wrong_requirement = deepcopy(base)
    target_by_id(wrong_requirement, "real_gdp")["truth_layers"][2][
        "requirement",
    ] = "latest_available"
    restamp!(wrong_requirement)
    @test_throws TargetCoverageError validate_inventory(wrong_requirement)

    optional_truth = deepcopy(base)
    target_by_id(optional_truth, "real_gdp")["truth_layers"][1]["required"] =
        false
    restamp!(optional_truth)
    @test_throws TargetCoverageError validate_inventory(optional_truth)

    empty_available = deepcopy(base)
    first_truth =
        target_by_id(empty_available, "real_gdp")["truth_layers"][1]
    first_truth["status"] = "available"
    restamp!(empty_available)
    @test_throws TargetCoverageError validate_inventory(empty_available)

    missing_with_observations = deepcopy(base)
    target_by_id(
        missing_with_observations,
        "real_gdp",
    )["truth_layers"][1]["observation_count"] = 1
    restamp!(missing_with_observations)
    @test_throws TargetCoverageError validate_inventory(
        missing_with_observations,
    )

    missing_with_hash = deepcopy(base)
    target_by_id(
        missing_with_hash,
        "real_gdp",
    )["truth_layers"][1]["artifact_sha256"] = TEST_HASH
    restamp!(missing_with_hash)
    @test_throws TargetCoverageError validate_inventory(missing_with_hash)

    inconsistent_matrix_count = deepcopy(base)
    inconsistent_matrix_count["contract"]["truth_matrix_count"] = 1
    restamp!(inconsistent_matrix_count)
    @test_throws TargetCoverageError validate_inventory(
        inconsistent_matrix_count,
    )

    incomplete_truth = ready_fixture()
    layer = target_by_id(incomplete_truth, "real_gdp")["truth_layers"][1]
    layer["status"] = "missing"
    layer["observation_count"] = 0
    layer["artifact_sha256"] = "unavailable"
    incomplete_truth["contract"]["truth_matrix_count"] = 23
    restamp!(incomplete_truth)
    readiness = promotion_readiness(incomplete_truth)
    @test readiness.ready === false
    @test readiness.complete_truth_target_count == 7
    @test any(
        blocker -> occursin(
            "real_gdp truth incomplete: first_release (missing)",
            blocker,
        ),
        readiness.blockers,
    )
end

@testset "Schema, count, hash, and parser failures" begin
    base = load_inventory()

    unknown_root = deepcopy(base)
    unknown_root["notes"] = "not in schema"
    restamp!(unknown_root)
    @test_throws TargetCoverageError validate_inventory(unknown_root)

    unknown_contract = deepcopy(base)
    unknown_contract["contract"]["override"] = true
    restamp!(unknown_contract)
    @test_throws TargetCoverageError validate_inventory(unknown_contract)

    unknown_target = deepcopy(base)
    target_by_id(unknown_target, "real_gdp")["proxy_allowed"] = true
    restamp!(unknown_target)
    @test_throws TargetCoverageError validate_inventory(unknown_target)

    unknown_truth = deepcopy(base)
    target_by_id(unknown_truth, "real_gdp")["truth_layers"][1]["cutoff"] =
        "latest"
    restamp!(unknown_truth)
    @test_throws TargetCoverageError validate_inventory(unknown_truth)

    wrong_bridge_count = deepcopy(base)
    wrong_bridge_count["contract"]["approved_operator_bridge_count"] = 1
    restamp!(wrong_bridge_count)
    @test_throws TargetCoverageError validate_inventory(wrong_bridge_count)

    placeholder_route = deepcopy(base)
    target_by_id(placeholder_route, "real_gdp")["acquisition_route"] = "TBD"
    restamp!(placeholder_route)
    @test_throws TargetCoverageError validate_inventory(placeholder_route)

    tampered = deepcopy(base)
    target_by_id(tampered, "real_gdp")["installed_evidence"][1] *= " changed"
    @test_throws TargetCoverageError validate_inventory(tampered)

    bad_hash = deepcopy(base)
    bad_hash["artifact"]["content_sha256"] = repeat("z", 64)
    @test_throws TargetCoverageError validate_inventory(bad_hash)

    integer_required_sum = deepcopy(base)
    integer_required_sum["contract"]["required_weight_sum"] = 1
    restamp!(integer_required_sum)
    @test_throws TargetCoverageError validate_inventory(integer_required_sum)

    invalid_audit_date = deepcopy(base)
    invalid_audit_date["contract"]["audit_as_of_date"] = "2026-02-31"
    restamp!(invalid_audit_date)
    @test_throws TargetCoverageError validate_inventory(invalid_audit_date)

    self_verified = deepcopy(base)
    self_verified["contract"]["evidence_verifier_status"] =
        "IMPLEMENTED_AND_VERIFIED"
    restamp!(self_verified)
    @test_throws TargetCoverageError validate_inventory(self_verified)

    mktempdir() do directory
        invalid_path = joinpath(directory, "invalid.toml")
        write(invalid_path, "[broken\n")
        @test_throws TargetCoverageError load_inventory(invalid_path)
    end
    @test_throws TargetCoverageError load_inventory(
        joinpath(@__DIR__, "missing-inventory.toml"),
    )
end
