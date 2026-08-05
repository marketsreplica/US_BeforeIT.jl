using Test
using BeforeITWeb
using JSON3
using JLD2
using UUIDs
import BeforeIT as Bit

function run_fixture_path(
        dataset_id,
        scenario;
        horizon = 1,
        trace = Dict("profile" => "standard"),
    )
    tmp = mktempdir()
    run_dir = joinpath(tmp, "run")
    mkpath(run_dir)
    spec = Dict(
        "run_id" => "test",
        "dataset_id" => dataset_id,
        "scenario" => scenario,
        "created_at" => "test",
        "sim" => Dict(
            "T" => horizon,
            "n_sims" => 1,
            "step_multithreading" => false,
            "base_seed" => 1,
        ),
        "overrides" => Dict(
            "parameters" => Dict{String, Float64}(),
            "initial_conditions" => Dict{String, Float64}(),
        ),
        "shock" => Dict("type" => "none"),
        "trace" => trace,
    )
    open(joinpath(run_dir, "spec.json"), "w") do io
        write(io, JSON3.write(spec))
    end
    BeforeITWeb.run_worker(run_dir)
    return run_dir
end

function run_fixture(
        dataset_id,
        scenario;
        horizon = 1,
        trace = Dict("profile" => "standard"),
    )
    run_dir =
        run_fixture_path(dataset_id, scenario; horizon, trace)
    return JSON3.read(read(joinpath(run_dir, "summary.json"), String))
end

@testset "Current national datasets" begin
    datasets = BeforeITWeb.available_datasets()
    @test datasets[1]["id"] == "US2026Q1"
    @test datasets[2]["id"] == "US2024Q4"
    @test datasets[1]["period"] == "2026-Q1"
    @test datasets[1]["country"] == "US"
    @test datasets[1]["currency"] == "USD"
    @test datasets[1]["flow_units"] == "million_usd_per_quarter"
    @test datasets[1]["stock_units"] == "million_usd"
    @test datasets[1]["default_scenario"] == "unconditional"
    @test datasets[1]["scenarios"] == ["unconditional"]
    @test datasets[1]["validation_checklist"] ==
        "data/us/validation/DATA_CHECKLIST.md"
    @test datasets[1]["input_snapshot_count"] > 0

    austria_nowcast = only(
        dataset for dataset in datasets if
            dataset["id"] == "AUSTRIA2026Q1"
    )
    @test austria_nowcast["default_scenario"] == "baseline"
    @test Set(austria_nowcast["scenarios"]) ==
        Set(["baseline", "upside", "downside", "unconditional"])
    @test austria_nowcast["live_source_count"] > 0

    assumptions =
        BeforeITWeb.scenario_assumptions("AUSTRIA2026Q1", "baseline")
    @test length(assumptions) == 6
    @test first(assumptions).year == 2026
    @test last(assumptions).year == 2031
    @test isempty(
        BeforeITWeb.scenario_assumptions(
            "AUSTRIA2024Q4",
            "unconditional",
        ),
    )
    @test_throws BeforeITWeb.ApiError BeforeITWeb.scenario_assumptions(
        "AUSTRIA2024Q4",
        "baseline",
    )
    @test isempty(
        BeforeITWeb.scenario_assumptions("US2026Q1", "unconditional"),
    )
    @test_throws BeforeITWeb.ApiError BeforeITWeb.scenario_assumptions(
        "US2026Q1",
        "baseline",
    )
end

@testset "Overrides validation" begin
    ok_params, ok_inits = BeforeITWeb.validate_overrides(
        "AUSTRIA2026Q1",
        Dict("psi" => 0.9, "psi_H" => 0.1),
        Dict(),
    )
    @test ok_params["psi"] ≈ 0.9
    @test ok_params["psi_H"] ≈ 0.1

    @test_throws BeforeITWeb.ApiError BeforeITWeb.validate_overrides(
        "AUSTRIA2026Q1",
        Dict("psi" => 0.9, "psi_H" => 0.2),
        Dict(),
    )

    us_params, us_inits = BeforeITWeb.validate_overrides(
        "US2026Q1",
        Dict(),
        Dict(),
    )
    @test isempty(us_params)
    @test isempty(us_inits)
    us_unrelated, _ = BeforeITWeb.validate_overrides(
        "US2026Q1",
        Dict("tau_VAT" => 0.08),
        Dict(),
    )
    @test us_unrelated["tau_VAT"] ≈ 0.08
    us_valid_propensity, _ = BeforeITWeb.validate_overrides(
        "US2026Q1",
        Dict("psi" => 0.9),
        Dict(),
    )
    @test us_valid_propensity["psi"] ≈ 0.9
    @test_throws BeforeITWeb.ApiError BeforeITWeb.validate_overrides(
        "US2026Q1",
        Dict("psi" => 1.0),
        Dict(),
    )
end

@testset "JSON matrix layout" begin
    matrix = reshape(collect(1.0:6.0), 2, 3)
    encoded = JSON3.read(JSON3.write(BeforeITWeb._json_value(matrix)))

    @test length(encoded) == 2
    @test collect(encoded[1]) == [1.0, 3.0, 5.0]
    @test collect(encoded[2]) == [2.0, 4.0, 6.0]

    nonfinite = BeforeITWeb._json_value([1.0, NaN, Inf, -Inf])
    @test nonfinite == [1.0, nothing, nothing, nothing]
    @test_nowarn JSON3.write(nonfinite)
    @test BeforeITWeb._json_value(true) === true

    _, nowcast_inits =
        BeforeITWeb._dataset_by_id("AUSTRIA2026Q1")
    for key in ("C_G", "C_E", "Y_I")
        @test_nowarn JSON3.write(
            BeforeITWeb._json_value(nowcast_inits[key]),
        )
    end
end

@testset "Output measurement adapter" begin
    raw = Dict{String, Any}(
        "nominal_gdp" => [200.0 220.0; 210.0 230.0],
        "real_gdp" => [100.0 110.0; 105.0 115.0],
        "real_household_consumption" =>
            [40.0 42.0; 41.0 43.0],
        "real_fixed_capitalformation" =>
            [20.0 21.0; 22.0 23.0],
        "gdp_deflator" => [2.0 2.0; 2.0 2.0],
        "real_sector_gva" =>
            reshape(collect(1.0:8.0), 2, 2, 2),
    )
    measurement = Dict{String, Any}(
        "schema_version" => "beforeit-output-measurement.v1",
        "method" => "origin_level_times_model_growth",
        "origin_period" => "2026-Q1",
        "series" => Dict{String, Any}(
            "real_gdp" => Dict(
                "scale" => 2.0,
                "unit" => "published GDP units",
                "basis" => "chained dollars, SAAR",
                "source" => "test source",
            ),
            "real_household_consumption" => Dict(
                "scale" => 3.0,
                "unit" => "published consumption units",
                "basis" => "chained dollars, SAAR",
                "source" => "test source",
            ),
            "gdp_deflator" => Dict(
                "scale" => 9.0,
                "unit" => "index",
                "basis" => "derived",
                "source" => "test source",
            ),
        ),
    )

    adjusted, audit =
        BeforeITWeb._apply_output_measurement(raw, measurement)
    @test adjusted["real_gdp"] ≈ raw["real_gdp"] .* 2.0
    @test adjusted["real_household_consumption"] ≈
        raw["real_household_consumption"] .* 3.0
    @test adjusted["real_fixed_capitalformation"] ==
        raw["real_fixed_capitalformation"]
    @test adjusted["real_sector_gva"] == raw["real_sector_gva"]
    @test adjusted["gdp_deflator"] ≈
        raw["nominal_gdp"] ./ adjusted["real_gdp"]
    @test raw["real_gdp"] == [100.0 110.0; 105.0 115.0]

    @test audit["applied"] === true
    @test audit["schema_version"] ==
        "beforeit-output-measurement.v1"
    @test audit["method"] == "origin_level_times_model_growth"
    @test audit["origin_period"] == "2026-Q1"
    @test audit["raw_series_field"] == "model_raw"
    @test audit["sector_real_gva_adjusted"] === false
    @test audit["ignored_derived_series"] == ["gdp_deflator"]
    @test audit["gdp_deflator"]["uses_adjusted_real_gdp"] === true
    @test audit["adjusted_series"]["real_gdp"]["unit"] ==
        "published GDP units"
    @test audit["adjusted_series"]["real_gdp"]["basis"] ==
        "chained dollars, SAAR"
    @test audit["adjusted_series"]["real_gdp"]["formula"] ==
        "published_value = model_raw_value * scale"

    path_raw = Dict{String, Any}(
        "nominal_gdp" => [
            200.0 220.0
            210.0 230.0
            220.0 240.0
        ],
        "real_gdp" => [
            100.0 110.0
            105.0 115.0
            110.0 120.0
        ],
        "real_household_consumption" => [40.0, 42.0, 44.0],
    )
    path_raw_before = deepcopy(path_raw)
    amplitude = 0.3
    decay = 0.7
    matrix_origin_horizon = 4
    vector_origin_horizon = 2
    path_measurement = Dict(
        "series" => Dict(
            "real_gdp" => Dict(
                "scale" => 2.0,
                "path_correction" => Dict(
                    "method" => "damped_log_bias",
                    "amplitude" => amplitude,
                    "decay" => decay,
                    "origin_horizon" => matrix_origin_horizon,
                    "formula" => "pipeline supplied formula",
                    "calibration_note" => "matrix correction",
                ),
            ),
            "real_household_consumption" => Dict(
                "scale" => 3.0,
                "path_correction" => Dict(
                    "method" => "damped_log_bias",
                    "amplitude" => -amplitude,
                    "decay" => decay,
                    "origin_horizon" => vector_origin_horizon,
                    "calibration_note" => "vector correction",
                ),
            ),
        ),
    )
    path_adjusted, path_audit =
        BeforeITWeb._apply_output_measurement(
        path_raw,
        path_measurement,
    )
    positive_factors = [
        exp(
                amplitude * (
                    exp(-decay * matrix_origin_horizon) -
                    exp(
                        -decay *
                        (matrix_origin_horizon + horizon),
                    )
                ),
            ) for
            horizon in 0:2
    ]
    negative_factors = [
        exp(
                -amplitude * (
                    exp(-decay * vector_origin_horizon) -
                    exp(
                        -decay *
                        (vector_origin_horizon + horizon),
                    )
                ),
            ) for
            horizon in 0:2
    ]

    @test path_adjusted["real_gdp"][1, :] ==
        path_raw["real_gdp"][1, :] .* 2.0
    @test path_adjusted["real_household_consumption"][1] ==
        path_raw["real_household_consumption"][1] * 3.0
    @test path_adjusted["real_gdp"] ≈
        path_raw["real_gdp"] .* 2.0 .*
        reshape(positive_factors, :, 1)
    @test path_adjusted["real_household_consumption"] ≈
        path_raw["real_household_consumption"] .* 3.0 .*
        negative_factors
    @test path_raw == path_raw_before
    @test path_audit["path_corrected_series"]["real_gdp"][
        "method",
    ] == "damped_log_bias"
    @test path_audit["path_corrected_series"]["real_gdp"][
        "calibration_note",
    ] == "matrix correction"
    @test path_audit["path_corrected_series"]["real_gdp"][
        "formula",
    ] == "pipeline supplied formula"
    @test path_audit["path_corrected_series"]["real_gdp"][
        "origin_horizon",
    ] == matrix_origin_horizon
    @test path_audit["path_corrected_series"]["real_gdp"][
        "origin_factor",
    ] ≈ exp(
        amplitude *
            (1 - exp(-decay * matrix_origin_horizon)),
    )
    @test path_audit["path_corrected_series"]["real_gdp"][
        "applied_formula",
    ] ==
        "relative_factor(h) = factor(origin_horizon + h) / factor(origin_horizon); relative_factor(0) = 1"
    @test path_audit["adjusted_series"][
        "real_household_consumption",
    ]["path_correction"]["origin_horizon"] ==
        vector_origin_horizon
    @test path_audit["adjusted_series"]["real_gdp"]["formula"] ==
        "published_value[h] = model_raw_value[h] * scale * factor(origin_horizon + h) / factor(origin_horizon)"

    default_origin_measurement = Dict(
        "series" => Dict(
            "real_household_consumption" => Dict(
                "scale" => 3.0,
                "path_correction" => Dict(
                    "method" => "damped_log_bias",
                    "amplitude" => -amplitude,
                    "decay" => decay,
                ),
            ),
        ),
    )
    default_origin_adjusted, default_origin_audit =
        BeforeITWeb._apply_output_measurement(
        path_raw,
        default_origin_measurement,
    )
    default_origin_factors = [
        exp(-amplitude * (1 - exp(-decay * horizon))) for
            horizon in 0:2
    ]
    @test default_origin_adjusted["real_household_consumption"] ≈
        path_raw["real_household_consumption"] .* 3.0 .*
        default_origin_factors
    @test default_origin_audit["path_corrected_series"][
        "real_household_consumption",
    ]["origin_horizon"] == 0
    @test default_origin_audit["path_corrected_series"][
        "real_household_consumption",
    ]["origin_factor"] == 1.0

    sector_adjusted, sector_audit =
        BeforeITWeb._apply_output_measurement(
        raw,
        Dict(
            "real_sector_gva" => Dict(
                "scale" => 4.0,
                "unit" => "published sector units",
                "basis" => "explicit sector bridge",
            ),
        ),
    )
    @test sector_adjusted["real_sector_gva"] ≈
        raw["real_sector_gva"] .* 4.0
    @test sector_adjusted["real_gdp"] == raw["real_gdp"]
    @test sector_audit["sector_real_gva_adjusted"] === true

    unmatched_adjusted, unmatched_audit =
        BeforeITWeb._apply_output_measurement(
        raw,
        Dict(
            "series" => Dict(
                "real_exports" => Dict("scale" => 1.5),
            ),
        ),
    )
    @test unmatched_adjusted["real_gdp"] == raw["real_gdp"]
    @test unmatched_audit["unmatched_configured_series"] ==
        ["real_exports"]

    @test_throws ArgumentError BeforeITWeb._apply_output_measurement(
        raw,
        Dict("series" => Dict("real_gdp" => Dict("scale" => 0.0))),
    )
    @test_throws ArgumentError BeforeITWeb._apply_output_measurement(
        raw,
        Dict("series" => Dict("real_gdp" => Dict{String, Any}())),
    )

    malformed_corrections = Any[
        "not a dictionary",
        Dict(
            "method" => "unknown",
            "amplitude" => 0.1,
            "decay" => 0.2,
        ),
        Dict(
            "method" => "damped_log_bias",
            "decay" => 0.2,
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => Inf,
            "decay" => 0.2,
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => 0.1,
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => 0.1,
            "decay" => 0.0,
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => true,
            "decay" => 0.2,
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => 0.1,
            "decay" => 0.2,
            "origin_horizon" => -1,
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => 0.1,
            "decay" => 0.2,
            "origin_horizon" => 1.0,
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => 0.1,
            "decay" => 0.2,
            "origin_horizon" => true,
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => 0.1,
            "decay" => 0.2,
            "origin_horizon" => "1",
        ),
        Dict(
            "method" => "damped_log_bias",
            "amplitude" => 0.1,
            "decay" => 0.2,
            "origin_horizon" => big(typemax(Int)) + 1,
        ),
    ]
    for malformed in malformed_corrections
        @test_throws ArgumentError BeforeITWeb._apply_output_measurement(
            raw,
            Dict(
                "series" => Dict(
                    "real_gdp" => Dict(
                        "scale" => 2.0,
                        "path_correction" => malformed,
                    ),
                ),
            ),
        )
    end

    @test_throws ArgumentError BeforeITWeb._apply_output_measurement(
        raw,
        Dict(
            "series" => Dict(
                "real_sector_gva" => Dict(
                    "scale" => 2.0,
                    "path_correction" => Dict(
                        "method" => "damped_log_bias",
                        "amplitude" => 0.1,
                        "decay" => 0.2,
                    ),
                ),
            ),
        ),
    )
end

@testset "Scenario-compatible shocks" begin
    productivity_model =
        Bit.build_austria_scenario_model(:baseline; horizon = 2)
    alpha_before = copy(productivity_model.firms.alpha_bar_i)
    productivity = Bit.ProductivityShock(1.01)
    productivity(productivity_model)
    alpha_shocked = copy(productivity_model.firms.alpha_bar_i)
    @test alpha_shocked ≈ alpha_before .* 1.01
    productivity_model.agg.t = 2
    productivity(productivity_model)
    @test productivity_model.firms.alpha_bar_i ≈ alpha_shocked

    consumption_model =
        Bit.build_austria_scenario_model(:baseline; horizon = 3)
    psi_before = consumption_model.prop.psi
    consumption = Bit.ConsumptionShock(1.1, 2)
    consumption(consumption_model)
    @test consumption_model.prop.psi ≈ psi_before * 1.1
    consumption_model.agg.t = 2
    consumption(consumption_model)
    @test consumption_model.prop.psi ≈ psi_before * 1.1
    consumption_model.agg.t = 3
    consumption(consumption_model)
    @test consumption_model.prop.psi ≈ psi_before

    rate_model =
        Bit.build_austria_scenario_model(:baseline; horizon = 2)
    annual_before = (1 + rate_model.cb.r_bar)^4 - 1
    rate_shock = BeforeITWeb._shock_from_spec(
        Dict(
            "type" => "interest_rate",
            "annual_rate" => 0.02,
            "final_time" => 2,
        ),
        2,
    )
    rate_shock(rate_model)
    @test (1 + rate_model.cb.r_bar)^4 - 1 ≈ annual_before + 0.02

    sector_model =
        Bit.build_austria_scenario_model(:baseline; horizon = 2)
    target_sector = Int(sector_model.firms.G_i[1])
    sector_alpha_before = copy(sector_model.firms.alpha_bar_i)
    sector_shock = BeforeITWeb._shock_from_spec(
        Dict(
            "type" => "sector_productivity",
            "sector" => target_sector,
            "multiplier" => 0.9,
        ),
        2,
    )
    sector_shock(sector_model)
    targeted = sector_model.firms.G_i .== target_sector
    @test any(targeted)
    @test sector_model.firms.alpha_bar_i[targeted] ≈
        sector_alpha_before[targeted] .* 0.9
    @test sector_model.firms.alpha_bar_i[.!targeted] ≈
        sector_alpha_before[.!targeted]
    sector_alpha_shocked = copy(sector_model.firms.alpha_bar_i)
    sector_model.agg.t = 2
    sector_shock(sector_model)
    @test sector_model.firms.alpha_bar_i ≈ sector_alpha_shocked
end

@testset "Web run contract" begin
    @test_throws BeforeITWeb.ApiError BeforeITWeb._normalize_shock_spec(
        Dict("type" => "unknown"),
        4,
    )
    @test_throws BeforeITWeb.ApiError BeforeITWeb._normalize_shock_spec(
        Dict(
            "type" => "consumption",
            "multiplier" => 1.1,
            "final_time" => 5,
        ),
        4,
    )

    quarterly_rate = (1.04)^(1 / 4) - 1
    ui_overrides = BeforeITWeb._overrides_to_ui(
        "AUSTRIA2026Q1",
        Dict(
            "parameters" => Dict("tau_VAT" => 0.2),
            "initial_conditions" => Dict("r_bar" => quarterly_rate),
        ),
    )
    @test ui_overrides["parameters"]["tau_VAT"] ≈ 0.2
    @test ui_overrides["initial_conditions"]["r_bar"] ≈ 0.04

    response = BeforeITWeb._prototype_file_response("index.html")
    @test response.status == 200
    @test occursin(
        "BeforeIT — Digital Twin Prototypes",
        String(response.body),
    )
    @test_throws BeforeITWeb.ApiError BeforeITWeb._prototype_file_response(
        "../public/index.html",
    )

    explorer = BeforeITWeb._explorer_file_response("index.html")
    @test explorer.status == 200
    @test occursin(
        "Economy Complexity Explorer",
        String(explorer.body),
    )
    @test_throws BeforeITWeb.ApiError BeforeITWeb._explorer_file_response(
        "../public/index.html",
    )

    sectors = BeforeITWeb.sector_metadata("AUSTRIA2026Q1")
    @test sectors["dataset_id"] == "AUSTRIA2026Q1"
    @test sectors["classification"] == "NACE/FIGARO"
    @test length(sectors["sectors"]) == 62
    @test all(
        all(
                haskey(sector, key) for key in (
                    "index",
                    "code",
                    "label",
                    "short_label",
                    "group_id",
                    "group_label",
                    "group_order",
                    "group_color",
                )
            ) for sector in sectors["sectors"]
    )
    @test length(
        unique(
            String(sector["code"]) for sector in sectors["sectors"]
        )
    ) == 62

    us_sectors = BeforeITWeb.sector_metadata("US2026Q1")
    @test us_sectors["dataset_id"] == "US2026Q1"
    @test us_sectors["classification"] == "BEA Summary I-O"
    @test us_sectors["version"] == "BEA68.web.v1"
    @test us_sectors["currency"] == "USD"
    @test us_sectors["flow_units"] == "million_usd_per_quarter"
    @test us_sectors["stock_units"] == "million_usd"
    @test length(us_sectors["sectors"]) == 68
    @test [sector["index"] for sector in us_sectors["sectors"]] ==
        collect(1:68)
    @test first(us_sectors["sectors"])["code"] == "111CA"
    @test first(us_sectors["sectors"])["label"] == "Farms"
    @test last(us_sectors["sectors"])["code"] == "ORE"
    @test last(us_sectors["sectors"])["label"] == "Other real estate"
    @test length(
        unique(
            String(sector["code"]) for sector in us_sectors["sectors"]
        )
    ) == 68
    @test all(
        all(
                haskey(sector, key) for key in (
                    "index",
                    "code",
                    "label",
                    "short_label",
                    "group_id",
                    "group_label",
                    "group_order",
                    "group_color",
                )
            ) for sector in us_sectors["sectors"]
    )

    summary_trace =
        BeforeITWeb._normalize_trace_spec(Dict("profile" => "SUMMARY"))
    @test summary_trace["profile"] == "summary"
    @test isempty(summary_trace["realization_indices"])
    @test summary_trace["checkpoints"] === false
    standard_trace = BeforeITWeb._normalize_trace_spec(
        Dict(
            "profile" => "standard",
            "realization_indices" => [1, 1],
        ),
    )
    @test standard_trace["realization_indices"] == [1]
    @test_throws BeforeITWeb.ApiError BeforeITWeb._normalize_trace_spec(
        Dict("profile" => "unknown"),
    )

    capacity_edge = BeforeITWeb._cashflow_normalized_edge(
        "capacity:test",
        "firm:1",
        "firm:2",
        5.0;
        label = "Capacity counterfactual",
        layer = "capacity_counterfactual",
        market = "business_goods",
        purpose = "business_inputs",
        measure_kind = "counterfactual_match",
        recognition = "capacity_counterfactual",
        evidence_basis = "transaction_event",
        aggregation = "test_fixture",
        level = "firm",
    )
    capacity_query = BeforeITWeb._cashflow_query_edges(
        [capacity_edge];
        level = "firm",
        layers = "capacity",
    )
    capacity_alias_query = BeforeITWeb._cashflow_query_edges(
        [capacity_edge];
        level = "firm",
        layers = "capacity_counterfactual",
    )
    @test length(capacity_query["edges"]) == 1
    @test capacity_query["edges"][1]["id"] == "capacity:test"
    @test capacity_alias_query["edges"][1]["id"] == "capacity:test"

    spec_dir = mktempdir()
    open(joinpath(spec_dir, "spec.json"), "w") do io
        write(
            io,
            JSON3.write(
                Dict(
                    "run_id" => "named-run",
                    "name" => "  Policy comparison  ",
                    "description" => "  Exact representative trace.  ",
                    "dataset_id" => "AUSTRIA2026Q1",
                    "scenario" => "baseline",
                    "created_at" => "2026-08-01T00:00:00Z",
                    "sim" => Dict(
                        "T" => 1,
                        "n_sims" => 1,
                        "step_multithreading" => false,
                        "base_seed" => 1,
                    ),
                    "overrides" => Dict(
                        "parameters" => Dict{String, Float64}(),
                        "initial_conditions" =>
                            Dict{String, Float64}(),
                    ),
                    "shock" => Dict("type" => "none"),
                    "trace" => Dict(
                        "profile" => "standard",
                        "realization_indices" => [1],
                    ),
                ),
            ),
        )
    end
    normalized_spec = BeforeITWeb._run_spec_payload(spec_dir)
    @test normalized_spec["name"] == "Policy comparison"
    @test normalized_spec["description"] ==
        "Exact representative trace."
    @test normalized_spec["trace"]["profile"] == "standard"
    @test normalized_spec["trace"]["realization_indices"] == [1]
end

@testset "Current worker paths" begin
    structural_path =
        run_fixture_path("AUSTRIA2024Q4", "unconditional")
    structural = JSON3.read(
        read(joinpath(structural_path, "summary.json"), String),
    )
    @test structural["periods"] == ["2024-Q4", "2025-Q1"]
    @test structural["scenario"] == "unconditional"
    @test length(structural["real_gdp"]["mean"]) == 2

    us_path = run_fixture_path("US2026Q1", "unconditional")
    us_forecast = JSON3.read(
        read(joinpath(us_path, "summary.json"), String),
    )
    @test us_forecast["periods"] == ["2026-Q1", "2026-Q2"]
    @test us_forecast["forecast_start_period"] == "2026-Q2"
    @test us_forecast["dataset_id"] == "US2026Q1"
    @test us_forecast["scenario"] == "unconditional"
    @test us_forecast["dataset_metadata"]["country"] == "US"
    @test us_forecast["dataset_metadata"]["currency"] == "USD"
    @test haskey(
        us_forecast["dataset_metadata"],
        "output_measurement",
    )
    @test us_forecast["trace_profile"] == "standard"
    @test us_forecast["cashflows_available"] === true
    @test length(us_forecast["real_gdp"]["mean"]) == 2
    @test all(!isnothing, us_forecast["real_gdp"]["mean"])
    @test length(us_forecast["real_sector_gva"]["mean"]) == 2
    @test length(us_forecast["real_sector_gva"]["mean"][1]) == 68
    @test haskey(us_forecast, "model_raw")
    @test haskey(us_forecast["model_raw"], "nominal_gdp")
    @test haskey(us_forecast["model_raw"], "real_gdp")
    @test haskey(us_forecast["model_raw"], "real_sector_gva")
    @test us_forecast["measurement_adjustment"]["raw_series_field"] ==
        "model_raw"
    @test us_forecast["measurement_adjustment"]["gdp_deflator"][
        "derived",
    ] === true

    _, us_measurements = BeforeITWeb._output_measurement_series(
        us_forecast["dataset_metadata"]["output_measurement"],
    )
    for name in (
            "real_gdp",
            "real_household_consumption",
            "real_government_consumption",
            "real_fixed_capitalformation",
            "real_exports",
            "real_imports",
        )
        haskey(us_measurements, name) || continue
        scale = us_measurements[name]["scale"]
        path_correction =
            get(us_measurements[name], "path_correction", nothing)
        horizon_factors = if path_correction === nothing
            ones(length(us_forecast[name]["mean"]))
        else
            amplitude = path_correction["amplitude"]
            decay = path_correction["decay"]
            origin_horizon =
                get(path_correction, "origin_horizon", 0)
            [
                exp(
                        amplitude * (
                            exp(-decay * origin_horizon) -
                            exp(
                                -decay *
                                (origin_horizon + horizon),
                            )
                        ),
                    ) for horizon in
                    0:(length(us_forecast[name]["mean"]) - 1)
            ]
        end
        @test collect(us_forecast[name]["mean"]) ≈
            collect(us_forecast["model_raw"][name]["mean"]) .*
            scale .* horizon_factors
        @test collect(us_forecast[name]["std"]) ≈
            collect(us_forecast["model_raw"][name]["std"]) .*
            scale .* horizon_factors
        @test us_forecast[name]["measurement"]["unit"] ==
            us_measurements[name]["unit"]
        @test us_forecast[name]["measurement"]["basis"] ==
            us_measurements[name]["basis"]
        if path_correction !== nothing
            @test first(us_forecast[name]["mean"]) ≈
                first(us_forecast["model_raw"][name]["mean"]) *
                scale
            @test us_forecast[name]["measurement"][
                "path_correction",
            ]["method"] == "damped_log_bias"
        end
    end
    @test collect(us_forecast["gdp_deflator"]["mean"]) ≈
        collect(us_forecast["model_raw"]["nominal_gdp"]["mean"]) ./
        collect(us_forecast["real_gdp"]["mean"])

    if haskey(us_measurements, "real_sector_gva")
        sector_scale = us_measurements["real_sector_gva"]["scale"]
        for row_index in eachindex(
                us_forecast["real_sector_gva"]["mean"],
            )
            @test collect(
                us_forecast["real_sector_gva"]["mean"][row_index],
            ) ≈
                collect(
                us_forecast["model_raw"]["real_sector_gva"][
                    "mean",
                ][row_index],
            ) .* sector_scale
        end
        @test us_forecast["measurement_adjustment"][
            "sector_real_gva_adjusted",
        ] === true
    else
        @test us_forecast["real_sector_gva"]["mean"] ==
            us_forecast["model_raw"]["real_sector_gva"]["mean"]
        @test us_forecast["measurement_adjustment"][
            "sector_real_gva_adjusted",
        ] === false
    end

    us_manifest = BeforeITWeb._cashflow_api_payload(us_path)
    @test us_manifest["dataset_id"] == "US2026Q1"
    @test collect(us_manifest["quarters"]) == [0, 1]
    @test collect(us_manifest["periods"]) == ["2026-Q1", "2026-Q2"]
    @test length(us_manifest["sector_directory"]) == 68
    @test length(us_manifest["firm_directory"]) == 130
    @test us_manifest["units"]["flow"] == "million_usd_per_quarter"
    @test us_manifest["units"]["stock"] == "million_usd"

    us_quarter = BeforeITWeb._cashflow_api_payload(
        us_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        page_size = 5000,
    )
    @test us_quarter["diagnostics"]["passed"] === true
    @test us_quarter["units"]["flow"] == "million_usd_per_quarter"
    @test us_quarter["units"]["stock"] == "million_usd"
    @test !isempty(us_quarter["edges"])
    us_currency_edges = [
        edge for edge in us_quarter["edges"] if
            occursin("million_", String(edge["units"]))
    ]
    @test !isempty(us_currency_edges)
    @test all(
        startswith(String(edge["units"]), "million_usd") for
            edge in us_currency_edges
    )
    @test !any(
        occursin("million_eur", String(edge["units"])) for
            edge in us_quarter["edges"]
    )
    @test all(
        account["account_units"] == "million_usd" for node in
            us_quarter["firms"] for
            account in node["account_reconciliations"]
    )

    forecast_path = run_fixture_path(
        "AUSTRIA2026Q1",
        "baseline";
        trace = Dict("profile" => "summary"),
    )
    forecast = JSON3.read(
        read(joinpath(forecast_path, "summary.json"), String),
    )
    @test forecast["periods"] == ["2026-Q1", "2026-Q2"]
    @test forecast["forecast_start_period"] == "2026-Q2"
    @test forecast["scenario"] == "baseline"
    @test forecast["dataset_metadata"]["structural_reference_year"] == 2024
    @test forecast["trace_profile"] == "summary"
    @test forecast["cashflows_available"] === false
    @test haskey(forecast, "real_gdp")
    @test all(!isnothing, forecast["real_gdp"]["mean"])
    @test length(forecast["real_sector_gva"]["mean"]) == 2
    @test length(forecast["real_sector_gva"]["mean"][1]) > 1
    @test !isfile(joinpath(forecast_path, "cashflows-manifest.json"))

    manifest = BeforeITWeb._cashflow_api_payload(structural_path)
    persisted_spec = BeforeITWeb._normalize_dict(
        JSON3.read(read(joinpath(structural_path, "spec.json"), String)),
    )
    persisted_manifest = BeforeITWeb._normalize_dict(
        JSON3.read(
            read(
                joinpath(structural_path, "cashflows-manifest.json"),
                String,
            ),
        ),
    )
    @test persisted_spec["provenance"]["schema_version"] ==
        BeforeITWeb.RUN_PROVENANCE_SCHEMA_VERSION
    for digest_field in (
            "producer_source_digest",
            "model_source_digest",
            "trace_source_digest",
            "dataset_digest",
            "calibration_digest",
            "initial_state_digest",
        )
        @test startswith(
            persisted_spec["provenance"][digest_field],
            "sha256:",
        )
    end
    @test persisted_spec["provenance"]["rng_policy"][
        "stream_stable_common_random_numbers",
    ] === false
    @test persisted_spec["provenance"]["execution_environment"] == Dict(
        "julia_version" => string(VERSION),
        "thread_count" => Threads.nthreads(),
        "architecture" => string(Sys.ARCH),
        "kernel" => string(Sys.KERNEL),
        "word_size" => Sys.WORD_SIZE,
        "scope" =>
            "Replay compatibility evidence; paired runs require exact agreement",
    )
    @test BeforeITWeb._experiment_canonical(
        persisted_spec["provenance"],
    ) == BeforeITWeb._experiment_canonical(
        persisted_manifest["provenance"],
    )
    @test BeforeITWeb._run_provenance_digest(
        reshape(collect(1:6), 2, 3),
    ) != BeforeITWeb._run_provenance_digest(collect(1:6))
    @test manifest["schema_version"] == "quarter-ledger.v2"
    @test manifest["trace_schema_version"] == "quarter-ledger.v2"
    @test manifest["api_schema_version"] == "explorer-edges.v2"
    @test collect(manifest["quarters"]) == [0, 1]
    @test collect(manifest["periods"]) == ["2024-Q4", "2025-Q1"]
    @test manifest["initial_period"] == "2024-Q4"
    @test manifest["initial_period_has_flows"] === false
    @test manifest["trace_profile"] == "standard"
    @test manifest["realization"]["index"] == 1
    @test manifest["realization"]["seed"] == 2
    @test manifest["realization"]["ensemble_size"] == 1
    @test !isempty(manifest["firm_directory"])
    @test length(manifest["sector_directory"]) == 62
    @test !isempty(manifest["scale_domains"])
    @test all(
        domain["min"] == 0.0 &&
            domain["max"] > 0 &&
            domain["count"] > 0 &&
            domain["mapping"] == "sqrt" for
            domain in values(manifest["scale_domains"])
    )
    for capability in (
            "normalized_edges",
            "institution_flows",
            "institution_components",
            "sector_network",
            "firm_network",
            "business_counterparties",
            "final_demand_counterparties",
            "capacity_counterfactual",
            "household_cohorts",
            "node_stock_flow_reconciliation",
            "opening_snapshot",
        )
        @test manifest["capabilities"][capability] === true
    end
    @test manifest["capabilities"]["true_unmet_demand"] === false
    @test manifest["capabilities"]["phase_trace"] === false
    @test manifest["capabilities"]["checkpoints"] === false

    stored_quarter = load(
        joinpath(structural_path, "cashflow-1.jld2"),
        "payload",
    )
    @test stored_quarter["edge_encoding"] ==
        BeforeITWeb.CASHFLOW_EDGE_ENCODING_GZIP
    @test stored_quarter["edge_compressed_bytes"] <
        stored_quarter["edge_uncompressed_bytes"]
    @test !haskey(stored_quarter, "edges")
    @test length(BeforeITWeb._cashflow_complete_edges(stored_quarter)) ==
        stored_quarter["edge_count"]
    BeforeITWeb._cashflow_clear_artifact_cache!()
    cached_metadata_a, cached_edges_a =
        BeforeITWeb._cashflow_cached_artifact(
        joinpath(structural_path, "cashflow-1.jld2"),
    )
    cached_metadata_b, cached_edges_b =
        BeforeITWeb._cashflow_cached_artifact(
        joinpath(structural_path, "cashflow-1.jld2"),
    )
    @test cached_edges_a === cached_edges_b
    @test cached_metadata_a !== cached_metadata_b
    cached_metadata_a["cache_copy_probe"] = true
    @test !haskey(cached_metadata_b, "cache_copy_probe")

    opening = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 0,
        detail = "firm",
        level = "firm",
    )
    @test opening["schema_version"] == "quarter-ledger.v2"
    @test opening["trace_schema_version"] == "quarter-ledger.v2"
    @test opening["api_schema_version"] == "explorer-edges.v2"
    @test opening["quarter_index"] == 0
    @test opening["summary_index"] == 1
    @test opening["snapshot_kind"] ==
        "calibrated_pre_restructuring"
    @test opening["realization"]["index"] == 1
    @test opening["timing"]["initial_period_has_flows"] === false
    @test opening["observability"]["potential_demand_is_cash"] === false
    @test opening["capabilities"]["opening_snapshot"] === true
    @test isempty(opening["edges"])
    @test opening["edge_count_total"] == 0
    @test opening["edge_count_matching"] == 0
    @test isempty(opening["flows"])
    @test isempty(opening["rollups"])
    @test all(
        stock["open"] == stock["close"] for
            stock in values(opening["stocks"])
    )
    @test opening["diagnostics"]["passed"] === true
    opening_json = JSON3.read(
        JSON3.write(BeforeITWeb._sanitize_for_json(opening)),
    )
    @test opening_json["timing"]["initial_period_has_flows"] === false
    @test opening_json["capabilities"]["opening_snapshot"] === true
    @test opening_json["observability"]["potential_demand_is_cash"] === false
    opening_firm_account = only(
        first(opening["firms"])["account_reconciliations"]
    )
    @test opening_firm_account["recorded_change"] == 0.0
    @test opening_firm_account["opening_value"] ==
        opening_firm_account["closing_value"]
    @test opening_firm_account["reconciliation_status"] ==
        "within_tolerance"
    @test opening_firm_account[
        "classified_cashflow_identity_supported",
    ] === false

    sector_trace = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "sector",
        level = "sector",
        limit = 12,
        sector_limit = 5000,
        page_size = 5000,
    )
    @test sector_trace["schema_version"] == "quarter-ledger.v2"
    @test sector_trace["trace_schema_version"] == "quarter-ledger.v2"
    @test sector_trace["api_schema_version"] == "explorer-edges.v2"
    @test sector_trace["period"] == "2025-Q1"
    @test sector_trace["summary_index"] == 2
    @test sector_trace["realization"]["index"] == 1
    @test isempty(sector_trace["firms"])
    @test sector_trace["diagnostics"]["passed"] === true
    diagnostics = sector_trace["diagnostics"]
    for diagnostic in (
            "goods_market_residual",
            "business_trace_residual",
            "household_final_demand_trace_residual",
            "government_final_demand_trace_residual",
            "foreign_final_demand_trace_residual",
            "all_market_trace_residual",
            "nominal_gdp_residual",
            "real_gdp_residual",
            "central_bank_balance_residual",
            "commercial_bank_balance_residual",
            "government_revenue_residual",
            "government_debt_residual",
            "external_position_residual",
            "central_bank_equity_residual",
            "bank_equity_residual",
            "firm_loan_identity_max_residual",
            "household_cohort_count_residual",
        )
        @test diagnostics[diagnostic] isa Real
        @test abs(diagnostics[diagnostic]) <= diagnostics["tolerance"]
    end
    @test sector_trace["diagnostics"]["potential_demand_not_cash"] >= 0
    @test sector_trace["relationship_count_total"] > 0
    @test sector_trace["sector_relationship_count_total"] > 0
    @test isempty(sector_trace["relationships"])
    @test isempty(sector_trace["sector_relationships"])
    @test all(
        edge["level"] in ("macro", "sector") for
            edge in sector_trace["edges"]
    )
    @test any(
        edge["market"] == "business_goods" &&
            edge["recognition"] == "realized_cash" for
            edge in sector_trace["edges"]
    )
    @test any(
        edge["market"] == "final_demand" &&
            edge["recognition"] == "realized_cash" for
            edge in sector_trace["edges"]
    )
    @test any(
        edge["evidence_basis"] == "model_equation" for
            edge in sector_trace["edges"]
    )

    firm_trace = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        limit = 5000,
        sector_limit = 5000,
        page_size = 5000,
    )
    @test !isempty(firm_trace["firms"])
    @test isempty(firm_trace["relationships"])
    @test isempty(firm_trace["sector_relationships"])
    @test all(
        edge["level"] in ("macro", "sector", "firm") for
            edge in firm_trace["edges"]
    )
    macro_trace = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "macro",
        page_size = 5000,
    )
    macro_edges = Dict(
        String(edge["id"]) => edge for edge in macro_trace["edges"]
    )
    firm_institution_rollups = (
        "macro:wages",
        "macro:firm-dividends",
        "macro:new-credit",
        "macro:principal",
        "macro:firm-credit-interest",
        "macro:firm-deposit-interest",
        "macro:firm-deposit-change",
        "stock:firm-loans",
        "stock:firm-deposits",
    )
    @test all(haskey(macro_edges, id) for id in firm_institution_rollups)
    @test Set(
        String(macro_edges[id]["layer"]) for
            id in firm_institution_rollups
    ) == Set(["income", "credit", "interest", "deposits", "stocks"])
    for macro_id in firm_institution_rollups
        sector_children = BeforeITWeb._cashflow_api_payload(
            structural_path;
            quarter = 1,
            detail = "firm",
            level = "firm",
            parent_id = macro_id,
            page_size = 5000,
        )
        @test sector_children["edge_count_matching"] > 0
        @test all(
            edge["level"] == "sector" &&
                edge["rollup_id"] == macro_id &&
                collect(String.(edge["parent_ids"])) == [macro_id] for
                edge in sector_children["edges"]
        )
        @test isapprox(
            sum(
                Float64(edge["signed_value"]) for
                    edge in sector_children["edges"]
            ),
            Float64(macro_edges[macro_id]["signed_value"]);
            atol = 1.0e-6,
            rtol = 1.0e-10,
        )
    end

    complete_account_edges = [
        edge for edge in BeforeITWeb._cashflow_complete_edges(
                structural_path;
                quarter = 1,
            ) if haskey(edge, "account_id")
    ]
    @test !isempty(complete_account_edges)
    account_fields = (
        "account_id",
        "account_kind",
        "account_holder_node_id",
        "account_level",
        "account_aggregation",
        "opening_value",
        "recorded_change",
        "closing_value",
        "residual",
        "tolerance",
        "reconciliation_residual",
        "reconciliation_tolerance",
        "reconciliation_status",
        "reconciliation_basis",
        "reconciliation_evidence_basis",
        "classified_cashflow_identity_supported",
    )
    @test all(
        all(haskey(edge, field) for field in account_fields) for
            edge in complete_account_edges
    )
    for edge in complete_account_edges
        @test isapprox(
            Float64(edge["opening_value"]) +
                Float64(edge["recorded_change"]),
            Float64(edge["closing_value"]);
            atol = Float64(edge["reconciliation_tolerance"]),
            rtol = 0.0,
        )
        @test abs(Float64(edge["reconciliation_residual"])) <=
            Float64(edge["reconciliation_tolerance"])
        @test edge["reconciliation_status"] == "within_tolerance"
        @test edge["classified_cashflow_identity_supported"] === false
    end

    deposit_sector_parent = first(
        edge for edge in complete_account_edges if
            edge["level"] == "sector" &&
            edge["purpose"] == "deposit_stock"
    )
    deposit_firm_children = [
        edge for edge in complete_account_edges if
            edge["level"] == "firm" &&
            edge["rollup_id"] == deposit_sector_parent["id"]
    ]
    @test !isempty(deposit_firm_children)
    @test isapprox(
        sum(Float64(edge["signed_value"]) for edge in deposit_firm_children),
        Float64(deposit_sector_parent["signed_value"]);
        atol = 1.0e-6,
        rtol = 1.0e-10,
    )
    deposit_sector = parse(
        Int,
        split(String(deposit_sector_parent["account_holder_node_id"]), ':')[2],
    )
    deposit_sector_firm_accounts = [
        only(node["account_reconciliations"]) for node in
            firm_trace["firms"] if
            Int(node["sector"]) == deposit_sector
    ]
    @test isapprox(
        sum(
            Float64(account["opening_value"]) for
                account in deposit_sector_firm_accounts
        ),
        Float64(deposit_sector_parent["opening_value"]);
        atol = 1.0e-6,
        rtol = 1.0e-10,
    )
    @test isapprox(
        sum(
            Float64(account["recorded_change"]) for
                account in deposit_sector_firm_accounts
        ),
        Float64(deposit_sector_parent["recorded_change"]);
        atol = 1.0e-6,
        rtol = 1.0e-10,
    )

    @test haskey(macro_edges, "stock:household-deposits")
    household_stock = macro_edges["stock:household-deposits"]
    household_stock_children = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "macro",
        parent_id = "stock:household-deposits",
        coverage = 1.0,
        page_size = 5000,
    )
    @test 1 <= length(household_stock_children["edges"]) <= 4
    @test all(
        edge["account_edge_role"] == "closing_stock" &&
            edge["summation_role"] == "component" for
            edge in household_stock_children["edges"]
    )
    @test isapprox(
        sum(
            Float64(edge["signed_value"]) for
                edge in household_stock_children["edges"]
        ),
        Float64(household_stock["signed_value"]);
        atol = 1.0e-6,
        rtol = 1.0e-10,
    )
    household_cohort_nodes = [
        node for node in macro_trace["nodes"] if
            startswith(String(node["id"]), "household:")
    ]
    @test length(household_cohort_nodes) == 4
    @test all(
        length(node["account_reconciliations"]) == 1 for
            node in household_cohort_nodes
    )

    selected_firm_node = first(firm_trace["firms"])
    selected_firm_account = only(
        selected_firm_node["account_reconciliations"]
    )
    @test selected_firm_account["account_holder_node_id"] ==
        selected_firm_node["id"]
    @test isapprox(
        Float64(selected_firm_account["opening_value"]) +
            Float64(selected_firm_account["recorded_change"]),
        Float64(selected_firm_account["closing_value"]);
        atol = Float64(
            selected_firm_account["reconciliation_tolerance"],
        ),
        rtol = 0.0,
    )

    government_revenue_rollup = only(
        rollup for rollup in macro_trace["rollups"] if
            rollup["id"] == "fiscal:government-revenue"
    )
    government_revenue_components = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        parent_id = government_revenue_rollup["id"],
        page_size = 5000,
    )
    @test government_revenue_components["edge_count_matching"] > 0
    @test all(
        edge["level"] == "macro" &&
            edge["rollup_id"] == government_revenue_rollup["id"] &&
            edge["summation_role"] == "component" for
            edge in government_revenue_components["edges"]
    )
    @test isapprox(
        sum(
            Float64(edge["signed_value"]) for
                edge in government_revenue_components["edges"]
        ),
        Float64(government_revenue_rollup["amount"]);
        atol = 1.0e-6,
        rtol = 1.0e-10,
    )

    fiscal_firm_components = Dict(
        "fiscal:employer-social-contribution" =>
            "employer_social_contribution",
        "fiscal:product-tax" => "product_tax",
        "fiscal:production-tax" => "production_tax",
        "fiscal:corporate-tax:firms" => "corporate_tax",
    )
    @test all(
        haskey(macro_edges, id) for id in (
                "fiscal:employer-social-contribution",
                "fiscal:production-tax",
                "fiscal:corporate-tax:firms",
            )
    )
    for (component_edge_id, component_id) in fiscal_firm_components
        # Normalized traces are sparse: an exactly-zero component (product
        # tax in some calibrations) has neither a macro edge nor descendants.
        haskey(macro_edges, component_edge_id) || continue
        sector_children = BeforeITWeb._cashflow_api_payload(
            structural_path;
            quarter = 1,
            detail = "firm",
            level = "firm",
            parent_id = component_edge_id,
            page_size = 5000,
        )
        @test sector_children["edge_count_matching"] > 0
        isempty(sector_children["edges"]) && continue
        @test all(
            edge["level"] == "sector" &&
                edge["rollup_id"] == component_edge_id &&
                edge["component_id"] == component_id &&
                edge["summation_role"] == "component" &&
                collect(String.(edge["parent_ids"])) ==
                [component_edge_id] for edge in sector_children["edges"]
        )
        @test isapprox(
            sum(
                Float64(edge["signed_value"]) for
                    edge in sector_children["edges"]
            ),
            Float64(macro_edges[component_edge_id]["signed_value"]);
            atol = 1.0e-6,
            rtol = 1.0e-10,
        )

        sector_parent = first(sector_children["edges"])
        firm_children = BeforeITWeb._cashflow_api_payload(
            structural_path;
            quarter = 1,
            detail = "firm",
            level = "firm",
            parent_id = sector_parent["id"],
            page_size = 5000,
        )
        @test firm_children["edge_count_matching"] > 0
        @test all(
            edge["level"] == "firm" &&
                edge["rollup_id"] == sector_parent["id"] &&
                edge["component_id"] == component_id &&
                edge["summation_role"] == "detail" &&
                collect(String.(edge["parent_ids"])) ==
                [String(sector_parent["id"])] for
                edge in firm_children["edges"]
        )
        @test isapprox(
            sum(
                Float64(edge["signed_value"]) for
                    edge in firm_children["edges"]
            ),
            Float64(sector_parent["signed_value"]);
            atol = 1.0e-6,
            rtol = 1.0e-10,
        )
    end

    focus_edge = first(
        edge for edge in firm_trace["edges"] if
            edge["level"] == "firm" &&
            (
                startswith(edge["source"], "firm:") ||
                startswith(edge["target"], "firm:")
            )
    )
    focus_node =
        startswith(focus_edge["source"], "firm:") ?
        focus_edge["source"] : focus_edge["target"]
    focus_id = parse(Int, split(focus_node, ':')[2])
    focused = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        limit = 5000,
        sector_limit = 5000,
        firm_id = focus_id,
        page_size = 5000,
    )
    @test focused["query"]["focus"] == focus_node
    @test all(
        edge["source"] == focus_node ||
            edge["target"] == focus_node for edge in focused["edges"]
    )

    money_direction = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        direction = "money",
        page_size = 5000,
    )
    @test money_direction["edge_count_matching"] ==
        firm_trace["edge_count_matching"]
    @test Set(
        String(edge["id"]) for edge in money_direction["edges"]
    ) == Set(String(edge["id"]) for edge in firm_trace["edges"])

    government_focus = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "sector",
        level = "sector",
        focus = "government",
        layers = "products",
        page_size = 5000,
    )
    @test government_focus["edge_count_matching"] > 0
    @test all(
        edge["source"] == "government" ||
            edge["target"] == "government" for
            edge in government_focus["edges"]
    )
    government_sector_parent = first(
        edge for edge in government_focus["edges"] if
            edge["level"] == "sector"
    )
    government_firm_children = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        parent_id = government_sector_parent["id"],
        layers = "products",
        coverage = 1.0,
        page_size = 5000,
    )
    @test government_firm_children["edge_count_matching"] > 0
    @test all(
        government_sector_parent["id"] in edge["parent_ids"] for
            edge in government_firm_children["edges"]
    )
    @test isapprox(
        sum(
            Float64(edge["amount"]) for
                edge in government_firm_children["edges"]
        ),
        Float64(government_sector_parent["amount"]);
        atol = 1.0e-6,
        rtol = 1.0e-10,
    )

    capacity = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        layers = "capacity",
        include_potential = true,
        page_size = 5000,
    )
    capacity_alias = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        layers = "capacity_counterfactual",
        include_potential = true,
        page_size = 5000,
    )
    @test all(
        edge["layer"] == "capacity" &&
            edge["recognition"] == "capacity_counterfactual" for
            edge in capacity["edges"]
    )
    @test Set(String(edge["id"]) for edge in capacity["edges"]) ==
        Set(String(edge["id"]) for edge in capacity_alias["edges"])

    first_page = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        coverage = 0.5,
        page_size = 7,
    )
    @test length(first_page["edges"]) == 7
    @test first_page["next_cursor"] !== nothing
    @test !isempty(first_page["coverage"])
    @test all(
        -1.0e-12 <= domain["returned_fraction"] <= 1.0 + 1.0e-12 &&
            -1.0e-12 <= domain["matching_fraction"] <=
            1.0 + 1.0e-12 &&
            domain["amount_omitted"] >= 0 for
            domain in values(first_page["coverage"])
    )
    second_page = BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        coverage = 0.5,
        page_size = 7,
        cursor = first_page["next_cursor"],
    )
    @test isempty(
        intersect(
            Set(String(edge["id"]) for edge in first_page["edges"]),
            Set(String(edge["id"]) for edge in second_page["edges"]),
        ),
    )
    @test_throws BeforeITWeb.ApiError BeforeITWeb._cashflow_api_payload(
        structural_path;
        quarter = 1,
        detail = "firm",
        level = "firm",
        layers = "products",
        coverage = 0.5,
        page_size = 7,
        cursor = first_page["next_cursor"],
    )

    complete_edges = BeforeITWeb._cashflow_complete_edges(
        structural_path;
        quarter = 1,
    )
    @test length(complete_edges) == firm_trace["edge_count_total"]
    edge_ids = String[String(edge["id"]) for edge in complete_edges]
    @test length(edge_ids) == length(unique(edge_ids))
    required_edge_keys = (
        "id",
        "canonical_source",
        "canonical_target",
        "source",
        "target",
        "display_source",
        "display_target",
        "signed_value",
        "amount",
        "label",
        "layer",
        "economic_layer",
        "market",
        "purpose",
        "measure_kind",
        "recognition",
        "evidence_basis",
        "realization_scope",
        "realization_index",
        "aggregation",
        "timing",
        "units",
        "direction_semantics",
        "valuation_basis",
        "level",
        "rollup_id",
        "parent_ids",
        "summation_role",
    )
    @test all(
        all(haskey(edge, key) for key in required_edge_keys) for
            edge in complete_edges
    )
    @test all(
        edge["amount"] == abs(edge["signed_value"]) &&
            edge["amount"] > 0 &&
            edge["realization_index"] == 1 for edge in complete_edges
    )
    @test all(
        haskey(
                manifest["scale_domains"],
                BeforeITWeb._cashflow_edge_domain(edge),
            ) &&
            edge["amount"] <=
            manifest["scale_domains"][
                BeforeITWeb._cashflow_edge_domain(edge),
            ]["max"] for edge in complete_edges
    )

    export_payload = BeforeITWeb._cashflow_export_payload(
        structural_path;
        quarter = 1,
        level = "macro",
    )
    @test export_payload["trace_schema_version"] ==
        "quarter-ledger.v2"
    @test export_payload["api_schema_version"] ==
        "explorer-edges.v2"
    @test export_payload["count"] == length(export_payload["edges"])
    @test export_payload["count"] > 0
    @test all(
        edge["level"] == "macro" for edge in export_payload["edges"]
    )
    csv_response = BeforeITWeb._cashflow_export_response(
        BeforeITWeb._sanitize_for_json(export_payload),
        "csv",
    )
    @test csv_response.status == 200
    csv_body = String(csv_response.body)
    @test startswith(
        csv_body,
        "run_id,quarter_index,period,trace_schema_version,api_schema_version,",
    )
    @test length(split(chomp(csv_body), "\r\n")) ==
        export_payload["count"] + 1
    jsonl_response = BeforeITWeb._cashflow_export_response(
        BeforeITWeb._sanitize_for_json(export_payload),
        "jsonl",
    )
    @test jsonl_response.status == 200
    jsonl_records = split(chomp(String(jsonl_response.body)), '\n')
    @test length(jsonl_records) == export_payload["count"] + 1
    @test JSON3.read(first(jsonl_records))["record_type"] == "metadata"
    @test all(
        JSON3.read(record)["record_type"] == "edge" for
            record in Iterators.drop(jsonl_records, 1)
    )
    @test_nowarn JSON3.write(
        BeforeITWeb._sanitize_for_json(firm_trace),
    )

    @test BeforeITWeb._experiment_digest(Dict("a" => 1, "b" => 2.0)) ==
        BeforeITWeb._experiment_digest(Dict("b" => 2.0, "a" => 1))
    intervention = BeforeITWeb._experiment_normalize_intervention(
        Dict(
            "shock" => Dict(
                "type" => "sector_productivity",
                "sector" => 1,
                "multiplier" => 1.0,
            ),
        ),
        "AUSTRIA2024Q4",
        1,
    )
    @test intervention["shock"] == Dict{String, Any}(
        "type" => "sector_productivity",
        "sector" => 1,
        "multiplier" => 1.0,
    )
    @test_throws BeforeITWeb.ApiError BeforeITWeb._experiment_normalize_intervention(
        Dict(
            "shock" => Dict(
                "type" => "sector_productivity",
                "sector" => 999,
                "multiplier" => 1.0,
            ),
        ),
        "AUSTRIA2024Q4",
        1,
    )

    experiments_directory = mktempdir()
    persisted_experiment_id = string(uuid4())
    persisted_experiment = Dict{String, Any}(
        "schema_version" => BeforeITWeb.EXPERIMENT_SCHEMA_VERSION,
        "experiment_id" => persisted_experiment_id,
        "created_at" => "2026-08-01T00:00:00Z",
        "run_ids" => Dict("baseline" => "a", "treatment" => "b"),
    )
    BeforeITWeb._experiment_write_json(
        BeforeITWeb._experiment_path(
            persisted_experiment_id;
            directory = experiments_directory,
        ),
        persisted_experiment,
    )
    @test BeforeITWeb.get_experiment(
        persisted_experiment_id;
        directory = experiments_directory,
    )["experiment_id"] == persisted_experiment_id
    @test only(
        BeforeITWeb.list_experiments(; directory = experiments_directory),
    )["experiment_id"] == persisted_experiment_id
    @test_throws BeforeITWeb.ApiError BeforeITWeb.get_experiment(
        "../not-an-experiment";
        directory = experiments_directory,
    )

    comparison_run_paths = String[]
    comparison_run_ids = String[]
    try
        for role in ("baseline", "treatment")
            run_id = string(uuid4())
            run_path = joinpath(BeforeITWeb.RUNS_DIR, run_id)
            mkpath(run_path)
            for filename in readdir(structural_path)
                cp(
                    joinpath(structural_path, filename),
                    joinpath(run_path, filename);
                    force = true,
                )
            end
            stored_spec = BeforeITWeb._normalize_dict(
                JSON3.read(read(joinpath(run_path, "spec.json"), String)),
            )
            stored_spec["run_id"] = run_id
            stored_spec["experiment_role"] = role
            BeforeITWeb._experiment_write_json(
                joinpath(run_path, "spec.json"),
                stored_spec,
            )
            stored_manifest = BeforeITWeb._normalize_dict(
                JSON3.read(
                    read(
                        joinpath(run_path, "cashflows-manifest.json"),
                        String,
                    ),
                ),
            )
            stored_manifest["run_id"] = run_id
            BeforeITWeb._experiment_write_json(
                joinpath(run_path, "cashflows-manifest.json"),
                stored_manifest,
            )
            push!(comparison_run_ids, run_id)
            push!(comparison_run_paths, run_path)
        end
        no_op_comparison = BeforeITWeb.compare_cashflows(
            comparison_run_ids[1],
            comparison_run_ids[2];
            quarter = 1,
            level = "sector",
            layers = "products",
            coverage = 1.0,
            limit = 10_000,
            include_unchanged = true,
            experiments_directory,
        )
        @test no_op_comparison["query_applied_after_join"] === true
        @test no_op_comparison["compatibility"]["paired"] === false
        @test no_op_comparison["compatibility"]["eligible"] === false
        @test no_op_comparison["numeric_contract"]["exact_zero_diff_within_contract"] ===
            true
        @test no_op_comparison["coverage"]["join_performed_before_coverage_and_truncation"] ===
            true
        @test no_op_comparison["coverage"]["count_complete_joined"] ==
            length(BeforeITWeb._cashflow_complete_edges(structural_path; quarter = 1))
        @test !isempty(no_op_comparison["shared_scale_domains"])
        @test all(
            domain["shared"] === true &&
                domain["scope"] == "run_wide_max_across_a_and_b" for
                domain in values(no_op_comparison["shared_scale_domains"])
        )
        @test !isempty(no_op_comparison["edges"])
        @test all(
            edge["delta_class"] == "unchanged" &&
                edge["delta"] == 0.0 for edge in no_op_comparison["edges"]
        )

        paired_experiment_id = string(uuid4())
        baseline_spec = BeforeITWeb._normalize_dict(
            JSON3.read(
                read(
                    joinpath(comparison_run_paths[1], "spec.json"),
                    String,
                ),
            ),
        )
        treatment_spec = BeforeITWeb._normalize_dict(
            JSON3.read(
                read(
                    joinpath(comparison_run_paths[2], "spec.json"),
                    String,
                ),
            ),
        )
        baseline_spec["experiment_id"] = paired_experiment_id
        baseline_spec["experiment_role"] = "baseline"
        treatment_spec["experiment_id"] = paired_experiment_id
        treatment_spec["experiment_role"] = "treatment"
        treatment_spec["parent_run_id"] = comparison_run_ids[1]
        BeforeITWeb._experiment_write_json(
            joinpath(comparison_run_paths[1], "spec.json"),
            baseline_spec,
        )
        BeforeITWeb._experiment_write_json(
            joinpath(comparison_run_paths[2], "spec.json"),
            treatment_spec,
        )
        baseline_effective =
            BeforeITWeb._experiment_effective_spec(baseline_spec)
        treatment_effective =
            BeforeITWeb._experiment_effective_spec(treatment_spec)
        paired_experiment = Dict{String, Any}(
            "schema_version" => BeforeITWeb.EXPERIMENT_SCHEMA_VERSION,
            "experiment_id" => paired_experiment_id,
            "created_at" => "2026-08-01T00:00:00Z",
            "run_ids" => Dict(
                "baseline" => comparison_run_ids[1],
                "treatment" => comparison_run_ids[2],
            ),
            "baseline_reused" => false,
            "base_spec_digest" =>
                BeforeITWeb._experiment_digest(baseline_effective),
            "treatment_spec_digest" =>
                BeforeITWeb._experiment_digest(treatment_effective),
            "realized_intervention_diff" => Any[],
        )
        BeforeITWeb._experiment_write_json(
            BeforeITWeb._experiment_path(
                paired_experiment_id;
                directory = experiments_directory,
            ),
            paired_experiment,
        )

        paired_no_op = BeforeITWeb.compare_cashflows(
            comparison_run_ids[1],
            comparison_run_ids[2];
            quarter = 1,
            level = "sector",
            layers = "products",
            coverage = 1.0,
            limit = 10_000,
            include_unchanged = true,
            experiments_directory,
        )
        @test paired_no_op["compatibility"]["paired"] === true
        @test paired_no_op["compatibility"]["comparison_mode"] ==
            "paired_controlled_contrast"
        @test all(
            check["passed"] for check in
                paired_no_op["compatibility"]["checks"] if startswith(
                    String(check["name"]),
                    "provenance_",
                )
        )

        treatment_manifest_path = joinpath(
            comparison_run_paths[2],
            "cashflows-manifest.json",
        )
        treatment_manifest = BeforeITWeb._normalize_dict(
            JSON3.read(read(treatment_manifest_path, String)),
        )
        delete!(treatment_manifest, "provenance")
        BeforeITWeb._experiment_write_json(
            treatment_manifest_path,
            treatment_manifest,
        )
        missing_provenance =
            BeforeITWeb._experiment_comparison_compatibility(
            comparison_run_paths[1],
            comparison_run_paths[2];
            level = "sector",
            layers = "products",
            experiment = paired_experiment,
            quarter = 1,
        )
        @test missing_provenance["paired"] === false
        missing_check = only(
            check for check in missing_provenance["checks"] if
                check["name"] == "provenance_required_fields"
        )
        @test missing_check["evidence"]["failure_code"] ==
            "provenance_missing"

        treatment_manifest["provenance"] =
            deepcopy(baseline_spec["provenance"])
        treatment_manifest["provenance"]["model_source_digest"] =
            "sha256:" * repeat("0", 64)
        treatment_spec["provenance"] =
            deepcopy(treatment_manifest["provenance"])
        BeforeITWeb._experiment_write_json(
            treatment_manifest_path,
            treatment_manifest,
        )
        BeforeITWeb._experiment_write_json(
            joinpath(comparison_run_paths[2], "spec.json"),
            treatment_spec,
        )
        mismatched_provenance =
            BeforeITWeb._experiment_comparison_compatibility(
            comparison_run_paths[1],
            comparison_run_paths[2];
            level = "sector",
            layers = "products",
            experiment = paired_experiment,
            quarter = 1,
        )
        @test mismatched_provenance["paired"] === false
        pair_check = only(
            check for check in mismatched_provenance["checks"] if
                check["name"] == "provenance_pair_identity"
        )
        @test pair_check["evidence"]["failure_code"] ==
            "provenance_pair_mismatch"
    finally
        for run_path in comparison_run_paths
            isdir(run_path) && rm(run_path; recursive = true, force = true)
        end
    end

    legacy_dir = mktempdir()
    legacy_manifest = Dict(
        "schema_version" => "quarter-ledger.v1",
        "quarters" => [1],
        "initial_period" => "2024-Q4",
    )
    open(joinpath(legacy_dir, "cashflows-manifest.json"), "w") do io
        write(io, JSON3.write(legacy_manifest))
    end
    legacy_payload = Dict{String, Any}(
        "schema_version" => "quarter-ledger.v1",
        "run_id" => "legacy-run",
        "period" => "2025-Q1",
        "quarter_index" => 1,
        "summary_index" => 2,
        "realization" => Dict("index" => 1),
        "capabilities" => Dict("firm_network" => true),
        "flows" => [
            Dict(
                "id" => "wages",
                "source" => "production",
                "target" => "households",
                "amount" => 12.5,
                "label" => "Wages",
                "layer" => "transactions",
                "category" => "income",
                "provenance" => "legacy_model_equation",
            ),
        ],
    )
    JLD2.jldsave(
        joinpath(legacy_dir, "cashflow-1.jld2"),
        true;
        payload = legacy_payload,
    )
    legacy = BeforeITWeb._cashflow_api_payload(
        legacy_dir;
        quarter = 1,
        detail = "sector",
        level = "macro",
    )
    @test legacy["trace_schema_version"] == "quarter-ledger.v1"
    @test legacy["api_schema_version"] == "explorer-edges.v2"
    @test legacy["capabilities"]["normalized_edges"] === true
    @test legacy["capabilities"]["normalized_edges_are_adapter"] === true
    @test legacy["capabilities"]["final_demand_counterparties"] === false
    @test legacy["capabilities"]["institution_components"] === false
    @test legacy["capabilities"]["stable_signed_direction"] === false
    @test length(legacy["edges"]) == 1
    @test legacy["edges"][1]["legacy_adapter"] === true
    @test legacy["edges"][1]["evidence_basis"] ==
        "legacy_model_equation"

    @test_throws BeforeITWeb.ApiError BeforeITWeb._cashflow_api_payload(
        mktempdir(),
    )
end

include("hierarchy_deeplink.jl")
include("provenance_environment.jl")
include("economic_validation.jl")
