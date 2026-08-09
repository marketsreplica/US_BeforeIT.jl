# U.S. benchmark origin adapter

`USBenchmarkOriginAdapter.jl` is a hermetic seam between validated origin
packages, the benchmark kernel, the model registry, and forecast-registry v3
records. It has no acquisition path, no truth reader, and no empirical-origin
entry point. The test uses only an in-memory synthetic `OriginData` fixture.

The integration caller must perform these steps outside this module:

1. Validate the model registry with artifact verification and validate the
   Tier-1 target contract. Resolve the model and target-panel entry, derive its
   seal with `model_manifest_sha256`, and resolve the model-card artifact hash.
   Construct `ModelMetadata` from those values plus both registry/target
   contract hashes, registry status, support status, track, products,
   target-panel identity, and execution scope. Runtime product, track, target
   order, operator versions, and transformation versions must match that
   handoff exactly.
2. Copy the selected quarterly-unconditional product policy and canonical
   benchmark track from the validated protocol into `ProductMetadata`.
3. Build an exact `ForecastCell` cross-product for every registered benchmark
   target and requested horizon. Each cell binds its registry horizon to one
   output row and one `OriginData.forecast_keys` value.
4. Construct `OriginReadiness` with the exact protocol and origin-manifest
   hashes. This version additionally requires
   `evidence_class = "synthetic_fixture_only"` at execution.
5. Call `authenticate_origin_data` on the exact in-memory `OriginData`, binding
   its complete canonical bytes to the origin manifest, protocol, model-registry
   content, target contract, target panel, and sorted source artifacts. Pass the
   resulting `AuthenticatedOriginData` as the required
   `authenticated_origin_data` keyword.
6. Inject `USForecastRegistry.derive_seed_record`,
   `USForecastBenchmarks.model_id`, and
   `USForecastBenchmarks.run_benchmark` into `run_benchmark_origin`.
7. For density runs, materialize the draw cube outside this module and return
   its exact artifact hash through `distribution_hash_provider`.
8. Append every returned payload with `USForecastRegistry.append_forecast!`.

Both public adapter paths reject a missing, spoofed, internally tampered, or
sample-mismatched receipt envelope. The adapter deep-copies the caller sample,
checks its complete canonical bytes against the concrete
`USOriginDataReceipt` implementation, and uses only that validated copy for
context and benchmark execution. Receipt manifest/protocol hashes are matched
to `OriginReadiness`; registry-content, target-contract, and target-panel
bindings are matched to `ModelMetadata`; synthetic evidence and false empirical
authorization must agree across all three handoffs. `run_benchmark_origin`
revalidates the owned sample after the injected runner returns, detecting
accidental mutation.

The validated model-registry v1 scope remains
`hermetic_validation_only_no_empirical_forecasts` and explicitly sets both
empirical execution and production scoring to false. `ModelMetadata` preserves
and enforces those values. Well-formed hashes, a supported model row, or an
upstream origin marked `ready` are therefore not production authorization.

Every success and failure payload, and the returned adapter context, carries
`origin_data_sample_sha256` and `origin_data_receipt_sha256`. These establish
exact byte/provenance integrity, but they do not prove that the declared source
artifacts semantically produced the matrices. Before any future empirical
authorization, root integration must add a trusted origin-data builder and
transformation receipt. Until then, non-synthetic origins are refused.

`map_benchmark_run` applies the same receipt, sample, metadata, seed, and output
validation to an injected precomputed run. It cannot independently prove how
that run was produced because it did not invoke the benchmark runner. Its claim
therefore remains hermetic mapping integrity only, never execution provenance.

The adapter expands both successful and failed `BenchmarkRun` envelopes into
one exact registry payload per target/horizon attempt. A failed benchmark
therefore remains visible with a failure code, no point, no distribution
artifact, and zero registered draws.

## Track vocabulary integration

The protocol value `published_forecast` is canonical. The adapter emits that
value and explicitly rejects `published_information`. The forecast registry
must accept `published_forecast` before published-track payloads can be
appended; its temporary `published_information` vocabulary must not leak back
through this adapter.

Both `current_diagnostic` origins and
`revised_mixed_vintage_diagnostic` tracks are rejected even if their upstream
diagnostic package reports `ready`. `quarterly_unconditional` also requires
`OriginData.x_future === nothing`.

Ragged-edge nowcasts, ex-ante scenarios, and ex-post replication are rejected
by this adapter. They require a separate sealed conditioning/assumption
contract before they can be admitted.

Run the hermetic suite from the repository root:

```sh
julia --project=scripts/us --startup-file=no \
  scripts/us/forecasting/runner/test_origin_data_receipt.jl
julia --project=scripts/us --startup-file=no \
  scripts/us/forecasting/runner/test_benchmark_origin_adapter.jl
```
