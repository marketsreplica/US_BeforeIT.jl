#!/usr/bin/env julia

using CSV
using DataFrames
using Dates
using JSON
using Statistics
using Test

include(joinpath(@__DIR__, "calibrate_outlook.jl"))
using .USOutlookCalibration

function synthetic_truth(config)
    dates = USOutlookCalibration.contract_dates(config).truth_dates
    frame = DataFrame(period = string.(dates))
    for (index, specification) in
        enumerate(USOutlookCalibration.DASHBOARD_SERIES)
        base = specification.name == "annual_policy_rate" ? 0.04 :
            specification.name == "gdp_deflator" ? 1.2 :
            100.0 * index
        frame[!, Symbol(specification.name)] =
            base .* (1 .+ 0.01 .* collect(0:(length(dates) - 1)))
    end
    return frame
end

function synthetic_paths(truth, dates; n_sims = 4)
    selected = truth[in.(truth.period, Ref(dates)), :]
    sort!(selected, :period)
    return Dict(
        specification.name =>
            repeat(
                reshape(
                    Float64.(selected[!, Symbol(specification.name)]),
                    :,
                    1,
                ),
                1,
                n_sims,
            )
            for specification in USOutlookCalibration.DASHBOARD_SERIES
    )
end

@testset "US outlook frozen truth contract" begin
    config = USOutlookCalibration.load_contract()
    dates = USOutlookCalibration.contract_dates(config)
    @test dates.truth_dates ==
        [
        Date(2023, 12, 31),
        Date(2024, 3, 31),
        Date(2024, 6, 30),
        Date(2024, 9, 30),
        Date(2024, 12, 31),
        Date(2025, 3, 31),
        Date(2025, 6, 30),
        Date(2025, 9, 30),
        Date(2025, 12, 31),
        Date(2026, 3, 31),
        Date(2026, 6, 30),
    ]
    @test dates.origin_dates ==
        lastdayofquarter.(dates.target_dates .- Month(3))
    @test dates.training_dates ==
        dates.target_dates[1:7]
    @test dates.holdout_dates ==
        dates.target_dates[8:9]

    frame = synthetic_truth(config)
    mktempdir() do directory
        truth_path = joinpath(directory, "truth.csv")
        CSV.write(truth_path, frame)
        pinned = deepcopy(config)
        pinned["truth_sha256"] =
            USOutlookCalibration.file_sha256(truth_path)
        @test USOutlookCalibration.verify_truth_sha256(truth_path, pinned) ==
            pinned["truth_sha256"]
        parsed =
            USOutlookCalibration.read_scoring_truth(truth_path, config)
        @test parsed.period == dates.truth_dates
        @test all(
            name -> name in propertynames(parsed),
            Symbol.(entry.name for entry in USOutlookCalibration.DASHBOARD_SERIES),
        )

        legacy = select(frame, Not(:wages))
        legacy[!, :nominal_wages] = frame.wages
        CSV.write(truth_path, legacy)
        parsed_legacy =
            USOutlookCalibration.read_scoring_truth(truth_path, config)
        @test parsed_legacy.wages == frame.wages

        missing_metric = select(frame, Not(:real_imports))
        CSV.write(truth_path, missing_metric)
        @test_throws ErrorException USOutlookCalibration.read_scoring_truth(
            truth_path,
            config,
        )

        gap = frame[frame.period .!= "2025-06-30", :]
        CSV.write(truth_path, gap)
        @test_throws ErrorException USOutlookCalibration.read_scoring_truth(
            truth_path,
            config,
        )

        extra = vcat(frame, frame[end:end, :])
        extra[end, :period] = "2026-09-30"
        CSV.write(truth_path, extra)
        @test_throws ErrorException USOutlookCalibration.read_scoring_truth(
            truth_path,
            config,
        )

        duplicate = vcat(frame, frame[end:end, :])
        CSV.write(truth_path, duplicate)
        @test_throws ErrorException USOutlookCalibration.read_scoring_truth(
            truth_path,
            config,
        )

        invalid = copy(frame)
        invalid[4, :real_gdp] = 0.0
        CSV.write(truth_path, invalid)
        @test_throws ErrorException USOutlookCalibration.verify_truth_sha256(
            truth_path,
            pinned,
        )
        @test_throws ErrorException USOutlookCalibration.read_scoring_truth(
            truth_path,
            config,
        )
    end

    backtest_dates = [dates.measurement_anchor; dates.target_dates]
    labels = USOutlookCalibration.split_labels(backtest_dates, config)
    @test labels[1] == "released_anchor"
    @test count(==("coefficient_fitting"), labels) == 7
    @test count(==("excluded_from_coefficient_fitting"), labels) == 2
    @test_throws ErrorException USOutlookCalibration.split_labels(
        [Date(2023, 12, 31)],
        config,
    )
end

@testset "US outlook config and CLI agreement" begin
    config = USOutlookCalibration.load_contract()
    @test USOutlookCalibration.parse_quarter("2026-Q1") ==
        Date(2026, 3, 31)
    @test USOutlookCalibration.validate_contract(deepcopy(config)) isa
        AbstractDict

    wrong_artifact_class = deepcopy(config)
    wrong_artifact_class["artifact_class"] = "C"
    @test_throws ErrorException USOutlookCalibration.validate_contract(
        wrong_artifact_class,
    )

    leaks_into_raw_calibration = deepcopy(config)
    leaks_into_raw_calibration["eligible_for_raw_calibration"] = true
    @test_throws ErrorException USOutlookCalibration.validate_contract(
        leaks_into_raw_calibration,
    )

    raw_product_not_retained = deepcopy(config)
    raw_product_not_retained["raw_forecast_required_alongside"] = false
    @test_throws ErrorException USOutlookCalibration.validate_contract(
        raw_product_not_retained,
    )

    bad_date = deepcopy(config)
    bad_date["target_end"] = "2026Q3"
    @test_throws ErrorException USOutlookCalibration.validate_contract(bad_date)

    bad_bound = deepcopy(config)
    bad_bound["parameter_bounds"]["rho"]["lower"] = 0.69
    @test_throws ErrorException USOutlookCalibration.validate_contract(bad_bound)

    bad_parameter = deepcopy(config)
    bad_parameter["parameter_overrides"]["rho"] = 1.1
    @test_throws ErrorException USOutlookCalibration.validate_contract(bad_parameter)

    bad_corrections = deepcopy(config)
    delete!(bad_corrections["output_corrections"], "wages")
    @test_throws ErrorException USOutlookCalibration.validate_contract(
        bad_corrections,
    )

    fitted_parameters = USOutlookCalibration.configured_parameters(config)
    @test USOutlookCalibration.validate_fitted_parameters(
        fitted_parameters,
        fitted_parameters,
    )
    mismatched_parameters = deepcopy(fitted_parameters)
    mismatched_parameters["rho"] += 0.001
    @test_throws ErrorException USOutlookCalibration.validate_fitted_parameters(
        mismatched_parameters,
        fitted_parameters,
    )

    fitted_corrections =
        USOutlookCalibration.configured_output_corrections(config)
    @test USOutlookCalibration.validate_fitted_corrections(
        fitted_corrections,
        fitted_corrections,
    )
    mismatched_corrections = deepcopy(fitted_corrections)
    value = mismatched_corrections["wages"]
    mismatched_corrections["wages"] =
        merge(value, (; amplitude = value.amplitude + 0.001))
    @test_throws ErrorException USOutlookCalibration.validate_fitted_corrections(
        mismatched_corrections,
        fitted_corrections,
    )

    options = USOutlookCalibration.parse_arguments(
        [
            "--config",
            USOutlookCalibration.DEFAULT_CONFIG_PATH,
            "--n-sims",
            "128",
            "--seed",
            "17000",
            "--forecast-horizon",
            "15",
        ]
    )
    validated = USOutlookCalibration.validate_cli_options(options, config)
    @test validated.n_sims == 128
    @test validated.seed == 17_000
    @test validated.forecast_horizon == 15
    @test_throws ErrorException USOutlookCalibration.parse_arguments(["bogus"])
    @test_throws ErrorException USOutlookCalibration.parse_arguments(
        [
            "--unknown",
            "1",
        ]
    )
    @test_throws ErrorException USOutlookCalibration.parse_arguments(
        [
            "--seed",
        ]
    )
    @test_throws ErrorException USOutlookCalibration.parse_arguments(
        [
            "--seed",
            "--n-sims",
        ]
    )
    @test_throws ErrorException USOutlookCalibration.parse_arguments(
        [
            "--seed",
            "1",
            "--seed",
            "2",
        ]
    )
    @test_throws ErrorException USOutlookCalibration.validate_cli_options(
        Dict("n-sims" => "1"),
        config,
    )
    @test_throws ErrorException USOutlookCalibration.validate_cli_options(
        Dict("n-sims" => "127"),
        config,
    )
    @test_throws ErrorException USOutlookCalibration.validate_cli_options(
        Dict("seed" => "-1"),
        config,
    )
    @test_throws ErrorException USOutlookCalibration.validate_cli_options(
        Dict("forecast-horizon" => "201"),
        config,
    )
    @test_throws ErrorException USOutlookCalibration.parse_quarter("2024-03-31")
end

@testset "US outlook generic nine-series scoring gate" begin
    config = USOutlookCalibration.load_contract()
    contract = USOutlookCalibration.contract_dates(config)
    raw_truth = synthetic_truth(config)
    mktempdir() do directory
        truth_path = joinpath(directory, "truth.csv")
        CSV.write(truth_path, raw_truth)
        truth =
            USOutlookCalibration.read_scoring_truth(truth_path, config)
        dates = [contract.measurement_anchor; contract.target_dates]
        paths = synthetic_paths(truth, dates)
        uncalibrated = Dict(name => values .* 1.12 for (name, values) in paths)
        origin_periods = [
            USOutlookCalibration.quarter_label(contract.measurement_anchor);
            USOutlookCalibration.quarter_label.(contract.origin_dates)
        ]
        backtest = USOutlookCalibration.build_backtest_frame(
            truth,
            dates,
            origin_periods,
            paths,
            uncalibrated,
            config,
        )
        metrics = vcat(
            USOutlookCalibration.score_frame(backtest, "uncalibrated"),
            USOutlookCalibration.score_frame(backtest, "calibrated"),
        )
        @test nrow(metrics) == 2 * 3 * 9
        @test USOutlookCalibration.calibration_gate(metrics)
        @test all(
            metrics[
                metrics.model_stage .== "calibrated",
                :target_met,
            ],
        )
        @test backtest.actual_policy_rate_annual ==
            backtest.actual_annual_policy_rate
        @test backtest.forecast_policy_rate_annual_mean ==
            backtest.forecast_annual_policy_rate_mean
        for specification in USOutlookCalibration.DASHBOARD_SERIES
            name = specification.name
            actual = backtest[1, Symbol("actual_$name")]
            @test backtest[1, Symbol("forecast_$(name)_mean")] == actual
            @test backtest[1, Symbol("forecast_$(name)_p10")] == actual
            @test backtest[1, Symbol("forecast_$(name)_p90")] == actual
        end

        report = USOutlookCalibration.report_metrics_frame(metrics)
        @test nrow(report) == 9
        @test Set(report.metric) ==
            Set(entry.name for entry in USOutlookCalibration.DASHBOARD_SERIES)
        @test all(report.holdout_mape_pct .< 1.0e-10)
        @test all(report.origin_anchored_holdout_mape_pct .> 11.9)
        @test all(report.origin_anchored_holdout_max_ape_pct .> 11.9)

        parameter_values =
            USOutlookCalibration.configured_parameters(config)
        parameter_frame =
            USOutlookCalibration.calibrated_parameters_frame(
            parameter_values,
            parameter_values,
            USOutlookCalibration.configured_parameter_bounds(config),
        )
        configured_corrections =
            USOutlookCalibration.configured_output_corrections(config)
        correction_frame =
            USOutlookCalibration.output_corrections_frame(
            Dict(
                name => merge(
                        correction,
                        (; loss = 0.0, evaluations = 1),
                    )
                    for (name, correction) in configured_corrections
            ),
        )
        structural_path = joinpath(directory, "structural.jld2")
        calibration_path = joinpath(directory, "calibration.jld2")
        open(structural_path, "w") do io
            write(io, "structural")
        end
        open(calibration_path, "w") do io
            write(io, "calibration")
        end
        summary = USOutlookCalibration.result_dictionary(
            backtest,
            metrics,
            parameter_frame,
            correction_frame,
            0.0,
            6096,
            config,
            USOutlookCalibration.DEFAULT_CONFIG_PATH,
            truth_path,
            structural_path,
            structural_path,
            calibration_path,
            DataFrame(period = [contract.target_end]),
        )
        reproducibility = summary["reproducibility"]
        @test reproducibility["backtest_seed"] == 17_000
        @test reproducibility["backtest_horizon_quarters"] == 1
        @test reproducibility["forecast_seed"] == 67_000
        @test reproducibility["forecast_horizon_quarters"] == 15
        @test length(reproducibility["config_sha256"]) == 64
        @test length(reproducibility["forecast_baseline_sha256"]) == 64
        @test length(reproducibility["truth_sha256"]) == 64
        @test haskey(reproducibility, "code_revision")

        failing_paths = deepcopy(paths)
        failing_paths["real_imports"][end, :] .*= 1.2
        failing_backtest = USOutlookCalibration.build_backtest_frame(
            truth,
            dates,
            origin_periods,
            failing_paths,
            uncalibrated,
            config,
        )
        failing_metrics =
            USOutlookCalibration.score_frame(failing_backtest, "calibrated")
        @test !USOutlookCalibration.calibration_gate(failing_metrics)
        row = only(
            eachrow(
                failing_metrics[
                    (failing_metrics.metric .== "real_imports") .&
                        (
                        failing_metrics.sample .==
                            "excluded_from_coefficient_fitting"
                    ),
                    :,
                ],
            ),
        )
        @test row.max_ape_pct > 10
        @test !row.target_met
    end
end

@testset "US outlook observation corrections" begin
    raw =
        repeat(reshape(fill(100.0, 10), :, 1), 1, 4)
    amplitude = 0.3
    decay = 2.0
    factor = exp(amplitude * (1 - exp(-decay)))
    actual = fill(100.0 * factor, 10)
    actual[1] = 100.0
    correction = USOutlookCalibration.fit_one_step_log_bias(
        raw,
        actual,
        collect(2:8);
        decay,
        amplitude_bound = 0.75,
        regularization = 0.0,
    )
    adjusted =
        USOutlookCalibration.apply_one_step_log_bias(raw, correction)
    @test correction.amplitude ≈ amplitude atol = 1.0e-12
    @test adjusted[1, :] == raw[1, :]
    @test all(adjusted[2:end, :] .≈ actual[2])
    continued = USOutlookCalibration.apply_damped_log_bias(
        raw,
        correction;
        origin_horizon = 1,
    )
    @test continued[1, :] == raw[1, :]
    @test all(
        continued[2, :] .≈
            100 .* exp(amplitude * (exp(-decay) - exp(-2 * decay))),
    )
    @test_throws ErrorException USOutlookCalibration.fit_one_step_log_bias(
        raw,
        actual,
        [1, 2];
        decay,
        amplitude_bound = 0.75,
        regularization = 0.0,
    )
    @test_throws ErrorException USOutlookCalibration.fit_one_step_log_bias(
        raw,
        actual,
        Int[];
        decay,
        amplitude_bound = 0.75,
        regularization = 0.0,
    )

    trending =
        repeat(reshape([100.0, 98.0, 97.0, 96.0, 95.0, 94.0], :, 1), 1, 4)
    damped_amplitude = 0.3
    damped_decay = 0.4
    factors = [
        horizon == 0 ? 1.0 :
            exp(damped_amplitude * (1 - exp(-damped_decay * horizon)))
            for horizon in 0:5
    ]
    damped_actual = vec(mean(trending; dims = 2)) .* factors
    damped = USOutlookCalibration.fit_damped_log_bias(
        trending,
        damped_actual,
        collect(2:5),
    )
    @test damped.amplitude ≈ damped_amplitude atol = 0.01
    @test damped.decay ≈ damped_decay atol = 0.02

    rebased = USOutlookCalibration.rebase_levels(trending, 250.0)
    @test all(rebased[1, :] .== 250.0)
    @test rebased[2, 1] == 245.0
end

@testset "US outlook checked-in provenance is current" begin
    summary_path = joinpath(
        USOutlookCalibration.DEFAULT_OUTPUT_DIR,
        "calibration_summary.json",
    )
    summary = JSON.parsefile(summary_path)
    reproducibility = summary["reproducibility"]
    for (path_key, hash_key) in (
            ("config_path", "config_sha256"),
            ("truth_path", "truth_sha256"),
            (
                "structural_artifact_path",
                "structural_artifact_sha256",
            ),
            (
                "forecast_baseline_path",
                "forecast_baseline_sha256",
            ),
            (
                "calibration_artifact_path",
                "calibration_artifact_sha256",
            ),
        )
        path = joinpath(
            USOutlookCalibration.REPO_ROOT,
            reproducibility[path_key],
        )
        @test USOutlookCalibration.file_sha256(path) ==
            reproducibility[hash_key]
    end
    @test summary["evaluation_design"]["real_time_vintage_claim"] ===
        false
end
