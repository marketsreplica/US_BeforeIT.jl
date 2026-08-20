# =====================================================================================
# Commodity-balance reconciliation for a structural-vintage U.S. calibration artifact
# (stage-2b workstream 2b-4).
#
# This is the METHOD of scripts/us/calibration/reconcile_commodity_balance.jl applied
# unchanged to a CLI-selected source artifact, so the 2017/2012 structures are
# "carried through the identical reconciliation" (STAGE2B_PROTOCOL.md). Every formula,
# tolerance, mode and default matches that script; the only changes are
#   * --src=PATH is required (the 2024 script hardcodes its source),
#   * --out/--report-dir default to vintage-specific NEW paths,
#   * lambda, rho and the residual decomposition are also written to a provenance TOML
#     beside the reconciled artifact.
#
#   julia --project=scripts/us scripts/us/calibration/structural_vintage/reconcile_structural_vintage.jl \
#       --src=data/us/calibration/US_2017_calibration_object.jld2
#
# Defaults: mode=final_demand_scaled ("VR1", rho forced to 1, the four final-demand
# budgets scaled by one lambda fixed by the accounting identity alone) and
# expectations=rw_drift — exactly the configuration of the shipped
# US_2024_calibration_object_reconciled.jld2. No constant anywhere is chosen with
# reference to a forecast error.
# =====================================================================================
using JLD2, Dates, Printf, Statistics, LinearAlgebra, SHA, TOML
import BeforeIT as Bit

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))

function cli_option(name::AbstractString, default)
    prefix = "--" * name * "="
    for argument in ARGS
        startswith(argument, prefix) && return argument[(length(prefix) + 1):end]
    end
    return default
end

const SRC_JLD2 = abspath(String(cli_option("src", "")))
isempty(cli_option("src", "")) && error("Pass --src=<calibration artifact .jld2>")
isfile(SRC_JLD2) || error("Source artifact not found: $SRC_JLD2")

const MODE_NAME = cli_option("mode", "final_demand_scaled")
MODE_NAME in ("supply_proportional", "final_demand_scaled") ||
    error("--mode must be supply_proportional or final_demand_scaled; got $(repr(MODE_NAME))")
const MODE = Symbol(MODE_NAME)
const TAG = MODE === :final_demand_scaled ? "_rho1" : ""

const EXPECTATIONS = cli_option("expectations", "rw_drift")
EXPECTATIONS in ("legacy_ar1_log_level", "rw_drift") ||
    error("--expectations must be legacy_ar1_log_level or rw_drift; got $(repr(EXPECTATIONS))")

const OUT_JLD2 = abspath(
    cli_option("out", replace(SRC_JLD2, ".jld2" => "_reconciled.jld2")),
)
OUT_JLD2 == SRC_JLD2 && error("--out must differ from --src")
isfile(OUT_JLD2) && error("Refusing to overwrite an existing artifact: $OUT_JLD2")
const STEM = replace(basename(SRC_JLD2), ".jld2" => "")
const REPORT_DIRECTORY = abspath(
    cli_option(
        "report-dir",
        joinpath(
            REPOSITORY_ROOT, "output", "us_forecasting",
            "commodity_balance_reconciliation_structural_vintage", STEM,
        ),
    ),
)
mkpath(REPORT_DIRECTORY)
const REPORT = joinpath(REPORT_DIRECTORY, "reconciliation_report$(TAG).txt")

# BEA summary commodity codes in MODEL ROW ORDER (labels only; the index is the
# authoritative identifier everywhere). Identical list to
# scripts/us/calibration/reconcile_commodity_balance.jl.
const CODES = [
    "111CA", "113FF", "211", "212", "213", "22", "23", "311FT", "313TT", "315AL",
    "321", "322", "323", "324", "325", "326", "327", "331", "332", "333",
    "334", "335", "3361MV", "3364OT", "337", "339", "42", "481", "482", "483",
    "484", "485", "486", "487OS", "493", "4A0", "511", "512", "513", "514",
    "521CI", "523", "524", "525", "532RL", "5411", "5412OP", "5415", "55", "561",
    "562", "61", "621", "622", "623", "624", "711AS", "713", "721", "722",
    "81", "GFE", "GFGD", "GFGN", "GSLE", "GSLG", "HS", "ORE",
]

# -------------------------------------------------------------------------------------
# Replicate `get_params_and_initial_conditions`' commodity-flow construction exactly.
# (Verbatim from reconcile_commodity_balance.jl.)
# -------------------------------------------------------------------------------------
function bridged_flows(figaro, calibration; T_cal = 1)
    G = size(figaro["intermediate_consumption"], 1)

    ic_raw = Matrix{Float64}(figaro["intermediate_consumption"][:, :, T_cal])
    hh_raw = vec(figaro["household_consumption"][:, T_cal])
    cf_raw = vec(figaro["fixed_capitalformation"][:, T_cal])
    ex_raw = vec(figaro["exports"][:, T_cal])
    gc_raw = vec(figaro["government_consumption"][:, T_cal])
    comp = vec(figaro["compensation_employees"][:, T_cal])
    os = vec(figaro["operating_surplus"][:, T_cal])
    txprod = vec(figaro["taxes_production"][:, T_cal])
    txp_hh = figaro["taxes_products_household"][T_cal]
    txp_cf = figaro["taxes_products_capitalformation"][T_cal]
    txp_g = figaro["taxes_products_government"][T_cal]
    obs_txp = vec(figaro["taxes_products"][:, T_cal])

    ic_m = max.(0, ic_raw)
    cf = Bit.pos(cf_raw)
    ex = Bit.pos(ex_raw)
    hh = copy(hh_raw)
    gc = copy(gc_raw)

    bridge = Bit.calibration_valuation_bridge(figaro, T_cal, G)
    use_ptn = Bit.calibration_boolean_marker(figaro, "use_product_tax_netting")
    bridge === nothing && error("reconciliation assumes a valuation bridge is present")

    it = use_ptn ? Bit.net_product_tax_targets(vec(sum(ic_m, dims = 1)), obs_txp, "ic") : vec(sum(ic_m, dims = 1))
    ht = use_ptn ? Bit.net_product_tax_targets(sum(hh), txp_hh, "hh") : sum(hh)
    ft = use_ptn ? Bit.net_product_tax_targets(sum(cf), txp_cf, "cf") : sum(cf)
    gt = use_ptn ? Bit.net_product_tax_targets(sum(gc), txp_g, "gc") : sum(gc)
    ic_b = Bit.apply_valuation_bridge(ic_m, bridge, "ic"; target_totals = it)
    hh_b = Bit.apply_valuation_bridge(hh, bridge, "hh"; target_total = ht)
    cf_b = Bit.apply_valuation_bridge(cf, bridge, "cf"; target_total = ft)
    gc_b = Bit.apply_valuation_bridge(gc, bridge, "gc"; target_total = gt)
    ex_b = Bit.apply_valuation_bridge(ex, bridge, "ex")

    industry_output = vec(sum(ic_b, dims = 1)) .+ txprod .+ comp .+ os
    cc = vec(calibration["capital_consumption"][:, T_cal])
    gcf_dw = calibration["gross_capitalformation_dwellings"][T_cal]
    txp_cf_dw = gcf_dw * (1 - 1 / (1 + txp_cf / sum(cf_b)))
    cf_dw = (gcf_dw - txp_cf_dw) * cf_b / sum(cf_b)
    cf_other = cf_b - cf_dw
    firm_cf = cf_other * sum(cc) / sum(cf_other)

    imports, reexports = Bit.calibration_trade_vectors(figaro, T_cal, G) do
        return vec(sum(ic_b, dims = 2)) + hh_b + gc_b + firm_cf + cf_dw + ex_b - industry_output
    end
    dom_ex = Bit.pos(ex_b - reexports)

    uses = vec(sum(ic_b, dims = 2)) + hh_b + gc_b + firm_cf + cf_dw + dom_ex
    supply = industry_output .+ imports

    return (;
        G, bridge, ic_raw, hh_raw, cf_raw, ex_raw, gc_raw, obs_txp,
        ic_b, hh_b, cf_b, gc_b, ex_b, industry_output, cc, gcf_dw, txp_cf_dw,
        cf_dw, cf_other, firm_cf, imports, reexports, dom_ex, uses, supply,
        raw_col_totals_ic = vec(sum(ic_m, dims = 1)),
        raw_tot_hh = sum(hh), raw_tot_cf = sum(cf), raw_tot_gc = sum(gc), raw_tot_ex = sum(ex),
    )
end

# -------------------------------------------------------------------------------------
# RAS (biproportional) balancing.  Zero-preserving by construction.
# -------------------------------------------------------------------------------------
function ras(
        U0::Matrix{Float64}, r::Vector{Float64}, c::Vector{Float64};
        tol = 1.0e-13, maxit = 20_000
    )
    abs(sum(r) - sum(c)) <= 1.0e-6 * abs(sum(c)) ||
        error("RAS infeasible: sum(row controls)=$(sum(r)) != sum(col controls)=$(sum(c))")
    U = copy(U0)
    hist = Float64[]
    for it in 1:maxit
        rs = vec(sum(U, dims = 1))
        any(iszero, rs[c .> 0]) && error("RAS: an active column is structurally empty")
        U .*= reshape(ifelse.(rs .> 0, c ./ max.(rs, eps()), 0.0), 1, :)
        ro = vec(sum(U, dims = 2))
        any(iszero, ro[r .> 0]) && error("RAS: an active row is structurally empty")
        U .*= reshape(ifelse.(ro .> 0, r ./ max.(ro, eps()), 0.0), :, 1)
        err = max(
            maximum(abs.(vec(sum(U, dims = 2)) .- r) ./ max.(r, 1.0)),
            maximum(abs.(vec(sum(U, dims = 1)) .- c) ./ max.(c, 1.0))
        )
        push!(hist, err)
        err < tol && return U, it, hist
    end
    return U, maxit, hist
end

# =====================================================================================
summary_values = Dict{String, Any}()
open(REPORT, "w") do io
    log(args...) = (println(args...); println(io, args...))
    P(fmt, args...) = (s = Printf.format(Printf.Format(fmt), args...); print(s); print(io, s))

    CO = JLD2.load(SRC_JLD2)["calibration_object"]
    F0 = bridged_flows(CO.figaro, CO.calibration)
    G = F0.G

    log("="^108)
    log("COMMODITY-BALANCE RECONCILIATION  (RAS on the use side, supply composition fixed)")
    log("source : ", SRC_JLD2)
    log("date   : ", Dates.now())
    log("="^108)

    # ---------------- pre-reconciliation diagnosis ----------------
    gap0 = F0.uses .- F0.supply
    rel0 = gap0 ./ F0.supply
    rho = sum(F0.uses) / sum(F0.supply)
    P("\nBEFORE\n")
    P("  sum industry_output  = %.6e\n", sum(F0.industry_output))
    P("  sum imports (BEA)    = %.6e   (fixed)\n", sum(F0.imports))
    P("  sum supply           = %.6e\n", sum(F0.supply))
    P("  sum uses             = %.6e\n", sum(F0.uses))
    P("  aggregate residual   = %.6e   (uses - supply)  ->  rho = %.8f\n", sum(gap0), rho)
    P(
        "  gap (uses-supply)/supply :  min %.4f  p10 %.4f  p25 %.4f  med %.4f  p75 %.4f  p90 %.4f  max %.4f\n",
        minimum(rel0), quantile(rel0, 0.1), quantile(rel0, 0.25), median(rel0),
        quantile(rel0, 0.75), quantile(rel0, 0.9), maximum(rel0)
    )
    P(
        "  over-demanded %d/%d ; |gap|>10%% %d ; |gap|>25%% %d ; mean|gap| %.4f ; sd %.4f\n",
        count(>(0), rel0), G, count(x -> abs(x) > 0.1, rel0), count(x -> abs(x) > 0.25, rel0),
        mean(abs.(rel0)), std(rel0)
    )

    # where the aggregate residual comes from, exactly
    VA = sum(F0.industry_output) - sum(F0.ic_b)
    EXP = sum(F0.hh_b) + sum(F0.gc_b) + sum(F0.cf_b) + sum(F0.dom_ex) - sum(F0.imports)
    prod_exp_disc = EXP - VA
    net_inv_gap = sum(F0.cc) - sum(F0.cf_other)
    P("\n  ACCOUNTING SOURCE OF THE AGGREGATE RESIDUAL (exact decomposition)\n")
    P("    sum(uses)-sum(supply) = [expenditure GDP - production GDP] + [CFC - GFCF_nondwelling]\n")
    P("      production-side VA (basic px)     = %.6e\n", VA)
    P("      expenditure-side C+G+GFCF+X-M     = %.6e\n", EXP)
    P("      (a) production/expenditure discrepancy = %.6e  (%.2f%% of GDP)\n", prod_exp_disc, 100 * prod_exp_disc / VA)
    P("      capital consumption CFC           = %.6e\n", sum(F0.cc))
    P("      non-dwelling GFCF (basic px)      = %.6e\n", sum(F0.cf_other))
    P("      (b) CFC - GFCF_nondwelling        = %.6e\n", net_inv_gap)
    P(
        "      (a)+(b)                           = %.6e ; measured residual = %.6e ; |diff| = %.3e\n",
        prod_exp_disc + net_inv_gap, sum(gap0), abs(prod_exp_disc + net_inv_gap - sum(gap0))
    )

    summary_values["rho_measured"] = rho
    summary_values["aggregate_residual"] = sum(gap0)
    summary_values["production_side_va"] = VA
    summary_values["expenditure_side_gdp"] = EXP
    summary_values["residual_production_expenditure_discrepancy"] = prod_exp_disc
    summary_values["residual_cfc_minus_nondwelling_gfcf"] = net_inv_gap
    summary_values["gap_before_min"] = minimum(rel0)
    summary_values["gap_before_max"] = maximum(rel0)
    summary_values["gap_before_mean_abs"] = mean(abs.(rel0))
    summary_values["gap_before_sd"] = std(rel0)
    summary_values["over_demanded_sectors"] = count(>(0), rel0)

    # ---------------- build the flow system ----------------
    inv_col = F0.firm_cf .+ F0.cf_dw
    U0 = hcat(F0.ic_b, F0.hh_b, F0.gc_b, inv_col, F0.dom_ex)
    ccontrol = vec(sum(U0, dims = 1))
    lambda = 1.0
    if MODE === :final_demand_scaled
        lambda = (sum(F0.supply) - sum(ccontrol[1:G])) / sum(ccontrol[(G + 1):end])
        ccontrol[(G + 1):end] .*= lambda
        rho = 1.0
        P("\nMODE = :final_demand_scaled  (rho forced to 1)\n")
        P(
            "  lambda = (supply - intermediates)/(C+G+I+X) = %.8f  (final demand scaled by %+.4f%%)\n",
            lambda, 100 * (lambda - 1)
        )
    else
        P("\nMODE = :supply_proportional  (all measured budgets held exactly; rho = %.8f)\n", rho)
    end
    rcontrol = rho .* F0.supply
    summary_values["mode"] = String(MODE)
    summary_values["rho"] = rho
    summary_values["lambda"] = lambda

    P("\nFLOW SYSTEM : %d commodities x %d users (%d industries + C + G + I + X)\n", G, size(U0, 2), G)
    P("  zeros in the flow matrix : %d / %d (%.1f%%)\n", count(iszero, U0), length(U0), 100 * count(iszero, U0) / length(U0))
    P(
        "  rows with zero total : %d ; columns with zero total : %d\n",
        count(iszero, vec(sum(U0, dims = 2))), count(iszero, ccontrol)
    )
    P("  row controls  = rho * supply   (sum %.6e)\n", sum(rcontrol))
    P("  col controls  = measured budgets (sum %.6e)\n", sum(ccontrol))

    U, iters, hist = ras(U0, collect(rcontrol), collect(ccontrol))
    P("\nRAS converged in %d iterations, final max relative control error %.3e\n", iters, hist[end])
    summary_values["ras_iterations"] = iters
    summary_values["ras_final_control_error"] = hist[end]

    # ---------------- post-reconciliation checks ----------------
    uses1 = vec(sum(U, dims = 2))
    ratio1 = uses1 ./ F0.supply
    P("\nAFTER\n")
    P("  max |uses_g/supply_g / rho - 1|  = %.3e     (target < 1e-6)\n", maximum(abs.(ratio1 ./ rho .- 1)))
    P(
        "  max |uses_g/supply_g - 1|        = %.6f     (= rho-1, the uniform aggregate residual)\n",
        maximum(abs.(ratio1 .- 1))
    )
    P("  sd of (uses-supply)/supply       = %.3e     (was %.4f)\n", std(ratio1 .- 1), std(rel0))
    colmove = maximum(abs.(vec(sum(U, dims = 1)) .- ccontrol) ./ max.(ccontrol, 1.0))
    P("  max relative column-budget move  = %.3e     (target < 1e-9)\n", colmove)
    colmove < 1.0e-9 || error("column budgets moved")
    maximum(abs.(ratio1 ./ rho .- 1)) < 1.0e-6 || error("balance not cleared")
    P("  zero pattern preserved           = %s\n", all((U0 .== 0) .== (U .== 0)))
    P("  all entries nonnegative          = %s\n", all(U .>= 0))

    duses = uses1 .- F0.uses
    P(
        "\n  per-commodity USE adjustment: sum|d| = %.6e (%.2f%% of total uses), max|d| = %.6e\n",
        sum(abs.(duses)), 100 * sum(abs.(duses)) / sum(F0.uses), maximum(abs.(duses))
    )
    P("  cellwise: sum|dU| = %.6e (%.2f%% of total flow)\n", sum(abs.(U .- U0)), 100 * sum(abs.(U .- U0)) / sum(U0))

    P("\n  LARGEST 10 COMMODITY ADJUSTMENTS\n")
    P("  %-4s %-8s %14s %14s %14s %10s %10s\n", "idx", "code", "uses_before", "uses_after", "d (USDm)", "d %%", "gap_before")
    for k in sortperm(abs.(duses), rev = true)[1:10]
        P(
            "  %-4d %-8s %14.5e %14.5e %14.5e %9.2f%% %9.2f%%\n",
            k, CODES[k], F0.uses[k], uses1[k], duses[k], 100 * duses[k] / F0.uses[k], 100 * rel0[k]
        )
    end

    P("\n  ADJUSTMENT BY USER COLUMN (aggregate shares are unchanged; only composition moves)\n")
    P("  %-14s %16s %16s %10s\n", "column", "budget", "sum|d cells|", "%% of budget")
    for (j, nm) in [(G + 1, "C_households"), (G + 2, "G_government"), (G + 3, "I_investment"), (G + 4, "X_exports")]
        P(
            "  %-14s %16.6e %16.6e %9.2f%%\n", nm, ccontrol[j], sum(abs.(U[:, j] .- U0[:, j])),
            100 * sum(abs.(U[:, j] .- U0[:, j])) / ccontrol[j]
        )
    end
    P(
        "  %-14s %16.6e %16.6e %9.2f%%\n", "intermediates", sum(ccontrol[1:G]),
        sum(abs.(U[:, 1:G] .- U0[:, 1:G])), 100 * sum(abs.(U[:, 1:G] .- U0[:, 1:G])) / sum(ccontrol[1:G])
    )

    # ---------------- write-back in the RAW (pre-bridge) basis ----------------
    br = F0.bridge
    ic_b_new = U[:, 1:G]
    hh_b_new = U[:, G + 1]
    gc_b_new = U[:, G + 2]
    inv_new = U[:, G + 3]
    ex_b_new = U[:, G + 4]
    cf_b_new = inv_new .* (sum(F0.cf_b) / sum(inv_new))

    unbridge(v, raw_total) = begin
        w = v ./ br
        w .* (raw_total / sum(w))
    end
    txp_hh = CO.figaro["taxes_products_household"][1]
    txp_g = CO.figaro["taxes_products_government"][1]
    ic_raw_new = similar(F0.ic_raw)
    for s in 1:G
        ic_raw_new[:, s] = unbridge(ic_b_new[:, s], F0.raw_col_totals_ic[s])
    end
    hh_raw_new = unbridge(hh_b_new, lambda * (F0.raw_tot_hh - txp_hh) + txp_hh)
    gc_raw_new = unbridge(gc_b_new, lambda * (F0.raw_tot_gc - txp_g) + txp_g)
    cf_raw_new = unbridge(cf_b_new, F0.raw_tot_cf)          # GFCF total is untouched
    ex_raw_new = unbridge(ex_b_new, lambda * F0.raw_tot_ex)

    fig = Dict{String, Any}()
    for (k, v) in CO.figaro
        fig[k] = deepcopy(v)
    end
    cal = deepcopy(CO.calibration)
    if MODE === :final_demand_scaled
        cal["capital_consumption"] = cal["capital_consumption"] .* lambda
        cal["gross_capitalformation_dwellings"] = cal["gross_capitalformation_dwellings"] .* lambda
    end
    fig["intermediate_consumption"] = reshape(ic_raw_new, G, G, 1)
    fig["household_consumption"] = reshape(hh_raw_new, G, 1)
    fig["government_consumption"] = reshape(gc_raw_new, G, 1)
    fig["fixed_capitalformation"] = reshape(cf_raw_new, G, 1)
    fig["exports"] = reshape(ex_raw_new, G, 1)
    fig["use_commodity_balance_inventory"] = false
    if EXPECTATIONS == "rw_drift"
        fig["expectation_rw_drift"] = true
    end

    # ---------------- verify the write-back through the unmodified pipeline ----------------
    F1 = bridged_flows(fig, cal)
    P("\nWRITE-BACK VERIFICATION (re-derived through the unmodified pipeline)\n")
    relerr(a, b) = maximum(abs.(a .- b) ./ max.(abs.(b), 1.0))
    P("  intermediate flows reproduce RAS solution : max rel err %.3e\n", relerr(F1.ic_b, ic_b_new))
    P("  household  flows                          : max rel err %.3e\n", relerr(F1.hh_b, hh_b_new))
    P("  government flows                          : max rel err %.3e\n", relerr(F1.gc_b, gc_b_new))
    P("  export     flows                          : max rel err %.3e\n", relerr(F1.dom_ex, ex_b_new))
    P("  investment flows (firm+dwellings)         : max rel err %.3e\n", relerr(F1.firm_cf .+ F1.cf_dw, inv_new))
    P("  industry_output UNCHANGED                 : max rel err %.3e\n", relerr(F1.industry_output, F0.industry_output))
    P("  imports UNCHANGED                         : max rel err %.3e\n", relerr(F1.imports, F0.imports))
    P("  capital consumption x lambda              : max rel err %.3e\n", relerr(F1.cc, lambda .* F0.cc))
    P(
        "  aggregate C/G/I/X vs lambda x target      : %.3e %.3e %.3e %.3e\n",
        abs(sum(F1.hh_b) / (lambda * sum(F0.hh_b)) - 1), abs(sum(F1.gc_b) / (lambda * sum(F0.gc_b)) - 1),
        abs((sum(F1.firm_cf) + sum(F1.cf_dw)) / (lambda * (sum(F0.firm_cf) + sum(F0.cf_dw))) - 1),
        abs(sum(F1.dom_ex) / (lambda * sum(F0.dom_ex)) - 1)
    )
    ratio2 = F1.uses ./ F1.supply
    P("  FINAL max |uses/supply / rho - 1|         : %.3e\n", maximum(abs.(ratio2 ./ rho .- 1)))
    maximum(abs.(ratio2 ./ rho .- 1)) < 1.0e-6 ||
        error("reconciled artifact does not clear through the pipeline")
    summary_values["final_max_abs_uses_over_supply_over_rho_minus_one"] =
        maximum(abs.(ratio2 ./ rho .- 1))

    # ---------------- coefficient deltas (what the model actually sees) ----------------
    a0 = F0.ic_b ./ sum(F0.ic_b, dims = 1)
    a1 = F1.ic_b ./ sum(F1.ic_b, dims = 1)
    P("\nCOEFFICIENT MOVEMENT (what Bit.Model receives)\n")
    P(
        "  a_sg   : max |da| = %.5f ; mean |da| = %.6f ; L1 per column mean = %.5f\n",
        maximum(abs.(a1 .- a0)), mean(abs.(a1 .- a0)), mean(vec(sum(abs.(a1 .- a0), dims = 1)))
    )
    for (nm, v0, v1) in [
            ("b_HH_g", F0.hh_b / sum(F0.hh_b), F1.hh_b / sum(F1.hh_b)),
            ("c_G_g ", F0.gc_b / sum(F0.gc_b), F1.gc_b / sum(F1.gc_b)),
            ("b_CF_g", F0.cf_other / sum(F0.cf_other), F1.cf_other / sum(F1.cf_other)),
            ("c_E_g ", F0.dom_ex / sum(F0.dom_ex), F1.dom_ex / sum(F1.dom_ex)),
            ("c_I_g ", F0.imports / sum(F0.imports), F1.imports / sum(F1.imports)),
        ]
        P("  %s : max |dshare| = %.5f ; L1 distance = %.5f\n", nm, maximum(abs.(v1 .- v0)), sum(abs.(v1 .- v0)))
    end

    # ---------------- save ----------------
    source_metadata = get(JLD2.load(SRC_JLD2), "metadata", Dict{String, Any}())
    reconciled = Bit.CalibrationData(
        cal, fig, deepcopy(CO.data), deepcopy(CO.ea),
        CO.max_calibration_date, CO.estimation_date,
    )
    meta = Dict{String, Any}(
        "provenance" => "RAS reconciliation of $(basename(SRC_JLD2))",
        "method" => MODE === :final_demand_scaled ?
            "biproportional (RAS) on the use side; row controls = industry_output + measured imports (rho = 1); " *
            "the 68 industry intermediate budgets are held exactly and the four final-demand budgets " *
            "C, G, I, X are scaled by lambda = (supply - intermediates)/(C+G+I+X), anchoring the " *
            "expenditure aggregates on the production account" :
            "biproportional (RAS) on the use side; row controls = rho*(industry_output + measured imports); " *
            "every measured column budget held exactly; rho = sum(uses)/sum(supply)",
        "mode" => String(MODE),
        "expectations" => EXPECTATIONS,
        "source_artifact" => SRC_JLD2,
        "source_artifact_sha256" => bytes2hex(SHA.sha256(read(SRC_JLD2))),
        "structural_reference_year" =>
            get(source_metadata, "structural_reference_year", missing),
        "rho" => rho,
        "lambda" => lambda,
        "aggregate_residual" => sum(gap0),
        "use_explicit_trade" => true,
        "use_commodity_balance_inventory" => false,
        "workstream" => "stage2b-2b4-structural-vintage-robustness",
        "built" => string(Dates.now()),
    )
    JLD2.jldsave(OUT_JLD2; calibration_object = reconciled, metadata = meta)
    P("\nwrote %s\n", OUT_JLD2)

    # per-commodity table for the record
    open(joinpath(REPORT_DIRECTORY, "reconciliation_by_commodity$(TAG).csv"), "w") do f
        println(f, "idx,code,supply,imports,uses_before,uses_after,delta,delta_pct,gap_before_pct,gap_after_pct")
        for k in 1:G
            @printf(
                f, "%d,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                k, CODES[k], F0.supply[k], F0.imports[k], F0.uses[k], F1.uses[k],
                F1.uses[k] - F0.uses[k], 100 * (F1.uses[k] - F0.uses[k]) / F0.uses[k],
                100 * rel0[k], 100 * (F1.uses[k] / F1.supply[k] - 1)
            )
        end
    end
    P("wrote %s\n", joinpath(REPORT_DIRECTORY, "reconciliation_by_commodity$(TAG).csv"))
end

# ---------------- provenance TOML beside the reconciled artifact ----------------
toml_path = replace(OUT_JLD2, ".jld2" => ".provenance.toml")
open(toml_path, "w") do io
    println(io, "# Provenance for $(basename(OUT_JLD2)) (stage2b workstream 2b-4)")
    println(io, "artifact_path = \"$(relpath(OUT_JLD2, REPOSITORY_ROOT))\"")
    println(io, "artifact_sha256 = \"$(bytes2hex(SHA.sha256(read(OUT_JLD2))))\"")
    println(io, "source_artifact = \"$(relpath(SRC_JLD2, REPOSITORY_ROOT))\"")
    println(io, "source_artifact_sha256 = \"$(bytes2hex(SHA.sha256(read(SRC_JLD2))))\"")
    println(io, "mode = \"$(summary_values["mode"])\"")
    println(io, "expectations = \"$EXPECTATIONS\"")
    println(io, "rho = $(summary_values["rho"])")
    println(io, "rho_measured_before_mode = $(summary_values["rho_measured"])")
    println(io, "lambda = $(summary_values["lambda"])")
    println(io, "ras_iterations = $(summary_values["ras_iterations"])")
    println(io, "ras_final_control_error = $(summary_values["ras_final_control_error"])")
    println(io, "final_max_abs_uses_over_supply_over_rho_minus_one = $(summary_values["final_max_abs_uses_over_supply_over_rho_minus_one"])")
    println(io, "report = \"$(relpath(REPORT, REPOSITORY_ROOT))\"")
    println(io, "")
    println(io, "[residual_decomposition]")
    println(io, "# sum(uses)-sum(supply) = [expenditure GDP - production GDP] + [CFC - GFCF_nondwelling]")
    println(io, "aggregate_residual_millions_usd = $(summary_values["aggregate_residual"])")
    println(io, "production_side_va_millions_usd = $(summary_values["production_side_va"])")
    println(io, "expenditure_side_gdp_millions_usd = $(summary_values["expenditure_side_gdp"])")
    println(io, "production_expenditure_discrepancy_millions_usd = $(summary_values["residual_production_expenditure_discrepancy"])")
    println(io, "cfc_minus_nondwelling_gfcf_millions_usd = $(summary_values["residual_cfc_minus_nondwelling_gfcf"])")
    println(io, "")
    println(io, "[pre_reconciliation_gap]")
    println(io, "min = $(summary_values["gap_before_min"])")
    println(io, "max = $(summary_values["gap_before_max"])")
    println(io, "mean_abs = $(summary_values["gap_before_mean_abs"])")
    println(io, "sd = $(summary_values["gap_before_sd"])")
    println(io, "over_demanded_sectors = $(summary_values["over_demanded_sectors"])")
end
println("wrote $toml_path")
println("\nDONE reconcile_structural_vintage.jl")
