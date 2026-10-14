"""Build the charts in charts/ from the query outputs saved in results/.

Usage (from the repository root):
    pip install -r requirements.txt
    python scripts/make_charts.py

The charts read only the CSV files in results/, so they can be rebuilt
without access to the database.
"""
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
CHARTS = ROOT / "charts"
CHARTS.mkdir(exist_ok=True)

# Palette: one hue per job. Text always uses the ink colours, never a series colour.
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_SOFT = "#52514e"
GRID = "#e4e3df"
BLUE = "#2a78d6"
ORANGE = "#eb6834"
AQUA = "#1baf7a"
BLUE_RAMP = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]

plt.rcParams.update({
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "font.family": "DejaVu Sans",
    "font.size": 10,
    "text.color": INK,
    "axes.labelcolor": INK_SOFT,
    "axes.edgecolor": GRID,
    "xtick.color": INK_SOFT,
    "ytick.color": INK_SOFT,
    "axes.spines.top": False,
    "axes.spines.right": False,
})


def finish(fig, ax, title, subtitle, name, title_y=0.985, subtitle_y=0.925):
    fig.suptitle(title, x=0.01, y=title_y, ha="left", fontsize=13, fontweight="bold")
    fig.text(0.01, subtitle_y, subtitle, ha="left", va="top", fontsize=9.5, color=INK_SOFT)
    ax.tick_params(length=0)
    fig.savefig(CHARTS / name, dpi=160, bbox_inches="tight", pad_inches=0.25)
    plt.close(fig)
    print("wrote", name)


def monthly_churn():
    df = pd.read_csv(RESULTS / "q01a_monthly_churn.csv", parse_dates=["month"])
    # 2015-01 is the left edge of the data and 2017-03 holds a single day.
    df = df[(df.month >= "2015-02-01") & (df.month <= "2017-02-01")]
    fig, ax = plt.subplots(figsize=(10, 4.6))
    fig.subplots_adjust(top=0.82)
    ax.plot(df.month, df.pct_churn_30d, color=BLUE, linewidth=2)
    spikes = df[df.pct_churn_30d > 15]
    ax.scatter(spikes.month, spikes.pct_churn_30d, s=42, color=BLUE, zorder=3,
               edgecolor=SURFACE, linewidth=2)
    for _, r in spikes.iterrows():
        ax.annotate(f"{r.month:%b %Y}\n{r.pct_churn_30d:.1f}%", (r.month, r.pct_churn_30d),
                    xytext=(0, 9), textcoords="offset points", ha="center", fontsize=9, color=INK)
    ax.set_ylim(0, 31)
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:.0f}%")
    ticks = pd.date_range("2015-03-01", "2017-02-01", freq="3MS")
    ax.set_xticks(ticks)
    ax.set_xticklabels([f"{t:%b %Y}" for t in ticks], fontsize=9)
    ax.tick_params(axis="x", pad=8)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines["left"].set_visible(False)
    finish(fig, ax, "Monthly churn sits between 4% and 10%, except in four months",
           "Share of expiries with no new transaction within 30 days, by month of expiry. "
           "Feb 2015 to Feb 2017.", "01_monthly_churn.png")


def cohort_heatmap():
    df = pd.read_csv(RESULTS / "q02_cohort_matrix.csv")
    cols = ["m0", "m1", "m2", "m3", "m6", "m12", "m18", "m24"]
    values = df[cols].to_numpy(dtype=float)
    cmap = LinearSegmentedColormap.from_list("blue_ramp", BLUE_RAMP)
    cmap.set_bad(SURFACE)
    fig, ax = plt.subplots(figsize=(8.6, 10.4))
    fig.subplots_adjust(top=0.875)
    ax.imshow(np.ma.masked_invalid(values), cmap=cmap, vmin=0, vmax=100, aspect="auto")
    for i in range(values.shape[0]):
        for j in range(values.shape[1]):
            v = values[i, j]
            if not np.isnan(v):
                ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=8.5,
                        color="#ffffff" if v >= 52 else INK)
    ax.set_xticks(range(len(cols)))
    ax.set_xticklabels([f"Month {c[1:]}" for c in cols], fontsize=9)
    ax.xaxis.tick_top()
    ax.set_yticks(range(len(df)))
    ax.set_yticklabels([f"{m[:7]}   n={n:,}" for m, n in zip(df.cohort_month, df.cohort_size)],
                       fontsize=8.5)
    # white gaps between cells
    ax.set_xticks(np.arange(-0.5, len(cols)), minor=True)
    ax.set_yticks(np.arange(-0.5, len(df)), minor=True)
    ax.grid(which="minor", color=SURFACE, linewidth=2)
    ax.tick_params(which="minor", length=0)
    for s in ax.spines.values():
        s.set_visible(False)
    finish(fig, ax, "Retention by cohort: the loss happens in the first month",
           "% of each cohort (month of first transaction) with an active subscription on the last "
           "day of month k.\nBlank = not yet observable. Pale rows are the free-promotion cohorts.",
           "02_cohort_retention.png", title_y=0.975, subtitle_y=0.948)


def churn_by_type():
    df = pd.read_csv(RESULTS / "q01b_churn_by_type.csv")
    df = df[~df.spike_month].copy()
    df["label"] = df.apply(lambda r: f"{'Free' if r.is_free else 'Paid'}, "
                                     f"{'auto-renew' if r.is_auto_renew else 'manual renewal'}", axis=1)
    df = df.sort_values("pct_churn_30d")
    fig, ax = plt.subplots(figsize=(9, 3.9))
    fig.subplots_adjust(top=0.76)
    bars = ax.barh(df.label, df.pct_churn_30d, color=BLUE, height=0.55)
    for b, (_, r) in zip(bars, df.iterrows()):
        ax.text(b.get_width() + 1.2, b.get_y() + b.get_height() / 2,
                f"{r.pct_churn_30d:.1f}%   ({r.pct_of_expiries:.1f}% of expiries)",
                va="center", fontsize=9.5, color=INK)
    ax.set_xlim(0, 112)
    ax.xaxis.set_visible(False)
    ax.spines["bottom"].set_visible(False)
    ax.tick_params(axis="y", labelsize=10, labelcolor=INK)
    finish(fig, ax, "Churn is driven by how the subscription renews",
           "30-day churn per expiry in normal months (Feb 2015 to Dec 2016, excluding the four "
           "spike months and cancellations).", "03_churn_by_renewal_type.png")


def usage_vs_churn():
    df = pd.read_csv(RESULTS / "q05_engagement_vs_churn.csv")
    bands = ["0 days", "1-2 days", "3-5 days", "6-7 days"]
    manual = df[~df.is_auto_renew].pct_churn.to_numpy()
    auto = df[df.is_auto_renew].pct_churn.to_numpy()
    x = np.arange(len(bands))
    w = 0.36
    fig, ax = plt.subplots(figsize=(9, 4.8))
    fig.subplots_adjust(top=0.8)
    b1 = ax.bar(x - w / 2 - 0.01, manual, w, color=ORANGE, label="Manual renewal")
    b2 = ax.bar(x + w / 2 + 0.01, auto, w, color=BLUE, label="Auto-renew")
    for bars in (b1, b2):
        for b in bars:
            ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 1.2, f"{b.get_height():.1f}%",
                    ha="center", fontsize=9.5, color=INK)
    ax.set_xticks(x)
    ax.set_xticklabels(bands)
    ax.set_xlabel("Active days in the first week of March 2017")
    ax.set_ylim(0, 75)
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:.0f}%")
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines["left"].set_visible(False)
    ax.legend(frameon=False, loc="upper right", labelcolor=INK)
    finish(fig, ax, "Low usage signals churn, but renewal type matters far more",
           "Churn among users whose subscription expired Mar 8 to Mar 31, 2017, by usage in the "
           "week before (official churn label).", "04_usage_vs_churn.png")


def winback():
    df = pd.read_csv(RESULTS / "q07_winback.csv")
    df = df[df.exits > 100]
    days = [60, 90, 180, 365]
    cols = ["pct_back_60d", "pct_back_90d", "pct_back_180d", "pct_back_365d"]
    series = [
        (True, False, "Auto-renew, lapsed without cancelling", BLUE),
        (False, False, "Manual renewal, did not renew", ORANGE),
        (True, True, "Auto-renew, cancelled", AQUA),
    ]
    fig, ax = plt.subplots(figsize=(9.4, 4.8))
    fig.subplots_adjust(top=0.8, right=0.7)
    for auto, cancel, label, color in series:
        r = df[(df.last_auto_renew == auto) & (df.ended_with_cancel == cancel)].iloc[0]
        y = [r[c] for c in cols]
        ax.plot(days, y, color=color, linewidth=2, marker="o", markersize=7,
                markeredgecolor=SURFACE, markeredgewidth=2, label=label)
        ax.annotate(f"{label}\n{y[-1]:.1f}% back within a year", (days[-1], y[-1]),
                    xytext=(10, 0), textcoords="offset points", va="center", fontsize=9, color=INK)
    ax.set_xticks(days)
    ax.set_xticklabels([str(d) for d in days])
    ax.set_xlabel("Days since the subscription ended")
    ax.set_ylim(0, 100)
    ax.set_xlim(40, 380)
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:.0f}%")
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines["left"].set_visible(False)
    finish(fig, ax, "How a subscription ends predicts whether the user comes back",
           "Cumulative % of churned periods followed by a new subscription. "
           "Exits up to Mar 2016, so a full year is observable.", "05_winback.png")


def activation_funnel():
    df = pd.read_csv(RESULTS / "q08_activation.csv")
    n = df.registrations.sum()
    steps = [("Registered", 100.0)]
    for label, col in [("Active 1+ days", "pct_active_1d"),
                       ("Active 3+ days (activated)", "pct_activated_3d"),
                       ("Active 5+ days", "pct_active_5d")]:
        steps.append((label, (df.registrations * df[col]).sum() / n))
    labels = [s[0] for s in steps][::-1]
    values = [s[1] for s in steps][::-1]
    fig, ax = plt.subplots(figsize=(9, 3.9))
    fig.subplots_adjust(top=0.76)
    bars = ax.barh(labels, values, color=BLUE, height=0.55)
    for b, v in zip(bars, values):
        ax.text(b.get_width() + 1.2, b.get_y() + b.get_height() / 2,
                f"{v:.0f}%", va="center", fontsize=9.5, color=INK)
    ax.set_xlim(0, 128)
    ax.xaxis.set_visible(False)
    ax.spines["bottom"].set_visible(False)
    ax.tick_params(axis="y", labelsize=10, labelcolor=INK)
    finish(fig, ax, "Nine in ten new users try the app; four in ten come back a third day",
           f"{n:,} users registered Mar 1 to Mar 24, 2017, by number of active days in their "
           "first seven days.", "06_activation_funnel.png")


if __name__ == "__main__":
    monthly_churn()
    cohort_heatmap()
    churn_by_type()
    usage_vs_churn()
    winback()
    activation_funnel()
