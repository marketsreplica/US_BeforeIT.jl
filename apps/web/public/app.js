const state = {
  activeTab: "results",
  datasets: [],
  datasetLabels: new Map(),
  knobs: [],
  schema: { parameters: [], initial_conditions: [] },
  inputGroup: "parameters",
  selectedInput: null,
  knobCategory: "All",
  runs: [],
  currentRunId: null,
  isRunning: false,
  datasetMetadata: null,
  sectorMetadata: null,
  scenarioAssumptions: [],
  sectors: [],
  historicalLookback: 54,
  cloneSourceName: null,
  cloneParentRunId: null,
  cloneTrace: {
    profile: "standard",
    realization_indices: [1],
    phase_detail: "none",
    checkpoints: false,
  },
  cloneShock: { type: "none" },
  preservedOverrides: { parameters: {}, initial_conditions: {} },
};

const SCENARIO_LABELS = {
  baseline: "Baseline · OeNB/WIFO",
  upside: "Upside · mild recovery",
  downside: "Downside · adverse conditions",
  unconditional: "Unconditional model",
};

const EDITABLE_META = {
  tau_INC: {
    label: "Income tax",
    category: "Taxes & fiscal",
    description: "Tax rate applied to household income before disposable income and consumption decisions are calculated.",
  },
  tau_FIRM: {
    label: "Corporate tax",
    category: "Taxes & fiscal",
    description: "Tax rate applied to firm profits before retained earnings and dividend distributions.",
  },
  tau_VAT: {
    label: "Value-added tax",
    category: "Taxes & fiscal",
    description: "Consumption tax added to the price households pay for goods and services.",
  },
  tau_SIF: {
    label: "Employer social insurance",
    category: "Taxes & fiscal",
    description: "Employer contribution rate added to the labor cost of each worker.",
  },
  tau_SIW: {
    label: "Employee social insurance",
    category: "Taxes & fiscal",
    description: "Employee contribution rate deducted from gross labor income.",
  },
  tau_EXPORT: {
    label: "Export tax",
    category: "Taxes & fiscal",
    description: "Tax rate applied to exported goods and services in the external-demand block.",
  },
  tau_CF: {
    label: "Capital formation tax",
    category: "Taxes & fiscal",
    description: "Tax rate applied to purchases that form productive fixed capital.",
  },
  tau_G: {
    label: "Government consumption tax",
    category: "Taxes & fiscal",
    description: "Tax rate applied to government purchases of goods and services.",
  },
  psi: {
    label: "Consumption share",
    category: "Households & firms",
    description: "Ratio of household disposable income allocated to current consumption. An official-data baseline may exceed one during household dissaving; manual edits are constrained together with housing investment.",
  },
  psi_H: {
    label: "Housing investment share",
    category: "Households & firms",
    description: "Ratio of household disposable income allocated to housing investment. For manual edits, psi + psi_H must be no greater than one; calibrated dissaving baselines are preserved.",
  },
  theta_UB: {
    label: "Benefit replacement rate",
    category: "Households & firms",
    description: "Share of the reference wage paid to an unemployed household as unemployment benefit.",
  },
  theta_DIV: {
    label: "Dividend payout",
    category: "Households & firms",
    description: "Share of distributable firm earnings paid to owners instead of retained by firms.",
  },
  mu: {
    label: "Bank risk premium",
    category: "Banking & credit",
    description: "Premium banks add above the policy rate when pricing credit to borrowers.",
  },
  zeta: {
    label: "Capital requirement",
    category: "Banking & credit",
    description: "Minimum bank capital coefficient that constrains the amount of credit banks can supply.",
  },
  zeta_LTV: {
    label: "Loan-to-value limit",
    category: "Banking & credit",
    description: "Maximum loan size relative to the value of collateral used in secured lending.",
  },
  zeta_b: {
    label: "New-firm leverage",
    category: "Banking & credit",
    description: "Loan-to-capital ratio used to finance firms that enter after a bankruptcy.",
  },
  theta: {
    label: "Debt installment rate",
    category: "Banking & credit",
    description: "Fraction of outstanding borrower debt repaid as an installment each model period.",
  },
  rho: {
    label: "Policy-rate smoothing",
    category: "Monetary policy",
    description: "Persistence of the central-bank policy rate; higher values make rate changes more gradual.",
  },
  r_star: {
    label: "Neutral real rate",
    category: "Monetary policy",
    description: "Quarterly equilibrium real interest rate used as the neutral anchor in the policy rule.",
  },
  pi_star: {
    label: "Inflation target",
    category: "Monetary policy",
    description: "Quarterly inflation target used by the central bank when setting the policy rate.",
  },
  xi_pi: {
    label: "Inflation response weight",
    category: "Monetary policy",
    description: "Strength of the policy-rate response to inflation moving away from its target.",
  },
  xi_gamma: {
    label: "Growth response weight",
    category: "Monetary policy",
    description: "Strength of the policy-rate response to the model's output or growth condition.",
  },
  r_G: {
    label: "Government bond spread",
    category: "Monetary policy",
    description: "Interest-rate spread used to price government borrowing relative to the policy-rate environment.",
  },
  r_bar: {
    label: "Initial policy rate",
    category: "Initial conditions",
    description: "Annualized policy rate at the start of the simulation; it is converted to a quarterly rate by the backend.",
  },
  sb_other: {
    label: "Other social benefits",
    category: "Initial conditions",
    description: "Initial per-recipient amount of social benefits other than unemployment and inactivity benefits.",
  },
  sb_inact: {
    label: "Inactive-household benefits",
    category: "Initial conditions",
    description: "Initial benefit amount paid to economically inactive households, including pension-like transfers.",
  },
  w_UB: {
    label: "Benefit reference wage",
    category: "Initial conditions",
    description: "Initial wage base used with the replacement rate to calculate unemployment benefits.",
  },
  omega: {
    label: "Capacity utilization",
    category: "Initial conditions",
    description: "Share of installed productive capacity in use when the simulated economy is initialized.",
  },
};

const PARAMETER_DESCRIPTIONS = {
  C: "Covariance matrix linking the estimated innovations in external demand, exports, and imports.",
  G: "Number of product groups represented in production, trade, and final demand.",
  H_act: "Number of economically active household agents in the calibrated population.",
  H_inact: "Number of economically inactive household agents in the calibrated population.",
  I_s: "Number of firm agents assigned to each industry sector.",
  J: "Number of government entities represented by the model.",
  L: "Number of foreign-consumer agents used to represent external demand.",
  S: "Number of industry sectors in the calibrated economy.",
  T: "Number of periods carried in the calibrated dataset.",
  T_max: "Maximum available length of the exogenous calibration series.",
  T_prime: "Historical lookback window used by agents to estimate expectations.",
  a_sg: "Industry-by-product technology coefficients describing production requirements.",
  alpha_s: "Quarterly real output produced per worker agent in each industry.",
  beta_s: "Sector output relative to intermediate-input use; a production-efficiency ratio.",
  kappa_s: "Quarterly real output relative to utilized productive capital in each industry.",
  delta_s: "Sector-specific depreciation rates for productive capital.",
  w_s: "Calibrated wage levels by industry sector.",
  tau_Y_s: "Sector-specific tax rates applied to production or output.",
  tau_K_s: "Sector-specific tax rates applied to productive capital.",
  b_CF_g: "Product allocation coefficients for firms' fixed-capital formation.",
  b_CFH_g: "Product allocation coefficients for household housing investment.",
  b_HH_g: "Household consumption-budget shares by product group.",
  c_G_g: "Baseline government consumption demand by product group.",
  c_E_g: "Baseline export demand by product group.",
  c_I_g: "Baseline import demand by product group.",
  alpha_E: "Persistence coefficient of the estimated log export-demand process.",
  beta_E: "Intercept of the estimated log export-demand process.",
  sigma_E: "Standard deviation of innovations to export demand.",
  alpha_G: "Persistence coefficient of the estimated log government-demand process.",
  beta_G: "Intercept of the estimated log government-demand process.",
  sigma_G: "Standard deviation of innovations to government demand.",
  alpha_I: "Persistence coefficient of the estimated log import-demand process.",
  beta_I: "Intercept of the estimated log import-demand process.",
  sigma_I: "Standard deviation of innovations to import demand.",
  alpha_Y_EA: "Persistence coefficient of the estimated log reference-area real-output process.",
  beta_Y_EA: "Intercept of the estimated log reference-area real-output process.",
  sigma_Y_EA: "Standard deviation of innovations to reference-area real output.",
  alpha_pi_EA: "Persistence coefficient of the estimated quarterly reference-area inflation process.",
  beta_pi_EA: "Intercept of the estimated quarterly reference-area inflation process.",
  sigma_pi_EA: "Standard deviation of innovations to reference-area inflation.",
  use_growth_rate_ar1: "Whether external macroeconomic expectations are estimated from growth rates instead of log levels.",
};

const INITIAL_DESCRIPTIONS = {
  C_E: "Calibrated export-demand path by product group used to initialize foreign consumption.",
  C_G: "Calibrated government-consumption path used as exogenous public demand.",
  D_H: "Initial stock of household deposits and liquid financial assets.",
  D_I: "Initial stock of firm deposits and liquid financial assets.",
  D_RoW: "Initial deposit position of the rest-of-world sector.",
  E_CB: "Initial central-bank equity position that balances the financial-sector balance sheet.",
  E_k: "Initial equity held by commercial banks.",
  K_H: "Initial value of the household housing-capital stock.",
  L_G: "Initial stock of outstanding government debt.",
  L_I: "Initial stock of outstanding firm debt.",
  N_s: "Initial employment count in each industry sector.",
  Y: "Historical domestic real-output series used to initialize expectations.",
  Y_EA: "Reference-area real output at the simulation starting point.",
  Y_EA_series: "Historical reference-area real-output series used to initialize the external expectations process.",
  Y_I: "Initial firm output or sales levels by product group.",
  omega: "Initial utilization rate of installed productive capacity.",
  pi: "Historical domestic inflation series used to initialize expectations.",
  pi_EA: "Reference-area inflation rate at the simulation starting point.",
  pi_EA_series: "Historical quarterly reference-area inflation series used to initialize external expectations.",
  r_bar: "Quarterly policy rate at the simulation starting point.",
  r_bar_series: "Historical quarterly policy-rate series used to initialize monetary-policy expectations.",
  sb_inact: "Initial benefit amount paid to economically inactive households.",
  sb_other: "Initial amount of other social transfers per recipient.",
  w_UB: "Initial reference wage used to calculate unemployment benefits.",
};

const UNITS = {
  fraction: {
    label: "decimal fraction (1 = 100%)",
    short: "fraction",
    type: "fraction",
  },
  quarterlyFraction: {
    label: "quarterly decimal rate (0.01 = 1%)",
    short: "qtr fraction",
    type: "fraction",
  },
  annualFraction: {
    label: "annual decimal rate (0.01 = 1%)",
    short: "annual fraction",
    type: "fraction",
  },
  dimensionless: {
    label: "dimensionless",
    short: "unitless",
    type: "number",
  },
  boolean: {
    label: "on/off flag (no physical unit)",
    short: "boolean",
    type: "boolean",
  },
  logPoints: {
    label: "log points",
    short: "log points",
    type: "number",
  },
  logVariance: {
    label: "squared log points",
    short: "log points²",
    type: "number",
  },
  quarters: {
    label: "quarters",
    short: "quarters",
    type: "number",
  },
  sectorCount: {
    label: "industry and product groups",
    short: "sectors",
    type: "number",
  },
  householdAgents: {
    label: "model household agents (dataset-specific calibration scale)",
    short: "household agents",
    type: "number",
  },
  firmAgents: {
    label: "model firm agents (dataset-specific calibration scale)",
    short: "firm agents",
    type: "number",
  },
  governmentAgents: {
    label: "model government agents",
    short: "gov. agents",
    type: "number",
  },
  foreignAgents: {
    label: "model foreign-consumer agents",
    short: "foreign agents",
    type: "number",
  },
  workerAgents: {
    label: "model worker agents (dataset-specific calibration scale)",
    short: "worker agents",
    type: "number",
  },
  moneyFlow: {
    label: "million currency units per quarter",
    short: "m / quarter",
    type: "moneyMillions",
    moneyKind: "flow",
  },
  moneyStock: {
    label: "million currency units",
    short: "m",
    type: "moneyMillions",
    moneyKind: "stock",
  },
  moneyPersonFlow: {
    label: "thousand currency units per person-agent per quarter",
    short: "k / person / qtr",
    type: "number",
    moneyKind: "personFlow",
  },
  moneyProductivity: {
    label: "thousand currency units of real output per worker-agent per quarter",
    short: "k / worker / qtr",
    type: "number",
    moneyKind: "productivity",
  },
  index: {
    label: "index level (initial period approximately 1.0)",
    short: "index",
    type: "number",
  },
  annualPercent: {
    label: "percent per year",
    short: "% annual",
    type: "percent",
  },
};

const PARAMETER_UNIT_KEYS = {
  C: "logVariance",
  G: "sectorCount",
  H_act: "householdAgents",
  H_inact: "householdAgents",
  I_s: "firmAgents",
  J: "governmentAgents",
  L: "foreignAgents",
  S: "sectorCount",
  T: "quarters",
  T_max: "quarters",
  T_prime: "quarters",
  alpha_s: "moneyProductivity",
  beta_s: "dimensionless",
  kappa_s: "quarterlyFraction",
  delta_s: "quarterlyFraction",
  w_s: "moneyPersonFlow",
  tau_Y_s: "fraction",
  tau_K_s: "fraction",
  a_sg: "fraction",
  b_CF_g: "fraction",
  b_CFH_g: "fraction",
  b_HH_g: "fraction",
  c_G_g: "fraction",
  c_E_g: "fraction",
  c_I_g: "fraction",
  alpha_E: "dimensionless",
  alpha_G: "dimensionless",
  alpha_I: "dimensionless",
  alpha_Y_EA: "dimensionless",
  alpha_pi_EA: "dimensionless",
  beta_E: "logPoints",
  beta_G: "logPoints",
  beta_I: "logPoints",
  beta_Y_EA: "logPoints",
  beta_pi_EA: "quarterlyFraction",
  sigma_E: "logPoints",
  sigma_G: "logPoints",
  sigma_I: "logPoints",
  sigma_Y_EA: "logPoints",
  sigma_pi_EA: "quarterlyFraction",
  use_growth_rate_ar1: "boolean",
  tau_INC: "fraction",
  tau_FIRM: "fraction",
  tau_VAT: "fraction",
  tau_SIF: "fraction",
  tau_SIW: "fraction",
  tau_EXPORT: "fraction",
  tau_CF: "fraction",
  tau_G: "fraction",
  theta_UB: "fraction",
  psi: "fraction",
  psi_H: "fraction",
  theta_DIV: "fraction",
  theta: "fraction",
  mu: "quarterlyFraction",
  r_G: "quarterlyFraction",
  zeta: "fraction",
  zeta_LTV: "fraction",
  zeta_b: "fraction",
  rho: "dimensionless",
  r_star: "quarterlyFraction",
  xi_pi: "dimensionless",
  xi_gamma: "dimensionless",
  pi_star: "quarterlyFraction",
};

const INITIAL_UNIT_KEYS = {
  C_E: "moneyFlow",
  C_G: "moneyFlow",
  D_H: "moneyStock",
  D_I: "moneyStock",
  D_RoW: "moneyStock",
  E_CB: "moneyStock",
  E_k: "moneyStock",
  K_H: "moneyStock",
  L_G: "moneyStock",
  L_I: "moneyStock",
  N_s: "workerAgents",
  Y: "moneyFlow",
  Y_EA: "moneyFlow",
  Y_EA_series: "moneyFlow",
  Y_I: "moneyFlow",
  omega: "fraction",
  pi: "quarterlyFraction",
  pi_EA: "quarterlyFraction",
  pi_EA_series: "quarterlyFraction",
  r_bar: "quarterlyFraction",
  r_bar_series: "quarterlyFraction",
  sb_inact: "moneyPersonFlow",
  sb_other: "moneyPersonFlow",
  w_UB: "moneyPersonFlow",
};

const CHARTS = [
  ["real_gdp", "Real GDP", "Aggregate inflation-adjusted production", "moneyFlow"],
  ["real_household_consumption", "Household consumption", "Inflation-adjusted household demand", "moneyFlow"],
  ["real_government_consumption", "Government consumption", "Inflation-adjusted public demand", "moneyFlow"],
  ["real_fixed_capitalformation", "Fixed capital formation", "Inflation-adjusted investment", "moneyFlow"],
  ["real_exports", "Exports", "Inflation-adjusted foreign sales", "moneyFlow"],
  ["real_imports", "Imports", "Inflation-adjusted foreign purchases", "moneyFlow"],
  ["wages", "Wages", "Aggregate wage payments", "moneyFlow"],
  ["gdp_deflator", "GDP deflator", "Nominal output divided by real output", "index"],
  ["euribor_annual", "Policy rate", "Annualized quarterly policy rate", "annualPercent"],
];

const PLOT_CONFIG = {
  responsive: true,
  displaylogo: false,
  modeBarButtonsToRemove: ["lasso2d", "select2d", "autoScale2d"],
  scrollZoom: false,
};

async function apiGet(path) {
  const response = await fetch(path, { headers: { Accept: "application/json" } });
  if (!response.ok) {
    throw new Error(`GET ${path} failed: ${response.status} ${await response.text()}`);
  }
  return response.json();
}

async function apiPost(path, body) {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || `POST ${path} failed: ${response.status}`);
  }
  return data;
}

function el(id) {
  return document.getElementById(id);
}

function formatShape(shape) {
  return Array.isArray(shape) ? shape.join(" × ") : "";
}

function formatEditableValue(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return String(value);
  if (Number.isInteger(number)) return String(number);
  return String(Number(number.toPrecision(8)));
}

function formatMetric(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "—";
  return new Intl.NumberFormat("en", {
    notation: Math.abs(number) >= 10000 ? "compact" : "standard",
    maximumFractionDigits: Math.abs(number) < 10 ? 2 : 1,
  }).format(number);
}

function formatPercent(value) {
  const number = Number(value);
  return Number.isFinite(number) ? `${(number * 100).toFixed(2)}%` : "—";
}

function monetaryPresentation(metadata = state.datasetMetadata) {
  const currency = String(
    metadata?.currency
      || metadata?.currency_code
      || (metadata?.country === "US" ? "USD" : "EUR"),
  ).toUpperCase();
  const conventionalSymbols = {
    EUR: "€",
    USD: "$",
    GBP: "£",
    JPY: "¥",
    CHF: "CHF ",
  };
  const symbol = String(
    metadata?.currency_symbol
      || conventionalSymbols[currency]
      || `${currency} `,
  );
  return {
    currency,
    symbol,
    flowUnits: String(metadata?.flow_units || `million_${currency.toLowerCase()}_per_quarter`),
    stockUnits: String(metadata?.stock_units || `million_${currency.toLowerCase()}`),
  };
}

function localizedUnit(unitKey, metadata = state.datasetMetadata) {
  const base = UNITS[unitKey] || UNITS.dimensionless;
  if (unitKey === "sectorCount") {
    return {
      ...base,
      label: `${classificationLabel()} industries/products`,
    };
  }
  if (!base.moneyKind) return base;
  const { symbol } = monetaryPresentation(metadata);
  if (base.moneyKind === "flow") {
    return {
      ...base,
      label: `${symbol} million per quarter`,
      short: `${symbol}m / quarter`,
    };
  }
  if (base.moneyKind === "stock") {
    return {
      ...base,
      label: `${symbol} million`,
      short: `${symbol}m`,
    };
  }
  if (base.moneyKind === "personFlow") {
    return {
      ...base,
      label: `${symbol} thousand per person-agent per quarter`,
      short: `${symbol}k / person / qtr`,
    };
  }
  return {
    ...base,
    label: `${symbol} thousand of real output per worker-agent per quarter`,
    short: `${symbol}k / worker / qtr`,
  };
}

function formatMoneyMillions(value, metadata = state.datasetMetadata) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "—";
  const absolute = Math.abs(number);
  const { symbol } = monetaryPresentation(metadata);
  if (absolute >= 1000) {
    return `${number < 0 ? "−" : ""}${symbol}${(absolute / 1000).toLocaleString("en", { maximumFractionDigits: 2 })}bn`;
  }
  return `${number < 0 ? "−" : ""}${symbol}${absolute.toLocaleString("en", { maximumFractionDigits: 1 })}m`;
}

function inputUnit(group, key) {
  const unitKey = group === "initial_conditions"
    ? INITIAL_UNIT_KEYS[key]
    : PARAMETER_UNIT_KEYS[key];
  return localizedUnit(unitKey);
}

function editableUnit(knob) {
  if (knob.group === "initial_conditions" && knob.key === "r_bar") {
    return UNITS.annualFraction;
  }
  return inputUnit(knob.group, knob.key);
}

function compactControlUnit(unit) {
  if (unit === UNITS.quarterlyFraction) return "qtr rate";
  if (unit === UNITS.annualFraction) return "annual rate";
  if (unit.moneyKind === "personFlow") return `${monetaryPresentation().symbol}k / qtr`;
  if (unit === UNITS.dimensionless) return "unitless";
  return unit.short;
}

function formatValueWithUnit(value, unit) {
  if (unit.type === "boolean") return value ? "Enabled" : "Disabled";
  if (unit.type === "moneyMillions") return formatMoneyMillions(value);
  if (unit.type === "fraction") return `${formatMetric(value)} (${formatPercent(value)})`;
  if (unit.type === "percent") return formatPercent(value);
  return `${formatMetric(value)} ${unit.short}`;
}

function seriesChange(series) {
  if (!Array.isArray(series) || series.length < 2) return null;
  const start = Number(series[0]);
  const end = Number(series[series.length - 1]);
  if (!Number.isFinite(start) || !Number.isFinite(end) || start === 0) return null;
  return (end / start - 1) * 100;
}

function describeInput(group, key) {
  if (group === "initial_conditions") {
    return INITIAL_DESCRIPTIONS[key] || `Initial model state supplied for ${key.replaceAll("_", " ")}.`;
  }
  if (EDITABLE_META[key]) return EDITABLE_META[key].description;
  if (PARAMETER_DESCRIPTIONS[key]) return PARAMETER_DESCRIPTIONS[key];
  if (key.startsWith("alpha_")) return `Persistence coefficient of the calibrated stochastic process for ${key.slice(6).replaceAll("_", " ")}.`;
  if (key.startsWith("beta_")) return `Intercept of the calibrated stochastic process for ${key.slice(5).replaceAll("_", " ")}.`;
  if (key.startsWith("sigma_")) return `Innovation volatility of the calibrated stochastic process for ${key.slice(6).replaceAll("_", " ")}.`;
  return `Calibrated structural model parameter ${key}.`;
}

function normalizeMatrix(values, shape) {
  if (!Array.isArray(values)) return [];
  if (Array.isArray(values[0])) return values;
  const rows = Number(shape?.[0]);
  const columns = Number(shape?.[1]);
  if (!rows || !columns || values.length !== rows * columns) return [];
  return Array.from({ length: rows }, (_, row) => (
    Array.from({ length: columns }, (_, column) => values[row + column * rows])
  ));
}

function relativeQuarterLabels(length) {
  const historicalLength = Math.min(state.historicalLookback, length);
  return Array.from({ length }, (_, index) => {
    const offset = index - historicalLength + 1;
    if (offset === 0) return "Q0";
    return offset > 0 ? `Q+${offset}` : `Q${offset}`;
  });
}

function classificationLabel() {
  return String(
    state.sectorMetadata?.classification_label
      || state.sectorMetadata?.classification
      || "dataset industry classification",
  );
}

function axisMetadata(group, key, data) {
  if (data.kind === "vector" && data.value.length === state.sectors.length) {
    const sectorCount = state.sectors.length;
    return {
      type: "industry",
      labels: state.sectors.map((sector) => `${sector.index}. ${sector.code} · ${sector.label}`),
      codes: state.sectors.map((sector) => sector.code),
      explanation: `Industry index 1–${sectorCount} follows this dataset's ${classificationLabel()} ordering. Each bar is one named industry or product group; the index is an identifier, not time.`,
    };
  }
  if (data.kind === "vector") {
    const historicalQuarters = Math.min(state.historicalLookback, data.value.length);
    const forwardQuarters = Math.max(0, data.value.length - historicalQuarters);
    const historicalRange = historicalQuarters === 1
      ? "Q0"
      : `Q-${historicalQuarters - 1} through Q0`;
    return {
      type: "time",
      labels: relativeQuarterLabels(data.value.length),
      explanation: forwardQuarters > 0
        ? `Q0 is the dataset's calibration quarter. The ${historicalQuarters} observations from ${historicalRange} are historical inputs used to form expectations; Q+1 to Q+${forwardQuarters} are forward exogenous quarters.`
        : `Q0 is the dataset's calibration quarter. This series contains ${historicalQuarters} historical observations from ${historicalRange} and ends at Q0.`,
    };
  }
  if (data.kind === "matrix" && data.shape?.[0] === state.sectors.length && data.shape?.[1] === state.sectors.length) {
    return {
      type: "industryMatrix",
      xLabels: state.sectors.map((sector) => sector.code),
      yLabels: state.sectors.map((sector) => sector.code),
      xHoverLabels: state.sectors.map((sector) => sector.label),
      yHoverLabels: state.sectors.map((sector) => sector.label),
      explanation: `Rows are supplying ${classificationLabel()} industries and columns are using industries/products. Hover a cell to see both full industry labels and the coefficient.`,
    };
  }
  if (group === "parameters" && key === "C") {
    const labels = ["Reference-area output", "Exports", "Imports"];
    return {
      type: "covarianceMatrix",
      xLabels: labels,
      yLabels: labels,
      explanation: "Rows and columns identify the three estimated shocks. Each cell is their covariance in squared log points.",
    };
  }
  return null;
}

function createExplorerPlotTarget(container, className = "") {
  const plot = document.createElement("div");
  plot.className = `explorer-plot ${className}`.trim();
  container.appendChild(plot);
  return plot;
}

function basePlotLayout(height) {
  return {
    autosize: true,
    height,
    margin: { t: 18, r: 24, b: 42, l: 58 },
    paper_bgcolor: "rgba(0,0,0,0)",
    plot_bgcolor: "rgba(0,0,0,0)",
    font: { family: "Inter, ui-sans-serif, system-ui, sans-serif", color: "#667085", size: 11 },
    hovermode: "x unified",
    hoverlabel: { bgcolor: "#101828", bordercolor: "#101828", font: { color: "#fff", size: 11 } },
    xaxis: {
      title: { text: "Quarter", font: { size: 10, color: "#98a2b3" } },
      gridcolor: "#eef1f5",
      linecolor: "#dfe4eb",
      zeroline: false,
      fixedrange: false,
    },
    yaxis: {
      gridcolor: "#eef1f5",
      linecolor: "#dfe4eb",
      zerolinecolor: "#dfe4eb",
      fixedrange: false,
      tickformat: "~s",
    },
    legend: {
      orientation: "h",
      x: 0,
      y: 1.08,
      font: { size: 10 },
      bgcolor: "rgba(0,0,0,0)",
    },
  };
}

function plotTimeSeries(target, values, labels, unit, color = "#3267e3") {
  const trace = {
    x: labels,
    y: values,
    type: "scatter",
    mode: "lines",
    name: "value",
    line: { color, width: 2.2, shape: "spline", smoothing: 0.45 },
    hovertemplate: `%{x}<br><b>%{y:,.4g} ${unit.short}</b><extra></extra>`,
  };
  const layout = basePlotLayout(390);
  const tickInterval = Math.max(1, Math.ceil((labels.length - 1) / 10));
  const tickIndices = Array.from(
    new Set([
      ...Array.from({ length: Math.ceil(labels.length / tickInterval) }, (_, index) => index * tickInterval),
      labels.length - 1,
    ]),
  ).filter((index) => index >= 0 && index < labels.length);
  layout.xaxis.title.text = "Quarter relative to calibration";
  layout.xaxis.tickmode = "array";
  layout.xaxis.tickvals = tickIndices.map((index) => labels[index]);
  layout.xaxis.ticktext = tickIndices.map((index) => labels[index]);
  layout.yaxis.title = { text: unit.label, font: { size: 10, color: "#98a2b3" } };
  layout.showlegend = false;
  return Plotly.react(target, [trace], layout, PLOT_CONFIG);
}

function plotIndustryBars(target, values, axis, unit) {
  const height = Math.max(460, values.length * 27 + 90);
  const trace = {
    x: values,
    y: axis.labels,
    type: "bar",
    orientation: "h",
    marker: {
      color: values,
      colorscale: [
        [0, "#b8caf7"],
        [1, "#3267e3"],
      ],
      line: { color: "rgba(36, 86, 214, 0.2)", width: 0.5 },
    },
    hovertemplate: `<b>%{y}</b><br>%{x:,.4g} ${unit.short}<extra></extra>`,
  };
  const layout = basePlotLayout(height);
  layout.margin = { t: 16, r: 30, b: 56, l: 330 };
  layout.hovermode = "closest";
  layout.showlegend = false;
  layout.xaxis.title.text = unit.label;
  layout.yaxis = {
    autorange: "reversed",
    automargin: false,
    gridcolor: "rgba(0,0,0,0)",
    tickfont: { size: 9, color: "#475467" },
    fixedrange: false,
  };
  return Plotly.react(target, [trace], layout, PLOT_CONFIG);
}

function plotMatrixHeatmap(target, values, options = {}) {
  const {
    height = 390,
    xLabels = null,
    yLabels = null,
    xHoverLabels = null,
    yHoverLabels = null,
    unit = UNITS.dimensionless,
    xTitle = "Column",
    yTitle = "Row",
  } = options;
  const customdata = values.map((row, rowIndex) => (
    row.map((_, columnIndex) => [
      yHoverLabels?.[rowIndex] || yLabels?.[rowIndex] || rowIndex + 1,
      xHoverLabels?.[columnIndex] || xLabels?.[columnIndex] || columnIndex + 1,
    ])
  ));
  const trace = {
    z: values,
    ...(Array.isArray(xLabels) ? { x: xLabels } : {}),
    ...(Array.isArray(yLabels) ? { y: yLabels } : {}),
    customdata,
    type: "heatmap",
    colorscale: [
      [0, "#eef3ff"],
      [0.35, "#a9c0f8"],
      [0.7, "#4f7cf0"],
      [1, "#173f9e"],
    ],
    colorbar: {
      thickness: 10,
      outlinewidth: 0,
      tickfont: { size: 9, color: "#667085" },
      title: { text: unit.short, side: "right", font: { size: 9, color: "#667085" } },
    },
    hovertemplate: `Row: %{customdata[0]}<br>Column: %{customdata[1]}<br><b>%{z:,.4g} ${unit.short}</b><extra></extra>`,
  };
  const layout = basePlotLayout(height);
  const longestYLabel = Array.isArray(yLabels)
    ? Math.max(0, ...yLabels.map((label) => String(label).length))
    : 0;
  layout.margin.l = Math.max(58, Math.min(180, 24 + longestYLabel * 6));
  layout.hovermode = "closest";
  layout.xaxis.title.text = xTitle;
  layout.xaxis.tickangle = xLabels?.length > 20 ? -55 : 0;
  layout.xaxis.tickfont = { size: xLabels?.length > 20 ? 8 : 10 };
  layout.yaxis.title = { text: yTitle, font: { size: 10, color: "#98a2b3" } };
  layout.yaxis.tickfont = { size: yLabels?.length > 20 ? 8 : 10 };
  layout.yaxis.autorange = "reversed";
  return Plotly.react(target, [trace], layout, PLOT_CONFIG);
}

function plotRibbon(target, time, mean, deviation, featured = false, unitKey = "dimensionless") {
  const unit = localizedUnit(unitKey);
  const upper = mean.map((value, index) => (
    value == null || deviation[index] == null ? null : value + deviation[index]
  ));
  const lower = mean.map((value, index) => (
    value == null || deviation[index] == null ? null : value - deviation[index]
  ));
  const isPercent = unit.type === "percent";
  const multiplier = isPercent ? 100 : 1;
  const scaledMean = mean.map((value) => (value == null ? null : value * multiplier));
  const scaledUpper = upper.map((value) => (value == null ? null : value * multiplier));
  const scaledLower = lower.map((value) => (value == null ? null : value * multiplier));
  const traces = [
    {
      x: time,
      y: scaledUpper,
      type: "scatter",
      mode: "lines",
      line: { width: 0 },
      showlegend: false,
      hoverinfo: "skip",
    },
    {
      x: time,
      y: scaledLower,
      type: "scatter",
      mode: "lines",
      fill: "tonexty",
      fillcolor: "rgba(79, 124, 240, 0.15)",
      line: { width: 0 },
      name: "±1 SD",
      hoverinfo: "skip",
    },
    {
      x: time,
      y: scaledMean,
      type: "scatter",
      mode: "lines",
      name: "Ensemble mean",
      line: { color: "#3267e3", width: featured ? 2.8 : 2.2, shape: "spline", smoothing: 0.35 },
      hovertemplate: `%{x}<br><b>%{y:,.3g}${isPercent ? "%" : ` ${unit.short}`}</b><extra></extra>`,
    },
  ];
  const layout = basePlotLayout(featured ? 350 : 275);
  layout.yaxis.title = { text: unit.label, font: { size: 10, color: "#98a2b3" } };
  if (isPercent) layout.yaxis.ticksuffix = "%";
  return Plotly.react(target, traces, layout, PLOT_CONFIG);
}

function showToast(message, isError = false) {
  const toast = el("toast");
  toast.textContent = message;
  toast.classList.toggle("is-error", isError);
  toast.hidden = false;
  window.clearTimeout(showToast.timeout);
  showToast.timeout = window.setTimeout(() => {
    toast.hidden = true;
  }, 4200);
}

function setEngineError(hasError) {
  el("enginePill").classList.toggle("has-error", hasError);
  el("enginePill").lastElementChild.textContent = hasError ? "Julia engine unavailable" : "Julia engine connected";
}

function setProgress(message, progress = 0, visible = true) {
  const normalized = Math.min(1, Math.max(0, Number(progress) || 0));
  el("runProgressWrap").hidden = !visible;
  el("progressBar").style.width = `${normalized * 100}%`;
  el("progressPercent").textContent = `${Math.round(normalized * 100)}%`;
  el("statusText").textContent = message || "";
}

function selectedDataset() {
  return state.datasets.find((dataset) => dataset.id === el("datasetSelect").value) || null;
}

function renderProvenance() {
  const metadata = state.datasetMetadata;
  if (!metadata) return;
  const scenario = el("scenarioSelect").value;
  const productionStatus = metadata.measurement_status?.production_network
    || metadata.measurement_status?.calibration
    || "Packaged model structure";
  const sourcePublisher = metadata.source_publisher
    || (metadata.country === "AT" ? "Eurostat" : "public-source");
  const sourceDetail = metadata.live_source_count > 0
    ? `${metadata.live_source_count} live ${sourcePublisher} series`
    : metadata.input_snapshot_count > 0
      ? `${metadata.input_snapshot_count} archived source snapshots`
      : "No live-series refresh";
  const sourceUpdate = metadata.latest_source_update
    ? `Latest publisher update ${String(metadata.latest_source_update).replace("T", " ").slice(0, 16)}`
    : metadata.kind === "structural"
      ? metadata.country === "AT"
        ? "Pinned February 2026 source snapshot"
        : "Pinned source snapshot"
      : "Packaged calibration";
  const outputMeasurement = metadata.output_measurement || {};
  const measuredSeries = Object.keys(outputMeasurement.series || {});
  const items = [
    {
      label: "Starting vintage",
      value: metadata.period,
      detail: metadata.description,
    },
    {
      label: "Observed controls",
      value: `Through ${metadata.observed_through}`,
      detail: scenario === "unconditional"
        ? "Subsequent quarters are stochastic model output"
        : `Forecast begins after ${metadata.observed_through}`,
    },
    {
      label: "Production network",
      value: metadata.country === "AT"
        ? `FIGARO ${metadata.structural_reference_year}`
        : `${classificationLabel()} ${metadata.structural_reference_year}`,
      detail: productionStatus,
    },
    {
      label: "Source audit",
      value: sourceDetail,
      detail: sourceUpdate,
    },
  ];
  if (measuredSeries.length > 0) {
    items.splice(2, 0, {
      label: "Published output basis",
      value: `Origin-anchored at ${outputMeasurement.origin_period || metadata.period}`,
      detail: `${measuredSeries.length} real series compound simulated growth onto released opening levels; raw model units remain in the run export.`,
    });
  }
  const root = el("datasetProvenance");
  root.replaceChildren();
  items.forEach((item) => {
    const container = document.createElement("div");
    container.className = "provenance-item";
    const label = document.createElement("span");
    label.textContent = item.label;
    const value = document.createElement("strong");
    value.textContent = item.value;
    value.title = item.value;
    const detail = document.createElement("small");
    detail.textContent = item.detail;
    detail.title = item.detail;
    container.append(label, value, detail);
    root.appendChild(container);
  });
}

function renderScenarioAssumptions() {
  const details = el("scenarioEvidence");
  const root = el("scenarioAssumptions");
  const scenario = el("scenarioSelect").value;
  root.replaceChildren();
  if (scenario === "unconditional" || state.scenarioAssumptions.length === 0) {
    details.hidden = true;
    details.open = false;
    return;
  }
  details.hidden = false;
  el("scenarioEvidenceSummary").textContent = `${SCENARIO_LABELS[scenario]} · 2026–2031 · percentages per year`;
  const table = document.createElement("table");
  table.className = "scenario-table";
  const head = document.createElement("thead");
  const headerRow = document.createElement("tr");
  ["Year", "Real GDP", "HICP", "Gov. consumption", "Exports", "Imports", "Source"].forEach((heading) => {
    const cell = document.createElement("th");
    cell.scope = "col";
    cell.textContent = heading;
    headerRow.appendChild(cell);
  });
  head.appendChild(headerRow);
  const body = document.createElement("tbody");
  state.scenarioAssumptions.forEach((row) => {
    const tr = document.createElement("tr");
    [
      row.year,
      `${row.real_gdp_growth.toFixed(1)}%`,
      `${row.hicp_inflation.toFixed(1)}%`,
      `${row.government_consumption_growth.toFixed(1)}%`,
      `${row.exports_growth.toFixed(1)}%`,
      `${row.imports_growth.toFixed(1)}%`,
      row.source,
    ].forEach((value, index) => {
      const cell = document.createElement("td");
      cell.textContent = String(value);
      if (index === 6) {
        cell.className = "source-cell";
        cell.title = row.method;
      }
      tr.appendChild(cell);
    });
    body.appendChild(tr);
  });
  table.append(head, body);
  root.appendChild(table);
}

function updateHorizonBounds() {
  const dataset = selectedDataset();
  const scenario = el("scenarioSelect").value;
  const input = el("TInput");
  const maximum = scenario === "unconditional" ? 80 : 23;
  input.max = String(maximum);
  if (Number(input.value) > maximum) input.value = String(maximum);
  if (!input.value && dataset) input.value = String(dataset.default_horizon);
}

async function reloadScenarioContext() {
  const datasetId = el("datasetSelect").value;
  const scenario = el("scenarioSelect").value;
  window.localStorage.setItem(`beforeit-scenario-${datasetId}`, scenario);
  updateHorizonBounds();
  const response = await apiGet(
    `/api/scenarios?dataset_id=${encodeURIComponent(datasetId)}&scenario=${encodeURIComponent(scenario)}`,
  );
  state.scenarioAssumptions = response.assumptions || [];
  renderScenarioAssumptions();
  renderProvenance();
}

function renderScenarioOptions(dataset) {
  const select = el("scenarioSelect");
  select.replaceChildren();
  dataset.scenarios.forEach((scenario) => {
    const option = document.createElement("option");
    option.value = scenario;
    option.textContent = SCENARIO_LABELS[scenario] || scenario;
    select.appendChild(option);
  });
  const saved = window.localStorage.getItem(`beforeit-scenario-${dataset.id}`);
  select.value = saved && dataset.scenarios.includes(saved)
    ? saved
    : dataset.default_scenario;
  el("TInput").value = String(dataset.default_horizon);
  updateHorizonBounds();
}

function activateTab(name) {
  state.activeTab = name;
  document.querySelectorAll(".tab-button").forEach((button) => {
    const active = button.dataset.tab === name;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-selected", String(active));
    button.tabIndex = active ? 0 : -1;
  });
  el("resultsPanel").hidden = name !== "results";
  el("inputsPanel").hidden = name !== "inputs";
  window.requestAnimationFrame(() => {
    document.querySelectorAll(".js-plotly-plot").forEach((plot) => Plotly.Plots.resize(plot));
  });
}

function editableMeta(knob) {
  return EDITABLE_META[knob.key] || {
    label: knob.label,
    category: knob.group === "initial_conditions" ? "Initial conditions" : "Other",
    description: `Editable model input ${knob.group}.${knob.key}.`,
  };
}

function emptyOverrides() {
  return { parameters: {}, initial_conditions: {} };
}

function copyObject(value, fallback = {}) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return { ...fallback };
  try {
    return JSON.parse(JSON.stringify(value));
  } catch {
    return { ...fallback };
  }
}

function cloneInheritanceFromRunSpec(spec, run = {}) {
  const sourceRunId = String(spec?.run_id || run?.run_id || "").trim();
  const defaultTrace = {
    profile: "standard",
    realization_indices: [1],
    phase_detail: "none",
    checkpoints: false,
  };
  return {
    parentRunId: sourceRunId || null,
    trace: copyObject(spec?.trace, defaultTrace),
  };
}

function cloneSubmissionFields(cloneState) {
  return {
    parent_run_id: cloneState?.cloneParentRunId || null,
    trace: copyObject(cloneState?.cloneTrace, {
      profile: "standard",
      realization_indices: [1],
      phase_detail: "none",
      checkpoints: false,
    }),
  };
}

function getOverridesFromForm() {
  const preserved = copyObject(state.preservedOverrides, emptyOverrides());
  const overrides = {
    parameters: { ...(preserved.parameters || {}) },
    initial_conditions: { ...(preserved.initial_conditions || {}) },
  };
  state.knobs.forEach((knob) => {
    const input = el(`knob-${knob.group}-${knob.key}`);
    if (!input || input.value === "") return;
    const value = Number(input.value);
    const baseline = Number(input.dataset.baseline);
    if (!Number.isFinite(value) || Math.abs(value - baseline) < 1e-12) return;
    overrides[knob.group][knob.key] = value;
  });
  if (Object.keys(overrides.parameters).length === 0) delete overrides.parameters;
  if (Object.keys(overrides.initial_conditions).length === 0) delete overrides.initial_conditions;
  return overrides;
}

function overrideCount(overrides) {
  return Object.values(overrides).reduce((total, group) => total + Object.keys(group).length, 0);
}

function updateOverrides() {
  const overrides = getOverridesFromForm();
  const count = overrideCount(overrides);
  el("overridesPreview").textContent = JSON.stringify(overrides, null, 2);
  el("overrideBadge").hidden = count === 0;
  el("overrideBadge").textContent = String(count);
  el("overrideSummary").textContent = count === 0
    ? "No changes from calibrated defaults"
    : `${count} parameter${count === 1 ? "" : "s"} changed`;

  state.knobs.forEach((knob) => {
    const input = el(`knob-${knob.group}-${knob.key}`);
    if (!input) return;
    const changed = Math.abs(Number(input.value) - Number(input.dataset.baseline)) >= 1e-12;
    input.closest(".parameter-row").classList.toggle("is-modified", changed);
  });
}

function applyKnobFilter() {
  const query = el("knobSearch").value.trim().toLowerCase();
  document.querySelectorAll(".parameter-row").forEach((row) => {
    const categoryMatch = state.knobCategory === "All" || row.dataset.category === state.knobCategory;
    const textMatch = !query || row.dataset.search.includes(query);
    row.hidden = !(categoryMatch && textMatch);
  });
  document.querySelectorAll(".parameter-group").forEach((group) => {
    group.hidden = !Array.from(group.querySelectorAll(".parameter-row")).some((row) => !row.hidden);
  });
}

function renderKnobFilters(categories) {
  const root = el("knobFilters");
  root.replaceChildren();
  ["All", ...categories].forEach((category) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `filter-chip${state.knobCategory === category ? " is-active" : ""}`;
    const count = category === "All"
      ? state.knobs.length
      : state.knobs.filter((knob) => editableMeta(knob).category === category).length;
    button.textContent = category;
    const badge = document.createElement("span");
    badge.textContent = String(count);
    button.appendChild(badge);
    button.addEventListener("click", () => {
      state.knobCategory = category;
      root.querySelectorAll(".filter-chip").forEach((chip) => chip.classList.toggle("is-active", chip === button));
      applyKnobFilter();
    });
    root.appendChild(button);
  });
}

function renderKnobs(knobs) {
  state.knobs = knobs;
  const groups = new Map();
  knobs.forEach((knob) => {
    const meta = editableMeta(knob);
    if (!groups.has(meta.category)) groups.set(meta.category, []);
    groups.get(meta.category).push(knob);
  });

  renderKnobFilters([...groups.keys()]);
  const root = el("knobsForm");
  root.replaceChildren();

  groups.forEach((groupKnobs, category) => {
    const section = document.createElement("section");
    section.className = "parameter-group";
    section.dataset.category = category;

    const header = document.createElement("div");
    header.className = "parameter-group-header";
    const heading = document.createElement("h3");
    heading.textContent = category;
    const count = document.createElement("span");
    count.textContent = `${groupKnobs.length} parameters`;
    header.append(heading, count);

    const grid = document.createElement("div");
    grid.className = "parameter-grid";
    groupKnobs.forEach((knob) => {
      const meta = editableMeta(knob);
      const unitMeta = editableUnit(knob);
      const tooltip = `${meta.description} Unit: ${unitMeta.label}.`;
      const row = document.createElement("div");
      row.className = "parameter-row";
      row.dataset.category = category;
      row.dataset.search = `${meta.label} ${knob.key} ${meta.description} ${category} ${unitMeta.label}`.toLowerCase();

      const copy = document.createElement("div");
      copy.className = "parameter-copy";
      const title = document.createElement("div");
      title.className = "parameter-title";
      const label = document.createElement("label");
      label.htmlFor = `knob-${knob.group}-${knob.key}`;
      label.textContent = meta.label;
      const info = document.createElement("button");
      info.type = "button";
      info.className = "info-tip";
      info.textContent = "i";
      info.dataset.tooltip = tooltip;
      info.title = tooltip;
      info.setAttribute("aria-label", `About ${meta.label}`);
      title.append(label, info);
      const key = document.createElement("small");
      key.textContent = `${knob.key} · ${knob.min}–${knob.max} · ${unitMeta.short}`;
      copy.append(title, key);

      const control = document.createElement("div");
      control.className = "parameter-control";
      const input = document.createElement("input");
      input.id = `knob-${knob.group}-${knob.key}`;
      input.type = "number";
      input.step = "any";
      input.min = knob.min;
      input.max = knob.max;
      input.value = formatEditableValue(knob.default);
      input.dataset.baseline = input.value;
      input.setAttribute("aria-describedby", `${input.id}-unit`);
      input.addEventListener("input", updateOverrides);
      control.appendChild(input);
      const unit = document.createElement("span");
      unit.id = `${input.id}-unit`;
      unit.className = "unit-label";
      unit.textContent = compactControlUnit(unitMeta);
      unit.title = unitMeta.label;
      control.appendChild(unit);

      row.append(copy, control);
      grid.appendChild(row);
    });

    section.append(header, grid);
    root.appendChild(section);
  });
  updateOverrides();
}

function resetKnobs() {
  state.preservedOverrides = emptyOverrides();
  state.knobs.forEach((knob) => {
    const input = el(`knob-${knob.group}-${knob.key}`);
    if (input) input.value = input.dataset.baseline;
  });
  updateOverrides();
  renderCloneContext();
  showToast("Parameters reset to calibrated defaults.");
}

function shockIsNone(shock) {
  return !shock || typeof shock !== "object" || String(shock.type || "none") === "none";
}

function shockSummary(shock) {
  if (shockIsNone(shock)) return "no intervention shock";
  const type = String(shock.type).replaceAll("_", " ");
  const settings = Object.entries(shock)
    .filter(([key]) => key !== "type")
    .map(([key, value]) => `${key.replaceAll("_", " ")} ${Array.isArray(value) ? value.join(", ") : value}`);
  return `${type}${settings.length ? ` (${settings.join("; ")})` : ""}`;
}

function preservedOverrideCount() {
  return Object.values(state.preservedOverrides || {}).reduce(
    (total, group) => total + Object.keys(group || {}).length,
    0,
  );
}

function renderCloneContext() {
  const root = el("cloneContext");
  if (!state.cloneSourceName) {
    root.hidden = true;
    return;
  }
  const inheritedShock = !shockIsNone(state.cloneShock);
  const hiddenOverrides = preservedOverrideCount();
  const tracedRealizations = Array.isArray(state.cloneTrace?.realization_indices)
    ? state.cloneTrace.realization_indices.join(", ")
    : "";
  const traceSummary = `${state.cloneTrace?.profile || "standard"} trace${tracedRealizations ? ` · realization ${tracedRealizations}` : ""}`;
  el("cloneContextName").textContent = `Clone settings restored from “${state.cloneSourceName}”`;
  el("cloneContextDetail").textContent = inheritedShock
    ? `Scenario, simulation controls, ${traceSummary}, and stored overrides were restored. The inherited ${shockSummary(state.cloneShock)} will be submitted with the next run${hiddenOverrides ? `; ${hiddenOverrides} non-editable override${hiddenOverrides === 1 ? " is" : "s are"} also preserved` : ""}.`
    : `Scenario, simulation controls, ${traceSummary}, and stored overrides were restored with no intervention shock${hiddenOverrides ? `; ${hiddenOverrides} non-editable override${hiddenOverrides === 1 ? " is" : "s are"} also preserved` : ""}.`;
  el("clearInheritedShock").hidden = !inheritedShock;
  root.hidden = false;
}

function clearCloneInheritance() {
  state.cloneSourceName = null;
  state.cloneParentRunId = null;
  state.cloneTrace = {
    profile: "standard",
    realization_indices: [1],
    phase_detail: "none",
    checkpoints: false,
  };
  state.cloneShock = { type: "none" };
  state.preservedOverrides = emptyOverrides();
  renderCloneContext();
}

async function restoreRunSpec(spec, run) {
  if (!spec || typeof spec !== "object") throw new Error("The saved run specification is unavailable.");
  state.preservedOverrides = emptyOverrides();
  const datasetId = String(spec.dataset_id || run?.dataset_id || "");
  if (datasetId && el("datasetSelect").value !== datasetId) {
    if (!state.datasetLabels.has(datasetId)) throw new Error(`The cloned run uses unavailable dataset ${datasetId}.`);
    el("datasetSelect").value = datasetId;
    await reloadForDataset({ resetClone: false });
  }

  const dataset = selectedDataset();
  const scenario = String(spec.scenario || "");
  if (scenario && !dataset?.scenarios?.includes(scenario)) {
    throw new Error(`The cloned run's scenario “${scenario}” is unavailable for ${datasetId}.`);
  }
  if (scenario) {
    el("scenarioSelect").value = scenario;
    await reloadScenarioContext();
  }
  const sim = spec.sim && typeof spec.sim === "object" ? spec.sim : {};
  if (Number.isFinite(Number(sim.T))) el("TInput").value = String(Number(sim.T));
  if (Number.isFinite(Number(sim.n_sims))) el("nSimsInput").value = String(Number(sim.n_sims));
  if (Number.isFinite(Number(sim.base_seed))) el("seedInput").value = String(Number(sim.base_seed));
  if (sim.step_multithreading != null) el("mtInput").checked = Boolean(sim.step_multithreading);

  const storedOverrides = spec.overrides && typeof spec.overrides === "object"
    ? spec.overrides
    : emptyOverrides();
  for (const group of ["parameters", "initial_conditions"]) {
    for (const [key, value] of Object.entries(storedOverrides[group] || {})) {
      const input = el(`knob-${group}-${key}`);
      if (input) input.value = String(value);
      else state.preservedOverrides[group][key] = value;
    }
  }
  state.cloneSourceName = run?.display_name || run?.name || spec.name || datasetId || "saved run";
  const inheritance = cloneInheritanceFromRunSpec(spec, run);
  state.cloneParentRunId = inheritance.parentRunId;
  state.cloneTrace = inheritance.trace;
  const restoredShock = copyObject(spec.shock, { type: "none" });
  state.cloneShock = restoredShock.type ? restoredShock : { type: "none" };
  updateOverrides();
  renderCloneContext();
  renderProvenance();
}

function renderInputCatalog() {
  const items = state.schema[state.inputGroup] || [];
  const query = el("inputSearch").value.trim().toLowerCase();
  const filtered = items.filter((item) => {
    const description = describeInput(state.inputGroup, item.key);
    const unit = inputUnit(state.inputGroup, item.key);
    return !query || `${item.key} ${item.kind} ${description} ${unit.label}`.toLowerCase().includes(query);
  });

  const root = el("inputCatalog");
  root.replaceChildren();
  if (filtered.length === 0) {
    const empty = document.createElement("div");
    empty.className = "catalog-empty";
    empty.textContent = "No inputs match this search.";
    root.appendChild(empty);
    return;
  }

  filtered.forEach((item) => {
    const description = describeInput(state.inputGroup, item.key);
    const unit = inputUnit(state.inputGroup, item.key);
    const tooltip = `${description} Unit: ${unit.label}.`;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "input-item";
    button.classList.toggle(
      "is-active",
      state.selectedInput?.group === state.inputGroup && state.selectedInput?.key === item.key,
    );
    button.title = tooltip;

    const title = document.createElement("span");
    title.className = "input-item-title";
    const code = document.createElement("code");
    code.textContent = item.key;
    const info = document.createElement("span");
    info.className = "info-tip";
    info.textContent = "i";
    info.dataset.tooltip = tooltip;
    info.title = tooltip;
    info.setAttribute("aria-label", tooltip);
    title.append(code, info);

    const kind = document.createElement("span");
    kind.className = "input-kind";
    kind.textContent = `${item.kind}${item.shape ? ` ${formatShape(item.shape)}` : ""}`;
    const detail = document.createElement("p");
    detail.textContent = `${description} Unit: ${unit.label}.`;
    button.append(title, kind, detail);
    button.addEventListener("click", () => loadInputValue(state.inputGroup, item.key));
    root.appendChild(button);
  });
}

async function loadInputValue(group, key) {
  state.selectedInput = { group, key };
  renderInputCatalog();
  const datasetId = el("datasetSelect").value;
  const description = describeInput(group, key);
  const unit = inputUnit(group, key);
  const meta = el("inputMeta");
  meta.replaceChildren();
  const eyebrow = document.createElement("span");
  eyebrow.className = "eyebrow";
  eyebrow.textContent = group === "parameters" ? "Structural parameter" : "Initial condition";
  const heading = document.createElement("h3");
  heading.textContent = key;
  const copy = document.createElement("p");
  copy.textContent = description;
  meta.append(eyebrow, heading, copy);

  const target = el("inputPlot");
  if (target.classList.contains("js-plotly-plot")) Plotly.purge(target);
  target.querySelectorAll(".js-plotly-plot").forEach((plot) => Plotly.purge(plot));
  target.replaceChildren();

  try {
    const data = await apiGet(
      `/api/datasets/value?dataset_id=${encodeURIComponent(datasetId)}&group=${encodeURIComponent(group)}&key=${encodeURIComponent(key)}`,
    );
    const metadata = document.createElement("div");
    metadata.className = "preview-meta";
    [
      data.kind,
      data.shape ? formatShape(data.shape) : "single value",
      unit.label,
      state.datasetLabels.get(datasetId) || datasetId,
    ].forEach((value) => {
      const badge = document.createElement("span");
      badge.textContent = value;
      metadata.appendChild(badge);
    });
    meta.appendChild(metadata);
    const axis = axisMetadata(group, key, data);
    if (axis?.explanation) {
      const explanation = document.createElement("div");
      explanation.className = "axis-explanation";
      const explanationTitle = document.createElement("strong");
      explanationTitle.textContent = "How to read the index";
      const explanationCopy = document.createElement("p");
      explanationCopy.textContent = axis.explanation;
      explanation.append(explanationTitle, explanationCopy);
      meta.appendChild(explanation);
    }

    if (data.kind === "scalar") {
      const scalar = document.createElement("div");
      scalar.className = "scalar-preview";
      const label = document.createElement("span");
      label.textContent = "Calibrated value";
      const value = document.createElement("strong");
      value.textContent = formatValueWithUnit(data.value, unit);
      value.title = `${data.value} ${unit.label}`;
      const exact = document.createElement("small");
      exact.textContent = `Exact model value: ${data.value} · ${unit.label}`;
      scalar.append(label, value, exact);
      target.appendChild(scalar);
    } else if (data.kind === "vector") {
      const plot = createExplorerPlotTarget(
        target,
        axis?.type === "industry" ? "industry-bar-plot" : "",
      );
      if (axis?.type === "industry") {
        await plotIndustryBars(plot, data.value, axis, unit);
      } else {
        await plotTimeSeries(
          plot,
          data.value,
          axis?.labels || data.value.map((_, index) => index + 1),
          unit,
        );
      }
    } else if (data.kind === "matrix") {
      const matrix = normalizeMatrix(data.value, data.shape);
      if (matrix.length === 0) {
        throw new Error(`Unexpected ${formatShape(data.shape)} matrix layout for ${key}.`);
      }
      const plot = createExplorerPlotTarget(target);
      await plotMatrixHeatmap(plot, matrix, {
        height: axis?.type === "industryMatrix" ? 680 : 390,
        xLabels: axis?.xLabels,
        yLabels: axis?.yLabels,
        xHoverLabels: axis?.xHoverLabels,
        yHoverLabels: axis?.yHoverLabels,
        unit,
        xTitle: axis?.type === "industryMatrix"
          ? `Using industry / product (${classificationLabel()})`
          : "Shock",
        yTitle: axis?.type === "industryMatrix"
          ? `Supplying industry (${classificationLabel()})`
          : "Shock",
      });
    } else {
      target.innerHTML = '<div class="history-empty">This input type cannot be visualized.</div>';
    }
  } catch (error) {
    target.innerHTML = '<div class="history-empty">Unable to load this input.</div>';
    showToast(String(error), true);
  }
}

async function loadInputsSchema(datasetId) {
  const [schema, lookback] = await Promise.all([
    apiGet(`/api/datasets/schema?dataset_id=${encodeURIComponent(datasetId)}`),
    apiGet(`/api/datasets/value?dataset_id=${encodeURIComponent(datasetId)}&group=parameters&key=T_prime`),
  ]);
  state.schema = schema;
  state.historicalLookback = Number(lookback.value) || 54;
  el("parametersCount").textContent = String(state.schema.parameters.length);
  el("initialConditionsCount").textContent = String(state.schema.initial_conditions.length);
  state.selectedInput = null;
  renderInputCatalog();
  const first = state.schema[state.inputGroup]?.[0];
  if (first) await loadInputValue(state.inputGroup, first.key);
}

function formatRunTime(dateString) {
  const date = new Date(dateString);
  if (Number.isNaN(date.getTime())) return dateString;
  const elapsed = Date.now() - date.getTime();
  if (elapsed >= 0 && elapsed < 60_000) return "Just now";
  if (elapsed >= 0 && elapsed < 3_600_000) return `${Math.floor(elapsed / 60_000)} min ago`;
  if (elapsed >= 0 && elapsed < 86_400_000) return `${Math.floor(elapsed / 3_600_000)} hr ago`;
  return new Intl.DateTimeFormat("en", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(date);
}

function shortDatasetName(datasetId) {
  return (state.datasetLabels.get(datasetId) || datasetId)
    .replace(" legacy", "")
    .replace(" structural", "")
    .replace(" nowcast", "")
    .replace("Steady state", "Steady");
}

function renderRuns() {
  const root = el("runsList");
  root.replaceChildren();
  if (state.runs.length === 0) {
    const empty = document.createElement("div");
    empty.className = "history-empty";
    empty.textContent = "No simulation runs yet.";
    root.appendChild(empty);
    return;
  }

  state.runs.slice(0, 6).forEach((run) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "run-item";
    button.classList.toggle("is-active", run.run_id === state.currentRunId);
    button.title = `Open run ${run.run_id}`;

    const icon = document.createElement("span");
    icon.className = "run-icon";
    icon.textContent = shortDatasetName(run.dataset_id).slice(0, 2).toUpperCase();
    const copy = document.createElement("span");
    copy.className = "run-copy";
    const dataset = document.createElement("strong");
    dataset.textContent = run.display_name || run.name || shortDatasetName(run.dataset_id);
    const date = document.createElement("small");
    const scenarioLabel = SCENARIO_LABELS[run.scenario] || run.scenario;
    date.textContent = `${shortDatasetName(run.dataset_id)} · ${scenarioLabel} · ${formatRunTime(run.created_at)}`;
    copy.append(dataset, date);
    const status = document.createElement("span");
    status.className = "run-state";
    status.dataset.state = run.state;
    status.textContent = run.state === "running" ? `${Math.round((run.progress || 0) * 100)}%` : run.state;
    button.append(icon, copy, status);
    button.addEventListener("click", () => loadRun(run.run_id));
    root.appendChild(button);
  });
}

async function refreshRuns() {
  state.runs = await apiGet("/api/runs");
  renderRuns();
  return state.runs;
}

function renderMetrics(summary) {
  const gdp = summary.real_gdp?.mean || [];
  const consumption = summary.real_household_consumption?.mean || [];
  const policy = summary.euribor_annual?.mean || [];
  const gdpChange = seriesChange(gdp);
  const consumptionChange = seriesChange(consumption);
  const periods = summary.periods || summary.t || [];
  const periodRange = periods.length > 1
    ? `${periods[0]}–${periods.at(-1)}`
    : periods[0] || `${summary.T} quarters`;
  const cards = [
    {
      label: "Real GDP",
      value: formatMoneyMillions(gdp.at(-1), summary.dataset_metadata),
      detail: gdpChange == null
        ? `Final mean · ${localizedUnit("moneyFlow", summary.dataset_metadata).short}`
        : `${gdpChange >= 0 ? "↑" : "↓"} ${Math.abs(gdpChange).toFixed(1)}% · ${localizedUnit("moneyFlow", summary.dataset_metadata).short}`,
      className: gdpChange >= 0 ? "positive" : "negative",
    },
    {
      label: "Household consumption",
      value: formatMoneyMillions(consumption.at(-1), summary.dataset_metadata),
      detail: consumptionChange == null
        ? `Final mean · ${localizedUnit("moneyFlow", summary.dataset_metadata).short}`
        : `${consumptionChange >= 0 ? "↑" : "↓"} ${Math.abs(consumptionChange).toFixed(1)}% · ${localizedUnit("moneyFlow", summary.dataset_metadata).short}`,
      className: consumptionChange >= 0 ? "positive" : "negative",
    },
    {
      label: "Annual policy rate",
      value: formatPercent(policy.at(-1)),
      detail: "Final ensemble mean · % per year",
      className: "",
    },
    {
      label: "Simulation coverage",
      value: `${summary.n_sims} ${summary.n_sims === 1 ? "path" : "paths"}`,
      detail: `${periodRange} · ±1 SD band`,
      className: "",
    },
  ];

  const root = el("metricsGrid");
  root.replaceChildren();
  cards.forEach((card) => {
    const article = document.createElement("article");
    article.className = "metric-card";
    const label = document.createElement("span");
    label.textContent = card.label;
    const value = document.createElement("strong");
    value.textContent = card.value;
    const detail = document.createElement("small");
    detail.className = card.className;
    detail.textContent = card.detail;
    article.append(label, value, detail);
    root.appendChild(article);
  });
}

function runSupportsExplorer(summary, run) {
  if (typeof summary?.cashflows_available === "boolean") {
    return summary.cashflows_available;
  }
  return Boolean(run?.cashflows_available);
}

function chartCard(title, subtitle, unitKey, className = "") {
  const card = document.createElement("article");
  card.className = `chart-card ${className}`.trim();
  const header = document.createElement("div");
  header.className = "chart-header";
  const heading = document.createElement("h3");
  heading.textContent = title;
  const chartMeta = document.createElement("div");
  chartMeta.className = "chart-meta";
  const detail = document.createElement("span");
  detail.textContent = subtitle;
  const unit = document.createElement("strong");
  unit.className = "chart-unit";
  unit.textContent = localizedUnit(unitKey).short;
  chartMeta.append(detail, unit);
  header.append(heading, chartMeta);
  const plot = document.createElement("div");
  plot.className = "chart-plot";
  card.append(header, plot);
  return { card, plot };
}

async function renderOutputs(runId, summary) {
  state.currentRunId = runId;
  renderRuns();
  const quarterLabel = summary.T === 1 ? "quarter" : "quarters";
  const pathLabel = summary.n_sims === 1 ? "ensemble path" : "ensemble paths";
  el("downloadCsv").href = `/api/runs/${runId}/download?format=csv`;
  el("downloadJld2").href = `/api/runs/${runId}/download?format=jld2`;
  const selectedRun = state.runs.find((run) => run.run_id === runId);
  const networkAvailable = runSupportsExplorer(summary, selectedRun);
  el("exploreRun").href = `/explorer/?run=${encodeURIComponent(runId)}&altitude=economy`;
  el("exploreRun").hidden = !networkAvailable;
  el("downloadCsv").hidden = false;
  el("downloadJld2").hidden = false;
  el("outputEmpty").hidden = true;
  const scenarioLabel = SCENARIO_LABELS[summary.scenario] || summary.scenario || "Unconditional model";
  const periods = summary.periods || summary.t;
  const dateRange = Array.isArray(periods) && periods.length > 1
    ? `${periods[0]}–${periods.at(-1)}`
    : `${summary.T} ${quarterLabel}`;
  const runName = selectedRun?.display_name || selectedRun?.name || null;
  el("resultsSubtitle").textContent = `${runName ? `${runName} · ` : ""}${state.datasetLabels.get(summary.dataset_id) || summary.dataset_id} · ${scenarioLabel} · ${dateRange} · ${summary.n_sims} ${pathLabel}`;
  renderMetrics(summary);

  const root = el("outputPlots");
  root.replaceChildren();
  const renderTasks = [];
  CHARTS.forEach(([key, title, subtitle, unitKey], index) => {
    if (!summary[key]) return;
    const featured = index === 0;
    const { card, plot } = chartCard(title, subtitle, unitKey, featured ? "is-featured" : "");
    root.appendChild(card);
    renderTasks.push(plotRibbon(
      plot,
      periods,
      summary[key].mean,
      summary[key].std,
      featured,
      unitKey,
    ));
  });

  if (summary.real_sector_gva?.mean) {
    const sectorMatrix = normalizeMatrix(
      summary.real_sector_gva.mean,
      [periods.length, state.sectors.length],
    );
    const { card, plot } = chartCard(
      "Sector gross value added",
      `Mean path · quarter × ${classificationLabel()} industry`,
      "moneyFlow",
      "is-wide",
    );
    root.appendChild(card);
    renderTasks.push(plotMatrixHeatmap(
      plot,
      sectorMatrix,
      {
        height: 420,
        xLabels: state.sectors.map((sector) => sector.code),
        yLabels: periods,
        xHoverLabels: state.sectors.map((sector) => `${sector.code} · ${sector.label}`),
        yHoverLabels: periods,
        unit: localizedUnit("moneyFlow"),
        xTitle: `Industry (${classificationLabel()})`,
        yTitle: "Quarter",
      },
    ));
  }
  await Promise.all(renderTasks);
}

async function loadRun(runId, options = {}) {
  state.currentRunId = runId;
  renderRuns();
  if (!options.silent) setProgress("Loading saved run…", 1, true);
  try {
    const status = await apiGet(`/api/runs/${runId}/status`);
    if (status.state !== "done") {
      setProgress(`${status.state}: ${status.message || ""}`, status.progress, true);
      if (status.state === "error") showToast(status.message || "Simulation failed.", true);
      return;
    }
    const summary = await apiGet(`/api/runs/${runId}/summary`);
    if (
      summary.dataset_id
      && summary.dataset_id !== el("datasetSelect").value
      && state.datasetLabels.has(summary.dataset_id)
    ) {
      el("datasetSelect").value = summary.dataset_id;
      await reloadForDataset({ resetClone: false });
    }
    await renderOutputs(runId, summary);
    if (!options.silent) {
      setProgress("Saved run loaded.", 1, true);
      window.setTimeout(() => {
        if (!state.isRunning) el("runProgressWrap").hidden = true;
      }, 1800);
    }
  } catch (error) {
    showToast(String(error), true);
  }
}

function validateRunControls() {
  const controls = [el("TInput"), el("nSimsInput"), el("seedInput")];
  const invalid = controls.find((control) => !control.checkValidity());
  if (invalid) {
    invalid.reportValidity();
    return false;
  }
  return true;
}

async function simulate() {
  if (state.isRunning || !validateRunControls()) return;
  state.isRunning = true;
  activateTab("results");
  el("simulateBtn").disabled = true;
  el("simulateBtnText").textContent = "Running…";
  setProgress("Submitting run to Julia…", 0, true);

  try {
    const datasetId = el("datasetSelect").value;
    const { run_id: runId } = await apiPost("/api/runs", {
      dataset_id: datasetId,
      scenario: el("scenarioSelect").value,
      sim: {
        T: Number(el("TInput").value),
        n_sims: Number(el("nSimsInput").value),
        base_seed: Number(el("seedInput").value),
        step_multithreading: el("mtInput").checked,
      },
      overrides: getOverridesFromForm(),
      shock: copyObject(state.cloneShock, { type: "none" }),
      ...cloneSubmissionFields(state),
    });

    state.currentRunId = runId;
    await refreshRuns();
    for (;;) {
      const status = await apiGet(`/api/runs/${runId}/status`);
      setProgress(status.message || status.state, status.progress, true);
      if (status.state === "done") {
        const summary = await apiGet(`/api/runs/${runId}/summary`);
        let historyRefreshError = null;
        try {
          await refreshRuns();
        } catch (error) {
          historyRefreshError = error;
        }
        await renderOutputs(runId, summary);
        setProgress("Simulation complete.", 1, true);
        showToast(
          historyRefreshError
            ? "Simulation complete. Results are ready, but run history could not refresh."
            : "Simulation complete. Results are ready.",
          Boolean(historyRefreshError),
        );
        break;
      }
      if (status.state === "error") {
        await refreshRuns();
        throw new Error(status.message || "The simulation failed.");
      }
      await new Promise((resolve) => window.setTimeout(resolve, 800));
    }
  } catch (error) {
    setProgress("Simulation failed.", 1, true);
    showToast(String(error), true);
  } finally {
    state.isRunning = false;
    el("simulateBtn").disabled = false;
    el("simulateBtnText").textContent = "Run simulation";
  }
}

async function reloadForDataset({ resetClone = true } = {}) {
  const datasetId = el("datasetSelect").value;
  const dataset = selectedDataset();
  if (!dataset) throw new Error(`Unknown dataset ${datasetId}`);
  if (resetClone) clearCloneInheritance();
  window.localStorage.setItem("beforeit-dataset", datasetId);
  el("datasetContext").textContent = state.datasetLabels.get(datasetId) || datasetId;
  renderScenarioOptions(dataset);
  el("knobsForm").innerHTML = '<div class="history-empty">Loading calibrated parameters…</div>';
  el("inputCatalog").innerHTML = '<div class="history-empty">Loading input catalog…</div>';
  const [knobs, metadata, sectorMetadata] = await Promise.all([
    apiGet(`/api/knobs?dataset_id=${encodeURIComponent(datasetId)}`),
    apiGet(`/api/datasets/metadata?dataset_id=${encodeURIComponent(datasetId)}`),
    apiGet(`/api/datasets/${encodeURIComponent(datasetId)}/sector-metadata`),
  ]);
  const sectors = Array.isArray(sectorMetadata?.sectors) ? sectorMetadata.sectors : [];
  if (sectors.length === 0) {
    throw new Error(`Dataset ${datasetId} has no sector metadata.`);
  }
  state.datasetMetadata = metadata;
  state.sectorMetadata = sectorMetadata;
  state.sectors = sectors;
  renderKnobs(knobs);
  await Promise.all([
    loadInputsSchema(datasetId),
    reloadScenarioContext(),
  ]);
}

function bindEvents() {
  document.querySelectorAll(".info-tip[data-tooltip]").forEach((tip) => {
    tip.title = tip.dataset.tooltip;
  });
  document.querySelectorAll(".tab-button").forEach((button) => {
    button.addEventListener("click", () => activateTab(button.dataset.tab));
    button.addEventListener("keydown", (event) => {
      if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
      event.preventDefault();
      const tabs = [...document.querySelectorAll(".tab-button")];
      const nextIndex = event.key === "ArrowRight"
        ? (tabs.indexOf(button) + 1) % tabs.length
        : (tabs.indexOf(button) - 1 + tabs.length) % tabs.length;
      tabs[nextIndex].focus();
      activateTab(tabs[nextIndex].dataset.tab);
    });
  });
  el("datasetSelect").addEventListener("change", () => reloadForDataset().catch(handleFatalError));
  el("scenarioSelect").addEventListener("change", () => reloadScenarioContext().catch(handleFatalError));
  el("simulateBtn").addEventListener("click", simulate);
  el("refreshRunsBtn").addEventListener("click", () => refreshRuns().catch(handleFatalError));
  el("resetKnobsBtn").addEventListener("click", resetKnobs);
  el("clearInheritedShock").addEventListener("click", () => {
    state.cloneShock = { type: "none" };
    renderCloneContext();
    showToast("The inherited intervention shock was removed; other cloned settings remain.");
  });
  el("reviewResultsBtn").addEventListener("click", () => activateTab("results"));
  el("knobSearch").addEventListener("input", applyKnobFilter);
  el("inputSearch").addEventListener("input", renderInputCatalog);
  el("inputGroupTabs").addEventListener("click", (event) => {
    const button = event.target.closest("[data-group]");
    if (!button) return;
    state.inputGroup = button.dataset.group;
    el("inputGroupTabs").querySelectorAll("[data-group]").forEach((chip) => {
      const active = chip === button;
      chip.classList.toggle("is-active", active);
      chip.setAttribute("aria-selected", String(active));
    });
    state.selectedInput = null;
    renderInputCatalog();
    const first = state.schema[state.inputGroup]?.[0];
    if (first) loadInputValue(state.inputGroup, first.key);
  });
}

function handleFatalError(error) {
  setEngineError(true);
  showToast(String(error), true);
}

async function init() {
  bindEvents();
  state.datasets = await apiGet("/api/datasets");
  state.datasetLabels = new Map(state.datasets.map((dataset) => [dataset.id, dataset.label]));
  const select = el("datasetSelect");
  state.datasets.forEach((dataset) => {
    const option = document.createElement("option");
    option.value = dataset.id;
    option.textContent = dataset.label;
    select.appendChild(option);
  });
  const savedDataset = window.localStorage.getItem("beforeit-dataset");
  if (savedDataset && state.datasetLabels.has(savedDataset)) select.value = savedDataset;

  await reloadForDataset();
  const runs = await refreshRuns();
  const requestedRunId = new URLSearchParams(window.location.search).get("open_run");
  const requestedRun = requestedRunId
    ? runs.find((run) => run.run_id === requestedRunId && run.state === "done")
    : null;
  const runToOpen = requestedRun || runs.find((run) => run.state === "done");
  if (requestedRun && requestedRun.dataset_id !== select.value && state.datasetLabels.has(requestedRun.dataset_id)) {
    select.value = requestedRun.dataset_id;
    await reloadForDataset({ resetClone: false });
  }
  if (requestedRun) {
    const spec = await apiGet(`/api/runs/${encodeURIComponent(requestedRun.run_id)}/spec`);
    await restoreRunSpec(spec, requestedRun);
  }
  if (runToOpen) await loadRun(runToOpen.run_id, { silent: true });
  if (requestedRun) {
    activateTab("inputs");
    showToast(`Cloned settings restored from ${requestedRun.display_name || requestedRun.name || requestedRun.run_id}.`);
  }
  setEngineError(false);
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    cloneInheritanceFromRunSpec,
    cloneSubmissionFields,
    formatMoneyMillions,
    monetaryPresentation,
    runSupportsExplorer,
  };
}

if (typeof document !== "undefined" && typeof window !== "undefined") {
  init().catch(handleFatalError);
}
