-- =============================================================================
-- US BeforeIT.jl - Core Economic Data Tables (BigQuery Compatible)
-- =============================================================================

-- GDP and National Accounts Data
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.gdp_national_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- GDP Components (Expenditure Approach) - Billions USD
  nominal_gdp FLOAT64,
  real_gdp FLOAT64,
  gdp_deflator FLOAT64,
  gdp_growth FLOAT64,
  
  -- GDP Components
  nominal_consumption FLOAT64,
  real_consumption FLOAT64,
  nominal_investment FLOAT64,
  real_investment FLOAT64,
  nominal_government FLOAT64,
  real_government FLOAT64,
  nominal_exports FLOAT64,
  real_exports FLOAT64,
  nominal_imports FLOAT64,
  real_imports FLOAT64,
  
  -- Income Components
  nominal_gva FLOAT64,
  real_gva FLOAT64,
  compensation_employees FLOAT64,
  operating_surplus FLOAT64,
  taxes_production FLOAT64,
  
  -- Investment Detail
  nominal_fixed_investment FLOAT64,
  real_fixed_investment FLOAT64,
  nominal_residential_investment FLOAT64,
  real_residential_investment FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter
OPTIONS (
  description = "Core US GDP and National Accounts data from BEA NIPA tables"
);

-- Personal Income and Consumption Data
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.personal_income_consumption` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Personal Income Components - Billions USD
  personal_income FLOAT64,
  disposable_personal_income FLOAT64,
  personal_saving FLOAT64,
  personal_saving_rate FLOAT64,
  
  -- Consumption by Category
  consumption_total FLOAT64,
  consumption_goods FLOAT64,
  consumption_services FLOAT64,
  consumption_durable_goods FLOAT64,
  consumption_nondurable_goods FLOAT64,
  
  -- Income by Source
  wages_salaries FLOAT64,
  proprietors_income FLOAT64,
  rental_income FLOAT64,
  personal_dividend_income FLOAT64,
  personal_interest_income FLOAT64,
  
  -- Taxes and Transfers
  personal_current_taxes FLOAT64,
  social_insurance_contributions FLOAT64,
  government_social_benefits FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter
OPTIONS (
  description = "US Personal Income and Consumption data from BEA NIPA tables"
);

-- Labor Market Data
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.labor_market` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_month INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Employment and Labor Force - Thousands of persons
  civilian_labor_force FLOAT64,
  employment_total FLOAT64,
  unemployment_total FLOAT64,
  unemployment_rate FLOAT64,
  labor_force_participation_rate FLOAT64,
  
  -- Employment by Status
  employment_full_time FLOAT64,
  employment_part_time FLOAT64,
  
  -- Demographic Breakdowns
  unemployment_rate_16_19 FLOAT64,
  unemployment_rate_20_24 FLOAT64,
  unemployment_rate_25_54 FLOAT64,
  unemployment_rate_55_over FLOAT64,
  
  -- Wages and Earnings
  average_hourly_earnings FLOAT64,
  average_weekly_hours FLOAT64,
  average_weekly_earnings FLOAT64,
  
  -- Job Flows
  job_openings FLOAT64,
  hires FLOAT64,
  quits FLOAT64,
  layoffs_discharges FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter, date_month
OPTIONS (
  description = "US Labor Market data from BLS surveys (CPS, CES, JOLTS)"
);

-- Interest Rates and Monetary Data
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.interest_rates_monetary` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_month INT64,
  date_day INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Policy Rates - Percent per annum
  federal_funds_rate FLOAT64,
  discount_rate FLOAT64,
  
  -- Treasury Rates
  treasury_3month FLOAT64,
  treasury_6month FLOAT64,
  treasury_1year FLOAT64,
  treasury_2year FLOAT64,
  treasury_5year FLOAT64,
  treasury_10year FLOAT64,
  treasury_30year FLOAT64,
  
  -- Corporate and Commercial Rates
  corporate_aaa FLOAT64,
  corporate_baa FLOAT64,
  commercial_paper_3month FLOAT64,
  prime_rate FLOAT64,
  
  -- Money Supply - Billions USD, seasonally adjusted
  money_supply_m1 FLOAT64,
  money_supply_m2 FLOAT64,
  monetary_base FLOAT64,
  
  -- Mortgage Rates
  mortgage_30year_fixed FLOAT64,
  mortgage_15year_fixed FLOAT64,
  
  -- Real Interest Rates (ex-post, using CPI)
  real_federal_funds_rate FLOAT64,
  real_treasury_10year FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter, date_month
OPTIONS (
  description = "US Interest Rates and Monetary data from Federal Reserve (H.15, H.6)"
);

-- External Trade Data
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.external_trade` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_month INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Trade Flows - Billions USD
  exports_goods_services FLOAT64,
  imports_goods_services FLOAT64,
  trade_balance FLOAT64,
  
  -- Goods Trade
  exports_goods FLOAT64,
  imports_goods FLOAT64,
  goods_trade_balance FLOAT64,
  
  -- Services Trade
  exports_services FLOAT64,
  imports_services FLOAT64,
  services_trade_balance FLOAT64,
  
  -- Trade by Major Categories
  exports_capital_goods FLOAT64,
  imports_capital_goods FLOAT64,
  exports_consumer_goods FLOAT64,
  imports_consumer_goods FLOAT64,
  exports_industrial_supplies FLOAT64,
  imports_industrial_supplies FLOAT64,
  
  -- Current Account Components
  current_account_balance FLOAT64,
  income_receipts FLOAT64,
  income_payments FLOAT64,
  secondary_income_receipts FLOAT64,
  secondary_income_payments FLOAT64,
  
  -- Exchange Rates
  usd_broad_index FLOAT64,
  usd_major_currencies_index FLOAT64,
  usd_oitp_index FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter, date_month
OPTIONS (
  description = "US External Trade data from BEA International Accounts and Census Bureau"
);