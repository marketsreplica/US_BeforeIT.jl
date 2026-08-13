module USAfterRedefinitionsFinalUseEnvelope

using SHA
using TOML

using ..USSupplyMakeDiagnostics:
    AxisBasis,
    CommodityBasis,
    ControlResidual,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector,
    published_rounding_tolerance
using ..USSymmetricSupplyUse: NegativeCell, negative_cells
using ..USAfterRedefinitionsCommonBasis:
    AfterRedefinitionsValueAddedBasis,
    FinalUseBasis,
    load_after_redefinitions_fixture
using ..USAfterRedefinitionsModelCore:
    build_model_core_aggregation
using ..USAfterRedefinitionsValuationEnvelope:
    TaxControlVariant,
    build_valuation_envelope

export FinalUseCategoryBasis,
    GDPApproachLedger,
    LegacyValuationBridgeAssessment,
    FinalUseEnvelopeReport,
    build_final_use_envelope,
    final_use_envelope_controls_pass,
    final_use_envelope_internal_controls_pass

struct FinalUseCategoryBasis <: AxisBasis end

const CONTRACT_SCHEMA =
    "beforeit-us-after-redefinitions-final-use-envelope.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_CONTRACT_SHA256 =
    "b4e3969a52618b4e462b8e468ada784dda85cae86550fb27659d2afbb4cbb2be"
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
const APPROVED_VALUATION_CONTRACT_SHA256 =
    "110f82037e45e1de3ce4f5a1df2b7982d064e90a9323f255c7441452fa6d2ede"
const FINAL_USE_CODES = [
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
const CATEGORY_CODES = [
    "household_consumption",
    "private_fixed_investment",
    "inventory_change",
    "exports",
    "imports_accounting_offset",
    "government_consumption",
    "government_gross_investment",
]
const VALUE_ADDED_CODES = ["V001", "V002", "V003"]
const EXPECTED_CATEGORY_COLUMNS = Dict(
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
const EXPECTED_BLOCKER_PREFIX = [
    "PRODUCER_PRICE_FINAL_USE_NOT_CONNECTED_TO_MODEL_STATE",
    "FINAL_USE_CATEGORY_LEDGER_NOT_CALIBRATION_ADAPTER",
    "F030_FLOW_NOT_MAPPED_TO_QUARTER_END_STOCK",
    "F050_OFFSET_NOT_SELECTED_AS_MODEL_IMPORT_BOUNDARY",
    "LEGACY_T013_T016_SCALAR_BRIDGE_REJECTED",
]

const DEFAULT_AFTER_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const DEFAULT_SUPPLY_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_approved",
)
const DEFAULT_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const DEFAULT_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const DEFAULT_VALUATION_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_valuation_envelope.toml")

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

"""
Three GDP approaches retained without balancing.

The `cell_*` quantities are sums of the archived workbook cells. The
`published_*` quantities use BEA's independently rounded controls. Their
differences are evidence about source rounding, not forecast errors.
"""
struct GDPApproachLedger
    cell_expenditure::Float64
    cell_income::Float64
    cell_industry_output::Float64
    cell_intermediate_use::Float64
    cell_production::Float64
    published_expenditure::Float64
    published_income::Float64
    published_output::Float64
    published_intermediate_use::Float64
    published_production::Float64
    cell_expenditure_income_gap::Float64
    cell_production_income_gap::Float64
    published_expenditure_income_gap::Float64
    published_production_income_gap::Float64
end

"""
Assessment of the legacy `T013/T016` commodity-ratio bridge.

The ratio is a reproducible arithmetic diagnostic. It is not identified at a
use cell, so this envelope rejects its application to calibration or state.
"""
struct LegacyValuationBridgeAssessment
    method::Symbol
    status::Symbol
    cell_identified::Bool
    recipient_allocation_observed::Bool
    diagnostic_only::Bool
    applied::Bool
    model_state_admissible::Bool
    forecast_origin_admissible::Bool
end

"""
Source-aware producer-price final-use and GDP envelope.

Every one of the 20 final-use columns is partitioned into seven declared
categories. The 68 model commodities and the `Used`/`Other` closure rows are
kept separate. No source cell is changed, and no balancing, valuation
allocation, inventory-stock conversion, import-boundary selection, or model
state write occurs.
"""
struct FinalUseEnvelopeReport
    year::Int
    source_commodity_codes::Vector{String}
    model_codes::Vector{String}
    closure_codes::Vector{String}
    final_use_codes::Vector{String}
    category_codes::Vector{String}
    category_columns::Dict{String, Vector{String}}
    source_commodity_mapping::Dict{String, String}
    source_industry_mapping::Dict{String, String}
    source_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    source_category_final_use::LabeledMatrix{
        CommodityBasis,
        FinalUseCategoryBasis,
    }
    model_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    model_category_final_use::LabeledMatrix{
        CommodityBasis,
        FinalUseCategoryBasis,
    }
    closure_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    closure_category_final_use::LabeledMatrix{
        CommodityBasis,
        FinalUseCategoryBasis,
    }
    model_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    closure_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    producer_value_added::LabeledMatrix{
        AfterRedefinitionsValueAddedBasis,
        IndustryBasis,
    }
    industry_output::LabeledVector{IndustryBasis}
    published_final_use_controls::LabeledVector{FinalUseBasis}
    published_category_controls::LabeledVector{FinalUseCategoryBasis}
    observed_tax_variant::TaxControlVariant
    zero_tax_variant::TaxControlVariant
    closure_net_product_tax_control::LabeledVector{CommodityBasis}
    source_net_product_tax_total::Float64
    gdp::GDPApproachLedger
    residuals::Vector{ControlResidual}
    negative_source_final_use_cells::Vector{NegativeCell}
    negative_model_final_use_cells::Vector{NegativeCell}
    negative_closure_final_use_cells::Vector{NegativeCell}
    negative_model_category_cells::Vector{NegativeCell}
    negative_closure_category_cells::Vector{NegativeCell}
    negative_value_added_cells::Vector{NegativeCell}
    contract_sha256::String
    after_fixture_sha256::String
    after_manifest_sha256::String
    after_source_zip_sha256::String
    model_mapping_sha256::String
    sector_mapping_sha256::String
    valuation_contract_sha256::String
    source_status::String
    transformation::Symbol
    price_basis::Symbol
    closure_policy::Symbol
    inventory_policy::Symbol
    import_policy::Symbol
    observed_tax_variant_policy::Symbol
    zero_tax_variant_policy::Symbol
    legacy_bridge::LegacyValuationBridgeAssessment
    final_use_adjustment_applied::Bool
    closure_allocation_applied::Bool
    inventory_stock_mapping_applied::Bool
    import_boundary_selected::Bool
    legacy_scalar_bridge_applied::Bool
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
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
    )
    contract_bytes = read(contract_path)
    contract_sha256 = sha256_hex(contract_bytes)
    contract_sha256 == APPROVED_CONTRACT_SHA256 ||
        throw(ArgumentError("final-use-envelope contract SHA-256 changed"))
    contract = TOML.parse(String(contract_bytes))
    get(contract, "schema_version", "") == CONTRACT_SCHEMA ||
        throw(ArgumentError("unsupported final-use-envelope contract schema"))
    get(contract, "classification", "") == EXPECTED_STATUS ||
        throw(ArgumentError("final-use-envelope status changed"))
    get(contract, "promotion_status", "") == EXPECTED_PROMOTION_STATUS ||
        throw(ArgumentError("final-use-envelope promotion status changed"))
    get(contract, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("final-use envelope cannot admit an origin"))
    get(contract, "model_state_write", true) === false ||
        throw(ArgumentError("final-use envelope cannot write model state"))
    get(contract, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("final-use envelope cannot affect accounting gates"))
    get(contract, "source_year", 0) == 2024 ||
        throw(ArgumentError("final-use-envelope source year changed"))
    get(contract, "price_basis", "") == "producers prices" ||
        throw(ArgumentError("final-use-envelope price basis changed"))
    String.(get(contract, "final_use_codes", String[])) == FINAL_USE_CODES ||
        throw(ArgumentError("final-use codes changed"))
    String.(get(contract, "category_codes", String[])) == CATEGORY_CODES ||
        throw(ArgumentError("final-use category codes changed"))
    String.(get(contract, "value_added_codes", String[])) ==
        VALUE_ADDED_CODES ||
        throw(ArgumentError("value-added codes changed"))

    specs = get(contract, "final_use_category", Any[])
    length(specs) == length(CATEGORY_CODES) ||
        throw(ArgumentError("final-use category specification count changed"))
    category_columns = Dict{String, Vector{String}}()
    for (position, spec) in pairs(specs)
        code = String(get(spec, "code", ""))
        code == CATEGORY_CODES[position] ||
            throw(ArgumentError("final-use category order changed"))
        columns = String.(get(spec, "source_columns", String[]))
        columns == EXPECTED_CATEGORY_COLUMNS[code] ||
            throw(ArgumentError("final-use category columns changed for $code"))
        !isempty(String(get(spec, "semantics", ""))) ||
            throw(ArgumentError("final-use category semantics are absent"))
        category_columns[code] = columns
    end
    flattened = reduce(vcat, values(category_columns); init = String[])
    length(flattened) == length(unique(flattened)) ||
        throw(ArgumentError("a final-use column belongs to multiple categories"))
    Set(flattened) == Set(FINAL_USE_CODES) ||
        throw(ArgumentError("final-use category partition is incomplete"))

    get(contract, "gdp_identity", "") ==
        "published final uses = published value added = published output - published intermediate use" ||
        throw(ArgumentError("GDP identity changed"))
    get(contract, "closure_policy", "") ==
        "USED_OTHER_SEPARATE_UNALLOCATED" ||
        throw(ArgumentError("closure policy changed"))
    get(contract, "inventory_policy", "") ==
        "F030_SIGNED_FLOW_NOT_STOCK" ||
        throw(ArgumentError("inventory policy changed"))
    get(contract, "import_policy", "") ==
        "F050_SIGNED_ACCOUNTING_OFFSET_NOT_MODEL_IMPORT_VECTOR" ||
        throw(ArgumentError("import policy changed"))
    get(contract, "observed_tax_variant_policy", "") ==
        "CONTROL_ONLY_NOT_USE_CELL_ALLOCATED" ||
        throw(ArgumentError("observed-tax policy changed"))
    get(contract, "zero_tax_variant_policy", "") ==
        "POLICY_COUNTERFACTUAL_NOT_OBSERVATION" ||
        throw(ArgumentError("zero-tax policy changed"))
    get(contract, "legacy_scalar_bridge_method", "") ==
        "T013_OVER_T016_COMMODITY_RATIO_WITH_PROPORTIONAL_RECIPIENT_RESCALE" ||
        throw(ArgumentError("legacy valuation-bridge method changed"))
    get(contract, "legacy_scalar_bridge_status", "") ==
        "REJECTED_NOT_CELL_IDENTIFIED" ||
        throw(ArgumentError("legacy valuation bridge was enabled"))
    get(contract, "cell_level_valuation_allocation_status", "") ==
        "MISSING" ||
        throw(ArgumentError("cell-level valuation allocation was overclaimed"))
    for flag in (
            "final_use_adjustment_applied",
            "closure_allocation_applied",
            "inventory_stock_mapping_applied",
            "import_boundary_selected",
            "legacy_scalar_bridge_applied",
            "balancing_applied",
            "clipping_applied",
        )
        get(contract, flag, true) === false ||
            throw(ArgumentError("final-use contract enabled $flag"))
    end

    after_cells_path = joinpath(after_directory, "cells.csv")
    after_manifest_path = joinpath(after_directory, "manifest.toml")
    identities = Dict(
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
        "valuation_envelope_contract_sha256" => (
            sha256_hex(read(valuation_contract_path)),
            APPROVED_VALUATION_CONTRACT_SHA256,
        ),
    )
    for (field, (actual, expected)) in identities
        actual == expected || throw(ArgumentError("$field bytes changed"))
        get(contract, field, "") == expected ||
            throw(ArgumentError("$field contract identity changed"))
    end
    after_manifest = TOML.parsefile(after_manifest_path)
    get(after_manifest, "source_zip_sha256", "") ==
        APPROVED_AFTER_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("after-redefinitions source ZIP changed"))
    get(after_manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("after-redefinitions source status changed"))
    get(contract, "after_redefinitions_source_zip_sha256", "") ==
        APPROVED_AFTER_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("contract source ZIP identity changed"))
    return (; contract, contract_sha256, category_columns, after_manifest)
end

function aggregate_categories(
        matrix::LabeledMatrix{R, FinalUseBasis},
        category_codes,
        category_columns,
    ) where {R <: AxisBasis}
    values = zeros(length(matrix.row_codes), length(category_codes))
    explicit = falses(size(values))
    for (category_position, category_code) in pairs(category_codes)
        columns = category_columns[category_code]
        positions = [matrix.column_index[code] for code in columns]
        values[:, category_position] =
            vec(sum(matrix.values[:, positions]; dims = 2))
        explicit[:, category_position] =
            vec(any(matrix.explicit[:, positions]; dims = 2))
    end
    return LabeledMatrix{R, FinalUseCategoryBasis}(
        matrix.row_codes,
        category_codes,
        values,
        explicit,
    )
end

function aggregate_commodity_rows(
        matrix::LabeledMatrix{CommodityBasis, C},
        target_codes,
        mapping,
    ) where {C <: AxisBasis}
    target_index =
        Dict(code => position for (position, code) in pairs(target_codes))
    values = zeros(length(target_codes), length(matrix.column_codes))
    explicit = falses(size(values))
    for (source_position, source_code) in pairs(matrix.row_codes)
        target_code = mapping[source_code]
        haskey(target_index, target_code) || continue
        target_position = target_index[target_code]
        values[target_position, :] .+= matrix.values[source_position, :]
        explicit[target_position, :] .|= matrix.explicit[source_position, :]
    end
    return LabeledMatrix{CommodityBasis, C}(
        target_codes,
        matrix.column_codes,
        values,
        explicit,
    )
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

function build_residuals(
        source_final_use,
        source_category,
        model_final_use,
        model_category,
        closure_final_use,
        closure_category,
        value_added,
        industry_output,
        published_final_controls,
        published_category_controls,
        gdp,
        source_industry_mapping,
        observed_tax_variant,
        closure_net_product_tax,
        source_net_product_tax_total,
        zero_tax_variant,
        category_columns,
    )
    residuals = ControlResidual[]
    source_industry_count = length(source_industry_mapping)
    source_value_added_cell_count =
        length(VALUE_ADDED_CODES) * source_industry_count
    for code in FINAL_USE_CODES
        add_residual!(
            residuals,
            :final_use_column_published_control,
            code,
            "sum published commodity cells = published final-use control",
            sum(source_final_use.values[:, source_final_use.column_index[code]]),
            published_final_controls[code],
            published_rounding_tolerance(length(source_final_use.row_codes)),
        )
    end
    for category in CATEGORY_CODES
        column_count = length(category_columns[category])
        add_residual!(
            residuals,
            :final_use_category_published_control,
            category,
            "sum category commodity cells = sum published column controls",
            sum(
                source_category.values[
                    :,
                    source_category.column_index[category],
                ],
            ),
            published_category_controls[category],
            37.0 * column_count,
        )
    end
    for (position, code) in pairs(source_final_use.row_codes)
        add_residual!(
            residuals,
            :source_final_use_row_partition,
            code,
            "20 source columns = seven declared categories",
            sum(source_final_use.values[position, :]),
            sum(source_category.values[position, :]),
            0.0,
        )
    end
    for (position, code) in pairs(model_final_use.row_codes)
        add_residual!(
            residuals,
            :model_final_use_row_partition,
            code,
            "20 model columns = seven declared categories",
            sum(model_final_use.values[position, :]),
            sum(model_category.values[position, :]),
            0.0,
        )
    end
    for (position, code) in pairs(closure_final_use.row_codes)
        add_residual!(
            residuals,
            :closure_final_use_row_partition,
            code,
            "20 closure columns = seven declared categories",
            sum(closure_final_use.values[position, :]),
            sum(closure_category.values[position, :]),
            0.0,
        )
    end
    for code in FINAL_USE_CODES
        add_residual!(
            residuals,
            :final_use_source_to_model_aggregation,
            code,
            "source column = model core + closure",
            sum(source_final_use.values[:, source_final_use.column_index[code]]),
            sum(model_final_use.values[:, model_final_use.column_index[code]]) +
                sum(
                closure_final_use.values[
                    :,
                    closure_final_use.column_index[code],
                ],
            ),
            0.0,
        )
    end
    for category in CATEGORY_CODES
        add_residual!(
            residuals,
            :final_use_category_aggregation,
            category,
            "source category = model core + closure",
            sum(
                source_category.values[
                    :,
                    source_category.column_index[category],
                ],
            ),
            sum(
                model_category.values[
                    :,
                    model_category.column_index[category],
                ],
            ) +
                sum(
                closure_category.values[
                    :,
                    closure_category.column_index[category],
                ],
            ),
            0.0,
        )
    end
    add_residual!(
        residuals,
        :published_final_use_category_partition,
        "T019",
        "20 published final-use controls = seven category controls",
        sum(published_final_controls.values),
        sum(published_category_controls.values),
        0.0,
    )
    add_residual!(
        residuals,
        :value_added_published_control,
        "V001+V002+V003",
        "sum value-added cells = published value-added grand control",
        sum(value_added.values),
        gdp.published_income,
        published_rounding_tolerance(source_value_added_cell_count),
    )
    add_residual!(
        residuals,
        :industry_output_published_control,
        "T008",
        "sum industry-output controls = published output grand control",
        gdp.cell_industry_output,
        gdp.published_output,
        published_rounding_tolerance(source_industry_count),
    )
    source_intermediate_cell_count =
        length(source_final_use.row_codes) * source_industry_count
    add_residual!(
        residuals,
        :intermediate_use_published_control,
        "T001",
        "sum intermediate-use cells = published intermediate grand control",
        gdp.cell_intermediate_use,
        gdp.published_intermediate_use,
        published_rounding_tolerance(source_intermediate_cell_count),
    )
    add_residual!(
        residuals,
        :cell_gdp_expenditure_income,
        "GDP",
        "cell expenditure = cell income within publication rounding",
        gdp.cell_expenditure,
        gdp.cell_income,
        (
            length(source_final_use.values) +
                source_value_added_cell_count
        ) / 2,
    )
    add_residual!(
        residuals,
        :cell_gdp_production_income,
        "GDP",
        "cell output - cell intermediate use = cell income within publication rounding",
        gdp.cell_production,
        gdp.cell_income,
        (
            source_industry_count +
                source_intermediate_cell_count +
                source_value_added_cell_count
        ) / 2,
    )
    add_residual!(
        residuals,
        :published_gdp_expenditure_income,
        "GDP",
        "published expenditure = published income",
        gdp.published_expenditure,
        gdp.published_income,
        0.0,
    )
    add_residual!(
        residuals,
        :published_gdp_production_income,
        "GDP",
        "published output - intermediate use = published income",
        gdp.published_production,
        gdp.published_income,
        0.0,
    )

    add_residual!(
        residuals,
        :observed_tax_control,
        "T015",
        "model observed tax + closure tax = source observed tax",
        sum(observed_tax_variant.commodity_net_product_tax.values) +
            sum(closure_net_product_tax.values),
        source_net_product_tax_total,
        0.0,
    )
    add_residual!(
        residuals,
        :zero_tax_policy_control,
        "T015_ZERO",
        "explicit-zero policy variant = zero",
        sum(zero_tax_variant.commodity_net_product_tax.values),
        0.0,
        0.0,
    )
    return residuals
end

function append_industry_identity_residuals!(
        residuals,
        model_intermediate,
        closure_intermediate,
        value_added,
        industry_output,
        source_industry_mapping,
    )
    for (position, code) in pairs(industry_output.codes)
        source_count =
            count(==(code), values(source_industry_mapping))
        lhs =
            sum(model_intermediate.values[:, position]) +
            sum(closure_intermediate.values[:, position]) +
            sum(value_added.values[:, position])
        add_residual!(
            residuals,
            :model_industry_output_identity,
            code,
            "model intermediate inputs + closure inputs + value added = industry output",
            lhs,
            industry_output.values[position],
            38.5 * source_count,
        )
    end
    return residuals
end

function expected_residual_family_counts()
    return Dict(
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
end

function final_use_envelope_internal_controls_pass(
        report::FinalUseEnvelopeReport,
    )
    report.year == 2024 || return false
    all(residual.passed for residual in report.residuals) || return false
    residual_family_counts(report.residuals) ==
        expected_residual_family_counts() || return false
    report.contract_sha256 == APPROVED_CONTRACT_SHA256 || return false
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
    report.valuation_contract_sha256 ==
        APPROVED_VALUATION_CONTRACT_SHA256 || return false
    report.source_status == EXPECTED_STATUS || return false
    report.transformation ==
        :code_keyed_final_use_partition_with_explicit_closure ||
        return false
    report.price_basis == :producers_prices || return false
    report.closure_policy == :used_other_separate_unallocated ||
        return false
    report.inventory_policy == :f030_signed_flow_not_stock || return false
    report.import_policy ==
        :f050_signed_accounting_offset_not_model_import_vector ||
        return false
    report.observed_tax_variant_policy ==
        :control_only_not_use_cell_allocated || return false
    report.zero_tax_variant_policy ==
        :policy_counterfactual_not_observation || return false
    any(
        (
            report.final_use_adjustment_applied,
            report.closure_allocation_applied,
            report.inventory_stock_mapping_applied,
            report.import_boundary_selected,
            report.legacy_scalar_bridge_applied,
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

    bridge = report.legacy_bridge
    bridge.method ==
        :t013_over_t016_commodity_ratio_with_proportional_recipient_rescale ||
        return false
    bridge.status == :rejected_not_cell_identified || return false
    bridge.cell_identified && return false
    bridge.recipient_allocation_observed && return false
    bridge.diagnostic_only || return false
    bridge.applied && return false
    bridge.model_state_admissible && return false
    bridge.forecast_origin_admissible && return false

    try
        source_codes = report.source_commodity_codes
        model_codes = report.model_codes
        closure_codes = report.closure_codes
        source_codes == report.source_final_use.row_codes || return false
        length(source_codes) == 73 || return false
        length(unique(source_codes)) == 73 || return false
        length(model_codes) == 68 || return false
        length(unique(model_codes)) == 68 || return false
        closure_codes == ["Used", "Other"] || return false
        report.final_use_codes == FINAL_USE_CODES || return false
        report.category_codes == CATEGORY_CODES || return false
        report.category_columns == EXPECTED_CATEGORY_COLUMNS || return false
        length(report.source_commodity_mapping) == 73 || return false
        length(report.source_industry_mapping) == 71 || return false

        report.source_final_use.column_codes == FINAL_USE_CODES ||
            return false
        report.source_category_final_use.row_codes == source_codes ||
            return false
        report.source_category_final_use.column_codes == CATEGORY_CODES ||
            return false
        report.model_final_use.row_codes == model_codes || return false
        report.model_final_use.column_codes == FINAL_USE_CODES ||
            return false
        report.model_category_final_use.row_codes == model_codes ||
            return false
        report.model_category_final_use.column_codes == CATEGORY_CODES ||
            return false
        report.closure_final_use.row_codes == closure_codes || return false
        report.closure_final_use.column_codes == FINAL_USE_CODES ||
            return false
        report.closure_category_final_use.row_codes == closure_codes ||
            return false
        report.closure_category_final_use.column_codes == CATEGORY_CODES ||
            return false

        expected_source_categories = aggregate_categories(
            report.source_final_use,
            CATEGORY_CODES,
            EXPECTED_CATEGORY_COLUMNS,
        )
        structurally_equal(
            report.source_category_final_use,
            expected_source_categories,
        ) || return false
        expected_model = aggregate_commodity_rows(
            report.source_final_use,
            model_codes,
            report.source_commodity_mapping,
        )
        expected_closure = aggregate_commodity_rows(
            report.source_final_use,
            closure_codes,
            report.source_commodity_mapping,
        )
        structurally_equal(report.model_final_use, expected_model) ||
            return false
        structurally_equal(report.closure_final_use, expected_closure) ||
            return false
        structurally_equal(
            report.model_category_final_use,
            aggregate_categories(
                report.model_final_use,
                CATEGORY_CODES,
                EXPECTED_CATEGORY_COLUMNS,
            ),
        ) || return false
        structurally_equal(
            report.closure_category_final_use,
            aggregate_categories(
                report.closure_final_use,
                CATEGORY_CODES,
                EXPECTED_CATEGORY_COLUMNS,
            ),
        ) || return false

        report.model_intermediate_use.row_codes == model_codes ||
            return false
        report.model_intermediate_use.column_codes == model_codes ||
            return false
        report.closure_intermediate_use.row_codes == closure_codes ||
            return false
        report.closure_intermediate_use.column_codes == model_codes ||
            return false
        report.producer_value_added.row_codes == VALUE_ADDED_CODES ||
            return false
        report.producer_value_added.column_codes == model_codes ||
            return false
        report.industry_output.codes == model_codes || return false
        report.published_final_use_controls.codes == FINAL_USE_CODES ||
            return false
        report.published_category_controls.codes == CATEGORY_CODES ||
            return false
        expected_published_categories = Float64[
            sum(
                    report.published_final_use_controls[column]
                    for column in EXPECTED_CATEGORY_COLUMNS[category]
                ) for category in CATEGORY_CODES
        ]
        report.published_category_controls.values ==
            expected_published_categories || return false

        gdp = report.gdp
        cell_expenditure =
            sum(report.model_final_use.values) +
            sum(report.closure_final_use.values)
        cell_income = sum(report.producer_value_added.values)
        cell_industry_output = sum(report.industry_output.values)
        cell_intermediate_use =
            sum(report.model_intermediate_use.values) +
            sum(report.closure_intermediate_use.values)
        isequal(gdp.cell_expenditure, cell_expenditure) || return false
        isequal(gdp.cell_income, cell_income) || return false
        isequal(gdp.cell_industry_output, cell_industry_output) ||
            return false
        isequal(gdp.cell_intermediate_use, cell_intermediate_use) ||
            return false
        isequal(
            gdp.cell_production,
            cell_industry_output - cell_intermediate_use,
        ) || return false
        isequal(
            gdp.published_expenditure,
            sum(report.published_final_use_controls.values),
        ) || return false
        isequal(
            gdp.published_production,
            gdp.published_output - gdp.published_intermediate_use,
        ) || return false
        isequal(
            gdp.cell_expenditure_income_gap,
            gdp.cell_expenditure - gdp.cell_income,
        ) || return false
        isequal(
            gdp.cell_production_income_gap,
            gdp.cell_production - gdp.cell_income,
        ) || return false
        isequal(
            gdp.published_expenditure_income_gap,
            gdp.published_expenditure - gdp.published_income,
        ) || return false
        isequal(
            gdp.published_production_income_gap,
            gdp.published_production - gdp.published_income,
        ) || return false

        observed = report.observed_tax_variant
        zero = report.zero_tax_variant
        observed.name == :observed || return false
        observed.source_semantics ==
            :table_262_t015_current_vintage_control || return false
        observed.use_cell_allocation == :none || return false
        observed.commodity_net_product_tax.codes == model_codes ||
            return false
        zero.name == :explicit_zero || return false
        zero.source_semantics == :policy_zero_not_observation ||
            return false
        zero.use_cell_allocation == :none || return false
        zero.commodity_net_product_tax.codes == model_codes || return false
        all(iszero, zero.commodity_net_product_tax.values) || return false
        report.closure_net_product_tax_control.codes == closure_codes ||
            return false
        for variant in (observed, zero)
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
            negative_cells(report.source_final_use),
            report.negative_source_final_use_cells,
        ) || return false
        negative_cell_vectors_match(
            negative_cells(report.model_final_use),
            report.negative_model_final_use_cells,
        ) || return false
        negative_cell_vectors_match(
            negative_cells(report.closure_final_use),
            report.negative_closure_final_use_cells,
        ) || return false
        negative_cell_vectors_match(
            negative_cells(report.model_category_final_use),
            report.negative_model_category_cells,
        ) || return false
        negative_cell_vectors_match(
            negative_cells(report.closure_category_final_use),
            report.negative_closure_category_cells,
        ) || return false
        negative_cell_vectors_match(
            negative_cells(report.producer_value_added),
            report.negative_value_added_cells,
        ) || return false
    catch
        return false
    end
    return true
end

function _build_final_use_envelope(
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
    )
    validated = validate_contract(
        contract_path,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
    )
    fixture = load_after_redefinitions_fixture(after_directory)
    model_core = build_model_core_aggregation(
        fixture,
        model_mapping_path;
        sector_mapping_path,
    )
    valuation = build_valuation_envelope(
        valuation_contract_path;
        supply_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
    )

    source_final_use = fixture.producer_final_use
    source_final_use.row_codes ==
        fixture.producer_commodity_output_make.codes ||
        throw(ArgumentError("source final-use commodity order changed"))
    source_final_use.column_codes == FINAL_USE_CODES ||
        throw(ArgumentError("source final-use columns changed"))
    model_final_use = model_core.producer_final_use
    closure_final_use = model_core.closure.producer_final_use
    category_columns = validated.category_columns
    source_category = aggregate_categories(
        source_final_use,
        CATEGORY_CODES,
        category_columns,
    )
    model_category = aggregate_categories(
        model_final_use,
        CATEGORY_CODES,
        category_columns,
    )
    closure_category = aggregate_categories(
        closure_final_use,
        CATEGORY_CODES,
        category_columns,
    )

    published_final_controls =
        fixture.producer_final_use_column_controls
    published_final_controls.codes == FINAL_USE_CODES ||
        throw(ArgumentError("published final-use control order changed"))
    published_category_controls =
        LabeledVector{FinalUseCategoryBasis}(
        CATEGORY_CODES,
        Float64[
            sum(
                    published_final_controls[column]
                    for column in category_columns[category]
                ) for category in CATEGORY_CODES
        ],
    )

    cell_expenditure =
        sum(model_final_use.values) + sum(closure_final_use.values)
    cell_income = sum(model_core.producer_value_added.values)
    cell_industry_output = sum(model_core.industry_output.values)
    cell_intermediate_use =
        sum(model_core.producer_intermediate_use.values) +
        sum(model_core.closure.producer_intermediate_use.values)
    published_expenditure = sum(published_final_controls.values)
    published_income = fixture.producer_value_added_grand_control
    published_output = fixture.producer_output_grand_control
    published_intermediate_use =
        fixture.producer_intermediate_grand_control
    cell_production = cell_industry_output - cell_intermediate_use
    published_production = published_output - published_intermediate_use
    gdp = GDPApproachLedger(
        cell_expenditure,
        cell_income,
        cell_industry_output,
        cell_intermediate_use,
        cell_production,
        published_expenditure,
        published_income,
        published_output,
        published_intermediate_use,
        published_production,
        cell_expenditure - cell_income,
        cell_production - cell_income,
        published_expenditure - published_income,
        published_production - published_income,
    )

    closure_tax_position =
        valuation.closure_supply_components.column_index["T015"]
    closure_tax = LabeledVector{CommodityBasis}(
        model_core.closure_codes,
        valuation.closure_supply_components.values[:, closure_tax_position],
    )
    source_net_product_tax_total =
        valuation.component_cell_sums["T015"]
    residuals = build_residuals(
        source_final_use,
        source_category,
        model_final_use,
        model_category,
        closure_final_use,
        closure_category,
        model_core.producer_value_added,
        model_core.industry_output,
        published_final_controls,
        published_category_controls,
        gdp,
        model_core.source_industry_mapping,
        valuation.observed_tax_variant,
        closure_tax,
        source_net_product_tax_total,
        valuation.zero_tax_variant,
        category_columns,
    )
    append_industry_identity_residuals!(
        residuals,
        model_core.producer_intermediate_use,
        model_core.closure.producer_intermediate_use,
        model_core.producer_value_added,
        model_core.industry_output,
        model_core.source_industry_mapping,
    )

    legacy_bridge = LegacyValuationBridgeAssessment(
        :t013_over_t016_commodity_ratio_with_proportional_recipient_rescale,
        :rejected_not_cell_identified,
        false,
        false,
        true,
        false,
        false,
        false,
    )
    blockers = vcat(
        EXPECTED_BLOCKER_PREFIX,
        valuation.promotion_blockers,
    )
    report = FinalUseEnvelopeReport(
        2024,
        copy(source_final_use.row_codes),
        model_core.model_codes,
        model_core.closure_codes,
        FINAL_USE_CODES,
        CATEGORY_CODES,
        category_columns,
        model_core.source_commodity_mapping,
        model_core.source_industry_mapping,
        source_final_use,
        source_category,
        model_final_use,
        model_category,
        closure_final_use,
        closure_category,
        model_core.producer_intermediate_use,
        model_core.closure.producer_intermediate_use,
        model_core.producer_value_added,
        model_core.industry_output,
        published_final_controls,
        published_category_controls,
        valuation.observed_tax_variant,
        valuation.zero_tax_variant,
        closure_tax,
        source_net_product_tax_total,
        gdp,
        residuals,
        negative_cells(source_final_use),
        negative_cells(model_final_use),
        negative_cells(closure_final_use),
        negative_cells(model_category),
        negative_cells(closure_category),
        negative_cells(model_core.producer_value_added),
        validated.contract_sha256,
        APPROVED_AFTER_FIXTURE_SHA256,
        APPROVED_AFTER_MANIFEST_SHA256,
        APPROVED_AFTER_SOURCE_ZIP_SHA256,
        APPROVED_MODEL_MAPPING_SHA256,
        APPROVED_SECTOR_MAPPING_SHA256,
        APPROVED_VALUATION_CONTRACT_SHA256,
        String(validated.after_manifest["status"]),
        :code_keyed_final_use_partition_with_explicit_closure,
        :producers_prices,
        :used_other_separate_unallocated,
        :f030_signed_flow_not_stock,
        :f050_signed_accounting_offset_not_model_import_vector,
        :control_only_not_use_cell_allocated,
        :policy_counterfactual_not_observation,
        legacy_bridge,
        false,
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
    final_use_envelope_internal_controls_pass(report) ||
        throw(ArgumentError("final-use-envelope internal controls do not pass"))
    return report
end

"""
    final_use_envelope_controls_pass(report, contract_path; paths...)

Public source-aware stale-report gate. The contract path is required; there is
no report-only overload that could be mistaken for provenance attestation.
"""
function final_use_envelope_controls_pass(
        report::FinalUseEnvelopeReport,
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
    )
    try
        expected = _build_final_use_envelope(
            contract_path;
            after_directory,
            supply_directory,
            model_mapping_path,
            sector_mapping_path,
            valuation_contract_path,
        )
        return structurally_equal(report, expected)
    catch
        return false
    end
end

"""
    build_final_use_envelope(contract_path; paths...)

Build the research-only producer-price final-use and GDP envelope from pinned
sources and require both internal and source-aware controls.
"""
function build_final_use_envelope(
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
    )
    report = _build_final_use_envelope(
        contract_path;
        after_directory,
        supply_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
    )
    final_use_envelope_controls_pass(
        report,
        contract_path;
        after_directory,
        supply_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
    ) || throw(ArgumentError("final-use-envelope source controls do not pass"))
    return report
end

end
