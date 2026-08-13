module USEFFRRecurringAcquisitionRestartV4

using Dates
using Downloads
using JSON
using SHA
using TOML

include(
    joinpath(
        @__DIR__,
        "..",
        "campaign_restart_v2",
        "USEFFRCampaignRestartV2.jl",
    ),
)
using .USEFFRCampaignRestartV2

include(
    joinpath(
        @__DIR__,
        "..",
        "capture_contract",
        "USEFFRCaptureContract.jl",
    ),
)
using .USEFFRCaptureContract

include(
    joinpath(
        @__DIR__,
        "..",
        "observed_state_contract",
        "USEFFRObservedStateContractV3.jl",
    ),
)
using .USEFFRObservedStateContractV3

export CapturedResponse,
    RestartDecisionBinding,
    RestartRecurringAcquisitionError,
    acquire_restart_recurring,
    canonical_transaction_id,
    dry_run_plan,
    evaluate_restart_result,
    load_and_validate_bundle,
    request_plan

const RestartControl = USEFFRCampaignRestartV2
const ReceiptContract = USEFFRCaptureContract
const ObservedStateContract = USEFFRObservedStateContractV3
const RestartDecisionBinding = ObservedStateContract.DecisionBinding
const SCHEMA_VERSION =
    "beforeit-us-effr-recurring-acquisition-restart.v4"
const STORAGE_SCHEMA =
    "beforeit-us-effr-recurring-restart-local-storage-integrity.v4"
const JOURNAL_SCHEMA =
    "beforeit-us-effr-recurring-restart-private-preflight-journal.v4"
const ATTEMPT_SCHEMA =
    "beforeit-us-effr-recurring-restart-request-attempt-event.v4"
const OPERATOR_AUTHORIZATION_SCHEMA =
    "beforeit-us-effr-recurring-restart-operator-execution-authorization.v4"
const MANIFEST_CANONICALIZATION =
    "sorted_toml_excluding_artifact_manifest_sha256.v1"
const STORAGE_CANONICALIZATION =
    "sorted_toml_excluding_artifact_receipt_sha256.v1"
const RESTART_CONTROL_FILE_SHA256 =
    "5e0873ec7c427c377386bf9bd33c782f39a4735391011cffc7e24a1c67aa7155"
const RESTART_SCHEDULE_FILE_SHA256 =
    "670e5b02b740e9195b768d22e002ee3de49f037efb5f0b1228f0c9482e3e0136"
const RESTART_SCHEDULE_CONTENT_SHA256 =
    "cae7f463b752ff2c60c78751ca0186712a53fb1732c7970e8bb0e4368d9e477b"
const RECURRING_V3_MODULE_FILE_SHA256 =
    "3685e0c0ca3d440bdf2816d3c3bc229656d4a2339d6009b34f2c754c4a7051de"
const RECURRING_V3_CLI_FILE_SHA256 =
    "e2f293dd77da818c5fd0ee64e8bb520a162f62e805c17fdc6cf6131f6db3800f"
const RECURRING_V3_TEST_FILE_SHA256 =
    "256eac940dace2e749efb98be33e9ba059f21883da5b6d0bf92fdac2beb7e41b"
const RECURRING_V3_README_FILE_SHA256 =
    "052d02b3117037d86830de50783f43f782907ae84824fa7507acd36b70784d02"
const RECEIPT_CONTRACT_FILE_SHA256 =
    "6c4ee3ff95b92daf34899db64dbff7fc920eb33e5bc4bf17a6adf99bf3b3f651"
const OBSERVED_STATE_CONTRACT_FILE_SHA256 =
    "3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6"
const OBSERVED_STATE_PROTOCOL_FILE_SHA256 =
    "d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716"
const OBSERVED_STATE_PROTOCOL_CONTENT_SHA256 =
    "33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c"
const OBSERVED_STATE_TEST_FILE_SHA256 =
    "55bfbf5a4b252804f4e3b2e91100c83b8ff98bffbf10eec5bdd3bd83d96ad66c"
const OBSERVED_STATE_README_FILE_SHA256 =
    "4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23"
const PROSPECTIVE_CONTRACT_ID =
    "beforeit-us-prospective-2026q3-acquisition.v2"
const PROSPECTIVE_CONTRACT_CONTENT_SHA256 =
    "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
const PROSPECTIVE_CONTRACT_FILE_SHA256 =
    "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
const RESTART_SCHEDULE_ID =
    "beforeit-us-effr-2026q3-prospective-restart-20260810.v2"
const RESTART_OUTPUT_ROOT_RELATIVE =
    "data/us/raw/forecasting/effr/prospective/2026q3_restart_v2"
const REPOSITORY_ROOT = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."),
)
const RESTART_OUTPUT_ROOT =
    joinpath(REPOSITORY_ROOT, RESTART_OUTPUT_ROOT_RELATIVE)
const UNCHANGED_ENDPOINT_CLAIM =
    "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
const RAW_UNCHANGED_PRESERVATION_STATUS =
    "RAW_BYTE_IDENTICAL_EMPTY_REVISION_TOKEN_NONADMITTING_CAPTURE_PRESERVED"
const POSITIVE_ENDPOINT_CLAIM =
    "MARKETS_API_ENDPOINT_STATE_OBSERVED_AS_OF_CAPTURE_TIME_ONLY"
const DATA_ENDPOINT =
    "https://markets.newyorkfed.org/api/rates/all/search.json"
const API_DOCUMENTATION_URL =
    "https://markets.newyorkfed.org/static/docs/markets-api.html"
const OPENAPI_URL =
    "https://markets.newyorkfed.org/static/docs/markets-api.yml"
const TERMS_URL = "https://www.newyorkfed.org/privacy/termsofuse"
const HOLIDAY_URL =
    "https://www.newyorkfed.org/aboutthefed/holiday_schedule"
const FINAL_HOST = "markets.newyorkfed.org"
const LIVE_TIMEOUT_SECONDS = 20
const USER_AGENT =
    "BeforeIT-US-EFFR-Recurring-Restart-Capture/4.0 (+https://github.com/MarketsReplica/US_BeforeIT.jl)"
const BUILTIN_TRANSPORT_POLICY =
    "DIRECT_TLS_NO_REDIRECT_NO_NETRC_NO_COOKIES_NO_AMBIENT_PROXY"
const SYNTHETIC_TRANSPORT_POLICY =
    "INJECTED_SYNTHETIC_TEST_CALLBACK_TRANSPORT_UNOBSERVABLE"
const BUILTIN_TRANSPORT_PROVENANCE =
    "BUILTIN_DOWNLOADS_TRANSPORT_AND_HOST_UTC_CLOCK"
const SYNTHETIC_TRANSPORT_PROVENANCE =
    "INJECTED_SYNTHETIC_TEST_TRANSPORT_AND_CLOCK"
const CAMPAIGN_ID =
    "frbny_effr_daily_first_state_and_revision_check_restart_20260810"
const SYNTHETIC_CAMPAIGN_ID =
    "SYNTHETIC_TEST_FIXTURE_NOT_CAMPAIGN_ELIGIBLE"
const SYNTHETIC_BLOCKER =
    "SYNTHETIC_TEST_FIXTURE_NOT_EMPIRICAL_EVIDENCE"
const PERSISTED_TRANSPORT_BLOCKER =
    "PERSISTED_TRANSPORT_PROVENANCE_NOT_EXTERNALLY_AUTHENTICATED"
const NETWORK_EXCHANGE_COUNT_BLOCKER =
    "NETWORK_EXCHANGE_COUNT_NOT_INDEPENDENTLY_WITNESSED"
const OPERATOR_AUTHENTICATION_BLOCKER =
    "OPERATOR_AUTHORIZATION_LOCALLY_SELF_REPORTED_NOT_EXTERNALLY_AUTHENTICATED"
const CURRENT_STATE_BLOCKER =
    "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const HEADER_NAME_PATTERN = r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$"
const ALWAYS_FALSE_GATES = Dict{String, Any}(
    "accuracy_evaluation_allowed" => false,
    "empirical_forecast_allowed" => false,
    "historical_first_byte_proven" => false,
    "origin_admissible" => false,
    "production_scoring_allowed" => false,
    "promotion_eligible" => false,
    "persisted_transport_provenance_authenticated" => false,
    "network_exchange_count_externally_witnessed" => false,
    "operator_authorization_externally_authenticated" => false,
    "readiness" => false,
    "source_inventory_mutation_allowed" => false,
)
const BASE_BLOCKERS = [
    "CAPTURE_CLOCK_HOST_OBSERVATION_ONLY",
    "CAPTURE_SOURCE_REVISION_NOT_EXTERNALLY_ATTESTED",
    "DURABLE_TWO_COPY_STORAGE_NOT_ESTABLISHED",
    "EXTERNAL_TIMESTAMP_NOT_ESTABLISHED",
    "LOCAL_RECEIPT_PIN_NOT_OUT_OF_BAND_AUTHENTICATION",
    "ORIGIN_ADMISSION_FORBIDDEN",
    "PRODUCTION_USE_FORBIDDEN",
    "PROMOTION_FORBIDDEN",
    "PROSPECTIVE_CONTRACT_DRAFT_UNAPPROVED",
    "READINESS_FALSE",
    "RETENTION_THROUGH_2031_NOT_EXTERNALLY_ATTESTED",
    "SOURCE_TRANSPORT_NOT_INDEPENDENTLY_ATTESTED",
    PERSISTED_TRANSPORT_BLOCKER,
    NETWORK_EXCHANGE_COUNT_BLOCKER,
    OPERATOR_AUTHENTICATION_BLOCKER,
]
const RESTART_CONTROL_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "campaign_restart_v2",
        "USEFFRCampaignRestartV2.jl",
    ),
)
const RESTART_SCHEDULE_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "campaign_restart_v2",
        "effr_2026q3_restart_schedule_v2.toml",
    ),
)
const RECURRING_V3_ROOT =
    normpath(joinpath(@__DIR__, "..", "recurring_acquisition"))
const RECURRING_V3_MODULE_PATH =
    joinpath(RECURRING_V3_ROOT, "USEFFRRecurringAcquisition.jl")
const RECURRING_V3_CLI_PATH =
    joinpath(RECURRING_V3_ROOT, "capture_effr_recurring.jl")
const RECURRING_V3_TEST_PATH =
    joinpath(RECURRING_V3_ROOT, "test_effr_recurring_acquisition.jl")
const RECURRING_V3_README_PATH = joinpath(RECURRING_V3_ROOT, "README.md")
const RECEIPT_CONTRACT_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "capture_contract",
        "USEFFRCaptureContract.jl",
    ),
)
const OBSERVED_STATE_ROOT =
    normpath(joinpath(@__DIR__, "..", "observed_state_contract"))
const OBSERVED_STATE_CONTRACT_PATH = joinpath(
    OBSERVED_STATE_ROOT,
    "USEFFRObservedStateContractV3.jl",
)
const OBSERVED_STATE_PROTOCOL_PATH =
    joinpath(OBSERVED_STATE_ROOT, "observed_state_contract_v3.toml")
const OBSERVED_STATE_TEST_PATH = joinpath(
    OBSERVED_STATE_ROOT,
    "test_effr_observed_state_contract_v3.jl",
)
const OBSERVED_STATE_README_PATH = joinpath(OBSERVED_STATE_ROOT, "README.md")
const CLI_PATH = joinpath(@__DIR__, "capture_effr_recurring_restart_v4.jl")

struct RestartRecurringAcquisitionError <: Exception
    message::String
end

Base.showerror(io::IO, error::RestartRecurringAcquisitionError) =
    print(io, error.message)

fail(location, message) =
    throw(RestartRecurringAcquisitionError("$location: $message"))

Base.@kwdef struct CapturedResponse
    object_id::String
    body::Vector{UInt8}
    requested_url::String
    final_url::String
    http_status::Int
    content_type::String
    content_encoding::String
    redirect_count::Int
    proxy_used::Bool
    response_headers::Vector{String}
    request_started_at_utc::DateTime
    response_body_completed_at_utc::DateTime
    response_metadata_observed_at_utc::DateTime
end

function _operator_authorization(
        authorization,
        execute_live;
        synthetic_fixture = false,
    )
    synthetic_fixture && !execute_live &&
        fail("operator authorization", "dry run cannot be synthetic")
    authorization_source = if !execute_live
        "NOT_GRANTED_DRY_RUN"
    elseif synthetic_fixture
        "EXPLICIT_SYNTHETIC_TEST_FIXTURE_ARGUMENT"
    else
        "EXPLICIT_EXECUTE_LIVE_ARGUMENT_BUILTIN_TRANSPORT"
    end
    return Dict{String, Any}(
        "schema_version" => OPERATOR_AUTHORIZATION_SCHEMA,
        "authorization_source" => authorization_source,
        "operator_network_execution_authorized" =>
            execute_live && !synthetic_fixture,
        "operator_raw_bundle_write_authorized" => execute_live,
        "restart_schedule_network_execution_authorized" =>
            authorization.network_execution_authorized,
        "restart_schedule_raw_data_write_authorized" =>
            authorization.raw_data_write_authorized,
        "separate_from_restart_schedule_governance_gates" => true,
        "bounded_to_one_restart_slot" => true,
        "network_exchange_count_ceiling" =>
            "NOT_INDEPENDENTLY_WITNESSED",
        "downloader_invocation_ceiling" => 6,
        "synthetic_test_fixture" => synthetic_fixture,
        "built_in_transport_required" =>
            execute_live && !synthetic_fixture,
        "persisted_transport_provenance_authenticated" => false,
        "network_exchange_count_externally_witnessed" => false,
        "operator_authorization_externally_authenticated" => false,
        "operator_identity_externally_authenticated" => false,
        "authorization_persistence_status" =>
            "LOCALLY_SELF_REPORTED_NOT_EXTERNALLY_AUTHENTICATED",
        "http_method" => "GET",
        "does_not_authorize_inventory_mutation" => true,
        "does_not_authorize_origin_admission" => true,
        "does_not_authorize_scoring_or_promotion" => true,
    )
end

sha256_hex(bytes) = bytes2hex(sha256(bytes))

const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
timestamp(value::DateTime) = Dates.format(value, TIMESTAMP_FORMAT) * "Z"

function file_sha256(path, location)
    isfile(path) || fail(location, "missing file $path")
    islink(path) && fail(location, "refuses symbolic link $path")
    return sha256_hex(read(path))
end

function _source_bindings()
    file_sha256(RESTART_CONTROL_PATH, "source binding") ==
        RESTART_CONTROL_FILE_SHA256 ||
        fail("source binding", "restart-control source changed")
    file_sha256(RESTART_SCHEDULE_PATH, "source binding") ==
        RESTART_SCHEDULE_FILE_SHA256 ||
        fail("source binding", "restart schedule changed")
    for (path, expected, label) in (
            (
                RECURRING_V3_MODULE_PATH,
                RECURRING_V3_MODULE_FILE_SHA256,
                "recurring-v3 module",
            ),
            (
                RECURRING_V3_CLI_PATH,
                RECURRING_V3_CLI_FILE_SHA256,
                "recurring-v3 CLI",
            ),
            (
                RECURRING_V3_TEST_PATH,
                RECURRING_V3_TEST_FILE_SHA256,
                "recurring-v3 tests",
            ),
            (
                RECURRING_V3_README_PATH,
                RECURRING_V3_README_FILE_SHA256,
                "recurring-v3 README",
            ),
        )
        file_sha256(path, "source binding") == expected ||
            fail("source binding", "$label source changed")
    end
    file_sha256(RECEIPT_CONTRACT_PATH, "source binding") ==
        RECEIPT_CONTRACT_FILE_SHA256 ||
        fail("source binding", "receipt contract changed")
    for (path, expected, label) in (
            (
                OBSERVED_STATE_CONTRACT_PATH,
                OBSERVED_STATE_CONTRACT_FILE_SHA256,
                "observed-state-v3 contract",
            ),
            (
                OBSERVED_STATE_PROTOCOL_PATH,
                OBSERVED_STATE_PROTOCOL_FILE_SHA256,
                "observed-state-v3 protocol",
            ),
            (
                OBSERVED_STATE_TEST_PATH,
                OBSERVED_STATE_TEST_FILE_SHA256,
                "observed-state-v3 tests",
            ),
            (
                OBSERVED_STATE_README_PATH,
                OBSERVED_STATE_README_FILE_SHA256,
                "observed-state-v3 README",
            ),
        )
        file_sha256(path, "source binding") == expected ||
            fail("source binding", "$label source changed")
    end
    schedule = RestartControl.load_restart_schedule(RESTART_SCHEDULE_PATH)
    schedule["artifact"]["content_sha256"] ==
        RESTART_SCHEDULE_CONTENT_SHA256 ||
        fail("source binding", "restart schedule semantic hash changed")
    return (
        schedule,
        restart_control_file_sha256 = RESTART_CONTROL_FILE_SHA256,
        restart_schedule_file_sha256 = RESTART_SCHEDULE_FILE_SHA256,
        restart_schedule_content_sha256 =
            RESTART_SCHEDULE_CONTENT_SHA256,
        recurring_v3_module_file_sha256 =
            RECURRING_V3_MODULE_FILE_SHA256,
        recurring_v3_cli_file_sha256 = RECURRING_V3_CLI_FILE_SHA256,
        recurring_v3_test_file_sha256 = RECURRING_V3_TEST_FILE_SHA256,
        recurring_v3_readme_file_sha256 =
            RECURRING_V3_README_FILE_SHA256,
        receipt_contract_file_sha256 = RECEIPT_CONTRACT_FILE_SHA256,
        observed_state_contract_file_sha256 =
            OBSERVED_STATE_CONTRACT_FILE_SHA256,
        observed_state_protocol_file_sha256 =
            OBSERVED_STATE_PROTOCOL_FILE_SHA256,
        observed_state_protocol_content_sha256 =
            OBSERVED_STATE_PROTOCOL_CONTENT_SHA256,
        observed_state_test_file_sha256 = OBSERVED_STATE_TEST_FILE_SHA256,
        observed_state_readme_file_sha256 =
            OBSERVED_STATE_README_FILE_SHA256,
        acquisition_source_sha256 =
            file_sha256(@__FILE__, "source binding"),
        acquisition_cli_sha256 =
            isfile(CLI_PATH) ? file_sha256(CLI_PATH, "source binding") : "NONE",
    )
end

function _phase(value)
    value isa AbstractString ||
        fail("phase", "must be the string first or revision-check")
    phase = String(value)
    phase in ("first", "revision-check") ||
        fail("phase", "must be first or revision-check")
    return phase
end

function _publication_date(value)
    value isa Date && return value
    value isa AbstractString ||
        fail("publication_date", "must be Date or canonical YYYY-MM-DD")
    text = String(value)
    try
        date = Date(text)
        string(date) == text ||
            fail("publication_date", "must be canonical YYYY-MM-DD")
        return date
    catch error
        error isa RestartRecurringAcquisitionError && rethrow()
        fail("publication_date", "must be canonical YYYY-MM-DD")
    end
end

function _authorization(schedule, publication_date, phase; observed = nothing)
    date = _publication_date(publication_date)
    slot = try
        RestartControl.planned_slot(schedule, date, _phase(phase))
    catch error
        error isa RestartControl.CampaignRestartError ||
            rethrow()
        fail("restart authorization", sprint(showerror, error))
    end
    if observed !== nothing
        observed isa DateTime || fail("clock", "must return UTC DateTime values")
        slot.scheduled_at_utc <= observed <= slot.deadline_at_utc ||
            fail(
            "restart authorization",
            "observation is outside the schedule-derived closed UTC window",
        )
    end
    return (;
        publication_date = slot.publication_date,
        effective_date = slot.effective_date,
        phase = slot.phase,
        state_class_candidate = slot.state_class,
        window_start_utc = slot.scheduled_at_utc,
        window_deadline_utc = slot.deadline_at_utc,
        transaction_id = slot.transaction_id,
        bundle_path = slot.bundle_path,
        journal_path = slot.journal_path,
        predecessor_bundle_path = slot.predecessor_bundle_path,
        rate_query = slot.rate_query,
        volume_query = slot.volume_query,
        network_execution_authorized = false,
        raw_data_write_authorized = false,
    )
end

phase_state(phase) =
    _phase(phase) == "first" ?
    "FIRST_0900_STATE" :
    "SAME_DAY_1430_REVISION_CHECK"

function canonical_transaction_id(publication_date, phase)
    bindings = _source_bindings()
    return _authorization(
        bindings.schedule,
        publication_date,
        phase,
    ).transaction_id
end

function _canonical_paths(
        output_root,
        authorization;
        synthetic_fixture = false,
    )
    root = abspath(String(output_root))
    if synthetic_fixture
        root != RESTART_OUTPUT_ROOT ||
            fail(
            "output root",
            "synthetic fixtures are forbidden from the restart campaign root",
        )
    else
        root == RESTART_OUTPUT_ROOT ||
            fail(
            "output root",
            "restart capture is fixed to $RESTART_OUTPUT_ROOT_RELATIVE",
        )
    end
    transaction_id = authorization.transaction_id
    date_root = joinpath(root, string(authorization.publication_date))
    state_root = joinpath(date_root, phase_state(authorization.phase))
    final_path = joinpath(state_root, transaction_id)
    journal_path = joinpath(state_root, ".journal-$transaction_id")
    predecessor_path = if authorization.phase == "first"
        joinpath(
            date_root,
            phase_state("first"),
            transaction_id,
        )
    else
        relative_predecessor = authorization.predecessor_bundle_path
        relative_predecessor == "NOT_APPLICABLE" &&
            fail("restart paths", "revision predecessor is absent")
        schedule_root = RESTART_OUTPUT_ROOT_RELATIVE * "/"
        startswith(relative_predecessor, schedule_root) ||
            fail("restart paths", "predecessor is outside restart root")
        joinpath(
            root,
            chop(
                relative_predecessor;
                head = length(schedule_root),
                tail = 0,
            ),
        )
    end
    expected_bundle = joinpath(
        RESTART_OUTPUT_ROOT_RELATIVE,
        string(authorization.publication_date),
        phase_state(authorization.phase),
        transaction_id,
    )
    expected_journal = joinpath(
        RESTART_OUTPUT_ROOT_RELATIVE,
        string(authorization.publication_date),
        phase_state(authorization.phase),
        ".journal-$transaction_id",
    )
    authorization.bundle_path == expected_bundle ||
        fail("restart paths", "schedule bundle path is not canonical")
    authorization.journal_path == expected_journal ||
        fail("restart paths", "schedule journal path is not canonical")
    return (;
        root,
        date_root,
        state_root,
        final_path,
        journal_path,
        transaction_id,
        predecessor_path,
    )
end

function _request_specs(authorization)
    rate_query = authorization.rate_query
    volume_query = authorization.volume_query
    return [
        (
            object_id = "rate_response",
            requested_url = "$DATA_ENDPOINT?$rate_query",
            canonical_query = rate_query,
            media_types = ("application/json",),
            extension = "json",
            maximum_bytes = 8_000_000,
        ),
        (
            object_id = "volume_response",
            requested_url = "$DATA_ENDPOINT?$volume_query",
            canonical_query = volume_query,
            media_types = ("application/json",),
            extension = "json",
            maximum_bytes = 8_000_000,
        ),
        (
            object_id = "api_documentation_snapshot",
            requested_url = API_DOCUMENTATION_URL,
            canonical_query = "NOT_APPLICABLE",
            media_types = ("text/html",),
            extension = "html",
            maximum_bytes = 2_000_000,
        ),
        (
            object_id = "openapi_snapshot",
            requested_url = OPENAPI_URL,
            canonical_query = "NOT_APPLICABLE",
            media_types = (
                "application/octet-stream",
                "application/yaml",
                "text/plain",
                "text/yaml",
            ),
            extension = "yml",
            maximum_bytes = 2_000_000,
        ),
        (
            object_id = "terms_snapshot",
            requested_url = TERMS_URL,
            canonical_query = "NOT_APPLICABLE",
            media_types = ("text/html",),
            extension = "html",
            maximum_bytes = 2_000_000,
        ),
        (
            object_id = "holiday_snapshot",
            requested_url = HOLIDAY_URL,
            canonical_query = "NOT_APPLICABLE",
            media_types = ("text/html",),
            extension = "html",
            maximum_bytes = 2_000_000,
        ),
    ]
end

function request_plan(publication_date, phase)
    bindings = _source_bindings()
    authorization = _authorization(
        bindings.schedule,
        publication_date,
        phase,
    )
    return _request_specs(authorization)
end

function dry_run_plan(
        publication_date,
        phase;
        output_root = RESTART_OUTPUT_ROOT,
        synthetic_test_fixture = false,
    )
    synthetic_test_fixture isa Bool ||
        fail("dry run", "synthetic_test_fixture must be Boolean")
    bindings = _source_bindings()
    authorization = _authorization(
        bindings.schedule,
        publication_date,
        phase,
    )
    paths = _canonical_paths(
        output_root,
        authorization;
        synthetic_fixture = synthetic_test_fixture,
    )
    return (
        schema_version = SCHEMA_VERSION,
        dry_run = true,
        network_requests_made = 0,
        filesystem_writes_made = 0,
        synthetic_test_fixture,
        campaign_eligible = !synthetic_test_fixture,
        authorization,
        transaction_id = paths.transaction_id,
        final_path = paths.final_path,
        journal_path = paths.journal_path,
        predecessor_path = authorization.phase == "revision-check" ?
            paths.predecessor_path : "NOT_APPLICABLE",
        requests = _request_specs(authorization),
        source_bindings = bindings,
        operator_authorization =
            _operator_authorization(authorization, false),
        gates = deepcopy(ALWAYS_FALSE_GATES),
    )
end

function _media_type(value)
    return lowercase(strip(first(split(String(value), ';'; limit = 2))))
end

function _reject_header_controls(value, location)
    text = String(value)
    any(character -> Int(character) < 0x20 || Int(character) == 0x7f, text) &&
        fail(location, "contains a forbidden control character")
    return text
end

function _validated_header_pair(key, value)
    raw_name = _reject_header_controls(key, "response header name")
    isempty(raw_name) &&
        fail("response header name", "must not be empty")
    raw_name == strip(raw_name) ||
        fail(
        "response header name",
        "must not have leading or trailing whitespace",
    )
    name = lowercase(raw_name)
    occursin(HEADER_NAME_PATTERN, name) ||
        fail("response header name", "is not a valid HTTP field-name")
    normalized_value =
        strip(_reject_header_controls(value, "response header $name"))
    return name, normalized_value
end

function _response_header(headers, name)
    wanted = lowercase(String(name))
    for item in headers
        key, value = if item isa Pair
            String(first(item)), String(last(item))
        elseif item isa Tuple && length(item) == 2
            String(item[1]), String(item[2])
        elseif item isa AbstractString && occursin(':', item)
            parts = split(String(item), ':'; limit = 2)
            parts[1], parts[2]
        else
            continue
        end
        lowercase(strip(key)) == wanted || continue
        return strip(value)
    end
    return ""
end

function _normalized_headers(headers)
    values = String[]
    singleton_values = Dict{String, String}()
    for item in headers
        key, value = if item isa Pair
            String(first(item)), String(last(item))
        elseif item isa Tuple && length(item) == 2
            String(item[1]), String(item[2])
        else
            fail("response headers", "must contain name/value pairs")
        end
        name, normalized_value = _validated_header_pair(key, value)
        if name in ("content-type", "content-encoding")
            comparison = lowercase(normalized_value)
            if haskey(singleton_values, name) &&
                    singleton_values[name] != comparison
                fail(
                    "response headers",
                    "conflicting duplicate $name fields are forbidden",
                )
            end
            singleton_values[name] = comparison
        end
        push!(values, "$name: $normalized_value")
    end
    return sort!(values)
end

function _validate_stored_headers(headers, location)
    headers isa Vector ||
        fail(location, "must be a Vector")
    pairs = Pair{String, String}[]
    for (index, item) in enumerate(headers)
        text = _typed_string(item, "$location[$index]")
        occursin(':', text) ||
            fail("$location[$index]", "must contain a field-name separator")
        parts = split(text, ':'; limit = 2)
        push!(pairs, parts[1] => strip(parts[2]))
    end
    normalized = _normalized_headers(pairs)
    String.(headers) == normalized ||
        fail(location, "must be canonical, sorted, and control-free")
    return normalized
end

function _direct_only_downloader()
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, _) -> begin
        curl = Downloads.Curl
        curl.setopt(easy, curl.CURLOPT_FOLLOWLOCATION, false)
        curl.setopt(easy, curl.CURLOPT_MAXREDIRS, 0)
        curl.setopt(easy, curl.CURLOPT_NETRC, curl.CURL_NETRC_IGNORED)
        curl.setopt(easy, curl.CURLOPT_NETRC_FILE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIEFILE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIE, C_NULL)
        curl.setopt(easy, curl.CURLOPT_COOKIEJAR, C_NULL)
        curl.setopt(easy, curl.CURLOPT_PROXY, "")
        curl.setopt(easy, curl.CURLOPT_NOPROXY, "*")
    end
    return downloader
end

function _live_downloader(spec)
    output = IOBuffer(; maxsize = spec.maximum_bytes + 1)
    response = try
        Downloads.request(
            spec.requested_url;
            downloader = _direct_only_downloader(),
            output,
            method = "GET",
            headers = [
                "Accept" => join(spec.media_types, ", "),
                "Accept-Encoding" => "identity",
                "User-Agent" => USER_AGENT,
            ],
            timeout = LIVE_TIMEOUT_SECONDS,
        )
    catch
        fail(
            "live $(spec.object_id)",
            "request failed under $BUILTIN_TRANSPORT_POLICY",
        )
    end
    observed_encoding =
        lowercase(_response_header(response.headers, "content-encoding"))
    return (
        body = take!(output),
        status = Int(response.status),
        final_url = String(response.url),
        headers = collect(response.headers),
        content_type = _response_header(response.headers, "content-type"),
        content_encoding =
            isempty(observed_encoding) ? "identity" : observed_encoding,
        redirect_count = 0,
        proxy_used = false,
    )
end

function _normalize_download(
        value,
        spec,
        started,
        completed,
        body,
    )
    getvalue(name) = if value isa NamedTuple
        hasproperty(value, name) ||
            fail("downloader", "missing response field $name")
        getproperty(value, name)
    elseif value isa AbstractDict
        key = String(name)
        haskey(value, key) ||
            fail("downloader", "missing response field $key")
        value[key]
    else
        fail("downloader", "must return a named tuple or string-keyed table")
    end
    status = getvalue(:status)
    status isa Integer && !(status isa Bool) ||
        fail("downloader.status", "must be an integer")
    headers = getvalue(:headers)
    headers isa AbstractVector ||
        fail("downloader.headers", "must be an array")
    return CapturedResponse(
        object_id = spec.object_id,
        body = body,
        requested_url = spec.requested_url,
        final_url = String(getvalue(:final_url)),
        http_status = Int(status),
        content_type = _reject_header_controls(
            getvalue(:content_type),
            "downloader.content_type",
        ),
        content_encoding = _reject_header_controls(
            getvalue(:content_encoding),
            "downloader.content_encoding",
        ),
        redirect_count = begin
            count = getvalue(:redirect_count)
            count isa Integer && !(count isa Bool) ||
                fail("downloader.redirect_count", "must be an integer")
            Int(count)
        end,
        proxy_used = begin
            used = getvalue(:proxy_used)
            used isa Bool ||
                fail("downloader.proxy_used", "must be Boolean")
            used
        end,
        response_headers = _normalized_headers(headers),
        request_started_at_utc = started,
        response_body_completed_at_utc = completed,
        response_metadata_observed_at_utc = completed,
    )
end

function _returned_body(value)
    raw_body = if value isa NamedTuple
        hasproperty(value, :body) ||
            fail(
            "downloader.body",
            "response returned without a preservable body",
        )
        getproperty(value, :body)
    elseif value isa AbstractDict
        haskey(value, "body") ||
            fail(
            "downloader.body",
            "response returned without a preservable body",
        )
        value["body"]
    else
        fail(
            "downloader.body",
            "response returned without a preservable body",
        )
    end
    return if raw_body isa Vector{UInt8}
        copy(raw_body)
    elseif raw_body isa AbstractString
        Vector{UInt8}(codeunits(String(raw_body)))
    else
        fail(
            "downloader.body",
            "response returned without a bytes-or-string body",
        )
    end
end

_normalize_download(value, spec, started, completed) =
    _normalize_download(
    value,
    spec,
    started,
    completed,
    _returned_body(value),
)

function _validate_transport(object, spec, authorization)
    object.object_id == spec.object_id ||
        fail("capture", "downloader returned the wrong object identity")
    object.requested_url == spec.requested_url ||
        fail(object.object_id, "requested URL changed")
    object.final_url == spec.requested_url ||
        fail(object.object_id, "redirect or final URL mismatch")
    object.redirect_count == 0 ||
        fail(object.object_id, "redirect count must be zero")
    object.proxy_used === false ||
        fail(object.object_id, "proxy use is forbidden")
    object.http_status == 200 ||
        fail(object.object_id, "HTTP status is not 200")
    object.content_encoding == "identity" ||
        fail(object.object_id, "content encoding must be identity")
    media_type = _media_type(object.content_type)
    media_type in spec.media_types ||
        fail(object.object_id, "unexpected media type $media_type")
    header_content_type =
        _response_header(object.response_headers, "content-type")
    isempty(header_content_type) ||
        _media_type(header_content_type) == media_type ||
        fail(object.object_id, "content-type header and metadata differ")
    header_content_encoding =
        lowercase(_response_header(object.response_headers, "content-encoding"))
    isempty(header_content_encoding) ||
        header_content_encoding == object.content_encoding ||
        fail(object.object_id, "content-encoding header and metadata differ")
    0 < length(object.body) <= spec.maximum_bytes ||
        fail(object.object_id, "response byte count is outside the bound")
    authorization.window_start_utc <= object.request_started_at_utc <=
        object.response_body_completed_at_utc <=
        authorization.window_deadline_utc ||
        fail(object.object_id, "capture is outside the frozen window")
    object.response_metadata_observed_at_utc ==
        object.response_body_completed_at_utc ||
        fail(object.object_id, "metadata timestamp must be conservative")
    return object
end

function _validate_request_start(started, authorization)
    started isa DateTime ||
        fail("clock", "must return UTC DateTime values")
    authorization.window_start_utc <= started <=
        authorization.window_deadline_utc ||
        fail(
        "request start",
        "outside the schedule-derived closed UTC window; request was not issued",
    )
    return started
end

function _ancestor_chain(path)
    current = abspath(String(path))
    chain = String[]
    while true
        push!(chain, current)
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    reverse!(chain)
    return chain
end

function _reject_symlink_components(path, location; require_leaf = false)
    absolute = abspath(String(path))
    for component in _ancestor_chain(absolute)
        islink(component) &&
            fail(location, "symbolic-link component rejected: $component")
        ispath(component) || continue
        isdir(component) ||
            fail(location, "non-directory path component rejected: $component")
    end
    require_leaf && !isdir(absolute) &&
        fail(location, "required directory is missing: $absolute")
    return absolute
end

function _ensure_directory_tree(path; leaf_mode = 0o755)
    absolute = abspath(String(path))
    chain = _ancestor_chain(absolute)
    for (index, component) in enumerate(chain)
        islink(component) &&
            fail("output preflight", "symbolic-link component rejected")
        if ispath(component)
            isdir(component) ||
                fail("output preflight", "non-directory component rejected")
            continue
        end
        mkdir(component; mode = index == length(chain) ? leaf_mode : 0o755)
        islink(component) &&
            fail("output preflight", "created directory became a symlink")
    end
    return _reject_symlink_components(
        absolute,
        "output preflight";
        require_leaf = true,
    )
end

function _fsync(io)
    flush(io)
    ccall(:fsync, Cint, (Cint,), fd(io)) == 0 ||
        fail("journal write", "fsync failed")
    return nothing
end

function _fsync_directory(path)
    directory = _reject_symlink_components(
        path,
        "directory sync";
        require_leaf = true,
    )
    flags =
        Base.Filesystem.JL_O_RDONLY |
        Base.Filesystem.JL_O_DIRECTORY |
        Base.Filesystem.JL_O_CLOEXEC
    io = Base.Filesystem.open(directory, flags)
    try
        ccall(:fsync, Cint, (Cint,), fd(io)) == 0 ||
            fail("directory sync", "fsync failed")
    finally
        close(io)
    end
    return nothing
end

function _write_exact(path, bytes; mode = 0o600)
    absolute = abspath(String(path))
    (ispath(absolute) || islink(absolute)) &&
        fail("journal write", "refuses to overwrite $absolute")
    parent = _reject_symlink_components(
        dirname(absolute),
        "journal write";
        require_leaf = true,
    )
    flags =
        Base.Filesystem.JL_O_WRONLY |
        Base.Filesystem.JL_O_CREAT |
        Base.Filesystem.JL_O_EXCL |
        Base.Filesystem.JL_O_CLOEXEC |
        Base.Filesystem.JL_O_NOFOLLOW
    io = Base.Filesystem.open(absolute, flags, mode)
    try
        write(io, bytes)
        _fsync(io)
    finally
        close(io)
    end
    islink(absolute) && fail("journal write", "written path became a symlink")
    stat(absolute).nlink == 1 ||
        fail("journal write", "written path is hard-linked")
    read(absolute) == bytes ||
        fail("journal write", "read-back differs")
    _fsync_directory(parent)
    return absolute
end

function _toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    return take!(io)
end

function _semantic_sha256(document, section, field)
    copy = deepcopy(document)
    pop!(copy[section], field, nothing)
    return sha256_hex(_toml_bytes(copy))
end

function _contained_path(root, path)
    relative = relpath(abspath(String(path)), abspath(String(root)))
    parts = splitpath(relative)
    return relative == "." ||
        (!isempty(parts) && first(parts) != ".." && !isabspath(relative))
end

function _reject_bundle_tree_symlinks(bundle)
    root = realpath(bundle)
    for (directory, child_directories, files) in
        walkdir(root; follow_symlinks = false)
        _contained_path(root, directory) ||
            fail("bundle", "directory escapes resolved bundle root")
        for name in (child_directories..., files...)
            child = joinpath(directory, name)
            islink(child) &&
                fail(
                "bundle",
                "symbolic-link descendant rejected: $child",
            )
        end
    end
    return root
end

function _safe_file(path, bundle)
    absolute = abspath(String(path))
    root = realpath(bundle)
    _contained_path(root, absolute) ||
        fail("bundle", "file path escapes the bundle")
    parent = _reject_symlink_components(
        dirname(absolute),
        "bundle file parent";
        require_leaf = true,
    )
    _contained_path(root, realpath(parent)) ||
        fail("bundle", "resolved file parent escapes the bundle")
    isfile(absolute) || fail("bundle", "missing file $absolute")
    islink(absolute) && fail("bundle", "symbolic-link file rejected")
    stat(absolute).nlink == 1 ||
        fail("bundle", "hard-linked file rejected")
    _contained_path(root, realpath(absolute)) ||
        fail("bundle", "resolved file escapes the bundle")
    return absolute
end

function _safe_relative(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    isempty(text) && fail(location, "must not be empty")
    isabspath(text) && fail(location, "must be relative")
    normalized = normpath(text)
    parts = splitpath(normalized)
    (normalized == "." || isempty(parts) || first(parts) == "..") &&
        fail(location, "escapes the bundle")
    normalized == text || fail(location, "must be normalized")
    return text
end

function _preflight(
        output_root,
        authorization;
        synthetic_fixture = false,
    )
    canonical = _canonical_paths(
        output_root,
        authorization;
        synthetic_fixture,
    )
    root = _ensure_directory_tree(canonical.root)
    date_root = _ensure_directory_tree(canonical.date_root)
    state_root = _ensure_directory_tree(canonical.state_root)
    for candidate in (canonical.final_path, canonical.journal_path)
        (ispath(candidate) || islink(candidate)) &&
            fail("output preflight", "append-only target already exists: $candidate")
        dirname(candidate) == state_root ||
            fail("output preflight", "candidate escapes state directory")
    end
    mkdir(canonical.journal_path; mode = 0o700)
    chmod(canonical.journal_path, 0o700)
    journal = realpath(canonical.journal_path)
    replica_a = _ensure_directory_tree(
        joinpath(journal, "replica-a");
        leaf_mode = 0o700,
    )
    replica_b = _ensure_directory_tree(
        joinpath(journal, "replica-b");
        leaf_mode = 0o700,
    )
    attempts = _ensure_directory_tree(
        joinpath(journal, "attempts");
        leaf_mode = 0o700,
    )
    receipts = _ensure_directory_tree(
        joinpath(journal, "receipts");
        leaf_mode = 0o700,
    )
    receipts_a = _ensure_directory_tree(
        joinpath(replica_a, "receipts");
        leaf_mode = 0o700,
    )
    receipts_b = _ensure_directory_tree(
        joinpath(replica_b, "receipts");
        leaf_mode = 0o700,
    )
    _fsync_directory(state_root)
    paths = merge(
        canonical,
        (;
            root,
            date_root,
            state_root,
            journal_path = journal,
            replica_a,
            replica_b,
            attempts,
            receipts,
            receipts_a,
            receipts_b,
        ),
    )
    preflight = Dict{String, Any}(
        "schema_version" => JOURNAL_SCHEMA,
        "transaction_id" => canonical.transaction_id,
        "phase" => authorization.phase,
        "publication_date" => string(authorization.publication_date),
        "effective_date" => string(authorization.effective_date),
        "journal_realpath" => journal,
        "final_path" => canonical.final_path,
        "created_before_network" => true,
        "append_only" => true,
        "private_mode" => "0700",
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
    _write_exact(
        joinpath(journal, "journal-preflight.toml"),
        _toml_bytes(preflight),
    )
    return paths
end

function _attempt_event_path(paths, index, object_id, state)
    return joinpath(
        paths.attempts,
        lpad(string(index), 4, '0') * "-$object_id-$state.toml",
    )
end

function _write_attempt_event(
        paths,
        index,
        spec,
        state,
        fields,
    )
    document = Dict{String, Any}(
        "schema_version" => ATTEMPT_SCHEMA,
        "transaction_id" => paths.transaction_id,
        "attempt_index" => index,
        "object_id" => spec.object_id,
        "state" => state,
        "requested_url" => spec.requested_url,
        "fields" => fields,
    )
    return _write_exact(
        _attempt_event_path(paths, index, spec.object_id, state),
        _toml_bytes(document),
    )
end

function _preserve_raw(paths, spec, body)
    digest = sha256_hex(body)
    name = "raw-sha256-$digest.$(spec.extension)"
    primary = joinpath(paths.replica_a, name)
    replica = joinpath(paths.replica_b, name)
    _write_exact(primary, body)
    _write_exact(replica, body)
    return (
        digest,
        primary_path = "replica-a/$name",
        replica_path = "replica-b/$name",
    )
end

function _record_failure(
        paths,
        error,
        object_id,
        attempt_index;
        request_started_at = nothing,
        downloader_invoked = false,
    )
    path = joinpath(paths.journal_path, "capture-failure.toml")
    (ispath(path) || islink(path)) && return nothing
    request_started_at === nothing || request_started_at isa DateTime ||
        fail("failure record", "request_started_at must be DateTime or nothing")
    downloader_invoked isa Bool ||
        fail("failure record", "downloader_invoked must be Boolean")
    downloader_invoked && request_started_at === nothing &&
        fail(
        "failure record",
        "an invoked downloader requires a request-start timestamp",
    )
    document = Dict{String, Any}(
        "schema_version" =>
            "beforeit-us-effr-recurring-restart-failure.v4",
        "transaction_id" => paths.transaction_id,
        "object_id" => object_id,
        "attempt_index" => attempt_index,
        "error_type" => string(typeof(error)),
        "error_message" => sprint(showerror, error),
        "request_started_at_utc" => request_started_at === nothing ?
            "NOT_OBSERVED_REQUEST_NOT_ISSUED" :
            timestamp(request_started_at),
        "downloader_invoked" => downloader_invoked,
        "journal_retained" => true,
        "retry_without_recovery_forbidden" => true,
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
    _write_exact(path, _toml_bytes(document))
    return nothing
end

function _capture_all!(
        paths,
        authorization,
        specs,
        downloader,
        clock,
    )
    objects = CapturedResponse[]
    for (index, spec) in enumerate(specs)
        prepared = clock()
        _validate_request_start(prepared, authorization)
        _write_attempt_event(
            paths,
            index,
            spec,
            "prepared",
            Dict{String, Any}(
                "pre_request_journaled_at_utc" => timestamp(prepared),
                "request_start_pending" => true,
                "written_before_request" => true,
            ),
        )
        started = clock()
        _validate_request_start(started, authorization)
        response = downloader(spec)
        body = _returned_body(response)
        preserved = _preserve_raw(paths, spec, body)
        completed = clock()
        completed isa DateTime ||
            fail("clock", "must return UTC DateTime values")
        object = _normalize_download(
            response,
            spec,
            started,
            completed,
            body,
        )
        _write_attempt_event(
            paths,
            index,
            spec,
            "completed",
            Dict{String, Any}(
                "request_started_at_utc" => timestamp(started),
                "response_body_completed_at_utc" => timestamp(completed),
                "http_status" => object.http_status,
                "final_url" => object.final_url,
                "raw_byte_count" => length(object.body),
                "raw_sha256" => preserved.digest,
                "primary_path" => preserved.primary_path,
                "replica_path" => preserved.replica_path,
                "body_preserved_before_validation" => true,
            ),
        )
        _validate_transport(object, spec, authorization)
        _write_attempt_event(
            paths,
            index,
            spec,
            "validated",
            Dict{String, Any}(
                "response_validation_passed" => true,
                "raw_sha256" => preserved.digest,
            ),
        )
        push!(objects, object)
    end
    return objects
end

function _expect_dict(value, location)
    value isa AbstractDict || fail(location, "must be an object")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return Dict{String, Any}(String(key) => item for (key, item) in value)
end

function _expect_exact_keys(value, required, optional, location)
    row = _expect_dict(value, location)
    actual = Set(keys(row))
    required_set = Set(String.(required))
    optional_set = Set(String.(optional))
    missing = sort!(collect(setdiff(required_set, actual)))
    unknown = sort!(collect(setdiff(actual, union(required_set, optional_set))))
    isempty(missing) ||
        fail(location, "missing fields: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown fields: $(join(unknown, ", "))")
    return row
end

function _closed_table(value, expected_keys, location)
    return _expect_exact_keys(
        value,
        expected_keys,
        (),
        location,
    )
end

function _typed_string(value, location; allow_empty = false)
    value isa String ||
        fail(location, "must be a String")
    (!isempty(value) || allow_empty) ||
        fail(location, "must not be empty")
    return value
end

function _typed_bool(value, location)
    value isa Bool || fail(location, "must be Bool")
    return value
end

function _typed_int(value, location; minimum = nothing)
    value isa Int && !(value isa Bool) ||
        fail(location, "must be Int and not Bool")
    minimum !== nothing && value < minimum &&
        fail(location, "is below the minimum $minimum")
    return value
end

function _typed_hash(value, location)
    text = _typed_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be a lowercase SHA-256")
    return text
end

function _require_type_exact_equal(actual, expected, location)
    if expected isa AbstractDict
        actual isa AbstractDict ||
            fail(location, "must be a table")
        actual_keys = Set(keys(actual))
        expected_keys = Set(keys(expected))
        actual_keys == expected_keys ||
            fail(location, "closed key set differs")
        for key in sort!(collect(expected_keys))
            _require_type_exact_equal(
                actual[key],
                expected[key],
                "$location.$key",
            )
        end
    elseif expected isa AbstractVector
        actual isa AbstractVector ||
            fail(location, "must be an array")
        length(actual) == length(expected) ||
            fail(location, "array length differs")
        for index in eachindex(expected)
            _require_type_exact_equal(
                actual[index],
                expected[index],
                "$location[$index]",
            )
        end
    else
        typeof(actual) === typeof(expected) ||
            fail(
            location,
            "type differs: expected $(typeof(expected)), got $(typeof(actual))",
        )
        isequal(actual, expected) ||
            fail(location, "value differs from closed expectation")
    end
    return nothing
end

function _expect_string(value, location; allow_empty = false)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    (!isempty(text) || allow_empty) ||
        fail(location, "must not be empty")
    return text
end

function _expect_number(value, location)
    value isa Real && !(value isa Bool) ||
        fail(location, "must be a number")
    number = Float64(value)
    isfinite(number) || fail(location, "must be finite")
    return number
end

function _footnote_token(row, location)
    haskey(row, "footnoteId") || return ""
    value = row["footnoteId"]
    value isa Integer && !(value isa Bool) ||
        fail(
        "$location.footnoteId",
        "must be an exact raw JSON integer",
    )
    value in (1, 2, 3) ||
        fail(
        "$location.footnoteId",
        "is outside the closed integer vocabulary 1, 2, 3",
    )
    return string(value)
end

_json_whitespace(byte) =
    byte in (UInt8(' '), UInt8('\t'), UInt8('\n'), UInt8('\r'))

function _skip_json_whitespace(bytes, index)
    cursor = index
    while cursor <= length(bytes) && _json_whitespace(bytes[cursor])
        cursor += 1
    end
    return cursor
end

function _scan_json_string(bytes, index, location)
    index <= length(bytes) && bytes[index] == UInt8('"') ||
        fail(location, "expected a JSON string")
    cursor = index + 1
    while cursor <= length(bytes)
        byte = bytes[cursor]
        if byte == UInt8('"')
            return cursor + 1
        elseif byte == UInt8('\\')
            cursor += 1
            cursor <= length(bytes) ||
                fail(location, "unterminated JSON escape")
            escape = bytes[cursor]
            if escape == UInt8('u')
                cursor + 4 <= length(bytes) ||
                    fail(location, "truncated JSON unicode escape")
                for offset in 1:4
                    isxdigit(Char(bytes[cursor + offset])) ||
                        fail(location, "invalid JSON unicode escape")
                end
                cursor += 5
                continue
            end
            escape in UInt8.(['"', '\\', '/', 'b', 'f', 'n', 'r', 't']) ||
                fail(location, "invalid JSON escape")
        elseif byte < 0x20
            fail(location, "unescaped JSON control character")
        end
        cursor += 1
    end
    return fail(location, "unterminated JSON string")
end

function _decoded_json_member(bytes, first_index, next_index, location)
    token = String(copy(bytes[first_index:(next_index - 1)]))
    decoded = try
        JSON.parse(token)
    catch
        fail(location, "invalid JSON member-name string")
    end
    decoded isa AbstractString ||
        fail(location, "JSON member name did not decode to a string")
    return String(decoded)
end

function _scan_json_value(bytes, index, location)
    cursor = _skip_json_whitespace(bytes, index)
    cursor <= length(bytes) || fail(location, "missing JSON value")
    byte = bytes[cursor]
    if byte == UInt8('{')
        cursor = _skip_json_whitespace(bytes, cursor + 1)
        seen = Set{String}()
        if cursor <= length(bytes) && bytes[cursor] == UInt8('}')
            return cursor + 1
        end
        while true
            member_start = cursor
            member_next =
                _scan_json_string(bytes, member_start, location)
            member = _decoded_json_member(
                bytes,
                member_start,
                member_next,
                location,
            )
            member in seen &&
                fail(
                location,
                "duplicate JSON member name after escape decoding: $member",
            )
            push!(seen, member)
            cursor = _skip_json_whitespace(bytes, member_next)
            cursor <= length(bytes) && bytes[cursor] == UInt8(':') ||
                fail(location, "missing JSON member separator")
            cursor = _scan_json_value(bytes, cursor + 1, location)
            cursor = _skip_json_whitespace(bytes, cursor)
            cursor <= length(bytes) ||
                fail(location, "unterminated JSON object")
            if bytes[cursor] == UInt8('}')
                return cursor + 1
            end
            bytes[cursor] == UInt8(',') ||
                fail(location, "invalid JSON object separator")
            cursor = _skip_json_whitespace(bytes, cursor + 1)
        end
    elseif byte == UInt8('[')
        cursor = _skip_json_whitespace(bytes, cursor + 1)
        if cursor <= length(bytes) && bytes[cursor] == UInt8(']')
            return cursor + 1
        end
        while true
            cursor = _scan_json_value(bytes, cursor, location)
            cursor = _skip_json_whitespace(bytes, cursor)
            cursor <= length(bytes) ||
                fail(location, "unterminated JSON array")
            if bytes[cursor] == UInt8(']')
                return cursor + 1
            end
            bytes[cursor] == UInt8(',') ||
                fail(location, "invalid JSON array separator")
            cursor = _skip_json_whitespace(bytes, cursor + 1)
        end
    elseif byte == UInt8('"')
        return _scan_json_string(bytes, cursor, location)
    end
    start = cursor
    while cursor <= length(bytes) &&
            !(bytes[cursor] in UInt8.([',', '}', ']'])) &&
            !_json_whitespace(bytes[cursor])
        cursor += 1
    end
    cursor > start || fail(location, "missing JSON primitive")
    return cursor
end

function _reject_duplicate_json_members(body, location)
    bytes = Vector{UInt8}(body)
    cursor = _scan_json_value(bytes, 1, location)
    _skip_json_whitespace(bytes, cursor) == length(bytes) + 1 ||
        fail(location, "trailing bytes after JSON value")
    return nothing
end

function _select_effr_row(body, report_type, effective_date)
    _reject_duplicate_json_members(body, "$report_type response")
    parsed = try
        JSON.parse(String(copy(body)))
    catch
        fail("$report_type response", "body is not valid UTF-8 JSON")
    end
    envelope = _expect_exact_keys(
        parsed,
        ("refRates",),
        (),
        "$report_type response envelope",
    )
    rows = envelope["refRates"]
    rows isa AbstractVector ||
        fail("$report_type response.refRates", "must be an array")
    candidates = Tuple{Int, Dict{String, Any}}[]
    for (index, raw_row) in enumerate(rows)
        row = _expect_dict(raw_row, "$report_type response.refRates[$index]")
        get(row, "type", nothing) == "EFFR" || continue
        push!(candidates, (index, row))
    end
    length(candidates) == 1 ||
        fail(
        "$report_type response.refRates",
        "must contain exactly one raw type=EFFR row",
    )
    index, row = only(candidates)
    common = ("effectiveDate", "type", "revisionIndicator")
    optional = ("footnoteId", "currentState")
    required = report_type == "rate" ?
        (
            common...,
            "percentRate",
            "percentPercentile1",
            "percentPercentile25",
            "percentPercentile75",
            "percentPercentile99",
            "targetRateFrom",
            "targetRateTo",
        ) :
        (common..., "volumeInBillions")
    row = _expect_exact_keys(
        row,
        required,
        optional,
        "$report_type EFFR row",
    )
    _expect_string(row["effectiveDate"], "$report_type effectiveDate") ==
        string(effective_date) ||
        fail("$report_type effectiveDate", "does not equal authorized date")
    _expect_string(row["type"], "$report_type identity") == "EFFR" ||
        fail("$report_type identity", "must be EFFR")
    revision = _expect_string(
        row["revisionIndicator"],
        "$report_type revisionIndicator";
        allow_empty = true,
    )
    revision in ("", "r") ||
        fail("$report_type revisionIndicator", "unknown raw token")
    current_state_present = haskey(row, "currentState")
    current_state = if current_state_present
        row["currentState"] isa Bool ||
            fail("$report_type currentState", "must be Boolean")
        row["currentState"] === false ||
            fail("$report_type currentState", "true state is ineligible")
        false
    else
        nothing
    end
    values = Dict{String, Any}()
    if report_type == "rate"
        for field in (
                "percentRate",
                "percentPercentile1",
                "percentPercentile25",
                "percentPercentile75",
                "percentPercentile99",
                "targetRateFrom",
                "targetRateTo",
            )
            values[field] = _expect_number(row[field], "$report_type $field")
        end
    else
        values["volumeInBillions"] =
            _expect_number(row["volumeInBillions"], "$report_type volume")
    end
    return (
        json_pointer = "/refRates/$(index - 1)",
        one_based_index = index,
        raw_keys = Tuple(sort!(collect(keys(row)))),
        revision,
        footnote = _footnote_token(row, "$report_type EFFR row"),
        current_state_present,
        current_state,
        current_state_source = current_state_present ?
            "RAW_FIELD_FALSE" :
            "ABSENT_FROM_RAW_RESPONSE_NOT_DERIVED",
        values,
    )
end

function _identity_record(report_type, selected)
    return Dict{String, Any}(
        "report_type" => report_type,
        "full_response_preserved_before_parse" => true,
        "selection_rule" => "EXACTLY_ONE_RAW_TYPE_EQUALS_EFFR",
        "json_pointer" => selected.json_pointer,
        "one_based_array_index" => selected.one_based_index,
        "raw_identity_field" => "type",
        "raw_identity_value" => "EFFR",
        "raw_keys" => collect(selected.raw_keys),
        "raw_revision_indicator" => selected.revision,
        "normalized_footnote_token" => selected.footnote,
        "raw_current_state_present" => selected.current_state_present,
        "raw_current_state_value" =>
            selected.current_state_present ? "false" : "ABSENT",
        "current_state_source" => selected.current_state_source,
        "alias_or_first_row_fallback_used" => false,
    )
end

function _object_by_id(objects, object_id)
    matches = [object for object in objects if object.object_id == object_id]
    length(matches) == 1 ||
        fail("capture", "expected exactly one $object_id")
    return only(matches)
end

function _receipt_blockers(revision)
    blockers = Set(
        (
            "EMPIRICAL_EXECUTION_FORBIDDEN",
            "HISTORICAL_FIRST_BYTES_UNPROVEN",
            "ORIGIN_ADMISSION_FORBIDDEN",
            "PRODUCTION_USE_FORBIDDEN",
            "PROMOTION_FORBIDDEN",
            "RATE_VOLUME_PAIR_NOT_YET_VALIDATED",
            "READINESS_FALSE",
        ),
    )
    revision == "r" &&
        push!(blockers, "OPENAPI_EXAMPLE_MISMATCH_PRESERVED")
    return sort!(collect(blockers))
end

function _build_receipt(
        object,
        selected,
        report_type,
        state_class,
        authorization;
        openapi_sha256,
        terms_sha256,
        storage_receipt_sha256,
        predecessor = "NONE",
    )
    required_revision =
        state_class == "FIRST_0900_STATE" ? "" :
        state_class == "SAME_DAY_1430_REVISION" ? "r" :
        fail("receipt", "unsupported state")
    selected.current_state_present ||
        fail("$report_type receipt", CURRENT_STATE_BLOCKER)
    selected.current_state === false ||
        fail("$report_type receipt", "raw currentState must be false")
    selected.revision == required_revision ||
        fail("$report_type receipt", "raw revision token is incompatible")
    predecessor_required = state_class == "SAME_DAY_1430_REVISION"
    predecessor_required && predecessor == "NONE" &&
        fail("$report_type receipt", "revision requires predecessor")
    effective = string(authorization.effective_date)
    publication = string(authorization.publication_date)
    query = "endDate=$effective&startDate=$effective&type=$report_type"
    raw_digest = sha256_hex(object.body)
    not_requested = "NOT_REQUESTED_IN_REPORT_TYPE"
    values = selected.values
    raw_fields = Dict{String, Any}(
        "effectiveDate" => effective,
        "type" => report_type,
        "percentRate" =>
            report_type == "rate" ? values["percentRate"] : not_requested,
        "percentPercentile1" =>
            report_type == "rate" ? values["percentPercentile1"] : not_requested,
        "percentPercentile25" =>
            report_type == "rate" ? values["percentPercentile25"] : not_requested,
        "percentPercentile75" =>
            report_type == "rate" ? values["percentPercentile75"] : not_requested,
        "percentPercentile99" =>
            report_type == "rate" ? values["percentPercentile99"] : not_requested,
        "targetRateFrom" =>
            report_type == "rate" ? values["targetRateFrom"] : not_requested,
        "targetRateTo" =>
            report_type == "rate" ? values["targetRateTo"] : not_requested,
        "volumeInBillions" =>
            report_type == "volume" ? values["volumeInBillions"] : not_requested,
        "footnote" => selected.footnote,
        "revisionIndicator" => selected.revision,
        "currentState" => false,
    )
    encoded_revision = isempty(selected.revision) ? "EMPTY" : selected.revision
    document = Dict{String, Any}(
        "schema_version" => ReceiptContract.SCHEMA_VERSION,
        "receipt_id" =>
            "EFFR:$effective:$(uppercase(report_type)):$state_class",
        "source" => Dict{String, Any}(
            "authority" => "Federal Reserve Bank of New York",
            "source_id" => "NYFED_MARKETS_API",
            "series_id" => "EFFR",
            "evidence_track" => "STRICT_FIRST_PUBLIC_BYTES",
            "concept_regime" =>
                "POST_2016_FR2420_VOLUME_WEIGHTED_MEDIAN",
            "route_class" => "NYFED_PROSPECTIVE_CAPTURE",
            "historical_vintage_claim" =>
                "CURRENT_API_DOES_NOT_PROVE_HISTORICAL_VINTAGE",
        ),
        "observation" => Dict{String, Any}(
            "effective_date" => effective,
            "publication_date" => publication,
            "publication_utc_offset" => "-04:00",
            "report_type" => report_type,
            "state_class" => state_class,
            "scheduled_publication_window" =>
                state_class == "FIRST_0900_STATE" ?
                "NYFED_APPROX_0900_ET" :
                "NYFED_APPROX_1430_ET",
            "pair_key" =>
                "effectiveDate=$effective;revisionToken=$encoded_revision",
        ),
        "request" => Dict{String, Any}(
            "endpoint" => DATA_ENDPOINT,
            "canonical_query" => query,
            "requested_url" => "$DATA_ENDPOINT?$query",
            "request_started_at_utc" =>
                timestamp(object.request_started_at_utc),
            "secret_ref" => "NOT_REQUIRED_PUBLIC_ENDPOINT",
        ),
        "response" => Dict{String, Any}(
            "response_headers_at_utc" =>
                timestamp(object.response_metadata_observed_at_utc),
            "response_body_completed_at_utc" =>
                timestamp(object.response_body_completed_at_utc),
            "availability_upper_bound_utc" =>
                timestamp(object.response_body_completed_at_utc),
            "http_status" => object.http_status,
            "final_host" => FINAL_HOST,
            "final_url" => object.final_url,
            "redirect_count" => 0,
            "redirect_chain" => Any[],
            "headers_complete" => true,
            "content_type" => _media_type(object.content_type),
            "content_encoding" => object.content_encoding,
            "content_length" => length(object.body),
        ),
        "artifact" => Dict{String, Any}(
            "raw_sha256" => raw_digest,
            "openapi_sha256" => openapi_sha256,
            "durable_storage_locator" => "artifact-sha256:$raw_digest",
            "durable_storage_receipt_sha256" =>
                storage_receipt_sha256,
        ),
        "raw_fields" => raw_fields,
        "classification" => Dict{String, Any}(
            "revision_class" =>
                isempty(selected.revision) ?
                "NOT_REVISED_RAW_EMPTY_TOKEN" :
                "DOCUMENTED_REVISED_RAW_TOKEN_WITH_SCHEMA_MISMATCH",
            "footnote_class" => Dict(
                "" => "NO_FOOTNOTE_RAW_EMPTY_TOKEN",
                "1" => "DOCUMENTED_REDUCED_VOLUME",
                "2" => "DOCUMENTED_BROKER_CONTINGENCY",
                "3" => "DOCUMENTED_PRIOR_DAY_REPUBLICATION",
            )[selected.footnote],
            "rate_report_volume_class" =>
                report_type == "rate" ?
                "NOT_REQUESTED_IN_REPORT_TYPE" :
                "PUBLISHED_VOLUME_FIELD",
            "unsupported_blank_class" => "NO_UNSUPPORTED_BLANK",
            "current_state_class" => "NOT_CURRENT_STATE_FLAG",
            "schema_class" =>
                isempty(selected.revision) ?
                "PINNED_CURRENT_API_EXACT_FIELDSET" :
                "DOCUMENTED_OPENAPI_EXAMPLE_MISMATCH_PINNED_FIELDSET",
            "schema_mismatch_detail" => "NONE",
            "quarantine_class" => "NOT_QUARANTINED",
            "adjudication_state" => "NOT_REQUIRED_EXACT_SCHEMA",
            "evidence_locator" => "artifact-sha256:$raw_digest",
            "blockers" => _receipt_blockers(selected.revision),
        ),
        "governance" => Dict{String, Any}(
            "terms_url" => TERMS_URL,
            "terms_snapshot_sha256" => terms_sha256,
            "terms_snapshot_date" => publication,
            "terms_review_decision" => "APPROVED_FOR_BOUNDED_CAPTURE",
            "attribution_requirement" =>
                "ATTRIBUTION_REQUIRED_FEDERAL_RESERVE_BANK_OF_NEW_YORK",
            "disclaimer_requirement" =>
                "REFERENCE_RATE_DISCLAIMER_REQUIRED_FOR_DERIVED_USE",
            "redistribution_scope" => "INTERNAL_RESEARCH_ONLY",
            "secret_ref" => "NOT_REQUIRED_PUBLIC_ENDPOINT",
        ),
        "lineage" => Dict{String, Any}(
            "predecessor_receipt_sha256" => predecessor,
            "supersedes_receipt_sha256" => predecessor,
            "supersession_status" =>
                predecessor_required ?
                "SUPERSEDES_BY_POINTER_WITHOUT_OVERWRITE" :
                "NEW_NONOVERWRITING_STATE",
        ),
        "gates" => Dict{String, Any}(
            "historical_first_byte_proven" => false,
            "origin_admissible" => false,
            "empirical_forecast_allowed" => false,
            "source_inventory_mutation_allowed" => false,
            "promotion_eligible" => false,
            "production_scoring_allowed" => false,
            "readiness" => false,
            "current_api_proves_historical_vintage" => false,
        ),
        "receipt_sha256" => repeat("0", 64),
    )
    document["receipt_sha256"] =
        ReceiptContract.canonical_receipt_sha256(document)
    ReceiptContract.validate_receipt(
        document,
        document["receipt_sha256"],
    )
    return document
end

function _storage_receipt(paths, objects, authorization)
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => STORAGE_SCHEMA,
            "canonicalization" => STORAGE_CANONICALIZATION,
            "receipt_sha256" => repeat("0", 64),
        ),
        "transaction_id" => paths.transaction_id,
        "publication_date" => string(authorization.publication_date),
        "effective_date" => string(authorization.effective_date),
        "copy_class" => "TWO_LOCAL_INTEGRITY_REPLICAS_NOT_DURABLE_STORAGE",
        "objects" => [
            Dict{String, Any}(
                    "object_id" => object.object_id,
                    "raw_sha256" => sha256_hex(object.body),
                    "raw_byte_count" => length(object.body),
                ) for object in objects
        ],
        "durable_external_copy_count" => 0,
        "external_timestamp_verified" => false,
        "retention_through_2031_attested" => false,
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
    document["artifact"]["receipt_sha256"] =
        _semantic_sha256(document, "artifact", "receipt_sha256")
    return document
end

function _write_triplicate(paths, relative_path, bytes)
    targets = (
        joinpath(paths.journal_path, relative_path),
        joinpath(paths.replica_a, relative_path),
        joinpath(paths.replica_b, relative_path),
    )
    for target in targets
        _write_exact(target, bytes)
    end
    return targets
end

function _write_receipts(paths, receipts)
    files = Dict{String, String}()
    for (report_type, receipt) in receipts
        digest = receipt["receipt_sha256"]
        name = "$report_type-receipt-sha256-$digest.toml"
        bytes = _toml_bytes(receipt)
        for directory in (paths.receipts, paths.receipts_a, paths.receipts_b)
            _write_exact(joinpath(directory, name), bytes)
        end
        files[report_type] = name
    end
    return files
end

function _result_template()
    return Dict{String, Any}(
        "status" => "PENDING_FAIL_CLOSED_EVALUATION",
        "success" => false,
        "raw_capture_complete" => false,
        "failure_code" => "NOT_YET_EVALUATED",
        "failure_detail" => "NOT_YET_EVALUATED",
        "rate_receipt_file" => "NONE",
        "volume_receipt_file" => "NONE",
        "rate_receipt_sha256" => "NONE",
        "volume_receipt_sha256" => "NONE",
        "pair_status" => "NOT_EVALUATED",
        "predecessor_bundle" => "NOT_APPLICABLE",
        "predecessor_manifest_sha256" => "NONE",
        "predecessor_rate_raw_sha256" => "NONE",
        "predecessor_volume_raw_sha256" => "NONE",
        "predecessor_rate_receipt_sha256" => "NONE",
        "predecessor_volume_receipt_sha256" => "NONE",
        "byte_equality_rate" => false,
        "byte_equality_volume" => false,
        "revision_observed" => false,
        "revision_receipt_created" => false,
        "one_date_receipt_validated" => false,
        "receipt_authentication_status" =>
            "SELF_GENERATED_LOCAL_INTEGRITY_PIN_NOT_OUT_OF_BAND",
    )
end

function _validate_result_shape(value)
    template = _result_template()
    result = _closed_table(
        value,
        keys(template),
        "bundle result",
    )
    for key in keys(template)
        expected = template[key]
        if expected isa String
            _typed_string(
                result[key],
                "bundle result.$key";
                allow_empty = true,
            )
        elseif expected isa Bool
            _typed_bool(result[key], "bundle result.$key")
        else
            fail("bundle result.$key", "template type is unhandled")
        end
    end
    return result
end

function _predecessor_fields!(result, predecessor)
    result["predecessor_bundle"] = predecessor.bundle_path
    result["predecessor_manifest_sha256"] =
        predecessor.manifest_sha256
    result["predecessor_rate_raw_sha256"] =
        predecessor.rate_raw_sha256
    result["predecessor_volume_raw_sha256"] =
        predecessor.volume_raw_sha256
    result["predecessor_rate_receipt_sha256"] =
        predecessor.rate_receipt_sha256
    result["predecessor_volume_receipt_sha256"] =
        predecessor.volume_receipt_sha256
    return result
end

function _mark_absent!(result, blockers; revision_observed)
    CURRENT_STATE_BLOCKER in blockers || push!(blockers, CURRENT_STATE_BLOCKER)
    sort!(blockers)
    result["status"] =
        "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
    result["success"] = true
    result["raw_capture_complete"] = true
    result["failure_code"] = CURRENT_STATE_BLOCKER
    result["failure_detail"] =
        "Raw EFFR rows omit currentState; no value was derived and no receipt was created."
    result["pair_status"] =
        "NOT_CREATED_RAW_CURRENT_STATE_FIELD_ABSENT"
    result["revision_observed"] = revision_observed
    return nothing
end

function _evaluate_capture(
        paths,
        authorization,
        objects,
        storage_receipt_sha256,
        predecessor,
    )
    by_id = Dict(object.object_id => object for object in objects)
    rate = _select_effr_row(
        by_id["rate_response"].body,
        "rate",
        authorization.effective_date,
    )
    volume = _select_effr_row(
        by_id["volume_response"].body,
        "volume",
        authorization.effective_date,
    )
    rate.revision == volume.revision ||
        fail("capture", "rate and volume revision tokens differ")
    rate.footnote == volume.footnote ||
        fail("capture", "rate and volume footnoteId presence/value differs")
    rate.current_state_present == volume.current_state_present ||
        fail("capture", "rate and volume currentState presence differs")
    docs = String(copy(by_id["api_documentation_snapshot"].body))
    occursin("markets-api.yml", docs) ||
        fail("capture", "API documentation lacks the OpenAPI binding")
    openapi_sha256 = sha256_hex(by_id["openapi_snapshot"].body)
    terms_sha256 = sha256_hex(by_id["terms_snapshot"].body)
    blockers = copy(BASE_BLOCKERS)
    result = _result_template()
    receipts = Dict{String, Dict{String, Any}}()
    pair = nothing
    if authorization.phase == "first"
        rate.revision == "" ||
            fail("first-state capture", "raw revision token must be empty")
        if !rate.current_state_present
            _mark_absent!(result, blockers; revision_observed = false)
        else
            receipts["rate"] = _build_receipt(
                by_id["rate_response"],
                rate,
                "rate",
                "FIRST_0900_STATE",
                authorization;
                openapi_sha256,
                terms_sha256,
                storage_receipt_sha256,
            )
            receipts["volume"] = _build_receipt(
                by_id["volume_response"],
                volume,
                "volume",
                "FIRST_0900_STATE",
                authorization;
                openapi_sha256,
                terms_sha256,
                storage_receipt_sha256,
            )
            pair = ReceiptContract.pair_receipts(
                receipts["rate"],
                receipts["rate"]["receipt_sha256"],
                receipts["volume"],
                receipts["volume"]["receipt_sha256"],
            )
            pair.pair_status ==
                "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT" ||
                fail("first-state capture", "receipt pair did not validate")
            result["status"] =
                "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
            result["success"] = true
            result["raw_capture_complete"] = true
            result["failure_code"] = "NONE"
            result["failure_detail"] = "NONE"
            result["pair_status"] = pair.pair_status
            result["one_date_receipt_validated"] = true
        end
    else
        predecessor === nothing &&
            fail("revision check", "canonical predecessor is required")
        _predecessor_fields!(result, predecessor)
        rate_equal =
            by_id["rate_response"].body == predecessor.rate_bytes
        volume_equal =
            by_id["volume_response"].body == predecessor.volume_bytes
        result["byte_equality_rate"] = rate_equal
        result["byte_equality_volume"] = volume_equal
        if rate.revision == ""
            rate_equal && volume_equal ||
                fail(
                "revision check",
                "bytes changed without the closed raw revision token r",
            )
            !rate.current_state_present &&
                push!(blockers, CURRENT_STATE_BLOCKER)
            sort!(unique!(blockers))
            result["status"] = RAW_UNCHANGED_PRESERVATION_STATUS
            result["success"] = true
            result["raw_capture_complete"] = true
            result["failure_code"] = "NONE"
            result["failure_detail"] = "NONE"
            result["pair_status"] = "NOT_APPLICABLE_NO_REVISION"
        elseif rate.revision == "r"
            (!rate_equal || !volume_equal) ||
                fail(
                "revision check",
                "raw token r appeared without any response-byte change",
            )
            if !rate.current_state_present
                _mark_absent!(result, blockers; revision_observed = true)
            else
                predecessor.rate_receipt_sha256 != "NONE" ||
                    fail("revision check", "predecessor rate receipt is absent")
                predecessor.volume_receipt_sha256 != "NONE" ||
                    fail("revision check", "predecessor volume receipt is absent")
                receipts["rate"] = _build_receipt(
                    by_id["rate_response"],
                    rate,
                    "rate",
                    "SAME_DAY_1430_REVISION",
                    authorization;
                    openapi_sha256,
                    terms_sha256,
                    storage_receipt_sha256,
                    predecessor = predecessor.rate_receipt_sha256,
                )
                receipts["volume"] = _build_receipt(
                    by_id["volume_response"],
                    volume,
                    "volume",
                    "SAME_DAY_1430_REVISION",
                    authorization;
                    openapi_sha256,
                    terms_sha256,
                    storage_receipt_sha256,
                    predecessor = predecessor.volume_receipt_sha256,
                )
                pair = ReceiptContract.pair_receipts(
                    receipts["rate"],
                    receipts["rate"]["receipt_sha256"],
                    receipts["volume"],
                    receipts["volume"]["receipt_sha256"],
                )
                pair.pair_status ==
                    "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT" ||
                    fail("revision check", "receipt pair did not validate")
                result["status"] =
                    "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE"
                result["success"] = true
                result["raw_capture_complete"] = true
                result["failure_code"] = "NONE"
                result["failure_detail"] = "NONE"
                result["pair_status"] = pair.pair_status
                result["revision_observed"] = true
                result["revision_receipt_created"] = true
                result["one_date_receipt_validated"] = true
            end
        else
            fail("revision check", "unsupported raw revision token")
        end
    end
    return (
        result,
        receipts,
        pair,
        blockers,
        row_identity = [
            _identity_record("rate", rate),
            _identity_record("volume", volume),
        ],
    )
end

function _object_record(object, spec)
    digest = sha256_hex(object.body)
    name = "raw-sha256-$digest.$(spec.extension)"
    return Dict{String, Any}(
        "object_id" => object.object_id,
        "role" => spec.object_id,
        "canonical_query" => spec.canonical_query,
        "requested_url" => object.requested_url,
        "final_url" => object.final_url,
        "http_method" => "GET",
        "http_status" => object.http_status,
        "content_type" => object.content_type,
        "content_encoding" => object.content_encoding,
        "redirect_count" => object.redirect_count,
        "proxy_used" => object.proxy_used,
        "raw_byte_count" => length(object.body),
        "raw_sha256" => digest,
        "primary_path" => "replica-a/$name",
        "replica_path" => "replica-b/$name",
        "request_started_at_utc" =>
            timestamp(object.request_started_at_utc),
        "response_body_completed_at_utc" =>
            timestamp(object.response_body_completed_at_utc),
        "response_metadata_observed_at_utc" =>
            timestamp(object.response_metadata_observed_at_utc),
        "response_headers" => copy(object.response_headers),
    )
end

function _build_manifest(
        paths,
        authorization,
        specs,
        objects,
        storage_receipt,
        evaluation,
        receipt_files,
        bindings,
        operator_authorization,
        synthetic_fixture,
    )
    result = deepcopy(evaluation.result)
    if haskey(evaluation.receipts, "rate")
        result["rate_receipt_file"] = receipt_files["rate"]
        result["volume_receipt_file"] = receipt_files["volume"]
        result["rate_receipt_sha256"] =
            evaluation.receipts["rate"]["receipt_sha256"]
        result["volume_receipt_sha256"] =
            evaluation.receipts["volume"]["receipt_sha256"]
    end
    manifest = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => SCHEMA_VERSION,
            "manifest_id" =>
                "effr-recurring-restart-v4.$(authorization.publication_date).$(phase_state(authorization.phase)).$(paths.transaction_id)",
            "canonicalization" => MANIFEST_CANONICALIZATION,
            "manifest_sha256" => repeat("0", 64),
        ),
        "contract_binding" => Dict{String, Any}(
            "prospective_contract_id" => PROSPECTIVE_CONTRACT_ID,
            "prospective_contract_content_sha256" =>
                PROSPECTIVE_CONTRACT_CONTENT_SHA256,
            "prospective_contract_file_sha256" =>
                PROSPECTIVE_CONTRACT_FILE_SHA256,
            "prospective_contract_status" =>
                "DRAFT_UNAPPROVED_FAIL_CLOSED",
            "restart_schedule_id" => RESTART_SCHEDULE_ID,
            "restart_schedule_content_sha256" =>
                RESTART_SCHEDULE_CONTENT_SHA256,
            "restart_schedule_file_sha256" =>
                RESTART_SCHEDULE_FILE_SHA256,
            "restart_control_file_sha256" =>
                RESTART_CONTROL_FILE_SHA256,
            "recurring_v3_source_base_module_sha256" =>
                RECURRING_V3_MODULE_FILE_SHA256,
            "recurring_v3_source_base_cli_sha256" =>
                RECURRING_V3_CLI_FILE_SHA256,
            "recurring_v3_source_base_test_sha256" =>
                RECURRING_V3_TEST_FILE_SHA256,
            "recurring_v3_source_base_readme_sha256" =>
                RECURRING_V3_README_FILE_SHA256,
            "source_base_reuse_is_not_behavioral_attestation" => true,
            "accepted_schedule_runner_restart_binding_complete" => false,
            "operator_flag_does_not_relabel_schedule_binding_complete" =>
                true,
            "receipt_contract_schema_version" =>
                ReceiptContract.SCHEMA_VERSION,
            "receipt_contract_file_sha256" =>
                RECEIPT_CONTRACT_FILE_SHA256,
            "observed_state_v3_contract_file_sha256" =>
                OBSERVED_STATE_CONTRACT_FILE_SHA256,
            "observed_state_v3_protocol_file_sha256" =>
                OBSERVED_STATE_PROTOCOL_FILE_SHA256,
            "observed_state_v3_protocol_content_sha256" =>
                OBSERVED_STATE_PROTOCOL_CONTENT_SHA256,
            "observed_state_v3_test_file_sha256" =>
                OBSERVED_STATE_TEST_FILE_SHA256,
            "observed_state_v3_readme_file_sha256" =>
                OBSERVED_STATE_README_FILE_SHA256,
            "observed_state_v3_role" =>
                "OFFLINE_ADJUDICATION_ONLY_NOT_ACQUISITION_AUTHORITY",
            "legacy_schedule_authorizes_restart_acquisition" => false,
            "raw_capture_status_is_observed_state_decision" => false,
            "acquisition_source_sha256" =>
                bindings.acquisition_source_sha256,
            "acquisition_cli_sha256" =>
                bindings.acquisition_cli_sha256,
        ),
        "event" => Dict{String, Any}(
            "campaign_id" => synthetic_fixture ?
                SYNTHETIC_CAMPAIGN_ID : CAMPAIGN_ID,
            "phase" => authorization.phase,
            "publication_date" => string(authorization.publication_date),
            "effective_date" => string(authorization.effective_date),
            "scheduled_time_utc" =>
                timestamp(authorization.window_start_utc),
            "capture_deadline_utc" =>
                timestamp(authorization.window_deadline_utc),
            "state_class_candidate" =>
                authorization.state_class_candidate,
            "publication_utc_offset" => "-04:00",
            "official_publication_day_validated" => false,
        ),
        "capture" => Dict{String, Any}(
            "transaction_id" => paths.transaction_id,
            "transport_policy" => synthetic_fixture ?
                SYNTHETIC_TRANSPORT_POLICY : BUILTIN_TRANSPORT_POLICY,
            "transport_provenance" => synthetic_fixture ?
                SYNTHETIC_TRANSPORT_PROVENANCE :
                BUILTIN_TRANSPORT_PROVENANCE,
            "transport_provenance_assertion_status" =>
                "LOCAL_UNAUTHENTICATED_RUNTIME_ASSERTION",
            "synthetic_test_fixture" => synthetic_fixture,
            "request_order" => [spec.object_id for spec in specs],
            "object_count" => length(objects),
            "network_exchange_count" =>
                "NOT_INDEPENDENTLY_WITNESSED",
            "network_exchange_count_semantics" =>
                "SIX_DOWNLOADER_INVOCATIONS_ARE_A_CODE_PATH_CONTRACT_NOT_WITNESSED_NETWORK_EXCHANGES",
            "downloader_invocation_count" => length(objects),
            "attempted_network_exchange_count" =>
                "NOT_INDEPENDENTLY_WITNESSED",
            "completed_response_count" => length(objects),
            "validated_response_count" => length(objects),
            "failed_attempt_count" => 0,
            "persisted_transport_provenance_authenticated" => false,
            "network_exchange_count_externally_witnessed" => false,
            "operator_authorization_externally_authenticated" => false,
            "response_header_timestamp_semantics" =>
                "CONSERVATIVE_POST_BODY_RESPONSE_OBJECT_OBSERVATION",
        ),
        "operator_authorization" => operator_authorization,
        "objects" => [
            _object_record(object, specs[index])
                for (index, object) in enumerate(objects)
        ],
        "row_identity" => evaluation.row_identity,
        "storage" => Dict{String, Any}(
            "local_storage_receipt_file" =>
                "local-storage-receipt.toml",
            "local_storage_receipt_sha256" =>
                storage_receipt["artifact"]["receipt_sha256"],
            "two_local_copies_verified" => true,
            "durable_external_copy_count" => 0,
            "external_timestamp_verified" => false,
            "retention_through_2031_attested" => false,
            "raw_bytes_git_commit_authorized" => false,
        ),
        "result" => result,
        "blockers" => sort!(
            unique!(
                synthetic_fixture ?
                    [evaluation.blockers; SYNTHETIC_BLOCKER] :
                    copy(evaluation.blockers),
            ),
        ),
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
    manifest["artifact"]["manifest_sha256"] =
        _semantic_sha256(manifest, "artifact", "manifest_sha256")
    return manifest
end

function _install_bundle!(
        paths,
        authorization,
        specs,
        objects,
        storage_receipt,
        evaluation,
        bindings,
        operator_authorization,
        synthetic_fixture,
    )
    storage_bytes = _toml_bytes(storage_receipt)
    _write_triplicate(paths, "local-storage-receipt.toml", storage_bytes)
    receipt_files = _write_receipts(paths, evaluation.receipts)
    manifest = _build_manifest(
        paths,
        authorization,
        specs,
        objects,
        storage_receipt,
        evaluation,
        receipt_files,
        bindings,
        operator_authorization,
        synthetic_fixture,
    )
    manifest_bytes = _toml_bytes(manifest)
    _write_triplicate(paths, "capture-manifest.toml", manifest_bytes)
    load_and_validate_bundle(
        paths.journal_path;
        allow_synthetic_test_fixture = synthetic_fixture,
    )
    (ispath(paths.final_path) || islink(paths.final_path)) &&
        fail("atomic publish", "final path appeared before rename")
    mv(paths.journal_path, paths.final_path)
    _fsync_directory(paths.state_root)
    return load_and_validate_bundle(
        paths.final_path;
        allow_synthetic_test_fixture = synthetic_fixture,
    )
end

function _manifest_object(manifest, object_id)
    matches = [
        item for item in manifest["objects"] if
            item["object_id"] == object_id
    ]
    length(matches) == 1 ||
        fail("bundle", "expected exactly one $object_id object")
    return only(matches)
end

function _read_object(bundle, record)
    primary_rel = _safe_relative(record["primary_path"], "object primary path")
    replica_rel = _safe_relative(record["replica_path"], "object replica path")
    primary = _safe_file(joinpath(bundle, primary_rel), bundle)
    replica = _safe_file(joinpath(bundle, replica_rel), bundle)
    primary_bytes = read(primary)
    replica_bytes = read(replica)
    primary_bytes == replica_bytes ||
        fail("bundle", "raw replicas differ")
    length(primary_bytes) == record["raw_byte_count"] ||
        fail("bundle", "raw byte count differs")
    sha256_hex(primary_bytes) == record["raw_sha256"] ||
        fail("bundle", "raw SHA-256 differs")
    return primary_bytes
end

function _read_triplicate(bundle, relative_path)
    relative = _safe_relative(relative_path, "triplicate path")
    paths = (
        _safe_file(joinpath(bundle, relative), bundle),
        _safe_file(joinpath(bundle, "replica-a", relative), bundle),
        _safe_file(joinpath(bundle, "replica-b", relative), bundle),
    )
    bytes = read(first(paths))
    all(path -> read(path) == bytes, paths) ||
        fail("bundle", "triplicate bytes differ for $relative")
    return bytes
end

function _load_receipt(bundle, file, expected_sha256)
    file = _typed_string(file, "bundle receipt file")
    expected_sha256 =
        _typed_string(expected_sha256, "bundle receipt expected SHA-256")
    file == "NONE" && expected_sha256 == "NONE" && return nothing
    file == "NONE" && fail("bundle receipt", "file/hash presence differs")
    occursin(HASH_PATTERN, expected_sha256) ||
        fail("bundle receipt", "invalid expected receipt SHA-256")
    relative = joinpath("receipts", _safe_relative(file, "receipt file"))
    bytes = _read_triplicate(bundle, relative)
    receipt = _closed_table(
        TOML.parse(String(bytes)),
        (
            "schema_version",
            "receipt_id",
            "source",
            "observation",
            "request",
            "response",
            "artifact",
            "raw_fields",
            "classification",
            "governance",
            "lineage",
            "gates",
            "receipt_sha256",
        ),
        "bundle receipt",
    )
    _require_type_exact_equal(
        receipt["receipt_sha256"],
        expected_sha256,
        "bundle receipt.receipt_sha256",
    )
    ReceiptContract.validate_receipt(receipt, expected_sha256)
    return receipt
end

function _validate_storage(bundle, manifest)
    storage = _closed_table(
        manifest["storage"],
        (
            "local_storage_receipt_file",
            "local_storage_receipt_sha256",
            "two_local_copies_verified",
            "durable_external_copy_count",
            "external_timestamp_verified",
            "retention_through_2031_attested",
            "raw_bytes_git_commit_authorized",
        ),
        "bundle storage manifest",
    )
    storage_hash = _typed_hash(
        storage["local_storage_receipt_sha256"],
        "bundle storage manifest.local_storage_receipt_sha256",
    )
    expected_storage = Dict{String, Any}(
        "local_storage_receipt_file" =>
            "local-storage-receipt.toml",
        "local_storage_receipt_sha256" => storage_hash,
        "two_local_copies_verified" => true,
        "durable_external_copy_count" => 0,
        "external_timestamp_verified" => false,
        "retention_through_2031_attested" => false,
        "raw_bytes_git_commit_authorized" => false,
    )
    _require_type_exact_equal(
        storage,
        expected_storage,
        "bundle storage manifest",
    )
    bytes = _read_triplicate(
        bundle,
        storage["local_storage_receipt_file"],
    )
    receipt = _closed_table(
        TOML.parse(String(bytes)),
        (
            "artifact",
            "transaction_id",
            "publication_date",
            "effective_date",
            "copy_class",
            "objects",
            "durable_external_copy_count",
            "external_timestamp_verified",
            "retention_through_2031_attested",
            "gates",
        ),
        "bundle storage receipt",
    )
    artifact = _closed_table(
        receipt["artifact"],
        ("schema_version", "canonicalization", "receipt_sha256"),
        "bundle storage receipt artifact",
    )
    _require_type_exact_equal(
        artifact["schema_version"],
        STORAGE_SCHEMA,
        "bundle storage receipt artifact.schema_version",
    )
    _require_type_exact_equal(
        artifact["canonicalization"],
        STORAGE_CANONICALIZATION,
        "bundle storage receipt artifact.canonicalization",
    )
    digest = _semantic_sha256(receipt, "artifact", "receipt_sha256")
    _require_type_exact_equal(
        artifact["receipt_sha256"],
        digest,
        "bundle storage receipt artifact.receipt_sha256",
    )
    _require_type_exact_equal(
        digest,
        storage_hash,
        "bundle storage receipt manifest binding",
    )
    _typed_string(
        receipt["transaction_id"],
        "bundle storage receipt.transaction_id",
    )
    _typed_string(
        receipt["publication_date"],
        "bundle storage receipt.publication_date",
    )
    _typed_string(
        receipt["effective_date"],
        "bundle storage receipt.effective_date",
    )
    _typed_string(
        receipt["copy_class"],
        "bundle storage receipt.copy_class",
    )
    objects = receipt["objects"]
    objects isa Vector ||
        fail("bundle storage receipt.objects", "must be a Vector")
    length(objects) == 6 ||
        fail(
        "bundle storage receipt.objects",
        "must contain exactly six objects",
    )
    for (index, raw_record) in enumerate(objects)
        record = _closed_table(
            raw_record,
            ("object_id", "raw_sha256", "raw_byte_count"),
            "bundle storage receipt.objects[$index]",
        )
        _typed_string(
            record["object_id"],
            "bundle storage receipt.objects[$index].object_id",
        )
        _typed_hash(
            record["raw_sha256"],
            "bundle storage receipt.objects[$index].raw_sha256",
        )
        _typed_int(
            record["raw_byte_count"],
            "bundle storage receipt.objects[$index].raw_byte_count";
            minimum = 1,
        )
    end
    _typed_int(
        receipt["durable_external_copy_count"],
        "bundle storage receipt.durable_external_copy_count";
        minimum = 0,
    )
    _typed_bool(
        receipt["external_timestamp_verified"],
        "bundle storage receipt.external_timestamp_verified",
    )
    _typed_bool(
        receipt["retention_through_2031_attested"],
        "bundle storage receipt.retention_through_2031_attested",
    )
    _require_type_exact_equal(
        receipt["gates"],
        ALWAYS_FALSE_GATES,
        "bundle storage receipt.gates",
    )
    return receipt
end

function _derive_root(bundle)
    state_root = dirname(bundle)
    date_root = dirname(state_root)
    return dirname(date_root)
end

function _manifest_timestamp(value, location)
    text = _typed_string(value, location)
    occursin(
        r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$",
        text,
    ) || fail(location, "must be canonical millisecond UTC")
    parsed = try
        DateTime(chop(text; tail = 1), TIMESTAMP_FORMAT)
    catch
        fail(location, "is not a valid timestamp")
    end
    timestamp(parsed) == text ||
        fail(location, "must be canonical millisecond UTC")
    return parsed
end

function _validate_closed_manifest_constants(
        manifest,
        authorization,
        bindings,
        synthetic_fixture,
    )
    expected_campaign_id =
        synthetic_fixture ? SYNTHETIC_CAMPAIGN_ID : CAMPAIGN_ID
    transaction_id = authorization.transaction_id
    expected_artifact = Dict{String, Any}(
        "schema_version" => SCHEMA_VERSION,
        "manifest_id" =>
            "effr-recurring-restart-v4.$(authorization.publication_date).$(phase_state(authorization.phase)).$transaction_id",
        "canonicalization" => MANIFEST_CANONICALIZATION,
        "manifest_sha256" => manifest["artifact"]["manifest_sha256"],
    )
    _require_type_exact_equal(
        manifest["artifact"],
        expected_artifact,
        "bundle artifact",
    )
    expected_binding = Dict{String, Any}(
        "prospective_contract_id" => PROSPECTIVE_CONTRACT_ID,
        "prospective_contract_content_sha256" =>
            PROSPECTIVE_CONTRACT_CONTENT_SHA256,
        "prospective_contract_file_sha256" =>
            PROSPECTIVE_CONTRACT_FILE_SHA256,
        "prospective_contract_status" =>
            "DRAFT_UNAPPROVED_FAIL_CLOSED",
        "restart_schedule_id" => RESTART_SCHEDULE_ID,
        "restart_schedule_content_sha256" =>
            RESTART_SCHEDULE_CONTENT_SHA256,
        "restart_schedule_file_sha256" =>
            RESTART_SCHEDULE_FILE_SHA256,
        "restart_control_file_sha256" =>
            RESTART_CONTROL_FILE_SHA256,
        "recurring_v3_source_base_module_sha256" =>
            RECURRING_V3_MODULE_FILE_SHA256,
        "recurring_v3_source_base_cli_sha256" =>
            RECURRING_V3_CLI_FILE_SHA256,
        "recurring_v3_source_base_test_sha256" =>
            RECURRING_V3_TEST_FILE_SHA256,
        "recurring_v3_source_base_readme_sha256" =>
            RECURRING_V3_README_FILE_SHA256,
        "source_base_reuse_is_not_behavioral_attestation" => true,
        "accepted_schedule_runner_restart_binding_complete" => false,
        "operator_flag_does_not_relabel_schedule_binding_complete" => true,
        "receipt_contract_schema_version" =>
            ReceiptContract.SCHEMA_VERSION,
        "receipt_contract_file_sha256" =>
            RECEIPT_CONTRACT_FILE_SHA256,
        "observed_state_v3_contract_file_sha256" =>
            OBSERVED_STATE_CONTRACT_FILE_SHA256,
        "observed_state_v3_protocol_file_sha256" =>
            OBSERVED_STATE_PROTOCOL_FILE_SHA256,
        "observed_state_v3_protocol_content_sha256" =>
            OBSERVED_STATE_PROTOCOL_CONTENT_SHA256,
        "observed_state_v3_test_file_sha256" =>
            OBSERVED_STATE_TEST_FILE_SHA256,
        "observed_state_v3_readme_file_sha256" =>
            OBSERVED_STATE_README_FILE_SHA256,
        "observed_state_v3_role" =>
            "OFFLINE_ADJUDICATION_ONLY_NOT_ACQUISITION_AUTHORITY",
        "legacy_schedule_authorizes_restart_acquisition" => false,
        "raw_capture_status_is_observed_state_decision" => false,
        "acquisition_source_sha256" =>
            bindings.acquisition_source_sha256,
        "acquisition_cli_sha256" =>
            bindings.acquisition_cli_sha256,
    )
    _require_type_exact_equal(
        manifest["contract_binding"],
        expected_binding,
        "bundle contract binding",
    )
    expected_event = Dict{String, Any}(
        "campaign_id" => expected_campaign_id,
        "phase" => authorization.phase,
        "publication_date" => string(authorization.publication_date),
        "effective_date" => string(authorization.effective_date),
        "scheduled_time_utc" =>
            timestamp(authorization.window_start_utc),
        "capture_deadline_utc" =>
            timestamp(authorization.window_deadline_utc),
        "state_class_candidate" =>
            authorization.state_class_candidate,
        "publication_utc_offset" => "-04:00",
        "official_publication_day_validated" => false,
    )
    _require_type_exact_equal(
        manifest["event"],
        expected_event,
        "bundle event",
    )
    _require_type_exact_equal(
        manifest["gates"],
        ALWAYS_FALSE_GATES,
        "bundle gates",
    )
    return nothing
end

function _validate_restart_schedule_manifest(
        bundle,
        manifest,
        authorization,
        synthetic_fixture,
    )
    bindings = manifest["contract_binding"]
    _require_type_exact_equal(
        bindings["restart_schedule_id"],
        RESTART_SCHEDULE_ID,
        "bundle restart schedule id",
    )
    schedule = _source_bindings().schedule
    _require_type_exact_equal(
        schedule["policy"]["output_root"],
        RESTART_OUTPUT_ROOT_RELATIVE,
        "restart schedule output root",
    )
    _require_type_exact_equal(
        schedule["claim_ceiling"]["unchanged_revision_status"],
        UNCHANGED_ENDPOINT_CLAIM,
        "restart schedule unchanged claim",
    )
    _require_type_exact_equal(
        schedule["claim_ceiling"]["positive_claim"],
        POSITIVE_ENDPOINT_CLAIM,
        "restart schedule positive claim",
    )
    _require_type_exact_equal(
        schedule["operational_control"][
            "runner_restart_binding_complete",
        ],
        false,
        "accepted restart schedule historical runner-binding flag",
    )
    if !synthetic_fixture
        expected_bundle = normpath(
            joinpath(REPOSITORY_ROOT, authorization.bundle_path),
        )
        bundle == expected_bundle ||
            fail(
            "bundle restart schedule",
            "bundle path differs from the exact restart schedule path",
        )
    end
    manifest["result"]["status"] ==
        "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED" &&
        fail(
        "bundle restart result",
        "legacy unchanged alias is forbidden; raw acquisition must use the internal preservation status",
    )
    manifest["result"]["status"] == UNCHANGED_ENDPOINT_CLAIM &&
        fail(
        "bundle restart result",
        "observed-state-v3 claim is forbidden as a raw acquisition status",
    )
    return nothing
end

function _validate_capture_manifest(
        bundle,
        manifest,
        authorization,
        specs,
        synthetic_fixture,
    )
    root = _derive_root(bundle)
    canonical = _canonical_paths(
        root,
        authorization;
        synthetic_fixture,
    )
    bundle in (canonical.final_path, canonical.journal_path) ||
        fail("bundle path", "is not the canonical final or journal path")
    capture = _closed_table(
        manifest["capture"],
        (
            "transaction_id",
            "transport_policy",
            "transport_provenance",
            "transport_provenance_assertion_status",
            "synthetic_test_fixture",
            "request_order",
            "object_count",
            "network_exchange_count",
            "network_exchange_count_semantics",
            "downloader_invocation_count",
            "attempted_network_exchange_count",
            "completed_response_count",
            "validated_response_count",
            "failed_attempt_count",
            "persisted_transport_provenance_authenticated",
            "network_exchange_count_externally_witnessed",
            "operator_authorization_externally_authenticated",
            "response_header_timestamp_semantics",
        ),
        "bundle capture",
    )
    expected_order = [spec.object_id for spec in specs]
    expected_capture = Dict{String, Any}(
        "transaction_id" => canonical.transaction_id,
        "transport_policy" => synthetic_fixture ?
            SYNTHETIC_TRANSPORT_POLICY : BUILTIN_TRANSPORT_POLICY,
        "transport_provenance" => synthetic_fixture ?
            SYNTHETIC_TRANSPORT_PROVENANCE :
            BUILTIN_TRANSPORT_PROVENANCE,
        "transport_provenance_assertion_status" =>
            "LOCAL_UNAUTHENTICATED_RUNTIME_ASSERTION",
        "synthetic_test_fixture" => synthetic_fixture,
        "request_order" => expected_order,
        "object_count" => 6,
        "network_exchange_count" =>
            "NOT_INDEPENDENTLY_WITNESSED",
        "network_exchange_count_semantics" =>
            "SIX_DOWNLOADER_INVOCATIONS_ARE_A_CODE_PATH_CONTRACT_NOT_WITNESSED_NETWORK_EXCHANGES",
        "downloader_invocation_count" => 6,
        "attempted_network_exchange_count" =>
            "NOT_INDEPENDENTLY_WITNESSED",
        "completed_response_count" => 6,
        "validated_response_count" => 6,
        "failed_attempt_count" => 0,
        "persisted_transport_provenance_authenticated" => false,
        "network_exchange_count_externally_witnessed" => false,
        "operator_authorization_externally_authenticated" => false,
        "response_header_timestamp_semantics" =>
            "CONSERVATIVE_POST_BODY_RESPONSE_OBJECT_OBSERVATION",
    )
    _require_type_exact_equal(
        capture,
        expected_capture,
        "bundle capture",
    )
    objects = manifest["objects"]
    objects isa Vector ||
        fail("bundle objects", "must be a Vector")
    length(objects) == 6 ||
        fail("bundle objects", "must contain exactly six objects")
    observed_order = String[]
    for (index, (raw_record, spec)) in enumerate(zip(objects, specs))
        record = _closed_table(
            raw_record,
            (
                "object_id",
                "role",
                "canonical_query",
                "requested_url",
                "final_url",
                "http_method",
                "http_status",
                "content_type",
                "content_encoding",
                "redirect_count",
                "proxy_used",
                "raw_byte_count",
                "raw_sha256",
                "primary_path",
                "replica_path",
                "request_started_at_utc",
                "response_body_completed_at_utc",
                "response_metadata_observed_at_utc",
                "response_headers",
            ),
            "bundle object[$index]",
        )
        object_id = _typed_string(
            record["object_id"],
            "bundle object[$index].object_id",
        )
        push!(observed_order, object_id)
        for (field, expected) in (
                ("object_id", spec.object_id),
                ("role", spec.object_id),
                ("canonical_query", spec.canonical_query),
                ("requested_url", spec.requested_url),
                ("final_url", spec.requested_url),
                ("http_method", "GET"),
                ("http_status", 200),
                ("redirect_count", 0),
                ("proxy_used", false),
                ("content_encoding", "identity"),
            )
            _require_type_exact_equal(
                record[field],
                expected,
                "bundle object[$index].$field",
            )
        end
        content_type = _typed_string(
            record["content_type"],
            "bundle object[$index].content_type",
        )
        _media_type(content_type) in spec.media_types ||
            fail("bundle object", "media type differs")
        stored_headers = _validate_stored_headers(
            record["response_headers"],
            "bundle object response headers",
        )
        header_content_type =
            _response_header(stored_headers, "content-type")
        isempty(header_content_type) ||
            _media_type(header_content_type) ==
            _media_type(content_type) ||
            fail("bundle object", "stored content type differs")
        header_content_encoding =
            lowercase(_response_header(stored_headers, "content-encoding"))
        isempty(header_content_encoding) ||
            header_content_encoding == record["content_encoding"] ||
            fail("bundle object", "stored content encoding differs")
        started = _manifest_timestamp(
            record["request_started_at_utc"],
            "bundle object request start",
        )
        completed = _manifest_timestamp(
            record["response_body_completed_at_utc"],
            "bundle object body completion",
        )
        metadata = _manifest_timestamp(
            record["response_metadata_observed_at_utc"],
            "bundle object metadata observation",
        )
        authorization.window_start_utc <= started <= completed <=
            authorization.window_deadline_utc ||
            fail("bundle object", "timestamps are outside the window")
        metadata == completed ||
            fail("bundle object", "metadata timestamp is not conservative")
        _typed_int(
            record["raw_byte_count"],
            "bundle object[$index].raw_byte_count";
            minimum = 1,
        )
        digest = _typed_hash(
            record["raw_sha256"],
            "bundle object[$index].raw_sha256",
        )
        expected_name = "raw-sha256-$digest.$(spec.extension)"
        _require_type_exact_equal(
            record["primary_path"],
            "replica-a/$expected_name",
            "bundle object[$index].primary_path",
        )
        _require_type_exact_equal(
            record["replica_path"],
            "replica-b/$expected_name",
            "bundle object[$index].replica_path",
        )
    end
    observed_order == expected_order ||
        fail("bundle objects", "identity/order differs")
    return canonical
end

function _validate_storage_cross_bindings(
        storage_receipt,
        manifest,
        authorization,
    )
    capture = manifest["capture"]
    expected_objects = [
        Dict{String, Any}(
                "object_id" => record["object_id"],
                "raw_sha256" => record["raw_sha256"],
                "raw_byte_count" => record["raw_byte_count"],
            ) for record in manifest["objects"]
    ]
    expected = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => STORAGE_SCHEMA,
            "canonicalization" => STORAGE_CANONICALIZATION,
            "receipt_sha256" => repeat("0", 64),
        ),
        "transaction_id" => capture["transaction_id"],
        "publication_date" => string(authorization.publication_date),
        "effective_date" => string(authorization.effective_date),
        "copy_class" =>
            "TWO_LOCAL_INTEGRITY_REPLICAS_NOT_DURABLE_STORAGE",
        "objects" => expected_objects,
        "durable_external_copy_count" => 0,
        "external_timestamp_verified" => false,
        "retention_through_2031_attested" => false,
        "gates" => deepcopy(ALWAYS_FALSE_GATES),
    )
    expected["artifact"]["receipt_sha256"] =
        _semantic_sha256(expected, "artifact", "receipt_sha256")
    _require_type_exact_equal(
        storage_receipt,
        expected,
        "bundle storage receipt",
    )
    return nothing
end

function _validate_receipt_cross_bindings(
        receipt,
        raw_bytes,
        report_type,
        authorization,
    )
    receipt === nothing && return nothing
    receipt["artifact"]["raw_sha256"] == sha256_hex(raw_bytes) ||
        fail("bundle receipt", "$report_type raw SHA-256 differs")
    observation = receipt["observation"]
    observation["publication_date"] ==
        string(authorization.publication_date) ||
        fail("bundle receipt", "$report_type publication date differs")
    observation["effective_date"] == string(authorization.effective_date) ||
        fail("bundle receipt", "$report_type effective date differs")
    observation["report_type"] == report_type ||
        fail("bundle receipt", "$report_type report identity differs")
    return nothing
end

function _captured_response_from_manifest(record, body)
    return CapturedResponse(
        object_id = record["object_id"],
        body = copy(body),
        requested_url = record["requested_url"],
        final_url = record["final_url"],
        http_status = record["http_status"],
        content_type = record["content_type"],
        content_encoding = record["content_encoding"],
        redirect_count = record["redirect_count"],
        proxy_used = record["proxy_used"],
        response_headers = _validate_stored_headers(
            record["response_headers"],
            "reconstructed response headers",
        ),
        request_started_at_utc = _manifest_timestamp(
            record["request_started_at_utc"],
            "reconstructed request start",
        ),
        response_body_completed_at_utc = _manifest_timestamp(
            record["response_body_completed_at_utc"],
            "reconstructed body completion",
        ),
        response_metadata_observed_at_utc = _manifest_timestamp(
            record["response_metadata_observed_at_utc"],
            "reconstructed metadata observation",
        ),
    )
end

function _reconstruct_expected_receipts(
        manifest,
        authorization,
        rate,
        volume,
        object_bytes,
        storage_receipt,
        predecessor,
    )
    rate.current_state_present == volume.current_state_present ||
        fail(
        "receipt reconstruction",
        "rate and volume currentState presence differs",
    )
    rate.revision == volume.revision ||
        fail(
        "receipt reconstruction",
        "rate and volume revision tokens differ",
    )
    rate.footnote == volume.footnote ||
        fail(
        "receipt reconstruction",
        "rate and volume footnoteId presence/value differs",
    )
    state_class = if !rate.current_state_present
        nothing
    elseif authorization.phase == "first"
        rate.revision == "" ||
            fail(
            "receipt reconstruction",
            "first-state revision token is not empty",
        )
        "FIRST_0900_STATE"
    elseif rate.revision == "r"
        predecessor === nothing &&
            fail(
            "receipt reconstruction",
            "revision predecessor is absent",
        )
        "SAME_DAY_1430_REVISION"
    elseif rate.revision == ""
        nothing
    else
        fail("receipt reconstruction", "unknown revision token")
    end
    state_class === nothing &&
        return (rate = nothing, volume = nothing, pair = nothing)
    rate_record = _manifest_object(manifest, "rate_response")
    volume_record = _manifest_object(manifest, "volume_response")
    rate_object = _captured_response_from_manifest(
        rate_record,
        object_bytes["rate_response"],
    )
    volume_object = _captured_response_from_manifest(
        volume_record,
        object_bytes["volume_response"],
    )
    openapi_sha256 = sha256_hex(object_bytes["openapi_snapshot"])
    terms_sha256 = sha256_hex(object_bytes["terms_snapshot"])
    storage_sha256 =
        storage_receipt["artifact"]["receipt_sha256"]
    rate_predecessor = state_class == "SAME_DAY_1430_REVISION" ?
        predecessor.rate_receipt_sha256 : "NONE"
    volume_predecessor = state_class == "SAME_DAY_1430_REVISION" ?
        predecessor.volume_receipt_sha256 : "NONE"
    expected_rate = _build_receipt(
        rate_object,
        rate,
        "rate",
        state_class,
        authorization;
        openapi_sha256,
        terms_sha256,
        storage_receipt_sha256 = storage_sha256,
        predecessor = rate_predecessor,
    )
    expected_volume = _build_receipt(
        volume_object,
        volume,
        "volume",
        state_class,
        authorization;
        openapi_sha256,
        terms_sha256,
        storage_receipt_sha256 = storage_sha256,
        predecessor = volume_predecessor,
    )
    expected_pair = ReceiptContract.pair_receipts(
        expected_rate,
        expected_rate["receipt_sha256"],
        expected_volume,
        expected_volume["receipt_sha256"],
    )
    return (
        rate = expected_rate,
        volume = expected_volume,
        pair = expected_pair,
    )
end

function _validate_reconstructed_receipt(actual, expected, report_type)
    if expected === nothing
        actual === nothing ||
            fail(
            "bundle reconstructed $report_type receipt",
            "unexpected receipt exists",
        )
        return nothing
    end
    actual === nothing &&
        fail(
        "bundle reconstructed $report_type receipt",
        "expected receipt is absent",
    )
    actual_content = deepcopy(actual)
    expected_content = deepcopy(expected)
    pop!(actual_content, "receipt_sha256", nothing)
    pop!(expected_content, "receipt_sha256", nothing)
    _require_type_exact_equal(
        actual_content,
        expected_content,
        "bundle reconstructed $report_type receipt",
    )
    _require_type_exact_equal(
        actual["receipt_sha256"],
        expected["receipt_sha256"],
        "bundle reconstructed $report_type receipt.receipt_sha256",
    )
    return nothing
end

function _load_predecessor(
        path,
        publication_date,
        effective_date;
        allow_synthetic_test_fixture = false,
    )
    validated = load_and_validate_bundle(
        path;
        validate_predecessor = false,
        allow_synthetic_test_fixture,
    )
    event = validated.manifest["event"]
    event["phase"] == "first" ||
        fail("predecessor", "must be a first-state bundle")
    event["publication_date"] == string(publication_date) ||
        fail("predecessor", "publication date differs")
    event["effective_date"] == string(effective_date) ||
        fail("predecessor", "effective date differs")
    status = validated.manifest["result"]["status"]
    status in (
        "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE",
        "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE",
    ) || fail("predecessor", "status is not a first-state outcome")
    return (
        bundle_path = validated.bundle_path,
        manifest_sha256 =
            validated.manifest["artifact"]["manifest_sha256"],
        rate_bytes = validated.rate_bytes,
        volume_bytes = validated.volume_bytes,
        rate_raw_sha256 = sha256_hex(validated.rate_bytes),
        volume_raw_sha256 = sha256_hex(validated.volume_bytes),
        rate_receipt_sha256 =
            validated.manifest["result"]["rate_receipt_sha256"],
        volume_receipt_sha256 =
            validated.manifest["result"]["volume_receipt_sha256"],
    )
end

function _expected_receipt_fields!(expected, rate_receipt, volume_receipt)
    rate_receipt === nothing &&
        fail("bundle result", "expected a rate receipt")
    volume_receipt === nothing &&
        fail("bundle result", "expected a volume receipt")
    rate_hash = rate_receipt["receipt_sha256"]
    volume_hash = volume_receipt["receipt_sha256"]
    expected["rate_receipt_file"] =
        "rate-receipt-sha256-$rate_hash.toml"
    expected["volume_receipt_file"] =
        "volume-receipt-sha256-$volume_hash.toml"
    expected["rate_receipt_sha256"] = rate_hash
    expected["volume_receipt_sha256"] = volume_hash
    return nothing
end

function _validate_closed_result(
        manifest,
        authorization,
        rate,
        volume,
        rate_bytes,
        volume_bytes,
        rate_receipt,
        volume_receipt,
        pair,
        predecessor,
        synthetic_fixture,
    )
    rate.revision == volume.revision ||
        fail("bundle transition", "rate and volume revision tokens differ")
    rate.footnote == volume.footnote ||
        fail(
        "bundle transition",
        "rate and volume footnoteId presence/value differs",
    )
    rate.current_state_present == volume.current_state_present ||
        fail(
        "bundle transition",
        "rate and volume currentState presence differs",
    )
    expected = _result_template()
    expected["success"] = true
    expected["raw_capture_complete"] = true
    expected["failure_code"] = "NONE"
    expected["failure_detail"] = "NONE"
    if authorization.phase == "first"
        rate.revision == "" ||
            fail("bundle transition", "first-state token must be empty")
        if rate.current_state_present
            expected["status"] =
                "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
            expected["pair_status"] =
                "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT"
            expected["one_date_receipt_validated"] = true
            _expected_receipt_fields!(
                expected,
                rate_receipt,
                volume_receipt,
            )
        else
            expected["status"] =
                "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
            expected["failure_code"] = CURRENT_STATE_BLOCKER
            expected["failure_detail"] =
                "Raw EFFR rows omit currentState; no value was derived and no receipt was created."
            expected["pair_status"] =
                "NOT_CREATED_RAW_CURRENT_STATE_FIELD_ABSENT"
        end
    else
        predecessor === nothing &&
            fail("bundle transition", "validated predecessor is required")
        _predecessor_fields!(expected, predecessor)
        rate_equal = rate_bytes == predecessor.rate_bytes
        volume_equal = volume_bytes == predecessor.volume_bytes
        expected["byte_equality_rate"] = rate_equal
        expected["byte_equality_volume"] = volume_equal
        if rate.revision == ""
            rate_equal && volume_equal ||
                fail("bundle transition", "changed empty-token bytes")
            expected["status"] = RAW_UNCHANGED_PRESERVATION_STATUS
            expected["pair_status"] = "NOT_APPLICABLE_NO_REVISION"
        elseif rate.revision == "r"
            (!rate_equal || !volume_equal) ||
                fail("bundle transition", "unchanged closed-token bytes")
            expected["revision_observed"] = true
            if rate.current_state_present
                expected["status"] =
                    "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE"
                expected["pair_status"] =
                    "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT"
                expected["revision_receipt_created"] = true
                expected["one_date_receipt_validated"] = true
                _expected_receipt_fields!(
                    expected,
                    rate_receipt,
                    volume_receipt,
                )
            else
                expected["status"] =
                    "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
                expected["failure_code"] = CURRENT_STATE_BLOCKER
                expected["failure_detail"] =
                    "Raw EFFR rows omit currentState; no value was derived and no receipt was created."
                expected["pair_status"] =
                    "NOT_CREATED_RAW_CURRENT_STATE_FIELD_ABSENT"
            end
        else
            fail("bundle transition", "unknown revision token")
        end
    end
    _require_type_exact_equal(
        manifest["result"],
        expected,
        "bundle result",
    )
    receipt_expected = expected["rate_receipt_sha256"] != "NONE"
    receipt_expected == (rate_receipt !== nothing) ||
        fail("bundle result", "receipt presence differs from closed result")
    if receipt_expected
        pair === nothing &&
            fail("bundle result", "validated receipt pair is absent")
        pair.pair_status == expected["pair_status"] ||
            fail("bundle result", "receipt pair status differs")
    else
        pair === nothing ||
            fail("bundle result", "unexpected receipt pair")
    end
    expected_blockers = copy(BASE_BLOCKERS)
    !rate.current_state_present &&
        push!(expected_blockers, CURRENT_STATE_BLOCKER)
    synthetic_fixture &&
        push!(expected_blockers, SYNTHETIC_BLOCKER)
    sort!(unique!(expected_blockers))
    _require_type_exact_equal(
        manifest["blockers"],
        expected_blockers,
        "bundle blockers",
    )
    return nothing
end

function _load_and_validate_bundle_impl(
        bundle_path;
        validate_predecessor = true,
        allow_synthetic_test_fixture = false,
    )
    validate_predecessor = _typed_bool(
        validate_predecessor,
        "loader validate_predecessor",
    )
    allow_synthetic_test_fixture = _typed_bool(
        allow_synthetic_test_fixture,
        "loader allow_synthetic_test_fixture",
    )
    bindings = _source_bindings()
    requested_bundle = abspath(
        _typed_string(bundle_path, "bundle path"),
    )
    isdir(requested_bundle) ||
        fail("bundle", "not a directory: $requested_bundle")
    bundle = _reject_symlink_components(
        requested_bundle,
        "bundle";
        require_leaf = true,
    )
    _reject_bundle_tree_symlinks(bundle)
    manifest_bytes =
        _read_triplicate(bundle, "capture-manifest.toml")
    manifest = _closed_table(
        TOML.parse(String(manifest_bytes)),
        (
            "artifact",
            "contract_binding",
            "event",
            "capture",
            "operator_authorization",
            "objects",
            "row_identity",
            "storage",
            "result",
            "blockers",
            "gates",
        ),
        "bundle manifest",
    )
    artifact = _closed_table(
        manifest["artifact"],
        (
            "schema_version",
            "manifest_id",
            "canonicalization",
            "manifest_sha256",
        ),
        "bundle artifact",
    )
    _require_type_exact_equal(
        artifact["schema_version"],
        SCHEMA_VERSION,
        "bundle artifact.schema_version",
    )
    manifest_hash = _typed_hash(
        artifact["manifest_sha256"],
        "bundle artifact.manifest_sha256",
    )
    digest = _semantic_sha256(
        manifest,
        "artifact",
        "manifest_sha256",
    )
    _require_type_exact_equal(
        manifest_hash,
        digest,
        "bundle artifact.manifest_sha256",
    )
    event = _closed_table(
        manifest["event"],
        (
            "campaign_id",
            "phase",
            "publication_date",
            "effective_date",
            "scheduled_time_utc",
            "capture_deadline_utc",
            "state_class_candidate",
            "publication_utc_offset",
            "official_publication_day_validated",
        ),
        "bundle event",
    )
    authorization = _authorization(
        bindings.schedule,
        event["publication_date"],
        event["phase"],
    )
    capture = _expect_dict(manifest["capture"], "bundle capture")
    haskey(capture, "synthetic_test_fixture") ||
        fail("bundle capture", "missing synthetic fixture marker")
    synthetic_fixture = _typed_bool(
        capture["synthetic_test_fixture"],
        "bundle capture.synthetic_test_fixture",
    )
    synthetic_fixture && !allow_synthetic_test_fixture &&
        fail(
        "bundle synthetic fixture",
        "default loader rejects synthetic test fixtures",
    )
    authorization.phase == "revision-check" && !validate_predecessor &&
        fail(
        "bundle predecessor",
        "revision validation cannot bypass its predecessor",
    )
    _validate_closed_manifest_constants(
        manifest,
        authorization,
        bindings,
        synthetic_fixture,
    )
    operator = manifest["operator_authorization"]
    _require_type_exact_equal(
        operator,
        _operator_authorization(
            authorization,
            true;
            synthetic_fixture,
        ),
        "bundle operator authorization",
    )
    specs = _request_specs(authorization)
    canonical = _validate_capture_manifest(
        bundle,
        manifest,
        authorization,
        specs,
        synthetic_fixture,
    )
    result = _validate_result_shape(manifest["result"])
    storage_receipt = _validate_storage(bundle, manifest)
    _validate_restart_schedule_manifest(
        bundle,
        manifest,
        authorization,
        synthetic_fixture,
    )
    object_bytes = Dict{String, Vector{UInt8}}()
    for record in manifest["objects"]
        object_bytes[record["object_id"]] =
            _read_object(bundle, record)
    end
    rate_bytes = object_bytes["rate_response"]
    volume_bytes = object_bytes["volume_response"]
    _validate_storage_cross_bindings(
        storage_receipt,
        manifest,
        authorization,
    )
    rate_receipt = _load_receipt(
        bundle,
        result["rate_receipt_file"],
        result["rate_receipt_sha256"],
    )
    volume_receipt = _load_receipt(
        bundle,
        result["volume_receipt_file"],
        result["volume_receipt_sha256"],
    )
    _validate_receipt_cross_bindings(
        rate_receipt,
        rate_bytes,
        "rate",
        authorization,
    )
    _validate_receipt_cross_bindings(
        volume_receipt,
        volume_bytes,
        "volume",
        authorization,
    )
    rate = _select_effr_row(rate_bytes, "rate", authorization.effective_date)
    volume =
        _select_effr_row(volume_bytes, "volume", authorization.effective_date)
    _require_type_exact_equal(
        manifest["row_identity"],
        [
            _identity_record("rate", rate),
            _identity_record("volume", volume),
        ],
        "bundle row identity",
    )
    rate.revision == volume.revision ||
        fail("bundle transition", "rate and volume revision tokens differ")
    rate.footnote == volume.footnote ||
        fail(
        "bundle transition",
        "rate and volume footnoteId presence/value differs",
    )
    rate.current_state_present == volume.current_state_present ||
        fail(
        "bundle transition",
        "rate and volume currentState presence differs",
    )
    predecessor = nothing
    if authorization.phase == "revision-check" && validate_predecessor
        _require_type_exact_equal(
            result["predecessor_bundle"],
            canonical.predecessor_path,
            "bundle predecessor path",
        )
        predecessor = _load_predecessor(
            canonical.predecessor_path,
            authorization.publication_date,
            authorization.effective_date,
            allow_synthetic_test_fixture =
                synthetic_fixture,
        )
        for (field, expected) in (
                (
                    "predecessor_manifest_sha256",
                    predecessor.manifest_sha256,
                ),
                (
                    "predecessor_rate_raw_sha256",
                    predecessor.rate_raw_sha256,
                ),
                (
                    "predecessor_volume_raw_sha256",
                    predecessor.volume_raw_sha256,
                ),
                (
                    "predecessor_rate_receipt_sha256",
                    predecessor.rate_receipt_sha256,
                ),
                (
                    "predecessor_volume_receipt_sha256",
                    predecessor.volume_receipt_sha256,
                ),
            )
            _require_type_exact_equal(
                result[field],
                expected,
                "bundle predecessor.$field",
            )
        end
    end
    reconstructed = _reconstruct_expected_receipts(
        manifest,
        authorization,
        rate,
        volume,
        object_bytes,
        storage_receipt,
        predecessor,
    )
    _validate_reconstructed_receipt(
        rate_receipt,
        reconstructed.rate,
        "rate",
    )
    _validate_reconstructed_receipt(
        volume_receipt,
        reconstructed.volume,
        "volume",
    )
    pair = if rate_receipt === nothing
        volume_receipt === nothing ||
            fail("bundle", "receipt presence differs")
        nothing
    else
        volume_receipt === nothing &&
            fail("bundle", "receipt presence differs")
        ReceiptContract.pair_receipts(
            rate_receipt,
            rate_receipt["receipt_sha256"],
            volume_receipt,
            volume_receipt["receipt_sha256"],
        )
    end
    _validate_closed_result(
        manifest,
        authorization,
        rate,
        volume,
        rate_bytes,
        volume_bytes,
        reconstructed.rate,
        reconstructed.volume,
        reconstructed.pair,
        predecessor,
        synthetic_fixture,
    )
    return (;
        bundle_path = bundle,
        manifest,
        rate_bytes,
        volume_bytes,
        rate_receipt,
        volume_receipt,
        pair,
    )
end

function load_and_validate_bundle(args...; kwargs...)
    try
        return _load_and_validate_bundle_impl(args...; kwargs...)
    catch error
        error isa InterruptException && rethrow()
        error isa RestartRecurringAcquisitionError && rethrow()
        fail(
            "bundle validation",
            "$(typeof(error)): $(sprint(showerror, error))",
        )
    end
end

function _observed_headers(record)
    stored = _validate_stored_headers(
        record["response_headers"],
        "observed-state-v3 reconstructed response headers",
    )
    pairs = Pair{String, String}[]
    for (index, item) in enumerate(stored)
        parts = split(item, ':'; limit = 2)
        length(parts) == 2 ||
            fail(
            "observed-state-v3 response headers[$index]",
            "missing field-name separator",
        )
        push!(pairs, parts[1] => strip(parts[2]))
    end
    return pairs
end

function _observed_captured_report(validated, report_type)
    report_type in ("rate", "volume") ||
        fail("observed-state-v3 report", "unknown report type")
    object_id = "$(report_type)_response"
    record = _manifest_object(validated.manifest, object_id)
    body = report_type == "rate" ?
        validated.rate_bytes : validated.volume_bytes
    return ObservedStateContract.CapturedReport(
        report_type = report_type,
        body = copy(body),
        canonical_query = record["canonical_query"],
        requested_url = record["requested_url"],
        final_url = record["final_url"],
        http_status = record["http_status"],
        redirect_count = record["redirect_count"],
        response_headers = _observed_headers(record),
        request_started_at_utc = _manifest_timestamp(
            record["request_started_at_utc"],
            "observed-state-v3 reconstructed request start",
        ),
        response_body_completed_at_utc = _manifest_timestamp(
            record["response_body_completed_at_utc"],
            "observed-state-v3 reconstructed body completion",
        ),
        response_metadata_observed_at_utc = _manifest_timestamp(
            record["response_metadata_observed_at_utc"],
            "observed-state-v3 reconstructed metadata observation",
        ),
    )
end

function _restart_observation(validated, observation_class)
    event = validated.manifest["event"]
    return ObservedStateContract.validate_endpoint_observation(
        _observed_captured_report(validated, "rate"),
        _observed_captured_report(validated, "volume");
        observation_class,
        publication_date = _publication_date(event["publication_date"]),
        effective_date = _publication_date(event["effective_date"]),
    )
end

function _evaluation_blockers(morning_manifest, revision_manifest, decision)
    blockers = String[]
    append!(blockers, String.(morning_manifest["blockers"]))
    append!(blockers, String.(revision_manifest["blockers"]))
    if decision === nothing
        push!(blockers, "OBSERVED_STATE_V3_DECISION_BINDING_REQUIRED")
    else
        append!(blockers, String.(decision["blockers"]))
    end
    push!(
        blockers,
        "PINNED_LEGACY_SCHEDULE_USED_ONLY_BY_OFFLINE_OBSERVED_STATE_V3_ADJUDICATOR",
    )
    push!(
        blockers,
        "DECISION_BINDING_PROVENANCE_NOT_AUTHENTICATED_BY_RESTART_RUNNER",
    )
    return sort!(unique!(blockers))
end

function _evaluate_restart_result_impl(
        bundle_path;
        decision_binding = nothing,
        allow_synthetic_test_fixture = false,
    )
    revision = load_and_validate_bundle(
        bundle_path;
        allow_synthetic_test_fixture,
    )
    revision_event = revision.manifest["event"]
    revision_event["phase"] == "revision-check" ||
        fail(
        "restart result evaluation",
        "requires the restart revision-check bundle and its exact morning predecessor",
    )
    predecessor_path = revision.manifest["result"]["predecessor_bundle"]
    morning = load_and_validate_bundle(
        predecessor_path;
        allow_synthetic_test_fixture,
    )
    morning_event = morning.manifest["event"]
    morning_event["phase"] == "first" ||
        fail("restart result evaluation", "predecessor is not morning phase")
    for field in ("publication_date", "effective_date")
        morning_event[field] == revision_event[field] ||
            fail(
            "restart result evaluation",
            "morning and revision $field differ",
        )
    end
    synthetic_fixture = revision.manifest["capture"]["synthetic_test_fixture"]
    morning.manifest["capture"]["synthetic_test_fixture"] ===
        synthetic_fixture ||
        fail(
        "restart result evaluation",
        "morning and revision synthetic-fixture markers differ",
    )
    morning_observation = _restart_observation(
        morning,
        ObservedStateContract.MORNING_WINDOW_ENDPOINT_OBSERVATION,
    )
    revision_observation = _restart_observation(
        revision,
        ObservedStateContract.POST_REVISION_WINDOW_ENDPOINT_OBSERVATION,
    )
    protocol = ObservedStateContract.load_protocol()
    protocol_hash =
        ObservedStateContract.protocol_semantic_sha256(protocol)
    protocol_hash == OBSERVED_STATE_PROTOCOL_CONTENT_SHA256 ||
        fail(
        "observed-state-v3 protocol",
        "semantic digest differs from the restart evaluator pin",
    )
    decision = if decision_binding === nothing
        nothing
    else
        decision_binding isa RestartDecisionBinding ||
            fail(
            "restart result evaluation decision binding",
            "must be RestartDecisionBinding or nothing",
        )
        ObservedStateContract.adjudicate_transition(
            morning_observation,
            revision_observation,
            decision_binding,
        )
    end
    outcome = decision === nothing ?
        "NOT_ADJUDICATED_DECISION_BINDING_REQUIRED" :
        decision["decision"]["outcome"]
    claim = decision === nothing ?
        "NOT_ADJUDICATED" : decision["decision"]["claim"]
    unchanged = outcome == UNCHANGED_ENDPOINT_CLAIM
    unchanged && claim != UNCHANGED_ENDPOINT_CLAIM &&
        fail(
        "observed-state-v3 decision",
        "exact unchanged outcome and claim differ",
    )
    unchanged && decision === nothing &&
        fail(
        "observed-state-v3 decision",
        "unchanged claim cannot be selected without adjudication",
    )
    decision_gates = decision === nothing ?
        deepcopy(ALWAYS_FALSE_GATES) : deepcopy(decision["gates"])
    all(value === false for value in values(decision_gates)) ||
        fail("observed-state-v3 decision", "a decision gate is true")
    return (;
        schema_version =
            "beforeit-us-effr-recurring-restart-result-evaluation.v4",
        bundle_validated = true,
        morning_bundle_validated = true,
        bundle_path = revision.bundle_path,
        manifest_sha256 =
            revision.manifest["artifact"]["manifest_sha256"],
        morning_bundle_path = morning.bundle_path,
        morning_manifest_sha256 =
            morning.manifest["artifact"]["manifest_sha256"],
        restart_schedule_id = RESTART_SCHEDULE_ID,
        restart_schedule_content_sha256 =
            RESTART_SCHEDULE_CONTENT_SHA256,
        observed_state_contract_file_sha256 =
            OBSERVED_STATE_CONTRACT_FILE_SHA256,
        observed_state_protocol_file_sha256 =
            OBSERVED_STATE_PROTOCOL_FILE_SHA256,
        observed_state_protocol_content_sha256 = protocol_hash,
        observed_state_role =
            "OFFLINE_ADJUDICATION_ONLY_NOT_ACQUISITION_AUTHORITY",
        legacy_schedule_authorizes_restart_acquisition = false,
        campaign_id = revision_event["campaign_id"],
        publication_date = revision_event["publication_date"],
        effective_date = revision_event["effective_date"],
        phase = revision_event["phase"],
        result_status = revision.manifest["result"]["status"],
        raw_capture_status_is_observed_state_decision = false,
        synthetic_test_fixture = synthetic_fixture,
        synthetic_fixture_permanently_nonempirical = synthetic_fixture,
        raw_capture_complete =
            revision.manifest["result"]["raw_capture_complete"],
        morning_observation_sha256 =
            morning_observation.observation_sha256,
        revision_observation_sha256 =
            revision_observation.observation_sha256,
        adjudication_status = decision === nothing ?
            "DECISION_BINDING_REQUIRED" : "OBSERVED_STATE_V3_ADJUDICATED",
        observed_state_outcome = outcome,
        endpoint_state_claim = claim,
        exact_unchanged_claim_selected = unchanged,
        observed_state_decision =
            decision === nothing ? nothing : deepcopy(decision),
        no_later_same_day_revision_claimed = false,
        final_state_for_day_claimed = false,
        publisher_authentication_established = false,
        decision_binding_provenance_authenticated = false,
        empirical_evidence_allowed = false,
        origin_admissible = false,
        accuracy_evaluation_allowed = false,
        production_scoring_allowed = false,
        promotion_eligible = false,
        morning_row_identity = deepcopy(morning.manifest["row_identity"]),
        row_identity = deepcopy(revision.manifest["row_identity"]),
        blockers = _evaluation_blockers(
            morning.manifest,
            revision.manifest,
            decision,
        ),
        gates = decision_gates,
    )
end

function evaluate_restart_result(args...; kwargs...)
    try
        return _evaluate_restart_result_impl(args...; kwargs...)
    catch error
        error isa InterruptException && rethrow()
        error isa RestartRecurringAcquisitionError && rethrow()
        if error isa ObservedStateContract.ObservedStateContractError
            fail(
                "observed-state-v3 offline adjudication",
                sprint(showerror, error),
            )
        end
        fail(
            "restart result evaluation",
            "$(typeof(error)): $(sprint(showerror, error))",
        )
    end
end

function acquire_restart_recurring(
        publication_date,
        phase;
        output_root = RESTART_OUTPUT_ROOT,
        execute_live = false,
        downloader = nothing,
        clock = nothing,
        synthetic_test_fixture = false,
    )
    if !execute_live
        downloader === nothing ||
            fail("dry run", "cannot accept an injected downloader")
        clock === nothing ||
            fail("dry run", "cannot accept an injected clock")
        synthetic_test_fixture &&
            fail("dry run", "cannot create a synthetic fixture")
        return dry_run_plan(publication_date, phase; output_root)
    end
    injected = downloader !== nothing || clock !== nothing
    injected == synthetic_test_fixture ||
        fail(
        "transport provenance",
        "injected downloader/clock requires synthetic_test_fixture=true",
    )
    if synthetic_test_fixture
        downloader !== nothing ||
            fail("synthetic fixture", "requires an injected downloader")
        clock !== nothing ||
            fail("synthetic fixture", "requires an injected clock")
    end
    active_clock = synthetic_test_fixture ? clock : () -> now(UTC)
    bindings = _source_bindings()
    date = _publication_date(publication_date)
    selected_phase = _phase(phase)
    observed = active_clock()
    observed isa DateTime ||
        fail("clock", "must return UTC DateTime values")
    authorization = _authorization(
        bindings.schedule,
        date,
        selected_phase;
        observed,
    )
    operator_authorization = _operator_authorization(
        authorization,
        true;
        synthetic_fixture = synthetic_test_fixture,
    )
    canonical = _canonical_paths(
        output_root,
        authorization;
        synthetic_fixture = synthetic_test_fixture,
    )
    predecessor = if selected_phase == "revision-check"
        _load_predecessor(
            canonical.predecessor_path,
            authorization.publication_date,
            authorization.effective_date,
            allow_synthetic_test_fixture =
                synthetic_test_fixture,
        )
    else
        nothing
    end
    paths = _preflight(
        output_root,
        authorization;
        synthetic_fixture = synthetic_test_fixture,
    )
    specs = _request_specs(authorization)
    selected_downloader = synthetic_test_fixture ?
        downloader : _live_downloader
    current_object = "NONE"
    current_index = 0
    current_request_started_at = nothing
    current_downloader_invoked = false
    try
        objects = CapturedResponse[]
        for (index, spec) in enumerate(specs)
            current_object = spec.object_id
            current_index = index
            current_request_started_at = nothing
            current_downloader_invoked = false
            prepared = active_clock()
            _validate_request_start(prepared, authorization)
            _write_attempt_event(
                paths,
                index,
                spec,
                "prepared",
                Dict{String, Any}(
                    "pre_request_journaled_at_utc" => timestamp(prepared),
                    "request_start_pending" => true,
                    "written_before_request" => true,
                ),
            )
            started = active_clock()
            _validate_request_start(started, authorization)
            current_request_started_at = started
            current_downloader_invoked = true
            response = selected_downloader(spec)
            body = _returned_body(response)
            preserved = _preserve_raw(paths, spec, body)
            completed = active_clock()
            completed isa DateTime ||
                fail("clock", "must return UTC DateTime values")
            object = _normalize_download(
                response,
                spec,
                started,
                completed,
                body,
            )
            _write_attempt_event(
                paths,
                index,
                spec,
                "completed",
                Dict{String, Any}(
                    "request_started_at_utc" => timestamp(started),
                    "response_body_completed_at_utc" => timestamp(completed),
                    "http_status" => object.http_status,
                    "final_url" => object.final_url,
                    "raw_byte_count" => length(object.body),
                    "raw_sha256" => preserved.digest,
                    "primary_path" => preserved.primary_path,
                    "replica_path" => preserved.replica_path,
                    "body_preserved_before_validation" => true,
                ),
            )
            _validate_transport(object, spec, authorization)
            _write_attempt_event(
                paths,
                index,
                spec,
                "validated",
                Dict{String, Any}(
                    "response_validation_passed" => true,
                    "raw_sha256" => preserved.digest,
                ),
            )
            push!(objects, object)
        end
        storage_receipt =
            _storage_receipt(paths, objects, authorization)
        evaluation = _evaluate_capture(
            paths,
            authorization,
            objects,
            storage_receipt["artifact"]["receipt_sha256"],
            predecessor,
        )
        return _install_bundle!(
            paths,
            authorization,
            specs,
            objects,
            storage_receipt,
            evaluation,
            bindings,
            operator_authorization,
            synthetic_test_fixture,
        )
    catch error
        _record_failure(
            paths,
            error,
            current_object,
            current_index;
            request_started_at = current_request_started_at,
            downloader_invoked = current_downloader_invoked,
        )
        rethrow()
    end
end

end
