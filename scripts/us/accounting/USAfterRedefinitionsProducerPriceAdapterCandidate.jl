module USAfterRedefinitionsProducerPriceAdapterCandidate

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
    AfterRedefinitionsValueAddedBasis,
    FinalUseBasis,
    load_after_redefinitions_fixture
using ..USAfterRedefinitionsModelCore:
    build_model_core_aggregation
using ..USAfterRedefinitionsValuationEnvelope: TaxControlVariant
using ..USAfterRedefinitionsFinalUseEnvelope:
    FinalUseCategoryBasis,
    build_final_use_envelope

export AdapterOutputAssessment,
    ClosureAccountAssessment,
    ClosureOmissionWitness,
    ImportBoundaryEvidence,
    InventoryFlowCandidate,
    ProducerPriceAdapterCandidateReport,
    ResidentialInvestmentCandidate,
    build_producer_price_adapter_candidate,
    materialize_producer_price_adapter_model_state,
    producer_price_adapter_candidate_controls_pass,
    producer_price_adapter_candidate_internal_controls_pass

const CONTRACT_SCHEMA =
    "beforeit-us-after-redefinitions-producer-price-adapter-candidate.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_ARTIFACT_ROLE =
    "TYPED_CALIBRATION_ADAPTER_CANDIDATE_ONLY"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_CONTRACT_SHA256 =
    "de524df56ad47fb1f26534019386b27f1fc45ebc927bda5f39c3ad812259cf58"
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
const APPROVED_FINAL_USE_CONTRACT_SHA256 =
    "b4e3969a52618b4e462b8e468ada784dda85cae86550fb27659d2afbb4cbb2be"
const APPROVED_SUPPLY_FIXTURE_SHA256 =
    "c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0"
const APPROVED_SUPPLY_MANIFEST_SHA256 =
    "564a99ec2011b2566b8951e9eecb4737c0bfbc88f1e077b1eaf596af9894575c"
const APPROVED_TABLE_262_SOURCE_SHA256 =
    "91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8"
const APPROVED_METHODOLOGY_PDF_SHA256 =
    "535627e5e44f8461c0a04410f4a05c55d47f2e325d9473cb2df06e5d3e6b271d"
const APPROVED_METHODOLOGY_RECEIPT_SHA256 =
    "b4b210be3c364415473f1ef407ed7ea6e9edc2b299bd1058c1658b0ebb3b91ac"
const EXPECTED_FINAL_USE_CODES = [
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
const EXPECTED_CATEGORY_CODES = [
    "household_consumption",
    "private_fixed_investment",
    "inventory_change",
    "exports",
    "imports_accounting_offset",
    "government_consumption",
    "government_gross_investment",
]
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
const EXPECTED_VALUE_ADDED_CODES = ["V001", "V002", "V003"]
const EXPECTED_CLOSURE_CODES = ["Used", "Other"]
const EXPECTED_FORBIDDEN_RUNTIME_KEYS = [
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
const EXPECTED_ADAPTER_BLOCKERS = [
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
const EXPECTED_UPSTREAM_BLOCKERS = [
    "PRODUCER_PRICE_FINAL_USE_NOT_CONNECTED_TO_MODEL_STATE",
    "FINAL_USE_CATEGORY_LEDGER_NOT_CALIBRATION_ADAPTER",
    "F030_FLOW_NOT_MAPPED_TO_QUARTER_END_STOCK",
    "F050_OFFSET_NOT_SELECTED_AS_MODEL_IMPORT_BOUNDARY",
    "LEGACY_T013_T016_SCALAR_BRIDGE_REJECTED",
    "MULTI_ARCHIVE_RELEASE_IDENTITY_NOT_EXTERNALLY_BOUND",
    "COMMODITY_REDEFINITION_REDISTRIBUTION_NOT_ALLOCATED",
    "MARGIN_TRANSPORT_USE_CELL_ALLOCATION_NOT_PROVIDED",
    "PRODUCT_TAX_USE_CELL_ALLOCATION_NOT_PROVIDED",
    "PROPORTIONAL_OR_SCALAR_VALUATION_BRIDGE_NOT_APPROVED",
    "OBSERVED_TAX_AND_ZERO_TAX_VARIANTS_NOT_TRANSITION_TESTED",
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
const DEFAULT_FINAL_USE_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_final_use_envelope.toml")
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
Classification of one candidate output.

`runtime_emission_allowed` is false for every output in this report. A direct
producer-price candidate is source-admissible here, not runtime-admissible.
"""
struct AdapterOutputAssessment
    name::Symbol
    source_basis::Symbol
    status::Symbol
    runtime_key::Union{Nothing, String}
    runtime_emission_allowed::Bool
    reason::String
end

"""
BEA methodology and numeric evidence for a closure commodity.

Neither account is represented as an ordinary model commodity or producer
industry. Its intermediate and final uses therefore remain a mandatory
sidecar rather than being proportionally spread over the 68-sector core.
"""
struct ClosureAccountAssessment
    code::String
    methodology_role::Symbol
    ordinary_model_commodity::Bool
    ordinary_model_producer_industry::Bool
    runtime_state_mapping_status::Symbol
    methodology_pdf_pages::Vector{Int}
    intermediate_use_total::Float64
    final_use_total::Float64
    make_total::Float64
    commodity_output::Float64
end

"""
Industry-level proof that the closure rows cannot be omitted.

`core_industry_gaps` equals industry output less core intermediate inputs and
value added. `full_industry_gaps` also subtracts `Used`/`Other` inputs. The
former is an economically material omitted-state wedge; the latter is source
rounding.
"""
struct ClosureOmissionWitness
    core_industry_gaps::LabeledVector{IndustryBasis}
    full_industry_gaps::LabeledVector{IndustryBasis}
    core_signed_total::Float64
    core_absolute_total::Float64
    core_maximum_absolute::Float64
    core_maximum_absolute_code::String
    core_maximum_relative_to_output::Float64
    core_maximum_relative_code::String
    full_signed_total::Float64
    full_absolute_total::Float64
    full_maximum_absolute::Float64
    full_maximum_absolute_code::String
end

"""
Signed annual `F030` evidence.

This is a flow. It is not divided by four, clipped, relabeled as a stock, or
emitted as BeforeIT's opening `S_s`.
"""
struct InventoryFlowCandidate
    model_flow::LabeledVector{CommodityBasis}
    model_explicit::BitVector
    closure_flow::LabeledVector{CommodityBasis}
    closure_explicit::BitVector
    source_frequency::Symbol
    sign_policy::Symbol
    stock_emission_applied::Bool
    quarterly_conversion_applied::Bool
end

"""
Direct residential fixed-investment composition from `F02R`.

The candidate preserves the commodity vector but does not claim that an
annual expenditure flow identifies the model's quarter-end dwelling stock.
"""
struct ResidentialInvestmentCandidate
    model_flow::LabeledVector{CommodityBasis}
    model_explicit::BitVector
    closure_flow::LabeledVector{CommodityBasis}
    closure_explicit::BitVector
    dwelling_stock_mapping_applied::Bool
end

"""
Separate producer-table `F050` and imputed-import evidence.

The `F050` vectors are signed accounting offsets. The imputed-import matrices
allocate an independently compiled import control across uses. Neither is
selected as a nonnegative model import vector.
"""
struct ImportBoundaryEvidence
    producer_f050_model::LabeledVector{CommodityBasis}
    producer_f050_model_explicit::BitVector
    producer_f050_closure::LabeledVector{CommodityBasis}
    producer_f050_closure_explicit::BitVector
    imputed_intermediate_model::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    imputed_intermediate_closure::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    imputed_final_model::LabeledMatrix{CommodityBasis, FinalUseBasis}
    imputed_final_closure::LabeledMatrix{CommodityBasis, FinalUseBasis}
    imputed_f050_model::LabeledVector{CommodityBasis}
    imputed_f050_model_explicit::BitVector
    imputed_f050_closure::LabeledVector{CommodityBasis}
    imputed_f050_closure_explicit::BitVector
    import_role::Symbol
    sign_convention::Symbol
    model_import_vector_emitted::Bool
    reexports_emitted::Bool
    domestic_use_subtraction_applied::Bool
end

"""
Byte-pinned, non-materializing producer-price calibration adapter candidate.

The report accepts code-keyed annual source accounts while retaining every
unresolved runtime boundary. In particular, it carries the 68×68 producer
core and a separate `Used`/`Other` sidecar. It emits no FIGARO dictionary,
parameters, initial conditions, model state, or forecast origin.
"""
struct ProducerPriceAdapterCandidateReport
    year::Int
    model_codes::Vector{String}
    closure_codes::Vector{String}
    final_use_codes::Vector{String}
    category_codes::Vector{String}
    value_added_codes::Vector{String}
    source_commodity_mapping::Dict{String, String}
    source_industry_mapping::Dict{String, String}
    core_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    closure_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    core_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    closure_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    core_category_final_use::LabeledMatrix{
        CommodityBasis,
        FinalUseCategoryBasis,
    }
    closure_category_final_use::LabeledMatrix{
        CommodityBasis,
        FinalUseCategoryBasis,
    }
    residential_investment::ResidentialInvestmentCandidate
    inventory_flow::InventoryFlowCandidate
    import_evidence::ImportBoundaryEvidence
    producer_value_added::LabeledMatrix{
        AfterRedefinitionsValueAddedBasis,
        IndustryBasis,
    }
    producer_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    closure_producer_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    commodity_output::LabeledVector{CommodityBasis}
    commodity_output_explicit::BitVector
    closure_commodity_output::LabeledVector{CommodityBasis}
    closure_commodity_output_explicit::BitVector
    industry_output::LabeledVector{IndustryBasis}
    industry_output_explicit::BitVector
    observed_tax_variant::TaxControlVariant
    zero_tax_variant::TaxControlVariant
    closure_net_product_tax_control::LabeledVector{CommodityBasis}
    source_net_product_tax_total::Float64
    closure_assessments::Vector{ClosureAccountAssessment}
    closure_omission_witness::ClosureOmissionWitness
    output_assessments::Vector{AdapterOutputAssessment}
    residuals::Vector{ControlResidual}
    negative_core_intermediate_cells::Vector{NegativeCell}
    negative_closure_intermediate_cells::Vector{NegativeCell}
    negative_core_final_use_cells::Vector{NegativeCell}
    negative_closure_final_use_cells::Vector{NegativeCell}
    negative_core_category_cells::Vector{NegativeCell}
    negative_closure_category_cells::Vector{NegativeCell}
    negative_value_added_cells::Vector{NegativeCell}
    negative_import_intermediate_model_cells::Vector{NegativeCell}
    negative_import_intermediate_closure_cells::Vector{NegativeCell}
    negative_import_final_model_cells::Vector{NegativeCell}
    negative_import_final_closure_cells::Vector{NegativeCell}
    contract_sha256::String
    after_fixture_sha256::String
    after_manifest_sha256::String
    after_source_zip_sha256::String
    model_mapping_sha256::String
    sector_mapping_sha256::String
    valuation_contract_sha256::String
    final_use_contract_sha256::String
    supply_fixture_sha256::String
    supply_manifest_sha256::String
    table_262_source_sha256::String
    methodology_pdf_sha256::String
    methodology_receipt_sha256::String
    source_status::String
    methodology_status::String
    artifact_role::Symbol
    source_frequency::Symbol
    unit::Symbol
    transformation::Symbol
    price_basis::Symbol
    intermediate_policy::Symbol
    closure_policy::Symbol
    scrap_transform_policy::Symbol
    other_boundary_policy::Symbol
    inventory_policy::Symbol
    import_policy::Symbol
    tax_policy::Symbol
    value_added_policy::Symbol
    government_policy::Symbol
    residential_policy::Symbol
    negative_cell_policy::Symbol
    explicit_mask_policy::Symbol
    legacy_scalar_bridge_policy::Symbol
    emitted_runtime_keys::Vector{String}
    forbidden_runtime_keys::Vector{String}
    candidate_materialized::Bool
    runtime_calibration_admissible::Bool
    calibration_dictionary_write::Bool
    figaro_dictionary_write::Bool
    parameter_write::Bool
    initial_conditions_write::Bool
    model_state_write::Bool
    forecast_origin_admissible::Bool
    valuation_bridge_applied::Bool
    tax_allocation_applied::Bool
    tax_variant_selected::Bool
    closure_allocation_applied::Bool
    inventory_stock_mapping_applied::Bool
    import_boundary_selected::Bool
    government_boundary_selected::Bool
    residential_stock_mapping_applied::Bool
    annual_to_quarter_mapping_applied::Bool
    raking_applied::Bool
    balancing_applied::Bool
    clipping_applied::Bool
    accounting_gate_effect::Symbol
    promotion_blockers::Vector{String}
    promotion_ready::Bool
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

function negative_cell_vectors_match(lhs, rhs)
    length(lhs) == length(rhs) || return false
    return all(
        left.row_code == right.row_code &&
            left.column_code == right.column_code &&
            isequal(left.value, right.value)
            for (left, right) in zip(lhs, rhs)
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

function column_candidate(
        matrix::LabeledMatrix{R, C},
        code,
    ) where {
        R <: AxisBasis,
        C <: AxisBasis,
    }
    position = matrix.column_index[code]
    return (
        LabeledVector{R}(
            matrix.row_codes,
            matrix.values[:, position],
        ),
        BitVector(matrix.explicit[:, position]),
    )
end

function aggregate_categories(
        matrix::LabeledMatrix{CommodityBasis, FinalUseBasis},
    )
    values = zeros(length(matrix.row_codes), length(EXPECTED_CATEGORY_CODES))
    explicit = falses(size(values))
    for (category_position, category) in pairs(EXPECTED_CATEGORY_CODES)
        positions = [
            matrix.column_index[code]
                for code in EXPECTED_CATEGORY_COLUMNS[category]
        ]
        values[:, category_position] =
            vec(sum(matrix.values[:, positions]; dims = 2))
        explicit[:, category_position] =
            vec(any(matrix.explicit[:, positions]; dims = 2))
    end
    return LabeledMatrix{CommodityBasis, FinalUseCategoryBasis}(
        matrix.row_codes,
        EXPECTED_CATEGORY_CODES,
        values,
        explicit,
    )
end

function validate_contract(
        contract_path,
        after_directory,
        supply_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
        final_use_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    contract_bytes = read(contract_path)
    contract_sha256 = sha256_hex(contract_bytes)
    contract_sha256 == APPROVED_CONTRACT_SHA256 ||
        throw(ArgumentError("producer-price adapter contract SHA-256 changed"))
    contract = TOML.parse(String(contract_bytes))
    get(contract, "schema_version", "") == CONTRACT_SCHEMA ||
        throw(ArgumentError("unsupported producer-price adapter contract"))
    get(contract, "classification", "") == EXPECTED_STATUS ||
        throw(ArgumentError("producer-price adapter status changed"))
    get(contract, "artifact_role", "") == EXPECTED_ARTIFACT_ROLE ||
        throw(ArgumentError("producer-price adapter artifact role changed"))
    get(contract, "promotion_status", "") == EXPECTED_PROMOTION_STATUS ||
        throw(ArgumentError("producer-price adapter promotion status changed"))
    get(contract, "source_year", 0) == 2024 ||
        throw(ArgumentError("producer-price adapter source year changed"))
    get(contract, "source_frequency", "") == "annual" ||
        throw(ArgumentError("producer-price adapter frequency changed"))
    get(contract, "unit", "") == "millions USD" ||
        throw(ArgumentError("producer-price adapter unit changed"))
    get(contract, "price_basis", "") == "producers prices" ||
        throw(ArgumentError("producer-price adapter price basis changed"))
    get(contract, "model_commodity_count", 0) == 68 ||
        throw(ArgumentError("model commodity count changed"))
    get(contract, "model_industry_count", 0) == 68 ||
        throw(ArgumentError("model industry count changed"))
    String.(get(contract, "closure_codes", String[])) ==
        EXPECTED_CLOSURE_CODES ||
        throw(ArgumentError("closure codes changed"))
    get(contract, "candidate_materialized", false) === true ||
        throw(ArgumentError("adapter candidate was not materialized"))
    get(contract, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("adapter candidate cannot affect accounting gates"))

    for flag in (
            "runtime_calibration_admissible",
            "calibration_dictionary_write",
            "figaro_dictionary_write",
            "parameter_write",
            "initial_conditions_write",
            "model_state_write",
            "forecast_origin_admissible",
            "valuation_bridge_applied",
            "tax_allocation_applied",
            "tax_variant_selected",
            "closure_allocation_applied",
            "inventory_stock_mapping_applied",
            "import_boundary_selected",
            "government_boundary_selected",
            "residential_stock_mapping_applied",
            "annual_to_quarter_mapping_applied",
            "raking_applied",
            "balancing_applied",
            "clipping_applied",
        )
        get(contract, flag, true) === false ||
            throw(ArgumentError("producer-price adapter enabled $flag"))
    end

    expected_policies = Dict(
        "intermediate_policy" =>
            "DIRECT_PRODUCER_PRICE_CORE_WITH_SEPARATE_CLOSURE_NO_RAKE",
        "closure_policy" => "USED_OTHER_SEPARATE_UNALLOCATED",
        "scrap_transform_policy" =>
            "BEA_NONSCRAP_TRANSFORMATION_REQUIRED_NOT_APPLIED",
        "other_boundary_policy" =>
            "OTHER_NONCOMPARABLE_IMPORTS_AND_ROW_ADJUSTMENT_BOUNDARY_UNSELECTED",
        "inventory_policy" =>
            "F030_SIGNED_ANNUAL_FLOW_NO_STOCK_EMISSION",
        "import_policy" =>
            "F050_SIGNED_OFFSET_AND_IMPUTED_IMPORT_EVIDENCE_NO_MODEL_IMPORT_VECTOR",
        "tax_policy" =>
            "OBSERVED_AND_ZERO_CONTROLS_UNSELECTED_NO_RUNTIME_TAX_EMISSION",
        "value_added_policy" =>
            "V001_V002_V003_RETAINED_WITHOUT_RUNTIME_TAX_SPLIT",
        "government_policy" =>
            "CONSUMPTION_AND_GROSS_INVESTMENT_RETAINED_SEPARATELY",
        "residential_policy" =>
            "F02R_RETAINED_WITHOUT_DWELLING_STOCK_MAPPING",
        "negative_cell_policy" => "PRESERVE",
        "explicit_mask_policy" =>
            "PRESERVE_NUMERIC_ZERO_VS_SELECTED_ZERO",
        "legacy_scalar_bridge_policy" =>
            "OMITTED_REJECTED_NOT_CELL_IDENTIFIED",
    )
    for (field, expected) in expected_policies
        get(contract, field, "") == expected ||
            throw(ArgumentError("producer-price adapter $field changed"))
    end
    String.(get(contract, "forbidden_runtime_keys", String[])) ==
        EXPECTED_FORBIDDEN_RUNTIME_KEYS ||
        throw(ArgumentError("forbidden runtime keys changed"))

    closure_specs = get(contract, "closure_account", Any[])
    length(closure_specs) == 2 ||
        throw(ArgumentError("closure-account specification count changed"))
    expected_closure_specs = (
        (
            "Used",
            "SCRAP_USED_AND_SECONDHAND_GOODS_COMMODITY_ONLY_BYPRODUCT_AND_FINAL_USE_SALES_ACCOUNT",
            [98, 214, 223, 224, 225],
        ),
        (
            "Other",
            "NONCOMPARABLE_IMPORTS_AND_REST_OF_WORLD_ADJUSTMENT_COMPOSITE",
            [123, 124],
        ),
    )
    for (spec, expected) in zip(closure_specs, expected_closure_specs)
        get(spec, "code", "") == expected[1] ||
            throw(ArgumentError("closure-account order changed"))
        get(spec, "methodology_role", "") == expected[2] ||
            throw(ArgumentError("closure-account methodology changed"))
        get(spec, "ordinary_model_commodity", true) === false ||
            throw(ArgumentError("closure account became a model commodity"))
        get(spec, "ordinary_model_producer_industry", true) === false ||
            throw(ArgumentError("closure account became a producer industry"))
        get(spec, "runtime_state_mapping_status", "") == "UNRESOLVED" ||
            throw(ArgumentError("closure runtime mapping was overclaimed"))
        Int.(get(spec, "methodology_pdf_pages", Int[])) == expected[3] ||
            throw(ArgumentError("closure methodology page set changed"))
    end

    after_cells_path = joinpath(after_directory, "cells.csv")
    after_manifest_path = joinpath(after_directory, "manifest.toml")
    supply_cells_path = joinpath(supply_directory, "cells.csv")
    supply_manifest_path = joinpath(supply_directory, "manifest.toml")
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
        "final_use_envelope_contract_sha256" => (
            sha256_hex(read(final_use_contract_path)),
            APPROVED_FINAL_USE_CONTRACT_SHA256,
        ),
        "supply_fixture_sha256" => (
            sha256_hex(read(supply_cells_path)),
            APPROVED_SUPPLY_FIXTURE_SHA256,
        ),
        "supply_manifest_sha256" => (
            sha256_hex(read(supply_manifest_path)),
            APPROVED_SUPPLY_MANIFEST_SHA256,
        ),
        "methodology_pdf_sha256" => (
            sha256_hex(read(methodology_pdf_path)),
            APPROVED_METHODOLOGY_PDF_SHA256,
        ),
        "methodology_receipt_sha256" => (
            sha256_hex(read(methodology_receipt_path)),
            APPROVED_METHODOLOGY_RECEIPT_SHA256,
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
    get(contract, "after_redefinitions_source_zip_sha256", "") ==
        APPROVED_AFTER_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("contract source ZIP identity changed"))
    get(after_manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("after-redefinitions source status changed"))

    supply_manifest = TOML.parsefile(supply_manifest_path)
    get(supply_manifest, "fixture_sha256", "") ==
        APPROVED_SUPPLY_FIXTURE_SHA256 ||
        throw(ArgumentError("supply fixture manifest identity changed"))
    sources = get(supply_manifest, "sources", Any[])
    table_262 = filter(
        source -> get(source, "table_id", "") == "262",
        sources,
    )
    length(table_262) == 1 ||
        throw(ArgumentError("Table 262 source record changed"))
    get(only(table_262), "source_sha256", "") ==
        APPROVED_TABLE_262_SOURCE_SHA256 ||
        throw(ArgumentError("Table 262 source identity changed"))
    get(contract, "table_262_source_sha256", "") ==
        APPROVED_TABLE_262_SOURCE_SHA256 ||
        throw(ArgumentError("contract Table 262 identity changed"))

    methodology = TOML.parsefile(methodology_receipt_path)
    get(methodology, "schema_version", "") ==
        "beforeit-bea-io-methodology-receipt.v1" ||
        throw(ArgumentError("methodology receipt schema changed"))
    get(methodology, "source_url", "") ==
        "https://www.bea.gov/sites/default/files/papers/WP2006-6.pdf" ||
        throw(ArgumentError("methodology source URL changed"))
    get(methodology, "title", "") ==
        "Concepts and Methods of the U.S. Input-Output Accounts" ||
        throw(ArgumentError("methodology title changed"))
    get(methodology, "source_sha256", "") ==
        APPROVED_METHODOLOGY_PDF_SHA256 ||
        throw(ArgumentError("methodology receipt PDF identity changed"))
    get(methodology, "byte_count", 0) == filesize(methodology_pdf_path) ||
        throw(ArgumentError("methodology receipt byte count changed"))
    get(methodology, "page_count", 0) == 266 ||
        throw(ArgumentError("methodology PDF page count changed"))
    Int.(get(methodology, "relevant_pdf_pages", Int[])) ==
        [98, 123, 124, 214, 223, 224, 225] ||
        throw(ArgumentError("methodology relevant-page set changed"))
    get(methodology, "status", "") ==
        "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA" ||
        throw(ArgumentError("methodology status changed"))
    get(methodology, "artifact_role", "") ==
        "SEMANTIC_METHOD_SOURCE_ONLY" ||
        throw(ArgumentError("methodology artifact role changed"))
    get(methodology, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("methodology source cannot admit an origin"))
    get(methodology, "model_state_write", true) === false ||
        throw(ArgumentError("methodology source cannot write model state"))
    get(methodology, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("methodology source cannot affect accounting gates"))

    return (;
        contract,
        contract_sha256,
        after_manifest,
        methodology,
    )
end

function expected_output_assessments()
    direct_reason =
        "Code-keyed annual producer-price source retained without runtime emission."
    unresolved_reason =
        "Signed or composite evidence retained; runtime semantics remain unselected."
    control_reason =
        "Observed or counterfactual control retained without use-cell allocation."
    return AdapterOutputAssessment[
        AdapterOutputAssessment(
            :core_intermediate_use,
            :commodity_by_industry,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :closure_intermediate_use,
            :closure_commodity_by_industry,
            :required_unmaterialized_sidecar,
            nothing,
            false,
            "Used/Other inputs are required by industry identities and have no selected runtime treatment.",
        ),
        AdapterOutputAssessment(
            :household_consumption,
            :commodity_final_use,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :private_fixed_investment,
            :commodity_final_use,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :residential_fixed_investment_f02r,
            :commodity_final_use,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :inventory_change_f030,
            :commodity_final_use,
            :signed_unresolved_diagnostic,
            nothing,
            false,
            unresolved_reason,
        ),
        AdapterOutputAssessment(
            :exports_f040,
            :commodity_final_use,
            :direct_producer_price_candidate,
            nothing,
            false,
            "Direct source vector retained; domestic-export/reexport separation remains a promotion blocker.",
        ),
        AdapterOutputAssessment(
            :imports_offset_f050,
            :commodity_final_use,
            :signed_unresolved_diagnostic,
            nothing,
            false,
            unresolved_reason,
        ),
        AdapterOutputAssessment(
            :government_consumption,
            :commodity_final_use,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :government_gross_investment,
            :commodity_final_use,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :value_added_v001,
            :value_added_by_industry,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :value_added_v002,
            :value_added_by_industry,
            :signed_unresolved_diagnostic,
            nothing,
            false,
            unresolved_reason,
        ),
        AdapterOutputAssessment(
            :value_added_v003,
            :value_added_by_industry,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :producer_make,
            :industry_by_commodity,
            :direct_producer_price_candidate,
            nothing,
            false,
            "Distinct industry and commodity axes retained; runtime sector-basis approximation remains unselected.",
        ),
        AdapterOutputAssessment(
            :commodity_output,
            :commodity,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :industry_output,
            :industry,
            :direct_producer_price_candidate,
            nothing,
            false,
            direct_reason,
        ),
        AdapterOutputAssessment(
            :imputed_import_allocations,
            :commodity_by_use,
            :signed_unresolved_diagnostic,
            nothing,
            false,
            unresolved_reason,
        ),
        AdapterOutputAssessment(
            :observed_t015,
            :commodity_control,
            :control_only,
            nothing,
            false,
            control_reason,
        ),
        AdapterOutputAssessment(
            :explicit_zero_product_tax,
            :commodity_control,
            :control_only,
            nothing,
            false,
            control_reason,
        ),
    ]
end

function build_closure_omission_witness(
        core_intermediate,
        closure_intermediate,
        value_added,
        industry_output,
    )
    core_gaps =
        industry_output.values .-
        vec(sum(core_intermediate.values; dims = 1)) .-
        vec(sum(value_added.values; dims = 1))
    full_gaps =
        core_gaps .-
        vec(sum(closure_intermediate.values; dims = 1))
    core_maximum_position = argmax(abs.(core_gaps))
    core_relative_gaps =
        abs.(core_gaps) ./ industry_output.values
    core_relative_position = argmax(core_relative_gaps)
    full_maximum_position = argmax(abs.(full_gaps))
    return ClosureOmissionWitness(
        LabeledVector{IndustryBasis}(industry_output.codes, core_gaps),
        LabeledVector{IndustryBasis}(industry_output.codes, full_gaps),
        sum(core_gaps),
        sum(abs.(core_gaps)),
        abs(core_gaps[core_maximum_position]),
        industry_output.codes[core_maximum_position],
        core_relative_gaps[core_relative_position],
        industry_output.codes[core_relative_position],
        sum(full_gaps),
        sum(abs.(full_gaps)),
        abs(full_gaps[full_maximum_position]),
        industry_output.codes[full_maximum_position],
    )
end

function build_residuals(
        core_intermediate,
        closure_intermediate,
        residential,
        inventory,
        imports,
        value_added,
        industry_output,
        source_industry_mapping,
        observed_tax,
        closure_tax,
        source_tax_total,
        closure_assessments,
    )
    residuals = ControlResidual[]
    add_residual!(
        residuals,
        :producer_price_core_total,
        "U_CORE",
        "sum core producer-price intermediate use",
        sum(core_intermediate.values),
        21_165_843.0,
        0.0,
    )
    add_residual!(
        residuals,
        :closure_intermediate_total,
        "U_USED_OTHER",
        "sum separate Used/Other intermediate-use sidecar",
        sum(closure_intermediate.values),
        272_726.0,
        0.0,
    )
    for (position, code) in pairs(industry_output.codes)
        lhs =
            sum(core_intermediate.values[:, position]) +
            sum(closure_intermediate.values[:, position]) +
            sum(value_added.values[:, position])
        source_count = count(==(code), values(source_industry_mapping))
        add_residual!(
            residuals,
            :industry_identity,
            code,
            "core inputs + closure inputs + V001/V002/V003 = industry output",
            lhs,
            industry_output.values[position],
            38.5 * source_count,
        )
    end
    core_gap =
        sum(industry_output.values) -
        sum(core_intermediate.values) -
        sum(value_added.values)
    full_gap = core_gap - sum(closure_intermediate.values)
    add_residual!(
        residuals,
        :identity_gap_witness,
        "CORE_ONLY",
        "industry output - core inputs - value added exposes omitted closure",
        core_gap,
        272_697.0,
        0.0,
    )
    add_residual!(
        residuals,
        :identity_gap_witness,
        "WITH_CLOSURE",
        "industry output - core inputs - closure inputs - value added is rounding only",
        full_gap,
        -29.0,
        0.0,
    )
    for (code, value, expected) in (
            ("F02R_CORE", sum(residential.model_flow.values), 1_184_020.0),
            (
                "F02R_CLOSURE",
                sum(residential.closure_flow.values),
                -1_182.0,
            ),
        )
        add_residual!(
            residuals,
            :residential_flow_total,
            code,
            "direct annual residential fixed-investment flow retained",
            value,
            expected,
            0.0,
        )
    end
    for (code, value, expected) in (
            ("F030_CORE", sum(inventory.model_flow.values), 44_095.0),
            (
                "F030_CLOSURE",
                sum(inventory.closure_flow.values),
                9_450.0,
            ),
        )
        add_residual!(
            residuals,
            :inventory_flow_total,
            code,
            "signed annual inventory-change flow retained",
            value,
            expected,
            0.0,
        )
    end
    for (code, value, expected) in (
            (
                "F050_CORE",
                sum(imports.producer_f050_model.values),
                -3_294_892.0,
            ),
            (
                "F050_CLOSURE",
                sum(imports.producer_f050_closure.values),
                -386_649.0,
            ),
        )
        add_residual!(
            residuals,
            :import_offset_total,
            code,
            "signed producer-table imports accounting offset retained",
            value,
            expected,
            0.0,
        )
    end
    for (code, expected) in (
            ("V001", 15_049_121.0),
            ("V002", 1_860_445.0),
            ("V003", 12_388_448.0),
        )
        position = value_added.row_index[code]
        add_residual!(
            residuals,
            :value_added_total,
            code,
            "signed producer-price value-added component retained",
            sum(value_added.values[position, :]),
            expected,
            0.0,
        )
    end
    for (code, value, expected) in (
            (
                "T015_CORE",
                sum(observed_tax.commodity_net_product_tax.values),
                986_971.0,
            ),
            ("T015_CLOSURE", sum(closure_tax.values), 23_351.0),
            ("T015_SOURCE", source_tax_total, 1_010_322.0),
        )
        add_residual!(
            residuals,
            :tax_control_total,
            code,
            "unselected net-product-tax control retained",
            value,
            expected,
            0.0,
        )
    end
    for assessment in closure_assessments
        expected_intermediate =
            assessment.code == "Used" ? 100_094.0 : 172_632.0
        expected_final =
            assessment.code == "Used" ? -86_542.0 : -166_441.0
        add_residual!(
            residuals,
            :closure_account_total,
            "$(assessment.code)_INTERMEDIATE",
            "closure-account intermediate use retained",
            assessment.intermediate_use_total,
            expected_intermediate,
            0.0,
        )
        add_residual!(
            residuals,
            :closure_account_total,
            "$(assessment.code)_FINAL",
            "closure-account final use retained",
            assessment.final_use_total,
            expected_final,
            0.0,
        )
    end
    for (code, value, expected) in (
            (
                "IMPUTED_INTERMEDIATE_CORE",
                sum(imports.imputed_intermediate_model.values),
                1_776_783.0,
            ),
            (
                "IMPUTED_FINAL_CORE",
                sum(imports.imputed_final_model.values),
                -1_776_831.0,
            ),
            (
                "IMPUTED_INTERMEDIATE_CLOSURE",
                sum(imports.imputed_intermediate_closure.values),
                181_714.0,
            ),
            (
                "IMPUTED_FINAL_CLOSURE",
                sum(imports.imputed_final_closure.values),
                -181_710.0,
            ),
        )
        add_residual!(
            residuals,
            :imputed_import_total,
            code,
            "separate imputed-import allocation evidence retained",
            value,
            expected,
            0.0,
        )
    end
    return residuals
end

function expected_residual_family_counts()
    return Dict(
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
end

function residual_family_counts(residuals)
    return Dict(
        family => count(residual -> residual.family == family, residuals)
            for family in unique(residual.family for residual in residuals)
    )
end

function producer_price_adapter_candidate_internal_controls_pass(
        report::ProducerPriceAdapterCandidateReport,
    )
    report.year == 2024 || return false
    expected_residuals = build_residuals(
        report.core_intermediate_use,
        report.closure_intermediate_use,
        report.residential_investment,
        report.inventory_flow,
        report.import_evidence,
        report.producer_value_added,
        report.industry_output,
        report.source_industry_mapping,
        report.observed_tax_variant,
        report.closure_net_product_tax_control,
        report.source_net_product_tax_total,
        report.closure_assessments,
    )
    structurally_equal(report.residuals, expected_residuals) || return false
    expected_witness = build_closure_omission_witness(
        report.core_intermediate_use,
        report.closure_intermediate_use,
        report.producer_value_added,
        report.industry_output,
    )
    structurally_equal(
        report.closure_omission_witness,
        expected_witness,
    ) || return false
    witness = report.closure_omission_witness
    witness.core_signed_total == 272_697.0 || return false
    witness.core_absolute_total == 272_703.0 || return false
    witness.core_maximum_absolute == 57_333.0 || return false
    witness.core_maximum_absolute_code == "81" || return false
    witness.core_maximum_relative_to_output ==
        0.09513620690230688 || return false
    witness.core_maximum_relative_code == "331" || return false
    witness.full_signed_total == -29.0 || return false
    witness.full_absolute_total == 127.0 || return false
    witness.full_maximum_absolute == 6.0 || return false
    witness.full_maximum_absolute_code == "326" || return false
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
    report.final_use_contract_sha256 ==
        APPROVED_FINAL_USE_CONTRACT_SHA256 || return false
    report.supply_fixture_sha256 == APPROVED_SUPPLY_FIXTURE_SHA256 ||
        return false
    report.supply_manifest_sha256 == APPROVED_SUPPLY_MANIFEST_SHA256 ||
        return false
    report.table_262_source_sha256 ==
        APPROVED_TABLE_262_SOURCE_SHA256 || return false
    report.methodology_pdf_sha256 == APPROVED_METHODOLOGY_PDF_SHA256 ||
        return false
    report.methodology_receipt_sha256 ==
        APPROVED_METHODOLOGY_RECEIPT_SHA256 || return false
    report.source_status == EXPECTED_STATUS || return false
    report.methodology_status ==
        "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA" || return false
    report.artifact_role == :typed_calibration_adapter_candidate_only ||
        return false
    report.source_frequency == :annual || return false
    report.unit == :millions_usd || return false
    report.transformation ==
        :code_keyed_producer_price_candidate_with_typed_closure_sidecar ||
        return false
    report.price_basis == :producers_prices || return false
    report.intermediate_policy ==
        :direct_producer_price_core_with_separate_closure_no_rake ||
        return false
    report.closure_policy == :used_other_separate_unallocated ||
        return false
    report.scrap_transform_policy ==
        :bea_nonscrap_transformation_required_not_applied || return false
    report.other_boundary_policy ==
        :other_noncomparable_imports_and_row_adjustment_boundary_unselected ||
        return false
    report.inventory_policy ==
        :f030_signed_annual_flow_no_stock_emission || return false
    report.import_policy ==
        :f050_signed_offset_and_imputed_import_evidence_no_model_import_vector ||
        return false
    report.tax_policy ==
        :observed_and_zero_controls_unselected_no_runtime_tax_emission ||
        return false
    report.value_added_policy ==
        :v001_v002_v003_retained_without_runtime_tax_split ||
        return false
    report.government_policy ==
        :consumption_and_gross_investment_retained_separately ||
        return false
    report.residential_policy ==
        :f02r_retained_without_dwelling_stock_mapping || return false
    report.negative_cell_policy == :preserve || return false
    report.explicit_mask_policy ==
        :preserve_numeric_zero_vs_selected_zero || return false
    report.legacy_scalar_bridge_policy ==
        :omitted_rejected_not_cell_identified || return false
    isempty(report.emitted_runtime_keys) || return false
    report.forbidden_runtime_keys == EXPECTED_FORBIDDEN_RUNTIME_KEYS ||
        return false
    isempty(
        intersect(report.emitted_runtime_keys, report.forbidden_runtime_keys),
    ) || return false
    report.candidate_materialized || return false
    any(
        (
            report.runtime_calibration_admissible,
            report.calibration_dictionary_write,
            report.figaro_dictionary_write,
            report.parameter_write,
            report.initial_conditions_write,
            report.model_state_write,
            report.forecast_origin_admissible,
            report.valuation_bridge_applied,
            report.tax_allocation_applied,
            report.tax_variant_selected,
            report.closure_allocation_applied,
            report.inventory_stock_mapping_applied,
            report.import_boundary_selected,
            report.government_boundary_selected,
            report.residential_stock_mapping_applied,
            report.annual_to_quarter_mapping_applied,
            report.raking_applied,
            report.balancing_applied,
            report.clipping_applied,
            report.promotion_ready,
        ),
    ) && return false
    report.accounting_gate_effect == :none || return false
    report.promotion_blockers ==
        vcat(EXPECTED_ADAPTER_BLOCKERS, EXPECTED_UPSTREAM_BLOCKERS) ||
        return false

    try
        model_codes = report.model_codes
        closure_codes = report.closure_codes
        model_codes == report.industry_output.codes || return false
        length(model_codes) == 68 || return false
        length(unique(model_codes)) == 68 || return false
        closure_codes == EXPECTED_CLOSURE_CODES || return false
        report.final_use_codes == EXPECTED_FINAL_USE_CODES || return false
        report.category_codes == EXPECTED_CATEGORY_CODES || return false
        report.value_added_codes == EXPECTED_VALUE_ADDED_CODES ||
            return false
        length(report.source_commodity_mapping) == 73 || return false
        length(report.source_industry_mapping) == 71 || return false

        report.core_intermediate_use.row_codes == model_codes ||
            return false
        report.core_intermediate_use.column_codes == model_codes ||
            return false
        report.closure_intermediate_use.row_codes == closure_codes ||
            return false
        report.closure_intermediate_use.column_codes == model_codes ||
            return false
        report.core_final_use.row_codes == model_codes || return false
        report.core_final_use.column_codes == EXPECTED_FINAL_USE_CODES ||
            return false
        report.closure_final_use.row_codes == closure_codes || return false
        report.closure_final_use.column_codes == EXPECTED_FINAL_USE_CODES ||
            return false
        report.core_category_final_use.row_codes == model_codes ||
            return false
        report.core_category_final_use.column_codes ==
            EXPECTED_CATEGORY_CODES || return false
        report.closure_category_final_use.row_codes == closure_codes ||
            return false
        report.closure_category_final_use.column_codes ==
            EXPECTED_CATEGORY_CODES || return false
        structurally_equal(
            report.core_category_final_use,
            aggregate_categories(report.core_final_use),
        ) || return false
        structurally_equal(
            report.closure_category_final_use,
            aggregate_categories(report.closure_final_use),
        ) || return false
        report.producer_value_added.row_codes ==
            EXPECTED_VALUE_ADDED_CODES || return false
        report.producer_value_added.column_codes == model_codes ||
            return false
        report.producer_make.row_codes == model_codes || return false
        report.producer_make.column_codes == model_codes || return false
        report.closure_producer_make.row_codes == model_codes ||
            return false
        report.closure_producer_make.column_codes == closure_codes ||
            return false
        report.commodity_output.codes == model_codes || return false
        report.closure_commodity_output.codes == closure_codes ||
            return false
        report.industry_output.codes == model_codes || return false
        length(report.commodity_output_explicit) == 68 || return false
        length(report.closure_commodity_output_explicit) == 2 ||
            return false
        length(report.industry_output_explicit) == 68 || return false

        residential_model, residential_model_explicit =
            column_candidate(report.core_final_use, "F02R")
        residential_closure, residential_closure_explicit =
            column_candidate(report.closure_final_use, "F02R")
        structurally_equal(
            report.residential_investment.model_flow,
            residential_model,
        ) || return false
        report.residential_investment.model_explicit ==
            residential_model_explicit || return false
        structurally_equal(
            report.residential_investment.closure_flow,
            residential_closure,
        ) || return false
        report.residential_investment.closure_explicit ==
            residential_closure_explicit || return false
        report.residential_investment.dwelling_stock_mapping_applied &&
            return false

        inventory_model, inventory_model_explicit =
            column_candidate(report.core_final_use, "F030")
        inventory_closure, inventory_closure_explicit =
            column_candidate(report.closure_final_use, "F030")
        structurally_equal(
            report.inventory_flow.model_flow,
            inventory_model,
        ) || return false
        report.inventory_flow.model_explicit == inventory_model_explicit ||
            return false
        structurally_equal(
            report.inventory_flow.closure_flow,
            inventory_closure,
        ) || return false
        report.inventory_flow.closure_explicit ==
            inventory_closure_explicit || return false
        report.inventory_flow.source_frequency == :annual || return false
        report.inventory_flow.sign_policy == :preserve || return false
        report.inventory_flow.stock_emission_applied && return false
        report.inventory_flow.quarterly_conversion_applied && return false

        f050_model, f050_model_explicit =
            column_candidate(report.core_final_use, "F050")
        f050_closure, f050_closure_explicit =
            column_candidate(report.closure_final_use, "F050")
        imports = report.import_evidence
        structurally_equal(imports.producer_f050_model, f050_model) ||
            return false
        imports.producer_f050_model_explicit == f050_model_explicit ||
            return false
        structurally_equal(imports.producer_f050_closure, f050_closure) ||
            return false
        imports.producer_f050_closure_explicit == f050_closure_explicit ||
            return false
        imports.imputed_intermediate_model.row_codes == model_codes ||
            return false
        imports.imputed_intermediate_model.column_codes == model_codes ||
            return false
        imports.imputed_intermediate_closure.row_codes == closure_codes ||
            return false
        imports.imputed_intermediate_closure.column_codes == model_codes ||
            return false
        imports.imputed_final_model.row_codes == model_codes || return false
        imports.imputed_final_model.column_codes == EXPECTED_FINAL_USE_CODES ||
            return false
        imports.imputed_final_closure.row_codes == closure_codes ||
            return false
        imports.imputed_final_closure.column_codes ==
            EXPECTED_FINAL_USE_CODES || return false
        imports.imputed_f050_model.codes == model_codes || return false
        imports.imputed_f050_closure.codes == closure_codes || return false
        expected_imputed_f050_model,
            expected_imputed_f050_model_explicit =
            column_candidate(imports.imputed_final_model, "F050")
        expected_imputed_f050_closure,
            expected_imputed_f050_closure_explicit =
            column_candidate(imports.imputed_final_closure, "F050")
        structurally_equal(
            imports.imputed_f050_model,
            expected_imputed_f050_model,
        ) || return false
        imports.imputed_f050_model_explicit ==
            expected_imputed_f050_model_explicit || return false
        structurally_equal(
            imports.imputed_f050_closure,
            expected_imputed_f050_closure,
        ) || return false
        imports.imputed_f050_closure_explicit ==
            expected_imputed_f050_closure_explicit || return false
        imports.import_role == :separate_bea_imputed_import_allocation ||
            return false
        imports.sign_convention ==
            :positive_allocated_uses_plus_signed_f050_accounting_offset ||
            return false
        imports.model_import_vector_emitted && return false
        imports.reexports_emitted && return false
        imports.domestic_use_subtraction_applied && return false

        observed = report.observed_tax_variant
        zero = report.zero_tax_variant
        observed.name == :observed || return false
        observed.commodity_net_product_tax.codes == model_codes ||
            return false
        observed.use_cell_allocation == :none || return false
        zero.name == :explicit_zero || return false
        zero.commodity_net_product_tax.codes == model_codes || return false
        zero.use_cell_allocation == :none || return false
        all(iszero, zero.commodity_net_product_tax.values) || return false
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
        report.closure_net_product_tax_control.codes == closure_codes ||
            return false
        sum(observed.commodity_net_product_tax.values) +
            sum(report.closure_net_product_tax_control.values) ==
            report.source_net_product_tax_total || return false

        structurally_equal(
            report.output_assessments,
            expected_output_assessments(),
        ) || return false
        length(report.closure_assessments) == 2 || return false
        expected_closure_roles = (
            :scrap_used_and_secondhand_goods_commodity_only_byproduct_and_final_use_sales_account,
            :noncomparable_imports_and_rest_of_world_adjustment_composite,
        )
        expected_methodology_pages = ([98, 214, 223, 224, 225], [123, 124])
        for (position, assessment) in pairs(report.closure_assessments)
            code = closure_codes[position]
            assessment.code == code || return false
            assessment.methodology_role == expected_closure_roles[position] ||
                return false
            assessment.ordinary_model_commodity && return false
            assessment.ordinary_model_producer_industry && return false
            assessment.runtime_state_mapping_status == :unresolved ||
                return false
            assessment.methodology_pdf_pages ==
                expected_methodology_pages[position] || return false
            closure_row =
                report.closure_intermediate_use.row_index[code]
            closure_final_row = report.closure_final_use.row_index[code]
            closure_make_column =
                report.closure_producer_make.column_index[code]
            isequal(
                assessment.intermediate_use_total,
                sum(report.closure_intermediate_use.values[closure_row, :]),
            ) || return false
            isequal(
                assessment.final_use_total,
                sum(report.closure_final_use.values[closure_final_row, :]),
            ) || return false
            isequal(
                assessment.make_total,
                sum(
                    report.closure_producer_make.values[
                        :,
                        closure_make_column,
                    ],
                ),
            ) || return false
            isequal(
                assessment.commodity_output,
                report.closure_commodity_output[code],
            ) || return false
        end

        negative_cell_vectors_match(
            report.negative_core_intermediate_cells,
            negative_cells(report.core_intermediate_use),
        ) || return false
        negative_cell_vectors_match(
            report.negative_closure_intermediate_cells,
            negative_cells(report.closure_intermediate_use),
        ) || return false
        negative_cell_vectors_match(
            report.negative_core_final_use_cells,
            negative_cells(report.core_final_use),
        ) || return false
        negative_cell_vectors_match(
            report.negative_closure_final_use_cells,
            negative_cells(report.closure_final_use),
        ) || return false
        negative_cell_vectors_match(
            report.negative_core_category_cells,
            negative_cells(report.core_category_final_use),
        ) || return false
        negative_cell_vectors_match(
            report.negative_closure_category_cells,
            negative_cells(report.closure_category_final_use),
        ) || return false
        negative_cell_vectors_match(
            report.negative_value_added_cells,
            negative_cells(report.producer_value_added),
        ) || return false
        negative_cell_vectors_match(
            report.negative_import_intermediate_model_cells,
            negative_cells(imports.imputed_intermediate_model),
        ) || return false
        negative_cell_vectors_match(
            report.negative_import_intermediate_closure_cells,
            negative_cells(imports.imputed_intermediate_closure),
        ) || return false
        negative_cell_vectors_match(
            report.negative_import_final_model_cells,
            negative_cells(imports.imputed_final_model),
        ) || return false
        negative_cell_vectors_match(
            report.negative_import_final_closure_cells,
            negative_cells(imports.imputed_final_closure),
        ) || return false

        isempty(report.negative_core_intermediate_cells) || return false
        length(report.negative_closure_intermediate_cells) == 5 ||
            return false
        length(report.negative_core_final_use_cells) == 52 || return false
        length(report.negative_closure_final_use_cells) == 9 ||
            return false
        length(report.negative_core_category_cells) == 52 || return false
        length(report.negative_closure_category_cells) == 5 || return false
        length(report.negative_value_added_cells) == 4 || return false
        count(
            cell -> cell.column_code == "F030",
            report.negative_core_final_use_cells,
        ) == 7 || return false
        count(
            cell -> cell.column_code == "F050",
            report.negative_core_final_use_cells,
        ) == 45 || return false
        Set(
            cell.column_code for cell in report.negative_core_category_cells
        ) == Set(["inventory_change", "imports_accounting_offset"]) ||
            return false
    catch
        return false
    end
    return true
end

function _build_producer_price_adapter_candidate(
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
        final_use_contract_path = DEFAULT_FINAL_USE_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    validated = validate_contract(
        contract_path,
        after_directory,
        supply_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
        final_use_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    fixture = load_after_redefinitions_fixture(after_directory)
    model_core = build_model_core_aggregation(
        fixture,
        model_mapping_path;
        sector_mapping_path,
    )
    final_use = build_final_use_envelope(
        final_use_contract_path;
        after_directory,
        supply_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
    )

    for (left, right, label) in (
            (
                model_core.producer_intermediate_use,
                final_use.model_intermediate_use,
                "core intermediate use",
            ),
            (
                model_core.closure.producer_intermediate_use,
                final_use.closure_intermediate_use,
                "closure intermediate use",
            ),
            (
                model_core.producer_final_use,
                final_use.model_final_use,
                "core final use",
            ),
            (
                model_core.closure.producer_final_use,
                final_use.closure_final_use,
                "closure final use",
            ),
            (
                model_core.producer_value_added,
                final_use.producer_value_added,
                "producer value added",
            ),
            (
                model_core.industry_output,
                final_use.industry_output,
                "industry output",
            ),
        )
        structurally_equal(left, right) ||
            throw(ArgumentError("upstream $label reports disagree"))
    end

    residential_model, residential_model_explicit =
        column_candidate(model_core.producer_final_use, "F02R")
    residential_closure, residential_closure_explicit =
        column_candidate(model_core.closure.producer_final_use, "F02R")
    residential = ResidentialInvestmentCandidate(
        residential_model,
        residential_model_explicit,
        residential_closure,
        residential_closure_explicit,
        false,
    )
    inventory_model, inventory_model_explicit =
        column_candidate(model_core.producer_final_use, "F030")
    inventory_closure, inventory_closure_explicit =
        column_candidate(model_core.closure.producer_final_use, "F030")
    inventory = InventoryFlowCandidate(
        inventory_model,
        inventory_model_explicit,
        inventory_closure,
        inventory_closure_explicit,
        :annual,
        :preserve,
        false,
        false,
    )
    producer_f050_model, producer_f050_model_explicit =
        column_candidate(model_core.producer_final_use, "F050")
    producer_f050_closure, producer_f050_closure_explicit =
        column_candidate(model_core.closure.producer_final_use, "F050")
    imports = ImportBoundaryEvidence(
        producer_f050_model,
        producer_f050_model_explicit,
        producer_f050_closure,
        producer_f050_closure_explicit,
        model_core.import_intermediate_use,
        model_core.closure.import_intermediate_use,
        model_core.import_final_use,
        model_core.closure.import_final_use,
        model_core.import_allocation.import_f050_offset,
        model_core.import_allocation.import_f050_explicit,
        model_core.closure.import_allocation.import_f050_offset,
        model_core.closure.import_allocation.import_f050_explicit,
        :separate_bea_imputed_import_allocation,
        :positive_allocated_uses_plus_signed_f050_accounting_offset,
        false,
        false,
        false,
    )

    closure_specs = validated.contract["closure_account"]
    closure_assessments = ClosureAccountAssessment[]
    for (position, code) in pairs(model_core.closure_codes)
        spec = closure_specs[position]
        intermediate_position =
            model_core.closure.producer_intermediate_use.row_index[code]
        final_position =
            model_core.closure.producer_final_use.row_index[code]
        make_position = model_core.closure.producer_make.column_index[code]
        push!(
            closure_assessments,
            ClosureAccountAssessment(
                code,
                Symbol(lowercase(String(spec["methodology_role"]))),
                false,
                false,
                :unresolved,
                Int.(spec["methodology_pdf_pages"]),
                sum(
                    model_core.closure.producer_intermediate_use.values[
                        intermediate_position,
                        :,
                    ],
                ),
                sum(
                    model_core.closure.producer_final_use.values[
                        final_position,
                        :,
                    ],
                ),
                sum(
                    model_core.closure.producer_make.values[
                        :,
                        make_position,
                    ],
                ),
                model_core.closure.commodity_output[code],
            ),
        )
    end
    closure_omission_witness = build_closure_omission_witness(
        model_core.producer_intermediate_use,
        model_core.closure.producer_intermediate_use,
        model_core.producer_value_added,
        model_core.industry_output,
    )
    residuals = build_residuals(
        model_core.producer_intermediate_use,
        model_core.closure.producer_intermediate_use,
        residential,
        inventory,
        imports,
        model_core.producer_value_added,
        model_core.industry_output,
        model_core.source_industry_mapping,
        final_use.observed_tax_variant,
        final_use.closure_net_product_tax_control,
        final_use.source_net_product_tax_total,
        closure_assessments,
    )

    report = ProducerPriceAdapterCandidateReport(
        2024,
        model_core.model_codes,
        model_core.closure_codes,
        copy(model_core.producer_final_use.column_codes),
        copy(final_use.category_codes),
        copy(model_core.producer_value_added.row_codes),
        model_core.source_commodity_mapping,
        model_core.source_industry_mapping,
        model_core.producer_intermediate_use,
        model_core.closure.producer_intermediate_use,
        model_core.producer_final_use,
        model_core.closure.producer_final_use,
        final_use.model_category_final_use,
        final_use.closure_category_final_use,
        residential,
        inventory,
        imports,
        model_core.producer_value_added,
        model_core.producer_make,
        model_core.closure.producer_make,
        model_core.commodity_output,
        model_core.commodity_output_explicit,
        model_core.closure.commodity_output,
        model_core.closure.commodity_output_explicit,
        model_core.industry_output,
        model_core.industry_output_explicit,
        final_use.observed_tax_variant,
        final_use.zero_tax_variant,
        final_use.closure_net_product_tax_control,
        final_use.source_net_product_tax_total,
        closure_assessments,
        closure_omission_witness,
        expected_output_assessments(),
        residuals,
        negative_cells(model_core.producer_intermediate_use),
        negative_cells(model_core.closure.producer_intermediate_use),
        negative_cells(model_core.producer_final_use),
        negative_cells(model_core.closure.producer_final_use),
        negative_cells(final_use.model_category_final_use),
        negative_cells(final_use.closure_category_final_use),
        negative_cells(model_core.producer_value_added),
        negative_cells(model_core.import_intermediate_use),
        negative_cells(model_core.closure.import_intermediate_use),
        negative_cells(model_core.import_final_use),
        negative_cells(model_core.closure.import_final_use),
        validated.contract_sha256,
        APPROVED_AFTER_FIXTURE_SHA256,
        APPROVED_AFTER_MANIFEST_SHA256,
        APPROVED_AFTER_SOURCE_ZIP_SHA256,
        APPROVED_MODEL_MAPPING_SHA256,
        APPROVED_SECTOR_MAPPING_SHA256,
        APPROVED_VALUATION_CONTRACT_SHA256,
        APPROVED_FINAL_USE_CONTRACT_SHA256,
        APPROVED_SUPPLY_FIXTURE_SHA256,
        APPROVED_SUPPLY_MANIFEST_SHA256,
        APPROVED_TABLE_262_SOURCE_SHA256,
        APPROVED_METHODOLOGY_PDF_SHA256,
        APPROVED_METHODOLOGY_RECEIPT_SHA256,
        String(validated.after_manifest["status"]),
        String(validated.methodology["status"]),
        :typed_calibration_adapter_candidate_only,
        :annual,
        :millions_usd,
        :code_keyed_producer_price_candidate_with_typed_closure_sidecar,
        :producers_prices,
        :direct_producer_price_core_with_separate_closure_no_rake,
        :used_other_separate_unallocated,
        :bea_nonscrap_transformation_required_not_applied,
        :other_noncomparable_imports_and_row_adjustment_boundary_unselected,
        :f030_signed_annual_flow_no_stock_emission,
        :f050_signed_offset_and_imputed_import_evidence_no_model_import_vector,
        :observed_and_zero_controls_unselected_no_runtime_tax_emission,
        :v001_v002_v003_retained_without_runtime_tax_split,
        :consumption_and_gross_investment_retained_separately,
        :f02r_retained_without_dwelling_stock_mapping,
        :preserve,
        :preserve_numeric_zero_vs_selected_zero,
        :omitted_rejected_not_cell_identified,
        String[],
        copy(EXPECTED_FORBIDDEN_RUNTIME_KEYS),
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        :none,
        vcat(EXPECTED_ADAPTER_BLOCKERS, final_use.promotion_blockers),
        false,
    )
    producer_price_adapter_candidate_internal_controls_pass(report) ||
        throw(ArgumentError("producer-price adapter internal controls do not pass"))
    return report
end

"""
    producer_price_adapter_candidate_controls_pass(
        report,
        contract_path;
        source_paths...,
    )

Public source-aware stale-report gate. The contract and source paths are
required; there is no report-only overload.
"""
function producer_price_adapter_candidate_controls_pass(
        report::ProducerPriceAdapterCandidateReport,
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
        final_use_contract_path = DEFAULT_FINAL_USE_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    try
        expected = _build_producer_price_adapter_candidate(
            contract_path;
            after_directory,
            supply_directory,
            model_mapping_path,
            sector_mapping_path,
            valuation_contract_path,
            final_use_contract_path,
            methodology_pdf_path,
            methodology_receipt_path,
        )
        return structurally_equal(report, expected)
    catch
        return false
    end
end

"""
    build_producer_price_adapter_candidate(contract_path; source_paths...)

Build the source-aware, candidate-only producer-price adapter and require both
internal and canonical-source controls.
"""
function build_producer_price_adapter_candidate(
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
        final_use_contract_path = DEFAULT_FINAL_USE_CONTRACT_PATH,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    report = _build_producer_price_adapter_candidate(
        contract_path;
        after_directory,
        supply_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
        final_use_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    producer_price_adapter_candidate_controls_pass(
        report,
        contract_path;
        after_directory,
        supply_directory,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
        final_use_contract_path,
        methodology_pdf_path,
        methodology_receipt_path,
    ) || throw(ArgumentError("producer-price adapter source controls do not pass"))
    return report
end

"""
    materialize_producer_price_adapter_model_state(report)

The candidate deliberately has no state-materialization path. The typed
closure, trade, tax, industry/commodity, quarterly, and measurement boundaries
must be resolved in later contracts before this method can be replaced.
"""
function materialize_producer_price_adapter_model_state(
        ::ProducerPriceAdapterCandidateReport,
    )
    throw(
        ArgumentError(
            "producer-price adapter candidate is not runtime-admissible; closure and calibration boundaries remain unresolved",
        ),
    )
end

end
