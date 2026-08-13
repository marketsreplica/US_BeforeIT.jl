module USEFFRCampaignRestartV2

using Dates
using SHA
using TOML

export CampaignRestartError,
    DEFAULT_SCHEDULE_PATH,
    RestartSlot,
    computed_schedule_sha256,
    load_restart_schedule,
    planned_slot,
    validate_restart_schedule

const DEFAULT_SCHEDULE_PATH =
    joinpath(@__DIR__, "effr_2026q3_restart_schedule_v2.toml")
const SOURCE_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const SCHEMA_VERSION = "beforeit-us-effr-campaign-restart-schedule.v2"
const SCHEDULE_ID = "beforeit-us-effr-2026q3-prospective-restart-20260810.v2"
const CAMPAIGN_ID =
    "frbny_effr_daily_first_state_and_revision_check_restart_20260810"
const PREDECESSOR_SCHEDULE_ID =
    "beforeit-us-effr-2026q3-prospective-campaign.v1"
const PREDECESSOR_CAMPAIGN_ID =
    "frbny_effr_daily_first_state_and_revision_check"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const OUTPUT_ROOT =
    "data/us/raw/forecasting/effr/prospective/2026q3_restart_v2"
const FIRST_STATE = "FIRST_0900_STATE"
const REVISION_STATE = "SAME_DAY_1430_REVISION_CHECK"
const FIRST_PHASE = "first"
const REVISION_PHASE = "revision-check"
const EXCLUDED_DATES = (Date(2026, 9, 7), Date(2026, 10, 12))
const MADRID_STANDARD_TIME_START = Date(2026, 10, 26)

const BINDING_SPECS = (
    (
        id = "recurring_module",
        relative_path =
            "forecasting/vintages/effr/recurring_acquisition/USEFFRRecurringAcquisition.jl",
        sha256 =
            "3685e0c0ca3d440bdf2816d3c3bc229656d4a2339d6009b34f2c754c4a7051de",
    ),
    (
        id = "recurring_cli",
        relative_path =
            "forecasting/vintages/effr/recurring_acquisition/capture_effr_recurring.jl",
        sha256 =
            "e2f293dd77da818c5fd0ee64e8bb520a162f62e805c17fdc6cf6131f6db3800f",
    ),
    (
        id = "recurring_tests",
        relative_path =
            "forecasting/vintages/effr/recurring_acquisition/test_effr_recurring_acquisition.jl",
        sha256 =
            "256eac940dace2e749efb98be33e9ba059f21883da5b6d0bf92fdac2beb7e41b",
    ),
    (
        id = "recurring_readme",
        relative_path =
            "forecasting/vintages/effr/recurring_acquisition/README.md",
        sha256 =
            "052d02b3117037d86830de50783f43f782907ae84824fa7507acd36b70784d02",
    ),
    (
        id = "capture_contract_module",
        relative_path =
            "forecasting/vintages/effr/capture_contract/USEFFRCaptureContract.jl",
        sha256 =
            "6c4ee3ff95b92daf34899db64dbff7fc920eb33e5bc4bf17a6adf99bf3b3f651",
    ),
    (
        id = "capture_contract_tests",
        relative_path =
            "forecasting/vintages/effr/capture_contract/test_effr_capture_contract.jl",
        sha256 =
            "6356f2f8ae4efb74ecbd063fb962f82a423d36c665276449679da3b197af3197",
    ),
    (
        id = "capture_contract_readme",
        relative_path =
            "forecasting/vintages/effr/capture_contract/README.md",
        sha256 =
            "6bc9934611c5641eed63a4802ac6dd83a55e0abe796e6f817a6a2855fecce326",
    ),
    (
        id = "project",
        relative_path = "Project.toml",
        sha256 =
            "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c",
    ),
    (
        id = "manifest",
        relative_path = "Manifest.toml",
        sha256 =
            "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263",
    ),
    (
        id = "current_inventory",
        relative_path = "forecasting/vintages/current_inventory.toml",
        sha256 =
            "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae",
    ),
    (
        id = "predecessor_campaign_module",
        relative_path =
            "forecasting/vintages/effr/campaign/USEFFRCampaignControl.jl",
        sha256 =
            "83db9b24f88e7ad48ba21726f7905b2ba7a00638e681ff40d8fdcf0c728edd02",
    ),
    (
        id = "predecessor_campaign_schedule",
        relative_path =
            "forecasting/vintages/effr/campaign/effr_2026q3_campaign_schedule.toml",
        sha256 =
            "ddbc7a089a636d09f97e68e67da7f534ecca6c88d6b7dbc8bf78080ce7400e25",
    ),
    (
        id = "predecessor_campaign_tests",
        relative_path =
            "forecasting/vintages/effr/campaign/test_effr_campaign_control.jl",
        sha256 =
            "f7b51987952baddccc254bce70aa22b7d1a1179b21f3d1e4169fdad2963b9cce",
    ),
    (
        id = "predecessor_campaign_readme",
        relative_path = "forecasting/vintages/effr/campaign/README.md",
        sha256 =
            "fe4fd2db322674a9f1773016f9c7aae2e618670cc449d1138809570cc306a7f5",
    ),
    (
        id = "observed_state_module",
        relative_path =
            "forecasting/vintages/effr/observed_state_contract/USEFFRObservedStateContractV3.jl",
        sha256 =
            "3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6",
    ),
    (
        id = "observed_state_protocol",
        relative_path =
            "forecasting/vintages/effr/observed_state_contract/observed_state_contract_v3.toml",
        sha256 =
            "d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716",
    ),
    (
        id = "observed_state_tests",
        relative_path =
            "forecasting/vintages/effr/observed_state_contract/test_effr_observed_state_contract_v3.jl",
        sha256 =
            "55bfbf5a4b252804f4e3b2e91100c83b8ff98bffbf10eec5bdd3bd83d96ad66c",
    ),
    (
        id = "observed_state_readme",
        relative_path =
            "forecasting/vintages/effr/observed_state_contract/README.md",
        sha256 =
            "4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23",
    ),
)

const FALSE_GATE_KEYS = (
    "network_execution_authorized",
    "raw_data_write_authorized",
    "inventory_mutation_authorized",
    "profile_completion_authorized",
    "origin_admissible",
    "accuracy_evaluation_allowed",
    "empirical_forecast_allowed",
    "production_scoring_allowed",
    "promotion_eligible",
    "production_use_allowed",
    "ready",
)

struct CampaignRestartError <: Exception
    message::String
end

Base.showerror(io::IO, error::CampaignRestartError) = print(io, error.message)

fail(location, message) =
    throw(CampaignRestartError("$location: $message"))

struct RestartSlot
    schedule_id::String
    sequence::Int
    day_sequence::Int
    publication_date::Date
    effective_date::Date
    phase::String
    state_class::String
    scheduled_at_utc::DateTime
    deadline_at_utc::DateTime
    scheduled_at_new_york::String
    deadline_at_new_york::String
    scheduled_at_madrid::String
    deadline_at_madrid::String
    transaction_id::String
    bundle_path::String
    journal_path::String
    predecessor_bundle_path::String
    rate_query::String
    volume_query::String
    network_execution_authorized::Bool
    raw_data_write_authorized::Bool
    origin_admissible::Bool
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
    isempty(missing) || fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) || fail(location, "unknown keys: $(join(unknown, ", "))")
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
    typeof(value) === typeof(expected) && value == expected ||
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
    date = try
        Date(text)
    catch
        fail(location, "must be canonical YYYY-MM-DD")
    end
    string(date) == text || fail(location, "must be canonical YYYY-MM-DD")
    return date
end

function expect_timestamp_utc(value, location)
    text = expect_string(value, location)
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", text) ||
        fail(location, "must be canonical whole-second UTC")
    timestamp = try
        DateTime(chop(text; tail = 1))
    catch
        fail(location, "must be canonical whole-second UTC")
    end
    Dates.format(timestamp, dateformat"yyyy-mm-ddTHH:MM:SS") * "Z" == text ||
        fail(location, "must be canonical whole-second UTC")
    return timestamp
end

function expect_local_timestamp(value, location)
    text = expect_string(value, location)
    occursin(
        r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$",
        text,
    ) || fail(location, "must be a canonical offset timestamp")
    return text
end

function expect_array(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    return value
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

function _file_sha256(path, location)
    isfile(path) || fail(location, "missing file $path")
    islink(path) && fail(location, "refuses symbolic link $path")
    return bytes2hex(sha256(read(path)))
end

function _publication_dates()
    dates = Date[]
    cursor = Date(2026, 8, 10)
    final = Date(2026, 10, 30)
    while cursor <= final
        if dayofweek(cursor) <= 5 && !(cursor in EXCLUDED_DATES)
            push!(dates, cursor)
        end
        cursor += Day(1)
    end
    return dates
end

function _compact(date)
    return Dates.format(date, dateformat"yyyymmdd")
end

function _transaction_id(date, phase)
    return phase == FIRST_PHASE ?
        "effr-$(_compact(date))-first-1300z" :
        "effr-$(_compact(date))-revision-1830z"
end

function _state_class(phase)
    return phase == FIRST_PHASE ? FIRST_STATE : REVISION_STATE
end

function _bundle_path(date, phase)
    transaction = _transaction_id(date, phase)
    return joinpath(
        OUTPUT_ROOT,
        string(date),
        _state_class(phase),
        transaction,
    )
end

function _journal_path(date, phase)
    transaction = _transaction_id(date, phase)
    return joinpath(
        OUTPUT_ROOT,
        string(date),
        _state_class(phase),
        ".journal-$transaction",
    )
end

function _utc_timestamp(date, phase, deadline)
    clock = if phase == FIRST_PHASE
        deadline ? "13:15:00" : "13:00:00"
    else
        deadline ? "18:45:00" : "18:30:00"
    end
    return "$(date)T$(clock)Z"
end

function _new_york_timestamp(date, phase, deadline)
    clock = if phase == FIRST_PHASE
        deadline ? "09:15:00" : "09:00:00"
    else
        deadline ? "14:45:00" : "14:30:00"
    end
    return "$(date)T$(clock)-04:00"
end

function _madrid_timestamp(date, phase, deadline)
    standard = date >= MADRID_STANDARD_TIME_START
    clock = if phase == FIRST_PHASE
        if standard
            deadline ? "14:15:00" : "14:00:00"
        else
            deadline ? "15:15:00" : "15:00:00"
        end
    elseif standard
        deadline ? "19:45:00" : "19:30:00"
    else
        deadline ? "20:45:00" : "20:30:00"
    end
    offset = standard ? "+01:00" : "+02:00"
    return "$(date)T$(clock)$(offset)"
end

function _expected_slots()
    rows = Dict{String, Any}[]
    effective = Date(2026, 8, 7)
    sequence = 0
    dates = _publication_dates()
    for (day_sequence, publication) in enumerate(dates)
        phases = publication == last(dates) ? (FIRST_PHASE,) :
            (FIRST_PHASE, REVISION_PHASE)
        for phase in phases
            sequence += 1
            predecessor = phase == FIRST_PHASE ? "NOT_APPLICABLE" :
                _bundle_path(publication, FIRST_PHASE)
            effective_text = string(effective)
            push!(
                rows,
                Dict{String, Any}(
                    "sequence" => sequence,
                    "day_sequence" => day_sequence,
                    "publication_date" => string(publication),
                    "effective_date" => effective_text,
                    "phase" => phase,
                    "state_class" => _state_class(phase),
                    "scheduled_at_utc" =>
                        _utc_timestamp(publication, phase, false),
                    "deadline_at_utc" =>
                        _utc_timestamp(publication, phase, true),
                    "scheduled_at_new_york" =>
                        _new_york_timestamp(publication, phase, false),
                    "deadline_at_new_york" =>
                        _new_york_timestamp(publication, phase, true),
                    "scheduled_at_madrid" =>
                        _madrid_timestamp(publication, phase, false),
                    "deadline_at_madrid" =>
                        _madrid_timestamp(publication, phase, true),
                    "transaction_id" => _transaction_id(publication, phase),
                    "bundle_path" => _bundle_path(publication, phase),
                    "journal_path" => _journal_path(publication, phase),
                    "predecessor_bundle_path" => predecessor,
                    "rate_query" =>
                        "endDate=$effective_text&startDate=$effective_text&type=rate",
                    "volume_query" =>
                        "endDate=$effective_text&startDate=$effective_text&type=volume",
                ),
            )
        end
        effective = publication
    end
    return rows
end

function _validate_artifact(root)
    artifact = expect_exact_keys(
        root["artifact"],
        (
            "schema_version",
            "schedule_id",
            "status",
            "canonicalization",
            "digest_algorithm",
            "content_sha256",
            "local_contract_authored_at_utc",
            "authored_timestamp_status",
        ),
        "schedule.artifact",
    )
    expect_exact(
        expect_string(artifact["schema_version"], "schedule.artifact.schema_version"),
        SCHEMA_VERSION,
        "schedule.artifact.schema_version",
    )
    expect_exact(
        expect_string(artifact["schedule_id"], "schedule.artifact.schedule_id"),
        SCHEDULE_ID,
        "schedule.artifact.schedule_id",
    )
    expect_exact(
        expect_string(artifact["status"], "schedule.artifact.status"),
        "FROZEN_ADDITIVE_RESTART_CONTROL_ONLY_NONADMITTING",
        "schedule.artifact.status",
    )
    expect_exact(
        expect_string(artifact["canonicalization"], "schedule.artifact.canonicalization"),
        "sorted-typed-length-aware-excluding-artifact-content-sha256.v1",
        "schedule.artifact.canonicalization",
    )
    expect_exact(
        expect_string(artifact["digest_algorithm"], "schedule.artifact.digest_algorithm"),
        "sha256",
        "schedule.artifact.digest_algorithm",
    )
    digest = expect_hash(artifact["content_sha256"], "schedule.artifact.content_sha256")
    digest == computed_schedule_sha256(root) ||
        fail("schedule.artifact.content_sha256", "semantic self-hash mismatch")
    expect_exact(
        expect_string(
            artifact["local_contract_authored_at_utc"],
            "schedule.artifact.local_contract_authored_at_utc",
        ),
        "2026-08-07T21:30:00Z",
        "schedule.artifact.local_contract_authored_at_utc",
    )
    expect_timestamp_utc(
        artifact["local_contract_authored_at_utc"],
        "schedule.artifact.local_contract_authored_at_utc",
    )
    return expect_exact(
        expect_string(
            artifact["authored_timestamp_status"],
            "schedule.artifact.authored_timestamp_status",
        ),
        "LOCAL_UNAUTHENTICATED_DECLARATION_NOT_EXTERNAL_TIMESTAMP",
        "schedule.artifact.authored_timestamp_status",
    )
end

function _validate_amendment(root)
    amendment = expect_exact_keys(
        root["amendment"],
        (
            "amendment_id",
            "amendment_type",
            "trigger",
            "selection_basis",
            "frozen_before_first_restart_value_observation",
            "first_restart_value_observation_not_before_utc",
            "effr_numeric_values_used_to_select_restart",
            "revision_outcome_used_to_select_restart",
            "outcome_driven_selection",
            "retroactive_backfill_allowed",
            "predecessor_files_mutated",
            "predecessor_slots_relabelled",
            "additive_successor_only",
        ),
        "schedule.amendment",
    )
    expected = Dict{String, Any}(
        "amendment_id" => "effr-operational-missingness-restart-20260807.v2",
        "amendment_type" => "PRE_CAPTURE_OPERATIONAL_MISSINGNESS",
        "trigger" =>
            "AUGUST_7_REVISION_WINDOW_MISSED_NO_LATE_REQUEST_NO_RETRY",
        "selection_basis" =>
            "OPERATIONAL_WINDOW_MISS_AND_PREDECLARED_CALENDAR_ONLY",
        "frozen_before_first_restart_value_observation" => true,
        "first_restart_value_observation_not_before_utc" =>
            "2026-08-10T13:00:00Z",
        "effr_numeric_values_used_to_select_restart" => false,
        "revision_outcome_used_to_select_restart" => false,
        "outcome_driven_selection" => false,
        "retroactive_backfill_allowed" => false,
        "predecessor_files_mutated" => false,
        "predecessor_slots_relabelled" => false,
        "additive_successor_only" => true,
    )
    for (key, value) in expected
        expect_exact(amendment[key], value, "schedule.amendment.$key")
    end
    authored = expect_timestamp_utc(
        root["artifact"]["local_contract_authored_at_utc"],
        "schedule.artifact.local_contract_authored_at_utc",
    )
    first_observation = expect_timestamp_utc(
        amendment["first_restart_value_observation_not_before_utc"],
        "schedule.amendment.first_restart_value_observation_not_before_utc",
    )
    return authored < first_observation ||
        fail("schedule.amendment", "must be frozen before first restart observation")
end

function _validate_policy(root)
    policy = expect_exact_keys(
        root["policy"],
        (
            "source_id",
            "requirement_id",
            "campaign_id",
            "predecessor_schedule_id",
            "predecessor_campaign_id",
            "campaign_start_date",
            "first_campaign_end_date",
            "revision_campaign_end_date",
            "initial_effective_date",
            "excluded_dates",
            "calendar_rule",
            "effective_date_rule",
            "first_scheduled_time_utc",
            "first_deadline_time_utc",
            "revision_scheduled_time_utc",
            "revision_deadline_time_utc",
            "new_york_utc_offset",
            "madrid_summer_utc_offset",
            "madrid_standard_utc_offset",
            "madrid_standard_time_start_date",
            "capture_window_minutes",
            "capture_window_boundary",
            "origin_cutoff_utc",
            "output_root",
            "expected_first_state_count",
            "expected_revision_check_count",
            "expected_slot_count",
        ),
        "schedule.policy",
    )
    expected = Dict{String, Any}(
        "source_id" => "frbny_effr",
        "requirement_id" => "frbny_effr_tier1",
        "campaign_id" => CAMPAIGN_ID,
        "predecessor_schedule_id" => PREDECESSOR_SCHEDULE_ID,
        "predecessor_campaign_id" => PREDECESSOR_CAMPAIGN_ID,
        "campaign_start_date" => "2026-08-10",
        "first_campaign_end_date" => "2026-10-30",
        "revision_campaign_end_date" => "2026-10-29",
        "initial_effective_date" => "2026-08-07",
        "excluded_dates" => ["2026-09-07", "2026-10-12"],
        "calendar_rule" =>
            "WEEKDAYS_EXCLUDING_EXACT_FROZEN_NYFED_HOLIDAYS",
        "effective_date_rule" =>
            "PREVIOUS_AUTHORIZED_PUBLICATION_DAY_WITH_20260807_SEED",
        "first_scheduled_time_utc" => "13:00:00Z",
        "first_deadline_time_utc" => "13:15:00Z",
        "revision_scheduled_time_utc" => "18:30:00Z",
        "revision_deadline_time_utc" => "18:45:00Z",
        "new_york_utc_offset" => "-04:00",
        "madrid_summer_utc_offset" => "+02:00",
        "madrid_standard_utc_offset" => "+01:00",
        "madrid_standard_time_start_date" => "2026-10-26",
        "capture_window_minutes" => 15,
        "capture_window_boundary" => "CLOSED_START_AND_DEADLINE",
        "origin_cutoff_utc" => "2026-10-30T14:00:00Z",
        "output_root" => OUTPUT_ROOT,
        "expected_first_state_count" => 58,
        "expected_revision_check_count" => 57,
        "expected_slot_count" => 115,
    )
    for (key, value) in expected
        expect_exact(policy[key], value, "schedule.policy.$key")
    end
    for key in (
            "campaign_start_date",
            "first_campaign_end_date",
            "revision_campaign_end_date",
            "initial_effective_date",
            "madrid_standard_time_start_date",
        )
        expect_date(policy[key], "schedule.policy.$key")
    end
    expect_timestamp_utc(policy["origin_cutoff_utc"], "schedule.policy.origin_cutoff_utc")
    return policy
end

function _validate_claims(root)
    claims = expect_exact_keys(
        root["claim_ceiling"],
        (
            "positive_claim",
            "unchanged_revision_status",
            "proves_first_publication",
            "proves_historical_first_byte",
            "proves_no_later_same_day_revision",
            "proves_final_daily_state",
            "proves_transport_provenance",
            "proves_origin_admissibility",
        ),
        "schedule.claim_ceiling",
    )
    expect_exact(
        claims["positive_claim"],
        "MARKETS_API_ENDPOINT_STATE_OBSERVED_AS_OF_CAPTURE_TIME_ONLY",
        "schedule.claim_ceiling.positive_claim",
    )
    expect_exact(
        claims["unchanged_revision_status"],
        "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE",
        "schedule.claim_ceiling.unchanged_revision_status",
    )
    for key in (
            "proves_first_publication",
            "proves_historical_first_byte",
            "proves_no_later_same_day_revision",
            "proves_final_daily_state",
            "proves_transport_provenance",
            "proves_origin_admissibility",
        )
        expect_exact(claims[key], false, "schedule.claim_ceiling.$key")
    end
    return
end

function _validate_source_bindings(root, overrides)
    expected_keys = String[]
    for spec in BINDING_SPECS
        push!(expected_keys, "$(spec.id)_path", "$(spec.id)_sha256")
    end
    source = expect_exact_keys(
        root["source_bindings"],
        Tuple(expected_keys),
        "schedule.source_bindings",
    )
    for spec in BINDING_SPECS
        path_key = "$(spec.id)_path"
        hash_key = "$(spec.id)_sha256"
        expect_exact(source[path_key], spec.relative_path, "schedule.source_bindings.$path_key")
        expected_hash = expect_hash(source[hash_key], "schedule.source_bindings.$hash_key")
        expect_exact(expected_hash, spec.sha256, "schedule.source_bindings.$hash_key")
        path = haskey(overrides, spec.id) ? String(overrides[spec.id]) :
            joinpath(SOURCE_ROOT, spec.relative_path)
        actual_hash = _file_sha256(path, "source binding $(spec.id)")
        actual_hash == expected_hash ||
            fail("source binding $(spec.id)", "exact file SHA-256 changed")
    end
    return
end

function _validate_predecessor(root)
    predecessor = expect_exact_keys(
        root["predecessor_history"],
        (
            "schedule_id",
            "campaign_id",
            "schedule_semantic_sha256",
            "governance_status",
            "planned_slot_count",
            "captured_august7_first_state_slot_count",
            "captured_august7_first_state_status",
            "missed_august7_revision_check_slot_count",
            "missed_august7_revision_check_status",
            "future_uncaptured_v1_slot_count",
            "theoretical_v1_total_maximum_after_miss_numerator",
            "theoretical_v1_total_maximum_after_miss_denominator",
            "theoretical_v1_total_maximum_status",
            "theoretical_v1_maximum_contributes_to_restart_completion",
            "coverage_accounting_status",
            "complete",
            "withdrawn_for_future_capture",
            "eligible_for_restart_coverage",
            "eligible_for_relabeling",
            "eligible_for_mutation",
            "may_be_combined_to_claim_restart_completion",
        ),
        "schedule.predecessor_history",
    )
    expected = Dict{String, Any}(
        "schedule_id" => PREDECESSOR_SCHEDULE_ID,
        "campaign_id" => PREDECESSOR_CAMPAIGN_ID,
        "schedule_semantic_sha256" =>
            "fb984becfc5608922cd4acffd7e3e3bdf997022935f816acad221ec32dcd0383",
        "governance_status" =>
            "WITHDRAWN_INCOMPLETE_PREDECESSOR_HISTORY_PRESERVED",
        "planned_slot_count" => 117,
        "captured_august7_first_state_slot_count" => 1,
        "captured_august7_first_state_status" =>
            "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE",
        "missed_august7_revision_check_slot_count" => 1,
        "missed_august7_revision_check_status" =>
            "OPERATIONAL_MISSINGNESS_WINDOW_MISSED_NO_LATE_REQUEST",
        "future_uncaptured_v1_slot_count" => 115,
        "theoretical_v1_total_maximum_after_miss_numerator" => 116,
        "theoretical_v1_total_maximum_after_miss_denominator" => 117,
        "theoretical_v1_total_maximum_status" =>
            "V1_ONLY_NONCOMBINABLE_CEILING_NOT_OBSERVED_COVERAGE",
        "theoretical_v1_maximum_contributes_to_restart_completion" => false,
        "coverage_accounting_status" =>
            "NOT_IMPORTED_INTO_RESTART_DENOMINATOR",
        "complete" => false,
        "withdrawn_for_future_capture" => true,
        "eligible_for_restart_coverage" => false,
        "eligible_for_relabeling" => false,
        "eligible_for_mutation" => false,
        "may_be_combined_to_claim_restart_completion" => false,
    )
    for (key, value) in expected
        expect_exact(predecessor[key], value, "schedule.predecessor_history.$key")
    end
    return expect_hash(
        predecessor["schedule_semantic_sha256"],
        "schedule.predecessor_history.schedule_semantic_sha256",
    )
end

function _validate_observed_state_acceptance(root)
    acceptance = expect_exact_keys(
        root["observed_state_acceptance"],
        (
            "contract_version",
            "independent_acceptance_required",
            "independent_acceptance_completed",
            "accepted_role",
            "root_test_count",
            "unrelated_tmp_test_count",
            "module_sha256",
            "protocol_file_sha256",
            "tests_sha256",
            "readme_sha256",
            "protocol_semantic_sha256",
            "unblocks_provenance",
            "unblocks_origin_admission",
            "unblocks_scoring",
            "unblocks_promotion",
            "unblocks_production",
        ),
        "schedule.observed_state_acceptance",
    )
    expected = Dict{String, Any}(
        "contract_version" => "beforeit-us-effr-observed-state-contract.v3",
        "independent_acceptance_required" => true,
        "independent_acceptance_completed" => true,
        "accepted_role" => "NARROW_OFFLINE_PERMANENTLY_NONADMITTING",
        "root_test_count" => 253,
        "unrelated_tmp_test_count" => 253,
        "module_sha256" =>
            "3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6",
        "protocol_file_sha256" =>
            "d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716",
        "tests_sha256" =>
            "55bfbf5a4b252804f4e3b2e91100c83b8ff98bffbf10eec5bdd3bd83d96ad66c",
        "readme_sha256" =>
            "4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23",
        "protocol_semantic_sha256" =>
            "33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c",
        "unblocks_provenance" => false,
        "unblocks_origin_admission" => false,
        "unblocks_scoring" => false,
        "unblocks_promotion" => false,
        "unblocks_production" => false,
    )
    for (key, value) in expected
        expect_exact(acceptance[key], value, "schedule.observed_state_acceptance.$key")
    end
    for key in (
            "module_sha256",
            "protocol_file_sha256",
            "tests_sha256",
            "readme_sha256",
            "protocol_semantic_sha256",
        )
        expect_hash(acceptance[key], "schedule.observed_state_acceptance.$key")
    end
    return
end

function _validate_operational_control(root)
    operational = expect_exact_keys(
        root["operational_control"],
        (
            "retry_policy",
            "duplicate_policy",
            "late_capture_policy",
            "one_slot_one_transaction",
            "retroactive_fill_forbidden",
            "runner_source_role",
            "runner_restart_binding_complete",
            "automation_created_by_contract",
            "network_client_present_in_contract",
            "raw_writer_present_in_contract",
            "source_inventory_writer_present_in_contract",
        ),
        "schedule.operational_control",
    )
    expected = Dict{String, Any}(
        "retry_policy" => "NO_AUTOMATIC_RETRY",
        "duplicate_policy" =>
            "FINAL_BUNDLE_OR_PRIVATE_JOURNAL_EXISTS_ISSUE_NO_REQUEST",
        "late_capture_policy" =>
            "OUTSIDE_WINDOW_ISSUE_NO_REQUEST_RECORD_OPERATIONAL_MISSINGNESS",
        "one_slot_one_transaction" => true,
        "retroactive_fill_forbidden" => true,
        "runner_source_role" =>
            "ACCEPTED_V3_SOURCE_BASE_REQUIRES_SEPARATE_RESTART_BINDING",
        "runner_restart_binding_complete" => false,
        "automation_created_by_contract" => false,
        "network_client_present_in_contract" => false,
        "raw_writer_present_in_contract" => false,
        "source_inventory_writer_present_in_contract" => false,
    )
    for (key, value) in expected
        expect_exact(operational[key], value, "schedule.operational_control.$key")
    end
    return
end

function _validate_coverage(root)
    coverage = expect_exact_keys(
        root["coverage"],
        (
            "restart_first_state_denominator",
            "restart_revision_check_denominator",
            "restart_slot_denominator",
            "restart_complete_pair_denominator",
            "maximum_restart_slot_coverage_numerator",
            "maximum_restart_slot_coverage_denominator",
            "restart_coverage_status",
            "restart_denominator_independent_of_v1",
            "v1_slots_contribute_to_restart_completion",
            "restart_slots_contribute_to_v1_completion",
            "august7_first_state_included",
            "august7_revision_check_included",
            "october30_revision_check_included",
            "all_115_required_for_restart_completion",
            "full_117_claim_allowed",
            "cross_campaign_receipt_combination_allowed",
            "maximum_origin_admissible_slot_count",
        ),
        "schedule.coverage",
    )
    expected = Dict{String, Any}(
        "restart_first_state_denominator" => 58,
        "restart_revision_check_denominator" => 57,
        "restart_slot_denominator" => 115,
        "restart_complete_pair_denominator" => 57,
        "maximum_restart_slot_coverage_numerator" => 115,
        "maximum_restart_slot_coverage_denominator" => 115,
        "restart_coverage_status" =>
            "RESTART_ONLY_DENOMINATOR_NO_V1_CONTRIBUTIONS",
        "restart_denominator_independent_of_v1" => true,
        "v1_slots_contribute_to_restart_completion" => false,
        "restart_slots_contribute_to_v1_completion" => false,
        "august7_first_state_included" => false,
        "august7_revision_check_included" => false,
        "october30_revision_check_included" => false,
        "all_115_required_for_restart_completion" => true,
        "full_117_claim_allowed" => false,
        "cross_campaign_receipt_combination_allowed" => false,
        "maximum_origin_admissible_slot_count" => 0,
    )
    for (key, value) in expected
        expect_exact(coverage[key], value, "schedule.coverage.$key")
    end
    return
end

function _validate_gates(root)
    gates = expect_exact_keys(root["gates"], FALSE_GATE_KEYS, "schedule.gates")
    for key in FALSE_GATE_KEYS
        expect_exact(gates[key], false, "schedule.gates.$key")
    end
    return
end

function _validate_slots(root)
    slots = expect_array(root["slots"], "schedule.slots")
    expected = _expected_slots()
    length(slots) == length(expected) ||
        fail("schedule.slots", "must contain exactly 115 slots")
    slot_keys = Tuple(keys(first(expected)))
    seen_transactions = Set{String}()
    seen_bundles = Set{String}()
    seen_journals = Set{String}()
    for (index, expected_row) in enumerate(expected)
        row = expect_exact_keys(slots[index], slot_keys, "schedule.slots[$index]")
        for (key, value) in expected_row
            expect_exact(row[key], value, "schedule.slots[$index].$key")
        end
        expect_int(row["sequence"], "schedule.slots[$index].sequence"; minimum = 1)
        expect_int(row["day_sequence"], "schedule.slots[$index].day_sequence"; minimum = 1)
        publication = expect_date(
            row["publication_date"],
            "schedule.slots[$index].publication_date",
        )
        expect_date(row["effective_date"], "schedule.slots[$index].effective_date")
        start = expect_timestamp_utc(
            row["scheduled_at_utc"],
            "schedule.slots[$index].scheduled_at_utc",
        )
        deadline = expect_timestamp_utc(
            row["deadline_at_utc"],
            "schedule.slots[$index].deadline_at_utc",
        )
        deadline - start == Minute(15) ||
            fail("schedule.slots[$index]", "window must be exactly 15 minutes")
        Date(start) == publication && Date(deadline) == publication ||
            fail("schedule.slots[$index]", "UTC window must be on publication date")
        expect_local_timestamp(
            row["scheduled_at_new_york"],
            "schedule.slots[$index].scheduled_at_new_york",
        )
        expect_local_timestamp(
            row["deadline_at_new_york"],
            "schedule.slots[$index].deadline_at_new_york",
        )
        expect_local_timestamp(
            row["scheduled_at_madrid"],
            "schedule.slots[$index].scheduled_at_madrid",
        )
        expect_local_timestamp(
            row["deadline_at_madrid"],
            "schedule.slots[$index].deadline_at_madrid",
        )
        transaction = expect_string(
            row["transaction_id"],
            "schedule.slots[$index].transaction_id",
        )
        bundle = expect_string(row["bundle_path"], "schedule.slots[$index].bundle_path")
        journal = expect_string(row["journal_path"], "schedule.slots[$index].journal_path")
        transaction in seen_transactions &&
            fail("schedule.slots[$index]", "duplicate transaction_id")
        bundle in seen_bundles && fail("schedule.slots[$index]", "duplicate bundle_path")
        journal in seen_journals && fail("schedule.slots[$index]", "duplicate journal_path")
        push!(seen_transactions, transaction)
        push!(seen_bundles, bundle)
        push!(seen_journals, journal)
    end
    final_first_deadline = expect_timestamp_utc(
        last(slots)["deadline_at_utc"],
        "schedule.slots[end].deadline_at_utc",
    )
    origin_cutoff = expect_timestamp_utc(
        root["policy"]["origin_cutoff_utc"],
        "schedule.policy.origin_cutoff_utc",
    )
    final_first_deadline < origin_cutoff ||
        fail("schedule.slots[end]", "terminal first-state window must precede origin cutoff")
    return slots
end

function validate_restart_schedule(
        schedule;
        binding_path_overrides::AbstractDict = Dict{String, String}(),
    )
    root = expect_exact_keys(
        schedule,
        (
            "artifact",
            "amendment",
            "policy",
            "claim_ceiling",
            "source_bindings",
            "predecessor_history",
            "observed_state_acceptance",
            "operational_control",
            "coverage",
            "gates",
            "slots",
        ),
        "schedule",
    )
    _validate_artifact(root)
    _validate_amendment(root)
    _validate_policy(root)
    _validate_claims(root)
    _validate_source_bindings(root, binding_path_overrides)
    _validate_predecessor(root)
    _validate_observed_state_acceptance(root)
    _validate_operational_control(root)
    _validate_coverage(root)
    _validate_gates(root)
    slots = _validate_slots(root)
    return (
        schedule_id = SCHEDULE_ID,
        campaign_id = CAMPAIGN_ID,
        content_sha256 = root["artifact"]["content_sha256"],
        first_state_count = 58,
        revision_check_count = 57,
        slot_count = length(slots),
        complete_pair_count = 57,
        endpoint_only_claim_ceiling = true,
        predecessor_withdrawn_incomplete = true,
        observed_state_offline_acceptance_complete = true,
        runner_restart_binding_complete = false,
        network_execution_authorized = false,
        raw_data_write_authorized = false,
        origin_admissible = false,
        production_scoring_allowed = false,
        promotion_eligible = false,
        ready = false,
    )
end

function load_restart_schedule(
        path::AbstractString = DEFAULT_SCHEDULE_PATH;
        binding_path_overrides::AbstractDict = Dict{String, String}(),
    )
    isfile(path) || fail("schedule", "missing file $path")
    islink(path) && fail("schedule", "refuses symbolic link $path")
    schedule = try
        TOML.parsefile(path)
    catch error
        fail("schedule", "TOML parse failed: $(sprint(showerror, error))")
    end
    validate_restart_schedule(schedule; binding_path_overrides)
    return schedule
end

function _phase(value)
    value isa AbstractString || fail("phase", "must be a string")
    phase = String(value)
    phase in (FIRST_PHASE, REVISION_PHASE) ||
        fail("phase", "must be first or revision-check")
    return phase
end

function planned_slot(schedule, publication_date, phase)
    validate_restart_schedule(schedule)
    date = publication_date isa Date ? publication_date :
        expect_date(publication_date, "publication_date")
    selected_phase = _phase(phase)
    matches = [
        row for row in schedule["slots"] if
            row["publication_date"] == string(date) &&
            row["phase"] == selected_phase
    ]
    length(matches) == 1 ||
        fail("slot", "date/phase is not present exactly once")
    row = only(matches)
    return RestartSlot(
        SCHEDULE_ID,
        row["sequence"],
        row["day_sequence"],
        Date(row["publication_date"]),
        Date(row["effective_date"]),
        row["phase"],
        row["state_class"],
        DateTime(chop(row["scheduled_at_utc"]; tail = 1)),
        DateTime(chop(row["deadline_at_utc"]; tail = 1)),
        row["scheduled_at_new_york"],
        row["deadline_at_new_york"],
        row["scheduled_at_madrid"],
        row["deadline_at_madrid"],
        row["transaction_id"],
        row["bundle_path"],
        row["journal_path"],
        row["predecessor_bundle_path"],
        row["rate_query"],
        row["volume_query"],
        false,
        false,
        false,
    )
end

end
