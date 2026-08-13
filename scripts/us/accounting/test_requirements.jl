using SHA
using Test

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))

using .USRequirementsDiagnostics
using .USSupplyMakeDiagnostics
using .USSymmetricSupplyUse

const REQUIREMENTS_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "bea_2024_requirements_approved")
const OFFICIAL_DIRECT_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_official_direct_requirements_approved",
)
const SUPPLY_MAKE_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "bea_2024_approved")

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function load_supply_make_report()
    fixture = load_canonical_fixture(SUPPLY_MAKE_FIXTURE_DIRECTORY)
    return diagnose_supply_make(
        fixture.use,
        fixture.supply;
        expected_supply_commodity_count = 73,
        expected_supply_industry_count = 71,
        expected_use_commodity_count = 70,
    )
end

function copied_fixture()
    directory = mktempdir()
    cp(
        joinpath(REQUIREMENTS_FIXTURE_DIRECTORY, "cells.csv"),
        joinpath(directory, "cells.csv"),
    )
    cp(
        joinpath(REQUIREMENTS_FIXTURE_DIRECTORY, "manifest.toml"),
        joinpath(directory, "manifest.toml"),
    )
    return directory
end

function copied_official_direct_fixture()
    directory = mktempdir()
    cp(
        joinpath(OFFICIAL_DIRECT_FIXTURE_DIRECTORY, "cells.csv"),
        joinpath(directory, "cells.csv"),
    )
    cp(
        joinpath(OFFICIAL_DIRECT_FIXTURE_DIRECTORY, "manifest.toml"),
        joinpath(directory, "manifest.toml"),
    )
    return directory
end

@testset "Official BEA commodity total-requirements diagnostic" begin
    @testset "Pinned current-vintage fixture" begin
        fixture = load_requirements_fixture(REQUIREMENTS_FIXTURE_DIRECTORY)
        cells_path = joinpath(REQUIREMENTS_FIXTURE_DIRECTORY, "cells.csv")
        manifest_path =
            joinpath(REQUIREMENTS_FIXTURE_DIRECTORY, "manifest.toml")

        @test fixture.year == 2024
        @test size(fixture.total_requirements) == (73, 73)
        @test length(fixture.total_output_requirements) == 73
        @test fixture.total_requirements.row_codes ==
            fixture.total_requirements.column_codes
        @test first(fixture.total_requirements.row_codes) == "111CA"
        @test last(fixture.total_requirements.row_codes) == "Used"
        @test all(fixture.total_requirements.explicit)
        @test all(fixture.total_requirements.values .>= 0.0)
        @test all(fixture.total_output_requirements.values .> 0.0)
        @test fixture.total_requirements["111CA", "111CA"] == 1.3041073
        @test fixture.total_output_requirements["111CA"] == 2.2643741
        @test sum(fixture.total_requirements.values) == 136.8996494

        @test sha256_hex(read(cells_path)) ==
            "d7285bc44bd9ee40cf51e1a7c0789fdce40b2764b438dec1c598cae81bc31b0b"
        @test sha256_hex(read(manifest_path)) ==
            "2bc6040081f9a888639948fe5e5cbf13732a257ee1f62784b19d0aaea4023084"
        @test fixture.source_sha256 ==
            "f38f13ac18365fe4a68ad64fc9a6be6661b62893c3b714ee2d070cb7e0cc434d"
        @test fixture.manifest["source_metadata_sha256"] ==
            "1cc83c9eec20698bb5a31aaba81eb98dd176126c187399a4d78910c65cebf787"
        @test fixture.manifest["fixture_cell_count"] == 5_402
        @test fixture.manifest["api_production_time_utc"] ==
            "2026-08-06T00:40:11.567Z"
        @test fixture.manifest["status"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test fixture.manifest["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test fixture.manifest["forecast_origin_admissible"] === false
        @test fixture.manifest["accounting_gate_effect"] == "NONE"
    end

    @testset "Published Leontief inversion" begin
        fixture = load_requirements_fixture(REQUIREMENTS_FIXTURE_DIRECTORY)
        report = build_direct_requirements(fixture)

        @test report.year == 2024
        @test size(report.direct_requirements) == (73, 73)
        @test report.direct_requirements.row_codes ==
            fixture.total_requirements.row_codes
        @test report.direct_requirements.column_codes ==
            fixture.total_requirements.column_codes
        @test !any(report.direct_requirements.explicit)
        @test length(report.residuals) == 75
        @test requirements_controls_pass(report)
        @test count(residual -> !residual.passed, report.residuals) == 0
        @test count(
            residual ->
            residual.family == :published_total_output_requirement,
            report.residuals,
        ) == 73
        @test maximum(
            abs(residual.residual)
                for residual in report.residuals
                if residual.family == :published_total_output_requirement
        ) ≈ 5.999999999062311e-7 atol = 1.0e-15
        @test report.maximum_inverse_reconstruction_error <= 1.0e-12
        @test report.maximum_leontief_identity_error <= 1.0e-12
        @test report.condition_number ≈ 2.9773112583535997 rtol = 1.0e-12
        @test report.spectral_radius ≈ 0.476007595 atol = 1.0e-10
        @test report.direct_requirements["111CA", "111CA"] ≈
            0.20920306625816254 rtol = 1.0e-12
        @test sum(report.direct_requirements.values) ≈
            33.435685582831596 rtol = 1.0e-12

        substantive = Set(
            (cell.row_code, cell.column_code)
                for cell in report.substantive_negative_direct_cells
        )
        @test substantive == Set(
            [
                ("Used", "111CA"),
                ("Used", "481"),
                ("Used", "483"),
                ("Used", "711AS"),
                ("Used", "GFGD"),
            ],
        )
        @test length(report.substantive_negative_direct_cells) == 5
        @test length(report.negative_direct_cells) >=
            length(report.substantive_negative_direct_cells)
        @test all(
            cell.value < -SUBSTANTIVE_NEGATIVE_THRESHOLD
                for cell in report.substantive_negative_direct_cells
        )
        @test :inverse_of_published_commodity_total_requirements ==
            report.transformation
        @test !report.clipping_applied
        @test !report.balancing_applied
        @test !report.promotion_ready
        @test "SUBSTANTIVE_NEGATIVE_DIRECT_REQUIREMENTS_REQUIRE_GOVERNED_POLICY" in
            report.promotion_blockers
        @test "FINAL_USE_VALUATION_LEDGER_NOT_PROVIDED" in
            report.promotion_blockers
        @test "DIRECT_REQUIREMENTS_IMPLIED_FROM_ROUNDED_TOTAL_MATRIX" in
            report.promotion_blockers
        @test "AFTER_REDEFINITIONS_SYSTEM_NOT_RECONCILED" in
            report.promotion_blockers
    end

    @testset "Official direct and market-share matrices" begin
        direct_fixture = load_official_direct_requirements_fixture(
            OFFICIAL_DIRECT_FIXTURE_DIRECTORY,
        )
        total_fixture =
            load_requirements_fixture(REQUIREMENTS_FIXTURE_DIRECTORY)
        cells_path = joinpath(OFFICIAL_DIRECT_FIXTURE_DIRECTORY, "cells.csv")
        manifest_path =
            joinpath(OFFICIAL_DIRECT_FIXTURE_DIRECTORY, "manifest.toml")

        @test direct_fixture.year == 2024
        @test size(direct_fixture.direct_by_industry) == (73, 71)
        @test size(direct_fixture.market_shares) == (71, 73)
        @test size(direct_fixture.value_added) == (3, 71)
        @test length(direct_fixture.industry_totals) == 71
        @test direct_fixture.direct_by_industry.column_codes ==
            direct_fixture.market_shares.row_codes
        @test direct_fixture.direct_by_industry.row_codes ==
            direct_fixture.market_shares.column_codes
        @test direct_fixture.value_added.column_codes ==
            direct_fixture.direct_by_industry.column_codes
        @test direct_fixture.industry_totals.codes ==
            direct_fixture.direct_by_industry.column_codes
        @test direct_fixture.direct_by_industry.row_codes[(end - 1):end] ==
            ["Used", "Other"]
        @test direct_fixture.value_added.row_codes ==
            ["V001", "V002", "V003"]
        @test all(direct_fixture.direct_by_industry.explicit)
        @test all(direct_fixture.market_shares.explicit)
        @test all(direct_fixture.value_added.explicit)
        @test direct_fixture.direct_by_industry["111CA", "111CA"] ==
            0.209297
        @test direct_fixture.direct_by_industry["Used", "483"] ==
            -0.0024796
        @test direct_fixture.market_shares["111CA", "111CA"] ==
            0.9995475
        @test direct_fixture.market_shares["GFGN", "22"] == -0.0000113
        @test direct_fixture.value_added["V001", "111CA"] == 0.0789758
        @test sum(direct_fixture.direct_by_industry.values) == 32.4246536
        @test sum(direct_fixture.market_shares.values) == 72.9999995
        @test sum(direct_fixture.value_added.values) == 38.5753495
        @test sum(direct_fixture.industry_totals.values) == 71.0000001
        @test count(
            value -> value < 0,
            direct_fixture.direct_by_industry.values,
        ) == 5
        @test count(
            value -> value < 0,
            direct_fixture.market_shares.values,
        ) == 1
        @test sha256_hex(read(cells_path)) ==
            "d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e"
        @test sha256_hex(read(manifest_path)) ==
            "a225951d7ec03aaaaa97f5cc02e58b862e00918dbd31cc35093d80f9dde8c35d"
        @test direct_fixture.source_zip_sha256 ==
            "e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae"
        @test direct_fixture.direct_workbook_sha256 ==
            "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439"
        @test direct_fixture.market_share_workbook_sha256 ==
            "57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2"
        @test direct_fixture.manifest["source_metadata_sha256"] ==
            "f3f57a7209f7c6d9b0f76b041f17ae78e9da1d8644dbd7d6815471e740abfaca"
        @test direct_fixture.manifest["forecast_origin_admissible"] === false
        @test direct_fixture.manifest["accounting_gate_effect"] == "NONE"
        @test direct_fixture.manifest["model_state_write"] === false

        report = build_official_direct_requirements(
            total_fixture,
            direct_fixture,
        )
        @test report.year == 2024
        @test size(report.direct_requirements) == (73, 73)
        @test size(report.inversion_implied_requirements) == (73, 73)
        @test size(report.reconstructed_total_requirements) == (73, 73)
        @test size(report.direct_difference) == (73, 73)
        @test report.direct_requirements.row_codes ==
            total_fixture.total_requirements.row_codes
        @test report.direct_requirements.column_codes ==
            total_fixture.total_requirements.column_codes
        @test length(report.residuals) == 221
        @test requirements_controls_pass(report)
        @test count(residual -> !residual.passed, report.residuals) == 0
        @test count(
            residual ->
            residual.family == :published_direct_input_value_added_control,
            report.residuals,
        ) == 71
        @test count(
            residual -> residual.family == :published_market_share_control,
            report.residuals,
        ) == 73
        @test count(
            residual ->
            residual.family == :published_total_output_requirement,
            report.residuals,
        ) == 73
        @test report.maximum_direct_agreement_error ≈
            1.0510923429546404e-7 atol = 1.0e-12 rtol = 0.0
        @test report.absolute_direct_agreement_error ≈
            0.00014533239097311166 atol = 1.0e-10 rtol = 0.0
        @test report.direct_agreement_rmse ≈
            3.486409258428036e-8 atol = 1.0e-12 rtol = 0.0
        @test report.maximum_total_requirements_agreement_error ≈
            1.6615042031098426e-7 atol = 1.0e-12 rtol = 0.0
        @test report.maximum_leontief_identity_error ≈
            1.2165373752557517e-7 atol = 1.0e-12 rtol = 0.0
        @test report.maximum_direct_agreement_error <=
            DIRECT_MATRIX_AGREEMENT_TOLERANCE
        @test report.maximum_total_requirements_agreement_error <=
            TOTAL_MATRIX_AGREEMENT_TOLERANCE
        @test report.condition_number ≈
            2.977311523874868 rtol = 1.0e-10
        @test report.spectral_radius ≈
            0.47600766629400815 rtol = 1.0e-10
        @test report.direct_requirements["111CA", "111CA"] ≈
            0.20920301569129005 atol = 1.0e-13
        @test sum(report.direct_requirements.values) ≈
            33.43568672521894 atol = 1.0e-12
        @test report.provenance.total_requirements_source_sha256 ==
            "f38f13ac18365fe4a68ad64fc9a6be6661b62893c3b714ee2d070cb7e0cc434d"
        @test report.provenance.total_requirements_metadata_sha256 ==
            "1cc83c9eec20698bb5a31aaba81eb98dd176126c187399a4d78910c65cebf787"
        @test report.provenance.total_requirements_fixture_sha256 ==
            "d7285bc44bd9ee40cf51e1a7c0789fdce40b2764b438dec1c598cae81bc31b0b"
        @test report.provenance.total_requirements_manifest_sha256 ==
            "2bc6040081f9a888639948fe5e5cbf13732a257ee1f62784b19d0aaea4023084"
        @test report.provenance.official_direct_source_zip_sha256 ==
            "e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae"
        @test report.provenance.official_direct_source_metadata_sha256 ==
            "f3f57a7209f7c6d9b0f76b041f17ae78e9da1d8644dbd7d6815471e740abfaca"
        @test report.provenance.direct_workbook_sha256 ==
            "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439"
        @test report.provenance.market_share_workbook_sha256 ==
            "57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2"
        @test report.provenance.official_direct_fixture_sha256 ==
            "d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e"
        @test report.provenance.official_direct_manifest_sha256 ==
            "a225951d7ec03aaaaa97f5cc02e58b862e00918dbd31cc35093d80f9dde8c35d"
        @test report.provenance.spreadsheet_reader_version == "2.8.31"
        @test length(report.negative_direct_cells) == 6
        @test length(report.substantive_negative_direct_cells) == 5
        @test length(report.negative_direct_by_industry_cells) == 5
        @test length(report.negative_market_share_cells) == 1
        @test Set(
            (cell.row_code, cell.column_code)
                for cell in report.substantive_negative_direct_cells
        ) == Set(
            [
                ("Used", "111CA"),
                ("Used", "481"),
                ("Used", "483"),
                ("Used", "711AS"),
                ("Used", "GFGD"),
            ],
        )
        @test report.direct_requirements["Used", "621"] ≈
            -5.180472e-8 atol = 1.0e-15
        @test report.transformation ==
            :official_after_redefinitions_direct_times_market_share
        @test !report.clipping_applied
        @test !report.balancing_applied
        @test !report.promotion_ready
        @test "OFFICIAL_AFTER_REDEFINITIONS_MATRICES_ROUNDED_TO_SEVEN_DECIMALS" in
            report.promotion_blockers
        @test "SUBSTANTIVE_NEGATIVE_DIRECT_REQUIREMENTS_REQUIRE_GOVERNED_POLICY" in
            report.promotion_blockers

        supply_make = load_supply_make_report()
        transactions =
            build_requirements_transactions(report, supply_make)
        @test transaction_controls_pass(transactions)
        @test transactions.transformation ==
            :official_direct_output_weighted_retail_transaction_aggregation
        @test sum(transactions.transactions.values) ≈
            21_012_023.990183584 atol = 1.0e-6
        @test sum(
            cell.value
                for cell in transactions.negative_source_transaction_cells
        ) ≈ -694.1853182666081 atol = 1.0e-6
        @test sum(
            cell.value for cell in transactions.negative_transaction_cells
        ) ≈ -694.1853182666081 atol = 1.0e-6
        comparison = compare_structural_transactions(
            build_industry_technology_system(supply_make),
            transactions,
        )
        @test comparison_controls_pass(comparison)
        @test comparison.signed_total_difference ≈
            426_517.0098164129 atol = 1.0e-6
        @test comparison.absolute_cell_difference ≈
            4_370_627.389108137 atol = 1.0e-6
        @test comparison.frobenius_difference ≈
            344_131.50570847536 atol = 1.0e-6
        @test comparison.cell_correlation ≈
            0.9662451430071153 rtol = 1.0e-12
        @test comparison.maximum_absolute_difference_cell.row_code == "42"
        @test comparison.maximum_absolute_difference_cell.column_code == "23"
        @test comparison.maximum_absolute_difference_cell.requirements_value ≈
            143_321.6814276 atol = 1.0e-6
        @test comparison.maximum_absolute_difference_cell.difference ≈
            -142_831.14655205666 atol = 1.0e-6
        @test comparison.right_basis ==
            :official_after_redefinitions_direct_requirements_diagnostic

        commodity_permutation =
            reverse(eachindex(direct_fixture.direct_by_industry.row_codes))
        industry_permutation =
            reverse(eachindex(direct_fixture.direct_by_industry.column_codes))
        permuted_fixture = OfficialDirectRequirementsFixture(
            direct_fixture.year,
            LabeledMatrix{CommodityBasis, IndustryBasis}(
                direct_fixture.direct_by_industry.row_codes[
                    commodity_permutation,
                ],
                direct_fixture.direct_by_industry.column_codes[
                    industry_permutation,
                ],
                direct_fixture.direct_by_industry.values[
                    commodity_permutation,
                    industry_permutation,
                ],
                direct_fixture.direct_by_industry.explicit[
                    commodity_permutation,
                    industry_permutation,
                ],
            ),
            LabeledMatrix{IndustryBasis, CommodityBasis}(
                direct_fixture.market_shares.row_codes[industry_permutation],
                direct_fixture.market_shares.column_codes[
                    commodity_permutation,
                ],
                direct_fixture.market_shares.values[
                    industry_permutation,
                    commodity_permutation,
                ],
                direct_fixture.market_shares.explicit[
                    industry_permutation,
                    commodity_permutation,
                ],
            ),
            LabeledMatrix{
                USRequirementsDiagnostics.ValueAddedBasis,
                IndustryBasis,
            }(
                direct_fixture.value_added.row_codes,
                direct_fixture.value_added.column_codes[
                    industry_permutation,
                ],
                direct_fixture.value_added.values[:, industry_permutation],
                direct_fixture.value_added.explicit[:, industry_permutation],
            ),
            LabeledVector{IndustryBasis}(
                direct_fixture.industry_totals.codes[industry_permutation],
                direct_fixture.industry_totals.values[industry_permutation],
            ),
            direct_fixture.source_zip_sha256,
            direct_fixture.direct_workbook_sha256,
            direct_fixture.market_share_workbook_sha256,
            direct_fixture.manifest,
        )
        permuted_report = build_official_direct_requirements(
            total_fixture,
            permuted_fixture,
        )
        @test requirements_controls_pass(permuted_report)
        @test all(
            isapprox(
                    permuted_report.direct_requirements[row_code, column_code],
                    report.direct_requirements[row_code, column_code];
                    atol = 1.0e-12,
                )
                for row_code in report.direct_requirements.row_codes
                for column_code in report.direct_requirements.column_codes
        )

        corrupted = copied_official_direct_fixture()
        corrupted_cells_path = joinpath(corrupted, "cells.csv")
        cells = read(corrupted_cells_path, String)
        write(
            corrupted_cells_path,
            replace(cells, "0.2092970" => "0.2092971"; count = 1),
        )
        @test_throws ArgumentError load_official_direct_requirements_fixture(
            corrupted,
        )

        origin_claim = copied_official_direct_fixture()
        origin_manifest_path = joinpath(origin_claim, "manifest.toml")
        manifest = read(origin_manifest_path, String)
        write(
            origin_manifest_path,
            replace(
                manifest,
                "forecast_origin_admissible = false" =>
                    "forecast_origin_admissible = true";
                count = 1,
            ),
        )
        @test_throws ArgumentError load_official_direct_requirements_fixture(
            origin_claim,
        )
    end

    @testset "Output-weighted retail aggregation" begin
        fixture = load_requirements_fixture(REQUIREMENTS_FIXTURE_DIRECTORY)
        report = build_direct_requirements(fixture)
        supply_make = load_supply_make_report()
        transactions =
            build_requirements_transactions(report, supply_make)

        @test size(transactions.source_transactions) == (73, 73)
        @test size(transactions.transactions) == (70, 70)
        @test size(transactions.direct_requirements) == (70, 70)
        @test length(transactions.source_commodity_output) == 73
        @test length(transactions.commodity_output) == 70
        @test transactions.transactions.row_codes ==
            transactions.transactions.column_codes
        @test transactions.direct_requirements.row_codes ==
            transactions.transactions.row_codes
        @test !any(transactions.source_transactions.explicit)
        @test !any(transactions.transactions.explicit)
        @test !any(transactions.direct_requirements.explicit)
        @test sum(transactions.source_commodity_output.values) ==
            49_726_234.0
        @test sum(transactions.commodity_output.values) == 49_726_234.0
        @test transactions.commodity_output["4A0"] == 2_403_974.0
        @test transactions.commodity_output["Other"] == 6_187.0
        @test transactions.commodity_output["Used"] == 13_553.0

        @test length(transactions.residuals) == 3
        @test transaction_controls_pass(transactions)
        @test count(residual -> !residual.passed, transactions.residuals) == 0
        @test sum(transactions.source_transactions.values) ≈
            21_012_023.1123363 atol = 1.0e-6
        @test sum(transactions.transactions.values) ≈
            21_012_023.1123363 atol = 1.0e-6
        @test sum(
            cell.value
                for cell in transactions.negative_source_transaction_cells
        ) ≈ -698.0012472515604 atol = 1.0e-6
        @test sum(
            cell.value for cell in transactions.negative_transaction_cells
        ) ≈ -697.8734967714099 atol = 1.0e-6
        @test Set(transactions.explicit_closure_codes) ==
            Set(["Other", "Used"])
        @test transactions.commodity_mapping["441"] == "4A0"
        @test transactions.commodity_mapping["Other"] == "Other"
        @test transactions.commodity_mapping["Used"] == "Used"
        @test transactions.transformation ==
            :implied_direct_output_weighted_retail_transaction_aggregation
        @test !transactions.clipping_applied
        @test !transactions.balancing_applied
        @test !transactions.promotion_ready
        @test "OUTPUT_WEIGHTED_RETAIL_AGGREGATION_DIAGNOSTIC_ONLY" in
            transactions.promotion_blockers

        wrong_year_fixture = RequirementsFixture(
            2023,
            fixture.total_requirements,
            fixture.total_output_requirements,
            fixture.source_sha256,
            fixture.manifest,
        )
        @test_throws ArgumentError build_requirements_transactions(
            build_direct_requirements(wrong_year_fixture),
            supply_make,
        )

        reconstructed =
            transactions.direct_requirements.values .*
            reshape(transactions.commodity_output.values, 1, :)
        @test maximum(
            abs,
            reconstructed - transactions.transactions.values,
        ) <= 1.0e-6

        symmetric = build_industry_technology_system(supply_make)
        comparison =
            compare_structural_transactions(symmetric, transactions)
        @test comparison_controls_pass(comparison)
        @test length(comparison.residuals) == 3
        @test size(comparison.signed_difference) == (70, 70)
        @test !any(comparison.signed_difference.explicit)
        @test comparison.signed_total_difference ≈
            426_517.8876636991 atol = 1.0e-6
        @test comparison.absolute_cell_difference ≈
            4_370_633.854742937 atol = 1.0e-6
        @test comparison.frobenius_difference ≈
            344_131.4896266068 atol = 1.0e-6
        @test comparison.cell_correlation ≈
            0.966245146371278 rtol = 1.0e-12
        @test comparison.row_difference["42"] ≈
            -1_169_852.269149011 atol = 1.0e-6
        @test comparison.column_difference["42"] ≈
            115_403.98133577591 atol = 1.0e-6
        @test comparison.maximum_absolute_difference_cell.row_code == "42"
        @test comparison.maximum_absolute_difference_cell.column_code == "23"
        @test comparison.maximum_absolute_difference_cell.symmetric_value ≈
            490.53487554334646 atol = 1.0e-6
        @test comparison.maximum_absolute_difference_cell.requirements_value ≈
            143_321.75643285608 atol = 1.0e-6
        @test comparison.maximum_absolute_difference_cell.difference ≈
            -142_831.22155731273 atol = 1.0e-6
        @test comparison.comparison_role ==
            :basis_and_system_boundary_comparison_only
        @test !comparison.valuation_bridge_applied
        @test !comparison.balancing_applied
        @test !comparison.clipping_applied
        @test !comparison.promotion_ready
        @test "COMPARISON_IS_NOT_A_VALUATION_BRIDGE" in
            comparison.promotion_blockers
    end

    @testset "Code ordering and evidence fail closed" begin
        fixture = load_requirements_fixture(REQUIREMENTS_FIXTURE_DIRECTORY)
        report = build_direct_requirements(fixture)
        supply_make = load_supply_make_report()
        transactions =
            build_requirements_transactions(report, supply_make)

        permutation = reverse(eachindex(fixture.total_requirements.row_codes))
        permuted_codes =
            fixture.total_requirements.row_codes[permutation]
        permuted_fixture = RequirementsFixture(
            fixture.year,
            LabeledMatrix{CommodityBasis, CommodityBasis}(
                permuted_codes,
                permuted_codes,
                fixture.total_requirements.values[
                    permutation,
                    permutation,
                ],
                fixture.total_requirements.explicit[
                    permutation,
                    permutation,
                ],
            ),
            LabeledVector{CommodityBasis}(
                permuted_codes,
                fixture.total_output_requirements.values[permutation],
            ),
            fixture.source_sha256,
            fixture.manifest,
        )
        permuted_report = build_direct_requirements(permuted_fixture)
        permuted_transactions =
            build_requirements_transactions(permuted_report, supply_make)
        symmetric = build_industry_technology_system(supply_make)
        comparison =
            compare_structural_transactions(symmetric, transactions)
        permuted_comparison =
            compare_structural_transactions(
            symmetric,
            permuted_transactions,
        )
        @test requirements_controls_pass(permuted_report)
        @test transaction_controls_pass(permuted_transactions)
        @test comparison_controls_pass(permuted_comparison)
        @test all(
            isapprox(
                    permuted_report.direct_requirements[row, column],
                    report.direct_requirements[row, column];
                    atol = 1.0e-12,
                )
                for row in report.direct_requirements.row_codes
                for column in report.direct_requirements.column_codes
        )
        @test all(
            isapprox(
                    permuted_transactions.transactions[row, column],
                    transactions.transactions[row, column];
                    atol = 1.0e-6,
                )
                for row in transactions.transactions.row_codes
                for column in transactions.transactions.column_codes
        )
        @test all(
            isapprox(
                    permuted_comparison.signed_difference[row, column],
                    comparison.signed_difference[row, column];
                    atol = 1.0e-6,
                )
                for row in comparison.signed_difference.row_codes
                for column in comparison.signed_difference.column_codes
        )

        mismatched_fixture = RequirementsFixture(
            fixture.year,
            LabeledMatrix{CommodityBasis, CommodityBasis}(
                fixture.total_requirements.row_codes,
                reverse(fixture.total_requirements.column_codes),
                fixture.total_requirements.values,
                fixture.total_requirements.explicit,
            ),
            fixture.total_output_requirements,
            fixture.source_sha256,
            fixture.manifest,
        )
        @test_throws ArgumentError build_direct_requirements(
            mismatched_fixture,
        )

        corrupted = copied_fixture()
        cells_path = joinpath(corrupted, "cells.csv")
        cells = read(cells_path, String)
        write(cells_path, replace(cells, "2.2643741" => "2.2643742"; count = 1))
        @test_throws ArgumentError load_requirements_fixture(corrupted)

        wrong_status = copied_fixture()
        manifest_path = joinpath(wrong_status, "manifest.toml")
        manifest = read(manifest_path, String)
        write(
            manifest_path,
            replace(
                manifest,
                "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE" =>
                    "APPROVED_ARCHIVED";
                count = 1,
            ),
        )
        @test_throws ArgumentError load_requirements_fixture(wrong_status)

        origin_claim = copied_fixture()
        manifest_path = joinpath(origin_claim, "manifest.toml")
        manifest = read(manifest_path, String)
        write(
            manifest_path,
            replace(
                manifest,
                "forecast_origin_admissible = false" =>
                    "forecast_origin_admissible = true";
                count = 1,
            ),
        )
        @test_throws ArgumentError load_requirements_fixture(origin_claim)

        source_relabel = copied_fixture()
        manifest_path = joinpath(source_relabel, "manifest.toml")
        manifest = read(manifest_path, String)
        write(
            manifest_path,
            replace(
                manifest,
                fixture.source_sha256 => repeat("0", 64);
                count = 1,
            ),
        )
        @test_throws ArgumentError load_requirements_fixture(source_relabel)

        loose_tolerance = copied_fixture()
        manifest_path = joinpath(loose_tolerance, "manifest.toml")
        manifest = read(manifest_path, String)
        write(
            manifest_path,
            replace(
                manifest,
                "published_decimal_places = 7" =>
                    "published_decimal_places = 0";
                count = 1,
            ),
        )
        @test_throws ArgumentError load_requirements_fixture(loose_tolerance)
    end
end
