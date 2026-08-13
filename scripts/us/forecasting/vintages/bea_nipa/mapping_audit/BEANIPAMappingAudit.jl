module BEANIPAMappingAudit

using Dates
using SHA
using TOML

export AUDIT_ARTIFACT_PATH,
    EXPECTED_AUDIT_SHA256,
    MappingAuditError,
    load_mapping_audit,
    mapping_fingerprint,
    profile_for_release,
    validate_mapping_audit,
    validate_mapping_audit_file

const AUDIT_ARTIFACT_PATH =
    joinpath(@__DIR__, "bea_nipa_mapping_audit.toml")
const EXPECTED_AUDIT_SHA256 =
    "424e34febc2054a055f8f9495a94f08fd93d8229d035b0a349b0446f0e7c2b5f"
const EXPECTED_TARGET_IDS = Set(
    [
        "core_pce_price_index",
        "gdp_deflator",
        "nominal_gdp",
        "pce_price_index",
        "real_gdp",
    ],
)
const EXPECTED_TOP_LEVEL_KEYS =
    Set(["artifact", "breaks", "evidence_gaps", "profiles", "releases", "workbooks"])
const EXPECTED_ARTIFACT_KEYS = Set(
    [
        "artifact_id",
        "audit_date",
        "break_count",
        "evidence_gap_count",
        "historical_availability_verified",
        "origin_admissible",
        "profile_assignment_policy",
        "profile_count",
        "provenance_scope",
        "raw_bytes_persisted",
        "ready",
        "release_count",
        "schema_version",
        "target_mapping_count",
        "uninspected_release_profile_assignment_allowed",
        "workbook_count",
    ],
)
const EXPECTED_WORKBOOK_KEYS = Set(
    [
        "file_format",
        "raw_bytes_persisted",
        "release_id",
        "retrieved_at_utc",
        "section_id",
        "sha256",
        "url",
        "workbook_id",
    ],
)
const EXPECTED_RELEASE_KEYS = Set(
    [
        "archive_label",
        "archive_label_date_matches_embedded_publication_date",
        "embedded_publication_date",
        "estimate_label",
        "historical_availability_verified",
        "inspected_target_ids",
        "mapping_scope",
        "origin_admissible",
        "ephemeral_audit_profile_assignment_eligible",
        "profile_id",
        "raw_bytes_persisted",
        "ready",
        "reference_period",
        "release_id",
        "workbook_ids",
    ],
)
const EXPECTED_PROFILE_KEYS = Set(
    [
        "description",
        "inspected_release_ids",
        "profile_id",
        "targets",
        "uninspected_release_assignment_allowed",
    ],
)
const EXPECTED_TARGET_KEYS = Set(
    [
        "base_year",
        "frequency",
        "physical_row_number",
        "published_line_number",
        "seasonal_adjustment",
        "section_id",
        "series_code",
        "sheet_name",
        "table_number",
        "target_id",
        "unit",
    ],
)
const EXPECTED_BREAK_KEYS = Set(
    [
        "adjacent_release_verified",
        "affected_target_ids",
        "break_id",
        "changed_dimensions",
        "evidence_workbook_ids",
        "historical_availability_verified",
        "mapping_break_demonstrated",
        "newer_release_id",
        "older_release_id",
        "origin_admissible",
        "ready",
    ],
)
const EXPECTED_GAP_KEYS =
    Set(["description", "gap_id", "required_resolution"])

struct MappingAuditError <: Exception
    message::String
end

Base.showerror(io::IO, error::MappingAuditError) = print(io, error.message)

fail(location, message) =
    throw(MappingAuditError("$location: $message"))

function expect_keys(value, expected, location)
    value isa AbstractDict || fail(location, "must be a table")
    found = Set(String(key) for key in keys(value))
    found == expected ||
        fail(
        location,
        "keys differ; missing=$(sort!(collect(setdiff(expected, found)))) " *
            "extra=$(sort!(collect(setdiff(found, expected))))",
    )
    return value
end

function expect_vector(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    return value
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    isempty(text) && fail(location, "must not be empty")
    return text
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be boolean")
    return value
end

function expect_false(value, location)
    expect_bool(value, location)
    value === false ||
        fail(location, "must remain false")
    return false
end

function expect_true(value, location)
    expect_bool(value, location)
    value === true ||
        fail(location, "must be true")
    return true
end

function expect_positive_integer(value, location)
    value isa Integer && value > 0 ||
        fail(location, "must be a positive integer")
    return Int(value)
end

function expect_string_vector(value, location; nonempty = true)
    values = expect_vector(value, location)
    nonempty && isempty(values) && fail(location, "must not be empty")
    strings = String[]
    for (index, item) in pairs(values)
        push!(strings, expect_string(item, "$location[$index]"))
    end
    length(strings) == length(unique(strings)) ||
        fail(location, "must contain unique strings")
    return strings
end

function index_unique(rows, key, location)
    result = Dict{String, Any}()
    for (index, raw_row) in pairs(rows)
        raw_row isa AbstractDict ||
            fail("$location[$index]", "must be a table")
        row = raw_row
        id = expect_string(
            get(row, key, nothing),
            "$location[$index].$key",
        )
        haskey(result, id) &&
            fail("$location[$index].$key", "duplicates $(repr(id))")
        result[id] = row
    end
    return result
end

function parse_date_string(value, location)
    text = expect_string(value, location)
    occursin(r"^\d{4}-\d{2}-\d{2}$", text) ||
        fail(location, "must use YYYY-MM-DD")
    try
        return Date(text)
    catch error
        return fail(location, "is not a valid date ($(sprint(showerror, error)))")
    end
end

function validate_artifact(artifact)
    expect_keys(artifact, EXPECTED_ARTIFACT_KEYS, "artifact")
    expected = Dict(
        "schema_version" => "beforeit-us-bea-nipa-mapping-audit.v1",
        "artifact_id" => "bea-nipa-hmi7-ephemeral-mapping-audit-2026-08-05",
        "audit_date" => "2026-08-05",
        "provenance_scope" => "ephemeral_research_audit_only",
        "profile_assignment_policy" => "exact_inspected_release_ids_only",
        "workbook_count" => 40,
        "release_count" => 20,
        "profile_count" => 8,
        "target_mapping_count" => 40,
        "break_count" => 7,
        "evidence_gap_count" => 9,
    )
    for (key, expected_value) in expected
        get(artifact, key, nothing) == expected_value ||
            fail(
            "artifact.$key",
            "expected $(repr(expected_value)), found " *
                repr(get(artifact, key, nothing)),
        )
    end
    for key in (
            "raw_bytes_persisted",
            "historical_availability_verified",
            "origin_admissible",
            "ready",
            "uninspected_release_profile_assignment_allowed",
        )
        expect_false(get(artifact, key, nothing), "artifact.$key")
    end
    return nothing
end

function validate_workbooks(workbooks)
    length(workbooks) == 40 ||
        fail("workbooks", "expected 40 records")
    by_id = index_unique(workbooks, "workbook_id", "workbooks")
    for (index, raw_workbook) in pairs(workbooks)
        location = "workbooks[$index]"
        workbook =
            expect_keys(raw_workbook, EXPECTED_WORKBOOK_KEYS, location)
        expect_string(workbook["release_id"], "$location.release_id")
        section = expect_string(workbook["section_id"], "$location.section_id")
        section in ("1", "2", "7") ||
            fail("$location.section_id", "must be 1, 2, or 7")
        format = expect_string(workbook["file_format"], "$location.file_format")
        format in ("xls", "xlsx") ||
            fail("$location.file_format", "must be xls or xlsx")
        url = expect_string(workbook["url"], "$location.url")
        startswith(
            url,
            "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/",
        ) || fail("$location.url", "must be an official BEA HMI7 workbook URL")
        endswith(lowercase(url), ".$format") ||
            fail("$location.url", "extension does not match file_format")
        occursin(r"[?#]", url) &&
            fail("$location.url", "must not contain a query or fragment")
        digest = expect_string(workbook["sha256"], "$location.sha256")
        occursin(r"^[0-9a-f]{64}$", digest) ||
            fail("$location.sha256", "must be a lowercase SHA-256")
        timestamp =
            expect_string(workbook["retrieved_at_utc"], "$location.retrieved_at_utc")
        occursin(
            r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$",
            timestamp,
        ) || fail(
            "$location.retrieved_at_utc",
            "must use microsecond UTC RFC3339 form",
        )
        parse_date_string(timestamp[1:10], "$location.retrieved_at_utc")
        expect_false(
            workbook["raw_bytes_persisted"],
            "$location.raw_bytes_persisted",
        )
    end
    return by_id
end

function validate_releases(releases, workbooks_by_id)
    length(releases) == 20 ||
        fail("releases", "expected 20 records")
    by_id = index_unique(releases, "release_id", "releases")
    referenced_workbooks = Set{String}()
    full_targets = sort!(collect(EXPECTED_TARGET_IDS))
    for (index, raw_release) in pairs(releases)
        location = "releases[$index]"
        release = expect_keys(raw_release, EXPECTED_RELEASE_KEYS, location)
        reference_period =
            expect_string(release["reference_period"], "$location.reference_period")
        occursin(r"^\d{4}Q[1-4]$", reference_period) ||
            fail("$location.reference_period", "must use YYYYQn")
        expect_string(release["estimate_label"], "$location.estimate_label")
        expect_string(release["archive_label"], "$location.archive_label")
        parse_date_string(
            release["embedded_publication_date"],
            "$location.embedded_publication_date",
        )
        expect_bool(
            release["archive_label_date_matches_embedded_publication_date"],
            "$location.archive_label_date_matches_embedded_publication_date",
        )
        scope = expect_string(release["mapping_scope"], "$location.mapping_scope")
        scope in ("all_five_targets", "partial_boundary_evidence") ||
            fail("$location.mapping_scope", "has an unsupported value")
        eligible = expect_bool(
            release["ephemeral_audit_profile_assignment_eligible"],
            "$location.ephemeral_audit_profile_assignment_eligible",
        )
        profile_id = expect_string(release["profile_id"], "$location.profile_id")
        targets = sort!(
            expect_string_vector(
                release["inspected_target_ids"],
                "$location.inspected_target_ids",
            ),
        )
        all(target -> target in EXPECTED_TARGET_IDS, targets) ||
            fail("$location.inspected_target_ids", "contains an unknown target")
        if eligible
            scope == "all_five_targets" ||
                fail("$location.mapping_scope", "eligible releases must cover all targets")
            profile_id != "none" ||
                fail("$location.profile_id", "eligible release must name a profile")
            targets == full_targets ||
                fail("$location.inspected_target_ids", "must cover exactly five targets")
        else
            scope == "partial_boundary_evidence" ||
                fail("$location.mapping_scope", "ineligible release must be partial")
            profile_id == "none" ||
                fail("$location.profile_id", "ineligible release must use none")
        end
        workbook_ids = expect_string_vector(
            release["workbook_ids"],
            "$location.workbook_ids",
        )
        release_id = release["release_id"]
        for workbook_id in workbook_ids
            haskey(workbooks_by_id, workbook_id) ||
                fail("$location.workbook_ids", "unknown workbook $workbook_id")
            workbook = workbooks_by_id[workbook_id]
            workbook["release_id"] == release_id ||
                fail(
                "$location.workbook_ids",
                "$workbook_id belongs to $(workbook["release_id"])",
            )
            workbook_id in referenced_workbooks &&
                fail("$location.workbook_ids", "reuses $workbook_id")
            push!(referenced_workbooks, workbook_id)
        end
        for key in (
                "raw_bytes_persisted",
                "historical_availability_verified",
                "origin_admissible",
                "ready",
            )
            expect_false(release[key], "$location.$key")
        end
    end
    referenced_workbooks == Set(keys(workbooks_by_id)) ||
        fail("releases.workbook_ids", "must partition all workbook records")
    return by_id
end

function validate_target(target, location)
    expect_keys(target, EXPECTED_TARGET_KEYS, location)
    target_id = expect_string(target["target_id"], "$location.target_id")
    target_id in EXPECTED_TARGET_IDS ||
        fail("$location.target_id", "is not a Tier-1 BEA target")
    section = expect_string(target["section_id"], "$location.section_id")
    section in ("1", "2", "7") ||
        fail("$location.section_id", "must be 1, 2, or 7")
    expect_string(target["sheet_name"], "$location.sheet_name")
    table_number = expect_string(target["table_number"], "$location.table_number")
    occursin(r"^\d+\.\d+(?:\.\d+)?$", table_number) ||
        fail("$location.table_number", "has invalid NIPA form")
    line = expect_positive_integer(
        target["published_line_number"],
        "$location.published_line_number",
    )
    row = expect_positive_integer(
        target["physical_row_number"],
        "$location.physical_row_number",
    )
    row > line ||
        fail("$location.physical_row_number", "must exceed published line number")
    series_code = expect_string(target["series_code"], "$location.series_code")
    occursin(r"^[A-Z0-9]+$", series_code) ||
        fail("$location.series_code", "must be uppercase alphanumeric")
    target["frequency"] == "quarterly" ||
        fail("$location.frequency", "must be quarterly")
    seasonal =
        expect_string(target["seasonal_adjustment"], "$location.seasonal_adjustment")
    expected_seasonal = target_id in ("nominal_gdp", "real_gdp") ?
        "seasonally_adjusted_annual_rate" :
        "seasonally_adjusted"
    seasonal == expected_seasonal ||
        fail("$location.seasonal_adjustment", "does not match target concept")
    unit = expect_string(target["unit"], "$location.unit")
    base_year = expect_string(target["base_year"], "$location.base_year")
    if target_id == "nominal_gdp"
        unit in ("billions_of_dollars", "millions_of_dollars") ||
            fail("$location.unit", "has invalid nominal GDP unit")
        base_year == "not_applicable" ||
            fail("$location.base_year", "must be not_applicable for nominal GDP")
    elseif target_id == "real_gdp"
        unit in (
            "billions_of_chained_dollars",
            "millions_of_chained_dollars",
        ) || fail("$location.unit", "has invalid real GDP unit")
        occursin(r"^\d{4}$", base_year) ||
            fail("$location.base_year", "must be a four-digit year")
    else
        unit == "index" ||
            fail("$location.unit", "price targets must use index")
        occursin(r"^\d{4}$", base_year) ||
            fail("$location.base_year", "must be a four-digit year")
    end
    return target_id
end

function validate_profiles(profiles, releases_by_id)
    length(profiles) == 8 ||
        fail("profiles", "expected 8 records")
    by_id = index_unique(profiles, "profile_id", "profiles")
    assigned_releases = Set{String}()
    target_mapping_count = 0
    for (index, raw_profile) in pairs(profiles)
        location = "profiles[$index]"
        profile = expect_keys(raw_profile, EXPECTED_PROFILE_KEYS, location)
        expect_string(profile["description"], "$location.description")
        expect_false(
            profile["uninspected_release_assignment_allowed"],
            "$location.uninspected_release_assignment_allowed",
        )
        profile_id = profile["profile_id"]
        release_ids = expect_string_vector(
            profile["inspected_release_ids"],
            "$location.inspected_release_ids",
        )
        for release_id in release_ids
            haskey(releases_by_id, release_id) ||
                fail("$location.inspected_release_ids", "unknown release $release_id")
            release = releases_by_id[release_id]
            release["ephemeral_audit_profile_assignment_eligible"] === true ||
                fail(
                "$location.inspected_release_ids",
                "$release_id is not assignment eligible",
            )
            release["profile_id"] == profile_id ||
                fail(
                "$location.inspected_release_ids",
                "$release_id declares profile $(release["profile_id"])",
            )
            release_id in assigned_releases &&
                fail("$location.inspected_release_ids", "reassigns $release_id")
            push!(assigned_releases, release_id)
        end
        targets = expect_vector(profile["targets"], "$location.targets")
        length(targets) == 5 ||
            fail("$location.targets", "must contain exactly five mappings")
        seen_targets = Set{String}()
        for (target_index, target) in pairs(targets)
            target_id =
                validate_target(target, "$location.targets[$target_index]")
            target_id in seen_targets &&
                fail("$location.targets[$target_index]", "duplicates $target_id")
            push!(seen_targets, target_id)
            target_mapping_count += 1
        end
        seen_targets == EXPECTED_TARGET_IDS ||
            fail("$location.targets", "must exactly cover the five BEA targets")
    end
    eligible_releases = Set(
        release_id for (release_id, release) in releases_by_id if
            release["ephemeral_audit_profile_assignment_eligible"] === true
    )
    assigned_releases == eligible_releases ||
        fail("profiles.inspected_release_ids", "must exactly cover eligible releases")
    target_mapping_count == 40 ||
        fail("profiles.targets", "expected 40 target mappings")
    return by_id
end

function validate_breaks(breaks, releases_by_id, workbooks_by_id)
    length(breaks) == 7 ||
        fail("breaks", "expected 7 records")
    by_id = index_unique(breaks, "break_id", "breaks")
    for (index, raw_break) in pairs(breaks)
        location = "breaks[$index]"
        break_record = expect_keys(raw_break, EXPECTED_BREAK_KEYS, location)
        older = expect_string(
            break_record["older_release_id"],
            "$location.older_release_id",
        )
        newer = expect_string(
            break_record["newer_release_id"],
            "$location.newer_release_id",
        )
        older != newer ||
            fail(location, "older and newer release must differ")
        haskey(releases_by_id, older) ||
            fail("$location.older_release_id", "is unknown")
        haskey(releases_by_id, newer) ||
            fail("$location.newer_release_id", "is unknown")
        older_date = parse_date_string(
            releases_by_id[older]["embedded_publication_date"],
            "$location.older_release_id",
        )
        newer_date = parse_date_string(
            releases_by_id[newer]["embedded_publication_date"],
            "$location.newer_release_id",
        )
        older_date < newer_date ||
            fail(location, "publication dates are not ordered")
        expect_true(
            break_record["adjacent_release_verified"],
            "$location.adjacent_release_verified",
        )
        expect_true(
            break_record["mapping_break_demonstrated"],
            "$location.mapping_break_demonstrated",
        )
        expect_string_vector(
            break_record["changed_dimensions"],
            "$location.changed_dimensions",
        )
        targets = expect_string_vector(
            break_record["affected_target_ids"],
            "$location.affected_target_ids",
        )
        all(target -> target in EXPECTED_TARGET_IDS, targets) ||
            fail("$location.affected_target_ids", "contains an unknown target")
        workbook_ids = expect_string_vector(
            break_record["evidence_workbook_ids"],
            "$location.evidence_workbook_ids",
        )
        evidence_release_ids = Set{String}()
        for workbook_id in workbook_ids
            haskey(workbooks_by_id, workbook_id) ||
                fail("$location.evidence_workbook_ids", "unknown $workbook_id")
            push!(
                evidence_release_ids,
                String(workbooks_by_id[workbook_id]["release_id"]),
            )
        end
        evidence_release_ids == Set([older, newer]) ||
            fail(
            "$location.evidence_workbook_ids",
            "must include evidence from both adjacent releases only",
        )
        for key in ("historical_availability_verified", "origin_admissible", "ready")
            expect_false(break_record[key], "$location.$key")
        end
    end
    return by_id
end

function validate_evidence_gaps(gaps)
    length(gaps) == 9 ||
        fail("evidence_gaps", "expected 9 records")
    by_id = index_unique(gaps, "gap_id", "evidence_gaps")
    for (index, gap) in pairs(gaps)
        location = "evidence_gaps[$index]"
        expect_keys(gap, EXPECTED_GAP_KEYS, location)
        expect_string(gap["description"], "$location.description")
        expect_string(gap["required_resolution"], "$location.required_resolution")
    end
    return by_id
end

"""
    validate_mapping_audit(document)

Validate the parsed audit structure. This verifies the fail-closed policy,
cross-record referential integrity, exact counts, and the fact that only
explicitly inspected releases can be assigned to profiles.
"""
function validate_mapping_audit(document)
    expect_keys(document, EXPECTED_TOP_LEVEL_KEYS, "mapping audit")
    artifact = document["artifact"]
    validate_artifact(artifact)
    workbooks = expect_vector(document["workbooks"], "workbooks")
    releases = expect_vector(document["releases"], "releases")
    profiles = expect_vector(document["profiles"], "profiles")
    breaks = expect_vector(document["breaks"], "breaks")
    gaps = expect_vector(document["evidence_gaps"], "evidence_gaps")

    workbooks_by_id = validate_workbooks(workbooks)
    releases_by_id = validate_releases(releases, workbooks_by_id)
    profiles_by_id = validate_profiles(profiles, releases_by_id)
    breaks_by_id = validate_breaks(breaks, releases_by_id, workbooks_by_id)
    gaps_by_id = validate_evidence_gaps(gaps)

    return (
        artifact = artifact,
        workbooks_by_id = workbooks_by_id,
        releases_by_id = releases_by_id,
        profiles_by_id = profiles_by_id,
        breaks_by_id = breaks_by_id,
        gaps_by_id = gaps_by_id,
    )
end

"""
    validate_mapping_audit_file(path=AUDIT_ARTIFACT_PATH)

Validate the exact checked-in bytes and parsed structure. The raw SHA-256 pins
every audited locator, digest, timestamp, mapping, break, and evidence gap.
"""
function validate_mapping_audit_file(path::AbstractString = AUDIT_ARTIFACT_PATH)
    bytes = read(path)
    isempty(bytes) && fail("mapping audit file", "must not be empty")
    byte_count = length(bytes)
    bytes[end] == UInt8('\n') ||
        fail("mapping audit file", "must end with LF")
    UInt8('\r') in bytes &&
        fail("mapping audit file", "must use LF, not CRLF")
    digest = bytes2hex(sha256(bytes))
    digest == EXPECTED_AUDIT_SHA256 ||
        fail(
        "mapping audit file SHA-256",
        "expected $EXPECTED_AUDIT_SHA256, found $digest",
    )
    text = try
        String(bytes)
    catch error
        return fail(
            "mapping audit file",
            "must be UTF-8 ($(sprint(showerror, error)))",
        )
    end
    document = try
        TOML.parse(text)
    catch error
        return fail(
            "mapping audit file",
            "is not valid TOML ($(sprint(showerror, error)))",
        )
    end
    validated = validate_mapping_audit(document)
    return merge(validated, (sha256 = digest, bytes = byte_count))
end

load_mapping_audit(path::AbstractString = AUDIT_ARTIFACT_PATH) =
    validate_mapping_audit_file(path)

"""
    profile_for_release(audit, release_id)

Return a mapping profile only when `release_id` is explicitly recorded as a
fully inspected, assignment-eligible release in that profile. No date,
quarter, archive-label, or nearest-profile inference is permitted.
"""
function profile_for_release(audit, release_id::AbstractString)
    id = String(release_id)
    releases_by_id = audit.releases_by_id
    haskey(releases_by_id, id) ||
        fail("profile assignment", "release $(repr(id)) was not inspected")
    release = releases_by_id[id]
    release["ephemeral_audit_profile_assignment_eligible"] === true ||
        fail(
        "profile assignment",
        "release $(repr(id)) has partial evidence only",
    )
    profile_id = String(release["profile_id"])
    haskey(audit.profiles_by_id, profile_id) ||
        fail("profile assignment", "declared profile $(repr(profile_id)) is absent")
    profile = audit.profiles_by_id[profile_id]
    id in profile["inspected_release_ids"] ||
        fail(
        "profile assignment",
        "release $(repr(id)) is not explicitly listed by $profile_id",
    )
    return profile
end

"""
Return a stable string containing every exact field in a target mapping.
"""
function mapping_fingerprint(profile_id::AbstractString, target)
    fields = (
        "target_id",
        "section_id",
        "sheet_name",
        "table_number",
        "published_line_number",
        "physical_row_number",
        "series_code",
        "frequency",
        "seasonal_adjustment",
        "unit",
        "base_year",
    )
    return join(
        vcat([String(profile_id)], [string(target[field]) for field in fields]),
        "|",
    )
end

end
