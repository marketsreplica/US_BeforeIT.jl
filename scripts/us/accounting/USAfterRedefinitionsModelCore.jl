module USAfterRedefinitionsModelCore

using LinearAlgebra
using SHA
using Statistics
using TOML

using ..USSupplyMakeDiagnostics:
    AxisBasis,
    CommodityBasis,
    ControlResidual,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector
using ..USSymmetricSupplyUse: NegativeCell, negative_cells
using ..USAfterRedefinitionsCommonBasis:
    AfterRedefinitionsFixture,
    AfterRedefinitionsProvenance,
    AfterRedefinitionsValueAddedBasis,
    FinalUseBasis,
    build_common_basis_report,
    common_basis_controls_pass,
    load_after_redefinitions_fixture

export ClosureAccountLedger,
    ImportAllocationLedger,
    ModelCoreCommutationResidualCell,
    ModelCoreAggregationReport,
    build_model_core_aggregation,
    model_core_internal_controls_pass,
    model_core_controls_pass,
    model_core_source_controls_pass

const MAPPING_SCHEMA =
    "beforeit-us-after-redefinitions-model-core-mapping.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_MAPPING_SHA256 =
    "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c"
const APPROVED_SECTOR_MAPPING_SHA256 =
    "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f"
const APPROVED_COMMON_BASIS_FIXTURE_SHA256 =
    "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac"
const APPROVED_COMMON_BASIS_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
)
const RETAIL_SOURCE_CODES = ("441", "445", "452", "4A0")
const NUMERICAL_TOLERANCE_MILLIONS_USD = 1.0e-6
const EXPECTED_PROMOTION_BLOCKERS = (
    "RETAIL_AGGREGATION_NOT_VALIDATED_ACROSS_ORIGIN_VINTAGES",
    "PRODUCT_TAX_PRODUCER_TO_BASIC_CELL_ALLOCATION_NOT_PROVIDED",
    "2017_PURCHASER_PRODUCER_BENCHMARK_NOT_A_2024_ALLOCATOR",
    "OTHER_USED_NOT_ALLOCATED_TO_68_SECTOR_CORE",
    "NEGATIVE_CELL_POLICY_NOT_APPROVED",
    "IMPORT_ALLOCATION_IS_SEPARATE_IMPUTED_EVIDENCE",
    "IMPORT_MATRIX_DOMESTIC_BOUNDARY_NOT_SELECTED",
    "IMPORT_SIGNED_REALLOCATIONS_EXCLUDING_F050_REQUIRE_REVIEW",
    "FINAL_USE_AND_VALUE_ADDED_COMMON_BASIS_NOT_FULLY_RECONCILED",
    "INVENTORY_HOLDER_AND_STAGE_MAPPINGS_NOT_PROVIDED",
    "LATENT_STATE_RECONCILIATION_NOT_APPLIED",
    "AFTER_REDEFINITIONS_FIXTURE_NOT_PROSPECTIVELY_CAPTURED",
    "CURRENT_VINTAGE_NOT_FORECAST_ORIGIN_ELIGIBLE",
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

struct ModelCoreCommutationResidualCell
    input_code::String
    output_code::String
    aggregated_source_value::Float64
    recomputed_value::Float64
    difference::Float64
end

"""
Typed summary of BEA's separate imputed import-allocation matrix.

Positive entries allocate imports to uses. `F050` is the signed accounting
offset that removes imports from total final use. The ledger is not a matrix
of independently measured bilateral imports and is not subtracted from the
producer-price use table.
"""
struct ImportAllocationLedger
    import_f050_offset::LabeledVector{CommodityBasis}
    import_f050_explicit::BitVector
    allocation_excluding_f050_total::Float64
    f050_total::Float64
    net_total::Float64
    negative_cells::Vector{NegativeCell}
    negative_f050_cells::Vector{NegativeCell}
    negative_allocation_cells::Vector{NegativeCell}
    import_role::Symbol
    sign_convention::Symbol
    domestic_use_subtraction_applied::Bool
end

"""
The two published closure commodities kept outside the 68×68 model core.

The ledger retains their intermediate/final/import uses, make/output controls,
and every cross-block symmetric transaction. `Used` and `Other` are not
silently dropped, allocated, or renamed as inventory/statistical discrepancy.
"""
struct ClosureAccountLedger
    codes::Vector{String}
    producer_intermediate_use::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    producer_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    producer_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    commodity_output::LabeledVector{CommodityBasis}
    commodity_output_explicit::BitVector
    import_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    import_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    import_allocation::ImportAllocationLedger
    model_input_to_closure_output::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    closure_input_to_model_output::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    closure_input_to_closure_output::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    negative_intermediate_cells::Vector{NegativeCell}
    negative_make_cells::Vector{NegativeCell}
    negative_symmetric_cells::Vector{NegativeCell}
    allocation_applied::Bool
end

"""
Producer-price aggregation from the pinned 73-commodity/71-industry source
system to the declared 68×68 model core.

Only retail source codes `441`, `445`, `452`, and `4A0` are summed to model
code `4A0`. `Used` and `Other` remain typed closure accounts. The report
separately retains:

1. the source 73×73 symmetric transactions aggregated to 70 accounts; and
2. transactions recomputed after the four retail industries become one.

For this pinned table, every retail make row has exactly one nonzero output,
mapped to the same aggregate retail commodity, so the two routes commute in
exact arithmetic. Their stored difference is a floating-point summation-order
residual. It is not an economic technology effect, is not balanced away, and
is not an accuracy statistic.
"""
struct ModelCoreAggregationReport
    year::Int
    model_codes::Vector{String}
    closure_codes::Vector{String}
    source_commodity_mapping::Dict{String, String}
    source_industry_mapping::Dict{String, String}
    producer_intermediate_use::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    producer_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    producer_value_added::LabeledMatrix{
        AfterRedefinitionsValueAddedBasis,
        IndustryBasis,
    }
    producer_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    commodity_output::LabeledVector{CommodityBasis}
    commodity_output_explicit::BitVector
    industry_output::LabeledVector{IndustryBasis}
    industry_output_explicit::BitVector
    direct_by_industry::LabeledMatrix{CommodityBasis, IndustryBasis}
    market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    product_mix::LabeledMatrix{IndustryBasis, CommodityBasis}
    symmetric_intermediate_use::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    import_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    import_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    import_allocation::ImportAllocationLedger
    closure::ClosureAccountLedger
    source_aggregated_symmetric_use::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    recomputed_aggregated_symmetric_use::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    joint_aggregation_commutation_residual::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    residuals::Vector{ControlResidual}
    signed_joint_aggregation_commutation_residual::Float64
    absolute_joint_aggregation_commutation_residual::Float64
    joint_aggregation_commutation_frobenius_residual::Float64
    source_recomputed_cell_correlation::Float64
    maximum_joint_aggregation_commutation_residual_cell::
    ModelCoreCommutationResidualCell
    negative_intermediate_cells::Vector{NegativeCell}
    negative_make_cells::Vector{NegativeCell}
    negative_symmetric_cells::Vector{NegativeCell}
    source_provenance::AfterRedefinitionsProvenance
    source_status::String
    mapping_sha256::String
    sector_mapping_sha256::String
    transformation::Symbol
    price_basis::Symbol
    import_role::Symbol
    import_sign_convention::Symbol
    domestic_use_subtraction_applied::Bool
    closure_policy::Symbol
    aggregation_applied::Bool
    valuation_bridge_applied::Bool
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

function aligned_values(matrix::LabeledMatrix, row_codes, column_codes)
    Set(matrix.row_codes) == Set(row_codes) ||
        throw(ArgumentError("matrix row codes do not match the requested axis"))
    Set(matrix.column_codes) == Set(column_codes) ||
        throw(ArgumentError("matrix column codes do not match the requested axis"))
    return Float64[
        matrix[row_code, column_code]
            for row_code in row_codes, column_code in column_codes
    ]
end

function aligned_explicit(matrix::LabeledMatrix, row_codes, column_codes)
    Set(matrix.row_codes) == Set(row_codes) ||
        throw(ArgumentError("matrix row codes do not match the requested axis"))
    Set(matrix.column_codes) == Set(column_codes) ||
        throw(ArgumentError("matrix column codes do not match the requested axis"))
    return BitMatrix(
        [
            matrix.explicit[
                    matrix.row_index[row_code],
                    matrix.column_index[column_code],
                ]
                for row_code in row_codes, column_code in column_codes
        ],
    )
end

function aligned_vector_values(vector::LabeledVector, codes)
    Set(vector.codes) == Set(codes) ||
        throw(ArgumentError("vector codes do not match the requested axis"))
    return Float64[vector[code] for code in codes]
end

function derived_matrix(::Type{R}, ::Type{C}, rows, columns, values) where {
        R <: AxisBasis,
        C <: AxisBasis,
    }
    return LabeledMatrix{R, C}(
        rows,
        columns,
        values,
        falses(size(values)),
    )
end

function validate_mapping(
        mapping_path::AbstractString,
        sector_mapping_path::AbstractString,
    )
    mapping_bytes = read(mapping_path)
    mapping_sha256 = sha256_hex(mapping_bytes)
    mapping_sha256 == APPROVED_MAPPING_SHA256 ||
        throw(ArgumentError("model-core mapping SHA-256 changed"))
    sector_mapping_bytes = read(sector_mapping_path)
    sector_mapping_sha256 = sha256_hex(sector_mapping_bytes)
    sector_mapping_sha256 == APPROVED_SECTOR_MAPPING_SHA256 ||
        throw(ArgumentError("sector mapping SHA-256 changed"))

    mapping = TOML.parse(String(mapping_bytes))
    sector_mapping = TOML.parse(String(sector_mapping_bytes))
    get(mapping, "schema_version", "") == MAPPING_SCHEMA ||
        throw(ArgumentError("unsupported model-core mapping schema"))
    get(mapping, "classification", "") == EXPECTED_STATUS ||
        throw(ArgumentError("model-core mapping status changed"))
    get(mapping, "promotion_status", "") == EXPECTED_PROMOTION_STATUS ||
        throw(ArgumentError("model-core mapping promotion status changed"))
    get(mapping, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("model-core mapping cannot admit an origin"))
    get(mapping, "model_state_write", true) === false ||
        throw(ArgumentError("model-core mapping cannot write model state"))
    get(mapping, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("model-core mapping cannot affect accounting gates"))
    get(mapping, "source_year", 0) == 2024 ||
        throw(ArgumentError("model-core mapping source year changed"))
    get(mapping, "source_price_basis", "") == "producers prices" ||
        throw(ArgumentError("model-core mapping price basis changed"))
    get(mapping, "source_commodity_count", 0) == 73 ||
        throw(ArgumentError("model-core source commodity count changed"))
    get(mapping, "source_industry_count", 0) == 71 ||
        throw(ArgumentError("model-core source industry count changed"))
    get(mapping, "model_commodity_count", 0) == 68 ||
        throw(ArgumentError("model-core commodity count changed"))
    get(mapping, "model_industry_count", 0) == 68 ||
        throw(ArgumentError("model-core industry count changed"))
    get(mapping, "common_basis_fixture_sha256", "") ==
        APPROVED_COMMON_BASIS_FIXTURE_SHA256 ||
        throw(ArgumentError("model-core source fixture identity changed"))
    get(mapping, "sector_mapping_sha256", "") ==
        APPROVED_SECTOR_MAPPING_SHA256 ||
        throw(ArgumentError("model-core sector mapping identity changed"))
    get(mapping, "sector_mapping_path", "") == "scripts/us/bea71.toml" ||
        throw(ArgumentError("model-core sector mapping path changed"))
    String.(get(mapping, "retail_source_codes", String[])) ==
        ["441", "445", "452", "4A0"] ||
        throw(ArgumentError("model-core retail source codes changed"))
    get(mapping, "retail_model_code", "") == "4A0" ||
        throw(ArgumentError("model-core retail target changed"))
    String.(get(mapping, "closure_account_codes", String[])) ==
        ["Used", "Other"] ||
        throw(ArgumentError("model-core closure accounts changed"))

    model_codes = String.(get(mapping, "model_codes", String[]))
    length(model_codes) == 68 &&
        length(unique(model_codes)) == 68 ||
        throw(ArgumentError("model-core codes are not 68 unique members"))
    sector_codes =
        String.(get(get(sector_mapping, "model", Dict()), "codes", String[]))
    model_codes == sector_codes ||
        throw(ArgumentError("model-core and sector-contract codes differ"))
    return (;
        mapping,
        model_codes,
        closure_codes = ["Used", "Other"],
        mapping_sha256,
        sector_mapping_sha256,
    )
end

function source_mapping(source_codes, model_codes, closure_codes; industry)
    targets = Set(model_codes)
    closures = Set(closure_codes)
    result = Dict{String, String}()
    for source_code in String.(source_codes)
        if !industry && source_code in closures
            result[source_code] = source_code
        elseif source_code in RETAIL_SOURCE_CODES
            result[source_code] = "4A0"
        elseif source_code in targets
            result[source_code] = source_code
        else
            throw(ArgumentError("unmapped source code $source_code"))
        end
    end
    expected_targets = industry ? targets : union(targets, closures)
    Set(values(result)) == expected_targets ||
        throw(ArgumentError("source mapping does not cover every target"))
    return result
end

function aggregate_matrix(
        ::Type{R},
        ::Type{C},
        matrix::LabeledMatrix,
        target_rows,
        target_columns,
        row_mapping,
        column_mapping,
    ) where {R <: AxisBasis, C <: AxisBasis}
    row_index =
        Dict(code => position for (position, code) in pairs(target_rows))
    column_index =
        Dict(code => position for (position, code) in pairs(target_columns))
    values = zeros(length(target_rows), length(target_columns))
    explicit = falses(size(values))
    for (source_row_position, source_row_code) in pairs(matrix.row_codes)
        target_row_position = row_index[row_mapping[source_row_code]]
        for (
                source_column_position,
                source_column_code,
            ) in pairs(matrix.column_codes)
            target_column_position =
                column_index[column_mapping[source_column_code]]
            values[target_row_position, target_column_position] +=
                matrix.values[source_row_position, source_column_position]
            explicit[target_row_position, target_column_position] |=
                matrix.explicit[
                source_row_position,
                source_column_position,
            ]
        end
    end
    return LabeledMatrix{R, C}(
        target_rows,
        target_columns,
        values,
        explicit,
    )
end

function aggregate_vector(
        ::Type{B},
        vector::LabeledVector,
        explicit,
        target_codes,
        mapping,
    ) where {B <: AxisBasis}
    length(explicit) == length(vector.codes) ||
        throw(ArgumentError("source vector explicit mask has the wrong length"))
    target_index =
        Dict(code => position for (position, code) in pairs(target_codes))
    values = zeros(length(target_codes))
    target_explicit = falses(length(target_codes))
    for (source_position, source_code) in pairs(vector.codes)
        target_position = target_index[mapping[source_code]]
        values[target_position] += vector.values[source_position]
        target_explicit[target_position] |= explicit[source_position]
    end
    return (
        LabeledVector{B}(target_codes, values),
        BitVector(target_explicit),
    )
end

function subset_matrix(
        ::Type{R},
        ::Type{C},
        matrix::LabeledMatrix,
        rows,
        columns,
    ) where {R <: AxisBasis, C <: AxisBasis}
    all(haskey(matrix.row_index, code) for code in rows) ||
        throw(ArgumentError("requested row is absent from the source matrix"))
    all(haskey(matrix.column_index, code) for code in columns) ||
        throw(ArgumentError("requested column is absent from the source matrix"))
    values = Float64[
        matrix[row_code, column_code]
            for row_code in rows, column_code in columns
    ]
    explicit = BitMatrix(
        [
            matrix.explicit[
                    matrix.row_index[row_code],
                    matrix.column_index[column_code],
                ]
                for row_code in rows, column_code in columns
        ],
    )
    return LabeledMatrix{R, C}(
        rows,
        columns,
        values,
        explicit,
    )
end

function scale_aware_close(lhs, rhs; atol = 1.0e-10, rtol = 1.0e-12)
    size(lhs) == size(rhs) || return false
    scale = max(1.0, maximum(abs, lhs), maximum(abs, rhs))
    return maximum(abs, lhs - rhs) <= atol + rtol * scale
end

function matrix_axes_match(matrix::LabeledMatrix, rows, columns)
    matrix.row_codes == rows || return false
    matrix.column_codes == columns || return false
    matrix.row_index ==
        Dict(code => position for (position, code) in pairs(rows)) ||
        return false
    matrix.column_index ==
        Dict(code => position for (position, code) in pairs(columns)) ||
        return false
    return size(matrix.values) == (length(rows), length(columns)) &&
        size(matrix.explicit) == size(matrix.values)
end

function vector_axis_matches(vector::LabeledVector, codes)
    vector.codes == codes || return false
    vector.index ==
        Dict(code => position for (position, code) in pairs(codes)) ||
        return false
    return length(vector.values) == length(codes)
end

function negative_cells_match(stored, matrix::LabeledMatrix)
    expected = negative_cells(matrix)
    return negative_cell_vectors_match(stored, expected)
end

function negative_cell_vectors_match(stored, expected)
    length(stored) == length(expected) || return false
    return all(
        lhs.row_code == rhs.row_code &&
            lhs.column_code == rhs.column_code &&
            isequal(lhs.value, rhs.value)
            for (lhs, rhs) in zip(stored, expected)
    )
end

function build_import_allocation_ledger(
        intermediate::LabeledMatrix{CommodityBasis, IndustryBasis},
        final::LabeledMatrix{CommodityBasis, FinalUseBasis},
    )
    intermediate.row_codes == final.row_codes ||
        throw(ArgumentError("import-allocation commodity axes differ"))
    f050_position = something(findfirst(==("F050"), final.column_codes))
    commodity_codes = intermediate.row_codes
    f050_values = final.values[:, f050_position]
    negative_f050_cells = NegativeCell[
        NegativeCell(code, "F050", f050_values[position])
            for (position, code) in pairs(commodity_codes)
            if f050_values[position] < 0
    ]
    negative_allocation_cells = vcat(
        negative_cells(intermediate),
        NegativeCell[
            NegativeCell(
                    commodity_codes[row_position],
                    final.column_codes[column_position],
                    final.values[row_position, column_position],
                )
                for row_position in eachindex(commodity_codes)
                for column_position in eachindex(final.column_codes)
                if final.column_codes[column_position] != "F050" &&
                final.values[row_position, column_position] < 0
        ],
    )
    return ImportAllocationLedger(
        LabeledVector{CommodityBasis}(commodity_codes, f050_values),
        BitVector(final.explicit[:, f050_position]),
        sum(intermediate.values) +
            sum(final.values) -
            sum(f050_values),
        sum(f050_values),
        sum(intermediate.values) + sum(final.values),
        vcat(negative_cells(intermediate), negative_cells(final)),
        negative_f050_cells,
        negative_allocation_cells,
        :separate_bea_imputed_import_allocation,
        :positive_allocated_uses_plus_signed_f050_accounting_offset,
        false,
    )
end

function residual_snapshots_are_consistent(residuals)
    return all(residuals) do residual
        all(
            isfinite,
            (
                residual.lhs,
                residual.rhs,
                residual.residual,
                residual.tolerance,
            ),
        ) || return false
        residual.tolerance >= 0 || return false
        isequal(residual.residual, residual.lhs - residual.rhs) ||
            return false
        return residual.passed ==
            (abs(residual.residual) <= residual.tolerance)
    end
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

function model_core_internal_controls_pass(report::ModelCoreAggregationReport)
    all(residual.passed for residual in report.residuals) || return false
    residual_snapshots_are_consistent(report.residuals) || return false
    residual_family_counts = Dict(
        family => count(residual -> residual.family == family, report.residuals)
            for family in unique(residual.family for residual in report.residuals)
    )
    residual_family_counts == Dict(
        :model_core_intermediate_aggregation => 1,
        :model_core_final_use_aggregation => 1,
        :model_core_value_added_aggregation => 1,
        :model_core_make_aggregation => 1,
        :model_core_import_intermediate_aggregation => 1,
        :model_core_import_final_aggregation => 1,
        :model_core_commodity_output_aggregation => 1,
        :model_core_industry_output_aggregation => 1,
        :model_core_commodity_use_output_control => 70,
        :model_core_commodity_make_output_control => 70,
        :model_core_market_share_normalization => 70,
        :model_core_import_offset_control => 70,
        :model_core_industry_make_output_control => 68,
        :model_core_industry_use_output_control => 68,
        :model_core_product_mix_normalization => 68,
        :model_core_symmetric_block_assembly => 1,
        :model_core_joint_aggregation_commutation => 1,
    ) || return false
    report.source_status == EXPECTED_STATUS || return false
    report.mapping_sha256 == APPROVED_MAPPING_SHA256 || return false
    report.sector_mapping_sha256 == APPROVED_SECTOR_MAPPING_SHA256 ||
        return false
    report.source_provenance.fixture_sha256 ==
        APPROVED_COMMON_BASIS_FIXTURE_SHA256 || return false
    report.aggregation_applied || return false
    report.valuation_bridge_applied && return false
    report.balancing_applied && return false
    report.clipping_applied && return false
    report.model_state_write && return false
    report.accounting_gate_effect == :none || return false
    report.forecast_origin_admissible && return false
    report.promotion_ready && return false
    report.closure.allocation_applied && return false
    report.transformation ==
        :code_keyed_retail_sum_with_explicit_closure_accounts || return false
    report.price_basis == :producers_prices || return false
    report.import_role == :separate_bea_imputed_import_allocation ||
        return false
    report.import_sign_convention ==
        :positive_allocated_uses_plus_signed_f050_accounting_offset ||
        return false
    report.domestic_use_subtraction_applied && return false
    report.closure_policy == :used_other_separate_unallocated || return false
    report.promotion_blockers == collect(EXPECTED_PROMOTION_BLOCKERS) ||
        return false
    try
        model_codes = report.model_codes
        closure_codes = report.closure_codes
        length(model_codes) == 68 || return false
        length(unique(model_codes)) == 68 || return false
        closure_codes == ["Used", "Other"] || return false
        report.closure.codes == closure_codes || return false
        account_codes = vcat(model_codes, closure_codes)
        industry_codes = report.industry_output.codes
        industry_codes == model_codes || return false
        final_use_codes = report.producer_final_use.column_codes
        length(final_use_codes) == 20 || return false
        length(unique(final_use_codes)) == 20 || return false
        "F030" in final_use_codes || return false
        "F050" in final_use_codes || return false
        value_added_codes = report.producer_value_added.row_codes
        value_added_codes == ["V001", "V002", "V003"] || return false

        expected_commodity_mapping = source_mapping(
            collect(keys(report.source_commodity_mapping)),
            model_codes,
            closure_codes;
            industry = false,
        )
        report.source_commodity_mapping == expected_commodity_mapping ||
            return false
        expected_industry_mapping = source_mapping(
            collect(keys(report.source_industry_mapping)),
            model_codes,
            closure_codes;
            industry = true,
        )
        report.source_industry_mapping == expected_industry_mapping ||
            return false
        length(report.source_commodity_mapping) == 73 || return false
        length(report.source_industry_mapping) == 71 || return false

        matrix_axes_match(
            report.producer_intermediate_use,
            model_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.producer_final_use,
            model_codes,
            final_use_codes,
        ) || return false
        matrix_axes_match(
            report.producer_value_added,
            value_added_codes,
            model_codes,
        ) || return false
        matrix_axes_match(report.producer_make, model_codes, model_codes) ||
            return false
        vector_axis_matches(report.commodity_output, model_codes) ||
            return false
        vector_axis_matches(report.industry_output, model_codes) ||
            return false
        length(report.commodity_output_explicit) == length(model_codes) ||
            return false
        length(report.industry_output_explicit) == length(model_codes) ||
            return false
        matrix_axes_match(
            report.import_intermediate_use,
            model_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.import_final_use,
            model_codes,
            final_use_codes,
        ) || return false
        structurally_equal(
            report.import_allocation,
            build_import_allocation_ledger(
                report.import_intermediate_use,
                report.import_final_use,
            ),
        ) || return false
        report.import_allocation.import_role == report.import_role ||
            return false
        report.import_allocation.sign_convention ==
            report.import_sign_convention || return false
        report.import_allocation.domestic_use_subtraction_applied ==
            report.domestic_use_subtraction_applied || return false

        matrix_axes_match(
            report.closure.producer_intermediate_use,
            closure_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.closure.producer_final_use,
            closure_codes,
            final_use_codes,
        ) || return false
        matrix_axes_match(
            report.closure.producer_make,
            model_codes,
            closure_codes,
        ) || return false
        vector_axis_matches(
            report.closure.commodity_output,
            closure_codes,
        ) || return false
        length(report.closure.commodity_output_explicit) ==
            length(closure_codes) || return false
        matrix_axes_match(
            report.closure.import_intermediate_use,
            closure_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.closure.import_final_use,
            closure_codes,
            final_use_codes,
        ) || return false
        structurally_equal(
            report.closure.import_allocation,
            build_import_allocation_ledger(
                report.closure.import_intermediate_use,
                report.closure.import_final_use,
            ),
        ) || return false
        report.closure.import_allocation.import_role == report.import_role ||
            return false
        report.closure.import_allocation.sign_convention ==
            report.import_sign_convention || return false
        report.closure.import_allocation.domestic_use_subtraction_applied ==
            report.domestic_use_subtraction_applied || return false

        matrix_axes_match(
            report.direct_by_industry,
            model_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.market_shares,
            model_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.product_mix,
            model_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.symmetric_intermediate_use,
            model_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.closure.model_input_to_closure_output,
            model_codes,
            closure_codes,
        ) || return false
        matrix_axes_match(
            report.closure.closure_input_to_model_output,
            closure_codes,
            model_codes,
        ) || return false
        matrix_axes_match(
            report.closure.closure_input_to_closure_output,
            closure_codes,
            closure_codes,
        ) || return false
        matrix_axes_match(
            report.source_aggregated_symmetric_use,
            account_codes,
            account_codes,
        ) || return false
        matrix_axes_match(
            report.recomputed_aggregated_symmetric_use,
            account_codes,
            account_codes,
        ) || return false
        matrix_axes_match(
            report.joint_aggregation_commutation_residual,
            account_codes,
            account_codes,
        ) || return false
        any(report.direct_by_industry.explicit) && return false
        any(report.market_shares.explicit) && return false
        any(report.product_mix.explicit) && return false
        any(report.symmetric_intermediate_use.explicit) && return false
        any(report.closure.model_input_to_closure_output.explicit) &&
            return false
        any(report.closure.closure_input_to_model_output.explicit) &&
            return false
        any(report.closure.closure_input_to_closure_output.explicit) &&
            return false
        any(report.source_aggregated_symmetric_use.explicit) && return false
        any(report.recomputed_aggregated_symmetric_use.explicit) &&
            return false
        any(report.joint_aggregation_commutation_residual.explicit) &&
            return false

        U = report.producer_intermediate_use.values
        V = report.producer_make.values
        q = report.commodity_output.values
        g = report.industry_output.values
        direct = U ./ reshape(g, 1, :)
        market = V ./ reshape(q, 1, :)
        product_mix = V ./ reshape(g, :, 1)
        symmetric = U * product_mix
        scale_aware_close(direct, report.direct_by_industry.values) ||
            return false
        scale_aware_close(market, report.market_shares.values) ||
            return false
        scale_aware_close(product_mix, report.product_mix.values) ||
            return false
        scale_aware_close(
            symmetric,
            report.symmetric_intermediate_use.values;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false

        closure_U = report.closure.producer_intermediate_use.values
        closure_V = report.closure.producer_make.values
        closure_q = report.closure.commodity_output.values
        full_U = vcat(U, closure_U)
        full_F = vcat(
            report.producer_final_use.values,
            report.closure.producer_final_use.values,
        )
        full_V = hcat(V, closure_V)
        full_q = vcat(q, closure_q)
        full_import_U = vcat(
            report.import_intermediate_use.values,
            report.closure.import_intermediate_use.values,
        )
        full_import_F = vcat(
            report.import_final_use.values,
            report.closure.import_final_use.values,
        )
        commodity_source_counts = Dict(
            code => count(
                    ==(code),
                    values(report.source_commodity_mapping),
                )
                for code in account_codes
        )
        industry_source_counts = Dict(
            code => count(
                    ==(code),
                    values(report.source_industry_mapping),
                )
                for code in model_codes
        )
        for (position, code) in pairs(account_codes)
            source_count = commodity_source_counts[code]
            abs(
                sum(full_U[position, :]) +
                    sum(full_F[position, :]) -
                    full_q[position],
            ) <= 46.0 * source_count || return false
            abs(sum(full_V[:, position]) - full_q[position]) <=
                36.0 * source_count || return false
            abs(
                sum(full_import_U[position, :]) +
                    sum(full_import_F[position, :]),
            ) <= 45.5 * source_count || return false
            abs(sum(full_V[:, position] ./ full_q[position]) - 1.0) <=
                36.0 * source_count / full_q[position] || return false
        end
        for (position, code) in pairs(model_codes)
            source_count = industry_source_counts[code]
            abs(sum(full_V[position, :]) - g[position]) <=
                37.0 * source_count || return false
            abs(
                sum(full_U[:, position]) +
                    sum(report.producer_value_added.values[:, position]) -
                    g[position],
            ) <= 38.5 * source_count || return false
            abs(sum(full_V[position, :] ./ g[position]) - 1.0) <=
                37.0 * source_count / g[position] || return false
        end
        closure_product_mix = closure_V ./ reshape(g, :, 1)
        core_U_to_closure = U * closure_product_mix
        closure_U_to_core = closure_U * product_mix
        closure_U_to_closure = closure_U * closure_product_mix
        scale_aware_close(
            core_U_to_closure,
            report.closure.model_input_to_closure_output.values;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false
        scale_aware_close(
            closure_U_to_core,
            report.closure.closure_input_to_model_output.values;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false
        scale_aware_close(
            closure_U_to_closure,
            report.closure.closure_input_to_closure_output.values;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false
        recomputed_full = vcat(U, closure_U) *
            hcat(product_mix, closure_product_mix)
        scale_aware_close(
            recomputed_full,
            aligned_values(
                report.recomputed_aggregated_symmetric_use,
                account_codes,
                account_codes,
            );
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false
        scale_aware_close(
            recomputed_full[1:length(model_codes), 1:length(model_codes)],
            report.symmetric_intermediate_use.values;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false
        scale_aware_close(
            recomputed_full[
                1:length(model_codes),
                (length(model_codes) + 1):end,
            ],
            core_U_to_closure;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false
        scale_aware_close(
            recomputed_full[
                (length(model_codes) + 1):end,
                1:length(model_codes),
            ],
            closure_U_to_core;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false
        scale_aware_close(
            recomputed_full[
                (length(model_codes) + 1):end,
                (length(model_codes) + 1):end,
            ],
            closure_U_to_closure;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false

        source_symmetric = report.source_aggregated_symmetric_use.values
        commutation_residual = recomputed_full - source_symmetric
        maximum(abs, commutation_residual) <=
            NUMERICAL_TOLERANCE_MILLIONS_USD || return false
        scale_aware_close(
            commutation_residual,
            report.joint_aggregation_commutation_residual.values;
            atol = NUMERICAL_TOLERANCE_MILLIONS_USD,
        ) || return false
        isapprox(
            report.signed_joint_aggregation_commutation_residual,
            sum(commutation_residual);
            atol = 1.0e-12,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.absolute_joint_aggregation_commutation_residual,
            sum(abs, commutation_residual);
            atol = 1.0e-12,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.joint_aggregation_commutation_frobenius_residual,
            norm(commutation_residual);
            atol = 1.0e-12,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.source_recomputed_cell_correlation,
            cor(vec(source_symmetric), vec(recomputed_full));
            atol = 1.0e-15,
            rtol = 1.0e-15,
        ) || return false
        maximum_index = argmax(abs.(commutation_residual))
        maximum_cell =
            report.maximum_joint_aggregation_commutation_residual_cell
        maximum_cell.input_code == account_codes[maximum_index[1]] ||
            return false
        maximum_cell.output_code == account_codes[maximum_index[2]] ||
            return false
        isequal(
            maximum_cell.aggregated_source_value,
            source_symmetric[maximum_index],
        ) || return false
        isequal(
            maximum_cell.recomputed_value,
            recomputed_full[maximum_index],
        ) || return false
        isequal(
            maximum_cell.difference,
            commutation_residual[maximum_index],
        ) || return false

        negative_cells_match(
            report.negative_intermediate_cells,
            report.producer_intermediate_use,
        ) || return false
        negative_cells_match(
            report.negative_make_cells,
            report.producer_make,
        ) || return false
        negative_cells_match(
            report.negative_symmetric_cells,
            report.symmetric_intermediate_use,
        ) || return false
        negative_cells_match(
            report.closure.negative_intermediate_cells,
            report.closure.producer_intermediate_use,
        ) || return false
        negative_cells_match(
            report.closure.negative_make_cells,
            report.closure.producer_make,
        ) || return false
        closure_symmetric = derived_matrix(
            CommodityBasis,
            CommodityBasis,
            account_codes,
            account_codes,
            vcat(
                hcat(
                    zeros(length(model_codes), length(model_codes)),
                    core_U_to_closure,
                ),
                hcat(closure_U_to_core, closure_U_to_closure),
            ),
        )
        negative_cells_match(
            report.closure.negative_symmetric_cells,
            closure_symmetric,
        ) || return false

        all(value -> isfinite(value) && value > 0, q) || return false
        all(value -> isfinite(value) && value > 0, closure_q) || return false
        all(value -> isfinite(value) && value > 0, g) || return false
    catch
        return false
    end
    return true
end

function _build_model_core_aggregation(
        fixture::AfterRedefinitionsFixture,
        mapping_path::AbstractString;
        sector_mapping_path::AbstractString = normpath(
            joinpath(@__DIR__, "..", "bea71.toml"),
        ),
    )
    approved_fixture = load_after_redefinitions_fixture(
        APPROVED_COMMON_BASIS_FIXTURE_DIRECTORY,
    )
    structurally_equal(fixture, approved_fixture) ||
        throw(
        ArgumentError(
            "in-memory common-basis fixture differs from the byte-pinned approved fixture",
        ),
    )
    common = build_common_basis_report(fixture)
    common_basis_controls_pass(common) ||
        throw(ArgumentError("source common-basis controls do not pass"))
    contract = validate_mapping(mapping_path, sector_mapping_path)
    model_codes = contract.model_codes
    closure_codes = contract.closure_codes
    account_codes = vcat(model_codes, closure_codes)

    source_commodity_codes =
        copy(fixture.producer_intermediate_use.row_codes)
    source_industry_codes =
        copy(fixture.producer_intermediate_use.column_codes)
    final_use_codes = copy(fixture.producer_final_use.column_codes)
    commodity_mapping = source_mapping(
        source_commodity_codes,
        model_codes,
        closure_codes;
        industry = false,
    )
    industry_mapping = source_mapping(
        source_industry_codes,
        model_codes,
        closure_codes;
        industry = true,
    )
    length(source_commodity_codes) == 73 ||
        throw(ArgumentError("source commodity count changed"))
    length(source_industry_codes) == 71 ||
        throw(ArgumentError("source industry count changed"))

    identity_final_mapping = Dict(code => code for code in final_use_codes)
    value_added_codes = copy(fixture.producer_value_added.row_codes)
    identity_value_added_mapping =
        Dict(code => code for code in value_added_codes)

    aggregated_U = aggregate_matrix(
        CommodityBasis,
        IndustryBasis,
        fixture.producer_intermediate_use,
        account_codes,
        model_codes,
        commodity_mapping,
        industry_mapping,
    )
    aggregated_F = aggregate_matrix(
        CommodityBasis,
        FinalUseBasis,
        fixture.producer_final_use,
        account_codes,
        final_use_codes,
        commodity_mapping,
        identity_final_mapping,
    )
    aggregated_VA = aggregate_matrix(
        AfterRedefinitionsValueAddedBasis,
        IndustryBasis,
        fixture.producer_value_added,
        value_added_codes,
        model_codes,
        identity_value_added_mapping,
        industry_mapping,
    )
    aggregated_V = aggregate_matrix(
        IndustryBasis,
        CommodityBasis,
        fixture.producer_make,
        model_codes,
        account_codes,
        industry_mapping,
        commodity_mapping,
    )
    aggregated_import_U = aggregate_matrix(
        CommodityBasis,
        IndustryBasis,
        fixture.import_intermediate_use,
        account_codes,
        model_codes,
        commodity_mapping,
        industry_mapping,
    )
    aggregated_import_F = aggregate_matrix(
        CommodityBasis,
        FinalUseBasis,
        fixture.import_final_use,
        account_codes,
        final_use_codes,
        commodity_mapping,
        identity_final_mapping,
    )

    q, q_explicit = aggregate_vector(
        CommodityBasis,
        fixture.producer_commodity_output_make,
        BitVector(
            fixture.source_explicit[
                "producer_make_commodity_output_2024",
            ][:, 1],
        ),
        account_codes,
        commodity_mapping,
    )
    g, g_explicit = aggregate_vector(
        IndustryBasis,
        fixture.producer_industry_output_make,
        BitVector(
            fixture.source_explicit[
                "producer_make_industry_output_2024",
            ][:, 1],
        ),
        model_codes,
        industry_mapping,
    )

    core_U = subset_matrix(
        CommodityBasis,
        IndustryBasis,
        aggregated_U,
        model_codes,
        model_codes,
    )
    core_F = subset_matrix(
        CommodityBasis,
        FinalUseBasis,
        aggregated_F,
        model_codes,
        final_use_codes,
    )
    core_V = subset_matrix(
        IndustryBasis,
        CommodityBasis,
        aggregated_V,
        model_codes,
        model_codes,
    )
    core_import_U = subset_matrix(
        CommodityBasis,
        IndustryBasis,
        aggregated_import_U,
        model_codes,
        model_codes,
    )
    core_import_F = subset_matrix(
        CommodityBasis,
        FinalUseBasis,
        aggregated_import_F,
        model_codes,
        final_use_codes,
    )
    core_q_values = Float64[q[code] for code in model_codes]
    core_q_explicit = BitVector(q_explicit[1:length(model_codes)])

    closure_U = subset_matrix(
        CommodityBasis,
        IndustryBasis,
        aggregated_U,
        closure_codes,
        model_codes,
    )
    closure_F = subset_matrix(
        CommodityBasis,
        FinalUseBasis,
        aggregated_F,
        closure_codes,
        final_use_codes,
    )
    closure_V = subset_matrix(
        IndustryBasis,
        CommodityBasis,
        aggregated_V,
        model_codes,
        closure_codes,
    )
    closure_import_U = subset_matrix(
        CommodityBasis,
        IndustryBasis,
        aggregated_import_U,
        closure_codes,
        model_codes,
    )
    closure_import_F = subset_matrix(
        CommodityBasis,
        FinalUseBasis,
        aggregated_import_F,
        closure_codes,
        final_use_codes,
    )
    core_import_allocation =
        build_import_allocation_ledger(core_import_U, core_import_F)
    closure_import_allocation =
        build_import_allocation_ledger(closure_import_U, closure_import_F)
    closure_q_values = Float64[q[code] for code in closure_codes]
    closure_q_explicit =
        BitVector(q_explicit[(length(model_codes) + 1):end])

    all(>(0), core_q_values) ||
        throw(ArgumentError("model-core commodity output is not positive"))
    all(>(0), closure_q_values) ||
        throw(ArgumentError("closure commodity output is not positive"))
    all(>(0), g.values) ||
        throw(ArgumentError("model-core industry output is not positive"))

    direct_values = core_U.values ./ reshape(g.values, 1, :)
    market_values = core_V.values ./ reshape(core_q_values, 1, :)
    product_mix_values = core_V.values ./ reshape(g.values, :, 1)
    closure_product_mix_values =
        closure_V.values ./ reshape(g.values, :, 1)
    symmetric_values = core_U.values * product_mix_values
    model_to_closure_values =
        core_U.values * closure_product_mix_values
    closure_to_model_values =
        closure_U.values * product_mix_values
    closure_to_closure_values =
        closure_U.values * closure_product_mix_values
    recomputed_full_values = vcat(core_U.values, closure_U.values) *
        hcat(product_mix_values, closure_product_mix_values)

    source_symmetric = aggregate_matrix(
        CommodityBasis,
        CommodityBasis,
        common.symmetric_intermediate_use,
        account_codes,
        account_codes,
        commodity_mapping,
        commodity_mapping,
    )
    recomputed_full = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        account_codes,
        account_codes,
        recomputed_full_values,
    )
    commutation_residual_values =
        recomputed_full_values - source_symmetric.values
    commutation_residual = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        account_codes,
        account_codes,
        commutation_residual_values,
    )

    residuals = ControlResidual[]
    for (family, aggregated_total, source_total, equation) in (
            (
                :model_core_intermediate_aggregation,
                sum(aggregated_U.values),
                sum(fixture.producer_intermediate_use.values),
                "aggregated intermediate uses preserve the 73x71 source total",
            ),
            (
                :model_core_final_use_aggregation,
                sum(aggregated_F.values),
                sum(fixture.producer_final_use.values),
                "aggregated final uses preserve the 73x20 source total",
            ),
            (
                :model_core_value_added_aggregation,
                sum(aggregated_VA.values),
                sum(fixture.producer_value_added.values),
                "aggregated value added preserves the 3x71 source total",
            ),
            (
                :model_core_make_aggregation,
                sum(aggregated_V.values),
                sum(fixture.producer_make.values),
                "aggregated make preserves the 71x73 source total",
            ),
            (
                :model_core_import_intermediate_aggregation,
                sum(aggregated_import_U.values),
                sum(fixture.import_intermediate_use.values),
                "aggregated import intermediate uses preserve the source total",
            ),
            (
                :model_core_import_final_aggregation,
                sum(aggregated_import_F.values),
                sum(fixture.import_final_use.values),
                "aggregated import final uses preserve the source total",
            ),
            (
                :model_core_commodity_output_aggregation,
                sum(q.values),
                sum(fixture.producer_commodity_output_make.values),
                "aggregated commodity outputs preserve the source total",
            ),
            (
                :model_core_industry_output_aggregation,
                sum(g.values),
                sum(fixture.producer_industry_output_make.values),
                "aggregated industry outputs preserve the source total",
            ),
        )
        add_residual!(
            residuals,
            family,
            "grand_total",
            equation,
            aggregated_total,
            source_total,
            0.0,
        )
    end

    commodity_source_counts = Dict(
        code => count(==(code), values(commodity_mapping))
            for code in account_codes
    )
    industry_source_counts = Dict(
        code => count(==(code), values(industry_mapping))
            for code in model_codes
    )
    full_U_values = vcat(core_U.values, closure_U.values)
    full_F_values = vcat(core_F.values, closure_F.values)
    full_V_values = hcat(core_V.values, closure_V.values)
    full_import_U_values =
        vcat(core_import_U.values, closure_import_U.values)
    full_import_F_values =
        vcat(core_import_F.values, closure_import_F.values)

    for (position, code) in pairs(account_codes)
        source_count = commodity_source_counts[code]
        commodity_rounding_tolerance = 46.0 * source_count
        make_rounding_tolerance = 36.0 * source_count
        add_residual!(
            residuals,
            :model_core_commodity_use_output_control,
            code,
            "aggregated intermediate plus final use = aggregated commodity output",
            sum(full_U_values[position, :]) +
                sum(full_F_values[position, :]),
            q.values[position],
            commodity_rounding_tolerance,
        )
        add_residual!(
            residuals,
            :model_core_commodity_make_output_control,
            code,
            "aggregated industry make = aggregated commodity output",
            sum(full_V_values[:, position]),
            q.values[position],
            make_rounding_tolerance,
        )
        add_residual!(
            residuals,
            :model_core_market_share_normalization,
            code,
            "aggregated commodity market shares sum to one",
            sum(full_V_values[:, position] ./ q.values[position]),
            1.0,
            make_rounding_tolerance / q.values[position],
        )
        add_residual!(
            residuals,
            :model_core_import_offset_control,
            code,
            "aggregated import allocations including F050 sum to zero",
            sum(full_import_U_values[position, :]) +
                sum(full_import_F_values[position, :]),
            0.0,
            45.5 * source_count,
        )
    end

    for (position, code) in pairs(model_codes)
        source_count = industry_source_counts[code]
        make_rounding_tolerance = 37.0 * source_count
        output_rounding_tolerance = 38.5 * source_count
        add_residual!(
            residuals,
            :model_core_industry_make_output_control,
            code,
            "aggregated make across core and closure commodities = industry output",
            sum(full_V_values[position, :]),
            g.values[position],
            make_rounding_tolerance,
        )
        add_residual!(
            residuals,
            :model_core_industry_use_output_control,
            code,
            "aggregated intermediate use plus value added = industry output",
            sum(full_U_values[:, position]) +
                sum(aggregated_VA.values[:, position]),
            g.values[position],
            output_rounding_tolerance,
        )
        add_residual!(
            residuals,
            :model_core_product_mix_normalization,
            code,
            "aggregated core plus closure product mix sums to one",
            sum(full_V_values[position, :] ./ g.values[position]),
            1.0,
            make_rounding_tolerance / g.values[position],
        )
    end
    add_residual!(
        residuals,
        :model_core_symmetric_block_assembly,
        "maximum_cell_error",
        "core and closure transaction blocks assemble the recomputed 70x70 system",
        maximum(
            abs,
            recomputed_full_values -
                vcat(
                hcat(symmetric_values, model_to_closure_values),
                hcat(
                    closure_to_model_values,
                    closure_to_closure_values,
                ),
            ),
        ),
        0.0,
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :model_core_joint_aggregation_commutation,
        "maximum_cell_difference",
        "joint retail commodity/industry aggregation commutes for the pinned diagonal retail make rows",
        maximum(abs, commutation_residual_values),
        0.0,
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )

    maximum_index = argmax(abs.(commutation_residual_values))
    maximum_cell = ModelCoreCommutationResidualCell(
        account_codes[maximum_index[1]],
        account_codes[maximum_index[2]],
        source_symmetric.values[maximum_index],
        recomputed_full_values[maximum_index],
        commutation_residual_values[maximum_index],
    )

    closure_symmetric = vcat(
        hcat(
            zeros(length(model_codes), length(model_codes)),
            model_to_closure_values,
        ),
        hcat(
            closure_to_model_values,
            closure_to_closure_values,
        ),
    )
    closure_ledger = ClosureAccountLedger(
        closure_codes,
        closure_U,
        closure_F,
        closure_V,
        LabeledVector{CommodityBasis}(
            closure_codes,
            closure_q_values,
        ),
        closure_q_explicit,
        closure_import_U,
        closure_import_F,
        closure_import_allocation,
        derived_matrix(
            CommodityBasis,
            CommodityBasis,
            model_codes,
            closure_codes,
            model_to_closure_values,
        ),
        derived_matrix(
            CommodityBasis,
            CommodityBasis,
            closure_codes,
            model_codes,
            closure_to_model_values,
        ),
        derived_matrix(
            CommodityBasis,
            CommodityBasis,
            closure_codes,
            closure_codes,
            closure_to_closure_values,
        ),
        negative_cells(closure_U),
        negative_cells(closure_V),
        negative_cells(
            derived_matrix(
                CommodityBasis,
                CommodityBasis,
                account_codes,
                account_codes,
                closure_symmetric,
            ),
        ),
        false,
    )
    blockers = collect(EXPECTED_PROMOTION_BLOCKERS)

    report = ModelCoreAggregationReport(
        fixture.year,
        model_codes,
        closure_codes,
        commodity_mapping,
        industry_mapping,
        core_U,
        core_F,
        aggregated_VA,
        core_V,
        LabeledVector{CommodityBasis}(model_codes, core_q_values),
        core_q_explicit,
        g,
        g_explicit,
        derived_matrix(
            CommodityBasis,
            IndustryBasis,
            model_codes,
            model_codes,
            direct_values,
        ),
        derived_matrix(
            IndustryBasis,
            CommodityBasis,
            model_codes,
            model_codes,
            market_values,
        ),
        derived_matrix(
            IndustryBasis,
            CommodityBasis,
            model_codes,
            model_codes,
            product_mix_values,
        ),
        derived_matrix(
            CommodityBasis,
            CommodityBasis,
            model_codes,
            model_codes,
            symmetric_values,
        ),
        core_import_U,
        core_import_F,
        core_import_allocation,
        closure_ledger,
        source_symmetric,
        recomputed_full,
        commutation_residual,
        residuals,
        sum(commutation_residual_values),
        sum(abs, commutation_residual_values),
        norm(commutation_residual_values),
        cor(
            vec(source_symmetric.values),
            vec(recomputed_full_values),
        ),
        maximum_cell,
        negative_cells(core_U),
        negative_cells(core_V),
        negative_cells(
            derived_matrix(
                CommodityBasis,
                CommodityBasis,
                model_codes,
                model_codes,
                symmetric_values,
            ),
        ),
        fixture.provenance,
        String(fixture.manifest["status"]),
        contract.mapping_sha256,
        contract.sector_mapping_sha256,
        :code_keyed_retail_sum_with_explicit_closure_accounts,
        :producers_prices,
        :separate_bea_imputed_import_allocation,
        :positive_allocated_uses_plus_signed_f050_accounting_offset,
        false,
        :used_other_separate_unallocated,
        true,
        false,
        false,
        false,
        false,
        :none,
        false,
        blockers,
        false,
    )
    model_core_internal_controls_pass(report) ||
        throw(ArgumentError("model-core aggregation controls do not pass"))
    return report
end

"""
    model_core_source_controls_pass(
        report,
        fixture,
        mapping_path;
        sector_mapping_path,
    )

Rebuild the complete diagnostic from the pinned source fixture and mapping
contracts, then compare every stored field recursively. This is the
source-aware stale-report check; `model_core_internal_controls_pass(report)`
verifies only the report's internal algebra and policy metadata without
reopening its source.
"""
function model_core_source_controls_pass(
        report::ModelCoreAggregationReport,
        fixture::AfterRedefinitionsFixture,
        mapping_path::AbstractString;
        sector_mapping_path::AbstractString = normpath(
            joinpath(@__DIR__, "..", "bea71.toml"),
        ),
    )
    try
        expected = _build_model_core_aggregation(
            fixture,
            mapping_path;
            sector_mapping_path,
        )
        return structurally_equal(report, expected)
    catch
        return false
    end
end

"""
    model_core_controls_pass(
        report,
        fixture,
        mapping_path;
        sector_mapping_path,
    )

Public source-aware gate. The fixture and both mapping contracts are required
so a downstream caller cannot accidentally treat the internal-only predicate
as a source/provenance attestation.
"""
function model_core_controls_pass(
        report::ModelCoreAggregationReport,
        fixture::AfterRedefinitionsFixture,
        mapping_path::AbstractString;
        sector_mapping_path::AbstractString = normpath(
            joinpath(@__DIR__, "..", "bea71.toml"),
        ),
    )
    return model_core_source_controls_pass(
        report,
        fixture,
        mapping_path;
        sector_mapping_path,
    )
end

"""
    build_model_core_aggregation(fixture, mapping_path; sector_mapping_path)

Build the research-only 68×68 producer-price model-core diagnostic and
separate `Used`/`Other` closure ledger from the byte-pinned common-basis
fixture. The returned report must pass both internal and source-aware controls.
"""
function build_model_core_aggregation(
        fixture::AfterRedefinitionsFixture,
        mapping_path::AbstractString;
        sector_mapping_path::AbstractString = normpath(
            joinpath(@__DIR__, "..", "bea71.toml"),
        ),
    )
    report = _build_model_core_aggregation(
        fixture,
        mapping_path;
        sector_mapping_path,
    )
    model_core_controls_pass(
        report,
        fixture,
        mapping_path;
        sector_mapping_path,
    ) || throw(ArgumentError("model-core source controls do not pass"))
    return report
end

end
