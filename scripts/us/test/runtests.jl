using Test
using Dates
using DataFrames
using DuckDB
using JLD2
using Random
using TOML

include(joinpath(@__DIR__, "..", "USPipeline.jl"))
using .USPipeline
include(
    joinpath(
        @__DIR__,
        "..",
        "migrate_calibration_firewall.jl",
    ),
)
using .USCalibrationFirewallMigration

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

    @testset "Source-aware output integration" begin
        fixture =
            USPipeline.USSupplyMakeDiagnostics.load_canonical_fixture(
            joinpath(
                USPipeline.SCRIPT_DIR,
                "accounting",
                "fixtures",
                "bea_2024_approved",
            ),
        )
        raw_rows(table) = [
            Dict{String, Any}(
                    "TableID" => cell.table_id,
                    "Year" => string(cell.year),
                    "RowCode" => cell.row_code,
                    "RowType" => cell.row_type,
                    "RowDescr" => cell.row_code,
                    "ColCode" => cell.column_code,
                    "ColType" => cell.column_type,
                    "ColDescr" => cell.column_code,
                    "DataValue" => string(cell.value),
                ) for cell in values(table.cells)
        ]
        state = USPipeline.RunState()
        state.tables["bea_io_259"] = raw_rows(fixture.use)
        state.tables["bea_io_262"] = raw_rows(fixture.supply)
        state.tables["bea_io_259_sha"] = fixture.use.source_sha256
        state.tables["bea_io_262_sha"] = fixture.supply.source_sha256

        USPipeline.build_io!(state)
        report = state.tables["supply_make_report"]
        @test USPipeline.USSupplyMakeDiagnostics.controls_pass(report)
        @test report.transformation ==
            :code_keyed_retail_aggregation_only
        @test report.balancing_applied === false
        @test size(report.raw_make) == (73, 71)
        @test size(report.aggregated_make) == (70, 68)
        @test size(report.raw_use) == (70, 71)
        @test size(report.aggregated_use) == (70, 68)

        symmetric = state.tables["symmetric_use_report"]
        @test USPipeline.USSymmetricSupplyUse.transformation_controls_pass(
            symmetric,
        )
        @test length(symmetric.residuals) == 420
        @test size(symmetric.published_symmetric_use) == (70, 70)
        @test size(symmetric.rounding_normalized_symmetric_use) == (70, 70)
        @test sum(symmetric.rounding_normalized_symmetric_use.values) ≈
            sum(report.aggregated_use.values) atol = 1.0e-6
        @test length(symmetric.negative_make_cells) == 9
        @test length(symmetric.negative_use_cells) == 5
        @test length(symmetric.negative_symmetric_cells) == 19
        @test symmetric.rounding_normalization_applied
        @test !symmetric.valuation_bridge_applied
        @test !symmetric.balancing_applied
        @test !symmetric.clipping_applied
        @test !symmetric.promotion_ready

        requirements = state.tables["requirements_report"]
        @test USPipeline.USRequirementsDiagnostics.requirements_controls_pass(
            requirements,
        )
        @test length(requirements.residuals) == 221
        @test size(requirements.total_requirements) == (73, 73)
        @test size(requirements.direct_requirements) == (73, 73)
        @test requirements.transformation ==
            :official_after_redefinitions_direct_times_market_share
        @test requirements.maximum_direct_agreement_error <= 1.0e-6
        @test requirements.maximum_total_requirements_agreement_error <=
            2.0e-6
        @test length(requirements.substantive_negative_direct_cells) == 5
        @test !requirements.clipping_applied
        @test !requirements.balancing_applied
        @test !requirements.promotion_ready

        requirements_transactions =
            state.tables["requirements_transaction_report"]
        @test USPipeline.USRequirementsDiagnostics.transaction_controls_pass(
            requirements_transactions,
        )
        @test length(requirements_transactions.residuals) == 3
        @test size(requirements_transactions.transactions) == (70, 70)
        @test sum(requirements_transactions.transactions.values) ≈
            21_012_023.990183584 atol = 1.0e-6
        @test sum(symmetric.rounding_normalized_symmetric_use.values) -
            sum(requirements_transactions.transactions.values) ≈
            426_517.0098164129 atol = 1.0e-6
        @test requirements_transactions.transformation ==
            :official_direct_output_weighted_retail_transaction_aggregation
        @test !requirements_transactions.clipping_applied
        @test !requirements_transactions.balancing_applied
        @test !requirements_transactions.promotion_ready

        requirements_comparison =
            state.tables["requirements_comparison_report"]
        @test USPipeline.USRequirementsDiagnostics.comparison_controls_pass(
            requirements_comparison,
        )
        @test length(requirements_comparison.residuals) == 3
        @test size(requirements_comparison.signed_difference) == (70, 70)
        @test requirements_comparison.signed_total_difference ≈
            426_517.0098164129 atol = 1.0e-6
        @test requirements_comparison.absolute_cell_difference ≈
            4_370_627.389108137 atol = 1.0e-6
        @test requirements_comparison.right_basis ==
            :official_after_redefinitions_direct_requirements_diagnostic
        @test requirements_comparison.maximum_absolute_difference_cell.row_code ==
            "42"
        @test requirements_comparison.maximum_absolute_difference_cell.column_code ==
            "23"
        @test !requirements_comparison.valuation_bridge_applied
        @test !requirements_comparison.balancing_applied
        @test !requirements_comparison.clipping_applied
        @test !requirements_comparison.promotion_ready

        commodity_output =
            state.tables["domestic_commodity_output_basic_price"]
        industry_output =
            state.tables["source_industry_output_basic_price"]
        supply_industry_output =
            state.tables["supply_industry_output_basic_price_t017"]
        @test length(commodity_output) == EXPECTED_SECTOR_COUNT
        @test length(industry_output) == EXPECTED_SECTOR_COUNT
        @test length(supply_industry_output) == EXPECTED_SECTOR_COUNT
        @test sum(commodity_output) == 49_706_494.0
        @test sum(industry_output) == 49_726_225.0
        @test supply_industry_output == industry_output
        @test sum(industry_output - commodity_output) == 19_731.0
        retail_index =
            findfirst(==("4A0"), state.tables["commodity_output_codes"])
        @test commodity_output[retail_index] == 2_403_974.0
        @test industry_output[retail_index] == 2_527_001.0

        closure = state.tables["io_closure_accounts"]
        @test Set(closure.commodity_code) == Set(["Other", "Used"])
        @test all(
            ==("explicit_unallocated_closure_account"),
            closure.allocation_policy,
        )
        @test closure[
            closure.commodity_code .== "Other",
            :domestic_output_basic_price_millions_usd,
        ] == [6_187.0]
        @test closure[
            closure.commodity_code .== "Used",
            :domestic_output_basic_price_millions_usd,
        ] == [13_553.0]

        reversed_state = USPipeline.RunState()
        reversed_state.tables["bea_io_259"] =
            reverse(state.tables["bea_io_259"])
        reversed_state.tables["bea_io_262"] =
            reverse(state.tables["bea_io_262"])
        reversed_state.tables["bea_io_259_sha"] =
            fixture.use.source_sha256
        reversed_state.tables["bea_io_262_sha"] =
            fixture.supply.source_sha256
        USPipeline.build_io!(reversed_state)
        reordered_codes =
            reversed_state.tables["commodity_output_codes"]
        reordered_values =
            reversed_state.tables[
            "domestic_commodity_output_basic_price",
        ]
        by_code = Dict(
            code => value for
                (code, value) in zip(reordered_codes, reordered_values)
        )
        @test [
            by_code[code] for
                code in state.tables["commodity_output_codes"]
        ] == commodity_output

        perturbed_t017_state = USPipeline.RunState()
        perturbed_t017_state.tables["bea_io_259"] =
            deepcopy(state.tables["bea_io_259"])
        perturbed_t017_state.tables["bea_io_262"] =
            deepcopy(state.tables["bea_io_262"])
        t017_111ca = only(
            row for row in perturbed_t017_state.tables["bea_io_262"]
                if row["RowCode"] == "T017" &&
                row["ColCode"] == "111CA"
        )
        t017_111ca["DataValue"] = string(
            parse(Float64, t017_111ca["DataValue"]) + 1.0,
        )
        perturbed_t017_state.tables["bea_io_259_sha"] =
            fixture.use.source_sha256
        perturbed_t017_state.tables["bea_io_262_sha"] =
            fixture.supply.source_sha256
        USPipeline.build_io!(perturbed_t017_state)
        agriculture_index = findfirst(
            ==("111CA"),
            perturbed_t017_state.tables["industry_output_codes"],
        )
        @test perturbed_t017_state.tables[
            "source_industry_output_basic_price",
        ][agriculture_index] == 572_741.0
        @test perturbed_t017_state.tables[
            "supply_industry_output_basic_price_t017",
        ][agriculture_index] == 572_742.0

        installed =
            USPipeline.Bit.load_us_calibration(:structural).calibration_object
        legacy_object = USPipeline.Bit.CalibrationData(
            deepcopy(installed.calibration),
            deepcopy(installed.figaro),
            deepcopy(installed.data),
            deepcopy(installed.ea),
            installed.max_calibration_date,
            installed.estimation_date,
        )
        legacy_parameters, legacy_initial_conditions =
            USPipeline.Bit.get_params_and_initial_conditions(
            legacy_object,
            DateTime(2024, 12, 31);
            scale = Float64(USPipeline.SOURCE_SPEC["pipeline"]["scale"]),
            use_growth_rate_ar1 = false,
        )

        source_aware_figaro = deepcopy(installed.figaro)
        source_aware_figaro["use_explicit_commodity_output"] = true
        source_aware_figaro["diagnose_commodity_balance"] = true
        source_aware_figaro["use_commodity_balance_inventory"] = false
        source_aware_figaro["domestic_commodity_output_basic_price"] =
            reshape(copy(commodity_output), EXPECTED_SECTOR_COUNT, 1)
        source_aware_figaro["commodity_output_codes"] =
            String.(state.tables["commodity_output_codes"])
        source_aware_figaro["commodity_output_basis"] =
            "BEA_TABLE_262_T007_COMMODITY_BASIC_PRICE"
        source_aware_figaro["industry_output_codes"] =
            String.(state.tables["industry_output_codes"])
        source_aware_figaro["industry_output_basis"] =
            "BEA_TABLE_259_T018_INDUSTRY_BASIC_PRICE"
        source_aware_figaro["source_industry_output_basic_price"] =
            reshape(copy(industry_output), EXPECTED_SECTOR_COUNT, 1)
        source_aware_object = USPipeline.Bit.CalibrationData(
            deepcopy(installed.calibration),
            source_aware_figaro,
            deepcopy(installed.data),
            deepcopy(installed.ea),
            installed.max_calibration_date,
            installed.estimation_date,
        )
        source_aware_parameters, source_aware_initial_conditions =
            USPipeline.Bit.get_params_and_initial_conditions(
            source_aware_object,
            DateTime(2024, 12, 31);
            scale = Float64(USPipeline.SOURCE_SPEC["pipeline"]["scale"]),
            use_growth_rate_ar1 = false,
        )

        registered_parameter_ids = Set(
            String(row["parameter_id"])
                for row in
                TOML.parsefile(
                    joinpath(
                        USPipeline.SCRIPT_DIR,
                        "calibration",
                        "parameter_registry.toml",
                    ),
                )["parameter"]
        )
        @test Set(keys(source_aware_parameters)) ==
            registered_parameter_ids
        @test source_aware_parameters[
            "use_commodity_balance_inventory",
        ] === false
        @test !haskey(
            source_aware_parameters,
            "diagnose_commodity_balance",
        )
        parameter_comparison_keys = setdiff(
            intersect(
                Set(keys(source_aware_parameters)),
                Set(keys(legacy_parameters)),
            ),
            Set(["use_commodity_balance_inventory"]),
        )
        @test setdiff(
            Set(keys(source_aware_parameters)),
            Set(keys(legacy_parameters)),
        ) == Set{String}()
        @test setdiff(
            Set(keys(legacy_parameters)),
            Set(keys(source_aware_parameters)),
        ) == Set{String}()
        for key in parameter_comparison_keys
            @test isequal(
                source_aware_parameters[key],
                legacy_parameters[key],
            )
        end

        commodity_diagnostic_keys = Set(
            [
                "S_s",
                "commodity_balance_supply_s",
                "commodity_balance_modeled_uses_s",
                "inventory_statistical_discrepancy_s",
                "commodity_balance_residual_s",
                "domestic_commodity_output_g",
                "commodity_supply_g",
                "modeled_commodity_uses_g",
                "unreconciled_commodity_gap_g",
                "commodity_balance_closure_applied",
                "commodity_output_codes",
            ]
        )
        shared_initial_condition_keys = setdiff(
            intersect(
                Set(keys(source_aware_initial_conditions)),
                Set(keys(legacy_initial_conditions)),
            ),
            commodity_diagnostic_keys,
        )
        for key in shared_initial_condition_keys
            @test isequal(
                source_aware_initial_conditions[key],
                legacy_initial_conditions[key],
            )
        end
        @test setdiff(
            Set(keys(source_aware_initial_conditions)),
            Set(keys(legacy_initial_conditions)),
        ) == Set(["commodity_output_codes"])
        @test setdiff(
            Set(keys(legacy_initial_conditions)),
            Set(keys(source_aware_initial_conditions)),
        ) == Set(
            [
                "S_s",
                "commodity_balance_supply_s",
                "commodity_balance_modeled_uses_s",
                "inventory_statistical_discrepancy_s",
                "commodity_balance_residual_s",
            ]
        )
        @test !haskey(source_aware_initial_conditions, "S_s")
        @test !haskey(
            source_aware_initial_conditions,
            "inventory_statistical_discrepancy_s",
        )
        @test source_aware_initial_conditions[
            "commodity_balance_closure_applied",
        ] === false
        @test source_aware_initial_conditions[
            "unreconciled_commodity_gap_g",
        ] ≈
            source_aware_initial_conditions["commodity_supply_g"] -
            source_aware_initial_conditions["modeled_commodity_uses_g"]
        @test sum(
            source_aware_initial_conditions[
                "unreconciled_commodity_gap_g",
            ],
        ) ≈ -99_596.0625219554 atol = 1.0e-6

        wrong_year_state = USPipeline.RunState()
        wrong_year_state.tables["bea_io_259"] =
            deepcopy(state.tables["bea_io_259"])
        wrong_year_state.tables["bea_io_262"] =
            deepcopy(state.tables["bea_io_262"])
        for row in wrong_year_state.tables["bea_io_259"]
            row["Year"] = "2023"
        end
        for row in wrong_year_state.tables["bea_io_262"]
            row["Year"] = "2023"
        end
        wrong_year_state.tables["bea_io_259_sha"] =
            fixture.use.source_sha256
        wrong_year_state.tables["bea_io_262_sha"] =
            fixture.supply.source_sha256
        @test_throws ErrorException USPipeline.build_io!(wrong_year_state)

        extra_control_state = USPipeline.RunState()
        extra_control_state.tables["bea_io_259"] =
            deepcopy(state.tables["bea_io_259"])
        extra_control_state.tables["bea_io_262"] =
            deepcopy(state.tables["bea_io_262"])
        extra_control = deepcopy(
            only(
                row for row in extra_control_state.tables["bea_io_259"]
                    if row["RowCode"] == "T005" &&
                    row["ColCode"] == "F010"
            ),
        )
        extra_control["ColCode"] = "FZZ"
        extra_control["ColDescr"] = "Unexpected final-use control"
        extra_control["DataValue"] = "0"
        push!(extra_control_state.tables["bea_io_259"], extra_control)
        extra_control_state.tables["bea_io_259_sha"] =
            fixture.use.source_sha256
        extra_control_state.tables["bea_io_262_sha"] =
            fixture.supply.source_sha256
        @test_throws ErrorException USPipeline.build_io!(
            extra_control_state,
        )
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
        @test bridge.scientific_status ==
            "REJECTED_NOT_CELL_IDENTIFIED"
        @test bridge.runtime_status ==
            "LEGACY_RESEARCH_PATH_STILL_APPLIED_PENDING_PRODUCER_PRICE_ADAPTER"
        @test !bridge.cell_identified
        @test bridge.diagnostic_only
        @test_throws ErrorException USPipeline.purchasers_to_basic_price_vector(
            Dict{Tuple{String, String}, Float64}(
                ("A", "T013") => 1.0,
                ("A", "T016") => 0.0,
            ),
            ["A"],
        )
    end

    @testset "Source-control and model-mapping status separation" begin
        state = USPipeline.RunState()
        USPipeline.record_parameter_check!(
            state,
            "imports",
            "synthetic signed import control",
            "REJECTED";
            source_control_reconciles = "APPROVED",
            model_mapping_admissible = "REJECTED",
            detail = "The source control passes but the proposed model mapping is rejected.",
        )
        USPipeline.record_parameter_check!(
            state,
            "purchasers_to_basic_price",
            "synthetic valuation control",
            "REJECTED";
            source_control_reconciles = "APPROVED",
            model_mapping_admissible = "REJECTED",
            detail = "The arithmetic ratio passes but has no admissible recipient-cell allocation.",
        )
        ledger = USPipeline.parameter_ledger(state)
        for parameter in ("imports", "purchasers_to_basic_price")
            row = only(
                eachrow(
                    ledger[ledger.parameter .== parameter, :],
                ),
            )
            @test row.status == "REJECTED"
            @test row.source_control_reconciles == "APPROVED"
            @test row.model_mapping_admissible == "REJECTED"
        end
        @test_throws ErrorException USPipeline.record_parameter_check!(
            state,
            "invalid_overall",
            "synthetic",
            "APPROVED";
            source_control_reconciles = "APPROVED",
            model_mapping_admissible = "REJECTED",
        )
        @test_throws ErrorException USPipeline.record_parameter_check!(
            state,
            "invalid_dimension",
            "synthetic",
            "APPROVED";
            source_control_reconciles = "UNKNOWN",
            model_mapping_admissible = "APPROVED",
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
        @test registry["quarterly_nipa_lines"]["nominal_household_consumption_quarterly"] ==
            "T10105:2"
        @test registry["quarterly_nipa_lines"]["nominal_gross_private_domestic_investment_quarterly"] ==
            "T10105:7"
        @test registry["quarterly_nipa_lines"]["nominal_fixed_investment_quarterly"] ==
            "T10105:8"
        @test registry["quarterly_nipa_lines"]["nominal_inventory_investment_quarterly"] ==
            "T10105:14"
        @test registry["quarterly_nipa_lines"]["nominal_exports_quarterly"] ==
            "T10105:16"
        @test registry["quarterly_nipa_lines"]["nominal_imports_quarterly"] ==
            "T10105:19"
        @test registry["quarterly_nipa_lines"]["nominal_government_consumption_and_investment_quarterly"] ==
            "T10105:22"
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

    @testset "NIPA nominal expenditure controls" begin
        data = Dict{String, Any}(
            "nominal_gdp_quarterly" =>
                [7_456_295.5, 7_966_430.25],
            "nominal_household_consumption_quarterly" =>
                [5_087_823.0, 5_408_737.0],
            "nominal_gross_private_domestic_investment_quarterly" =>
                [1_315_457.5, 1_408_504.0],
            "nominal_fixed_investment_quarterly" =>
                [1_311_010.25, 1_415_517.25],
            "nominal_inventory_investment_quarterly" =>
                [4_447.25, -7_013.25],
            "nominal_exports_quarterly" =>
                [812_063.75, 877_175.75],
            "nominal_imports_quarterly" =>
                [1_046_730.25, 1_082_164.75],
            "nominal_government_consumption_and_investment_quarterly" =>
                [1_287_681.25, 1_354_178.75],
        )
        @test USPipeline.nipa_nominal_expenditure_residuals(data) ==
            [0.25, -0.5]
        @test USPipeline.nipa_private_investment_residuals(data) ==
            [0.0, 0.0]
        @test data["nominal_inventory_investment_quarterly"][2] < 0

        missing_component = copy(data)
        delete!(
            missing_component,
            "nominal_inventory_investment_quarterly",
        )
        @test_throws ErrorException USPipeline.nipa_nominal_expenditure_residuals(
            missing_component,
        )

        misaligned = deepcopy(data)
        push!(misaligned["nominal_exports_quarterly"], 1.0)
        @test_throws ErrorException USPipeline.nipa_nominal_expenditure_residuals(
            misaligned,
        )
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

    @testset "Calibration firewall" begin
        @test !isdefined(
            USPipeline,
            :apply_forecast_parameter_overrides!,
        )
        @test !isdefined(USPipeline, :FORECAST_CALIBRATION_FILE)

        correction_contract = TOML.parsefile(
            joinpath(
                USPipeline.SCRIPT_DIR,
                "forecast_calibration.toml",
            ),
        )
        @test correction_contract["artifact_class"] == "H"
        @test correction_contract["eligible_for_raw_calibration"] === false
        @test correction_contract["raw_forecast_required_alongside"] === true

        baseline = USPipeline.Bit.load_us_baseline(:structural)
        panel = DataFrame(period = [Date(2024, 12, 31)])
        for specification in
            USPipeline.output_measurement_specifications()
            panel[!, specification.panel_column] = [1.0]
        end
        measurement = USPipeline.output_measurement_metadata(
            panel,
            DateTime(2024, 12, 31),
            "2024-Q4",
            baseline.parameters,
            baseline.initial_conditions;
            seed = 91,
        )
        @test all(
            !haskey(series, "path_correction")
                for series in values(measurement["series"])
        )

        mktempdir() do directory
            temporary_paths = String[]
            for source in
                USCalibrationFirewallMigration.DEFAULT_ARTIFACT_PATHS
                target = joinpath(directory, basename(source))
                cp(source, target)
                push!(temporary_paths, target)
            end
            results =
                USCalibrationFirewallMigration.migrate_all!(
                temporary_paths,
            )
            @test length(results) == 4
            @test all(
                occursin(r"^[0-9a-f]{64}$", result.migrated_sha256)
                    for result in results
            )
            @test all(
                USCalibrationFirewallMigration.validate_migrated_artifact(
                        path,
                    ) isa AbstractDict for path in temporary_paths
            )
            rerun =
                USCalibrationFirewallMigration.migrate_all!(
                temporary_paths,
            )
            @test all(!result.changed for result in rerun)
            migrated_calibration =
                USCalibrationFirewallMigration.validate_migrated_artifact(
                temporary_paths[3],
            )
            @test migrated_calibration["calibration_object"] isa
                USPipeline.Bit.CalibrationData
        end

        synthetic_payload = Dict{String, Any}(
            "parameters" => Dict{String, Any}(
                name => 100.0
                    for name in
                    USCalibrationFirewallMigration.POLICY_PARAMETER_NAMES
            ),
        )
        synthetic_metadata = Dict{String, Any}(
            "forecast_calibration" => Dict{String, Any}(
                "estimated_parameters" => Dict{String, Any}(
                    name => Float64(index)
                        for (index, name) in enumerate(
                            USCalibrationFirewallMigration.POLICY_PARAMETER_NAMES,
                        )
                ),
            ),
        )
        restored =
            USCalibrationFirewallMigration.restored_policy_parameters!(
            synthetic_payload,
            synthetic_metadata,
        )
        @test restored == Dict(
            name => Float64(index)
                for (index, name) in enumerate(
                    USCalibrationFirewallMigration.POLICY_PARAMETER_NAMES,
                )
        )
        @test synthetic_payload["parameters"] == restored

        scale = Float64(USPipeline.SOURCE_SPEC["pipeline"]["scale"])
        for (vintage, origin) in (
                (:structural, DateTime(2024, 12, 31)),
                (:nowcast, DateTime(2026, 3, 31)),
            )
            installed = USPipeline.Bit.load_us_baseline(vintage)
            calibration =
                USPipeline.Bit.load_us_calibration(vintage)
            raw_parameters, _ =
                USPipeline.Bit.get_params_and_initial_conditions(
                calibration.calibration_object,
                origin;
                scale,
                use_growth_rate_ar1 = false,
            )
            for name in
                USCalibrationFirewallMigration.POLICY_PARAMETER_NAMES
                @test installed.parameters[name] ≈ raw_parameters[name]
            end
            @test haskey(
                installed.metadata,
                "calibration_firewall",
            )
            @test !haskey(
                installed.metadata,
                "forecast_calibration",
            )
            @test haskey(
                calibration.metadata,
                "calibration_firewall",
            )
            @test !haskey(
                calibration.metadata,
                "forecast_calibration",
            )
            @test all(
                !haskey(series, "path_correction")
                    for series in values(
                        installed.metadata["output_measurement"]["series"],
                    )
            )
        end
    end

    @testset "68-sector model contract" begin
        pipeline = USPipeline.SOURCE_SPEC["pipeline"]
        @test Int(pipeline["structural_year"]) == 2024
        @test occursin(
            r"(^|[^0-9])68([^0-9]|$)",
            String(pipeline["model_sector_system"]),
        )
        @test Int(pipeline["source_industry_count"]) == 71
        @test Int(pipeline["modeled_commodity_count"]) == 68
        @test Int.(pipeline["raw_use_shape"]) == [68, 71]
        @test Int.(pipeline["model_bridge_shape"]) == [68, 68]
        @test String.(pipeline["retail_source_industries"]) ==
            ["441", "445", "452", "4A0"]
        @test String(pipeline["retail_model_commodity"]) == "4A0"
        @test EXPECTED_SECTOR_COUNT == 68
    end

    @testset "U.S. per-period accounting gate" begin
        gate_path = joinpath(
            USPipeline.VALIDATION_ROOT,
            "ACCOUNTING_GATES.toml",
        )
        gate = TOML.parsefile(gate_path)
        @test gate["schema_version"] ==
            "beforeit-us-accounting-gates.v2"
        @test gate["gate_status"] == "FAIL"
        @test gate["diagnostic_status"] ==
            "OBSERVATION_LAYER_REPAIRED_LATENT_STATE_FAILED"
        @test occursin(
            "nominal_capitalformation",
            gate["formula"],
        )
        @test occursin("source_gpdi", gate["observation_formula"])
        @test occursin(
            "model_implied",
            gate["latent_state_formula"],
        )
        @test occursin(
            "Do not add",
            gate["prohibited_closure"],
        )
        @test occursin(
            "agent state",
            gate["next_implementation"],
        )
        gate_split = gate["gate_split"]
        @test gate_split["observation_layer_status"] == "PASS"
        @test gate_split["latent_state_status"] == "FAIL"
        @test gate_split["inventory_stock_status"] == "MISSING"
        @test gate_split["supply_make_valuation_status"] == "FAIL"
        @test gate_split["full_accounting_status"] == "FAIL"
        @test gate_split["promotion_status"] == "FAIL"
        @test gate_split["origin_admissible"] === false
        @test gate_split["mapping_evidence_class"] ==
            "OBSERVATION_ONLY_NOT_APPROVAL"
        source_tolerance =
            Float64(gate["source_rounding_absolute_tolerance"])
        @test source_tolerance == 1.0
        candidate_evidence = gate["candidate_evidence"]
        candidate_manifest_path = normpath(
            joinpath(
                USPipeline.REPO_ROOT,
                candidate_evidence["manifest"],
            ),
        )
        @test USCalibrationFirewallMigration.file_sha256(
            candidate_manifest_path,
        ) == candidate_evidence["manifest_sha256"]
        candidate_manifest = TOML.parsefile(candidate_manifest_path)
        @test candidate_manifest["schema_version"] ==
            "beforeit-us-opening-accounting-candidates-manifest.v1"
        @test candidate_manifest["classification"] ==
            "REVISED_CURRENT_VINTAGE_DIAGNOSTIC"
        @test candidate_manifest["forecast_origin_admissible"] ===
            false
        @test candidate_manifest["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test Int(candidate_manifest["candidate_count"]) == 2
        @test candidate_manifest["build_contract_sha256"] ==
            candidate_evidence["build_contract_sha256"]
        @test candidate_manifest["builder_sha256"] ==
            candidate_evidence["builder_sha256"]
        manifest_candidates = Dict(
            String(row["artifact_path"]) => row
                for row in candidate_manifest["candidate"]
        )
        @test Set(keys(manifest_candidates)) == Set(
            String(row["candidate_artifact"])
                for row in gate["vintages"]
        )
        @test candidate_evidence["legacy_artifacts_unchanged"] ===
            true
        @test candidate_evidence["byte_rebuild_deterministic"] ===
            true
        @test candidate_evidence["origin_admissible"] === false
        @test candidate_evidence["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test all(
            occursin(r"^[0-9a-f]{64}$", String(hash))
                for (key, hash) in gate["source_artifacts"]
                if endswith(String(key), "_sha256")
        )
        @test gate["source_artifacts"]["source_status"] ==
            "APPROVED_ARCHIVED"
        discrepancy_gate = gate["commodity_discrepancy"]
        @test Int(discrepancy_gate["positive_sector_count"]) == 26
        @test Int(discrepancy_gate["negative_sector_count"]) == 42
        @test Float64(discrepancy_gate["positive_sum"]) +
            Float64(discrepancy_gate["negative_sum"]) ≈
            Float64(discrepancy_gate["annual_sum"]) atol = 1.0e-6

        inventory_control = gate["official_inventory_control"]
        inventory_components =
            Float64(inventory_control["modeled_68_rows"]) +
            Float64(inventory_control["used_code"]) +
            Float64(inventory_control["other_code"])
        @test abs(
            inventory_components -
                Float64(inventory_control["published_total"]),
        ) == Float64(
            inventory_control["component_rounding_difference"],
        )
        @test abs(
            Float64(
                inventory_control[
                    "correlation_with_commodity_discrepancy",
                ],
            ),
        ) < 0.04
        @test occursin(
            "not a defensible proxy",
            inventory_control["conclusion"],
        )

        decomposition = gate["diagnostic_decomposition"]
        decomposition_sum = sum(
            Float64(decomposition[key])
                for key in (
                    "diagnostic_basic_price_f030",
                    "supply_mapping",
                    "intermediate_use_construction",
                    "household_use_rescaling",
                    "government_use_rescaling",
                    "capital_use_construction",
                    "export_use_rescaling",
                    "published_cell_and_ratio_rounding",
                )
        )
        diagnostic_rounding =
            Float64(decomposition["rounding_tolerance"])
        @test decomposition_sum ≈
            Float64(decomposition["total"]) atol = diagnostic_rounding
        @test Float64(decomposition["total"]) ≈
            Float64(discrepancy_gate["annual_sum"]) atol =
            diagnostic_rounding

        supply_decomposition = gate["supply_mapping_decomposition"]
        @test sum(
            Float64(supply_decomposition[key])
                for key in (
                    "industry_output_minus_commodity_output",
                    "intermediate_product_tax_netting",
                    "output_control_rounding",
                    "import_adjustment",
                )
        ) ≈ Float64(supply_decomposition["total"]) atol = 1.0e-6
        @test Float64(
            supply_decomposition[
                "correlation_with_commodity_discrepancy",
            ],
        ) > 0.87
        @test Float64(supply_decomposition["univariate_r_squared"]) >
            0.77
        @test Set(String.(gate["required_repairs"]["items"])) >= Set(
            [
                "origin_vintage_t10105_macro_component_anchors_for_each_forecast_origin",
                "latent_agent_state_and_sector_demand_reconciliation_to_macro_controls",
                "signed_inventory_investment_separate_from_nonnegative_inventory_stock",
                "table_262_t007_supply_make_bridge",
                "explicit_other_and_used_closure_accounts",
            ],
        )
        tolerance = Float64(gate["absolute_tolerance"])
        expected = Dict(
            "structural_2024Q4" => :structural,
            "nowcast_2026Q1" => :nowcast,
        )
        for vintage_gate in gate["vintages"]
            vintage = expected[String(vintage_gate["id"])]
            baseline = USPipeline.Bit.load_us_baseline(vintage)
            @test USCalibrationFirewallMigration.file_sha256(
                baseline.path,
            ) == vintage_gate["artifact_sha256"]

            # The frozen legacy artifact remains useful as a controlled
            # diagnostic, but its opening model-state wedge is not a pass.
            Random.seed!(20260803)
            legacy_model = USPipeline.Bit.Model(
                deepcopy(baseline.parameters),
                deepcopy(baseline.initial_conditions),
            )
            USPipeline.Bit.run!(
                legacy_model,
                4;
                parallel = false,
            )
            legacy_residuals =
                USPipeline.Bit.get_accounting_residuals(
                legacy_model.data,
            )
            legacy_opening =
                legacy_residuals.gdp_and_expenditure[1]
            legacy_opening_share =
                legacy_opening / legacy_model.data.nominal_gdp[1]
            discrepancy = sum(
                baseline.initial_conditions[
                    "inventory_statistical_discrepancy_s",
                ],
            )
            @test discrepancy ≈
                Float64(
                vintage_gate["annual_commodity_discrepancy_sum"],
            ) atol = tolerance
            inferred_timescale = legacy_opening / discrepancy
            @test inferred_timescale ≈
                Float64(vintage_gate["inferred_timescale"]) atol =
                1.0e-12
            @test legacy_opening ≈
                Float64(
                vintage_gate[
                    "residual_from_commodity_discrepancy",
                ],
            ) atol = tolerance
            @test legacy_opening ≈
                Float64(vintage_gate["opening_residual"]) atol = tolerance
            @test legacy_opening_share ≈
                Float64(vintage_gate["opening_residual_share_gdp"]) atol =
                1.0e-12
            @test abs(legacy_opening) > tolerance
            @test abs(legacy_opening) >
                10 *
                abs(
                Float64(
                    vintage_gate["official_inventory_investment"],
                ),
            )
            @test abs(
                Float64(
                    vintage_gate["official_nipa_identity_residual"],
                ),
            ) <= 0.5
            @test maximum(
                abs,
                legacy_residuals.gdp_and_expenditure[2:end],
            ) <= tolerance
            @test maximum(
                abs,
                legacy_residuals.gdp_and_expenditure_real[2:end],
            ) <= tolerance
            @test maximum(
                abs,
                legacy_residuals.income_and_production,
            ) <= tolerance

            candidate_path = normpath(
                joinpath(
                    USPipeline.REPO_ROOT,
                    vintage_gate["candidate_artifact"],
                ),
            )
            manifest_candidate = manifest_candidates[
                String(vintage_gate["candidate_artifact"]),
            ]
            @test USCalibrationFirewallMigration.file_sha256(
                candidate_path,
            ) == vintage_gate["candidate_artifact_sha256"]
            @test manifest_candidate["artifact_sha256"] ==
                vintage_gate["candidate_artifact_sha256"]
            @test manifest_candidate["semantic_sha256"] ==
                vintage_gate["candidate_semantic_sha256"]
            @test Int(manifest_candidate["diagnostic_seed"]) ==
                Int(vintage_gate["diagnostic_seed"])
            @test manifest_candidate["origin_admissible"] === false
            @test manifest_candidate["overall_accounting_promotion"] ==
                "FAIL"
            candidate_payload = JLD2.load(candidate_path)
            @test Set(keys(candidate_payload)) ==
                Set(["parameters", "initial_conditions", "metadata"])
            candidate_parameters = candidate_payload["parameters"]
            candidate_initial_conditions =
                candidate_payload["initial_conditions"]
            candidate_metadata = candidate_payload["metadata"]
            @test candidate_metadata["semantic_sha256"] ==
                vintage_gate["candidate_semantic_sha256"]
            @test candidate_metadata["promotion_status"] ==
                "RESEARCH_ONLY_NOT_PROMOTED"
            @test candidate_metadata["forecast_origin_admissible"] ===
                false
            pipeline_reconciliation =
                USPipeline.opening_macro_reconciliation_metadata(
                candidate_parameters,
                candidate_initial_conditions;
                seed = Int(vintage_gate["diagnostic_seed"]),
            )
            @test pipeline_reconciliation["observation_layer_gate"] ==
                "PASS"
            @test pipeline_reconciliation[
                "latent_state_reconciliation_gate",
            ] == "FAIL"
            @test pipeline_reconciliation[
                "structural_supply_use_gate",
            ] == "FAIL_UNRECONCILED"
            @test pipeline_reconciliation["full_accounting_gate"] ==
                "FAIL"
            @test pipeline_reconciliation[
                "model_numeric_tolerance",
            ] == tolerance
            @test pipeline_reconciliation[
                "maximum_absolute_observation_gap",
            ] <= tolerance
            @test !haskey(candidate_initial_conditions, "S_s")
            @test !haskey(
                candidate_initial_conditions,
                "inventory_statistical_discrepancy_s",
            )
            @test candidate_initial_conditions[
                "commodity_balance_closure_applied",
            ] === false
            @test sum(
                candidate_initial_conditions[
                    "unreconciled_commodity_gap_g",
                ],
            ) ≈ Float64(
                vintage_gate[
                    "candidate_unreconciled_commodity_gap_annual_sum",
                ],
            ) atol = tolerance

            candidate_commodity =
                candidate_metadata["commodity_diagnostic"]
            @test candidate_commodity["closure_applied"] === false
            @test candidate_commodity[
                "mapped_to_inventory_flow",
            ] === false
            @test candidate_commodity[
                "mapped_to_inventory_stock",
            ] === false
            @test Float64(candidate_commodity["annual_sum"]) ≈
                Float64(
                gate["candidate_commodity_diagnostic"][
                    "annual_sum",
                ],
            ) atol = tolerance

            candidate_seed = Int(vintage_gate["diagnostic_seed"])
            Random.seed!(candidate_seed)
            candidate_model = USPipeline.Bit.Model(
                deepcopy(candidate_parameters),
                deepcopy(candidate_initial_conditions),
            )
            candidate_implied =
                USPipeline.Bit.model_implied_opening_macro(
                candidate_model,
            )
            candidate_opening_residuals =
                USPipeline.Bit.get_accounting_residuals(
                candidate_model.data,
            )
            observed_opening =
                first(
                candidate_opening_residuals.gdp_and_expenditure,
            )
            @test abs(observed_opening) <= source_tolerance
            @test abs(
                observed_opening -
                    Float64(
                    vintage_gate["observed_opening_residual"],
                ),
            ) <= source_tolerance
            @test observed_opening ≈
                Float64(
                manifest_candidate[
                    "observed_expenditure_residual",
                ],
            ) atol = tolerance
            @test observed_opening ≈
                Float64(
                vintage_gate["official_nipa_identity_residual"],
            ) atol = tolerance
            @test candidate_implied.expenditure_residual ≈
                Float64(
                vintage_gate[
                    "model_implied_opening_residual",
                ],
            ) atol = tolerance
            @test candidate_implied.expenditure_residual ≈
                Float64(
                manifest_candidate[
                    "model_implied_expenditure_residual",
                ],
            ) atol = tolerance
            @test abs(candidate_implied.expenditure_residual) >
                tolerance
            @test candidate_implied.expenditure_residual /
                candidate_implied.nominal_gdp ≈
                Float64(
                vintage_gate["opening_residual_share_gdp"],
            ) atol = 1.0e-12

            reconciliation =
                candidate_metadata["opening_macro_reconciliation"]
            @test Int(reconciliation["diagnostic_seed"]) ==
                candidate_seed
            @test reconciliation["observation_layer_gate"] ==
                "PASS_AT_SOURCE_ROUNDING"
            @test reconciliation[
                "latent_state_reconciliation_gate",
            ] == "FAIL"
            @test reconciliation["structural_supply_use_gate"] ==
                "FAIL"
            @test reconciliation["inventory_stock_gate"] ==
                "FAIL_MISSING_INDEPENDENT_QUARTER_END_STOCK"
            @test reconciliation["full_accounting_gate"] == "FAIL"
            @test reconciliation["forecast_promotion_gate"] == "FAIL"
            @test Float64(
                reconciliation["source_expenditure_residual"],
            ) ≈ observed_opening atol = tolerance
            @test Float64(
                reconciliation[
                    "maximum_absolute_component_gap",
                ],
            ) ≈ Float64(
                vintage_gate["maximum_absolute_component_gap"],
            ) atol = tolerance
            @test Float64(
                reconciliation[
                    "source_values",
                ]["nominal_inventory_investment"],
            ) == Float64(
                vintage_gate["official_inventory_investment"],
            )

            component = vintage_gate["component_comparison"]
            component_keys = Dict(
                "nominal_gdp" =>
                    "model_minus_source_nominal_gdp",
                "nominal_household_consumption" =>
                    "model_minus_source_pce",
                "nominal_gross_private_domestic_investment" =>
                    "model_minus_source_gpdi",
                "nominal_fixed_investment" =>
                    "model_minus_source_fixed_investment",
                "nominal_inventory_investment" =>
                    "model_minus_source_inventory_investment",
                "nominal_exports" =>
                    "model_minus_source_exports",
                "nominal_imports" =>
                    "model_minus_source_imports",
                "nominal_government_consumption_and_investment" =>
                    "model_minus_source_government_consumption_and_investment",
            )
            for (
                    reconciliation_key,
                    component_key,
                ) in component_keys
                @test Float64(
                    reconciliation["model_minus_source"][
                        reconciliation_key,
                    ],
                ) ≈ Float64(component[component_key]) atol = tolerance
            end

            USPipeline.Bit.run!(
                candidate_model,
                4;
                parallel = false,
            )
            candidate_residuals =
                USPipeline.Bit.get_accounting_residuals(
                candidate_model.data,
            )
            @test maximum(
                abs,
                candidate_residuals.gdp_and_expenditure[2:end],
            ) <= tolerance
            @test maximum(
                abs,
                candidate_residuals.gdp_and_expenditure_real[2:end],
            ) <= tolerance
            @test maximum(
                abs,
                candidate_residuals.income_and_production,
            ) <= tolerance
            @test candidate_metadata["simulated_accounting"][
                "gate",
            ] == "PASS_AFTER_OPENING"
            @test candidate_metadata["gate_split"][
                "overall_accounting_promotion",
            ] == "FAIL"
            @test vintage_gate[
                "overall_accounting_promotion_status",
            ] == "FAIL"
            @test vintage_gate["origin_admissible"] === false
        end

        structural =
            USPipeline.Bit.load_us_baseline(:structural)
        sector_discrepancy = structural.initial_conditions[
            "inventory_statistical_discrepancy_s",
        ]
        positive = sector_discrepancy[sector_discrepancy .> 0]
        negative = sector_discrepancy[sector_discrepancy .< 0]
        @test length(positive) ==
            Int(discrepancy_gate["positive_sector_count"])
        @test length(negative) ==
            Int(discrepancy_gate["negative_sector_count"])
        @test sum(positive) ≈
            Float64(discrepancy_gate["positive_sum"]) atol = tolerance
        @test sum(negative) ≈
            Float64(discrepancy_gate["negative_sum"]) atol = tolerance
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
            parameters_by_name = Dict(
                String(parameter["name"]) => parameter
                    for parameter in validation["parameters"]
            )
            for parameter_name in (
                    "imports",
                    "purchasers_to_basic_price",
                )
                parameter = parameters_by_name[parameter_name]
                @test parameter["status"] == "REJECTED"
                @test parameter["source_control_reconciles"] ==
                    "APPROVED"
                @test parameter["model_mapping_admissible"] ==
                    "REJECTED"
            end
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
