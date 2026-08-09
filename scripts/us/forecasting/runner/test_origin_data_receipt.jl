#!/usr/bin/env julia

using Dates
using Test

include(joinpath(@__DIR__, "..", "benchmarks", "USForecastBenchmarks.jl"))
include(joinpath(@__DIR__, "USOriginDataReceipt.jl"))

using .USForecastBenchmarks
using .USOriginDataReceipt

const ORIGIN_MANIFEST_HASH = repeat("a", 64)
const PROTOCOL_HASH = repeat("b", 64)
const MODEL_REGISTRY_HASH = repeat("c", 64)
const TARGET_CONTRACT_HASH = repeat("d", 64)
const SOURCE_A_HASH = repeat("e", 64)
const SOURCE_Z_HASH = repeat("f", 64)
const ALTERNATE_HASH = repeat("1", 64)
const TARGET_PANEL_ID = "tier1.synthetic.v1"
const EXPECTED_SAMPLE_SHA256 =
    "fdedf8ec447a3312f853d2533eef0d6bd1e52d4c6814c9a3d390b8caaa9ec6e8"
const EXPECTED_RECEIPT_SHA256 =
    "4993f81d4f00b1c5388388921c0ce781bc211cc84f393399f9e5ef8af0bb4d90"

function sample_fixture(; with_exogenous = true)
    y_train = [
        0.0 -0.0
        1.25 10.5
        2.5 11.75
        3.75 12.0
    ]
    x_train = with_exogenous ? [
            0.0 -0.0
            0.5 1.0
            1.5 2.0
            2.5 3.0
        ] : nothing
    x_future = with_exogenous ? [
            3.5 4.0
            4.5 5.0
        ] : nothing
    return OriginData(
        origin_id = "origin.2026q1.synthetic",
        origin_key = "2026Q1",
        training_keys = ["2025Q2", "2025Q3", "2025Q4", "2026Q1"],
        forecast_keys = ["2026Q2", "2026Q3"],
        y_train = y_train,
        x_train = x_train,
        x_future = x_future,
        target_names = ["real_gdp", "pce_price_index"],
        predictor_names =
            with_exogenous ? ["fiscal_path", "trade_path"] : nothing,
    )
end

function integer_sample(key_type)
    return OriginData(
        origin_id = "origin.integer.synthetic",
        origin_key = key_type(4),
        training_keys = key_type[1, 2, 3, 4],
        forecast_keys = key_type[5, 6],
        y_train = reshape(collect(1.0:8.0), 4, 2),
        target_names = ["target_a", "target_b"],
    )
end

function date_sample()
    return OriginData(
        origin_id = "origin.date.synthetic",
        origin_key = Date(2026, 3, 31),
        training_keys = [
            Date(2025, 6, 30),
            Date(2025, 9, 30),
            Date(2025, 12, 31),
            Date(2026, 3, 31),
        ],
        forecast_keys = [Date(2026, 6, 30), Date(2026, 9, 30)],
        y_train = reshape(collect(1.0:8.0), 4, 2),
        target_names = ["target_a", "target_b"],
    )
end

function source_fixture()
    return [
        SourceArtifact(
            artifact_id = "z-state",
            sha256 = SOURCE_Z_HASH,
        ),
        SourceArtifact(
            artifact_id = "a-vintage-panel",
            sha256 = SOURCE_A_HASH,
        ),
    ]
end

function authentication_kwargs(; source_artifacts = source_fixture())
    return (;
        origin_manifest_sha256 = ORIGIN_MANIFEST_HASH,
        protocol_sha256 = PROTOCOL_HASH,
        model_registry_content_sha256 = MODEL_REGISTRY_HASH,
        target_contract_sha256 = TARGET_CONTRACT_HASH,
        target_panel_id = TARGET_PANEL_ID,
        source_artifacts,
    )
end

function snapshot_with(
        snapshot;
        origin_id = snapshot.origin_id,
        origin_key = snapshot.origin_key,
        training_keys = snapshot.training_keys,
        forecast_keys = snapshot.forecast_keys,
        y_train = snapshot.y_train,
        x_train = snapshot.x_train,
        x_future = snapshot.x_future,
        target_names = snapshot.target_names,
        predictor_names = snapshot.predictor_names,
    )
    key_type = typeof(origin_key)
    return OriginDataSnapshot{key_type}(
        origin_id,
        origin_key,
        training_keys,
        forecast_keys,
        y_train,
        x_train,
        x_future,
        target_names,
        predictor_names,
    )
end

function receipt_with(
        receipt;
        schema_version = receipt.schema_version,
        canonicalization = receipt.canonicalization,
        digest_algorithm = receipt.digest_algorithm,
        evidence_class = receipt.evidence_class,
        empirical_execution_authorized =
            receipt.empirical_execution_authorized,
        origin_manifest_sha256 = receipt.origin_manifest_sha256,
        protocol_sha256 = receipt.protocol_sha256,
        model_registry_content_sha256 =
            receipt.model_registry_content_sha256,
        target_contract_sha256 = receipt.target_contract_sha256,
        target_panel_id = receipt.target_panel_id,
        source_artifacts = receipt.source_artifacts,
        sample_sha256 = receipt.sample_sha256,
        receipt_sha256 = receipt.receipt_sha256,
    )
    return OriginDataReceipt(;
        schema_version,
        canonicalization,
        digest_algorithm,
        evidence_class,
        empirical_execution_authorized,
        origin_manifest_sha256,
        protocol_sha256,
        model_registry_content_sha256,
        target_contract_sha256,
        target_panel_id,
        source_artifacts,
        sample_sha256,
        receipt_sha256,
    )
end

function replace_envelope(
        envelope;
        sample = envelope.sample,
        receipt = envelope.receipt,
    )
    return AuthenticatedOriginData(sample, receipt)
end

function raw_sample(
        sample;
        origin_id = sample.origin_id,
        origin_key = sample.origin_key,
        training_keys = sample.training_keys,
        forecast_keys = sample.forecast_keys,
        y_train = sample.y_train,
        x_train = sample.x_train,
        x_future = sample.x_future,
        target_names = sample.target_names,
        predictor_names = sample.predictor_names,
    )
    return (;
        origin_id,
        origin_key,
        training_keys,
        forecast_keys,
        y_train,
        x_train,
        x_future,
        target_names,
        predictor_names,
    )
end

@testset "deterministic owned receipt and fixed execution scope" begin
    sample = sample_fixture()
    sources = source_fixture()
    envelope = authenticate_origin_data(
        sample;
        authentication_kwargs(; source_artifacts = sources)...,
    )
    validation = validate_origin_data_receipt(
        envelope;
        sample,
    )
    repeated = authenticate_origin_data(
        sample;
        authentication_kwargs(; source_artifacts = reverse(sources))...,
    )

    @test envelope.receipt.schema_version ==
        "beforeit-us-origin-data-receipt.v1"
    @test envelope.receipt.canonicalization ==
        "typed-length-prefixed-big-endian.v1"
    @test envelope.receipt.digest_algorithm == "sha256"
    @test envelope.receipt.evidence_class == "synthetic_fixture_only"
    @test !envelope.receipt.empirical_execution_authorized
    @test [
        source.artifact_id for source in envelope.receipt.source_artifacts
    ] == ["a-vintage-panel", "z-state"]
    @test validation.source_artifact_count == 2
    @test validation.key_type === String
    @test validation.sample_sha256 == envelope.receipt.sample_sha256
    @test validation.receipt_sha256 == envelope.receipt.receipt_sha256
    @test validation.sample_sha256 == EXPECTED_SAMPLE_SHA256
    @test validation.receipt_sha256 == EXPECTED_RECEIPT_SHA256
    @test origin_data_sha256(sample) == envelope.receipt.sample_sha256
    @test repeated.receipt.sample_sha256 ==
        envelope.receipt.sample_sha256
    @test repeated.receipt.receipt_sha256 ==
        envelope.receipt.receipt_sha256

    owned = authenticated_sample(envelope)
    @test owned.y_train == sample.y_train
    @test owned.x_train == sample.x_train
    @test owned.training_keys == sample.training_keys
    @test owned.y_train !== sample.y_train
    @test owned.x_train !== sample.x_train
    @test owned.training_keys !== sample.training_keys

    original_y = envelope.sample.y_train[1, 1]
    original_key = envelope.sample.training_keys[1]
    sample.y_train[1, 1] = 999.0
    sample.training_keys[1] = "1900Q1"
    empty!(sources)
    @test envelope.sample.y_train[1, 1] == original_y
    @test envelope.sample.training_keys[1] == original_key
    @test length(envelope.receipt.source_artifacts) == 2
    @test validate_origin_data_receipt(envelope).receipt_sha256 ==
        envelope.receipt.receipt_sha256
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        envelope;
        sample,
    )

    owned.y_train[1, 1] = -77.0
    @test envelope.sample.y_train[1, 1] == original_y
    @test validate_origin_data_receipt(envelope).sample_sha256 ==
        envelope.receipt.sample_sha256
end

@testset "typed keys and IEEE-754 signed-zero canonicalization" begin
    baseline = sample_fixture()
    baseline_envelope = authenticate_origin_data(
        baseline;
        authentication_kwargs()...,
    )
    negative_zero = sample_fixture()
    negative_zero.y_train[1, 1] = -0.0
    negative_zero_envelope = authenticate_origin_data(
        negative_zero;
        authentication_kwargs()...,
    )
    @test reinterpret(UInt64, baseline.y_train[1, 1]) ==
        0x0000000000000000
    @test reinterpret(UInt64, negative_zero.y_train[1, 1]) ==
        0x8000000000000000
    @test baseline_envelope.receipt.sample_sha256 !=
        negative_zero_envelope.receipt.sample_sha256
    @test baseline_envelope.receipt.receipt_sha256 !=
        negative_zero_envelope.receipt.receipt_sha256
    absent_exogenous = authenticate_origin_data(
        sample_fixture(with_exogenous = false);
        authentication_kwargs()...,
    )
    @test absent_exogenous.receipt.sample_sha256 !=
        baseline_envelope.receipt.sample_sha256

    int64_sample = integer_sample(Int64)
    int32_sample = integer_sample(Int32)
    int64_envelope = authenticate_origin_data(
        int64_sample;
        authentication_kwargs()...,
    )
    int32_envelope = authenticate_origin_data(
        int32_sample;
        authentication_kwargs()...,
    )
    @test int64_envelope.receipt.sample_sha256 !=
        int32_envelope.receipt.sample_sha256
    @test validate_origin_data_receipt(int64_envelope).key_type === Int64
    @test validate_origin_data_receipt(int32_envelope).key_type === Int32
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        int64_envelope;
        sample = int32_sample,
    )

    dates = date_sample()
    date_envelope = authenticate_origin_data(
        dates;
        authentication_kwargs()...,
    )
    @test validate_origin_data_receipt(date_envelope).key_type === Date
    @test origin_data_sha256(dates) == date_envelope.receipt.sample_sha256

    float_keys = raw_sample(
        integer_sample(Int64);
        origin_key = 4.0,
        training_keys = Float64[1, 2, 3, 4],
        forecast_keys = Float64[5, 6],
    )
    @test_throws OriginDataReceiptError authenticate_origin_data(
        float_keys;
        authentication_kwargs()...,
    )
    symbol_keys = raw_sample(
        sample_fixture(with_exogenous = false);
        origin_key = :d,
        training_keys = Symbol[:a, :b, :c, :d],
        forecast_keys = Symbol[:e, :f],
    )
    @test_throws OriginDataReceiptError authenticate_origin_data(
        symbol_keys;
        authentication_kwargs()...,
    )
end

@testset "every sample field is sealed and revalidated" begin
    envelope = authenticate_origin_data(
        sample_fixture();
        authentication_kwargs()...,
    )

    tampered = deepcopy(envelope)
    tampered.sample.y_train[1, 1] = -0.0
    @test_throws OriginDataReceiptError validate_origin_data_receipt(tampered)

    tampered = deepcopy(envelope)
    tampered.sample.y_train[2, 1] += 0.25
    @test_throws OriginDataReceiptError validate_origin_data_receipt(tampered)

    tampered = deepcopy(envelope)
    tampered.sample.x_train[1, 1] = -0.0
    @test_throws OriginDataReceiptError validate_origin_data_receipt(tampered)

    tampered = deepcopy(envelope)
    tampered.sample.x_future[2, 2] += 1.0
    @test_throws OriginDataReceiptError validate_origin_data_receipt(tampered)

    tampered = deepcopy(envelope)
    tampered.sample.training_keys[1] = "2025Q1"
    @test_throws OriginDataReceiptError validate_origin_data_receipt(tampered)

    tampered = deepcopy(envelope)
    tampered.sample.forecast_keys[2] = "2026Q4"
    @test_throws OriginDataReceiptError validate_origin_data_receipt(tampered)

    tampered = deepcopy(envelope)
    reverse!(tampered.sample.training_keys)
    @test_throws OriginDataReceiptError validate_origin_data_receipt(tampered)

    tampered = deepcopy(envelope)
    reverse!(tampered.sample.forecast_keys)
    @test_throws OriginDataReceiptError validate_origin_data_receipt(tampered)

    changed_origin = snapshot_with(
        envelope.sample;
        origin_id = "origin.changed.synthetic",
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; sample = changed_origin),
    )

    changed_origin_key = snapshot_with(
        envelope.sample;
        origin_key = "2026Q0",
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; sample = changed_origin_key),
    )

    no_exogenous = snapshot_with(
        envelope.sample;
        x_train = nothing,
        x_future = nothing,
        predictor_names = String[],
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; sample = no_exogenous),
    )

    changed_targets = deepcopy(envelope)
    changed_targets.sample.target_names[1] = "nominal_gdp"
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        changed_targets,
    )

    reordered_targets = deepcopy(envelope)
    reverse!(reordered_targets.sample.target_names)
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        reordered_targets,
    )

    reordered_predictors = deepcopy(envelope)
    reverse!(reordered_predictors.sample.predictor_names)
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        reordered_predictors,
    )
    changed_predictor = deepcopy(envelope)
    changed_predictor.sample.predictor_names[1] = "changed_path"
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        changed_predictor,
    )

    truncated_y = snapshot_with(
        envelope.sample;
        y_train = copy(envelope.sample.y_train[1:3, :]),
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; sample = truncated_y),
    )
    truncated_x = snapshot_with(
        envelope.sample;
        x_future = copy(envelope.sample.x_future[:, 1:1]),
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; sample = truncated_x),
    )

    nonfinite_y = sample_fixture()
    nonfinite_y.y_train[1, 1] = Inf
    @test_throws OriginDataReceiptError authenticate_origin_data(
        nonfinite_y;
        authentication_kwargs()...,
    )
    nonfinite_x = sample_fixture()
    nonfinite_x.x_future[1, 1] = NaN
    @test_throws OriginDataReceiptError authenticate_origin_data(
        nonfinite_x;
        authentication_kwargs()...,
    )

    one_sided_x = raw_sample(
        sample_fixture();
        x_future = nothing,
    )
    @test_throws OriginDataReceiptError authenticate_origin_data(
        one_sided_x;
        authentication_kwargs()...,
    )
end

@testset "provenance set, fixed authorization, and self-hash" begin
    sample = sample_fixture()
    envelope = authenticate_origin_data(
        sample;
        authentication_kwargs()...,
    )
    receipt = envelope.receipt

    @test_throws OriginDataReceiptError authenticate_origin_data(
        sample;
        authentication_kwargs(
            source_artifacts = SourceArtifact[],
        )...,
    )
    duplicates = [
        SourceArtifact(artifact_id = "duplicate", sha256 = SOURCE_A_HASH),
        SourceArtifact(artifact_id = "duplicate", sha256 = SOURCE_Z_HASH),
    ]
    @test_throws OriginDataReceiptError authenticate_origin_data(
        sample;
        authentication_kwargs(source_artifacts = duplicates)...,
    )
    @test_throws OriginDataReceiptError SourceArtifact(
        artifact_id = "bad artifact",
        sha256 = SOURCE_A_HASH,
    )
    @test_throws OriginDataReceiptError SourceArtifact(
        artifact_id = "bad-hash",
        sha256 = repeat("0", 64),
    )

    for bad_hash in (
            repeat("0", 64),
            uppercase(ORIGIN_MANIFEST_HASH),
            "not-a-hash",
        )
        bad_kwargs = merge(
            authentication_kwargs(),
            (; origin_manifest_sha256 = bad_hash),
        )
        @test_throws OriginDataReceiptError authenticate_origin_data(
            sample;
            bad_kwargs...,
        )
    end

    @test_throws OriginDataReceiptError receipt_with(
        receipt;
        empirical_execution_authorized = true,
    )
    @test_throws OriginDataReceiptError receipt_with(
        receipt;
        evidence_class = "vintage_clean_candidate",
    )
    @test_throws OriginDataReceiptError receipt_with(
        receipt;
        schema_version = "beforeit-us-origin-data-receipt.v2",
    )
    @test_throws OriginDataReceiptError receipt_with(
        receipt;
        canonicalization = "julia-serialization",
    )
    @test_throws OriginDataReceiptError receipt_with(
        receipt;
        digest_algorithm = "sha512",
    )
    @test_throws OriginDataReceiptError receipt_with(
        receipt;
        source_artifacts = reverse(receipt.source_artifacts),
    )
    invalid_panel_kwargs = merge(
        authentication_kwargs(),
        (; target_panel_id = "bad panel"),
    )
    @test_throws OriginDataReceiptError authenticate_origin_data(
        sample;
        invalid_panel_kwargs...,
    )

    altered_origin = receipt_with(
        receipt;
        origin_manifest_sha256 = ALTERNATE_HASH,
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; receipt = altered_origin),
    )
    altered_protocol = receipt_with(
        receipt;
        protocol_sha256 = ALTERNATE_HASH,
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; receipt = altered_protocol),
    )
    altered_registry = receipt_with(
        receipt;
        model_registry_content_sha256 = ALTERNATE_HASH,
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; receipt = altered_registry),
    )
    altered_target_contract = receipt_with(
        receipt;
        target_contract_sha256 = ALTERNATE_HASH,
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; receipt = altered_target_contract),
    )
    altered_panel = receipt_with(
        receipt;
        target_panel_id = "tier1.changed.v1",
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; receipt = altered_panel),
    )

    altered_sources = (
        SourceArtifact(
            artifact_id = "a-vintage-panel",
            sha256 = ALTERNATE_HASH,
        ),
        receipt.source_artifacts[2],
    )
    altered_source_receipt = receipt_with(
        receipt;
        source_artifacts = altered_sources,
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; receipt = altered_source_receipt),
    )
    altered_source_id_receipt = receipt_with(
        receipt;
        source_artifacts = (
            SourceArtifact(
                artifact_id = "b-vintage-panel",
                sha256 = SOURCE_A_HASH,
            ),
            receipt.source_artifacts[2],
        ),
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(
            envelope;
            receipt = altered_source_id_receipt,
        ),
    )

    altered_sample_hash = receipt_with(
        receipt;
        sample_sha256 = ALTERNATE_HASH,
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; receipt = altered_sample_hash),
    )
    altered_seal = receipt_with(
        receipt;
        receipt_sha256 = ALTERNATE_HASH,
    )
    @test_throws OriginDataReceiptError validate_origin_data_receipt(
        replace_envelope(envelope; receipt = altered_seal),
    )

    encoded_sample =
        USOriginDataReceipt.sample_bytes(envelope.sample)
    @test USOriginDataReceipt.receipt_preimage(
        receipt,
        encoded_sample,
    ) == USOriginDataReceipt.receipt_preimage(
        altered_seal,
        encoded_sample,
    )
    @test USOriginDataReceipt.receipt_preimage(
        receipt,
        encoded_sample,
    ) != USOriginDataReceipt.receipt_preimage(
        altered_sample_hash,
        encoded_sample,
    )
    @test !(
        :builder_approval in propertynames(receipt) ||
            :empirical_builder_approval in propertynames(receipt)
    )
end
