module USAfterRedefinitionsClosureBoundaryCandidate

using LinearAlgebra
using SHA
using TOML

using ..USSupplyMakeDiagnostics:
    CommodityBasis,
    ControlResidual,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector
using ..USSymmetricSupplyUse: NegativeCell, negative_cells
using ..USRequirementsDiagnostics:
    load_official_direct_requirements_fixture
using ..USAfterRedefinitionsCommonBasis:
    FinalUseBasis,
    load_after_redefinitions_fixture
using ..USAfterRedefinitionsProducerPriceAdapterCandidate:
    ProducerPriceAdapterCandidateReport,
    build_producer_price_adapter_candidate

export ClosureBoundaryLedger,
    ClosureBoundaryCandidateReport,
    UsedNonscrapWitness,
    build_closure_boundary_candidate,
    closure_boundary_candidate_controls_pass,
    closure_boundary_candidate_internal_controls_pass,
    materialize_closure_boundary_model_state

const CONTRACT_SCHEMA =
    "beforeit-us-after-redefinitions-closure-boundary-candidate.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_ARTIFACT_ROLE = "TYPED_CLOSURE_BOUNDARY_CANDIDATE_ONLY"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_CONTRACT_SHA256 =
    "ad6f1995575b1fa612577eb4001e9163159d6802fa947d6f5385a2d07758172f"
const EXPECTED_CLOSURE_CODES = ["Used", "Other"]
const EXPECTED_METHODOLOGY_PAGES = [98, 123, 124, 214, 223, 224, 225]
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
const EXPECTED_BOUNDARY_BLOCKERS = [
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
    "after_redefinitions_import_workbook_sha256" =>
        "9246c68288bb593495366288b9d8fd2038cae1ff500855ccd3e5c4377d0d3b25",
    "after_redefinitions_purchaser_use_workbook_sha256" =>
        "9d55530ec5cd4688855ef474c779d0dba5f2e1e74d4fcfcdc95cddc64c69262b",
    "official_market_share_fixture_sha256" =>
        "d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e",
    "official_market_share_manifest_sha256" =>
        "a225951d7ec03aaaaa97f5cc02e58b862e00918dbd31cc35093d80f9dde8c35d",
    "official_market_share_source_zip_sha256" =>
        "e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae",
    "official_market_share_source_metadata_sha256" =>
        "f3f57a7209f7c6d9b0f76b041f17ae78e9da1d8644dbd7d6815471e740abfaca",
    "official_direct_workbook_sha256" =>
        "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439",
    "official_market_share_workbook_sha256" =>
        "57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2",
    "producer_price_adapter_contract_sha256" =>
        "de524df56ad47fb1f26534019386b27f1fc45ebc927bda5f39c3ad812259cf58",
    "model_mapping_sha256" =>
        "546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c",
    "sector_mapping_sha256" =>
        "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f",
    "valuation_contract_sha256" =>
        "110f82037e45e1de3ce4f5a1df2b7982d064e90a9323f255c7441452fa6d2ede",
    "final_use_contract_sha256" =>
        "b4e3969a52618b4e462b8e468ada784dda85cae86550fb27659d2afbb4cbb2be",
    "supply_fixture_sha256" =>
        "c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0",
    "supply_manifest_sha256" =>
        "564a99ec2011b2566b8951e9eecb4737c0bfbc88f1e077b1eaf596af9894575c",
    "table_262_source_sha256" =>
        "91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8",
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
const DEFAULT_OFFICIAL_MARKET_SHARE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_2024_official_direct_requirements_approved",
)
const DEFAULT_ADAPTER_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_producer_price_adapter_candidate.toml")
const DEFAULT_MODEL_MAPPING_PATH =
    joinpath(@__DIR__, "after_redefinitions_model_core_mapping.toml")
const DEFAULT_SECTOR_MAPPING_PATH =
    normpath(joinpath(@__DIR__, "..", "bea71.toml"))
const DEFAULT_VALUATION_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_valuation_envelope.toml")
const DEFAULT_FINAL_USE_CONTRACT_PATH =
    joinpath(@__DIR__, "after_redefinitions_final_use_envelope.toml")
const DEFAULT_SUPPLY_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "bea_2024_approved")
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
One source-basis closure account.

The signed intermediate-use, final-use, make, and published market-share
vectors retain source codes and masks. The market-share vector is evidence,
not permission to treat the closure account as an ordinary commodity.
"""
struct ClosureBoundaryLedger
    code::String
    methodology_role::Symbol
    methodology_pdf_pages::Vector{Int}
    intermediate_use::LabeledVector{IndustryBasis}
    intermediate_use_explicit::BitVector
    final_use::LabeledVector{FinalUseBasis}
    final_use_explicit::BitVector
    make_by_industry::LabeledVector{IndustryBasis}
    make_explicit::BitVector
    published_market_share::LabeledVector{IndustryBasis}
    published_market_share_explicit::BitVector
    commodity_output::Float64
    commodity_output_explicit::Bool
    ordinary_model_commodity::Bool
    ordinary_model_producer_industry::Bool
    component_split::Bool
end

"""
BEA nonscrap-output arithmetic for the source 71-industry core.

`h` is the `Used` make column, `p = h ./ g`, and
`W = (I - diag(p)) \\ D_core`. Here `D_core` is the rounded, separately
published cross-archive matrix. It is not interchangeable with the same-table
`V_core * diag(q_core)^-1`, and source-first ratios are not interchangeable
with the required aggregate-first 68-sector construction. `W` is diagnostic
only and is never applied to the adapter's `U`, `a`, or `beta`.
"""
struct UsedNonscrapWitness
    scrap_output::LabeledVector{IndustryBasis}
    scrap_output_explicit::BitVector
    industry_output::LabeledVector{IndustryBasis}
    industry_output_explicit::BitVector
    scrap_share::LabeledVector{IndustryBasis}
    scrap_share_explicit::BitVector
    nonscrap_ratio::LabeledVector{IndustryBasis}
    nonscrap_ratio_explicit::BitVector
    ordinary_commodity_output::LabeledVector{CommodityBasis}
    ordinary_commodity_output_explicit::BitVector
    official_core_market_shares::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    diagnostic_nonscrap_transform::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    published_core_make_identity_residual::LabeledVector{IndustryBasis}
    used_only_output_gap::LabeledVector{IndustryBasis}
    other_nonscrap_output_requirement::LabeledVector{IndustryBasis}
    published_other_closure_residual::LabeledVector{IndustryBasis}
    formula::Symbol
    runtime_admissible::Bool
    applied_to_core_use::Bool
    applied_to_direct_requirements::Bool
    applied_to_output_multiplier::Bool
end

"""
Source-aware closure-boundary candidate with no runtime materialization path.

The report carries both source 71-industry closure ledgers and the current
68-sector adapter sidecar. The closure accounts remain disjoint from the
ordinary model codes; no 70-account runtime technology is constructed.
"""
struct ClosureBoundaryCandidateReport
    year::Int
    source_industry_codes::Vector{String}
    source_ordinary_commodity_codes::Vector{String}
    model_codes::Vector{String}
    closure_codes::Vector{String}
    source_industry_mapping::Dict{String, String}
    used::ClosureBoundaryLedger
    other::ClosureBoundaryLedger
    nonscrap::UsedNonscrapWitness
    adapter_core_intermediate_use::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    adapter_closure_intermediate_use::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    adapter_closure_final_use::LabeledMatrix{
        CommodityBasis,
        FinalUseBasis,
    }
    adapter_closure_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    core_identity_omission::Float64
    full_identity_gap::Float64
    residuals::Vector{ControlResidual}
    negative_core_market_share_cells::Vector{NegativeCell}
    negative_nonscrap_transform_cells::Vector{NegativeCell}
    contract_sha256::String
    byte_pins::Dict{String, String}
    source_status::String
    methodology_status::String
    artifact_role::Symbol
    source_frequency::Symbol
    unit::Symbol
    price_basis::Symbol
    policies::Dict{Symbol, Symbol}
    flags::Dict{Symbol, Bool}
    emitted_runtime_keys::Vector{String}
    forbidden_runtime_keys::Vector{String}
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

function row_candidate(matrix::LabeledMatrix{R, C}, code) where {R, C}
    position = matrix.row_index[code]
    return (
        LabeledVector{C}(
            matrix.column_codes,
            vec(matrix.values[position, :]),
        ),
        BitVector(matrix.explicit[position, :]),
    )
end

function column_candidate(matrix::LabeledMatrix{R, C}, code) where {R, C}
    position = matrix.column_index[code]
    return (
        LabeledVector{R}(
            matrix.row_codes,
            vec(matrix.values[:, position]),
        ),
        BitVector(matrix.explicit[:, position]),
    )
end

function output_explicit(fixture, code)
    position = fixture.producer_commodity_output_make.index[code]
    mask =
        fixture.source_explicit["producer_make_commodity_output_2024"]
    return Bool(mask[position, 1])
end

function expected_flags()
    return Dict(
        :candidate_materialized => true,
        :nonscrap_diagnostic_computed => true,
        :runtime_nonscrap_transformation_implemented => false,
        :w_runtime_admissible => false,
        :generic_closure_market_share_application => false,
        :closure_disjoint_from_model_core => true,
        :seventy_account_runtime_expansion => false,
        :closure_smearing_into_core_u => false,
        :closure_smearing_into_a => false,
        :closure_smearing_into_beta => false,
        :other_component_split => false,
        :used_asset_transfer_mapping => false,
        :current_dollar_price_quantity_decomposition => false,
        :quarterly_dynamic_law => false,
        :financial_counterpart_mapping => false,
        :row_adjustment_observation_operator => false,
        :behavioral_production_constraint_mapping => false,
        :double_entry_transition_tests => false,
        :industry_commodity_runtime_transform_selected => false,
        :aggregate_first_68_nonscrap_transform_built => false,
        :runtime_calibration_admissible => false,
        :calibration_dictionary_write => false,
        :figaro_dictionary_write => false,
        :parameter_write => false,
        :initial_conditions_write => false,
        :model_state_write => false,
        :forecast_origin_admissible => false,
        :balancing_applied => false,
        :normalization_applied => false,
        :clipping_applied => false,
        :raking_applied => false,
    )
end

function expected_policies()
    return Dict(
        :scrap_output_formula => :h_equals_make_used_column,
        :scrap_share_formula => :p_equals_h_divided_by_g,
        :nonscrap_ratio_formula => :one_minus_p,
        :nonscrap_transform_formula =>
            :inverse_one_minus_diagonal_p_times_core_d,
        :used =>
            :source_signed_ledger_plus_diagnostic_bea_nonscrap_witness,
        :other => :source_signed_composite_ledger_component_split_unresolved,
        :market_share =>
            :official_published_d_without_generic_closure_application,
        :official_d_role =>
            :rounded_separately_published_cross_archive_witness_only,
        :same_table_identity_role =>
            :v_core_and_q_core_define_source_identity_official_d_residual_is_ledgered,
        :eventual_model_transform_order =>
            :aggregate_make_output_and_scrap_to_68_before_forming_p_d_and_w,
        :aggregation_commutation =>
            :source_first_and_aggregate_first_nonscrap_not_interchangeable,
        :negative_cell => :preserve_and_ledger,
        :explicit_mask =>
            :preserve_source_masks_derived_values_have_false_mask,
        :cross_archive_release_identity => :not_externally_bound,
        :cross_archive_application_status => :arithmetic_diagnostic_only,
    )
end

function validate_contract(
        contract_path,
        after_directory,
        official_market_share_directory,
        adapter_contract_path,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
        final_use_contract_path,
        supply_directory,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    contract_bytes = read(contract_path)
    contract_sha256 = sha256_hex(contract_bytes)
    contract_sha256 == APPROVED_CONTRACT_SHA256 ||
        throw(ArgumentError("unexpected closure-boundary contract SHA-256"))
    contract = TOML.parse(String(contract_bytes))
    expected_scalars = Dict{String, Any}(
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
        "model_commodity_count" => 68,
        "model_industry_count" => 68,
        "scrap_output_formula" => "h[i] = V_make[i,Used]",
        "scrap_share_formula" => "p[i] = h[i] / g[i]",
        "nonscrap_ratio_formula" => "r[i] = 1 - p[i]",
        "nonscrap_transform_formula" =>
            "W = (I - diag(p))^-1 * D_core",
        "core_market_share_definition" =>
            "D_core = D_official[:,ordinary_commodities]",
        "orientation" => "industry_by_commodity",
        "used_policy" =>
            "SOURCE_SIGNED_LEDGER_PLUS_DIAGNOSTIC_BEA_NONSCRAP_WITNESS",
        "other_policy" =>
            "SOURCE_SIGNED_COMPOSITE_LEDGER_COMPONENT_SPLIT_UNRESOLVED",
        "market_share_policy" =>
            "OFFICIAL_PUBLISHED_D_RETAINED_WITHOUT_GENERIC_CLOSURE_APPLICATION",
        "official_d_role" =>
            "ROUNDED_SEPARATELY_PUBLISHED_CROSS_ARCHIVE_WITNESS_ONLY",
        "same_table_identity_role" =>
            "V_CORE_AND_Q_CORE_DEFINE_SOURCE_IDENTITY_OFFICIAL_D_RESIDUAL_IS_LEDGERED",
        "eventual_model_transform_order" =>
            "AGGREGATE_MAKE_OUTPUT_AND_SCRAP_TO_68_BEFORE_FORMING_P_D_AND_W",
        "aggregation_commutation_policy" =>
            "SOURCE_FIRST_AND_AGGREGATE_FIRST_NONSCRAP_TRANSFORMS_NOT_INTERCHANGEABLE",
        "negative_cell_policy" => "PRESERVE_AND_LEDGER",
        "explicit_mask_policy" =>
            "PRESERVE_SOURCE_MASKS_DERIVED_VALUES_HAVE_FALSE_MASK",
        "cross_archive_release_identity" => "NOT_EXTERNALLY_BOUND",
        "cross_archive_application_status" =>
            "ARITHMETIC_DIAGNOSTIC_ONLY",
        "accounting_gate_effect" => "NONE",
    )
    for (key, expected) in expected_scalars
        get(contract, key, nothing) == expected ||
            throw(ArgumentError("unexpected closure-boundary contract $key"))
    end
    String.(get(contract, "closure_codes", String[])) ==
        EXPECTED_CLOSURE_CODES ||
        throw(ArgumentError("unexpected closure codes"))
    Int.(get(contract, "methodology_pdf_pages", Int[])) ==
        EXPECTED_METHODOLOGY_PAGES ||
        throw(ArgumentError("unexpected methodology page ledger"))
    String.(get(contract, "forbidden_runtime_keys", String[])) ==
        EXPECTED_FORBIDDEN_RUNTIME_KEYS ||
        throw(ArgumentError("unexpected forbidden runtime keys"))
    String.(get(contract, "promotion_blockers", String[])) ==
        EXPECTED_BOUNDARY_BLOCKERS ||
        throw(ArgumentError("unexpected closure-boundary blockers"))
    contract_flags = expected_flags()
    for (key, expected) in contract_flags
        get(contract, String(key), !expected) === expected ||
            throw(ArgumentError("unexpected closure-boundary flag $key"))
    end
    byte_pins = Dict(
        String(key) => String(value)
            for (key, value) in get(contract, "byte_pins", Dict())
    )
    byte_pins == EXPECTED_BYTE_PINS ||
        throw(ArgumentError("unexpected closure-boundary byte pins"))

    closure_specs = get(contract, "closure_account", Any[])
    length(closure_specs) == 2 ||
        throw(ArgumentError("closure-account contract count changed"))
    for (spec, code, role, pages) in zip(
            closure_specs,
            EXPECTED_CLOSURE_CODES,
            [
                "COMPOSITE_SPECIAL_ACCOUNT_SCRAP_BYPRODUCT_PLUS_SIGNED_USED_ASSET_TRANSFERS",
                "NONCOMPARABLE_IMPORTS_AND_REST_OF_WORLD_ADJUSTMENT_COMPOSITE",
            ],
            [[98, 214, 223, 224, 225], [123, 124]],
        )
        get(spec, "code", "") == code ||
            throw(ArgumentError("closure-account order changed"))
        get(spec, "methodology_role", "") == role ||
            throw(ArgumentError("closure-account role changed"))
        Int.(get(spec, "methodology_pdf_pages", Int[])) == pages ||
            throw(ArgumentError("closure-account methodology pages changed"))
        get(spec, "ordinary_model_commodity", true) === false ||
            throw(ArgumentError("closure account cannot be an ordinary commodity"))
        get(spec, "ordinary_model_producer_industry", true) === false ||
            throw(ArgumentError("closure account cannot be an ordinary industry"))
        get(spec, "component_split", true) === false ||
            throw(ArgumentError("closure component split is not identified"))
    end

    pinned_files = Dict(
        "after_redefinitions_fixture_sha256" =>
            joinpath(after_directory, "cells.csv"),
        "after_redefinitions_manifest_sha256" =>
            joinpath(after_directory, "manifest.toml"),
        "official_market_share_fixture_sha256" =>
            joinpath(official_market_share_directory, "cells.csv"),
        "official_market_share_manifest_sha256" =>
            joinpath(official_market_share_directory, "manifest.toml"),
        "producer_price_adapter_contract_sha256" => adapter_contract_path,
        "model_mapping_sha256" => model_mapping_path,
        "sector_mapping_sha256" => sector_mapping_path,
        "valuation_contract_sha256" => valuation_contract_path,
        "final_use_contract_sha256" => final_use_contract_path,
        "supply_fixture_sha256" => joinpath(supply_directory, "cells.csv"),
        "supply_manifest_sha256" =>
            joinpath(supply_directory, "manifest.toml"),
        "methodology_pdf_sha256" => methodology_pdf_path,
        "methodology_receipt_sha256" => methodology_receipt_path,
    )
    for (pin, path) in pinned_files
        sha256_hex(read(path)) == EXPECTED_BYTE_PINS[pin] ||
            throw(ArgumentError("$pin does not match its approved bytes"))
    end

    after_manifest = TOML.parsefile(joinpath(after_directory, "manifest.toml"))
    official_manifest =
        TOML.parsefile(joinpath(official_market_share_directory, "manifest.toml"))
    supply_manifest =
        TOML.parsefile(joinpath(supply_directory, "manifest.toml"))
    methodology = TOML.parsefile(methodology_receipt_path)
    manifest_pins = [
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
    ]
    for (manifest, key, pin) in manifest_pins
        lowercase(String(get(manifest, key, ""))) ==
            EXPECTED_BYTE_PINS[pin] ||
            throw(ArgumentError("$pin changed in its source manifest"))
    end
    get(after_manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("after-redefinitions status changed"))
    get(official_manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("official market-share status changed"))
    table_262_sources = filter(
        source -> get(source, "table_id", "") == "262",
        get(supply_manifest, "sources", Any[]),
    )
    length(table_262_sources) == 1 ||
        throw(ArgumentError("supply manifest Table 262 identity changed"))
    lowercase(String(get(only(table_262_sources), "source_sha256", ""))) ==
        EXPECTED_BYTE_PINS["table_262_source_sha256"] ||
        throw(ArgumentError("Table 262 source SHA-256 changed"))
    get(methodology, "status", "") ==
        "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA" ||
        throw(ArgumentError("methodology status changed"))
    lowercase(String(get(methodology, "source_sha256", ""))) ==
        EXPECTED_BYTE_PINS["methodology_pdf_sha256"] ||
        throw(ArgumentError("methodology receipt no longer identifies the PDF"))

    return (
        contract = contract,
        contract_sha256 = contract_sha256,
        after_manifest = after_manifest,
        official_manifest = official_manifest,
        methodology = methodology,
    )
end

function build_ledger(fixture, official_market_shares, spec)
    code = String(spec["code"])
    intermediate, intermediate_explicit =
        row_candidate(fixture.producer_intermediate_use, code)
    final_use, final_use_explicit =
        row_candidate(fixture.producer_final_use, code)
    make, make_explicit =
        column_candidate(fixture.producer_make, code)
    market_share, market_share_explicit =
        column_candidate(official_market_shares, code)
    return ClosureBoundaryLedger(
        code,
        Symbol(lowercase(String(spec["methodology_role"]))),
        Int.(spec["methodology_pdf_pages"]),
        intermediate,
        intermediate_explicit,
        final_use,
        final_use_explicit,
        make,
        make_explicit,
        market_share,
        market_share_explicit,
        fixture.producer_commodity_output_make[code],
        output_explicit(fixture, code),
        false,
        false,
        false,
    )
end

function build_nonscrap_witness(
        fixture,
        official_market_shares,
        used,
        other,
    )
    industry_codes = copy(fixture.producer_make.row_codes)
    ordinary_codes = filter(
        code -> !(code in EXPECTED_CLOSURE_CODES),
        fixture.producer_make.column_codes,
    )
    ordinary_codes == industry_codes ||
        throw(
        ArgumentError(
            "source ordinary commodity and industry axes are not code-aligned",
        ),
    )
    official_market_shares.row_codes == industry_codes ||
        throw(ArgumentError("official market-share industry axis changed"))
    Set(official_market_shares.column_codes) ==
        Set(fixture.producer_make.column_codes) ||
        throw(ArgumentError("official market-share commodity axis changed"))

    industry_output = fixture.producer_industry_output_make
    industry_output_explicit = BitVector(
        fixture.source_explicit["producer_make_industry_output_2024"][:, 1],
    )
    all(>(0.0), industry_output.values) ||
        throw(ArgumentError("industry output must be positive"))
    scrap_share_values =
        used.make_by_industry.values ./ industry_output.values
    all(value -> 0.0 <= value < 1.0, scrap_share_values) ||
        throw(ArgumentError("scrap shares must be in [0,1)"))
    nonscrap_ratio_values = 1.0 .- scrap_share_values
    commodity_positions = [
        official_market_shares.column_index[code] for code in ordinary_codes
    ]
    core_market_shares = LabeledMatrix{IndustryBasis, CommodityBasis}(
        industry_codes,
        ordinary_codes,
        official_market_shares.values[:, commodity_positions],
        official_market_shares.explicit[:, commodity_positions],
    )
    nonscrap_operator =
        Matrix{Float64}(I, length(industry_codes), length(industry_codes)) -
        Diagonal(scrap_share_values)
    transform_values = nonscrap_operator \ core_market_shares.values
    commodity_output_positions = [
        fixture.producer_commodity_output_make.index[code]
            for code in ordinary_codes
    ]
    ordinary_output_values =
        fixture.producer_commodity_output_make.values[
        commodity_output_positions,
    ]
    ordinary_output_explicit = BitVector(
        fixture.source_explicit[
            "producer_make_commodity_output_2024",
        ][commodity_output_positions, 1],
    )
    published_core_make_identity_residual_values =
        core_market_shares.values * ordinary_output_values .-
        (
        nonscrap_ratio_values .* industry_output.values .-
            other.make_by_industry.values
    )
    used_only_output_gap_values =
        industry_output.values .-
        transform_values * ordinary_output_values
    other_nonscrap_output_requirement_values =
        nonscrap_operator \ other.make_by_industry.values
    published_other_closure_residual_values =
        used_only_output_gap_values .-
        other_nonscrap_output_requirement_values
    diagnostic_transform = LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }(
        industry_codes,
        ordinary_codes,
        transform_values,
        falses(size(transform_values)),
    )
    return UsedNonscrapWitness(
        used.make_by_industry,
        copy(used.make_explicit),
        industry_output,
        industry_output_explicit,
        LabeledVector{IndustryBasis}(industry_codes, scrap_share_values),
        falses(length(industry_codes)),
        LabeledVector{IndustryBasis}(
            industry_codes,
            nonscrap_ratio_values,
        ),
        falses(length(industry_codes)),
        LabeledVector{CommodityBasis}(
            ordinary_codes,
            ordinary_output_values,
        ),
        ordinary_output_explicit,
        core_market_shares,
        diagnostic_transform,
        LabeledVector{IndustryBasis}(
            industry_codes,
            published_core_make_identity_residual_values,
        ),
        LabeledVector{IndustryBasis}(
            industry_codes,
            used_only_output_gap_values,
        ),
        LabeledVector{IndustryBasis}(
            industry_codes,
            other_nonscrap_output_requirement_values,
        ),
        LabeledVector{IndustryBasis}(
            industry_codes,
            published_other_closure_residual_values,
        ),
        :inverse_one_minus_diagonal_p_times_core_d,
        false,
        false,
        false,
        false,
    )
end

function aggregate_source_industries(vector, mapping, model_codes)
    target_index =
        Dict(code => position for (position, code) in pairs(model_codes))
    values = zeros(length(model_codes))
    explicit = falses(length(model_codes))
    for (position, code) in pairs(vector.codes)
        target = mapping[code]
        target_position = target_index[target]
        values[target_position] += vector.values[position]
        explicit[target_position] = true
    end
    return values, explicit
end

function build_residuals(used, other, nonscrap, adapter)
    residuals = ControlResidual[]
    for (
            ledger,
            expected_intermediate,
            expected_final,
            expected_output,
            expected_f050,
            expected_use_output_gap,
        ) in (
            (used, 100_094.0, -86_542.0, 13_553.0, -17_449.0, -1.0),
            (other, 172_632.0, -166_441.0, 6_187.0, -369_200.0, 4.0),
        )
        for (suffix, lhs, rhs, equation) in (
                (
                    "INTERMEDIATE",
                    sum(ledger.intermediate_use.values),
                    expected_intermediate,
                    "signed source intermediate-use ledger retained",
                ),
                (
                    "FINAL",
                    sum(ledger.final_use.values),
                    expected_final,
                    "signed source final-use ledger retained",
                ),
                (
                    "MAKE",
                    sum(ledger.make_by_industry.values),
                    expected_output,
                    "source make column retained",
                ),
                (
                    "OUTPUT",
                    ledger.commodity_output,
                    expected_output,
                    "source commodity-output control retained",
                ),
            )
            add_residual!(
                residuals,
                :closure_source_total,
                "$(ledger.code)_$suffix",
                equation,
                lhs,
                rhs,
                0.0,
            )
        end
        add_residual!(
            residuals,
            :closure_import_boundary,
            "$(ledger.code)_F050",
            "signed closure F050 accounting offset retained",
            ledger.final_use["F050"],
            expected_f050,
            0.0,
        )
        add_residual!(
            residuals,
            :closure_use_output_rounding,
            ledger.code,
            "intermediate use plus final use less commodity output",
            sum(ledger.intermediate_use.values) +
                sum(ledger.final_use.values) -
                ledger.commodity_output,
            expected_use_output_gap,
            0.0,
        )
    end
    p = nonscrap.scrap_share.values
    g = nonscrap.industry_output.values
    h = nonscrap.scrap_output.values
    r = nonscrap.nonscrap_ratio.values
    D = nonscrap.official_core_market_shares.values
    W = nonscrap.diagnostic_nonscrap_transform.values
    formula_W =
        (Matrix{Float64}(I, length(p), length(p)) - Diagonal(p)) \ D
    for (code, lhs, rhs, tolerance, equation) in (
            (
                "H_TOTAL",
                sum(h),
                13_553.0,
                0.0,
                "h equals total Used byproduct make",
            ),
            (
                "H_EQUALS_P_TIMES_G",
                maximum(abs.(h .- p .* g)),
                0.0,
                1.0e-10,
                "h = p .* g",
            ),
            (
                "R_EQUALS_ONE_MINUS_P",
                maximum(abs.(r .+ p .- 1.0)),
                0.0,
                1.0e-15,
                "nonscrap ratio plus scrap share equals one",
            ),
            (
                "D_COLUMN_CONTROL",
                maximum(abs.(vec(sum(D; dims = 1)) .- 1.0)),
                0.0,
                3.6e-6,
                "published ordinary-commodity D columns sum to one",
            ),
            (
                "W_FORMULA",
                maximum(abs.(W .- formula_W)),
                0.0,
                1.0e-15,
                "W = (I - diag(p))^-1 * D_core",
            ),
        )
        add_residual!(
            residuals,
            :nonscrap_method,
            code,
            equation,
            lhs,
            rhs,
            tolerance,
        )
    end
    core_identity_residual =
        nonscrap.published_core_make_identity_residual.values
    other_closure_residual =
        nonscrap.published_other_closure_residual.values
    for (code, lhs, rhs, equation) in (
            (
                "D_CORE_Q_SIGNED",
                sum(core_identity_residual),
                1.0964131995460775,
                "ledgered residual of published D_core*q_core - ((I-P)g-o)",
            ),
            (
                "D_CORE_Q_ABSOLUTE",
                sum(abs.(core_identity_residual)),
                19.094310799777304,
                "absolute published cross-archive core-make residual",
            ),
            (
                "OTHER_REQUIREMENT_SIGNED",
                sum(other_closure_residual),
                -1.0963464654378186,
                "ledgered residual of g-W*q_core - (I-P)^-1*o",
            ),
            (
                "OTHER_REQUIREMENT_ABSOLUTE",
                sum(abs.(other_closure_residual)),
                19.10204200799126,
                "absolute published cross-archive Other-closure residual",
            ),
        )
        add_residual!(
            residuals,
            :cross_archive_identity_residual,
            code,
            equation,
            lhs,
            rhs,
            1.0e-9,
        )
    end

    for (ledger, row_position) in (
            (used, adapter.adapter_closure_intermediate_use.row_index["Used"]),
            (other, adapter.adapter_closure_intermediate_use.row_index["Other"]),
        )
        aggregated_intermediate, _ = aggregate_source_industries(
            ledger.intermediate_use,
            adapter.source_industry_mapping,
            adapter.model_codes,
        )
        aggregated_make, _ = aggregate_source_industries(
            ledger.make_by_industry,
            adapter.source_industry_mapping,
            adapter.model_codes,
        )
        final_position =
            adapter.adapter_closure_final_use.row_index[ledger.code]
        make_position =
            adapter.adapter_closure_make.column_index[ledger.code]
        for (suffix, lhs, equation) in (
                (
                    "INTERMEDIATE",
                    maximum(
                        abs.(
                            aggregated_intermediate .-
                                adapter.adapter_closure_intermediate_use.values[
                                row_position,
                                :,
                            ]
                        ),
                    ),
                    "source closure use aggregates exactly to adapter sidecar",
                ),
                (
                    "FINAL",
                    maximum(
                        abs.(
                            ledger.final_use.values .-
                                adapter.adapter_closure_final_use.values[
                                final_position,
                                :,
                            ]
                        ),
                    ),
                    "source closure final use equals adapter sidecar",
                ),
                (
                    "MAKE",
                    maximum(
                        abs.(
                            aggregated_make .-
                                adapter.adapter_closure_make.values[
                                :,
                                make_position,
                            ]
                        ),
                    ),
                    "source closure make aggregates exactly to adapter sidecar",
                ),
            )
            add_residual!(
                residuals,
                :adapter_reconciliation,
                "$(ledger.code)_$suffix",
                equation,
                lhs,
                0.0,
                0.0,
            )
        end
    end
    add_residual!(
        residuals,
        :no_smearing_witness,
        "CORE_U_TOTAL",
        "the adapter's untouched 68x68 core U total is retained",
        sum(adapter.adapter_core_intermediate_use.values),
        21_165_843.0,
        0.0,
    )
    add_residual!(
        residuals,
        :closure_identity_witness,
        "CORE_ONLY",
        "industry identity gap before the closure sidecar",
        adapter.core_identity_omission,
        272_697.0,
        0.0,
    )
    add_residual!(
        residuals,
        :closure_identity_witness,
        "WITH_CLOSURE",
        "industry identity gap after the closure sidecar is source rounding",
        adapter.full_identity_gap,
        -29.0,
        0.0,
    )
    return residuals
end

function closure_boundary_candidate_internal_controls_pass(
        report::ClosureBoundaryCandidateReport,
    )
    try
        report.year == 2024 || return false
        length(report.source_industry_codes) == 71 || return false
        length(report.source_ordinary_commodity_codes) == 71 ||
            return false
        length(report.model_codes) == 68 || return false
        report.closure_codes == EXPECTED_CLOSURE_CODES || return false
        isempty(intersect(Set(report.model_codes), Set(report.closure_codes))) ||
            return false
        isempty(
            intersect(Set(report.source_industry_codes), Set(report.closure_codes)),
        ) || return false
        report.source_industry_codes ==
            report.source_ordinary_commodity_codes ||
            return false
        Set(keys(report.source_industry_mapping)) ==
            Set(report.source_industry_codes) ||
            return false
        Set(values(report.source_industry_mapping)) ==
            Set(report.model_codes) ||
            return false

        for ledger in (report.used, report.other)
            ledger.intermediate_use.codes == report.source_industry_codes ||
                return false
            ledger.final_use.codes ==
                report.adapter_closure_final_use.column_codes ||
                return false
            ledger.make_by_industry.codes == report.source_industry_codes ||
                return false
            ledger.published_market_share.codes ==
                report.source_industry_codes ||
                return false
            length(ledger.intermediate_use_explicit) == 71 || return false
            length(ledger.final_use_explicit) == 20 || return false
            length(ledger.make_explicit) == 71 || return false
            length(ledger.published_market_share_explicit) == 71 ||
                return false
            ledger.ordinary_model_commodity && return false
            ledger.ordinary_model_producer_industry && return false
            ledger.component_split && return false
            ledger.commodity_output_explicit || return false
        end
        report.used.code == "Used" || return false
        report.other.code == "Other" || return false
        report.used.methodology_pdf_pages == [98, 214, 223, 224, 225] ||
            return false
        report.other.methodology_pdf_pages == [123, 124] || return false

        witness = report.nonscrap
        witness.scrap_output.codes == report.source_industry_codes ||
            return false
        witness.industry_output.codes == report.source_industry_codes ||
            return false
        witness.scrap_share.codes == report.source_industry_codes ||
            return false
        witness.nonscrap_ratio.codes == report.source_industry_codes ||
            return false
        witness.ordinary_commodity_output.codes ==
            report.source_ordinary_commodity_codes ||
            return false
        witness.official_core_market_shares.row_codes ==
            report.source_industry_codes ||
            return false
        witness.official_core_market_shares.column_codes ==
            report.source_ordinary_commodity_codes ||
            return false
        witness.diagnostic_nonscrap_transform.row_codes ==
            report.source_industry_codes ||
            return false
        witness.diagnostic_nonscrap_transform.column_codes ==
            report.source_ordinary_commodity_codes ||
            return false
        size(witness.official_core_market_shares) == (71, 71) ||
            return false
        size(witness.diagnostic_nonscrap_transform) == (71, 71) ||
            return false
        witness.scrap_output.values == report.used.make_by_industry.values ||
            return false
        witness.scrap_output_explicit == report.used.make_explicit ||
            return false
        witness.industry_output_explicit == trues(71) || return false
        witness.scrap_share_explicit == falses(71) || return false
        witness.nonscrap_ratio_explicit == falses(71) || return false
        witness.ordinary_commodity_output_explicit == trues(71) ||
            return false
        all(witness.official_core_market_shares.explicit) || return false
        any(witness.diagnostic_nonscrap_transform.explicit) && return false
        all(value -> 0.0 <= value < 1.0, witness.scrap_share.values) ||
            return false
        all(>(0.0), witness.nonscrap_ratio.values) || return false
        maximum(
            abs.(
                witness.scrap_output.values .-
                    witness.scrap_share.values .* witness.industry_output.values
            )
        ) <= 1.0e-10 || return false
        witness.nonscrap_ratio.values ==
            1.0 .- witness.scrap_share.values ||
            return false
        formula_W =
            (
            Matrix{Float64}(I, 71, 71) -
                Diagonal(witness.scrap_share.values)
        ) \ witness.official_core_market_shares.values
        isapprox(
            witness.diagnostic_nonscrap_transform.values,
            formula_W;
            atol = 1.0e-12,
            rtol = 0.0,
        ) ||
            return false
        q = witness.ordinary_commodity_output.values
        D = witness.official_core_market_shares.values
        W = witness.diagnostic_nonscrap_transform.values
        p = witness.scrap_share.values
        g = witness.industry_output.values
        r = witness.nonscrap_ratio.values
        o = report.other.make_by_industry.values
        nonscrap_operator =
            Matrix{Float64}(I, 71, 71) - Diagonal(p)
        expected_core_identity_residual =
            D * q .- (r .* g .- o)
        expected_used_only_output_gap = g .- W * q
        expected_other_requirement = nonscrap_operator \ o
        expected_other_residual =
            expected_used_only_output_gap .-
            expected_other_requirement
        for vector in (
                witness.published_core_make_identity_residual,
                witness.used_only_output_gap,
                witness.other_nonscrap_output_requirement,
                witness.published_other_closure_residual,
            )
            vector.codes == report.source_industry_codes ||
                return false
        end
        isapprox(
            witness.published_core_make_identity_residual.values,
            expected_core_identity_residual;
            atol = 1.0e-10,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            witness.used_only_output_gap.values,
            expected_used_only_output_gap;
            atol = 1.0e-10,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            witness.other_nonscrap_output_requirement.values,
            expected_other_requirement;
            atol = 1.0e-10,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            witness.published_other_closure_residual.values,
            expected_other_residual;
            atol = 1.0e-10,
            rtol = 0.0,
        ) ||
            return false
        sum(q) == 50_716_816.0 || return false
        isapprox(
            sum(expected_core_identity_residual),
            1.0964131995460775;
            atol = 1.0e-9,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            sum(abs.(expected_core_identity_residual)),
            19.094310799777304;
            atol = 1.0e-9,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            maximum(abs.(expected_core_identity_residual)),
            0.7825910001993179;
            atol = 1.0e-9,
            rtol = 0.0,
        ) ||
            return false
        witness.published_core_make_identity_residual.codes[
            argmax(abs.(expected_core_identity_residual)),
        ] == "42" || return false
        isapprox(
            sum(expected_used_only_output_gap),
            6_185.903653534562;
            atol = 1.0e-9,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            sum(expected_other_requirement),
            6_187.0;
            atol = 1.0e-9,
            rtol = 0.0,
        ) || return false
        count(!iszero, expected_other_requirement) == 1 ||
            return false
        witness.other_nonscrap_output_requirement.codes[
            findfirst(!iszero, expected_other_requirement),
        ] == "GFGN" || return false
        isapprox(
            sum(expected_other_residual),
            -1.0963464654378186;
            atol = 1.0e-9,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            sum(abs.(expected_other_residual)),
            19.10204200799126;
            atol = 1.0e-9,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            maximum(abs.(expected_other_residual)),
            0.7825910001993179;
            atol = 1.0e-9,
            rtol = 0.0,
        ) ||
            return false
        witness.formula ==
            :inverse_one_minus_diagonal_p_times_core_d ||
            return false
        witness.runtime_admissible && return false
        witness.applied_to_core_use && return false
        witness.applied_to_direct_requirements && return false
        witness.applied_to_output_multiplier && return false

        size(report.adapter_core_intermediate_use) == (68, 68) ||
            return false
        size(report.adapter_closure_intermediate_use) == (2, 68) ||
            return false
        size(report.adapter_closure_final_use) == (2, 20) ||
            return false
        size(report.adapter_closure_make) == (68, 2) || return false
        report.adapter_core_intermediate_use.row_codes ==
            report.model_codes ||
            return false
        report.adapter_core_intermediate_use.column_codes ==
            report.model_codes ||
            return false
        report.adapter_closure_intermediate_use.row_codes ==
            EXPECTED_CLOSURE_CODES ||
            return false
        report.adapter_closure_make.column_codes ==
            EXPECTED_CLOSURE_CODES ||
            return false

        count(<(0.0), report.used.intermediate_use.values) == 5 ||
            return false
        sum(filter(<(0.0), report.used.intermediate_use.values)) ==
            -729.0 ||
            return false
        count(!iszero, report.used.make_by_industry.values) == 14 ||
            return false
        isapprox(
            sum(report.used.published_market_share.values),
            1.0000001;
            atol = 1.0e-15,
            rtol = 0.0,
        ) || return false
        count(!iszero, report.used.published_market_share.values) == 15 ||
            return false
        maximum(report.used.published_market_share.values) == 0.4188515 ||
            return false
        report.used.published_market_share.codes[
            argmax(report.used.published_market_share.values),
        ] == "GSLG" || return false
        count(<(0.0), report.other.intermediate_use.values) == 0 ||
            return false
        sum(report.other.published_market_share.values) == 1.0 ||
            return false
        count(!iszero, report.other.published_market_share.values) == 1 ||
            return false
        report.other.published_market_share["GFGN"] == 1.0 ||
            return false
        count(<(0.0), witness.official_core_market_shares.values) == 1 ||
            return false
        minimum(witness.official_core_market_shares.values) == -1.13e-5 ||
            return false
        count(<(0.0), witness.diagnostic_nonscrap_transform.values) == 1 ||
            return false
        maximum(witness.scrap_share.values) ==
            0.008175911954472797 ||
            return false
        witness.scrap_share.codes[argmax(witness.scrap_share.values)] ==
            "332" ||
            return false
        isapprox(
            sum(witness.official_core_market_shares.values),
            70.9999994;
            atol = 1.0e-12,
            rtol = 0.0,
        ) ||
            return false
        isapprox(
            sum(witness.diagnostic_nonscrap_transform.values),
            71.02971261741644;
            atol = 1.0e-12,
            rtol = 0.0,
        ) || return false

        expected_residuals = build_residuals(
            report.used,
            report.other,
            report.nonscrap,
            report,
        )
        structurally_equal(report.residuals, expected_residuals) ||
            return false
        length(report.residuals) == 30 || return false
        all(residual -> residual.passed, report.residuals) || return false
        structurally_equal(
            report.negative_core_market_share_cells,
            negative_cells(witness.official_core_market_shares),
        ) || return false
        structurally_equal(
            report.negative_nonscrap_transform_cells,
            negative_cells(witness.diagnostic_nonscrap_transform),
        ) || return false

        report.contract_sha256 == APPROVED_CONTRACT_SHA256 || return false
        report.byte_pins == EXPECTED_BYTE_PINS || return false
        report.source_status == EXPECTED_STATUS || return false
        report.methodology_status ==
            "APPROVED_METHODOLOGY_SOURCE_NOT_ORIGIN_DATA" ||
            return false
        report.artifact_role == :typed_closure_boundary_candidate_only ||
            return false
        report.source_frequency == :annual || return false
        report.unit == :millions_usd || return false
        report.price_basis == :producers_prices || return false
        report.policies == expected_policies() || return false
        report.flags == expected_flags() || return false
        isempty(report.emitted_runtime_keys) || return false
        report.forbidden_runtime_keys == EXPECTED_FORBIDDEN_RUNTIME_KEYS ||
            return false
        all(
            blocker -> blocker in report.promotion_blockers,
            EXPECTED_BOUNDARY_BLOCKERS,
        ) || return false
        length(unique(report.promotion_blockers)) ==
            length(report.promotion_blockers) ||
            return false
        report.promotion_ready && return false
    catch
        return false
    end
    return true
end

function _build_closure_boundary_candidate(
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        official_market_share_directory =
            DEFAULT_OFFICIAL_MARKET_SHARE_DIRECTORY,
        adapter_contract_path = DEFAULT_ADAPTER_CONTRACT_PATH,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
        final_use_contract_path = DEFAULT_FINAL_USE_CONTRACT_PATH,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    validated = validate_contract(
        contract_path,
        after_directory,
        official_market_share_directory,
        adapter_contract_path,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
        final_use_contract_path,
        supply_directory,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    adapter = build_producer_price_adapter_candidate(
        adapter_contract_path;
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
    official =
        load_official_direct_requirements_fixture(official_market_share_directory)
    official.year == fixture.year == adapter.year ||
        throw(ArgumentError("closure-boundary source years differ"))
    source_industry_codes = copy(fixture.producer_make.row_codes)
    source_ordinary_codes = filter(
        code -> !(code in EXPECTED_CLOSURE_CODES),
        fixture.producer_make.column_codes,
    )
    source_ordinary_codes == source_industry_codes ||
        throw(ArgumentError("ordinary commodity and industry codes differ"))
    isempty(intersect(Set(adapter.model_codes), Set(EXPECTED_CLOSURE_CODES))) ||
        throw(ArgumentError("closure accounts entered the 68-sector core"))
    isempty(
        intersect(Set(source_industry_codes), Set(EXPECTED_CLOSURE_CODES)),
    ) || throw(ArgumentError("closure accounts entered the producer axis"))

    specs = validated.contract["closure_account"]
    used = build_ledger(fixture, official.market_shares, specs[1])
    other = build_ledger(fixture, official.market_shares, specs[2])
    nonscrap = build_nonscrap_witness(
        fixture,
        official.market_shares,
        used,
        other,
    )
    core_identity_omission =
        adapter.closure_omission_witness.core_signed_total
    full_identity_gap =
        adapter.closure_omission_witness.full_signed_total

    report_stub = (
        adapter_closure_intermediate_use =
            adapter.closure_intermediate_use,
        adapter_closure_final_use = adapter.closure_final_use,
        adapter_closure_make = adapter.closure_producer_make,
        adapter_core_intermediate_use = adapter.core_intermediate_use,
        source_industry_mapping = adapter.source_industry_mapping,
        model_codes = adapter.model_codes,
        core_identity_omission = core_identity_omission,
        full_identity_gap = full_identity_gap,
    )
    residuals =
        build_residuals(used, other, nonscrap, report_stub)
    blockers =
        unique(vcat(EXPECTED_BOUNDARY_BLOCKERS, adapter.promotion_blockers))
    report = ClosureBoundaryCandidateReport(
        fixture.year,
        source_industry_codes,
        source_ordinary_codes,
        copy(adapter.model_codes),
        copy(EXPECTED_CLOSURE_CODES),
        copy(adapter.source_industry_mapping),
        used,
        other,
        nonscrap,
        adapter.core_intermediate_use,
        adapter.closure_intermediate_use,
        adapter.closure_final_use,
        adapter.closure_producer_make,
        core_identity_omission,
        full_identity_gap,
        residuals,
        negative_cells(nonscrap.official_core_market_shares),
        negative_cells(nonscrap.diagnostic_nonscrap_transform),
        validated.contract_sha256,
        copy(EXPECTED_BYTE_PINS),
        String(validated.after_manifest["status"]),
        String(validated.methodology["status"]),
        :typed_closure_boundary_candidate_only,
        :annual,
        :millions_usd,
        :producers_prices,
        expected_policies(),
        expected_flags(),
        String[],
        copy(EXPECTED_FORBIDDEN_RUNTIME_KEYS),
        blockers,
        false,
    )
    closure_boundary_candidate_internal_controls_pass(report) ||
        throw(ArgumentError("closure-boundary internal controls do not pass"))
    return report
end

"""
    closure_boundary_candidate_controls_pass(
        report,
        contract_path;
        source_paths...,
    )

Public fail-closed source-aware stale-report gate. The contract and source
paths are required; there is deliberately no report-only overload.
"""
function closure_boundary_candidate_controls_pass(
        report::ClosureBoundaryCandidateReport,
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        official_market_share_directory =
            DEFAULT_OFFICIAL_MARKET_SHARE_DIRECTORY,
        adapter_contract_path = DEFAULT_ADAPTER_CONTRACT_PATH,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
        final_use_contract_path = DEFAULT_FINAL_USE_CONTRACT_PATH,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    closure_boundary_candidate_internal_controls_pass(report) ||
        return false
    try
        expected = _build_closure_boundary_candidate(
            contract_path;
            after_directory,
            official_market_share_directory,
            adapter_contract_path,
            model_mapping_path,
            sector_mapping_path,
            valuation_contract_path,
            final_use_contract_path,
            supply_directory,
            methodology_pdf_path,
            methodology_receipt_path,
        )
        return structurally_equal(report, expected)
    catch
        return false
    end
end

"""
    build_closure_boundary_candidate(contract_path; source_paths...)

Build the source-aware closure-boundary report and require both internal and
canonical-source controls.
"""
function build_closure_boundary_candidate(
        contract_path;
        after_directory = DEFAULT_AFTER_FIXTURE_DIRECTORY,
        official_market_share_directory =
            DEFAULT_OFFICIAL_MARKET_SHARE_DIRECTORY,
        adapter_contract_path = DEFAULT_ADAPTER_CONTRACT_PATH,
        model_mapping_path = DEFAULT_MODEL_MAPPING_PATH,
        sector_mapping_path = DEFAULT_SECTOR_MAPPING_PATH,
        valuation_contract_path = DEFAULT_VALUATION_CONTRACT_PATH,
        final_use_contract_path = DEFAULT_FINAL_USE_CONTRACT_PATH,
        supply_directory = DEFAULT_SUPPLY_FIXTURE_DIRECTORY,
        methodology_pdf_path = DEFAULT_METHODOLOGY_PDF_PATH,
        methodology_receipt_path = DEFAULT_METHODOLOGY_RECEIPT_PATH,
    )
    report = _build_closure_boundary_candidate(
        contract_path;
        after_directory,
        official_market_share_directory,
        adapter_contract_path,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
        final_use_contract_path,
        supply_directory,
        methodology_pdf_path,
        methodology_receipt_path,
    )
    closure_boundary_candidate_controls_pass(
        report,
        contract_path;
        after_directory,
        official_market_share_directory,
        adapter_contract_path,
        model_mapping_path,
        sector_mapping_path,
        valuation_contract_path,
        final_use_contract_path,
        supply_directory,
        methodology_pdf_path,
        methodology_receipt_path,
    ) || throw(ArgumentError("closure-boundary source controls do not pass"))
    return report
end

"""
    materialize_closure_boundary_model_state(report)

The candidate has no state-materialization path. Used and Other require
price/quantity, quarterly, financial, observation, and behavioral boundaries
before any runtime mapping can be considered.
"""
function materialize_closure_boundary_model_state(
        ::ClosureBoundaryCandidateReport,
    )
    throw(
        ArgumentError(
            "closure-boundary candidate is diagnostic only; no 70-account technology or runtime state is admissible",
        ),
    )
end

end
