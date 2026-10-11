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
