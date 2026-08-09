#!/usr/bin/env julia

using Test

include(joinpath(@__DIR__, "USTrustedOriginBuilder.jl"))

using .USTrustedOriginBuilder

const A_HASH = repeat("a", 64)
const B_HASH = repeat("b", 64)
const C_HASH = repeat("c", 64)
const D_HASH = repeat("d", 64)

function artifact_fixture()
    return [
        BuilderSourceArtifact("artifact.a", A_HASH),
        BuilderSourceArtifact("artifact.b", B_HASH),
        BuilderSourceArtifact("artifact.c", C_HASH),
    ]
end

function observation_fixture()
    return [
        SourceObservation("obs.01", "artifact.a", A_HASH, "series.gdp", "2025Q4", "vintage.2026q1", 1.0),
        SourceObservation("obs.02", "artifact.a", A_HASH, "series.pce", "2025Q4", "vintage.2026q1", 2.0),
        SourceObservation("obs.03", "artifact.b", B_HASH, "series.gdp", "2026Q1", "vintage.2026q1", 3.0),
        SourceObservation("obs.04", "artifact.b", B_HASH, "series.pce", "2026Q1", "vintage.2026q1", 4.0),
        SourceObservation("obs.05", "artifact.c", C_HASH, "series.fiscal", "2025Q4", "vintage.2026q1", 5.0),
        SourceObservation("obs.06", "artifact.c", C_HASH, "series.fiscal", "2026Q1", "vintage.2026q1", 6.0),
        SourceObservation("obs.07", "artifact.c", C_HASH, "series.fiscal", "2026Q2", "vintage.2026q1", 7.0),
    ]
end

function derivation_fixture(; omit_last = false)
    cells = [
        CellDerivation("y_train", "2025Q4", "real_gdp", 1.0, "transform.gdp", "v1", "identity", "v1", ["obs.01"], Float64[]),
        CellDerivation("y_train", "2025Q4", "pce_price_index", 2.0, "transform.pce", "v1", "identity", "v1", ["obs.02"], Float64[]),
        CellDerivation("y_train", "2026Q1", "real_gdp", 3.0, "transform.gdp", "v1", "identity", "v1", ["obs.03"], Float64[]),
        CellDerivation("y_train", "2026Q1", "pce_price_index", 4.0, "transform.pce", "v1", "identity", "v1", ["obs.04"], Float64[]),
        CellDerivation("x_train", "2025Q4", "fiscal_path", 5.0, "transform.fiscal", "v1", "identity", "v1", ["obs.05"], Float64[]),
        CellDerivation("x_train", "2026Q1", "fiscal_path", 6.0, "transform.fiscal", "v1", "identity", "v1", ["obs.06"], Float64[]),
        CellDerivation("x_future", "2026Q2", "fiscal_path", 7.0, "transform.fiscal", "v1", "identity", "v1", ["obs.07"], Float64[]),
    ]
    return omit_last ? cells[1:(end - 1)] : cells
end

function fixture(; source_artifacts = artifact_fixture(), source_observations = observation_fixture(), cell_derivations = derivation_fixture())
    return build_synthetic_origin_data(
        origin_id = "origin.2026q1.synthetic",
        origin_key = "2026Q1",
        training_keys = ["2025Q4", "2026Q1"],
        forecast_keys = ["2026Q2"],
        target_names = ["real_gdp", "pce_price_index"],
        predictor_names = ["fiscal_path"],
        source_artifacts = source_artifacts,
        source_observations = source_observations,
        cell_derivations = cell_derivations,
    )
end

function resealed_result(sample, receipt)
    key_type = typeof(sample.origin_key)
    sample_hash = USOriginDataReceipt.origin_data_sha256(sample)
    provisional = TransformationReceipt{key_type}(
        receipt.schema_version,
        receipt.canonicalization,
        receipt.digest_algorithm,
        receipt.evidence_class,
        receipt.empirical_execution_authorized,
        receipt.production_admission_authorized,
        receipt.source_artifacts,
        receipt.source_observations,
        receipt.cell_derivations,
        sample_hash,
        repeat("1", 64),
    )
    resealed = TransformationReceipt{key_type}(
        receipt.schema_version,
        receipt.canonicalization,
        receipt.digest_algorithm,
        receipt.evidence_class,
        receipt.empirical_execution_authorized,
        receipt.production_admission_authorized,
        receipt.source_artifacts,
        receipt.source_observations,
        receipt.cell_derivations,
        sample_hash,
        derivation_receipt_sha256(provisional),
    )
    return BuiltOriginData{key_type}(sample, resealed)
end

@testset "trusted synthetic origin builder" begin
    result = fixture()
    validated = validate_built_origin_data(result)
    @test validated.source_observation_count == 7
    @test validated.cell_derivation_count == 7
    @test result.receipt.evidence_class == "synthetic_fixture_only"
    @test !result.receipt.empirical_execution_authorized
    @test !result.receipt.production_admission_authorized
    @test result.sample.y_train == [1.0 2.0; 3.0 4.0]
    @test result.sample.x_train == reshape([5.0, 6.0], 2, 1)
    @test result.sample.x_future == reshape([7.0], 1, 1)
    @test derivation_receipt_sha256(result.receipt) == result.receipt.receipt_sha256
    @test fixture().receipt.receipt_sha256 == result.receipt.receipt_sha256
    @test_throws TrustedOriginBuilderError SourceObservation(
        "obs.bad", "artifact.a", A_HASH, "series.bad", "2026Q1", "vintage.2026q1", 1
    )
    @test_throws TrustedOriginBuilderError CellDerivation(
        "y_train", "2026Q1", "real_gdp", 1, "transform.bad", "v1", "identity", "v1", ["obs.01"], Float64[]
    )

    @test_throws TrustedOriginBuilderError fixture(cell_derivations = derivation_fixture(omit_last = true))
    @test_throws TrustedOriginBuilderError fixture(source_observations = observation_fixture()[1:(end - 1)])
    @test_throws TrustedOriginBuilderError fixture(
        source_artifacts = [
            BuilderSourceArtifact("artifact.a", A_HASH),
            BuilderSourceArtifact("artifact.alias", A_HASH),
        ]
    )
    @test_throws TrustedOriginBuilderError fixture(
        source_artifacts = [artifact_fixture()...; BuilderSourceArtifact("artifact.unused", D_HASH)]
    )
    reordered = derivation_fixture()
    reordered[1], reordered[2] = reordered[2], reordered[1]
    @test_throws TrustedOriginBuilderError fixture(cell_derivations = reordered)

    lookahead = observation_fixture()
    lookahead[end] = SourceObservation(
        "obs.07",
        "artifact.c",
        C_HASH,
        "series.fiscal",
        "2026Q3",
        "vintage.2026q1",
        7.0,
    )
    @test_throws TrustedOriginBuilderError fixture(source_observations = lookahead)

    bad_value = derivation_fixture()
    bad_value[1] = CellDerivation("y_train", "2025Q4", "real_gdp", 2.0, "transform.gdp", "v1", "identity", "v1", ["obs.01"], Float64[])
    @test_throws TrustedOriginBuilderError fixture(cell_derivations = bad_value)

    bad_operator = derivation_fixture()
    bad_operator[1] = CellDerivation("y_train", "2025Q4", "real_gdp", 1.0, "transform.gdp", "v1", "opaque", "v99", ["obs.01"], Float64[])
    @test_throws TrustedOriginBuilderError fixture(cell_derivations = bad_operator)

    weighted = derivation_fixture()
    weighted[1] = CellDerivation("y_train", "2025Q4", "real_gdp", 1.0, "transform.gdp", "v1", "weighted_sum", "v1", ["obs.01"], [1.0, 0.0])
    @test validate_built_origin_data(fixture(cell_derivations = weighted)).cell_derivation_count == 7

    result.sample.y_train[1, 1] = 99.0
    @test_throws TrustedOriginBuilderError validate_built_origin_data(result)

    receipt_mutation = fixture()
    receipt_mutation.receipt.cell_derivations[1].input_observation_ids[1] = "obs.02"
    @test_throws TrustedOriginBuilderError validate_built_origin_data(receipt_mutation)

    valid = fixture()
    invalid_origin_id_sample = USForecastBenchmarks.OriginData(
        origin_id = "origin with spaces",
        origin_key = valid.sample.origin_key,
        training_keys = valid.sample.training_keys,
        forecast_keys = valid.sample.forecast_keys,
        y_train = valid.sample.y_train,
        x_train = valid.sample.x_train,
        x_future = valid.sample.x_future,
        target_names = valid.sample.target_names,
        predictor_names = valid.sample.predictor_names,
    )
    @test_throws TrustedOriginBuilderError validate_built_origin_data(
        resealed_result(invalid_origin_id_sample, valid.receipt),
    )
end
