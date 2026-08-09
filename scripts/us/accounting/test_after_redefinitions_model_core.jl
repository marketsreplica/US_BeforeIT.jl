using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"))

using .USAfterRedefinitionsCommonBasis
using .USAfterRedefinitionsModelCore

const MODEL_CORE_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const MODEL_CORE_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const MODEL_CORE_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const MODEL_CORE_RETAIL_CODES = ["441", "445", "452", "4A0"]

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function independently_aggregate_matrix(
        matrix,
        target_rows,
        target_columns,
        row_mapping,
        column_mapping,
    )
    values = zeros(length(target_rows), length(target_columns))
    explicit = falses(size(values))
    for (target_row_position, target_row_code) in pairs(target_rows)
        source_rows = findall(
            code -> row_mapping[code] == target_row_code,
            matrix.row_codes,
        )
        for (
                target_column_position,
                target_column_code,
            ) in pairs(target_columns)
            source_columns = findall(
                code -> column_mapping[code] == target_column_code,
                matrix.column_codes,
            )
            source_values = matrix.values[source_rows, source_columns]
            source_explicit = matrix.explicit[source_rows, source_columns]
            values[target_row_position, target_column_position] =
                sum(source_values)
            explicit[target_row_position, target_column_position] =
                any(source_explicit)
        end
    end
    return (; values, explicit = BitMatrix(explicit))
end

function independently_aggregate_vector(
        vector,
        source_explicit,
        target_codes,
        mapping,
    )
    values = zeros(length(target_codes))
    explicit = falses(length(target_codes))
    for (target_position, target_code) in pairs(target_codes)
        source_positions =
            findall(code -> mapping[code] == target_code, vector.codes)
        values[target_position] = sum(vector.values[source_positions])
        explicit[target_position] = any(source_explicit[source_positions])
    end
    return (; values, explicit = BitVector(explicit))
end

function maximum_residual_ratio(report, family)
    residuals =
        filter(residual -> residual.family == family, report.residuals)
    return maximum(
        residual.tolerance == 0.0 ?
        (residual.residual == 0.0 ? 0.0 : Inf) :
        abs(residual.residual) / residual.tolerance
            for residual in residuals
    )
end

@testset "BEA after-redefinitions 68-sector model-core aggregation" begin
    fixture =
        load_after_redefinitions_fixture(MODEL_CORE_FIXTURE_DIRECTORY)
    report = build_model_core_aggregation(
        fixture,
        MODEL_CORE_MAPPING_PATH;
        sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
    )
    mapping = TOML.parsefile(MODEL_CORE_MAPPING_PATH)
    sector_mapping = TOML.parsefile(MODEL_CORE_SECTOR_MAPPING_PATH)

    @testset "Pinned mapping and research-only policy" begin
        @test sha256_hex(read(MODEL_CORE_MAPPING_PATH)) ==
            "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c"
        @test sha256_hex(read(MODEL_CORE_SECTOR_MAPPING_PATH)) ==
            "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f"
        @test mapping["schema_version"] ==
            "beforeit-us-after-redefinitions-model-core-mapping.v1"
        @test mapping["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test mapping["promotion_status"] == "RESEARCH_ONLY_NOT_PROMOTED"
        @test mapping["forecast_origin_admissible"] === false
        @test mapping["model_state_write"] === false
        @test mapping["accounting_gate_effect"] == "NONE"
        @test mapping["source_year"] == 2024
        @test mapping["source_price_basis"] == "producers prices"
        @test mapping["common_basis_fixture_sha256"] ==
            fixture.provenance.fixture_sha256
        @test mapping["sector_mapping_sha256"] ==
            sha256_hex(read(MODEL_CORE_SECTOR_MAPPING_PATH))
        @test String.(mapping["model_codes"]) ==
            String.(sector_mapping["model"]["codes"])
        @test length(mapping["model_codes"]) == 68
        @test length(unique(mapping["model_codes"])) == 68

        @test report.year == 2024
        @test report.model_codes == String.(mapping["model_codes"])
        @test report.closure_codes == ["Used", "Other"]
        @test report.source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test report.mapping_sha256 == sha256_hex(read(MODEL_CORE_MAPPING_PATH))
        @test report.sector_mapping_sha256 ==
            sha256_hex(read(MODEL_CORE_SECTOR_MAPPING_PATH))
        @test report.price_basis == :producers_prices
        @test report.transformation ==
            :code_keyed_retail_sum_with_explicit_closure_accounts
        @test report.closure_policy == :used_other_separate_unallocated
        @test report.aggregation_applied
        @test !report.valuation_bridge_applied
        @test !report.balancing_applied
        @test !report.clipping_applied
        @test !report.model_state_write
        @test report.accounting_gate_effect == :none
        @test !report.forecast_origin_admissible
        @test !report.closure.allocation_applied
        @test !report.promotion_ready
        @test length(report.promotion_blockers) == 13
        @test "OTHER_USED_NOT_ALLOCATED_TO_68_SECTOR_CORE" in
            report.promotion_blockers
        @test "IMPORT_ALLOCATION_IS_SEPARATE_IMPUTED_EVIDENCE" in
            report.promotion_blockers
        @test "IMPORT_SIGNED_REALLOCATIONS_EXCLUDING_F050_REQUIRE_REVIEW" in
            report.promotion_blockers
        @test "FINAL_USE_AND_VALUE_ADDED_COMMON_BASIS_NOT_FULLY_RECONCILED" in
            report.promotion_blockers
        @test "LATENT_STATE_RECONCILIATION_NOT_APPLIED" in
            report.promotion_blockers
        @test "CURRENT_VINTAGE_NOT_FORECAST_ORIGIN_ELIGIBLE" in
            report.promotion_blockers

        @test length(report.source_commodity_mapping) == 73
        @test length(report.source_industry_mapping) == 71
        for code in MODEL_CORE_RETAIL_CODES
            @test report.source_commodity_mapping[code] == "4A0"
            @test report.source_industry_mapping[code] == "4A0"
        end
        @test report.source_commodity_mapping["Used"] == "Used"
        @test report.source_commodity_mapping["Other"] == "Other"
        @test !haskey(report.source_industry_mapping, "Used")
        @test !haskey(report.source_industry_mapping, "Other")
        @test all(
            source == target
                for (source, target) in report.source_commodity_mapping
                if source ∉ MODEL_CORE_RETAIL_CODES &&
                    source ∉ report.closure_codes
        )
        @test all(
            source == target
                for (source, target) in report.source_industry_mapping
                if source ∉ MODEL_CORE_RETAIL_CODES
        )
        @test model_core_internal_controls_pass(report)
        @test model_core_controls_pass(
            report,
            fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )
        @test model_core_source_controls_pass(
            report,
            fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )
        @test_throws MethodError model_core_controls_pass(report)
    end

    @testset "Independent code-key aggregation and masks" begin
        model_codes = report.model_codes
        closure_codes = report.closure_codes
        account_codes = vcat(model_codes, closure_codes)
        final_use_codes = fixture.producer_final_use.column_codes
        value_added_codes = fixture.producer_value_added.row_codes
        final_mapping = Dict(code => code for code in final_use_codes)
        value_added_mapping =
            Dict(code => code for code in value_added_codes)

        expected_U = independently_aggregate_matrix(
            fixture.producer_intermediate_use,
            account_codes,
            model_codes,
            report.source_commodity_mapping,
            report.source_industry_mapping,
        )
        expected_F = independently_aggregate_matrix(
            fixture.producer_final_use,
            account_codes,
            final_use_codes,
            report.source_commodity_mapping,
            final_mapping,
        )
        expected_VA = independently_aggregate_matrix(
            fixture.producer_value_added,
            value_added_codes,
            model_codes,
            value_added_mapping,
            report.source_industry_mapping,
        )
        expected_V = independently_aggregate_matrix(
            fixture.producer_make,
            model_codes,
            account_codes,
            report.source_industry_mapping,
            report.source_commodity_mapping,
        )
        expected_import_U = independently_aggregate_matrix(
            fixture.import_intermediate_use,
            account_codes,
            model_codes,
            report.source_commodity_mapping,
            report.source_industry_mapping,
        )
        expected_import_F = independently_aggregate_matrix(
            fixture.import_final_use,
            account_codes,
            final_use_codes,
            report.source_commodity_mapping,
            final_mapping,
        )
        expected_q = independently_aggregate_vector(
            fixture.producer_commodity_output_make,
            BitVector(
                fixture.source_explicit[
                    "producer_make_commodity_output_2024"
                ][:, 1],
            ),
            account_codes,
            report.source_commodity_mapping,
        )
        expected_g = independently_aggregate_vector(
            fixture.producer_industry_output_make,
            BitVector(
                fixture.source_explicit[
                    "producer_make_industry_output_2024"
                ][:, 1],
            ),
            model_codes,
            report.source_industry_mapping,
        )

        @test size(report.producer_intermediate_use) == (68, 68)
        @test size(report.producer_final_use) == (68, 20)
        @test size(report.producer_value_added) == (3, 68)
        @test size(report.producer_make) == (68, 68)
        @test size(report.direct_by_industry) == (68, 68)
        @test size(report.market_shares) == (68, 68)
        @test size(report.product_mix) == (68, 68)
        @test size(report.symmetric_intermediate_use) == (68, 68)
        @test size(report.import_intermediate_use) == (68, 68)
        @test size(report.import_final_use) == (68, 20)
        @test size(report.closure.producer_intermediate_use) == (2, 68)
        @test size(report.closure.producer_final_use) == (2, 20)
        @test size(report.closure.producer_make) == (68, 2)
        @test size(report.source_aggregated_symmetric_use) == (70, 70)
        @test size(report.recomputed_aggregated_symmetric_use) == (70, 70)
        @test size(report.joint_aggregation_commutation_residual) == (70, 70)

        @test vcat(
            report.producer_intermediate_use.values,
            report.closure.producer_intermediate_use.values,
        ) == expected_U.values
        @test vcat(
            report.producer_intermediate_use.explicit,
            report.closure.producer_intermediate_use.explicit,
        ) == expected_U.explicit
        @test vcat(
            report.producer_final_use.values,
            report.closure.producer_final_use.values,
        ) == expected_F.values
        @test vcat(
            report.producer_final_use.explicit,
            report.closure.producer_final_use.explicit,
        ) == expected_F.explicit
        @test report.producer_value_added.values == expected_VA.values
        @test report.producer_value_added.explicit == expected_VA.explicit
        @test hcat(
            report.producer_make.values,
            report.closure.producer_make.values,
        ) == expected_V.values
        @test hcat(
            report.producer_make.explicit,
            report.closure.producer_make.explicit,
        ) == expected_V.explicit
        @test vcat(
            report.import_intermediate_use.values,
            report.closure.import_intermediate_use.values,
        ) == expected_import_U.values
        @test vcat(
            report.import_intermediate_use.explicit,
            report.closure.import_intermediate_use.explicit,
        ) == expected_import_U.explicit
        @test vcat(
            report.import_final_use.values,
            report.closure.import_final_use.values,
        ) == expected_import_F.values
        @test vcat(
            report.import_final_use.explicit,
            report.closure.import_final_use.explicit,
        ) == expected_import_F.explicit
        @test vcat(
            report.commodity_output.values,
            report.closure.commodity_output.values,
        ) == expected_q.values
        @test vcat(
            report.commodity_output_explicit,
            report.closure.commodity_output_explicit,
        ) == expected_q.explicit
        @test report.industry_output.values == expected_g.values
        @test report.industry_output_explicit == expected_g.explicit

        @test sum(expected_U.values) ==
            sum(fixture.producer_intermediate_use.values)
        @test sum(expected_F.values) == sum(fixture.producer_final_use.values)
        @test sum(expected_VA.values) ==
            sum(fixture.producer_value_added.values)
        @test sum(expected_V.values) == sum(fixture.producer_make.values)
        @test sum(expected_import_U.values) ==
            sum(fixture.import_intermediate_use.values)
        @test sum(expected_import_F.values) ==
            sum(fixture.import_final_use.values)
        @test sum(expected_q.values) ==
            sum(fixture.producer_commodity_output_make.values)
        @test sum(expected_g.values) ==
            sum(fixture.producer_industry_output_make.values)

        @test count(report.producer_intermediate_use.explicit) == 3_539
        @test count(report.producer_final_use.explicit) == 332
        @test count(report.producer_make.explicit) == 477
        @test count(report.import_intermediate_use.explicit) == 2_217
        @test count(report.import_final_use.explicit) == 180
        @test count(report.closure.producer_intermediate_use.explicit) == 97
        @test count(report.closure.producer_final_use.explicit) == 16
        @test count(report.closure.producer_make.explicit) == 20
        @test count(report.closure.import_intermediate_use.explicit) == 85
        @test count(report.closure.import_final_use.explicit) == 7

        explicit_zero = findfirst(
            (expected_U.values .== 0.0) .& expected_U.explicit,
        )
        selected_zero = findfirst(
            (expected_U.values .== 0.0) .& .!expected_U.explicit,
        )
        @test !isnothing(explicit_zero)
        @test !isnothing(selected_zero)
        @test expected_U.values[explicit_zero] ==
            expected_U.values[selected_zero] == 0.0
        @test expected_U.explicit[explicit_zero]
        @test !expected_U.explicit[selected_zero]
    end

    @testset "Closure ledger, transformation, and source controls" begin
        model_codes = report.model_codes
        closure_codes = report.closure_codes
        account_codes = vcat(model_codes, closure_codes)
        full_U = vcat(
            report.producer_intermediate_use.values,
            report.closure.producer_intermediate_use.values,
        )
        full_V = hcat(
            report.producer_make.values,
            report.closure.producer_make.values,
        )
        full_product_mix =
            full_V ./ reshape(report.industry_output.values, :, 1)
        independently_recomputed = full_U * full_product_mix

        @test report.direct_by_industry.values ≈
            report.producer_intermediate_use.values ./
            reshape(report.industry_output.values, 1, :) atol = 1.0e-12
        @test report.market_shares.values ≈
            report.producer_make.values ./
            reshape(report.commodity_output.values, 1, :) atol = 1.0e-12
        @test report.product_mix.values ≈
            report.producer_make.values ./
            reshape(report.industry_output.values, :, 1) atol = 1.0e-12
        @test report.recomputed_aggregated_symmetric_use.values ≈
            independently_recomputed atol = 1.0e-8
        @test report.symmetric_intermediate_use.values ≈
            independently_recomputed[1:68, 1:68] atol = 1.0e-8
        @test report.closure.model_input_to_closure_output.values ≈
            independently_recomputed[1:68, 69:70] atol = 1.0e-8
        @test report.closure.closure_input_to_model_output.values ≈
            independently_recomputed[69:70, 1:68] atol = 1.0e-8
        @test report.closure.closure_input_to_closure_output.values ≈
            independently_recomputed[69:70, 69:70] atol = 1.0e-8

        common = build_common_basis_report(fixture)
        @test report.promotion_blockers[2:end] == common.promotion_blockers
        independently_aggregated_source =
            independently_aggregate_matrix(
            common.symmetric_intermediate_use,
            account_codes,
            account_codes,
            report.source_commodity_mapping,
            report.source_commodity_mapping,
        )
        @test report.source_aggregated_symmetric_use.values ≈
            independently_aggregated_source.values atol = 1.0e-8 rtol =
            1.0e-12
        @test report.source_aggregated_symmetric_use.explicit ==
            independently_aggregated_source.explicit
        difference =
            independently_recomputed - independently_aggregated_source.values
        @test report.joint_aggregation_commutation_residual.values ≈
            difference atol = 1.0e-8
        @test report.signed_joint_aggregation_commutation_residual ≈
            sum(difference) atol = 1.0e-12
        @test report.absolute_joint_aggregation_commutation_residual ≈
            sum(abs, difference) atol = 1.0e-12
        @test report.joint_aggregation_commutation_frobenius_residual ≈
            sqrt(sum(abs2, difference)) atol = 1.0e-12
        @test report.source_recomputed_cell_correlation ≈ 1.0 atol =
            1.0e-15
        @test maximum(abs, difference) < 1.0e-6
        @test report.absolute_joint_aggregation_commutation_residual <
            1.0e-6

        for code in MODEL_CORE_RETAIL_CODES
            nonzero_outputs = [
                commodity for commodity in fixture.producer_make.column_codes
                    if fixture.producer_make[code, commodity] != 0.0
            ]
            @test nonzero_outputs == [code]
            @test fixture.producer_make[code, code] ==
                fixture.producer_industry_output_make[code]
        end

        @test sum(report.producer_intermediate_use.values) == 21_165_843.0
        @test sum(report.producer_final_use.values) == 29_550_990.0
        @test sum(report.producer_value_added.values) == 29_298_014.0
        @test sum(report.producer_make.values) == 50_716_812.0
        @test sum(report.commodity_output.values) == 50_716_816.0
        @test sum(report.industry_output.values) == 50_736_554.0
        @test sum(report.import_intermediate_use.values) == 1_776_783.0
        @test sum(report.import_final_use.values) == -1_776_831.0
        @test sum(report.closure.producer_intermediate_use.values) ==
            272_726.0
        @test sum(report.closure.producer_final_use.values) == -252_983.0
        @test sum(report.closure.producer_make.values) == 19_740.0
        @test sum(report.closure.commodity_output.values) == 19_740.0
        @test sum(report.closure.import_intermediate_use.values) == 181_714.0
        @test sum(report.closure.import_final_use.values) == -181_710.0
        @test report.import_role ==
            :separate_bea_imputed_import_allocation
        @test report.import_sign_convention ==
            :positive_allocated_uses_plus_signed_f050_accounting_offset
        @test !report.domestic_use_subtraction_applied
        @test report.import_allocation.import_role == report.import_role
        @test report.import_allocation.sign_convention ==
            report.import_sign_convention
        @test !report.import_allocation.domestic_use_subtraction_applied
        @test report.import_allocation.allocation_excluding_f050_total ==
            3_409_217.0
        @test report.import_allocation.f050_total == -3_409_265.0
        @test report.import_allocation.net_total == -48.0
        @test sum(report.import_allocation.import_f050_offset.values) ==
            report.import_allocation.f050_total
        @test report.closure.import_allocation.import_role ==
            report.import_role
        @test report.closure.import_allocation.sign_convention ==
            report.import_sign_convention
        @test !report.closure.import_allocation.domestic_use_subtraction_applied
        @test report.closure.import_allocation.allocation_excluding_f050_total ==
            386_653.0
        @test report.closure.import_allocation.f050_total == -386_649.0
        @test report.closure.import_allocation.net_total == 4.0
        @test report.import_allocation.allocation_excluding_f050_total +
            report.closure.import_allocation.allocation_excluding_f050_total ==
            3_795_870.0
        @test report.import_allocation.f050_total +
            report.closure.import_allocation.f050_total == -3_795_914.0
        @test report.import_allocation.net_total +
            report.closure.import_allocation.net_total == -44.0
        @test report.closure.commodity_output["Used"] == 13_553.0
        @test report.closure.commodity_output["Other"] == 6_187.0
        @test report.commodity_output["4A0"] == 2_716_290.0
        @test report.industry_output["4A0"] == 2_708_018.0

        @test length(report.negative_intermediate_cells) == 0
        @test length(report.negative_make_cells) == 1
        @test length(report.negative_symmetric_cells) == 0
        @test length(report.import_allocation.negative_cells) == 56
        @test length(report.import_allocation.negative_f050_cells) == 46
        @test length(report.import_allocation.negative_allocation_cells) == 10
        @test length(report.closure.negative_intermediate_cells) == 5
        @test length(report.closure.negative_make_cells) == 0
        @test length(report.closure.negative_symmetric_cells) == 6
        @test length(report.closure.import_allocation.negative_cells) == 2
        @test length(
            report.closure.import_allocation.negative_f050_cells,
        ) == 2
        @test isempty(
            report.closure.import_allocation.negative_allocation_cells,
        )
        @test length(report.import_allocation.negative_cells) +
            length(report.closure.import_allocation.negative_cells) == 58
        @test length(report.import_allocation.negative_f050_cells) +
            length(report.closure.import_allocation.negative_f050_cells) == 48
        @test length(report.import_allocation.negative_allocation_cells) +
            length(
                report.closure.import_allocation.negative_allocation_cells,
            ) == 10

        @test length(report.residuals) == 494
        @test all(residual.passed for residual in report.residuals)
        @test count(
            residual ->
                residual.family ==
                :model_core_joint_aggregation_commutation,
            report.residuals,
        ) == 1
        @test maximum_residual_ratio(
            report,
            :model_core_commodity_use_output_control,
        ) ≈ 0.13043478260869565
        @test maximum_residual_ratio(
            report,
            :model_core_import_offset_control,
        ) ≈ 0.15384615384615385
        @test maximum_residual_ratio(
            report,
            :model_core_industry_use_output_control,
        ) ≈ 0.15584415584415584
    end

    @testset "Stale reports and contract changes fail closed" begin
        balanced_cycle_fixture = deepcopy(fixture)
        balanced_cycle_fixture.producer_intermediate_use.values[1, 1] +=
            100.0
        balanced_cycle_fixture.producer_intermediate_use.values[1, 2] -=
            100.0
        balanced_cycle_fixture.producer_intermediate_use.values[2, 1] -=
            100.0
        balanced_cycle_fixture.producer_intermediate_use.values[2, 2] +=
            100.0
        @test sum(
            balanced_cycle_fixture.producer_intermediate_use.values;
            dims = 1,
        ) == sum(fixture.producer_intermediate_use.values; dims = 1)
        @test sum(
            balanced_cycle_fixture.producer_intermediate_use.values;
            dims = 2,
        ) == sum(fixture.producer_intermediate_use.values; dims = 2)
        @test_throws ArgumentError build_model_core_aggregation(
            balanced_cycle_fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )
        @test !model_core_source_controls_pass(
            report,
            balanced_cycle_fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )

        stale_direct = deepcopy(report)
        stale_direct.direct_by_industry.values[1, 1] += 1.0e-3
        @test !model_core_internal_controls_pass(stale_direct)

        stale_final = deepcopy(report)
        stale_final.producer_final_use.values[1, 1] += 1_000.0
        @test !model_core_internal_controls_pass(stale_final)

        stale_value_added = deepcopy(report)
        stale_value_added.producer_value_added.values[1, 1] += 1_000.0
        @test !model_core_internal_controls_pass(stale_value_added)

        stale_import = deepcopy(report)
        stale_import.import_final_use.values[1, 1] += 1_000.0
        @test !model_core_internal_controls_pass(stale_import)

        stale_import_ledger = deepcopy(report)
        stale_import_ledger.import_allocation.import_f050_offset.values[1] +=
            1.0
        @test !model_core_internal_controls_pass(stale_import_ledger)

        stale_closure_block = deepcopy(report)
        stale_closure_block.closure.model_input_to_closure_output.values[
            1,
            1,
        ] += 1.0
        @test !model_core_internal_controls_pass(stale_closure_block)

        stale_source_symmetric = deepcopy(report)
        stale_source_symmetric.source_aggregated_symmetric_use.values[
            1,
            1,
        ] += 1.0
        @test !model_core_internal_controls_pass(stale_source_symmetric)

        stale_difference = deepcopy(report)
        stale_difference.joint_aggregation_commutation_residual.values[
            1,
            1,
        ] += 1.0
        @test !model_core_internal_controls_pass(stale_difference)

        stale_negatives = deepcopy(report)
        empty!(stale_negatives.negative_make_cells)
        @test !model_core_internal_controls_pass(stale_negatives)

        stale_residuals = deepcopy(report)
        pop!(stale_residuals.residuals)
        @test !model_core_internal_controls_pass(stale_residuals)

        compensated_final = deepcopy(report)
        compensated_final.producer_final_use.values[1, 1] += 1.0
        compensated_final.producer_final_use.values[1, 2] -= 1.0
        @test !model_core_source_controls_pass(
            compensated_final,
            fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )

        stale_mask = deepcopy(report)
        stale_mask.producer_intermediate_use.explicit[1, 1] =
            !stale_mask.producer_intermediate_use.explicit[1, 1]
        @test !model_core_source_controls_pass(
            stale_mask,
            fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )

        stale_output_mask = deepcopy(report)
        stale_output_mask.commodity_output_explicit[1] =
            !stale_output_mask.commodity_output_explicit[1]
        @test model_core_internal_controls_pass(stale_output_mask)
        @test !model_core_controls_pass(
            stale_output_mask,
            fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )

        stale_mapping = deepcopy(report)
        stale_mapping.source_commodity_mapping["441"] = "441"
        @test !model_core_internal_controls_pass(stale_mapping)
        @test !model_core_source_controls_pass(
            stale_mapping,
            fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )

        changed_mapping_directory = mktempdir()
        changed_mapping_path =
            joinpath(changed_mapping_directory, "mapping.toml")
        cp(MODEL_CORE_MAPPING_PATH, changed_mapping_path)
        open(changed_mapping_path, "a") do io
            write(io, "\n")
        end
        @test_throws ArgumentError build_model_core_aggregation(
            fixture,
            changed_mapping_path;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )
        @test !model_core_source_controls_pass(
            report,
            fixture,
            changed_mapping_path;
            sector_mapping_path = MODEL_CORE_SECTOR_MAPPING_PATH,
        )

        changed_sector_mapping_path =
            joinpath(changed_mapping_directory, "bea71.toml")
        cp(MODEL_CORE_SECTOR_MAPPING_PATH, changed_sector_mapping_path)
        open(changed_sector_mapping_path, "a") do io
            write(io, "\n")
        end
        @test_throws ArgumentError build_model_core_aggregation(
            fixture,
            MODEL_CORE_MAPPING_PATH;
            sector_mapping_path = changed_sector_mapping_path,
        )

        source = read(
            joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"),
            String,
        )
        @test !occursin("model_state_write = true", source)
        @test !occursin("forecast_origin_admissible = true", source)
        @test !occursin("promotion_ready = true", source)
        @test !occursin("balance!(", source)
        @test !occursin("clip!(", source)
    end
end
