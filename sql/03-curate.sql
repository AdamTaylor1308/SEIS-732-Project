-- 03-curate.sql
-- Raw -> Curated: dimensions with surrogate keys, then the Jan 1 inventory fact.
-- Processing location: US. Every statement uses CREATE OR REPLACE, so a rerun rebuilds Curated from Raw.
-- Requires: ust-seis732.ccr_raw.nass_cattle_jan1 (02-ingest.sql).

CREATE SCHEMA IF NOT EXISTS `ust-seis732.ccr_curated` OPTIONS(location = 'US');

-- dim_state: 50 states + one national row (FIPS 99, 'US TOTAL').
-- FIPS codes are stored as unpadded text ('1', '10', '2'), so sort them as numbers.
-- The same input always gives the same keys: AL = 1 ... WY = 50, US = 51.
CREATE OR REPLACE TABLE `ust-seis732.ccr_curated.dim_state` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SAFE_CAST(state_fips_code AS INT64)) AS state_key,
  state_fips_code,
  state_alpha,
  state_name,
  agg_level_desc AS geo_level                -- 'STATE' or 'NATIONAL'
FROM (
  SELECT DISTINCT state_fips_code, state_alpha, state_name, agg_level_desc
  FROM `ust-seis732.ccr_raw.nass_cattle_jan1`
);

-- dim_cattle_class: one row per series.
CREATE OR REPLACE TABLE `ust-seis732.ccr_curated.dim_cattle_class` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY short_desc) AS cattle_class_key,
  short_desc AS source_short_desc,
  CASE short_desc
    WHEN 'CATTLE, COWS, BEEF - INVENTORY' THEN 'Beef cows'
    WHEN 'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY' THEN 'Beef replacement heifers'
  END AS class_name,
  CASE short_desc
    WHEN 'CATTLE, COWS, BEEF - INVENTORY' THEN 'Beef cows that have calved'
    WHEN 'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY'
      THEN 'Heifers 500 lbs and over kept to replace beef cows'
  END AS nass_definition
FROM (SELECT DISTINCT short_desc FROM `ust-seis732.ccr_raw.nass_cattle_jan1`);

-- dim_date: one row per inventory year (always January 1).
CREATE OR REPLACE TABLE `ust-seis732.ccr_curated.dim_date` AS
SELECT
  yr * 10000 + 101   AS date_key,        -- YYYY0101
  DATE(yr, 1, 1)     AS inventory_date,
  yr                 AS year
FROM (SELECT DISTINCT SAFE_CAST(year AS INT64) AS yr
      FROM `ust-seis732.ccr_raw.nass_cattle_jan1`);

-- fact_cattle_inventory_jan1: one row per geography, cattle class and year.
-- Inner joins on natural keys: a Raw row with no matching dimension row would drop out,
-- which the row-count check below (and 04-acceptance.sql) would catch.
CREATE OR REPLACE TABLE `ust-seis732.ccr_curated.fact_cattle_inventory_jan1` AS
SELECT
  s.state_key,
  c.cattle_class_key,
  d.date_key,
  SAFE_CAST(REPLACE(TRIM(r.value), ',', '') AS INT64) AS head_count,
  SAFE_CAST(r.load_time AS TIMESTAMP)                 AS source_load_ts,
  TRUE                                                AS is_current   -- P2: one load, so every row is current.
FROM `ust-seis732.ccr_raw.nass_cattle_jan1` r
JOIN `ust-seis732.ccr_curated.dim_state` s
  ON  r.state_fips_code = s.state_fips_code
  AND r.state_alpha     = s.state_alpha
  AND r.agg_level_desc  = s.geo_level
JOIN `ust-seis732.ccr_curated.dim_cattle_class` c
  ON  r.short_desc = c.source_short_desc
JOIN `ust-seis732.ccr_curated.dim_date` d
  ON  SAFE_CAST(r.year AS INT64) = d.year;

-- Verify the build. Expected: dimensions 51 / 2 / 103; fact = Raw = 10,143; 0 NULL head counts.
SELECT
  (SELECT COUNT(*) FROM `ust-seis732.ccr_curated.dim_state`)        AS dim_state_rows,
  (SELECT COUNT(*) FROM `ust-seis732.ccr_curated.dim_cattle_class`) AS dim_cattle_class_rows,
  (SELECT COUNT(*) FROM `ust-seis732.ccr_curated.dim_date`)         AS dim_date_rows,
  (SELECT COUNT(*) FROM `ust-seis732.ccr_raw.nass_cattle_jan1`)     AS raw_rows,
  (SELECT COUNT(*) FROM `ust-seis732.ccr_curated.fact_cattle_inventory_jan1`) AS fact_rows,
  (SELECT COUNTIF(head_count IS NULL)
     FROM `ust-seis732.ccr_curated.fact_cattle_inventory_jan1`)     AS null_head_counts;


-- Field trace: Minnesota beef cows, Jan 1 2022, through Source -> Raw -> Curated.
SELECT
  src.value     AS source_value,
  r.value       AS raw_value,
  f.head_count  AS curated_head_count
FROM `bigquery-public-data.usda_nass_agriculture.animals_products` src
JOIN `ust-seis732.ccr_raw.nass_cattle_jan1` r
  ON  src.state_alpha = r.state_alpha AND src.short_desc = r.short_desc AND src.year = r.year
  AND src.reference_period_desc = r.reference_period_desc AND src.source_desc = r.source_desc
  AND src.domaincat_desc = r.domaincat_desc AND src.agg_level_desc = r.agg_level_desc
JOIN `ust-seis732.ccr_curated.dim_state` s        ON r.state_alpha = s.state_alpha
JOIN `ust-seis732.ccr_curated.dim_cattle_class` c ON r.short_desc = c.source_short_desc
JOIN `ust-seis732.ccr_curated.fact_cattle_inventory_jan1` f
  ON  f.state_key = s.state_key AND f.cattle_class_key = c.cattle_class_key
  AND f.date_key = SAFE_CAST(r.year AS INT64) * 10000 + 101
WHERE r.state_alpha = 'MN'
  AND r.short_desc = 'CATTLE, COWS, BEEF - INVENTORY'
  AND r.year = '2022';
