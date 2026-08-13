# RTDSM quarterly research acquisition

This directory implements a bounded, opt-in acquisition contract for exactly
five Federal Reserve Bank of Philadelphia Real-Time Data Set for
Macroeconomists quarterly vintage matrices:

- `NOUTPUTQvQd.xlsx`;
- `ROUTPUTQvQd.xlsx`;
- `PQvQd.xlsx`;
- `pconQvQd.xlsx`; and
- `PCONXQvQd.xlsx`.

The adjacent
`../rtdsm_quarterly_profile.json` is authoritative. The module refuses profile
drift from its reviewed 6,658-byte identity,
`6eb3a722dc6cfed72f16782f6f065a85de1bc0a3b2c1b733695c6338db1b593c`.
It also preserves the profile's conservative use-right boundary: research use
only; no authorization to redistribute raw files, commit them to Git, use
them commercially, reuse the Philadelphia Fed logo, or train a model.

## Evidence boundary

This capture is a present-day research diagnostic. It does not establish
historical or intraday availability, a strict forecast origin, truth, a model
input, an empirical score, inventory admission, production readiness, or
forecasting accuracy. `P` and `PCON` remain direct-mapping concept mismatches;
the capture does not relax any mapping caveat.

The receipt contains eleven gates. The only gate that may be true is
`research_diagnostic_allowed`. Training, origin, truth, model-input,
empirical-execution, inventory, production, and readiness gates remain false.

## Live acquisition

There is no implicit network path. A live run requires all four explicit
arguments:

```sh
julia --project=. \
  scripts/us/forecasting/vintages/rtdsm/acquisition/capture_rtdsm_quarterly.jl \
  --live \
  --raw-root /absolute/canonical/ignored/raw/root \
  --terms-reviewed-local-date YYYY-MM-DD \
  --research-purpose-attestation RESEARCH_DIAGNOSTIC_ONLY
```

Before running, review the Philadelphia Fed terms at
<https://www.philadelphiafed.org/about-us/privacy-notice>. The supplied date
must equal the capture date in `America/New_York`, resolved from the sealed
IANA TZDB 2026c semantics. The raw root must already exist, be absolute and
canonical, contain no symlink component, and be an ignored local data
location. This contract does not add a Git ignore rule and does not authorize
raw Git storage. If the root is inside the repository, the module requires a
successful `git check-ignore --no-index` result before any download; storage
outside the repository is accepted as outside Git scope.

The client requests only the five exact query-free HTTPS URLs on
`www.philadelphiafed.org`. Redirect following is disabled. Every response must
be HTTP 200, identity encoded, have a canonical matching `Content-Length`, stay
at or below 10 MB, use the XLSX media type, and pass bounded ZIP/XLSX central
directory checks. Response bodies are streamed into a bounded in-memory buffer;
the transport stage never closes and reopens a named temporary path.

## Transaction and storage

All five responses validate before storage begins. They are installed as one
transaction beneath:

```text
philadelphia_fed/rtdsm/quarterly/captures/
  bundle-sha256-<five-file-content-hash>/
    receipt-self-sha256-<receipt-hash>/
```

Each raw filename includes its series ID and SHA-256. A repeated byte bundle
with a different capture receipt receives a distinct receipt directory.
Staging is same-parent, files are written exclusively and read back, and the
sealed directory is installed with a platform atomic no-replace rename. A
racing target is validated, never overwritten. Bundle files are mode `0444`,
the leaf directory is mode `0555`, and hard-linked or symbolic-linked files
are rejected.

The canonical TOML receipt is self-hashed with its `receipt_sha256` field
omitted from the hash preimage. Validation recomputes the receipt, five-file
bundle hash, every raw hash and size, ZIP envelope, exact filename set,
profile/terms/timezone identities, timestamps, mappings, modes, link counts,
and gates.

## Hermetic tests

The test suite performs no network access:

```sh
julia --project=. \
  scripts/us/forecasting/vintages/rtdsm/acquisition/test_rtdsm_quarterly_acquisition.jl
```

It uses generated minimal ZIP/XLSX fixtures and covers profile tamper, URL and
redirect drift, terms/attestation/timezone refusal, HTTP and byte limits,
malformed and unsafe ZIPs, missing/reordered/aliased matrices, canonical
receipts, immutable storage, content tamper, symlinks, hard links,
receipt-specific repeated bytes, partial-transaction refusal, idempotence, and
exclusive-install races.
