using Test
using Dates
using DataFrames
using DuckDB
using JLD2
using TOML

include(joinpath(@__DIR__, "..", "USPipeline.jl"))
using .USPipeline

const EXPECTED_SECTOR_COUNT = 68
const VALID_QA_STATUSES = Set(["APPROVED", "DUBIOUS", "REJECTED", "MISSING"])

function observed_commodity_codes(rows)
    special_rows = Set(
        [
            "Other",
            "Used",
            "T005",
            "T00OSUB",
            "T00OTOP",
            "T00SUB",
            "T00TOP",
            "T018",
            "V001",
            "V003",
            "VABAS",
            "VAPRO",
        ]
    )
    ordered = unique(String(row["RowCode"]) for row in rows)
    return [code for code in ordered if !(code in special_rows)]
end

function all_regular_files(root)
    isdir(root) || return String[]
    files = String[]
    for (directory, _, names) in walkdir(root)
        for name in names
            path = joinpath(directory, name)
            isfile(path) && push!(files, path)
        end
    end
    return sort!(files)
end

# Search as bytes so PDFs and other non-UTF-8 source bodies are covered. The
# overlap catches a credential split across two read chunks.
function file_contains_any_literal(path, needles; chunk_size = 1024 * 1024)
    found = falses(length(needles))
    isempty(needles) && return found
    overlap_size = maximum(length, needles) - 1
    carry = UInt8[]
    open(path, "r") do io
        while !eof(io)
            chunk = read(io, chunk_size)
            haystack = isempty(carry) ? chunk : vcat(carry, chunk)
            for index in eachindex(needles)
                found[index] && continue
                found[index] = findfirst(needles[index], haystack) !== nothing
            end
            all(found) && break
            kept = min(overlap_size, length(haystack))
            carry = kept == 0 ? UInt8[] : copy(@view haystack[(end - kept + 1):end])
        end
    end
    return found
end

function query_frame(connection, sql)
    return DataFrame(DuckDB.DBInterface.execute(connection, sql))
end

@testset "U.S. pipeline offline tests" begin
    @testset "BEA numeric parsing" begin
        @test USPipeline.parse_bea_number("1,234.50") == 1234.5
        @test USPipeline.parse_bea_number(" (1,234.50) ") == -1234.5
        @test USPipeline.parse_bea_number("-17.25") == -17.25
        @test USPipeline.parse_bea_number("1.25e3") == 1250.0
        @test USPipeline.parse_bea_number("0") == 0.0
        for marker in ("", "--", "---", "NA", "(NA)", "(D)", "not-a-number")
            @test ismissing(USPipeline.parse_bea_number(marker))
        end
        @test ismissing(USPipeline.parse_bea_number(missing))
    end

    @testset "Quarter conversion" begin
        @test USPipeline.quarter_end(2024, 1) == Date(2024, 3, 31)
        @test USPipeline.quarter_end(2024, 2) == Date(2024, 6, 30)
        @test USPipeline.quarter_end(2024, 3) == Date(2024, 9, 30)
        @test USPipeline.quarter_end(2024, 4) == Date(2024, 12, 31)
        @test USPipeline.parse_quarter("1996Q4") == Date(1996, 12, 31)
        @test USPipeline.parse_quarter("2024Q1") == Date(2024, 3, 31)
        @test USPipeline.quarter_of(Date(2024, 1, 1)) == Date(2024, 3, 31)
        @test USPipeline.quarter_of(Date(2024, 6, 30)) == Date(2024, 6, 30)
        @test USPipeline.quarter_of(Date(2024, 11, 15)) == Date(2024, 12, 31)
        @test_throws ErrorException USPipeline.parse_quarter("2024Q0")
        @test_throws ErrorException USPipeline.parse_quarter("2024q1")
        @test_throws Exception USPipeline.quarter_end(2024, 0)
        @test_throws Exception USPipeline.quarter_end(2024, 5)
    end

    @testset "Official quantity-index level backcast" begin
        observed_periods =
            [Date(2007, 3, 31), Date(2007, 6, 30), Date(2007, 9, 30)]
        observed_values = [200.0, 220.0, 240.0]
        index_periods = [
            Date(2006, 9, 30),
            Date(2006, 12, 31),
            observed_periods...,
        ]
        index_values = [80.0, 90.0, 100.0, 110.0, 120.0]
        backcast = USPipeline.linked_level_backcast(
            observed_periods,
            observed_values,
            index_periods,
            index_values;
            start_period = Date(2006, 9, 30),
        )
        @test backcast.periods ==
            [Date(2006, 9, 30), Date(2006, 12, 31)]
        @test backcast.values == [160.0, 180.0]
        @test backcast.link_factor == 2.0
        @test backcast.overlap_count == 3
        @test backcast.max_relative_error == 0.0
        @test_throws ErrorException USPipeline.linked_level_backcast(
            observed_periods[1:2],
            [200.0, 440.0],
            observed_periods[1:2],
            [100.0, 110.0];
            start_period = Date(2007, 3, 31),
        )
    end

    @testset "Exact quarterly panel alignment" begin
        panel = DataFrame(
            period = [
                Date(1996, 12, 31),
                Date(1997, 3, 31),
                Date(1997, 6, 30),
            ],
            value = [1.0, 2.0, 3.0],
        )
        aligned = USPipeline.align_quarterly_panel(
            panel,
            [Date(1997, 6, 30), Date(1996, 12, 31)],
        )
        @test aligned.period ==
            [Date(1997, 6, 30), Date(1996, 12, 31)]
        @test aligned.value == [3.0, 1.0]
        mismatch = try
            USPipeline.align_quarterly_panel(
                panel,
                [Date(1996, 9, 30), Date(1996, 12, 31)],
            )
        catch error
            error
        end
        @test mismatch isa ErrorException
        @test occursin("1996-09-30", sprint(showerror, mismatch))
        @test occursin("missing periods", sprint(showerror, mismatch))
    end

    @testset "Measured trade routing and nonnegative shares" begin
        adjusted = USPipeline.nonnegative_import_vector([10.0, -2.0, 5.0])
        @test adjusted.negative_count == 1
        @test adjusted.negative_adjustment == -2.0
        @test all(adjusted.values .>= 0)
        @test sum(adjusted.values) ≈ 13.0
        @test adjusted.values ≈ [10.0, 0.0, 5.0] .* (13 / 15)

        explicit_figaro = Dict{String, Any}(
            "imports" => reshape([4.0, 5.0, 6.0], 3, 1),
            "reexports" => reshape([1.0, 0.0, 2.0], 3, 1),
            "use_explicit_trade" => true,
        )
        residual_was_evaluated = Ref(false)
        imports, reexports = USPipeline.Bit.calibration_trade_vectors(
            explicit_figaro,
            1,
            3,
        ) do
            residual_was_evaluated[] = true
            error("explicit imports must bypass the goods-balance residual")
        end
        @test !residual_was_evaluated[]
        @test imports == [4.0, 5.0, 6.0]
        @test reexports == [1.0, 0.0, 2.0]

        legacy_import_field_was_evaluated = Ref(false)
        legacy_import_field, legacy_import_field_reexports =
            USPipeline.Bit.calibration_trade_vectors(
            Dict{String, Any}(
                "imports" => reshape([99.0, 99.0, 99.0], 3, 1),
            ),
            1,
            3,
        ) do
            legacy_import_field_was_evaluated[] = true
            [2.0, -1.0, 0.0]
        end
        @test legacy_import_field_was_evaluated[]
        @test legacy_import_field == [2.0, 0.0, 0.0]
        @test legacy_import_field_reexports == [0.0, -1.0, 0.0]

        legacy_imports, legacy_reexports =
            USPipeline.Bit.calibration_trade_vectors(
            Dict{String, Any}(),
            1,
            3,
        ) do
            [3.0, -2.0, 0.0]
        end
        @test legacy_imports == [3.0, 0.0, 0.0]
        @test legacy_reexports == [0.0, -2.0, 0.0]

        export_shares = USPipeline.Bit.nonnegative_calibration_share(
            [3.0, -1.0, 1.0],
            "test exports",
        )
        @test export_shares == [0.75, 0.0, 0.25]
        @test all(isfinite, export_shares)
        @test all(export_shares .>= 0)
        @test_throws ErrorException USPipeline.Bit.nonnegative_calibration_share(
            zeros(3),
            "empty imports",
        )
    end

    @testset "BEA purchasers-to-basic-price bridge" begin
        supply_values = Dict{Tuple{String, String}, Float64}(
            ("A", "T013") => 8.0,
            ("A", "T016") => 4.0,
            ("441", "T013") => 1.0,
            ("441", "T016") => 0.0,
            ("445", "T013") => 2.0,
            ("445", "T016") => 0.0,
            ("452", "T013") => 3.0,
            ("452", "T016") => 0.0,
            ("4A0", "T013") => 4.0,
            ("4A0", "T016") => 5.0,
        )
        bridge = USPipeline.purchasers_to_basic_price_vector(
            supply_values,
            ["A", "4A0"],
        )
        @test bridge.basic_price == [8.0, 10.0]
        @test bridge.purchasers_price == [4.0, 5.0]
        @test bridge.values == [2.0, 2.0]
        @test_throws ErrorException USPipeline.purchasers_to_basic_price_vector(
            Dict{Tuple{String, String}, Float64}(
                ("A", "T013") => 1.0,
                ("A", "T016") => 0.0,
            ),
            ["A"],
        )
    end

    @testset "Monthly SAAR wages to quarterly flow" begin
        state = USPipeline.RunState()
        monthly = [
            (Date(2024, 10, 1), 12_000.0),
            (Date(2024, 11, 1), 12_300.0),
            (Date(2024, 12, 1), 12_600.0),
            (Date(2025, 1, 1), 12_900.0),
            (Date(2025, 2, 1), 13_200.0),
            (Date(2025, 3, 1), 13_500.0),
            (Date(2025, 4, 1), 13_800.0),
            (Date(2025, 5, 1), 14_100.0),
        ]
        for (period, value) in monthly
            push!(
                state.observations,
                (
                    source = "FRED",
                    dataset = "series_observations",
                    series_id = "A576RC1",
                    period = period,
                    frequency = "M",
                    unit = "Billions of Dollars",
                    value = value,
                    status = "APPROVED",
                    raw_sha256 = repeat("0", 64),
                    note = "Wage and salary disbursements",
                ),
            )
        end
        state.tables["fred_metadata"] = Dict(
            "A576RC1" => Dict(
                "frequency_short" => "M",
                "units" => "Billions of Dollars",
                "seasonal_adjustment_short" => "SAAR",
            ),
        )
        USPipeline.build_nominal_wages!(state)
        quarterly = state.tables["nominal_wages_quarterly"]
        @test quarterly.quarter ==
            [Date(2024, 12, 31), Date(2025, 3, 31)]
        @test quarterly.value == [3_075_000.0, 3_300_000.0]
        @test all(==(3), quarterly.month_count)
    end

    @testset "Economic-outlook actuals snapshot" begin
        periods = [
            Date(2023, 9, 30);
            collect(Date(2023, 12, 31):Month(3):Date(2026, 6, 30))
        ]
        nominal_gdp = collect(200.0:10.0:310.0)
        real_gdp = collect(100.0:5.0:155.0)
        panel = DataFrame(
            period = periods,
            nominal_gdp_quarterly = nominal_gdp,
            real_gdp_quarterly = real_gdp,
            gdp_deflator_quarterly = nominal_gdp ./ real_gdp,
            real_household_consumption_quarterly =
                collect(60.0:2.0:82.0),
            real_government_consumption_quarterly =
                collect(15.0:1.0:26.0),
            real_fixed_capitalformation_quarterly =
                collect(18.0:1.0:29.0),
            real_exports_quarterly = collect(10.0:1.0:21.0),
            real_imports_quarterly = collect(12.0:1.0:23.0),
            nominal_wages_quarterly = collect(50.0:2.0:72.0),
            euribor = collect(0.04:-0.001:0.029),
        )
        snapshot = USPipeline.economic_outlook_actuals_frame(panel)
        @test snapshot.period ==
            collect(Date(2023, 12, 31):Month(3):Date(2026, 6, 30))
        @test nrow(snapshot) == 11
        @test snapshot.nominal_gdp == nominal_gdp[2:end]
        @test snapshot.gdp_deflator ==
            snapshot.nominal_gdp ./ snapshot.real_gdp
        @test snapshot.real_fixed_capitalformation ==
            panel.real_fixed_capitalformation_quarterly[2:end]
        @test snapshot.wages ==
            panel.nominal_wages_quarterly[2:end]
        @test snapshot.annual_policy_rate == panel.euribor[2:end]
        @test all(==("2026-08-04"), snapshot.data_truth_vintage)
        @test all(==("FRED:FEDFUNDS"), snapshot.policy_rate_source_id)
        @test all(==("FRED:A576RC1 (BEA)"), snapshot.wage_source_id)
        @test all(
            source -> occursin("real_household_consumption=T10106:2", source),
            snapshot.bea_source_ids,
        )
        @test all(
            source -> occursin(
                "real_fixed_capitalformation=T10106:8",
                source,
            ),
            snapshot.bea_source_ids,
        )
        @test_throws ErrorException USPipeline.economic_outlook_actuals_frame(
            panel[panel.period .!= Date(2025, 9, 30), :],
        )
    end

    @testset "Frozen official source registry" begin
        registry = USPipeline.SOURCE_SPEC

        expected_fred = Dict(
            "household_cash" =>
                (["HNOCDAQ027S"], "sum", true, "Q", "Millions of Dollars"),
            "firm_cash" => (
                ["NCBCDTQ027S", "NNBCDAQ027S"],
                "sum",
                true,
                "Q",
                "Millions of Dollars",
            ),
            "firm_debt" => (
                ["BOGZ1FL144104005Q"],
                "identity",
                true,
                "Q",
                "Millions of Dollars",
            ),
            "government_debt" => (
                ["FGTCMDODNS", "SLGTCMDODNS"],
                "sum",
                true,
                "Q",
                "Millions of Dollars",
            ),
            "bank_equity" => (
                ["BOGZ1FL704194005Q", "BOGZ1FL704190005Q"],
                "difference",
                true,
                "Q",
                "Millions of Dollars",
            ),
            "policy_rate" =>
                (["FEDFUNDS"], "identity", false, "M", "Percent"),
            "wages" => (
                ["A576RC1"],
                "identity",
                false,
                "M",
                "Billions of Dollars",
            ),
        )
        @test Set(keys(registry["fred_series"])) == Set(keys(expected_fred))
        for (concept, (series, operation, stock, frequency, unit)) in
            expected_fred
            specification = registry["fred_series"][concept]
            @test String.(specification["series"]) == series
            @test String(specification["operation"]) == operation
            @test Bool(specification["stock"]) == stock
            @test String(specification["frequency"]) == frequency
            @test String(specification["unit"]) == unit
        end

        # Annual person controls are NSA CPS series; only the headline
        # unemployment-rate input is seasonally adjusted.
        expected_bls = Dict(
            "unemployment_rate" => "LNS14000000",
            "population" => "LNU00000000",
            "labor_force" => "LNU01000000",
            "employed" => "LNU02000000",
            "unemployed" => "LNU03000000",
            "inactive" => "LNU05000000",
        )
        @test Dict(
            String(name) => String(series)
                for (name, series) in registry["bls_series"]
        ) == expected_bls

        @test registry["bea"]["input_output"]["use_table"] == "259"
        @test registry["bea"]["input_output"]["supply_table"] == "262"
        @test Set(String.(registry["bea"]["nipa"]["quarterly_tables"])) ==
            Set(["T10103", "T10105", "T10106"])
        @test registry["quarterly_nipa_lines"]["real_household_consumption_quarterly"] ==
            "T10106:2"
        @test registry["quarterly_nipa_lines"]["real_fixed_capitalformation_quarterly"] ==
            "T10106:8"
        @test registry["quarterly_nipa_backcasts"]["real_fixed_capitalformation_quarterly"] ==
            "T10103:8"
        @test registry["pipeline"]["data_truth_vintage"] == "2026-08-04"
        @test registry["pipeline"]["economic_outlook_actual_start"] ==
            "2023-12-31"
        @test registry["pipeline"]["economic_outlook_actual_end"] ==
            "2026-06-30"
        @test Set(String.(registry["bea"]["fixed_assets"]["tables"])) == Set(
            [
                "FAAt301ESI",
                "FAAt304ESI",
                "FAAt501",
                "FAAt504",
                "FAAt701",
                "FAAt703",
            ]
        )
        @test all(startswith(String(url), "https://") for url in values(registry["endpoints"]))
    end

    @testset "Economic-outlook measurement specifications" begin
        specifications = USPipeline.output_measurement_specifications()
        by_name = Dict(specification.name => specification for specification in specifications)
        @test Set(keys(by_name)) == Set(
            [
                "real_gdp",
                "real_household_consumption",
                "real_government_consumption",
                "real_fixed_capitalformation",
                "real_exports",
                "real_imports",
                "wages",
            ],
        )
        @test by_name["real_fixed_capitalformation"].panel_column ==
            :real_fixed_capitalformation_quarterly
        @test by_name["real_fixed_capitalformation"].model_field ==
            :real_fixed_capitalformation
        @test by_name["wages"].panel_column == :nominal_wages_quarterly
        @test by_name["wages"].model_field == :wages
        @test by_name["wages"].unit ==
            "millions of current dollars per quarter"
    end

    @testset "68-sector model contract" begin
        pipeline = USPipeline.SOURCE_SPEC["pipeline"]
        @test Int(pipeline["structural_year"]) == 2024
        @test occursin(
            r"(^|[^0-9])68([^0-9]|$)",
            String(pipeline["model_sector_system"]),
        )
        @test EXPECTED_SECTOR_COUNT == 68
    end

    @testset "Collected cache (when present)" begin
        cache_path = joinpath(USPipeline.SCRIPT_DIR, "cache", "collected.jld2")
        if isfile(cache_path)
            state = JLD2.load(cache_path, "state")
            @test state isa USPipeline.RunState
            @test nrow(state.acquisitions) > 0
            @test nrow(state.source_checks) > 0
            @test nrow(state.observations) > 0
            @test all(status -> status in VALID_QA_STATUSES, state.acquisitions.status)
            @test all(status -> status in VALID_QA_STATUSES, state.source_checks.status)
            @test all(status -> status in VALID_QA_STATUSES, state.observations.status)
            @test all(==(200), state.acquisitions.http_status)
            @test all(>(0), state.acquisitions.byte_count)
            @test all(sha -> occursin(r"^[0-9a-f]{64}$", sha), state.acquisitions.raw_sha256)
            @test all(
                row -> isfile(joinpath(USPipeline.REPO_ROOT, row.raw_path)),
                eachrow(state.acquisitions),
            )

            required_tables = Set(
                [
                    "bea_io_259",
                    "bea_io_262",
                    "fred_metadata",
                    "bls_rows",
                    "qcew",
                    "susb",
                    "usda_farms",
                ]
            )
            @test required_tables ⊆ Set(keys(state.tables))

            commodity_codes = observed_commodity_codes(state.tables["bea_io_259"])
            @test length(commodity_codes) == EXPECTED_SECTOR_COUNT
            @test length(unique(commodity_codes)) == EXPECTED_SECTOR_COUNT

            expected_fred_series = Set(
                reduce(
                    vcat,
                    [
                        String.(specification["series"])
                            for specification in
                            values(USPipeline.SOURCE_SPEC["fred_series"])
                    ],
                ),
            )
            collected_fred_series =
                Set(String.(keys(state.tables["fred_metadata"])))
            legacy_fred_series = setdiff(
                expected_fred_series,
                Set(["A576RC1"]),
            )
            @test legacy_fred_series ⊆ collected_fred_series
            @test collected_fred_series ⊆ expected_fred_series
            @test Set(String.(keys(state.tables["bls_rows"]))) ==
                Set(String.(values(USPipeline.SOURCE_SPEC["bls_series"])))

            qcew = state.tables["qcew"]
            @test qcew isa DataFrame
            @test nrow(qcew) > 0
            @test Set(
                [
                    "own_code",
                    "industry_code",
                    "annual_avg_estabs",
                    "annual_avg_emplvl",
                    "total_annual_wages",
                ]
            ) ⊆ Set(names(qcew))

            susb = state.tables["susb"]
            @test susb isa DataFrame
            @test nrow(susb) > 0
            @test Set(["naics", "firms", "establishments", "employment"]) ⊆
                Set(names(susb))
            @test state.tables["usda_farms"] > 0
        else
            @test true
        end
    end

    @testset "Configured API credentials are absent from raw persistence" begin
        api_key_names = ("FRED_API_KEY", "BEA_API_KEY", "BLS_API_KEY")
        configured = [
            Vector{UInt8}(codeunits(USPipeline.load_env()[name]))
                for name in api_key_names
                if !isempty(get(USPipeline.load_env(), name, ""))
        ]
        raw_files = all_regular_files(USPipeline.RAW_ROOT)
        leaking_file_count = 0
        for path in raw_files
            leaking_file_count += any(file_contains_any_literal(path, configured))
        end
        # Keep failure output limited to a count: credential values must never
        # be interpolated into the Test failure report.
        @test leaking_file_count == 0
    end

    @testset "Generated validation artifacts (when present)" begin
        machine_log = joinpath(USPipeline.VALIDATION_ROOT, "validation.toml")
        if isfile(machine_log)
            validation = TOML.parsefile(machine_log)
            @test validation["country"] == "US"
            @test Int(validation["sector_count"]) == EXPECTED_SECTOR_COUNT
            @test all(
                parameter -> String(parameter["status"]) in VALID_QA_STATUSES,
                validation["parameters"],
            )
            @test isfile(joinpath(USPipeline.VALIDATION_ROOT, "DATA_CHECKLIST.md"))
            @test isfile(joinpath(USPipeline.VALIDATION_ROOT, "TEST_LOG.md"))
        else
            @test true
        end

        baseline_paths = (
            joinpath(USPipeline.BASELINE_ROOT, "US_2024Q4_structural.jld2"),
            joinpath(USPipeline.BASELINE_ROOT, "US_2026Q1_nowcast.jld2"),
        )
        for path in baseline_paths
            isfile(path) || continue
            artifact = JLD2.load(path)
            @test Set(["parameters", "initial_conditions", "metadata"]) ⊆
                Set(keys(artifact))
            @test artifact["parameters"] isa AbstractDict
            @test artifact["initial_conditions"] isa AbstractDict
            @test artifact["metadata"] isa AbstractDict
            metadata = artifact["metadata"]
            haskey(metadata, "country") && @test metadata["country"] == "US"
            haskey(metadata, "sector_count") &&
                @test Int(metadata["sector_count"]) == EXPECTED_SECTOR_COUNT
            @test haskey(metadata, "output_measurement")
            measurement = metadata["output_measurement"]
            @test measurement["schema_version"] ==
                "beforeit-output-measurement.v1"
            @test measurement["method"] ==
                "origin_level_times_model_growth"
            legacy_measurements = Set(
                [
                    "real_gdp",
                    "real_household_consumption",
                    "real_government_consumption",
                    "real_exports",
                    "real_imports",
                ],
            )
            current_measurements = union(
                legacy_measurements,
                Set(["real_fixed_capitalformation", "wages"]),
            )
            artifact_measurements = Set(keys(measurement["series"]))
            if get(metadata, "data_truth_vintage", "") == "2026-08-04"
                @test artifact_measurements == current_measurements
                @test measurement["data_truth_vintage"] == "2026-08-04"
            else
                @test legacy_measurements ⊆ artifact_measurements
            end
            for series in values(measurement["series"])
                @test isfinite(series["scale"])
                @test series["scale"] > 0
                @test series["actual_value"] > 0
                @test series["raw_model_value"] > 0
            end
        end

        calibration_paths = (
            joinpath(
                USPipeline.CALIBRATION_ROOT,
                "US_2024_calibration_object.jld2",
            ),
            joinpath(
                USPipeline.CALIBRATION_ROOT,
                "US_2026Q1_nowcast_object.jld2",
            ),
        )
        for path in calibration_paths
            isfile(path) || continue
            artifact = JLD2.load(path)
            @test Set(["calibration_object", "metadata"]) ⊆ Set(keys(artifact))
            calibration = artifact["calibration_object"]
            @test calibration isa USPipeline.Bit.CalibrationData
            @test size(calibration.figaro["intermediate_consumption"], 1) ==
                EXPECTED_SECTOR_COUNT
            @test size(calibration.figaro["intermediate_consumption"], 2) ==
                EXPECTED_SECTOR_COUNT
            @test size(calibration.figaro["imports"]) ==
                (EXPECTED_SECTOR_COUNT, 1)
            @test all(isfinite, calibration.figaro["imports"])
            @test all(calibration.figaro["imports"] .>= 0)
            @test haskey(
                calibration.data,
                "real_household_consumption_quarterly",
            )
            metadata = artifact["metadata"]
            if get(metadata, "data_truth_vintage", "") == "2026-08-04"
                @test haskey(
                    calibration.data,
                    "real_fixed_capitalformation_quarterly",
                )
                @test haskey(calibration.data, "nominal_wages_quarterly")
                @test calibration.data["gdp_deflator_quarterly"] ≈
                    calibration.data["nominal_gdp_quarterly"] ./
                    calibration.data["real_gdp_quarterly"]
            end
            @test length(calibration.calibration["firms"]) ==
                EXPECTED_SECTOR_COUNT
            @test length(calibration.calibration["employees"]) ==
                EXPECTED_SECTOR_COUNT
        end
    end

    @testset "DuckDB persistence (when present)" begin
        if isfile(USPipeline.DATABASE_PATH)
            database = DuckDB.DB(USPipeline.DATABASE_PATH)
            connection = DuckDB.DBInterface.connect(database)
            try
                catalog = query_frame(
                    connection,
                    """
                    SELECT table_name, table_type
                    FROM information_schema.tables
                    WHERE table_schema = 'main'
                    """,
                )
                names_present = Set(String.(catalog.table_name))
                @test Set(
                    [
                        "acquisitions",
                        "source_checks",
                        "parameter_checks",
                        "observations",
                        "test_events",
                        "qa_status_summary",
                    ]
                ) ⊆ names_present

                for table_name in (
                        "acquisitions",
                        "source_checks",
                        "parameter_checks",
                        "observations",
                    )
                    count_frame = query_frame(
                        connection,
                        "SELECT count(*) AS n FROM $table_name",
                    )
                    @test count_frame.n[1] > 0
                end

                invalid_source_statuses = query_frame(
                    connection,
                    """
                    SELECT count(*) AS n
                    FROM source_checks
                    WHERE status NOT IN ('APPROVED', 'DUBIOUS', 'REJECTED', 'MISSING')
                    """,
                )
                @test invalid_source_statuses.n[1] == 0

                if "io_cells" in names_present
                    sector_shape = query_frame(
                        connection,
                        """
                        SELECT
                            count(DISTINCT commodity_code) AS commodities,
                            count(DISTINCT industry_code) AS industries
                        FROM io_cells
                        """,
                    )
                    @test sector_shape.commodities[1] == EXPECTED_SECTOR_COUNT
                    @test sector_shape.industries[1] == EXPECTED_SECTOR_COUNT
                end
                if "sector_annual" in names_present
                    sector_count = query_frame(
                        connection,
                        "SELECT count(DISTINCT code) AS n FROM sector_annual",
                    )
                    @test sector_count.n[1] == EXPECTED_SECTOR_COUNT
                end
            finally
                close(connection)
                close(database)
            end
        else
            @test true
        end
    end
end
