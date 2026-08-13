using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsValuationEnvelope.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsFinalUseEnvelope.jl"))

using .USAfterRedefinitionsCommonBasis
using .USAfterRedefinitionsFinalUseEnvelope
using .USAfterRedefinitionsModelCore

const FINAL_USE_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_final_use_envelope.toml")
const FINAL_USE_AFTER_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const FINAL_USE_SUPPLY_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "bea_2024_approved")
const FINAL_USE_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const FINAL_USE_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const FINAL_USE_VALUATION_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_valuation_envelope.toml")
const FINAL_USE_CODES_TEST = [
    "F010",
    "F02S",
    "F02E",
    "F02N",
    "F02R",
    "F030",
    "F040",
    "F050",
    "F06C",
    "F06S",
    "F06E",
    "F06N",
    "F07C",
    "F07S",
    "F07E",
    "F07N",
    "F10C",
    "F10S",
    "F10E",
    "F10N",
]
const FINAL_USE_CATEGORY_CODES_TEST = [
    "household_consumption",
    "private_fixed_investment",
    "inventory_change",
    "exports",
    "imports_accounting_offset",
    "government_consumption",
    "government_gross_investment",
]
const FINAL_USE_CATEGORY_COLUMNS_TEST = Dict(
    "household_consumption" => ["F010"],
    "private_fixed_investment" => ["F02S", "F02E", "F02N", "F02R"],
    "inventory_change" => ["F030"],
    "exports" => ["F040"],
    "imports_accounting_offset" => ["F050"],
    "government_consumption" => ["F06C", "F07C", "F10C"],
    "government_gross_investment" => [
        "F06S",
        "F06E",
        "F06N",
        "F07S",
        "F07E",
        "F07N",
        "F10S",
        "F10E",
        "F10N",
    ],
)
const FINAL_USE_BLOCKER_PREFIX_TEST = [
    "PRODUCER_PRICE_FINAL_USE_NOT_CONNECTED_TO_MODEL_STATE",
    "FINAL_USE_CATEGORY_LEDGER_NOT_CALIBRATION_ADAPTER",
    "F030_FLOW_NOT_MAPPED_TO_QUARTER_END_STOCK",
    "F050_OFFSET_NOT_SELECTED_AS_MODEL_IMPORT_BOUNDARY",
    "LEGACY_T013_T016_SCALAR_BRIDGE_REJECTED",
]
const FINAL_USE_VALUATION_BLOCKER_PREFIX_TEST = [
    "MULTI_ARCHIVE_RELEASE_IDENTITY_NOT_EXTERNALLY_BOUND",
    "COMMODITY_REDEFINITION_REDISTRIBUTION_NOT_ALLOCATED",
    "MARGIN_TRANSPORT_USE_CELL_ALLOCATION_NOT_PROVIDED",
    "PRODUCT_TAX_USE_CELL_ALLOCATION_NOT_PROVIDED",
    "PROPORTIONAL_OR_SCALAR_VALUATION_BRIDGE_NOT_APPROVED",
    "OBSERVED_TAX_AND_ZERO_TAX_VARIANTS_NOT_TRANSITION_TESTED",
]

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function independently_aggregate_categories(matrix, category_codes, mapping)
    values = zeros(size(matrix.values, 1), length(category_codes))
    explicit = falses(size(values))
    for (category_position, category) in pairs(category_codes)
        positions = [
            matrix.column_index[code] for code in mapping[category]
        ]
        values[:, category_position] =
            vec(sum(matrix.values[:, positions]; dims = 2))
        explicit[:, category_position] =
            vec(any(matrix.explicit[:, positions]; dims = 2))
    end
    return (; values, explicit = BitMatrix(explicit))
end

function independently_aggregate_rows(
        matrix,
        target_codes,
        source_mapping,
    )
    values = zeros(length(target_codes), size(matrix.values, 2))
    explicit = falses(size(values))
    for (target_position, target_code) in pairs(target_codes)
        positions = findall(
            source_code -> source_mapping[source_code] == target_code,
            matrix.row_codes,
        )
        values[target_position, :] =
            vec(sum(matrix.values[positions, :]; dims = 1))
        explicit[target_position, :] =
            vec(any(matrix.explicit[positions, :]; dims = 1))
    end
    return (; values, explicit = BitMatrix(explicit))
end

function residual_family_counts(residuals)
    return Dict(
        family => count(residual -> residual.family == family, residuals)
            for family in unique(residual.family for residual in residuals)
    )
end

function maximum_residual_ratio(report, family)
    family_residuals =
        filter(residual -> residual.family == family, report.residuals)
    return maximum(
        residual.tolerance == 0.0 ?
            (residual.residual == 0.0 ? 0.0 : Inf) :
            abs(residual.residual) / residual.tolerance
            for residual in family_residuals
    )
end

function copied_fixture(source_directory)
    target_directory = mktempdir()
    for filename in ("cells.csv", "manifest.toml")
        cp(
            joinpath(source_directory, filename),
            joinpath(target_directory, filename),
        )
    end
    return target_directory
end

function copied_file(source_path)
    target_path = joinpath(mktempdir(), basename(source_path))
    cp(source_path, target_path)
    return target_path
end

function append_newline(path)
    write(path, read(path, String) * "\n")
    return path
end

@testset "BEA after-redefinitions producer-price final-use envelope" begin
    fixture = load_after_redefinitions_fixture(
        FINAL_USE_AFTER_FIXTURE_DIRECTORY,
    )
    model_core = build_model_core_aggregation(
        fixture,
        FINAL_USE_MODEL_MAPPING_PATH;
        sector_mapping_path = FINAL_USE_SECTOR_MAPPING_PATH,
    )
    report = build_final_use_envelope(
        FINAL_USE_CONTRACT_PATH;
        after_directory = FINAL_USE_AFTER_FIXTURE_DIRECTORY,
        supply_directory = FINAL_USE_SUPPLY_FIXTURE_DIRECTORY,
        model_mapping_path = FINAL_USE_MODEL_MAPPING_PATH,
        sector_mapping_path = FINAL_USE_SECTOR_MAPPING_PATH,
        valuation_contract_path = FINAL_USE_VALUATION_CONTRACT_PATH,
    )
    contract = TOML.parsefile(FINAL_USE_CONTRACT_PATH)

    @testset "Pinned contract and fail-closed scientific role" begin
        @test sha256_hex(read(FINAL_USE_CONTRACT_PATH)) ==
            "b4e3969a52618b4e462b8e468ada784dda85cae86550fb27659d2afbb4cbb2be"
        @test sha256_hex(
            read(
                joinpath(
                    FINAL_USE_AFTER_FIXTURE_DIRECTORY,
                    "cells.csv",
                ),
            ),
        ) ==
            "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac"
        @test sha256_hex(
            read(
                joinpath(
                    FINAL_USE_AFTER_FIXTURE_DIRECTORY,
                    "manifest.toml",
                ),
            ),
        ) ==
            "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030"
        @test sha256_hex(read(FINAL_USE_MODEL_MAPPING_PATH)) ==
            "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c"
        @test sha256_hex(read(FINAL_USE_SECTOR_MAPPING_PATH)) ==
            "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f"
        @test sha256_hex(read(FINAL_USE_VALUATION_CONTRACT_PATH)) ==
            "110f82037e45e1de3ce4f5a1df2b7982d064e90a9323f255c7441452fa6d2ede"

        @test contract["schema_version"] ==
            "beforeit-us-after-redefinitions-final-use-envelope.v1"
        @test contract["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract["promotion_status"] == "RESEARCH_ONLY_NOT_PROMOTED"
        @test contract["source_year"] == 2024
        @test contract["price_basis"] == "producers prices"
        @test String.(contract["final_use_codes"]) ==
            FINAL_USE_CODES_TEST
        @test String.(contract["category_codes"]) ==
            FINAL_USE_CATEGORY_CODES_TEST
        @test String.(contract["value_added_codes"]) ==
            ["V001", "V002", "V003"]
        @test length(contract["final_use_category"]) == 7
        @test Set(
            reduce(
                vcat,
                (
                    String.(spec["source_columns"])
                        for spec in contract["final_use_category"]
                );
                init = String[],
            ),
        ) == Set(FINAL_USE_CODES_TEST)
        @test contract["legacy_scalar_bridge_status"] ==
            "REJECTED_NOT_CELL_IDENTIFIED"
        @test contract["cell_level_valuation_allocation_status"] ==
            "MISSING"
        @test contract["inventory_policy"] ==
            "F030_SIGNED_FLOW_NOT_STOCK"
        @test contract["import_policy"] ==
            "F050_SIGNED_ACCOUNTING_OFFSET_NOT_MODEL_IMPORT_VECTOR"
        @test contract["observed_tax_variant_policy"] ==
            "CONTROL_ONLY_NOT_USE_CELL_ALLOCATED"
        @test contract["zero_tax_variant_policy"] ==
            "POLICY_COUNTERFACTUAL_NOT_OBSERVATION"
        @test !contract["forecast_origin_admissible"]
        @test !contract["model_state_write"]
        @test contract["accounting_gate_effect"] == "NONE"
        for flag in (
                "final_use_adjustment_applied",
                "closure_allocation_applied",
                "inventory_stock_mapping_applied",
                "import_boundary_selected",
                "legacy_scalar_bridge_applied",
                "balancing_applied",
                "clipping_applied",
            )
            @test !contract[flag]
        end

        @test report.year == 2024
        @test report.contract_sha256 ==
            sha256_hex(read(FINAL_USE_CONTRACT_PATH))
        @test report.after_fixture_sha256 ==
            sha256_hex(
            read(
                joinpath(
                    FINAL_USE_AFTER_FIXTURE_DIRECTORY,
                    "cells.csv",
                ),
            ),
        )
        @test report.after_manifest_sha256 ==
            sha256_hex(
            read(
                joinpath(
                    FINAL_USE_AFTER_FIXTURE_DIRECTORY,
                    "manifest.toml",
                ),
            ),
        )
        @test report.after_source_zip_sha256 ==
            "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
        @test report.model_mapping_sha256 ==
            sha256_hex(read(FINAL_USE_MODEL_MAPPING_PATH))
        @test report.sector_mapping_sha256 ==
            sha256_hex(read(FINAL_USE_SECTOR_MAPPING_PATH))
        @test report.valuation_contract_sha256 ==
            sha256_hex(read(FINAL_USE_VALUATION_CONTRACT_PATH))
        @test report.source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test report.transformation ==
            :code_keyed_final_use_partition_with_explicit_closure
        @test report.price_basis == :producers_prices
        @test report.closure_policy == :used_other_separate_unallocated
        @test report.inventory_policy == :f030_signed_flow_not_stock
        @test report.import_policy ==
            :f050_signed_accounting_offset_not_model_import_vector
        @test report.observed_tax_variant_policy ==
            :control_only_not_use_cell_allocated
        @test report.zero_tax_variant_policy ==
            :policy_counterfactual_not_observation
        @test !report.final_use_adjustment_applied
        @test !report.closure_allocation_applied
        @test !report.inventory_stock_mapping_applied
        @test !report.import_boundary_selected
        @test !report.legacy_scalar_bridge_applied
        @test !report.balancing_applied
        @test !report.clipping_applied
        @test !report.model_state_write
        @test report.accounting_gate_effect == :none
        @test !report.forecast_origin_admissible
        @test !report.promotion_ready
        @test report.promotion_blockers[1:5] ==
            FINAL_USE_BLOCKER_PREFIX_TEST
        @test report.promotion_blockers[6:11] ==
            FINAL_USE_VALUATION_BLOCKER_PREFIX_TEST
        @test report.promotion_blockers[12:end] ==
            model_core.promotion_blockers
        @test length(report.promotion_blockers) == 24

        bridge = report.legacy_bridge
        @test bridge.method ==
            :t013_over_t016_commodity_ratio_with_proportional_recipient_rescale
        @test bridge.status == :rejected_not_cell_identified
        @test !bridge.cell_identified
        @test !bridge.recipient_allocation_observed
        @test bridge.diagnostic_only
        @test !bridge.applied
        @test !bridge.model_state_admissible
        @test !bridge.forecast_origin_admissible

        @test final_use_envelope_internal_controls_pass(report)
        @test final_use_envelope_controls_pass(
            report,
            FINAL_USE_CONTRACT_PATH;
            after_directory = FINAL_USE_AFTER_FIXTURE_DIRECTORY,
            supply_directory = FINAL_USE_SUPPLY_FIXTURE_DIRECTORY,
            model_mapping_path = FINAL_USE_MODEL_MAPPING_PATH,
            sector_mapping_path = FINAL_USE_SECTOR_MAPPING_PATH,
            valuation_contract_path = FINAL_USE_VALUATION_CONTRACT_PATH,
        )
        @test_throws MethodError final_use_envelope_controls_pass(report)
    end

    @testset "Independent source projection, category partition, and masks" begin
        expected_source_categories = independently_aggregate_categories(
            fixture.producer_final_use,
            FINAL_USE_CATEGORY_CODES_TEST,
            FINAL_USE_CATEGORY_COLUMNS_TEST,
        )
        expected_model = independently_aggregate_rows(
            fixture.producer_final_use,
            model_core.model_codes,
            model_core.source_commodity_mapping,
        )
        expected_closure = independently_aggregate_rows(
            fixture.producer_final_use,
            model_core.closure_codes,
            model_core.source_commodity_mapping,
        )
        expected_model_categories = independently_aggregate_categories(
            report.model_final_use,
            FINAL_USE_CATEGORY_CODES_TEST,
            FINAL_USE_CATEGORY_COLUMNS_TEST,
        )
        expected_closure_categories = independently_aggregate_categories(
            report.closure_final_use,
            FINAL_USE_CATEGORY_CODES_TEST,
            FINAL_USE_CATEGORY_COLUMNS_TEST,
        )

        @test report.source_commodity_codes ==
            fixture.producer_final_use.row_codes
        @test length(report.source_commodity_codes) == 73
        @test report.model_codes == model_core.model_codes
        @test length(report.model_codes) == 68
        @test report.closure_codes == ["Used", "Other"]
        @test report.final_use_codes == FINAL_USE_CODES_TEST
        @test report.category_codes == FINAL_USE_CATEGORY_CODES_TEST
        @test report.category_columns ==
            FINAL_USE_CATEGORY_COLUMNS_TEST
        @test size(report.source_final_use.values) == (73, 20)
        @test size(report.source_category_final_use.values) == (73, 7)
        @test size(report.model_final_use.values) == (68, 20)
        @test size(report.model_category_final_use.values) == (68, 7)
        @test size(report.closure_final_use.values) == (2, 20)
        @test size(report.closure_category_final_use.values) == (2, 7)
        @test report.source_final_use.values ==
            fixture.producer_final_use.values
        @test report.source_final_use.explicit ==
            fixture.producer_final_use.explicit
        @test report.source_category_final_use.values ==
            expected_source_categories.values
        @test report.source_category_final_use.explicit ==
            expected_source_categories.explicit
        @test report.model_final_use.values == expected_model.values
        @test report.model_final_use.explicit == expected_model.explicit
        @test report.closure_final_use.values == expected_closure.values
        @test report.closure_final_use.explicit ==
            expected_closure.explicit
        @test report.model_category_final_use.values ==
            expected_model_categories.values
        @test report.model_category_final_use.explicit ==
            expected_model_categories.explicit
        @test report.closure_category_final_use.values ==
            expected_closure_categories.values
        @test report.closure_category_final_use.explicit ==
            expected_closure_categories.explicit

        for (row_position, _) in pairs(report.source_commodity_codes)
            @test sum(report.source_final_use.values[row_position, :]) ==
                sum(
                report.source_category_final_use.values[
                    row_position,
                    :,
                ],
            )
        end
        explicit_zero = findfirst(
            (report.source_final_use.values .== 0.0) .&
                report.source_final_use.explicit,
        )
        omitted_zero = findfirst(
            (report.source_final_use.values .== 0.0) .&
                .!report.source_final_use.explicit,
        )
        @test !isnothing(explicit_zero)
        @test !isnothing(omitted_zero)
        @test report.source_final_use.values[explicit_zero] ==
            report.source_final_use.values[omitted_zero] == 0.0
        @test report.source_final_use.explicit[explicit_zero]
        @test !report.source_final_use.explicit[omitted_zero]

        @test count(report.source_final_use.explicit) == 359
        @test count(report.source_category_final_use.explicit) == 271
        @test count(report.model_final_use.explicit) == 332
        @test count(report.model_category_final_use.explicit) == 255
        @test count(report.closure_final_use.explicit) == 16
        @test count(report.closure_category_final_use.explicit) == 10
        @test count(
            (report.source_final_use.values .== 0.0) .&
                report.source_final_use.explicit,
        ) == 9
        @test count(
            (report.source_final_use.values .== 0.0) .&
                .!report.source_final_use.explicit,
        ) == 1_101
        expected_model_category_explicit_counts = Dict(
            "household_consumption" => 60,
            "private_fixed_investment" => 31,
            "inventory_change" => 32,
            "exports" => 58,
            "imports_accounting_offset" => 50,
            "government_consumption" => 3,
            "government_gross_investment" => 21,
        )
        expected_closure_category_explicit_counts = Dict(
            "household_consumption" => 2,
            "private_fixed_investment" => 2,
            "inventory_change" => 1,
            "exports" => 2,
            "imports_accounting_offset" => 2,
            "government_consumption" => 0,
            "government_gross_investment" => 1,
        )
        for category in FINAL_USE_CATEGORY_CODES_TEST
            @test count(
                report.model_category_final_use.explicit[
                    :,
                    report.model_category_final_use.column_index[category],
                ],
            ) == expected_model_category_explicit_counts[category]
            @test count(
                report.closure_category_final_use.explicit[
                    :,
                    report.closure_category_final_use.column_index[
                        category,
                    ],
                ],
            ) == expected_closure_category_explicit_counts[category]
        end
    end

    @testset "Category controls, closure, signs, and GDP approaches" begin
        expected_model = Dict(
            "household_consumption" => 19_853_257.0,
            "private_fixed_investment" => 5_360_603.0,
            "inventory_change" => 44_095.0,
            "exports" => 2_528_675.0,
            "imports_accounting_offset" => -3_294_892.0,
            "government_consumption" => 3_991_840.0,
            "government_gross_investment" => 1_067_412.0,
        )
        expected_closure = Dict(
            "household_consumption" => 42_750.0,
            "private_fixed_investment" => -154_828.0,
            "inventory_change" => 9_450.0,
            "exports" => 254_403.0,
            "imports_accounting_offset" => -386_649.0,
            "government_consumption" => 0.0,
            "government_gross_investment" => -18_109.0,
        )
        expected_published = Dict(
            "household_consumption" => 19_896_009.0,
            "private_fixed_investment" => 5_205_774.0,
            "inventory_change" => 53_546.0,
            "exports" => 2_783_078.0,
            "imports_accounting_offset" => -3_681_538.0,
            "government_consumption" => 3_991_840.0,
            "government_gross_investment" => 1_049_304.0,
        )
        for category in FINAL_USE_CATEGORY_CODES_TEST
            model_total = sum(
                report.model_category_final_use.values[
                    :,
                    report.model_category_final_use.column_index[category],
                ],
            )
            closure_total = sum(
                report.closure_category_final_use.values[
                    :,
                    report.closure_category_final_use.column_index[
                        category,
                    ],
                ],
            )
            @test model_total == expected_model[category]
            @test closure_total == expected_closure[category]
            @test report.published_category_controls[category] ==
                expected_published[category]
            @test abs(
                model_total + closure_total -
                    expected_published[category],
            ) <= 3.0
        end

        @test sum(report.model_intermediate_use.values) == 21_165_843.0
        @test sum(report.closure_intermediate_use.values) == 272_726.0
        @test sum(report.model_final_use.values) == 29_550_990.0
        @test sum(report.closure_final_use.values) == -252_983.0
        @test sum(
            report.closure_intermediate_use.values[
                report.closure_intermediate_use.row_index["Used"],
                :,
            ],
        ) == 100_094.0
        @test sum(
            report.closure_intermediate_use.values[
                report.closure_intermediate_use.row_index["Other"],
                :,
            ],
        ) == 172_632.0
        @test sum(
            report.closure_final_use.values[
                report.closure_final_use.row_index["Used"],
                :,
            ],
        ) == -86_542.0
        @test sum(
            report.closure_final_use.values[
                report.closure_final_use.row_index["Other"],
                :,
            ],
        ) == -166_441.0

        value_added_totals = Dict(
            code => sum(
                    report.producer_value_added.values[
                        report.producer_value_added.row_index[code],
                        :,
                    ],
                ) for code in ("V001", "V002", "V003")
        )
        @test value_added_totals == Dict(
            "V001" => 15_049_121.0,
            "V002" => 1_860_445.0,
            "V003" => 12_388_448.0,
        )
        @test count(
            value -> value < 0.0,
            report.producer_value_added.values[
                report.producer_value_added.row_index["V002"],
                :,
            ],
        ) == 4
        @test count(
            iszero,
            report.producer_value_added.values[
                report.producer_value_added.row_index["V002"],
                :,
            ],
        ) == 3
        @test length(report.negative_model_final_use_cells) == 52
        @test length(report.negative_closure_final_use_cells) == 9
        @test length(report.negative_source_final_use_cells) == 61
        @test count(
            value -> value < 0.0,
            report.source_category_final_use.values,
        ) == 57
        @test length(report.negative_model_category_cells) == 52
        @test length(report.negative_closure_category_cells) == 5
        @test length(report.negative_value_added_cells) == 4
        @test count(report.producer_value_added.explicit) == 201

        gdp = report.gdp
        @test gdp.cell_expenditure == 29_298_007.0
        @test gdp.cell_income == 29_298_014.0
        @test gdp.cell_industry_output == 50_736_554.0
        @test gdp.cell_intermediate_use == 21_438_569.0
        @test gdp.cell_production == 29_297_985.0
        @test gdp.published_expenditure == 29_298_013.0
        @test gdp.published_income == 29_298_013.0
        @test gdp.published_output == 50_736_555.0
        @test gdp.published_intermediate_use == 21_438_542.0
        @test gdp.published_production == 29_298_013.0
        @test gdp.cell_expenditure_income_gap == -7.0
        @test gdp.cell_production_income_gap == -29.0
        @test gdp.published_expenditure_income_gap == 0.0
        @test gdp.published_production_income_gap == 0.0

        @test report.observed_tax_variant.use_cell_allocation == :none
        @test sum(
            report.observed_tax_variant.commodity_net_product_tax.values,
        ) == 986_971.0
        @test report.closure_net_product_tax_control.codes ==
            ["Used", "Other"]
        @test sum(report.closure_net_product_tax_control.values) ==
            23_351.0
        @test report.source_net_product_tax_total == 1_010_322.0
        @test sum(
            report.observed_tax_variant.commodity_net_product_tax.values,
        ) + sum(report.closure_net_product_tax_control.values) ==
            report.source_net_product_tax_total
        @test all(
            iszero,
            report.zero_tax_variant.commodity_net_product_tax.values,
        )
        @test !report.observed_tax_variant.allocation_applied
        @test !report.zero_tax_variant.allocation_applied
    end

    @testset "Residual inventory and publication-rounding envelope" begin
        @test length(report.residuals) == 275
        @test all(residual.passed for residual in report.residuals)
        @test residual_family_counts(report.residuals) == Dict(
            :final_use_column_published_control => 20,
            :final_use_category_published_control => 7,
            :source_final_use_row_partition => 73,
            :model_final_use_row_partition => 68,
            :closure_final_use_row_partition => 2,
            :final_use_source_to_model_aggregation => 20,
            :final_use_category_aggregation => 7,
            :published_final_use_category_partition => 1,
            :value_added_published_control => 1,
            :industry_output_published_control => 1,
            :intermediate_use_published_control => 1,
            :cell_gdp_expenditure_income => 1,
            :cell_gdp_production_income => 1,
            :published_gdp_expenditure_income => 1,
            :published_gdp_production_income => 1,
            :model_industry_output_identity => 68,
            :observed_tax_control => 1,
            :zero_tax_policy_control => 1,
        )
        @test maximum_residual_ratio(
            report,
            :final_use_column_published_control,
        ) <= 3 / 37
        @test maximum_residual_ratio(
            report,
            :final_use_category_published_control,
        ) <= 3 / 37
        @test maximum_residual_ratio(
            report,
            :value_added_published_control,
        ) == 1 / 107
        @test maximum_residual_ratio(
            report,
            :industry_output_published_control,
        ) <= 1 / 36
        @test maximum_residual_ratio(
            report,
            :intermediate_use_published_control,
        ) <= 27 / 2592
        @test maximum_residual_ratio(
            report,
            :cell_gdp_expenditure_income,
        ) == 7 / 836.5
        @test maximum_residual_ratio(
            report,
            :cell_gdp_production_income,
        ) == 29 / 2733.5
        @test maximum_residual_ratio(
            report,
            :model_industry_output_identity,
        ) == 6 / 38.5
        for family in (
                :source_final_use_row_partition,
                :model_final_use_row_partition,
                :closure_final_use_row_partition,
                :final_use_source_to_model_aggregation,
                :final_use_category_aggregation,
                :published_final_use_category_partition,
                :published_gdp_expenditure_income,
                :published_gdp_production_income,
                :observed_tax_control,
                :zero_tax_policy_control,
            )
            @test maximum_residual_ratio(report, family) == 0.0
        end
    end

    @testset "Stale reports and changed source bytes fail closed" begin
        stale_source = deepcopy(report)
        stale_source.source_final_use.values[1, 1] += 1.0
        @test !final_use_envelope_internal_controls_pass(stale_source)
        @test !final_use_envelope_controls_pass(
            stale_source,
            FINAL_USE_CONTRACT_PATH,
        )

        compensated_source = deepcopy(report)
        compensated_source.source_final_use.values[1, 1] += 1.0
        compensated_source.source_final_use.values[2, 1] -= 1.0
        compensated_source.source_category_final_use.values[1, 1] += 1.0
        compensated_source.source_category_final_use.values[2, 1] -= 1.0
        @test !final_use_envelope_internal_controls_pass(
            compensated_source,
        )

        stale_mask = deepcopy(report)
        stale_mask.source_final_use.explicit[1, 1] =
            !stale_mask.source_final_use.explicit[1, 1]
        @test !final_use_envelope_internal_controls_pass(stale_mask)

        stale_published_control = deepcopy(report)
        stale_published_control.published_final_use_controls.values[1] +=
            1.0
        @test !final_use_envelope_internal_controls_pass(
            stale_published_control,
        )

        compensated_mask = deepcopy(report)
        compensated_mask.producer_value_added.explicit[1, 1] =
            !compensated_mask.producer_value_added.explicit[1, 1]
        @test final_use_envelope_internal_controls_pass(compensated_mask)
        @test !final_use_envelope_controls_pass(
            compensated_mask,
            FINAL_USE_CONTRACT_PATH,
        )

        stale_residuals = deepcopy(report)
        pop!(stale_residuals.residuals)
        @test !final_use_envelope_internal_controls_pass(stale_residuals)

        stale_blockers = deepcopy(report)
        empty!(stale_blockers.promotion_blockers)
        @test !final_use_envelope_internal_controls_pass(stale_blockers)

        changed_contract = copied_file(FINAL_USE_CONTRACT_PATH)
        append_newline(changed_contract)
        @test_throws ArgumentError build_final_use_envelope(changed_contract)
        @test !final_use_envelope_controls_pass(
            report,
            changed_contract,
        )

        changed_after_cells =
            copied_fixture(FINAL_USE_AFTER_FIXTURE_DIRECTORY)
        append_newline(joinpath(changed_after_cells, "cells.csv"))
        @test_throws ArgumentError build_final_use_envelope(
            FINAL_USE_CONTRACT_PATH;
            after_directory = changed_after_cells,
        )
        @test !final_use_envelope_controls_pass(
            report,
            FINAL_USE_CONTRACT_PATH;
            after_directory = changed_after_cells,
        )

        changed_after_manifest =
            copied_fixture(FINAL_USE_AFTER_FIXTURE_DIRECTORY)
        append_newline(joinpath(changed_after_manifest, "manifest.toml"))
        @test_throws ArgumentError build_final_use_envelope(
            FINAL_USE_CONTRACT_PATH;
            after_directory = changed_after_manifest,
        )

        changed_model_mapping =
            copied_file(FINAL_USE_MODEL_MAPPING_PATH)
        append_newline(changed_model_mapping)
        @test_throws ArgumentError build_final_use_envelope(
            FINAL_USE_CONTRACT_PATH;
            model_mapping_path = changed_model_mapping,
        )

        changed_sector_mapping =
            copied_file(FINAL_USE_SECTOR_MAPPING_PATH)
        append_newline(changed_sector_mapping)
        @test_throws ArgumentError build_final_use_envelope(
            FINAL_USE_CONTRACT_PATH;
            sector_mapping_path = changed_sector_mapping,
        )

        changed_valuation_contract =
            copied_file(FINAL_USE_VALUATION_CONTRACT_PATH)
        append_newline(changed_valuation_contract)
        @test_throws ArgumentError build_final_use_envelope(
            FINAL_USE_CONTRACT_PATH;
            valuation_contract_path = changed_valuation_contract,
        )

        source = read(
            joinpath(
                @__DIR__,
                "USAfterRedefinitionsFinalUseEnvelope.jl",
            ),
            String,
        )
        @test !occursin("model_state_write = true", source)
        @test !occursin("forecast_origin_admissible = true", source)
        @test !occursin("promotion_ready = true", source)
        @test !occursin("balance!(", source)
        @test !occursin("clip!(", source)
    end
end
