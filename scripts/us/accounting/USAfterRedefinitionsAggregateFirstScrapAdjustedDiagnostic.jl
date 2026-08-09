module USAfterRedefinitionsAggregateFirstScrapAdjustedDiagnostic

using LinearAlgebra
using SHA
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
    FinalUseBasis,
    load_after_redefinitions_fixture

export AccountingIdentityWitness,
    AggregateFirstScrapAdjustedDiagnosticReport,
    CoefficientAggregationWitness,
    MatrixDifferenceLedger,
    OtherOutputWitness,
    SignLedger,
    StabilityWitness,
    TransformedFlowWitness,
    VectorResidualSummary,
    aggregate_first_scrap_adjusted_diagnostic_controls_pass,
    aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass,
    build_aggregate_first_scrap_adjusted_diagnostic,
    materialize_aggregate_first_scrap_adjusted_model_state

const CONTRACT_SCHEMA =
    "beforeit-us-after-redefinitions-aggregate-first-scrap-adjusted-diagnostic.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_ARTIFACT_ROLE =
    "AGGREGATE_FIRST_68_SCRAP_ADJUSTED_DIAGNOSTIC_ONLY"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_CONTRACT_SHA256 =
    "5248278e3dac6d8ff262d0c3eeffa819819b1b619f15f352c8557764c4523c26"
const EXPECTED_CLOSURE_CODES = ["Used", "Other"]
const EXPECTED_METHODOLOGY_PAGES = [98, 123, 124, 214, 223, 224, 225]
const EXPECTED_ADDITIONAL_METHODOLOGY_PAGES = [213]
const RETAIL_SOURCE_CODE_ORDER = ["441", "445", "452", "4A0"]
const RETAIL_SOURCE_CODES = Set(RETAIL_SOURCE_CODE_ORDER)
const DIFFERENCE_THRESHOLD = 1.0e-9

const EXPECTED_SOURCE_MATRIX_MASK_SHA256 = Dict(
    :intermediate_use =>
        "14b57fa813059dd533b2f95f5966300d73a0b4c82b10cf1921524004c7aa69a8",
    :final_use =>
        "1416d35bf383c024d4a42c1cd77f6f299c355ab2dfca3310949737301a317acf",
    :make =>
        "b63cc65a38b658ed900f69cb02646c17fb7d7ceecffb6d71d317d74c2092abf2",
)
const EXPECTED_SOURCE_VECTOR_MASK_SHA256 = Dict(
    :commodity_output =>
        "3cd15194ad28eab01fec46faee93c2fcf20e386a5811927a4a2c3671543195a6",
    :industry_output =>
        "3cd15194ad28eab01fec46faee93c2fcf20e386a5811927a4a2c3671543195a6",
    :scrap_output =>
        "7dd05ab78aa0f475d1d175db03e98b8ab33bae72cc842e27f332d86a8c3ca7cd",
    :other_output =>
        "96e76a07ea99ac770d6f2b0e13ff96697f0bc0c83242e2330ed933f9a811e1f9",
)
const EXPECTED_DERIVED_VECTOR_KEYS = Set(
    [
        :commodity_output,
        :industry_output,
        :scrap_output,
        :other_output,
        :scrap_shares,
        :nonscrap_ratios,
        :final_demand,
    ],
)

const EXPECTED_PROMOTION_BLOCKERS = [
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

const EXPECTED_FORBIDDEN_RUNTIME_KEYS = [
    "U",
    "a",
    "beta",
    "prices",
    "quantities",
    "RoW_financial_counterpart",
    "row_adjustment_observation_operator",
    "FIGARO",
    "parameters",
    "initial_conditions",
    "model_state",
]

const EXPECTED_BYTE_PINS = Dict(
    "after_redefinitions_fixture_sha256" =>
        "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac",
    "after_redefinitions_manifest_sha256" =>
        "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030",
    "after_redefinitions_source_zip_sha256" =>
        "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da",
    "after_redefinitions_source_metadata_sha256" =>
        "8be9fbef6e2c18a7388cd61bd14312159fc3984d4dbc2c60158e977ee7f0e878",
    "after_redefinitions_producer_use_workbook_sha256" =>
        "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7",
    "after_redefinitions_producer_make_workbook_sha256" =>
        "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6",
    "model_mapping_sha256" =>
        "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c",
    "sector_mapping_sha256" =>
        "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f",
    "closure_boundary_contract_sha256" =>
        "ad6f1995575b1fa612577eb4001e9163159d6802fa947d6f5385a2d07758172f",
    "methodology_pdf_sha256" =>
        "535627e5e44f8461c0a04410f4a05c55d47f2e325d9473cb2df06e5d3e6b271d",
    "methodology_receipt_sha256" =>
        "b4b210be3c364415473f1ef407ed7ea6e9edc2b299bd1058c1658b0ebb3b91ac",
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
const DEFAULT_CLOSURE_BOUNDARY_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_closure_boundary_candidate.toml")
const DEFAULT_METHODOLOGY_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_io_concepts_methods_2006_approved",
)
const DEFAULT_METHODOLOGY_PDF_PATH = joinpath(
    DEFAULT_METHODOLOGY_DIRECTORY,
    "Concepts_and_Methods_US_IO_Accounts_2006.pdf",
)
const DEFAULT_METHODOLOGY_RECEIPT_PATH =
    joinpath(DEFAULT_METHODOLOGY_DIRECTORY, "receipt.toml")

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
mask_sha256(mask) = sha256_hex(UInt8.(vec(mask)))

"""Signed-value ledger that never clips, normalizes, or redistributes."""
struct SignLedger
    total::Float64
    negative_count::Int
    negative_total::Float64
    positive_count::Int
    positive_total::Float64
    zero_count::Int
    minimum::Float64
    maximum::Float64
    absolute_total::Float64
end

"""Compact summary of a labeled accounting-residual vector."""
struct VectorResidualSummary
    signed_total::Float64
    absolute_total::Float64
    maximum_absolute_residual::Float64
    maximum_residual_code::String
    maximum_residual_value::Float64
    nonzero_count::Int
    negative_count::Int
    positive_count::Int
end

"""Labeled matrix-difference diagnostics at a fixed materiality threshold."""
struct MatrixDifferenceLedger
    signed_total::Float64
    absolute_total::Float64
    frobenius_norm::Float64
    maximum_absolute_difference::Float64
    maximum_row_code::String
    maximum_column_code::String
    value_at_maximum::Float64
    material_cell_count::Int
    materiality_threshold::Float64
    relative_absolute_total::Float64
end

"""
Source-71 coefficient comparator for this pinned table.

The conditional comparison uses commodity-output composition weights
`Cq=diag(q71)A'diag(q68)^-1`. Equality is not a general aggregation
identity: this witness is valid only because all four merged retail source
rows satisfy the separately recorded zero-closure and own-commodity make
preconditions. The raw `A*W71*A'` shortcut is retained only as an explicit
falsification witness.
"""
struct CoefficientAggregationWitness
    comparator_scope::Symbol
    merged_source_codes::Vector{String}
    merged_zero_scrap_output::Bool
    merged_zero_other_output::Bool
    merged_own_commodity_make_only::Bool
    merged_own_make_equals_industry_output::Bool
    source_input_coefficients::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    source_market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    source_scrap_shares::LabeledVector{IndustryBasis}
    source_nonscrap_transform::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    source_requirements::LabeledMatrix{CommodityBasis, CommodityBasis}
    q_composition_weights::LabeledMatrix{CommodityBasis, CommodityBasis}
    conditional_current_table_aggregate_w::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    conditional_current_table_w_difference::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    conditional_current_table_w_ledger::MatrixDifferenceLedger
    conditional_current_table_aggregate_h::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    conditional_current_table_h_difference::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    conditional_current_table_h_ledger::MatrixDifferenceLedger
    raw_unweighted_w_shortcut::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    raw_unweighted_w_difference::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    raw_unweighted_w_ledger::MatrixDifferenceLedger
    raw_unweighted_w_shortcut_accepted::Bool
end

"""Aggregate-first versus source-first transformed-flow noncommutation."""
struct TransformedFlowWitness
    aggregate_first_intermediate::LabeledMatrix{
        IndustryBasis,
        IndustryBasis,
    }
    source_first_intermediate::LabeledMatrix{
        IndustryBasis,
        IndustryBasis,
    }
    intermediate_difference::LabeledMatrix{
        IndustryBasis,
        IndustryBasis,
    }
    intermediate_difference_ledger::MatrixDifferenceLedger
    aggregate_first_final_use::LabeledMatrix{
        IndustryBasis,
        FinalUseBasis,
    }
    source_first_final_use::LabeledMatrix{IndustryBasis, FinalUseBasis}
    final_use_difference::LabeledMatrix{IndustryBasis, FinalUseBasis}
    final_use_difference_ledger::MatrixDifferenceLedger
    combined_row_difference::LabeledVector{IndustryBasis}
    combined_row_difference_summary::VectorResidualSummary
    aggregate_first_intermediate_signs::SignLedger
    source_first_intermediate_signs::SignLedger
    aggregate_first_final_use_signs::SignLedger
    source_first_final_use_signs::SignLedger
end

"""
Published current-dollar identity residuals and their formula-only floating
point differences. Source residuals are evidence; formula differences should
be near machine precision and are never used to erase the source residuals.
"""
struct AccountingIdentityWitness
    make_source_residual::LabeledVector{IndustryBasis}
    make_source_summary::VectorResidualSummary
    market_share_formula_residual::LabeledVector{IndustryBasis}
    market_share_formula_summary::VectorResidualSummary
    market_share_minus_make_fp::LabeledVector{IndustryBasis}
    market_share_minus_make_fp_summary::VectorResidualSummary
    nonscrap_formula_residual::LabeledVector{IndustryBasis}
    nonscrap_formula_summary::VectorResidualSummary
    nonscrap_residual_from_make::LabeledVector{IndustryBasis}
    nonscrap_minus_make_propagation_fp::LabeledVector{IndustryBasis}
    nonscrap_minus_make_propagation_fp_summary::VectorResidualSummary
    use_source_residual::LabeledVector{CommodityBasis}
    use_source_summary::VectorResidualSummary
    input_coefficient_formula_residual::LabeledVector{CommodityBasis}
    input_coefficient_formula_summary::VectorResidualSummary
    input_coefficient_minus_use_fp::LabeledVector{CommodityBasis}
    input_coefficient_minus_use_fp_summary::VectorResidualSummary
end

"""Arithmetic witness for the unresolved `Other` output term."""
struct OtherOutputWitness
    omission_residual::LabeledVector{CommodityBasis}
    omission_summary::VectorResidualSummary
    arithmetic_output_term::LabeledVector{CommodityBasis}
    arithmetic_output_term_signs::SignLedger
    adjusted_equation_residual::LabeledVector{CommodityBasis}
    adjusted_equation_summary::VectorResidualSummary
    no_other_solution::LabeledVector{CommodityBasis}
    no_other_solution_residual::LabeledVector{CommodityBasis}
    no_other_solution_summary::VectorResidualSummary
    arithmetic_other_solution::LabeledVector{CommodityBasis}
    arithmetic_other_solution_residual::LabeledVector{CommodityBasis}
    arithmetic_other_solution_summary::VectorResidualSummary
    role::Symbol
    boundary_selected::Bool
end

"""Numerical stability evidence for the two diagnostic linear systems."""
struct StabilityWitness
    spectral_radius_requirements::Float64
    nonscrap_operator_condition::Float64
    leontief_operator_condition::Float64
end

"""
Same-table aggregate-first 68-sector scrap-adjusted diagnostic.

Every source level comes from one byte-pinned after-redefinitions fixture.
The separately published official market-share archive is deliberately
absent. This report is a current-vintage arithmetic diagnostic and has no
runtime materialization path.
"""
struct AggregateFirstScrapAdjustedDiagnosticReport
    year::Int
    source_codes::Vector{String}
    model_codes::Vector{String}
    final_use_codes::Vector{String}
    source_industry_mapping::Dict{String, String}
    industry_aggregation::LabeledMatrix{IndustryBasis, IndustryBasis}
    commodity_aggregation::LabeledMatrix{CommodityBasis, CommodityBasis}
    source_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    source_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    source_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    source_commodity_output::LabeledVector{CommodityBasis}
    source_industry_output::LabeledVector{IndustryBasis}
    source_scrap_output::LabeledVector{IndustryBasis}
    source_other_output::LabeledVector{IndustryBasis}
    source_vector_explicit::Dict{Symbol, BitVector}
    aggregate_intermediate_use::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    aggregate_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    aggregate_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    aggregate_commodity_output::LabeledVector{CommodityBasis}
    aggregate_industry_output::LabeledVector{IndustryBasis}
    aggregate_scrap_output::LabeledVector{IndustryBasis}
    aggregate_other_output::LabeledVector{IndustryBasis}
    input_coefficients::LabeledMatrix{CommodityBasis, IndustryBasis}
    market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    scrap_shares::LabeledVector{IndustryBasis}
    nonscrap_ratios::LabeledVector{IndustryBasis}
    nonscrap_transform::LabeledMatrix{IndustryBasis, CommodityBasis}
    requirements::LabeledMatrix{CommodityBasis, CommodityBasis}
    final_demand::LabeledVector{CommodityBasis}
    leontief_inverse::LabeledMatrix{CommodityBasis, CommodityBasis}
    derived_vector_explicit::Dict{Symbol, BitVector}
    coefficients::CoefficientAggregationWitness
    flows::TransformedFlowWitness
    identities::AccountingIdentityWitness
    other::OtherOutputWitness
    stability::StabilityWitness
    sign_ledgers::Dict{Symbol, SignLedger}
    negative_make_cells::Vector{NegativeCell}
    negative_market_share_cells::Vector{NegativeCell}
    negative_nonscrap_transform_cells::Vector{NegativeCell}
    residuals::Vector{ControlResidual}
    contract_sha256::String
    byte_pins::Dict{String, String}
    source_status::String
    methodology_status::String
    artifact_role::Symbol
    promotion_status::Symbol
    source_frequency::Symbol
    unit::Symbol
    price_basis::Symbol
    policies::Dict{Symbol, Symbol}
    flags::Dict{Symbol, Bool}
    emitted_runtime_keys::Vector{String}
    forbidden_runtime_keys::Vector{String}
    promotion_blockers::Vector{String}
    accounting_gate_effect::Symbol
    promotion_ready::Bool
end

function derived_matrix(
        ::Type{R},
        ::Type{C},
        row_codes,
        column_codes,
        values,
    ) where {R <: AxisBasis, C <: AxisBasis}
    return LabeledMatrix{R, C}(
        row_codes,
        column_codes,
        values,
        falses(size(values)),
    )
end

function sign_ledger(values)
    numeric = Float64.(collect(values))
    negatives = numeric[numeric .< 0.0]
    positives = numeric[numeric .> 0.0]
    return SignLedger(
        sum(numeric),
        length(negatives),
        sum(negatives; init = 0.0),
        length(positives),
        sum(positives; init = 0.0),
        count(iszero, numeric),
        minimum(numeric),
        maximum(numeric),
        sum(abs, numeric),
    )
end

sign_ledger(matrix::LabeledMatrix) = sign_ledger(matrix.values)
sign_ledger(vector::LabeledVector) = sign_ledger(vector.values)

function residual_summary(vector::LabeledVector)
    maximum_position = argmax(abs.(vector.values))
    maximum_value = vector.values[maximum_position]
    return VectorResidualSummary(
        sum(vector.values),
        sum(abs, vector.values),
        abs(maximum_value),
        vector.codes[maximum_position],
        maximum_value,
        count(!iszero, vector.values),
        count(<(0.0), vector.values),
        count(>(0.0), vector.values),
    )
end

function difference_ledger(matrix::LabeledMatrix; denominator)
    values = matrix.values
    maximum_position = argmax(abs.(values))
    row_position, column_position = Tuple(maximum_position)
    absolute_total = sum(abs, values)
    numeric_denominator = Float64(denominator)
    return MatrixDifferenceLedger(
        sum(values),
        absolute_total,
        norm(values),
        abs(values[maximum_position]),
        matrix.row_codes[row_position],
        matrix.column_codes[column_position],
        values[maximum_position],
        count(>(DIFFERENCE_THRESHOLD), abs.(values)),
        DIFFERENCE_THRESHOLD,
        iszero(numeric_denominator) ? Inf : absolute_total / numeric_denominator,
    )
end

function matrix_axes_match(matrix::LabeledMatrix, rows, columns)
    return matrix.row_codes == rows &&
        matrix.column_codes == columns &&
        matrix.row_index ==
        Dict(code => position for (position, code) in pairs(rows)) &&
        matrix.column_index ==
        Dict(code => position for (position, code) in pairs(columns)) &&
        size(matrix.values) == (length(rows), length(columns)) &&
        size(matrix.explicit) == size(matrix.values)
end

function vector_axis_matches(vector::LabeledVector, codes)
    return vector.codes == codes &&
        vector.index ==
        Dict(code => position for (position, code) in pairs(codes)) &&
        length(vector.values) == length(codes)
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

function expected_policies()
    return Dict(
        :same_table_source => :only_pinned_after_redefinitions_v_u_f_q_g,
        :official_cross_archive_d => :forbidden_not_loaded_not_accepted,
        :final_use => :all_20_signed_columns,
        :aggregation_order => :aggregate_levels_before_ratios_and_w,
        :source_first_comparison =>
            :q_composition_weighted_coefficients_plus_flow_level_noncommutation,
        :coefficient_comparator_scope =>
            :current_table_numerical_witness_not_a_general_aggregation_identity,
        :raw_unweighted_w_shortcut => :explicitly_rejected,
        :other_term => :arithmetic_omission_witness_only,
        :used_make_component =>
            :h_is_the_make_side_scrap_component_of_composite_used_not_the_used_use_or_final_asset_transfer_rows,
        :other_make_component =>
            :o_and_t_other_are_make_side_arithmetic_closure_witnesses_not_allocations_of_other_use_or_final_rows,
        :special_use_exclusion =>
            :used_and_other_use_and_final_rows_excluded_from_u68_and_e68_and_retained_in_the_closure_boundary_sidecar,
        :negative_cell => :preserve_and_ledger,
        :rounding =>
            :preserve_published_current_dollar_residuals_and_separate_formula_floating_point,
        :explicit_mask =>
            :preserve_source_masks_derived_values_have_false_mask,
    )
end

function expected_flags()
    return Dict(
        :aggregate_first_diagnostic => true,
        :runtime_transform_selected => false,
        :apply_to_runtime_u => false,
        :apply_to_runtime_a => false,
        :apply_to_runtime_beta => false,
        :raw_unweighted_w_shortcut_accepted => false,
        :other_boundary_selected => false,
        :current_dollar_price_quantity_decomposition => false,
        :quarterly_dynamic_law => false,
        :financial_counterpart_mapping => false,
        :row_adjustment_observation_operator => false,
        :double_entry_transition_tests => false,
        :runtime_calibration_admissible => false,
        :calibration_dictionary_write => false,
        :figaro_dictionary_write => false,
        :parameter_write => false,
        :initial_conditions_write => false,
        :model_state_write => false,
        :forecast_origin_admissible => false,
        :balancing_applied => false,
        :clipping_applied => false,
        :normalization_applied => false,
        :raking_applied => false,
    )
end

function require_hash(path, expected, label)
    sha256_hex(read(path)) == expected ||
        throw(ArgumentError("$label SHA-256 changed"))
    return expected
end

function require_contract_value(contract, key, expected)
    get(contract, key, nothing) == expected ||
        throw(ArgumentError("aggregate-first contract field $key changed"))
    return expected
end

function validate_contract(
        contract_path,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        closure_boundary_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    contract_sha256 =
        require_hash(contract_path, APPROVED_CONTRACT_SHA256, "contract")
    contract = TOML.parsefile(contract_path)
    scalar_values = Dict{String, Any}(
        "schema_version" => CONTRACT_SCHEMA,
        "classification" => EXPECTED_STATUS,
        "artifact_role" => EXPECTED_ARTIFACT_ROLE,
        "promotion_status" => EXPECTED_PROMOTION_STATUS,
        "source_year" => 2024,
        "source_frequency" => "annual",
        "unit" => "millions USD",
        "price_basis" => "producers prices",
        "source_industry_count" => 71,
        "source_ordinary_commodity_count" => 71,
        "model_industry_count" => 68,
        "model_commodity_count" => 68,
        "final_use_count" => 20,
        "same_table_market_share_definition" =>
            "D68=(A*Vcore*A')*diag(A*qcore)^-1",
        "final_use_policy" => "ALL_20_SIGNED_COLUMNS",
        "aggregation_order" => "AGGREGATE_LEVELS_BEFORE_RATIOS_AND_W",
        "source_first_comparison_policy" =>
            "Q_COMPOSITION_WEIGHTED_COEFFICIENTS_PLUS_FLOW_LEVEL_NONCOMMUTATION",
        "coefficient_comparator_scope" =>
            "CURRENT_TABLE_NUMERICAL_WITNESS_NOT_A_GENERAL_AGGREGATION_IDENTITY",
        "other_term_role" => "ARITHMETIC_OMISSION_WITNESS_ONLY",
        "used_make_component_policy" =>
            "H_IS_THE_MAKE_SIDE_SCRAP_COMPONENT_OF_COMPOSITE_USED_NOT_THE_USED_USE_OR_FINAL_ASSET_TRANSFER_ROWS",
        "other_make_component_policy" =>
            "O_AND_T_OTHER_ARE_MAKE_SIDE_ARITHMETIC_CLOSURE_WITNESSES_NOT_ALLOCATIONS_OF_OTHER_USE_OR_FINAL_ROWS",
        "special_use_exclusion_policy" =>
            "USED_AND_OTHER_USE_AND_FINAL_ROWS_EXCLUDED_FROM_U68_AND_E68_AND_RETAINED_IN_THE_CLOSURE_BOUNDARY_SIDECAR",
        "explicit_mask_policy" =>
            "PRESERVE_SOURCE_MASKS_DERIVED_VALUES_HAVE_FALSE_MASK",
        "negative_cell_policy" => "PRESERVE_AND_LEDGER",
        "rounding_policy" =>
            "PRESERVE_PUBLISHED_CURRENT_DOLLAR_RESIDUALS_AND_SEPARATE_FORMULA_FLOATING_POINT",
        "same_table_source_policy" =>
            "ONLY_PINNED_AFTER_REDEFINITIONS_V_U_F_Q_G",
        "official_cross_archive_d_policy" =>
            "FORBIDDEN_NOT_LOADED_NOT_ACCEPTED",
        "raw_unweighted_w_shortcut_policy" => "EXPLICITLY_REJECTED",
        "accounting_gate_effect" => "NONE",
        "promotion_ready" => false,
    )
    for (key, expected) in scalar_values
        require_contract_value(contract, key, expected)
    end
    String.(contract["closure_codes"]) == EXPECTED_CLOSURE_CODES ||
        throw(ArgumentError("closure-code contract changed"))
    Int.(contract["methodology_pdf_pages"]) ==
        EXPECTED_METHODOLOGY_PAGES ||
        throw(ArgumentError("methodology-page contract changed"))
    Int.(contract["diagnostic_additional_methodology_pdf_pages"]) ==
        EXPECTED_ADDITIONAL_METHODOLOGY_PAGES ||
        throw(ArgumentError("additional methodology-page contract changed"))
    String.(contract["promotion_blockers"]) ==
        EXPECTED_PROMOTION_BLOCKERS ||
        throw(ArgumentError("promotion blockers changed"))
    String.(contract["forbidden_runtime_keys"]) ==
        EXPECTED_FORBIDDEN_RUNTIME_KEYS ||
        throw(ArgumentError("forbidden runtime keys changed"))
    isempty(contract["emitted_runtime_keys"]) ||
        throw(ArgumentError("diagnostic cannot emit runtime keys"))
    for (key, expected) in expected_flags()
        require_contract_value(contract, String(key), expected)
    end

    byte_pins = Dict(
        String(key) => String(value)
            for (key, value) in contract["byte_pins"]
    )
    byte_pins == EXPECTED_BYTE_PINS ||
        throw(ArgumentError("aggregate-first byte pins changed"))
    pinned_files = Dict(
        "after_redefinitions_fixture_sha256" =>
            joinpath(after_directory, "cells.csv"),
        "after_redefinitions_manifest_sha256" =>
            joinpath(after_directory, "manifest.toml"),
        "model_mapping_sha256" => model_mapping_path,
        "sector_mapping_sha256" => sector_mapping_path,
        "closure_boundary_contract_sha256" =>
            closure_boundary_contract_path,
        "methodology_pdf_sha256" => methodology_pdf_path,
        "methodology_receipt_sha256" => methodology_receipt_path,
    )
    for (pin, path) in pinned_files
        require_hash(path, EXPECTED_BYTE_PINS[pin], pin)
    end

    after_manifest = TOML.parsefile(joinpath(after_directory, "manifest.toml"))
    manifest_pins = Dict(
        "source_zip_sha256" =>
            "after_redefinitions_source_zip_sha256",
        "source_metadata_sha256" =>
            "after_redefinitions_source_metadata_sha256",
        "producer_use_workbook_sha256" =>
            "after_redefinitions_producer_use_workbook_sha256",
        "producer_make_workbook_sha256" =>
            "after_redefinitions_producer_make_workbook_sha256",
    )
    for (manifest_key, pin) in manifest_pins
        lowercase(String(after_manifest[manifest_key])) ==
            EXPECTED_BYTE_PINS[pin] ||
            throw(ArgumentError("$pin changed in after-redefinitions manifest"))
    end
    get(after_manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("after-redefinitions status changed"))

    model_mapping = TOML.parsefile(model_mapping_path)
    get(model_mapping, "common_basis_fixture_sha256", "") ==
        EXPECTED_BYTE_PINS["after_redefinitions_fixture_sha256"] ||
        throw(ArgumentError("model mapping fixture identity changed"))
    get(model_mapping, "sector_mapping_sha256", "") ==
        EXPECTED_BYTE_PINS["sector_mapping_sha256"] ||
        throw(ArgumentError("model mapping sector identity changed"))
    get(model_mapping, "closure_account_codes", String[]) ==
        EXPECTED_CLOSURE_CODES ||
        throw(ArgumentError("model mapping closure codes changed"))

    closure_contract = TOML.parsefile(closure_boundary_contract_path)
    get(closure_contract, "schema_version", "") ==
        "beforeit-us-after-redefinitions-closure-boundary-candidate.v1" ||
        throw(ArgumentError("closure-boundary schema changed"))
    get(closure_contract, "classification", "") == EXPECTED_STATUS ||
        throw(ArgumentError("closure-boundary status changed"))
    closure_pins = Dict(
        String(key) => String(value)
            for (key, value) in closure_contract["byte_pins"]
    )
    for pin in (
            "after_redefinitions_fixture_sha256",
            "after_redefinitions_manifest_sha256",
            "after_redefinitions_source_zip_sha256",
            "after_redefinitions_source_metadata_sha256",
            "after_redefinitions_producer_use_workbook_sha256",
            "after_redefinitions_producer_make_workbook_sha256",
            "model_mapping_sha256",
            "sector_mapping_sha256",
            "methodology_pdf_sha256",
            "methodology_receipt_sha256",
        )
        closure_pins[pin] == EXPECTED_BYTE_PINS[pin] ||
            throw(ArgumentError("closure-boundary pin $pin changed"))
    end

    methodology = TOML.parsefile(methodology_receipt_path)
    get(methodology, "status", "") ==
        "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA" ||
        throw(ArgumentError("methodology status changed"))
    lowercase(String(get(methodology, "source_sha256", ""))) ==
        EXPECTED_BYTE_PINS["methodology_pdf_sha256"] ||
        throw(ArgumentError("methodology receipt/PDF identity changed"))
    Int.(get(methodology, "relevant_pdf_pages", Int[])) ==
        EXPECTED_METHODOLOGY_PAGES ||
        throw(ArgumentError("methodology relevant pages changed"))
    get(methodology, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("methodology cannot admit a forecast origin"))
    get(methodology, "model_state_write", true) === false ||
        throw(ArgumentError("methodology cannot write model state"))

    return (
        contract_sha256 = contract_sha256,
        contract = contract,
        byte_pins = byte_pins,
        after_manifest = after_manifest,
        methodology = methodology,
        model_mapping = model_mapping,
    )
end

function aggregation_contract(source_codes, model_mapping, sector_mapping_path)
    model_codes = String.(model_mapping["model_codes"])
    sector_mapping = TOML.parsefile(sector_mapping_path)
    model_codes == String.(sector_mapping["model"]["codes"]) ||
        throw(ArgumentError("model and sector mapping axes differ"))
    length(model_codes) == 68 && length(unique(model_codes)) == 68 ||
        throw(ArgumentError("model axis changed"))
    retail_codes = Set(String.(model_mapping["retail_source_codes"]))
    retail_codes == RETAIL_SOURCE_CODES ||
        throw(ArgumentError("retail aggregation source codes changed"))
    model_index =
        Dict(code => position for (position, code) in pairs(model_codes))
    mapping = Dict{String, String}()
    aggregation_values = zeros(length(model_codes), length(source_codes))
    for (source_position, source_code) in pairs(source_codes)
        target = source_code in retail_codes ? "4A0" : source_code
        haskey(model_index, target) ||
            throw(ArgumentError("unmapped source code $source_code"))
        mapping[source_code] = target
        aggregation_values[model_index[target], source_position] = 1.0
    end
    all(vec(sum(aggregation_values; dims = 1)) .== 1.0) ||
        throw(ArgumentError("aggregation must map every source code once"))
    Set(values(mapping)) == Set(model_codes) ||
        throw(ArgumentError("aggregation misses a model code"))
    return (
        model_codes,
        mapping,
        derived_matrix(
            IndustryBasis,
            IndustryBasis,
            model_codes,
            source_codes,
            aggregation_values,
        ),
        derived_matrix(
            CommodityBasis,
            CommodityBasis,
            model_codes,
            source_codes,
            aggregation_values,
        ),
    )
end

function source_vector_explicit(fixture, matrix_id, positions)
    mask = fixture.source_explicit[matrix_id]
    return BitVector(mask[positions, 1])
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

function build_sign_ledgers(report)
    return Dict(
        :source_intermediate_use =>
            sign_ledger(report.source_intermediate_use),
        :source_final_use => sign_ledger(report.source_final_use),
        :source_make => sign_ledger(report.source_make),
        :aggregate_intermediate_use =>
            sign_ledger(report.aggregate_intermediate_use),
        :aggregate_final_use => sign_ledger(report.aggregate_final_use),
        :aggregate_make => sign_ledger(report.aggregate_make),
        :commodity_output => sign_ledger(report.aggregate_commodity_output),
        :industry_output => sign_ledger(report.aggregate_industry_output),
        :scrap_output => sign_ledger(report.aggregate_scrap_output),
        :other_output => sign_ledger(report.aggregate_other_output),
        :input_coefficients => sign_ledger(report.input_coefficients),
        :market_shares => sign_ledger(report.market_shares),
        :scrap_shares => sign_ledger(report.scrap_shares),
        :nonscrap_transform => sign_ledger(report.nonscrap_transform),
        :requirements => sign_ledger(report.requirements),
        :final_demand => sign_ledger(report.final_demand),
        :leontief_inverse => sign_ledger(report.leontief_inverse),
        :other_output_term =>
            sign_ledger(report.other.arithmetic_output_term),
    )
end

function build_residuals(report)
    residuals = ControlResidual[]
    for (code, lhs, rhs) in (
            ("U68_TOTAL", sum(report.aggregate_intermediate_use.values), 21_165_843.0),
            ("F68_TOTAL", sum(report.aggregate_final_use.values), 29_550_990.0),
            ("V68_TOTAL", sum(report.aggregate_make.values), 50_716_812.0),
            ("Q68_TOTAL", sum(report.aggregate_commodity_output.values), 50_716_816.0),
            ("G68_TOTAL", sum(report.aggregate_industry_output.values), 50_736_554.0),
            ("H68_SCRAP_TOTAL", sum(report.aggregate_scrap_output.values), 13_553.0),
            ("O68_OTHER_TOTAL", sum(report.aggregate_other_output.values), 6_187.0),
        )
        add_residual!(
            residuals,
            :aggregate_level,
            code,
            "same-table source levels aggregate before ratios",
            lhs,
            rhs,
            0.0,
        )
    end

    identities = report.identities
    for (code, summary, rhs, tolerance) in (
            ("MAKE_SIGNED", identities.make_source_summary, -2.0, 1.0e-8),
            ("MAKE_ABSOLUTE", identities.make_source_summary, 30.0, 1.0e-8),
            (
                "D_SIGNED",
                identities.market_share_formula_summary,
                -2.000000000167347,
                1.0e-7,
            ),
            (
                "D_ABSOLUTE",
                identities.market_share_formula_summary,
                30.00000000048749,
                1.0e-7,
            ),
            (
                "W_SIGNED",
                identities.nonscrap_formula_summary,
                1.9730748415822745,
                1.0e-7,
            ),
            (
                "W_ABSOLUTE",
                identities.nonscrap_formula_summary,
                30.04198597046343,
                1.0e-7,
            ),
            ("USE_SIGNED", identities.use_source_summary, -17.0, 1.0e-8),
            ("USE_ABSOLUTE", identities.use_source_summary, 121.0, 1.0e-8),
        )
        value = endswith(code, "SIGNED") ?
            summary.signed_total : summary.absolute_total
        add_residual!(
            residuals,
            :published_identity_residual,
            code,
            "published current-dollar residual retained",
            value,
            rhs,
            tolerance,
        )
    end
    for (code, lhs, tolerance) in (
            (
                "D_MINUS_MAKE_FP",
                identities.market_share_minus_make_fp_summary.absolute_total,
                1.0e-8,
            ),
            (
                "W_MINUS_PROPAGATED_MAKE_FP",
                identities.nonscrap_minus_make_propagation_fp_summary.absolute_total,
                1.0e-8,
            ),
            (
                "B_MINUS_USE_FP",
                identities.input_coefficient_minus_use_fp_summary.absolute_total,
                1.0e-8,
            ),
        )
        add_residual!(
            residuals,
            :formula_floating_point,
            code,
            "formula-only floating-point difference separated from source residual",
            lhs,
            0.0,
            tolerance,
        )
    end

    coefficients = report.coefficients
    for (code, ledger, tolerance) in (
            (
                "W_Q_WEIGHTED",
                coefficients.conditional_current_table_w_ledger,
                1.0e-12,
            ),
            (
                "H_Q_WEIGHTED",
                coefficients.conditional_current_table_h_ledger,
                1.0e-12,
            ),
        )
        add_residual!(
            residuals,
            :conditional_current_table_coefficient_comparator,
            code,
            "pinned-table coefficient equality under asserted merged-retail preconditions",
            ledger.maximum_absolute_difference,
            0.0,
            tolerance,
        )
    end
    add_residual!(
        residuals,
        :rejected_shortcut_witness,
        "RAW_AWA_L1",
        "raw A*W71*A' is not a valid coefficient aggregation",
        coefficients.raw_unweighted_w_ledger.absolute_total,
        2.99999974604394,
        1.0e-10,
    )

    flows = report.flows
    for (code, ledger, rhs, tolerance) in (
            (
                "Z_L1",
                flows.intermediate_difference_ledger,
                1_151.302692026168,
                1.0e-6,
            ),
            (
                "Y_L1",
                flows.final_use_difference_ledger,
                2_562.397923892939,
                1.0e-6,
            ),
        )
        add_residual!(
            residuals,
            :flow_noncommutation,
            code,
            "aggregate-first and source-first transformed flows differ",
            ledger.absolute_total,
            rhs,
            tolerance,
        )
    end
    add_residual!(
        residuals,
        :flow_noncommutation,
        "COMBINED_ROW_L1",
        "intermediate and final noncommutation nearly cancel only in row totals",
        flows.combined_row_difference_summary.absolute_total,
        0.05688487550054,
        1.0e-8,
    )

    other = report.other
    for (code, summary, rhs, tolerance) in (
            (
                "OMISSION_SIGNED",
                other.omission_summary,
                1_895.838353566262,
                1.0e-7,
            ),
            (
                "OMISSION_ABSOLUTE",
                other.omission_summary,
                1_927.472872337382,
                1.0e-7,
            ),
            (
                "ADJUSTED_SIGNED",
                other.adjusted_equation_summary,
                -14.606366737874,
                1.0e-7,
            ),
            (
                "ADJUSTED_ABSOLUTE",
                other.adjusted_equation_summary,
                120.329989078666,
                1.0e-7,
            ),
            (
                "NO_OTHER_SOLUTION_SIGNED",
                other.no_other_solution_summary,
                3_264.838451893080,
                1.0e-6,
            ),
            (
                "WITH_OTHER_SOLUTION_SIGNED",
                other.arithmetic_other_solution_summary,
                -33.16731505423,
                1.0e-6,
            ),
        )
        value = endswith(code, "ABSOLUTE") ?
            summary.absolute_total : summary.signed_total
        add_residual!(
            residuals,
            :other_output_witness,
            code,
            "Other term is arithmetic evidence without a selected boundary",
            value,
            rhs,
            tolerance,
        )
    end
    add_residual!(
        residuals,
        :other_output_witness,
        "TERM_TOTAL",
        "B*(I-P)^-1*o arithmetic term retained",
        other.arithmetic_output_term_signs.total,
        1_910.444720304135,
        1.0e-7,
    )

    for (code, lhs, rhs, tolerance) in (
            (
                "RHO_H",
                report.stability.spectral_radius_requirements,
                0.46609378423653025,
                1.0e-12,
            ),
            (
                "COND_I_MINUS_P",
                report.stability.nonscrap_operator_condition,
                1.008243308519139,
                1.0e-12,
            ),
            (
                "COND_I_MINUS_H",
                report.stability.leontief_operator_condition,
                2.913215049708531,
                1.0e-11,
            ),
        )
        add_residual!(
            residuals,
            :stability,
            code,
            "diagnostic linear-system stability witness",
            lhs,
            rhs,
            tolerance,
        )
    end

    for (code, lhs, rhs, tolerance) in (
            ("D_SUM", sum(report.market_shares.values), 67.99993136621207, 1.0e-10),
            ("W_SUM", sum(report.nonscrap_transform.values), 68.02964492856546, 1.0e-10),
            ("B_SUM", sum(report.input_coefficients.values), 30.95969934849524, 1.0e-10),
            ("H_SUM", sum(report.requirements.values), 31.15992380781542, 1.0e-10),
            (
                "D_COLUMN_RESIDUAL",
                maximum(
                    abs.(
                        vec(sum(report.market_shares.values; dims = 1)) .-
                            1.0
                    ),
                ),
                4.046944556856946e-5,
                1.0e-12,
            ),
        )
        add_residual!(
            residuals,
            :coefficient_witness,
            code,
            "same-table aggregate-first coefficient golden",
            lhs,
            rhs,
            tolerance,
        )
    end
    return residuals
end

function build_coefficient_witness(
        source_codes,
        model_codes,
        A,
        U71,
        V71,
        q71,
        g71,
        h71,
        o71,
        B68,
        W68,
        H68,
    )
    source_B_values = U71.values * Diagonal(1.0 ./ g71.values)
    source_D_values = V71.values * Diagonal(1.0 ./ q71.values)
    source_p_values = h71.values ./ g71.values
    source_nonscrap_operator =
        Matrix{Float64}(I, length(source_codes), length(source_codes)) -
        Diagonal(source_p_values)
    source_W_values = source_nonscrap_operator \ source_D_values
    source_H_values = source_B_values * source_W_values
    q68_values = A * q71.values
    Cq_values =
        Diagonal(q71.values) * transpose(A) * Diagonal(1.0 ./ q68_values)
    valid_W_values = A * source_W_values * Cq_values
    valid_H_values = A * source_H_values * Cq_values
    raw_W_values = A * source_W_values * transpose(A)
    valid_W_difference_values = W68.values - valid_W_values
    valid_H_difference_values = H68.values - valid_H_values
    raw_W_difference_values = W68.values - raw_W_values
    retail_positions = [V71.row_index[code] for code in RETAIL_SOURCE_CODE_ORDER]
    merged_zero_scrap_output = all(iszero, h71.values[retail_positions])
    merged_zero_other_output = all(iszero, o71.values[retail_positions])
    merged_own_commodity_make_only = all(RETAIL_SOURCE_CODE_ORDER) do code
        row_position = V71.row_index[code]
        column_position = V71.column_index[code]
        all(
            position == column_position || iszero(value)
                for (position, value) in enumerate(V71.values[row_position, :])
        )
    end
    merged_own_make_equals_industry_output =
        all(RETAIL_SOURCE_CODE_ORDER) do code
        V71.values[V71.row_index[code], V71.column_index[code]] ==
            g71.values[g71.index[code]]
    end

    source_B = derived_matrix(
        CommodityBasis,
        IndustryBasis,
        source_codes,
        source_codes,
        source_B_values,
    )
    source_D = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        source_codes,
        source_codes,
        source_D_values,
    )
    source_W = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        source_codes,
        source_codes,
        source_W_values,
    )
    source_H = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        source_codes,
        source_codes,
        source_H_values,
    )
    Cq = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        source_codes,
        model_codes,
        Cq_values,
    )
    valid_W = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        valid_W_values,
    )
    valid_W_difference = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        valid_W_difference_values,
    )
    valid_H = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        valid_H_values,
    )
    valid_H_difference = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        valid_H_difference_values,
    )
    raw_W = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        raw_W_values,
    )
    raw_W_difference = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        raw_W_difference_values,
    )
    return CoefficientAggregationWitness(
        :current_table_conditional_not_general_identity,
        copy(RETAIL_SOURCE_CODE_ORDER),
        merged_zero_scrap_output,
        merged_zero_other_output,
        merged_own_commodity_make_only,
        merged_own_make_equals_industry_output,
        source_B,
        source_D,
        LabeledVector{IndustryBasis}(source_codes, source_p_values),
        source_W,
        source_H,
        Cq,
        valid_W,
        valid_W_difference,
        difference_ledger(
            valid_W_difference;
            denominator = sum(abs, W68.values),
        ),
        valid_H,
        valid_H_difference,
        difference_ledger(
            valid_H_difference;
            denominator = sum(abs, H68.values),
        ),
        raw_W,
        raw_W_difference,
        difference_ledger(
            raw_W_difference;
            denominator = sum(abs, W68.values),
        ),
        false,
    )
end

function build_flow_witness(
        source_codes,
        model_codes,
        final_use_codes,
        A,
        U71,
        F71,
        W68,
        U68,
        F68,
        coefficients,
    )
    aggregate_first_Z_values = W68.values * U68.values
    source_first_Z_values =
        A * coefficients.source_nonscrap_transform.values *
        U71.values *
        transpose(A)
    aggregate_first_Y_values = W68.values * F68.values
    source_first_Y_values =
        A * coefficients.source_nonscrap_transform.values * F71.values
    Z_difference_values =
        aggregate_first_Z_values - source_first_Z_values
    Y_difference_values =
        aggregate_first_Y_values - source_first_Y_values
    combined_row_values =
        vec(sum(Z_difference_values; dims = 2)) +
        vec(sum(Y_difference_values; dims = 2))

    aggregate_first_Z = derived_matrix(
        IndustryBasis,
        IndustryBasis,
        model_codes,
        model_codes,
        aggregate_first_Z_values,
    )
    source_first_Z = derived_matrix(
        IndustryBasis,
        IndustryBasis,
        model_codes,
        model_codes,
        source_first_Z_values,
    )
    Z_difference = derived_matrix(
        IndustryBasis,
        IndustryBasis,
        model_codes,
        model_codes,
        Z_difference_values,
    )
    aggregate_first_Y = derived_matrix(
        IndustryBasis,
        FinalUseBasis,
        model_codes,
        final_use_codes,
        aggregate_first_Y_values,
    )
    source_first_Y = derived_matrix(
        IndustryBasis,
        FinalUseBasis,
        model_codes,
        final_use_codes,
        source_first_Y_values,
    )
    Y_difference = derived_matrix(
        IndustryBasis,
        FinalUseBasis,
        model_codes,
        final_use_codes,
        Y_difference_values,
    )
    combined_row =
        LabeledVector{IndustryBasis}(model_codes, combined_row_values)
    return TransformedFlowWitness(
        aggregate_first_Z,
        source_first_Z,
        Z_difference,
        difference_ledger(
            Z_difference;
            denominator = sum(abs, source_first_Z_values),
        ),
        aggregate_first_Y,
        source_first_Y,
        Y_difference,
        difference_ledger(
            Y_difference;
            denominator = sum(abs, source_first_Y_values),
        ),
        combined_row,
        residual_summary(combined_row),
        sign_ledger(aggregate_first_Z),
        sign_ledger(source_first_Z),
        sign_ledger(aggregate_first_Y),
        sign_ledger(source_first_Y),
    )
end

function build_identity_witness(
        model_codes,
        U,
        V,
        q,
        g,
        h,
        o,
        B,
        D,
        p,
        W,
        e,
    )
    n = length(model_codes)
    nonscrap_operator =
        Matrix{Float64}(I, n, n) - Diagonal(p.values)
    make_values =
        vec(sum(V.values; dims = 2)) + h.values + o.values - g.values
    d_values =
        D.values * q.values -
        (nonscrap_operator * g.values - o.values)
    d_minus_make_values = d_values - make_values
    w_values =
        g.values - W.values * q.values -
        (nonscrap_operator \ o.values)
    w_from_make_values = -(nonscrap_operator \ make_values)
    w_fp_values = w_values - w_from_make_values
    use_values =
        q.values - vec(sum(U.values; dims = 2)) - e.values
    b_values = q.values - B.values * g.values - e.values
    b_minus_use_values = b_values - use_values

    make = LabeledVector{IndustryBasis}(model_codes, make_values)
    d_residual = LabeledVector{IndustryBasis}(model_codes, d_values)
    d_fp =
        LabeledVector{IndustryBasis}(model_codes, d_minus_make_values)
    w_residual = LabeledVector{IndustryBasis}(model_codes, w_values)
    w_from_make =
        LabeledVector{IndustryBasis}(model_codes, w_from_make_values)
    w_fp = LabeledVector{IndustryBasis}(model_codes, w_fp_values)
    use_residual = LabeledVector{CommodityBasis}(model_codes, use_values)
    b_residual = LabeledVector{CommodityBasis}(model_codes, b_values)
    b_fp = LabeledVector{CommodityBasis}(model_codes, b_minus_use_values)
    return AccountingIdentityWitness(
        make,
        residual_summary(make),
        d_residual,
        residual_summary(d_residual),
        d_fp,
        residual_summary(d_fp),
        w_residual,
        residual_summary(w_residual),
        w_from_make,
        w_fp,
        residual_summary(w_fp),
        use_residual,
        residual_summary(use_residual),
        b_residual,
        residual_summary(b_residual),
        b_fp,
        residual_summary(b_fp),
    )
end

function build_other_witness(model_codes, q, o, B, p, H, e)
    n = length(model_codes)
    nonscrap_operator =
        Matrix{Float64}(I, n, n) - Diagonal(p.values)
    leontief_operator = Matrix{Float64}(I, n, n) - H.values
    omission_values = q.values - H.values * q.values - e.values
    term_values = B.values * (nonscrap_operator \ o.values)
    adjusted_values = omission_values - term_values
    no_other_solution_values = leontief_operator \ e.values
    no_other_residual_values = q.values - no_other_solution_values
    arithmetic_other_solution_values =
        leontief_operator \ (e.values + term_values)
    arithmetic_other_residual_values =
        q.values - arithmetic_other_solution_values
    omission =
        LabeledVector{CommodityBasis}(model_codes, omission_values)
    term = LabeledVector{CommodityBasis}(model_codes, term_values)
    adjusted =
        LabeledVector{CommodityBasis}(model_codes, adjusted_values)
    no_other_solution = LabeledVector{CommodityBasis}(
        model_codes,
        no_other_solution_values,
    )
    no_other_residual = LabeledVector{CommodityBasis}(
        model_codes,
        no_other_residual_values,
    )
    arithmetic_other_solution = LabeledVector{CommodityBasis}(
        model_codes,
        arithmetic_other_solution_values,
    )
    arithmetic_other_residual = LabeledVector{CommodityBasis}(
        model_codes,
        arithmetic_other_residual_values,
    )
    return OtherOutputWitness(
        omission,
        residual_summary(omission),
        term,
        sign_ledger(term),
        adjusted,
        residual_summary(adjusted),
        no_other_solution,
        no_other_residual,
        residual_summary(no_other_residual),
        arithmetic_other_solution,
        arithmetic_other_residual,
        residual_summary(arithmetic_other_residual),
        :arithmetic_omission_witness_only,
        false,
    )
end

function _build_aggregate_first_scrap_adjusted_diagnostic(
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        closure_boundary_contract_path =
            DEFAULT_CLOSURE_BOUNDARY_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    validated = validate_contract(
        contract_path,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        closure_boundary_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    fixture = load_after_redefinitions_fixture(after_directory)
    source_codes = copy(fixture.producer_make.row_codes)
    length(source_codes) == 71 ||
        throw(ArgumentError("source industry axis changed"))
    ordinary_codes = filter(
        code -> !(code in EXPECTED_CLOSURE_CODES),
        fixture.producer_make.column_codes,
    )
    ordinary_codes == source_codes ||
        throw(ArgumentError("ordinary commodity and industry axes differ"))
    (
        model_codes,
        source_mapping,
        industry_aggregation,
        commodity_aggregation,
    ) = aggregation_contract(
        source_codes,
        validated.model_mapping,
        sector_mapping_path,
    )
    A = industry_aggregation.values
    ordinary_positions = [
        fixture.producer_make.column_index[code] for code in ordinary_codes
    ]
    source_U = LabeledMatrix{CommodityBasis, IndustryBasis}(
        source_codes,
        source_codes,
        fixture.producer_intermediate_use.values[ordinary_positions, :],
        fixture.producer_intermediate_use.explicit[ordinary_positions, :],
    )
    source_F = LabeledMatrix{CommodityBasis, FinalUseBasis}(
        source_codes,
        fixture.producer_final_use.column_codes,
        fixture.producer_final_use.values[ordinary_positions, :],
        fixture.producer_final_use.explicit[ordinary_positions, :],
    )
    source_V = LabeledMatrix{IndustryBasis, CommodityBasis}(
        source_codes,
        source_codes,
        fixture.producer_make.values[:, ordinary_positions],
        fixture.producer_make.explicit[:, ordinary_positions],
    )
    source_q = LabeledVector{CommodityBasis}(
        source_codes,
        fixture.producer_commodity_output_make.values[ordinary_positions],
    )
    source_g = fixture.producer_industry_output_make
    used_position = fixture.producer_make.column_index["Used"]
    other_position = fixture.producer_make.column_index["Other"]
    source_h = LabeledVector{IndustryBasis}(
        source_codes,
        fixture.producer_make.values[:, used_position],
    )
    source_o = LabeledVector{IndustryBasis}(
        source_codes,
        fixture.producer_make.values[:, other_position],
    )
    source_explicit = Dict(
        :commodity_output => source_vector_explicit(
            fixture,
            "producer_make_commodity_output_2024",
            ordinary_positions,
        ),
        :industry_output => source_vector_explicit(
            fixture,
            "producer_make_industry_output_2024",
            collect(1:length(source_codes)),
        ),
        :scrap_output =>
            BitVector(fixture.producer_make.explicit[:, used_position]),
        :other_output =>
            BitVector(fixture.producer_make.explicit[:, other_position]),
    )

    U_values = A * source_U.values * transpose(A)
    F_values = A * source_F.values
    V_values = A * source_V.values * transpose(A)
    q_values = A * source_q.values
    g_values = A * source_g.values
    h_values = A * source_h.values
    o_values = A * source_o.values
    all(>(0.0), q_values) ||
        throw(ArgumentError("aggregate commodity output must be positive"))
    all(>(0.0), g_values) ||
        throw(ArgumentError("aggregate industry output must be positive"))
    all(value -> 0.0 <= value < 1.0, h_values ./ g_values) ||
        throw(ArgumentError("aggregate scrap shares must be in [0,1)"))

    U = derived_matrix(
        CommodityBasis,
        IndustryBasis,
        model_codes,
        model_codes,
        U_values,
    )
    F = derived_matrix(
        CommodityBasis,
        FinalUseBasis,
        model_codes,
        source_F.column_codes,
        F_values,
    )
    V = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        V_values,
    )
    q = LabeledVector{CommodityBasis}(model_codes, q_values)
    g = LabeledVector{IndustryBasis}(model_codes, g_values)
    h = LabeledVector{IndustryBasis}(model_codes, h_values)
    o = LabeledVector{IndustryBasis}(model_codes, o_values)
    B_values = U_values * Diagonal(1.0 ./ g_values)
    D_values = V_values * Diagonal(1.0 ./ q_values)
    p_values = h_values ./ g_values
    nonscrap_ratio_values = 1.0 .- p_values
    nonscrap_operator =
        Matrix{Float64}(I, length(model_codes), length(model_codes)) -
        Diagonal(p_values)
    W_values = nonscrap_operator \ D_values
    H_values = B_values * W_values
    e_values = vec(sum(F_values; dims = 2))
    leontief_operator =
        Matrix{Float64}(I, length(model_codes), length(model_codes)) -
        H_values
    inverse_values =
        leontief_operator \ Matrix{Float64}(I, length(model_codes), length(model_codes))
    B = derived_matrix(
        CommodityBasis,
        IndustryBasis,
        model_codes,
        model_codes,
        B_values,
    )
    D = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        D_values,
    )
    p = LabeledVector{IndustryBasis}(model_codes, p_values)
    nonscrap_ratios =
        LabeledVector{IndustryBasis}(model_codes, nonscrap_ratio_values)
    W = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        W_values,
    )
    H = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        H_values,
    )
    e = LabeledVector{CommodityBasis}(model_codes, e_values)
    leontief_inverse = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        model_codes,
        model_codes,
        inverse_values,
    )
    derived_explicit = Dict(
        :commodity_output => falses(length(model_codes)),
        :industry_output => falses(length(model_codes)),
        :scrap_output => falses(length(model_codes)),
        :other_output => falses(length(model_codes)),
        :scrap_shares => falses(length(model_codes)),
        :nonscrap_ratios => falses(length(model_codes)),
        :final_demand => falses(length(model_codes)),
    )

    coefficients = build_coefficient_witness(
        source_codes,
        model_codes,
        A,
        source_U,
        source_V,
        source_q,
        source_g,
        source_h,
        source_o,
        B,
        W,
        H,
    )
    flows = build_flow_witness(
        source_codes,
        model_codes,
        source_F.column_codes,
        A,
        source_U,
        source_F,
        W,
        U,
        F,
        coefficients,
    )
    identities = build_identity_witness(
        model_codes,
        U,
        V,
        q,
        g,
        h,
        o,
        B,
        D,
        p,
        W,
        e,
    )
    other = build_other_witness(model_codes, q, o, B, p, H, e)
    stability = StabilityWitness(
        maximum(abs, eigvals(H_values)),
        cond(nonscrap_operator),
        cond(leontief_operator),
    )
    report_stub = (
        source_intermediate_use = source_U,
        source_final_use = source_F,
        source_make = source_V,
        aggregate_intermediate_use = U,
        aggregate_final_use = F,
        aggregate_make = V,
        aggregate_commodity_output = q,
        aggregate_industry_output = g,
        aggregate_scrap_output = h,
        aggregate_other_output = o,
        input_coefficients = B,
        market_shares = D,
        scrap_shares = p,
        nonscrap_transform = W,
        requirements = H,
        final_demand = e,
        leontief_inverse = leontief_inverse,
        other = other,
    )
    sign_ledgers = build_sign_ledgers(report_stub)
    report_without_residuals = (
        aggregate_intermediate_use = U,
        aggregate_final_use = F,
        aggregate_make = V,
        aggregate_commodity_output = q,
        aggregate_industry_output = g,
        aggregate_scrap_output = h,
        aggregate_other_output = o,
        input_coefficients = B,
        market_shares = D,
        nonscrap_transform = W,
        requirements = H,
        coefficients = coefficients,
        flows = flows,
        identities = identities,
        other = other,
        stability = stability,
    )
    residuals = build_residuals(report_without_residuals)
    report = AggregateFirstScrapAdjustedDiagnosticReport(
        fixture.year,
        source_codes,
        model_codes,
        copy(source_F.column_codes),
        source_mapping,
        industry_aggregation,
        commodity_aggregation,
        source_U,
        source_F,
        source_V,
        source_q,
        source_g,
        source_h,
        source_o,
        source_explicit,
        U,
        F,
        V,
        q,
        g,
        h,
        o,
        B,
        D,
        p,
        nonscrap_ratios,
        W,
        H,
        e,
        leontief_inverse,
        derived_explicit,
        coefficients,
        flows,
        identities,
        other,
        stability,
        sign_ledgers,
        negative_cells(V),
        negative_cells(D),
        negative_cells(W),
        residuals,
        validated.contract_sha256,
        validated.byte_pins,
        String(validated.after_manifest["status"]),
        String(validated.methodology["status"]),
        :aggregate_first_68_scrap_adjusted_diagnostic_only,
        :research_only_not_promoted,
        :annual,
        :millions_usd,
        :producers_prices,
        expected_policies(),
        expected_flags(),
        String[],
        copy(EXPECTED_FORBIDDEN_RUNTIME_KEYS),
        copy(EXPECTED_PROMOTION_BLOCKERS),
        :none,
        false,
    )
    aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
        report,
    ) || throw(ArgumentError("aggregate-first internal controls do not pass"))
    return report
end

function aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
        report::AggregateFirstScrapAdjustedDiagnosticReport,
    )
    try
        report.year == 2024 || return false
        length(report.source_codes) == 71 || return false
        length(report.model_codes) == 68 || return false
        length(report.final_use_codes) == 20 || return false
        length(unique(report.source_codes)) == 71 || return false
        length(unique(report.model_codes)) == 68 || return false
        isempty(
            intersect(Set(report.model_codes), Set(EXPECTED_CLOSURE_CODES)),
        ) || return false

        A = report.industry_aggregation.values
        matrix_axes_match(
            report.industry_aggregation,
            report.model_codes,
            report.source_codes,
        ) || return false
        matrix_axes_match(
            report.commodity_aggregation,
            report.model_codes,
            report.source_codes,
        ) || return false
        A == report.commodity_aggregation.values || return false
        any(report.industry_aggregation.explicit) && return false
        any(report.commodity_aggregation.explicit) && return false
        all(value -> value == 0.0 || value == 1.0, A) || return false
        all(vec(sum(A; dims = 1)) .== 1.0) || return false
        count(==(1.0), A) == 71 || return false
        sum(A[report.industry_aggregation.row_index["4A0"], :]) == 4.0 ||
            return false
        for source_code in report.source_codes
            target =
                source_code in RETAIL_SOURCE_CODES ? "4A0" : source_code
            report.source_industry_mapping[source_code] == target ||
                return false
            A[
                report.industry_aggregation.row_index[target],
                report.industry_aggregation.column_index[source_code],
            ] == 1.0 || return false
        end

        matrix_axes_match(
            report.source_intermediate_use,
            report.source_codes,
            report.source_codes,
        ) || return false
        matrix_axes_match(
            report.source_final_use,
            report.source_codes,
            report.final_use_codes,
        ) || return false
        matrix_axes_match(
            report.source_make,
            report.source_codes,
            report.source_codes,
        ) || return false
        mask_sha256(report.source_intermediate_use.explicit) ==
            EXPECTED_SOURCE_MATRIX_MASK_SHA256[:intermediate_use] ||
            return false
        mask_sha256(report.source_final_use.explicit) ==
            EXPECTED_SOURCE_MATRIX_MASK_SHA256[:final_use] ||
            return false
        mask_sha256(report.source_make.explicit) ==
            EXPECTED_SOURCE_MATRIX_MASK_SHA256[:make] ||
            return false
        for vector in (
                report.source_commodity_output,
                report.source_industry_output,
                report.source_scrap_output,
                report.source_other_output,
            )
            vector_axis_matches(vector, report.source_codes) || return false
        end
        Set(keys(report.source_vector_explicit)) ==
            Set(keys(EXPECTED_SOURCE_VECTOR_MASK_SHA256)) || return false
        all(
            length(mask) == 71
                for mask in values(report.source_vector_explicit)
        ) || return false
        all(
            mask_sha256(report.source_vector_explicit[key]) == expected
                for (key, expected) in EXPECTED_SOURCE_VECTOR_MASK_SHA256
        ) || return false

        U_values =
            A * report.source_intermediate_use.values * transpose(A)
        F_values = A * report.source_final_use.values
        V_values = A * report.source_make.values * transpose(A)
        q_values = A * report.source_commodity_output.values
        g_values = A * report.source_industry_output.values
        h_values = A * report.source_scrap_output.values
        o_values = A * report.source_other_output.values
        expected_matrices = (
            (
                report.aggregate_intermediate_use,
                CommodityBasis,
                IndustryBasis,
                report.model_codes,
                report.model_codes,
                U_values,
            ),
            (
                report.aggregate_final_use,
                CommodityBasis,
                FinalUseBasis,
                report.model_codes,
                report.final_use_codes,
                F_values,
            ),
            (
                report.aggregate_make,
                IndustryBasis,
                CommodityBasis,
                report.model_codes,
                report.model_codes,
                V_values,
            ),
        )
        for (matrix, _, _, rows, columns, values) in expected_matrices
            matrix_axes_match(matrix, rows, columns) || return false
            matrix.values == values || return false
            any(matrix.explicit) && return false
        end
        for (vector, values) in (
                (report.aggregate_commodity_output, q_values),
                (report.aggregate_industry_output, g_values),
                (report.aggregate_scrap_output, h_values),
                (report.aggregate_other_output, o_values),
            )
            vector_axis_matches(vector, report.model_codes) || return false
            vector.values == values || return false
        end
        Set(keys(report.derived_vector_explicit)) ==
            EXPECTED_DERIVED_VECTOR_KEYS || return false
        all(
            mask == falses(68)
                for mask in values(report.derived_vector_explicit)
        ) || return false

        B_values = U_values * Diagonal(1.0 ./ g_values)
        D_values = V_values * Diagonal(1.0 ./ q_values)
        p_values = h_values ./ g_values
        ratio_values = 1.0 .- p_values
        nonscrap_operator =
            Matrix{Float64}(I, 68, 68) - Diagonal(p_values)
        W_values = nonscrap_operator \ D_values
        H_values = B_values * W_values
        e_values = vec(sum(F_values; dims = 2))
        leontief_operator = Matrix{Float64}(I, 68, 68) - H_values
        inverse_values =
            leontief_operator \ Matrix{Float64}(I, 68, 68)
        for (matrix, rows, columns, values) in (
                (
                    report.input_coefficients,
                    report.model_codes,
                    report.model_codes,
                    B_values,
                ),
                (
                    report.market_shares,
                    report.model_codes,
                    report.model_codes,
                    D_values,
                ),
                (
                    report.nonscrap_transform,
                    report.model_codes,
                    report.model_codes,
                    W_values,
                ),
                (
                    report.requirements,
                    report.model_codes,
                    report.model_codes,
                    H_values,
                ),
                (
                    report.leontief_inverse,
                    report.model_codes,
                    report.model_codes,
                    inverse_values,
                ),
            )
            matrix_axes_match(matrix, rows, columns) || return false
            isapprox(matrix.values, values; atol = 1.0e-13, rtol = 0.0) ||
                return false
            any(matrix.explicit) && return false
        end
        report.scrap_shares.values == p_values || return false
        report.nonscrap_ratios.values == ratio_values || return false
        report.final_demand.values == e_values || return false
        all(value -> 0.0 <= value < 1.0, p_values) || return false
        all(>(0.0), ratio_values) || return false

        expected_coefficients = build_coefficient_witness(
            report.source_codes,
            report.model_codes,
            A,
            report.source_intermediate_use,
            report.source_make,
            report.source_commodity_output,
            report.source_industry_output,
            report.source_scrap_output,
            report.source_other_output,
            report.input_coefficients,
            report.nonscrap_transform,
            report.requirements,
        )
        structurally_equal(report.coefficients, expected_coefficients) ||
            return false
        report.coefficients.comparator_scope ==
            :current_table_conditional_not_general_identity ||
            return false
        report.coefficients.merged_source_codes ==
            RETAIL_SOURCE_CODE_ORDER || return false
        all(
            (
                report.coefficients.merged_zero_scrap_output,
                report.coefficients.merged_zero_other_output,
                report.coefficients.merged_own_commodity_make_only,
                report.coefficients.merged_own_make_equals_industry_output,
            ),
        ) || return false
        report.coefficients.conditional_current_table_w_ledger.maximum_absolute_difference <=
            2.0e-12 || return false
        report.coefficients.conditional_current_table_h_ledger.maximum_absolute_difference <=
            2.0e-12 || return false
        report.coefficients.raw_unweighted_w_ledger.absolute_total > 2.9 ||
            return false
        report.coefficients.raw_unweighted_w_ledger.maximum_row_code ==
            "4A0" || return false
        report.coefficients.raw_unweighted_w_ledger.maximum_column_code ==
            "4A0" || return false
        report.coefficients.raw_unweighted_w_shortcut_accepted &&
            return false

        expected_flows = build_flow_witness(
            report.source_codes,
            report.model_codes,
            report.final_use_codes,
            A,
            report.source_intermediate_use,
            report.source_final_use,
            report.nonscrap_transform,
            report.aggregate_intermediate_use,
            report.aggregate_final_use,
            report.coefficients,
        )
        structurally_equal(report.flows, expected_flows) || return false
        report.flows.intermediate_difference_ledger.absolute_total >
            1_100.0 || return false
        report.flows.final_use_difference_ledger.absolute_total >
            2_500.0 || return false

        expected_identities = build_identity_witness(
            report.model_codes,
            report.aggregate_intermediate_use,
            report.aggregate_make,
            report.aggregate_commodity_output,
            report.aggregate_industry_output,
            report.aggregate_scrap_output,
            report.aggregate_other_output,
            report.input_coefficients,
            report.market_shares,
            report.scrap_shares,
            report.nonscrap_transform,
            report.final_demand,
        )
        structurally_equal(report.identities, expected_identities) ||
            return false
        expected_other = build_other_witness(
            report.model_codes,
            report.aggregate_commodity_output,
            report.aggregate_other_output,
            report.input_coefficients,
            report.scrap_shares,
            report.requirements,
            report.final_demand,
        )
        structurally_equal(report.other, expected_other) || return false
        report.other.role == :arithmetic_omission_witness_only ||
            return false
        report.other.boundary_selected && return false

        isapprox(
            report.stability.spectral_radius_requirements,
            maximum(abs, eigvals(H_values));
            atol = 1.0e-12,
            rtol = 0.0,
        ) || return false
        isapprox(
            report.stability.nonscrap_operator_condition,
            cond(nonscrap_operator);
            atol = 1.0e-12,
            rtol = 0.0,
        ) || return false
        isapprox(
            report.stability.leontief_operator_condition,
            cond(leontief_operator);
            atol = 1.0e-11,
            rtol = 0.0,
        ) || return false
        report.stability.spectral_radius_requirements < 1.0 || return false

        expected_signs = build_sign_ledgers(report)
        report.sign_ledgers == expected_signs || return false
        report.sign_ledgers[:aggregate_make].negative_count == 1 ||
            return false
        report.sign_ledgers[:market_shares].negative_count == 1 ||
            return false
        report.sign_ledgers[:nonscrap_transform].negative_count == 1 ||
            return false
        for key in (
                :aggregate_intermediate_use,
                :scrap_output,
                :other_output,
                :input_coefficients,
                :scrap_shares,
                :requirements,
                :leontief_inverse,
            )
            report.sign_ledgers[key].negative_count == 0 || return false
        end
        structurally_equal(
            report.negative_make_cells,
            negative_cells(report.aggregate_make),
        ) || return false
        structurally_equal(
            report.negative_market_share_cells,
            negative_cells(report.market_shares),
        ) || return false
        structurally_equal(
            report.negative_nonscrap_transform_cells,
            negative_cells(report.nonscrap_transform),
        ) || return false

        expected_residuals = build_residuals(report)
        structurally_equal(report.residuals, expected_residuals) ||
            return false
        all(residual -> residual.passed, report.residuals) || return false

        report.contract_sha256 == APPROVED_CONTRACT_SHA256 || return false
        report.byte_pins == EXPECTED_BYTE_PINS || return false
        report.source_status == EXPECTED_STATUS || return false
        report.methodology_status ==
            "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA" ||
            return false
        report.artifact_role ==
            :aggregate_first_68_scrap_adjusted_diagnostic_only ||
            return false
        report.promotion_status == :research_only_not_promoted ||
            return false
        report.source_frequency == :annual || return false
        report.unit == :millions_usd || return false
        report.price_basis == :producers_prices || return false
        report.policies == expected_policies() || return false
        report.flags == expected_flags() || return false
        isempty(report.emitted_runtime_keys) || return false
        report.forbidden_runtime_keys == EXPECTED_FORBIDDEN_RUNTIME_KEYS ||
            return false
        report.promotion_blockers == EXPECTED_PROMOTION_BLOCKERS ||
            return false
        report.accounting_gate_effect == :none || return false
        report.promotion_ready && return false
    catch
        return false
    end
    return true
end

"""
    aggregate_first_scrap_adjusted_diagnostic_controls_pass(
        report,
        contract_path;
        source_paths...,
    )

Fail-closed source-aware stale-report gate. It validates internal structure
before reopening every direct byte source and reconstructing the canonical
report. There is deliberately no report-only overload.
"""
function aggregate_first_scrap_adjusted_diagnostic_controls_pass(
        report::AggregateFirstScrapAdjustedDiagnosticReport,
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        closure_boundary_contract_path =
            DEFAULT_CLOSURE_BOUNDARY_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    aggregate_first_scrap_adjusted_diagnostic_internal_controls_pass(
        report,
    ) || return false
    try
        expected = _build_aggregate_first_scrap_adjusted_diagnostic(
            contract_path;
            after_directory,
            model_mapping_path,
            sector_mapping_path,
            closure_boundary_contract_path,
            methodology_pdf_path,
            methodology_receipt_path,
        )
        return structurally_equal(report, expected)
    catch
        return false
    end
end

"""
    build_aggregate_first_scrap_adjusted_diagnostic(
        contract_path;
        source_paths...,
    )

Build the same-table diagnostic and require the canonical source-aware gate.
"""
function build_aggregate_first_scrap_adjusted_diagnostic(
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        closure_boundary_contract_path =
            DEFAULT_CLOSURE_BOUNDARY_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    report = _build_aggregate_first_scrap_adjusted_diagnostic(
        contract_path;
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        closure_boundary_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    aggregate_first_scrap_adjusted_diagnostic_controls_pass(
        report,
        contract_path;
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        closure_boundary_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    ) || throw(ArgumentError("canonical aggregate-first controls do not pass"))
    return report
end

"""
No runtime materializer exists for this research-only diagnostic.
"""
function materialize_aggregate_first_scrap_adjusted_model_state(
        ::AggregateFirstScrapAdjustedDiagnosticReport,
    )
    throw(
        ArgumentError(
            "aggregate-first scrap-adjusted diagnostic is not runtime admissible",
        ),
    )
end

end
