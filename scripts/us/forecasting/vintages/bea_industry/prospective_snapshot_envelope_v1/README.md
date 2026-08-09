# Prospective snapshot envelope v1

`USProspectiveSnapshotEnvelopeV1` is a reusable, Julia-stdlib-only boundary for
preserving one prospectively observed HTTPS artifact. It validates inert
`FetchResponse` values and ZIP/OOXML evidence without opening a socket. Its only
capture entry point, `capture_with_fetcher`, requires both an injected transport
and `execute_live=true`; the default path is a zero-request, zero-write dry run.
There is deliberately no built-in HTTP client.

## Closed transport boundary

A source adapter supplies a `CapturePolicy` with one exact HTTPS URL and host,
ordered request headers, allowed media types, an optional expected body digest,
capture times, and request/body/header/time caps. Validation requires:

- HTTP 200, the exact requested and effective URL, no redirect, no retry, and
  parsed response headers retained in order;
- exact HTTP-token header names, no surrounding whitespace or controls, and no
  conflicting duplicate `Content-Type`, `Content-Encoding`, or `Content-Length`;
- absent or `identity` content encoding and a body length/digest inside the
  closed policy;
- transport assertions that no proxy, netrc, request cookie, or credential
  header was used; and
- monotone millisecond UTC timestamps inside the capture window.

The local terms-review date must equal the UTC date of both callback-authorization
clock samples and the response's request-start assertion. This is a closed
comparison rule, not proof that a human review occurred or legal advice.

Those transport flags, local clocks, actor names, and terms-review statements
remain unauthenticated local assertions. Parsed headers are not raw wire bytes;
the receipt fixes `raw_wire_headers_preserved=false` and carries that blocker.

## Exactly-once storage and reconstruction

Before any transaction mutation, a typed `ClockSource` must return a sample in
the closed capture window. After the exclusive lock and private recovery journal
are durable, the envelope resamples the clock and gates the window again. The
fetch callback is the next effectful operation. An early or late sample at either
gate makes the callback unreachable; response-supplied timestamps never
authorize callback reachability. Both passing samples are stored as
`UNAUTHENTICATED_LOCAL_HOST_CLOCK_ASSERTION` evidence and reconstructed during
validation.

The journal marks that a request may have begun before calling the transport. A
pre-existing final bundle, quarantine, journal, staging directory, or lock
suppresses a duplicate request. Recovery can publish an already complete, fully
validated staging bundle or quarantine; an uncertain or incomplete request state
fails closed with `no retry allowed`.

Successful preservation creates two separately written, fsynced, reread files
for each of the raw body, parsed transport evidence, and local attestation. The
replicas must have distinct inodes and link count one. Optional externally
timestamped token bytes also receive two copies and require an injected verifier.
If no provider is supplied, `external_timestamp.established=false`.

The final validator rejects symbolic links at every internal path, hard-linked
material files, unknown directories/files, writable sealed material, replica
drift, and inconsistent journal/lock state. It rederives the response from the
raw and transport replicas, reruns the adapter selector, reconstructs the entire
receipt, and reconstructs the entire manifest. Matching self-hashes alone are
not sufficient. Every integer-valued control is exact-typed; TOML `Float` and
`Bool` aliases cannot impersonate counts, byte limits, durations, statuses, or
header sequences even after coordinated self-rehashing.

Both replicas live in one local filesystem fault domain. The protocol records a
fault-domain count of one and does not call this independent archival custody.

## Received-invalid quarantine

Once the fetcher has returned a typed response, response, selector, and timestamp
evidence failures do not discard the observed body. The envelope first seals a
separate nonadmitting quarantine with two independently written/fsynced/reread
copies of the raw body, untrusted parsed transport, and local attestation. A
reconstructed failure record and quarantine manifest bind the raw hash, failure
phase/code, policy, and closed gates. The validator applies the same inode,
hard-link, symlink, mode, exact-file-set, journal, and reconstruction checks.

A quarantine contains no completion receipt or selector/profile evidence. Its
only success status is `VALIDATED_NONADMITTING_QUARANTINE_NO_RETRY`; every
origin/admission/promotion/scoring gate remains false, and later calls suppress a
duplicate request. Parsed transport fields and failure details remain
unauthenticated assertions, while the raw replicas preserve exactly the bytes
that the typed fetcher returned.

## ZIP and OOXML boundary

The module includes a bounded parser for classic non-ZIP64 archives. It checks
the terminal EOCD, central/local header agreement, exact member names, path
traversal, encryption, entry and aggregate-size caps, methods, sizes, and CRC
metadata. `verify_member_payload` independently recomputes the selected member's
CRC-32, byte count, and SHA-256. `verify_ooxml_workbook` applies that check to
`xl/workbook.xml`, requires the core XLSX members, rejects DTD/entity hazards and
duplicate decoded sheet names, and validates exact required sheets.

The generic module does not implement DEFLATE or launch an extractor. An adapter
may rely on a precommitted whole-archive digest plus preregistered member/OOXML
identities, or inject independently extracted bytes for the stronger payload
audit. The BEA adapter does both in its offline verification tests.

## Scientific gates

The envelope never writes a source inventory, model state, forecast, score, or
promotion record. Every origin, empirical-forecast, accuracy, production,
inventory-mutation, and promotion gate is hard false. A valid bundle is capture
evidence only.

## Verification

From the repository root:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_industry/prospective_snapshot_envelope_v1/test_prospective_snapshot_envelope_v1.jl
```

The accepted local run passes 190 assertions, including exact dry-run behavior,
header and ZIP/OOXML adversaries, both early/late clock gates with zero callback
calls, wrong-hash/content-type/selector quarantines, quarantine no-retry and
self-rehash adversaries, Float/Bool integer-alias mutations across manifests,
receipts, transports, and quarantine, exactly-once suppression, recovery of a
durable rename with a lagging journal, interrupted-request recovery refusal,
inode/symlink/hardlink checks, receipt/manifest reconstruction, and
available/unavailable external timestamp paths.

Frozen implementation identities for this version are:

- module: `cb8fffd626c019fa6ce65a32664a46d1ecd87d3337f72ea378900d2d4f05b165`
- tests: `ae36445f9b7af77fa8a93a945bab2109382c881e2942c71c78f9252a29470d1e`
