"""Render manuscript figures from the project analysis outputs."""

from pathlib import Path
import argparse
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score, roc_curve

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.root
    results = root / "analysis" / "Results"
    output = root / "figures"
    output.mkdir(parents=True, exist_ok=True)
    prefix = "mimic_delirium_analysis_"

    def read(name):
        return pd.read_csv(results / f"{prefix}{name}.csv")

    def save(fig, number):
        fig.savefig(output / f"Figure{number}.png", dpi=1200 if number == 1 else 900, facecolor="white")
        plt.close(fig)

    plt.rcParams.update(
        {
            "font.family": "Arial",
            "font.size": 10,
            "lines.linewidth": 1.0,
            "axes.linewidth": 0.8,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "pdf.fonttype": 42,
        }
    )
    flow = read("Cohort_Flow").set_index("step")
    n = lambda step: int(flow.loc[step, "n_stays"])
    patients = int(flow.loc[7, "n_patients"])
    comp = read("Model_Comparison")
    model_n = int(comp.N.iloc[0])
    predictions = read("OOF_Predictions")
    fig, ax = plt.subplots(figsize=(8, 7.6))
    fig.subplots_adjust(left=0.01, right=0.99, bottom=0.015, top=0.99)
    ax.axis("off")
    ax.set(xlim=(0, 1), ylim=(0, 1))
    main_boxes = [
        f"All ICU stays after joins and adult-age filter\n{n(3):,} stays",
        f"ICU stay at least 24 hours\n{n(4):,} stays",
        f"No positive CAM-ICU before 24 hours\n{n(5):,} stays",
        f"Evaluable post-landmark CAM-ICU\n{n(6):,} stays",
        f"First eligible stay per patient\n{patients:,} patients",
        f"Complete-case modeling\n{model_n:,} patients, {int(predictions.delirium.sum()):,} outcomes",
    ]
    exclusions = [
        f"Stay shorter than 24 hours\n{n(3)-n(4):,} stays",
        f"Early positive CAM-ICU\n{n(4)-n(5):,} stays",
        f"No evaluable later CAM-ICU\n{n(5)-n(6):,} stays",
        f"Additional eligible stays\n{n(6)-n(7):,} stays",
        f"Missing predictors\n{patients-model_n:,} patients",
    ]
    ys = np.linspace(0.91, 0.14, 6)
    h = 0.10
    for i, label in enumerate(main_boxes):
        ax.add_patch(
            FancyBboxPatch(
                (0.02, ys[i] - h / 2),
                0.57,
                h,
                boxstyle="round,pad=0.01",
                facecolor="white",
                edgecolor=".4",
            )
        )
        ax.text(0.305, ys[i], label, ha="center", va="center", fontsize=10)
        if i < 5:
            mid = (ys[i] + ys[i + 1]) / 2
            ax.annotate(
                "",
                (0.305, ys[i + 1] + h / 2 + 0.01),
                (0.305, ys[i] - h / 2 - 0.01),
                arrowprops={"arrowstyle": "->", "color": ".4"},
            )
            ax.annotate(
                "",
                (0.65, mid),
                (0.305, mid),
                arrowprops={"arrowstyle": "->", "color": ".4"},
            )
            ax.add_patch(
                FancyBboxPatch(
                    (0.66, mid - 0.045),
                    0.31,
                    0.09,
                    boxstyle="round,pad=0.01",
                    facecolor="white",
                    edgecolor=".4",
                )
            )
            ax.text(0.815, mid, exclusions[i], ha="center", va="center", fontsize=9)
    ax.text(
        0.02,
        0.035,
        "MIMIC-IV version 3.1. Evaluable means a Positive or Negative CAM-ICU record.\nThe required joins and adult-age filter removed no stays.",
        fontsize=9,
    )
    save(fig, 1)
    fig, ax = plt.subplots(figsize=(7, 6))
    for model, color, style in [
        ("A", "#D55E00", ":"),
        ("B", "#0072B2", "--"),
        ("C", "#009E73", "-"),
    ]:
        p = predictions[f"Model_{model}_OOF"]
        x, y, _ = roc_curve(predictions.delirium, p)
        ax.plot(
            x,
            y,
            color=color,
            ls=style,
            lw=2,
            label=f"Model {model}: AUC {roc_auc_score(predictions.delirium,p):.4f}",
        )
    ax.plot([0, 1], [0, 1], ls="--", color=".6", lw=1)
    ax.set(
        xlim=(0, 1),
        ylim=(0, 1),
        xlabel="False-positive rate",
        ylabel="True-positive rate",
    )
    ax.legend(loc="lower right", frameon=False)
    fig.tight_layout()
    save(fig, 2)
    groups = read("Calibration_Groups")
    cal = read("Calibration").iloc[0]
    fig, ax = plt.subplots(figsize=(7, 6))
    ax.plot([0, 1], [0, 1], ls="--", color=".6", label="Perfect calibration")
    ax.plot(
        groups.iloc[:, 0], groups.iloc[:, 1], "-o", color="#0072B2", label="Model C"
    )
    ax.text(
        0.43,
        0.11,
        f"Brier score: {cal.OOF_Brier:.4f}\nCalibration intercept: {cal.Calibration_intercept:.4f}\nCalibration slope: {cal.Calibration_slope:.4f}",
        transform=ax.transAxes,
    )
    ax.set(
        xlim=(0, 1),
        ylim=(0, 1),
        xlabel="Mean predicted probability",
        ylabel="Observed outcome proportion",
    )
    ax.legend(loc="upper left", frameon=False)
    fig.tight_layout()
    save(fig, 3)
    hospitals = pd.read_csv(
        root / "analysis/eICU/results/eICU_IECV_calibration_hospital_results_v1.0.csv"
    )
    hospitals = hospitals.sort_values("Delta_AUC_B_C").reset_index(drop=True)
    fig, (a, b) = plt.subplots(
        1, 2, figsize=(9, 7.2), gridspec_kw={"width_ratios": [1, 1]}
    )
    yy = np.arange(len(hospitals))
    a.axvline(0, color=".5", ls="--", lw=1)
    a.scatter(
        hospitals.Delta_AUC_B_C,
        yy,
        c=np.where(hospitals.Delta_AUC_B_C > 0, "#0072B2", "#D55E00"),
        s=32,
    )
    a.set(
        yticks=yy,
        yticklabels=[f"Hospital {i+1:02d}" for i in yy],
        xlabel="AUC difference (Model C minus B)",
        title="A  Held-out discrimination",
    )
    a.set_xlim(-0.035, 0.025)
    a.invert_yaxis()
    a.tick_params(axis="y", length=0)
    b.plot([0, 0.8], [0, 0.8], ls="--", color=".6", lw=1)
    for name, color, marker in [("B", "#D55E00", "s"), ("C", "#0072B2", "o")]:
        b.scatter(
            hospitals[f"Model {name}_Mean_Predicted_Risk"],
            hospitals.event_rate,
            color=color,
            marker=marker,
            s=35,
            label=f"Model {name}",
            alpha=0.8,
        )
    b.set(
        xlim=(0, 0.8),
        ylim=(0, 0.8),
        xlabel="Hospital mean predicted risk",
        ylabel="Hospital observed outcome proportion",
        title="B  Held-out average risk",
    )
    b.legend(frameon=False, loc="upper left")
    b.set_aspect("equal", adjustable="box")
    fig.tight_layout(w_pad=2.5)
    save(fig, 4)


if __name__ == "__main__":
    main()
