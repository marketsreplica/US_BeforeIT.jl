module USSourceReleaseRegistry

using Dates
using SHA
using TOML

export SourceReleaseValidationError,
    append_retrieval_event!,
    asof_releases,
    build_cannot_run_record,
    canonical_sha256,
    evaluate_completeness,
    inventory_sha256,
    load_inventory,
    load_requirements,
    requirements_sha256,
    stamp_inventory_sha256!,
    stamp_requirements_sha256!,
    validate_cannot_run_record,
    validate_inventory,
    validate_requirements

const INVENTORY_SCHEMA = "beforeit-us-source-release-inventory.v1"
const REQUIREMENTS_SCHEMA = "beforeit-us-source-completeness-requirements.v1"
const EVALUATION_SCHEMA = "beforeit-us-source-completeness-evaluation.v1"
const CANNOT_RUN_SCHEMA = "beforeit-us-source-cannot-run.v1"
const CANONICALIZATION = "utf8-length-prefixed-sorted-map-array-order.v1"
const PROTOCOL_SHA256 =
    "88519e5b04936f528396cf5243ff270844d0d38651fd84fc3b1c76fef997b584"
const EVIDENCE_VERIFIER_STATUS = "NOT_IMPLEMENTED_FAIL_CLOSED"
const REQUIREMENTS_APPROVAL_STATUS = "DRAFT_UNAPPROVED"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const QUALITY_STATUSES = Set(["APPROVED", "DUBIOUS", "REJECTED"])
const COMPLETENESS_QUALITY_STATUSES = Set(["APPROVED", "DUBIOUS"])
const INVENTORY_STATUSES = Set(["OPEN", "INCOMPLETE", "COMPLETE"])
const REQUIREMENT_BLOCK_KINDS = Set(["source", "target", "structural"])
const BLOCK_KINDS = union(REQUIREMENT_BLOCK_KINDS, Set(["registry"]))
const BLOCK_STATUSES =
    Set(["AVAILABLE", "MISSING", "UNACCEPTABLE_QUALITY", "AMBIGUOUS"])
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const TIMESTAMP_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"

const INVENTORY_ROOT_KEYS = Set(
    [
        "artifact",
        "release_events",
        "admissible_origin_timestamps_utc",
        "audit_facts",
    ],
)
const INVENTORY_HEADER_KEYS = Set(
    [
        "schema_version",
        "inventory_id",
        "status",
        "evidence_verifier_status",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const EVENT_KEYS = Set(
    [
        "retrieval_event_id",
        "release_event_id",
        "source_id",
        "source_family",
        "dataset_id",
        "series_id",
        "release_timestamp_utc",
        "availability_timestamp_utc",
        "availability_basis",
        "availability_evidence_locator",
        "retrieved_at_utc",
        "raw_sha256",
        "source_release_id",
        "source_locator",
        "retrieval_locator",
        "reference_period_start",
        "reference_period_end",
        "realtime_start_utc",
        "realtime_end_utc",
        "frequency",
        "unit",
        "seasonal_adjustment",
        "annual_rate_flag",
        "stock_flow_index_rate",
        "price_basis",
        "transformation_version",
        "classification",
        "classification_vintage",
        "quality_status",
    ],
)
const RETRIEVAL_FIELDS = Set(
    [
        "retrieval_event_id",
        "retrieved_at_utc",
        "retrieval_locator",
    ],
)
const RELEASE_IMMUTABLE_FIELDS =
    sort!(collect(setdiff(EVENT_KEYS, RETRIEVAL_FIELDS)))
const SNAPSHOT_FIELDS = (
    "source_id",
    "source_family",
    "dataset_id",
    "series_id",
    "reference_period_start",
    "reference_period_end",
    "frequency",
    "unit",
    "seasonal_adjustment",
    "annual_rate_flag",
    "stock_flow_index_rate",
    "price_basis",
    "transformation_version",
    "classification",
    "classification_vintage",
)
const AUDIT_FACT_KEYS = Set(
    [
        "fact_id",
        "finding",
        "evidence_locator",
        "implication",
        "distribution_status",
    ],
)
const DISTRIBUTION_STATUSES = Set(
    [
        "TRACKED_DISTRIBUTABLE",
        "EXTERNAL_ARCHIVE",
        "IGNORED_LOCAL_ONLY_NOT_REGISTERED",
        "NOT_AVAILABLE",
    ],
)

const REQUIREMENTS_ROOT_KEYS = Set(["artifact", "blocks"])
const REQUIREMENTS_HEADER_KEYS = Set(
    [
        "schema_version",
        "requirements_id",
        "protocol_sha256",
        "approval_status",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const BLOCK_KEYS = Set(
    [
        "block_id",
        "block_kind",
        "source_id",
        "source_family",
        "dataset_id",
        "series_id",
        "frequency",
        "unit",
        "seasonal_adjustment",
        "annual_rate_flag",
        "stock_flow_index_rate",
        "price_basis",
        "transformation_version",
        "classification",
        "classification_vintage",
        "required_reference_period_start",
        "required_reference_period_end",
        "allowed_quality_statuses",
    ],
)
const BLOCK_RESULT_KEYS = Set(
    [
        "block_id",
        "block_kind",
        "status",
        "reason_code",
        "candidate_release_event_ids",
        "selected_release_event_id",
        "selected_raw_sha256",
        "selected_availability_timestamp_utc",
    ],
)
const CANNOT_RUN_KEYS = Set(
    [
        "schema_version",
        "record_id",
        "origin_timestamp_utc",
        "status",
        "complete",
        "origin_evidence_sha256",
        "requirements_sha256",
        "evaluation_sha256",
        "unavailable_block_ids",
        "reason_codes",
        "block_results",
        "content_sha256",
    ],
)

struct SourceReleaseValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::SourceReleaseValidationError) =
    print(io, error.message)

fail(location, message) =
    throw(SourceReleaseValidationError("$location: $message"))

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

function expect_array(value, location; allow_empty = true)
    value isa AbstractVector || fail(location, "must be an array")
    !allow_empty && isempty(value) && fail(location, "must not be empty")
    return value
end

function expect_string_array(
        value,
        location;
        allow_empty = true,
        identifier = false,
    )
    values = expect_array(value, location; allow_empty)
    strings = [
        identifier ?
            expect_identifier(entry, "$location[$index]") :
            expect_string(entry, "$location[$index]")
            for (index, entry) in enumerate(values)
    ]
    length(Set(strings)) == length(strings) ||
        fail(location, "must not contain duplicates")
    return strings
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

function canonical_sha256(value)
    io = IOBuffer()
    _canonical_write(io, value)
    return bytes2hex(sha256(take!(io)))
end

function artifact_sha256(value, location)
    artifact = deepcopy(expect_table(value, location))
    header = expect_table(
        get(artifact, "artifact", nothing),
        "$location.artifact",
    )
    pop!(header, "content_sha256", nothing)
    return canonical_sha256(artifact)
end

inventory_sha256(inventory) =
    artifact_sha256(inventory, "inventory")
requirements_sha256(requirements) =
    artifact_sha256(requirements, "requirements")

function stamp_inventory_sha256!(inventory)
    artifact = expect_table(inventory, "inventory")
    header = expect_table(
        get(artifact, "artifact", nothing),
        "inventory.artifact",
    )
    header["content_sha256"] = inventory_sha256(artifact)
    return artifact
end

function stamp_requirements_sha256!(requirements)
    artifact = expect_table(requirements, "requirements")
    header = expect_table(
        get(artifact, "artifact", nothing),
        "requirements.artifact",
    )
    header["content_sha256"] = requirements_sha256(artifact)
    return artifact
end

function load_inventory(path::AbstractString)
    inventory = TOML.parsefile(path)
    validate_inventory(inventory)
    return inventory
end

function load_requirements(path::AbstractString)
    requirements = TOML.parsefile(path)
    validate_requirements(requirements)
    return requirements
end

event_value(event, field) = event[field]

function event_tuple(event, fields)
    return Tuple(event_value(event, field) for field in fields)
end

function validate_event(event, location)
    event = expect_exact_keys(event, EVENT_KEYS, location)
    for key in (
            "retrieval_event_id",
            "release_event_id",
            "source_id",
            "source_family",
            "dataset_id",
            "series_id",
            "source_release_id",
            "transformation_version",
        )
        expect_identifier(event[key], "$location.$key")
    end
    for key in (
            "availability_basis",
            "availability_evidence_locator",
            "source_locator",
            "retrieval_locator",
            "frequency",
            "unit",
            "seasonal_adjustment",
            "stock_flow_index_rate",
            "price_basis",
            "classification",
            "classification_vintage",
        )
        expect_string(event[key], "$location.$key")
    end

    release_timestamp = expect_timestamp(
        event["release_timestamp_utc"],
        "$location.release_timestamp_utc",
    )
    availability_timestamp = expect_timestamp(
        event["availability_timestamp_utc"],
        "$location.availability_timestamp_utc",
    )
    retrieved_at = expect_timestamp(
        event["retrieved_at_utc"],
        "$location.retrieved_at_utc",
    )
    realtime_start = expect_timestamp(
        event["realtime_start_utc"],
        "$location.realtime_start_utc",
    )
    realtime_end = expect_timestamp(
        event["realtime_end_utc"],
        "$location.realtime_end_utc",
    )
    release_timestamp <= availability_timestamp ||
        fail(
        location,
        "availability timestamp precedes the official release timestamp",
    )
    availability_timestamp <= retrieved_at ||
        fail(location, "retrieval timestamp precedes availability")
    realtime_start == availability_timestamp ||
        fail(
        location,
        "realtime interval must start at the evidenced availability timestamp",
    )
    availability_timestamp < realtime_end ||
        fail(location, "availability is outside the realtime interval")
    realtime_start < realtime_end ||
        fail(location, "realtime interval must be nonempty and half-open")

    reference_start = expect_date(
        event["reference_period_start"],
        "$location.reference_period_start",
    )
    reference_end = expect_date(
        event["reference_period_end"],
        "$location.reference_period_end",
    )
    reference_start <= reference_end ||
        fail(location, "reference coverage is reversed")

    expect_hash(event["raw_sha256"], "$location.raw_sha256")
    expect_bool(event["annual_rate_flag"], "$location.annual_rate_flag")
    expect_one_of(
        event["quality_status"],
        QUALITY_STATUSES,
        "$location.quality_status",
    )
    return event
end

function validate_audit_fact(fact, location)
    fact = expect_exact_keys(fact, AUDIT_FACT_KEYS, location)
    expect_identifier(fact["fact_id"], "$location.fact_id")
    for key in ("finding", "evidence_locator", "implication")
        expect_string(fact[key], "$location.$key")
    end
    expect_one_of(
        fact["distribution_status"],
        DISTRIBUTION_STATUSES,
        "$location.distribution_status",
    )
    return fact
end

function validate_inventory(inventory)
    inventory =
        expect_exact_keys(inventory, INVENTORY_ROOT_KEYS, "inventory")
    header = expect_exact_keys(
        inventory["artifact"],
        INVENTORY_HEADER_KEYS,
        "inventory.artifact",
    )
    expect_string(header["schema_version"], "inventory.artifact.schema_version") ==
        INVENTORY_SCHEMA ||
        fail(
        "inventory.artifact.schema_version",
        "must equal $INVENTORY_SCHEMA",
    )
    expect_identifier(header["inventory_id"], "inventory.artifact.inventory_id")
    expect_one_of(
        header["status"],
        INVENTORY_STATUSES,
        "inventory.artifact.status",
    )
    expect_string(
        header["evidence_verifier_status"],
        "inventory.artifact.evidence_verifier_status",
    ) == EVIDENCE_VERIFIER_STATUS ||
        fail(
        "inventory.artifact.evidence_verifier_status",
        "must equal $EVIDENCE_VERIFIER_STATUS",
    )
    expect_string(
        header["canonicalization"],
        "inventory.artifact.canonicalization",
    ) == CANONICALIZATION ||
        fail(
        "inventory.artifact.canonicalization",
        "must equal $CANONICALIZATION",
    )
    expect_string(
        header["digest_algorithm"],
        "inventory.artifact.digest_algorithm",
    ) == "sha256" ||
        fail("inventory.artifact.digest_algorithm", "must equal sha256")
    stored_hash =
        expect_hash(header["content_sha256"], "inventory.artifact.content_sha256")

    origins = expect_array(
        inventory["admissible_origin_timestamps_utc"],
        "inventory.admissible_origin_timestamps_utc",
    )
    origin_strings = [
        begin
                expect_timestamp(
                    origin,
                    "inventory.admissible_origin_timestamps_utc[$index]",
                )
                String(origin)
            end
            for (index, origin) in enumerate(origins)
    ]
    issorted(origin_strings) ||
        fail(
        "inventory.admissible_origin_timestamps_utc",
        "must be sorted",
    )
    length(Set(origin_strings)) == length(origin_strings) ||
        fail(
        "inventory.admissible_origin_timestamps_utc",
        "must not contain duplicates",
    )

    facts = expect_array(inventory["audit_facts"], "inventory.audit_facts")
    fact_ids = String[]
    for (index, fact) in enumerate(facts)
        validate_audit_fact(fact, "inventory.audit_facts[$index]")
        push!(fact_ids, String(fact["fact_id"]))
    end
    issorted(fact_ids) ||
        fail("inventory.audit_facts", "must be sorted by fact_id")
    length(Set(fact_ids)) == length(fact_ids) ||
        fail("inventory.audit_facts", "contains duplicate fact_id values")

    events =
        expect_array(inventory["release_events"], "inventory.release_events")
    retrieval_ids = Set{String}()
    retrieval_keys = Set{Tuple}()
    release_groups = Dict{String, Vector{Any}}()
    event_order = Tuple{DateTime, String}[]
    ambiguity_keys = Dict{Tuple, String}()
    for (index, event) in enumerate(events)
        location = "inventory.release_events[$index]"
        validate_event(event, location)
        retrieval_id = String(event["retrieval_event_id"])
        retrieval_id in retrieval_ids &&
            fail(location, "duplicates retrieval_event_id $retrieval_id")
        push!(retrieval_ids, retrieval_id)

        retrieved_at =
            expect_timestamp(event["retrieved_at_utc"], "$location.retrieved_at_utc")
        push!(event_order, (retrieved_at, retrieval_id))
        retrieval_key = (
            String(event["release_event_id"]),
            String(event["retrieved_at_utc"]),
            String(event["retrieval_locator"]),
        )
        retrieval_key in retrieval_keys &&
            fail(location, "duplicates a retrieval event provenance tuple")
        push!(retrieval_keys, retrieval_key)

        release_id = String(event["release_event_id"])
        push!(get!(release_groups, release_id, Any[]), event)
    end
    issorted(event_order) ||
        fail(
        "inventory.release_events",
        "must be append-ordered by retrieved_at_utc then retrieval_event_id",
    )

    for (release_id, group) in release_groups
        first_event = first(group)
        for (index, event) in enumerate(Iterators.drop(group, 1))
            for field in RELEASE_IMMUTABLE_FIELDS
                event[field] == first_event[field] ||
                    fail(
                    "inventory.release_events",
                    "release_event_id $release_id changes immutable field $field on refetch $(index + 1)",
                )
            end
        end
        ambiguity_key = (
            event_tuple(first_event, SNAPSHOT_FIELDS)...,
            String(first_event["release_timestamp_utc"]),
            String(first_event["availability_timestamp_utc"]),
        )
        if haskey(ambiguity_keys, ambiguity_key)
            other = ambiguity_keys[ambiguity_key]
            fail(
                "inventory.release_events",
                "ambiguous release events $other and $release_id share a snapshot and exact release/availability timestamps",
            )
        end
        ambiguity_keys[ambiguity_key] = release_id
    end

    actual_hash = inventory_sha256(inventory)
    stored_hash == actual_hash ||
        fail(
        "inventory.artifact.content_sha256",
        "does not match canonical inventory hash $actual_hash",
    )
    return inventory
end

function validate_block(block, location)
    block = expect_exact_keys(block, BLOCK_KEYS, location)
    for key in (
            "block_id",
            "source_id",
            "source_family",
            "dataset_id",
            "series_id",
            "transformation_version",
        )
        expect_identifier(block[key], "$location.$key")
    end
    expect_one_of(
        block["block_kind"],
        REQUIREMENT_BLOCK_KINDS,
        "$location.block_kind",
    )
    for key in (
            "frequency",
            "unit",
            "seasonal_adjustment",
            "stock_flow_index_rate",
            "price_basis",
            "classification",
            "classification_vintage",
        )
        expect_string(block[key], "$location.$key")
    end
    expect_bool(block["annual_rate_flag"], "$location.annual_rate_flag")
    reference_start = expect_date(
        block["required_reference_period_start"],
        "$location.required_reference_period_start",
    )
    reference_end = expect_date(
        block["required_reference_period_end"],
        "$location.required_reference_period_end",
    )
    reference_start <= reference_end ||
        fail(location, "required reference coverage is reversed")
    statuses = expect_string_array(
        block["allowed_quality_statuses"],
        "$location.allowed_quality_statuses";
        allow_empty = false,
    )
    all(status -> status in COMPLETENESS_QUALITY_STATUSES, statuses) ||
        fail(
        location,
        "allowed_quality_statuses may contain only APPROVED or DUBIOUS",
    )
    issorted(statuses) ||
        fail(location, "allowed_quality_statuses must be sorted")
    return block
end

function validate_requirements(requirements)
    requirements = expect_exact_keys(
        requirements,
        REQUIREMENTS_ROOT_KEYS,
        "requirements",
    )
    header = expect_exact_keys(
        requirements["artifact"],
        REQUIREMENTS_HEADER_KEYS,
        "requirements.artifact",
    )
    expect_string(
        header["schema_version"],
        "requirements.artifact.schema_version",
    ) == REQUIREMENTS_SCHEMA ||
        fail(
        "requirements.artifact.schema_version",
        "must equal $REQUIREMENTS_SCHEMA",
    )
    expect_identifier(
        header["requirements_id"],
        "requirements.artifact.requirements_id",
    )
    expect_hash(
        header["protocol_sha256"],
        "requirements.artifact.protocol_sha256",
    ) == PROTOCOL_SHA256 ||
        fail(
        "requirements.artifact.protocol_sha256",
        "must equal $PROTOCOL_SHA256",
    )
    expect_string(
        header["approval_status"],
        "requirements.artifact.approval_status",
    ) == REQUIREMENTS_APPROVAL_STATUS ||
        fail(
        "requirements.artifact.approval_status",
        "must equal $REQUIREMENTS_APPROVAL_STATUS",
    )
    expect_string(
        header["canonicalization"],
        "requirements.artifact.canonicalization",
    ) == CANONICALIZATION ||
        fail(
        "requirements.artifact.canonicalization",
        "must equal $CANONICALIZATION",
    )
    expect_string(
        header["digest_algorithm"],
        "requirements.artifact.digest_algorithm",
    ) == "sha256" ||
        fail("requirements.artifact.digest_algorithm", "must equal sha256")
    stored_hash = expect_hash(
        header["content_sha256"],
        "requirements.artifact.content_sha256",
    )

    blocks =
        expect_array(requirements["blocks"], "requirements.blocks"; allow_empty = false)
    block_ids = String[]
    selectors = Set{Tuple}()
    kinds = Set{String}()
    for (index, block) in enumerate(blocks)
        validate_block(block, "requirements.blocks[$index]")
        push!(block_ids, String(block["block_id"]))
        push!(kinds, String(block["block_kind"]))
        selector = (
            event_tuple(
                block,
                (
                    "block_kind",
                    "source_id",
                    "source_family",
                    "dataset_id",
                    "series_id",
                    "frequency",
                    "unit",
                    "seasonal_adjustment",
                    "annual_rate_flag",
                    "stock_flow_index_rate",
                    "price_basis",
                    "transformation_version",
                    "classification",
                    "classification_vintage",
                    "required_reference_period_start",
                    "required_reference_period_end",
                ),
            )...,
            Tuple(String.(block["allowed_quality_statuses"])),
        )
        selector in selectors &&
            fail(
            "requirements.blocks[$index]",
            "duplicates another completeness selector",
        )
        push!(selectors, selector)
    end
    issorted(block_ids) ||
        fail("requirements.blocks", "must be sorted by block_id")
    length(Set(block_ids)) == length(block_ids) ||
        fail("requirements.blocks", "contains duplicate block_id values")
    kinds == REQUIREMENT_BLOCK_KINDS ||
        fail(
        "requirements.blocks",
        "must include source, target, and structural block kinds",
    )

    actual_hash = requirements_sha256(requirements)
    stored_hash == actual_hash ||
        fail(
        "requirements.artifact.content_sha256",
        "does not match canonical requirements hash $actual_hash",
    )
    return requirements
end

function append_retrieval_event!(inventory, event)
    validate_inventory(inventory)
    candidate = deepcopy(inventory)
    candidate_event = Dict{String, Any}(
        String(key) => deepcopy(value) for (key, value) in pairs(event)
    )
    push!(candidate["release_events"], candidate_event)
    stamp_inventory_sha256!(candidate)
    validate_inventory(candidate)
    inventory["release_events"] = candidate["release_events"]
    inventory["artifact"]["content_sha256"] =
        candidate["artifact"]["content_sha256"]
    return inventory
end

function logical_releases(inventory)
    groups = Dict{String, Vector{Any}}()
    for event in inventory["release_events"]
        release_id = String(event["release_event_id"])
        push!(get!(groups, release_id, Any[]), event)
    end
    summaries = Dict{String, Any}[]
    summary_fields = sort!(collect(setdiff(EVENT_KEYS, RETRIEVAL_FIELDS)))
    for release_id in sort!(collect(keys(groups)))
        group = groups[release_id]
        first_event = first(group)
        summary = Dict{String, Any}(
            field => deepcopy(first_event[field]) for field in summary_fields
        )
        summary["archive_retrieval_event_id"] =
            String(first_event["retrieval_event_id"])
        summary["archive_retrieved_at_utc"] =
            String(first_event["retrieved_at_utc"])
        summary["archive_retrieval_locator"] =
            String(first_event["retrieval_locator"])
        push!(summaries, summary)
    end
    return summaries
end

function _asof_all(
        inventory,
        origin_timestamp_utc;
        include_expired_latest = false,
    )
    validate_inventory(inventory)
    origin = expect_timestamp(origin_timestamp_utc, "origin_timestamp_utc")
    eligible = Dict{String, Any}[]
    for release in logical_releases(inventory)
        release_timestamp = expect_timestamp(
            release["release_timestamp_utc"],
            "release.release_timestamp_utc",
        )
        availability_timestamp = expect_timestamp(
            release["availability_timestamp_utc"],
            "release.availability_timestamp_utc",
        )
        realtime_start = expect_timestamp(
            release["realtime_start_utc"],
            "release.realtime_start_utc",
        )
        if release_timestamp <= origin &&
                availability_timestamp <= origin &&
                realtime_start <= origin
            push!(eligible, release)
        end
    end

    grouped = Dict{Tuple, Vector{Dict{String, Any}}}()
    for release in eligible
        key = event_tuple(release, SNAPSHOT_FIELDS)
        push!(get!(grouped, key, Dict{String, Any}[]), release)
    end
    selected = Dict{String, Any}[]
    for key in sort!(collect(keys(grouped)); by = canonical_sha256)
        candidates = grouped[key]
        ranks = [
            (
                    expect_timestamp(
                        candidate["availability_timestamp_utc"],
                        "release.availability_timestamp_utc",
                    ),
                    expect_timestamp(
                        candidate["release_timestamp_utc"],
                        "release.release_timestamp_utc",
                    ),
                )
                for candidate in candidates
        ]
        latest = maximum(ranks)
        winners = findall(==(latest), ranks)
        length(winners) == 1 ||
            fail(
            "asof selection",
            "ambiguous latest release for snapshot $(repr(key))",
        )
        winner = candidates[only(winners)]
        realtime_end = expect_timestamp(
            winner["realtime_end_utc"],
            "release.realtime_end_utc",
        )
        (include_expired_latest || origin < realtime_end) &&
            push!(selected, winner)
    end
    sort!(selected; by = release -> String(release["release_event_id"]))
    return selected
end

function asof_releases(
        inventory,
        origin_timestamp_utc;
        allowed_quality_statuses = Set(["APPROVED"]),
    )
    statuses = Set(String.(collect(allowed_quality_statuses)))
    all(status -> status in QUALITY_STATUSES, statuses) ||
        fail(
        "allowed_quality_statuses",
        "contains an unknown quality status",
    )
    return [
        release for
            release in _asof_all(inventory, origin_timestamp_utc) if
            String(release["quality_status"]) in statuses
    ]
end

function block_matches_release(block, release)
    for field in (
            "source_id",
            "source_family",
            "dataset_id",
            "series_id",
            "frequency",
            "unit",
            "seasonal_adjustment",
            "annual_rate_flag",
            "stock_flow_index_rate",
            "price_basis",
            "transformation_version",
            "classification",
            "classification_vintage",
        )
        block[field] == release[field] || return false
    end
    required_start =
        expect_date(block["required_reference_period_start"], "block start")
    required_end =
        expect_date(block["required_reference_period_end"], "block end")
    release_start =
        expect_date(release["reference_period_start"], "release start")
    release_end = expect_date(release["reference_period_end"], "release end")
    return release_start <= required_start && required_end <= release_end
end

function empty_block_result(block, status, reason_code, candidates = String[])
    return Dict{String, Any}(
        "block_id" => String(block["block_id"]),
        "block_kind" => String(block["block_kind"]),
        "status" => status,
        "reason_code" => reason_code,
        "candidate_release_event_ids" => sort!(copy(candidates)),
        "selected_release_event_id" => "not_available",
        "selected_raw_sha256" => repeat("0", 64),
        "selected_availability_timestamp_utc" => "not_available",
    )
end

function registry_block_result(
        block_id,
        passed,
        failure_reason,
        evidence_sha256,
        origin_timestamp_utc,
    )
    block = Dict{String, Any}(
        "block_id" => block_id,
        "block_kind" => "registry",
    )
    passed ||
        return empty_block_result(
        block,
        "MISSING",
        failure_reason,
    )
    evidence_id = "registry-evidence-$block_id"
    return Dict{String, Any}(
        "block_id" => block_id,
        "block_kind" => "registry",
        "status" => "AVAILABLE",
        "reason_code" => "REGISTRY_CHECK_PASSED",
        "candidate_release_event_ids" => [evidence_id],
        "selected_release_event_id" => evidence_id,
        "selected_raw_sha256" => evidence_sha256,
        "selected_availability_timestamp_utc" => origin_timestamp_utc,
    )
end

function evaluate_block(block, releases, origin)
    matches = [
        release for release in releases if block_matches_release(block, release)
    ]
    isempty(matches) &&
        return empty_block_result(
        block,
        "MISSING",
        "NO_ELIGIBLE_RELEASE_COVERS_REQUIRED_REFERENCE_INTERVAL",
    )

    ranks = [
        (
                expect_timestamp(
                    release["availability_timestamp_utc"],
                    "release availability",
                ),
                expect_timestamp(
                    release["release_timestamp_utc"],
                    "release timestamp",
                ),
            )
            for release in matches
    ]
    latest = maximum(ranks)
    winner_indexes = findall(==(latest), ranks)
    candidate_ids =
        String[release["release_event_id"] for release in matches[winner_indexes]]
    if length(winner_indexes) != 1
        return empty_block_result(
            block,
            "AMBIGUOUS",
            "MULTIPLE_LATEST_RELEASES_COVER_REQUIRED_REFERENCE_INTERVAL",
            candidate_ids,
        )
    end

    selected = matches[only(winner_indexes)]
    realtime_end = expect_timestamp(
        selected["realtime_end_utc"],
        "selected release realtime_end_utc",
    )
    if origin >= realtime_end
        return empty_block_result(
            block,
            "MISSING",
            "LATEST_RELEASE_REALTIME_INTERVAL_EXPIRED",
            [String(selected["release_event_id"])],
        )
    end
    allowed = Set(String.(block["allowed_quality_statuses"]))
    if String(selected["quality_status"]) ∉ allowed
        return empty_block_result(
            block,
            "UNACCEPTABLE_QUALITY",
            "LATEST_RELEASE_QUALITY_NOT_ALLOWED",
            [String(selected["release_event_id"])],
        )
    end
    return Dict{String, Any}(
        "block_id" => String(block["block_id"]),
        "block_kind" => String(block["block_kind"]),
        "status" => "AVAILABLE",
        "reason_code" => "AVAILABLE_EXACT_AS_OF_ORIGIN",
        "candidate_release_event_ids" =>
            [String(selected["release_event_id"])],
        "selected_release_event_id" =>
            String(selected["release_event_id"]),
        "selected_raw_sha256" => String(selected["raw_sha256"]),
        "selected_availability_timestamp_utc" =>
            String(selected["availability_timestamp_utc"]),
    )
end

function with_content_sha256(value)
    result = deepcopy(value)
    pop!(result, "content_sha256", nothing)
    result["content_sha256"] = canonical_sha256(result)
    return result
end

function evaluate_completeness(
        inventory,
        requirements,
        origin_timestamp_utc,
    )
    validate_inventory(inventory)
    validate_requirements(requirements)
    origin = expect_timestamp(origin_timestamp_utc, "origin_timestamp_utc")
    canonical_origin =
        Dates.format(origin, RFC3339_SECONDS_FORMAT) * "Z"
    origin_declared = canonical_origin in
        String.(inventory["admissible_origin_timestamps_utc"])
    registry_manifest = Dict{String, Any}(
        "inventory_id" => String(inventory["artifact"]["inventory_id"]),
        "inventory_schema_version" =>
            String(inventory["artifact"]["schema_version"]),
        "inventory_status" => String(inventory["artifact"]["status"]),
        "evidence_verifier_status" =>
            String(inventory["artifact"]["evidence_verifier_status"]),
        "origin_timestamp_utc" => canonical_origin,
        "origin_declared" => origin_declared,
        "requirements_id" =>
            String(requirements["artifact"]["requirements_id"]),
        "requirements_approval_status" =>
            String(requirements["artifact"]["approval_status"]),
        "protocol_sha256" =>
            String(requirements["artifact"]["protocol_sha256"]),
    )
    registry_evidence_sha256 = canonical_sha256(registry_manifest)
    registry_results = [
        registry_block_result(
            "registry_evidence_verifier",
            inventory["artifact"]["evidence_verifier_status"] ==
                "IMPLEMENTED_AND_VERIFIED",
            "EVIDENCE_ARTIFACT_VERIFIER_NOT_IMPLEMENTED",
            registry_evidence_sha256,
            canonical_origin,
        ),
        registry_block_result(
            "registry_inventory_complete",
            inventory["artifact"]["status"] == "COMPLETE",
            "INVENTORY_STATUS_NOT_COMPLETE",
            registry_evidence_sha256,
            canonical_origin,
        ),
        registry_block_result(
            "registry_origin_declared",
            origin_declared,
            "ORIGIN_NOT_LISTED_AS_ADMISSIBLE",
            registry_evidence_sha256,
            canonical_origin,
        ),
        registry_block_result(
            "registry_requirements_approved",
            requirements["artifact"]["approval_status"] == "APPROVED",
            "REQUIREMENTS_NOT_APPROVED",
            registry_evidence_sha256,
            canonical_origin,
        ),
    ]
    releases = _asof_all(
        inventory,
        origin_timestamp_utc;
        include_expired_latest = true,
    )
    requirement_results = [
        evaluate_block(block, releases, origin)
            for block in requirements["blocks"]
    ]
    block_results = vcat(registry_results, requirement_results)
    candidate_complete =
        all(result -> result["status"] == "AVAILABLE", requirement_results)
    complete =
        all(result -> result["status"] == "AVAILABLE", block_results)
    status_counts = Dict{String, Any}(
        status => count(result -> result["status"] == status, block_results)
            for status in sort!(collect(BLOCK_STATUSES))
    )
    result = Dict{String, Any}(
        "schema_version" => EVALUATION_SCHEMA,
        "origin_timestamp_utc" => canonical_origin,
        "status" => complete ? "READY" : "CANNOT_RUN",
        "complete" => complete,
        "candidate_complete" => candidate_complete,
        "origin_evidence_sha256" => canonical_sha256(
            Dict{String, Any}(
                "registry_manifest" => registry_manifest,
                "block_results" => block_results,
            ),
        ),
        "requirements_sha256" => requirements_sha256(requirements),
        "status_counts" => status_counts,
        "block_results" => block_results,
    )
    return with_content_sha256(result)
end

function build_cannot_run_record(
        inventory,
        requirements,
        origin_timestamp_utc,
    )
    evaluation =
        evaluate_completeness(inventory, requirements, origin_timestamp_utc)
    evaluation["complete"] &&
        fail("cannot-run record", "cannot be built for a complete origin")
    unavailable = [
        result for result in evaluation["block_results"] if
            result["status"] != "AVAILABLE"
    ]
    unavailable_ids =
        sort!(String[result["block_id"] for result in unavailable])
    reason_codes =
        sort!(unique(String[result["reason_code"] for result in unavailable]))
    evaluation_hash = String(evaluation["content_sha256"])
    record = Dict{String, Any}(
        "schema_version" => CANNOT_RUN_SCHEMA,
        "record_id" => "cannot-run-" * evaluation_hash[1:16],
        "origin_timestamp_utc" => String(evaluation["origin_timestamp_utc"]),
        "status" => "CANNOT_RUN",
        "complete" => false,
        "origin_evidence_sha256" =>
            String(evaluation["origin_evidence_sha256"]),
        "requirements_sha256" =>
            String(evaluation["requirements_sha256"]),
        "evaluation_sha256" => evaluation_hash,
        "unavailable_block_ids" => unavailable_ids,
        "reason_codes" => reason_codes,
        "block_results" => deepcopy(evaluation["block_results"]),
    )
    return with_content_sha256(record)
end

function validate_block_result(result, location)
    result = expect_exact_keys(result, BLOCK_RESULT_KEYS, location)
    expect_identifier(result["block_id"], "$location.block_id")
    expect_one_of(result["block_kind"], BLOCK_KINDS, "$location.block_kind")
    expect_one_of(result["status"], BLOCK_STATUSES, "$location.status")
    expect_identifier(result["reason_code"], "$location.reason_code")
    candidates = expect_string_array(
        result["candidate_release_event_ids"],
        "$location.candidate_release_event_ids";
        identifier = true,
    )
    issorted(candidates) ||
        fail(location, "candidate_release_event_ids must be sorted")
    selected_id =
        expect_string(result["selected_release_event_id"], "$location.selected_release_event_id")
    selected_hash =
        expect_hash(result["selected_raw_sha256"], "$location.selected_raw_sha256")
    selected_availability = expect_string(
        result["selected_availability_timestamp_utc"],
        "$location.selected_availability_timestamp_utc",
    )
    if result["status"] == "AVAILABLE"
        expect_identifier(selected_id, "$location.selected_release_event_id")
        expect_timestamp(
            selected_availability,
            "$location.selected_availability_timestamp_utc",
        )
        selected_hash == repeat("0", 64) &&
            fail(location, "available block cannot use the null hash")
    else
        selected_id == "not_available" ||
            fail(location, "unavailable block must use not_available")
        selected_hash == repeat("0", 64) ||
            fail(location, "unavailable block must use the null hash")
        selected_availability == "not_available" ||
            fail(location, "unavailable block must use not_available")
    end
    return result
end

function validate_cannot_run_record(record)
    record =
        expect_exact_keys(record, CANNOT_RUN_KEYS, "cannot_run_record")
    expect_string(record["schema_version"], "cannot_run_record.schema_version") ==
        CANNOT_RUN_SCHEMA ||
        fail(
        "cannot_run_record.schema_version",
        "must equal $CANNOT_RUN_SCHEMA",
    )
    record_id =
        expect_identifier(record["record_id"], "cannot_run_record.record_id")
    expect_timestamp(
        record["origin_timestamp_utc"],
        "cannot_run_record.origin_timestamp_utc",
    )
    expect_string(record["status"], "cannot_run_record.status") ==
        "CANNOT_RUN" ||
        fail("cannot_run_record.status", "must equal CANNOT_RUN")
    expect_bool(record["complete"], "cannot_run_record.complete") === false ||
        fail("cannot_run_record.complete", "must be false")
    for key in (
            "origin_evidence_sha256",
            "requirements_sha256",
            "evaluation_sha256",
            "content_sha256",
        )
        expect_hash(record[key], "cannot_run_record.$key")
    end
    expected_record_id =
        "cannot-run-" * String(record["evaluation_sha256"])[1:16]
    record_id == expected_record_id ||
        fail(
        "cannot_run_record.record_id",
        "must be derived from evaluation_sha256 as $expected_record_id",
    )
    results = expect_array(
        record["block_results"],
        "cannot_run_record.block_results";
        allow_empty = false,
    )
    for (index, result) in enumerate(results)
        validate_block_result(
            result,
            "cannot_run_record.block_results[$index]",
        )
    end
    unavailable = sort!(
        String[
            result["block_id"] for result in results if
                result["status"] != "AVAILABLE"
        ],
    )
    recorded_unavailable = expect_string_array(
        record["unavailable_block_ids"],
        "cannot_run_record.unavailable_block_ids";
        allow_empty = false,
        identifier = true,
    )
    unavailable == recorded_unavailable ||
        fail(
        "cannot_run_record.unavailable_block_ids",
        "does not match unavailable block results",
    )
    expected_reasons = sort!(
        unique(
            String[
                result["reason_code"] for result in results if
                    result["status"] != "AVAILABLE"
            ],
        ),
    )
    recorded_reasons = expect_string_array(
        record["reason_codes"],
        "cannot_run_record.reason_codes";
        allow_empty = false,
        identifier = true,
    )
    expected_reasons == recorded_reasons ||
        fail(
        "cannot_run_record.reason_codes",
        "does not match unavailable block results",
    )
    canonical = deepcopy(record)
    stored_hash = pop!(canonical, "content_sha256")
    actual_hash = canonical_sha256(canonical)
    stored_hash == actual_hash ||
        fail(
        "cannot_run_record.content_sha256",
        "does not match canonical record hash $actual_hash",
    )
    return record
end

function validate_cannot_run_record(record, inventory, requirements)
    validate_cannot_run_record(record)
    expected = build_cannot_run_record(
        inventory,
        requirements,
        String(record["origin_timestamp_utc"]),
    )
    record == expected ||
        fail(
        "cannot_run_record",
        "does not match the supplied inventory, requirements, and origin",
    )
    return record
end

end
