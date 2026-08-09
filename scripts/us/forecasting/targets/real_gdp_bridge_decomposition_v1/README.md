# Real-GDP bridge decomposition v1

This isolated component separates three contracts that were previously
collapsed under `abm-to-bea-real-gdp.v1-draft`:

1. the official BEA A191RX adjacent-level transform;
2. the core-three `real_gdp` to `real_gdp_growth` identity alias; and
3. the ABM path measurement candidate.

Its maximum status is `REAL_GDP_BRIDGE_DECOMPOSED_NONADMITTING`. It does not
approve the ABM observation equation or make an empirical forecast eligible.

## Official target transform

The source selector is NIPA T10106 line 1, series A191RX, quarterly SAAR,
published as `millions_of_chained_dollars` with base year 2017. The normalized
Tier-1 spelling `millions_chained_2017_dollars_saar` is a factor-one name/base/
seasonal-basis alias, not a numerical conversion. Both adjacent positive level tokens must
come from the same exact artifact, release, vintage, unit, reference year,
and seasonal basis. The project observable is

```text
400 * (ln(level[t]) - ln(level[t-1]))
```

rounded to 12 decimal places with two independent MPFR precision checks. It
is a continuously compounded annualization. BEA's published headline growth
uses `100*((level[t]/level[t-1])^4-1)`, so the two formulas are deliberately
not treated as aliases. Multiplying both levels by a common SAAR or display
scale leaves the log change unchanged; mixing releases or vintages is
rejected. The observation constructor checks caller-supplied identity fields;
it does not reopen or authenticate the named source artifact, so its result
reports only `declared_identity_fields_equal`, never a proven release or
origin.

## Core-three alias

The accepted revised core-three fixture already stores the project log-growth
observable in its column named `real_gdp`. Mapping that column to model input
`real_gdp_growth` is an exact bitwise identity. No log, difference, annualize,
or scale operation is permitted a second time. This proves name/unit mechanics
only; the revised fixture remains non-real-time and nonadmitting.

## ABM boundary

The accepted ABM v5 source declares the first pair
`model_implied_opening_to_post_step_flow` and the later three pairs
`post_step_flow_to_post_step_flow`. The first pair is not comparable: the
constructor sets real GDP equal to a normalized-price, model-implied nominal
opening, while later rows use an additive formula after the completed market
and accounting step. Evaluating the later formula on the untouched constructor
state, burning a step, dropping h=1, or shifting horizon labels is forbidden.

The h=2--h=4 pairs are same-basis internal mechanics, but the additive model
flow has not been shown equivalent to official Fisher-chain real GDP. A valid
h=1 would require a completed origin-quarter flow from the same timing and
collector convention, obtained from a pre-origin filtered state and an
origin-quarter transition or an independently validated reconstruction.

The shared Tier-1 target and benchmark registry still attach the ABM-specific
draft operator label to the generic real-GDP target. Promotion therefore also
requires a successor registry migration that names the official source
transform, core-three alias, and ABM measurement bridge separately.

## Claim ceiling

The module reads and hashes pinned metadata/source files only. Its result
flags are scoped to operations owned by this bridge component; they do not
make claims about unrelated modules already present in the caller process. It does not
load the 318 official level values or claim that a synthetic arithmetic test
is an origin-bound observation receipt. It does not include any upstream
module, read raw truth values, construct or step the ABM,
fit a model, emit a forecast, score, admit an origin, mutate a registry,
approve an operator, promote, or register production use. Every downstream
gate remains false.

The official distinctions follow BEA's [NIPA Handbook chapter
4](https://www.bea.gov/resources/methodologies/nipa-handbook/pdf/chapter-04.pdf)
and [quarterly-growth FAQ](https://www.bea.gov/help/faq/122). The requirement
to preserve the information set follows the Philadelphia Fed's [Real-Time
Data Set for Macroeconomists](https://www.philadelphiafed.org/surveys-and-data/real-time-data-research/real-time-data-set-for-macroeconomists)
and Stark and Croushore (2002), DOI
[`10.1016/S0164-0704(02)00062-9`](https://doi.org/10.1016/S0164-0704(02)00062-9).

Run from the repository root:

```sh
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/targets/real_gdp_bridge_decomposition_v1/test_real_gdp_bridge_decomposition_v1.jl
```
