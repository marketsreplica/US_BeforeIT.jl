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
include(
    joinpath(
        @__DIR__,
        "USAfterRedefinitionsProducerPriceAdapterCandidate.jl",
    ),
)

using .USAfterRedefinitionsCommonBasis:
    AfterRedefinitionsValueAddedBasis,
    FinalUseBasis
using .USAfterRedefinitionsFinalUseEnvelope: FinalUseCategoryBasis
using .USAfterRedefinitionsProducerPriceAdapterCandidate
using .USSupplyMakeDiagnostics:
    CommodityBasis,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector

const ADAPTER_CONTRACT_PATH = joinpath(
    @__DIR__,
    "after_redefinitions_producer_price_adapter_candidate.toml",
)
const ADAPTER_AFTER_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const ADAPTER_SUPPLY_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "bea_2024_approved")
const ADAPTER_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const ADAPTER_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const ADAPTER_VALUATION_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_valuation_envelope.toml")
const ADAPTER_FINAL_USE_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_final_use_envelope.toml")
const ADAPTER_METHODOLOGY_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_io_concepts_methods_2006_approved",
)
const ADAPTER_METHODOLOGY_PDF_PATH = joinpath(
    ADAPTER_METHODOLOGY_DIRECTORY,
    "Concepts_and_Methods_US_IO_Accounts_2006.pdf",
)
const ADAPTER_METHODOLOGY_RECEIPT_PATH =
    joinpath(ADAPTER_METHODOLOGY_DIRECTORY, "receipt.toml")

const ADAPTER_FINAL_USE_CODES = [
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
const ADAPTER_CATEGORY_CODES = [
    "household_consumption",
    "private_fixed_investment",
    "inventory_change",
    "exports",
    "imports_accounting_offset",
    "government_consumption",
    "government_gross_investment",
]
const ADAPTER_CLOSURE_CODES = ["Used", "Other"]
const ADAPTER_FORBIDDEN_RUNTIME_KEYS = [
    "purchasers_to_basic_price",
    "use_product_tax_netting",
    "imports",
    "reexports",
    "S_s",
    "allocated_product_taxes",
    "government_total",
    "FIGARO",
    "parameters",
    "initial_conditions",
    "model_state",
]
const ADAPTER_BLOCKER_PREFIX = [
    "ADAPTER_CANDIDATE_NOT_CONNECTED_TO_CALIBRATION_RUNTIME",
    "USED_OTHER_CLOSURE_NOT_ALLOCATED_TO_68_MODEL_GOODS",
    "V002_NOT_SPLIT_TO_RUNTIME_TAX_CONCEPTS",
    "GOVERNMENT_CONSUMPTION_AND_INVESTMENT_RUNTIME_BOUNDARY_NOT_SELECTED",
    "F02R_NOT_MAPPED_TO_DWELLING_CAPITAL_STOCK",
    "ANNUAL_STRUCTURE_NOT_MAPPED_TO_QUARTERLY_OPENING_STATE",
    "LEGACY_VALUATION_RAKE_STILL_REACHABLE_OUTSIDE_CANDIDATE",
    "REEXPORT_SEPARATION_NOT_PROVIDED",
    "INDUSTRY_COMMODITY_RUNTIME_BASIS_NOT_SELECTED",
    "PRODUCER_PRICE_MEASUREMENT_ADAPTER_NOT_PROVIDED",
    "CLOSURE_INTERMEDIATE_INPUTS_NOT_IN_68_SECTOR_TECHNOLOGY",
    "CLOSURE_SECONDARY_OUTPUT_NOT_MAPPED_TO_68_SUPPLY",
    "BEA_USED_SCRAP_TRANSFORMATION_NOT_IMPLEMENTED",
    "OTHER_NONCOMPARABLE_IMPORT_ROW_ADJUSTMENT_NOT_MODELED",
    "SIGNED_FINAL_USE_COMPONENTS_NOT_BEHAVIORALLY_DECOMPOSED",
    "GOVERNMENT_GROSS_INVESTMENT_HAS_NO_MODEL_STATE",
    "CLOSURE_DYNAMIC_LAW_PRICE_AND_FINANCIAL_COUNTERPART_MISSING",
    "INDUSTRY_COMMODITY_TRANSFORMATION_NOT_SELECTED",
]

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function residual_family_counts(residuals)
    return Dict(
        family => count(residual -> residual.family == family, residuals)
            for family in unique(residual.family for residual in residuals)
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

function append_one_byte(path)
    open(path, "a") do io
        write(io, UInt8('\n'))
    end
    return path
end

function matrix_column(matrix, code)
    position = matrix.column_index[code]
    return (
        values = matrix.values[:, position],
        explicit = BitVector(matrix.explicit[:, position]),
    )
end

function only_residual(report, family, code)
    return only(
        filter(
            residual ->
            residual.family == family && residual.code == code,
            report.residuals,
        ),
    )
end

@testset "BEA after-redefinitions producer-price adapter candidate" begin
    report = build_producer_price_adapter_candidate(
        ADAPTER_CONTRACT_PATH;
        after_directory = ADAPTER_AFTER_FIXTURE_DIRECTORY,
        supply_directory = ADAPTER_SUPPLY_FIXTURE_DIRECTORY,
        model_mapping_path = ADAPTER_MODEL_MAPPING_PATH,
        sector_mapping_path = ADAPTER_SECTOR_MAPPING_PATH,
        valuation_contract_path = ADAPTER_VALUATION_CONTRACT_PATH,
        final_use_contract_path = ADAPTER_FINAL_USE_CONTRACT_PATH,
        methodology_pdf_path = ADAPTER_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = ADAPTER_METHODOLOGY_RECEIPT_PATH,
    )
    contract = TOML.parsefile(ADAPTER_CONTRACT_PATH)
    methodology = TOML.parsefile(ADAPTER_METHODOLOGY_RECEIPT_PATH)

    @testset "Pinned contract, sources, and methodology receipt" begin
        pinned_files = [
            (
                ADAPTER_CONTRACT_PATH,
                "de524df56ad47fb1f26534019386b27f1fc45ebc927bda5f39c3ad812259cf58",
            ),
            (
                joinpath(ADAPTER_AFTER_FIXTURE_DIRECTORY, "cells.csv"),
                "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac",
            ),
            (
                joinpath(ADAPTER_AFTER_FIXTURE_DIRECTORY, "manifest.toml"),
                "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030",
            ),
            (
                ADAPTER_MODEL_MAPPING_PATH,
                "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c",
            ),
            (
                ADAPTER_SECTOR_MAPPING_PATH,
                "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f",
            ),
            (
                ADAPTER_VALUATION_CONTRACT_PATH,
                "110f82037e45e1de3ce4f5a1df2b7982d064e90a9323f255c7441452fa6d2ede",
            ),
            (
                ADAPTER_FINAL_USE_CONTRACT_PATH,
                "b4e3969a52618b4e462b8e468ada784dda85cae86550fb27659d2afbb4cbb2be",
            ),
            (
                joinpath(ADAPTER_SUPPLY_FIXTURE_DIRECTORY, "cells.csv"),
                "c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0",
            ),
            (
                joinpath(ADAPTER_SUPPLY_FIXTURE_DIRECTORY, "manifest.toml"),
                "564a99ec2011b2566b8951e9eecb4737c0bfbc88f1e077b1eaf596af9894575c",
            ),
            (
                ADAPTER_METHODOLOGY_PDF_PATH,
                "535627e5e44f8461c0a04410f4a05c55d47f2e325d9473cb2df06e5d3e6b271d",
            ),
            (
                ADAPTER_METHODOLOGY_RECEIPT_PATH,
                "b4b210be3c364415473f1ef407ed7ea6e9edc2b299bd1058c1658b0ebb3b91ac",
            ),
        ]
        for (path, expected_sha256) in pinned_files
            @test sha256_hex(read(path)) == expected_sha256
        end

        @test contract["schema_version"] ==
            "beforeit-us-after-redefinitions-producer-price-adapter-candidate.v1"
        @test contract["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract["artifact_role"] ==
            "TYPED_CALIBRATION_ADAPTER_CANDIDATE_ONLY"
        @test contract["promotion_status"] == "RESEARCH_ONLY_NOT_PROMOTED"
        @test contract["source_year"] == 2024
        @test contract["source_frequency"] == "annual"
        @test contract["unit"] == "millions USD"
        @test contract["price_basis"] == "producers prices"
        @test contract["model_commodity_count"] == 68
        @test contract["model_industry_count"] == 68
        @test String.(contract["closure_codes"]) == ADAPTER_CLOSURE_CODES
        @test contract["scrap_transform_policy"] ==
            "BEA_NONSCRAP_TRANSFORMATION_REQUIRED_NOT_APPLIED"
        @test contract["other_boundary_policy"] ==
            "OTHER_NONCOMPARABLE_IMPORTS_AND_ROW_ADJUSTMENT_BOUNDARY_UNSELECTED"
        @test String.(contract["forbidden_runtime_keys"]) ==
            ADAPTER_FORBIDDEN_RUNTIME_KEYS
        @test length(contract["closure_account"]) == 2

        @test methodology["schema_version"] ==
            "beforeit-bea-io-methodology-receipt.v1"
        @test methodology["source_url"] ==
            "https://www.bea.gov/sites/default/files/papers/WP2006-6.pdf"
        @test methodology["source_sha256"] ==
            sha256_hex(read(ADAPTER_METHODOLOGY_PDF_PATH))
        @test methodology["byte_count"] ==
            filesize(ADAPTER_METHODOLOGY_PDF_PATH)
        @test methodology["media_type"] == "application/pdf"
        @test methodology["page_count"] == 266
        @test Int.(methodology["relevant_pdf_pages"]) ==
            [98, 123, 124, 214, 223, 224, 225]
        @test methodology["status"] ==
            "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA"
        @test methodology["artifact_role"] ==
            "SEMANTIC_METHOD_SOURCE_ONLY"
        @test !methodology["forecast_origin_admissible"]
        @test !methodology["model_state_write"]
        @test methodology["accounting_gate_effect"] == "NONE"

        @test report.contract_sha256 ==
            sha256_hex(read(ADAPTER_CONTRACT_PATH))
        @test report.after_fixture_sha256 ==
            sha256_hex(
            read(joinpath(ADAPTER_AFTER_FIXTURE_DIRECTORY, "cells.csv")),
        )
        @test report.after_manifest_sha256 ==
            sha256_hex(
            read(joinpath(ADAPTER_AFTER_FIXTURE_DIRECTORY, "manifest.toml")),
        )
        @test report.model_mapping_sha256 ==
            sha256_hex(read(ADAPTER_MODEL_MAPPING_PATH))
        @test report.sector_mapping_sha256 ==
            sha256_hex(read(ADAPTER_SECTOR_MAPPING_PATH))
        @test report.valuation_contract_sha256 ==
            sha256_hex(read(ADAPTER_VALUATION_CONTRACT_PATH))
        @test report.final_use_contract_sha256 ==
            sha256_hex(read(ADAPTER_FINAL_USE_CONTRACT_PATH))
        @test report.supply_fixture_sha256 ==
            sha256_hex(
            read(joinpath(ADAPTER_SUPPLY_FIXTURE_DIRECTORY, "cells.csv")),
        )
        @test report.supply_manifest_sha256 ==
            sha256_hex(
            read(joinpath(ADAPTER_SUPPLY_FIXTURE_DIRECTORY, "manifest.toml")),
        )
        @test report.methodology_pdf_sha256 ==
            methodology["source_sha256"]
        @test report.methodology_receipt_sha256 ==
            sha256_hex(read(ADAPTER_METHODOLOGY_RECEIPT_PATH))
        @test report.after_source_zip_sha256 ==
            "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
        @test report.table_262_source_sha256 ==
            "91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8"
    end

    @testset "Typed axes and explicit-mask preservation" begin
        @test report.core_intermediate_use isa
            LabeledMatrix{CommodityBasis, IndustryBasis}
        @test report.closure_intermediate_use isa
            LabeledMatrix{CommodityBasis, IndustryBasis}
        @test report.core_final_use isa
            LabeledMatrix{CommodityBasis, FinalUseBasis}
        @test report.closure_final_use isa
            LabeledMatrix{CommodityBasis, FinalUseBasis}
        @test report.core_category_final_use isa
            LabeledMatrix{CommodityBasis, FinalUseCategoryBasis}
        @test report.closure_category_final_use isa
            LabeledMatrix{CommodityBasis, FinalUseCategoryBasis}
        @test report.producer_value_added isa
            LabeledMatrix{AfterRedefinitionsValueAddedBasis, IndustryBasis}
        @test report.producer_make isa
            LabeledMatrix{IndustryBasis, CommodityBasis}
        @test report.closure_producer_make isa
            LabeledMatrix{IndustryBasis, CommodityBasis}
        @test report.commodity_output isa LabeledVector{CommodityBasis}
        @test report.closure_commodity_output isa
            LabeledVector{CommodityBasis}
        @test report.industry_output isa LabeledVector{IndustryBasis}

        @test length(report.model_codes) == 68
        @test length(unique(report.model_codes)) == 68
        @test report.closure_codes == ADAPTER_CLOSURE_CODES
        @test report.final_use_codes == ADAPTER_FINAL_USE_CODES
        @test report.category_codes == ADAPTER_CATEGORY_CODES
        @test report.value_added_codes == ["V001", "V002", "V003"]
        @test size(report.core_intermediate_use) == (68, 68)
        @test size(report.closure_intermediate_use) == (2, 68)
        @test size(report.core_final_use) == (68, 20)
        @test size(report.closure_final_use) == (2, 20)
        @test size(report.core_category_final_use) == (68, 7)
        @test size(report.closure_category_final_use) == (2, 7)
        @test size(report.producer_value_added) == (3, 68)
        @test size(report.producer_make) == (68, 68)
        @test size(report.closure_producer_make) == (68, 2)
        @test length(report.commodity_output) == 68
        @test length(report.closure_commodity_output) == 2
        @test length(report.industry_output) == 68

        @test report.core_intermediate_use.row_codes == report.model_codes
        @test report.core_intermediate_use.column_codes ==
            report.model_codes
        @test report.closure_intermediate_use.row_codes ==
            ADAPTER_CLOSURE_CODES
        @test report.closure_intermediate_use.column_codes ==
            report.model_codes
        @test report.producer_make.row_codes == report.model_codes
        @test report.producer_make.column_codes == report.model_codes
        @test report.closure_producer_make.row_codes ==
            report.model_codes
        @test report.closure_producer_make.column_codes ==
            ADAPTER_CLOSURE_CODES
        @test report.commodity_output.codes == report.model_codes
        @test report.closure_commodity_output.codes ==
            ADAPTER_CLOSURE_CODES
        @test report.industry_output.codes == report.model_codes

        explicit_counts = (
            core_intermediate = count(report.core_intermediate_use.explicit),
            closure_intermediate =
                count(report.closure_intermediate_use.explicit),
            core_final = count(report.core_final_use.explicit),
            closure_final = count(report.closure_final_use.explicit),
            core_category = count(report.core_category_final_use.explicit),
            closure_category =
                count(report.closure_category_final_use.explicit),
            value_added = count(report.producer_value_added.explicit),
            producer_make = count(report.producer_make.explicit),
            closure_make = count(report.closure_producer_make.explicit),
            commodity_output = count(report.commodity_output_explicit),
            closure_output =
                count(report.closure_commodity_output_explicit),
            industry_output = count(report.industry_output_explicit),
        )
        @test explicit_counts == (
            core_intermediate = 3_539,
            closure_intermediate = 97,
            core_final = 332,
            closure_final = 16,
            core_category = 255,
            closure_category = 10,
            value_added = 201,
            producer_make = 477,
            closure_make = 20,
            commodity_output = 68,
            closure_output = 2,
            industry_output = 68,
        )
        @test size(report.commodity_output_explicit) == (68,)
        @test size(report.closure_commodity_output_explicit) == (2,)
        @test size(report.industry_output_explicit) == (68,)

        explicit_zero = findfirst(
            (report.core_final_use.values .== 0.0) .&
                report.core_final_use.explicit,
        )
        omitted_zero = findfirst(
            (report.core_final_use.values .== 0.0) .&
                .!report.core_final_use.explicit,
        )
        @test explicit_zero !== nothing
        @test omitted_zero !== nothing
        @test report.core_final_use.values[explicit_zero] ==
            report.core_final_use.values[omitted_zero] == 0.0
        @test report.core_final_use.explicit[explicit_zero]
        @test !report.core_final_use.explicit[omitted_zero]

        for (candidate, source, code) in (
                (
                    report.residential_investment.model_flow,
                    report.core_final_use,
                    "F02R",
                ),
                (
                    report.residential_investment.closure_flow,
                    report.closure_final_use,
                    "F02R",
                ),
                (
                    report.inventory_flow.model_flow,
                    report.core_final_use,
                    "F030",
                ),
                (
                    report.inventory_flow.closure_flow,
                    report.closure_final_use,
                    "F030",
                ),
                (
                    report.import_evidence.producer_f050_model,
                    report.core_final_use,
                    "F050",
                ),
                (
                    report.import_evidence.producer_f050_closure,
                    report.closure_final_use,
                    "F050",
                ),
            )
            column = matrix_column(source, code)
            @test candidate.codes == source.row_codes
            @test candidate.values == column.values
        end
        @test report.residential_investment.model_explicit ==
            matrix_column(report.core_final_use, "F02R").explicit
        @test report.residential_investment.closure_explicit ==
            matrix_column(report.closure_final_use, "F02R").explicit
        @test report.inventory_flow.model_explicit ==
            matrix_column(report.core_final_use, "F030").explicit
        @test report.inventory_flow.closure_explicit ==
            matrix_column(report.closure_final_use, "F030").explicit
        @test report.import_evidence.producer_f050_model_explicit ==
            matrix_column(report.core_final_use, "F050").explicit
        @test report.import_evidence.producer_f050_closure_explicit ==
            matrix_column(report.closure_final_use, "F050").explicit
    end

    @testset "Golden totals and complete residual ledger" begin
        @test sum(report.core_intermediate_use.values) == 21_165_843.0
        @test sum(report.closure_intermediate_use.values) == 272_726.0
        @test sum(report.core_final_use.values) == 29_550_990.0
        @test sum(report.closure_final_use.values) == -252_983.0
        @test vec(sum(report.core_category_final_use.values; dims = 1)) ==
            [
            19_853_257.0,
            5_360_603.0,
            44_095.0,
            2_528_675.0,
            -3_294_892.0,
            3_991_840.0,
            1_067_412.0,
        ]
        @test vec(
            sum(report.closure_category_final_use.values; dims = 1),
        ) == [
            42_750.0,
            -154_828.0,
            9_450.0,
            254_403.0,
            -386_649.0,
            0.0,
            -18_109.0,
        ]
        @test vec(sum(report.producer_value_added.values; dims = 2)) ==
            [15_049_121.0, 1_860_445.0, 12_388_448.0]
        @test sum(report.producer_make.values) == 50_716_812.0
        @test sum(report.closure_producer_make.values) == 19_740.0
        @test sum(report.commodity_output.values) == 50_716_816.0
        @test sum(report.closure_commodity_output.values) == 19_740.0
        @test sum(report.industry_output.values) == 50_736_554.0

        @test length(report.residuals) == 92
        @test residual_family_counts(report.residuals) == Dict(
            :producer_price_core_total => 1,
            :closure_intermediate_total => 1,
            :industry_identity => 68,
            :identity_gap_witness => 2,
            :residential_flow_total => 2,
            :inventory_flow_total => 2,
            :import_offset_total => 2,
            :value_added_total => 3,
            :tax_control_total => 3,
            :closure_account_total => 4,
            :imputed_import_total => 4,
        )
        for residual in report.residuals
            @test residual.passed
            @test abs(residual.residual) <= residual.tolerance
        end
        industry_residuals = filter(
            residual -> residual.family == :industry_identity,
            report.residuals,
        )
        @test length(industry_residuals) == 68
        @test Set(residual.code for residual in industry_residuals) ==
            Set(report.model_codes)
        @test maximum(abs(residual.residual) for residual in industry_residuals) ==
            6.0
        @test maximum(
            abs(residual.residual) / residual.tolerance
                for residual in industry_residuals
        ) < 1.0

        core_gap =
            only_residual(report, :identity_gap_witness, "CORE_ONLY")
        full_gap =
            only_residual(report, :identity_gap_witness, "WITH_CLOSURE")
        @test core_gap.lhs == 272_697.0
        @test core_gap.rhs == 272_697.0
        @test full_gap.lhs == -29.0
        @test full_gap.rhs == -29.0
        witness = report.closure_omission_witness
        @test witness.core_industry_gaps.codes == report.model_codes
        @test witness.full_industry_gaps.codes == report.model_codes
        @test sum(witness.core_industry_gaps.values) == 272_697.0
        @test sum(abs.(witness.core_industry_gaps.values)) == 272_703.0
        @test witness.core_signed_total == 272_697.0
        @test witness.core_absolute_total == 272_703.0
        @test witness.core_maximum_absolute == 57_333.0
        @test witness.core_maximum_absolute_code == "81"
        @test witness.core_maximum_relative_to_output ==
            0.09513620690230688
        @test witness.core_maximum_relative_code == "331"
        @test sum(witness.full_industry_gaps.values) == -29.0
        @test sum(abs.(witness.full_industry_gaps.values)) == 127.0
        @test witness.full_signed_total == -29.0
        @test witness.full_absolute_total == 127.0
        @test witness.full_maximum_absolute == 6.0
        @test witness.full_maximum_absolute_code == "326"
        @test only_residual(report, :tax_control_total, "T015_CORE").lhs ==
            986_971.0
        @test only_residual(
            report,
            :tax_control_total,
            "T015_CLOSURE",
        ).lhs == 23_351.0
        @test only_residual(
            report,
            :tax_control_total,
            "T015_SOURCE",
        ).lhs == 1_010_322.0
    end

    @testset "Closure semantics remain a non-model sidecar" begin
        @test length(report.closure_assessments) == 2
        used, other = report.closure_assessments
        @test used.code == "Used"
        @test used.methodology_role ==
            :scrap_used_and_secondhand_goods_commodity_only_byproduct_and_final_use_sales_account
        @test used.methodology_pdf_pages == [98, 214, 223, 224, 225]
        @test used.intermediate_use_total == 100_094.0
        @test used.final_use_total == -86_542.0
        @test used.make_total == 13_553.0
        @test used.commodity_output == 13_553.0
        @test other.code == "Other"
        @test other.methodology_role ==
            :noncomparable_imports_and_rest_of_world_adjustment_composite
        @test other.methodology_pdf_pages == [123, 124]
        @test other.intermediate_use_total == 172_632.0
        @test other.final_use_total == -166_441.0
        @test other.make_total == 6_187.0
        @test other.commodity_output == 6_187.0
        for assessment in report.closure_assessments
            @test !assessment.ordinary_model_commodity
            @test !assessment.ordinary_model_producer_industry
            @test assessment.runtime_state_mapping_status == :unresolved
        end

        @test vec(
            sum(report.closure_producer_make.values; dims = 1),
        ) == [13_553.0, 6_187.0]
        @test report.closure_commodity_output.values ==
            [13_553.0, 6_187.0]
        @test count(
            !iszero,
            report.closure_producer_make.values[
                :,
                report.closure_producer_make.column_index["Used"],
            ],
        ) == 14
        @test count(
            !iszero,
            report.closure_producer_make.values[
                :,
                report.closure_producer_make.column_index["Other"],
            ],
        ) == 1
        @test isempty(report.negative_core_intermediate_cells)
        @test length(report.negative_closure_intermediate_cells) == 5
        @test length(report.negative_core_final_use_cells) == 52
        @test length(report.negative_closure_final_use_cells) == 9
        @test length(report.negative_core_category_cells) == 52
        @test length(report.negative_closure_category_cells) == 5
        @test length(report.negative_value_added_cells) == 4
    end

    @testset "Signed inventory, imports, and V002 remain unselected" begin
        inventory = report.inventory_flow
        @test sum(inventory.model_flow.values) == 44_095.0
        @test sum(inventory.closure_flow.values) == 9_450.0
        @test count(<(0.0), inventory.model_flow.values) == 7
        @test count(<(0.0), inventory.closure_flow.values) == 0
        @test inventory.source_frequency == :annual
        @test inventory.sign_policy == :preserve
        @test !inventory.stock_emission_applied
        @test !inventory.quarterly_conversion_applied

        residential = report.residential_investment
        @test sum(residential.model_flow.values) == 1_184_020.0
        @test sum(residential.closure_flow.values) == -1_182.0
        @test !residential.dwelling_stock_mapping_applied

        v002_position = report.producer_value_added.row_index["V002"]
        v002 = report.producer_value_added.values[v002_position, :]
        @test sum(v002) == 1_860_445.0
        @test count(<(0.0), v002) == 4
        @test minimum(v002) < 0.0

        imports = report.import_evidence
        @test sum(imports.producer_f050_model.values) == -3_294_892.0
        @test sum(imports.producer_f050_closure.values) == -386_649.0
        @test count(<(0.0), imports.producer_f050_model.values) == 45
        @test count(<(0.0), imports.producer_f050_closure.values) == 2
        @test imports.imputed_intermediate_model isa
            LabeledMatrix{CommodityBasis, IndustryBasis}
        @test imports.imputed_intermediate_closure isa
            LabeledMatrix{CommodityBasis, IndustryBasis}
        @test imports.imputed_final_model isa
            LabeledMatrix{CommodityBasis, FinalUseBasis}
        @test imports.imputed_final_closure isa
            LabeledMatrix{CommodityBasis, FinalUseBasis}
        @test size(imports.imputed_intermediate_model) == (68, 68)
        @test size(imports.imputed_intermediate_closure) == (2, 68)
        @test size(imports.imputed_final_model) == (68, 20)
        @test size(imports.imputed_final_closure) == (2, 20)
        @test sum(imports.imputed_intermediate_model.values) ==
            1_776_783.0
        @test sum(imports.imputed_final_model.values) == -1_776_831.0
        @test sum(imports.imputed_intermediate_closure.values) ==
            181_714.0
        @test sum(imports.imputed_final_closure.values) == -181_710.0
        @test sum(imports.imputed_f050_model.values) == -3_409_265.0
        @test sum(imports.imputed_f050_closure.values) == -386_649.0
        @test imports.imputed_f050_model.values ==
            matrix_column(imports.imputed_final_model, "F050").values
        @test imports.imputed_f050_model_explicit ==
            matrix_column(imports.imputed_final_model, "F050").explicit
        @test imports.imputed_f050_closure.values ==
            matrix_column(imports.imputed_final_closure, "F050").values
        @test imports.imputed_f050_closure_explicit ==
            matrix_column(imports.imputed_final_closure, "F050").explicit
        @test count(imports.imputed_intermediate_model.explicit) == 2_217
        @test count(imports.imputed_intermediate_closure.explicit) == 85
        @test count(imports.imputed_final_model.explicit) == 180
        @test count(imports.imputed_final_closure.explicit) == 7
        @test count(imports.imputed_f050_model_explicit) == 46
        @test count(imports.imputed_f050_closure_explicit) == 2
        @test length(report.negative_import_intermediate_model_cells) == 2
        @test isempty(report.negative_import_intermediate_closure_cells)
        @test length(report.negative_import_final_model_cells) == 54
        @test length(report.negative_import_final_closure_cells) == 2
        @test imports.import_role ==
            :separate_bea_imputed_import_allocation
        @test imports.sign_convention ==
            :positive_allocated_uses_plus_signed_f050_accounting_offset
        @test !imports.model_import_vector_emitted
        @test !imports.reexports_emitted
        @test !imports.domestic_use_subtraction_applied
    end

    @testset "No runtime emission and fail-closed materialization" begin
        @test report.year == 2024
        @test report.source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test report.methodology_status ==
            "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA"
        @test report.artifact_role ==
            :typed_calibration_adapter_candidate_only
        @test report.source_frequency == :annual
        @test report.unit == :millions_usd
        @test report.price_basis == :producers_prices
        @test report.transformation ==
            :code_keyed_producer_price_candidate_with_typed_closure_sidecar
        @test report.legacy_scalar_bridge_policy ==
            :omitted_rejected_not_cell_identified
        @test report.scrap_transform_policy ==
            :bea_nonscrap_transformation_required_not_applied
        @test report.other_boundary_policy ==
            :other_noncomparable_imports_and_row_adjustment_boundary_unselected
        @test report.negative_cell_policy == :preserve
        @test report.explicit_mask_policy ==
            :preserve_numeric_zero_vs_selected_zero
        @test isempty(report.emitted_runtime_keys)
        @test report.forbidden_runtime_keys ==
            ADAPTER_FORBIDDEN_RUNTIME_KEYS
        @test isempty(
            intersect(
                report.emitted_runtime_keys,
                report.forbidden_runtime_keys,
            ),
        )
        @test report.candidate_materialized
        @test !report.runtime_calibration_admissible
        for flag in (
                :calibration_dictionary_write,
                :figaro_dictionary_write,
                :parameter_write,
                :initial_conditions_write,
                :model_state_write,
                :forecast_origin_admissible,
                :valuation_bridge_applied,
                :tax_allocation_applied,
                :tax_variant_selected,
                :closure_allocation_applied,
                :inventory_stock_mapping_applied,
                :import_boundary_selected,
                :government_boundary_selected,
                :residential_stock_mapping_applied,
                :annual_to_quarter_mapping_applied,
                :raking_applied,
                :balancing_applied,
                :clipping_applied,
                :promotion_ready,
            )
            @test !getproperty(report, flag)
        end
        @test report.accounting_gate_effect == :none
        @test report.promotion_blockers[1:18] == ADAPTER_BLOCKER_PREFIX
        @test length(report.promotion_blockers) == 42

        @test length(report.output_assessments) == 19
        @test Set(assessment.name for assessment in report.output_assessments) ==
            Set(
            [
                :core_intermediate_use,
                :closure_intermediate_use,
                :household_consumption,
                :private_fixed_investment,
                :residential_fixed_investment_f02r,
                :inventory_change_f030,
                :exports_f040,
                :imports_offset_f050,
                :government_consumption,
                :government_gross_investment,
                :value_added_v001,
                :value_added_v002,
                :value_added_v003,
                :producer_make,
                :commodity_output,
                :industry_output,
                :imputed_import_allocations,
                :observed_t015,
                :explicit_zero_product_tax,
            ],
        )
        for assessment in report.output_assessments
            @test assessment.runtime_key === nothing
            @test !assessment.runtime_emission_allowed
            @test !isempty(assessment.reason)
        end

        @test report.observed_tax_variant.name == :observed
        @test sum(
            report.observed_tax_variant.commodity_net_product_tax.values,
        ) == 986_971.0
        @test report.zero_tax_variant.name == :explicit_zero
        @test all(
            iszero,
            report.zero_tax_variant.commodity_net_product_tax.values,
        )
        @test report.observed_tax_variant.use_cell_allocation == :none
        @test report.zero_tax_variant.use_cell_allocation == :none
        @test sum(report.closure_net_product_tax_control.values) ==
            23_351.0
        @test report.source_net_product_tax_total == 1_010_322.0

        @test producer_price_adapter_candidate_internal_controls_pass(
            report,
        )
        @test_throws MethodError producer_price_adapter_candidate_controls_pass(
            report,
        )
        @test_throws ArgumentError materialize_producer_price_adapter_model_state(
            report,
        )
        @test isempty(report.emitted_runtime_keys)
        @test !report.model_state_write
    end

    @testset "Stale reports and one-byte changes fail closed" begin
        stale_runtime = deepcopy(report)
        push!(stale_runtime.emitted_runtime_keys, "model_state")
        @test !producer_price_adapter_candidate_internal_controls_pass(
            stale_runtime,
        )

        stale_residuals = deepcopy(report)
        pop!(stale_residuals.residuals)
        @test !producer_price_adapter_candidate_internal_controls_pass(
            stale_residuals,
        )

        stale_assessment = deepcopy(report)
        pop!(stale_assessment.output_assessments)
        @test !producer_price_adapter_candidate_internal_controls_pass(
            stale_assessment,
        )

        transposed_core = deepcopy(report)
        transposed_core.core_intermediate_use.values .=
            transpose(copy(report.core_intermediate_use.values))
        @test !producer_price_adapter_candidate_internal_controls_pass(
            transposed_core,
        )

        closure_smeared = deepcopy(report)
        closure_index = findfirst(
            !iszero,
            closure_smeared.closure_intermediate_use.values,
        )
        closure_value =
            closure_smeared.closure_intermediate_use.values[closure_index]
        closure_smeared.core_intermediate_use.values[
            1,
            closure_index[2],
        ] += closure_value
        closure_smeared.closure_intermediate_use.values[closure_index] = 0.0
        @test !producer_price_adapter_candidate_internal_controls_pass(
            closure_smeared,
        )

        divided_inventory = deepcopy(report)
        divided_inventory.core_final_use.values[
            :,
            divided_inventory.core_final_use.column_index["F030"],
        ] ./= 4
        @test !producer_price_adapter_candidate_internal_controls_pass(
            divided_inventory,
        )

        relabeled_imports = deepcopy(report)
        relabeled_imports.core_final_use.values[
            :,
            relabeled_imports.core_final_use.column_index["F050"],
        ] .= abs.(
            relabeled_imports.core_final_use.values[
                :,
                relabeled_imports.core_final_use.column_index["F050"],
            ],
        )
        @test !producer_price_adapter_candidate_internal_controls_pass(
            relabeled_imports,
        )

        clipped_v002 = deepcopy(report)
        v002_position =
            clipped_v002.producer_value_added.row_index["V002"]
        clipped_v002.producer_value_added.values[v002_position, :] .= max.(
            clipped_v002.producer_value_added.values[v002_position, :],
            0.0,
        )
        @test !producer_price_adapter_candidate_internal_controls_pass(
            clipped_v002,
        )

        stale_core = deepcopy(report)
        stale_core.core_intermediate_use.values[1, 1] += 1.0
        @test !producer_price_adapter_candidate_controls_pass(
            stale_core,
            ADAPTER_CONTRACT_PATH;
            after_directory = ADAPTER_AFTER_FIXTURE_DIRECTORY,
            supply_directory = ADAPTER_SUPPLY_FIXTURE_DIRECTORY,
            model_mapping_path = ADAPTER_MODEL_MAPPING_PATH,
            sector_mapping_path = ADAPTER_SECTOR_MAPPING_PATH,
            valuation_contract_path = ADAPTER_VALUATION_CONTRACT_PATH,
            final_use_contract_path = ADAPTER_FINAL_USE_CONTRACT_PATH,
            methodology_pdf_path = ADAPTER_METHODOLOGY_PDF_PATH,
            methodology_receipt_path = ADAPTER_METHODOLOGY_RECEIPT_PATH,
        )

        changed_contract = append_one_byte(
            copied_file(ADAPTER_CONTRACT_PATH),
        )
        @test_throws ArgumentError build_producer_price_adapter_candidate(
            changed_contract,
        )
        @test !producer_price_adapter_candidate_controls_pass(
            report,
            changed_contract,
        )

        for filename in ("cells.csv", "manifest.toml")
            changed_after =
                copied_fixture(ADAPTER_AFTER_FIXTURE_DIRECTORY)
            append_one_byte(joinpath(changed_after, filename))
            @test_throws ArgumentError build_producer_price_adapter_candidate(
                ADAPTER_CONTRACT_PATH;
                after_directory = changed_after,
            )
            @test !producer_price_adapter_candidate_controls_pass(
                report,
                ADAPTER_CONTRACT_PATH;
                after_directory = changed_after,
            )
        end

        for filename in ("cells.csv", "manifest.toml")
            changed_supply =
                copied_fixture(ADAPTER_SUPPLY_FIXTURE_DIRECTORY)
            append_one_byte(joinpath(changed_supply, filename))
            @test_throws ArgumentError build_producer_price_adapter_candidate(
                ADAPTER_CONTRACT_PATH;
                supply_directory = changed_supply,
            )
            @test !producer_price_adapter_candidate_controls_pass(
                report,
                ADAPTER_CONTRACT_PATH;
                supply_directory = changed_supply,
            )
        end

        for (source_path, keyword) in (
                (ADAPTER_MODEL_MAPPING_PATH, :model_mapping_path),
                (ADAPTER_SECTOR_MAPPING_PATH, :sector_mapping_path),
                (
                    ADAPTER_VALUATION_CONTRACT_PATH,
                    :valuation_contract_path,
                ),
                (
                    ADAPTER_FINAL_USE_CONTRACT_PATH,
                    :final_use_contract_path,
                ),
            )
            changed_source =
                append_one_byte(copied_file(source_path))
            options = NamedTuple{(keyword,)}((changed_source,))
            @test_throws ArgumentError build_producer_price_adapter_candidate(
                ADAPTER_CONTRACT_PATH;
                options...,
            )
            @test !producer_price_adapter_candidate_controls_pass(
                report,
                ADAPTER_CONTRACT_PATH;
                options...,
            )
        end

        changed_methodology_pdf = append_one_byte(
            copied_file(ADAPTER_METHODOLOGY_PDF_PATH),
        )
        @test_throws ArgumentError build_producer_price_adapter_candidate(
            ADAPTER_CONTRACT_PATH;
            methodology_pdf_path = changed_methodology_pdf,
        )
        @test !producer_price_adapter_candidate_controls_pass(
            report,
            ADAPTER_CONTRACT_PATH;
            methodology_pdf_path = changed_methodology_pdf,
        )

        changed_methodology_receipt = append_one_byte(
            copied_file(ADAPTER_METHODOLOGY_RECEIPT_PATH),
        )
        @test_throws ArgumentError build_producer_price_adapter_candidate(
            ADAPTER_CONTRACT_PATH;
            methodology_receipt_path = changed_methodology_receipt,
        )
        @test !producer_price_adapter_candidate_controls_pass(
            report,
            ADAPTER_CONTRACT_PATH;
            methodology_receipt_path = changed_methodology_receipt,
        )
    end

    @testset "Source contains no runtime write path" begin
        source = read(
            joinpath(
                @__DIR__,
                "USAfterRedefinitionsProducerPriceAdapterCandidate.jl",
            ),
            String,
        )
        @test !occursin("USPipeline", source)
        @test !occursin("rake!(", source)
        @test !occursin("balance!(", source)
        @test !occursin("clip!(", source)
        @test !occursin(r"(?m)^\s*(?:open|write|touch|cp|mv|rm)\s*\(", source)
        @test !occursin(r"FIGARO\s*\[", source)
        @test !occursin(r"parameters\s*\[", source)
        @test !occursin(r"initial_conditions\s*\[", source)
        @test !occursin(r"model_state\s*\[", source)
        @test !occursin(
            r"push!\s*\(\s*report\.emitted_runtime_keys",
            source,
        )
        @test occursin(
            "producer-price adapter candidate is not runtime-admissible",
            source,
        )
    end
end
