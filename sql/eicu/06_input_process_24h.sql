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
