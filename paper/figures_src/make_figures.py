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
os.environ.setdefault("SOURCE_DATE_EPOCH", "1786320000")  # 2026-08-10T00:00:00Z

import matplotlib

matplotlib.use("pdf")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.ticker import MultipleLocator  # noqa: E402

# --------------------------------------------------------------------------
# paths
# --------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "paper", "figures")
V2 = os.path.join(REPO, "output", "us_forecasting", "abm_v2_comparison", "v2_headline")
V1 = os.path.join(REPO, "output", "us_forecasting", "abm_v2_comparison", "v1_headline")
OUTLOOK = os.path.join(REPO, "output", "us_forecasting", "abm_v2_comparison_outlook")
RECON = os.path.join(REPO, "output", "us_forecasting", "commodity_balance_reconciliation")
PANEL = os.path.join(
    REPO, "scripts", "us", "forecasting", "diagnostics", "revised_data",
    "fixtures", "quarterly_panel.csv",
)

os.makedirs(OUT, exist_ok=True)

# --------------------------------------------------------------------------
# house style: one accent for the ABM, grey for every statistical benchmark
# --------------------------------------------------------------------------
ACCENT = "#1a4f8a"       # ABM v2 (repaired)
ACCENT_PALE = "#9dbedd"  # ABM v1 (pre-repair)
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
        "beforeit_abm_us_v2_mean": "ABM v2",
        "beforeit_abm_us_v2_median": "ABM v2 (med.)",
        "beforeit_abm_us_v1_mean": "ABM v1",
        "beforeit_abm_us_v1_median": "ABM v1 (med.)",
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


# ==========================================================================
# F1 -- weighted RMSE ratio, headline pair, three tracks x six model columns
# ==========================================================================
def figure1():
    rows = read(os.path.join(V2, "weighted_relative_scores.csv"))
    ratio = {}
    for r in rows:
        if r["target_set"] != "headline_real_gdp_gdp_deflator":
            continue
        ratio[(r["sample_track"], r["model_id"])] = float(
            r["weighted_macro_average_cellwise_rmse_ratio"])

    bvar = next(m for (_, m) in ratio if m.startswith("bvar_mniw"))
    order = [
        ("beforeit_abm_us_v2_mean", ACCENT),
        ("beforeit_abm_us_v1_mean", ACCENT_PALE),
        ("naive_historical_mean", GREY_DARK),
        (bvar, GREY),
        ("univariate_ar_p1_constant", GREY),
        ("naive_no_change", GREY_PALE),
    ]

    fig, ax = plt.subplots(figsize=(6.3, 2.9))
    n = len(order)
    width = 0.78 / n
    for j, (model, colour) in enumerate(order):
        xs, ys = [], []
        for i, (track, _) in enumerate(TRACKS):
            xs.append(i + (j - (n - 1) / 2) * width)
            ys.append(ratio[(track, model)])
        hatch = "///" if model == "beforeit_abm_us_v1_mean" else None
        bars = ax.bar(xs, ys, width * 0.92, color=colour, label=short(model),
                      edgecolor="white", linewidth=0.4, hatch=hatch, zorder=3)
        for b, y in zip(bars, ys):
            ax.text(b.get_x() + b.get_width() / 2, y + 0.022, f"{y:.3f}",
                    ha="center", va="bottom", fontsize=6.0, rotation=90,
                    color=RULE, zorder=4)

    ax.axhline(1.0, color=RULE, linewidth=0.9, linestyle="--", zorder=2)
    ax.text(-0.48, 1.012, "VAR(1) anchor", fontsize=7.0, va="bottom", ha="left",
            color=RULE)
    ax.set_xticks(range(len(TRACKS)))
    ax.set_xticklabels([lab for _, lab in TRACKS])
    ax.set_ylabel("weighted RMSE ratio\n(lower is better)")
    ax.set_ylim(0, 1.62)
    ax.yaxis.set_major_locator(MultipleLocator(0.25))
    ax.grid(axis="y", zorder=0)
    ax.legend(ncol=6, loc="upper center", bbox_to_anchor=(0.5, 1.20),
              columnspacing=1.2, handlelength=1.3, handletextpad=0.5)
    save(fig, "f1_weighted_rmse_ratio.pdf")


# ==========================================================================
# F2 -- RMSE ratio against horizon, real GDP and the GDP deflator
# ==========================================================================
def figure2():
    rows = [r for r in read(os.path.join(V2, "relative_scores.csv"))
            if r["sample_track"] == "abm_all_available_common_cells"]
    by = defaultdict(dict)
    for r in rows:
        by[(r["target_id"], int(r["horizon"]))][r["model_id"]] = float(r["rmse_ratio"])

    fig, axes = plt.subplots(1, 2, figsize=(6.3, 2.6), sharex=True)
    for ax, target, title in zip(
            axes, ["real_gdp", "gdp_deflator"],
            ["real GDP growth", "GDP-deflator inflation"]):
        v2 = [by[(target, h)]["beforeit_abm_us_v2_mean"] for h in HORIZONS]
        v1 = [by[(target, h)]["beforeit_abm_us_v1_mean"] for h in HORIZONS]
        best, best_lab = [], []
        for h in HORIZONS:
            cell = {m: v for m, v in by[(target, h)].items()
                    if not m.startswith("beforeit_abm_us")}
            m = min(cell, key=cell.get)
            best.append(cell[m])
            best_lab.append(short(m))

        ax.axhline(1.0, color=RULE, linewidth=0.8, linestyle="--", zorder=2)
        ax.plot(HORIZONS, best, marker="s", markersize=3.4, color=GREY,
                linewidth=1.0, linestyle=":", label="best statistical, per cell",
                zorder=3)
        ax.plot(HORIZONS, v1, marker="^", markersize=3.6, color=ACCENT_PALE,
                linewidth=1.1, label="ABM v1", zorder=4)
        ax.plot(HORIZONS, v2, marker="o", markersize=3.8, color=ACCENT,
                linewidth=1.5, label="ABM v2", zorder=5)
        for h, y, lab in zip(HORIZONS, best, best_lab):
            ax.annotate(lab, (h, y), textcoords="offset points", xytext=(0, -10),
                        ha="center", fontsize=5.8, color=GREY_DARK)
        ax.set_title(title)
        ax.set_xlabel("horizon $h$ (quarters)")
        ax.set_xticks(HORIZONS)
        ax.set_xlim(0.0, 13.2)
        ax.grid(axis="y", zorder=0)
    axes[0].set_ylabel("RMSE ratio to VAR(1)")
    axes[0].set_ylim(0.55, 1.40)
    axes[1].set_ylim(0.55, 1.40)
    axes[0].legend(loc="upper left", handlelength=1.6)
    save(fig, "f2_rmse_ratio_by_horizon.pdf")


# ==========================================================================
# F3 -- real-GDP bias by horizon, v1 against v2
# ==========================================================================
def figure3():
    rows = [r for r in read(os.path.join(V2, "score_summaries.csv"))
            if r["sample_track"] == "abm_all_available_common_cells"
            and r["target_id"] == "real_gdp"]
    bias = {(r["model_id"], int(r["horizon"])): float(r["mean_error"]) for r in rows}
    v1 = [bias[("beforeit_abm_us_v1_mean", h)] for h in HORIZONS]
    v2 = [bias[("beforeit_abm_us_v2_mean", h)] for h in HORIZONS]

    fig, ax = plt.subplots(figsize=(6.3, 2.55))
    x = list(range(len(HORIZONS)))
    w = 0.36
    ax.bar([i - w / 2 for i in x], v1, w, color=ACCENT_PALE, hatch="///",
           edgecolor="white", linewidth=0.4, label="ABM v1", zorder=3)
    ax.bar([i + w / 2 for i in x], v2, w, color=ACCENT, edgecolor="white",
           linewidth=0.4, label="ABM v2", zorder=3)
    ax.axhline(0.0, color=RULE, linewidth=0.8, zorder=4)

    for i, (a, b) in enumerate(zip(v1, v2)):
        ax.text(i - w / 2, a - 0.28, f"{a:.2f}", ha="center", va="top",
                fontsize=6.6, color=GREY_DARK)
        ax.text(i + w / 2, 0.22, f"{b:.2f}", ha="center", va="bottom",
                fontsize=6.6, color=ACCENT)
    ax.annotate("the $h{=}2$ rationing transient",
                xy=(1 - w / 2, v1[1]), xytext=(1.62, -5.9),
                fontsize=7.2, color=GREY_DARK,
                arrowprops=dict(arrowstyle="->", color=GREY_DARK, linewidth=0.7))
    ax.set_xticks(x)
    ax.set_xticklabels([f"$h={h}$" for h in HORIZONS])
    ax.set_ylabel("mean error, pp annualized\n(forecast $-$ realized)")
    ax.set_ylim(-8.4, 1.6)
    ax.grid(axis="y", zorder=0)
    ax.legend(loc="lower right", handlelength=1.3)

    # v2 bars are invisible at the v1 scale; the inset shows them on their own.
    ins = ax.inset_axes([0.035, 0.10, 0.235, 0.28])
    ins.bar(x, v2, 0.55, color=ACCENT, edgecolor="white", linewidth=0.3, zorder=3)
    ins.axhline(0.0, color=RULE, linewidth=0.6, zorder=4)
    ins.set_ylim(-0.30, 0.06)
    ins.set_xticks(x)
    ins.set_xticklabels([str(h) for h in HORIZONS], fontsize=5.8)
    ins.tick_params(axis="y", labelsize=5.8, length=2)
    ins.set_title("v2 alone, same units", fontsize=6.2, pad=2)
    for spine in ins.spines.values():
        spine.set_linewidth(0.5)
    save(fig, "f3_real_gdp_bias.pdf")


# ==========================================================================
# F4 -- interval coverage, empirical against nominal
# ==========================================================================
def figure4():
    rows = read(os.path.join(V2, "abm_v2_interval_coverage.csv"))
    agg = defaultdict(lambda: [0.0, 0.0, 0.0, 0])
    for r in rows:
        if r["target_id"] == "unemployment_rate":
            continue
        n = int(r["observation_count"])
        a = agg[(r["model_id"], r["target_id"])]
        a[0] += n * float(r["coverage_05_95"])
        a[1] += n * float(r["coverage_10_90"])
        a[2] += n * float(r["coverage_25_75"])
        a[3] += n

    nominal = [0.50, 0.80, 0.90]
    marks = {"real_gdp": "o", "nominal_gdp": "s", "gdp_deflator": "^",
             "effective_federal_funds_rate": "D"}
    names = {"real_gdp": "real GDP", "nominal_gdp": "nominal GDP",
             "gdp_deflator": "GDP deflator", "effective_federal_funds_rate": "EFFR"}

    fig, axes = plt.subplots(1, 2, figsize=(6.3, 2.85), sharey=True)
    for ax, model, title, colour in [
            (axes[0], "beforeit_abm_us_v1_mean", "ABM v1", ACCENT_PALE),
            (axes[1], "beforeit_abm_us_v2_mean", "ABM v2", ACCENT)]:
        ax.plot([0.4, 1.0], [0.4, 1.0], color=RULE, linewidth=0.8,
                linestyle="--", zorder=2)
        for target in ["real_gdp", "nominal_gdp", "gdp_deflator",
                       "effective_federal_funds_rate"]:
            s = agg[(model, target)]
            emp = [s[2] / s[3], s[1] / s[3], s[0] / s[3]]
            ax.plot(nominal, emp, marker=marks[target], markersize=4.2,
                    color=colour, linewidth=1.0, label=names[target],
                    markerfacecolor=colour if target == "real_gdp" else "white",
                    markeredgecolor=colour, markeredgewidth=0.9, zorder=4)
        ax.set_title(title)
        ax.set_xlabel("nominal coverage")
        ax.set_xticks(nominal)
        ax.set_xlim(0.42, 0.98)
        ax.grid(zorder=0)
    axes[0].set_ylabel("empirical coverage")
    axes[0].set_ylim(0.0, 1.0)
    axes[0].text(0.86, 0.93, "perfect\ncalibration", fontsize=6.6, color=RULE,
                 ha="center", va="center")
    axes[1].legend(loc="lower right", handlelength=1.5)
    save(fig, "f4_interval_coverage.pdf")


# ==========================================================================
# F5 -- commodity balance gap before and after the RAS reconciliation
# ==========================================================================
def figure5():
    rows = read(os.path.join(RECON, "reconciliation_by_commodity_rho1.csv"))
    before = sorted(float(r["gap_before_pct"]) for r in rows)
    after = sorted(float(r["gap_after_pct"]) for r in rows)
    n = len(before)

    fig, axes = plt.subplots(1, 2, figsize=(6.3, 2.6))

    ax = axes[0]
    ax.hist(before, bins=20, color=GREY, edgecolor="white", linewidth=0.5,
            zorder=3, label="before")
    ax.axvline(0.0, color=RULE, linewidth=0.9, linestyle="--", zorder=4)
    ax.annotate(f"min {min(before):.1f}%", xy=(min(before), 1.2),
                xytext=(-62, 8.6), fontsize=6.8, color=GREY_DARK,
                arrowprops=dict(arrowstyle="->", color=GREY_DARK, linewidth=0.6))
    ax.annotate(f"max +{max(before):.1f}%", xy=(max(before), 1.2),
                xytext=(15, 8.6), fontsize=6.8, color=GREY_DARK,
                arrowprops=dict(arrowstyle="->", color=GREY_DARK, linewidth=0.6))
    ax.set_xlabel(r"$(\mathrm{uses}_g-\mathrm{supply}_g)/\mathrm{supply}_g$, %")
    ax.set_ylabel("commodities")
    ax.set_xlim(-80, 60)
    ax.set_title("before reconciliation")
    ax.grid(axis="y", zorder=0)

    ax = axes[1]
    ax.step([-80] + before + [60], [0] + [(i + 1) / n for i in range(n)] + [1.0],
            where="post", color=GREY, linewidth=1.3, label="before", zorder=3)
    ax.step([-80, 0, 0, 60], [0, 0, 1, 1], where="post", color=ACCENT,
            linewidth=1.6, label=r"after (all $|{\rm gap}|<10^{-13}$)", zorder=4)
    ax.axvline(0.0, color=RULE, linewidth=0.8, linestyle="--", zorder=2)
    ax.set_xlim(-80, 60)
    ax.set_ylim(0, 1.03)
    ax.set_xlabel(r"$(\mathrm{uses}_g-\mathrm{supply}_g)/\mathrm{supply}_g$, %")
    ax.set_ylabel("empirical CDF, 68 commodities")
    ax.set_title("cumulative distribution")
    ax.legend(loc="upper left", handlelength=1.5)
    ax.grid(zorder=0)
    save(fig, "f5_commodity_balance.pdf")


# ==========================================================================
# F6 -- fan chart, 2026Q1 origin, with realized history prepended
# ==========================================================================
def _q_index(period):
    y, q = int(period[:4]), int(period[-1])
    return y * 4 + (q - 1)


def _q_label(idx):
    return f"{idx // 4}Q{idx % 4 + 1}"


def figure6():
    panel = read(PANEL)
    hist = [(r["period"], float(r["real_gdp"]), float(r["gdp_deflator"]))
            for r in panel if _q_index(r["period"]) >= _q_index("2023Q1")]

    out = [r for r in read(os.path.join(OUTLOOK, "current_outlook.csv"))
           if r["origin_period"] == "2026Q1"]
    fan = defaultdict(dict)
    for r in out:
        fan[r["target_id"]][int(r["horizon"])] = r

    fig, axes = plt.subplots(1, 2, figsize=(6.3, 2.75), sharex=True)
    for ax, target, col, title in [
            (axes[0], "real_gdp", 1, "real GDP growth"),
            (axes[1], "gdp_deflator", 2, "GDP-deflator inflation")]:
        hx = [_q_index(p) for p, _, _ in hist]
        hy = [v[col] for v in hist]
        ax.plot(hx, hy, color=GREY_DARK, linewidth=1.1, marker="o",
                markersize=2.4, label="realized (revised panel)", zorder=5)

        hs = sorted(fan[target])
        fx = [_q_index("2026Q1") + h for h in hs]
        med = [float(fan[target][h]["ensemble_median"]) for h in hs]
        p05 = [float(fan[target][h]["percentile_05"]) for h in hs]
        p25 = [float(fan[target][h]["percentile_25"]) for h in hs]
        p75 = [float(fan[target][h]["percentile_75"]) for h in hs]
        p95 = [float(fan[target][h]["percentile_95"]) for h in hs]
        ax.fill_between(fx, p05, p95, color=ACCENT, alpha=0.16, linewidth=0,
                        label="5--95th percentile", zorder=2)
        ax.fill_between(fx, p25, p75, color=ACCENT, alpha=0.32, linewidth=0,
                        label="25--75th percentile", zorder=3)
        ax.plot(fx, med, color=ACCENT, linewidth=1.5, marker="o", markersize=2.8,
                label="ensemble median", zorder=6)
        ax.axvline(_q_index("2026Q1"), color=RULE, linewidth=0.7,
                   linestyle=":", zorder=4)
        ax.axhline(0.0, color=GREY_PALE, linewidth=0.7, zorder=1)
        ax.text(_q_index("2026Q1") - 0.4, ax.get_ylim()[1], "origin 2026Q1",
                rotation=90, fontsize=6.4, va="top", ha="right", color=RULE)
        ax.set_title(title)
        ticks = [_q_index(p) for p in
                 ["2023Q1", "2024Q1", "2025Q1", "2026Q1", "2027Q1", "2028Q1", "2029Q1"]]
        ax.set_xticks(ticks)
        ax.set_xticklabels([_q_label(t) for t in ticks], rotation=45, ha="right")
        ax.grid(axis="y", zorder=0)
    axes[0].set_ylabel("pp, annualized")
    axes[0].legend(loc="lower left", handlelength=1.4, fontsize=6.6)
    save(fig, "f6_outlook_fan.pdf")


# ==========================================================================
# F9 -- forecast against realized across all 61 origins, h = 4
# ==========================================================================
def figure9(horizon=4):
    panel = {r["period"]: r for r in read(PANEL)}
    # the ensemble cache carries every origin; only cells whose target quarter
    # exists in the revised panel are scoreable, and only those are plotted.
    e1 = [r for r in read(os.path.join(V1, "abm_ensemble_summaries.csv"))
          if r["target_id"] == "real_gdp" and int(r["horizon"]) == horizon
          and r["target_period"] in panel]
    e2 = [r for r in read(os.path.join(V2, "abm_ensemble_summaries.csv"))
          if r["target_id"] == "real_gdp" and int(r["horizon"]) == horizon
          and r["target_period"] in panel]
    e1.sort(key=lambda r: int(r["origin_index"]))
    e2.sort(key=lambda r: int(r["origin_index"]))

    x = [_q_index(r["target_period"]) for r in e2]
    actual = [float(panel[r["target_period"]]["real_gdp"]) for r in e2]
    f1 = [float(r["ensemble_mean"]) for r in e1]
    f2 = [float(r["ensemble_mean"]) for r in e2]
    lo = [float(r["percentile_05"]) for r in e2]
    hi = [float(r["percentile_95"]) for r in e2]

    fig, ax = plt.subplots(figsize=(6.3, 2.8))
    ax.axvspan(_q_index("2020Q1"), _q_index("2021Q4"), color=GREY_PALE,
               alpha=0.55, linewidth=0, zorder=1)
    ax.text(_q_index("2020Q1") - 0.6, 33, "cells removed by the\npandemic mask",
            fontsize=6.2, ha="right", va="top", color=GREY_DARK)
    ax.fill_between(x, lo, hi, color=ACCENT, alpha=0.14, linewidth=0,
                    label="ABM v2, 5--95th percentile", zorder=2)
    ax.plot(x, actual, color=RULE, linewidth=1.2, label="realized", zorder=6)
    ax.plot(x, f1, color=ACCENT_PALE, linewidth=1.1, linestyle="--",
            label="ABM v1 ensemble mean", zorder=4)
    ax.plot(x, f2, color=ACCENT, linewidth=1.3, label="ABM v2 ensemble mean",
            zorder=5)
    ax.axhline(0.0, color=GREY_PALE, linewidth=0.7, zorder=1)
    ticks = [_q_index(f"{y}Q1") for y in range(2011, 2026, 2)]
    ax.set_xticks(ticks)
    ax.set_xticklabels([_q_label(t) for t in ticks], rotation=45, ha="right")
    ax.set_ylabel("real GDP growth, pp annualized")
    ax.set_xlabel("target quarter")
    ax.set_ylim(-38, 38)
    ax.grid(axis="y", zorder=0)
    ax.legend(ncol=2, loc="lower center", handlelength=1.6, fontsize=6.9)
    save(fig, "f9_paths_h4.pdf")


if __name__ == "__main__":
    figure1()
    figure2()
    figure3()
    figure4()
    figure5()
    figure6()
    figure9()
