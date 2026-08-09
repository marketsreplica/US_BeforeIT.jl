# BEA cross-archive revision-sensitivity diagnostic

This directory compares the exact checked-in 2019Q4 and 2021Q2 BEA HMI7
semantic fingerprints. It covers exactly five targets and 92 comparison
quarters, 1997Q1–2019Q4:

- nominal GDP;
- real GDP;
- GDP implicit price deflator;
- PCE price index; and
- core PCE price index.

For each target, the artifact contains complete quarterly rows and deterministic
summaries for:

1. the level revision, defined as the later archive observation minus the
   earlier archive observation;
2. the relative level revision in percent; and
3. the protocol primary transform revision, where each source transform is
   `400*ln(level_t/level_t_minus_1)`.

The transform reported for 1997Q1 uses 1996Q4 only as lag support. The
comparison periods themselves remain exactly 1997Q1–2019Q4. All calculations
use Python `Decimal` at precision 80 with round-half-even and are serialized as
decimal strings. Each complete row vector has its own SHA-256.

## Evidence boundary

The later 2021Q2 release includes BEA's 2021 annual update and revised history.
This is therefore a present-day, non-admitting sensitivity diagnostic. It is
not:

- a standard within-definition revision comparison;
- a truth artifact;
- a forecast origin;
- a score or accuracy result; or
- evidence of what was historically available at either release time.

The generator validates the exact source filenames and file SHA-256s, canonical
JSON, parser/mapping/raw-pair/release-profile identities, all five mappings,
the complete period window, positive decimal inputs, and hard-false source
gates. Its generated artifact repeats hard-false admission, execution,
inventory, production, and readiness gates at artifact, source, and target
scope. It never changes the vintage inventory.

## Regenerate

No network access or non-standard Python package is used:

```sh
python3 \
  scripts/us/forecasting/vintages/bea_nipa/historical_fingerprints/revision_diagnostic/build_revision_diagnostic.py
```

The default input is the adjacent `fingerprints/` directory and the default
output is this directory's `artifacts/` subdirectory. Repeated generation is
byte-identical and returns the existing content-addressed file.

## Test

```sh
python3 \
  scripts/us/forecasting/vintages/bea_nipa/historical_fingerprints/revision_diagnostic/test_revision_diagnostic.py
```

The standard-library suite covers official regeneration and adversarial source
identity, byte tamper, canonicalization, duplicate-key, gate, period, target,
mapping, release-profile, nonpositive, malformed-number, and output-path
failures. Publication uses a same-directory temporary file and an atomic
exclusive hard link, so a dangling symlink or concurrently created content
address is never overwritten. The temporary descriptor remains open through
publication; its inode and bytes are checked against the new destination
before success, so swapping the temporary pathname also fails closed.
