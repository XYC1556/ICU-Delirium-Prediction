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
