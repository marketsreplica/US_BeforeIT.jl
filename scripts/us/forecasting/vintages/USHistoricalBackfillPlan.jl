module USHistoricalBackfillPlan

using Dates
using SHA
using TOML

export BackfillPlanValidationError,
    backfill_plan_sha256,
    load_backfill_plan,
    stamp_backfill_plan_sha256!,
    validate_backfill_plan,
    validate_contract_alignment,
    validate_prospective_capture_deadline,
    validate_inventory_alignment

const PLAN_SCHEMA = "beforeit-us-historical-backfill-plan.v1"
const PLAN_ID = "beforeit-us-historical-backfill-and-capture.v1"
const PLAN_STATUS = "PLAN_ONLY_NOT_ACQUIRED"
const AS_OF_DATE = "2026-08-05"
const PROTOCOL_SHA256 =
    "88519e5b04936f528396cf5243ff270844d0d38651fd84fc3b1c76fef997b584"
const TIER1_TARGETS_SHA256 =
    "bdbbeb48a39c7fdd03972626cf7f1e421ba7c5dd254f5537a40dda0eb4ae1fcb"
const CANONICALIZATION = "utf8-length-prefixed-sorted-map-array-order.v1"
const INVENTORY_SCHEMA = "beforeit-us-source-release-inventory.v1"
const INVENTORY_SHA256 =
    "6b1fc42b1d645d43f9be6e215d42ab662924d6bb51249760aa2992d143031d74"
const INVENTORY_LOCATOR = "scripts/us/forecasting/vintages/current_inventory.toml"
const RECONSTRUCTION_ORIGIN = "2026-07-31T14:00:00Z"
const RECONSTRUCTION_TRIGGER = "2026-07-30T12:30:00Z"
const PROSPECTIVE_ORIGIN = "2026-10-30T14:00:00Z"
const PROSPECTIVE_TRIGGER = "2026-10-29T12:30:00Z"
const AUDITED_UTC_OFFSET_SECONDS = -4 * 60 * 60
const AUDITED_US_FEDERAL_HOLIDAYS_2026 = Set(
    [
        Date(2026, 9, 7),
        Date(2026, 10, 12),
    ],
)
const UNESTABLISHED_TIMESTAMP = "NOT_ESTABLISHED"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const TIMESTAMP_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const LOCAL_TIMESTAMP_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"
const QUARTER_PATTERN = r"^\d{4}Q[1-4]$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"

const ROOT_KEYS = Set(
    [
        "artifact",
        "admission",
        "inventory_guard",
        "precision_policy",
        "licensing",
        "pilot_origins",
        "source_routes",
        "acquisition_stages",
    ],
)
const ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "plan_id",
        "status",
        "as_of_date",
        "protocol_sha256",
        "tier1_targets_sha256",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const ADMISSION_KEYS = Set(
    [
        "strict_retrospective_origin_count",
        "strict_retrospective_origin_timestamps_utc",
        "timing_timezone_label",
        "timing_conversion_method",
        "timing_utc_offset_seconds",
        "timing_offset_scope",
        "reconstruction_trigger_release_timestamp_local",
        "reconstruction_trigger_release_timestamp_utc",
        "reconstruction_only_origin_timestamp_local",
        "reconstruction_only_origin_timestamp_utc",
        "reconstruction_evidence_class",
        "reconstruction_status",
        "reconstruction_runnable",
        "reconstruction_promotion_eligible",
        "planned_first_prospective_trigger_release_timestamp_local",
        "planned_first_prospective_trigger_release_timestamp_utc",
        "planned_first_prospective_origin_timestamp_local",
        "planned_first_prospective_origin_timestamp_utc",
        "planned_first_prospective_capture_deadline_utc",
        "planned_first_prospective_reference_quarter",
        "planned_first_prospective_origin_rule",
        "planned_first_prospective_schedule_locator",
        "planned_first_prospective_schedule_locator_role",
        "planned_first_prospective_schedule_revalidation_required",
        "planned_first_prospective_schedule_snapshot_receipt_status",
        "planned_first_prospective_trigger_capture_receipt_status",
        "planned_first_prospective_trigger_capture_receipt_count",
        "planned_first_prospective_complete_origin_receipt_status",
        "planned_first_prospective_complete_origin_receipt_count",
        "planned_first_prospective_missed_deadline_policy",
        "planned_first_prospective_status",
        "planned_first_prospective_admitted",
        "planned_first_prospective_ready",
        "accuracy_evaluation_allowed",
    ],
)
const INVENTORY_GUARD_KEYS = Set(
    [
        "inventory_locator",
        "inventory_schema_version",
        "expected_inventory_sha256",
        "required_release_event_count",
        "required_admissible_origin_count",
        "plan_may_mutate_inventory",
    ],
)
const PRECISION_POLICY_KEYS = Set(
    [
        "exact_timestamp_format",
        "exact_intraday_evidence_required",
        "date_only_origin_eligible",
        "no_time_origin_eligible",
        "mixed_precision_origin_eligible_without_event_resolution",
        "retrieval_time_may_substitute_for_release_time",
        "route_level_claim_may_substitute_for_event_evidence",
        "raw_release_bytes_required",
        "raw_sha256_required",
        "first_state_bytes_required",
    ],
)
const LICENSING_KEYS = Set(
    [
        "bea_terms_locator",
        "bea_terms_review_as_of_date",
        "bea_terms_recheck_before_acquisition",
        "bea_public_domain_status",
        "bea_attribution_policy",
        "bls_copyright_locator",
        "bls_developer_terms_locator",
        "bls_terms_review_as_of_date",
        "bls_terms_recheck_before_acquisition",
        "bls_public_domain_status",
        "bls_attribution_policy",
        "bls_api_access_date_required",
        "bls_api_disclaimer_required",
        "bls_emblem_use_allowed",
        "bls_plan_authorizes_byte_acquisition",
        "fred_alfred_warehouse_status",
        "fred_alfred_terms_locator",
        "fred_alfred_terms_review_as_of_date",
        "fred_alfred_terms_recheck_before_use",
        "written_clearance_required",
        "cache_allowed_without_clearance",
        "archive_allowed_without_clearance",
        "software_or_ai_use_allowed_without_clearance",
        "permitted_unresolved_role",
        "rtdsm_role",
        "frbny_reference_rates_terms_locator",
        "frbny_terms_review_as_of_date",
        "frbny_terms_recheck_before_acquisition",
        "frbny_reference_rate_notice_required",
        "frbny_attribution_required",
        "frbny_plan_authorizes_byte_acquisition",
    ],
)
const PILOT_KEYS = Set(
    [
        "pilot_id",
        "reference_quarter",
        "pilot_kind",
        "evidence_class",
        "origin_timestamp_status",
        "origin_timestamp_utc",
        "admission_status",
        "runnable",
        "promotion_eligible",
        "purpose",
    ],
)
const SOURCE_KEYS = Set(
    [
        "route_id",
        "provider",
        "source_family",
        "role",
        "discovery_locator",
        "locator_role",
        "exact_release_byte_locator_status",
        "archive_identifier",
        "discovery_schema",
        "series_identifiers",
        "terms_locator",
        "terms_review_status",
        "redistribution_status",
        "attribution_requirement",
        "archive_start",
        "coverage_detail",
        "published_artifact_formats",
        "bytes_status",
        "timestamp_evidence_class",
        "timestamp_detail",
        "first_state_status",
        "method_break",
        "target_ids",
        "required_for_strict_origin",
        "release_bytes_registered",
        "registered_release_event_count",
        "origin_admissible",
        "route_status",
        "blocker_code",
        "acquisition_priority",
    ],
)
const STAGE_KEYS = Set(
    [
        "stage",
        "stage_id",
        "route_ids",
        "entry_condition",
        "exit_condition",
        "status",
    ],
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
const BEA_TIER1_TARGET_IDS = Set(
    [
        "core_pce_price_index",
        "gdp_deflator",
        "nominal_gdp",
        "pce_price_index",
        "real_gdp",
    ],
)
const BYTE_STATUSES = Set(
    [
        "CURRENT_AND_REVISED_ONLY_NO_COMPLETE_FIRST_STATE_ARCHIVE",
        "NO_SYSTEMATIC_AS_PUBLISHED_BYTE_ARCHIVE",
        "OFFICIAL_ARCHIVE_ROUTE_IDENTIFIED_NOT_ACQUIRED",
    ],
)
const TIMESTAMP_EVIDENCE_CLASSES = Set(
    [
        "date_only",
        "exact_intraday_route_only",
        "historical_first_state_unverified",
        "mixed_event_level",
        "no_time",
    ],
)
const ROUTE_STATUSES = Set(
    [
        "BACKFILL_CANDIDATE_NOT_INSTALLED",
        "PROSPECTIVE_CAPTURE_REQUIRED",
        "STRUCTURAL_BLOCKED",
    ],
)
const PILOT_KINDS = Set(
    ["coverage_gap_probe", "prospective_capture", "reconstructed_diagnostic"],
)
const PILOT_EVIDENCE_CLASSES =
    Set(["prospective", "reconstructed_after_origin"])
const PILOT_TIMESTAMP_STATUSES = Set(
    [
        "EXACT_DIAGNOSTIC_CUTOFF",
        "EXACT_PLANNED_CUTOFF",
        "NOT_ESTABLISHED",
    ],
)
const DISCOVERY_LOCATOR_ROLE =
    "OFFICIAL_DISCOVERY_ROUTE_NOT_EXACT_RELEASE_BYTE_IDENTITY"
const EXACT_RELEASE_LOCATOR_STATUS = "UNRESOLVED_NOT_REGISTERED"
const UNRESOLVED_TERMS_REVIEW =
    "NOT_REVIEWED_BLOCKS_BYTE_ACQUISITION"
const UNRESOLVED_REDISTRIBUTION =
    "UNRESOLVED_NO_REDISTRIBUTION_AUTHORIZED_BY_PLAN"
const SOURCE_ATTRIBUTION_REQUIREMENT =
    "PRESERVE_PROVIDER_SOURCE_AND_RELEASE_IDENTIFIERS"
const BEA_TERMS_LOCATOR = "https://www.bea.gov/index.php/help/faq/145"
const BEA_TERMS_REVIEW_DATE = "2026-08-05"
const BEA_TERMS_REVIEW_STATUS =
    "REVIEWED_AS_OF_2026-08-05_RECHECK_BEFORE_ACQUISITION"
const BEA_REDISTRIBUTION_STATUS =
    "PUBLIC_DOMAIN_UNLESS_OTHERWISE_STATED_RECHECK_FILE_SPECIFIC_NOTICES"
const BEA_ATTRIBUTION_REQUIREMENT =
    "PRESERVE_BEA_SOURCE_AND_RELEASE_IDENTIFIERS_ATTRIBUTION_APPRECIATED"
const BLS_COPYRIGHT_LOCATOR =
    "https://www.bls.gov/opub/copyright-information.htm"
const BLS_DEVELOPER_TERMS_LOCATOR =
    "https://www.bls.gov/developers/termsOfService.htm"
const BLS_TERMS_REVIEW_DATE = "2026-08-06"
const BLS_TERMS_REVIEW_STATUS =
    "REVIEWED_AS_OF_2026-08-06_RECHECK_BEFORE_ACQUISITION"
const BLS_PUBLIC_DOMAIN_STATUS =
    "PUBLIC_DOMAIN_EXCEPT_PREVIOUSLY_COPYRIGHTED_PHOTOGRAPHS_AND_ILLUSTRATIONS_RECHECK_FILE_SPECIFIC_NOTICES"
const BLS_ATTRIBUTION_REQUIREMENT =
    "CITE_BLS_PRESERVE_SOURCE_ACCESS_AND_RELEASE_IDENTIFIERS_NO_EMBLEM"

const EXPECTED_PILOTS = Dict(
    "2008q3_gap_probe" => Dict(
        "reference_quarter" => "2008Q3",
        "pilot_kind" => "coverage_gap_probe",
        "evidence_class" => "reconstructed_after_origin",
        "origin_timestamp_status" => "NOT_ESTABLISHED",
        "origin_timestamp_utc" => UNESTABLISHED_TIMESTAMP,
        "admission_status" => "CANNOT_RUN",
    ),
    "2019q4_reconstructed" => Dict(
        "reference_quarter" => "2019Q4",
        "pilot_kind" => "reconstructed_diagnostic",
        "evidence_class" => "reconstructed_after_origin",
        "origin_timestamp_status" => "NOT_ESTABLISHED",
        "origin_timestamp_utc" => UNESTABLISHED_TIMESTAMP,
        "admission_status" => "CANNOT_RUN",
    ),
    "2020q1_reconstructed" => Dict(
        "reference_quarter" => "2020Q1",
        "pilot_kind" => "reconstructed_diagnostic",
        "evidence_class" => "reconstructed_after_origin",
        "origin_timestamp_status" => "NOT_ESTABLISHED",
        "origin_timestamp_utc" => UNESTABLISHED_TIMESTAMP,
        "admission_status" => "CANNOT_RUN",
    ),
    "2021q2_reconstructed" => Dict(
        "reference_quarter" => "2021Q2",
        "pilot_kind" => "reconstructed_diagnostic",
        "evidence_class" => "reconstructed_after_origin",
        "origin_timestamp_status" => "NOT_ESTABLISHED",
        "origin_timestamp_utc" => UNESTABLISHED_TIMESTAMP,
        "admission_status" => "CANNOT_RUN",
    ),
    "2026q2_reconstructed" => Dict(
        "reference_quarter" => "2026Q2",
        "pilot_kind" => "reconstructed_diagnostic",
        "evidence_class" => "reconstructed_after_origin",
        "origin_timestamp_status" => "EXACT_DIAGNOSTIC_CUTOFF",
        "origin_timestamp_utc" => RECONSTRUCTION_ORIGIN,
        "admission_status" => "CANNOT_RUN",
    ),
    "2026q3_prospective" => Dict(
        "reference_quarter" => "2026Q3",
        "pilot_kind" => "prospective_capture",
        "evidence_class" => "prospective",
        "origin_timestamp_status" => "EXACT_PLANNED_CUTOFF",
        "origin_timestamp_utc" => PROSPECTIVE_ORIGIN,
        "admission_status" => "PLANNED_NOT_CAPTURED_NOT_ADMITTED",
    ),
)

const EXPECTED_SOURCE_FACTS = Dict(
    "bea_fixed_assets_hmi11" => Dict(
        "role" => "structural_input",
        "archive_start" => "VINTAGES_AVAILABLE_START_NOT_CERTIFIED",
        "bytes_status" => "OFFICIAL_ARCHIVE_ROUTE_IDENTIFIED_NOT_ACQUIRED",
        "timestamp_evidence_class" => "date_only",
        "first_state_status" => "MANY_RELEASES_HAVE_DATE_ONLY_METADATA",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "STRUCTURAL_BLOCKED",
        "blocker_code" => "DATE_ONLY_TIMES_AND_BYTES_NOT_REGISTERED",
    ),
    "bea_industry_hmi8" => Dict(
        "role" => "structural_input",
        "archive_start" => "APPROXIMATELY_2014",
        "bytes_status" => "OFFICIAL_ARCHIVE_ROUTE_IDENTIFIED_NOT_ACQUIRED",
        "timestamp_evidence_class" => "mixed_event_level",
        "first_state_status" => "SYSTEMATIC_INDUSTRY_AND_IO_ARCHIVE_ROUTE_IDENTIFIED",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "STRUCTURAL_BLOCKED",
        "blocker_code" => "EVENT_LEVEL_TIMES_AND_BYTES_NOT_REGISTERED",
    ),
    "bea_nipa_hmi7" => Dict(
        "role" => "tier1_target",
        "archive_start" => "2002Q2_FINAL_ONLY_2002Q3_FULL_SEQUENCE",
        "bytes_status" => "OFFICIAL_ARCHIVE_ROUTE_IDENTIFIED_NOT_ACQUIRED",
        "timestamp_evidence_class" => "exact_intraday_route_only",
        "first_state_status" => "ADVANCE_PRELIMINARY_FINAL_SEQUENCE_FROM_2002Q3",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "BACKFILL_CANDIDATE_NOT_INSTALLED",
        "blocker_code" => "RELEASE_BYTES_HASHES_AND_TIMES_NOT_REGISTERED",
    ),
    "bls_ces_employment_situation" => Dict(
        "role" => "tier1_target",
        "archive_start" => "2003-05",
        "bytes_status" => "OFFICIAL_ARCHIVE_ROUTE_IDENTIFIED_NOT_ACQUIRED",
        "timestamp_evidence_class" => "exact_intraday_route_only",
        "first_state_status" => "FIRST_PRELIMINARY_VALUES_DOCUMENTED_SINCE_2003-05",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "BACKFILL_CANDIDATE_NOT_INSTALLED",
        "blocker_code" => "RELEASE_BYTES_HASHES_AND_TIMES_NOT_REGISTERED",
    ),
    "bls_cps_employment_situation" => Dict(
        "role" => "tier1_target",
        "archive_start" => "START_NOT_CERTIFIED_BY_THIS_AUDIT",
        "bytes_status" => "OFFICIAL_ARCHIVE_ROUTE_IDENTIFIED_NOT_ACQUIRED",
        "timestamp_evidence_class" => "exact_intraday_route_only",
        "first_state_status" => "EMPLOYMENT_SITUATION_ARCHIVE_ROUTE_IDENTIFIED",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "BACKFILL_CANDIDATE_NOT_INSTALLED",
        "blocker_code" => "RELEASE_BYTES_HASHES_AND_TIMES_NOT_REGISTERED",
    ),
    "bls_cps_structural_controls" => Dict(
        "role" => "structural_input",
        "archive_start" => "START_NOT_CERTIFIED_BY_THIS_AUDIT",
        "bytes_status" => "NO_SYSTEMATIC_AS_PUBLISHED_BYTE_ARCHIVE",
        "timestamp_evidence_class" => "no_time",
        "first_state_status" => "STRUCTURAL_CONTROL_FIRST_STATE_BYTES_NOT_ESTABLISHED",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "STRUCTURAL_BLOCKED",
        "blocker_code" => "NO_SYSTEMATIC_FIRST_STATE_BYTES_OR_INTRADAY_TIMES",
    ),
    "bls_qcew" => Dict(
        "role" => "structural_input",
        "archive_start" => "START_NOT_CERTIFIED_BY_THIS_AUDIT",
        "bytes_status" => "NO_SYSTEMATIC_AS_PUBLISHED_BYTE_ARCHIVE",
        "timestamp_evidence_class" => "date_only",
        "first_state_status" => "AS_PUBLISHED_STRUCTURAL_SEQUENCE_NOT_ESTABLISHED",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "STRUCTURAL_BLOCKED",
        "blocker_code" => "NO_SYSTEMATIC_FIRST_STATE_BYTES_AND_DATE_ONLY_TIMES",
    ),
    "census_susb" => Dict(
        "role" => "structural_input",
        "archive_start" => "START_NOT_CERTIFIED_BY_THIS_AUDIT",
        "bytes_status" => "NO_SYSTEMATIC_AS_PUBLISHED_BYTE_ARCHIVE",
        "timestamp_evidence_class" => "no_time",
        "first_state_status" => "AS_PUBLISHED_STRUCTURAL_SEQUENCE_NOT_ESTABLISHED",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "STRUCTURAL_BLOCKED",
        "blocker_code" => "NO_SYSTEMATIC_FIRST_STATE_BYTES_OR_INTRADAY_TIMES",
    ),
    "frb_z1" => Dict(
        "role" => "structural_input",
        "archive_start" => "1996Q2",
        "bytes_status" => "OFFICIAL_ARCHIVE_ROUTE_IDENTIFIED_NOT_ACQUIRED",
        "timestamp_evidence_class" => "mixed_event_level",
        "first_state_status" => "PDF_OLDER_HTML_AFTER_2004_CSV_FROM_2016",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "STRUCTURAL_BLOCKED",
        "blocker_code" => "EVENT_LEVEL_TIMES_AND_BYTES_NOT_REGISTERED",
    ),
    "frbny_effr" => Dict(
        "role" => "tier1_target",
        "archive_start" => "2000-07-03",
        "bytes_status" => "CURRENT_AND_REVISED_ONLY_NO_COMPLETE_FIRST_STATE_ARCHIVE",
        "timestamp_evidence_class" => "historical_first_state_unverified",
        "first_state_status" => "NO_COMPLETE_HISTORICAL_FIRST_STATE_ARCHIVE",
        "method_break" => "2016-03-01_CALCULATION_METHOD_CHANGE",
        "route_status" => "PROSPECTIVE_CAPTURE_REQUIRED",
        "blocker_code" => "FIRST_STATE_BYTES_AND_EXACT_HISTORICAL_TIMES_UNAVAILABLE",
    ),
    "usda_structural_counts" => Dict(
        "role" => "structural_input",
        "archive_start" => "START_NOT_CERTIFIED_BY_THIS_AUDIT",
        "bytes_status" => "NO_SYSTEMATIC_AS_PUBLISHED_BYTE_ARCHIVE",
        "timestamp_evidence_class" => "date_only",
        "first_state_status" => "RELEASE_DATES_OFTEN_LACK_INTRADAY_TIME",
        "method_break" => "NONE_IDENTIFIED_IN_THIS_PLAN",
        "route_status" => "STRUCTURAL_BLOCKED",
        "blocker_code" => "NO_SYSTEMATIC_FIRST_STATE_BYTES_AND_DATE_ONLY_TIMES",
    ),
)

const EXPECTED_TARGETS_BY_ROUTE = Dict(
    "bea_nipa_hmi7" => BEA_TIER1_TARGET_IDS,
    "bls_ces_employment_situation" => Set(["payroll_employment"]),
    "bls_cps_employment_situation" => Set(["unemployment_rate"]),
    "frbny_effr" => Set(["effective_federal_funds_rate"]),
)

const EXPECTED_SOURCE_IDENTITIES = Dict(
    "bea_fixed_assets_hmi11" => (
        "U.S. Bureau of Economic Analysis",
        "historical_fixed_assets",
    ),
    "bea_industry_hmi8" => (
        "U.S. Bureau of Economic Analysis",
        "historical_industry_and_input_output",
    ),
    "bea_nipa_hmi7" => (
        "U.S. Bureau of Economic Analysis",
        "historical_nipa",
    ),
    "bls_ces_employment_situation" => (
        "U.S. Bureau of Labor Statistics",
        "employment_situation_ces",
    ),
    "bls_cps_employment_situation" => (
        "U.S. Bureau of Labor Statistics",
        "employment_situation_cps",
    ),
    "bls_cps_structural_controls" => (
        "U.S. Bureau of Labor Statistics",
        "cps_structural_controls",
    ),
    "bls_qcew" => (
        "U.S. Bureau of Labor Statistics",
        "quarterly_census_employment_wages",
    ),
    "census_susb" => (
        "U.S. Census Bureau",
        "statistics_of_us_businesses",
    ),
    "frb_z1" => (
        "Board of Governors of the Federal Reserve System",
        "financial_accounts_z1",
    ),
    "frbny_effr" => (
        "Federal Reserve Bank of New York",
        "reference_rates_effr",
    ),
    "usda_structural_counts" => (
        "U.S. Department of Agriculture",
        "farm_structural_counts",
    ),
)

const EXPECTED_SOURCE_DISCOVERY = Dict(
    "bea_fixed_assets_hmi11" => (
        discovery_locator = "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=11&getFiles=false&getDirs=true",
        archive_identifier = "BEA_HMI_11",
        discovery_schema = "BEA_HISTDATA_FEA_DISPLAY_CHILDREN_C_JSON",
        series_identifiers = String[],
        terms_locator = BEA_TERMS_LOCATOR,
        terms_review_status = BEA_TERMS_REVIEW_STATUS,
        redistribution_status = BEA_REDISTRIBUTION_STATUS,
        attribution_requirement = BEA_ATTRIBUTION_REQUIREMENT,
    ),
    "bea_industry_hmi8" => (
        discovery_locator = "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=8&getFiles=false&getDirs=true",
        archive_identifier = "BEA_HMI_8",
        discovery_schema = "BEA_HISTDATA_FEA_DISPLAY_CHILDREN_C_JSON",
        series_identifiers = String[],
        terms_locator = BEA_TERMS_LOCATOR,
        terms_review_status = BEA_TERMS_REVIEW_STATUS,
        redistribution_status = BEA_REDISTRIBUTION_STATUS,
        attribution_requirement = BEA_ATTRIBUTION_REQUIREMENT,
    ),
    "bea_nipa_hmi7" => (
        discovery_locator = "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=7&getFiles=false&getDirs=true",
        archive_identifier = "BEA_HMI_7",
        discovery_schema = "BEA_HISTDATA_FEA_DISPLAY_CHILDREN_C_JSON",
        series_identifiers = [
            "NIPA:T10105:line1:A191RC",
            "NIPA:T10106:line1:A191RX",
            "NIPA:T10109:line1:A191RD",
            "NIPA:T20304:line1:DPCERG",
            "NIPA:T20304:line25:DPCCRG",
        ],
        terms_locator = BEA_TERMS_LOCATOR,
        terms_review_status = BEA_TERMS_REVIEW_STATUS,
        redistribution_status = BEA_REDISTRIBUTION_STATUS,
        attribution_requirement = BEA_ATTRIBUTION_REQUIREMENT,
    ),
    "bls_ces_employment_situation" => (
        discovery_locator = "https://www.bls.gov/web/empsit/cesvininfo.htm",
        archive_identifier = "BLS_EMPLOYMENT_SITUATION_CES",
        discovery_schema = "HTML_DISCOVERY_PAGE",
        series_identifiers = ["BLS:CES0000000001"],
        terms_locator = BLS_COPYRIGHT_LOCATOR,
        terms_review_status = BLS_TERMS_REVIEW_STATUS,
        redistribution_status = BLS_PUBLIC_DOMAIN_STATUS,
        attribution_requirement = BLS_ATTRIBUTION_REQUIREMENT,
    ),
    "bls_cps_employment_situation" => (
        discovery_locator = "https://www.bls.gov/bls/news-release/empsit.htm",
        archive_identifier = "BLS_EMPLOYMENT_SITUATION_CPS",
        discovery_schema = "HTML_DISCOVERY_PAGE",
        series_identifiers = ["BLS:LNS14000000"],
        terms_locator = BLS_COPYRIGHT_LOCATOR,
        terms_review_status = BLS_TERMS_REVIEW_STATUS,
        redistribution_status = BLS_PUBLIC_DOMAIN_STATUS,
        attribution_requirement = BLS_ATTRIBUTION_REQUIREMENT,
    ),
    "bls_cps_structural_controls" => (
        discovery_locator = "https://www.bls.gov/cps/data.htm",
        archive_identifier = "BLS_CPS_MULTISERIES_UNRESOLVED",
        discovery_schema = "HTML_DISCOVERY_PAGE",
        series_identifiers = String[],
        terms_locator = BLS_COPYRIGHT_LOCATOR,
        terms_review_status = BLS_TERMS_REVIEW_STATUS,
        redistribution_status = BLS_PUBLIC_DOMAIN_STATUS,
        attribution_requirement = BLS_ATTRIBUTION_REQUIREMENT,
    ),
    "bls_qcew" => (
        discovery_locator = "https://www.bls.gov/cew/downloadable-data-files.htm",
        archive_identifier = "BLS_QCEW",
        discovery_schema = "HTML_DISCOVERY_PAGE",
        series_identifiers = String[],
        terms_locator = BLS_COPYRIGHT_LOCATOR,
        terms_review_status = BLS_TERMS_REVIEW_STATUS,
        redistribution_status = BLS_PUBLIC_DOMAIN_STATUS,
        attribution_requirement = BLS_ATTRIBUTION_REQUIREMENT,
    ),
    "census_susb" => (
        discovery_locator = "https://www.census.gov/programs-surveys/susb/data.html",
        archive_identifier = "CENSUS_SUSB",
        discovery_schema = "HTML_DISCOVERY_PAGE",
        series_identifiers = String[],
        terms_locator = "UNRESOLVED",
        terms_review_status = UNRESOLVED_TERMS_REVIEW,
        redistribution_status = UNRESOLVED_REDISTRIBUTION,
        attribution_requirement = SOURCE_ATTRIBUTION_REQUIREMENT,
    ),
    "frb_z1" => (
        discovery_locator = "https://www.federalreserve.gov/releases/z1/release-dates.htm",
        archive_identifier = "FRB_Z1",
        discovery_schema = "HTML_DISCOVERY_PAGE",
        series_identifiers = String[],
        terms_locator = "UNRESOLVED",
        terms_review_status = UNRESOLVED_TERMS_REVIEW,
        redistribution_status = UNRESOLVED_REDISTRIBUTION,
        attribution_requirement = SOURCE_ATTRIBUTION_REQUIREMENT,
    ),
    "frbny_effr" => (
        discovery_locator = "https://www.newyorkfed.org/markets/reference-rates/effr",
        archive_identifier = "FRBNY_EFFR",
        discovery_schema = "HTML_DISCOVERY_PAGE",
        series_identifiers = ["FRBNY:EFFR"],
        terms_locator = "https://www.newyorkfed.org/privacy/termsofuse",
        terms_review_status = "REVIEWED_AS_OF_2026-08-05_RECHECK_BEFORE_ACQUISITION",
        redistribution_status = "PERMITTED_SUBJECT_TO_CURRENT_TERMS_AND_REFERENCE_RATE_NOTICE",
        attribution_requirement = "PRESERVE_FRBNY_SOURCE_IDENTIFIERS_AND_PUBLISH_PRESCRIBED_REFERENCE_RATE_NOTICE",
    ),
    "usda_structural_counts" => (
        discovery_locator = "https://www.nass.usda.gov/Publications/AgCensus/",
        archive_identifier = "USDA_NASS_CENSUS_OF_AGRICULTURE",
        discovery_schema = "HTML_DISCOVERY_PAGE",
        series_identifiers = String[],
        terms_locator = "UNRESOLVED",
        terms_review_status = UNRESOLVED_TERMS_REVIEW,
        redistribution_status = UNRESOLVED_REDISTRIBUTION,
        attribution_requirement = SOURCE_ATTRIBUTION_REQUIREMENT,
    ),
)

const EXPECTED_STAGES = Dict(
    1 => (
        "bea_tier1_release_files",
        Set(["bea_nipa_hmi7"]),
    ),
    2 => (
        "bls_tier1_release_files",
        Set(
            [
                "bls_ces_employment_situation",
                "bls_cps_employment_situation",
            ]
        ),
    ),
    3 => (
        "federal_reserve_targets_and_accounts",
        Set(["frb_z1", "frbny_effr"]),
    ),
    4 => (
        "bea_structural_archives",
        Set(["bea_fixed_assets_hmi11", "bea_industry_hmi8"]),
    ),
    5 => (
        "remaining_structural_archives",
        Set(
            [
                "bls_cps_structural_controls",
                "bls_qcew",
                "census_susb",
                "usda_structural_counts",
            ]
        ),
    ),
)

const EXPECTED_STAGE_CONDITIONS = Dict(
    1 => (
        "Plan validator and immutable retrieval manifest format pass review.",
        "All selected HMI7 release files have immutable bytes, SHA256, release IDs, exact availability evidence, and target mappings; no origin is admitted by this stage alone.",
    ),
    2 => (
        "Stage 1 event schema is reusable for BLS release files.",
        "CES and unemployment first-state release artifacts have exact event evidence and pass target-operator validation; structural CPS remains a separate blocker.",
    ),
    3 => (
        "Target and structural event manifests can represent revisions and format changes.",
        "Z.1 format eras are mapped and prospective EFFR capture records first and revision windows; historical EFFR gaps stay explicit.",
    ),
    4 => (
        "Tier-1 target acquisition has demonstrated byte- and timestamp-resolving retrieval.",
        "Industry, input-output, and fixed-assets events have exact classifications, bytes, hashes, and event-level time evidence or explicit missing-time blockers.",
    ),
    5 => (
        "Source-specific licensing and redistribution review is recorded before byte capture.",
        "Every required structural input has a certified first-state release sequence or remains an explicit CANNOT_RUN blocker; FRED and ALFRED are excluded without written clearance.",
    ),
)

struct BackfillPlanValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::BackfillPlanValidationError) =
    print(io, error.message)

fail(location, message) =
    throw(BackfillPlanValidationError("$location: $message"))

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

function expect_string(value, location; allow_empty = false)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    !allow_empty && isempty(text) && fail(location, "must not be empty")
    return text
end

function expect_identifier(value, location)
    text = expect_string(value, location)
    occursin(IDENTIFIER_PATTERN, text) ||
        fail(location, "contains unsupported identifier characters")
    return text
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be Boolean")
    return value
end

function expect_integer(value, location)
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    return Int(value)
end

function expect_array(value, location; allow_empty = true)
    value isa AbstractVector || fail(location, "must be an array")
    !allow_empty && isempty(value) && fail(location, "must not be empty")
    return value
end

function expect_string_array(value, location; allow_empty = true)
    values = expect_array(value, location; allow_empty)
    strings = [
        expect_string(entry, "$location[$index]") for
            (index, entry) in enumerate(values)
    ]
    length(Set(strings)) == length(strings) ||
        fail(location, "must not contain duplicates")
    return strings
end

function expect_one_of(value, allowed, location)
    text = expect_string(value, location)
    text in allowed ||
        fail(
        location,
        "must be one of $(join(sort!(collect(allowed)), ", "))",
    )
    return text
end

function expect_timestamp(value, location)
    text = expect_string(value, location)
    occursin(TIMESTAMP_PATTERN, text) ||
        fail(
        location,
        "must be an RFC3339 UTC timestamp at exact second precision",
    )
    timestamp = try
        DateTime(text[1:(end - 1)], RFC3339_SECONDS_FORMAT)
    catch
        fail(location, "is not a valid UTC timestamp")
    end
    Dates.format(timestamp, RFC3339_SECONDS_FORMAT) * "Z" == text ||
        fail(location, "is not a canonical UTC timestamp")
    return timestamp
end

function expect_local_timestamp(value, location)
    text = expect_string(value, location)
    occursin(LOCAL_TIMESTAMP_PATTERN, text) ||
        fail(
        location,
        "must be a local wall-clock timestamp at exact second precision without an offset",
    )
    timestamp = try
        DateTime(text, RFC3339_SECONDS_FORMAT)
    catch
        fail(location, "is not a valid local wall-clock timestamp")
    end
    Dates.format(timestamp, RFC3339_SECONDS_FORMAT) == text ||
        fail(location, "is not a canonical local wall-clock timestamp")
    return timestamp
end

function fixed_offset_utc(local_timestamp, utc_offset_seconds)
    return local_timestamp - Second(utc_offset_seconds)
end

function next_business_day(date)
    candidate = date + Day(1)
    while dayofweek(candidate) > 5 ||
            candidate in AUDITED_US_FEDERAL_HOLIDAYS_2026
        candidate += Day(1)
    end
    return candidate
end

function validate_fixed_offset_timing(
        admission,
        prefix,
        expected_trigger_utc,
        expected_origin_utc,
    )
    origin_prefix =
        prefix == "reconstruction" ? "reconstruction_only" : prefix
    trigger_local = expect_local_timestamp(
        admission["$(prefix)_trigger_release_timestamp_local"],
        "plan.admission.$(prefix)_trigger_release_timestamp_local",
    )
    trigger_utc = expect_timestamp(
        admission["$(prefix)_trigger_release_timestamp_utc"],
        "plan.admission.$(prefix)_trigger_release_timestamp_utc",
    )
    origin_local = expect_local_timestamp(
        admission["$(origin_prefix)_origin_timestamp_local"],
        "plan.admission.$(origin_prefix)_origin_timestamp_local",
    )
    origin_utc = expect_timestamp(
        admission["$(origin_prefix)_origin_timestamp_utc"],
        "plan.admission.$(origin_prefix)_origin_timestamp_utc",
    )
    trigger_utc == expect_timestamp(
        expected_trigger_utc,
        "expected.$prefix.trigger",
    ) ||
        fail(
        "plan.admission.$(prefix)_trigger_release_timestamp_utc",
        "does not match the pinned as-of-plan trigger",
    )
    origin_utc == expect_timestamp(expected_origin_utc, "expected.$prefix.origin") ||
        fail(
        "plan.admission.$(origin_prefix)_origin_timestamp_utc",
        "does not match the pinned issue cutoff",
    )
    fixed_offset_utc(trigger_local, AUDITED_UTC_OFFSET_SECONDS) ==
        trigger_utc ||
        fail(
        "plan.admission.$(prefix)_trigger_release_timestamp_local",
        "does not convert to the declared UTC timestamp under the audited fixed offset",
    )
    fixed_offset_utc(origin_local, AUDITED_UTC_OFFSET_SECONDS) == origin_utc ||
        fail(
        "plan.admission.$(origin_prefix)_origin_timestamp_local",
        "does not convert to the declared UTC timestamp under the audited fixed offset",
    )
    dayofweek(Date(trigger_local)) <= 5 ||
        fail(
        "plan.admission.$(prefix)_trigger_release_timestamp_local",
        "trigger must fall on a weekday",
    )
    dayofweek(Date(origin_local)) <= 5 ||
        fail(
        "plan.admission.$(origin_prefix)_origin_timestamp_local",
        "origin must fall on a weekday",
    )
    Date(origin_local) == next_business_day(Date(trigger_local)) ||
        fail(
        "plan.admission.$(origin_prefix)_origin_timestamp_local",
        "must fall on the first business day after the trigger",
    )
    Time(trigger_local) == Time(8, 30) ||
        fail(
        "plan.admission.$(prefix)_trigger_release_timestamp_local",
        "trigger wall-clock time must equal 08:30",
    )
    Time(origin_local) == Time(10) ||
        fail(
        "plan.admission.$(origin_prefix)_origin_timestamp_local",
        "origin wall-clock time must equal 10:00",
    )
    return nothing
end

function expect_date(value, location)
    text = expect_string(value, location)
    occursin(DATE_PATTERN, text) ||
        fail(location, "must use YYYY-MM-DD")
    date = try
        Date(text)
    catch
        fail(location, "is not a valid date")
    end
    string(date) == text || fail(location, "is not a canonical date")
    return date
end

function expect_quarter(value, location)
    text = expect_string(value, location)
    occursin(QUARTER_PATTERN, text) ||
        fail(location, "must use YYYYQn")
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
        fail(
            "canonicalization",
            "unsupported value of type $(typeof(value))",
        )
    end
    return io
end

function canonical_sha256(value)
    io = IOBuffer()
    _canonical_write(io, value)
    return bytes2hex(sha256(take!(io)))
end

function backfill_plan_sha256(plan)
    copy = deepcopy(expect_table(plan, "plan"))
    artifact = expect_table(get(copy, "artifact", nothing), "plan.artifact")
    pop!(artifact, "content_sha256", nothing)
    return canonical_sha256(copy)
end

function stamp_backfill_plan_sha256!(plan)
    table = expect_table(plan, "plan")
    artifact = expect_table(get(table, "artifact", nothing), "plan.artifact")
    artifact["content_sha256"] = backfill_plan_sha256(table)
    return table
end

function validate_artifact(plan)
    artifact = expect_exact_keys(
        plan["artifact"],
        ARTIFACT_KEYS,
        "plan.artifact",
    )
    expect_string(artifact["schema_version"], "plan.artifact.schema_version") ==
        PLAN_SCHEMA ||
        fail("plan.artifact.schema_version", "must equal $PLAN_SCHEMA")
    expect_identifier(artifact["plan_id"], "plan.artifact.plan_id") ==
        PLAN_ID ||
        fail("plan.artifact.plan_id", "must equal $PLAN_ID")
    expect_string(artifact["status"], "plan.artifact.status") ==
        PLAN_STATUS ||
        fail("plan.artifact.status", "must equal $PLAN_STATUS")
    expect_date(artifact["as_of_date"], "plan.artifact.as_of_date")
    artifact["as_of_date"] == AS_OF_DATE ||
        fail("plan.artifact.as_of_date", "must equal $AS_OF_DATE")
    expect_hash(artifact["protocol_sha256"], "plan.artifact.protocol_sha256") ==
        PROTOCOL_SHA256 ||
        fail(
        "plan.artifact.protocol_sha256",
        "must equal the pinned forecasting protocol hash",
    )
    expect_hash(
        artifact["tier1_targets_sha256"],
        "plan.artifact.tier1_targets_sha256",
    ) == TIER1_TARGETS_SHA256 ||
        fail(
        "plan.artifact.tier1_targets_sha256",
        "must equal the pinned Tier-1 target-contract digest",
    )
    expect_string(
        artifact["canonicalization"],
        "plan.artifact.canonicalization",
    ) == CANONICALIZATION ||
        fail(
        "plan.artifact.canonicalization",
        "must equal $CANONICALIZATION",
    )
    expect_string(
        artifact["digest_algorithm"],
        "plan.artifact.digest_algorithm",
    ) == "sha256" ||
        fail("plan.artifact.digest_algorithm", "must equal sha256")
    stored_hash =
        expect_hash(artifact["content_sha256"], "plan.artifact.content_sha256")
    stored_hash == backfill_plan_sha256(plan) ||
        fail("plan.artifact.content_sha256", "does not match plan content")
    return artifact
end

function validate_admission(plan)
    admission = expect_exact_keys(
        plan["admission"],
        ADMISSION_KEYS,
        "plan.admission",
    )
    retrospective_count = expect_integer(
        admission["strict_retrospective_origin_count"],
        "plan.admission.strict_retrospective_origin_count",
    )
    retrospective_count == 0 ||
        fail(
        "plan.admission.strict_retrospective_origin_count",
        "must remain zero until a separately verified origin is admitted",
    )
    retrospective_origins = expect_string_array(
        admission["strict_retrospective_origin_timestamps_utc"],
        "plan.admission.strict_retrospective_origin_timestamps_utc",
    )
    isempty(retrospective_origins) ||
        fail(
        "plan.admission.strict_retrospective_origin_timestamps_utc",
        "must remain empty",
    )
    retrospective_count == length(retrospective_origins) ||
        fail("plan.admission", "retrospective count does not match timestamps")

    admission["timing_timezone_label"] == "America/New_York" ||
        fail(
        "plan.admission.timing_timezone_label",
        "must equal America/New_York",
    )
    admission["timing_conversion_method"] ==
        "AUDITED_FIXED_UTC_OFFSET_NO_IANA_RUNTIME" ||
        fail(
        "plan.admission.timing_conversion_method",
        "must disclose the audited fixed-offset conversion method",
    )
    expect_integer(
        admission["timing_utc_offset_seconds"],
        "plan.admission.timing_utc_offset_seconds",
    ) == AUDITED_UTC_OFFSET_SECONDS ||
        fail(
        "plan.admission.timing_utc_offset_seconds",
        "must equal the audited EDT offset for these dates",
    )
    admission["timing_offset_scope"] ==
        "ONLY_2026-07-30_THROUGH_2026-10-30_REVALIDATE_BEFORE_CAPTURE" ||
        fail(
        "plan.admission.timing_offset_scope",
        "must disclose the narrow fixed-offset audit scope",
    )
    validate_fixed_offset_timing(
        admission,
        "reconstruction",
        RECONSTRUCTION_TRIGGER,
        RECONSTRUCTION_ORIGIN,
    )
    validate_fixed_offset_timing(
        admission,
        "planned_first_prospective",
        PROSPECTIVE_TRIGGER,
        PROSPECTIVE_ORIGIN,
    )
    admission["reconstruction_evidence_class"] ==
        "reconstructed_after_origin" ||
        fail(
        "plan.admission.reconstruction_evidence_class",
        "must equal reconstructed_after_origin",
    )
    admission["reconstruction_status"] == "CANNOT_RUN" ||
        fail(
        "plan.admission.reconstruction_status",
        "must equal CANNOT_RUN",
    )
    !expect_bool(
        admission["reconstruction_runnable"],
        "plan.admission.reconstruction_runnable",
    ) ||
        fail(
        "plan.admission.reconstruction_runnable",
        "a reconstruction cannot be runnable as a strict origin",
    )
    !expect_bool(
        admission["reconstruction_promotion_eligible"],
        "plan.admission.reconstruction_promotion_eligible",
    ) ||
        fail(
        "plan.admission.reconstruction_promotion_eligible",
        "a reconstruction cannot be promotion eligible",
    )

    admission["planned_first_prospective_capture_deadline_utc"] ==
        PROSPECTIVE_ORIGIN ||
        fail(
        "plan.admission.planned_first_prospective_capture_deadline_utc",
        "must equal the prospective issue cutoff",
    )
    expect_timestamp(
        admission["planned_first_prospective_capture_deadline_utc"],
        "plan.admission.planned_first_prospective_capture_deadline_utc",
    )
    expect_quarter(
        admission["planned_first_prospective_reference_quarter"],
        "plan.admission.planned_first_prospective_reference_quarter",
    ) == "2026Q3" ||
        fail(
        "plan.admission.planned_first_prospective_reference_quarter",
        "must equal 2026Q3",
    )
    admission["planned_first_prospective_origin_rule"] ==
        "FIRST_BUSINESS_DAY_AFTER_BEA_ADVANCE_AT_10:00_AMERICA/NEW_YORK" ||
        fail(
        "plan.admission.planned_first_prospective_origin_rule",
        "must match the pinned quarterly issue rule",
    )
    admission["planned_first_prospective_schedule_locator"] ==
        "https://www.bea.gov/news/schedule" ||
        fail(
        "plan.admission.planned_first_prospective_schedule_locator",
        "must point to the official BEA schedule",
    )
    admission["planned_first_prospective_schedule_locator_role"] ==
        "MUTABLE_OFFICIAL_DISCOVERY_ROUTE_NOT_IMMUTABLE_EVENT_EVIDENCE" ||
        fail(
        "plan.admission.planned_first_prospective_schedule_locator_role",
        "must not overclaim a mutable schedule page as immutable evidence",
    )
    expect_bool(
        admission["planned_first_prospective_schedule_revalidation_required"],
        "plan.admission.planned_first_prospective_schedule_revalidation_required",
    ) ||
        fail(
        "plan.admission.planned_first_prospective_schedule_revalidation_required",
        "must be true",
    )
    admission["planned_first_prospective_schedule_snapshot_receipt_status"] ==
        "NO_IMMUTABLE_SNAPSHOT_RECEIPT" ||
        fail(
        "plan.admission.planned_first_prospective_schedule_snapshot_receipt_status",
        "must remain NO_IMMUTABLE_SNAPSHOT_RECEIPT",
    )
    admission["planned_first_prospective_trigger_capture_receipt_status"] ==
        "NO_IMMUTABLE_TRIGGER_CAPTURE_RECEIPT" ||
        fail(
        "plan.admission.planned_first_prospective_trigger_capture_receipt_status",
        "must remain NO_IMMUTABLE_TRIGGER_CAPTURE_RECEIPT",
    )
    expect_integer(
        admission["planned_first_prospective_trigger_capture_receipt_count"],
        "plan.admission.planned_first_prospective_trigger_capture_receipt_count",
    ) == 0 ||
        fail(
        "plan.admission.planned_first_prospective_trigger_capture_receipt_count",
        "must remain zero in this plan-only artifact",
    )
    admission["planned_first_prospective_complete_origin_receipt_status"] ==
        "NO_IMMUTABLE_COMPLETE_ORIGIN_RECEIPT" ||
        fail(
        "plan.admission.planned_first_prospective_complete_origin_receipt_status",
        "must remain NO_IMMUTABLE_COMPLETE_ORIGIN_RECEIPT",
    )
    expect_integer(
        admission["planned_first_prospective_complete_origin_receipt_count"],
        "plan.admission.planned_first_prospective_complete_origin_receipt_count",
    ) == 0 ||
        fail(
        "plan.admission.planned_first_prospective_complete_origin_receipt_count",
        "must remain zero in this plan-only artifact",
    )
    admission["planned_first_prospective_missed_deadline_policy"] ==
        "FAIL_CI_AND_SUPERSEDE_PLAN" ||
        fail(
        "plan.admission.planned_first_prospective_missed_deadline_policy",
        "must fail closed after a missed capture deadline",
    )
    admission["planned_first_prospective_status"] ==
        "PLANNED_NOT_CAPTURED_NOT_ADMITTED" ||
        fail(
        "plan.admission.planned_first_prospective_status",
        "must remain planned, uncaptured, and unadmitted",
    )
    for field in (
            "planned_first_prospective_admitted",
            "planned_first_prospective_ready",
            "accuracy_evaluation_allowed",
        )
        !expect_bool(admission[field], "plan.admission.$field") ||
            fail("plan.admission.$field", "must be false")
    end
    return admission
end

function validate_inventory_guard(plan)
    guard = expect_exact_keys(
        plan["inventory_guard"],
        INVENTORY_GUARD_KEYS,
        "plan.inventory_guard",
    )
    expect_string(
        guard["inventory_locator"],
        "plan.inventory_guard.inventory_locator",
    ) == INVENTORY_LOCATOR ||
        fail(
        "plan.inventory_guard.inventory_locator",
        "must equal $INVENTORY_LOCATOR",
    )
    guard["inventory_schema_version"] == INVENTORY_SCHEMA ||
        fail(
        "plan.inventory_guard.inventory_schema_version",
        "must equal $INVENTORY_SCHEMA",
    )
    expect_hash(
        guard["expected_inventory_sha256"],
        "plan.inventory_guard.expected_inventory_sha256",
    ) == INVENTORY_SHA256 ||
        fail(
        "plan.inventory_guard.expected_inventory_sha256",
        "must pin the unchanged empty inventory",
    )
    for field in (
            "required_release_event_count",
            "required_admissible_origin_count",
        )
        expect_integer(guard[field], "plan.inventory_guard.$field") == 0 ||
            fail("plan.inventory_guard.$field", "must equal zero")
    end
    !expect_bool(
        guard["plan_may_mutate_inventory"],
        "plan.inventory_guard.plan_may_mutate_inventory",
    ) ||
        fail(
        "plan.inventory_guard.plan_may_mutate_inventory",
        "a research plan may not mutate the release inventory",
    )
    return guard
end

function validate_precision_policy(plan)
    policy = expect_exact_keys(
        plan["precision_policy"],
        PRECISION_POLICY_KEYS,
        "plan.precision_policy",
    )
    policy["exact_timestamp_format"] == "RFC3339_seconds_Z" ||
        fail(
        "plan.precision_policy.exact_timestamp_format",
        "must equal RFC3339_seconds_Z",
    )
    for field in (
            "exact_intraday_evidence_required",
            "raw_release_bytes_required",
            "raw_sha256_required",
            "first_state_bytes_required",
        )
        expect_bool(policy[field], "plan.precision_policy.$field") ||
            fail("plan.precision_policy.$field", "must be true")
    end
    for field in (
            "date_only_origin_eligible",
            "no_time_origin_eligible",
            "mixed_precision_origin_eligible_without_event_resolution",
            "retrieval_time_may_substitute_for_release_time",
            "route_level_claim_may_substitute_for_event_evidence",
        )
        !expect_bool(policy[field], "plan.precision_policy.$field") ||
            fail("plan.precision_policy.$field", "must be false")
    end
    return policy
end

function validate_licensing(plan)
    licensing = expect_exact_keys(
        plan["licensing"],
        LICENSING_KEYS,
        "plan.licensing",
    )
    licensing["bea_terms_locator"] == BEA_TERMS_LOCATOR ||
        fail(
        "plan.licensing.bea_terms_locator",
        "must point to the reviewed official BEA source-use policy",
    )
    expect_date(
        licensing["bea_terms_review_as_of_date"],
        "plan.licensing.bea_terms_review_as_of_date",
    ) == Date(BEA_TERMS_REVIEW_DATE) ||
        fail(
        "plan.licensing.bea_terms_review_as_of_date",
        "must equal $BEA_TERMS_REVIEW_DATE",
    )
    expect_bool(
        licensing["bea_terms_recheck_before_acquisition"],
        "plan.licensing.bea_terms_recheck_before_acquisition",
    ) ||
        fail(
        "plan.licensing.bea_terms_recheck_before_acquisition",
        "must be true",
    )
    licensing["bea_public_domain_status"] ==
        "PUBLIC_DOMAIN_UNLESS_OTHERWISE_STATED" ||
        fail(
        "plan.licensing.bea_public_domain_status",
        "must preserve the qualification in the official BEA policy",
    )
    licensing["bea_attribution_policy"] ==
        "SOURCE_ATTRIBUTION_APPRECIATED_AND_REQUIRED_BY_THIS_PLAN" ||
        fail(
        "plan.licensing.bea_attribution_policy",
        "must preserve source attribution as a plan requirement",
    )
    licensing["bls_copyright_locator"] == BLS_COPYRIGHT_LOCATOR ||
        fail(
        "plan.licensing.bls_copyright_locator",
        "must point to the reviewed official BLS copyright policy",
    )
    licensing["bls_developer_terms_locator"] ==
        BLS_DEVELOPER_TERMS_LOCATOR ||
        fail(
        "plan.licensing.bls_developer_terms_locator",
        "must point to the reviewed official BLS developer terms",
    )
    expect_date(
        licensing["bls_terms_review_as_of_date"],
        "plan.licensing.bls_terms_review_as_of_date",
    ) == Date(BLS_TERMS_REVIEW_DATE) ||
        fail(
        "plan.licensing.bls_terms_review_as_of_date",
        "must equal $BLS_TERMS_REVIEW_DATE",
    )
    expect_bool(
        licensing["bls_terms_recheck_before_acquisition"],
        "plan.licensing.bls_terms_recheck_before_acquisition",
    ) ||
        fail(
        "plan.licensing.bls_terms_recheck_before_acquisition",
        "must be true",
    )
    licensing["bls_public_domain_status"] ==
        "PUBLIC_DOMAIN_EXCEPT_PREVIOUSLY_COPYRIGHTED_PHOTOGRAPHS_AND_ILLUSTRATIONS" ||
        fail(
        "plan.licensing.bls_public_domain_status",
        "must preserve the qualifications in the official BLS policy",
    )
    licensing["bls_attribution_policy"] ==
        "CITE_BLS_SOURCE_ACCESS_DATE_AND_API_DISCLAIMER_WHEN_APPLICABLE_NO_EMBLEM" ||
        fail(
        "plan.licensing.bls_attribution_policy",
        "must preserve BLS attribution, conditional API, and emblem restrictions",
    )
    for field in (
            "bls_api_access_date_required",
            "bls_api_disclaimer_required",
            "bls_terms_recheck_before_acquisition",
            "bls_plan_authorizes_byte_acquisition",
        )
        expect_bool(licensing[field], "plan.licensing.$field") ||
            fail("plan.licensing.$field", "must be true")
    end
    !expect_bool(
        licensing["bls_emblem_use_allowed"],
        "plan.licensing.bls_emblem_use_allowed",
    ) ||
        fail(
        "plan.licensing.bls_emblem_use_allowed",
        "must remain false",
    )
    licensing["fred_alfred_warehouse_status"] ==
        "EXCLUDED_PENDING_WRITTEN_CLEARANCE" ||
        fail(
        "plan.licensing.fred_alfred_warehouse_status",
        "must exclude FRED/ALFRED pending written clearance",
    )
    licensing["fred_alfred_terms_locator"] ==
        "https://fred.stlouisfed.org/legal/terms/" ||
        fail(
        "plan.licensing.fred_alfred_terms_locator",
        "must point to the reviewed official FRED terms",
    )
    expect_date(
        licensing["fred_alfred_terms_review_as_of_date"],
        "plan.licensing.fred_alfred_terms_review_as_of_date",
    ) == Date(AS_OF_DATE) ||
        fail(
        "plan.licensing.fred_alfred_terms_review_as_of_date",
        "must equal the plan audit date",
    )
    expect_bool(
        licensing["fred_alfred_terms_recheck_before_use"],
        "plan.licensing.fred_alfred_terms_recheck_before_use",
    ) ||
        fail(
        "plan.licensing.fred_alfred_terms_recheck_before_use",
        "must be true",
    )
    expect_bool(
        licensing["written_clearance_required"],
        "plan.licensing.written_clearance_required",
    ) ||
        fail(
        "plan.licensing.written_clearance_required",
        "must be true",
    )
    for field in (
            "cache_allowed_without_clearance",
            "archive_allowed_without_clearance",
            "software_or_ai_use_allowed_without_clearance",
        )
        !expect_bool(licensing[field], "plan.licensing.$field") ||
            fail("plan.licensing.$field", "must be false")
    end
    licensing["permitted_unresolved_role"] ==
        "DISCOVERY_METADATA_ONLY_NO_DATA_COPY" ||
        fail(
        "plan.licensing.permitted_unresolved_role",
        "must remain discovery metadata only",
    )
    licensing["rtdsm_role"] ==
        "CROSS_CHECK_ONLY_NOT_INTRADAY_AVAILABILITY_EVIDENCE" ||
        fail(
        "plan.licensing.rtdsm_role",
        "must remain a cross-check only",
    )
    licensing["frbny_reference_rates_terms_locator"] ==
        "https://www.newyorkfed.org/privacy/termsofuse" ||
        fail(
        "plan.licensing.frbny_reference_rates_terms_locator",
        "must point to the official FRBNY terms",
    )
    expect_date(
        licensing["frbny_terms_review_as_of_date"],
        "plan.licensing.frbny_terms_review_as_of_date",
    ) == Date(AS_OF_DATE) ||
        fail(
        "plan.licensing.frbny_terms_review_as_of_date",
        "must equal the plan audit date",
    )
    for field in (
            "frbny_terms_recheck_before_acquisition",
            "frbny_reference_rate_notice_required",
            "frbny_attribution_required",
        )
        expect_bool(licensing[field], "plan.licensing.$field") ||
            fail("plan.licensing.$field", "must be true")
    end
    !expect_bool(
        licensing["frbny_plan_authorizes_byte_acquisition"],
        "plan.licensing.frbny_plan_authorizes_byte_acquisition",
    ) ||
        fail(
        "plan.licensing.frbny_plan_authorizes_byte_acquisition",
        "must remain false pending acquisition-time terms review",
    )
    return licensing
end

function validate_pilot(pilot, location)
    pilot = expect_exact_keys(pilot, PILOT_KEYS, location)
    pilot_id = expect_identifier(pilot["pilot_id"], "$location.pilot_id")
    haskey(EXPECTED_PILOTS, pilot_id) ||
        fail("$location.pilot_id", "is not a required pilot")
    expected = EXPECTED_PILOTS[pilot_id]
    expect_quarter(pilot["reference_quarter"], "$location.reference_quarter")
    expect_one_of(pilot["pilot_kind"], PILOT_KINDS, "$location.pilot_kind")
    expect_one_of(
        pilot["evidence_class"],
        PILOT_EVIDENCE_CLASSES,
        "$location.evidence_class",
    )
    expect_one_of(
        pilot["origin_timestamp_status"],
        PILOT_TIMESTAMP_STATUSES,
        "$location.origin_timestamp_status",
    )
    expect_string(pilot["origin_timestamp_utc"], "$location.origin_timestamp_utc")
    for (field, value) in expected
        pilot[field] == value ||
            fail("$location.$field", "does not match required pilot contract")
    end
    if pilot["origin_timestamp_status"] == "NOT_ESTABLISHED"
        pilot["origin_timestamp_utc"] == UNESTABLISHED_TIMESTAMP ||
            fail(
            "$location.origin_timestamp_utc",
            "must use $UNESTABLISHED_TIMESTAMP when no exact time is established",
        )
    else
        expect_timestamp(
            pilot["origin_timestamp_utc"],
            "$location.origin_timestamp_utc",
        )
    end
    !expect_bool(pilot["runnable"], "$location.runnable") ||
        fail("$location.runnable", "must be false")
    !expect_bool(pilot["promotion_eligible"], "$location.promotion_eligible") ||
        fail("$location.promotion_eligible", "must be false")
    expect_string(pilot["purpose"], "$location.purpose")
    return pilot_id
end

function validate_pilots(plan)
    pilots = expect_array(
        plan["pilot_origins"],
        "plan.pilot_origins";
        allow_empty = false,
    )
    pilot_ids = String[]
    for (index, pilot) in enumerate(pilots)
        push!(
            pilot_ids,
            validate_pilot(pilot, "plan.pilot_origins[$index]"),
        )
    end
    pilot_ids == sort!(collect(keys(EXPECTED_PILOTS))) ||
        fail(
        "plan.pilot_origins",
        "must contain the six required pilots sorted by pilot_id",
    )
    return pilots
end

function validate_source_route(route, location)
    route = expect_exact_keys(route, SOURCE_KEYS, location)
    route_id = expect_identifier(route["route_id"], "$location.route_id")
    haskey(EXPECTED_SOURCE_FACTS, route_id) ||
        fail("$location.route_id", "is not a required source route")
    expected = EXPECTED_SOURCE_FACTS[route_id]
    for field in (
            "provider",
            "source_family",
            "role",
            "discovery_locator",
            "locator_role",
            "exact_release_byte_locator_status",
            "archive_identifier",
            "discovery_schema",
            "terms_locator",
            "terms_review_status",
            "redistribution_status",
            "attribution_requirement",
            "archive_start",
            "coverage_detail",
            "timestamp_detail",
            "first_state_status",
            "method_break",
            "route_status",
            "blocker_code",
        )
        expect_string(route[field], "$location.$field")
    end
    for (field, value) in expected
        route[field] == value ||
            fail("$location.$field", "does not match audited source fact")
    end
    provider, source_family = EXPECTED_SOURCE_IDENTITIES[route_id]
    route["provider"] == provider ||
        fail("$location.provider", "does not match the official source")
    route["source_family"] == source_family ||
        fail("$location.source_family", "does not match the source route")
    discovery = EXPECTED_SOURCE_DISCOVERY[route_id]
    for field in (
            "discovery_locator",
            "archive_identifier",
            "discovery_schema",
            "terms_locator",
            "terms_review_status",
            "redistribution_status",
            "attribution_requirement",
        )
        route[field] == getproperty(discovery, Symbol(field)) ||
            fail("$location.$field", "does not match audited route metadata")
    end
    route["locator_role"] == DISCOVERY_LOCATOR_ROLE ||
        fail(
        "$location.locator_role",
        "must distinguish discovery from exact release-byte identity",
    )
    route["exact_release_byte_locator_status"] ==
        EXACT_RELEASE_LOCATOR_STATUS ||
        fail(
        "$location.exact_release_byte_locator_status",
        "must remain unresolved until immutable release bytes are registered",
    )
    expect_one_of(
        route["bytes_status"],
        BYTE_STATUSES,
        "$location.bytes_status",
    )
    expect_one_of(
        route["timestamp_evidence_class"],
        TIMESTAMP_EVIDENCE_CLASSES,
        "$location.timestamp_evidence_class",
    )
    expect_one_of(
        route["route_status"],
        ROUTE_STATUSES,
        "$location.route_status",
    )
    startswith(route["discovery_locator"], "https://") ||
        fail("$location.discovery_locator", "must be an HTTPS locator")
    series_identifiers = expect_string_array(
        route["series_identifiers"],
        "$location.series_identifiers",
    )
    issorted(series_identifiers) ||
        fail("$location.series_identifiers", "must be sorted")
    series_identifiers == discovery.series_identifiers ||
        fail(
        "$location.series_identifiers",
        "does not match the audited source series identifiers",
    )
    formats = expect_string_array(
        route["published_artifact_formats"],
        "$location.published_artifact_formats";
        allow_empty = false,
    )
    issorted(formats) ||
        fail("$location.published_artifact_formats", "must be sorted")
    targets =
        expect_string_array(route["target_ids"], "$location.target_ids")
    issorted(targets) || fail("$location.target_ids", "must be sorted")
    expected_targets = get(EXPECTED_TARGETS_BY_ROUTE, route_id, Set{String}())
    Set(targets) == expected_targets ||
        fail("$location.target_ids", "does not match the route target contract")
    expect_bool(
        route["required_for_strict_origin"],
        "$location.required_for_strict_origin",
    ) ||
        fail("$location.required_for_strict_origin", "must be true")
    !expect_bool(
        route["release_bytes_registered"],
        "$location.release_bytes_registered",
    ) ||
        fail(
        "$location.release_bytes_registered",
        "must remain false until bytes are separately registered",
    )
    expect_integer(
        route["registered_release_event_count"],
        "$location.registered_release_event_count",
    ) == 0 ||
        fail("$location.registered_release_event_count", "must equal zero")
    !expect_bool(route["origin_admissible"], "$location.origin_admissible") ||
        fail(
        "$location.origin_admissible",
        "a plan-only route cannot be origin admissible",
    )
    priority =
        expect_integer(route["acquisition_priority"], "$location.acquisition_priority")
    1 <= priority <= length(EXPECTED_STAGES) ||
        fail("$location.acquisition_priority", "is outside the stage range")
    return route_id, Set(targets), priority
end

function validate_source_routes(plan)
    routes = expect_array(
        plan["source_routes"],
        "plan.source_routes";
        allow_empty = false,
    )
    route_ids = String[]
    covered_targets = Set{String}()
    priority_by_route = Dict{String, Int}()
    for (index, route) in enumerate(routes)
        route_id, targets, priority =
            validate_source_route(route, "plan.source_routes[$index]")
        push!(route_ids, route_id)
        union!(covered_targets, targets)
        priority_by_route[route_id] = priority
    end
    route_ids == sort!(collect(keys(EXPECTED_SOURCE_FACTS))) ||
        fail(
        "plan.source_routes",
        "must contain all audited source routes sorted by route_id",
    )
    covered_targets == TIER1_TARGET_IDS ||
        fail(
        "plan.source_routes",
        "must map each of the eight Tier-1 targets exactly once",
    )
    return priority_by_route
end

function validate_acquisition_stages(plan, priority_by_route)
    stages = expect_array(
        plan["acquisition_stages"],
        "plan.acquisition_stages";
        allow_empty = false,
    )
    length(stages) == length(EXPECTED_STAGES) ||
        fail(
        "plan.acquisition_stages",
        "must contain $(length(EXPECTED_STAGES)) stages",
    )
    seen_routes = Set{String}()
    for (index, stage) in enumerate(stages)
        location = "plan.acquisition_stages[$index]"
        stage = expect_exact_keys(stage, STAGE_KEYS, location)
        stage_number = expect_integer(stage["stage"], "$location.stage")
        stage_number == index ||
            fail("$location.stage", "must be sequential and array ordered")
        haskey(EXPECTED_STAGES, stage_number) ||
            fail("$location.stage", "is not a required stage")
        expected_id, expected_routes = EXPECTED_STAGES[stage_number]
        expect_identifier(stage["stage_id"], "$location.stage_id") ==
            expected_id ||
            fail("$location.stage_id", "does not match required stage")
        route_ids = expect_string_array(
            stage["route_ids"],
            "$location.route_ids";
            allow_empty = false,
        )
        issorted(route_ids) ||
            fail("$location.route_ids", "must be sorted")
        Set(route_ids) == expected_routes ||
            fail("$location.route_ids", "does not match required stage routes")
        isempty(intersect(seen_routes, expected_routes)) ||
            fail("$location.route_ids", "a route appears in multiple stages")
        union!(seen_routes, expected_routes)
        all(priority_by_route[route_id] == stage_number for route_id in route_ids) ||
            fail(
            "$location.route_ids",
            "route acquisition priorities must equal their stage",
        )
        entry_condition =
            expect_string(stage["entry_condition"], "$location.entry_condition")
        exit_condition =
            expect_string(stage["exit_condition"], "$location.exit_condition")
        expected_entry, expected_exit =
            EXPECTED_STAGE_CONDITIONS[stage_number]
        entry_condition == expected_entry ||
            fail(
            "$location.entry_condition",
            "does not match the audited machine-pinned stage criterion",
        )
        exit_condition == expected_exit ||
            fail(
            "$location.exit_condition",
            "does not match the audited machine-pinned stage criterion",
        )
        stage["status"] == "PLANNED_NOT_STARTED" ||
            fail("$location.status", "must equal PLANNED_NOT_STARTED")
    end
    seen_routes == Set(keys(EXPECTED_SOURCE_FACTS)) ||
        fail(
        "plan.acquisition_stages",
        "must cover every source route exactly once",
    )
    return stages
end

function validate_backfill_plan(plan)
    plan = expect_exact_keys(plan, ROOT_KEYS, "plan")
    validate_artifact(plan)
    validate_admission(plan)
    validate_inventory_guard(plan)
    validate_precision_policy(plan)
    validate_licensing(plan)
    validate_pilots(plan)
    priority_by_route = validate_source_routes(plan)
    validate_acquisition_stages(plan, priority_by_route)
    return plan
end

function load_backfill_plan(path::AbstractString)
    plan = TOML.parsefile(path)
    validate_backfill_plan(plan)
    return plan
end

function validate_contract_alignment(
        plan,
        protocol_sha256::AbstractString,
        tier1_targets_sha256::AbstractString,
    )
    validate_backfill_plan(plan)
    artifact = plan["artifact"]
    String(protocol_sha256) == artifact["protocol_sha256"] ||
        fail(
        "plan.artifact.protocol_sha256",
        "does not match the live protocol.toml semantic digest",
    )
    String(tier1_targets_sha256) == artifact["tier1_targets_sha256"] ||
        fail(
        "plan.artifact.tier1_targets_sha256",
        "does not match the live tier1_targets.toml contract digest",
    )
    return plan
end

function validate_prospective_capture_deadline(
        plan,
        observed_at_utc::DateTime = now(UTC),
    )
    validate_backfill_plan(plan)
    admission = plan["admission"]
    trigger = expect_timestamp(
        admission[
            "planned_first_prospective_trigger_release_timestamp_utc",
        ],
        "plan.admission.planned_first_prospective_trigger_release_timestamp_utc",
    )
    origin = expect_timestamp(
        admission["planned_first_prospective_capture_deadline_utc"],
        "plan.admission.planned_first_prospective_capture_deadline_utc",
    )
    if observed_at_utc >= origin
        complete_receipt_count =
            admission[
            "planned_first_prospective_complete_origin_receipt_count",
        ]
        complete_receipt_status =
            admission[
            "planned_first_prospective_complete_origin_receipt_status",
        ]
        if complete_receipt_count == 0 ||
                complete_receipt_status !=
                "IMMUTABLE_COMPLETE_ORIGIN_RECEIPT_VERIFIED" ||
                !admission["planned_first_prospective_admitted"]
            fail(
                "plan.admission.planned_first_prospective_capture_deadline_utc",
                "the complete-origin receipt and admission transition are absent at or after the prospective origin; fail CI and supersede this plan",
            )
        end
    elseif observed_at_utc >= trigger
        trigger_receipt_count =
            admission[
            "planned_first_prospective_trigger_capture_receipt_count",
        ]
        trigger_receipt_status =
            admission[
            "planned_first_prospective_trigger_capture_receipt_status",
        ]
        if trigger_receipt_count == 0 ||
                trigger_receipt_status !=
                "IMMUTABLE_TRIGGER_CAPTURE_RECEIPT_VERIFIED"
            fail(
                "plan.admission.planned_first_prospective_trigger_release_timestamp_utc",
                "the immutable trigger-release capture receipt is absent at or after the scheduled trigger; fail CI and investigate immediately",
            )
        end
    end
    return observed_at_utc
end

function validate_inventory_alignment(plan, inventory)
    validate_backfill_plan(plan)
    inventory = expect_table(inventory, "inventory")
    guard = plan["inventory_guard"]
    artifact = expect_table(
        get(inventory, "artifact", nothing),
        "inventory.artifact",
    )
    expect_string(
        get(artifact, "schema_version", nothing),
        "inventory.artifact.schema_version",
    ) == guard["inventory_schema_version"] ||
        fail(
        "inventory.artifact.schema_version",
        "does not match the backfill-plan guard",
    )
    expect_hash(
        get(artifact, "content_sha256", nothing),
        "inventory.artifact.content_sha256",
    ) == guard["expected_inventory_sha256"] ||
        fail(
        "inventory.artifact.content_sha256",
        "does not match the pinned empty inventory",
    )
    inventory_copy = deepcopy(inventory)
    inventory_copy_artifact =
        expect_table(inventory_copy["artifact"], "inventory.artifact")
    stored_inventory_hash =
        pop!(inventory_copy_artifact, "content_sha256", nothing)
    canonical_sha256(inventory_copy) == stored_inventory_hash ||
        fail(
        "inventory.artifact.content_sha256",
        "does not match inventory content",
    )
    events = expect_array(
        get(inventory, "release_events", nothing),
        "inventory.release_events",
    )
    length(events) == guard["required_release_event_count"] ||
        fail(
        "inventory.release_events",
        "count does not match the zero-event guard",
    )
    origins = expect_array(
        get(inventory, "admissible_origin_timestamps_utc", nothing),
        "inventory.admissible_origin_timestamps_utc",
    )
    length(origins) == guard["required_admissible_origin_count"] ||
        fail(
        "inventory.admissible_origin_timestamps_utc",
        "count does not match the zero-origin guard",
    )
    return inventory
end

function validate_inventory_alignment(
        plan,
        inventory_path::AbstractString,
    )
    return validate_inventory_alignment(plan, TOML.parsefile(inventory_path))
end

end
