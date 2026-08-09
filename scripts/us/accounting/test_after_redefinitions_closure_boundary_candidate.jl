using SHA
using Test
using TOML
using LinearAlgebra

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
include(
    joinpath(
        @__DIR__,
        "USAfterRedefinitionsClosureBoundaryCandidate.jl",
    ),
)

using .USAfterRedefinitionsClosureBoundaryCandidate
using .USAfterRedefinitionsCommonBasis: FinalUseBasis
using .USSupplyMakeDiagnostics:
    CommodityBasis,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector

const CLOSURE_BOUNDARY_CONTRACT_PATH = joinpath(
    @__DIR__,
    "after_redefinitions_closure_boundary_candidate.toml",
)
const CLOSURE_BOUNDARY_AFTER_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const CLOSURE_BOUNDARY_OFFICIAL_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_official_direct_requirements_approved",
)
const CLOSURE_BOUNDARY_ADAPTER_CONTRACT_PATH = joinpath(
    @__DIR__,
    "after_redefinitions_producer_price_adapter_candidate.toml",
)
const CLOSURE_BOUNDARY_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const CLOSURE_BOUNDARY_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const CLOSURE_BOUNDARY_VALUATION_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_valuation_envelope.toml")
const CLOSURE_BOUNDARY_FINAL_USE_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_final_use_envelope.toml")
const CLOSURE_BOUNDARY_SUPPLY_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "bea_2024_approved")
const CLOSURE_BOUNDARY_METHODOLOGY_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_io_concepts_methods_2006_approved",
)
const CLOSURE_BOUNDARY_METHODOLOGY_PDF_PATH = joinpath(
    CLOSURE_BOUNDARY_METHODOLOGY_DIRECTORY,
    "Concepts_and_Methods_US_IO_Accounts_2006.pdf",
)
const CLOSURE_BOUNDARY_METHODOLOGY_RECEIPT_PATH =
    joinpath(CLOSURE_BOUNDARY_METHODOLOGY_DIRECTORY, "receipt.toml")

const CLOSURE_BOUNDARY_CODES = ["Used", "Other"]
const CLOSURE_BOUNDARY_BLOCKERS = [
    "CLOSURE_BOUNDARY_CANDIDATE_DIAGNOSTIC_ONLY",
    "MULTI_ARCHIVE_RELEASE_IDENTITY_NOT_EXTERNALLY_BOUND",
    "PUBLISHED_MARKET_SHARE_ROUNDING_DRIFT_RETAINED",
    "SOURCE_FIRST_AND_AGGREGATE_FIRST_NONSCRAP_NOT_INTERCHANGEABLE",
    "AGGREGATE_FIRST_68_NONSCRAP_TRANSFORM_NOT_BUILT",
    "USED_SCRAP_NONSCRAP_TRANSFORMATION_NOT_IMPLEMENTED",
    "USED_ASSET_TRANSFER_AND_NEGATIVE_FLOW_SEMANTICS_NOT_MAPPED",
    "OTHER_COMPOSITE_NOT_SPLIT_NONCOMPARABLE_IMPORTS_VS_ROW_ADJUSTMENT",
    "OTHER_NONCOMPARABLE_IMPORT_FINANCIAL_COUNTERPART_NOT_MAPPED_TO_ROTW",
    "ROW_ADJUSTMENT_COMPONENTS_AND_ACCOUNTING_COUNTERPARTS_NOT_IDENTIFIED",
    "CLOSURE_CURRENT_DOLLAR_PRICE_QUANTITY_DECOMPOSITION_NOT_IDENTIFIED",
    "CLOSURE_QUARTERLY_DYNAMIC_LAW_NOT_ESTIMATED",
    "CLOSURE_CORE_INPUT_COST_AND_PRODUCTION_CONSTRAINT_BOUNDARY_NOT_SELECTED",
    "CLOSURE_DOUBLE_ENTRY_AND_BANK_IDENTITIES_NOT_TRANSITION_TESTED",
    "INDUSTRY_COMMODITY_TRANSFORMATION_NOT_SELECTED",
    "70_ACCOUNT_PRODUCT_MIX_DIAGNOSTIC_NOT_RUNTIME_TECHNOLOGY",
]

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

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

function residual_family_counts(residuals)
    return Dict(
        family => count(residual -> residual.family == family, residuals)
            for family in unique(residual.family for residual in residuals)
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

@testset "BEA after-redefinitions closure-boundary candidate" begin
    report = build_closure_boundary_candidate(
        CLOSURE_BOUNDARY_CONTRACT_PATH;
        after_directory = CLOSURE_BOUNDARY_AFTER_DIRECTORY,
        official_market_share_directory =
            CLOSURE_BOUNDARY_OFFICIAL_DIRECTORY,
        adapter_contract_path = CLOSURE_BOUNDARY_ADAPTER_CONTRACT_PATH,
        model_mapping_path = CLOSURE_BOUNDARY_MODEL_MAPPING_PATH,
        sector_mapping_path = CLOSURE_BOUNDARY_SECTOR_MAPPING_PATH,
        valuation_contract_path = CLOSURE_BOUNDARY_VALUATION_CONTRACT_PATH,
        final_use_contract_path =
            CLOSURE_BOUNDARY_FINAL_USE_CONTRACT_PATH,
        supply_directory = CLOSURE_BOUNDARY_SUPPLY_DIRECTORY,
        methodology_pdf_path =
            CLOSURE_BOUNDARY_METHODOLOGY_PDF_PATH,
        methodology_receipt_path =
            CLOSURE_BOUNDARY_METHODOLOGY_RECEIPT_PATH,
    )
    contract = TOML.parsefile(CLOSURE_BOUNDARY_CONTRACT_PATH)

    @testset "Pinned contract and complete source identities" begin
        @test sha256_hex(read(CLOSURE_BOUNDARY_CONTRACT_PATH)) ==
            "ad6f1995575b1fa612577eb4001e9163159d6802fa947d6f5385a2d07758172f"
        pinned_files = Dict(
            "after_redefinitions_fixture_sha256" => joinpath(
                CLOSURE_BOUNDARY_AFTER_DIRECTORY,
                "cells.csv",
            ),
            "after_redefinitions_manifest_sha256" => joinpath(
                CLOSURE_BOUNDARY_AFTER_DIRECTORY,
                "manifest.toml",
            ),
            "official_market_share_fixture_sha256" => joinpath(
                CLOSURE_BOUNDARY_OFFICIAL_DIRECTORY,
                "cells.csv",
            ),
            "official_market_share_manifest_sha256" => joinpath(
                CLOSURE_BOUNDARY_OFFICIAL_DIRECTORY,
                "manifest.toml",
            ),
            "producer_price_adapter_contract_sha256" =>
                CLOSURE_BOUNDARY_ADAPTER_CONTRACT_PATH,
            "model_mapping_sha256" =>
                CLOSURE_BOUNDARY_MODEL_MAPPING_PATH,
            "sector_mapping_sha256" =>
                CLOSURE_BOUNDARY_SECTOR_MAPPING_PATH,
            "valuation_contract_sha256" =>
                CLOSURE_BOUNDARY_VALUATION_CONTRACT_PATH,
            "final_use_contract_sha256" =>
                CLOSURE_BOUNDARY_FINAL_USE_CONTRACT_PATH,
            "supply_fixture_sha256" => joinpath(
                CLOSURE_BOUNDARY_SUPPLY_DIRECTORY,
                "cells.csv",
            ),
            "supply_manifest_sha256" => joinpath(
                CLOSURE_BOUNDARY_SUPPLY_DIRECTORY,
                "manifest.toml",
            ),
            "methodology_pdf_sha256" =>
                CLOSURE_BOUNDARY_METHODOLOGY_PDF_PATH,
            "methodology_receipt_sha256" =>
                CLOSURE_BOUNDARY_METHODOLOGY_RECEIPT_PATH,
        )
        contract_pins = Dict(
            String(key) => String(value)
                for (key, value) in contract["byte_pins"]
        )
        @test report.byte_pins == contract_pins
        for (pin, path) in pinned_files
            @test sha256_hex(read(path)) == contract_pins[pin]
        end

        after_manifest = TOML.parsefile(
            joinpath(CLOSURE_BOUNDARY_AFTER_DIRECTORY, "manifest.toml"),
        )
        official_manifest = TOML.parsefile(
            joinpath(CLOSURE_BOUNDARY_OFFICIAL_DIRECTORY, "manifest.toml"),
        )
        supply_manifest = TOML.parsefile(
            joinpath(CLOSURE_BOUNDARY_SUPPLY_DIRECTORY, "manifest.toml"),
        )
        for (manifest, source_key, pin) in (
                (
                    after_manifest,
                    "source_zip_sha256",
                    "after_redefinitions_source_zip_sha256",
                ),
                (
                    after_manifest,
                    "source_metadata_sha256",
                    "after_redefinitions_source_metadata_sha256",
                ),
                (
                    after_manifest,
                    "producer_use_workbook_sha256",
                    "after_redefinitions_producer_use_workbook_sha256",
                ),
                (
                    after_manifest,
                    "producer_make_workbook_sha256",
                    "after_redefinitions_producer_make_workbook_sha256",
                ),
                (
                    after_manifest,
                    "import_workbook_sha256",
                    "after_redefinitions_import_workbook_sha256",
                ),
                (
                    after_manifest,
                    "purchaser_use_workbook_sha256",
                    "after_redefinitions_purchaser_use_workbook_sha256",
                ),
                (
                    official_manifest,
                    "source_zip_sha256",
                    "official_market_share_source_zip_sha256",
                ),
                (
                    official_manifest,
                    "source_metadata_sha256",
                    "official_market_share_source_metadata_sha256",
                ),
                (
                    official_manifest,
                    "direct_workbook_sha256",
                    "official_direct_workbook_sha256",
                ),
                (
                    official_manifest,
                    "market_share_workbook_sha256",
                    "official_market_share_workbook_sha256",
                ),
            )
            @test lowercase(String(manifest[source_key])) ==
                contract_pins[pin]
        end
        table_262 = only(
            filter(
                source -> source["table_id"] == "262",
                supply_manifest["sources"],
            ),
        )
        @test lowercase(String(table_262["source_sha256"])) ==
            contract_pins["table_262_source_sha256"]

        @test contract["schema_version"] ==
            "beforeit-us-after-redefinitions-closure-boundary-candidate.v1"
        @test contract["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract["artifact_role"] ==
            "TYPED_CLOSURE_BOUNDARY_CANDIDATE_ONLY"
        @test contract["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test contract["source_year"] == 2024
        @test contract["source_industry_count"] == 71
        @test contract["source_ordinary_commodity_count"] == 71
        @test contract["model_commodity_count"] == 68
        @test contract["model_industry_count"] == 68
        @test String.(contract["closure_codes"]) ==
            CLOSURE_BOUNDARY_CODES
        @test contract["scrap_output_formula"] ==
            "h[i] = V_make[i,Used]"
        @test contract["scrap_share_formula"] == "p[i] = h[i] / g[i]"
        @test contract["nonscrap_ratio_formula"] == "r[i] = 1 - p[i]"
        @test contract["nonscrap_transform_formula"] ==
            "W = (I - diag(p))^-1 * D_core"
        @test contract["cross_archive_release_identity"] ==
            "NOT_EXTERNALLY_BOUND"
        @test contract["cross_archive_application_status"] ==
            "ARITHMETIC_DIAGNOSTIC_ONLY"
        @test contract["official_d_role"] ==
            "ROUNDED_SEPARATELY_PUBLISHED_CROSS_ARCHIVE_WITNESS_ONLY"
        @test contract["same_table_identity_role"] ==
            "V_CORE_AND_Q_CORE_DEFINE_SOURCE_IDENTITY_OFFICIAL_D_RESIDUAL_IS_LEDGERED"
        @test contract["eventual_model_transform_order"] ==
            "AGGREGATE_MAKE_OUTPUT_AND_SCRAP_TO_68_BEFORE_FORMING_P_D_AND_W"
        @test contract["aggregation_commutation_policy"] ==
            "SOURCE_FIRST_AND_AGGREGATE_FIRST_NONSCRAP_TRANSFORMS_NOT_INTERCHANGEABLE"
        @test String.(contract["promotion_blockers"]) ==
            CLOSURE_BOUNDARY_BLOCKERS
    end

    @testset "Typed source axes, closure disjointness, and masks" begin
        @test length(report.source_industry_codes) == 71
        @test report.source_ordinary_commodity_codes ==
            report.source_industry_codes
        @test length(report.model_codes) == 68
        @test report.closure_codes == CLOSURE_BOUNDARY_CODES
        @test isempty(
            intersect(Set(report.model_codes), Set(report.closure_codes)),
        )
        @test isempty(
            intersect(
                Set(report.source_industry_codes),
                Set(report.closure_codes),
            ),
        )
        @test Set(keys(report.source_industry_mapping)) ==
            Set(report.source_industry_codes)
        @test Set(values(report.source_industry_mapping)) ==
            Set(report.model_codes)

        for ledger in (report.used, report.other)
            @test ledger.intermediate_use isa
                LabeledVector{IndustryBasis}
            @test ledger.final_use isa LabeledVector{FinalUseBasis}
            @test ledger.make_by_industry isa
                LabeledVector{IndustryBasis}
            @test ledger.published_market_share isa
                LabeledVector{IndustryBasis}
            @test ledger.intermediate_use.codes ==
                report.source_industry_codes
            @test ledger.make_by_industry.codes ==
                report.source_industry_codes
            @test ledger.published_market_share.codes ==
                report.source_industry_codes
            @test length(ledger.final_use) == 20
            @test !ledger.ordinary_model_commodity
            @test !ledger.ordinary_model_producer_industry
            @test !ledger.component_split
            @test ledger.commodity_output_explicit
        end
        @test report.nonscrap.official_core_market_shares isa
            LabeledMatrix{IndustryBasis, CommodityBasis}
        @test report.nonscrap.diagnostic_nonscrap_transform isa
            LabeledMatrix{IndustryBasis, CommodityBasis}
        @test size(report.nonscrap.official_core_market_shares) ==
            (71, 71)
        @test size(report.nonscrap.diagnostic_nonscrap_transform) ==
            (71, 71)
        @test all(report.nonscrap.official_core_market_shares.explicit)
        @test !any(report.nonscrap.diagnostic_nonscrap_transform.explicit)
        @test !any(report.nonscrap.scrap_share_explicit)
        @test !any(report.nonscrap.nonscrap_ratio_explicit)
        @test all(report.nonscrap.ordinary_commodity_output_explicit)
        @test all(report.nonscrap.industry_output_explicit)

        @test count(report.used.intermediate_use_explicit) == 35
        @test count(report.used.final_use_explicit) == 12
        @test count(report.used.make_explicit) == 19
        @test count(report.used.published_market_share_explicit) == 71
        @test count(report.other.intermediate_use_explicit) == 66
        @test count(report.other.final_use_explicit) == 4
        @test count(report.other.make_explicit) == 1
        @test count(report.other.published_market_share_explicit) == 71
    end

    @testset "Signed closure ledgers and boundary witnesses" begin
        used = report.used
        other = report.other
        @test used.code == "Used"
        @test sum(used.intermediate_use.values) == 100_094.0
        @test sum(used.final_use.values) == -86_542.0
        @test sum(used.make_by_industry.values) == 13_553.0
        @test used.commodity_output == 13_553.0
        @test used.final_use["F050"] == -17_449.0
        @test sum(used.intermediate_use.values) +
            sum(used.final_use.values) - used.commodity_output == -1.0
        @test count(<(0.0), used.intermediate_use.values) == 5
        @test sum(filter(<(0.0), used.intermediate_use.values)) == -729.0
        @test count(<(0.0), used.final_use.values) == 7
        @test sum(filter(<(0.0), used.final_use.values)) == -211_701.0
        @test count(!iszero, used.make_by_industry.values) == 14
        @test count(<(0.0), used.make_by_industry.values) == 0

        @test other.code == "Other"
        @test sum(other.intermediate_use.values) == 172_632.0
        @test sum(other.final_use.values) == -166_441.0
        @test sum(other.make_by_industry.values) == 6_187.0
        @test other.commodity_output == 6_187.0
        @test other.final_use["F050"] == -369_200.0
        @test sum(other.intermediate_use.values) +
            sum(other.final_use.values) - other.commodity_output == 4.0
        @test count(<(0.0), other.intermediate_use.values) == 0
        @test count(<(0.0), other.final_use.values) == 2
        @test sum(filter(<(0.0), other.final_use.values)) == -405_401.0
        @test count(!iszero, other.make_by_industry.values) == 1

        @test isapprox(
            sum(used.published_market_share.values),
            1.0000001;
            atol = 1.0e-15,
            rtol = 0.0,
        )
        @test count(!iszero, used.published_market_share.values) == 15
        @test maximum(used.published_market_share.values) == 0.4188515
        @test used.published_market_share.codes[
            argmax(used.published_market_share.values),
        ] == "GSLG"
        @test sum(other.published_market_share.values) == 1.0
        @test count(!iszero, other.published_market_share.values) == 1
        @test other.published_market_share["GFGN"] == 1.0
        @test only_residual(
            report,
            :closure_import_boundary,
            "Used_F050",
        ).lhs == -17_449.0
        @test only_residual(
            report,
            :closure_import_boundary,
            "Other_F050",
        ).lhs == -369_200.0
        @test only_residual(
            report,
            :closure_use_output_rounding,
            "Used",
        ).lhs == -1.0
        @test only_residual(
            report,
            :closure_use_output_rounding,
            "Other",
        ).lhs == 4.0
    end

    @testset "BEA h, p, nonscrap ratio, and diagnostic W" begin
        witness = report.nonscrap
        h = witness.scrap_output.values
        g = witness.industry_output.values
        p = witness.scrap_share.values
        ratio = witness.nonscrap_ratio.values
        D = witness.official_core_market_shares.values
        W = witness.diagnostic_nonscrap_transform.values
        q = witness.ordinary_commodity_output.values

        @test witness.scrap_output.values ==
            report.used.make_by_industry.values
        @test witness.scrap_output_explicit ==
            report.used.make_explicit
        @test sum(h) == 13_553.0
        @test count(!iszero, h) == 14
        @test all(>=(0.0), h)
        @test all(>(0.0), g)
        @test p == h ./ g
        @test ratio == 1.0 .- p
        @test all(value -> 0.0 <= value < 1.0, p)
        @test all(>(0.0), ratio)
        @test maximum(p) == 0.008175911954472797
        @test witness.scrap_share.codes[argmax(p)] == "332"
        @test maximum(abs.(h .- p .* g)) <= 1.0e-10
        @test witness.ordinary_commodity_output.codes ==
            report.source_ordinary_commodity_codes
        @test sum(q) == 50_716_816.0

        @test isapprox(sum(D), 70.9999994; atol = 1.0e-12, rtol = 0.0)
        @test count(<(0.0), D) == 1
        @test minimum(D) == -1.13e-5
        @test isapprox(
            maximum(abs.(vec(sum(D; dims = 1)) .- 1.0)),
            2.9999999995311555e-7;
            atol = 1.0e-15,
            rtol = 0.0,
        )
        formula_W =
            (
            Matrix{Float64}(I, 71, 71) -
                LinearAlgebra.Diagonal(p)
        ) \ D
        @test isapprox(W, formula_W; atol = 1.0e-12, rtol = 0.0)
        @test isapprox(
            sum(W),
            71.02971261741644;
            atol = 1.0e-12,
            rtol = 0.0,
        )
        @test count(<(0.0), W) == 1
        @test minimum(W) == -1.13e-5
        @test isapprox(
            maximum(W),
            1.0018547305266363;
            atol = 1.0e-12,
            rtol = 0.0,
        )
        @test isapprox(
            maximum(abs.(vec(sum(W; dims = 1)) .- 1.0)),
            0.008109028612843794;
            atol = 1.0e-15,
            rtol = 0.0,
        )
        @test length(report.negative_core_market_share_cells) == 1
        @test length(report.negative_nonscrap_transform_cells) == 1
        @test witness.formula ==
            :inverse_one_minus_diagonal_p_times_core_d
        @test !witness.runtime_admissible
        @test !witness.applied_to_core_use
        @test !witness.applied_to_direct_requirements
        @test !witness.applied_to_output_multiplier

        o = report.other.make_by_industry.values
        core_identity_residual =
            D * q .- (ratio .* g .- o)
        used_only_output_gap = g .- W * q
        other_requirement =
            (Matrix{Float64}(I, 71, 71) - Diagonal(p)) \ o
        other_closure_residual =
            used_only_output_gap .- other_requirement
        @test isapprox(
            witness.published_core_make_identity_residual.values,
            core_identity_residual;
            atol = 1.0e-10,
            rtol = 0.0,
        )
        @test isapprox(
            witness.used_only_output_gap.values,
            used_only_output_gap;
            atol = 1.0e-10,
            rtol = 0.0,
        )
        @test isapprox(
            witness.other_nonscrap_output_requirement.values,
            other_requirement;
            atol = 1.0e-10,
            rtol = 0.0,
        )
        @test isapprox(
            witness.published_other_closure_residual.values,
            other_closure_residual;
            atol = 1.0e-10,
            rtol = 0.0,
        )
        for vector in (
                witness.published_core_make_identity_residual,
                witness.used_only_output_gap,
                witness.other_nonscrap_output_requirement,
                witness.published_other_closure_residual,
            )
            @test vector.codes == report.source_industry_codes
        end
        @test isapprox(
            sum(core_identity_residual),
            1.0964131995460775;
            atol = 1.0e-9,
            rtol = 0.0,
        )
        @test isapprox(
            sum(abs.(core_identity_residual)),
            19.094310799777304;
            atol = 1.0e-9,
            rtol = 0.0,
        )
        @test isapprox(
            maximum(abs.(core_identity_residual)),
            0.7825910001993179;
            atol = 1.0e-9,
            rtol = 0.0,
        )
        @test witness.published_core_make_identity_residual.codes[
            argmax(abs.(core_identity_residual)),
        ] == "42"
        @test isapprox(
            sum(used_only_output_gap),
            6_185.903653534562;
            atol = 1.0e-9,
            rtol = 0.0,
        )
        @test isapprox(
            sum(other_requirement),
            6_187.0;
            atol = 1.0e-9,
            rtol = 0.0,
        )
        @test count(!iszero, other_requirement) == 1
        @test isapprox(
            witness.other_nonscrap_output_requirement["GFGN"],
            6_187.0;
            atol = 1.0e-9,
            rtol = 0.0,
        )
        @test isapprox(
            sum(other_closure_residual),
            -1.0963464654378186;
            atol = 1.0e-9,
            rtol = 0.0,
        )
        @test isapprox(
            sum(abs.(other_closure_residual)),
            19.10204200799126;
            atol = 1.0e-9,
            rtol = 0.0,
        )
        @test isapprox(
            maximum(abs.(other_closure_residual)),
            0.7825910001993179;
            atol = 1.0e-9,
            rtol = 0.0,
        )
    end

    @testset "Adapter reconciliation and no-smearing witness" begin
        @test size(report.adapter_core_intermediate_use) == (68, 68)
        @test size(report.adapter_closure_intermediate_use) == (2, 68)
        @test size(report.adapter_closure_final_use) == (2, 20)
        @test size(report.adapter_closure_make) == (68, 2)
        @test sum(report.adapter_core_intermediate_use.values) ==
            21_165_843.0
        @test sum(report.adapter_closure_intermediate_use.values) ==
            272_726.0
        @test sum(report.adapter_closure_final_use.values) ==
            -252_983.0
        @test sum(report.adapter_closure_make.values) == 19_740.0
        @test report.core_identity_omission == 272_697.0
        @test report.full_identity_gap == -29.0

        adapter_residuals = filter(
            residual -> residual.family == :adapter_reconciliation,
            report.residuals,
        )
        @test length(adapter_residuals) == 6
        @test all(
            residual -> residual.lhs == residual.rhs == 0.0,
            adapter_residuals
        )
        @test !hasfield(ClosureBoundaryCandidateReport, :a)
        @test !hasfield(ClosureBoundaryCandidateReport, :beta)
        @test !report.flags[:seventy_account_runtime_expansion]
        @test !report.flags[:closure_smearing_into_core_u]
        @test !report.flags[:closure_smearing_into_a]
        @test !report.flags[:closure_smearing_into_beta]
        @test !report.flags[:generic_closure_market_share_application]
    end

    @testset "Complete controls and non-runtime classification" begin
        @test length(report.residuals) == 30
        @test residual_family_counts(report.residuals) == Dict(
            :closure_source_total => 8,
            :closure_import_boundary => 2,
            :closure_use_output_rounding => 2,
            :nonscrap_method => 5,
            :cross_archive_identity_residual => 4,
            :adapter_reconciliation => 6,
            :no_smearing_witness => 1,
            :closure_identity_witness => 2,
        )
        @test all(residual -> residual.passed, report.residuals)
        @test closure_boundary_candidate_internal_controls_pass(report)
        @test closure_boundary_candidate_controls_pass(
            report,
            CLOSURE_BOUNDARY_CONTRACT_PATH;
            after_directory = CLOSURE_BOUNDARY_AFTER_DIRECTORY,
            official_market_share_directory =
                CLOSURE_BOUNDARY_OFFICIAL_DIRECTORY,
            adapter_contract_path =
                CLOSURE_BOUNDARY_ADAPTER_CONTRACT_PATH,
            model_mapping_path = CLOSURE_BOUNDARY_MODEL_MAPPING_PATH,
            sector_mapping_path = CLOSURE_BOUNDARY_SECTOR_MAPPING_PATH,
            valuation_contract_path =
                CLOSURE_BOUNDARY_VALUATION_CONTRACT_PATH,
            final_use_contract_path =
                CLOSURE_BOUNDARY_FINAL_USE_CONTRACT_PATH,
            supply_directory = CLOSURE_BOUNDARY_SUPPLY_DIRECTORY,
            methodology_pdf_path =
                CLOSURE_BOUNDARY_METHODOLOGY_PDF_PATH,
            methodology_receipt_path =
                CLOSURE_BOUNDARY_METHODOLOGY_RECEIPT_PATH,
        )
        @test !hasmethod(
            closure_boundary_candidate_controls_pass,
            Tuple{ClosureBoundaryCandidateReport},
        )
        @test isempty(report.emitted_runtime_keys)
        @test !report.promotion_ready
        @test all(
            blocker -> blocker in report.promotion_blockers,
            CLOSURE_BOUNDARY_BLOCKERS,
        )
        @test all(
            flag -> !report.flags[flag],
            [
                :runtime_nonscrap_transformation_implemented,
                :w_runtime_admissible,
                :other_component_split,
                :used_asset_transfer_mapping,
                :current_dollar_price_quantity_decomposition,
                :quarterly_dynamic_law,
                :financial_counterpart_mapping,
                :row_adjustment_observation_operator,
                :behavioral_production_constraint_mapping,
                :double_entry_transition_tests,
                :industry_commodity_runtime_transform_selected,
                :aggregate_first_68_nonscrap_transform_built,
                :runtime_calibration_admissible,
                :calibration_dictionary_write,
                :figaro_dictionary_write,
                :parameter_write,
                :initial_conditions_write,
                :model_state_write,
                :forecast_origin_admissible,
                :balancing_applied,
                :normalization_applied,
                :clipping_applied,
                :raking_applied,
            ],
        )
        @test_throws ArgumentError materialize_closure_boundary_model_state(
            report,
        )
    end

    @testset "Adversarial in-memory transformations fail closed" begin
        mutated = deepcopy(report)
        mutated.nonscrap.scrap_output.values[1] += 1.0
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.nonscrap.scrap_share.values[1] += 0.01
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.nonscrap.nonscrap_ratio.values[1] -= 0.01
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        original_W =
            copy(mutated.nonscrap.diagnostic_nonscrap_transform.values)
        mutated.nonscrap.diagnostic_nonscrap_transform.values .=
            transpose(original_W)
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.nonscrap.official_core_market_shares.values[:, [1, 2]] .=
            mutated.nonscrap.official_core_market_shares.values[:, [2, 1]]
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.nonscrap.official_core_market_shares.explicit[1, 1] =
            false
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.nonscrap.published_core_make_identity_residual.values[1] +=
            1.0
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.nonscrap.used_only_output_gap.values[1] += 1.0
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.nonscrap.other_nonscrap_output_requirement.values[1] +=
            1.0
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.nonscrap.published_other_closure_residual.values[1] +=
            1.0
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.used.final_use.values[
            mutated.used.final_use.index["F050"],
        ] *= -1.0
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.other.published_market_share.values .= 0.0
        mutated.other.published_market_share.values[
            mutated.other.published_market_share.index["GSLG"],
        ] = 1.0
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.adapter_core_intermediate_use.values[1, 1] += 1.0
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.flags[:seventy_account_runtime_expansion] = true
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        mutated.flags[:closure_smearing_into_beta] = true
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        push!(mutated.emitted_runtime_keys, "beta")
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        popfirst!(mutated.promotion_blockers)
        @test !closure_boundary_candidate_internal_controls_pass(mutated)

        mutated = deepcopy(report)
        reverse!(mutated.closure_codes)
        @test !closure_boundary_candidate_internal_controls_pass(mutated)
    end

    @testset "Every local source-byte mutation fails the public gate" begin
        bad_contract = append_one_byte(
            copied_file(CLOSURE_BOUNDARY_CONTRACT_PATH),
        )
        @test !closure_boundary_candidate_controls_pass(
            report,
            bad_contract,
        )

        bad_after = copied_fixture(CLOSURE_BOUNDARY_AFTER_DIRECTORY)
        append_one_byte(joinpath(bad_after, "cells.csv"))
        @test !closure_boundary_candidate_controls_pass(
            report,
            CLOSURE_BOUNDARY_CONTRACT_PATH;
            after_directory = bad_after,
        )
        bad_after = copied_fixture(CLOSURE_BOUNDARY_AFTER_DIRECTORY)
        append_one_byte(joinpath(bad_after, "manifest.toml"))
        @test !closure_boundary_candidate_controls_pass(
            report,
            CLOSURE_BOUNDARY_CONTRACT_PATH;
            after_directory = bad_after,
        )

        bad_official =
            copied_fixture(CLOSURE_BOUNDARY_OFFICIAL_DIRECTORY)
        append_one_byte(joinpath(bad_official, "cells.csv"))
        @test !closure_boundary_candidate_controls_pass(
            report,
            CLOSURE_BOUNDARY_CONTRACT_PATH;
            official_market_share_directory = bad_official,
        )
        bad_official =
            copied_fixture(CLOSURE_BOUNDARY_OFFICIAL_DIRECTORY)
        append_one_byte(joinpath(bad_official, "manifest.toml"))
        @test !closure_boundary_candidate_controls_pass(
            report,
            CLOSURE_BOUNDARY_CONTRACT_PATH;
            official_market_share_directory = bad_official,
        )

        for (path, keyword) in (
                (
                    CLOSURE_BOUNDARY_ADAPTER_CONTRACT_PATH,
                    :adapter_contract_path,
                ),
                (
                    CLOSURE_BOUNDARY_MODEL_MAPPING_PATH,
                    :model_mapping_path,
                ),
                (
                    CLOSURE_BOUNDARY_SECTOR_MAPPING_PATH,
                    :sector_mapping_path,
                ),
                (
                    CLOSURE_BOUNDARY_VALUATION_CONTRACT_PATH,
                    :valuation_contract_path,
                ),
                (
                    CLOSURE_BOUNDARY_FINAL_USE_CONTRACT_PATH,
                    :final_use_contract_path,
                ),
                (
                    CLOSURE_BOUNDARY_METHODOLOGY_PDF_PATH,
                    :methodology_pdf_path,
                ),
                (
                    CLOSURE_BOUNDARY_METHODOLOGY_RECEIPT_PATH,
                    :methodology_receipt_path,
                ),
            )
            bad_path = append_one_byte(copied_file(path))
            keywords = NamedTuple{(keyword,)}((bad_path,))
            @test !closure_boundary_candidate_controls_pass(
                report,
                CLOSURE_BOUNDARY_CONTRACT_PATH;
                keywords...,
            )
        end

        bad_supply =
            copied_fixture(CLOSURE_BOUNDARY_SUPPLY_DIRECTORY)
        append_one_byte(joinpath(bad_supply, "cells.csv"))
        @test !closure_boundary_candidate_controls_pass(
            report,
            CLOSURE_BOUNDARY_CONTRACT_PATH;
            supply_directory = bad_supply,
        )
        bad_supply =
            copied_fixture(CLOSURE_BOUNDARY_SUPPLY_DIRECTORY)
        append_one_byte(joinpath(bad_supply, "manifest.toml"))
        @test !closure_boundary_candidate_controls_pass(
            report,
            CLOSURE_BOUNDARY_CONTRACT_PATH;
            supply_directory = bad_supply,
        )
    end
end
