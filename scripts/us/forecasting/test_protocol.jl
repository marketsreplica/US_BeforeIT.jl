#!/usr/bin/env julia

using Test

include(joinpath(@__DIR__, "contracts", "USForecastProtocol.jl"))
using .USForecastProtocol

function reversed_dict(table)
    return Dict(reverse(collect(pairs(table))))
end

@testset "WS-0A valid protocol contract" begin
    protocol = load_protocol()
    @test validate_protocol(protocol) === protocol
    @test protocol["status"] == "draft"
    @test protocol["approval_status"] == "pending_validation"
    @test protocol["governance"]["frozen"] === false
    @test protocol["products"]["quarterly_unconditional"]["horizons"] ==
        [1, 2, 4, 8, 12]
    @test protocol["products"]["ragged_edge_nowcast"]["horizons"] == [0, 1]
    @test protocol["products"]["cross_product_pooling"] === false
    @test protocol["benchmarks"]["cross_track_pooling"] === false
    @test Set(keys(protocol["truth"])) >=
        Set(["first_release", "near_mature", "mature"])
    @test protocol["origin_requirements"][
        "retrospective_vintage_clean_minimum",
    ] == 40
    @test protocol["origin_requirements"]["prospective_shadow_minimum"] == 8

    artifact = protocol_artifact()
    @test artifact.protocol == protocol
    @test artifact.canonical == canonicalize_protocol(protocol)
    @test artifact.sha256 == protocol_sha256(protocol)
    @test occursin(r"^[0-9a-f]{64}$", artifact.sha256)

    reordered = reversed_dict(deepcopy(protocol))
    reordered["issue_rules"] = reversed_dict(reordered["issue_rules"])
    reordered["scores"] = reversed_dict(reordered["scores"])
    @test canonicalize_protocol(reordered) ==
        canonicalize_protocol(protocol)
    @test protocol_sha256(reordered) == artifact.sha256

    new_experiment = deepcopy(protocol)
    new_experiment["experiment_version"] =
        "beforeit-us-retrospective.v2-draft"
    @test validate_protocol(new_experiment) === new_experiment
    @test protocol_sha256(new_experiment) != artifact.sha256
end

@testset "WS-0A validator fails closed" begin
    base = load_protocol()

    unknown = deepcopy(base)
    unknown["unreviewed_option"] = true
    @test_throws ProtocolValidationError validate_protocol(unknown)

    missing = deepcopy(base)
    delete!(missing, "truth")
    @test_throws ProtocolValidationError validate_protocol(missing)

    approved_without_signoff = deepcopy(base)
    approved_without_signoff["status"] = "frozen"
    @test_throws ProtocolValidationError validate_protocol(
        approved_without_signoff,
    )

    local_timezone = deepcopy(base)
    local_timezone["issue_rules"]["timestamp"]["local_timezone"] = "UTC"
    @test_throws ProtocolValidationError validate_protocol(local_timezone)

    missing_intraday = deepcopy(base)
    missing_intraday["issue_rules"]["missing_intraday_release_timestamp"] =
        "assume_midnight"
    @test_throws ProtocolValidationError validate_protocol(missing_intraday)

    wrong_horizons = deepcopy(base)
    wrong_horizons["products"]["quarterly_unconditional"]["horizons"] =
        [1, 2, 4, 8]
    @test_throws ProtocolValidationError validate_protocol(wrong_horizons)

    pooled_products = deepcopy(base)
    pooled_products["products"]["cross_product_pooling"] = true
    @test_throws ProtocolValidationError validate_protocol(pooled_products)

    duplicated_pool = deepcopy(base)
    duplicated_pool["products"]["ragged_edge_nowcast"]["ranking_pool"] =
        duplicated_pool["products"]["quarterly_unconditional"]["ranking_pool"]
    @test_throws ProtocolValidationError validate_protocol(duplicated_pool)

    missing_operator_version = deepcopy(base)
    delete!(missing_operator_version["targets"][1], "operator_version")
    @test_throws ProtocolValidationError validate_protocol(
        missing_operator_version,
    )

    bad_target_weight = deepcopy(base)
    bad_target_weight["targets"][1]["weight"] = 0.25
    @test_throws ProtocolValidationError validate_protocol(bad_target_weight)

    rewritten_truth = deepcopy(base)
    rewritten_truth["truth"]["mature"]["fixed_lag_months"] = 36
    @test_throws ProtocolValidationError validate_protocol(rewritten_truth)

    pooled_benchmarks = deepcopy(base)
    pooled_benchmarks["benchmarks"]["cross_track_pooling"] = true
    @test_throws ProtocolValidationError validate_protocol(pooled_benchmarks)

    missing_density_score = deepcopy(base)
    missing_density_score["scores"]["density"]["primary"] = ["crps"]
    @test_throws ProtocolValidationError validate_protocol(
        missing_density_score,
    )

    insufficient_origins = deepcopy(base)
    insufficient_origins["origin_requirements"][
        "retrospective_vintage_clean_minimum",
    ] = 39
    @test_throws ProtocolValidationError validate_protocol(insufficient_origins)

    permissive_promotion = deepcopy(base)
    permissive_promotion["promotion"]["all_gates_required"] = false
    @test_throws ProtocolValidationError validate_protocol(permissive_promotion)

    wrong_numeric_type = deepcopy(base)
    wrong_numeric_type["promotion"]["evidence_volume"][
        "retrospective_vintage_clean_minimum",
    ] = true
    @test_throws ProtocolValidationError validate_protocol(wrong_numeric_type)

    invalid_float = deepcopy(base)
    invalid_float["promotion"]["confidence_level"] = NaN
    @test_throws ProtocolValidationError validate_protocol(invalid_float)
    @test_throws ProtocolValidationError canonicalize_protocol(invalid_float)
    @test_throws ProtocolValidationError protocol_sha256(invalid_float)
end

@testset "WS-0A parser fails closed" begin
    mktempdir() do directory
        invalid_path = joinpath(directory, "invalid.toml")
        write(invalid_path, "[broken\n")
        @test_throws ProtocolValidationError load_protocol(invalid_path)
    end
    @test_throws ProtocolValidationError load_protocol(
        joinpath(@__DIR__, "missing-protocol.toml"),
    )
end
