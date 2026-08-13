# Direct multi-step univariate AR benchmark

## Status and identity

This kernel is an isolated, hermetic benchmark implementation. It is not
origin-admitted until the forecasting registry and frozen-origin runner bind
its source hash and exact model identifier.

`DirectARSpec(candidate_lags=1, intercept=true)` and
`DirectARSpec(candidate_lags=4, intercept=true)` are the fixed-lag variants.
`DirectARSpec(candidate_lags=1:8, intercept=true)` selects a lag separately for
each target and horizon by BIC. The canonical candidate set, intercept choice,
implementation version, and density rule are all encoded in `model_id`.

## Point forecast

For target \(j\), horizon \(h\), historical forecast origin \(t\), and lag
order \(p\), the direct equation is

\[
y_{t+h,j} = c_{h,j}
  + \sum_{\ell=1}^{p}\beta_{h,j,\ell}y_{t+1-\ell,j}
  + e_{t,h,j}.
\]

The response is horizon-specific. At the live origin \(T\), the forecast uses
only \((y_{T,j},\ldots,y_{T-p+1,j})\). Within the training sample, the last
regression response is \(y_{T,j}\); there is no future-target input in
`OriginData`.

For BIC selection at horizon \(h\), every candidate is evaluated on historical
forecast origins

\[
\max(\mathcal{P}),\ldots,T-h,
\]

so candidates have exactly the same response dates. After selection, the
chosen lag is refitted on its full eligible origin window
\(p,\ldots,T-h\). Ties retain the smaller lag because candidates are
canonicalized in ascending order.

## Density forecast

The density construction preserves empirical dependence across both horizons
and targets without pretending that separately fitted point equations form a
recursive multivariate system.

After all direct regressions are fitted, their residuals are aligned on
historical forecast origins

\[
\max_{h,j}(p_{h,j}),\ldots,T-H.
\]

For each aligned origin, the residual vector is ordered as

\[
(e_{t,1,1},\ldots,e_{t,1,K},
  e_{t,2,1},\ldots,e_{t,H,K}).
\]

The kernel column-centers these vectors, estimates their corrected full sample
covariance, and adds one joint zero-mean Gaussian residual draw to the complete
point path. This makes the simulated errors coherent across horizons and
targets. A density run fails visibly unless there are more aligned origins
than joint dimensions and the centered residual matrix has full column rank.
Point-only forecasts do not require this covariance.

The draws are conditional plug-in draws. They exclude uncertainty in
coefficients, BIC selection, and the residual covariance. A fixed
`MersenneTwister` seed makes draws exactly reproducible.

## Information boundary and failure policy

- `x_train` and `x_future` are rejected, not silently ignored.
- No future realization of any target can be supplied through `OriginData`.
- Every design, response, coefficient, residual, and covariance must be finite.
- Every OLS design must have full column rank and residual degrees of freedom.
- Density covariance construction enforces aligned-sample, degrees-of-freedom,
  rank, and positive-definiteness checks.
- Any violation is retained as a structured failed `BenchmarkRun`; the model is
  never silently omitted or replaced.

## Literature and interpretation

Marcellino, Stock, and Watson define direct forecasts as horizon-specific
estimated models and emphasize that their relative accuracy against iterated
forecasts is empirical. Their broad U.S. macroeconomic exercise often favored
iterated forecasts, especially with longer selected lags; that result is
motivation for a controlled comparison, not a universal ranking:

Massimiliano Marcellino, James H. Stock, and Mark W. Watson (2006),
“A comparison of direct and iterated multistep AR methods for forecasting
macroeconomic time series,” *Journal of Econometrics* 135, 499–526.
[doi:10.1016/j.jeconom.2005.07.020](https://doi.org/10.1016/j.jeconom.2005.07.020)

Chevillon surveys why direct estimation can behave differently under
misspecification, nonstationarity, and horizon-specific design, while also
making clear that its merits depend on the setting:

Guillaume Chevillon (2007), “Direct Multi-Step Estimation and Forecasting,”
*Journal of Economic Surveys* 21, 746–785.
[doi:10.1111/j.1467-6419.2007.00518.x](https://doi.org/10.1111/j.1467-6419.2007.00518.x)

This implementation therefore makes no claim that direct forecasts dominate
the existing iterated AR. That claim can only be assessed from admissible,
vintage-clean out-of-sample origins under the frozen evaluation protocol.

## Known limitations

The point equations are linear and univariate. They contain no cross-target
lags, exogenous predictors, regularization, break handling, pandemic or
effective-lower-bound treatment, or time-varying parameters. Density draws are
Gaussian and do not propagate estimation or selection uncertainty. The full
joint covariance requirement can make density runs unavailable in short
samples or when \(H\times K\) is large. The BIC calculation is the Gaussian OLS
criterion and does not apply a HAC correction for the serial dependence induced
by overlapping multi-step residuals. These are intentional benchmark
boundaries, not claims about a preferred production model.
