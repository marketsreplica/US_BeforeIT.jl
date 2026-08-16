module USRevisedDataABMComparison

using Dates
using JLD2
using LinearAlgebra
using Random
using SHA
using Statistics
using TOML

import BeforeIT as Bit

if !isdefined(@__MODULE__, :USRevisedDataBenchmarkDiagnostic)
    include(joinpath(@__DIR__, "..", "USRevisedDataBenchmarkDiagnostic.jl"))
end
using .USRevisedDataBenchmarkDiagnostic

const BASE = USRevisedDataBenchmarkDiagnostic

export ABMVariant,
    ABMComparisonResult,
    ABMOriginDiagnostic,
    ABMWeightedScore,
    EnsembleSummary,
    MonteCarloError,
    HEADLINE_VARIANT,
    BURN_IN_VARIANT,
    OUTLOOK_VARIANT,
    HEADLINE_V2_VARIANT,
    OUTLOOK_V2_VARIANT,
    RECONCILED_CALIBRATION_OBJECT_PATH,
    ACTIVE_CALIBRATION_PATH,
    CACHE_IDENTITY_FILENAME,
    CACHE_IDENTITY_SCHEMA,
    SEED_CONTRACT_ID,
    CacheIdentityError,
    build_cache_identity,
    read_cache_identity,
    write_cache_identity,
    validate_cache_identity,
    canonical_origin_count,
    simulate_abm_ensembles,
    run_abm_comparison,
    write_abm_comparison,
    write_abm_outlook

const CONTRACT_ID = "beforeit-us-revised-data-abm-comparison.v1"
const INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
const MIXED_VINTAGE_STRUCTURAL_YEAR = 2024
const PANEL_FIRST_PERIOD = "2000Q3"

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const CALIBRATION_OBJECT_PATH = joinpath(
    REPOSITORY_ROOT,
    "data",
    "us",
    "calibration",
    "US_2024_calibration_object.jld2",
)
const BASE_DIAGNOSTIC_PATH = normpath(
    joinpath(@__DIR__, "..", "USRevisedDataBenchmarkDiagnostic.jl"),
)

# v2 initialises the model from a commodity-balance-reconciled calibration artifact
# built by `scripts/us/calibration/reconcile_commodity_balance.jl`. The artifact -- not
# this module -- carries the reconciliation mode and the growth-expectation
# specification, so the selection is a single path.
const RECONCILED_CALIBRATION_OBJECT_PATH = joinpath(
    REPOSITORY_ROOT,
    "data",
    "us",
    "calibration",
    "US_2024_calibration_object_reconciled.jld2",
)

# Set by the runner before `simulate_abm_ensembles`; the manifests seal whatever was
# actually used, never the default.
const ACTIVE_CALIBRATION_PATH = Ref(CALIBRATION_OBJECT_PATH)


"""
    calibration_provenance_lines()

TOML lines describing the calibration artifact the run actually used, including the
reconciliation metadata when the artifact carries it. `lambda` is an explicit accounting
choice (the artifact's expenditure aggregates are scaled onto its production account) and
must survive into every manifest.
"""
function calibration_provenance_lines()
    path = ACTIVE_CALIBRATION_PATH[]
    lines = [
        "calibration_object_path = \"$(relpath(path, REPOSITORY_ROOT))\"",
        "calibration_object_sha256 = \"$(sha256_hex(read(path)))\"",
    ]
    stored = JLD2.load(path)
    metadata = get(stored, "metadata", nothing)
    reconciled = metadata isa AbstractDict && haskey(metadata, "method")
    push!(lines, "commodity_balance_reconciled = $reconciled")
    if reconciled
        push!(lines, "reconciliation_method = \"$(metadata["method"])\"")
        push!(lines, "reconciliation_mode = \"$(get(metadata, "mode", "unknown"))\"")
        push!(lines, "reconciliation_rho = $(get(metadata, "rho", NaN))")
        push!(lines, "reconciliation_lambda = $(get(metadata, "lambda", NaN))")
        push!(
            lines,
            "reconciliation_lambda_semantics = \"explicit accounting choice: the four " *
                "final-demand aggregates C, G, I and X (and capital_consumption and " *
                "gross_capitalformation_dwellings, which set the investment budget) are " *
                "scaled by lambda so the artifact's expenditure aggregates match its " *
                "production account and the opening commodity balance clears exactly. " *
                "lambda is fixed by the accounting identity alone and was not chosen with " *
                "reference to any forecast error.\"",
        )
        push!(
            lines,
            "growth_expectation_specification = \"$(get(metadata, "expectations", "legacy_ar1_log_level"))\"",
        )
        push!(lines, "opening_inventories_from_discrepancy = false")
        push!(lines, "measured_bea_imports_retained = true")
    else
        push!(lines, "growth_expectation_specification = \"legacy_ar1_log_level\"")
    end
    return lines
end

# The five targets the ABM serves with a native operator. `pce_price_index`,
# `core_pce_price_index` and `payroll_employment` need measurement bridges the
# model does not provide and are deliberately absent.
const HEADLINE_TARGET_IDS = ["real_gdp", "gdp_deflator"]
const SECONDARY_TARGET_IDS = ["nominal_gdp", "effective_federal_funds_rate"]

# `unemployment_rate` is emitted and diagnosed but never enters a weighted
# score: the initial unemployed stock is a length-1 annual array frozen at
# 2024, so every historical origin opens at the 2024 labour market.
const UNSCORED_APPENDIX_TARGET_IDS = ["unemployment_rate"]
const SCORED_TARGET_SETS = [
    ("headline_real_gdp_gdp_deflator", HEADLINE_TARGET_IDS),
    (
        "secondary_nominal_gdp_effective_federal_funds_rate",
        SECONDARY_TARGET_IDS,
    ),
]

const ALL_AVAILABLE_TRACK = "abm_all_available_common_cells"
const BALANCED_H12_TRACK = "abm_balanced_h12_common_cells"
const PANDEMIC_MASKED_TRACK = "abm_pandemic_masked_common_cells"
const TRACKS = (ALL_AVAILABLE_TRACK, BALANCED_H12_TRACK, PANDEMIC_MASKED_TRACK)

# Frozen `PT_ACUTE` window from the project's regime matrix: the cut is on the
# TARGET date, not the origin date. The masked track keeps `PT_PRE` + `PT_POST`.
const ACUTE_PANDEMIC_FIRST_TARGET_PERIOD = "2020Q1"
const ACUTE_PANDEMIC_LAST_TARGET_PERIOD = "2021Q4"

struct ABMVariant
    name::String
    mean_model_id::String
    median_model_id::String
    burn_in_quarters::Int
    default_paths::Int
end

const HEADLINE_VARIANT = ABMVariant(
    "headline",
    "beforeit_abm_us_v1_mean",
    "beforeit_abm_us_v1_median",
    0,
    500,
)
const BURN_IN_VARIANT = ABMVariant(
    "burnin",
    "beforeit_abm_us_v1_mean_burnin",
    "beforeit_abm_us_v1_median_burnin",
    1,
    128,
)
const OUTLOOK_VARIANT = ABMVariant(
    "outlook",
    "beforeit_abm_us_v1_mean",
    "beforeit_abm_us_v1_median",
    0,
    500,
)
const HEADLINE_V2_VARIANT = ABMVariant(
    "headline_v2",
    "beforeit_abm_us_v2_mean",
    "beforeit_abm_us_v2_median",
    0,
    500,
)
const OUTLOOK_V2_VARIANT = ABMVariant(
    "outlook_v2",
    "beforeit_abm_us_v2_mean",
    "beforeit_abm_us_v2_median",
    0,
    500,
)

# The numerical forecast kernel is a separately sealed file: everything whose
# change can move a forecast number lives there, and its digest is compared on
# every run. See USRevisedDataABMKernel.jl.
include(joinpath(@__DIR__, "USRevisedDataABMKernel.jl"))


# ---------------------------------------------------------------------------
# cache identity
#
# An ensemble cache is only resumable by a run that would have produced the same
# rows. Keying resumption on (variant, origin_index) alone lets a second run with
# a different calibration artifact, path count or code version adopt stale
# forecasts and then relabel them in its own manifest. The identity document
# below is written beside the cache at first generation and revalidated in full
# before any cached row is loaded.
# ---------------------------------------------------------------------------

const CACHE_IDENTITY_FILENAME = "cache_identity.toml"
const CACHE_IDENTITY_SCHEMA = "beforeit-us-revised-data-abm-cache-identity.v5"
const CACHE_IDENTITY_SCHEMA_V4 = "beforeit-us-revised-data-abm-cache-identity.v4"
const CACHE_IDENTITY_SCHEMA_V3 = "beforeit-us-revised-data-abm-cache-identity.v3"
const CACHE_IDENTITY_SCHEMA_V1 = "beforeit-us-revised-data-abm-cache-identity.v1"
const CACHE_IDENTITY_SCHEMA_V2 = "beforeit-us-revised-data-abm-cache-identity.v2"


# The simulation owns these files. --force-recompute must remove all of them:
# leaving a stale failure log beside a fresh, clean cache misreports the run.
const RUN_OWNED_SIMULATION_ARTIFACTS = (
    "abm_ensemble_summaries.csv",
    "abm_origin_diagnostics.csv",
    "abm_path_failures.log",
    CACHE_IDENTITY_FILENAME,
)

const NUMERICAL_KERNEL_PATH =
    joinpath(@__DIR__, "USRevisedDataABMKernel.jl")
const RUNNER_PATH =
    joinpath(@__DIR__, "run_revised_data_abm_comparison.jl")
const ENVIRONMENT_MANIFEST_PATH =
    joinpath(REPOSITORY_ROOT, "scripts", "us", "Manifest.toml")
const RUNTIME_SOURCE_ROOT = joinpath(REPOSITORY_ROOT, "src")

"""
    runtime_source_tree_sha256()

A deterministic digest of the model runtime that actually generates the paths.

Defined as the sha256 of the concatenation, over every `.jl` file under `src/`
sorted by its `/`-separated path relative to the repository root, of
`"<relative path>\0<file sha256>\n"`. Sorting makes it filesystem-order
independent; including the path makes a rename visible; including each file's
digest makes any content change visible.

Without this a change in `src/agent_actions/` would alter every forecast while
the caches still validated clean -- exactly the silent staleness the identity
exists to prevent.
"""
function runtime_source_tree_sha256(root::AbstractString = RUNTIME_SOURCE_ROOT)
    entries = Tuple{String, String}[]
    for (directory, _, files) in walkdir(root)
        for file in files
            endswith(file, ".jl") || continue
            absolute = joinpath(directory, file)
            relative = replace(
                relpath(absolute, REPOSITORY_ROOT),
                Base.Filesystem.path_separator => "/",
            )
            push!(entries, (relative, sha256_hex(read(absolute))))
        end
    end
    sort!(entries; by = first)
    context = SHA.SHA256_CTX()
    for (relative, digest) in entries
        SHA.update!(context, Vector{UInt8}(relative))
        SHA.update!(context, UInt8[0x00])
        SHA.update!(context, Vector{UInt8}(digest))
        SHA.update!(context, UInt8[0x0a])
    end
    return bytes2hex(SHA.digest!(context))
end

# The seed stream is `hash((:beforeit_us_abm_revised_comparison_v1, variant, origin, path))`
# reduced modulo 0x40000000 and consumed through the default global RNG. Both
# `Base.hash` and the global RNG are version-bound, so the contract id travels with
# the Julia version that produced the cache.
const SEED_CONTRACT_ID =
    "beforeit_us_abm_revised_comparison_v1/base_hash_mod_0x40000000/global_rng"

# Fields that must agree exactly before a cached row may be reused. Order is fixed
# so the document is deterministic.
const CACHE_IDENTITY_FIELDS = (
    "schema_version",
    "contract_id",
    "seed_contract_id",
    "variant",
    "burn_in_quarters",
    "simulated_quarters",
    "paths_requested",
    "model_scale",
    "calibration_object_path",
    "calibration_object_sha256",
    "comparison_code_sha256",
    "base_diagnostic_code_sha256",
    "runtime_source_tree_sha256",
    "numerical_kernel_sha256",
    "runner_sha256",
    "environment_manifest_sha256",
    "panel_sha256",
    "panel_manifest_sha256",
    "julia_version",
    "origin_indices",
    "origin_pairs",
)
# Schema 4 recorded every sealed digest but bound only the origin INDICES;
# schema 5 binds the exact index -> period pairs.
const CACHE_IDENTITY_FIELDS_V4 = (
    "schema_version",
    "contract_id",
    "seed_contract_id",
    "variant",
    "burn_in_quarters",
    "simulated_quarters",
    "paths_requested",
    "model_scale",
    "calibration_object_path",
    "calibration_object_sha256",
    "comparison_code_sha256",
    "base_diagnostic_code_sha256",
    "runtime_source_tree_sha256",
    "numerical_kernel_sha256",
    "runner_sha256",
    "environment_manifest_sha256",
    "panel_sha256",
    "panel_manifest_sha256",
    "julia_version",
    "origin_indices",
)

# The fields that describe WHICH EXPERIMENT the cached rows are. These must agree
# exactly before a schema-1 identity may be upgraded: if any of them moved, the
# document no longer describes the cache and upgrading would launder it.
#
# The code-identity fields are deliberately NOT in this list. Introducing schema 2
# necessarily changes the module, and the runner changed with it, so demanding
# equality there would make the upgrade impossible by construction. Those fields
# are re-baselined and the document says so. The empirical guarantee that the code
# change did not move the numbers is the byte-identical re-score, not this check.
# Fields describing the harness rather than the model runtime. A migrated identity
# has these re-baselined under attestation and they are not re-compared; a native
# identity must match the current tree. runtime_source_tree_sha256 and
# environment_manifest_sha256 are deliberately excluded -- those can change the
# numbers, so they are compared on every run regardless of migration.
const HARNESS_IDENTITY_FIELDS = (
    "comparison_code_sha256",
    "base_diagnostic_code_sha256",
    "runner_sha256",
)

const CACHE_IDENTITY_EXPERIMENT_FIELDS = (
    "contract_id",
    "seed_contract_id",
    "variant",
    "burn_in_quarters",
    "simulated_quarters",
    "paths_requested",
    "model_scale",
    "calibration_object_path",
    "calibration_object_sha256",
    "panel_sha256",
    "panel_manifest_sha256",
    "julia_version",
    "origin_indices",
)

# What schema 1 recorded. Retained so a v1 document can be verified before upgrade.
# Schema 2 recorded the runtime tree, runner and environment but not the
# numerical kernel, which had not yet been extracted.
const CACHE_IDENTITY_FIELDS_V2 = (
    "schema_version",
    "contract_id",
    "seed_contract_id",
    "variant",
    "burn_in_quarters",
    "simulated_quarters",
    "paths_requested",
    "model_scale",
    "calibration_object_path",
    "calibration_object_sha256",
    "comparison_code_sha256",
    "base_diagnostic_code_sha256",
    "runtime_source_tree_sha256",
    "runner_sha256",
    "environment_manifest_sha256",
    "panel_sha256",
    "panel_manifest_sha256",
    "julia_version",
    "origin_indices",
)

const CACHE_IDENTITY_FIELDS_V1 = (
    "schema_version",
    "contract_id",
    "seed_contract_id",
    "variant",
    "burn_in_quarters",
    "simulated_quarters",
    "paths_requested",
    "model_scale",
    "calibration_object_path",
    "calibration_object_sha256",
    "comparison_code_sha256",
    "base_diagnostic_code_sha256",
    "panel_sha256",
    "panel_manifest_sha256",
    "julia_version",
    "origin_indices",
)

"""
    effective_generation_provenance(identity)

The code identity that actually produced the cached rows.

For a migrated document the current `comparison_code_sha256` is a re-baselined
value describing the tree at migration time, not the tree that generated the
rows; the generating hashes live in the `original_schema1_*` fields. Comparing
the re-baselined values would judge two caches with different real provenance to
be equivalent, which is precisely what preserving the originals was meant to
prevent.
"""
function effective_generation_provenance(identity::AbstractDict)
    migrated = get(identity, "upgraded_from_schema_1", false) === true
    comparison = migrated ?
        get(identity, "original_schema1_comparison_code_sha256", nothing) :
        get(identity, "comparison_code_sha256", nothing)
    base = migrated ?
        get(identity, "original_schema1_base_diagnostic_code_sha256", nothing) :
        get(identity, "base_diagnostic_code_sha256", nothing)
    return (
        comparison = comparison === nothing ? nothing : String(comparison),
        base_diagnostic = base === nothing ? nothing : String(base),
        migrated = migrated,
    )
end

struct CacheIdentityError <: Exception
    field::String
    message::String
end

function Base.showerror(io::IO, error::CacheIdentityError)
    print(io, "cache identity mismatch on `", error.field, "`: ", error.message)
    return nothing
end

"""
    rewrite_struct_csv(path, rows, T)

Atomically replace a struct CSV: write a sibling temporary and rename over the
original, so an interrupted prune can never leave a half-written file.
"""
function rewrite_struct_csv(path::AbstractString, rows, ::Type{T}) where {T}
    temporary = path * ".tmp"
    isfile(temporary) && rm(temporary)
    if isempty(rows)
        open(temporary, "w") do io
            println(io, join(String.(fieldnames(T)), ","))
        end
    else
        append_struct_csv(temporary, rows, T)
    end
    mv(temporary, path; force = true)
    return path
end

"""
    origin_grid_complete(rows)

Whether an origin's ensemble rows are exactly the expected target x horizon grid:
the right number of rows, no duplicates, and every (target, horizon) pair present
once. A bare row count would accept a block that lost one cell and gained a
duplicate of another.
"""
function origin_grid_complete(rows)
    length(rows) == ENSEMBLE_ROWS_PER_ORIGIN || return false
    seen = Set{Tuple{String, Int}}()
    for row in rows
        key = (row.target_id, row.horizon)
        key in seen && return false
        push!(seen, key)
    end
    # Set equality, not cardinality: 60 distinct pairs is not the same as the 60
    # pairs this contract scores. A horizon-13 cell substituted for an expected
    # one keeps the count while silently changing the grid.
    return seen == EXPECTED_FORECAST_GRID
end

"""
    finalize_cache_identity(identity_path, identity, diagnostics)

Rewrite the stored identity so it describes the origin set the cache actually
holds, then revalidate. Called on every successful exit -- including the path
where nothing was pending -- so an identity left stale by a run that died between
appending origins and refreshing self-heals on the next invocation instead of
persisting a claim the cache no longer supports.
"""
function finalize_cache_identity(identity_path, identity, diagnostics)
    (identity_path === nothing || identity === nothing) && return false
    refreshed = copy(identity)
    refreshed["origin_indices"] =
        sort!(unique(getfield.(diagnostics, :origin_index)))
    refreshed["origin_pairs"] = sort!(
        unique(
            "$(row.origin_index)=$(row.origin_period)" for row in diagnostics
        ),
    )
    changed = true
    if isfile(identity_path)
        stored_now = read_cache_identity(identity_path)
        for field in (
                "adopted_from_legacy_cache",
                "upgraded_from_schema_1",
                "original_schema1_comparison_code_sha256",
                "original_schema1_base_diagnostic_code_sha256",
                "migration_verified_fields",
            )
            haskey(stored_now, field) && (refreshed[field] = stored_now[field])
        end
        changed = Set(get(stored_now, "origin_indices", Int[])) !=
            Set(refreshed["origin_indices"])
    end
    write_cache_identity(identity_path, refreshed)
    validate_cache_identity(
        refreshed,
        read_cache_identity(identity_path);
        location = relpath(identity_path, REPOSITORY_ROOT),
    )
    return changed
end

"""
    build_cache_identity(variant, origins; paths, calibration_path, panel)

The identity a run would stamp on the cache it generates. Every field is either a
content hash or an exact run parameter; nothing here is derived from CLI text.
"""
function build_cache_identity(
        variant::ABMVariant,
        origins::Vector{Tuple{Int, String}};
        paths::Int,
        calibration_path::AbstractString,
        panel::QuarterlyPanel,
    )
    return Dict{String, Any}(
        "schema_version" => CACHE_IDENTITY_SCHEMA,
        "contract_id" => CONTRACT_ID,
        "seed_contract_id" => SEED_CONTRACT_ID,
        "variant" => variant.name,
        "burn_in_quarters" => variant.burn_in_quarters,
        "simulated_quarters" => SIMULATION_HORIZON + variant.burn_in_quarters,
        "paths_requested" => paths,
        "model_scale" => MODEL_SCALE,
        "calibration_object_path" =>
            relpath(abspath(calibration_path), REPOSITORY_ROOT),
        "calibration_object_sha256" => sha256_hex(read(abspath(calibration_path))),
        "comparison_code_sha256" => sha256_hex(read(abspath(@__FILE__))),
        "base_diagnostic_code_sha256" => sha256_hex(read(BASE_DIAGNOSTIC_PATH)),
        "runtime_source_tree_sha256" => runtime_source_tree_sha256(),
        "numerical_kernel_sha256" => sha256_hex(read(NUMERICAL_KERNEL_PATH)),
        "runner_sha256" => sha256_hex(read(RUNNER_PATH)),
        "environment_manifest_sha256" =>
            isfile(ENVIRONMENT_MANIFEST_PATH) ?
            sha256_hex(read(ENVIRONMENT_MANIFEST_PATH)) : "absent",
        "panel_sha256" => panel.panel_sha256,
        "panel_manifest_sha256" => panel.manifest_sha256,
        "julia_version" => string(VERSION),
        "origin_indices" => [entry[1] for entry in origins],
        # The exact index -> period mapping, not just the indices. Origin index
        # derivation happens in the harness, so binding the pairs is what stops a
        # change to period arithmetic from silently re-pointing an index at a
        # different quarter while validation still sees a familiar index set.
        "origin_pairs" => ["$(entry[1])=$(entry[2])" for entry in origins],
    )
end

"""
    write_cache_identity(path, identity; adopted_from_legacy_cache = false)

Persist the identity document beside its cache.
"""
function write_cache_identity(
        path::AbstractString,
        identity::AbstractDict;
        adopted_from_legacy_cache::Bool = false,
    )
    lines = String[]
    for field in CACHE_IDENTITY_FIELDS
        value = identity[field]
        if field == "origin_pairs"
            push!(
                lines,
                "origin_pairs = [" *
                    join(("\"$(pair)\"" for pair in value), ", ") * "]",
            )
            continue
        end
        rendered = if value isa AbstractString
            "\"$(value)\""
        elseif value isa AbstractVector
            "[$(join(value, ", "))]"
        elseif value isa Bool
            string(value)
        else
            string(value)
        end
        push!(lines, "$(field) = $(rendered)")
    end
    sticky_adoption =
        adopted_from_legacy_cache ||
        get(identity, "adopted_from_legacy_cache", false) === true
    push!(lines, "adopted_from_legacy_cache = $(sticky_adoption)")
    for field in (
            "original_schema1_comparison_code_sha256",
            "original_schema1_base_diagnostic_code_sha256",
        )
        haskey(identity, field) &&
            push!(lines, "$(field) = \"$(identity[field])\"")
    end
    if haskey(identity, "migration_verified_fields")
        rendered = join(
            ("\"$(field)\"" for field in identity["migration_verified_fields"]),
            ", ",
        )
        push!(lines, "migration_verified_fields = [$rendered]")
    end
    if get(identity, "upgraded_from_schema_1", false) === true
        push!(lines, "upgraded_from_schema_1 = true")
        push!(
            lines,
            "upgrade_note = \"Verified unchanged before upgrade: contract, seed " *
                "contract, variant, burn-in, simulated quarters, requested paths, " *
                "model scale, calibration artifact and sha256, panel and manifest " *
                "sha256, Julia version, origin set. Re-baselined from the tree at " *
                "upgrade time and NOT attested as observed at cache generation: " *
                "comparison_code_sha256, base_diagnostic_code_sha256, " *
                "runtime_source_tree_sha256, runner_sha256, " *
                "environment_manifest_sha256. The guarantee that those code changes " *
                "did not move the numbers is the byte-identical re-score of every " *
                "committed score table, not this document. Attestation chain for " *
                "numerical_kernel_sha256: the schema-1 module hash preserved above " *
                "generated these rows; the numerical kernel was then extracted out " *
                "of that module by an auditable pure-move commit (refactor: extract " *
                "the numerical forecast kernel) which moved no line and left every " *
                "score table byte-identical; the kernel digest is enforced on every " *
                "run from that point on, migrated identity or not. The kernel was " *
                "subsequently EXTENDED to absorb the complete per-origin generation " *
                "operation (refactor: move per-origin generation orchestration into " *
                "the sealed kernel), because calling a sealed function does not seal " *
                "its call arguments or surrounding control flow; that move left every " *
                "score table byte-identical and numerical_kernel_sha256 was restamped " *
                "here.\"",
        )
    end
    push!(lines, "written_at = \"$(Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SSZ"))\"")
    # Atomic: a half-written identity beside a complete cache is worse than none.
    temporary = path * ".tmp"
    open(temporary, "w") do io
        for line in lines
            println(io, line)
        end
    end
    mv(temporary, path; force = true)
    return path
end

"""
    read_cache_identity(path)

Parse a stored identity document, rejecting one that omits any required field.
"""
function read_cache_identity(path::AbstractString)
    isfile(path) || throw(
        CacheIdentityError(
            "path",
            "no identity document at $path; the cache cannot be authenticated",
        ),
    )
    document = TOML.parsefile(path)
    schema = get(document, "schema_version", "")
    required = if schema == CACHE_IDENTITY_SCHEMA_V1
        CACHE_IDENTITY_FIELDS_V1
    elseif schema == CACHE_IDENTITY_SCHEMA_V2
        CACHE_IDENTITY_FIELDS_V2
    elseif schema in (CACHE_IDENTITY_SCHEMA_V3, CACHE_IDENTITY_SCHEMA_V4)
        CACHE_IDENTITY_FIELDS_V4
    else
        CACHE_IDENTITY_FIELDS
    end
    for field in required
        haskey(document, field) ||
            throw(CacheIdentityError(field, "absent from $path"))
    end
    return document
end

"""
    upgrade_cache_identity(stored, expected)

Raise a schema-v1 identity to v2 after checking that everything v1 covered still
agrees. The three fields v1 never recorded -- the model runtime tree, the runner
and the environment manifest -- are taken from the current tree and the document
records that they were re-baselined rather than observed at generation, so the
upgrade never claims to have witnessed something it did not.
"""
function upgrade_cache_identity(
        stored::AbstractDict,
        expected::AbstractDict,
        cache_diagnostics = nothing,
    )
    for field in CACHE_IDENTITY_EXPERIMENT_FIELDS
        want = expected[field]
        got = stored[field]
        if field in ("origin_indices", "origin_pairs")
            Set(got) == Set(want) || throw(
                CacheIdentityError(
                    field,
                    "schema-1 identity covers a different origin set; refusing to upgrade",
                ),
            )
            continue
        end
        matched = (want isa Real && got isa Real) ? want == got :
            string(want) == string(got)
        matched || throw(
            CacheIdentityError(
                field,
                "schema-1 identity has $(repr(got)) but this tree has $(repr(want)); " *
                    "refusing to upgrade an identity that no longer describes the cache",
            ),
        )
    end
    # Origin pairs are DERIVED from the diagnostics the cache actually carries, never
    # copied from the older document or taken on trust from the request. A pre-v5
    # identity bound only indices, so accepting a claimed mapping would let an
    # upgrade mint a pairing the cache does not evidence.
    if cache_diagnostics !== nothing
        derived = sort!(
            unique(
                "$(row.origin_index)=$(row.origin_period)" for row in cache_diagnostics
            ),
        )
        requested = Set(String.(get(expected, "origin_pairs", String[])))
        unrequested = [pair for pair in derived if !(pair in requested)]
        isempty(unrequested) || throw(
            CacheIdentityError(
                "origin_pairs",
                "the cache maps origins to quarters this run does not request: " *
                    "$(unrequested); refusing to upgrade an identity onto a different " *
                    "index -> period mapping",
            ),
        )
    end

    upgraded = copy(expected)
    if cache_diagnostics !== nothing
        upgraded["origin_pairs"] = sort!(
            unique(
                "$(row.origin_index)=$(row.origin_period)" for row in cache_diagnostics
            ),
        )
        upgraded["origin_indices"] =
            sort!(unique(getfield.(cache_diagnostics, :origin_index)))
    end
    upgraded["upgraded_from_schema_1"] = true
    # Preserve, never overwrite, what schema 1 actually recorded. Replacing these
    # with current hashes would erase the only record of the code that produced
    # the cache, which is the opposite of what an identity document is for.
    # A schema-2 document already carries the preserved originals; only a schema-1
    # document's own hashes are the generation hashes.
    upgraded["original_schema1_comparison_code_sha256"] = String(
        get(
            stored, "original_schema1_comparison_code_sha256",
            stored["comparison_code_sha256"],
        ),
    )
    upgraded["original_schema1_base_diagnostic_code_sha256"] = String(
        get(
            stored, "original_schema1_base_diagnostic_code_sha256",
            stored["base_diagnostic_code_sha256"],
        ),
    )
    upgraded["migration_verified_fields"] =
        collect(CACHE_IDENTITY_EXPERIMENT_FIELDS)
    # Adoption is sticky: a cache that was once adopted from an unauthenticated
    # predecessor never becomes natively generated, however many times its
    # identity is migrated afterwards.
    upgraded["adopted_from_legacy_cache"] =
        get(stored, "adopted_from_legacy_cache", false) === true
    return upgraded
end

"""
    validate_cache_identity(expected, stored; location)

Compare the identity this run would stamp against the one the cache carries and
throw a `CacheIdentityError` naming the first field that disagrees. A cached row
is never loaded before this returns.
"""
function validate_cache_identity(
        expected::AbstractDict,
        stored::AbstractDict;
        location::AbstractString = "cache",
    )
    # Code identity. A migrated document records the hashes that actually
    # generated its rows in original_schema1_*, and the migration itself is the
    # attestation that the current tree is an accepted successor -- re-comparing
    # the fresh hash against it on every run would merely re-litigate that
    # decision and invalidate every migrated cache on any later edit here. So a
    # migrated identity is required to still carry intact generation provenance;
    # a native one must match the current tree exactly.
    # Harness fields describe the code that drove and scored the run. A migration
    # re-baselines them once, under an explicit attestation; the model runtime and
    # the environment are NOT in this set and are always compared exactly, so a
    # change under src/ or in the package environment can never pass silently.
    stored_provenance = effective_generation_provenance(stored)
    if stored_provenance.migrated
        for (label, value) in (
                ("original_schema1_comparison_code_sha256", stored_provenance.comparison),
                (
                    "original_schema1_base_diagnostic_code_sha256",
                    stored_provenance.base_diagnostic,
                ),
            )
            value === nothing && throw(
                CacheIdentityError(
                    label,
                    "$location is migrated but has lost its generation provenance",
                ),
            )
        end
    else
        for label in HARNESS_IDENTITY_FIELDS
            want = expected[label]
            got = stored[label]
            string(want) == string(got) || throw(
                CacheIdentityError(
                    label,
                    "this run has $(repr(want)) but $location was generated with $(repr(got))",
                ),
            )
        end
    end
    for field in CACHE_IDENTITY_FIELDS
        field in HARNESS_IDENTITY_FIELDS && continue
        want = expected[field]
        got = stored[field]
        if field in ("origin_indices", "origin_pairs")
            # A resumable cache may hold a prefix of the requested origins, but it
            # must never hold an origin this run did not ask for.
            extra = setdiff(Set(got), Set(want))
            isempty(extra) || throw(
                CacheIdentityError(
                    field,
                    "$location holds origins $(sort!(collect(extra))) that this run does not request",
                ),
            )
            continue
        end
        if want isa Real && got isa Real
            want == got && continue
        elseif string(want) == string(got)
            continue
        end
        throw(
            CacheIdentityError(
                field,
                "this run has $(repr(want)) but $location was generated with $(repr(got))",
            ),
        )
    end
    return nothing
end

struct EnsembleSummary
    variant::String
    origin_index::Int
    origin_period::String
    target_period::String
    target_id::String
    horizon::Int
    paths_used::Int
    ensemble_mean::Float64
    ensemble_median::Float64
    ensemble_sd::Float64
    monte_carlo_standard_error::Float64
    percentile_05::Float64
    percentile_10::Float64
    percentile_25::Float64
    percentile_75::Float64
    percentile_90::Float64
    percentile_95::Float64
end

struct ABMOriginDiagnostic
    variant::String
    origin_index::Int
    origin_period::String
    build_period::String
    calibration_date::String
    burn_in_quarters::Int
    simulated_quarters::Int
    t_prime::Int
    t_max::Int
    paths_requested::Int
    paths_used::Int
    paths_failed::Int
    calibration_seconds::Float64
    simulation_seconds::Float64
end

struct ABMWeightedScore
    sample_track::String
    target_set::String
    model_id::String
    benchmark_model_id::String
    status::String
    target_horizon_cell_count::Int
    expected_target_horizon_cell_count::Int
    minimum_common_observation_count::Int
    maximum_common_observation_count::Int
    model_failure_count::Int
    all_model_failure_count::Int
    failure_free::Bool
    weighted_macro_average_cellwise_rmse_ratio::Float64
    weighted_macro_average_cellwise_mae_ratio::Float64
end

struct MonteCarloError
    model_family::String
    target_id::String
    horizon::Int
    origin_count::Int
    monte_carlo_paths::Int
    mean_ensemble_sd::Float64
    mean_monte_carlo_standard_error::Float64
    maximum_monte_carlo_standard_error::Float64
end

struct ABMComparisonResult
    contract_id::String
    variant::String
    information_track::String
    panel_sha256::String
    panel_manifest_sha256::String
    panel_source_receipts_sha256::String
    periods::Vector{String}
    target_ids::Vector{String}
    model_ids::Vector{String}
    horizons::Vector{Int}
    monte_carlo_paths::Int
    burn_in_quarters::Int
    simulated_quarters::Int
    forecast_cells::Vector{ForecastCell}
    failures::Vector{DiagnosticFailure}
    abm_origin_diagnostics::Vector{ABMOriginDiagnostic}
    ensemble_summaries::Vector{EnsembleSummary}
    summaries::Vector{ScoreSummary}
    relative_scores::Vector{RelativeScore}
    weighted_relative_scores::Vector{ABMWeightedScore}
    monte_carlo_errors::Vector{MonteCarloError}
    benchmark_model_id::String
    abm_mean_model_id::String
    abm_median_model_id::String
    abm_path_failure_count::Int
    canonical_origin_count::Int
    observed_origin_count::Int
    path_incomplete_origin_count::Int
    minimum_paths_used::Int
    extra_column_provenance::Vector{Dict{String, Any}}
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

# ---------------------------------------------------------------------------
# period helpers
# ---------------------------------------------------------------------------

origin_index_for_period(period::AbstractString) =
    BASE.quarter_ordinal(period) - BASE.quarter_ordinal(PANEL_FIRST_PERIOD) + 1

function is_acute_pandemic_target(period::AbstractString)
    ordinal = BASE.quarter_ordinal(period)
    return ordinal >= BASE.quarter_ordinal(ACUTE_PANDEMIC_FIRST_TARGET_PERIOD) &&
        ordinal <= BASE.quarter_ordinal(ACUTE_PANDEMIC_LAST_TARGET_PERIOD)
end

function target_column(panel::QuarterlyPanel, target_id::AbstractString)
    matches = findall(==(target_id), panel.target_names)
    length(matches) == 1 ||
        throw(ArgumentError("panel must contain target $target_id exactly once"))
    return only(matches)
end

# ---------------------------------------------------------------------------
# ABM origin construction and simulation
# ---------------------------------------------------------------------------

"""
    simulate_abm_ensembles(variant, origins; paths, ...)

Free-run `paths` independent ensembles at every origin and reduce them to
per-target/horizon ensemble statistics. Results are appended to `cache_path`
after each origin, and any origin already present in the cache is skipped, so
an interrupted run resumes instead of restarting. Failed paths are counted and
never resampled.
"""
function simulate_abm_ensembles(
        variant::ABMVariant,
        origins::Vector{Tuple{Int, String}};
        paths::Int,
        cache_path::AbstractString,
        diagnostics_path::AbstractString,
        calibration_path::AbstractString = CALIBRATION_OBJECT_PATH,
        path_failures_path::Union{Nothing, AbstractString} = nothing,
        progress::Bool = true,
        identity_path::Union{Nothing, AbstractString} = nothing,
        identity::Union{Nothing, AbstractDict} = nothing,
        force_recompute::Bool = false,
        adopt_legacy_identity::Bool = false,
        allow_repair::Bool = true,
        upgrade_identity_schema::Bool = false,
    )
    identity_adopted = false
    identity_upgraded = false
    if identity_path !== nothing && identity !== nothing
        cache_present = isfile(cache_path) && filesize(cache_path) > 0
        if force_recompute
            directory = dirname(abspath(cache_path))
            removed = String[]
            for name in RUN_OWNED_SIMULATION_ARTIFACTS
                stale = joinpath(directory, name)
                isfile(stale) && (rm(stale); push!(removed, name))
            end
            # Explicit paths may sit outside the directory in tests.
            for stale in (cache_path, diagnostics_path, identity_path, path_failures_path)
                stale === nothing && continue
                isfile(stale) && (rm(stale); push!(removed, basename(stale)))
            end
            progress && println(
                "  --force-recompute: removed $(join(sort!(unique(removed)), ", "))",
            )
            cache_present = false
        end
        if !cache_present
            write_cache_identity(identity_path, identity)
        elseif !isfile(identity_path)
            # A cache produced before identity documents existed. Adoption is never
            # automatic: it records an assertion the operator is making.
            adopt_legacy_identity || throw(
                CacheIdentityError(
                    "path",
                    "$cache_path predates cache identity documents. Rerun with " *
                        "--adopt-cache-identity to stamp the current run identity onto " *
                        "it, or --force-recompute to regenerate it from scratch.",
                ),
            )
            write_cache_identity(
                identity_path,
                identity;
                adopted_from_legacy_cache = true,
            )
            identity_adopted = true
            progress && println(
                "  --adopt-cache-identity: stamped this run's identity onto a legacy cache",
            )
        else
            stored = read_cache_identity(identity_path)
            stored_schema = String(get(stored, "schema_version", ""))
            if stored_schema in (
                    CACHE_IDENTITY_SCHEMA_V1,
                    CACHE_IDENTITY_SCHEMA_V2,
                    CACHE_IDENTITY_SCHEMA_V3,
                    CACHE_IDENTITY_SCHEMA_V4,
                )
                upgrade_identity_schema || throw(
                    CacheIdentityError(
                        "schema_version",
                        "$identity_path predates the current identity schema and " *
                            "does not record every sealed component. Rerun with " *
                            "--upgrade-cache-identity to verify and raise it, or " *
                            "--force-recompute to regenerate.",
                    ),
                )
                on_disk_diagnostics = isfile(diagnostics_path) ?
                    filter(
                        row -> row.variant == variant.name,
                        read_struct_csv(diagnostics_path, ABMOriginDiagnostic),
                    ) : nothing
                write_cache_identity(
                    identity_path,
                    upgrade_cache_identity(stored, identity, on_disk_diagnostics),
                )
                identity_upgraded = true
                progress && println(
                    "  --upgrade-cache-identity: verified and raised $stored_schema to " *
                        "$CACHE_IDENTITY_SCHEMA",
                )
            else
                validate_cache_identity(
                    identity,
                    stored;
                    location = relpath(identity_path, REPOSITORY_ROOT),
                )
            end
        end
    end
    summaries = read_struct_csv(cache_path, EnsembleSummary)
    diagnostics = read_struct_csv(diagnostics_path, ABMOriginDiagnostic)
    completed = Set(
        row.origin_index for row in diagnostics if row.variant == variant.name
    )
    # Keep every row of this variant, including origins whose diagnostic row was
    # lost. Filtering to `completed` first hides an orphaned ensemble block from
    # detection, so the origin is regenerated and appended beside rows that were
    # never pruned -- 180 rows on disk after a "successful" resume.
    summaries = filter(row -> row.variant == variant.name, summaries)
    orphaned = setdiff(Set(getfield.(summaries, :origin_index)), completed)
    diagnostics =
        filter(row -> row.variant == variant.name, diagnostics)

    # Ensemble rows and diagnostics are appended separately, so an interruption
    # between the two writes can leave an origin with a partial row block that
    # still looks "completed". Any origin whose row count is not exactly
    # ENSEMBLE_ROWS_PER_ORIGIN is treated as absent and regenerated.
    grouped = Dict{Int, Vector{EnsembleSummary}}()
    for row in summaries
        push!(get!(grouped, row.origin_index, EnsembleSummary[]), row)
    end
    diagnostic_counts = Dict{Int, Int}()
    for row in diagnostics
        diagnostic_counts[row.origin_index] =
            get(diagnostic_counts, row.origin_index, 0) + 1
    end
    inconsistent = sort!(
        collect(
            union(
                Set(
                    index for index in completed
                        if !origin_grid_complete(
                            get(grouped, index, EnsembleSummary[]),
                        ) || get(diagnostic_counts, index, 0) != 1
                ),
                orphaned,
            ),
        ),
    )
    if !isempty(inconsistent)
        periods = Dict(
            row.origin_index => row.origin_period for row in diagnostics
        )
        described = join(
            (
                "$(get(periods, index, "?")) (index $index, " *
                    "$(length(get(grouped, index, EnsembleSummary[]))) of " *
                    "$ENSEMBLE_ROWS_PER_ORIGIN rows, " *
                    "$(get(diagnostic_counts, index, 0)) diagnostic row(s))"
                    for index in inconsistent
            ),
            ", ",
        )
        allow_repair || throw(
            CacheIdentityError(
                "ensemble_row_count",
                "cache at $cache_path is internally inconsistent for origin(s) " *
                    "$described; rerun with --force-recompute to regenerate, or " *
                    "restore the interrupted directory",
            ),
        )
        progress && println(
            "  discarding $(length(inconsistent)) interrupted origin(s): $described",
        )
        setdiff!(completed, inconsistent)
        summaries = filter(row -> row.origin_index in completed, summaries)
        diagnostics = filter(row -> row.origin_index in completed, diagnostics)
        # Prune on disk before anything is appended. Filtering in memory alone
        # leaves the bad rows in the file, so the regenerated origin is appended
        # beside them and every later resume re-detects and re-regenerates it --
        # the file grows without bound and never converges.
        rewrite_struct_csv(cache_path, summaries, EnsembleSummary)
        rewrite_struct_csv(diagnostics_path, diagnostics, ABMOriginDiagnostic)
    end

    path_failures = String[]

    pending = [entry for entry in origins if !(entry[1] in completed)]
    if isempty(pending)
        progress && println(
            "  all $(length(origins)) origins already cached for variant $(variant.name)",
        )
        if finalize_cache_identity(identity_path, identity, diagnostics)
            progress && println(
                "  repaired a stale identity left by an interrupted run",
            )
        end
        return (; summaries, diagnostics, path_failures, identity_adopted, identity_upgraded)
    end
    progress && println(
        "  simulating $(length(pending)) of $(length(origins)) origins " *
            "($(length(completed)) resumed from cache), $(paths) paths each",
    )

    started_all = time()
    for (origin_index, origin_period) in pending
        generated = generate_origin_ensemble(
            variant,
            origin_index,
            origin_period,
            paths,
            calibration_path,
        )
        origin_summaries = generated.summaries
        diagnostic = generated.diagnostic
        append!(path_failures, generated.path_failures)

        append_struct_csv(cache_path, origin_summaries, EnsembleSummary)
        append_struct_csv(diagnostics_path, [diagnostic], ABMOriginDiagnostic)
        append!(summaries, origin_summaries)
        push!(diagnostics, diagnostic)
        if path_failures_path !== nothing && !isempty(path_failures)
            open(path_failures_path, "a") do io
                for message in path_failures
                    println(io, message)
                end
            end
            empty!(path_failures)
        end

        # The per-origin timings and the surviving path count now live on the
        # diagnostic the sealed kernel returns; they are no longer locals of this
        # loop. Reading them off `generated` keeps the printed line identical to
        # the pre-extraction one while leaving the kernel untouched.
        progress && println(
            "  origin $origin_period (index $origin_index): " *
                "calibration $(round(diagnostic.calibration_seconds, digits = 2))s " *
                "simulation $(round(diagnostic.simulation_seconds, digits = 2))s " *
                "paths $(diagnostic.paths_used)/$paths " *
                "elapsed $(round(time() - started_all, digits = 1))s",
        )
    end
    sort!(diagnostics; by = row -> row.origin_index)
    sort!(
        summaries;
        by = row -> (row.origin_index, row.target_id, row.horizon),
    )
    # Persist the canonical order. Rows are appended per origin as they are
    # generated, so without this the file keeps generation order (target order as
    # declared) while the in-memory vectors -- and therefore every derived table --
    # are sorted. That split is why a clean regeneration reproduced every score
    # table byte-for-byte yet could not reproduce the cache's own sha256 seal: the
    # only writer that ever emitted sorted rows was the repair path below. Writing
    # the sorted order here makes the on-disk artifact canonical for every run,
    # so `abm_ensemble_summaries_sha256` and `forecast_cells_sha256` are
    # reproducible from scratch rather than only after a prune.
    rewrite_struct_csv(cache_path, summaries, EnsembleSummary)
    rewrite_struct_csv(diagnostics_path, diagnostics, ABMOriginDiagnostic)
    finalize_cache_identity(identity_path, identity, diagnostics)
    return (; summaries, diagnostics, path_failures, identity_adopted, identity_upgraded)
end

# ---------------------------------------------------------------------------
# cells, tracks and scores
# ---------------------------------------------------------------------------

"""
    abm_forecast_cells(panel, ensembles, variant)

Emit the thirteen-column `ForecastCell` schema for both ABM columns. The MASE
scale is recomputed from the panel exactly as the base diagnostic does, so the
scaled errors are comparable across models.
"""
function abm_forecast_cells(
        panel::QuarterlyPanel,
        ensembles::Vector{EnsembleSummary},
        variant::ABMVariant,
    )
    cells = ForecastCell[]
    scales_by_origin = Dict{Int, Vector{Float64}}()
    for row in ensembles
        row.horizon in BASE.HORIZONS || continue
        target_index = row.origin_index + row.horizon
        target_index <= length(panel.periods) || continue
        row.paths_used > 0 || continue
        column = target_column(panel, row.target_id)
        scales = get!(scales_by_origin, row.origin_index) do
            BASE.mase_scales(panel.values[1:(row.origin_index), :])
        end
        actual = panel.values[target_index, column]
        for (model_id, point) in (
                (variant.mean_model_id, row.ensemble_mean),
                (variant.median_model_id, row.ensemble_median),
            )
            error = point - actual
            push!(
                cells,
                ForecastCell(
                    model_id,
                    row.origin_index,
                    row.origin_period,
                    panel.periods[target_index],
                    row.target_id,
                    row.horizon,
                    point,
                    actual,
                    error,
                    abs(error),
                    error^2,
                    scales[column],
                    abs(error) / scales[column],
                ),
            )
        end
    end
    return cells
end

function comparison_relative_scores(summaries, model_ids, benchmark_model_id)
    by_key = Dict(
        (row.sample_track, row.model_id, row.target_id, row.horizon) => row
            for row in summaries
    )
    relative = RelativeScore[]
    for track in TRACKS
        for model in model_ids
            for target in ABM_TARGET_IDS
                for horizon in BASE.HORIZONS
                    key = (track, model, target, horizon)
                    benchmark_key =
                        (track, benchmark_model_id, target, horizon)
                    haskey(by_key, key) && haskey(by_key, benchmark_key) ||
                        continue
                    row = by_key[key]
                    benchmark = by_key[benchmark_key]
                    row.observation_count == benchmark.observation_count ||
                        throw(
                        ArgumentError(
                            "ABM comparison samples are not matched for $key",
                        ),
                    )
                    benchmark.rmse > 0.0 ||
                        throw(ArgumentError("benchmark RMSE must be positive"))
                    benchmark.mae > 0.0 ||
                        throw(ArgumentError("benchmark MAE must be positive"))
                    rmse_ratio = row.rmse / benchmark.rmse
                    push!(
                        relative,
                        RelativeScore(
                            track,
                            model,
                            benchmark_model_id,
                            target,
                            horizon,
                            row.observation_count,
                            rmse_ratio,
                            row.mae / benchmark.mae,
                            100.0 * (1.0 - rmse_ratio),
                        ),
                    )
                end
            end
        end
    end
    return relative
end

"""
    canonical_origin_count(panel)

The number of scored origins a full run of this contract covers, derived from the
panel rather than from CLI arguments. A run that covers fewer origins is a smoke
test and must not be labelled or ranked as a comparison.
"""
canonical_origin_count(panel::QuarterlyPanel) =
    length(BASE.MINIMUM_TRAINING_QUARTERS:(length(panel.periods) - 1))

"""
    path_complete_origins(diagnostics)

`(complete, incomplete, minimum_paths_used)` over the ABM origin diagnostics. An
origin counts as complete only when every requested path survived: paths are never
resampled, so a partially failed origin is a smaller ensemble wearing the same
label, not a complete one.
"""
function path_complete_origins(diagnostics)
    isempty(diagnostics) && return (0, 0, 0)
    complete = count(row -> row.paths_used == row.paths_requested, diagnostics)
    incomplete = length(diagnostics) - complete
    return (complete, incomplete, minimum(getfield.(diagnostics, :paths_used)))
end

function comparison_weighted_scores(
        relative,
        model_ids,
        benchmark_model_id,
        failures;
        canonical_origins::Int = 0,
        observed_origins::Int = 0,
        path_incomplete_origins::Int = 0,
    )
    all_model_failure_count = length(failures)
    # Sample adequacy is a property of the run, not of any one model column.
    origins_sufficient = canonical_origins > 0 && observed_origins >= canonical_origins
    paths_sufficient = path_incomplete_origins == 0
    output = ABMWeightedScore[]
    for track in TRACKS
        for (set_name, target_ids) in SCORED_TARGET_SETS
            target_weight = 1.0 / length(target_ids)
            expected_cells = length(target_ids) * length(BASE.HORIZONS)
            for model in model_ids
                selected = filter(
                    row ->
                    row.sample_track == track &&
                        row.model_id == model &&
                        row.target_id in target_ids,
                    relative,
                )
                selected_cells =
                    Set((row.target_id, row.horizon) for row in selected)
                complete =
                    length(selected) == expected_cells &&
                    length(selected_cells) == expected_cells
                total_weight = sum(
                    target_weight * BASE.HORIZON_WEIGHTS[row.horizon]
                        for row in selected;
                    init = 0.0,
                )
                observation_counts = getfield.(selected, :observation_count)
                minimum_count = isempty(observation_counts) ? -1 :
                    minimum(observation_counts)
                maximum_count = isempty(observation_counts) ? -1 :
                    maximum(observation_counts)
                model_failure_count =
                    count(failure -> failure.model_id == model, failures)
                failure_free = all_model_failure_count == 0
                if complete && total_weight ≈ 1.0 && failure_free &&
                        origins_sufficient && paths_sufficient
                    weighted_rmse = sum(
                        target_weight *
                            BASE.HORIZON_WEIGHTS[row.horizon] *
                            row.rmse_ratio for row in selected;
                        init = 0.0,
                    )
                    weighted_mae = sum(
                        target_weight *
                            BASE.HORIZON_WEIGHTS[row.horizon] *
                            row.mae_ratio for row in selected;
                        init = 0.0,
                    )
                    status = "COMPLETE_MATCHED"
                else
                    weighted_rmse = NaN
                    weighted_mae = NaN
                    status = if !origins_sufficient
                        "INSUFFICIENT_ORIGINS_SMOKE_ONLY"
                    elseif !paths_sufficient
                        "INCOMPLETE_PATH_COVERAGE_NOT_RANKED"
                    elseif complete && total_weight ≈ 1.0
                        "MATCHED_GRID_WITH_MODEL_FAILURES_NOT_RANKED"
                    else
                        "INCOMPLETE_MATCHED_GRID_NOT_RANKED"
                    end
                end
                push!(
                    output,
                    ABMWeightedScore(
                        track,
                        set_name,
                        model,
                        benchmark_model_id,
                        status,
                        length(selected),
                        expected_cells,
                        minimum_count,
                        maximum_count,
                        model_failure_count,
                        all_model_failure_count,
                        failure_free,
                        weighted_rmse,
                        weighted_mae,
                    ),
                )
            end
        end
    end
    return output
end

"""
    model_family(variant)

The ensemble's family label, derived from the variant so that a v2 run is never
labelled as v1. `beforeit_abm_us_v2_mean` -> `beforeit_abm_us_v2`,
`beforeit_abm_us_v1_mean_burnin` -> `beforeit_abm_us_v1_burnin`.
"""
model_family(variant::ABMVariant) = replace(variant.mean_model_id, "_mean" => "")

function monte_carlo_errors(
        panel::QuarterlyPanel,
        ensembles::Vector{EnsembleSummary},
        paths::Int,
        variant::ABMVariant,
    )
    family = model_family(variant)
    output = MonteCarloError[]
    for target_id in ABM_TARGET_IDS
        for horizon in BASE.HORIZONS
            selected = filter(
                row ->
                row.target_id == target_id &&
                    row.horizon == horizon &&
                    row.paths_used > 1 &&
                    row.origin_index + row.horizon <= length(panel.periods),
                ensembles,
            )
            isempty(selected) && continue
            dispersions = getfield.(selected, :ensemble_sd)
            standard_errors =
                getfield.(selected, :monte_carlo_standard_error)
            push!(
                output,
                MonteCarloError(
                    family,
                    target_id,
                    horizon,
                    length(selected),
                    paths,
                    mean(dispersions),
                    mean(standard_errors),
                    maximum(standard_errors),
                ),
            )
        end
    end
    return output
end

"""
    run_abm_comparison(panel, ensembles, diagnostics, variant; paths)

Merge the ABM ensemble columns into the ten-model statistical diagnostic and
score them on cells common to every model. This is a revised/mixed-vintage
research diagnostic: it is not a real-time forecast, an admitted origin, or
promotion evidence.
"""
function run_abm_comparison(
        panel::QuarterlyPanel,
        ensembles::Vector{EnsembleSummary},
        diagnostics::Vector{ABMOriginDiagnostic},
        variant::ABMVariant;
        paths::Int,
        extra_columns::Vector{Tuple{ABMVariant, Vector{EnsembleSummary}}} =
            Tuple{ABMVariant, Vector{EnsembleSummary}}[],
        extra_column_provenance::Vector{Dict{String, Any}} = Dict{String, Any}[],
        extra_origin_sets::Vector{Set{Int}} = Set{Int}[],
    )
    BASE.validate_panel(panel)
    base_result = BASE.run_revised_benchmark_diagnostic(panel)

    forecast_cells = filter(
        row -> row.target_id in ABM_TARGET_IDS,
        base_result.forecast_cells,
    )
    append!(forecast_cells, abm_forecast_cells(panel, ensembles, variant))
    # Additional ABM columns (e.g. the v1 baseline alongside v2) are scored on exactly
    # the same common cells, so the side-by-side delta cannot be a sample artifact.
    for (extra_variant, extra_ensembles) in extra_columns
        append!(
            forecast_cells,
            abm_forecast_cells(panel, extra_ensembles, extra_variant),
        )
    end

    failures = copy(base_result.failures)
    for diagnostic in diagnostics
        diagnostic.paths_used > 0 && continue
        for model_id in (variant.mean_model_id, variant.median_model_id)
            push!(
                failures,
                DiagnosticFailure(
                    model_id,
                    diagnostic.origin_index,
                    diagnostic.origin_period,
                    SIMULATION_HORIZON,
                    "abm_origin_without_usable_paths",
                    "ABMEnsembleFailure",
                    "every simulated path at this origin was unusable",
                ),
            )
        end
    end

    model_ids =
        [base_result.model_ids; variant.mean_model_id; variant.median_model_id]
    for (extra_variant, _) in extra_columns
        push!(model_ids, extra_variant.mean_model_id)
        push!(model_ids, extra_variant.median_model_id)
    end
    common_keys = BASE.common_cell_keys(forecast_cells, model_ids)
    common_rows =
        filter(row -> BASE.cell_key(row) in common_keys, forecast_cells)
    balanced_last_origin = length(panel.periods) - BASE.MAXIMUM_HORIZON
    balanced_rows =
        filter(row -> row.origin_index <= balanced_last_origin, common_rows)
    pandemic_masked_rows = filter(
        row -> !is_acute_pandemic_target(row.target_period),
        common_rows,
    )

    summaries = vcat(
        BASE.summarize_rows(
            ALL_AVAILABLE_TRACK,
            common_rows,
            model_ids,
            ABM_TARGET_IDS,
        ),
        BASE.summarize_rows(
            BALANCED_H12_TRACK,
            balanced_rows,
            model_ids,
            ABM_TARGET_IDS,
        ),
        BASE.summarize_rows(
            PANDEMIC_MASKED_TRACK,
            pandemic_masked_rows,
            model_ids,
            ABM_TARGET_IDS,
        ),
    )
    relative = comparison_relative_scores(
        summaries,
        model_ids,
        base_result.benchmark_model_id,
    )
    _, path_incomplete_origins, minimum_paths_used =
        path_complete_origins(diagnostics)
    # Canonicality is a property of the WHOLE scored field, not of the primary
    # column. A companion column covering fewer origins shrinks the common cell
    # set, so the narrowest included column governs the combined status.
    primary_origins = Set(getfield.(diagnostics, :origin_index))
    observed_origins = minimum(
        (length(set) for set in [primary_origins; extra_origin_sets]),
    )
    canonical_origins = canonical_origin_count(panel)
    weighted = comparison_weighted_scores(
        relative,
        model_ids,
        base_result.benchmark_model_id,
        failures;
        canonical_origins = canonical_origins,
        observed_origins = observed_origins,
        path_incomplete_origins = path_incomplete_origins,
    )

    return ABMComparisonResult(
        CONTRACT_ID,
        variant.name,
        panel.information_track,
        panel.panel_sha256,
        panel.manifest_sha256,
        panel.source_receipts_sha256,
        copy(panel.periods),
        copy(ABM_TARGET_IDS),
        model_ids,
        copy(BASE.HORIZONS),
        paths,
        variant.burn_in_quarters,
        SIMULATION_HORIZON + variant.burn_in_quarters,
        forecast_cells,
        failures,
        diagnostics,
        ensembles,
        summaries,
        relative,
        weighted,
        monte_carlo_errors(panel, ensembles, paths, variant),
        base_result.benchmark_model_id,
        variant.mean_model_id,
        variant.median_model_id,
        sum(getfield.(diagnostics, :paths_failed); init = 0),
        canonical_origins,
        observed_origins,
        path_incomplete_origins,
        minimum_paths_used,
        extra_column_provenance,
    )
end

# ---------------------------------------------------------------------------
# CSV helpers
# ---------------------------------------------------------------------------

function append_struct_csv(path, rows, ::Type{T}) where {T}
    headers = fieldnames(T)
    isfile(path) || open(path, "w") do io
        println(io, join(String.(headers), ","))
    end
    isempty(rows) && return path
    open(path, "a") do io
        for row in rows
            println(
                io,
                join(
                    (
                        BASE.csv_escape(getfield(row, field)) for
                            field in headers
                    ),
                    ",",
                ),
            )
        end
    end
    return path
end

parse_csv_field(::Type{String}, text) = String(text)
parse_csv_field(::Type{Int}, text) = parse(Int, text)
parse_csv_field(::Type{Float64}, text) = parse(Float64, text)
parse_csv_field(::Type{Bool}, text) = parse(Bool, text)

function read_struct_csv(path, ::Type{T}) where {T}
    rows = T[]
    isfile(path) || return rows
    lines = readlines(path)
    isempty(lines) && return rows
    headers = collect(String.(fieldnames(T)))
    String.(split(lines[1], ',')) == headers ||
        throw(ArgumentError("cache $path has an unexpected header"))
    types = fieldtypes(T)
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ',')
        length(fields) == length(headers) ||
            throw(ArgumentError("cache $path has a malformed row"))
        push!(
            rows,
            T(
                (
                    parse_csv_field(types[index], fields[index]) for
                        index in eachindex(headers)
                )...,
            ),
        )
    end
    return rows
end

# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------

toml_string(value) = repr(String(value))
toml_string_array(values) = "[" * join(toml_string.(values), ", ") * "]"

function repository_commit()
    try
        return readchomp(
            `git -C $(REPOSITORY_ROOT) rev-parse HEAD`,
        )
    catch
        return "unavailable"
    end
end

function repository_tree_clean()
    try
        return isempty(
            readchomp(`git -C $(REPOSITORY_ROOT) status --porcelain`),
        )
    catch
        return false
    end
end

function track_observation_counts(result::ABMComparisonResult, track)
    counts = Int[]
    for horizon in result.horizons
        selected = filter(
            row ->
            row.sample_track == track &&
                row.model_id == result.abm_mean_model_id &&
                row.target_id == first(result.target_ids) &&
                row.horizon == horizon,
            result.summaries,
        )
        push!(counts, isempty(selected) ? -1 : only(selected).observation_count)
    end
    return counts
end

function weighted_score(result::ABMComparisonResult, track, target_set, model_id)
    matches = filter(
        row ->
        row.sample_track == track &&
            row.target_set == target_set &&
            row.model_id == model_id,
        result.weighted_relative_scores,
    )
    return isempty(matches) ? nothing : only(matches)
end

function write_manifest(path, result::ABMComparisonResult, output_hashes)
    all_available_counts =
        track_observation_counts(result, ALL_AVAILABLE_TRACK)
    balanced_counts = track_observation_counts(result, BALANCED_H12_TRACK)
    pandemic_counts = track_observation_counts(result, PANDEMIC_MASKED_TRACK)
    lines = [
        "schema_version = \"beforeit-us-revised-data-abm-comparison-result.v1\"",
        "contract_id = \"$(result.contract_id)\"",
        "variant = \"$(result.variant)\"",
        "information_track = \"$(result.information_track)\"",
        "real_time = false",
        "origin_admissible = false",
        "promotion_eligible = false",
        "production_accuracy_score = false",
        "paper_parity_claimed = false",
        "abm_forecast_included = true",
        "mixed_vintage_structural_year = $MIXED_VINTAGE_STRUCTURAL_YEAR",
        "mixed_vintage_annual_structure_is_future_information_at_historical_origins = true",
        "h1_opening_row_transient = true",
        "monte_carlo_paths = $(result.monte_carlo_paths)",
        "mc_standard_error_reported = true",
        "burn_in_quarters = $(result.burn_in_quarters)",
        "simulated_quarters = $(result.simulated_quarters)",
        "model_scale = $(repr(MODEL_SCALE))",
        "ensemble_functional = \"pathwise_transform_then_ensemble_mean_and_median\"",
        "parallel_simulation = false",
        "resampling_of_failed_paths = false",
        "panel_sha256 = \"$(result.panel_sha256)\"",
        "panel_manifest_sha256 = \"$(result.panel_manifest_sha256)\"",
        "panel_source_receipts_sha256 = \"$(result.panel_source_receipts_sha256)\"",
        "start_period = \"$(first(result.periods))\"",
        "end_period = \"$(last(result.periods))\"",
        "comparison_target_count = $(length(result.target_ids))",
        "comparison_target_ids = $(toml_string_array(result.target_ids))",
        "headline_scored_target_ids = $(toml_string_array(HEADLINE_TARGET_IDS))",
        "secondary_scored_target_ids = $(toml_string_array(SECONDARY_TARGET_IDS))",
        "unscored_appendix_target_ids = $(toml_string_array(UNSCORED_APPENDIX_TARGET_IDS))",
        "unemployment_rate_excluded_from_weighted_scores = true",
        "unemployment_rate_exclusion_reason = \"initial unemployed stock is a length-one annual array frozen at 2024, so every historical origin opens at the 2024 labour market\"",
        "model_count = $(length(result.model_ids))",
        "model_ids = $(toml_string_array(result.model_ids))",
        "benchmark_model_id = \"$(result.benchmark_model_id)\"",
        "abm_mean_model_id = \"$(result.abm_mean_model_id)\"",
        "abm_median_model_id = \"$(result.abm_median_model_id)\"",
        "horizons = [$(join(result.horizons, ", "))]",
        "horizon_weights = [$(join((BASE.HORIZON_WEIGHTS[horizon] for horizon in result.horizons), ", "))]",
        "all_available_track = \"$ALL_AVAILABLE_TRACK\"",
        "balanced_h12_track = \"$BALANCED_H12_TRACK\"",
        "pandemic_masked_track = \"$PANDEMIC_MASKED_TRACK\"",
        "pandemic_mask_rule = \"exclude cells whose TARGET period falls in $ACUTE_PANDEMIC_FIRST_TARGET_PERIOD..$ACUTE_PANDEMIC_LAST_TARGET_PERIOD (frozen PT_ACUTE window); the masked track is PT_PRE plus PT_POST\"",
        "all_available_common_observation_counts = [$(join(all_available_counts, ", "))]",
        "balanced_h12_common_observation_counts = [$(join(balanced_counts, ", "))]",
        "pandemic_masked_common_observation_counts = [$(join(pandemic_counts, ", "))]",
        "forecast_cell_count = $(length(result.forecast_cells))",
        "failure_count = $(length(result.failures))",
        "failure_free = $(isempty(result.failures))",
        "abm_origin_count = $(length(result.abm_origin_diagnostics))",
        "abm_canonical_origin_count = $(result.canonical_origin_count)",
        "abm_observed_origin_count = $(result.observed_origin_count)",
        "sample_is_canonical = $(result.observed_origin_count >= result.canonical_origin_count)",
        "sample_completeness_semantics = \"a run earns COMPLETE_MATCHED only when it covers the canonical origin grid derived from the panel and every requested path survived at every origin; anything narrower is INSUFFICIENT_ORIGINS_SMOKE_ONLY or INCOMPLETE_PATH_COVERAGE_NOT_RANKED and is not a ranking\"",
        "abm_path_failure_count = $(result.abm_path_failure_count)",
        "abm_path_incomplete_origin_count = $(result.path_incomplete_origin_count)",
        "abm_minimum_paths_used = $(result.minimum_paths_used)",
        "abm_paths_are_never_resampled = true",
        "abm_origin_indices = [$(join(getfield.(result.abm_origin_diagnostics, :origin_index), ", "))]",
        "abm_origin_failed_path_counts = [$(join(getfield.(result.abm_origin_diagnostics, :paths_failed), ", "))]",
        "abm_origin_used_path_counts = [$(join(getfield.(result.abm_origin_diagnostics, :paths_used), ", "))]",
        "score_summary_count = $(length(result.summaries))",
        "relative_score_count = $(length(result.relative_scores))",
        "weighted_relative_score_count = $(length(result.weighted_relative_scores))",
        "monte_carlo_error_row_count = $(length(result.monte_carlo_errors))",
        "minimum_training_quarters = $(BASE.MINIMUM_TRAINING_QUARTERS)",
        "error_sign = \"$(BASE.ERROR_SIGN)\"",
        "truth_vintage = \"revised_mixed_vintage_snapshot\"",
        "weighted_ratio_formula = \"$(BASE.WEIGHTED_RATIO_FORMULA)\"",
        "weighted_ratio_semantics = \"$(BASE.WEIGHTED_RATIO_SEMANTICS)\"",
        "sample_policy = \"common target-horizon-origin score cells across the ten statistical models and both ABM columns; all-available, balanced-h12 and pandemic-masked reported separately\"",
        "known_comparability_limit = \"statistical models use the registered eight-target panel; the ABM is a structural simulator initialised from its own calibration artifact and shares only the score panel\"",
        "code_commit_sha = \"$(repository_commit())\"",
        "code_working_tree_clean = $(repository_tree_clean())",
        "comparison_code_sha256 = \"$(sha256_hex(read(abspath(@__FILE__))))\"",
        "base_diagnostic_code_sha256 = \"$(sha256_hex(read(BASE_DIAGNOSTIC_PATH)))\"",
        calibration_provenance_lines()...,
        "julia_project_sha256 = \"$(sha256_hex(read(BASE.PROJECT_PATH)))\"",
        "julia_version = \"$(VERSION)\"",
        "blas_threads = $(BLAS.get_num_threads())",
        "julia_threads = $(Threads.nthreads())",
        "seed_contract_id = \"$(SEED_CONTRACT_ID)\"",
        "cache_identity_schema = \"$(CACHE_IDENTITY_SCHEMA)\"",
        "reproducibility_note = \"seeds derive from Base.hash and are consumed through the default global RNG; both are version-bound, so exact regeneration requires the julia_version recorded above. Cross-version reruns are new experiments, not reproductions.\"",
    ]
    for (index, provenance) in enumerate(result.extra_column_provenance)
        push!(lines, "")
        push!(lines, "[[also_scored_column]]")
        push!(lines, "index = $index")
        for key in sort!(collect(keys(provenance)))
            value = provenance[key]
            rendered = value isa AbstractString ? "\"$(value)\"" : string(value)
            push!(lines, "$(key) = $(rendered)")
        end
    end
    for (track, label) in (
            (ALL_AVAILABLE_TRACK, "all_available"),
            (BALANCED_H12_TRACK, "balanced_h12"),
            (PANDEMIC_MASKED_TRACK, "pandemic_masked"),
        )
        for (set_name, _) in SCORED_TARGET_SETS
            for (model_id, model_label) in (
                    (result.abm_mean_model_id, "abm_mean"),
                    (result.abm_median_model_id, "abm_median"),
                )
                score = weighted_score(result, track, set_name, model_id)
                score === nothing && continue
                prefix = "$(model_label)_$(label)_$(set_name)"
                push!(lines, "$(prefix)_status = \"$(score.status)\"")
                push!(
                    lines,
                    "$(prefix)_weighted_rmse_ratio = $(repr(score.weighted_macro_average_cellwise_rmse_ratio))",
                )
                push!(
                    lines,
                    "$(prefix)_weighted_mae_ratio = $(repr(score.weighted_macro_average_cellwise_mae_ratio))",
                )
            end
        end
    end
    for (key, value) in sort!(collect(output_hashes); by = first)
        push!(lines, "$(key)_sha256 = \"$value\"")
    end
    write(path, join(lines, "\n") * "\n")
    return path
end

"""
    write_abm_comparison(result, output_directory)

Write the ABM comparison tables and manifest.
"""
function write_abm_comparison(
        result::ABMComparisonResult,
        output_directory::AbstractString,
    )
    mkpath(output_directory)
    paths = Dict(
        "forecast_cells" => joinpath(output_directory, "forecast_cells.csv"),
        "failures" => joinpath(output_directory, "failures.csv"),
        "abm_origin_diagnostics" =>
            joinpath(output_directory, "abm_origin_diagnostics.csv"),
        "abm_ensemble_summaries" =>
            joinpath(output_directory, "abm_ensemble_summaries.csv"),
        "score_summaries" =>
            joinpath(output_directory, "score_summaries.csv"),
        "relative_scores" =>
            joinpath(output_directory, "relative_scores.csv"),
        "weighted_relative_scores" =>
            joinpath(output_directory, "weighted_relative_scores.csv"),
        "monte_carlo_errors" =>
            joinpath(output_directory, "monte_carlo_errors.csv"),
    )
    BASE.write_struct_csv(
        paths["forecast_cells"],
        result.forecast_cells,
        ForecastCell,
    )
    BASE.write_struct_csv(paths["failures"], result.failures, DiagnosticFailure)
    BASE.write_struct_csv(
        paths["abm_origin_diagnostics"],
        result.abm_origin_diagnostics,
        ABMOriginDiagnostic,
    )
    BASE.write_struct_csv(
        paths["abm_ensemble_summaries"],
        result.ensemble_summaries,
        EnsembleSummary,
    )
    BASE.write_struct_csv(
        paths["score_summaries"],
        result.summaries,
        ScoreSummary,
    )
    BASE.write_struct_csv(
        paths["relative_scores"],
        result.relative_scores,
        RelativeScore,
    )
    BASE.write_struct_csv(
        paths["weighted_relative_scores"],
        result.weighted_relative_scores,
        ABMWeightedScore,
    )
    BASE.write_struct_csv(
        paths["monte_carlo_errors"],
        result.monte_carlo_errors,
        MonteCarloError,
    )
    hashes = Dict(name => sha256_hex(read(path)) for (name, path) in paths)
    manifest_path = joinpath(output_directory, "manifest.toml")
    write_manifest(manifest_path, result, hashes)
    hashes["manifest"] = sha256_hex(read(manifest_path))
    return (; paths, manifest_path, hashes)
end

"""
    write_abm_outlook(ensembles, diagnostics, output_directory; paths)

Write the unscored forward-looking ensemble table. These origins lie beyond the
end of the revised panel, so no realized truth exists and nothing here is
scored.
"""
function write_abm_outlook(
        ensembles::Vector{EnsembleSummary},
        diagnostics::Vector{ABMOriginDiagnostic},
        output_directory::AbstractString;
        paths::Int,
    )
    mkpath(output_directory)
    outlook_path = joinpath(output_directory, "current_outlook.csv")
    diagnostics_path =
        joinpath(output_directory, "abm_origin_diagnostics.csv")
    BASE.write_struct_csv(outlook_path, ensembles, EnsembleSummary)
    BASE.write_struct_csv(
        diagnostics_path,
        diagnostics,
        ABMOriginDiagnostic,
    )
    lines = [
        "schema_version = \"beforeit-us-revised-data-abm-outlook.v1\"",
        "contract_id = \"$CONTRACT_ID\"",
        "variant = \"outlook\"",
        "information_track = \"$INFORMATION_TRACK\"",
        "scored = false",
        "realized_truth_available = false",
        "real_time = false",
        "origin_admissible = false",
        "promotion_eligible = false",
        "abm_forecast_included = true",
        "mixed_vintage_structural_year = $MIXED_VINTAGE_STRUCTURAL_YEAR",
        "h1_opening_row_transient = true",
        "monte_carlo_paths = $paths",
        "mc_standard_error_reported = true",
        "model_scale = $(repr(MODEL_SCALE))",
        "ensemble_functional = \"pathwise_transform_then_ensemble_mean_and_median\"",
        "origin_periods = $(toml_string_array(unique(getfield.(diagnostics, :origin_period))))",
        "target_ids = $(toml_string_array(ABM_TARGET_IDS))",
        "horizons = [$(join(1:SIMULATION_HORIZON, ", "))]",
        "abm_origin_failed_path_counts = [$(join(getfield.(diagnostics, :paths_failed), ", "))]",
        "abm_origin_used_path_counts = [$(join(getfield.(diagnostics, :paths_used), ", "))]",
        "code_commit_sha = \"$(repository_commit())\"",
        "comparison_code_sha256 = \"$(sha256_hex(read(abspath(@__FILE__))))\"",
        calibration_provenance_lines()...,
        "julia_version = \"$(VERSION)\"",
        "current_outlook_sha256 = \"$(sha256_hex(read(outlook_path)))\"",
    ]
    manifest_path = joinpath(output_directory, "manifest.toml")
    write(manifest_path, join(lines, "\n") * "\n")
    return (; outlook_path, diagnostics_path, manifest_path)
end

end
