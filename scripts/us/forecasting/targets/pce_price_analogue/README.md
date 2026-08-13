# Synthetic household-consumption implicit-price analogue

This directory qualifies one deliberately narrow economic object:
`beforeit-household-consumption-implicit-price-analogue.v1`. Its strongest
status is `MODEL_OPERATOR_MECHANICS_VALIDATED_NONADMITTING`.

For caller-supplied synthetic raw paths of nominal household consumption
`N[path,t]` and real household consumption `R[path,t]`, it computes

```text
D[path,t] = N[path,t] / R[path,t]
q/q[path,t] = 400 * log(D[path,t] / D[path,t-1])
h4[path,t] = 100 * log(D[path,t] / D[path,t-4])
```

The four-quarter result is optional and is available only with at least five
strictly sequential quarterly rows. Every transform is evaluated separately
for every path before any ensemble summary. The module produces no summary;
the test fixture demonstrates that transforming a cross-path mean can differ
from averaging the pathwise transforms. A positive, time-invariant rebase of
`D` within a path cancels from both transformations.

These are continuous-log evaluation transforms. Any eventual comparison must
apply the same transform to direct official index levels; it must not substitute
BEA's published compounded annualized percent-change presentation.

The executable computation accepts only dense `Matrix{Float64}` level paths,
`Vector{String}` canonical sequential quarters, and contiguous one-based
`Vector{Int}` path identifiers. It rejects Boolean, missing, nonfinite, zero,
negative, non-dense, wrong-shape, or nonsequential inputs. It takes no model,
artifact, truth, forecast, score, origin, registry, or output path and performs
no file, network, model-execution, or write operation. Protocol and local
source-pin validation are separate read-only qualification checks.

## Claim boundary

The analogue is not the BEA total PCE price index, is not the BEA core PCE
price index, and is not an approved Tier-1 observation operator. BEA defines
chain-type price measures using adjacent-period Fisher indexes and
distinguishes them from implicit price deflators formed by dividing current
dollars by chained dollars; see the [NIPA Handbook, chapter
4](https://www.bea.gov/resources/methodologies/nipa-handbook/pdf/chapter-04.pdf).
[Chapter
5](https://www.bea.gov/resources/methodologies/nipa-handbook/pdf/chapter-05.pdf)
and BEA's [PCE price-and-quantity
FAQ](https://www.bea.gov/help/faq/521) describe component-specific PCE methods
and aggregation. The arithmetic qualified here does not reproduce those
methods.

Official PCE also has a broader and differently valued scope than an unlabeled
model household aggregate. BEA documents scope, weight, and formula differences
in its [PCE/CPI reconciliation FAQ](https://www.bea.gov/help/faq/555), NPISH
treatment in its [NPISH FAQ](https://www.bea.gov/help/faq/1009), and imputed
versus market transactions in its [market-based PCE
FAQ](https://www.bea.gov/help/faq/83). No bridge yet reconciles persons and
NPISH, payer and third-party flows, imputations, or purchaser-price taxes and
margins.

Core PCE needs an official detailed-purpose crosswalk and Fisher
reaggregation. BEA's [core definition](https://www.bea.gov/help/faq/518) and
official [food-and-energy composition
workbook](https://www.bea.gov/sites/default/files/2018-04/Composition%20of%20food%20and%20energy%20excluded%20from%20Core%20PCE%20Price%20Index.xls)
show why broad model sectors cannot simply be removed.

The protocol therefore leaves these blockers open:

- Fisher-chain equivalence;
- PCE/NPISH, payer, third-party, and imputation scope;
- purchaser-price tax and margin valuation;
- the core food/energy product crosswalk;
- exact direct-release vintages;
- seasonal-adjustment equivalence; and
- the opening price/basket stitch.

The last blocker is an executable prohibition. The model's initialization
sets opening real household consumption equal to opening nominal household
consumption, so opening `D0` is normalized to one. Joining that row to the
first post-step ratio crosses measurement regimes. This qualification permits
only homogeneous synthetic post-step-like rows and refuses any empirical
opening-to-first-step execution. Dropping or burning the opening row is not
silently authorized because it would change forecast-horizon semantics.

For post-step rows, the pinned model source sets nominal consumption to
`(1 + tau_VAT) * total_consumption` and real consumption to the same numerator
divided by `agg.P_bar_h`; their ratio is therefore `agg.P_bar_h` by
construction. That internal identity motivates the analogue name but supplies
no BEA concept equivalence.

The direct official selectors `NIPA/T20304/line 1/DPCERG` and
`NIPA/T20304/line 25/DPCCRG` are documented only for eventual total and core
truth acquisition. This directory loads neither series and contains no
release-vintage evidence. Exact local source bytes are SHA-256 pinned in the
self-hashed protocol. The BEA URLs are authoritative source locators, not
claims that remote bytes were archived or authenticated by this artifact.

## Verification

From the repository root:

```sh
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/targets/pce_price_analogue/test_pce_price_analogue_qualification.jl
```

The same command is also run from an unrelated temporary working directory
with absolute script and project paths. Passing establishes only the synthetic
mechanics status above. Origin admission, Tier-1 coverage, forecast emission,
scoring, inference, promotion, and production registration remain false.
