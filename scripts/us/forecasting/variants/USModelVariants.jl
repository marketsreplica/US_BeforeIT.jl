module USModelVariants

using SHA
using TOML

export DEFAULT_CROSSWALK_PATH,
    DEFAULT_VARIANTS_PATH,
    RegistryValidationError,
    approval_payload_sha256,
    computed_artifact_sha256,
    expected_gate_attestation,
    load_registry,
    registry_report,
    require_closed_gate,
    validate_crosswalk,
    validate_variants

const DEFAULT_CROSSWALK_PATH = joinpath(@__DIR__, "crosswalk.toml")
const DEFAULT_VARIANTS_PATH = joinpath(@__DIR__, "baseline_variants.toml")
const CROSSWALK_SCHEMA = "beforeit-paper-code-crosswalk.v1"
const VARIANTS_SCHEMA = "beforeit-model-variant-baseline.v1"
const BASELINE_COMMIT = "6030f7558a9956a99465a09e31c51f37df198c90"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const SIGNATURE_PATTERN = r"^sha256:[0-9a-f]{64}$"
const SIGNED_AT_PATTERN =
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
const IDENTIFIER_PATTERN = r"^[a-z0-9][a-z0-9_]*$"
const REPOSITORY_EVIDENCE_PATTERN =
    r"^repo:[A-Za-z0-9._/-]+(?::[0-9]+(?:-[0-9]+)?)?$"
const COMMIT_EVIDENCE_PATTERN =
    r"^commit:[0-9a-f]{40}:[A-Za-z0-9._/-]+:[0-9]+(?:-[0-9]+)?$"
const PENDING_EVIDENCE_PATTERN = r"^pending:[a-z0-9][a-z0-9_]*$"
const EVIDENCE_PREFIXES = Dict(
    "paper_evidence" => ("paper:", "paper_gap:"),
    "code_evidence" => ("repo:", "commit:"),
    "test_evidence" => ("repo:", "pending:"),
)

const VARIANT_IDS = [
    "printed_paper_reference",
    "upstream_compatible_6030f75",
    "reviewed_us_port",
    "corrected_candidate",
]

const EXPECTED_ENTRY_IDS = Set(
    [
        "paper_typo_a26_financing_gap",
        "paper_typo_a55_a56_debt_sign",
        "paper_typo_c4_bank_profit_interest_sign",
        "diff_01_buyer_price_weight",
        "diff_02_buyer_size_available_supply",
        "diff_03_sector_price_index_weighting",
        "diff_04_realized_input_price_profit",
        "diff_05_capacity_capped_desired_scale",
        "diff_06_credit_headroom_installment",
        "diff_07_stochastic_exogenous_innovations",
        "diff_08_combined_retail_priority",
        "diff_09_firm_before_retail_allocation",
        "diff_10_phantom_demand_second_pass",
        "diff_11_price_renormalized_final_demand",
        "diff_12_zero_intercept_taylor_regression",
        "diff_13_zeroed_sector_product_tax",
        "diff_14_total_gfcf_housing_weights",
        "diff_15_profit_concept_tax_dividend",
        "diff_16_export_and_investment_tax_mapping",
        "diff_17_scaled_agent_population",
        "diff_18_labor_round_robin_matching",
        "diff_19_min_productivity_floor",
        "convention_matlab_rounding",
        "convention_unemployment_benefit_timing",
        "convention_ea_inflation_log1p",
        "defect_vector_min_capacity_cap",
        "defect_growth_rate_ar1_wiring",
        "us_measured_trade",
        "us_product_tax_netting_bridge",
        "us_opening_commodity_inventory",
        "us_negative_trade_cells_clamped",
        "us_ea_block_uses_us_data",
        "us_modelgr_extension",
        "us_canvas_extension",
        "us_productivity_shock_timing",
        "us_consumption_shock_reversal_timing",
        "us_census_labor_and_sector_wages",
        "us_transaction_and_opening_loggers",
        "us_provenance_validation_ledger",
        "us_forecast_error_calibration_layer",
    ],
)

const CLASSIFICATIONS = Set(
    [
        "paper_typo_candidate",
        "printed_upstream_difference",
        "implementation_convention",
        "latent_defect",
        "us_fork_addition",
    ],
)
const MATERIALITIES = Set(["low", "medium", "high", "critical"])
const ENTRY_STATUSES = Set(
    [
        "documented_variant_split",
        "documented_convention",
        "corrected_candidate_implemented",
        "open_independent_adjudication",
        "open_replication_evidence",
        "open_economic_validation",
        "open_regression_test",
    ],
)
const AMBIGUOUS_TREATMENTS = Set(
    [
        "default",
        "inherit",
        "later",
        "maybe",
        "na",
        "none",
        "placeholder",
        "same",
        "tbd",
        "todo",
        "unknown",
        "unspecified",
        "decide",
        "decided",
        "decision",
    ],
)
const TREATMENT_PREFIXES = (
    "correct_",
    "disable_",
    "enable_",
    "execute_",
    "record_",
    "reference_",
    "reject_",
    "require_",
    "retain_",
    "separate_",
)

struct RegistryValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::RegistryValidationError) =
    print(io, error.message)

fail(path::AbstractString, message::AbstractString) =
    throw(RegistryValidationError("$path: $message"))

function expect_table(value, path)
    value isa AbstractDict ||
        fail(path, "expected a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(path, "table keys must be strings")
    return value
end

function check_keys(table, path, expected_keys)
    expect_table(table, path)
    actual = Set(String(key) for key in keys(table))
    expected = Set(String(key) for key in expected_keys)
    missing = sort!(collect(setdiff(expected, actual)))
    unknown = sort!(collect(setdiff(actual, expected)))
    isempty(missing) ||
        fail(path, "missing required key(s): $(join(missing, ", "))")
    isempty(unknown) ||
        fail(path, "unknown key(s): $(join(unknown, ", "))")
    return table
end

function expect_string(value, path)
    value isa AbstractString ||
        fail(path, "expected a string")
    text = String(value)
    isempty(text) &&
        fail(path, "must not be empty")
    strip(text) == text ||
        fail(path, "must not contain leading or trailing whitespace")
    return text
end

function expect_identifier(value, path)
    identifier = expect_string(value, path)
    occursin(IDENTIFIER_PATTERN, identifier) ||
        fail(path, "expected a lowercase snake_case identifier")
    return identifier
end

function expect_bool(value, path)
    value isa Bool ||
        fail(path, "expected a Boolean")
    return value
end

function expect_int(value, path)
    value isa Integer && !(value isa Bool) ||
        fail(path, "expected an integer")
    return Int(value)
end

function expect_string_vector(value, path)
    value isa AbstractVector ||
        fail(path, "expected an array of strings")
    result = String[]
    for (index, entry) in enumerate(value)
        push!(result, expect_string(entry, "$path[$index]"))
    end
    isempty(result) &&
        fail(path, "must not be empty")
    length(Set(result)) == length(result) ||
        fail(path, "must not contain duplicates")
    return result
end

function expect_exact(value, expected, path)
    value == expected ||
        fail(path, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function expect_enum(value, allowed, path)
    text = expect_string(value, path)
    text in allowed ||
        fail(path, "unsupported value '$text'")
    return text
end

function validate_evidence(entry, field, path)
    values = expect_string_vector(entry[field], "$path.$field")
    prefixes = EVIDENCE_PREFIXES[field]
    for (index, value) in enumerate(values)
        any(prefix -> startswith(value, prefix), prefixes) ||
            fail(
            "$path.$field[$index]",
            "expected one of the prefixes $(join(prefixes, ", "))",
        )
        if startswith(value, "repo:")
            occursin(REPOSITORY_EVIDENCE_PATTERN, value) ||
                fail("$path.$field[$index]", "malformed repository pointer")
        elseif startswith(value, "commit:")
            occursin(COMMIT_EVIDENCE_PATTERN, value) ||
                fail("$path.$field[$index]", "malformed commit pointer")
        elseif startswith(value, "pending:")
            occursin(PENDING_EVIDENCE_PATTERN, value) ||
                fail("$path.$field[$index]", "malformed pending-test pointer")
        elseif startswith(value, "paper:")
            ncodeunits(value) > ncodeunits("paper:") + 8 ||
                fail("$path.$field[$index]", "paper evidence is blank")
        elseif startswith(value, "paper_gap:")
            ncodeunits(value) > ncodeunits("paper_gap:") + 8 ||
                fail("$path.$field[$index]", "paper-gap evidence is blank")
        end
    end
    return values
end

function validate_treatments(treatments, path)
    check_keys(treatments, path, VARIANT_IDS)
    for variant_id in VARIANT_IDS
        treatment =
            expect_identifier(treatments[variant_id], "$path.$variant_id")
        treatment in AMBIGUOUS_TREATMENTS &&
            fail("$path.$variant_id", "ambiguous treatment '$treatment'")
        if variant_id != "printed_paper_reference"
            ambiguous_tokens =
                intersect(Set(split(treatment, "_")), AMBIGUOUS_TREATMENTS)
            isempty(ambiguous_tokens) ||
                fail(
                "$path.$variant_id",
                "ambiguous treatment token(s): " *
                    join(sort!(collect(ambiguous_tokens)), ", "),
            )
        end
        any(prefix -> startswith(treatment, prefix), TREATMENT_PREFIXES) ||
            fail(
            "$path.$variant_id",
            "treatment must begin with a concrete action verb",
        )
    end
    return treatments
end

function validate_artifact_table(artifact, path)
    check_keys(artifact, path, ("canonicalization", "content_sha256"))
    expect_exact(
        artifact["canonicalization"],
        "sorted_typed_v1_excluding_artifact_content_sha256",
        "$path.canonicalization",
    )
    digest = expect_string(artifact["content_sha256"], "$path.content_sha256")
    occursin(HASH_PATTERN, digest) ||
        fail("$path.content_sha256", "expected a lowercase SHA-256")
    return artifact
end

function validate_crosswalk(crosswalk)
    path = "crosswalk"
    check_keys(
        crosswalk,
        path,
        (
            "schema_version",
            "artifact_status",
            "source_baseline_commit",
            "paper_reference",
            "paper_sha256",
            "required_variant_ids",
            "blanket_replication_claims_prohibited",
            "expected_entry_count",
            "expected_printed_difference_count",
            "artifact",
            "entries",
        ),
    )
    expect_exact(crosswalk["schema_version"], CROSSWALK_SCHEMA, "$path.schema_version")
    expect_enum(
        crosswalk["artifact_status"],
        Set(["draft", "approved"]),
        "$path.artifact_status",
    )
    expect_exact(
        crosswalk["source_baseline_commit"],
        BASELINE_COMMIT,
        "$path.source_baseline_commit",
    )
    expect_string(crosswalk["paper_reference"], "$path.paper_reference")
    paper_sha256 = expect_string(crosswalk["paper_sha256"], "$path.paper_sha256")
    occursin(HASH_PATTERN, paper_sha256) ||
        fail("$path.paper_sha256", "expected a lowercase SHA-256")
    expect_exact(
        expect_string_vector(
            crosswalk["required_variant_ids"],
            "$path.required_variant_ids",
        ),
        VARIANT_IDS,
        "$path.required_variant_ids",
    )
    expect_bool(
        crosswalk["blanket_replication_claims_prohibited"],
        "$path.blanket_replication_claims_prohibited",
    ) ||
        fail(
        "$path.blanket_replication_claims_prohibited",
        "blanket replication claims must be prohibited",
    )
    expect_exact(
        expect_int(crosswalk["expected_entry_count"], "$path.expected_entry_count"),
        length(EXPECTED_ENTRY_IDS),
        "$path.expected_entry_count",
    )
    expect_exact(
        expect_int(
            crosswalk["expected_printed_difference_count"],
            "$path.expected_printed_difference_count",
        ),
        19,
        "$path.expected_printed_difference_count",
    )
    validate_artifact_table(crosswalk["artifact"], "$path.artifact")

    entries = crosswalk["entries"]
    entries isa AbstractVector ||
        fail("$path.entries", "expected an array of tables")
    length(entries) == length(EXPECTED_ENTRY_IDS) ||
        fail(
        "$path.entries",
        "expected $(length(EXPECTED_ENTRY_IDS)) entries, got $(length(entries))",
    )
    actual_ids = String[]
    printed_difference_count = 0
    for (index, entry) in enumerate(entries)
        entry_path = "$path.entries[$index]"
        check_keys(
            entry,
            entry_path,
            (
                "id",
                "title",
                "classification",
                "materiality",
                "paper_evidence",
                "code_evidence",
                "resolution",
                "status",
                "rationale",
                "test_evidence",
                "owner",
                "independent_validator",
                "treatments",
            ),
        )
        identifier = expect_identifier(entry["id"], "$entry_path.id")
        push!(actual_ids, identifier)
        expect_string(entry["title"], "$entry_path.title")
        classification = expect_enum(
            entry["classification"],
            CLASSIFICATIONS,
            "$entry_path.classification",
        )
        printed_difference_count +=
            classification == "printed_upstream_difference"
        expect_enum(
            entry["materiality"],
            MATERIALITIES,
            "$entry_path.materiality",
        )
        validate_evidence(entry, "paper_evidence", entry_path)
        validate_evidence(entry, "code_evidence", entry_path)
        expect_identifier(entry["resolution"], "$entry_path.resolution")
        expect_enum(entry["status"], ENTRY_STATUSES, "$entry_path.status")
        expect_string(entry["rationale"], "$entry_path.rationale")
        validate_evidence(entry, "test_evidence", entry_path)
        expect_identifier(entry["owner"], "$entry_path.owner")
        expect_identifier(
            entry["independent_validator"],
            "$entry_path.independent_validator",
        )
        validate_treatments(entry["treatments"], "$entry_path.treatments")
    end
    length(Set(actual_ids)) == length(actual_ids) ||
        fail("$path.entries", "entry identifiers must be unique")
    actual_id_set = Set(actual_ids)
    missing = sort!(collect(setdiff(EXPECTED_ENTRY_IDS, actual_id_set)))
    extra = sort!(collect(setdiff(actual_id_set, EXPECTED_ENTRY_IDS)))
    isempty(missing) ||
        fail("$path.entries", "missing required entry IDs: $(join(missing, ", "))")
    isempty(extra) ||
        fail("$path.entries", "unknown entry IDs: $(join(extra, ", "))")
    printed_difference_count == 19 ||
        fail(
        "$path.entries",
        "expected 19 printed/upstream differences, got $printed_difference_count",
    )
    return crosswalk
end

function validate_change_classes(classes, path)
    classes isa AbstractVector ||
        fail(path, "expected an array of tables")
    actual = String[]
    for (index, class) in enumerate(classes)
        class_path = "$path[$index]"
        check_keys(class, class_path, ("id", "description"))
        push!(actual, expect_identifier(class["id"], "$class_path.id"))
        expect_string(class["description"], "$class_path.description")
    end
    Set(actual) == CLASSIFICATIONS ||
        fail(path, "change-class taxonomy must exactly cover the crosswalk")
    length(actual) == length(CLASSIFICATIONS) ||
        fail(path, "change-class identifiers must be unique")
    return classes
end

function validate_variant(variant, index)
    path = "variants.variants[$index]"
    check_keys(
        variant,
        path,
        (
            "id",
            "label",
            "source_kind",
            "code_revision",
            "executable",
            "immutable",
            "validation_status",
            "allowed_claim",
            "price_search",
            "capacity_minimum",
            "trade_closure",
            "product_tax_treatment",
            "opening_inventories",
            "external_block",
            "exogenous_process",
            "policy_rule",
            "agent_scale",
            "calibration_vintages",
            "growth_process",
            "extensions",
            "forecast_error_calibration",
            "scenario_timing",
        ),
    )
    identifier = expect_identifier(variant["id"], "$path.id")
    expect_string(variant["label"], "$path.label")
    expect_enum(
        variant["source_kind"],
        Set(
            [
                "reference_document",
                "repository_checkout",
                "configuration_profile",
                "working_tree_candidate",
            ],
        ),
        "$path.source_kind",
    )
    expect_string(variant["code_revision"], "$path.code_revision")
    expect_bool(variant["executable"], "$path.executable")
    expect_bool(variant["immutable"], "$path.immutable")
    expect_enum(
        variant["validation_status"],
        Set(
            [
                "reference_only",
                "historical_unvalidated",
                "reviewed_unvalidated",
                "candidate_unvalidated",
            ],
        ),
        "$path.validation_status",
    )
    expect_string(variant["allowed_claim"], "$path.allowed_claim")
    for field in (
            "price_search",
            "capacity_minimum",
            "trade_closure",
            "product_tax_treatment",
            "opening_inventories",
            "external_block",
            "exogenous_process",
            "policy_rule",
            "agent_scale",
            "calibration_vintages",
            "growth_process",
            "forecast_error_calibration",
            "scenario_timing",
        )
        expect_identifier(variant[field], "$path.$field")
    end
    expect_string_vector(variant["extensions"], "$path.extensions")
    return identifier
end

function _signature_complete(gate, actor)
    name = String(gate[actor])
    signature = String(gate["$(actor)_signature"])
    signed_at = String(gate["$(actor)_signed_at"])
    return name != "unassigned" &&
        occursin(IDENTIFIER_PATTERN, name) &&
        occursin(SIGNATURE_PATTERN, signature) &&
        occursin(SIGNED_AT_PATTERN, signed_at)
end

is_open_entry(entry) = startswith(String(entry["status"]), "open_")

function is_implemented_test_pointer(pointer)
    startswith(pointer, "repo:") || return false
    path = lowercase(first(split(pointer[6:end], ":")))
    return startswith(path, "test/") ||
        occursin("/test/", path) ||
        occursin("/test_", path)
end

function registry_open_counts(crosswalk)
    entries = crosswalk["entries"]
    return (
        open_entries = count(is_open_entry, entries),
        pending_test_entries = count(
            entry -> any(startswith(pointer, "pending:") for pointer in entry["test_evidence"]),
            entries,
        ),
        pending_test_pointers = sum(
            startswith(pointer, "pending:")
                for entry in entries for pointer in entry["test_evidence"]
        ),
        untested_entries = count(
            entry -> !any(is_implemented_test_pointer, entry["test_evidence"]),
            entries,
        ),
        unassigned_owners =
            count(entry -> entry["owner"] == "unassigned", entries),
        unassigned_validators = count(
            entry -> entry["independent_validator"] == "unassigned",
            entries,
        ),
    )
end

function _gate_reasons(crosswalk, variants)
    gate = variants["gate"]
    reasons = String[]
    crosswalk["artifact_status"] == "approved" ||
        push!(reasons, "crosswalk artifact status is draft")
    variants["artifact_status"] == "approved" ||
        push!(reasons, "variant artifact status is draft")
    gate["status"] == "closed" ||
        push!(reasons, "governance status is open")
    _signature_complete(gate, "model_owner") ||
        push!(reasons, "model-owner signature is missing")
    _signature_complete(gate, "independent_validator") ||
        push!(reasons, "independent-validator signature is missing")
    if _signature_complete(gate, "model_owner") &&
            gate["model_owner_signature"] !=
            expected_gate_attestation(crosswalk, variants, "model_owner")
        push!(reasons, "model-owner attestation is not bound to this registry")
    end
    if _signature_complete(gate, "independent_validator") &&
            gate["independent_validator_signature"] !=
            expected_gate_attestation(
            crosswalk,
            variants,
            "independent_validator",
        )
        push!(
            reasons,
            "independent-validator attestation is not bound to this registry",
        )
    end
    if gate["model_owner"] != "unassigned" &&
            gate["model_owner"] == gate["independent_validator"]
        push!(reasons, "model owner and independent validator are not independent")
    end
    counts = registry_open_counts(crosswalk)
    counts.open_entries == 0 ||
        push!(reasons, "$(counts.open_entries) crosswalk entries remain open")
    counts.pending_test_entries == 0 ||
        push!(
        reasons,
        "$(counts.pending_test_entries) crosswalk entries retain pending tests",
    )
    counts.untested_entries == 0 ||
        push!(
        reasons,
        "$(counts.untested_entries) crosswalk entries lack implemented tests",
    )
    counts.unassigned_owners == 0 ||
        push!(
        reasons,
        "$(counts.unassigned_owners) crosswalk entries lack an owner",
    )
    counts.unassigned_validators == 0 ||
        push!(
        reasons,
        "$(counts.unassigned_validators) crosswalk entries lack an independent validator",
    )
    conflicted_entries = count(
        entry ->
        entry["independent_validator"] != "unassigned" &&
            entry["independent_validator"] == entry["owner"],
        crosswalk["entries"],
    )
    conflicted_entries == 0 ||
        push!(
        reasons,
        "$conflicted_entries crosswalk entries use their owner as validator",
    )
    return reasons
end

function validate_gate_actor(gate, actor, path)
    name = expect_identifier(gate[actor], "$path.$actor")
    signature = expect_string(
        gate["$(actor)_signature"],
        "$path.$(actor)_signature",
    )
    signed_at =
        expect_string(gate["$(actor)_signed_at"], "$path.$(actor)_signed_at")
    signature == "unsigned" || occursin(SIGNATURE_PATTERN, signature) ||
        fail(
        "$path.$(actor)_signature",
        "expected 'unsigned' or a sha256 attestation",
    )
    signed_at == "unassigned" || occursin(SIGNED_AT_PATTERN, signed_at) ||
        fail(
        "$path.$(actor)_signed_at",
        "expected 'unassigned' or an RFC3339 UTC-second timestamp",
    )
    (signature == "unsigned") == (signed_at == "unassigned") ||
        fail(
        "$path.$actor",
        "signature and signed-at fields must be completed together",
    )
    if name == "unassigned"
        signature == "unsigned" ||
            fail("$path.$actor", "an unassigned actor cannot sign")
    end
    return name
end

function validate_gate(gate, path)
    check_keys(
        gate,
        path,
        (
            "status",
            "approval_scope",
            "model_owner",
            "model_owner_signature",
            "model_owner_signed_at",
            "independent_validator",
            "independent_validator_signature",
            "independent_validator_signed_at",
            "schema_validation_is_approval",
        ),
    )
    expect_enum(gate["status"], Set(["open", "closed"]), "$path.status")
    expect_exact(
        gate["approval_scope"],
        "crosswalk_and_variant_baseline",
        "$path.approval_scope",
    )
    validate_gate_actor(gate, "model_owner", path)
    validate_gate_actor(gate, "independent_validator", path)
    expect_bool(
        gate["schema_validation_is_approval"],
        "$path.schema_validation_is_approval",
    ) === false ||
        fail("$path.schema_validation_is_approval", "must remain false")
    if gate["status"] == "closed"
        _signature_complete(gate, "model_owner") ||
            fail(path, "closed gate requires a model-owner signature")
        _signature_complete(gate, "independent_validator") ||
            fail(path, "closed gate requires an independent-validator signature")
        gate["model_owner"] != gate["independent_validator"] ||
            fail(path, "model owner and independent validator must differ")
    end
    return gate
end

function validate_variants(variants)
    path = "variants"
    check_keys(
        variants,
        path,
        (
            "schema_version",
            "artifact_status",
            "source_baseline_commit",
            "crosswalk_sha256",
            "blanket_replication_claims_prohibited",
            "artifact",
            "gate",
            "change_classes",
            "variants",
        ),
    )
    expect_exact(variants["schema_version"], VARIANTS_SCHEMA, "$path.schema_version")
    artifact_status = expect_enum(
        variants["artifact_status"],
        Set(["draft", "approved"]),
        "$path.artifact_status",
    )
    expect_exact(
        variants["source_baseline_commit"],
        BASELINE_COMMIT,
        "$path.source_baseline_commit",
    )
    crosswalk_sha256 =
        expect_string(variants["crosswalk_sha256"], "$path.crosswalk_sha256")
    occursin(HASH_PATTERN, crosswalk_sha256) ||
        fail("$path.crosswalk_sha256", "expected a lowercase SHA-256")
    expect_bool(
        variants["blanket_replication_claims_prohibited"],
        "$path.blanket_replication_claims_prohibited",
    ) ||
        fail(
        "$path.blanket_replication_claims_prohibited",
        "blanket replication claims must be prohibited",
    )
    validate_artifact_table(variants["artifact"], "$path.artifact")
    validate_gate(variants["gate"], "$path.gate")
    if variants["gate"]["status"] == "closed" && artifact_status != "approved"
        fail(
            "$path.artifact_status",
            "a closed gate requires an approved variant artifact",
        )
    end
    validate_change_classes(variants["change_classes"], "$path.change_classes")

    variant_entries = variants["variants"]
    variant_entries isa AbstractVector ||
        fail("$path.variants", "expected an array of tables")
    length(variant_entries) == length(VARIANT_IDS) ||
        fail("$path.variants", "expected exactly four variants")
    actual_ids = [
        validate_variant(variant, index)
            for (index, variant) in enumerate(variant_entries)
    ]
    actual_ids == VARIANT_IDS ||
        fail("$path.variants", "variants must appear in the required order")

    paper, upstream, us_port, corrected = variant_entries
    paper["executable"] === false ||
        fail("$path.variants[1].executable", "paper reference is not executable")
    paper["allowed_claim"] == "reference_only_not_executable" ||
        fail("$path.variants[1].allowed_claim", "blanket paper-model claim rejected")
    upstream["code_revision"] == BASELINE_COMMIT ||
        fail("$path.variants[2].code_revision", "must pin commit $BASELINE_COMMIT")
    upstream["allowed_claim"] ==
        "historical_upstream_compatible_behavior_not_paper_equivalence" ||
        fail("$path.variants[2].allowed_claim", "blanket replication claim rejected")
    us_port["allowed_claim"] ==
        "reviewed_us_port_configuration_not_forecast_validated" ||
        fail("$path.variants[3].allowed_claim", "forecast-validation claim rejected")
    corrected["allowed_claim"] ==
        "candidate_with_correctness_fixes_not_forecast_validated" ||
        fail("$path.variants[4].allowed_claim", "forecast-validation claim rejected")
    corrected["capacity_minimum"] == "elementwise_capacity_cap" ||
        fail(
        "$path.variants[4].capacity_minimum",
        "corrected candidate must use the elementwise cap",
    )
    corrected["growth_process"] == "log_level_default_with_base_model_guard" ||
        fail(
        "$path.variants[4].growth_process",
        "corrected candidate must guard growth-rate coefficients",
    )
    return variants
end

function _canonical_write(io, value)
    if value isa AbstractDict
        keys_sorted = sort!(String.(collect(keys(value))))
        print(io, "d", length(keys_sorted), "{")
        for key in keys_sorted
            _canonical_write(io, key)
            _canonical_write(io, value[key])
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "a", length(value), "[")
        for entry in value
            _canonical_write(io, entry)
        end
        print(io, "]")
    elseif value isa AbstractString
        text = String(value)
        print(io, "s", ncodeunits(text), ":", text)
    elseif value isa Bool
        print(io, value ? "b1" : "b0")
    elseif value isa Integer
        print(io, "i", value, ";")
    elseif value isa AbstractFloat
        number = Float64(value)
        isfinite(number) ||
            fail("canonicalization", "nonfinite numbers are prohibited")
        print(io, "f", bitstring(number), ";")
    else
        fail(
            "canonicalization",
            "unsupported value of type $(typeof(value))",
        )
    end
    return io
end

function computed_artifact_sha256(table)
    canonical = deepcopy(expect_table(table, "artifact"))
    artifact = expect_table(canonical["artifact"], "artifact.artifact")
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, canonical)
    return bytes2hex(sha256(take!(io)))
end

function approval_payload_sha256(crosswalk, variants)
    payload_crosswalk = deepcopy(expect_table(crosswalk, "crosswalk"))
    payload_variants = deepcopy(expect_table(variants, "variants"))
    pop!(
        expect_table(
            payload_crosswalk["artifact"],
            "crosswalk.artifact",
        ),
        "content_sha256",
        nothing,
    )
    pop!(
        expect_table(payload_variants["artifact"], "variants.artifact"),
        "content_sha256",
        nothing,
    )
    gate = expect_table(payload_variants["gate"], "variants.gate")
    for actor in ("model_owner", "independent_validator")
        gate["$(actor)_signature"] = "unsigned"
        gate["$(actor)_signed_at"] = "unassigned"
    end
    io = IOBuffer()
    _canonical_write(
        io,
        Dict(
            "crosswalk" => payload_crosswalk,
            "variants" => payload_variants,
        ),
    )
    return bytes2hex(sha256(take!(io)))
end

function expected_gate_attestation(crosswalk, variants, actor)
    actor in ("model_owner", "independent_validator") ||
        fail("variants.gate", "unknown attestation actor '$actor'")
    gate = variants["gate"]
    actor_name = expect_identifier(gate[actor], "variants.gate.$actor")
    actor_name == "unassigned" &&
        fail("variants.gate.$actor", "unassigned actor cannot attest")
    signed_at = expect_string(
        gate["$(actor)_signed_at"],
        "variants.gate.$(actor)_signed_at",
    )
    occursin(SIGNED_AT_PATTERN, signed_at) ||
        fail(
        "variants.gate.$(actor)_signed_at",
        "attestation requires an RFC3339 UTC-second timestamp",
    )
    payload = join(
        (
            "beforeit-ws0b-attestation-v1",
            gate["approval_scope"],
            actor,
            actor_name,
            signed_at,
            crosswalk["artifact"]["content_sha256"],
            variants["crosswalk_sha256"],
            approval_payload_sha256(crosswalk, variants),
        ),
        '\0',
    )
    return "sha256:" * bytes2hex(sha256(payload))
end

function verify_artifact_sha256(table, path)
    expected = table["artifact"]["content_sha256"]
    actual = computed_artifact_sha256(table)
    expected == actual ||
        fail(
        "$path.artifact.content_sha256",
        "digest mismatch: declared $expected, computed $actual",
    )
    return actual
end

function parse_artifact(path)
    isfile(path) ||
        fail(path, "file does not exist")
    try
        return TOML.parsefile(path)
    catch error
        error isa RegistryValidationError && rethrow()
        fail(path, "could not parse TOML: $(sprint(showerror, error))")
    end
end

function registry_report(crosswalk, variants)
    validate_crosswalk(crosswalk)
    validate_variants(variants)
    crosswalk_sha256 = verify_artifact_sha256(crosswalk, "crosswalk")
    variants["crosswalk_sha256"] == crosswalk_sha256 ||
        fail(
        "variants.crosswalk_sha256",
        "does not identify the validated crosswalk",
    )
    variants_sha256 = verify_artifact_sha256(variants, "variants")
    reasons = _gate_reasons(crosswalk, variants)
    if variants["gate"]["status"] == "closed" && !isempty(reasons)
        fail("variants.gate", "closed gate is incomplete: $(join(reasons, "; "))")
    end
    counts = Dict{String, Int}()
    for entry in crosswalk["entries"]
        classification = String(entry["classification"])
        counts[classification] = get(counts, classification, 0) + 1
    end
    open_counts = registry_open_counts(crosswalk)
    approval_sha256 = approval_payload_sha256(crosswalk, variants)
    return (
        schema_valid = true,
        gate_closed = isempty(reasons),
        gate_status = isempty(reasons) ? "closed" : "open",
        gate_reasons = reasons,
        entry_count = length(crosswalk["entries"]),
        classification_counts = counts,
        open_entry_count = open_counts.open_entries,
        pending_test_entry_count = open_counts.pending_test_entries,
        pending_test_pointer_count = open_counts.pending_test_pointers,
        untested_entry_count = open_counts.untested_entries,
        unassigned_owner_count = open_counts.unassigned_owners,
        unassigned_validator_count = open_counts.unassigned_validators,
        crosswalk_sha256,
        variants_sha256,
        approval_payload_sha256 = approval_sha256,
    )
end

function load_registry(
        crosswalk_path::AbstractString = DEFAULT_CROSSWALK_PATH,
        variants_path::AbstractString = DEFAULT_VARIANTS_PATH,
    )
    crosswalk = parse_artifact(crosswalk_path)
    variants = parse_artifact(variants_path)
    report = registry_report(crosswalk, variants)
    return (; crosswalk, variants, report)
end

function require_closed_gate(report)
    report.schema_valid ||
        fail("registry", "schema is not valid")
    report.gate_closed ||
        fail(
        "registry.gate",
        "gate remains open: $(join(report.gate_reasons, "; "))",
    )
    return report
end

function main(args = ARGS)
    registry = load_registry()
    report = registry.report
    println("schema_valid=$(report.schema_valid)")
    println("entry_count=$(report.entry_count)")
    println("open_entry_count=$(report.open_entry_count)")
    println("pending_test_entry_count=$(report.pending_test_entry_count)")
    println("pending_test_pointer_count=$(report.pending_test_pointer_count)")
    println("untested_entry_count=$(report.untested_entry_count)")
    println("unassigned_owner_count=$(report.unassigned_owner_count)")
    println(
        "unassigned_validator_count=$(report.unassigned_validator_count)",
    )
    println("crosswalk_sha256=$(report.crosswalk_sha256)")
    println("variants_sha256=$(report.variants_sha256)")
    println(
        "approval_payload_sha256=$(report.approval_payload_sha256)",
    )
    println("gate=$(report.gate_status)")
    for reason in report.gate_reasons
        println("gate_reason=$reason")
    end
    "--schema-only" in args && return 0
    require_closed_gate(report)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(main())
    catch error
        if error isa RegistryValidationError
            println(stderr, "validation_error=$(sprint(showerror, error))")
            exit(2)
        end
        rethrow()
    end
end

end
