abstract type AbstractProperties <: AbstractObject end

const OPENING_MACRO_CONTROL_UNIT =
    "millions_current_currency_per_model_quarter"

const OPENING_MACRO_NUMERIC_KEYS = (
    "opening_nominal_gdp",
    "opening_nominal_household_consumption",
    "opening_nominal_government_consumption_and_investment",
    "opening_nominal_capitalformation",
    "opening_nominal_fixed_capitalformation",
    "opening_nominal_inventory_investment",
    "opening_nominal_fixed_capitalformation_dwellings",
    "opening_nominal_exports",
    "opening_nominal_imports",
)

"""
    validated_opening_macro_controls(initial_conditions)

Read an explicitly opted-in, current-price opening observation from an
initial-condition dictionary. The opening row is a measured origin-quarter
flow record, not an inferred inventory stock or a balancing plug. Gross
private domestic investment must reconcile to fixed investment plus signed
inventory investment, and the expenditure-side GDP identity must pass the
declared source-rounding tolerance.

Artifacts without `use_opening_macro_controls = true` retain the original
model-implied opening-row behavior and return `nothing`.
"""
function validated_opening_macro_controls(initial_conditions)
    enabled = get(initial_conditions, "use_opening_macro_controls", false)
    enabled isa Bool ||
        throw(
        ArgumentError(
            "initial_conditions[\"use_opening_macro_controls\"] must be boolean",
        ),
    )
    enabled || return nothing

    source = get(initial_conditions, "opening_macro_control_source", nothing)
    source isa AbstractString && !isempty(strip(source)) ||
        throw(ArgumentError("opening macro controls require a nonempty source"))
    unit = get(initial_conditions, "opening_macro_control_unit", nothing)
    unit == OPENING_MACRO_CONTROL_UNIT ||
        throw(
        ArgumentError(
            "opening macro controls must use $OPENING_MACRO_CONTROL_UNIT",
        ),
    )
    tolerance_value = get(
        initial_conditions,
        "opening_macro_control_absolute_tolerance",
        nothing,
    )
    tolerance_value isa Real ||
        throw(ArgumentError("opening macro controls require a numeric tolerance"))
    tolerance = Float64(tolerance_value)
    isfinite(tolerance) && tolerance >= 0 ||
        throw(
        ArgumentError(
            "opening macro control tolerance must be finite and nonnegative",
        ),
    )

    values = Dict{String, Float64}()
    for key in OPENING_MACRO_NUMERIC_KEYS
        haskey(initial_conditions, key) ||
            throw(ArgumentError("opening macro controls are missing $key"))
        value = initial_conditions[key]
        value isa Real ||
            throw(ArgumentError("opening macro control $key must be numeric"))
        numeric = Float64(value)
        isfinite(numeric) ||
            throw(ArgumentError("opening macro control $key must be finite"))
        values[key] = numeric
    end

    for key in (
            "opening_nominal_gdp",
            "opening_nominal_household_consumption",
            "opening_nominal_government_consumption_and_investment",
            "opening_nominal_capitalformation",
            "opening_nominal_fixed_capitalformation",
            "opening_nominal_exports",
            "opening_nominal_imports",
        )
        values[key] > 0 ||
            throw(ArgumentError("opening macro control $key must be positive"))
    end
    dwellings = values["opening_nominal_fixed_capitalformation_dwellings"]
    dwellings >= 0 ||
        throw(
        ArgumentError(
            "opening dwelling investment control cannot be negative",
        ),
    )
    dwellings <=
        values["opening_nominal_fixed_capitalformation"] + tolerance ||
        throw(
        ArgumentError(
            "opening dwelling investment exceeds total fixed investment",
        ),
    )

    investment_residual =
        values["opening_nominal_capitalformation"] -
        values["opening_nominal_fixed_capitalformation"] -
        values["opening_nominal_inventory_investment"]
    abs(investment_residual) <= tolerance ||
        throw(
        ArgumentError(
            "opening gross private domestic investment does not reconcile " *
                "to fixed investment plus signed inventory investment",
        ),
    )
    expenditure_residual =
        values["opening_nominal_gdp"] -
        values["opening_nominal_household_consumption"] -
        values["opening_nominal_government_consumption_and_investment"] -
        values["opening_nominal_capitalformation"] -
        values["opening_nominal_exports"] +
        values["opening_nominal_imports"]
    abs(expenditure_residual) <= tolerance ||
        throw(
        ArgumentError(
            "opening macro controls do not satisfy the current-price " *
                "expenditure identity",
        ),
    )

    return (
        source = String(source),
        unit = String(unit),
        tolerance,
        nominal_gdp = values["opening_nominal_gdp"],
        nominal_household_consumption =
            values["opening_nominal_household_consumption"],
        nominal_government_consumption_and_investment =
            values[
            "opening_nominal_government_consumption_and_investment",
        ],
        nominal_capitalformation =
            values["opening_nominal_capitalformation"],
        nominal_fixed_capitalformation =
            values["opening_nominal_fixed_capitalformation"],
        nominal_inventory_investment =
            values["opening_nominal_inventory_investment"],
        nominal_fixed_capitalformation_dwellings = dwellings,
        nominal_exports = values["opening_nominal_exports"],
        nominal_imports = values["opening_nominal_imports"],
        investment_residual,
        expenditure_residual,
    )
end

Bit.@object mutable struct Properties(Object) <: AbstractProperties
    G::Bit.typeInt
    T_prime::Bit.typeInt
    H_act::Bit.typeInt
    H_inact::Bit.typeInt
    J::Bit.typeInt
    L::Bit.typeInt
    I_s::Vector{Bit.typeInt}
    I::Bit.typeInt
    H::Bit.typeInt
    tau_INC::Bit.typeFloat
    tau_FIRM::Bit.typeFloat
    tau_VAT::Bit.typeFloat
    tau_SIF::Bit.typeFloat
    tau_SIW::Bit.typeFloat
    tau_EXPORT::Bit.typeFloat
    tau_CF::Bit.typeFloat
    tau_G::Bit.typeFloat
    theta_UB::Bit.typeFloat
    psi::Bit.typeFloat
    psi_H::Bit.typeFloat
    mu::Bit.typeFloat
    theta_DIV::Bit.typeFloat
    theta::Bit.typeFloat
    zeta::Bit.typeFloat
    zeta_LTV::Bit.typeFloat
    zeta_b::Bit.typeFloat
    b_CF_g::Vector{Bit.typeFloat}
    b_CFH_g::Vector{Bit.typeFloat}
    b_HH_g::Vector{Bit.typeFloat}
    c_G_g::Vector{Bit.typeFloat}
    c_E_g::Vector{Bit.typeFloat}
    c_I_g::Vector{Bit.typeFloat}
    a_sg::Matrix{Bit.typeFloat}
    C::Matrix{Bit.typeFloat}
    D_H::Bit.typeFloat
    K_H::Bit.typeFloat
    sb_other::Bit.typeFloat
    E_k::Bit.typeFloat
    r_bar::Bit.typeFloat
    use_opening_macro_controls::Bool
    opening_nominal_gdp::Bit.typeFloat
    opening_nominal_household_consumption::Bit.typeFloat
    opening_nominal_government_consumption_and_investment::Bit.typeFloat
    opening_nominal_capitalformation::Bit.typeFloat
    opening_nominal_fixed_capitalformation::Bit.typeFloat
    opening_nominal_inventory_investment::Bit.typeFloat
    opening_nominal_fixed_capitalformation_dwellings::Bit.typeFloat
    opening_nominal_exports::Bit.typeFloat
    opening_nominal_imports::Bit.typeFloat
    expectation_rw_drift::Bool
    trend_growth_rate::Bit.typeFloat
    investment_accelerator_nu::Bit.typeFloat
    normal_utilization::Bit.typeFloat
    trend_capital_deepening::Bit.typeFloat
    trend_capacity_efficiency::Bit.typeFloat
end

function Properties(parameters::Dict{String, Any}, initial_conditions)

    G = typeInt(parameters["G"])
    T_prime = typeInt(parameters["T_prime"])       # Time interval used to estimate parameters for expectations

    H_act = typeInt(parameters["H_act"])    # Number of economically active persons
    H_inact = typeInt(parameters["H_inact"])  # Number of economically inactive persons
    # H = I + H_W + H_inact + 1

    J = typeInt(parameters["J"])       # Number of government entities
    L = typeInt(parameters["L"])        # Number of foreign consumers
    I_s = Vector{typeInt}(vec(parameters["I_s"]))           # Number of firms/investors in the s-th industry
    I = typeInt(sum(parameters["I_s"]))        # Number of firms
    H = H_act + H_inact # Total number of households

    tau_INC = typeFloat(parameters["tau_INC"])    # Income tax rate
    tau_FIRM = typeFloat(parameters["tau_FIRM"])   # Corporate tax rate
    tau_VAT = typeFloat(parameters["tau_VAT"])    # Value-added tax rate
    tau_SIF = typeFloat(parameters["tau_SIF"])    # Social insurance rate (employers’ contributions)
    tau_SIW = typeFloat(parameters["tau_SIW"])    # Social insurance rate (employees’ contributions)
    tau_EXPORT = typeFloat(parameters["tau_EXPORT"]) # Export tax rate
    tau_CF = typeFloat(parameters["tau_CF"])     # Tax rate on capital formation
    tau_G = typeFloat(parameters["tau_G"])      # Tax rate on government consumption
    theta_UB = typeFloat(parameters["theta_UB"])   # Unemployment benefit replacement rate
    psi = typeFloat(parameters["psi"])        # Fraction of income devoted to consumption
    psi_H = typeFloat(parameters["psi_H"])      # Fraction of income devoted to investment in housing
    mu = typeFloat(parameters["mu"])         # Risk premium on policy rate

    # banking related parameters
    theta_DIV = typeFloat(parameters["theta_DIV"])  # Dividend payout ratio
    theta = typeFloat(parameters["theta"])      # Rate of installment on debt
    zeta = typeFloat(parameters["zeta"])       # Banks’ capital requirement coefficient
    zeta_LTV = typeFloat(parameters["zeta_LTV"])   # Loan-to-value (LTV) ratio
    zeta_b = typeFloat(parameters["zeta_b"])     # Loan-to-capital ratio for new firms after bankruptcy

    # products related parameters
    b_CF_g = Vector{typeFloat}(vec(parameters["b_CF_g"]))   # Capital formation coefficient g-th product (firm investment)
    b_CFH_g = Vector{typeFloat}(vec(parameters["b_CFH_g"])) # Household investment coefficient of the g-th product
    b_HH_g = Vector{typeFloat}(vec(parameters["b_HH_g"]))   # Consumption coefficient g-th product of households
    c_G_g = Vector{typeFloat}(vec(parameters["c_G_g"]))     # Consumption of the g-th product of the government in mln. Euro
    c_E_g = Vector{typeFloat}(vec(parameters["c_E_g"]))     # Exports of the g-th product in mln. Euro
    c_I_g = Vector{typeFloat}(vec(parameters["c_I_g"]))     # Imports of the gth product in mln. Euro
    a_sg = Matrix{typeFloat}(parameters["a_sg"])            # Technology coefficient of the gth product in the sth industry

    C = Matrix{typeFloat}(parameters["C"])

    D_H = typeFloat(initial_conditions["D_H"])
    K_H = typeFloat(initial_conditions["K_H"])
    sb_other = typeFloat(initial_conditions["sb_other"])
    E_k = typeFloat(initial_conditions["E_k"])
    r_bar = typeFloat(initial_conditions["r_bar"])

    opening_controls =
        validated_opening_macro_controls(initial_conditions)
    use_opening_macro_controls = opening_controls !== nothing
    opening_nominal_gdp =
        typeFloat(use_opening_macro_controls ? opening_controls.nominal_gdp : 0)
    opening_nominal_household_consumption = typeFloat(
        use_opening_macro_controls ?
            opening_controls.nominal_household_consumption : 0,
    )
    opening_nominal_government_consumption_and_investment = typeFloat(
        use_opening_macro_controls ?
            opening_controls.nominal_government_consumption_and_investment :
            0,
    )
    opening_nominal_capitalformation = typeFloat(
        use_opening_macro_controls ?
            opening_controls.nominal_capitalformation : 0,
    )
    opening_nominal_fixed_capitalformation = typeFloat(
        use_opening_macro_controls ?
            opening_controls.nominal_fixed_capitalformation : 0,
    )
    opening_nominal_inventory_investment = typeFloat(
        use_opening_macro_controls ?
            opening_controls.nominal_inventory_investment : 0,
    )
    opening_nominal_fixed_capitalformation_dwellings = typeFloat(
        use_opening_macro_controls ?
            opening_controls.nominal_fixed_capitalformation_dwellings : 0,
    )
    opening_nominal_exports = typeFloat(
        use_opening_macro_controls ? opening_controls.nominal_exports : 0,
    )
    opening_nominal_imports = typeFloat(
        use_opening_macro_controls ? opening_controls.nominal_imports : 0,
    )

    # Growth-expectation specification.  `false` reproduces the legacy log-level AR(1)
    # exactly, so calibrations that do not register the parameter are unaffected.
    expectation_rw_drift = Bool(get(parameters, "expectation_rw_drift", false))

    # Balanced-growth repair (US stage 2b). Defaults reproduce the frozen
    # no-growth economy exactly; calibrations that do not register the
    # parameters are unaffected. `trend_growth_rate` is the quarterly trend
    # growth of output per modeled worker (labour productivity plus labour
    # force growth, estimated from observed series through the forecast
    # origin, never from forecast errors). `investment_accelerator_nu` is the
    # per-quarter closure rate of the capacity gap in desired investment;
    # `normal_utilization` is the calibration's normal-utilization convention
    # (omega), the same constant used to back out kappa_s at initialization.
    trend_growth_rate = typeFloat(get(parameters, "trend_growth_rate", 0.0))
    investment_accelerator_nu =
        typeFloat(get(parameters, "investment_accelerator_nu", 0.0))
    normal_utilization = typeFloat(get(parameters, "normal_utilization", 0.85))
    # When positive, desired investment becomes the printed-paper A.17 form
    # (replacement scaled by desired, uncapped output) plus the balanced-growth
    # net-investment flow `g * K_i`, so `net I = Delta K = g K` holds by
    # construction on the balanced path.
    trend_capital_deepening =
        typeFloat(get(parameters, "trend_capital_deepening", 0.0))
    # When positive, capital productivity `kappa_i` and the depreciation
    # coefficient `delta_i` grow at this quarterly rate alongside labour
    # productivity: capacity per unit of book capital tracks trend
    # (efficiency-units growth) while the replacement share `delta/kappa`
    # and CFC/output stay exactly stable. No demand flow is injected.
    trend_capacity_efficiency =
        typeFloat(get(parameters, "trend_capacity_efficiency", 0.0))

    return Properties(
        G, T_prime, H_act, H_inact, J, L, I_s, I, H, tau_INC, tau_FIRM, tau_VAT, tau_SIF,
        tau_SIW, tau_EXPORT, tau_CF, tau_G, theta_UB, psi, psi_H, mu, theta_DIV, theta, zeta, zeta_LTV,
        zeta_b, b_CF_g, b_CFH_g, b_HH_g, c_G_g, c_E_g, c_I_g, a_sg, C, D_H, K_H, sb_other, E_k, r_bar,
        use_opening_macro_controls, opening_nominal_gdp, opening_nominal_household_consumption,
        opening_nominal_government_consumption_and_investment, opening_nominal_capitalformation,
        opening_nominal_fixed_capitalformation, opening_nominal_inventory_investment,
        opening_nominal_fixed_capitalformation_dwellings, opening_nominal_exports,
        opening_nominal_imports, expectation_rw_drift, trend_growth_rate,
        investment_accelerator_nu, normal_utilization, trend_capital_deepening,
        trend_capacity_efficiency
    )
end
