# ---------------------------------------------------------------------------
# Smets–Wouters (AER 2007) linearized model, assembled in Sims canonical form
#
#     Gamma0 s_t = Gamma1 s_{t-1} + Psi eps_t + Pi eta_t
#
# for the validated gensys solver in
# `scripts/us/forecasting/benchmarks/small_nk_dsge/USSmallNKDSGEMechanics.jl`.
#
# Equations follow the published replication `Smets_Wouters_2007.mod`
# (Pfeifer DSGE_mod collection, itself validated against the AER article's
# posterior); the flexible-price block is included because the policy rule
# reacts to the model-consistent output gap. Two lag states per growth
# observable make the measurement equations Markov.
#
# All parameters are Float64. Composite steady-state coefficients follow the
# replication file exactly. Fixed (non-estimated) constants: ctou = 0.025,
# clandaw = 1.5, cg = 0.18, curvp = 10, curvw = 10.
# ---------------------------------------------------------------------------

const SW07_STATE_NAMES = [
    # flexible-price block
    "zcapf", "rkf", "kf", "pkf", "cf", "invef", "yf", "labf", "wf", "rrf", "kpf",
    # sticky block
    "mc", "zcap", "rk", "k", "pk", "c", "inve", "y", "lab", "pinf", "w", "r", "kp",
    # exogenous processes
    "a", "b", "g", "qs", "ms", "spinf", "sw",
    # MA(1) auxiliaries for the price/wage markup shocks
    "epinfma", "ewma",
    # one-step-ahead expectation states
    "E_cf", "E_labf", "E_invef", "E_pkf", "E_rkf",
    "E_c", "E_lab", "E_inve", "E_pk", "E_rk", "E_pinf", "E_w",
    # lag states for growth measurement
    "y_lag", "c_lag", "inve_lag", "w_lag",
]

const SW07_SHOCK_NAMES = ["ea", "eb", "eg", "eqs", "em", "epinf", "ew"]

const SW07_EXPECTATION_NAMES = [
    "eta_cf", "eta_labf", "eta_invef", "eta_pkf", "eta_rkf",
    "eta_c", "eta_lab", "eta_inve", "eta_pk", "eta_rk", "eta_pinf", "eta_w",
]

const SW07_OBSERVABLE_NAMES =
    ["dy", "dc", "dinve", "dw", "labobs", "pinfobs", "robs"]

# Estimated parameters, replication order and priors (`estimated_params` block).
# Tuple: (name, sw07_mode_init, lower, upper, prior_kind, prior_a, prior_b).
# For :invgamma1 the pair (a, b) is (s, nu) of the Sims density; (s = 0.056419,
# nu = 2) reproduces the published "inverse gamma, mean 0.1, 2 df" prior.
const SW07_ESTIMATED_PARAMETERS = [
    ("sd_ea", 0.4618, 0.01, 3.0, :invgamma1, 0.056419, 2.0),
    ("sd_eb", 0.1818513, 0.025, 5.0, :invgamma1, 0.056419, 2.0),
    ("sd_eg", 0.609, 0.01, 3.0, :invgamma1, 0.056419, 2.0),
    ("sd_eqs", 0.46017, 0.01, 3.0, :invgamma1, 0.056419, 2.0),
    ("sd_em", 0.2397, 0.01, 3.0, :invgamma1, 0.056419, 2.0),
    ("sd_epinf", 0.1455, 0.01, 3.0, :invgamma1, 0.056419, 2.0),
    ("sd_ew", 0.2089, 0.01, 3.0, :invgamma1, 0.056419, 2.0),
    ("crhoa", 0.9676, 0.01, 0.9999, :beta, 0.5, 0.2),
    ("crhob", 0.2703, 0.01, 0.9999, :beta, 0.5, 0.2),
    ("crhog", 0.993, 0.01, 0.9999, :beta, 0.5, 0.2),
    ("crhoqs", 0.5724, 0.01, 0.9999, :beta, 0.5, 0.2),
    ("crhoms", 0.3, 0.01, 0.9999, :beta, 0.5, 0.2),
    ("crhopinf", 0.8692, 0.01, 0.9999, :beta, 0.5, 0.2),
    ("crhow", 0.9546, 0.001, 0.9999, :beta, 0.5, 0.2),
    ("cmap", 0.7652, 0.01, 0.9999, :beta, 0.5, 0.2),
    ("cmaw", 0.8936, 0.01, 0.9999, :beta, 0.5, 0.2),
    ("csadjcost", 6.3325, 2.0, 15.0, :normal, 4.0, 1.5),
    ("csigma", 1.2312, 0.25, 3.0, :normal, 1.5, 0.375),
    ("chabb", 0.7205, 0.001, 0.99, :beta, 0.7, 0.1),
    ("cprobw", 0.7937, 0.3, 0.95, :beta, 0.5, 0.1),
    ("csigl", 2.8401, 0.25, 10.0, :normal, 2.0, 0.75),
    ("cprobp", 0.7813, 0.5, 0.95, :beta, 0.5, 0.1),
    ("cindw", 0.4425, 0.01, 0.99, :beta, 0.5, 0.15),
    ("cindp", 0.3291, 0.01, 0.99, :beta, 0.5, 0.15),
    ("czcap", 0.2648, 0.01, 1.0, :beta, 0.5, 0.15),
    ("cfc", 1.4672, 1.0, 3.0, :normal, 1.25, 0.125),
    ("crpi", 1.7985, 1.0, 3.0, :normal, 1.5, 0.25),
    ("crr", 0.8258, 0.5, 0.975, :beta, 0.75, 0.1),
    ("cry", 0.0893, 0.001, 0.5, :normal, 0.125, 0.05),
    ("crdy", 0.2239, 0.001, 0.5, :normal, 0.125, 0.05),
    ("constepinf", 0.7, 0.1, 2.0, :gamma, 0.625, 0.1),
    ("constebeta", 0.742, 0.01, 2.0, :gamma, 0.25, 0.1),
    ("constelab", 1.2918, -10.0, 10.0, :normal, 0.0, 2.0),
    ("ctrend", 0.3982, 0.1, 0.8, :normal, 0.4, 0.1),
    ("cgy", 0.05, 0.01, 2.0, :normal, 0.5, 0.25),
    ("calfa", 0.24, 0.01, 1.0, :normal, 0.3, 0.05),
]

const SW07_FIXED = (ctou = 0.025, clandaw = 1.5, cg = 0.18, curvp = 10.0, curvw = 10.0)

sw07_parameter_names() = String[first(row) for row in SW07_ESTIMATED_PARAMETERS]

function sw07_mode_start()
    return Dict{String, Float64}(
        String(row[1]) => Float64(row[2]) for row in SW07_ESTIMATED_PARAMETERS
    )
end

"""
    sw07_canonical(theta) -> (canonical, measurement_loading, measurement_intercept, shock_sd)

Assemble the 49-state canonical system at the parameter dictionary `theta`.
Returns the `CanonicalSystem` for the sealed gensys solver plus the measurement
loading `Z` (7 x 49), intercept `d` (7), and the shock standard deviations in
`SW07_SHOCK_NAMES` order.
"""
function sw07_canonical(theta::Dict{String, Float64})
    n = length(SW07_STATE_NAMES)
    n_shock = length(SW07_SHOCK_NAMES)
    n_eta = length(SW07_EXPECTATION_NAMES)
    index = Dict(name => i for (i, name) in enumerate(SW07_STATE_NAMES))
    shock_index = Dict(name => i for (i, name) in enumerate(SW07_SHOCK_NAMES))
    eta_index = Dict(name => i for (i, name) in enumerate(SW07_EXPECTATION_NAMES))

    G0 = zeros(n, n)
    G1 = zeros(n, n)
    Psi = zeros(n, n_shock)
    Pi = zeros(n, n_eta)

    # fixed constants and composite steady-state coefficients (replication file)
    ctou, clandaw, cg = SW07_FIXED.ctou, SW07_FIXED.clandaw, SW07_FIXED.cg
    curvp, curvw = SW07_FIXED.curvp, SW07_FIXED.curvw
    p = name -> theta[name]
    cpie = 1.0 + p("constepinf") / 100.0
    cgamma = 1.0 + p("ctrend") / 100.0
    cbeta = 1.0 / (1.0 + p("constebeta") / 100.0)
    csigma = p("csigma")
    calfa = p("calfa")
    cfc = p("cfc")
    clandap = cfc
    cbetabar = cbeta * cgamma^(-csigma)
    cr = cpie / (cbeta * cgamma^(-csigma))
    crk = (cbeta^-1.0) * (cgamma^csigma) - (1.0 - ctou)
    cw = (calfa^calfa * (1.0 - calfa)^(1.0 - calfa) / (clandap * crk^calfa))^(1.0 / (1.0 - calfa))
    cikbar = 1.0 - (1.0 - ctou) / cgamma
    cik = cikbar * cgamma
    clk = ((1.0 - calfa) / calfa) * (crk / cw)
    cky = cfc * clk^(calfa - 1.0)
    ciy = cik * cky
    ccy = 1.0 - cg - cik * cky
    crkky = crk * cky
    cwhlc = (1.0 / clandaw) * (1.0 - calfa) / calfa * crk * cky / ccy
    conster = (cr - 1.0) * 100.0

    chabb = p("chabb")
    csadjcost = p("csadjcost")
    czcap = p("czcap")
    csigl = p("csigl")
    cprobp, cprobw = p("cprobp"), p("cprobw")
    cindp, cindw = p("cindp"), p("cindw")
    crpi, crr, cry, crdy = p("crpi"), p("crr"), p("cry"), p("crdy")
    crhoa, crhob, crhog = p("crhoa"), p("crhob"), p("crhog")
    crhoqs, crhoms, crhopinf, crhow = p("crhoqs"), p("crhoms"), p("crhopinf"), p("crhow")
    cmap, cmaw, cgy = p("cmap"), p("cmaw"), p("cgy")

    habit = chabb / cgamma
    inv_denominator = 1.0 + cbetabar * cgamma
    consumption_lag = habit / (1.0 + habit)
    consumption_lead = 1.0 / (1.0 + habit)
    consumption_lab = (csigma - 1.0) * cwhlc / (csigma * (1.0 + habit))
    consumption_rate = (1.0 - habit) / (csigma * (1.0 + habit))
    pk_b_coefficient = 1.0 / consumption_rate
    rk_share = crk / (crk + 1.0 - ctou)
    pk_share = (1.0 - ctou) / (crk + 1.0 - ctou)

    equation = 0
    set = (M, eq, name, value) -> (M[eq, index[name]] += value)
    setshock = (eq, name, value) -> (Psi[eq, shock_index[name]] += value)
    seteta = (eq, name, value) -> (Pi[eq, eta_index[name]] += value)

    # ---------------- flexible-price economy ----------------
    # F1  a = calfa*rkf + (1-calfa)*wf
    equation += 1
    set(G0, equation, "rkf", calfa); set(G0, equation, "wf", 1.0 - calfa)
    set(G0, equation, "a", -1.0)
    # F2  zcapf = ((1-czcap)/czcap) * rkf
    equation += 1
    set(G0, equation, "zcapf", 1.0); set(G0, equation, "rkf", -(1.0 - czcap) / czcap)
    # F3  rkf = wf + labf - kf
    equation += 1
    set(G0, equation, "rkf", 1.0); set(G0, equation, "wf", -1.0)
    set(G0, equation, "labf", -1.0); set(G0, equation, "kf", 1.0)
    # F4  kf = kpf(-1) + zcapf
    equation += 1
    set(G0, equation, "kf", 1.0); set(G0, equation, "zcapf", -1.0)
    set(G1, equation, "kpf", 1.0)
    # F5  invef = (1/(1+bg))*( invef(-1) + bg*E[invef+1] + (1/(g^2 phi))*pkf ) + qs
    equation += 1
    set(G0, equation, "invef", 1.0)
    set(G0, equation, "E_invef", -cbetabar * cgamma / inv_denominator)
    set(G0, equation, "pkf", -(1.0 / (cgamma^2 * csadjcost)) / inv_denominator)
    set(G0, equation, "qs", -1.0)
    set(G1, equation, "invef", 1.0 / inv_denominator)
    # F6  pkf = -rrf + pk_b*b + rk_share*E[rkf+1] + pk_share*E[pkf+1]
    equation += 1
    set(G0, equation, "pkf", 1.0); set(G0, equation, "rrf", 1.0)
    set(G0, equation, "b", -pk_b_coefficient)
    set(G0, equation, "E_rkf", -rk_share); set(G0, equation, "E_pkf", -pk_share)
    # F7  cf = lag*cf(-1) + lead*E[cf+1] + lab*(labf - E[labf+1]) - rate*rrf + b
    equation += 1
    set(G0, equation, "cf", 1.0)
    set(G0, equation, "E_cf", -consumption_lead)
    set(G0, equation, "labf", -consumption_lab)
    set(G0, equation, "E_labf", consumption_lab)
    set(G0, equation, "rrf", consumption_rate)
    set(G0, equation, "b", -1.0)
    set(G1, equation, "cf", consumption_lag)
    # F8  yf = ccy*cf + ciy*invef + g + crkky*zcapf
    equation += 1
    set(G0, equation, "yf", 1.0); set(G0, equation, "cf", -ccy)
    set(G0, equation, "invef", -ciy); set(G0, equation, "g", -1.0)
    set(G0, equation, "zcapf", -crkky)
    # F9  yf = cfc*( calfa*kf + (1-calfa)*labf + a )
    equation += 1
    set(G0, equation, "yf", 1.0); set(G0, equation, "kf", -cfc * calfa)
    set(G0, equation, "labf", -cfc * (1.0 - calfa)); set(G0, equation, "a", -cfc)
    # F10 wf = csigl*labf + (1/(1-habit))*cf - (habit/(1-habit))*cf(-1)
    equation += 1
    set(G0, equation, "wf", 1.0); set(G0, equation, "labf", -csigl)
    set(G0, equation, "cf", -1.0 / (1.0 - habit))
    set(G1, equation, "cf", -habit / (1.0 - habit))
    # F11 kpf = (1-cikbar)*kpf(-1) + cikbar*invef + cikbar*g^2*phi*qs
    equation += 1
    set(G0, equation, "kpf", 1.0); set(G0, equation, "invef", -cikbar)
    set(G0, equation, "qs", -cikbar * cgamma^2 * csadjcost)
    set(G1, equation, "kpf", 1.0 - cikbar)

    # ---------------- sticky price-wage economy ----------------
    # S1  mc = calfa*rk + (1-calfa)*w - a
    equation += 1
    set(G0, equation, "mc", 1.0); set(G0, equation, "rk", -calfa)
    set(G0, equation, "w", -(1.0 - calfa)); set(G0, equation, "a", 1.0)
    # S2  zcap = ((1-czcap)/czcap) * rk
    equation += 1
    set(G0, equation, "zcap", 1.0); set(G0, equation, "rk", -(1.0 - czcap) / czcap)
    # S3  rk = w + lab - k
    equation += 1
    set(G0, equation, "rk", 1.0); set(G0, equation, "w", -1.0)
    set(G0, equation, "lab", -1.0); set(G0, equation, "k", 1.0)
    # S4  k = kp(-1) + zcap
    equation += 1
    set(G0, equation, "k", 1.0); set(G0, equation, "zcap", -1.0)
    set(G1, equation, "kp", 1.0)
    # S5  inve
    equation += 1
    set(G0, equation, "inve", 1.0)
    set(G0, equation, "E_inve", -cbetabar * cgamma / inv_denominator)
    set(G0, equation, "pk", -(1.0 / (cgamma^2 * csadjcost)) / inv_denominator)
    set(G0, equation, "qs", -1.0)
    set(G1, equation, "inve", 1.0 / inv_denominator)
    # S6  pk = -r + E[pinf+1] + pk_b*b + rk_share*E[rk+1] + pk_share*E[pk+1]
    equation += 1
    set(G0, equation, "pk", 1.0); set(G0, equation, "r", 1.0)
    set(G0, equation, "E_pinf", -1.0)
    set(G0, equation, "b", -pk_b_coefficient)
    set(G0, equation, "E_rk", -rk_share); set(G0, equation, "E_pk", -pk_share)
    # S7  c = lag*c(-1) + lead*E[c+1] + lab*(lab - E[lab+1]) - rate*(r - E[pinf+1]) + b
    equation += 1
    set(G0, equation, "c", 1.0)
    set(G0, equation, "E_c", -consumption_lead)
    set(G0, equation, "lab", -consumption_lab)
    set(G0, equation, "E_lab", consumption_lab)
    set(G0, equation, "r", consumption_rate)
    set(G0, equation, "E_pinf", -consumption_rate)
    set(G0, equation, "b", -1.0)
    set(G1, equation, "c", consumption_lag)
    # S8  y = ccy*c + ciy*inve + g + crkky*zcap
    equation += 1
    set(G0, equation, "y", 1.0); set(G0, equation, "c", -ccy)
    set(G0, equation, "inve", -ciy); set(G0, equation, "g", -1.0)
    set(G0, equation, "zcap", -crkky)
    # S9  y = cfc*( calfa*k + (1-calfa)*lab + a )
    equation += 1
    set(G0, equation, "y", 1.0); set(G0, equation, "k", -cfc * calfa)
    set(G0, equation, "lab", -cfc * (1.0 - calfa)); set(G0, equation, "a", -cfc)
    # S10 pinf Phillips curve
    equation += 1
    pinf_denominator = 1.0 + cbetabar * cgamma * cindp
    slope = ((1.0 - cprobp) * (1.0 - cbetabar * cgamma * cprobp) / cprobp) /
        ((cfc - 1.0) * curvp + 1.0)
    set(G0, equation, "pinf", 1.0)
    set(G0, equation, "E_pinf", -cbetabar * cgamma / pinf_denominator)
    set(G0, equation, "mc", -slope / pinf_denominator)
    set(G0, equation, "spinf", -1.0)
    set(G1, equation, "pinf", cindp / pinf_denominator)
    # S11 wage Phillips curve
    equation += 1
    wage_slope = (1.0 - cprobw) * (1.0 - cbetabar * cgamma * cprobw) /
        ((1.0 + cbetabar * cgamma) * cprobw) / ((clandaw - 1.0) * curvw + 1.0)
    set(G0, equation, "w", 1.0 + wage_slope)
    set(G0, equation, "E_w", -cbetabar * cgamma / inv_denominator)
    set(G0, equation, "pinf", (1.0 + cbetabar * cgamma * cindw) / inv_denominator)
    set(G0, equation, "E_pinf", -cbetabar * cgamma / inv_denominator)
    set(G0, equation, "lab", -wage_slope * csigl)
    set(G0, equation, "c", -wage_slope / (1.0 - habit))
    set(G0, equation, "sw", -1.0)
    set(G1, equation, "w", 1.0 / inv_denominator)
    set(G1, equation, "pinf", cindw / inv_denominator)
    set(G1, equation, "c", -wage_slope * habit / (1.0 - habit))
    # S12 Taylor rule:
    # r = crpi(1-crr)pinf + cry(1-crr)(y-yf) + crdy((y-yf)-(y(-1)-yf(-1))) + crr r(-1) + ms
    equation += 1
    set(G0, equation, "r", 1.0)
    set(G0, equation, "pinf", -crpi * (1.0 - crr))
    set(G0, equation, "y", -(cry * (1.0 - crr) + crdy))
    set(G0, equation, "yf", cry * (1.0 - crr) + crdy)
    set(G0, equation, "ms", -1.0)
    set(G1, equation, "r", crr)
    set(G1, equation, "y", -crdy)
    set(G1, equation, "yf", crdy)
    # S13 kp
    equation += 1
    set(G0, equation, "kp", 1.0); set(G0, equation, "inve", -cikbar)
    set(G0, equation, "qs", -cikbar * cgamma^2 * csadjcost)
    set(G1, equation, "kp", 1.0 - cikbar)

    # ---------------- exogenous processes ----------------
    # a = crhoa a(-1) + ea
    equation += 1
    set(G0, equation, "a", 1.0); set(G1, equation, "a", crhoa)
    setshock(equation, "ea", 1.0)
    # b = crhob b(-1) + eb
    equation += 1
    set(G0, equation, "b", 1.0); set(G1, equation, "b", crhob)
    setshock(equation, "eb", 1.0)
    # g = crhog g(-1) + eg + cgy ea
    equation += 1
    set(G0, equation, "g", 1.0); set(G1, equation, "g", crhog)
    setshock(equation, "eg", 1.0); setshock(equation, "ea", cgy)
    # qs = crhoqs qs(-1) + eqs
    equation += 1
    set(G0, equation, "qs", 1.0); set(G1, equation, "qs", crhoqs)
    setshock(equation, "eqs", 1.0)
    # ms = crhoms ms(-1) + em
    equation += 1
    set(G0, equation, "ms", 1.0); set(G1, equation, "ms", crhoms)
    setshock(equation, "em", 1.0)
    # spinf = crhopinf spinf(-1) + epinfma - cmap epinfma(-1)
    equation += 1
    set(G0, equation, "spinf", 1.0); set(G0, equation, "epinfma", -1.0)
    set(G1, equation, "spinf", crhopinf); set(G1, equation, "epinfma", -cmap)
    # epinfma = epinf
    equation += 1
    set(G0, equation, "epinfma", 1.0)
    setshock(equation, "epinf", 1.0)
    # sw = crhow sw(-1) + ewma - cmaw ewma(-1)
    equation += 1
    set(G0, equation, "sw", 1.0); set(G0, equation, "ewma", -1.0)
    set(G1, equation, "sw", crhow); set(G1, equation, "ewma", -cmaw)
    # ewma = ew
    equation += 1
    set(G0, equation, "ewma", 1.0)
    setshock(equation, "ew", 1.0)

    # ---------------- expectational identities ----------------
    # x_t = E_{t-1}[x_t] + eta_x_t  for each forward-looking variable x
    for (variable, expectation, eta) in (
            ("cf", "E_cf", "eta_cf"), ("labf", "E_labf", "eta_labf"),
            ("invef", "E_invef", "eta_invef"), ("pkf", "E_pkf", "eta_pkf"),
            ("rkf", "E_rkf", "eta_rkf"),
            ("c", "E_c", "eta_c"), ("lab", "E_lab", "eta_lab"),
            ("inve", "E_inve", "eta_inve"), ("pk", "E_pk", "eta_pk"),
            ("rk", "E_rk", "eta_rk"), ("pinf", "E_pinf", "eta_pinf"),
            ("w", "E_w", "eta_w"),
        )
        equation += 1
        set(G0, equation, variable, 1.0)
        set(G1, equation, expectation, 1.0)
        seteta(equation, eta, 1.0)
    end

    # ---------------- lag identities ----------------
    for (lag_state, source) in (
            ("y_lag", "y"), ("c_lag", "c"), ("inve_lag", "inve"), ("w_lag", "w"),
        )
        equation += 1
        set(G0, equation, lag_state, 1.0)
        set(G1, equation, source, 1.0)
    end

    equation == n || error("SW07 assembly produced $equation equations for $n states")

    # ---------------- measurement ----------------
    Z = zeros(length(SW07_OBSERVABLE_NAMES), n)
    d = zeros(length(SW07_OBSERVABLE_NAMES))
    ctrend = p("ctrend")
    for (row, (level, lag)) in enumerate(
            (("y", "y_lag"), ("c", "c_lag"), ("inve", "inve_lag"), ("w", "w_lag")),
        )
        Z[row, index[level]] = 1.0
        Z[row, index[lag]] = -1.0
        d[row] = ctrend
    end
    Z[5, index["lab"]] = 1.0
    d[5] = p("constelab")
    Z[6, index["pinf"]] = 1.0
    d[6] = p("constepinf")
    Z[7, index["r"]] = 1.0
    d[7] = conster

    shock_sd = [
        p("sd_ea"), p("sd_eb"), p("sd_eg"), p("sd_eqs"),
        p("sd_em"), p("sd_epinf"), p("sd_ew"),
    ]
    return (
        gamma0 = G0, gamma1 = G1, constant = zeros(n),
        shock_loading = Psi, expectational_loading = Pi,
        measurement_loading = Z, measurement_intercept = d,
        shock_sd = shock_sd,
    )
end
