module USSupplyMakeDiagnostics

using CSV
using JSON
using SHA
using TOML

export AxisBasis,
    CommodityBasis,
    IndustryBasis,
    BasisMismatchError,
    LabeledVector,
    LabeledMatrix,
    IOCell,
    IOTable,
    ControlResidual,
    SupplyMakeReport,
    RETAIL_SOURCE_CODES,
    EXPLICIT_CLOSURE_CODES,
    load_bea_json,
    load_canonical_fixture,
    diagnose_supply_make,
    keyed_difference,
    control_residuals,
    controls_pass,
    cell_value,
    has_cell,
    published_rounding_tolerance

abstract type AxisBasis end
struct CommodityBasis <: AxisBasis end
struct IndustryBasis <: AxisBasis end

const RETAIL_SOURCE_CODES = ("441", "445", "452", "4A0")
const EXPLICIT_CLOSURE_CODES = ("Other", "Used")

const SUPPLY_COMPONENT_CODES = (
    "MADJ",
    "MCIF",
    "MDTY",
    "SUB",
    "T007",
    "T013",
    "T014",
    "T015",
    "T016",
    "TOP",
    "Trade",
    "Trans",
)

const USE_CONTROL_ROWS = Set(
    [
        "T005",
        "T00OSUB",
        "T00OTOP",
        "T00SUB",
        "T00TOP",
        "T018",
        "V001",
        "V003",
        "VABAS",
        "VAPRO",
    ],
)

"""
Raised when an operation would compare an industry-indexed vector with a
commodity-indexed vector. Matching code strings or equal vector lengths do not
make the two economic bases interchangeable.
"""
struct BasisMismatchError <: Exception
    lhs_basis::DataType
    rhs_basis::DataType
end

function Base.showerror(io::IO, error::BasisMismatchError)
    return print(
        io,
        "cannot compare ",
        error.lhs_basis,
        " with ",
        error.rhs_basis,
        "; apply an explicit make/supply transformation first",
    )
end

"""
A vector whose codes and economic basis are part of its value. Consumers must
look values up by code or call `keyed_difference`; the latter refuses mixed
industry/commodity bases and aligns equal-basis vectors by code rather than
position.
"""
struct LabeledVector{B <: AxisBasis}
    codes::Vector{String}
    values::Vector{Float64}
    index::Dict{String, Int}

    function LabeledVector{B}(codes, values) where {B <: AxisBasis}
        string_codes = String.(collect(codes))
        float_values = Float64.(collect(values))
        length(string_codes) == length(float_values) ||
            throw(ArgumentError("labeled-vector code/value lengths differ"))
        length(unique(string_codes)) == length(string_codes) ||
            throw(ArgumentError("labeled-vector codes must be unique"))
        all(isfinite, float_values) ||
            throw(ArgumentError("labeled-vector values must be finite"))
        index = Dict(code => position for (position, code) in pairs(string_codes))
        return new{B}(string_codes, float_values, index)
    end
end

Base.length(vector::LabeledVector) = length(vector.codes)
Base.getindex(vector::LabeledVector, code::AbstractString) =
    vector.values[vector.index[String(code)]]

"""
A matrix with separately typed row and column bases. `explicit` distinguishes
published cells from structural zeroes materialized from the sparse BEA API
response.
"""
struct LabeledMatrix{R <: AxisBasis, C <: AxisBasis}
    row_codes::Vector{String}
    column_codes::Vector{String}
    values::Matrix{Float64}
    explicit::BitMatrix
    row_index::Dict{String, Int}
    column_index::Dict{String, Int}

    function LabeledMatrix{R, C}(
            row_codes,
            column_codes,
            values,
            explicit = trues(size(values)),
        ) where {R <: AxisBasis, C <: AxisBasis}
        rows = String.(collect(row_codes))
        columns = String.(collect(column_codes))
        matrix = Matrix{Float64}(values)
        mask = BitMatrix(explicit)
        size(matrix) == (length(rows), length(columns)) ||
            throw(ArgumentError("labeled-matrix dimensions do not match its axes"))
        size(mask) == size(matrix) ||
            throw(ArgumentError("labeled-matrix explicit mask has the wrong shape"))
        length(unique(rows)) == length(rows) ||
            throw(ArgumentError("labeled-matrix row codes must be unique"))
        length(unique(columns)) == length(columns) ||
            throw(ArgumentError("labeled-matrix column codes must be unique"))
        all(isfinite, matrix) ||
            throw(ArgumentError("labeled-matrix values must be finite"))
        row_index = Dict(code => position for (position, code) in pairs(rows))
        column_index =
            Dict(code => position for (position, code) in pairs(columns))
        return new{R, C}(
            rows,
            columns,
            matrix,
            mask,
            row_index,
            column_index,
        )
    end
end

Base.size(matrix::LabeledMatrix) = size(matrix.values)
Base.getindex(
    matrix::LabeledMatrix,
    row_code::AbstractString,
    column_code::AbstractString,
) = matrix.values[
    matrix.row_index[String(row_code)],
    matrix.column_index[String(column_code)],
]

"""
Subtract two equal-basis vectors after aligning by code. A positional
industry-output-minus-commodity-output calculation is rejected even when both
vectors happen to have the same length.
"""
function keyed_difference(
        lhs::LabeledVector{L},
        rhs::LabeledVector{R},
    ) where {L <: AxisBasis, R <: AxisBasis}
    L === R || throw(BasisMismatchError(L, R))
    Set(lhs.codes) == Set(rhs.codes) ||
        throw(ArgumentError("equal-basis vectors must have the same code set"))
    return LabeledVector{L}(lhs.codes, [lhs[code] - rhs[code] for code in lhs.codes])
end

struct IOCell
    table_id::String
    year::Int
    row_code::String
    row_type::String
    column_code::String
    column_type::String
    value::Float64

    function IOCell(
            table_id,
            year,
            row_code,
            row_type,
            column_code,
            column_type,
            value,
        )
        numeric_value = Float64(value)
        isfinite(numeric_value) ||
            throw(ArgumentError("I-O cell values must be finite"))
        return new(
            String(table_id),
            Int(year),
            String(row_code),
            String(row_type),
            String(column_code),
            String(column_type),
            numeric_value,
        )
    end
end

"""
Sparse, provenance-pinned view of one BEA I-O table. Missing matrix cells are
allowed because the API omits structural zeroes; required published controls
are always read with `required=true`.
"""
struct IOTable
    table_id::String
    year::Int
    source_sha256::String
    cells::Dict{Tuple{String, String}, IOCell}
    row_codes::Vector{String}
    column_codes::Vector{String}
end

function IOTable(cells; source_sha256 = "")
    materialized = IOCell[cell for cell in cells]
    isempty(materialized) && throw(ArgumentError("an I-O table cannot be empty"))
    table_ids = unique(cell.table_id for cell in materialized)
    years = unique(cell.year for cell in materialized)
    length(table_ids) == 1 ||
        throw(ArgumentError("I-O cells contain more than one table id"))
    length(years) == 1 ||
        throw(ArgumentError("I-O cells contain more than one year"))
    source_hash = lowercase(String(source_sha256))
    if !isempty(source_hash)
        occursin(r"^[0-9a-f]{64}$", source_hash) ||
            throw(ArgumentError("source SHA-256 must be 64 lowercase hex digits"))
    end
    lookup = Dict{Tuple{String, String}, IOCell}()
    rows = String[]
    columns = String[]
    for cell in materialized
        key = (cell.row_code, cell.column_code)
        haskey(lookup, key) &&
            throw(ArgumentError("duplicate I-O cell $(cell.table_id) $key"))
        lookup[key] = cell
        cell.row_code in rows || push!(rows, cell.row_code)
        cell.column_code in columns || push!(columns, cell.column_code)
    end
    return IOTable(first(table_ids), first(years), source_hash, lookup, rows, columns)
end

has_cell(table::IOTable, row_code::AbstractString, column_code::AbstractString) =
    haskey(table.cells, (String(row_code), String(column_code)))

function cell_value(
        table::IOTable,
        row_code::AbstractString,
        column_code::AbstractString;
        required = false,
    )
    key = (String(row_code), String(column_code))
    if haskey(table.cells, key)
        return table.cells[key].value
    end
    required &&
        throw(ArgumentError("required $(table.table_id) control cell $key is absent"))
    return 0.0
end

function parse_bea_value(value)
    text = strip(String(value))
    isempty(text) && throw(ArgumentError("BEA I-O value is blank"))
    negative_parentheses = startswith(text, "(") && endswith(text, ")")
    negative_parentheses && (text = text[2:(end - 1)])
    number = tryparse(Float64, replace(text, "," => ""))
    number === nothing &&
        throw(ArgumentError("BEA I-O value is not numeric: $(repr(value))"))
    result = negative_parentheses ? -number : number
    isfinite(result) || throw(ArgumentError("BEA I-O value must be finite"))
    return result
end

function sha256_hex(bytes)
    return bytes2hex(SHA.sha256(bytes))
end

"""
Load one archived BEA API response without network access. Optional expected
hash, table, and year arguments turn provenance mismatches into hard errors.
"""
function load_bea_json(
        path::AbstractString;
        expected_sha256 = nothing,
        expected_table_id = nothing,
        expected_year = nothing,
    )
    bytes = read(path)
    actual_hash = sha256_hex(bytes)
    if expected_sha256 !== nothing
        lowercase(String(expected_sha256)) == actual_hash ||
            throw(ArgumentError("archived BEA payload SHA-256 mismatch"))
    end
    payload = JSON.parse(String(bytes))
    haskey(payload, "BEAAPI") ||
        throw(ArgumentError("archived payload has no BEAAPI object"))
    results = get(payload["BEAAPI"], "Results", nothing)
    results isa AbstractVector && length(results) == 1 ||
        throw(ArgumentError("archived payload must contain exactly one result"))
    rows = get(first(results), "Data", nothing)
    rows isa AbstractVector ||
        throw(ArgumentError("archived payload result has no Data array"))
    cells = IOCell[]
    for row in rows
        push!(
            cells,
            IOCell(
                row["TableID"],
                parse(Int, String(row["Year"])),
                row["RowCode"],
                get(row, "RowType", ""),
                row["ColCode"],
                get(row, "ColType", ""),
                parse_bea_value(row["DataValue"]),
            ),
        )
    end
    table = IOTable(cells; source_sha256 = actual_hash)
    if expected_table_id !== nothing
        table.table_id == String(expected_table_id) ||
            throw(ArgumentError("unexpected BEA table id $(table.table_id)"))
    end
    if expected_year !== nothing
        table.year == Int(expected_year) ||
            throw(ArgumentError("unexpected BEA table year $(table.year)"))
    end
    return table
end

"""
Load the hermetic, numeric projection of approved archived Tables 259 and 262.
The bundle pins both source payload hashes and its own canonical CSV hash.
Descriptions and API envelope metadata are intentionally omitted; no numeric
cell used by the diagnostics is omitted.
"""
function load_canonical_fixture(directory::AbstractString)
    manifest_path = joinpath(directory, "manifest.toml")
    cells_path = joinpath(directory, "cells.csv")
    manifest = TOML.parsefile(manifest_path)
    get(manifest, "schema_version", "") ==
        "beforeit-us-supply-make-fixture.v1" ||
        throw(ArgumentError("unsupported supply/make fixture schema"))
    expected_fixture_hash = lowercase(String(manifest["fixture_sha256"]))
    actual_fixture_hash = sha256_hex(read(cells_path))
    expected_fixture_hash == actual_fixture_hash ||
        throw(ArgumentError("canonical fixture SHA-256 mismatch"))

    source_specs = Dict(
        String(spec["table_id"]) => spec for spec in manifest["sources"]
    )
    all(
        get(spec, "status", "") == "APPROVED_ARCHIVED"
            for spec in values(source_specs)
    ) || throw(ArgumentError("fixture contains a source that is not approved"))
    grouped = Dict{String, Vector{IOCell}}()
    loaded_cell_count = 0
    for row in CSV.File(cells_path)
        table_id = string(row.table_id)
        push!(
            get!(grouped, table_id, IOCell[]),
            IOCell(
                table_id,
                Int(row.year),
                String(row.row_code),
                String(row.row_type),
                String(row.column_code),
                String(row.column_type),
                Float64(row.value),
            ),
        )
        loaded_cell_count += 1
    end
    loaded_cell_count == Int(manifest["fixture_cell_count"]) ||
        throw(ArgumentError("fixture total cell count mismatch"))
    Set(keys(grouped)) == Set(keys(source_specs)) ||
        throw(ArgumentError("fixture tables do not match its manifest"))

    tables = Dict{String, IOTable}()
    for (table_id, cells) in grouped
        spec = source_specs[table_id]
        length(cells) == Int(spec["cell_count"]) ||
            throw(ArgumentError("fixture cell count mismatch for table $table_id"))
        table = IOTable(cells; source_sha256 = String(spec["source_sha256"]))
        table.year == Int(spec["year"]) ||
            throw(ArgumentError("fixture year mismatch for table $table_id"))
        tables[table_id] = table
    end
    haskey(tables, "259") && haskey(tables, "262") ||
        throw(ArgumentError("fixture must contain BEA Tables 259 and 262"))
    return (; use = tables["259"], supply = tables["262"], manifest)
end

"""
The worst-case residual when `term_count` independently rounded published
terms are summed and compared with one independently rounded control. BEA
Table 259/262 values are reported in whole millions of dollars.
"""
function published_rounding_tolerance(term_count::Integer; unit = 1.0)
    term_count >= 1 || throw(ArgumentError("rounding term count must be positive"))
    numeric_unit = Float64(unit)
    isfinite(numeric_unit) && numeric_unit > 0 ||
        throw(ArgumentError("rounding unit must be finite and positive"))
    return (Int(term_count) + 1) * numeric_unit / 2
end

struct ControlResidual
    family::Symbol
    code::String
    equation::String
    lhs::Float64
    rhs::Float64
    residual::Float64
    tolerance::Float64
    passed::Bool
end

function ControlResidual(
        family::Symbol,
        code,
        equation,
        lhs,
        rhs,
        tolerance,
    )
    numeric_lhs = Float64(lhs)
    numeric_rhs = Float64(rhs)
    numeric_tolerance = Float64(tolerance)
    all(isfinite, (numeric_lhs, numeric_rhs, numeric_tolerance)) ||
        throw(ArgumentError("control residual inputs must be finite"))
    numeric_tolerance >= 0 ||
        throw(ArgumentError("control residual tolerance cannot be negative"))
    residual = numeric_lhs - numeric_rhs
    return ControlResidual(
        family,
        String(code),
        String(equation),
        numeric_lhs,
        numeric_rhs,
        residual,
        numeric_tolerance,
        abs(residual) <= numeric_tolerance,
    )
end

struct SupplyMakeReport
    year::Int
    raw_make::LabeledMatrix{CommodityBasis, IndustryBasis}
    aggregated_make::LabeledMatrix{CommodityBasis, IndustryBasis}
    raw_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    aggregated_use::LabeledMatrix{CommodityBasis, IndustryBasis}
    raw_commodity_output::LabeledVector{CommodityBasis}
    raw_industry_output::LabeledVector{IndustryBasis}
    commodity_output::LabeledVector{CommodityBasis}
    industry_output::LabeledVector{IndustryBasis}
    purchaser_supply::LabeledVector{CommodityBasis}
    total_use::LabeledVector{CommodityBasis}
    commodity_mapping::Dict{String, String}
    industry_mapping::Dict{String, String}
    residuals::Vector{ControlResidual}
    explicit_closure_codes::Vector{String}
    transformation::Symbol
    balancing_applied::Bool
end

control_residuals(report::SupplyMakeReport, family::Symbol) =
    [residual for residual in report.residuals if residual.family == family]
controls_pass(report::SupplyMakeReport) = all(residual.passed for residual in report.residuals)

function ordered_unique(values)
    result = String[]
    for value in values
        text = String(value)
        text in result || push!(result, text)
    end
    return result
end

function explicit_retail_mapping(codes; preserve_closure = false)
    mapping = Dict{String, String}()
    for source_code in codes
        code = String(source_code)
        mapping[code] = code in RETAIL_SOURCE_CODES ? "4A0" : code
    end
    if preserve_closure
        for code in EXPLICIT_CLOSURE_CODES
            haskey(mapping, code) ||
                throw(ArgumentError("required closure commodity $code is absent"))
            mapping[code] == code ||
                throw(ArgumentError("closure commodity $code cannot be remapped"))
        end
    end
    for code in RETAIL_SOURCE_CODES
        haskey(mapping, code) ||
            throw(ArgumentError("retail source code $code is absent"))
    end
    return mapping
end

function aggregate_vector(vector::LabeledVector{B}, mapping) where {B <: AxisBasis}
    Set(keys(mapping)) == Set(vector.codes) ||
        throw(ArgumentError("aggregation mapping must cover exactly the source axis"))
    target_codes = ordered_unique(mapping[code] for code in vector.codes)
    values = Dict(code => 0.0 for code in target_codes)
    for code in vector.codes
        values[mapping[code]] += vector[code]
    end
    return LabeledVector{B}(target_codes, [values[code] for code in target_codes])
end

function aggregate_matrix(
        matrix::LabeledMatrix{R, C},
        row_mapping,
        column_mapping,
    ) where {R <: AxisBasis, C <: AxisBasis}
    Set(keys(row_mapping)) == Set(matrix.row_codes) ||
        throw(ArgumentError("row mapping must cover exactly the source rows"))
    Set(keys(column_mapping)) == Set(matrix.column_codes) ||
        throw(ArgumentError("column mapping must cover exactly the source columns"))
    target_rows =
        ordered_unique(row_mapping[source] for source in matrix.row_codes)
    target_columns =
        ordered_unique(column_mapping[source] for source in matrix.column_codes)
    row_index = Dict(code => index for (index, code) in pairs(target_rows))
    column_index =
        Dict(code => index for (index, code) in pairs(target_columns))
    values = zeros(length(target_rows), length(target_columns))
    explicit = falses(length(target_rows), length(target_columns))
    for (source_row_index, source_row) in pairs(matrix.row_codes)
        target_row_index = row_index[row_mapping[source_row]]
        for (source_column_index, source_column) in pairs(matrix.column_codes)
            target_column_index = column_index[column_mapping[source_column]]
            values[target_row_index, target_column_index] +=
                matrix.values[source_row_index, source_column_index]
            explicit[target_row_index, target_column_index] |=
                matrix.explicit[source_row_index, source_column_index]
        end
    end
    sum(values) == sum(matrix.values) ||
        throw(AssertionError("aggregation changed the make-matrix grand total"))
    return LabeledMatrix{R, C}(target_rows, target_columns, values, explicit)
end

function add_residual!(
        residuals,
        family,
        code,
        equation,
        lhs,
        rhs;
        term_count = 1,
        tolerance = published_rounding_tolerance(term_count),
    )
    push!(
        residuals,
        ControlResidual(family, code, equation, lhs, rhs, tolerance),
    )
    return residuals
end

function validate_table_contract(use::IOTable, supply::IOTable)
    use.table_id == "259" ||
        throw(ArgumentError("use input must be BEA Table 259"))
    supply.table_id == "262" ||
        throw(ArgumentError("supply input must be BEA Table 262"))
    use.year == supply.year ||
        throw(ArgumentError("BEA use and supply years differ"))
    for table in (use, supply)
        all(
            cell ->
            cell.row_type == "Commodity" &&
                cell.column_type == "Industry",
            values(table.cells),
        ) ||
            throw(
            ArgumentError(
                "BEA Table $(table.table_id) contains a mislabeled economic axis",
            ),
        )
    end
    for code in EXPLICIT_CLOSURE_CODES
        code in use.row_codes ||
            throw(ArgumentError("Table 259 omits explicit closure row $code"))
        code in supply.row_codes ||
            throw(ArgumentError("Table 262 omits explicit closure row $code"))
    end
    "T017" in supply.row_codes ||
        throw(ArgumentError("Table 262 omits T017 control row"))
    "T005" in use.row_codes ||
        throw(ArgumentError("Table 259 omits T005 control row"))
    return nothing
end

function source_axes(use::IOTable, supply::IOTable)
    supply_commodities = [
        code for code in supply.row_codes if code != "T017"
    ]
    possible_industries = Set(
        code for code in supply_commodities if !(code in EXPLICIT_CLOSURE_CODES)
    )
    supply_industries = [
        code for code in supply.column_codes if code in possible_industries
    ]
    unknown_supply_columns = [
        code for code in supply.column_codes if
            !(code in supply_industries) && !(code in SUPPLY_COMPONENT_CODES)
    ]
    isempty(unknown_supply_columns) ||
        throw(
        ArgumentError(
            "unclassified Table 262 columns: $unknown_supply_columns",
        ),
    )
    use_commodities = [
        code for code in use.row_codes if !(code in USE_CONTROL_ROWS)
    ]
    use_industries = [
        code for code in supply_industries if code in use.column_codes
    ]
    length(use_industries) == length(supply_industries) ||
        throw(ArgumentError("Table 259 is missing Table 262 industry columns"))
    unknown_use_columns = [
        code for code in use.column_codes if
            !(code in use_industries) &&
            code != "T001" &&
            code != "T019" &&
            !startswith(code, "F")
    ]
    isempty(unknown_use_columns) ||
        throw(ArgumentError("unclassified Table 259 columns: $unknown_use_columns"))
    final_use_codes = [code for code in use.column_codes if startswith(code, "F")]
    isempty(final_use_codes) &&
        throw(ArgumentError("Table 259 contains no final-use columns"))
    return (;
        supply_commodities,
        supply_industries,
        use_commodities,
        use_industries,
        final_use_codes,
    )
end

function make_matrix(supply, commodity_codes, industry_codes)
    values = zeros(length(commodity_codes), length(industry_codes))
    explicit = falses(size(values))
    for (row_index, commodity_code) in pairs(commodity_codes)
        for (column_index, industry_code) in pairs(industry_codes)
            values[row_index, column_index] =
                cell_value(supply, commodity_code, industry_code)
            explicit[row_index, column_index] =
                has_cell(supply, commodity_code, industry_code)
        end
    end
    return LabeledMatrix{CommodityBasis, IndustryBasis}(
        commodity_codes,
        industry_codes,
        values,
        explicit,
    )
end

function use_matrix(use, commodity_codes, industry_codes)
    values = zeros(length(commodity_codes), length(industry_codes))
    explicit = falses(size(values))
    for (row_index, commodity_code) in pairs(commodity_codes)
        for (column_index, industry_code) in pairs(industry_codes)
            values[row_index, column_index] =
                cell_value(use, commodity_code, industry_code)
            explicit[row_index, column_index] =
                has_cell(use, commodity_code, industry_code)
        end
    end
    return LabeledMatrix{CommodityBasis, IndustryBasis}(
        commodity_codes,
        industry_codes,
        values,
        explicit,
    )
end

"""
Build raw and explicitly aggregated make/supply diagnostics.

No residual is allocated, scaled, zeroed, or balanced. `transformation` is
always `:code_keyed_retail_aggregation_only`, and `balancing_applied` is
always false. `Other` and `Used` remain named rows in every commodity-axis
artifact and in the cross-table closure checks.
"""
function diagnose_supply_make(
        use::IOTable,
        supply::IOTable;
        expected_supply_commodity_count = nothing,
        expected_supply_industry_count = nothing,
        expected_use_commodity_count = nothing,
    )
    validate_table_contract(use, supply)
    axes = source_axes(use, supply)
    if expected_supply_commodity_count !== nothing
        length(axes.supply_commodities) ==
            Int(expected_supply_commodity_count) ||
            throw(ArgumentError("unexpected Table 262 commodity count"))
    end
    if expected_supply_industry_count !== nothing
        length(axes.supply_industries) ==
            Int(expected_supply_industry_count) ||
            throw(ArgumentError("unexpected Table 262 industry count"))
    end
    if expected_use_commodity_count !== nothing
        length(axes.use_commodities) == Int(expected_use_commodity_count) ||
            throw(ArgumentError("unexpected Table 259 commodity count"))
    end

    commodity_mapping =
        explicit_retail_mapping(axes.supply_commodities; preserve_closure = true)
    industry_mapping = explicit_retail_mapping(axes.supply_industries)
    mapped_commodities =
        Set(commodity_mapping[code] for code in axes.supply_commodities)
    mapped_commodities == Set(axes.use_commodities) ||
        throw(
        ArgumentError(
            "retail-aggregated Table 262 commodities do not match Table 259",
        ),
    )

    raw_make =
        make_matrix(supply, axes.supply_commodities, axes.supply_industries)
    aggregated_make =
        aggregate_matrix(raw_make, commodity_mapping, industry_mapping)
    raw_use = use_matrix(use, axes.use_commodities, axes.use_industries)
    use_row_mapping = Dict(code => code for code in axes.use_commodities)
    aggregated_use =
        aggregate_matrix(raw_use, use_row_mapping, industry_mapping)

    raw_commodity_output = LabeledVector{CommodityBasis}(
        axes.supply_commodities,
        [
            cell_value(supply, code, "T007"; required = true)
                for code in axes.supply_commodities
        ],
    )
    raw_industry_output = LabeledVector{IndustryBasis}(
        axes.supply_industries,
        [
            cell_value(supply, "T017", code; required = true)
                for code in axes.supply_industries
        ],
    )
    commodity_output =
        aggregate_vector(raw_commodity_output, commodity_mapping)
    industry_output = aggregate_vector(raw_industry_output, industry_mapping)

    raw_purchaser_supply = LabeledVector{CommodityBasis}(
        axes.supply_commodities,
        [
            cell_value(supply, code, "T016"; required = true)
                for code in axes.supply_commodities
        ],
    )
    purchaser_supply =
        aggregate_vector(raw_purchaser_supply, commodity_mapping)
    total_use = LabeledVector{CommodityBasis}(
        axes.use_commodities,
        [
            cell_value(use, code, "T019"; required = true)
                for code in axes.use_commodities
        ],
    )

    residuals = ControlResidual[]

    for (row_index, code) in pairs(raw_make.row_codes)
        add_residual!(
            residuals,
            :t007_commodity_make,
            code,
            "sum_industry(make[commodity,industry]) = T007",
            sum(@view raw_make.values[row_index, :]),
            raw_commodity_output[code];
            term_count = length(raw_make.column_codes),
        )
    end
    for (column_index, code) in pairs(raw_make.column_codes)
        add_residual!(
            residuals,
            :t007_industry_make,
            code,
            "sum_commodity(make[commodity,industry]) = T017 industry output",
            sum(@view raw_make.values[:, column_index]),
            raw_industry_output[code];
            term_count = length(raw_make.row_codes),
        )
    end
    add_residual!(
        residuals,
        :t007_grand_control,
        "commodity",
        "sum_commodity(T007) = T017/T007",
        sum(raw_commodity_output.values),
        cell_value(supply, "T017", "T007"; required = true);
        term_count = length(raw_commodity_output),
    )
    add_residual!(
        residuals,
        :t007_grand_control,
        "industry",
        "sum_industry(T017) = T017/T007",
        sum(raw_industry_output.values),
        cell_value(supply, "T017", "T007"; required = true);
        term_count = length(raw_industry_output),
    )

    supply_equations = (
        (
            :t013_basic_supply,
            ("T007", "MCIF", "MADJ"),
            "T007 + MCIF + MADJ = T013",
            "T013",
        ),
        (
            :t014_margins,
            ("Trade", "Trans"),
            "Trade + Trans = T014",
            "T014",
        ),
        (
            :t015_product_taxes,
            ("TOP", "MDTY", "SUB"),
            "TOP + MDTY + SUB = T015",
            "T015",
        ),
        (
            :t016_purchaser_supply,
            ("T013", "T014", "T015"),
            "T013 + T014 + T015 = T016",
            "T016",
        ),
    )
    for commodity_code in axes.supply_commodities
        for (family, components, equation, control) in supply_equations
            add_residual!(
                residuals,
                family,
                commodity_code,
                equation,
                sum(cell_value(supply, commodity_code, code) for code in components),
                cell_value(
                    supply,
                    commodity_code,
                    control;
                    required = control in ("T013", "T016"),
                );
                term_count = length(components),
            )
        end
    end
    for column_code in SUPPLY_COMPONENT_CODES
        add_residual!(
            residuals,
            :supply_column_control,
            column_code,
            "sum_commodity($column_code) = T017/$column_code",
            sum(
                cell_value(supply, commodity_code, column_code)
                    for commodity_code in axes.supply_commodities
            ),
            cell_value(supply, "T017", column_code; required = true);
            term_count = length(axes.supply_commodities),
        )
    end

    for commodity_code in axes.use_commodities
        add_residual!(
            residuals,
            :t001_intermediate_use,
            commodity_code,
            "sum_industry(use[commodity,industry]) = T001",
            sum(
                cell_value(use, commodity_code, industry_code)
                    for industry_code in axes.use_industries
            ),
            cell_value(use, commodity_code, "T001");
            term_count = length(axes.use_industries),
        )
        add_residual!(
            residuals,
            :t019_total_use,
            commodity_code,
            "T001 + sum_final_use = T019",
            cell_value(use, commodity_code, "T001") +
                sum(
                cell_value(use, commodity_code, final_code)
                    for final_code in axes.final_use_codes
            ),
            cell_value(use, commodity_code, "T019"; required = true);
            term_count = 1 + length(axes.final_use_codes),
        )
    end
    for industry_code in axes.use_industries
        add_residual!(
            residuals,
            :use_column_control,
            industry_code,
            "sum_commodity(use[commodity,industry]) = T005/industry",
            sum(
                cell_value(use, commodity_code, industry_code)
                    for commodity_code in axes.use_commodities
            ),
            cell_value(use, "T005", industry_code; required = true);
            term_count = length(axes.use_commodities),
        )
    end
    for final_code in axes.final_use_codes
        add_residual!(
            residuals,
            :use_column_control,
            final_code,
            "sum_commodity(use[commodity,final]) = T005/final",
            sum(
                cell_value(use, commodity_code, final_code)
                    for commodity_code in axes.use_commodities
            ),
            cell_value(use, "T005", final_code; required = true);
            term_count = length(axes.use_commodities),
        )
    end
    add_residual!(
        residuals,
        :t019_grand_control,
        "row",
        "sum_commodity(T019) = T005/T019",
        sum(total_use.values),
        cell_value(use, "T005", "T019"; required = true);
        term_count = length(total_use),
    )
    add_residual!(
        residuals,
        :t019_grand_control,
        "column",
        "T005/T001 + sum_final_controls = T005/T019",
        cell_value(use, "T005", "T001"; required = true) +
            sum(
            cell_value(use, "T005", final_code; required = true)
                for final_code in axes.final_use_codes
        ),
        cell_value(use, "T005", "T019"; required = true);
        term_count = 1 + length(axes.final_use_codes),
    )

    source_count_by_target = Dict{String, Int}()
    for target in values(commodity_mapping)
        source_count_by_target[target] = get(source_count_by_target, target, 0) + 1
    end
    for commodity_code in total_use.codes
        add_residual!(
            residuals,
            :t016_t019_supply_use,
            commodity_code,
            "retail-aggregated T016 = T019 at purchasers' prices",
            purchaser_supply[commodity_code],
            total_use[commodity_code];
            term_count = source_count_by_target[commodity_code],
        )
    end

    retail_supply_sources =
        sum(raw_purchaser_supply[code] for code in RETAIL_SOURCE_CODES)
    add_residual!(
        residuals,
        :retail_aggregation,
        "T016",
        "sum(T016[441,445,452,4A0]) = aggregated T016[4A0]",
        retail_supply_sources,
        purchaser_supply["4A0"];
        tolerance = 0.0,
    )
    add_residual!(
        residuals,
        :retail_aggregation,
        "T019",
        "aggregated T016[4A0] = Table 259 T019[4A0]",
        purchaser_supply["4A0"],
        total_use["4A0"];
        term_count = length(RETAIL_SOURCE_CODES),
    )
    add_residual!(
        residuals,
        :retail_aggregation,
        "T007",
        "sum(T007[441,445,452,4A0]) = aggregated commodity output[4A0]",
        sum(raw_commodity_output[code] for code in RETAIL_SOURCE_CODES),
        commodity_output["4A0"];
        tolerance = 0.0,
    )

    for code in EXPLICIT_CLOSURE_CODES
        code in aggregated_make.row_codes ||
            throw(AssertionError("aggregated make matrix dropped closure row $code"))
        code in aggregated_use.row_codes ||
            throw(AssertionError("aggregated use matrix dropped closure row $code"))
        code in purchaser_supply.codes ||
            throw(AssertionError("purchaser supply dropped closure row $code"))
        code in total_use.codes ||
            throw(AssertionError("total use dropped closure row $code"))
    end

    return SupplyMakeReport(
        use.year,
        raw_make,
        aggregated_make,
        raw_use,
        aggregated_use,
        raw_commodity_output,
        raw_industry_output,
        commodity_output,
        industry_output,
        purchaser_supply,
        total_use,
        commodity_mapping,
        industry_mapping,
        residuals,
        collect(EXPLICIT_CLOSURE_CODES),
        :code_keyed_retail_aggregation_only,
        false,
    )
end

end
