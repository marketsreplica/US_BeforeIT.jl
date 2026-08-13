# Fixed-parameter quarterly semi-structural benchmark

## Status and scope

`SemiStructuralSpec` is a small linear-Gaussian state-space benchmark for four
US quarterly observables. It is a semi-structural model, not a DSGE model.
Every coefficient, covariance, and initial-state covariance is fixed in the
constructor before a forecast origin is processed. The origin calculation
uses the exact Kalman filter to update latent states; it does not fit, tune, or
select parameters.

Its density is a **fixed-parameter, conditional-on-hyperparameters
posterior-state predictive density**. It includes filtered-state uncertainty
and future process and measurement shocks. It excludes parameter uncertainty.
Consequently, this v1 benchmark does **not** satisfy a full
posterior-parameter density requirement and does **not** satisfy a DSGE
requirement.

## Observable contract

Inputs have exactly four columns in this order:

| Column | Target name | Required unit |
|---:|---|---|
| 1 | `real_gdp_growth` | annualized quarter-over-quarter percent |
| 2 | `pce_inflation` | annualized quarter-over-quarter percent |
| 3 | `unemployment_rate` | quarterly-average percent |
| 4 | `effective_federal_funds_rate` | quarterly-average percent |

`OriginData.target_names` is checked exactly. The contract is encoded as
`quarterly_core4_contract_v1` in the model identifier. `x_train` and
`x_future` are rejected: this benchmark is unconditional with respect to
future exogenous paths, and silently ignoring a supplied path is not allowed.
The `OriginData` interface has no future-target field.

## State and equations

The state is

```text
[potential growth, output gap, natural unemployment, neutral real rate,
 inflation anchor, inflation, policy rate, lagged output gap]
```

The fixed transition contains the intended economic links:

```text
IS:
gap[t] = rho_gap * gap[t-1]
       - alpha * ((policy[t-1] - inflation[t-1]) - neutral_rate[t-1])
       + shock_gap[t]

Phillips:
inflation[t] = rho_pi * inflation[t-1]
             + (1-rho_pi) * anchor[t-1]
             + kappa * gap[t-1]
             + shock_pi[t]

Taylor rule with interest-rate smoothing:
policy[t] = rho_i * policy[t-1]
          + (1-rho_i) * (
                neutral_rate[t-1] + anchor[t-1]
                + phi_pi * (inflation[t-1] - anchor[t-1])
                + phi_y * gap[t-1]
            )
          + shock_i[t]

Okun measurement:
unemployment[t] = natural_unemployment[t]
                - beta * gap[t]
                + measurement_error[t]

GDP-growth measurement:
gdp_growth[t] = potential_growth[t]
              + 4 * (gap[t] - gap[t-1])
              + measurement_error[t]
```

Potential growth, natural unemployment, the neutral real rate, and the
inflation anchor follow stationary AR(1) processes around constructor-fixed
means. Inflation and the policy rate are endogenous states, while the lagged
gap state makes the GDP-growth identity a standard contemporaneous
measurement equation.

## Filtering and prediction

For fixed system matrices,

```text
state[t] = c + A * state[t-1] + process_shock[t]
data[t]  = d + H * state[t]   + measurement_shock[t].
```

The implementation runs the ordinary prediction and update recursions with a
Joseph-form covariance update. Innovation covariances are factored directly:
there is no jitter, covariance inflation, missing-data substitution, or
approximate filter. The reported likelihood is the exact Gaussian likelihood
conditional on the constructor-fixed values.

The point forecast propagates the terminal filtered state mean. Each density
path uses one local `MersenneTwister` created from the explicit benchmark seed,
draws a terminal state from its filtered Gaussian distribution, and then
recursively draws the shared state transition and four-observable measurement
vectors. A path is therefore jointly coherent across targets and horizons.
Changing the seed changes draws but cannot change the point path.

## Validation and identity

Construction requires:

- finite scalar values;
- stationary scalar trend/anchor persistences;
- policy smoothing in `[0, 1)`;
- positive IS, Phillips, Okun, and Taylor-inflation coefficients;
- nonnegative Taylor output response;
- finite, symmetric, positive-semidefinite process, measurement, and initial
  covariances; and
- spectral radius below one for the complete transition matrix.

The model identifier ends in the SHA-256 of a versioned canonical parameter
payload. Every forecast-relevant `Float64` is represented in that payload by
its exact 16-digit IEEE-754 hexadecimal token. Full upper triangles represent
the three symmetric covariance matrices, and the observable-contract version
and GDP-growth annualization factor are included. Thus parameter identities do
not depend on rounded decimal rendering, and no forecast-relevant field is
omitted.

Runtime validation errors use the benchmark module's existing structured
failure envelope: `run_benchmark` returns `status == :failed` and a
`BenchmarkFailure` with `:invalid_input`, `:dimension_mismatch`,
`:estimation_failure`, or `:execution_failure` as appropriate.

## Known limitations

This is deliberately the smallest transparent kernel that carries the five
requested latent concepts and IS/Phillips/Okun/Taylor links. It has no
parameter posterior, origin-specific parameter fitting, stochastic
volatility, regime switching, effective-lower-bound treatment, survey or
other exogenous conditioning, nonlinear constraints, rational-expectations
solution, microfoundations, or DSGE equilibrium interpretation.
