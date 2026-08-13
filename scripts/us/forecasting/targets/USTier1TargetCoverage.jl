module USTier1TargetCoverage

using Dates
using SHA
using TOML

export DEFAULT_INVENTORY_PATH,
    EXPECTED_TARGET_IDS,
    REQUIRED_TRUTH_LAYER_IDS,
    TargetCoverageError,
    computed_content_sha256,
    inventory_sha256,
    load_inventory,
    promotion_readiness,
    require_promotion_ready,
    stamp_content_sha256!,
    validate_inventory

const DEFAULT_INVENTORY_PATH = joinpath(@__DIR__, "tier1_targets.toml")
const SCHEMA_VERSION = "beforeit-us-tier1-target-truth-coverage.v1"
const CANONICALIZATION =
    "sorted_typed_v1_excluding_artifact_content_sha256"
const CONTRACT_ID = "beforeit-us-tier1-target-coverage.v1-draft"
const PROTOCOL_ID = "beforeit-us-forecast-evaluation.v1-draft"
const PROTOCOL_SHA256 =
    "88519e5b04936f528396cf5243ff270844d0d38651fd84fc3b1c76fef997b584"
const WEIGHT_TOLERANCE = 1.0e-12
const MINIMUM_PROMOTION_OBSERVATIONS = 40
const EVIDENCE_VERIFIER_STATUS = "NOT_IMPLEMENTED_FAIL_CLOSED"

const EXPECTED_TARGET_IDS = (
    "real_gdp",
    "pce_price_index",
    "core_pce_price_index",
    "gdp_deflator",
    "unemployment_rate",
    "payroll_employment",
    "effective_federal_funds_rate",
    "nominal_gdp",
)

const REQUIRED_TRUTH_LAYER_IDS = (
    "first_release",
    "near_mature",
    "mature",
)

const EXPECTED_TARGETS = Dict(
    "real_gdp" => (
        target_version = "bea-real-gdp.v1-draft",
        source_concept = "BEA_NIPA_real_gdp",
        provider = "U.S. Bureau of Economic Analysis",
        source_table = "NIPA Table 1.1.6",
        source_series = "Gross domestic product",
        source_dataset_id = "NIPA",
        source_table_id = "T10106",
        source_line_number = "1",
        source_series_code = "A191RX",
        source_unit = "millions_chained_2017_dollars_saar",
        source_seasonal_adjustment = "seasonally_adjusted_at_annual_rates",
        frequency = "quarterly",
        source_release_granularity = "quarterly_nipa_estimate",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_growth",
        secondary_transformation = "four_quarter_log_growth",
        transformation_version = "us-real-gdp-growth.v1-draft",
        operator_version = "abm-to-bea-real-gdp.v1-draft",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
    ),
    "pce_price_index" => (
        target_version = "bea-pce-price-index.v1-draft",
        source_concept = "BEA_NIPA_pce_price_index",
        provider = "U.S. Bureau of Economic Analysis",
        source_table = "NIPA Table 2.3.4",
        source_series = "Personal consumption expenditures",
        source_dataset_id = "NIPA",
        source_table_id = "T20304",
        source_line_number = "1",
        source_series_code = "DPCERG",
        source_unit = "index_2017_equals_100",
        source_seasonal_adjustment = "seasonally_adjusted",
        frequency = "quarterly",
        source_release_granularity = "quarterly_nipa_estimate",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        transformation_version = "us-pce-price-inflation.v1-draft",
        operator_version = "abm-to-bea-pce-price-index.v1-draft",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
    ),
    "core_pce_price_index" => (
        target_version = "bea-core-pce-price-index.v1-draft",
        source_concept = "BEA_NIPA_core_pce_price_index",
        provider = "U.S. Bureau of Economic Analysis",
        source_table = "NIPA Table 2.3.4",
        source_series =
            "Personal consumption expenditures excluding food and energy",
        source_dataset_id = "NIPA",
        source_table_id = "T20304",
        source_line_number = "25",
        source_series_code = "DPCCRG",
        source_unit = "index_2017_equals_100",
        source_seasonal_adjustment = "seasonally_adjusted",
        frequency = "quarterly",
        source_release_granularity = "quarterly_nipa_estimate",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        transformation_version = "us-core-pce-price-inflation.v1-draft",
        operator_version = "abm-to-bea-core-pce-price-index.v1-draft",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
    ),
    "gdp_deflator" => (
        target_version = "bea-gdp-deflator.v1-draft",
        source_concept = "BEA_NIPA_gdp_deflator",
        provider = "U.S. Bureau of Economic Analysis",
        source_table = "NIPA Table 1.1.9",
        source_series = "Gross domestic product",
        source_dataset_id = "NIPA",
        source_table_id = "T10109",
        source_line_number = "1",
        source_series_code = "A191RD",
        source_unit = "index_2017_equals_100",
        source_seasonal_adjustment = "seasonally_adjusted",
        frequency = "quarterly",
        source_release_granularity = "quarterly_nipa_estimate",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        transformation_version = "us-gdp-deflator-inflation.v1-draft",
        operator_version = "abm-to-bea-gdp-deflator.v1-draft",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
    ),
    "unemployment_rate" => (
        target_version = "bls-unemployment-rate.v1-draft",
        source_concept = "BLS_CPS_unemployment_rate",
        provider = "U.S. Bureau of Labor Statistics",
        source_table = "Current Population Survey",
        source_series = "LNS14000000",
        source_dataset_id = "BLS_CPS_PUBLIC_DATA_API",
        source_table_id = "LNS",
        source_line_number = "not_applicable",
        source_series_code = "LNS14000000",
        source_unit = "percent_of_civilian_labor_force",
        source_seasonal_adjustment = "seasonally_adjusted",
        frequency = "monthly",
        source_release_granularity = "monthly_employment_situation_release",
        aggregation = "quarterly_average_monthly",
        primary_transformation = "percent_level",
        secondary_transformation = "quarterly_change",
        transformation_version = "us-cps-unemployment-quarterly.v1-draft",
        operator_version = "abm-to-bls-unemployment-rate.v1-draft",
        output_unit = "percentage_points",
        truth_policy = "monthly_or_daily_derived",
    ),
    "payroll_employment" => (
        target_version = "bls-payroll-employment.v1-draft",
        source_concept = "BLS_CES_total_nonfarm_payrolls",
        provider = "U.S. Bureau of Labor Statistics",
        source_table = "Current Employment Statistics",
        source_series = "CES0000000001",
        source_dataset_id = "BLS_CES_PUBLIC_DATA_API",
        source_table_id = "CES",
        source_line_number = "not_applicable",
        source_series_code = "CES0000000001",
        source_unit = "thousands_of_payroll_jobs",
        source_seasonal_adjustment = "seasonally_adjusted",
        frequency = "monthly",
        source_release_granularity = "monthly_employment_situation_release",
        aggregation = "quarterly_average_monthly",
        primary_transformation = "quarterly_log_growth",
        secondary_transformation = "revision_to_level",
        transformation_version = "us-ces-payroll-quarterly.v1-draft",
        operator_version = "abm-to-bls-payroll-employment.v1-draft",
        output_unit = "log_points",
        truth_policy = "monthly_or_daily_derived",
    ),
    "effective_federal_funds_rate" => (
        target_version = "frb-effective-federal-funds-rate.v1-draft",
        source_concept = "FRB_effective_federal_funds_rate",
        provider = "Federal Reserve Bank of New York",
        source_table = "Reference Rates",
        source_series = "EFFR",
        source_dataset_id = "FRBNY_REFERENCE_RATES",
        source_table_id = "EFFR",
        source_line_number = "not_applicable",
        source_series_code = "EFFR",
        source_unit = "percent_per_annum",
        source_seasonal_adjustment = "not_seasonally_adjusted",
        frequency = "daily_business_day",
        source_release_granularity = "daily_reference_rate_publication",
        aggregation = "quarterly_average_daily",
        primary_transformation = "percentage_point_level",
        secondary_transformation = "quarterly_change",
        transformation_version = "us-effr-quarterly-average.v1-draft",
        operator_version =
            "abm-to-frb-effective-federal-funds-rate.v1-draft",
        output_unit = "percentage_points",
        truth_policy = "monthly_or_daily_derived",
    ),
    "nominal_gdp" => (
        target_version = "bea-nominal-gdp.v1-draft",
        source_concept = "BEA_NIPA_nominal_gdp",
        provider = "U.S. Bureau of Economic Analysis",
        source_table = "NIPA Table 1.1.5",
        source_series = "Gross domestic product",
        source_dataset_id = "NIPA",
        source_table_id = "T10105",
        source_line_number = "1",
        source_series_code = "A191RC",
        source_unit = "millions_current_dollars_saar",
        source_seasonal_adjustment = "seasonally_adjusted_at_annual_rates",
        frequency = "quarterly",
        source_release_granularity = "quarterly_nipa_estimate",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_growth",
        secondary_transformation = "four_quarter_log_growth",
        transformation_version = "us-nominal-gdp-growth.v1-draft",
        operator_version = "abm-to-bea-nominal-gdp.v1-draft",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
    ),
)

const TARGET_KEYS = (
    "target_id",
    "target_version",
    "weight",
    "source_concept",
    "provider",
    "source_table",
    "source_series",
    "source_dataset_id",
    "source_table_id",
    "source_line_number",
    "source_series_code",
    "source_unit",
    "source_seasonal_adjustment",
    "frequency",
    "source_release_granularity",
    "aggregation",
    "primary_transformation",
    "secondary_transformation",
    "transformation_version",
    "operator_version",
    "output_unit",
    "truth_policy",
    "operator_status",
    "installed_status",
    "installed_evidence",
    "vintage_status",
    "release_timestamp_status",
    "historical_vintage_count",
    "retrieval_vintages",
    "acquisition_route",
    "truth_layers",
)

struct TargetCoverageError <: Exception
    message::String
end

Base.showerror(io::IO, error::TargetCoverageError) =
    print(io, error.message)

fail(location, message) =
    throw(TargetCoverageError("$location: $message"))

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    expected_set = Set(String.(expected))
    missing = sort!(collect(setdiff(expected_set, actual)))
    unknown = sort!(collect(setdiff(actual, expected_set)))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown keys: $(join(unknown, ", "))")
    return table
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
    return text
end

function expect_string_array(value, location; allow_empty = false)
    value isa AbstractVector || fail(location, "must be an array")
    !allow_empty && isempty(value) &&
        fail(location, "must not be empty")
    result = [
        expect_string(entry, "$location[$index]")
            for (index, entry) in enumerate(value)
    ]
    length(result) == length(Set(result)) ||
        fail(location, "must not contain duplicate values")
    return result
end

function expect_integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    number = Int(value)
    number >= minimum || fail(location, "must be at least $minimum")
    return number
end

function expect_float(value, location)
    value isa AbstractFloat || fail(location, "must be a floating-point number")
    number = Float64(value)
    isfinite(number) || fail(location, "must be finite")
    return number
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function expect_one_of(value, allowed, location)
    text = expect_string(value, location)
    text in allowed ||
        fail(location, "unsupported value '$text'")
    return text
end

function expect_exact(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

function expect_date(value, location)
    text = expect_string(value, location)
    occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", text) ||
        fail(location, "must use YYYY-MM-DD")
    date = try
        Date(text)
    catch
        fail(location, "must be a valid calendar date")
    end
    string(date) == text || fail(location, "must be a canonical calendar date")
    return text
end

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        entries =
            sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            _canonical_write(io, String(key))
            _canonical_write(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "A", length(value), "[")
        for entry in value
            _canonical_write(io, entry)
        end
        print(io, "]")
    elseif value isa AbstractString
        text = String(value)
        print(io, "S", ncodeunits(text), ":", text)
    elseif value isa Bool
        print(io, value ? "B1" : "B0")
    elseif value isa Integer
        print(io, "I", value, ";")
    elseif value isa AbstractFloat
        number = Float64(value)
        isfinite(number) ||
            fail("canonicalization", "cannot encode a nonfinite number")
        print(io, "F", bitstring(number), ";")
    else
        fail(
            "canonicalization",
            "unsupported value of type $(typeof(value))",
        )
    end
    return io
end

function computed_content_sha256(value)
    inventory = deepcopy(expect_table(value, "inventory"))
    artifact =
        expect_table(get(inventory, "artifact", nothing), "inventory.artifact")
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, inventory)
    return bytes2hex(sha256(take!(io)))
end

function stamp_content_sha256!(value)
    inventory = expect_table(value, "inventory")
    artifact =
        expect_table(get(inventory, "artifact", nothing), "inventory.artifact")
    artifact["content_sha256"] = computed_content_sha256(inventory)
    return inventory
end

function load_inventory(path::AbstractString = DEFAULT_INVENTORY_PATH)
    isfile(path) ||
        fail("inventory", "file does not exist: $(abspath(path))")
    return try
        TOML.parsefile(path)
    catch error
        fail(
            "inventory",
            "could not parse TOML: $(sprint(showerror, error))",
        )
    end
end

function validate_artifact(inventory)
    artifact = expect_exact_keys(
        inventory["artifact"],
        ("schema_version", "canonicalization", "content_sha256"),
        "inventory.artifact",
    )
    expect_exact(
        artifact["schema_version"],
        SCHEMA_VERSION,
        "inventory.artifact.schema_version",
    )
    expect_exact(
        artifact["canonicalization"],
        CANONICALIZATION,
        "inventory.artifact.canonicalization",
    )
    declared =
        expect_hash(artifact["content_sha256"], "inventory.artifact.content_sha256")
    computed = computed_content_sha256(inventory)
    declared == computed ||
        fail(
        "inventory.artifact.content_sha256",
        "declared $declared does not match computed $computed",
    )
    return declared
end

function validate_contract(contract)
    contract = expect_exact_keys(
        contract,
        (
            "contract_id",
            "protocol_id",
            "protocol_sha256",
            "audit_as_of_date",
            "audit_scope",
            "required_target_count",
            "required_truth_layers",
            "required_weight_sum",
            "minimum_promotion_observations_per_truth_layer",
            "minimum_historical_vintages_per_target",
            "evidence_verifier_status",
            "truth_matrix_count",
            "approved_operator_bridge_count",
            "promotion_rule",
        ),
        "inventory.contract",
    )
    expect_exact(
        contract["contract_id"],
        CONTRACT_ID,
        "inventory.contract.contract_id",
    )
    expect_exact(
        contract["protocol_id"],
        PROTOCOL_ID,
        "inventory.contract.protocol_id",
    )
    expect_exact(
        contract["protocol_sha256"],
        PROTOCOL_SHA256,
        "inventory.contract.protocol_sha256",
    )
    expect_date(
        contract["audit_as_of_date"],
        "inventory.contract.audit_as_of_date",
    )
    expect_string(contract["audit_scope"], "inventory.contract.audit_scope")
    expect_exact(
        expect_integer(
            contract["required_target_count"],
            "inventory.contract.required_target_count";
            minimum = 1,
        ),
        length(EXPECTED_TARGET_IDS),
        "inventory.contract.required_target_count",
    )
    truth_layers = expect_string_array(
        contract["required_truth_layers"],
        "inventory.contract.required_truth_layers",
    )
    truth_layers == collect(REQUIRED_TRUTH_LAYER_IDS) ||
        fail(
        "inventory.contract.required_truth_layers",
        "must equal $(join(REQUIRED_TRUTH_LAYER_IDS, ", ")) in order",
    )
    expect_exact(
        expect_float(
            contract["required_weight_sum"],
            "inventory.contract.required_weight_sum",
        ),
        1.0,
        "inventory.contract.required_weight_sum",
    )
    expect_exact(
        expect_integer(
            contract["minimum_promotion_observations_per_truth_layer"],
            "inventory.contract.minimum_promotion_observations_per_truth_layer";
            minimum = 1,
        ),
        MINIMUM_PROMOTION_OBSERVATIONS,
        "inventory.contract.minimum_promotion_observations_per_truth_layer",
    )
    expect_exact(
        expect_integer(
            contract["minimum_historical_vintages_per_target"],
            "inventory.contract.minimum_historical_vintages_per_target";
            minimum = 1,
        ),
        MINIMUM_PROMOTION_OBSERVATIONS,
        "inventory.contract.minimum_historical_vintages_per_target",
    )
    expect_exact(
        contract["evidence_verifier_status"],
        EVIDENCE_VERIFIER_STATUS,
        "inventory.contract.evidence_verifier_status",
    )
    expect_integer(
        contract["truth_matrix_count"],
        "inventory.contract.truth_matrix_count";
        minimum = 0,
    )
    expect_integer(
        contract["approved_operator_bridge_count"],
        "inventory.contract.approved_operator_bridge_count";
        minimum = 0,
    )
    expect_exact(
        contract["promotion_rule"],
        "all_eight_exact_historical_targets_all_three_truth_layers_all_operators_approved_and_all_artifacts_verified",
        "inventory.contract.promotion_rule",
    )
    return contract
end

function validate_truth_layer(layer, target_id, truth_policy, index)
    location = "inventory.targets[$target_id].truth_layers[$index]"
    layer = expect_exact_keys(
        layer,
        (
            "layer_id",
            "required",
            "requirement",
            "status",
            "observation_count",
            "artifact_sha256",
        ),
        location,
    )
    layer_id = expect_one_of(
        layer["layer_id"],
        Set(REQUIRED_TRUTH_LAYER_IDS),
        "$location.layer_id",
    )
    expect_bool(layer["required"], "$location.required") ||
        fail("$location.required", "every Tier-1 truth layer is required")
    requirement = expect_string(layer["requirement"], "$location.requirement")
    expected_requirement =
        layer_id == "first_release" ?
        "earliest_official_release_reporting_complete_target_reference_period" :
        layer_id == "near_mature" ?
        truth_policy == "nipa_quarterly" ?
        "third_scheduled_quarterly_estimate" :
        "latest_official_vintage_at_reference_period_end_plus_90_calendar_days" :
        "latest_official_vintage_at_fixed_60_month_lag"
    requirement == expected_requirement ||
        fail(
        "$location.requirement",
        "expected '$expected_requirement', got '$requirement'",
    )
    status = expect_one_of(
        layer["status"],
        Set(["available", "missing"]),
        "$location.status",
    )
    count = expect_integer(
        layer["observation_count"],
        "$location.observation_count";
        minimum = 0,
    )
    artifact_sha256 =
        expect_string(layer["artifact_sha256"], "$location.artifact_sha256")
    if status == "available"
        count > 0 ||
            fail("$location.observation_count", "available truth must be nonempty")
        expect_hash(artifact_sha256, "$location.artifact_sha256")
    else
        count == 0 ||
            fail("$location.observation_count", "missing truth must have count 0")
        artifact_sha256 == "unavailable" ||
            fail(
            "$location.artifact_sha256",
            "missing truth must use 'unavailable'",
        )
    end
    return layer_id
end

function validate_vintage_state(target, target_id, location)
    installed_status = expect_one_of(
        target["installed_status"],
        Set(["exact", "approximate", "absent"]),
        "$location.installed_status",
    )
    vintage_status = expect_one_of(
        target["vintage_status"],
        Set(["historical_bitemporal", "current_vintage_only", "absent"]),
        "$location.vintage_status",
    )
    timestamp_status = expect_one_of(
        target["release_timestamp_status"],
        Set(
            [
                "exact_historical_release_timestamps",
                "retrieval_timestamp_only",
                "absent",
            ],
        ),
        "$location.release_timestamp_status",
    )
    historical_count = expect_integer(
        target["historical_vintage_count"],
        "$location.historical_vintage_count";
        minimum = 0,
    )
    retrieval_vintages = expect_string_array(
        target["retrieval_vintages"],
        "$location.retrieval_vintages";
        allow_empty = true,
    )
    for (index, vintage) in enumerate(retrieval_vintages)
        expect_date(
            vintage,
            "$location.retrieval_vintages[$index]",
        )
    end
    issorted(retrieval_vintages) ||
        fail("$location.retrieval_vintages", "must be sorted")

    if vintage_status == "historical_bitemporal"
        installed_status == "exact" ||
            fail(
            "$location.installed_status",
            "historical coverage requires the exact target",
        )
        timestamp_status == "exact_historical_release_timestamps" ||
            fail(
            "$location.release_timestamp_status",
            "historical coverage requires exact release timestamps",
        )
        historical_count > 0 ||
            fail(
            "$location.historical_vintage_count",
            "historical coverage must contain at least one vintage",
        )
        isempty(retrieval_vintages) ||
            fail(
            "$location.retrieval_vintages",
            "retrieval snapshot dates cannot evidence historical releases",
        )
    elseif vintage_status == "current_vintage_only"
        installed_status != "absent" ||
            fail(
            "$location.installed_status",
            "a current-vintage target cannot be absent",
        )
        timestamp_status == "retrieval_timestamp_only" ||
            fail(
            "$location.release_timestamp_status",
            "current-vintage coverage must be labeled retrieval-only",
        )
        historical_count == 0 ||
            fail(
            "$location.historical_vintage_count",
            "retrieval snapshots are not historical release vintages",
        )
        isempty(retrieval_vintages) &&
            fail(
            "$location.retrieval_vintages",
            "current-vintage coverage needs a retrieval date",
        )
    else
        installed_status == "absent" ||
            fail(
            "$location.installed_status",
            "absent vintage coverage requires an absent exact target",
        )
        timestamp_status == "absent" ||
            fail(
            "$location.release_timestamp_status",
            "absent coverage must use an absent timestamp status",
        )
        historical_count == 0 ||
            fail(
            "$location.historical_vintage_count",
            "absent coverage must have count 0",
        )
        isempty(retrieval_vintages) ||
            fail(
            "$location.retrieval_vintages",
            "absent exact coverage cannot list retrieval vintages",
        )
    end

    if target_id == "effective_federal_funds_rate"
        target["provider"] == "Federal Reserve Bank of New York" ||
            fail(
            "$location.provider",
            "daily EFFR cannot be replaced by a FRED FEDFUNDS series",
        )
        target["source_series"] == "EFFR" ||
            fail(
            "$location.source_series",
            "daily EFFR requires the EFFR source series; FEDFUNDS is monthly",
        )
        target["frequency"] == "daily_business_day" ||
            fail(
            "$location.frequency",
            "daily EFFR cannot use monthly FEDFUNDS",
        )
    end
    return nothing
end

function validate_target(target, index)
    location = "inventory.targets[$index]"
    target = expect_exact_keys(target, TARGET_KEYS, location)
    target_id = expect_string(target["target_id"], "$location.target_id")
    haskey(EXPECTED_TARGETS, target_id) ||
        fail("$location.target_id", "unexpected Tier-1 target '$target_id'")
    specification = EXPECTED_TARGETS[target_id]

    for field in keys(specification)
        field_name = String(field)
        actual = expect_string(target[field_name], "$location.$field_name")
        expected = getfield(specification, field)
        actual == expected ||
            fail(
            "$location.$field_name",
            "expected $(repr(expected)), got $(repr(actual))",
        )
    end

    weight = expect_float(target["weight"], "$location.weight")
    isapprox(weight, 0.125; atol = WEIGHT_TOLERANCE, rtol = 0.0) ||
        fail("$location.weight", "each of the eight target weights must be 0.125")
    expect_one_of(
        target["operator_status"],
        Set(["approved", "pending_validation", "rejected"]),
        "$location.operator_status",
    )
    expect_string_array(
        target["installed_evidence"],
        "$location.installed_evidence",
    )
    acquisition_route =
        expect_string(target["acquisition_route"], "$location.acquisition_route")
    occursin("exact_release", acquisition_route) ||
        fail(
        "$location.acquisition_route",
        "must name an exact-release archival route",
    )
    validate_vintage_state(target, target_id, location)

    truth_layers = target["truth_layers"]
    truth_layers isa AbstractVector ||
        fail("$location.truth_layers", "must be an array of tables")
    layer_ids = String[]
    for (truth_index, layer) in enumerate(truth_layers)
        push!(
            layer_ids,
            validate_truth_layer(
                layer,
                target_id,
                specification.truth_policy,
                truth_index,
            ),
        )
    end
    length(layer_ids) == length(Set(layer_ids)) ||
        fail("$location.truth_layers", "contains duplicate truth layers")
    Set(layer_ids) == Set(REQUIRED_TRUTH_LAYER_IDS) ||
        fail(
        "$location.truth_layers",
        "must contain first_release, near_mature, and mature exactly once",
    )
    return target_id
end

function validate_inventory(inventory)
    inventory = expect_exact_keys(
        inventory,
        ("artifact", "contract", "targets"),
        "inventory",
    )
    validate_contract(inventory["contract"])
    targets = inventory["targets"]
    targets isa AbstractVector ||
        fail("inventory.targets", "must be an array of tables")
    target_ids = String[]
    total_weight = 0.0
    truth_matrix_count = 0
    approved_operator_count = 0
    for (index, target) in enumerate(targets)
        target_id = validate_target(target, index)
        push!(target_ids, target_id)
        total_weight += Float64(target["weight"])
        truth_matrix_count += count(
            layer -> layer["status"] == "available",
            target["truth_layers"],
        )
        approved_operator_count += target["operator_status"] == "approved"
    end
    length(target_ids) == length(Set(target_ids)) ||
        fail("inventory.targets", "contains duplicate target IDs")
    Set(target_ids) == Set(EXPECTED_TARGET_IDS) ||
        fail(
        "inventory.targets",
        "must contain exactly the eight protocol Tier-1 targets",
    )
    length(target_ids) == length(EXPECTED_TARGET_IDS) ||
        fail("inventory.targets", "must contain exactly eight entries")
    isapprox(total_weight, 1.0; atol = WEIGHT_TOLERANCE, rtol = 0.0) ||
        fail("inventory.targets.weight", "target weights must sum to 1.0")
    expect_exact(
        inventory["contract"]["truth_matrix_count"],
        truth_matrix_count,
        "inventory.contract.truth_matrix_count",
    )
    expect_exact(
        inventory["contract"]["approved_operator_bridge_count"],
        approved_operator_count,
        "inventory.contract.approved_operator_bridge_count",
    )
    digest = validate_artifact(inventory)
    return (
        inventory = inventory,
        sha256 = digest,
        target_count = length(target_ids),
        truth_matrix_count = truth_matrix_count,
        approved_operator_bridge_count = approved_operator_count,
        weight_sum = total_weight,
    )
end

function inventory_sha256(inventory = load_inventory())
    return validate_inventory(inventory).sha256
end

function promotion_readiness(inventory = load_inventory())
    validation = validate_inventory(inventory)
    blockers = String[]
    exact_count = 0
    approximate_count = 0
    absent_count = 0
    historical_count = 0
    complete_truth_target_count = 0
    approved_operator_count = 0

    target_lookup =
        Dict(target["target_id"] => target for target in inventory["targets"])
    for target_id in EXPECTED_TARGET_IDS
        target = target_lookup[target_id]
        if target["installed_status"] == "exact"
            exact_count += 1
        else
            if target["installed_status"] == "approximate"
                approximate_count += 1
            else
                absent_count += 1
            end
            push!(
                blockers,
                "$target_id exact target is $(target["installed_status"])",
            )
        end
        if target["vintage_status"] == "historical_bitemporal"
            if target["historical_vintage_count"] >=
                    MINIMUM_PROMOTION_OBSERVATIONS
                historical_count += 1
            else
                push!(
                    blockers,
                    "$target_id historical vintage count is $(target["historical_vintage_count"])/$(MINIMUM_PROMOTION_OBSERVATIONS)",
                )
            end
        else
            push!(
                blockers,
                "$target_id vintage coverage is $(target["vintage_status"])",
            )
        end
        if target["operator_status"] == "approved"
            approved_operator_count += 1
        else
            push!(
                blockers,
                "$target_id operator is $(target["operator_status"])",
            )
        end
        incomplete_layers = [
            layer["status"] != "available" ?
                "$(layer["layer_id"]) (missing)" :
                "$(layer["layer_id"]) ($(layer["observation_count"])/$(MINIMUM_PROMOTION_OBSERVATIONS))"
                for layer in target["truth_layers"] if
                layer["status"] != "available" ||
                layer["observation_count"] <
                MINIMUM_PROMOTION_OBSERVATIONS
        ]
        if isempty(incomplete_layers)
            complete_truth_target_count += 1
        else
            push!(
                blockers,
                "$target_id truth incomplete: $(join(incomplete_layers, ", "))",
            )
        end
    end

    schema_ready = isempty(blockers)
    evidence_verified =
        inventory["contract"]["evidence_verifier_status"] ==
        "IMPLEMENTED_AND_VERIFIED"
    evidence_verified ||
        push!(
        blockers,
        "resolved truth/operator artifact verification is not implemented",
    )
    ready = isempty(blockers)
    return (
        ready = ready,
        schema_ready = schema_ready,
        status = ready ?
            "READY" :
            schema_ready ?
            "EVIDENCE_VERIFICATION_REQUIRED" :
            "NOT_READY",
        evidence_verifier_status =
            inventory["contract"]["evidence_verifier_status"],
        inventory_sha256 = validation.sha256,
        target_count = validation.target_count,
        exact_target_count = exact_count,
        approximate_target_count = approximate_count,
        absent_target_count = absent_count,
        installed_or_approximate_target_count =
            exact_count + approximate_count,
        historical_vintage_target_count = historical_count,
        complete_truth_target_count = complete_truth_target_count,
        truth_matrix_count = validation.truth_matrix_count,
        approved_operator_bridge_count = approved_operator_count,
        weight_sum = validation.weight_sum,
        blockers = blockers,
    )
end

function require_promotion_ready(inventory = load_inventory())
    result = promotion_readiness(inventory)
    result.ready ||
        fail(
        "promotion",
        "Tier-1 coverage is not ready: $(join(result.blockers, "; "))",
    )
    return result
end

end
