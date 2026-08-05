module AustriaPipeline

using CSV
using DataFrames
using Dates
using Downloads
using DuckDB
using JLD2
using JSON
using Random
using SHA
using Statistics
using TOML

import BeforeIT as Bit
import CalibrateBeforeIT as CBit

const SCRIPT_DIR = @__DIR__
const REPO_ROOT = normpath(joinpath(SCRIPT_DIR, "..", ".."))
const CACHE_ROOT = joinpath(SCRIPT_DIR, "cache")
const DATA_ROOT = joinpath(REPO_ROOT, "data", "austria")
const SOURCE_FILE = joinpath(SCRIPT_DIR, "sources.toml")
const SOURCE_SPEC = TOML.parsefile(SOURCE_FILE)
const EUROSTAT_API =
    "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data"
const NOWCAST_PERIODS = ["2025-Q1", "2025-Q2", "2025-Q3", "2025-Q4", "2026-Q1"]
const VALIDATION_SEED = 20260729

export prepare_data!, build_structural_baseline!, build_nowcast_baseline!,
    build_scenarios!, validate_artifacts!, run_all!, main

artifact_path(parts...) = joinpath(DATA_ROOT, parts...)
cache_path(parts...) = joinpath(CACHE_ROOT, parts...)

function sha256_file(path::String)
    return open(path, "r") do io
        bytes2hex(SHA.sha256(io))
    end
end

function download_verified!(source::Dict{String, Any}, destination::String)
    mkpath(dirname(destination))
    if !isfile(destination) || sha256_file(destination) != source["sha256"]
        @info "Downloading" source = source["name"] destination
        Downloads.download(source["url"], destination)
    end
    actual = sha256_file(destination)
    expected = source["sha256"]
    actual == expected || error("Checksum mismatch for $destination: $actual != $expected")
    return destination
end

function extract_parquet_snapshot!(archive::String, snapshot_root::String)
    marker = joinpath(snapshot_root, "data", "010_eurostat_tables", "nace64.parquet")
    if !isfile(marker)
        mkpath(snapshot_root)
        run(
            `unzip -o $archive data/010_eurostat_tables/\*.parquet -d $snapshot_root`,
        )
    end
    return dirname(marker)
end

function extract_figaro_csv!(archive::String, destination::String, csv_name::String)
    csv_path = joinpath(destination, csv_name)
    if !isfile(csv_path)
        mkpath(destination)
        run(`unzip -o $archive $csv_name -d $destination`)
    end
    return csv_path
end

function figaro_range_sql(column::String)
    replacements = [
        "C10T12" => "C10-12",
        "C13T15" => "C13-15",
        "E37T39" => "E37-39",
        "N80T82" => "N80-82",
        "R90T92" => "R90-92",
    ]
    expression = column
    for (from, to) in replacements
        expression = "replace($expression, '$from', '$to')"
    end
    return expression
end

function build_augmented_figaro!(snapshot_path::String, figaro_csv::String)
    output_2024 = joinpath(snapshot_path, "naio_10_fcp_ii_2024_AT.parquet")
    output_all = joinpath(snapshot_path, "naio_10_fcp_ii.parquet")
    if isfile(output_all)
        return output_all
    end

    conn = DuckDB.DBInterface.connect(DuckDB.DB)
    row_expression = figaro_range_sql("rowPi")
    column_expression = figaro_range_sql("colPi")
    DuckDB.DBInterface.execute(
        conn,
        """
        COPY (
            SELECT
                'A'::VARCHAR AS freq,
                $column_expression::VARCHAR AS ind_use,
                (
                    CASE
                        WHEN starts_with(rowPi, 'CPA_') THEN substr($row_expression, 5)
                        ELSE rowPi
                    END
                )::VARCHAR AS ind_ava,
                counterpartArea::VARCHAR AS c_dest,
                'MIO_EUR'::VARCHAR AS unit,
                refArea::VARCHAR AS c_orig,
                '2024'::VARCHAR AS "time",
                obsValue::DOUBLE AS value
            FROM read_csv_auto('$figaro_csv', header = true)
            WHERE refArea = 'AT' OR counterpartArea = 'AT'
        )
        TO '$output_2024' (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
    )

    input_queries = [
        "SELECT * FROM read_parquet('$(joinpath(snapshot_path, "naio_10_fcp_ii$i.parquet"))')"
            for i in 1:4
    ]
    union_query = join(input_queries, " UNION ALL ")
    DuckDB.DBInterface.execute(
        conn,
        """
        COPY (
            $union_query
            UNION ALL
            SELECT * FROM read_parquet('$output_2024')
        )
        TO '$output_all' (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
    )

    check = DataFrame(
        DuckDB.DBInterface.execute(
            conn,
            """
            SELECT "time", count(*) AS rows
            FROM read_parquet('$output_all')
            WHERE c_dest = 'AT'
            GROUP BY "time"
            ORDER BY "time"
            """,
        ),
    )
    all(check.rows .== 221_214) ||
        error("FIGARO topology check failed: expected 221,214 Austria-destination rows per year")
    return output_all
end

function preprocess_austria_business_data!(snapshot_path::String)
    outputs = [
        joinpath(snapshot_path, "$(table)_a64.parquet")
            for table in
            ["bd_9ac_l_form_r2", "bd_l_form", "sbs_na_sca_r2", "sbs_ovw_act"]
    ]
    all(isfile, outputs) && return outputs

    at_path = cache_path("at_preprocess")
    mkpath(at_path)
    cp(
        joinpath(snapshot_path, "nace64.parquet"),
        joinpath(at_path, "nace64.parquet");
        force = true,
    )
    conn = DuckDB.DBInterface.connect(DuckDB.DB)
    source_tables =
        ["bd_9ac_l_form_r2", "bd_l_form", "sbs_na_sca_r2", "sbs_ovw_act"]
    for table in source_tables
        input = joinpath(snapshot_path, "$table.parquet")
        output = joinpath(at_path, "$table.parquet")
        DuckDB.DBInterface.execute(
            conn,
            "COPY (SELECT * FROM '$input' WHERE geo = 'AT') TO '$output' (FORMAT PARQUET)",
        )
    end

    CBit.eurostat_path = at_path
    for table in ["bd_9ac_l_form_r2", "bd_l_form"]
        ok, _ = CBit.create_business_demographic_a64_data(table, at_path, conn)
        ok || error("Failed to create $table A64 data")
    end
    for table in ["sbs_na_sca_r2", "sbs_ovw_act"]
        ok, _ = CBit.create_enterprise_statistics_a64_data(table, at_path, conn)
        ok || error("Failed to create $table A64 data")
    end
    for table in source_tables
        cp(
            joinpath(at_path, "$(table)_a64.parquet"),
            joinpath(snapshot_path, "$(table)_a64.parquet");
            force = true,
        )
    end
    return outputs
end

function unify_unemployment!(snapshot_path::String)
    marker = cache_path("unemployment_unified.txt")
    isfile(marker) && return
    CBit.eurostat_path = snapshot_path
    conn = DuckDB.DBInterface.connect(DuckDB.DB)
    CBit.unify_unemployment_rate_sources("une_rt_a", conn)
    CBit.unify_unemployment_rate_sources("une_rt_q", conn)
    write(marker, "Eurostat current and historical unemployment tables unified\n")
    return
end

"""
    prepare_data!()

Download and verify immutable inputs, extract the Eurostat Parquet snapshot,
map the 2026-edition FIGARO 2024 use table to BeforeIT's A64 convention, and
create Austria-only business-demography tables.
"""
function prepare_data!()
    downloads = cache_path("downloads")
    snapshot_root = cache_path("snapshot")
    figaro_root = cache_path("figaro")

    eurostat_source = SOURCE_SPEC["eurostat_snapshot"]
    figaro_source = SOURCE_SPEC["figaro_2024"]
    eurostat_archive =
        download_verified!(eurostat_source, joinpath(downloads, eurostat_source["filename"]))
    figaro_archive =
        download_verified!(figaro_source, joinpath(downloads, figaro_source["filename"]))
    snapshot_path = extract_parquet_snapshot!(eurostat_archive, snapshot_root)
    figaro_csv =
        extract_figaro_csv!(figaro_archive, figaro_root, figaro_source["csv_filename"])

    build_augmented_figaro!(snapshot_path, figaro_csv)
    unify_unemployment!(snapshot_path)
    preprocess_austria_business_data!(snapshot_path)
    return snapshot_path
end

function extend_firms_to_2024!(calibration, snapshot_path::String)
    size(calibration["firms"], 2) == 14 || return calibration
    conn = DuckDB.DBInterface.connect(DuckDB.DB)
    query = """
        SELECT s.value
        FROM '$(joinpath(snapshot_path, "nace64.parquet"))' n
        LEFT JOIN '$(joinpath(snapshot_path, "sbs_ovw_act_a64.parquet"))' s
          ON n.nace = s.nace_r2
         AND s.geo = 'AT'
         AND s.time = '2024'
         AND s.indic_sbs = 'ENT_NR'
        WHERE n.nace NOT IN ('L68A', 'T', 'U')
        ORDER BY n.id
    """
    observed_firms_2024 = CBit.execute(conn, query)
    firms_2024 = copy(calibration["firms"][:, end])
    observed = .!ismissing.(observed_firms_2024)
    firms_2024[observed] .= observed_firms_2024[observed]
    calibration["firms"] = hcat(calibration["firms"], firms_2024)
    return calibration
end

function base_metadata(period::String, kind::String)
    return Dict(
        "schema_version" => 1,
        "country" => "AT",
        "period" => period,
        "kind" => kind,
        "created_at" => string(now(UTC)),
        "beforeit_version" => "0.6.0",
        "calibratebeforeit_revision" =>
            SOURCE_SPEC["calibration_code"]["revision"],
        "eurostat_snapshot_sha256" =>
            SOURCE_SPEC["eurostat_snapshot"]["sha256"],
        "figaro_sha256" => SOURCE_SPEC["figaro_2024"]["sha256"],
        "sector_count" => 62,
        "scale" => 0.001,
    )
end

function build_structural_baseline!(snapshot_path::String = prepare_data!())
    CBit.eurostat_path = snapshot_path
    @info "Importing 1996-2024 euro-area and Austrian controls"
    ea = CBit.import_data("EA19", 1996, 2024)
    figaro = CBit.import_figaro_data("AT", 2010, 2024, 62)
    national = CBit.import_data("AT", 1996, 2024)
    calibration = CBit.import_calibration_data("AT", 2010, 2024, 62, figaro)
    extend_firms_to_2024!(calibration, snapshot_path)

    calibration_object = Bit.CalibrationData(
        calibration,
        figaro,
        national,
        ea,
        DateTime(2024, 12, 31),
        DateTime(1996, 12, 31),
    )
    parameters, initial_conditions = Bit.get_params_and_initial_conditions(
        calibration_object,
        DateTime(2024, 12, 31);
        scale = 0.001,
    )

    metadata = base_metadata("2024-Q4", "structural")
    metadata["structural_reference_year"] = 2024
    metadata["measurement_status"] = Dict(
        "production_network" =>
            "official FIGARO 2026 edition; recent-year cells may include Eurostat estimates",
        "national_accounts" => "observed",
        "financial_stocks" => "observed",
        "firm_counts_2024" =>
            "observed SBS where available; 2023 carry-forward for uncovered legal-form sectors",
    )

    object_path = artifact_path("calibration", "AT_2024_calibration_object.jld2")
    baseline_path = artifact_path("baselines", "AT_2024Q4_structural.jld2")
    mkpath(dirname(object_path))
    mkpath(dirname(baseline_path))
    jldsave(object_path; calibration_object, metadata)
    jldsave(baseline_path; parameters, initial_conditions, metadata)
    return (; calibration_object, parameters, initial_conditions, metadata, object_path, baseline_path)
end

function fetch_series(
        source_records::Vector{Dict{String, Any}},
        dataset::String;
        periods = NOWCAST_PERIODS,
        scale = 1.0,
        filters...,
    )
    query = ["$(key)=$(value)" for (key, value) in sort!(collect(filters); by = first)]
    push!(query, "sinceTimePeriod=$(first(periods))")
    push!(query, "untilTimePeriod=$(last(periods))")
    push!(query, "lang=en")
    url = "$EUROSTAT_API/$dataset?" * join(query, "&")
    response = JSON.parsefile(Downloads.download(url))
    sizes = Int.(response["size"])
    prod(sizes[1:(end - 1)]) == 1 ||
        error("Eurostat filters did not resolve to one $dataset series: $url")

    time_index = response["dimension"]["time"]["category"]["index"]
    available_periods = if time_index isa AbstractVector
        String.(time_index)
    else
        sort!(collect(keys(time_index)); by = period -> time_index[period])
    end
    values_object = response["value"]
    values = Dict{String, Union{Missing, Float64}}()
    for (index, period) in enumerate(available_periods)
        key = string(index - 1)
        values[period] =
            haskey(values_object, key) ? scale * Float64(values_object[key]) : missing
    end
    missing_periods = [
        period for period in periods
            if !haskey(values, period) || ismissing(values[period])
    ]
    isempty(missing_periods) ||
        error("$dataset is missing $(join(missing_periods, ", ")): $url")

    push!(
        source_records,
        Dict(
            "dataset" => dataset,
            "url" => url,
            "updated" => get(response, "updated", missing),
            "latest_period" => last(available_periods),
        ),
    )
    return Float64[values[period] for period in periods]
end

function quarter_end(period::String)
    year_number = parse(Int, period[1:4])
    quarter = parse(Int, period[end:end])
    month = 3 * quarter
    return DateTime(year_number, month, daysinmonth(Date(year_number, month)))
end

function extend_quarter_axis!(dictionary, periods = NOWCAST_PERIODS)
    append!(dictionary["quarters_num"], Bit.date2num.(quarter_end.(periods)))
    return dictionary
end

append_series!(dictionary, key, values) = (append!(dictionary[key], values); dictionary)

function refresh_quarterly_calibration!(calibration, source_records)
    extend_quarter_axis!(calibration)
    append_series!(
        calibration,
        "firm_cash_quarterly",
        fetch_series(
            source_records,
            "nasq_10_f_bs";
            geo = "AT",
            sector = "S11",
            na_item = "F2",
            finpos = "ASS",
            unit = "MIO_EUR",
        ),
    )
    append_series!(
        calibration,
        "firm_debt_quarterly",
        fetch_series(
            source_records,
            "nasq_10_f_bs";
            geo = "AT",
            sector = "S11",
            na_item = "F4",
            finpos = "LIAB",
            unit = "MIO_EUR",
        ),
    )
    append_series!(
        calibration,
        "household_cash_quarterly",
        fetch_series(
            source_records,
            "nasq_10_f_bs";
            geo = "AT",
            sector = "S14_S15",
            na_item = "F2",
            finpos = "ASS",
            unit = "MIO_EUR",
        ),
    )
    monetary_equity = fetch_series(
        source_records,
        "nasq_10_f_bs";
        geo = "AT",
        sector = "S121_S122_S123",
        na_item = "F5",
        finpos = "LIAB",
        unit = "MIO_EUR",
    )
    central_bank_equity = fetch_series(
        source_records,
        "nasq_10_f_bs";
        geo = "AT",
        sector = "S121",
        na_item = "F5",
        finpos = "LIAB",
        unit = "MIO_EUR",
    )
    append_series!(
        calibration,
        "bank_equity_quarterly",
        monetary_equity - central_bank_equity,
    )
    append_series!(
        calibration,
        "government_debt_quarterly",
        fetch_series(
            source_records,
            "gov_10q_ggdebt";
            geo = "AT",
            sector = "S13",
            na_item = "GD",
            unit = "MIO_EUR",
        ),
    )
    append_series!(
        calibration,
        "government_deficit_quarterly",
        fetch_series(
            source_records,
            "gov_10q_ggnfa";
            geo = "AT",
            sector = "S13",
            na_item = "B9",
            unit = "MIO_EUR",
            s_adj = "NSA",
        ),
    )
    append_series!(
        calibration,
        "firm_interest_quarterly",
        fetch_series(
            source_records,
            "nasq_10_nf_tr";
            geo = "AT",
            sector = "S11",
            na_item = "D41",
            direct = "PAID",
            unit = "CP_MEUR",
            s_adj = "NSA",
        ),
    )
    append_series!(
        calibration,
        "interest_government_debt_quarterly",
        fetch_series(
            source_records,
            "gov_10q_ggnfa";
            geo = "AT",
            sector = "S13",
            na_item = "D41PAY",
            unit = "MIO_EUR",
            s_adj = "NSA",
        ),
    )
    return calibration
end

function refresh_national_controls!(national, source_records)
    extend_quarter_axis!(national)
    specifications = [
        ("nominal_gdp_quarterly", "B1GQ", "CP_MEUR"),
        ("real_gdp_quarterly", "B1GQ", "CLV10_MEUR"),
        ("real_government_consumption_quarterly", "P3_S13", "CLV10_MEUR"),
        ("real_exports_quarterly", "P6", "CLV10_MEUR"),
        ("real_imports_quarterly", "P7", "CLV10_MEUR"),
    ]
    for (key, item, unit) in specifications
        append_series!(
            national,
            key,
            fetch_series(
                source_records,
                "namq_10_gdp";
                geo = "AT",
                na_item = item,
                unit,
                s_adj = "SCA",
            ),
        )
    end
    append_series!(
        national,
        "unemployment_rate_quarterly",
        fetch_series(
            source_records,
            "une_rt_q";
            scale = 0.01,
            geo = "AT",
            unit = "PC_ACT",
            age = "Y15-74",
            s_adj = "SA",
            sex = "T",
        ),
    )
    append_series!(
        national,
        "euribor",
        fetch_series(
            source_records,
            "irt_st_q";
            scale = 0.01,
            geo = "EA",
            int_rt = "IRT_M3",
        ),
    )
    return national
end

function refresh_ea_controls!(ea, source_records)
    extend_quarter_axis!(ea)
    for (key, unit) in [
            ("nominal_gdp_quarterly", "CP_MEUR"),
            ("real_gdp_quarterly", "CLV10_MEUR"),
        ]
        append_series!(
            ea,
            key,
            fetch_series(
                source_records,
                "namq_10_gdp";
                geo = "EA19",
                na_item = "B1GQ",
                unit,
                s_adj = "SCA",
            ),
        )
    end
    return ea
end

function build_nowcast_baseline!()
    structural_path = artifact_path("calibration", "AT_2024_calibration_object.jld2")
    isfile(structural_path) || build_structural_baseline!()
    structural = load(structural_path)["calibration_object"]
    calibration = deepcopy(structural.calibration)
    figaro = deepcopy(structural.figaro)
    national = deepcopy(structural.data)
    ea = deepcopy(structural.ea)
    source_records = Dict{String, Any}[]

    refresh_quarterly_calibration!(calibration, source_records)
    refresh_national_controls!(national, source_records)
    refresh_ea_controls!(ea, source_records)
    nowcast_object = Bit.CalibrationData(
        calibration,
        figaro,
        national,
        ea,
        DateTime(2024, 12, 31),
        DateTime(1996, 12, 31),
    )
    parameters, initial_conditions = Bit.get_params_and_initial_conditions(
        nowcast_object,
        DateTime(2026, 3, 31);
        scale = 0.001,
    )

    metadata = base_metadata("2026-Q1", "nowcast")
    metadata["structural_reference_year"] = 2024
    metadata["measurement_status"] = Dict(
        "production_network" =>
            "official FIGARO 2024 table, carried as structural benchmark; recent-year cells may include Eurostat estimates",
        "national_accounts" => "observed through 2026-Q1",
        "financial_stocks" => "observed through 2026-Q1",
        "annual_distributional_parameters" => "latest observed 2024 structure",
    )
    metadata["live_source_records"] = source_records

    object_path = artifact_path("calibration", "AT_2026Q1_nowcast_object.jld2")
    baseline_path = artifact_path("baselines", "AT_2026Q1_nowcast.jld2")
    mkpath(dirname(object_path))
    mkpath(dirname(baseline_path))
    jldsave(object_path; calibration_object = nowcast_object, metadata)
    jldsave(baseline_path; parameters, initial_conditions, metadata)
    return (; nowcast_object, parameters, initial_conditions, metadata, object_path, baseline_path)
end

function build_scenarios!()
    path = artifact_path("scenarios", "AT_2026_2031_annual.csv")
    isfile(path) || error("Scenario assumptions are missing: $path")
    scenarios = CSV.read(path, DataFrame)
    expected = Set(["baseline", "upside", "downside"])
    Set(scenarios.scenario) == expected || error("Scenario names must be $expected")
    all(group -> nrow(group) == 6, groupby(scenarios, :scenario)) ||
        error("Each scenario must contain 2026-2031")
    return path
end

function model_validation(model::Bit.AbstractModel, horizon::Int)
    initial_cb, initial_bank = Bit.get_accounting_identity_banks(model)
    Bit.run!(model, horizon; parallel = false)
    final_cb, final_bank = Bit.get_accounting_identity_banks(model)
    finite = all(
        isfinite,
        vcat(
            model.data.nominal_gdp,
            model.data.real_gdp,
            model.data.nominal_gva,
            model.data.real_gva,
        ),
    )
    positive_real_gdp = all(>(0), model.data.real_gdp)
    return Dict(
        "horizon_quarters" => horizon,
        "initial_central_bank_residual" => initial_cb,
        "initial_commercial_bank_residual" => initial_bank,
        "final_central_bank_residual" => final_cb,
        "final_commercial_bank_residual" => final_bank,
        "finite_outputs" => finite,
        "positive_real_gdp" => positive_real_gdp,
        "final_real_gdp" => model.data.real_gdp[end],
    )
end

function model_validation(path::String, horizon::Int)
    artifact = load(path)
    model = Bit.Model(artifact["parameters"], artifact["initial_conditions"])
    return model_validation(model, horizon)
end

function run_2024_backtest!(calibration_path::String; simulations = 8)
    calibration_object = load(calibration_path)["calibration_object"]
    parameters, initial_conditions = Bit.get_params_and_initial_conditions(
        calibration_object,
        DateTime(2023, 12, 31);
        scale = 0.001,
    )
    models = Bit.ensemblerun(
        Bit.Model(parameters, initial_conditions),
        4,
        simulations;
        parallel = false,
    )
    predicted_growth = [
        model.data.real_gdp[end] / model.data.real_gdp[1] - 1 for model in models
    ]
    data = calibration_object.data
    q2023 = findfirst(
        ==(Bit.date2num(DateTime(2023, 12, 31))),
        data["quarters_num"],
    )
    q2024 = findfirst(
        ==(Bit.date2num(DateTime(2024, 12, 31))),
        data["quarters_num"],
    )
    actual_growth =
        data["real_gdp_quarterly"][q2024] / data["real_gdp_quarterly"][q2023] - 1
    result = DataFrame(
        origin = ["2023-Q4"],
        target = ["2024-Q4"],
        simulations = [simulations],
        predicted_growth_mean = [sum(predicted_growth) / simulations],
        predicted_growth_p10 = [quantile(predicted_growth, 0.1)],
        predicted_growth_p90 = [quantile(predicted_growth, 0.9)],
        actual_growth = [actual_growth],
    )
    path = artifact_path("validation", "AT_2024_backtest.csv")
    mkpath(dirname(path))
    CSV.write(path, result)
    return path
end

function validate_artifacts!()
    structural_path = artifact_path("baselines", "AT_2024Q4_structural.jld2")
    nowcast_path = artifact_path("baselines", "AT_2026Q1_nowcast.jld2")
    calibration_path = artifact_path("calibration", "AT_2024_calibration_object.jld2")
    all(isfile, [structural_path, nowcast_path, calibration_path]) ||
        error("Build the structural and nowcast baselines before validation")

    Random.seed!(VALIDATION_SEED + 1)
    structural = model_validation(structural_path, 4)
    Random.seed!(VALIDATION_SEED + 2)
    nowcast = model_validation(nowcast_path, 23)
    scenarios = Dict{String, Any}()
    for scenario in ("baseline", "upside", "downside")
        Random.seed!(VALIDATION_SEED + 10)
        model = Bit.build_austria_scenario_model(
            Symbol(scenario);
            horizon = 23,
        )
        scenarios[scenario] = model_validation(model, 23)
    end
    tolerance = 1.0e-6
    for result in (structural, nowcast, values(scenarios)...)
        maximum(
            abs.(
                [
                    result["initial_central_bank_residual"],
                    result["initial_commercial_bank_residual"],
                    result["final_central_bank_residual"],
                    result["final_commercial_bank_residual"],
                ]
            ),
        ) <= tolerance || error("Accounting residual exceeds $tolerance")
        result["finite_outputs"] || error("Simulation produced non-finite output")
        result["positive_real_gdp"] || error("Simulation produced non-positive real GDP")
    end

    Random.seed!(VALIDATION_SEED + 3)
    backtest_path = run_2024_backtest!(calibration_path)
    validation = Dict(
        "schema_version" => 1,
        "data_vintage" => "2026-07-29",
        "random_seed" => VALIDATION_SEED,
        "accounting_tolerance" => tolerance,
        "structural_2024Q4" => structural,
        "nowcast_2026Q1_to_2031Q4" => nowcast,
        "conditional_scenarios_2026Q2_to_2031Q4" => scenarios,
        "backtest" => relpath(backtest_path, REPO_ROOT),
    )
    validation_path = artifact_path("validation", "validation.toml")
    open(validation_path, "w") do io
        TOML.print(io, validation; sorted = true)
    end
    return validation
end

function run_all!()
    snapshot_path = prepare_data!()
    build_structural_baseline!(snapshot_path)
    build_nowcast_baseline!()
    build_scenarios!()
    return validate_artifacts!()
end

function main(args = ARGS)
    command = isempty(args) ? "all" : first(args)
    return if command == "prepare"
        println(prepare_data!())
    elseif command == "structural"
        println(build_structural_baseline!().baseline_path)
    elseif command == "nowcast"
        println(build_nowcast_baseline!().baseline_path)
    elseif command == "scenarios"
        println(build_scenarios!())
    elseif command == "validate"
        println(validate_artifacts!())
    elseif command == "all"
        println(run_all!())
    else
        error("Unknown command '$command'. Use prepare, structural, nowcast, scenarios, validate, or all.")
    end
end

end
