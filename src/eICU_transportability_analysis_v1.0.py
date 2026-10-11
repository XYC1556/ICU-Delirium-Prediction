"""Within-eICU model development and leave-one-hospital-out evaluation."""

from pathlib import Path
import hashlib
import platform
import warnings
from importlib.metadata import version

import numpy as np
import pandas as pd
import statsmodels.api as sm
from scipy.stats import spearmanr
from sklearn.exceptions import ConvergenceWarning
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import brier_score_loss, roc_auc_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from threadpoolctl import threadpool_limits

ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "data" / "eICU_model_ABC_complete_case_v1.0.csv"
RESULTS_DIR = ROOT / "results"
MODEL_A = ["age", "male", "aps"]
MODEL_B = MODEL_A + ["day1_intubation", "vasopressor_24h"]
CARE_PROCESS = [
    "monitoring_episodes_24h",
    "nighttime_monitoring_ratio",
    "laboratory_testing_episodes_24h",
    "glucose_checks_24h",
    "input_events_24h",
    "procedure_events_24h",
]
MODELS = {"Model A": MODEL_A, "Model B": MODEL_B, "Model C": MODEL_B + CARE_PROCESS}
SEED = 20260907
N_BOOT = 1000


def build_model():
    return make_pipeline(
        StandardScaler(),
        LogisticRegression(C=np.inf, solver="lbfgs", max_iter=5000, tol=1e-8),
    )


def fit_predict(train, test, variables):
    model = build_model()
    model.fit(train[variables], train["outcome"])
    return model, model.predict_proba(test[variables])[:, 1]


def calibration(y, p):
    logit = np.log(np.clip(p, 1e-15, 1 - 1e-15) / (1 - np.clip(p, 1e-15, 1 - 1e-15)))
    intercept = sm.GLM(
        y, np.ones((len(y), 1)), offset=logit, family=sm.families.Binomial()
    ).fit()
    slope = sm.GLM(y, sm.add_constant(logit), family=sm.families.Binomial()).fit()
    if not intercept.converged or not slope.converged:
        raise RuntimeError("Calibration model did not converge.")
    return float(intercept.params[0]), float(slope.params[1])


def metrics(y, p):
    return {"AUC": roc_auc_score(y, p), "Brier": brier_score_loss(y, p)}


def summarize(frame, columns):
    return pd.DataFrame(
        [
            {
                "Metric": c,
                "N_Hospitals": len(frame),
                "Median": frame[c].median(),
                "P25": frame[c].quantile(0.25),
                "P75": frame[c].quantile(0.75),
                "Min": frame[c].min(),
                "Max": frame[c].max(),
            }
            for c in columns
        ]
    )


def save(frame, name):
    frame.to_csv(RESULTS_DIR / f"eICU_{name}_v1.0.csv", index=False)


def evaluate_hospitals(df, models, threshold):
    counts = df.groupby("hospitalid").outcome.agg(["size", "sum"])
    eligible = counts.index[
        (counts["sum"] >= threshold) & (counts["size"] - counts["sum"] >= threshold)
    ]
    records = []
    for hospital in eligible:
        train = df.loc[df.hospitalid != hospital]
        test = df.loc[df.hospitalid == hospital]
        y = test.outcome.to_numpy()
        row = {
            "hospitalid": hospital,
            "n": len(test),
            "events": int(y.sum()),
            "non_events": int(len(y) - y.sum()),
            "event_rate": y.mean(),
        }
        for name, variables in models.items():
            _, p = fit_predict(train, test, variables)
            row.update({f"{name}_{k}": v for k, v in metrics(y, p).items()})
            intercept, slope = calibration(y, p)
            row[f"{name}_Calibration_Intercept"] = intercept
            row[f"{name}_Calibration_Slope"] = slope
            row[f"{name}_Mean_Predicted_Risk"] = p.mean()
        row["Delta_AUC_A_B"] = row["Model B_AUC"] - row["Model A_AUC"]
        row["Delta_AUC_B_C"] = row["Model C_AUC"] - row["Model B_AUC"]
        row["Delta_Brier_C_minus_B"] = row["Model C_Brier"] - row["Model B_Brier"]
        records.append(row)
    return pd.DataFrame(records)


def main():
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    warnings.simplefilter("error", ConvergenceWarning)
    df = pd.read_csv(DATA_PATH)
    required = ["outcome", "hospitalid", "day1_any_ventilation"] + MODELS["Model C"]
    if (
        df[required].isna().any().any()
        or not np.isfinite(df[required].to_numpy()).all()
    ):
        raise ValueError("Missing or nonfinite analysis values.")
    for column in ["patientunitstayid", "uniquepid"]:
        if df[column].isna().any() or not df[column].is_unique:
            raise ValueError(f"Nonunique or missing {column}.")
    for column in [
        "outcome",
        "male",
        "day1_intubation",
        "day1_any_ventilation",
        "vasopressor_24h",
    ]:
        if not df[column].isin([0, 1]).all():
            raise ValueError(f"Invalid binary values in {column}.")
    if len(df) != 10015 or df.outcome.sum() != 1688 or df.hospitalid.nunique() != 49:
        raise ValueError("Unexpected cohort counts.")
    y = df.outcome.to_numpy()
    apparent, fitted = {}, {}
    for name, variables in MODELS.items():
        fitted[name], p = fit_predict(df, df, variables)
        apparent[name] = metrics(y, p)
    rng = np.random.default_rng(SEED)
    draws = []
    for b in range(N_BOOT):
        sample = df.iloc[rng.integers(0, len(df), len(df))]
        row = {"iteration": b + 1}
        for name, variables in MODELS.items():
            model, p_test = fit_predict(sample, df, variables)
            p_boot = model.predict_proba(sample[variables])[:, 1]
            boot, test = metrics(sample.outcome, p_boot), metrics(y, p_test)
            for metric in ["AUC", "Brier"]:
                key = metric.lower()
                row[f"{name}_{key}_boot"] = boot[metric]
                row[f"{name}_{key}_test"] = test[metric]
                sign = 1 if metric == "AUC" else -1
                row[f"{name}_{key}_optimism"] = sign * (boot[metric] - test[metric])
        for a, bname, tag in [
            ("Model A", "Model B", "A_B"),
            ("Model B", "Model C", "B_C"),
        ]:
            for kind in ["boot", "test"]:
                row[f"delta_auc_{tag}_{kind}"] = (
                    row[f"{bname}_auc_{kind}"] - row[f"{a}_auc_{kind}"]
                )
        draws.append(row)
    boot = pd.DataFrame(draws)
    save(boot, "bootstrap_draws")
    corrected = []
    for name, variables in MODELS.items():
        row = {
            "Model": name,
            "N": len(df),
            "Events": int(y.sum()),
            "Hospitals": df.hospitalid.nunique(),
        }
        for metric in ["AUC", "Brier"]:
            optimism = boot[f"{name}_{metric.lower()}_optimism"].mean()
            row[f"Apparent_{metric}"] = apparent[name][metric]
            row[f"Mean_{metric}_Optimism"] = optimism
            row[f"Corrected_{metric}"] = (
                apparent[name][metric] + (-1 if metric == "AUC" else 1) * optimism
            )
        scaler, model = fitted[name].steps[0][1], fitted[name].steps[1][1]
        raw_coef = model.coef_[0] / scaler.scale_
        row["Coefficient_const"] = model.intercept_[0] - np.dot(raw_coef, scaler.mean_)
        row.update({f"Coefficient_{v}": c for v, c in zip(variables, raw_coef)})
        row.update(
            {
                "Bootstrap_replicates": N_BOOT,
                "Seed": SEED,
                "Penalty": "none",
                "Input_SHA256": hashlib.sha256(DATA_PATH.read_bytes()).hexdigest(),
                "Python": platform.python_version(),
                "Software": ", ".join(
                    f"{m} {version(m)}"
                    for m in ["numpy", "pandas", "scipy", "scikit-learn", "statsmodels"]
                ),
            }
        )
        corrected.append(row)
    save(pd.DataFrame(corrected), "bootstrap_corrected_performance")
    deltas = []
    for a, bname, tag in [("Model A", "Model B", "A_B"), ("Model B", "Model C", "B_C")]:
        delta = apparent[bname]["AUC"] - apparent[a]["AUC"]
        optimism = (
            boot[f"delta_auc_{tag}_boot"] - boot[f"delta_auc_{tag}_test"]
        ).mean()
        samples = boot[f"delta_auc_{tag}_boot"]
        deltas.append(
            {
                "Comparison": f"{a} to {bname}",
                "Apparent_Delta_AUC": delta,
                "Mean_Optimism": optimism,
                "Corrected_Delta_AUC": delta - optimism,
                "Bootstrap_Median_Delta_AUC": samples.median(),
                "Bootstrap_P2.5": samples.quantile(0.025),
                "Bootstrap_P97.5": samples.quantile(0.975),
                "Percentile_interpretation": "Distribution of resampled apparent increments, not a CI for the corrected increment",
            }
        )
    save(pd.DataFrame(deltas), "delta_AUC_bootstrap")
    all_hospitals = evaluate_hospitals(df, MODELS, 10)
    primary = all_hospitals.loc[
        (all_hospitals.events >= 20) & (all_hospitals.non_events >= 20)
    ].copy()
    auc_columns = [f"Model {m}_AUC" for m in "ABC"] + ["Delta_AUC_A_B", "Delta_AUC_B_C"]
    save(primary, "IECV_hospital_results")
    save(summarize(primary, auc_columns), "IECV_summary")
    save(all_hospitals, "IECV_threshold10_hospital_results")
    save(summarize(all_hospitals, auc_columns), "IECV_threshold10_summary")
    comparison = []
    for threshold, frame in [(20, primary), (10, all_hospitals)]:
        comparison.append(
            {
                "Minimum_events_and_non_events": threshold,
                "Hospitals": len(frame),
                "Patients": int(frame.n.sum()),
                "Events": int(frame.events.sum()),
                "Median_Delta_AUC_B_C": frame.Delta_AUC_B_C.median(),
                "P25": frame.Delta_AUC_B_C.quantile(0.25),
                "P75": frame.Delta_AUC_B_C.quantile(0.75),
                "Positive_hospitals": int((frame.Delta_AUC_B_C > 0).sum()),
            }
        )
    save(pd.DataFrame(comparison), "IECV_threshold20_vs_10")
    save(primary, "IECV_calibration_hospital_results")
    cal_columns = [
        f"Model {m}_{metric}"
        for metric in [
            "AUC",
            "Brier",
            "Calibration_Intercept",
            "Calibration_Slope",
            "Mean_Predicted_Risk",
        ]
        for m in "BC"
    ] + ["Delta_AUC_B_C", "Delta_Brier_C_minus_B"]
    save(summarize(primary, cal_columns), "IECV_calibration_summary")
    save(
        summarize(
            primary,
            [
                "event_rate",
                "Model B_Mean_Predicted_Risk",
                "Model C_Mean_Predicted_Risk",
            ],
        ),
        "IECV_observed_vs_predicted_risk",
    )
    correlations = []
    for col in [
        "Model B_AUC",
        "Model C_AUC",
        "Delta_AUC_B_C",
        "Delta_Brier_C_minus_B",
        "Model B_Calibration_Slope",
        "Model C_Calibration_Slope",
    ]:
        r, p = spearmanr(primary.event_rate, primary[col])
        correlations.append(
            {"Metric": col, "Spearman_rho_with_event_rate": r, "P_value": p}
        )
    save(pd.DataFrame(correlations), "IECV_heterogeneity_correlations")
    sensitivity = {
        k: [("day1_any_ventilation" if v == "day1_intubation" else v) for v in values]
        for k, values in MODELS.items()
    }
    sens = evaluate_hospitals(df, sensitivity, 20)
    save(sens, "sensitivity_anyVent_IECV_hospitals")
    save(summarize(sens, auc_columns), "sensitivity_anyVent_IECV_summary")
    pooled = []
    for name, variables in sensitivity.items():
        _, p = fit_predict(df, df, variables)
        pooled.append({"Model": name, **metrics(y, p)})
    save(pd.DataFrame(pooled), "sensitivity_anyVent_pooled")
    save(
        pd.DataFrame(
            [
                {
                    "Specification": label,
                    "Hospitals": len(frame),
                    "Median_Delta_AUC_B_C": frame.Delta_AUC_B_C.median(),
                    "P25": frame.Delta_AUC_B_C.quantile(0.25),
                    "P75": frame.Delta_AUC_B_C.quantile(0.75),
                    "Positive_hospitals": int((frame.Delta_AUC_B_C > 0).sum()),
                }
                for label, frame in [
                    ("Day-one intubation", primary),
                    ("Any day-one ventilation", sens),
                ]
            ]
        ),
        "primary_vs_anyVent_sensitivity",
    )
    print(
        f"Completed {N_BOOT} bootstrap replicates and hospital validation in {len(primary)} primary hospitals."
    )


if __name__ == "__main__":
    with threadpool_limits(limits=1):
        main()
