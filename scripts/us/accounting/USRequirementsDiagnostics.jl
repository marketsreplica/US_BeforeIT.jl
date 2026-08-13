module USRequirementsDiagnostics

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
    SupplyMakeReport,
    controls_pass
using ..USSymmetricSupplyUse:
    NegativeCell,
    SymmetricUseReport,
    negative_cells,
    transformation_controls_pass

export RequirementsFixture,
    OfficialDirectRequirementsFixture,
    OfficialDirectRequirementsProvenance,
    RequirementsReport,
    OfficialDirectRequirementsReport,
    RequirementsTransactionReport,
    RequirementsComparisonReport,
    SignedDifferenceCell,
    build_direct_requirements,
    build_official_direct_requirements,
    build_requirements_transactions,
    compare_structural_transactions,
    load_official_direct_requirements_fixture,
    load_requirements_fixture,
    comparison_controls_pass,
    requirements_controls_pass,
    transaction_controls_pass,
    COEFFICIENT_NUMERICAL_TOLERANCE,
    DIRECT_MATRIX_AGREEMENT_TOLERANCE,
    TOTAL_MATRIX_AGREEMENT_TOLERANCE,
    SUBSTANTIVE_NEGATIVE_THRESHOLD

const FIXTURE_SCHEMA = "beforeit-us-total-requirements-fixture.v1"
const EXPECTED_STATUS = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const EXPECTED_ACCOUNTING_GATE_EFFECT = "NONE"
const APPROVED_TABLE_ID = "59"
const APPROVED_YEAR = 2024
const APPROVED_FIXTURE_SHA256 =
    "d7285bc44bd9ee40cf51e1a7c0789fdce40b2764b438dec1c598cae81bc31b0b"
const APPROVED_MANIFEST_SHA256 =
    "2bc6040081f9a888639948fe5e5cbf13732a257ee1f62784b19d0aaea4023084"
const APPROVED_SOURCE_SHA256 =
    "f38f13ac18365fe4a68ad64fc9a6be6661b62893c3b714ee2d070cb7e0cc434d"
const APPROVED_SOURCE_METADATA_SHA256 =
    "1cc83c9eec20698bb5a31aaba81eb98dd176126c187399a4d78910c65cebf787"
const APPROVED_API_PRODUCTION_TIME = "2026-08-06T00:40:11.567Z"
const APPROVED_CELL_COUNT = 5_402
const PUBLISHED_DECIMAL_PLACES = 7
const COEFFICIENT_UNIT =
    "dollars of commodity output per dollar of commodity delivered to final use"
const COEFFICIENT_NUMERICAL_TOLERANCE = 1.0e-12
const DIRECT_MATRIX_AGREEMENT_TOLERANCE = 1.0e-6
const TOTAL_MATRIX_AGREEMENT_TOLERANCE = 2.0e-6
const TRANSACTION_NUMERICAL_TOLERANCE_MILLIONS_USD = 1.0e-6
const SUBSTANTIVE_NEGATIVE_THRESHOLD = 1.0e-6
const FIXTURE_COLUMNS = [
    "table_id",
    "year",
    "row_code",
    "row_type",
    "column_code",
    "column_type",
    "value",
]
const OFFICIAL_DIRECT_FIXTURE_SCHEMA =
    "beforeit-us-official-direct-requirements-fixture.v1"
const APPROVED_OFFICIAL_DIRECT_FIXTURE_SHA256 =
    "d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e"
const APPROVED_OFFICIAL_DIRECT_MANIFEST_SHA256 =
    "a225951d7ec03aaaaa97f5cc02e58b862e00918dbd31cc35093d80f9dde8c35d"
const APPROVED_DIRECT_SOURCE_ZIP_SHA256 =
    "e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae"
const APPROVED_DIRECT_SOURCE_METADATA_SHA256 =
    "f3f57a7209f7c6d9b0f76b041f17ae78e9da1d8644dbd7d6815471e740abfaca"
const APPROVED_DIRECT_WORKBOOK_SHA256 =
    "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439"
const APPROVED_MARKET_SHARE_WORKBOOK_SHA256 =
    "57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2"
const APPROVED_OFFICIAL_DIRECT_CELL_COUNT = 10_650
const APPROVED_COMMODITY_COUNT = 73
const APPROVED_INDUSTRY_COUNT = 71
const APPROVED_VALUE_ADDED_COUNT = 3
const OFFICIAL_DIRECT_COEFFICIENT_UNIT =
    "dimensionless producer-price after-redefinitions coefficient"
const DIRECT_MATRIX_ID = "commodity_by_industry_direct"
const MARKET_SHARE_MATRIX_ID = "industry_by_commodity_market_share"
const VALUE_ADDED_MATRIX_ID = "industry_value_added"
const INDUSTRY_CONTROL_MATRIX_ID = "industry_control_total"
const OFFICIAL_DIRECT_FIXTURE_COLUMNS = [
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
]

struct ValueAddedBasis <: AxisBasis end
struct ControlBasis <: AxisBasis end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

"""
Canonical projection of BEA Input-Output Table 59.

The matrix rows and columns are both commodities. `total_output_requirements`
is the separately published blank-code control row: the total commodity
output required per dollar delivered to final use for each column commodity.
"""
struct RequirementsFixture
    year::Int
    total_requirements::LabeledMatrix{CommodityBasis, CommodityBasis}
    total_output_requirements::LabeledVector{CommodityBasis}
    source_sha256::String
    manifest::Dict{String, Any}
end

"""
Canonical projection of BEA's directly published, after-redefinitions
commodity-by-industry requirements and industry-by-commodity market shares.

The source workbooks publish `B` on a commodity-by-industry basis and `D` on
an industry-by-commodity basis. Their product `B * D` is the directly
published route to a commodity-by-commodity coefficient matrix. The
value-added rows and industry-total row are retained as source controls.
"""
struct OfficialDirectRequirementsFixture
    year::Int
    direct_by_industry::LabeledMatrix{CommodityBasis, IndustryBasis}
    market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    value_added::LabeledMatrix{ValueAddedBasis, IndustryBasis}
    industry_totals::LabeledVector{IndustryBasis}
    source_zip_sha256::String
    direct_workbook_sha256::String
    market_share_workbook_sha256::String
    manifest::Dict{String, Any}
end

"""
Immutable identities for every byte source used by the official-direct report.

The report combines Table 59 with the direct-requirements and market-share
workbooks. Keeping those identities distinct prevents a downstream artifact
from presenting the ZIP digest as if it covered the full multi-source result.
"""
struct OfficialDirectRequirementsProvenance
    total_requirements_source_sha256::String
    total_requirements_metadata_sha256::String
    total_requirements_fixture_sha256::String
    total_requirements_manifest_sha256::String
    official_direct_source_zip_sha256::String
    official_direct_source_metadata_sha256::String
    direct_workbook_sha256::String
    market_share_workbook_sha256::String
    official_direct_fixture_sha256::String
    official_direct_manifest_sha256::String
    spreadsheet_reader_version::String
end

"""
Direct requirements implied by BEA's published total-requirements matrix.

If `L` is the published commodity-by-commodity total-requirements matrix,
the implied direct matrix is `A = I - inv(L)`. The inversion is diagnostic:
no negative value is clipped and no balancing is applied.
"""
struct RequirementsReport
    year::Int
    total_requirements::LabeledMatrix{CommodityBasis, CommodityBasis}
    total_output_requirements::LabeledVector{CommodityBasis}
    direct_requirements::LabeledMatrix{CommodityBasis, CommodityBasis}
    residuals::Vector{ControlResidual}
    negative_direct_cells::Vector{NegativeCell}
    substantive_negative_direct_cells::Vector{NegativeCell}
    condition_number::Float64
    spectral_radius::Float64
    maximum_inverse_reconstruction_error::Float64
    maximum_leontief_identity_error::Float64
    source_sha256::String
    source_status::String
    transformation::Symbol
    clipping_applied::Bool
    balancing_applied::Bool
    promotion_blockers::Vector{String}
    promotion_ready::Bool
end

"""
Official after-redefinitions direct-requirements transformation report.

`direct_requirements` is `B * D`, aligned by codes to Table 59. The
Table-59 inversion is retained separately in `inversion_implied_requirements`
as a published-rounding round-trip, not used as the primary coefficient
source. No signs are clipped and no matrix is balanced.
"""
struct OfficialDirectRequirementsReport
    year::Int
    total_requirements::LabeledMatrix{CommodityBasis, CommodityBasis}
    total_output_requirements::LabeledVector{CommodityBasis}
    direct_by_industry::LabeledMatrix{CommodityBasis, IndustryBasis}
    market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    value_added::LabeledMatrix{ValueAddedBasis, IndustryBasis}
    industry_totals::LabeledVector{IndustryBasis}
    direct_requirements::LabeledMatrix{CommodityBasis, CommodityBasis}
    inversion_implied_requirements::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    reconstructed_total_requirements::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    direct_difference::LabeledMatrix{CommodityBasis, CommodityBasis}
    residuals::Vector{ControlResidual}
    negative_direct_cells::Vector{NegativeCell}
    substantive_negative_direct_cells::Vector{NegativeCell}
    negative_direct_by_industry_cells::Vector{NegativeCell}
    negative_market_share_cells::Vector{NegativeCell}
    condition_number::Float64
    spectral_radius::Float64
    maximum_direct_agreement_error::Float64
    absolute_direct_agreement_error::Float64
    direct_agreement_rmse::Float64
    maximum_total_requirements_agreement_error::Float64
    maximum_leontief_identity_error::Float64
    provenance::OfficialDirectRequirementsProvenance
    source_status::String
    transformation::Symbol
    clipping_applied::Bool
    balancing_applied::Bool
    promotion_blockers::Vector{String}
    promotion_ready::Bool
end

"""
Output-weighted aggregation of an official direct-requirements diagnostic.

Direct coefficients cannot be added when commodities are combined. The
operator first constructs transactions `Z = A * diag(q)` from the 73 published
commodity-output controls, aggregates both transaction axes, aggregates
output, and only then recomputes 70-commodity direct coefficients.
"""
struct RequirementsTransactionReport
    year::Int
    source_commodity_output::LabeledVector{CommodityBasis}
    source_transactions::LabeledMatrix{CommodityBasis, CommodityBasis}
    commodity_output::LabeledVector{CommodityBasis}
    transactions::LabeledMatrix{CommodityBasis, CommodityBasis}
    direct_requirements::LabeledMatrix{CommodityBasis, CommodityBasis}
    commodity_mapping::Dict{String, String}
    residuals::Vector{ControlResidual}
    negative_source_transaction_cells::Vector{NegativeCell}
    negative_transaction_cells::Vector{NegativeCell}
    explicit_closure_codes::Vector{String}
    transformation::Symbol
    clipping_applied::Bool
    balancing_applied::Bool
    promotion_blockers::Vector{String}
    promotion_ready::Bool
end

"""
Largest signed cell difference between the purchasers-price symmetric-use
diagnostic and an after-redefinitions requirements transaction system.
"""
struct SignedDifferenceCell
    row_code::String
    column_code::String
    symmetric_value::Float64
    requirements_value::Float64
    difference::Float64
end

"""
Code-keyed comparison of two separately published 70-commodity transaction
diagnostics.

The difference is always `symmetric_use - requirements`. It is a
price/redefinition/system-boundary diagnostic, not a valuation bridge or a
residual that may be balanced into either source matrix.
"""
struct RequirementsComparisonReport
    year::Int
    symmetric_transactions::LabeledMatrix{CommodityBasis, CommodityBasis}
    requirements_transactions::LabeledMatrix{CommodityBasis, CommodityBasis}
    signed_difference::LabeledMatrix{CommodityBasis, CommodityBasis}
    row_difference::LabeledVector{CommodityBasis}
    column_difference::LabeledVector{CommodityBasis}
    residuals::Vector{ControlResidual}
    signed_total_difference::Float64
    absolute_cell_difference::Float64
    frobenius_difference::Float64
    cell_correlation::Float64
    maximum_absolute_difference_cell::SignedDifferenceCell
    left_basis::Symbol
    right_basis::Symbol
    comparison_role::Symbol
    valuation_bridge_applied::Bool
    balancing_applied::Bool
    clipping_applied::Bool
    promotion_blockers::Vector{String}
    promotion_ready::Bool
end

requirements_controls_pass(report::RequirementsReport) =
    all(residual.passed for residual in report.residuals)
requirements_controls_pass(report::OfficialDirectRequirementsReport) =
    all(residual.passed for residual in report.residuals)
transaction_controls_pass(report::RequirementsTransactionReport) =
    all(residual.passed for residual in report.residuals)
comparison_controls_pass(report::RequirementsComparisonReport) =
    all(residual.passed for residual in report.residuals)

function derived_matrix(row_codes, column_codes, values)
    return LabeledMatrix{CommodityBasis, CommodityBasis}(
        row_codes,
        column_codes,
        values,
        falses(size(values)),
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

function ordered_unique(values)
    result = String[]
    for value in values
        text = String(value)
        text in result || push!(result, text)
    end
    return result
end

function materialize_fixture_matrix(
        ::Type{R},
        ::Type{C},
        rows,
        matrix_id,
        expected_rows,
        expected_columns,
        expected_row_type,
        expected_column_type,
    ) where {R <: AxisBasis, C <: AxisBasis}
    selected = [row for row in rows if row.matrix_id == matrix_id]
    length(selected) == expected_rows * expected_columns ||
        throw(ArgumentError("$matrix_id has an unexpected cell count"))
    row_positions = sort!(unique(Int(row.row_position) for row in selected))
    column_positions =
        sort!(unique(Int(row.column_position) for row in selected))
    row_positions == collect(1:expected_rows) ||
        throw(ArgumentError("$matrix_id row positions are not contiguous"))
    column_positions == collect(1:expected_columns) ||
        throw(ArgumentError("$matrix_id column positions are not contiguous"))

    row_codes = Vector{String}(undef, expected_rows)
    row_descriptions = Vector{String}(undef, expected_rows)
    column_codes = Vector{String}(undef, expected_columns)
    column_descriptions = Vector{String}(undef, expected_columns)
    for position in row_positions
        position_rows = [
            row for row in selected if Int(row.row_position) == position
        ]
        codes = unique(String(row.row_code) for row in position_rows)
        descriptions =
            unique(String(row.row_description) for row in position_rows)
        types = unique(String(row.row_type) for row in position_rows)
        length(codes) == 1 ||
            throw(ArgumentError("$matrix_id row $position has multiple codes"))
        length(descriptions) == 1 ||
            throw(ArgumentError("$matrix_id row $position has multiple descriptions"))
        types == [expected_row_type] ||
            throw(ArgumentError("$matrix_id row $position has the wrong basis"))
        row_codes[position] = only(codes)
        row_descriptions[position] = only(descriptions)
    end
    for position in column_positions
        position_rows = [
            row for row in selected if Int(row.column_position) == position
        ]
        codes = unique(String(row.column_code) for row in position_rows)
        descriptions =
            unique(String(row.column_description) for row in position_rows)
        types = unique(String(row.column_type) for row in position_rows)
        length(codes) == 1 ||
            throw(ArgumentError("$matrix_id column $position has multiple codes"))
        length(descriptions) == 1 ||
            throw(
            ArgumentError(
                "$matrix_id column $position has multiple descriptions",
            ),
        )
        types == [expected_column_type] ||
            throw(ArgumentError("$matrix_id column $position has the wrong basis"))
        column_codes[position] = only(codes)
        column_descriptions[position] = only(descriptions)
    end
    length(unique(row_codes)) == length(row_codes) ||
        throw(ArgumentError("$matrix_id row codes are not unique"))
    length(unique(column_codes)) == length(column_codes) ||
        throw(ArgumentError("$matrix_id column codes are not unique"))

    values = zeros(expected_rows, expected_columns)
    explicit = falses(size(values))
    for row in selected
        row_position = Int(row.row_position)
        column_position = Int(row.column_position)
        explicit[row_position, column_position] &&
            throw(ArgumentError("$matrix_id contains a duplicate cell"))
        value = Float64(row.value)
        isfinite(value) ||
            throw(ArgumentError("$matrix_id contains a nonfinite value"))
        values[row_position, column_position] = value
        explicit[row_position, column_position] = true
    end
    all(explicit) ||
        throw(ArgumentError("$matrix_id contains an implicit cell"))

    return (
        matrix = LabeledMatrix{R, C}(
            row_codes,
            column_codes,
            values,
            explicit,
        ),
        row_descriptions = row_descriptions,
        column_descriptions = column_descriptions,
    )
end

function load_official_direct_requirements_fixture(
        directory::AbstractString,
    )
    manifest_path = joinpath(directory, "manifest.toml")
    cells_path = joinpath(directory, "cells.csv")
    manifest_bytes = read(manifest_path)
    sha256_hex(manifest_bytes) == APPROVED_OFFICIAL_DIRECT_MANIFEST_SHA256 ||
        throw(ArgumentError("unexpected official-direct manifest SHA-256"))
    manifest = TOML.parse(String(manifest_bytes))
    get(manifest, "schema_version", "") == OFFICIAL_DIRECT_FIXTURE_SCHEMA ||
        throw(ArgumentError("unsupported official-direct fixture schema"))
    get(manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("unexpected official-direct fixture status"))
    get(manifest, "promotion_status", "") == EXPECTED_PROMOTION_STATUS ||
        throw(ArgumentError("unexpected official-direct promotion status"))
    get(manifest, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("official-direct fixture cannot be origin admissible"))
    get(manifest, "accounting_gate_effect", "") ==
        EXPECTED_ACCOUNTING_GATE_EFFECT ||
        throw(ArgumentError("official-direct fixture cannot affect accounting gates"))
    get(manifest, "model_state_write", true) === false ||
        throw(ArgumentError("official-direct fixture cannot write model state"))
    get(manifest, "year", 0) == APPROVED_YEAR ||
        throw(ArgumentError("official-direct fixture has the wrong year"))
    get(manifest, "fixture_cell_count", 0) ==
        APPROVED_OFFICIAL_DIRECT_CELL_COUNT ||
        throw(ArgumentError("official-direct fixture has the wrong cell count"))
    get(manifest, "commodity_count", 0) == APPROVED_COMMODITY_COUNT ||
        throw(ArgumentError("official-direct commodity count changed"))
    get(manifest, "industry_count", 0) == APPROVED_INDUSTRY_COUNT ||
        throw(ArgumentError("official-direct industry count changed"))
    get(manifest, "value_added_count", 0) ==
        APPROVED_VALUE_ADDED_COUNT ||
        throw(ArgumentError("official-direct value-added count changed"))
    get(manifest, "published_decimal_places", 0) ==
        PUBLISHED_DECIMAL_PLACES ||
        throw(ArgumentError("official-direct coefficient precision changed"))
    get(manifest, "coefficient_unit", "") ==
        OFFICIAL_DIRECT_COEFFICIENT_UNIT ||
        throw(ArgumentError("official-direct coefficient unit changed"))
    get(manifest, "price_basis", "") == "producers' prices" ||
        throw(ArgumentError("official-direct price basis changed"))
    get(manifest, "artifact_tool_version", "") == "2.8.31" ||
        throw(ArgumentError("official-direct spreadsheet reader changed"))
    get(manifest, "direct_matrix_id", "") == DIRECT_MATRIX_ID ||
        throw(ArgumentError("official-direct matrix selector changed"))
    get(manifest, "market_share_matrix_id", "") ==
        MARKET_SHARE_MATRIX_ID ||
        throw(ArgumentError("market-share matrix selector changed"))
    get(manifest, "value_added_matrix_id", "") == VALUE_ADDED_MATRIX_ID ||
        throw(ArgumentError("value-added matrix selector changed"))
    get(manifest, "industry_control_matrix_id", "") ==
        INDUSTRY_CONTROL_MATRIX_ID ||
        throw(ArgumentError("industry-control matrix selector changed"))
    get(manifest, "direct_matrix_range", "") == "2024!C8:BU80" ||
        throw(ArgumentError("official-direct source range changed"))
    get(manifest, "market_share_matrix_range", "") == "2024!C8:BW78" ||
        throw(ArgumentError("market-share source range changed"))
    get(manifest, "value_added_range", "") == "2024!C81:BU83" ||
        throw(ArgumentError("value-added source range changed"))
    get(manifest, "direct_control_tolerance", Inf) == 3.85e-6 ||
        throw(ArgumentError("official-direct control tolerance changed"))
    get(manifest, "market_share_control_tolerance", Inf) == 3.6e-6 ||
        throw(ArgumentError("market-share control tolerance changed"))
    get(manifest, "negative_direct_cell_count", -1) == 5 ||
        throw(ArgumentError("official-direct negative-cell count changed"))
    get(manifest, "negative_market_share_cell_count", -1) == 1 ||
        throw(ArgumentError("market-share negative-cell count changed"))
    lowercase(String(manifest["fixture_sha256"])) ==
        APPROVED_OFFICIAL_DIRECT_FIXTURE_SHA256 ||
        throw(ArgumentError("unexpected official-direct fixture SHA-256"))
    lowercase(String(manifest["source_zip_sha256"])) ==
        APPROVED_DIRECT_SOURCE_ZIP_SHA256 ||
        throw(ArgumentError("unexpected official-direct ZIP SHA-256"))
    get(manifest, "source_zip_byte_count", 0) == 8_486_511 ||
        throw(ArgumentError("unexpected official-direct ZIP byte count"))
    lowercase(String(manifest["source_metadata_sha256"])) ==
        APPROVED_DIRECT_SOURCE_METADATA_SHA256 ||
        throw(ArgumentError("unexpected official-direct metadata SHA-256"))
    lowercase(String(manifest["direct_workbook_sha256"])) ==
        APPROVED_DIRECT_WORKBOOK_SHA256 ||
        throw(ArgumentError("unexpected direct-workbook SHA-256"))
    lowercase(String(manifest["market_share_workbook_sha256"])) ==
        APPROVED_MARKET_SHARE_WORKBOOK_SHA256 ||
        throw(ArgumentError("unexpected market-share-workbook SHA-256"))
    sha256_hex(read(cells_path)) == APPROVED_OFFICIAL_DIRECT_FIXTURE_SHA256 ||
        throw(ArgumentError("official-direct fixture SHA-256 mismatch"))

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
        ),
    )
    String.(propertynames(table)) == OFFICIAL_DIRECT_FIXTURE_COLUMNS ||
        throw(ArgumentError("unexpected official-direct fixture columns"))
    rows = collect(table)
    length(rows) == APPROVED_OFFICIAL_DIRECT_CELL_COUNT ||
        throw(ArgumentError("official-direct fixture cell count mismatch"))
    all(row -> Int(row.year) == APPROVED_YEAR, rows) ||
        throw(ArgumentError("official-direct fixture contains another year"))
    matrix_ids = Set(String(row.matrix_id) for row in rows)
    matrix_ids == Set(
        [
            DIRECT_MATRIX_ID,
            MARKET_SHARE_MATRIX_ID,
            VALUE_ADDED_MATRIX_ID,
            INDUSTRY_CONTROL_MATRIX_ID,
        ],
    ) || throw(ArgumentError("official-direct fixture contains another matrix"))
    canonical_keys = [
        (
                String(row.matrix_id),
                Int(row.row_position),
                Int(row.column_position),
            ) for row in rows
    ]
    canonical_keys == sort(canonical_keys) ||
        throw(ArgumentError("official-direct fixture rows are not canonical"))

    direct = materialize_fixture_matrix(
        CommodityBasis,
        IndustryBasis,
        rows,
        DIRECT_MATRIX_ID,
        APPROVED_COMMODITY_COUNT,
        APPROVED_INDUSTRY_COUNT,
        "Commodity",
        "Industry",
    )
    market = materialize_fixture_matrix(
        IndustryBasis,
        CommodityBasis,
        rows,
        MARKET_SHARE_MATRIX_ID,
        APPROVED_INDUSTRY_COUNT,
        APPROVED_COMMODITY_COUNT,
        "Industry",
        "Commodity",
    )
    value_added = materialize_fixture_matrix(
        ValueAddedBasis,
        IndustryBasis,
        rows,
        VALUE_ADDED_MATRIX_ID,
        APPROVED_VALUE_ADDED_COUNT,
        APPROVED_INDUSTRY_COUNT,
        "ValueAdded",
        "Industry",
    )
    controls = materialize_fixture_matrix(
        ControlBasis,
        IndustryBasis,
        rows,
        INDUSTRY_CONTROL_MATRIX_ID,
        1,
        APPROVED_INDUSTRY_COUNT,
        "Control",
        "Industry",
    )

    direct.matrix.column_codes == market.matrix.row_codes ||
        throw(ArgumentError("direct and market-share industry codes differ"))
    direct.column_descriptions == market.row_descriptions ||
        throw(ArgumentError("direct and market-share industry descriptions differ"))
    direct.matrix.row_codes == market.matrix.column_codes ||
        throw(ArgumentError("direct and market-share commodity codes differ"))
    direct.row_descriptions == market.column_descriptions ||
        throw(ArgumentError("direct and market-share commodity descriptions differ"))
    value_added.matrix.column_codes == direct.matrix.column_codes ||
        throw(ArgumentError("value-added industry codes differ"))
    value_added.column_descriptions == direct.column_descriptions ||
        throw(ArgumentError("value-added industry descriptions differ"))
    controls.matrix.column_codes == direct.matrix.column_codes ||
        throw(ArgumentError("industry-control codes differ"))
    controls.column_descriptions == direct.column_descriptions ||
        throw(ArgumentError("industry-control descriptions differ"))
    controls.matrix.row_codes == ["Total"] ||
        throw(ArgumentError("industry-control row is not Total"))
    value_added.matrix.row_codes == ["V001", "V002", "V003"] ||
        throw(ArgumentError("unexpected value-added rows"))
    all(code -> code in direct.matrix.row_codes, EXPLICIT_CLOSURE_CODES) ||
        throw(ArgumentError("official-direct fixture omits Other or Used"))
    count(value -> value < 0.0, direct.matrix.values) ==
        Int(manifest["negative_direct_cell_count"]) ||
        throw(ArgumentError("official-direct sign pattern changed"))
    count(value -> value < 0.0, market.matrix.values) ==
        Int(manifest["negative_market_share_cell_count"]) ||
        throw(ArgumentError("market-share sign pattern changed"))

    return OfficialDirectRequirementsFixture(
        APPROVED_YEAR,
        direct.matrix,
        market.matrix,
        value_added.matrix,
        LabeledVector{IndustryBasis}(
            controls.matrix.column_codes,
            vec(controls.matrix.values),
        ),
        String(manifest["source_zip_sha256"]),
        String(manifest["direct_workbook_sha256"]),
        String(manifest["market_share_workbook_sha256"]),
        manifest,
    )
end

function load_requirements_fixture(directory::AbstractString)
    manifest_path = joinpath(directory, "manifest.toml")
    cells_path = joinpath(directory, "cells.csv")
    manifest_bytes = read(manifest_path)
    sha256_hex(manifest_bytes) == APPROVED_MANIFEST_SHA256 ||
        throw(ArgumentError("unexpected total-requirements manifest SHA-256"))
    manifest = TOML.parse(String(manifest_bytes))
    get(manifest, "schema_version", "") == FIXTURE_SCHEMA ||
        throw(ArgumentError("unsupported total-requirements fixture schema"))
    get(manifest, "status", "") == EXPECTED_STATUS ||
        throw(ArgumentError("unexpected total-requirements fixture status"))
    get(manifest, "promotion_status", "") == EXPECTED_PROMOTION_STATUS ||
        throw(ArgumentError("unexpected total-requirements promotion status"))
    get(manifest, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("requirements fixture cannot be origin admissible"))
    get(manifest, "accounting_gate_effect", "") ==
        EXPECTED_ACCOUNTING_GATE_EFFECT ||
        throw(ArgumentError("requirements fixture cannot affect accounting gates"))
    get(manifest, "table_id", "") == APPROVED_TABLE_ID ||
        throw(ArgumentError("requirements fixture must project BEA Table 59"))
    get(manifest, "year", 0) == APPROVED_YEAR ||
        throw(ArgumentError("requirements fixture must contain the approved year"))
    get(manifest, "fixture_cell_count", 0) == APPROVED_CELL_COUNT ||
        throw(ArgumentError("requirements fixture has an unexpected cell count"))
    get(manifest, "published_decimal_places", 0) ==
        PUBLISHED_DECIMAL_PLACES ||
        throw(ArgumentError("unexpected requirements coefficient precision"))
    get(manifest, "coefficient_unit", "") == COEFFICIENT_UNIT ||
        throw(ArgumentError("unexpected requirements coefficient unit"))
    get(manifest, "api_production_time_utc", "") ==
        APPROVED_API_PRODUCTION_TIME ||
        throw(ArgumentError("unexpected Table 59 API production time"))
    expected_hash = lowercase(String(manifest["fixture_sha256"]))
    expected_hash == APPROVED_FIXTURE_SHA256 ||
        throw(ArgumentError("unexpected total-requirements fixture SHA-256"))
    lowercase(String(manifest["source_sha256"])) == APPROVED_SOURCE_SHA256 ||
        throw(ArgumentError("unexpected Table 59 source SHA-256"))
    lowercase(String(manifest["source_metadata_sha256"])) ==
        APPROVED_SOURCE_METADATA_SHA256 ||
        throw(ArgumentError("unexpected Table 59 metadata SHA-256"))
    actual_hash = sha256_hex(read(cells_path))
    expected_hash == actual_hash ||
        throw(ArgumentError("total-requirements fixture SHA-256 mismatch"))

    year = Int(manifest["year"])
    table = CSV.File(
        cells_path;
        missingstring = nothing,
        types = Dict(
            :table_id => String,
            :year => Int,
            :row_code => String,
            :row_type => String,
            :column_code => String,
            :column_type => String,
            :value => Float64,
        ),
    )
    String.(propertynames(table)) == FIXTURE_COLUMNS ||
        throw(ArgumentError("unexpected total-requirements fixture columns"))
    rows = collect(table)
    row_keys = [(row.row_code, row.column_code) for row in rows]
    row_keys == sort(row_keys) ||
        throw(ArgumentError("requirements fixture rows are not canonical"))
    length(rows) == Int(manifest["fixture_cell_count"]) ||
        throw(ArgumentError("total-requirements fixture cell count mismatch"))
    all(row -> row.table_id == "59", rows) ||
        throw(ArgumentError("requirements fixture contains another table"))
    all(row -> Int(row.year) == year, rows) ||
        throw(ArgumentError("requirements fixture contains another year"))
    all(
        row ->
        String(row.row_type) == "Commodity" &&
            String(row.column_type) == "Commodity",
        rows,
    ) || throw(ArgumentError("requirements fixture has a mislabeled axis"))

    column_codes = ordered_unique(String(row.column_code) for row in rows)
    row_codes = ordered_unique(String(row.row_code) for row in rows)
    isempty(first(row_codes)) ||
        throw(ArgumentError("requirements fixture must begin with its blank control row"))
    commodity_codes = [code for code in row_codes if !isempty(code)]
    Set(commodity_codes) == Set(column_codes) ||
        throw(ArgumentError("requirements commodity row/column codes differ"))
    expected_cell_count =
        (length(commodity_codes) + 1) * length(column_codes)
    length(rows) == expected_cell_count ||
        throw(ArgumentError("requirements fixture is not a complete rectangular grid"))

    values = zeros(length(commodity_codes), length(column_codes))
    explicit = falses(size(values))
    controls = zeros(length(column_codes))
    control_explicit = falses(length(column_codes))
    row_index =
        Dict(code => index for (index, code) in pairs(commodity_codes))
    column_index =
        Dict(code => index for (index, code) in pairs(column_codes))
    for row in rows
        row_code = String(row.row_code)
        column_code = String(row.column_code)
        column_position = column_index[column_code]
        value = Float64(row.value)
        isfinite(value) ||
            throw(ArgumentError("requirements fixture contains a nonfinite value"))
        if isempty(row_code)
            control_explicit[column_position] &&
                throw(ArgumentError("duplicate requirements control cell"))
            controls[column_position] = value
            control_explicit[column_position] = true
        else
            row_position = row_index[row_code]
            explicit[row_position, column_position] &&
                throw(ArgumentError("duplicate requirements matrix cell"))
            values[row_position, column_position] = value
            explicit[row_position, column_position] = true
        end
    end
    all(explicit) ||
        throw(ArgumentError("requirements matrix has an implicit cell"))
    all(control_explicit) ||
        throw(ArgumentError("requirements control row has an implicit cell"))
    all(value -> value >= 0, values) ||
        throw(ArgumentError("published total requirements must be nonnegative"))
    all(value -> value > 0, controls) ||
        throw(ArgumentError("published output-requirement controls must be positive"))

    return RequirementsFixture(
        year,
        LabeledMatrix{CommodityBasis, CommodityBasis}(
            commodity_codes,
            column_codes,
            values,
            explicit,
        ),
        LabeledVector{CommodityBasis}(column_codes, controls),
        String(manifest["source_sha256"]),
        manifest,
    )
end

function build_direct_requirements(fixture::RequirementsFixture)
    matrix = fixture.total_requirements
    matrix.row_codes == matrix.column_codes ||
        throw(ArgumentError("requirements matrix axes must use the same order"))
    dimension = length(matrix.row_codes)
    identity_matrix = Matrix{Float64}(I, dimension, dimension)
    inverse_matrix = inv(matrix.values)
    direct_values = identity_matrix - inverse_matrix
    reconstructed = inv(identity_matrix - direct_values)
    reconstruction_error = maximum(abs, reconstructed - matrix.values)
    leontief_error =
        maximum(abs, (identity_matrix - direct_values) * matrix.values - identity_matrix)

    direct_requirements =
        derived_matrix(matrix.row_codes, matrix.column_codes, direct_values)
    negatives = negative_cells(direct_requirements)
    substantive_negatives = [
        cell
            for cell in negatives
            if cell.value < -SUBSTANTIVE_NEGATIVE_THRESHOLD
    ]

    residuals = ControlResidual[]
    decimal_places = Int(fixture.manifest["published_decimal_places"])
    published_unit = 10.0^(-decimal_places)
    column_tolerance =
        (dimension + 1) * published_unit / 2
    for (column_index, code) in pairs(matrix.column_codes)
        add_residual!(
            residuals,
            :published_total_output_requirement,
            code,
            "sum_commodity(L[commodity,target]) = published total-output requirement",
            sum(@view matrix.values[:, column_index]),
            fixture.total_output_requirements[code],
            column_tolerance,
        )
    end
    add_residual!(
        residuals,
        :inverse_reconstruction,
        "L",
        "inv(I - A) = published L",
        reconstruction_error,
        0.0,
        COEFFICIENT_NUMERICAL_TOLERANCE,
    )
    add_residual!(
        residuals,
        :leontief_identity,
        "I",
        "(I - A) * L = I",
        leontief_error,
        0.0,
        COEFFICIENT_NUMERICAL_TOLERANCE,
    )

    blockers = [
        "CURRENT_VINTAGE_NOT_ORIGIN_ELIGIBLE",
        "DIRECT_REQUIREMENTS_IMPLIED_FROM_ROUNDED_TOTAL_MATRIX",
        "AFTER_REDEFINITIONS_SYSTEM_NOT_RECONCILED",
        "FINAL_USE_VALUATION_LEDGER_NOT_PROVIDED",
        "OTHER_USED_NOT_ALLOCATED_TO_68_SECTOR_CORE",
    ]
    isempty(substantive_negatives) ||
        push!(
        blockers,
        "SUBSTANTIVE_NEGATIVE_DIRECT_REQUIREMENTS_REQUIRE_GOVERNED_POLICY",
    )

    return RequirementsReport(
        fixture.year,
        matrix,
        fixture.total_output_requirements,
        direct_requirements,
        residuals,
        negatives,
        substantive_negatives,
        cond(matrix.values),
        maximum(abs, eigvals(direct_values)),
        reconstruction_error,
        leontief_error,
        fixture.source_sha256,
        EXPECTED_STATUS,
        :inverse_of_published_commodity_total_requirements,
        false,
        false,
        blockers,
        false,
    )
end

"""
    build_official_direct_requirements(total_fixture, direct_fixture)

Construct the primary commodity-by-commodity direct matrix as `B * D` from
BEA's directly published after-redefinitions workbooks. Table 59 is aligned by
commodity code and used only for published-rounding and Leontief round-trip
controls.
"""
function build_official_direct_requirements(
        total_fixture::RequirementsFixture,
        direct_fixture::OfficialDirectRequirementsFixture,
    )
    total_fixture.year == direct_fixture.year ||
        throw(ArgumentError("official-direct and total-requirements years differ"))
    total_matrix = total_fixture.total_requirements
    total_matrix.row_codes == total_matrix.column_codes ||
        throw(ArgumentError("total-requirements axes must use the same order"))
    direct_fixture.direct_by_industry.column_codes ==
        direct_fixture.market_shares.row_codes ||
        throw(ArgumentError("official-direct industry axes are not aligned"))
    direct_fixture.direct_by_industry.row_codes ==
        direct_fixture.market_shares.column_codes ||
        throw(ArgumentError("official-direct commodity axes are not aligned"))
    direct_fixture.value_added.column_codes ==
        direct_fixture.direct_by_industry.column_codes ||
        throw(ArgumentError("official-direct value-added axis is not aligned"))
    direct_fixture.industry_totals.codes ==
        direct_fixture.direct_by_industry.column_codes ||
        throw(ArgumentError("official-direct total-control axis is not aligned"))

    source_commodity_codes =
        direct_fixture.direct_by_industry.row_codes
    Set(source_commodity_codes) == Set(total_matrix.row_codes) ||
        throw(
        ArgumentError(
            "official-direct and total-requirements commodity codes differ",
        ),
    )
    source_direct_values =
        direct_fixture.direct_by_industry.values *
        direct_fixture.market_shares.values
    source_index = Dict(
        code => index for (index, code) in pairs(source_commodity_codes)
    )
    aligned_indices = [source_index[code] for code in total_matrix.row_codes]
    official_direct_values =
        source_direct_values[aligned_indices, aligned_indices]

    dimension = length(total_matrix.row_codes)
    identity_matrix = Matrix{Float64}(I, dimension, dimension)
    inversion_implied_values = identity_matrix - inv(total_matrix.values)
    direct_difference_values =
        official_direct_values - inversion_implied_values
    reconstructed_total_values =
        inv(identity_matrix - official_direct_values)
    direct_agreement_error = maximum(abs, direct_difference_values)
    total_agreement_error =
        maximum(abs, reconstructed_total_values - total_matrix.values)
    published_leontief_error = maximum(
        abs,
        (identity_matrix - official_direct_values) *
            total_matrix.values - identity_matrix,
    )
    numerical_leontief_error = maximum(
        abs,
        (identity_matrix - official_direct_values) *
            reconstructed_total_values - identity_matrix,
    )

    direct_requirements = derived_matrix(
        total_matrix.row_codes,
        total_matrix.column_codes,
        official_direct_values,
    )
    inversion_implied_requirements = derived_matrix(
        total_matrix.row_codes,
        total_matrix.column_codes,
        inversion_implied_values,
    )
    reconstructed_total_requirements = derived_matrix(
        total_matrix.row_codes,
        total_matrix.column_codes,
        reconstructed_total_values,
    )
    direct_difference = derived_matrix(
        total_matrix.row_codes,
        total_matrix.column_codes,
        direct_difference_values,
    )
    negatives = negative_cells(direct_requirements)
    substantive_negatives = [
        cell
            for cell in negatives
            if cell.value < -SUBSTANTIVE_NEGATIVE_THRESHOLD
    ]

    residuals = ControlResidual[]
    direct_control_tolerance =
        Float64(direct_fixture.manifest["direct_control_tolerance"])
    for (industry_index, code) in
        pairs(direct_fixture.direct_by_industry.column_codes)
        add_residual!(
            residuals,
            :published_direct_input_value_added_control,
            code,
            "sum(B[commodity,industry]) + sum(VA[value_added,industry]) = published industry total",
            sum(
                @view direct_fixture.direct_by_industry.values[
                    :,
                    industry_index,
                ]
            ) +
                sum(
                @view direct_fixture.value_added.values[
                    :,
                    industry_index,
                ]
            ),
            direct_fixture.industry_totals[code],
            direct_control_tolerance,
        )
    end
    market_control_tolerance =
        Float64(direct_fixture.manifest["market_share_control_tolerance"])
    for (commodity_index, code) in
        pairs(direct_fixture.market_shares.column_codes)
        add_residual!(
            residuals,
            :published_market_share_control,
            code,
            "sum(D[industry,commodity]) = 1",
            sum(
                @view direct_fixture.market_shares.values[
                    :,
                    commodity_index,
                ]
            ),
            1.0,
            market_control_tolerance,
        )
    end
    decimal_places =
        Int(total_fixture.manifest["published_decimal_places"])
    total_output_tolerance =
        (dimension + 1) * 10.0^(-decimal_places) / 2
    for (column_index, code) in pairs(total_matrix.column_codes)
        add_residual!(
            residuals,
            :published_total_output_requirement,
            code,
            "sum_commodity(L[commodity,target]) = published total-output requirement",
            sum(@view total_matrix.values[:, column_index]),
            total_fixture.total_output_requirements[code],
            total_output_tolerance,
        )
    end
    add_residual!(
        residuals,
        :direct_matrix_round_trip,
        "maximum_cell_error",
        "B * D = I - inv(Table 59 L), within published rounding",
        direct_agreement_error,
        0.0,
        DIRECT_MATRIX_AGREEMENT_TOLERANCE,
    )
    add_residual!(
        residuals,
        :total_matrix_round_trip,
        "maximum_cell_error",
        "inv(I - B * D) = Table 59 L, within published rounding",
        total_agreement_error,
        0.0,
        TOTAL_MATRIX_AGREEMENT_TOLERANCE,
    )
    add_residual!(
        residuals,
        :published_leontief_identity,
        "maximum_cell_error",
        "(I - B * D) * Table 59 L = I, within published rounding",
        published_leontief_error,
        0.0,
        TOTAL_MATRIX_AGREEMENT_TOLERANCE,
    )
    add_residual!(
        residuals,
        :inverse_numerical_identity,
        "maximum_cell_error",
        "(I - B * D) * inv(I - B * D) = I",
        numerical_leontief_error,
        0.0,
        COEFFICIENT_NUMERICAL_TOLERANCE,
    )

    blockers = [
        "CURRENT_VINTAGE_NOT_ORIGIN_ELIGIBLE",
        "OFFICIAL_AFTER_REDEFINITIONS_MATRICES_ROUNDED_TO_SEVEN_DECIMALS",
        "AFTER_REDEFINITIONS_SYSTEM_NOT_RECONCILED",
        "FINAL_USE_VALUATION_LEDGER_NOT_PROVIDED",
        "OTHER_USED_NOT_ALLOCATED_TO_68_SECTOR_CORE",
    ]
    isempty(substantive_negatives) ||
        push!(
        blockers,
        "SUBSTANTIVE_NEGATIVE_DIRECT_REQUIREMENTS_REQUIRE_GOVERNED_POLICY",
    )

    return OfficialDirectRequirementsReport(
        total_fixture.year,
        total_matrix,
        total_fixture.total_output_requirements,
        direct_fixture.direct_by_industry,
        direct_fixture.market_shares,
        direct_fixture.value_added,
        direct_fixture.industry_totals,
        direct_requirements,
        inversion_implied_requirements,
        reconstructed_total_requirements,
        direct_difference,
        residuals,
        negatives,
        substantive_negatives,
        negative_cells(direct_fixture.direct_by_industry),
        negative_cells(direct_fixture.market_shares),
        cond(reconstructed_total_values),
        maximum(abs, eigvals(official_direct_values)),
        direct_agreement_error,
        sum(abs, direct_difference_values),
        sqrt(sum(abs2, direct_difference_values) / length(direct_difference_values)),
        total_agreement_error,
        published_leontief_error,
        OfficialDirectRequirementsProvenance(
            total_fixture.source_sha256,
            String(total_fixture.manifest["source_metadata_sha256"]),
            String(total_fixture.manifest["fixture_sha256"]),
            APPROVED_MANIFEST_SHA256,
            direct_fixture.source_zip_sha256,
            String(direct_fixture.manifest["source_metadata_sha256"]),
            direct_fixture.direct_workbook_sha256,
            direct_fixture.market_share_workbook_sha256,
            String(direct_fixture.manifest["fixture_sha256"]),
            APPROVED_OFFICIAL_DIRECT_MANIFEST_SHA256,
            String(direct_fixture.manifest["artifact_tool_version"]),
        ),
        EXPECTED_STATUS,
        :official_after_redefinitions_direct_times_market_share,
        false,
        false,
        blockers,
        false,
    )
end

function build_requirements_transactions(
        requirements::Union{
            RequirementsReport,
            OfficialDirectRequirementsReport,
        },
        supply_make::SupplyMakeReport,
    )
    requirements_controls_pass(requirements) ||
        throw(ArgumentError("requirements controls do not pass"))
    requirements.year == supply_make.year ||
        throw(ArgumentError("requirements and supply/make years differ"))
    controls_pass(supply_make) ||
        throw(ArgumentError("supply/make controls do not pass"))
    supply_make.transformation == :code_keyed_retail_aggregation_only ||
        throw(ArgumentError("unexpected supply/make transformation"))
    supply_make.balancing_applied &&
        throw(ArgumentError("balanced supply/make inputs are not diagnostic"))
    requirements.clipping_applied &&
        throw(ArgumentError("clipped direct requirements are not diagnostic"))
    requirements.balancing_applied &&
        throw(ArgumentError("balanced direct requirements are not diagnostic"))
    requirements.promotion_ready &&
        throw(ArgumentError("promoted direct requirements are not diagnostic"))
    requirements.transformation in (
        :inverse_of_published_commodity_total_requirements,
        :official_after_redefinitions_direct_times_market_share,
    ) || throw(ArgumentError("unexpected direct-requirements transformation"))
    source_codes = requirements.direct_requirements.row_codes
    requirements.direct_requirements.column_codes == source_codes ||
        throw(ArgumentError("direct-requirements axes are not aligned"))
    Set(source_codes) == Set(supply_make.raw_commodity_output.codes) ||
        throw(
        ArgumentError(
            "requirements commodities do not match raw supply commodities",
        ),
    )
    Set(keys(supply_make.commodity_mapping)) == Set(source_codes) ||
        throw(ArgumentError("commodity aggregation mapping is incomplete"))

    source_output_values = Float64[
        supply_make.raw_commodity_output[code] for code in source_codes
    ]
    all(value -> value > 0, source_output_values) ||
        throw(ArgumentError("source commodity outputs must be positive"))
    source_transaction_values =
        requirements.direct_requirements.values .*
        reshape(source_output_values, 1, :)
    source_transactions =
        derived_matrix(source_codes, source_codes, source_transaction_values)

    target_codes = ordered_unique(
        supply_make.commodity_mapping[code] for code in source_codes
    )
    target_index =
        Dict(code => index for (index, code) in pairs(target_codes))
    aggregation = zeros(length(target_codes), length(source_codes))
    for (source_index, code) in pairs(source_codes)
        aggregation[
            target_index[supply_make.commodity_mapping[code]],
            source_index,
        ] = 1.0
    end
    all(vec(sum(aggregation; dims = 1)) .== 1.0) ||
        throw(AssertionError("each source commodity must have one target"))

    transaction_values =
        aggregation * source_transaction_values * transpose(aggregation)
    output_values = aggregation * source_output_values
    direct_values = transaction_values ./ reshape(output_values, 1, :)
    transactions =
        derived_matrix(target_codes, target_codes, transaction_values)
    direct_requirements =
        derived_matrix(target_codes, target_codes, direct_values)

    residuals = ControlResidual[]
    add_residual!(
        residuals,
        :transaction_aggregation,
        "grand_total",
        "sum(aggregated Z) = sum(source Z)",
        sum(transaction_values),
        sum(source_transaction_values),
        TRANSACTION_NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :output_aggregation,
        "grand_total",
        "sum(aggregated q) = sum(source q)",
        sum(output_values),
        sum(source_output_values),
        TRANSACTION_NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    reconstructed_transactions =
        direct_values .* reshape(output_values, 1, :)
    add_residual!(
        residuals,
        :direct_transaction_reconstruction,
        "maximum_cell_error",
        "A_aggregated * diag(q_aggregated) = Z_aggregated",
        maximum(abs, reconstructed_transactions - transaction_values),
        0.0,
        TRANSACTION_NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    for code in EXPLICIT_CLOSURE_CODES
        code in target_codes ||
            throw(ArgumentError("aggregated requirements dropped $code"))
    end

    source_negatives = negative_cells(source_transactions)
    transaction_negatives = negative_cells(transactions)
    blockers = copy(requirements.promotion_blockers)
    push!(blockers, "OUTPUT_WEIGHTED_RETAIL_AGGREGATION_DIAGNOSTIC_ONLY")
    transformation =
        requirements.transformation ==
        :official_after_redefinitions_direct_times_market_share ?
        :official_direct_output_weighted_retail_transaction_aggregation :
        :implied_direct_output_weighted_retail_transaction_aggregation

    return RequirementsTransactionReport(
        requirements.year,
        LabeledVector{CommodityBasis}(source_codes, source_output_values),
        source_transactions,
        LabeledVector{CommodityBasis}(target_codes, output_values),
        transactions,
        direct_requirements,
        copy(supply_make.commodity_mapping),
        residuals,
        source_negatives,
        transaction_negatives,
        collect(EXPLICIT_CLOSURE_CODES),
        transformation,
        false,
        false,
        blockers,
        false,
    )
end

"""
    compare_structural_transactions(symmetric, requirements)

Compare the rounding-normalized industry-technology symmetric-use diagnostic
with the output-weighted after-redefinitions requirements diagnostic. Axes
are aligned by commodity code. The returned difference must not be interpreted
as an admissible valuation adjustment.
"""
function compare_structural_transactions(
        symmetric::SymmetricUseReport,
        requirements::RequirementsTransactionReport,
    )
    transformation_controls_pass(symmetric) ||
        throw(ArgumentError("symmetric-use controls do not pass"))
    transaction_controls_pass(requirements) ||
        throw(ArgumentError("requirements transaction controls do not pass"))
    symmetric.year == requirements.year ||
        throw(ArgumentError("structural transaction years differ"))
    symmetric.valuation_bridge_applied &&
        throw(ArgumentError("unexpected promoted symmetric-use valuation"))
    symmetric.clipping_applied &&
        throw(ArgumentError("clipped symmetric-use input is not diagnostic"))
    symmetric.balancing_applied &&
        throw(ArgumentError("balanced symmetric-use input is not diagnostic"))
    requirements.clipping_applied &&
        throw(ArgumentError("clipped requirements input is not diagnostic"))
    requirements.balancing_applied &&
        throw(ArgumentError("balanced requirements input is not diagnostic"))
    requirements.promotion_ready &&
        throw(ArgumentError("promoted requirements transactions are not diagnostic"))
    requirements.transformation in (
        :official_direct_output_weighted_retail_transaction_aggregation,
        :implied_direct_output_weighted_retail_transaction_aggregation,
    ) || throw(ArgumentError("unexpected requirements transaction transformation"))

    target_codes = copy(requirements.transactions.row_codes)
    requirements.transactions.column_codes == target_codes ||
        throw(ArgumentError("requirements transaction axes are not aligned"))
    Set(symmetric.rounding_normalized_symmetric_use.row_codes) ==
        Set(target_codes) ||
        throw(ArgumentError("symmetric and requirements commodity rows differ"))
    Set(symmetric.rounding_normalized_symmetric_use.column_codes) ==
        Set(target_codes) ||
        throw(ArgumentError("symmetric and requirements commodity columns differ"))

    symmetric_values = [
        symmetric.rounding_normalized_symmetric_use[row_code, column_code]
            for row_code in target_codes, column_code in target_codes
    ]
    requirements_values = copy(requirements.transactions.values)
    difference_values = symmetric_values - requirements_values
    row_values = vec(sum(difference_values; dims = 2))
    column_values = vec(sum(difference_values; dims = 1))
    signed_total = sum(difference_values)

    maximum_index = argmax(abs.(difference_values))
    maximum_cell = SignedDifferenceCell(
        target_codes[maximum_index[1]],
        target_codes[maximum_index[2]],
        symmetric_values[maximum_index],
        requirements_values[maximum_index],
        difference_values[maximum_index],
    )

    residuals = ControlResidual[]
    add_residual!(
        residuals,
        :comparison_row_sum,
        "grand_total",
        "sum(row differences) = sum(cell differences)",
        sum(row_values),
        signed_total,
        TRANSACTION_NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :comparison_column_sum,
        "grand_total",
        "sum(column differences) = sum(cell differences)",
        sum(column_values),
        signed_total,
        TRANSACTION_NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :comparison_source_totals,
        "grand_total",
        "sum(symmetric) - sum(requirements) = sum(cell differences)",
        sum(symmetric_values) - sum(requirements_values),
        signed_total,
        TRANSACTION_NUMERICAL_TOLERANCE_MILLIONS_USD,
    )

    blockers = [
        "COMPARISON_IS_NOT_A_VALUATION_BRIDGE",
        "PRICE_BASES_AND_AFTER_REDEFINITIONS_SYSTEM_NOT_RECONCILED",
        "CELL_LEVEL_MARGIN_TAX_SUBSIDY_LEDGER_NOT_PROVIDED",
        "OTHER_USED_NOT_ALLOCATED_TO_68_SECTOR_CORE",
        "MODEL_STATE_RECONCILIATION_NOT_APPLIED",
    ]
    right_basis =
        requirements.transformation ==
        :official_direct_output_weighted_retail_transaction_aggregation ?
        :official_after_redefinitions_direct_requirements_diagnostic :
        :total_requirements_inversion_diagnostic
    return RequirementsComparisonReport(
        symmetric.year,
        derived_matrix(target_codes, target_codes, symmetric_values),
        derived_matrix(target_codes, target_codes, requirements_values),
        derived_matrix(target_codes, target_codes, difference_values),
        LabeledVector{CommodityBasis}(target_codes, row_values),
        LabeledVector{CommodityBasis}(target_codes, column_values),
        residuals,
        signed_total,
        sum(abs, difference_values),
        norm(difference_values),
        cor(vec(symmetric_values), vec(requirements_values)),
        maximum_cell,
        :purchasers_price_use_industry_technology_diagnostic,
        right_basis,
        :basis_and_system_boundary_comparison_only,
        false,
        false,
        false,
        blockers,
        false,
    )
end

end
