-- =============================================================================
-- US BeforeIT.jl - Financial and Government Data Tables
-- =============================================================================
-- This script creates the financial and government tables for the US BeforeIT.jl
-- economic modeling framework. These tables store balance sheet data, government
-- finance, and financial flow accounts data.
-- =============================================================================

-- =============================================================================
-- Household Financial Accounts
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.household_financial_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 NOT NULL COMMENT "Quarter (1-4)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  
  -- Assets - Billions USD
  total_assets FLOAT64 COMMENT "Total financial assets",
  
  -- Liquid assets
  cash_and_deposits FLOAT64 COMMENT "Cash and checkable deposits",
  time_savings_deposits FLOAT64 COMMENT "Time and savings deposits",
  money_market_funds FLOAT64 COMMENT "Money market fund shares",
  
  -- Securities
  corporate_equities FLOAT64 COMMENT "Corporate equities",
  mutual_fund_shares FLOAT64 COMMENT "Mutual fund shares",
  treasury_securities FLOAT64 COMMENT "U.S. Treasury securities",
  agency_securities FLOAT64 COMMENT "U.S. government agency securities",
  municipal_securities FLOAT64 COMMENT "Municipal securities",
  corporate_bonds FLOAT64 COMMENT "Corporate and foreign bonds",
  
  -- Pension and insurance
  pension_entitlements FLOAT64 COMMENT "Pension entitlements",
  life_insurance_reserves FLOAT64 COMMENT "Life insurance reserves",
  
  -- Real estate
  real_estate_value FLOAT64 COMMENT "Real estate at market value",
  owners_equity_real_estate FLOAT64 COMMENT "Owners' equity in real estate",
  
  -- Liabilities
  total_liabilities FLOAT64 COMMENT "Total liabilities",
  home_mortgages FLOAT64 COMMENT "Home mortgages",
  consumer_credit FLOAT64 COMMENT "Consumer credit",
  other_loans FLOAT64 COMMENT "Other loans and advances",
  
  -- Net worth
  net_worth FLOAT64 COMMENT "Net worth (assets minus liabilities)",
  
  -- Flow measures (changes from previous quarter)
  net_acquisition_assets FLOAT64 COMMENT "Net acquisition of financial assets",
  net_incurrence_liabilities FLOAT64 COMMENT "Net incurrence of liabilities",
  net_lending FLOAT64 COMMENT "Net lending (+) or borrowing (-)",
  
  -- Ratios and derived measures
  debt_to_income_ratio FLOAT64 COMMENT "Debt service ratio (percent of disposable income)",
  financial_obligations_ratio FLOAT64 COMMENT "Financial obligations ratio (percent)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., FED_Z1_B101H)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_household_financial_accounts PRIMARY KEY (date_year, date_quarter) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY date_quarter
OPTIONS (
  description = "US Household Financial Accounts from Federal Reserve Z.1 Financial Accounts",
  labels = [("data_type", "household_finance"), ("frequency", "quarterly"), ("source", "federal_reserve")]
);

-- =============================================================================
-- Corporate Financial Accounts
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.corporate_financial_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 NOT NULL COMMENT "Quarter (1-4)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  
  -- Assets - Billions USD
  total_assets FLOAT64 COMMENT "Total financial assets",
  
  -- Liquid assets
  cash_and_deposits FLOAT64 COMMENT "Cash and checkable deposits",
  time_deposits FLOAT64 COMMENT "Time and savings deposits",
  money_market_funds FLOAT64 COMMENT "Money market fund shares",
  
  -- Securities
  treasury_securities FLOAT64 COMMENT "U.S. Treasury securities",
  agency_securities FLOAT64 COMMENT "U.S. government agency securities",
  municipal_securities FLOAT64 COMMENT "Municipal securities",
  corporate_bonds FLOAT64 COMMENT "Corporate and foreign bonds",
  corporate_equities FLOAT64 COMMENT "Corporate equities",
  
  -- Trade receivables and other
  trade_receivables FLOAT64 COMMENT "Trade receivables",
  other_accounts_receivable FLOAT64 COMMENT "Other accounts receivable",
  
  -- Liabilities
  total_liabilities FLOAT64 COMMENT "Total liabilities",
  
  -- Debt securities
  corporate_bonds_issued FLOAT64 COMMENT "Corporate bonds issued",
  commercial_paper FLOAT64 COMMENT "Commercial paper",
  
  -- Loans
  bank_loans FLOAT64 COMMENT "Bank loans n.e.c.",
  other_loans FLOAT64 COMMENT "Other loans and advances",
  
  -- Trade payables
  trade_payables FLOAT64 COMMENT "Trade payables",
  other_accounts_payable FLOAT64 COMMENT "Other accounts payable",
  
  -- Equity
  corporate_equity_outstanding FLOAT64 COMMENT "Corporate equity outstanding",
  
  -- Net worth
  net_worth FLOAT64 COMMENT "Net worth (assets minus liabilities)",
  
  -- Flow measures
  net_acquisition_assets FLOAT64 COMMENT "Net acquisition of financial assets",
  net_incurrence_liabilities FLOAT64 COMMENT "Net incurrence of liabilities",
  net_lending FLOAT64 COMMENT "Net lending (+) or borrowing (-)",
  
  -- Corporate finance measures
  debt_to_equity_ratio FLOAT64 COMMENT "Debt to equity ratio",
  cash_to_assets_ratio FLOAT64 COMMENT "Cash to total assets ratio",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., FED_Z1_B103)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_corporate_financial_accounts PRIMARY KEY (date_year, date_quarter) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY date_quarter
OPTIONS (
  description = "US Corporate Financial Accounts from Federal Reserve Z.1 Financial Accounts",
  labels = [("data_type", "corporate_finance"), ("frequency", "quarterly"), ("source", "federal_reserve")]
);

-- =============================================================================
-- Banking Sector Financial Accounts
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.banking_sector_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 NOT NULL COMMENT "Quarter (1-4)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  
  -- Assets - Billions USD
  total_assets FLOAT64 COMMENT "Total bank assets",
  
  -- Cash and reserves
  cash_and_reserves FLOAT64 COMMENT "Cash and reserves",
  required_reserves FLOAT64 COMMENT "Required reserves",
  excess_reserves FLOAT64 COMMENT "Excess reserves",
  
  -- Securities
  treasury_securities FLOAT64 COMMENT "U.S. Treasury securities",
  agency_securities FLOAT64 COMMENT "U.S. government agency securities",
  municipal_securities FLOAT64 COMMENT "Municipal securities",
  other_securities FLOAT64 COMMENT "Other securities",
  
  -- Loans
  total_loans FLOAT64 COMMENT "Total loans",
  commercial_industrial_loans FLOAT64 COMMENT "Commercial and industrial loans",
  real_estate_loans FLOAT64 COMMENT "Real estate loans",
  consumer_loans FLOAT64 COMMENT "Consumer loans",
  other_loans FLOAT64 COMMENT "Other loans",
  
  -- Liabilities
  total_liabilities FLOAT64 COMMENT "Total liabilities",
  
  -- Deposits
  total_deposits FLOAT64 COMMENT "Total deposits",
  checkable_deposits FLOAT64 COMMENT "Checkable deposits",
  time_savings_deposits FLOAT64 COMMENT "Time and savings deposits",
  large_time_deposits FLOAT64 COMMENT "Large time deposits",
  
  -- Other funding
  fed_funds_repo FLOAT64 COMMENT "Federal funds and repurchase agreements",
  other_borrowed_money FLOAT64 COMMENT "Other borrowed money",
  
  -- Equity
  bank_equity FLOAT64 COMMENT "Bank equity capital",
  
  -- Credit quality measures
  loan_loss_allowances FLOAT64 COMMENT "Allowances for loan losses",
  nonperforming_loans FLOAT64 COMMENT "Nonperforming loans",
  net_charge_offs FLOAT64 COMMENT "Net charge-offs",
  
  -- Regulatory capital ratios
  tier1_capital_ratio FLOAT64 COMMENT "Tier 1 capital ratio (percent)",
  total_capital_ratio FLOAT64 COMMENT "Total capital ratio (percent)",
  leverage_ratio FLOAT64 COMMENT "Leverage ratio (percent)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., FED_H8, FED_Z1_B109)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_banking_sector_accounts PRIMARY KEY (date_year, date_quarter) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY date_quarter
OPTIONS (
  description = "US Banking Sector Financial Accounts from Federal Reserve H.8 and Z.1",
  labels = [("data_type", "banking_sector"), ("frequency", "quarterly"), ("source", "federal_reserve")]
);

-- =============================================================================
-- Government Financial Accounts
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.government_financial_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 NOT NULL COMMENT "Quarter (1-4)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  
  -- Government level
  government_level STRING NOT NULL COMMENT "Government level: FEDERAL, STATE_LOCAL, or TOTAL",
  
  -- Assets - Billions USD
  total_assets FLOAT64 COMMENT "Total financial assets",
  
  -- Cash and securities
  cash_and_deposits FLOAT64 COMMENT "Cash and checkable deposits",
  treasury_securities FLOAT64 COMMENT "U.S. Treasury securities",
  agency_securities FLOAT64 COMMENT "U.S. government agency securities",
  municipal_securities FLOAT64 COMMENT "Municipal securities",
  corporate_equities FLOAT64 COMMENT "Corporate equities",
  
  -- Pension assets
  pension_fund_assets FLOAT64 COMMENT "Government pension fund assets",
  
  -- Liabilities
  total_liabilities FLOAT64 COMMENT "Total liabilities",
  
  -- Debt securities
  treasury_debt FLOAT64 COMMENT "U.S. Treasury debt securities",
  agency_debt FLOAT64 COMMENT "U.S. government agency debt securities",
  municipal_debt FLOAT64 COMMENT "Municipal securities",
  
  -- Loans
  loans_payable FLOAT64 COMMENT "Loans payable",
  
  -- Other liabilities
  trade_payables FLOAT64 COMMENT "Trade payables",
  
  -- Net worth
  net_worth FLOAT64 COMMENT "Net worth (assets minus liabilities)",
  
  -- Flow measures
  net_acquisition_assets FLOAT64 COMMENT "Net acquisition of financial assets",
  net_incurrence_liabilities FLOAT64 COMMENT "Net incurrence of liabilities",
  net_lending FLOAT64 COMMENT "Net lending (+) or borrowing (-)",
  
  -- Debt ratios
  debt_to_gdp_ratio FLOAT64 COMMENT "Debt to GDP ratio (percent)",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., FED_Z1_F106, FED_Z1_F107)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_government_financial_accounts PRIMARY KEY (date_year, date_quarter, government_level) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY government_level, date_quarter
OPTIONS (
  description = "US Government Financial Accounts from Federal Reserve Z.1 Financial Accounts",
  labels = [("data_type", "government_finance"), ("frequency", "quarterly"), ("source", "federal_reserve")]
);

-- =============================================================================
-- Government Fiscal Operations
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.government_fiscal_operations` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_month INT64 COMMENT "Month (1-12, for monthly data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL, QUARTERLY, or MONTHLY",
  
  -- Government level
  government_level STRING NOT NULL COMMENT "Government level: FEDERAL, STATE_LOCAL, or TOTAL",
  
  -- Revenues - Billions USD
  total_revenue FLOAT64 COMMENT "Total government revenue",
  
  -- Tax revenues
  individual_income_taxes FLOAT64 COMMENT "Individual income taxes",
  corporate_income_taxes FLOAT64 COMMENT "Corporate income taxes",
  payroll_taxes FLOAT64 COMMENT "Payroll taxes",
  excise_taxes FLOAT64 COMMENT "Excise taxes",
  customs_duties FLOAT64 COMMENT "Customs duties",
  estate_gift_taxes FLOAT64 COMMENT "Estate and gift taxes",
  other_taxes FLOAT64 COMMENT "Other taxes",
  
  -- Non-tax revenues
  social_insurance_contributions FLOAT64 COMMENT "Social insurance contributions",
  other_receipts FLOAT64 COMMENT "Other receipts",
  
  -- Expenditures
  total_expenditures FLOAT64 COMMENT "Total government expenditures",
  
  -- Mandatory spending
  social_security FLOAT64 COMMENT "Social Security benefits",
  medicare FLOAT64 COMMENT "Medicare benefits",
  medicaid FLOAT64 COMMENT "Medicaid benefits",
  unemployment_insurance FLOAT64 COMMENT "Unemployment insurance benefits",
  other_social_benefits FLOAT64 COMMENT "Other social benefits",
  
  -- Discretionary spending
  defense_spending FLOAT64 COMMENT "Defense spending",
  nondefense_discretionary FLOAT64 COMMENT "Nondefense discretionary spending",
  
  -- Other spending
  interest_payments FLOAT64 COMMENT "Interest payments on debt",
  grants_to_state_local FLOAT64 COMMENT "Grants to state and local governments",
  other_expenditures FLOAT64 COMMENT "Other expenditures",
  
  -- Fiscal balance
  budget_balance FLOAT64 COMMENT "Budget balance (surplus/deficit)",
  primary_balance FLOAT64 COMMENT "Primary balance (excluding interest)",
  
  -- Ratios to GDP
  revenue_to_gdp FLOAT64 COMMENT "Total revenue as percent of GDP",
  expenditure_to_gdp FLOAT64 COMMENT "Total expenditure as percent of GDP",
  deficit_to_gdp FLOAT64 COMMENT "Budget deficit as percent of GDP",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., TREASURY_MTS, BEA_NIPA_T3)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_government_fiscal_operations PRIMARY KEY (date_year, date_quarter, date_month, frequency, government_level) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY government_level, frequency, date_quarter
OPTIONS (
  description = "US Government Fiscal Operations from Treasury and BEA",
  labels = [("data_type", "fiscal_operations"), ("frequency", "mixed"), ("source", "treasury_bea")]
);

-- =============================================================================
-- Tax Rates and Tax Policy
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.tax_rates_policy` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  
  -- Tax type and scope
  tax_type STRING NOT NULL COMMENT "Tax type: INCOME, CORPORATE, PAYROLL, etc.",
  tax_scope STRING NOT NULL COMMENT "Tax scope: FEDERAL, STATE, LOCAL, or TOTAL",
  
  -- Statutory rates - Percent
  statutory_rate FLOAT64 COMMENT "Statutory tax rate (percent)",
  top_marginal_rate FLOAT64 COMMENT "Top marginal tax rate (percent)",
  
  -- Effective rates - Percent
  average_effective_rate FLOAT64 COMMENT "Average effective tax rate (percent)",
  marginal_effective_rate FLOAT64 COMMENT "Marginal effective tax rate (percent)",
  
  -- Tax base and revenue
  tax_base FLOAT64 COMMENT "Tax base (billions USD)",
  tax_revenue FLOAT64 COMMENT "Tax revenue (billions USD)",
  
  -- Income tax specifics
  standard_deduction FLOAT64 COMMENT "Standard deduction (dollars)",
  personal_exemption FLOAT64 COMMENT "Personal exemption (dollars)",
  
  -- Corporate tax specifics
  corporate_rate FLOAT64 COMMENT "Corporate income tax rate (percent)",
  depreciation_allowance FLOAT64 COMMENT "Depreciation allowance rate (percent)",
  
  -- Payroll tax specifics
  social_security_rate FLOAT64 COMMENT "Social Security tax rate (percent)",
  medicare_rate FLOAT64 COMMENT "Medicare tax rate (percent)",
  unemployment_rate FLOAT64 COMMENT "Unemployment insurance tax rate (percent)",
  
  -- Tax incidence measures
  elasticity_taxable_income FLOAT64 COMMENT "Elasticity of taxable income",
  tax_multiplier FLOAT64 COMMENT "Tax multiplier effect",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., IRS_SOI, CBO_TAX_RATES)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_tax_rates_policy PRIMARY KEY (date_year, date_quarter, tax_type, tax_scope) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY tax_type, tax_scope, date_quarter
OPTIONS (
  description = "US Tax Rates and Policy parameters from IRS, CBO, and academic sources",
  labels = [("data_type", "tax_policy"), ("frequency", "mixed"), ("source", "irs_cbo")]
);

-- =============================================================================
-- Central Bank Operations
-- =============================================================================
CREATE OR REPLACE TABLE `us_beforeit_data.central_bank_operations` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 COMMENT "Quarter (1-4, NULL for annual data)",
  date_month INT64 COMMENT "Month (1-12, for monthly data)",
  date_week INT64 COMMENT "Week (1-53, for weekly data)",
  date_matlab_num FLOAT64 COMMENT "MATLAB datenum for compatibility",
  frequency STRING NOT NULL COMMENT "Data frequency: ANNUAL, QUARTERLY, MONTHLY, or WEEKLY",
  
  -- Federal Reserve Balance Sheet - Billions USD
  total_assets FLOAT64 COMMENT "Total Federal Reserve assets",
  
  -- Assets
  treasury_securities_held FLOAT64 COMMENT "U.S. Treasury securities held outright",
  agency_mbs_held FLOAT64 COMMENT "Federal agency MBS held outright",
  other_securities FLOAT64 COMMENT "Other securities held outright",
  
  -- Lending facilities
  discount_window_loans FLOAT64 COMMENT "Primary credit (discount window)",
  term_auction_credit FLOAT64 COMMENT "Term auction credit",
  other_credit_extensions FLOAT64 COMMENT "Other credit extensions",
  
  -- Liabilities
  currency_in_circulation FLOAT64 COMMENT "Currency in circulation",
  bank_reserves FLOAT64 COMMENT "Reserve balances with Federal Reserve Banks",
  reverse_repo_operations FLOAT64 COMMENT "Reverse repurchase agreements",
  treasury_general_account FLOAT64 COMMENT "U.S. Treasury general account",
  
  -- Monetary policy indicators
  federal_funds_target FLOAT64 COMMENT "Federal funds target rate (percent)",
  federal_funds_target_lower FLOAT64 COMMENT "Federal funds target range lower bound (percent)",
  federal_funds_target_upper FLOAT64 COMMENT "Federal funds target range upper bound (percent)",
  
  -- Quantitative easing measures
  qe_program_purchases FLOAT64 COMMENT "Securities purchased under QE programs",
  qe_program_active BOOLEAN COMMENT "Whether QE program is active",
  
  -- Forward guidance indicators
  forward_guidance_horizon FLOAT64 COMMENT "Forward guidance horizon (quarters)",
  policy_uncertainty_index FLOAT64 COMMENT "Monetary policy uncertainty index",
  
  -- Metadata
  data_source STRING COMMENT "Primary data source (e.g., FED_H41, FED_FOMC)",
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  CONSTRAINT pk_central_bank_operations PRIMARY KEY (date_year, date_quarter, date_month, date_week, frequency) NOT ENFORCED
)
PARTITION BY DATE(TIMESTAMP(CONCAT(CAST(date_year AS STRING), '-01-01')))
CLUSTER BY frequency, date_quarter, date_month
OPTIONS (
  description = "US Federal Reserve Operations and Balance Sheet from Federal Reserve H.4.1",
  labels = [("data_type", "central_bank"), ("frequency", "mixed"), ("source", "federal_reserve")]
);

-- =============================================================================
-- Create indexes for better query performance
-- =============================================================================

-- Index for household financial time series
CREATE INDEX IF NOT EXISTS idx_household_financial_time_series 
ON `us_beforeit_data.household_financial_accounts` (date_year, date_quarter);

-- Index for corporate financial time series
CREATE INDEX IF NOT EXISTS idx_corporate_financial_time_series 
ON `us_beforeit_data.corporate_financial_accounts` (date_year, date_quarter);

-- Index for government financial accounts by level
CREATE INDEX IF NOT EXISTS idx_government_financial_level 
ON `us_beforeit_data.government_financial_accounts` (government_level, date_year, date_quarter);

-- Index for fiscal operations by government level
CREATE INDEX IF NOT EXISTS idx_fiscal_operations_level 
ON `us_beforeit_data.government_fiscal_operations` (government_level, frequency, date_year, date_quarter);

-- Index for tax rates by type and scope
CREATE INDEX IF NOT EXISTS idx_tax_rates_type_scope 
ON `us_beforeit_data.tax_rates_policy` (tax_type, tax_scope, date_year, date_quarter);

-- Index for central bank operations time series
CREATE INDEX IF NOT EXISTS idx_central_bank_time_series 
ON `us_beforeit_data.central_bank_operations` (frequency, date_year, date_quarter, date_month);