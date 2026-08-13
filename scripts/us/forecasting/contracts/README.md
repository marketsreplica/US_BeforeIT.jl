# U.S. forecast protocol contract kernel

This directory implements the machine-checkable WS-0A contract used by
[`../protocol.toml`](../protocol.toml). The protocol is deliberately marked
`draft` / `pending_validation`: it is a concrete preregistration proposal, not
a model-owner or independent-validator signature and not evidence of forecast
skill.

`USForecastProtocol.jl` provides four public operations:

- `load_protocol()` parses and validates the TOML contract;
- `validate_protocol(protocol)` rejects missing, unknown, mistyped, or
  semantically inconsistent fields;
- `canonicalize_protocol(protocol)` emits a deterministic typed encoding with
  sorted map keys;
- `protocol_sha256(protocol)` and `protocol_artifact()` compute the lowercase
  SHA-256 of those canonical bytes.

The canonical digest is insensitive to TOML comments and table/key ordering.
Array order remains significant because ordered horizons, score lists, and
weights are part of the contract. Canonicalization never accepts an
unvalidated object.

The draft decisions are:

- issue the quarterly unconditional forecast at 10:00:00
  `America/New_York` on the first U.S. business day after the BEA advance GDP
  release, convert through the IANA timezone database, and store/compare
  timestamps as RFC 3339 UTC seconds;
- treat a release without an auditable intraday timestamp as ineligible and
  require `release_timestamp_utc <= origin_timestamp_utc`;
- keep quarterly unconditional forecasts, ragged-edge nowcasts, ex-ante
  scenarios, and ex-post paper conditionals in distinct ranking pools;
- score the operational Tier-1 panel at horizons 1, 2, 4, 8, and 12 against
  first, near-mature, and fixed-60-month mature truth;
- keep common-information and archived published-forecast benchmark tracks
  separate;
- require point and density evidence, at least 40 vintage-clean retrospective
  origins for horizons 1, 2, and 4, and eight consecutive prospective shadow
  origins;
- require every scientific, evidence-volume, point, density, robustness,
  incremental-value, reliability, and governance gate before promotion.

The 5% aggregate point/density non-inferiority margins, 10% critical-cell
point margin, 10 percentage-point absolute coverage tolerance, target/horizon
weights, and 2% incremental-value threshold are proposals pending economic
justification and independent validation. A material change after approval
must receive a new experiment version and digest.
