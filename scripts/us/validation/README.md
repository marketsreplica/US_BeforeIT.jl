# U.S. validation foundations

`USBitemporal.jl` is the first WS-1A query-layer slice. It validates the
minimum observation schema, selects only releases eligible at an exact UTC
origin, applies realtime validity intervals, fails on ambiguous latest
releases, and emits deterministic row and snapshot SHA-256 values.

Run the hermetic leakage fixtures with:

```sh
julia --project=scripts/us scripts/us/validation/test_bitemporal.jl
```

This module does not make the existing current-vintage data pseudo-real-time.
It is the fail-closed primitive that future archived source releases and
origin-manifest builders must use.

## Evidence-web reseal

Many contracts, policies, profiles and READMEs here cite other files by SHA-256.
Those citations form a web: rewriting one changes the citing file's own digest,
which invalidates every citation of *it*. `reseal_evidence_web.jl` closes that web
mechanically instead of one failing test at a time.

```sh
# what would change, against the last commit (default baseline is HEAD)
julia --project=scripts/us scripts/us/validation/reseal_evidence_web.jl

# against an explicit revision, writing the rewrites and iterating to a fixpoint
julia --project=scripts/us scripts/us/validation/reseal_evidence_web.jl \
  --baseline=<git-rev> --apply
```

For every tracked file whose bytes moved since the baseline it finds that file's
old digest and rewrites the digest wherever it is cited, repeating until nothing
moves. Ordering is deterministic, binary files are skipped, and
`US_FORECASTING_PLAN_WORK_LOG.md` is protected because a mechanical sweep must
never rewrite a historical record.

**Run it whenever any sealed file changes.** Reacting to individual CI failures is
unreliable: during the release that introduced this tool, chasing failures exposed
two stale citations while a single sweep found sixty-two.

**It does not compute semantic seals.** Several modules seal a canonicalised
projection of a document rather than its bytes -- `problem_scope_hash`,
`candidate_problem_hash`, an admission `evidence_hash`, an origin package's
content hash, the PCE protocol's content hash. Those must be re-derived by the
module that owns them; the tool prints the list when it applies rewrites. The
physical sweep and the semantic re-derivation converge jointly, usually in two
rounds: re-derive, sweep, repeat until both report no change.
