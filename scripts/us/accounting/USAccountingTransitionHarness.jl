module USAccountingTransitionHarness

using CSV
using Dates
using JLD2
using LinearAlgebra
using Random
using SHA
using TOML

import BeforeIT as Bit

include(joinpath(@__DIR__, "build_opening_accounting_candidate.jl"))
using .USOpeningAccountingCandidate

export CONTRACT_SCHEMA,
    RECORD_SCHEMA,
    REPORT_SCHEMA,
    CandidateInput,
    HarnessContract,
    IdentityRecord,
    TransitionHarnessReport,
    load_contract,
    run_harness,
    source_tree_digest,
    validate_report,
    write_report

const CONTRACT_SCHEMA =
    "beforeit-us-accounting-transition-harness-contract.v1"
const RECORD_SCHEMA =
    "beforeit-us-accounting-transition-identity-record.v1"
const REPORT_SCHEMA =
    "beforeit-us-accounting-transition-harness-report.v1"
const EXPECTED_HORIZONS = [1, 4, 12]
const EXPECTED_SEEDS = [20261003, 20261004]
const EXPECTED_CANDIDATE_IDS = [
    "nowcast_2026Q1_opening_accounting_v1",
    "structural_2024Q4_opening_accounting_v1",
]
const SAFE_CLASSIFICATION = "REVISED_MIXED_VINTAGE_DIAGNOSTIC"
const SAFE_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const EXPECTED_BLOCKERS = Dict(
    "observed_tax_income_production_variant" =>
        "OBSERVED_TAX_MAPPING_NOT_AVAILABLE",
    "explicit_inventory_stock_flow_variant" =>
        "EXPLICIT_INVENTORY_MAPPING_NOT_AVAILABLE",
    "confidence_weighted_accounting_variant" =>
        "CONFIDENCE_WEIGHT_MAPPING_NOT_AVAILABLE",
)
const SOURCE_TREE_DIGEST_ALGORITHM =
    "sha256(sorted_posix_relative_path + NUL + lowercase_file_sha256 + LF)"
const COMMON_IDENTITY_IDS = Set(
    [
        "nominal_income_production",
        "real_expenditure",
        "central_bank_balance_sheet",
        "commercial_bank_balance_sheet",
        "tracked_data_finite",
        "accounting_state_finite",
        "positive_price_domain",
        "final_goods_inventory_stock_domain",
        "intermediate_goods_inventory_stock_domain",
        "nominal_inventory_flow_decomposition",
        "real_inventory_flow_decomposition",
        "same_seed_exact_replay",
        "same_seed_cross_horizon_prefix",
        collect(keys(EXPECTED_BLOCKERS))...,
    ],
)
const OPENING_IDENTITY_IDS = Set(
    [
        "opening_observation_nominal_expenditure",
        "opening_latent_nominal_expenditure",
    ],
)
const TRANSITION_IDENTITY_IDS = Set(
    [
        "nominal_expenditure_transition",
        "final_goods_inventory_stock_flow",
        "intermediate_goods_inventory_stock_flow",
    ],
)
const AGENT_STATE_FIELDS = (
    :w_act,
    :w_inact,
    :firms,
    :bank,
    :cb,
    :gov,
    :rotw,
    :agg,
    :prop,
    :data,
)
const PRICE_FIELDS = (
    (:firms, :P_i),
    (:firms, :P_bar_i),
    (:firms, :P_CF_i),
    (:rotw, :P_m),
    (:rotw, :P_l),
    (:gov, :P_j),
    (:agg, :P_bar),
    (:agg, :P_bar_g),
    (:agg, :P_bar_HH),
    (:agg, :P_bar_CF),
    (:agg, :P_bar_h),
    (:agg, :P_bar_CF_h),
)
const OPENING_PRICE_FIELDS = (
    (:firms, :P_i),
    (:agg, :P_bar),
    (:agg, :P_bar_g),
    (:agg, :P_bar_HH),
    (:agg, :P_bar_CF),
)
const REPO_ROOT = dirname(
    joinpath(
        normpath(joinpath(@__DIR__, "..", "..", "..")),
        ".accounting-transition-root",
    ),
)
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "accounting_transition_harness.toml")

struct CandidateInput
    candidate_id::String
    origin_period::Date
    artifact_path::String
    artifact_sha256::String
    semantic_sha256::String
    observed_expenditure_residual::Float64
    latent_expenditure_residual::Float64
end

struct HarnessContract
    path::String
    sha256::String
    repo_root::String
    classification::String
    information_track::String
    promotion_status::String
    horizons::Vector{Int}
    seeds::Vector{Int}
    model_numeric_tolerance::Float64
    domain_tolerance::Float64
    candidate_manifest_path::String
    candidate_manifest_sha256::String
    candidate_builder_path::String
    candidate_builder_sha256::String
    candidate_execution_envelope_dependency_path::String
    candidate_execution_envelope_dependency_sha256::String
    candidate_supply_make_dependency_path::String
    candidate_supply_make_dependency_sha256::String
    candidate_t10105_dependency_path::String
    candidate_t10105_dependency_sha256::String
    harness_module_path::String
    harness_module_sha256::String
    julia_project_path::String
    julia_project_sha256::String
    julia_manifest_path::String
    julia_manifest_sha256::String
    runtime_source_tree_path::String
    runtime_source_tree_digest_algorithm::String
    runtime_source_tree_file_count::Int
    runtime_source_tree_sha256::String
    execution_envelope::Dict{String, Any}
    byte_reproducibility_scope::String
    cross_machine_byte_determinism_claimed::Bool
    candidates::Vector{CandidateInput}
    blocked_variants::Dict{String, NamedTuple{(:blocker, :basis), Tuple{String, String}}}
    origin_admissible::Bool
    accuracy_selection_eligible::Bool
    runtime_selection_eligible::Bool
    runtime_parallel::Bool
end

struct IdentityRecord
    schema_version::String
    candidate_id::String
    candidate_semantic_sha256::String
    seed::Int
    requested_horizon::Int
    realized_period::Int
    realized_date::Date
    identity_id::String
    layer::String
    status::String
    diagnostic_value::Union{Missing, Float64}
    absolute_diagnostic_value::Union{Missing, Float64}
    tolerance::Union{Missing, Float64}
    blocker::String
    basis::String
    origin_admissible::Bool
    promotion_eligible::Bool
    accuracy_selection_eligible::Bool
    runtime_selection_eligible::Bool
end

struct TransitionHarnessReport
    schema_version::String
    contract_path::String
    contract_sha256::String
    classification::String
    information_track::String
    promotion_status::String
    horizons::Vector{Int}
    seeds::Vector{Int}
    candidate_ids::Vector{String}
    record_semantic_sha256::String
    records::Vector{IdentityRecord}
    runtime_source_tree_sha256::String
    runtime_source_tree_file_count::Int
    julia_version::String
    julia_thread_count::Int
    blas_thread_count::Int
    blas_vendor::String
    origin_admissible::Bool
    promotion_eligible::Bool
    accuracy_selection_eligible::Bool
    runtime_selection_eligible::Bool
end

struct ScenarioTrace
    records::Vector{IdentityRecord}
    state_hashes::Vector{String}
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
file_sha256(path) = sha256_hex(read(path))

function fail(location::AbstractString, message::AbstractString)
    throw(ArgumentError("$location: $message"))
end

function exact_keys(value, expected, location)
    value isa AbstractDict || fail(location, "must be a table")
    actual = Set(String.(keys(value)))
    wanted = Set(String.(expected))
    actual == wanted ||
        fail(
        location,
        "keys differ; missing=$(sort!(collect(setdiff(wanted, actual)))) " *
            "extra=$(sort!(collect(setdiff(actual, wanted))))",
    )
    return value
end

function nonempty_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    isempty(strip(text)) && fail(location, "must be nonempty")
    return text
end

function sha256_string(value, location)
    text = nonempty_string(value, location)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail(location, "must be a lowercase SHA-256")
    return text
end

function false_boolean(value, location)
    value === false || fail(location, "must remain false")
    return false
end

function safe_path(repo_root::AbstractString, relative_path, location)
    text = nonempty_string(relative_path, location)
    isabspath(text) && fail(location, "must be repository-relative")
    root = dirname(
        joinpath(
            abspath(normpath(String(repo_root))),
            ".accounting-transition-root",
        ),
    )
    resolved = normpath(joinpath(root, text))
    prefix = root * Base.Filesystem.path_separator
    (resolved == root || startswith(resolved, prefix)) ||
        fail(location, "escapes the repository root")
    return resolved
end

function verified_file(repo_root, relative_path, expected_sha256, location)
    path = safe_path(repo_root, relative_path, "$location.path")
    isfile(path) || fail(location, "file is missing")
    expected = sha256_string(expected_sha256, "$location.sha256")
    actual = file_sha256(path)
    actual == expected ||
        fail(location, "SHA-256 mismatch; expected $expected, got $actual")
    return path
end

function source_tree_digest(directory::AbstractString)
    root = abspath(normpath(String(directory)))
    isdir(root) || fail("runtime_source_tree", "directory is missing: $root")
    paths = String[]
    for (walk_root, _, files) in walkdir(root; follow_symlinks = false)
        for filename in files
            endswith(filename, ".jl") || continue
            path = joinpath(walk_root, filename)
            islink(path) &&
                fail("runtime_source_tree", "Julia source cannot be a symlink: $path")
            push!(paths, path)
        end
    end
    isempty(paths) && fail("runtime_source_tree", "contains no Julia sources")
    sort!(paths; by = path -> replace(relpath(path, root), '\\' => '/'))
    io = IOBuffer()
    relative_paths = String[]
    for path in paths
        relative_path = replace(relpath(path, root), '\\' => '/')
        push!(relative_paths, relative_path)
        write(io, codeunits(relative_path))
        write(io, UInt8(0))
        write(io, codeunits(file_sha256(path)))
        write(io, UInt8('\n'))
    end
    return (
        sha256 = sha256_hex(take!(io)),
        file_count = length(paths),
        relative_paths,
        algorithm = SOURCE_TREE_DIGEST_ALGORITHM,
    )
end

function exact_integer_vector(value, expected, location)
    value isa AbstractVector || fail(location, "must be an array")
    all(entry -> entry isa Integer && !(entry isa Bool), value) ||
        fail(location, "must contain only integers")
    result = Int.(value)
    result == expected ||
        fail(location, "must equal $(repr(expected)) in this exact order")
    return result
end

function finite_nonnegative(value, location; positive = false)
    value isa Real && !(value isa Bool) ||
        fail(location, "must be numeric")
    result = Float64(value)
    isfinite(result) || fail(location, "must be finite")
    valid = positive ? result > 0 : result >= 0
    valid ||
        fail(location, positive ? "must be positive" : "must be nonnegative")
    return result
end

function parse_blocked_variants(raw)
    raw isa AbstractVector ||
        fail("contract.blocked_variant", "must be an array of tables")
    parsed = Dict{String, NamedTuple{(:blocker, :basis), Tuple{String, String}}}()
    for (index, row) in enumerate(raw)
        location = "contract.blocked_variant[$index]"
        exact_keys(row, ["identity_id", "blocker", "basis"], location)
        identity_id = nonempty_string(row["identity_id"], "$location.identity_id")
        haskey(parsed, identity_id) &&
            fail(location, "duplicates identity_id $identity_id")
        parsed[identity_id] = (
            blocker = nonempty_string(row["blocker"], "$location.blocker"),
            basis = nonempty_string(row["basis"], "$location.basis"),
        )
    end
    Set(keys(parsed)) == Set(keys(EXPECTED_BLOCKERS)) ||
        fail(
        "contract.blocked_variant",
        "identity set differs from the frozen blocked variants",
    )
    for (identity_id, blocker) in EXPECTED_BLOCKERS
        parsed[identity_id].blocker == blocker ||
            fail(
            "contract.blocked_variant.$identity_id",
            "blocker must remain $blocker",
        )
    end
    return parsed
end

function parse_candidates(manifest, repo_root, expected_ids)
    exact_keys(
        manifest,
        [
            "schema_version",
            "build_contract_path",
            "build_contract_sha256",
            "builder_path",
            "builder_sha256",
            "classification",
            "promotion_status",
            "forecast_origin_admissible",
            "information_track",
            "julia_project_path",
            "julia_project_sha256",
            "julia_manifest_path",
            "julia_manifest_sha256",
            "execution_envelope_module_path",
            "execution_envelope_module_sha256",
            "supply_make_reader_path",
            "supply_make_reader_sha256",
            "t10105_reader_path",
            "t10105_reader_sha256",
            "execution_envelope",
            "byte_reproducibility_scope",
            "cross_machine_byte_determinism_claimed",
            "runtime_source_tree_path",
            "runtime_source_tree_digest_algorithm",
            "runtime_source_tree_file_count",
            "runtime_source_tree_sha256",
            "legacy_artifacts_unchanged",
            "candidate_count",
            "candidate",
        ],
        "candidate_manifest",
    )
    manifest["schema_version"] ==
        USOpeningAccountingCandidate.MANIFEST_SCHEMA ||
        fail("candidate_manifest.schema_version", "is unsupported")
    manifest["classification"] == "REVISED_CURRENT_VINTAGE_DIAGNOSTIC" ||
        fail("candidate_manifest.classification", "is not diagnostic")
    manifest["promotion_status"] == SAFE_PROMOTION_STATUS ||
        fail("candidate_manifest.promotion_status", "is unsafe")
    false_boolean(
        manifest["forecast_origin_admissible"],
        "candidate_manifest.forecast_origin_admissible",
    )
    manifest["information_track"] == SAFE_CLASSIFICATION ||
        fail("candidate_manifest.information_track", "is not revised-data")
    manifest["legacy_artifacts_unchanged"] === true ||
        fail("candidate_manifest.legacy_artifacts_unchanged", "must be true")
    manifest["byte_reproducibility_scope"] ==
        USOpeningAccountingCandidate.USJuliaExecutionEnvelope.BYTE_REPRODUCIBILITY_SCOPE ||
        fail(
        "candidate_manifest.byte_reproducibility_scope",
        "differs from the frozen scope",
    )
    false_boolean(
        manifest["cross_machine_byte_determinism_claimed"],
        "candidate_manifest.cross_machine_byte_determinism_claimed",
    )
    USOpeningAccountingCandidate.USJuliaExecutionEnvelope.validate_execution_envelope_table(
        manifest["execution_envelope"],
        "candidate_manifest.execution_envelope",
    )
    rows = manifest["candidate"]
    rows isa AbstractVector ||
        fail("candidate_manifest.candidate", "must be an array")
    Int(manifest["candidate_count"]) == length(rows) ||
        fail("candidate_manifest.candidate_count", "does not match rows")

    candidates = CandidateInput[]
    for (index, row) in enumerate(rows)
        location = "candidate_manifest.candidate[$index]"
        required = [
            "artifact_path",
            "artifact_sha256",
            "candidate_id",
            "classification",
            "diagnostic_seed",
            "inventory_stock",
            "kind",
            "latent_state_reconciliation",
            "maximum_absolute_component_gap",
            "model_implied_expenditure_residual",
            "model_implied_values",
            "model_minus_source",
            "observed_expenditure_residual",
            "opening_macro_control_identity",
            "origin_admissible",
            "origin_period",
            "overall_accounting_promotion",
            "promotion_status",
            "semantic_sha256",
            "source_expenditure_residual",
            "source_values",
            "structural_supply_use",
            "unreconciled_commodity_gap_annual_sum",
        ]
        exact_keys(row, required, location)
        candidate_id =
            nonempty_string(row["candidate_id"], "$location.candidate_id")
        row["classification"] == "REVISED_CURRENT_VINTAGE_DIAGNOSTIC" ||
            fail("$location.classification", "is not diagnostic")
        row["promotion_status"] == SAFE_PROMOTION_STATUS ||
            fail("$location.promotion_status", "is unsafe")
        false_boolean(row["origin_admissible"], "$location.origin_admissible")
        row["opening_macro_control_identity"] ==
            "PASS_AT_SOURCE_ROUNDING" ||
            fail(
            "$location.opening_macro_control_identity",
            "must pass only at source rounding",
        )
        row["latent_state_reconciliation"] == "FAIL" ||
            fail("$location.latent_state_reconciliation", "must remain failed")
        row["structural_supply_use"] == "FAIL" ||
            fail("$location.structural_supply_use", "must remain failed")
        row["overall_accounting_promotion"] == "FAIL" ||
            fail("$location.overall_accounting_promotion", "must remain failed")
        artifact_path =
            nonempty_string(row["artifact_path"], "$location.artifact_path")
        artifact_sha256 =
            sha256_string(row["artifact_sha256"], "$location.artifact_sha256")
        verified_file(
            repo_root,
            artifact_path,
            artifact_sha256,
            "$location.artifact",
        )
        push!(
            candidates,
            CandidateInput(
                candidate_id,
                Date(nonempty_string(row["origin_period"], "$location.origin_period")),
                artifact_path,
                artifact_sha256,
                sha256_string(
                    row["semantic_sha256"],
                    "$location.semantic_sha256",
                ),
                Float64(row["observed_expenditure_residual"]),
                Float64(row["model_implied_expenditure_residual"]),
            ),
        )
    end
    ids = sort!(getfield.(candidates, :candidate_id))
    ids == sort!(copy(expected_ids)) ||
        fail("candidate_manifest.candidate", "candidate IDs differ")
    length(unique(ids)) == length(ids) ||
        fail("candidate_manifest.candidate", "candidate IDs are not unique")
    sort!(candidates; by = candidate -> candidate.candidate_id)
    return candidates
end

function load_contract(
        path::AbstractString = DEFAULT_CONTRACT_PATH;
        repo_root::AbstractString = REPO_ROOT,
    )
    isfile(path) || fail("contract", "file is missing: $(abspath(path))")
    raw = TOML.parsefile(path)
    exact_keys(
        raw,
        [
            "schema_version",
            "classification",
            "information_track",
            "promotion_status",
            "origin_admissible",
            "accuracy_selection_eligible",
            "runtime_selection_eligible",
            "runtime_parallel",
            "horizons",
            "seeds",
            "model_numeric_tolerance",
            "domain_tolerance",
            "candidate_manifest_path",
            "candidate_manifest_sha256",
            "candidate_builder_path",
            "candidate_builder_sha256",
            "candidate_execution_envelope_dependency_path",
            "candidate_execution_envelope_dependency_sha256",
            "candidate_supply_make_dependency_path",
            "candidate_supply_make_dependency_sha256",
            "candidate_t10105_dependency_path",
            "candidate_t10105_dependency_sha256",
            "harness_module_path",
            "harness_module_sha256",
            "julia_project_path",
            "julia_project_sha256",
            "julia_manifest_path",
            "julia_manifest_sha256",
            "runtime_source_tree_path",
            "runtime_source_tree_digest_algorithm",
            "runtime_source_tree_file_count",
            "runtime_source_tree_sha256",
            "execution_envelope",
            "byte_reproducibility_scope",
            "cross_machine_byte_determinism_claimed",
            "candidate_ids",
            "blocked_variant",
        ],
        "contract",
    )
    raw["schema_version"] == CONTRACT_SCHEMA ||
        fail("contract.schema_version", "is unsupported")
    raw["classification"] == SAFE_CLASSIFICATION ||
        fail("contract.classification", "must remain revised-data diagnostic")
    raw["information_track"] == SAFE_CLASSIFICATION ||
        fail("contract.information_track", "must remain revised-data diagnostic")
    raw["promotion_status"] == SAFE_PROMOTION_STATUS ||
        fail("contract.promotion_status", "is unsafe")
    origin_admissible =
        false_boolean(raw["origin_admissible"], "contract.origin_admissible")
    accuracy_selection_eligible = false_boolean(
        raw["accuracy_selection_eligible"],
        "contract.accuracy_selection_eligible",
    )
    runtime_selection_eligible = false_boolean(
        raw["runtime_selection_eligible"],
        "contract.runtime_selection_eligible",
    )
    runtime_parallel =
        false_boolean(raw["runtime_parallel"], "contract.runtime_parallel")
    horizons =
        exact_integer_vector(raw["horizons"], EXPECTED_HORIZONS, "contract.horizons")
    seeds = exact_integer_vector(raw["seeds"], EXPECTED_SEEDS, "contract.seeds")
    candidate_ids = String.(
        nonempty_string(value, "contract.candidate_ids[$index]")
            for (index, value) in enumerate(raw["candidate_ids"])
    )
    candidate_ids == EXPECTED_CANDIDATE_IDS ||
        fail(
        "contract.candidate_ids",
        "must equal $(repr(EXPECTED_CANDIDATE_IDS)) in this exact order",
    )
    model_numeric_tolerance = finite_nonnegative(
        raw["model_numeric_tolerance"],
        "contract.model_numeric_tolerance";
        positive = true,
    )
    model_numeric_tolerance == 1.0e-6 ||
        fail("contract.model_numeric_tolerance", "must remain 1.0e-6")
    domain_tolerance = finite_nonnegative(
        raw["domain_tolerance"],
        "contract.domain_tolerance";
        positive = true,
    )
    domain_tolerance == 1.0e-10 ||
        fail("contract.domain_tolerance", "must remain 1.0e-10")

    candidate_manifest_path = nonempty_string(
        raw["candidate_manifest_path"],
        "contract.candidate_manifest_path",
    )
    candidate_manifest_sha256 = sha256_string(
        raw["candidate_manifest_sha256"],
        "contract.candidate_manifest_sha256",
    )
    manifest_path = verified_file(
        repo_root,
        candidate_manifest_path,
        candidate_manifest_sha256,
        "contract.candidate_manifest",
    )
    candidate_builder_path = nonempty_string(
        raw["candidate_builder_path"],
        "contract.candidate_builder_path",
    )
    candidate_builder_sha256 = sha256_string(
        raw["candidate_builder_sha256"],
        "contract.candidate_builder_sha256",
    )
    verified_file(
        repo_root,
        candidate_builder_path,
        candidate_builder_sha256,
        "contract.candidate_builder",
    )
    candidate_execution_envelope_dependency_path = nonempty_string(
        raw["candidate_execution_envelope_dependency_path"],
        "contract.candidate_execution_envelope_dependency_path",
    )
    candidate_execution_envelope_dependency_sha256 = sha256_string(
        raw["candidate_execution_envelope_dependency_sha256"],
        "contract.candidate_execution_envelope_dependency_sha256",
    )
    verified_file(
        repo_root,
        candidate_execution_envelope_dependency_path,
        candidate_execution_envelope_dependency_sha256,
        "contract.candidate_execution_envelope_dependency",
    )
    candidate_supply_make_dependency_path = nonempty_string(
        raw["candidate_supply_make_dependency_path"],
        "contract.candidate_supply_make_dependency_path",
    )
    candidate_supply_make_dependency_sha256 = sha256_string(
        raw["candidate_supply_make_dependency_sha256"],
        "contract.candidate_supply_make_dependency_sha256",
    )
    verified_file(
        repo_root,
        candidate_supply_make_dependency_path,
        candidate_supply_make_dependency_sha256,
        "contract.candidate_supply_make_dependency",
    )
    candidate_t10105_dependency_path = nonempty_string(
        raw["candidate_t10105_dependency_path"],
        "contract.candidate_t10105_dependency_path",
    )
    candidate_t10105_dependency_sha256 = sha256_string(
        raw["candidate_t10105_dependency_sha256"],
        "contract.candidate_t10105_dependency_sha256",
    )
    verified_file(
        repo_root,
        candidate_t10105_dependency_path,
        candidate_t10105_dependency_sha256,
        "contract.candidate_t10105_dependency",
    )
    harness_module_path = nonempty_string(
        raw["harness_module_path"],
        "contract.harness_module_path",
    )
    harness_module_sha256 = sha256_string(
        raw["harness_module_sha256"],
        "contract.harness_module_sha256",
    )
    verified_file(
        repo_root,
        harness_module_path,
        harness_module_sha256,
        "contract.harness_module",
    )
    julia_project_path =
        nonempty_string(raw["julia_project_path"], "contract.julia_project_path")
    julia_project_sha256 = sha256_string(
        raw["julia_project_sha256"],
        "contract.julia_project_sha256",
    )
    verified_file(
        repo_root,
        julia_project_path,
        julia_project_sha256,
        "contract.julia_project",
    )
    julia_manifest_path = nonempty_string(
        raw["julia_manifest_path"],
        "contract.julia_manifest_path",
    )
    julia_manifest_sha256 = sha256_string(
        raw["julia_manifest_sha256"],
        "contract.julia_manifest_sha256",
    )
    verified_file(
        repo_root,
        julia_manifest_path,
        julia_manifest_sha256,
        "contract.julia_manifest",
    )
    runtime_source_tree_path = nonempty_string(
        raw["runtime_source_tree_path"],
        "contract.runtime_source_tree_path",
    )
    runtime_source_tree_digest_algorithm = nonempty_string(
        raw["runtime_source_tree_digest_algorithm"],
        "contract.runtime_source_tree_digest_algorithm",
    )
    runtime_source_tree_digest_algorithm == SOURCE_TREE_DIGEST_ALGORITHM ||
        fail(
        "contract.runtime_source_tree_digest_algorithm",
        "differs from the frozen algorithm",
    )
    raw_source_tree_file_count = raw["runtime_source_tree_file_count"]
    raw_source_tree_file_count isa Integer &&
        !(raw_source_tree_file_count isa Bool) ||
        fail("contract.runtime_source_tree_file_count", "must be an integer")
    runtime_source_tree_file_count = Int(raw_source_tree_file_count)
    runtime_source_tree_file_count > 0 ||
        fail("contract.runtime_source_tree_file_count", "must be positive")
    runtime_source_tree_sha256 = sha256_string(
        raw["runtime_source_tree_sha256"],
        "contract.runtime_source_tree_sha256",
    )
    runtime_source_tree_directory = safe_path(
        repo_root,
        runtime_source_tree_path,
        "contract.runtime_source_tree_path",
    )
    digest = source_tree_digest(runtime_source_tree_directory)
    digest.file_count == runtime_source_tree_file_count ||
        fail(
        "contract.runtime_source_tree_file_count",
        "expected $runtime_source_tree_file_count, got $(digest.file_count)",
    )
    digest.sha256 == runtime_source_tree_sha256 ||
        fail(
        "contract.runtime_source_tree_sha256",
        "expected $runtime_source_tree_sha256, got $(digest.sha256)",
    )
    execution_envelope =
        USOpeningAccountingCandidate.USJuliaExecutionEnvelope.validate_execution_envelope_table(
        raw["execution_envelope"],
        "contract.execution_envelope",
    )
    byte_reproducibility_scope = nonempty_string(
        raw["byte_reproducibility_scope"],
        "contract.byte_reproducibility_scope",
    )
    byte_reproducibility_scope ==
        USOpeningAccountingCandidate.USJuliaExecutionEnvelope.BYTE_REPRODUCIBILITY_SCOPE ||
        fail(
        "contract.byte_reproducibility_scope",
        "differs from the frozen scope",
    )
    cross_machine_byte_determinism_claimed = false_boolean(
        raw["cross_machine_byte_determinism_claimed"],
        "contract.cross_machine_byte_determinism_claimed",
    )
    blocked_variants = parse_blocked_variants(raw["blocked_variant"])
    candidate_manifest = TOML.parsefile(manifest_path)
    candidates =
        parse_candidates(candidate_manifest, repo_root, candidate_ids)

    candidate_manifest["builder_path"] == candidate_builder_path ||
        fail("candidate_manifest.builder_path", "differs from harness contract")
    candidate_manifest["builder_sha256"] == candidate_builder_sha256 ||
        fail("candidate_manifest.builder_sha256", "differs from harness contract")
    candidate_manifest["execution_envelope_module_path"] ==
        candidate_execution_envelope_dependency_path ||
        fail(
        "candidate_manifest.execution_envelope_module_path",
        "differs from harness contract",
    )
    candidate_manifest["execution_envelope_module_sha256"] ==
        candidate_execution_envelope_dependency_sha256 ||
        fail(
        "candidate_manifest.execution_envelope_module_sha256",
        "differs from harness contract",
    )
    candidate_manifest["supply_make_reader_path"] ==
        candidate_supply_make_dependency_path ||
        fail(
        "candidate_manifest.supply_make_reader_path",
        "differs from harness contract",
    )
    candidate_manifest["supply_make_reader_sha256"] ==
        candidate_supply_make_dependency_sha256 ||
        fail(
        "candidate_manifest.supply_make_reader_sha256",
        "differs from harness contract",
    )
    candidate_manifest["t10105_reader_path"] ==
        candidate_t10105_dependency_path ||
        fail(
        "candidate_manifest.t10105_reader_path",
        "differs from harness contract",
    )
    candidate_manifest["t10105_reader_sha256"] ==
        candidate_t10105_dependency_sha256 ||
        fail(
        "candidate_manifest.t10105_reader_sha256",
        "differs from harness contract",
    )
    candidate_manifest["julia_project_path"] == julia_project_path ||
        fail("candidate_manifest.julia_project_path", "differs from harness contract")
    candidate_manifest["julia_project_sha256"] == julia_project_sha256 ||
        fail(
        "candidate_manifest.julia_project_sha256",
        "differs from harness contract",
    )
    candidate_manifest["julia_manifest_path"] == julia_manifest_path ||
        fail(
        "candidate_manifest.julia_manifest_path",
        "differs from harness contract",
    )
    candidate_manifest["julia_manifest_sha256"] == julia_manifest_sha256 ||
        fail(
        "candidate_manifest.julia_manifest_sha256",
        "differs from harness contract",
    )
    candidate_manifest["execution_envelope"] == execution_envelope ||
        fail(
        "candidate_manifest.execution_envelope",
        "differs from harness contract",
    )
    candidate_manifest["byte_reproducibility_scope"] ==
        byte_reproducibility_scope ||
        fail(
        "candidate_manifest.byte_reproducibility_scope",
        "differs from harness contract",
    )
    candidate_manifest["cross_machine_byte_determinism_claimed"] ===
        cross_machine_byte_determinism_claimed ||
        fail(
        "candidate_manifest.cross_machine_byte_determinism_claimed",
        "differs from harness contract",
    )
    candidate_manifest["runtime_source_tree_path"] ==
        runtime_source_tree_path ||
        fail(
        "candidate_manifest.runtime_source_tree_path",
        "differs from harness contract",
    )
    candidate_manifest["runtime_source_tree_digest_algorithm"] ==
        runtime_source_tree_digest_algorithm ||
        fail(
        "candidate_manifest.runtime_source_tree_digest_algorithm",
        "differs from harness contract",
    )
    Int(candidate_manifest["runtime_source_tree_file_count"]) ==
        runtime_source_tree_file_count ||
        fail(
        "candidate_manifest.runtime_source_tree_file_count",
        "differs from harness contract",
    )
    candidate_manifest["runtime_source_tree_sha256"] ==
        runtime_source_tree_sha256 ||
        fail(
        "candidate_manifest.runtime_source_tree_sha256",
        "differs from harness contract",
    )

    return HarnessContract(
        abspath(path),
        file_sha256(path),
        dirname(
            joinpath(
                abspath(normpath(String(repo_root))),
                ".accounting-transition-root",
            ),
        ),
        String(raw["classification"]),
        String(raw["information_track"]),
        String(raw["promotion_status"]),
        horizons,
        seeds,
        model_numeric_tolerance,
        domain_tolerance,
        candidate_manifest_path,
        candidate_manifest_sha256,
        candidate_builder_path,
        candidate_builder_sha256,
        candidate_execution_envelope_dependency_path,
        candidate_execution_envelope_dependency_sha256,
        candidate_supply_make_dependency_path,
        candidate_supply_make_dependency_sha256,
        candidate_t10105_dependency_path,
        candidate_t10105_dependency_sha256,
        harness_module_path,
        harness_module_sha256,
        julia_project_path,
        julia_project_sha256,
        julia_manifest_path,
        julia_manifest_sha256,
        runtime_source_tree_path,
        runtime_source_tree_digest_algorithm,
        runtime_source_tree_file_count,
        runtime_source_tree_sha256,
        execution_envelope,
        byte_reproducibility_scope,
        cross_machine_byte_determinism_claimed,
        candidates,
        blocked_variants,
        origin_admissible,
        accuracy_selection_eligible,
        runtime_selection_eligible,
        runtime_parallel,
    )
end

function load_candidate(contract::HarnessContract, input::CandidateInput)
    path = verified_file(
        contract.repo_root,
        input.artifact_path,
        input.artifact_sha256,
        "candidate.$(input.candidate_id).artifact",
    )
    payload = JLD2.load(path)
    Set(keys(payload)) == Set(["parameters", "initial_conditions", "metadata"]) ||
        fail("candidate.$(input.candidate_id)", "artifact keys differ")
    result = (
        parameters = payload["parameters"],
        initial_conditions = payload["initial_conditions"],
        metadata = payload["metadata"],
        semantic_sha256 = payload["metadata"]["semantic_sha256"],
    )
    USOpeningAccountingCandidate.validate_candidate(result)
    result.metadata["candidate_id"] == input.candidate_id ||
        fail("candidate.$(input.candidate_id)", "metadata ID differs")
    result.metadata["origin_period"] == string(input.origin_period) ||
        fail("candidate.$(input.candidate_id)", "origin period differs")
    result.semantic_sha256 == input.semantic_sha256 ||
        fail("candidate.$(input.candidate_id)", "semantic SHA-256 differs")
    reconciliation = result.metadata["opening_macro_reconciliation"]
    Float64(reconciliation["observed_expenditure_residual"]) ==
        input.observed_expenditure_residual ||
        fail("candidate.$(input.candidate_id)", "observed residual differs")
    Float64(reconciliation["model_implied_expenditure_residual"]) ==
        input.latent_expenditure_residual ||
        fail("candidate.$(input.candidate_id)", "latent residual differs")
    return result
end

function identity_record(
        input::CandidateInput,
        seed::Int,
        horizon::Int,
        realized_period::Int,
        identity_id::AbstractString,
        layer::AbstractString,
        status::AbstractString;
        value = missing,
        tolerance = missing,
        blocker = "",
        basis,
    )
    diagnostic_value =
        ismissing(value) ? missing : Float64(value)
    absolute_value =
        ismissing(diagnostic_value) ? missing : abs(diagnostic_value)
    numeric_tolerance =
        ismissing(tolerance) ? missing : Float64(tolerance)
    realized_date =
        lastdayofquarter(input.origin_period + Month(3 * realized_period))
    return IdentityRecord(
        RECORD_SCHEMA,
        input.candidate_id,
        input.semantic_sha256,
        seed,
        horizon,
        realized_period,
        realized_date,
        String(identity_id),
        String(layer),
        String(status),
        diagnostic_value,
        absolute_value,
        numeric_tolerance,
        String(blocker),
        String(basis),
        false,
        false,
        false,
        false,
    )
end

function residual_status(value, tolerance; source_rounding = false)
    if !isfinite(value)
        return "FAIL"
    elseif abs(value) <= tolerance
        return source_rounding ? "PASS_AT_SOURCE_ROUNDING" : "PASS"
    end
    return "FAIL"
end

function violation_status(violation)
    return isfinite(violation) && violation <= 0 ? "PASS" : "FAIL"
end

function canonical_state_value(value)
    if value isa Base.RefValue
        return canonical_state_value(value[])
    elseif value isa AbstractDict
        return Dict{String, Any}(
            string(key) => canonical_state_value(entry)
                for (key, entry) in pairs(value)
        )
    elseif value isa AbstractArray
        return map(canonical_state_value, value)
    elseif value isa Number || value isa AbstractString ||
            value isa Symbol || value isa Date || value isa DateTime ||
            value === nothing
        return deepcopy(value)
    end
    return fail("harness_determinism", "unsupported state type $(typeof(value))")
end

function object_payload(object)
    return Dict{String, Any}(
        String(name) => canonical_state_value(getfield(object, name))
            for name in fieldnames(typeof(object))
    )
end

function state_hash(model)
    fieldnames(typeof(model)) == AGENT_STATE_FIELDS ||
        fail(
        "harness_determinism",
        "model field coverage changed; expected $(repr(AGENT_STATE_FIELDS)), got $(repr(fieldnames(typeof(model))))",
    )
    payload = Dict{String, Any}(
        String(name) => object_payload(getproperty(model, name))
            for name in AGENT_STATE_FIELDS
    )
    return USOpeningAccountingCandidate.semantic_sha256(payload)
end

function numeric_values!(destination::Vector{Float64}, value)
    if value isa Bool
        push!(destination, value ? 1.0 : 0.0)
    elseif value isa Real
        push!(destination, Float64(value))
    elseif value isa Base.RefValue
        numeric_values!(destination, value[])
    elseif value isa AbstractDict
        for entry in values(value)
            numeric_values!(destination, entry)
        end
    elseif value isa AbstractArray
        for entry in value
            numeric_values!(destination, entry)
        end
    else
        fail("accounting_state_finite", "unsupported numeric state type $(typeof(value))")
    end
    return destination
end

function latest_data_values(model)
    data = model.data
    period_count = length(data.collection_time)
    values = Float64[]
    for name in fieldnames(typeof(data))
        series = getfield(data, name)
        length(series) == period_count ||
            fail("tracked_data_finite.$name", "period count differs")
        numeric_values!(values, series[end])
    end
    return values
end

function accounting_state_values(model)
    values = Float64[]
    for object_name in AGENT_STATE_FIELDS[1:(end - 1)]
        object = getproperty(model, object_name)
        for field_name in fieldnames(typeof(object))
            numeric_values!(values, getfield(object, field_name))
        end
    end
    return values
end

function price_values(model, realized_period)
    values = Float64[]
    fields = realized_period == 0 ? OPENING_PRICE_FIELDS : PRICE_FIELDS
    for (object_name, field_name) in fields
        object = getproperty(model, object_name)
        numeric_values!(values, getproperty(object, field_name))
    end
    return values
end

function maximum_absolute(values)
    isempty(values) && fail("identity", "residual vector is empty")
    return maximum(abs, values)
end

function append_blocked_records!(
        records,
        contract,
        input,
        seed,
        horizon,
        realized_period,
    )
    for identity_id in sort!(collect(keys(contract.blocked_variants)))
        variant = contract.blocked_variants[identity_id]
        push!(
            records,
            identity_record(
                input,
                seed,
                horizon,
                realized_period,
                identity_id,
                "blocked_variant",
                "NOT_RUN_BLOCKED";
                blocker = variant.blocker,
                basis = variant.basis,
            ),
        )
    end
    return records
end

function append_period_records!(
        records,
        contract,
        input,
        model,
        seed,
        horizon,
        realized_period;
        previous_final_inventory = nothing,
        previous_intermediate_inventory = nothing,
    )
    tolerance = contract.model_numeric_tolerance
    residuals = Bit.get_accounting_residuals(model.data)
    index = realized_period + 1
    index == length(model.data.collection_time) ||
        fail("period", "data index differs from realized period")

    if realized_period == 0
        observed = residuals.gdp_and_expenditure[index]
        push!(
            records,
            identity_record(
                input,
                seed,
                horizon,
                realized_period,
                "opening_observation_nominal_expenditure",
                "opening_observation",
                residual_status(observed, 1.0; source_rounding = true);
                value = observed,
                tolerance = 1.0,
                basis = "Observed opening GDP less PCE, government consumption and investment, gross private domestic investment, and exports, plus imports.",
            ),
        )
        implied = Bit.model_implied_opening_macro(model)
        latent = implied.expenditure_residual
        latent_status =
            isfinite(latent) && abs(latent) > tolerance ?
            "FAIL_EXPECTED_LATENT_WEDGE" : "FAIL"
        push!(
            records,
            identity_record(
                input,
                seed,
                horizon,
                realized_period,
                "opening_latent_nominal_expenditure",
                "latent_opening_state",
                latent_status;
                value = latent,
                tolerance,
                basis = "Agent-state-implied opening GDP expenditure residual, kept separate from the source-anchored observation row.",
            ),
        )
    else
        nominal = residuals.gdp_and_expenditure[index]
        push!(
            records,
            identity_record(
                input,
                seed,
                horizon,
                realized_period,
                "nominal_expenditure_transition",
                "simulated_transition",
                residual_status(nominal, tolerance);
                value = nominal,
                tolerance,
                basis = "Simulated nominal GDP less household and government consumption, capital formation, and exports, plus imports.",
            ),
        )
    end

    income = residuals.income_and_production[index]
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "nominal_income_production",
            "model_accounting_series",
            residual_status(income, tolerance);
            value = income,
            tolerance,
            basis = "Nominal GVA less compensation of employees, operating surplus, and model-implied taxes on production.",
        ),
    )
    real_expenditure = residuals.gdp_and_expenditure_real[index]
    real_source_rounding = realized_period == 0
    real_tolerance = real_source_rounding ? 1.0 : tolerance
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "real_expenditure",
            real_source_rounding ?
                "opening_derived_normalized_prices" : "simulated_transition",
            residual_status(
                real_expenditure,
                real_tolerance;
                source_rounding = real_source_rounding,
            );
            value = real_expenditure,
            tolerance = real_tolerance,
            basis = "Real GDP less real household and government consumption, capital formation, and exports, plus imports; the opening row is derived from nominal controls under normalized prices and is not an independent real observation.",
        ),
    )

    central_bank, commercial_bank = Bit.get_accounting_identity_banks(model)
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "central_bank_balance_sheet",
            "model_balance_sheet",
            residual_status(central_bank, tolerance);
            value = central_bank,
            tolerance,
            basis = "Central-bank equity plus rest-of-world deposits less government loans plus the commercial-bank balancing deposit.",
        ),
    )
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "commercial_bank_balance_sheet",
            "model_balance_sheet",
            residual_status(commercial_bank, tolerance);
            value = commercial_bank,
            tolerance,
            basis = "Firm deposits plus household deposits and bank equity less firm loans and the bank balancing deposit.",
        ),
    )

    data_values = latest_data_values(model)
    nonfinite_data = count(!isfinite, data_values)
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "tracked_data_finite",
            "finite_domain",
            nonfinite_data == 0 ? "PASS" : "FAIL";
            value = nonfinite_data,
            tolerance = 0.0,
            basis = "Count of nonfinite values in every tracked Data field at this realized period.",
        ),
    )
    state_values = accounting_state_values(model)
    nonfinite_state = count(!isfinite, state_values)
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "accounting_state_finite",
            "finite_domain",
            nonfinite_state == 0 ? "PASS" : "FAIL";
            value = nonfinite_state,
            tolerance = 0.0,
            basis = "Count of nonfinite numeric values across workers, firms, bank, central bank, government, rest of world, aggregate state, and model properties.",
        ),
    )
    prices = price_values(model, realized_period)
    minimum_price = minimum(prices)
    price_violation =
        all(isfinite, prices) && minimum_price > 0 ? 0.0 : 1.0
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "positive_price_domain",
            "finite_domain",
            violation_status(price_violation);
            value = price_violation,
            tolerance = 0.0,
            basis = (
                realized_period == 0 ?
                    "Zero if every initialized opening producer and aggregate normalized-price index is finite and strictly positive; transaction-specific realized prices are first in-domain after transition 1." :
                    "Zero if every firm, import, export, government, and aggregate price index used by transition accounting is finite and strictly positive."
            ) * " Minimum checked price=$(repr(minimum_price)).",
        ),
    )

    minimum_final_inventory = minimum(model.firms.S_i)
    final_inventory_violation =
        max(0.0, -minimum_final_inventory - contract.domain_tolerance)
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "final_goods_inventory_stock_domain",
            "endogenous_model_inventory",
            violation_status(final_inventory_violation);
            value = final_inventory_violation,
            tolerance = 0.0,
            basis = "Maximum nonnegativity violation of endogenous firm final-goods stock S_i after a 1e-10 numeric allowance; this is not an observed inventory mapping.",
        ),
    )
    minimum_intermediate_inventory = minimum(model.firms.M_i)
    intermediate_inventory_violation =
        max(0.0, -minimum_intermediate_inventory - contract.domain_tolerance)
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "intermediate_goods_inventory_stock_domain",
            "endogenous_model_inventory",
            violation_status(intermediate_inventory_violation);
            value = intermediate_inventory_violation,
            tolerance = 0.0,
            basis = "Maximum nonnegativity violation of endogenous firm intermediate-goods stock M_i after a 1e-10 numeric allowance; this is not an observed inventory mapping.",
        ),
    )

    data = model.data
    nominal_inventory_residual =
        data.nominal_inventory_investment[index] -
        data.nominal_capitalformation[index] +
        data.nominal_fixed_capitalformation[index]
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "nominal_inventory_flow_decomposition",
            realized_period == 0 ?
                "opening_observation" : "simulated_transition",
            residual_status(nominal_inventory_residual, tolerance);
            value = nominal_inventory_residual,
            tolerance,
            basis = "Nominal inventory investment less total capital formation plus fixed capital formation.",
        ),
    )
    real_inventory_residual =
        data.real_inventory_investment[index] -
        data.real_capitalformation[index] +
        data.real_fixed_capitalformation[index]
    push!(
        records,
        identity_record(
            input,
            seed,
            horizon,
            realized_period,
            "real_inventory_flow_decomposition",
            realized_period == 0 ?
                "opening_derived_normalized_prices" : "simulated_transition",
            residual_status(real_inventory_residual, tolerance);
            value = real_inventory_residual,
            tolerance,
            basis = "Real inventory investment less total capital formation plus fixed capital formation.",
        ),
    )

    if realized_period > 0
        previous_final_inventory === nothing &&
            fail("final_goods_inventory_stock_flow", "previous stock is absent")
        previous_intermediate_inventory === nothing &&
            fail(
            "intermediate_goods_inventory_stock_flow",
            "previous stock is absent",
        )
        final_stock_residual = maximum_absolute(
            model.firms.S_i .-
                previous_final_inventory .-
                model.firms.DS_i,
        )
        push!(
            records,
            identity_record(
                input,
                seed,
                horizon,
                realized_period,
                "final_goods_inventory_stock_flow",
                "endogenous_model_inventory",
                residual_status(final_stock_residual, tolerance);
                value = final_stock_residual,
                tolerance,
                basis = "Maximum absolute firm-level residual of S_i(t)-S_i(t-1)-DS_i(t); firm cells are checked before aggregation.",
            ),
        )
        intermediate_stock_residual = maximum_absolute(
            model.firms.M_i .-
                previous_intermediate_inventory .+
                model.firms.Y_i ./ model.firms.beta_i .-
                model.firms.DM_i,
        )
        push!(
            records,
            identity_record(
                input,
                seed,
                horizon,
                realized_period,
                "intermediate_goods_inventory_stock_flow",
                "endogenous_model_inventory",
                residual_status(intermediate_stock_residual, tolerance);
                value = intermediate_stock_residual,
                tolerance,
                basis = "Maximum absolute firm-level residual of M_i(t)-M_i(t-1)+Y_i(t)/beta_i-DM_i(t); firm cells are checked before aggregation.",
            ),
        )
    end
    append_blocked_records!(
        records,
        contract,
        input,
        seed,
        horizon,
        realized_period,
    )
    return records
end

function simulate_trace(
        contract,
        input,
        candidate,
        seed,
        horizon;
        emit_records,
    )
    Random.seed!(seed)
    model = Bit.Model(
        deepcopy(candidate.parameters),
        deepcopy(candidate.initial_conditions),
    )
    records = IdentityRecord[]
    hashes = String[state_hash(model)]
    if emit_records
        append_period_records!(
            records,
            contract,
            input,
            model,
            seed,
            horizon,
            0,
        )
    end
    for realized_period in 1:horizon
        previous_final_inventory = copy(model.firms.S_i)
        previous_intermediate_inventory = copy(model.firms.M_i)
        Bit.step!(model; parallel = false)
        Bit.collect_data!(model)
        push!(hashes, state_hash(model))
        if emit_records
            append_period_records!(
                records,
                contract,
                input,
                model,
                seed,
                horizon,
                realized_period;
                previous_final_inventory,
                previous_intermediate_inventory,
            )
        end
    end
    return ScenarioTrace(records, hashes)
end

function append_determinism_records!(
        records,
        input,
        seed,
        horizon,
        primary,
        replay,
        longest,
    )
    length(primary.state_hashes) == horizon + 1 ||
        fail("same_seed_exact_replay", "primary trace length differs")
    length(replay.state_hashes) == horizon + 1 ||
        fail("same_seed_exact_replay", "replay trace length differs")
    length(longest.state_hashes) == last(EXPECTED_HORIZONS) + 1 ||
        fail("same_seed_cross_horizon_prefix", "longest trace length differs")
    for realized_period in 0:horizon
        replay_difference =
            primary.state_hashes[realized_period + 1] ==
            replay.state_hashes[realized_period + 1] ? 0.0 : 1.0
        push!(
            records,
            identity_record(
                input,
                seed,
                horizon,
                realized_period,
                "same_seed_exact_replay",
                "harness_determinism",
                violation_status(replay_difference);
                value = replay_difference,
                tolerance = 0.0,
                basis = "Exact semantic SHA-256 equality of the complete mutable agent state and collected-data prefix in an independent same-seed replay.",
            ),
        )
        prefix_difference =
            primary.state_hashes[realized_period + 1] ==
            longest.state_hashes[realized_period + 1] ? 0.0 : 1.0
        push!(
            records,
            identity_record(
                input,
                seed,
                horizon,
                realized_period,
                "same_seed_cross_horizon_prefix",
                "harness_determinism",
                violation_status(prefix_difference);
                value = prefix_difference,
                tolerance = 0.0,
                basis = "Exact semantic SHA-256 equality against the same-seed 12-quarter run at this realized period.",
            ),
        )
    end
    return records
end

function record_payload(record::IdentityRecord)
    return (
        schema_version = record.schema_version,
        candidate_id = record.candidate_id,
        candidate_semantic_sha256 = record.candidate_semantic_sha256,
        seed = record.seed,
        requested_horizon = record.requested_horizon,
        realized_period = record.realized_period,
        realized_date = record.realized_date,
        identity_id = record.identity_id,
        layer = record.layer,
        status = record.status,
        diagnostic_value =
            ismissing(record.diagnostic_value) ?
            nothing : record.diagnostic_value,
        absolute_diagnostic_value =
            ismissing(record.absolute_diagnostic_value) ?
            nothing : record.absolute_diagnostic_value,
        tolerance =
            ismissing(record.tolerance) ? nothing : record.tolerance,
        blocker = record.blocker,
        basis = record.basis,
        origin_admissible = record.origin_admissible,
        promotion_eligible = record.promotion_eligible,
        accuracy_selection_eligible =
            record.accuracy_selection_eligible,
        runtime_selection_eligible = record.runtime_selection_eligible,
    )
end

function record_semantic_sha256(records)
    payload = record_payload.(records)
    return USOpeningAccountingCandidate.semantic_sha256(payload)
end

function expected_identity_ids(realized_period)
    return union(
        COMMON_IDENTITY_IDS,
        realized_period == 0 ?
            OPENING_IDENTITY_IDS : TRANSITION_IDENTITY_IDS,
    )
end

function validate_record(record, contract)
    record.schema_version == RECORD_SCHEMA ||
        fail("record.schema_version", "is unsupported")
    false_boolean(record.origin_admissible, "record.origin_admissible")
    false_boolean(record.promotion_eligible, "record.promotion_eligible")
    false_boolean(
        record.accuracy_selection_eligible,
        "record.accuracy_selection_eligible",
    )
    false_boolean(
        record.runtime_selection_eligible,
        "record.runtime_selection_eligible",
    )
    record.requested_horizon in contract.horizons ||
        fail("record.requested_horizon", "is outside the contract")
    0 <= record.realized_period <= record.requested_horizon ||
        fail("record.realized_period", "is outside the requested horizon")
    record.seed in contract.seeds ||
        fail("record.seed", "is outside the contract")
    if haskey(EXPECTED_BLOCKERS, record.identity_id)
        record.status == "NOT_RUN_BLOCKED" ||
            fail("record.$(record.identity_id)", "must remain blocked")
        record.blocker == EXPECTED_BLOCKERS[record.identity_id] ||
            fail("record.$(record.identity_id)", "blocker differs")
        ismissing(record.diagnostic_value) ||
            fail("record.$(record.identity_id)", "must not invent a value")
        ismissing(record.absolute_diagnostic_value) ||
            fail("record.$(record.identity_id)", "must not invent an absolute value")
        ismissing(record.tolerance) ||
            fail("record.$(record.identity_id)", "must not invent a tolerance")
    else
        isempty(record.blocker) ||
            fail("record.$(record.identity_id)", "has an unexpected blocker")
        ismissing(record.diagnostic_value) &&
            fail("record.$(record.identity_id)", "is missing a diagnostic value")
        ismissing(record.absolute_diagnostic_value) &&
            fail(
            "record.$(record.identity_id)",
            "is missing an absolute diagnostic value",
        )
        ismissing(record.tolerance) &&
            fail("record.$(record.identity_id)", "is missing a tolerance")
        isfinite(record.diagnostic_value) ||
            fail("record.$(record.identity_id)", "value is nonfinite")
        record.absolute_diagnostic_value == abs(record.diagnostic_value) ||
            fail("record.$(record.identity_id)", "absolute value differs")
        isfinite(record.tolerance) && record.tolerance >= 0 ||
            fail("record.$(record.identity_id)", "tolerance is invalid")
        if record.identity_id == "opening_latent_nominal_expenditure"
            record.status == "FAIL_EXPECTED_LATENT_WEDGE" ||
                fail(
                "record.$(record.identity_id)",
                "must retain the expected latent failure",
            )
            record.absolute_diagnostic_value > record.tolerance ||
                fail(
                "record.$(record.identity_id)",
                "unexpectedly passes its tolerance",
            )
        elseif record.status ∉ ("PASS", "PASS_AT_SOURCE_ROUNDING")
            fail(
                "record.$(record.identity_id)",
                "has unexpected status $(record.status)",
            )
        end
    end
    isempty(record.basis) && fail("record.$(record.identity_id)", "basis is empty")
    return record
end

function validate_report(report::TransitionHarnessReport, contract::HarnessContract)
    report.schema_version == REPORT_SCHEMA ||
        fail("report.schema_version", "is unsupported")
    report.contract_path == contract.path ||
        fail("report.contract_path", "differs from loaded contract")
    report.contract_sha256 == contract.sha256 ||
        fail("report.contract_sha256", "differs from loaded contract")
    report.classification == SAFE_CLASSIFICATION ||
        fail("report.classification", "is unsafe")
    report.information_track == SAFE_CLASSIFICATION ||
        fail("report.information_track", "is unsafe")
    report.promotion_status == SAFE_PROMOTION_STATUS ||
        fail("report.promotion_status", "is unsafe")
    report.horizons == contract.horizons ||
        fail("report.horizons", "differ from contract")
    report.seeds == contract.seeds ||
        fail("report.seeds", "differ from contract")
    report.candidate_ids == getfield.(contract.candidates, :candidate_id) ||
        fail("report.candidate_ids", "differ from contract")
    report.runtime_source_tree_sha256 ==
        contract.runtime_source_tree_sha256 ||
        fail("report.runtime_source_tree_sha256", "differs from contract")
    report.runtime_source_tree_file_count ==
        contract.runtime_source_tree_file_count ||
        fail("report.runtime_source_tree_file_count", "differs from contract")
    report.julia_version == string(VERSION) ||
        fail("report.julia_version", "differs from executing Julia")
    report.julia_thread_count == Threads.nthreads() ||
        fail("report.julia_thread_count", "differs from executing Julia")
    report.blas_thread_count == LinearAlgebra.BLAS.get_num_threads() ||
        fail("report.blas_thread_count", "differs from executing BLAS")
    report.blas_vendor == string(LinearAlgebra.BLAS.vendor()) ||
        fail("report.blas_vendor", "differs from executing BLAS")
    false_boolean(report.origin_admissible, "report.origin_admissible")
    false_boolean(report.promotion_eligible, "report.promotion_eligible")
    false_boolean(
        report.accuracy_selection_eligible,
        "report.accuracy_selection_eligible",
    )
    false_boolean(
        report.runtime_selection_eligible,
        "report.runtime_selection_eligible",
    )
    isempty(report.records) && fail("report.records", "is empty")
    keys_seen = Set{Tuple{String, Int, Int, Int, String}}()
    by_scenario_period =
        Dict{Tuple{String, Int, Int, Int}, Set{String}}()
    semantic_by_id = Dict(
        candidate.candidate_id => candidate.semantic_sha256
            for candidate in contract.candidates
    )
    origin_by_id = Dict(
        candidate.candidate_id => candidate.origin_period
            for candidate in contract.candidates
    )
    candidate_by_id = Dict(
        candidate.candidate_id => candidate
            for candidate in contract.candidates
    )
    for record in report.records
        validate_record(record, contract)
        haskey(semantic_by_id, record.candidate_id) ||
            fail("record.candidate_id", "is outside the contract")
        record.candidate_semantic_sha256 ==
            semantic_by_id[record.candidate_id] ||
            fail("record.candidate_semantic_sha256", "differs from candidate")
        expected_date = lastdayofquarter(
            origin_by_id[record.candidate_id] +
                Month(3 * record.realized_period),
        )
        record.realized_date == expected_date ||
            fail("record.realized_date", "differs from realized period")
        candidate = candidate_by_id[record.candidate_id]
        if record.identity_id ==
                "opening_observation_nominal_expenditure" ||
                (
                record.identity_id == "real_expenditure" &&
                    record.realized_period == 0
            )
            record.diagnostic_value ==
                candidate.observed_expenditure_residual ||
                fail(
                "record.$(record.identity_id)",
                "differs from the pinned opening observation residual",
            )
        elseif record.identity_id ==
                "opening_latent_nominal_expenditure"
            isapprox(
                record.diagnostic_value,
                candidate.latent_expenditure_residual;
                atol = contract.model_numeric_tolerance,
                rtol = 0.0,
            ) ||
                fail(
                "record.$(record.identity_id)",
                "differs from the pinned latent-state residual",
            )
        end
        key = (
            record.candidate_id,
            record.seed,
            record.requested_horizon,
            record.realized_period,
            record.identity_id,
        )
        key in keys_seen &&
            fail("report.records", "duplicate identity key $(repr(key))")
        push!(keys_seen, key)
        scenario_period = key[1:4]
        push!(
            get!(
                by_scenario_period,
                scenario_period,
                Set{String}(),
            ),
            record.identity_id,
        )
    end
    for candidate in contract.candidates
        for seed in contract.seeds
            for horizon in contract.horizons
                for realized_period in 0:horizon
                    key = (
                        candidate.candidate_id,
                        seed,
                        horizon,
                        realized_period,
                    )
                    haskey(by_scenario_period, key) ||
                        fail("report.records", "missing scenario period $(repr(key))")
                    by_scenario_period[key] ==
                        expected_identity_ids(realized_period) ||
                        fail(
                        "report.records",
                        "identity set differs at $(repr(key))",
                    )
                end
            end
        end
    end
    report.record_semantic_sha256 == record_semantic_sha256(report.records) ||
        fail("report.record_semantic_sha256", "does not match records")
    return report
end

function run_harness(contract::HarnessContract = load_contract())
    USOpeningAccountingCandidate.validate_build_environment(
        Dict{String, Any}(
            "execution_envelope" => contract.execution_envelope,
        ),
    )
    contract.runtime_parallel &&
        fail("runtime", "parallel execution must remain disabled")
    runtime_digest = source_tree_digest(
        safe_path(
            contract.repo_root,
            contract.runtime_source_tree_path,
            "contract.runtime_source_tree_path",
        ),
    )
    runtime_digest.sha256 == contract.runtime_source_tree_sha256 ||
        fail("runtime", "source-tree SHA-256 changed after contract load")
    runtime_digest.file_count == contract.runtime_source_tree_file_count ||
        fail("runtime", "source-tree file count changed after contract load")

    traces =
        Dict{Tuple{String, Int, Int}, NamedTuple{(:primary, :replay), Tuple{ScenarioTrace, ScenarioTrace}}}()
    candidate_payloads = Dict{String, Any}()
    for input in contract.candidates
        candidate_payloads[input.candidate_id] =
            load_candidate(contract, input)
        candidate = candidate_payloads[input.candidate_id]
        for seed in contract.seeds
            for horizon in contract.horizons
                primary = simulate_trace(
                    contract,
                    input,
                    candidate,
                    seed,
                    horizon;
                    emit_records = true,
                )
                replay = simulate_trace(
                    contract,
                    input,
                    candidate,
                    seed,
                    horizon;
                    emit_records = false,
                )
                traces[(input.candidate_id, seed, horizon)] = (;
                    primary,
                    replay,
                )
            end
        end
    end

    records = IdentityRecord[]
    longest_horizon = last(contract.horizons)
    for input in contract.candidates
        for seed in contract.seeds
            longest =
                traces[(input.candidate_id, seed, longest_horizon)].primary
            for horizon in contract.horizons
                trace = traces[(input.candidate_id, seed, horizon)]
                append!(records, trace.primary.records)
                append_determinism_records!(
                    records,
                    input,
                    seed,
                    horizon,
                    trace.primary,
                    trace.replay,
                    longest,
                )
            end
        end
    end
    sort!(
        records;
        by = record -> (
            record.candidate_id,
            record.seed,
            record.requested_horizon,
            record.realized_period,
            record.identity_id,
        ),
    )
    report = TransitionHarnessReport(
        REPORT_SCHEMA,
        contract.path,
        contract.sha256,
        contract.classification,
        contract.information_track,
        contract.promotion_status,
        copy(contract.horizons),
        copy(contract.seeds),
        getfield.(contract.candidates, :candidate_id),
        record_semantic_sha256(records),
        records,
        runtime_digest.sha256,
        runtime_digest.file_count,
        string(VERSION),
        Threads.nthreads(),
        LinearAlgebra.BLAS.get_num_threads(),
        string(LinearAlgebra.BLAS.vendor()),
        false,
        false,
        false,
        false,
    )
    return validate_report(report, contract)
end

function csv_record_payload(record::IdentityRecord)
    return (
        schema_version = record.schema_version,
        candidate_id = record.candidate_id,
        candidate_semantic_sha256 = record.candidate_semantic_sha256,
        seed = record.seed,
        requested_horizon = record.requested_horizon,
        realized_period = record.realized_period,
        realized_date = string(record.realized_date),
        identity_id = record.identity_id,
        layer = record.layer,
        status = record.status,
        diagnostic_value = record.diagnostic_value,
        absolute_diagnostic_value = record.absolute_diagnostic_value,
        tolerance = record.tolerance,
        blocker = record.blocker,
        basis = record.basis,
        origin_admissible = record.origin_admissible,
        promotion_eligible = record.promotion_eligible,
        accuracy_selection_eligible =
            record.accuracy_selection_eligible,
        runtime_selection_eligible = record.runtime_selection_eligible,
    )
end

function report_manifest(report, contract, records_sha256)
    status_counts = Dict{String, Int}()
    for record in report.records
        status_counts[record.status] =
            get(status_counts, record.status, 0) + 1
    end
    return Dict{String, Any}(
        "schema_version" => REPORT_SCHEMA,
        "contract_path" => relpath(contract.path, contract.repo_root),
        "contract_sha256" => contract.sha256,
        "classification" => report.classification,
        "information_track" => report.information_track,
        "promotion_status" => report.promotion_status,
        "horizons" => report.horizons,
        "seeds" => report.seeds,
        "candidate_ids" => report.candidate_ids,
        "candidate" => [
            Dict{String, Any}(
                    "candidate_id" => candidate.candidate_id,
                    "origin_period" => string(candidate.origin_period),
                    "artifact_path" => candidate.artifact_path,
                    "artifact_sha256" => candidate.artifact_sha256,
                    "semantic_sha256" => candidate.semantic_sha256,
                ) for candidate in contract.candidates
        ],
        "candidate_manifest_path" => contract.candidate_manifest_path,
        "candidate_manifest_sha256" =>
            contract.candidate_manifest_sha256,
        "candidate_builder_path" => contract.candidate_builder_path,
        "candidate_builder_sha256" => contract.candidate_builder_sha256,
        "candidate_execution_envelope_dependency_path" =>
            contract.candidate_execution_envelope_dependency_path,
        "candidate_execution_envelope_dependency_sha256" =>
            contract.candidate_execution_envelope_dependency_sha256,
        "candidate_supply_make_dependency_path" =>
            contract.candidate_supply_make_dependency_path,
        "candidate_supply_make_dependency_sha256" =>
            contract.candidate_supply_make_dependency_sha256,
        "candidate_t10105_dependency_path" =>
            contract.candidate_t10105_dependency_path,
        "candidate_t10105_dependency_sha256" =>
            contract.candidate_t10105_dependency_sha256,
        "harness_module_path" => contract.harness_module_path,
        "harness_module_sha256" => contract.harness_module_sha256,
        "julia_project_path" => contract.julia_project_path,
        "julia_project_sha256" => contract.julia_project_sha256,
        "julia_manifest_path" => contract.julia_manifest_path,
        "julia_manifest_sha256" => contract.julia_manifest_sha256,
        "record_count" => length(report.records),
        "record_semantic_sha256" => report.record_semantic_sha256,
        "records_csv" => "transition_identity_records.csv",
        "records_csv_sha256" => records_sha256,
        "status_counts" => status_counts,
        "runtime_source_tree_path" => contract.runtime_source_tree_path,
        "runtime_source_tree_digest_algorithm" =>
            contract.runtime_source_tree_digest_algorithm,
        "runtime_source_tree_file_count" =>
            report.runtime_source_tree_file_count,
        "runtime_source_tree_sha256" =>
            report.runtime_source_tree_sha256,
        "execution_envelope" => contract.execution_envelope,
        "byte_reproducibility_scope" =>
            contract.byte_reproducibility_scope,
        "cross_machine_byte_determinism_claimed" =>
            contract.cross_machine_byte_determinism_claimed,
        "julia_version" => report.julia_version,
        "julia_thread_count" => report.julia_thread_count,
        "blas_thread_count" => report.blas_thread_count,
        "blas_vendor" => report.blas_vendor,
        "thread_contract" => "single_thread_julia_and_blas",
        "origin_admissible" => false,
        "promotion_eligible" => false,
        "accuracy_selection_eligible" => false,
        "runtime_selection_eligible" => false,
        "interpretation" =>
            "Engineering accounting-transition diagnostic only; no origin, promotion, forecast-accuracy, or runtime-selection claim.",
    )
end

function write_report(
        report::TransitionHarnessReport,
        contract::HarnessContract,
        output_directory::AbstractString,
    )
    validate_report(report, contract)
    target = abspath(normpath(String(output_directory)))
    ispath(target) &&
        fail("output_directory", "refusing to overwrite existing path $target")
    parent = dirname(target)
    mkpath(parent)
    temporary = mktempdir(parent)
    records_path =
        joinpath(temporary, "transition_identity_records.csv")
    manifest_path = joinpath(temporary, "manifest.toml")
    try
        CSV.write(records_path, csv_record_payload.(report.records))
        records_sha256 = file_sha256(records_path)
        manifest = report_manifest(report, contract, records_sha256)
        open(manifest_path, "w") do io
            TOML.print(io, manifest; sorted = true)
        end
        mv(temporary, target)
    finally
        isdir(temporary) && rm(temporary; recursive = true)
    end
    installed_records =
        joinpath(target, "transition_identity_records.csv")
    installed_manifest = joinpath(target, "manifest.toml")
    return (
        directory = target,
        records_path = installed_records,
        records_sha256 = file_sha256(installed_records),
        manifest_path = installed_manifest,
        manifest_sha256 = file_sha256(installed_manifest),
        record_count = length(report.records),
    )
end

end
