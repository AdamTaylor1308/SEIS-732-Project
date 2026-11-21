-- 04-acceptance.sql
-- Two acceptance checks on the Curated layer. Run after 03-curate.sql.
-- Processing location: US. Read-only: these queries change no tables.

-- CHECK 1 — Grain and relationships
-- Risk: a reload or a bad dimension join leaves two current rows for one key, a fact row with
-- no dimension match, or a Raw row that never reaches Curated, which would inflate or drop head counts.
-- Expected: 0 duplicate current keys, 0 fact rows missing a dimension, current fact rows = Raw rows (10,143),
-- 0 Raw rows missing from Curated, 0 head_count values that differ from their Raw row.
WITH cur AS (
  SELECT f.state_key, f.cattle_class_key, f.date_key, f.head_count, f.is_current,
         s.state_alpha, s.geo_level, c.source_short_desc, d.year
  FROM `ust-seis732.ccr_curated.fact_cattle_inventory_jan1` f
  LEFT JOIN `ust-seis732.ccr_curated.dim_state`        s USING (state_key)
  LEFT JOIN `ust-seis732.ccr_curated.dim_cattle_class` c USING (cattle_class_key)
  LEFT JOIN `ust-seis732.ccr_curated.dim_date`         d USING (date_key)
),
raw AS (
  SELECT state_alpha, agg_level_desc AS geo_level, short_desc AS source_short_desc,
         SAFE_CAST(year AS INT64) AS year,
         SAFE_CAST(REPLACE(TRIM(value), ',', '') AS INT64) AS head_count
  FROM `ust-seis732.ccr_raw.nass_cattle_jan1`
),
matched AS (
  SELECT r.head_count AS raw_head_count, c.head_count AS cur_head_count, c.state_key
  FROM raw r
  LEFT JOIN cur c
    ON  r.state_alpha = c.state_alpha AND r.geo_level = c.geo_level
    AND r.source_short_desc = c.source_short_desc AND r.year = c.year
    AND c.is_current
)
SELECT
  (SELECT COUNT(*) FROM (
     SELECT state_key, cattle_class_key, date_key FROM cur
     WHERE is_current GROUP BY 1, 2, 3 HAVING COUNT(*) > 1))              AS duplicate_current_keys,
  (SELECT COUNTIF(state_alpha IS NULL OR source_short_desc IS NULL OR year IS NULL)
     FROM cur)                                                            AS fact_rows_missing_dimension,
  (SELECT COUNT(*) FROM raw)                                              AS raw_rows,
  (SELECT COUNTIF(is_current) FROM cur)                                   AS current_fact_rows,
  (SELECT COUNTIF(state_key IS NULL) FROM matched)                        AS raw_rows_missing_from_curated,
  (SELECT COUNTIF(raw_head_count != cur_head_count) FROM matched)         AS head_count_mismatches;


-- CHECK 2 — Meaning of the national row for the audience result
-- Risk: the lead-lag analysis removes the national cycle by subtracting the U.S. change. If Curated's
-- U.S. row no longer equals the sum of the states (a dropped state, a misassigned key, a bad conversion),
-- every state's relative change shifts and the wrong states could look like leaders.
-- Independent evidence: P1 Query 6 found U.S. = sum of states in 103 of 103 years for both series, in the source.
-- Expected: 103 years per class, 103 exact matches, 0 mismatches, max difference 0.
WITH cur AS (
  SELECT c.class_name, d.year, s.geo_level, f.head_count
  FROM `ust-seis732.ccr_curated.fact_cattle_inventory_jan1` f
  JOIN `ust-seis732.ccr_curated.dim_state`        s USING (state_key)
  JOIN `ust-seis732.ccr_curated.dim_cattle_class` c USING (cattle_class_key)
  JOIN `ust-seis732.ccr_curated.dim_date`         d USING (date_key)
  WHERE f.is_current
),
by_year AS (
  SELECT class_name, year,
         SUM(IF(geo_level = 'NATIONAL', head_count, 0)) AS us_published,
         SUM(IF(geo_level = 'STATE',    head_count, 0)) AS state_sum
  FROM cur
  GROUP BY 1, 2
)
SELECT class_name,
       COUNT(*)                              AS years,
       COUNTIF(us_published = state_sum)     AS years_exact_match,
       COUNTIF(us_published != state_sum)    AS years_mismatch,
       MAX(ABS(us_published - state_sum))    AS max_abs_diff_head
FROM by_year
GROUP BY 1
ORDER BY 1;
