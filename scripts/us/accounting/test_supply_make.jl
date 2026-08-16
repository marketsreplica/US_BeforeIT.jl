using JSON
using SHA
using Test

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
using .USSupplyMakeDiagnostics
using .USSymmetricSupplyUse

function io_cell(table_id, row_code, column_code, value)
    return IOCell(
        table_id,
        2024,
        row_code,
        "Commodity",
        column_code,
        "Industry",
        value,
    )
end

function minimal_tables(; corrupt_t016 = 0.0, drop_supply_row = nothing)
    industry_codes = ["A", "441", "445", "452", "4A0"]
    commodity_codes = ["A", "441", "445", "452", "4A0", "Other", "Used"]

    make_values = Dict(
        ("A", "A") => 10.0,
        ("A", "441") => 1.0,
        ("441", "441") => 2.0,
        ("445", "445") => 3.0,
        ("452", "452") => 4.0,
        ("4A0", "4A0") => 5.0,
        ("Other", "A") => 1.0,
        ("Used", "4A0") => 1.0,
    )
    t007 = Dict(
        "A" => 11.0,
        "441" => 2.0,
        "445" => 3.0,
        "452" => 4.0,
        "4A0" => 5.0,
        "Other" => 1.0,
        "Used" => 1.0,
    )
    mcif = Dict(
        "A" => 1.0,
        "441" => 0.0,
        "445" => 0.0,
        "452" => 0.0,
        "4A0" => 1.0,
        "Other" => 1.0,
        "Used" => 2.0,
    )
    trade = Dict(
        "A" => 0.0,
        "441" => -2.0,
        "445" => -3.0,
        "452" => -4.0,
        "4A0" => 8.0,
        "Other" => 0.0,
        "Used" => 0.0,
    )
    t013 = Dict(code => t007[code] + mcif[code] for code in commodity_codes)
    t016 = Dict(code => t013[code] + trade[code] for code in commodity_codes)
    t016["A"] += corrupt_t016

    supply_cells = IOCell[]
    for ((row_code, column_code), value) in make_values
        row_code == drop_supply_row && continue
        push!(supply_cells, io_cell("262", row_code, column_code, value))
    end
    for code in commodity_codes
        code == drop_supply_row && continue
        for (column_code, value) in (
                ("T007", t007[code]),
                ("MCIF", mcif[code]),
                ("T013", t013[code]),
                ("Trade", trade[code]),
                ("T014", trade[code]),
                ("T016", t016[code]),
            )
            push!(supply_cells, io_cell("262", code, column_code, value))
        end
    end
    industry_output = Dict(
        code => sum(get(make_values, (row, code), 0.0) for row in commodity_codes)
            for code in industry_codes
    )
    for code in industry_codes
        push!(supply_cells, io_cell("262", "T017", code, industry_output[code]))
    end
    component_controls = Dict(
        "T007" => sum(values(t007)),
        "MCIF" => sum(values(mcif)),
        "MADJ" => 0.0,
        "T013" => sum(values(t013)),
        "Trade" => sum(values(trade)),
        "Trans" => 0.0,
        "T014" => sum(values(trade)),
        "TOP" => 0.0,
        "MDTY" => 0.0,
        "SUB" => 0.0,
        "T015" => 0.0,
        "T016" => sum(values(t016)),
    )
    for (code, value) in component_controls
        push!(supply_cells, io_cell("262", "T017", code, value))
    end

    use_commodities = ["A", "4A0", "Other", "Used"]
    use_values = Dict(
        ("A", "A") => 3.0,
        ("A", "441") => 1.0,
        ("4A0", "A") => 1.0,
        ("4A0", "441") => 1.0,
        ("4A0", "445") => 1.0,
        ("4A0", "452") => 1.0,
        ("4A0", "4A0") => 1.0,
        ("Other", "A") => 1.0,
        ("Used", "4A0") => 1.0,
    )
    final_use = Dict("A" => 8.0, "4A0" => 9.0, "Other" => 1.0, "Used" => 2.0)
    use_cells = IOCell[]
    for ((row_code, column_code), value) in use_values
        push!(use_cells, io_cell("259", row_code, column_code, value))
    end
    for code in use_commodities
        intermediate =
            sum(get(use_values, (code, industry), 0.0) for industry in industry_codes)
        push!(use_cells, io_cell("259", code, "T001", intermediate))
        push!(use_cells, io_cell("259", code, "F010", final_use[code]))
        push!(
            use_cells,
            io_cell("259", code, "T019", intermediate + final_use[code]),
        )
    end
    for industry in industry_codes
        push!(
            use_cells,
            io_cell(
                "259",
                "T005",
                industry,
                sum(
                    get(use_values, (commodity, industry), 0.0)
                        for commodity in use_commodities
                ),
            ),
        )
    end
    intermediate_total =
        sum(cell.value for cell in use_cells if cell.column_code == "T001")
    final_total = sum(values(final_use))
    push!(use_cells, io_cell("259", "T005", "T001", intermediate_total))
    push!(use_cells, io_cell("259", "T005", "F010", final_total))
    push!(
        use_cells,
        io_cell("259", "T005", "T019", intermediate_total + final_total),
    )

    return (
        use = IOTable(use_cells),
        supply = IOTable(supply_cells),
    )
end

function maximum_residual(report, family)
    values = control_residuals(report, family)
    return maximum(abs(residual.residual) for residual in values)
end

@testset "Source-aware U.S. supply/make diagnostics" begin
    @testset "Typed, code-keyed minimal system" begin
        tables = minimal_tables()
        report = diagnose_supply_make(
            tables.use,
            tables.supply;
            expected_supply_commodity_count = 7,
            expected_supply_industry_count = 5,
            expected_use_commodity_count = 4,
        )

        @test size(report.raw_make) == (7, 5)
        @test size(report.aggregated_make) == (4, 2)
        @test size(report.raw_use) == (4, 5)
        @test size(report.aggregated_use) == (4, 2)
        @test report.aggregated_make["A", "4A0"] == 1.0
        @test report.aggregated_make["4A0", "4A0"] == 14.0
        @test report.aggregated_use["4A0", "4A0"] == 4.0
        @test sum(report.raw_make.values) == sum(report.aggregated_make.values)
        @test sum(report.raw_use.values) == sum(report.aggregated_use.values)
        @test report.raw_make.explicit[
            report.raw_make.row_index["A"],
            report.raw_make.column_index["A"],
        ]
        @test !report.raw_make.explicit[
            report.raw_make.row_index["A"],
            report.raw_make.column_index["445"],
        ]
        @test report.commodity_mapping["441"] == "4A0"
        @test report.commodity_mapping["Other"] == "Other"
        @test report.commodity_mapping["Used"] == "Used"
        @test report.industry_mapping["452"] == "4A0"

        @test report.commodity_output["4A0"] == 14.0
        @test report.industry_output["4A0"] == 16.0
        @test report.purchaser_supply["4A0"] == 14.0
        @test report.total_use["4A0"] == 14.0
        @test report.purchaser_supply["Other"] == 2.0
        @test report.purchaser_supply["Used"] == 3.0
        @test Set(report.explicit_closure_codes) == Set(["Other", "Used"])

        @test controls_pass(report)
        @test all(residual.passed for residual in report.residuals)
        @test report.transformation == :code_keyed_retail_aggregation_only
        @test !report.balancing_applied
        @test length(control_residuals(report, :retail_aggregation)) == 3
        @test maximum_residual(report, :t007_commodity_make) == 0.0
        @test maximum_residual(report, :t016_t019_supply_use) == 0.0

        reordered = diagnose_supply_make(
            IOTable(reverse(collect(values(tables.use.cells)))),
            IOTable(reverse(collect(values(tables.supply.cells)))),
        )
        @test controls_pass(reordered)
        @test all(
            reordered.commodity_output[code] == report.commodity_output[code]
                for code in report.commodity_output.codes
        )
        @test all(
            reordered.industry_output[code] == report.industry_output[code]
                for code in report.industry_output.codes
        )
        @test all(
            reordered.aggregated_make[row, column] ==
                report.aggregated_make[row, column]
                for row in report.aggregated_make.row_codes
                for column in report.aggregated_make.column_codes
        )
    end

    @testset "Mixed economic bases and positional shortcuts are rejected" begin
        commodity =
            LabeledVector{CommodityBasis}(["A", "B"], [10.0, 20.0])
        industry = LabeledVector{IndustryBasis}(["A", "B"], [9.0, 21.0])
        @test_throws BasisMismatchError keyed_difference(commodity, industry)

        reordered =
            LabeledVector{CommodityBasis}(["B", "A"], [18.0, 7.0])
        difference = keyed_difference(commodity, reordered)
        @test difference.codes == ["A", "B"]
        @test difference.values == [3.0, 2.0]
        @test_throws ArgumentError keyed_difference(
            commodity,
            LabeledVector{CommodityBasis}(["A", "C"], [1.0, 2.0]),
        )

        tables = minimal_tables()
        mislabeled_cells = collect(values(tables.use.cells))
        original = first(mislabeled_cells)
        mislabeled_cells[1] = IOCell(
            original.table_id,
            original.year,
            original.row_code,
            "Industry",
            original.column_code,
            "Commodity",
            original.value,
        )
        @test_throws ArgumentError diagnose_supply_make(
            IOTable(mislabeled_cells),
            tables.supply,
        )
    end

    @testset "Industry-technology transformation is explicit and conservative" begin
        tables = minimal_tables()
        source = diagnose_supply_make(tables.use, tables.supply)
        report = build_industry_technology_system(source)

        @test size(report.published_market_shares) == (2, 4)
        @test size(report.rounding_normalized_market_shares) == (2, 4)
        @test size(report.published_product_mix) == (2, 4)
        @test size(report.rounding_normalized_product_mix) == (2, 4)
        @test size(report.published_symmetric_use) == (4, 4)
        @test size(report.rounding_normalized_symmetric_use) == (4, 4)
        @test report.rounding_normalized_symmetric_use.row_codes ==
            source.commodity_output.codes
        @test report.rounding_normalized_symmetric_use.column_codes ==
            source.commodity_output.codes

        @test transformation_controls_pass(report)
        @test length(report.residuals) == 24
        @test all(
            isapprox(
                    sum(
                        report.rounding_normalized_product_mix.values[
                            industry_index,
                            :,
                        ],
                    ),
                    1.0;
                    atol = NUMERICAL_TOLERANCE_RATIO,
                )
                for industry_index in axes(
                    report.rounding_normalized_product_mix.values,
                    1,
                )
        )
        @test vec(
            sum(report.rounding_normalized_symmetric_use.values; dims = 2),
        ) ≈ vec(sum(source.aggregated_use.values; dims = 2)) atol =
            NUMERICAL_TOLERANCE_MILLIONS_USD
        @test sum(report.rounding_normalized_symmetric_use.values) ≈
            sum(source.aggregated_use.values) atol =
            NUMERICAL_TOLERANCE_MILLIONS_USD
        @test report.rounding_normalized_symmetric_use["A", "A"] ≈
            3.0 * 10.0 / 11.0 + 1.0 / 16.0
        @test report.rounding_normalized_symmetric_use["A", "Other"] ≈
            3.0 / 11.0
        @test report.rounding_normalized_symmetric_use["A", "Used"] ≈
            1.0 / 16.0

        @test report.source_make.explicit[
            report.source_make.row_index["A"],
            report.source_make.column_index["A"],
        ]
        @test !report.source_make.explicit[
            report.source_make.row_index["Other"],
            report.source_make.column_index["4A0"],
        ]
        @test report.source_use.explicit[
            report.source_use.row_index["A"],
            report.source_use.column_index["A"],
        ]
        @test !report.source_use.explicit[
            report.source_use.row_index["Other"],
            report.source_use.column_index["4A0"],
        ]
        @test isempty(report.negative_make_cells)
        @test isempty(report.negative_use_cells)
        @test isempty(report.negative_symmetric_cells)
        @test report.technology_assumption == :industry_technology
        @test report.use_price_basis == :purchasers_prices
        @test report.make_price_basis == :producer_prices
        @test report.output_price_basis == :basic_prices
        @test report.rounding_normalization_applied
        @test !report.valuation_bridge_applied
        @test !report.balancing_applied
        @test !report.clipping_applied
        @test !report.promotion_ready
        @test Set(report.explicit_closure_codes) == Set(["Other", "Used"])
        @test Set(report.promotion_blockers) == Set(
            [
                "VALUATION_BRIDGE_NOT_APPLIED",
                "OTHER_USED_CLOSURE_ACCOUNTS_UNALLOCATED",
                "MODEL_STATE_RECONCILIATION_NOT_APPLIED",
            ],
        )
        @test !any(report.rounding_normalized_symmetric_use.explicit)

        reordered_source = diagnose_supply_make(
            IOTable(reverse(collect(values(tables.use.cells)))),
            IOTable(reverse(collect(values(tables.supply.cells)))),
        )
        reordered = build_industry_technology_system(reordered_source)
        @test all(
            reordered.rounding_normalized_symmetric_use[row, column] ==
                report.rounding_normalized_symmetric_use[row, column]
                for row in report.rounding_normalized_symmetric_use.row_codes
                for column in
                report.rounding_normalized_symmetric_use.column_codes
        )

        failed_source =
            diagnose_supply_make(
            minimal_tables(; corrupt_t016 = 10.0).use,
            minimal_tables(; corrupt_t016 = 10.0).supply,
        )
        @test_throws ArgumentError build_industry_technology_system(
            failed_source,
        )
    end

    @testset "Diagnostics expose failures without balancing them away" begin
        tables = minimal_tables(; corrupt_t016 = 10.0)
        report = diagnose_supply_make(tables.use, tables.supply)
        @test !controls_pass(report)
        @test report.purchaser_supply["A"] == 22.0
        @test report.total_use["A"] == 12.0
        @test maximum_residual(report, :t016_purchaser_supply) == 10.0
        @test maximum_residual(report, :t016_t019_supply_use) == 10.0
        @test !report.balancing_applied
        @test sum(report.raw_make.values) == sum(report.aggregated_make.values)
    end

    @testset "Required retail and closure rows cannot disappear implicitly" begin
        no_retail = minimal_tables(; drop_supply_row = "445")
        @test_throws ArgumentError diagnose_supply_make(
            no_retail.use,
            no_retail.supply,
        )
        no_other = minimal_tables(; drop_supply_row = "Other")
        @test_throws ArgumentError diagnose_supply_make(
            no_other.use,
            no_other.supply,
        )
    end

    @testset "Sparse-table and provenance contracts" begin
        duplicate = io_cell("259", "A", "B", 1.0)
        @test_throws ArgumentError IOTable([duplicate, duplicate])
        @test cell_value(IOTable([duplicate]), "missing", "cell") == 0.0
        @test_throws ArgumentError cell_value(
            IOTable([duplicate]),
            "missing",
            "control";
            required = true,
        )
        @test published_rounding_tolerance(3) == 2.0
        @test published_rounding_tolerance(3; unit = 0.1) ≈ 0.2
        @test_throws ArgumentError published_rounding_tolerance(0)

        mktempdir() do directory
            path = joinpath(directory, "table.json")
            payload = Dict(
                "BEAAPI" => Dict(
                    "Results" => [
                        Dict(
                            "Data" => [
                                Dict(
                                    "TableID" => "259",
                                    "Year" => "2024",
                                    "RowCode" => "A",
                                    "RowType" => "Commodity",
                                    "ColCode" => "B",
                                    "ColType" => "Industry",
                                    "DataValue" => "1,234",
                                ),
                            ],
                        ),
                    ],
                ),
            )
            open(path, "w") do io
                JSON.print(io, payload)
            end
            digest = bytes2hex(SHA.sha256(read(path)))
            table = load_bea_json(
                path;
                expected_sha256 = digest,
                expected_table_id = "259",
                expected_year = 2024,
            )
            @test cell_value(table, "A", "B") == 1234.0
            @test table.source_sha256 == digest
            @test_throws ArgumentError load_bea_json(
                path;
                expected_sha256 = repeat("0", 64),
            )
            @test_throws ArgumentError load_bea_json(
                path;
                expected_table_id = "262",
            )
        end
    end

    @testset "Approved archived 2024 controls (hermetic projection)" begin
        fixture = load_canonical_fixture(
            joinpath(@__DIR__, "fixtures", "bea_2024_approved"),
        )
        @test fixture.use.source_sha256 ==
            "2bdd65f04e1bf31fd66d1e642afd0fb9dda2fd9bb5ba3bacf8db83431be1e918"
        @test fixture.supply.source_sha256 ==
            "91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8"
        @test fixture.manifest["fixture_sha256"] ==
            "c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0"
        @test length(fixture.use.cells) == 4640
        @test length(fixture.supply.cells) == 1728

        report = diagnose_supply_make(
            fixture.use,
            fixture.supply;
            expected_supply_commodity_count = 73,
            expected_supply_industry_count = 71,
            expected_use_commodity_count = 70,
        )
        @test size(report.raw_make) == (73, 71)
        @test size(report.aggregated_make) == (70, 68)
        @test size(report.raw_use) == (70, 71)
        @test size(report.aggregated_use) == (70, 68)
        @test length(report.residuals) == 755
        @test controls_pass(report)
        @test count(residual -> !residual.passed, report.residuals) == 0

        @test cell_value(fixture.supply, "T017", "T007") == 49_726_230.0
        @test cell_value(fixture.supply, "T017", "T016") == 54_418_092.0
        @test cell_value(fixture.use, "T005", "T019") == 54_418_093.0
        @test sum(report.raw_make.values) == 49_726_222.0
        @test sum(report.aggregated_make.values) == 49_726_222.0
        @test sum(report.raw_use.values) == 21_438_541.0
        @test sum(report.aggregated_use.values) == 21_438_541.0
        @test sum(report.raw_commodity_output.values) == 49_726_234.0
        @test sum(report.raw_industry_output.values) == 49_726_225.0
        @test sum(report.purchaser_supply.values) == 54_418_090.0
        @test sum(report.total_use.values) == 54_418_092.0

        # Four retail commodity/industry sources are not positionally
        # interchangeable. They aggregate to different T007 controls, while
        # their purchaser-price supply correctly closes to use.
        @test report.commodity_output["4A0"] == 2_403_974.0
        @test report.industry_output["4A0"] == 2_527_001.0
        @test report.industry_output["4A0"] -
            report.commodity_output["4A0"] == 123_027.0
        @test report.purchaser_supply["4A0"] == 18_144.0
        @test report.total_use["4A0"] == 18_144.0

        @test report.raw_commodity_output["Other"] == 6_187.0
        @test report.raw_commodity_output["Used"] == 13_553.0
        @test report.purchaser_supply["Other"] == 375_387.0
        @test report.total_use["Other"] == 375_387.0
        @test report.purchaser_supply["Used"] == 307_187.0
        @test report.total_use["Used"] == 307_187.0

        @test maximum_residual(report, :t007_commodity_make) == 4.0
        @test maximum_residual(report, :t007_industry_make) == 4.0
        @test maximum_residual(report, :t016_purchaser_supply) == 1.0
        @test maximum_residual(report, :t019_total_use) == 2.0
        @test maximum_residual(report, :t016_t019_supply_use) == 1.0
        cross_table = control_residuals(report, :t016_t019_supply_use)
        @test [
            (residual.code, residual.residual)
                for residual in cross_table if residual.residual != 0
        ] == [("325", -1.0), ("487OS", -1.0)]

        symmetric = build_industry_technology_system(report)
        @test transformation_controls_pass(symmetric)
        @test length(symmetric.residuals) == 420
        @test size(symmetric.published_market_shares) == (68, 70)
        @test size(symmetric.rounding_normalized_market_shares) == (68, 70)
        @test size(symmetric.published_product_mix) == (68, 70)
        @test size(symmetric.rounding_normalized_product_mix) == (68, 70)
        @test size(symmetric.published_symmetric_use) == (70, 70)
        @test size(symmetric.rounding_normalized_symmetric_use) == (70, 70)
        @test maximum(
            abs,
            symmetric.commodity_output.values -
                symmetric.make_row_sums.values,
        ) == 4.0
        @test maximum(
            abs,
            symmetric.industry_output.values -
                symmetric.make_column_sums.values,
        ) == 4.0
        @test maximum(
            abs,
            vec(sum(symmetric.published_market_shares.values; dims = 1)) .-
                1.0,
        ) ≈ 4.0469445568680484e-5
        @test maximum(
            abs,
            vec(sum(symmetric.published_product_mix.values; dims = 2)) .-
                1.0,
        ) ≈ 4.2710402118339985e-5
        @test maximum(
            abs,
            vec(
                sum(
                    symmetric.rounding_normalized_market_shares.values;
                    dims = 1,
                ),
            ) .- 1.0,
        ) <= NUMERICAL_TOLERANCE_RATIO
        @test maximum(
            abs,
            vec(
                sum(
                    symmetric.rounding_normalized_product_mix.values;
                    dims = 2,
                ),
            ) .- 1.0,
        ) <= NUMERICAL_TOLERANCE_RATIO

        @test sum(symmetric.published_symmetric_use.values) ≈
            21_438_537.92674519 atol = NUMERICAL_TOLERANCE_MILLIONS_USD
        @test sum(symmetric.rounding_normalized_symmetric_use.values) ≈
            21_438_541.0 atol = NUMERICAL_TOLERANCE_MILLIONS_USD
        @test maximum(
            abs,
            vec(
                sum(
                    symmetric.rounding_normalized_symmetric_use.values;
                    dims = 2,
                ),
            ) - [
                sum(
                        report.aggregated_use.values[
                            report.aggregated_use.row_index[code],
                            :,
                        ],
                    )
                    for code in
                    symmetric.rounding_normalized_symmetric_use.row_codes
            ],
        ) <= NUMERICAL_TOLERANCE_MILLIONS_USD
        @test sum(
            abs,
            symmetric.published_symmetric_use.values -
                symmetric.rounding_normalized_symmetric_use.values,
        ) ≈ 20.577411440142875 atol = NUMERICAL_TOLERANCE_MILLIONS_USD

        @test length(symmetric.negative_make_cells) == 9
        @test length(symmetric.negative_use_cells) == 5
        @test length(symmetric.negative_symmetric_cells) == 19
        @test sum(cell.value for cell in symmetric.negative_make_cells) ==
            -406.0
        @test sum(cell.value for cell in symmetric.negative_use_cells) ==
            -506.0
        @test sum(cell.value for cell in symmetric.negative_symmetric_cells) ≈
            -468.8914424387554
        @test Set(
            (cell.row_code, cell.column_code, cell.value)
                for cell in symmetric.negative_use_cells
        ) == Set(
            [
                ("Used", "111CA", -18.0),
                ("Used", "481", -90.0),
                ("Used", "483", -183.0),
                ("Used", "711AS", -155.0),
                ("Used", "GFGD", -60.0),
            ],
        )
        # The projected rows come from BLAS matrix products whose last-bit
        # rounding differs across platforms, so exact equality is not portable.
        @test sum(
            symmetric.rounding_normalized_symmetric_use.values[
                symmetric.rounding_normalized_symmetric_use.row_index["Other"],
                :,
            ],
        ) ≈ 172_632.0 atol = 1.0e-3
        @test sum(
            symmetric.rounding_normalized_symmetric_use.values[
                symmetric.rounding_normalized_symmetric_use.row_index["Used"],
                :,
            ],
        ) ≈ 133_321.0 atol = 1.0e-3
        @test "NEGATIVE_CELLS_PRESERVED_REQUIRES_GOVERNED_POLICY" in
            symmetric.promotion_blockers
        @test !symmetric.valuation_bridge_applied
        @test !symmetric.balancing_applied
        @test !symmetric.clipping_applied
        @test !symmetric.promotion_ready

        mktempdir() do directory
            source_directory =
                joinpath(@__DIR__, "fixtures", "bea_2024_approved")
            cp(
                joinpath(source_directory, "manifest.toml"),
                joinpath(directory, "manifest.toml"),
            )
            cp(
                joinpath(source_directory, "cells.csv"),
                joinpath(directory, "cells.csv"),
            )
            open(joinpath(directory, "cells.csv"), "a") do io
                println(io)
            end
            @test_throws ArgumentError load_canonical_fixture(directory)
        end
    end
end
