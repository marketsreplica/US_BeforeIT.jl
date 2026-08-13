module USBEAInventoryStockDiagnostic

using CSV
using DataFrames
using Dates
using JSON
using SHA
using TOML

export T50805BRowSemantic,
    StockLevel,
    ExcludedFinalSales,
    ExcludedRatio,
    InventoryStockObservation,
    PublishedIdentityResidual,
    PublishedRatioResidual,
    BEAInventoryStockReport,
    PROMOTION_BLOCKERS,
    FIXTURE_MANIFEST_SHA256,
    load_bea_inventory_stock_fixture,
    diagnose_bea_inventory_stocks,
    stock_observation,
    stock_value_millions,
    published_identities_pass,
    published_ratios_pass,
    write_bea_inventory_stock_fixture

const FIXTURE_SCHEMA = "beforeit-us-bea-inventory-stock-diagnostic.v1"
const APPROVED_SOURCE_SHA256 =
    "428eb140bc2977b78d65f55da0470e9d1eab2d75b2bba4ef021a4f1014bdefbe"
const APPROVED_SOURCE_BYTE_COUNT = 44_627
const APPROVED_WIRE_BYTE_COUNT = 44_641
const APPROVED_SOURCE_METADATA_SHA256 =
    "8c06cc9ff25b0c13af8bd40cf594b6b6b1073a97ffd4cf344f76365f1cf0bb97"
const APPROVED_CONTENT_FINGERPRINT_SHA256 =
    "e141b2edd846e8046af278b33e9fe3951e6416e03c41d953351b1784bc916ab1"
const APPROVED_API_PRODUCTION_TIME = "2026-08-06T02:44:47.180"
const APPROVED_RETRIEVAL_COMPLETED_AT = "2026-08-06T02:50:58.965Z"
const FIXTURE_MANIFEST_SHA256 =
    "c1e7c6aa1469557844307478170c9d4820898a49e67c258da49c0c596cbab3f6"
const TABLE_NAME = "T50805B"
const REFERENCE_PERIOD_LABEL = "2026Q1"
const REFERENCE_PERIOD = Date(2026, 3, 31)
const PUBLISHED_ROUNDING_UNIT_MILLIONS = 1.0
const RATIO_ROUNDING_TOLERANCE = 0.005

const END_OF_QUARTER_NOTE =
    "1. Inventories are as of the end of the quarter. The quarter-to-quarter " *
    "change in inventories calculated from current-dollar inventories in " *
    "this table is not the current-dollar change in private inventories " *
    "component of GDP. The former is the difference between two inventory " *
    "stocks, each valued at its respective end-of-quarter prices. The latter " *
    "is the change in the physical volume of inventories valued at average " *
    "prices of the quarter. In addition, changes calculated from this table " *
    "are at quarterly rates, whereas, the change in private inventories is " *
    "stated at annual rates."
const FINAL_SALES_NOTE =
    "2. Quarterly totals at monthly rates. Final sales of domestic business " *
    "equals final sales of domestic product less gross output of general " *
    "government, gross value added of nonprofit institutions, compensation " *
    "paid to domestic workers, and imputed rental of owner-occupied nonfarm " *
    "housing. It includes a small amount of final sales by farm and by " *
    "government enterprises."
const TABLE_NOTE =
    "Table 5.8.5B. Private Inventories and Domestic Final Sales by Industry " *
    "[Billions of dollars] - LastRevised: July 30, 2026"
const NAICS_NOTE =
    "Note. Estimates in this table are based on the North American Industry " *
    "Classification System (NAICS)."

@enum T50805BRowSemantic begin
    StockLevel
    ExcludedFinalSales
    ExcludedRatio
end

semantic_name(::Val{StockLevel}) = "STOCK_LEVEL"
semantic_name(::Val{ExcludedFinalSales}) = "EXCLUDED_FINAL_SALES"
semantic_name(::Val{ExcludedRatio}) = "EXCLUDED_RATIO"
semantic_name(value::T50805BRowSemantic) = semantic_name(Val(value))

function parse_semantic(value)
    text = String(value)
    text == "STOCK_LEVEL" && return StockLevel
    text == "EXCLUDED_FINAL_SALES" && return ExcludedFinalSales
    text == "EXCLUDED_RATIO" && return ExcludedRatio
    throw(ArgumentError("unsupported T50805B row semantic $text"))
end

const ROW_SPECS = (
    (
        line = 1,
        series = "A371RC",
        description = "Private inventories",
        semantic = StockLevel,
        role = "PRIMARY_HOLDER_TOTAL",
        note_ref = "T50805B,T50805B.1",
    ),
    (
        line = 2,
        series = "B372RC",
        description = "Farm",
        semantic = StockLevel,
        role = "PRIMARY_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 3,
        series = "N238RC",
        description = "Mining, utilities, and construction",
        semantic = StockLevel,
        role = "PRIMARY_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 4,
        series = "N376RC",
        description = "Manufacturing",
        semantic = StockLevel,
        role = "PRIMARY_PARTITION_CONTROL",
        note_ref = "T50805B",
    ),
    (
        line = 5,
        series = "N377RC",
        description = "Durable goods industries",
        semantic = StockLevel,
        role = "MANUFACTURING_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 6,
        series = "N378RC",
        description = "Nondurable goods industries",
        semantic = StockLevel,
        role = "MANUFACTURING_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 7,
        series = "N379RC",
        description = "Wholesale trade",
        semantic = StockLevel,
        role = "PRIMARY_PARTITION_CONTROL",
        note_ref = "T50805B",
    ),
    (
        line = 8,
        series = "N380RC",
        description = "Durable goods industries",
        semantic = StockLevel,
        role = "WHOLESALE_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 9,
        series = "N381RC",
        description = "Nondurable goods industries",
        semantic = StockLevel,
        role = "WHOLESALE_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 10,
        series = "N382RC",
        description = "Retail trade",
        semantic = StockLevel,
        role = "PRIMARY_PARTITION_CONTROL",
        note_ref = "T50805B",
    ),
    (
        line = 11,
        series = "N864RC",
        description = "Motor vehicle and parts dealers",
        semantic = StockLevel,
        role = "RETAIL_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 12,
        series = "N239RC",
        description = "Food and beverage stores",
        semantic = StockLevel,
        role = "RETAIL_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 13,
        series = "N240RC",
        description = "General merchandise stores",
        semantic = StockLevel,
        role = "RETAIL_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 14,
        series = "N865RC",
        description = "Other retail stores",
        semantic = StockLevel,
        role = "RETAIL_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 15,
        series = "N385RC",
        description = "Other industries",
        semantic = StockLevel,
        role = "PRIMARY_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 16,
        series = "A371RC",
        description = "Private inventories",
        semantic = StockLevel,
        role = "DUPLICATE_TOTAL_CONTROL",
        note_ref = "T50805B",
    ),
    (
        line = 17,
        series = "N241RC",
        description = "Durable goods industries",
        semantic = StockLevel,
        role = "ALTERNATE_DURABILITY_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 18,
        series = "N242RC",
        description = "Nondurable goods industries",
        semantic = StockLevel,
        role = "ALTERNATE_DURABILITY_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 19,
        series = "A373RC",
        description = "Nonfarm industries",
        semantic = StockLevel,
        role = "SUPPLEMENTAL_HOLDER_CONTROL",
        note_ref = "T50805B",
    ),
    (
        line = 20,
        series = "N379RC",
        description = "Wholesale trade",
        semantic = StockLevel,
        role = "DUPLICATE_SUBTOTAL_CONTROL",
        note_ref = "T50805B",
    ),
    (
        line = 21,
        series = "N802RC",
        description = "Merchant wholesale trade",
        semantic = StockLevel,
        role = "WHOLESALE_TYPE_PARTITION_CONTROL",
        note_ref = "T50805B",
    ),
    (
        line = 22,
        series = "N803RC",
        description = "Durable goods industries",
        semantic = StockLevel,
        role = "MERCHANT_DURABILITY_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 23,
        series = "N804RC",
        description = "Nondurable goods industries",
        semantic = StockLevel,
        role = "MERCHANT_DURABILITY_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 24,
        series = "N805RC",
        description = "Nonmerchant wholesale trade",
        semantic = StockLevel,
        role = "WHOLESALE_TYPE_PARTITION_COMPONENT",
        note_ref = "T50805B",
    ),
    (
        line = 25,
        series = "A809RC",
        description = "Final sales of domestic business",
        semantic = ExcludedFinalSales,
        role = "RATIO_DENOMINATOR_NOT_STOCK",
        note_ref = "T50805B,T50805B.2",
    ),
    (
        line = 26,
        series = "A810RC",
        description =
            "Final sales of goods and structures of domestic business",
        semantic = ExcludedFinalSales,
        role = "RATIO_DENOMINATOR_NOT_STOCK",
        note_ref = "T50805B,T50805B.2",
    ),
    (
        line = 27,
        series = "A811RC",
        description = "Private inventories to final sales",
        semantic = ExcludedRatio,
        role = "PUBLISHED_RATIO_NOT_STOCK",
        note_ref = "T50805B",
    ),
    (
        line = 28,
        series = "A812RC",
        description = "Nonfarm inventories to final sales",
        semantic = ExcludedRatio,
        role = "PUBLISHED_RATIO_NOT_STOCK",
        note_ref = "T50805B",
    ),
    (
        line = 29,
        series = "A813RC",
        description =
            "Nonfarm inventories to final sales of goods and structures",
        semantic = ExcludedRatio,
        role = "PUBLISHED_RATIO_NOT_STOCK",
        note_ref = "T50805B",
    ),
)

const IDENTITY_SPECS = (
    (
        id = "primary_holder_partition",
        lhs = 1,
        rhs = [2, 3, 4, 7, 10, 15],
    ),
    (id = "manufacturing_durability", lhs = 4, rhs = [5, 6]),
    (id = "wholesale_durability", lhs = 7, rhs = [8, 9]),
    (id = "retail_detail", lhs = 10, rhs = [11, 12, 13, 14]),
    (id = "private_total_duplicate", lhs = 1, rhs = [16]),
    (id = "private_total_durability", lhs = 16, rhs = [17, 18]),
    (id = "farm_nonfarm_partition", lhs = 16, rhs = [2, 19]),
    (
        id = "nonfarm_holder_partition",
        lhs = 19,
        rhs = [3, 4, 7, 10, 15],
    ),
    (id = "wholesale_total_duplicate", lhs = 7, rhs = [20]),
    (id = "wholesale_merchant_partition", lhs = 20, rhs = [21, 24]),
    (id = "merchant_wholesale_durability", lhs = 21, rhs = [22, 23]),
)

const RATIO_SPECS = (
    (
        id = "private_inventory_to_final_sales",
        numerator = 1,
        denominator = 25,
        published = 27,
    ),
    (
        id = "nonfarm_inventory_to_final_sales",
        numerator = 19,
        denominator = 25,
        published = 28,
    ),
    (
        id = "nonfarm_inventory_to_goods_and_structures_final_sales",
        numerator = 19,
        denominator = 26,
        published = 29,
    ),
)

const PROMOTION_BLOCKERS = [
    "CURRENT_VINTAGE_NOT_FIRST_RELEASE_ORIGIN_EVIDENCE",
    "NO_HOLDER_TO_MODEL_SECTOR_MAPPING",
    "NO_HOLDER_TO_COMMODITY_BRIDGE",
    "NO_END_OF_QUARTER_PRICE_TO_MODEL_VALUATION_BRIDGE",
    "NO_INVENTORY_STAGE_DECOMPOSITION",
    "NO_STAGE_TO_MODEL_STOCK_SCOPE_BRIDGE",
    "NO_LATENT_STATE_RECONCILIATION",
]

const FIXTURE_COLUMNS = [
    :table_name,
    :series_code,
    :line_number,
    :line_description,
    :time_period,
    :metric_name,
    :cl_unit,
    :unit_mult,
    :data_value,
    :numeric_value,
    :economic_unit,
    :note_ref,
    :row_semantic,
    :counting_role,
]

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function parse_bea_value(value)
    text = strip(String(value))
    isempty(text) && throw(ArgumentError("BEA T50805B value is blank"))
    negative = startswith(text, "(") && endswith(text, ")")
    negative && (text = text[2:(end - 1)])
    numeric = tryparse(Float64, replace(text, "," => ""))
    numeric === nothing &&
        throw(ArgumentError("BEA T50805B value is not numeric"))
    result = negative ? -numeric : numeric
    isfinite(result) ||
        throw(ArgumentError("BEA T50805B value must be finite"))
    return result
end

function row_spec(line_number::Integer)
    index = findfirst(spec -> spec.line == line_number, ROW_SPECS)
    index === nothing &&
        throw(ArgumentError("unsupported T50805B line $line_number"))
    return ROW_SPECS[index]
end

function expected_metric(spec)
    if spec.semantic == ExcludedRatio
        return (
            metric_name = "Current Dollar Ratios",
            cl_unit = "Level",
            unit_mult = 0,
            economic_unit = "ratio",
        )
    end
    return (
        metric_name = "Current Dollars",
        cl_unit = "Level",
        unit_mult = 6,
        economic_unit = "millions_current_usd",
    )
end

struct InventoryStockObservation
    table_name::String
    series_code::String
    line_number::Int
    line_description::String
    reference_period::Date
    metric_name::String
    cl_unit::String
    unit_mult::Int
    data_value::String
    numeric_value::Float64
    economic_unit::Symbol
    note_ref::String
    semantic::T50805BRowSemantic
    counting_role::String

    function InventoryStockObservation(
            table_name,
            series_code,
            line_number,
            line_description,
            reference_period,
            metric_name,
            cl_unit,
            unit_mult,
            data_value,
            numeric_value,
            economic_unit,
            note_ref,
            semantic,
            counting_role,
        )
        line = Int(line_number)
        spec = row_spec(line)
        parsed_semantic =
            semantic isa T50805BRowSemantic ?
            semantic : parse_semantic(semantic)
        parsed_semantic == spec.semantic ||
            throw(ArgumentError("T50805B line $line semantic changed"))
        expected = expected_metric(spec)
        String(table_name) == TABLE_NAME ||
            throw(ArgumentError("inventory-stock observation has wrong table"))
        String(series_code) == spec.series ||
            throw(ArgumentError("T50805B line $line series changed"))
        String(line_description) == spec.description ||
            throw(ArgumentError("T50805B line $line description changed"))
        Date(reference_period) == REFERENCE_PERIOD ||
            throw(ArgumentError("T50805B observation has wrong quarter"))
        String(metric_name) == expected.metric_name ||
            throw(ArgumentError("T50805B line $line metric changed"))
        String(cl_unit) == expected.cl_unit ||
            throw(ArgumentError("T50805B line $line level selector changed"))
        Int(unit_mult) == expected.unit_mult ||
            throw(ArgumentError("T50805B line $line unit multiplier changed"))
        Symbol(economic_unit) == Symbol(expected.economic_unit) ||
            throw(ArgumentError("T50805B line $line economic unit changed"))
        String(note_ref) == spec.note_ref ||
            throw(ArgumentError("T50805B line $line note reference changed"))
        String(counting_role) == spec.role ||
            throw(ArgumentError("T50805B line $line counting role changed"))
        parsed_value = parse_bea_value(data_value)
        value = Float64(numeric_value)
        isfinite(value) ||
            throw(ArgumentError("T50805B numeric value must be finite"))
        value == parsed_value ||
            throw(ArgumentError("T50805B text and numeric values differ"))
        value > 0 ||
            throw(ArgumentError("T50805B Q1 values must be positive"))
        return new(
            TABLE_NAME,
            spec.series,
            line,
            spec.description,
            REFERENCE_PERIOD,
            expected.metric_name,
            expected.cl_unit,
            expected.unit_mult,
            String(data_value),
            value,
            Symbol(expected.economic_unit),
            spec.note_ref,
            parsed_semantic,
            spec.role,
        )
    end
end

function stock_value_millions(observation::InventoryStockObservation)
    observation.semantic == StockLevel ||
        throw(ArgumentError("non-stock T50805B rows have no stock value"))
    observation.economic_unit == :millions_current_usd ||
        throw(ArgumentError("stock row does not use millions of current dollars"))
    return observation.numeric_value
end

struct PublishedIdentityResidual
    identity_id::String
    lhs_line::Int
    rhs_lines::Vector{Int}
    lhs_millions::Float64
    rhs_millions::Float64
    residual_millions::Float64
    tolerance_millions::Float64
    passed::Bool
end

struct PublishedRatioResidual
    identity_id::String
    numerator_line::Int
    denominator_line::Int
    published_line::Int
    calculated_ratio::Float64
    published_ratio::Float64
    residual::Float64
    tolerance::Float64
    passed::Bool
end

struct BEAInventoryStockReport
    reference_period::Date
    observations::Vector{InventoryStockObservation}
    observation_index::Dict{Int, Int}
    stock_line_numbers::Vector{Int}
    excluded_line_numbers::Vector{Int}
    private_inventory_total_millions::Float64
    duplicate_private_inventory_total_millions::Float64
    identity_residuals::Vector{PublishedIdentityResidual}
    ratio_residuals::Vector{PublishedRatioResidual}
    stock_time_semantics::Symbol
    holder_basis::Symbol
    valuation_basis::Symbol
    duplicate_rows_preserved::Bool
    duplicate_rows_double_counted::Bool
    annual_rate_division_applied::Bool
    flow_conversion_applied::Bool
    holder_to_model_sector_mapping_applied::Bool
    holder_to_commodity_bridge_applied::Bool
    valuation_bridge_applied::Bool
    inventory_stage_decomposition_applied::Bool
    stage_to_model_stock_scope_bridge_applied::Bool
    latent_state_reconciliation_applied::Bool
    model_inventory_vector_emitted::Bool
    forecast_origin_admissible::Bool
    accounting_gate_effect::Symbol
    model_state_write_authorized::Bool
    promotion_ready::Bool
    promotion_blockers::Vector{String}
    manifest::Dict{String, Any}
end

function stock_observation(report::BEAInventoryStockReport, line_number::Integer)
    index = get(report.observation_index, Int(line_number), nothing)
    index === nothing &&
        throw(KeyError("T50805B line $(Int(line_number))"))
    observation = report.observations[index]
    observation.semantic == StockLevel ||
        throw(ArgumentError("T50805B line $(Int(line_number)) is not stock"))
    return observation
end

published_identities_pass(report::BEAInventoryStockReport) =
    all(residual.passed for residual in report.identity_residuals)
published_ratios_pass(report::BEAInventoryStockReport) =
    all(residual.passed for residual in report.ratio_residuals)

function published_rounding_tolerance(rhs_term_count::Integer)
    rhs_term_count >= 1 ||
        throw(ArgumentError("identity must contain at least one right-hand term"))
    return (rhs_term_count + 1) * PUBLISHED_ROUNDING_UNIT_MILLIONS / 2
end

function build_identity_residuals(observations, index)
    residuals = PublishedIdentityResidual[]
    for spec in IDENTITY_SPECS
        lhs_observation = observations[index[spec.lhs]]
        rhs_observations = [observations[index[line]] for line in spec.rhs]
        lhs_observation.semantic == StockLevel &&
            all(item -> item.semantic == StockLevel, rhs_observations) ||
            throw(ArgumentError("published stock identity includes a non-stock row"))
        lhs = stock_value_millions(lhs_observation)
        rhs = sum(stock_value_millions, rhs_observations)
        tolerance = published_rounding_tolerance(length(spec.rhs))
        residual = lhs - rhs
        push!(
            residuals,
            PublishedIdentityResidual(
                spec.id,
                spec.lhs,
                copy(spec.rhs),
                lhs,
                rhs,
                residual,
                tolerance,
                abs(residual) <= tolerance,
            ),
        )
    end
    return residuals
end

function build_ratio_residuals(observations, index)
    residuals = PublishedRatioResidual[]
    for spec in RATIO_SPECS
        numerator = stock_value_millions(observations[index[spec.numerator]])
        denominator_observation = observations[index[spec.denominator]]
        published_observation = observations[index[spec.published]]
        denominator_observation.semantic == ExcludedFinalSales ||
            throw(ArgumentError("ratio denominator was relabeled as stock"))
        published_observation.semantic == ExcludedRatio ||
            throw(ArgumentError("published ratio was relabeled as stock"))
        denominator = denominator_observation.numeric_value
        published = published_observation.numeric_value
        calculated = numerator / denominator
        residual = published - calculated
        push!(
            residuals,
            PublishedRatioResidual(
                spec.id,
                spec.numerator,
                spec.denominator,
                spec.published,
                calculated,
                published,
                residual,
                RATIO_ROUNDING_TOLERANCE,
                abs(residual) <= RATIO_ROUNDING_TOLERANCE,
            ),
        )
    end
    return residuals
end

function validate_observation_set(observations)
    length(observations) == length(ROW_SPECS) ||
        throw(ArgumentError("T50805B fixture must contain exactly 29 Q1 rows"))
    line_numbers = [observation.line_number for observation in observations]
    line_numbers == collect(1:29) ||
        throw(ArgumentError("T50805B fixture line axis must be ordered 1:29"))
    length(unique(line_numbers)) == length(line_numbers) ||
        throw(ArgumentError("T50805B fixture line numbers must be unique"))
    count(item -> item.semantic == StockLevel, observations) == 24 ||
        throw(ArgumentError("T50805B fixture must preserve 24 stock rows"))
    count(item -> item.semantic == ExcludedFinalSales, observations) == 2 ||
        throw(ArgumentError("T50805B fixture must exclude two final-sales rows"))
    count(item -> item.semantic == ExcludedRatio, observations) == 3 ||
        throw(ArgumentError("T50805B fixture must exclude three ratio rows"))
    return nothing
end

function observations_from_frame(frame::DataFrame)
    Symbol.(names(frame)) == FIXTURE_COLUMNS ||
        throw(ArgumentError("T50805B fixture columns changed"))
    observations = InventoryStockObservation[]
    for row in eachrow(frame)
        String(row.time_period) == REFERENCE_PERIOD_LABEL ||
            throw(ArgumentError("T50805B fixture period label changed"))
        push!(
            observations,
            InventoryStockObservation(
                row.table_name,
                row.series_code,
                row.line_number,
                row.line_description,
                REFERENCE_PERIOD,
                row.metric_name,
                row.cl_unit,
                row.unit_mult,
                row.data_value,
                row.numeric_value,
                row.economic_unit,
                row.note_ref,
                row.row_semantic,
                row.counting_role,
            ),
        )
    end
    validate_observation_set(observations)
    return observations
end

function require_false(manifest, key)
    get(manifest, key, nothing) === false ||
        throw(ArgumentError("T50805B manifest requires $key=false"))
    return nothing
end

function validate_manifest(manifest, cells_path)
    get(manifest, "schema_version", "") == FIXTURE_SCHEMA ||
        throw(ArgumentError("unsupported T50805B fixture schema"))
    get(manifest, "fixture_sha256", "") == sha256_hex(read(cells_path)) ||
        throw(ArgumentError("T50805B fixture SHA-256 mismatch"))
    Int(get(manifest, "fixture_row_count", -1)) == 29 ||
        throw(ArgumentError("T50805B fixture row count changed"))
    get(manifest, "table_name", "") == TABLE_NAME ||
        throw(ArgumentError("T50805B fixture table changed"))
    get(manifest, "reference_period", "") == REFERENCE_PERIOD_LABEL ||
        throw(ArgumentError("T50805B fixture quarter changed"))
    get(manifest, "stock_line_numbers", Int[]) == collect(1:24) ||
        throw(ArgumentError("T50805B stock-line contract changed"))
    get(manifest, "excluded_line_numbers", Int[]) == collect(25:29) ||
        throw(ArgumentError("T50805B excluded-line contract changed"))
    get(manifest, "source_sha256", "") == APPROVED_SOURCE_SHA256 ||
        throw(ArgumentError("T50805B source SHA-256 mismatch"))
    Int(get(manifest, "source_byte_count", -1)) ==
        APPROVED_SOURCE_BYTE_COUNT ||
        throw(ArgumentError("T50805B source byte count mismatch"))
    Int(get(manifest, "source_wire_byte_count", -1)) ==
        APPROVED_WIRE_BYTE_COUNT ||
        throw(ArgumentError("T50805B source wire-byte count mismatch"))
    get(manifest, "source_metadata_sha256", "") ==
        APPROVED_SOURCE_METADATA_SHA256 ||
        throw(ArgumentError("T50805B source-metadata SHA-256 mismatch"))
    get(manifest, "source_content_fingerprint_sha256", "") ==
        APPROVED_CONTENT_FINGERPRINT_SHA256 ||
        throw(ArgumentError("T50805B content fingerprint mismatch"))
    get(manifest, "api_production_time_utc", "") ==
        APPROVED_API_PRODUCTION_TIME * "Z" ||
        throw(ArgumentError("T50805B API production time changed"))
    get(manifest, "retrieval_completed_at_utc", "") ==
        APPROVED_RETRIEVAL_COMPLETED_AT ||
        throw(ArgumentError("T50805B retrieval timestamp changed"))
    get(manifest, "last_revised", "") == "July 30, 2026" ||
        throw(ArgumentError("T50805B revision date changed"))
    get(manifest, "classification", "") ==
        "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE" ||
        throw(ArgumentError("T50805B fixture classification changed"))
    get(manifest, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("T50805B fixture cannot affect accounting gates"))
    get(manifest, "stock_time_semantics", "") ==
        "END_OF_QUARTER_LEVEL_NOT_AN_ANNUAL_RATE" ||
        throw(ArgumentError("T50805B stock-time semantics changed"))
    get(manifest, "valuation_basis", "") ==
        "CURRENT_DOLLARS_AT_RESPECTIVE_END_OF_QUARTER_PRICES" ||
        throw(ArgumentError("T50805B valuation semantics changed"))
    get(manifest, "duplicate_policy", "") ==
        "PRESERVE_PUBLISHED_DUPLICATES; ADDRESS_BY_LINE; NEVER_SUM_ALL_STOCK_ROWS" ||
        throw(ArgumentError("T50805B duplicate policy changed"))
    get(manifest, "promotion_blockers", String[]) == PROMOTION_BLOCKERS ||
        throw(ArgumentError("T50805B promotion blockers changed"))
    for key in (
            "annual_rate_division_applied",
            "flow_conversion_applied",
            "duplicate_rows_double_counted",
            "wire_payload_archived",
            "holder_to_model_sector_mapping_applied",
            "holder_to_commodity_bridge_applied",
            "valuation_bridge_applied",
            "inventory_stage_decomposition_applied",
            "stage_to_model_stock_scope_bridge_applied",
            "latent_state_reconciliation_applied",
            "model_inventory_vector_emitted",
            "forecast_origin_admissible",
            "model_state_write_authorized",
            "promotion_ready",
        )
        require_false(manifest, key)
    end
    get(manifest, "duplicate_rows_preserved", nothing) === true ||
        throw(ArgumentError("T50805B published duplicates must be preserved"))
    return nothing
end

function load_bea_inventory_stock_fixture(directory::AbstractString)
    manifest_path = joinpath(directory, "manifest.toml")
    cells_path = joinpath(directory, "cells.csv")
    isfile(manifest_path) ||
        throw(ArgumentError("missing T50805B fixture manifest"))
    isfile(cells_path) ||
        throw(ArgumentError("missing T50805B fixture cells"))
    sha256_hex(read(manifest_path)) == FIXTURE_MANIFEST_SHA256 ||
        throw(ArgumentError("T50805B fixture manifest SHA-256 mismatch"))
    manifest = TOML.parsefile(manifest_path)
    validate_manifest(manifest, cells_path)
    frame = CSV.read(cells_path, DataFrame; stringtype = String)
    observations = observations_from_frame(frame)
    return (; observations, manifest, manifest_path, cells_path)
end

function diagnose_bea_inventory_stocks(fixture)
    observations = fixture.observations
    validate_observation_set(observations)
    index = Dict(
        observation.line_number => position
            for (position, observation) in pairs(observations)
    )
    identities = build_identity_residuals(observations, index)
    ratios = build_ratio_residuals(observations, index)
    all(residual.passed for residual in identities) ||
        throw(ArgumentError("T50805B published stock identities failed"))
    all(residual.passed for residual in ratios) ||
        throw(ArgumentError("T50805B published ratios failed"))
    total = stock_value_millions(observations[index[1]])
    duplicate_total = stock_value_millions(observations[index[16]])
    total == duplicate_total ||
        throw(ArgumentError("T50805B duplicate private totals differ"))
    return BEAInventoryStockReport(
        REFERENCE_PERIOD,
        observations,
        index,
        collect(1:24),
        collect(25:29),
        total,
        duplicate_total,
        identities,
        ratios,
        :end_of_quarter_level,
        :published_holder_industry,
        :current_dollars_at_respective_end_of_quarter_prices,
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
        :none,
        false,
        false,
        copy(PROMOTION_BLOCKERS),
        fixture.manifest,
    )
end

function payload_request_map(payload)
    result = Dict{String, String}()
    for parameter in payload["BEAAPI"]["Request"]["RequestParam"]
        name = uppercase(String(parameter["ParameterName"]))
        haskey(result, name) &&
            throw(ArgumentError("duplicate BEA request parameter"))
        result[name] = String(parameter["ParameterValue"])
    end
    return result
end

function validate_archived_source(source_bytes, metadata)
    sha256_hex(source_bytes) == APPROVED_SOURCE_SHA256 ||
        throw(ArgumentError("archived T50805B source SHA-256 mismatch"))
    length(source_bytes) == APPROVED_SOURCE_BYTE_COUNT ||
        throw(ArgumentError("archived T50805B source byte count mismatch"))
    payload = JSON.parse(String(copy(source_bytes)))
    request = payload_request_map(payload)
    request == Dict(
        "USERID" => "[REDACTED:BEA_API_KEY]",
        "METHOD" => "GETDATA",
        "DATASETNAME" => "NIPA",
        "TABLENAME" => TABLE_NAME,
        "FREQUENCY" => "Q",
        "YEAR" => "2025,2026",
        "RESULTFORMAT" => "JSON",
    ) || throw(ArgumentError("archived T50805B request echo changed"))
    results = payload["BEAAPI"]["Results"]
    String(results["UTCProductionTime"]) == APPROVED_API_PRODUCTION_TIME ||
        throw(ArgumentError("archived T50805B API production time changed"))
    String(results["Statistic"]) == "NIPA Table" ||
        throw(ArgumentError("archived T50805B statistic changed"))
    notes = Dict(
        String(note["NoteRef"]) => String(note["NoteText"])
            for note in results["Notes"]
    )
    notes == Dict(
        "T50805B" => TABLE_NOTE,
        "T50805B.1" => END_OF_QUARTER_NOTE,
        "T50805B.2" => FINAL_SALES_NOTE,
        "T50805B.3" => NAICS_NOTE,
    ) || throw(ArgumentError("archived T50805B notes changed"))
    rows = results["Data"]
    length(rows) == 174 ||
        throw(ArgumentError("archived T50805B row count changed"))

    get(metadata, "redacted_sha256", "") == APPROVED_SOURCE_SHA256 ||
        throw(ArgumentError("T50805B sidecar source binding changed"))
    Int(get(metadata, "redacted_byte_count", -1)) ==
        APPROVED_SOURCE_BYTE_COUNT ||
        throw(ArgumentError("T50805B sidecar byte count changed"))
    Int(get(metadata, "wire_byte_count", -1)) ==
        APPROVED_WIRE_BYTE_COUNT ||
        throw(ArgumentError("T50805B sidecar wire-byte count changed"))
    tryparse(Int, String(get(metadata, "content_length", ""))) ==
        APPROVED_WIRE_BYTE_COUNT ||
        throw(ArgumentError("T50805B sidecar Content-Length changed"))
    get(metadata, "content_fingerprint_sha256", "") ==
        APPROVED_CONTENT_FINGERPRINT_SHA256 ||
        throw(ArgumentError("T50805B sidecar content fingerprint changed"))
    get(metadata, "retrieval_completed_at_utc", "") ==
        APPROVED_RETRIEVAL_COMPLETED_AT ||
        throw(ArgumentError("T50805B sidecar retrieval time changed"))
    get(metadata, "api_production_time_utc", "") ==
        APPROVED_API_PRODUCTION_TIME * "Z" ||
        throw(ArgumentError("T50805B sidecar production time changed"))
    get(metadata, "http_status", 0) == 200 ||
        throw(ArgumentError("T50805B sidecar does not record HTTP 200"))
    get(metadata, "request", Dict{String, Any}()) == Dict(
        "method" => "GetData",
        "DataSetName" => "NIPA",
        "TableName" => TABLE_NAME,
        "Frequency" => "Q",
        "Year" => "2025,2026",
        "ResultFormat" => "JSON",
    ) || throw(ArgumentError("T50805B sidecar query changed"))
    redaction = get(metadata, "redaction", Dict{String, Any}())
    get(redaction, "request_field", "") == "UserID" &&
        get(redaction, "replacement", "") == "[REDACTED:BEA_API_KEY]" &&
        get(redaction, "occurrence_count", 0) == 1 &&
        get(redaction, "wire_payload_archived", true) === false ||
        throw(ArgumentError("T50805B sidecar redaction contract changed"))
    get(metadata, "vintage_classification", "") ==
        "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE" ||
        throw(ArgumentError("T50805B sidecar classification changed"))
    get(metadata, "forecast_origin_admissible", true) === false ||
        throw(ArgumentError("T50805B sidecar origin flag changed"))
    get(metadata, "accounting_gate_effect", "") == "NONE" ||
        throw(ArgumentError("T50805B sidecar gate flag changed"))
    get(metadata, "model_state_write_authorized", true) === false ||
        throw(ArgumentError("T50805B sidecar state-write flag changed"))
    get(metadata, "promotion_ready", true) === false ||
        throw(ArgumentError("T50805B sidecar promotion flag changed"))
    return rows
end

function project_q1_rows(rows)
    q1_rows = [
        row for row in rows
            if String(row["TimePeriod"]) == REFERENCE_PERIOD_LABEL
    ]
    length(q1_rows) == 29 ||
        throw(ArgumentError("archived T50805B must contain 29 Q1 rows"))
    sort!(q1_rows; by = row -> parse(Int, String(row["LineNumber"])))
    projected = NamedTuple[]
    for (position, row) in pairs(q1_rows)
        line = parse(Int, String(row["LineNumber"]))
        line == position ||
            throw(ArgumentError("archived T50805B Q1 line axis changed"))
        spec = row_spec(line)
        expected = expected_metric(spec)
        String(row["TableName"]) == TABLE_NAME ||
            throw(ArgumentError("T50805B Q1 table selector changed"))
        String(row["SeriesCode"]) == spec.series ||
            throw(ArgumentError("T50805B Q1 series selector changed"))
        String(row["LineDescription"]) == spec.description ||
            throw(ArgumentError("T50805B Q1 description changed"))
        String(row["METRIC_NAME"]) == expected.metric_name ||
            throw(ArgumentError("T50805B Q1 metric changed"))
        String(row["CL_UNIT"]) == expected.cl_unit ||
            throw(ArgumentError("T50805B Q1 level selector changed"))
        parse(Int, String(row["UNIT_MULT"])) == expected.unit_mult ||
            throw(ArgumentError("T50805B Q1 unit multiplier changed"))
        String(row["NoteRef"]) == spec.note_ref ||
            throw(ArgumentError("T50805B Q1 note reference changed"))
        data_value = String(row["DataValue"])
        push!(
            projected,
            (
                table_name = TABLE_NAME,
                series_code = spec.series,
                line_number = line,
                line_description = spec.description,
                time_period = REFERENCE_PERIOD_LABEL,
                metric_name = expected.metric_name,
                cl_unit = expected.cl_unit,
                unit_mult = expected.unit_mult,
                data_value,
                numeric_value = parse_bea_value(data_value),
                economic_unit = expected.economic_unit,
                note_ref = spec.note_ref,
                row_semantic = semantic_name(spec.semantic),
                counting_role = spec.role,
            ),
        )
    end
    frame = DataFrame(projected)
    observations_from_frame(frame)
    return frame
end

function write_exclusive(path, bytes)
    if isfile(path)
        read(path) == bytes ||
            throw(ArgumentError("refusing to overwrite different fixture bytes"))
        return false
    end
    temporary_path, io = mktemp(dirname(path))
    try
        write(io, bytes)
        close(io)
        mv(temporary_path, path; force = false)
    catch
        isopen(io) && close(io)
        isfile(temporary_path) && rm(temporary_path)
        rethrow()
    end
    return true
end

function write_bea_inventory_stock_fixture(
        source_path::AbstractString,
        metadata_path::AbstractString,
        output_directory::AbstractString,
    )
    source_bytes = read(source_path)
    metadata_bytes = read(metadata_path)
    sha256_hex(metadata_bytes) == APPROVED_SOURCE_METADATA_SHA256 ||
        throw(ArgumentError("archived T50805B metadata SHA-256 mismatch"))
    metadata = JSON.parse(String(copy(metadata_bytes)))
    rows = validate_archived_source(source_bytes, metadata)
    frame = project_q1_rows(rows)

    cells_io = IOBuffer()
    CSV.write(cells_io, frame)
    cells_bytes = take!(cells_io)
    fixture_sha256 = sha256_hex(cells_bytes)
    manifest = Dict{String, Any}(
        "schema_version" => FIXTURE_SCHEMA,
        "fixture_sha256" => fixture_sha256,
        "fixture_row_count" => nrow(frame),
        "table_name" => TABLE_NAME,
        "reference_period" => REFERENCE_PERIOD_LABEL,
        "stock_line_numbers" => collect(1:24),
        "excluded_line_numbers" => collect(25:29),
        "source_sha256" => APPROVED_SOURCE_SHA256,
        "source_byte_count" => APPROVED_SOURCE_BYTE_COUNT,
        "source_wire_byte_count" => APPROVED_WIRE_BYTE_COUNT,
        "source_metadata_sha256" => APPROVED_SOURCE_METADATA_SHA256,
        "source_content_fingerprint_sha256" =>
            APPROVED_CONTENT_FINGERPRINT_SHA256,
        "api_production_time_utc" =>
            APPROVED_API_PRODUCTION_TIME * "Z",
        "retrieval_completed_at_utc" =>
            APPROVED_RETRIEVAL_COMPLETED_AT,
        "last_revised" => "July 30, 2026",
        "classification" =>
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE",
        "projection" =>
            "All 29 published 2026Q1 rows, selectors, descriptions, units, " *
            "values, note references, and explicit stock/exclusion roles.",
        "stock_time_semantics" =>
            "END_OF_QUARTER_LEVEL_NOT_AN_ANNUAL_RATE",
        "valuation_basis" =>
            "CURRENT_DOLLARS_AT_RESPECTIVE_END_OF_QUARTER_PRICES",
        "duplicate_policy" =>
            "PRESERVE_PUBLISHED_DUPLICATES; ADDRESS_BY_LINE; NEVER_SUM_ALL_STOCK_ROWS",
        "duplicate_rows_preserved" => true,
        "duplicate_rows_double_counted" => false,
        "annual_rate_division_applied" => false,
        "flow_conversion_applied" => false,
        "wire_payload_archived" => false,
        "holder_to_model_sector_mapping_applied" => false,
        "holder_to_commodity_bridge_applied" => false,
        "valuation_bridge_applied" => false,
        "inventory_stage_decomposition_applied" => false,
        "stage_to_model_stock_scope_bridge_applied" => false,
        "latent_state_reconciliation_applied" => false,
        "model_inventory_vector_emitted" => false,
        "forecast_origin_admissible" => false,
        "accounting_gate_effect" => "NONE",
        "model_state_write_authorized" => false,
        "promotion_ready" => false,
        "promotion_blockers" => PROMOTION_BLOCKERS,
        "published_rounding_unit_millions" =>
            PUBLISHED_ROUNDING_UNIT_MILLIONS,
        "published_ratio_rounding_tolerance" =>
            RATIO_ROUNDING_TOLERANCE,
        "source_notes" => Dict(
            "table" => TABLE_NOTE,
            "end_of_quarter" => END_OF_QUARTER_NOTE,
            "final_sales" => FINAL_SALES_NOTE,
            "naics" => NAICS_NOTE,
        ),
    )
    manifest_io = IOBuffer()
    TOML.print(manifest_io, manifest; sorted = true)
    println(manifest_io)
    manifest_bytes = take!(manifest_io)

    mkpath(output_directory)
    cells_path = joinpath(output_directory, "cells.csv")
    manifest_path = joinpath(output_directory, "manifest.toml")
    write_exclusive(cells_path, cells_bytes)
    write_exclusive(manifest_path, manifest_bytes)
    return (;
        frame,
        manifest,
        cells_path,
        manifest_path,
        fixture_sha256,
        manifest_sha256 = sha256_hex(manifest_bytes),
    )
end

end # module
