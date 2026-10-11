# ICU Delirium Prediction and Cross-Hospital Model Transportability

## Overview

This project investigates the predictive value of first-day clinical
and care-process measures for subsequent documented delirium in
intensive care units.

Using MIMIC-IV and eICU databases, the study evaluates clinical
prediction models and examines their generalisability across hospitals.

## Research Objectives

1. Develop clinical prediction models for subsequent documented ICU delirium.
2. Assess the incremental predictive value of care-process measures.
3. Evaluate model discrimination and calibration.
4. Investigate cross-hospital differences in predictive performance.

## Data Sources

- MIMIC-IV v3.1
- eICU Collaborative Research Database v2.0

The study includes:

- 28,089 ICU patients from MIMIC-IV.
- 10,015 patients from 49 hospitals in eICU.

## Methods

- SQL-based clinical data extraction and cohort construction
- Logistic regression modelling
- Cross-validation and bootstrap resampling
- Leave-one-hospital-out internal-external cross-validation
- Model discrimination and calibration assessment
- Sensitivity analyses

## Tools

- Python
- SQL
- Google BigQuery
- Clinical prediction modelling

## Key Findings

Incremental predictive value observed in pooled analyses was not
consistently reproduced at the hospital level.

Substantial between-hospital heterogeneity was observed in model
discrimination and calibration.

## Research Status

Manuscript under peer review at BMC Medical Informatics and
Decision Making.

## Data Availability

MIMIC-IV and eICU are credentialed-access clinical databases.

Patient-level data are not publicly redistributed in this repository.
Access to the original datasets requires completion of the applicable
training and data-use agreements.

## Author

XIONG YICHENG

MSc in Biomedical Informatics (Analytics Track)

National University of Singapore
