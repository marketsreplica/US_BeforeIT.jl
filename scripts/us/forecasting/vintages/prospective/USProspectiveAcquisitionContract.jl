module USProspectiveAcquisitionContract

using Dates
using SHA
using TOML

export ProspectiveContractValidationError,
    contract_sha256,
    evaluate_governance,
    evaluate_receipt_evidence,
    load_contract,
    stamp_contract_sha256!,
    validate_contract,
    validate_receipt

const CONTRACT_SCHEMA =
    "beforeit-us-prospective-acquisition-requirements.v2-draft"
const CONTRACT_ID = "beforeit-us-prospective-2026q3-acquisition.v1"
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
        "verifier",
        "approval",
        "retention",
        "requirements",
        "fixed_events",
        "recurring_windows",
        "snapshot_campaigns",
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
const RECEIPT_KEYS = Set(
    [
        "receipt_id",
        "event_id",
        "requirement_id",
        "retrieved_at_utc",
        "receipt_completed_at_utc",
        "availability_upper_bound_utc",
        "availability_basis",
        "raw_sha256",
        "receipt_sha256",
        "receipt_artifact_status",
        "durable_storage_status",
        "retain_until_utc",
    ],
)

const ARTIFACT_STATUSES = Set(
    [
        "DRAFT_UNAPPROVED_FAIL_CLOSED",
        "VERIFIER_READY_REQUIREMENTS_UNAPPROVED",
        "APPROVED_REQUIREMENTS_VERIFIER_BLOCKED",
        "GOVERNANCE_ACTIVE_ORIGIN_NOT_ADMITTED",
    ],
)
const VERIFIER_STATUSES =
    Set(["NOT_IMPLEMENTED_FAIL_CLOSED", "IMPLEMENTED_AND_VERIFIED"])
const RECEIPT_VERIFICATION_STATUSES =
    Set(["NOT_VERIFIED", "VERIFIED"])
const APPROVAL_STATUSES = Set(["DRAFT_UNAPPROVED", "APPROVED"])
const BLOCK_KINDS = Set(["source", "target", "structural"])
const ACQUISITION_MODES = Set(
    [
        "fixed_release",
        "fixed_and_recurring_release",
        "pre_origin_snapshot",
        "fixed_release_and_pre_origin_snapshot",
    ],
)
const TIMESTAMP_BASES =
    Set(["official_exact", "official_approximate_window"])
const EVENT_PURPOSES = Set(
    [
        "capture_rehearsal",
        "latest_structural_release",
        "latest_pre_origin_release",
        "annual_structure_and_history_refresh",
        "trigger_release",
        "last_eligible_daily_rate",
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
const REQUIRED_REQUIREMENT_IDS = Set(
    [
        "bea_fixed_assets_structural",
        "bea_industry_io_structural",
        "bea_nipa_tier1",
        "bls_cps_structural",
        "bls_employment_tier1",
        "bls_qcew_structural",
        "census_susb_structural",
        "classification_maps",
        "frb_z1_structural",
        "frbny_effr_tier1",
        "usda_counts_structural",
    ],
)
const REQUIRED_SOURCE_BY_REQUIREMENT = Dict(
    "bea_fixed_assets_structural" => "bea_fixed_assets_hmi11",
    "bea_industry_io_structural" => "bea_industry_hmi8",
    "bea_nipa_tier1" => "bea_nipa_hmi7",
    "bls_cps_structural" => "bls_cps_structural_controls",
    "bls_employment_tier1" => "bls_employment_situation",
    "bls_qcew_structural" => "bls_qcew",
    "census_susb_structural" => "census_susb",
    "classification_maps" => "official_classification_maps",
    "frb_z1_structural" => "frb_z1",
    "frbny_effr_tier1" => "frbny_effr",
    "usda_counts_structural" => "usda_structural_counts",
)
const EXPECTED_FIXED_EVENTS = [
    (
        event_id = "bls_employment_situation_2026_07",
        source_id = "bls_employment_situation",
        requirement_ids = ["bls_employment_tier1"],
        reference_period = "2026-07",
        official_schedule_locator =
            "https://www.bls.gov/schedule/news_release/empsit.htm",
        scheduled_timestamp_utc = "2026-08-07T12:30:00Z",
        timestamp_basis = "official_exact",
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
        scheduled_timestamp_utc = "2026-08-28T14:00:00Z",
        timestamp_basis = "official_exact",
        capture_not_before_utc = "2026-08-28T14:00:00Z",
        capture_deadline_utc = "2026-08-28T14:15:00Z",
        event_purpose = "latest_structural_release",
        required_for_complete_origin = true,
    ),
    (
        event_id = "bls_employment_situation_2026_08",
        source_id = "bls_employment_situation",
        requirement_ids = ["bls_employment_tier1"],
        reference_period = "2026-08",
        official_schedule_locator =
            "https://www.bls.gov/schedule/news_release/empsit.htm",
        scheduled_timestamp_utc = "2026-09-04T12:30:00Z",
        timestamp_basis = "official_exact",
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
        scheduled_timestamp_utc = "2026-09-11T16:00:00Z",
        timestamp_basis = "official_exact",
        capture_not_before_utc = "2026-09-11T16:00:00Z",
        capture_deadline_utc = "2026-09-11T16:15:00Z",
        event_purpose = "latest_structural_release",
        required_for_complete_origin = true,
    ),
    (
        event_id = "bea_annual_update_2026",
        source_id = "bea_annual_update_2026",
        requirement_ids = [
            "bea_industry_io_structural",
            "bea_nipa_tier1",
        ],
        reference_period = "2026-annual-update",
        official_schedule_locator = "https://www.bea.gov/news/schedule",
        scheduled_timestamp_utc = "2026-09-30T12:30:00Z",
        timestamp_basis = "official_exact",
        capture_not_before_utc = "2026-09-30T12:30:00Z",
        capture_deadline_utc = "2026-09-30T13:30:00Z",
        event_purpose = "annual_structure_and_history_refresh",
        required_for_complete_origin = true,
    ),
    (
        event_id = "bls_employment_situation_2026_09",
        source_id = "bls_employment_situation",
        requirement_ids = ["bls_employment_tier1"],
        reference_period = "2026-09",
        official_schedule_locator =
            "https://www.bls.gov/schedule/news_release/empsit.htm",
        scheduled_timestamp_utc = "2026-10-02T12:30:00Z",
        timestamp_basis = "official_exact",
        capture_not_before_utc = "2026-10-02T12:30:00Z",
        capture_deadline_utc = "2026-10-02T12:45:00Z",
        event_purpose = "latest_pre_origin_release",
        required_for_complete_origin = true,
    ),
    (
        event_id = "bea_gdp_2026q3_advance",
        source_id = "bea_nipa_hmi7",
        requirement_ids = ["bea_nipa_tier1"],
        reference_period = "2026Q3",
        official_schedule_locator = "https://www.bea.gov/news/schedule",
        scheduled_timestamp_utc = "2026-10-29T12:30:00Z",
        timestamp_basis = "official_exact",
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
        scheduled_timestamp_utc = "2026-10-30T13:00:00Z",
        timestamp_basis = "official_approximate_window",
        capture_not_before_utc = "2026-10-30T12:55:00Z",
        capture_deadline_utc = "2026-10-30T13:15:00Z",
        event_purpose = "last_eligible_daily_rate",
        required_for_complete_origin = true,
    ),
]
const EXPECTED_RECURRING_WINDOWS = Dict(
    "frbny_effr_daily_first_state" => (
        "2026-08-07",
        "2026-10-30",
        "13:00:00Z",
        "first_state_candidate",
    ),
    "frbny_effr_daily_revision_check" => (
        "2026-08-07",
        "2026-10-29",
        "18:30:00Z",
        "same_day_revision_candidate",
    ),
)

struct ProspectiveContractValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::ProspectiveContractValidationError) =
    print(io, error.message)

fail(location, message) =
    throw(ProspectiveContractValidationError("$location: $message"))

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
    actual = Set(String.(collect(keys(table))))
    actual == expected_keys ||
        fail(
        location,
        "must contain exactly $(join(sort!(collect(expected_keys)), ", ")); found $(join(sort!(collect(actual)), ", "))",
    )
    return table
end

function expect_string(value, location; allow_empty = false)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
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

function expect_one_of(value, allowed, location)
    text = expect_string(value, location)
    text in allowed ||
        fail(location, "must be one of $(join(sort!(collect(allowed)), ", "))")
    return text
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

function expect_date(value, location)
    text = expect_string(value, location)
    occursin(DATE_PATTERN, text) || fail(location, "must use YYYY-MM-DD")
    parsed = try
        Date(text)
    catch
        fail(location, "is not a valid date")
    end
    string(parsed) == text || fail(location, "is not canonical")
    return parsed
end

function expect_time_z(value, location)
    text = expect_string(value, location)
    occursin(TIME_Z_PATTERN, text) ||
        fail(location, "must use HH:MM:SSZ")
    parsed = try
        Time(chop(text; tail = 1))
    catch
        fail(location, "is not a valid UTC time")
    end
    Dates.format(parsed, dateformat"HH:MM:SS") * "Z" == text ||
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

function contract_sha256(contract)
    copy = deepcopy(expect_table(contract, "contract"))
    artifact =
        expect_table(get(copy, "artifact", nothing), "contract.artifact")
    pop!(artifact, "content_sha256", nothing)
    return canonical_sha256(copy)
end

function stamp_contract_sha256!(contract)
    table = expect_table(contract, "contract")
    artifact =
        expect_table(get(table, "artifact", nothing), "contract.artifact")
    artifact["content_sha256"] = contract_sha256(table)
    return table
end

function evaluate_governance(contract)
    verifier = expect_table(contract["verifier"], "contract.verifier")
    approval = expect_table(contract["approval"], "contract.approval")
    verifier_ready =
        verifier["implementation_status"] == "IMPLEMENTED_AND_VERIFIED" &&
        verifier["receipt_artifact_verification_status"] == "VERIFIED"
    approval_ready =
        approval["artifact_approval_status"] == "APPROVED"
    return (
        verifier_ready = verifier_ready,
        approval_ready = approval_ready,
        activation_ready = verifier_ready && approval_ready,
    )
end

function expected_artifact_status(governance)
    if governance.verifier_ready && governance.approval_ready
        return "GOVERNANCE_ACTIVE_ORIGIN_NOT_ADMITTED"
    elseif governance.verifier_ready
        return "VERIFIER_READY_REQUIREMENTS_UNAPPROVED"
    elseif governance.approval_ready
        return "APPROVED_REQUIREMENTS_VERIFIER_BLOCKED"
    end
    return "DRAFT_UNAPPROVED_FAIL_CLOSED"
end

function validate_artifact(contract)
    artifact = expect_exact_keys(
        contract["artifact"],
        ARTIFACT_KEYS,
        "contract.artifact",
    )
    expect_string(
        artifact["schema_version"],
        "contract.artifact.schema_version",
    ) == CONTRACT_SCHEMA ||
        fail(
        "contract.artifact.schema_version",
        "must equal $CONTRACT_SCHEMA",
    )
    expect_string(artifact["contract_id"], "contract.artifact.contract_id") ==
        CONTRACT_ID ||
        fail("contract.artifact.contract_id", "must equal $CONTRACT_ID")
    expect_one_of(
        artifact["status"],
        ARTIFACT_STATUSES,
        "contract.artifact.status",
    )
    expect_date(artifact["as_of_date"], "contract.artifact.as_of_date") ==
        Date(2026, 8, 6) ||
        fail("contract.artifact.as_of_date", "must equal 2026-08-06")
    expect_hash(
        artifact["protocol_sha256"],
        "contract.artifact.protocol_sha256",
    ) == PROTOCOL_SHA256 ||
        fail(
        "contract.artifact.protocol_sha256",
        "does not match the protocol contract",
    )
    expect_hash(
        artifact["tier1_targets_sha256"],
        "contract.artifact.tier1_targets_sha256",
    ) == TIER1_TARGETS_SHA256 ||
        fail(
        "contract.artifact.tier1_targets_sha256",
        "does not match the Tier-1 target contract",
    )
    expect_string(
        artifact["canonicalization"],
        "contract.artifact.canonicalization",
    ) == CANONICALIZATION ||
        fail(
        "contract.artifact.canonicalization",
        "must equal $CANONICALIZATION",
    )
    expect_string(
        artifact["digest_algorithm"],
        "contract.artifact.digest_algorithm",
    ) == "sha256" ||
        fail("contract.artifact.digest_algorithm", "must equal sha256")
    stored_hash =
        expect_hash(
        artifact["content_sha256"],
        "contract.artifact.content_sha256",
    )
    actual_hash = contract_sha256(contract)
    stored_hash == actual_hash ||
        fail(
        "contract.artifact.content_sha256",
        "does not match canonical contract hash $actual_hash",
    )
    return artifact
end

function validate_origin(contract)
    origin =
        expect_exact_keys(contract["origin"], ORIGIN_KEYS, "contract.origin")
    expect_identifier(origin["origin_id"], "contract.origin.origin_id") ==
        "origin.2026q3.prospective-capture-candidate" ||
        fail(
        "contract.origin.origin_id",
        "must identify the 2026Q3 prospective candidate",
    )
    expect_string(
        origin["reference_quarter"],
        "contract.origin.reference_quarter",
    ) == "2026Q3" ||
        fail("contract.origin.reference_quarter", "must equal 2026Q3")
    expect_timestamp(
        origin["origin_timestamp_utc"],
        "contract.origin.origin_timestamp_utc",
    ) == expect_timestamp(ORIGIN_TIMESTAMP, "expected origin") ||
        fail(
        "contract.origin.origin_timestamp_utc",
        "must equal $ORIGIN_TIMESTAMP",
    )
    expect_string(origin["origin_rule"], "contract.origin.origin_rule") ==
        "FIRST_BUSINESS_DAY_AFTER_BEA_ADVANCE_AT_10:00_AMERICA/NEW_YORK" ||
        fail("contract.origin.origin_rule", "does not match the protocol")
    expect_string(
        origin["admission_status"],
        "contract.origin.admission_status",
    ) == "PLANNED_NOT_CAPTURED_NOT_ADMITTED" ||
        fail(
        "contract.origin.admission_status",
        "must remain PLANNED_NOT_CAPTURED_NOT_ADMITTED",
    )
    for field in (
            "inventory_mutation_authorized",
            "origin_admissible",
            "ready",
            "accuracy_evaluation_allowed",
        )
        !expect_bool(origin[field], "contract.origin.$field") ||
            fail("contract.origin.$field", "must remain false")
    end
    return origin
end

function validate_availability_policy(contract)
    policy = expect_exact_keys(
        contract["availability_policy"],
        AVAILABILITY_KEYS,
        "contract.availability_policy",
    )
    expected_strings = Dict(
        "policy_version" => "availability-upper-bound.v1-draft",
        "eligibility_time_field" => "availability_upper_bound_utc",
        "eligible_basis" => "VERIFIED_PRE_ORIGIN_RECEIPT_COMPLETION",
        "availability_upper_bound_semantics" =>
            "conservative_latest_time_by_which_exact_bytes_are_proven_available_not_an_asserted_original_publication_time",
    )
    for (field, expected) in expected_strings
        expect_string(
            policy[field],
            "contract.availability_policy.$field",
        ) == expected ||
            fail(
            "contract.availability_policy.$field",
            "must equal $expected",
        )
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
            fail("contract.availability_policy.$field", "must equal true")
    end
    for field in (
            "post_origin_receipt_eligible",
            "historical_backfill_eligible",
            "unverified_receipt_eligible",
            "schedule_or_route_only_eligible",
        )
        !expect_bool(policy[field], "contract.availability_policy.$field") ||
            fail("contract.availability_policy.$field", "must equal false")
    end
    return policy
end

function validate_verifier(contract)
    verifier = expect_exact_keys(
        contract["verifier"],
        VERIFIER_KEYS,
        "contract.verifier",
    )
    status = expect_one_of(
        verifier["implementation_status"],
        VERIFIER_STATUSES,
        "contract.verifier.implementation_status",
    )
    receipt_status = expect_one_of(
        verifier["receipt_artifact_verification_status"],
        RECEIPT_VERIFICATION_STATUSES,
        "contract.verifier.receipt_artifact_verification_status",
    )
    implementation_hash = expect_string(
        verifier["implementation_artifact_sha256"],
        "contract.verifier.implementation_artifact_sha256",
    )
    if status == "IMPLEMENTED_AND_VERIFIED"
        expect_hash(
            implementation_hash,
            "contract.verifier.implementation_artifact_sha256",
        )
        receipt_status == "VERIFIED" ||
            fail(
            "contract.verifier.receipt_artifact_verification_status",
            "must be VERIFIED when implementation is ready",
        )
    else
        implementation_hash == "unavailable" ||
            fail(
            "contract.verifier.implementation_artifact_sha256",
            "must be unavailable while the verifier is not implemented",
        )
        receipt_status == "NOT_VERIFIED" ||
            fail(
            "contract.verifier.receipt_artifact_verification_status",
            "must remain NOT_VERIFIED while the verifier is unavailable",
        )
    end
    expect_bool(
        verifier["activation_requires_implementation"],
        "contract.verifier.activation_requires_implementation",
    ) ||
        fail(
        "contract.verifier.activation_requires_implementation",
        "must equal true",
    )
    expect_bool(
        verifier["status_is_independent_of_requirements_approval"],
        "contract.verifier.status_is_independent_of_requirements_approval",
    ) ||
        fail(
        "contract.verifier.status_is_independent_of_requirements_approval",
        "must equal true",
    )
    return verifier
end

function validate_approval(contract)
    approval = expect_exact_keys(
        contract["approval"],
        APPROVAL_KEYS,
        "contract.approval",
    )
    status = expect_one_of(
        approval["artifact_approval_status"],
        APPROVAL_STATUSES,
        "contract.approval.artifact_approval_status",
    )
    model_owner =
        expect_string(approval["model_owner"], "contract.approval.model_owner")
    model_signature = expect_string(
        approval["model_owner_signature"],
        "contract.approval.model_owner_signature",
    )
    validator = expect_string(
        approval["independent_validator"],
        "contract.approval.independent_validator",
    )
    validator_signature = expect_string(
        approval["independent_validator_signature"],
        "contract.approval.independent_validator_signature",
    )
    if status == "APPROVED"
        expect_identifier(model_owner, "contract.approval.model_owner")
        expect_identifier(
            validator,
            "contract.approval.independent_validator",
        )
        model_owner != validator ||
            fail(
            "contract.approval.independent_validator",
            "must differ from model_owner",
        )
        expect_hash(
            model_signature,
            "contract.approval.model_owner_signature",
        )
        expect_hash(
            validator_signature,
            "contract.approval.independent_validator_signature",
        )
    else
        model_owner == "unassigned" ||
            fail(
            "contract.approval.model_owner",
            "must be unassigned while draft",
        )
        validator == "unassigned" ||
            fail(
            "contract.approval.independent_validator",
            "must be unassigned while draft",
        )
        model_signature == "unsigned" ||
            fail(
            "contract.approval.model_owner_signature",
            "must be unsigned while draft",
        )
        validator_signature == "unsigned" ||
            fail(
            "contract.approval.independent_validator_signature",
            "must be unsigned while draft",
        )
    end
    expect_bool(
        approval["activation_requires_approval"],
        "contract.approval.activation_requires_approval",
    ) ||
        fail(
        "contract.approval.activation_requires_approval",
        "must equal true",
    )
    expect_bool(
        approval["status_is_independent_of_verifier_implementation"],
        "contract.approval.status_is_independent_of_verifier_implementation",
    ) ||
        fail(
        "contract.approval.status_is_independent_of_verifier_implementation",
        "must equal true",
    )
    return approval
end

function validate_retention(contract, origin)
    retention = expect_exact_keys(
        contract["retention"],
        RETENTION_KEYS,
        "contract.retention",
    )
    expect_string(
        retention["policy_version"],
        "contract.retention.policy_version",
    ) == "prospective-durable-retention.v1-draft" ||
        fail(
        "contract.retention.policy_version",
        "must equal prospective-durable-retention.v1-draft",
    )
    minimum_retain = expect_timestamp(
        retention["minimum_retain_until_utc"],
        "contract.retention.minimum_retain_until_utc",
    )
    minimum_retain ==
        expect_timestamp(MINIMUM_RETAIN_UNTIL, "expected retention") ||
        fail(
        "contract.retention.minimum_retain_until_utc",
        "must equal $MINIMUM_RETAIN_UNTIL",
    )
    months = expect_int(
        retention["origin_plus_mature_truth_months"],
        "contract.retention.origin_plus_mature_truth_months";
        minimum = 1,
    )
    months == 60 ||
        fail(
        "contract.retention.origin_plus_mature_truth_months",
        "must equal 60",
    )
    minimum_retain >=
        expect_timestamp(origin["origin_timestamp_utc"], "origin") +
        Month(months) ||
        fail(
        "contract.retention.minimum_retain_until_utc",
        "must cover the mature-truth horizon",
    )
    expect_int(
        retention["minimum_durable_copy_count"],
        "contract.retention.minimum_durable_copy_count";
        minimum = 2,
    ) == 2 ||
        fail(
        "contract.retention.minimum_durable_copy_count",
        "must equal 2",
    )
    for field in (
            "content_addressed_storage_required",
            "write_once_or_versioned_storage_required",
            "raw_and_receipt_bytes_co_retained",
            "hash_manifest_required",
            "external_timestamp_receipt_required",
        )
        expect_bool(retention[field], "contract.retention.$field") ||
            fail("contract.retention.$field", "must equal true")
    end
    for field in (
            "github_actions_artifact_only_allowed",
            "short_retention_artifact_is_origin_evidence",
        )
        !expect_bool(retention[field], "contract.retention.$field") ||
            fail("contract.retention.$field", "must equal false")
    end
    return retention
end

function validate_requirements(contract)
    rows = expect_array(
        contract["requirements"],
        "contract.requirements";
        allow_empty = false,
    )
    ids = String[]
    target_ids = String[]
    kinds = Set{String}()
    source_by_id = Dict{String, String}()
    for (index, row) in enumerate(rows)
        location = "contract.requirements[$index]"
        item = expect_exact_keys(row, REQUIREMENT_KEYS, location)
        requirement_id =
            expect_identifier(item["requirement_id"], "$location.requirement_id")
        push!(ids, requirement_id)
        block_kind =
            expect_one_of(item["block_kind"], BLOCK_KINDS, "$location.block_kind")
        push!(kinds, block_kind)
        source_id =
            expect_identifier(item["source_id"], "$location.source_id")
        source_by_id[requirement_id] = source_id
        expect_identifier(item["source_family"], "$location.source_family")
        locator = expect_string(item["source_locator"], "$location.source_locator")
        startswith(locator, "https://") ||
            fail("$location.source_locator", "must use HTTPS")
        targets = expect_string_array(item["target_ids"], "$location.target_ids")
        if block_kind == "target"
            isempty(targets) &&
                fail("$location.target_ids", "must not be empty for target blocks")
            append!(target_ids, targets)
        elseif !isempty(targets)
            fail("$location.target_ids", "must be empty outside target blocks")
        end
        expect_one_of(
            item["acquisition_mode"],
            ACQUISITION_MODES,
            "$location.acquisition_mode",
        )
        expect_bool(
            item["required_for_complete_origin"],
            "$location.required_for_complete_origin",
        ) ||
            fail("$location.required_for_complete_origin", "must equal true")
        expect_string(item["evidence_status"], "$location.evidence_status") ==
            "MISSING_NOT_CAPTURED" ||
            fail(
            "$location.evidence_status",
            "must remain MISSING_NOT_CAPTURED",
        )
        expect_int(
            item["registered_raw_artifact_count"],
            "$location.registered_raw_artifact_count";
            minimum = 0,
        ) == 0 ||
            fail(
            "$location.registered_raw_artifact_count",
            "must remain zero",
        )
    end
    issorted(ids) || fail("contract.requirements", "must sort by requirement_id")
    length(ids) == length(unique(ids)) ||
        fail("contract.requirements", "contains duplicate requirement IDs")
    Set(ids) == REQUIRED_REQUIREMENT_IDS ||
        fail(
        "contract.requirements",
        "must contain the complete prospective requirement set",
    )
    source_by_id == REQUIRED_SOURCE_BY_REQUIREMENT ||
        fail(
        "contract.requirements",
        "source IDs do not match the pinned requirement routes",
    )
    kinds == BLOCK_KINDS ||
        fail(
        "contract.requirements",
        "must include source, target, and structural blocks",
    )
    Set(target_ids) == TIER1_TARGET_IDS ||
        fail(
        "contract.requirements",
        "must cover all eight Tier-1 targets exactly once",
    )
    length(target_ids) == length(unique(target_ids)) ||
        fail(
        "contract.requirements",
        "Tier-1 targets must map to exactly one requirement",
    )
    return Dict(ids[index] => rows[index] for index in eachindex(ids))
end

function validate_fixed_events(contract, requirements, origin)
    rows = expect_array(
        contract["fixed_events"],
        "contract.fixed_events";
        allow_empty = false,
    )
    length(rows) == length(EXPECTED_FIXED_EVENTS) ||
        fail(
        "contract.fixed_events",
        "must contain exactly $(length(EXPECTED_FIXED_EVENTS)) events",
    )
    observed = NamedTuple[]
    scheduled_times = DateTime[]
    ids = String[]
    origin_time =
        expect_timestamp(origin["origin_timestamp_utc"], "contract.origin")
    for (index, row) in enumerate(rows)
        location = "contract.fixed_events[$index]"
        item = expect_exact_keys(row, FIXED_EVENT_KEYS, location)
        event_id = expect_identifier(item["event_id"], "$location.event_id")
        push!(ids, event_id)
        source_id = expect_identifier(item["source_id"], "$location.source_id")
        requirement_ids = expect_string_array(
            item["requirement_ids"],
            "$location.requirement_ids";
            allow_empty = false,
        )
        for requirement_id in requirement_ids
            haskey(requirements, requirement_id) ||
                fail(
                "$location.requirement_ids",
                "references unknown requirement $requirement_id",
            )
        end
        reference_period =
            expect_string(item["reference_period"], "$location.reference_period")
        locator = expect_string(
            item["official_schedule_locator"],
            "$location.official_schedule_locator",
        )
        startswith(locator, "https://") ||
            fail("$location.official_schedule_locator", "must use HTTPS")
        scheduled = expect_timestamp(
            item["scheduled_timestamp_utc"],
            "$location.scheduled_timestamp_utc",
        )
        push!(scheduled_times, scheduled)
        timestamp_basis = expect_one_of(
            item["timestamp_basis"],
            TIMESTAMP_BASES,
            "$location.timestamp_basis",
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
            fail(
            location,
            "capture window must contain the scheduled timestamp",
        )
        deadline < origin_time ||
            fail(
            "$location.capture_deadline_utc",
            "must precede the origin cutoff",
        )
        timestamp_basis == "official_exact" &&
            capture_start != scheduled &&
            fail(
            "$location.capture_not_before_utc",
            "must equal the exact scheduled timestamp",
        )
        purpose = expect_one_of(
            item["event_purpose"],
            EVENT_PURPOSES,
            "$location.event_purpose",
        )
        required_for_complete_origin = expect_bool(
            item["required_for_complete_origin"],
            "$location.required_for_complete_origin",
        )
        expect_string(item["capture_status"], "$location.capture_status") ==
            "PLANNED_NOT_CAPTURED" ||
            fail("$location.capture_status", "must remain PLANNED_NOT_CAPTURED")
        expect_string(
            item["immutable_receipt_status"],
            "$location.immutable_receipt_status",
        ) == "MISSING" ||
            fail("$location.immutable_receipt_status", "must remain MISSING")
        expect_int(item["receipt_count"], "$location.receipt_count"; minimum = 0) ==
            0 ||
            fail("$location.receipt_count", "must remain zero")
        !expect_bool(item["origin_eligible"], "$location.origin_eligible") ||
            fail("$location.origin_eligible", "must remain false")
        push!(
            observed,
            (
                event_id = event_id,
                source_id = source_id,
                requirement_ids = requirement_ids,
                reference_period = reference_period,
                official_schedule_locator = locator,
                scheduled_timestamp_utc =
                    Dates.format(scheduled, RFC3339_SECONDS_FORMAT) * "Z",
                timestamp_basis = timestamp_basis,
                capture_not_before_utc =
                    Dates.format(capture_start, RFC3339_SECONDS_FORMAT) * "Z",
                capture_deadline_utc =
                    Dates.format(deadline, RFC3339_SECONDS_FORMAT) * "Z",
                event_purpose = purpose,
                required_for_complete_origin = required_for_complete_origin,
            ),
        )
    end
    observed == EXPECTED_FIXED_EVENTS ||
        fail(
        "contract.fixed_events",
        "does not match the pinned 2026Q3 capture calendar",
    )
    issorted(scheduled_times) ||
        fail("contract.fixed_events", "must be chronological")
    length(ids) == length(unique(ids)) ||
        fail("contract.fixed_events", "contains duplicate event IDs")
    return Dict(ids[index] => rows[index] for index in eachindex(ids))
end

function validate_recurring_windows(contract, requirements)
    rows = expect_array(
        contract["recurring_windows"],
        "contract.recurring_windows";
        allow_empty = false,
    )
    length(rows) == length(EXPECTED_RECURRING_WINDOWS) ||
        fail(
        "contract.recurring_windows",
        "must contain both EFFR windows",
    )
    ids = String[]
    for (index, row) in enumerate(rows)
        location = "contract.recurring_windows[$index]"
        item = expect_exact_keys(row, RECURRING_WINDOW_KEYS, location)
        window_id = expect_identifier(item["window_id"], "$location.window_id")
        push!(ids, window_id)
        source_id = expect_identifier(item["source_id"], "$location.source_id")
        requirement_id = expect_identifier(
            item["requirement_id"],
            "$location.requirement_id",
        )
        haskey(requirements, requirement_id) ||
            fail("$location.requirement_id", "is not a known requirement")
        requirements[requirement_id]["source_id"] == source_id ||
            fail("$location.source_id", "does not match the requirement")
        start_date =
            expect_date(item["campaign_start_date"], "$location.campaign_start_date")
        end_date =
            expect_date(item["campaign_end_date"], "$location.campaign_end_date")
        start_date <= end_date ||
            fail(location, "campaign start must not follow campaign end")
        scheduled_time =
            expect_time_z(item["scheduled_time_utc"], "$location.scheduled_time_utc")
        expect_int(
            item["capture_window_minutes"],
            "$location.capture_window_minutes";
            minimum = 1,
        ) == 15 ||
            fail("$location.capture_window_minutes", "must equal 15")
        expect_string(item["business_day_rule"], "$location.business_day_rule") ==
            "NEW_YORK_FED_PUBLICATION_DAYS_REVALIDATE_OFFICIAL_HOLIDAYS" ||
            fail(
            "$location.business_day_rule",
            "must retain the official-calendar revalidation rule",
        )
        expect_string(item["timestamp_basis"], "$location.timestamp_basis") ==
            "official_approximate_window" ||
            fail(
            "$location.timestamp_basis",
            "must remain official_approximate_window",
        )
        evidence_role =
            expect_string(item["evidence_role"], "$location.evidence_role")
        expect_bool(
            item["origin_day_completion_before_cutoff_required"],
            "$location.origin_day_completion_before_cutoff_required",
        ) ||
            fail(
            "$location.origin_day_completion_before_cutoff_required",
            "must equal true",
        )
        expect_string(item["capture_status"], "$location.capture_status") ==
            "PLANNED_NOT_CAPTURED" ||
            fail("$location.capture_status", "must remain PLANNED_NOT_CAPTURED")
        expect_int(item["receipt_count"], "$location.receipt_count"; minimum = 0) ==
            0 ||
            fail("$location.receipt_count", "must remain zero")
        !expect_bool(item["origin_eligible"], "$location.origin_eligible") ||
            fail("$location.origin_eligible", "must remain false")
        expected = get(EXPECTED_RECURRING_WINDOWS, window_id, nothing)
        expected === nothing &&
            fail("$location.window_id", "is not a pinned EFFR window")
        (
            string(start_date),
            string(end_date),
            Dates.format(scheduled_time, dateformat"HH:MM:SS") * "Z",
            evidence_role,
        ) == expected ||
            fail(location, "does not match the pinned EFFR campaign")
    end
    issorted(ids) ||
        fail("contract.recurring_windows", "must sort by window_id")
    length(ids) == length(unique(ids)) ||
        fail("contract.recurring_windows", "contains duplicate window IDs")
    return rows
end

function validate_snapshot_campaigns(contract, requirements, origin)
    rows = expect_array(
        contract["snapshot_campaigns"],
        "contract.snapshot_campaigns";
        allow_empty = false,
    )
    length(rows) == 1 ||
        fail(
        "contract.snapshot_campaigns",
        "must contain the slow-structural pre-origin campaign",
    )
    item = expect_exact_keys(
        only(rows),
        SNAPSHOT_CAMPAIGN_KEYS,
        "contract.snapshot_campaigns[1]",
    )
    expect_string(
        item["campaign_id"],
        "contract.snapshot_campaigns[1].campaign_id",
    ) == "slow_structural_pre_origin" ||
        fail(
        "contract.snapshot_campaigns[1].campaign_id",
        "must equal slow_structural_pre_origin",
    )
    ids = expect_string_array(
        item["requirement_ids"],
        "contract.snapshot_campaigns[1].requirement_ids";
        allow_empty = false,
    )
    expected_ids = sort!(
        [
            "bea_fixed_assets_structural",
            "bls_cps_structural",
            "census_susb_structural",
            "classification_maps",
            "usda_counts_structural",
        ],
    )
    ids == expected_ids ||
        fail(
        "contract.snapshot_campaigns[1].requirement_ids",
        "must include the slow-moving structural sources",
    )
    all(haskey(requirements, requirement_id) for requirement_id in ids) ||
        fail(
        "contract.snapshot_campaigns[1].requirement_ids",
        "contains an unknown requirement",
    )
    capture_not_before = expect_timestamp(
        item["capture_not_before_utc"],
        "contract.snapshot_campaigns[1].capture_not_before_utc",
    )
    capture_not_before == DateTime(2026, 8, 6) ||
        fail(
        "contract.snapshot_campaigns[1].capture_not_before_utc",
        "must equal 2026-08-06T00:00:00Z",
    )
    deadline = expect_timestamp(
        item["capture_deadline_utc"],
        "contract.snapshot_campaigns[1].capture_deadline_utc",
    )
    deadline == DateTime(2026, 8, 31, 23, 59, 59) ||
        fail(
        "contract.snapshot_campaigns[1].capture_deadline_utc",
        "must equal 2026-08-31T23:59:59Z",
    )
    capture_not_before <= deadline ||
        fail(
        "contract.snapshot_campaigns[1]",
        "capture window start must not follow its deadline",
    )
    deadline <
        expect_timestamp(origin["origin_timestamp_utc"], "contract.origin") ||
        fail(
        "contract.snapshot_campaigns[1].capture_deadline_utc",
        "must precede the origin",
    )
    expect_string(
        item["availability_basis"],
        "contract.snapshot_campaigns[1].availability_basis",
    ) == "VERIFIED_PRE_ORIGIN_RECEIPT_COMPLETION" ||
        fail(
        "contract.snapshot_campaigns[1].availability_basis",
        "must use the conservative upper-bound policy",
    )
    expect_string(item["purpose"], "contract.snapshot_campaigns[1].purpose") ==
        "prove_exact_current_bytes_available_before_origin_without_asserting_original_publication_time" ||
        fail(
        "contract.snapshot_campaigns[1].purpose",
        "must preserve the conservative evidence boundary",
    )
    expect_string(
        item["capture_status"],
        "contract.snapshot_campaigns[1].capture_status",
    ) == "PLANNED_NOT_CAPTURED" ||
        fail(
        "contract.snapshot_campaigns[1].capture_status",
        "must remain PLANNED_NOT_CAPTURED",
    )
    expect_int(
        item["receipt_count"],
        "contract.snapshot_campaigns[1].receipt_count";
        minimum = 0,
    ) == 0 ||
        fail(
        "contract.snapshot_campaigns[1].receipt_count",
        "must remain zero",
    )
    !expect_bool(
        item["origin_eligible"],
        "contract.snapshot_campaigns[1].origin_eligible",
    ) ||
        fail(
        "contract.snapshot_campaigns[1].origin_eligible",
        "must remain false",
    )
    return rows
end

function validate_contract(contract)
    contract =
        expect_exact_keys(contract, ROOT_KEYS, "contract")
    validate_origin(contract)
    validate_availability_policy(contract)
    validate_verifier(contract)
    validate_approval(contract)
    governance = evaluate_governance(contract)
    artifact = contract["artifact"]
    expect_string(artifact["status"], "contract.artifact.status") ==
        expected_artifact_status(governance) ||
        fail(
        "contract.artifact.status",
        "does not match independent verifier/approval states",
    )
    retention = validate_retention(contract, contract["origin"])
    requirements = validate_requirements(contract)
    validate_fixed_events(
        contract,
        requirements,
        contract["origin"],
    )
    validate_recurring_windows(contract, requirements)
    validate_snapshot_campaigns(
        contract,
        requirements,
        contract["origin"],
    )
    validate_artifact(contract)
    return contract
end

function load_contract(path::AbstractString)
    contract = TOML.parsefile(path)
    validate_contract(contract)
    return contract
end

function validate_receipt(contract, receipt)
    validate_contract(contract)
    item = expect_exact_keys(receipt, RECEIPT_KEYS, "receipt")
    expect_identifier(item["receipt_id"], "receipt.receipt_id")
    event_id = expect_identifier(item["event_id"], "receipt.event_id")
    requirement_id =
        expect_identifier(item["requirement_id"], "receipt.requirement_id")
    requirements = Dict(
        row["requirement_id"] => row for row in contract["requirements"]
    )
    haskey(requirements, requirement_id) ||
        fail("receipt.requirement_id", "is not declared by the contract")
    fixed_events =
        Dict(row["event_id"] => row for row in contract["fixed_events"])
    snapshot_campaigns = Dict(
        row["campaign_id"] => row for row in contract["snapshot_campaigns"]
    )
    recurring_windows = Dict(
        row["window_id"] => row for row in contract["recurring_windows"]
    )
    capture_not_before = nothing
    capture_deadline = nothing
    recurring_window = nothing
    if haskey(fixed_events, event_id)
        requirement_id in fixed_events[event_id]["requirement_ids"] ||
            fail(
            "receipt.requirement_id",
            "is not assigned to receipt.event_id",
        )
        capture_not_before = expect_timestamp(
            fixed_events[event_id]["capture_not_before_utc"],
            "contract.fixed_events.capture_not_before_utc",
        )
        capture_deadline = expect_timestamp(
            fixed_events[event_id]["capture_deadline_utc"],
            "contract.fixed_events.capture_deadline_utc",
        )
    elseif haskey(snapshot_campaigns, event_id)
        requirement_id in snapshot_campaigns[event_id]["requirement_ids"] ||
            fail(
            "receipt.requirement_id",
            "is not assigned to the snapshot campaign",
        )
        capture_not_before = expect_timestamp(
            snapshot_campaigns[event_id]["capture_not_before_utc"],
            "contract.snapshot_campaigns.capture_not_before_utc",
        )
        capture_deadline = expect_timestamp(
            snapshot_campaigns[event_id]["capture_deadline_utc"],
            "contract.snapshot_campaigns.capture_deadline_utc",
        )
    elseif haskey(recurring_windows, event_id)
        recurring_windows[event_id]["requirement_id"] == requirement_id ||
            fail(
            "receipt.requirement_id",
            "is not assigned to the recurring window",
        )
        recurring_window = recurring_windows[event_id]
    else
        fail("receipt.event_id", "is not declared by the contract")
    end
    retrieved = expect_timestamp(
        item["retrieved_at_utc"],
        "receipt.retrieved_at_utc",
    )
    completed = expect_timestamp(
        item["receipt_completed_at_utc"],
        "receipt.receipt_completed_at_utc",
    )
    upper_bound = expect_timestamp(
        item["availability_upper_bound_utc"],
        "receipt.availability_upper_bound_utc",
    )
    if recurring_window !== nothing
        retrieval_date = Date(retrieved)
        campaign_start = expect_date(
            recurring_window["campaign_start_date"],
            "contract.recurring_windows.campaign_start_date",
        )
        campaign_end = expect_date(
            recurring_window["campaign_end_date"],
            "contract.recurring_windows.campaign_end_date",
        )
        campaign_start <= retrieval_date <= campaign_end ||
            fail(
            "receipt.retrieved_at_utc",
            "falls outside the recurring campaign dates",
        )
        dayofweek(retrieval_date) <= 5 ||
            fail(
            "receipt.retrieved_at_utc",
            "recurring campaign receipts must use a weekday subject to official-holiday revalidation",
        )
        scheduled_text =
            string(retrieval_date) * "T" *
            chop(recurring_window["scheduled_time_utc"]; tail = 1) * "Z"
        capture_not_before = expect_timestamp(
            scheduled_text,
            "contract.recurring_windows.scheduled_time_utc",
        )
        capture_deadline =
            capture_not_before +
            Minute(recurring_window["capture_window_minutes"])
    end
    retrieved <= completed ||
        fail(
        "receipt.receipt_completed_at_utc",
        "must not precede retrieval",
    )
    expect_string(item["availability_basis"], "receipt.availability_basis") ==
        contract["availability_policy"]["eligible_basis"] ||
        fail(
        "receipt.availability_basis",
        "does not match the prospective upper-bound policy",
    )
    expect_hash(item["raw_sha256"], "receipt.raw_sha256")
    expect_hash(item["receipt_sha256"], "receipt.receipt_sha256")
    expect_one_of(
        item["receipt_artifact_status"],
        RECEIPT_VERIFICATION_STATUSES,
        "receipt.receipt_artifact_status",
    )
    expect_one_of(
        item["durable_storage_status"],
        Set(["NOT_VERIFIED", "VERIFIED"]),
        "receipt.durable_storage_status",
    )
    retain_until =
        expect_timestamp(item["retain_until_utc"], "receipt.retain_until_utc")
    return (
        event_id = event_id,
        requirement_id = requirement_id,
        retrieved = retrieved,
        completed = completed,
        upper_bound = upper_bound,
        retain_until = retain_until,
        capture_not_before = capture_not_before,
        capture_deadline = capture_deadline,
    )
end

function evaluate_receipt_evidence(contract, receipt)
    parsed = validate_receipt(contract, receipt)
    origin = expect_timestamp(
        contract["origin"]["origin_timestamp_utc"],
        "contract.origin.origin_timestamp_utc",
    )
    minimum_retain = expect_timestamp(
        contract["retention"]["minimum_retain_until_utc"],
        "contract.retention.minimum_retain_until_utc",
    )
    upper_bound_matches_completion =
        parsed.upper_bound == parsed.completed
    pre_origin = parsed.upper_bound < origin
    capture_window_compliant =
        (
        parsed.capture_not_before === nothing ||
            parsed.retrieved >= parsed.capture_not_before
    ) &&
        parsed.completed <= parsed.capture_deadline
    receipt_verified =
        receipt["receipt_artifact_status"] == "VERIFIED"
    durable_storage_verified =
        receipt["durable_storage_status"] == "VERIFIED"
    retention_sufficient = parsed.retain_until >= minimum_retain
    temporal_candidate_eligible =
        upper_bound_matches_completion &&
        pre_origin &&
        capture_window_compliant &&
        receipt_verified &&
        durable_storage_verified &&
        retention_sufficient
    governance = evaluate_governance(contract)
    contract_usable =
        temporal_candidate_eligible && governance.activation_ready
    reason_codes = String[]
    !upper_bound_matches_completion &&
        push!(reason_codes, "UPPER_BOUND_NOT_RECEIPT_COMPLETION")
    !pre_origin && push!(reason_codes, "NOT_PROVEN_BEFORE_ORIGIN")
    !capture_window_compliant &&
        push!(reason_codes, "OUTSIDE_CONTRACT_CAPTURE_WINDOW")
    !receipt_verified && push!(reason_codes, "RECEIPT_ARTIFACT_NOT_VERIFIED")
    !durable_storage_verified &&
        push!(reason_codes, "DURABLE_STORAGE_NOT_VERIFIED")
    !retention_sufficient &&
        push!(reason_codes, "RETENTION_DOES_NOT_COVER_MATURE_TRUTH")
    !governance.verifier_ready &&
        push!(reason_codes, "VERIFIER_NOT_IMPLEMENTED")
    !governance.approval_ready &&
        push!(reason_codes, "REQUIREMENTS_NOT_APPROVED")
    return (
        temporal_candidate_eligible = temporal_candidate_eligible,
        verifier_ready = governance.verifier_ready,
        requirements_approved = governance.approval_ready,
        contract_usable = contract_usable,
        origin_admissible = false,
        ready = false,
        reason_codes = sort!(reason_codes),
    )
end

end
