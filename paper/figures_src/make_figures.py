#!/usr/bin/env python3
"""Regenerate every vector figure in ``paper/figures`` from committed result CSVs.

Run from anywhere:

    python3 paper/figures_src/make_figures.py

Every number plotted here is read from a file under ``output/us_forecasting/`` or
``scripts/us/forecasting/diagnostics/revised_data/fixtures/``.  Nothing is hard
coded except axis labels, the horizon weights used for annotation, and the
nominal coverage levels, all of which are stated in the run manifests.
"""

from __future__ import annotations

import csv
import os
from collections import defaultdict

# Pin the PDF creation timestamp so a re-run is byte-reproducible; matplotlib
# honours SOURCE_DATE_EPOCH when it writes the /CreationDate entry.
os.environ.setdefault("SOURCE_DATE_EPOCH", "1786924800")  # 2026-08-17T00:00:00Z

import matplotlib

matplotlib.use("pdf")
import matplotlib.pyplot as plt  # noqa: E402

# --------------------------------------------------------------------------
# paths
# --------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "paper", "figures")
STAGE = os.path.join(REPO, "output", "us_forecasting", "stage2b_scorecard")
FULL = os.path.join(REPO, "output", "us_forecasting", "stage2b_full")
V3 = os.path.join(FULL, "v3_headline")
V1 = os.path.join(FULL, "v1_headline")
V2 = os.path.join(FULL, "v2_headline")
OUTLOOK = os.path.join(FULL, "outlook_v3")
RECON = os.path.join(REPO, "output", "us_forecasting", "commodity_balance_reconciliation")
PANEL = os.path.join(
    REPO, "scripts", "us", "forecasting", "diagnostics", "revised_data",
    "fixtures", "quarterly_panel.csv",
)

os.makedirs(OUT, exist_ok=True)

# --------------------------------------------------------------------------
# house style: one accent for the ABM, a dark tone for the DSGE columns,
# grey for the statistical family
# --------------------------------------------------------------------------
ACCENT = "#1a4f8a"       # the ABM
ACCENT_PALE = "#9dbedd"  # ABM ablation (no reconciliation)
DSGE = "#7a4a21"         # DSGE columns
GREY = "#8c8c8c"
GREY_DARK = "#4d4d4d"
GREY_PALE = "#cfcfcf"
RULE = "#2b2b2b"

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["DejaVu Serif"],
    "font.size": 8.5,
    "axes.labelsize": 8.5,
    "axes.titlesize": 9.0,
    "axes.titleweight": "normal",
    "legend.fontsize": 7.6,
    "xtick.labelsize": 8.0,
    "ytick.labelsize": 8.0,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.edgecolor": RULE,
    "axes.linewidth": 0.6,
    "xtick.major.width": 0.6,
    "ytick.major.width": 0.6,
    "grid.color": "#dddddd",
    "grid.linewidth": 0.5,
    "legend.frameon": False,
    "figure.dpi": 200,
    "pdf.fonttype": 42,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.02,
})

HORIZONS = [1, 2, 4, 8, 12]
ANCHOR = "beforeit_var_p1_constant"
ABM = "beforeit_abm_us_v3_mean"
ABM_NORECON = "beforeit_abm_us_v1_mean"
SW07 = "dsge_sw07"
SMALLNK = "dsge_small_nk"
TRACKS = [
    ("abm_all_available_common_cells", "all-available"),
    ("abm_balanced_h12_common_cells", "balanced $h{=}12$"),
    ("abm_pandemic_masked_common_cells", "pandemic-masked"),
]


def read(path):
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh))


def save(fig, name):
    path = os.path.join(OUT, name)
    fig.savefig(path)
    plt.close(fig)
    print("wrote", os.path.relpath(path, REPO))


def short(model_id):
    """Compact display label for a scored model column."""
    table = {
        ABM: "ABM",
        "beforeit_abm_us_v3_median": "ABM (med.)",
        ABM_NORECON: "ABM (no recon.)",
        SW07: "SW07 DSGE",
        SMALLNK: "small-NK DSGE",
        "naive_no_change": "naive RW",
        "naive_drift": "naive drift",
        "naive_historical_mean": "hist. mean",
        "univariate_ar_p1_constant": "AR(1)",
        "univariate_ar_p4_constant": "AR(4)",
        "univariate_ar_bic_p1-2-3-4-5-6-7-8_constant": "AR(BIC)",
        "beforeit_var_p1_constant": "VAR(1)",
        "beforeit_var_p2_constant": "VAR(2)",
        "beforeit_var_p3_constant": "VAR(3)",
    }
    if model_id in table:
        return table[model_id]
    if model_id.startswith("bvar_mniw"):
        return "BVAR"
    return model_id


def colour(model_id):
    if model_id == ABM:
        return ACCENT
    if model_id == ABM_NORECON:
        return ACCENT_PALE
    if model_id in (SW07, SMALLNK):
        return DSGE
    return GREY


# ==========================================================================
# F1 -- weighted RMSE ratio, headline pair, three tracks, selected columns
# ==========================================================================
def figure1():
    rows = read(os.path.join(STAGE, "stage2b_weighted_scores.csv"))
    rows = [r for r in rows
            if r["target_set"] == "headline_real_gdp_gdp_deflator"
            and r["status"] == "COMPLETE_MATCHED"]
    value = {(r["sample_track"], r["model_id"]): float(r["weighted_rmse_ratio"])
             for r in rows}
    columns = [ABM, SW07, SMALLNK, "naive_historical_mean",
               "bvar_mniw_v1_p1_constant_tight3fc999999999999a_decay3ff0000000000000_own0000000000000000_ivar4059000000000000_iwoff2_iscale3ff0000000000000_floor3e45798ee2308c3a_diffmse_scale",
               "univariate_ar_p1_constant", ANCHOR]
    # resolve the BVAR id robustly (hash-suffixed)
    all_ids = {r["model_id"] for r in rows}
    columns = [next((m for m in all_ids if m.startswith(c[:9])), c)
               if c.startswith("bvar") else c for c in columns]

    fig, ax = plt.subplots(figsize=(6.3, 2.7))
    n_col = len(columns)
    width = 0.8 / n_col
    for j, m in enumerate(columns):
        xs = [i + (j - n_col / 2 + 0.5) * width for i in range(len(TRACKS))]
        ys = [value[(t, m)] for t, _ in TRACKS]
        ax.bar(xs, ys, width * 0.92, color=colour(m), edgecolor="white",
               linewidth=0.4, label=short(m), zorder=3)
        for x, y in zip(xs, ys):
            ax.text(x, y + 0.012, f"{y:.3f}"[1:], ha="center", va="bottom",
                    fontsize=5.4, rotation=90, color=GREY_DARK)
    ax.axhline(1.0, color=RULE, linewidth=0.8, linestyle="--", zorder=4)
    ax.set_xticks(range(len(TRACKS)))
    ax.set_xticklabels([label for _, label in TRACKS])
    ax.set_ylabel("weighted RMSE ratio vs VAR(1)")
    ax.set_ylim(0.60, 1.20)
    ax.grid(axis="y", zorder=0)
    ax.legend(loc="upper left", ncol=4, handlelength=1.1, columnspacing=0.9)
    save(fig, "f1_weighted_rmse_ratio.pdf")


# ==========================================================================
# F2 -- RMSE ratio by horizon: ABM, SW07, and the best-statistical envelope
# ==========================================================================
def figure2():
    rows = [r for r in read(os.path.join(STAGE, "stage2b_relative_scores.csv"))
            if r["sample_track"] == "abm_all_available_common_cells"]
    stat_ids = {r["model_id"] for r in rows
                if not r["model_id"].startswith("beforeit_abm")
                and not r["model_id"].startswith("dsge")}
    fig, axes = plt.subplots(1, 2, figsize=(6.3, 2.55), sharex=True)
    for ax, target, title in zip(
            axes, ["real_gdp", "gdp_deflator"],
            ["real GDP growth", "GDP-deflator inflation"]):
        sel = [r for r in rows if r["target_id"] == target]
        ratio = {(r["model_id"], int(r["horizon"])): float(r["rmse_ratio"])
                 for r in sel}
        xs = range(len(HORIZONS))
        ax.plot(xs, [ratio[(ABM, h)] for h in HORIZONS], color=ACCENT,
                marker="o", markersize=3.5, linewidth=1.4, label="ABM", zorder=5)
        ax.plot(xs, [ratio[(SW07, h)] for h in HORIZONS], color=DSGE,
                marker="s", markersize=3.2, linewidth=1.2, label="SW07 DSGE",
                zorder=4)
        best_vals, best_names = [], []
        for h in HORIZONS:
            candidates = [(ratio[(m, h)], m) for m in stat_ids if (m, h) in ratio]
            v, m = min(candidates)
            best_vals.append(v)
            best_names.append(short(m))
        ax.plot(xs, best_vals, color=GREY_DARK, marker="s", markersize=3.2,
                linewidth=0.0, label="best statistical (per cell)", zorder=3)
        for x, v, name in zip(xs, best_vals, best_names):
            ax.annotate(name, (x, v), textcoords="offset points",
                        xytext=(0, -11), ha="center", fontsize=5.6,
                        color=GREY_DARK)
        ax.axhline(1.0, color=RULE, linewidth=0.7, linestyle="--", zorder=2)
        ax.set_xticks(list(xs))
        ax.set_xticklabels([f"$h={h}$" for h in HORIZONS])
        ax.set_title(title)
        ax.grid(axis="y", zorder=0)
    axes[0].set_ylabel("RMSE ratio vs VAR(1)")
    axes[0].legend(loc="upper left", handlelength=1.3)
    save(fig, "f2_rmse_ratio_by_horizon.pdf")


# ==========================================================================
# F3 -- real-GDP mean error by horizon: the accounting component's effect
# ==========================================================================
def figure3():
    rows = [r for r in read(os.path.join(STAGE, "stage2b_cell_losses.csv"))
            if r["target_id"] == "real_gdp"]
    sums = defaultdict(float)
    counts = defaultdict(int)
    for r in rows:
        key = (r["model_id"], int(r["horizon"]))
        sums[key] += float(r["error"])
        counts[key] += 1
    bias = {k: sums[k] / counts[k] for k in sums}
    noreco = [bias[(ABM_NORECON, h)] for h in HORIZONS]
    full = [bias[(ABM, h)] for h in HORIZONS]

    fig, ax = plt.subplots(figsize=(6.3, 2.55))
    x = list(range(len(HORIZONS)))
    w = 0.36
    ax.bar([i - w / 2 for i in x], noreco, w, color=ACCENT_PALE, hatch="///",
           edgecolor="white", linewidth=0.4, label="without reconciliation",
           zorder=3)
    ax.bar([i + w / 2 for i in x], full, w, color=ACCENT, edgecolor="white",
           linewidth=0.4, label="the model", zorder=3)
    ax.axhline(0.0, color=RULE, linewidth=0.8, zorder=4)
    for i, (a, b) in enumerate(zip(noreco, full)):
        ax.text(i - w / 2, a - 0.28, f"{a:.2f}", ha="center", va="top",
                fontsize=6.6, color=GREY_DARK)
        ax.text(i + w / 2, 0.22, f"{b:.2f}", ha="center", va="bottom",
                fontsize=6.6, color=ACCENT)
    ax.annotate("the $h{=}2$ rationing transient",
                xy=(1 - w / 2, noreco[1]), xytext=(1.62, -5.9),
                fontsize=7.2, color=GREY_DARK,
                arrowprops=dict(arrowstyle="->", color=GREY_DARK, linewidth=0.7))
    ax.set_xticks(x)
    ax.set_xticklabels([f"$h={h}$" for h in HORIZONS])
    ax.set_ylabel("mean error, pp annualized\n(forecast $-$ realized)")
    ax.set_ylim(-8.4, 1.6)
    ax.grid(axis="y", zorder=0)
    ax.legend(loc="lower right", handlelength=1.3)
    ins = ax.inset_axes([0.035, 0.10, 0.235, 0.28])
    ins.bar(x, full, 0.55, color=ACCENT, edgecolor="white", linewidth=0.3,
            zorder=3)
    ins.axhline(0.0, color=RULE, linewidth=0.6, zorder=4)
    ins.set_ylim(-0.30, 0.30)
    ins.set_xticks(x)
    ins.set_xticklabels([str(h) for h in HORIZONS], fontsize=5.8)
    ins.tick_params(axis="y", labelsize=5.8, length=2)
    ins.set_title("the model alone, same units", fontsize=6.2, pad=2)
    for spine in ins.spines.values():
        spine.set_linewidth(0.5)
    save(fig, "f3_real_gdp_bias.pdf")


# ==========================================================================
# F4 -- interval coverage, empirical against nominal (ABM, all-available)
# ==========================================================================
def figure4():
    rows = [r for r in read(os.path.join(STAGE, "stage2b_density_coverage.csv"))
            if r["sample_track"] == "abm_all_available_common_cells"
            and r["model_id"] == ABM]
    targets = [
        ("real_gdp", "real GDP", "o"),
        ("nominal_gdp", "nominal GDP", "D"),
        ("gdp_deflator", "deflator", "s"),
        ("effective_federal_funds_rate", "EFFR", "^"),
        ("unemployment_rate", "unemployment", "v"),
    ]
    levels = [0.5, 0.8, 0.9]
    fig, ax = plt.subplots(figsize=(4.4, 3.3))
    ax.plot([0, 1], [0, 1], color=RULE, linewidth=0.8, linestyle="--", zorder=2)
    for target, label, marker in targets:
        xs, ys = [], []
        for level in levels:
            sel = [r for r in rows if r["target_id"] == target
                   and abs(float(r["nominal_level"]) - level) < 1e-9]
            n = sum(int(r["observation_count"]) for r in sel)
            cov = sum(float(r["empirical_coverage"]) * int(r["observation_count"])
                      for r in sel) / n
            xs.append(level)
            ys.append(cov)
        ax.plot(xs, ys, marker=marker, markersize=4.5, linewidth=1.0,
                label=label, zorder=3)
    ax.set_xlabel("nominal central-interval coverage")
    ax.set_ylabel("empirical coverage")
    ax.set_xlim(0.05, 1.0)
    ax.set_ylim(0.0, 1.0)
    ax.grid(zorder=0)
    ax.legend(loc="upper left", handlelength=1.2)
    save(fig, "f4_interval_coverage.pdf")


# ==========================================================================
# F5 -- the opening commodity balance, before and after reconciliation
# ==========================================================================
def figure5():
    rows = read(os.path.join(RECON, "reconciliation_by_commodity_rho1.csv"))
    before = sorted(float(r["gap_before_pct"]) for r in rows)
    after = sorted(float(r["gap_after_pct"]) for r in rows)
    fig, axes = plt.subplots(1, 2, figsize=(6.3, 2.5))
    ax = axes[0]
    ax.hist(before, bins=24, color=GREY, edgecolor="white", linewidth=0.4,
            zorder=3)
    ax.axvline(0.0, color=RULE, linewidth=0.8, zorder=4)
    ax.set_xlabel("(uses $-$ supply) / supply, %")
    ax.set_ylabel("commodities")
    ax.grid(axis="y", zorder=0)
    ax = axes[1]
    n = len(before)
    ax.step(before, [i / n for i in range(1, n + 1)], color=GREY,
            linewidth=1.2, label="before", zorder=3)
    ax.step(after, [i / n for i in range(1, n + 1)], color=ACCENT,
            linewidth=1.4, label="after", zorder=4)
    ax.axvline(0.0, color=RULE, linewidth=0.6, linestyle=":", zorder=2)
    ax.set_xlabel("(uses $-$ supply) / supply, %")
    ax.set_ylabel("empirical CDF")
    ax.grid(zorder=0)
    ax.legend(loc="lower right", handlelength=1.3)
    save(fig, "f5_commodity_balance.pdf")


# ==========================================================================
# period helpers
# ==========================================================================
def _q_index(period):
    year, quarter = period.split("Q")
    return int(year) * 4 + (int(quarter) - 1)


def _q_label(idx):
    return f"{idx // 4}Q{idx % 4 + 1}"


# ==========================================================================
# F6 -- current outlook fan from the 2026Q1 origin (unscored)
# ==========================================================================
def figure6():
    panel = read(PANEL)
    origin = "2026Q1"
    ens = [r for r in read(os.path.join(OUTLOOK, "abm_ensemble_summaries.csv"))
           if r["origin_period"] == origin]
    fig, axes = plt.subplots(1, 2, figsize=(6.3, 2.6), sharex=True)
    for ax, target, title, column in zip(
            axes, ["real_gdp", "gdp_deflator"],
            ["real GDP growth", "GDP-deflator inflation"],
            ["real_gdp", "gdp_deflator"]):
        hist = [(r["period"], float(r[column])) for r in panel
                if _q_index(r["period"]) >= _q_index("2023Q1")]
        hx = [_q_index(p) for p, _ in hist]
        hy = [v for _, v in hist]
        ax.plot(hx, hy, color=GREY_DARK, linewidth=1.1, label="realised",
                zorder=4)
        sel = sorted((int(r["horizon"]), r) for r in ens
                     if r["target_id"] == target)
        fx = [_q_index(origin) + h for h, _ in sel]
        med = [float(r["ensemble_median"]) for _, r in sel]
        p05 = [float(r["percentile_05"]) for _, r in sel]
        p25 = [float(r["percentile_25"]) for _, r in sel]
        p75 = [float(r["percentile_75"]) for _, r in sel]
        p95 = [float(r["percentile_95"]) for _, r in sel]
        ax.fill_between(fx, p05, p95, color=ACCENT, alpha=0.16, linewidth=0,
                        zorder=2, label="5--95%")
        ax.fill_between(fx, p25, p75, color=ACCENT, alpha=0.34, linewidth=0,
                        zorder=3, label="25--75%")
        ax.plot(fx, med, color=ACCENT, linewidth=1.4, zorder=5, label="median")
        ax.axvline(_q_index(origin), color=RULE, linewidth=0.7, linestyle=":",
                   zorder=1)
        ticks = [t for t in range(_q_index("2023Q1"), max(fx) + 1)
                 if t % 4 == 0]
        ax.set_xticks(ticks)
        ax.set_xticklabels([_q_label(t)[:4] for t in ticks])
        ax.set_title(title)
        ax.grid(axis="y", zorder=0)
    axes[0].set_ylabel("pp, annualized")
    axes[0].legend(loc="lower left", handlelength=1.2, fontsize=6.8)
    save(fig, "f6_outlook_fan.pdf")


# ==========================================================================
# F7 -- unemployment at h=8: the model's band, the no-growth ablation, truth
# ==========================================================================
def figure7(horizon=8):
    panel = read(PANEL)
    truth = {r["period"]: float(r["unemployment_rate"]) for r in panel}
    v3 = [r for r in read(os.path.join(V3, "abm_ensemble_summaries.csv"))
          if r["target_id"] == "unemployment_rate"
          and int(r["horizon"]) == horizon and r["target_period"] in truth]
    v2 = [r for r in read(os.path.join(V2, "abm_ensemble_summaries.csv"))
          if r["target_id"] == "unemployment_rate"
          and int(r["horizon"]) == horizon and r["target_period"] in truth]
    v3.sort(key=lambda r: _q_index(r["target_period"]))
    v2.sort(key=lambda r: _q_index(r["target_period"]))
    xs = [_q_index(r["target_period"]) for r in v3]
    fig, ax = plt.subplots(figsize=(6.3, 2.6))
    ax.fill_between(xs,
                    [float(r["percentile_05"]) for r in v3],
                    [float(r["percentile_95"]) for r in v3],
                    color=ACCENT, alpha=0.18, linewidth=0, zorder=2,
                    label="ABM 5--95%")
    ax.plot(xs, [float(r["ensemble_median"]) for r in v3], color=ACCENT,
            linewidth=1.4, zorder=5, label="ABM median")
    ax.plot([_q_index(r["target_period"]) for r in v2],
            [float(r["ensemble_median"]) for r in v2], color=ACCENT_PALE,
            linewidth=1.1, linestyle="--", zorder=4,
            label="without trend growth (median)")
    ax.plot(xs, [truth[r["target_period"]] for r in v3], color=GREY_DARK,
            linewidth=1.1, zorder=6, label="realised")
    ticks = [t for t in range(min(xs), max(xs) + 1) if t % 8 == 0]
    ax.set_xticks(ticks)
    ax.set_xticklabels([_q_label(t)[:4] for t in ticks])
    ax.set_ylabel("unemployment rate, %")
    ax.set_ylim(0, 14.5)
    ax.grid(axis="y", zorder=0)
    ax.legend(loc="upper right", handlelength=1.3, fontsize=6.8)
    save(fig, "f7_unemployment.pdf")


# ==========================================================================
# F9 -- four-quarter-ahead real GDP growth across the backtest
# ==========================================================================
def figure9(horizon=4):
    panel = read(PANEL)
    truth = {r["period"]: float(r["real_gdp"]) for r in panel}
    model = [r for r in read(os.path.join(V3, "abm_ensemble_summaries.csv"))
             if r["target_id"] == "real_gdp" and int(r["horizon"]) == horizon
             and r["target_period"] in truth]
    ablation = [r for r in read(os.path.join(V1, "abm_ensemble_summaries.csv"))
                if r["target_id"] == "real_gdp" and int(r["horizon"]) == horizon
                and r["target_period"] in truth]
    model.sort(key=lambda r: _q_index(r["target_period"]))
    ablation.sort(key=lambda r: _q_index(r["target_period"]))
    xs = [_q_index(r["target_period"]) for r in model]
    fig, ax = plt.subplots(figsize=(6.3, 2.6))
    ax.plot(xs, [truth[r["target_period"]] for r in model], color=GREY_DARK,
            linewidth=1.1, zorder=5, label="realised")
    ax.plot(xs, [float(r["ensemble_mean"]) for r in model], color=ACCENT,
            linewidth=1.4, zorder=6, label="ABM (mean)")
    ax.plot([_q_index(r["target_period"]) for r in ablation],
            [float(r["ensemble_mean"]) for r in ablation], color=ACCENT_PALE,
            linewidth=1.1, linestyle="--", zorder=4,
            label="without reconciliation")
    ax.axhline(0.0, color=RULE, linewidth=0.6, zorder=1)
    ticks = [t for t in range(min(xs), max(xs) + 1) if t % 8 == 0]
    ax.set_xticks(ticks)
    ax.set_xticklabels([_q_label(t)[:4] for t in ticks])
    ax.set_ylabel("real GDP growth at $h{=}4$,\npp annualized")
    ax.set_ylim(-11, 36)
    ax.grid(axis="y", zorder=0)
    ax.legend(loc="upper right", handlelength=1.3, fontsize=6.8)
    save(fig, "f9_paths_h4.pdf")


if __name__ == "__main__":
    figure1()
    figure2()
    figure3()
    figure4()
    figure5()
    figure6()
    figure7()
    figure9()
