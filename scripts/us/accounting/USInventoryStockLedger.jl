module USInventoryStockLedger

using CSV
using DataFrames
using Dates
using SHA
using TOML

export FIXTURE_SCHEMA,
    FIXTURE_MANIFEST_SHA256,
    LEDGER_COLUMNS,
    PROMOTION_BLOCKERS,
    InventoryObservation,
    InventoryIdentityResidual,
    InventoryStockLedger,
    identity_residuals,
    load_inventory_stock_fixture,
    observation,
    stage_additivity_pass,
    validate_inventory_stock_ledger

const FIXTURE_SCHEMA = "beforeit-us-inventory-stock-ledger-fixture.v1"
const FIXTURE_MANIFEST_SHA256 =
    "60d011228150a9ce7f8ade01b4bf74c32de5ef103584c54f7ba6e6372c592af6"
const LEDGER_COLUMNS = (
    :observation_id,
    :series_id,
    :reference_period,
    :published_value,
    :value_millions_current_usd,
)
const ECONOMIC_UNIT = "millions_current_usd"
const STOCK_TIME_BASIS = "end_of_period"
const CLASSIFICATION = "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE"
const PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const SOURCE_STATUS = "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE"
const MISSING_VALUES_POLICY = "MISSING_NOT_ZERO"
const EMPTY_SHA256 =
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const M3_SOURCE_ID = "census_m3_contract"
const M3_HOLDER_CODE = "31-33"
const M3_INVENTORY_SCOPE = "manufacturing"
const M3_VALUATION_BASIS = :non_lifo_cost
const M3_COVERAGE_STATUS = "PARTIAL_HOLDER_COVERAGE"
const EXPECTED_COVERED_HOLDER_CODES = (M3_HOLDER_CODE,)
const EXPECTED_IDENTITY_TOLERANCE_MILLIONS_USD = 0.0
const ALLOWED_STAGES =
    Set(["TOTAL", "MATERIALS", "WORK_IN_PROCESS", "FINISHED_GOODS"])
const PROMOTION_BLOCKERS = [
    "SOURCE_BYTES_NOT_PINNED",
    "SOURCE_VINTAGE_NOT_ORIGIN_ADMISSIBLE",
    "HOLDER_TO_COMMODITY_BRIDGE_NOT_APPLIED",
    "COST_TO_MODEL_PRICE_VALUATION_BRIDGE_NOT_APPLIED",
    "STAGE_TO_MODEL_STOCK_SCOPE_BRIDGE_NOT_APPLIED",
    "SECTOR_COVERAGE_INCOMPLETE",
    "MODEL_STATE_RECONCILIATION_NOT_APPLIED",
]

const TOP_LEVEL_KEYS = Set(
    [
        "schema_version",
        "fixture_id",
        "fixture_sha256",
        "fixture_row_count",
        "economic_unit",
        "stock_time_basis",
        "classification",
        "promotion_status",
        "forecast_origin_admissible",
        "model_state_write_authorized",
        "accounting_gate_effect",
        "boundary",
        "sources",
        "series",
        "identities",
    ],
)
const BOUNDARY_KEYS = Set(
    [
        "holder_to_commodity_bridge_applied",
        "valuation_bridge_applied",
        "stage_to_model_stock_scope_bridge_applied",
        "sector_coverage_complete",
        "model_state_reconciliation_applied",
        "model_inventory_vector_emitted",
        "production_promotion_ready",
        "missing_values_policy",
        "covered_holder_codes",
        "promotion_blockers",
    ],
)
const SOURCE_KEYS = Set(
    [
        "source_id",
        "source_agency",
        "dataset_id",
        "publication_id",
        "source_status",
        "raw_sha256",
        "raw_byte_count",
        "metadata_sha256",
        "release_timestamp_utc",
        "retrieved_at_utc",
        "frequency",
        "seasonal_adjustment",
        "annual_rate_flag",
        "saar_divisor",
        "stock_flow_index_rate",
        "published_unit",
        "multiplier_to_millions",
        "price_basis",
        "valuation_basis",
        "period_semantics",
        "economic_basis",
        "coverage_scope",
        "vintage_classification",
        "origin_admissible",
        "usage_role",
    ],
)
const SERIES_KEYS = Set(
    [
        "series_id",
        "source_id",
        "published_series_code",
        "description",
        "holder_basis",
        "holder_code",
        "inventory_stage",
        "inventory_scope",
        "coverage_status",
        "usage_role",
    ],
)
const IDENTITY_KEYS = Set(
    [
        "identity_id",
        "equation",
        "lhs_observation_ids",
        "rhs_observation_ids",
        "tolerance_millions_usd",
    ],
)

struct InventoryObservation
    observation_id::String
    series_id::String
    source_id::String
    reference_period::Date
    published_value::Float64
    value_millions_current_usd::Float64
    holder_basis::Symbol
    holder_code::String
    inventory_stage::Symbol
    inventory_scope::String
    valuation_basis::Symbol
    coverage_status::String
end

struct InventoryIdentityResidual
    identity_id::String
    equation::String
    lhs::Float64
    rhs::Float64
    residual::Float64
    tolerance_millions_usd::Float64
    passed::Bool
end

struct InventoryStockLedger
    observations::Vector{InventoryObservation}
    observation_index::Dict{String, Int}
    residuals::Vector{InventoryIdentityResidual}
    covered_holder_codes::Vector{String}
    missing_values_policy::Symbol
    holder_to_commodity_bridge_applied::Bool
    valuation_bridge_applied::Bool
    stage_to_model_stock_scope_bridge_applied::Bool
    sector_coverage_complete::Bool
    model_state_reconciliation_applied::Bool
    model_inventory_vector_emitted::Bool
    forecast_origin_admissible::Bool
    model_state_write_authorized::Bool
    promotion_ready::Bool
    promotion_blockers::Vector{String}
    manifest::Dict{String, Any}
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function require_exact_keys(value, expected::Set{String}, location::AbstractString)
    value isa AbstractDict ||
        throw(ArgumentError("$location must be a table"))
    actual = Set(String.(keys(value)))
    actual == expected ||
        throw(
        ArgumentError(
            "$location keys differ from the frozen inventory-stock contract",
        ),
    )
    return nothing
end

function require_false(value, location::AbstractString)
    value === false ||
        throw(ArgumentError("$location must remain false"))
    return false
end

function require_nonempty_string(value, location::AbstractString)
    value isa AbstractString && !isempty(strip(String(value))) ||
        throw(ArgumentError("$location must be a nonempty string"))
    return String(value)
end

function require_sha256(value, location::AbstractString)
    text = lowercase(require_nonempty_string(value, location))
    occursin(r"^[0-9a-f]{64}$", text) ||
        throw(ArgumentError("$location must be a lowercase SHA-256 digest"))
    return text
end

function require_finite_nonnegative(value, location::AbstractString)
    number = Float64(value)
    isfinite(number) && number >= 0 ||
        throw(ArgumentError("$location must be finite and nonnegative"))
    return number
end

function is_quarter_end(date::Date)
    month(date) in (3, 6, 9, 12) || return false
    return date == lastdayofmonth(date)
end

function validate_source(source, index)
    location = "sources[$index]"
    require_exact_keys(source, SOURCE_KEYS, location)
    source_id = require_nonempty_string(source["source_id"], "$location.source_id")
    require_nonempty_string(source["source_agency"], "$location.source_agency")
    require_nonempty_string(source["dataset_id"], "$location.dataset_id")
    require_nonempty_string(source["publication_id"], "$location.publication_id")
    source["source_status"] == SOURCE_STATUS ||
        throw(ArgumentError("$location is not explicitly synthetic"))
    require_sha256(source["raw_sha256"], "$location.raw_sha256") == EMPTY_SHA256 ||
        throw(ArgumentError("$location raw digest must identify empty content"))
    Int(source["raw_byte_count"]) == 0 ||
        throw(ArgumentError("$location cannot claim archived source bytes"))
    require_sha256(source["metadata_sha256"], "$location.metadata_sha256") ==
        EMPTY_SHA256 ||
        throw(ArgumentError("$location metadata digest must identify empty content"))
    source["release_timestamp_utc"] == "not_applicable_synthetic" ||
        throw(ArgumentError("$location release timestamp is not synthetic"))
    source["retrieved_at_utc"] == "not_applicable_synthetic" ||
        throw(ArgumentError("$location retrieval timestamp is not synthetic"))
    source["frequency"] in ("monthly", "quarterly") ||
        throw(ArgumentError("$location has an unsupported frequency"))
    source["seasonal_adjustment"] == "seasonally_adjusted" ||
        throw(ArgumentError("$location must declare seasonal adjustment"))
    require_false(source["annual_rate_flag"], "$location.annual_rate_flag")
    Float64(source["saar_divisor"]) == 1.0 ||
        throw(ArgumentError("$location stock must never be divided by four"))
    source["stock_flow_index_rate"] == "STOCK" ||
        throw(ArgumentError("$location is not a stock source"))
    published_unit = String(source["published_unit"])
    multiplier = Float64(source["multiplier_to_millions"])
    if published_unit == "billions_current_usd"
        multiplier == 1000.0 ||
            throw(ArgumentError("$location billions conversion must be ×1000"))
    elseif published_unit == "millions_current_usd"
        multiplier == 1.0 ||
            throw(ArgumentError("$location millions conversion must be ×1"))
    else
        throw(ArgumentError("$location has an unsupported published unit"))
    end
    source["price_basis"] in ("current_cost", "book_cost") ||
        throw(ArgumentError("$location has an unsupported price basis"))
    source["valuation_basis"] in
        ("current_replacement_cost", "non_lifo_cost") ||
        throw(ArgumentError("$location has an unsupported valuation basis"))
    source["period_semantics"] == STOCK_TIME_BASIS ||
        throw(ArgumentError("$location is not end-of-period"))
    source["economic_basis"] == "holder_industry" ||
        throw(ArgumentError("$location is not on the holder-industry basis"))
    require_nonempty_string(source["coverage_scope"], "$location.coverage_scope")
    source["vintage_classification"] == CLASSIFICATION ||
        throw(ArgumentError("$location has the wrong vintage classification"))
    require_false(source["origin_admissible"], "$location.origin_admissible")
    source["usage_role"] == "CONTROL_ONLY" ||
        throw(ArgumentError("$location usage must remain control-only"))
    return source_id
end

function validate_series(series, index, source_ids)
    location = "series[$index]"
    require_exact_keys(series, SERIES_KEYS, location)
    series_id = require_nonempty_string(series["series_id"], "$location.series_id")
    String(series["source_id"]) in source_ids ||
        throw(ArgumentError("$location references an unknown source"))
    require_nonempty_string(
        series["published_series_code"],
        "$location.published_series_code",
    )
    require_nonempty_string(series["description"], "$location.description")
    series["holder_basis"] == "holder_industry" ||
        throw(ArgumentError("$location holder basis cannot be commodity"))
    require_nonempty_string(series["holder_code"], "$location.holder_code")
    String(series["inventory_stage"]) in ALLOWED_STAGES ||
        throw(ArgumentError("$location has an unsupported inventory stage"))
    require_nonempty_string(series["inventory_scope"], "$location.inventory_scope")
    series["coverage_status"] in ("AGGREGATE_CONTROL", "PARTIAL_HOLDER_COVERAGE") ||
        throw(ArgumentError("$location has an unsupported coverage status"))
    series["usage_role"] == "CONTROL_ONLY" ||
        throw(ArgumentError("$location usage must remain control-only"))
    return series_id
end

function validate_boundary(boundary)
    require_exact_keys(boundary, BOUNDARY_KEYS, "boundary")
    require_false(
        boundary["holder_to_commodity_bridge_applied"],
        "boundary.holder_to_commodity_bridge_applied",
    )
    require_false(
        boundary["valuation_bridge_applied"],
        "boundary.valuation_bridge_applied",
    )
    require_false(
        boundary["stage_to_model_stock_scope_bridge_applied"],
        "boundary.stage_to_model_stock_scope_bridge_applied",
    )
    require_false(
        boundary["sector_coverage_complete"],
        "boundary.sector_coverage_complete",
    )
    require_false(
        boundary["model_state_reconciliation_applied"],
        "boundary.model_state_reconciliation_applied",
    )
    require_false(
        boundary["model_inventory_vector_emitted"],
        "boundary.model_inventory_vector_emitted",
    )
    require_false(
        boundary["production_promotion_ready"],
        "boundary.production_promotion_ready",
    )
    boundary["missing_values_policy"] == MISSING_VALUES_POLICY ||
        throw(ArgumentError("missing values must not be interpreted as zero"))
    covered_holder_codes = String.(boundary["covered_holder_codes"])
    length(unique(covered_holder_codes)) == length(covered_holder_codes) ||
        throw(ArgumentError("covered holder codes must be unique"))
    Tuple(covered_holder_codes) == EXPECTED_COVERED_HOLDER_CODES ||
        throw(
        ArgumentError(
            "covered holder codes differ from the frozen partial-coverage boundary",
        ),
    )
    String.(boundary["promotion_blockers"]) == PROMOTION_BLOCKERS ||
        throw(ArgumentError("promotion blockers differ from the frozen boundary"))
    return covered_holder_codes
end

function validate_manifest(manifest, cells_path)
    require_exact_keys(manifest, TOP_LEVEL_KEYS, "manifest")
    manifest["schema_version"] == FIXTURE_SCHEMA ||
        throw(ArgumentError("unsupported inventory-stock fixture schema"))
    require_nonempty_string(manifest["fixture_id"], "manifest.fixture_id")
    require_sha256(manifest["fixture_sha256"], "manifest.fixture_sha256") ==
        sha256_hex(read(cells_path)) ||
        throw(ArgumentError("inventory-stock fixture SHA-256 mismatch"))
    Int(manifest["fixture_row_count"]) >= 1 ||
        throw(ArgumentError("inventory-stock fixture must contain rows"))
    manifest["economic_unit"] == ECONOMIC_UNIT ||
        throw(ArgumentError("unsupported inventory-stock economic unit"))
    manifest["stock_time_basis"] == STOCK_TIME_BASIS ||
        throw(ArgumentError("fixture does not contain end-of-period stocks"))
    manifest["classification"] == CLASSIFICATION ||
        throw(ArgumentError("fixture must remain explicitly synthetic"))
    manifest["promotion_status"] == PROMOTION_STATUS ||
        throw(ArgumentError("fixture promotion status changed"))
    require_false(
        manifest["forecast_origin_admissible"],
        "manifest.forecast_origin_admissible",
    )
    require_false(
        manifest["model_state_write_authorized"],
        "manifest.model_state_write_authorized",
    )
    manifest["accounting_gate_effect"] == "NONE" ||
        throw(ArgumentError("fixture cannot alter accounting gates"))

    covered_holder_codes = validate_boundary(manifest["boundary"])

    sources = manifest["sources"]
    sources isa AbstractVector && !isempty(sources) ||
        throw(ArgumentError("manifest sources must be a nonempty array"))
    source_ids = [
        validate_source(source, index)
            for (index, source) in pairs(sources)
    ]
    length(unique(source_ids)) == length(source_ids) ||
        throw(ArgumentError("source identifiers must be unique"))
    source_id_set = Set(source_ids)

    series = manifest["series"]
    series isa AbstractVector && !isempty(series) ||
        throw(ArgumentError("manifest series must be a nonempty array"))
    series_ids = [
        validate_series(entry, index, source_id_set)
            for (index, entry) in pairs(series)
    ]
    length(unique(series_ids)) == length(series_ids) ||
        throw(ArgumentError("series identifiers must be unique"))

    identities = manifest["identities"]
    identities isa AbstractVector && !isempty(identities) ||
        throw(ArgumentError("manifest identities must be a nonempty array"))
    identity_ids = String[]
    for (index, identity) in pairs(identities)
        location = "identities[$index]"
        require_exact_keys(identity, IDENTITY_KEYS, location)
        push!(
            identity_ids,
            require_nonempty_string(
                identity["identity_id"],
                "$location.identity_id",
            ),
        )
        identity["equation"] ==
            "total = materials + work_in_process + finished_goods" ||
            throw(ArgumentError("$location has an unsupported equation"))
        lhs = String.(identity["lhs_observation_ids"])
        rhs = String.(identity["rhs_observation_ids"])
        length(lhs) == 1 ||
            throw(ArgumentError("$location must have exactly one total"))
        length(rhs) == 3 && length(unique(rhs)) == 3 ||
            throw(ArgumentError("$location must have three unique stages"))
        isempty(intersect(Set(lhs), Set(rhs))) ||
            throw(ArgumentError("$location cannot repeat a term across sides"))
        tolerance = require_finite_nonnegative(
            identity["tolerance_millions_usd"],
            "$location.tolerance_millions_usd",
        )
        tolerance == EXPECTED_IDENTITY_TOLERANCE_MILLIONS_USD ||
            throw(
            ArgumentError(
                "$location tolerance differs from the exact synthetic identity",
            ),
        )
    end
    length(unique(identity_ids)) == length(identity_ids) ||
        throw(ArgumentError("identity identifiers must be unique"))

    return (; covered_holder_codes, source_ids, series_ids)
end

function build_observations(frame, manifest)
    series_by_id =
        Dict(String(entry["series_id"]) => entry for entry in manifest["series"])
    source_by_id =
        Dict(String(entry["source_id"]) => entry for entry in manifest["sources"])
    observations = InventoryObservation[]
    for row in eachrow(frame)
        series_id = String(row.series_id)
        haskey(series_by_id, series_id) ||
            throw(ArgumentError("observation references an unknown series"))
        series = series_by_id[series_id]
        source = source_by_id[String(series["source_id"])]
        published_value = require_finite_nonnegative(
            row.published_value,
            "observation $(row.observation_id) published value",
        )
        value_millions = require_finite_nonnegative(
            row.value_millions_current_usd,
            "observation $(row.observation_id) converted value",
        )
        expected =
            published_value * Float64(source["multiplier_to_millions"])
        value_millions == expected ||
            throw(
            ArgumentError(
                "observation $(row.observation_id) violates the published-unit conversion",
            ),
        )
        reference_period = Date(row.reference_period)
        is_quarter_end(reference_period) ||
            throw(
            ArgumentError(
                "observation $(row.observation_id) is not calendar-quarter-end",
            ),
        )
        push!(
            observations,
            InventoryObservation(
                String(row.observation_id),
                series_id,
                String(series["source_id"]),
                reference_period,
                published_value,
                value_millions,
                Symbol(series["holder_basis"]),
                String(series["holder_code"]),
                Symbol(lowercase(String(series["inventory_stage"]))),
                String(series["inventory_scope"]),
                Symbol(source["valuation_basis"]),
                String(series["coverage_status"]),
            ),
        )
    end
    return observations
end

function build_identity_residuals(observations, identities)
    by_id = Dict(item.observation_id => item for item in observations)
    residuals = InventoryIdentityResidual[]
    for identity in identities
        lhs_ids = String.(identity["lhs_observation_ids"])
        rhs_ids = String.(identity["rhs_observation_ids"])
        referenced = [lhs_ids; rhs_ids]
        all(id -> haskey(by_id, id), referenced) ||
            throw(ArgumentError("inventory identity references a missing observation"))
        lhs = sum(by_id[id].value_millions_current_usd for id in lhs_ids)
        rhs = sum(by_id[id].value_millions_current_usd for id in rhs_ids)
        total = by_id[only(lhs_ids)]
        rhs_stages = Set(by_id[id].inventory_stage for id in rhs_ids)
        total.inventory_stage == :total ||
            throw(ArgumentError("inventory identity left side is not total"))
        rhs_stages ==
            Set([:materials, :work_in_process, :finished_goods]) ||
            throw(ArgumentError("inventory identity right-side stages are incomplete"))
        all(
            id ->
            by_id[id].holder_basis == total.holder_basis &&
                by_id[id].holder_code == total.holder_code &&
                by_id[id].reference_period == total.reference_period &&
                by_id[id].source_id == total.source_id &&
                by_id[id].valuation_basis == total.valuation_basis &&
                by_id[id].inventory_scope == total.inventory_scope &&
                by_id[id].coverage_status == total.coverage_status,
            rhs_ids,
        ) ||
            throw(
            ArgumentError(
                "inventory identity mixes holders, periods, sources, valuation bases, scopes, or coverage statuses",
            ),
        )
        identity_terms = [total; [by_id[id] for id in rhs_ids]]
        all(
            item ->
            item.source_id == M3_SOURCE_ID &&
                item.holder_basis == :holder_industry &&
                item.holder_code == M3_HOLDER_CODE &&
                item.inventory_scope == M3_INVENTORY_SCOPE &&
                item.valuation_basis == M3_VALUATION_BASIS &&
                item.coverage_status == M3_COVERAGE_STATUS,
            identity_terms,
        ) ||
            throw(
            ArgumentError(
                "inventory identity does not preserve the frozen M3 manufacturing semantics",
            ),
        )
        tolerance = Float64(identity["tolerance_millions_usd"])
        residual = lhs - rhs
        push!(
            residuals,
            InventoryIdentityResidual(
                String(identity["identity_id"]),
                String(identity["equation"]),
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

function validate_inventory_stock_ledger(ledger::InventoryStockLedger)
    !isempty(ledger.observations) ||
        throw(ArgumentError("inventory-stock ledger is empty"))
    all(
        item ->
        isfinite(item.value_millions_current_usd) &&
            item.value_millions_current_usd >= 0,
        ledger.observations,
    ) ||
        throw(ArgumentError("inventory-stock ledger contains invalid values"))
    all(item -> item.holder_basis == :holder_industry, ledger.observations) ||
        throw(ArgumentError("inventory-stock ledger mixes economic bases"))
    ledger.missing_values_policy == :missing_not_zero ||
        throw(ArgumentError("missing inventory sectors cannot be zero-filled"))
    !ledger.holder_to_commodity_bridge_applied ||
        throw(ArgumentError("holder-to-commodity bridge cannot be claimed"))
    !ledger.valuation_bridge_applied ||
        throw(ArgumentError("valuation bridge cannot be claimed"))
    !ledger.stage_to_model_stock_scope_bridge_applied ||
        throw(
        ArgumentError(
            "stage-to-model-stock scope bridge cannot be claimed",
        ),
    )
    !ledger.sector_coverage_complete ||
        throw(ArgumentError("sector coverage cannot be claimed complete"))
    !ledger.model_state_reconciliation_applied ||
        throw(ArgumentError("model-state reconciliation cannot be claimed"))
    !ledger.model_inventory_vector_emitted ||
        throw(ArgumentError("model inventory vector cannot be emitted"))
    !ledger.forecast_origin_admissible ||
        throw(ArgumentError("synthetic fixture cannot be origin-admissible"))
    !ledger.model_state_write_authorized ||
        throw(ArgumentError("synthetic fixture cannot authorize model writes"))
    !ledger.promotion_ready ||
        throw(ArgumentError("inventory-stock checkpoint cannot promote"))
    ledger.promotion_blockers == PROMOTION_BLOCKERS ||
        throw(ArgumentError("inventory-stock promotion blockers changed"))
    return ledger
end

function load_inventory_stock_fixture(directory::AbstractString)
    manifest_path = joinpath(directory, "manifest.toml")
    cells_path = joinpath(directory, "inventory_stock_ledger.csv")
    isfile(manifest_path) ||
        throw(ArgumentError("missing inventory-stock fixture manifest"))
    isfile(cells_path) ||
        throw(ArgumentError("missing inventory-stock fixture CSV"))
    manifest_bytes = read(manifest_path)
    sha256_hex(manifest_bytes) == FIXTURE_MANIFEST_SHA256 ||
        throw(ArgumentError("inventory-stock manifest SHA-256 mismatch"))
    manifest = TOML.parse(String(manifest_bytes))
    validated = validate_manifest(manifest, cells_path)
    frame = CSV.read(
        cells_path,
        DataFrame;
        types = Dict(
            :observation_id => String,
            :series_id => String,
            :reference_period => Date,
            :published_value => Float64,
            :value_millions_current_usd => Float64,
        ),
    )
    Symbol.(names(frame)) == collect(LEDGER_COLUMNS) ||
        throw(ArgumentError("inventory-stock fixture columns changed"))
    nrow(frame) == Int(manifest["fixture_row_count"]) ||
        throw(ArgumentError("inventory-stock fixture row count changed"))
    canonical_order = sortperm(
        1:nrow(frame);
        by = index ->
        (frame.reference_period[index], frame.observation_id[index]),
    )
    canonical_order == collect(1:nrow(frame)) ||
        throw(ArgumentError("inventory-stock fixture rows are not canonical"))
    length(unique(frame.observation_id)) == nrow(frame) ||
        throw(ArgumentError("observation identifiers must be unique"))
    length(unique(frame.series_id)) == nrow(frame) ||
        throw(ArgumentError("each synthetic series must have one observation"))
    Set(frame.series_id) == Set(validated.series_ids) ||
        throw(ArgumentError("fixture observations and manifest series differ"))

    observations = build_observations(frame, manifest)
    observation_index =
        Dict(item.observation_id => index for (index, item) in pairs(observations))
    residuals = build_identity_residuals(observations, manifest["identities"])
    boundary = manifest["boundary"]
    ledger = InventoryStockLedger(
        observations,
        observation_index,
        residuals,
        validated.covered_holder_codes,
        :missing_not_zero,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        copy(PROMOTION_BLOCKERS),
        manifest,
    )
    return validate_inventory_stock_ledger(ledger)
end

function observation(ledger::InventoryStockLedger, observation_id::AbstractString)
    id = String(observation_id)
    haskey(ledger.observation_index, id) ||
        throw(KeyError(id))
    return ledger.observations[ledger.observation_index[id]]
end

identity_residuals(ledger::InventoryStockLedger) = copy(ledger.residuals)
stage_additivity_pass(ledger::InventoryStockLedger) =
    all(item -> item.passed, ledger.residuals)

end # module
