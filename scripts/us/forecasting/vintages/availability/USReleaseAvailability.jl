module USReleaseAvailability

using Dates
using SHA
using TOML

export AvailabilityValidationError,
    AvailabilityWindow,
    TemporalGateResult,
    canonical_sha256,
    default_policy_path,
    default_timezone_semantics_path,
    derive_availability_window,
    evaluate_temporal_gate,
    evidence_sha256,
    load_policy,
    policy_sha256,
    stamp_evidence_sha256!,
    validate_evidence,
    validate_policy,
    validate_timezone_semantics,
    load_timezone_semantics,
    timezone_semantics_sha256

const POLICY_SCHEMA = "beforeit-us-release-availability-policy.v2"
const POLICY_ID = "beforeit-us-retrospective-release-availability.v2"
const POLICY_STATUS = "SEALED_RESEARCH_ONLY_FAIL_CLOSED"
const EVIDENCE_SCHEMA = "beforeit-us-release-availability-evidence.v2"
const RESULT_SCHEMA = "beforeit-us-release-temporal-gate-result.v2"
const CANONICALIZATION =
    "utf8-length-prefixed-sorted-map-array-order.v1"
const POLICY_CONTENT_SHA256 =
    "6af185c5fa8be4404a064294a0053eec093ca1a59cbc29f1a0566ada3364de11"
const TIMEZONE_SEMANTICS_SCHEMA = "beforeit-us-timezone-semantics.v1"
const TIMEZONE_SEMANTICS_ID =
    "beforeit-us-iana-tzdb-local-midnight-semantics.2026c.v1"
const TIMEZONE_SEMANTICS_CONTENT_SHA256 =
    "8ed940e6deb1a1aa0922369eb8b0ad327ecf52def3c37c7317f81b87afe7a174"
const TIMEZONE_SEMANTICS_LOCATOR =
    "urn:beforeit:iana-tzdb:2026c:us-release-availability-semantics"
const TIMEZONE_SEMANTICS_FILENAME =
    "timezone_semantics_iana_tzdb_2026c.toml"
const TIMEZONE_SEMANTICS_SOURCE_URL =
    "https://data.iana.org/time-zones/releases/tzdata2026c.tar.gz"
const TIMEZONE_SEMANTICS_SOURCE_SHA256 =
    "e4a178a4477f3d0ea77cc31828ff72aa38feff8d61aa13e7e99e142e9d902be4"
const TIMEZONE_SEMANTICS_START_DATE = Date(1997, 1, 1)
const TIMEZONE_SEMANTICS_END_DATE = Date(2036, 1, 1)

const EXACT_ASSERTION = "actual_public_timestamp"
const DATE_ASSERTION = "official_actual_release_date"
const DATE_RANGE_ASSERTION = "official_actual_release_date_range"
const ACCEPTED_ASSERTIONS =
    [EXACT_ASSERTION, DATE_ASSERTION, DATE_RANGE_ASSERTION]
const REJECTED_ASSERTIONS = [
    "schedule_only",
    "planned_release_date",
    "retrieval_timestamp",
    "unexplained_vintage_date",
    "route_level_claim",
    "unknown_timezone",
]

const EVIDENCE_SCOPE = "retrospective_research"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const TIMESTAMP_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"
const OFFSET_PATTERN = r"^([+-])(\d{2}):(\d{2})$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
const LOCATOR_PATTERN = r"^[A-Za-z][A-Za-z0-9+.-]*:\S+$"
const ZERO_SHA256 = repeat("0", 64)

const ALLOWED_TIMEZONE_OFFSETS = Dict(
    "UTC" => ["+00:00"],
    "America/New_York" => ["-05:00", "-04:00"],
    "America/Chicago" => ["-06:00", "-05:00"],
)
const ALLOWED_OFFSET_DELTA_MINUTES = [-60, 0, 60]

const POLICY_ROOT_KEYS = Set(
    [
        "artifact",
        "assertions",
        "interval",
        "timezone",
        "evidence",
        "scope",
    ],
)
const POLICY_ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "policy_id",
        "status",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const POLICY_ASSERTION_KEYS = Set(
    [
        "accepted_bases",
        "rejected_bases",
        "unknown_basis_action",
        "timestamp_precision",
        "exact_timestamp_semantics",
        "actual_date_semantics",
        "actual_date_range_semantics",
    ],
)
const POLICY_INTERVAL_KEYS = Set(
    [
        "boundary_semantics",
        "date_interval_lower_rule",
        "date_interval_upper_rule",
        "safe_not_before_rule",
        "origin_at_upper_bound_temporal_gate_allowed",
        "same_local_day_origin_allowed",
    ],
)
const POLICY_TIMEZONE_KEYS = Set(
    [
        "conversion_method",
        "runtime_tzdb_dependency_allowed",
        "source_timezone_required",
        "timezone_rules_evidence_required",
        "utc_offset_format",
        "minimum_utc_offset_minutes",
        "maximum_utc_offset_minutes",
        "allowed_offset_delta_minutes",
        "allowed_offsets",
        "semantics_artifact_locator",
        "semantics_artifact_sha256",
    ],
)
const TIMEZONE_SEMANTICS_ROOT_KEYS = Set(["artifact", "source", "coverage", "zones"])
const TIMEZONE_SEMANTICS_ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "artifact_id",
        "canonicalization",
        "digest_algorithm",
        "content_sha256",
    ],
)
const TIMEZONE_SEMANTICS_SOURCE_KEYS = Set(
    [
        "iana_tzdb_version",
        "iana_tzdb_source_url",
        "iana_tzdb_source_sha256",
        "generation_method",
    ],
)
const TIMEZONE_SEMANTICS_COVERAGE_KEYS = Set(
    [
        "local_date_start_inclusive",
        "local_date_end_inclusive",
        "local_midnight_semantics",
    ],
)
const TIMEZONE_SEMANTICS_ZONE_KEYS = Set(["segments"])
const TIMEZONE_SEMANTICS_SEGMENT_KEYS = Set(["local_date_start", "utc_offset"])
const POLICY_EVIDENCE_KEYS = Set(
    [
        "availability_evidence_sha256_required",
        "release_byte_evidence_sha256_required",
        "vintage_evidence_sha256_required",
        "evidence_content_sha256_required",
        "zero_sha256_allowed",
        "availability_release_byte_and_vintage_evidence_must_be_pairwise_distinct",
    ],
)
const POLICY_SCOPE_KEYS = Set(
    [
        "evidence_scope",
        "empirical_forecast_execution_allowed",
        "production_scoring_allowed",
        "origin_admission_authorized",
        "inventory_mutation_authorized",
        "temporal_gate_only",
    ],
)

const COMMON_EVIDENCE_KEYS = Set(
    [
        "schema_version",
        "evidence_id",
        "release_event_id",
        "source_id",
        "assertion_basis",
        "availability_evidence_locator",
        "availability_evidence_sha256",
        "release_byte_evidence_locator",
        "release_byte_evidence_sha256",
        "vintage_evidence_locator",
        "vintage_evidence_sha256",
        "evidence_scope",
        "empirical_forecast_execution_allowed",
        "production_scoring_allowed",
        "origin_admission_authorized",
        "inventory_mutation_authorized",
        "content_sha256",
    ],
)
const EXACT_EVIDENCE_KEYS =
    union(COMMON_EVIDENCE_KEYS, Set(["actual_public_timestamp_utc"]))
const DATE_EVIDENCE_KEYS = union(
    COMMON_EVIDENCE_KEYS,
    Set(
        [
            "local_start_date",
            "local_end_date",
            "source_timezone",
            "start_utc_offset",
            "end_utc_offset",
            "timezone_rules_evidence_locator",
            "timezone_rules_evidence_sha256",
        ],
    ),
)

struct AvailabilityValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::AvailabilityValidationError) =
    print(io, error.message)

"""
An evidenced publication window in UTC.

For exact timestamps, all three timestamps are equal and `interval_hours` is
zero. For official local dates or date ranges, the interval is half-open and
`safe_not_before_utc` equals its exclusive upper bound.
"""
struct AvailabilityWindow
    assertion_basis::String
    lower_bound_utc::DateTime
    upper_bound_utc::DateTime
    safe_not_before_utc::DateTime
    interval_hours::Int
    source_timezone::Union{Nothing, String}
end

"""
The output of the temporal gate. This type deliberately has no admission or
inventory-write capability, and its governance flags are always false.
"""
struct TemporalGateResult
    schema_version::String
    evidence_id::String
    release_event_id::String
    policy_sha256::String
    evidence_sha256::String
    evidence_scope::String
    origin_timestamp_utc::DateTime
    window::AvailabilityWindow
    temporal_gate_pass::Bool
    reason_code::String
    temporal_gate_only::Bool
    origin_admission_authorized::Bool
    empirical_forecast_execution_allowed::Bool
    production_scoring_allowed::Bool
    inventory_mutation_authorized::Bool
end

fail(location, message) =
    throw(AvailabilityValidationError("$location: $message"))

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

function expect_locator(value, location)
    text = expect_string(value, location)
    occursin(LOCATOR_PATTERN, text) ||
        fail(location, "must be a non-whitespace absolute locator")
    return text
end

function expect_nonzero_hash(value, location)
    text = expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    text == ZERO_SHA256 && fail(location, "must not be the zero SHA256")
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

function expect_equal(value, expected, location)
    value == expected ||
        fail(location, "must equal $(repr(expected))")
    return value
end

function expect_string_array(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    strings = [
        expect_string(entry, "$location[$index]")
            for (index, entry) in enumerate(value)
    ]
    length(Set(strings)) == length(strings) ||
        fail(location, "must not contain duplicates")
    return strings
end

function expect_integer_array(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    integers = [
        expect_integer(entry, "$location[$index]")
            for (index, entry) in enumerate(value)
    ]
    length(Set(integers)) == length(integers) ||
        fail(location, "must not contain duplicates")
    return integers
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
    year(date) <= 9998 ||
        fail(location, "must leave room for the exclusive next-day bound")
    return date
end

function expect_offset(value, location)
    text = expect_string(value, location)
    match_result = match(OFFSET_PATTERN, text)
    match_result === nothing ||
        length(match_result.captures) == 3 ||
        fail(location, "must use signed ±HH:MM form")
    match_result === nothing &&
        fail(location, "must use signed ±HH:MM form")
    sign_text, hours_text, minutes_text = match_result.captures
    hours = parse(Int, hours_text)
    minutes = parse(Int, minutes_text)
    minutes < 60 || fail(location, "minutes must be below 60")
    total = 60 * hours + minutes
    total <= 14 * 60 ||
        fail(location, "must be between -14:00 and +14:00")
    sign_text == "-" && (total = -total)
    return text, total
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

function policy_sha256(policy)
    artifact = deepcopy(expect_table(policy, "policy"))
    header = expect_table(
        get(artifact, "artifact", nothing),
        "policy.artifact",
    )
    pop!(header, "content_sha256", nothing)
    return canonical_sha256(artifact)
end

function timezone_semantics_sha256(semantics)
    artifact = deepcopy(expect_table(semantics, "timezone_semantics"))
    header = expect_table(
        get(artifact, "artifact", nothing),
        "timezone_semantics.artifact",
    )
    pop!(header, "content_sha256", nothing)
    return canonical_sha256(artifact)
end

function evidence_sha256(evidence)
    artifact = deepcopy(expect_table(evidence, "evidence"))
    pop!(artifact, "content_sha256", nothing)
    return canonical_sha256(artifact)
end

function stamp_evidence_sha256!(evidence)
    artifact = expect_table(evidence, "evidence")
    artifact["content_sha256"] = evidence_sha256(artifact)
    return artifact
end

default_policy_path() = joinpath(@__DIR__, "release_availability_policy.toml")
default_timezone_semantics_path() =
    joinpath(@__DIR__, TIMEZONE_SEMANTICS_FILENAME)

function validate_timezone_semantics(semantics)
    artifact = expect_exact_keys(
        semantics,
        TIMEZONE_SEMANTICS_ROOT_KEYS,
        "timezone_semantics",
    )
    header = expect_exact_keys(
        artifact["artifact"],
        TIMEZONE_SEMANTICS_ARTIFACT_KEYS,
        "timezone_semantics.artifact",
    )
    source = expect_exact_keys(
        artifact["source"],
        TIMEZONE_SEMANTICS_SOURCE_KEYS,
        "timezone_semantics.source",
    )
    coverage = expect_exact_keys(
        artifact["coverage"],
        TIMEZONE_SEMANTICS_COVERAGE_KEYS,
        "timezone_semantics.coverage",
    )
    zones = expect_exact_keys(
        artifact["zones"],
        keys(ALLOWED_TIMEZONE_OFFSETS),
        "timezone_semantics.zones",
    )
    for (field, expected) in (
            ("schema_version", TIMEZONE_SEMANTICS_SCHEMA),
            ("artifact_id", TIMEZONE_SEMANTICS_ID),
            ("canonicalization", CANONICALIZATION),
            ("digest_algorithm", "sha256"),
        )
        expect_equal(
            expect_string(header[field], "timezone_semantics.artifact.$field"),
            expected,
            "timezone_semantics.artifact.$field",
        )
    end
    stored_hash = expect_nonzero_hash(
        header["content_sha256"],
        "timezone_semantics.artifact.content_sha256",
    )
    for (field, expected) in (
            ("iana_tzdb_version", "2026c"),
            ("iana_tzdb_source_url", TIMEZONE_SEMANTICS_SOURCE_URL),
            ("iana_tzdb_source_sha256", TIMEZONE_SEMANTICS_SOURCE_SHA256),
            (
                "generation_method",
                "zic-compiled-iana-source-plus-python-zoneinfo-local-midnight-scan.v1",
            ),
        )
        expect_equal(
            expect_string(source[field], "timezone_semantics.source.$field"),
            expected,
            "timezone_semantics.source.$field",
        )
    end
    start_date = expect_date(
        coverage["local_date_start_inclusive"],
        "timezone_semantics.coverage.local_date_start_inclusive",
    )
    end_date = expect_date(
        coverage["local_date_end_inclusive"],
        "timezone_semantics.coverage.local_date_end_inclusive",
    )
    expect_equal(
        start_date,
        TIMEZONE_SEMANTICS_START_DATE,
        "timezone_semantics.coverage.local_date_start_inclusive",
    )
    expect_equal(
        end_date,
        TIMEZONE_SEMANTICS_END_DATE,
        "timezone_semantics.coverage.local_date_end_inclusive",
    )
    expect_equal(
        expect_string(
            coverage["local_midnight_semantics"],
            "timezone_semantics.coverage.local_midnight_semantics",
        ),
        "offset_at_source_local_midnight",
        "timezone_semantics.coverage.local_midnight_semantics",
    )
    for name in sort!(collect(keys(ALLOWED_TIMEZONE_OFFSETS)))
        zone = expect_exact_keys(
            zones[name],
            TIMEZONE_SEMANTICS_ZONE_KEYS,
            "timezone_semantics.zones.$name",
        )
        segments = zone["segments"]
        segments isa AbstractVector ||
            fail("timezone_semantics.zones.$name.segments", "must be an array")
        isempty(segments) &&
            fail("timezone_semantics.zones.$name.segments", "must not be empty")
        previous_date = nothing
        for (index, segment) in enumerate(segments)
            row = expect_exact_keys(
                segment,
                TIMEZONE_SEMANTICS_SEGMENT_KEYS,
                "timezone_semantics.zones.$name.segments[$index]",
            )
            segment_date = expect_date(
                row["local_date_start"],
                "timezone_semantics.zones.$name.segments[$index].local_date_start",
            )
            (start_date <= segment_date <= end_date) ||
                fail(
                "timezone_semantics.zones.$name.segments[$index].local_date_start",
                "must lie within the sealed coverage range",
            )
            if previous_date === nothing
                segment_date == start_date ||
                    fail(
                    "timezone_semantics.zones.$name.segments[$index].local_date_start",
                    "first segment must start at the sealed coverage start",
                )
            else
                segment_date > previous_date ||
                    fail(
                    "timezone_semantics.zones.$name.segments[$index].local_date_start",
                    "must be strictly increasing",
                )
            end
            offset, _ = expect_offset(
                row["utc_offset"],
                "timezone_semantics.zones.$name.segments[$index].utc_offset",
            )
            offset in ALLOWED_TIMEZONE_OFFSETS[name] ||
                fail(
                "timezone_semantics.zones.$name.segments[$index].utc_offset",
                "is not allowed for $name",
            )
            previous_date = segment_date
        end
        if name == "UTC"
            length(segments) == 1 ||
                fail("timezone_semantics.zones.UTC.segments", "must have one segment")
            segments[1]["utc_offset"] == "+00:00" ||
                fail("timezone_semantics.zones.UTC.segments", "must be +00:00")
        end
    end
    actual_hash = timezone_semantics_sha256(artifact)
    stored_hash == actual_hash ||
        fail(
        "timezone_semantics.artifact.content_sha256",
        "does not match canonical timezone-semantics hash $actual_hash",
    )
    actual_hash == TIMEZONE_SEMANTICS_CONTENT_SHA256 ||
        fail(
        "timezone_semantics.artifact.content_sha256",
        "does not match the module-pinned timezone-semantics hash",
    )
    return artifact
end

function load_timezone_semantics(
        path::AbstractString = default_timezone_semantics_path(),
    )
    semantics = TOML.parsefile(path)
    validate_timezone_semantics(semantics)
    return semantics
end

function sealed_offset_at_local_midnight(semantics, source_timezone, local_date)
    TIMEZONE_SEMANTICS_START_DATE <= local_date <= TIMEZONE_SEMANTICS_END_DATE ||
        fail(
        "evidence.local_start_date",
        "is outside the pinned timezone-semantics coverage range " *
            "$(TIMEZONE_SEMANTICS_START_DATE) through $(TIMEZONE_SEMANTICS_END_DATE)",
    )
    segments = semantics["zones"][source_timezone]["segments"]
    selected = nothing
    for segment in segments
        segment_date = expect_date(
            segment["local_date_start"],
            "timezone_semantics segment",
        )
        segment_date <= local_date || break
        selected = segment
    end
    selected === nothing &&
        fail("evidence.local_start_date", "has no sealed timezone-semantics segment")
    return expect_offset(selected["utc_offset"], "timezone_semantics segment.utc_offset")
end

function validate_policy(policy)
    artifact = expect_exact_keys(policy, POLICY_ROOT_KEYS, "policy")
    header = expect_exact_keys(
        artifact["artifact"],
        POLICY_ARTIFACT_KEYS,
        "policy.artifact",
    )
    assertions = expect_exact_keys(
        artifact["assertions"],
        POLICY_ASSERTION_KEYS,
        "policy.assertions",
    )
    interval = expect_exact_keys(
        artifact["interval"],
        POLICY_INTERVAL_KEYS,
        "policy.interval",
    )
    timezone = expect_exact_keys(
        artifact["timezone"],
        POLICY_TIMEZONE_KEYS,
        "policy.timezone",
    )
    evidence = expect_exact_keys(
        artifact["evidence"],
        POLICY_EVIDENCE_KEYS,
        "policy.evidence",
    )
    scope = expect_exact_keys(
        artifact["scope"],
        POLICY_SCOPE_KEYS,
        "policy.scope",
    )

    expect_equal(
        expect_string(header["schema_version"], "policy.artifact.schema_version"),
        POLICY_SCHEMA,
        "policy.artifact.schema_version",
    )
    expect_equal(
        expect_string(header["policy_id"], "policy.artifact.policy_id"),
        POLICY_ID,
        "policy.artifact.policy_id",
    )
    expect_equal(
        expect_string(header["status"], "policy.artifact.status"),
        POLICY_STATUS,
        "policy.artifact.status",
    )
    expect_equal(
        expect_string(
            header["canonicalization"],
            "policy.artifact.canonicalization",
        ),
        CANONICALIZATION,
        "policy.artifact.canonicalization",
    )
    expect_equal(
        expect_string(
            header["digest_algorithm"],
            "policy.artifact.digest_algorithm",
        ),
        "sha256",
        "policy.artifact.digest_algorithm",
    )
    stored_hash = expect_nonzero_hash(
        header["content_sha256"],
        "policy.artifact.content_sha256",
    )

    expect_equal(
        expect_string_array(
            assertions["accepted_bases"],
            "policy.assertions.accepted_bases",
        ),
        ACCEPTED_ASSERTIONS,
        "policy.assertions.accepted_bases",
    )
    expect_equal(
        expect_string_array(
            assertions["rejected_bases"],
            "policy.assertions.rejected_bases",
        ),
        REJECTED_ASSERTIONS,
        "policy.assertions.rejected_bases",
    )
    for (field, expected) in (
            ("unknown_basis_action", "reject"),
            ("timestamp_precision", "rfc3339_utc_exact_second"),
            ("exact_timestamp_semantics", "actual_public_instant"),
            (
                "actual_date_semantics",
                "source_local_calendar_day_half_open",
            ),
            (
                "actual_date_range_semantics",
                "inclusive_source_local_dates_half_open",
            ),
        )
        expect_equal(
            expect_string(
                assertions[field],
                "policy.assertions.$field",
            ),
            expected,
            "policy.assertions.$field",
        )
    end

    for (field, expected) in (
            ("boundary_semantics", "half_open"),
            (
                "date_interval_lower_rule",
                "local_start_date_midnight_using_sealed_start_offset",
            ),
            (
                "date_interval_upper_rule",
                "day_after_local_end_date_midnight_using_sealed_end_offset",
            ),
            (
                "safe_not_before_rule",
                "exact_instant_or_date_interval_exclusive_upper_bound",
            ),
        )
        expect_equal(
            expect_string(interval[field], "policy.interval.$field"),
            expected,
            "policy.interval.$field",
        )
    end
    expect_equal(
        expect_bool(
            interval["origin_at_upper_bound_temporal_gate_allowed"],
            "policy.interval.origin_at_upper_bound_temporal_gate_allowed",
        ),
        true,
        "policy.interval.origin_at_upper_bound_temporal_gate_allowed",
    )
    expect_equal(
        expect_bool(
            interval["same_local_day_origin_allowed"],
            "policy.interval.same_local_day_origin_allowed",
        ),
        false,
        "policy.interval.same_local_day_origin_allowed",
    )

    expect_equal(
        expect_string(
            timezone["conversion_method"],
            "policy.timezone.conversion_method",
        ),
        "sealed_iana_tzdb_local_midnight_table_no_runtime_tzdb",
        "policy.timezone.conversion_method",
    )
    for field in (
            "runtime_tzdb_dependency_allowed",
            "source_timezone_required",
            "timezone_rules_evidence_required",
        )
        expected = field == "runtime_tzdb_dependency_allowed" ? false : true
        expect_equal(
            expect_bool(timezone[field], "policy.timezone.$field"),
            expected,
            "policy.timezone.$field",
        )
    end
    expect_equal(
        expect_string(
            timezone["utc_offset_format"],
            "policy.timezone.utc_offset_format",
        ),
        "signed_hh_mm",
        "policy.timezone.utc_offset_format",
    )
    expect_equal(
        expect_integer(
            timezone["minimum_utc_offset_minutes"],
            "policy.timezone.minimum_utc_offset_minutes",
        ),
        -840,
        "policy.timezone.minimum_utc_offset_minutes",
    )
    expect_equal(
        expect_integer(
            timezone["maximum_utc_offset_minutes"],
            "policy.timezone.maximum_utc_offset_minutes",
        ),
        840,
        "policy.timezone.maximum_utc_offset_minutes",
    )
    expect_equal(
        expect_integer_array(
            timezone["allowed_offset_delta_minutes"],
            "policy.timezone.allowed_offset_delta_minutes",
        ),
        ALLOWED_OFFSET_DELTA_MINUTES,
        "policy.timezone.allowed_offset_delta_minutes",
    )
    allowed_offsets = expect_exact_keys(
        timezone["allowed_offsets"],
        keys(ALLOWED_TIMEZONE_OFFSETS),
        "policy.timezone.allowed_offsets",
    )
    for name in sort!(collect(keys(ALLOWED_TIMEZONE_OFFSETS)))
        expect_equal(
            expect_string_array(
                allowed_offsets[name],
                "policy.timezone.allowed_offsets.$name",
            ),
            ALLOWED_TIMEZONE_OFFSETS[name],
            "policy.timezone.allowed_offsets.$name",
        )
    end
    expect_equal(
        expect_locator(
            timezone["semantics_artifact_locator"],
            "policy.timezone.semantics_artifact_locator",
        ),
        TIMEZONE_SEMANTICS_LOCATOR,
        "policy.timezone.semantics_artifact_locator",
    )
    expect_equal(
        expect_nonzero_hash(
            timezone["semantics_artifact_sha256"],
            "policy.timezone.semantics_artifact_sha256",
        ),
        TIMEZONE_SEMANTICS_CONTENT_SHA256,
        "policy.timezone.semantics_artifact_sha256",
    )
    semantics = load_timezone_semantics()
    expect_equal(
        timezone_semantics_sha256(semantics),
        TIMEZONE_SEMANTICS_CONTENT_SHA256,
        "policy.timezone.semantics_artifact_sha256",
    )

    for field in (
            "availability_evidence_sha256_required",
            "release_byte_evidence_sha256_required",
            "vintage_evidence_sha256_required",
            "evidence_content_sha256_required",
            "availability_release_byte_and_vintage_evidence_must_be_pairwise_distinct",
        )
        expect_equal(
            expect_bool(evidence[field], "policy.evidence.$field"),
            true,
            "policy.evidence.$field",
        )
    end
    expect_equal(
        expect_bool(
            evidence["zero_sha256_allowed"],
            "policy.evidence.zero_sha256_allowed",
        ),
        false,
        "policy.evidence.zero_sha256_allowed",
    )

    expect_equal(
        expect_string(
            scope["evidence_scope"],
            "policy.scope.evidence_scope",
        ),
        EVIDENCE_SCOPE,
        "policy.scope.evidence_scope",
    )
    expect_equal(
        expect_bool(scope["temporal_gate_only"], "policy.scope.temporal_gate_only"),
        true,
        "policy.scope.temporal_gate_only",
    )
    for field in (
            "empirical_forecast_execution_allowed",
            "production_scoring_allowed",
            "origin_admission_authorized",
            "inventory_mutation_authorized",
        )
        expect_equal(
            expect_bool(scope[field], "policy.scope.$field"),
            false,
            "policy.scope.$field",
        )
    end

    actual_hash = policy_sha256(artifact)
    stored_hash == actual_hash ||
        fail(
        "policy.artifact.content_sha256",
        "does not match canonical policy hash $actual_hash",
    )
    actual_hash == POLICY_CONTENT_SHA256 ||
        fail(
        "policy.artifact.content_sha256",
        "does not match the module-pinned sealed policy hash",
    )
    return artifact
end

function load_policy(path::AbstractString = default_policy_path())
    policy = TOML.parsefile(path)
    validate_policy(policy)
    return policy
end

function assertion_keys(assertion_basis)
    assertion_basis == EXACT_ASSERTION && return EXACT_EVIDENCE_KEYS
    assertion_basis in (DATE_ASSERTION, DATE_RANGE_ASSERTION) &&
        return DATE_EVIDENCE_KEYS
    assertion_basis in REJECTED_ASSERTIONS &&
        fail(
        "evidence.assertion_basis",
        "$assertion_basis is explicitly rejected by policy",
    )
    return fail(
        "evidence.assertion_basis",
        "unknown availability assertion; policy is fail-closed",
    )
end

function validate_common_evidence(evidence)
    expect_equal(
        expect_string(
            evidence["schema_version"],
            "evidence.schema_version",
        ),
        EVIDENCE_SCHEMA,
        "evidence.schema_version",
    )
    expect_identifier(evidence["evidence_id"], "evidence.evidence_id")
    expect_identifier(
        evidence["release_event_id"],
        "evidence.release_event_id",
    )
    expect_identifier(evidence["source_id"], "evidence.source_id")

    availability_locator = expect_locator(
        evidence["availability_evidence_locator"],
        "evidence.availability_evidence_locator",
    )
    availability_hash = expect_nonzero_hash(
        evidence["availability_evidence_sha256"],
        "evidence.availability_evidence_sha256",
    )
    byte_locator = expect_locator(
        evidence["release_byte_evidence_locator"],
        "evidence.release_byte_evidence_locator",
    )
    byte_hash = expect_nonzero_hash(
        evidence["release_byte_evidence_sha256"],
        "evidence.release_byte_evidence_sha256",
    )
    vintage_locator = expect_locator(
        evidence["vintage_evidence_locator"],
        "evidence.vintage_evidence_locator",
    )
    vintage_hash = expect_nonzero_hash(
        evidence["vintage_evidence_sha256"],
        "evidence.vintage_evidence_sha256",
    )

    length(Set((availability_locator, byte_locator, vintage_locator))) == 3 ||
        fail(
        "evidence",
        "availability, release-byte, and vintage evidence locators " *
            "must be pairwise distinct",
    )
    length(Set((availability_hash, byte_hash, vintage_hash))) == 3 ||
        fail(
        "evidence",
        "availability, release-byte, and vintage evidence hashes " *
            "must be pairwise distinct",
    )
    expect_equal(
        expect_string(evidence["evidence_scope"], "evidence.evidence_scope"),
        EVIDENCE_SCOPE,
        "evidence.evidence_scope",
    )
    for field in (
            "empirical_forecast_execution_allowed",
            "production_scoring_allowed",
            "origin_admission_authorized",
            "inventory_mutation_authorized",
        )
        expect_equal(
            expect_bool(evidence[field], "evidence.$field"),
            false,
            "evidence.$field",
        )
    end
    expect_nonzero_hash(
        evidence["content_sha256"],
        "evidence.content_sha256",
    )
    return nothing
end

function validate_date_evidence(policy, evidence, assertion_basis)
    start_date = expect_date(
        evidence["local_start_date"],
        "evidence.local_start_date",
    )
    end_date = expect_date(
        evidence["local_end_date"],
        "evidence.local_end_date",
    )
    if assertion_basis == DATE_ASSERTION
        start_date == end_date ||
            fail(
            "evidence.local_end_date",
            "must equal local_start_date for a single-date assertion",
        )
    else
        start_date < end_date ||
            fail(
            "evidence.local_end_date",
            "must follow local_start_date for a date-range assertion",
        )
    end
    start_date >= TIMEZONE_SEMANTICS_START_DATE ||
        fail(
        "evidence.local_start_date",
        "is outside the pinned timezone-semantics coverage range",
    )
    end_date + Day(1) <= TIMEZONE_SEMANTICS_END_DATE ||
        fail(
        "evidence.local_end_date",
        "requires a day-after-end offset outside the pinned timezone-semantics coverage range",
    )

    source_timezone = expect_string(
        evidence["source_timezone"],
        "evidence.source_timezone",
    )
    allowed_offsets = policy["timezone"]["allowed_offsets"]
    haskey(allowed_offsets, source_timezone) ||
        fail(
        "evidence.source_timezone",
        "is unknown to the sealed policy",
    )
    start_offset, start_minutes = expect_offset(
        evidence["start_utc_offset"],
        "evidence.start_utc_offset",
    )
    end_offset, end_minutes = expect_offset(
        evidence["end_utc_offset"],
        "evidence.end_utc_offset",
    )
    start_offset in allowed_offsets[source_timezone] ||
        fail(
        "evidence.start_utc_offset",
        "is not allowed for $source_timezone by the sealed policy",
    )
    end_offset in allowed_offsets[source_timezone] ||
        fail(
        "evidence.end_utc_offset",
        "is not allowed for $source_timezone by the sealed policy",
    )
    offset_delta = end_minutes - start_minutes
    offset_delta in policy["timezone"]["allowed_offset_delta_minutes"] ||
        fail(
        "evidence.end_utc_offset",
        "offset transition must be -60, 0, or +60 minutes",
    )

    timezone_locator = expect_locator(
        evidence["timezone_rules_evidence_locator"],
        "evidence.timezone_rules_evidence_locator",
    )
    timezone_hash = expect_nonzero_hash(
        evidence["timezone_rules_evidence_sha256"],
        "evidence.timezone_rules_evidence_sha256",
    )
    expect_equal(
        timezone_locator,
        policy["timezone"]["semantics_artifact_locator"],
        "evidence.timezone_rules_evidence_locator",
    )
    expect_equal(
        timezone_hash,
        policy["timezone"]["semantics_artifact_sha256"],
        "evidence.timezone_rules_evidence_sha256",
    )
    timezone_locator != evidence["release_byte_evidence_locator"] ||
        fail(
        "evidence.timezone_rules_evidence_locator",
        "must be distinct from release-byte evidence",
    )
    timezone_locator != evidence["vintage_evidence_locator"] ||
        fail(
        "evidence.timezone_rules_evidence_locator",
        "must be distinct from vintage evidence",
    )
    timezone_hash != evidence["release_byte_evidence_sha256"] ||
        fail(
        "evidence.timezone_rules_evidence_sha256",
        "must be distinct from release-byte evidence",
    )
    timezone_hash != evidence["vintage_evidence_sha256"] ||
        fail(
        "evidence.timezone_rules_evidence_sha256",
        "must be distinct from vintage evidence",
    )
    timezone_locator != evidence["availability_evidence_locator"] ||
        fail(
        "evidence.timezone_rules_evidence_locator",
        "must be distinct from availability evidence",
    )
    timezone_hash != evidence["availability_evidence_sha256"] ||
        fail(
        "evidence.timezone_rules_evidence_sha256",
        "must be distinct from availability evidence",
    )
    semantics = load_timezone_semantics()
    sealed_start_offset, sealed_start_minutes =
        sealed_offset_at_local_midnight(semantics, source_timezone, start_date)
    sealed_end_offset, sealed_end_minutes = sealed_offset_at_local_midnight(
        semantics,
        source_timezone,
        end_date + Day(1),
    )
    start_offset == sealed_start_offset && start_minutes == sealed_start_minutes ||
        fail(
        "evidence.start_utc_offset",
        "does not match the pinned IANA TZDB local-midnight semantics",
    )
    end_offset == sealed_end_offset && end_minutes == sealed_end_minutes ||
        fail(
        "evidence.end_utc_offset",
        "does not match the pinned IANA TZDB local-midnight semantics",
    )
    return start_date, end_date, source_timezone, start_minutes, end_minutes
end

function validate_evidence(policy, evidence)
    validate_policy(policy)
    artifact = expect_table(evidence, "evidence")
    assertion_basis = expect_string(
        get(artifact, "assertion_basis", nothing),
        "evidence.assertion_basis",
    )
    expected_keys = assertion_keys(assertion_basis)
    artifact = expect_exact_keys(artifact, expected_keys, "evidence")
    validate_common_evidence(artifact)

    if assertion_basis == EXACT_ASSERTION
        expect_timestamp(
            artifact["actual_public_timestamp_utc"],
            "evidence.actual_public_timestamp_utc",
        )
    else
        validate_date_evidence(
            policy,
            artifact,
            assertion_basis,
        )
    end

    actual_hash = evidence_sha256(artifact)
    artifact["content_sha256"] == actual_hash ||
        fail(
        "evidence.content_sha256",
        "does not match canonical evidence hash $actual_hash",
    )
    return artifact
end

function derive_availability_window(policy, evidence)
    artifact = validate_evidence(policy, evidence)
    assertion_basis = String(artifact["assertion_basis"])
    if assertion_basis == EXACT_ASSERTION
        timestamp = expect_timestamp(
            artifact["actual_public_timestamp_utc"],
            "evidence.actual_public_timestamp_utc",
        )
        return AvailabilityWindow(
            assertion_basis,
            timestamp,
            timestamp,
            timestamp,
            0,
            nothing,
        )
    end

    start_date, end_date, source_timezone, start_minutes, end_minutes =
        validate_date_evidence(policy, artifact, assertion_basis)
    lower_bound = DateTime(start_date) - Minute(start_minutes)
    upper_bound = DateTime(end_date + Day(1)) - Minute(end_minutes)
    upper_bound > lower_bound ||
        fail(
        "evidence",
        "sealed date interval must have a positive UTC duration",
    )
    duration_milliseconds = Dates.value(upper_bound - lower_bound)
    milliseconds_per_hour = 60 * 60 * 1_000
    duration_milliseconds % milliseconds_per_hour == 0 ||
        fail("evidence", "date interval must span a whole number of hours")
    interval_hours = div(duration_milliseconds, milliseconds_per_hour)
    return AvailabilityWindow(
        assertion_basis,
        lower_bound,
        upper_bound,
        upper_bound,
        interval_hours,
        source_timezone,
    )
end

function evaluate_temporal_gate(
        policy,
        evidence,
        origin_timestamp_utc::AbstractString,
    )
    window = derive_availability_window(policy, evidence)
    origin_timestamp = expect_timestamp(
        origin_timestamp_utc,
        "origin_timestamp_utc",
    )
    passed = origin_timestamp >= window.safe_not_before_utc
    reason_code = passed ?
        "TEMPORAL_GATE_SATISFIED_NO_ADMISSION" :
        "ORIGIN_BEFORE_SAFE_NOT_BEFORE"
    return TemporalGateResult(
        RESULT_SCHEMA,
        String(evidence["evidence_id"]),
        String(evidence["release_event_id"]),
        policy_sha256(policy),
        evidence_sha256(evidence),
        EVIDENCE_SCOPE,
        origin_timestamp,
        window,
        passed,
        reason_code,
        true,
        false,
        false,
        false,
        false,
    )
end

end
