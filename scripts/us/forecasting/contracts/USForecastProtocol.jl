module USForecastProtocol

using SHA
using TOML

export DEFAULT_PROTOCOL_PATH,
    ProtocolValidationError,
    canonicalize_protocol,
    load_protocol,
    protocol_artifact,
    protocol_sha256,
    validate_protocol

const DEFAULT_PROTOCOL_PATH =
    normpath(joinpath(@__DIR__, "..", "protocol.toml"))
const EXPECTED_SCHEMA = "beforeit-us-forecast-protocol.v1"
const EXPECTED_HORIZONS = [1, 2, 4, 8, 12]
const EXPECTED_CORE_HORIZONS = [1, 2, 4]
const EXPECTED_LONG_HORIZONS = [8, 12]
const VERSION_PATTERN =
    r"^[a-z0-9][a-z0-9._-]*\.v[1-9][0-9]*(?:-draft)?$"
const IDENTIFIER_PATTERN = r"^[a-z0-9][a-z0-9_]*$"

struct ProtocolValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::ProtocolValidationError) =
    print(io, error.message)

fail(path::AbstractString, message::AbstractString) =
    throw(ProtocolValidationError("$path: $message"))

function expect_table(value, path)
    value isa AbstractDict ||
        fail(path, "expected a table")
    for key in keys(value)
        key isa AbstractString ||
            fail(path, "table keys must be strings")
    end
    return value
end

function check_keys(table, path, expected_keys)
    expect_table(table, path)
    actual = Set(String(key) for key in keys(table))
    expected = Set(String(key) for key in expected_keys)
    missing = sort!(collect(setdiff(expected, actual)))
    unknown = sort!(collect(setdiff(actual, expected)))
    isempty(missing) ||
        fail(path, "missing required key(s): $(join(missing, ", "))")
    isempty(unknown) ||
        fail(path, "unknown key(s): $(join(unknown, ", "))")
    return table
end

function expect_string(value, path)
    value isa AbstractString ||
        fail(path, "expected a string")
    text = String(value)
    isempty(text) &&
        fail(path, "must not be empty")
    strip(text) == text ||
        fail(path, "must not contain leading or trailing whitespace")
    return text
end

function expect_exact_string(table, key, expected, path)
    value = expect_string(table[key], "$path.$key")
    value == expected ||
        fail("$path.$key", "expected '$expected', got '$value'")
    return value
end

function expect_version(value, path)
    version = expect_string(value, path)
    occursin(VERSION_PATTERN, version) ||
        fail(path, "expected a versioned identifier ending in .vN or .vN-draft")
    return version
end

function expect_identifier(value, path)
    identifier = expect_string(value, path)
    occursin(IDENTIFIER_PATTERN, identifier) ||
        fail(path, "expected a lowercase snake_case identifier")
    return identifier
end

function expect_bool(value, path)
    value isa Bool ||
        fail(path, "expected a Boolean")
    return value
end

function expect_int(value, path)
    value isa Integer && !(value isa Bool) ||
        fail(path, "expected an integer")
    return Int(value)
end

function expect_float(value, path)
    value isa AbstractFloat ||
        fail(path, "expected a floating-point number")
    number = Float64(value)
    isfinite(number) ||
        fail(path, "must be finite")
    return number
end

function expect_string_vector(value, path; allow_empty = false)
    value isa AbstractVector ||
        fail(path, "expected an array of strings")
    strings = String[]
    for (index, entry) in enumerate(value)
        push!(strings, expect_string(entry, "$path[$index]"))
    end
    allow_empty || !isempty(strings) ||
        fail(path, "must not be empty")
    length(Set(strings)) == length(strings) ||
        fail(path, "must not contain duplicate values")
    return strings
end

function expect_int_vector(value, path; allow_empty = false)
    value isa AbstractVector ||
        fail(path, "expected an array of integers")
    integers = Int[]
    for (index, entry) in enumerate(value)
        push!(integers, expect_int(entry, "$path[$index]"))
    end
    allow_empty || !isempty(integers) ||
        fail(path, "must not be empty")
    length(Set(integers)) == length(integers) ||
        fail(path, "must not contain duplicate values")
    return integers
end

function expect_float_vector(value, path; allow_empty = false)
    value isa AbstractVector ||
        fail(path, "expected an array of floating-point numbers")
    numbers = Float64[]
    for (index, entry) in enumerate(value)
        push!(numbers, expect_float(entry, "$path[$index]"))
    end
    allow_empty || !isempty(numbers) ||
        fail(path, "must not be empty")
    return numbers
end

function expect_exact(value, expected, path)
    value == expected ||
        fail(path, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function validate_governance(governance)
    path = "protocol.governance"
    check_keys(
        governance,
        path,
        (
            "model_owner_role",
            "model_owner_approval",
            "independent_validator_role",
            "independent_validator_approval",
            "frozen",
        ),
    )
    expect_exact_string(
        governance,
        "model_owner_role",
        "research_lead",
        path,
    )
    expect_exact_string(
        governance,
        "model_owner_approval",
        "pending",
        path,
    )
    expect_exact_string(
        governance,
        "independent_validator_role",
        "independent_validation",
        path,
    )
    expect_exact_string(
        governance,
        "independent_validator_approval",
        "pending_validation",
        path,
    )
    expect_bool(governance["frozen"], "$path.frozen") === false ||
        fail("$path.frozen", "a draft protocol cannot be frozen")
    return governance
end

function validate_issue_rules(issue_rules)
    path = "protocol.issue_rules"
    check_keys(
        issue_rules,
        path,
        (
            "release_eligibility",
            "same_timestamp_release",
            "missing_intraday_release_timestamp",
            "timestamp",
            "quarterly",
            "nowcast",
        ),
    )
    expect_exact_string(
        issue_rules,
        "release_eligibility",
        "release_timestamp_utc <= origin_timestamp_utc",
        path,
    )
    expect_exact_string(
        issue_rules,
        "same_timestamp_release",
        "eligible",
        path,
    )
    expect_exact_string(
        issue_rules,
        "missing_intraday_release_timestamp",
        "ineligible",
        path,
    )

    timestamp = expect_table(issue_rules["timestamp"], "$path.timestamp")
    check_keys(
        timestamp,
        "$path.timestamp",
        (
            "local_timezone",
            "daylight_saving_rule",
            "canonical_timezone",
            "canonical_format",
            "comparison_precision",
        ),
    )
    expect_exact_string(
        timestamp,
        "local_timezone",
        "America/New_York",
        "$path.timestamp",
    )
    expect_exact_string(
        timestamp,
        "daylight_saving_rule",
        "IANA_tzdb_at_origin_date",
        "$path.timestamp",
    )
    expect_exact_string(
        timestamp,
        "canonical_timezone",
        "UTC",
        "$path.timestamp",
    )
    expect_exact_string(
        timestamp,
        "canonical_format",
        "RFC3339_seconds_Z",
        "$path.timestamp",
    )
    expect_exact_string(
        timestamp,
        "comparison_precision",
        "seconds",
        "$path.timestamp",
    )

    quarterly = expect_table(issue_rules["quarterly"], "$path.quarterly")
    check_keys(
        quarterly,
        "$path.quarterly",
        (
            "version",
            "trigger",
            "business_day_calendar",
            "local_issue_time",
            "publication_calendar",
            "latest_quarter_treatment",
        ),
    )
    expect_version(quarterly["version"], "$path.quarterly.version")
    expect_exact_string(
        quarterly,
        "trigger",
        "first_business_day_after_bea_advance_gdp_release",
        "$path.quarterly",
    )
    expect_exact_string(
        quarterly,
        "business_day_calendar",
        "us_federal_holidays_weekends.v1",
        "$path.quarterly",
    )
    expect_exact_string(
        quarterly,
        "local_issue_time",
        "10:00:00",
        "$path.quarterly",
    )
    expect_exact_string(
        quarterly,
        "publication_calendar",
        "bea_gdp_release_calendar.v1",
        "$path.quarterly",
    )
    expect_exact_string(
        quarterly,
        "latest_quarter_treatment",
        "advance_estimate_observed_provisional",
        "$path.quarterly",
    )

    nowcast = expect_table(issue_rules["nowcast"], "$path.nowcast")
    check_keys(
        nowcast,
        "$path.nowcast",
        (
            "version",
            "cutoffs",
            "business_day_calendar",
            "local_issue_time",
            "final_cutoff_relation",
        ),
    )
    expect_version(nowcast["version"], "$path.nowcast.version")
    expect_exact(
        expect_string_vector(nowcast["cutoffs"], "$path.nowcast.cutoffs"),
        [
            "tenth_business_day_after_month_end",
            "final_business_day_before_bea_advance_gdp_release",
        ],
        "$path.nowcast.cutoffs",
    )
    expect_exact_string(
        nowcast,
        "business_day_calendar",
        "us_federal_holidays_weekends.v1",
        "$path.nowcast",
    )
    expect_exact_string(
        nowcast,
        "local_issue_time",
        "10:00:00",
        "$path.nowcast",
    )
    expect_exact_string(
        nowcast,
        "final_cutoff_relation",
        "strictly_before_bea_advance_release_timestamp",
        "$path.nowcast",
    )
    return issue_rules
end

const EXPECTED_PRODUCTS = Dict(
    "quarterly_unconditional" => (
        kind = "unconditional_forecast",
        information_set = "exact_as_of_origin_releases_only",
        origin_rule = "quarterly-after-advance.v1-draft",
        horizons = EXPECTED_HORIZONS,
        conditioning = "none",
        benchmark_tracks = ["common_information", "published_forecast"],
        ranking_pool = "quarterly_unconditional_only",
        promotion_eligible = true,
        realized_future_data_allowed = false,
        show_unconditional_baseline = false,
    ),
    "ragged_edge_nowcast" => (
        kind = "ragged_edge_nowcast",
        information_set = "exact_as_of_monthly_weekly_cutoff",
        origin_rule = "monthly-and-pre-advance-nowcast.v1-draft",
        horizons = [0, 1],
        conditioning = "released_ragged_edge_observations_only",
        benchmark_tracks = ["common_information", "published_forecast"],
        ranking_pool = "ragged_edge_nowcast_only",
        promotion_eligible = false,
        realized_future_data_allowed = false,
        show_unconditional_baseline = false,
    ),
    "ex_ante_scenario" => (
        kind = "conditional_scenario",
        information_set = "exact_as_of_origin_plus_versioned_assumptions",
        origin_rule = "quarterly-after-advance.v1-draft",
        horizons = EXPECTED_HORIZONS,
        conditioning = "hard_soft_or_endogenous_labels_required",
        benchmark_tracks = ["common_information", "published_forecast"],
        ranking_pool = "ex_ante_scenario_only",
        promotion_eligible = false,
        realized_future_data_allowed = false,
        show_unconditional_baseline = true,
    ),
    "ex_post_replication" => (
        kind = "ex_post_paper_conditional",
        information_set = "revised_data_plus_realized_future_gem_paths",
        origin_rule = "paper-replication-interpretation.v1-draft",
        horizons = EXPECTED_HORIZONS,
        conditioning = "realized_future_government_exports_imports",
        benchmark_tracks = ["common_information"],
        ranking_pool = "ex_post_replication_only",
        promotion_eligible = false,
        realized_future_data_allowed = true,
        show_unconditional_baseline = true,
    ),
)

function validate_products(products)
    path = "protocol.products"
    expected_product_ids = sort!(collect(keys(EXPECTED_PRODUCTS)))
    check_keys(
        products,
        path,
        ("cross_product_pooling", expected_product_ids...),
    )
    expect_bool(products["cross_product_pooling"], "$path.cross_product_pooling") ===
        false ||
        fail("$path.cross_product_pooling", "products must remain distinct")

    stored_ids = String[]
    ranking_pools = String[]
    for section in expected_product_ids
        specification = EXPECTED_PRODUCTS[section]
        product_path = "$path.$section"
        product = expect_table(products[section], product_path)
        check_keys(
            product,
            product_path,
            (
                "product_id",
                "version",
                "kind",
                "information_set",
                "origin_rule",
                "horizons",
                "conditioning",
                "benchmark_tracks",
                "ranking_pool",
                "promotion_eligible",
                "realized_future_data_allowed",
                "show_unconditional_baseline",
            ),
        )
        product_id =
            expect_identifier(product["product_id"], "$product_path.product_id")
        product_id == section ||
            fail(
            "$product_path.product_id",
            "must equal its table name '$section'",
        )
        push!(stored_ids, product_id)
        expect_version(product["version"], "$product_path.version")
        for key in (
                "kind",
                "information_set",
                "origin_rule",
                "conditioning",
                "ranking_pool",
            )
            expect_exact_string(
                product,
                key,
                getproperty(specification, Symbol(key)),
                product_path,
            )
        end
        expect_exact(
            expect_int_vector(product["horizons"], "$product_path.horizons"),
            specification.horizons,
            "$product_path.horizons",
        )
        expect_exact(
            expect_string_vector(
                product["benchmark_tracks"],
                "$product_path.benchmark_tracks",
            ),
            specification.benchmark_tracks,
            "$product_path.benchmark_tracks",
        )
        for key in (
                "promotion_eligible",
                "realized_future_data_allowed",
                "show_unconditional_baseline",
            )
            actual = expect_bool(product[key], "$product_path.$key")
            expected = getproperty(specification, Symbol(key))
            actual === expected ||
                fail("$product_path.$key", "expected $expected")
        end
        push!(ranking_pools, String(product["ranking_pool"]))
    end
    length(Set(stored_ids)) == length(stored_ids) ||
        fail(path, "product IDs must be unique")
    length(Set(ranking_pools)) == length(ranking_pools) ||
        fail(path, "each product must have a distinct ranking pool")
    return products
end

const EXPECTED_TARGETS = Dict(
    "real_gdp" => (
        source_concept = "BEA_NIPA_real_gdp",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_growth",
        secondary_transformation = "four_quarter_log_growth",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
        critical = true,
    ),
    "pce_price_index" => (
        source_concept = "BEA_NIPA_pce_price_index",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
        critical = false,
    ),
    "core_pce_price_index" => (
        source_concept = "BEA_NIPA_core_pce_price_index",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
        critical = true,
    ),
    "gdp_deflator" => (
        source_concept = "BEA_NIPA_gdp_deflator",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
        critical = false,
    ),
    "unemployment_rate" => (
        source_concept = "BLS_CPS_unemployment_rate",
        aggregation = "quarterly_average_monthly",
        primary_transformation = "percent_level",
        secondary_transformation = "quarterly_change",
        output_unit = "percentage_points",
        truth_policy = "monthly_or_daily_derived",
        critical = true,
    ),
    "payroll_employment" => (
        source_concept = "BLS_CES_total_nonfarm_payrolls",
        aggregation = "quarterly_average_monthly",
        primary_transformation = "quarterly_log_growth",
        secondary_transformation = "revision_to_level",
        output_unit = "log_points",
        truth_policy = "monthly_or_daily_derived",
        critical = false,
    ),
    "effective_federal_funds_rate" => (
        source_concept = "FRB_effective_federal_funds_rate",
        aggregation = "quarterly_average_daily",
        primary_transformation = "percentage_point_level",
        secondary_transformation = "quarterly_change",
        output_unit = "percentage_points",
        truth_policy = "monthly_or_daily_derived",
        critical = false,
    ),
    "nominal_gdp" => (
        source_concept = "BEA_NIPA_nominal_gdp",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_growth",
        secondary_transformation = "four_quarter_log_growth",
        output_unit = "percentage_points_annual_rate",
        truth_policy = "nipa_quarterly",
        critical = false,
    ),
)

function validate_targets(targets)
    path = "protocol.targets"
    targets isa AbstractVector ||
        fail(path, "expected an array of target tables")
    length(targets) == length(EXPECTED_TARGETS) ||
        fail(path, "expected exactly $(length(EXPECTED_TARGETS)) Tier-1 targets")
    seen = Set{String}()
    total_weight = 0.0
    for (index, raw_target) in enumerate(targets)
        target_path = "$path[$index]"
        target = expect_table(raw_target, target_path)
        check_keys(
            target,
            target_path,
            (
                "target_id",
                "target_version",
                "operator_version",
                "source_concept",
                "aggregation",
                "primary_transformation",
                "secondary_transformation",
                "output_unit",
                "truth_policy",
                "bridge_status",
                "critical",
                "weight",
            ),
        )
        target_id =
            expect_identifier(target["target_id"], "$target_path.target_id")
        haskey(EXPECTED_TARGETS, target_id) ||
            fail("$target_path.target_id", "unrecognized Tier-1 target")
        target_id in seen &&
            fail("$target_path.target_id", "duplicate target '$target_id'")
        push!(seen, target_id)
        expect_version(
            target["target_version"],
            "$target_path.target_version",
        )
        expect_version(
            target["operator_version"],
            "$target_path.operator_version",
        )
        specification = EXPECTED_TARGETS[target_id]
        for key in (
                "source_concept",
                "aggregation",
                "primary_transformation",
                "secondary_transformation",
                "output_unit",
                "truth_policy",
            )
            expect_exact_string(
                target,
                key,
                getproperty(specification, Symbol(key)),
                target_path,
            )
        end
        expect_exact_string(
            target,
            "bridge_status",
            "pending_validation",
            target_path,
        )
        critical = expect_bool(target["critical"], "$target_path.critical")
        critical === specification.critical ||
            fail(
            "$target_path.critical",
            "critical-target designation disagrees with the contract",
        )
        weight = expect_float(target["weight"], "$target_path.weight")
        weight > 0.0 ||
            fail("$target_path.weight", "must be positive")
        total_weight += weight
    end
    seen == Set(keys(EXPECTED_TARGETS)) ||
        fail(path, "target set is incomplete")
    isapprox(total_weight, 1.0; atol = 1.0e-12, rtol = 0.0) ||
        fail(path, "target weights must sum to 1.0, got $total_weight")
    return targets
end

function validate_truth(truth)
    path = "protocol.truth"
    check_keys(
        truth,
        path,
        (
            "version",
            "error_sign",
            "revision_error_sign",
            "mixed_vintage_label_required",
            "score_status_before_mature",
            "score_status_after_mature",
            "first_release",
            "near_mature",
            "mature",
        ),
    )
    expect_version(truth["version"], "$path.version")
    expect_exact_string(
        truth,
        "error_sign",
        "forecast_minus_truth",
        path,
    )
    expect_exact_string(
        truth,
        "revision_error_sign",
        "first_release_minus_mature_truth",
        path,
    )
    expect_bool(
        truth["mixed_vintage_label_required"],
        "$path.mixed_vintage_label_required",
    ) === true ||
        fail("$path.mixed_vintage_label_required", "must be true")
    expect_exact_string(
        truth,
        "score_status_before_mature",
        "provisional",
        path,
    )
    expect_exact_string(
        truth,
        "score_status_after_mature",
        "final",
        path,
    )

    first = expect_table(truth["first_release"], "$path.first_release")
    check_keys(first, "$path.first_release", ("version", "definition", "tie_break"))
    expect_version(first["version"], "$path.first_release.version")
    expect_exact_string(
        first,
        "definition",
        "earliest_official_release_reporting_complete_target_reference_period",
        "$path.first_release",
    )
    expect_exact_string(
        first,
        "tie_break",
        "earliest_release_timestamp_then_source_release_id",
        "$path.first_release",
    )

    near = expect_table(truth["near_mature"], "$path.near_mature")
    check_keys(
        near,
        "$path.near_mature",
        (
            "version",
            "definition",
            "nipa_rule",
            "monthly_or_daily_rule",
            "cutoff_time_utc",
            "missing_cutoff_policy",
        ),
    )
    expect_version(near["version"], "$path.near_mature.version")
    expect_exact_string(
        near,
        "definition",
        "source_family_specific_fixed_rule",
        "$path.near_mature",
    )
    expect_exact_string(
        near,
        "nipa_rule",
        "third_scheduled_quarterly_estimate",
        "$path.near_mature",
    )
    expect_exact_string(
        near,
        "monthly_or_daily_rule",
        "latest_official_vintage_at_reference_period_end_plus_90_calendar_days",
        "$path.near_mature",
    )
    expect_exact_string(
        near,
        "cutoff_time_utc",
        "23:59:59Z",
        "$path.near_mature",
    )
    expect_exact_string(
        near,
        "missing_cutoff_policy",
        "score_unavailable",
        "$path.near_mature",
    )

    mature = expect_table(truth["mature"], "$path.mature")
    check_keys(
        mature,
        "$path.mature",
        (
            "version",
            "definition",
            "fixed_lag_months",
            "cutoff_time_utc",
            "post_cutoff_revisions",
            "missing_cutoff_policy",
        ),
    )
    expect_version(mature["version"], "$path.mature.version")
    expect_exact_string(
        mature,
        "definition",
        "latest_official_vintage_at_fixed_reference_period_lag",
        "$path.mature",
    )
    expect_int(mature["fixed_lag_months"], "$path.mature.fixed_lag_months") ==
        60 ||
        fail("$path.mature.fixed_lag_months", "expected 60")
    expect_exact_string(
        mature,
        "cutoff_time_utc",
        "23:59:59Z",
        "$path.mature",
    )
    expect_exact_string(
        mature,
        "post_cutoff_revisions",
        "excluded_from_primary_mature_truth",
        "$path.mature",
    )
    expect_exact_string(
        mature,
        "missing_cutoff_policy",
        "score_unavailable",
        "$path.mature",
    )
    return truth
end

const COMMON_BENCHMARKS = [
    "seasonal_naive",
    "random_walk",
    "ar",
    "var",
    "bvar",
    "dynamic_factor_bridge_midas",
    "compact_semi_structural",
    "smets_wouters_dsge",
]
const PUBLISHED_BENCHMARKS = [
    "spf",
    "cbo",
    "fomc_sep",
    "frbny_dsge",
    "gdpnow",
    "nyfed_staff_nowcast",
]

function validate_benchmark_track(
        track,
        path;
        information_rule,
        families,
        hyperparameter_rule,
        density_required,
        champion_eligible,
    )
    check_keys(
        track,
        path,
        (
            "version",
            "information_rule",
            "families",
            "hyperparameter_rule",
            "fallback_policy",
            "density_required",
            "eligible_for_primary_champion",
        ),
    )
    expect_version(track["version"], "$path.version")
    expect_exact_string(
        track,
        "information_rule",
        information_rule,
        path,
    )
    expect_exact(
        expect_string_vector(track["families"], "$path.families"),
        families,
        "$path.families",
    )
    expect_exact_string(
        track,
        "hyperparameter_rule",
        hyperparameter_rule,
        path,
    )
    expect_exact_string(
        track,
        "fallback_policy",
        "explicit_failure_record_no_silent_substitution",
        path,
    )
    actual_density_required =
        expect_bool(track["density_required"], "$path.density_required")
    actual_density_required === density_required ||
        fail("$path.density_required", "expected $density_required")
    eligible = expect_bool(
        track["eligible_for_primary_champion"],
        "$path.eligible_for_primary_champion",
    )
    eligible === champion_eligible ||
        fail(
        "$path.eligible_for_primary_champion",
        "expected $champion_eligible",
    )
    return track
end

function validate_benchmarks(benchmarks)
    path = "protocol.benchmarks"
    check_keys(
        benchmarks,
        path,
        (
            "version",
            "cross_track_pooling",
            "primary_champion_track",
            "common_information",
            "published_forecast",
        ),
    )
    expect_version(benchmarks["version"], "$path.version")
    expect_bool(
        benchmarks["cross_track_pooling"],
        "$path.cross_track_pooling",
    ) === false ||
        fail("$path.cross_track_pooling", "benchmark tracks must remain distinct")
    expect_exact_string(
        benchmarks,
        "primary_champion_track",
        "common_information",
        path,
    )
    validate_benchmark_track(
        expect_table(
            benchmarks["common_information"],
            "$path.common_information",
        ),
        "$path.common_information";
        information_rule = "identical_origin_manifest_and_eligible_observables",
        families = COMMON_BENCHMARKS,
        hyperparameter_rule = "selected_inside_each_origin_using_past_data_only",
        density_required = true,
        champion_eligible = true,
    )
    validate_benchmark_track(
        expect_table(
            benchmarks["published_forecast"],
            "$path.published_forecast",
        ),
        "$path.published_forecast";
        information_rule = "matched_archived_publication_timestamp_distinct_information_set",
        families = PUBLISHED_BENCHMARKS,
        hyperparameter_rule = "publisher_method_as_archived_not_reselected",
        density_required = false,
        champion_eligible = false,
    )
    return benchmarks
end

function validate_scores(scores)
    path = "protocol.scores"
    check_keys(
        scores,
        path,
        (
            "version",
            "balanced_sample_rule",
            "all_available_samples_reported",
            "exact_origin_counts_required",
            "heterogeneous_pooling_allowed",
            "point",
            "density",
            "horizon_weights",
        ),
    )
    expect_version(scores["version"], "$path.version")
    expect_exact_string(
        scores,
        "balanced_sample_rule",
        "intersection_by_target_horizon_truth_model_pair_and_benchmark_track",
        path,
    )
    for key in ("all_available_samples_reported", "exact_origin_counts_required")
        expect_bool(scores[key], "$path.$key") === true ||
            fail("$path.$key", "must be true")
    end
    expect_bool(
        scores["heterogeneous_pooling_allowed"],
        "$path.heterogeneous_pooling_allowed",
    ) === false ||
        fail("$path.heterogeneous_pooling_allowed", "must be false")

    point = expect_table(scores["point"], "$path.point")
    check_keys(
        point,
        "$path.point",
        ("primary", "diagnostics", "paper_parity", "mape_policy"),
    )
    expect_exact(
        expect_string_vector(point["primary"], "$path.point.primary"),
        ["rmse", "mae", "mase", "mean_error"],
        "$path.point.primary",
    )
    expect_exact(
        expect_string_vector(point["diagnostics"], "$path.point.diagnostics"),
        [
            "median_absolute_error",
            "relative_rmse",
            "relative_mae",
            "direction_accuracy",
            "turning_point_accuracy",
            "event_classification_accuracy",
            "economically_weighted_loss",
            "accounting_residual",
        ],
        "$path.point.diagnostics",
    )
    expect_exact_string(point, "paper_parity", "rmse", "$path.point")
    expect_exact_string(
        point,
        "mape_policy",
        "diagnostic_only_for_strictly_positive_economically_meaningful_levels",
        "$path.point",
    )

    density = expect_table(scores["density"], "$path.density")
    check_keys(
        density,
        "$path.density",
        (
            "primary",
            "interval_coverage_levels",
            "diagnostics",
            "event_scores",
            "multivariate_scores",
            "log_score_policy",
            "full_predictive_uncertainty_required",
        ),
    )
    expect_exact(
        expect_string_vector(density["primary"], "$path.density.primary"),
        ["crps", "weighted_interval_score"],
        "$path.density.primary",
    )
    coverage = expect_float_vector(
        density["interval_coverage_levels"],
        "$path.density.interval_coverage_levels",
    )
    expect_exact(
        coverage,
        [0.5, 0.8, 0.9, 0.95],
        "$path.density.interval_coverage_levels",
    )
    expect_exact(
        expect_string_vector(
            density["diagnostics"],
            "$path.density.diagnostics",
        ),
        [
            "coverage",
            "interval_width",
            "sharpness",
            "pit_rank_histogram",
            "serial_independence",
            "calibration_curve",
        ],
        "$path.density.diagnostics",
    )
    expect_exact(
        expect_string_vector(
            density["event_scores"],
            "$path.density.event_scores",
        ),
        ["brier_score", "reliability"],
        "$path.density.event_scores",
    )
    expect_exact(
        expect_string_vector(
            density["multivariate_scores"],
            "$path.density.multivariate_scores",
        ),
        ["energy_score", "variogram_score"],
        "$path.density.multivariate_scores",
    )
    expect_exact_string(
        density,
        "log_score_policy",
        "disabled_until_finite_ensemble_estimator_and_tail_safeguard_are_preregistered",
        "$path.density",
    )
    expect_bool(
        density["full_predictive_uncertainty_required"],
        "$path.density.full_predictive_uncertainty_required",
    ) === true ||
        fail("$path.density.full_predictive_uncertainty_required", "must be true")

    horizon_weights =
        expect_table(scores["horizon_weights"], "$path.horizon_weights")
    check_keys(
        horizon_weights,
        "$path.horizon_weights",
        ("horizons", "weights"),
    )
    horizons = expect_int_vector(
        horizon_weights["horizons"],
        "$path.horizon_weights.horizons",
    )
    expect_exact(horizons, EXPECTED_HORIZONS, "$path.horizon_weights.horizons")
    weights = expect_float_vector(
        horizon_weights["weights"],
        "$path.horizon_weights.weights",
    )
    length(weights) == length(horizons) ||
        fail("$path.horizon_weights.weights", "must align with horizons")
    all(weight -> weight > 0.0, weights) ||
        fail("$path.horizon_weights.weights", "weights must be positive")
    isapprox(sum(weights), 1.0; atol = 1.0e-12, rtol = 0.0) ||
        fail("$path.horizon_weights.weights", "weights must sum to 1.0")
    return scores
end

function validate_origin_requirements(requirements)
    path = "protocol.origin_requirements"
    check_keys(
        requirements,
        path,
        (
            "version",
            "core_horizons",
            "long_horizons",
            "retrospective_vintage_clean_minimum",
            "long_horizon_rule",
            "prospective_shadow_minimum",
            "exact_counts_by_cell_required",
            "insufficient_sample_status",
        ),
    )
    expect_version(requirements["version"], "$path.version")
    expect_exact(
        expect_int_vector(requirements["core_horizons"], "$path.core_horizons"),
        EXPECTED_CORE_HORIZONS,
        "$path.core_horizons",
    )
    expect_exact(
        expect_int_vector(requirements["long_horizons"], "$path.long_horizons"),
        EXPECTED_LONG_HORIZONS,
        "$path.long_horizons",
    )
    expect_int(
        requirements["retrospective_vintage_clean_minimum"],
        "$path.retrospective_vintage_clean_minimum",
    ) == 40 ||
        fail("$path.retrospective_vintage_clean_minimum", "expected 40")
    expect_exact_string(
        requirements,
        "long_horizon_rule",
        "maximum_common_balanced_sample_with_power_report",
        path,
    )
    expect_int(
        requirements["prospective_shadow_minimum"],
        "$path.prospective_shadow_minimum",
    ) == 8 ||
        fail("$path.prospective_shadow_minimum", "expected 8")
    expect_bool(
        requirements["exact_counts_by_cell_required"],
        "$path.exact_counts_by_cell_required",
    ) === true ||
        fail("$path.exact_counts_by_cell_required", "must be true")
    expect_exact_string(
        requirements,
        "insufficient_sample_status",
        "research_only_no_superiority_claim",
        path,
    )
    return requirements
end

function validate_promotion(promotion)
    path = "protocol.promotion"
    check_keys(
        promotion,
        path,
        (
            "version",
            "status",
            "product_id",
            "all_gates_required",
            "confidence_level",
            "scientific_integrity",
            "evidence_volume",
            "point_competitiveness",
            "density_usefulness",
            "robustness",
            "incremental_abm_value",
            "prospective_reliability",
            "governance",
        ),
    )
    expect_version(promotion["version"], "$path.version")
    expect_exact_string(
        promotion,
        "status",
        "inactive_pending_validation",
        path,
    )
    expect_exact_string(
        promotion,
        "product_id",
        "quarterly_unconditional",
        path,
    )
    expect_bool(promotion["all_gates_required"], "$path.all_gates_required") ===
        true ||
        fail("$path.all_gates_required", "must be true")
    confidence = expect_float(promotion["confidence_level"], "$path.confidence_level")
    confidence == 0.95 ||
        fail("$path.confidence_level", "expected 0.95")

    integrity = expect_table(
        promotion["scientific_integrity"],
        "$path.scientific_integrity",
    )
    check_keys(
        integrity,
        "$path.scientific_integrity",
        ("max_unresolved_failures", "failure_categories"),
    )
    expect_int(
        integrity["max_unresolved_failures"],
        "$path.scientific_integrity.max_unresolved_failures",
    ) == 0 ||
        fail(
        "$path.scientific_integrity.max_unresolved_failures",
        "expected zero",
    )
    expect_exact(
        expect_string_vector(
            integrity["failure_categories"],
            "$path.scientific_integrity.failure_categories",
        ),
        [
            "leakage",
            "identity",
            "variant",
            "parameter_status",
            "numerical",
            "scale_convergence",
        ],
        "$path.scientific_integrity.failure_categories",
    )

    evidence =
        expect_table(promotion["evidence_volume"], "$path.evidence_volume")
    check_keys(
        evidence,
        "$path.evidence_volume",
        (
            "retrospective_vintage_clean_minimum",
            "core_horizons",
            "long_horizon_rule",
        ),
    )
    expect_int(
        evidence["retrospective_vintage_clean_minimum"],
        "$path.evidence_volume.retrospective_vintage_clean_minimum",
    ) == 40 ||
        fail(
        "$path.evidence_volume.retrospective_vintage_clean_minimum",
        "expected 40",
    )
    expect_exact(
        expect_int_vector(
            evidence["core_horizons"],
            "$path.evidence_volume.core_horizons",
        ),
        EXPECTED_CORE_HORIZONS,
        "$path.evidence_volume.core_horizons",
    )
    expect_exact_string(
        evidence,
        "long_horizon_rule",
        "maximum_common_balanced_sample_with_power_report",
        "$path.evidence_volume",
    )

    point = expect_table(
        promotion["point_competitiveness"],
        "$path.point_competitiveness",
    )
    check_keys(
        point,
        "$path.point_competitiveness",
        (
            "index",
            "benchmark_track",
            "noninferiority_relative_loss_upper_ci_max",
            "critical_cell_relative_loss_upper_ci_max",
            "critical_cell_explanation_required",
        ),
    )
    expect_exact_string(
        point,
        "index",
        "target_horizon_weighted_primary_point_loss",
        "$path.point_competitiveness",
    )
    expect_exact_string(
        point,
        "benchmark_track",
        "strongest_frozen_common_information_benchmark",
        "$path.point_competitiveness",
    )
    expect_float(
        point["noninferiority_relative_loss_upper_ci_max"],
        "$path.point_competitiveness.noninferiority_relative_loss_upper_ci_max",
    ) == 1.05 ||
        fail(
        "$path.point_competitiveness.noninferiority_relative_loss_upper_ci_max",
        "expected 1.05",
    )
    expect_float(
        point["critical_cell_relative_loss_upper_ci_max"],
        "$path.point_competitiveness.critical_cell_relative_loss_upper_ci_max",
    ) == 1.1 ||
        fail(
        "$path.point_competitiveness.critical_cell_relative_loss_upper_ci_max",
        "expected 1.10",
    )
    expect_bool(
        point["critical_cell_explanation_required"],
        "$path.point_competitiveness.critical_cell_explanation_required",
    ) === true ||
        fail(
        "$path.point_competitiveness.critical_cell_explanation_required",
        "must be true",
    )

    density = expect_table(
        promotion["density_usefulness"],
        "$path.density_usefulness",
    )
    check_keys(
        density,
        "$path.density_usefulness",
        (
            "primary_scores",
            "noninferiority_relative_score_upper_ci_max",
            "maximum_absolute_coverage_error",
            "full_predictive_uncertainty_required",
        ),
    )
    expect_exact(
        expect_string_vector(
            density["primary_scores"],
            "$path.density_usefulness.primary_scores",
        ),
        ["crps", "weighted_interval_score"],
        "$path.density_usefulness.primary_scores",
    )
    expect_float(
        density["noninferiority_relative_score_upper_ci_max"],
        "$path.density_usefulness.noninferiority_relative_score_upper_ci_max",
    ) == 1.05 ||
        fail(
        "$path.density_usefulness.noninferiority_relative_score_upper_ci_max",
        "expected 1.05",
    )
    expect_float(
        density["maximum_absolute_coverage_error"],
        "$path.density_usefulness.maximum_absolute_coverage_error",
    ) == 0.1 ||
        fail(
        "$path.density_usefulness.maximum_absolute_coverage_error",
        "expected 0.10",
    )
    expect_bool(
        density["full_predictive_uncertainty_required"],
        "$path.density_usefulness.full_predictive_uncertainty_required",
    ) === true ||
        fail(
        "$path.density_usefulness.full_predictive_uncertainty_required",
        "must be true",
    )

    robustness =
        expect_table(promotion["robustness"], "$path.robustness")
    check_keys(
        robustness,
        "$path.robustness",
        ("required_dimensions", "max_unexplained_failures"),
    )
    expect_exact(
        expect_string_vector(
            robustness["required_dimensions"],
            "$path.robustness.required_dimensions",
        ),
        [
            "truth_vintage",
            "estimation_window",
            "regime",
            "agent_scale",
            "origin_state_draws",
            "structural_and_model_variants",
        ],
        "$path.robustness.required_dimensions",
    )
    expect_int(
        robustness["max_unexplained_failures"],
        "$path.robustness.max_unexplained_failures",
    ) == 0 ||
        fail("$path.robustness.max_unexplained_failures", "expected zero")

    incremental = expect_table(
        promotion["incremental_abm_value"],
        "$path.incremental_abm_value",
    )
    check_keys(
        incremental,
        "$path.incremental_abm_value",
        (
            "eligible_objectives",
            "minimum_relative_improvement",
            "tier1_point_gate_must_pass",
        ),
    )
    expect_exact(
        expect_string_vector(
            incremental["eligible_objectives"],
            "$path.incremental_abm_value.eligible_objectives",
        ),
        [
            "sector",
            "joint_tail",
            "scenario",
            "combination",
        ],
        "$path.incremental_abm_value.eligible_objectives",
    )
    expect_float(
        incremental["minimum_relative_improvement"],
        "$path.incremental_abm_value.minimum_relative_improvement",
    ) == 0.02 ||
        fail(
        "$path.incremental_abm_value.minimum_relative_improvement",
        "expected 0.02",
    )
    expect_bool(
        incremental["tier1_point_gate_must_pass"],
        "$path.incremental_abm_value.tier1_point_gate_must_pass",
    ) === true ||
        fail(
        "$path.incremental_abm_value.tier1_point_gate_must_pass",
        "must be true",
    )

    prospective = expect_table(
        promotion["prospective_reliability"],
        "$path.prospective_reliability",
    )
    check_keys(
        prospective,
        "$path.prospective_reliability",
        ("minimum_consecutive_origins", "max_material_pipeline_failures"),
    )
    expect_int(
        prospective["minimum_consecutive_origins"],
        "$path.prospective_reliability.minimum_consecutive_origins",
    ) == 8 ||
        fail(
        "$path.prospective_reliability.minimum_consecutive_origins",
        "expected 8",
    )
    expect_int(
        prospective["max_material_pipeline_failures"],
        "$path.prospective_reliability.max_material_pipeline_failures",
    ) == 0 ||
        fail(
        "$path.prospective_reliability.max_material_pipeline_failures",
        "expected zero",
    )

    governance =
        expect_table(promotion["governance"], "$path.governance")
    check_keys(
        governance,
        "$path.governance",
        ("required_signoffs", "rollback_procedure_required"),
    )
    expect_exact(
        expect_string_vector(
            governance["required_signoffs"],
            "$path.governance.required_signoffs",
        ),
        [
            "observation_operator",
            "vintage_firewall",
            "benchmark_fairness",
            "model_risk_limits",
            "rollback_procedure",
        ],
        "$path.governance.required_signoffs",
    )
    expect_bool(
        governance["rollback_procedure_required"],
        "$path.governance.rollback_procedure_required",
    ) === true ||
        fail("$path.governance.rollback_procedure_required", "must be true")
    return promotion
end

function validate_change_control(change_control)
    path = "protocol.change_control"
    check_keys(
        change_control,
        path,
        (
            "version",
            "retrospective_score_freeze",
            "exploratory_change_policy",
            "prospective_maintenance_policy",
            "material_change_requires_new_experiment_version",
            "forecast_artifacts_immutable",
            "truth_and_scores_append_only",
        ),
    )
    expect_version(change_control["version"], "$path.version")
    expect_exact_string(
        change_control,
        "retrospective_score_freeze",
        "freeze_code_data_queries_targets_weights_margins_and_seeds_before_final_run",
        path,
    )
    expect_exact_string(
        change_control,
        "exploratory_change_policy",
        "new_exploratory_experiment_id_and_no_retroactive_primary_claim",
        path,
    )
    expect_exact_string(
        change_control,
        "prospective_maintenance_policy",
        "versioned_change_with_predeployment_review_and_parallel_challenger_run",
        path,
    )
    for key in (
            "material_change_requires_new_experiment_version",
            "forecast_artifacts_immutable",
            "truth_and_scores_append_only",
        )
        expect_bool(change_control[key], "$path.$key") === true ||
            fail("$path.$key", "must be true")
    end
    return change_control
end

"""
    validate_protocol(protocol)

Validate the complete WS-0A contract. Every table uses an exact key allowlist,
and every decision-bearing value has a type and semantic check. Unknown or
missing material is rejected rather than defaulted.
"""
function validate_protocol(protocol)
    path = "protocol"
    check_keys(
        protocol,
        path,
        (
            "schema_version",
            "protocol_id",
            "experiment_version",
            "status",
            "approval_status",
            "canonicalization",
            "digest_algorithm",
            "governance",
            "issue_rules",
            "products",
            "targets",
            "truth",
            "benchmarks",
            "scores",
            "origin_requirements",
            "promotion",
            "change_control",
        ),
    )
    expect_exact_string(
        protocol,
        "schema_version",
        EXPECTED_SCHEMA,
        path,
    )
    expect_version(protocol["protocol_id"], "$path.protocol_id")
    expect_version(protocol["experiment_version"], "$path.experiment_version")
    expect_exact_string(protocol, "status", "draft", path)
    expect_exact_string(
        protocol,
        "approval_status",
        "pending_validation",
        path,
    )
    expect_exact_string(
        protocol,
        "canonicalization",
        "utf8_length_prefixed_sorted_map.v1",
        path,
    )
    expect_exact_string(protocol, "digest_algorithm", "sha256", path)
    validate_governance(
        expect_table(protocol["governance"], "$path.governance"),
    )
    validate_issue_rules(
        expect_table(protocol["issue_rules"], "$path.issue_rules"),
    )
    validate_products(expect_table(protocol["products"], "$path.products"))
    validate_targets(protocol["targets"])
    validate_truth(expect_table(protocol["truth"], "$path.truth"))
    validate_benchmarks(
        expect_table(protocol["benchmarks"], "$path.benchmarks"),
    )
    validate_scores(expect_table(protocol["scores"], "$path.scores"))
    validate_origin_requirements(
        expect_table(
            protocol["origin_requirements"],
            "$path.origin_requirements",
        ),
    )
    validate_promotion(
        expect_table(protocol["promotion"], "$path.promotion"),
    )
    validate_change_control(
        expect_table(protocol["change_control"], "$path.change_control"),
    )
    return protocol
end

function write_canonical(io::IO, value)
    if value isa AbstractDict
        entries = sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            write_canonical(io, String(key))
            write_canonical(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "A", length(value), "[")
        for entry in value
            write_canonical(io, entry)
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
        bits = reinterpret(UInt64, number)
        print(io, "F", string(bits; base = 16, pad = 16))
    else
        fail(
            "protocol",
            "unsupported canonical value type $(typeof(value))",
        )
    end
    return io
end

"""
    canonicalize_protocol(protocol) -> String

Return the validated protocol in a deterministic, typed, length-prefixed UTF-8
encoding. Map keys are sorted; array order remains contract-significant.
"""
function canonicalize_protocol(protocol)
    validate_protocol(protocol)
    io = IOBuffer()
    write_canonical(io, protocol)
    return String(take!(io))
end

"""
    protocol_sha256(protocol) -> String

Return the lowercase SHA-256 digest of the canonical protocol bytes.
"""
function protocol_sha256(protocol)
    canonical = canonicalize_protocol(protocol)
    return bytes2hex(sha256(collect(codeunits(canonical))))
end

"""
    load_protocol([path]) -> Dict

Parse and validate a protocol TOML file. Parse errors and schema errors both
fail closed.
"""
function load_protocol(path::AbstractString = DEFAULT_PROTOCOL_PATH)
    isfile(path) ||
        fail("protocol", "file does not exist: $(abspath(path))")
    protocol = try
        TOML.parsefile(path)
    catch error
        fail(
            "protocol",
            "could not parse TOML: $(sprint(showerror, error))",
        )
    end
    return validate_protocol(protocol)
end

"""
    protocol_artifact([path])

Load the protocol and return its validated data, canonical representation, and
canonical SHA-256. The digest is stable across TOML comments and table ordering.
"""
function protocol_artifact(path::AbstractString = DEFAULT_PROTOCOL_PATH)
    protocol = load_protocol(path)
    canonical = canonicalize_protocol(protocol)
    digest = bytes2hex(sha256(collect(codeunits(canonical))))
    return (; protocol, canonical, sha256 = digest)
end

end
