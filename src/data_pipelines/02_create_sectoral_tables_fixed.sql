-- =============================================================================
-- US BeforeIT.jl - Sectoral and Input-Output Tables (BigQuery Compatible)
-- =============================================================================

-- Industry Classification Reference Table
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.industry_classification` (
  -- Industry identifiers
  naics_code STRING NOT NULL,
  naics_2digit STRING,
  naics_title STRING NOT NULL,
  
  -- BeforeIT mapping
  beforeit_sector_id INT64,
  beforeit_sector_name STRING,
  beforeit_aggregate_id INT64,
  beforeit_aggregate_name STRING,
  
  -- EU NACE mapping for compatibility
  nace_code STRING,
  nace_title STRING,
  
  -- Industry characteristics
  industry_type STRING,
  is_tradable BOOLEAN,
  is_manufacturing BOOLEAN,
  is_government BOOLEAN,
  
  -- Metadata
  classification_version STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY beforeit_sector_id, naics_2digit
OPTIONS (
  description = "Industry classification mapping between NAICS, BeforeIT sectors, and EU NACE"
);

-- Sectoral Employment Data
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.sectoral_employment` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_month INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Industry identifiers
  naics_code STRING NOT NULL,
  beforeit_sector_id INT64,
  
  -- Employment measures - Thousands of persons
  total_employment FLOAT64,
  production_workers FLOAT64,
  all_employees FLOAT64,
  
  -- Hours and earnings
  average_weekly_hours FLOAT64,
  average_hourly_earnings FLOAT64,
  average_weekly_earnings FLOAT64,
  
  -- Establishment data
  number_establishments FLOAT64,
  total_wages FLOAT64,
  
  -- Job flows (from JOLTS when available)
  job_openings FLOAT64,
  hires FLOAT64,
  quits FLOAT64,
  layoffs_discharges FLOAT64,
  
  -- Metadata
  data_source STRING,
  is_seasonally_adjusted BOOLEAN,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY beforeit_sector_id, frequency, date_quarter
OPTIONS (
  description = "US Employment data by industry from BLS (CES, QCEW, JOLTS)"
);

-- Sectoral Output and Value Added
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.sectoral_output` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Industry identifiers
  naics_code STRING NOT NULL,
  beforeit_sector_id INT64,
  
  -- Output measures - Billions USD
  nominal_gross_output FLOAT64,
  real_gross_output FLOAT64,
  gross_output_deflator FLOAT64,
  
  -- Value added measures
  nominal_value_added FLOAT64,
  real_value_added FLOAT64,
  value_added_deflator FLOAT64,
  
  -- Value added components
  compensation_employees FLOAT64,
  gross_operating_surplus FLOAT64,
  taxes_production FLOAT64,
  
  -- Intermediate inputs
  nominal_intermediate_inputs FLOAT64,
  real_intermediate_inputs FLOAT64,
  
  -- Capital measures
  capital_stock FLOAT64,
  capital_services FLOAT64,
  depreciation FLOAT64,
  
  -- Productivity measures
  labor_productivity FLOAT64,
  multifactor_productivity FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY beforeit_sector_id, frequency, date_quarter
OPTIONS (
  description = "US Sectoral Output and Value Added data from BEA GDP-by-Industry accounts"
);

-- Input-Output Use Table
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.input_output_use` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  io_table_type STRING NOT NULL,
  
  -- Industry identifiers
  using_industry_naics STRING NOT NULL,
  using_industry_beforeit_id INT64,
  supplying_industry_naics STRING NOT NULL,
  supplying_industry_beforeit_id INT64,
  
  -- Use table values - Millions USD
  intermediate_use FLOAT64,
  
  -- Technical coefficients
  technical_coefficient FLOAT64,
  
  -- Metadata
  data_source STRING,
  table_detail_level STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY using_industry_beforeit_id, supplying_industry_beforeit_id
OPTIONS (
  description = "US Input-Output Use Table showing intermediate consumption by industry"
);

-- Input-Output Make Table
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.input_output_make` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  io_table_type STRING NOT NULL,
  
  -- Industry and commodity identifiers
  industry_naics STRING NOT NULL,
  industry_beforeit_id INT64,
  commodity_code STRING NOT NULL,
  commodity_description STRING,
  
  -- Make table values - Millions USD
  commodity_output FLOAT64,
  
  -- Market shares
  market_share FLOAT64,
  
  -- Metadata
  data_source STRING,
  table_detail_level STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY industry_beforeit_id
OPTIONS (
  description = "US Input-Output Make Table showing commodity production by industry"
);

-- Final Demand by Industry
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.final_demand_by_industry` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Industry identifiers
  naics_code STRING NOT NULL,
  beforeit_sector_id INT64,
  
  -- Final demand components - Millions USD
  personal_consumption FLOAT64,
  government_consumption FLOAT64,
  gross_private_investment FLOAT64,
  exports FLOAT64,
  imports FLOAT64,
  
  -- Investment detail
  nonresidential_investment FLOAT64,
  residential_investment FLOAT64,
  inventory_investment FLOAT64,
  
  -- Government detail
  federal_government FLOAT64,
  state_local_government FLOAT64,
  
  -- Trade detail
  goods_exports FLOAT64,
  services_exports FLOAT64,
  goods_imports FLOAT64,
  services_imports FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY beforeit_sector_id, frequency, date_quarter
OPTIONS (
  description = "US Final Demand by Industry from BEA Input-Output accounts"
);

-- Sectoral Capital Stock and Investment
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.sectoral_capital` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Industry identifiers
  naics_code STRING NOT NULL,
  beforeit_sector_id INT64,
  
  -- Capital stock measures - Billions USD
  net_capital_stock FLOAT64,
  gross_capital_stock FLOAT64,
  
  -- Capital stock by type
  structures FLOAT64,
  equipment FLOAT64,
  intellectual_property FLOAT64,
  
  -- Investment flows
  gross_investment FLOAT64,
  net_investment FLOAT64,
  depreciation FLOAT64,
  
  -- Investment by type
  structures_investment FLOAT64,
  equipment_investment FLOAT64,
  intellectual_property_investment FLOAT64,
  
  -- Residential capital (for relevant sectors)
  residential_capital_stock FLOAT64,
  residential_investment FLOAT64,
  
  -- Capital services and returns
  capital_services FLOAT64,
  user_cost_capital FLOAT64,
  return_on_capital FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY beforeit_sector_id, frequency, date_quarter
OPTIONS (
  description = "US Sectoral Capital Stock and Investment data from BEA Fixed Assets accounts"
);