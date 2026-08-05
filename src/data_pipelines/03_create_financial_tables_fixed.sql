-- =============================================================================
-- US BeforeIT.jl - Financial and Government Data Tables (BigQuery Compatible)
-- =============================================================================

-- Household Financial Accounts
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.household_financial_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 NOT NULL,
  date_matlab_num FLOAT64,
  
  -- Assets - Billions USD
  total_assets FLOAT64,
  
  -- Liquid assets
  cash_and_deposits FLOAT64,
  time_savings_deposits FLOAT64,
  money_market_funds FLOAT64,
  
  -- Securities
  corporate_equities FLOAT64,
  mutual_fund_shares FLOAT64,
  treasury_securities FLOAT64,
  agency_securities FLOAT64,
  municipal_securities FLOAT64,
  corporate_bonds FLOAT64,
  
  -- Pension and insurance
  pension_entitlements FLOAT64,
  life_insurance_reserves FLOAT64,
  
  -- Real estate
  real_estate_value FLOAT64,
  owners_equity_real_estate FLOAT64,
  
  -- Liabilities
  total_liabilities FLOAT64,
  home_mortgages FLOAT64,
  consumer_credit FLOAT64,
  other_loans FLOAT64,
  
  -- Net worth
  net_worth FLOAT64,
  
  -- Flow measures (changes from previous quarter)
  net_acquisition_assets FLOAT64,
  net_incurrence_liabilities FLOAT64,
  net_lending FLOAT64,
  
  -- Ratios and derived measures
  debt_to_income_ratio FLOAT64,
  financial_obligations_ratio FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY date_quarter
OPTIONS (
  description = "US Household Financial Accounts from Federal Reserve Z.1 Financial Accounts"
);

-- Corporate Financial Accounts
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.corporate_financial_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 NOT NULL,
  date_matlab_num FLOAT64,
  
  -- Assets - Billions USD
  total_assets FLOAT64,
  
  -- Liquid assets
  cash_and_deposits FLOAT64,
  time_deposits FLOAT64,
  money_market_funds FLOAT64,
  
  -- Securities
  treasury_securities FLOAT64,
  agency_securities FLOAT64,
  municipal_securities FLOAT64,
  corporate_bonds FLOAT64,
  corporate_equities FLOAT64,
  
  -- Trade receivables and other
  trade_receivables FLOAT64,
  other_accounts_receivable FLOAT64,
  
  -- Liabilities
  total_liabilities FLOAT64,
  
  -- Debt securities
  corporate_bonds_issued FLOAT64,
  commercial_paper FLOAT64,
  
  -- Loans
  bank_loans FLOAT64,
  other_loans FLOAT64,
  
  -- Trade payables
  trade_payables FLOAT64,
  other_accounts_payable FLOAT64,
  
  -- Equity
  corporate_equity_outstanding FLOAT64,
  
  -- Net worth
  net_worth FLOAT64,
  
  -- Flow measures
  net_acquisition_assets FLOAT64,
  net_incurrence_liabilities FLOAT64,
  net_lending FLOAT64,
  
  -- Corporate finance measures
  debt_to_equity_ratio FLOAT64,
  cash_to_assets_ratio FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY date_quarter
OPTIONS (
  description = "US Corporate Financial Accounts from Federal Reserve Z.1 Financial Accounts"
);

-- Banking Sector Financial Accounts
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.banking_sector_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 NOT NULL,
  date_matlab_num FLOAT64,
  
  -- Assets - Billions USD
  total_assets FLOAT64,
  
  -- Cash and reserves
  cash_and_reserves FLOAT64,
  required_reserves FLOAT64,
  excess_reserves FLOAT64,
  
  -- Securities
  treasury_securities FLOAT64,
  agency_securities FLOAT64,
  municipal_securities FLOAT64,
  other_securities FLOAT64,
  
  -- Loans
  total_loans FLOAT64,
  commercial_industrial_loans FLOAT64,
  real_estate_loans FLOAT64,
  consumer_loans FLOAT64,
  other_loans FLOAT64,
  
  -- Liabilities
  total_liabilities FLOAT64,
  
  -- Deposits
  total_deposits FLOAT64,
  checkable_deposits FLOAT64,
  time_savings_deposits FLOAT64,
  large_time_deposits FLOAT64,
  
  -- Other funding
  fed_funds_repo FLOAT64,
  other_borrowed_money FLOAT64,
  
  -- Equity
  bank_equity FLOAT64,
  
  -- Credit quality measures
  loan_loss_allowances FLOAT64,
  nonperforming_loans FLOAT64,
  net_charge_offs FLOAT64,
  
  -- Regulatory capital ratios
  tier1_capital_ratio FLOAT64,
  total_capital_ratio FLOAT64,
  leverage_ratio FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY date_quarter
OPTIONS (
  description = "US Banking Sector Financial Accounts from Federal Reserve H.8 and Z.1"
);

-- Government Financial Accounts
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.government_financial_accounts` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64 NOT NULL,
  date_matlab_num FLOAT64,
  
  -- Government level
  government_level STRING NOT NULL,
  
  -- Assets - Billions USD
  total_assets FLOAT64,
  
  -- Cash and securities
  cash_and_deposits FLOAT64,
  treasury_securities FLOAT64,
  agency_securities FLOAT64,
  municipal_securities FLOAT64,
  corporate_equities FLOAT64,
  
  -- Pension assets
  pension_fund_assets FLOAT64,
  
  -- Liabilities
  total_liabilities FLOAT64,
  
  -- Debt securities
  treasury_debt FLOAT64,
  agency_debt FLOAT64,
  municipal_debt FLOAT64,
  
  -- Loans
  loans_payable FLOAT64,
  
  -- Other liabilities
  trade_payables FLOAT64,
  
  -- Net worth
  net_worth FLOAT64,
  
  -- Flow measures
  net_acquisition_assets FLOAT64,
  net_incurrence_liabilities FLOAT64,
  net_lending FLOAT64,
  
  -- Debt ratios
  debt_to_gdp_ratio FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY government_level, date_quarter
OPTIONS (
  description = "US Government Financial Accounts from Federal Reserve Z.1 Financial Accounts"
);

-- Government Fiscal Operations
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.government_fiscal_operations` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_month INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Government level
  government_level STRING NOT NULL,
  
  -- Revenues - Billions USD
  total_revenue FLOAT64,
  
  -- Tax revenues
  individual_income_taxes FLOAT64,
  corporate_income_taxes FLOAT64,
  payroll_taxes FLOAT64,
  excise_taxes FLOAT64,
  customs_duties FLOAT64,
  estate_gift_taxes FLOAT64,
  other_taxes FLOAT64,
  
  -- Non-tax revenues
  social_insurance_contributions FLOAT64,
  other_receipts FLOAT64,
  
  -- Expenditures
  total_expenditures FLOAT64,
  
  -- Mandatory spending
  social_security FLOAT64,
  medicare FLOAT64,
  medicaid FLOAT64,
  unemployment_insurance FLOAT64,
  other_social_benefits FLOAT64,
  
  -- Discretionary spending
  defense_spending FLOAT64,
  nondefense_discretionary FLOAT64,
  
  -- Other spending
  interest_payments FLOAT64,
  grants_to_state_local FLOAT64,
  other_expenditures FLOAT64,
  
  -- Fiscal balance
  budget_balance FLOAT64,
  primary_balance FLOAT64,
  
  -- Ratios to GDP
  revenue_to_gdp FLOAT64,
  expenditure_to_gdp FLOAT64,
  deficit_to_gdp FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY government_level, frequency, date_quarter
OPTIONS (
  description = "US Government Fiscal Operations from Treasury and BEA"
);

-- Tax Rates and Tax Policy
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.tax_rates_policy` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_matlab_num FLOAT64,
  
  -- Tax type and scope
  tax_type STRING NOT NULL,
  tax_scope STRING NOT NULL,
  
  -- Statutory rates - Percent
  statutory_rate FLOAT64,
  top_marginal_rate FLOAT64,
  
  -- Effective rates - Percent
  average_effective_rate FLOAT64,
  marginal_effective_rate FLOAT64,
  
  -- Tax base and revenue
  tax_base FLOAT64,
  tax_revenue FLOAT64,
  
  -- Income tax specifics
  standard_deduction FLOAT64,
  personal_exemption FLOAT64,
  
  -- Corporate tax specifics
  corporate_rate FLOAT64,
  depreciation_allowance FLOAT64,
  
  -- Payroll tax specifics
  social_security_rate FLOAT64,
  medicare_rate FLOAT64,
  unemployment_rate FLOAT64,
  
  -- Tax incidence measures
  elasticity_taxable_income FLOAT64,
  tax_multiplier FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY tax_type, tax_scope, date_quarter
OPTIONS (
  description = "US Tax Rates and Policy parameters from IRS, CBO, and academic sources"
);

-- Central Bank Operations
CREATE OR REPLACE TABLE `marketsreplica.us_beforeit_data.central_bank_operations` (
  -- Time identifiers
  date_year INT64 NOT NULL,
  date_quarter INT64,
  date_month INT64,
  date_week INT64,
  date_matlab_num FLOAT64,
  frequency STRING NOT NULL,
  
  -- Federal Reserve Balance Sheet - Billions USD
  total_assets FLOAT64,
  
  -- Assets
  treasury_securities_held FLOAT64,
  agency_mbs_held FLOAT64,
  other_securities FLOAT64,
  
  -- Lending facilities
  discount_window_loans FLOAT64,
  term_auction_credit FLOAT64,
  other_credit_extensions FLOAT64,
  
  -- Liabilities
  currency_in_circulation FLOAT64,
  bank_reserves FLOAT64,
  reverse_repo_operations FLOAT64,
  treasury_general_account FLOAT64,
  
  -- Monetary policy indicators
  federal_funds_target FLOAT64,
  federal_funds_target_lower FLOAT64,
  federal_funds_target_upper FLOAT64,
  
  -- Quantitative easing measures
  qe_program_purchases FLOAT64,
  qe_program_active BOOLEAN,
  
  -- Forward guidance indicators
  forward_guidance_horizon FLOAT64,
  policy_uncertainty_index FLOAT64,
  
  -- Metadata
  data_source STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY frequency, date_quarter, date_month
OPTIONS (
  description = "US Federal Reserve Operations and Balance Sheet from Federal Reserve H.4.1"
);