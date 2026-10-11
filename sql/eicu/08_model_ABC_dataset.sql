CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.model_abc_dataset`
AS

SELECT
  c.patientunitstayid,
  c.uniquepid,
  c.hospitalid,
  c.wardid,

  c.subsequent_positive AS outcome,

  c.age_numeric AS age,

  CASE
    WHEN c.gender = 'Male' THEN 1
    WHEN c.gender = 'Female' THEN 0
    ELSE NULL
  END AS male,

  a.acute_physiology_score AS aps,

  ap.oobintubday1 AS day1_intubation,
  ap.oobventday1 AS day1_any_ventilation,
  v.vasopressor_24h,

  cp.monitoring_episodes_24h,
  cp.nighttime_monitoring_ratio,

  lp.laboratory_testing_episodes_24h,
  lp.glucose_checks_24h,

  ip.input_events_24h,

  pp.procedure_events_24h

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

LEFT JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.aps_24h` a
ON c.patientunitstayid = a.patientunitstayid

LEFT JOIN
  `physionet-data.eicu_crd.apachepredvar` ap
ON c.patientunitstayid = ap.patientunitstayid

LEFT JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.vasopressor_24h` v
ON c.patientunitstayid = v.patientunitstayid

LEFT JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.care_process_24h` cp
ON c.patientunitstayid = cp.patientunitstayid

LEFT JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.lab_process_24h` lp
ON c.patientunitstayid = lp.patientunitstayid

LEFT JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.input_process_24h` ip
ON c.patientunitstayid = ip.patientunitstayid

LEFT JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.procedure_process_24h` pp
ON c.patientunitstayid = pp.patientunitstayid;

CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.model_abc_complete_case`
AS

SELECT *
FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.model_abc_dataset`

WHERE
  age IS NOT NULL
  AND male IS NOT NULL
  AND aps IS NOT NULL
  AND day1_intubation IS NOT NULL
  AND vasopressor_24h IS NOT NULL
  AND monitoring_episodes_24h IS NOT NULL
  AND nighttime_monitoring_ratio IS NOT NULL
  AND laboratory_testing_episodes_24h IS NOT NULL
  AND glucose_checks_24h IS NOT NULL
  AND input_events_24h IS NOT NULL
  AND procedure_events_24h IS NOT NULL;
