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
