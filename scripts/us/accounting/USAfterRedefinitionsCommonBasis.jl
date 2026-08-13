module USAfterRedefinitionsCommonBasis

using CSV
using LinearAlgebra
using SHA
using Statistics
using TOML

using ..USSupplyMakeDiagnostics:
    AxisBasis,
    CommodityBasis,
    ControlResidual,
    EXPLICIT_CLOSURE_CODES,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector,
    published_rounding_tolerance
using ..USSymmetricSupplyUse: NegativeCell, negative_cells
using ..USRequirementsDiagnostics:
    OfficialDirectRequirementsProvenance,
    OfficialDirectRequirementsReport,
    requirements_controls_pass

export AfterRedefinitionsFixture,
    AfterRedefinitionsProvenance,
    CommonBasisReport,
    CommonBasisComparisonReport,
    ValuationBenchmarkReport,
    FinalUseBasis,
    RecipientBasis,
    AfterRedefinitionsValueAddedBasis,
    CommonBasisDifferenceCell,
    load_after_redefinitions_fixture,
    build_common_basis_report,
    compare_official_direct_common_basis,
    common_basis_controls_pass,
    common_basis_comparison_controls_pass,
    valuation_controls_pass

struct FinalUseBasis <: AxisBasis end
struct RecipientBasis <: AxisBasis end
struct AfterRedefinitionsValueAddedBasis <: AxisBasis end

const RETAIL_SOURCE_CODES = Set(["441", "445", "452", "4A0"])
const NUMERICAL_TOLERANCE_MILLIONS_USD = 1.0e-6
const PUBLISHED_COEFFICIENT_ROUNDING_UNIT = 1.0e-7
const FIXTURE_SCHEMA =
    "beforeit-us-after-redefinitions-common-basis-fixture.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_FIXTURE_SHA256 =
    "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac"
const APPROVED_MANIFEST_SHA256 =
    "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030"
const APPROVED_SOURCE_ZIP_SHA256 =
    "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
const APPROVED_SOURCE_METADATA_SHA256 =
    "8be9fbef6e2c18a7388cd61bd14312159fc3984d4dbc2c60158e977ee7f0e878"
const APPROVED_PRODUCER_USE_WORKBOOK_SHA256 =
    "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7"
const APPROVED_PRODUCER_MAKE_WORKBOOK_SHA256 =
    "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6"
const APPROVED_IMPORT_WORKBOOK_SHA256 =
    "9246c68288bb593495366288b9d8fd2038cae1ff500855ccd3e5c4377d0d3b25"
const APPROVED_PURCHASER_USE_WORKBOOK_SHA256 =
    "9d55530ec5cd4688855ef474c779d0dba5f2e1e74d4fcfcdc95cddc64c69262b"
const APPROVED_FIXTURE_CELL_COUNT = 32_443
const APPROVED_SELECTED_ZERO_COUNT = 16_016
const APPROVED_EXPLICIT_NUMERIC_ZERO_COUNT = 819
const APPROVED_NEGATIVE_CELL_COUNT = 321
const APPROVED_SOURCE_URL =
    "https://apps.bea.gov/industry/release/zip/" *
    "MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip"
const APPROVED_SOURCE_RETRIEVED_AT_UTC = "2026-08-06T05:03:02.322Z"
const APPROVED_PRODUCER_USE_MEMBER =
    "IOUse_After_Redefinitions_PRO_Summary.xlsx"
const APPROVED_PRODUCER_MAKE_MEMBER =
    "IOMake_After_Redefinitions_PRO_Summary.xlsx"
const APPROVED_IMPORT_MEMBER =
    "ImportMatrices_After_Redefinitions_Summary.xlsx"
const APPROVED_PURCHASER_USE_MEMBER =
    "IOUse_After_Redefinitions_PUR_Summary.xlsx"
const APPROVED_PRESERVATION_POLICY =
    "Every projected source cell is retained. BEA ellipsis markers are " *
    "numeric zero with source_cell_kind=selected_zero_not_shown; published " *
    "numeric zero remains source_cell_kind=numeric. Negative cells, F030, " *
    "Other, and Used are not clipped, balanced, allocated, or dropped."
const APPROVED_SCIENTIFIC_ROLE =
    "Current-vintage common-basis accounting diagnostic. The 2017 " *
    "purchaser/producer pair is a historical valuation benchmark, not a " *
    "2024 allocator and not forecast-origin evidence."
const FIXTURE_COLUMNS = [
    "matrix_id",
    "year",
    "row_position",
    "row_code",
    "row_description",
    "row_type",
    "column_position",
    "column_code",
    "column_description",
    "column_type",
    "value",
    "source_cell_kind",
]

const PROJECTION_SPECS = [
    (
        matrix_id = "benchmark_producer_final_use_2017",
        year = 2017,
        rows = 73,
        columns = 20,
        row_type = "Commodity",
        column_type = "FinalUse",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges =
            ["2017!A8:B80", "2017!BW6:CP7", "2017!BW8:CP80"],
        projection_sha256 =
            "4bc19b6085b3fc3e7e791af9d783adc4ddde1feb3248f62e45d6612ec9f38cd3",
    ),
    (
        matrix_id = "benchmark_producer_grand_output_2017",
        year = 2017,
        rows = 1,
        columns = 1,
        row_type = "Control",
        column_type = "Control",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2017!CR86"],
        projection_sha256 =
            "6238ba2b7ee337975af4b6de67d552d4263195f1e85f8442b4929abb6813d7c3",
    ),
    (
        matrix_id = "benchmark_producer_intermediate_use_2017",
        year = 2017,
        rows = 73,
        columns = 71,
        row_type = "Commodity",
        column_type = "Industry",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2017!A8:B80", "2017!C6:BU7", "2017!C8:BU80"],
        projection_sha256 =
            "90e2ebde55a75ccf57ba61ceda120dd64e51077adf8d325c46cad1973d08f795",
    ),
    (
        matrix_id = "benchmark_purchaser_final_use_2017",
        year = 2017,
        rows = 70,
        columns = 20,
        row_type = "Commodity",
        column_type = "FinalUse",
        source_member = "IOUse_After_Redefinitions_PUR_Summary.xlsx",
        source_ranges =
            ["2017!A8:B77", "2017!BW6:CP7", "2017!BW8:CP77"],
        projection_sha256 =
            "fb315aa628c22da80c174f6c4cd4d046b3ae1d678099a233d0ceca31dbcf23fc",
    ),
    (
        matrix_id = "benchmark_purchaser_grand_output_2017",
        year = 2017,
        rows = 1,
        columns = 1,
        row_type = "Control",
        column_type = "Control",
        source_member = "IOUse_After_Redefinitions_PUR_Summary.xlsx",
        source_ranges = ["2017!CR83"],
        projection_sha256 =
            "8e06e3798bb9c838045741185f80d80800779a06377ae7a762a473fb9dcff028",
    ),
    (
        matrix_id = "benchmark_purchaser_intermediate_use_2017",
        year = 2017,
        rows = 70,
        columns = 71,
        row_type = "Commodity",
        column_type = "Industry",
        source_member = "IOUse_After_Redefinitions_PUR_Summary.xlsx",
        source_ranges = ["2017!A8:B77", "2017!C6:BU7", "2017!C8:BU77"],
        projection_sha256 =
            "1c1fbc215923869cbe9893d9bdedb9e1da4229237980720d2c8159706258c5bd",
    ),
    (
        matrix_id = "import_commodity_controls_2024",
        year = 2024,
        rows = 73,
        columns = 2,
        row_type = "Commodity",
        column_type = "Control",
        source_member = "ImportMatrices_After_Redefinitions_Summary.xlsx",
        source_ranges =
            ["2024!A8:B80", "2024!BV8:BV80", "2024!CQ8:CQ80"],
        projection_sha256 =
            "4cb90198a12d4d3587aabb3a4f8fe0da6a9e34606dcce5344412e49da603b5cb",
    ),
    (
        matrix_id = "import_final_use_2024",
        year = 2024,
        rows = 73,
        columns = 20,
        row_type = "Commodity",
        column_type = "FinalUse",
        source_member = "ImportMatrices_After_Redefinitions_Summary.xlsx",
        source_ranges =
            ["2024!A8:B80", "2024!BW6:CP7", "2024!BW8:CP80"],
        projection_sha256 =
            "fc9880daed7aafe40c804f969cc6d61c1d08d5d8ed6613ed8bd657fd8d834224",
    ),
    (
        matrix_id = "import_intermediate_use_2024",
        year = 2024,
        rows = 73,
        columns = 71,
        row_type = "Commodity",
        column_type = "Industry",
        source_member = "ImportMatrices_After_Redefinitions_Summary.xlsx",
        source_ranges = ["2024!A8:B80", "2024!C6:BU7", "2024!C8:BU80"],
        projection_sha256 =
            "36151c03db3c3c33fc170324c4ef19805aade5be7f7655b3ea5ff3c91a198443",
    ),
    (
        matrix_id = "producer_final_use_2024",
        year = 2024,
        rows = 73,
        columns = 20,
        row_type = "Commodity",
        column_type = "FinalUse",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges =
            ["2024!A8:B80", "2024!BW6:CP7", "2024!BW8:CP80"],
        projection_sha256 =
            "205d6c126efc27ba07e89b262e27f81f9bcb7200d679ce039a5aaa7a889e6fbb",
    ),
    (
        matrix_id = "producer_intermediate_use_2024",
        year = 2024,
        rows = 73,
        columns = 71,
        row_type = "Commodity",
        column_type = "Industry",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2024!A8:B80", "2024!C6:BU7", "2024!C8:BU80"],
        projection_sha256 =
            "4a8b361fc8c635602df6cedd0f3d7e728933105e37eaddbebabc8ce1925173f4",
    ),
    (
        matrix_id = "producer_make_2024",
        year = 2024,
        rows = 71,
        columns = 73,
        row_type = "Industry",
        column_type = "Commodity",
        source_member = "IOMake_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2024!A8:B78", "2024!C6:BW7", "2024!C8:BW78"],
        projection_sha256 =
            "5c80053d4e1803e05f5ad597daa4f7511e6ab68e4b07c45e48678c09ed8c63d4",
    ),
    (
        matrix_id = "producer_make_commodity_output_2024",
        year = 2024,
        rows = 73,
        columns = 1,
        row_type = "Commodity",
        column_type = "Control",
        source_member = "IOMake_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2024!C6:BW7", "2024!C79:BW79"],
        projection_sha256 =
            "012e85bbb74764355347c4c556a70d34f1385effef21577a2abdda86c34d2833",
    ),
    (
        matrix_id = "producer_make_grand_output_2024",
        year = 2024,
        rows = 1,
        columns = 1,
        row_type = "Control",
        column_type = "Control",
        source_member = "IOMake_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2024!BX79"],
        projection_sha256 =
            "40e681ab0dd8c8461dcbbcc5b885649fb816db9d0fefdc9d1b8459a739d21cf9",
    ),
    (
        matrix_id = "producer_make_industry_output_2024",
        year = 2024,
        rows = 71,
        columns = 1,
        row_type = "Industry",
        column_type = "Control",
        source_member = "IOMake_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2024!A8:B78", "2024!BX8:BX78"],
        projection_sha256 =
            "9ce864bb432c097172e22f735ab6c659eff9a2d91f34ce6803aea0545de368e0",
    ),
    (
        matrix_id = "producer_use_commodity_controls_2024",
        year = 2024,
        rows = 73,
        columns = 3,
        row_type = "Commodity",
        column_type = "Control",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges =
            ["2024!A8:B80", "2024!BV8:BV80", "2024!CQ8:CR80"],
        projection_sha256 =
            "ef577965059370abc16db5b339dc357ababe37e52c25b0d1a36c32046db95a6e",
    ),
    (
        matrix_id = "producer_use_grand_controls_2024",
        year = 2024,
        rows = 1,
        columns = 23,
        row_type = "Control",
        column_type = "Control",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = [
            "2024!BV81",
            "2024!BW6:CP7",
            "2024!BW86:CP86",
            "2024!CQ85",
            "2024!CR86",
        ],
        projection_sha256 =
            "58bfe4bda5de0d8725d25ad148dea197cd6a4eb724c1a47e4e6e0da481fbfeef",
    ),
    (
        matrix_id = "producer_use_industry_controls_2024",
        year = 2024,
        rows = 3,
        columns = 71,
        row_type = "Control",
        column_type = "Industry",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2024!C6:BU7", "2024!C81:BU81", "2024!C85:BU86"],
        projection_sha256 =
            "efdd23571e57016a1234bf0ddf6924c16a763b626aac8f6ccd16e4acce04d54b",
    ),
    (
        matrix_id = "producer_value_added_2024",
        year = 2024,
        rows = 3,
        columns = 71,
        row_type = "ValueAdded",
        column_type = "Industry",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        source_ranges = ["2024!A82:B84", "2024!C6:BU7", "2024!C82:BU84"],
        projection_sha256 =
            "81cd3d1443357f1fad597bd329616deaabc15b435960ca2354ad4a8d047e20bb",
    ),
]

"""
Immutable source identities for the current-vintage after-redefinitions
diagnostic. The ZIP, acquisition receipt, four member workbooks, canonical
fixture, and manifest retain distinct hashes.
"""
struct AfterRedefinitionsProvenance
    source_url::String
    source_zip_sha256::String
    source_metadata_sha256::String
    producer_use_workbook_sha256::String
    producer_make_workbook_sha256::String
    import_workbook_sha256::String
    purchaser_use_workbook_sha256::String
    fixture_sha256::String
    manifest_sha256::String
    spreadsheet_reader_version::String
end

"""
Canonical projection of BEA's after-redefinitions workbooks.

The 2024 blocks retain producer-price use, make, value-added, final-use, and
separate import-allocation cells and controls. The 2017 blocks retain both
producer- and purchaser-price benchmark use tables. A false `explicit` bit
means the source workbook contained BEA's `...` marker ("selected data with
zero values are not shown"); a numeric source zero remains explicit.
"""
struct AfterRedefinitionsFixture
    year::Int
    benchmark_year::Int
    producer_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    producer_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    producer_value_added::LabeledMatrix{
        AfterRedefinitionsValueAddedBasis,
        IndustryBasis,
    }
    producer_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    producer_intermediate_row_controls::LabeledVector{CommodityBasis}
    producer_final_row_controls::LabeledVector{CommodityBasis}
    producer_commodity_output_use::LabeledVector{CommodityBasis}
    producer_intermediate_column_controls::LabeledVector{IndustryBasis}
    producer_value_added_column_controls::LabeledVector{IndustryBasis}
    producer_industry_output_use::LabeledVector{IndustryBasis}
    producer_commodity_output_make::LabeledVector{CommodityBasis}
    producer_industry_output_make::LabeledVector{IndustryBasis}
    producer_intermediate_grand_control::Float64
    producer_final_use_column_controls::LabeledVector{FinalUseBasis}
    producer_value_added_grand_control::Float64
    producer_output_grand_control::Float64
    producer_make_output_grand_control::Float64
    import_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    import_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    import_intermediate_row_controls::LabeledVector{CommodityBasis}
    import_final_row_controls::LabeledVector{CommodityBasis}
    benchmark_producer_intermediate_use::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    benchmark_producer_final_use::LabeledMatrix{
        CommodityBasis,
        FinalUseBasis,
    }
    benchmark_purchaser_intermediate_use::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    benchmark_purchaser_final_use::LabeledMatrix{
        CommodityBasis,
        FinalUseBasis,
    }
    benchmark_producer_grand_output::Float64
    benchmark_purchaser_grand_output::Float64
    source_explicit::Dict{String, BitMatrix}
    commodity_descriptions::Dict{String, String}
    industry_descriptions::Dict{String, String}
    final_use_descriptions::Dict{String, String}
    provenance::AfterRedefinitionsProvenance
    manifest::Dict{String, Any}
end

"""
2017 producer-to-purchaser valuation benchmark after the four published retail
commodity rows in the producer table are explicitly aggregated to the
purchaser table's `4A0` row.

The signed difference is `purchaser - producer`. It measures a historical
valuation redistribution. It is not a 2024 margin/tax allocator.
"""
struct ValuationBenchmarkReport
    year::Int
    producer_use::LabeledMatrix{CommodityBasis, RecipientBasis}
    purchaser_use::LabeledMatrix{CommodityBasis, RecipientBasis}
    purchaser_minus_producer::LabeledMatrix{CommodityBasis, RecipientBasis}
    recipient_total_difference::LabeledVector{RecipientBasis}
    residuals::Vector{ControlResidual}
    producer_total::Float64
    purchaser_total::Float64
    producer_published_total::Float64
    purchaser_published_total::Float64
    published_total_difference::Float64
    signed_total_difference::Float64
    absolute_cell_difference::Float64
    frobenius_difference::Float64
    cell_correlation::Float64
    negative_producer_cells::Vector{NegativeCell}
    negative_purchaser_cells::Vector{NegativeCell}
    negative_difference_cells::Vector{NegativeCell}
    retail_aggregation::Dict{String, String}
    valuation_bridge_applied::Bool
    balancing_applied::Bool
    clipping_applied::Bool
    promotion_blockers::Vector{String}
    promotion_ready::Bool
end

"""
Common producer-price 2024 make/use system.

`B_implied = U * diag(g)^(-1)`, `D_implied = V * diag(q)^(-1)`, and
`Z = U * diag(g)^(-1) * V`, where `U` is commodity-by-industry producer-price
intermediate use and `V` is industry-by-commodity make. All divisions and
matrix products are code-keyed before being materialized.
"""
struct CommonBasisReport
    year::Int
    producer_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    producer_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    producer_value_added::LabeledMatrix{
        AfterRedefinitionsValueAddedBasis,
        IndustryBasis,
    }
    producer_make::LabeledMatrix{IndustryBasis, CommodityBasis}
    commodity_output::LabeledVector{CommodityBasis}
    industry_output::LabeledVector{IndustryBasis}
    implied_direct_by_industry::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    implied_market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    product_mix::LabeledMatrix{IndustryBasis, CommodityBasis}
    symmetric_intermediate_use::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    inventory_change_flow::LabeledVector{CommodityBasis}
    inventory_change_flow_explicit::BitVector
    import_intermediate_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    import_final_use::LabeledMatrix{CommodityBasis, FinalUseBasis}
    import_f050_offset::LabeledVector{CommodityBasis}
    import_f050_explicit::BitVector
    import_allocation_excluding_f050_total::Float64
    import_f050_total::Float64
    import_net_total::Float64
    valuation_benchmark::ValuationBenchmarkReport
    residuals::Vector{ControlResidual}
    negative_intermediate_use_cells::Vector{NegativeCell}
    negative_make_cells::Vector{NegativeCell}
    negative_symmetric_cells::Vector{NegativeCell}
    negative_import_cells::Vector{NegativeCell}
    negative_import_f050_cells::Vector{NegativeCell}
    negative_import_allocation_cells::Vector{NegativeCell}
    explicit_closure_codes::Vector{String}
    provenance::AfterRedefinitionsProvenance
    source_status::String
    transformation::Symbol
    price_basis::Symbol
    import_role::Symbol
    import_sign_convention::Symbol
    source_rounding_unit_millions_usd::Float64
    domestic_use_subtraction_applied::Bool
    valuation_bridge_applied::Bool
    balancing_applied::Bool
    clipping_applied::Bool
    model_state_write::Bool
    accounting_gate_effect::Symbol
    promotion_blockers::Vector{String}
    promotion_ready::Bool
end

struct CommonBasisDifferenceCell
    row_code::String
    column_code::String
    source_value::Float64
    published_value::Float64
    difference::Float64
end

"""
Comparison of the common producer-price source system with BEA's separately
published after-redefinitions direct-requirements (`B`) and market-share (`D`)
workbooks.

The transaction difference is `source U*diag(g)^(-1)*V -
published B*D*diag(q)`. These products share the same BEA I-O system and are
not independent validation data.
"""
struct CommonBasisComparisonReport
    year::Int
    source_direct_by_industry::LabeledMatrix{CommodityBasis, IndustryBasis}
    published_direct_by_industry::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    direct_coefficient_difference::LabeledMatrix{
        CommodityBasis,
        IndustryBasis,
    }
    source_market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    published_market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    market_share_difference::LabeledMatrix{IndustryBasis, CommodityBasis}
    source_transactions::LabeledMatrix{CommodityBasis, CommodityBasis}
    published_transactions::LabeledMatrix{CommodityBasis, CommodityBasis}
    transaction_difference::LabeledMatrix{CommodityBasis, CommodityBasis}
    residuals::Vector{ControlResidual}
    maximum_direct_coefficient_difference::Float64
    absolute_direct_coefficient_difference::Float64
    direct_coefficient_rmse::Float64
    maximum_market_share_difference::Float64
    absolute_market_share_difference::Float64
    market_share_rmse::Float64
    signed_transaction_total_difference::Float64
    absolute_transaction_cell_difference::Float64
    transaction_frobenius_difference::Float64
    transaction_cell_correlation::Float64
    maximum_absolute_transaction_difference_cell::CommonBasisDifferenceCell
    source_total::Float64
    published_total::Float64
    direct_interval_failure_count::Int
    market_share_interval_failure_count::Int
    maximum_direct_interval_ratio::Float64
    maximum_market_share_interval_ratio::Float64
    maximum_transaction_rounding_bound_ratio::Float64
    common_provenance::AfterRedefinitionsProvenance
    official_provenance::OfficialDirectRequirementsProvenance
    common_source_status::String
    official_source_status::String
    comparison_role::Symbol
    valuation_bridge_applied::Bool
    balancing_applied::Bool
    clipping_applied::Bool
    model_state_write::Bool
    accounting_gate_effect::Symbol
    promotion_blockers::Vector{String}
    promotion_ready::Bool
end

function scale_aware_close(lhs, rhs; atol = 1.0e-12, rtol = 1.0e-12)
    size(lhs) == size(rhs) || return false
    scale = max(1.0, maximum(abs, lhs), maximum(abs, rhs))
    return maximum(abs, lhs - rhs) <= atol + rtol * scale
end

function valuation_controls_pass(report::ValuationBenchmarkReport)
    all(residual.passed for residual in report.residuals) || return false
    any(
        (
            report.valuation_bridge_applied,
            report.balancing_applied,
            report.clipping_applied,
            report.promotion_ready,
        ),
    ) && return false
    try
        producer = report.producer_use.values
        purchaser = aligned_values(
            report.purchaser_use,
            report.producer_use.row_codes,
            report.producer_use.column_codes,
        )
        difference = aligned_values(
            report.purchaser_minus_producer,
            report.producer_use.row_codes,
            report.producer_use.column_codes,
        )
        scale_aware_close(purchaser - producer, difference) || return false
        isapprox(
            report.producer_total,
            sum(producer);
            atol = 1.0e-8,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.purchaser_total,
            sum(purchaser);
            atol = 1.0e-8,
            rtol = 1.0e-12,
        ) || return false
        report.published_total_difference ==
            report.purchaser_published_total -
            report.producer_published_total || return false
        isapprox(
            report.signed_total_difference,
            sum(difference);
            atol = 1.0e-8,
            rtol = 1.0e-12,
        ) || return false
    catch
        return false
    end
    return true
end

function common_basis_controls_pass(report::CommonBasisReport)
    all(residual.passed for residual in report.residuals) || return false
    valuation_controls_pass(report.valuation_benchmark) || return false
    report.source_status == EXPECTED_STATUS || return false
    report.provenance.fixture_sha256 == APPROVED_FIXTURE_SHA256 ||
        return false
    report.provenance.manifest_sha256 == APPROVED_MANIFEST_SHA256 ||
        return false
    any(
        (
            report.domestic_use_subtraction_applied,
            report.valuation_bridge_applied,
            report.balancing_applied,
            report.clipping_applied,
            report.model_state_write,
            report.promotion_ready,
        ),
    ) && return false
    report.accounting_gate_effect == :none || return false
    try
        commodities = report.producer_intermediate_use.row_codes
        industries = report.producer_intermediate_use.column_codes
        final_uses = report.producer_final_use.column_codes
        U = aligned_values(
            report.producer_intermediate_use,
            commodities,
            industries,
        )
        F = aligned_values(
            report.producer_final_use,
            commodities,
            final_uses,
        )
        V = aligned_values(report.producer_make, industries, commodities)
        q = aligned_vector_values(report.commodity_output, commodities)
        g = aligned_vector_values(report.industry_output, industries)
        all(value -> isfinite(value) && value > 0, q) || return false
        all(value -> isfinite(value) && value > 0, g) || return false
        source_B = U ./ reshape(g, 1, :)
        source_D = V ./ reshape(q, 1, :)
        source_product_mix = V ./ reshape(g, :, 1)
        source_Z = U * source_product_mix
        scale_aware_close(
            source_B,
            aligned_values(
                report.implied_direct_by_industry,
                commodities,
                industries,
            ),
        ) || return false
        scale_aware_close(
            source_D,
            aligned_values(
                report.implied_market_shares,
                industries,
                commodities,
            ),
        ) || return false
        scale_aware_close(
            source_product_mix,
            aligned_values(
                report.product_mix,
                industries,
                commodities,
            ),
        ) || return false
        scale_aware_close(
            source_Z,
            aligned_values(
                report.symmetric_intermediate_use,
                commodities,
                commodities,
            );
            atol = 1.0e-8,
        ) || return false
        f030_position = something(findfirst(==("F030"), final_uses))
        aligned_vector_values(
            report.inventory_change_flow,
            commodities,
        ) == F[:, f030_position] || return false
        producer_final_explicit = aligned_explicit(
            report.producer_final_use,
            commodities,
            final_uses,
        )
        report.inventory_change_flow_explicit ==
            producer_final_explicit[:, f030_position] || return false
        imports_U = aligned_values(
            report.import_intermediate_use,
            commodities,
            industries,
        )
        imports_F = aligned_values(
            report.import_final_use,
            commodities,
            final_uses,
        )
        f050_position = something(findfirst(==("F050"), final_uses))
        import_f050 = imports_F[:, f050_position]
        aligned_vector_values(report.import_f050_offset, commodities) ==
            import_f050 || return false
        import_final_explicit = aligned_explicit(
            report.import_final_use,
            commodities,
            final_uses,
        )
        report.import_f050_explicit ==
            import_final_explicit[:, f050_position] || return false
        isapprox(
            report.import_allocation_excluding_f050_total,
            sum(imports_U) + sum(imports_F) - sum(import_f050);
            atol = 1.0e-8,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.import_f050_total,
            sum(import_f050);
            atol = 1.0e-8,
            rtol = 1.0e-12,
        ) || return false
        isapprox(
            report.import_net_total,
            sum(imports_U) + sum(imports_F);
            atol = 1.0e-8,
            rtol = 1.0e-12,
        ) || return false
    catch
        return false
    end
    return true
end

function common_basis_comparison_controls_pass(
        report::CommonBasisComparisonReport,
    )
    all(residual.passed for residual in report.residuals) || return false
    report.direct_interval_failure_count == 0 || return false
    report.market_share_interval_failure_count == 0 || return false
    report.maximum_direct_interval_ratio <= 1 || return false
    report.maximum_market_share_interval_ratio <= 1 || return false
    report.maximum_transaction_rounding_bound_ratio <= 1 || return false
    report.common_source_status == EXPECTED_STATUS || return false
    report.official_source_status == EXPECTED_STATUS || return false
    report.common_provenance.fixture_sha256 == APPROVED_FIXTURE_SHA256 ||
        return false
    any(
        (
            report.valuation_bridge_applied,
            report.balancing_applied,
            report.clipping_applied,
            report.model_state_write,
            report.promotion_ready,
        ),
    ) && return false
    report.accounting_gate_effect == :none || return false
    try
        commodities = report.source_direct_by_industry.row_codes
        industries = report.source_direct_by_industry.column_codes
        source_B = report.source_direct_by_industry.values
        published_B = aligned_values(
            report.published_direct_by_industry,
            commodities,
            industries,
        )
        direct_difference = aligned_values(
            report.direct_coefficient_difference,
            commodities,
            industries,
        )
        scale_aware_close(source_B - published_B, direct_difference) ||
            return false
        source_D = aligned_values(
            report.source_market_shares,
            industries,
            commodities,
        )
        published_D = aligned_values(
            report.published_market_shares,
            industries,
            commodities,
        )
        market_difference = aligned_values(
            report.market_share_difference,
            industries,
            commodities,
        )
        scale_aware_close(source_D - published_D, market_difference) ||
            return false
        source_Z = aligned_values(
            report.source_transactions,
            commodities,
            commodities,
        )
        published_Z = aligned_values(
            report.published_transactions,
            commodities,
            commodities,
        )
        transaction_difference = aligned_values(
            report.transaction_difference,
            commodities,
            commodities,
        )
        scale_aware_close(
            source_Z - published_Z,
            transaction_difference;
            atol = 1.0e-8,
        ) || return false
    catch
        return false
    end
    return true
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

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

function aligned_values(matrix::LabeledMatrix, row_codes, column_codes)
    Set(matrix.row_codes) == Set(row_codes) ||
        throw(ArgumentError("matrix row codes do not match the requested axis"))
    Set(matrix.column_codes) == Set(column_codes) ||
        throw(ArgumentError("matrix column codes do not match the requested axis"))
    return [
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

function coefficient_reconstruction_tolerance(output, repeated_count)
    count = Int(repeated_count)
    count >= 1 ||
        throw(ArgumentError("coefficient repetition count must be positive"))
    all(value -> isfinite(value) && value >= 0, output) ||
        throw(ArgumentError("coefficient output controls must be nonnegative"))
    source_cell_rounding = length(output) * count / 2
    coefficient_rounding =
        PUBLISHED_COEFFICIENT_ROUNDING_UNIT *
        count *
        sum(output) /
        2
    return source_cell_rounding + coefficient_rounding
end

function ratio_interval(numerator, denominator)
    denominator > 0.5 ||
        throw(ArgumentError("rounded output control is too close to zero"))
    numerator_bounds = (Float64(numerator) - 0.5, Float64(numerator) + 0.5)
    denominator_bounds =
        (Float64(denominator) - 0.5, Float64(denominator) + 0.5)
    candidates = Float64[
        numerator_value / denominator_value for
            numerator_value in numerator_bounds for
            denominator_value in denominator_bounds
    ]
    return extrema(candidates)
end

function coefficient_interval_tolerance(
        source_center,
        source_lower,
        source_upper,
        published_center,
    )
    published_radius = PUBLISHED_COEFFICIENT_ROUNDING_UNIT / 2
    if source_center >= published_center
        return source_center - source_lower + published_radius
    end
    return source_upper - source_center + published_radius
end

function bounded_ratio(residual, tolerance)
    tolerance > 0 ||
        return residual == 0 ? 0.0 : Inf
    return abs(residual) / tolerance
end

function validate_axis_equality(lhs, rhs, label)
    lhs_codes = String.(lhs)
    rhs_codes = String.(rhs)
    length(lhs_codes) == length(unique(lhs_codes)) ||
        throw(ArgumentError("$label left axis contains duplicate codes"))
    length(rhs_codes) == length(unique(rhs_codes)) ||
        throw(ArgumentError("$label right axis contains duplicate codes"))
    Set(lhs_codes) == Set(rhs_codes) ||
        throw(ArgumentError("$label code sets differ"))
    return nothing
end

function validate_fixture(fixture::AfterRedefinitionsFixture)
    validate_manifest(fixture.manifest)
    fixture.year == 2024 ||
        throw(ArgumentError("common-basis fixture must use 2024"))
    fixture.benchmark_year == 2017 ||
        throw(ArgumentError("valuation benchmark must use 2017"))

    commodities = fixture.producer_intermediate_use.row_codes
    industries = fixture.producer_intermediate_use.column_codes
    final_uses = fixture.producer_final_use.column_codes
    validate_axis_equality(
        fixture.producer_final_use.row_codes,
        commodities,
        "producer-use commodity",
    )
    validate_axis_equality(
        fixture.producer_make.column_codes,
        commodities,
        "producer make/use commodity",
    )
    validate_axis_equality(
        fixture.producer_make.row_codes,
        industries,
        "producer make/use industry",
    )
    validate_axis_equality(
        fixture.producer_value_added.column_codes,
        industries,
        "value-added/use industry",
    )
    validate_axis_equality(
        fixture.import_intermediate_use.row_codes,
        commodities,
        "import/use commodity",
    )
    validate_axis_equality(
        fixture.import_intermediate_use.column_codes,
        industries,
        "import/use industry",
    )
    validate_axis_equality(
        fixture.import_final_use.row_codes,
        commodities,
        "import/final-use commodity",
    )
    validate_axis_equality(
        fixture.import_final_use.column_codes,
        final_uses,
        "import/producer final-use",
    )
    for vector in (
            fixture.producer_intermediate_row_controls,
            fixture.producer_final_row_controls,
            fixture.producer_commodity_output_use,
            fixture.producer_commodity_output_make,
            fixture.import_intermediate_row_controls,
            fixture.import_final_row_controls,
        )
        validate_axis_equality(vector.codes, commodities, "commodity control")
    end
    validate_axis_equality(
        fixture.producer_final_use_column_controls.codes,
        final_uses,
        "final-use column control",
    )
    for vector in (
            fixture.producer_intermediate_column_controls,
            fixture.producer_value_added_column_controls,
            fixture.producer_industry_output_use,
            fixture.producer_industry_output_make,
        )
        validate_axis_equality(vector.codes, industries, "industry control")
    end
    Set(fixture.producer_value_added.row_codes) ==
        Set(["V001", "V002", "V003"]) ||
        throw(ArgumentError("unexpected value-added rows"))
    all(code -> code in commodities, EXPLICIT_CLOSURE_CODES) ||
        throw(ArgumentError("common-basis fixture omits Other or Used"))
    "F030" in final_uses ||
        throw(ArgumentError("common-basis fixture omits F030 inventories"))
    "F050" in final_uses ||
        throw(ArgumentError("common-basis fixture omits F050 import offset"))
    length(commodities) == 73 ||
        throw(ArgumentError("common-basis commodity count changed"))
    length(industries) == 71 ||
        throw(ArgumentError("common-basis industry count changed"))
    length(final_uses) == 20 ||
        throw(ArgumentError("common-basis final-use count changed"))

    all(>(0), fixture.producer_commodity_output_make.values) ||
        throw(ArgumentError("producer commodity outputs must be positive"))
    all(>(0), fixture.producer_industry_output_make.values) ||
        throw(ArgumentError("producer industry outputs must be positive"))
    all(
        value -> isfinite(value) && value > 0,
        (
            fixture.producer_intermediate_grand_control,
            fixture.producer_value_added_grand_control,
            fixture.producer_output_grand_control,
            fixture.producer_make_output_grand_control,
            fixture.benchmark_producer_grand_output,
            fixture.benchmark_purchaser_grand_output,
        ),
    ) || throw(ArgumentError("published grand controls must be positive"))

    manifest = fixture.manifest
    get(manifest, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("common-basis fixture cannot be origin admissible"))
    get(manifest, "model_state_write", true) === false ||
        throw(ArgumentError("common-basis fixture cannot write model state"))
    get(manifest, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("common-basis fixture cannot affect accounting gates"))
    get(manifest, "promotion_status", "") == "RESEARCH_ONLY_NOT_PROMOTED" ||
        throw(ArgumentError("common-basis fixture cannot claim promotion"))
    provenance = fixture.provenance
    provenance.source_url == String(manifest["source_url"]) ||
        throw(ArgumentError("fixture source URL provenance changed"))
    provenance.source_zip_sha256 ==
        String(manifest["source_zip_sha256"]) ||
        throw(ArgumentError("fixture source ZIP provenance changed"))
    provenance.source_metadata_sha256 ==
        String(manifest["source_metadata_sha256"]) ||
        throw(ArgumentError("fixture source metadata provenance changed"))
    provenance.producer_use_workbook_sha256 ==
        String(manifest["producer_use_workbook_sha256"]) ||
        throw(ArgumentError("fixture producer-use provenance changed"))
    provenance.producer_make_workbook_sha256 ==
        String(manifest["producer_make_workbook_sha256"]) ||
        throw(ArgumentError("fixture producer-make provenance changed"))
    provenance.import_workbook_sha256 ==
        String(manifest["import_workbook_sha256"]) ||
        throw(ArgumentError("fixture import provenance changed"))
    provenance.purchaser_use_workbook_sha256 ==
        String(manifest["purchaser_use_workbook_sha256"]) ||
        throw(ArgumentError("fixture purchaser-use provenance changed"))
    provenance.fixture_sha256 == String(manifest["fixture_sha256"]) ||
        throw(ArgumentError("fixture canonical provenance changed"))
    provenance.manifest_sha256 == APPROVED_MANIFEST_SHA256 ||
        throw(ArgumentError("fixture manifest provenance changed"))
    provenance.spreadsheet_reader_version ==
        String(manifest["artifact_tool_version"]) ||
        throw(ArgumentError("fixture reader provenance changed"))
    Set(keys(fixture.source_explicit)) ==
        Set(spec.matrix_id for spec in PROJECTION_SPECS) ||
        throw(ArgumentError("fixture source-kind projections changed"))
    for spec in PROJECTION_SPECS
        size(fixture.source_explicit[spec.matrix_id]) ==
            (spec.rows, spec.columns) ||
            throw(ArgumentError("$(spec.matrix_id) source-kind shape changed"))
    end
    for (matrix_id, matrix) in (
            "producer_intermediate_use_2024" =>
                fixture.producer_intermediate_use,
            "producer_final_use_2024" => fixture.producer_final_use,
            "producer_value_added_2024" => fixture.producer_value_added,
            "producer_make_2024" => fixture.producer_make,
            "import_intermediate_use_2024" => fixture.import_intermediate_use,
            "import_final_use_2024" => fixture.import_final_use,
            "benchmark_producer_intermediate_use_2017" =>
                fixture.benchmark_producer_intermediate_use,
            "benchmark_producer_final_use_2017" =>
                fixture.benchmark_producer_final_use,
            "benchmark_purchaser_intermediate_use_2017" =>
                fixture.benchmark_purchaser_intermediate_use,
            "benchmark_purchaser_final_use_2017" =>
                fixture.benchmark_purchaser_final_use,
        )
        fixture.source_explicit[matrix_id] == matrix.explicit ||
            throw(ArgumentError("$matrix_id source-kind mask diverged"))
    end

    benchmark_industries =
        fixture.benchmark_producer_intermediate_use.column_codes
    benchmark_final_uses = fixture.benchmark_producer_final_use.column_codes
    validate_axis_equality(
        fixture.benchmark_purchaser_intermediate_use.column_codes,
        benchmark_industries,
        "benchmark industry",
    )
    validate_axis_equality(
        fixture.benchmark_purchaser_final_use.column_codes,
        benchmark_final_uses,
        "benchmark final-use",
    )
    validate_axis_equality(
        benchmark_final_uses,
        final_uses,
        "2017/2024 final-use",
    )
    length(fixture.benchmark_producer_intermediate_use.row_codes) == 73 ||
        throw(ArgumentError("benchmark producer commodity count changed"))
    length(fixture.benchmark_purchaser_intermediate_use.row_codes) == 70 ||
        throw(ArgumentError("benchmark purchaser commodity count changed"))
    return nothing
end

function retail_mapping(source_codes, target_codes)
    targets = Set(String.(target_codes))
    mapping = Dict{String, String}()
    for source in String.(source_codes)
        target = source in RETAIL_SOURCE_CODES ? "4A0" : source
        target in targets ||
            throw(ArgumentError("benchmark retail mapping lacks target $target"))
        mapping[source] = target
    end
    Set(values(mapping)) == targets ||
        throw(ArgumentError("benchmark retail mapping does not cover targets"))
    return mapping
end

function aggregate_rows(
        matrix::LabeledMatrix{CommodityBasis, C},
        target_codes,
        mapping,
    ) where {C <: AxisBasis}
    target_index =
        Dict(String(code) => position for (position, code) in pairs(target_codes))
    values = zeros(length(target_codes), length(matrix.column_codes))
    explicit = falses(size(values))
    for (source_position, source_code) in pairs(matrix.row_codes)
        target_position = target_index[mapping[source_code]]
        values[target_position, :] .+= matrix.values[source_position, :]
        explicit[target_position, :] .|=
            matrix.explicit[source_position, :]
    end
    return LabeledMatrix{CommodityBasis, C}(
        target_codes,
        matrix.column_codes,
        values,
        explicit,
    )
end

function combine_recipients(intermediate, final_use)
    validate_axis_equality(
        intermediate.row_codes,
        final_use.row_codes,
        "intermediate/final-use commodity",
    )
    recipient_codes = vcat(
        intermediate.column_codes,
        final_use.column_codes,
    )
    length(unique(recipient_codes)) == length(recipient_codes) ||
        throw(ArgumentError("recipient codes are not unique"))
    return LabeledMatrix{CommodityBasis, RecipientBasis}(
        intermediate.row_codes,
        recipient_codes,
        hcat(
            intermediate.values,
            aligned_values(
                final_use,
                intermediate.row_codes,
                final_use.column_codes,
            ),
        ),
        hcat(
            intermediate.explicit,
            aligned_explicit(
                final_use,
                intermediate.row_codes,
                final_use.column_codes,
            ),
        ),
    )
end

function build_valuation_benchmark(fixture::AfterRedefinitionsFixture)
    target_codes =
        copy(fixture.benchmark_purchaser_intermediate_use.row_codes)
    mapping = retail_mapping(
        fixture.benchmark_producer_intermediate_use.row_codes,
        target_codes,
    )
    producer_intermediate = aggregate_rows(
        fixture.benchmark_producer_intermediate_use,
        target_codes,
        mapping,
    )
    producer_final = aggregate_rows(
        fixture.benchmark_producer_final_use,
        target_codes,
        mapping,
    )
    producer = combine_recipients(producer_intermediate, producer_final)
    purchaser = combine_recipients(
        fixture.benchmark_purchaser_intermediate_use,
        fixture.benchmark_purchaser_final_use,
    )
    validate_axis_equality(
        purchaser.row_codes,
        producer.row_codes,
        "benchmark commodity",
    )
    validate_axis_equality(
        purchaser.column_codes,
        producer.column_codes,
        "benchmark recipient",
    )
    purchaser = LabeledMatrix{CommodityBasis, RecipientBasis}(
        producer.row_codes,
        producer.column_codes,
        aligned_values(
            purchaser,
            producer.row_codes,
            producer.column_codes,
        ),
        aligned_explicit(
            purchaser,
            producer.row_codes,
            producer.column_codes,
        ),
    )

    difference_values = purchaser.values - producer.values
    recipient_difference = vec(sum(difference_values; dims = 1))
    residuals = ControlResidual[]
    column_tolerance = (
        length(fixture.benchmark_producer_intermediate_use.row_codes) +
            length(fixture.benchmark_purchaser_intermediate_use.row_codes)
    ) / 2
    for (position, code) in pairs(producer.column_codes)
        add_residual!(
            residuals,
            :benchmark_recipient_total_conservation,
            code,
            "sum(purchaser uses) = sum(aggregated producer uses)",
            sum(purchaser.values[:, position]),
            sum(producer.values[:, position]),
            column_tolerance,
        )
    end
    add_residual!(
        residuals,
        :benchmark_producer_published_grand_total,
        "grand_total",
        "sum(aggregated producer cells) = published producer grand total",
        sum(producer.values),
        fixture.benchmark_producer_grand_output,
        published_rounding_tolerance(length(producer.values)),
    )
    add_residual!(
        residuals,
        :benchmark_purchaser_published_grand_total,
        "grand_total",
        "sum(purchaser cells) = published purchaser grand total",
        sum(purchaser.values),
        fixture.benchmark_purchaser_grand_output,
        published_rounding_tolerance(length(purchaser.values)),
    )
    add_residual!(
        residuals,
        :benchmark_published_grand_total_conservation,
        "grand_total",
        "published purchaser grand total = published producer grand total",
        fixture.benchmark_purchaser_grand_output,
        fixture.benchmark_producer_grand_output,
        published_rounding_tolerance(1),
    )

    difference = derived_matrix(
        CommodityBasis,
        RecipientBasis,
        producer.row_codes,
        producer.column_codes,
        difference_values,
    )
    return ValuationBenchmarkReport(
        fixture.benchmark_year,
        producer,
        purchaser,
        difference,
        LabeledVector{RecipientBasis}(
            producer.column_codes,
            recipient_difference,
        ),
        residuals,
        sum(producer.values),
        sum(purchaser.values),
        fixture.benchmark_producer_grand_output,
        fixture.benchmark_purchaser_grand_output,
        fixture.benchmark_purchaser_grand_output -
            fixture.benchmark_producer_grand_output,
        sum(difference_values),
        sum(abs, difference_values),
        norm(difference_values),
        cor(vec(producer.values), vec(purchaser.values)),
        negative_cells(producer),
        negative_cells(purchaser),
        negative_cells(difference),
        mapping,
        false,
        false,
        false,
        [
            "2017_BENCHMARK_IS_NOT_A_2024_VALUATION_ALLOCATOR",
            "MARGIN_TAX_SUBSIDY_COMPONENTS_NOT_SEPARATELY_IDENTIFIED",
            "OTHER_USED_NOT_ALLOCATED_TO_MODEL_CORE",
        ],
        false,
    )
end

function add_2024_source_controls!(
        residuals,
        fixture,
        U,
        F,
        VA,
        V,
        imports_U,
        imports_F,
        commodity_codes,
        industry_codes,
    )
    intermediate_rows = vec(sum(U; dims = 2))
    final_rows = vec(sum(F; dims = 2))
    intermediate_columns = vec(sum(U; dims = 1))
    final_columns = vec(sum(F; dims = 1))
    value_added_columns = vec(sum(VA; dims = 1))
    make_industry_rows = vec(sum(V; dims = 2))
    make_commodity_columns = vec(sum(V; dims = 1))
    import_intermediate_rows = vec(sum(imports_U; dims = 2))
    import_final_rows = vec(sum(imports_F; dims = 2))

    for (position, code) in pairs(commodity_codes)
        add_residual!(
            residuals,
            :producer_intermediate_row_control,
            code,
            "sum(industry intermediate uses) = published total intermediate",
            intermediate_rows[position],
            fixture.producer_intermediate_row_controls[code],
            published_rounding_tolerance(length(industry_codes)),
        )
        add_residual!(
            residuals,
            :producer_final_row_control,
            code,
            "sum(final uses) = published total final use",
            final_rows[position],
            fixture.producer_final_row_controls[code],
            published_rounding_tolerance(
                length(fixture.producer_final_use.column_codes),
            ),
        )
        add_residual!(
            residuals,
            :producer_commodity_output_control,
            code,
            "total intermediate + total final use = commodity output",
            fixture.producer_intermediate_row_controls[code] +
                fixture.producer_final_row_controls[code],
            fixture.producer_commodity_output_use[code],
            published_rounding_tolerance(2),
        )
        add_residual!(
            residuals,
            :producer_make_commodity_control,
            code,
            "sum(industry make) = make-table commodity output",
            make_commodity_columns[position],
            fixture.producer_commodity_output_make[code],
            published_rounding_tolerance(length(industry_codes)),
        )
        add_residual!(
            residuals,
            :producer_use_make_commodity_control,
            code,
            "use-table commodity output = make-table commodity output",
            fixture.producer_commodity_output_use[code],
            fixture.producer_commodity_output_make[code],
            published_rounding_tolerance(1),
        )
        add_residual!(
            residuals,
            :import_intermediate_row_control,
            code,
            "sum(industry import uses) = published import intermediate control",
            import_intermediate_rows[position],
            fixture.import_intermediate_row_controls[code],
            published_rounding_tolerance(length(industry_codes)),
        )
        add_residual!(
            residuals,
            :import_final_row_control,
            code,
            "sum(final import uses) = published import final control",
            import_final_rows[position],
            fixture.import_final_row_controls[code],
            published_rounding_tolerance(
                length(fixture.import_final_use.column_codes),
            ),
        )
        add_residual!(
            residuals,
            :import_published_offset_control,
            code,
            "published import total intermediate + total final use = 0",
            fixture.import_intermediate_row_controls[code] +
                fixture.import_final_row_controls[code],
            0.0,
            published_rounding_tolerance(1),
        )
        add_residual!(
            residuals,
            :import_cell_offset_control,
            code,
            "sum(import allocations including signed F050 offset) = 0",
            import_intermediate_rows[position] +
                import_final_rows[position],
            0.0,
            published_rounding_tolerance(
                length(industry_codes) +
                    length(fixture.import_final_use.column_codes) - 1,
            ),
        )
    end

    for (position, code) in pairs(industry_codes)
        add_residual!(
            residuals,
            :producer_intermediate_column_control,
            code,
            "sum(commodity intermediate uses) = published industry intermediate",
            intermediate_columns[position],
            fixture.producer_intermediate_column_controls[code],
            published_rounding_tolerance(length(commodity_codes)),
        )
        add_residual!(
            residuals,
            :producer_value_added_column_control,
            code,
            "sum(value-added components) = published total value added",
            value_added_columns[position],
            fixture.producer_value_added_column_controls[code],
            published_rounding_tolerance(size(VA, 1)),
        )
        add_residual!(
            residuals,
            :producer_industry_output_control,
            code,
            "total intermediate + total value added = industry output",
            fixture.producer_intermediate_column_controls[code] +
                fixture.producer_value_added_column_controls[code],
            fixture.producer_industry_output_use[code],
            published_rounding_tolerance(2),
        )
        add_residual!(
            residuals,
            :producer_make_industry_control,
            code,
            "sum(commodity make) = make-table industry output",
            make_industry_rows[position],
            fixture.producer_industry_output_make[code],
            published_rounding_tolerance(length(commodity_codes)),
        )
        add_residual!(
            residuals,
            :producer_use_make_industry_control,
            code,
            "use-table industry output = make-table industry output",
            fixture.producer_industry_output_use[code],
            fixture.producer_industry_output_make[code],
            published_rounding_tolerance(1),
        )
    end
    for (position, code) in pairs(fixture.producer_final_use.column_codes)
        add_residual!(
            residuals,
            :producer_final_use_column_control,
            code,
            "sum(commodity final uses) = published final-use column total",
            final_columns[position],
            fixture.producer_final_use_column_controls[code],
            published_rounding_tolerance(length(commodity_codes)),
        )
    end
    add_residual!(
        residuals,
        :producer_intermediate_row_grand_control,
        "grand_total",
        "sum(commodity intermediate controls) = published intermediate grand total",
        sum(fixture.producer_intermediate_row_controls.values),
        fixture.producer_intermediate_grand_control,
        published_rounding_tolerance(length(commodity_codes)),
    )
    add_residual!(
        residuals,
        :producer_intermediate_column_grand_control,
        "grand_total",
        "sum(industry intermediate controls) = published intermediate grand total",
        sum(fixture.producer_intermediate_column_controls.values),
        fixture.producer_intermediate_grand_control,
        published_rounding_tolerance(length(industry_codes)),
    )
    add_residual!(
        residuals,
        :producer_final_row_grand_control,
        "grand_total",
        "sum(commodity final-use controls) = published value-added grand total",
        sum(fixture.producer_final_row_controls.values),
        fixture.producer_value_added_grand_control,
        published_rounding_tolerance(length(commodity_codes)),
    )
    add_residual!(
        residuals,
        :producer_final_column_grand_control,
        "grand_total",
        "sum(final-use column controls) = published value-added grand total",
        sum(fixture.producer_final_use_column_controls.values),
        fixture.producer_value_added_grand_control,
        published_rounding_tolerance(
            length(fixture.producer_final_use_column_controls.codes),
        ),
    )
    add_residual!(
        residuals,
        :producer_value_added_grand_control,
        "grand_total",
        "sum(industry value-added controls) = published value-added grand total",
        sum(fixture.producer_value_added_column_controls.values),
        fixture.producer_value_added_grand_control,
        published_rounding_tolerance(length(industry_codes)),
    )
    add_residual!(
        residuals,
        :producer_use_grand_output_identity,
        "grand_total",
        "published intermediate plus value added = published use-table output",
        fixture.producer_intermediate_grand_control +
            fixture.producer_value_added_grand_control,
        fixture.producer_output_grand_control,
        published_rounding_tolerance(2),
    )
    add_residual!(
        residuals,
        :producer_make_commodity_grand_control,
        "grand_total",
        "sum(make-table commodity controls) = published make-table output",
        sum(fixture.producer_commodity_output_make.values),
        fixture.producer_make_output_grand_control,
        published_rounding_tolerance(length(commodity_codes)),
    )
    add_residual!(
        residuals,
        :producer_make_industry_grand_control,
        "grand_total",
        "sum(make-table industry controls) = published make-table output",
        sum(fixture.producer_industry_output_make.values),
        fixture.producer_make_output_grand_control,
        published_rounding_tolerance(length(industry_codes)),
    )
    add_residual!(
        residuals,
        :producer_use_make_grand_output_control,
        "grand_total",
        "published use-table output = published make-table output",
        fixture.producer_output_grand_control,
        fixture.producer_make_output_grand_control,
        published_rounding_tolerance(1),
    )
    aggregate_control_tolerance =
        (length(commodity_codes) + length(industry_codes)) / 2
    add_residual!(
        residuals,
        :producer_gdp_approach_control,
        "grand_total",
        "sum(commodity final-use controls) = sum(industry value added)",
        sum(fixture.producer_final_row_controls.values),
        sum(fixture.producer_value_added_column_controls.values),
        aggregate_control_tolerance,
    )
    add_residual!(
        residuals,
        :producer_output_approach_control,
        "grand_total",
        "sum(make-table commodity output) = sum(make-table industry output)",
        sum(fixture.producer_commodity_output_make.values),
        sum(fixture.producer_industry_output_make.values),
        aggregate_control_tolerance,
    )
    return residuals
end

"""
    build_common_basis_report(fixture)

Build the source-preserving common producer-price diagnostic. No cell is
clipped, balanced, allocated, or written to model state.
"""
function build_common_basis_report(fixture::AfterRedefinitionsFixture)
    validate_fixture(fixture)
    commodity_codes = copy(fixture.producer_intermediate_use.row_codes)
    industry_codes = copy(fixture.producer_intermediate_use.column_codes)
    final_use_codes = copy(fixture.producer_final_use.column_codes)

    U = aligned_values(
        fixture.producer_intermediate_use,
        commodity_codes,
        industry_codes,
    )
    F = aligned_values(
        fixture.producer_final_use,
        commodity_codes,
        final_use_codes,
    )
    VA = aligned_values(
        fixture.producer_value_added,
        fixture.producer_value_added.row_codes,
        industry_codes,
    )
    V = aligned_values(
        fixture.producer_make,
        industry_codes,
        commodity_codes,
    )
    imports_U = aligned_values(
        fixture.import_intermediate_use,
        commodity_codes,
        industry_codes,
    )
    imports_F = aligned_values(
        fixture.import_final_use,
        commodity_codes,
        final_use_codes,
    )
    producer_final_explicit = aligned_explicit(
        fixture.producer_final_use,
        commodity_codes,
        final_use_codes,
    )
    import_final_explicit = aligned_explicit(
        fixture.import_final_use,
        commodity_codes,
        final_use_codes,
    )
    q = aligned_vector_values(
        fixture.producer_commodity_output_make,
        commodity_codes,
    )
    g = aligned_vector_values(
        fixture.producer_industry_output_make,
        industry_codes,
    )

    direct_values = U ./ reshape(g, 1, :)
    market_share_values = V ./ reshape(q, 1, :)
    product_mix_values = V ./ reshape(g, :, 1)
    symmetric_values = U * product_mix_values
    f030_position = something(findfirst(==("F030"), final_use_codes))

    direct = derived_matrix(
        CommodityBasis,
        IndustryBasis,
        commodity_codes,
        industry_codes,
        direct_values,
    )
    market = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        industry_codes,
        commodity_codes,
        market_share_values,
    )
    product_mix = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        industry_codes,
        commodity_codes,
        product_mix_values,
    )
    symmetric = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        commodity_codes,
        commodity_codes,
        symmetric_values,
    )

    residuals = ControlResidual[]
    add_2024_source_controls!(
        residuals,
        fixture,
        U,
        F,
        VA,
        V,
        imports_U,
        imports_F,
        commodity_codes,
        industry_codes,
    )
    for (position, code) in pairs(industry_codes)
        add_residual!(
            residuals,
            :product_mix_normalization,
            code,
            "sum(V industry product mix / g) = 1, within source rounding",
            sum(product_mix_values[position, :]),
            1.0,
            published_rounding_tolerance(length(commodity_codes)) /
                g[position],
        )
    end
    for (position, code) in pairs(commodity_codes)
        add_residual!(
            residuals,
            :market_share_normalization,
            code,
            "sum(V commodity market shares / q) = 1, within source rounding",
            sum(market_share_values[:, position]),
            1.0,
            published_rounding_tolerance(length(industry_codes)) /
                q[position],
        )
    end
    symmetric_rows = vec(sum(symmetric_values; dims = 2))
    source_rows = vec(sum(U; dims = 2))
    for (position, code) in pairs(commodity_codes)
        propagated_tolerance = sum(
            abs.(U[position, :]) .*
                (
                published_rounding_tolerance(
                    length(commodity_codes),
                ) ./
                    g
            ),
        )
        add_residual!(
            residuals,
            :symmetric_intermediate_row_conservation,
            code,
            "sum(U * diag(g)^(-1) * V) = sum(U), within source rounding",
            symmetric_rows[position],
            source_rows[position],
            propagated_tolerance,
        )
    end

    negative_imports = vcat(
        negative_cells(fixture.import_intermediate_use),
        negative_cells(fixture.import_final_use),
    )
    import_f050_position =
        something(findfirst(==("F050"), final_use_codes))
    import_f050_values = imports_F[:, import_f050_position]
    import_f050_cells = NegativeCell[
        NegativeCell(
                commodity_codes[position],
                "F050",
                import_f050_values[position],
            ) for position in eachindex(commodity_codes) if
            import_f050_values[position] < 0
    ]
    import_allocation_negatives = vcat(
        negative_cells(fixture.import_intermediate_use),
        NegativeCell[
            NegativeCell(
                    commodity_codes[row_position],
                    final_use_codes[column_position],
                    imports_F[row_position, column_position],
                ) for row_position in eachindex(commodity_codes) for
                column_position in eachindex(final_use_codes) if
                final_use_codes[column_position] != "F050" &&
                imports_F[row_position, column_position] < 0
        ],
    )
    import_allocation_excluding_f050_total =
        sum(imports_U) + sum(imports_F) - sum(import_f050_values)
    import_net_total = sum(imports_U) + sum(imports_F)
    blockers = [
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

    return CommonBasisReport(
        fixture.year,
        fixture.producer_intermediate_use,
        fixture.producer_final_use,
        fixture.producer_value_added,
        fixture.producer_make,
        LabeledVector{CommodityBasis}(commodity_codes, q),
        LabeledVector{IndustryBasis}(industry_codes, g),
        direct,
        market,
        product_mix,
        symmetric,
        LabeledVector{CommodityBasis}(
            commodity_codes,
            F[:, f030_position],
        ),
        BitVector(producer_final_explicit[:, f030_position]),
        fixture.import_intermediate_use,
        fixture.import_final_use,
        LabeledVector{CommodityBasis}(
            commodity_codes,
            import_f050_values,
        ),
        BitVector(import_final_explicit[:, import_f050_position]),
        import_allocation_excluding_f050_total,
        sum(import_f050_values),
        import_net_total,
        build_valuation_benchmark(fixture),
        residuals,
        negative_cells(fixture.producer_intermediate_use),
        negative_cells(fixture.producer_make),
        negative_cells(symmetric),
        negative_imports,
        import_f050_cells,
        import_allocation_negatives,
        collect(EXPLICIT_CLOSURE_CODES),
        fixture.provenance,
        String(fixture.manifest["status"]),
        :after_redefinitions_producer_price_industry_technology,
        :producers_prices,
        :separate_bea_imputed_import_allocation,
        :positive_allocated_uses_plus_signed_f050_accounting_offset,
        1.0,
        false,
        false,
        false,
        false,
        false,
        :none,
        blockers,
        false,
    )
end

function difference_matrix(::Type{R}, ::Type{C}, rows, columns, lhs, rhs) where {
        R <: AxisBasis,
        C <: AxisBasis,
    }
    return derived_matrix(R, C, rows, columns, lhs - rhs)
end

"""
    compare_official_direct_common_basis(common, official)

Compare source-derived coefficients and transactions with BEA's rounded,
separately published direct-requirements and market-share workbooks on the
same 2024 after-redefinitions producer-price output basis.
"""
function compare_official_direct_common_basis(
        common::CommonBasisReport,
        official::OfficialDirectRequirementsReport,
    )
    common_basis_controls_pass(common) ||
        throw(ArgumentError("common-basis source controls do not pass"))
    requirements_controls_pass(official) ||
        throw(ArgumentError("official direct-requirements controls do not pass"))
    common.year == official.year ||
        throw(ArgumentError("common-basis comparison years differ"))
    common.source_status == EXPECTED_STATUS ||
        throw(ArgumentError("unexpected common-basis source status"))
    official.source_status == EXPECTED_STATUS ||
        throw(ArgumentError("unexpected official-direct source status"))
    official.transformation ==
        :official_after_redefinitions_direct_times_market_share ||
        throw(ArgumentError("unexpected official direct-requirements route"))
    any(
        (
            common.valuation_bridge_applied,
            common.balancing_applied,
            common.clipping_applied,
            common.model_state_write,
            common.promotion_ready,
            official.balancing_applied,
            official.clipping_applied,
            official.promotion_ready,
        ),
    ) && throw(ArgumentError("promoted or mutated inputs are not diagnostic"))

    commodities = copy(common.producer_intermediate_use.row_codes)
    industries = copy(common.producer_intermediate_use.column_codes)
    U = aligned_values(
        common.producer_intermediate_use,
        commodities,
        industries,
    )
    V = aligned_values(
        common.producer_make,
        industries,
        commodities,
    )
    q = aligned_vector_values(common.commodity_output, commodities)
    g = aligned_vector_values(common.industry_output, industries)
    all(value -> isfinite(value) && value > 0, q) ||
        throw(ArgumentError("common-basis commodity outputs are invalid"))
    all(value -> isfinite(value) && value > 0, g) ||
        throw(ArgumentError("common-basis industry outputs are invalid"))

    source_B = U ./ reshape(g, 1, :)
    source_D = V ./ reshape(q, 1, :)
    source_product_mix = V ./ reshape(g, :, 1)
    source_Z = U * source_product_mix
    stored_B = aligned_values(
        common.implied_direct_by_industry,
        commodities,
        industries,
    )
    published_B = aligned_values(
        official.direct_by_industry,
        commodities,
        industries,
    )
    stored_D = aligned_values(
        common.implied_market_shares,
        industries,
        commodities,
    )
    published_D = aligned_values(
        official.market_shares,
        industries,
        commodities,
    )
    stored_product_mix = aligned_values(
        common.product_mix,
        industries,
        commodities,
    )
    stored_Z = aligned_values(
        common.symmetric_intermediate_use,
        commodities,
        commodities,
    )
    published_Z = (published_B * published_D) .* reshape(q, 1, :)
    source_round_trip = (source_B * source_D) .* reshape(q, 1, :)
    direct_difference_values = source_B - published_B
    market_difference_values = source_D - published_D
    transaction_difference_values = source_Z - published_Z

    residuals = ControlResidual[]
    add_residual!(
        residuals,
        :source_direct_snapshot_consistency,
        "maximum_cell_error",
        "recomputed U / g = stored implied direct coefficients",
        maximum(abs, source_B - stored_B),
        0.0,
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :source_market_share_snapshot_consistency,
        "maximum_cell_error",
        "recomputed V / q = stored implied market shares",
        maximum(abs, source_D - stored_D),
        0.0,
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :source_product_mix_snapshot_consistency,
        "maximum_cell_error",
        "recomputed V / g = stored product mix",
        maximum(abs, source_product_mix - stored_product_mix),
        0.0,
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :source_transaction_snapshot_consistency,
        "maximum_cell_error",
        "recomputed U * diag(g)^(-1) * V = stored transactions",
        maximum(abs, source_Z - stored_Z),
        0.0,
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :source_common_basis_round_trip,
        "maximum_cell_error",
        "B_implied * D_implied * diag(q) = U * diag(g)^(-1) * V",
        maximum(abs, source_round_trip - source_Z),
        0.0,
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )

    direct_tolerances = zeros(size(source_B))
    direct_interval_ratios = zeros(size(source_B))
    for commodity_position in eachindex(commodities)
        for industry_position in eachindex(industries)
            source_lower, source_upper = ratio_interval(
                U[commodity_position, industry_position],
                g[industry_position],
            )
            tolerance = coefficient_interval_tolerance(
                source_B[commodity_position, industry_position],
                source_lower,
                source_upper,
                published_B[commodity_position, industry_position],
            )
            difference =
                direct_difference_values[
                commodity_position,
                industry_position,
            ]
            direct_tolerances[commodity_position, industry_position] =
                tolerance
            direct_interval_ratios[commodity_position, industry_position] =
                bounded_ratio(difference, tolerance)
            add_residual!(
                residuals,
                :direct_coefficient_rounding_interval,
                "$(commodities[commodity_position])->$(industries[industry_position])",
                "source U/g and published B rounding intervals overlap",
                source_B[commodity_position, industry_position],
                published_B[commodity_position, industry_position],
                tolerance,
            )
        end
    end

    market_tolerances = zeros(size(source_D))
    market_interval_ratios = zeros(size(source_D))
    for industry_position in eachindex(industries)
        for commodity_position in eachindex(commodities)
            source_lower, source_upper = ratio_interval(
                V[industry_position, commodity_position],
                q[commodity_position],
            )
            tolerance = coefficient_interval_tolerance(
                source_D[industry_position, commodity_position],
                source_lower,
                source_upper,
                published_D[industry_position, commodity_position],
            )
            difference =
                market_difference_values[
                industry_position,
                commodity_position,
            ]
            market_tolerances[industry_position, commodity_position] =
                tolerance
            market_interval_ratios[industry_position, commodity_position] =
                bounded_ratio(difference, tolerance)
            add_residual!(
                residuals,
                :market_share_rounding_interval,
                "$(industries[industry_position])->$(commodities[commodity_position])",
                "source V/q and published D rounding intervals overlap",
                source_D[industry_position, commodity_position],
                published_D[industry_position, commodity_position],
                tolerance,
            )
        end
    end

    transaction_rounding_bounds = (
        abs.(source_B) * market_tolerances +
            direct_tolerances * abs.(source_D) +
            direct_tolerances * market_tolerances
    ) .* reshape(q, 1, :)
    transaction_rounding_ratios = map(
        bounded_ratio,
        transaction_difference_values,
        transaction_rounding_bounds,
    )
    for (position, code) in pairs(commodities)
        add_residual!(
            residuals,
            :transaction_rounding_row_bound,
            code,
            "transaction row L1 difference is within propagated coefficient rounding",
            sum(abs, transaction_difference_values[position, :]),
            0.0,
            sum(transaction_rounding_bounds[position, :]),
        )
        add_residual!(
            residuals,
            :transaction_rounding_column_bound,
            code,
            "transaction column L1 difference is within propagated coefficient rounding",
            sum(abs, transaction_difference_values[:, position]),
            0.0,
            sum(transaction_rounding_bounds[:, position]),
        )
    end
    maximum_transaction_rounding_ratio =
        maximum(transaction_rounding_ratios)
    add_residual!(
        residuals,
        :transaction_rounding_maximum_cell_ratio,
        "maximum_cell",
        "every transaction cell is within its propagated coefficient-rounding bound",
        maximum_transaction_rounding_ratio,
        0.0,
        1.0,
    )

    reconstructed_U = published_B .* reshape(g, 1, :)
    reconstructed_V = published_D .* reshape(q, 1, :)
    add_residual!(
        residuals,
        :published_direct_intermediate_total,
        "grand_total",
        "sum(B_published * diag(g)) tracks producer U under coefficient rounding",
        sum(reconstructed_U),
        sum(common.producer_intermediate_use.values),
        coefficient_reconstruction_tolerance(g, length(commodities)),
    )
    add_residual!(
        residuals,
        :published_market_share_make_total,
        "grand_total",
        "sum(D_published * diag(q)) tracks producer V under coefficient rounding",
        sum(reconstructed_V),
        sum(common.producer_make.values),
        coefficient_reconstruction_tolerance(q, length(industries)),
    )
    add_residual!(
        residuals,
        :transaction_difference_identity,
        "grand_total",
        "sum(source) - sum(published) = sum(cell differences)",
        sum(source_Z) - sum(published_Z),
        sum(transaction_difference_values),
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )

    maximum_index = argmax(abs.(transaction_difference_values))
    maximum_cell = CommonBasisDifferenceCell(
        commodities[maximum_index[1]],
        commodities[maximum_index[2]],
        source_Z[maximum_index],
        published_Z[maximum_index],
        transaction_difference_values[maximum_index],
    )

    direct_difference = difference_matrix(
        CommodityBasis,
        IndustryBasis,
        commodities,
        industries,
        source_B,
        published_B,
    )
    market_difference = difference_matrix(
        IndustryBasis,
        CommodityBasis,
        industries,
        commodities,
        source_D,
        published_D,
    )
    transaction_difference = difference_matrix(
        CommodityBasis,
        CommodityBasis,
        commodities,
        commodities,
        source_Z,
        published_Z,
    )
    source_direct = derived_matrix(
        CommodityBasis,
        IndustryBasis,
        commodities,
        industries,
        source_B,
    )
    source_market = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        industries,
        commodities,
        source_D,
    )
    source_transactions = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        commodities,
        commodities,
        source_Z,
    )
    blockers = [
        "COMMON_BASIS_COMPARISON_IS_NOT_INDEPENDENT_VALIDATION",
        "MULTI_ARCHIVE_RELEASE_IDENTITY_NOT_EXTERNALLY_BOUND",
        "PUBLISHED_COEFFICIENTS_AND_SOURCE_CELLS_ARE_INDEPENDENTLY_ROUNDED",
        "PRODUCT_TAX_PRODUCER_TO_BASIC_ALLOCATION_NOT_PROVIDED",
        "OTHER_USED_NOT_ALLOCATED_TO_68_SECTOR_CORE",
        "NEGATIVE_CELL_POLICY_NOT_APPROVED",
        "LATENT_STATE_RECONCILIATION_NOT_APPLIED",
        "AFTER_REDEFINITIONS_FIXTURE_NOT_PROSPECTIVELY_CAPTURED",
        "CURRENT_VINTAGE_NOT_FORECAST_ORIGIN_ELIGIBLE",
    ]
    return CommonBasisComparisonReport(
        common.year,
        source_direct,
        LabeledMatrix{CommodityBasis, IndustryBasis}(
            commodities,
            industries,
            published_B,
            aligned_explicit(
                official.direct_by_industry,
                commodities,
                industries,
            ),
        ),
        direct_difference,
        source_market,
        LabeledMatrix{IndustryBasis, CommodityBasis}(
            industries,
            commodities,
            published_D,
            aligned_explicit(
                official.market_shares,
                industries,
                commodities,
            ),
        ),
        market_difference,
        source_transactions,
        derived_matrix(
            CommodityBasis,
            CommodityBasis,
            commodities,
            commodities,
            published_Z,
        ),
        transaction_difference,
        residuals,
        maximum(abs, direct_difference_values),
        sum(abs, direct_difference_values),
        sqrt(mean(abs2, direct_difference_values)),
        maximum(abs, market_difference_values),
        sum(abs, market_difference_values),
        sqrt(mean(abs2, market_difference_values)),
        sum(transaction_difference_values),
        sum(abs, transaction_difference_values),
        norm(transaction_difference_values),
        cor(vec(source_Z), vec(published_Z)),
        maximum_cell,
        sum(source_Z),
        sum(published_Z),
        count(>(1.0), direct_interval_ratios),
        count(>(1.0), market_interval_ratios),
        maximum(direct_interval_ratios),
        maximum(market_interval_ratios),
        maximum_transaction_rounding_ratio,
        common.provenance,
        official.provenance,
        common.source_status,
        official.source_status,
        :same_system_common_basis_rounding_comparator,
        false,
        false,
        false,
        false,
        :none,
        blockers,
        false,
    )
end

struct CanonicalProjection
    matrix_id::String
    year::Int
    row_codes::Vector{String}
    row_descriptions::Vector{String}
    row_type::String
    column_codes::Vector{String}
    column_descriptions::Vector{String}
    column_type::String
    values::Matrix{Float64}
    explicit::BitMatrix
end

function validate_manifest(manifest)
    get(manifest, "schema_version", "") == FIXTURE_SCHEMA ||
        throw(ArgumentError("unsupported after-redefinitions fixture schema"))
    get(manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("unexpected after-redefinitions fixture status"))
    get(manifest, "promotion_status", "") == EXPECTED_PROMOTION_STATUS ||
        throw(ArgumentError("unexpected after-redefinitions promotion status"))
    get(manifest, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("fixture cannot be forecast-origin admissible"))
    get(manifest, "model_state_write", true) === false ||
        throw(ArgumentError("fixture cannot write model state"))
    get(manifest, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("fixture cannot affect accounting gates"))
    get(manifest, "year", 0) == 2024 ||
        throw(ArgumentError("fixture current year changed"))
    get(manifest, "benchmark_year", 0) == 2017 ||
        throw(ArgumentError("fixture benchmark year changed"))
    get(manifest, "unit", "") == "millions of current dollars" ||
        throw(ArgumentError("fixture unit changed"))
    get(manifest, "use_price_basis_2024", "") == "producers prices" ||
        throw(ArgumentError("2024 producer-use price basis changed"))
    get(manifest, "use_price_basis_2017_benchmark", "") ==
        "producers and purchasers prices, separate source tables" ||
        throw(ArgumentError("2017 benchmark price basis changed"))
    get(manifest, "artifact_tool_version", "") == "2.8.39" ||
        throw(ArgumentError("spreadsheet reader version changed"))
    get(manifest, "fixture_cell_count", 0) ==
        APPROVED_FIXTURE_CELL_COUNT ||
        throw(ArgumentError("fixture cell count changed"))
    get(manifest, "selected_zero_not_shown_count", 0) ==
        APPROVED_SELECTED_ZERO_COUNT ||
        throw(ArgumentError("selected-zero count changed"))
    get(manifest, "explicit_numeric_zero_count", 0) ==
        APPROVED_EXPLICIT_NUMERIC_ZERO_COUNT ||
        throw(ArgumentError("explicit numeric-zero count changed"))
    get(manifest, "negative_cell_count", 0) ==
        APPROVED_NEGATIVE_CELL_COUNT ||
        throw(ArgumentError("negative-cell count changed"))
    get(manifest, "projection_count", 0) == length(PROJECTION_SPECS) ||
        throw(ArgumentError("projection count changed"))
    get(manifest, "source_url", "") == APPROVED_SOURCE_URL ||
        throw(ArgumentError("source URL changed"))
    get(manifest, "source_retrieved_at_utc", "") ==
        APPROVED_SOURCE_RETRIEVED_AT_UTC ||
        throw(ArgumentError("source retrieval timestamp changed"))
    get(manifest, "source_zip_byte_count", 0) == 8_326_144 ||
        throw(ArgumentError("source ZIP byte count changed"))
    get(manifest, "producer_use_workbook_member", "") ==
        APPROVED_PRODUCER_USE_MEMBER ||
        throw(ArgumentError("producer-use workbook member changed"))
    get(manifest, "producer_make_workbook_member", "") ==
        APPROVED_PRODUCER_MAKE_MEMBER ||
        throw(ArgumentError("producer-make workbook member changed"))
    get(manifest, "import_workbook_member", "") ==
        APPROVED_IMPORT_MEMBER ||
        throw(ArgumentError("import workbook member changed"))
    get(manifest, "purchaser_use_workbook_member", "") ==
        APPROVED_PURCHASER_USE_MEMBER ||
        throw(ArgumentError("purchaser-use workbook member changed"))
    get(manifest, "preservation_policy", "") ==
        APPROVED_PRESERVATION_POLICY ||
        throw(ArgumentError("fixture preservation policy changed"))
    get(manifest, "scientific_role", "") == APPROVED_SCIENTIFIC_ROLE ||
        throw(ArgumentError("fixture scientific role changed"))
    lowercase(String(get(manifest, "fixture_sha256", ""))) ==
        APPROVED_FIXTURE_SHA256 ||
        throw(ArgumentError("manifest fixture SHA-256 changed"))
    lowercase(String(get(manifest, "source_zip_sha256", ""))) ==
        APPROVED_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("source ZIP SHA-256 changed"))
    lowercase(String(get(manifest, "source_metadata_sha256", ""))) ==
        APPROVED_SOURCE_METADATA_SHA256 ||
        throw(ArgumentError("source metadata SHA-256 changed"))
    lowercase(String(get(manifest, "producer_use_workbook_sha256", ""))) ==
        APPROVED_PRODUCER_USE_WORKBOOK_SHA256 ||
        throw(ArgumentError("producer-use workbook SHA-256 changed"))
    lowercase(String(get(manifest, "producer_make_workbook_sha256", ""))) ==
        APPROVED_PRODUCER_MAKE_WORKBOOK_SHA256 ||
        throw(ArgumentError("producer-make workbook SHA-256 changed"))
    lowercase(String(get(manifest, "import_workbook_sha256", ""))) ==
        APPROVED_IMPORT_WORKBOOK_SHA256 ||
        throw(ArgumentError("import workbook SHA-256 changed"))
    lowercase(String(get(manifest, "purchaser_use_workbook_sha256", ""))) ==
        APPROVED_PURCHASER_USE_WORKBOOK_SHA256 ||
        throw(ArgumentError("purchaser-use workbook SHA-256 changed"))

    projections = get(manifest, "projection", Any[])
    length(projections) == length(PROJECTION_SPECS) ||
        throw(ArgumentError("manifest projection count changed"))
    projection_ids =
        String[String(projection["matrix_id"]) for projection in projections]
    projection_ids == sort(projection_ids) ||
        throw(ArgumentError("manifest projections are not canonical"))
    projection_ids == [spec.matrix_id for spec in PROJECTION_SPECS] ||
        throw(ArgumentError("manifest projection identifiers changed"))
    for (projection, spec) in zip(projections, PROJECTION_SPECS)
        get(projection, "year", 0) == spec.year ||
            throw(ArgumentError("$(spec.matrix_id) year changed"))
        get(projection, "row_count", 0) == spec.rows ||
            throw(ArgumentError("$(spec.matrix_id) row count changed"))
        get(projection, "column_count", 0) == spec.columns ||
            throw(ArgumentError("$(spec.matrix_id) column count changed"))
        get(projection, "cell_count", 0) == spec.rows * spec.columns ||
            throw(ArgumentError("$(spec.matrix_id) cell count changed"))
        get(projection, "row_type", "") == spec.row_type ||
            throw(ArgumentError("$(spec.matrix_id) row type changed"))
        get(projection, "column_type", "") == spec.column_type ||
            throw(ArgumentError("$(spec.matrix_id) column type changed"))
        get(projection, "source_member", "") == spec.source_member ||
            throw(ArgumentError("$(spec.matrix_id) source member changed"))
        String.(get(projection, "source_ranges", String[])) ==
            spec.source_ranges ||
            throw(ArgumentError("$(spec.matrix_id) source ranges changed"))
        lowercase(String(get(projection, "projection_sha256", ""))) ==
            spec.projection_sha256 ||
            throw(ArgumentError("$(spec.matrix_id) projection SHA-256 changed"))
    end
    return nothing
end

function materialize_projection(rows, spec)
    selected =
        [row for row in rows if String(row.matrix_id) == spec.matrix_id]
    length(selected) == spec.rows * spec.columns ||
        throw(ArgumentError("$(spec.matrix_id) fixture cell count changed"))
    all(row -> Int(row.year) == spec.year, selected) ||
        throw(ArgumentError("$(spec.matrix_id) contains another year"))
    all(row -> String(row.row_type) == spec.row_type, selected) ||
        throw(ArgumentError("$(spec.matrix_id) row type changed"))
    all(row -> String(row.column_type) == spec.column_type, selected) ||
        throw(ArgumentError("$(spec.matrix_id) column type changed"))

    row_codes = Vector{String}(undef, spec.rows)
    row_descriptions = Vector{String}(undef, spec.rows)
    for position in 1:spec.rows
        positioned =
            [row for row in selected if Int(row.row_position) == position]
        length(positioned) == spec.columns ||
            throw(ArgumentError("$(spec.matrix_id) row grid changed"))
        codes = unique(String(row.row_code) for row in positioned)
        descriptions =
            unique(String(row.row_description) for row in positioned)
        length(codes) == 1 && length(descriptions) == 1 ||
            throw(ArgumentError("$(spec.matrix_id) row metadata changed"))
        row_codes[position] = only(codes)
        row_descriptions[position] = only(descriptions)
    end
    column_codes = Vector{String}(undef, spec.columns)
    column_descriptions = Vector{String}(undef, spec.columns)
    for position in 1:spec.columns
        positioned = [
            row for row in selected if Int(row.column_position) == position
        ]
        length(positioned) == spec.rows ||
            throw(ArgumentError("$(spec.matrix_id) column grid changed"))
        codes = unique(String(row.column_code) for row in positioned)
        descriptions =
            unique(String(row.column_description) for row in positioned)
        length(codes) == 1 && length(descriptions) == 1 ||
            throw(ArgumentError("$(spec.matrix_id) column metadata changed"))
        column_codes[position] = only(codes)
        column_descriptions[position] = only(descriptions)
    end
    length(unique(row_codes)) == length(row_codes) ||
        throw(ArgumentError("$(spec.matrix_id) row codes are not unique"))
    length(unique(column_codes)) == length(column_codes) ||
        throw(ArgumentError("$(spec.matrix_id) column codes are not unique"))

    values = zeros(spec.rows, spec.columns)
    explicit = falses(size(values))
    seen = falses(size(values))
    for row in selected
        row_position = Int(row.row_position)
        column_position = Int(row.column_position)
        1 <= row_position <= spec.rows ||
            throw(ArgumentError("$(spec.matrix_id) row position is invalid"))
        1 <= column_position <= spec.columns ||
            throw(ArgumentError("$(spec.matrix_id) column position is invalid"))
        seen[row_position, column_position] &&
            throw(ArgumentError("$(spec.matrix_id) contains a duplicate cell"))
        value = Float64(row.value)
        isfinite(value) && isinteger(value) ||
            throw(ArgumentError("$(spec.matrix_id) value is not a whole million"))
        source_kind = String(row.source_cell_kind)
        source_kind in ("numeric", "selected_zero_not_shown") ||
            throw(ArgumentError("$(spec.matrix_id) source-cell kind changed"))
        if source_kind == "selected_zero_not_shown"
            value == 0.0 ||
                throw(ArgumentError("an ellipsis source cell is not zero"))
        else
            explicit[row_position, column_position] = true
        end
        values[row_position, column_position] = value
        seen[row_position, column_position] = true
    end
    all(seen) ||
        throw(ArgumentError("$(spec.matrix_id) contains an implicit grid cell"))
    return CanonicalProjection(
        spec.matrix_id,
        spec.year,
        row_codes,
        row_descriptions,
        spec.row_type,
        column_codes,
        column_descriptions,
        spec.column_type,
        values,
        explicit,
    )
end

function labeled_projection(
        ::Type{R},
        ::Type{C},
        projection::CanonicalProjection,
    ) where {R <: AxisBasis, C <: AxisBasis}
    return LabeledMatrix{R, C}(
        projection.row_codes,
        projection.column_codes,
        projection.values,
        projection.explicit,
    )
end

function matrix_column_vector(
        ::Type{B},
        projection::CanonicalProjection,
        column_code,
    ) where {B <: AxisBasis}
    position = findfirst(==(String(column_code)), projection.column_codes)
    position === nothing &&
        throw(ArgumentError("$(projection.matrix_id) lacks $column_code"))
    return LabeledVector{B}(
        projection.row_codes,
        projection.values[:, position],
    )
end

function matrix_row_vector(
        ::Type{B},
        projection::CanonicalProjection,
        row_code,
    ) where {B <: AxisBasis}
    position = findfirst(==(String(row_code)), projection.row_codes)
    position === nothing &&
        throw(ArgumentError("$(projection.matrix_id) lacks $row_code"))
    return LabeledVector{B}(
        projection.column_codes,
        projection.values[position, :],
    )
end

"""
    load_after_redefinitions_fixture(directory)

Load the byte-pinned current-vintage projection. The loader rejects changes to
the manifest, CSV, source hashes, workbook members, exact ranges, matrix
shapes, positional axes, descriptions, source-cell kinds, or fail-closed
research status.
"""
function load_after_redefinitions_fixture(directory::AbstractString)
    manifest_path = joinpath(directory, "manifest.toml")
    cells_path = joinpath(directory, "cells.csv")
    manifest_bytes = read(manifest_path)
    sha256_hex(manifest_bytes) == APPROVED_MANIFEST_SHA256 ||
        throw(ArgumentError("unexpected after-redefinitions manifest SHA-256"))
    manifest = TOML.parse(String(manifest_bytes))
    validate_manifest(manifest)
    sha256_hex(read(cells_path)) == APPROVED_FIXTURE_SHA256 ||
        throw(ArgumentError("after-redefinitions fixture SHA-256 changed"))

    table = CSV.File(
        cells_path;
        missingstring = nothing,
        types = Dict(
            :matrix_id => String,
            :year => Int,
            :row_position => Int,
            :row_code => String,
            :row_description => String,
            :row_type => String,
            :column_position => Int,
            :column_code => String,
            :column_description => String,
            :column_type => String,
            :value => Float64,
            :source_cell_kind => String,
        ),
    )
    String.(propertynames(table)) == FIXTURE_COLUMNS ||
        throw(ArgumentError("unexpected after-redefinitions fixture columns"))
    rows = collect(table)
    length(rows) == APPROVED_FIXTURE_CELL_COUNT ||
        throw(ArgumentError("after-redefinitions fixture cell count changed"))
    canonical_keys = [
        (
                String(row.matrix_id),
                Int(row.year),
                Int(row.row_position),
                Int(row.column_position),
            ) for row in rows
    ]
    canonical_keys == sort(canonical_keys) ||
        throw(ArgumentError("after-redefinitions fixture is not canonical"))
    count(
        row ->
        String(row.source_cell_kind) == "selected_zero_not_shown",
        rows,
    ) == APPROVED_SELECTED_ZERO_COUNT ||
        throw(ArgumentError("selected-zero source kinds changed"))
    count(
        row ->
        String(row.source_cell_kind) == "numeric" &&
            Float64(row.value) == 0.0,
        rows,
    ) == APPROVED_EXPLICIT_NUMERIC_ZERO_COUNT ||
        throw(ArgumentError("explicit numeric-zero source kinds changed"))
    count(row -> Float64(row.value) < 0.0, rows) ==
        APPROVED_NEGATIVE_CELL_COUNT ||
        throw(ArgumentError("fixture negative-cell count changed"))

    projections = Dict{String, CanonicalProjection}()
    for spec in PROJECTION_SPECS
        projections[spec.matrix_id] =
            materialize_projection(rows, spec)
    end

    producer_intermediate = labeled_projection(
        CommodityBasis,
        IndustryBasis,
        projections["producer_intermediate_use_2024"],
    )
    producer_final = labeled_projection(
        CommodityBasis,
        FinalUseBasis,
        projections["producer_final_use_2024"],
    )
    producer_value_added = labeled_projection(
        AfterRedefinitionsValueAddedBasis,
        IndustryBasis,
        projections["producer_value_added_2024"],
    )
    producer_make = labeled_projection(
        IndustryBasis,
        CommodityBasis,
        projections["producer_make_2024"],
    )
    import_intermediate = labeled_projection(
        CommodityBasis,
        IndustryBasis,
        projections["import_intermediate_use_2024"],
    )
    import_final = labeled_projection(
        CommodityBasis,
        FinalUseBasis,
        projections["import_final_use_2024"],
    )
    benchmark_producer_intermediate = labeled_projection(
        CommodityBasis,
        IndustryBasis,
        projections["benchmark_producer_intermediate_use_2017"],
    )
    benchmark_producer_final = labeled_projection(
        CommodityBasis,
        FinalUseBasis,
        projections["benchmark_producer_final_use_2017"],
    )
    benchmark_purchaser_intermediate = labeled_projection(
        CommodityBasis,
        IndustryBasis,
        projections["benchmark_purchaser_intermediate_use_2017"],
    )
    benchmark_purchaser_final = labeled_projection(
        CommodityBasis,
        FinalUseBasis,
        projections["benchmark_purchaser_final_use_2017"],
    )

    commodity_controls =
        projections["producer_use_commodity_controls_2024"]
    industry_controls =
        projections["producer_use_industry_controls_2024"]
    make_commodity_output =
        projections["producer_make_commodity_output_2024"]
    make_industry_output =
        projections["producer_make_industry_output_2024"]
    use_grand_controls =
        projections["producer_use_grand_controls_2024"]
    make_grand_output =
        projections["producer_make_grand_output_2024"]
    benchmark_producer_grand_output =
        projections["benchmark_producer_grand_output_2017"]
    benchmark_purchaser_grand_output =
        projections["benchmark_purchaser_grand_output_2017"]
    import_controls = projections["import_commodity_controls_2024"]
    commodity_controls.column_codes == ["T001", "T004", "T007"] ||
        throw(ArgumentError("producer commodity-control codes changed"))
    industry_controls.row_codes == ["T001", "V004", "T017"] ||
        throw(ArgumentError("producer industry-control codes changed"))
    make_commodity_output.column_codes == ["T007"] ||
        throw(ArgumentError("make commodity-output control changed"))
    make_industry_output.column_codes == ["T017"] ||
        throw(ArgumentError("make industry-output control changed"))
    use_grand_controls.row_codes == ["GrandTotal"] ||
        throw(ArgumentError("producer-use grand-control row changed"))
    use_grand_controls.column_codes ==
        vcat(["T001"], producer_final.column_codes, ["V004", "T007"]) ||
        throw(ArgumentError("producer-use grand-control columns changed"))
    make_grand_output.row_codes == ["GrandTotal"] &&
        make_grand_output.column_codes == ["T017"] ||
        throw(ArgumentError("make grand-output control changed"))
    benchmark_producer_grand_output.row_codes == ["GrandTotal"] &&
        benchmark_producer_grand_output.column_codes == ["T007"] ||
        throw(ArgumentError("producer benchmark grand control changed"))
    benchmark_purchaser_grand_output.row_codes == ["GrandTotal"] &&
        benchmark_purchaser_grand_output.column_codes == ["T007"] ||
        throw(ArgumentError("purchaser benchmark grand control changed"))
    import_controls.column_codes == ["T001", "T004"] ||
        throw(ArgumentError("import control codes changed"))

    use_projection = projections["producer_intermediate_use_2024"]
    final_projection = projections["producer_final_use_2024"]
    commodity_descriptions = Dict(
        code => description for
            (code, description) in
            zip(use_projection.row_codes, use_projection.row_descriptions)
    )
    industry_descriptions = Dict(
        code => description for
            (code, description) in zip(
                use_projection.column_codes,
                use_projection.column_descriptions,
            )
    )
    final_use_descriptions = Dict(
        code => description for
            (code, description) in zip(
                final_projection.column_codes,
                final_projection.column_descriptions,
            )
    )
    provenance = AfterRedefinitionsProvenance(
        String(manifest["source_url"]),
        String(manifest["source_zip_sha256"]),
        String(manifest["source_metadata_sha256"]),
        String(manifest["producer_use_workbook_sha256"]),
        String(manifest["producer_make_workbook_sha256"]),
        String(manifest["import_workbook_sha256"]),
        String(manifest["purchaser_use_workbook_sha256"]),
        String(manifest["fixture_sha256"]),
        APPROVED_MANIFEST_SHA256,
        String(manifest["artifact_tool_version"]),
    )
    fixture = AfterRedefinitionsFixture(
        2024,
        2017,
        producer_intermediate,
        producer_final,
        producer_value_added,
        producer_make,
        matrix_column_vector(
            CommodityBasis,
            commodity_controls,
            "T001",
        ),
        matrix_column_vector(
            CommodityBasis,
            commodity_controls,
            "T004",
        ),
        matrix_column_vector(
            CommodityBasis,
            commodity_controls,
            "T007",
        ),
        matrix_row_vector(IndustryBasis, industry_controls, "T001"),
        matrix_row_vector(IndustryBasis, industry_controls, "V004"),
        matrix_row_vector(IndustryBasis, industry_controls, "T017"),
        matrix_column_vector(
            CommodityBasis,
            make_commodity_output,
            "T007",
        ),
        matrix_column_vector(
            IndustryBasis,
            make_industry_output,
            "T017",
        ),
        use_grand_controls.values[
            use_grand_controls.row_codes .== "GrandTotal",
            use_grand_controls.column_codes .== "T001",
        ][1],
        LabeledVector{FinalUseBasis}(
            producer_final.column_codes,
            Float64[
                use_grand_controls.values[
                        use_grand_controls.row_codes .== "GrandTotal",
                        use_grand_controls.column_codes .== code,
                    ][1] for code in producer_final.column_codes
            ],
        ),
        use_grand_controls.values[
            use_grand_controls.row_codes .== "GrandTotal",
            use_grand_controls.column_codes .== "V004",
        ][1],
        use_grand_controls.values[
            use_grand_controls.row_codes .== "GrandTotal",
            use_grand_controls.column_codes .== "T007",
        ][1],
        make_grand_output.values[1, 1],
        import_intermediate,
        import_final,
        matrix_column_vector(CommodityBasis, import_controls, "T001"),
        matrix_column_vector(CommodityBasis, import_controls, "T004"),
        benchmark_producer_intermediate,
        benchmark_producer_final,
        benchmark_purchaser_intermediate,
        benchmark_purchaser_final,
        benchmark_producer_grand_output.values[1, 1],
        benchmark_purchaser_grand_output.values[1, 1],
        Dict(
            matrix_id => copy(projection.explicit) for
                (matrix_id, projection) in projections
        ),
        commodity_descriptions,
        industry_descriptions,
        final_use_descriptions,
        provenance,
        manifest,
    )
    validate_fixture(fixture)
    return fixture
end

end
