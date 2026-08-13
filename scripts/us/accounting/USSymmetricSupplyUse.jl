module USSymmetricSupplyUse

using ..USSupplyMakeDiagnostics:
    AxisBasis,
    CommodityBasis,
    ControlResidual,
    EXPLICIT_CLOSURE_CODES,
    IndustryBasis,
    LabeledMatrix,
    LabeledVector,
    SupplyMakeReport,
    controls_pass,
    published_rounding_tolerance

export NegativeCell,
    SymmetricUseReport,
    build_industry_technology_system,
    negative_cells,
    transformation_controls_pass,
    NUMERICAL_TOLERANCE_MILLIONS_USD,
    NUMERICAL_TOLERANCE_RATIO

const NUMERICAL_TOLERANCE_MILLIONS_USD = 1.0e-6
const NUMERICAL_TOLERANCE_RATIO = 1.0e-12

"""
A negative cell retained from a published or derived matrix.

Negative values are evidence, not missing values. The symmetric-use operator
does not clip, redistribute, or relabel them.
"""
struct NegativeCell
    row_code::String
    column_code::String
    value::Float64
end

"""
Diagnostic industry-technology transformation of the archived BEA make/use
system.

Let `V` be the commodity-by-industry make matrix, `U` the
commodity-by-industry intermediate-use matrix, `q` published commodity
output, and `g` published industry output. The published-control variant is

    Z_published = U * diag(g)^(-1) * transpose(V)

and the corresponding market-share matrix is

    D_published = transpose(V) * diag(q)^(-1).

Independently rounded `q`, `g`, and matrix cells differ by at most a few
million dollars. The report therefore also exposes a rounding-normalized
variant. It divides each make column by its observed column sum, making the
industry product mixes an exact partition before applying `U`. No source cell
is changed, and both variants remain available for comparison.

The result is still a diagnostic. `U` is at purchasers' prices, `V` is at
producer prices, and `q` is at basic prices. No margin/tax valuation bridge,
closure-account allocation, balancing, clipping, or model-state
reconciliation is applied.
"""
struct SymmetricUseReport
    year::Int
    source_make::LabeledMatrix{CommodityBasis, IndustryBasis}
    source_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    commodity_output::LabeledVector{CommodityBasis}
    industry_output::LabeledVector{IndustryBasis}
    make_row_sums::LabeledVector{CommodityBasis}
    make_column_sums::LabeledVector{IndustryBasis}
    published_market_shares::LabeledMatrix{IndustryBasis, CommodityBasis}
    rounding_normalized_market_shares::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    published_product_mix::LabeledMatrix{IndustryBasis, CommodityBasis}
    rounding_normalized_product_mix::LabeledMatrix{
        IndustryBasis,
        CommodityBasis,
    }
    published_symmetric_use::LabeledMatrix{CommodityBasis, CommodityBasis}
    rounding_normalized_symmetric_use::LabeledMatrix{
        CommodityBasis,
        CommodityBasis,
    }
    residuals::Vector{ControlResidual}
    negative_make_cells::Vector{NegativeCell}
    negative_use_cells::Vector{NegativeCell}
    negative_symmetric_cells::Vector{NegativeCell}
    explicit_closure_codes::Vector{String}
    promotion_blockers::Vector{String}
    technology_assumption::Symbol
    use_price_basis::Symbol
    make_price_basis::Symbol
    output_price_basis::Symbol
    rounding_policy::Symbol
    closure_policy::Symbol
    rounding_normalization_applied::Bool
    valuation_bridge_applied::Bool
    balancing_applied::Bool
    clipping_applied::Bool
    promotion_ready::Bool
end

transformation_controls_pass(report::SymmetricUseReport) =
    all(residual.passed for residual in report.residuals)

function negative_cells(matrix::LabeledMatrix)
    cells = NegativeCell[]
    for row_index in eachindex(matrix.row_codes)
        for column_index in eachindex(matrix.column_codes)
            value = matrix.values[row_index, column_index]
            value < 0 || continue
            push!(
                cells,
                NegativeCell(
                    matrix.row_codes[row_index],
                    matrix.column_codes[column_index],
                    value,
                ),
            )
        end
    end
    return cells
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

function derived_matrix(::Type{R}, ::Type{C}, row_codes, column_codes, values) where {
        R <: AxisBasis,
        C <: AxisBasis,
    }
    return LabeledMatrix{R, C}(
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

function validate_source_report(report::SupplyMakeReport)
    controls_pass(report) ||
        throw(ArgumentError("source supply/make controls do not pass"))
    report.transformation == :code_keyed_retail_aggregation_only ||
        throw(ArgumentError("unexpected source aggregation contract"))
    report.balancing_applied &&
        throw(ArgumentError("balanced source matrices are not admissible"))

    commodity_codes = report.commodity_output.codes
    industry_codes = report.industry_output.codes
    Set(report.aggregated_make.row_codes) == Set(commodity_codes) ||
        throw(ArgumentError("make rows do not match commodity-output codes"))
    Set(report.aggregated_use.row_codes) == Set(commodity_codes) ||
        throw(ArgumentError("use rows do not match commodity-output codes"))
    Set(report.aggregated_make.column_codes) == Set(industry_codes) ||
        throw(ArgumentError("make columns do not match industry-output codes"))
    Set(report.aggregated_use.column_codes) == Set(industry_codes) ||
        throw(ArgumentError("use columns do not match industry-output codes"))
    for code in EXPLICIT_CLOSURE_CODES
        code in commodity_codes ||
            throw(ArgumentError("source report dropped closure commodity $code"))
    end
    return nothing
end

"""
    build_industry_technology_system(source_report)

Construct published-control and rounding-normalized commodity-by-commodity
intermediate-use diagnostics under the industry-technology assumption.

Every operation is code-keyed. The function rejects failed or balanced source
reports and preserves negative cells. It never claims that a valuation bridge
or opening-state reconciliation has occurred.
"""
function build_industry_technology_system(source_report::SupplyMakeReport)
    validate_source_report(source_report)

    commodity_codes = copy(source_report.commodity_output.codes)
    industry_codes = copy(source_report.industry_output.codes)
    make_values = aligned_values(
        source_report.aggregated_make,
        commodity_codes,
        industry_codes,
    )
    use_values = aligned_values(
        source_report.aggregated_use,
        commodity_codes,
        industry_codes,
    )
    commodity_output = Float64[
        source_report.commodity_output[code] for code in commodity_codes
    ]
    industry_output = Float64[
        source_report.industry_output[code] for code in industry_codes
    ]
    make_row_values = vec(sum(make_values; dims = 2))
    make_column_values = vec(sum(make_values; dims = 1))

    all(>(0), commodity_output) ||
        throw(ArgumentError("published commodity outputs must be positive"))
    all(>(0), industry_output) ||
        throw(ArgumentError("published industry outputs must be positive"))
    all(>(0), make_row_values) ||
        throw(ArgumentError("observed make row sums must be positive"))
    all(>(0), make_column_values) ||
        throw(ArgumentError("observed make column sums must be positive"))

    transposed_make = permutedims(make_values)
    published_market_share_values =
        transposed_make ./ reshape(commodity_output, 1, :)
    normalized_market_share_values =
        transposed_make ./ reshape(make_row_values, 1, :)
    published_product_mix_values =
        transposed_make ./ reshape(industry_output, :, 1)
    normalized_product_mix_values =
        transposed_make ./ reshape(make_column_values, :, 1)

    published_symmetric_values =
        use_values * published_product_mix_values
    normalized_symmetric_values =
        use_values * normalized_product_mix_values

    source_make = LabeledMatrix{CommodityBasis, IndustryBasis}(
        commodity_codes,
        industry_codes,
        make_values,
        aligned_explicit(
            source_report.aggregated_make,
            commodity_codes,
            industry_codes,
        ),
    )
    source_use = LabeledMatrix{CommodityBasis, IndustryBasis}(
        commodity_codes,
        industry_codes,
        use_values,
        aligned_explicit(
            source_report.aggregated_use,
            commodity_codes,
            industry_codes,
        ),
    )
    make_row_sums =
        LabeledVector{CommodityBasis}(commodity_codes, make_row_values)
    make_column_sums =
        LabeledVector{IndustryBasis}(industry_codes, make_column_values)
    published_market_shares = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        industry_codes,
        commodity_codes,
        published_market_share_values,
    )
    normalized_market_shares = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        industry_codes,
        commodity_codes,
        normalized_market_share_values,
    )
    published_product_mix = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        industry_codes,
        commodity_codes,
        published_product_mix_values,
    )
    normalized_product_mix = derived_matrix(
        IndustryBasis,
        CommodityBasis,
        industry_codes,
        commodity_codes,
        normalized_product_mix_values,
    )
    published_symmetric_use = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        commodity_codes,
        commodity_codes,
        published_symmetric_values,
    )
    normalized_symmetric_use = derived_matrix(
        CommodityBasis,
        CommodityBasis,
        commodity_codes,
        commodity_codes,
        normalized_symmetric_values,
    )

    residuals = ControlResidual[]
    commodity_term_count = length(industry_codes)
    industry_term_count = length(commodity_codes)
    for (commodity_index, code) in pairs(commodity_codes)
        published_tolerance =
            published_rounding_tolerance(commodity_term_count) /
            commodity_output[commodity_index]
        add_residual!(
            residuals,
            :published_market_share,
            code,
            "sum_industry(V[commodity,industry] / published_q[commodity]) = 1",
            sum(@view published_market_share_values[:, commodity_index]),
            1.0,
            published_tolerance,
        )
        add_residual!(
            residuals,
            :rounding_normalized_market_share,
            code,
            "sum_industry(V[commodity,industry] / sum_industry(V)) = 1",
            sum(@view normalized_market_share_values[:, commodity_index]),
            1.0,
            NUMERICAL_TOLERANCE_RATIO,
        )
    end

    published_mix_tolerances = zeros(length(industry_codes))
    for (industry_index, code) in pairs(industry_codes)
        published_tolerance =
            published_rounding_tolerance(industry_term_count) /
            industry_output[industry_index]
        published_mix_tolerances[industry_index] = published_tolerance
        add_residual!(
            residuals,
            :published_product_mix,
            code,
            "sum_commodity(V[commodity,industry] / published_g[industry]) = 1",
            sum(@view published_product_mix_values[industry_index, :]),
            1.0,
            published_tolerance,
        )
        add_residual!(
            residuals,
            :rounding_normalized_product_mix,
            code,
            "sum_commodity(V[commodity,industry] / sum_commodity(V)) = 1",
            sum(@view normalized_product_mix_values[industry_index, :]),
            1.0,
            NUMERICAL_TOLERANCE_RATIO,
        )
    end

    source_row_totals = vec(sum(use_values; dims = 2))
    published_row_totals = vec(sum(published_symmetric_values; dims = 2))
    normalized_row_totals = vec(sum(normalized_symmetric_values; dims = 2))
    published_row_tolerances =
        abs.(use_values) * published_mix_tolerances
    for (commodity_index, code) in pairs(commodity_codes)
        add_residual!(
            residuals,
            :published_symmetric_row_conservation,
            code,
            "sum_target(Z_published[source,target]) = sum_industry(U[source,industry])",
            published_row_totals[commodity_index],
            source_row_totals[commodity_index],
            published_row_tolerances[commodity_index] +
                NUMERICAL_TOLERANCE_MILLIONS_USD,
        )
        add_residual!(
            residuals,
            :rounding_normalized_symmetric_row_conservation,
            code,
            "sum_target(Z_normalized[source,target]) = sum_industry(U[source,industry])",
            normalized_row_totals[commodity_index],
            source_row_totals[commodity_index],
            NUMERICAL_TOLERANCE_MILLIONS_USD,
        )
    end
    add_residual!(
        residuals,
        :published_symmetric_grand_conservation,
        "T001",
        "sum(Z_published) = sum(U) within published-output rounding",
        sum(published_symmetric_values),
        sum(use_values),
        sum(published_row_tolerances) +
            NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    add_residual!(
        residuals,
        :rounding_normalized_symmetric_grand_conservation,
        "T001",
        "sum(Z_normalized) = sum(U)",
        sum(normalized_symmetric_values),
        sum(use_values),
        NUMERICAL_TOLERANCE_MILLIONS_USD,
    )
    for code in EXPLICIT_CLOSURE_CODES
        closure_index = findfirst(==(code), commodity_codes)
        add_residual!(
            residuals,
            :closure_row_conservation,
            code,
            "sum_target(Z_normalized[closure,target]) = sum_industry(U[closure,industry])",
            normalized_row_totals[closure_index],
            source_row_totals[closure_index],
            NUMERICAL_TOLERANCE_MILLIONS_USD,
        )
    end

    make_negatives = negative_cells(source_make)
    use_negatives = negative_cells(source_use)
    symmetric_negatives = negative_cells(normalized_symmetric_use)
    blockers = [
        "VALUATION_BRIDGE_NOT_APPLIED",
        "OTHER_USED_CLOSURE_ACCOUNTS_UNALLOCATED",
        "MODEL_STATE_RECONCILIATION_NOT_APPLIED",
    ]
    if !isempty(make_negatives) ||
            !isempty(use_negatives) ||
            !isempty(symmetric_negatives)
        push!(blockers, "NEGATIVE_CELLS_PRESERVED_REQUIRES_GOVERNED_POLICY")
    end

    return SymmetricUseReport(
        source_report.year,
        source_make,
        source_use,
        LabeledVector{CommodityBasis}(commodity_codes, commodity_output),
        LabeledVector{IndustryBasis}(industry_codes, industry_output),
        make_row_sums,
        make_column_sums,
        published_market_shares,
        normalized_market_shares,
        published_product_mix,
        normalized_product_mix,
        published_symmetric_use,
        normalized_symmetric_use,
        residuals,
        make_negatives,
        use_negatives,
        symmetric_negatives,
        collect(EXPLICIT_CLOSURE_CODES),
        blockers,
        :industry_technology,
        :purchasers_prices,
        :producer_prices,
        :basic_prices,
        :published_controls_plus_exact_make_sum_normalization,
        :explicit_unallocated_other_used,
        true,
        false,
        false,
        false,
        false,
    )
end

end
