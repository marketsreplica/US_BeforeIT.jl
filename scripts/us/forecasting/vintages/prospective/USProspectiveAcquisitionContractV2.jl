module USProspectiveAcquisitionContractV2

using Dates
using SHA
using TOML

export ProspectiveContractV2ValidationError,
    contract_sha256,
    evaluate_requirement_completion,
    load_contract,
    stamp_contract_sha256!,
    validate_contract

const CONTRACT_SCHEMA =
    "beforeit-us-prospective-acquisition-requirements.v6-draft"
const CONTRACT_ID = "beforeit-us-prospective-2026q3-acquisition.v2"
const PROTOCOL_SHA256 =
    "88519e5b04936f528396cf5243ff270844d0d38651fd84fc3b1c76fef997b584"
const TIER1_TARGETS_SHA256 =
    "bdbbeb48a39c7fdd03972626cf7f1e421ba7c5dd254f5537a40dda0eb4ae1fcb"
const CANONICALIZATION = "utf8-length-prefixed-sorted-map-array-order.v1"
const ORIGIN_TIMESTAMP = "2026-10-30T14:00:00Z"
const MINIMUM_RETAIN_UNTIL = "2031-10-30T14:00:00Z"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const TIMESTAMP_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"
const TIME_Z_PATTERN = r"^\d{2}:\d{2}:\d{2}Z$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"

const ROOT_KEYS = Set(
    [
        "artifact",
        "origin",
        "availability_policy",
        "selector_resolution_policy",
        "verifier",
        "approval",
        "retention",
        "requirements",
        "fixed_events",
        "recurring_windows",
        "snapshot_campaigns",
    ],
)
const SELECTOR_RESOLUTION_POLICY_KEYS = Set(
    [
        "policy_version",
        "resolution_schema",
        "planned_selector_field",
        "resolved_selector_hash_field",
        "candidate_catalog_required",
        "candidate_rank_must_equal_one",
        "resolved_identity_must_not_contain_tokens",
        "not_applicable_literal",
        "unknown_release_timestamp_literal",
        "raw_receipt_hash_binding_required",
        "resolved_dimensions_bind_every_selector_key",
        "dynamic_set_resolutions_required",
        "official_artifact_host_allowlist_enforced",
        "official_artifact_source_affinity_enforced",
        "verifier_attestation_required_for_completion",
        "shape_complete_is_not_requirement_complete",
    ],
)
const ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "contract_id",
        "status",
        "as_of_date",
        "protocol_sha256",
        "tier1_targets_sha256",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const ORIGIN_KEYS = Set(
    [
        "origin_id",
        "reference_quarter",
        "origin_timestamp_utc",
        "origin_rule",
        "admission_status",
        "inventory_mutation_authorized",
        "origin_admissible",
        "ready",
        "accuracy_evaluation_allowed",
    ],
)
const AVAILABILITY_KEYS = Set(
    [
        "policy_version",
        "eligibility_time_field",
        "eligible_basis",
        "availability_upper_bound_semantics",
        "upper_bound_must_equal_receipt_completed_at_utc",
        "upper_bound_must_precede_origin",
        "unknown_original_release_time_allowed_for_prospective_receipt",
        "official_release_timestamp_preserved_when_evidenced",
        "post_origin_receipt_eligible",
        "historical_backfill_eligible",
        "unverified_receipt_eligible",
        "schedule_or_route_only_eligible",
        "raw_sha256_required",
        "receipt_sha256_required",
        "durable_storage_receipt_required",
    ],
)
const VERIFIER_KEYS = Set(
    [
        "implementation_status",
        "implementation_artifact_sha256",
        "receipt_artifact_verification_status",
        "activation_requires_implementation",
        "status_is_independent_of_requirements_approval",
    ],
)
const APPROVAL_KEYS = Set(
    [
        "artifact_approval_status",
        "model_owner",
        "model_owner_signature",
        "independent_validator",
        "independent_validator_signature",
        "activation_requires_approval",
        "status_is_independent_of_verifier_implementation",
    ],
)
const RETENTION_KEYS = Set(
    [
        "policy_version",
        "minimum_retain_until_utc",
        "origin_plus_mature_truth_months",
        "minimum_durable_copy_count",
        "content_addressed_storage_required",
        "write_once_or_versioned_storage_required",
        "raw_and_receipt_bytes_co_retained",
        "hash_manifest_required",
        "external_timestamp_receipt_required",
        "github_actions_artifact_only_allowed",
        "short_retention_artifact_is_origin_evidence",
    ],
)
const REQUIREMENT_KEYS = Set(
    [
        "requirement_id",
        "block_kind",
        "source_id",
        "source_family",
        "source_locator",
        "target_ids",
        "acquisition_mode",
        "required_for_complete_origin",
        "completion_rule",
        "default_capture_id",
        "profile_capture_overrides",
        "profile_completion_dates",
        "required_profile_count",
        "artifact_profiles",
        "evidence_status",
        "registered_raw_artifact_count",
    ],
)
const FIXED_EVENT_KEYS = Set(
    [
        "event_id",
        "source_id",
        "requirement_ids",
        "reference_period",
        "official_schedule_locator",
        "scheduled_timestamp_utc",
        "timestamp_basis",
        "capture_not_before_utc",
        "capture_deadline_utc",
        "event_purpose",
        "required_for_complete_origin",
        "capture_status",
        "immutable_receipt_status",
        "receipt_count",
        "origin_eligible",
    ],
)
const RECURRING_WINDOW_KEYS = Set(
    [
        "window_id",
        "source_id",
        "requirement_id",
        "campaign_start_date",
        "campaign_end_date",
        "scheduled_time_utc",
        "capture_window_minutes",
        "business_day_rule",
        "excluded_dates",
        "timestamp_basis",
        "evidence_role",
        "origin_day_completion_before_cutoff_required",
        "capture_status",
        "receipt_count",
        "origin_eligible",
    ],
)
const SNAPSHOT_CAMPAIGN_KEYS = Set(
    [
        "campaign_id",
        "requirement_ids",
        "capture_not_before_utc",
        "capture_deadline_utc",
        "availability_basis",
        "purpose",
        "capture_status",
        "receipt_count",
        "origin_eligible",
    ],
)
const PROFILE_EVIDENCE_KEYS = Set(
    [
        "evidence_id",
        "requirement_id",
        "profile_id",
        "selector",
        "capture_id",
        "raw_sha256",
        "receipt_sha256",
        "selector_evidence_sha256",
        "receipt_completed_at_utc",
        "availability_upper_bound_utc",
        "receipt_artifact_status",
        "durable_storage_status",
        "retain_until_utc",
        "resolution",
    ],
)
const SELECTOR_RESOLUTION_KEYS = Set(
    [
        "resolution_schema",
        "requirement_id",
        "profile_id",
        "policy_selector",
        "resolution_mode",
        "source_id",
        "release_id",
        "release_timestamp_utc",
        "reference_period",
        "dataset_id",
        "frequency",
        "table_id",
        "line_id",
        "series_id",
        "official_artifact_locator",
        "artifact_member_locator",
        "candidate_catalog_sha256",
        "candidate_rank",
        "eligible_candidate_count",
        "raw_sha256",
        "receipt_sha256",
        "receipt_completed_at_utc",
        "resolved_dimensions",
        "set_resolutions",
    ],
)
const SET_RESOLUTION_KEYS = Set(
    [
        "policy_value",
        "coverage_mode",
        "resolved_value",
        "member_count",
        "members_sha256",
        "candidate_catalog_sha256",
    ],
)
const SELECTOR_RESOLUTION_SCHEMA =
    "beforeit-us-resolved-selector-evidence.v3-draft"
const UNRESOLVED_IDENTITY_PATTERN =
    r"(?i)(^|[^A-Z0-9])(ALL|LATEST|PINNED|SAME|THROUGH)([^A-Z0-9]|$)"
const OFFICIAL_ARTIFACT_HOSTS_BY_SELECTOR_SOURCE = Dict(
    "BEA" => Set(["apps.bea.gov", "www.bea.gov"]),
    "BEFOREIT" => Set(["github.com", "raw.githubusercontent.com"]),
    "BLS" => Set(["download.bls.gov", "www.bls.gov"]),
    "CENSUS" => Set(["api.census.gov", "www.census.gov", "www2.census.gov"]),
    "FRB" => Set(["www.federalreserve.gov"]),
    "FRED" => Set(["api.stlouisfed.org", "fred.stlouisfed.org"]),
    "FRBNY" => Set(["markets.newyorkfed.org", "www.newyorkfed.org"]),
    "USDA" => Set(
        ["nass.usda.gov", "www.nass.usda.gov", "www.usda.gov"],
    ),
)

const TIER1_TARGET_IDS = Set(
    [
        "core_pce_price_index",
        "effective_federal_funds_rate",
        "gdp_deflator",
        "nominal_gdp",
        "payroll_employment",
        "pce_price_index",
        "real_gdp",
        "unemployment_rate",
    ],
)

const REQUIRED_REQUIREMENTS = Dict(
    "bea_fixed_assets_structural" => (
        block_kind = "structural",
        source_id = "bea_fixed_assets_hmi11",
        source_family = "fixed_assets",
        source_locator = "https://apps.bea.gov/histdata/",
        target_ids = String[],
        acquisition_mode = "fixed_release_and_pre_origin_snapshot",
    ),
    "bea_gdpbyindustry_sector_accounts" => (
        block_kind = "structural",
        source_id = "bea_gdpbyindustry",
        source_family = "gdp_by_industry_sector_accounts",
        source_locator = "https://apps.bea.gov/histdata/",
        target_ids = String[],
        acquisition_mode = "fixed_release_and_pre_origin_snapshot",
    ),
    "bea_industry_io_structural" => (
        block_kind = "structural",
        source_id = "bea_industry_hmi8",
        source_family = "industry_input_output",
        source_locator = "https://apps.bea.gov/histdata/",
        target_ids = String[],
        acquisition_mode = "fixed_release_and_pre_origin_snapshot",
    ),
    "bea_industry_valuation_structural" => (
        block_kind = "structural",
        source_id = "bea_industry_valuation_matrices",
        source_family = "industry_input_output_valuation",
        source_locator = "https://www.bea.gov/industry/input-output-accounts-data",
        target_ids = String[],
        acquisition_mode = "fixed_release_and_pre_origin_snapshot",
    ),
    "bea_inventory_stock_control" => (
        block_kind = "structural",
        source_id = "bea_nipa_t50805b",
        source_family = "private_inventory_stock",
        source_locator = "https://apps.bea.gov/histdata/",
        target_ids = String[],
        acquisition_mode = "fixed_release_and_pre_origin_snapshot",
    ),
    "bea_nipa_expenditure_history" => (
        block_kind = "structural",
        source_id = "bea_nipa_hmi7_expenditure_history",
        source_family = "nipa_quarterly_expenditure_calibration",
        source_locator = "https://apps.bea.gov/histdata/",
        target_ids = String[],
        acquisition_mode = "fixed_release",
    ),
    "bea_nipa_income_fiscal_structural" => (
        block_kind = "structural",
        source_id = "bea_nipa_hmi7_calibration",
        source_family = "nipa_income_fiscal_calibration",
        source_locator = "https://apps.bea.gov/histdata/",
        target_ids = String[],
        acquisition_mode = "fixed_release_and_pre_origin_snapshot",
    ),
    "bea_nipa_tier1" => (
        block_kind = "target",
        source_id = "bea_nipa_hmi7",
        source_family = "nipa",
        source_locator = "https://apps.bea.gov/histdata/",
        target_ids = [
            "core_pce_price_index",
            "gdp_deflator",
            "nominal_gdp",
            "pce_price_index",
            "real_gdp",
        ],
        acquisition_mode = "fixed_release",
    ),
    "bls_cps_structural" => (
        block_kind = "structural",
        source_id = "bls_cps_structural_controls",
        source_family = "cps_structural_controls",
        source_locator = "https://www.bls.gov/cps/data.htm",
        target_ids = String[],
        acquisition_mode = "pre_origin_snapshot",
    ),
    "bls_employment_tier1" => (
        block_kind = "target",
        source_id = "bls_employment_situation",
        source_family = "employment_situation",
        source_locator = "https://www.bls.gov/bls/news-release/empsit.htm",
        target_ids = ["payroll_employment", "unemployment_rate"],
        acquisition_mode = "fixed_release",
    ),
    "bls_qcew_structural" => (
        block_kind = "structural",
        source_id = "bls_qcew",
        source_family = "quarterly_census_employment_wages",
        source_locator = "https://www.bls.gov/cew/downloadable-data-files.htm",
        target_ids = String[],
        acquisition_mode = "fixed_release_and_pre_origin_snapshot",
    ),
    "census_aies_inventory_allocation" => (
        block_kind = "structural",
        source_id = "census_aies_inventory",
        source_family = "annual_integrated_economic_survey_inventory",
        source_locator = "https://www.census.gov/programs-surveys/aies.html",
        target_ids = String[],
        acquisition_mode = "pre_origin_snapshot",
    ),
    "census_m3_inventory_stages" => (
        block_kind = "structural",
        source_id = "census_m3",
        source_family = "manufacturers_shipments_inventories_orders",
        source_locator = "https://www.census.gov/manufacturing/m3/",
        target_ids = String[],
        acquisition_mode = "fixed_release",
    ),
    "census_mrts_inventory_stock" => (
        block_kind = "structural",
        source_id = "census_mrts",
        source_family = "monthly_retail_trade_inventory",
        source_locator = "https://www.census.gov/retail/mrtsinv/",
        target_ids = String[],
        acquisition_mode = "fixed_release",
    ),
    "census_mwts_inventory_stock" => (
        block_kind = "structural",
        source_id = "census_mwts",
        source_family = "monthly_wholesale_trade_inventory",
        source_locator = "https://www.census.gov/wholesale/",
        target_ids = String[],
        acquisition_mode = "fixed_release",
    ),
    "census_susb_structural" => (
        block_kind = "structural",
        source_id = "census_susb",
        source_family = "statistics_of_us_businesses",
        source_locator = "https://www.census.gov/programs-surveys/susb/data.html",
        target_ids = String[],
        acquisition_mode = "pre_origin_snapshot",
    ),
    "classification_maps" => (
        block_kind = "source",
        source_id = "official_classification_maps",
        source_family = "classification_and_concordance",
        source_locator = "https://www.census.gov/naics/",
        target_ids = String[],
        acquisition_mode = "pre_origin_snapshot",
    ),
    "frb_z1_structural" => (
        block_kind = "structural",
        source_id = "frb_z1",
        source_family = "financial_accounts_z1",
        source_locator = "https://www.federalreserve.gov/releases/z1/release-dates.htm",
        target_ids = String[],
        acquisition_mode = "fixed_release",
    ),
    "fred_policy_rate_history" => (
        block_kind = "structural",
        source_id = "fred_fedfunds",
        source_family = "effective_federal_funds_rate_history",
        source_locator = "https://fred.stlouisfed.org/series/FEDFUNDS",
        target_ids = String[],
        acquisition_mode = "pre_origin_snapshot",
    ),
    "frbny_effr_tier1" => (
        block_kind = "target",
        source_id = "frbny_effr",
        source_family = "reference_rates_effr",
        source_locator = "https://www.newyorkfed.org/markets/reference-rates/effr",
        target_ids = ["effective_federal_funds_rate"],
        acquisition_mode = "fixed_and_recurring_release",
    ),
    "usda_counts_structural" => (
        block_kind = "structural",
        source_id = "usda_nass_farms_land",
        source_family = "farms_and_land_in_farms",
        source_locator = "https://www.nass.usda.gov/Publications/Todays_Reports/",
        target_ids = String[],
        acquisition_mode = "pre_origin_snapshot",
    ),
)

const REQUIRED_PROFILES_BY_REQUIREMENT = Dict(
    "bea_fixed_assets_structural" => Dict(
        "faat301esi_net_stock" =>
            "BEA:FixedAssets:TableName=FAAt301ESI:Frequency=A:Year=2024:LineNumber=1,3,4,6,7,8,9,13,16,17,18,19,20,21,22,23,24,25,26,30,33,34,35,36,37,38,39,40,43,49,50,51,52,53,54,55,56,58,59,60,61,63,64,68,69,72,74,75,77,78,79,80,82,83,84,86,87,88,89,91,92,94,95,96",
        "faat304esi_depreciation" =>
            "BEA:FixedAssets:TableName=FAAt304ESI:Frequency=A:Year=2024:LineNumber=1,3,4,6,7,8,9,13,16,17,18,19,20,21,22,23,24,25,26,30,33,34,35,36,37,38,39,40,43,49,50,51,52,53,54,55,56,58,59,60,61,63,64,68,69,72,74,75,77,78,79,80,82,83,84,86,87,88,89,91,92,94,95,96",
        "faat307esi_investment" =>
            "BEA:FixedAssets:TableName=FAAt307ESI:Frequency=A:Year=2024:LineNumber=1,3,4,6,7,8,9,13,16,17,18,19,20,21,22,23,24,25,26,30,33,34,35,36,37,38,39,40,43,49,50,51,52,53,54,55,56,58,59,60,61,63,64,68,69,72,74,75,77,78,79,80,82,83,84,86,87,88,89,91,92,94,95,96",
        "faat501_residential_net_stock" =>
            "BEA:FixedAssets:TableName=FAAt501:Frequency=A:Year=2024:LineNumber=11,12",
        "faat504_residential_depreciation" =>
            "BEA:FixedAssets:TableName=FAAt504:Frequency=A:Year=2024:LineNumber=11,12",
        "faat507_residential_investment" =>
            "BEA:FixedAssets:TableName=FAAt507:Frequency=A:Year=2024:LineNumber=11,12",
        "faat701_government_net_stock" =>
            "BEA:FixedAssets:TableName=FAAt701:Frequency=A:Year=2024:LineNumber=1,21,22,55,79",
        "faat703_government_depreciation" =>
            "BEA:FixedAssets:TableName=FAAt703:Frequency=A:Year=2024:LineNumber=1,21,22,55,79",
    ),
    "bea_gdpbyindustry_sector_accounts" => Dict(
        "gdpbyindustry_t1_value_added_annual_2024" =>
            "BEA:GDPbyIndustry:TableID=1:Frequency=A:Year=2024:Industry=ALL",
        "gdpbyindustry_t1_value_added_quarterly_through_2026q2" =>
            "BEA:GDPbyIndustry:TableID=1:Frequency=Q:Year=2024,2025,2026:Industry=ALL:required_last_period=2026Q2",
        "gdpbyindustry_t6_components_value_added_annual_2024" =>
            "BEA:GDPbyIndustry:TableID=6:Frequency=A:Year=2024:Industry=ALL",
        "gdpbyindustry_t10_real_value_added_annual_2024" =>
            "BEA:GDPbyIndustry:TableID=10:Frequency=A:Year=2024:Industry=ALL",
        "gdpbyindustry_t10_real_value_added_quarterly_through_2026q2" =>
            "BEA:GDPbyIndustry:TableID=10:Frequency=Q:Year=2024,2025,2026:Industry=ALL:required_last_period=2026Q2",
        "gdpbyindustry_t15_gross_output_annual_2024" =>
            "BEA:GDPbyIndustry:TableID=15:Frequency=A:Year=2024:Industry=ALL",
        "gdpbyindustry_t15_gross_output_quarterly_through_2026q2" =>
            "BEA:GDPbyIndustry:TableID=15:Frequency=Q:Year=2024,2025,2026:Industry=ALL:required_last_period=2026Q2",
        "gdpbyindustry_t20_intermediate_inputs_annual_2024" =>
            "BEA:GDPbyIndustry:TableID=20:Frequency=A:Year=2024:Industry=ALL",
        "gdpbyindustry_t20_intermediate_inputs_quarterly_through_2026q2" =>
            "BEA:GDPbyIndustry:TableID=20:Frequency=Q:Year=2024,2025,2026:Industry=ALL:required_last_period=2026Q2",
        "gdpbyindustry_t208_real_gross_output_annual_2024" =>
            "BEA:GDPbyIndustry:TableID=208:Frequency=A:Year=2024:Industry=ALL",
        "gdpbyindustry_t208_real_gross_output_quarterly_through_2026q2" =>
            "BEA:GDPbyIndustry:TableID=208:Frequency=Q:Year=2024,2025,2026:Industry=ALL:required_last_period=2026Q2",
        "gdpbyindustry_t209_real_intermediate_inputs_annual_2024" =>
            "BEA:GDPbyIndustry:TableID=209:Frequency=A:Year=2024:Industry=ALL",
        "gdpbyindustry_t209_real_intermediate_inputs_quarterly_through_2026q2" =>
            "BEA:GDPbyIndustry:TableID=209:Frequency=Q:Year=2024,2025,2026:Industry=ALL:required_last_period=2026Q2",
    ),
    "bea_industry_io_structural" => Dict(
        "inputoutput_t259_use" =>
            "BEA:InputOutput:TableID=259:Year=2024:full_published_table=true:required_rows=71_source_commodities,Used,Other,T005,V001,T00OTOP,T00OSUB,V003,VABAS,T018,T00TOP,T00SUB,VAPRO:required_columns=71_source_industries,T001,F010,F02S,F02E,F02N,F02R,F030,F040,F06C,F06S,F06E,F06N,F07C,F07S,F07E,F07N,F10C,F10S,F10E,F10N,T019",
        "inputoutput_t262_supply" =>
            "BEA:InputOutput:TableID=262:Year=2024:full_published_table=true:required_rows=71_source_commodities,Other,Used,T017:required_columns=71_source_industries,T007,MCIF,MADJ,T013,Trade,Trans,T014,MDTY,TOP,SUB,T015,T016",
    ),
    "bea_industry_valuation_structural" => Dict(
        "after_redefinitions_release_zip" =>
            "BEA:InputOutputAfterRedefinitions:release=2025_annual_update:archive=MAKE-USE-IMPORTS (AFTER REDEFINITIONS).zip",
        "producer_use_2024" =>
            "BEA:InputOutputAfterRedefinitions:member=IOUse_After_Redefinitions_PRO_Summary.xlsx:sheet=2024:price_basis=producers",
        "make_2024" =>
            "BEA:InputOutputAfterRedefinitions:member=IOMake_After_Redefinitions_PRO_Summary.xlsx:sheet=2024:price_basis=producers",
        "imports_by_user_2024" =>
            "BEA:InputOutputAfterRedefinitions:member=ImportMatrices_After_Redefinitions_Summary.xlsx:sheet=2024:full_industry_and_final_use_matrix=true",
        "benchmark_purchaser_use_2017" =>
            "BEA:BenchmarkInputOutput:Year=2017:use_table:price_basis=purchasers:full_published_table=true:resolved_workbook_member_required=true",
        "benchmark_producer_use_2017" =>
            "BEA:BenchmarkInputOutput:Year=2017:use_table:price_basis=producers:full_published_table=true:resolved_workbook_member_required=true",
    ),
    "bea_inventory_stock_control" => Dict(
        "nipa_t50805b_inventory_stock" =>
            "BEA:NIPA:TableName=T50805B:Frequency=Q:Year=2025,2026:full_published_line_universe=true:history_through=2026Q3:unit=millions_current_dollars_at_respective_end_of_quarter_prices:stock=true:SAAR=false",
    ),
    "bea_nipa_expenditure_history" => Dict(
        "nipa_t10105_l1_nominal_gdp" =>
            "BEA:NIPA:TableName=T10105:Frequency=Q:Year=X:LineNumber=1:history_through=2026Q3:SAAR=true",
        "nipa_t10105_l2_nominal_pce" =>
            "BEA:NIPA:TableName=T10105:Frequency=Q:Year=X:LineNumber=2:history_through=2026Q3:SAAR=true",
        "nipa_t10105_l7_nominal_gpdi" =>
            "BEA:NIPA:TableName=T10105:Frequency=Q:Year=X:LineNumber=7:history_through=2026Q3:SAAR=true",
        "nipa_t10105_l8_nominal_fixed_investment" =>
            "BEA:NIPA:TableName=T10105:Frequency=Q:Year=X:LineNumber=8:history_through=2026Q3:SAAR=true",
        "nipa_t10105_l14_nominal_inventory_investment" =>
            "BEA:NIPA:TableName=T10105:Frequency=Q:Year=X:LineNumber=14:history_through=2026Q3:SAAR=true:signed_flow=true",
        "nipa_t10105_l16_nominal_exports" =>
            "BEA:NIPA:TableName=T10105:Frequency=Q:Year=X:LineNumber=16:history_through=2026Q3:SAAR=true",
        "nipa_t10105_l19_nominal_imports" =>
            "BEA:NIPA:TableName=T10105:Frequency=Q:Year=X:LineNumber=19:history_through=2026Q3:SAAR=true",
        "nipa_t10105_l22_nominal_government" =>
            "BEA:NIPA:TableName=T10105:Frequency=Q:Year=X:LineNumber=22:history_through=2026Q3:SAAR=true",
        "nipa_t10106_l1_real_gdp" =>
            "BEA:NIPA:TableName=T10106:Frequency=Q:Year=X:LineNumber=1:history_through=2026Q3:SAAR=true:chained_dollars=true",
        "nipa_t10106_l2_real_pce" =>
            "BEA:NIPA:TableName=T10106:Frequency=Q:Year=X:LineNumber=2:history_through=2026Q3:SAAR=true:chained_dollars=true",
        "nipa_t10106_l8_real_fixed_investment" =>
            "BEA:NIPA:TableName=T10106:Frequency=Q:Year=X:LineNumber=8:history_through=2026Q3:SAAR=true:chained_dollars=true",
        "nipa_t10106_l16_real_exports" =>
            "BEA:NIPA:TableName=T10106:Frequency=Q:Year=X:LineNumber=16:history_through=2026Q3:SAAR=true:chained_dollars=true",
        "nipa_t10106_l19_real_imports" =>
            "BEA:NIPA:TableName=T10106:Frequency=Q:Year=X:LineNumber=19:history_through=2026Q3:SAAR=true:chained_dollars=true",
        "nipa_t10106_l22_real_government" =>
            "BEA:NIPA:TableName=T10106:Frequency=Q:Year=X:LineNumber=22:history_through=2026Q3:SAAR=true:chained_dollars=true",
    ),
    "bea_nipa_income_fiscal_structural" => Dict(
        "nipa_t11000_income_full" =>
            "BEA:NIPA:TableName=T11000:Frequency=A:Year=2024:LineNumber=ALL:full_published_table=true:required_lines=2,3,6",
        "nipa_t11200_national_income_full" =>
            "BEA:NIPA:TableName=T11200:Frequency=A:Year=2024:LineNumber=ALL:full_published_table=true",
        "nipa_t11400_gross_domestic_income_full" =>
            "BEA:NIPA:TableName=T11400:Frequency=A:Year=2024:LineNumber=ALL:full_published_table=true",
        "nipa_t20100_household" =>
            "BEA:NIPA:TableName=T20100:Frequency=A:Year=2024:LineNumber=9,12,13,17",
        "nipa_t30100_government_full" =>
            "BEA:NIPA:TableName=T30100:Frequency=A:Year=2024:LineNumber=ALL:full_published_table=true:required_lines=3,5,27,43",
        "nipa_t30200_federal_government_full" =>
            "BEA:NIPA:TableName=T30200:Frequency=A:Year=2024:LineNumber=ALL:full_published_table=true",
        "nipa_t30300_state_local_government_full" =>
            "BEA:NIPA:TableName=T30300:Frequency=A:Year=2024:LineNumber=ALL:full_published_table=true",
        "nipa_t30600_social_contributions" =>
            "BEA:NIPA:TableName=T30600:Frequency=A:Year=2024:LineNumber=20",
        "nipa_t31200_benefits" =>
            "BEA:NIPA:TableName=T31200:Frequency=A:Year=2024:LineNumber=5,7",
        "nipa_t51100_capital_taxes" =>
            "BEA:NIPA:TableName=T51100:Frequency=A:Year=2024:LineNumber=19,20",
        "nipa_t71100_interest" =>
            "BEA:NIPA:TableName=T71100:Frequency=A:Year=2024:LineNumber=7,8",
        "nipa_t10103_fixed_investment_backcast" =>
            "BEA:NIPA:TableName=T10103:Frequency=Q:Year=X:LineNumber=8:quantity_index_history_through=2006Q4",
        "pio_monthly_wages" =>
            "BEA:NIPA:TableName=T20600:Frequency=M:Year=X:LineNumber=3:SeriesCode=A034RC:history_start=1959M01:history_end=2026M09:unit=millions_of_dollars:SAAR=true:wages_and_salaries",
    ),
    "bea_nipa_tier1" => Dict(
        "nipa_t10105_nominal_gdp" =>
            "BEA:NIPA:2026Q3_ADVANCE:TableName=T10105:Frequency=Q:Year=X:LineNumber=1:SeriesCode=A191RC:history_through=2026Q3:SAAR=true",
        "nipa_t10106_real_gdp" =>
            "BEA:NIPA:2026Q3_ADVANCE:TableName=T10106:Frequency=Q:Year=X:LineNumber=1:SeriesCode=A191RX:history_through=2026Q3:SAAR=true",
        "nipa_t10109_gdp_deflator" =>
            "BEA:NIPA:2026Q3_ADVANCE:TableName=T10109:Frequency=Q:Year=X:LineNumber=1:SeriesCode=A191RD:history_through=2026Q3:index=true",
        "nipa_t20304_core_pce_price" =>
            "BEA:NIPA:2026Q3_ADVANCE:TableName=T20304:Frequency=Q:Year=X:LineNumber=25:SeriesCode=DPCCRG:history_through=2026Q3:index=true",
        "nipa_t20304_pce_price" =>
            "BEA:NIPA:2026Q3_ADVANCE:TableName=T20304:Frequency=Q:Year=X:LineNumber=1:SeriesCode=DPCERG:history_through=2026Q3:index=true",
    ),
    "bls_cps_structural" => Dict(
        "cps_employed" =>
            "BLS:CPS:SeriesID=LNU02000000:Frequency=M:NSA=true:history_as_known_at_receipt_through=2026-09:historical_first_states_not_claimed=true",
        "cps_inactive" =>
            "BLS:CPS:SeriesID=LNU05000000:Frequency=M:NSA=true:history_as_known_at_receipt_through=2026-09:historical_first_states_not_claimed=true",
        "cps_labor_force" =>
            "BLS:CPS:SeriesID=LNU01000000:Frequency=M:NSA=true:history_as_known_at_receipt_through=2026-09:historical_first_states_not_claimed=true",
        "cps_population" =>
            "BLS:CPS:SeriesID=LNU00000000:Frequency=M:NSA=true:history_as_known_at_receipt_through=2026-09:historical_first_states_not_claimed=true",
        "cps_unemployed" =>
            "BLS:CPS:SeriesID=LNU03000000:Frequency=M:NSA=true:history_as_known_at_receipt_through=2026-09:historical_first_states_not_claimed=true",
        "cps_unemployment_rate" =>
            "BLS:CPS:SeriesID=LNS14000000:Frequency=M:SA=true:history_as_known_at_receipt_through=2026-09:seasonal_factor_vintage_as_known_at_receipt=true:historical_first_states_not_claimed=true",
    ),
    "bls_employment_tier1" => Dict(
        "ces_total_nonfarm_payroll" =>
            "BLS:CES:SeriesID=CES0000000001:Frequency=M:SA=true:2026-09_EmploymentSituation:first_published_2026-09_value_and_release_history_snapshot=true:historical_first_states_not_claimed=true",
        "cps_unemployment_rate_target" =>
            "BLS:CPS:SeriesID=LNS14000000:Frequency=M:SA=true:2026-09_EmploymentSituation:first_published_2026-09_value_and_release_history_snapshot=true:seasonal_factor_vintage_as_released=true:historical_first_states_not_claimed=true",
        "employment_situation_release_bundle" =>
            "BLS:EmploymentSituation:ReferencePeriod=2026-09:release_news_file_and_exact_CES_CPS_machine_tables=true",
    ),
    "bls_qcew_structural" => Dict(
        "qcew_2022_annual_national" =>
            "BLS:QCEW:Year=2022:Frequency=A:Area=US000:full_national_file=true:required_fields=own_code,industry_code,annual_avg_estabs,annual_avg_emplvl,total_annual_wages",
        "qcew_2024_annual_national" =>
            "BLS:QCEW:Year=2024:Frequency=A:Area=US000:full_national_file=true:required_fields=own_code,industry_code,annual_avg_estabs,annual_avg_emplvl,total_annual_wages",
        "qcew_2026q1_quarterly" =>
            "BLS:QCEW:ReferencePeriod=2026Q1:Frequency=Q:Area=US000:national_release_and_revision_metadata=true",
    ),
    "census_aies_inventory_allocation" => Dict(
        "aies00inv_2023_economy_wide" =>
            "CENSUS:AIES:Year=2023:archive=AIES00INV.zip:member=AIES00INV.dat:delimiter=pipe:Geography=0100000US:NAICS_vintage=2017:required_fields=NAICS,INDLEVEL,YEAR,RCPT_TOT_VAL,RCPT_TOT_VAL_F,INV_E_TOT_DVAL,INV_E_TOT_DVAL_F,RCPT_TOT_CV,RCPT_TOT_CV_F,INV_E_TOT_CV,INV_E_TOT_CV_F",
        "aies31inv_2023_manufacturing_valuation" =>
            "CENSUS:AIES:Year=2023:archive=AIES31INV.zip:member=AIES31INV.dat:delimiter=pipe:Geography=0100000US:NAICS_vintage=2017:required_fields=NAICS,INDLEVEL,YEAR,INV_E_TOT_DVAL,INV_E_TOT_DVAL_F,INV_E_LIFO_VAL,INV_E_LIFO_VAL_F,INV_E_LIFO_RSV_VAL,INV_E_LIFO_RSV_VAL_F,INV_E_TOT_CV,INV_E_TOT_CV_F,INV_E_LIFO_CV,INV_E_LIFO_CV_F,INV_E_LIFO_RSV_CV,INV_E_LIFO_RSV_CV_F",
        "aies42inv_2023_wholesale_valuation" =>
            "CENSUS:AIES:Year=2023:archive=AIES42INV.zip:member=AIES42INV.dat:delimiter=pipe:Geography=0100000US:NAICS_vintage=2017:required_fields=NAICS,INDLEVEL,YEAR,INV_E_TOT_DVAL,INV_E_TOT_DVAL_F,INV_E_LIFO_VAL,INV_E_LIFO_VAL_F,INV_E_LIFO_RSV_VAL,INV_E_LIFO_RSV_VAL_F,INV_E_TOT_CV,INV_E_TOT_CV_F,INV_E_LIFO_CV,INV_E_LIFO_CV_F,INV_E_LIFO_RSV_CV,INV_E_LIFO_RSV_CV_F",
        "aies44inv_2023_retail_valuation" =>
            "CENSUS:AIES:Year=2023:archive=AIES44INV.zip:member=AIES44INV.dat:delimiter=pipe:Geography=0100000US:NAICS_vintage=2017:required_fields=NAICS,INDLEVEL,YEAR,INV_E_TOT_DVAL,INV_E_TOT_DVAL_F,INV_E_LIFO_VAL,INV_E_LIFO_VAL_F,INV_E_LIFO_RSV_VAL,INV_E_LIFO_RSV_VAL_F,INV_E_TOT_CV,INV_E_TOT_CV_F,INV_E_LIFO_CV,INV_E_LIFO_CV_F,INV_E_LIFO_RSV_CV,INV_E_LIFO_RSV_CV_F",
        "aies51inv_2023_information_stages" =>
            "CENSUS:AIES:Year=2023:archive=AIES51INV.zip:member=AIES51INV.dat:delimiter=pipe:Geography=0100000US:NAICS_vintage=2017:required_fields=NAICS,INDLEVEL,YEAR,INV_E_TOT_DVAL,INV_E_TOT_DVAL_F,INV_E_FIN_VAL,INV_E_FIN_VAL_F,INV_E_WIP_VAL,INV_E_WIP_VAL_F,INV_E_MAT_VAL,INV_E_MAT_VAL_F,INV_E_TOT_CV,INV_E_TOT_CV_F,INV_E_FIN_CV,INV_E_FIN_CV_F,INV_E_WIP_CV,INV_E_WIP_CV_F,INV_E_MAT_CV,INV_E_MAT_CV_F",
    ),
    "census_m3_inventory_stages" => Dict(
        "m3_2026_08_stage_table" =>
            "CENSUS:M3:ReferencePeriod=2026-08:full_report:Table=6:inventories_by_stage_of_fabrication:materials_and_supplies,work_in_process,finished_goods,total:SA_and_valuation_metadata_required=true",
        "m3_2026_09_advance_total" =>
            "CENSUS:M3:ReferencePeriod=2026-09:advance_report:total_manufacturing_inventories:SA_and_valuation_metadata_required=true",
    ),
    "census_mrts_inventory_stock" => Dict(
        "mrts_2026_08_inventory" =>
            "CENSUS:MRTS:ReferencePeriod=2026-08:member=mrtsinv92-present.xlsx:Geography=US:stock_time=end_of_month:published_unit=millions_current_dollars:valuation=not_adjusted_for_price_changes:adjustment_states=SA,NSA:full_published_kind_of_business_rows=true:inventory_and_inventory_sales_ratio=true",
    ),
    "census_mwts_inventory_stock" => Dict(
        "mwts_2026_08_adjusted_inventory" =>
            "CENSUS:MWTS:ReferencePeriod=2026-08:member=timeseries1.xlsx:Geography=US:stock_time=end_of_month:published_unit=millions_current_dollars:valuation=not_adjusted_for_price_changes:adjustment_state=seasonally_and_trading_day_adjusted:merchant_wholesalers_excluding_manufacturers_sales_branches_and_offices=true:full_published_kind_of_business_rows=true:inventory_and_inventory_sales_ratio=true",
        "mwts_2026_08_not_adjusted_inventory" =>
            "CENSUS:MWTS:ReferencePeriod=2026-08:member=timeseries2.xlsx:Geography=US:stock_time=end_of_month:published_unit=millions_current_dollars:valuation=not_adjusted_for_price_changes:adjustment_state=not_adjusted:merchant_wholesalers_excluding_manufacturers_sales_branches_and_offices=true:full_published_kind_of_business_rows=true:inventory_and_inventory_sales_ratio=true",
    ),
    "census_susb_structural" => Dict(
        "susb_employer_enterprises" =>
            "CENSUS:SUSB:Year=2022:Geography=US:STATE=00:ENTRSIZE=ALL_PUBLISHED_CODES:6digit_NAICS_full_file=true:required_fields=NAICS,ENTRSIZE,FIRM,ESTB,EMPL:NAICS_vintage=2017",
    ),
    "classification_maps" => Dict(
        "bea_summary_codes" =>
            "BEA:InputOutput:Year=2024:summary_industry_and_commodity_code_lists:71_source_industries,71_source_commodities,Other,Used",
        "bea_industry_commodity_naics_concordance" =>
            "BEA:InputOutputClassification:member=BEA-Industry-and-Commodity-Codes-and-NAICS-Concordance.xlsx:publication_path=2023-10:full_published_industry_and_commodity_code_to_NAICS_definitions=true",
        "beforeit_bea71_model_bridge" =>
            "BEFOREIT:repository:scripts/us/bea71.toml:sha256=2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f:71_to_68_retail_Other_Used_QCEW_SUSB_fixed_asset_concordance",
        "naics_2017" => "CENSUS:NAICS:2017:official_structure",
        "naics_2017_to_2022" =>
            "CENSUS:NAICS:2017_to_2022:official_concordance",
        "naics_2022" => "CENSUS:NAICS:2022:official_structure",
    ),
    "frb_z1_structural" => Dict(
        "z1_2026q2_data_bundle" =>
            "FRB:Z1:Release=2026Q2:complete_release_CSV_bundle=true",
        "z1_2026q2_series_dictionary" =>
            "FRB:Z1:Release=2026Q2:matching_series_dictionary=true",
        "z1_2026q2_code_changes_table_map" =>
            "FRB:Z1:Release=2026Q2:code_changes_and_table_mapping=true",
        "z1_fl104000005_firm_cash" =>
            "FRB:Z1:Release=2026Q2:Series=FL104000005.Q:Frequency=Q:stock_level=true:NSA=true:FRED_crosscheck=NCBCDTQ027S",
        "z1_fl114000005_noncorporate_cash" =>
            "FRB:Z1:Release=2026Q2:Series=FL114000005.Q:Frequency=Q:stock_level=true:NSA=true:FRED_crosscheck=NNBCDAQ027S",
        "z1_fl144104005_firm_debt" =>
            "FRB:Z1:Release=2026Q2:Series=FL144104005.Q:Frequency=Q:stock_level=true:NSA=true:FRED_crosscheck=BOGZ1FL144104005Q",
        "z1_fl154000005_household_cash" =>
            "FRB:Z1:Release=2026Q2:Series=FL154000005.Q:Frequency=Q:stock_level=true:NSA=true:FRED_crosscheck=HNOCDAQ027S",
        "z1_fl214104005_state_local_debt" =>
            "FRB:Z1:Release=2026Q2:Series=FL214104005.Q:Frequency=Q:stock_level=true:NSA=true:FRED_crosscheck=SLGTCMDODNS",
        "z1_fl314104005_federal_debt" =>
            "FRB:Z1:Release=2026Q2:Series=FL314104005.Q:Frequency=Q:stock_level=true:NSA=true:FRED_crosscheck=FGTCMDODNS",
        "z1_fl704190005_depository_liabilities" =>
            "FRB:Z1:Release=2026Q2:Series=FL704190005.Q:Frequency=Q:stock_level=true:NSA=true:FRED_crosscheck=BOGZ1FL704190005Q",
        "z1_fl704194005_depository_liabilities_equity" =>
            "FRB:Z1:Release=2026Q2:Series=FL704194005.Q:Frequency=Q:stock_level=true:NSA=true:FRED_crosscheck=BOGZ1FL704194005Q",
    ),
    "fred_policy_rate_history" => Dict(
        "fredfunds_monthly_calibration_history" =>
            "FRED:SeriesID=FEDFUNDS:Frequency=M:ObservationStart=1996-10-01:ObservationEnd=2026-09-30:VintageDate=2026-10-30:Units=Percent:AggregationMethod=Average:exact_series_metadata_and_observations=true",
    ),
    "frbny_effr_tier1" => Dict(
        "effr_daily_history" =>
            "FRBNY:EFFR:Frequency=D:daily_rate_and_volume_history_through=2026-10-29:percent_level=true",
        "effr_first_state_manifest" =>
            "FRBNY:EFFR:first_state_receipt_manifest:coverage=2026-08-07_to_2026-10-30:official_business_days_excluding=2026-09-07,2026-10-12",
        "effr_revision_manifest" =>
            "FRBNY:EFFR:same_day_revision_receipt_manifest:coverage=2026-08-07_to_2026-10-29:official_business_days_excluding=2026-09-07,2026-10-12",
    ),
    "usda_counts_structural" => Dict(
        "farms_and_land_in_farms" =>
            "USDA:NASS:FarmsAndLandInFarms:Report=2025_summary_containing_2024:ReferenceYear=2024:Geography=US:Series=number_of_farms:Unit=farms",
    ),
)

const REQUIRED_DEFAULT_CAPTURE_BY_REQUIREMENT = Dict(
    "bea_fixed_assets_structural" => "final_structural_pre_origin",
    "bea_gdpbyindustry_sector_accounts" => "final_structural_pre_origin",
    "bea_industry_io_structural" => "final_structural_pre_origin",
    "bea_industry_valuation_structural" => "slow_structural_pre_origin",
    "bea_inventory_stock_control" => "bea_gdp_2026q3_advance",
    "bea_nipa_expenditure_history" => "bea_gdp_2026q3_advance",
    "bea_nipa_income_fiscal_structural" => "final_structural_pre_origin",
    "bea_nipa_tier1" => "bea_gdp_2026q3_advance",
    "bls_cps_structural" => "final_structural_pre_origin",
    "bls_employment_tier1" => "bls_employment_situation_2026_09",
    "bls_qcew_structural" => "final_structural_pre_origin",
    "census_aies_inventory_allocation" => "final_structural_pre_origin",
    "census_m3_inventory_stages" => "census_m3_2026_08_full",
    "census_mrts_inventory_stock" => "census_mrts_inventory_2026_08",
    "census_mwts_inventory_stock" => "census_mwts_2026_08",
    "census_susb_structural" => "final_structural_pre_origin",
    "classification_maps" => "final_structural_pre_origin",
    "frb_z1_structural" => "frb_z1_2026q2",
    "fred_policy_rate_history" => "final_structural_pre_origin",
    "frbny_effr_tier1" => "frbny_effr_2026_10_29_first_state",
    "usda_counts_structural" => "final_structural_pre_origin",
)

const REQUIRED_CAPTURE_OVERRIDES_BY_REQUIREMENT = Dict(
    requirement_id => Dict{String, String}()
        for requirement_id in keys(REQUIRED_PROFILES_BY_REQUIREMENT)
)
REQUIRED_CAPTURE_OVERRIDES_BY_REQUIREMENT["census_m3_inventory_stages"] =
    Dict(
    "m3_2026_09_advance_total" => "census_m3_2026_09_advance",
)
REQUIRED_CAPTURE_OVERRIDES_BY_REQUIREMENT["bls_qcew_structural"] = Dict(
    "qcew_2026q1_quarterly" => "bls_qcew_2026q1",
)
REQUIRED_CAPTURE_OVERRIDES_BY_REQUIREMENT["frbny_effr_tier1"] = Dict(
    "effr_first_state_manifest" => "frbny_effr_daily_first_state",
    "effr_revision_manifest" => "frbny_effr_daily_revision_check",
)
const REQUIRED_COMPLETION_DATES_BY_REQUIREMENT = Dict(
    requirement_id => Dict{String, String}()
        for requirement_id in keys(REQUIRED_PROFILES_BY_REQUIREMENT)
)
REQUIRED_COMPLETION_DATES_BY_REQUIREMENT["frbny_effr_tier1"] = Dict(
    "effr_first_state_manifest" => "2026-10-30",
    "effr_revision_manifest" => "2026-10-29",
)
const REQUIRED_RECURRING_EXCLUDED_DATES = ["2026-09-07", "2026-10-12"]

const EXPECTED_FIXED_EVENTS = [
    (
        event_id = "bls_employment_situation_2026_07",
        source_id = "bls_employment_situation",
        requirement_ids = [
            "bls_cps_structural",
            "bls_employment_tier1",
        ],
        reference_period = "2026-07",
        official_schedule_locator =
            "https://www.bls.gov/schedule/news_release/empsit.htm",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-08-07T12:30:00Z",
        capture_not_before_utc = "2026-08-07T12:30:00Z",
        capture_deadline_utc = "2026-08-07T12:45:00Z",
        event_purpose = "capture_rehearsal",
        required_for_complete_origin = false,
    ),
    (
        event_id = "bls_qcew_2026q1",
        source_id = "bls_qcew",
        requirement_ids = ["bls_qcew_structural"],
        reference_period = "2026Q1",
        official_schedule_locator =
            "https://www.bls.gov/cew/release-calendar.htm",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-08-28T14:00:00Z",
        capture_not_before_utc = "2026-08-28T14:00:00Z",
        capture_deadline_utc = "2026-08-28T14:15:00Z",
        event_purpose = "latest_structural_release",
        required_for_complete_origin = true,
    ),
    (
        event_id = "bls_employment_situation_2026_08",
        source_id = "bls_employment_situation",
        requirement_ids = [
            "bls_cps_structural",
            "bls_employment_tier1",
        ],
        reference_period = "2026-08",
        official_schedule_locator =
            "https://www.bls.gov/schedule/news_release/empsit.htm",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-09-04T12:30:00Z",
        capture_not_before_utc = "2026-09-04T12:30:00Z",
        capture_deadline_utc = "2026-09-04T12:45:00Z",
        event_purpose = "capture_rehearsal",
        required_for_complete_origin = false,
    ),
    (
        event_id = "frb_z1_2026q2",
        source_id = "frb_z1",
        requirement_ids = ["frb_z1_structural"],
        reference_period = "2026Q2",
        official_schedule_locator =
            "https://www.federalreserve.gov/newsevents/2026-september.htm",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-09-11T16:00:00Z",
        capture_not_before_utc = "2026-09-11T16:00:00Z",
        capture_deadline_utc = "2026-09-11T16:15:00Z",
        event_purpose = "latest_structural_release",
        required_for_complete_origin = true,
    ),
    (
        event_id = "bea_annual_update_2026",
        source_id = "bea_annual_update_2026",
        requirement_ids = [
            "bea_fixed_assets_structural",
            "bea_gdpbyindustry_sector_accounts",
            "bea_industry_io_structural",
            "bea_industry_valuation_structural",
            "bea_nipa_expenditure_history",
            "bea_nipa_income_fiscal_structural",
            "bea_nipa_tier1",
        ],
        reference_period = "2026-annual-update",
        official_schedule_locator = "https://www.bea.gov/news/schedule",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-09-30T12:30:00Z",
        capture_not_before_utc = "2026-09-30T12:30:00Z",
        capture_deadline_utc = "2026-09-30T13:30:00Z",
        event_purpose = "annual_structure_and_history_refresh_rehearsal",
        required_for_complete_origin = false,
    ),
    (
        event_id = "bls_employment_situation_2026_09",
        source_id = "bls_employment_situation",
        requirement_ids = [
            "bls_cps_structural",
            "bls_employment_tier1",
        ],
        reference_period = "2026-09",
        official_schedule_locator =
            "https://www.bls.gov/schedule/news_release/empsit.htm",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-10-02T12:30:00Z",
        capture_not_before_utc = "2026-10-02T12:30:00Z",
        capture_deadline_utc = "2026-10-02T12:45:00Z",
        event_purpose = "latest_pre_origin_release",
        required_for_complete_origin = true,
    ),
    (
        event_id = "census_m3_2026_08_full",
        source_id = "census_m3",
        requirement_ids = ["census_m3_inventory_stages"],
        reference_period = "2026-08",
        official_schedule_locator =
            "https://www.census.gov/manufacturing/m3/release_schedule.html",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-10-02T14:00:00Z",
        capture_not_before_utc = "2026-10-02T14:00:00Z",
        capture_deadline_utc = "2026-10-02T14:15:00Z",
        event_purpose = "latest_inventory_stage_release",
        required_for_complete_origin = true,
    ),
    (
        event_id = "census_mwts_2026_08",
        source_id = "census_mwts",
        requirement_ids = ["census_mwts_inventory_stock"],
        reference_period = "2026-08",
        official_schedule_locator =
            "https://www.census.gov/wholesale/release_schedule.html",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-10-08T14:00:00Z",
        capture_not_before_utc = "2026-10-08T14:00:00Z",
        capture_deadline_utc = "2026-10-08T14:15:00Z",
        event_purpose = "latest_pre_origin_inventory_stock",
        required_for_complete_origin = true,
    ),
    (
        event_id = "census_mrts_inventory_2026_08",
        source_id = "census_mrts",
        requirement_ids = ["census_mrts_inventory_stock"],
        reference_period = "2026-08",
        official_schedule_locator =
            "https://www.census.gov/retail/release_schedule.html",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-10-15T14:00:00Z",
        capture_not_before_utc = "2026-10-15T14:00:00Z",
        capture_deadline_utc = "2026-10-15T14:15:00Z",
        event_purpose = "latest_pre_origin_inventory_stock",
        required_for_complete_origin = true,
    ),
    (
        event_id = "census_m3_2026_09_advance",
        source_id = "census_m3",
        requirement_ids = ["census_m3_inventory_stages"],
        reference_period = "2026-09",
        official_schedule_locator =
            "https://www.census.gov/manufacturing/m3/release_schedule.html",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-10-27T12:30:00Z",
        capture_not_before_utc = "2026-10-27T12:30:00Z",
        capture_deadline_utc = "2026-10-27T12:45:00Z",
        event_purpose = "last_eligible_manufacturing_total",
        required_for_complete_origin = true,
    ),
    (
        event_id = "bea_gdp_2026q3_advance",
        source_id = "bea_nipa_hmi7",
        requirement_ids = [
            "bea_inventory_stock_control",
            "bea_nipa_expenditure_history",
            "bea_nipa_income_fiscal_structural",
            "bea_nipa_tier1",
        ],
        reference_period = "2026Q3",
        official_schedule_locator = "https://www.bea.gov/news/schedule",
        timestamp_basis = "official_exact",
        scheduled_timestamp_utc = "2026-10-29T12:30:00Z",
        capture_not_before_utc = "2026-10-29T12:30:00Z",
        capture_deadline_utc = "2026-10-29T13:00:00Z",
        event_purpose = "trigger_release",
        required_for_complete_origin = true,
    ),
    (
        event_id = "frbny_effr_2026_10_29_first_state",
        source_id = "frbny_effr",
        requirement_ids = ["frbny_effr_tier1"],
        reference_period = "2026-10-29",
        official_schedule_locator =
            "https://www.newyorkfed.org/markets/reference-rates/effr",
        timestamp_basis = "official_approximate_window",
        scheduled_timestamp_utc = "2026-10-30T13:00:00Z",
        capture_not_before_utc = "2026-10-30T12:55:00Z",
        capture_deadline_utc = "2026-10-30T13:15:00Z",
        event_purpose = "last_eligible_daily_rate",
        required_for_complete_origin = true,
    ),
]

const EXPECTED_SNAPSHOT_CAMPAIGNS = [
    (
        campaign_id = "slow_structural_pre_origin",
        requirement_ids = [
            "bea_fixed_assets_structural",
            "bea_industry_valuation_structural",
            "bls_cps_structural",
            "census_aies_inventory_allocation",
            "census_susb_structural",
            "classification_maps",
            "usda_counts_structural",
        ],
        capture_not_before_utc = "2026-08-06T00:00:00Z",
        capture_deadline_utc = "2026-08-31T23:59:59Z",
        purpose = "early_rehearsal_and_exact_current_byte_capture",
    ),
    (
        campaign_id = "final_structural_pre_origin",
        requirement_ids = [
            "bea_fixed_assets_structural",
            "bea_gdpbyindustry_sector_accounts",
            "bea_industry_io_structural",
            "bea_inventory_stock_control",
            "bea_nipa_income_fiscal_structural",
            "bls_cps_structural",
            "bls_qcew_structural",
            "census_aies_inventory_allocation",
            "census_susb_structural",
            "classification_maps",
            "fred_policy_rate_history",
            "usda_counts_structural",
        ],
        capture_not_before_utc = "2026-10-29T13:30:00Z",
        capture_deadline_utc = "2026-10-30T13:45:00Z",
        purpose = "prove_final_latest_eligible_structural_bytes_before_origin",
    ),
]

struct ProspectiveContractV2ValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::ProspectiveContractV2ValidationError) =
    print(io, error.message)

fail(location, message) =
    throw(ProspectiveContractV2ValidationError("$location: $message"))

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    return value
end

function expect_array(value, location; allow_empty = true)
    value isa AbstractVector || fail(location, "must be an array")
    !allow_empty && isempty(value) && fail(location, "must not be empty")
    return value
end

function expect_exact_keys(value, expected_keys, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    actual == expected_keys ||
        fail(
        location,
        "must contain exactly $(join(sort!(collect(expected_keys)), ", "))",
    )
    return table
end

function expect_string(value, location; allow_empty = false)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    !allow_empty && isempty(text) && fail(location, "must not be empty")
    return text
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function expect_int(value, location; minimum = nothing)
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    number = Int(value)
    minimum !== nothing && number < minimum &&
        fail(location, "must be at least $minimum")
    return number
end

function expect_identifier(value, location)
    text = expect_string(value, location)
    occursin(IDENTIFIER_PATTERN, text) ||
        fail(location, "must be a stable identifier")
    return text
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be a lowercase SHA-256")
    return text
end

function expect_timestamp(value, location)
    text = expect_string(value, location)
    occursin(TIMESTAMP_PATTERN, text) ||
        fail(location, "must use RFC3339 UTC at second precision")
    parsed = try
        DateTime(chop(text; tail = 1), RFC3339_SECONDS_FORMAT)
    catch
        fail(location, "is not a valid timestamp")
    end
    Dates.format(parsed, RFC3339_SECONDS_FORMAT) * "Z" == text ||
        fail(location, "is not canonical")
    return parsed
end

function expect_string_array(value, location; allow_empty = true)
    array = expect_array(value, location; allow_empty)
    result = [
        expect_string(entry, "$location[$index]")
            for (index, entry) in enumerate(array)
    ]
    length(result) == length(unique(result)) ||
        fail(location, "must not contain duplicates")
    issorted(result) || fail(location, "must be sorted")
    return result
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
    elseif value isa AbstractVector || value isa Tuple
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
    else
        fail("canonicalization", "unsupported value of type $(typeof(value))")
    end
    return io
end

function canonical_sha256(value)
    io = IOBuffer()
    _canonical_write(io, value)
    return bytes2hex(sha256(take!(io)))
end

function contract_sha256(contract)
    copy = deepcopy(expect_table(contract, "contract"))
    artifact =
        expect_table(get(copy, "artifact", nothing), "contract.artifact")
    pop!(artifact, "content_sha256", nothing)
    return canonical_sha256(copy)
end

function stamp_contract_sha256!(contract)
    artifact =
        expect_table(expect_table(contract, "contract")["artifact"], "artifact")
    artifact["content_sha256"] = contract_sha256(contract)
    return contract
end

function validate_shared_fail_closed(contract)
    artifact =
        expect_exact_keys(contract["artifact"], ARTIFACT_KEYS, "contract.artifact")
    artifact["schema_version"] == CONTRACT_SCHEMA ||
        fail("contract.artifact.schema_version", "unsupported schema")
    artifact["contract_id"] == CONTRACT_ID ||
        fail("contract.artifact.contract_id", "unsupported contract")
    artifact["status"] == "DRAFT_UNAPPROVED_FAIL_CLOSED" ||
        fail("contract.artifact.status", "must remain fail closed")
    artifact["as_of_date"] == "2026-08-06" ||
        fail("contract.artifact.as_of_date", "unexpected audit date")
    artifact["protocol_sha256"] == PROTOCOL_SHA256 ||
        fail("contract.artifact.protocol_sha256", "protocol pin mismatch")
    artifact["tier1_targets_sha256"] == TIER1_TARGETS_SHA256 ||
        fail("contract.artifact.tier1_targets_sha256", "target pin mismatch")
    artifact["canonicalization"] == CANONICALIZATION ||
        fail("contract.artifact.canonicalization", "canonicalization mismatch")
    artifact["digest_algorithm"] == "sha256" ||
        fail("contract.artifact.digest_algorithm", "must be sha256")
    expect_hash(artifact["content_sha256"], "contract.artifact.content_sha256") ==
        contract_sha256(contract) ||
        fail("contract.artifact.content_sha256", "content digest mismatch")

    origin =
        expect_exact_keys(contract["origin"], ORIGIN_KEYS, "contract.origin")
    origin["origin_id"] == "origin.2026q3.prospective-capture-candidate.v2" ||
        fail("contract.origin.origin_id", "origin ID mismatch")
    origin["reference_quarter"] == "2026Q3" ||
        fail("contract.origin.reference_quarter", "quarter mismatch")
    origin["origin_timestamp_utc"] == ORIGIN_TIMESTAMP ||
        fail("contract.origin.origin_timestamp_utc", "cutoff mismatch")
    expect_timestamp(origin["origin_timestamp_utc"], "contract.origin")
    origin["origin_rule"] ==
        "FIRST_BUSINESS_DAY_AFTER_BEA_ADVANCE_AT_10:00_AMERICA/NEW_YORK" ||
        fail("contract.origin.origin_rule", "origin rule changed")
    origin["admission_status"] == "PLANNED_NOT_CAPTURED_NOT_ADMITTED" ||
        fail("contract.origin.admission_status", "must remain not admitted")
    for field in (
            "inventory_mutation_authorized",
            "origin_admissible",
            "ready",
            "accuracy_evaluation_allowed",
        )
        !expect_bool(origin[field], "contract.origin.$field") ||
            fail("contract.origin.$field", "must remain false")
    end

    policy = expect_exact_keys(
        contract["availability_policy"],
        AVAILABILITY_KEYS,
        "contract.availability_policy",
    )
    expected_policy_strings = Dict(
        "policy_version" => "availability-upper-bound.v1-draft",
        "eligibility_time_field" => "availability_upper_bound_utc",
        "eligible_basis" => "VERIFIED_PRE_ORIGIN_RECEIPT_COMPLETION",
        "availability_upper_bound_semantics" =>
            "conservative_latest_time_by_which_exact_bytes_are_proven_available_not_an_asserted_original_publication_time",
    )
    for (field, expected) in expected_policy_strings
        expect_string(
            policy[field],
            "contract.availability_policy.$field",
        ) == expected ||
            fail("contract.availability_policy.$field", "policy value changed")
    end
    for field in (
            "upper_bound_must_equal_receipt_completed_at_utc",
            "upper_bound_must_precede_origin",
            "unknown_original_release_time_allowed_for_prospective_receipt",
            "official_release_timestamp_preserved_when_evidenced",
            "raw_sha256_required",
            "receipt_sha256_required",
            "durable_storage_receipt_required",
        )
        expect_bool(policy[field], "contract.availability_policy.$field") ||
            fail("contract.availability_policy.$field", "must remain true")
    end
    for field in (
            "post_origin_receipt_eligible",
            "historical_backfill_eligible",
            "unverified_receipt_eligible",
            "schedule_or_route_only_eligible",
        )
        !expect_bool(policy[field], "contract.availability_policy.$field") ||
            fail("contract.availability_policy.$field", "must remain false")
    end

    resolution_policy = expect_exact_keys(
        contract["selector_resolution_policy"],
        SELECTOR_RESOLUTION_POLICY_KEYS,
        "contract.selector_resolution_policy",
    )
    expected_resolution_strings = Dict(
        "policy_version" => "resolved-selector-evidence.v3-draft",
        "resolution_schema" => SELECTOR_RESOLUTION_SCHEMA,
        "planned_selector_field" => "selector",
        "resolved_selector_hash_field" => "selector_evidence_sha256",
        "not_applicable_literal" => "NOT_APPLICABLE",
        "unknown_release_timestamp_literal" => "UNKNOWN_NOT_ASSERTED",
    )
    for (field, expected) in expected_resolution_strings
        expect_string(
            resolution_policy[field],
            "contract.selector_resolution_policy.$field",
        ) == expected ||
            fail(
            "contract.selector_resolution_policy.$field",
            "policy value changed",
        )
    end
    expect_string_array(
        resolution_policy["resolved_identity_must_not_contain_tokens"],
        "contract.selector_resolution_policy.resolved_identity_must_not_contain_tokens";
        allow_empty = false,
    ) == ["ALL", "LATEST", "PINNED", "SAME", "THROUGH"] ||
        fail(
        "contract.selector_resolution_policy.resolved_identity_must_not_contain_tokens",
        "unresolved-token policy changed",
    )
    for field in (
            "candidate_catalog_required",
            "candidate_rank_must_equal_one",
            "raw_receipt_hash_binding_required",
            "resolved_dimensions_bind_every_selector_key",
            "dynamic_set_resolutions_required",
            "official_artifact_host_allowlist_enforced",
            "official_artifact_source_affinity_enforced",
            "verifier_attestation_required_for_completion",
            "shape_complete_is_not_requirement_complete",
        )
        expect_bool(
            resolution_policy[field],
            "contract.selector_resolution_policy.$field",
        ) ||
            fail(
            "contract.selector_resolution_policy.$field",
            "must remain true",
        )
    end

    verifier = expect_exact_keys(
        contract["verifier"],
        VERIFIER_KEYS,
        "contract.verifier",
    )
    verifier["implementation_status"] == "NOT_IMPLEMENTED_FAIL_CLOSED" ||
        fail(
        "contract.verifier.implementation_status",
        "must remain unimplemented",
    )
    verifier["implementation_artifact_sha256"] == "unavailable" ||
        fail(
        "contract.verifier.implementation_artifact_sha256",
        "must remain unavailable",
    )
    verifier["receipt_artifact_verification_status"] == "NOT_VERIFIED" ||
        fail(
        "contract.verifier.receipt_artifact_verification_status",
        "must remain unverified",
    )
    for field in (
            "activation_requires_implementation",
            "status_is_independent_of_requirements_approval",
        )
        expect_bool(verifier[field], "contract.verifier.$field") ||
            fail("contract.verifier.$field", "must remain true")
    end

    approval = expect_exact_keys(
        contract["approval"],
        APPROVAL_KEYS,
        "contract.approval",
    )
    approval["artifact_approval_status"] == "DRAFT_UNAPPROVED" ||
        fail(
        "contract.approval.artifact_approval_status",
        "must remain unapproved",
    )
    for field in ("model_owner", "independent_validator")
        approval[field] == "unassigned" ||
            fail("contract.approval.$field", "must remain unassigned")
    end
    for field in ("model_owner_signature", "independent_validator_signature")
        approval[field] == "unsigned" ||
            fail("contract.approval.$field", "must remain unsigned")
    end
    for field in (
            "activation_requires_approval",
            "status_is_independent_of_verifier_implementation",
        )
        expect_bool(approval[field], "contract.approval.$field") ||
            fail("contract.approval.$field", "must remain true")
    end

    retention = expect_exact_keys(
        contract["retention"],
        RETENTION_KEYS,
        "contract.retention",
    )
    retention["policy_version"] ==
        "prospective-durable-retention.v1-draft" ||
        fail("contract.retention.policy_version", "policy version changed")
    retention["minimum_retain_until_utc"] == MINIMUM_RETAIN_UNTIL ||
        fail(
        "contract.retention.minimum_retain_until_utc",
        "retention boundary changed",
    )
    expect_timestamp(
        retention["minimum_retain_until_utc"],
        "contract.retention.minimum_retain_until_utc",
    )
    expect_int(
        retention["origin_plus_mature_truth_months"],
        "contract.retention.origin_plus_mature_truth_months";
        minimum = 1,
    ) == 60 ||
        fail(
        "contract.retention.origin_plus_mature_truth_months",
        "must remain 60",
    )
    expect_int(
        retention["minimum_durable_copy_count"],
        "contract.retention.minimum_durable_copy_count";
        minimum = 2,
    ) == 2 ||
        fail(
        "contract.retention.minimum_durable_copy_count",
        "must require two copies",
    )
    for field in (
            "content_addressed_storage_required",
            "write_once_or_versioned_storage_required",
            "raw_and_receipt_bytes_co_retained",
            "hash_manifest_required",
            "external_timestamp_receipt_required",
        )
        expect_bool(retention[field], "contract.retention.$field") ||
            fail("contract.retention.$field", "must remain true")
    end
    for field in (
            "github_actions_artifact_only_allowed",
            "short_retention_artifact_is_origin_evidence",
        )
        !expect_bool(retention[field], "contract.retention.$field") ||
            fail("contract.retention.$field", "must remain false")
    end
    return nothing
end

function validate_requirements(contract)
    rows = expect_array(
        contract["requirements"],
        "contract.requirements";
        allow_empty = false,
    )
    length(rows) == length(REQUIRED_REQUIREMENTS) ||
        fail(
        "contract.requirements",
        "must contain exactly $(length(REQUIRED_REQUIREMENTS)) requirements",
    )
    ids = String[]
    targets = String[]
    for (index, row) in enumerate(rows)
        location = "contract.requirements[$index]"
        item = expect_exact_keys(row, REQUIREMENT_KEYS, location)
        requirement_id =
            expect_identifier(item["requirement_id"], "$location.requirement_id")
        push!(ids, requirement_id)
        haskey(REQUIRED_REQUIREMENTS, requirement_id) ||
            fail(location, "unknown requirement")
        expected = REQUIRED_REQUIREMENTS[requirement_id]
        for field in (
                "block_kind",
                "source_id",
                "source_family",
                "source_locator",
                "acquisition_mode",
            )
            item[field] == getproperty(expected, Symbol(field)) ||
                fail("$location.$field", "does not match the pinned route")
        end
        target_ids =
            expect_string_array(item["target_ids"], "$location.target_ids")
        target_ids == expected.target_ids ||
            fail("$location.target_ids", "target selector mismatch")
        append!(targets, target_ids)
        expect_bool(
            item["required_for_complete_origin"],
            "$location.required_for_complete_origin",
        ) ||
            fail("$location.required_for_complete_origin", "must equal true")
        item["completion_rule"] == "ALL_PROFILES_VERIFIED" ||
            fail("$location.completion_rule", "must require all profiles")
        item["default_capture_id"] ==
            REQUIRED_DEFAULT_CAPTURE_BY_REQUIREMENT[requirement_id] ||
            fail(
            "$location.default_capture_id",
            "does not match the required latest capture",
        )
        capture_overrides = Dict(
            String(key) => expect_identifier(
                    value,
                    "$location.profile_capture_overrides.$key",
                ) for (key, value) in
                expect_table(
                    item["profile_capture_overrides"],
                    "$location.profile_capture_overrides",
                )
        )
        capture_overrides ==
            REQUIRED_CAPTURE_OVERRIDES_BY_REQUIREMENT[requirement_id] ||
            fail(
            "$location.profile_capture_overrides",
            "does not match the profile-specific capture contract",
        )
        completion_dates = Dict(
            String(key) => expect_string(
                    value,
                    "$location.profile_completion_dates.$key",
                ) for (key, value) in
                expect_table(
                    item["profile_completion_dates"],
                    "$location.profile_completion_dates",
                )
        )
        all(
            occursin(DATE_PATTERN, value)
                for value in values(completion_dates)
        ) ||
            fail(
            "$location.profile_completion_dates",
            "must contain YYYY-MM-DD dates",
        )
        completion_dates ==
            REQUIRED_COMPLETION_DATES_BY_REQUIREMENT[requirement_id] ||
            fail(
            "$location.profile_completion_dates",
            "does not match the profile coverage boundary",
        )
        profiles =
            expect_table(item["artifact_profiles"], "$location.artifact_profiles")
        actual_profiles = Dict(
            String(key) => expect_string(
                    value,
                    "$location.artifact_profiles.$key",
                ) for (key, value) in profiles
        )
        expected_profiles = REQUIRED_PROFILES_BY_REQUIREMENT[requirement_id]
        actual_profiles == expected_profiles ||
            fail("$location.artifact_profiles", "selector profile set mismatch")
        expect_int(
            item["required_profile_count"],
            "$location.required_profile_count";
            minimum = 1,
        ) == length(expected_profiles) ||
            fail("$location.required_profile_count", "profile count mismatch")
        item["evidence_status"] == "MISSING_NOT_CAPTURED" ||
            fail("$location.evidence_status", "must remain missing")
        expect_int(
            item["registered_raw_artifact_count"],
            "$location.registered_raw_artifact_count";
            minimum = 0,
        ) == 0 ||
            fail("$location.registered_raw_artifact_count", "must remain zero")
    end
    issorted(ids) || fail("contract.requirements", "must be sorted")
    Set(ids) == Set(keys(REQUIRED_REQUIREMENTS)) ||
        fail("contract.requirements", "requirement set mismatch")
    length(ids) == length(unique(ids)) ||
        fail("contract.requirements", "contains duplicate IDs")
    Set(targets) == TIER1_TARGET_IDS ||
        fail("contract.requirements", "Tier-1 coverage mismatch")
    length(targets) == length(unique(targets)) ||
        fail("contract.requirements", "Tier-1 target assigned more than once")
    return Dict(ids[index] => rows[index] for index in eachindex(ids))
end

function event_tuple(item, location)
    scheduled = expect_timestamp(
        item["scheduled_timestamp_utc"],
        "$location.scheduled_timestamp_utc",
    )
    capture_start = expect_timestamp(
        item["capture_not_before_utc"],
        "$location.capture_not_before_utc",
    )
    deadline = expect_timestamp(
        item["capture_deadline_utc"],
        "$location.capture_deadline_utc",
    )
    capture_start <= scheduled <= deadline ||
        fail(location, "capture window must contain scheduled time")
    deadline < DateTime(2026, 10, 30, 14) ||
        fail(location, "capture deadline must precede origin")
    return (
        event_id = expect_identifier(item["event_id"], "$location.event_id"),
        source_id = expect_identifier(item["source_id"], "$location.source_id"),
        requirement_ids = expect_string_array(
            item["requirement_ids"],
            "$location.requirement_ids";
            allow_empty = false,
        ),
        reference_period =
            expect_string(item["reference_period"], "$location.reference_period"),
        official_schedule_locator = expect_string(
            item["official_schedule_locator"],
            "$location.official_schedule_locator",
        ),
        timestamp_basis =
            expect_string(item["timestamp_basis"], "$location.timestamp_basis"),
        scheduled_timestamp_utc = item["scheduled_timestamp_utc"],
        capture_not_before_utc = item["capture_not_before_utc"],
        capture_deadline_utc = item["capture_deadline_utc"],
        event_purpose =
            expect_string(item["event_purpose"], "$location.event_purpose"),
        required_for_complete_origin = expect_bool(
            item["required_for_complete_origin"],
            "$location.required_for_complete_origin",
        ),
    )
end

function validate_fixed_events(contract, requirements)
    rows =
        expect_array(contract["fixed_events"], "fixed_events"; allow_empty = false)
    length(rows) == length(EXPECTED_FIXED_EVENTS) ||
        fail("fixed_events", "must contain exactly 12 events")
    observed = NamedTuple[]
    for (index, row) in enumerate(rows)
        location = "fixed_events[$index]"
        item = expect_exact_keys(row, FIXED_EVENT_KEYS, location)
        tuple = event_tuple(item, location)
        all(haskey(requirements, id) for id in tuple.requirement_ids) ||
            fail("$location.requirement_ids", "contains unknown requirement")
        item["capture_status"] == "PLANNED_NOT_CAPTURED" ||
            fail("$location.capture_status", "must remain planned")
        item["immutable_receipt_status"] == "MISSING" ||
            fail("$location.immutable_receipt_status", "must remain missing")
        expect_int(item["receipt_count"], "$location.receipt_count"; minimum = 0) ==
            0 ||
            fail("$location.receipt_count", "must remain zero")
        !expect_bool(item["origin_eligible"], "$location.origin_eligible") ||
            fail("$location.origin_eligible", "must remain false")
        push!(observed, tuple)
    end
    observed == EXPECTED_FIXED_EVENTS ||
        fail("fixed_events", "does not match pinned v2 calendar")
    return rows
end

function validate_recurring_windows(contract, requirements)
    rows = expect_array(
        contract["recurring_windows"],
        "recurring_windows";
        allow_empty = false,
    )
    length(rows) == 2 ||
        fail("recurring_windows", "must retain exactly two EFFR windows")
    expected = [
        (
            window_id = "frbny_effr_daily_first_state",
            campaign_start_date = "2026-08-07",
            campaign_end_date = "2026-10-30",
            scheduled_time_utc = "13:00:00Z",
            capture_window_minutes = 15,
            business_day_rule =
                "NEW_YORK_FED_PUBLICATION_DAYS_REVALIDATE_OFFICIAL_HOLIDAYS",
            excluded_dates = REQUIRED_RECURRING_EXCLUDED_DATES,
            timestamp_basis = "official_approximate_window",
            evidence_role = "first_state_candidate",
            origin_day_completion_before_cutoff_required = true,
        ),
        (
            window_id = "frbny_effr_daily_revision_check",
            campaign_start_date = "2026-08-07",
            campaign_end_date = "2026-10-29",
            scheduled_time_utc = "18:30:00Z",
            capture_window_minutes = 15,
            business_day_rule =
                "NEW_YORK_FED_PUBLICATION_DAYS_REVALIDATE_OFFICIAL_HOLIDAYS",
            excluded_dates = REQUIRED_RECURRING_EXCLUDED_DATES,
            timestamp_basis = "official_approximate_window",
            evidence_role = "same_day_revision_candidate",
            origin_day_completion_before_cutoff_required = true,
        ),
    ]
    for (index, row) in enumerate(rows)
        location = "recurring_windows[$index]"
        item = expect_exact_keys(row, RECURRING_WINDOW_KEYS, location)
        item["window_id"] == expected[index].window_id ||
            fail("$location.window_id", "window mismatch")
        item["source_id"] == "frbny_effr" ||
            fail("$location.source_id", "source mismatch")
        item["requirement_id"] == "frbny_effr_tier1" ||
            fail("$location.requirement_id", "requirement mismatch")
        haskey(requirements, item["requirement_id"]) ||
            fail("$location.requirement_id", "unknown requirement")
        for field in (
                "campaign_start_date",
                "campaign_end_date",
                "scheduled_time_utc",
                "business_day_rule",
                "timestamp_basis",
                "evidence_role",
            )
            item[field] == getproperty(expected[index], Symbol(field)) ||
                fail("$location.$field", "window value mismatch")
        end
        expect_string_array(
            item["excluded_dates"],
            "$location.excluded_dates";
            allow_empty = false,
        ) == expected[index].excluded_dates ||
            fail("$location.excluded_dates", "holiday exclusions changed")
        all(
            occursin(DATE_PATTERN, date)
                for date in item["excluded_dates"]
        ) ||
            fail("$location.excluded_dates", "must use YYYY-MM-DD")
        occursin(DATE_PATTERN, item["campaign_start_date"]) ||
            fail("$location.campaign_start_date", "must use YYYY-MM-DD")
        occursin(DATE_PATTERN, item["campaign_end_date"]) ||
            fail("$location.campaign_end_date", "must use YYYY-MM-DD")
        occursin(TIME_Z_PATTERN, item["scheduled_time_utc"]) ||
            fail("$location.scheduled_time_utc", "must use HH:MM:SSZ")
        expect_int(
            item["capture_window_minutes"],
            "$location.capture_window_minutes";
            minimum = 1,
        ) == expected[index].capture_window_minutes ||
            fail("$location.capture_window_minutes", "window value mismatch")
        expect_bool(
            item["origin_day_completion_before_cutoff_required"],
            "$location.origin_day_completion_before_cutoff_required",
        ) == expected[index].origin_day_completion_before_cutoff_required ||
            fail(
            "$location.origin_day_completion_before_cutoff_required",
            "window value mismatch",
        )
        item["capture_status"] == "PLANNED_NOT_CAPTURED" ||
            fail("$location.capture_status", "must remain planned")
        expect_int(item["receipt_count"], "$location.receipt_count"; minimum = 0) ==
            0 ||
            fail("$location.receipt_count", "must remain zero")
        !expect_bool(item["origin_eligible"], "$location.origin_eligible") ||
            fail("$location.origin_eligible", "must remain false")
    end
    return rows
end

function campaign_tuple(item, location)
    start = expect_timestamp(
        item["capture_not_before_utc"],
        "$location.capture_not_before_utc",
    )
    deadline = expect_timestamp(
        item["capture_deadline_utc"],
        "$location.capture_deadline_utc",
    )
    start <= deadline ||
        fail(location, "capture start must not follow deadline")
    deadline < DateTime(2026, 10, 30, 14) ||
        fail(location, "deadline must precede origin")
    return (
        campaign_id =
            expect_identifier(item["campaign_id"], "$location.campaign_id"),
        requirement_ids = expect_string_array(
            item["requirement_ids"],
            "$location.requirement_ids";
            allow_empty = false,
        ),
        capture_not_before_utc = item["capture_not_before_utc"],
        capture_deadline_utc = item["capture_deadline_utc"],
        purpose = expect_string(item["purpose"], "$location.purpose"),
    )
end

function validate_snapshot_campaigns(contract, requirements)
    rows = expect_array(
        contract["snapshot_campaigns"],
        "snapshot_campaigns";
        allow_empty = false,
    )
    length(rows) == 2 ||
        fail("snapshot_campaigns", "must contain early and final campaigns")
    observed = NamedTuple[]
    for (index, row) in enumerate(rows)
        location = "snapshot_campaigns[$index]"
        item = expect_exact_keys(row, SNAPSHOT_CAMPAIGN_KEYS, location)
        tuple = campaign_tuple(item, location)
        all(haskey(requirements, id) for id in tuple.requirement_ids) ||
            fail("$location.requirement_ids", "contains unknown requirement")
        item["availability_basis"] ==
            "VERIFIED_PRE_ORIGIN_RECEIPT_COMPLETION" ||
            fail("$location.availability_basis", "basis mismatch")
        item["capture_status"] == "PLANNED_NOT_CAPTURED" ||
            fail("$location.capture_status", "must remain planned")
        expect_int(item["receipt_count"], "$location.receipt_count"; minimum = 0) ==
            0 ||
            fail("$location.receipt_count", "must remain zero")
        !expect_bool(item["origin_eligible"], "$location.origin_eligible") ||
            fail("$location.origin_eligible", "must remain false")
        push!(observed, tuple)
    end
    observed == EXPECTED_SNAPSHOT_CAMPAIGNS ||
        fail("snapshot_campaigns", "campaign definition mismatch")
    return rows
end

function validate_contract(contract)
    contract = expect_exact_keys(contract, ROOT_KEYS, "contract")
    validate_shared_fail_closed(contract)
    requirements = validate_requirements(contract)
    validate_fixed_events(contract, requirements)
    validate_recurring_windows(contract, requirements)
    validate_snapshot_campaigns(contract, requirements)
    return contract
end

function load_contract(path::AbstractString)
    contract = TOML.parsefile(path)
    validate_contract(contract)
    return contract
end

function capture_authorizations(contract)
    authorizations = Dict{String, Set{String}}()
    windows = Dict{String, Any}()
    for event in contract["fixed_events"]
        id = String(event["event_id"])
        authorizations[id] = Set(String.(event["requirement_ids"]))
        windows[id] = (
            kind = :bounded,
            capture_start =
                expect_timestamp(event["capture_not_before_utc"], "fixed event"),
            capture_deadline =
                expect_timestamp(event["capture_deadline_utc"], "fixed event"),
        )
    end
    for campaign in contract["snapshot_campaigns"]
        id = String(campaign["campaign_id"])
        authorizations[id] = Set(String.(campaign["requirement_ids"]))
        windows[id] = (
            kind = :bounded,
            capture_start = expect_timestamp(
                campaign["capture_not_before_utc"],
                "campaign",
            ),
            capture_deadline = expect_timestamp(
                campaign["capture_deadline_utc"],
                "campaign",
            ),
        )
    end
    for recurring in contract["recurring_windows"]
        id = String(recurring["window_id"])
        authorizations[id] = Set([String(recurring["requirement_id"])])
        windows[id] = (
            kind = :recurring,
            campaign_start = Date(recurring["campaign_start_date"]),
            campaign_end = Date(recurring["campaign_end_date"]),
            scheduled_time_utc = String(recurring["scheduled_time_utc"]),
            capture_window_minutes = Int(recurring["capture_window_minutes"]),
            excluded_dates = Set(Date.(recurring["excluded_dates"])),
        )
    end
    return authorizations, windows
end

function within_capture_window(spec, completed)
    if spec.kind == :bounded
        return spec.capture_start <= completed <= spec.capture_deadline
    end
    completed_date = Date(completed)
    spec.campaign_start <= completed_date <= spec.campaign_end ||
        return false
    dayofweek(completed_date) <= 5 || return false
    completed_date in spec.excluded_dates && return false
    scheduled = expect_timestamp(
        string(completed_date) *
            "T" *
            chop(spec.scheduled_time_utc; tail = 1) *
            "Z",
        "recurring capture window",
    )
    return scheduled <= completed <=
        scheduled + Minute(spec.capture_window_minutes)
end

function selector_dimension(selector::String, keys)
    for segment in split(selector, ":")
        for key in keys
            prefix = "$key="
            startswith(segment, prefix) &&
                return segment[(ncodeunits(prefix) + 1):end]
        end
    end
    return nothing
end

function selector_dimensions(selector::String)
    dimensions = Dict{String, String}()
    for segment in split(selector, ":")
        occursin("=", segment) || continue
        parts = split(segment, "="; limit = 2)
        key, value = String(parts[1]), String(parts[2])
        isempty(key) && fail("selector", "empty selector-dimension key")
        isempty(value) && fail("selector", "empty selector-dimension value")
        haskey(dimensions, key) &&
            fail("selector", "duplicate selector-dimension key $key")
        dimensions[key] = value
    end
    return dimensions
end

function selector_dataset_id(selector::String)
    segments = split(selector, ":")
    length(segments) >= 2 ||
        fail("selector", "must identify source and dataset")
    all(!isempty, segments[1:2]) ||
        fail("selector", "source and dataset must be nonempty")
    return join(segments[1:2], ":")
end

function is_dynamic_selector_value(value::String)
    return value == "X" || has_unresolved_identity_token(value)
end

function dynamic_resolution_mode(value::String)
    value == "X" && return "FULL_REQUESTED_HISTORY"
    occursin(r"(?i)(^|[^A-Z0-9])ALL([^A-Z0-9]|$)", value) &&
        return "FULL_PUBLISHED_UNIVERSE"
    occursin(r"(?i)(^|[^A-Z0-9])LATEST([^A-Z0-9]|$)", value) &&
        return "LATEST_ELIGIBLE_SELECTION"
    return "POLICY_RESOLUTION"
end

function official_https_host(locator::String)
    matched = match(r"^https://([^/:?#]+)(?:[/:?#]|$)", lowercase(locator))
    matched === nothing && return nothing
    return String(matched.captures[1])
end

expected_resolution_mode(selector::String) =
    occursin("LATEST_ELIGIBLE", uppercase(selector)) ?
    "LATEST_ELIGIBLE" : "FIXED"

function has_unresolved_identity_token(value::String)
    value == "UNKNOWN_NOT_ASSERTED" && return false
    value == "NOT_APPLICABLE" && return false
    return occursin(UNRESOLVED_IDENTITY_PATTERN, value)
end

function resolution_rejection(
        contract,
        item,
        requirement,
        requirement_id::String,
        profile_id::String,
        expected_selector::String,
        location::String,
    )
    resolution = expect_exact_keys(
        item["resolution"],
        SELECTOR_RESOLUTION_KEYS,
        "$location.resolution",
    )
    resolution["resolution_schema"] == SELECTOR_RESOLUTION_SCHEMA ||
        return "RESOLUTION_SCHEMA_MISMATCH"
    resolution["requirement_id"] == requirement_id ||
        return "RESOLUTION_REQUIREMENT_MISMATCH"
    resolution["profile_id"] == profile_id ||
        return "RESOLUTION_PROFILE_MISMATCH"
    resolution["policy_selector"] == expected_selector ||
        return "RESOLUTION_SELECTOR_MISMATCH"
    resolution["source_id"] == requirement["source_id"] ||
        return "RESOLUTION_SOURCE_MISMATCH"
    resolution["resolution_mode"] ==
        expected_resolution_mode(expected_selector) ||
        return "RESOLUTION_MODE_MISMATCH"

    required_identity_fields = (
        "release_id",
        "reference_period",
        "dataset_id",
    )
    for field in required_identity_fields
        value = expect_string(resolution[field], "$location.resolution.$field")
        value != "NOT_APPLICABLE" ||
            return "RESOLUTION_IDENTITY_MISSING"
        !has_unresolved_identity_token(value) ||
            return "UNRESOLVED_SELECTOR_IDENTITY"
    end
    for field in (
            "frequency",
            "table_id",
            "line_id",
            "series_id",
            "artifact_member_locator",
        )
        value = expect_string(resolution[field], "$location.resolution.$field")
        !has_unresolved_identity_token(value) ||
            return "UNRESOLVED_SELECTOR_IDENTITY"
    end
    resolution["dataset_id"] == selector_dataset_id(expected_selector) ||
        return "RESOLUTION_DATASET_MISMATCH"

    planned_dimensions = selector_dimensions(expected_selector)
    resolved_dimensions = expect_exact_keys(
        resolution["resolved_dimensions"],
        Set(keys(planned_dimensions)),
        "$location.resolution.resolved_dimensions",
    )
    for (key, planned_value) in planned_dimensions
        resolved_value = expect_string(
            resolved_dimensions[key],
            "$location.resolution.resolved_dimensions.$key",
        )
        if is_dynamic_selector_value(planned_value)
            resolved_value != planned_value ||
                return "UNRESOLVED_SELECTOR_DIMENSION"
            resolved_value != "X" ||
                return "UNRESOLVED_SELECTOR_DIMENSION"
            resolved_value != "NOT_APPLICABLE" ||
                return "RESOLUTION_DIMENSION_MISSING"
            !has_unresolved_identity_token(resolved_value) ||
                return "UNRESOLVED_SELECTOR_DIMENSION"
        elseif resolved_value != planned_value
            return "RESOLUTION_DIMENSION_MISMATCH"
        end
    end
    dynamic_keys = Set(
        key for (key, value) in planned_dimensions if
            is_dynamic_selector_value(value)
    )
    set_resolutions = expect_exact_keys(
        resolution["set_resolutions"],
        dynamic_keys,
        "$location.resolution.set_resolutions",
    )
    candidate_catalog_sha256 = expect_hash(
        resolution["candidate_catalog_sha256"],
        "$location.resolution.candidate_catalog_sha256",
    )
    for key in dynamic_keys
        set_resolution = expect_exact_keys(
            set_resolutions[key],
            SET_RESOLUTION_KEYS,
            "$location.resolution.set_resolutions.$key",
        )
        planned_value = planned_dimensions[key]
        set_resolution["policy_value"] == planned_value ||
            return "SET_RESOLUTION_POLICY_MISMATCH"
        mode = dynamic_resolution_mode(planned_value)
        set_resolution["coverage_mode"] == mode ||
            return "SET_RESOLUTION_MODE_MISMATCH"
        members_sha256 = expect_hash(
            set_resolution["members_sha256"],
            "$location.resolution.set_resolutions.$key.members_sha256",
        )
        set_resolution["candidate_catalog_sha256"] ==
            candidate_catalog_sha256 ||
            return "SET_RESOLUTION_CATALOG_MISMATCH"
        minimum_count = mode == "LATEST_ELIGIBLE_SELECTION" ? 1 : 2
        expect_int(
            set_resolution["member_count"],
            "$location.resolution.set_resolutions.$key.member_count";
            minimum = minimum_count,
        )
        resolved_value = "sha256:$members_sha256"
        set_resolution["resolved_value"] == resolved_value ||
            return "SET_RESOLUTION_VALUE_MISMATCH"
        resolved_dimensions[key] == resolved_value ||
            return "SET_RESOLUTION_DIMENSION_MISMATCH"
    end

    official_locator = expect_string(
        resolution["official_artifact_locator"],
        "$location.resolution.official_artifact_locator",
    )
    startswith(official_locator, "https://") ||
        return "RESOLUTION_LOCATOR_INVALID"
    !has_unresolved_identity_token(official_locator) ||
        return "UNRESOLVED_SELECTOR_IDENTITY"
    official_host = official_https_host(official_locator)
    selector_source = first(split(expected_selector, ":"))
    allowed_hosts = get(
        OFFICIAL_ARTIFACT_HOSTS_BY_SELECTOR_SOURCE,
        selector_source,
        Set{String}(),
    )
    official_host !== nothing && official_host in allowed_hosts ||
        return "RESOLUTION_LOCATOR_HOST_INVALID"
    lowercase_locator = lowercase(official_locator)
    if selector_source == "BEFOREIT" &&
            !(
            startswith(
                lowercase_locator,
                "https://github.com/marketsreplica/us_beforeit.jl/",
            ) ||
                startswith(
                lowercase_locator,
                "https://raw.githubusercontent.com/marketsreplica/us_beforeit.jl/",
            )
        )
        return "RESOLUTION_LOCATOR_REPOSITORY_INVALID"
    end
    official_locator != requirement["source_locator"] ||
        return "RESOLUTION_LOCATOR_INVALID"
    all(
        !occursin(token, lowercase_locator)
            for token in (
                "news/schedule",
                "release-dates",
                "release_schedule",
                "/schedule/",
            )
    ) || return "RESOLUTION_LOCATOR_INVALID"

    projected_dimensions = (
        ("frequency", ("Frequency",)),
        ("table_id", ("TableName", "TableID", "Table")),
        ("line_id", ("LineNumber",)),
        ("series_id", ("Series", "SeriesID", "SeriesCode")),
    )
    for (field, keys) in projected_dimensions
        key = findfirst(candidate -> haskey(resolved_dimensions, candidate), keys)
        key === nothing && continue
        resolution[field] == resolved_dimensions[keys[key]] ||
            return "RESOLUTION_DIMENSION_MISMATCH"
    end
    if haskey(resolved_dimensions, "ReferencePeriod") &&
            resolution["reference_period"] !=
            resolved_dimensions["ReferencePeriod"]
        return "RESOLUTION_DIMENSION_MISMATCH"
    end
    release_key = if haskey(resolved_dimensions, "Release")
        "Release"
    elseif haskey(resolved_dimensions, "release")
        "release"
    end
    if release_key !== nothing &&
            resolution["release_id"] != resolved_dimensions[release_key]
        return "RESOLUTION_RELEASE_ID_MISMATCH"
    end
    member_key = if haskey(resolved_dimensions, "member")
        "member"
    elseif haskey(resolved_dimensions, "archive")
        "archive"
    end
    if member_key !== nothing &&
            resolution["artifact_member_locator"] !=
            resolved_dimensions[member_key]
        return "RESOLUTION_MEMBER_MISMATCH"
    end
    if get(resolved_dimensions, "resolved_workbook_member_required", "false") ==
            "true" &&
            resolution["artifact_member_locator"] == "NOT_APPLICABLE"
        return "RESOLUTION_MEMBER_MISSING"
    end

    expect_hash(
        resolution["candidate_catalog_sha256"],
        "$location.resolution.candidate_catalog_sha256",
    )
    expect_int(
        resolution["candidate_rank"],
        "$location.resolution.candidate_rank";
        minimum = 1,
    ) == 1 ||
        return "RESOLUTION_CANDIDATE_RANK_INVALID"
    candidate_count = expect_int(
        resolution["eligible_candidate_count"],
        "$location.resolution.eligible_candidate_count";
        minimum = 1,
    )
    candidate_count >= resolution["candidate_rank"] ||
        return "RESOLUTION_CANDIDATE_RANK_INVALID"

    resolution["raw_sha256"] == item["raw_sha256"] ||
        return "RESOLUTION_HASH_BINDING_MISMATCH"
    resolution["receipt_sha256"] == item["receipt_sha256"] ||
        return "RESOLUTION_HASH_BINDING_MISMATCH"
    resolution["receipt_completed_at_utc"] ==
        item["receipt_completed_at_utc"] ||
        return "RESOLUTION_RECEIPT_TIME_MISMATCH"
    item["selector_evidence_sha256"] == canonical_sha256(resolution) ||
        return "RESOLUTION_HASH_MISMATCH"

    release_timestamp = expect_string(
        resolution["release_timestamp_utc"],
        "$location.resolution.release_timestamp_utc",
    )
    fixed_event = findfirst(
        event -> event["event_id"] == item["capture_id"],
        contract["fixed_events"],
    )
    if fixed_event !== nothing
        event = contract["fixed_events"][fixed_event]
        if event["timestamp_basis"] == "official_exact" &&
                release_timestamp != event["scheduled_timestamp_utc"]
            return "RESOLUTION_RELEASE_TIME_MISMATCH"
        end
    end
    if release_timestamp != "UNKNOWN_NOT_ASSERTED"
        released =
            expect_timestamp(release_timestamp, "$location.resolution.release_timestamp_utc")
        completed = expect_timestamp(
            resolution["receipt_completed_at_utc"],
            "$location.resolution.receipt_completed_at_utc",
        )
        released <= completed && released < DateTime(2026, 10, 30, 14) ||
            return "RESOLUTION_RELEASE_TIME_INVALID"
    end
    return nothing
end

function evaluate_requirement_completion(
        contract,
        requirement_id::AbstractString,
        evidence_rows,
    )
    validate_contract(contract)
    id = String(requirement_id)
    haskey(REQUIRED_PROFILES_BY_REQUIREMENT, id) ||
        fail("requirement_id", "unknown requirement")
    rows = expect_array(evidence_rows, "evidence_rows")
    expected_profiles = REQUIRED_PROFILES_BY_REQUIREMENT[id]
    requirement = only(
        requirement for requirement in contract["requirements"] if
            requirement["requirement_id"] == id
    )
    authorizations, windows = capture_authorizations(contract)
    accepted = Dict{String, String}()
    rejected = String[]
    evidence_ids = Set{String}()
    duplicate_profiles = Set{String}()
    for (index, row) in enumerate(rows)
        location = "evidence_rows[$index]"
        item = expect_exact_keys(row, PROFILE_EVIDENCE_KEYS, location)
        evidence_id =
            expect_identifier(item["evidence_id"], "$location.evidence_id")
        evidence_id in evidence_ids &&
            fail("$location.evidence_id", "duplicate evidence ID")
        push!(evidence_ids, evidence_id)
        if item["requirement_id"] != id
            push!(rejected, "$evidence_id:REQUIREMENT_MISMATCH")
            continue
        end
        profile_id =
            expect_identifier(item["profile_id"], "$location.profile_id")
        if !haskey(expected_profiles, profile_id)
            push!(rejected, "$evidence_id:UNKNOWN_PROFILE")
            continue
        end
        if item["selector"] != expected_profiles[profile_id]
            push!(rejected, "$evidence_id:SELECTOR_MISMATCH")
            continue
        end
        capture_id =
            expect_identifier(item["capture_id"], "$location.capture_id")
        expected_capture_id = get(
            requirement["profile_capture_overrides"],
            profile_id,
            requirement["default_capture_id"],
        )
        if capture_id != expected_capture_id
            push!(rejected, "$evidence_id:WRONG_PROFILE_CAPTURE")
            continue
        end
        if !haskey(authorizations, capture_id) ||
                !(id in authorizations[capture_id])
            push!(rejected, "$evidence_id:UNAUTHORIZED_CAPTURE")
            continue
        end
        for field in ("raw_sha256", "receipt_sha256", "selector_evidence_sha256")
            expect_hash(item[field], "$location.$field")
        end
        resolution_error = resolution_rejection(
            contract,
            item,
            requirement,
            id,
            profile_id,
            expected_profiles[profile_id],
            location,
        )
        if resolution_error !== nothing
            push!(rejected, "$evidence_id:$resolution_error")
            continue
        end
        completed = expect_timestamp(
            item["receipt_completed_at_utc"],
            "$location.receipt_completed_at_utc",
        )
        upper_bound = expect_timestamp(
            item["availability_upper_bound_utc"],
            "$location.availability_upper_bound_utc",
        )
        if completed != upper_bound
            push!(rejected, "$evidence_id:UPPER_BOUND_MISMATCH")
            continue
        end
        if !within_capture_window(windows[capture_id], completed) ||
                !(completed < DateTime(2026, 10, 30, 14))
            push!(rejected, "$evidence_id:OUTSIDE_CAPTURE_WINDOW")
            continue
        end
        expected_completion_date = get(
            requirement["profile_completion_dates"],
            profile_id,
            nothing,
        )
        if expected_completion_date !== nothing &&
                Date(completed) != Date(expected_completion_date)
            push!(rejected, "$evidence_id:PROFILE_COVERAGE_DATE_MISMATCH")
            continue
        end
        if item["receipt_artifact_status"] != "VERIFIED"
            push!(rejected, "$evidence_id:RECEIPT_NOT_VERIFIED")
            continue
        end
        if item["durable_storage_status"] != "VERIFIED"
            push!(rejected, "$evidence_id:STORAGE_NOT_VERIFIED")
            continue
        end
        retain_until =
            expect_timestamp(item["retain_until_utc"], "$location.retain_until_utc")
        if retain_until < DateTime(2031, 10, 30, 14)
            push!(rejected, "$evidence_id:RETENTION_TOO_SHORT")
            continue
        end
        if haskey(accepted, profile_id) || profile_id in duplicate_profiles
            push!(rejected, "$evidence_id:DUPLICATE_PROFILE")
            delete!(accepted, profile_id)
            push!(duplicate_profiles, profile_id)
            continue
        end
        accepted[profile_id] = evidence_id
    end
    missing = sort!(collect(setdiff(Set(keys(expected_profiles)), Set(keys(accepted)))))
    shape_complete = isempty(missing) && isempty(rejected)
    return (
        requirement_id = id,
        completion_rule = "ALL_PROFILES_VERIFIED",
        expected_profile_count = length(expected_profiles),
        accepted_profile_count = length(accepted),
        accepted_profile_ids = sort!(collect(keys(accepted))),
        missing_profile_ids = missing,
        rejected_evidence = rejected,
        shape_complete = shape_complete,
        verifier_attested = false,
        complete = false,
        origin_admissible = false,
        ready = false,
        inventory_mutation_authorized = false,
    )
end

end
