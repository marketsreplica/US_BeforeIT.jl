# BLS July 2026 capture rehearsal runbook

This is a one-shot, nonadmitting rehearsal for the July 2026 Employment
Situation release. It cannot create or promote a prospective origin.

## Fixed window

- Event: 2026-08-07 12:30:00 UTC
- Capture deadline: 2026-08-07 12:45:00 UTC
- Canonical request: unregistered, v1-compatible signature sent to the BLS v2
  endpoint for `CES0000000001` and `LNS14000000`
- Per-invocation API-attempt cap: 25

The 25-attempt limit is not evidence that the same public IP still has 25
anonymous requests available that day. Before either automated or manual
operation, coordinate all same-IP BLS API use and record prior query count.
Do not run the scheduled and manual collectors independently. This immutable
contract does not support adding a registration key.

## Primary GitHub Actions run

`.github/workflows/us-bls-202607-rehearsal.yml` is scheduled for 12:07 UTC and
waits until the fixed window. It must be merged to the repository’s default
branch before that time; GitHub runs schedules only from the default branch.
The workflow is inert on every date except 2026-08-07.
It pins Julia 1.10.3 and records the actual Julia version plus the SHA-256
digests of `scripts/us/Project.toml` and `scripts/us/Manifest.toml`. Its
transaction ID is derived from the GitHub run ID and run attempt so that a
rerun cannot collide with the primary attempt.

GitHub documents that scheduled jobs can be delayed or dropped. Treat the
workflow as the primary attempt, not as the sole operational control. Its
20-minute capture-step timeout is longer than the fixed 15-minute polling
window. Each API response is journaled incrementally, and accepted API bytes
are installed before either news route is attempted. The always-run upload
retains available bundles and failure journals for 90 days.

## Independent local backup

Have one operator ready on a host with Julia 1.10.3 and the exact clean merged
commit that contains this runbook and workflow. Record that commit before the
window; do not use a dirty checkout for the manual capture.
First confirm that the GitHub run has not started or consumed the anonymous
same-IP quota. From the repository root:

```sh
test -z "$(git status --porcelain)"
julia --startup-file=no --project=scripts/us -e 'using Pkg; Pkg.instantiate()'
GITHUB_SHA="$(git rev-parse HEAD)" \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/evidence/capture_bls_202607_rehearsal.jl \
  artifacts/bls-202607-rehearsal
```

Invoke the collector at or just after 12:30 UTC. Outside the fixed window it
fails closed and writes a diagnostic failure journal when possible.
The local collector adds a random 128-bit nonce to its timestamped transaction
ID. An operator-supplied `BLS_REHEARSAL_TRANSACTION_ID` may instead be used,
but it must be unique.

Receipt verification recomputes hashes of the collector and verifier source.
Archive the exact `USBLS202607RehearsalCapture.jl`,
`USBLS202607RehearsalReceipt.jl`, pinned v2 contract, and the U.S. Project and
Manifest with the complete output directory. Also record their SHA-256 digests.
The GitHub workflow does this automatically in `verification-context/`.
For a clean workflow or manual receipt, checking out its verified
`source_revision` is another reproducible route. If a manual operator omits the
checked `GITHUB_SHA` assignment, the receipt uses
`UNVERIFIED_LOCAL_WORKTREE`; it then has no checkout route and will become
unverifiable after source changes unless this exact context is archived.

## Network and diagnostic policy

Each live request uses a fresh downloader with redirects, netrc, cookies, and
ambient proxies disabled. Requests are direct-only, have a 12-second total
timeout, and enforce response limits of 1 MiB for the API, 2 MiB for HTML, and
8 MiB for PDF. A host that requires an HTTP proxy cannot run this collector
without a separately reviewed policy change.

Received API response bodies, including stale, non-200, invalid, and
capture-agent-reported metadata failures, are retained in two local
content-addressed copies. News attempts also produce a content-addressed
diagnostic with sanitized allowlisted headers and two copies of every complete
response body. Request exception text is not retained. The news diagnostic is
explicitly unbound to the API checkpoint: its shared transaction ID is
caller-reported correlation only, and it makes no claim that a full receipt was
installed.

## Required handoff

Preserve the entire output directory. A successful run contains an immediately
installed API-only bundle, possibly a second API-plus-news bundle, and immutable
attempt journals plus a news diagnostic. A controlled failure contains terminal
diagnostic journals when the failure occurs before news collection. Preserve
`runner-invocation.txt` as diagnostic context, not as an attestation. All
receipts, journals, and news diagnostics declare local integrity only, keep
external time and durability unattested, and set origin admission, readiness,
inventory mutation, and accuracy evaluation to false.
