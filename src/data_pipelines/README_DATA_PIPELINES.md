# US BeforeIT.jl BigQuery Database Schema

This directory contains the BigQuery database schema and initialization scripts for the US BeforeIT.jl economic modeling framework.

## Overview

The US BeforeIT.jl database is designed to store comprehensive economic data required for agent-based macroeconomic modeling. The database includes national accounts data, sectoral input-output relationships, financial accounts, government fiscal data, and all necessary variables for model calibration and simulation.

## Database Structure

### Core Components

1. **Core Economic Data** - GDP, national accounts, labor market, interest rates, trade
2. **Sectoral Data** - Industry-level employment, output, input-output relationships
3. **Financial Data** - Balance sheets, financial flows, banking sector data
4. **Government Data** - Fiscal operations, tax policy, central bank operations
5. **Reference Data** - Industry classifications, data sources, quality controls

### Data Sources

The database integrates data from multiple US government agencies:

- **Bureau of Economic Analysis (BEA)** - GDP, national accounts, input-output tables
- **Bureau of Labor Statistics (BLS)** - Employment, wages, labor market data
- **Federal Reserve** - Interest rates, money supply, financial accounts
- **U.S. Treasury** - Government fiscal data
- **U.S. Census Bureau** - Trade data
- **Internal Revenue Service (IRS)** - Tax data

## File Structure

```
src/data_pipelines/
├── README.md                                    # This file
├── initialize_bigquery_database.sql           # Main initialization script
├── 01_create_core_economic_tables.sql         # Core economic data tables
├── 02_create_sectoral_inputoutput_tables.sql  # Sectoral and I-O tables
├── 03_create_financial_government_tables.sql  # Financial and government tables
└── schema_documentation/                       # Detailed schema documentation
```

## Quick Start

### 1. Prerequisites

- Google Cloud Platform account with BigQuery enabled
- Appropriate IAM permissions for BigQuery dataset creation
- Access to US economic data sources (see [Data Sources](#data-sources))

### 2. Database Initialization

Execute the scripts in the following order:

```bash
# 1. Initialize the database and create the dataset
bq query --use_legacy_sql=false < initialize_bigquery_database.sql

# 2. Create core economic data tables
bq query --use_legacy_sql=false < 01_create_core_economic_tables.sql

# 3. Create sectoral and input-output tables
bq query --use_legacy_sql=false < 02_create_sectoral_inputoutput_tables.sql

# 4. Create financial and government tables
bq query --use_legacy_sql=false < 03_create_financial_government_tables.sql
```

### 3. Verify Installation

```sql
-- Check that all tables were created successfully
SELECT table_name, creation_time, row_count
FROM `us_beforeit_data.INFORMATION_SCHEMA.TABLES`
WHERE table_schema = 'us_beforeit_data'
ORDER BY creation_time;
```

## Database Schema Details

### Core Economic Tables

| Table Name | Description | Key Variables | Frequency |
|------------|-------------|---------------|-----------|
| `gdp_national_accounts` | GDP and national accounts data | GDP, consumption, investment, government spending, trade | Quarterly/Annual |
| `personal_income_consumption` | Personal income and consumption | Disposable income, consumption by category, saving rate | Quarterly/Annual |
| `labor_market` | Employment and labor market data | Employment, unemployment, wages, hours worked | Monthly/Quarterly |
| `interest_rates_monetary` | Interest rates and monetary data | Federal funds rate, Treasury rates, money supply | Daily/Weekly/Monthly |
| `external_trade` | International trade data | Exports, imports, trade balance, exchange rates | Monthly/Quarterly |

### Sectoral Tables

| Table Name | Description | Key Variables | Frequency |
|------------|-------------|---------------|-----------|
| `industry_classification` | Industry classification mapping | NAICS codes, BeforeIT sector mapping | Reference |
| `sectoral_employment` | Employment by industry | Employment, wages, hours by sector | Monthly/Quarterly |
| `sectoral_output` | Output and value added by industry | Gross output, value added, productivity | Quarterly/Annual |
| `input_output_use` | Input-output use table | Intermediate consumption matrix | Annual |
| `input_output_make` | Input-output make table | Commodity production by industry | Annual |
| `final_demand_by_industry` | Final demand by industry | Consumption, investment, exports by sector | Quarterly/Annual |
| `sectoral_capital` | Capital stock by industry | Capital stock, investment, depreciation | Quarterly/Annual |

### Financial Tables

| Table Name | Description | Key Variables | Frequency |
|------------|-------------|---------------|-----------|
| `household_financial_accounts` | Household balance sheets | Assets, liabilities, net worth | Quarterly |
| `corporate_financial_accounts` | Corporate balance sheets | Corporate assets, debt, equity | Quarterly |
| `banking_sector_accounts` | Banking sector balance sheets | Bank assets, deposits, loans, capital | Quarterly |
| `government_financial_accounts` | Government balance sheets | Government assets, debt by level | Quarterly |
| `government_fiscal_operations` | Government fiscal operations | Revenue, expenditure, deficit by level | Monthly/Quarterly |
| `tax_rates_policy` | Tax rates and policy parameters | Tax rates, bases, effective rates | Quarterly/Annual |
| `central_bank_operations` | Federal Reserve operations | Fed balance sheet, monetary policy | Weekly/Monthly |

## Data Dictionary

### Key Data Types and Conventions

- **Monetary Values**: Stored in billions of USD unless otherwise specified
- **Rates**: Stored as percentages (e.g., 5.25 for 5.25%)
- **Time Identifiers**: Separate columns for year, quarter, month to enable flexible queries
- **MATLAB Compatibility**: `date_matlab_num` fields for compatibility with existing Julia code
- **Frequency Indicators**: All tables include frequency field to distinguish data periodicity

### Industry Classification

The database uses a mapping between:
- **NAICS**: North American Industry Classification System (US standard)
- **BeforeIT Sectors**: Internal 71-sector classification used by the model
- **NACE**: European classification (for compatibility with EU data)

### Data Quality Features

- **Constraints**: Primary key constraints for data integrity
- **Partitioning**: Tables partitioned by year for query performance
- **Clustering**: Tables clustered by key dimensions for optimal performance
- **Indexing**: Strategic indexes for common query patterns
- **Validation**: Built-in data quality checks and validation rules

## Model Integration

### Calibration Data Requirements

The database schema matches the requirements identified in the BeforeIT.jl model:

1. **Time Series Data**: Quarterly/annual economic indicators for model estimation
2. **Sectoral Data**: 71-sector disaggregation for structural modeling
3. **Financial Flows**: Complete financial accounts for agent balance sheets
4. **Government Data**: Detailed fiscal operations for government sector modeling
5. **Initial Conditions**: All required variables for model initialization

### Data Transformation Pipeline

The database supports the BeforeIT.jl calibration pipeline:

1. **Raw Data Ingestion**: Loading data from multiple government sources
2. **Harmonization**: Converting data to consistent formats and frequencies
3. **Validation**: Ensuring data quality and consistency
4. **Aggregation**: Creating model-ready aggregates and derived variables
5. **Export**: Generating MATLAB/Julia-compatible calibration files

## Usage Examples

### Basic GDP Query

```sql
SELECT 
  date_year,
  date_quarter,
  nominal_gdp,
  real_gdp,
  gdp_growth
FROM `us_beforeit_data.gdp_national_accounts`
WHERE frequency = 'QUARTERLY'
  AND date_year >= 2010
ORDER BY date_year DESC, date_quarter DESC;
```

### Sectoral Employment Analysis

```sql
SELECT 
  ic.beforeit_sector_name,
  se.date_year,
  se.date_quarter,
  se.total_employment,
  se.average_hourly_earnings
FROM `us_beforeit_data.sectoral_employment` se
JOIN `us_beforeit_data.industry_classification` ic
  ON se.beforeit_sector_id = ic.beforeit_sector_id
WHERE se.frequency = 'QUARTERLY'
  AND se.date_year = 2019
ORDER BY se.total_employment DESC;
```

### Financial Accounts Summary

```sql
SELECT 
  date_year,
  date_quarter,
  total_assets as household_assets,
  total_liabilities as household_liabilities,
  net_worth as household_net_worth
FROM `us_beforeit_data.household_financial_accounts`
WHERE date_year >= 2010
ORDER BY date_year DESC, date_quarter DESC;
```

## Data Loading

After creating the database schema, you'll need to populate the tables with actual data. The recommended approach is:

1. **Set up data source connections** to government APIs and databases
2. **Create ETL pipelines** to extract, transform, and load data
3. **Implement data validation** to ensure quality and consistency
4. **Schedule regular updates** to maintain current data
5. **Monitor data quality** using the built-in quality checks

## Performance Optimization

The database schema includes several performance optimizations:

- **Partitioning**: Tables partitioned by year for efficient time-based queries
- **Clustering**: Strategic clustering on key dimensions
- **Indexing**: Indexes on frequently queried columns
- **Views**: Pre-built views for common query patterns
- **Materialized Views**: For complex aggregations (to be implemented)

## Data Governance

The database includes features for data governance:

- **Data Lineage**: Tracking data sources and transformations
- **Quality Checks**: Built-in validation rules and quality metrics
- **Access Control**: Permission management for different user roles
- **Audit Trail**: Logging of data changes and access
- **Documentation**: Comprehensive metadata and documentation

## Support and Maintenance

### Data Quality Monitoring

Regular checks should be performed:

```sql
-- Run data quality checks
SELECT 
  check_id,
  table_name,
  check_description,
  last_run_status,
  last_run_result
FROM `us_beforeit_data.data_quality_checks`
WHERE last_run_status = 'FAILED'
ORDER BY last_run_timestamp DESC;
```

### Database Statistics

Monitor database usage:

```sql
-- Check table sizes and row counts
SELECT 
  table_name,
  row_count,
  size_bytes / 1024 / 1024 / 1024 as size_gb
FROM `us_beforeit_data.INFORMATION_SCHEMA.TABLES`
WHERE table_schema = 'us_beforeit_data'
ORDER BY size_bytes DESC;
```

## Contributing

When adding new tables or modifying the schema:

1. Update the relevant SQL files
2. Add appropriate documentation
3. Include data quality checks
4. Test with sample data
5. Update this README

## License

This database schema is part of the US BeforeIT.jl project and follows the same licensing terms as the main project.

## Contact

For questions about the database schema or issues with implementation, please refer to the main US BeforeIT.jl project documentation and issue tracking system.