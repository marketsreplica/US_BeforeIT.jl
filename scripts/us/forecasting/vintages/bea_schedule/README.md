# BEA prospective schedule monitor

This directory closes one narrow prospective-origin planning gap: it can
revalidate and snapshot the mutable official
[`https://www.bea.gov/news/schedule`](https://www.bea.gov/news/schedule) page.
The strict contract requires exactly one press-release row with:

- date `October 29`;
- time `8:30 AM`; and
- title `GDP (Advance Estimate), 3rd Quarter 2026`.

A moved, renamed, duplicated, or structurally unrecognized target row fails
closed. A different release at the same date and time cannot satisfy the
contract because matching begins with the exact GDP title.

## Evidence boundary

Successful output is
`MUTABLE_SCHEDULE_SNAPSHOT_ONLY_NOT_RELEASE_OR_ORIGIN_EVIDENCE`. It establishes
only that the fetched mutable schedule page contained the expected row at the
retrieval time recorded in metadata. It is not:

- GDP release content or release-byte evidence;
- evidence that the release actually occurred at the scheduled time;
- exact origin-availability or first-state evidence;
- an inventory or admission mutation; or
- an admissible origin or READY forecast package.

The live command writes the exact downloaded HTTP response-body bytes to a
SHA-256-addressed `.html` filename. It then writes sorted TOML metadata to a
filename addressed by the SHA-256 of those exact metadata bytes. Metadata
records the raw-body hash, response headers used for audit context, the strict
event match, and the non-admitting scope. The caller controls the output
directory and its retention; neither the command nor a GitHub Actions upload
is a permanence or future-availability guarantee.

## Hermetic test

Run:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_schedule/test_bea_schedule_monitor.jl
```

This test is network-free. Its one HTML fixture is a normalized, structurally
faithful subset containing exactly the target row. It is not a raw source
response. `fixtures/fixture_manifest.toml` records the fixture hash and that
distinction.

## Opt-in live snapshot

Create an explicit output directory, then run:

```sh
mkdir -p artifacts/bea-schedule
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_schedule/live_snapshot.jl \
  --live artifacts/bea-schedule
```

The command uses Julia standard libraries, HTTPS, a 30-second request timeout,
and a 2 MB accepted-body limit. It requires HTTP 200, the unchanged official
effective locator, an HTML content type, and the exact expected event. It
writes nothing to forecasting inventory, plan, admission, or origin-package
paths.

The scheduled workflow runs the hermetic test, performs this opt-in live
snapshot, conditionally uploads the two hash-addressed files as a named
short-retention Actions artifact, and then runs the separate prospective
receipt deadline guard. A network or validation failure remains a failed
workflow step; the deadline guard is still attempted and cannot be bypassed
by the schedule monitor.
