# Synthetic ABM GDP operator-mechanics qualification

This directory qualifies only the arithmetic and horizon mapping of two
candidate U.S. Tier-1 ABM observation operators:

```text
real GDP growth =
  400 * log(real_gdp[t] / real_gdp[t-1])

GDP-deflator inflation =
  400 * log(
    (nominal_gdp[t] / real_gdp[t]) /
    (nominal_gdp[t-1] / real_gdp[t-1])
  )
```

The input rows are `model.data.real_gdp` and
`model.data.nominal_gdp`. `model.agg.Y` is gross firm output rather than the
recorded GDP measure. `model.data.real_gdp_ea` and
`model.data.gdp_deflator_growth_ea` are legacy external-block regressors.
None may substitute for the two contracted native measurement fields.

The formulas are applied to every raw path column before any ensemble
summary. Row one is the origin; row `h+1` maps to horizon `h`. Model GDP
flows are quarterly. Calibration's SAAR-to-quarterly division is a constant
that cancels from log growth, so the operator annualizes the quarterly log
change by 400 and does not multiply level paths by four.

## Scientific boundary

Passing this suite establishes
`MODEL_OPERATOR_MECHANICS_VALIDATED_NONADMITTING`, not an approved
observation bridge. The model's additive real-flow measure has not been
shown equivalent to BEA Fisher-chain real GDP. The model ratio has not passed
historical identities against direct NIPA Table 1.1.9 `A191RD` values.
Opening accounting, output scale, historical input lineage, truth layers,
and admitted origins remain unresolved.

The executable accepts only an explicitly labeled synthetic fixture. It
also requires an explicit raw/uncorrected path declaration and rejects
class-H, bridge-adjusted, origin-reanchored, and empirical paths. It cannot
construct or run the model, load truth, write a forecast, score, conduct
inference, admit an origin, change the Tier-1 inventory, approve an operator,
promote a result, or register a production artifact. The eight-target
promotion count therefore remains 0/8.

The synthetic-fixture, raw-path, truth, and correction flags are caller
assertions. This module cannot authenticate upstream provenance, and its
returned in-memory arrays are mutable test values rather than a sealed
artifact. Source pins reject symlinks in relative source components and
resolve inside the supplied repository root; a symlink supplied as the root
itself is allowed. A later empirical operator will still require independently
bound path, seed, lineage, and validation receipts.

The conceptual decisions follow the
[BEA NIPA Handbook](https://www.bea.gov/sites/default/files/methodologies/nipa-handbook-all-chapters.pdf),
which defines an implicit price deflator as 100 times current-dollar value
divided by the corresponding chained-dollar value. That identity supports
the candidate arithmetic but does not prove that the model's two internal
aggregates match the official concepts. The distinction between current
archive content and data actually available at a historical origin follows
[Croushore and Stark](https://doi.org/10.1016/S0304-4076(01)00072-0).

Run from the repository root:

```sh
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/targets/abm_gdp_operator/test_abm_gdp_operator_qualification.jl
```
