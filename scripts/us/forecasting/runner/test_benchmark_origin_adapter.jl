#!/usr/bin/env julia

using Test

include(joinpath(@__DIR__, "..", "benchmarks", "USForecastBenchmarks.jl"))
include(
    joinpath(
        @__DIR__,
        "..",
        "benchmarks",
        "USBenchmarkModelRegistry.jl",
    ),
)
include(joinpath(@__DIR__, "..", "registry", "USForecastRegistry.jl"))
include(
    joinpath(
        @__DIR__,
        "..",
        "targets",
        "USTier1TargetCoverage.jl",
    ),
)
include(joinpath(@__DIR__, "USBenchmarkOriginAdapter.jl"))

using .USBenchmarkOriginAdapter
using .USForecastBenchmarks
using .USForecastRegistry
import .USBenchmarkModelRegistry
import .USTier1TargetCoverage

const EXPERIMENT_ID = "us-origin-adapter.synthetic.v1"
const PROTOCOL_HASH = repeat("a", 64)
const ENVIRONMENT_HASH = repeat("b", 64)
const ORIGIN_HASH = repeat("c", 64)
const MODEL_MANIFEST_HASH = repeat("d", 64)
const MODEL_CARD_HASH = repeat("e", 64)
const DISTRIBUTION_HASH = repeat("f", 64)
const MODEL_REGISTRY_HASH = repeat("9", 64)
const TARGET_CONTRACT_HASH = repeat("8", 64)
const SOURCE_ARTIFACT_HASH = repeat("7", 64)
const ORIGIN_TIMESTAMP = "2026-04-30T14:00:00Z"
const REGISTERED_TIMESTAMP = "2026-04-30T14:01:00Z"
const MASTER_SEED = 20_260_807
const PATH_ID = 3

function origin_fixture(;
        origin_id = "origin.2026q1.synthetic",
        origin_kind = "prospective",
        origin_timestamp_utc = ORIGIN_TIMESTAMP,
        origin_manifest_sha256 = ORIGIN_HASH,
        protocol_sha256 = PROTOCOL_HASH,
        information_track = "common_information",
        evidence_class = "synthetic_fixture_only",
        status = "ready",
    )
    return OriginReadiness(;
        origin_id,
        origin_kind,
        origin_timestamp_utc,
        origin_manifest_sha256,
        protocol_sha256,
        information_track,
        evidence_class,
        status,
    )
end

function product_fixture(;
        information_track = "common_information",
        horizons = [1, 4],
    )
    return ProductMetadata(
        product_id = "quarterly_unconditional",
        kind = "unconditional_forecast",
        conditioning = "none",
        realized_future_data_allowed = false,
        information_track = information_track,
        horizons = horizons,
    )
end

function model_fixture(;
        model_id = "naive_no_change",
        model_manifest_sha256 = MODEL_MANIFEST_HASH,
        model_card_sha256 = MODEL_CARD_HASH,
        registry_content_sha256 = MODEL_REGISTRY_HASH,
        target_contract_sha256 = TARGET_CONTRACT_HASH,
        registry_status = "frozen_implementation_only",
        support_status = "supported",
        information_track = "common_information",
        product_ids = ["quarterly_unconditional"],
        target_panel_id = "synthetic-tier1-subset.v1",
        targets = registered_targets_fixture(),
        execution_class =
            "hermetic_validation_only_no_empirical_forecasts",
        empirical_forecast_execution_allowed = false,
        production_scoring_allowed = false,
    )
    return ModelMetadata(;
        model_id,
        model_manifest_sha256,
        model_card_sha256,
        registry_content_sha256,
        target_contract_sha256,
        registry_status,
        support_status,
        information_track,
        product_ids,
        target_panel_id,
        targets,
        execution_class,
        empirical_forecast_execution_allowed,
        production_scoring_allowed,
    )
end

function sample_fixture(;
        origin_id = "origin.2026q1.synthetic",
        x_train = nothing,
        x_future = nothing,
    )
    training_keys = [
        "2024Q4",
        "2025Q1",
        "2025Q2",
        "2025Q3",
        "2025Q4",
        "2026Q1",
    ]
    forecast_keys = ["2026Q2", "2026Q3", "2026Q4", "2027Q1"]
    y_train = [
        1.0 10.0
        1.5 10.5
        2.0 11.0
        2.5 11.5
        3.0 12.0
        3.5 12.5
    ]
    return OriginData(
        origin_id = origin_id,
        origin_key = "2026Q1",
        training_keys = training_keys,
        forecast_keys = forecast_keys,
        y_train = y_train,
        x_train = x_train,
        x_future = x_future,
        target_names = ["real_gdp", "pce_price_index"],
        predictor_names =
            x_train === nothing ? nothing : ["synthetic_predictor"],
    )
end

function authenticated_fixture(
        sample;
        origin = origin_fixture(),
        model = model_fixture(),
        origin_manifest_sha256 = origin.origin_manifest_sha256,
        protocol_sha256 = origin.protocol_sha256,
        model_registry_content_sha256 =
            model.registry_content_sha256,
        target_contract_sha256 = model.target_contract_sha256,
        target_panel_id = model.target_panel_id,
    )
    return authenticate_origin_data(
        sample;
        origin_manifest_sha256,
        protocol_sha256,
        model_registry_content_sha256,
        target_contract_sha256,
        target_panel_id,
        source_artifacts = [
            SourceArtifact(
                "synthetic-origin-fixture",
                SOURCE_ARTIFACT_HASH,
            ),
        ],
    )
end

const TARGET_METADATA = Dict(
    "real_gdp" => (
        target_id = "real_gdp",
        operator = "abm-to-bea-real-gdp.v1-draft",
        transformation = "us-real-gdp-growth.v1-draft",
    ),
    "pce_price_index" => (
        target_id = "pce_price_index",
        operator = "abm-to-bea-pce-price-index.v1-draft",
        transformation = "us-pce-price-inflation.v1-draft",
    ),
)

const PERIOD_METADATA = Dict(
    1 => (
        start = "2026-04-01",
        stop = "2026-06-30",
        suffix = "2026q2",
    ),
    4 => (
        start = "2027-01-01",
        stop = "2027-03-31",
        suffix = "2027q1",
    ),
)

function registered_targets_fixture()
    return RegisteredTarget[
        RegisteredTarget(
                target_id = TARGET_METADATA[target_name].target_id,
                target_operator_version =
                TARGET_METADATA[target_name].operator,
                transformation_version =
                TARGET_METADATA[target_name].transformation,
            ) for
            target_name in ("real_gdp", "pce_price_index")
    ]
end

function resolved_no_change_registration()
    registry = USBenchmarkModelRegistry.load_model_registry(;
        verify_artifacts = true,
    )
    entry = USBenchmarkModelRegistry.model_entry(
        registry,
        "naive_no_change",
    )
    panel = only(
        candidate
            for candidate in registry["target_panels"]
            if candidate["target_panel_id"] == entry["target_panel_id"]
    )
    inventory =
        USTier1TargetCoverage.load_inventory()
    inventory_validation =
        USTier1TargetCoverage.validate_inventory(inventory)
    inventory_targets = Dict(
        target["target_id"] => target for target in inventory["targets"]
    )
    targets = RegisteredTarget[]
    for panel_target in panel["targets"]
        target = inventory_targets[panel_target["target_id"]]
        panel_target["operator_version"] == target["operator_version"] ||
            error("model and target registries disagree on operator version")
        panel_target["primary_transformation"] ==
            target["primary_transformation"] ||
            error("model and target registries disagree on transformation")
        panel_target["transformation_version"] ==
            target["transformation_version"] ||
            error("model and target registries disagree on transformation version")
        push!(
            targets,
            RegisteredTarget(
                target_id = target["target_id"],
                target_operator_version = target["operator_version"],
                transformation_version =
                    panel_target["transformation_version"],
            ),
        )
    end
    card = only(
        artifact
            for artifact in registry["artifacts"]
            if artifact["artifact_id"] ==
            entry["model_card_artifact_id"]
    )
    scope = registry["execution_scope"]
    metadata = ModelMetadata(
        model_id = entry["model_id"],
        model_manifest_sha256 =
            USBenchmarkModelRegistry.model_manifest_sha256(
            registry,
            entry["model_id"],
        ),
        model_card_sha256 = card["sha256"],
        registry_content_sha256 =
            registry["registry_content_sha256"],
        target_contract_sha256 = inventory_validation.sha256,
        registry_status = registry["registry_status"],
        support_status = entry["support_status"],
        information_track = entry["information_track"],
        product_ids = entry["products"],
        target_panel_id = entry["target_panel_id"],
        targets = targets,
        execution_class = scope["evidence_class"],
        empirical_forecast_execution_allowed =
            scope["empirical_forecast_execution_allowed"],
        production_scoring_allowed =
            scope["production_scoring_allowed"],
    )
    return (; metadata, registry, inventory)
end

function full_panel_sample(model)
    observations = 40
    targets = length(model.targets)
    training = Matrix{Float64}(undef, observations, targets)
    for row in 1:observations, column in 1:targets
        training[row, column] = row + column / 10
    end
    return OriginData(
        origin_id = "origin.2026q1.synthetic",
        origin_key = observations,
        training_keys = collect(1:observations),
        forecast_keys =
            collect((observations + 1):(observations + 4)),
        y_train = training,
        target_names =
            [target.target_id for target in model.targets],
    )
end

function full_panel_cells(sample, model)
    cells = ForecastCell[]
    for target in model.targets
        for horizon in (1, 4)
            period = PERIOD_METADATA[horizon]
            push!(
                cells,
                ForecastCell(
                    forecast_id =
                        "forecast.$(target.target_id).h$horizon",
                    target_name = target.target_id,
                    target_id = target.target_id,
                    target_operator_version =
                        target.target_operator_version,
                    transformation_version =
                        target.transformation_version,
                    horizon = horizon,
                    output_index = horizon,
                    forecast_key = sample.forecast_keys[horizon],
                    target_period_start = period.start,
                    target_period_end = period.stop,
                    truth_key =
                        "$(target.target_id).$(period.suffix)",
                ),
            )
        end
    end
    return cells
end

function cells_fixture(sample = sample_fixture(); horizons = [1, 4])
    cells = ForecastCell[]
    for target_name in sample.target_names
        target = TARGET_METADATA[target_name]
        for horizon in horizons
            period = PERIOD_METADATA[horizon]
            push!(
                cells,
                ForecastCell(
                    forecast_id =
                        "forecast.$(target.target_id).h$horizon",
                    target_name = target_name,
                    target_id = target.target_id,
                    target_operator_version = target.operator,
                    transformation_version = target.transformation,
                    horizon = horizon,
                    output_index = horizon,
                    forecast_key = sample.forecast_keys[horizon],
                    target_period_start = period.start,
                    target_period_end = period.stop,
                    truth_key =
                        "$(target.target_id).$(period.suffix)",
                ),
            )
        end
    end
    return cells
end

function adapter_kwargs(
        sample = sample_fixture();
        origin = origin_fixture(),
        product = product_fixture(),
        model = model_fixture(),
        authenticated_origin_data =
            authenticated_fixture(sample; origin, model),
        cells = cells_fixture(sample),
        n_draws = 0,
        seed_deriver = USForecastRegistry.derive_seed_record,
        distribution_hash_provider = nothing,
    )
    return (;
        origin,
        product,
        model,
        authenticated_origin_data,
        cells,
        experiment_id = EXPERIMENT_ID,
        protocol_sha256 = PROTOCOL_HASH,
        execution_registered_at_utc = REGISTERED_TIMESTAMP,
        master_seed = MASTER_SEED,
        path_id = PATH_ID,
        n_draws,
        seed_deriver,
        benchmark_model_id = USForecastBenchmarks.model_id,
        benchmark_runner = USForecastBenchmarks.run_benchmark,
        distribution_hash_provider,
    )
end

function adapter_error(f)
    try
        f()
    catch error
        error isa AdapterValidationError || rethrow()
        return sprint(showerror, error)
    end
    error("expected AdapterValidationError")
end

function appendable_registry(records)
    return mktempdir() do directory
        create_registry!(
            directory;
            experiment_id = EXPERIMENT_ID,
            protocol_sha256 = PROTOCOL_HASH,
            environment_sha256 = ENVIRONMENT_HASH,
            knowledge_cutoff_utc = ORIGIN_TIMESTAMP,
            execution_created_at_utc = ORIGIN_TIMESTAMP,
        )
        envelopes = [
            append_forecast!(directory, record) for record in records
        ]
        verified = verify_registry(directory)
        return (; envelopes, verified)
    end
end

@testset "strict metadata and canonical track vocabulary" begin
    @test AuthenticatedOriginData ===
        USOriginDataReceipt.AuthenticatedOriginData
    @test authenticate_origin_data ===
        USOriginDataReceipt.authenticate_origin_data
    @test :receipt_validator ∉ propertynames(adapter_kwargs())
    @test origin_fixture().status == "ready"
    @test product_fixture().horizons == (1, 4)
    @test model_fixture().model_id == "naive_no_change"

    readiness_message =
        adapter_error(() -> origin_fixture(status = "cannot_run"))
    @test occursin("explicit validated value ready", readiness_message)

    current_message = adapter_error(
        () -> origin_fixture(origin_kind = "current_diagnostic"),
    )
    @test occursin("tracked current diagnostics", current_message)

    mixed_message = adapter_error(
        () -> origin_fixture(
            origin_kind = "current_diagnostic",
            information_track = "revised_mixed_vintage_diagnostic",
            evidence_class = "diagnostic_only_no_promotion",
        ),
    )
    @test occursin("mixed-vintage diagnostic", mixed_message)

    alias_message = adapter_error(
        () -> origin_fixture(
            information_track = "published_information",
        ),
    )
    @test occursin("protocol-canonical", alias_message)
    @test occursin("published_forecast", alias_message)

    published_origin = origin_fixture(
        information_track = "published_forecast",
        evidence_class = "published_archive_candidate",
    )
    published_product =
        product_fixture(information_track = "published_forecast")
    @test published_origin.information_track == "published_forecast"
    @test published_product.information_track == "published_forecast"

    @test_throws AdapterValidationError origin_fixture(
        origin_manifest_sha256 = repeat("0", 64),
    )
    @test_throws AdapterValidationError origin_fixture(
        protocol_sha256 = uppercase(PROTOCOL_HASH),
    )
    @test_throws AdapterValidationError model_fixture(
        model_manifest_sha256 = "not-a-hash",
    )
    @test_throws AdapterValidationError model_fixture(
        model_card_sha256 = repeat("0", 64),
    )
    @test_throws AdapterValidationError model_fixture(
        target_contract_sha256 = repeat("0", 64),
    )
    @test_throws AdapterValidationError model_fixture(
        registry_status = "production_approved",
    )
    @test_throws AdapterValidationError model_fixture(
        support_status = "unsupported",
    )
    @test_throws AdapterValidationError model_fixture(
        empirical_forecast_execution_allowed = true,
    )
    @test_throws AdapterValidationError model_fixture(
        production_scoring_allowed = true,
    )
    @test_throws AdapterValidationError ProductMetadata(
        product_id = "quarterly_unconditional",
        kind = "conditional_scenario",
        conditioning = "none",
        realized_future_data_allowed = false,
        information_track = "common_information",
        horizons = [1],
    )
    @test_throws AdapterValidationError ProductMetadata(
        product_id = "ragged_edge_nowcast",
        kind = "ragged_edge_nowcast",
        conditioning = "released_ragged_edge_observations_only",
        realized_future_data_allowed = false,
        information_track = "common_information",
        horizons = [0, 1],
    )
    @test_throws AdapterValidationError product_fixture(horizons = [3])
    @test_throws AdapterValidationError product_fixture(horizons = [4, 1])

    @test_throws AdapterValidationError ForecastCell(
        forecast_id = "forecast.real_gdp.h1",
        target_name = "real_gdp",
        target_id = "real_gdp",
        target_operator_version = "",
        transformation_version = "us-real-gdp-growth.v1-draft",
        horizon = 1,
        output_index = 1,
        forecast_key = "2026Q2",
        target_period_start = "2026-04-01",
        target_period_end = "2026-06-30",
        truth_key = "real_gdp.2026q2",
    )
    @test_throws AdapterValidationError ForecastCell(
        forecast_id = "forecast.real_gdp.h4",
        target_name = "real_gdp",
        target_id = "real_gdp",
        target_operator_version = "abm-to-bea-real-gdp.v1-draft",
        transformation_version = "us-real-gdp-growth.v1-draft",
        horizon = 4,
        output_index = 3,
        forecast_key = "2026Q4",
        target_period_start = "2027-01-01",
        target_period_end = "2027-03-31",
        truth_key = "real_gdp.2027q1",
    )
end

@testset "synthetic success derives registry seed and appends" begin
    sample = sample_fixture()
    seed_calls = Ref(0)
    seed_deriver = function (master_seed; kwargs...)
        seed_calls[] += 1
        return USForecastRegistry.derive_seed_record(
            master_seed;
            kwargs...,
        )
    end
    kwargs = adapter_kwargs(sample; seed_deriver)
    result = run_benchmark_origin(
        NoChangeSpec(),
        sample;
        kwargs...,
    )

    @test seed_calls[] == 1
    @test result.benchmark_run.status == :ok
    @test length(result.forecast_records) == 4
    @test result.context.origin_data_sample_sha256 ==
        kwargs.authenticated_origin_data.receipt.sample_sha256
    @test result.context.origin_data_receipt_sha256 ==
        kwargs.authenticated_origin_data.receipt.receipt_sha256
    @test result.context.origin_data_sample_sha256 ==
        "d23eb0effe609199c181a8b543495a146d7ae97ff6fcf370c6be02da677565ae"
    @test result.context.origin_data_receipt_sha256 ==
        "80e9d7f3f11156a50feec4da9a69e7abdef756352f42014afb26dd0ac9bf63c5"
    @test result.seed_record.seed ==
        USForecastRegistry.derive_seed(
        MASTER_SEED;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = ORIGIN_HASH,
        model_id = "naive_no_change",
        path_id = PATH_ID,
        purpose = "forecast",
    )
    @test result.seed_record.namespace["purpose"] == "forecast"
    @test all(
        record -> record["seed"] == result.seed_record.seed,
        result.forecast_records,
    )
    @test all(
        record -> record["seed_key_sha256"] ==
            result.seed_record.seed_key_sha256,
        result.forecast_records,
    )
    @test all(
        record -> record["origin_manifest_sha256"] == ORIGIN_HASH,
        result.forecast_records,
    )
    @test all(
        record -> record["origin_data_sample_sha256"] ==
            result.context.origin_data_sample_sha256,
        result.forecast_records,
    )
    @test all(
        record -> record["origin_data_receipt_sha256"] ==
            result.context.origin_data_receipt_sha256,
        result.forecast_records,
    )
    @test all(
        record -> record["model_manifest_sha256"] ==
            MODEL_MANIFEST_HASH,
        result.forecast_records,
    )
    @test all(
        record -> record["model_card_sha256"] == MODEL_CARD_HASH,
        result.forecast_records,
    )
    @test result.seed_record.namespace["model_id"] ==
        model_fixture().model_id
    @test all(
        record -> record["status"] == "success",
        result.forecast_records,
    )
    @test all(
        record -> record["n_draws"] == 0 &&
            record["distribution_artifact_sha256"] === nothing,
        result.forecast_records,
    )

    gdp_h1 = only(
        record
            for record in result.forecast_records
            if record["target_id"] == "real_gdp" &&
            record["horizon"] == 1
    )
    pce_h4 = only(
        record
            for record in result.forecast_records
            if record["target_id"] == "pce_price_index" &&
            record["horizon"] == 4
    )
    @test gdp_h1["point_forecast"] == 3.5
    @test pce_h4["point_forecast"] == 12.5

    registry = appendable_registry(result.forecast_records)
    @test length(registry.envelopes) == 4
    @test length(registry.verified.forecasts) == 4
end

@testset "validated model and target registry handoff" begin
    resolved = resolved_no_change_registration()
    model = resolved.metadata
    sample = full_panel_sample(model)
    cells = full_panel_cells(sample, model)
    kwargs = adapter_kwargs(sample; model, cells)
    result = run_benchmark_origin(
        NoChangeSpec(),
        sample;
        kwargs...,
    )

    @test model.registry_content_sha256 ==
        resolved.registry["registry_content_sha256"]
    @test model.target_contract_sha256 ==
        resolved.inventory["artifact"]["content_sha256"]
    @test model.target_panel_id ==
        "tier1_quarterly_primary_transformations_v1"
    @test length(model.targets) == 8
    @test [target.target_id for target in model.targets] ==
        sample.target_names
    @test !model.empirical_forecast_execution_allowed
    @test !model.production_scoring_allowed
    @test result.benchmark_run.status == :ok
    @test length(result.forecast_records) == 16
    @test Set(
        record["target_id"] for record in result.forecast_records
    ) == Set(target.target_id for target in model.targets)
    @test Set(
        record["horizon"] for record in result.forecast_records
    ) == Set([1, 4])

    registry = appendable_registry(result.forecast_records)
    @test length(registry.verified.forecasts) == 16
end

@testset "density artifact seam and structured benchmark failure" begin
    sample = sample_fixture()
    provider_calls = Ref(0)
    provider = function (forecast)
        provider_calls[] += 1
        @test size(forecast.draws) == (4, 2, 7)
        return DISTRIBUTION_HASH
    end
    density_kwargs = adapter_kwargs(
        sample;
        n_draws = 7,
        distribution_hash_provider = provider,
    )
    density = run_benchmark_origin(
        NoChangeSpec(),
        sample;
        density_kwargs...,
    )
    @test provider_calls[] == 1
    @test all(
        record -> record["n_draws"] == 7,
        density.forecast_records,
    )
    @test all(
        record -> record["distribution_artifact_sha256"] ==
            DISTRIBUTION_HASH,
        density.forecast_records,
    )

    missing_provider_kwargs = adapter_kwargs(sample; n_draws = 2)
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        missing_provider_kwargs...,
    )

    spec = ARSpec(candidate_lags = 1:4)
    failed_model = model_fixture(model_id = model_id(spec))
    failure_provider = _ -> error(
        "distribution provider must not run after benchmark failure",
    )
    failed_kwargs = adapter_kwargs(
        sample;
        model = failed_model,
        n_draws = 7,
        distribution_hash_provider = failure_provider,
    )
    failed = run_benchmark_origin(spec, sample; failed_kwargs...)
    @test failed.benchmark_run.status == :failed
    @test length(failed.forecast_records) == 4
    @test all(
        record -> record["status"] == "failed",
        failed.forecast_records,
    )
    @test all(
        record -> record["point_forecast"] === nothing &&
            record["distribution_artifact_sha256"] === nothing &&
            record["n_draws"] == 0,
        failed.forecast_records,
    )
    @test all(
        record -> record["failure_code"] == "invalid_input",
        failed.forecast_records,
    )
    @test all(
        record -> record["origin_data_sample_sha256"] ==
            failed.context.origin_data_sample_sha256 &&
            record["origin_data_receipt_sha256"] ==
            failed.context.origin_data_receipt_sha256,
        failed.forecast_records,
    )
    failed_registry = appendable_registry(failed.forecast_records)
    @test length(failed_registry.verified.forecasts) == 4
end

@testset "precomputed BenchmarkRun mapping and tamper rejection" begin
    sample = sample_fixture()
    derived_seed = USForecastRegistry.derive_seed(
        MASTER_SEED;
        experiment_id = EXPERIMENT_ID,
        origin_manifest_sha256 = ORIGIN_HASH,
        model_id = "naive_no_change",
        path_id = PATH_ID,
        purpose = "forecast",
    )
    run = run_benchmark(
        NoChangeSpec(),
        sample;
        n_draws = 0,
        seed = derived_seed,
    )
    kwargs = adapter_kwargs(sample)
    map_kwargs = Base.structdiff(
        kwargs,
        (;
            benchmark_model_id = kwargs.benchmark_model_id,
            benchmark_runner = kwargs.benchmark_runner,
        ),
    )
    mapped = map_benchmark_run(run, sample; map_kwargs...)
    @test length(mapped.forecast_records) == 4
    @test mapped.benchmark_run === run
    @test mapped.context.origin_data_sample_sha256 ==
        map_kwargs.authenticated_origin_data.receipt.sample_sha256
    @test mapped.context.origin_data_receipt_sha256 ==
        map_kwargs.authenticated_origin_data.receipt.receipt_sha256

    wrong_seed_run = run_benchmark(
        NoChangeSpec(),
        sample;
        n_draws = 0,
        seed = derived_seed + 1,
    )
    @test_throws AdapterValidationError map_benchmark_run(
        wrong_seed_run,
        sample;
        map_kwargs...,
    )

    missing_receipt_kwargs = Base.structdiff(
        map_kwargs,
        (;
            authenticated_origin_data =
                map_kwargs.authenticated_origin_data,
        ),
    )
    @test_throws UndefKeywordError map_benchmark_run(
        run,
        sample;
        missing_receipt_kwargs...,
    )
end

@testset "receipt envelope, cross-bindings, and owned execution copy" begin
    sample = sample_fixture()
    envelope = authenticated_fixture(sample)
    base_kwargs = adapter_kwargs(
        sample;
        authenticated_origin_data = envelope,
    )
    missing_receipt_kwargs = Base.structdiff(
        base_kwargs,
        (;
            authenticated_origin_data =
                base_kwargs.authenticated_origin_data,
        ),
    )
    @test_throws UndefKeywordError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        missing_receipt_kwargs...,
    )

    runner_calls = Ref(0)
    guarded_runner = function (args...; kwargs...)
        runner_calls[] += 1
        return run_benchmark(args...; kwargs...)
    end
    spoof_kwargs = merge(
        base_kwargs,
        (;
            authenticated_origin_data = (
                sample = envelope.sample,
                receipt = envelope.receipt,
            ),
            benchmark_runner = guarded_runner,
        ),
    )
    spoof_message = adapter_error(
        () -> run_benchmark_origin(
            NoChangeSpec(),
            sample;
            spoof_kwargs...,
        ),
    )
    @test occursin(
        "must be an AuthenticatedOriginData",
        spoof_message,
    )
    @test runner_calls[] == 0

    tampered_snapshot = deepcopy(envelope)
    tampered_snapshot.sample.y_train[1, 1] =
        tampered_snapshot.sample.y_train[1, 1] + 0.25
    tampered_snapshot_kwargs = merge(
        base_kwargs,
        (;
            authenticated_origin_data = tampered_snapshot,
            benchmark_runner = guarded_runner,
        ),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        tampered_snapshot_kwargs...,
    )
    @test runner_calls[] == 0

    receipt = envelope.receipt
    tampered_receipt = OriginDataReceipt(
        schema_version = receipt.schema_version,
        canonicalization = receipt.canonicalization,
        digest_algorithm = receipt.digest_algorithm,
        evidence_class = receipt.evidence_class,
        empirical_execution_authorized =
            receipt.empirical_execution_authorized,
        origin_manifest_sha256 =
            receipt.origin_manifest_sha256,
        protocol_sha256 = receipt.protocol_sha256,
        model_registry_content_sha256 =
            receipt.model_registry_content_sha256,
        target_contract_sha256 =
            receipt.target_contract_sha256,
        target_panel_id = receipt.target_panel_id,
        source_artifacts = receipt.source_artifacts,
        sample_sha256 = receipt.sample_sha256,
        receipt_sha256 = repeat("6", 64),
    )
    tampered_seal = AuthenticatedOriginData(
        envelope.sample,
        tampered_receipt,
    )
    tampered_seal_kwargs = merge(
        base_kwargs,
        (;
            authenticated_origin_data = tampered_seal,
            benchmark_runner = guarded_runner,
        ),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        tampered_seal_kwargs...,
    )
    @test runner_calls[] == 0

    cross_binding_receipts = [
        (
            "origin_manifest_sha256",
            authenticated_fixture(
                sample;
                origin_manifest_sha256 = repeat("1", 64),
            ),
        ),
        (
            "protocol_sha256",
            authenticated_fixture(
                sample;
                protocol_sha256 = repeat("2", 64),
            ),
        ),
        (
            "model_registry_content_sha256",
            authenticated_fixture(
                sample;
                model_registry_content_sha256 = repeat("3", 64),
            ),
        ),
        (
            "target_contract_sha256",
            authenticated_fixture(
                sample;
                target_contract_sha256 = repeat("4", 64),
            ),
        ),
        (
            "target_panel_id",
            authenticated_fixture(
                sample;
                target_panel_id = "different-panel.v1",
            ),
        ),
    ]
    for (field, mismatched_envelope) in cross_binding_receipts
        mismatch_kwargs = merge(
            base_kwargs,
            (;
                authenticated_origin_data =
                    mismatched_envelope,
                benchmark_runner = guarded_runner,
            ),
        )
        message = adapter_error(
            () -> run_benchmark_origin(
                NoChangeSpec(),
                sample;
                mismatch_kwargs...,
            ),
        )
        @test occursin(field, message)
    end
    @test runner_calls[] == 0

    evidence_origin = origin_fixture(
        evidence_class = "vintage_clean_candidate",
    )
    evidence_kwargs = adapter_kwargs(
        sample;
        origin = evidence_origin,
        authenticated_origin_data = envelope,
    )
    evidence_kwargs = merge(
        evidence_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    evidence_message = adapter_error(
        () -> run_benchmark_origin(
            NoChangeSpec(),
            sample;
            evidence_kwargs...,
        ),
    )
    @test occursin("evidence_class", evidence_message)
    @test runner_calls[] == 0

    original = sample_fixture()
    original_envelope = authenticated_fixture(original)
    original.y_train[1, 1] += 1.0
    changed_input_kwargs = adapter_kwargs(
        original;
        authenticated_origin_data = original_envelope,
    )
    changed_input_kwargs = merge(
        changed_input_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        original;
        changed_input_kwargs...,
    )
    @test runner_calls[] == 0

    caller_sample = sample_fixture()
    caller_before = copy(caller_sample.y_train)
    caller_envelope = authenticated_fixture(caller_sample)
    mutating_runner_calls = Ref(0)
    mutating_runner = function (spec, owned_sample; kwargs...)
        mutating_runner_calls[] += 1
        @test owned_sample !== caller_sample
        owned_sample.y_train[1, 1] += 10.0
        return run_benchmark(spec, owned_sample; kwargs...)
    end
    mutation_kwargs = adapter_kwargs(
        caller_sample;
        authenticated_origin_data = caller_envelope,
    )
    mutation_kwargs = merge(
        mutation_kwargs,
        (; benchmark_runner = mutating_runner),
    )
    mutation_message = adapter_error(
        () -> run_benchmark_origin(
            NoChangeSpec(),
            caller_sample;
            mutation_kwargs...,
        ),
    )
    @test occursin("benchmark_runner.sample", mutation_message)
    @test mutating_runner_calls[] == 1
    @test caller_sample.y_train == caller_before
end

@testset "all unsafe or incomplete contexts fail before execution" begin
    sample = sample_fixture()
    runner_calls = Ref(0)
    guarded_runner = function (args...; kwargs...)
        runner_calls[] += 1
        return run_benchmark(args...; kwargs...)
    end

    wrong_model_kwargs = adapter_kwargs(
        sample;
        model = model_fixture(model_id = "naive_drift"),
    )
    wrong_model_kwargs = merge(
        wrong_model_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        wrong_model_kwargs...,
    )
    @test runner_calls[] == 0

    empirical_origin_kwargs = adapter_kwargs(
        sample;
        origin = origin_fixture(
            evidence_class = "vintage_clean_candidate",
        ),
    )
    empirical_origin_kwargs = merge(
        empirical_origin_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        empirical_origin_kwargs...,
    )
    @test runner_calls[] == 0

    wrong_track_model_kwargs = adapter_kwargs(
        sample;
        model = model_fixture(
            information_track = "published_forecast",
        ),
    )
    wrong_track_model_kwargs = merge(
        wrong_track_model_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        wrong_track_model_kwargs...,
    )
    @test runner_calls[] == 0

    incomplete_panel_kwargs = adapter_kwargs(
        sample;
        model = model_fixture(
            targets = registered_targets_fixture()[1:1],
        ),
    )
    incomplete_panel_kwargs = merge(
        incomplete_panel_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        incomplete_panel_kwargs...,
    )
    @test runner_calls[] == 0

    missing_cell_kwargs = adapter_kwargs(
        sample;
        cells = cells_fixture(sample)[1:3],
    )
    missing_cell_kwargs = merge(
        missing_cell_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        missing_cell_kwargs...,
    )
    @test runner_calls[] == 0

    duplicate_target_cells = cells_fixture(sample)
    pce_indices = findall(
        cell -> cell.target_name == "pce_price_index",
        duplicate_target_cells,
    )
    for index in pce_indices
        cell = duplicate_target_cells[index]
        duplicate_target_cells[index] = ForecastCell(
            forecast_id = cell.forecast_id,
            target_name = cell.target_name,
            target_id = "real_gdp",
            target_operator_version = cell.target_operator_version,
            transformation_version = cell.transformation_version,
            horizon = cell.horizon,
            output_index = cell.output_index,
            forecast_key = cell.forecast_key,
            target_period_start = cell.target_period_start,
            target_period_end = cell.target_period_end,
            truth_key = cell.truth_key,
        )
    end
    duplicate_target_kwargs = adapter_kwargs(
        sample;
        cells = duplicate_target_cells,
    )
    duplicate_target_kwargs = merge(
        duplicate_target_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        duplicate_target_kwargs...,
    )
    @test runner_calls[] == 0

    bad_cells = cells_fixture(sample)
    bad = bad_cells[1]
    bad_cells[1] = ForecastCell(
        forecast_id = bad.forecast_id,
        target_name = bad.target_name,
        target_id = bad.target_id,
        target_operator_version = bad.target_operator_version,
        transformation_version = bad.transformation_version,
        horizon = bad.horizon,
        output_index = bad.output_index,
        forecast_key = "2099Q4",
        target_period_start = bad.target_period_start,
        target_period_end = bad.target_period_end,
        truth_key = bad.truth_key,
    )
    bad_cell_kwargs = adapter_kwargs(sample; cells = bad_cells)
    bad_cell_kwargs = merge(
        bad_cell_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        bad_cell_kwargs...,
    )
    @test runner_calls[] == 0

    x_train = reshape(collect(1.0:6.0), :, 1)
    x_future = reshape(collect(7.0:10.0), :, 1)
    conditional_sample =
        sample_fixture(; x_train, x_future)
    future_kwargs = adapter_kwargs(
        conditional_sample;
        cells = cells_fixture(conditional_sample),
    )
    future_kwargs = merge(
        future_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    future_message = adapter_error(
        () -> run_benchmark_origin(
            NoChangeSpec(),
            conditional_sample;
            future_kwargs...,
        ),
    )
    @test occursin("unconditional product", future_message)
    @test runner_calls[] == 0

    wrong_origin_sample =
        sample_fixture(origin_id = "origin.other.synthetic")
    wrong_origin_kwargs = adapter_kwargs(
        wrong_origin_sample;
        cells = cells_fixture(wrong_origin_sample),
    )
    wrong_origin_kwargs = merge(
        wrong_origin_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        wrong_origin_sample;
        wrong_origin_kwargs...,
    )
    @test runner_calls[] == 0

    mismatched_track_kwargs = adapter_kwargs(
        sample;
        product =
            product_fixture(information_track = "published_forecast"),
    )
    mismatched_track_kwargs = merge(
        mismatched_track_kwargs,
        (; benchmark_runner = guarded_runner),
    )
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        mismatched_track_kwargs...,
    )
    @test runner_calls[] == 0
end

@testset "published_forecast is canonical and registration-bound" begin
    sample = sample_fixture()
    origin = origin_fixture(
        information_track = "published_forecast",
    )
    product =
        product_fixture(information_track = "published_forecast")
    runner_calls = Ref(0)
    guarded_runner = function (args...; kwargs...)
        runner_calls[] += 1
        return run_benchmark(args...; kwargs...)
    end
    kwargs = adapter_kwargs(sample; origin, product)
    kwargs = merge(kwargs, (; benchmark_runner = guarded_runner))
    @test origin.information_track == "published_forecast"
    @test product.information_track == "published_forecast"
    @test_throws AdapterValidationError run_benchmark_origin(
        NoChangeSpec(),
        sample;
        kwargs...,
    )
    @test runner_calls[] == 0
end
