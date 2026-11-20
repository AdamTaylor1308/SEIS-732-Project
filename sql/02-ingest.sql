-- 02-ingest.sql

CREATE SCHEMA IF NOT EXISTS `ust-seis732.ccr_raw` OPTIONS(location = 'US');

CREATE OR REPLACE TABLE `ust-seis732.ccr_raw.nass_cattle_jan1` AS
SELECT
  src.*,                                  -- every source column, unchanged (all STRING)
  CURRENT_TIMESTAMP() AS extracted_at     -- when this copy was made
FROM `bigquery-public-data.usda_nass_agriculture.animals_products` AS src
WHERE commodity_desc = 'CATTLE'
  AND short_desc IN ('CATTLE, COWS, BEEF - INVENTORY',
                     'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY')
  AND reference_period_desc = 'FIRST OF JAN'
  AND source_desc = 'SURVEY'
  AND domaincat_desc = 'NOT SPECIFIED'
  AND agg_level_desc IN ('STATE', 'NATIONAL');

-- Verifying the load. Expected: 10,143 rows total (beef cows 5,126; heifers 5,017), years 1920–2022.
SELECT
  short_desc,
  COUNT(*)                        AS raw_rows,
  MIN(SAFE_CAST(year AS INT64))   AS first_year,
  MAX(SAFE_CAST(year AS INT64))   AS last_year,
  COUNT(DISTINCT state_alpha)     AS geographies,
  MAX(load_time)                  AS newest_source_load_time,
  MAX(extracted_at)               AS extracted_at
FROM `ust-seis732.ccr_raw.nass_cattle_jan1`
GROUP BY ROLLUP(short_desc)
ORDER BY short_desc NULLS LAST;


