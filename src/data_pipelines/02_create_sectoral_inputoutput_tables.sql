-- =============================================================================
-- US BeforeIT.jl - Sectoral and Input-Output Tables
-- =============================================================================
-- This script creates the sectoral and input-output tables for the US BeforeIT.jl
-- economic modeling framework. These tables store detailed industry-level data,
-- employment by sector, and input-output relationships.
-- =============================================================================

-- =============================================================================
-- Industry Classification Reference Table
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.industry_classification` (
  -- Industry identifiers
  naics_code STRING NOT NULL COMMENT "6-digit NAICS code",
  naics_2digit STRING COMMENT "2-digit NAICS sector code",
  naics_title STRING NOT NULL COMMENT "Official NAICS industry title",
  
  -- BeforeIT mapping
  beforeit_sector_id INT64 COMMENT "BeforeIT internal sector ID (1-71)",
  beforeit_sector_name STRING COMMENT "BeforeIT sector name",
  beforeit_aggregate_id INT64 COMMENT "BeforeIT aggregate sector ID (1-10)",
  beforeit_aggregate_name STRING COMMENT "BeforeIT aggregate sector name",
  
  -- EU NACE mapping for compatibility
  nace_code STRING COMMENT "Corresponding EU NACE code (for comparison)",
  nace_title STRING COMMENT "EU NACE industry title",
  
  -- Industry characteristics
  industry_type STRING COMMENT "Industry type: GOODS, SERVICES, or GOVERNMENT",
  is_tradable BOOLEAN COMMENT "Whether industry produces tradable goods/services",
  is_manufacturing BOOLEAN COMMENT "Whether industry is manufacturing",
  is_government BOOLEAN COMMENT "Whether industry is government sector",
  
  -- Metadata
  classification_version STRING COMMENT "NAICS classification version (e.g., 2017)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_industry_classification PRIMARY KEY (naics_code) NOT ENFORCED
)
CLUSTER BY beforeit_sector_id, naics_2digit
OPTIONS (
  description = "Industry classification mapping between NAICS, BeforeIT sectors, and EU NACE",
  labels = [("data_type", "reference"), ("source", "census_bureau")]
);

-- =============================================================================
-- Sectoral Employment Data
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.sectoral_employment` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_month INT64 COMMENT "Month (1-12, for monthly data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL, QUARTERLY, or MONTHLY",
  
  -- Industry identifiers
  naics_code STRING NOT NULL COMMENT "6-digit NAICS industry code",
  beforeit_sector_id INT64 COMMENT "BeforeIT internal sector ID (1-71)",
  
  -- Employment measures - Thousands of persons
  total_employment FLOAT64 COMMENT "Total employment (thousands)",
  production_workers FLOAT64 COMMENT "Production and nonsupervisory employees (thousands)",
  all_employees FLOAT64 COMMENT "All employees (thousands)",
  
  -- Hours and earnings
  average_weekly_hours FLOAT64 COMMENT "Average weekly hours of production workers",
  average_hourly_earnings FLOAT64 COMMENT "Average hourly earnings of production workers (dollars)",
  average_weekly_earnings FLOAT64 COMMENT "Average weekly earnings of production workers (dollars)",
  
  -- Establishment data
  number_establishments FLOAT64 COMMENT "Number of establishments (from QCEW)",
  total_wages FLOAT64 COMMENT "Total wages paid (millions USD, from QCEW)",
  
  -- Job flows (from JOLTS when available)
  job_openings FLOAT64 COMMENT "Job openings (thousands)",
  hires FLOAT64 COMMENT "Total hires (thousands)",
  quits FLOAT64 COMMENT "Total quits (thousands)",
  layoffs_discharges FLOAT64 COMMENT "Layoffs and discharges (thousands)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BLS_CES, BLS_QCEW, BLS_JOLTS)",
  is_seasonally_adjusted BOOLEAN COMMENT "Whether data is seasonally adjusted",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_sectoral_employment PRIMARY KEY (date_year, date_quarter, date_month, frequency, naics_code) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY beforeit_sector_id, frequency, date_quarter
OPTIONS (
  description = "US Employment data by industry from BLS (CES, QCEW, JOLTS)",
  labels = [("data_type", "sectoral_employment"), ("frequency", "mixed"), ("source", "bls")]
);

-- =============================================================================
-- Sectoral Output and Value Added
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.sectoral_output` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL or QUARTERLY",
  
  -- Industry identifiers
  naics_code STRING NOT NULL COMMENT "6-digit NAICS industry code",
  beforeit_sector_id INT64 COMMENT "BeforeIT internal sector ID (1-71)",
  
  -- Output measures - Billions USD
  nominal_gross_output FLOAT64 COMMENT "Nominal gross output (current prices)",
  real_gross_output FLOAT64 COMMENT "Real gross output (chained 2012 dollars)",
  gross_output_deflator FLOAT64 COMMENT "Gross output deflator (2012=100)",
  
  -- Value added measures
  nominal_value_added FLOAT64 COMMENT "Nominal value added (current prices)",
  real_value_added FLOAT64 COMMENT "Real value added (chained 2012 dollars)",
  value_added_deflator FLOAT64 COMMENT "Value added deflator (2012=100)",
  
  -- Value added components
  compensation_employees FLOAT64 COMMENT "Compensation of employees",
  gross_operating_surplus FLOAT64 COMMENT "Gross operating surplus",
  taxes_production FLOAT64 COMMENT "Taxes on production and imports less subsidies",
  
  -- Intermediate inputs
  nominal_intermediate_inputs FLOAT64 COMMENT "Nominal intermediate inputs",
  real_intermediate_inputs FLOAT64 COMMENT "Real intermediate inputs (chained 2012 dollars)",
  
  -- Capital measures
  capital_stock FLOAT64 COMMENT "Net stock of fixed assets (end of period)",
  capital_services FLOAT64 COMMENT "Capital services flow",
  depreciation FLOAT64 COMMENT "Consumption of fixed capital",
  
  -- Productivity measures
  labor_productivity FLOAT64 COMMENT "Labor productivity (output per hour)",
  multifactor_productivity FLOAT64 COMMENT "Multifactor productivity index",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BEA_GDP_BY_INDUSTRY, BEA_KLEMS)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_sectoral_output PRIMARY KEY (date_year, date_quarter, frequency, naics_code) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY beforeit_sector_id, frequency, date_quarter
OPTIONS (
  description = "US Sectoral Output and Value Added data from BEA GDP-by-Industry accounts",
  labels = [("data_type", "sectoral_output"), ("frequency", "mixed"), ("source", "bea")]
);

-- =============================================================================
-- Input-Output Use Table
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.input_output_use` (
  -- Time identifiers
  date_year INT64 NOT NULL COMMENT "Year of input-output table",
  io_table_type STRING NOT NULL COMMENT "Table type: BENCHMARK or ANNUAL",
  
  -- Industry identifiers
  using_industry_naics STRING NOT NULL COMMENT "NAICS code of industry using input",
  using_industry_beforeit_id INT64 COMMENT "BeforeIT sector ID of using industry",
  supplying_industry_naics STRING NOT NULL COMMENT "NAICS code of industry supplying input",
  supplying_industry_beforeit_id INT64 COMMENT "BeforeIT sector ID of supplying industry",
  
  -- Use table values - Millions USD
  intermediate_use FLOAT64 COMMENT "Intermediate use (millions USD)",
  
  -- Technical coefficients
  technical_coefficient FLOAT64 COMMENT "Technical coefficient (input per unit output)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BEA_IO_USE_TABLE)",
  table_detail_level STRING COMMENT "Detail level: SUMMARY, SECTOR, or DETAILED",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_input_output_use PRIMARY KEY (date_year, io_table_type, using_industry_naics, supplying_industry_naics) NOT ENFORCED
)
PARTITION BY date_year
CLUSTER BY using_industry_beforeit_id, supplying_industry_beforeit_id
OPTIONS (
  description = "US Input-Output Use Table showing intermediate consumption by industry",
  labels = [("data_type", "input_output"), ("source", "bea")]
);

-- =============================================================================
-- Input-Output Make Table
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.input_output_make` (
  -- Time identifiers
  date_year INT64 NOT NULL COMMENT "Year of input-output table",
  io_table_type STRING NOT NULL COMMENT "Table type: BENCHMARK or ANNUAL",
  
  -- Industry and commodity identifiers
  industry_naics STRING NOT NULL COMMENT "NAICS code of producing industry",
  industry_beforeit_id INT64 COMMENT "BeforeIT sector ID of producing industry",
  commodity_code STRING NOT NULL COMMENT "Commodity code",
  commodity_description STRING COMMENT "Commodity description",
  
  -- Make table values - Millions USD
  commodity_output FLOAT64 COMMENT "Commodity output by industry (millions USD)",
  
  -- Market shares
  market_share FLOAT64 COMMENT "Industry's share of total commodity production",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BEA_IO_MAKE_TABLE)",
  table_detail_level STRING COMMENT "Detail level: SUMMARY, SECTOR, or DETAILED",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_input_output_make PRIMARY KEY (date_year, io_table_type, industry_naics, commodity_code) NOT ENFORCED
)
PARTITION BY date_year
CLUSTER BY industry_beforeit_id
OPTIONS (
  description = "US Input-Output Make Table showing commodity production by industry",
  labels = [("data_type", "input_output"), ("source", "bea")]
);

-- =============================================================================
-- Final Demand by Industry
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.final_demand_by_industry` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL or QUARTERLY",
  
  -- Industry identifiers
  naics_code STRING NOT NULL COMMENT "6-digit NAICS industry code",
  beforeit_sector_id INT64 COMMENT "BeforeIT internal sector ID (1-71)",
  
  -- Final demand components - Millions USD
  personal_consumption FLOAT64 COMMENT "Personal consumption expenditures",
  government_consumption FLOAT64 COMMENT "Government consumption expenditures",
  gross_private_investment FLOAT64 COMMENT "Gross private domestic investment",
  exports FLOAT64 COMMENT "Exports of goods and services",
  imports FLOAT64 COMMENT "Imports of goods and services (negative)",
  
  -- Investment detail
  nonresidential_investment FLOAT64 COMMENT "Nonresidential fixed investment",
  residential_investment FLOAT64 COMMENT "Residential fixed investment",
  inventory_investment FLOAT64 COMMENT "Change in private inventories",
  
  -- Government detail
  federal_government FLOAT64 COMMENT "Federal government consumption",
  state_local_government FLOAT64 COMMENT "State and local government consumption",
  
  -- Trade detail
  goods_exports FLOAT64 COMMENT "Exports of goods",
  services_exports FLOAT64 COMMENT "Exports of services",
  goods_imports FLOAT64 COMMENT "Imports of goods (negative)",
  services_imports FLOAT64 COMMENT "Imports of services (negative)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BEA_IO_FINAL_DEMAND)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_final_demand_by_industry PRIMARY KEY (date_year, date_quarter, frequency, naics_code) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY beforeit_sector_id, frequency, date_quarter
OPTIONS (
  description = "US Final Demand by Industry from BEA Input-Output accounts",
  labels = [("data_type", "final_demand"), ("frequency", "mixed"), ("source", "bea")]
);

-- =============================================================================
-- Sectoral Capital Stock and Investment
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.sectoral_capital` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL or QUARTERLY",
  
  -- Industry identifiers
  naics_code STRING NOT NULL COMMENT "6-digit NAICS industry code",
  beforeit_sector_id INT64 COMMENT "BeforeIT internal sector ID (1-71)",
  
  -- Capital stock measures - Billions USD
  net_capital_stock FLOAT64 COMMENT "Net stock of fixed assets (end of period)",
  gross_capital_stock FLOAT64 COMMENT "Gross stock of fixed assets (end of period)",
  
  -- Capital stock by type
  structures FLOAT64 COMMENT "Net stock of structures",
  equipment FLOAT64 COMMENT "Net stock of equipment",
  intellectual_property FLOAT64 COMMENT "Net stock of intellectual property products",
  
  -- Investment flows
  gross_investment FLOAT64 COMMENT "Gross investment in fixed assets",
  net_investment FLOAT64 COMMENT "Net investment in fixed assets",
  depreciation FLOAT64 COMMENT "Consumption of fixed capital (depreciation)",
  
  -- Investment by type
  structures_investment FLOAT64 COMMENT "Investment in structures",
  equipment_investment FLOAT64 COMMENT "Investment in equipment",
  intellectual_property_investment FLOAT64 COMMENT "Investment in intellectual property",
  
  -- Residential capital (for relevant sectors)
  residential_capital_stock FLOAT64 COMMENT "Net stock of residential fixed assets",
  residential_investment FLOAT64 COMMENT "Residential fixed investment",
  
  -- Capital services and returns
  capital_services FLOAT64 COMMENT "Capital services flow",
  user_cost_capital FLOAT64 COMMENT "User cost of capital",
  return_on_capital FLOAT64 COMMENT "Rate of return on capital",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., BEA_FIXED_ASSETS)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_sectoral_capital PRIMARY KEY (date_year, date_quarter, frequency, naics_code) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY beforeit_sector_id, frequency, date_quarter
OPTIONS (
  description = "US Sectoral Capital Stock and Investment data from BEA Fixed Assets accounts",
  labels = [("data_type", "sectoral_capital"), ("frequency", "mixed"), ("source", "bea")]
);

-- =============================================================================
-- Create indexes for better query performance
-- =============================================================================

-- Index for industry classification lookups
CREATE INDEX IF NOT EXISTS idx_industry_classification_beforeit 
ON `us_beforeit_data.industry_classification` (beforeit_sector_id, naics_2digit);

-- Index for sectoral employment time series queries
CREATE INDEX IF NOT EXISTS idx_sectoral_employment_time_series 
ON `us_beforeit_data.sectoral_employment` (beforeit_sector_id, frequency, date_year, date_quarter);

-- Index for sectoral output time series queries
CREATE INDEX IF NOT EXISTS idx_sectoral_output_time_series 
ON `us_beforeit_data.sectoral_output` (beforeit_sector_id, frequency, date_year, date_quarter);

-- Index for input-output table queries
CREATE INDEX IF NOT EXISTS idx_input_output_use_coefficients 
ON `us_beforeit_data.input_output_use` (date_year, using_industry_beforeit_id, supplying_industry_beforeit_id);