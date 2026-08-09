module USCommonOriginPreflightV1

using SHA
using TOML

export PreflightError,
    compile_preflight,
    load_manifest,
    manifest_content_sha256,
    result_content_sha256,
    validate_preflight

const SCHEMA_VERSION = "beforeit-us-common-origin-preflight-result.v1"
const MANIFEST_SCHEMA_VERSION =
    "beforeit-us-common-origin-preflight-manifest.v1"
const CONTRACT_ID = "beforeit-us-common-origin-comparison-preflight.v1"
const CANONICALIZATION =
    "sorted-typed-length-prefixed-v1-excluding-artifact-content-sha256"
const CANNOT_RUN = "CANNOT_RUN"
const READY_FOR_SEAL = "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
const FORBIDDEN_READY_TO_SCORE = "READY_TO_SCORE"
const ZERO_SHA256 = repeat("0", 64)
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const ALLOWED_SOURCE_KINDS = Set(
    [
        "documentation",
        "metadata_toml",
        "reference_metadata_toml",
        "source",
    ],
)
const REPOSITORY_ROOT = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", ".."),
)
const MANIFEST_PATH = joinpath(@__DIR__, "common_origin_preflight_v1.toml")

# These identities are frozen only after the manifest and deterministic current
# result have been independently regenerated. They intentionally do not appear
# in the manifest, avoiding a circular self-reference.
const EXPECTED_MANIFEST_PHYSICAL_SHA256 =
    "a44f90f1cc809cfcc928e69f0ddc046916554fee9a534ff8d6162a4df6143902"
const EXPECTED_CURRENT_RESULT_SHA256 =
    "4b0871cdd9c25fadcd266b778ba23b0415f23ce8e8c423f6ee7fc5d936938fd5"

const SCIENTIFIC_GATE_NAMES = [
    "accuracy_claim_allowed",
    "admission_allowed",
    "production_allowed",
    "promotion_allowed",
    "scoring_allowed",
    "suitability_claim_allowed",
]
const EXPECTED_REJECTED_COMPARISON_HASHES = Dict(
    "core3_equilibrium_comparison_module_sha256" =>
        "da3581203ed0ac580a315df172ed5f6a068770c99f1a172c8d8106ccbf2aa728",
    "core3_equilibrium_comparison_tests_sha256" =>
        "956b7011b01e8436aaee261e5767b9b3a73c96ffb42c0b7ffd36f4a841d93bc4",
    "core3_equilibrium_comparison_runner_sha256" =>
        "8fd455c959121ce1391e30b95a6dc2363f0ada25087269205890548f92d881f3",
    "core3_equilibrium_comparison_readme_sha256" =>
        "f37b550a8a2e28ac0817f02c646fd7dd6ce361529b57ae3e216d3973a879c67d",
    "core3_equilibrium_comparison_claimed_result_sha256" =>
        "7e92f0dfc54b2dc6d69fd9924c2f7e2c3de19d99286805289d5c9fd8f5302f6d",
)

struct PreflightError <: Exception
    code::Symbol
    message::String
end

Base.showerror(io::IO, error::PreflightError) =
    print(io, "common-origin preflight ", error.code, ": ", error.message)

fail(code::Symbol, message) = throw(PreflightError(code, String(message)))

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(SHA.sha256(bytes))

function _emit_length(io::IO, count::Integer)
    count >= 0 || fail(:canonicalization, "negative canonical length")
    write(io, string(count), ':')
    return nothing
end

function _emit_canonical(io::IO, value)
    if value === nothing
        write(io, "N;")
    elseif value isa Bool
        write(io, value ? "B1;" : "B0;")
    elseif value isa Integer
        encoded = codeunits(string(value))
        write(io, 'I')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractFloat
        isfinite(value) || fail(:canonicalization, "nonfinite float")
        encoded = codeunits(bitstring(Float64(value)))
        write(io, 'F')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractString
        encoded = codeunits(String(value))
        write(io, 'S')
        _emit_length(io, length(encoded))
        write(io, encoded)
        write(io, ';')
    elseif value isa AbstractVector
        write(io, 'A')
        _emit_length(io, length(value))
        for item in value
            _emit_canonical(io, item)
        end
        write(io, ';')
    elseif value isa AbstractDict
        all(key -> key isa AbstractString, keys(value)) ||
            fail(:canonicalization, "dictionary keys must be strings")
        ordered = sort!(String.(collect(keys(value))))
        write(io, 'D')
        _emit_length(io, length(ordered))
        for key in ordered
            _emit_canonical(io, key)
            _emit_canonical(io, value[key])
        end
        write(io, ';')
    else
        fail(:canonicalization, "unsupported value type $(typeof(value))")
    end
    return nothing
end

function canonical_bytes(value)
    io = IOBuffer()
    _emit_canonical(io, value)
    return take!(io)
end

canonical_sha256(value) = sha256_hex(canonical_bytes(value))

function _without_artifact_content_hash(document::AbstractDict)
    payload = deepcopy(document)
    artifact = get(payload, "artifact", nothing)
    artifact isa AbstractDict ||
        fail(:invalid_schema, "document.artifact must be a table")
    pop!(artifact, "content_sha256", nothing)
    return payload
end

manifest_content_sha256(document::AbstractDict) =
    canonical_sha256(_without_artifact_content_hash(document))

result_content_sha256(document::AbstractDict) =
    canonical_sha256(_without_artifact_content_hash(document))

function _expect_table(value, location)
    value isa AbstractDict || fail(:invalid_schema, "$location must be a table")
    return value
end

function _expect_vector(value, location)
    value isa AbstractVector || fail(:invalid_schema, "$location must be an array")
    return value
end

function _expect_string(value, location)
    value isa AbstractString || fail(:invalid_schema, "$location must be a string")
    return String(value)
end

function _expect_bool(value, location)
    value isa Bool || fail(:invalid_schema, "$location must be boolean")
    return value
end

function _expect_int(value, location)
    value isa Integer && !(value isa Bool) ||
        fail(:invalid_schema, "$location must be an integer")
    return Int(value)
end

function _expect_hash(value, location)
    text = _expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(:invalid_hash, "$location must be lowercase SHA-256")
    return text
end

function _expect_exact_keys(table::AbstractDict, expected, location)
    actual = Set(String.(collect(keys(table))))
    wanted = Set(String.(collect(expected)))
    actual == wanted || begin
        missing = sort!(collect(setdiff(wanted, actual)))
        extra = sort!(collect(setdiff(actual, wanted)))
        fail(
            :invalid_schema,
            "$location keys differ; missing=$(join(missing, ',')) extra=$(join(extra, ','))",
        )
    end
    return table
end

function _stable_state(path)
    info = stat(path)
    return (
        info.device,
        info.inode,
        info.mode,
        info.nlink,
        info.size,
        info.mtime,
        info.ctime,
    )
end

function _validate_relative_path(relative::AbstractString)
    text = String(relative)
    isempty(text) && fail(:unsafe_path, "empty repository-relative path")
    isabspath(text) && fail(:unsafe_path, "absolute path is forbidden")
    occursin('\\', text) && fail(:unsafe_path, "backslash path is forbidden")
    components = split(text, '/'; keepempty = true)
    all(component -> !isempty(component) && component != "." && component != "..", components) ||
        fail(:unsafe_path, "path contains empty, dot, or parent component")
    return components
end

function _safe_read_repository_file(relative::AbstractString, expected_hash, label)
    components = _validate_relative_path(relative)
    current = REPOSITORY_ROOT
    for component in components
        current = joinpath(current, component)
        ispath(current) || fail(:missing_source, "$label is missing at $relative")
        islink(current) &&
            fail(:unsafe_path, "$label has symbolic-link component $component")
    end
    isfile(current) || fail(:unsafe_path, "$label is not a regular file")
    leaf = lstat(current)
    leaf.nlink == 1 || fail(:unsafe_path, "$label is hard-linked")
    before = _stable_state(current)
    bytes = read(current)
    after = _stable_state(current)
    before == after || fail(:source_race, "$label changed while being read")
    digest = sha256_hex(bytes)
    digest == expected_hash ||
        fail(:source_hash_mismatch, "$label expected $expected_hash, got $digest")
    return bytes
end

function _manifest_payload(document)
    artifact = _expect_table(get(document, "artifact", nothing), "manifest.artifact")
    _expect_exact_keys(
        artifact,
        ["schema_version", "canonicalization", "content_sha256"],
        "manifest.artifact",
    )
    _expect_string(artifact["schema_version"], "manifest.artifact.schema_version") ==
        MANIFEST_SCHEMA_VERSION ||
        fail(:invalid_schema, "manifest schema version changed")
    _expect_string(artifact["canonicalization"], "manifest.artifact.canonicalization") ==
        CANONICALIZATION || fail(:invalid_schema, "manifest canonicalization changed")
    declared = _expect_hash(
        artifact["content_sha256"],
        "manifest.artifact.content_sha256",
    )
    computed = manifest_content_sha256(document)
    declared == computed ||
        fail(:manifest_self_hash, "manifest self-hash expected $computed, got $declared")

    contract = _expect_table(get(document, "contract", nothing), "manifest.contract")
    _expect_string(contract["contract_id"], "manifest.contract.contract_id") ==
        CONTRACT_ID || fail(:invalid_contract, "manifest contract ID changed")
    allowed = String.(
        _expect_vector(contract["allowed_statuses"], "manifest.contract.allowed_statuses"),
    )
    allowed == [CANNOT_RUN] ||
        fail(:invalid_contract, "manifest allowed statuses changed")
    _expect_string(
        contract["successor_only_status"],
        "manifest.contract.successor_only_status",
    ) == READY_FOR_SEAL ||
        fail(:invalid_contract, "successor-only ready status changed")
    _expect_string(contract["forbidden_status"], "manifest.contract.forbidden_status") ==
        FORBIDDEN_READY_TO_SCORE ||
        fail(:invalid_contract, "READY_TO_SCORE prohibition changed")
    _expect_string(
        contract["current_expected_status"],
        "manifest.contract.current_expected_status",
    ) == CANNOT_RUN || fail(:gate_elevation, "current manifest must remain CANNOT_RUN")

    sources = _expect_vector(get(document, "sources", nothing), "manifest.sources")
    isempty(sources) && fail(:invalid_schema, "manifest has no sources")
    binding_ids = String[]
    paths = String[]
    for (index, source_value) in enumerate(sources)
        source = _expect_table(source_value, "manifest.sources[$index]")
        _expect_exact_keys(
            source,
            ["binding_id", "path", "sha256", "kind"],
            "manifest.sources[$index]",
        )
        binding_id = _expect_string(source["binding_id"], "sources[$index].binding_id")
        path = _expect_string(source["path"], "sources[$index].path")
        _validate_relative_path(path)
        _expect_hash(source["sha256"], "sources[$index].sha256")
        kind = _expect_string(source["kind"], "sources[$index].kind")
        kind in ALLOWED_SOURCE_KINDS ||
            fail(:invalid_schema, "unsupported source kind $kind")
        push!(binding_ids, binding_id)
        push!(paths, path)
    end
    allunique(binding_ids) || fail(:invalid_schema, "duplicate source binding ID")
    allunique(paths) || fail(:invalid_schema, "duplicate source path")
    return document
end

function _load_manifest_unfrozen()
    expected = EXPECTED_MANIFEST_PHYSICAL_SHA256
    expected == ZERO_SHA256 &&
        fail(:unfrozen, "manifest physical SHA-256 has not been frozen")
    relative = relpath(MANIFEST_PATH, REPOSITORY_ROOT)
    bytes = _safe_read_repository_file(relative, expected, "preflight manifest")
    _verify_manifest_physical_bytes(bytes)
    document = try
        TOML.parse(String(copy(bytes)))
    catch error
        fail(:invalid_toml, "manifest TOML parse failed: $(sprint(showerror, error))")
    end
    _manifest_payload(document)
    return document, bytes
end

function _verify_manifest_physical_bytes(bytes::AbstractVector{UInt8})
    digest = sha256_hex(bytes)
    digest == EXPECTED_MANIFEST_PHYSICAL_SHA256 ||
        fail(
        :manifest_physical_hash,
        "expected $EXPECTED_MANIFEST_PHYSICAL_SHA256, got $digest",
    )
    return bytes
end

function load_manifest()
    document, _ = _load_manifest_unfrozen()
    return deepcopy(document)
end

struct EvidenceBundle
    manifest::Dict{String, Any}
    manifest_physical_sha256::String
    documents::Dict{String, Dict{String, Any}}
    texts::Dict{String, String}
    bindings::Vector{Dict{String, Any}}
end

function _load_evidence()
    manifest, manifest_bytes = _load_manifest_unfrozen()
    documents = Dict{String, Dict{String, Any}}()
    texts = Dict{String, String}()
    bindings = Dict{String, Any}[]
    for source_value in manifest["sources"]
        source = _expect_table(source_value, "manifest.source")
        binding_id = String(source["binding_id"])
        path = String(source["path"])
        expected = String(source["sha256"])
        bytes = _safe_read_repository_file(path, expected, binding_id)
        source_text = String(bytes)
        texts[binding_id] = source_text
        if endswith(String(source["kind"]), "toml")
            parsed = try
                TOML.parse(source_text)
            catch error
                fail(
                    :invalid_toml,
                    "$binding_id TOML parse failed: $(sprint(showerror, error))",
                )
            end
            documents[binding_id] = parsed
        end
        push!(
            bindings,
            Dict{String, Any}(
                "binding_id" => binding_id,
                "path" => path,
                "physical_sha256" => expected,
                "kind" => String(source["kind"]),
            ),
        )
    end
    return EvidenceBundle(
        manifest,
        sha256_hex(manifest_bytes),
        documents,
        texts,
        bindings,
    )
end

function _document(bundle::EvidenceBundle, binding_id)
    haskey(bundle.documents, binding_id) ||
        fail(:invalid_binding, "$binding_id is not parsed metadata")
    return bundle.documents[binding_id]
end

function _text(bundle::EvidenceBundle, binding_id)
    haskey(bundle.texts, binding_id) ||
        fail(:invalid_binding, "$binding_id has no bound bytes")
    return bundle.texts[binding_id]
end

function _binding_record(bundle::EvidenceBundle, binding_id)
    selected = [item for item in bundle.bindings if item["binding_id"] == binding_id]
    length(selected) == 1 || fail(:invalid_binding, "$binding_id is missing or duplicated")
    return only(selected)
end

function _require_occurs(text, needle, location)
    occursin(String(needle), text) ||
        fail(:semantic_mismatch, "$location no longer contains expected bound fact")
    return nothing
end

function _quarter_index(value)
    text = _expect_string(value, "quarter")
    matched = match(r"^(\d{4})Q([1-4])$", text)
    matched === nothing && fail(:invalid_schema, "invalid quarter $text")
    return 4 * parse(Int, matched.captures[1]) + parse(Int, matched.captures[2]) - 1
end

function _quarter_label(index::Integer)
    index >= 0 || fail(:invalid_schema, "quarter index must be nonnegative")
    year, quarter_zero = divrem(index, 4)
    return "$(year)Q$(quarter_zero + 1)"
end

function _last_origin_for_horizon(panel_end, horizon)
    steps = _expect_int(horizon, "horizon")
    steps >= 1 || fail(:invalid_schema, "horizon must be positive")
    return _quarter_label(_quarter_index(panel_end) - steps)
end

function _intersection(values::Vector{Vector{T}}) where {T}
    isempty(values) && return T[]
    result = Set(values[1])
    for value in values[2:end]
        intersect!(result, Set(value))
    end
    return sort!(collect(result))
end

function _validate_bound_semantics(bundle::EvidenceBundle)
    manifest = bundle.manifest
    claims = _expect_table(manifest["accepted_claims"], "manifest.accepted_claims")
    comparison =
        _expect_table(manifest["comparison_contract"], "manifest.comparison_contract")

    inventory = _document(bundle, "current_source_inventory")
    inventory_artifact = _expect_table(inventory["artifact"], "inventory.artifact")
    inventory_artifact["content_sha256"] == claims["inventory_content_sha256"] ||
        fail(:semantic_mismatch, "inventory semantic identity changed")
    inventory_artifact["status"] == "INCOMPLETE" ||
        fail(:gate_elevation, "inventory status changed")
    inventory_artifact["evidence_verifier_status"] ==
        "NOT_IMPLEMENTED_FAIL_CLOSED" ||
        fail(:gate_elevation, "inventory verifier status changed")
    inventory["release_events"] == Any[] ||
        fail(:gate_elevation, "current inventory unexpectedly has release events")
    inventory["admissible_origin_timestamps_utc"] == Any[] ||
        fail(:gate_elevation, "current inventory unexpectedly has admitted origins")

    window = _document(bundle, "common_window_decision")
    window["artifact"]["content_sha256"] == claims["common_window_content_sha256"] ||
        fail(:semantic_mismatch, "common-window semantic identity changed")
    decision = _expect_table(window["decision"], "common_window.decision")
    decision["inventory_sha256"] ==
        bundle.bindings[
        findfirst(item -> item["binding_id"] == "current_source_inventory", bundle.bindings),
    ]["physical_sha256"] ||
        fail(:invalid_binding, "common-window inventory physical binding changed")
    decision["admitted_origin_count"] == 0 ||
        fail(:gate_elevation, "common-window admitted-origin count changed")
    decision["strict_all_three_intersection_count"] == 0 ||
        fail(:gate_elevation, "strict common-window intersection changed")
    decision["metadata_only"] === true ||
        fail(:gate_elevation, "common-window metadata-only flag changed")
    triple = only(
        [
            item for item in window["intersections"] if
                item["intersection_id"] == "BEA_X_BLS_X_EFFR"
        ],
    )
    triple["first_quarter"] == "2016Q2" ||
        fail(:semantic_mismatch, "metadata intersection start changed")
    triple["last_quarter"] == "2021Q2" ||
        fail(:semantic_mismatch, "metadata intersection end changed")
    triple["quarter_count"] == 21 ||
        fail(:semantic_mismatch, "metadata intersection count changed")
    triple["strict_admitted_origin_count"] == 0 ||
        fail(:gate_elevation, "strict metadata intersection count changed")

    origin = _document(bundle, "current_origin_package")
    origin["artifact"]["content_sha256"] == claims["origin_package_content_sha256"] ||
        fail(:semantic_mismatch, "origin semantic identity changed")
    origin_record = _expect_table(origin["origin"], "origin.origin")
    origin_record["status"] == "cannot_run" ||
        fail(:gate_elevation, "current origin status changed")
    origin_record["information_track"] == "revised_mixed_vintage_diagnostic" ||
        fail(:gate_elevation, "current origin track changed")
    origin_record["reference_period"] == comparison["abm_origin_period"] ||
        fail(:semantic_mismatch, "current origin reference period changed")
    origin_record["protocol_sha256"] == claims["protocol_content_sha256"] ||
        fail(:invalid_binding, "origin protocol semantic binding changed")

    cannot_run = _document(bundle, "current_origin_cannot_run")
    cannot_run["artifact"]["content_sha256"] == claims["cannot_run_content_sha256"] ||
        fail(:semantic_mismatch, "cannot-run semantic identity changed")
    cannot_run["record"]["origin_package_sha256"] ==
        origin["artifact"]["content_sha256"] ||
        fail(:invalid_binding, "cannot-run origin-package binding changed")
    cannot_run["record"]["status"] == "cannot_run" ||
        fail(:gate_elevation, "cannot-run status changed")
    cannot_run["record"]["failure_count"] == length(cannot_run["failures"]) == 21 ||
        fail(:semantic_mismatch, "cannot-run failure count changed")

    selector_text = _text(bundle, "structural_asof_selector")
    for component in comparison["structural_component_ids"]
        _require_occurs(selector_text, "\"$component\"", "structural selector")
    end
    _require_occurs(
        selector_text,
        "RETROSPECTIVE_HINDSIGHT_SELECTED",
        "structural selector",
    )
    _require_occurs(selector_text, "ORIGIN_ELIGIBLE_AS_OF", "structural selector")

    opening_mapping = _document(bundle, "opening_macro_mapping")
    opening_mapping["artifact"]["content_sha256"] ==
        claims["opening_mapping_content_sha256"] ||
        fail(:semantic_mismatch, "opening-mapping semantic identity changed")
    opening_mapping["gate"]["status"] == "OPEN" ||
        fail(:gate_elevation, "opening-mapping gate changed")
    length(opening_mapping["mapping"]) == 7 ||
        fail(:semantic_mismatch, "opening-mapping count changed")
    mapping_statuses = [String(item["status"]) for item in opening_mapping["mapping"]]
    count(==("unresolved"), mapping_statuses) == 6 ||
        fail(:semantic_mismatch, "opening unresolved-mapping count changed")
    count(==("rejected"), mapping_statuses) == 1 ||
        fail(:semantic_mismatch, "opening rejected-mapping count changed")

    parameter_registry = _document(bundle, "parameter_registry")
    parameter_registry["schema"]["baseline_parameter_count"] == 66 ||
        fail(:semantic_mismatch, "parameter-registry declared count changed")
    length(parameter_registry["parameter"]) == 66 ||
        fail(:semantic_mismatch, "parameter-registry row count changed")
    parameter_statuses = [
        String(item["review_status"]) for item in parameter_registry["parameter"]
    ]
    count(==("approved"), parameter_statuses) == 0 ||
        fail(:gate_elevation, "parameter approval count changed")
    count(==("provisional"), parameter_statuses) == 22 ||
        fail(:semantic_mismatch, "provisional parameter count changed")
    count(==("unresolved"), parameter_statuses) == 43 ||
        fail(:semantic_mismatch, "unresolved parameter count changed")
    count(==("rejected"), parameter_statuses) == 1 ||
        fail(:semantic_mismatch, "rejected parameter count changed")
    origin_record["parameter_registry_sha256"] ==
        claims["parameter_registry_content_sha256"] ||
        fail(:invalid_binding, "origin parameter-registry semantic binding changed")

    variant = _document(bundle, "variant_manifest")
    variant["artifact"]["content_sha256"] ==
        claims["variant_manifest_content_sha256"] ||
        fail(:semantic_mismatch, "variant-manifest semantic identity changed")
    variant["artifact_status"] == "draft" ||
        fail(:gate_elevation, "variant artifact status changed")
    variant["gate"]["status"] == "open" ||
        fail(:gate_elevation, "variant gate status changed")
    origin_record["model_variant_sha256"] ==
        claims["variant_manifest_content_sha256"] ||
        fail(:invalid_binding, "origin variant semantic binding changed")

    accounting = _document(bundle, "accounting_gates")
    _binding_record(bundle, "accounting_gates")["physical_sha256"] ==
        claims["accounting_gates_physical_sha256"] ||
        fail(:invalid_binding, "accounting-gates physical binding changed")
    accounting["gate_status"] == "FAIL" ||
        fail(:gate_elevation, "accounting gate changed")
    accounting["gate_split"]["latent_state_status"] == "FAIL" ||
        fail(:gate_elevation, "latent-state gate changed")
    accounting["gate_split"]["inventory_stock_status"] == "MISSING" ||
        fail(:gate_elevation, "inventory-stock gate changed")
    accounting["gate_split"]["supply_make_valuation_status"] == "FAIL" ||
        fail(:gate_elevation, "supply/make/valuation gate changed")
    accounting["gate_split"]["full_accounting_status"] == "FAIL" ||
        fail(:gate_elevation, "full-accounting gate changed")

    source_schema = _document(bundle, "source_inventory_schema")
    source_schema["requirements_schema_version"] ==
        "beforeit-us-source-completeness-requirements.v1" ||
        fail(:semantic_mismatch, "source-completeness schema changed")

    _require_occurs(
        _text(bundle, "synthetic_origin_builder"),
        "const EVIDENCE_CLASS = \"synthetic_fixture_only\"",
        "origin builder",
    )
    _require_occurs(
        _text(bundle, "synthetic_origin_receipt"),
        "const EVIDENCE_CLASS = \"synthetic_fixture_only\"",
        "origin receipt",
    )
    _require_occurs(
        _text(bundle, "synthetic_benchmark_adapter"),
        "const SYNTHETIC_ORIGIN_EVIDENCE = \"synthetic_fixture_only\"",
        "benchmark adapter",
    )

    targets = _document(bundle, "tier1_target_contract")
    targets["artifact"]["content_sha256"] == claims["target_contract_content_sha256"] ||
        fail(:semantic_mismatch, "target-contract semantic identity changed")
    target_contract = _expect_table(targets["contract"], "targets.contract")
    target_contract["required_target_count"] == length(targets["targets"]) == 8 ||
        fail(:semantic_mismatch, "Tier-1 target count changed")
    target_contract["truth_matrix_count"] == 0 ||
        fail(:gate_elevation, "Tier-1 truth-matrix count changed")
    target_contract["approved_operator_bridge_count"] == 0 ||
        fail(:gate_elevation, "Tier-1 approved bridge count changed")
    target_contract["evidence_verifier_status"] == "NOT_IMPLEMENTED_FAIL_CLOSED" ||
        fail(:gate_elevation, "Tier-1 verifier status changed")
    target_contract["protocol_sha256"] == claims["protocol_content_sha256"] ||
        fail(:invalid_binding, "target-contract protocol semantic binding changed")

    target_bindings = _expect_vector(
        manifest["model_target_bindings"],
        "manifest.model_target_bindings",
    )
    length(target_bindings) == 8 ||
        fail(:invalid_contract, "model-target binding count changed")
    expected_sources = Set(
        [
            ("core3_autoregressive", "real_gdp_growth", "real_gdp"),
            ("core3_autoregressive", "pce_inflation", "pce_price_index"),
            (
                "core3_autoregressive",
                "effective_federal_funds_rate",
                "effective_federal_funds_rate",
            ),
            ("small_new_keynesian_dsge", "real_gdp_growth", "real_gdp"),
            ("small_new_keynesian_dsge", "pce_inflation", "pce_price_index"),
            (
                "small_new_keynesian_dsge",
                "effective_federal_funds_rate",
                "effective_federal_funds_rate",
            ),
            ("beforeit_us_abm_base", "real_gdp_growth", "real_gdp"),
            (
                "beforeit_us_abm_base",
                "gdp_deflator_inflation",
                "gdp_deflator",
            ),
        ],
    )
    observed_sources = Set{Tuple{String, String, String}}()
    expected_source_units = Dict(
        ("core3_autoregressive", "real_gdp_growth") =>
            "annualized_quarter_over_quarter_percent",
        ("core3_autoregressive", "pce_inflation") =>
            "annualized_quarter_over_quarter_percent",
        ("core3_autoregressive", "effective_federal_funds_rate") =>
            "quarterly_average_percent",
        ("small_new_keynesian_dsge", "real_gdp_growth") =>
            "annualized_quarter_over_quarter_percent",
        ("small_new_keynesian_dsge", "pce_inflation") =>
            "annualized_quarter_over_quarter_percent",
        ("small_new_keynesian_dsge", "effective_federal_funds_rate") =>
            "quarterly_average_percent",
        ("beforeit_us_abm_base", "real_gdp_growth") =>
            "percentage_points_annual_rate",
        ("beforeit_us_abm_base", "gdp_deflator_inflation") =>
            "percentage_points_annual_rate",
    )
    for (index, binding_value) in enumerate(target_bindings)
        binding = _expect_table(binding_value, "model_target_bindings[$index]")
        _expect_exact_keys(
            binding,
            [
                "model_family_id",
                "source_target_id",
                "source_unit",
                "official_target_id",
                "operator_version",
                "transformation_version",
                "official_output_unit",
                "mapping_status",
            ],
            "model_target_bindings[$index]",
        )
        family = String(binding["model_family_id"])
        source_target = String(binding["source_target_id"])
        official_target = String(binding["official_target_id"])
        push!(observed_sources, (family, source_target, official_target))
        binding["source_unit"] == expected_source_units[(family, source_target)] ||
            fail(:invalid_binding, "source unit changed for $family/$source_target")
        target = only(
            [item for item in targets["targets"] if item["target_id"] == official_target],
        )
        binding["operator_version"] == target["operator_version"] ||
            fail(:invalid_binding, "operator binding changed for $family/$source_target")
        binding["transformation_version"] == target["transformation_version"] ||
            fail(:invalid_binding, "transform binding changed for $family/$source_target")
        binding["official_output_unit"] == target["output_unit"] ||
            fail(:invalid_binding, "unit binding changed for $family/$source_target")
        binding["mapping_status"] == "unapproved" ||
            fail(:gate_elevation, "model-target mapping was elevated")
    end
    observed_sources == expected_sources ||
        fail(:invalid_contract, "model-target source bindings changed")
    any(
        item -> item[1] == "core3_autoregressive" &&
            item[2] == "pce_inflation" && item[3] == "gdp_deflator",
        observed_sources,
    ) && fail(:invalid_binding, "PCE inflation was aliased to the GDP deflator")
    effr_target = only(
        [
            item for item in targets["targets"] if
                item["target_id"] == "effective_federal_funds_rate"
        ],
    )
    effr_target["primary_transformation"] == "percentage_point_level" ||
        fail(:invalid_binding, "EFFR level transformation changed")

    protocol = _document(bundle, "evaluation_protocol")
    protocol["status"] == "draft" ||
        fail(:gate_elevation, "evaluation protocol status changed")
    protocol["approval_status"] == "pending_validation" ||
        fail(:gate_elevation, "evaluation protocol approval changed")
    protocol["governance"]["frozen"] === false ||
        fail(:gate_elevation, "evaluation protocol frozen flag changed")
    protocol_horizons = protocol["products"]["quarterly_unconditional"]["horizons"]
    protocol_horizons == comparison["required_protocol_horizons"] ||
        fail(:semantic_mismatch, "evaluation horizons changed")
    protocol["origin_requirements"]["core_horizons"] == comparison["core_horizons"] ||
        fail(:semantic_mismatch, "core horizons changed")
    protocol["origin_requirements"]["long_horizons"] == comparison["long_horizons"] ||
        fail(:semantic_mismatch, "long horizons changed")

    registry = _document(bundle, "benchmark_registry_manifest")
    registry["registry_content_sha256"] == claims["benchmark_registry_content_sha256"] ||
        fail(:semantic_mismatch, "benchmark-registry semantic identity changed")
    registry["execution_scope"]["empirical_forecast_execution_allowed"] === false ||
        fail(:gate_elevation, "benchmark empirical execution flag changed")
    registry["execution_scope"]["production_scoring_allowed"] === false ||
        fail(:gate_elevation, "benchmark production scoring flag changed")

    core3_text = _text(bundle, "core3_mechanics_module")
    for fact in (
            "CORE3_AUTOREGRESSIVE_MECHANICS_VALIDATED_NONADMITTING",
            "quarterly_nk3_aggregate_pce_contract_v1",
            "revised_mixed_vintage_diagnostic",
            "const REVISED_PANEL_START = \"$(comparison["core3_panel_start"])\"",
            "const REVISED_PANEL_END = \"$(comparison["core3_panel_end"])\"",
            "const MAXIMUM_HORIZON = 12",
            "nk3_aggregate_pce_univariate_ar1_ols_v1",
            "nk3_aggregate_pce_var1_ols_v1",
            "nk3_aggregate_pce_bvar1_mniw_stationary_v1",
            claims["core3_ar_model_contract_sha256"],
            claims["core3_var_model_contract_sha256"],
            claims["core3_bvar_model_contract_sha256"],
        )
        _require_occurs(core3_text, fact, "core3 mechanics")
    end
    core3_fixture = _document(bundle, "core3_revised_fixture_manifest")
    core3_fixture["schema_version"] ==
        "beforeit-us-revised-data-quarterly-panel.v1" ||
        fail(:semantic_mismatch, "core3 fixture metadata schema changed")
    core3_fixture["information_track"] ==
        comparison["core3_fixture_information_track"] ||
        fail(:semantic_mismatch, "core3 fixture information track changed")
    core3_fixture["forecast_origin_admissible"] === false ||
        fail(:gate_elevation, "core3 fixture origin-admission flag changed")
    core3_fixture["promotion_eligible"] === false ||
        fail(:gate_elevation, "core3 fixture promotion flag changed")
    core3_fixture["real_time"] === false ||
        fail(:gate_elevation, "core3 fixture real-time flag changed")
    core3_fixture["row_count"] == comparison["core3_fixture_row_count"] ||
        fail(:semantic_mismatch, "core3 fixture declared row count changed")
    core3_fixture["start_period"] == comparison["core3_panel_start"] ||
        fail(:semantic_mismatch, "core3 fixture start period changed")
    core3_fixture["end_period"] == comparison["core3_panel_end"] ||
        fail(:semantic_mismatch, "core3 fixture end period changed")
    core3_fixture["panel_file"] == comparison["core3_fixture_declared_panel_file"] ||
        fail(:semantic_mismatch, "core3 fixture declared panel path changed")
    core3_fixture["panel_sha256"] ==
        comparison["core3_fixture_declared_panel_sha256"] ||
        fail(:semantic_mismatch, "core3 fixture declared panel identity changed")
    core3_fixture["target_order"] == [
        "real_gdp",
        "pce_price_index",
        "core_pce_price_index",
        "gdp_deflator",
        "unemployment_rate",
        "payroll_employment",
        "effective_federal_funds_rate",
        "nominal_gdp",
    ] || fail(:semantic_mismatch, "core3 fixture target order changed")
    core3_quarantine = _expect_table(
        core3_fixture["quarantine"],
        "core3 fixture quarantine",
    )
    core3_quarantine["inventory_registered"] === false ||
        fail(:gate_elevation, "core3 fixture inventory registration changed")
    core3_quarantine["origin_count_added"] == 0 ||
        fail(:gate_elevation, "core3 fixture origin count changed")
    core3_quarantine["abm_forecast_scores_added"] == 0 ||
        fail(:gate_elevation, "core3 fixture forecast score count changed")
    derived_h1 = _last_origin_for_horizon(comparison["core3_panel_end"], 1)
    derived_h4 = _last_origin_for_horizon(comparison["core3_panel_end"], 4)
    derived_h12 = _last_origin_for_horizon(comparison["core3_panel_end"], 12)
    derived_h1 == comparison["core3_last_h1_origin"] ||
        fail(:invalid_contract, "core3 last h1 origin assertion is not derived")
    derived_h4 == comparison["core3_last_h4_origin"] ||
        fail(:invalid_contract, "core3 last h4 origin assertion is not derived")
    derived_h12 == comparison["core3_last_h12_origin"] ||
        fail(:invalid_contract, "core3 last h12 origin assertion is not derived")

    small_nk_text = _text(bundle, "small_nk_mechanics_module")
    for fact in (
            "const MODEL_CLASS = \"small_new_keynesian_dsge\"",
            "FIXED_PARAMETER_DSGE_MECHANICS_VALIDATED_NO_EMPIRICAL_EVIDENCE",
            "quarterly_nk3_aggregate_pce_contract_v1",
            claims["small_nk_mechanics_fingerprint_sha256"],
            "const MAXIMUM_PREDICTIVE_HORIZON = 12",
        )
        _require_occurs(small_nk_text, fact, "small-NK mechanics")
    end

    abm = _document(bundle, "abm_v5_protocol")
    abm["model_id"] == "beforeit-us-abm-base" ||
        fail(:semantic_mismatch, "ABM model ID changed")
    abm["information_track"] == "revised_mixed_vintage" ||
        fail(:gate_elevation, "ABM information track changed")
    abm["origin_period"] == comparison["abm_origin_period"] ||
        fail(:semantic_mismatch, "ABM origin changed")
    abm["horizons"] == [1, 2, 3, 4] ||
        fail(:semantic_mismatch, "ABM horizons changed")
    abm["path_count"] == comparison["abm_path_count"] ||
        fail(:semantic_mismatch, "ABM path count changed")
    abm["horizon_measurement_basis"][1] == comparison["abm_h1_basis"] ||
        fail(:semantic_mismatch, "ABM h1 measurement basis changed")
    all(
        ==(comparison["abm_later_basis"]),
        abm["horizon_measurement_basis"][2:4],
    ) || fail(:semantic_mismatch, "ABM later-horizon measurement basis changed")
    abm["expected_multi_step_path_set_sha256"] ==
        claims["abm_v5_path_set_sha256"] ||
        fail(:semantic_mismatch, "ABM path-set identity changed")
    abm["expected_path_one_h4_post_collection_sha256"] ==
        claims["abm_v5_path_one_h4_sha256"] ||
        fail(:semantic_mismatch, "ABM h4 path identity changed")
    abm["expected_multi_step_execution_envelope_sha256"] ==
        claims["abm_v5_execution_envelope_sha256"] ||
        fail(:semantic_mismatch, "ABM execution envelope changed")
    abm["execution_counts"]["total_constructions"] == 65 ||
        fail(:semantic_mismatch, "ABM construction count changed")
    abm["execution_counts"]["total_steps"] == 260 ||
        fail(:semantic_mismatch, "ABM step count changed")
    abm["execution_counts"]["total_collection_events"] == 325 ||
        fail(:semantic_mismatch, "ABM collection count changed")
    _require_occurs(
        _text(bundle, "abm_v5_module"),
        claims["abm_v5_result_sha256"],
        "ABM v5 module accepted result",
    )

    rejected = _expect_table(manifest["rejected_claims"], "manifest.rejected_claims")
    rejected["core3_equilibrium_comparison_disposition"] ==
        "REJECTED_NOT_COMMON_ORIGIN_EVIDENCE" ||
        fail(:gate_elevation, "rejected comparison disposition changed")
    for (claim_key, expected_hash) in EXPECTED_REJECTED_COMPARISON_HASHES
        rejected[claim_key] == expected_hash ||
            fail(:invalid_contract, "historical rejected comparison identity changed")
    end
    return nothing
end

function _registered_model_ids(registry)
    models = _expect_vector(registry["models"], "registry.models")
    return sort!(String[model["model_id"] for model in models])
end

function _target_by_id(targets, target_id)
    selected = [target for target in targets if target["target_id"] == target_id]
    length(selected) == 1 ||
        fail(:semantic_mismatch, "target $target_id is missing or duplicated")
    return only(selected)
end

function _add_blocker!(blockers, reason_id, source_binding_ids)
    bindings = sort!(unique!(String.(collect(source_binding_ids))))
    isempty(bindings) && fail(:invalid_blocker, "blocker $reason_id has no source binding")
    push!(
        blockers,
        Dict{String, Any}(
            "reason_id" => String(reason_id),
            "source_binding_ids" => bindings,
        ),
    )
    return nothing
end

function _sorted_unique_blockers(blockers)
    sort!(blockers; by = item -> item["reason_id"])
    ids = String[item["reason_id"] for item in blockers]
    allunique(ids) || fail(:invalid_blocker, "duplicate derived blocker")
    return blockers
end

function _condition_ids_for_blocker(reason_id::AbstractString)
    reason = String(reason_id)
    if startswith(reason, "SOURCE_RELEASE_EVENT_") ||
            reason in (
            "SOURCE_INVENTORY_INCOMPLETE",
            "SOURCE_INVENTORY_VERIFIER_NOT_IMPLEMENTED_FAIL_CLOSED",
            "COMMON_WINDOW_GATE_FALSE:ARTIFACT_CAPTURE_COMPLETE",
            "COMMON_WINDOW_GATE_FALSE:SOURCE_COVERAGE_PROVEN",
        )
        return ["source_release_events_present"]
    elseif reason == "ADMISSIBLE_ORIGIN_COUNT_ZERO" ||
            reason == "COMMON_WINDOW_GATE_FALSE:ORIGIN_ADMISSION_COMPLETE"
        return ["admissible_origins_present"]
    elseif startswith(reason, "COMMON_WINDOW_METADATA_LABELS_NOT_ADMITTED") ||
            reason in (
            "STRICT_ALL_THREE_COMMON_ORIGIN_INTERSECTION_EMPTY",
            "COMMON_WINDOW_GATE_FALSE:STRICT_INTERSECTION_ADMISSIBLE",
        )
        return ["strict_common_origin_intersection_present"]
    elseif reason in (
            "CURRENT_ORIGIN_REVISED_MIXED_VINTAGE_TRACK_FORBIDDEN",
            "CORE3_INFORMATION_TRACK_REVISED_MIXED_VINTAGE_FORBIDDEN",
            "ABM_INFORMATION_TRACK_REVISED_MIXED_VINTAGE_FORBIDDEN",
        )
        return ["origin_information_track_exact_as_of"]
    elseif reason == "CURRENT_ORIGIN_STATUS_CANNOT_RUN" ||
            startswith(reason, "ORIGIN_FAILURE:")
        return ["origin_package_runnable"]
    elseif startswith(reason, "REGISTERED_STRUCTURAL_CATALOG_EMPTY:")
        return ["structural_historical_catalogs_complete"]
    elseif reason == "STRUCTURAL_ASOF_SELECTOR_HAS_NO_BOUND_RELEASE_SET_OR_RECEIPT"
        return ["structural_selection_as_of_only"]
    elseif startswith(reason, "SYNTHETIC_") ||
            reason == "COMMON_WINDOW_GATE_FALSE:TERMS_AUTHORIZATION_COMPLETE"
        return ["empirical_receipts_source_bound_nonsynthetic"]
    elseif reason == "TIER1_APPROVED_OPERATOR_BRIDGE_COUNT_ZERO" ||
            startswith(reason, "TARGET_OPERATOR_NOT_APPROVED:")
        return ["target_operators_approved"]
    elseif startswith(reason, "TARGET_HISTORICAL_VINTAGE_COUNT_ZERO:")
        return ["target_historical_vintages_present"]
    elseif reason in (
            "TIER1_EVIDENCE_VERIFIER_NOT_IMPLEMENTED_FAIL_CLOSED",
            "TIER1_TARGET_CONTRACT_NOT_FROZEN",
        )
        return ["target_contract_frozen_without_truth_access"]
    elseif startswith(reason, "EVALUATION_PROTOCOL_")
        return ["evaluation_protocol_frozen"]
    elseif startswith(reason, "REQUIRED_MODEL_UNREGISTERED:") ||
            reason == "SMALL_NK_MECHANICS_CLASS_HAS_NO_EXECUTABLE_REGISTRY_MODEL_ID"
        return ["all_models_registered"]
    elseif startswith(reason, "MODEL_COMMON_ORIGIN_INTERSECTION_EMPTY:") ||
            reason in (
            "SMALL_NK_FIXED_PARAMETERS_NOT_ORIGIN_WISE_ESTIMATED",
            "ABM_ACCEPTED_RESULT_SOFTWARE_ONLY_NONADMITTING",
        )
        return ["model_origin_semantics_match"]
    elseif reason == "ELIGIBLE_COMMON_TARGET_INTERSECTION_EMPTY_UNAPPROVED_BRIDGE"
        return ["model_target_semantics_match"]
    elseif startswith(reason, "COMMON_TRANSFORMATION_OPERATOR_NOT_APPROVED:")
        return ["model_transform_semantics_match"]
    elseif reason in (
            "NOMINAL_COMMON_HORIZONS_ONLY_1_2_4",
            "REQUIRED_LONG_HORIZONS_8_12_ABSENT_FROM_ABM",
            "ABM_H2_H4_RAW_MODEL_PATHS_HAVE_NO_APPROVED_OFFICIAL_BRIDGE",
            "ELIGIBLE_COMMON_HORIZON_CELL_INTERSECTION_EMPTY",
        )
        return ["eligible_required_protocol_horizons_complete"]
    elseif reason == "ABM_H1_OPENING_TO_FLOW_MEASUREMENT_BASIS_BREAK"
        return ["abm_h1_measurement_basis_compatible"]
    elseif reason in (
            "ABM_PATH_COUNT_32_HAS_NO_COMMON_REGISTERED_CONVERGENCE_CONTRACT",
            "MODEL_PATH_REGISTRATION_INTERSECTION_EMPTY",
        )
        return ["path_protocols_compatible"]
    elseif reason in (
            "BENCHMARK_EMPIRICAL_EXECUTION_NOT_AUTHORIZED",
            "COMMON_WINDOW_GATE_FALSE:EMPIRICAL_EXECUTION_ALLOWED",
        )
        return ["benchmark_empirical_execution_authorized"]
    elseif reason in (
            "FORECAST_SEAL_CANNOT_AUTHENTICATE_VINTAGE_OR_SOURCE_PROVENANCE",
            "FORECAST_SEAL_INPUTS_INCOMPLETE_ON_CURRENT_EVIDENCE",
        )
        return ["forecast_seal_inputs_complete"]
    end
    return fail(:invalid_blocker, "blocker $reason is not mapped to a readiness condition")
end

function _derive_result(bundle::EvidenceBundle)
    _validate_bound_semantics(bundle)
    manifest = bundle.manifest
    comparison = manifest["comparison_contract"]
    inventory = _document(bundle, "current_source_inventory")
    window = _document(bundle, "common_window_decision")
    origin = _document(bundle, "current_origin_package")
    cannot_run = _document(bundle, "current_origin_cannot_run")
    targets_document = _document(bundle, "tier1_target_contract")
    targets = targets_document["targets"]
    protocol = _document(bundle, "evaluation_protocol")
    registry = _document(bundle, "benchmark_registry_manifest")
    abm = _document(bundle, "abm_v5_protocol")

    required_models = sort!(String.(comparison["required_executable_model_ids"]))
    mechanics_classes = sort!(String.(comparison["mechanics_class_ids"]))
    registered_models = _registered_model_ids(registry)
    registration_intersection = sort!(collect(intersect(Set(required_models), Set(registered_models))))
    missing_models = sort!(collect(setdiff(Set(required_models), Set(registered_models))))

    core3_targets = String.(comparison["core3_target_ids"])
    nk_targets = String.(comparison["small_nk_target_ids"])
    abm_targets = String.(comparison["abm_target_ids"])
    declared_common_targets =
        _intersection([core3_targets, nk_targets, abm_targets])
    declared_common_targets == ["real_gdp"] ||
        fail(:semantic_mismatch, "declared common target intersection changed")
    shared_target = _target_by_id(targets, "real_gdp")
    shared_target["primary_transformation"] == comparison["common_target_transform"] ||
        fail(:semantic_mismatch, "shared GDP transformation changed")
    eligible_common_targets = shared_target["operator_status"] == "approved" &&
        shared_target["historical_vintage_count"] > 0 ? ["real_gdp"] : String[]

    protocol_horizons = Int.(comparison["required_protocol_horizons"])
    core3_horizons = collect(1:12)
    nk_horizons = collect(1:12)
    abm_horizons = Int.(abm["horizons"])
    nominal_horizons = _intersection(
        [protocol_horizons, core3_horizons, nk_horizons, abm_horizons],
    )
    nominal_horizons == [1, 2, 4] ||
        fail(:semantic_mismatch, "nominal horizon intersection changed")
    eligible_horizons = Int[]

    abm_origin = String(comparison["abm_origin_period"])
    core3_last_h1 = _last_origin_for_horizon(comparison["core3_panel_end"], 1)
    core3_last_h4 = _last_origin_for_horizon(comparison["core3_panel_end"], 4)
    core3_last_h12 = _last_origin_for_horizon(comparison["core3_panel_end"], 12)
    _quarter_index(abm_origin) > _quarter_index(core3_last_h1) ||
        fail(:semantic_mismatch, "ABM/core3 origin geometry changed")
    strict_origins = String[]

    blockers = Dict{String, Any}[]
    limitations = Dict{String, Any}[]
    _add_blocker!(blockers, "SOURCE_RELEASE_EVENT_COUNT_ZERO", ["current_source_inventory"])
    _add_blocker!(blockers, "ADMISSIBLE_ORIGIN_COUNT_ZERO", ["current_source_inventory"])
    _add_blocker!(blockers, "SOURCE_INVENTORY_INCOMPLETE", ["current_source_inventory"])
    _add_blocker!(
        blockers,
        "SOURCE_INVENTORY_VERIFIER_NOT_IMPLEMENTED_FAIL_CLOSED",
        ["current_source_inventory"],
    )

    seal_blocking_window_gates = Set(
        [
            "artifact_capture_complete",
            "empirical_execution_allowed",
            "origin_admission_complete",
            "source_coverage_proven",
            "strict_intersection_admissible",
            "terms_authorization_complete",
        ],
    )
    for (gate, value) in sort!(collect(window["gates"]); by = first)
        value === false || fail(:gate_elevation, "common-window gate $gate is not false")
        _add_blocker!(
            String(gate) in seal_blocking_window_gates ? blockers : limitations,
            "COMMON_WINDOW_GATE_FALSE:$(uppercase(String(gate)))",
            ["common_window_decision", "current_source_inventory"],
        )
    end
    _add_blocker!(
        blockers,
        "COMMON_WINDOW_METADATA_LABELS_NOT_ADMITTED:2016Q2:2021Q2:21",
        ["common_window_decision"],
    )
    _add_blocker!(
        blockers,
        "STRICT_ALL_THREE_COMMON_ORIGIN_INTERSECTION_EMPTY",
        ["common_window_decision", "current_source_inventory"],
    )

    _add_blocker!(
        blockers,
        "CURRENT_ORIGIN_STATUS_CANNOT_RUN",
        ["current_origin_package", "current_origin_cannot_run"],
    )
    _add_blocker!(
        blockers,
        "CURRENT_ORIGIN_REVISED_MIXED_VINTAGE_TRACK_FORBIDDEN",
        ["current_origin_package"],
    )
    for failure in cannot_run["failures"]
        reason = "ORIGIN_FAILURE:" * uppercase(replace(String(failure["failure_id"]), ':' => '_')) *
            ":" * uppercase(String(failure["status"]))
        _add_blocker!(
            blockers,
            reason,
            ["current_origin_package", "current_origin_cannot_run"],
        )
    end

    for component in comparison["structural_component_ids"]
        _add_blocker!(
            blockers,
            "REGISTERED_STRUCTURAL_CATALOG_EMPTY:$(uppercase(String(component)))",
            ["structural_asof_selector", "current_source_inventory"],
        )
    end
    _add_blocker!(
        blockers,
        "STRUCTURAL_ASOF_SELECTOR_HAS_NO_BOUND_RELEASE_SET_OR_RECEIPT",
        ["structural_asof_selector", "current_source_inventory"],
    )

    _add_blocker!(
        blockers,
        "SYNTHETIC_ORIGIN_BUILDER_NOT_EMPIRICAL_EVIDENCE",
        ["synthetic_origin_builder"],
    )
    _add_blocker!(
        blockers,
        "SYNTHETIC_ORIGIN_RECEIPT_NOT_EMPIRICAL_EVIDENCE",
        ["synthetic_origin_receipt"],
    )
    _add_blocker!(
        blockers,
        "SYNTHETIC_BENCHMARK_ADAPTER_NOT_EMPIRICAL_EVIDENCE",
        ["synthetic_benchmark_adapter"],
    )

    target_contract = targets_document["contract"]
    _add_blocker!(
        limitations,
        "TIER1_TRUTH_MATRIX_COUNT_ZERO_TRUTH_ARTIFACT_ABSENT_AND_NOT_LOADED",
        ["tier1_target_contract"],
    )
    _add_blocker!(
        blockers,
        "TIER1_APPROVED_OPERATOR_BRIDGE_COUNT_ZERO",
        ["tier1_target_contract"],
    )
    _add_blocker!(
        blockers,
        "TIER1_EVIDENCE_VERIFIER_NOT_IMPLEMENTED_FAIL_CLOSED",
        ["tier1_target_contract"],
    )
    _add_blocker!(
        blockers,
        "TIER1_TARGET_CONTRACT_NOT_FROZEN",
        ["tier1_target_contract", "evaluation_protocol"],
    )
    target_contract["truth_matrix_count"] == 0 ||
        fail(:gate_elevation, "truth matrix unexpectedly present")
    for target in targets
        target_id = uppercase(String(target["target_id"]))
        target["operator_status"] == "approved" ||
            _add_blocker!(
            blockers,
            "TARGET_OPERATOR_NOT_APPROVED:$target_id:$(uppercase(String(target["operator_status"])))",
            ["tier1_target_contract"],
        )
        target["historical_vintage_count"] > 0 ||
            _add_blocker!(
            blockers,
            "TARGET_HISTORICAL_VINTAGE_COUNT_ZERO:$target_id",
            ["tier1_target_contract"],
        )
    end

    _add_blocker!(blockers, "EVALUATION_PROTOCOL_DRAFT", ["evaluation_protocol"])
    _add_blocker!(
        blockers,
        "EVALUATION_PROTOCOL_APPROVAL_PENDING",
        ["evaluation_protocol"],
    )
    _add_blocker!(blockers, "EVALUATION_PROTOCOL_NOT_FROZEN", ["evaluation_protocol"])

    _add_blocker!(
        blockers,
        "BENCHMARK_EMPIRICAL_EXECUTION_NOT_AUTHORIZED",
        ["benchmark_registry_manifest", "benchmark_registry_module"],
    )
    _add_blocker!(
        limitations,
        "BENCHMARK_PRODUCTION_SCORING_NOT_AUTHORIZED",
        ["benchmark_registry_manifest", "benchmark_registry_module"],
    )
    for model_id in missing_models
        binding = model_id == "beforeit-us-abm-base" ? "abm_v5_module" :
            "core3_mechanics_module"
        _add_blocker!(
            blockers,
            "REQUIRED_MODEL_UNREGISTERED:$(uppercase(model_id))",
            [binding, "benchmark_registry_manifest"],
        )
    end

    _add_blocker!(
        blockers,
        "MODEL_COMMON_ORIGIN_INTERSECTION_EMPTY:ABM_2026Q1_AFTER_CORE3_LAST_H1_2025Q2",
        ["abm_v5_protocol", "core3_mechanics_module", "core3_revised_fixture_manifest"],
    )
    _add_blocker!(
        blockers,
        "CORE3_INFORMATION_TRACK_REVISED_MIXED_VINTAGE_FORBIDDEN",
        ["core3_mechanics_module", "core3_revised_fixture_manifest"],
    )
    _add_blocker!(
        blockers,
        "SMALL_NK_FIXED_PARAMETERS_NOT_ORIGIN_WISE_ESTIMATED",
        ["small_nk_mechanics_module", "small_nk_mechanics_readme"],
    )
    _add_blocker!(
        blockers,
        "SMALL_NK_MECHANICS_CLASS_HAS_NO_EXECUTABLE_REGISTRY_MODEL_ID",
        ["small_nk_mechanics_module", "benchmark_registry_manifest"],
    )
    _add_blocker!(
        blockers,
        "ABM_INFORMATION_TRACK_REVISED_MIXED_VINTAGE_FORBIDDEN",
        ["abm_v5_protocol"],
    )
    _add_blocker!(
        blockers,
        "ABM_ACCEPTED_RESULT_SOFTWARE_ONLY_NONADMITTING",
        ["abm_v5_module", "abm_v5_protocol", "abm_v5_readme"],
    )

    _add_blocker!(
        limitations,
        "DECLARED_COMMON_TARGET_INTERSECTION_SINGLETON_REAL_GDP",
        ["abm_v5_protocol", "core3_mechanics_module", "small_nk_mechanics_module"],
    )
    _add_blocker!(
        blockers,
        "ELIGIBLE_COMMON_TARGET_INTERSECTION_EMPTY_UNAPPROVED_BRIDGE",
        ["abm_v5_protocol", "tier1_target_contract"],
    )
    _add_blocker!(
        limitations,
        "PCE_INFLATION_MUST_NOT_ALIAS_GDP_DEFLATOR_INFLATION",
        ["abm_v5_protocol", "core3_mechanics_module", "tier1_target_contract"],
    )
    _add_blocker!(
        blockers,
        "COMMON_TRANSFORMATION_OPERATOR_NOT_APPROVED:ANNUALIZED_QOQ_LOG_GROWTH",
        ["tier1_target_contract"],
    )

    _add_blocker!(
        blockers,
        "NOMINAL_COMMON_HORIZONS_ONLY_1_2_4",
        ["abm_v5_protocol", "evaluation_protocol", "core3_mechanics_module", "small_nk_mechanics_module"],
    )
    _add_blocker!(
        blockers,
        "REQUIRED_LONG_HORIZONS_8_12_ABSENT_FROM_ABM",
        ["abm_v5_protocol", "evaluation_protocol"],
    )
    _add_blocker!(
        blockers,
        "ABM_H1_OPENING_TO_FLOW_MEASUREMENT_BASIS_BREAK",
        ["abm_v5_protocol"],
    )
    _add_blocker!(
        blockers,
        "ABM_H2_H4_RAW_MODEL_PATHS_HAVE_NO_APPROVED_OFFICIAL_BRIDGE",
        ["abm_v5_protocol", "tier1_target_contract"],
    )
    _add_blocker!(
        blockers,
        "ELIGIBLE_COMMON_HORIZON_CELL_INTERSECTION_EMPTY",
        ["abm_v5_protocol", "evaluation_protocol", "tier1_target_contract"],
    )

    _add_blocker!(
        blockers,
        "ABM_PATH_COUNT_32_HAS_NO_COMMON_REGISTERED_CONVERGENCE_CONTRACT",
        ["abm_v5_protocol", "benchmark_registry_manifest", "evaluation_protocol"],
    )
    _add_blocker!(
        blockers,
        "MODEL_PATH_REGISTRATION_INTERSECTION_EMPTY",
        ["abm_v5_protocol", "benchmark_registry_manifest", "core3_mechanics_module", "small_nk_mechanics_module"],
    )

    for blocker in abm["blockers"]
        _add_blocker!(
            limitations,
            "ABM_V5_PROTOCOL_BLOCKER:$(String(blocker))",
            ["abm_v5_protocol"],
        )
    end
    _add_blocker!(
        blockers,
        "FORECAST_SEAL_CANNOT_AUTHENTICATE_VINTAGE_OR_SOURCE_PROVENANCE",
        ["forecast_registry_module", "current_source_inventory"],
    )
    _add_blocker!(
        blockers,
        "FORECAST_SEAL_INPUTS_INCOMPLETE_ON_CURRENT_EVIDENCE",
        [
            "current_source_inventory",
            "current_origin_package",
            "tier1_target_contract",
            "benchmark_registry_manifest",
        ],
    )

    blockers = _sorted_unique_blockers(blockers)
    limitations = _sorted_unique_blockers(limitations)

    conditions = Dict{String, Bool}(
        "source_release_events_present" => !isempty(inventory["release_events"]),
        "admissible_origins_present" =>
            !isempty(inventory["admissible_origin_timestamps_utc"]),
        "strict_common_origin_intersection_present" => !isempty(strict_origins),
        "origin_information_track_exact_as_of" => false,
        "origin_package_runnable" => origin["origin"]["status"] == "ready",
        "structural_historical_catalogs_complete" => false,
        "structural_selection_as_of_only" => false,
        "empirical_receipts_source_bound_nonsynthetic" => false,
        "target_operators_approved" => target_contract["approved_operator_bridge_count"] == 8,
        "target_historical_vintages_present" =>
            all(target -> target["historical_vintage_count"] > 0, targets),
        "target_contract_frozen_without_truth_access" => false,
        "evaluation_protocol_frozen" => protocol["governance"]["frozen"] === true,
        "all_models_registered" => isempty(missing_models),
        "model_origin_semantics_match" => false,
        "model_target_semantics_match" => !isempty(eligible_common_targets),
        "model_transform_semantics_match" => false,
        "eligible_required_protocol_horizons_complete" =>
            eligible_horizons == protocol_horizons,
        "path_protocols_compatible" => false,
        "abm_h1_measurement_basis_compatible" => false,
        "benchmark_empirical_execution_authorized" =>
            registry["execution_scope"]["empirical_forecast_execution_allowed"],
        "forecast_seal_inputs_complete" => false,
    )
    declared_conditions = Set(String.(keys(manifest["required_conditions"])))
    Set(keys(conditions)) == declared_conditions ||
        fail(:invalid_contract, "derived readiness conditions differ from manifest")
    all(value -> value === true, values(manifest["required_conditions"])) ||
        fail(:invalid_contract, "manifest future requirement declarations changed")

    for blocker in blockers
        blocker["condition_ids"] =
            _condition_ids_for_blocker(blocker["reason_id"])
    end
    false_conditions = sort!([key for (key, value) in conditions if !value])
    covered_conditions = Set(
        condition_id for blocker in blockers for condition_id in blocker["condition_ids"]
    )
    Set(false_conditions) == covered_conditions ||
        fail(:invalid_blocker, "blockers do not exactly cover false readiness conditions")
    status = CANNOT_RUN

    source_bindings = sort!(deepcopy(bundle.bindings); by = item -> item["binding_id"])
    readiness = [
        Dict{String, Any}(
                "condition_id" => key,
                "satisfied" => conditions[key],
                "blocking_reason_ids" => sort!(
                    String[
                        blocker["reason_id"] for blocker in blockers if
                        key in blocker["condition_ids"]
                    ],
                ),
            ) for key in sort!(collect(keys(conditions)))
    ]
    policy_rejections = [
        "ABM_H1_OPENING_TO_FLOW_BASIS_BREAK_FORBIDDEN",
        "HINDSIGHT_STRUCTURAL_SELECTION_FORBIDDEN",
        "HISTORICAL_CORE3_EQUILIBRIUM_COMPARISON_REJECTED_NOT_COMMON_ORIGIN_EVIDENCE",
        "MISMATCHED_ORIGIN_TARGET_TRANSFORM_SEMANTICS_FORBIDDEN",
        "PCE_INFLATION_TO_GDP_DEFLATOR_ALIAS_FORBIDDEN",
        "READY_TO_SCORE_FORBIDDEN",
        "REPEATED_HASH_LABEL_WITHOUT_EXACT_SOURCE_BINDING_FORBIDDEN",
        "REVISED_OR_CURRENT_INFORMATION_TRACK_FORBIDDEN",
        "SYNTHETIC_RECEIPT_OR_DERIVATION_FORBIDDEN",
        "UNREGISTERED_MODEL_FORBIDDEN",
    ]

    result = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => SCHEMA_VERSION,
            "canonicalization" => CANONICALIZATION,
            "content_sha256" => ZERO_SHA256,
        ),
        "preflight" => Dict{String, Any}(
            "contract_id" => CONTRACT_ID,
            "status" => status,
            "claim_ceiling" => status,
            "manifest_physical_sha256" => bundle.manifest_physical_sha256,
            "manifest_content_sha256" =>
                bundle.manifest["artifact"]["content_sha256"],
            "source_binding_count" => length(source_bindings),
            "blocking_reason_count" => length(blockers),
            "limitation_count" => length(limitations),
            "successor_only_status" => READY_FOR_SEAL,
            "current_v1_ready_status_reachable" => false,
            "preflight_future_truth_values_loaded" => false,
            "preflight_truth_artifact_accessed" => false,
            "preflight_revised_panel_artifact_accessed" => false,
            "preflight_owned_model_module_loaded" => false,
            "preflight_model_execution_performed" => false,
            "preflight_forecast_artifact_emitted" => false,
            "preflight_score_computed" => false,
            "preflight_filesystem_write_performed" => false,
            "preflight_network_access_performed" => false,
        ),
        "preflight_owned_action_counts" => Dict{String, Any}(
            "pinned_files_read" => length(source_bindings) + 1,
            "metadata_toml_files_parsed" => length(bundle.documents) + 1,
            "upstream_modules_included" => 0,
            "model_constructions" => 0,
            "model_steps" => 0,
            "model_filters" => 0,
            "model_fits" => 0,
            "model_forecasts" => 0,
            "scores" => 0,
            "truth_artifacts_accessed" => 0,
            "revised_panel_artifacts_accessed" => 0,
            "filesystem_writes" => 0,
            "network_requests" => 0,
        ),
        "truth_policy_state" => Dict{String, Any}(
            "truth_policy_metadata_present" => true,
            "truth_policy_metadata_frozen" => false,
            "registered_truth_matrix_count" => Int(target_contract["truth_matrix_count"]),
            "preflight_truth_artifact_accessed" => false,
            "ready_to_score_allowed" => false,
        ),
        "intersections" => Dict{String, Any}(
            "origin" => Dict{String, Any}(
                "metadata_label_first" => "2016Q2",
                "metadata_label_last" => "2021Q2",
                "metadata_label_count" => 21,
                "strict_admitted_origins" => strict_origins,
                "abm_origin_period" => abm_origin,
                "core3_fixture_metadata_binding_id" =>
                    "core3_revised_fixture_manifest",
                "core3_fixture_declared_information_track" =>
                    String(comparison["core3_fixture_information_track"]),
                "core3_fixture_declared_row_count" =>
                    Int(comparison["core3_fixture_row_count"]),
                "core3_fixture_declared_panel_file" =>
                    String(comparison["core3_fixture_declared_panel_file"]),
                "core3_fixture_declared_panel_sha256" =>
                    String(comparison["core3_fixture_declared_panel_sha256"]),
                "core3_revised_panel_artifact_accessed" => false,
                "core3_last_h1_origin" => core3_last_h1,
                "core3_last_h4_origin" => core3_last_h4,
                "core3_last_h12_origin" => core3_last_h12,
                "all_model_common_origins" => String[],
            ),
            "target" => Dict{String, Any}(
                "core3_target_ids" => sort(core3_targets),
                "small_nk_target_ids" => sort(nk_targets),
                "abm_target_ids" => sort(abm_targets),
                "declared_all_model_common_target_ids" => declared_common_targets,
                "eligible_all_model_common_target_ids" => eligible_common_targets,
                "pce_and_gdp_deflator_alias_allowed" => false,
            ),
            "transform" => Dict{String, Any}(
                "declared_common_transform_ids" =>
                    [String(comparison["common_target_transform"])],
                "approved_common_transform_ids" => String[],
            ),
            "horizon" => Dict{String, Any}(
                "required_protocol_horizons" => protocol_horizons,
                "nominal_all_model_horizons" => nominal_horizons,
                "eligible_all_model_horizons" => eligible_horizons,
                "abm_h1_basis" => String(comparison["abm_h1_basis"]),
                "abm_h1_basis_compatible" => false,
            ),
            "path" => Dict{String, Any}(
                "abm_path_count" => Int(comparison["abm_path_count"]),
                "shared_registered_path_contract_ids" => String[],
                "common_convergence_rule_present" => false,
            ),
            "registration" => Dict{String, Any}(
                "required_executable_model_ids" => required_models,
                "mechanics_class_ids_not_executable_model_ids" => mechanics_classes,
                "registered_required_model_ids" => registration_intersection,
                "missing_required_model_ids" => missing_models,
            ),
        ),
        "model_target_bindings" => sort!(
            deepcopy(manifest["model_target_bindings"]);
            by = item -> (item["model_family_id"], item["source_target_id"]),
        ),
        "source_bindings" => source_bindings,
        "readiness_conditions" => readiness,
        "blocking_reasons" => blockers,
        "limitations" => limitations,
        "policy_rejections" => policy_rejections,
        "historical_rejected_evidence" => deepcopy(manifest["rejected_claims"]),
        "scientific_gates" => Dict{String, Any}(
            gate => false for gate in SCIENTIFIC_GATE_NAMES
        ),
    )
    result["artifact"]["content_sha256"] = result_content_sha256(result)
    return result
end

function _compile_current_unchecked_expected()
    bundle = _load_evidence()
    return _derive_result(bundle)
end

function compile_preflight()
    result = _compile_current_unchecked_expected()
    EXPECTED_CURRENT_RESULT_SHA256 == ZERO_SHA256 &&
        fail(:unfrozen, "current preflight result SHA-256 has not been frozen")
    result["artifact"]["content_sha256"] == EXPECTED_CURRENT_RESULT_SHA256 ||
        fail(
        :result_identity_changed,
        "expected $EXPECTED_CURRENT_RESULT_SHA256, got $(result["artifact"]["content_sha256"])",
    )
    return result
end

function validate_preflight(candidate::AbstractDict)
    artifact = _expect_table(get(candidate, "artifact", nothing), "result.artifact")
    _expect_string(artifact["schema_version"], "result.artifact.schema_version") ==
        SCHEMA_VERSION || fail(:invalid_schema, "result schema changed")
    _expect_string(artifact["canonicalization"], "result.artifact.canonicalization") ==
        CANONICALIZATION || fail(:invalid_schema, "result canonicalization changed")
    declared = _expect_hash(artifact["content_sha256"], "result.artifact.content_sha256")
    computed = result_content_sha256(candidate)
    declared == computed || fail(:result_self_hash, "result self-hash mismatch")
    status = _expect_string(candidate["preflight"]["status"], "result.preflight.status")
    status == CANNOT_RUN ||
        fail(:invalid_status, "current v1 result status must remain CANNOT_RUN")
    expected = compile_preflight()
    canonical_bytes(candidate) == canonical_bytes(expected) ||
        fail(:evidence_replay_mismatch, "candidate differs from exact evidence replay")
    return candidate
end

end # module
