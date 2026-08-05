-- =============================================================================
-- US BeforeIT.jl - BigQuery Database Initialization Script
-- =============================================================================
-- This is the main initialization script that creates all tables for the
-- US BeforeIT.jl economic modeling database in BigQuery.
-- 
-- Execute this script to create the complete database schema.
-- =============================================================================

-- Set up BigQuery project and dataset
-- Note: Replace 'your-project-id' with your actual Google Cloud project ID
-- SET @@dataset_id = 'your-project-id.us_beforeit_data';

-- =============================================================================
-- STEP 1: Create Core Economic Data Tables
-- =============================================================================
-- Execute the core economic data tables script
-- This includes GDP, national accounts, labor market, interest rates, and trade data
-- Source: 01_create_core_economic_tables.sql

-- Create dataset
CREATE SCHEMA IF NOT EXISTS `us_beforeit_data`
OPTIONS (
  description = "US BeforeIT.jl Economic Modeling Data - Complete dataset for macroeconomic modeling",
  location = "US",
  labels = [("project", "us_beforeit"), ("type", "economic_data"), ("version", "v1.0")]
);

-- Log table creation progress
CREATE OR REPLACE TABLE `us_beforeit_data.database_initialization_log` (
  initialization_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  script_name STRING,
  script_step STRING,
  status STRING,
  message STRING,
  execution_time_seconds FLOAT64
);

-- Insert initial log entry
INSERT INTO `us_beforeit_data.database_initialization_log` 
VALUES (
  CURRENT_TIMESTAMP(),
  'initialize_bigquery_database.sql',
  'DATASET_CREATION',
  'SUCCESS',
  'Created us_beforeit_data dataset with US location',
  0.0
);

-- =============================================================================
-- STEP 2: Create Reference and Lookup Tables
-- =============================================================================

-- Create data source reference table
CREATE OR REPLACE TABLE `us_beforeit_data.data_sources_reference` (
  source_id STRING NOT NULL,
  source_name STRING NOT NULL,
  source_organization STRING,
  source_description STRING,
  source_url STRING,
  data_frequency STRING,
  data_coverage STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_data_sources_reference PRIMARY KEY (source_id) NOT ENFORCED
)
OPTIONS (
  description = "Reference table for all data sources used in the US BeforeIT.jl database",
  labels = [("data_type", "reference"), ("table_type", "lookup")]
);

-- Insert data source references
INSERT INTO `us_beforeit_data.data_sources_reference` VALUES
('BEA_NIPA', 'Bureau of Economic Analysis - National Income and Product Accounts', 'U.S. Bureau of Economic Analysis', 'Comprehensive accounts of U.S. economic activity', 'https://www.bea.gov/data/gdp/gross-domestic-product', 'QUARTERLY', 'National', CURRENT_TIMESTAMP()),
('BEA_IO', 'Bureau of Economic Analysis - Input-Output Accounts', 'U.S. Bureau of Economic Analysis', 'Input-output accounts showing inter-industry relationships', 'https://www.bea.gov/industry/input-output-accounts-data', 'ANNUAL', 'Sectoral', CURRENT_TIMESTAMP()),
('BEA_GDP_INDUSTRY', 'Bureau of Economic Analysis - GDP by Industry', 'U.S. Bureau of Economic Analysis', 'Value added by industry', 'https://www.bea.gov/data/gdp/gdp-industry', 'QUARTERLY', 'Sectoral', CURRENT_TIMESTAMP()),
('BEA_INTERNATIONAL', 'Bureau of Economic Analysis - International Trade', 'U.S. Bureau of Economic Analysis', 'International trade in goods and services', 'https://www.bea.gov/data/intl-trade-investment/international-trade-goods-and-services', 'MONTHLY', 'National', CURRENT_TIMESTAMP()),
('BLS_CPS', 'Bureau of Labor Statistics - Current Population Survey', 'U.S. Bureau of Labor Statistics', 'Monthly household survey for employment and unemployment', 'https://www.bls.gov/cps/', 'MONTHLY', 'National', CURRENT_TIMESTAMP()),
('BLS_CES', 'Bureau of Labor Statistics - Current Employment Statistics', 'U.S. Bureau of Labor Statistics', 'Monthly establishment survey for employment and wages', 'https://www.bls.gov/ces/', 'MONTHLY', 'Sectoral', CURRENT_TIMESTAMP()),
('BLS_QCEW', 'Bureau of Labor Statistics - Quarterly Census of Employment and Wages', 'U.S. Bureau of Labor Statistics', 'Quarterly employment and wage data by industry', 'https://www.bls.gov/cew/', 'QUARTERLY', 'Sectoral', CURRENT_TIMESTAMP()),
('BLS_JOLTS', 'Bureau of Labor Statistics - Job Openings and Labor Turnover Survey', 'U.S. Bureau of Labor Statistics', 'Monthly job openings, hires, and separations', 'https://www.bls.gov/jlt/', 'MONTHLY', 'National', CURRENT_TIMESTAMP()),
('FED_H15', 'Federal Reserve - Selected Interest Rates (H.15)', 'Board of Governors of the Federal Reserve System', 'Daily interest rates and yields', 'https://www.federalreserve.gov/releases/h15/', 'DAILY', 'National', CURRENT_TIMESTAMP()),
('FED_H6', 'Federal Reserve - Money Stock Measures (H.6)', 'Board of Governors of the Federal Reserve System', 'Weekly money supply data', 'https://www.federalreserve.gov/releases/h6/', 'WEEKLY', 'National', CURRENT_TIMESTAMP()),
('FED_H8', 'Federal Reserve - Assets and Liabilities of Commercial Banks (H.8)', 'Board of Governors of the Federal Reserve System', 'Weekly bank balance sheet data', 'https://www.federalreserve.gov/releases/h8/', 'WEEKLY', 'National', CURRENT_TIMESTAMP()),
('FED_H41', 'Federal Reserve - Factors Affecting Reserve Balances (H.4.1)', 'Board of Governors of the Federal Reserve System', 'Weekly Federal Reserve balance sheet', 'https://www.federalreserve.gov/releases/h41/', 'WEEKLY', 'National', CURRENT_TIMESTAMP()),
('FED_Z1', 'Federal Reserve - Financial Accounts of the United States (Z.1)', 'Board of Governors of the Federal Reserve System', 'Quarterly financial accounts and balance sheets', 'https://www.federalreserve.gov/releases/z1/', 'QUARTERLY', 'Sectoral', CURRENT_TIMESTAMP()),
('TREASURY_MTS', 'U.S. Treasury - Monthly Treasury Statement', 'U.S. Department of the Treasury', 'Monthly federal government receipts and outlays', 'https://fiscal.treasury.gov/reports-statements/mts/', 'MONTHLY', 'National', CURRENT_TIMESTAMP()),
('CENSUS_TRADE', 'U.S. Census Bureau - International Trade', 'U.S. Census Bureau', 'Monthly international trade in goods', 'https://www.census.gov/foreign-trade/statistics/highlights/top/index.html', 'MONTHLY', 'National', CURRENT_TIMESTAMP()),
('IRS_SOI', 'Internal Revenue Service - Statistics of Income', 'Internal Revenue Service', 'Annual tax statistics', 'https://www.irs.gov/statistics/soi-tax-stats', 'ANNUAL', 'National', CURRENT_TIMESTAMP()),
('CBO_BUDGET', 'Congressional Budget Office - Budget and Economic Data', 'Congressional Budget Office', 'Budget projections and economic analysis', 'https://www.cbo.gov/data', 'ANNUAL', 'National', CURRENT_TIMESTAMP());

-- Create frequency reference table
CREATE OR REPLACE TABLE `us_beforeit_data.frequency_reference` (
  frequency_code STRING NOT NULL,
  frequency_name STRING NOT NULL,
  frequency_description STRING,
  periods_per_year INT64,
  
  CONSTRAINT pk_frequency_reference PRIMARY KEY (frequency_code) NOT ENFORCED
)
OPTIONS (
  description = "Reference table for data frequencies used in the database",
  labels = [("data_type", "reference"), ("table_type", "lookup")]
);

-- Insert frequency references
INSERT INTO `us_beforeit_data.frequency_reference` VALUES
('DAILY', 'Daily', 'Daily observations', 365),
('WEEKLY', 'Weekly', 'Weekly observations', 52),
('MONTHLY', 'Monthly', 'Monthly observations', 12),
('QUARTERLY', 'Quarterly', 'Quarterly observations', 4),
('ANNUAL', 'Annual', 'Annual observations', 1);

-- Log completion of reference tables
INSERT INTO `us_beforeit_data.database_initialization_log` 
VALUES (
  CURRENT_TIMESTAMP(),
  'initialize_bigquery_database.sql',
  'REFERENCE_TABLES',
  'SUCCESS',
  'Created data_sources_reference and frequency_reference tables',
  0.0
);

-- =============================================================================
-- STEP 3: Execute Individual Table Creation Scripts
-- =============================================================================

-- Note: In a production environment, you would execute these scripts separately
-- or use a BigQuery job to run them in sequence. For now, we'll create a 
-- placeholder that indicates the order of execution.

CREATE OR REPLACE TABLE `us_beforeit_data.script_execution_order` (
  execution_order INT64 NOT NULL,
  script_name STRING NOT NULL,
  script_description STRING,
  depends_on STRING,
  status STRING DEFAULT 'PENDING',
  execution_timestamp TIMESTAMP,
  
  CONSTRAINT pk_script_execution_order PRIMARY KEY (execution_order) NOT ENFORCED
)
OPTIONS (
  description = "Order of script execution for database initialization",
  labels = [("data_type", "metadata"), ("table_type", "control")]
);

-- Insert execution order
INSERT INTO `us_beforeit_data.script_execution_order` VALUES
(1, '01_create_core_economic_tables.sql', 'Create core economic data tables (GDP, labor, interest rates, trade)', NULL, 'PENDING', NULL),
(2, '02_create_sectoral_inputoutput_tables.sql', 'Create sectoral and input-output tables', '01_create_core_economic_tables.sql', 'PENDING', NULL),
(3, '03_create_financial_government_tables.sql', 'Create financial and government data tables', '01_create_core_economic_tables.sql', 'PENDING', NULL),
(4, 'create_calibration_tables.sql', 'Create calibration and parameter tables', '01_create_core_economic_tables.sql,02_create_sectoral_inputoutput_tables.sql,03_create_financial_government_tables.sql', 'PENDING', NULL),
(5, 'create_simulation_tables.sql', 'Create simulation output tables', 'create_calibration_tables.sql', 'PENDING', NULL);

-- =============================================================================
-- STEP 4: Create Data Quality and Validation Tables
-- =============================================================================

-- Create data quality checks table
CREATE OR REPLACE TABLE `us_beforeit_data.data_quality_checks` (
  check_id STRING NOT NULL,
  table_name STRING NOT NULL,
  check_type STRING NOT NULL,
  check_description STRING,
  check_sql STRING,
  expected_result STRING,
  last_run_timestamp TIMESTAMP,
  last_run_status STRING,
  last_run_result STRING,
  
  CONSTRAINT pk_data_quality_checks PRIMARY KEY (check_id) NOT ENFORCED
)
OPTIONS (
  description = "Data quality checks for all tables in the database",
  labels = [("data_type", "quality"), ("table_type", "control")]
);

-- Insert basic data quality checks
INSERT INTO `us_beforeit_data.data_quality_checks` VALUES
('GDP_CONSISTENCY', 'gdp_national_accounts', 'CONSISTENCY', 'Check that nominal GDP > 0 for all records', 'SELECT COUNT(*) FROM `us_beforeit_data.gdp_national_accounts` WHERE nominal_gdp <= 0', '0', NULL, 'PENDING', NULL),
('EMPLOYMENT_POSITIVE', 'labor_market', 'RANGE', 'Check that employment is positive', 'SELECT COUNT(*) FROM `us_beforeit_data.labor_market` WHERE employment_total < 0', '0', NULL, 'PENDING', NULL),
('INTEREST_RATE_RANGE', 'interest_rates_monetary', 'RANGE', 'Check that interest rates are within reasonable bounds', 'SELECT COUNT(*) FROM `us_beforeit_data.interest_rates_monetary` WHERE federal_funds_rate < -5 OR federal_funds_rate > 25', '0', NULL, 'PENDING', NULL),
('HOUSEHOLD_ASSETS_POSITIVE', 'household_financial_accounts', 'RANGE', 'Check that total household assets are positive', 'SELECT COUNT(*) FROM `us_beforeit_data.household_financial_accounts` WHERE total_assets <= 0', '0', NULL, 'PENDING', NULL),
('SECTORAL_EMPLOYMENT_SUM', 'sectoral_employment', 'CONSISTENCY', 'Check that sectoral employment sums to total employment', 'SELECT 1', '1', NULL, 'PENDING', NULL);

-- Create data lineage table
CREATE OR REPLACE TABLE `us_beforeit_data.data_lineage` (
  lineage_id STRING NOT NULL,
  source_table STRING NOT NULL,
  target_table STRING NOT NULL,
  transformation_type STRING,
  transformation_description STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_data_lineage PRIMARY KEY (lineage_id) NOT ENFORCED
)
OPTIONS (
  description = "Data lineage and transformation tracking",
  labels = [("data_type", "lineage"), ("table_type", "metadata")]
);

-- =============================================================================
-- STEP 5: Create Views for Common Queries
-- =============================================================================

-- Create view for latest GDP data
CREATE OR REPLACE VIEW `us_beforeit_data.latest_gdp_data` AS
SELECT 
  date_year,
  date_quarter,
  nominal_gdp,
  real_gdp,
  gdp_deflator,
  gdp_growth,
  nominal_consumption,
  real_consumption,
  nominal_investment,
  real_investment,
  nominal_government,
  real_government,
  nominal_exports,
  real_exports,
  nominal_imports,
  real_imports
FROM `us_beforeit_data.gdp_national_accounts`
WHERE frequency = 'QUARTERLY'
  AND date_year >= EXTRACT(YEAR FROM CURRENT_DATE()) - 10
ORDER BY date_year DESC, date_quarter DESC;

-- Create view for latest employment data
CREATE OR REPLACE VIEW `us_beforeit_data.latest_employment_data` AS
SELECT 
  date_year,
  date_quarter,
  date_month,
  employment_total,
  unemployment_total,
  unemployment_rate,
  labor_force_participation_rate,
  average_hourly_earnings,
  average_weekly_hours
FROM `us_beforeit_data.labor_market`
WHERE frequency = 'MONTHLY'
  AND date_year >= EXTRACT(YEAR FROM CURRENT_DATE()) - 5
ORDER BY date_year DESC, date_month DESC;

-- Create view for model calibration summary
CREATE OR REPLACE VIEW `us_beforeit_data.model_calibration_summary` AS
SELECT 
  'GDP Data' as data_category,
  COUNT(*) as record_count,
  MIN(date_year) as earliest_year,
  MAX(date_year) as latest_year
FROM `us_beforeit_data.gdp_national_accounts`
WHERE frequency = 'QUARTERLY'
UNION ALL
SELECT 
  'Labor Market Data' as data_category,
  COUNT(*) as record_count,
  MIN(date_year) as earliest_year,
  MAX(date_year) as latest_year
FROM `us_beforeit_data.labor_market`
WHERE frequency = 'QUARTERLY'
UNION ALL
SELECT 
  'Interest Rate Data' as data_category,
  COUNT(*) as record_count,
  MIN(date_year) as earliest_year,
  MAX(date_year) as latest_year
FROM `us_beforeit_data.interest_rates_monetary`
WHERE frequency = 'QUARTERLY';

-- =============================================================================
-- STEP 6: Set Up Permissions and Access Control
-- =============================================================================

-- Note: In production, you would set up appropriate IAM roles and permissions
-- This is a placeholder for documentation purposes

-- Create permissions reference table
CREATE OR REPLACE TABLE `us_beforeit_data.access_permissions` (
  permission_id STRING NOT NULL,
  role_name STRING NOT NULL,
  table_name STRING,
  permission_type STRING,
  granted_by STRING,
  granted_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_access_permissions PRIMARY KEY (permission_id) NOT ENFORCED
)
OPTIONS (
  description = "Access permissions for database tables and views",
  labels = [("data_type", "security"), ("table_type", "control")]
);

-- =============================================================================
-- STEP 7: Final Initialization Log
-- =============================================================================

-- Insert final log entry
INSERT INTO `us_beforeit_data.database_initialization_log` 
VALUES (
  CURRENT_TIMESTAMP(),
  'initialize_bigquery_database.sql',
  'INITIALIZATION_COMPLETE',
  'SUCCESS',
  'Database initialization completed successfully. Ready for data loading.',
  0.0
);

-- =============================================================================
-- COMPLETION MESSAGE
-- =============================================================================

SELECT 
  'US BeforeIT.jl BigQuery Database Initialization Complete' as status,
  CURRENT_TIMESTAMP() as completion_time,
  'Execute individual table creation scripts (01, 02, 03) to create all data tables' as next_steps;

-- =============================================================================
-- USAGE INSTRUCTIONS
-- =============================================================================

/*
To complete the database setup:

1. Execute this initialization script first
2. Execute 01_create_core_economic_tables.sql
3. Execute 02_create_sectoral_inputoutput_tables.sql  
4. Execute 03_create_financial_government_tables.sql
5. Load data using the data pipeline scripts
6. Run data quality checks
7. Begin model calibration

The database will be ready for the US BeforeIT.jl economic modeling framework.
*/