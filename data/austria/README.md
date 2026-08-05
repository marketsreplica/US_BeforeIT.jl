# Austria data artifacts

This directory contains the checked-in, versioned outputs of the Austrian
calibration pipeline:

- `baselines/`: ready-to-run parameter and initial-condition artifacts;
- `calibration/`: source calibration objects used to derive the baselines;
- `scenarios/`: annual published and derived assumptions through 2031;
- `validation/`: deterministic accounting checks and a one-year backtest; and
- `ARTIFACTS.toml`: byte sizes and SHA-256 hashes for this checked-in vintage.

Artifact metadata distinguishes observations, structural carry-forwards,
official recent-year FIGARO estimates, and future scenario assumptions. The
full source registry is `scripts/austria/sources.toml`; raw source archives and
intermediate files are intentionally excluded from Git.

See `docs/src/austria_current_baselines.md` for coverage, reproduction
instructions, API examples, and limitations.
