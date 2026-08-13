module USAfterRedefinitionsGenericIndustryTransformDiagnostic

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
using ..USRequirementsDiagnostics:
    load_official_direct_requirements_fixture
using ..USAfterRedefinitionsCommonBasis:
    AfterRedefinitionsValueAddedBasis,
    FinalUseBasis,
    load_after_redefinitions_fixture

export ClosureTransformWitness,
    GenericIndustryTransformDiagnosticReport,
    MarketShareSubstitutionWitness,
    MatrixSignLedger,
    TransformRoundingLedger,
    VectorResidualSummary,
    build_generic_industry_transform_diagnostic,
    generic_industry_transform_diagnostic_controls_pass,
    generic_industry_transform_diagnostic_internal_controls_pass

const CONTRACT_SCHEMA =
    "beforeit-us-after-redefinitions-generic-industry-transform-diagnostic.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_ARTIFACT_ROLE =
    "REJECTED_GENERIC_INDUSTRY_TRANSFORM_DIAGNOSTIC_ONLY"
const EXPECTED_PROMOTION_STATUS = "REJECTED_NOT_RUNTIME_ADMISSIBLE"
const APPROVED_CONTRACT_SHA256 =
    "4297b6faf5cd3fb0b0ee67d8d287f8b3481090c5d4e683c041e55f7a2d185f7c"
const APPROVED_OFFICIAL_FIXTURE_SHA256 =
    "d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e"
const APPROVED_OFFICIAL_MANIFEST_SHA256 =
    "a225951d7ec03aaaaa97f5cc02e58b862e00918dbd31cc35093d80f9dde8c35d"
const APPROVED_OFFICIAL_SOURCE_ZIP_SHA256 =
    "e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae"
const APPROVED_OFFICIAL_SOURCE_METADATA_SHA256 =
    "f3f57a7209f7c6d9b0f76b041f17ae78e9da1d8644dbd7d6815471e740abfaca"
const APPROVED_DIRECT_WORKBOOK_SHA256 =
    "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439"
const APPROVED_MARKET_SHARE_WORKBOOK_SHA256 =
    "57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2"
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
const APPROVED_ADAPTER_CONTRACT_SHA256 =
    "de524df56ad47fb1f26534019386b27f1fc45ebc927bda5f39c3ad812259cf58"
const APPROVED_METHODOLOGY_PDF_SHA256 =
    "535627e5e44f8461c0a04410f4a05c55d47f2e325d9473cb2df06e5d3e6b271d"
const APPROVED_METHODOLOGY_RECEIPT_SHA256 =
    "b4b210be3c364415473f1ef407ed7ea6e9edc2b299bd1058c1658b0ebb3b91ac"
const SOURCE_TRANSFORM_FORMULA = "Z_71 = D_official * U_producer"
const FINAL_USE_TRANSFORM_FORMULA = "Y_71 = D_official * F_producer"
const AGGREGATION_FORMULA =
    "Z_68 = A * Z_71 * transpose(A); Y_68 = A * Y_71"
const EXPECTED_CLOSURE_CODES = ["Used", "Other"]
const RETAIL_SOURCE_CODES = Set(["441", "445", "452", "4A0"])
const EXPECTED_PROMOTION_BLOCKERS = [
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
const CLOSURE_ROLES = Dict(
    "Used" =>
        "SCRAP_USED_AND_SECONDHAND_GOODS_COMMODITY_ONLY_BYPRODUCT_AND_FINAL_USE_SALES_ACCOUNT",
    "Other" =>
        "NONCOMPARABLE_IMPORTS_AND_REST_OF_WORLD_ADJUSTMENT_COMPOSITE",
)
const CLOSURE_PAGES = Dict(
    "Used" => [98, 214, 223, 224, 225],
    "Other" => [123, 124],
)

const DEFAULT_OFFICIAL_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_official_direct_requirements_approved",
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
const DEFAULT_ADAPTER_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_producer_price_adapter_candidate.toml")
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

"""
Signed-cell ledger. Published and derived negatives are retained; this ledger
never clips, redistributes, or reclassifies them.
"""
struct MatrixSignLedger
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

"""Summary of one signed accounting-identity residual vector."""
struct VectorResidualSummary
    signed_total::Float64
    absolute_total::Float64
    maximum_absolute_residual::Float64
    maximum_residual_code::String
    negative_count::Int
    positive_count::Int
end

"""
Ledger of published-rounding drift created by applying the exact official
market-share matrix. Drift is evidence, not a balancing target.
"""
struct TransformRoundingLedger
    market_share_total::Float64
    maximum_market_share_column_residual::Float64
    source_intermediate_total::Float64
    transformed_intermediate_total::Float64
    intermediate_total_drift::Float64
    source_final_use_total::Float64
    transformed_final_use_total::Float64
    final_use_total_drift::Float64
end

"""
Counterfactual showing that `producer_make / commodity_output` is not
interchangeable with the separately published official market-share matrix.
"""
struct MarketShareSubstitutionWitness
    make_derived_market_shares::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    official_minus_make_derived::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    make_derived_total::Float64
    make_derived_maximum_column_residual::Float64
    signed_difference::Float64
    absolute_difference::Float64
    differing_cell_count::Int
    maximum_difference::Float64
    maximum_row_code::String
    maximum_column_code::String
    official_value_at_maximum::Float64
    make_derived_value_at_maximum::Float64
end

"""
Contribution caused by transforming one special BEA closure commodity through
generic `D`. These contributions diagnose the semantic failure; they are not
approved allocations.
"""
struct ClosureTransformWitness
    code::String
    market_shares::LabeledVector{IndustryBasis}
    transformed_intermediate::LabeledMatrix{
        IndustryBasis,
        IndustryBasis,
    }
    transformed_final_use::LabeledMatrix{IndustryBasis, FinalUseBasis}
    intermediate_signs::MatrixSignLedger
    final_use_signs::MatrixSignLedger
    methodology_role::String
    methodology_pdf_pages::Vector{Int}
end

"""
Rejected generic industry-transform diagnostic.

The report performs the exact arithmetic `D_official * U` and
`D_official * F` on the published 71-industry/73-commodity axes, and only then
aggregates the four retail industries to the 68-industry model axis. It is a
byte-pinned falsification artifact, not a calibration or runtime candidate.
"""
struct GenericIndustryTransformDiagnosticReport
    year::Int
    source_industry_codes::Vector{String}
    commodity_codes::Vector{String}
    model_industry_codes::Vector{String}
    final_use_codes::Vector{String}
    source_industry_mapping::Dict{String, String}
    official_market_shares::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    producer_intermediate_use::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    producer_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    producer_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    producer_value_added::LabeledMatrix{
        AfterRedefinitionsValueAddedBasis,
        IndustryBasis,
    }
    commodity_output::LabeledVector{CommodityBasis}
    industry_output::LabeledVector{IndustryBasis}
    industry_aggregation::LabeledMatrix{IndustryBasis, IndustryBasis}
    source_transformed_intermediate::LabeledMatrix{
        IndustryBasis,
        IndustryBasis,
    }
    source_transformed_final_use::LabeledMatrix{
        IndustryBasis,
        FinalUseBasis,
    }
    model_transformed_intermediate::LabeledMatrix{
        IndustryBasis,
        IndustryBasis,
    }
    model_transformed_final_use::LabeledMatrix{
        IndustryBasis,
        FinalUseBasis,
    }
    closure_witnesses::Vector{ClosureTransformWitness}
    closure_intermediate_contribution::LabeledMatrix{
        IndustryBasis,
        IndustryBasis,
    }
    closure_final_use_contribution::LabeledMatrix{
        IndustryBasis,
        FinalUseBasis,
    }
    market_share_substitution::MarketShareSubstitutionWitness
    official_market_share_signs::MatrixSignLedger
    source_intermediate_signs::MatrixSignLedger
    source_final_use_signs::MatrixSignLedger
    source_transformed_intermediate_signs::MatrixSignLedger
    source_transformed_final_use_signs::MatrixSignLedger
    model_transformed_intermediate_signs::MatrixSignLedger
    model_transformed_final_use_signs::MatrixSignLedger
    closure_intermediate_signs::MatrixSignLedger
    closure_final_use_signs::MatrixSignLedger
    rounding::TransformRoundingLedger
    source_input_identity_residual::LabeledVector{IndustryBasis}
    source_output_identity_residual::LabeledVector{IndustryBasis}
    model_input_identity_residual::LabeledVector{IndustryBasis}
    model_output_identity_residual::LabeledVector{IndustryBasis}
    source_input_identity_summary::VectorResidualSummary
    source_output_identity_summary::VectorResidualSummary
    model_input_identity_summary::VectorResidualSummary
    model_output_identity_summary::VectorResidualSummary
    negative_official_market_share_cells::Vector{NegativeCell}
    negative_source_transformed_intermediate_cells::Vector{NegativeCell}
    negative_source_transformed_final_use_cells::Vector{NegativeCell}
    negative_model_transformed_intermediate_cells::Vector{NegativeCell}
    negative_model_transformed_final_use_cells::Vector{NegativeCell}
    residuals::Vector{ControlResidual}
    contract_sha256::String
    official_fixture_sha256::String
    official_manifest_sha256::String
    official_source_zip_sha256::String
    official_source_metadata_sha256::String
    direct_workbook_sha256::String
    market_share_workbook_sha256::String
    after_fixture_sha256::String
    after_manifest_sha256::String
    after_source_zip_sha256::String
    model_mapping_sha256::String
    sector_mapping_sha256::String
    adapter_contract_sha256::String
    methodology_pdf_sha256::String
    methodology_receipt_sha256::String
    source_transform_formula::String
    final_use_transform_formula::String
    aggregation_formula::String
    source_status::String
    artifact_role::String
    promotion_status::String
    market_share_source::Symbol
    aggregation_order::Symbol
    cross_archive_release_identity::Symbol
    cross_archive_application_status::Symbol
    negative_cell_policy::Symbol
    rounding_policy::Symbol
    closure_policy::Symbol
    diagnostic_transform_applied::Bool
    runtime_transform_selected::Bool
    runtime_calibration_admissible::Bool
    calibration_dictionary_write::Bool
    parameter_write::Bool
    initial_conditions_write::Bool
    model_state_write::Bool
    forecast_origin_admissible::Bool
    accounting_gate_effect::Symbol
    nonscrap_transform_applied::Bool
    used_final_sales_supply_adjustment_applied::Bool
    other_boundary_selected::Bool
    balancing_applied::Bool
    normalization_applied::Bool
    clipping_applied::Bool
    raking_applied::Bool
    promotion_blockers::Vector{String}
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

function matrix_sign_ledger(values)
    numeric = Matrix{Float64}(values)
    negatives = numeric[numeric .< 0.0]
    positives = numeric[numeric .> 0.0]
    return MatrixSignLedger(
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

matrix_sign_ledger(matrix::LabeledMatrix) =
    matrix_sign_ledger(matrix.values)

function residual_summary(vector::LabeledVector)
    maximum_position = argmax(abs.(vector.values))
    return VectorResidualSummary(
        sum(vector.values),
        sum(abs, vector.values),
        abs(vector.values[maximum_position]),
        vector.codes[maximum_position],
        count(value -> value < 0.0, vector.values),
        count(value -> value > 0.0, vector.values),
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
            structurally_equal(left, right)
                for (left, right) in zip(lhs, rhs)
        )
    elseif lhs isa AbstractDict
        Set(keys(lhs)) == Set(keys(rhs)) || return false
        return all(structurally_equal(lhs[key], rhs[key]) for key in keys(lhs))
    elseif lhs isa Tuple
        return all(
            structurally_equal(left, right)
                for (left, right) in zip(lhs, rhs)
        )
    elseif isstructtype(typeof(lhs)) &&
            !(lhs isa Number || lhs isa AbstractString || lhs isa Symbol)
        return all(
            structurally_equal(getfield(lhs, field), getfield(rhs, field))
                for field in fieldnames(typeof(lhs))
        )
    end
    return isequal(lhs, rhs)
end

function require_hash(path, expected, label)
    sha256_hex(read(path)) == expected ||
        throw(ArgumentError("$label SHA-256 changed"))
    return expected
end

function require_contract_value(contract, key, expected)
    return get(contract, key, nothing) == expected ||
        throw(ArgumentError("generic-transform contract field $key changed"))
end

function validate_contract(
        contract_path,
        official_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        adapter_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    require_hash(
        contract_path,
        APPROVED_CONTRACT_SHA256,
        "generic-transform contract",
    )
    contract = TOML.parsefile(contract_path)
    require_contract_value(contract, "schema_version", CONTRACT_SCHEMA)
    require_contract_value(contract, "classification", EXPECTED_STATUS)
    require_contract_value(contract, "artifact_role", EXPECTED_ARTIFACT_ROLE)
    require_contract_value(
        contract,
        "promotion_status",
        EXPECTED_PROMOTION_STATUS,
    )
    require_contract_value(contract, "source_year", 2024)
    require_contract_value(contract, "source_commodity_count", 73)
    require_contract_value(contract, "source_industry_count", 71)
    require_contract_value(contract, "model_industry_count", 68)
    require_contract_value(contract, "final_use_count", 20)
    require_contract_value(contract, "closure_codes", EXPECTED_CLOSURE_CODES)
    require_contract_value(
        contract,
        "source_transform_formula",
        SOURCE_TRANSFORM_FORMULA,
    )
    require_contract_value(
        contract,
        "final_use_transform_formula",
        FINAL_USE_TRANSFORM_FORMULA,
    )
    require_contract_value(
        contract,
        "post_transform_aggregation_formula",
        AGGREGATION_FORMULA,
    )
    require_contract_value(
        contract,
        "market_share_source",
        "OFFICIAL_PUBLISHED_IXC_MS_SUMMARY_NOT_RECOMPUTED",
    )
    require_contract_value(
        contract,
        "aggregation_order",
        "TRANSFORM_SOURCE_AXES_THEN_AGGREGATE_INDUSTRIES",
    )
    require_contract_value(
        contract,
        "cross_archive_release_identity",
        "NOT_EXTERNALLY_BOUND",
    )
    require_contract_value(
        contract,
        "cross_archive_application_status",
        "ARITHMETIC_DIAGNOSTIC_ONLY",
    )
    require_contract_value(
        contract,
        "promotion_blockers",
        EXPECTED_PROMOTION_BLOCKERS,
    )

    require_contract_value(contract, "diagnostic_transform_applied", true)
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
        require_contract_value(contract, key, false)
    end
    require_contract_value(contract, "accounting_gate_effect", "NONE")

    pinned_paths = [
        (
            joinpath(official_directory, "cells.csv"),
            APPROVED_OFFICIAL_FIXTURE_SHA256,
            "official market-share fixture",
        ),
        (
            joinpath(official_directory, "manifest.toml"),
            APPROVED_OFFICIAL_MANIFEST_SHA256,
            "official market-share manifest",
        ),
        (
            joinpath(after_directory, "cells.csv"),
            APPROVED_AFTER_FIXTURE_SHA256,
            "after-redefinitions fixture",
        ),
        (
            joinpath(after_directory, "manifest.toml"),
            APPROVED_AFTER_MANIFEST_SHA256,
            "after-redefinitions manifest",
        ),
        (
            model_mapping_path,
            APPROVED_MODEL_MAPPING_SHA256,
            "model mapping",
        ),
        (
            sector_mapping_path,
            APPROVED_SECTOR_MAPPING_SHA256,
            "sector mapping",
        ),
        (
            adapter_contract_path,
            APPROVED_ADAPTER_CONTRACT_SHA256,
            "producer-price adapter contract",
        ),
        (
            methodology_pdf_path,
            APPROVED_METHODOLOGY_PDF_SHA256,
            "methodology PDF",
        ),
        (
            methodology_receipt_path,
            APPROVED_METHODOLOGY_RECEIPT_SHA256,
            "methodology receipt",
        ),
    ]
    for (path, expected, label) in pinned_paths
        require_hash(path, expected, label)
    end

    pinned_contract_hashes = Dict(
        "official_market_share_fixture_sha256" =>
            APPROVED_OFFICIAL_FIXTURE_SHA256,
        "official_market_share_manifest_sha256" =>
            APPROVED_OFFICIAL_MANIFEST_SHA256,
        "official_market_share_source_zip_sha256" =>
            APPROVED_OFFICIAL_SOURCE_ZIP_SHA256,
        "official_market_share_source_metadata_sha256" =>
            APPROVED_OFFICIAL_SOURCE_METADATA_SHA256,
        "official_direct_workbook_sha256" =>
            APPROVED_DIRECT_WORKBOOK_SHA256,
        "official_market_share_workbook_sha256" =>
            APPROVED_MARKET_SHARE_WORKBOOK_SHA256,
        "after_redefinitions_fixture_sha256" =>
            APPROVED_AFTER_FIXTURE_SHA256,
        "after_redefinitions_manifest_sha256" =>
            APPROVED_AFTER_MANIFEST_SHA256,
        "after_redefinitions_source_zip_sha256" =>
            APPROVED_AFTER_SOURCE_ZIP_SHA256,
        "model_mapping_sha256" => APPROVED_MODEL_MAPPING_SHA256,
        "sector_mapping_sha256" => APPROVED_SECTOR_MAPPING_SHA256,
        "producer_price_adapter_contract_sha256" =>
            APPROVED_ADAPTER_CONTRACT_SHA256,
        "methodology_pdf_sha256" => APPROVED_METHODOLOGY_PDF_SHA256,
        "methodology_receipt_sha256" =>
            APPROVED_METHODOLOGY_RECEIPT_SHA256,
    )
    for (key, expected) in pinned_contract_hashes
        require_contract_value(contract, key, expected)
    end

    closure_accounts = get(contract, "closure_account", Any[])
    length(closure_accounts) == 2 ||
        throw(ArgumentError("generic-transform closure contract changed"))
    for account in closure_accounts
        code = String(get(account, "code", ""))
        code in EXPECTED_CLOSURE_CODES ||
            throw(ArgumentError("generic-transform closure code changed"))
        get(account, "methodology_role", "") == CLOSURE_ROLES[code] ||
            throw(ArgumentError("generic-transform closure role changed"))
        Int.(get(account, "methodology_pdf_pages", Int[])) ==
            CLOSURE_PAGES[code] ||
            throw(ArgumentError("generic-transform closure pages changed"))
        get(account, "ordinary_model_commodity", true) === false ||
            throw(ArgumentError("closure cannot become a model commodity"))
        get(account, "ordinary_model_producer_industry", true) === false ||
            throw(ArgumentError("closure cannot become a model industry"))
    end

    receipt = TOML.parsefile(methodology_receipt_path)
    get(receipt, "source_sha256", "") == APPROVED_METHODOLOGY_PDF_SHA256 ||
        throw(ArgumentError("methodology receipt/PDF identity changed"))
    Int.(get(receipt, "relevant_pdf_pages", Int[])) ==
        [98, 123, 124, 214, 223, 224, 225] ||
        throw(ArgumentError("methodology receipt relevant pages changed"))
    get(receipt, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("methodology source cannot admit an origin"))
    get(receipt, "model_state_write", true) === false ||
        throw(ArgumentError("methodology source cannot write model state"))
    get(receipt, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("methodology source cannot affect gates"))
    return contract
end

function source_industry_contract(model_mapping_path, sector_mapping_path)
    mapping = TOML.parsefile(model_mapping_path)
    sector_mapping = TOML.parsefile(sector_mapping_path)
    model_codes = String.(get(mapping, "model_codes", String[]))
    model_codes == String.(
        get(get(sector_mapping, "model", Dict()), "codes", String[]),
    ) || throw(ArgumentError("model and sector mapping codes differ"))
    length(model_codes) == 68 && length(unique(model_codes)) == 68 ||
        throw(ArgumentError("model industry axis changed"))
    return model_codes
end

function industry_aggregation_matrix(source_codes, model_codes)
    model_index =
        Dict(code => position for (position, code) in pairs(model_codes))
    mapping = Dict{String, String}()
    aggregation_values = zeros(length(model_codes), length(source_codes))
    for (source_position, source_code) in pairs(source_codes)
        target_code = source_code in RETAIL_SOURCE_CODES ? "4A0" : source_code
        haskey(model_index, target_code) ||
            throw(ArgumentError("unmapped source industry $source_code"))
        mapping[source_code] = target_code
        aggregation_values[model_index[target_code], source_position] = 1.0
    end
    Set(values(mapping)) == Set(model_codes) ||
        throw(ArgumentError("industry aggregation misses a model code"))
    return (
        mapping,
        derived_matrix(
            IndustryBasis,
            IndustryBasis,
            model_codes,
            source_codes,
            aggregation_values,
        ),
    )
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

function closure_witness(code, D, U, F)
    commodity_position = D.column_index[code]
    shares = D.values[:, commodity_position]
    intermediate =
        shares * transpose(U.values[commodity_position, :])
    final_use = shares * transpose(F.values[commodity_position, :])
    intermediate_matrix = derived_matrix(
        IndustryBasis,
        IndustryBasis,
        D.row_codes,
        U.column_codes,
        intermediate,
    )
    final_use_matrix = derived_matrix(
        IndustryBasis,
        FinalUseBasis,
        D.row_codes,
        F.column_codes,
        final_use,
    )
    return ClosureTransformWitness(
        code,
        LabeledVector{IndustryBasis}(D.row_codes, shares),
        intermediate_matrix,
        final_use_matrix,
        matrix_sign_ledger(intermediate_matrix),
        matrix_sign_ledger(final_use_matrix),
        CLOSURE_ROLES[code],
        CLOSURE_PAGES[code],
    )
end

function _build_generic_industry_transform_diagnostic(
        contract_path;
        official_directory = DEFAULT_OFFICIAL_FIXTURE_DIRECTORY,
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        adapter_contract_path = DEFAULT_ADAPTER_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    contract = validate_contract(
        contract_path,
        official_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        adapter_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    official =
        load_official_direct_requirements_fixture(official_directory)
    after = load_after_redefinitions_fixture(after_directory)
    official.year == after.year == 2024 ||
        throw(ArgumentError("generic-transform source years differ"))
    official.source_zip_sha256 == APPROVED_OFFICIAL_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("official source ZIP identity changed"))
    official.direct_workbook_sha256 == APPROVED_DIRECT_WORKBOOK_SHA256 ||
        throw(ArgumentError("official direct workbook identity changed"))
    official.market_share_workbook_sha256 ==
        APPROVED_MARKET_SHARE_WORKBOOK_SHA256 ||
        throw(ArgumentError("official market-share workbook identity changed"))
    after.provenance.source_zip_sha256 == APPROVED_AFTER_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("after-redefinitions source ZIP identity changed"))

    D = official.market_shares
    U = after.producer_intermediate_use
    F = after.producer_final_use
    V = after.producer_make
    q = after.producer_commodity_output_make
    g = after.producer_industry_output_make
    VA = after.producer_value_added
    D.column_codes == U.row_codes == F.row_codes == V.column_codes ==
        q.codes ||
        throw(ArgumentError("commodity axes are not identical and ordered"))
    D.row_codes == U.column_codes == V.row_codes == g.codes ==
        VA.column_codes ||
        throw(ArgumentError("industry axes are not identical and ordered"))
    all(D.explicit) ||
        throw(ArgumentError("official market-share source cells must be explicit"))

    model_codes =
        source_industry_contract(model_mapping_path, sector_mapping_path)
    source_mapping, A = industry_aggregation_matrix(D.row_codes, model_codes)
    z71_values = D.values * U.values
    y71_values = D.values * F.values
    z68_values = A.values * z71_values * transpose(A.values)
    y68_values = A.values * y71_values
    Z71 = derived_matrix(
        IndustryBasis,
        IndustryBasis,
        D.row_codes,
        U.column_codes,
        z71_values,
    )
    Y71 = derived_matrix(
        IndustryBasis,
        FinalUseBasis,
        D.row_codes,
        F.column_codes,
        y71_values,
    )
    Z68 = derived_matrix(
        IndustryBasis,
        IndustryBasis,
        model_codes,
        model_codes,
        z68_values,
    )
    Y68 = derived_matrix(
        IndustryBasis,
        FinalUseBasis,
        model_codes,
        F.column_codes,
        y68_values,
    )

    witnesses = [
        closure_witness(code, D, U, F) for code in EXPECTED_CLOSURE_CODES
    ]
    closure_intermediate_values = sum(
        witness.transformed_intermediate.values for witness in witnesses
    )
    closure_final_values =
        sum(witness.transformed_final_use.values for witness in witnesses)
    closure_Z = derived_matrix(
        IndustryBasis,
        IndustryBasis,
        D.row_codes,
        U.column_codes,
        closure_intermediate_values,
    )
    closure_Y = derived_matrix(
        IndustryBasis,
        FinalUseBasis,
        D.row_codes,
        F.column_codes,
        closure_final_values,
    )

    make_D_values = V.values ./ transpose(q.values)
    difference_values = D.values - make_D_values
    maximum_index = argmax(abs.(difference_values))
    make_D = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        D.row_codes,
        D.column_codes,
        make_D_values,
    )
    D_difference = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        D.row_codes,
        D.column_codes,
        difference_values,
    )
    substitution = MarketShareSubstitutionWitness(
        make_D,
        D_difference,
        sum(make_D_values),
        maximum(abs, vec(sum(make_D_values; dims = 1)) .- 1.0),
        sum(difference_values),
        sum(abs, difference_values),
        count(!iszero, difference_values),
        difference_values[maximum_index],
        D.row_codes[maximum_index[1]],
        D.column_codes[maximum_index[2]],
        D.values[maximum_index],
        make_D_values[maximum_index],
    )

    rounding = TransformRoundingLedger(
        sum(D.values),
        maximum(abs, vec(sum(D.values; dims = 1)) .- 1.0),
        sum(U.values),
        sum(z71_values),
        sum(z71_values) - sum(U.values),
        sum(F.values),
        sum(y71_values),
        sum(y71_values) - sum(F.values),
    )

    source_input_values =
        vec(sum(z71_values; dims = 1)) +
        vec(sum(VA.values; dims = 1)) - g.values
    source_output_values =
        vec(sum(z71_values; dims = 2)) +
        vec(sum(y71_values; dims = 2)) - g.values
    model_value_added = VA.values * transpose(A.values)
    model_output = A.values * g.values
    model_input_values =
        vec(sum(z68_values; dims = 1)) +
        vec(sum(model_value_added; dims = 1)) - model_output
    model_output_values =
        vec(sum(z68_values; dims = 2)) +
        vec(sum(y68_values; dims = 2)) - model_output
    source_input =
        LabeledVector{IndustryBasis}(D.row_codes, source_input_values)
    source_output =
        LabeledVector{IndustryBasis}(D.row_codes, source_output_values)
    model_input =
        LabeledVector{IndustryBasis}(model_codes, model_input_values)
    model_output_residual =
        LabeledVector{IndustryBasis}(model_codes, model_output_values)

    residuals = ControlResidual[]
    for (position, code) in pairs(D.column_codes)
        add_residual!(
            residuals,
            :official_market_share_column_control,
            code,
            "sum_i D_official[i,c] = 1 within published precision",
            sum(D.values[:, position]),
            1.0,
            3.6e-6,
        )
    end
    add_residual!(
        residuals,
        :exact_transform,
        "intermediate",
        SOURCE_TRANSFORM_FORMULA,
        maximum(abs, Z71.values - D.values * U.values),
        0.0,
        0.0,
    )
    add_residual!(
        residuals,
        :exact_transform,
        "final_use",
        FINAL_USE_TRANSFORM_FORMULA,
        maximum(abs, Y71.values - D.values * F.values),
        0.0,
        0.0,
    )
    add_residual!(
        residuals,
        :post_transform_aggregation,
        "intermediate",
        AGGREGATION_FORMULA,
        maximum(
            abs,
            Z68.values - A.values * Z71.values * transpose(A.values),
        ),
        0.0,
        0.0,
    )
    add_residual!(
        residuals,
        :post_transform_aggregation,
        "final_use",
        AGGREGATION_FORMULA,
        maximum(abs, Y68.values - A.values * Y71.values),
        0.0,
        0.0,
    )
    for (code, lhs, rhs, tolerance) in (
            ("official_D_total", sum(D.values), 72.9999995, 1.0e-12),
            (
                "source_transformed_intermediate_total",
                sum(Z71.values),
                21_438_568.4256538,
                1.0e-6,
            ),
            (
                "source_transformed_final_use_total",
                sum(Y71.values),
                29_298_006.672114003,
                1.0e-6,
            ),
            (
                "closure_intermediate_total",
                sum(closure_Z.values),
                272_726.01000939996,
                1.0e-6,
            ),
            (
                "closure_final_use_total",
                sum(closure_Y.values),
                -252_983.00865420004,
                1.0e-6,
            ),
            (
                "official_make_D_absolute_difference",
                substitution.absolute_difference,
                0.0008565132482050305,
                1.0e-12,
            ),
        )
        add_residual!(
            residuals,
            :pinned_numeric_witness,
            code,
            "pinned diagnostic witness is reproduced",
            lhs,
            rhs,
            tolerance,
        )
    end

    return GenericIndustryTransformDiagnosticReport(
        after.year,
        D.row_codes,
        D.column_codes,
        model_codes,
        F.column_codes,
        source_mapping,
        D,
        U,
        F,
        V,
        VA,
        q,
        g,
        A,
        Z71,
        Y71,
        Z68,
        Y68,
        witnesses,
        closure_Z,
        closure_Y,
        substitution,
        matrix_sign_ledger(D),
        matrix_sign_ledger(U),
        matrix_sign_ledger(F),
        matrix_sign_ledger(Z71),
        matrix_sign_ledger(Y71),
        matrix_sign_ledger(Z68),
        matrix_sign_ledger(Y68),
        matrix_sign_ledger(closure_Z),
        matrix_sign_ledger(closure_Y),
        rounding,
        source_input,
        source_output,
        model_input,
        model_output_residual,
        residual_summary(source_input),
        residual_summary(source_output),
        residual_summary(model_input),
        residual_summary(model_output_residual),
        negative_cells(D),
        negative_cells(Z71),
        negative_cells(Y71),
        negative_cells(Z68),
        negative_cells(Y68),
        residuals,
        APPROVED_CONTRACT_SHA256,
        APPROVED_OFFICIAL_FIXTURE_SHA256,
        APPROVED_OFFICIAL_MANIFEST_SHA256,
        APPROVED_OFFICIAL_SOURCE_ZIP_SHA256,
        APPROVED_OFFICIAL_SOURCE_METADATA_SHA256,
        APPROVED_DIRECT_WORKBOOK_SHA256,
        APPROVED_MARKET_SHARE_WORKBOOK_SHA256,
        APPROVED_AFTER_FIXTURE_SHA256,
        APPROVED_AFTER_MANIFEST_SHA256,
        APPROVED_AFTER_SOURCE_ZIP_SHA256,
        APPROVED_MODEL_MAPPING_SHA256,
        APPROVED_SECTOR_MAPPING_SHA256,
        APPROVED_ADAPTER_CONTRACT_SHA256,
        APPROVED_METHODOLOGY_PDF_SHA256,
        APPROVED_METHODOLOGY_RECEIPT_SHA256,
        SOURCE_TRANSFORM_FORMULA,
        FINAL_USE_TRANSFORM_FORMULA,
        AGGREGATION_FORMULA,
        EXPECTED_STATUS,
        EXPECTED_ARTIFACT_ROLE,
        EXPECTED_PROMOTION_STATUS,
        :official_published_ixc_ms_summary_not_recomputed,
        :transform_source_axes_then_aggregate_industries,
        :not_externally_bound,
        :arithmetic_diagnostic_only,
        :preserve_and_ledger,
        :preserve_published_values_and_ledger_drift,
        :used_other_transformed_only_to_expose_generic_D_failure,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        :none,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        String.(contract["promotion_blockers"]),
    )
end

"""
Internal algebra and policy predicate. This deliberately is not the public
source attestation; callers must provide the byte sources to
`generic_industry_transform_diagnostic_controls_pass`.
"""
function generic_industry_transform_diagnostic_internal_controls_pass(
        report::GenericIndustryTransformDiagnosticReport,
    )
    all(residual.passed for residual in report.residuals) || return false
    report.source_status == EXPECTED_STATUS || return false
    report.artifact_role == EXPECTED_ARTIFACT_ROLE || return false
    report.promotion_status == EXPECTED_PROMOTION_STATUS || return false
    report.promotion_blockers == EXPECTED_PROMOTION_BLOCKERS || return false
    report.contract_sha256 == APPROVED_CONTRACT_SHA256 || return false
    report.official_fixture_sha256 == APPROVED_OFFICIAL_FIXTURE_SHA256 ||
        return false
    report.direct_workbook_sha256 == APPROVED_DIRECT_WORKBOOK_SHA256 ||
        return false
    report.after_fixture_sha256 == APPROVED_AFTER_FIXTURE_SHA256 ||
        return false
    report.adapter_contract_sha256 == APPROVED_ADAPTER_CONTRACT_SHA256 ||
        return false
    report.methodology_pdf_sha256 == APPROVED_METHODOLOGY_PDF_SHA256 ||
        return false
    report.source_transform_formula == SOURCE_TRANSFORM_FORMULA || return false
    report.final_use_transform_formula == FINAL_USE_TRANSFORM_FORMULA ||
        return false
    report.aggregation_formula == AGGREGATION_FORMULA || return false
    report.market_share_source ==
        :official_published_ixc_ms_summary_not_recomputed || return false
    report.aggregation_order ==
        :transform_source_axes_then_aggregate_industries || return false
    report.cross_archive_release_identity == :not_externally_bound ||
        return false
    report.cross_archive_application_status == :arithmetic_diagnostic_only ||
        return false
    report.negative_cell_policy == :preserve_and_ledger || return false
    report.rounding_policy ==
        :preserve_published_values_and_ledger_drift || return false
    report.closure_policy ==
        :used_other_transformed_only_to_expose_generic_D_failure || return false
    report.diagnostic_transform_applied || return false
    any(
        (
            report.runtime_transform_selected,
            report.runtime_calibration_admissible,
            report.calibration_dictionary_write,
            report.parameter_write,
            report.initial_conditions_write,
            report.model_state_write,
            report.forecast_origin_admissible,
            report.nonscrap_transform_applied,
            report.used_final_sales_supply_adjustment_applied,
            report.other_boundary_selected,
            report.balancing_applied,
            report.normalization_applied,
            report.clipping_applied,
            report.raking_applied,
        ),
    ) && return false
    report.accounting_gate_effect == :none || return false

    try
        industries = report.source_industry_codes
        commodities = report.commodity_codes
        model_codes = report.model_industry_codes
        final_uses = report.final_use_codes
        D = report.official_market_shares
        U = report.producer_intermediate_use
        F = report.producer_final_use
        A = report.industry_aggregation
        Z71 = report.source_transformed_intermediate
        Y71 = report.source_transformed_final_use
        Z68 = report.model_transformed_intermediate
        Y68 = report.model_transformed_final_use

        matrix_axes_match(D, industries, commodities) || return false
        matrix_axes_match(U, commodities, industries) || return false
        matrix_axes_match(F, commodities, final_uses) || return false
        matrix_axes_match(A, model_codes, industries) || return false
        matrix_axes_match(Z71, industries, industries) || return false
        matrix_axes_match(Y71, industries, final_uses) || return false
        matrix_axes_match(Z68, model_codes, model_codes) || return false
        matrix_axes_match(Y68, model_codes, final_uses) || return false
        all(D.explicit) || return false
        any(A.explicit) && return false
        any(Z71.explicit) && return false
        any(Y71.explicit) && return false
        any(Z68.explicit) && return false
        any(Y68.explicit) && return false
        isequal(Z71.values, D.values * U.values) || return false
        isequal(Y71.values, D.values * F.values) || return false
        isequal(
            Z68.values,
            A.values * Z71.values * transpose(A.values),
        ) || return false
        isequal(Y68.values, A.values * Y71.values) || return false
        all(sum(A.values; dims = 1) .== 1.0) || return false
        all(
            value == 0.0 || value == 1.0
                for value in A.values
        ) || return false
        Set(values(report.source_industry_mapping)) == Set(model_codes) ||
            return false

        structurally_equal(
            report.official_market_share_signs,
            matrix_sign_ledger(D),
        ) || return false
        structurally_equal(
            report.source_intermediate_signs,
            matrix_sign_ledger(U),
        ) || return false
        structurally_equal(
            report.source_final_use_signs,
            matrix_sign_ledger(F),
        ) || return false
        structurally_equal(
            report.source_transformed_intermediate_signs,
            matrix_sign_ledger(Z71),
        ) || return false
        structurally_equal(
            report.source_transformed_final_use_signs,
            matrix_sign_ledger(Y71),
        ) || return false
        structurally_equal(
            report.model_transformed_intermediate_signs,
            matrix_sign_ledger(Z68),
        ) || return false
        structurally_equal(
            report.model_transformed_final_use_signs,
            matrix_sign_ledger(Y68),
        ) || return false
        negative_cell_vectors_match(
            report.negative_official_market_share_cells,
            negative_cells(D),
        ) || return false
        negative_cell_vectors_match(
            report.negative_source_transformed_intermediate_cells,
            negative_cells(Z71),
        ) || return false
        negative_cell_vectors_match(
            report.negative_source_transformed_final_use_cells,
            negative_cells(Y71),
        ) || return false
        negative_cell_vectors_match(
            report.negative_model_transformed_intermediate_cells,
            negative_cells(Z68),
        ) || return false
        negative_cell_vectors_match(
            report.negative_model_transformed_final_use_cells,
            negative_cells(Y68),
        ) || return false
        vector_axis_matches(
            report.source_input_identity_residual,
            industries,
        ) || return false
        vector_axis_matches(
            report.source_output_identity_residual,
            industries,
        ) || return false
        vector_axis_matches(
            report.model_input_identity_residual,
            model_codes,
        ) || return false
        vector_axis_matches(
            report.model_output_identity_residual,
            model_codes,
        ) || return false
        structurally_equal(
            report.source_input_identity_summary,
            residual_summary(report.source_input_identity_residual),
        ) || return false
        structurally_equal(
            report.source_output_identity_summary,
            residual_summary(report.source_output_identity_residual),
        ) || return false
        structurally_equal(
            report.model_input_identity_summary,
            residual_summary(report.model_input_identity_residual),
        ) || return false
        structurally_equal(
            report.model_output_identity_summary,
            residual_summary(report.model_output_identity_residual),
        ) || return false

        length(report.closure_witnesses) == 2 || return false
        [witness.code for witness in report.closure_witnesses] ==
            EXPECTED_CLOSURE_CODES || return false
        for witness in report.closure_witnesses
            expected = closure_witness(witness.code, D, U, F)
            structurally_equal(witness, expected) || return false
        end
        closure_Z =
            sum(w.transformed_intermediate.values for w in report.closure_witnesses)
        closure_Y =
            sum(w.transformed_final_use.values for w in report.closure_witnesses)
        isequal(report.closure_intermediate_contribution.values, closure_Z) ||
            return false
        isequal(report.closure_final_use_contribution.values, closure_Y) ||
            return false
        structurally_equal(
            report.closure_intermediate_signs,
            matrix_sign_ledger(closure_Z),
        ) || return false
        structurally_equal(
            report.closure_final_use_signs,
            matrix_sign_ledger(closure_Y),
        ) || return false

        make_D =
            report.producer_make.values ./
            transpose(report.commodity_output.values)
        substitution = report.market_share_substitution
        isequal(substitution.make_derived_market_shares.values, make_D) ||
            return false
        isequal(
            substitution.official_minus_make_derived.values,
            D.values - make_D,
        ) || return false
        substitution.absolute_difference > 0.0 || return false
    catch
        return false
    end
    return true
end

"""
Source-aware canonical gate. Every contract, source fixture, mapping, adapter
contract, and methodology byte source is reopened, the report is rebuilt, and
every field is recursively compared. Altered paths fail closed.
"""
function generic_industry_transform_diagnostic_controls_pass(
        report::GenericIndustryTransformDiagnosticReport,
        contract_path::AbstractString;
        official_directory = DEFAULT_OFFICIAL_FIXTURE_DIRECTORY,
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        adapter_contract_path = DEFAULT_ADAPTER_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    try
        generic_industry_transform_diagnostic_internal_controls_pass(report) ||
            return false
        expected = _build_generic_industry_transform_diagnostic(
            contract_path;
            official_directory,
            after_directory,
            model_mapping_path,
            sector_mapping_path,
            adapter_contract_path,
            methodology_pdf_path,
            methodology_receipt_path,
        )
        return structurally_equal(report, expected)
    catch
        return false
    end
end

"""
Build the byte-pinned rejected diagnostic. No calibration dictionary,
parameter, initial condition, model state, or accounting gate is written.
"""
function build_generic_industry_transform_diagnostic(
        contract_path::AbstractString;
        official_directory = DEFAULT_OFFICIAL_FIXTURE_DIRECTORY,
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        adapter_contract_path = DEFAULT_ADAPTER_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    report = _build_generic_industry_transform_diagnostic(
        contract_path;
        official_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        adapter_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    generic_industry_transform_diagnostic_internal_controls_pass(report) ||
        throw(ArgumentError("generic-transform internal controls do not pass"))
    generic_industry_transform_diagnostic_controls_pass(
        report,
        contract_path;
        official_directory,
        after_directory,
        model_mapping_path,
        sector_mapping_path,
        adapter_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    ) || throw(ArgumentError("generic-transform source controls do not pass"))
    return report
end

end
