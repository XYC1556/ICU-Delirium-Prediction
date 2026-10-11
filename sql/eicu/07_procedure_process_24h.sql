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
