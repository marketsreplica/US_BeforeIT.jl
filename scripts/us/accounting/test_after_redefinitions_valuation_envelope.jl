using LinearAlgebra
using SHA
using Statistics
using Test
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsValuationEnvelope.jl"))

using .USAfterRedefinitionsCommonBasis
using .USAfterRedefinitionsModelCore
using .USAfterRedefinitionsValuationEnvelope
using .USSupplyMakeDiagnostics

const VALUATION_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_valuation_envelope.toml")
const VALUATION_SUPPLY_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "bea_2024_approved")
const VALUATION_AFTER_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const VALUATION_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const VALUATION_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const VALUATION_COMPONENT_CODES = [
    "T007",
    "MCIF",
    "MADJ",
    "T013",
    "Trade",
    "Trans",
    "T014",
    "TOP",
    "MDTY",
    "SUB",
    "T015",
    "T016",
]
const VALUATION_BLOCKER_PREFIX = [
    "MULTI_ARCHIVE_RELEASE_IDENTITY_NOT_EXTERNALLY_BOUND",
    "COMMODITY_REDEFINITION_REDISTRIBUTION_NOT_ALLOCATED",
    "MARGIN_TRANSPORT_USE_CELL_ALLOCATION_NOT_PROVIDED",
    "PRODUCT_TAX_USE_CELL_ALLOCATION_NOT_PROVIDED",
    "PROPORTIONAL_OR_SCALAR_VALUATION_BRIDGE_NOT_APPROVED",
    "OBSERVED_TAX_AND_ZERO_TAX_VARIANTS_NOT_TRANSITION_TESTED",
]

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function independently_aggregate_matrix(
        values,
        explicit,
        source_codes,
        target_codes,
        mapping,
    )
    aggregated_values = zeros(length(target_codes), size(values, 2))
    aggregated_explicit = falses(size(aggregated_values))
    for (target_position, target_code) in pairs(target_codes)
        source_positions =
            findall(code -> mapping[code] == target_code, source_codes)
        aggregated_values[target_position, :] =
            vec(sum(values[source_positions, :]; dims = 1))
        aggregated_explicit[target_position, :] =
            vec(any(explicit[source_positions, :]; dims = 1))
    end
    return (;
        values = aggregated_values,
        explicit = BitMatrix(aggregated_explicit),
    )
end

function independently_aggregate_vector(
        values,
        explicit,
        source_codes,
        target_codes,
        mapping,
    )
    aggregated_values = zeros(length(target_codes))
    aggregated_explicit = falses(length(target_codes))
    for (target_position, target_code) in pairs(target_codes)
        source_positions =
            findall(code -> mapping[code] == target_code, source_codes)
        aggregated_values[target_position] = sum(values[source_positions])
        aggregated_explicit[target_position] = any(explicit[source_positions])
    end
    return (;
        values = aggregated_values,
        explicit = BitVector(aggregated_explicit),
    )
end

function residual_family_counts(residuals)
    return Dict(
        family => count(residual -> residual.family == family, residuals)
            for family in unique(residual.family for residual in residuals)
    )
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
    target_directory = mktempdir()
    target_path = joinpath(target_directory, basename(source_path))
    cp(source_path, target_path)
    return target_path
end

function append_newline(path)
    write(path, read(path, String) * "\n")
    return path
end

@testset "BEA after-redefinitions valuation envelope" begin
    supply_fixture =
        load_canonical_fixture(VALUATION_SUPPLY_FIXTURE_DIRECTORY)
    after_fixture = load_after_redefinitions_fixture(
        VALUATION_AFTER_FIXTURE_DIRECTORY,
    )
    model_core = build_model_core_aggregation(
        after_fixture,
        VALUATION_MODEL_MAPPING_PATH;
        sector_mapping_path = VALUATION_SECTOR_MAPPING_PATH,
    )
    report = build_valuation_envelope(
        VALUATION_CONTRACT_PATH;
        supply_directory = VALUATION_SUPPLY_FIXTURE_DIRECTORY,
        after_directory = VALUATION_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = VALUATION_MODEL_MAPPING_PATH,
        sector_mapping_path = VALUATION_SECTOR_MAPPING_PATH,
    )
    contract = TOML.parsefile(VALUATION_CONTRACT_PATH)

    @testset "Pinned sources and research-only policy" begin
        @test sha256_hex(read(VALUATION_CONTRACT_PATH)) ==
            "110f82037e45e1de3ce4f5a1df2b7982d064e90a9323f255c7441452fa6d2ede"
        @test sha256_hex(
            read(
                joinpath(
                    VALUATION_SUPPLY_FIXTURE_DIRECTORY,
                    "cells.csv",
                ),
            ),
        ) ==
            "c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0"
        @test sha256_hex(
            read(
                joinpath(
                    VALUATION_SUPPLY_FIXTURE_DIRECTORY,
                    "manifest.toml",
                ),
            ),
        ) ==
            "564a99ec2011b2566b8951e9eecb4737c0bfbc88f1e077b1eaf596af9894575c"
        @test sha256_hex(
            read(joinpath(VALUATION_AFTER_FIXTURE_DIRECTORY, "cells.csv")),
        ) ==
            "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac"
        @test sha256_hex(
            read(
                joinpath(
                    VALUATION_AFTER_FIXTURE_DIRECTORY,
                    "manifest.toml",
                ),
            ),
        ) ==
            "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030"
        @test sha256_hex(read(VALUATION_MODEL_MAPPING_PATH)) ==
            "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c"
        @test sha256_hex(read(VALUATION_SECTOR_MAPPING_PATH)) ==
            "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f"

        @test contract["schema_version"] ==
            "beforeit-us-after-redefinitions-valuation-envelope.v1"
        @test contract["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract["promotion_status"] == "RESEARCH_ONLY_NOT_PROMOTED"
        @test contract["source_year"] == 2024
        @test String.(contract["component_codes"]) ==
            VALUATION_COMPONENT_CODES
        @test length(contract["component_meanings"]) == 12
        @test String.(contract["row_equations"]) == [
            "T007 + MCIF + MADJ = T013",
            "Trade + Trans = T014",
            "TOP + MDTY + SUB = T015",
            "T013 + T014 + T015 = T016",
        ]
        @test contract["cross_archive_release_identity"] ==
            "NOT_EXTERNALLY_BOUND"
        @test contract["cell_allocation_policy"] == "NONE"
        @test contract["tax_variant_effect"] == "NONE_DIAGNOSTIC_ONLY"
        @test contract["accounting_gate_effect"] == "NONE"
        @test !contract["forecast_origin_admissible"]
        @test !contract["model_state_write"]
        for flag in (
                "margin_allocation_applied",
                "tax_allocation_applied",
                "redefinition_allocation_applied",
                "domestic_use_subtraction_applied",
                "balancing_applied",
                "clipping_applied",
            )
            @test !contract[flag]
        end

        @test report.year == 2024
        @test report.contract_sha256 ==
            sha256_hex(read(VALUATION_CONTRACT_PATH))
        @test report.supply_fixture_sha256 ==
            sha256_hex(
            read(
                joinpath(
                    VALUATION_SUPPLY_FIXTURE_DIRECTORY,
                    "cells.csv",
                ),
            ),
        )
        @test report.supply_manifest_sha256 ==
            sha256_hex(
            read(
                joinpath(
                    VALUATION_SUPPLY_FIXTURE_DIRECTORY,
                    "manifest.toml",
                ),
            ),
        )
        @test report.supply_table_source_sha256 ==
            "91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8"
        @test report.after_fixture_sha256 ==
            sha256_hex(
            read(joinpath(VALUATION_AFTER_FIXTURE_DIRECTORY, "cells.csv")),
        )
        @test report.after_manifest_sha256 ==
            sha256_hex(
            read(
                joinpath(
                    VALUATION_AFTER_FIXTURE_DIRECTORY,
                    "manifest.toml",
                ),
            ),
        )
        @test report.after_source_zip_sha256 ==
            "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
        @test report.model_mapping_sha256 ==
            sha256_hex(read(VALUATION_MODEL_MAPPING_PATH))
        @test report.sector_mapping_sha256 ==
            sha256_hex(read(VALUATION_SECTOR_MAPPING_PATH))
        @test report.supply_source_status == "APPROVED_ARCHIVED"
        @test report.after_source_status ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test report.cross_archive_release_identity ==
            :not_externally_bound
        @test report.transformation ==
            :code_keyed_valuation_envelope_with_unallocated_redefinition_residual
        @test report.tax_variant_effect == :none_diagnostic_only
        @test !report.margin_allocation_applied
        @test !report.tax_allocation_applied
        @test !report.redefinition_allocation_applied
        @test !report.domestic_use_subtraction_applied
        @test !report.balancing_applied
        @test !report.clipping_applied
        @test !report.model_state_write
        @test report.accounting_gate_effect == :none
        @test !report.forecast_origin_admissible
        @test !report.promotion_ready
        @test report.promotion_blockers[1:6] == VALUATION_BLOCKER_PREFIX
        @test report.promotion_blockers[7:end] ==
            model_core.promotion_blockers
        @test length(report.promotion_blockers) == 19
        @test valuation_envelope_internal_controls_pass(report)
        @test valuation_envelope_controls_pass(
            report,
            VALUATION_CONTRACT_PATH;
            supply_directory = VALUATION_SUPPLY_FIXTURE_DIRECTORY,
            after_directory = VALUATION_AFTER_FIXTURE_DIRECTORY,
            model_mapping_path = VALUATION_MODEL_MAPPING_PATH,
            sector_mapping_path = VALUATION_SECTOR_MAPPING_PATH,
        )
        @test_throws MethodError valuation_envelope_controls_pass(report)
    end

    @testset "Independent source projection, aggregation, and masks" begin
        source_codes =
            copy(after_fixture.producer_commodity_output_make.codes)
        expected_source_values = Float64[
            cell_value(supply_fixture.supply, code, component)
                for code in source_codes,
                component in VALUATION_COMPONENT_CODES
        ]
        expected_source_explicit = BitMatrix(
            [
                has_cell(supply_fixture.supply, code, component)
                    for code in source_codes,
                    component in VALUATION_COMPONENT_CODES
            ],
        )
        expected_model = independently_aggregate_matrix(
            expected_source_values,
            expected_source_explicit,
            source_codes,
            model_core.model_codes,
            model_core.source_commodity_mapping,
        )
        expected_closure = independently_aggregate_matrix(
            expected_source_values,
            expected_source_explicit,
            source_codes,
            model_core.closure_codes,
            model_core.source_commodity_mapping,
        )
        expected_after_values = Float64[
            after_fixture.producer_commodity_output_make[code]
                for code in source_codes
        ]
        expected_after_explicit = BitVector(
            after_fixture.source_explicit[
                "producer_make_commodity_output_2024",
            ][:, 1],
        )
        expected_model_after = independently_aggregate_vector(
            expected_after_values,
            expected_after_explicit,
            source_codes,
            model_core.model_codes,
            model_core.source_commodity_mapping,
        )
        expected_closure_after = independently_aggregate_vector(
            expected_after_values,
            expected_after_explicit,
            source_codes,
            model_core.closure_codes,
            model_core.source_commodity_mapping,
        )

        @test report.source_commodity_codes == source_codes
        @test report.model_codes == model_core.model_codes
        @test report.closure_codes == ["Used", "Other"]
        @test size(report.source_supply_components.values) == (73, 12)
        @test size(report.model_supply_components.values) == (68, 12)
        @test size(report.closure_supply_components.values) == (2, 12)
        @test report.source_supply_components.row_codes == source_codes
        @test report.source_supply_components.column_codes ==
            VALUATION_COMPONENT_CODES
        @test report.source_supply_components.values ==
            expected_source_values
        @test report.source_supply_components.explicit ==
            expected_source_explicit
        @test report.model_supply_components.values ==
            expected_model.values
        @test report.model_supply_components.explicit ==
            expected_model.explicit
        @test report.closure_supply_components.values ==
            expected_closure.values
        @test report.closure_supply_components.explicit ==
            expected_closure.explicit
        @test count(report.source_supply_components.explicit) == 672
        @test count(report.model_supply_components.explicit) == 636
        @test count(report.closure_supply_components.explicit) == 18

        explicit_zero = findfirst(
            (expected_source_values .== 0.0) .&
                expected_source_explicit,
        )
        omitted_zero = findfirst(
            (expected_source_values .== 0.0) .&
                .!expected_source_explicit,
        )
        @test !isnothing(explicit_zero)
        @test !isnothing(omitted_zero)
        @test expected_source_values[explicit_zero] ==
            expected_source_values[omitted_zero] == 0.0
        @test expected_source_explicit[explicit_zero]
        @test !expected_source_explicit[omitted_zero]

        @test report.source_after_producer_output.values ==
            expected_after_values
        @test report.source_after_producer_output_explicit ==
            expected_after_explicit
        @test report.model_after_producer_output.values ==
            expected_model_after.values
        @test report.model_after_producer_output_explicit ==
            expected_model_after.explicit
        @test report.closure_after_producer_output.values ==
            expected_closure_after.values
        @test report.closure_after_producer_output_explicit ==
            expected_closure_after.explicit

        component_position = Dict(
            code => position
                for (position, code) in pairs(VALUATION_COMPONENT_CODES)
        )
        expected_implied =
            expected_source_values[:, component_position["T007"]] +
            expected_source_values[:, component_position["T015"]]
        expected_redistribution =
            expected_after_values - expected_implied
        expected_model_implied = independently_aggregate_vector(
            expected_implied,
            trues(length(source_codes)),
            source_codes,
            model_core.model_codes,
            model_core.source_commodity_mapping,
        )
        expected_closure_implied = independently_aggregate_vector(
            expected_implied,
            trues(length(source_codes)),
            source_codes,
            model_core.closure_codes,
            model_core.source_commodity_mapping,
        )
        expected_model_redistribution = independently_aggregate_vector(
            expected_redistribution,
            trues(length(source_codes)),
            source_codes,
            model_core.model_codes,
            model_core.source_commodity_mapping,
        )
        expected_closure_redistribution = independently_aggregate_vector(
            expected_redistribution,
            trues(length(source_codes)),
            source_codes,
            model_core.closure_codes,
            model_core.source_commodity_mapping,
        )
        @test report.source_implied_pre_redefinitions_producer_output.values ==
            expected_implied
        @test report.model_implied_pre_redefinitions_producer_output.values ==
            expected_model_implied.values
        @test report.closure_implied_pre_redefinitions_producer_output.values ==
            expected_closure_implied.values
        @test report.source_redefinition_redistribution.values ==
            expected_redistribution
        @test report.model_redefinition_redistribution.values ==
            expected_model_redistribution.values
        @test report.closure_redefinition_redistribution.values ==
            expected_closure_redistribution.values
    end

    @testset "Valuation identities and redistribution witness" begin
        expected_cell_sums = Dict(
            "T007" => 49_726_234.0,
            "MCIF" => 3_712_328.0,
            "MADJ" => -30_786.0,
            "T013" => 53_407_773.0,
            "Trade" => -1.0,
            "Trans" => -1.0,
            "T014" => -3.0,
            "TOP" => 1_016_094.0,
            "MDTY" => 83_586.0,
            "SUB" => -89_357.0,
            "T015" => 1_010_322.0,
            "T016" => 54_418_090.0,
        )
        expected_published_controls = Dict(
            "T007" => 49_726_230.0,
            "MCIF" => 3_712_324.0,
            "MADJ" => -30_786.0,
            "T013" => 53_407_768.0,
            "Trade" => -1.0,
            "Trans" => 0.0,
            "T014" => -1.0,
            "TOP" => 1_016_095.0,
            "MDTY" => 83_587.0,
            "SUB" => -89_356.0,
            "T015" => 1_010_326.0,
            "T016" => 54_418_092.0,
        )
        @test report.component_cell_sums == expected_cell_sums
        @test report.component_published_controls ==
            expected_published_controls
        for component in VALUATION_COMPONENT_CODES
            position =
                report.source_supply_components.column_index[component]
            @test sum(
                report.source_supply_components.values[:, position],
            ) == expected_cell_sums[component]
            @test cell_value(
                supply_fixture.supply,
                "T017",
                component;
                required = true,
            ) == expected_published_controls[component]
        end

        components = report.source_supply_components
        for position in axes(components.values, 1)
            value(code) =
                components.values[position, components.column_index[code]]
            @test abs(
                value("T007") + value("MCIF") + value("MADJ") -
                    value("T013"),
            ) <= 2.0
            @test abs(value("Trade") + value("Trans") - value("T014")) <=
                1.5
            @test abs(
                value("TOP") + value("MDTY") + value("SUB") -
                    value("T015"),
            ) <= 2.0
            @test abs(
                value("T013") + value("T014") + value("T015") -
                    value("T016"),
            ) <= 2.0
        end

        @test sum(report.source_after_producer_output.values) ==
            50_736_556.0
        @test expected_cell_sums["T007"] + expected_cell_sums["T015"] ==
            50_736_556.0
        @test after_fixture.producer_make_output_grand_control ==
            50_736_556.0
        @test expected_published_controls["T007"] +
            expected_published_controls["T015"] == 50_736_556.0
        @test sum(report.model_after_producer_output.values) ==
            50_716_816.0
        @test sum(report.closure_after_producer_output.values) == 19_740.0
        @test sum(
            report.model_implied_pre_redefinitions_producer_output.values,
        ) == 50_693_465.0
        @test sum(
            report.closure_implied_pre_redefinitions_producer_output.values,
        ) == 43_091.0

        redistribution =
            report.source_redefinition_redistribution.values
        @test report.signed_redefinition_redistribution ==
            sum(redistribution) == 0.0
        @test report.absolute_redefinition_redistribution ==
            sum(abs, redistribution) == 1_254_404.0
        @test report.redefinition_redistribution_frobenius ≈
            norm(redistribution) ≈ 412_844.9769053754
        @test report.producer_pre_redefinitions_cell_correlation ≈
            cor(
                report.source_after_producer_output.values,
                report.source_implied_pre_redefinitions_producer_output.values,
            ) ≈ 0.9981283833867927
        @test count(value -> value < 0.0, redistribution) == 32
        @test count(iszero, redistribution) == 31
        @test count(value -> value > 0.0, redistribution) == 10
        @test sum(
            report.source_redefinition_redistribution[code]
                for code in ("441", "445", "452", "4A0")
        ) == 312_316.0
        @test sum(report.model_redefinition_redistribution.values) ==
            23_351.0
        @test sum(report.closure_redefinition_redistribution.values) ==
            -23_351.0
        @test report.closure_redefinition_redistribution["Used"] ==
            -23_351.0
        @test report.closure_redefinition_redistribution["Other"] == 0.0

        maximum_cell =
            report.maximum_redefinition_redistribution_cell
        @test maximum_cell.commodity_code == "42"
        @test maximum_cell.after_redefinitions_producer_output ==
            2_878_927.0
        @test maximum_cell.pre_redefinitions_basic_output ==
            2_563_701.0
        @test maximum_cell.net_product_tax == 345.0
        @test maximum_cell.redistribution == 314_881.0
        @test abs(maximum_cell.redistribution) ==
            maximum(abs, redistribution)

        negative_counts = Dict(
            code => count(
                    value -> value < 0.0,
                    components.values[:, components.column_index[code]],
                ) for code in VALUATION_COMPONENT_CODES
        )
        @test negative_counts == Dict(
            "T007" => 0,
            "MCIF" => 0,
            "MADJ" => 6,
            "T013" => 0,
            "Trade" => 5,
            "Trans" => 5,
            "T014" => 10,
            "TOP" => 0,
            "MDTY" => 0,
            "SUB" => 13,
            "T015" => 4,
            "T016" => 0,
        )
        @test length(report.negative_supply_component_cells) == 43
        @test length(
            report.negative_redefinition_redistribution_cells,
        ) == 32
    end

    @testset "Tax controls remain unallocated diagnostics" begin
        observed = report.observed_tax_variant
        zero = report.zero_tax_variant
        @test observed.name == :observed
        @test observed.source_semantics ==
            :table_262_t015_current_vintage_control
        @test observed.use_cell_allocation == :none
        @test observed.commodity_net_product_tax.codes ==
            report.model_codes
        @test observed.commodity_net_product_tax.values ==
            report.model_supply_components.values[
            :,
            report.model_supply_components.column_index["T015"],
        ]
        @test sum(observed.commodity_net_product_tax.values) == 986_971.0
        @test sum(
            report.closure_supply_components.values[
                :,
                report.closure_supply_components.column_index["T015"],
            ],
        ) == 23_351.0
        @test sum(observed.commodity_net_product_tax.values) +
            sum(
            report.closure_supply_components.values[
                :,
                report.closure_supply_components.column_index["T015"],
            ],
        ) == 1_010_322.0

        @test zero.name == :explicit_zero
        @test zero.source_semantics == :policy_zero_not_observation
        @test zero.use_cell_allocation == :none
        @test zero.commodity_net_product_tax.codes == report.model_codes
        @test all(iszero, zero.commodity_net_product_tax.values)
        for variant in (observed, zero)
            @test !variant.allocation_applied
            @test !variant.model_state_write
            @test !variant.forecast_origin_admissible
            @test !variant.promotion_ready
        end
    end

    @testset "Residual inventory and rounding envelope" begin
        @test length(report.residuals) == 324
        @test all(residual.passed for residual in report.residuals)
        @test residual_family_counts(report.residuals) == Dict(
            :valuation_supply_basic_identity => 73,
            :valuation_margin_identity => 73,
            :valuation_product_tax_identity => 73,
            :valuation_purchaser_supply_identity => 73,
            :valuation_component_published_control => 12,
            :valuation_after_output_published_control => 1,
            :valuation_published_producer_basic_identity => 1,
            :valuation_cell_sum_producer_basic_identity => 1,
            :valuation_redefinition_zero_sum => 1,
            :valuation_component_aggregation => 12,
            :valuation_after_output_aggregation => 1,
            :valuation_implied_output_aggregation => 1,
            :valuation_redistribution_aggregation => 1,
            :valuation_component_block_assembly => 1,
        )
        @test maximum_residual_ratio(
            report,
            :valuation_supply_basic_identity,
        ) ≈ 0.5
        @test maximum_residual_ratio(
            report,
            :valuation_margin_identity,
        ) ≈ 2 / 3
        @test maximum_residual_ratio(
            report,
            :valuation_product_tax_identity,
        ) ≈ 0.5
        @test maximum_residual_ratio(
            report,
            :valuation_purchaser_supply_identity,
        ) ≈ 0.5
        @test maximum_residual_ratio(
            report,
            :valuation_component_published_control,
        ) ≈ 5 / 37
        for family in (
                :valuation_after_output_published_control,
                :valuation_published_producer_basic_identity,
                :valuation_cell_sum_producer_basic_identity,
                :valuation_redefinition_zero_sum,
                :valuation_component_aggregation,
                :valuation_after_output_aggregation,
                :valuation_implied_output_aggregation,
                :valuation_redistribution_aggregation,
                :valuation_component_block_assembly,
            )
            @test maximum_residual_ratio(report, family) == 0.0
        end
    end

    @testset "Stale reports and changed source bytes fail closed" begin
        stale_source_value = deepcopy(report)
        stale_source_value.source_supply_components.values[1, 1] += 1.0
        @test !valuation_envelope_internal_controls_pass(stale_source_value)
        @test !valuation_envelope_controls_pass(
            stale_source_value,
            VALUATION_CONTRACT_PATH,
        )

        compensated_optional_component = deepcopy(report)
        mcif_position =
            compensated_optional_component.source_supply_components.column_index[
            "MCIF",
        ]
        compensated_optional_component.source_supply_components.values[
            1,
            mcif_position,
        ] += 1.0
        compensated_optional_component.source_supply_components.values[
            2,
            mcif_position,
        ] -= 1.0
        @test valuation_envelope_internal_controls_pass(
            compensated_optional_component,
        )
        @test !valuation_envelope_controls_pass(
            compensated_optional_component,
            VALUATION_CONTRACT_PATH,
        )

        stale_mask = deepcopy(report)
        stale_mask.source_supply_components.explicit[1, 1] =
            !stale_mask.source_supply_components.explicit[1, 1]
        @test valuation_envelope_internal_controls_pass(stale_mask)
        @test !valuation_envelope_controls_pass(
            stale_mask,
            VALUATION_CONTRACT_PATH,
        )

        stale_tax_variant = deepcopy(report)
        stale_tax_variant.observed_tax_variant.commodity_net_product_tax.values[
            1,
        ] += 1.0
        @test !valuation_envelope_internal_controls_pass(stale_tax_variant)
        @test !valuation_envelope_controls_pass(
            stale_tax_variant,
            VALUATION_CONTRACT_PATH,
        )

        stale_residuals = deepcopy(report)
        pop!(stale_residuals.residuals)
        @test !valuation_envelope_internal_controls_pass(stale_residuals)

        stale_blockers = deepcopy(report)
        empty!(stale_blockers.promotion_blockers)
        @test !valuation_envelope_internal_controls_pass(stale_blockers)

        changed_contract_path = copied_file(VALUATION_CONTRACT_PATH)
        append_newline(changed_contract_path)
        @test_throws ArgumentError build_valuation_envelope(
            changed_contract_path,
        )
        @test !valuation_envelope_controls_pass(
            report,
            changed_contract_path,
        )

        changed_supply_cells =
            copied_fixture(VALUATION_SUPPLY_FIXTURE_DIRECTORY)
        append_newline(joinpath(changed_supply_cells, "cells.csv"))
        @test_throws ArgumentError build_valuation_envelope(
            VALUATION_CONTRACT_PATH;
            supply_directory = changed_supply_cells,
        )
        @test !valuation_envelope_controls_pass(
            report,
            VALUATION_CONTRACT_PATH;
            supply_directory = changed_supply_cells,
        )

        changed_supply_manifest =
            copied_fixture(VALUATION_SUPPLY_FIXTURE_DIRECTORY)
        append_newline(joinpath(changed_supply_manifest, "manifest.toml"))
        @test_throws ArgumentError build_valuation_envelope(
            VALUATION_CONTRACT_PATH;
            supply_directory = changed_supply_manifest,
        )

        changed_after_cells =
            copied_fixture(VALUATION_AFTER_FIXTURE_DIRECTORY)
        append_newline(joinpath(changed_after_cells, "cells.csv"))
        @test_throws ArgumentError build_valuation_envelope(
            VALUATION_CONTRACT_PATH;
            after_directory = changed_after_cells,
        )
        @test !valuation_envelope_controls_pass(
            report,
            VALUATION_CONTRACT_PATH;
            after_directory = changed_after_cells,
        )

        changed_after_manifest =
            copied_fixture(VALUATION_AFTER_FIXTURE_DIRECTORY)
        append_newline(joinpath(changed_after_manifest, "manifest.toml"))
        @test_throws ArgumentError build_valuation_envelope(
            VALUATION_CONTRACT_PATH;
            after_directory = changed_after_manifest,
        )

        changed_model_mapping =
            copied_file(VALUATION_MODEL_MAPPING_PATH)
        append_newline(changed_model_mapping)
        @test_throws ArgumentError build_valuation_envelope(
            VALUATION_CONTRACT_PATH;
            model_mapping_path = changed_model_mapping,
        )
        @test !valuation_envelope_controls_pass(
            report,
            VALUATION_CONTRACT_PATH;
            model_mapping_path = changed_model_mapping,
        )

        changed_sector_mapping =
            copied_file(VALUATION_SECTOR_MAPPING_PATH)
        append_newline(changed_sector_mapping)
        @test_throws ArgumentError build_valuation_envelope(
            VALUATION_CONTRACT_PATH;
            sector_mapping_path = changed_sector_mapping,
        )
        @test !valuation_envelope_controls_pass(
            report,
            VALUATION_CONTRACT_PATH;
            sector_mapping_path = changed_sector_mapping,
        )

        source = read(
            joinpath(
                @__DIR__,
                "USAfterRedefinitionsValuationEnvelope.jl",
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
