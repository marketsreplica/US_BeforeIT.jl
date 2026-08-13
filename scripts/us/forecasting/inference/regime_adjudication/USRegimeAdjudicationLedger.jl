module USRegimeAdjudicationLedger

using SHA
using TOML

export ACCEPTED_REGIME_LABELS,
    CONTRAST_IDS,
    DISPOSITIONS,
    LEDGER_SCHEMA_VERSION,
    RegimeAdjudicationError,
    affected_contrast_inclusion_mask,
    build_regime_adjudication_ledger,
    computed_ledger_sha256,
    full_sample_primary_inclusion_mask,
    validate_regime_adjudication_ledger

const LEDGER_SCHEMA_VERSION =
    "beforeit-us-forecast-regime-adjudication-ledger.v1"
const CANONICALIZATION =
    "sorted_toml_excluding_artifact_content_sha256.v1"
const ARTIFACT_CLASS =
    "UPSTREAM_REGIME_ADJUDICATION_PROTOCOL_LEDGER"
const SCIENTIFIC_ROLE =
    "INFERENCE_INPUT_GOVERNANCE_ONLY_NOT_A_SCORE_OR_PROMOTION_ARTIFACT"
const CONTRAST_IDS = (
    "PANDEMIC_REGIME_CONTRAST",
    "NBER_REGIME_CONTRAST",
    "POLICY_REGIME_CONTRAST",
)
const ACCEPTED_REGIME_LABELS = (
    PANDEMIC_REGIME_CONTRAST = (
        "PRE_PANDEMIC",
        "PANDEMIC_ACUTE",
        "POST_ACUTE",
    ),
    NBER_REGIME_CONTRAST = (
        "NBER_RECESSION",
        "NBER_EXPANSION",
    ),
    POLICY_REGIME_CONTRAST = (
        "ELB_POLICY",
        "STANDARD_POLICY",
    ),
)
const ALL_ACCEPTED_LABELS = (
    ACCEPTED_REGIME_LABELS.PANDEMIC_REGIME_CONTRAST...,
    ACCEPTED_REGIME_LABELS.NBER_REGIME_CONTRAST...,
    ACCEPTED_REGIME_LABELS.POLICY_REGIME_CONTRAST...,
)
const DISPOSITIONS = (
    "REGIME_ACCEPTED",
    "REGIME_UNKNOWN_PENDING_ADJUDICATION",
    "REGIME_CONTRADICTION_QUARANTINED",
    "REGIME_CONFLICT_QUARANTINED",
)
const PENDING_ISSUE_CODES = (
    "BARE_USED_INVALID_FOR_REGIME",
    "OTHER_UNREGISTERED_FOR_REGIME",
    "UNKNOWN_OR_UNREGISTERED_RAW_TOKEN",
    "NO_RAW_REGIME_TOKEN_SUPPLIED",
    "INSUFFICIENT_EVIDENCE_FOR_ACCEPTANCE",
    "SOURCE_USAGE_PROVENANCE_OUTSIDE_REGIME_VOCABULARY",
    "NATIVE_BEA_ACCOUNTING_LABEL_OUTSIDE_REGIME_VOCABULARY",
)
const CONTRADICTION_ISSUE_CODES = (
    "MUTUALLY_EXCLUSIVE_REGIME_LABELS_PRESENT",
    "REGIME_LABEL_CONTRADICTS_CONTRAST",
)
const CONFLICT_ISSUE_CODES = (
    "SOURCE_ASSERTIONS_DISAGREE",
    "SOURCE_PROVENANCE_CONFLICT",
)
const RESERVED_ID_TOKENS = (
    "used",
    "other",
    "unknown",
    "dubious",
    "unspecified",
    "unassigned",
    "placeholder",
    "tbd",
    "todo",
    "na",
    "n/a",
    "none",
    "null",
    "missing",
)
const EVIDENCE_REF_NAMESPACES = (
    "evidence",
    "manifest",
    "source",
    "sha256",
    "doi",
    "urn",
    "https",
)
const ID_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:-]*$"
const EVIDENCE_REF_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:/#-]*$"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const INPUT_RECORD_KEYS = (
    "record_id",
    "observation_id",
    "contrast_id",
    "raw_tokens",
    "evidence_refs",
    "disposition",
    "accepted_regime_label",
    "issue_code",
)
const RECORD_KEYS = (
    INPUT_RECORD_KEYS...,
    "raw_token_count",
    "include_in_full_sample_primary",
    "include_in_affected_regime_contrast",
)
const ARTIFACT_KEYS = (
    "schema_version",
    "ledger_id",
    "artifact_class",
    "scientific_role",
    "canonicalization",
    "content_sha256",
    "scoring_artifact",
    "promotion_artifact",
    "empirical_result_artifact",
)
const PROTOCOL_KEYS = (
    "raw_token_policy",
    "raw_token_evidence_policy",
    "full_sample_primary_policy",
    "full_sample_mask_scope",
    "affected_contrast_policy",
    "bare_used_policy",
    "other_unknown_policy",
    "source_usage_provenance_policy",
    "native_bea_accounting_label_policy",
)
const SUMMARY_KEYS = (
    "observation_count",
    "record_count",
    "raw_token_count",
    "accepted_count",
    "pending_count",
    "contradiction_count",
    "conflict_count",
    "affected_contrast_included_count",
    "affected_contrast_excluded_count",
    "full_sample_primary_included_count",
)
const MASK_KEYS = (
    "contrast_id",
    "observation_ids",
    "inclusion_mask",
    "included_count",
    "excluded_count",
)
const INVENTORY_KEYS = (
    "sequence",
    "record_id",
    "observation_id",
    "contrast_id",
    "token_index",
    "raw_token",
    "evidence_ref",
)
const TOP_LEVEL_KEYS = (
    "artifact",
    "protocol",
    "summary",
    "observation_ids",
    "full_sample_primary_mask",
    "contrast_masks",
    "raw_token_inventory",
    "records",
)

struct RegimeAdjudicationError <: Exception
    message::String
end

Base.showerror(io::IO, error::RegimeAdjudicationError) =
    print(io, error.message)

fail(location, message) =
    throw(RegimeAdjudicationError("$location: $message"))

function _expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return Dict{String, Any}(String(key) => item for (key, item) in value)
end

function _expect_exact_keys(value, expected, location)
    table = _expect_table(value, location)
    actual_keys = Set(keys(table))
    expected_keys = Set(String.(expected))
    actual_keys == expected_keys ||
        fail(
        location,
        "keys must be exactly $(sort!(collect(expected_keys))); got " *
            "$(sort!(collect(actual_keys)))",
    )
    return table
end

function _expect_vector(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    return value
end

function _expect_string(value, location; allow_empty = false)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) ||
        fail(location, "must not have leading or trailing whitespace")
    (allow_empty || !isempty(text)) ||
        fail(location, "must not be empty")
    return text
end

function _expect_bool(value, location)
    value isa Bool || fail(location, "must be Boolean")
    return value
end

function _expect_integer(value, location; minimum = 0)
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer, not Bool")
    result = try
        Int(value)
    catch
        fail(location, "is outside the supported integer range")
    end
    result >= minimum || fail(location, "must be at least $minimum")
    return result
end

function _expect_exact(value, expected, location)
    value == expected ||
        fail(location, "must equal $(repr(expected)); got $(repr(value))")
    return value
end

function _validate_id(value, location)
    text = _expect_string(value, location)
    occursin(ID_PATTERN, text) ||
        fail(location, "contains unsupported identifier characters")
    lowercase(text) in RESERVED_ID_TOKENS &&
        fail(location, "is a reserved placeholder identifier")
    return text
end

function _accepted_labels(contrast_id)
    contrast_id == "PANDEMIC_REGIME_CONTRAST" &&
        return ACCEPTED_REGIME_LABELS.PANDEMIC_REGIME_CONTRAST
    contrast_id == "NBER_REGIME_CONTRAST" &&
        return ACCEPTED_REGIME_LABELS.NBER_REGIME_CONTRAST
    contrast_id == "POLICY_REGIME_CONTRAST" &&
        return ACCEPTED_REGIME_LABELS.POLICY_REGIME_CONTRAST
    return fail("contrast_id", "unknown contrast")
end

function _raw_tokens(value, location)
    tokens = Tuple(
        _expect_string(token, "$location[$index]")
            for (index, token) in enumerate(_expect_vector(value, location))
    )
    return tokens
end

function _evidence_refs(value, token_count, location)
    refs = Tuple(
        let
                ref = _expect_string(item, "$location[$index]")
                occursin(EVIDENCE_REF_PATTERN, ref) ||
                fail(
                    "$location[$index]",
                    "contains unsupported evidence-reference characters",
                )
                separator = findfirst(==(':'), ref)
                separator === nothing &&
                fail(
                    "$location[$index]",
                    "must use a recognized evidence-reference namespace",
                )
                namespace = lowercase(ref[firstindex(ref):(separator - 1)])
                namespace in EVIDENCE_REF_NAMESPACES ||
                fail(
                    "$location[$index]",
                    "uses an unrecognized evidence-reference namespace",
                )
                separator < lastindex(ref) ||
                fail("$location[$index]", "has an empty evidence payload")
                payload = ref[(separator + 1):lastindex(ref)]
                lowercase(payload) in RESERVED_ID_TOKENS &&
                fail(
                    "$location[$index]",
                    "contains a reserved placeholder payload",
                )
                components = [
                    component for component in
                    split(lowercase(payload), r"[._:/#-]+")
                    if !isempty(component)
                ]
                !isempty(components) ||
                fail("$location[$index]", "has an empty evidence payload")
                any(component -> component in RESERVED_ID_TOKENS, components) &&
                fail(
                    "$location[$index]",
                    "contains a reserved placeholder component",
                )
                ref
        end for (index, item) in enumerate(_expect_vector(value, location))
    )
    length(refs) == token_count ||
        fail(location, "must contain exactly one reference per raw token")
    return refs
end

_lower_token(token) = lowercase(String(token))

function _is_source_usage_provenance(token)
    upper = uppercase(String(token))
    return startswith(upper, "SOURCE_USAGE_") ||
        startswith(upper, "PROVENANCE_") ||
        startswith(upper, "USED_AS_SOURCE_")
end

function _validate_pending_issue(tokens, issue_code, location)
    issue_code in PENDING_ISSUE_CODES ||
        fail(location, "unknown pending-adjudication issue code")
    lowered = _lower_token.(tokens)
    has_used = "used" in lowered
    has_other = "other" in lowered
    has_source_usage = any(_is_source_usage_provenance, tokens)
    has_source_usage &&
        issue_code !=
        "SOURCE_USAGE_PROVENANCE_OUTSIDE_REGIME_VOCABULARY" &&
        fail(location, "typed source-usage provenance requires its explicit reason")
    has_used && has_other &&
        issue_code !=
        "NATIVE_BEA_ACCOUNTING_LABEL_OUTSIDE_REGIME_VOCABULARY" &&
        fail(location, "combined Used/Other tokens require the native-BEA reason")
    has_used && !has_other &&
        issue_code ∉ (
        "BARE_USED_INVALID_FOR_REGIME",
        "NATIVE_BEA_ACCOUNTING_LABEL_OUTSIDE_REGIME_VOCABULARY",
    ) &&
        fail(location, "raw Used requires an explicit out-of-vocabulary reason")
    has_other && !has_used &&
        issue_code ∉ (
        "OTHER_UNREGISTERED_FOR_REGIME",
        "NATIVE_BEA_ACCOUNTING_LABEL_OUTSIDE_REGIME_VOCABULARY",
    ) &&
        fail(location, "raw Other requires an explicit out-of-vocabulary reason")
    if issue_code == "BARE_USED_INVALID_FOR_REGIME"
        "used" in lowered ||
            fail(location, "bare-Used issue requires a raw Used token")
    elseif issue_code == "OTHER_UNREGISTERED_FOR_REGIME"
        "other" in lowered ||
            fail(location, "Other issue requires a raw Other token")
    elseif issue_code == "UNKNOWN_OR_UNREGISTERED_RAW_TOKEN"
        !isempty(tokens) ||
            fail(location, "unknown-token issue requires a raw token")
        any(
            token ->
            token ∉ ALL_ACCEPTED_LABELS &&
                _lower_token(token) ∉ ("used", "other") &&
                !_is_source_usage_provenance(token),
            tokens,
        ) || fail(
            location,
            "unknown-token issue requires an unregistered non-Used/Other token",
        )
    elseif issue_code == "NO_RAW_REGIME_TOKEN_SUPPLIED"
        isempty(tokens) ||
            fail(location, "no-token issue requires an empty raw token array")
    elseif issue_code == "INSUFFICIENT_EVIDENCE_FOR_ACCEPTANCE"
        !isempty(tokens) ||
            fail(location, "insufficient-evidence issue requires a raw token")
    elseif issue_code ==
            "SOURCE_USAGE_PROVENANCE_OUTSIDE_REGIME_VOCABULARY"
        any(_is_source_usage_provenance, tokens) ||
            fail(location, "source-usage issue requires a typed provenance token")
    elseif issue_code ==
            "NATIVE_BEA_ACCOUNTING_LABEL_OUTSIDE_REGIME_VOCABULARY"
        any(token -> _lower_token(token) in ("used", "other"), tokens) ||
            fail(location, "BEA-label issue requires raw Used or Other")
    end
    return nothing
end

function _validate_record_semantics(
        contrast_id,
        tokens,
        evidence_refs,
        disposition,
        accepted_label,
        issue_code,
        include_affected,
        location,
    )
    disposition in DISPOSITIONS ||
        fail("$location.disposition", "unknown disposition")
    allowed_labels = _accepted_labels(contrast_id)
    lowered_tokens = _lower_token.(tokens)
    contains_pending_only_token =
        any(token -> token in ("used", "other"), lowered_tokens) ||
        any(_is_source_usage_provenance, tokens)
    contains_pending_only_token &&
        disposition != "REGIME_UNKNOWN_PENDING_ADJUDICATION" &&
        fail(
        "$location.disposition",
        "Used, Other, and source-usage provenance require pending adjudication",
    )
    if disposition == "REGIME_ACCEPTED"
        issue_code == "NONE" ||
            fail("$location.issue_code", "accepted regime requires NONE")
        accepted_label in allowed_labels ||
            fail(
            "$location.accepted_regime_label",
            "is not registered for $contrast_id",
        )
        !isempty(tokens) ||
            fail("$location.raw_tokens", "accepted regime requires raw evidence")
        all(token -> token == accepted_label, tokens) ||
            fail(
            "$location.raw_tokens",
            "accepted regime requires every preserved token to equal the accepted label",
        )
        include_affected ||
            fail("$location.include_in_affected_regime_contrast", "must be true")
    else
        accepted_label == "NOT_ACCEPTED" ||
            fail(
            "$location.accepted_regime_label",
            "nonaccepted disposition requires NOT_ACCEPTED",
        )
        !include_affected ||
            fail(
            "$location.include_in_affected_regime_contrast",
            "unresolved or conflicted record must be excluded",
        )
        if disposition == "REGIME_UNKNOWN_PENDING_ADJUDICATION"
            _validate_pending_issue(tokens, issue_code, "$location.issue_code")
        elseif disposition == "REGIME_CONTRADICTION_QUARANTINED"
            issue_code in CONTRADICTION_ISSUE_CODES ||
                fail("$location.issue_code", "unknown contradiction issue code")
            all(token -> token in ALL_ACCEPTED_LABELS, tokens) ||
                fail(
                "$location.raw_tokens",
                "contradiction records may contain only registered regime labels",
            )
            distinct = Set(tokens)
            if issue_code == "MUTUALLY_EXCLUSIVE_REGIME_LABELS_PRESENT"
                all(token -> token in allowed_labels, tokens) ||
                    fail(
                    "$location.raw_tokens",
                    "mutually exclusive labels must belong to the affected contrast",
                )
                count(token -> token in allowed_labels, distinct) >= 2 ||
                    fail(
                    "$location.raw_tokens",
                    "contradiction requires two registered mutually exclusive labels",
                )
                length(Set(evidence_refs)) >= 2 ||
                    fail(
                    "$location.evidence_refs",
                    "mutually exclusive labels require distinct evidence references",
                )
            else
                any(
                    token ->
                    token in ALL_ACCEPTED_LABELS &&
                        token ∉ allowed_labels,
                    distinct,
                ) || fail(
                    "$location.raw_tokens",
                    "contrast contradiction requires a label from another contrast",
                )
            end
        else
            issue_code in CONFLICT_ISSUE_CODES ||
                fail("$location.issue_code", "unknown source-conflict issue code")
            all(token -> token in allowed_labels, tokens) ||
                fail(
                "$location.raw_tokens",
                "source conflicts may contain only labels registered for the affected contrast",
            )
            if issue_code == "SOURCE_ASSERTIONS_DISAGREE"
                length(Set(tokens)) >= 2 ||
                    fail(
                    "$location.raw_tokens",
                    "assertion disagreement requires at least two distinct raw tokens",
                )
            end
            length(Set(evidence_refs)) >= 2 ||
                fail(
                "$location.evidence_refs",
                "source conflict requires distinct evidence references",
            )
        end
    end
    return nothing
end

function _validate_record(value, sequence)
    location = "records[$sequence]"
    row = _expect_exact_keys(value, RECORD_KEYS, location)
    record_id = _validate_id(row["record_id"], "$location.record_id")
    observation_id =
        _validate_id(row["observation_id"], "$location.observation_id")
    contrast_id = _expect_string(row["contrast_id"], "$location.contrast_id")
    contrast_id in CONTRAST_IDS ||
        fail("$location.contrast_id", "unknown contrast")
    tokens = _raw_tokens(row["raw_tokens"], "$location.raw_tokens")
    evidence_refs = _evidence_refs(
        row["evidence_refs"],
        length(tokens),
        "$location.evidence_refs",
    )
    raw_token_count = _expect_integer(
        row["raw_token_count"],
        "$location.raw_token_count",
    )
    raw_token_count == length(tokens) ||
        fail("$location.raw_token_count", "does not match preserved tokens")
    disposition =
        _expect_string(row["disposition"], "$location.disposition")
    accepted_label = _expect_string(
        row["accepted_regime_label"],
        "$location.accepted_regime_label",
    )
    issue_code = _expect_string(row["issue_code"], "$location.issue_code")
    include_full = _expect_bool(
        row["include_in_full_sample_primary"],
        "$location.include_in_full_sample_primary",
    )
    include_full ||
        fail(
        "$location.include_in_full_sample_primary",
        "full-sample primary analysis must preserve every observation",
    )
    include_affected = _expect_bool(
        row["include_in_affected_regime_contrast"],
        "$location.include_in_affected_regime_contrast",
    )
    _validate_record_semantics(
        contrast_id,
        tokens,
        evidence_refs,
        disposition,
        accepted_label,
        issue_code,
        include_affected,
        location,
    )
    return (;
        record_id,
        observation_id,
        contrast_id,
        raw_tokens = tokens,
        evidence_refs,
        raw_token_count,
        disposition,
        accepted_regime_label = accepted_label,
        issue_code,
        include_in_full_sample_primary = include_full,
        include_in_affected_regime_contrast = include_affected,
    )
end

function _canonical_content_bytes(document)
    copy = deepcopy(document)
    artifact = get(copy, "artifact", nothing)
    artifact isa AbstractDict ||
        fail("ledger.artifact", "missing artifact table")
    haskey(artifact, "content_sha256") ||
        fail("ledger.artifact", "missing content_sha256")
    delete!(artifact, "content_sha256")
    io = IOBuffer()
    TOML.print(io, copy; sorted = true)
    bytes = take!(io)
    isempty(bytes) || bytes[end] == UInt8('\n') ||
        push!(bytes, UInt8('\n'))
    return bytes
end

computed_ledger_sha256(document) =
    bytes2hex(sha256(_canonical_content_bytes(document)))

function _expected_inventory(records)
    inventory = Dict{String, Any}[]
    sequence = 0
    for record in records
        for (token_index, (raw_token, evidence_ref)) in enumerate(
                zip(record.raw_tokens, record.evidence_refs),
            )
            sequence += 1
            push!(
                inventory,
                Dict{String, Any}(
                    "sequence" => sequence,
                    "record_id" => record.record_id,
                    "observation_id" => record.observation_id,
                    "contrast_id" => record.contrast_id,
                    "token_index" => token_index,
                    "raw_token" => raw_token,
                    "evidence_ref" => evidence_ref,
                ),
            )
        end
    end
    return inventory
end

function _expected_masks(observation_ids, records)
    return [
        let
                by_observation = Dict(
                    record.observation_id =>
                    record.include_in_affected_regime_contrast
                    for record in records
                    if record.contrast_id == contrast_id
                )
                mask = [by_observation[id] for id in observation_ids]
                Dict{String, Any}(
                    "contrast_id" => contrast_id,
                    "observation_ids" => collect(observation_ids),
                    "inclusion_mask" => mask,
                    "included_count" => count(identity, mask),
                    "excluded_count" => count(!, mask),
                )
        end for contrast_id in CONTRAST_IDS
    ]
end

function _expected_summary(observation_ids, records)
    dispositions = getproperty.(records, :disposition)
    included = count(
        record -> record.include_in_affected_regime_contrast,
        records,
    )
    return Dict{String, Any}(
        "observation_count" => length(observation_ids),
        "record_count" => length(records),
        "raw_token_count" => sum(record.raw_token_count for record in records),
        "accepted_count" => count(==("REGIME_ACCEPTED"), dispositions),
        "pending_count" => count(
            ==("REGIME_UNKNOWN_PENDING_ADJUDICATION"),
            dispositions,
        ),
        "contradiction_count" => count(
            ==("REGIME_CONTRADICTION_QUARANTINED"),
            dispositions,
        ),
        "conflict_count" =>
            count(==("REGIME_CONFLICT_QUARANTINED"), dispositions),
        "affected_contrast_included_count" => included,
        "affected_contrast_excluded_count" => length(records) - included,
        "full_sample_primary_included_count" => length(observation_ids),
    )
end

function _validate_inventory(value, expected)
    rows = _expect_vector(value, "raw_token_inventory")
    validated = Dict{String, Any}[]
    for (index, raw_row) in enumerate(rows)
        row = _expect_exact_keys(
            raw_row,
            INVENTORY_KEYS,
            "raw_token_inventory[$index]",
        )
        push!(
            validated,
            Dict{String, Any}(
                "sequence" => _expect_integer(
                    row["sequence"],
                    "raw_token_inventory[$index].sequence";
                    minimum = 1,
                ),
                "record_id" => _expect_string(
                    row["record_id"],
                    "raw_token_inventory[$index].record_id",
                ),
                "observation_id" => _expect_string(
                    row["observation_id"],
                    "raw_token_inventory[$index].observation_id",
                ),
                "contrast_id" => _expect_string(
                    row["contrast_id"],
                    "raw_token_inventory[$index].contrast_id",
                ),
                "token_index" => _expect_integer(
                    row["token_index"],
                    "raw_token_inventory[$index].token_index";
                    minimum = 1,
                ),
                "raw_token" => _expect_string(
                    row["raw_token"],
                    "raw_token_inventory[$index].raw_token",
                ),
                "evidence_ref" => _expect_string(
                    row["evidence_ref"],
                    "raw_token_inventory[$index].evidence_ref",
                ),
            ),
        )
    end
    validated == expected ||
        fail(
        "raw_token_inventory",
        "does not preserve every raw token in record and token order",
    )
    return Tuple(
        (
                sequence = row["sequence"],
                record_id = row["record_id"],
                observation_id = row["observation_id"],
                contrast_id = row["contrast_id"],
                token_index = row["token_index"],
                raw_token = row["raw_token"],
                evidence_ref = row["evidence_ref"],
            ) for row in validated
    )
end

function _validate_masks(value, observation_ids, expected)
    rows = _expect_vector(value, "contrast_masks")
    length(rows) == length(CONTRAST_IDS) ||
        fail("contrast_masks", "must contain every registered contrast")
    for (index, raw_row) in enumerate(rows)
        location = "contrast_masks[$index]"
        row = _expect_exact_keys(raw_row, MASK_KEYS, location)
        _expect_exact(
            _expect_string(row["contrast_id"], "$location.contrast_id"),
            CONTRAST_IDS[index],
            "$location.contrast_id",
        )
        ids = Tuple(
            _expect_string(id, "$location.observation_ids")
                for id in _expect_vector(
                    row["observation_ids"],
                    "$location.observation_ids",
                )
        )
        ids == observation_ids ||
            fail("$location.observation_ids", "must preserve registry order")
        mask = Tuple(
            _expect_bool(item, "$location.inclusion_mask")
                for item in _expect_vector(
                    row["inclusion_mask"],
                    "$location.inclusion_mask",
                )
        )
        length(mask) == length(observation_ids) ||
            fail("$location.inclusion_mask", "length mismatch")
        included =
            _expect_integer(row["included_count"], "$location.included_count")
        excluded =
            _expect_integer(row["excluded_count"], "$location.excluded_count")
        included == count(identity, mask) ||
            fail("$location.included_count", "does not match mask")
        excluded == count(!, mask) ||
            fail("$location.excluded_count", "does not match mask")
        row == expected[index] ||
            fail(location, "mask differs from record dispositions")
    end
    return Tuple(
        (
                contrast_id = row["contrast_id"],
                observation_ids = Tuple(row["observation_ids"]),
                inclusion_mask = Tuple(row["inclusion_mask"]),
                included_count = row["included_count"],
                excluded_count = row["excluded_count"],
            ) for row in expected
    )
end

"""
    validate_regime_adjudication_ledger(document)

Validate a closed, self-hashed upstream adjudication ledger. The returned
named tuples do not expose mutable arrays or dictionaries from `document`.
"""
function validate_regime_adjudication_ledger(document)
    root = _expect_exact_keys(document, TOP_LEVEL_KEYS, "ledger")
    artifact =
        _expect_exact_keys(root["artifact"], ARTIFACT_KEYS, "ledger.artifact")
    _expect_exact(
        artifact["schema_version"],
        LEDGER_SCHEMA_VERSION,
        "ledger.artifact.schema_version",
    )
    ledger_id = _validate_id(artifact["ledger_id"], "ledger.artifact.ledger_id")
    _expect_exact(
        artifact["artifact_class"],
        ARTIFACT_CLASS,
        "ledger.artifact.artifact_class",
    )
    _expect_exact(
        artifact["scientific_role"],
        SCIENTIFIC_ROLE,
        "ledger.artifact.scientific_role",
    )
    _expect_exact(
        artifact["canonicalization"],
        CANONICALIZATION,
        "ledger.artifact.canonicalization",
    )
    declared = _expect_string(
        artifact["content_sha256"],
        "ledger.artifact.content_sha256",
    )
    occursin(HASH_PATTERN, declared) ||
        fail("ledger.artifact.content_sha256", "must be lowercase SHA-256")
    declared == computed_ledger_sha256(root) ||
        fail("ledger.artifact.content_sha256", "semantic digest mismatch")
    for field in (
            "scoring_artifact",
            "promotion_artifact",
            "empirical_result_artifact",
        )
        _expect_bool(artifact[field], "ledger.artifact.$field") === false ||
            fail("ledger.artifact.$field", "must remain false")
    end

    protocol =
        _expect_exact_keys(root["protocol"], PROTOCOL_KEYS, "ledger.protocol")
    expected_protocol = Dict{String, Any}(
        "raw_token_policy" =>
            "PRESERVE_EXACT_ADMITTED_ORDER_CASE_AND_MULTIPLICITY_REJECT_SURROUNDING_WHITESPACE_NO_COERCION",
        "raw_token_evidence_policy" =>
            "EXACTLY_ONE_CLOSED_NAMESPACE_NONPLACEHOLDER_EVIDENCE_REFERENCE_PER_RAW_TOKEN",
        "full_sample_primary_policy" =>
            "PRESERVE_ALL_OBSERVATIONS_UNCHANGED",
        "full_sample_mask_scope" =>
            "REGIME_ONLY_MUST_BE_CONJOINED_WITH_SEPARATE_SCORE_CELL_ELIGIBILITY",
        "affected_contrast_policy" =>
            "EXCLUDE_UNRESOLVED_OR_CONFLICTED_ONLY_FROM_AFFECTED_REGIME_CONTRAST",
        "bare_used_policy" =>
            "PRESERVE_RAW_TOKEN_PENDING_INVALID_FOR_REGIME_NEVER_ACCEPT_OR_COERCE",
        "other_unknown_policy" =>
            "PRESERVE_RAW_TOKEN_PENDING_NEVER_ACCEPT_OR_COERCE",
        "source_usage_provenance_policy" =>
            "TYPED_PROVENANCE_IS_OUTSIDE_REGIME_VOCABULARY",
        "native_bea_accounting_label_policy" =>
            "NATIVE_USED_OTHER_LABELS_ARE_OUTSIDE_REGIME_VOCABULARY",
    )
    protocol == expected_protocol ||
        fail("ledger.protocol", "protocol constants differ from closed v1 rules")

    observation_ids = Tuple(
        _validate_id(value, "ledger.observation_ids[$index]")
            for (index, value) in enumerate(
                _expect_vector(root["observation_ids"], "ledger.observation_ids"),
            )
    )
    !isempty(observation_ids) ||
        fail("ledger.observation_ids", "must not be empty")
    length(observation_ids) == length(unique(observation_ids)) ||
        fail("ledger.observation_ids", "duplicate observation ID")

    raw_records = _expect_vector(root["records"], "ledger.records")
    length(raw_records) == length(observation_ids) * length(CONTRAST_IDS) ||
        fail("ledger.records", "must contain one record per observation/contrast")
    records = Tuple(
        _validate_record(row, sequence)
            for (sequence, row) in enumerate(raw_records)
    )
    record_ids = getproperty.(records, :record_id)
    length(record_ids) == length(unique(record_ids)) ||
        fail("ledger.records", "duplicate record ID")
    observed_pairs =
        Tuple((row.observation_id, row.contrast_id) for row in records)
    expected_pairs = Tuple(
        (observation_id, contrast_id)
            for observation_id in observation_ids
            for contrast_id in CONTRAST_IDS
    )
    observed_pairs == expected_pairs ||
        fail(
        "ledger.records",
        "records must exhaust the observation/contrast grid in registry order",
    )

    full_mask = Tuple(
        _expect_bool(value, "ledger.full_sample_primary_mask[$index]")
            for (index, value) in enumerate(
                _expect_vector(
                    root["full_sample_primary_mask"],
                    "ledger.full_sample_primary_mask",
                ),
            )
    )
    length(full_mask) == length(observation_ids) ||
        fail("ledger.full_sample_primary_mask", "length mismatch")
    all(full_mask) ||
        fail(
        "ledger.full_sample_primary_mask",
        "full-sample primary analysis must retain every observation",
    )

    expected_inventory = _expected_inventory(records)
    inventory =
        _validate_inventory(root["raw_token_inventory"], expected_inventory)
    expected_masks = _expected_masks(observation_ids, records)
    masks = _validate_masks(
        root["contrast_masks"],
        observation_ids,
        expected_masks,
    )
    expected_summary = _expected_summary(observation_ids, records)
    summary =
        _expect_exact_keys(root["summary"], SUMMARY_KEYS, "ledger.summary")
    for key in SUMMARY_KEYS
        _expect_integer(summary[key], "ledger.summary.$key")
    end
    summary == expected_summary ||
        fail("ledger.summary", "counts are not exhaustive or internally consistent")

    return (;
        schema_version = LEDGER_SCHEMA_VERSION,
        ledger_id,
        artifact_class = ARTIFACT_CLASS,
        scientific_role = SCIENTIFIC_ROLE,
        content_sha256 = declared,
        observation_ids,
        full_sample_primary_mask = full_mask,
        contrast_masks = masks,
        raw_token_inventory = inventory,
        records,
        summary = (;
            observation_count = summary["observation_count"],
            record_count = summary["record_count"],
            raw_token_count = summary["raw_token_count"],
            accepted_count = summary["accepted_count"],
            pending_count = summary["pending_count"],
            contradiction_count = summary["contradiction_count"],
            conflict_count = summary["conflict_count"],
            affected_contrast_included_count =
                summary["affected_contrast_included_count"],
            affected_contrast_excluded_count =
                summary["affected_contrast_excluded_count"],
            full_sample_primary_included_count =
                summary["full_sample_primary_included_count"],
        ),
        scoring_artifact = false,
        promotion_artifact = false,
        empirical_result_artifact = false,
    )
end

function _input_record(value, location)
    row = _expect_exact_keys(value, INPUT_RECORD_KEYS, location)
    record_id = _validate_id(row["record_id"], "$location.record_id")
    observation_id =
        _validate_id(row["observation_id"], "$location.observation_id")
    contrast_id = _expect_string(row["contrast_id"], "$location.contrast_id")
    contrast_id in CONTRAST_IDS ||
        fail("$location.contrast_id", "unknown contrast")
    tokens = _raw_tokens(row["raw_tokens"], "$location.raw_tokens")
    evidence_refs = _evidence_refs(
        row["evidence_refs"],
        length(tokens),
        "$location.evidence_refs",
    )
    disposition = _expect_string(row["disposition"], "$location.disposition")
    disposition in DISPOSITIONS ||
        fail("$location.disposition", "unknown disposition")
    accepted_label = _expect_string(
        row["accepted_regime_label"],
        "$location.accepted_regime_label",
    )
    issue_code = _expect_string(row["issue_code"], "$location.issue_code")
    include_affected = disposition == "REGIME_ACCEPTED"
    _validate_record_semantics(
        contrast_id,
        tokens,
        evidence_refs,
        disposition,
        accepted_label,
        issue_code,
        include_affected,
        location,
    )
    return Dict{String, Any}(
        "record_id" => record_id,
        "observation_id" => observation_id,
        "contrast_id" => contrast_id,
        "raw_tokens" => collect(tokens),
        "evidence_refs" => collect(evidence_refs),
        "disposition" => disposition,
        "accepted_regime_label" => accepted_label,
        "issue_code" => issue_code,
        "raw_token_count" => length(tokens),
        "include_in_full_sample_primary" => true,
        "include_in_affected_regime_contrast" => include_affected,
    )
end

"""
    build_regime_adjudication_ledger(ledger_id, observation_ids, records)

Build and immediately validate a deterministic observation-by-contrast ledger.
Input records may arrive in any order but must exhaust the registered grid.
"""
function build_regime_adjudication_ledger(
        ledger_id,
        observation_ids,
        records,
    )
    validated_ledger_id = _validate_id(ledger_id, "ledger_id")
    ids = Tuple(
        _validate_id(value, "observation_ids[$index]")
            for (index, value) in enumerate(
                _expect_vector(observation_ids, "observation_ids"),
            )
    )
    !isempty(ids) || fail("observation_ids", "must not be empty")
    length(ids) == length(unique(ids)) ||
        fail("observation_ids", "duplicate observation ID")
    input_rows = [
        _input_record(value, "records[$index]")
            for (index, value) in enumerate(_expect_vector(records, "records"))
    ]
    record_ids = [row["record_id"] for row in input_rows]
    length(record_ids) == length(unique(record_ids)) ||
        fail("records", "duplicate record ID")
    by_pair = Dict{Tuple{String, String}, Dict{String, Any}}()
    for row in input_rows
        pair = (row["observation_id"], row["contrast_id"])
        haskey(by_pair, pair) &&
            fail("records", "duplicate observation/contrast pair $pair")
        row["observation_id"] in ids ||
            fail("records", "observation ID is absent from the registry")
        by_pair[pair] = row
    end
    expected_pairs = Tuple(
        (observation_id, contrast_id)
            for observation_id in ids
            for contrast_id in CONTRAST_IDS
    )
    Set(keys(by_pair)) == Set(expected_pairs) ||
        fail("records", "input does not exhaust the observation/contrast grid")
    ordered_rows = [by_pair[pair] for pair in expected_pairs]
    immutable_rows = Tuple(
        _validate_record(row, index)
            for (index, row) in enumerate(ordered_rows)
    )
    inventory = _expected_inventory(immutable_rows)
    masks = _expected_masks(ids, immutable_rows)
    summary = _expected_summary(ids, immutable_rows)
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => LEDGER_SCHEMA_VERSION,
            "ledger_id" => validated_ledger_id,
            "artifact_class" => ARTIFACT_CLASS,
            "scientific_role" => SCIENTIFIC_ROLE,
            "canonicalization" => CANONICALIZATION,
            "content_sha256" => repeat("0", 64),
            "scoring_artifact" => false,
            "promotion_artifact" => false,
            "empirical_result_artifact" => false,
        ),
        "protocol" => Dict{String, Any}(
            "raw_token_policy" =>
                "PRESERVE_EXACT_ADMITTED_ORDER_CASE_AND_MULTIPLICITY_REJECT_SURROUNDING_WHITESPACE_NO_COERCION",
            "raw_token_evidence_policy" =>
                "EXACTLY_ONE_CLOSED_NAMESPACE_NONPLACEHOLDER_EVIDENCE_REFERENCE_PER_RAW_TOKEN",
            "full_sample_primary_policy" =>
                "PRESERVE_ALL_OBSERVATIONS_UNCHANGED",
            "full_sample_mask_scope" =>
                "REGIME_ONLY_MUST_BE_CONJOINED_WITH_SEPARATE_SCORE_CELL_ELIGIBILITY",
            "affected_contrast_policy" =>
                "EXCLUDE_UNRESOLVED_OR_CONFLICTED_ONLY_FROM_AFFECTED_REGIME_CONTRAST",
            "bare_used_policy" =>
                "PRESERVE_RAW_TOKEN_PENDING_INVALID_FOR_REGIME_NEVER_ACCEPT_OR_COERCE",
            "other_unknown_policy" =>
                "PRESERVE_RAW_TOKEN_PENDING_NEVER_ACCEPT_OR_COERCE",
            "source_usage_provenance_policy" =>
                "TYPED_PROVENANCE_IS_OUTSIDE_REGIME_VOCABULARY",
            "native_bea_accounting_label_policy" =>
                "NATIVE_USED_OTHER_LABELS_ARE_OUTSIDE_REGIME_VOCABULARY",
        ),
        "summary" => summary,
        "observation_ids" => collect(ids),
        "full_sample_primary_mask" => fill(true, length(ids)),
        "contrast_masks" => masks,
        "raw_token_inventory" => inventory,
        "records" => ordered_rows,
    )
    document["artifact"]["content_sha256"] =
        computed_ledger_sha256(document)
    validate_regime_adjudication_ledger(document)
    return document
end

function affected_contrast_inclusion_mask(validated, contrast_id)
    String(contrast_id) in CONTRAST_IDS ||
        fail("contrast_id", "unknown contrast")
    matches = [
        mask for mask in validated.contrast_masks if
            mask.contrast_id == String(contrast_id)
    ]
    length(matches) == 1 ||
        fail("contrast_masks", "validated ledger lacks an exact contrast mask")
    return only(matches).inclusion_mask
end

"""
    full_sample_primary_inclusion_mask(validated)

Return only the regime-adjudication component of full-sample eligibility.
Downstream inference must conjoin it with independently validated score-cell,
pairing, maturity, target, horizon, and model-execution eligibility.
"""
function full_sample_primary_inclusion_mask(validated)
    all(validated.full_sample_primary_mask) ||
        fail("full_sample_primary_mask", "must retain every observation")
    return validated.full_sample_primary_mask
end

end
