# U.S. BeforeIT calibration: data, acquisition, and storage plan

Last investigated and link-checked: **2026-08-06**.

This document is the implementation specification for building a United States
calibration of BeforeIT. It is based on the actual fields read by
[`src/utils/calibration.jl`](src/utils/calibration.jl), not only on a generic
macroeconomic data wish list.

## Executive decision

1. **A national first version can be built entirely from public data.** No
   commercial purchase is required for the U.S. structural calibration.
2. Use the **BEA summary system with 71 source industries and 68 modeled
   commodities** as the canonical dimensional contract. BEA Table 259 supplies
   68 commodity rows and 71 industry columns; the four retail source
   industries are aggregated to the observed `4A0` retail commodity before
   constructing the symmetric bridge. A governed industry-technology
   diagnostic now produces a 70×70 commodity system with `Other` and `Used`
   explicit; it is not reduced to the model's 68×68 core until the common
   valuation and closure-account policies are approved. This is the closest
   U.S. analogue to the 64-sector European FIGARO input used by the existing
   calibration. BEA's after-redefinitions direct-requirements and market-share
   workbooks now supply the primary `A = B*D` commodity comparator, with Table
   59 inversion retained only as a published-rounding round trip. These remain
   current-vintage transformation evidence rather than independent data or a
   model input.
3. Build two named baselines:
   - **2024Q4 structural baseline:** all annual structural accounts aligned to
     the latest complete 2024 BEA input-output data.
   - **2026Q1 nowcast baseline:** carry the 2024 structure forward with current
     quarterly macro, labor, and Financial Accounts controls. Label it as a
     hybrid/nowcast baseline, not as a 2026 structural table.
4. Estimate the quarterly processes from **1997Q1 onward**, loading 1996Q4 as
   the extra observation required to calculate the first inflation rate.
5. Store authoritative data as **immutable raw files plus versioned Parquet**,
   query it locally with **DuckDB**, and export the exact model inputs as
   **JLD2 artifacts**. A server database or BigQuery is unnecessary at this
   stage.
6. The configured **FRED and BEA API keys work**. The configured registered
   **BLS key does not**; the BLS endpoint itself works without a key under the
   lower anonymous limits. Renew or replace the BLS key before automated
   backfills.

The difficult part is not buying data. It is preserving units and vintages,
building the BEA/BLS/Census sector concordance, reconciling jobs with people
and firms with establishments, and preventing product-tax double counting.

## 1. What the model actually needs

`get_params_and_initial_conditions` consumes four input blocks. Almost all
model parameters and initial conditions are derived from these blocks.

### 1.1 Annual and quarterly calibration block

| Required input | Shape/frequency | Meaning and proposed U.S. construction |
|---|---:|---|
| `years_num`, `quarters_num` | annual and quarterly indexes | Quarter-end/year-end MATLAB-style dates expected by the current importer |
| `household_cash_quarterly` | quarterly stock | Household currency and deposits from Federal Reserve Financial Accounts |
| `property_income`, `mixed_income` | annual flows | BEA NIPA household property income and proprietors' income controls |
| `firm_cash_quarterly` | quarterly stock | Nonfinancial corporate plus noncorporate currency and deposits |
| `firm_debt_quarterly` | quarterly stock | Nonfinancial business debt securities plus loans |
| `firm_debt_consolidation_ratio_quarterly` | optional quarterly ratio | Set to 1 initially unless a documented consolidation adjustment is built |
| `firm_interest_quarterly` or `firm_interest` | quarterly or annual flow | Prefer a consistent BEA/Fed measure; annual BEA NIPA is an acceptable first version |
| `government_debt_quarterly` | quarterly stock | Federal plus state/local credit-market debt |
| `interest_government_debt_quarterly` or annual equivalent | flow | BEA NIPA general-government interest paid |
| `social_benefits` | annual flow | BEA NIPA government social benefits to persons |
| `unemployment_benefits` | annual flow | Unemployment-insurance benefits within NIPA social benefits |
| `pension_benefits` | annual flow | Social Security and other pension benefit control; definition must be frozen in metadata |
| `corporate_tax` | annual flow | Taxes on corporate income |
| `wages_by_sector` | sector × year | Prefer sectoral wages; the scalar `wages` fallback loses sector information |
| `social_contributions`, `income_tax`, `capital_taxes` | annual flows | BEA NIPA government receipts. Treat estate/gift taxes explicitly; do not silently force a European definition onto U.S. accounts |
| `bank_equity_quarterly` | quarterly stock | Private depository-institution total assets less liabilities |
| `government_deficit_quarterly` or annual equivalent | flow | Positive-deficit convention required by the calibration; derive as the negative of NIPA net lending/borrowing and test the sign |
| `firms`, `employees` | sector × year counts | Census SUSB enterprise counts and CPS-rescaled QCEW employment shares; see the population-unit warning below |
| `population` | annual persons | Civilian noninstitutional population age 16+ is the most coherent denominator for this model |
| `fixed_assets`, `dwellings`, `capital_consumption` | sector × year stocks/flows | BEA Fixed Assets current-cost net stock and depreciation |
| `gross_capitalformation_dwellings` | annual flow | Residential private fixed investment from the I-O final-use columns |
| `unemployed_census`, `inactive_census` | optional counts | Prefer direct CPS annual-average counts over reconstructing both from a single unemployment rate |

If sectoral fixed assets and depreciation are supplied, the European fallback
fields (`fixed_assets_eu7`, `dwellings_eu7`,
`nominal_nace64_output_eu7`, `nace64_capital_consumption`, and
`nominal_nace64_output`) are not needed.

### 1.2 FIGARO-equivalent industry accounts

For each annual structural year, the code requires:

| Required input | Shape | U.S. source |
|---|---:|---|
| `intermediate_consumption` | commodity × industry × year | BEA Input-Output Table 259, intermediate-use block |
| `household_consumption` | commodity × year | Table 259 final-use column `F010` |
| `fixed_capitalformation` | commodity × year | Sum `F02E/F02N/F02R/F02S`, `F06E/F06N/F06S`, `F07E/F07N/F07S`, and `F10E/F10N/F10S`; exclude inventories `F030` |
| `exports` | commodity × year | Table 259 `F040` |
| `compensation_employees` | industry × year | Table 259 value-added row `V001` |
| `operating_surplus` | industry × year | Table 259 row `V003` |
| `government_consumption` | commodity × year | Sum `F06C`, `F07C`, and `F10C` |
| `taxes_production` | industry × year | Table 259 row `T00OTOP`, with sign and subsidies checked |
| `taxes_products_household`, `taxes_products_capitalformation`, `taxes_products_government` | scalar controls × year | Construct through a purchasers/basic-price valuation bridge and reconcile to NIPA tax controls |
| `taxes_products` | industry × year | Preserve the observed series in curated data, although the current calibration code subsequently zeroes it |

[BEA's I-O accounts](https://www.bea.gov/data/industries/input-output-accounts-data)
offer annual 71-industry summary tables and more detailed benchmark tables.
The [BEA I-O guide](https://www.bea.gov/resources/guide-interactive-industry-input-output-accounts-tables)
documents the 15-, 71-, 138-, and detailed classifications.

Table 259, **Use of Commodities by Industries—Summary**, is the primary table.
Table 262, **Domestic Supply of Commodities by Industries—Summary**, should be
ingested as a validation source for imports, margins, and supply. The current
U.S. adapter opts into measured Table 262 imports; the upstream residual
goods-balance calculation remains only as a fallback for other country
artifacts. A measured import vector must not be mixed with that fallback.

The BEA API test on 2026-08-01 found explicit annual I-O years through 2024.
Use the maximum year returned by the parameter metadata; `Year=Latest` returned
an internal API error in the test.

### 1.3 Quarterly national block

| Required input | Proposed series |
|---|---|
| `nominal_gdp_quarterly` | BEA NIPA nominal GDP |
| `nominal_household_consumption_quarterly` | BEA NIPA personal consumption expenditures |
| `nominal_gross_private_domestic_investment_quarterly` | BEA NIPA gross private domestic investment |
| `nominal_fixed_investment_quarterly` | BEA NIPA fixed investment |
| `nominal_inventory_investment_quarterly` | BEA NIPA signed change in private inventories; this is a flow, not an inventory stock |
| `nominal_exports_quarterly`, `nominal_imports_quarterly` | BEA NIPA nominal exports and imports |
| `nominal_government_consumption_and_investment_quarterly` | BEA NIPA government consumption expenditures and gross investment |
| `real_gdp_quarterly` | BEA NIPA real GDP |
| `unemployment_rate_quarterly` | BLS CPS unemployment rate, quarterly average, expressed as a fraction |
| `euribor` | Replace semantically with the effective federal funds rate; keep the existing field name only at the adapter boundary |
| `real_government_consumption_quarterly` | BEA real government consumption expenditures and gross investment |
| `real_exports_quarterly` | BEA real exports of goods and services |
| `real_imports_quarterly` | BEA real imports of goods and services |

The code derives the GDP deflator from nominal/real GDP, estimates the domestic
government/export/import processes, estimates a Taylor rule, and constructs
their initial paths. The nominal T10105 controls are preserved for opening
account reconciliation:

```text
GDP = PCE + gross private domestic investment
    + exports - imports + government
gross private domestic investment = fixed investment
    + signed change in private inventories
```

They are not yet allocated to all model sectors or used to anchor every
installed opening-state component.

**Critical units rule:** BEA quarterly NIPA flow levels are normally reported
at seasonally adjusted annual rates. Divide nominal and real quarterly flow
levels by four before supplying them to calibration. Do not divide rates or
end-of-period balance-sheet stocks. The resulting `timescale` should be close
to 0.25; a value close to 1 is a likely SAAR error. Preserve negative
inventory-investment quarters after the SAAR conversion.

**Inventory warning:** the current research artifact's
`inventory_statistical_discrepancy_s` is an unreconciled commodity-balance
diagnostic, not BEA F030 or NIPA inventory investment. Its use as an opening
stock bridge is rejected for forecast promotion in
`data/us/validation/ACCOUNTING_GATES.toml`. Do not force GDP closure by adding
that discrepancy to capital formation. The standalone inventory-stock ledger
now fixes end-of-period, no-SAAR-division, unit, M3-stage, and missing-not-zero
semantics, but its fixture is explicitly synthetic. It emits no `S_s`: BEA
Table 5.8.5B is now archived and verified for all 29 published 2026Q1 rows as
a current-vintage diagnostic, but it is not an origin-time first-release
receipt and is origin-ineligible. Holder-to-model-sector and
holder-to-commodity mappings, manufacturing/wholesale/retail stage evidence,
valuation and stage-to-model-stock-scope bridges, latent-state reconciliation,
and origin-time receipts are still required.

### 1.4 `ea` block: a U.S.-specific semantic issue

The block called `ea` is used for the monetary area's GDP, GDP deflator, and
Taylor-rule regressors. It is not the model's export-demand economy. For
Austria, the euro area is correct. For the United States, supply:

- U.S. nominal GDP again;
- U.S. real GDP again; and
- the implied U.S. GDP deflator.

That makes the estimated policy rule respond to U.S. activity and inflation.
Domestic exports and imports already have separate processes. A foreign or
rest-of-world GDP series is therefore **not required by the current code**.
If a later model change separates foreign demand from the monetary-policy
block, the [Dallas Fed DGEI](https://www.dallasfed.org/research/international/dgei)
rest-of-world aggregates, OECD data, and Federal Reserve trade weights are
good public candidates.

### 1.5 Derived initial conditions and parameters

The raw data above generate the main stocks and states:

- firm deposits and debt (`D_I`, `L_I`);
- household deposits and dwelling capital (`D_H`, `K_H`);
- government debt (`L_G`);
- bank and central-bank equity (`E_k`, residual `E_CB`);
- sector employment (`N_s`);
- GDP, inflation, policy rate, and historical series;
- benefit amounts per unemployed/inactive/other household;
- 68-commodity technology, wage, tax, final-demand, and network parameters
  derived from 71 BEA source industries;
- effective household, corporate, payroll, consumption, capital-formation,
  government, and export tax rates; and
- AR(1), Taylor-rule, and shock-covariance parameters.

The current code also imposes assumptions that data acquisition cannot solve:

| Assumption | Current value/behavior | Required treatment |
|---|---:|---|
| Capacity utilization `omega` | 0.85 | Keep as a documented baseline; sensitivity-test with Federal Reserve capacity utilization |
| Replacement rate `theta_UB` | `0.55 × (1-τ_INC) × (1-τ_SIW)` | Compare with state UI replacement-rate evidence |
| Debt amortization `theta` | 0.05 per quarter | Sensitivity-test |
| Bank capital constraint `zeta` | 0.03 | Sensitivity-test or map deliberately to a regulatory-capital definition |
| Loan-to-value `zeta_LTV` | 0.60 | Sensitivity-test |
| Bank recapitalization `zeta_b` | 0.50 | Sensitivity-test |
| Government/export producer counts | `J ≈ firms/4`, `L ≈ firms/2` | Model assumption, not an observed count |
| Rest-of-world deposits `D_RoW` | 0 | Document or change the model |
| Sector product taxes | loaded, then set to zero | Resolve the accounting design before claiming a tax-complete U.S. calibration |

## 2. Recommended public-source acquisition map

### 2.1 Industry structure, capital, labor, and firms

| Need | Primary public source | Access and transformation | Assessment |
|---|---|---|---|
| 71×71 use matrix and final demand | [BEA Input-Output Accounts](https://www.bea.gov/data/industries/input-output-accounts-data), API dataset `InputOutput`, Table 259 | API JSON or official XLSX; use explicit year and save the table metadata | **Works; primary source** |
| Domestic supply/import validation | BEA I-O Table 262 | Ingest with Table 259 and reconcile by commodity | **Works; QA source** |
| Commodity network comparator | BEA after-redefinitions direct-requirements and market-share workbooks, plus I-O Table 59 | Compute the primary direct matrix as `B*D`; use `I-inv(L59)` only as a published-rounding round trip; apply Table 262 `T007` output and aggregate transactions/output before recomputing coefficients | **Works; diagnostic only** |
| Private-inventory holder controls | BEA NIPA Table 5.8.5B (`T50805B`) | Preserve end-of-quarter current-price stocks, duplicate controls, final-sales denominators, ratios, redacted-source/semantic hashes, and receipt metadata; never divide stocks by four or equate their change with NIPA inventory investment | **Current vintage verified; origin-ineligible and not model-mapped** |
| Industry output controls | [BEA GDP by Industry](https://www.bea.gov/data/gdp/gdp-industry) | API dataset `GDPbyIndustry`; map BEA industry codes to the 71 summary codes | **Works** |
| Industry assets | [BEA Fixed Assets](https://apps.bea.gov/iTable/?ReqID=10&step=2) | API tables `FAAt301ESI` (current-cost net stock), `FAAt304ESI` (depreciation), and `FAAt307ESI` (investment) | **Works** |
| Residential assets | BEA Fixed Assets | `FAAt501`, `FAAt504`, and `FAAt507`; allocate consistently with the I-O dwelling investment vector | **Works** |
| Government fixed assets | BEA Fixed Assets | `FAAt701`/`FAAt703` if government production capital is represented separately | **Works; definition decision needed** |
| Employment, wages, establishments | [BLS QCEW](https://www.bls.gov/cew/overview.htm) and [bulk files](https://www.bls.gov/cew/downloadable-data-files.htm) | Download annual national totals at six-digit NAICS, then aggregate through a versioned NAICS→BEA-71 concordance | **Works; >95% of U.S. jobs** |
| Employer firms | [Census SUSB](https://www.census.gov/programs-surveys/susb/about.html) [tables](https://www.census.gov/programs-surveys/susb/data/tables.html) | Use enterprise counts, not establishment counts; latest tables lag roughly 2–2.5 years, so nowcast by QCEW establishment growth | **Works with lag/proxies** |
| Agriculture omitted by SUSB | [USDA ERS farm counts](https://www.ers.usda.gov/data-products/ag-and-food-statistics-charting-the-essentials/farming-and-farm-income) | Use annual farm counts for agricultural productive units | **Works; proxy definition** |
| Employment persons, unemployed, inactive, population | [BLS CPS](https://www.bls.gov/cps/) | Annual averages from monthly CPS. Rescale QCEW sector job shares to the CPS employed-person control before combining with population | **Works; necessary unit reconciliation** |

QCEW counts jobs and establishments; CPS counts people; SUSB counts enterprises.
They are not interchangeable. The recommended first-version synthesis is:

1. obtain total employed, unemployed, and inactive people from CPS;
2. distribute employed people across industries using QCEW job shares;
3. use SUSB employer-enterprise counts for `firms`;
4. fill SUSB exclusions explicitly (agriculture with USDA, government with
   QCEW establishment-like pseudo-producers, and other excluded codes with
   documented proxies); and
5. retain `count_concept`, source year, nowcast method, and proxy flags.

This avoids subtracting payroll jobs from a population measured in persons.

### 2.2 Financial initial conditions

Use the [Federal Reserve Financial Accounts of the United States
(Z.1)](https://www.federalreserve.gov/releases/z1/). The June 11, 2026 release
substantially renumbered tables, so collectors must use stable series mnemonics
and download the matching data dictionary instead of relying on old table
numbers such as “L.101.”

Proposed quarterly series:

| Model concept | Proposed Z.1 construction |
|---|---|
| Household cash | `FL153020005.Q + FL153030005.Q + LM153030505.Q` |
| Nonfinancial corporate cash | `FL103020005.Q + FL103030003.Q + FL103091003.Q` |
| Nonfinancial noncorporate cash | `FL113020005.Q + FL113030003.Q` |
| Firm debt | Corporate `FL104122005.Q + FL104135005.Q` plus noncorporate `FL114135005.Q` |
| Federal debt | `FL314122005.Q` |
| State/local debt | `FL213162005.Q` |
| Depository-institution equity | `FL704194005.Q - FL704190005.Q` |

Freeze this mapping in a reviewed YAML/TOML file with series labels, sectors,
units, and the Z.1 release date. Validate every release against the downloaded
series dictionary because mnemonics can be revised or discontinued.

The principal household sector includes nonprofit institutions serving
households. Use the supplemental household table where a pure-household
measure is available; otherwise label the concept HH+NPISH. Firm debt is total
credit-market debt, although the simulation abstracts it as bank credit. That
is a model mapping, not a claim that every observed bond is a bank loan.

[FDIC quarterly bank data](https://www.fdic.gov/bank-data-guide/data-downloads)
are free and useful for validating bank capital or later modeling bank
heterogeneity, but Z.1 is the better aggregate initial-condition source.

### 2.3 Income, fiscal, taxes, and benefits

The coherent primary source is the [BEA NIPA API and
tables](https://apps.bea.gov/iTable/?ReqID=19&step=2), because BeforeIT needs
accrual-based, consolidated general-government concepts rather than only
federal cash transactions.

| BEA table | Main use in calibration |
|---|---|
| `T10105` | Nominal GDP and expenditure components |
| `T11000` | Gross domestic income components |
| `T11200` | National income, property income, and proprietors' income checks |
| `T11400` | Corporate value added, profits, interest, and corporate-tax checks |
| `T20100` | Personal income, contributions, taxes, transfers, and disposable-income reconciliation |
| `T30100` | Combined federal/state/local government receipts, expenditures, interest, and net lending |
| `T30200`, `T30300` | Federal and state/local decomposition and QA |
| `T30600` | Contributions for government social insurance |
| `T31200` | Government social benefits by program/type |
| `T71100` | Interest paid and received by sector/legal form; annual firm-interest fallback |

The [Treasury Monthly Treasury Statement through
FiscalData](https://fiscaldata.treasury.gov/datasets/monthly-treasury-statement/)
is free and API-accessible. Use it to validate or nowcast federal cash
receipts/spending, not as the primary calibration source: it is federal-only
and modified-cash, whereas NIPA is the general-government accounting frame.

Tax construction requires a written crosswalk:

- personal current taxes → household income tax;
- taxes on corporate income → corporate tax;
- social-insurance contributions → employer and household portions;
- estate/gift or other capital-transfer taxes → `capital_taxes` only if their
  model interpretation is accepted;
- taxes less subsidies on production/imports → industry production/product
  tax controls; and
- final-use product taxes → household, capital, and government tax wedges.

### 2.4 Quarterly estimation panel and monetary rate

Use BEA NIPA directly for GDP and the three real expenditure components, BLS
CPS for unemployment, and the Federal Reserve/FRED for the effective federal
funds rate. FRED is convenient for a small aligned panel and vintages, but it
is an aggregator: its [API terms](https://fred.stlouisfed.org/docs/api/terms_of_use.html)
warn that some series are third-party copyrighted. Store the originating
agency and series notes, and prefer the originating agency for core bulk data.

Suggested minimum series registry:

| Internal name | Origin | Candidate identifier |
|---|---|---|
| nominal GDP | BEA NIPA | Table 1.1.5, GDP line |
| real GDP | BEA NIPA | Table 1.1.6, GDP line |
| real government consumption/investment | BEA NIPA | Table 1.1.6, government line |
| real exports | BEA NIPA | Table 1.1.6, exports line |
| real imports | BEA NIPA | Table 1.1.6, imports line |
| unemployment rate | BLS CPS | `LNS14000000`, quarterly average |
| policy rate | Federal Reserve via FRED | `FEDFUNDS`, quarterly average; annual percent converted to decimal before calibration |

### 2.5 Forecasts, scenarios, and real-time backtests

Forecasts are optional for an unconditional simulation: the code uses the
observed endpoint and the estimated stochastic processes. Add forecast paths
only for conditioned scenarios.

| Use | Free source | What it provides |
|---|---|---|
| Fiscal/economic baseline | [CBO Budget and Economic Data](https://www.cbo.gov/data/budget-economic-data) | Official baseline projections; annual paths may need documented quarterly interpolation |
| Consensus macro forecasts | [Philadelphia Fed Survey of Professional Forecasters](https://www.philadelphiafed.org/surveys-and-data/real-time-data-research/survey-of-professional-forecasters) | Quarterly forecast distributions for major aggregates |
| Fed policy projections | [Federal Reserve SEP](https://www.federalreserve.gov/monetarypolicy/fomcprojtabl20260617.htm) | Policymaker medians/ranges for key annual variables; not a full component path |
| Energy scenarios | [EIA Annual Energy Outlook](https://www.eia.gov/outlooks/aeo/) | Optional sector/price/scenario assumptions |
| Revision-aware backtests | [Philadelphia Fed RTDSM](https://www.philadelphiafed.org/surveys-and-data/real-time-data-research/real-time-data-set-for-macroeconomists) | Monthly/quarterly vintages and first/second/third release values |
| FRED vintages | [ALFRED](https://alfred.stlouisfed.org/) | Vintages for many FRED series |

Backtests should select a vintage available on the simulated decision date,
not today's revised history.

### 2.6 Public microdata for future model extensions

These data are useful if BeforeIT later introduces household or firm
heterogeneity, but they are **not required by the current aggregate-sector
initializer**:

- [Survey of Consumer Finances](https://www.federalreserve.gov/econres/scfindex.htm):
  triennial public household wealth, debt, and income microdata;
- [Consumer Expenditure Survey public-use
  microdata](https://www.bls.gov/cex/pumd.htm): spending, income, and
  demographics;
- [CPS public-use files](https://www.census.gov/programs-surveys/cps/data/datasets.html):
  monthly labor and income microdata; and
- [ACS PUMS](https://www.census.gov/programs-surveys/acs/microdata.html):
  large-sample demographic and geographic microdata.

## 3. API and access tests

Tests were performed from this repository's `.env` on 2026-08-01 without
printing or storing any secret values in this document.

| Service | Test | Result | Action |
|---|---|---|---|
| FRED | Request one observation for `GDP` | HTTP 200, valid observation | **Key works** |
| BEA | `GetDatasetList` | HTTP 200, 13 datasets, no BEA error | **Key works** |
| BLS registered v2 | Request `LNS14000000` with `BLS_API_KEY` | HTTP 200 but `REQUEST_NOT_PROCESSED`; registered key rejected | **Renew/replace the key** |
| BLS anonymous v2 | Same series without a key | HTTP 200, `REQUEST_SUCCEEDED` | **Endpoint works for development** |

According to the [BLS API FAQ](https://www.bls.gov/developers/api_faqs.htm),
registered access permits 500 queries/day, 50 series/query, and 20 years/query;
unregistered access permits 25 queries/day, 25 series/query, and 10 years/query.
BLS registration keys must be renewed at least annually. Bulk QCEW downloads
should be used instead of spending API quota on large industry backfills.

The [BEA API guide](https://apps.bea.gov/api/_pdf/bea_web_service_api_user_guide.pdf)
documents limits of 100 requests/minute, 100 MB/minute, and 30 errors/minute.
Collectors should cache parameter metadata, request in batches, apply a
rate limiter, and never use the production pipeline to probe invalid
combinations repeatedly.

The Census API is free; the
[Census API guide](https://www.census.gov/content/dam/Census/data/developers/api-user-guide/api-guide.pdf)
states that an API key is needed above 500 queries per IP address per day.
Bulk SUSB files are preferable for a reproducible annual calibration, so a
Census key is optional.

Keep `.env` untracked. Add a startup check that reports only `present`,
`accepted`, and the service error code—never the key or full authenticated URL.

## 4. Do we need to purchase data?

### Required purchase: none

BEA, BLS, Census, Federal Reserve, Treasury, CBO, EIA, and Philadelphia Fed
sources cover every observed field required by the national model. The public
route has more integration work but is transparent, reproducible, and legally
easier to archive.

Commercial products can buy **time, harmonization, regional detail, forecasts,
and vendor support**. They do not fill a hard national-data gap in version 1.
Public list prices are generally not posted, so the old unsupported dollar
bands have been removed.

| Product | What it would buy | Is it needed? | Purchasing and license work |
|---|---|---|---|
| [IMPLAN pricing/packages](https://implan.com/implan-pricing-and-packages/) and [API](https://implan.com/api/) | Annual national/state/county I-O, tax, employment, trade, environmental data and detailed industry impact workflows | **No** for national BEA-71; strongest option if moving quickly to regional or much finer industry models | Annual subscription; specialized academic/government packages; API priced by quote. Ask explicitly about bulk extraction, persistent storage after expiry, derived outputs, client-facing use, and API limits |
| [Haver Analytics](https://www.haver.com/our-data) | Curated official releases, update operations, transformations, and one desktop/API-style workflow | **No**; useful when staff time and release latency dominate | Request a quote for named databases, users, API/feed, vintages, backfill, and storage/redistribution rights |
| [Moody's Data Buffet](https://www.economy.com/products/tools/data-buffet) | Large curated macro database, forecasts, scenarios, API/S3/FTP/Office delivery | **No** for history; useful for an integrated commercial forecast feed | Subscription by quote. Separate raw-data, forecast, API, user, and derived-output entitlements |
| [Oxford Economics Global Economic Model](https://www.oxfordeconomics.com/subscriptions/global-economic-model/) | Global model, baseline and alternate scenarios, forecast updates, model/API tooling | **No** for calibration; useful for global conditioned scenarios | Demo and custom quote; confirm scenario export, automated access, named users, and use in a downstream simulation |
| [S&P Global Economic Data](https://www.marketplace.spglobal.com/en/datasets/economic-data-%2813%29) | Long U.S./global forecasts, alternate scenarios, industry detail, delivery feeds | **No** for calibration; possible forecast/scenario alternative | Custom quote; specify exact forecast vintages, API/cloud delivery, storage, model-input, and publication rights |
| [Macrobond](https://www.macrobond.com/) | Cross-source discovery, metadata, transformations, charts, and collaboration | **No**; useful analyst productivity layer | Quote/order form with designated users. Confirm data-feed rights, source-specific third-party restrictions, historical vintages, and whether extracted data may persist after termination |
| Orbis/Compustat/Capital IQ/D&B | Entity-level company balance sheets, ownership, and financials | **No** for the current synthetic sector-firm initializer; possible future heterogeneous-firm model | Typically custom and restrictive licenses. Evaluate private-firm coverage, survivorship, publication of aggregates, entity matching, APIs, and post-termination retention |

If only one optional purchase is considered, choose based on the actual next
goal:

- **regional/fine-industry model:** request an academic/government IMPLAN quote;
- **operational release curation:** request Haver and Macrobond trials;
- **forecast-conditioned scenarios:** compare Moody's, Oxford, and S&P using
  the same required-variable checklist; or
- **firm heterogeneity:** evaluate entity-level coverage only after the model
  schema exists.

### Commercial quote checklist

Send every vendor the same requirements:

1. exact datasets, geographic/industry detail, history, and vintages;
2. delivery method (bulk, API, S3/FTP) and documented rate/volume limits;
3. annual subscription, setup, API, additional-user, and support charges;
4. trial data and a machine-readable sample before contracting;
5. rights to retain raw extracts and calibrated artifacts after expiration;
6. rights to create, store, publish, and redistribute derived aggregates;
7. internal versus consulting/client-facing use;
8. development, CI, production, and backup environments;
9. update schedule, revisions, backfill, source metadata, and SLA; and
10. termination notice, renewal escalation, audit, and attribution terms.

Do not approve a purchase based on a platform demo alone. Run the vendor sample
through the same sector concordance, accounting identities, and vintage tests
as the public pipeline.

## 5. Storage architecture

### Recommendation: files as the system of record, DuckDB as the query layer

Use the successful pattern already present in the Austria pipeline: immutable
downloads, checksums, columnar staged data, local analytical queries, and
versioned JLD2 runtime artifacts.

```text
data/us/
  sources.toml                 # endpoints, table/series IDs, licenses, cadence
  concordances/
    bea71.csv
    naics_to_bea71.csv
    z1_series.toml
    nipa_lines.toml
  raw/                         # ignored by Git; immutable bytes as received
    bea/<release_vintage>/...
    bls/<release_vintage>/...
    census/<release_vintage>/...
    federal_reserve/<release_vintage>/...
  staged/                      # ignored by Git; normalized versioned Parquet
    io/year=2024/...
    nipa/vintage=2026-07-30/...
    qcew/year=2024/...
    z1/vintage=2026-06-11/...
  curated/                     # model-shaped Parquet plus QA and lineage
    us_bea71_annual.parquet
    us_quarterly_panel.parquet
    us_financial_stocks.parquet
    calibration_manifest.json
    validation_report.json
  calibration/
    US_2024_calibration_object.jld2
  baselines/
    US_2024Q4_structural.jld2
    US_2026Q1_nowcast.jld2
  ARTIFACTS.toml
```

The raw directory must preserve the exact downloaded JSON, CSV, XLSX, ZIP, or
text payload plus request metadata and SHA-256. Never overwrite a vintage.
Parquet is the normalized, portable analytical source of truth. A local
DuckDB database may hold views and cached tables, but it must be rebuildable
from Parquet. JLD2 is the optimized input to BeforeIT, not the only copy of
the evidence.

Commit to Git:

- collectors, transformations, schemas, and tests;
- source registry and small concordance tables;
- manifests, checksums, and validation summaries; and
- small redistributable artifacts if their source terms allow it.

Keep large/raw data outside Git, using local storage initially and a
content-addressed object store or Julia Artifacts for collaboration and CI.
Never commit API keys or authenticated request URLs.

### Minimum provenance schema

Every staged observation or table must be traceable through:

| Field | Purpose |
|---|---|
| `source_agency`, `dataset_id`, `table_or_series_id` | Stable origin |
| `observation_period`, `frequency` | Economic reference period |
| `release_date`, `vintage_date`, `retrieved_at` | Real-time reproducibility |
| `units`, `scale`, `seasonal_adjustment`, `saar` | Prevent silent factor and rate errors |
| `price_basis`, `valuation_basis` | Current/chained dollars and basic/producer/purchaser prices |
| `classification`, `classification_vintage` | NAICS/BEA code interpretation |
| `transformation_id`, `source_rows` | Reproducible derivation |
| `proxy_flag`, `quality_flag` | Synthetic/nowcast/missing-sector visibility |
| `license_id`, `attribution` | Use and redistribution constraints |
| `raw_sha256`, `pipeline_commit` | Byte and code lineage |

Long-form staged tables should use explicit dimensions rather than encoded
column names. The curated layer may materialize the 71×71 arrays that the Julia
code needs.

### Why not a server database or BigQuery now?

- The national data are small and released monthly, quarterly, or annually.
- One reproducible pipeline and a small team do not need concurrent
  transactional writes.
- DuckDB reads Parquet and performs matrix/table joins without operating a
  service.
- The simulation already consumes local JLD2 artifacts.
- A cloud database adds credentials, cost, migrations, egress, and another
  source of state without resolving the real issues—concordance and
  accounting.

Adopt Postgres/BigQuery only when at least one of these becomes real:

- multiple users or services need concurrent governed access;
- state/county, establishment, or licensed microdata reach material scale;
- cloud scheduling, BI, row-level permissions, or cross-project joins are
  required; or
- a production API must serve historical vintages.

The existing BigQuery design documents can remain as a future option, but
they should not be the first implementation target.

## 6. Transformation and validation gates

### 6.1 Transformations that must be explicit

1. **Quarterly flows:** convert SAAR levels to quarter flows by dividing by
   four before calibration.
2. **Interest/unemployment rates:** convert percent to decimal; the code then
   converts an annual policy rate to an effective quarterly rate.
3. **Stocks:** use quarter-end/current-cost stocks without dividing by four.
4. **Prices:** never sum chain-dollar components to form an accounting total.
   Use current-dollar accounts for identities and chained indexes only for
   growth/deflation.
5. **Industry codes:** use a versioned many-to-one mapping to BEA-71 and fail
   on unmapped material values.
6. **Employment:** rescale sector job shares to a person total; retain the
   original QCEW job totals for QA.
7. **Firms:** distinguish enterprise, establishment, employer, and farm/pseudo-
   producer concepts.
8. **Deficit sign:** encode and test the model's positive-deficit convention.
9. **Taxes:** construct a valuation bridge and test GDP from income and
   expenditure sides before and after model-specific zeroing.
10. **Nowcasts:** retain observed structural year and nowcast target quarter
    separately; never relabel a carried-forward I-O matrix as newly observed.

### 6.2 Automated acceptance tests

A baseline is not publishable until it passes:

- exact 71×71 dimensions, stable code ordering, and complete concordance;
- no unexpected missing, NaN, infinite, or negative inputs;
- industry output = intermediate inputs + compensation + gross operating
  surplus + taxes less subsidies on production, within a documented tolerance;
- GDP income and expenditure constructions reconcile to BEA controls;
- I-O final-use sums reconcile to NIPA controls or have an explicit bridge;
- household, firm, government, and bank stocks reconcile to Z.1 aggregates;
- QCEW, CPS, and SUSB coverage/proxy shares are reported;
- `timescale` is plausibly near one quarter of the annual accounts;
- sector final-demand shares and input-network columns sum to one where defined;
- tax and behavioral rates are finite and economically plausible;
- Z.1 series names still match the stored data dictionary;
- the Julia calibration object loads and initializes the simulation;
- accounting identities hold immediately after initialization;
- deterministic smoke tests run without nonfinite states; and
- simulated moments are compared with held-out U.S. quarterly data and, for
  historical exercises, with the data vintage actually available then.

For product taxes, maintain two views:

1. the economically observed BEA tax/valuation bridge; and
2. the model-compatible view used by the current code.

This makes the present zeroing transparent and allows the model accounting to
be repaired later without recollecting source data.

### 6.3 Current opening-accounting candidate status

The installed structural and nowcast baselines remain protected legacy
research artifacts; they have not been relabeled as accounting-valid.
Separate 2024Q4 and 2026Q1 candidate JLD2 files now anchor the first observed
row to the exact BEA T10105 current-dollar controls. This resolves only the
observation-layer identity at the published $1m rounding tolerance.

The same candidates deliberately preserve and report the initialized
agent-state implications. Their latent expenditure residuals are
-$137,674.939893m and -$147,094.197894m, respectively. Supply/use valuation,
the sector demand bridge, an origin-eligible and bridge-complete nonnegative
model inventory vector, full accounting, vintage eligibility, and
forecast-skill evaluation remain failed or missing. The current-vintage
T50805B holder controls do not close the allocation, valuation, stage/scope,
latent-reconciliation, or origin-time receipt gaps. The candidates are
therefore `RESEARCH_ONLY_NOT_PROMOTED`, are not loaded by
`load_us_baseline`, and must not appear in an accuracy table.

The candidate builder disables the rejected commodity-balance inventory
closure, removes all discrepancy-derived inventory aliases, retains the T007
gap without balancing, and stores signed NIPA inventory investment separately
from inventory stocks. Exact details and commands are in
`scripts/us/accounting/README.md`.

The official `B*D`, T007-scaled comparator does not close these blockers.
Its 70×70 transaction total is $426,517.009816m below the purchasers-price
symmetric-use diagnostic. Table 59 inversion agrees within published-rounding
tolerance but remains only a round trip. The cross-system gap is retained as a
price/system-boundary diagnostic because a production conversion requires
cell-specific trade and transportation margins; it is not a scalar
reconciliation target or an accuracy result.

## 7. Implementation sequence

### Phase 0 — lock definitions

- Approve BEA-71 as the model sector system.
- Approve 2024Q4 structural and 2026Q1 nowcast baselines.
- Freeze person/job/firm definitions and the fiscal/tax crosswalk.
- Replace the BLS key and add non-secret API health checks.

### Phase 1 — collectors and raw archive

- BEA metadata-driven collectors for I-O, NIPA, GDP by Industry, and Fixed
  Assets;
- bulk BLS QCEW plus small CPS API/bulk collector;
- SUSB/USDA firm-count inputs;
- Federal Reserve Z.1 collector keyed by series mnemonic and release
  dictionary; and
- request manifests, checksums, retries, rate limiting, and release dates.

### Phase 2 — staged and curated accounts

- build and test NAICS↔BEA-71 concordances;
- construct Table 259 industry/final-demand arrays and Table 262 QA;
- construct current-cost capital/depreciation vectors;
- reconcile CPS/QCEW/SUSB counts;
- build fiscal/income/tax controls;
- build the quarterly estimation panel; and
- build observed and model-compatible accounting views.

### Phase 3 — model artifacts

- generate the four input dictionaries (`calibration`, `figaro`, `data`,
  `ea`);
- write `US_2024_calibration_object.jld2`;
- generate the two baseline JLD2 files and manifests;
- run calibration, initialization, accounting, and smoke tests; and
- publish an artifact card stating sources, vintages, transformations,
  assumptions, proxies, known limitations, and hashes.

### Phase 4 — empirical validation and optional procurement

- backtest against directly archived release vintages, using RTDSM only as a
  curated date/month-granular research proxy rather than strict intraday
  origin evidence; exclude FRED/ALFRED acquisition until written
  project-specific clearance;
- compare simulated U.S. moments and impulse responses with observed data;
- sensitivity-test the six hard-coded behavioral/financial assumptions; and
- only then trial a vendor against a measured shortcoming such as regional
  detail, staff update time, or scenario coverage.

## 8. Principal unresolved modeling decisions

These are model-design choices, not missing purchases:

1. **Product-tax accounting:** the calibration deliberately zeroes sector
   product taxes. The U.S. adapter must avoid double counting while preserving
   the observed valuation bridge.
2. **Firm concept:** SUSB enterprises are the closest national concept, but
   excluded sectors and the annual lag require explicit proxies.
3. **Labor concept:** sector jobs must be reconciled to household persons.
4. **Government productive units:** decide whether government industries use
   pseudo-firms based on establishments, employment, or another scale rule.
5. **Firm debt:** decide whether all credit-market debt is acceptable under
   the model's single bank-loan abstraction.
6. **HH versus HH+NPISH:** choose a consistent household boundary across NIPA
   and Z.1.
7. **Interest flows:** decide between annual NIPA stability and quarterly Fed
   integrated-account detail.
8. **External block:** the current `ea` block should be populated with U.S.
   data; a true foreign-demand block requires code changes.
9. **Hard-coded parameters:** capacity utilization, benefit replacement,
   amortization, capital constraint, LTV, and recapitalization need
   sensitivity analysis even with perfect source data.

The recommended next engineering milestone is a small vertical slice:
download BEA 2024 Table 259 and Fixed Assets, build the BEA-71 schema and one
quarter of the macro/Z.1 panel, then prove that an initial calibration artifact
passes the dimensions, units, and accounting tests before completing the full
historical backfill.
