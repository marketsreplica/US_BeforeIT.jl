#!/usr/bin/env julia

using Dates
using Random
using Test
using TOML

include(joinpath(@__DIR__, "USForecastRegistry.jl"))
using .USForecastRegistry

const EXPERIMENT_ID = "us-quarterly-pilot.v1"
const PROTOCOL_HASH = repeat("a", 64)
const ENVIRONMENT_HASH = repeat("b", 64)
const ORIGIN_HASH = repeat("c", 64)
const ORIGIN_DATA_SAMPLE_HASH = repeat("4", 64)
const ORIGIN_DATA_RECEIPT_HASH = repeat("5", 64)
const MODEL_MANIFEST_HASH = repeat("d", 64)
const MODEL_CARD_HASH = repeat("e", 64)
const DISTRIBUTION_HASH = repeat("f", 64)
const SEED_KEY_HASH = repeat("1", 64)
const SOURCE_HASH = repeat("2", 64)
const RETROSPECTIVE_EXPERIMENT_ID = "us-quarterly-replay.v1"
const QUARANTINE_NONCE = repeat("3", 64)

function forecast_payload(;
        forecast_id = "forecast.ar1.gdp.h1",
        model_id = "ar.fixed-lag-1.intercept-true",
        point_forecast = 2.25,
        n_draws = 1_000,
        distribution_artifact_sha256 = DISTRIBUTION_HASH,
        status = "success",
        failure_code = nothing,
        information_track = "common_information",
    )
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-forecast-record.v3",
        "experiment_id" => EXPERIMENT_ID,
        "forecast_id" => forecast_id,
        "execution_registered_at_utc" => "2026-07-31T14:01:00Z",
        "origin_id" => "origin.2026q2.advance",
        "origin_timestamp_utc" => "2026-07-31T14:00:00Z",
        "origin_manifest_sha256" => ORIGIN_HASH,
        "origin_data_sample_sha256" => ORIGIN_DATA_SAMPLE_HASH,
        "origin_data_receipt_sha256" => ORIGIN_DATA_RECEIPT_HASH,
        "protocol_sha256" => PROTOCOL_HASH,
        "model_id" => model_id,
        "model_manifest_sha256" => MODEL_MANIFEST_HASH,
        "model_card_sha256" => MODEL_CARD_HASH,
        "product_id" => "quarterly-unconditional",
        "information_track" => information_track,
        "target_id" => "real-gdp-growth",
        "target_operator_version" => "nipa-real-gdp-growth.v1",
        "transformation_version" => "annualized-log-growth.v1",
        "horizon" => 1,
        "target_period_start" => "2026-07-01",
        "target_period_end" => "2026-09-30",
        "truth_key" => "real-gdp-growth.2026q3",
        "status" => status,
        "point_forecast" => point_forecast,
        "distribution_artifact_sha256" =>
            distribution_artifact_sha256,
        "n_draws" => n_draws,
        "seed" => 77,
        "seed_key_sha256" => SEED_KEY_HASH,
        "failure_code" => failure_code,
    )
end

function truth_payload(;
        truth_id = "truth.real-gdp-growth.2026q3.first",
        truth_key = "real-gdp-growth.2026q3",
        truth_vintage = "first_release",
        value = 2.1,
    )
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-truth-record.v2",
        "experiment_id" => EXPERIMENT_ID,
        "truth_id" => truth_id,
        "truth_key" => truth_key,
        "execution_appended_at_utc" => "2026-10-29T13:31:00Z",
        "release_timestamp_utc" => "2026-10-29T12:30:00Z",
        "target_id" => "real-gdp-growth",
        "target_operator_version" => "nipa-real-gdp-growth.v1",
        "transformation_version" => "annualized-log-growth.v1",
        "target_period_start" => "2026-07-01",
        "target_period_end" => "2026-09-30",
        "truth_vintage" => truth_vintage,
        "value" => value,
        "source_artifact_sha256" => SOURCE_HASH,
    )
end

function score_payload(
        forecast_record, truth_record;
        score_id = "score.ar1.gdp.h1.squared-error",
        forecast_id = "forecast.ar1.gdp.h1",
        truth_id = "truth.real-gdp-growth.2026q3.first",
        forecast_record_sha256 = forecast_record["record_sha256"],
        truth_record_sha256 = truth_record["record_sha256"],
    )
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-score-record.v2",
        "experiment_id" => EXPERIMENT_ID,
        "score_id" => score_id,
        "forecast_id" => forecast_id,
        "truth_id" => truth_id,
        "forecast_record_sha256" => forecast_record_sha256,
        "truth_record_sha256" => truth_record_sha256,
        "evaluation_version" => "us-evaluation.v1",
        "metric" => "squared-error",
        "value" => (2.25 - 2.1)^2,
        "execution_evaluated_at_utc" => "2026-10-29T13:32:00Z",
    )
end

function make_registry(directory)
    return create_registry!(
        directory;
        experiment_id = EXPERIMENT_ID,
        protocol_sha256 = PROTOCOL_HASH,
        environment_sha256 = ENVIRONMENT_HASH,
        knowledge_cutoff_utc = "2026-07-31T14:00:00Z",
        execution_created_at_utc = "2026-07-31T14:00:00Z",
    )
end

function retrospective_forecast_payload(;
        origin_timestamp_utc = "2010-01-29T13:30:00Z",
        execution_registered_at_utc = "2026-08-06T09:01:00Z",
    )
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-forecast-record.v3",
        "experiment_id" => RETROSPECTIVE_EXPERIMENT_ID,
        "forecast_id" => "forecast.replay.ar1.gdp.h1",
        "execution_registered_at_utc" =>
            execution_registered_at_utc,
        "origin_id" => "origin.2010q1.advance",
        "origin_timestamp_utc" => origin_timestamp_utc,
        "origin_manifest_sha256" => ORIGIN_HASH,
        "origin_data_sample_sha256" => ORIGIN_DATA_SAMPLE_HASH,
        "origin_data_receipt_sha256" => ORIGIN_DATA_RECEIPT_HASH,
        "protocol_sha256" => PROTOCOL_HASH,
        "model_id" => "ar.fixed-lag-1.intercept-true",
        "model_manifest_sha256" => MODEL_MANIFEST_HASH,
        "model_card_sha256" => MODEL_CARD_HASH,
        "product_id" => "quarterly-unconditional",
        "information_track" => "common_information",
        "target_id" => "real-gdp-growth",
        "target_operator_version" => "nipa-real-gdp-growth.v1",
        "transformation_version" => "annualized-log-growth.v1",
        "horizon" => 1,
        "target_period_start" => "2010-04-01",
        "target_period_end" => "2010-06-30",
        "truth_key" => "real-gdp-growth.2010q2",
        "status" => "success",
        "point_forecast" => 2.25,
        "distribution_artifact_sha256" => DISTRIBUTION_HASH,
        "n_draws" => 1_000,
        "seed" => 77,
        "seed_key_sha256" => SEED_KEY_HASH,
        "failure_code" => nothing,
    )
end

function quarantine_truth_record(;
        truth_id = "truth.real-gdp-growth.2010q2.first",
        release_timestamp_utc = "2010-07-30T12:30:00Z",
        value = 2.1,
    )
    return Dict{String, Any}(
        "truth_id" => truth_id,
        "truth_key" => "real-gdp-growth.2010q2",
        "release_timestamp_utc" => release_timestamp_utc,
        "target_id" => "real-gdp-growth",
        "target_operator_version" => "nipa-real-gdp-growth.v1",
        "transformation_version" => "annualized-log-growth.v1",
        "target_period_start" => "2010-04-01",
        "target_period_end" => "2010-06-30",
        "truth_vintage" => "first_release",
        "value" => value,
        "source_artifact_sha256" => SOURCE_HASH,
    )
end

function quarantine_manifest(;
        records = [quarantine_truth_record()],
        knowledge_cutoff_utc = "2010-01-29T13:30:00Z",
    )
    return Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-retrospective-truth-quarantine.v1",
            "experiment_id" => RETROSPECTIVE_EXPERIMENT_ID,
            "protocol_sha256" => PROTOCOL_HASH,
            "knowledge_cutoff_utc" => knowledge_cutoff_utc,
            "truth_record_count" => length(records),
        ),
        "truth_records" => records,
    )
end

function write_toml(path, payload)
    open(path, "w") do io
        TOML.print(io, payload; sorted = true)
    end
    return path
end

function make_retrospective_registry(
        directory,
        manifest_path;
        commitment_nonce = QUARANTINE_NONCE,
    )
    return create_registry!(
        directory;
        experiment_id = RETROSPECTIVE_EXPERIMENT_ID,
        protocol_sha256 = PROTOCOL_HASH,
        environment_sha256 = ENVIRONMENT_HASH,
        run_mode = "retrospective_replay",
        knowledge_cutoff_utc = "2010-01-29T13:30:00Z",
        execution_created_at_utc = "2026-08-06T09:00:00Z",
        truth_quarantine_commitment_sha256 =
            truth_quarantine_commitment(
            manifest_path,
            commitment_nonce,
        ),
    )
end

function retrospective_truth_payload(;
        truth_id = "truth.real-gdp-growth.2010q2.first",
        value = 2.1,
        execution_appended_at_utc = "2026-08-06T09:04:00Z",
    )
    committed = quarantine_truth_record(
        truth_id = truth_id,
        value = value,
    )
    return merge(
        Dict{String, Any}(
            "schema_version" => "beforeit-us-truth-record.v2",
            "experiment_id" => RETROSPECTIVE_EXPERIMENT_ID,
            "execution_appended_at_utc" =>
                execution_appended_at_utc,
        ),
        committed,
    )
end

function retrospective_score_payload(forecast_record, truth_record)
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-score-record.v2",
        "experiment_id" => RETROSPECTIVE_EXPERIMENT_ID,
        "score_id" => "score.replay.ar1.gdp.h1.squared-error",
        "forecast_id" => "forecast.replay.ar1.gdp.h1",
        "truth_id" => "truth.real-gdp-growth.2010q2.first",
        "forecast_record_sha256" => forecast_record["record_sha256"],
        "truth_record_sha256" => truth_record["record_sha256"],
        "evaluation_version" => "us-evaluation.v1",
        "metric" => "squared-error",
        "value" => (2.25 - 2.1)^2,
        "execution_evaluated_at_utc" => "2026-08-06T09:05:00Z",
    )
end

function prepare_revealed_registry(parent, name)
    manifest_path = write_toml(
        joinpath(parent, "$name-quarantine.toml"),
        quarantine_manifest(),
    )
    directory = joinpath(parent, name)
    make_retrospective_registry(directory, manifest_path)
    append_forecast!(directory, retrospective_forecast_payload())
    seal_forecasts!(
        directory;
        execution_sealed_at_utc = "2026-08-06T09:02:00Z",
    )
    reveal_retrospective_truth!(
        directory;
        quarantine_manifest_path = manifest_path,
        commitment_nonce = QUARANTINE_NONCE,
        execution_revealed_at_utc = "2026-08-06T09:03:00Z",
    )
    return directory
end

@testset "origin/model/path RNG substreams" begin
    before = MersenneTwister(20260805)
    untouched = copy(before)
    first = derive_seed(
        17_000;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = ORIGIN_HASH,
        model_id = "beforeit.corrected.v1",
        path_id = 1,
        purpose = "forecast",
    )
    repeated = derive_seed(
        17_000;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = ORIGIN_HASH,
        model_id = "beforeit.corrected.v1",
        path_id = 1,
        purpose = "forecast",
    )
    second_path = derive_seed(
        17_000;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = ORIGIN_HASH,
        model_id = "beforeit.corrected.v1",
        path_id = 2,
        purpose = "forecast",
    )
    second_model = derive_seed(
        17_000;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = ORIGIN_HASH,
        model_id = "bvar.minnesota.v1",
        path_id = 1,
        purpose = "forecast",
    )
    @test first == repeated
    record = derive_seed_record(
        17_000;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = ORIGIN_HASH,
        model_id = "beforeit.corrected.v1",
        path_id = 1,
        purpose = "forecast",
    )
    @test record.seed == 5_541_391_213_369_324_329
    @test record.seed_key_sha256 ==
        "cce6f9f2f25973288bc15e591b8ad7ce3f4a4e19ab7683835aa2f73ddc53015c"
    @test length(Set([first, second_path, second_model])) == 3
    @test first >= 0
    @test rand(before) == rand(untouched)
    @test_throws RegistryValidationError derive_seed(
        -1;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = ORIGIN_HASH,
        model_id = "beforeit.corrected.v1",
        path_id = 1,
        purpose = "forecast",
    )
    @test_throws RegistryValidationError derive_seed(
        1;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = "not-a-hash",
        model_id = "beforeit.corrected.v1",
        path_id = 1,
        purpose = "forecast",
    )
end

@testset "sealed forecast registry lifecycle" begin
    mktempdir() do directory
        registry = make_registry(directory)
        @test registry.verified
        @test registry.forecast_count == 0
        @test registry.truth_count == 0
        @test registry.score_count == 0
        @test registry.seal === nothing

        @test_throws RegistryValidationError append_truth!(
            directory,
            truth_payload(),
        )
        @test verify_registry(directory).truth_count == 0

        backdated_forecast = forecast_payload()
        backdated_forecast["execution_registered_at_utc"] =
            "2026-07-31T13:58:00Z"
        @test_throws RegistryValidationError append_forecast!(
            directory,
            backdated_forecast,
        )
        @test verify_registry(directory).forecast_count == 0

        missing_sample_hash = forecast_payload()
        delete!(
            missing_sample_hash,
            "origin_data_sample_sha256",
        )
        @test_throws RegistryValidationError append_forecast!(
            directory,
            missing_sample_hash,
        )
        missing_receipt_hash = forecast_payload()
        delete!(
            missing_receipt_hash,
            "origin_data_receipt_sha256",
        )
        @test_throws RegistryValidationError append_forecast!(
            directory,
            missing_receipt_hash,
        )
        zero_sample_hash = forecast_payload()
        zero_sample_hash["origin_data_sample_sha256"] =
            repeat("0", 64)
        @test_throws RegistryValidationError append_forecast!(
            directory,
            zero_sample_hash,
        )
        malformed_receipt_hash = forecast_payload()
        malformed_receipt_hash["origin_data_receipt_sha256"] =
            "not-a-receipt-hash"
        @test_throws RegistryValidationError append_forecast!(
            directory,
            malformed_receipt_hash,
        )
        legacy_v2_forecast = forecast_payload()
        legacy_v2_forecast["schema_version"] =
            "beforeit-us-forecast-record.v2"
        @test_throws RegistryValidationError append_forecast!(
            directory,
            legacy_v2_forecast,
        )
        @test verify_registry(directory).forecast_count == 0

        forecast = append_forecast!(directory, forecast_payload())
        @test occursin(r"^[0-9a-f]{64}$", forecast["record_sha256"])
        @test forecast["payload"]["origin_data_sample_sha256"] ==
            ORIGIN_DATA_SAMPLE_HASH
        @test forecast["payload"]["origin_data_receipt_sha256"] ==
            ORIGIN_DATA_RECEIPT_HASH
        @test verify_registry(directory).forecast_count == 1

        published = append_forecast!(
            directory,
            forecast_payload(
                forecast_id = "forecast.spf.gdp.h1",
                model_id = "spf.archived.v1",
                information_track = "published_forecast",
            ),
        )
        @test published["payload"]["information_track"] ==
            "published_forecast"
        legacy_track = forecast_payload(
            forecast_id = "forecast.legacy-track.gdp.h1",
            model_id = "spf.legacy.v1",
            information_track = "published_information",
        )
        @test_throws RegistryValidationError append_forecast!(
            directory,
            legacy_track,
        )

        duplicate_id = forecast_payload(model_id = "ar.fixed-lag-2.intercept-true")
        @test_throws RegistryValidationError append_forecast!(
            directory,
            duplicate_id,
        )
        duplicate_key = forecast_payload(forecast_id = "forecast.duplicate")
        @test_throws RegistryValidationError append_forecast!(
            directory,
            duplicate_key,
        )
        unexpected_outcome = forecast_payload()
        unexpected_outcome["truth_value"] = 2.1
        @test_throws RegistryValidationError append_forecast!(
            directory,
            unexpected_outcome,
        )
        @test verify_registry(directory).forecast_count == 2

        failed = append_forecast!(
            directory,
            forecast_payload(
                forecast_id = "forecast.failed.gdp.h1",
                model_id = "bvar.rank-deficient",
                point_forecast = nothing,
                n_draws = 0,
                distribution_artifact_sha256 = nothing,
                status = "failed",
                failure_code = "rank-deficient",
            ),
        )
        @test failed["payload"]["status"] == "failed"
        @test failed["payload"]["origin_data_sample_sha256"] ==
            ORIGIN_DATA_SAMPLE_HASH
        @test failed["payload"]["origin_data_receipt_sha256"] ==
            ORIGIN_DATA_RECEIPT_HASH

        @test_throws RegistryValidationError seal_forecasts!(
            directory;
            execution_sealed_at_utc = "2026-07-31T14:00:30Z",
        )
        @test verify_registry(directory).seal === nothing
        seal = seal_forecasts!(
            directory;
            execution_sealed_at_utc = "2026-07-31T14:02:00Z",
        )
        @test seal["forecast_count"] == 3
        sealed_bytes = read(joinpath(directory, "forecasts.jsonl"))
        @test_throws RegistryValidationError append_forecast!(
            directory,
            forecast_payload(
                forecast_id = "forecast.after-seal",
                model_id = "mean.expanding",
            ),
        )
        @test read(joinpath(directory, "forecasts.jsonl")) == sealed_bytes

        released_too_late = truth_payload()
        released_too_late["execution_appended_at_utc"] =
            "2026-10-29T12:00:00Z"
        @test_throws RegistryValidationError append_truth!(
            directory,
            released_too_late,
        )
        released_before_seal = truth_payload()
        released_before_seal["release_timestamp_utc"] =
            "2026-07-31T14:01:30Z"
        @test_throws RegistryValidationError append_truth!(
            directory,
            released_before_seal,
        )
        unrelated_truth = truth_payload(
            truth_id = "truth.unrelated",
            truth_key = "real-gdp-growth.2025q1",
        )
        @test_throws RegistryValidationError append_truth!(
            directory,
            unrelated_truth,
        )
        truth = append_truth!(directory, truth_payload())
        @test verify_registry(directory).truth_count == 1

        duplicate_truth = truth_payload(
            truth_id = "truth.real-gdp-growth.duplicate",
        )
        @test_throws RegistryValidationError append_truth!(
            directory,
            duplicate_truth,
        )
        @test verify_registry(directory).truth_count == 1

        wrong_forecast_hash = score_payload(
            forecast,
            truth;
            forecast_record_sha256 = repeat("9", 64),
        )
        @test_throws RegistryValidationError append_score!(
            directory,
            wrong_forecast_hash,
        )
        unknown_forecast = score_payload(
            forecast,
            truth;
            forecast_id = "forecast.unknown",
        )
        @test_throws RegistryValidationError append_score!(
            directory,
            unknown_forecast,
        )
        failed_score = score_payload(
            failed,
            truth;
            score_id = "score.failed",
            forecast_id = "forecast.failed.gdp.h1",
        )
        @test_throws RegistryValidationError append_score!(
            directory,
            failed_score,
        )
        premature_score = score_payload(
            forecast,
            truth;
            score_id = "score.premature",
        )
        premature_score["execution_evaluated_at_utc"] =
            "2026-10-29T13:30:00Z"
        @test_throws RegistryValidationError append_score!(
            directory,
            premature_score,
        )
        @test verify_registry(directory).score_count == 0

        score = append_score!(
            directory,
            score_payload(forecast, truth),
        )
        @test occursin(r"^[0-9a-f]{64}$", score["record_sha256"])
        verified = verify_registry(directory)
        @test verified.forecast_count == 3
        @test verified.truth_count == 1
        @test verified.score_count == 1

        duplicate_score = score_payload(
            forecast,
            truth;
            score_id = "score.duplicate",
        )
        @test_throws RegistryValidationError append_score!(
            directory,
            duplicate_score,
        )
        @test verify_registry(directory).score_count == 1
    end
end

@testset "v3 registry mode and execution-time invariants" begin
    mktempdir() do parent
        manifest_path = write_toml(
            joinpath(parent, "quarantine.toml"),
            quarantine_manifest(),
        )
        @test_throws RegistryValidationError create_registry!(
            joinpath(parent, "backdated-creation");
            experiment_id = RETROSPECTIVE_EXPERIMENT_ID,
            protocol_sha256 = PROTOCOL_HASH,
            environment_sha256 = ENVIRONMENT_HASH,
            run_mode = "retrospective_replay",
            knowledge_cutoff_utc = "2026-08-06T09:01:00Z",
            execution_created_at_utc = "2026-08-06T09:00:00Z",
            truth_quarantine_commitment_sha256 =
                truth_quarantine_commitment(
                manifest_path,
                QUARANTINE_NONCE,
            ),
        )
        @test_throws RegistryValidationError create_registry!(
            joinpath(parent, "missing-commitment");
            experiment_id = RETROSPECTIVE_EXPERIMENT_ID,
            protocol_sha256 = PROTOCOL_HASH,
            environment_sha256 = ENVIRONMENT_HASH,
            run_mode = "retrospective_replay",
            knowledge_cutoff_utc = "2010-01-29T13:30:00Z",
            execution_created_at_utc = "2026-08-06T09:00:00Z",
        )
        @test_throws RegistryValidationError create_registry!(
            joinpath(parent, "prospective-with-commitment");
            experiment_id = EXPERIMENT_ID,
            protocol_sha256 = PROTOCOL_HASH,
            environment_sha256 = ENVIRONMENT_HASH,
            run_mode = "prospective",
            knowledge_cutoff_utc = "2026-07-31T14:00:00Z",
            execution_created_at_utc = "2026-07-31T14:00:00Z",
            truth_quarantine_commitment_sha256 = repeat("9", 64),
        )

        prospective_directory = joinpath(parent, "prospective")
        make_registry(prospective_directory)
        append_forecast!(prospective_directory, forecast_payload())
        seal_forecasts!(
            prospective_directory;
            execution_sealed_at_utc = "2026-07-31T14:02:00Z",
        )
        @test_throws RegistryValidationError reveal_retrospective_truth!(
            prospective_directory;
            quarantine_manifest_path = manifest_path,
            commitment_nonce = QUARANTINE_NONCE,
            execution_revealed_at_utc = "2026-07-31T14:03:00Z",
        )
    end
end

@testset "retrospective replay quarantines truth until post-seal reveal" begin
    mktempdir() do parent
        manifest_path = write_toml(
            joinpath(parent, "quarantine.toml"),
            quarantine_manifest(),
        )
        directory = joinpath(parent, "registry")
        registry = make_retrospective_registry(directory, manifest_path)
        @test registry.verified
        @test registry.header["run_mode"] == "retrospective_replay"
        @test registry.header["knowledge_cutoff_utc"] ==
            "2010-01-29T13:30:00Z"
        @test registry.header["execution_created_at_utc"] ==
            "2026-08-06T09:00:00Z"
        @test registry.reveal === nothing
        @test registry.committed_truth_count === nothing
        @test registry.truth_reveal_complete === nothing

        @test_throws RegistryValidationError append_truth!(
            directory,
            retrospective_truth_payload(),
        )
        wrong_origin = retrospective_forecast_payload(
            origin_timestamp_utc = "2010-01-29T13:29:59Z",
        )
        @test_throws RegistryValidationError append_forecast!(
            directory,
            wrong_origin,
        )
        backdated_registration = retrospective_forecast_payload(
            execution_registered_at_utc = "2026-08-06T08:59:59Z",
        )
        @test_throws RegistryValidationError append_forecast!(
            directory,
            backdated_registration,
        )

        forecast = append_forecast!(
            directory,
            retrospective_forecast_payload(),
        )
        @test forecast["payload"]["origin_timestamp_utc"] <
            forecast["payload"]["execution_registered_at_utc"]
        @test_throws RegistryValidationError reveal_retrospective_truth!(
            directory;
            quarantine_manifest_path = manifest_path,
            commitment_nonce = QUARANTINE_NONCE,
            execution_revealed_at_utc = "2026-08-06T09:02:00Z",
        )
        seal = seal_forecasts!(
            directory;
            execution_sealed_at_utc = "2026-08-06T09:02:00Z",
        )
        @test seal["execution_sealed_at_utc"] ==
            "2026-08-06T09:02:00Z"
        @test quarantine_truth_record()["release_timestamp_utc"] <
            seal["execution_sealed_at_utc"]
        @test_throws RegistryValidationError append_truth!(
            directory,
            retrospective_truth_payload(),
        )
        unappended_truth_stub =
            Dict("record_sha256" => repeat("8", 64))
        @test_throws RegistryValidationError append_score!(
            directory,
            retrospective_score_payload(
                forecast,
                unappended_truth_stub,
            ),
        )

        @test_throws RegistryValidationError reveal_retrospective_truth!(
            directory;
            quarantine_manifest_path = manifest_path,
            commitment_nonce = repeat("4", 64),
            execution_revealed_at_utc = "2026-08-06T09:03:00Z",
        )
        tampered_path = write_toml(
            joinpath(parent, "tampered.toml"),
            quarantine_manifest(
                records = [quarantine_truth_record(value = 2.2)],
            ),
        )
        @test_throws RegistryValidationError reveal_retrospective_truth!(
            directory;
            quarantine_manifest_path = tampered_path,
            commitment_nonce = QUARANTINE_NONCE,
            execution_revealed_at_utc = "2026-08-06T09:03:00Z",
        )
        future_truth_path = write_toml(
            joinpath(parent, "future-truth.toml"),
            quarantine_manifest(
                records = [
                    quarantine_truth_record(
                        release_timestamp_utc =
                            "2027-07-30T12:30:00Z",
                    ),
                ],
            ),
        )
        @test_throws RegistryValidationError reveal_retrospective_truth!(
            directory;
            quarantine_manifest_path = future_truth_path,
            commitment_nonce = QUARANTINE_NONCE,
            execution_revealed_at_utc = "2026-08-06T09:03:00Z",
        )
        @test !isfile(
            joinpath(directory, "truth_quarantine_manifest.toml"),
        )
        @test !isfile(
            joinpath(directory, "truth_reveal_receipt.toml"),
        )
        @test_throws RegistryValidationError reveal_retrospective_truth!(
            directory;
            quarantine_manifest_path = manifest_path,
            commitment_nonce = QUARANTINE_NONCE,
            execution_revealed_at_utc = "2026-08-06T09:02:00Z",
        )

        reveal = reveal_retrospective_truth!(
            directory;
            quarantine_manifest_path = manifest_path,
            commitment_nonce = QUARANTINE_NONCE,
            execution_revealed_at_utc = "2026-08-06T09:03:00Z",
        )
        @test reveal.receipt["forecast_seal_sha256"] ==
            seal["seal_sha256"]
        @test read(joinpath(directory, "truth_quarantine_manifest.toml")) ==
            read(manifest_path)
        revealed_registry = verify_registry(directory)
        @test revealed_registry.committed_truth_count == 1
        @test revealed_registry.truth_reveal_complete == false
        @test_throws RegistryValidationError reveal_retrospective_truth!(
            directory;
            quarantine_manifest_path = manifest_path,
            commitment_nonce = QUARANTINE_NONCE,
            execution_revealed_at_utc = "2026-08-06T09:03:01Z",
        )

        early_append = retrospective_truth_payload(
            execution_appended_at_utc = "2026-08-06T09:02:59Z",
        )
        @test_throws RegistryValidationError append_truth!(
            directory,
            early_append,
        )
        changed_truth = retrospective_truth_payload(value = 2.2)
        @test_throws RegistryValidationError append_truth!(
            directory,
            changed_truth,
        )
        uncommitted_truth = retrospective_truth_payload(
            truth_id = "truth.real-gdp-growth.2010q2.uncommitted",
        )
        @test_throws RegistryValidationError append_truth!(
            directory,
            uncommitted_truth,
        )

        truth = append_truth!(
            directory,
            retrospective_truth_payload(),
        )
        @test truth["payload"]["release_timestamp_utc"] <
            truth["payload"]["execution_appended_at_utc"]
        @test verify_registry(directory).truth_reveal_complete == true
        score = append_score!(
            directory,
            retrospective_score_payload(forecast, truth),
        )
        @test occursin(r"^[0-9a-f]{64}$", score["record_sha256"])
        verified = verify_registry(directory)
        @test verified.forecast_count == 1
        @test verified.truth_count == 1
        @test verified.score_count == 1
        @test verified.truth_reveal_complete == true

        internal_manifest =
            joinpath(directory, "truth_quarantine_manifest.toml")
        original = String(read(internal_manifest))
        tampered = replace(original, "2.1" => "2.2"; count = 1)
        @test tampered != original
        open(internal_manifest, "w") do io
            write(io, tampered)
        end
        @test_throws RegistryValidationError verify_registry(directory)
    end
end

@testset "retrospective reveal artifacts are complete and tamper-evident" begin
    mktempdir() do parent
        partial_directory =
            prepare_revealed_registry(parent, "partial-reveal")
        rm(joinpath(partial_directory, "truth_reveal_receipt.toml"))
        @test_throws RegistryValidationError verify_registry(
            partial_directory,
        )

        receipt_directory =
            prepare_revealed_registry(parent, "receipt-tamper")
        receipt_path =
            joinpath(receipt_directory, "truth_reveal_receipt.toml")
        original = String(read(receipt_path))
        tampered = replace(
            original,
            "2026-08-06T09:03:00Z" => "2026-08-06T09:04:00Z";
            count = 1,
        )
        @test tampered != original
        open(receipt_path, "w") do io
            write(io, tampered)
        end
        @test_throws RegistryValidationError verify_registry(
            receipt_directory,
        )

        uncovered_manifest = quarantine_manifest()
        uncovered_manifest["truth_records"][1]["truth_key"] =
            "real-gdp-growth.unregistered"
        uncovered_path = write_toml(
            joinpath(parent, "uncovered-quarantine.toml"),
            uncovered_manifest,
        )
        uncovered_directory = joinpath(parent, "uncovered")
        make_retrospective_registry(
            uncovered_directory,
            uncovered_path,
        )
        append_forecast!(
            uncovered_directory,
            retrospective_forecast_payload(),
        )
        seal_forecasts!(
            uncovered_directory;
            execution_sealed_at_utc = "2026-08-06T09:02:00Z",
        )
        @test_throws RegistryValidationError reveal_retrospective_truth!(
            uncovered_directory;
            quarantine_manifest_path = uncovered_path,
            commitment_nonce = QUARANTINE_NONCE,
            execution_revealed_at_utc = "2026-08-06T09:03:00Z",
        )
    end
end

@testset "record hashes are deterministic and sealed bytes are tamper-evident" begin
    mktempdir() do parent
        first_directory = joinpath(parent, "first")
        second_directory = joinpath(parent, "second")
        make_registry(first_directory)
        make_registry(second_directory)
        first_record =
            append_forecast!(first_directory, forecast_payload())
        second_record =
            append_forecast!(second_directory, forecast_payload())
        @test first_record["record_sha256"] == second_record["record_sha256"]
        @test read(joinpath(first_directory, "forecasts.jsonl")) ==
            read(joinpath(second_directory, "forecasts.jsonl"))

        seal_forecasts!(
            first_directory;
            execution_sealed_at_utc = "2026-07-31T14:02:00Z",
        )
        path = joinpath(first_directory, "forecasts.jsonl")
        original = String(read(path))
        tampered = replace(original, "2.25" => "2.35"; count = 1)
        @test tampered != original
        open(path, "w") do io
            write(io, tampered)
        end
        @test_throws RegistryValidationError verify_registry(first_directory)
    end
end
