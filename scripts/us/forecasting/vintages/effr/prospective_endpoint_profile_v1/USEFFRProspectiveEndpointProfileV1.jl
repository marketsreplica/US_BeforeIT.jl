module USEFFRProspectiveEndpointProfileV1

using Dates
using SHA
using TOML

export ProfileError,
    PROFILE_PATH,
    compile_current_result,
    profile_semantic_sha256,
    validate_current_result,
    validate_profile,
    validate_profile_document

const PROFILE_PATH =
    joinpath(@__DIR__, "effr_prospective_endpoint_profile_v1.toml")
const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."))
const PROFILE_SCHEMA = "beforeit-us-effr-prospective-endpoint-profile.v1"
const CONTRACT_ID =
    "beforeit-us-effr-pre-origin-observed-endpoint-model-input.v1"
const CANONICALIZATION =
    "sorted-typed-length-aware-excluding-artifact-content-sha256.v1"
const CURRENT_STATUS = "CANNOT_RUN"
const READY_STATUS = "READY_FOR_MODEL_INPUT_PROFILE_SEAL_NO_TRUTH_LOADED"
const ESTIMAND_ID = "PRE_ORIGIN_OBSERVED_ENDPOINT_VINTAGE"
const CLAIM_CEILING =
    "MARKETS_API_EFFR_ENDPOINT_STATE_OBSERVED_AS_OF_CAPTURE_TIME_ONLY"
const ORIGIN_TIMESTAMP = "2026-10-30T14:00:00Z"
const MATHEMATICAL_RETENTION_MINIMUM = "2034-09-30T23:59:59Z"
const CONSERVATIVE_RETENTION_CUSHION = "2034-10-30T14:00:00Z"
const EXPECTED_PROFILE_PHYSICAL_SHA256 =
    "7de8e23e11d202a887e20d6e90616501562c9c3682db1200c753bb207ae4451b"
const EXPECTED_PROFILE_SEMANTIC_SHA256 =
    "4ed9a0f99c6c8490da35c290ce87c6051a6a1bf08da5eb2ee8ac601f75a4eaa5"
const EXPECTED_CURRENT_RESULT_SHA256 =
    "35c422d6483cabfe17df0f3aac58ef1139573c78ef5d4b9ae5fc5de94ec732a4"

const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
const TIMESTAMP_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"

const TOP_LEVEL_KEYS = Set(
    [
        "approval",
        "artifact",
        "contract",
        "coverage",
        "current_evidence",
        "estimand",
        "gates",
        "lineage",
        "methodology",
        "origin",
        "parent_supersession",
        "predecessor_missingness",
        "prohibited_actions",
        "required_conditions",
        "retention",
        "source_semantics",
        "sources",
    ],
)

const FALSE_GATE_KEYS = Set(
    [
        "accuracy_evaluation_allowed",
        "forecast_emission_allowed",
        "model_input_profile_ready",
        "origin_admissible",
        "production_use_allowed",
        "promotion_eligible",
        "scoring_allowed",
        "source_inventory_mutation_allowed",
        "truth_access_allowed",
    ],
)

const SECTION_SCHEMA_PINS = Dict(
    "approval" => (
        key_count = 8,
        keyset_sha256 = "75b0dfd6a31f7e1a990070c92132fb4aa826da2161a65e2893ddac45a9df24cc",
    ),
    "artifact" => (
        key_count = 5,
        keyset_sha256 = "73849697a5c4aef5dc20ba5b73d3a5637733080a469cffaec3b427d37bbcdad1",
    ),
    "contract" => (
        key_count = 15,
        keyset_sha256 = "8c888ed9a8cdae15e62f7c0afc74abf5474e494560336a6689e2e3faf44ee5a0",
    ),
    "coverage" => (
        key_count = 40,
        keyset_sha256 = "6fa8778b2293505d9542aa35b331a392dd3d17258d0b9ea9d53c8d73a8954f0b",
    ),
    "current_evidence" => (
        key_count = 27,
        keyset_sha256 = "a0dba22ef22a413af0e7414a8a187ee77a0ddd97048f0203ad85e7671967e8b2",
    ),
    "estimand" => (
        key_count = 21,
        keyset_sha256 = "7b42b4a752a818d0b11a41acb479c585e25a560548785c8e06a8b0c1f90793d2",
    ),
    "gates" => (
        key_count = 9,
        keyset_sha256 = "89e6b20d64360fd3a05d1ad992ed7485ae12c396d8a0b5a158c198917a679bd4",
    ),
    "lineage" => (
        key_count = 19,
        keyset_sha256 = "671b70de61ac94322d243818da42df1486a925e7199a0daf6ea29978785d8b63",
    ),
    "methodology" => (
        key_count = 8,
        keyset_sha256 = "438a801f0cdde26a3bd016e243df0f1a3c1ee36cfdc648f965a2508fbc11dbe0",
    ),
    "origin" => (
        key_count = 6,
        keyset_sha256 = "f6db8ac21bfc08009e23b492f9b5e6f66531c68e64ee9e255b4da96560e8b946",
    ),
    "parent_supersession" => (
        key_count = 12,
        keyset_sha256 = "9bc28194d62431d1554200dc80ae212e70c720a51548119ca3225c768f681e81",
    ),
    "predecessor_missingness" => (
        key_count = 14,
        keyset_sha256 = "42e71cae7c348a4d74522a983bd3b53d50bf64abff44d439ac08fefc0743c2ef",
    ),
    "required_conditions" => (
        key_count = 26,
        keyset_sha256 = "25d45d2eb0636f8b2fc39ec6bc1f41f2b5dea6aab685856b8879bb7bf9dbb0d2",
    ),
    "retention" => (
        key_count = 17,
        keyset_sha256 = "1f2d90edca8d40573f045b4624fe608784f4643583af5cbfc980b128f6a21c00",
    ),
    "source_semantics" => (
        key_count = 3,
        keyset_sha256 = "82733ca9099d017c9c548543e441931e36367383358fd67b71660e6c69b7d148",
    ),
)

const PROHIBITED_ACTIONS = [
    "ADMIT_ORIGIN",
    "APPEND_FORECAST",
    "APPEND_SCORE",
    "APPEND_TRUTH",
    "AUTHENTICATE_PUBLISHER_FROM_LOCAL_HASHES",
    "CLAIM_CURRENT_STATE",
    "CLAIM_FINAL_DAILY_STATE",
    "CLAIM_FIRST_PUBLIC_BYTES",
    "CLAIM_NO_LATER_CORRECTION",
    "EMIT_FORECAST",
    "EXECUTE_MODEL",
    "LOAD_TRUTH",
    "MUTATE_SOURCE_INVENTORY",
    "PROMOTE_MODEL",
    "WRITE_CAPTURE_OR_RECEIPT",
]

const SOURCE_SPECS = (
    (
        binding_id = "observed_state_v3_module",
        path = "scripts/us/forecasting/vintages/effr/observed_state_contract/USEFFRObservedStateContractV3.jl",
        sha256 = "3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6",
        role = "accepted_offline_observed_state_validator",
    ),
    (
        binding_id = "observed_state_v3_protocol",
        path = "scripts/us/forecasting/vintages/effr/observed_state_contract/observed_state_contract_v3.toml",
        sha256 = "d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716",
        role = "accepted_observed_state_semantics",
    ),
    (
        binding_id = "observed_state_v3_tests",
        path = "scripts/us/forecasting/vintages/effr/observed_state_contract/test_effr_observed_state_contract_v3.jl",
        sha256 = "55bfbf5a4b252804f4e3b2e91100c83b8ff98bffbf10eec5bdd3bd83d96ad66c",
        role = "accepted_observed_state_adversarial_tests",
    ),
    (
        binding_id = "observed_state_v3_readme",
        path = "scripts/us/forecasting/vintages/effr/observed_state_contract/README.md",
        sha256 = "4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23",
        role = "accepted_observed_state_claim_ceiling",
    ),
    (
        binding_id = "prospective_v2_module",
        path = "scripts/us/forecasting/vintages/prospective/USProspectiveAcquisitionContractV2.jl",
        sha256 = "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379",
        role = "accepted_selector_complete_prospective_contract_validator",
    ),
    (
        binding_id = "prospective_v2_contract",
        path = "scripts/us/forecasting/vintages/prospective/prospective_2026q3_contract_v2.toml",
        sha256 = "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f",
        role = "accepted_selector_complete_prospective_requirements",
    ),
    (
        binding_id = "prospective_v2_tests",
        path = "scripts/us/forecasting/vintages/prospective/test_prospective_acquisition_contract_v2.jl",
        sha256 = "4e46ef57fd9b3b26be884175b6594b4f425719fc96944da9b0d9c60db10d1083",
        role = "accepted_prospective_contract_adversarial_tests",
    ),
    (
        binding_id = "prospective_v2_readme",
        path = "scripts/us/forecasting/vintages/prospective/README.md",
        sha256 = "9d51d793ea36f440eec697180a71b221331495766b424d683cb7a1bd1b28e9ad",
        role = "accepted_prospective_contract_claim_ceiling",
    ),
    (
        binding_id = "restart_v2_module",
        path = "scripts/us/forecasting/vintages/effr/campaign_restart_v2/USEFFRCampaignRestartV2.jl",
        sha256 = "5e0873ec7c427c377386bf9bd33c782f39a4735391011cffc7e24a1c67aa7155",
        role = "accepted_restart_schedule_validator",
    ),
    (
        binding_id = "restart_v2_schedule",
        path = "scripts/us/forecasting/vintages/effr/campaign_restart_v2/effr_2026q3_restart_schedule_v2.toml",
        sha256 = "670e5b02b740e9195b768d22e002ee3de49f037efb5f0b1228f0c9482e3e0136",
        role = "accepted_115_slot_schedule",
    ),
    (
        binding_id = "restart_v2_tests",
        path = "scripts/us/forecasting/vintages/effr/campaign_restart_v2/test_effr_campaign_restart_v2.jl",
        sha256 = "0f0df50d5fbc1f1ef666084d5c20cf7e40f5116549ecc1390404959013beea33",
        role = "accepted_restart_schedule_tests",
    ),
    (
        binding_id = "restart_v2_readme",
        path = "scripts/us/forecasting/vintages/effr/campaign_restart_v2/README.md",
        sha256 = "fa7288ef3addd50c4836ec89971e1b002d6940fc42b37bc8010a1773ab4305d6",
        role = "accepted_restart_schedule_claim_ceiling",
    ),
    (
        binding_id = "restart_v4_module",
        path = "scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/USEFFRRecurringAcquisitionRestartV4.jl",
        sha256 = "a7c2e4c092e5e7a17e1bfd4143641a2e97c5566386720630ee06f12066d8b527",
        role = "accepted_nonadmitting_restart_collector_and_offline_evaluator",
    ),
    (
        binding_id = "restart_v4_cli",
        path = "scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/capture_effr_recurring_restart_v4.jl",
        sha256 = "cf3b1eb6eec26f711f5a75c6c3cef7448a782d7c1ad216e79df4d41ca45e0e02",
        role = "accepted_restart_capture_entrypoint",
    ),
    (
        binding_id = "restart_v4_tests",
        path = "scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/test_effr_recurring_acquisition_restart_v4.jl",
        sha256 = "f77f66cbce8ee3d936e9b7fe61d26b449ed4759b4aeeaa9ab74842a7b3c9fda5",
        role = "accepted_restart_collector_adversarial_tests",
    ),
    (
        binding_id = "restart_v4_readme",
        path = "scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/README.md",
        sha256 = "861a43dbae2bc42f3862809fa33145ab8041ffbfbcc0f622359ada0229687d4e",
        role = "accepted_restart_collector_claim_ceiling",
    ),
)

struct ProfileError <: Exception
    code::String
    location::String
    message::String
end

Base.showerror(io::IO, error::ProfileError) =
    print(io, error.code, " at ", error.location, ": ", error.message)

fail(code, location, message) =
    throw(ProfileError(String(code), String(location), String(message)))

function _expect_table(value, location)
    value isa AbstractDict || fail("TYPE_MISMATCH", location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail("TYPE_MISMATCH", location, "must use string keys")
    return value
end

function _expect_exact_keys(value, expected, location)
    table = _expect_table(value, location)
    actual = Set(String.(keys(table)))
    expected_set = Set(String.(expected))
    actual == expected_set ||
        fail(
        "CLOSED_SCHEMA_MISMATCH",
        location,
        "expected $(sort!(collect(expected_set))), got $(sort!(collect(actual)))",
    )
    return table
end

function _validate_section_schemas(profile)
    for (section, pin) in SECTION_SCHEMA_PINS
        table = _expect_table(profile[section], section)
        actual_keys = sort!(String.(collect(keys(table))))
        actual_sha256 = bytes2hex(sha256(codeunits(join(actual_keys, '\0'))))
        length(actual_keys) == pin.key_count &&
            actual_sha256 == pin.keyset_sha256 ||
            fail(
            "CLOSED_SCHEMA_MISMATCH",
            section,
            "unexpected or missing field",
        )
    end
    return nothing
end

function _expect_string(value, location)
    value isa AbstractString || fail("TYPE_MISMATCH", location, "must be a string")
    text = String(value)
    text == strip(text) ||
        fail("NONCANONICAL_STRING", location, "must not have surrounding whitespace")
    isempty(text) && fail("EMPTY_STRING", location, "must not be empty")
    return text
end

function _expect_bool(value, location)
    value isa Bool || fail("TYPE_MISMATCH", location, "must be Boolean")
    return value
end

function _expect_integer(value, location; minimum = typemin(Int))
    typeof(value) === Int || fail("TYPE_MISMATCH", location, "must be an exact Int")
    value >= minimum || fail("RANGE_VIOLATION", location, "is below $minimum")
    return value
end

function _expect_hash(value, location)
    text = _expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail("INVALID_SHA256", location, "must be lowercase SHA-256")
    return text
end

function _expect_identifier(value, location)
    text = _expect_string(value, location)
    occursin(IDENTIFIER_PATTERN, text) ||
        fail("INVALID_IDENTIFIER", location, "is outside the closed syntax")
    return text
end

function _expect_timestamp(value, location)
    text = _expect_string(value, location)
    occursin(TIMESTAMP_PATTERN, text) ||
        fail("INVALID_TIMESTAMP", location, "must be whole-second UTC")
    parsed = try
        DateTime(chop(text; tail = 1), TIMESTAMP_FORMAT)
    catch
        fail("INVALID_TIMESTAMP", location, "cannot be parsed")
    end
    Dates.format(parsed, TIMESTAMP_FORMAT) * "Z" == text ||
        fail("NONCANONICAL_TIMESTAMP", location, "must round-trip exactly")
    return parsed
end

function _expect_date(value, location)
    text = _expect_string(value, location)
    occursin(DATE_PATTERN, text) ||
        fail("INVALID_DATE", location, "must use YYYY-MM-DD")
    parsed = try
        Date(text)
    catch
        fail("INVALID_DATE", location, "cannot be parsed")
    end
    string(parsed) == text ||
        fail("NONCANONICAL_DATE", location, "must round-trip exactly")
    return parsed
end

function _expect_string_array(value, location; sorted = false)
    value isa AbstractVector || fail("TYPE_MISMATCH", location, "must be an array")
    result = String[
        _expect_string(entry, "$location[$index]") for
            (index, entry) in enumerate(value)
    ]
    length(result) == length(unique(result)) ||
        fail("DUPLICATE_VALUE", location, "must not contain duplicates")
    sorted && !issorted(result) &&
        fail("NONCANONICAL_ORDER", location, "must be sorted")
    return result
end

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        entries = sort!(collect(pairs(value)); by = pair -> String(first(pair)))
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
            "UNSUPPORTED_CANONICAL_TYPE",
            "canonicalization",
            "unsupported type $(typeof(value))",
        )
    end
    return io
end

function canonical_sha256(value)
    io = IOBuffer()
    _canonical_write(io, value)
    return bytes2hex(sha256(take!(io)))
end

function profile_semantic_sha256(profile)
    copy_profile = deepcopy(_expect_table(profile, "profile"))
    artifact = _expect_table(copy_profile["artifact"], "profile.artifact")
    pop!(artifact, "content_sha256", nothing)
    return canonical_sha256(copy_profile)
end

function _observed_state_semantic_sha256(document)
    function encode(value)
        if value isa AbstractDict
            keys_sorted = sort!(String.(collect(keys(value))))
            payload = join(
                "K$(ncodeunits(key)):$key" * encode(value[key]) for
                    key in keys_sorted
            )
            return "D$(length(keys_sorted)):$payload"
        elseif value isa AbstractVector
            return "A$(length(value)):" * join(encode(entry) for entry in value)
        elseif value isa AbstractString
            text = String(value)
            return "S$(ncodeunits(text)):$text"
        elseif value isa Bool
            return value ? "B1" : "B0"
        elseif value isa Integer
            return "I$value"
        end
        return fail(
            "UNSUPPORTED_UPSTREAM_CANONICAL_TYPE",
            "observed-state canonicalization",
            "unsupported type $(typeof(value))",
        )
    end
    copy_document = deepcopy(_expect_table(document, "observed-state protocol"))
    pop!(
        _expect_table(copy_document["artifact"], "observed-state artifact"),
        "content_sha256",
        nothing,
    )
    return bytes2hex(sha256(codeunits(encode(copy_document))))
end

function _path_components(relative_path)
    path = _expect_string(relative_path, "source.path")
    isabspath(path) && fail("PATH_ESCAPE", "source.path", "must be relative")
    occursin('\\', path) &&
        fail("PATH_ESCAPE", "source.path", "backslash separators are forbidden")
    components = split(path, '/'; keepempty = true)
    any(component -> component in ("", ".", ".."), components) &&
        fail("PATH_ESCAPE", "source.path", "contains an unsafe component")
    return components
end

function _read_regular_bound_file(root, relative_path, expected_sha256, location)
    root_input = rstrip(abspath(root), Sys.iswindows() ? ['\\'] : ['/'])
    isdir(root_input) || fail("ROOT_MISSING", location, "repository root is missing")
    islink(root_input) &&
        fail("SYMLINK_REJECTED", location, "repository root must not be a symlink")
    root_absolute = realpath(root_input)
    current = root_absolute
    components = _path_components(relative_path)
    for (index, component) in enumerate(components)
        current = joinpath(current, component)
        ispath(current) || fail("SOURCE_MISSING", location, "missing $relative_path")
        islink(current) &&
            fail("SYMLINK_REJECTED", location, "symbolic path component is forbidden")
        if index < length(components)
            isdir(current) ||
                fail("PATH_TYPE_MISMATCH", location, "parent component is not a directory")
        end
    end
    isfile(current) || fail("PATH_TYPE_MISMATCH", location, "leaf is not a file")
    stat(current).nlink == 1 ||
        fail("HARDLINK_REJECTED", location, "leaf must have exactly one link")
    resolved = realpath(current)
    prefix = root_absolute * (Sys.iswindows() ? "\\" : "/")
    (resolved == root_absolute || startswith(resolved, prefix)) ||
        fail("PATH_ESCAPE", location, "resolved leaf escaped repository root")
    bytes = read(current)
    digest = bytes2hex(sha256(bytes))
    digest == expected_sha256 ||
        fail("SOURCE_SHA256_MISMATCH", location, "expected $expected_sha256, got $digest")
    return bytes
end

function _parse_toml_bytes(bytes, location)
    try
        return TOML.parse(String(copy(bytes)))
    catch error
        fail("TOML_PARSE_FAILED", location, sprint(showerror, error))
    end
end

function _source_index(profile)
    sources = profile["sources"]
    sources isa AbstractVector || fail("TYPE_MISMATCH", "sources", "must be an array")
    length(sources) == length(SOURCE_SPECS) ||
        fail("SOURCE_COUNT_MISMATCH", "sources", "must contain $(length(SOURCE_SPECS)) entries")
    index = Dict{String, Any}()
    for (position, source) in enumerate(sources)
        item = _expect_exact_keys(
            source,
            ["binding_id", "path", "role", "sha256"],
            "sources[$position]",
        )
        binding_id = _expect_identifier(item["binding_id"], "sources[$position].binding_id")
        haskey(index, binding_id) &&
            fail("DUPLICATE_SOURCE_BINDING", "sources", "duplicate $binding_id")
        index[binding_id] = item
    end
    for expected in SOURCE_SPECS
        haskey(index, expected.binding_id) ||
            fail("SOURCE_BINDING_MISSING", "sources", expected.binding_id)
        actual = index[expected.binding_id]
        actual["path"] == expected.path ||
            fail("SOURCE_PATH_MISMATCH", expected.binding_id, "path changed")
        actual["sha256"] == expected.sha256 ||
            fail("SOURCE_PIN_MISMATCH", expected.binding_id, "SHA-256 changed")
        actual["role"] == expected.role ||
            fail("SOURCE_ROLE_MISMATCH", expected.binding_id, "role changed")
    end
    return index
end

function _verify_bound_sources(profile; repository_root = REPOSITORY_ROOT)
    index = _source_index(profile)
    bytes_by_id = Dict{String, Vector{UInt8}}()
    for spec in SOURCE_SPECS
        bytes_by_id[spec.binding_id] = _read_regular_bound_file(
            repository_root,
            spec.path,
            spec.sha256,
            "source.$(spec.binding_id)",
        )
    end

    semantics = profile["source_semantics"]
    observed = _parse_toml_bytes(
        bytes_by_id["observed_state_v3_protocol"],
        "observed-state-v3 protocol",
    )
    observed_semantic = _observed_state_semantic_sha256(observed)
    observed_semantic == semantics["observed_state_protocol_semantic_sha256"] ||
        fail("UPSTREAM_SEMANTIC_MISMATCH", "observed-state-v3", observed_semantic)
    observed["artifact"]["content_sha256"] == observed_semantic ||
        fail("UPSTREAM_SELF_HASH_MISMATCH", "observed-state-v3", "embedded digest differs")
    observed["current_state_disposition"] == Dict{String, Any}(
        "authoritative_evidence_ever_official" => "NOT_ESTABLISHED",
        "captured_wire_presence" => "ABSENT",
        "current_openapi_definition" => "ABSENT",
        "raw_false_derivation_allowed" => false,
        "synthetic_current_state_allowed" => false,
    ) || fail("UPSTREAM_SEMANTIC_MISMATCH", "observed-state currentState", "changed")
    observed["estimand"]["status"] == "PENDING" ||
        fail("UPSTREAM_SEMANTIC_MISMATCH", "observed-state estimand", "must remain pending")
    observed["estimand"]["candidate_estimands"] ==
        ["STRICT_FIRST_PUBLIC_BYTES", ESTIMAND_ID] ||
        fail("UPSTREAM_SEMANTIC_MISMATCH", "observed-state estimand", "candidates changed")
    observed["policy"]["unchanged_claim"] ==
        "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE" ||
        fail("UPSTREAM_CLAIM_CEILING_CHANGED", "observed-state policy", "changed")
    all(value -> value === false, values(observed["gates"])) ||
        fail("UPSTREAM_GATE_ELEVATION", "observed-state gates", "must all be false")

    prospective = _parse_toml_bytes(
        bytes_by_id["prospective_v2_contract"],
        "prospective-v2 contract",
    )
    prospective_semantic = profile_semantic_sha256(prospective)
    prospective_semantic == semantics["prospective_v2_contract_semantic_sha256"] ||
        fail("UPSTREAM_SEMANTIC_MISMATCH", "prospective-v2", prospective_semantic)
    prospective["artifact"]["content_sha256"] == prospective_semantic ||
        fail("UPSTREAM_SELF_HASH_MISMATCH", "prospective-v2", "embedded digest differs")
    prospective["origin"]["origin_timestamp_utc"] == ORIGIN_TIMESTAMP ||
        fail("UPSTREAM_ORIGIN_CHANGED", "prospective-v2", "origin cutoff changed")
    prospective["retention"]["minimum_retain_until_utc"] ==
        "2031-10-30T14:00:00Z" ||
        fail("UPSTREAM_RETENTION_CHANGED", "prospective-v2", "boundary changed")
    prospective["retention"]["origin_plus_mature_truth_months"] == 60 ||
        fail("UPSTREAM_RETENTION_CHANGED", "prospective-v2", "lag changed")
    prospective["verifier"]["implementation_status"] ==
        "NOT_IMPLEMENTED_FAIL_CLOSED" ||
        fail("UPSTREAM_GATE_ELEVATION", "prospective-v2 verifier", "changed")
    prospective["approval"]["artifact_approval_status"] == "DRAFT_UNAPPROVED" ||
        fail("UPSTREAM_GATE_ELEVATION", "prospective-v2 approval", "changed")
    effr_requirements = [
        requirement for requirement in prospective["requirements"] if
            requirement["requirement_id"] == "frbny_effr_tier1"
    ]
    length(effr_requirements) == 1 ||
        fail("UPSTREAM_PROFILE_MISMATCH", "prospective-v2 EFFR", "must be unique")
    effr_profiles = only(effr_requirements)["artifact_profiles"]
    Set(keys(effr_profiles)) ==
        Set(["effr_daily_history", "effr_first_state_manifest", "effr_revision_manifest"]) ||
        fail("UPSTREAM_PROFILE_MISMATCH", "prospective-v2 EFFR", "profile set changed")

    schedule = _parse_toml_bytes(
        bytes_by_id["restart_v2_schedule"],
        "restart-v2 schedule",
    )
    schedule_semantic = profile_semantic_sha256(schedule)
    schedule_semantic == semantics["restart_v2_schedule_semantic_sha256"] ||
        fail("UPSTREAM_SEMANTIC_MISMATCH", "restart-v2 schedule", schedule_semantic)
    schedule["artifact"]["content_sha256"] == schedule_semantic ||
        fail("UPSTREAM_SELF_HASH_MISMATCH", "restart-v2 schedule", "embedded digest differs")
    policy = schedule["policy"]
    policy["origin_cutoff_utc"] == ORIGIN_TIMESTAMP ||
        fail("UPSTREAM_ORIGIN_CHANGED", "restart-v2 schedule", "cutoff changed")
    policy["expected_first_state_count"] == 58 ||
        fail("UPSTREAM_COVERAGE_CHANGED", "restart-v2 schedule", "first count changed")
    policy["expected_revision_check_count"] == 57 ||
        fail("UPSTREAM_COVERAGE_CHANGED", "restart-v2 schedule", "revision count changed")
    policy["expected_slot_count"] == 115 ||
        fail("UPSTREAM_COVERAGE_CHANGED", "restart-v2 schedule", "slot count changed")
    slots = schedule["slots"]
    length(slots) == 115 ||
        fail("UPSTREAM_COVERAGE_CHANGED", "restart-v2 schedule", "slot rows changed")
    Int[slot["sequence"] for slot in slots] == collect(1:115) ||
        fail("UPSTREAM_COVERAGE_CHANGED", "restart-v2 schedule", "sequence changed")
    count(slot -> slot["phase"] == "first", slots) == 58 ||
        fail("UPSTREAM_COVERAGE_CHANGED", "restart-v2 schedule", "first rows changed")
    count(slot -> slot["phase"] == "revision-check", slots) == 57 ||
        fail("UPSTREAM_COVERAGE_CHANGED", "restart-v2 schedule", "revision rows changed")
    schedule["claim_ceiling"]["positive_claim"] ==
        "MARKETS_API_ENDPOINT_STATE_OBSERVED_AS_OF_CAPTURE_TIME_ONLY" ||
        fail("UPSTREAM_CLAIM_CEILING_CHANGED", "restart-v2 schedule", "changed")
    schedule["predecessor_history"]["planned_slot_count"] == 117 ||
        fail("UPSTREAM_MISSINGNESS_CHANGED", "restart-v2 predecessor", "denominator changed")
    schedule["predecessor_history"]["missed_august7_revision_check_slot_count"] == 1 ||
        fail("UPSTREAM_MISSINGNESS_CHANGED", "restart-v2 predecessor", "miss changed")
    schedule["predecessor_history"]["complete"] === false ||
        fail("UPSTREAM_GATE_ELEVATION", "restart-v2 predecessor", "must remain incomplete")
    all(value -> value === false, values(schedule["gates"])) ||
        fail("UPSTREAM_GATE_ELEVATION", "restart-v2 gates", "must all be false")

    return bytes_by_id
end

function _validate_closed_profile_semantics(profile)
    artifact = _expect_exact_keys(
        profile["artifact"],
        ["canonicalization", "content_sha256", "contract_id", "schema_version", "status"],
        "artifact",
    )
    artifact["schema_version"] == PROFILE_SCHEMA ||
        fail("SCHEMA_CHANGED", "artifact.schema_version", "unsupported")
    artifact["contract_id"] == CONTRACT_ID ||
        fail("CONTRACT_CHANGED", "artifact.contract_id", "unsupported")
    artifact["status"] == CURRENT_STATUS ||
        fail("STATUS_ELEVATION", "artifact.status", "current artifact must remain CANNOT_RUN")
    artifact["canonicalization"] == CANONICALIZATION ||
        fail("CANONICALIZATION_CHANGED", "artifact.canonicalization", "unsupported")

    contract = profile["contract"]
    contract["allowed_statuses"] == [CURRENT_STATUS, READY_STATUS] ||
        fail("STATUS_VOCABULARY_CHANGED", "contract.allowed_statuses", "changed")
    contract["current_expected_status"] == CURRENT_STATUS ||
        fail("STATUS_ELEVATION", "contract.current_expected_status", "changed")
    contract["ready_status"] == READY_STATUS ||
        fail("STATUS_VOCABULARY_CHANGED", "contract.ready_status", "changed")
    for field in (
            "filesystem_write_forbidden",
            "forecast_seal_status_forbidden",
            "model_execution_forbidden",
            "network_access_forbidden",
            "origin_admission_forbidden",
            "ready_to_score_forbidden",
            "source_inventory_mutation_forbidden",
            "truth_access_forbidden",
        )
        _expect_bool(contract[field], "contract.$field") ||
            fail("PROHIBITION_REMOVED", "contract.$field", "must remain true")
    end
    contract["local_hashes_authenticate_publisher"] === false ||
        fail("TRUST_ELEVATION", "contract.local_hashes_authenticate_publisher", "must be false")

    estimand = profile["estimand"]
    estimand["estimand_id"] == ESTIMAND_ID ||
        fail("ESTIMAND_CHANGED", "estimand.estimand_id", "changed")
    estimand["role"] == "MODEL_INPUT_ONLY" ||
        fail("ESTIMAND_ROLE_CHANGED", "estimand.role", "changed")
    estimand["status"] == "DEFINED_NOT_APPROVED" ||
        fail("APPROVAL_ELEVATION", "estimand.status", "must remain unapproved")
    estimand["claim_ceiling"] == CLAIM_CEILING ||
        fail("CLAIM_CEILING_CHANGED", "estimand.claim_ceiling", "changed")
    estimand["current_state"] === false ||
        fail("CURRENT_STATE_FORGERY", "estimand.current_state", "must remain false")
    estimand["current_state_derivation_allowed"] === false ||
        fail("CURRENT_STATE_FORGERY", "estimand.current_state_derivation_allowed", "must be false")
    for field in (
            "final_daily_state",
            "first_public_bytes",
            "forecast_output_role_allowed",
            "historical_first_byte",
            "no_later_correction",
            "no_later_same_day_revision",
            "publisher_provenance_authenticated",
            "rate_volume_pair_atomic",
            "transport_provenance_authenticated",
            "truth_role_allowed",
        )
        estimand[field] === false ||
            fail("CLAIM_ELEVATION", "estimand.$field", "must remain false")
    end

    origin = profile["origin"]
    _expect_timestamp(origin["origin_timestamp_utc"], "origin.origin_timestamp_utc")
    origin["origin_timestamp_utc"] == ORIGIN_TIMESTAMP ||
        fail("ORIGIN_CHANGED", "origin.origin_timestamp_utc", "changed")
    origin["admission_status"] == "PLANNED_NOT_CAPTURED_NOT_ADMITTED" ||
        fail("ADMISSION_ELEVATION", "origin.admission_status", "changed")

    coverage = profile["coverage"]
    coverage["q3_endpoint_history_candidate_start"] == "2026-07-01" ||
        fail("HISTORY_RANGE_CHANGED", "coverage", "start changed")
    coverage["q3_endpoint_history_candidate_end"] == "2026-10-29" ||
        fail("HISTORY_RANGE_CHANGED", "coverage", "end changed")
    coverage["q3_endpoint_history_candidate_row_count"] == 84 ||
        fail("HISTORY_RANGE_CHANGED", "coverage", "row count changed")
    coverage["q3_endpoint_history_candidate_excluded_dates"] ==
        ["2026-07-03", "2026-09-07", "2026-10-12"] ||
        fail("HISTORY_CALENDAR_CHANGED", "coverage", "holiday set changed")
    coverage["q3_endpoint_history_candidate_approved"] === false ||
        fail("CANDIDATE_ELEVATION", "coverage", "Q3 endpoint campaign must remain unapproved")
    coverage["q3_candidate_establishes_complete_effr_daily_history"] === false ||
        fail("COVERAGE_ALIAS_FORGERY", "coverage", "Q3 candidate is not complete history")
    coverage["q3_candidate_establishes_training_history_sufficiency"] === false ||
        fail("TRAINING_HISTORY_FORGERY", "coverage", "Q3 candidate is not sufficient training")
    coverage["model_input_training_history_selector_start"] == "UNDECIDED" ||
        fail("SELECTOR_START_ELEVATION", "coverage", "selector start must remain undecided")
    coverage["daily_history_selector_start_approved"] === false ||
        fail("SELECTOR_START_ELEVATION", "coverage", "selector start must remain unapproved")
    coverage["training_history_length_sufficient"] === false ||
        fail("TRAINING_HISTORY_FORGERY", "coverage", "training sufficiency must remain false")
    coverage["minimum_training_quarters"] == 60 ||
        fail("TRAINING_CONTRACT_CHANGED", "coverage", "minimum training quarters changed")
    coverage["core3_revised_geometry_start"] == "2000Q3" ||
        fail("TRAINING_CONTRACT_CHANGED", "coverage", "core-three start changed")
    coverage["restart_required_first_observation_count"] == 58 ||
        fail("RESTART_COVERAGE_CHANGED", "coverage", "first count changed")
    coverage["restart_required_revision_observation_count"] == 57 ||
        fail("RESTART_COVERAGE_CHANGED", "coverage", "revision count changed")
    coverage["restart_required_slot_count"] == 115 ||
        fail("RESTART_COVERAGE_CHANGED", "coverage", "slot count changed")
    coverage["restart_does_not_establish_daily_history_coverage"] === true ||
        fail("COVERAGE_ALIAS_FORGERY", "coverage", "restart cannot stand in for history")
    coverage["restart_does_not_establish_first_public_bytes"] === true ||
        fail("CLAIM_ELEVATION", "coverage", "restart cannot prove first bytes")
    coverage["cross_campaign_combination_allowed"] === false ||
        fail("CROSS_CAMPAIGN_FORGERY", "coverage", "must be false")

    expected_dates = _q3_endpoint_candidate_dates()
    length(expected_dates) == coverage["q3_endpoint_history_candidate_row_count"] ||
        fail("INTERNAL_CALENDAR_MISMATCH", "coverage", "row count does not derive")
    first(expected_dates) == Date(2026, 7, 1) ||
        fail("INTERNAL_CALENDAR_MISMATCH", "coverage", "first date changed")
    last(expected_dates) == Date(2026, 10, 29) ||
        fail("INTERNAL_CALENDAR_MISMATCH", "coverage", "last date changed")

    methodology = profile["methodology"]
    methodology["methodology_change_effective_date"] == "2016-03-01" ||
        fail("METHODOLOGY_BREAK_CHANGED", "methodology", "date changed")
    methodology["pre_post_2016_regime_treatment_required"] === true ||
        fail("METHODOLOGY_REQUIREMENT_REMOVED", "methodology", "regime treatment required")
    methodology["pre_post_2016_regime_treatment_status"] ==
        "UNDECIDED_UNAPPROVED" ||
        fail("METHODOLOGY_ELEVATION", "methodology", "must remain unapproved")
    methodology["methodology_break_may_be_ignored"] === false ||
        fail("METHODOLOGY_REQUIREMENT_REMOVED", "methodology", "break cannot be ignored")
    methodology["local_evidence_binding_id"] == "observed_state_v3_protocol" ||
        fail("METHODOLOGY_BINDING_CHANGED", "methodology", "binding changed")

    supersession = profile["parent_supersession"]
    supersession["legacy_profile_ids"] ==
        ["effr_daily_history", "effr_first_state_manifest", "effr_revision_manifest"] ||
        fail("SUPERSESSION_MAPPING_CHANGED", "parent_supersession", "legacy set changed")
    supersession["semantic_supersession_decision_status"] ==
        "MISSING_UNAPPROVED" ||
        fail("SUPERSESSION_ELEVATION", "parent_supersession", "decision must be missing")
    for field in (
            "legacy_profile_relabeling_allowed",
            "parent_requirement_completion_authorized",
            "qualified_leaf_dispatch_present",
            "this_leaf_alone_satisfies_parent_requirement",
        )
        supersession[field] === false ||
            fail("SUPERSESSION_ELEVATION", "parent_supersession.$field", "must be false")
    end
    supersession["semantic_supersession_decision_required"] === true ||
        fail("SUPERSESSION_REQUIREMENT_REMOVED", "parent_supersession", "decision required")
    supersession["qualified_leaf_dispatch_required"] === true ||
        fail("DISPATCH_REQUIREMENT_REMOVED", "parent_supersession", "dispatch required")

    missingness = profile["predecessor_missingness"]
    missingness["predecessor_planned_slot_count"] == 117 ||
        fail("PREDECESSOR_MISSINGNESS_CHANGED", "predecessor_missingness", "denominator changed")
    missingness["august_7_revision_missed_count"] == 1 ||
        fail("PREDECESSOR_MISSINGNESS_CHANGED", "predecessor_missingness", "miss changed")
    for field in (
            "cross_campaign_relabeling_allowed",
            "old_117_slot_manifest_completion_claim_allowed",
            "predecessor_complete",
            "predecessor_may_complete_restart",
            "predecessor_recoverable",
            "restart_may_complete_predecessor",
        )
        missingness[field] === false ||
            fail("PREDECESSOR_COMPLETION_FORGERY", "predecessor_missingness.$field", "must be false")
    end

    approval = profile["approval"]
    approval["current_status"] == "MISSING" ||
        fail("APPROVAL_ELEVATION", "approval.current_status", "must remain missing")
    approval["distinct_owner_validator_required"] === true ||
        fail("SEPARATION_OF_DUTIES_REMOVED", "approval", "must be required")
    approval["self_rehashed_receipt_sufficient"] === false ||
        fail("SELF_HASH_TRUST_ELEVATION", "approval", "must remain false")

    lineage = profile["lineage"]
    lineage["q3_endpoint_history_status"] == "MISSING" ||
        fail("LINEAGE_ELEVATION", "lineage.q3_endpoint_history_status", "must be missing")
    lineage["model_input_training_history_status"] == "MISSING" ||
        fail("LINEAGE_ELEVATION", "lineage.model_input_training_history_status", "must be missing")
    lineage["restart_diagnostic_status"] == "MISSING" ||
        fail("LINEAGE_ELEVATION", "lineage.restart_diagnostic_status", "must be missing")
    lineage["self_rehashed_lineage_sufficient"] === false ||
        fail("SELF_HASH_TRUST_ELEVATION", "lineage", "must remain false")
    lineage["synthetic_fixture_eligible"] === false ||
        fail("SYNTHETIC_EVIDENCE_ELEVATION", "lineage", "must remain false")
    lineage["minimum_independent_durability_domains"] == 2 ||
        fail("DURABILITY_REQUIREMENT_CHANGED", "lineage", "two domains are required")
    lineage["external_trusted_timestamp_required"] === true ||
        fail("TIMESTAMP_REQUIREMENT_REMOVED", "lineage", "external timestamp required")

    retention = profile["retention"]
    retention["h12_target_reference_period"] == "2029Q3" ||
        fail("RETENTION_GEOMETRY_CHANGED", "retention", "h12 target changed")
    retention["h12_target_period_end_utc"] == "2029-09-30T23:59:59Z" ||
        fail("RETENTION_GEOMETRY_CHANGED", "retention", "h12 period end changed")
    retention["mature_truth_lag_months"] == 60 ||
        fail("RETENTION_GEOMETRY_CHANGED", "retention", "mature lag changed")
    retention["mathematical_minimum_retain_until_utc"] ==
        MATHEMATICAL_RETENTION_MINIMUM ||
        fail("RETENTION_GEOMETRY_CHANGED", "retention", "minimum changed")
    retention["conservative_custody_cushion_until_utc"] ==
        CONSERVATIVE_RETENTION_CUSHION ||
        fail("RETENTION_GEOMETRY_CHANGED", "retention", "cushion changed")
    retention["prospective_v2_retain_until_utc"] == "2031-10-30T14:00:00Z" ||
        fail("RETENTION_DEFECT_HIDDEN", "retention", "v2 boundary changed")
    retention["prospective_v2_retention_sufficient"] === false ||
        fail("RETENTION_ELEVATION", "retention", "v2 must remain insufficient")
    retention["successor_retention_contract_required"] === true ||
        fail("RETENTION_REQUIREMENT_REMOVED", "retention", "successor must be required")
    retention["successor_retention_status"] == "MISSING" ||
        fail("RETENTION_ELEVATION", "retention", "successor must remain missing")
    _expect_timestamp(
        retention["h12_target_period_end_utc"],
        "retention.h12_target_period_end_utc",
    )
    _expect_timestamp(
        retention["mathematical_minimum_retain_until_utc"],
        "retention.mathematical_minimum_retain_until_utc",
    )
    _expect_timestamp(
        retention["conservative_custody_cushion_until_utc"],
        "retention.conservative_custody_cushion_until_utc",
    )
    _expect_timestamp(
        retention["prospective_v2_retain_until_utc"],
        "retention.prospective_v2_retain_until_utc",
    )
    DateTime(2034, 9, 30, 23, 59, 59) ==
        DateTime(2029, 9, 30, 23, 59, 59) + Month(60) ||
        fail("INTERNAL_RETENTION_MISMATCH", "retention", "60-month derivation failed")
    _expect_timestamp(
        retention["prospective_v2_retain_until_utc"],
        "retention.prospective_v2_retain_until_utc",
    ) < _expect_timestamp(
        retention["mathematical_minimum_retain_until_utc"],
        "retention.mathematical_minimum_retain_until_utc",
    ) || fail("RETENTION_DEFECT_HIDDEN", "retention", "v2 is not earlier than minimum")

    required = profile["required_conditions"]
    all(value -> value === true, values(required)) ||
        fail("REQUIREMENT_WEAKENED", "required_conditions", "all declarations must be true")
    current = profile["current_evidence"]
    for (key, value) in current
        if endswith(key, "_verified") && value isa Integer
            value == 0 || fail("EVIDENCE_ELEVATION", "current_evidence.$key", "must be zero")
        elseif value isa Bool
            value === false ||
                fail("EVIDENCE_ELEVATION", "current_evidence.$key", "must be false")
        end
    end
    gates = _expect_exact_keys(profile["gates"], FALSE_GATE_KEYS, "gates")
    all(value -> value === false, values(gates)) ||
        fail("GATE_ELEVATION", "gates", "all gates must remain false")
    profile["prohibited_actions"] == PROHIBITED_ACTIONS ||
        fail("PROHIBITION_SET_CHANGED", "prohibited_actions", "changed")
    return nothing
end

function _q3_endpoint_candidate_dates()
    excluded = Set([Date(2026, 7, 3), Date(2026, 9, 7), Date(2026, 10, 12)])
    return [
        date for date in Date(2026, 7, 1):Day(1):Date(2026, 10, 29) if
            dayofweek(date) <= 5 && !(date in excluded)
    ]
end

function validate_profile_document(
        profile;
        verify_sources = true,
        repository_root = REPOSITORY_ROOT,
    )
    document = _expect_exact_keys(profile, TOP_LEVEL_KEYS, "profile")
    _validate_section_schemas(document)
    _source_index(document)
    _validate_closed_profile_semantics(document)
    embedded = _expect_hash(
        document["artifact"]["content_sha256"],
        "artifact.content_sha256",
    )
    computed = profile_semantic_sha256(document)
    embedded == computed ||
        fail("PROFILE_SELF_HASH_MISMATCH", "artifact.content_sha256", "does not reproduce")
    computed == EXPECTED_PROFILE_SEMANTIC_SHA256 ||
        fail("OUT_OF_BAND_PROFILE_PIN_MISMATCH", "profile", "semantic bytes changed")
    verify_sources && _verify_bound_sources(document; repository_root)
    return document
end

function validate_profile(path::AbstractString = PROFILE_PATH)
    absolute = abspath(path)
    expected_relative = relpath(absolute, REPOSITORY_ROOT)
    bytes = _read_regular_bound_file(
        REPOSITORY_ROOT,
        expected_relative,
        EXPECTED_PROFILE_PHYSICAL_SHA256,
        "profile manifest",
    )
    document = _parse_toml_bytes(bytes, "profile manifest")
    return validate_profile_document(document)
end

const BLOCKER_BINDINGS = Dict(
    "model_owner_approval_present" => ["prospective_v2_contract"],
    "independent_validator_approval_present" => ["prospective_v2_contract"],
    "distinct_owner_validator_established" => ["prospective_v2_contract"],
    "semantic_supersession_decision_present" => ["prospective_v2_contract", "observed_state_v3_protocol"],
    "qualified_leaf_dispatch_present" => ["prospective_v2_contract"],
    "q3_endpoint_history_lineage_manifest_present" => ["prospective_v2_contract"],
    "q3_endpoint_history_lineage_independently_verified" => ["prospective_v2_contract"],
    "q3_endpoint_history_exact_date_set_complete" => ["prospective_v2_contract"],
    "q3_endpoint_history_rate_volume_rows_complete" => ["prospective_v2_contract"],
    "model_input_training_history_lineage_manifest_present" => ["prospective_v2_contract"],
    "model_input_training_history_lineage_independently_verified" => ["prospective_v2_contract"],
    "daily_history_selector_start_approved" => ["prospective_v2_contract"],
    "training_history_length_sufficient" => ["prospective_v2_contract"],
    "pre_post_2016_regime_treatment_approved" => ["observed_state_v3_protocol"],
    "restart_diagnostic_lineage_manifest_present" => ["restart_v2_schedule", "restart_v4_module"],
    "restart_diagnostic_lineage_independently_verified" => ["restart_v2_schedule", "restart_v4_module"],
    "restart_first_observation_coverage_complete" => ["restart_v2_schedule", "restart_v4_module"],
    "restart_revision_observation_coverage_complete" => ["restart_v2_schedule", "restart_v4_module"],
    "restart_slot_coverage_complete" => ["restart_v2_schedule", "restart_v4_module"],
    "restart_pair_coverage_complete" => ["restart_v2_schedule", "restart_v4_module"],
    "external_timestamp_lineage_complete" => ["prospective_v2_contract", "restart_v4_module"],
    "durable_replica_lineage_complete" => ["prospective_v2_contract", "restart_v4_module"],
    "two_independent_durability_domains_verified" => ["prospective_v2_contract", "restart_v4_module"],
    "successor_retention_contract_present" => ["prospective_v2_contract"],
    "full_truth_horizon_retention_covered" => ["prospective_v2_contract"],
    "verified_mature_receipt_plus_audit_policy_covered" => ["prospective_v2_contract"],
)

const BLOCKER_REASONS = Dict(
    "model_owner_approval_present" => "MODEL_OWNER_APPROVAL_RECEIPT_MISSING",
    "independent_validator_approval_present" => "INDEPENDENT_VALIDATOR_APPROVAL_RECEIPT_MISSING",
    "distinct_owner_validator_established" => "DISTINCT_OWNER_VALIDATOR_IDENTITIES_NOT_ESTABLISHED",
    "semantic_supersession_decision_present" => "LEGACY_TO_ACTIVE_THREE_PROFILE_SUPERSESSION_DECISION_MISSING",
    "qualified_leaf_dispatch_present" => "QUALIFIED_PARENT_V3_LEAF_DISPATCH_MISSING",
    "q3_endpoint_history_lineage_manifest_present" => "Q3_ENDPOINT_HISTORY_CANDIDATE_LINEAGE_MANIFEST_MISSING",
    "q3_endpoint_history_lineage_independently_verified" => "Q3_ENDPOINT_HISTORY_CANDIDATE_LINEAGE_NOT_INDEPENDENTLY_VERIFIED",
    "q3_endpoint_history_exact_date_set_complete" => "Q3_ENDPOINT_HISTORY_CANDIDATE_EXACT_84_DATE_SET_NOT_VERIFIED",
    "q3_endpoint_history_rate_volume_rows_complete" => "Q3_ENDPOINT_HISTORY_CANDIDATE_RATE_VOLUME_ROWS_NOT_VERIFIED",
    "model_input_training_history_lineage_manifest_present" => "MODEL_INPUT_TRAINING_HISTORY_LINEAGE_MANIFEST_MISSING",
    "model_input_training_history_lineage_independently_verified" => "MODEL_INPUT_TRAINING_HISTORY_LINEAGE_NOT_INDEPENDENTLY_VERIFIED",
    "daily_history_selector_start_approved" => "MODEL_INPUT_DAILY_HISTORY_SELECTOR_START_UNJUSTIFIED_UNAPPROVED",
    "training_history_length_sufficient" => "MODEL_INPUT_TRAINING_HISTORY_LENGTH_NOT_ESTABLISHED_FOR_60_QUARTERS",
    "pre_post_2016_regime_treatment_approved" => "EFFR_PRE_POST_2016_METHODOLOGY_REGIME_TREATMENT_UNDECIDED",
    "restart_diagnostic_lineage_manifest_present" => "RESTART_115_SLOT_DIAGNOSTIC_LINEAGE_MANIFEST_MISSING",
    "restart_diagnostic_lineage_independently_verified" => "RESTART_DIAGNOSTIC_LINEAGE_NOT_INDEPENDENTLY_VERIFIED",
    "restart_first_observation_coverage_complete" => "RESTART_FIRST_OBSERVATION_COVERAGE_ZERO_OF_58",
    "restart_revision_observation_coverage_complete" => "RESTART_REVISION_OBSERVATION_COVERAGE_ZERO_OF_57",
    "restart_slot_coverage_complete" => "RESTART_SLOT_COVERAGE_ZERO_OF_115",
    "restart_pair_coverage_complete" => "RESTART_COMPLETE_PAIR_COVERAGE_ZERO_OF_57",
    "external_timestamp_lineage_complete" => "EXTERNAL_TIMESTAMP_LINEAGE_INCOMPLETE",
    "durable_replica_lineage_complete" => "DURABLE_REPLICA_LINEAGE_INCOMPLETE",
    "two_independent_durability_domains_verified" => "TWO_INDEPENDENT_DURABILITY_DOMAINS_NOT_VERIFIED",
    "successor_retention_contract_present" => "SUCCESSOR_FULL_HORIZON_RETENTION_CONTRACT_MISSING",
    "full_truth_horizon_retention_covered" => "PROSPECTIVE_V2_RETENTION_ENDS_BEFORE_H12_MATURE_TRUTH_MINIMUM",
    "verified_mature_receipt_plus_audit_policy_covered" => "VERIFIED_MATURE_RECEIPT_COMPLETION_PLUS_AUDIT_CUSTODY_NOT_COVERED",
)

function _derive_conditions(profile)
    evidence = profile["current_evidence"]
    coverage = profile["coverage"]
    conditions = Dict{String, Bool}(
        "model_owner_approval_present" => evidence["model_owner_approval_present"],
        "independent_validator_approval_present" => evidence["independent_validator_approval_present"],
        "distinct_owner_validator_established" => evidence["distinct_owner_validator_established"],
        "semantic_supersession_decision_present" =>
            evidence["semantic_supersession_decision_present"],
        "qualified_leaf_dispatch_present" => evidence["qualified_leaf_dispatch_present"],
        "q3_endpoint_history_lineage_manifest_present" =>
            evidence["q3_endpoint_history_lineage_manifest_present"],
        "q3_endpoint_history_lineage_independently_verified" =>
            evidence["q3_endpoint_history_lineage_independently_verified"],
        "q3_endpoint_history_exact_date_set_complete" =>
            evidence["q3_endpoint_history_exact_date_set_verified"] &&
            evidence["q3_endpoint_history_row_count_verified"] ==
            coverage["q3_endpoint_history_candidate_row_count"],
        "q3_endpoint_history_rate_volume_rows_complete" =>
            evidence["q3_endpoint_history_rate_volume_rows_verified"],
        "model_input_training_history_lineage_manifest_present" =>
            evidence["model_input_training_history_lineage_manifest_present"],
        "model_input_training_history_lineage_independently_verified" =>
            evidence["model_input_training_history_lineage_independently_verified"],
        "daily_history_selector_start_approved" =>
            evidence["daily_history_selector_start_approved"],
        "training_history_length_sufficient" =>
            evidence["training_history_length_sufficient"],
        "pre_post_2016_regime_treatment_approved" =>
            evidence["pre_post_2016_regime_treatment_approved"],
        "restart_diagnostic_lineage_manifest_present" =>
            evidence["restart_diagnostic_lineage_manifest_present"],
        "restart_diagnostic_lineage_independently_verified" =>
            evidence["restart_diagnostic_lineage_independently_verified"],
        "restart_first_observation_coverage_complete" =>
            evidence["restart_first_observation_count_verified"] ==
            coverage["restart_required_first_observation_count"],
        "restart_revision_observation_coverage_complete" =>
            evidence["restart_revision_observation_count_verified"] ==
            coverage["restart_required_revision_observation_count"],
        "restart_slot_coverage_complete" =>
            evidence["restart_slot_count_verified"] ==
            coverage["restart_required_slot_count"],
        "restart_pair_coverage_complete" =>
            evidence["restart_complete_pair_count_verified"] ==
            coverage["restart_required_complete_pair_count"],
        "external_timestamp_lineage_complete" =>
            evidence["external_timestamp_lineage_complete"],
        "durable_replica_lineage_complete" =>
            evidence["durable_replica_lineage_complete"],
        "two_independent_durability_domains_verified" =>
            evidence["independent_durability_domain_count_verified"] >= 2,
        "successor_retention_contract_present" =>
            evidence["successor_retention_contract_present"],
        "full_truth_horizon_retention_covered" =>
            evidence["full_truth_horizon_retention_covered"],
        "verified_mature_receipt_plus_audit_policy_covered" =>
            evidence["verified_mature_receipt_plus_audit_policy_covered"],
    )
    Set(keys(conditions)) == Set(keys(profile["required_conditions"])) ||
        fail("CONDITION_SET_MISMATCH", "required_conditions", "derivation changed")
    return conditions
end

function _result_without_hash(profile)
    conditions = _derive_conditions(profile)
    false_conditions = sort!([key for (key, value) in conditions if !value])
    blockers = [
        Dict{String, Any}(
                "condition_id" => condition,
                "reason_id" => BLOCKER_REASONS[condition],
                "source_binding_ids" => BLOCKER_BINDINGS[condition],
            ) for condition in false_conditions
    ]
    sort!(blockers; by = blocker -> blocker["reason_id"])
    return Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-effr-prospective-endpoint-profile-result.v1",
            "canonicalization" => CANONICALIZATION,
            "content_sha256" => repeat("0", 64),
        ),
        "preflight" => Dict{String, Any}(
            "contract_id" => CONTRACT_ID,
            "status" => CURRENT_STATUS,
            "claim_ceiling" => CLAIM_CEILING,
            "profile_physical_sha256" => EXPECTED_PROFILE_PHYSICAL_SHA256,
            "profile_content_sha256" => EXPECTED_PROFILE_SEMANTIC_SHA256,
            "source_binding_count" => length(SOURCE_SPECS),
            "false_condition_count" => length(false_conditions),
            "blocking_reason_count" => length(blockers),
            "model_input_profile_ready" => false,
            "truth_loaded" => false,
            "model_executed" => false,
            "network_access_performed" => false,
            "filesystem_write_performed" => false,
        ),
        "estimand" => Dict{String, Any}(
            "estimand_id" => ESTIMAND_ID,
            "role" => "MODEL_INPUT_ONLY",
            "status" => "DEFINED_NOT_APPROVED",
            "first_public_bytes" => false,
            "current_state" => false,
            "final_daily_state" => false,
            "no_later_correction" => false,
        ),
        "coverage" => Dict{String, Any}(
            "q3_endpoint_history_candidate_start" => "2026-07-01",
            "q3_endpoint_history_candidate_end" => "2026-10-29",
            "q3_endpoint_history_candidate_row_count" => 84,
            "q3_endpoint_history_verified_row_count" => 0,
            "q3_candidate_establishes_complete_training_history" => false,
            "model_input_training_history_selector_start" => "UNDECIDED",
            "minimum_training_quarters" => 60,
            "methodology_change_effective_date" => "2016-03-01",
            "pre_post_2016_regime_treatment_approved" => false,
            "restart_campaign_start_date" => "2026-08-10",
            "restart_required_slot_count" => 115,
            "restart_verified_slot_count" => 0,
            "restart_establishes_daily_history" => false,
            "restart_establishes_first_public_bytes" => false,
            "predecessor_planned_slot_count" => 117,
            "predecessor_missed_slot_count" => 1,
            "predecessor_complete" => false,
            "cross_campaign_combination_allowed" => false,
            "semantic_supersession_decision_present" => false,
            "qualified_leaf_dispatch_present" => false,
        ),
        "retention" => Dict{String, Any}(
            "prospective_v2_retain_until_utc" => "2031-10-30T14:00:00Z",
            "h12_target_reference_period" => "2029Q3",
            "h12_target_period_end_utc" => "2029-09-30T23:59:59Z",
            "mature_truth_lag_months" => 60,
            "mathematical_minimum_retain_until_utc" =>
                MATHEMATICAL_RETENTION_MINIMUM,
            "conservative_custody_cushion_until_utc" =>
                CONSERVATIVE_RETENTION_CUSHION,
            "successor_retention_contract_present" => false,
            "prospective_v2_retention_sufficient" => false,
            "verified_mature_receipt_plus_audit_policy_covered" => false,
        ),
        "readiness_conditions" => [
            Dict{String, Any}(
                    "condition_id" => key,
                    "satisfied" => conditions[key],
                    "blocking_reason_ids" =>
                    conditions[key] ? String[] : [BLOCKER_REASONS[key]],
                ) for key in sort!(collect(keys(conditions)))
        ],
        "blocking_reasons" => blockers,
        "limitations" => [
            "LOCAL_HASHES_DO_NOT_AUTHENTICATE_PUBLISHER_TRANSPORT_CLOCK_OR_IDENTITIES",
            "OBSERVED_STATE_V3_PERMANENTLY_NONADMITTING",
            "PREDECESSOR_117_SLOT_CAMPAIGN_IRRECOVERABLY_INCOMPLETE",
            "PROSPECTIVE_V2_CONTRACT_DRAFT_UNAPPROVED",
            "PROSPECTIVE_V2_VERIFIER_NOT_IMPLEMENTED_FAIL_CLOSED",
            "Q3_84_DATE_ENDPOINT_CANDIDATE_IS_NOT_A_60_QUARTER_MODEL_TRAINING_UNIVERSE",
            "RESTART_115_SLOT_LINEAGE_IS_DIAGNOSTIC_NOT_DAILY_HISTORY_OR_FIRST_PUBLICATION",
            "SELF_REHASHED_APPROVAL_LINEAGE_OR_RETENTION_RECEIPT_NOT_SUFFICIENT",
            "SUCCESSOR_EVIDENCE_ADMISSION_COMPILER_NOT_IMPLEMENTED",
        ],
        "gates" => deepcopy(profile["gates"]),
        "prohibited_actions" => copy(PROHIBITED_ACTIONS),
    )
end

function _result_semantic_sha256(result)
    copy_result = deepcopy(result)
    pop!(copy_result["artifact"], "content_sha256", nothing)
    return canonical_sha256(copy_result)
end

function compile_current_result()
    profile = validate_profile()
    result = _result_without_hash(profile)
    result["artifact"]["content_sha256"] = _result_semantic_sha256(result)
    return validate_current_result(result)
end

function validate_current_result(result)
    document = _expect_table(result, "result")
    expected = _result_without_hash(validate_profile())
    expected["artifact"]["content_sha256"] = _result_semantic_sha256(expected)
    document == expected ||
        fail("RESULT_REPLAY_MISMATCH", "result", "does not exactly replay current evidence")
    document["artifact"]["content_sha256"] == EXPECTED_CURRENT_RESULT_SHA256 ||
        fail("OUT_OF_BAND_RESULT_PIN_MISMATCH", "result", "result identity changed")
    return document
end

end
