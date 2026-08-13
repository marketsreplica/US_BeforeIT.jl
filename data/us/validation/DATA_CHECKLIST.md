# U.S. calibration data checklist

Generated: `2026-08-04T00:27:13.046`
Status correction applied: `2026-08-06`
Structural reference: `2024Q4`; nowcast: `2026Q1`; economic-outlook truth vintage: `2026-08-04`; model system: `BEA 68 observed commodity sectors`.

Overall status is fail-closed across two distinct questions: `source_control_reconciles` records whether the retained source/control arithmetic passes, while `model_mapping_admissible` records whether that evidence supports writing the parameter into model state. **APPROVED** passes the stated question; **DUBIOUS** requires the stated sensitivity or unresolved bridge; **REJECTED** is scientifically or mechanically ineligible; **MISSING** has no validated construction. The next generated report will emit both dimensions for every parameter.

The two legacy mappings corrected after this snapshot are:

| Parameter | Overall status | `source_control_reconciles` | `model_mapping_admissible` | Reason |
|---|---|---|---|---|
| imports | REJECTED | APPROVED | REJECTED | The signed source rows and total reconcile, but flooring negative valuation adjustments and proportionally rescaling positive rows is not a selected model-import boundary. |
| purchasers_to_basic_price | REJECTED | APPROVED | REJECTED | The code-keyed `T013/T016` arithmetic is reproducible, but the quotient does not identify the recipient-cell margin/tax allocation. |

## Parameter coverage

| Status | Parameters |
|---|---:|
| APPROVED | 38 |
| DUBIOUS | 17 |
| REJECTED | 2 |

| Parameter | Status | Frequency | Unit | Shape | Source(s) | Test note |
|---|---|---|---|---:|---|---|
| years_num | APPROVED | A | MATLAB date number | 1 | Curated U.S. adapter | 2024 year-end structural axis. |
| quarters_num | APPROVED | Q | MATLAB date number | 118 | Curated U.S. adapter | Financial-stock quarter axis 1996Q4–2026Q1. |
| household_cash_quarterly | APPROVED | Q | millions USD | 118 | Federal Reserve Financial Accounts via FRED HNOCDAQ027S | Households and nonprofit organizations; total currency and deposits; asset, level |
| property_income | DUBIOUS | A | millions USD | 1 | BEA NIPA T20100:12+13 | Rental-income boundary plus personal interest/dividends is explicit. |
| mixed_income | APPROVED | A | millions USD | 1 | BEA NIPA T20100:9 | Proprietors' income. |
| firm_cash_quarterly | APPROVED | Q | millions USD | 118 | Federal Reserve Financial Accounts via FRED NCBCDTQ027S+NNBCDAQ027S | Nonfinancial corporate and noncorporate currency and deposits; asset, level |
| firm_debt_quarterly | APPROVED | Q | millions USD | 118 | Federal Reserve Financial Accounts via FRED BOGZ1FL144104005Q | Nonfinancial business debt securities and loans; liability, level |
| firm_debt_consolidation_ratio_quarterly | DUBIOUS | Q | ratio | 118 | Model assumption | Set to 1 pending a documented consolidated/nonconsolidated bridge. |
| firm_interest | DUBIOUS | A | millions USD | 1 | BEA NIPA T71100:7+8 | Nonfinancial corporate plus noncorporate interest paid. |
| government_debt_quarterly | APPROVED | Q | millions USD | 118 | Federal Reserve Financial Accounts via FRED FGTCMDODNS+SLGTCMDODNS | Federal plus state and local debt securities and loans; liability, level |
| interest_government_debt | APPROVED | A | millions USD | 1 | BEA NIPA T30100:27 | Consolidated government interest paid. |
| social_benefits | APPROVED | A | millions USD | 1 | BEA NIPA T20100:17 | Government social benefits to persons. |
| unemployment_benefits | APPROVED | A | millions USD | 1 | BEA NIPA T31200:7 | Unemployment insurance benefits. |
| pension_benefits | APPROVED | A | millions USD | 1 | BEA NIPA T31200:5 | Narrow Social Security definition. |
| corporate_tax | APPROVED | A | millions USD | 1 | BEA NIPA T30100:5 | Taxes on corporate income. |
| wages_by_sector | DUBIOUS | A | millions USD | 68×1 | BLS QCEW wage shares controlled to BEA NIPA wages | Constrained allocation preserves the NIPA wage total and keeps every sector below BEA compensation. |
| social_contributions | APPROVED | A | millions USD | 1 | BEA NIPA T11000:2−3 + T30600:20 | Employer plus employee/self-employed contributions. |
| income_tax | APPROVED | A | millions USD | 1 | BEA NIPA T30100:3+5 | Personal plus corporate tax required by code. |
| capital_taxes | APPROVED | A | millions USD | 1 | BEA NIPA T51100:19+20 | Federal and state/local estate and gift taxes. |
| bank_equity_quarterly | APPROVED | Q | millions USD | 118 | Federal Reserve Financial Accounts via FRED BOGZ1FL704194005Q−BOGZ1FL704190005Q | Private depository institutions total liabilities and equity less liabilities |
| government_deficit | APPROVED | A | millions USD | 1 | BEA NIPA −T30100:43 | Positive-deficit convention. |
| firms | DUBIOUS | A | productive units | 68×1 | Census SUSB + QCEW nowcast + USDA/government/housing proxies | SUSB employer enterprises are nowcast 2022→2024 by QCEW establishments; farms and government require explicit proxies. |
| employees | DUBIOUS | A | persons | 68×1 | BLS QCEW shares rescaled to BLS CPS employed persons | QCEW payroll-job distribution scaled to the 2024 CPS employed-person annual control. |
| population | APPROVED | A | persons | 1 | BLS CPS NSA annual average | 2024 M13 when exposed, otherwise the mean of twelve complete official monthly NSA observations; converted from thousands to persons. |
| fixed_assets | DUBIOUS | A | millions USD | 68×1 | BEA Fixed Assets | Private lines reconcile exactly; government enterprises are allocated by I-O output and HS retains a 0.1% productive-capital/CFC bridge to satisfy the model denominator. |
| dwellings | DUBIOUS | A | millions USD | 68×1 | BEA Fixed Assets | Private lines reconcile exactly; government enterprises are allocated by I-O output and HS retains a 0.1% productive-capital/CFC bridge to satisfy the model denominator. |
| capital_consumption | DUBIOUS | A | millions USD | 68×1 | BEA Fixed Assets | Private lines reconcile exactly; government enterprises are allocated by I-O output and HS retains a 0.1% productive-capital/CFC bridge to satisfy the model denominator. |
| gross_capitalformation_dwellings | DUBIOUS | A | millions USD | 1 | BEA InputOutput 259 | Table 259 F02R plus the Table 262 valuation-bridge product tax. |
| unemployed_census | APPROVED | A | persons | 1 | BLS CPS NSA annual average | 2024 M13 when exposed, otherwise the mean of twelve complete official monthly NSA observations; converted from thousands to persons. |
| inactive_census | APPROVED | A | persons | 1 | BLS CPS NSA annual average | 2024 M13 when exposed, otherwise the mean of twelve complete official monthly NSA observations; converted from thousands to persons. |
| intermediate_consumption | DUBIOUS | A | millions USD | 68×68×1 | BEA InputOutput 259 | 68×68 column-controlled model bridge; approved raw source retained. |
| household_consumption | APPROVED | A | millions USD | 68×1 | BEA InputOutput 259 | Table 259 F010. |
| fixed_capitalformation | APPROVED | A | millions USD | 68×1 | BEA InputOutput 259 | Table 259 private fixed-investment uses F02E+F02N+F02R+F02S, excluding inventories. |
| exports | APPROVED | A | millions USD | 68×1 | BEA InputOutput 259 | Table 259 F040. |
| imports | REJECTED | A | millions USD | 68×1 | BEA InputOutput 262 | `source_control_reconciles=APPROVED`; `model_mapping_admissible=REJECTED`. The signed source rows and total reconcile, but the legacy floor-and-rescale vector is not a selected model-import boundary. |
| purchasers_to_basic_price | REJECTED | A | basic-price supply / purchasers-price supply | 68×1 | BEA InputOutput 262 | `source_control_reconciles=APPROVED`; `model_mapping_admissible=REJECTED`. The code-keyed T013/T016 arithmetic is reproducible, but it does not identify a use-cell valuation allocation. |
| compensation_employees | APPROVED | A | millions USD | 68×1 | BEA InputOutput 259 | Table 259 V001. |
| operating_surplus | APPROVED | A | millions USD | 68×1 | BEA InputOutput 259 | Table 259 V003. |
| government_consumption | APPROVED | A | millions USD | 68×1 | BEA InputOutput 259 | Table 259 federal and state/local consumption plus gross-investment uses F06*/F07*/F10*, matching broad NIPA government demand. |
| taxes_products_household | DUBIOUS | A | millions USD | 1 | BEA InputOutput 259 | Table 262 commodity tax valuation bridge allocated to F010. |
| taxes_products_capitalformation | DUBIOUS | A | millions USD | 1 | BEA InputOutput 259 | Table 262 commodity tax valuation bridge allocated to fixed-investment uses. |
| taxes_production | APPROVED | A | millions USD | 68×1 | BEA InputOutput 259 | Table 259 T00OTOP−T00OSUB. |
| taxes_products_government | DUBIOUS | A | millions USD | 1 | BEA InputOutput 259 | Table 262 commodity tax valuation bridge allocated to government-consumption uses. |
| taxes_products | DUBIOUS | A | millions USD | 68×1 | BEA InputOutput 259 | Table 262 commodity tax valuation bridge allocated to intermediate industries; current model intentionally sets it to zero. |
| nominal_gdp_quarterly | APPROVED | Q | millions USD per quarter | 119 | BEA NIPA T10105:1 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_gdp_quarterly | APPROVED | Q | millions USD per quarter | 119 | BEA NIPA T10106:1 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_household_consumption_quarterly | APPROVED | Q | millions USD per quarter | 119 | BEA NIPA T10106:2 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_fixed_capitalformation_quarterly | DUBIOUS | Q | millions USD per quarter | 119 | BEA NIPA T10106:8 with T10103:8 quantity-index history | Official quarterly SAAR levels divided by four where published; the pre-2007 history is linked from the official quantity index because T10106 exposes chained-dollar fixed-investment levels only from 2007Q1. |
| nominal_wages_quarterly | APPROVED | Q | millions USD per quarter | 119 | BEA Personal Income and Outlays via FRED A576RC1 | Quarterly mean of three monthly SAAR wage-and-salary disbursement levels, multiplied by 1,000 and divided by four. |
| gdp_deflator_quarterly | APPROVED | Q | nominal-to-real GDP ratio | 119 | Derived from BEA NIPA T10105:1 / T10106:1 | Nominal GDP divided by real GDP without multiplying by 100, matching the web Economic outlook ratio. |
| unemployment_rate_quarterly | DUBIOUS | Q | fraction | 122 | BLS CPS LNS14000000 | Quarterly means of SA monthly rates; 2025Q4 includes the explicitly flagged October shutdown interpolation. |
| euribor | APPROVED | Q | annual decimal rate | 119 | FRED FEDFUNDS | Field name is retained at the model boundary; values are quarterly means of the effective federal funds rate divided by 100. |
| real_government_consumption_quarterly | APPROVED | Q | millions USD per quarter | 119 | BEA NIPA T10106:22 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_exports_quarterly | APPROVED | Q | millions USD per quarter | 119 | BEA NIPA T10106:16 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_imports_quarterly | APPROVED | Q | millions USD per quarter | 119 | BEA NIPA T10106:19 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| ea.nominal_gdp_quarterly | APPROVED | Q | millions USD per quarter | 119 | Curated U.S. adapter | U.S. GDP repeated for the U.S. monetary-policy block. |
| ea.real_gdp_quarterly | APPROVED | Q | millions chained USD per quarter | 119 | Curated U.S. adapter | U.S. real GDP repeated for the U.S. monetary-policy block. |

## Source checks

| Source | Dataset | Check | Status | Observed | Expected | Detail |
|---|---|---|---|---|---|---|
| BEA | InputOutput | table_259-2024.http_schema | APPROVED | 200, 4640 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/inputoutput/vintage=2026-08-04/table_259-2024/2bdd65f04e1bf31fd66d1e642afd0fb9dda2fd9bb5ba3bacf8db83431be1e918.json; SHA-256 2bdd65f04e1bf31fd66d1e642afd0fb9dda2fd9bb5ba3bacf8db83431be1e918 |
| BEA | InputOutput | table_262-2024.http_schema | APPROVED | 200, 1728 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/inputoutput/vintage=2026-08-04/table_262-2024/91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8.json; SHA-256 91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8 |
| BEA | NIPA | T11000-A-2024.http_schema | APPROVED | 200, 24 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t11000-a-2024/6cecbaf30f36bf8618117042434a84321a064f7440ea3d6d97dc1e4699ecab91.json; SHA-256 6cecbaf30f36bf8618117042434a84321a064f7440ea3d6d97dc1e4699ecab91 |
| BEA | NIPA | T20100-A-2024.http_schema | APPROVED | 200, 43 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t20100-a-2024/5981c20aacf6a038f67b7ae906d54a32954730ab73affa6d6c208d16009e2ae6.json; SHA-256 5981c20aacf6a038f67b7ae906d54a32954730ab73affa6d6c208d16009e2ae6 |
| BEA | NIPA | T30100-A-2024.http_schema | APPROVED | 200, 43 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t30100-a-2024/88e2ad5a6b9c8daa5b5706585415569e93d70446344f9300b51e16c4c90416d9.json; SHA-256 88e2ad5a6b9c8daa5b5706585415569e93d70446344f9300b51e16c4c90416d9 |
| BEA | NIPA | T30600-A-2024.http_schema | APPROVED | 200, 32 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t30600-a-2024/a63b2652d46209cb0384c3d0fefac38573f1ea792a1f871743a1adeebbb5cec8.json; SHA-256 a63b2652d46209cb0384c3d0fefac38573f1ea792a1f871743a1adeebbb5cec8 |
| BEA | NIPA | T31200-A-2024.http_schema | APPROVED | 200, 42 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t31200-a-2024/bf72593f8dcccf1f40a30fa31a5f95982a3c6e7cce3c5071de1f7b01ce1eb828.json; SHA-256 bf72593f8dcccf1f40a30fa31a5f95982a3c6e7cce3c5071de1f7b01ce1eb828 |
| BEA | NIPA | T51100-A-2024.http_schema | APPROVED | 200, 57 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t51100-a-2024/def1a538357384e48a0fe64daf67a607dd8d6e42c75585f83a32253104b0bce8.json; SHA-256 def1a538357384e48a0fe64daf67a607dd8d6e42c75585f83a32253104b0bce8 |
| BEA | NIPA | T71100-A-2024.http_schema | APPROVED | 200, 109 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t71100-a-2024/0b9f2129d74e9120a19b71b209bb84a34c18be32718d899ec1e8af0509e3c700.json; SHA-256 0b9f2129d74e9120a19b71b209bb84a34c18be32718d899ec1e8af0509e3c700 |
| BEA | NIPA | T10103-Q-history.http_schema | APPROVED | 200, 7632 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t10103-q-history/1b9d0114fb45590cdf01ba7cb3edd046c9678070aae678e6a4e9dc38915a9b48.json; SHA-256 1b9d0114fb45590cdf01ba7cb3edd046c9678070aae678e6a4e9dc38915a9b48 |
| BEA | NIPA | T10105-Q-history.http_schema | APPROVED | 200, 8268 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t10105-q-history/a80351ce2daeccd5994caea385c6ee9f5201fa46ce0c4cab3e7fa19fc8dec574.json; SHA-256 a80351ce2daeccd5994caea385c6ee9f5201fa46ce0c4cab3e7fa19fc8dec574 |
| BEA | NIPA | T10106-Q-history.http_schema | APPROVED | 200, 4766 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/nipa/vintage=2026-08-04/t10106-q-history/21c8c2207024fa70d9c941b5d40f03c00c8067125f38ed764990214fd5b9d0b2.json; SHA-256 21c8c2207024fa70d9c941b5d40f03c00c8067125f38ed764990214fd5b9d0b2 |
| BEA | FixedAssets | FAAt301ESI-2024.http_schema | APPROVED | 200, 96 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/fixedassets/vintage=2026-08-04/faat301esi-2024/2d76397b0eec272a62e745f00b05365dececd259a0ba149e1701361b884811cc.json; SHA-256 2d76397b0eec272a62e745f00b05365dececd259a0ba149e1701361b884811cc |
| BEA | FixedAssets | FAAt304ESI-2024.http_schema | APPROVED | 200, 96 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/fixedassets/vintage=2026-08-04/faat304esi-2024/f30c0026141e1c0eb90fc0fcf25001e6929a5ab64afea47b2a6b42335dc48e31.json; SHA-256 f30c0026141e1c0eb90fc0fcf25001e6929a5ab64afea47b2a6b42335dc48e31 |
| BEA | FixedAssets | FAAt501-2024.http_schema | APPROVED | 200, 12 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/fixedassets/vintage=2026-08-04/faat501-2024/050912d4dac039818c31754cc181344846a683326babc0e5ef67ad04b2702c08.json; SHA-256 050912d4dac039818c31754cc181344846a683326babc0e5ef67ad04b2702c08 |
| BEA | FixedAssets | FAAt504-2024.http_schema | APPROVED | 200, 12 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/fixedassets/vintage=2026-08-04/faat504-2024/00597b6767063eae3a3c0048271348b2ef69f4253126578046613be89b9955d4.json; SHA-256 00597b6767063eae3a3c0048271348b2ef69f4253126578046613be89b9955d4 |
| BEA | FixedAssets | FAAt701-2024.http_schema | APPROVED | 200, 90 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/fixedassets/vintage=2026-08-04/faat701-2024/141f2a03308c216d6d277cf3b1522d45e9c717ea5f04082e662e9abdab49c554.json; SHA-256 141f2a03308c216d6d277cf3b1522d45e9c717ea5f04082e662e9abdab49c554 |
| BEA | FixedAssets | FAAt703-2024.http_schema | APPROVED | 200, 90 rows | HTTP 200 and non-empty Data | Raw response: data/us/raw/bea/fixedassets/vintage=2026-08-04/faat703-2024/c9cf148c060b1fa64443a516e6a82f3384c3acc5f52a37fd4777d8b138af95b4.json; SHA-256 c9cf148c060b1fa64443a516e6a82f3384c3acc5f52a37fd4777d8b138af95b4 |
| FRED | A576RC1 | metadata_and_values | APPROVED | 357 rows; Monthly; Billions of Dollars | Non-empty level/rate series with reviewed metadata | Compensation of Employees, Received: Wage and Salary Disbursements |
| FRED | A576RC1 | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | BOGZ1FL144104005Q | metadata_and_values | APPROVED | 118 rows; Quarterly, End of Period; Millions of U.S. Dollars | Non-empty level/rate series with reviewed metadata | Nonfinancial Business; Debt Securities and Loans; Liability, Level |
| FRED | BOGZ1FL144104005Q | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | BOGZ1FL704190005Q | metadata_and_values | APPROVED | 118 rows; Quarterly, End of Period; Millions of U.S. Dollars | Non-empty level/rate series with reviewed metadata | Private Depository Institutions; Total Liabilities, Level |
| FRED | BOGZ1FL704190005Q | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | BOGZ1FL704194005Q | metadata_and_values | APPROVED | 118 rows; Quarterly, End of Period; Millions of U.S. Dollars | Non-empty level/rate series with reviewed metadata | Private Depository Institutions; Total Liabilities and Equity, Level |
| FRED | BOGZ1FL704194005Q | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | FEDFUNDS | metadata_and_values | APPROVED | 358 rows; Monthly; Percent | Non-empty level/rate series with reviewed metadata | Federal Funds Effective Rate |
| FRED | FEDFUNDS | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | FGTCMDODNS | metadata_and_values | APPROVED | 118 rows; Quarterly, End of Period; Millions of U.S. Dollars | Non-empty level/rate series with reviewed metadata | Federal Government; Debt Securities and Loans; Liability, Level |
| FRED | FGTCMDODNS | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | HNOCDAQ027S | metadata_and_values | APPROVED | 118 rows; Quarterly, End of Period; Millions of U.S. Dollars | Non-empty level/rate series with reviewed metadata | Households and Nonprofit Organizations; Total Currency and Deposits; Asset, Level |
| FRED | HNOCDAQ027S | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | NCBCDTQ027S | metadata_and_values | APPROVED | 118 rows; Quarterly, End of Period; Millions of U.S. Dollars | Non-empty level/rate series with reviewed metadata | Nonfinancial Corporate Business; Total Currency and Deposits; Asset, Level |
| FRED | NCBCDTQ027S | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | NNBCDAQ027S | metadata_and_values | APPROVED | 118 rows; Quarterly, End of Period; Millions of U.S. Dollars | Non-empty level/rate series with reviewed metadata | Nonfinancial Noncorporate Business; Total Currency and Deposits; Asset, Level |
| FRED | NNBCDAQ027S | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| FRED | SLGTCMDODNS | metadata_and_values | APPROVED | 118 rows; Quarterly, End of Period; Millions of U.S. Dollars | Non-empty level/rate series with reviewed metadata | State and Local Governments; Debt Securities and Loans; Liability, Level |
| FRED | SLGTCMDODNS | credential_not_persisted | APPROVED | Sanitized raw response scan | API credential absent | The raw archive redacts any API response credential echo before persistence. |
| BLS | Public Data API | registered_key | APPROVED | REQUEST_SUCCEEDED | REQUEST_SUCCEEDED | Registered access works. |
| BLS | CPS | registered_1996-2005 | APPROVED | REQUEST_SUCCEEDED | REQUEST_SUCCEEDED | Registered access chunk; raw SHA-256 15baa5589af0e5f1f7264e65a176ab95cf7f77a272f3b55739b0685a96afff72 |
| BLS | CPS | registered_2006-2015 | APPROVED | REQUEST_SUCCEEDED | REQUEST_SUCCEEDED | Registered access chunk; raw SHA-256 9a23dd39fbe48fcc24768a335e74997602ffeda76db8984a6904b9e1ae1428d2 |
| BLS | CPS | registered_2016-2025 | APPROVED | REQUEST_SUCCEEDED | REQUEST_SUCCEEDED | Registered access chunk; raw SHA-256 ed6c3c92c4b2039b1f23f842958b2c4f4b7deb3fd39dcb0dd54338890ad1b2e6 |
| BLS | CPS | registered_2026-2026 | APPROVED | REQUEST_SUCCEEDED | REQUEST_SUCCEEDED | Registered access chunk; raw SHA-256 2769315744070707f786cbf00185af04ee0197c9a5ed668f1cc05844b077e25a |
| BLS | CPS | LNS14000000.nonempty | APPROVED | 366 | > 0 monthly observations | unemployment_rate |
| BLS | CPS | LNU00000000.nonempty | APPROVED | 366 | > 0 monthly observations | population |
| BLS | CPS | LNU01000000.nonempty | APPROVED | 366 | > 0 monthly observations | labor_force |
| BLS | CPS | LNU02000000.nonempty | APPROVED | 366 | > 0 monthly observations | employed |
| BLS | CPS | LNU03000000.nonempty | APPROVED | 366 | > 0 monthly observations | unemployed |
| BLS | CPS | LNU05000000.nonempty | APPROVED | 366 | > 0 monthly observations | inactive |
| BLS | QCEW | 2022-annual-US-area.download | APPROVED | 823163 bytes | HTTP 200, non-empty body | data/us/raw/bls/qcew/vintage=2026-08-04/2022-annual-us-area/c45cbb64a1b1eef16bfd743510d9d02792ccad82f60e9df202c5daa3e8c5cc18.csv; SHA-256 c45cbb64a1b1eef16bfd743510d9d02792ccad82f60e9df202c5daa3e8c5cc18 |
| BLS | QCEW | 2022.schema | APPROVED | annual_avg_emplvl, annual_avg_estabs, industry_code, own_code, total_annual_wages | annual_avg_emplvl, annual_avg_estabs, industry_code, own_code, total_annual_wages | 4464 national annual rows |
| BLS | QCEW | 2024-annual-US-area.download | APPROVED | 847197 bytes | HTTP 200, non-empty body | data/us/raw/bls/qcew/vintage=2026-08-04/2024-annual-us-area/48db086828a01798731242c6d3d4957f80f941afe75463a1ff7d43de774bea46.csv; SHA-256 48db086828a01798731242c6d3d4957f80f941afe75463a1ff7d43de774bea46 |
| BLS | QCEW | 2024.schema | APPROVED | annual_avg_emplvl, annual_avg_estabs, industry_code, own_code, total_annual_wages | annual_avg_emplvl, annual_avg_estabs, industry_code, own_code, total_annual_wages | 4526 national annual rows |
| Census | SUSB | 2022-US-state-six-digit-NAICS.download | APPROVED | 56000447 bytes | HTTP 200, non-empty body | data/us/raw/census/susb/vintage=2026-08-04/2022-us-state-six-digit-naics/6f7b2f2b14cbad9dbfeb31d3bfc9f729368a0e971727de4eda88c9f83f77a513.txt; SHA-256 6f7b2f2b14cbad9dbfeb31d3bfc9f729368a0e971727de4eda88c9f83f77a513 |
| Census | SUSB | national_all_enterprises_schema | APPROVED | 2003 selected of 570105 rows | STATE=00, ENTRSIZE=01 rows with FIRM/ESTB/EMPL | Employer enterprises are used as the closest available firm concept. |
| USDA | Farms and Land in Farms | 2025-summary-containing-2024.download | APPROVED | 618881 bytes | HTTP 200, non-empty body | data/us/raw/usda/farms-and-land-in-farms/vintage=2026-08-04/2025-summary-containing-2024/8ed104e9df2280f1daf85ce37b20e68ced001ae23d5c3755c7c32fafecada25b.pdf; SHA-256 8ed104e9df2280f1daf85ce37b20e68ced001ae23d5c3755c7c32fafecada25b |
| USDA | Farms and Land in Farms | manual_extraction | DUBIOUS | 1880000 farms in 2024 | National published farm count | USDA national farm count is used as the agriculture producer-count proxy; a farm is not identical to the model's firm concept. |
| BEA | InputOutput 259/262 | product_tax_valuation_bridge | DUBIOUS | modeled commodities $986971.0m (97.69% of T015); allocation error $0.0m | Commodity product/import taxes allocated across domestic uses; exports remain zero-rated | Table 262 TOP+MDTY+SUB is allocated in proportion to Table 259 domestic intermediate/final uses. Other/Used commodities and inventories remain visible outside current model demand categories. |
| BEA | InputOutput 259 | observed_core_topology | APPROVED | (68, 68); 71 industries aggregated to 68 | 68×68 after 441+445+452+4A0 → 4A0 | No synthetic commodity split is introduced. |
| BEA | InputOutput 259 | intermediate_control_gap | DUBIOUS | Raw sparse core is 98.573% of T005; gap $305953.0m | T005 industry controls | The model bridge scales each industry column to T005; raw observed and bridged matrices are both retained. |
| BEA | InputOutput 259 | output_identity_after_bridge | APPROVED | maximum absolute industry error $2.0m | ≤ $2m BEA rounding | T005 + V001 + V003 + T00OTOP − T00OSUB = T018 |
| BEA | InputOutput 259/262 | cross_table_output_and_use | APPROVED | industry output max error $0.0m; commodity total max error $1.0m | ≤ $2m BEA rounding | Table 259 T018/T019 cross-checks Table 262 T017/T016. |
| BEA | InputOutput 262 | purchasers_to_basic_price_bridge | APPROVED | 68 finite positive ratios; range (0.31607841624030714, 132.4941578483245) | T013/T016 by modeled commodity, with 441+445+452+4A0 aggregated before the 4A0 ratio | The bridge converts purchaser-price use distributions to basic-price producer distributions. Aggregate macro expenditure controls are preserved later during calibration. |
| BEA | InputOutput 259 | exports_structural_control | APPROVED | 68-sector $2.508613e6m + excluded Other/Used $274464.0m = $2.783077e6m | T005/F040 $2.783078e6m (error $-1.0m) | The model retains the 68 observed commodities; noncomparable and used-goods exports remain outside the model vector but are included in this control reconciliation. |
| BEA | InputOutput 262 | imports_structural_control | APPROVED | 68-sector $3.294978e6m + excluded Other/Used $386560.0m = $3.681538e6m | T017/(MCIF+MADJ) $3.681538e6m (error $0.0m) | 4 negative commodity MCIF+MADJ entries (total $-28530.0m) were floored at zero; positive entries were scaled by 0.9914145036936831 to preserve the T017 control net of Other/Used. The raw 68-row sum differed from that control by $4.0m due to published rounding. |
| BEA | T20100 | social_benefits.line_mapping | APPROVED | T20100:17, A063RC, Government social benefits to persons | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T30100 | government_net_lending.line_mapping | APPROVED | T30100:43, AD01RC, Net lending or net borrowing (-) | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T11000 | compensation_employees.line_mapping | APPROVED | T11000:2, A4002C, Compensation of employees, paid | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T31200 | pension_benefits.line_mapping | APPROVED | T31200:5, W823RC, Social security | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T30100 | personal_current_taxes.line_mapping | APPROVED | T30100:3, W055RC, Personal current taxes | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T51100 | federal_estate_gift_taxes.line_mapping | APPROVED | T51100:19, LA000372, Estate and gift taxes, federal | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T11000 | employer_supplements.line_mapping | APPROVED | T11000:6, A038RC, Supplements to wages and salaries | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T51100 | state_local_estate_gift_taxes.line_mapping | APPROVED | T51100:20, S21020, Estate and gift taxes, state and local | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T20100 | mixed_income.line_mapping | APPROVED | T20100:9, A041RC, Proprietors' income with inventory valuation and capital consumption adjustments | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T11000 | wages_total.line_mapping | APPROVED | T11000:3, A4102C, Wages and salaries | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T30600 | social_contributions_household.line_mapping | APPROVED | T30600:20, B228RC, Employee and self-employed contributions | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T30100 | corporate_tax.line_mapping | APPROVED | T30100:5, W025RC, Taxes on corporate income | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T20100 | personal_asset_income.line_mapping | APPROVED | T20100:13, W210RC, Personal income receipts on assets | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T71100 | firm_interest_corporate.line_mapping | APPROVED | T71100:7, B1101C, Nonfinancial | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T31200 | unemployment_benefits.line_mapping | APPROVED | T31200:7, A1589C, Unemployment insurance | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T20100 | rental_income.line_mapping | APPROVED | T20100:12, A048RC, Rental income of persons with capital consumption adjustment | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T71100 | firm_interest_noncorporate.line_mapping | APPROVED | T71100:8, A2064C, Sole proprietorships and partnerships | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | T30100 | government_interest.line_mapping | APPROVED | T30100:27, A180RC, Interest payments | Frozen line number with non-empty official label | 2024 current-dollar annual level, UNIT_MULT=6. |
| BEA | NIPA | social_contribution_semantics | APPROVED | total 3.695834e6; employer 2.639129e6; household 1.056705e6 | total ≥ employer and residual household ≥ 0 | Code-facing total matches the calibration's employer/household subtraction convention. |
| BEA | T10106 | real_imports_quarterly.quarterly_panel | APPROVED | 119 unique quarter rows, 1996-12-31–2026-06-30 | At least 118 unique quarters from 1996Q4 | SAAR flow levels divided by four exactly once. |
| BEA | T10106 | real_gdp_quarterly.quarterly_panel | APPROVED | 119 unique quarter rows, 1996-12-31–2026-06-30 | At least 118 unique quarters from 1996Q4 | SAAR flow levels divided by four exactly once. |
| BEA | T10105 | nominal_gdp_quarterly.quarterly_panel | APPROVED | 119 unique quarter rows, 1996-12-31–2026-06-30 | At least 118 unique quarters from 1996Q4 | SAAR flow levels divided by four exactly once. |
| BEA | T10106 | real_exports_quarterly.quarterly_panel | APPROVED | 119 unique quarter rows, 1996-12-31–2026-06-30 | At least 118 unique quarters from 1996Q4 | SAAR flow levels divided by four exactly once. |
| BEA | T10106 | real_government_consumption_quarterly.quarterly_panel | APPROVED | 119 unique quarter rows, 1996-12-31–2026-06-30 | At least 118 unique quarters from 1996Q4 | SAAR flow levels divided by four exactly once. |
| BEA | T10106 | real_household_consumption_quarterly.quarterly_panel | APPROVED | 119 unique quarter rows, 1996-12-31–2026-06-30 | At least 118 unique quarters from 1996Q4 | SAAR flow levels divided by four exactly once. |
| BEA | T10103+T10106 | real_fixed_capitalformation_quarterly.quantity_index_backcast | APPROVED | 41 linked quarters; factor 8587.474684455126; maximum overlap relative error 6.445973714235457e-6 | Complete 1996Q4–2006Q4 history with a stable T10103/T10106 overlap link | Published T10106 chained-dollar levels are retained exactly from 2007Q1 onward. Earlier levels use the official T10103 quantity index and a robust median link over every published overlap quarter. |
| BEA | T10106 | real_fixed_capitalformation_quarterly.quarterly_panel | APPROVED | 119 unique quarter rows, 1996-12-31–2026-06-30 | At least 118 unique quarters from 1996Q4 | SAAR flow levels divided by four exactly once. |
| FRED | BOGZ1FL144104005Q | firm_debt_quarterly.stock_metadata | APPROVED | 118 quarters, 1996-12-31–2026-03-31; NSA level | 118 complete quarter-end NSA level observations in millions USD | End-of-period stocks are never divided by four. |
| FRED | BOGZ1FL704194005Q+BOGZ1FL704190005Q | bank_equity_quarterly.stock_metadata | APPROVED | 118 quarters, 1996-12-31–2026-03-31; NSA level | 118 complete quarter-end NSA level observations in millions USD | End-of-period stocks are never divided by four. |
| FRED | HNOCDAQ027S | household_cash_quarterly.stock_metadata | APPROVED | 118 quarters, 1996-12-31–2026-03-31; NSA level | 118 complete quarter-end NSA level observations in millions USD | End-of-period stocks are never divided by four. |
| FRED | FGTCMDODNS+SLGTCMDODNS | government_debt_quarterly.stock_metadata | APPROVED | 118 quarters, 1996-12-31–2026-03-31; NSA level | 118 complete quarter-end NSA level observations in millions USD | End-of-period stocks are never divided by four. |
| FRED | NCBCDTQ027S+NNBCDAQ027S | firm_cash_quarterly.stock_metadata | APPROVED | 118 quarters, 1996-12-31–2026-03-31; NSA level | 118 complete quarter-end NSA level observations in millions USD | End-of-period stocks are never divided by four. |
| BLS | CPS | 2024_annual_person_identity | APPROVED | population−employed−unemployed−inactive = -83.33333331346512 persons | within 10,000 persons (published-thousands rounding) | NSA M13 annual averages; people, not payroll jobs. |
| BLS | CPS | 2025_october_shutdown_gap | DUBIOUS | No official October 2025 CPS observation; imputed 4.45% | Explicit, visible bridge if a complete model panel is required | Midpoint of September and November. The source observation remains missing; no official 2025Q4 estimate is claimed. |
| FRED | A576RC1 | monthly_saar_to_quarterly_flow | APPROVED | 119 complete quarters, 1996-12-31–2026-06-30; monthly SAAR billions | At least 119 complete quarters from 1996Q4 through 2026Q2 | Monthly SAAR levels are averaged within each calendar quarter, converted from billions to millions, then divided by four. |
| Curated | quarterly_panel | complete_intersection | APPROVED | 119 complete quarters, 1996-12-31–2026-06-30 | 119 quarters from 1996Q4 through at least 2026Q2 | BEA flows, FRED/BEA nominal wages, CPS unemployment and effective federal funds rate. The GDP deflator is nominal GDP divided by real GDP, matching the web output definition. |
| Census/BLS | SUSB/QCEW | susb_exclusion_proxies | DUBIOUS | 482, 487OS | Explicit QCEW-establishment fallback for SUSB-excluded sectors | Railroads, postal services, and other statutory SUSB exclusions do not have employer-enterprise rows. |
| BLS | QCEW | bea68_mapping_coverage | APPROVED | jobs 99.861%; wages 99.854% | ≥ 99.5% of national all-ownership controls | Exact aggregate NAICS 2022 rows; no descendant double counting. |
| BEA | FixedAssets | private_and_government_stock_controls | APPROVED | private error $-2.0m; government error $0.0m | ≤ $2m BEA rounding | Private sector lines plus HS/ORE special split; government level/enterprise allocation preserves national controls. |
| Curated | model_contract | quarterly_annual_timescale | APPROVED | 0.25920035304053934 | 0.20–0.30 | Quarterly nominal GDP divided by the annual structural income-account proxy; catches accidental SAAR or stock division. |
| BeforeIT | calibrated parameters | shape_share_rate_covariance | APPROVED | 68 sectors; demand/network shares sum to one; minimum covariance eigenvalue 3.563274457856033e-5 | Finite shapes, normalized shares, plausible effective rates, PSD covariance | Both structural and nowcast artifacts passed construction-time finite-value checks. |
| Pipeline | raw archive | credential_persistence_scan | APPROVED | 338 files scanned; 0 credential matches | zero configured API-key byte sequences | Credential values are never printed. BEA response echoes are redacted before archival. |
| BeforeIT | structural baseline | simulation_smoke_4 | APPROVED | finite=true, positive GDP=true, max bank residual=4.0978193283081055e-8 | finite positive outputs and bank residuals ≤ 1.0e-6 | Seed 20260803; serial simulation. |
| BeforeIT | nowcast baseline | simulation_smoke_4 | APPROVED | finite=true, positive GDP=true, max bank residual=1.1175870895385742e-8 | finite positive outputs and bank residuals ≤ 1.0e-6 | Seed 20260804; serial simulation. |
