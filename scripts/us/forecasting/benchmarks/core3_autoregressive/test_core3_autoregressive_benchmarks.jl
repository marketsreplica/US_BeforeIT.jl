using LinearAlgebra
using SHA
using Test

include("USCore3AutoregressiveBenchmarks.jl")
using .USCore3AutoregressiveBenchmarks

const Core3 = USCore3AutoregressiveBenchmarks

struct UnsupportedCore3Spec <: AbstractCore3Spec end

function quarter_from_ordinal(ordinal)
    year, offset = divrem(ordinal, 4)
    return "$(lpad(string(year), 4, '0'))Q$(offset + 1)"
end

function quarter_sequence(first_quarter, count)
    start = Core3._quarter_ordinal(first_quarter, "test quarter")
    return [quarter_from_ordinal(start + offset) for offset in 0:(count - 1)]
end

function synthetic_training(rows = 80)
    values = Matrix{Float64}(undef, rows, 3)
    values[1, :] .= (1.0, 2.0, 3.0)
    for time in 2:rows
        shock1 = 0.22 * sin(0.71 * time) + 0.06 * cos(0.037 * time^2)
        shock2 = 0.18 * cos(0.43 * time) + 0.04 * sin(0.071 * time^2)
        shock3 = 0.12 * sin(0.29 * time) + 0.08 * cos(0.53 * time)
        lag = @view values[time - 1, :]
        values[time, 1] = 0.35 + 0.42 * lag[1] + 0.08 * lag[2] + shock1
        values[time, 2] = 0.25 + 0.05 * lag[1] + 0.51 * lag[2] + shock2
        values[time, 3] = 0.15 + 0.07 * lag[1] - 0.04 * lag[2] +
            0.61 * lag[3] + shock3
    end
    return values
end

function synthetic_sample(; rows = 80, horizon = 12, values = synthetic_training(rows))
    all_periods = quarter_sequence("1980Q1", rows + horizon)
    return synthetic_core3_sample(
        origin_id = "synthetic-core3-$(all_periods[rows])",
        origin_key = all_periods[rows],
        training_keys = all_periods[1:rows],
        forecast_keys = all_periods[(rows + 1):end],
        y_train = values,
    )
end

function sha256_file(path)
    return bytes2hex(SHA.sha256(read(path)))
end

function clone_forecast(
        forecast;
        sample_sha256 = forecast.sample_sha256,
        point = copy(forecast.point),
        draws = copy(forecast.draws),
        diagnostics = deepcopy(forecast.diagnostics),
        origin_bound = forecast.origin_bound,
        origin_admissible = forecast.origin_admissible,
        scoring_eligible = forecast.scoring_eligible,
        empirical_accuracy_evidence = forecast.empirical_accuracy_evidence,
        forecast_suitability_evidence = forecast.forecast_suitability_evidence,
        promotion_eligible = forecast.promotion_eligible,
        production_eligible = forecast.production_eligible,
        registered_benchmark = forecast.registered_benchmark,
        content_sha256 = forecast.content_sha256,
    )
    return Core3Forecast(
        forecast.schema_version,
        forecast.contract_id,
        forecast.status,
        forecast.canonicalization,
        forecast.target_panel_id,
        forecast.model_id,
        forecast.model_contract_sha256,
        sample_sha256,
        forecast.information_track,
        forecast.origin_id,
        forecast.origin_key,
        copy(forecast.training_keys),
        copy(forecast.forecast_keys),
        copy(forecast.target_names),
        copy(forecast.target_units),
        point,
        draws,
        diagnostics,
        copy(forecast.blockers),
        origin_bound,
        origin_admissible,
        scoring_eligible,
        empirical_accuracy_evidence,
        forecast_suitability_evidence,
        promotion_eligible,
        production_eligible,
        registered_benchmark,
        content_sha256,
    )
end

function clone_sample(
        sample;
        origin_id = sample.origin_id,
        origin_key = sample.origin_key,
        training_keys = copy(sample.training_keys),
        forecast_keys = copy(sample.forecast_keys),
        y_train = copy(sample.y_train),
    )
    return Core3Sample(
        sample.schema_version,
        origin_id,
        origin_key,
        training_keys,
        forecast_keys,
        y_train,
        copy(sample.target_names),
        copy(sample.target_units),
        sample.target_panel_id,
        sample.information_track,
        sample.source_manifest_sha256,
        sample.source_panel_sha256,
        sample.source_receipts_sha256,
        sample.source_core3_values_sha256,
        sample.origin_receipt_sha256,
        sample.origin_bound,
    )
end

function restamp(forecast)
    unstamped = clone_forecast(forecast; content_sha256 = repeat("0", 64))
    digest = canonical_sha256(Core3._forecast_payload(unstamped))
    return clone_forecast(unstamped; content_sha256 = digest)
end

@testset "closed target and model contracts" begin
    @test TARGET_PANEL_ID == "quarterly_nk3_aggregate_pce_contract_v1"
    @test TARGET_NAMES == (
        "real_gdp_growth",
        "pce_inflation",
        "effective_federal_funds_rate",
    )
    @test TARGET_UNITS == (
        "annualized_quarter_over_quarter_percent",
        "annualized_quarter_over_quarter_percent",
        "quarterly_average_percent",
    )
    @test STATUS == "CORE3_AUTOREGRESSIVE_MECHANICS_VALIDATED_NONADMITTING"
    specs = default_core3_specs()
    @test typeof.(specs) == [Core3AR1Spec, Core3VAR1Spec, Core3BVAR1Spec]
    @test model_id.(specs) == [
        "nk3_aggregate_pce_univariate_ar1_ols_v1",
        "nk3_aggregate_pce_var1_ols_v1",
        "nk3_aggregate_pce_bvar1_mniw_stationary_v1",
    ]
    @test model_contract_sha256.(specs) == [
        "0d33cbebb614794097f31f215fe8dd628a85120c0a198d429216bc37af771842",
        "2860c9e0fe1e76e72e365cca1a93559d5adfb1b95755d27b3256ef48c987fc5c",
        "32c9c0c6409f521ba2e919b7bc2b36bc8a47e5217c5aedc6b0bbe019b6470fd6",
    ]
    for spec in specs
        contract = model_contract(spec)
        @test contract["target_names"] == collect(TARGET_NAMES)
        @test contract["target_units"] == collect(TARGET_UNITS)
        @test contract["lags"] == 1
        @test contract["intercept"] === true
        @test contract["predictive_rng_semantics"] ==
            "sha256_domain_separated_mersenne_twister_per_path"
        for key in (
                "origin_admissible",
                "scoring_eligible",
                "empirical_accuracy_evidence",
                "forecast_suitability_evidence",
                "promotion_eligible",
                "production_eligible",
                "registered_benchmark",
            )
            @test contract[key] === false
        end
    end
    bvar_contract = model_contract(Core3BVAR1Spec())
    @test bvar_contract["prior_family"] == "matrix_normal_inverse_wishart"
    @test bvar_contract["prior_version"] == "core3_stationary_mniw_v1"
    @test bvar_contract["prior_hyperparameters"] == Dict{String, Any}(
        "tightness" => 0.2,
        "lag_decay" => 1.0,
        "own_lag_mean" => 0.0,
        "intercept_variance" => 100.0,
        "inverse_wishart_dof_offset" => 2,
        "innovation_scale" => 1.0,
        "training_scale_floor" => 1.0e-8,
        "training_scale_rule" =>
            "max(mean_squared_first_difference,training_scale_floor)",
    )
    @test bvar_contract["hyperparameter_selection"] == "none_fixed_before_origin"
    @test bvar_contract["stationarity_semantics"] ==
        "zero_own_lag_prior_center_for_stationary_transformed_observables"
    @test bvar_contract["stability_enforcement"] === false
    @test bvar_contract["unstable_draw_truncation"] === false

    unsupported = run_core3_benchmark(
        UnsupportedCore3Spec(),
        synthetic_sample(; horizon = 1),
    )
    @test unsupported.status == :failed
    @test unsupported.model_id == "unsupported_core3_spec"
    @test unsupported.forecast === nothing
    @test unsupported.failure.code == :unknown_model
end

@testset "strict sample schema, order, and leakage boundary" begin
    values = synthetic_training()
    periods = quarter_sequence("1980Q1", 92)
    training_keys = periods[1:80]
    forecast_keys = periods[81:92]
    sample = synthetic_core3_sample(
        origin_id = "synthetic-contract-test",
        origin_key = training_keys[end],
        training_keys = training_keys,
        forecast_keys = forecast_keys,
        y_train = values,
    )
    original_value = sample.y_train[1, 1]
    original_key = sample.training_keys[1]
    values[1, 1] = 9999.0
    training_keys[1] = "1900Q1"
    @test sample.y_train[1, 1] == original_value
    @test sample.training_keys[1] == original_key
    @test size(sample.y_train) == (80, 3)
    @test sample.origin_key == "1999Q4"
    @test sample.forecast_keys == quarter_sequence("2000Q1", 12)
    @test sample.target_names == collect(TARGET_NAMES)
    @test sample.target_units == collect(TARGET_UNITS)
    @test sample.origin_receipt_sha256 === nothing
    @test sample.origin_bound === false
    @test occursin(r"^[0-9a-f]{64}$", sample_sha256(sample))
    @test !(:future_targets in fieldnames(Core3Sample))
    @test !(:x_train in fieldnames(Core3Sample))
    @test !(:x_future in fieldnames(Core3Sample))

    base_arguments = (
        origin_id = "synthetic-invalid",
        origin_key = "1999Q4",
        training_keys = quarter_sequence("1980Q1", 80),
        forecast_keys = quarter_sequence("2000Q1", 4),
        y_train = synthetic_training(),
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        schema_version = "other",
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        target_panel_id = "tier1_quarterly_primary_transformations_v1",
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        target_names = reverse(collect(TARGET_NAMES)),
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        target_names = Symbol.(TARGET_NAMES),
    )
    wrong_units = collect(TARGET_UNITS)
    wrong_units[3] = "annualized_percent"
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        target_units = wrong_units,
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        future_targets = zeros(4, 3),
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        x_train = ones(80, 1),
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        x_future = ones(4, 1),
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        y_train = ones(80, 4),
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        y_train = ones(59, 3),
        training_keys = quarter_sequence("1985Q2", 59),
        origin_key = "1999Q4",
    )
    nonfinite = synthetic_training()
    nonfinite[4, 2] = Inf
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        y_train = nonfinite,
    )
    booleans = fill(true, 80, 3)
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        y_train = booleans,
    )
    gapped = quarter_sequence("1980Q1", 80)
    gapped[40] = "1990Q2"
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        training_keys = gapped,
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        origin_key = "1999Q3",
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        forecast_keys = quarter_sequence("2000Q2", 4),
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        forecast_keys = quarter_sequence("2000Q1", 13),
    )
    @test_throws Core3BenchmarkError synthetic_core3_sample(;
        base_arguments...,
        forecast_keys = ["2000Q1", "2000 Q2"],
    )
end

@testset "pinned revised-panel mapping is nonadmitting and origin-bounded" begin
    panel = load_revised_core3_panel()
    @test length(panel.periods) == 101
    @test size(panel.values) == (101, 3)
    @test first(panel.periods) == "2000Q3"
    @test last(panel.periods) == "2025Q3"
    @test panel.manifest_sha256 ==
        "fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f"
    @test panel.panel_sha256 ==
        "f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe"
    @test panel.source_receipts_sha256 ==
        "14bab08bb573265e0affc878cedbbb8d4a0f8f5510fc59990f92d614f109d488"
    @test panel.core3_values_sha256 ==
        "905875dbbf7dea22850776d94ee9a1c4ec7d92fc96c6ba3608d00d83a1e9a477"
    @test panel.values[1, :] ≈ [
        0.407522681487,
        2.568940474165,
        6.511428571429,
    ] atol = 0.0 rtol = 0.0

    sample = revised_core3_sample(panel, 80; horizon = 12)
    @test sample.information_track == "revised_mixed_vintage_diagnostic"
    @test length(sample.training_keys) == 80
    @test size(sample.y_train) == (80, 3)
    @test sample.origin_key == panel.periods[80]
    @test sample.forecast_keys == panel.periods[81:92]
    @test sample.y_train == panel.values[1:80, :]
    @test sample.source_core3_values_sha256 == panel.core3_values_sha256
    @test sample.origin_receipt_sha256 === nothing
    @test sample.origin_bound === false
    @test_throws Core3BenchmarkError revised_core3_sample(
        panel,
        80;
        horizon = 12,
        future_targets = panel.values[81:92, :],
    )
    @test_throws Core3BenchmarkError revised_core3_sample(
        panel,
        59;
        horizon = 1,
    )
    @test_throws Core3BenchmarkError revised_core3_sample(
        panel,
        100;
        horizon = 2,
    )

    baseline = run_core3_family(sample; n_draws = 2, seed = 71)
    panel.values[81:end, :] .+= 10_000.0
    replay = run_core3_family(sample; n_draws = 2, seed = 71)
    @test [run.forecast.content_sha256 for run in baseline] ==
        [run.forecast.content_sha256 for run in replay]
    @test_throws Core3BenchmarkError revised_core3_sample(
        panel,
        80;
        horizon = 12,
    )
end

@testset "revised samples rebind independently before model execution" begin
    panel = load_revised_core3_panel()
    sample = revised_core3_sample(panel, 80; horizon = 12)

    altered_values = copy(sample.y_train)
    altered_values[17, 2] += 123.0
    altered = clone_sample(sample; y_train = altered_values)
    attacker_digest = canonical_sha256(Core3._sample_payload(altered))
    @test occursin(r"^[0-9a-f]{64}$", attacker_digest)
    @test_throws Core3BenchmarkError sample_sha256(altered)
    altered_run = run_core3_benchmark(
        Core3AR1Spec(),
        altered;
        n_draws = 1,
        seed = 19,
    )
    @test altered_run.status == :failed
    @test altered_run.failure.code == :revised_sample_binding_mismatch
    @test altered_run.forecast === nothing

    unrelated_keys = quarter_sequence("1980Q1", 92)
    unrelated = clone_sample(
        sample;
        origin_id = "revised-core3-diagnostic-1999Q4",
        origin_key = "1999Q4",
        training_keys = unrelated_keys[1:80],
        forecast_keys = unrelated_keys[81:92],
        y_train = synthetic_training(80),
    )
    @test unrelated.source_manifest_sha256 == sample.source_manifest_sha256
    @test unrelated.source_panel_sha256 == sample.source_panel_sha256
    @test unrelated.source_receipts_sha256 == sample.source_receipts_sha256
    @test unrelated.source_core3_values_sha256 ==
        sample.source_core3_values_sha256
    unrelated_run = run_core3_benchmark(
        Core3VAR1Spec(),
        unrelated;
        n_draws = 1,
        seed = 23,
    )
    @test unrelated_run.status == :failed
    @test unrelated_run.failure.code == :revised_sample_binding_mismatch
    @test unrelated_run.forecast === nothing

    baseline = run_core3_benchmark(
        Core3AR1Spec(),
        sample;
        n_draws = 1,
        seed = 29,
    )
    @test baseline.status == :ok
    forged_forecast = restamp(
        clone_forecast(
            something(baseline.forecast);
            sample_sha256 = attacker_digest,
        ),
    )
    validation_error = try
        validate_forecast(forged_forecast, Core3AR1Spec(), altered)
        nothing
    catch error
        error
    end
    @test validation_error isa Core3BenchmarkError
    @test validation_error.code == :revised_sample_binding_mismatch
end

@testset "common sample, structured output, and all gates false" begin
    sample = synthetic_sample()
    runs = run_core3_family(sample; n_draws = 24, seed = 31415)
    @test length(runs) == 3
    @test all(run -> run.status == :ok, runs)
    @test all(run -> run.failure === nothing, runs)
    @test length(unique(run.forecast.sample_sha256 for run in runs)) == 1
    @test only(unique(run.forecast.sample_sha256 for run in runs)) ==
        sample_sha256(sample)
    for run in runs
        forecast = something(run.forecast)
        @test forecast.model_id == run.model_id
        @test forecast.target_names == collect(TARGET_NAMES)
        @test forecast.target_units == collect(TARGET_UNITS)
        @test forecast.training_keys == sample.training_keys
        @test forecast.forecast_keys == sample.forecast_keys
        @test size(forecast.point) == (12, 3)
        @test size(forecast.draws) == (12, 3, 24)
        @test all(isfinite, forecast.point)
        @test all(isfinite, forecast.draws)
        @test forecast.diagnostics["training_rows"] == 80
        @test forecast.diagnostics["training_response_rows"] == 79
        @test forecast.diagnostics["future_targets_available_to_model"] === false
        @test forecast.diagnostics["exogenous_inputs_available_to_model"] === false
        @test forecast.diagnostics["point_forecast_depends_on_draw_count"] === false
        @test forecast.origin_bound === false
        @test forecast.origin_admissible === false
        @test forecast.scoring_eligible === false
        @test forecast.empirical_accuracy_evidence === false
        @test forecast.forecast_suitability_evidence === false
        @test forecast.promotion_eligible === false
        @test forecast.production_eligible === false
        @test forecast.registered_benchmark === false
        @test "AUTHENTICATED_ORIGIN_RECEIPT_NOT_BOUND" in forecast.blockers
        @test "SCORING_AND_ACCURACY_GATES_FALSE" in forecast.blockers
        @test validate_forecast(forecast, default_core3_specs()[findfirst(==(run.model_id), model_id.(default_core3_specs()))], sample) === forecast
    end
    bvar = something(runs[3].forecast)
    @test bvar.diagnostics["prior_own_lag_mean"] == 0.0
    @test bvar.diagnostics["prior_tightness"] == 0.2
    @test bvar.diagnostics["coefficient_uncertainty_in_draws"] === true
    @test bvar.diagnostics["covariance_uncertainty_in_draws"] === true
    @test bvar.diagnostics["stability_enforced"] === false
    @test bvar.diagnostics["unstable_draws_truncated"] === false
    @test bvar.diagnostics["posterior_inverse_wishart_dof"] == 84
    @test isposdef(Symmetric(bvar.diagnostics["posterior_inverse_wishart_scale"]))
    @test isposdef(Symmetric(bvar.diagnostics["posterior_row_covariance"]))
end

@testset "seed reproducibility and coherent recursive horizons" begin
    long_sample = synthetic_sample(; horizon = 12)
    short_sample = synthetic_sample(; horizon = 4)
    for spec in default_core3_specs()
        point_only = run_core3_benchmark(spec, long_sample; n_draws = 0, seed = 0)
        simulated = run_core3_benchmark(spec, long_sample; n_draws = 8, seed = 99)
        repeated = run_core3_benchmark(spec, long_sample; n_draws = 8, seed = 99)
        changed_seed = run_core3_benchmark(spec, long_sample; n_draws = 8, seed = 100)
        short = run_core3_benchmark(spec, short_sample; n_draws = 1, seed = 7)
        long = run_core3_benchmark(spec, long_sample; n_draws = 1, seed = 7)
        short_many =
            run_core3_benchmark(spec, short_sample; n_draws = 5, seed = 27)
        long_many =
            run_core3_benchmark(spec, long_sample; n_draws = 5, seed = 27)
        few_paths =
            run_core3_benchmark(spec, long_sample; n_draws = 3, seed = 41)
        many_paths =
            run_core3_benchmark(spec, long_sample; n_draws = 8, seed = 41)
        @test all(
            run -> run.status == :ok,
            (
                point_only,
                simulated,
                repeated,
                changed_seed,
                short,
                long,
                short_many,
                long_many,
                few_paths,
                many_paths,
            ),
        )
        @test point_only.forecast.point == simulated.forecast.point
        @test simulated.forecast.point == repeated.forecast.point
        @test simulated.forecast.draws == repeated.forecast.draws
        @test simulated.forecast.draws != changed_seed.forecast.draws
        @test size(point_only.forecast.draws) == (12, 3, 0)
        @test short.forecast.point == long.forecast.point[1:4, :]
        @test short.forecast.draws == long.forecast.draws[1:4, :, :]
        @test short_many.forecast.draws == long_many.forecast.draws[1:4, :, :]
        @test few_paths.forecast.draws == many_paths.forecast.draws[:, :, 1:3]

        coefficients = if spec isa Core3AR1Spec
            simulated.forecast.diagnostics[
                "coefficient_matrix_intercept_then_own_lag",
            ]
        elseif spec isa Core3VAR1Spec
            simulated.forecast.diagnostics[
                "coefficient_matrix_intercept_then_lag_block",
            ]
        else
            simulated.forecast.diagnostics["posterior_coefficient_mean"]
        end
        expected_second = if spec isa Core3AR1Spec
            coefficients[1, :] .+
                coefficients[2, :] .* simulated.forecast.point[1, :]
        else
            vec(coefficients' * [1.0; simulated.forecast.point[1, :]])
        end
        @test simulated.forecast.point[2, :] ≈ expected_second atol = 1.0e-14 rtol = 0.0
    end
end

@testset "rank and covariance singularities fail visibly" begin
    constant_sample = synthetic_sample(; values = ones(80, 3))
    for spec in default_core3_specs()
        run = run_core3_benchmark(spec, constant_sample; n_draws = 2, seed = 1)
        @test run.status == :failed
        @test run.forecast === nothing
        @test run.failure.code == :rank_deficient
        @test occursin("rank", run.failure.message)
    end

    rows = 80
    rank_one = Matrix{Float64}(undef, rows, 3)
    rank_one[1, :] .= (0.4, -0.2, 0.7)
    transition = Diagonal([0.25, 0.45, 0.65])
    loading = [1.0, 2.0, -1.5]
    constant = [0.1, 0.2, -0.1]
    for time in 2:rows
        innovation = sin(0.37 * time) + 0.2 * cos(0.11 * time^2)
        rank_one[time, :] .=
            constant + transition * rank_one[time - 1, :] +
            loading * innovation
    end
    covariance_sample = synthetic_sample(; values = rank_one)
    design, _ = Core3._lag1_design(covariance_sample.y_train)
    @test first(Core3._numerical_rank(design)) == 4
    var_run = run_core3_benchmark(
        Core3VAR1Spec(),
        covariance_sample;
        n_draws = 1,
        seed = 1,
    )
    @test var_run.status == :failed
    @test var_run.failure.code == :singular_covariance
    @test occursin("positive definite", var_run.failure.message)
    bvar_run = run_core3_benchmark(
        Core3BVAR1Spec(),
        covariance_sample;
        n_draws = 1,
        seed = 1,
    )
    @test bvar_run.status == :ok
    @test isposdef(
        Symmetric(
            bvar_run.forecast.diagnostics[
                "posterior_mean_innovation_covariance",
            ],
        ),
    )
end

@testset "evidence-bound replay and gate elevation fail" begin
    sample = synthetic_sample(; horizon = 4)
    spec = Core3VAR1Spec()
    run = run_core3_benchmark(spec, sample; n_draws = 3, seed = 88)
    @test run.status == :ok
    forecast = run.forecast

    changed_point = copy(forecast.point)
    changed_point[1, 1] += 1.0
    changed = clone_forecast(forecast; point = changed_point)
    @test_throws Core3BenchmarkError validate_forecast(changed, spec, sample)
    rehashed = restamp(changed)
    replay_error = try
        validate_forecast(rehashed, spec, sample)
        nothing
    catch error
        error
    end
    @test replay_error isa Core3BenchmarkError
    @test replay_error.code == :replay_mismatch

    elevated = restamp(clone_forecast(forecast; scoring_eligible = true))
    gate_error = try
        validate_forecast(elevated, spec, sample)
        nothing
    catch error
        error
    end
    @test gate_error isa Core3BenchmarkError
    @test gate_error.code == :gate_elevation

    changed_training = deepcopy(sample)
    changed_training.y_train[1, 1] += 0.5
    @test_throws Core3BenchmarkError validate_forecast(
        forecast,
        spec,
        changed_training,
    )
end

@testset "existing registries remain untouched and candidate has no scoring path" begin
    repository_root = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
    registry_path = joinpath(
        repository_root,
        "scripts",
        "us",
        "forecasting",
        "benchmarks",
        "benchmark_model_registry.toml",
    )
    registry_module_path = joinpath(
        repository_root,
        "scripts",
        "us",
        "forecasting",
        "benchmarks",
        "USBenchmarkModelRegistry.jl",
    )
    @test sha256_file(registry_path) ==
        "4476504650da2f374b1719b41282c5cb2e55e7190be8e0c4c2e42801c2c72f28"
    @test sha256_file(registry_module_path) ==
        "d98322fdb60d4c8142296db5e4008db8c945699672a028a8626a038f979adcfb"
    registry_text = read(registry_path, String)
    for spec in default_core3_specs()
        @test !occursin(model_id(spec), registry_text)
    end
    @test !occursin(TARGET_PANEL_ID, registry_text)

    source = read(joinpath(@__DIR__, "USCore3AutoregressiveBenchmarks.jl"), String)
    for forbidden in (
            "Downloads",
            "HTTP.",
            "Sockets",
            "run(`",
            "mktemp",
            "Base.write",
            "open(",
            "rm(",
        )
        @test !occursin(forbidden, source)
    end
    exports = names(Core3)
    @test !(:score in exports)
    @test !(:admit_origin in exports)
    @test !(:promote in exports)
    @test !occursin("beforeit_var_p1", source)
end
