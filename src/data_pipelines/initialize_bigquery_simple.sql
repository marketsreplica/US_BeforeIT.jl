-- =============================================================================
-- US BeforeIT.jl - BigQuery Database Initialization Script (Simplified)
-- =============================================================================
-- This script creates the dataset and basic tables for US BeforeIT.jl
-- =============================================================================

-- Create dataset
CREATE SCHEMA IF NOT EXISTS `marketsreplica.us_beforeit_data`
OPTIONS (
  description = "US BeforeIT.jl Economic Modeling Data",
  location = "US"
);

-- Log table creation progress
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.database_initialization_log` (
  initialization_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  script_name STRING,
  script_step STRING,
  status STRING,
  message STRING,
  execution_time_seconds FLOAT64
);

-- Insert initial log entry
INSERT INTO `marketsreplica.us_beforeit_data.database_initialization_log` 
VALUES (
  CURRENT_TIMESTAMP(),
  'initialize_bigquery_simple.sql',
  'DATASET_CREATION',
  'SUCCESS',
  'Created us_beforeit_data dataset with US location',
  0.0
);

-- Create data source reference table
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.data_sources_reference` (
  source_id STRING NOT NULL,
  source_name STRING NOT NULL,
  source_organization STRING,
  source_description STRING,
  source_url STRING,
  data_frequency STRING,
  data_coverage STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
OPTIONS (
  description = "Reference table for all data sources used in the US BeforeIT.jl database"
);

-- Create frequency reference table
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.frequency_reference` (
  frequency_code STRING NOT NULL,
  frequency_name STRING NOT NULL,
  frequency_description STRING,
  periods_per_year INT64
)
OPTIONS (
  description = "Reference table for data frequencies used in the database"
);

-- Insert frequency references
INSERT INTO `marketsreplica.us_beforeit_data.frequency_reference` VALUES
('DAILY', 'Daily', 'Daily observations', 365),
('WEEKLY', 'Weekly', 'Weekly observations', 52),
('MONTHLY', 'Monthly', 'Monthly observations', 12),
('QUARTERLY', 'Quarterly', 'Quarterly observations', 4),
('ANNUAL', 'Annual', 'Annual observations', 1);

-- Insert final log entry
INSERT INTO `marketsreplica.us_beforeit_data.database_initialization_log` 
VALUES (
  CURRENT_TIMESTAMP(),
  'initialize_bigquery_simple.sql',
  'INITIALIZATION_COMPLETE',
  'SUCCESS',
  'Basic database initialization completed successfully.',
  0.0
);

SELECT 
  'US BeforeIT.jl BigQuery Database Initialization Complete' as status,
  CURRENT_TIMESTAMP() as completion_time;