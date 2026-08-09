module USEFFRCampaignControl

using Dates
using SHA
using TOML

include(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "prospective",
        "USProspectiveAcquisitionContractV2.jl",
    ),
)
using .USProspectiveAcquisitionContractV2

export CampaignControlError,
    CaptureAuthorization,
    DEFAULT_CONTRACT_PATH,
    DEFAULT_SCHEDULE_PATH,
    ValidatedBundleManifest,
    capture_authorization,
    computed_schedule_sha256,
    evaluate_campaign,
    load_schedule,
    validate_schedule,
    validated_bundle_manifest

const DEFAULT_SCHEDULE_PATH =
    joinpath(@__DIR__, "effr_2026q3_campaign_schedule.toml")
const DEFAULT_CONTRACT_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "prospective",
        "prospective_2026q3_contract_v2.toml",
    ),
)
const SCHEDULE_SCHEMA = "beforeit-us-effr-campaign-schedule.v1"
const SCHEDULE_ID = "beforeit-us-effr-2026q3-prospective-campaign.v1"
const CONTRACT_ID = "beforeit-us-prospective-2026q3-acquisition.v2"
const CONTRACT_CONTENT_SHA256 =
    "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
const CONTRACT_FILE_SHA256 =
    "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
const SOURCE_ID = "frbny_effr"
const REQUIREMENT_ID = "frbny_effr_tier1"
const CAMPAIGN_ID = "frbny_effr_daily_first_state_and_revision_check"
const FIRST_WINDOW_ID = "frbny_effr_daily_first_state"
const REVISION_WINDOW_ID = "frbny_effr_daily_revision_check"
const CURRENT_STATE_BLOCKER =
    "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT"
const API_ENDPOINT =
    "https://markets.newyorkfed.org/api/rates/all/search.json"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const ALWAYS_FALSE_GATE_KEYS = (
    "network_execution_authorized",
    "raw_data_write_authorized",
    "profile_completion_authorized",
    "inventory_mutation_authorized",
    "origin_admissible",
    "accuracy_evaluation_allowed",
    "promotion_eligible",
    "production_scoring_allowed",
    "ready",
)
const MANIFEST_FALSE_GATE_KEYS = (
    "accuracy_evaluation_allowed",
    "empirical_forecast_allowed",
    "origin_admissible",
    "production_scoring_allowed",
    "promotion_eligible",
    "readiness",
    "source_inventory_mutation_allowed",
)
const ACCEPTED_STATUSES = Set(
    [
        "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE",
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE",
        "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED",
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE",
    ],
)

struct CampaignControlError <: Exception
    message::String
end

Base.showerror(io::IO, error::CampaignControlError) =
    print(io, error.message)

fail(location, message) =
    throw(CampaignControlError("$location: $message"))

struct CaptureAuthorization
    schedule_id::String
    sequence::Int
    phase::String
    publication_date::Date
    effective_date::Date
    window_start_utc::DateTime
    window_deadline_utc::DateTime
    state_class_candidate::String
    network_execution_authorized::Bool
    raw_data_write_authorized::Bool
    inventory_mutation_authorized::Bool
    origin_admissible::Bool
end

struct ValidatedBundleManifest
    bundle_path::String
    manifest::Dict{String, Any}
end

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    required = Set(String.(expected))
    missing = sort!(collect(setdiff(required, actual)))
    unknown = sort!(collect(setdiff(actual, required)))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown keys: $(join(unknown, ", "))")
    return table
end

function expect_keys(value, required, location)
    table = expect_table(value, location)
    missing =
        sort!(collect(setdiff(Set(String.(required)), Set(String.(keys(table))))))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    return table
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
    occursin('\0', text) && fail(location, "must not contain NUL")
    return text
end

function expect_exact(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be Boolean")
    return value
end

function expect_int(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    number = try
        Int(value)
    catch
        fail(location, "is outside the platform Int range")
    end
    number >= minimum || fail(location, "must be at least $minimum")
    return number
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be a lowercase SHA-256")
    return text
end

function expect_date(value, location)
    text = expect_string(value, location)
    try
        parsed = Date(text)
        string(parsed) == text || fail(location, "must be canonical YYYY-MM-DD")
        return parsed
    catch error
        error isa CampaignControlError && rethrow()
        fail(location, "must be canonical YYYY-MM-DD")
    end
end

function expect_timestamp(value, location)
    text = expect_string(value, location)
    endswith(text, "Z") || fail(location, "must end in Z")
    try
        return DateTime(chop(text; tail = 1))
    catch
        fail(location, "must be a canonical UTC timestamp")
    end
end

function expect_time(value, location)
    text = expect_string(value, location)
    occursin(r"^\d{2}:\d{2}:\d{2}Z$", text) ||
        fail(location, "must be HH:MM:SSZ")
    try
        return Time(chop(text; tail = 1))
    catch
        fail(location, "must be HH:MM:SSZ")
    end
end

function expect_array(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    return value
end

function file_sha256(path)
    isfile(path) || fail("contract", "missing file $path")
    islink(path) && fail("contract", "refuses symbolic link $path")
    return bytes2hex(sha256(read(path)))
end

function _canonical_write(io::IO, value)
    return if value isa AbstractDict
        keys_sorted = sort!(String.(collect(keys(value))))
        print(io, "M", length(keys_sorted), "{")
        for key in keys_sorted
            _canonical_write(io, key)
            _canonical_write(io, value[key])
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "A", length(value), "[")
        for item in value
            _canonical_write(io, item)
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
        fail("canonicalization", "unsupported type $(typeof(value))")
    end
end

function computed_schedule_sha256(schedule)
    document = deepcopy(expect_table(schedule, "schedule"))
    artifact = expect_table(document["artifact"], "schedule.artifact")
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, document)
    return bytes2hex(sha256(take!(io)))
end

function _contract_window(contract, window_id)
    matches = [
        window for window in contract["recurring_windows"] if
            window["window_id"] == window_id
    ]
    length(matches) == 1 ||
        fail("contract.recurring_windows", "expected exactly one $window_id")
    return only(matches)
end

function _validate_contract_binding(schedule, contract_path)
    contract = try
        load_contract(contract_path)
    catch error
        fail("contract", sprint(showerror, error))
    end
    file_sha256(contract_path) == CONTRACT_FILE_SHA256 ||
        fail("contract", "file SHA-256 differs from frozen schedule binding")
    artifact = contract["artifact"]
    expect_exact(
        artifact["contract_id"],
        CONTRACT_ID,
        "contract.artifact.contract_id",
    )
    expect_exact(
        artifact["content_sha256"],
        CONTRACT_CONTENT_SHA256,
        "contract.artifact.content_sha256",
    )
    policy = schedule["policy"]
    expected = Dict(
        FIRST_WINDOW_ID => (
            end_date = policy["first_campaign_end_date"],
            scheduled = policy["first_scheduled_time_utc"],
            role = "first_state_candidate",
        ),
        REVISION_WINDOW_ID => (
            end_date = policy["revision_campaign_end_date"],
            scheduled = policy["revision_scheduled_time_utc"],
            role = "same_day_revision_candidate",
        ),
    )
    for window_id in (FIRST_WINDOW_ID, REVISION_WINDOW_ID)
        window = _contract_window(contract, window_id)
        spec = expected[window_id]
        expect_exact(window["source_id"], SOURCE_ID, "$window_id.source_id")
        expect_exact(
            window["requirement_id"],
            REQUIREMENT_ID,
            "$window_id.requirement_id",
        )
        expect_exact(
            window["campaign_start_date"],
            policy["campaign_start_date"],
            "$window_id.campaign_start_date",
        )
        expect_exact(
            window["campaign_end_date"],
            spec.end_date,
            "$window_id.campaign_end_date",
        )
        expect_exact(
            window["scheduled_time_utc"],
            spec.scheduled,
            "$window_id.scheduled_time_utc",
        )
        expect_exact(
            window["capture_window_minutes"],
            policy["capture_window_minutes"],
            "$window_id.capture_window_minutes",
        )
        expect_exact(
            window["business_day_rule"],
            policy["business_day_rule"],
            "$window_id.business_day_rule",
        )
        expect_exact(
            window["excluded_dates"],
            policy["excluded_dates"],
            "$window_id.excluded_dates",
        )
        expect_exact(
            window["evidence_role"],
            spec.role,
            "$window_id.evidence_role",
        )
        expect_exact(
            window["origin_day_completion_before_cutoff_required"],
            true,
            "$window_id.origin_day_completion_before_cutoff_required",
        )
    end
    return contract
end

function _expected_publication_dates(policy)
    start_date = expect_date(
        policy["campaign_start_date"],
        "schedule.policy.campaign_start_date",
    )
    end_date = expect_date(
        policy["first_campaign_end_date"],
        "schedule.policy.first_campaign_end_date",
    )
    excluded = Set(
        expect_date(value, "schedule.policy.excluded_dates")
            for value in policy["excluded_dates"]
    )
    return [
        date for date in start_date:Day(1):end_date if
            dayofweek(date) <= 5 && !(date in excluded)
    ]
end

function validate_schedule(
        schedule;
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH,
    )
    root = expect_exact_keys(
        schedule,
        ("artifact", "policy", "gates", "days"),
        "schedule",
    )
    artifact = expect_exact_keys(
        root["artifact"],
        (
            "schema_version",
            "schedule_id",
            "status",
            "canonicalization",
            "digest_algorithm",
            "content_sha256",
            "prospective_contract_id",
            "prospective_contract_content_sha256",
            "prospective_contract_file_sha256",
        ),
        "schedule.artifact",
    )
    expect_exact(
        artifact["schema_version"],
        SCHEDULE_SCHEMA,
        "schedule.artifact.schema_version",
    )
    expect_exact(
        artifact["schedule_id"],
        SCHEDULE_ID,
        "schedule.artifact.schedule_id",
    )
    expect_exact(
        artifact["status"],
        "FROZEN_CONTROL_ONLY_NONADMITTING",
        "schedule.artifact.status",
    )
    expect_exact(
        artifact["canonicalization"],
        "sorted-typed-length-aware-excluding-artifact-content-sha256.v1",
        "schedule.artifact.canonicalization",
    )
    expect_exact(
        artifact["digest_algorithm"],
        "sha256",
        "schedule.artifact.digest_algorithm",
    )
    expect_hash(artifact["content_sha256"], "schedule.artifact.content_sha256")
    expect_exact(
        artifact["content_sha256"],
        computed_schedule_sha256(root),
        "schedule.artifact.content_sha256",
    )
    expect_exact(
        artifact["prospective_contract_id"],
        CONTRACT_ID,
        "schedule.artifact.prospective_contract_id",
    )
    expect_exact(
        artifact["prospective_contract_content_sha256"],
        CONTRACT_CONTENT_SHA256,
        "schedule.artifact.prospective_contract_content_sha256",
    )
    expect_exact(
        artifact["prospective_contract_file_sha256"],
        CONTRACT_FILE_SHA256,
        "schedule.artifact.prospective_contract_file_sha256",
    )
    policy = expect_exact_keys(
        root["policy"],
        (
            "source_id",
            "requirement_id",
            "campaign_id",
            "first_window_id",
            "revision_window_id",
            "campaign_start_date",
            "first_campaign_end_date",
            "revision_campaign_end_date",
            "initial_effective_date",
            "first_scheduled_time_utc",
            "first_deadline_time_utc",
            "revision_scheduled_time_utc",
            "revision_deadline_time_utc",
            "capture_window_minutes",
            "business_day_rule",
            "effective_date_rule",
            "excluded_dates",
            "expected_first_state_count",
            "expected_revision_check_count",
            "expected_slot_count",
            "origin_timestamp_utc",
        ),
        "schedule.policy",
    )
    expect_exact(policy["source_id"], SOURCE_ID, "schedule.policy.source_id")
    expect_exact(
        policy["requirement_id"],
        REQUIREMENT_ID,
        "schedule.policy.requirement_id",
    )
    expect_exact(
        policy["campaign_id"],
        CAMPAIGN_ID,
        "schedule.policy.campaign_id",
    )
    expect_exact(
        policy["first_window_id"],
        FIRST_WINDOW_ID,
        "schedule.policy.first_window_id",
    )
    expect_exact(
        policy["revision_window_id"],
        REVISION_WINDOW_ID,
        "schedule.policy.revision_window_id",
    )
    expect_exact(
        policy["effective_date_rule"],
        "PREVIOUS_AUTHORIZED_PUBLICATION_DAY_WITH_INITIAL_SEED",
        "schedule.policy.effective_date_rule",
    )
    expect_int(
        policy["capture_window_minutes"],
        "schedule.policy.capture_window_minutes";
        minimum = 1,
    ) == 15 ||
        fail("schedule.policy.capture_window_minutes", "must be 15")
    first_start =
        expect_time(policy["first_scheduled_time_utc"], "schedule.policy")
    first_deadline =
        expect_time(policy["first_deadline_time_utc"], "schedule.policy")
    revision_start =
        expect_time(policy["revision_scheduled_time_utc"], "schedule.policy")
    revision_deadline =
        expect_time(policy["revision_deadline_time_utc"], "schedule.policy")
    first_deadline - first_start == Minute(15) ||
        fail("schedule.policy", "first-state window must be 15 minutes")
    revision_deadline - revision_start == Minute(15) ||
        fail("schedule.policy", "revision window must be 15 minutes")
    gates = expect_exact_keys(
        root["gates"],
        ALWAYS_FALSE_GATE_KEYS,
        "schedule.gates",
    )
    for key in ALWAYS_FALSE_GATE_KEYS
        expect_exact(gates[key], false, "schedule.gates.$key")
    end
    days = expect_array(root["days"], "schedule.days")
    expected_dates = _expected_publication_dates(policy)
    expect_int(
        policy["expected_first_state_count"],
        "schedule.policy.expected_first_state_count",
    ) == length(expected_dates) ||
        fail("schedule.policy.expected_first_state_count", "calendar mismatch")
    length(days) == length(expected_dates) ||
        fail("schedule.days", "explicit schedule does not cover expected dates")
    previous_effective = expect_date(
        policy["initial_effective_date"],
        "schedule.policy.initial_effective_date",
    )
    revision_end = expect_date(
        policy["revision_campaign_end_date"],
        "schedule.policy.revision_campaign_end_date",
    )
    revision_count = 0
    for (index, value) in enumerate(days)
        row = expect_exact_keys(
            value,
            (
                "sequence",
                "publication_date",
                "effective_date",
                "revision_check_required",
            ),
            "schedule.days[$index]",
        )
        expect_int(row["sequence"], "schedule.days[$index].sequence") == index ||
            fail("schedule.days[$index].sequence", "must equal $index")
        publication =
            expect_date(row["publication_date"], "schedule.days[$index]")
        effective =
            expect_date(row["effective_date"], "schedule.days[$index]")
        publication == expected_dates[index] ||
            fail("schedule.days[$index]", "publication calendar mismatch")
        effective == previous_effective ||
            fail("schedule.days[$index]", "effective-date chain mismatch")
        required = expect_bool(
            row["revision_check_required"],
            "schedule.days[$index].revision_check_required",
        )
        required == (publication <= revision_end) ||
            fail("schedule.days[$index]", "revision terminal date mismatch")
        revision_count += required
        previous_effective = publication
    end
    expect_int(
        policy["expected_revision_check_count"],
        "schedule.policy.expected_revision_check_count",
    ) == revision_count ||
        fail("schedule.policy.expected_revision_check_count", "calendar mismatch")
    expect_int(
        policy["expected_slot_count"],
        "schedule.policy.expected_slot_count",
    ) == length(days) + revision_count ||
        fail("schedule.policy.expected_slot_count", "slot count mismatch")
    origin =
        expect_timestamp(policy["origin_timestamp_utc"], "schedule.policy")
    final_first_deadline = DateTime(last(expected_dates), first_deadline)
    final_first_deadline < origin ||
        fail("schedule.policy", "origin-day capture does not precede origin")
    _validate_contract_binding(root, contract_path)
    return (
        schedule_id = SCHEDULE_ID,
        content_sha256 = artifact["content_sha256"],
        first_state_count = length(days),
        revision_check_count = revision_count,
        slot_count = length(days) + revision_count,
    )
end

function load_schedule(
        path::AbstractString = DEFAULT_SCHEDULE_PATH;
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH,
    )
    isfile(path) || fail("schedule", "missing file $path")
    islink(path) && fail("schedule", "refuses symbolic link $path")
    schedule = TOML.parsefile(path)
    validate_schedule(schedule; contract_path)
    return schedule
end

function _phase(value)
    value isa AbstractString ||
        fail("phase", "must be the string first or revision-check")
    phase = String(value)
    phase in ("first", "revision-check") ||
        fail("phase", "must be first or revision-check")
    return phase
end

function _capture_authorization(
        schedule,
        publication_date,
        phase;
        observed_at_utc = nothing,
    )
    publication = publication_date isa Date ?
        publication_date :
        expect_date(publication_date, "publication_date")
    selected_phase = _phase(phase)
    matches = [
        (index, row) for (index, row) in enumerate(schedule["days"]) if
            Date(row["publication_date"]) == publication
    ]
    length(matches) == 1 ||
        fail("publication_date", "is not an authorized campaign date")
    sequence, row = only(matches)
    if selected_phase == "revision-check" &&
            !row["revision_check_required"]
        fail("phase", "revision check is not authorized for $publication")
    end
    policy = schedule["policy"]
    start_time = expect_time(
        policy[
            selected_phase == "first" ?
                "first_scheduled_time_utc" :
                "revision_scheduled_time_utc",
        ],
        "schedule.policy",
    )
    deadline_time = expect_time(
        policy[
            selected_phase == "first" ?
                "first_deadline_time_utc" :
                "revision_deadline_time_utc",
        ],
        "schedule.policy",
    )
    start = DateTime(publication, start_time)
    deadline = DateTime(publication, deadline_time)
    if observed_at_utc !== nothing
        observed = observed_at_utc isa DateTime ?
            observed_at_utc :
            expect_timestamp(observed_at_utc, "observed_at_utc")
        start <= observed <= deadline ||
            fail("observed_at_utc", "is outside the frozen capture window")
    end
    return CaptureAuthorization(
        SCHEDULE_ID,
        sequence,
        selected_phase,
        publication,
        Date(row["effective_date"]),
        start,
        deadline,
        selected_phase == "first" ?
            "FIRST_0900_STATE" :
            "SAME_DAY_1430_REVISION_CHECK",
        false,
        false,
        false,
        false,
    )
end

function capture_authorization(
        schedule,
        publication_date,
        phase;
        observed_at_utc = nothing,
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH,
    )
    validate_schedule(schedule; contract_path)
    return _capture_authorization(
        schedule,
        publication_date,
        phase;
        observed_at_utc,
    )
end

function validated_bundle_manifest(validation_result)
    hasproperty(validation_result, :bundle_path) ||
        fail("validated bundle", "missing bundle_path")
    hasproperty(validation_result, :manifest) ||
        fail("validated bundle", "missing manifest")
    path = abspath(expect_string(validation_result.bundle_path, "bundle_path"))
    manifest = deepcopy(
        expect_table(validation_result.manifest, "validated bundle manifest"),
    )
    return ValidatedBundleManifest(path, Dict{String, Any}(manifest))
end

function _manifest_object(manifest, object_id)
    objects = expect_array(manifest["objects"], "manifest.objects")
    matches = [
        object for object in objects if
            get(object, "object_id", nothing) == object_id
    ]
    length(matches) == 1 ||
        fail("manifest.objects", "expected exactly one $object_id")
    return expect_table(only(matches), "manifest.objects.$object_id")
end

function _validate_current_state_semantics(manifest, status)
    identities =
        expect_array(manifest["row_identity"], "manifest.row_identity")
    length(identities) == 2 ||
        fail("manifest.row_identity", "must contain rate and volume identities")
    report_types = Set{String}()
    absent_rows = 0
    present_false_rows = 0
    for (index, value) in enumerate(identities)
        row = expect_keys(
            value,
            (
                "report_type",
                "raw_current_state_present",
                "raw_current_state_value",
                "current_state_source",
                "alias_or_first_row_fallback_used",
            ),
            "manifest.row_identity[$index]",
        )
        report_type = expect_string(
            row["report_type"],
            "manifest.row_identity[$index].report_type",
        )
        report_type in ("rate", "volume") ||
            fail("manifest.row_identity[$index]", "unknown report type")
        push!(report_types, report_type)
        expect_exact(
            row["alias_or_first_row_fallback_used"],
            false,
            "manifest.row_identity[$index]",
        )
        present = expect_bool(
            row["raw_current_state_present"],
            "manifest.row_identity[$index].raw_current_state_present",
        )
        if !present
            expect_exact(
                row["raw_current_state_value"],
                "ABSENT",
                "manifest.row_identity[$index]",
            )
            expect_exact(
                row["current_state_source"],
                "ABSENT_FROM_RAW_RESPONSE_NOT_DERIVED",
                "manifest.row_identity[$index]",
            )
            absent_rows += 1
        else
            expect_exact(
                row["raw_current_state_value"],
                "false",
                "manifest.row_identity[$index]",
            )
            expect_exact(
                row["current_state_source"],
                "RAW_FIELD_FALSE",
                "manifest.row_identity[$index]",
            )
            present_false_rows += 1
        end
    end
    report_types == Set(["rate", "volume"]) ||
        fail("manifest.row_identity", "must contain rate and volume once")
    result = manifest["result"]
    blockers = Set(String.(manifest["blockers"]))
    (absent_rows == 2 || present_false_rows == 2) ||
        fail(
        "manifest.row_identity",
        "currentState evidence may not mix present and absent rows",
    )
    absent = absent_rows == 2
    incompatible = status ==
        "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
    if incompatible
        absent ||
            fail(
            "manifest.result.status",
            "compatibility status requires absent raw currentState",
        )
        expect_exact(
            result["failure_code"],
            CURRENT_STATE_BLOCKER,
            "manifest.result.failure_code",
        )
        CURRENT_STATE_BLOCKER in blockers ||
            fail("manifest.blockers", "missing absent-currentState blocker")
        expect_exact(
            result["one_date_receipt_validated"],
            false,
            "manifest.result.one_date_receipt_validated",
        )
        expect_exact(
            result["revision_receipt_created"],
            false,
            "manifest.result.revision_receipt_created",
        )
        for key in ("rate_receipt_file", "volume_receipt_file")
            expect_exact(result[key], "NONE", "manifest.result.$key")
        end
    elseif status ==
            "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
        expect_exact(
            result["one_date_receipt_validated"],
            false,
            "manifest.result.one_date_receipt_validated",
        )
        expect_exact(
            result["revision_receipt_created"],
            false,
            "manifest.result.revision_receipt_created",
        )
    elseif absent
        fail(
            "manifest.result.status",
            "receipt candidate may not derive absent currentState as false",
        )
    elseif CURRENT_STATE_BLOCKER in blockers
        fail(
            "manifest.blockers",
            "absent-currentState blocker conflicts with receipt status",
        )
    end
    return absent
end

function expect_none_or_hash(value, location)
    text = expect_string(value, location)
    text == "NONE" && return text
    return expect_hash(text, location)
end

function _require_receipts(result, location)
    for key in ("rate_receipt_file", "volume_receipt_file")
        value = expect_string(result[key], "$location.$key")
        value != "NONE" || fail("$location.$key", "must name a receipt")
    end
    for key in ("rate_receipt_sha256", "volume_receipt_sha256")
        expect_hash(result[key], "$location.$key")
    end
    return
end

function _require_no_receipts(result, location)
    for key in (
            "rate_receipt_file",
            "volume_receipt_file",
            "rate_receipt_sha256",
            "volume_receipt_sha256",
        )
        expect_exact(result[key], "NONE", "$location.$key")
    end
    return
end

function _require_real_predecessor(result, location; hashes_required)
    predecessor =
        expect_string(result["predecessor_bundle"], "$location.predecessor_bundle")
    predecessor != "NOT_APPLICABLE" ||
        fail("$location.predecessor_bundle", "must name the first-state bundle")
    for key in (
            "predecessor_rate_receipt_sha256",
            "predecessor_volume_receipt_sha256",
        )
        if hashes_required
            expect_hash(result[key], "$location.$key")
        else
            expect_none_or_hash(result[key], "$location.$key")
        end
    end
    return
end

function _validate_status_matrix(result, status, phase, current_state_absent)
    location = "manifest.result"
    one_date = expect_bool(
        result["one_date_receipt_validated"],
        "$location.one_date_receipt_validated",
    )
    revision_observed = expect_bool(
        result["revision_observed"],
        "$location.revision_observed",
    )
    revision_created = expect_bool(
        result["revision_receipt_created"],
        "$location.revision_receipt_created",
    )
    failure_code = expect_string(result["failure_code"], "$location.failure_code")
    if status ==
            "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
        phase == "first" ||
            fail(location, "first-state candidate requires phase first")
        current_state_absent &&
            fail(location, "first-state candidate requires raw currentState=false")
        one_date || fail(location, "first-state candidate requires one-date receipts")
        !revision_observed ||
            fail(location, "first-state candidate cannot observe a revision")
        !revision_created ||
            fail(location, "first-state candidate cannot create revision receipts")
        failure_code == "NONE" ||
            fail(location, "first-state candidate requires failure_code NONE")
        _require_receipts(result, location)
        expect_exact(
            result["predecessor_bundle"],
            "NOT_APPLICABLE",
            "$location.predecessor_bundle",
        )
        for key in (
                "predecessor_rate_receipt_sha256",
                "predecessor_volume_receipt_sha256",
            )
            expect_exact(result[key], "NONE", "$location.$key")
        end
    elseif status ==
            "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE"
        phase == "revision-check" ||
            fail(location, "revision candidate requires phase revision-check")
        current_state_absent &&
            fail(location, "revision candidate requires raw currentState=false")
        one_date || fail(location, "revision candidate requires one-date receipts")
        revision_observed ||
            fail(location, "revision candidate must observe a revision")
        revision_created ||
            fail(location, "revision candidate must create revision receipts")
        failure_code == "NONE" ||
            fail(location, "revision candidate requires failure_code NONE")
        _require_receipts(result, location)
        _require_real_predecessor(result, location; hashes_required = true)
    elseif status == "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
        phase == "revision-check" ||
            fail(location, "byte-identical status requires phase revision-check")
        !one_date ||
            fail(location, "byte-identical status cannot validate one-date receipts")
        !revision_observed ||
            fail(location, "byte-identical status cannot observe a revision")
        !revision_created ||
            fail(location, "byte-identical status cannot create revision receipts")
        failure_code == "NONE" ||
            fail(location, "byte-identical status requires failure_code NONE")
        _require_no_receipts(result, location)
        _require_real_predecessor(result, location; hashes_required = false)
    elseif status ==
            "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
        current_state_absent ||
            fail(location, "incompatible status requires absent raw currentState")
        !one_date ||
            fail(location, "incompatible status cannot validate one-date receipts")
        !revision_created ||
            fail(location, "incompatible status cannot create revision receipts")
        failure_code == CURRENT_STATE_BLOCKER ||
            fail(location, "incompatible status requires the currentState blocker")
        _require_no_receipts(result, location)
        if phase == "first"
            !revision_observed ||
                fail(location, "first phase cannot observe a revision")
            expect_exact(
                result["predecessor_bundle"],
                "NOT_APPLICABLE",
                "$location.predecessor_bundle",
            )
            for key in (
                    "predecessor_rate_receipt_sha256",
                    "predecessor_volume_receipt_sha256",
                )
                expect_exact(result[key], "NONE", "$location.$key")
            end
        else
            _require_real_predecessor(
                result,
                location;
                hashes_required = false,
            )
        end
    else
        fail(location, "unhandled completed status")
    end
    return nothing
end

function _validate_manifest(schedule, bundle)
    manifest = expect_keys(
        bundle.manifest,
        (
            "artifact",
            "contract_binding",
            "event",
            "capture",
            "objects",
            "row_identity",
            "result",
            "blockers",
            "gates",
        ),
        "manifest",
    )
    artifact = expect_keys(
        manifest["artifact"],
        ("manifest_id", "manifest_sha256", "schema_version"),
        "manifest.artifact",
    )
    manifest_id = expect_string(
        artifact["manifest_id"],
        "manifest.artifact.manifest_id",
    )
    manifest_sha256 = expect_hash(
        artifact["manifest_sha256"],
        "manifest.artifact.manifest_sha256",
    )
    binding = expect_keys(
        manifest["contract_binding"],
        (
            "prospective_contract_id",
            "prospective_contract_content_sha256",
            "prospective_contract_file_sha256",
            "prospective_contract_status",
        ),
        "manifest.contract_binding",
    )
    expect_exact(
        binding["prospective_contract_id"],
        CONTRACT_ID,
        "manifest.contract_binding.prospective_contract_id",
    )
    expect_exact(
        binding["prospective_contract_content_sha256"],
        CONTRACT_CONTENT_SHA256,
        "manifest.contract_binding.prospective_contract_content_sha256",
    )
    expect_exact(
        binding["prospective_contract_file_sha256"],
        CONTRACT_FILE_SHA256,
        "manifest.contract_binding.prospective_contract_file_sha256",
    )
    expect_exact(
        binding["prospective_contract_status"],
        "DRAFT_UNAPPROVED_FAIL_CLOSED",
        "manifest.contract_binding.prospective_contract_status",
    )
    event = expect_keys(
        manifest["event"],
        (
            "campaign_id",
            "phase",
            "publication_date",
            "effective_date",
            "scheduled_time_utc",
            "capture_deadline_utc",
            "state_class_candidate",
        ),
        "manifest.event",
    )
    expect_exact(
        event["campaign_id"],
        CAMPAIGN_ID,
        "manifest.event.campaign_id",
    )
    authorization = _capture_authorization(
        schedule,
        event["publication_date"],
        event["phase"],
    )
    expect_exact(
        expect_date(event["effective_date"], "manifest.event.effective_date"),
        authorization.effective_date,
        "manifest.event.effective_date",
    )
    expect_exact(
        expect_timestamp(
            event["scheduled_time_utc"],
            "manifest.event.scheduled_time_utc",
        ),
        authorization.window_start_utc,
        "manifest.event.scheduled_time_utc",
    )
    expect_exact(
        expect_timestamp(
            event["capture_deadline_utc"],
            "manifest.event.capture_deadline_utc",
        ),
        authorization.window_deadline_utc,
        "manifest.event.capture_deadline_utc",
    )
    expect_exact(
        event["state_class_candidate"],
        authorization.state_class_candidate,
        "manifest.event.state_class_candidate",
    )
    gates = expect_table(manifest["gates"], "manifest.gates")
    for key in MANIFEST_FALSE_GATE_KEYS
        haskey(gates, key) || fail("manifest.gates", "missing $key")
        expect_exact(gates[key], false, "manifest.gates.$key")
    end
    result = expect_keys(
        manifest["result"],
        (
            "status",
            "success",
            "raw_capture_complete",
            "failure_code",
            "rate_receipt_file",
            "volume_receipt_file",
            "rate_receipt_sha256",
            "volume_receipt_sha256",
            "predecessor_bundle",
            "predecessor_rate_receipt_sha256",
            "predecessor_volume_receipt_sha256",
            "revision_observed",
            "revision_receipt_created",
            "one_date_receipt_validated",
        ),
        "manifest.result",
    )
    status = expect_string(result["status"], "manifest.result.status")
    status in ACCEPTED_STATUSES ||
        fail("manifest.result.status", "is not a completed control status")
    expect_exact(result["success"], true, "manifest.result.success")
    expect_exact(
        result["raw_capture_complete"],
        true,
        "manifest.result.raw_capture_complete",
    )
    absent = _validate_current_state_semantics(manifest, status)
    _validate_status_matrix(
        result,
        status,
        authorization.phase,
        absent,
    )
    effective = string(authorization.effective_date)
    for report_type in ("rate", "volume")
        object = _manifest_object(manifest, "$(report_type)_response")
        expected_query =
            "endDate=$effective&startDate=$effective&type=$report_type"
        expect_exact(
            object["canonical_query"],
            expected_query,
            "manifest.objects.$report_type.canonical_query",
        )
        expect_exact(
            object["requested_url"],
            "$API_ENDPOINT?$expected_query",
            "manifest.objects.$report_type.requested_url",
        )
    end
    capture = expect_keys(
        manifest["capture"],
        ("transaction_id",),
        "manifest.capture",
    )
    transaction_id =
        expect_string(capture["transaction_id"], "manifest.capture.transaction_id")
    return (
        slot_id = "$(authorization.publication_date):$(authorization.phase)",
        authorization,
        bundle_path = bundle.bundle_path,
        manifest_id,
        manifest_sha256,
        transaction_id,
        status,
        current_state_absent = absent,
        predecessor_bundle = expect_string(
            result["predecessor_bundle"],
            "manifest.result.predecessor_bundle",
        ),
        predecessor_rate_receipt_sha256 = expect_string(
            result["predecessor_rate_receipt_sha256"],
            "manifest.result.predecessor_rate_receipt_sha256",
        ),
        predecessor_volume_receipt_sha256 = expect_string(
            result["predecessor_volume_receipt_sha256"],
            "manifest.result.predecessor_volume_receipt_sha256",
        ),
        rate_receipt_sha256 = expect_string(
            result["rate_receipt_sha256"],
            "manifest.result.rate_receipt_sha256",
        ),
        volume_receipt_sha256 = expect_string(
            result["volume_receipt_sha256"],
            "manifest.result.volume_receipt_sha256",
        ),
    )
end

function _expected_slot_ids(schedule)
    slots = String[]
    for row in schedule["days"]
        date = row["publication_date"]
        push!(slots, "$date:first")
        row["revision_check_required"] &&
            push!(slots, "$date:revision-check")
    end
    return slots
end

function evaluate_campaign(
        schedule,
        validated_bundles;
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH,
    )
    validation = validate_schedule(schedule; contract_path)
    bundles = expect_array(validated_bundles, "validated_bundles")
    records = NamedTuple[]
    rejected = String[]
    for (index, value) in enumerate(bundles)
        value isa ValidatedBundleManifest ||
            fail(
            "validated_bundles[$index]",
            "must be a ValidatedBundleManifest",
        )
        try
            push!(records, _validate_manifest(schedule, value))
        catch error
            error isa CampaignControlError || rethrow()
            push!(rejected, "bundle[$index]:$(sprint(showerror, error))")
        end
    end
    by_slot = Dict{String, Vector{Int}}()
    for (index, record) in enumerate(records)
        push!(get!(by_slot, record.slot_id, Int[]), index)
    end
    duplicate_slots =
        sort!([slot for (slot, indices) in by_slot if length(indices) != 1])
    accepted = Dict{String, NamedTuple}()
    for (slot, indices) in by_slot
        length(indices) == 1 || continue
        accepted[slot] = records[only(indices)]
    end
    expected_slots = _expected_slot_ids(schedule)
    missing_slots =
        sort!(collect(setdiff(Set(expected_slots), Set(keys(accepted)))))
    unexpected_slots =
        sort!(collect(setdiff(Set(keys(accepted)), Set(expected_slots))))
    identity_failures = String[]
    for field in (
            :bundle_path,
            :manifest_id,
            :manifest_sha256,
            :transaction_id,
        )
        seen = Dict{String, String}()
        for record in values(accepted)
            value = getproperty(record, field)
            if haskey(seen, value)
                push!(
                    identity_failures,
                    "$(field):$(seen[value]) aliases $(record.slot_id)",
                )
            else
                seen[value] = record.slot_id
            end
        end
    end
    predecessor_failures = String[]
    for row in schedule["days"]
        date = row["publication_date"]
        revision_slot = "$date:revision-check"
        haskey(accepted, revision_slot) || continue
        first_slot = "$date:first"
        haskey(accepted, first_slot) || begin
            push!(predecessor_failures, "$revision_slot:MISSING_FIRST_STATE")
            continue
        end
        revision = accepted[revision_slot]
        first = accepted[first_slot]
        revision.predecessor_bundle == first.bundle_path ||
            push!(
            predecessor_failures,
            "$revision_slot:PREDECESSOR_PATH_MISMATCH",
        )
        for (label, predecessor, receipt) in (
                (
                    "RATE",
                    revision.predecessor_rate_receipt_sha256,
                    first.rate_receipt_sha256,
                ),
                (
                    "VOLUME",
                    revision.predecessor_volume_receipt_sha256,
                    first.volume_receipt_sha256,
                ),
            )
            predecessor == receipt ||
                push!(
                predecessor_failures,
                "$revision_slot:PREDECESSOR_$(label)_RECEIPT_MISMATCH",
            )
        end
    end
    compatibility_blocker_slots = sort!(
        [
            record.slot_id for record in values(accepted) if
                record.current_state_absent
        ],
    )
    raw_capture_coverage_complete =
        isempty(missing_slots) &&
        isempty(unexpected_slots) &&
        isempty(duplicate_slots) &&
        isempty(rejected) &&
        isempty(identity_failures) &&
        isempty(predecessor_failures)
    receipt_semantics_complete =
        raw_capture_coverage_complete &&
        isempty(compatibility_blocker_slots)
    status = if !isempty(rejected) ||
            !isempty(duplicate_slots) ||
            !isempty(identity_failures) ||
            !isempty(predecessor_failures) ||
            !isempty(unexpected_slots)
        "CAMPAIGN_CONTROL_INVALID"
    elseif !raw_capture_coverage_complete
        "CAMPAIGN_CONTROL_INCOMPLETE"
    elseif !receipt_semantics_complete
        "RAW_CAPTURE_COVERAGE_COMPLETE_RECEIPT_SEMANTICS_BLOCKED"
    else
        "LOCAL_RECEIPT_COVERAGE_CANDIDATE_NONADMITTING"
    end
    return (
        status,
        schedule_id = validation.schedule_id,
        schedule_sha256 = validation.content_sha256,
        expected_slot_count = validation.slot_count,
        accepted_slot_count = length(accepted),
        missing_slot_ids = missing_slots,
        unexpected_slot_ids = unexpected_slots,
        duplicate_slot_ids = duplicate_slots,
        rejected_bundles = rejected,
        identity_failures = sort!(identity_failures),
        predecessor_failures = sort!(predecessor_failures),
        compatibility_blocker_slot_ids = compatibility_blocker_slots,
        raw_capture_coverage_complete,
        receipt_semantics_complete,
        profile_completion_authorized = false,
        profile_complete = false,
        inventory_mutation_authorized = false,
        origin_admissible = false,
        accuracy_evaluation_allowed = false,
        promotion_eligible = false,
        production_scoring_allowed = false,
        ready = false,
    )
end

end
