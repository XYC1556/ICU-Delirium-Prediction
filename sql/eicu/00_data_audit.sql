WITH delirium_records AS (
  SELECT
    patientunitstayid,
    nursingchartoffset,
    nursingchartentryoffset,
    nursingchartcelltypevalname,
    nursingchartcelltypevallabel,
    nursingchartvalue
  FROM `physionet-data.eicu_crd.nursecharting`
  WHERE nursingchartcelltypevallabel = 'Delirium Scale/Score'
)

SELECT *
FROM delirium_records
WHERE patientunitstayid IN (
  SELECT patientunitstayid
  FROM delirium_records
  WHERE nursingchartcelltypevalname = 'Delirium Scale'
    AND UPPER(TRIM(nursingchartvalue)) = 'CAM-ICU'
)
ORDER BY
  patientunitstayid,
  nursingchartoffset,
  nursingchartentryoffset,
  nursingchartcelltypevalname
LIMIT 500;

WITH cam AS (
  SELECT
    patientunitstayid,
    nursingchartoffset,
    MAX(
      CASE
        WHEN nursingchartcelltypevalname = 'Delirium Scale'
          AND UPPER(TRIM(nursingchartvalue)) = 'CAM-ICU'
        THEN 1 ELSE 0
      END
    ) AS is_cam,
    MAX(
      CASE
        WHEN nursingchartcelltypevalname = 'Delirium Score'
        THEN UPPER(TRIM(nursingchartvalue))
      END
    ) AS cam_result
  FROM `physionet-data.eicu_crd.nursecharting`
  WHERE nursingchartcelltypevallabel = 'Delirium Scale/Score'
  GROUP BY patientunitstayid, nursingchartoffset
)

SELECT
  COUNT(*) AS cam_assessments,
  COUNT(DISTINCT patientunitstayid) AS patients_with_cam,
  COUNTIF(cam_result = 'YES') AS positive_assessments,
  COUNTIF(cam_result = 'NO') AS negative_assessments,
  COUNTIF(cam_result IS NULL) AS missing_assessments
FROM cam
WHERE is_cam = 1;

SELECT
  a.day1fio2,
  COUNT(*) AS n
FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

LEFT JOIN
  `physionet-data.eicu_crd.apachepredvar` a
ON c.patientunitstayid = a.patientunitstayid

GROUP BY
  a.day1fio2

ORDER BY
  a.day1fio2;

SELECT
  a.oobventday1,

  CASE
    WHEN a.day1fio2 IS NULL THEN 'NULL'
    WHEN a.day1fio2 = -1 THEN '-1'
    WHEN a.day1fio2 > 0 THEN 'VALID'
    ELSE 'OTHER'
  END AS fio2_status,

  COUNT(*) AS n

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

LEFT JOIN
  `physionet-data.eicu_crd.apachepredvar` a
ON c.patientunitstayid = a.patientunitstayid

GROUP BY
  a.oobventday1,
  fio2_status

ORDER BY
  a.oobventday1,
  fio2_status;

WITH monitoring AS (
  SELECT
    c.patientunitstayid,
    n.nursingchartoffset

  FROM
    `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

  JOIN
    `physionet-data.eicu_crd.nursecharting` n
  ON c.patientunitstayid = n.patientunitstayid

  WHERE n.nursingchartoffset >= 0
    AND n.nursingchartoffset < 1440
)

SELECT
  COUNT(*) AS raw_nursing_rows,

  COUNT(DISTINCT CONCAT(
    CAST(patientunitstayid AS STRING),
    '-',
    CAST(nursingchartoffset AS STRING)
  )) AS unique_monitoring_episodes,

  COUNT(DISTINCT patientunitstayid)
    AS patients_with_monitoring

FROM monitoring;

SELECT
  c.patientunitstayid,
  p.unitadmittime24,
  n.nursingchartoffset,
  n.nursingchartcelltypevallabel,
  n.nursingchartcelltypevalname,
  n.nursingchartvalue,

  TIME_ADD(
    p.unitadmittime24,
    INTERVAL n.nursingchartoffset MINUTE
  ) AS reconstructed_clock_time

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

JOIN
  `physionet-data.eicu_crd.patient` p
ON c.patientunitstayid = p.patientunitstayid

JOIN
  `physionet-data.eicu_crd.nursecharting` n
ON c.patientunitstayid = n.patientunitstayid

WHERE n.nursingchartoffset >= 0
  AND n.nursingchartoffset < 1440

ORDER BY
  c.patientunitstayid,
  n.nursingchartoffset

LIMIT 200;

WITH lab_24h AS (
  SELECT
    l.patientunitstayid,
    l.labresultoffset,
    l.labname,
    l.labid

  FROM
    `physionet-data.eicu_crd.lab` l

  JOIN
    `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c
  ON l.patientunitstayid = c.patientunitstayid

  WHERE l.labresultoffset >= 0
    AND l.labresultoffset < 1440
),

offset_summary AS (
  SELECT
    patientunitstayid,
    labresultoffset,

    COUNT(*) AS rows_at_offset,
    COUNT(DISTINCT labname) AS unique_lab_tests

  FROM lab_24h

  GROUP BY
    patientunitstayid,
    labresultoffset
)

SELECT
  COUNT(*) AS unique_lab_offsets,

  COUNT(DISTINCT patientunitstayid)
    AS patients_with_labs,

  APPROX_QUANTILES(
    rows_at_offset, 100
  )[OFFSET(25)] AS rows_per_offset_p25,

  APPROX_QUANTILES(
    rows_at_offset, 100
  )[OFFSET(50)] AS rows_per_offset_median,

  APPROX_QUANTILES(
    rows_at_offset, 100
  )[OFFSET(75)] AS rows_per_offset_p75,

  APPROX_QUANTILES(
    rows_at_offset, 100
  )[OFFSET(99)] AS rows_per_offset_p99,

  APPROX_QUANTILES(
    unique_lab_tests, 100
  )[OFFSET(50)] AS unique_tests_median,

  MAX(rows_at_offset) AS rows_per_offset_max

FROM offset_summary;

SELECT
  l.labname,
  COUNT(*) AS single_test_episodes

FROM `physionet-data.eicu_crd.lab` l

JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c
ON l.patientunitstayid = c.patientunitstayid

JOIN (
  SELECT
    patientunitstayid,
    labresultoffset
  FROM `physionet-data.eicu_crd.lab`
  WHERE labresultoffset >= 0
    AND labresultoffset < 1440
  GROUP BY
    patientunitstayid,
    labresultoffset
  HAVING COUNT(DISTINCT labname) = 1
) s

ON l.patientunitstayid = s.patientunitstayid
AND l.labresultoffset = s.labresultoffset

WHERE l.labresultoffset >= 0
  AND l.labresultoffset < 1440

GROUP BY l.labname

ORDER BY single_test_episodes DESC

LIMIT 50;

SELECT
  t.treatmentstring,
  COUNT(*) AS records,
  COUNT(DISTINCT t.patientunitstayid) AS patients

FROM
  `physionet-data.eicu_crd.treatment` t

JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c
ON t.patientunitstayid = c.patientunitstayid

WHERE t.treatmentoffset >= 0
  AND t.treatmentoffset < 1440

GROUP BY
  t.treatmentstring

ORDER BY
  records DESC

LIMIT 200;

SELECT
  t.treatmentstring,
  COUNT(*) AS records,
  COUNT(DISTINCT t.patientunitstayid) AS patients

FROM
  `physionet-data.eicu_crd.treatment` t

JOIN
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c
ON t.patientunitstayid = c.patientunitstayid

WHERE t.treatmentoffset >= 0
  AND t.treatmentoffset < 1440

  AND (
    REGEXP_CONTAINS(
      LOWER(t.treatmentstring),
      r'procedures / diagnostics'
    )
    OR REGEXP_CONTAINS(
      LOWER(t.treatmentstring),
      r'radiologic procedures / bronchoscopy'
    )
    OR REGEXP_CONTAINS(
      LOWER(t.treatmentstring),
      r'non-operative procedures'
    )
    OR REGEXP_CONTAINS(
      LOWER(t.treatmentstring),
      r'radiology, diagnostic and procedures'
    )
    OR REGEXP_CONTAINS(
      LOWER(t.treatmentstring),
      r'exploratory surgery'
    )
    OR REGEXP_CONTAINS(
      LOWER(t.treatmentstring),
      r'\|dialysis\|'
    )
  )

GROUP BY
  t.treatmentstring

ORDER BY
  records DESC;

SELECT
  COUNT(*) AS n,
  COUNT(DISTINCT uniquepid) AS unique_patients,
  COUNT(DISTINCT patientunitstayid) AS unique_icu_stays,

  COUNTIF(subsequent_positive = 1) AS positive_outcomes,
  COUNTIF(subsequent_positive = 0) AS negative_outcomes,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(subsequent_positive = 1),
      COUNT(*)
    ),
    2
  ) AS positive_rate_percent,

  COUNTIF(age_numeric < 18) AS age_under_18,

  COUNTIF(gender NOT IN ('Male', 'Female')) AS nonbinary_or_unknown_gender

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort`;

SELECT
  COUNT(*) AS n,
  COUNTIF(acute_physiology_score IS NOT NULL) AS valid_aps,
  COUNTIF(acute_physiology_score IS NULL) AS missing_aps,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(acute_physiology_score IS NOT NULL),
      COUNT(*)
    ),
    2
  ) AS coverage_percent,

  MIN(acute_physiology_score) AS min_aps,
  MAX(acute_physiology_score) AS max_aps

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.aps_24h`;

SELECT
  COUNT(*) AS n,

  COUNTIF(vasopressor_24h = 1)
    AS vasopressor_yes,

  COUNTIF(vasopressor_24h = 0)
    AS vasopressor_no,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(vasopressor_24h = 1),
      COUNT(*)
    ),
    2
  ) AS vasopressor_percent

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.vasopressor_24h`;

WITH monitoring_episodes AS (
  SELECT DISTINCT
    c.patientunitstayid,
    n.nursingchartoffset,

    TIME_ADD(
      p.unitadmittime24,
      INTERVAL n.nursingchartoffset MINUTE
    ) AS clock_time

  FROM
    `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

  JOIN
    `physionet-data.eicu_crd.patient` p
  ON c.patientunitstayid = p.patientunitstayid

  JOIN
    `physionet-data.eicu_crd.nursecharting` n
  ON c.patientunitstayid = n.patientunitstayid

  WHERE n.nursingchartoffset >= 0
    AND n.nursingchartoffset < 1440
),

patient_level AS (
  SELECT
    c.patientunitstayid,

    COUNT(m.nursingchartoffset)
      AS monitoring_episodes_24h,

    COUNTIF(
      m.clock_time >= TIME '00:00:00'
      AND m.clock_time < TIME '06:00:00'
    ) AS nighttime_episodes,

    SAFE_DIVIDE(
      COUNTIF(
        m.clock_time >= TIME '00:00:00'
        AND m.clock_time < TIME '06:00:00'
      ),
      COUNT(m.nursingchartoffset)
    ) AS nighttime_ratio

  FROM
    `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

  LEFT JOIN monitoring_episodes m
  ON c.patientunitstayid = m.patientunitstayid

  GROUP BY c.patientunitstayid
)

SELECT
  COUNT(*) AS n,

  COUNTIF(monitoring_episodes_24h > 0)
    AS patients_with_monitoring,

  COUNTIF(monitoring_episodes_24h = 0)
    AS patients_without_monitoring,

  APPROX_QUANTILES(
    monitoring_episodes_24h, 100
  )[OFFSET(1)] AS episodes_p01,

  APPROX_QUANTILES(
    monitoring_episodes_24h, 100
  )[OFFSET(25)] AS episodes_p25,

  APPROX_QUANTILES(
    monitoring_episodes_24h, 100
  )[OFFSET(50)] AS episodes_median,

  APPROX_QUANTILES(
    monitoring_episodes_24h, 100
  )[OFFSET(75)] AS episodes_p75,

  APPROX_QUANTILES(
    monitoring_episodes_24h, 100
  )[OFFSET(99)] AS episodes_p99,

  MAX(monitoring_episodes_24h)
    AS episodes_max,

  APPROX_QUANTILES(
    nighttime_ratio, 100
  )[OFFSET(25)] AS night_ratio_p25,

  APPROX_QUANTILES(
    nighttime_ratio, 100
  )[OFFSET(50)] AS night_ratio_median,

  APPROX_QUANTILES(
    nighttime_ratio, 100
  )[OFFSET(75)] AS night_ratio_p75

FROM patient_level;

SELECT
  COUNT(*) AS n,

  COUNTIF(laboratory_testing_episodes_24h > 0)
    AS patients_with_lab_testing,

  COUNTIF(glucose_checks_24h > 0)
    AS patients_with_glucose_checks,

  APPROX_QUANTILES(
    laboratory_testing_episodes_24h, 100
  )[OFFSET(25)] AS lab_p25,

  APPROX_QUANTILES(
    laboratory_testing_episodes_24h, 100
  )[OFFSET(50)] AS lab_median,

  APPROX_QUANTILES(
    laboratory_testing_episodes_24h, 100
  )[OFFSET(75)] AS lab_p75,

  APPROX_QUANTILES(
    laboratory_testing_episodes_24h, 100
  )[OFFSET(99)] AS lab_p99,

  MAX(laboratory_testing_episodes_24h)
    AS lab_max,

  APPROX_QUANTILES(
    glucose_checks_24h, 100
  )[OFFSET(25)] AS glucose_p25,

  APPROX_QUANTILES(
    glucose_checks_24h, 100
  )[OFFSET(50)] AS glucose_median,

  APPROX_QUANTILES(
    glucose_checks_24h, 100
  )[OFFSET(75)] AS glucose_p75,

  APPROX_QUANTILES(
    glucose_checks_24h, 100
  )[OFFSET(99)] AS glucose_p99,

  MAX(glucose_checks_24h)
    AS glucose_max

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.lab_process_24h`;

SELECT
  COUNT(*) AS n,

  COUNTIF(input_events_24h > 0)
    AS patients_with_input_events,

  APPROX_QUANTILES(input_events_24h, 100)[OFFSET(25)]
    AS input_p25,

  APPROX_QUANTILES(input_events_24h, 100)[OFFSET(50)]
    AS input_median,

  APPROX_QUANTILES(input_events_24h, 100)[OFFSET(75)]
    AS input_p75,

  APPROX_QUANTILES(input_events_24h, 100)[OFFSET(99)]
    AS input_p99,

  MAX(input_events_24h)
    AS input_max

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.input_process_24h`;

SELECT
  COUNT(*) AS n,

  COUNTIF(procedure_events_24h > 0)
    AS patients_with_procedures,

  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(procedure_events_24h > 0),
      COUNT(*)
    ),
    2
  ) AS procedure_coverage_percent,

  APPROX_QUANTILES(
    procedure_events_24h, 100
  )[OFFSET(25)] AS procedure_p25,

  APPROX_QUANTILES(
    procedure_events_24h, 100
  )[OFFSET(50)] AS procedure_median,

  APPROX_QUANTILES(
    procedure_events_24h, 100
  )[OFFSET(75)] AS procedure_p75,

  APPROX_QUANTILES(
    procedure_events_24h, 100
  )[OFFSET(99)] AS procedure_p99,

  MAX(procedure_events_24h)
    AS procedure_max

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.procedure_process_24h`;

SELECT
  COUNT(*) AS total_rows,

  COUNT(DISTINCT patientunitstayid)
    AS unique_stays,

  COUNTIF(
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
    AND procedure_events_24h IS NOT NULL
  ) AS complete_case_n,

  COUNTIF(
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
    AND procedure_events_24h IS NOT NULL
    AND outcome = 1
  ) AS complete_case_events,

  COUNTIF(nighttime_monitoring_ratio IS NULL)
    AS missing_night_ratio,

  COUNTIF(aps IS NULL)
    AS missing_aps,

  COUNTIF(day1_intubation IS NULL)
    AS missing_intubation

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.model_abc_dataset`;

SELECT
  COUNT(*) AS n,
  COUNTIF(outcome = 1) AS events,
  COUNTIF(outcome = 0) AS non_events,
  ROUND(
    100 * SAFE_DIVIDE(COUNTIF(outcome = 1), COUNT(*)),
    2
  ) AS event_rate_percent
FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.model_abc_complete_case`;

WITH raw_aps AS (
  SELECT c.patientunitstayid, MAX(a.acutephysiologyscore) AS raw_aps
  FROM `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c
  LEFT JOIN `physionet-data.eicu_crd.apachepatientresult` a
    ON c.patientunitstayid = a.patientunitstayid AND a.apacheversion = 'IV'
  GROUP BY c.patientunitstayid
)
SELECT raw_aps, COUNT(*) AS n
FROM raw_aps
GROUP BY raw_aps
ORDER BY raw_aps;
