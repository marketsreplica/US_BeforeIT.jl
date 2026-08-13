# OriginData receipt contract v1

`USOriginDataReceipt.jl` provides deterministic integrity and provenance
scaffolding for a synthetic benchmark `OriginData`. It copies the complete
sample into an owned snapshot and seals that snapshot together with its
declared upstream artifact identities.

V1 is deliberately not production authorization:

- `evidence_class` is always `synthetic_fixture_only`;
- `empirical_execution_authorized` is always `false`;
- neither value is accepted from the caller;
- no builder approval, truth value, outcome, filesystem path, or source reader
  exists in the API.

The receipt proves that later validation sees the same bytes and provenance
identities that were sealed. It does not prove that the named source artifacts
semantically produced the matrices. Closing that semantic-derivation boundary
requires an independently validated origin-data builder and transformation
receipt.

## Owned sample

`authenticate_origin_data` validates and copies these fields:

1. `origin_id`
2. `origin_key`
3. `training_keys`, preserving type, value, and order
4. `forecast_keys`, preserving type, value, and order
5. `y_train`
6. `x_train`, including exact absence or presence
7. `x_future`, including exact absence or presence
8. `target_names`, preserving order
9. `predictor_names`, preserving order

Matrices must be exact `Matrix{Float64}` values with dimensions consistent
with their key and name vectors. Every element must be finite. Both exogenous
matrices must be present together or absent together.

Supported key types are exact `String`, `Date`, `DateTime`, and fixed-width
signed or unsigned integers from 8 through 128 bits. Boolean, floating-point,
symbolic, arbitrary-precision, composite, and caller-defined key types are
rejected. Training and forecast key vectors must use the exact same concrete
type as `origin_key`, remain strictly increasing, and obey the origin boundary.

The envelope owns its vectors and matrices. Mutation of the caller's original
sample after authentication cannot alter the sealed snapshot. A copied sample
is returned only after receipt validation. Direct mutation of the snapshot is
detected by the next validation.

## Canonical byte format

The canonicalization identifier is
`typed-length-prefixed-big-endian.v1`. It is independent of Julia
`Serialization` and host endianness.

Every encoded value is one frame:

```text
uint32_be tag_byte_length
tag_utf8_bytes
uint64_be payload_byte_length
payload_bytes
```

Records contain framed fields in the fixed order listed by this contract. An
ordered vector starts with a `uint64_be` element count followed by one typed
frame per element. Strings contain their exact UTF-8 code units.

Integer keys use an exact concrete-type tag and fixed-width two's-complement
big-endian bytes. `Date` uses signed day-count bits; `DateTime` uses signed
millisecond-count bits. Thus equal-looking values with different key types
produce different hashes.

A matrix frame contains:

```text
uint64_be row_count
uint64_be column_count
row_count * column_count IEEE-754 binary64 bit patterns
```

Elements follow Julia column-major linear order. Each binary64 pattern is
written as eight big-endian bytes. This preserves every bit, including the
difference between `+0.0` and `-0.0`. An absent matrix uses a distinct
zero-payload `Nothing` frame.

The sample record is domain-separated with:

```text
beforeit-us-origin-data-sample.v1
```

and contains the nine owned-sample fields in the order above.

## Provenance and hashes

The receipt binds:

- origin-manifest SHA-256;
- protocol SHA-256;
- model-registry content SHA-256;
- target-contract SHA-256;
- target-panel ID;
- a nonempty, sorted set of unique source-artifact IDs and SHA-256 values;
- the canonical sample SHA-256;
- the complete canonical sample bytes.

All hashes must be nonzero, lowercase, 64-character hexadecimal strings.
Source artifact IDs must be unique. Input source order is normalized by
artifact ID and hash; stored receipts must already be in that canonical order.

`sample_sha256` is SHA-256 over the domain-separated sample record.

`receipt_sha256` is SHA-256 over a record domain-separated with:

```text
beforeit-us-origin-data-receipt-self-hash.v1
```

The self-hash preimage includes every receipt field and the complete sample
except `receipt_sha256` itself. No other field is excluded.

For the pinned synthetic fixture in `test_origin_data_receipt.jl`:

```text
sample_sha256  = fdedf8ec447a3312f853d2533eef0d6bd1e52d4c6814c9a3d390b8caaa9ec6e8
receipt_sha256 = 4993f81d4f00b1c5388388921c0ce781bc211cc84f393399f9e5ef8af0bb4d90
```

## Validation boundary

`validate_origin_data_receipt` always reconstructs and validates the owned
snapshot, recomputes both hashes, and verifies all fixed receipt fields and
source provenance. Supplying an external sample additionally requires equality
of the complete canonical byte streams, not merely equality of their digests.

`USBenchmarkOriginAdapter` requires the concrete `AuthenticatedOriginData`
envelope for both public mapping paths. It deep-copies the caller's sample,
validates the copy against the receipt before preparing the run, and binds:

- origin-manifest and protocol hashes to `OriginReadiness`;
- model-registry content, target-contract, and target-panel identities to
  `ModelMetadata`;
- synthetic evidence to `OriginReadiness`;
- false empirical authorization to `ModelMetadata`.

`run_benchmark_origin` executes only the validated copy and revalidates it after
the runner returns. Every returned context and every success/failure forecast
payload contains the sample and receipt hashes. `map_benchmark_run` validates
an injected precomputed run but cannot independently establish how that run was
produced; its guarantee is hermetic mapping integrity, not execution
provenance.

Empirical admission remains blocked until a separate trusted builder proves the
semantic derivation from each sealed source artifact into these exact sample
bytes.
