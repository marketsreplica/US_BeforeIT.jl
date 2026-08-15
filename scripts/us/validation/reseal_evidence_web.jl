#!/usr/bin/env julia

# Re-seal the repository's evidence web after any sealed file changes.
#
#   usage: reseal_evidence_web.jl [--baseline=<git-rev>] [--apply] [--root=<dir>]
#
# Many contracts, policies, profiles and READMEs in this repository cite other
# files by SHA-256. Those citations form a web: rewriting one changes the citing
# file's own digest, which invalidates every citation of *it*. Chasing that web
# one failing test at a time is slow and unreliable -- during the release that
# introduced this tool, reacting to individual CI failures exposed two stale
# citations while a single sweep found sixty-two.
#
# This tool does the physical half of the job exhaustively and to a fixpoint:
# for every tracked file whose bytes differ from the baseline revision, it finds
# that file's old digest and rewrites the digest wherever it is cited, repeating
# until nothing moves.
#
# It deliberately does NOT invent semantic hashes. Several modules seal a
# canonicalised projection of a document rather than its bytes (for example
# `problem_scope_hash`, `candidate_problem_hash`, an admission `evidence_hash`,
# or a module's own `APPROVED_CONTRACT_SHA256` over a contract). Those must be
# re-derived by the module that defines them. When the sweep reaches a fixpoint
# it prints the semantic seals it knows about so the operator can re-derive them
# and run the sweep again; the two converge jointly, usually in two rounds.
#
# Default is a dry run. Nothing is written without `--apply`.

using SHA

const DEFAULT_BASELINE = "HEAD"

# Files whose historical text must never be rewritten by a mechanical sweep.
const PROTECTED = ("US_FORECASTING_PLAN_WORK_LOG.md",)

# Semantic seals a physical sweep cannot compute. Each entry names the seal and
# the command that re-derives it.
const SEMANTIC_SEALS = (
    (
        seal = "problem_scope_hash / candidate_problem_hash",
        owner = "scripts/us/accounting/USProductionReconciliationLedger.jl",
        rederive = "declared_scope_hash(raw) and build_production_reconciliation_ledger().problem_hash",
    ),
    (
        seal = "admission evidence_hash",
        owner = "scripts/us/accounting/USProductionReconciliationAdmissionEvidence.jl",
        rederive = "build_production_reconciliation_admission_evidence().evidence_hash",
    ),
    (
        seal = "APPROVED_CONTRACT_SHA256",
        owner = "scripts/us/accounting/US*.jl",
        rederive = "sha256 of the module's DEFAULT_CONTRACT_PATH (physical; this sweep handles it)",
    ),
    (
        seal = "runtime_source_tree_sha256",
        owner = "scripts/us/accounting/build_opening_accounting_candidate.jl",
        rederive = "source_tree_digest(runtime_source_tree_path); rebuild candidates afterwards",
    ),
    (
        seal = "opening_macro_mapping content_sha256 / origin package + cannot-run hashes",
        owner = "scripts/us/forecasting/origins/USOriginPackages.jl",
        rederive = "run test_origin_packages.jl and take the reported computed value",
    ),
    (
        seal = "PCE analogue protocol content_sha256",
        owner = "scripts/us/forecasting/targets/pce_price_analogue/USPCEPriceAnalogueQualification.jl",
        rederive = "compute_protocol_content_sha256(document)",
    ),
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

cli_option(args, name, default) = begin
    prefix = "--" * name * "="
    index = findfirst(argument -> startswith(argument, prefix), args)
    index === nothing ? default : args[index][(length(prefix) + 1):end]
end

"""
    tracked_files(root)

Every file git tracks, in git's own (deterministic) order.
"""
function tracked_files(root)
    output = read(Cmd(`git ls-files`; dir = root), String)
    return sort!(filter(!isempty, split(output, '\n')))
end

"""
    baseline_digest(root, revision, path)

The SHA-256 of `path` as of `revision`, or `nothing` when the file did not exist.
"""
function baseline_digest(root, revision, path)
    command = Cmd(`git show $(revision):$(path)`; dir = root)
    bytes = try
        read(pipeline(command; stderr = devnull))
    catch
        return nothing
    end
    return sha256_hex(bytes)
end

"""
    stale_digest_map(root, revision, paths)

`old digest => (new digest, path)` for every tracked file whose bytes moved since
the baseline. These are exactly the citations that need rewriting.
"""
function stale_digest_map(root, revision, paths)
    mapping = Dict{String, Tuple{String, String}}()
    for path in paths
        absolute = joinpath(root, path)
        isfile(absolute) || continue
        old = baseline_digest(root, revision, path)
        old === nothing && continue
        new = sha256_hex(read(absolute))
        old == new && continue
        mapping[old] = (new, path)
    end
    return mapping
end

"""
    sweep_once(root, paths, mapping; apply)

Rewrite every citation of a stale digest. Returns the list of rewrites performed
(or that would be performed, when `apply` is false). Binary files and protected
paths are skipped.
"""
function sweep_once(root, paths, mapping; apply::Bool)
    rewrites = Tuple{String, String, String, String, Int}[]
    for path in paths
        path in PROTECTED && continue
        absolute = joinpath(root, path)
        isfile(absolute) || continue
        text = try
            read(absolute, String)
        catch
            continue                      # not UTF-8: never a citation carrier
        end
        updated = text
        for old in sort!(collect(keys(mapping)))   # deterministic order
            occursin(old, updated) || continue
            new, source = mapping[old]
            count = length(collect(eachmatch(Regex(old), updated)))
            updated = replace(updated, old => new)
            push!(rewrites, (path, source, old, new, count))
        end
        if apply && updated != text
            write(absolute, updated)
        end
    end
    return rewrites
end

function main(args)
    root = abspath(cli_option(args, "root", pwd()))
    revision = cli_option(args, "baseline", DEFAULT_BASELINE)
    apply = "--apply" in args

    isdir(joinpath(root, ".git")) || isfile(joinpath(root, ".git")) ||
        throw(ArgumentError("$root is not a git working tree"))

    println("evidence-web reseal")
    println("  root      = $root")
    println("  baseline  = $revision")
    println("  mode      = $(apply ? "APPLY" : "dry run (pass --apply to write)")")

    paths = tracked_files(root)
    total = 0
    for pass in 1:20
        mapping = stale_digest_map(root, revision, paths)
        rewrites = sweep_once(root, paths, mapping; apply = apply)
        println("  pass $pass: $(length(rewrites)) stale citation(s)")
        for (path, source, old, new, count) in rewrites
            println("      $path")
            println("          cites $source  $(first(old, 10)) => $(first(new, 10))  x$count")
        end
        total += length(rewrites)
        isempty(rewrites) && break
        apply || break                    # a dry run reports one pass only
        pass == 20 && error("evidence web did not converge in 20 passes")
    end

    println("  total rewrites: $total")
    if apply && total > 0
        println()
        println("  Semantic seals are NOT computed by this tool. If any of the files")
        println("  below changed, re-derive their seals and run the sweep again:")
        for entry in SEMANTIC_SEALS
            println("      - $(entry.seal)")
            println("          owner:    $(entry.owner)")
            println("          rederive: $(entry.rederive)")
        end
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
