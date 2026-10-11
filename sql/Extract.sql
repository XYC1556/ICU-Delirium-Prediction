-- BigQuery Standard SQL. Replace YOUR_PROJECT_ID with your authorized destination project.
-- Execute the three sections separately; export the first two query results and final eICU table as described in README.md.
-- MIMIC analytic dataset
WITH base_stays AS (

    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.first_careunit,
        i.intime,
        i.outtime,
        i.los,

        age.age,
        p.gender,

        a.admission_type

    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i

    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON i.subject_id = p.subject_id

    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON i.hadm_id = a.hadm_id

    INNER JOIN `physionet-data.mimiciv_3_1_derived.age` AS age
        ON i.hadm_id = age.hadm_id

    WHERE i.los >= 1
      AND age.age >= 18
),

eligible_stays AS (

    SELECT
        b.*

    FROM base_stays AS b

    WHERE NOT EXISTS (

        SELECT 1

        FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c

        WHERE c.stay_id = b.stay_id
          AND c.itemid = 228332
          AND c.value = 'Positive'

          AND c.charttime >= b.intime

          AND c.charttime < DATETIME_ADD(
              b.intime,
              INTERVAL 24 HOUR
          )
    )
),

outcome AS (

    SELECT
        e.stay_id,

        MAX(
            CASE
                WHEN c.value = 'Positive' THEN 1
                ELSE 0
            END
        ) AS delirium

    FROM eligible_stays AS e

    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
        ON e.stay_id = c.stay_id

    WHERE c.itemid = 228332

      AND c.charttime >= DATETIME_ADD(
          e.intime,
          INTERVAL 24 HOUR
      )

      AND c.charttime <= e.outtime

      AND c.value IN (
          'Positive',
          'Negative'
      )

    GROUP BY e.stay_id
),

candidate_cohort AS (

    SELECT
        e.*,
        o.delirium

    FROM eligible_stays AS e

    INNER JOIN outcome AS o
        ON e.stay_id = o.stay_id
),

main_cohort AS (

    SELECT * EXCEPT(rn)

    FROM (

        SELECT
            c.*,

            ROW_NUMBER() OVER (
                PARTITION BY c.subject_id
                ORDER BY c.intime, c.stay_id
            ) AS rn

        FROM candidate_cohort AS c
    )

    WHERE rn = 1
),

vital_counts AS (

    SELECT
        m.stay_id,

        COUNT(
            DISTINCT c.charttime
        ) AS vital_sign_count_24h,

        COUNT(
            DISTINCT IF(
                EXTRACT(HOUR FROM c.charttime) >= 22
                OR EXTRACT(HOUR FROM c.charttime) < 6,
                c.charttime,
                NULL
            )
        ) AS night_vital_count_24h

    FROM main_cohort AS m

    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
        ON m.stay_id = c.stay_id

    WHERE c.charttime >= m.intime

      AND c.charttime < DATETIME_ADD(
          m.intime,
          INTERVAL 24 HOUR
      )

      AND c.itemid IN (
          220045,
          220210,
          223761,
          223762,
          220277,
          220179,
          220180,
          220181
      )

    GROUP BY m.stay_id
),

lab_specimen_counts AS (

    SELECT
        m.stay_id,

        COUNT(
            DISTINCT l.specimen_id
        ) AS lab_specimen_count_24h

    FROM main_cohort AS m

    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l

        ON m.hadm_id = l.hadm_id

        AND l.charttime >= m.intime

        AND l.charttime < DATETIME_ADD(
            m.intime,
            INTERVAL 24 HOUR
        )

        AND l.specimen_id IS NOT NULL

    GROUP BY m.stay_id
),

glucose_counts AS (

    SELECT
        m.stay_id,

        COUNT(c.itemid)
            AS glucose_check_count_24h

    FROM main_cohort AS m

    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c

        ON m.stay_id = c.stay_id

        AND c.charttime >= m.intime

        AND c.charttime < DATETIME_ADD(
            m.intime,
            INTERVAL 24 HOUR
        )

        AND c.itemid = 225664

    GROUP BY m.stay_id
),

input_event_counts AS (

    SELECT
        m.stay_id,

        COUNT(inp.stay_id)
            AS input_event_count_24h

    FROM main_cohort AS m

    LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS inp

        ON m.stay_id = inp.stay_id

        AND inp.starttime >= m.intime

        AND inp.starttime < DATETIME_ADD(
            m.intime,
            INTERVAL 24 HOUR
        )

    GROUP BY m.stay_id
),

procedure_counts AS (

    SELECT
        m.stay_id,

        COUNT(pr.stay_id)
            AS procedure_count_24h

    FROM main_cohort AS m

    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pr

        ON m.stay_id = pr.stay_id

        AND pr.starttime >= m.intime

        AND pr.starttime < DATETIME_ADD(
            m.intime,
            INTERVAL 24 HOUR
        )

    GROUP BY m.stay_id
),

sofa_ranked AS (

    SELECT
        m.stay_id,
        s.sofa_24hours,

        ROW_NUMBER() OVER (
            PARTITION BY m.stay_id
            ORDER BY s.endtime DESC
        ) AS rn

    FROM main_cohort AS m

    INNER JOIN `physionet-data.mimiciv_3_1_derived.sofa` AS s
        ON m.stay_id = s.stay_id

    WHERE s.starttime >= m.intime

      AND s.endtime <= DATETIME_ADD(
          m.intime,
          INTERVAL 24 HOUR
      )
),

sofa_24h AS (

    SELECT
        stay_id,
        sofa_24hours

    FROM sofa_ranked

    WHERE rn = 1
),

ventilation_24h AS (

    SELECT
        m.stay_id,

        MAX(
            CASE
                WHEN v.ventilation_status = 'InvasiveVent'
                THEN 1
                ELSE 0
            END
        ) AS mechanical_ventilation

    FROM main_cohort AS m

    LEFT JOIN `physionet-data.mimiciv_3_1_derived.ventilation` AS v

        ON m.stay_id = v.stay_id

        AND v.starttime < DATETIME_ADD(
            m.intime,
            INTERVAL 24 HOUR
        )

        AND v.endtime > m.intime

    GROUP BY m.stay_id
),

vasopressor_24h AS (

    SELECT
        m.stay_id,

        MAX(
            CASE
                WHEN va.norepinephrine IS NOT NULL
                  OR va.epinephrine IS NOT NULL
                  OR va.dopamine IS NOT NULL
                  OR va.phenylephrine IS NOT NULL
                  OR va.vasopressin IS NOT NULL
                THEN 1
                ELSE 0
            END
        ) AS vasopressor_use

    FROM main_cohort AS m

    LEFT JOIN `physionet-data.mimiciv_3_1_derived.vasoactive_agent` AS va

        ON m.stay_id = va.stay_id

        AND va.starttime < DATETIME_ADD(
            m.intime,
            INTERVAL 24 HOUR
        )

        AND va.endtime > m.intime

    GROUP BY m.stay_id
)

SELECT
    m.stay_id,
    m.subject_id,
    m.hadm_id,

    m.age,
    m.gender,

    m.first_careunit,
    m.admission_type,

    m.delirium,

    s.sofa_24hours,

    COALESCE(
        vent.mechanical_ventilation,
        0
    ) AS mechanical_ventilation,

    COALESCE(
        vaso.vasopressor_use,
        0
    ) AS vasopressor_use,

    COALESCE(
        v.vital_sign_count_24h,
        0
    ) AS vital_sign_count_24h,

    ROUND(
        SAFE_DIVIDE(
            v.night_vital_count_24h,
            v.vital_sign_count_24h
        ),
        3
    ) AS night_vital_ratio,

    COALESCE(
        lab.lab_specimen_count_24h,
        0
    ) AS lab_specimen_count_24h,

    COALESCE(
        g.glucose_check_count_24h,
        0
    ) AS glucose_check_count_24h,

    COALESCE(
        inp.input_event_count_24h,
        0
    ) AS input_event_count_24h,

    COALESCE(
        pr.procedure_count_24h,
        0
    ) AS procedure_count_24h

FROM main_cohort AS m

LEFT JOIN sofa_24h AS s
    ON m.stay_id = s.stay_id

LEFT JOIN ventilation_24h AS vent
    ON m.stay_id = vent.stay_id

LEFT JOIN vasopressor_24h AS vaso
    ON m.stay_id = vaso.stay_id

LEFT JOIN vital_counts AS v
    ON m.stay_id = v.stay_id

LEFT JOIN lab_specimen_counts AS lab
    ON m.stay_id = lab.stay_id

LEFT JOIN glucose_counts AS g
    ON m.stay_id = g.stay_id

LEFT JOIN input_event_counts AS inp
    ON m.stay_id = inp.stay_id

LEFT JOIN procedure_counts AS pr
    ON m.stay_id = pr.stay_id

ORDER BY m.stay_id;

-- MIMIC cohort counts for Cohort_Flow_Counts.csv
WITH source_stays AS (SELECT subject_id, stay_id FROM `physionet-data.mimiciv_3_1_icu.icustays`),
joined_stays AS (

    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.first_careunit,
        i.intime,
        i.outtime,
        i.los,

        age.age,
        p.gender,

        a.admission_type

    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i

    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON i.subject_id = p.subject_id

    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON i.hadm_id = a.hadm_id

    INNER JOIN `physionet-data.mimiciv_3_1_derived.age` AS age
        ON i.hadm_id = age.hadm_id


),


adult_stays AS (SELECT * FROM joined_stays WHERE age >= 18),
base_stays AS (SELECT * FROM adult_stays WHERE los >= 1),
eligible_stays AS (

    SELECT
        b.*

    FROM base_stays AS b

    WHERE NOT EXISTS (

        SELECT 1

        FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c

        WHERE c.stay_id = b.stay_id
          AND c.itemid = 228332
          AND c.value = 'Positive'

          AND c.charttime >= b.intime

          AND c.charttime < DATETIME_ADD(
              b.intime,
              INTERVAL 24 HOUR
          )
    )
),

outcome AS (

    SELECT
        e.stay_id,

        MAX(
            CASE
                WHEN c.value = 'Positive' THEN 1
                ELSE 0
            END
        ) AS delirium

    FROM eligible_stays AS e

    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
        ON e.stay_id = c.stay_id

    WHERE c.itemid = 228332

      AND c.charttime >= DATETIME_ADD(
          e.intime,
          INTERVAL 24 HOUR
      )

      AND c.charttime <= e.outtime

      AND c.value IN (
          'Positive',
          'Negative'
      )

    GROUP BY e.stay_id
),

candidate_cohort AS (

    SELECT
        e.*,
        o.delirium

    FROM eligible_stays AS e

    INNER JOIN outcome AS o
        ON e.stay_id = o.stay_id
),

main_cohort AS (

    SELECT * EXCEPT(rn)

    FROM (

        SELECT
            c.*,

            ROW_NUMBER() OVER (
                PARTITION BY c.subject_id
                ORDER BY c.intime, c.stay_id
            ) AS rn

        FROM candidate_cohort AS c
    )

    WHERE rn = 1
)
SELECT step, stage, n_rows, n_stays, n_patients,
    LAG(n_stays) OVER (ORDER BY step) - n_stays AS stays_removed_from_previous_step,
    final_delirium_cases
FROM (
SELECT 1 AS step, 'All ICU stays' AS stage, COUNT(*) AS n_rows, COUNT(DISTINCT stay_id) AS n_stays, COUNT(DISTINCT subject_id) AS n_patients, CAST(NULL AS INT64) AS final_delirium_cases FROM source_stays
UNION ALL
SELECT 2 AS step, 'After required table joins' AS stage, COUNT(*) AS n_rows, COUNT(DISTINCT stay_id) AS n_stays, COUNT(DISTINCT subject_id) AS n_patients, CAST(NULL AS INT64) AS final_delirium_cases FROM joined_stays
UNION ALL
SELECT 3 AS step, 'Age >= 18 years' AS stage, COUNT(*) AS n_rows, COUNT(DISTINCT stay_id) AS n_stays, COUNT(DISTINCT subject_id) AS n_patients, CAST(NULL AS INT64) AS final_delirium_cases FROM adult_stays
UNION ALL
SELECT 4 AS step, 'ICU stay >= 24 hours' AS stage, COUNT(*) AS n_rows, COUNT(DISTINCT stay_id) AS n_stays, COUNT(DISTINCT subject_id) AS n_patients, CAST(NULL AS INT64) AS final_delirium_cases FROM base_stays
UNION ALL
SELECT 5 AS step, 'No documented CAM-ICU positive before 24 hours' AS stage, COUNT(*) AS n_rows, COUNT(DISTINCT stay_id) AS n_stays, COUNT(DISTINCT subject_id) AS n_patients, CAST(NULL AS INT64) AS final_delirium_cases FROM eligible_stays
UNION ALL
SELECT 6 AS step, 'At least one evaluable CAM-ICU after 24 hours' AS stage, COUNT(*) AS n_rows, COUNT(DISTINCT stay_id) AS n_stays, COUNT(DISTINCT subject_id) AS n_patients, CAST(NULL AS INT64) AS final_delirium_cases FROM candidate_cohort
UNION ALL
SELECT 7 AS step, 'First eligible ICU stay per patient' AS stage, COUNT(*) AS n_rows, COUNT(DISTINCT stay_id) AS n_stays, COUNT(DISTINCT subject_id) AS n_patients, SUM(delirium) AS final_delirium_cases FROM main_cohort
)
ORDER BY step;

-- eICU extraction stages in execution order
CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort`
AS

WITH cam_records AS (
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
          AND UPPER(TRIM(nursingchartvalue)) IN ('YES', 'NO')
        THEN UPPER(TRIM(nursingchartvalue))
      END
    ) AS cam_result

  FROM `physionet-data.eicu_crd.nursecharting`
  WHERE nursingchartcelltypevallabel = 'Delirium Scale/Score'

  GROUP BY
    patientunitstayid,
    nursingchartoffset
),

cam_assessments AS (
  SELECT
    patientunitstayid,
    nursingchartoffset,
    cam_result
  FROM cam_records
  WHERE is_cam = 1
    AND cam_result IN ('YES', 'NO')
),

adult_patient AS (
  SELECT
    *,
    CASE
      WHEN age = '> 89' THEN 90
      WHEN SAFE_CAST(age AS INT64) IS NOT NULL
        THEN SAFE_CAST(age AS INT64)
      ELSE NULL
    END AS age_numeric

  FROM `physionet-data.eicu_crd.patient`
),

stay_level AS (
  SELECT
    p.patientunitstayid,
    p.patienthealthsystemstayid,
    p.uniquepid,
    p.hospitalid,
    p.wardid,
    p.unitvisitnumber,
    p.unitdischargeoffset,

    p.age AS age_original,
    p.age_numeric,
    p.gender,
    p.admissionweight,

    MAX(
      CASE
        WHEN c.nursingchartoffset >= 0
          AND c.nursingchartoffset < 1440
          AND c.cam_result = 'YES'
        THEN 1 ELSE 0
      END
    ) AS early_positive,

    MAX(
      CASE
        WHEN c.nursingchartoffset >= 1440
          AND c.nursingchartoffset <= p.unitdischargeoffset
          AND c.cam_result IN ('YES', 'NO')
        THEN 1 ELSE 0
      END
    ) AS post_landmark_evaluable,

    MAX(
      CASE
        WHEN c.nursingchartoffset >= 1440
          AND c.nursingchartoffset <= p.unitdischargeoffset
          AND c.cam_result = 'YES'
        THEN 1 ELSE 0
      END
    ) AS subsequent_positive

  FROM adult_patient p

  LEFT JOIN cam_assessments c
    ON p.patientunitstayid = c.patientunitstayid

  WHERE p.unitdischargeoffset >= 1440
    AND p.age_numeric >= 18

  GROUP BY
    p.patientunitstayid,
    p.patienthealthsystemstayid,
    p.uniquepid,
    p.hospitalid,
    p.wardid,
    p.unitvisitnumber,
    p.unitdischargeoffset,
    p.age,
    p.age_numeric,
    p.gender,
    p.admissionweight
),

eligible AS (
  SELECT *
  FROM stay_level
  WHERE early_positive = 0
    AND post_landmark_evaluable = 1
),

first_eligible AS (
  SELECT *
  FROM eligible

  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY uniquepid
    ORDER BY unitvisitnumber, patientunitstayid
  ) = 1
)

SELECT
  patientunitstayid,
  patienthealthsystemstayid,
  uniquepid,
  hospitalid,
  wardid,
  unitvisitnumber,
  unitdischargeoffset,
  age_original,
  age_numeric,
  gender,
  admissionweight,
  subsequent_positive

FROM first_eligible;

CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.aps_24h`
AS

SELECT
  c.patientunitstayid,

  CASE
    WHEN MAX(a.acutephysiologyscore) >= 0
    THEN MAX(a.acutephysiologyscore)
    ELSE NULL
  END AS acute_physiology_score

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

LEFT JOIN
  `physionet-data.eicu_crd.apachepatientresult` a
ON c.patientunitstayid = a.patientunitstayid
AND a.apacheversion = 'IV'

GROUP BY
  c.patientunitstayid;

CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.vasopressor_24h`
AS

SELECT
  c.patientunitstayid,

  MAX(
    CASE
      WHEN i.patientunitstayid IS NOT NULL
      THEN 1
      ELSE 0
    END
  ) AS vasopressor_24h

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

LEFT JOIN
  `physionet-data.eicu_crd.infusiondrug` i
ON c.patientunitstayid = i.patientunitstayid

AND i.infusionoffset >= 0
AND i.infusionoffset < 1440

AND REGEXP_CONTAINS(
  LOWER(i.drugname),
  r'norepi|norepinephrine|levophed|epinephrine|adrenaline|dopamine|phenylephrine|neosynephrine|neo-synephrine|vasopressin'
)

GROUP BY
  c.patientunitstayid;

CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.care_process_24h`
AS

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

monitoring_summary AS (
  SELECT
    patientunitstayid,

    COUNT(*) AS monitoring_episodes_24h,

    COUNTIF(
      clock_time >= TIME '00:00:00'
      AND clock_time < TIME '06:00:00'
    ) AS nighttime_monitoring_episodes,

    SAFE_DIVIDE(
      COUNTIF(
        clock_time >= TIME '00:00:00'
        AND clock_time < TIME '06:00:00'
      ),
      COUNT(*)
    ) AS nighttime_monitoring_ratio

  FROM monitoring_episodes

  GROUP BY patientunitstayid
)

SELECT
  c.patientunitstayid,

  COALESCE(m.monitoring_episodes_24h, 0)
    AS monitoring_episodes_24h,

  COALESCE(m.nighttime_monitoring_episodes, 0)
    AS nighttime_monitoring_episodes,

  m.nighttime_monitoring_ratio

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

LEFT JOIN monitoring_summary m
ON c.patientunitstayid = m.patientunitstayid;

CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.lab_process_24h`
AS

WITH lab_summary AS (
  SELECT
    c.patientunitstayid,

    COUNT(
      DISTINCT l.labresultoffset
    ) AS laboratory_testing_episodes_24h,

    COUNTIF(
      LOWER(TRIM(l.labname)) = 'bedside glucose'
    ) AS glucose_checks_24h

  FROM
    `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

  LEFT JOIN
    `physionet-data.eicu_crd.lab` l
  ON c.patientunitstayid = l.patientunitstayid
  AND l.labresultoffset >= 0
  AND l.labresultoffset < 1440

  GROUP BY
    c.patientunitstayid
)

SELECT *
FROM lab_summary;

CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.input_process_24h`
AS

SELECT
  c.patientunitstayid,

  COUNTIF(
    i.patientunitstayid IS NOT NULL
    AND STRPOS(i.cellpath, '|I&O|Intake (ml)|') > 0
  ) AS input_events_24h

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

LEFT JOIN
  `physionet-data.eicu_crd.intakeoutput` i
ON c.patientunitstayid = i.patientunitstayid
AND i.intakeoutputoffset >= 0
AND i.intakeoutputoffset < 1440

GROUP BY c.patientunitstayid;

CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.eicu_delirium_validation.procedure_process_24h`
AS

SELECT
  c.patientunitstayid,

  COUNTIF(
    t.patientunitstayid IS NOT NULL
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
  ) AS procedure_events_24h

FROM
  `YOUR_PROJECT_ID.eicu_delirium_validation.external_cohort` c

LEFT JOIN
  `physionet-data.eicu_crd.treatment` t
ON c.patientunitstayid = t.patientunitstayid
AND t.treatmentoffset >= 0
AND t.treatmentoffset < 1440

GROUP BY
  c.patientunitstayid;

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
