using LinearAlgebra
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(
    joinpath(
        @__DIR__,
        "USAfterRedefinitionsAggregateFirstScrapAdjustedDiagnostic.jl",
    ),
)

using .USAfterRedefinitionsAggregateFirstScrapAdjustedDiagnostic
using .USAfterRedefinitionsCommonBasis: FinalUseBasis
using .USRequirementsDiagnostics: load_official_direct_requirements_fixture
using .USSupplyMakeDiagnostics:
    CommodityBasis,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector

const SCRAP68_CONTRACT_PATH = joinpath(
    @__DIR__,
    "after_redefinitions_aggregate_first_scrap_adjusted_diagnostic.toml",
)
const SCRAP68_AFTER_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const SCRAP68_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const SCRAP68_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const SCRAP68_CLOSURE_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_closure_boundary_candidate.toml")
const SCRAP68_METHODOLOGY_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_io_concepts_methods_2006_approved",
)
const SCRAP68_METHODOLOGY_PDF_PATH = joinpath(
    SCRAP68_METHODOLOGY_DIRECTORY,
    "Concepts_and_Methods_US_IO_Accounts_2006.pdf",
)
const SCRAP68_METHODOLOGY_RECEIPT_PATH =
    joinpath(SCRAP68_METHODOLOGY_DIRECTORY, "receipt.toml")
const SCRAP68_OFFICIAL_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_official_direct_requirements_approved",
)

const SCRAP68_BLOCKERS = [
    "AGGREGATE_FIRST_68_SCRAP_ADJUSTED_DIAGNOSTIC_ONLY",
    "SAME_TABLE_MARKET_SHARE_NOT_BEA_PUBLISHED_D",
    "AGGREGATE_FIRST_AND_SOURCE_FIRST_TRANSFORMED_FLOWS_DO_NOT_COMMUTE",
    "RETAIL_WITHIN_AGGREGATE_COMPOSITION_NOT_MODELED",
    "PUBLISHED_CURRENT_DOLLAR_ROUNDING_RESIDUALS_RETAINED",
    "NEGATIVE_MAKE_DERIVED_MARKET_SHARE_CELL_POLICY_NOT_APPROVED",
    "USED_ASSET_TRANSFER_AND_NEGATIVE_FLOW_SEMANTICS_NOT_MAPPED",
    "OTHER_COMPOSITE_NOT_SPLIT_NONCOMPARABLE_IMPORTS_VS_ROW_ADJUSTMENT",
    "OTHER_OUTPUT_TERM_HAS_NO_ADMISSIBLE_DOMESTIC_OR_ROTW_BOUNDARY",
    "OTHER_NONCOMPARABLE_IMPORT_FINANCIAL_COUNTERPART_NOT_MAPPED_TO_ROTW",
    "ROW_ADJUSTMENT_COMPONENTS_AND_ACCOUNTING_COUNTERPARTS_NOT_IDENTIFIED",
    "SIGNED_FINAL_USE_COMPONENTS_NOT_BEHAVIORALLY_DECOMPOSED",
    "CLOSURE_CURRENT_DOLLAR_PRICE_QUANTITY_DECOMPOSITION_NOT_IDENTIFIED",
    "CLOSURE_QUARTERLY_DYNAMIC_LAW_NOT_ESTIMATED",
    "CLOSURE_CORE_INPUT_COST_AND_PRODUCTION_CONSTRAINT_BOUNDARY_NOT_SELECTED",
    "CLOSURE_DOUBLE_ENTRY_AND_BANK_IDENTITIES_NOT_TRANSITION_TESTED",
    "INDUSTRY_COMMODITY_RUNTIME_TRANSFORMATION_NOT_SELECTED",
    "AGGREGATE_FIRST_TRANSFORM_NOT_VALIDATED_ACROSS_ORIGIN_VINTAGES",
    "CURRENT_VINTAGE_NOT_FORECAST_ORIGIN_ELIGIBLE",
]

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function copied_file(source_path)
    target = joinpath(mktempdir(), basename(source_path))
    cp(source_path, target)
    return target
end

function copied_fixture(source_directory)
    target = mktempdir()
    for filename in ("cells.csv", "manifest.toml")
        cp(joinpath(source_directory, filename), joinpath(target, filename))
    end
    return target
end

function append_one_byte(path)
    open(path, "a") do io
        write(io, UInt8('\n'))
    end
    return path
end

function build_report()
    return build_aggregate_first_scrap_adjusted_diagnostic(
        SCRAP68_CONTRACT_PATH;
        after_directory = SCRAP68_AFTER_DIRECTORY,
        model_mapping_path = SCRAP68_MODEL_MAPPING_PATH,
        sector_mapping_path = SCRAP68_SECTOR_MAPPING_PATH,
        closure_boundary_contract_path = SCRAP68_CLOSURE_CONTRACT_PATH,
        methodology_pdf_path = SCRAP68_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = SCRAP68_METHODOLOGY_RECEIPT_PATH,
    )
end

function source_controls_pass(report; kwargs...)
    return aggregate_first_scrap_adjusted_diagnostic_controls_pass(
        report,
        SCRAP68_CONTRACT_PATH;
        after_directory = SCRAP68_AFTER_DIRECTORY,
        model_mapping_path = SCRAP68_MODEL_MAPPING_PATH,
        sector_mapping_path = SCRAP68_SECTOR_MAPPING_PATH,
        closure_boundary_contract_path = SCRAP68_CLOSURE_CONTRACT_PATH,
        methodology_pdf_path = SCRAP68_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = SCRAP68_METHODOLOGY_RECEIPT_PATH,
        kwargs...,
    )
end

function family_counts(residuals)
    counts = Dict{Symbol, Int}()
    for residual in residuals
        counts[residual.family] =
            get(counts, residual.family, 0) + 1
    end
    return counts
end

@testset "aggregate-first 68-sector scrap-adjusted diagnostic" begin
    report = build_report()
    contract = TOML.parsefile(SCRAP68_CONTRACT_PATH)

    @testset "byte-pinned same-table and methodology contract" begin
        pinned_files = [
            (
                SCRAP68_CONTRACT_PATH,
                "5248278e3dac6d8ff262d0c3eeffa819819b1b619f15f352c8557764c4523c26",
            ),
            (
                joinpath(SCRAP68_AFTER_DIRECTORY, "cells.csv"),
                "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac",
            ),
            (
                joinpath(SCRAP68_AFTER_DIRECTORY, "manifest.toml"),
                "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030",
            ),
            (
                SCRAP68_MODEL_MAPPING_PATH,
                "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c",
            ),
            (
                SCRAP68_SECTOR_MAPPING_PATH,
                "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f",
            ),
            (
                SCRAP68_CLOSURE_CONTRACT_PATH,
                "ad6f1995575b1fa612577eb4001e9163159d6802fa947d6f5385a2d07758172f",
            ),
            (
                SCRAP68_METHODOLOGY_PDF_PATH,
                "535627e5e44f8461c0a04410f4a05c55d47f2e325d9473cb2df06e5d3e6b271d",
            ),
            (
                SCRAP68_METHODOLOGY_RECEIPT_PATH,
                "b4b210be3c364415473f1ef407ed7ea6e9edc2b299bd1058c1658b0ebb3b91ac",
            ),
        ]
        for (path, expected_sha256) in pinned_files
            @test sha256_hex(read(path)) == expected_sha256
        end
        @test contract["schema_version"] ==
            "beforeit-us-after-redefinitions-aggregate-first-scrap-adjusted-diagnostic.v1"
        @test contract["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract["artifact_role"] ==
            "AGGREGATE_FIRST_68_SCRAP_ADJUSTED_DIAGNOSTIC_ONLY"
        @test contract["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test Int.(contract["diagnostic_additional_methodology_pdf_pages"]) ==
            [213]
        @test contract["same_table_market_share_definition"] ==
            "D68=(A*Vcore*A')*diag(A*qcore)^-1"
        @test contract["same_table_source_policy"] ==
            "ONLY_PINNED_AFTER_REDEFINITIONS_V_U_F_Q_G"
        @test contract["official_cross_archive_d_policy"] ==
            "FORBIDDEN_NOT_LOADED_NOT_ACCEPTED"
        @test contract["final_use_policy"] == "ALL_20_SIGNED_COLUMNS"
        @test contract["aggregation_order"] ==
            "AGGREGATE_LEVELS_BEFORE_RATIOS_AND_W"
        @test contract["source_first_comparison_policy"] ==
            "Q_COMPOSITION_WEIGHTED_COEFFICIENTS_PLUS_FLOW_LEVEL_NONCOMMUTATION"
        @test contract["coefficient_comparator_scope"] ==
            "CURRENT_TABLE_NUMERICAL_WITNESS_NOT_A_GENERAL_AGGREGATION_IDENTITY"
        @test contract["other_term_role"] ==
            "ARITHMETIC_OMISSION_WITNESS_ONLY"
        @test contract["used_make_component_policy"] ==
            "H_IS_THE_MAKE_SIDE_SCRAP_COMPONENT_OF_COMPOSITE_USED_NOT_THE_USED_USE_OR_FINAL_ASSET_TRANSFER_ROWS"
        @test contract["other_make_component_policy"] ==
            "O_AND_T_OTHER_ARE_MAKE_SIDE_ARITHMETIC_CLOSURE_WITNESSES_NOT_ALLOCATIONS_OF_OTHER_USE_OR_FINAL_ROWS"
        @test contract["special_use_exclusion_policy"] ==
            "USED_AND_OTHER_USE_AND_FINAL_ROWS_EXCLUDED_FROM_U68_AND_E68_AND_RETAINED_IN_THE_CLOSURE_BOUNDARY_SIDECAR"
        @test contract["raw_unweighted_w_shortcut_policy"] ==
            "EXPLICITLY_REJECTED"
        @test String.(contract["promotion_blockers"]) ==
            SCRAP68_BLOCKERS
        @test isempty(contract["emitted_runtime_keys"])
        @test contract["aggregate_first_diagnostic"] === true
        for key in (
                "runtime_transform_selected",
                "apply_to_runtime_u",
                "apply_to_runtime_a",
                "apply_to_runtime_beta",
                "raw_unweighted_w_shortcut_accepted",
                "other_boundary_selected",
                "current_dollar_price_quantity_decomposition",
                "quarterly_dynamic_law",
                "financial_counterpart_mapping",
                "row_adjustment_observation_operator",
                "double_entry_transition_tests",
                "runtime_calibration_admissible",
                "calibration_dictionary_write",
                "figaro_dictionary_write",
                "parameter_write",
                "initial_conditions_write",
                "model_state_write",
                "forecast_origin_admissible",
                "promotion_ready",
                "balancing_applied",
                "clipping_applied",
                "normalization_applied",
                "raking_applied",
            )
            @test contract[key] === false
        end
        @test contract["accounting_gate_effect"] == "NONE"

        byte_pins = contract["byte_pins"]
        after_manifest = TOML.parsefile(
            joinpath(SCRAP68_AFTER_DIRECTORY, "manifest.toml"),
        )
        for (manifest_key, pin_key) in (
                (
                    "source_zip_sha256",
                    "after_redefinitions_source_zip_sha256",
                ),
                (
                    "source_metadata_sha256",
                    "after_redefinitions_source_metadata_sha256",
                ),
                (
                    "producer_use_workbook_sha256",
                    "after_redefinitions_producer_use_workbook_sha256",
                ),
                (
                    "producer_make_workbook_sha256",
                    "after_redefinitions_producer_make_workbook_sha256",
                ),
            )
            @test after_manifest[manifest_key] == byte_pins[pin_key]
        end
        @test byte_pins["closure_boundary_contract_sha256"] ==
            sha256_hex(read(SCRAP68_CLOSURE_CONTRACT_PATH))
        @test byte_pins["methodology_pdf_sha256"] ==
            sha256_hex(read(SCRAP68_METHODOLOGY_PDF_PATH))
        @test report.byte_pins ==
            Dict(String(key) => String(value) for (key, value) in byte_pins)
    end

    @testset "typed source levels and independent direct-loop aggregation" begin
        @test report.year == 2024
        @test length(report.source_codes) == 71
        @test length(report.model_codes) == 68
        @test length(report.final_use_codes) == 20
        @test report.industry_aggregation isa
            LabeledMatrix{IndustryBasis, IndustryBasis}
        @test report.commodity_aggregation isa
            LabeledMatrix{CommodityBasis, CommodityBasis}
        @test report.source_intermediate_use isa
            LabeledMatrix{CommodityBasis, IndustryBasis}
        @test report.source_final_use isa
            LabeledMatrix{CommodityBasis, FinalUseBasis}
        @test report.source_make isa
            LabeledMatrix{IndustryBasis, CommodityBasis}
        @test report.source_commodity_output isa
            LabeledVector{CommodityBasis}
        @test report.source_industry_output isa
            LabeledVector{IndustryBasis}
        @test report.source_scrap_output isa LabeledVector{IndustryBasis}
        @test report.source_other_output isa LabeledVector{IndustryBasis}
        @test size(report.industry_aggregation) == (68, 71)
        @test size(report.source_intermediate_use) == (71, 71)
        @test size(report.source_final_use) == (71, 20)
        @test size(report.source_make) == (71, 71)
        @test all(
            value == 0.0 || value == 1.0
                for value in report.industry_aggregation.values
        )
        @test all(
            sum(report.industry_aggregation.values; dims = 1) .== 1.0,
        )
        @test count(==(1.0), report.industry_aggregation.values) == 71
        @test report.industry_aggregation.values ==
            report.commodity_aggregation.values
        @test !any(report.industry_aggregation.explicit)
        @test !any(report.commodity_aggregation.explicit)
        @test report.source_industry_mapping["441"] == "4A0"
        @test report.source_industry_mapping["445"] == "4A0"
        @test report.source_industry_mapping["452"] == "4A0"
        @test report.source_industry_mapping["4A0"] == "4A0"

        model_index = Dict(
            code => position
                for (position, code) in pairs(report.model_codes)
        )
        loop_U = zeros(68, 68)
        loop_F = zeros(68, 20)
        loop_V = zeros(68, 68)
        loop_q = zeros(68)
        loop_g = zeros(68)
        loop_h = zeros(68)
        loop_o = zeros(68)
        for (source_row, source_code) in pairs(report.source_codes)
            target_row =
                model_index[report.source_industry_mapping[source_code]]
            loop_q[target_row] +=
                report.source_commodity_output.values[source_row]
            loop_g[target_row] +=
                report.source_industry_output.values[source_row]
            loop_h[target_row] +=
                report.source_scrap_output.values[source_row]
            loop_o[target_row] +=
                report.source_other_output.values[source_row]
            for final_position in eachindex(report.final_use_codes)
                loop_F[target_row, final_position] +=
                    report.source_final_use.values[
                    source_row,
                    final_position,
                ]
            end
            for (source_column, source_column_code) in
                pairs(report.source_codes)
                target_column = model_index[
                    report.source_industry_mapping[source_column_code],
                ]
                loop_U[target_row, target_column] +=
                    report.source_intermediate_use.values[
                    source_row,
                    source_column,
                ]
                loop_V[target_row, target_column] +=
                    report.source_make.values[
                    source_row,
                    source_column,
                ]
            end
        end
        @test report.aggregate_intermediate_use.values == loop_U
        @test report.aggregate_final_use.values == loop_F
        @test report.aggregate_make.values == loop_V
        @test report.aggregate_commodity_output.values == loop_q
        @test report.aggregate_industry_output.values == loop_g
        @test report.aggregate_scrap_output.values == loop_h
        @test report.aggregate_other_output.values == loop_o
        @test sum(loop_U) == 21_165_843.0
        @test sum(loop_F) == 29_550_990.0
        @test sum(loop_V) == 50_716_812.0
        @test sum(loop_q) == 50_716_816.0
        @test sum(loop_g) == 50_736_554.0
        @test sum(loop_h) == 13_553.0
        @test sum(loop_o) == 6_187.0
        @test count(>(0.0), loop_h) == 14
        @test count(!iszero, loop_o) == 1
        @test loop_o[model_index["GFGN"]] == 6_187.0

        for matrix in (
                report.aggregate_intermediate_use,
                report.aggregate_final_use,
                report.aggregate_make,
                report.input_coefficients,
                report.market_shares,
                report.nonscrap_transform,
                report.requirements,
                report.leontief_inverse,
            )
            @test !any(matrix.explicit)
        end
        @test all(
            mask == falses(68)
                for mask in values(report.derived_vector_explicit)
        )
    end

    @testset "aggregate-first B, D, p, W, H, and source comparator" begin
        U = report.aggregate_intermediate_use.values
        V = report.aggregate_make.values
        q = report.aggregate_commodity_output.values
        g = report.aggregate_industry_output.values
        h = report.aggregate_scrap_output.values
        A = report.industry_aggregation.values
        B = report.input_coefficients.values
        D = report.market_shares.values
        p = report.scrap_shares.values
        W = report.nonscrap_transform.values
        H = report.requirements.values
        nonscrap_operator =
            Matrix{Float64}(I, 68, 68) - Diagonal(p)

        @test B == U * Diagonal(1.0 ./ g)
        @test D == V * Diagonal(1.0 ./ q)
        @test p == h ./ g
        @test report.nonscrap_ratios.values == 1.0 .- p
        @test isapprox(
            W,
            nonscrap_operator \ D;
            atol = 1.0e-13,
            rtol = 0.0,
        )
        @test H == B * W
        @test report.final_demand.values ==
            vec(sum(report.aggregate_final_use.values; dims = 2))
        @test maximum(p) == 0.008175911954472797
        @test report.scrap_shares.codes[argmax(p)] == "332"
        @test minimum(report.nonscrap_ratios.values) ==
            0.9918240880455272
        @test isapprox(cond(nonscrap_operator), 1.008243308519139; atol = 1.0e-10)
        @test isapprox(sum(D), 67.99993136621207; atol = 1.0e-10)
        @test isapprox(sum(W), 68.02964492856546; atol = 1.0e-10)
        @test isapprox(sum(B), 30.95969934849524; atol = 1.0e-10)
        @test isapprox(sum(H), 31.15992380781542; atol = 1.0e-10)
        @test isapprox(maximum(W), 1.0018547305266363; atol = 1.0e-11)
        @test isapprox(maximum(H), 0.5808078341748951; atol = 1.0e-11)

        column_residuals = abs.(vec(sum(D; dims = 1)) .- 1.0)
        @test isapprox(
            maximum(column_residuals),
            4.046944556856946e-5;
            atol = 1.0e-10,
        )
        @test report.model_codes[argmax(column_residuals)] == "315AL"

        coefficients = report.coefficients
        Cq = coefficients.q_composition_weights.values
        @test coefficients.comparator_scope ==
            :current_table_conditional_not_general_identity
        @test coefficients.merged_source_codes ==
            ["441", "445", "452", "4A0"]
        @test coefficients.merged_zero_scrap_output
        @test coefficients.merged_zero_other_output
        @test coefficients.merged_own_commodity_make_only
        @test coefficients.merged_own_make_equals_industry_output
        @test size(Cq) == (71, 68)
        @test all(Cq .>= 0.0)
        @test maximum(
            abs.(vec(sum(Cq; dims = 1)) .- ones(68)),
        ) <= 2.0e-16
        @test coefficients.conditional_current_table_aggregate_w.values ==
            A * coefficients.source_nonscrap_transform.values * Cq
        @test coefficients.conditional_current_table_aggregate_h.values ==
            A * coefficients.source_requirements.values * Cq
        @test coefficients.conditional_current_table_w_ledger.absolute_total <=
            5.0e-11
        @test coefficients.conditional_current_table_w_ledger.maximum_absolute_difference <=
            2.0e-12
        @test coefficients.conditional_current_table_h_ledger.absolute_total <=
            5.0e-11
        @test coefficients.conditional_current_table_h_ledger.maximum_absolute_difference <=
            2.0e-12
        @test coefficients.conditional_current_table_w_ledger.material_cell_count ==
            0
        @test coefficients.conditional_current_table_h_ledger.material_cell_count ==
            0

        raw = coefficients.raw_unweighted_w_ledger
        @test coefficients.raw_unweighted_w_shortcut.values ==
            A * coefficients.source_nonscrap_transform.values *
            transpose(A)
        @test isapprox(raw.signed_total, -2.99999974604394; atol = 1.0e-12)
        @test isapprox(raw.absolute_total, 2.99999974604394; atol = 1.0e-12)
        @test raw.maximum_row_code == "4A0"
        @test raw.maximum_column_code == "4A0"
        @test isapprox(
            raw.value_at_maximum,
            -2.97816614434223;
            atol = 1.0e-12,
        )
        @test !coefficients.raw_unweighted_w_shortcut_accepted

        q_composition_output =
            coefficients.q_composition_weights.values * q
        @test isapprox(
            W * q -
                A * coefficients.source_nonscrap_transform.values *
                report.source_commodity_output.values,
            zeros(68);
            atol = 2.0e-10,
            rtol = 0.0,
        )
        @test maximum(
            abs.(
                q_composition_output -
                    report.source_commodity_output.values
            ),
        ) <= 5.0e-10
    end

    @testset "published identity residuals remain separate from formula FP" begin
        identities = report.identities
        make = identities.make_source_summary
        d_formula = identities.market_share_formula_summary
        d_fp = identities.market_share_minus_make_fp_summary
        w_formula = identities.nonscrap_formula_summary
        w_fp = identities.nonscrap_minus_make_propagation_fp_summary
        use = identities.use_source_summary
        b_formula = identities.input_coefficient_formula_summary
        b_fp = identities.input_coefficient_minus_use_fp_summary

        @test make.signed_total == -2.0
        @test make.absolute_total == 30.0
        @test make.maximum_absolute_residual == 3.0
        @test make.maximum_residual_code == "332"
        @test make.nonzero_count == 25
        @test isapprox(d_formula.signed_total, -2.000000000167347; atol = 1.0e-8)
        @test isapprox(d_formula.absolute_total, 30.00000000048749; atol = 1.0e-8)
        @test d_fp.absolute_total <= 2.0e-9
        @test isapprox(
            d_fp.maximum_absolute_residual,
            2.3283064365386963e-10;
            atol = 3.0e-10,
            rtol = 0.0,
        )
        @test isapprox(w_formula.signed_total, 1.9730748415822745; atol = 1.0e-8)
        @test isapprox(w_formula.absolute_total, 30.04198597046343; atol = 1.0e-8)
        @test isapprox(
            w_formula.maximum_absolute_residual,
            3.024729925498832;
            atol = 1.0e-8,
        )
        @test w_formula.maximum_residual_code == "332"
        @test w_formula.maximum_residual_value < 0.0
        @test isapprox(
            w_fp.maximum_absolute_residual,
            2.433555579273161e-10;
            atol = 3.0e-10,
            rtol = 0.0,
        )
        @test use.signed_total == -17.0
        @test use.absolute_total == 121.0
        @test use.maximum_absolute_residual == 7.0
        @test use.maximum_residual_code == "4A0"
        @test use.nonzero_count == 55
        @test isapprox(b_formula.signed_total, -17.00000000005821; atol = 1.0e-8)
        @test isapprox(b_formula.absolute_total, 121.0000000000582; atol = 1.0e-8)
        @test b_fp.absolute_total <= 6.0e-11

        p = report.scrap_shares.values
        nonscrap_operator =
            Matrix{Float64}(I, 68, 68) - Diagonal(p)
        @test maximum(
            abs.(
                identities.nonscrap_formula_residual.values +
                    (
                    nonscrap_operator \
                        identities.make_source_residual.values
                )
            ),
        ) <= 3.0e-10
        @test report.aggregate_other_output.values ==
            nonscrap_operator \ report.aggregate_other_output.values
    end

    @testset "transformed-flow noncommutation is explicit" begin
        flows = report.flows
        Z = flows.intermediate_difference_ledger
        Y = flows.final_use_difference_ledger
        row = flows.combined_row_difference_summary
        @test flows.aggregate_first_intermediate.values ==
            report.nonscrap_transform.values *
            report.aggregate_intermediate_use.values
        @test flows.aggregate_first_final_use.values ==
            report.nonscrap_transform.values *
            report.aggregate_final_use.values
        @test flows.intermediate_difference.values ==
            flows.aggregate_first_intermediate.values -
            flows.source_first_intermediate.values
        @test flows.final_use_difference.values ==
            flows.aggregate_first_final_use.values -
            flows.source_first_final_use.values
        @test isapprox(Z.signed_total, 0.02527699166531; atol = 1.0e-7)
        @test isapprox(Z.absolute_total, 1_151.302692026168; atol = 1.0e-6)
        @test isapprox(Z.frobenius_norm, 480.551718086236; atol = 1.0e-6)
        @test isapprox(Z.maximum_absolute_difference, 334.442360239453; atol = 1.0e-6)
        @test Z.maximum_row_code == "4A0"
        @test Z.maximum_column_code == "23"
        @test Z.value_at_maximum < 0.0
        @test Z.material_cell_count == 264
        @test isapprox(Z.relative_absolute_total, 5.437563701735044e-5; atol = 1.0e-12)
        @test isapprox(Y.signed_total, -0.02527441486032; atol = 1.0e-7)
        @test isapprox(Y.absolute_total, 2_562.397923892939; atol = 1.0e-6)
        @test isapprox(Y.frobenius_norm, 1_356.748888872956; atol = 1.0e-6)
        @test isapprox(Y.maximum_absolute_difference, 921.581348184962; atol = 1.0e-6)
        @test Y.maximum_row_code == "4A0"
        @test Y.maximum_column_code == "F010"
        @test Y.value_at_maximum > 0.0
        @test Y.material_cell_count == 16
        @test isapprox(Y.relative_absolute_total, 7.043699124562336e-5; atol = 1.0e-12)
        @test isapprox(row.signed_total, 2.576805008713129e-6; atol = 1.0e-9)
        @test isapprox(row.absolute_total, 0.05688487550054; atol = 1.0e-9)
        @test isapprox(row.maximum_absolute_residual, 0.02843857184666; atol = 1.0e-9)
        @test row.maximum_residual_code == "4A0"

        for signs in (
                flows.aggregate_first_intermediate_signs,
                flows.source_first_intermediate_signs,
            )
            @test signs.negative_count == 68
            @test isapprox(signs.negative_total, -4.964339867897825; atol = 1.0e-9)
            @test isapprox(signs.minimum, -0.473641491578577; atol = 1.0e-12)
        end
        for signs in (
                flows.aggregate_first_final_use_signs,
                flows.source_first_final_use_signs,
            )
            @test signs.negative_count == 62
            @test isapprox(signs.negative_total, -3_410_662.857507384; atol = 1.0e-6)
            @test isapprox(signs.minimum, -447_562.788034044; atol = 1.0e-6)
        end
    end

    @testset "Other omission, adjusted equation, stability, and signs" begin
        other = report.other
        @test isapprox(other.omission_summary.signed_total, 1_895.838353566262; atol = 1.0e-6)
        @test isapprox(other.omission_summary.absolute_total, 1_927.472872337382; atol = 1.0e-6)
        @test isapprox(other.omission_summary.maximum_absolute_residual, 208.482359154033; atol = 1.0e-6)
        @test other.omission_summary.maximum_residual_code == "521CI"
        @test other.arithmetic_output_term_signs.negative_count == 0
        @test isapprox(other.arithmetic_output_term_signs.total, 1_910.444720304135; atol = 1.0e-6)
        @test isapprox(other.arithmetic_output_term_signs.maximum, 207.59896035379; atol = 1.0e-6)
        @test report.other.arithmetic_output_term.codes[
            argmax(report.other.arithmetic_output_term.values),
        ] == "521CI"
        @test isapprox(other.adjusted_equation_summary.signed_total, -14.606366737874; atol = 1.0e-6)
        @test isapprox(other.adjusted_equation_summary.absolute_total, 120.329989078666; atol = 1.0e-6)
        @test isapprox(other.adjusted_equation_summary.maximum_absolute_residual, 7.024382279905; atol = 1.0e-6)
        @test other.adjusted_equation_summary.maximum_residual_code == "4A0"
        @test isapprox(other.no_other_solution_summary.signed_total, 3_264.838451893080; atol = 1.0e-6)
        @test isapprox(other.no_other_solution_summary.absolute_total, 3_271.385407675950; atol = 1.0e-6)
        @test other.no_other_solution_summary.maximum_residual_code == "5412OP"
        @test isapprox(other.arithmetic_other_solution_summary.signed_total, -33.16731505423; atol = 1.0e-6)
        @test isapprox(other.arithmetic_other_solution_summary.absolute_total, 138.958125724206; atol = 1.0e-6)
        @test other.arithmetic_other_solution_summary.maximum_residual_code == "331"
        @test other.role == :arithmetic_omission_witness_only
        @test !other.boundary_selected

        @test isapprox(report.stability.spectral_radius_requirements, 0.46609378423653025; atol = 1.0e-10)
        @test isapprox(report.stability.nonscrap_operator_condition, 1.008243308519139; atol = 1.0e-10)
        @test isapprox(report.stability.leontief_operator_condition, 2.913215049708531; atol = 1.0e-9)
        @test report.stability.spectral_radius_requirements < 1.0

        @test report.sign_ledgers[:aggregate_make].negative_count == 1
        @test report.sign_ledgers[:aggregate_make].negative_total == -9.0
        @test report.sign_ledgers[:market_shares].negative_count == 1
        @test report.sign_ledgers[:nonscrap_transform].negative_count == 1
        @test report.sign_ledgers[:aggregate_intermediate_use].negative_count == 0
        @test report.sign_ledgers[:input_coefficients].negative_count == 0
        @test report.sign_ledgers[:requirements].negative_count == 0
        @test report.sign_ledgers[:leontief_inverse].negative_count == 0
        @test report.sign_ledgers[:final_demand].negative_count == 5
        @test report.sign_ledgers[:final_demand].negative_total == -124_516.0
        @test report.sign_ledgers[:final_demand].minimum == -61_416.0
        @test report.final_demand.codes[
            argmin(report.final_demand.values),
        ] == "331"

        negative_V = only(report.negative_make_cells)
        negative_D = only(report.negative_market_share_cells)
        negative_W = only(report.negative_nonscrap_transform_cells)
        @test (
            negative_V.row_code,
            negative_V.column_code,
            negative_V.value,
        ) == ("GFGN", "22", -9.0)
        @test (
            negative_D.row_code,
            negative_D.column_code,
            negative_D.value,
        ) == ("GFGN", "22", -1.0822133427285485e-5)
        @test (
            negative_W.row_code,
            negative_W.column_code,
            negative_W.value,
        ) == ("GFGN", "22", -1.0822133427285485e-5)
    end

    @testset "complete controls and diagnostic-only classification" begin
        @test length(report.residuals) == 39
        @test family_counts(report.residuals) == Dict(
            :aggregate_level => 7,
            :published_identity_residual => 8,
            :formula_floating_point => 3,
            :conditional_current_table_coefficient_comparator => 2,
            :rejected_shortcut_witness => 1,
            :flow_noncommutation => 3,
            :other_output_witness => 7,
            :stability => 3,
            :coefficient_witness => 5,
        )
        @test all(residual -> residual.passed, report.residuals)
        @test aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            report,
        )
        @test source_controls_pass(report)
        @test !hasmethod(
            aggregate_first_scrap_adjusted_diagnostic_controls_pass,
            Tuple{AggregateFirstScrapAdjustedDiagnosticReport},
        )
        @test_throws MethodError aggregate_first_scrap_adjusted_diagnostic_controls_pass(
            report,
        )
        @test report.source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test report.methodology_status ==
            "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA"
        @test report.artifact_role ==
            :aggregate_first_68_scrap_adjusted_diagnostic_only
        @test report.promotion_status == :research_only_not_promoted
        @test report.promotion_blockers == SCRAP68_BLOCKERS
        @test report.flags[:aggregate_first_diagnostic]
        for (key, value) in report.flags
            key == :aggregate_first_diagnostic && continue
            @test value === false
        end
        @test isempty(report.emitted_runtime_keys)
        @test report.accounting_gate_effect == :none
        @test !report.promotion_ready
        @test_throws ArgumentError materialize_aggregate_first_scrap_adjusted_model_state(
            report,
        )

        source = read(
            joinpath(
                @__DIR__,
                "USAfterRedefinitionsAggregateFirstScrapAdjustedDiagnostic.jl",
            ),
            String,
        )
        @test !occursin("load_official_direct_requirements_fixture", source)
        @test !occursin("bea_2024_official_direct_requirements", source)
        @test !occursin(r"FIGARO\s*\[", source)
        @test !occursin(r"parameters\s*\[", source)
        @test !occursin(r"initial_conditions\s*\[", source)
        @test !occursin(r"model_state\s*\[", source)
        @test !occursin("balance!", source)
        @test !occursin("clip!", source)
        @test occursin("not runtime admissible", source)
    end

    @testset "adversarial arithmetic substitutions fail closed" begin
        transposed_U = deepcopy(report)
        transposed_U.aggregate_intermediate_use.values .=
            transpose(transposed_U.aggregate_intermediate_use.values)
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            transposed_U,
        )

        ratio_before_aggregation = deepcopy(report)
        ratio_before_aggregation.market_shares.values .=
            ratio_before_aggregation.industry_aggregation.values *
            ratio_before_aggregation.coefficients.source_market_shares.values *
            transpose(ratio_before_aggregation.industry_aggregation.values)
        @test maximum(
            abs.(
                ratio_before_aggregation.market_shares.values -
                    report.market_shares.values
            ),
        ) > 0.0
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            ratio_before_aggregation,
        )

        h_from_q = deepcopy(report)
        h_from_q.source_scrap_output.values .=
            h_from_q.source_commodity_output.values
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            h_from_q,
        )

        h_from_u = deepcopy(report)
        h_from_u.source_scrap_output.values .= vec(
            sum(h_from_u.source_intermediate_use.values; dims = 2),
        )
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            h_from_u,
        )

        plus_p = deepcopy(report)
        plus_operator =
            Matrix{Float64}(I, 68, 68) +
            Diagonal(plus_p.scrap_shares.values)
        plus_p.nonscrap_transform.values .=
            plus_operator \ plus_p.market_shares.values
        @test maximum(
            abs.(
                plus_p.nonscrap_transform.values -
                    report.nonscrap_transform.values
            ),
        ) > 1.0e-4
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            plus_p,
        )

        right_solve = deepcopy(report)
        right_operator =
            Matrix{Float64}(I, 68, 68) -
            Diagonal(right_solve.scrap_shares.values)
        right_solve.nonscrap_transform.values .=
            right_solve.market_shares.values / right_operator
        @test maximum(
            abs.(
                right_solve.nonscrap_transform.values -
                    report.nonscrap_transform.values
            ),
        ) > 1.0e-4
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            right_solve,
        )

        dropped_other = deepcopy(report)
        dropped_other.source_other_output.values .= 0.0
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            dropped_other,
        )

        folded_other = deepcopy(report)
        gfg_position =
            folded_other.aggregate_make.row_index["GFGN"]
        folded_other.aggregate_make.values[gfg_position, :] .+=
            folded_other.aggregate_other_output.values[gfg_position] / 68
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            folded_other,
        )

        unsigned_final = deepcopy(report)
        unsigned_final.source_final_use.values .=
            max.(unsigned_final.source_final_use.values, 0.0)
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            unsigned_final,
        )

        clipped_make = deepcopy(report)
        clipped_make.aggregate_make.values .=
            max.(clipped_make.aggregate_make.values, 0.0)
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            clipped_make,
        )

        normalized_D = deepcopy(report)
        normalized_D.market_shares.values ./=
            sum(normalized_D.market_shares.values; dims = 1)
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            normalized_D,
        )

        official_substitution = deepcopy(report)
        official =
            load_official_direct_requirements_fixture(SCRAP68_OFFICIAL_DIRECTORY)
        official_positions = [
            official.market_shares.column_index[code]
                for code in report.source_codes
        ]
        official_core = official.market_shares.values[:, official_positions]
        official_substitution.market_shares.values .=
            report.industry_aggregation.values *
            official_core *
            report.coefficients.q_composition_weights.values
        @test maximum(
            abs.(
                official_substitution.market_shares.values -
                    report.market_shares.values
            ),
        ) > 1.0e-6
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            official_substitution,
        )

        raw_awa = deepcopy(report)
        raw_awa.nonscrap_transform.values .=
            raw_awa.coefficients.raw_unweighted_w_shortcut.values
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            raw_awa,
        )

        stale_composition = deepcopy(report)
        stale_composition.coefficients.q_composition_weights.values[1, 1] +=
            0.01
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_composition,
        )

        stale_flow = deepcopy(report)
        stale_flow.flows.aggregate_first_intermediate.values[1, 1] += 1.0
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_flow,
        )

        stale_identity = deepcopy(report)
        stale_identity.identities.make_source_residual.values[1] += 1.0
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_identity,
        )

        stale_other = deepcopy(report)
        stale_other.other.arithmetic_output_term.values[1] += 1.0
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_other,
        )

        stale_mask = deepcopy(report)
        stale_mask.market_shares.explicit[1, 1] = true
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_mask,
        )

        stale_source_mask = deepcopy(report)
        stale_source_mask.source_vector_explicit[:scrap_output][1] =
            !stale_source_mask.source_vector_explicit[:scrap_output][1]
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_source_mask,
        )
        @test !source_controls_pass(stale_source_mask)

        equal_count_source_mask_swap = deepcopy(report)
        scrap_mask =
            equal_count_source_mask_swap.source_vector_explicit[:scrap_output]
        set_position = findfirst(identity, scrap_mask)
        unset_position = findfirst(!, scrap_mask)
        scrap_mask[set_position] = false
        scrap_mask[unset_position] = true
        @test count(scrap_mask) ==
            count(report.source_vector_explicit[:scrap_output])
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            equal_count_source_mask_swap,
        )

        equal_count_matrix_mask_swap = deepcopy(report)
        use_mask = equal_count_matrix_mask_swap.source_intermediate_use.explicit
        set_cell = findfirst(identity, use_mask)
        unset_cell = findfirst(!, use_mask)
        use_mask[set_cell] = false
        use_mask[unset_cell] = true
        @test count(use_mask) ==
            count(report.source_intermediate_use.explicit)
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            equal_count_matrix_mask_swap,
        )

        extra_derived_mask = deepcopy(report)
        extra_derived_mask.derived_vector_explicit[:unexpected] = falses(68)
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            extra_derived_mask,
        )

        stale_mapping = deepcopy(report)
        stale_mapping.source_industry_mapping["441"] = "441"
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_mapping,
        )

        stale_flags = deepcopy(report)
        stale_flags.flags[:runtime_transform_selected] = true
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_flags,
        )

        stale_blockers = deepcopy(report)
        pop!(stale_blockers.promotion_blockers)
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_blockers,
        )

        stale_residual = deepcopy(report)
        stale_residual.residuals[1] = typeof(stale_residual.residuals[1])(
            :aggregate_level,
            "STALE",
            "stale residual",
            0.0,
            0.0,
            0.0,
        )
        @test !aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
            stale_residual,
        )

        # Internal controls run before source reopening.
        @test !aggregate_first_scrap_adjusted_diagnostic_controls_pass(
            stale_flags,
            joinpath(mktempdir(), "missing-contract.toml"),
        )
    end

    @testset "one-byte source and contract changes fail closed" begin
        altered_contract = append_one_byte(copied_file(SCRAP68_CONTRACT_PATH))
        @test !aggregate_first_scrap_adjusted_diagnostic_controls_pass(
            report,
            altered_contract;
            after_directory = SCRAP68_AFTER_DIRECTORY,
            model_mapping_path = SCRAP68_MODEL_MAPPING_PATH,
            sector_mapping_path = SCRAP68_SECTOR_MAPPING_PATH,
            closure_boundary_contract_path =
                SCRAP68_CLOSURE_CONTRACT_PATH,
            methodology_pdf_path = SCRAP68_METHODOLOGY_PDF_PATH,
            methodology_receipt_path =
                SCRAP68_METHODOLOGY_RECEIPT_PATH,
        )
        @test_throws ArgumentError build_aggregate_first_scrap_adjusted_diagnostic(
            altered_contract,
        )

        altered_after_cells = copied_fixture(SCRAP68_AFTER_DIRECTORY)
        append_one_byte(joinpath(altered_after_cells, "cells.csv"))
        @test !source_controls_pass(
            report;
            after_directory = altered_after_cells,
        )

        altered_after_manifest = copied_fixture(SCRAP68_AFTER_DIRECTORY)
        append_one_byte(joinpath(altered_after_manifest, "manifest.toml"))
        @test !source_controls_pass(
            report;
            after_directory = altered_after_manifest,
        )

        altered_model_mapping =
            append_one_byte(copied_file(SCRAP68_MODEL_MAPPING_PATH))
        @test !source_controls_pass(
            report;
            model_mapping_path = altered_model_mapping,
        )

        altered_sector_mapping =
            append_one_byte(copied_file(SCRAP68_SECTOR_MAPPING_PATH))
        @test !source_controls_pass(
            report;
            sector_mapping_path = altered_sector_mapping,
        )

        altered_closure =
            append_one_byte(copied_file(SCRAP68_CLOSURE_CONTRACT_PATH))
        @test !source_controls_pass(
            report;
            closure_boundary_contract_path = altered_closure,
        )

        altered_pdf =
            append_one_byte(copied_file(SCRAP68_METHODOLOGY_PDF_PATH))
        @test !source_controls_pass(
            report;
            methodology_pdf_path = altered_pdf,
        )

        altered_receipt =
            append_one_byte(copied_file(SCRAP68_METHODOLOGY_RECEIPT_PATH))
        @test !source_controls_pass(
            report;
            methodology_receipt_path = altered_receipt,
        )
    end
end
