# Revised-data semi-structural comparison

This diagnostic adds the registered fixed-parameter quarterly
semi-structural state-space model to the existing revised-data U.S. benchmark
exercise. It compares eleven native-input models on the four target cells
common to all of them:

- real GDP growth;
- PCE price inflation;
- the unemployment rate; and
- the effective federal funds rate.

The ten statistical models retain their registered eight-target estimation
panel. The semi-structural model retains its registered four-target panel.
Forecast cutoffs and realized score cells are identical, but estimation target
panels are not. The result is therefore a transparent native-input comparison,
not a claim that every model used an identical regressor set.

The semi-structural model carries potential growth, an output gap, natural
unemployment, a neutral real rate, an inflation anchor, inflation, the policy
rate, and a lagged output gap. Its fixed transition contains IS, Phillips,
Okun, and Taylor-rule links. It updates latent states with an exact Kalman
filter at each origin.

It is explicitly **not a DSGE model**: there is no rational-expectations
solution, microfoundation, parameter posterior, origin-specific parameter
fitting, regime switching, or effective-lower-bound mechanism. Calling this
comparison “DSGE evidence” would be incorrect.

The underlying panel is current/revised and mixed-vintage. Consequently, the
comparison is research diagnostic evidence only. It is not a strict origin,
ABM result, production accuracy score, paper-parity result, or promotion
artifact.

Run the hermetic test:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_semi_structural_comparison.jl
```

Generate the ignored result tables:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/diagnostics/run_revised_data_semi_structural_comparison.jl
```

## Deterministic revised-data result

The canonical single-thread run spans 2000Q3--2025Q3, uses expanding windows
with a 40-quarter minimum, and scores horizons 1, 2, 4, 8, and 12. It produced
12,452 forecast cells, 671 model-origin diagnostics, 440 score summaries, and
zero failures.

Ratios below use registered VAR(1) as 1. A value below 1 is a lower loss than
VAR(1). The weighted statistic is a macro-average of cellwise ratios, with
equal target weights and preregistered horizon weights; it is not a ratio of
pooled losses.

| Sample track | Common observations at h=1/2/4/8/12 | Semi-structural RMSE ratio | Semi-structural MAE ratio | RMSE rank |
|---|---|---:|---:|---:|
| all available | 61 / 60 / 58 / 54 / 50 | 0.7488895447345775 | 0.8856658629411573 | 1 of 11 |
| balanced through h=12 | 50 / 50 / 50 / 50 / 50 | 0.7445969022111804 | 0.8730449475542831 | 1 of 11 |

The rank is among the eleven models executed here, not all fifteen registered
models. The registered seasonal-naive model and three direct-AR
implementations are not part of this diagnostic. A same-core4 VAR/BVAR
exercise is also still required to separate input-panel effects from model
structure.

The registered AR(1) ranks second on weighted RMSE and first on weighted MAE
on both tracks. The semi-structural model beats VAR(1) on RMSE in 19 of 20
all-available target-horizon cells and all 20 balanced cells. The
all-available exception is EFFR at horizon 1, with a ratio of
1.003388852007923. The aggregate advantage is especially strong for
unemployment, so this result must not be generalized to every target.

The comparison scores point forecasts only. Although the model implementation
can propagate fixed-parameter latent-state uncertainty, no predictive draws
or density scores are consumed here, and parameter uncertainty is absent.
The fixed coefficients and covariances are hash-bound, but they have not been
validated as empirical or literature estimates for this U.S. panel. VAR(1),
the ratio anchor, is unstable at the 2010Q2 origin (companion spectral radius
1.0342403057; design condition number 8,747.39); the run exposes rather than
filters that case.
No Diebold--Mariano/HAC, block-bootstrap, multiple-comparison, regime-slice,
or truth-vintage robustness inference has yet been run.

## Independent audit stress result

After the headline specification was run, an independent reviewer excluded
target realizations from 2020Q1 through 2021Q4 as an **unregistered stress
calculation**. The semi-structural weighted ratios and ranks changed as
follows:

| Sample track | RMSE ratio / rank | MAE ratio / rank |
|---|---:|---:|
| all available | 0.9849208060 / 5 of 11 | 1.0546117447 / 7 of 11 |
| balanced through h=12 | 0.9967595829 / 5 of 11 | 1.0647287406 / 7 of 11 |

The exclusion was not preregistered and is therefore not promoted to a formal
competing result or used to choose a preferred sample. It is an audit warning:
the headline rank is materially pandemic/regime-sensitive. The full sample
remains the headline result, consistent with the project plan, while a
literature-grounded regime definition and robustness matrix remain required
before any superiority claim.
