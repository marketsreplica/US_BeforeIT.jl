module USAfterRedefinitionsValuationEnvelope

using LinearAlgebra
using SHA
using Statistics
using TOML

using ..USSupplyMakeDiagnostics:
    AxisBasis,
    CommodityBasis,
    ControlResidual,
    LabeledMatrix,
    LabeledVector,
    cell_value,
    has_cell,
    load_canonical_fixture,
    published_rounding_tolerance
using ..USSymmetricSupplyUse: NegativeCell, negative_cells
using ..USAfterRedefinitionsCommonBasis:
    load_after_redefinitions_fixture
using ..USAfterRedefinitionsModelCore:
    build_model_core_aggregation,
    model_core_controls_pass

export TaxControlVariant,
    ValuationComponentBasis,
    ValuationEnvelopeReport,
    ValuationRedistributionCell,
    build_valuation_envelope,
    valuation_envelope_controls_pass,
    valuation_envelope_internal_controls_pass

struct ValuationComponentBasis <: AxisBasis end

const CONTRACT_SCHEMA =
    "beforeit-us-after-redefinitions-valuation-envelope.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_CONTRACT_SHA256 =
    "110f82037e45e1de3ce4f5a1df2b7982d064e90a9323f255c7441452fa6d2ede"
const APPROVED_SUPPLY_FIXTURE_SHA256 =
    "c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0"
const APPROVED_SUPPLY_MANIFEST_SHA256 =
    "564a99ec2011b2566b8951e9eecb4737c0bfbc88f1e077b1eaf596af9894575c"
const APPROVED_SUPPLY_TABLE_SHA256 =
    "91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8"
const APPROVED_AFTER_FIXTURE_SHA256 =
    "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac"
const APPROVED_AFTER_MANIFEST_SHA256 =
    "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030"
const APPROVED_AFTER_SOURCE_ZIP_SHA256 =
    "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
const APPROVED_MODEL_MAPPING_SHA256 =
    "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c"
const APPROVED_SECTOR_MAPPING_SHA256 =
    "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f"
const COMPONENT_CODES = [
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
const EXPECTED_BLOCKER_PREFIX = [
    "MULTI_ARCHIVE_RELEASE_IDENTITY_NOT_EXTERNALLY_BOUND",
    "COMMODITY_REDEFINITION_REDISTRIBUTION_NOT_ALLOCATED",
    "MARGIN_TRANSPORT_USE_CELL_ALLOCATION_NOT_PROVIDED",
    "PRODUCT_TAX_USE_CELL_ALLOCATION_NOT_PROVIDED",
    "PROPORTIONAL_OR_SCALAR_VALUATION_BRIDGE_NOT_APPROVED",
    "OBSERVED_TAX_AND_ZERO_TAX_VARIANTS_NOT_TRANSITION_TESTED",
]
const NUMERICAL_TOLERANCE_MILLIONS_USD = 1.0e-6

const DEFAULT_SUPPLY_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_approved",
)
const DEFAULT_AFTER_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const DEFAULT_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const DEFAULT_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

struct ValuationRedistributionCell
    commodity_code::String
    after_redefinitions_producer_output::Float64
    pre_redefinitions_basic_output::Float64
    net_product_tax::Float64
    redistribution::Float64
end

"""
Commodity-level tax control for one research variant.

The observed variant retains Table 262 `T015`; the explicit-zero variant is a
policy counterfactual. Neither variant allocates tax to intermediate or final
use cells, writes model state, or admits a forecast origin.
"""
struct TaxControlVariant
    name::Symbol
    commodity_net_product_tax::LabeledVector{CommodityBasis}
    source_semantics::Symbol
    use_cell_allocation::Symbol
    allocation_applied::Bool
    model_state_write::Bool
    forecast_origin_admissible::Bool
    promotion_ready::Bool
end

"""
Research-only valuation envelope joining two separately captured 2024 BEA
systems.

Table 262 supplies basic-price output, imports, margins, taxes, subsidies, and
purchasers-price supply. The after-redefinitions workbook supplies
producer-price commodity output. Their grand totals satisfy

    producer output = domestic basic output + net product tax,

but the commodity rows differ by a large signed, zero-sum redefinition vector.
That vector is retained as an impossibility witness for an ungoverned scalar
or proportional bridge; it is not allocated or balanced away.
"""
struct ValuationEnvelopeReport
    year::Int
    source_commodity_codes::Vector{String}
    model_codes::Vector{String}
    closure_codes::Vector{String}
    source_supply_components::LabeledMatrix{
        CommodityBasis,
        ValuationComponentBasis,
    }
    model_supply_components::LabeledMatrix{
        CommodityBasis,
        ValuationComponentBasis,
    }
    closure_supply_components::LabeledMatrix{
        CommodityBasis,
        ValuationComponentBasis,
    }
    source_after_producer_output::LabeledVector{CommodityBasis}
    source_after_producer_output_explicit::BitVector
    model_after_producer_output::LabeledVector{CommodityBasis}
    model_after_producer_output_explicit::BitVector
    closure_after_producer_output::LabeledVector{CommodityBasis}
    closure_after_producer_output_explicit::BitVector
    source_implied_pre_redefinitions_producer_output::
    LabeledVector{CommodityBasis}
    model_implied_pre_redefinitions_producer_output::
    LabeledVector{CommodityBasis}
    closure_implied_pre_redefinitions_producer_output::
    LabeledVector{CommodityBasis}
    source_redefinition_redistribution::LabeledVector{CommodityBasis}
    model_redefinition_redistribution::LabeledVector{CommodityBasis}
    closure_redefinition_redistribution::LabeledVector{CommodityBasis}
    observed_tax_variant::TaxControlVariant
    zero_tax_variant::TaxControlVariant
    component_cell_sums::Dict{String, Float64}
    component_published_controls::Dict{String, Float64}
    residuals::Vector{ControlResidual}
    signed_redefinition_redistribution::Float64
    absolute_redefinition_redistribution::Float64
    redefinition_redistribution_frobenius::Float64
    producer_pre_redefinitions_cell_correlation::Float64
    maximum_redefinition_redistribution_cell::ValuationRedistributionCell
    negative_supply_component_cells::Vector{NegativeCell}
    negative_redefinition_redistribution_cells::Vector{NegativeCell}
    contract_sha256::String
    supply_fixture_sha256::String
    supply_manifest_sha256::String
    supply_table_source_sha256::String
    after_fixture_sha256::String
    after_manifest_sha256::String
    after_source_zip_sha256::String
    model_mapping_sha256::String
    sector_mapping_sha256::String
    supply_source_status::String
    after_source_status::String
    cross_archive_release_identity::Symbol
    transformation::Symbol
    tax_variant_effect::Symbol
    margin_allocation_applied::Bool
    tax_allocation_applied::Bool
    redefinition_allocation_applied::Bool
    domestic_use_subtraction_applied::Bool
    balancing_applied::Bool
    clipping_applied::Bool
    model_state_write::Bool
    accounting_gate_effect::Symbol
    forecast_origin_admissible::Bool
    promotion_blockers::Vector{String}
    promotion_ready::Bool
end

function add_residual!(
        residuals,
        family,
        code,
        equation,
        lhs,
        rhs,
        tolerance,
    )
    push!(
        residuals,
        ControlResidual(family, code, equation, lhs, rhs, tolerance),
    )
    return residuals
end

function structurally_equal(lhs, rhs)
    typeof(lhs) === typeof(rhs) || return false
    if lhs isa AbstractArray
        axes(lhs) == axes(rhs) || return false
        return all(
            structurally_equal(lhs[index], rhs[index])
                for index in eachindex(lhs)
        )
    elseif lhs isa AbstractDict
        Set(keys(lhs)) == Set(keys(rhs)) || return false
        return all(
            structurally_equal(lhs[key], rhs[key]) for key in keys(lhs)
        )
    elseif lhs isa Number ||
            lhs isa AbstractString ||
            lhs isa Symbol ||
            lhs isa Bool ||
            lhs === nothing
        return isequal(lhs, rhs)
    elseif isstructtype(typeof(lhs))
        return all(
            structurally_equal(getfield(lhs, field), getfield(rhs, field))
                for field in fieldnames(typeof(lhs))
        )
    end
    return isequal(lhs, rhs)
end

function validate_contract(
        contract_path,
        supply_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
    )
    contract_bytes = read(contract_path)
    contract_sha256 = sha256_hex(contract_bytes)
    contract_sha256 == APPROVED_CONTRACT_SHA256 ||
        throw(ArgumentError("valuation-envelope contract SHA-256 changed"))
    contract = TOML.parse(String(contract_bytes))
    get(contract, "schema_version", "") == CONTRACT_SCHEMA ||
        throw(ArgumentError("unsupported valuation-envelope contract schema"))
    get(contract, "classification", "") == EXPECTED_STATUS ||
        throw(ArgumentError("valuation-envelope status changed"))
    get(contract, "promotion_status", "") == EXPECTED_PROMOTION_STATUS ||
        throw(ArgumentError("valuation-envelope promotion status changed"))
    get(contract, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("valuation envelope cannot admit an origin"))
    get(contract, "model_state_write", true) === false ||
        throw(ArgumentError("valuation envelope cannot write model state"))
    get(contract, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("valuation envelope cannot affect accounting gates"))
    get(contract, "source_year", 0) == 2024 ||
        throw(ArgumentError("valuation-envelope source year changed"))
    String.(get(contract, "component_codes", String[])) == COMPONENT_CODES ||
        throw(ArgumentError("valuation component codes changed"))
    length(get(contract, "component_meanings", String[])) ==
        length(COMPONENT_CODES) ||
        throw(ArgumentError("valuation component meanings changed"))
    String.(get(contract, "row_equations", String[])) == [
        "T007 + MCIF + MADJ = T013",
        "Trade + Trans = T014",
        "TOP + MDTY + SUB = T015",
        "T013 + T014 + T015 = T016",
    ] || throw(ArgumentError("valuation row equations changed"))
    get(contract, "cross_archive_release_identity", "") ==
        "NOT_EXTERNALLY_BOUND" ||
        throw(ArgumentError("cross-archive release identity was overclaimed"))
    get(contract, "cell_allocation_policy", "") == "NONE" ||
        throw(ArgumentError("valuation cell allocation was enabled"))
    get(contract, "tax_variant_effect", "") == "NONE_DIAGNOSTIC_ONLY" ||
        throw(ArgumentError("valuation tax variant effect changed"))
    for flag in (
            "margin_allocation_applied",
            "tax_allocation_applied",
            "redefinition_allocation_applied",
            "domestic_use_subtraction_applied",
            "balancing_applied",
            "clipping_applied",
        )
        get(contract, flag, true) === false ||
            throw(ArgumentError("valuation contract enabled $flag"))
    end

    supply_cells_path = joinpath(supply_directory, "cells.csv")
    supply_manifest_path = joinpath(supply_directory, "manifest.toml")
    after_cells_path = joinpath(after_directory, "cells.csv")
    after_manifest_path = joinpath(after_directory, "manifest.toml")
    identities = Dict(
        "supply_fixture_sha256" => (
            sha256_hex(read(supply_cells_path)),
            APPROVED_SUPPLY_FIXTURE_SHA256,
        ),
        "supply_manifest_sha256" => (
            sha256_hex(read(supply_manifest_path)),
            APPROVED_SUPPLY_MANIFEST_SHA256,
        ),
        "after_redefinitions_fixture_sha256" => (
            sha256_hex(read(after_cells_path)),
            APPROVED_AFTER_FIXTURE_SHA256,
        ),
        "after_redefinitions_manifest_sha256" => (
            sha256_hex(read(after_manifest_path)),
            APPROVED_AFTER_MANIFEST_SHA256,
        ),
        "model_mapping_sha256" => (
            sha256_hex(read(model_mapping_path)),
            APPROVED_MODEL_MAPPING_SHA256,
        ),
        "sector_mapping_sha256" => (
            sha256_hex(read(sector_mapping_path)),
            APPROVED_SECTOR_MAPPING_SHA256,
        ),
    )
    for (field, (actual, expected)) in identities
        actual == expected ||
            throw(ArgumentError("$field bytes changed"))
        get(contract, field, "") == expected ||
            throw(ArgumentError("$field contract identity changed"))
    end

    supply_manifest = TOML.parsefile(supply_manifest_path)
    source_specs = Dict(
        String(spec["table_id"]) => spec
            for spec in supply_manifest["sources"]
    )
    haskey(source_specs, "262") ||
        throw(ArgumentError("supply fixture no longer contains Table 262"))
    supply_spec = source_specs["262"]
    get(supply_spec, "source_sha256", "") == APPROVED_SUPPLY_TABLE_SHA256 ||
        throw(ArgumentError("Table 262 source identity changed"))
    get(supply_spec, "status", "") == "APPROVED_ARCHIVED" ||
        throw(ArgumentError("Table 262 source status changed"))
    get(supply_spec, "year", 0) == 2024 ||
        throw(ArgumentError("Table 262 source year changed"))
    get(contract, "supply_table_source_sha256", "") ==
        APPROVED_SUPPLY_TABLE_SHA256 ||
        throw(ArgumentError("contract Table 262 identity changed"))
    get(contract, "supply_source_status", "") == "APPROVED_ARCHIVED" ||
        throw(ArgumentError("contract Table 262 status changed"))

    after_manifest = TOML.parsefile(after_manifest_path)
    get(after_manifest, "source_zip_sha256", "") ==
        APPROVED_AFTER_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("after-redefinitions source ZIP changed"))
    get(after_manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("after-redefinitions source status changed"))
    get(contract, "after_redefinitions_source_zip_sha256", "") ==
        APPROVED_AFTER_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("contract source ZIP identity changed"))
    get(contract, "after_redefinitions_source_status", "") ==
        EXPECTED_STATUS ||
        throw(ArgumentError("contract after-source status changed"))
    return (;
        contract,
        contract_sha256,
        supply_manifest,
        supply_spec,
        after_manifest,
    )
end

function aggregate_rows(
        matrix::LabeledMatrix{CommodityBasis, ValuationComponentBasis},
        target_codes,
        mapping,
    )
    index = Dict(code => position for (position, code) in pairs(target_codes))
    values = zeros(length(target_codes), length(matrix.column_codes))
    explicit = falses(size(values))
    for (source_position, source_code) in pairs(matrix.row_codes)
        target_code = mapping[source_code]
        haskey(index, target_code) || continue
        target_position = index[target_code]
        values[target_position, :] .+= matrix.values[source_position, :]
        explicit[target_position, :] .|=
            matrix.explicit[source_position, :]
    end
    return LabeledMatrix{CommodityBasis, ValuationComponentBasis}(
        target_codes,
        matrix.column_codes,
        values,
        explicit,
    )
end

function aggregate_vector(vector::LabeledVector{CommodityBasis}, target_codes, mapping)
    index = Dict(code => position for (position, code) in pairs(target_codes))
    values = zeros(length(target_codes))
    for (source_position, source_code) in pairs(vector.codes)
        target_code = mapping[source_code]
        haskey(index, target_code) || continue
        values[index[target_code]] += vector.values[source_position]
    end
    return LabeledVector{CommodityBasis}(target_codes, values)
end

function aggregate_mask(source_codes, source_explicit, target_codes, mapping)
    length(source_codes) == length(source_explicit) ||
        throw(ArgumentError("valuation source mask has the wrong length"))
    index = Dict(code => position for (position, code) in pairs(target_codes))
    explicit = falses(length(target_codes))
    for (source_position, source_code) in pairs(source_codes)
        target_code = mapping[source_code]
        haskey(index, target_code) || continue
        explicit[index[target_code]] |= source_explicit[source_position]
    end
    return BitVector(explicit)
end

function component_position(matrix, code)
    return matrix.column_index[String(code)]
end

function component_values(matrix, code)
    return matrix.values[:, component_position(matrix, code)]
end

function derived_negative_cells(vector, column_code)
    return NegativeCell[
        NegativeCell(code, column_code, vector.values[position])
            for (position, code) in pairs(vector.codes)
            if vector.values[position] < 0
    ]
end

function negative_cell_vectors_match(lhs, rhs)
    length(lhs) == length(rhs) || return false
    return all(
        left.row_code == right.row_code &&
            left.column_code == right.column_code &&
            isequal(left.value, right.value)
            for (left, right) in zip(lhs, rhs)
    )
end

function residual_family_counts(residuals)
    return Dict(
        family => count(residual -> residual.family == family, residuals)
            for family in unique(residual.family for residual in residuals)
    )
end

function valuation_envelope_internal_controls_pass(
        report::ValuationEnvelopeReport,
    )
    report.year == 2024 || return false
    all(residual.passed for residual in report.residuals) || return false
    residual_family_counts(report.residuals) == Dict(
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
    ) || return false
    report.contract_sha256 == APPROVED_CONTRACT_SHA256 || return false
    report.supply_fixture_sha256 == APPROVED_SUPPLY_FIXTURE_SHA256 ||
        return false
    report.supply_manifest_sha256 == APPROVED_SUPPLY_MANIFEST_SHA256 ||
        return false
    report.supply_table_source_sha256 == APPROVED_SUPPLY_TABLE_SHA256 ||
        return false
    report.after_fixture_sha256 == APPROVED_AFTER_FIXTURE_SHA256 ||
        return false
    report.after_manifest_sha256 == APPROVED_AFTER_MANIFEST_SHA256 ||
        return false
    report.after_source_zip_sha256 == APPROVED_AFTER_SOURCE_ZIP_SHA256 ||
        return false
    report.model_mapping_sha256 == APPROVED_MODEL_MAPPING_SHA256 ||
        return false
    report.sector_mapping_sha256 == APPROVED_SECTOR_MAPPING_SHA256 ||
        return false
    report.supply_source_status == "APPROVED_ARCHIVED" || return false
    report.after_source_status == EXPECTED_STATUS || return false
    report.cross_archive_release_identity == :not_externally_bound ||
        return false
    report.transformation ==
        :code_keyed_valuation_envelope_with_unallocated_redefinition_residual ||
        return false
    report.tax_variant_effect == :none_diagnostic_only || return false
    any(
        (
            report.margin_allocation_applied,
            report.tax_allocation_applied,
            report.redefinition_allocation_applied,
            report.domestic_use_subtraction_applied,
            report.balancing_applied,
            report.clipping_applied,
            report.model_state_write,
            report.forecast_origin_admissible,
            report.promotion_ready,
        ),
    ) && return false
    report.accounting_gate_effect == :none || return false
    length(report.promotion_blockers) >= length(EXPECTED_BLOCKER_PREFIX) ||
        return false
    report.promotion_blockers[1:length(EXPECTED_BLOCKER_PREFIX)] ==
        EXPECTED_BLOCKER_PREFIX || return false
    try
        source_codes = report.source_commodity_codes
        model_codes = report.model_codes
        closure_codes = report.closure_codes
        length(source_codes) == 73 || return false
        length(unique(source_codes)) == 73 || return false
        length(model_codes) == 68 || return false
        length(unique(model_codes)) == 68 || return false
        closure_codes == ["Used", "Other"] || return false
        source_matrix = report.source_supply_components
        source_matrix.row_codes == source_codes || return false
        source_matrix.column_codes == COMPONENT_CODES || return false
        size(source_matrix.values) == (73, 12) || return false
        report.model_supply_components.row_codes == model_codes ||
            return false
        report.closure_supply_components.row_codes == closure_codes ||
            return false
        report.model_supply_components.column_codes == COMPONENT_CODES ||
            return false
        report.closure_supply_components.column_codes == COMPONENT_CODES ||
            return false
        size(report.model_supply_components.values) == (68, 12) ||
            return false
        size(report.closure_supply_components.values) == (2, 12) ||
            return false
        # The source order differs from the model-plus-closure order, so the
        # source-aware rebuild is responsible for cell-level aggregation.
        for code in COMPONENT_CODES
            isapprox(
                sum(component_values(source_matrix, code)),
                sum(component_values(report.model_supply_components, code)) +
                    sum(
                    component_values(
                        report.closure_supply_components,
                        code,
                    ),
                );
                atol = 0.0,
                rtol = 0.0,
            ) || return false
        end

        source_after = report.source_after_producer_output
        source_after.codes == source_codes || return false
        length(report.source_after_producer_output_explicit) == 73 ||
            return false
        report.model_after_producer_output.codes == model_codes ||
            return false
        report.closure_after_producer_output.codes == closure_codes ||
            return false
        report.source_implied_pre_redefinitions_producer_output.codes ==
            source_codes || return false
        report.source_redefinition_redistribution.codes == source_codes ||
            return false
        basic = component_values(source_matrix, "T007")
        tax = component_values(source_matrix, "T015")
        implied = basic + tax
        redistribution = source_after.values - implied
        report.source_implied_pre_redefinitions_producer_output.values ==
            implied || return false
        report.source_redefinition_redistribution.values ==
            redistribution || return false
        isapprox(
            report.signed_redefinition_redistribution,
            sum(redistribution);
            atol = 1.0e-12,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.absolute_redefinition_redistribution,
            sum(abs, redistribution);
            atol = 1.0e-8,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.redefinition_redistribution_frobenius,
            norm(redistribution);
            atol = 1.0e-8,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.producer_pre_redefinitions_cell_correlation,
            cor(source_after.values, implied);
            atol = 1.0e-15,
            rtol = 1.0e-15,
        ) || return false
        maximum_position = argmax(abs.(redistribution))
        maximum_cell = report.maximum_redefinition_redistribution_cell
        maximum_cell.commodity_code == source_codes[maximum_position] ||
            return false
        isequal(
            maximum_cell.after_redefinitions_producer_output,
            source_after.values[maximum_position],
        ) || return false
        isequal(
            maximum_cell.pre_redefinitions_basic_output,
            basic[maximum_position],
        ) || return false
        isequal(maximum_cell.net_product_tax, tax[maximum_position]) ||
            return false
        isequal(
            maximum_cell.redistribution,
            redistribution[maximum_position],
        ) || return false

        report.observed_tax_variant.name == :observed || return false
        report.observed_tax_variant.source_semantics ==
            :table_262_t015_current_vintage_control || return false
        report.observed_tax_variant.use_cell_allocation == :none ||
            return false
        report.observed_tax_variant.commodity_net_product_tax.codes ==
            model_codes || return false
        report.observed_tax_variant.commodity_net_product_tax.values ==
            component_values(report.model_supply_components, "T015") ||
            return false
        report.zero_tax_variant.name == :explicit_zero || return false
        report.zero_tax_variant.source_semantics ==
            :policy_zero_not_observation || return false
        report.zero_tax_variant.use_cell_allocation == :none || return false
        report.zero_tax_variant.commodity_net_product_tax.codes ==
            model_codes || return false
        all(iszero, report.zero_tax_variant.commodity_net_product_tax.values) ||
            return false
        for variant in (
                report.observed_tax_variant,
                report.zero_tax_variant,
            )
            any(
                (
                    variant.allocation_applied,
                    variant.model_state_write,
                    variant.forecast_origin_admissible,
                    variant.promotion_ready,
                ),
            ) && return false
        end
        negative_cell_vectors_match(
            negative_cells(source_matrix),
            report.negative_supply_component_cells,
        ) || return false
        expected_negative_redistribution =
            derived_negative_cells(
            report.source_redefinition_redistribution,
            "redefinition_redistribution",
        )
        negative_cell_vectors_match(
            expected_negative_redistribution,
            report.negative_redefinition_redistribution_cells,
        ) || return false
    catch
        return false
    end
    return true
end

function _build_valuation_envelope(
        contract_path;
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
    )
    validated = validate_contract(
        contract_path,
        supply_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
    )
    supply_fixture = load_canonical_fixture(supply_directory)
    after_fixture = load_after_redefinitions_fixture(after_directory)
    model_core = build_model_core_aggregation(
        after_fixture,
        model_mapping_path;
        sector_mapping_path,
    )
    model_core_controls_pass(
        model_core,
        after_fixture,
        model_mapping_path;
        sector_mapping_path,
    ) || throw(ArgumentError("source model-core controls do not pass"))

    source_codes = copy(after_fixture.producer_commodity_output_make.codes)
    supply_rows = [
        code for code in supply_fixture.supply.row_codes if code != "T017"
    ]
    Set(source_codes) == Set(supply_rows) ||
        throw(ArgumentError("valuation source commodity code sets differ"))
    length(source_codes) == 73 ||
        throw(ArgumentError("valuation source commodity count changed"))
    all(
        has_cell(supply_fixture.supply, code, component)
            for code in source_codes
            for component in ("T007", "T013", "T016")
    ) || throw(ArgumentError("required valuation source control is absent"))

    source_component_values = Float64[
        cell_value(supply_fixture.supply, code, component)
            for code in source_codes, component in COMPONENT_CODES
    ]
    source_component_explicit = BitMatrix(
        [
            has_cell(supply_fixture.supply, code, component)
                for code in source_codes, component in COMPONENT_CODES
        ],
    )
    source_components =
        LabeledMatrix{CommodityBasis, ValuationComponentBasis}(
        source_codes,
        COMPONENT_CODES,
        source_component_values,
        source_component_explicit,
    )
    model_components = aggregate_rows(
        source_components,
        model_core.model_codes,
        model_core.source_commodity_mapping,
    )
    closure_components = aggregate_rows(
        source_components,
        model_core.closure_codes,
        model_core.source_commodity_mapping,
    )

    source_after = LabeledVector{CommodityBasis}(
        source_codes,
        Float64[
            after_fixture.producer_commodity_output_make[code]
                for code in source_codes
        ],
    )
    source_after_explicit = BitVector(
        after_fixture.source_explicit[
            "producer_make_commodity_output_2024",
        ][:, 1],
    )
    model_after = aggregate_vector(
        source_after,
        model_core.model_codes,
        model_core.source_commodity_mapping,
    )
    closure_after = aggregate_vector(
        source_after,
        model_core.closure_codes,
        model_core.source_commodity_mapping,
    )
    model_after_explicit = aggregate_mask(
        source_codes,
        source_after_explicit,
        model_core.model_codes,
        model_core.source_commodity_mapping,
    )
    closure_after_explicit = aggregate_mask(
        source_codes,
        source_after_explicit,
        model_core.closure_codes,
        model_core.source_commodity_mapping,
    )

    source_implied_values =
        component_values(source_components, "T007") +
        component_values(source_components, "T015")
    source_implied =
        LabeledVector{CommodityBasis}(source_codes, source_implied_values)
    model_implied = aggregate_vector(
        source_implied,
        model_core.model_codes,
        model_core.source_commodity_mapping,
    )
    closure_implied = aggregate_vector(
        source_implied,
        model_core.closure_codes,
        model_core.source_commodity_mapping,
    )
    source_redistribution_values =
        source_after.values - source_implied.values
    source_redistribution = LabeledVector{CommodityBasis}(
        source_codes,
        source_redistribution_values,
    )
    model_redistribution = aggregate_vector(
        source_redistribution,
        model_core.model_codes,
        model_core.source_commodity_mapping,
    )
    closure_redistribution = aggregate_vector(
        source_redistribution,
        model_core.closure_codes,
        model_core.source_commodity_mapping,
    )

    observed_variant = TaxControlVariant(
        :observed,
        LabeledVector{CommodityBasis}(
            model_core.model_codes,
            component_values(model_components, "T015"),
        ),
        :table_262_t015_current_vintage_control,
        :none,
        false,
        false,
        false,
        false,
    )
    zero_variant = TaxControlVariant(
        :explicit_zero,
        LabeledVector{CommodityBasis}(
            model_core.model_codes,
            zeros(length(model_core.model_codes)),
        ),
        :policy_zero_not_observation,
        :none,
        false,
        false,
        false,
        false,
    )

    component_cell_sums = Dict(
        component => sum(component_values(source_components, component))
            for component in COMPONENT_CODES
    )
    component_published_controls = Dict(
        component =>
            cell_value(
                supply_fixture.supply,
                "T017",
                component;
                required = true,
            )
            for component in COMPONENT_CODES
    )
    residuals = ControlResidual[]
    for (position, code) in pairs(source_codes)
        values = Dict(
            component =>
                source_components.values[
                    position,
                    component_position(source_components, component),
                ]
                for component in COMPONENT_CODES
        )
        for (
                family,
                equation,
                lhs,
                rhs,
                tolerance,
            ) in (
                (
                    :valuation_supply_basic_identity,
                    "T007 + MCIF + MADJ = T013",
                    values["T007"] + values["MCIF"] + values["MADJ"],
                    values["T013"],
                    published_rounding_tolerance(3),
                ),
                (
                    :valuation_margin_identity,
                    "Trade + Trans = T014",
                    values["Trade"] + values["Trans"],
                    values["T014"],
                    published_rounding_tolerance(2),
                ),
                (
                    :valuation_product_tax_identity,
                    "TOP + MDTY + SUB = T015",
                    values["TOP"] + values["MDTY"] + values["SUB"],
                    values["T015"],
                    published_rounding_tolerance(3),
                ),
                (
                    :valuation_purchaser_supply_identity,
                    "T013 + T014 + T015 = T016",
                    values["T013"] + values["T014"] + values["T015"],
                    values["T016"],
                    published_rounding_tolerance(3),
                ),
            )
            add_residual!(
                residuals,
                family,
                code,
                equation,
                lhs,
                rhs,
                tolerance,
            )
        end
    end
    for component in COMPONENT_CODES
        add_residual!(
            residuals,
            :valuation_component_published_control,
            component,
            "sum of 73 published component cells equals the T017 component control",
            component_cell_sums[component],
            component_published_controls[component],
            published_rounding_tolerance(73),
        )
    end
    add_residual!(
        residuals,
        :valuation_after_output_published_control,
        "T017",
        "sum of after-redefinitions producer-output cells equals its published make control",
        sum(source_after.values),
        after_fixture.producer_make_output_grand_control,
        published_rounding_tolerance(73),
    )
    add_residual!(
        residuals,
        :valuation_published_producer_basic_identity,
        "grand_total",
        "published after producer output = published before basic output + published net product tax",
        after_fixture.producer_make_output_grand_control,
        component_published_controls["T007"] +
            component_published_controls["T015"],
        1.5,
    )
    add_residual!(
        residuals,
        :valuation_cell_sum_producer_basic_identity,
        "grand_total",
        "rounded after producer cells = rounded before basic cells + rounded net-product-tax cells",
        sum(source_after.values),
        component_cell_sums["T007"] + component_cell_sums["T015"],
        109.5,
    )
    add_residual!(
        residuals,
        :valuation_redefinition_zero_sum,
        "grand_total",
        "commodity redefinition redistribution sums to zero within source rounding",
        sum(source_redistribution.values),
        0.0,
        109.5,
    )
    for component in COMPONENT_CODES
        add_residual!(
            residuals,
            :valuation_component_aggregation,
            component,
            "model plus closure component totals preserve the 73-commodity source",
            sum(component_values(model_components, component)) +
                sum(component_values(closure_components, component)),
            component_cell_sums[component],
            0.0,
        )
    end
    for (family, source, model, closure, equation) in (
            (
                :valuation_after_output_aggregation,
                source_after,
                model_after,
                closure_after,
                "model plus closure after-output totals preserve the source",
            ),
            (
                :valuation_implied_output_aggregation,
                source_implied,
                model_implied,
                closure_implied,
                "model plus closure implied pre-redefinitions producer output preserves the source",
            ),
            (
                :valuation_redistribution_aggregation,
                source_redistribution,
                model_redistribution,
                closure_redistribution,
                "model plus closure redefinition redistribution preserves the source",
            ),
        )
        add_residual!(
            residuals,
            family,
            "grand_total",
            equation,
            sum(model.values) + sum(closure.values),
            sum(source.values),
            0.0,
        )
    end
    add_residual!(
        residuals,
        :valuation_component_block_assembly,
        "maximum_component_total_error",
        "model and closure component blocks preserve every source component total",
        maximum(
            abs(
                    component_cell_sums[component] -
                    sum(component_values(model_components, component)) -
                    sum(component_values(closure_components, component)),
                ) for component in COMPONENT_CODES
        ),
        0.0,
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )

    maximum_position = argmax(abs.(source_redistribution_values))
    maximum_cell = ValuationRedistributionCell(
        source_codes[maximum_position],
        source_after.values[maximum_position],
        component_values(source_components, "T007")[maximum_position],
        component_values(source_components, "T015")[maximum_position],
        source_redistribution_values[maximum_position],
    )
    blockers = vcat(
        EXPECTED_BLOCKER_PREFIX,
        model_core.promotion_blockers,
    )
    report = ValuationEnvelopeReport(
        2024,
        source_codes,
        model_core.model_codes,
        model_core.closure_codes,
        source_components,
        model_components,
        closure_components,
        source_after,
        source_after_explicit,
        model_after,
        model_after_explicit,
        closure_after,
        closure_after_explicit,
        source_implied,
        model_implied,
        closure_implied,
        source_redistribution,
        model_redistribution,
        closure_redistribution,
        observed_variant,
        zero_variant,
        component_cell_sums,
        component_published_controls,
        residuals,
        sum(source_redistribution_values),
        sum(abs, source_redistribution_values),
        norm(source_redistribution_values),
        cor(source_after.values, source_implied_values),
        maximum_cell,
        negative_cells(source_components),
        derived_negative_cells(
            source_redistribution,
            "redefinition_redistribution",
        ),
        validated.contract_sha256,
        APPROVED_SUPPLY_FIXTURE_SHA256,
        APPROVED_SUPPLY_MANIFEST_SHA256,
        APPROVED_SUPPLY_TABLE_SHA256,
        APPROVED_AFTER_FIXTURE_SHA256,
        APPROVED_AFTER_MANIFEST_SHA256,
        APPROVED_AFTER_SOURCE_ZIP_SHA256,
        APPROVED_MODEL_MAPPING_SHA256,
        APPROVED_SECTOR_MAPPING_SHA256,
        String(validated.supply_spec["status"]),
        String(validated.after_manifest["status"]),
        :not_externally_bound,
        :code_keyed_valuation_envelope_with_unallocated_redefinition_residual,
        :none_diagnostic_only,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        :none,
        false,
        blockers,
        false,
    )
    valuation_envelope_internal_controls_pass(report) ||
        throw(ArgumentError("valuation-envelope internal controls do not pass"))
    return report
end

function valuation_envelope_controls_pass(
        report::ValuationEnvelopeReport,
        contract_path;
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
    )
    try
        expected = _build_valuation_envelope(
            contract_path;
            supply_directory,
            after_directory,
            model_mapping_path,
            sector_mapping_path,
        )
        return structurally_equal(report, expected)
    catch
        return false
    end
end

function build_valuation_envelope(
        contract_path;
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
    )
    report = _build_valuation_envelope(
        contract_path;
        supply_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
    )
    valuation_envelope_controls_pass(
        report,
        contract_path;
        supply_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
    ) || throw(ArgumentError("valuation-envelope source controls do not pass"))
    return report
end

end
