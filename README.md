# ICU Delirium Prediction and Cross-Hospital Model Transportability

**Author:** XIONG YICHENG — MSc Biomedical Informatics, National University of Singapore

## Overview
Research code for analysing the incremental predictive value of first-day care-process measures for subsequently documented ICU delirium, and assessing model performance and transportability across hospitals using MIMIC-IV v3.1 and eICU v2.0.

## Project structure
- `sql/Extract.sql`: SQL extraction for MIMIC-IV / study cohorts.
- `sql/eicu/`: eICU cohort selection, data audits, feature tables and analytical dataset queries.
- `src/Analysis.ipynb`: Python modelling/analysis notebook (outputs removed).
- `src/Figures.py`: plotting scripts.
- `src/eICU_transportability_analysis_v1.0.py`: cross-hospital analysis, calibration and validation.

## Execution and limitations
The scripts are taken from the actual research project. They have **not been independently rerun or validated** in this public release. They require approved access to the relevant PhysioNet databases, authorized BigQuery resources, and locally prepared patient-level data. Some original relative paths expect the author's local project layout and will need adjustment; this repository does not supply restricted input data. SQL for the eICU work uses `YOUR_PROJECT_ID` as a placeholder in place of the original Google Cloud project identifier. The eICU SQL workflow may need queries executed in dependency order; see the numeric prefixes, with `00_data_audit.sql` used for auditing.

No MIMIC-IV/eICU patient-level datasets or patient-level model predictions are distributed here. Access must comply with the PhysioNet credentialing and data-use agreements. Do not publish actual query outputs, patient identifiers, tokens, or other restricted information.

## Methods
Nested logistic regression, cross-validation, bootstrap resampling, discrimination and calibration assessment, leave-one-hospital-out internal-external validation, and sensitivity analyses.

## Publications
Manuscript status should be checked against the latest submission record before referencing it in applications.
