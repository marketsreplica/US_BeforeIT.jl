# U.S. origin-package kernel

This directory contains the fail-closed boundary between archived data and a
forecast run. It does not yet implement the full 14-step origin runner in
`US_FORECASTING_PLAN.md`.

`USOriginPackages.jl` validates four hash-addressed artifacts:

1. An opening NIPA macro-control artifact containing GDP, PCE, gross private
   domestic investment, fixed investment, signed inventory investment,
   exports, imports, and government consumption plus gross investment. The
   validator independently recomputes both published identities and allows
   only the stated source-rounding tolerances.
2. `opening_macro_mapping.toml`, the semantic bridge from those source
   concepts to model concepts and fields. Every required mapping must be
   approved, supported by evidence, and assigned to different model-owner and
   independent-validator identities before this gate closes. The current gate
   is deliberately open.
3. An origin package linking the protocol, environment, macro control,
   mapping registry, model variant, parameter registry, and eight required
   origin blocks. Data releases and estimated-state cutoffs must not postdate
   the origin. A package is runnable only when every block is available, every
   gate passes, the semantic mapping gate is closed, and an
   `OriginReadinessResolver` independently resolves the declared artifacts
   and external gate results.
4. A derived cannot-run record that enumerates every unavailable block,
   nonpassing gate, and unapproved mapping. The record is rejected if a
   blocker is omitted, invented, changed, or linked to a different package.

All content digests use a typed, length-prefixed canonical encoding with map
keys sorted and array order preserved. The embedded `artifact.content_sha256`
field is excluded from its own digest. This makes TOML comments and key order
irrelevant while retaining type and sequence sensitivity.

Availability timestamps are not inferred from a vintage label. Each macro
control states whether its eligibility timestamp is an official release time
or the conservative completion time of an archived retrieval. A
current/revised snapshot must use the
`revised_mixed_vintage_diagnostic` information track and
`diagnostic_only_no_promotion` evidence class.

Run the hermetic tests with:

```text
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/origins/test_origin_packages.jl
```

The tests include negative inventory investment, identity manipulation,
post-origin leakage, falsified readiness, hash tampering, self-approval,
mixed-vintage mislabeling, and incomplete cannot-run records.

Declared readiness is not evidence of readiness. If a package would otherwise
resolve to `READY`, the caller must supply an `OriginReadinessResolver` whose
artifact-path keys are exactly the protocol, environment, macro source, and
all available origin-block IDs. Every resolved file must exist, must not be a
symbolic link, and is rehashed against the package before and after gate
validation. The resolver must also provide exactly one callable validator for
each required external gate; each callback must reproduce the declared
`status`, `reason`, and `evidence`. The macro-control identity and semantic
mapping checks remain built into this module.

This closes the former self-assertion path in which package TOML could claim
matching hashes and passing gates without opening the referenced bytes or
executing external validators. It is still an injection boundary, not an
external trust anchor: the production registry must freeze and attest the
approved validator identities before the first origin can be admitted.

The tracked current-vintage diagnostic binds every mapping's evidence to the
exact raw SHA-256 of `data/us/validation/ACCOUNTING_GATES.toml`. Its current
provenance chain is:

```text
accounting gate, raw SHA-256:      8884f6946ea76de65d3f99ce92bacd0bf5b7aa0a5f4717b8a7b8c12439018d7a
mapping, typed canonical SHA-256:  febe49f6f71425f170c1fd3ed6f95aea8f921751018f5457218e355f55e61047
origin, typed canonical SHA-256:   966af1b956f39f570a427a484a8cac8254cb6d5647f54d4aaaab91eb53c9a82f
cannot-run, typed canonical SHA:   d9b91e566deeee91dbff0057bb3d0f39bb809325750a0155439d2ebede1c93d8
```

The mapping gate remains open: six mappings are unresolved and inventory
investment is rejected as a flow-to-stock or discrepancy mapping. The
observation identity's pass supplies evidence only; it confers no mapping
approval. The current hermetic result is 62/62 assertions in both the default
and `--check-bounds=yes` modes.
