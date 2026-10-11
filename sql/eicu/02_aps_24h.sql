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
