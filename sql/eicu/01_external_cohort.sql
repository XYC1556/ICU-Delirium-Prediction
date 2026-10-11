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
