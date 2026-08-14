# 2026Q1 current-vintage origin audit

This directory is a negative-control origin package. It is not a forecast
origin and must not enter an accuracy table.

The macro control is reconstructed from the archived BEA NIPA T10105 response
retrieved on 2026-08-04. Its annual-rate values are divided by four and both
published identities are checked. Because the archive stores millisecond
retrieval completion while the protocol compares RFC3339 timestamps at
seconds precision, `availability_timestamp_utc` is conservatively rounded up
to `2026-08-04T00:26:34Z`.

The package is labeled `revised_mixed_vintage_diagnostic` and
`diagnostic_only_no_promotion`. It cannot run because the local data are
current/revised retrieval snapshots rather than reconstructible historical
releases. The T10105 observation identity now passes at source rounding, but
latent state, supply/use valuation, inventory stock, and full accounting
remain failed; origin-specific dynamics and state are absent; the observation
operators are not frozen; parameter and variant approval gates remain open;
and no macro-to-model mapping is approved.

`cannot_run.toml` is derived from the package and the mapping registry. Its 21
failures are exhaustive under the current contract:

- six missing, pending, or rejected origin blocks;
- eight failed or pending gates;
- seven unresolved or rejected semantic mappings.

Hash bases in `origin_package.toml` are:

- canonical protocol content for `protocol_sha256`;
- raw `scripts/us/Manifest.toml` bytes for `environment_sha256`;
- canonical macro-control and mapping-registry content;
- canonical model-variant and parameter-registry content.

The environment hash is only a dependency-lock identifier. A runnable future
package must additionally pin the repository tree, Julia/runtime identity,
and execution image; this diagnostic cannot pass readiness regardless.

Any change to those blockers requires regenerating and revalidating the
origin package and cannot-run record. A passing synthetic fixture exists only
in the test suite to prove that the gate can close when independently
reviewed inputs are eventually available.

The current hash chain is:

```text
ACCOUNTING_GATES.toml raw SHA-256:
8884f6946ea76de65d3f99ce92bacd0bf5b7aa0a5f4717b8a7b8c12439018d7a

opening mapping typed-canonical SHA-256:
febe49f6f71425f170c1fd3ed6f95aea8f921751018f5457218e355f55e61047

origin package typed-canonical SHA-256:
966af1b956f39f570a427a484a8cac8254cb6d5647f54d4aaaab91eb53c9a82f

cannot-run typed-canonical SHA-256:
d9b91e566deeee91dbff0057bb3d0f39bb809325750a0155439d2ebede1c93d8
```

Every one of the seven mapping records cites the accounting-gate raw hash and
labels the candidate evidence observation-only. Six mappings remain
unresolved and inventory investment remains rejected. The cannot-run record
still contains exactly 21 blockers (six blocks, eight gates, seven mappings),
and the origin suite passes 62/62 assertions.
