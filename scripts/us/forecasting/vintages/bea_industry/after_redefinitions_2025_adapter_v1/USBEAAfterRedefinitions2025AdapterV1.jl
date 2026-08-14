module USBEAAfterRedefinitions2025AdapterV1

using SHA
using TOML

export AdapterError,
    ARCHIVE_BYTE_COUNT,
    ARCHIVE_SHA256,
    ARCHIVE_URL,
    capture_after_redefinitions_with_fetcher,
    dry_run_plan,
    load_and_validate_profile,
    selector_receipt,
    validate_capture_bundle,
    validate_capture_quarantine,
    validate_extracted_evidence,
    validate_repository_bindings

const ADAPTER_SCHEMA = "beforeit-us-bea-after-redefinitions-2025-adapter.v1"
const ADAPTER_MODULE_NORMALIZED_SHA256 =
    "9bd6b1e249d010ceecd8a9deac5b17b7541ce58838642b3decbb8ef688babe31"
const PROFILE_FILE_SHA256 =
    "57c71a1d9a1a8f4ecad7fbc4dbc284590792aa3b2966388bf138397dc0e10d11"
const ENVELOPE_FILE_SHA256 =
    "cb8fffd626c019fa6ce65a32664a46d1ecd87d3337f72ea378900d2d4f05b165"
const PROSPECTIVE_FILE_SHA256 =
    "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
const PROSPECTIVE_SEMANTIC_SHA256 =
    "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
const INVENTORY_FILE_SHA256 =
    "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"
const PROJECT_FILE_SHA256 =
    "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"
const MANIFEST_FILE_SHA256 =
    "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"
const ARCHIVE_URL =
    "https://apps.bea.gov/HistData/Files/Releases/Industry/2025/GDP_by_Industry/Q2/Annual_September-25-2025/MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip"
const ARCHIVE_SHA256 =
    "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
const ARCHIVE_BYTE_COUNT = 8_326_144
const REQUIRED_PROFILE_IDS = Set(
    [
        "after_redefinitions_release_zip",
        "benchmark_producer_use_2017",
        "benchmark_purchaser_use_2017",
        "imports_by_user_2024",
        "make_2024",
        "producer_use_2024",
    ],
)
const REQUIRED_WORKBOOK_MEMBERS = Set(
    [
        "IOMake_After_Redefinitions_PRO_Summary.xlsx",
        "IOUse_After_Redefinitions_PRO_Summary.xlsx",
        "IOUse_After_Redefinitions_PUR_Summary.xlsx",
        "ImportMatrices_After_Redefinitions_Summary.xlsx",
    ],
)
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const CRC_PATTERN = r"^[0-9a-f]{8}$"

const PROFILE_PATH = joinpath(@__DIR__, "bea_after_redefinitions_2025_profile_v1.toml")
const ENVELOPE_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "prospective_snapshot_envelope_v1",
        "USProspectiveSnapshotEnvelopeV1.jl",
    ),
)
const SCRIPTS_US_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const REPOSITORY_ROOT_WITH_SEPARATOR =
    normpath(joinpath(SCRIPTS_US_ROOT, "..", ".."))
const REPOSITORY_ROOT = endswith(REPOSITORY_ROOT_WITH_SEPARATOR, "/") ?
    chop(REPOSITORY_ROOT_WITH_SEPARATOR) : REPOSITORY_ROOT_WITH_SEPARATOR
const PROSPECTIVE_PATH = joinpath(
    SCRIPTS_US_ROOT,
    "forecasting",
    "vintages",
    "prospective",
    "prospective_2026q3_contract_v2.toml",
)
const INVENTORY_PATH = joinpath(
    SCRIPTS_US_ROOT,
    "forecasting",
    "vintages",
    "current_inventory.toml",
)
const PROJECT_PATH = joinpath(SCRIPTS_US_ROOT, "Project.toml")
const MANIFEST_PATH = joinpath(SCRIPTS_US_ROOT, "Manifest.toml")

struct AdapterError <: Exception
    message::String
end

Base.showerror(io::IO, error::AdapterError) = print(io, error.message)
fail(location, message) = throw(AdapterError("$location: $message"))
sha256_hex(bytes) = bytes2hex(sha256(bytes))

function _adapter_module_hashes()
    bytes = read(@__FILE__)
    text = String(copy(bytes))
    occurrences = findall(ADAPTER_MODULE_NORMALIZED_SHA256, text)
    length(occurrences) == 1 ||
        fail("source.adapter", "normalized-hash literal must occur exactly once")
    normalized_text = replace(
        text,
        ADAPTER_MODULE_NORMALIZED_SHA256 => repeat("0", 64);
        count = 1,
    )
    normalized = sha256_hex(codeunits(normalized_text))
    normalized == ADAPTER_MODULE_NORMALIZED_SHA256 ||
        fail("source.adapter", "normalized SHA-256 identity changed")
    return (
        physical_sha256 = sha256_hex(bytes),
        normalized_sha256 = normalized,
    )
end

function _regular_file_sha256(path, location)
    isabspath(path) || fail(location, "path must be absolute")
    normpath(path) == path || fail(location, "path must be normalized")
    isfile(path) || fail(location, "missing file $path")
    islink(path) && fail(location, "symbolic link forbidden")
    realpath(path) == path || fail(location, "path must be canonical")
    stat(path).nlink == 1 || fail(location, "hard-linked file forbidden")
    return sha256_hex(read(path))
end

_regular_file_sha256(ENVELOPE_PATH, "source.envelope") == ENVELOPE_FILE_SHA256 ||
    fail("source.envelope", "SHA-256 identity changed before include")

include(ENVELOPE_PATH)
using .USProspectiveSnapshotEnvelopeV1

const Envelope = USProspectiveSnapshotEnvelopeV1

function _expect(value, expected, location)
    typeof(value) === typeof(expected) && value == expected ||
        fail(location, "expected exact $(typeof(expected)) $(repr(expected)), got $(typeof(value)) $(repr(value))")
    return value
end

function _string(value, location; allow_empty = false)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    !allow_empty && isempty(text) && fail(location, "must not be empty")
    return text
end

function _integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) || fail(location, "must be an integer")
    number = Int(value)
    number >= minimum || fail(location, "must be at least $minimum")
    return number
end

function _validate_integer_controls(value, location)
    if value isa AbstractDict
        for (raw_key, item) in value
            key = String(raw_key)
            item_location = "$location.$key"
            if endswith(key, "_count") || endswith(key, "_bytes") ||
                    endswith(key, "_milliseconds") || endswith(key, "_seconds") ||
                    key in ("compression_method", "maximum_redirects", "sequence")
                _integer(item, item_location)
            end
            _validate_integer_controls(item, item_location)
        end
    elseif value isa AbstractVector
        for (index, item) in enumerate(value)
            _validate_integer_controls(item, "$location[$index]")
        end
    end
    return value
end

function _hash(value, location)
    text = _string(value, location)
    occursin(HASH_PATTERN, text) || fail(location, "must be lowercase SHA-256")
    return text
end

function _crc(value, location)
    text = _string(value, location)
    occursin(CRC_PATTERN, text) || fail(location, "must be lowercase CRC-32")
    return text
end

function _toml_hash(value)
    io = IOBuffer()
    TOML.print(io, value; sorted = true)
    return sha256_hex(take!(io))
end

function _profile_map(profile)
    result = Dict{String, Dict{String, Any}}()
    for row in profile["profiles"]
        id = _string(row["profile_id"], "profile.profile_id")
        haskey(result, id) && fail("profile.profiles", "duplicate ID $id")
        result[id] = Dict{String, Any}(String(key) => value for (key, value) in row)
    end
    return result
end

function _workbook_map(profile)
    result = Dict{String, Dict{String, Any}}()
    for row in profile["workbooks"]
        member = _string(row["member"], "profile.workbook.member")
        haskey(result, member) && fail("profile.workbooks", "duplicate member $member")
        result[member] = Dict{String, Any}(String(key) => value for (key, value) in row)
    end
    return result
end

function _archive_entry_map(profile)
    result = Dict{String, Dict{String, Any}}()
    for row in profile["archive_entries"]
        name = _string(row["name"], "profile.archive_entry.name")
        haskey(result, name) && fail("profile.archive_entries", "duplicate name $name")
        result[name] = Dict{String, Any}(String(key) => value for (key, value) in row)
    end
    return result
end

function _prospective_requirement(document)
    matches = [
        row for row in document["requirements"] if
            get(row, "requirement_id", "") == "bea_industry_valuation_structural"
    ]
    length(matches) == 1 || fail("prospective", "valuation requirement must occur once")
    return only(matches)
end

"""Validate the frozen adapter profile and its exact prospective-v2 mapping."""
function load_and_validate_profile(profile_path = PROFILE_PATH)
    path = normpath(String(profile_path))
    isfile(path) || fail("profile", "missing")
    profile = TOML.parsefile(path)
    _validate_integer_controls(profile, "profile")
    _expect(
        profile["schema_version"],
        "beforeit-us-bea-after-redefinitions-2025-prospective-profile.v1",
        "profile.schema_version",
    )
    _expect(
        profile["contract_id"],
        "bea-after-redefinitions-2025-annual-update-prospective-snapshot-v1",
        "profile.contract_id",
    )
    _expect(profile["current_status"], "CANNOT_RUN_NO_NEW_PROSPECTIVE_BUNDLE", "profile.status")
    _expect(profile["requirement_id"], "bea_industry_valuation_structural", "profile.requirement_id")
    _expect(profile["campaign_id"], "slow_structural_pre_origin", "profile.campaign_id")
    _expect(
        profile["source_attribution"],
        "Source: U.S. Bureau of Economic Analysis",
        "profile.source_attribution",
    )
    _expect(profile["source_endorsement_claim"], "NONE", "profile.source_endorsement_claim")
    _expect(profile["required_profile_count"], 6, "profile.required_profile_count")
    _expect(profile["august_completion_eligible"], true, "profile.august_completion_eligible")
    _expect(
        profile["excluded_other_slow_structural_profile_count"],
        27,
        "profile.excluded_count",
    )
    _expect(profile["excluded_other_profile_relabel_allowed"], false, "profile.relabel")
    for gate in (
            "origin_admissible",
            "source_inventory_mutation_allowed",
            "model_state_write_allowed",
            "empirical_forecast_allowed",
            "accuracy_evaluation_allowed",
            "promotion_eligible",
            "production_scoring_allowed",
        )
        _expect(profile[gate], false, "profile.$gate")
    end
    source = profile["source"]
    _expect(source["requested_url"], ARCHIVE_URL, "profile.source.requested_url")
    _expect(source["archive_sha256"], ARCHIVE_SHA256, "profile.source.archive_sha256")
    _expect(source["archive_byte_count"], ARCHIVE_BYTE_COUNT, "profile.source.archive_byte_count")
    _expect(source["archive_entry_count"], 12, "profile.source.archive_entry_count")
    _expect(source["expected_host"], "apps.bea.gov", "profile.source.expected_host")
    _hash(source["requested_url_sha256"], "profile.source.requested_url_sha256") ==
        sha256_hex(codeunits(ARCHIVE_URL)) ||
        fail("profile.source.requested_url_sha256", "does not bind exact URL")
    _hash(source["terms_url_sha256"], "profile.source.terms_url_sha256") ==
        sha256_hex(codeunits(source["terms_url"])) ||
        fail("profile.source.terms_url_sha256", "does not bind exact terms URL")
    _expect(source["terms_review_timezone"], "UTC", "profile.source.terms_review_timezone")
    policy_review = profile["policy_review"]
    _expect(policy_review["access_date"], "2026-08-08", "profile.policy_review.access_date")
    for key in (
            "linking_policy_url",
            "faq_145_url",
            "input_output_page_url",
            "open_data_page_url",
        )
        _hash(policy_review[key * "_sha256"], "profile.policy_review.$key.sha256") ==
            sha256_hex(codeunits(policy_review[key])) ||
            fail("profile.policy_review.$key", "URL SHA-256 mismatch")
    end
    _expect(
        policy_review["page_content_sha256_status"],
        "NOT_CAPTURED_NO_POLICY_AUTHORIZATION_CLAIM",
        "profile.policy_review.page_content_sha256_status",
    )
    for key in (
            "same_day_policy_authorization_claimed",
            "direct_archive_authority_inferred_from_api_terms",
            "api_authority_inferred_from_direct_archive_policy",
        )
        _expect(policy_review[key], false, "profile.policy_review.$key")
    end
    _expect(policy_review["source_attribution_required"], true, "profile.policy_review.attribution")
    _expect(
        policy_review["source_attribution"],
        "Source: U.S. Bureau of Economic Analysis",
        "profile.policy_review.source_attribution",
    )
    _expect(policy_review["endorsement_claim"], "NONE", "profile.policy_review.endorsement")
    request_headers = profile["request_headers"]
    length(request_headers) == 3 || fail("profile.request_headers", "must contain three rows")
    for (index, row) in enumerate(request_headers)
        _expect(row["sequence"], index, "profile.request_headers[$index].sequence")
    end
    transport = profile["transport"]
    for (key, expected) in (
            "maximum_request_count" => 1,
            "maximum_redirects" => 0,
            "retry_count" => 0,
            "minimum_body_bytes" => ARCHIVE_BYTE_COUNT,
            "maximum_body_bytes" => ARCHIVE_BYTE_COUNT,
            "maximum_duration_seconds" => 60,
            "maximum_header_count" => 64,
            "maximum_header_bytes" => 65_536,
        )
        _expect(transport[key], expected, "profile.transport.$key")
    end
    profiles = _profile_map(profile)
    Set(keys(profiles)) == REQUIRED_PROFILE_IDS || fail("profile.profiles", "ID set mismatch")
    workbooks = _workbook_map(profile)
    Set(keys(workbooks)) == REQUIRED_WORKBOOK_MEMBERS ||
        fail("profile.workbooks", "member set mismatch")
    entries = _archive_entry_map(profile)
    length(entries) == 12 || fail("profile.archive_entries", "must contain 12 exact entries")
    for (name, entry) in entries
        _integer(
            entry["compressed_byte_count"],
            "profile.archive_entries.$name.compressed_byte_count";
            minimum = 0,
        )
        _integer(
            entry["uncompressed_byte_count"],
            "profile.archive_entries.$name.uncompressed_byte_count";
            minimum = 0,
        )
        _expect(
            _integer(entry["compression_method"], "profile.archive_entries.$name.compression_method"),
            8,
            "profile.archive_entries.$name.compression_method",
        )
    end
    for (member, workbook) in workbooks
        _hash(workbook["sha256"], "profile.workbooks.$member.sha256")
        _integer(workbook["byte_count"], "profile.workbooks.$member.byte_count"; minimum = 1)
        _crc(workbook["outer_crc32"], "profile.workbooks.$member.outer_crc32")
        _hash(
            workbook["workbook_xml_sha256"],
            "profile.workbooks.$member.workbook_xml_sha256",
        )
        _integer(
            workbook["workbook_xml_byte_count"],
            "profile.workbooks.$member.workbook_xml_byte_count";
            minimum = 1,
        )
        _crc(
            workbook["workbook_xml_crc32"],
            "profile.workbooks.$member.workbook_xml_crc32",
        )
        length(unique(String.(workbook["sheet_names"]))) == length(workbook["sheet_names"]) ||
            fail("profile.workbooks.$member.sheet_names", "duplicates forbidden")
        entry = entries[member]
        _expect(entry["crc32"], workbook["outer_crc32"], "profile.workbooks.$member.crc")
        _expect(
            entry["uncompressed_byte_count"],
            workbook["byte_count"],
            "profile.workbooks.$member.size",
        )
    end
    prospective = TOML.parsefile(PROSPECTIVE_PATH)
    _validate_integer_controls(prospective, "prospective")
    prospective_artifact = prospective["artifact"]
    _expect(
        prospective_artifact["contract_id"],
        profile["prospective_contract"]["contract_id"],
        "prospective.contract_id",
    )
    _expect(
        prospective_artifact["content_sha256"],
        PROSPECTIVE_SEMANTIC_SHA256,
        "prospective.content_sha256",
    )
    requirement = _prospective_requirement(prospective)
    _expect(
        requirement["default_capture_id"],
        "slow_structural_pre_origin",
        "prospective.default_capture_id",
    )
    _expect(requirement["required_profile_count"], 6, "prospective.required_profile_count")
    exact_selectors = Dict{String, String}(
        String(key) => String(value) for
            (key, value) in requirement["artifact_profiles"]
    )
    Set(keys(exact_selectors)) == REQUIRED_PROFILE_IDS ||
        fail("prospective.artifact_profiles", "profile ID set mismatch")
    for (id, row) in profiles
        _expect(row["selector"], exact_selectors[id], "profile.profiles.$id.selector")
        member = String(row["member"])
        sheet = String(row["sheet"])
        if isempty(member)
            id == "after_redefinitions_release_zip" ||
                fail("profile.profiles.$id", "only archive profile may omit member")
            isempty(sheet) || fail("profile.profiles.$id", "archive sheet must be empty")
        else
            haskey(workbooks, member) || fail("profile.profiles.$id", "unknown member")
            sheet in String.(workbooks[member]["sheet_names"]) ||
                fail("profile.profiles.$id", "required sheet absent from OOXML inventory")
        end
    end
    return profile
end

function validate_repository_bindings()
    adapter_hashes = _adapter_module_hashes()
    observed = Dict{String, String}(
        "adapter_module_file_sha256" => adapter_hashes.physical_sha256,
        "adapter_module_normalized_sha256" => adapter_hashes.normalized_sha256,
        "envelope_file_sha256" => _regular_file_sha256(ENVELOPE_PATH, "source.envelope"),
        "profile_file_sha256" => _regular_file_sha256(PROFILE_PATH, "source.profile"),
        "prospective_file_sha256" =>
            _regular_file_sha256(PROSPECTIVE_PATH, "source.prospective"),
        "inventory_file_sha256" => _regular_file_sha256(INVENTORY_PATH, "source.inventory"),
        "project_file_sha256" => _regular_file_sha256(PROJECT_PATH, "source.project"),
        "manifest_file_sha256" => _regular_file_sha256(MANIFEST_PATH, "source.manifest"),
    )
    expected = Dict(
        "envelope_file_sha256" => ENVELOPE_FILE_SHA256,
        "profile_file_sha256" => PROFILE_FILE_SHA256,
        "prospective_file_sha256" => PROSPECTIVE_FILE_SHA256,
        "inventory_file_sha256" => INVENTORY_FILE_SHA256,
        "project_file_sha256" => PROJECT_FILE_SHA256,
        "manifest_file_sha256" => MANIFEST_FILE_SHA256,
    )
    for (key, value) in expected
        get(observed, key, "") == value ||
            fail("source.$key", "executable/source identity changed")
    end
    profile = load_and_validate_profile()
    for row in profile["repository_evidence"]
        relative = String(row["path"])
        path = normpath(joinpath(REPOSITORY_ROOT, relative))
        startswith(path, REPOSITORY_ROOT * "/") || fail("source.evidence", "path escapes repo")
        _regular_file_sha256(path, "source.evidence.$(row["evidence_id"])") == row["sha256"] ||
            fail("source.evidence.$(row["evidence_id"])", "SHA-256 identity changed")
    end
    return observed
end

function _capture_policy()
    bindings = validate_repository_bindings()
    profile = load_and_validate_profile()
    headers = Pair{String, String}[
        String(row["name"]) => String(row["value"]) for
            row in sort(profile["request_headers"]; by = row -> row["sequence"])
    ]
    transport = profile["transport"]
    window = profile["capture_window"]
    source = profile["source"]
    return Envelope.CapturePolicy(
        policy_id = profile["contract_id"],
        source_id = "bea_industry_valuation_matrices",
        campaign_id = profile["campaign_id"],
        artifact_id = "bea_after_redefinitions_2025_annual_update_zip",
        requested_url = source["requested_url"],
        expected_host = source["expected_host"],
        media_types = source["media_types"],
        extension = source["extension"],
        minimum_body_bytes = transport["minimum_body_bytes"],
        maximum_body_bytes = transport["maximum_body_bytes"],
        maximum_duration_seconds = transport["maximum_duration_seconds"],
        maximum_header_count = transport["maximum_header_count"],
        maximum_header_bytes = transport["maximum_header_bytes"],
        not_before_utc = window["not_before_utc"],
        deadline_utc = window["deadline_utc"],
        expected_body_sha256 = source["archive_sha256"],
        request_headers = headers,
        source_bindings = bindings,
        blockers = profile["limitations"]["blockers"],
    )
end

function _entry_evidence(entries, expected_entries)
    observed = Dict(entry.name => entry for entry in entries)
    Set(keys(observed)) == Set(keys(expected_entries)) ||
        fail("archive.entries", "member name set differs from profile")
    result = Dict{String, Dict{String, Any}}()
    for name in sort!(collect(keys(expected_entries)))
        entry = observed[name]
        expected = expected_entries[name]
        crc = lowercase(string(entry.crc32; base = 16, pad = 8))
        _expect(crc, expected["crc32"], "archive.entries.$name.crc32")
        _expect(
            Int(entry.compressed_size),
            expected["compressed_byte_count"],
            "archive.entries.$name.compressed_size",
        )
        _expect(
            Int(entry.uncompressed_size),
            expected["uncompressed_byte_count"],
            "archive.entries.$name.uncompressed_size",
        )
        _expect(
            Int(entry.compression_method),
            expected["compression_method"],
            "archive.entries.$name.compression_method",
        )
        result[name] = Dict{String, Any}(
            "compressed_byte_count" => Int(entry.compressed_size),
            "compression_method" => Int(entry.compression_method),
            "crc32" => crc,
            "name" => name,
            "uncompressed_byte_count" => Int(entry.uncompressed_size),
        )
    end
    return result
end

"""
Independently verify supplied decompressed workbook and `xl/workbook.xml` bytes.
The caller controls extraction; this pure function never invokes a shell or writes.
"""
function validate_extracted_evidence(archive_bytes, workbook_payloads, workbook_xml_payloads)
    profile = load_and_validate_profile()
    archive = UInt8[byte for byte in archive_bytes]
    length(archive) == ARCHIVE_BYTE_COUNT || fail("archive", "byte count mismatch")
    sha256_hex(archive) == ARCHIVE_SHA256 || fail("archive", "SHA-256 mismatch")
    entries = Envelope.inspect_zip(
        archive;
        maximum_entries = 64,
        maximum_uncompressed_bytes = 32_000_000,
    )
    _entry_evidence(entries, _archive_entry_map(profile))
    Set(String.(keys(workbook_payloads))) == REQUIRED_WORKBOOK_MEMBERS ||
        fail("extracted.workbooks", "member set mismatch")
    Set(String.(keys(workbook_xml_payloads))) == REQUIRED_WORKBOOK_MEMBERS ||
        fail("extracted.workbook_xml", "member set mismatch")
    workbooks = _workbook_map(profile)
    result = Dict{String, Any}()
    for member in sort!(collect(REQUIRED_WORKBOOK_MEMBERS))
        contract = workbooks[member]
        payload = workbook_payloads[member]
        member_evidence = Envelope.verify_member_payload(
            entries,
            member,
            payload;
            expected_sha256 = contract["sha256"],
        )
        ooxml = Envelope.verify_ooxml_workbook(
            payload,
            workbook_xml_payloads[member];
            expected_workbook_sha256 = contract["sha256"],
            expected_workbook_xml_sha256 = contract["workbook_xml_sha256"],
            required_sheets = contract["sheet_names"],
        )
        _expect(member_evidence.member_byte_count, contract["byte_count"], "extracted.$member.size")
        _expect(member_evidence.member_crc32, contract["outer_crc32"], "extracted.$member.crc")
        _expect(
            ooxml.workbook_xml_byte_count,
            contract["workbook_xml_byte_count"],
            "extracted.$member.workbook_xml_size",
        )
        _expect(
            ooxml.workbook_xml_crc32,
            contract["workbook_xml_crc32"],
            "extracted.$member.workbook_xml_crc",
        )
        _expect(ooxml.sheets, String.(contract["sheet_names"]), "extracted.$member.sheet_names")
        result[member] = Dict{String, Any}(
            "member_byte_count" => member_evidence.member_byte_count,
            "member_crc32" => member_evidence.member_crc32,
            "member_sha256" => member_evidence.member_sha256,
            "sheet_inventory_sha256" => _toml_hash(Dict("sheet_names" => ooxml.sheets)),
            "workbook_xml_byte_count" => ooxml.workbook_xml_byte_count,
            "workbook_xml_crc32" => ooxml.workbook_xml_crc32,
            "workbook_xml_sha256" => ooxml.workbook_xml_sha256,
        )
    end
    return result
end

function _static_workbook_evidence(profile)
    result = Dict{String, Any}()
    for (member, workbook) in _workbook_map(profile)
        result[member] = Dict{String, Any}(
            "member_byte_count" => workbook["byte_count"],
            "member_crc32" => workbook["outer_crc32"],
            "member_sha256" => workbook["sha256"],
            "sheet_inventory_sha256" =>
                _toml_hash(Dict("sheet_names" => workbook["sheet_names"])),
            "workbook_xml_byte_count" => workbook["workbook_xml_byte_count"],
            "workbook_xml_crc32" => workbook["workbook_xml_crc32"],
            "workbook_xml_sha256" => workbook["workbook_xml_sha256"],
        )
    end
    return result
end

"""Reconstruct the six-profile selector receipt from exact raw archive bytes."""
function selector_receipt(
        archive_bytes;
        workbook_payloads = nothing,
        workbook_xml_payloads = nothing,
    )
    profile = load_and_validate_profile()
    archive = UInt8[byte for byte in archive_bytes]
    length(archive) == ARCHIVE_BYTE_COUNT || fail("archive", "byte count mismatch")
    archive_hash = sha256_hex(archive)
    archive_hash == ARCHIVE_SHA256 || fail("archive", "SHA-256 mismatch")
    entries = Envelope.inspect_zip(
        archive;
        maximum_entries = 64,
        maximum_uncompressed_bytes = 32_000_000,
    )
    entry_evidence = _entry_evidence(entries, _archive_entry_map(profile))
    supplied = workbook_payloads !== nothing || workbook_xml_payloads !== nothing
    (workbook_payloads === nothing) == (workbook_xml_payloads === nothing) ||
        fail("selector", "workbook and workbook.xml evidence must be supplied together")
    workbook_evidence = supplied ?
        validate_extracted_evidence(archive, workbook_payloads, workbook_xml_payloads) :
        _static_workbook_evidence(profile)
    workbooks = _workbook_map(profile)
    profile_documents = Dict{String, Any}[]
    for row in sort(profile["profiles"]; by = row -> row["profile_id"])
        id = String(row["profile_id"])
        member = String(row["member"])
        sheet = String(row["sheet"])
        evidence = Dict{String, Any}(
            "archive_byte_count" => length(archive),
            "archive_entry_count" => length(entries),
            "archive_sha256" => archive_hash,
            "archive_zip_directory_valid" => true,
            "evidence_kind" => row["evidence_kind"],
            "profile_id" => id,
            "selector" => row["selector"],
            "verified" => true,
        )
        if !isempty(member)
            workbook = workbooks[member]
            selected = workbook_evidence[member]
            evidence["member"] = member
            evidence["member_byte_count"] = selected["member_byte_count"]
            evidence["member_crc32"] = entry_evidence[member]["crc32"]
            evidence["member_sha256"] = selected["member_sha256"]
            evidence["required_sheet"] = sheet
            evidence["required_sheet_present"] = sheet in String.(workbook["sheet_names"])
            evidence["sheet_inventory_sha256"] = selected["sheet_inventory_sha256"]
            evidence["workbook_xml_byte_count"] = selected["workbook_xml_byte_count"]
            evidence["workbook_xml_crc32"] = selected["workbook_xml_crc32"]
            evidence["workbook_xml_sha256"] = selected["workbook_xml_sha256"]
        else
            evidence["member"] = ""
            evidence["required_sheet"] = ""
            evidence["required_sheet_present"] = true
        end
        push!(profile_documents, evidence)
    end
    document = Dict{String, Any}(
        "adapter_schema_version" => ADAPTER_SCHEMA,
        "all_profiles_verified" => true,
        "archive_byte_count" => length(archive),
        "archive_entry_count" => length(entries),
        "archive_sha256" => archive_hash,
        "archive_zip_directory_valid" => true,
        "completion_eligibility" => "AUGUST_2026_ONLY_THESE_SIX_PROFILES",
        "excluded_other_profile_count" => 27,
        "excluded_other_profile_relabel_allowed" => false,
        "independent_extracted_payload_verification_performed" => supplied,
        "ooxml_evidence_basis" => supplied ?
            "INDEPENDENTLY_SUPPLIED_MEMBER_AND_WORKBOOK_XML_BYTES_REHASHED_AND_CRC_CHECKED" :
            "EXACT_FULL_ARCHIVE_SHA256_PLUS_PREREGISTERED_MEMBER_AND_OOXML_IDENTITIES",
        "profile_count" => length(profile_documents),
        "profiles" => profile_documents,
        "requirement_id" => "bea_industry_valuation_structural",
        "status" => "ALL_SIX_VALUATION_PROFILES_VERIFIED_NONADMITTING",
    )
    _validate_integer_controls(document, "selector")
    _expect(document["profile_count"], 6, "selector.profile_count")
    _expect(document["excluded_other_profile_count"], 27, "selector.excluded_other_profile_count")
    return document
end

function _selector_builder(evidence_provider)
    return function (archive)
        if evidence_provider === nothing
            return selector_receipt(archive)
        end
        material = evidence_provider(copy(archive))
        material isa NamedTuple || fail("evidence_provider", "must return a NamedTuple")
        hasproperty(material, :workbook_payloads) ||
            fail("evidence_provider", "missing workbook_payloads")
        hasproperty(material, :workbook_xml_payloads) ||
            fail("evidence_provider", "missing workbook_xml_payloads")
        return selector_receipt(
            archive;
            workbook_payloads = material.workbook_payloads,
            workbook_xml_payloads = material.workbook_xml_payloads,
        )
    end
end

function dry_run_plan(transaction_id = "bea-after-redefinitions-2025-annual-update-august")
    policy = _capture_policy()
    plan = Envelope.dry_run_plan(policy, transaction_id)
    return (
        status = "CANNOT_RUN_NO_NEW_PROSPECTIVE_BUNDLE_DRY_RUN_ONLY",
        policy_id = plan.policy_id,
        policy_sha256 = plan.policy_sha256,
        transaction_id = plan.transaction_id,
        requested_url = plan.requested_url,
        request_count_if_live = plan.request_count_if_live,
        network_request_count = plan.network_request_count,
        filesystem_write_count = plan.filesystem_write_count,
        profile_count = 6,
        excluded_other_profile_count = 27,
        gates = plan.gates,
    )
end

function capture_after_redefinitions_with_fetcher(;
        raw_root,
        transaction_id = "bea-after-redefinitions-2025-annual-update-august",
        actor,
        terms_reviewed_local_date,
        execute_live = false,
        fetcher = nothing,
        evidence_provider = nothing,
        timestamp_provider = nothing,
        timestamp_verifier = nothing,
        clock_source = Envelope.system_clock_source(),
    )
    policy = _capture_policy()
    return Envelope.capture_with_fetcher(
        policy;
        raw_root = raw_root,
        transaction_id = transaction_id,
        actor = actor,
        terms_reviewed_local_date = terms_reviewed_local_date,
        execute_live = execute_live,
        fetcher = fetcher,
        selector_builder = _selector_builder(evidence_provider),
        timestamp_provider = timestamp_provider,
        timestamp_verifier = timestamp_verifier,
        clock_source = clock_source,
    )
end

function validate_capture_bundle(
        bundle_path;
        evidence_provider = nothing,
        timestamp_verifier = nothing,
    )
    return Envelope.validate_bundle(
        _capture_policy(),
        bundle_path;
        selector_builder = _selector_builder(evidence_provider),
        timestamp_verifier = timestamp_verifier,
    )
end


function validate_capture_quarantine(quarantine_path)
    return Envelope.validate_quarantine(_capture_policy(), quarantine_path)
end

end # module
