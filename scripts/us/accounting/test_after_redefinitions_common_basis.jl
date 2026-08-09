using CSV
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))

using .USAfterRedefinitionsCommonBasis
using .USRequirementsDiagnostics
using .USSupplyMakeDiagnostics

const COMMON_BASIS_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const REQUIREMENTS_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "bea_2024_requirements_approved")
const OFFICIAL_DIRECT_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_official_direct_requirements_approved",
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function copied_common_basis_fixture()
    directory = mktempdir()
    cp(
        joinpath(COMMON_BASIS_FIXTURE_DIRECTORY, "cells.csv"),
        joinpath(directory, "cells.csv"),
    )
    cp(
        joinpath(COMMON_BASIS_FIXTURE_DIRECTORY, "manifest.toml"),
        joinpath(directory, "manifest.toml"),
    )
    return directory
end

function load_official_report()
    total_fixture =
        load_requirements_fixture(REQUIREMENTS_FIXTURE_DIRECTORY)
    direct_fixture = load_official_direct_requirements_fixture(
        OFFICIAL_DIRECT_FIXTURE_DIRECTORY,
    )
    return build_official_direct_requirements(total_fixture, direct_fixture)
end

function maximum_family_residual(report, family)
    return maximum(
        abs(residual.residual)
            for residual in report.residuals
            if residual.family == family
    )
end

@testset "BEA after-redefinitions common-basis diagnostic" begin
    @testset "Pinned spreadsheet projection and source-cell semantics" begin
        fixture =
            load_after_redefinitions_fixture(COMMON_BASIS_FIXTURE_DIRECTORY)
        cells_path = joinpath(COMMON_BASIS_FIXTURE_DIRECTORY, "cells.csv")
        manifest_path =
            joinpath(COMMON_BASIS_FIXTURE_DIRECTORY, "manifest.toml")

        @test fixture.year == 2024
        @test fixture.benchmark_year == 2017
        @test size(fixture.producer_intermediate_use) == (73, 71)
        @test size(fixture.producer_final_use) == (73, 20)
        @test size(fixture.producer_value_added) == (3, 71)
        @test size(fixture.producer_make) == (71, 73)
        @test size(fixture.import_intermediate_use) == (73, 71)
        @test size(fixture.import_final_use) == (73, 20)
        @test size(fixture.benchmark_producer_intermediate_use) == (73, 71)
        @test size(fixture.benchmark_producer_final_use) == (73, 20)
        @test size(fixture.benchmark_purchaser_intermediate_use) == (70, 71)
        @test size(fixture.benchmark_purchaser_final_use) == (70, 20)

        @test fixture.producer_intermediate_use.row_codes ==
            fixture.producer_final_use.row_codes
        @test fixture.producer_intermediate_use.row_codes ==
            fixture.producer_make.column_codes
        @test fixture.producer_intermediate_use.column_codes ==
            fixture.producer_make.row_codes
        @test fixture.producer_intermediate_use.column_codes ==
            fixture.producer_value_added.column_codes
        @test fixture.producer_intermediate_use.row_codes ==
            fixture.import_intermediate_use.row_codes
        @test fixture.producer_intermediate_use.column_codes ==
            fixture.import_intermediate_use.column_codes
        @test fixture.producer_final_use.column_codes ==
            fixture.import_final_use.column_codes
        @test fixture.producer_value_added.row_codes ==
            ["V001", "V002", "V003"]
        @test fixture.producer_intermediate_use.row_codes[(end - 1):end] ==
            ["Used", "Other"]
        @test "F030" in fixture.producer_final_use.column_codes
        @test fixture.final_use_descriptions["F030"] ==
            "Change in private inventories"
        @test fixture.commodity_descriptions["Other"] ==
            "Noncomparable imports and rest-of-the-world adjustment [1]"

        @test fixture.producer_intermediate_use["111CA", "111CA"] ==
            118_579.0
        @test fixture.producer_make["111CA", "111CA"] == 556_775.0
        @test sum(fixture.producer_intermediate_use.values) ==
            21_438_569.0
        @test sum(fixture.producer_make.values) == 50_736_552.0
        @test sum(fixture.import_intermediate_use.values) +
            sum(fixture.import_final_use.values) == -44.0
        @test fixture.producer_intermediate_grand_control == 21_438_542.0
        @test fixture.producer_final_use_column_controls["F030"] ==
            53_546.0
        @test fixture.producer_value_added_grand_control == 29_298_013.0
        @test fixture.producer_output_grand_control == 50_736_555.0
        @test fixture.producer_make_output_grand_control == 50_736_556.0
        @test fixture.benchmark_producer_grand_output == 34_468_130.0
        @test fixture.benchmark_purchaser_grand_output == 34_468_130.0
        @test count(<(0.0), fixture.producer_intermediate_use.values) == 5
        @test count(<(0.0), fixture.producer_make.values) == 1
        @test count(<(0.0), fixture.import_intermediate_use.values) +
            count(<(0.0), fixture.import_final_use.values) == 58
        @test Set(keys(fixture.source_explicit)) ==
            Set(
            spec.matrix_id for
                spec in USAfterRedefinitionsCommonBasis.PROJECTION_SPECS
        )
        @test all(
            size(fixture.source_explicit[spec.matrix_id]) ==
                (spec.rows, spec.columns) for
                spec in USAfterRedefinitionsCommonBasis.PROJECTION_SPECS
        )

        ellipsis_row =
            fixture.benchmark_producer_final_use.row_index["111CA"]
        ellipsis_column =
            fixture.benchmark_producer_final_use.column_index["F02S"]
        numeric_zero_row =
            fixture.benchmark_producer_final_use.row_index["483"]
        numeric_zero_column =
            fixture.benchmark_producer_final_use.column_index["F02N"]
        @test fixture.benchmark_producer_final_use.values[
            ellipsis_row,
            ellipsis_column,
        ] == 0.0
        @test !fixture.benchmark_producer_final_use.explicit[
            ellipsis_row,
            ellipsis_column,
        ]
        @test fixture.benchmark_producer_final_use.values[
            numeric_zero_row,
            numeric_zero_column,
        ] == 0.0
        @test fixture.benchmark_producer_final_use.explicit[
            numeric_zero_row,
            numeric_zero_column,
        ]

        @test sha256_hex(read(cells_path)) ==
            "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac"
        @test sha256_hex(read(manifest_path)) ==
            "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030"
        @test fixture.provenance.source_zip_sha256 ==
            "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
        @test fixture.provenance.source_metadata_sha256 ==
            "8be9fbef6e2c18a7388cd61bd14312159fc3984d4dbc2c60158e977ee7f0e878"
        @test fixture.provenance.producer_use_workbook_sha256 ==
            "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7"
        @test fixture.provenance.producer_make_workbook_sha256 ==
            "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6"
        @test fixture.provenance.import_workbook_sha256 ==
            "9246c68288bb593495366288b9d8fd2038cae1ff500855ccd3e5c4377d0d3b25"
        @test fixture.provenance.purchaser_use_workbook_sha256 ==
            "9d55530ec5cd4688855ef474c779d0dba5f2e1e74d4fcfcdc95cddc64c69262b"
        @test fixture.provenance.spreadsheet_reader_version == "2.8.39"
        @test fixture.manifest["fixture_cell_count"] == 32_443
        @test fixture.manifest["projection_count"] == 19
        @test fixture.manifest["selected_zero_not_shown_count"] == 16_016
        @test fixture.manifest["explicit_numeric_zero_count"] == 819
        @test fixture.manifest["negative_cell_count"] == 321
        @test fixture.manifest["forecast_origin_admissible"] === false
        @test fixture.manifest["model_state_write"] === false
        @test fixture.manifest["accounting_gate_effect"] == "NONE"
        @test fixture.manifest["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
    end

    @testset "Producer-price make/use algebra and controls" begin
        fixture =
            load_after_redefinitions_fixture(COMMON_BASIS_FIXTURE_DIRECTORY)
        report = build_common_basis_report(fixture)

        @test report.year == 2024
        @test size(report.implied_direct_by_industry) == (73, 71)
        @test size(report.implied_market_shares) == (71, 73)
        @test size(report.product_mix) == (71, 73)
        @test size(report.symmetric_intermediate_use) == (73, 73)
        @test report.implied_direct_by_industry["111CA", "111CA"] ≈
            0.2092979334787735 rtol = 1.0e-14
        @test report.implied_market_shares["111CA", "111CA"] ≈
            0.9995475982313246 rtol = 1.0e-14
        @test report.symmetric_intermediate_use["111CA", "111CA"] ≈
            116_532.25940419202 rtol = 1.0e-14
        @test sum(report.symmetric_intermediate_use.values) ≈
            21_438_566.625123385 atol = 1.0e-5 rtol = 1.0e-12
        @test sum(report.inventory_change_flow.values) == 53_545.0
        @test count(report.inventory_change_flow_explicit) == 33
        @test report.inventory_change_flow_explicit ==
            fixture.producer_final_use.explicit[
            :,
            fixture.producer_final_use.column_index["F030"],
        ]
        @test report.inventory_change_flow.codes[
            .!report.inventory_change_flow_explicit,
        ] == [
            "22",
            "23",
            "441",
            "445",
            "452",
            "4A0",
            "485",
            "487OS",
            "493",
            "513",
            "514",
            "521CI",
            "523",
            "524",
            "525",
            "HS",
            "ORE",
            "532RL",
            "5411",
            "5415",
            "5412OP",
            "55",
            "561",
            "562",
            "61",
            "621",
            "622",
            "623",
            "624",
            "711AS",
            "713",
            "721",
            "722",
            "81",
            "GFGD",
            "GFGN",
            "GFE",
            "GSLG",
            "GSLE",
            "Other",
        ]
        @test sum(report.import_intermediate_use.values) +
            sum(report.import_final_use.values) == -44.0
        @test report.import_f050_offset.values ==
            fixture.import_final_use.values[
            :,
            fixture.import_final_use.column_index["F050"],
        ]
        @test report.import_f050_explicit ==
            fixture.import_final_use.explicit[
            :,
            fixture.import_final_use.column_index["F050"],
        ]
        @test count(report.import_f050_explicit) == 48
        @test report.import_f050_offset.codes[
            .!report.import_f050_explicit,
        ] == [
            "23",
            "42",
            "441",
            "445",
            "452",
            "4A0",
            "482",
            "483",
            "484",
            "485",
            "486",
            "493",
            "525",
            "HS",
            "ORE",
            "532RL",
            "55",
            "624",
            "721",
            "722",
            "81",
            "GFGD",
            "GFGN",
            "GSLG",
            "GSLE",
        ]
        @test report.import_allocation_excluding_f050_total == 3_795_870.0
        @test report.import_f050_total == -3_795_914.0
        @test report.import_net_total == -44.0
        @test report.import_allocation_excluding_f050_total +
            report.import_f050_total == report.import_net_total
        @test report.commodity_output.codes ==
            report.symmetric_intermediate_use.row_codes
        @test report.industry_output.codes ==
            report.producer_intermediate_use.column_codes
        @test all(>(0.0), report.commodity_output.values)
        @test all(>(0.0), report.industry_output.values)

        @test length(report.residuals) == 1_260
        @test common_basis_controls_pass(report)
        @test all(residual.passed for residual in report.residuals)
        expected_family_counts = Dict(
            :import_cell_offset_control => 73,
            :import_final_row_control => 73,
            :import_intermediate_row_control => 73,
            :import_published_offset_control => 73,
            :market_share_normalization => 73,
            :producer_commodity_output_control => 73,
            :producer_final_column_grand_control => 1,
            :producer_intermediate_row_control => 73,
            :producer_final_row_control => 73,
            :producer_final_row_grand_control => 1,
            :producer_final_use_column_control => 20,
            :producer_gdp_approach_control => 1,
            :producer_make_commodity_control => 73,
            :producer_use_make_commodity_control => 73,
            :producer_intermediate_column_control => 71,
            :producer_intermediate_column_grand_control => 1,
            :producer_intermediate_row_grand_control => 1,
            :producer_value_added_column_control => 71,
            :producer_value_added_grand_control => 1,
            :producer_industry_output_control => 71,
            :producer_make_industry_control => 71,
            :producer_make_industry_grand_control => 1,
            :producer_make_commodity_grand_control => 1,
            :producer_output_approach_control => 1,
            :producer_use_grand_output_identity => 1,
            :producer_use_make_industry_control => 71,
            :producer_use_make_grand_output_control => 1,
            :product_mix_normalization => 71,
            :symmetric_intermediate_row_conservation => 73,
        )
        @test Dict(
            family => count(
                    residual -> residual.family == family,
                    report.residuals,
                ) for family in unique(
                    residual.family for residual in report.residuals
                )
        ) == expected_family_counts
        @test maximum_family_residual(
            report,
            :producer_intermediate_row_control,
        ) == 5.0
        @test maximum_family_residual(
            report,
            :producer_final_row_control,
        ) == 2.0
        @test maximum_family_residual(
            report,
            :producer_commodity_output_control,
        ) == 1.0
        @test maximum_family_residual(
            report,
            :producer_intermediate_column_control,
        ) == 6.0
        @test maximum_family_residual(
            report,
            :producer_value_added_column_control,
        ) == 1.0
        @test maximum_family_residual(
            report,
            :producer_make_industry_control,
        ) == 3.0
        @test maximum_family_residual(
            report,
            :import_intermediate_row_control,
        ) == 7.0
        @test maximum_family_residual(
            report,
            :symmetric_intermediate_row_conservation,
        ) ≈ 0.6049662362784147 atol = 1.0e-12

        source_round_trip =
            report.implied_direct_by_industry.values *
            report.implied_market_shares.values .*
            reshape(report.commodity_output.values, 1, :)
        @test maximum(
            abs,
            source_round_trip - report.symmetric_intermediate_use.values,
        ) <= 1.0e-6
        @test length(report.negative_intermediate_use_cells) == 5
        @test length(report.negative_make_cells) == 1
        @test length(report.negative_symmetric_cells) == 6
        @test sum(cell.value for cell in report.negative_symmetric_cells) ≈
            -725.7715165953548 atol = 1.0e-9
        @test length(report.negative_import_cells) == 58
        @test sum(cell.value for cell in report.negative_import_cells) ==
            -3_806_603.0
        @test length(report.negative_import_f050_cells) == 48
        @test sum(
            cell.value for cell in report.negative_import_f050_cells
        ) == -3_795_914.0
        @test length(report.negative_import_allocation_cells) == 10
        @test sum(
            cell.value for cell in report.negative_import_allocation_cells
        ) == -10_689.0
        @test Set(report.explicit_closure_codes) == Set(["Other", "Used"])

        @test report.provenance.fixture_sha256 ==
            fixture.provenance.fixture_sha256
        @test report.provenance.manifest_sha256 ==
            fixture.provenance.manifest_sha256
        @test report.source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test report.transformation ==
            :after_redefinitions_producer_price_industry_technology
        @test report.price_basis == :producers_prices
        @test report.import_role == :separate_bea_imputed_import_allocation
        @test report.import_sign_convention ==
            :positive_allocated_uses_plus_signed_f050_accounting_offset
        @test report.source_rounding_unit_millions_usd == 1.0
        @test !report.domestic_use_subtraction_applied
        @test !report.valuation_bridge_applied
        @test !report.balancing_applied
        @test !report.clipping_applied
        @test !report.model_state_write
        @test report.accounting_gate_effect == :none
        @test !report.promotion_ready
        @test "PRODUCT_TAX_PRODUCER_TO_BASIC_CELL_ALLOCATION_NOT_PROVIDED" in
            report.promotion_blockers
        @test "INVENTORY_HOLDER_AND_STAGE_MAPPINGS_NOT_PROVIDED" in
            report.promotion_blockers
        @test "LATENT_STATE_RECONCILIATION_NOT_APPLIED" in
            report.promotion_blockers
        @test "CURRENT_VINTAGE_NOT_FORECAST_ORIGIN_ELIGIBLE" in
            report.promotion_blockers
    end

    @testset "2017 purchaser/producer valuation benchmark" begin
        fixture =
            load_after_redefinitions_fixture(COMMON_BASIS_FIXTURE_DIRECTORY)
        benchmark = build_common_basis_report(fixture).valuation_benchmark

        @test benchmark.year == 2017
        @test size(benchmark.producer_use) == (70, 91)
        @test size(benchmark.purchaser_use) == (70, 91)
        @test size(benchmark.purchaser_minus_producer) == (70, 91)
        @test benchmark.producer_use.row_codes ==
            benchmark.purchaser_use.row_codes
        @test benchmark.producer_use.column_codes ==
            benchmark.purchaser_use.column_codes
        @test benchmark.producer_use.row_codes[(end - 1):end] ==
            ["Used", "Other"]
        @test benchmark.retail_aggregation["441"] == "4A0"
        @test benchmark.retail_aggregation["445"] == "4A0"
        @test benchmark.retail_aggregation["452"] == "4A0"
        @test benchmark.retail_aggregation["4A0"] == "4A0"
        @test benchmark.retail_aggregation["Other"] == "Other"
        @test benchmark.retail_aggregation["Used"] == "Used"

        @test benchmark.producer_total == 34_468_125.0
        @test benchmark.purchaser_total == 34_468_139.0
        @test benchmark.producer_published_total == 34_468_130.0
        @test benchmark.purchaser_published_total == 34_468_130.0
        @test benchmark.published_total_difference == 0.0
        @test benchmark.signed_total_difference == 14.0
        @test benchmark.absolute_cell_difference == 8_169_470.0
        @test benchmark.frobenius_difference ≈
            1_845_430.9367662608 atol = 1.0e-5 rtol = 1.0e-12
        @test benchmark.cell_correlation ≈
            0.8993569937292458 rtol = 1.0e-12
        @test length(benchmark.negative_producer_cells) == 70
        @test length(benchmark.negative_purchaser_cells) == 68
        @test length(benchmark.negative_difference_cells) == 547
        @test length(benchmark.residuals) == 94
        @test valuation_controls_pass(benchmark)
        @test maximum(abs(residual.residual) for residual in benchmark.residuals) ==
            9.0
        @test all(
            residual.tolerance == 71.5 for
                residual in benchmark.residuals if
                residual.family ==
                :benchmark_recipient_total_conservation
        )
        @test Dict(
            family => count(
                    residual -> residual.family == family,
                    benchmark.residuals,
                ) for family in unique(
                    residual.family for residual in benchmark.residuals
                )
        ) == Dict(
            :benchmark_recipient_total_conservation => 91,
            :benchmark_producer_published_grand_total => 1,
            :benchmark_purchaser_published_grand_total => 1,
            :benchmark_published_grand_total_conservation => 1,
        )
        @test sum(benchmark.recipient_total_difference.values) == 14.0

        @test !benchmark.valuation_bridge_applied
        @test !benchmark.balancing_applied
        @test !benchmark.clipping_applied
        @test !benchmark.promotion_ready
        @test "2017_BENCHMARK_IS_NOT_A_2024_VALUATION_ALLOCATOR" in
            benchmark.promotion_blockers
        @test "MARGIN_TAX_SUBSIDY_COMPONENTS_NOT_SEPARATELY_IDENTIFIED" in
            benchmark.promotion_blockers
    end

    @testset "Official direct coefficients on the same producer basis" begin
        common = build_common_basis_report(
            load_after_redefinitions_fixture(
                COMMON_BASIS_FIXTURE_DIRECTORY,
            ),
        )
        official = load_official_report()
        comparison = compare_official_direct_common_basis(common, official)

        @test comparison.year == 2024
        @test common_basis_comparison_controls_pass(comparison)
        @test length(comparison.residuals) == 10_521
        @test all(residual.passed for residual in comparison.residuals)
        @test Dict(
            family => count(
                    residual -> residual.family == family,
                    comparison.residuals,
                ) for family in unique(
                    residual.family for residual in comparison.residuals
                )
        ) == Dict(
            :source_direct_snapshot_consistency => 1,
            :source_market_share_snapshot_consistency => 1,
            :source_product_mix_snapshot_consistency => 1,
            :source_transaction_snapshot_consistency => 1,
            :source_common_basis_round_trip => 1,
            :direct_coefficient_rounding_interval => 5_183,
            :market_share_rounding_interval => 5_183,
            :transaction_rounding_row_bound => 73,
            :transaction_rounding_column_bound => 73,
            :transaction_rounding_maximum_cell_ratio => 1,
            :published_direct_intermediate_total => 1,
            :published_market_share_make_total => 1,
            :transaction_difference_identity => 1,
        )
        @test comparison.direct_interval_failure_count == 0
        @test comparison.market_share_interval_failure_count == 0
        @test comparison.maximum_direct_interval_ratio ≈
            0.9884042149195085 atol = 1.0e-12 rtol = 1.0e-10
        @test comparison.maximum_market_share_interval_ratio ≈
            0.9736681278137415 atol = 1.0e-12 rtol = 1.0e-10
        @test comparison.maximum_transaction_rounding_bound_ratio ≈
            0.9373110641260786 atol = 1.0e-12 rtol = 1.0e-10
        @test comparison.maximum_direct_coefficient_difference ≈
            2.1233070523152264e-5 atol = 1.0e-14 rtol = 1.0e-10
        @test comparison.absolute_direct_coefficient_difference ≈
            0.0039634232222247115 atol = 1.0e-13 rtol = 1.0e-10
        @test comparison.direct_coefficient_rmse ≈
            1.8036473142280707e-6 atol = 1.0e-14 rtol = 1.0e-10
        @test comparison.maximum_market_share_difference ≈
            2.7890009591975684e-5 atol = 1.0e-14 rtol = 1.0e-10
        @test comparison.absolute_market_share_difference ≈
            0.0008565132482050305 atol = 1.0e-13 rtol = 1.0e-10
        @test comparison.market_share_rmse ≈
            1.3021805367398334e-6 atol = 1.0e-14 rtol = 1.0e-10

        @test comparison.source_total ≈
            21_438_566.625123385 atol = 1.0e-5 rtol = 1.0e-12
        @test comparison.published_total ≈
            21_438_542.743527092 atol = 1.0e-5 rtol = 1.0e-12
        @test comparison.signed_transaction_total_difference ≈
            23.881596289592924 atol = 1.0e-6 rtol = 1.0e-10
        @test comparison.absolute_transaction_cell_difference ≈
            944.8403948304654 atol = 1.0e-6 rtol = 1.0e-10
        @test comparison.transaction_frobenius_difference ≈
            17.595970995524745 atol = 1.0e-8 rtol = 1.0e-10
        @test comparison.transaction_cell_correlation ≈
            0.999999999904247 rtol = 1.0e-12
        maximum_cell =
            comparison.maximum_absolute_transaction_difference_cell
        @test maximum_cell.row_code == "335"
        @test maximum_cell.column_code == "5412OP"
        @test maximum_cell.source_value ≈
            7_018.542497511509 atol = 1.0e-8 rtol = 1.0e-12
        @test maximum_cell.published_value ≈
            7_019.167741695769 atol = 1.0e-8 rtol = 1.0e-12
        @test maximum_cell.difference ≈
            -0.6252441842598273 atol = 1.0e-10 rtol = 1.0e-10

        @test comparison.source_transactions.values ==
            common.symmetric_intermediate_use.values
        @test maximum(
            abs,
            comparison.transaction_difference.values -
                (
                comparison.source_transactions.values -
                    comparison.published_transactions.values
            ),
        ) == 0.0
        @test comparison.common_provenance.fixture_sha256 ==
            common.provenance.fixture_sha256
        @test comparison.common_provenance.manifest_sha256 ==
            common.provenance.manifest_sha256
        @test comparison.official_provenance.official_direct_fixture_sha256 ==
            official.provenance.official_direct_fixture_sha256
        @test comparison.official_provenance.official_direct_manifest_sha256 ==
            official.provenance.official_direct_manifest_sha256
        @test comparison.common_source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test comparison.official_source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test comparison.comparison_role ==
            :same_system_common_basis_rounding_comparator
        @test !comparison.valuation_bridge_applied
        @test !comparison.balancing_applied
        @test !comparison.clipping_applied
        @test !comparison.model_state_write
        @test comparison.accounting_gate_effect == :none
        @test !comparison.promotion_ready
        @test "COMMON_BASIS_COMPARISON_IS_NOT_INDEPENDENT_VALIDATION" in
            comparison.promotion_blockers
        @test "MULTI_ARCHIVE_RELEASE_IDENTITY_NOT_EXTERNALLY_BOUND" in
            comparison.promotion_blockers
        @test "PUBLISHED_COEFFICIENTS_AND_SOURCE_CELLS_ARE_INDEPENDENTLY_ROUNDED" in
            comparison.promotion_blockers
        @test "CURRENT_VINTAGE_NOT_FORECAST_ORIGIN_ELIGIBLE" in
            comparison.promotion_blockers
    end

    @testset "Adversarial coefficient and snapshot mutations fail closed" begin
        common = build_common_basis_report(
            load_after_redefinitions_fixture(
                COMMON_BASIS_FIXTURE_DIRECTORY,
            ),
        )
        official = load_official_report()

        swapped_direct = deepcopy(official)
        @test swapped_direct.direct_by_industry.values !==
            official.direct_by_industry.values
        original_direct_pair =
            copy(official.direct_by_industry.values[1:2, 1])
        swapped_direct.direct_by_industry.values[1, 1],
            swapped_direct.direct_by_industry.values[2, 1] =
            swapped_direct.direct_by_industry.values[2, 1],
            swapped_direct.direct_by_industry.values[1, 1]
        @test swapped_direct.direct_by_industry.values[1:2, 1] ==
            reverse(original_direct_pair)
        @test official.direct_by_industry.values[1:2, 1] ==
            original_direct_pair
        direct_comparison =
            compare_official_direct_common_basis(common, swapped_direct)
        @test direct_comparison.direct_interval_failure_count == 2
        @test direct_comparison.market_share_interval_failure_count == 0
        @test count(
            residual ->
            residual.family == :direct_coefficient_rounding_interval &&
                !residual.passed,
            direct_comparison.residuals,
        ) == 2
        @test !common_basis_comparison_controls_pass(direct_comparison)

        swapped_market_share = deepcopy(official)
        @test swapped_market_share.market_shares.values !==
            official.market_shares.values
        original_market_share_pair =
            copy(official.market_shares.values[1:2, 1])
        swapped_market_share.market_shares.values[1, 1],
            swapped_market_share.market_shares.values[2, 1] =
            swapped_market_share.market_shares.values[2, 1],
            swapped_market_share.market_shares.values[1, 1]
        @test swapped_market_share.market_shares.values[1:2, 1] ==
            reverse(original_market_share_pair)
        @test official.market_shares.values[1:2, 1] ==
            original_market_share_pair
        market_comparison =
            compare_official_direct_common_basis(common, swapped_market_share)
        @test market_comparison.direct_interval_failure_count == 0
        @test market_comparison.market_share_interval_failure_count == 2
        @test count(
            residual ->
            residual.family == :market_share_rounding_interval &&
                !residual.passed,
            market_comparison.residuals,
        ) == 2
        @test !common_basis_comparison_controls_pass(market_comparison)

        stale_common = deepcopy(common)
        @test stale_common.implied_direct_by_industry.values !==
            common.implied_direct_by_industry.values
        stored_direct = common.implied_direct_by_industry.values[1, 1]
        stale_common.implied_direct_by_industry.values[1, 1] += 1.0e-3
        @test common.implied_direct_by_industry.values[1, 1] ==
            stored_direct
        @test !common_basis_controls_pass(stale_common)
        @test_throws ArgumentError compare_official_direct_common_basis(
            stale_common,
            official,
        )

        nominal_comparison =
            compare_official_direct_common_basis(common, official)
        stale_comparison = deepcopy(nominal_comparison)
        @test stale_comparison.source_direct_by_industry.values !==
            nominal_comparison.source_direct_by_industry.values
        stale_comparison.source_direct_by_industry.values[1, 1] += 1.0e-3
        @test common_basis_comparison_controls_pass(nominal_comparison)
        @test !common_basis_comparison_controls_pass(stale_comparison)
    end

    @testset "Fail-closed byte, range, kind, and promotion contracts" begin
        manifest = TOML.parsefile(
            joinpath(COMMON_BASIS_FIXTURE_DIRECTORY, "manifest.toml"),
        )
        origin_claim = deepcopy(manifest)
        origin_claim["forecast_origin_admissible"] = true
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
            origin_claim,
        )
        state_claim = deepcopy(manifest)
        state_claim["model_state_write"] = true
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
            state_claim,
        )
        gate_claim = deepcopy(manifest)
        gate_claim["accounting_gate_effect"] = "PROMOTE"
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
            gate_claim,
        )
        wrong_reader = deepcopy(manifest)
        wrong_reader["artifact_tool_version"] = "2.8.38"
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
            wrong_reader,
        )
        wrong_range = deepcopy(manifest)
        wrong_range["projection"][1]["source_ranges"] = ["2017!A8:CP80"]
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
            wrong_range,
        )
        wrong_member = deepcopy(manifest)
        wrong_member["projection"][1]["source_member"] =
            "IOUse_After_Redefinitions_PUR_Summary.xlsx"
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
            wrong_member,
        )
        wrong_projection_hash = deepcopy(manifest)
        wrong_projection_hash["projection"][1]["projection_sha256"] =
            repeat("0", 64)
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
            wrong_projection_hash,
        )
        wrong_source = deepcopy(manifest)
        wrong_source["source_zip_sha256"] = repeat("0", 64)
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
            wrong_source,
        )
        for (key, replacement) in (
                "source_url" => "https://example.invalid/source.zip",
                "source_retrieved_at_utc" => "2026-08-06T05:03:03.322Z",
                "source_zip_byte_count" => 8_326_145,
                "producer_use_workbook_member" => "producer-use.xlsx",
                "producer_make_workbook_member" => "producer-make.xlsx",
                "import_workbook_member" => "imports.xlsx",
                "purchaser_use_workbook_member" => "purchaser-use.xlsx",
                "preservation_policy" => "changed preservation policy",
                "scientific_role" => "changed scientific role",
            )
            changed_metadata = deepcopy(manifest)
            changed_metadata[key] = replacement
            @test_throws ArgumentError USAfterRedefinitionsCommonBasis.validate_manifest(
                changed_metadata,
            )
        end

        table = CSV.File(
            joinpath(COMMON_BASIS_FIXTURE_DIRECTORY, "cells.csv");
            missingstring = nothing,
        )
        rows = Any[NamedTuple(row) for row in table]
        spec = first(USAfterRedefinitionsCommonBasis.PROJECTION_SPECS)
        invalid_kind = copy(rows)
        invalid_kind[1] =
            merge(invalid_kind[1], (source_cell_kind = "blank",))
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.materialize_projection(
            invalid_kind,
            spec,
        )
        nonzero_ellipsis = copy(rows)
        nonzero_ellipsis[1] = merge(
            nonzero_ellipsis[1],
            (source_cell_kind = "selected_zero_not_shown",),
        )
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.materialize_projection(
            nonzero_ellipsis,
            spec,
        )
        noninteger = copy(rows)
        noninteger[1] = merge(noninteger[1], (value = 75_521.5,))
        @test_throws ArgumentError USAfterRedefinitionsCommonBasis.materialize_projection(
            noninteger,
            spec,
        )

        corrupted = copied_common_basis_fixture()
        cells_path = joinpath(corrupted, "cells.csv")
        bytes = read(cells_path)
        bytes[end - 10] = bytes[end - 10] == UInt8('0') ? UInt8('1') : UInt8('0')
        write(cells_path, bytes)
        @test_throws ArgumentError load_after_redefinitions_fixture(corrupted)

        changed_manifest = copied_common_basis_fixture()
        manifest_path = joinpath(changed_manifest, "manifest.toml")
        write(manifest_path, read(manifest_path), UInt8('\n'))
        @test_throws ArgumentError load_after_redefinitions_fixture(
            changed_manifest,
        )
    end

    @testset "Acquisition and generator are explicit research-only paths" begin
        acquisition_path =
            joinpath(@__DIR__, "acquire_bea_after_redefinitions.jl")
        generator_path = joinpath(
            @__DIR__,
            "generate_after_redefinitions_common_basis_fixture.mjs",
        )
        acquisition = read(acquisition_path, String)
        generator = read(generator_path, String)

        @test occursin(
            "MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip",
            acquisition,
        )
        @test occursin(
            "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da",
            acquisition,
        )
        @test occursin("\"model_state_write\" => false", acquisition)
        @test occursin("@oai/artifact-tool", generator)
        @test occursin("artifactToolVersion: \"2.8.39\"", generator)
        @test occursin(
            "selected_zero_not_shown",
            generator,
        )
        @test occursin(
            "fixtureSha256:",
            generator,
        )
        @test !occursin("openpyxl", lowercase(generator))
        @test !occursin("ras(", lowercase(generator))
        @test !occursin("balance(", lowercase(generator))
    end
end
