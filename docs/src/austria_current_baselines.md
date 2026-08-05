# Current Austrian baselines and forecasts

BeforeIT's original `AUSTRIA2010Q1` calibration remains useful for replication,
but it is no longer the most recent usable Austrian starting point. This
repository also contains:

- a **2024 Q4 structural baseline**, using the 2026 edition of Eurostat FIGARO
  for the 2024 production network;
- a **2026 Q1 nowcast baseline**, replacing the structural artifact's quarterly
  national-accounts, financial-balance-sheet, government, unemployment, and
  euro-area controls with data observed through 2026 Q1; and
- annual **baseline, upside, and downside assumptions for 2026–2031**, with a
  model adapter that converts the exogenous government-consumption, export, and
  import assumptions into quarterly paths.

The short answer to “is post-2010 data available?” is **yes, with different
publication lags**. The short answer to “is future data available?” is **no**:
2027–2031 values are forecast assumptions, not observations. A current
simulation must therefore separate slow-moving structural data, current
quarterly observations, and explicitly versioned future scenarios.

## Availability as of 29 July 2026

| Model input | Source and usable coverage | Latest point used | Treatment |
| --- | --- | --- | --- |
| Inter-country production and use network | [Eurostat FIGARO](https://ec.europa.eu/eurostat/web/esa-supply-use-input-tables/information-data), annual from 2010 to release year minus two | 2024 | Official 2026-edition 64-industry table. Eurostat may estimate recent-year supply/use cells before national tables arrive. |
| Annual national and industry accounts | Eurostat ESA 2010 tables | 2024 | Re-estimated through the pinned 11 February 2026 calibration snapshot. |
| Quarterly GDP and demand controls | [Eurostat dissemination API](https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data) | 2026 Q1 | Live values and each exact query URL/publisher timestamp are stored in the nowcast artifact. |
| Sector and household financial stocks, government debt/deficit, interest flows | Eurostat quarterly sector and government accounts | 2026 Q1 | Live controls replace their 2024 values. |
| Unemployment and euro-area controls | Eurostat quarterly labour-market, interest-rate, and national-accounts tables | 2026 Q1 | Live controls replace their 2024 values. |
| Enterprise counts | Eurostat SBS and business-demography tables | Mostly 2024 | 2024 SBS counts are used where covered; remaining legal-form sectors carry 2023 counts and are labelled as such. |
| Classification | [ÖNACE 2025 / NACE Rev. 2.1](https://www.statistik.at/ueber-uns/erhebungen/klassifikationsmitteilung/informationen-zur-oenace) applies from 2025 | Transition begins in 2025 | The model keeps its 62-sector NACE Rev. 2/FIGARO topology. New Rev. 2.1 sector data need a concordance before structural replacement. |
| Population | [Statistics Austria population projections](https://www.statistik.at/en/statistics/population-and-society/population/demographische-prognosen/population-projections-for-austria-and-federal-states) | Projection from 2025 | Available for demographic extensions, but not imposed in the supplied scenario adapter. |
| Short forecast | [OeNB June 2026 outlook](https://www.oenb.at/Publikationen/Volkswirtschaft/reports/2026/report-2026-17-prognose/html-version.html) | 2026–2028 | Published baseline, mild, and adverse GDP/HICP anchors; published baseline demand components. |
| Medium forecast | [WIFO May 2026 forecast](https://www.wifo.ac.at/en/publication/446452/) | 2026–2031 | Published medium-term baseline extends the scenario table to 2031. Post-2028 upside/downside values are transparent sensitivities around it. |

This layered treatment follows the model's published use as an Austrian
forecasting ABM in
[Poledna et al.](https://www.sciencedirect.com/science/article/pii/S0014292122001891)
and the reproducibility/extensibility goals described in the
[BeforeIT software paper](https://arxiv.org/abs/2502.13267).

## Reproduce the artifacts

The source registry in `scripts/austria/sources.toml` pins immutable source
archives by SHA-256, the exact `CalibrateBeforeIT.jl` Git revision, the live-data
vintage, and the official forecast publications. Raw downloads and intermediate
Parquet files are cached locally and are not committed.

```sh
julia --project=scripts/austria scripts/austria/bootstrap.jl
julia --project=scripts/austria scripts/austria/austria_pipeline.jl all
```

The first command instantiates the dedicated calibration environment. The
second verifies source checksums, maps FIGARO 2024 into the legacy A64 schema,
builds both baselines, refreshes the live controls, writes the scenarios, runs
accounting/finite-output checks, and executes a deterministic 2023 Q4–2024 Q4
backtest. Individual commands are `prepare`, `structural`, `nowcast`,
`scenarios`, and `validate`.

The immutable input archives total about 1.1 GB. Allow additional temporary
space for extraction and conversion. The first build is network- and
I/O-intensive; later builds reuse the ignored `scripts/austria/cache/`
directory.

## Load and simulate

```julia
import BeforeIT as Bit

artifact = Bit.load_austria_baseline(:nowcast)
model = Bit.Model(artifact.parameters, artifact.initial_conditions)
Bit.run!(model, 8; parallel = false) # Unconditional simulation from 2026 Q1
```

To run a conditional scenario through 2031 Q4:

```julia
model = Bit.build_austria_scenario_model(:baseline; horizon = 23)
Bit.run!(model, 23; parallel = false)

# Or run an ensemble:
models = Bit.run_austria_scenario(
    :downside;
    horizon = 23,
    simulations = 8,
    parallel = true,
)
```

The scenario CSV records GDP, HICP, private-consumption, investment, trade,
government-consumption, and budget-balance assumptions. GDP and HICP are
**comparison anchors** rather than hard targets. The current model adapter
directly conditions only the model's exogenous real government-consumption,
export-demand, and import-supply paths. Household consumption, investment,
prices, GDP, employment, credit, and public finances remain endogenous model
outcomes.

## Interpretation and update policy

The `2024Q4` artifact is the best fully aligned structural starting point. The
`2026Q1` artifact is the best current starting point, but it is a hybrid:
quarterly totals and balance sheets are current while its production network,
firm distribution, and other annual structural relationships remain anchored
to 2024. It should be called a **nowcast baseline**, not a 2026 structural
calibration.

For subsequent vintages:

1. refresh the pinned Eurostat snapshot and FIGARO edition;
2. update and test the Rev. 2.1-to-model sector concordance;
3. replace carried-forward enterprise counts when full observations arrive;
4. move `NOWCAST_PERIODS` and the calibration date to the latest complete
   quarter, preserving the exact API responses or query metadata;
5. replace the OeNB/WIFO scenario vintage and keep published values separate
   from derived sensitivities; and
6. rerun the accounting checks, deterministic backtest, and package tests.

The structural input lag cannot be removed by software. It can only be handled
honestly: use the latest official network, nowcast fast-moving controls, and
report forecast assumptions and structural carry-forwards in the artifact
metadata.
