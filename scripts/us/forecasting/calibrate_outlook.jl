#!/usr/bin/env julia

module USOutlookCalibration

    using CSV
    using DataFrames
    using Dates
    using JSON
    using LinearAlgebra
    using Printf
    using Random
    using SHA
    using Statistics
    using TOML

    import BeforeIT as Bit

    const SCRIPT_DIR = @__DIR__
    const REPO_ROOT = normpath(joinpath(SCRIPT_DIR, "..", "..", ".."))
    const DEFAULT_OUTPUT_DIR = joinpath(REPO_ROOT, "output", "us_calibration")
    const DEFAULT_CONFIG_PATH =
        joinpath(REPO_ROOT, "scripts", "us", "forecast_calibration.toml")
    const EXPECTED_SCHEMA = "beforeit-us-forecast-calibration.v2"
    const EXPECTED_TRUTH_START = Date(2023, 12, 31)
    const EXPECTED_MEASUREMENT_ANCHOR = Date(2024, 3, 31)
    const EXPECTED_TARGET_START = Date(2024, 6, 30)
    const EXPECTED_TRAIN_END = Date(2025, 12, 31)
    const EXPECTED_HOLDOUT_START = Date(2026, 3, 31)
    const EXPECTED_TARGET_END = Date(2026, 6, 30)
    const DEFAULT_SEED = 17_000
    const DEFAULT_SIMS = 128
    const DEFAULT_FORECAST_HORIZON = 15
    const DEFAULT_BACKTEST_HORIZON = 1
    const EXPECTED_MODEL_SCALE = 1.0e-5
    const EXPECTED_CORRECTION_DECAY = 2.0
    const EXPECTED_TARGET_MAX_APE = 10.0

    const PARAMETER_NAMES = ("rho", "r_star", "xi_pi", "xi_gamma")
    const EXPECTED_PARAMETER_BOUNDS = Dict(
        "rho" => (0.7, 0.99),
        "r_star" => (-0.005, 0.003),
        "xi_pi" => (0.5, 1.5),
        "xi_gamma" => (0.0, 1.25),
    )
    const EXPECTED_REGULARIZATION_SCALES = Dict(
        "rho" => 0.1,
        "r_star" => 0.003,
        "xi_pi" => 0.5,
        "xi_gamma" => 0.5,
    )
    const EXPECTED_REGULARIZATION_WEIGHT = 0.002
    const EXPECTED_OUTPUT_BIAS_AMPLITUDE_BOUND = 0.75
    const EXPECTED_OUTPUT_BIAS_REGULARIZATION = 1.0e-4
    const CORRECTABLE_SERIES = (
        "real_gdp",
        "real_household_consumption",
        "real_government_consumption",
        "real_fixed_capitalformation",
        "real_exports",
        "real_imports",
        "wages",
    )
    const DASHBOARD_SERIES = (
        (
            name = "real_gdp",
            display_name = "Real GDP",
            unit = "million chained 2017 USD per quarter",
        ),
        (
            name = "real_household_consumption",
            display_name = "Real household consumption",
            unit = "million chained 2017 USD per quarter",
        ),
        (
            name = "real_government_consumption",
            display_name = "Real government consumption",
            unit = "million chained 2017 USD per quarter",
        ),
        (
            name = "real_fixed_capitalformation",
            display_name = "Real fixed capital formation",
            unit = "million chained 2017 USD per quarter",
        ),
        (
            name = "real_exports",
            display_name = "Real exports",
            unit = "million chained 2017 USD per quarter",
        ),
        (
            name = "real_imports",
            display_name = "Real imports",
            unit = "million chained 2017 USD per quarter",
        ),
        (
            name = "wages",
            display_name = "Nominal wages",
            unit = "million current USD per quarter",
        ),
        (
            name = "gdp_deflator",
            display_name = "GDP deflator",
            unit = "nominal GDP / real GDP ratio",
        ),
        (
            name = "annual_policy_rate",
            display_name = "Federal funds rate",
            unit = "percentage points",
        ),
    )
    const RAW_MODEL_SERIES = (
        :real_gdp,
        :real_household_consumption,
        :real_government_consumption,
        :real_fixed_capitalformation,
        :real_exports,
        :real_imports,
        :wages,
        :nominal_gdp,
        :euribor,
        :real_gdp_ea,
        :gdp_deflator_growth_ea,
    )
    const CLI_ALLOWLIST =
        Set(["config", "output-dir", "n-sims", "seed", "forecast-horizon"])

    function parse_quarter(value::AbstractString)
        matched = match(r"^(\d{4})-?Q([1-4])$", String(value))
        matched === nothing &&
            error("Invalid quarter '$value'; expected YYYYQ[1-4] or YYYY-Q[1-4]")
        year_value = parse(Int, matched.captures[1])
        quarter_value = parse(Int, matched.captures[2])
        return lastdayofquarter(Date(year_value, 3 * quarter_value, 1))
    end

    function config_number(config, section, key)
        table = get(config, section, nothing)
        table isa AbstractDict ||
            error("Calibration config is missing [$section]")
        value = get(table, key, nothing)
        value isa Real ||
            error("Calibration config $section.$key must be numeric")
        number = Float64(value)
        isfinite(number) ||
            error("Calibration config $section.$key must be finite")
        return number
    end

    function validate_contract(config::AbstractDict)
        get(config, "schema_version", nothing) == EXPECTED_SCHEMA ||
            error("Unsupported calibration schema")
        date_expectations = Dict(
            "truth_start" => EXPECTED_TRUTH_START,
            "measurement_anchor" => EXPECTED_MEASUREMENT_ANCHOR,
            "target_start" => EXPECTED_TARGET_START,
            "training_end" => EXPECTED_TRAIN_END,
            "holdout_start" => EXPECTED_HOLDOUT_START,
            "target_end" => EXPECTED_TARGET_END,
        )
        for (key, expected) in date_expectations
            haskey(config, key) ||
                error("Calibration config is missing $key")
            parse_quarter(String(config[key])) == expected ||
                error("Calibration config $key must equal $(quarter_label(expected))")
        end
        parse_quarter(String(config["target_start"])) ==
            lastdayofquarter(
            parse_quarter(String(config["measurement_anchor"])) + Month(3),
        ) ||
            error("The first scored target must immediately follow the measurement anchor")
        parse_quarter(String(config["holdout_start"])) ==
            lastdayofquarter(
            parse_quarter(String(config["training_end"])) + Month(3),
        ) ||
            error("The holdout must immediately follow the fitting sample")

        integer_expectations = Dict(
            "ensemble_size" => DEFAULT_SIMS,
            "backtest_seed" => DEFAULT_SEED,
            "forecast_seed" => DEFAULT_SEED + 50_000,
            "backtest_horizon" => DEFAULT_BACKTEST_HORIZON,
            "forecast_horizon" => DEFAULT_FORECAST_HORIZON,
        )
        for (key, expected) in integer_expectations
            value = get(config, key, nothing)
            value isa Integer ||
                error("Calibration config $key must be an integer")
            value == expected ||
                error("Calibration config $key must equal $expected")
        end
        config["ensemble_size"] > 1 ||
            error("Calibration ensemble_size must exceed one")
        config["backtest_horizon"] == 1 ||
            error("Rolling back-test horizon must equal one quarter")
        config["forecast_horizon"] >= 1 ||
            error("Forecast horizon must be positive")
        get(config, "common_seed_schedule", nothing) === true ||
            error("Calibration config must use the common seed schedule")
        get(config, "real_time_vintage_claim", nothing) === false ||
            error("Calibration config must not claim a real-time-vintage back-test")
        isempty(strip(String(get(config, "truth_file", "")))) &&
            error("Calibration config truth_file must not be empty")
        isempty(strip(String(get(config, "truth_vintage", "")))) &&
            error("Calibration config truth_vintage must not be empty")
        truth_sha256 = String(get(config, "truth_sha256", ""))
        occursin(r"^[0-9a-f]{64}$", truth_sha256) ||
            error("Calibration config truth_sha256 must be 64 lowercase hex characters")

        Float64(get(config, "model_scale", NaN)) == EXPECTED_MODEL_SCALE ||
            error("Calibration config model_scale disagrees with the model contract")
        source_scale = Float64(
            TOML.parsefile(joinpath(REPO_ROOT, "scripts", "us", "sources.toml"))[
                "pipeline",
            ]["scale"],
        )
        Float64(config["model_scale"]) == source_scale ||
            error("Calibration config model_scale disagrees with sources.toml")
        Float64(get(config, "target_max_ape_pct", NaN)) ==
            EXPECTED_TARGET_MAX_APE ||
            error("Calibration config target_max_ape_pct disagrees with the target")
        Float64(get(config, "correction_decay", NaN)) ==
            EXPECTED_CORRECTION_DECAY ||
            error("Calibration config correction_decay disagrees with the web adapter")

        bounds = get(config, "parameter_bounds", nothing)
        bounds isa AbstractDict ||
            error("Calibration config is missing [parameter_bounds]")
        scales = get(config, "regularization_scales", nothing)
        scales isa AbstractDict ||
            error("Calibration config is missing [regularization_scales]")
        overrides = get(config, "parameter_overrides", nothing)
        overrides isa AbstractDict ||
            error("Calibration config is missing [parameter_overrides]")
        Set(String.(keys(bounds))) == Set(PARAMETER_NAMES) ||
            error("Calibration parameter bounds do not match the policy-rule parameters")
        Set(String.(keys(scales))) == Set(PARAMETER_NAMES) ||
            error("Calibration regularization scales do not match the policy-rule parameters")
        Set(String.(keys(overrides))) == Set(PARAMETER_NAMES) ||
            error("Calibration overrides do not match the policy-rule parameters")
        for name in PARAMETER_NAMES
            entry = bounds[name]
            entry isa AbstractDict ||
                error("Parameter bound $name must be a table")
            configured = (
                Float64(get(entry, "lower", NaN)),
                Float64(get(entry, "upper", NaN)),
            )
            configured == EXPECTED_PARAMETER_BOUNDS[name] ||
                error("Parameter bounds for $name disagree with the optimizer")
            scale = Float64(scales[name])
            scale == EXPECTED_REGULARIZATION_SCALES[name] ||
                error("Regularization scale for $name disagrees with the optimizer")
            value = Float64(overrides[name])
            isfinite(value) && configured[1] <= value <= configured[2] ||
                error("Parameter override $name is outside its configured bounds")
        end
        config_number(config, "optimization", "regularization_weight") ==
            EXPECTED_REGULARIZATION_WEIGHT ||
            error("Optimizer regularization weight disagrees with the contract")
        config_number(config, "output_correction_constraints", "amplitude_bound") ==
            EXPECTED_OUTPUT_BIAS_AMPLITUDE_BOUND ||
            error("Output-correction amplitude bound disagrees with the contract")
        config_number(config, "output_correction_constraints", "regularization") ==
            EXPECTED_OUTPUT_BIAS_REGULARIZATION ||
            error("Output-correction regularization disagrees with the contract")

        corrections = get(config, "output_corrections", nothing)
        corrections isa AbstractDict ||
            error("Calibration config is missing [output_corrections]")
        Set(String.(keys(corrections))) == Set(CORRECTABLE_SERIES) ||
            error("Output corrections must cover the seven origin-anchored level series")
        for name in CORRECTABLE_SERIES
            correction = corrections[name]
            get(correction, "method", nothing) == "damped_log_bias" ||
                error("Output correction $name must use damped_log_bias")
            amplitude = Float64(get(correction, "amplitude", NaN))
            decay = Float64(get(correction, "decay", NaN))
            origin_horizon = get(correction, "origin_horizon", nothing)
            isfinite(amplitude) &&
                abs(amplitude) <= EXPECTED_OUTPUT_BIAS_AMPLITUDE_BOUND ||
                error("Output correction $name has an invalid amplitude")
            decay == EXPECTED_CORRECTION_DECAY ||
                error("Output correction $name has an invalid decay")
            origin_horizon isa Integer &&
                !(origin_horizon isa Bool) && origin_horizon == 0 ||
                error("Output correction $name must start at horizon zero")
        end
        return config
    end

    function load_contract(path::String = DEFAULT_CONFIG_PATH)
        isfile(path) || error("Calibration config is not installed: $path")
        return validate_contract(TOML.parsefile(path))
    end

    quarter_label(date::Date) = "$(year(date))Q$(quarterofyear(date))"

    function quarter_dates(start::Date, horizon::Integer)
        return [lastdayofquarter(start + Month(3 * step)) for step in 0:horizon]
    end

    function contract_dates(config)
        truth_start = parse_quarter(String(config["truth_start"]))
        measurement_anchor = parse_quarter(String(config["measurement_anchor"]))
        target_start = parse_quarter(String(config["target_start"]))
        training_end = parse_quarter(String(config["training_end"]))
        holdout_start = parse_quarter(String(config["holdout_start"]))
        target_end = parse_quarter(String(config["target_end"]))
        function quarterly_sequence(start_date, end_date)
            dates = Date[]
            current = start_date
            while current <= end_date
                push!(dates, current)
                current = lastdayofquarter(current + Month(3))
            end
            return dates
        end
        truth_dates = quarterly_sequence(truth_start, target_end)
        target_dates = quarterly_sequence(target_start, target_end)
        origin_dates =
            lastdayofquarter.(target_dates .- Month(3))
        training_dates = quarterly_sequence(target_start, training_end)
        holdout_dates = quarterly_sequence(holdout_start, target_end)
        return (;
            truth_start,
            measurement_anchor,
            target_start,
            training_end,
            holdout_start,
            target_end,
            truth_dates,
            target_dates,
            origin_dates,
            training_dates,
            holdout_dates,
        )
    end

    function split_labels(periods, config)
        dates = contract_dates(config)
        labels = String[]
        for period in periods
            if period == dates.measurement_anchor
                push!(labels, "released_anchor")
            elseif period in dates.training_dates
                push!(labels, "coefficient_fitting")
            elseif period in dates.holdout_dates
                push!(labels, "excluded_from_coefficient_fitting")
            else
                error("Period $period is outside the scoring design")
            end
        end
        return labels
    end

    function read_scoring_truth(path::String, config)
        isfile(path) || error("Frozen scoring truth is not installed: $path")
        frame = CSV.read(path, DataFrame)
        :period in propertynames(frame) ||
            error("Frozen scoring truth is missing period")
        if :wages ∉ propertynames(frame) && :nominal_wages in propertynames(frame)
            rename!(frame, :nominal_wages => :wages)
        end
        required = Symbol.(("period", (entry.name for entry in DASHBOARD_SERIES)...))
        missing_columns = setdiff(required, propertynames(frame))
        isempty(missing_columns) ||
            error(
            "Frozen scoring truth is missing $(join(String.(missing_columns), ", "))",
        )

        parsed_periods = Date[]
        for value in frame.period
            value isa Missing &&
                error("Frozen scoring truth contains a missing period")
            try
                push!(
                    parsed_periods,
                    value isa Date ? value :
                        value isa DateTime ? Date(value) : Date(String(value)),
                )
            catch
                error("Frozen scoring truth contains an invalid period: $value")
            end
        end
        frame.period = parsed_periods
        length(unique(frame.period)) == nrow(frame) ||
            error("Frozen scoring truth contains duplicate periods")
        sort!(frame, :period)
        expected = contract_dates(config).truth_dates
        frame.period == expected ||
            error(
            "Frozen scoring truth must contain exactly $(quarter_label(first(expected))) through $(quarter_label(last(expected))) with no gaps or extra rows",
        )
        for name in Symbol.(entry.name for entry in DASHBOARD_SERIES)
            column = frame[!, name]
            any(ismissing, column) &&
                error("Frozen scoring truth $name contains missing values")
            values = try
                Float64.(column)
            catch
                error("Frozen scoring truth $name must be numeric")
            end
            all(isfinite, values) ||
                error("Frozen scoring truth $name contains nonfinite values")
            all(>(0), values) ||
                error("Frozen scoring truth $name must be strictly positive")
            frame[!, name] = values
        end
        return frame
    end

    function scoring_truth_path(config, config_path::String)
        configured = String(get(config, "truth_file", ""))
        isempty(configured) ||
            return isabspath(configured) ?
            normpath(configured) : normpath(joinpath(REPO_ROOT, configured))
        error("Calibration config is missing truth_file: $config_path")
    end

    function simulate_ensemble(
            baseline,
            parameters::AbstractDict,
            horizon::Integer,
            n_sims::Integer;
            seed::Integer = DEFAULT_SEED,
            assimilated_policy_rate::Union{Nothing, Float64} = nothing,
            assimilated_policy_step::Integer = 1,
        )
        paths = Dict(
            name => zeros(Float64, horizon + 1, n_sims)
                for name in RAW_MODEL_SERIES
        )
        for simulation in 1:n_sims
            Random.seed!(seed + simulation)
            model = Bit.Model(
                deepcopy(Dict{String, Any}(parameters)),
                deepcopy(baseline.initial_conditions),
            )
            for step in 1:horizon
                Bit.step!(model; parallel = false)
                if step == assimilated_policy_step &&
                        assimilated_policy_rate !== nothing
                    model.cb.r_bar =
                        (1 + assimilated_policy_rate)^(1 / 4) - 1
                    model.bank.r = model.cb.r_bar + model.prop.mu
                end
                Bit.collect_data!(model)
            end
            for name in RAW_MODEL_SERIES
                paths[name][:, simulation] .= getproperty(model.data, name)
            end
        end
        return paths
    end

    function rebase_levels(raw::AbstractMatrix, actual_origin::Real; origin_index::Integer = 1)
        denominators = reshape(raw[origin_index, :], 1, :)
        all(isfinite, denominators) || error("Model origin contains nonfinite values")
        all(!iszero, denominators) || error("Model origin contains zero values")
        return Float64(actual_origin) .* raw ./ denominators
    end

    """
        fit_damped_log_bias(raw_paths, actual, training_indices)

    Estimate a bounded, saturating observation bridge on training quarters only.
    For forecast horizon `h > 0`, the published path is multiplied by
    `exp(amplitude * (1 - exp(-decay * h)))`; the origin is unchanged. This
    absorbs the reproducible initialization transient without forcing the ABM's
    long-run growth rate to equal a fitted linear trend.
    """
    function fit_damped_log_bias(
            raw_paths,
            actual,
            training_indices;
            amplitude_bound::Real = EXPECTED_OUTPUT_BIAS_AMPLITUDE_BOUND,
            decay_bounds = (0.02, EXPECTED_CORRECTION_DECAY),
            regularization::Real = EXPECTED_OUTPUT_BIAS_REGULARIZATION,
        )
        raw_mean = vec(mean(raw_paths; dims = 2))
        horizons = Float64.(training_indices .- 1)
        errors = log.(Float64.(actual[training_indices]) ./ raw_mean[training_indices])
        all(isfinite, errors) || error("Output-bias training errors are nonfinite")

        lower, upper = decay_bounds
        best = nothing
        evaluations = 0
        for pass in 1:4
            for decay in range(lower, upper; length = pass == 1 ? 401 : 201)
                loadings = 1 .- exp.(-decay .* horizons)
                denominator = sum(abs2, loadings) +
                    regularization / amplitude_bound^2
                amplitude = clamp(
                    dot(loadings, errors) / denominator,
                    -amplitude_bound,
                    amplitude_bound,
                )
                residuals = errors .- amplitude .* loadings
                loss = mean(abs2, residuals) +
                    regularization * (amplitude / amplitude_bound)^2
                evaluations += 1
                if best === nothing || loss < best.loss
                    best = (; amplitude, decay, loss)
                end
            end
            width = (upper - lower) / 10
            lower = max(decay_bounds[1], best.decay - width)
            upper = min(decay_bounds[2], best.decay + width)
        end
        return merge(best, (; evaluations))
    end

    function fit_one_step_log_bias(
            raw_paths::AbstractMatrix,
            actual,
            fitting_indices;
            decay::Real,
            amplitude_bound::Real,
            regularization::Real,
        )
        isempty(fitting_indices) &&
            error("At least one coefficient-fitting observation is required")
        all(index -> index > 1, fitting_indices) ||
            error("The released anchor cannot be used for coefficient fitting")
        raw_mean = vec(mean(raw_paths; dims = 2))
        errors =
            log.(Float64.(actual[fitting_indices]) ./ raw_mean[fitting_indices])
        all(isfinite, errors) ||
            error("One-step output-bias training errors are nonfinite")
        loading = 1 - exp(-Float64(decay))
        denominator =
            length(errors) * loading^2 + regularization / amplitude_bound^2
        amplitude = clamp(
            loading * sum(errors) / denominator,
            -amplitude_bound,
            amplitude_bound,
        )
        residuals = errors .- amplitude * loading
        loss = mean(abs2, residuals) +
            regularization * (amplitude / amplitude_bound)^2
        return (;
            amplitude,
            decay = Float64(decay),
            loss,
            evaluations = 1,
        )
    end

    function apply_one_step_log_bias(raw_paths::AbstractMatrix, correction)
        factors = ones(Float64, size(raw_paths, 1))
        factors[2:end] .= exp(
            correction.amplitude * (1 - exp(-correction.decay)),
        )
        return raw_paths .* reshape(factors, :, 1)
    end

    function apply_damped_log_bias(
            raw_paths::AbstractMatrix,
            correction;
            origin_horizon::Integer = 0,
        )
        origin_horizon >= 0 ||
            error("Output-correction origin horizon must be nonnegative")
        factors = [
            horizon == 0 ? 1.0 :
                exp(
                    correction.amplitude * (
                        exp(-correction.decay * origin_horizon) -
                        exp(
                            -correction.decay *
                            (origin_horizon + horizon),
                        )
                    ),
                )
                for horizon in 0:(size(raw_paths, 1) - 1)
        ]
        return raw_paths .* reshape(factors, :, 1)
    end

    annualize_rate(quarterly) = (1 .+ quarterly) .^ 4 .- 1

    function policy_paths_from_drivers(
            quarterly_start::Real,
            gdp_ea::AbstractMatrix,
            inflation::AbstractMatrix,
            candidate::AbstractDict,
            pi_star::Real,
        )
        horizon, n_sims = size(gdp_ea, 1) - 1, size(gdp_ea, 2)
        rates = zeros(Float64, horizon + 1, n_sims)
        rates[1, :] .= quarterly_start
        rho = Float64(candidate["rho"])
        r_star = Float64(candidate["r_star"])
        xi_pi = Float64(candidate["xi_pi"])
        xi_gamma = Float64(candidate["xi_gamma"])
        for simulation in 1:n_sims, step in 2:(horizon + 1)
            growth = gdp_ea[step, simulation] / gdp_ea[step - 1, simulation] - 1
            rate = rho * rates[step - 1, simulation] +
                (1 - rho) * (
                r_star + pi_star +
                    xi_pi * (inflation[step, simulation] - pi_star) +
                    xi_gamma * growth
            )
            rates[step, simulation] = max(0.0, rate)
        end
        return annualize_rate(rates)
    end

    function center_vector(parameters)
        return Dict(name => Float64(parameters[name]) for name in PARAMETER_NAMES)
    end

    function uncalibrated_parameters(baseline)
        parameters = deepcopy(baseline.parameters)
        calibration = get(
            baseline.metadata,
            "forecast_calibration",
            Dict{String, Any}(),
        )
        estimated = get(
            calibration,
            "estimated_parameters",
            Dict{String, Any}(),
        )
        for name in PARAMETER_NAMES
            haskey(estimated, name) &&
                (parameters[name] = Float64(estimated[name]))
        end
        return parameters
    end

    function regularization(candidate, center, scales)
        return sum(
            (
                    (Float64(candidate[name]) - center[name]) /
                    scales[name]
                )^2 for name in PARAMETER_NAMES
        )
    end

    function rolling_policy_forecasts(
            quarterly_starts,
            growth,
            inflation,
            candidate,
            pi_stars,
        )
        size(growth) == size(inflation) ||
            error("Rolling policy drivers must have identical shapes")
        length(quarterly_starts) == size(growth, 1) ||
            error("A policy-rate origin is required for every rolling target")
        length(pi_stars) == size(growth, 1) ||
            error("A policy target is required for every rolling target")
        quarterly = similar(growth, Float64)
        rho = Float64(candidate["rho"])
        r_star = Float64(candidate["r_star"])
        xi_pi = Float64(candidate["xi_pi"])
        xi_gamma = Float64(candidate["xi_gamma"])
        for row in axes(growth, 1), simulation in axes(growth, 2)
            quarterly[row, simulation] = max(
                0.0,
                rho * quarterly_starts[row] +
                    (1 - rho) * (
                    r_star + pi_stars[row] +
                        xi_pi * (inflation[row, simulation] - pi_stars[row]) +
                        xi_gamma * growth[row, simulation]
                ),
            )
        end
        return annualize_rate(quarterly)
    end

    function rolling_rate_objective(
            candidate,
            center,
            quarterly_starts,
            growth,
            inflation,
            pi_stars,
            actual_rates,
            fitting_indices,
            scales,
            regularization_weight,
        )
        forecasts = rolling_policy_forecasts(
            quarterly_starts,
            growth,
            inflation,
            candidate,
            pi_stars,
        )
        mean_forecast = vec(mean(forecasts; dims = 2))
        relative_errors = abs.(
            mean_forecast[fitting_indices] .-
                actual_rates[fitting_indices]
        ) ./ abs.(actual_rates[fitting_indices])
        forecast_loss = mean(relative_errors) + 0.25 * maximum(relative_errors)
        return forecast_loss +
            regularization_weight * regularization(candidate, center, scales)
    end

    function axis_grid(lower, upper, center, points)
        values = collect(range(lower, upper; length = points))
        push!(values, clamp(center, lower, upper))
        return sort!(unique(values))
    end

    function optimize_rolling_policy_rule(
            center,
            quarterly_starts,
            growth,
            inflation,
            pi_stars,
            actual_rates,
            fitting_indices,
            parameter_bounds,
            scales,
            regularization_weight,
        )
        bounds = deepcopy(parameter_bounds)
        best = deepcopy(center)
        best_loss = Inf
        evaluations = 0
        for pass in 1:4
            points = pass == 1 ? 7 : 5
            grids = Dict(
                name => axis_grid(
                        bounds[name][1],
                        bounds[name][2],
                        best[name],
                        points,
                    ) for name in PARAMETER_NAMES
            )
            for rho in grids["rho"],
                    r_star in grids["r_star"],
                    xi_pi in grids["xi_pi"],
                    xi_gamma in grids["xi_gamma"]
                candidate = Dict(
                    "rho" => rho,
                    "r_star" => r_star,
                    "xi_pi" => xi_pi,
                    "xi_gamma" => xi_gamma,
                )
                loss = rolling_rate_objective(
                    candidate,
                    center,
                    quarterly_starts,
                    growth,
                    inflation,
                    pi_stars,
                    actual_rates,
                    fitting_indices,
                    scales,
                    regularization_weight,
                )
                evaluations += 1
                if loss < best_loss
                    best_loss = loss
                    best = candidate
                end
            end
            for name in PARAMETER_NAMES
                lower, upper = bounds[name]
                half_width = (upper - lower) / 4
                global_lower, global_upper = parameter_bounds[name]
                bounds[name] = (
                    max(global_lower, best[name] - half_width),
                    min(global_upper, best[name] + half_width),
                )
            end
        end
        return best, best_loss, evaluations
    end

    function configured_parameter_bounds(config)
        return Dict(
            name => (
                    Float64(config["parameter_bounds"][name]["lower"]),
                    Float64(config["parameter_bounds"][name]["upper"]),
                ) for name in PARAMETER_NAMES
        )
    end

    function configured_regularization_scales(config)
        return Dict(
            name => Float64(config["regularization_scales"][name])
                for name in PARAMETER_NAMES
        )
    end

    function configured_parameters(config)
        return Dict(
            name => Float64(config["parameter_overrides"][name])
                for name in PARAMETER_NAMES
        )
    end

    function configured_output_corrections(config)
        return Dict(
            name => (
                    amplitude =
                    Float64(config["output_corrections"][name]["amplitude"]),
                    decay = Float64(config["output_corrections"][name]["decay"]),
                    loss = NaN,
                    evaluations = 0,
                ) for name in CORRECTABLE_SERIES
        )
    end

    function validate_fitted_parameters(fitted, configured; atol::Real = 1.0e-12)
        for name in PARAMETER_NAMES
            isapprox(fitted[name], configured[name]; atol, rtol = 0) ||
                error(
                "Fitted policy parameter $name=$(fitted[name]) disagrees with the authoritative config value $(configured[name])",
            )
        end
        return true
    end

    function validate_fitted_corrections(fitted, configured; atol::Real = 1.0e-12)
        Set(keys(fitted)) == Set(keys(configured)) ||
            error("Fitted output-correction series disagree with the config")
        for name in keys(fitted)
            isapprox(
                fitted[name].amplitude,
                configured[name].amplitude;
                atol,
                rtol = 0,
            ) ||
                error(
                "Fitted output correction $name disagrees with the authoritative config",
            )
            fitted[name].decay == configured[name].decay ||
                error("Fitted output-correction decay for $name disagrees with the config")
        end
        return true
    end

    function unique_truth_row(truth::DataFrame, period::Date)
        rows = truth[truth.period .== period, :]
        nrow(rows) == 1 ||
            error("Frozen scoring truth must contain a unique $period row")
        return only(eachrow(rows))
    end

    function anchor_dashboard_paths(raw, origin_truth; origin_index::Integer = 1)
        anchored = Dict{String, Matrix{Float64}}()
        for name in CORRECTABLE_SERIES
            anchored[name] = rebase_levels(
                raw[Symbol(name)],
                Float64(origin_truth[Symbol(name)]);
                origin_index,
            )
        end
        nominal_origin =
            Float64(origin_truth.real_gdp) * Float64(origin_truth.gdp_deflator)
        anchored["nominal_gdp"] = rebase_levels(
            raw[:nominal_gdp],
            nominal_origin;
            origin_index,
        )
        anchored["gdp_deflator"] =
            anchored["nominal_gdp"] ./ anchored["real_gdp"]
        anchored["annual_policy_rate"] = annualize_rate(raw[:euribor])
        anchored["annual_policy_rate"][origin_index, :] .=
            Float64(origin_truth.annual_policy_rate)
        return anchored
    end

    function rolling_one_step_paths(
            calibration_object,
            truth::DataFrame,
            config;
            n_sims::Integer,
            seed::Integer,
        )
        dates = contract_dates(config)
        backtest_dates = [dates.measurement_anchor; dates.target_dates]
        path_count = length(backtest_dates)
        paths = Dict(
            name => zeros(Float64, path_count, n_sims)
                for name in (
                    CORRECTABLE_SERIES...,
                    "nominal_gdp",
                    "gdp_deflator",
                    "annual_policy_rate",
                )
        )
        anchor_truth = unique_truth_row(truth, dates.measurement_anchor)
        for name in keys(paths)
            if name == "nominal_gdp"
                paths[name][1, :] .=
                    anchor_truth.real_gdp * anchor_truth.gdp_deflator
            else
                paths[name][1, :] .= anchor_truth[Symbol(name)]
            end
        end

        target_count = length(dates.target_dates)
        growth = zeros(Float64, target_count, n_sims)
        inflation = zeros(Float64, target_count, n_sims)
        quarterly_starts = zeros(Float64, target_count)
        pi_stars = zeros(Float64, target_count)
        origin_periods = String[quarter_label(dates.measurement_anchor)]
        for (target_index, (origin, target)) in
            enumerate(zip(dates.origin_dates, dates.target_dates))
            parameters, initial_conditions =
                Bit.get_params_and_initial_conditions(
                calibration_object,
                DateTime(origin);
                scale = Float64(config["model_scale"]),
                use_growth_rate_ar1 = false,
            )
            raw = simulate_ensemble(
                (;
                    parameters,
                    initial_conditions,
                ),
                parameters,
                Int(config["backtest_horizon"]),
                n_sims;
                seed,
            )
            origin_truth = unique_truth_row(truth, origin)
            anchored = anchor_dashboard_paths(raw, origin_truth)
            target_row = target_index + 1
            for name in keys(paths)
                paths[name][target_row, :] .= anchored[name][2, :]
            end
            growth[target_index, :] .=
                raw[:real_gdp_ea][2, :] ./ raw[:real_gdp_ea][1, :] .- 1
            inflation[target_index, :] .=
                raw[:gdp_deflator_growth_ea][2, :]
            quarterly_starts[target_index] =
                (1 + Float64(origin_truth.annual_policy_rate))^(1 / 4) - 1
            pi_stars[target_index] = Float64(parameters["pi_star"])
            push!(origin_periods, quarter_label(origin))
            target == backtest_dates[target_row] ||
                error("Rolling target-date alignment failed")
        end
        return (;
            dates = backtest_dates,
            origin_periods,
            paths,
            growth,
            inflation,
            quarterly_starts,
            pi_stars,
        )
    end

    function apply_rolling_corrections(paths, corrections)
        corrected = deepcopy(paths)
        for name in CORRECTABLE_SERIES
            corrected[name] =
                apply_one_step_log_bias(paths[name], corrections[name])
        end
        corrected["gdp_deflator"] =
            corrected["nominal_gdp"] ./ corrected["real_gdp"]
        return corrected
    end

    function row_quantiles(matrix::AbstractMatrix)
        return (
            mean = vec(mean(matrix; dims = 2)),
            p10 = [quantile(view(matrix, row, :), 0.1) for row in axes(matrix, 1)],
            p90 = [quantile(view(matrix, row, :), 0.9) for row in axes(matrix, 1)],
        )
    end

    function pin_summary_anchor!(summary, value::Real)
        anchor = Float64(value)
        summary.mean[1] = anchor
        summary.p10[1] = anchor
        summary.p90[1] = anchor
        return summary
    end

    function safe_mape(forecast, actual)
        all(!iszero, actual) || error("MAPE is undefined for zero actual values")
        return 100 * mean(abs.(forecast .- actual) ./ abs.(actual))
    end

    function safe_max_ape(forecast, actual)
        all(!iszero, actual) || error("APE is undefined for zero actual values")
        return 100 * maximum(abs.(forecast .- actual) ./ abs.(actual))
    end

    function score_frame(
            backtest::DataFrame,
            model_stage::String;
            target_max_ape_pct::Real = EXPECTED_TARGET_MAX_APE,
        )
        model_stage in ("uncalibrated", "calibrated") ||
            error("Unknown model stage $model_stage")
        forecast_prefix = model_stage == "calibrated" ? "forecast" : "uncalibrated"
        rows = DataFrame(
            model_stage = String[],
            metric = String[],
            sample = String[],
            observations = Int[],
            mape_pct = Union{Missing, Float64}[],
            max_ape_pct = Union{Missing, Float64}[],
            mae = Float64[],
            rmse = Float64[],
            error_unit = String[],
            target_met = Bool[],
        )
        samples = Dict(
            "all_forecasts" => backtest.split .!= "released_anchor",
            "coefficient_fitting" =>
                backtest.split .== "coefficient_fitting",
            "excluded_from_coefficient_fitting" =>
                backtest.split .== "excluded_from_coefficient_fitting",
        )
        for (sample, mask) in samples, specification in DASHBOARD_SERIES
            actual_column = Symbol("actual_$(specification.name)")
            forecast_column =
                Symbol("$(forecast_prefix)_$(specification.name)_mean")
            actual = Float64.(backtest[mask, actual_column])
            forecast = Float64.(backtest[mask, forecast_column])
            isempty(actual) && continue
            errors = forecast .- actual
            mae = specification.name == "annual_policy_rate" ?
                100 * mean(abs.(errors)) : mean(abs.(errors))
            rmse = specification.name == "annual_policy_rate" ?
                100 * sqrt(mean(errors .^ 2)) : sqrt(mean(errors .^ 2))
            mape = safe_mape(forecast, actual)
            max_ape = safe_max_ape(forecast, actual)
            push!(
                rows,
                (
                    model_stage = model_stage,
                    metric = specification.name,
                    sample = sample,
                    observations = length(actual),
                    mape_pct = mape,
                    max_ape_pct = max_ape,
                    mae = mae,
                    rmse = rmse,
                    error_unit = specification.unit,
                    target_met = max_ape < target_max_ape_pct,
                ),
            )
        end
        return rows
    end

    function build_backtest_frame(
            actuals,
            dates,
            origin_periods,
            paths,
            uncalibrated_paths,
            config,
        )
        selected = actuals[in.(actuals.period, Ref(dates)), :]
        sort!(selected, :period)
        selected.period == dates || error("Actuals do not cover every backtest quarter")
        length(origin_periods) == length(dates) ||
            error("A rolling origin is required for each back-test row")
        frame = DataFrame(
            period = dates,
            quarter = quarter_label.(dates),
            split = split_labels(dates, config),
            origin_period = origin_periods,
        )
        for specification in DASHBOARD_SERIES
            name = specification.name
            actual = Float64.(selected[!, Symbol(name)])
            calibrated = row_quantiles(paths[name])
            uncalibrated = row_quantiles(uncalibrated_paths[name])
            pin_summary_anchor!(calibrated, first(actual))
            pin_summary_anchor!(uncalibrated, first(actual))
            frame[!, Symbol("actual_$name")] = actual
            frame[!, Symbol("forecast_$(name)_mean")] = calibrated.mean
            frame[!, Symbol("forecast_$(name)_p10")] = calibrated.p10
            frame[!, Symbol("forecast_$(name)_p90")] = calibrated.p90
            frame[!, Symbol("$(name)_ape_pct")] =
                100 .* abs.(calibrated.mean .- actual) ./ abs.(actual)
            frame[!, Symbol("uncalibrated_$(name)_mean")] =
                uncalibrated.mean
            frame[!, Symbol("uncalibrated_$(name)_ape_pct")] =
                100 .* abs.(uncalibrated.mean .- actual) ./ abs.(actual)
        end
        frame[!, :annual_policy_rate_error_pp] =
            100 .* (
            frame.forecast_annual_policy_rate_mean .-
                frame.actual_annual_policy_rate
        )
        # Stable aliases retain compatibility with the first report revision.
        frame[!, :actual_policy_rate_annual] =
            frame.actual_annual_policy_rate
        frame[!, :forecast_policy_rate_annual_mean] =
            frame.forecast_annual_policy_rate_mean
        frame[!, :forecast_policy_rate_annual_p10] =
            frame.forecast_annual_policy_rate_p10
        frame[!, :forecast_policy_rate_annual_p90] =
            frame.forecast_annual_policy_rate_p90
        frame[!, :policy_rate_ape_pct] =
            frame.annual_policy_rate_ape_pct
        frame[!, :policy_rate_error_pp] =
            frame.annual_policy_rate_error_pp
        frame[!, :uncalibrated_policy_rate_annual_mean] =
            frame.uncalibrated_annual_policy_rate_mean
        frame[!, :uncalibrated_policy_rate_annual_ape_pct] =
            frame.uncalibrated_annual_policy_rate_ape_pct
        return frame
    end

    function output_corrections_frame(
            corrections;
            amplitude_bound::Real = EXPECTED_OUTPUT_BIAS_AMPLITUDE_BOUND,
            decay::Real = EXPECTED_CORRECTION_DECAY,
        )
        rows = DataFrame(
            series = String[],
            amplitude = Float64[],
            decay = Float64[],
            loss = Float64[],
            evaluations = Int[],
            amplitude_lower_bound = Float64[],
            amplitude_upper_bound = Float64[],
            decay_lower_bound = Float64[],
            decay_upper_bound = Float64[],
        )
        for name in sort!(collect(keys(corrections)))
            correction = corrections[name]
            push!(
                rows,
                (
                    series = name,
                    amplitude = correction.amplitude,
                    decay = correction.decay,
                    loss = correction.loss,
                    evaluations = correction.evaluations,
                    amplitude_lower_bound = -amplitude_bound,
                    amplitude_upper_bound = amplitude_bound,
                    decay_lower_bound = decay,
                    decay_upper_bound = decay,
                ),
            )
        end
        return rows
    end

    function calibrated_parameters_frame(original, optimized, parameter_bounds)
        frame = DataFrame(
            parameter = String[],
            original = Float64[],
            optimized = Float64[],
            lower_bound = Float64[],
            upper_bound = Float64[],
            percent_change = Float64[],
        )
        for name in PARAMETER_NAMES
            lower, upper = parameter_bounds[name]
            push!(
                frame,
                (
                    parameter = name,
                    original = original[name],
                    optimized = optimized[name],
                    lower_bound = lower,
                    upper_bound = upper,
                    percent_change = 100 * (optimized[name] / original[name] - 1),
                ),
            )
        end
        return frame
    end

    function future_forecast(
            baseline,
            parameters,
            actuals;
            output_corrections,
            horizon::Integer,
            n_sims::Integer,
            seed::Integer,
            config,
        )
        measurement_date = contract_dates(config).target_end
        measurement_truth = unique_truth_row(actuals, measurement_date)
        structural_origin = parse_quarter(String(baseline.metadata["period"]))
        month_difference =
            12 * (year(measurement_date) - year(structural_origin)) +
            month(measurement_date) - month(structural_origin)
        month_difference >= 0 && month_difference % 3 == 0 ||
            error("Structural origin does not align with the forecast measurement date")
        historical_steps = month_difference ÷ 3
        simulation_horizon = historical_steps + horizon
        raw = simulate_ensemble(
            baseline,
            parameters,
            simulation_horizon,
            n_sims;
            seed,
            assimilated_policy_rate =
                Float64(measurement_truth.annual_policy_rate),
            assimilated_policy_step = historical_steps,
        )
        actual_index = historical_steps + 1
        selected = actual_index:(simulation_horizon + 1)
        published = Dict{String, Matrix{Float64}}()
        for name in CORRECTABLE_SERIES
            reanchored = rebase_levels(
                raw[Symbol(name)],
                Float64(measurement_truth[Symbol(name)]);
                origin_index = actual_index,
            )
            reanchored[actual_index, :] .=
                Float64(measurement_truth[Symbol(name)])
            published[name] = apply_damped_log_bias(
                reanchored[selected, :],
                output_corrections[name],
                origin_horizon = historical_steps,
            )
        end
        nominal = rebase_levels(
            raw[:nominal_gdp],
            Float64(measurement_truth.real_gdp) *
                Float64(measurement_truth.gdp_deflator);
            origin_index = actual_index,
        )
        nominal[actual_index, :] .=
            Float64(measurement_truth.real_gdp) *
            Float64(measurement_truth.gdp_deflator)
        published["nominal_gdp"] = nominal[selected, :]
        published["gdp_deflator"] =
            published["nominal_gdp"] ./ published["real_gdp"]
        policy = annualize_rate(raw[:euribor])
        policy[actual_index, :] .=
            Float64(measurement_truth.annual_policy_rate)
        published["annual_policy_rate"] = policy[selected, :]

        dates = quarter_dates(measurement_date, horizon)
        status = [
            date == measurement_date ? "measurement_reanchored_actual" : "forecast"
                for date in dates
        ]
        frame = DataFrame(
            period = dates,
            quarter = quarter_label.(dates),
            status = status,
        )
        for specification in DASHBOARD_SERIES
            summary = pin_summary_anchor!(
                row_quantiles(published[specification.name]),
                measurement_truth[Symbol(specification.name)],
            )
            frame[!, Symbol("$(specification.name)_mean")] = summary.mean
            frame[!, Symbol("$(specification.name)_p10")] = summary.p10
            frame[!, Symbol("$(specification.name)_p90")] = summary.p90
        end
        frame[!, :policy_rate_annual_mean] =
            frame.annual_policy_rate_mean
        frame[!, :policy_rate_annual_p10] =
            frame.annual_policy_rate_p10
        frame[!, :policy_rate_annual_p90] =
            frame.annual_policy_rate_p90
        return frame
    end

    function write_json(path, value)
        open(path, "w") do io
            JSON.print(io, value, 2)
            write(io, '\n')
        end
        return path
    end

    function file_sha256(path::String)
        isfile(path) || error("Cannot hash missing file: $path")
        return open(path, "r") do io
            bytes2hex(SHA.sha256(io))
        end
    end

    function verify_truth_sha256(path::String, config)
        expected = String(config["truth_sha256"])
        actual = file_sha256(path)
        actual == expected || error(
            "Frozen scoring truth SHA-256 mismatch: expected $expected, got $actual",
        )
        return actual
    end

    function git_revision()
        head = try
            strip(
                read(
                    `git -C $REPO_ROOT rev-parse HEAD`,
                    String,
                ),
            )
        catch
            nothing
        end
        dirty = try
            !isempty(
                strip(
                    read(
                        `git -C $REPO_ROOT status --porcelain --untracked-files=normal`,
                        String,
                    ),
                ),
            )
        catch
            nothing
        end
        return Dict(
            "git_head" => head,
            "working_tree_dirty" => dirty,
            "calibration_script_sha256" => file_sha256(@__FILE__),
        )
    end

    function calibration_gate(metrics::DataFrame)
        selected = metrics[
            (metrics.model_stage .== "calibrated") .&
                in.(
                metrics.sample,
                Ref(
                    [
                        "all_forecasts",
                        "excluded_from_coefficient_fitting",
                    ]
                ),
            ),
            :,
        ]
        expected = Set(
            (name, sample)
                for name in (entry.name for entry in DASHBOARD_SERIES)
                for sample in (
                    "all_forecasts",
                    "excluded_from_coefficient_fitting",
                )
        )
        observed = Set((row.metric, row.sample) for row in eachrow(selected))
        observed == expected ||
            error("Calibration gate does not contain every dashboard series and sample")
        return all(selected.target_met)
    end

    function report_metrics_frame(metrics::DataFrame)
        rows = DataFrame(
            metric = String[],
            display_name = String[],
            display_unit = String[],
            fit_mape_pct = Float64[],
            fit_max_ape_pct = Float64[],
            holdout_mape_pct = Float64[],
            holdout_max_ape_pct = Float64[],
            all_mape_pct = Float64[],
            all_max_ape_pct = Float64[],
            holdout_mae_display = Float64[],
            origin_anchored_holdout_mape_pct = Float64[],
            origin_anchored_holdout_max_ape_pct = Float64[],
            target_met = Bool[],
        )
        calibrated = metrics[metrics.model_stage .== "calibrated", :]
        origin_anchored = metrics[metrics.model_stage .== "uncalibrated", :]
        for specification in DASHBOARD_SERIES
            metric_rows =
                calibrated[calibrated.metric .== specification.name, :]
            origin_anchored_metric_rows = origin_anchored[
                origin_anchored.metric .== specification.name,
                :,
            ]
            function sample_row(rows, sample)
                selected = rows[rows.sample .== sample, :]
                nrow(selected) == 1 ||
                    error(
                    "Report metrics require one $(specification.name) $sample row",
                )
                return only(eachrow(selected))
            end
            fit = sample_row(metric_rows, "coefficient_fitting")
            holdout = sample_row(metric_rows, "excluded_from_coefficient_fitting")
            all_forecasts = sample_row(metric_rows, "all_forecasts")
            origin_anchored_holdout = sample_row(
                origin_anchored_metric_rows,
                "excluded_from_coefficient_fitting",
            )
            push!(
                rows,
                (
                    metric = specification.name,
                    display_name = specification.display_name,
                    display_unit = specification.unit,
                    fit_mape_pct = fit.mape_pct,
                    fit_max_ape_pct = fit.max_ape_pct,
                    holdout_mape_pct = holdout.mape_pct,
                    holdout_max_ape_pct = holdout.max_ape_pct,
                    all_mape_pct = all_forecasts.mape_pct,
                    all_max_ape_pct = all_forecasts.max_ape_pct,
                    holdout_mae_display = holdout.mae,
                    origin_anchored_holdout_mape_pct =
                        origin_anchored_holdout.mape_pct,
                    origin_anchored_holdout_max_ape_pct =
                        origin_anchored_holdout.max_ape_pct,
                    target_met =
                        holdout.target_met && all_forecasts.target_met,
                ),
            )
        end
        return rows
    end

    function result_dictionary(
            backtest,
            metrics,
            parameter_frame,
            correction_frame,
            optimization_loss,
            evaluations,
            config,
            config_path,
            truth_path,
            structural_path,
            forecast_baseline_path,
            calibration_path,
            forecast,
        )
        metric_rows = [
            Dict(String(name) => row[name] for name in propertynames(row))
                for row in eachrow(metrics)
        ]
        parameters = Dict(
            row.parameter => Dict(
                    "original" => row.original,
                    "optimized" => row.optimized,
                    "lower_bound" => row.lower_bound,
                    "upper_bound" => row.upper_bound,
                ) for row in eachrow(parameter_frame)
        )
        output_corrections = Dict(
            row.series => Dict(
                    "amplitude" => row.amplitude,
                    "decay" => row.decay,
                    "formula" =>
                    "factor(h) = exp(amplitude * (1 - exp(-decay * h))) for h > 0; factor(0) = 1",
                ) for row in eachrow(correction_frame)
        )
        dates = contract_dates(config)
        return Dict(
            "schema_version" => "beforeit-us-outlook-calibration.v2",
            "generated_at" => string(now(UTC)),
            "evaluation_design" => Dict(
                "kind" => "current-vintage ex-post rolling one-quarter backtest",
                "released_measurement_anchor" =>
                    quarter_label(dates.measurement_anchor),
                "rolling_origins" =>
                    "$(quarter_label(first(dates.origin_dates)))-$(quarter_label(last(dates.origin_dates)))",
                "scored_targets" =>
                    "$(quarter_label(first(dates.target_dates)))-$(quarter_label(last(dates.target_dates)))",
                "coefficient_fitting" =>
                    "$(quarter_label(first(dates.training_dates)))-$(quarter_label(last(dates.training_dates)))",
                "excluded_from_coefficient_fitting" =>
                    "$(quarter_label(first(dates.holdout_dates)))-$(quarter_label(last(dates.holdout_dates)))",
                "truth_vintage" => String(config["truth_vintage"]),
                "real_time_vintage_claim" => false,
                "ensemble_size" => Int(config["ensemble_size"]),
                "backtest_seed" => Int(config["backtest_seed"]),
                "backtest_horizon_quarters" =>
                    Int(config["backtest_horizon"]),
                "common_seed_schedule" => true,
                "target_periods_are_excluded_from_coefficient_fitting" =>
                    quarter_label.(dates.holdout_dates),
            ),
            "conditional_forecast_design" => Dict(
                "measurement_anchor" => quarter_label(dates.target_end),
                "horizon_quarters" => Int(config["forecast_horizon"]),
                "seed" => Int(config["forecast_seed"]),
                "last_output_period" =>
                    quarter_label(maximum(forecast.period)),
                "measurement_reanchoring" =>
                    "All seven published level series are re-anchored to released 2026Q2 measurements; the GDP deflator is derived from re-anchored nominal GDP divided by corrected real GDP.",
                "state_assimilation" =>
                    "Only the policy-rate state is updated inside the latest 2026Q1 nowcast path at the measurement date.",
                "output_correction_continuation" =>
                    "Damped path factors continue from the nowcast origin and are normalized to one at the 2026Q2 measurement re-anchor.",
            ),
            "objective" => Dict(
                "policy_loss" => optimization_loss,
                "evaluations" => evaluations,
                "regularization_weight" =>
                    Float64(config["optimization"]["regularization_weight"]),
                "forecast_term" =>
                    "coefficient-fitting MAPE + 0.25 * maximum coefficient-fitting APE",
            ),
            "parameters" => parameters,
            "output_corrections" => output_corrections,
            "metrics" => metric_rows,
            "target" => Dict(
                "definition" => "maximum quarterly absolute percentage error below 10% for every Economic outlook series",
                "threshold_pct" => Float64(config["target_max_ape_pct"]),
                "all_metrics_pass" => calibration_gate(metrics),
            ),
            "latest_backtest_quarter" => quarter_label(maximum(backtest.period)),
            "reproducibility" => Dict(
                "config_path" => relpath(config_path, REPO_ROOT),
                "config_sha256" => file_sha256(config_path),
                "truth_path" => relpath(truth_path, REPO_ROOT),
                "truth_sha256" => file_sha256(truth_path),
                "structural_artifact_path" =>
                    relpath(structural_path, REPO_ROOT),
                "structural_artifact_sha256" =>
                    file_sha256(structural_path),
                "forecast_baseline_path" =>
                    relpath(forecast_baseline_path, REPO_ROOT),
                "forecast_baseline_sha256" =>
                    file_sha256(forecast_baseline_path),
                "calibration_artifact_path" =>
                    relpath(calibration_path, REPO_ROOT),
                "calibration_artifact_sha256" =>
                    file_sha256(calibration_path),
                "backtest_seed" => Int(config["backtest_seed"]),
                "backtest_horizon_quarters" =>
                    Int(config["backtest_horizon"]),
                "forecast_seed" => Int(config["forecast_seed"]),
                "forecast_horizon_quarters" =>
                    Int(config["forecast_horizon"]),
                "ensemble_size" => Int(config["ensemble_size"]),
                "code_revision" => git_revision(),
            ),
        )
    end

    function run_calibration(;
            output_dir::String = DEFAULT_OUTPUT_DIR,
            config_path::String = DEFAULT_CONFIG_PATH,
            n_sims::Union{Nothing, Integer} = nothing,
            seed::Union{Nothing, Integer} = nothing,
            forecast_horizon::Union{Nothing, Integer} = nothing,
            enforce_config_agreement::Bool = true,
            fit_only::Bool = false,
        )
        config_path = abspath(config_path)
        config = load_contract(config_path)
        configured_sims = Int(config["ensemble_size"])
        configured_seed = Int(config["backtest_seed"])
        configured_forecast_horizon = Int(config["forecast_horizon"])
        n_sims === nothing || n_sims == configured_sims ||
            error("--n-sims must exactly match ensemble_size in the config")
        seed === nothing || seed == configured_seed ||
            error("--seed must exactly match backtest_seed in the config")
        forecast_horizon === nothing ||
            forecast_horizon == configured_forecast_horizon ||
            error(
            "--forecast-horizon must exactly match forecast_horizon in the config",
        )
        isempty(strip(output_dir)) &&
            error("output_dir must not be empty")
        mkpath(output_dir)

        structural = Bit.load_us_baseline(:structural)
        forecast_baseline = Bit.load_us_baseline(:nowcast)
        calibration_artifact = Bit.load_us_calibration(:structural)
        calibration = calibration_artifact.calibration_object
        truth_path = scoring_truth_path(config, config_path)
        verify_truth_sha256(truth_path, config)
        actuals = read_scoring_truth(truth_path, config)
        dates = contract_dates(config)

        baseline_parameters = uncalibrated_parameters(structural)
        center = center_vector(baseline_parameters)
        rolling = rolling_one_step_paths(
            calibration,
            actuals,
            config;
            n_sims = configured_sims,
            seed = configured_seed,
        )
        target_actuals =
            Float64.(
            actuals[
                in.(actuals.period, Ref(dates.target_dates)),
                :annual_policy_rate,
            ],
        )
        fitting_target_indices =
            findall(in.(dates.target_dates, Ref(dates.training_dates)))
        optimized, optimization_loss, evaluations =
            optimize_rolling_policy_rule(
            center,
            rolling.quarterly_starts,
            rolling.growth,
            rolling.inflation,
            rolling.pi_stars,
            target_actuals,
            fitting_target_indices,
            configured_parameter_bounds(config),
            configured_regularization_scales(config),
            Float64(config["optimization"]["regularization_weight"]),
        )
        configured_policy_parameters = configured_parameters(config)
        if enforce_config_agreement
            validate_fitted_parameters(
                optimized,
                configured_policy_parameters,
            )
        end
        authoritative_parameters = enforce_config_agreement ?
            configured_policy_parameters : optimized

        uncalibrated_paths = deepcopy(rolling.paths)
        uncalibrated_paths["annual_policy_rate"][2:end, :] .=
            rolling_policy_forecasts(
            rolling.quarterly_starts,
            rolling.growth,
            rolling.inflation,
            center,
            rolling.pi_stars,
        )
        calibrated_raw_paths = deepcopy(rolling.paths)
        calibrated_raw_paths["annual_policy_rate"][2:end, :] .=
            rolling_policy_forecasts(
            rolling.quarterly_starts,
            rolling.growth,
            rolling.inflation,
            authoritative_parameters,
            rolling.pi_stars,
        )
        selected_actuals =
            actuals[in.(actuals.period, Ref(rolling.dates)), :]
        sort!(selected_actuals, :period)
        split = split_labels(rolling.dates, config)
        fitting_backtest_indices = findall(==("coefficient_fitting"), split)
        amplitude_bound = Float64(
            config["output_correction_constraints"]["amplitude_bound"],
        )
        correction_regularization = Float64(
            config["output_correction_constraints"]["regularization"],
        )
        correction_decay = Float64(config["correction_decay"])
        fitted_corrections = Dict(
            name => fit_one_step_log_bias(
                    calibrated_raw_paths[name],
                    selected_actuals[!, Symbol(name)],
                    fitting_backtest_indices;
                    decay = correction_decay,
                    amplitude_bound,
                    regularization = correction_regularization,
                ) for name in CORRECTABLE_SERIES
        )
        configured_corrections = configured_output_corrections(config)
        enforce_config_agreement &&
            validate_fitted_corrections(
            fitted_corrections,
            configured_corrections,
        )
        authoritative_corrections = enforce_config_agreement ?
            configured_corrections : fitted_corrections
        output_corrections = Dict(
            name => (
                    amplitude = authoritative_corrections[name].amplitude,
                    decay = authoritative_corrections[name].decay,
                    loss = fitted_corrections[name].loss,
                    evaluations = fitted_corrections[name].evaluations,
                ) for name in CORRECTABLE_SERIES
        )
        if fit_only
            println("[parameter_overrides]")
            for name in PARAMETER_NAMES
                println("$name = $(repr(optimized[name]))")
            end
            for name in sort!(collect(keys(fitted_corrections)))
                println()
                println("[output_corrections.$name]")
                println("method = \"damped_log_bias\"")
                println(
                    "amplitude = $(repr(fitted_corrections[name].amplitude))",
                )
                println("decay = $(repr(fitted_corrections[name].decay))")
                println(
                    "formula = \"factor(h)=exp(amplitude*(1-exp(-decay*h))) for h>0; factor(0)=1\"",
                )
            end
            return (;
                optimized,
                fitted_corrections,
                optimization_loss,
                evaluations,
            )
        end
        calibrated_paths =
            apply_rolling_corrections(calibrated_raw_paths, output_corrections)
        backtest = build_backtest_frame(
            actuals,
            rolling.dates,
            rolling.origin_periods,
            calibrated_paths,
            uncalibrated_paths,
            config,
        )
        metrics = vcat(
            score_frame(
                backtest,
                "uncalibrated";
                target_max_ape_pct =
                    Float64(config["target_max_ape_pct"]),
            ),
            score_frame(
                backtest,
                "calibrated";
                target_max_ape_pct =
                    Float64(config["target_max_ape_pct"]),
            ),
        )
        calibration_gate(metrics) ||
            error("Calibrated Economic outlook metrics do not meet the configured gate")
        parameter_frame = calibrated_parameters_frame(
            center,
            authoritative_parameters,
            configured_parameter_bounds(config),
        )
        correction_frame = output_corrections_frame(
            output_corrections;
            amplitude_bound,
            decay = correction_decay,
        )
        report_metrics = report_metrics_frame(metrics)

        current_parameters = deepcopy(forecast_baseline.parameters)
        for name in PARAMETER_NAMES
            current_parameters[name] = authoritative_parameters[name]
        end
        forecast = future_forecast(
            forecast_baseline,
            current_parameters,
            actuals;
            output_corrections,
            horizon = configured_forecast_horizon,
            n_sims = configured_sims,
            seed = Int(config["forecast_seed"]),
            config,
        )

        CSV.write(joinpath(output_dir, "backtest_quarterly.csv"), backtest)
        CSV.write(joinpath(output_dir, "backtest_metrics.csv"), metrics)
        CSV.write(joinpath(output_dir, "report_metrics.csv"), report_metrics)
        CSV.write(joinpath(output_dir, "optimized_parameters.csv"), parameter_frame)
        CSV.write(joinpath(output_dir, "output_corrections.csv"), correction_frame)
        CSV.write(joinpath(output_dir, "forecast_quarterly.csv"), forecast)
        summary = result_dictionary(
            backtest,
            metrics,
            parameter_frame,
            correction_frame,
            optimization_loss,
            evaluations,
            config,
            config_path,
            truth_path,
            structural.path,
            forecast_baseline.path,
            calibration_artifact.path,
            forecast,
        )
        write_json(joinpath(output_dir, "calibration_summary.json"), summary)

        println("US Economic outlook calibration complete")
        println("  design: current-vintage rolling one-quarter origins")
        println(
            "  coefficient fitting: $(quarter_label(first(dates.training_dates)))-$(quarter_label(last(dates.training_dates)))",
        )
        println(
            "  excluded from coefficient fitting: $(quarter_label(first(dates.holdout_dates)))-$(quarter_label(last(dates.holdout_dates)))",
        )
        println(
            "  ensemble: $configured_sims serial paths; back-test seed $configured_seed",
        )
        println("  policy evaluations: $evaluations")
        for row in eachrow(parameter_frame)
            @printf("  %-9s %.8f -> %.8f\n", row.parameter, row.original, row.optimized)
        end
        for row in eachrow(
                metrics[
                    (metrics.model_stage .== "calibrated") .&
                        (
                        metrics.sample .==
                            "excluded_from_coefficient_fitting"
                    ),
                    :,
                ],
            )
            @printf(
                "  holdout %-34s MAPE %6.3f%% max %6.3f%%\n",
                row.metric,
                row.mape_pct,
                row.max_ape_pct,
            )
        end
        for row in eachrow(correction_frame)
            @printf(
                "  output %-28s amplitude % .6f decay %.6f\n",
                row.series,
                row.amplitude,
                row.decay,
            )
        end
        println("  outputs: $output_dir")
        return (;
            backtest,
            metrics,
            report_metrics,
            parameter_frame,
            forecast,
            summary,
        )
    end

    function parse_arguments(arguments)
        values = Dict{String, String}()
        index = 1
        while index <= length(arguments)
            argument = String(arguments[index])
            startswith(argument, "--") || error("Unknown argument $argument")
            name = argument[3:end]
            name in CLI_ALLOWLIST || error("Unknown option $argument")
            haskey(values, name) && error("Duplicate option $argument")
            index == length(arguments) && error("Missing value for $argument")
            value = String(arguments[index + 1])
            startswith(value, "--") &&
                error("Missing value for $argument")
            values[name] = value
            index += 2
        end
        return values
    end

    function parse_bounded_integer(
            options,
            name,
            default::Integer;
            minimum::Integer,
            maximum::Integer,
        )
        raw = get(options, name, string(default))
        value = try
            parse(Int, raw)
        catch
            error("--$name must be an integer")
        end
        minimum <= value <= maximum ||
            error("--$name must be between $minimum and $maximum")
        return value
    end

    function validate_cli_options(options, config)
        n_sims = parse_bounded_integer(
            options,
            "n-sims",
            Int(config["ensemble_size"]);
            minimum = 2,
            maximum = 4096,
        )
        seed = parse_bounded_integer(
            options,
            "seed",
            Int(config["backtest_seed"]);
            minimum = 0,
            maximum = 1_000_000_000,
        )
        forecast_horizon = parse_bounded_integer(
            options,
            "forecast-horizon",
            Int(config["forecast_horizon"]);
            minimum = 1,
            maximum = 200,
        )
        n_sims == Int(config["ensemble_size"]) ||
            error("--n-sims must exactly match ensemble_size in the config")
        seed == Int(config["backtest_seed"]) ||
            error("--seed must exactly match backtest_seed in the config")
        forecast_horizon == Int(config["forecast_horizon"]) ||
            error(
            "--forecast-horizon must exactly match forecast_horizon in the config",
        )
        output_dir = get(options, "output-dir", DEFAULT_OUTPUT_DIR)
        isempty(strip(output_dir)) &&
            error("--output-dir must not be empty")
        return (; n_sims, seed, forecast_horizon, output_dir)
    end

    function main(arguments = ARGS)
        options = parse_arguments(arguments)
        config_path = abspath(get(options, "config", DEFAULT_CONFIG_PATH))
        config = load_contract(config_path)
        validated = validate_cli_options(options, config)
        return run_calibration(
            output_dir = validated.output_dir,
            config_path = config_path,
            n_sims = validated.n_sims,
            seed = validated.seed,
            forecast_horizon = validated.forecast_horizon,
        )
    end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    using .USOutlookCalibration
    USOutlookCalibration.main()
end
