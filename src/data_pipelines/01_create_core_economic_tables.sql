-- =============================================================================
-- US BeforeIT.jl - Core Economic Data Tables
-- =============================================================================
-- This script creates the core economic data tables for the US BeforeIT.jl
-- economic modeling framework. These tables store national accounts data,
-- GDP components, and key macroeconomic indicators.
-- =============================================================================

-- Dataset already created in initialization script
-- CREATE SCHEMA IF NOT EXISTS `marketsreplica.us_beforeit_data`

-- =============================================================================
-- GDP and National Accounts Data
-- =============================================================================
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.gdp_national_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL COMMENT "Year (YYYY format)",
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL or QUARTERLY",
  
  -- GDP Components (Expenditure Approach) - Billions USD
  nominal_gdp FLOAT64 COMMENT "Nominal Gross Domestic Product (current prices)",
  real_gdp FLOAT64 COMMENT "Real Gross Domestic Product (chained 2012 dollars)",
  gdp_deflator FLOAT64 COMMENT "GDP deflator index (2012=100)",
  gdp_growth FLOAT64 COMMENT "Real GDP growth rate (quarter-over-quarter or year-over-year)",
  
  -- GDP Components
  nominal_consumption FLOAT64 COMMENT "Nominal personal consumption expenditures",
  real_consumption FLOAT64 COMMENT "Real personal consumption expenditures (chained 2012 dollars)",
  nominal_investment FLOAT64 COMMENT "Nominal gross private domestic investment",
  real_investment FLOAT64 COMMENT "Real gross private domestic investment (chained 2012 dollars)",
  nominal_government FLOAT64 COMMENT "Nominal government consumption expenditures",
  real_government FLOAT64 COMMENT "Real government consumption expenditures (chained 2012 dollars)",
  nominal_exports FLOAT64 COMMENT "Nominal exports of goods and services",
  real_exports FLOAT64 COMMENT "Real exports of goods and services (chained 2012 dollars)",
  nominal_imports FLOAT64 COMMENT "Nominal imports of goods and services",
  real_imports FLOAT64 COMMENT "Real imports of goods and services (chained 2012 dollars)",
  
  -- Income Components
  nominal_gva FLOAT64 COMMENT "Nominal gross value added",
  real_gva FLOAT64 COMMENT "Real gross value added (chained 2012 dollars)",
  compensation_employees FLOAT64 COMMENT "Compensation of employees",
  operating_surplus FLOAT64 COMMENT "Gross operating surplus",
  taxes_production FLOAT64 COMMENT "Taxes on production and imports",
  
  -- Investment Detail
  nominal_fixed_investment FLOAT64 COMMENT "Nominal gross private fixed investment",
  real_fixed_investment FLOAT64 COMMENT "Real gross private fixed investment (chained 2012 dollars)",
  nominal_residential_investment FLOAT64 COMMENT "Nominal residential fixed investment",
  real_residential_investment FLOAT64 COMMENT "Real residential fixed investment (chained 2012 dollars)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BEA_NIPA_TABLE_1_1_1)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP() COMMENT "Record last updated timestamp",
  
  -- Note: BigQuery doesn't support primary key constraints
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter
OPTIONS (
  description = "Core US GDP and National Accounts data from BEA NIPA tables",
  labels = [("data_type", "national_accounts"), ("frequency", "mixed"), ("source", "bea")]
);

-- =============================================================================
-- Personal Income and Consumption Data
-- =============================================================================
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.personal_income_consumption` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL or QUARTERLY",
  
  -- Personal Income Components - Billions USD
  personal_income FLOAT64 COMMENT "Personal income",
  disposable_personal_income FLOAT64 COMMENT "Disposable personal income",
  personal_saving FLOAT64 COMMENT "Personal saving",
  personal_saving_rate FLOAT64 COMMENT "Personal saving rate (percent)",
  
  -- Consumption by Category
  consumption_total FLOAT64 COMMENT "Total personal consumption expenditures",
  consumption_goods FLOAT64 COMMENT "Personal consumption expenditures: goods",
  consumption_services FLOAT64 COMMENT "Personal consumption expenditures: services",
  consumption_durable_goods FLOAT64 COMMENT "Personal consumption expenditures: durable goods",
  consumption_nondurable_goods FLOAT64 COMMENT "Personal consumption expenditures: nondurable goods",
  
  -- Income by Source
  wages_salaries FLOAT64 COMMENT "Wages and salaries",
  proprietors_income FLOAT64 COMMENT "Proprietors' income",
  rental_income FLOAT64 COMMENT "Rental income of persons",
  personal_dividend_income FLOAT64 COMMENT "Personal dividend income",
  personal_interest_income FLOAT64 COMMENT "Personal interest income",
  
  -- Taxes and Transfers
  personal_current_taxes FLOAT64 COMMENT "Personal current taxes",
  social_insurance_contributions FLOAT64 COMMENT "Contributions for social insurance",
  government_social_benefits FLOAT64 COMMENT "Government social benefits to persons",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BEA_NIPA_TABLE_2_1)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  -- Note: BigQuery doesn't support primary key constraints
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter
OPTIONS (
  description = "US Personal Income and Consumption data from BEA NIPA tables",
  labels = [("data_type", "personal_income"), ("frequency", "mixed"), ("source", "bea")]
);

-- =============================================================================
-- Labor Market Data
-- =============================================================================
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.labor_market` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_month INT64 COMMENT "Month (1-12, for monthly data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL, QUARTERLY, or MONTHLY",
  
  -- Employment and Labor Force - Thousands of persons
  civilian_labor_force FLOAT64 COMMENT "Civilian labor force (thousands)",
  employment_total FLOAT64 COMMENT "Total civilian employment (thousands)",
  unemployment_total FLOAT64 COMMENT "Total unemployment (thousands)",
  unemployment_rate FLOAT64 COMMENT "Unemployment rate (percent)",
  labor_force_participation_rate FLOAT64 COMMENT "Labor force participation rate (percent)",
  
  -- Employment by Status
  employment_full_time FLOAT64 COMMENT "Full-time employment (thousands)",
  employment_part_time FLOAT64 COMMENT "Part-time employment (thousands)",
  
  -- Demographic Breakdowns
  unemployment_rate_16_19 FLOAT64 COMMENT "Unemployment rate, 16-19 years (percent)",
  unemployment_rate_20_24 FLOAT64 COMMENT "Unemployment rate, 20-24 years (percent)",
  unemployment_rate_25_54 FLOAT64 COMMENT "Unemployment rate, 25-54 years (percent)",
  unemployment_rate_55_over FLOAT64 COMMENT "Unemployment rate, 55+ years (percent)",
  
  -- Wages and Earnings
  average_hourly_earnings FLOAT64 COMMENT "Average hourly earnings of production workers (dollars)",
  average_weekly_hours FLOAT64 COMMENT "Average weekly hours of production workers",
  average_weekly_earnings FLOAT64 COMMENT "Average weekly earnings of production workers (dollars)",
  
  -- Job Flows
  job_openings FLOAT64 COMMENT "Job openings (thousands, JOLTS survey)",
  hires FLOAT64 COMMENT "Total hires (thousands, JOLTS survey)",
  quits FLOAT64 COMMENT "Total quits (thousands, JOLTS survey)",
  layoffs_discharges FLOAT64 COMMENT "Layoffs and discharges (thousands, JOLTS survey)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BLS_CPS, BLS_CES, BLS_JOLTS)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  -- Note: BigQuery doesn't support primary key constraints
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter, date_month
OPTIONS (
  description = "US Labor Market data from BLS surveys (CPS, CES, JOLTS)",
  labels = [("data_type", "labor_market"), ("frequency", "mixed"), ("source", "bls")]
);

-- =============================================================================
-- Interest Rates and Monetary Data
-- =============================================================================
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.interest_rates_monetary` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_month INT64 COMMENT "Month (1-12, for monthly data)",
  date_day INT64 COMMENT "Day (1-31, for daily data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL, QUARTERLY, MONTHLY, or DAILY",
  
  -- Policy Rates - Percent per annum
  federal_funds_rate FLOAT64 COMMENT "Federal funds effective rate (percent)",
  discount_rate FLOAT64 COMMENT "Primary credit rate (discount rate) (percent)",
  
  -- Treasury Rates
  treasury_3month FLOAT64 COMMENT "3-month Treasury bill rate (percent)",
  treasury_6month FLOAT64 COMMENT "6-month Treasury bill rate (percent)",
  treasury_1year FLOAT64 COMMENT "1-year Treasury constant maturity rate (percent)",
  treasury_2year FLOAT64 COMMENT "2-year Treasury constant maturity rate (percent)",
  treasury_5year FLOAT64 COMMENT "5-year Treasury constant maturity rate (percent)",
  treasury_10year FLOAT64 COMMENT "10-year Treasury constant maturity rate (percent)",
  treasury_30year FLOAT64 COMMENT "30-year Treasury constant maturity rate (percent)",
  
  -- Corporate and Commercial Rates
  corporate_aaa FLOAT64 COMMENT "Corporate bond yield, AAA-rated (percent)",
  corporate_baa FLOAT64 COMMENT "Corporate bond yield, BAA-rated (percent)",
  commercial_paper_3month FLOAT64 COMMENT "3-month commercial paper rate (percent)",
  prime_rate FLOAT64 COMMENT "Bank prime loan rate (percent)",
  
  -- Money Supply - Billions USD, seasonally adjusted
  money_supply_m1 FLOAT64 COMMENT "Money supply M1 (billions USD)",
  money_supply_m2 FLOAT64 COMMENT "Money supply M2 (billions USD)",
  monetary_base FLOAT64 COMMENT "Monetary base (billions USD)",
  
  -- Mortgage Rates
  mortgage_30year_fixed FLOAT64 COMMENT "30-year fixed mortgage rate (percent)",
  mortgage_15year_fixed FLOAT64 COMMENT "15-year fixed mortgage rate (percent)",
  
  -- Real Interest Rates (ex-post, using CPI)
  real_federal_funds_rate FLOAT64 COMMENT "Real federal funds rate (percent)",
  real_treasury_10year FLOAT64 COMMENT "Real 10-year Treasury rate (percent)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., FED_H15, FED_H6, FRED)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  -- Note: BigQuery doesn't support primary key constraints
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter, date_month
OPTIONS (
  description = "US Interest Rates and Monetary data from Federal Reserve (H.15, H.6)",
  labels = [("data_type", "monetary"), ("frequency", "mixed"), ("source", "federal_reserve")]
);

-- =============================================================================
-- External Trade Data
-- =============================================================================
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.external_trade` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_month INT64 COMMENT "Month (1-12, for monthly data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL, QUARTERLY, or MONTHLY",
  
  -- Trade Flows - Billions USD
  exports_goods_services FLOAT64 COMMENT "Exports of goods and services",
  imports_goods_services FLOAT64 COMMENT "Imports of goods and services",
  trade_balance FLOAT64 COMMENT "Trade balance (exports - imports)",
  
  -- Goods Trade
  exports_goods FLOAT64 COMMENT "Exports of goods",
  imports_goods FLOAT64 COMMENT "Imports of goods",
  goods_trade_balance FLOAT64 COMMENT "Goods trade balance",
  
  -- Services Trade
  exports_services FLOAT64 COMMENT "Exports of services",
  imports_services FLOAT64 COMMENT "Imports of services",
  services_trade_balance FLOAT64 COMMENT "Services trade balance",
  
  -- Trade by Major Categories
  exports_capital_goods FLOAT64 COMMENT "Exports of capital goods",
  imports_capital_goods FLOAT64 COMMENT "Imports of capital goods",
  exports_consumer_goods FLOAT64 COMMENT "Exports of consumer goods",
  imports_consumer_goods FLOAT64 COMMENT "Imports of consumer goods",
  exports_industrial_supplies FLOAT64 COMMENT "Exports of industrial supplies",
  imports_industrial_supplies FLOAT64 COMMENT "Imports of industrial supplies",
  
  -- Current Account Components
  current_account_balance FLOAT64 COMMENT "Current account balance",
  income_receipts FLOAT64 COMMENT "Primary income receipts",
  income_payments FLOAT64 COMMENT "Primary income payments",
  secondary_income_receipts FLOAT64 COMMENT "Secondary income receipts",
  secondary_income_payments FLOAT64 COMMENT "Secondary income payments",
  
  -- Exchange Rates
  usd_broad_index FLOAT64 COMMENT "US dollar broad trade-weighted index",
  usd_major_currencies_index FLOAT64 COMMENT "US dollar major currencies index",
  usd_oitp_index FLOAT64 COMMENT "US dollar other important trading partners index",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BEA_INTERNATIONAL, CENSUS_TRADE)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  -- Note: BigQuery doesn't support primary key constraints
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter, date_month
OPTIONS (
  description = "US External Trade data from BEA International Accounts and Census Bureau",
  labels = [("data_type", "external_trade"), ("frequency", "mixed"), ("source", "bea_census")]
);