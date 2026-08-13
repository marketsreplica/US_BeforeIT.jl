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
        "USAfterRedefinitionsGenericIndustryTransformDiagnostic.jl",
    ),
)

using .USAfterRedefinitionsCommonBasis:
    AfterRedefinitionsValueAddedBasis,
    FinalUseBasis
using .USAfterRedefinitionsGenericIndustryTransformDiagnostic
using .USSupplyMakeDiagnostics:
    CommodityBasis,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector

const GENERIC_CONTRACT_PATH = joinpath(
    @__DIR__,
    "after_redefinitions_generic_industry_transform_diagnostic.toml",
)
const GENERIC_OFFICIAL_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_official_direct_requirements_approved",
)
const GENERIC_AFTER_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const GENERIC_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const GENERIC_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const GENERIC_ADAPTER_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_producer_price_adapter_candidate.toml")
const GENERIC_METHODOLOGY_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_io_concepts_methods_2006_approved",
)
const GENERIC_METHODOLOGY_PDF_PATH = joinpath(
    GENERIC_METHODOLOGY_DIRECTORY,
    "Concepts_and_Methods_US_IO_Accounts_2006.pdf",
)
const GENERIC_METHODOLOGY_RECEIPT_PATH =
    joinpath(GENERIC_METHODOLOGY_DIRECTORY, "receipt.toml")
const GENERIC_BLOCKERS = [
    "GENERIC_MARKET_SHARE_TRANSFORM_DIAGNOSTIC_ONLY",
    "MULTI_ARCHIVE_RELEASE_IDENTITY_NOT_EXTERNALLY_BOUND",
    "USED_SCRAP_NONSCRAP_TRANSFORMATION_NOT_APPLIED",
    "USED_FINAL_USE_SALES_SUPPLY_TREATMENT_NOT_IMPLEMENTED",
    "OTHER_NONCOMPARABLE_IMPORT_ROW_BOUNDARY_NOT_SELECTED",
    "OTHER_GENERIC_D_ASSIGNMENT_TO_GFGN_NOT_ADMISSIBLE",
    "TRANSFORMED_ROWS_ARE_INDUSTRIES_NOT_MODEL_COMMODITIES",
    "NEGATIVE_TRANSFORMED_CELL_POLICY_NOT_APPROVED",
    "PUBLISHED_MARKET_SHARE_ROUNDING_DRIFT_RETAINED",
    "OFFICIAL_D_AND_MAKE_D_ARE_NOT_INTERCHANGEABLE",
    "RUNTIME_INDUSTRY_TRANSFORMATION_NOT_SELECTED",
    "PRODUCER_PRICE_ADAPTER_CONTRACT_REMAINS_NON_RUNTIME",
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

function replace_report_field(report, field::Symbol, replacement)
    names = fieldnames(typeof(report))
    position = findfirst(==(field), names)
    position === nothing && throw(ArgumentError("unknown report field $field"))
    arguments = Any[getfield(report, name) for name in names]
    arguments[position] = replacement
    return typeof(report)(arguments...)
end

function build_report()
    return build_generic_industry_transform_diagnostic(
        GENERIC_CONTRACT_PATH;
        official_directory = GENERIC_OFFICIAL_DIRECTORY,
        after_directory = GENERIC_AFTER_DIRECTORY,
        model_mapping_path = GENERIC_MODEL_MAPPING_PATH,
        sector_mapping_path = GENERIC_SECTOR_MAPPING_PATH,
        adapter_contract_path = GENERIC_ADAPTER_CONTRACT_PATH,
        methodology_pdf_path = GENERIC_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = GENERIC_METHODOLOGY_RECEIPT_PATH,
    )
end

function source_controls_pass(report; kwargs...)
    return generic_industry_transform_diagnostic_controls_pass(
        report,
        GENERIC_CONTRACT_PATH;
        official_directory = GENERIC_OFFICIAL_DIRECTORY,
        after_directory = GENERIC_AFTER_DIRECTORY,
        model_mapping_path = GENERIC_MODEL_MAPPING_PATH,
        sector_mapping_path = GENERIC_SECTOR_MAPPING_PATH,
        adapter_contract_path = GENERIC_ADAPTER_CONTRACT_PATH,
        methodology_pdf_path = GENERIC_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = GENERIC_METHODOLOGY_RECEIPT_PATH,
        kwargs...,
    )
end

@testset "rejected BEA generic industry-transform diagnostic" begin
    report = build_report()
    contract = TOML.parsefile(GENERIC_CONTRACT_PATH)

    @testset "byte-pinned rejection contract and methodology" begin
        pinned_files = [
            (
                GENERIC_CONTRACT_PATH,
                "4297b6faf5cd3fb0b0ee67d8d287f8b3481090c5d4e683c041e55f7a2d185f7c",
            ),
            (
                joinpath(GENERIC_OFFICIAL_DIRECTORY, "cells.csv"),
                "d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e",
            ),
            (
                joinpath(GENERIC_OFFICIAL_DIRECTORY, "manifest.toml"),
                "a225951d7ec03aaaaa97f5cc02e58b862e00918dbd31cc35093d80f9dde8c35d",
            ),
            (
                joinpath(GENERIC_AFTER_DIRECTORY, "cells.csv"),
                "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac",
            ),
            (
                joinpath(GENERIC_AFTER_DIRECTORY, "manifest.toml"),
                "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030",
            ),
            (
                GENERIC_MODEL_MAPPING_PATH,
                "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c",
            ),
            (
                GENERIC_SECTOR_MAPPING_PATH,
                "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f",
            ),
            (
                GENERIC_ADAPTER_CONTRACT_PATH,
                "de524df56ad47fb1f26534019386b27f1fc45ebc927bda5f39c3ad812259cf58",
            ),
            (
                GENERIC_METHODOLOGY_PDF_PATH,
                "535627e5e44f8461c0a04410f4a05c55d47f2e325d9473cb2df06e5d3e6b271d",
            ),
            (
                GENERIC_METHODOLOGY_RECEIPT_PATH,
                "b4b210be3c364415473f1ef407ed7ea6e9edc2b299bd1058c1658b0ebb3b91ac",
            ),
        ]
        for (path, expected_sha256) in pinned_files
            @test sha256_hex(read(path)) == expected_sha256
        end

        @test contract["schema_version"] ==
            "beforeit-us-after-redefinitions-generic-industry-transform-diagnostic.v1"
        @test contract["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract["artifact_role"] ==
            "REJECTED_GENERIC_INDUSTRY_TRANSFORM_DIAGNOSTIC_ONLY"
        @test contract["promotion_status"] ==
            "REJECTED_NOT_RUNTIME_ADMISSIBLE"
        @test contract["market_share_source"] ==
            "OFFICIAL_PUBLISHED_IXC_MS_SUMMARY_NOT_RECOMPUTED"
        @test contract["aggregation_order"] ==
            "TRANSFORM_SOURCE_AXES_THEN_AGGREGATE_INDUSTRIES"
        @test contract["cross_archive_release_identity"] ==
            "NOT_EXTERNALLY_BOUND"
        @test contract["cross_archive_application_status"] ==
            "ARITHMETIC_DIAGNOSTIC_ONLY"
        @test contract["producer_price_adapter_contract_sha256"] ==
            sha256_hex(read(GENERIC_ADAPTER_CONTRACT_PATH))
        @test contract["official_direct_workbook_sha256"] ==
            "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439"
        @test contract["methodology_pdf_sha256"] ==
            sha256_hex(read(GENERIC_METHODOLOGY_PDF_PATH))
        @test contract["methodology_receipt_sha256"] ==
            sha256_hex(read(GENERIC_METHODOLOGY_RECEIPT_PATH))
        @test String.(contract["promotion_blockers"]) == GENERIC_BLOCKERS
        @test contract["diagnostic_transform_applied"] === true
        for key in (
                "runtime_transform_selected",
                "runtime_calibration_admissible",
                "calibration_dictionary_write",
                "parameter_write",
                "initial_conditions_write",
                "model_state_write",
                "forecast_origin_admissible",
                "nonscrap_transform_applied",
                "used_final_sales_supply_adjustment_applied",
                "other_boundary_selected",
                "balancing_applied",
                "normalization_applied",
                "clipping_applied",
                "raking_applied",
            )
            @test contract[key] === false
        end
        @test contract["accounting_gate_effect"] == "NONE"
        closure_contract =
            Dict(String(account["code"]) => account for account in contract["closure_account"])
        @test Set(keys(closure_contract)) == Set(["Used", "Other"])
        @test Int.(closure_contract["Used"]["methodology_pdf_pages"]) ==
            [98, 214, 223, 224, 225]
        @test Int.(closure_contract["Other"]["methodology_pdf_pages"]) ==
            [123, 124]
    end

    @testset "typed exact transform then aggregation" begin
        @test report.year == 2024
        @test length(report.source_industry_codes) == 71
        @test length(report.commodity_codes) == 73
        @test length(report.model_industry_codes) == 68
        @test length(report.final_use_codes) == 20
        @test report.official_market_shares isa
            LabeledMatrix{IndustryBasis, CommodityBasis}
        @test report.producer_intermediate_use isa
            LabeledMatrix{CommodityBasis, IndustryBasis}
        @test report.producer_final_use isa
            LabeledMatrix{CommodityBasis, FinalUseBasis}
        @test report.producer_make isa
            LabeledMatrix{IndustryBasis, CommodityBasis}
        @test report.producer_value_added isa
            LabeledMatrix{AfterRedefinitionsValueAddedBasis, IndustryBasis}
        @test report.commodity_output isa LabeledVector{CommodityBasis}
        @test report.industry_output isa LabeledVector{IndustryBasis}
        @test report.industry_aggregation isa
            LabeledMatrix{IndustryBasis, IndustryBasis}
        @test report.source_transformed_intermediate isa
            LabeledMatrix{IndustryBasis, IndustryBasis}
        @test report.source_transformed_final_use isa
            LabeledMatrix{IndustryBasis, FinalUseBasis}
        @test report.model_transformed_intermediate isa
            LabeledMatrix{IndustryBasis, IndustryBasis}
        @test report.model_transformed_final_use isa
            LabeledMatrix{IndustryBasis, FinalUseBasis}
        @test size(report.official_market_shares) == (71, 73)
        @test size(report.producer_intermediate_use) == (73, 71)
        @test size(report.producer_final_use) == (73, 20)
        @test size(report.industry_aggregation) == (68, 71)
        @test size(report.source_transformed_intermediate) == (71, 71)
        @test size(report.source_transformed_final_use) == (71, 20)
        @test size(report.model_transformed_intermediate) == (68, 68)
        @test size(report.model_transformed_final_use) == (68, 20)

        D = report.official_market_shares.values
        U = report.producer_intermediate_use.values
        F = report.producer_final_use.values
        A = report.industry_aggregation.values
        @test report.official_market_shares.column_codes ==
            report.producer_intermediate_use.row_codes ==
            report.producer_final_use.row_codes
        @test report.official_market_shares.row_codes ==
            report.producer_intermediate_use.column_codes
        @test report.source_transformed_intermediate.values == D * U
        @test report.source_transformed_final_use.values == D * F
        @test report.model_transformed_intermediate.values ==
            A * (D * U) * transpose(A)
        @test report.model_transformed_final_use.values == A * (D * F)
        @test all(sum(A; dims = 1) .== 1.0)
        @test all(value == 0.0 || value == 1.0 for value in A)
        @test count(==(1.0), A) == 71
        @test sum(A[report.industry_aggregation.row_index["4A0"], :]) == 4.0
        @test report.source_industry_mapping["441"] == "4A0"
        @test report.source_industry_mapping["445"] == "4A0"
        @test report.source_industry_mapping["452"] == "4A0"
        @test report.source_industry_mapping["4A0"] == "4A0"
        @test all(report.official_market_shares.explicit)
        for derived in (
                report.industry_aggregation,
                report.source_transformed_intermediate,
                report.source_transformed_final_use,
                report.model_transformed_intermediate,
                report.model_transformed_final_use,
                report.closure_intermediate_contribution,
                report.closure_final_use_contribution,
            )
            @test !any(derived.explicit)
        end
        @test report.source_transform_formula ==
            "Z_71 = D_official * U_producer"
        @test report.final_use_transform_formula ==
            "Y_71 = D_official * F_producer"
        @test report.aggregation_formula ==
            "Z_68 = A * Z_71 * transpose(A); Y_68 = A * Y_71"
    end

    @testset "signed cells and published-rounding ledgers" begin
        @test isapprox(
            report.rounding.market_share_total,
            72.9999995;
            atol = 1.0e-12,
        )
        @test isapprox(
            report.rounding.maximum_market_share_column_residual,
            2.9999999995311555e-7;
            atol = 1.0e-16,
        )
        @test report.official_market_share_signs.negative_count == 1
        @test report.official_market_share_signs.negative_total == -1.13e-5
        negative_D = only(report.negative_official_market_share_cells)
        @test negative_D.row_code == "GFGN"
        @test negative_D.column_code == "22"
        @test negative_D.value == -1.13e-5

        @test report.source_intermediate_signs.negative_count == 5
        @test report.source_intermediate_signs.negative_total == -729.0
        @test report.source_final_use_signs.negative_count == 61
        @test report.source_final_use_signs.negative_total == -4_026_821.0
        @test report.source_transformed_intermediate_signs.negative_count == 14
        @test isapprox(
            report.source_transformed_intermediate_signs.negative_total,
            -168.07219089999998;
            atol = 1.0e-12,
        )
        @test report.source_transformed_intermediate_signs.minimum ==
            -64.96443029999999
        @test report.source_transformed_intermediate_signs.maximum ==
            566_447.7122816
        @test isapprox(
            report.source_transformed_intermediate_signs.absolute_total,
            21_438_904.570035603;
            atol = 1.0e-6,
        )
        @test report.source_transformed_final_use_signs.negative_count == 135
        @test isapprox(
            report.source_transformed_final_use_signs.negative_total,
            -3_991_835.1907419995;
            atol = 1.0e-6,
        )
        @test report.source_transformed_final_use_signs.minimum ==
            -447_562.6077516999
        @test report.source_transformed_final_use_signs.maximum ==
            3_133_851.5615391
        @test isapprox(
            report.source_transformed_final_use_signs.absolute_total,
            37_281_677.053597994;
            atol = 1.0e-6,
        )
        @test report.model_transformed_intermediate_signs.negative_count == 14
        @test report.model_transformed_final_use_signs.negative_count == 135
        @test isapprox(
            report.rounding.intermediate_total_drift,
            -0.574346199631691;
            atol = 1.0e-12,
        )
        @test isapprox(
            report.rounding.final_use_total_drift,
            -0.3278859965503216;
            atol = 1.0e-12,
        )
        @test length(report.negative_source_transformed_intermediate_cells) == 14
        @test length(report.negative_source_transformed_final_use_cells) == 135
        @test length(report.negative_model_transformed_intermediate_cells) == 14
        @test length(report.negative_model_transformed_final_use_cells) == 135
    end

    @testset "closure transformation witnesses reject generic semantics" begin
        @test [witness.code for witness in report.closure_witnesses] ==
            ["Used", "Other"]
        used = report.closure_witnesses[1]
        other = report.closure_witnesses[2]
        @test count(!iszero, used.market_shares.values) == 15
        @test isapprox(sum(used.market_shares.values), 1.0000001; atol = 1.0e-12)
        @test used.market_shares["GSLG"] == 0.4188515
        @test used.intermediate_signs.negative_count == 75
        @test isapprox(
            used.intermediate_signs.total,
            100_094.0100094;
            atol = 1.0e-6,
        )
        @test used.final_use_signs.negative_count == 105
        @test isapprox(
            used.final_use_signs.total,
            -86_542.0086542;
            atol = 1.0e-6,
        )
        @test count(!iszero, other.market_shares.values) == 1
        @test other.market_shares["GFGN"] == 1.0
        @test other.intermediate_signs.negative_count == 0
        @test other.intermediate_signs.total == 172_632.0
        @test other.final_use_signs.negative_count == 2
        @test other.final_use_signs.negative_total == -405_401.0
        @test other.final_use_signs.positive_total == 238_960.0
        @test other.final_use_signs.total == -166_441.0
        @test used.methodology_pdf_pages == [98, 214, 223, 224, 225]
        @test other.methodology_pdf_pages == [123, 124]

        @test report.closure_intermediate_signs.negative_count == 75
        @test isapprox(
            report.closure_intermediate_signs.total,
            272_726.01000939996;
            atol = 1.0e-6,
        )
        @test isapprox(
            report.closure_intermediate_signs.negative_total,
            -729.0000729;
            atol = 1.0e-9,
        )
        @test report.closure_final_use_signs.negative_count == 107
        @test isapprox(
            report.closure_final_use_signs.total,
            -252_983.00865420004;
            atol = 1.0e-6,
        )
        @test isapprox(
            report.closure_final_use_signs.negative_total,
            -617_102.0211701001;
            atol = 1.0e-6,
        )
        no_closure_Z =
            report.source_transformed_intermediate.values -
            report.closure_intermediate_contribution.values
        no_closure_Y =
            report.source_transformed_final_use.values -
            report.closure_final_use_contribution.values
        @test isapprox(sum(no_closure_Z), 21_165_842.4156444; atol = 1.0e-6)
        @test count(value -> value < 0.0, no_closure_Z) == 71
        @test isapprox(
            sum(no_closure_Z[no_closure_Z .< 0.0]),
            -5.1835473;
            atol = 1.0e-9,
        )
        @test isapprox(sum(no_closure_Y), 29_550_989.6807682; atol = 1.0e-6)
        @test count(value -> value < 0.0, no_closure_Y) == 62
        @test isapprox(
            sum(no_closure_Y[no_closure_Y .< 0.0]),
            -3_408_965.7861947;
            atol = 1.0e-6,
        )
    end

    @testset "official D cannot be substituted by make-derived D" begin
        witness = report.market_share_substitution
        make_D =
            report.producer_make.values ./
            transpose(report.commodity_output.values)
        @test witness.make_derived_market_shares.values == make_D
        @test witness.official_minus_make_derived.values ==
            report.official_market_shares.values - make_D
        @test isapprox(
            witness.make_derived_total,
            72.99993111225601;
            atol = 1.0e-12,
        )
        @test isapprox(
            witness.make_derived_maximum_column_residual,
            4.046944556856946e-5;
            atol = 1.0e-16,
        )
        @test isapprox(
            witness.signed_difference,
            6.83877439945971e-5;
            atol = 1.0e-16,
        )
        @test isapprox(
            witness.absolute_difference,
            0.0008565132482050305;
            atol = 1.0e-16,
        )
        @test witness.differing_cell_count == 437
        @test witness.maximum_row_code == "331"
        @test witness.maximum_column_code == "Used"
        @test isapprox(
            witness.maximum_difference,
            2.7890009591975684e-5;
            atol = 1.0e-16,
        )
        @test witness.official_value_at_maximum == 0.0444461
        @test witness.make_derived_value_at_maximum ==
            0.04441820999040803
    end

    @testset "cross-source identity residuals are witnesses, not gates" begin
        source_input = report.source_input_identity_summary
        source_output = report.source_output_identity_summary
        model_input = report.model_input_identity_summary
        model_output = report.model_output_identity_summary
        @test isapprox(source_input.signed_total, 28.425653798483836; atol = 1.0e-12)
        @test isapprox(source_input.absolute_total, 131.05323759969178; atol = 1.0e-12)
        @test source_input.maximum_residual_code == "326"
        @test source_input.maximum_absolute_residual == 6.016380200046115
        @test isapprox(source_output.signed_total, 21.09776779980166; atol = 1.0e-12)
        @test source_output.maximum_residual_code == "331"
        @test source_output.maximum_absolute_residual == 4.944044500123709
        @test isapprox(model_input.signed_total, 28.425653798756684; atol = 1.0e-12)
        @test model_input.maximum_residual_code == "326"
        @test isapprox(model_output.signed_total, 21.097767799627036; atol = 1.0e-12)
        @test model_output.maximum_residual_code == "4A0"
        @test model_output.maximum_absolute_residual == 6.909504000097513
        @test all(residual.passed for residual in report.residuals)
        @test count(
            residual ->
            residual.family == :official_market_share_column_control,
            report.residuals,
        ) == 73
        @test count(
            residual -> residual.family == :exact_transform,
            report.residuals,
        ) == 2
        @test count(
            residual ->
            residual.family == :post_transform_aggregation,
            report.residuals,
        ) == 2
        @test count(
            residual -> residual.family == :pinned_numeric_witness,
            report.residuals,
        ) == 6
    end

    @testset "fail-closed rejected status and canonical source gate" begin
        @test report.source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test report.artifact_role ==
            "REJECTED_GENERIC_INDUSTRY_TRANSFORM_DIAGNOSTIC_ONLY"
        @test report.promotion_status == "REJECTED_NOT_RUNTIME_ADMISSIBLE"
        @test report.promotion_blockers == GENERIC_BLOCKERS
        @test report.diagnostic_transform_applied
        @test !report.runtime_transform_selected
        @test !report.runtime_calibration_admissible
        @test !report.calibration_dictionary_write
        @test !report.parameter_write
        @test !report.initial_conditions_write
        @test !report.model_state_write
        @test !report.forecast_origin_admissible
        @test report.accounting_gate_effect == :none
        @test !report.nonscrap_transform_applied
        @test !report.used_final_sales_supply_adjustment_applied
        @test !report.other_boundary_selected
        @test !report.balancing_applied
        @test !report.normalization_applied
        @test !report.clipping_applied
        @test !report.raking_applied
        @test generic_industry_transform_diagnostic_internal_controls_pass(
            report,
        )
        @test source_controls_pass(report)
        @test_throws MethodError generic_industry_transform_diagnostic_controls_pass(
            report,
        )

        stale_D = deepcopy(report)
        stale_D.official_market_shares.values[1, 1] += 1.0
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_D,
        )
        @test !source_controls_pass(stale_D)

        stale_orientation = deepcopy(report)
        stale_orientation.official_market_shares.values[[1, 2], :] =
            stale_orientation.official_market_shares.values[[2, 1], :]
        stale_orientation.official_market_shares.values[:, [1, 2]] =
            stale_orientation.official_market_shares.values[:, [2, 1]]
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_orientation,
        )

        stale_normalized_D = deepcopy(report)
        stale_normalized_D.official_market_shares.values ./=
            sum(stale_normalized_D.official_market_shares.values; dims = 1)
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_normalized_D,
        )

        stale_clipped_D = deepcopy(report)
        stale_clipped_D.official_market_shares.values .= max.(
            stale_clipped_D.official_market_shares.values,
            0.0,
        )
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_clipped_D,
        )

        stale_transform = deepcopy(report)
        stale_transform.source_transformed_intermediate.values[1, 1] += 5.0
        stale_transform.source_transformed_intermediate.values[2, 2] -= 5.0
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_transform,
        )
        @test !source_controls_pass(stale_transform)

        stale_axis = deepcopy(report)
        stale_axis.source_transformed_final_use.column_codes[[1, 2]] =
            stale_axis.source_transformed_final_use.column_codes[[2, 1]]
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_axis,
        )

        stale_mask = deepcopy(report)
        stale_mask.model_transformed_intermediate.explicit[1, 1] = true
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_mask,
        )

        stale_aggregation = deepcopy(report)
        stale_aggregation.industry_aggregation.values[:, [1, 2]] =
            stale_aggregation.industry_aggregation.values[:, [2, 1]]
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_aggregation,
        )

        stale_pre_transform = deepcopy(report)
        commodity_aggregation = zeros(
            length(report.model_industry_codes),
            length(report.commodity_codes),
        )
        model_index = Dict(
            code => position
                for (position, code) in pairs(report.model_industry_codes)
        )
        commodity_index = report.official_market_shares.column_index
        for code in report.source_industry_codes
            target = report.source_industry_mapping[code]
            commodity_aggregation[
                model_index[target],
                commodity_index[code],
            ] = 1.0
        end
        pre_transform_shortcut =
            (
            stale_pre_transform.industry_aggregation.values *
                stale_pre_transform.official_market_shares.values *
                transpose(commodity_aggregation)
        ) * (
            commodity_aggregation *
                stale_pre_transform.producer_intermediate_use.values *
                transpose(stale_pre_transform.industry_aggregation.values)
        )
        @test maximum(
            abs.(
                pre_transform_shortcut .-
                    stale_pre_transform.model_transformed_intermediate.values
            ),
        ) > 1.0
        stale_pre_transform.model_transformed_intermediate.values .=
            pre_transform_shortcut
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_pre_transform,
        )

        stale_make_D = deepcopy(report)
        stale_make_D.official_market_shares.values .=
            stale_make_D.market_share_substitution.make_derived_market_shares.values
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_make_D,
        )

        stale_clipped = deepcopy(report)
        stale_clipped.source_transformed_final_use.values .= max.(
            stale_clipped.source_transformed_final_use.values,
            0.0,
        )
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_clipped,
        )

        stale_closure = deepcopy(report)
        stale_closure.closure_intermediate_contribution.values .= 0.0
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_closure,
        )

        stale_other = deepcopy(report)
        other_shares = stale_other.closure_witnesses[2].market_shares.values
        gfg_position =
            stale_other.closure_witnesses[2].market_shares.index["GFGN"]
        gsl_position =
            stale_other.closure_witnesses[2].market_shares.index["GSLG"]
        other_shares[gfg_position] -= 0.1
        other_shares[gsl_position] += 0.1
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_other,
        )

        stale_identity = deepcopy(report)
        stale_identity.model_output_identity_residual.values[1] += 1.0
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_identity,
        )

        stale_blockers = deepcopy(report)
        pop!(stale_blockers.promotion_blockers)
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_blockers,
        )
        @test !source_controls_pass(stale_blockers)

        stale_runtime =
            replace_report_field(report, :runtime_transform_selected, true)
        @test !generic_industry_transform_diagnostic_internal_controls_pass(
            stale_runtime,
        )
        @test !source_controls_pass(stale_runtime)
    end

    @testset "altered byte sources fail closed" begin
        altered_contract = append_one_byte(copied_file(GENERIC_CONTRACT_PATH))
        @test !generic_industry_transform_diagnostic_controls_pass(
            report,
            altered_contract;
            official_directory = GENERIC_OFFICIAL_DIRECTORY,
            after_directory = GENERIC_AFTER_DIRECTORY,
            model_mapping_path = GENERIC_MODEL_MAPPING_PATH,
            sector_mapping_path = GENERIC_SECTOR_MAPPING_PATH,
            adapter_contract_path = GENERIC_ADAPTER_CONTRACT_PATH,
            methodology_pdf_path = GENERIC_METHODOLOGY_PDF_PATH,
            methodology_receipt_path = GENERIC_METHODOLOGY_RECEIPT_PATH,
        )
        @test_throws ArgumentError build_generic_industry_transform_diagnostic(
            altered_contract,
        )

        altered_official = copied_fixture(GENERIC_OFFICIAL_DIRECTORY)
        append_one_byte(joinpath(altered_official, "cells.csv"))
        @test !source_controls_pass(
            report;
            official_directory = altered_official,
        )

        altered_official_manifest =
            copied_fixture(GENERIC_OFFICIAL_DIRECTORY)
        append_one_byte(joinpath(altered_official_manifest, "manifest.toml"))
        @test !source_controls_pass(
            report;
            official_directory = altered_official_manifest,
        )

        altered_after = copied_fixture(GENERIC_AFTER_DIRECTORY)
        append_one_byte(joinpath(altered_after, "manifest.toml"))
        @test !source_controls_pass(report; after_directory = altered_after)

        altered_after_cells = copied_fixture(GENERIC_AFTER_DIRECTORY)
        append_one_byte(joinpath(altered_after_cells, "cells.csv"))
        @test !source_controls_pass(
            report;
            after_directory = altered_after_cells,
        )

        altered_mapping =
            append_one_byte(copied_file(GENERIC_MODEL_MAPPING_PATH))
        @test !source_controls_pass(
            report;
            model_mapping_path = altered_mapping,
        )

        altered_sector =
            append_one_byte(copied_file(GENERIC_SECTOR_MAPPING_PATH))
        @test !source_controls_pass(
            report;
            sector_mapping_path = altered_sector,
        )

        altered_adapter =
            append_one_byte(copied_file(GENERIC_ADAPTER_CONTRACT_PATH))
        @test !source_controls_pass(
            report;
            adapter_contract_path = altered_adapter,
        )

        altered_pdf =
            append_one_byte(copied_file(GENERIC_METHODOLOGY_PDF_PATH))
        @test !source_controls_pass(
            report;
            methodology_pdf_path = altered_pdf,
        )

        altered_receipt =
            append_one_byte(copied_file(GENERIC_METHODOLOGY_RECEIPT_PATH))
        @test !source_controls_pass(
            report;
            methodology_receipt_path = altered_receipt,
        )
    end

    @testset "module remains diagnostic-only" begin
        source = read(
            joinpath(
                @__DIR__,
                "USAfterRedefinitionsGenericIndustryTransformDiagnostic.jl",
            ),
            String,
        )
        @test !occursin("materialize_generic", source)
        @test !occursin(r"FIGARO\s*\[", source)
        @test !occursin(r"parameters\s*\[", source)
        @test !occursin(r"initial_conditions\s*\[", source)
        @test !occursin(r"model_state\s*\[", source)
        @test !occursin("balance!", source)
        @test !occursin("clip!", source)
        @test occursin("REJECTED_GENERIC_INDUSTRY_TRANSFORM", source)
        @test occursin("NOT_RUNTIME_ADMISSIBLE", source)
    end
end
