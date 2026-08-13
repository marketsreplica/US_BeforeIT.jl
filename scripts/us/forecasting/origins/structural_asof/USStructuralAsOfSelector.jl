module USStructuralAsOfSelector

using Dates
using SHA

export StructuralAsOfError,
    build_structural_asof_receipt,
    canonical_sha256,
    refuse_prohibited_action,
    validate_receipt,
    validate_release_set,
    validate_registry_binding

const SCHEMA_VERSION = "beforeit-us-structural-asof-receipt.v1"
const CONTRACT_ID = "beforeit-us-structural-asof-selector.v1"
const CANONICALIZATION = "utf8-length-prefixed-sorted-map-array-order.v1"
const ORIGIN_ELIGIBLE_AS_OF = "ORIGIN_ELIGIBLE_AS_OF"
const RETROSPECTIVE_HINDSIGHT_SELECTED =
    "RETROSPECTIVE_HINDSIGHT_SELECTED"
const SELECTION_TRACKS =
    Set([ORIGIN_ELIGIBLE_AS_OF, RETROSPECTIVE_HINDSIGHT_SELECTED])
const REQUIRED_COMPONENTS = [
    "io_or_supply_use",
    "fixed_assets",
    "firm_counts",
    "qcew_or_labor",
    "sector_or_financial_accounts",
    "classification_maps",
]
const REQUIRED_COMPONENT_SET = Set(REQUIRED_COMPONENTS)
const QUALITY_STATUSES = Set(["APPROVED", "DUBIOUS", "REJECTED"])
const REQUIRED_QUALITY_STATUS = "APPROVED"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
const TIMESTAMP_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const REGISTRY_MODULE_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "vintages",
        "USSourceReleaseRegistry.jl",
    ),
)
const REGISTRY_SCHEMA_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "vintages",
        "source_release_inventory.schema.toml",
    ),
)
const REGISTRY_MODULE_SHA256 =
    "7f705a07cc7b2531f1ee2bbceb1b80f1a0a32abae77794802bd502bbe7f4493e"
const REGISTRY_SCHEMA_SHA256 =
    "1782f8943e942a2ec2dc4998eafa460c194cdad2207246754efc7b6c64892673"
const RELEASE_KEYS = Set(
    [
        "component_id",
        "release_event_id",
        "source_id",
        "dataset_id",
        "source_release_id",
        "observation_period_start",
        "observation_period_end",
        "release_timestamp_utc",
        "availability_timestamp_utc",
        "raw_sha256",
        "mapping_version",
        "classification_system",
        "classification_version",
        "quality_status",
    ],
)
const COMPONENT_RECEIPT_KEYS = Set(
    [
        "component_id",
        "release_event_id",
        "source_id",
        "dataset_id",
        "source_release_id",
        "observation_period_start",
        "observation_period_end",
        "observation_period_end_boundary_utc",
        "release_timestamp_utc",
        "availability_timestamp_utc",
        "raw_sha256",
        "mapping_version",
        "classification_system",
        "classification_version",
        "quality_status",
        "structural_age_days_signed",
        "structural_age_seconds_signed",
        "release_age_seconds_signed",
        "availability_age_seconds_signed",
        "future_observation_period_relative_to_origin",
        "released_after_origin",
        "available_after_origin",
        "eligible_at_origin",
        "carry_valid_from_utc",
        "carry_until_rule",
    ],
)
const RECEIPT_KEYS = Set(
    [
        "schema_version",
        "contract_id",
        "canonicalization",
        "digest_algorithm",
        "registry_module_sha256",
        "registry_schema_sha256",
        "origin_timestamp_utc",
        "selection_track",
        "selection_rule",
        "carry_rule",
        "required_components",
        "considered_evidence_sha256",
        "components",
        "blockers",
        "structural_information_set_eligible",
        "retrospective_hindsight_selected",
        "future_period_structure_present",
        "pseudo_oos_structural_compatibility",
        "origin_admissible",
        "promotion_eligible",
        "accuracy_evidence",
        "receipt_nonadmitting",
        "content_sha256",
    ],
)
const PROHIBITED_ACTIONS = Set(
    [
        :origin_admission,
        :promotion,
        :score,
        :accuracy_claim,
        :production,
        :relabel_hindsight_as_pseudo_oos,
        :relabel_future_structure_as_pseudo_oos,
    ],
)

struct StructuralAsOfError <: Exception
    message::String
end

Base.showerror(io::IO, error::StructuralAsOfError) =
    print(io, error.message)

fail(location, message) =
    throw(StructuralAsOfError("$location: $message"))

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function read_exact_regular_file(path, expected_sha256, location)
    isfile(path) || fail(location, "is missing")
    islink(path) && fail(location, "must not be a symbolic link")
    before = stat(path)
    before.nlink == 1 || fail(location, "must have exactly one hard link")
    bytes = read(path)
    after = stat(path)
    (
        before.device,
        before.inode,
        before.size,
        before.mtime,
        before.ctime,
    ) == (
        after.device,
        after.inode,
        after.size,
        after.mtime,
        after.ctime,
    ) || fail(location, "changed while being read")
    sha256_hex(bytes) == expected_sha256 ||
        fail(location, "SHA-256 changed")
    return bytes
end

const Registry = let
    bytes = read_exact_regular_file(
        REGISTRY_MODULE_PATH,
        REGISTRY_MODULE_SHA256,
        "pinned source-release registry",
    )
    loaded = Base.include_string(@__MODULE__, String(bytes), REGISTRY_MODULE_PATH)
    loaded isa Module || fail(
        "pinned source-release registry",
        "did not load as a module",
    )
    loaded
end

canonical_sha256(value) = Registry.canonical_sha256(value)

function validate_registry_binding()
    read_exact_regular_file(
        REGISTRY_MODULE_PATH,
        REGISTRY_MODULE_SHA256,
        "pinned source-release registry",
    )
    read_exact_regular_file(
        REGISTRY_SCHEMA_PATH,
        REGISTRY_SCHEMA_SHA256,
        "pinned source-release schema",
    )
    getfield(Registry, :CANONICALIZATION) == CANONICALIZATION ||
        fail("registry binding", "canonicalization changed")
    return true
end

function expect_exact_keys(value, expected, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    actual = Set(String.(keys(value)))
    missing = sort!(collect(setdiff(expected, actual)))
    unknown = sort!(collect(setdiff(actual, expected)))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown keys: $(join(unknown, ", "))")
    return value
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
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

function expect_timestamp(value, location)
    text = expect_string(value, location)
    occursin(TIMESTAMP_PATTERN, text) ||
        fail(location, "must be a canonical second-precision UTC timestamp")
    parsed = try
        DateTime(text[1:(end - 1)], RFC3339_SECONDS_FORMAT)
    catch
        fail(location, "is not a valid UTC timestamp")
    end
    Dates.format(parsed, RFC3339_SECONDS_FORMAT) * "Z" == text ||
        fail(location, "is not a canonical UTC timestamp")
    return parsed
end

function expect_date(value, location)
    text = expect_string(value, location)
    occursin(DATE_PATTERN, text) ||
        fail(location, "must use canonical YYYY-MM-DD")
    parsed = try
        Date(text)
    catch
        fail(location, "is not a valid date")
    end
    string(parsed) == text || fail(location, "is not canonical")
    return parsed
end

function seconds_between(later::DateTime, earlier::DateTime)
    milliseconds = Dates.value(later - earlier)
    milliseconds % 1000 == 0 ||
        fail("timestamp arithmetic", "lost exact-second precision")
    return milliseconds ÷ 1000
end

observation_end_boundary(observation_end::Date) =
    DateTime(observation_end + Day(1)) - Second(1)

function normalize_release(release, index)
    location = "releases[$index]"
    table = expect_exact_keys(release, RELEASE_KEYS, location)
    component = expect_identifier(table["component_id"], "$location.component_id")
    component in REQUIRED_COMPONENT_SET ||
        fail("$location.component_id", "is not a required structural component")
    normalized = Dict{String, Any}()
    for key in (
            "component_id",
            "release_event_id",
            "source_id",
            "dataset_id",
            "source_release_id",
            "mapping_version",
            "classification_system",
            "classification_version",
        )
        normalized[key] = expect_identifier(table[key], "$location.$key")
    end
    normalized["raw_sha256"] =
        expect_hash(table["raw_sha256"], "$location.raw_sha256")
    quality = expect_string(table["quality_status"], "$location.quality_status")
    quality in QUALITY_STATUSES ||
        fail("$location.quality_status", "is not a closed quality status")
    normalized["quality_status"] = quality
    observation_start = expect_date(
        table["observation_period_start"],
        "$location.observation_period_start",
    )
    observation_end = expect_date(
        table["observation_period_end"],
        "$location.observation_period_end",
    )
    observation_start <= observation_end ||
        fail(location, "observation period is reversed")
    release_time = expect_timestamp(
        table["release_timestamp_utc"],
        "$location.release_timestamp_utc",
    )
    availability_time = expect_timestamp(
        table["availability_timestamp_utc"],
        "$location.availability_timestamp_utc",
    )
    release_time <= availability_time ||
        fail(location, "availability precedes official release")
    observation_end_boundary(observation_end) <= release_time ||
        fail(location, "release precedes the observation-period end")
    normalized["observation_period_start"] = string(observation_start)
    normalized["observation_period_end"] = string(observation_end)
    normalized["release_timestamp_utc"] =
        Dates.format(release_time, RFC3339_SECONDS_FORMAT) * "Z"
    normalized["availability_timestamp_utc"] =
        Dates.format(availability_time, RFC3339_SECONDS_FORMAT) * "Z"
    return normalized
end

function release_rank(release)
    return (
        expect_timestamp(
            release["availability_timestamp_utc"],
            "release availability timestamp",
        ),
        expect_timestamp(
            release["release_timestamp_utc"],
            "release timestamp",
        ),
    )
end

function validate_release_set(releases)
    releases isa AbstractVector || fail("releases", "must be an array")
    isempty(releases) && fail("releases", "must not be empty")
    normalized = [normalize_release(release, index) for (index, release) in enumerate(releases)]
    release_ids = String[release["release_event_id"] for release in normalized]
    length(unique(release_ids)) == length(release_ids) ||
        fail("releases", "release_event_id values must be globally unique")
    for component in REQUIRED_COMPONENTS
        candidates = filter(release -> release["component_id"] == component, normalized)
        isempty(candidates) && fail(component, "has no supplied release")
    end
    sort!(
        normalized;
        by = release -> (
            findfirst(==(release["component_id"]), REQUIRED_COMPONENTS),
            release_rank(release),
            release["release_event_id"],
        ),
    )
    return normalized
end

function eligible_at_origin(release, origin)
    observation_end = Date(release["observation_period_end"])
    observation_boundary = observation_end_boundary(observation_end)
    release_time = expect_timestamp(
        release["release_timestamp_utc"],
        "release timestamp",
    )
    availability_time = expect_timestamp(
        release["availability_timestamp_utc"],
        "availability timestamp",
    )
    return observation_boundary <= origin &&
        release_time <= origin && availability_time <= origin
end

function unique_latest(candidates, component)
    isempty(candidates) && fail(component, "has no eligible structural release")
    ranks = release_rank.(candidates)
    latest = maximum(ranks)
    winners = findall(==(latest), ranks)
    length(winners) == 1 ||
        fail(component, "latest structural release is ambiguous")
    winner = candidates[only(winners)]
    winner["quality_status"] == REQUIRED_QUALITY_STATUS ||
        fail(component, "latest structural release quality is not APPROVED")
    return winner
end

function component_receipt(release, origin)
    release_time = expect_timestamp(
        release["release_timestamp_utc"],
        "release timestamp",
    )
    availability_time = expect_timestamp(
        release["availability_timestamp_utc"],
        "availability timestamp",
    )
    observation_end = Date(release["observation_period_end"])
    observation_boundary = observation_end_boundary(observation_end)
    eligible = eligible_at_origin(release, origin)
    return Dict{String, Any}(
        "component_id" => release["component_id"],
        "release_event_id" => release["release_event_id"],
        "source_id" => release["source_id"],
        "dataset_id" => release["dataset_id"],
        "source_release_id" => release["source_release_id"],
        "observation_period_start" => release["observation_period_start"],
        "observation_period_end" => release["observation_period_end"],
        "observation_period_end_boundary_utc" =>
            Dates.format(observation_boundary, RFC3339_SECONDS_FORMAT) * "Z",
        "release_timestamp_utc" => release["release_timestamp_utc"],
        "availability_timestamp_utc" => release["availability_timestamp_utc"],
        "raw_sha256" => release["raw_sha256"],
        "mapping_version" => release["mapping_version"],
        "classification_system" => release["classification_system"],
        "classification_version" => release["classification_version"],
        "quality_status" => release["quality_status"],
        "structural_age_days_signed" =>
            Dates.value(Date(origin) - observation_end),
        "structural_age_seconds_signed" =>
            seconds_between(origin, observation_boundary),
        "release_age_seconds_signed" => seconds_between(origin, release_time),
        "availability_age_seconds_signed" =>
            seconds_between(origin, availability_time),
        "future_observation_period_relative_to_origin" =>
            observation_boundary > origin,
        "released_after_origin" => release_time > origin,
        "available_after_origin" => availability_time > origin,
        "eligible_at_origin" => eligible,
        "carry_valid_from_utc" => release["availability_timestamp_utc"],
        "carry_until_rule" =>
            "EXCLUSIVE_NEXT_ORIGIN_ELIGIBLE_RELEASE_FOR_COMPONENT",
    )
end

function receipt_payload(receipt)
    result = deepcopy(receipt)
    pop!(result, "content_sha256", nothing)
    return result
end

function with_content_sha256(receipt)
    result = receipt_payload(receipt)
    result["content_sha256"] = canonical_sha256(result)
    return result
end

function build_structural_asof_receipt(
        releases,
        origin_timestamp_utc;
        selection_track = ORIGIN_ELIGIBLE_AS_OF,
    )
    validate_registry_binding()
    track = expect_string(selection_track, "selection_track")
    track in SELECTION_TRACKS ||
        fail("selection_track", "is not a closed structural selection track")
    origin = expect_timestamp(origin_timestamp_utc, "origin_timestamp_utc")
    normalized = validate_release_set(releases)
    selected = Dict{String, Any}[]
    considered = Dict{String, Any}[]
    for component in REQUIRED_COMPONENTS
        candidates = filter(release -> release["component_id"] == component, normalized)
        eligible = filter(release -> eligible_at_origin(release, origin), candidates)
        if track == ORIGIN_ELIGIBLE_AS_OF
            append!(considered, eligible)
            push!(selected, unique_latest(eligible, component))
        else
            append!(considered, candidates)
            push!(selected, unique_latest(candidates, component))
        end
    end
    component_rows = component_receipt.(selected, Ref(origin))
    all_origin_eligible = all(row -> row["eligible_at_origin"], component_rows)
    future_period_present = any(
        row -> row["future_observation_period_relative_to_origin"],
        component_rows,
    )
    hindsight = track == RETROSPECTIVE_HINDSIGHT_SELECTED
    structural_eligible = !hindsight && all_origin_eligible && !future_period_present
    blockers = [
        "NONADMITTING_SELECTOR_RECEIPT",
        "OTHER_ORIGIN_GATES_NOT_EVALUATED",
        "LOCAL_UNAUTHENTICATED_FIXITY_ASSERTIONS",
    ]
    hindsight && push!(blockers, "RETROSPECTIVE_HINDSIGHT_SELECTION_NONPROMOTABLE")
    future_period_present &&
        push!(blockers, "FUTURE_OBSERVATION_PERIOD_RELATIVE_TO_ORIGIN")
    any(row -> row["released_after_origin"], component_rows) &&
        push!(blockers, "POST_ORIGIN_RELEASE_SELECTED")
    any(row -> row["available_after_origin"], component_rows) &&
        push!(blockers, "POST_ORIGIN_AVAILABILITY_SELECTED")
    receipt = Dict{String, Any}(
        "schema_version" => SCHEMA_VERSION,
        "contract_id" => CONTRACT_ID,
        "canonicalization" => CANONICALIZATION,
        "digest_algorithm" => "sha256",
        "registry_module_sha256" => REGISTRY_MODULE_SHA256,
        "registry_schema_sha256" => REGISTRY_SCHEMA_SHA256,
        "origin_timestamp_utc" =>
            Dates.format(origin, RFC3339_SECONDS_FORMAT) * "Z",
        "selection_track" => track,
        "selection_rule" =>
            "unique_maximum_availability_then_release_timestamp_per_component",
        "carry_rule" =>
            "selected_release_applies_until_exclusive_next_origin_eligible_release_for_component",
        "required_components" => copy(REQUIRED_COMPONENTS),
        "considered_evidence_sha256" => canonical_sha256(considered),
        "components" => component_rows,
        "blockers" => blockers,
        "structural_information_set_eligible" => structural_eligible,
        "retrospective_hindsight_selected" => hindsight,
        "future_period_structure_present" => future_period_present,
        "pseudo_oos_structural_compatibility" => structural_eligible ?
            "COMPATIBLE_PENDING_ALL_OTHER_GATES" :
            "FORBIDDEN",
        "origin_admissible" => false,
        "promotion_eligible" => false,
        "accuracy_evidence" => false,
        "receipt_nonadmitting" => true,
    )
    validate_registry_binding()
    return with_content_sha256(receipt)
end

function validate_receipt(receipt, releases)
    table = expect_exact_keys(receipt, RECEIPT_KEYS, "receipt")
    expect_hash(table["content_sha256"], "receipt.content_sha256")
    canonical_sha256(receipt_payload(table)) == table["content_sha256"] ||
        fail("receipt.content_sha256", "does not match canonical content")
    components = table["components"]
    components isa AbstractVector || fail("receipt.components", "must be an array")
    length(components) == length(REQUIRED_COMPONENTS) ||
        fail("receipt.components", "must contain all required components")
    for (index, component) in enumerate(components)
        expect_exact_keys(component, COMPONENT_RECEIPT_KEYS, "receipt.components[$index]")
    end
    rebuilt = build_structural_asof_receipt(
        releases,
        table["origin_timestamp_utc"];
        selection_track = table["selection_track"],
    )
    canonical_sha256(rebuilt) == canonical_sha256(table) ||
        fail("receipt", "does not rederive from the supplied release evidence")
    return table
end

function refuse_prohibited_action(action::Symbol)
    action in PROHIBITED_ACTIONS ||
        fail("prohibited action", "unknown action $(String(action))")
    return fail(
        "prohibited action",
        "structural-as-of selector forbids $(String(action))",
    )
end

end # module
