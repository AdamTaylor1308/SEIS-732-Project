-- 1. Series discovery: confirm exact series text, reference periods, sources and coverage
--    for beef cows and replacement heifers at state and national level.
SELECT short_desc, reference_period_desc, source_desc, domaincat_desc, agg_level_desc,
       MIN(SAFE_CAST(year AS INT64)) AS first_year,
       MAX(SAFE_CAST(year AS INT64)) AS last_year,
       COUNT(DISTINCT state_alpha) AS geographies,
       COUNT(*) AS n
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE'
  AND agg_level_desc IN ('STATE', 'NATIONAL')
  AND (short_desc LIKE 'CATTLE, COWS, BEEF%' OR short_desc LIKE '%BEEF REPLACEMENT%')
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1, 2, 3, 4, 5;


-- 2. Grain test: one row per geography + cattle class + year within the fact scope.
--    Expected: 0 rows with a missing key part, 0 repeated groups, max_rows_per_key = 1.
WITH scope AS (
  SELECT *
  FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
  WHERE commodity_desc = 'CATTLE'
    AND short_desc IN ('CATTLE, COWS, BEEF - INVENTORY',
                       'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY')
    AND reference_period_desc = 'FIRST OF JAN'
    AND source_desc = 'SURVEY'
    AND domaincat_desc = 'NOT SPECIFIED'
    AND agg_level_desc IN ('STATE', 'NATIONAL')
),
grain_groups AS (
  SELECT agg_level_desc, state_alpha, short_desc, year, COUNT(*) AS rows_per_key
  FROM scope
  GROUP BY agg_level_desc, state_alpha, short_desc, year
)
SELECT
  COALESCE(SUM(rows_per_key), 0) AS source_rows,
  COALESCE(SUM(IF(state_alpha IS NULL OR TRIM(state_alpha) = '', rows_per_key, 0)), 0) AS rows_missing_state,
  COALESCE(SUM(IF(SAFE_CAST(year AS INT64) IS NULL, rows_per_key, 0)), 0) AS rows_missing_or_bad_year,
  COALESCE(SUM(IF(short_desc IS NULL, rows_per_key, 0)), 0) AS rows_missing_series,
  COUNTIF(rows_per_key > 1) AS repeated_key_groups,
  MAX(rows_per_key) AS max_rows_per_key
FROM grain_groups;


-- 3. The 14 duplicated P0 keys: which series they belong to and whether the copies differ.
--    Shows whether any duplicate falls inside the fact scope.
SELECT short_desc, reference_period_desc, source_desc, domaincat_desc,
       COUNT(*) AS duplicated_keys,
       SUM(n) AS rows_involved,
       COUNTIF(distinct_values > 1) AS keys_with_conflicting_values,
       COUNTIF(distinct_load_times > 1) AS keys_with_multiple_load_times
FROM (
  SELECT state_alpha, short_desc, domaincat_desc, year, reference_period_desc, source_desc,
         COUNT(*) AS n,
         COUNT(DISTINCT value) AS distinct_values,
         COUNT(DISTINCT load_time) AS distinct_load_times
  FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
  WHERE commodity_desc = 'CATTLE' AND agg_level_desc = 'STATE'
  GROUP BY 1, 2, 3, 4, 5, 6
  HAVING COUNT(*) > 1
)
GROUP BY 1, 2, 3, 4
ORDER BY duplicated_keys DESC;


-- 4. Value conversion: how many in-scope values parse to numbers vs. suppression codes.
SELECT short_desc,
       COUNT(*) AS n,
       COUNTIF(SAFE_CAST(REPLACE(TRIM(value), ',', '') AS INT64) IS NOT NULL) AS numeric_values,
       COUNTIF(TRIM(value) IN ('(D)', '(Z)', '(NA)', '(X)', '(S)', '(L)', '(H)')) AS suppression_codes,
       COUNTIF(SAFE_CAST(REPLACE(TRIM(value), ',', '') AS INT64) IS NULL
               AND TRIM(value) NOT IN ('(D)', '(Z)', '(NA)', '(X)', '(S)', '(L)', '(H)')) AS other_unparseable
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE'
  AND short_desc IN ('CATTLE, COWS, BEEF - INVENTORY',
                     'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY')
  AND reference_period_desc = 'FIRST OF JAN'
  AND source_desc = 'SURVEY'
  AND domaincat_desc = 'NOT SPECIFIED'
  AND agg_level_desc IN ('STATE', 'NATIONAL')
GROUP BY 1;


-- 5. Ratio completeness: geography-years that have one class but not the other.
--    A heifer-to-cow ratio needs both rows for the same geography and year.
WITH scope AS (
  SELECT agg_level_desc, state_alpha, SAFE_CAST(year AS INT64) AS yr, short_desc
  FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
  WHERE commodity_desc = 'CATTLE'
    AND short_desc IN ('CATTLE, COWS, BEEF - INVENTORY',
                       'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY')
    AND reference_period_desc = 'FIRST OF JAN'
    AND source_desc = 'SURVEY'
    AND domaincat_desc = 'NOT SPECIFIED'
    AND agg_level_desc IN ('STATE', 'NATIONAL')
),
pairs AS (
  SELECT agg_level_desc, state_alpha, yr,
         COUNTIF(short_desc LIKE 'CATTLE, COWS, BEEF%') AS cow_rows,
         COUNTIF(short_desc LIKE '%BEEF REPLACEMENT%') AS heifer_rows
  FROM scope
  GROUP BY 1, 2, 3
)
SELECT agg_level_desc,
       COUNT(*) AS geography_years,
       COUNTIF(cow_rows > 0 AND heifer_rows > 0) AS both_present,
       COUNTIF(cow_rows > 0 AND heifer_rows = 0) AS cows_only,
       COUNTIF(cow_rows = 0 AND heifer_rows > 0) AS heifers_only,
       MIN(IF(cow_rows > 0 AND heifer_rows > 0, yr, NULL)) AS first_paired_year,
       MAX(IF(cow_rows > 0 AND heifer_rows > 0, yr, NULL)) AS last_paired_year
FROM pairs
GROUP BY 1;


-- 6. National boundary case: does the published U.S. total equal the sum of state rows
--    (including OTHER STATES)? Decides whether the national ratio uses the U.S. row or a sum.
WITH scope AS (
  SELECT agg_level_desc, state_alpha, SAFE_CAST(year AS INT64) AS yr, short_desc,
         SAFE_CAST(REPLACE(TRIM(value), ',', '') AS INT64) AS head
  FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
  WHERE commodity_desc = 'CATTLE'
    AND short_desc IN ('CATTLE, COWS, BEEF - INVENTORY',
                       'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY')
    AND reference_period_desc = 'FIRST OF JAN'
    AND source_desc = 'SURVEY'
    AND domaincat_desc = 'NOT SPECIFIED'
    AND agg_level_desc IN ('STATE', 'NATIONAL')
),
by_year AS (
  SELECT short_desc, yr,
         SUM(IF(agg_level_desc = 'NATIONAL', head, 0)) AS us_published,
         SUM(IF(agg_level_desc = 'STATE', head, 0)) AS state_sum,
         COUNTIF(agg_level_desc = 'STATE') AS state_rows,
         COUNTIF(agg_level_desc = 'STATE' AND head IS NULL) AS state_rows_suppressed
  FROM scope
  GROUP BY 1, 2
)
SELECT short_desc,
       COUNT(*) AS years,
       COUNTIF(us_published = state_sum) AS years_exact_match,
       COUNTIF(us_published != state_sum) AS years_mismatch,
       MAX(ABS(us_published - state_sum)) AS max_abs_diff_head,
       MIN(state_rows) AS min_state_rows,
       MAX(state_rows) AS max_state_rows,
       SUM(state_rows_suppressed) AS suppressed_state_rows
FROM by_year
WHERE us_published > 0
GROUP BY 1;


-- 7. Revision evidence for the history plan: when were in-scope values loaded, by year?
--    Varying load_time across reference years suggests values are revised after first release.
SELECT short_desc,
       SAFE_CAST(year AS INT64) AS yr,
       COUNT(*) AS n,
       MIN(load_time) AS first_load_time,
       MAX(load_time) AS last_load_time
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE'
  AND short_desc IN ('CATTLE, COWS, BEEF - INVENTORY',
                     'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY')
  AND reference_period_desc = 'FIRST OF JAN'
  AND source_desc = 'SURVEY'
  AND domaincat_desc = 'NOT SPECIFIED'
  AND agg_level_desc = 'NATIONAL'
GROUP BY 1, 2
ORDER BY 1, 2 DESC
LIMIT 40;


-- 8. Lead-lag feasibility: which states' beef cow cycle runs ahead of Minnesota's?
--    Measure: year-over-year % change in Jan 1 beef cows, minus the U.S. change that year
--    (removes the shared national cycle). Correlates state X in year t with MN in year t + k.
--    k = 0 is the same-year baseline. r_early / r_late split the history to test whether a lead holds.
WITH cows AS (
  SELECT agg_level_desc, state_alpha, state_name,
         SAFE_CAST(year AS INT64) AS yr,
         SAFE_CAST(REPLACE(TRIM(value), ',', '') AS INT64) AS head
  FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
  WHERE commodity_desc = 'CATTLE'
    AND short_desc = 'CATTLE, COWS, BEEF - INVENTORY'
    AND reference_period_desc = 'FIRST OF JAN'
    AND source_desc = 'SURVEY'
    AND domaincat_desc = 'NOT SPECIFIED'
    AND agg_level_desc IN ('STATE', 'NATIONAL')
),
chg AS (
  SELECT agg_level_desc, state_alpha, state_name, yr,
         IF(LAG(yr) OVER w = yr - 1,
            SAFE_DIVIDE(head - LAG(head) OVER w, LAG(head) OVER w), NULL) AS pct_chg
  FROM cows
  WHERE head IS NOT NULL
  WINDOW w AS (PARTITION BY agg_level_desc, state_alpha ORDER BY yr)
),
rel AS (
  SELECT s.state_alpha, s.yr, s.pct_chg - u.pct_chg AS rel_chg
  FROM chg s
  JOIN chg u ON u.yr = s.yr AND u.agg_level_desc = 'NATIONAL'
  WHERE s.agg_level_desc = 'STATE' AND s.state_name != 'OTHER STATES'
),
mn AS (SELECT yr, rel_chg FROM rel WHERE state_alpha = 'MN')
SELECT x.state_alpha, k AS lead_years,
       COUNT(m.rel_chg) AS n_years,
       ROUND(CORR(x.rel_chg, m.rel_chg), 2) AS r_all,
       ROUND(CORR(IF(m.yr <= 1990, x.rel_chg, NULL), m.rel_chg), 2) AS r_early_to_1990,
       ROUND(CORR(IF(m.yr > 1990, x.rel_chg, NULL), m.rel_chg), 2) AS r_late_after_1990
FROM rel x
CROSS JOIN UNNEST([0, 1, 2, 3]) AS k
JOIN mn m ON m.yr = x.yr + k
WHERE x.state_alpha != 'MN'
GROUP BY 1, 2
HAVING n_years >= 30
ORDER BY lead_years, r_all DESC;


-- 9. Which state-years have beef cows but no replacement heifers (109 in query 5)?
--    Summarized by state so the gap can be explained (early years, small states, or both).
WITH pairs AS (
  SELECT state_alpha, SAFE_CAST(year AS INT64) AS yr,
         COUNTIF(short_desc = 'CATTLE, COWS, BEEF - INVENTORY') AS cow_rows,
         COUNTIF(short_desc = 'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY') AS heifer_rows
  FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
  WHERE commodity_desc = 'CATTLE'
    AND short_desc IN ('CATTLE, COWS, BEEF - INVENTORY',
                       'CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY')
    AND reference_period_desc = 'FIRST OF JAN'
    AND source_desc = 'SURVEY'
    AND domaincat_desc = 'NOT SPECIFIED'
    AND agg_level_desc = 'STATE'
  GROUP BY 1, 2
)
SELECT state_alpha,
       COUNT(*) AS cows_only_years,
       MIN(yr) AS first_gap_year,
       MAX(yr) AS last_gap_year
FROM pairs
WHERE cow_rows > 0 AND heifer_rows = 0
GROUP BY 1
ORDER BY cows_only_years DESC;


-- 10. Sub-annual discovery: which state-level cattle series are published more than once a year,
--     still run to 2015 or later, and include Minnesota? Needed for 6-18 month lead times.
SELECT short_desc, freq_desc,
       COUNT(DISTINCT reference_period_desc) AS periods_per_year,
       MIN(SAFE_CAST(year AS INT64)) AS first_year,
       MAX(SAFE_CAST(year AS INT64)) AS last_year,
       COUNT(DISTINCT state_alpha) AS states,
       LOGICAL_OR(state_alpha = 'MN') AS has_mn,
       COUNT(*) AS n
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE'
  AND agg_level_desc = 'STATE'
  AND source_desc = 'SURVEY'
  AND domaincat_desc = 'NOT SPECIFIED'
GROUP BY 1, 2
HAVING periods_per_year >= 2 AND last_year >= 2015
ORDER BY has_mn DESC, states DESC, n DESC;


-- 11. Semi-annual option: Jan 1 + Jul 1 beef cow inventory by state.
--     Which states (incl. MN) have both, and for which years? Jul 1 state data ends in 2004.
SELECT state_alpha,
       COUNTIF(reference_period_desc = 'FIRST OF JAN') AS jan_rows,
       COUNTIF(reference_period_desc = 'FIRST OF JUL') AS jul_rows,
       MIN(IF(reference_period_desc = 'FIRST OF JUL', SAFE_CAST(year AS INT64), NULL)) AS jul_first_year,
       MAX(IF(reference_period_desc = 'FIRST OF JUL', SAFE_CAST(year AS INT64), NULL)) AS jul_last_year
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE'
  AND short_desc = 'CATTLE, COWS, BEEF - INVENTORY'
  AND reference_period_desc IN ('FIRST OF JAN', 'FIRST OF JUL')
  AND source_desc = 'SURVEY'
  AND domaincat_desc = 'NOT SPECIFIED'
  AND agg_level_desc = 'STATE'
GROUP BY 1
HAVING jul_rows > 0
ORDER BY state_alpha;


-- 12. P0 feedback: find a state-level cattle PRICE RECEIVED series comparable to annual inventory.
--     Looking for an ANNUAL (or MARKETING YEAR) series that runs to 2022, covers many states, and includes MN.
--     Monthly series are listed too, since a monthly price could give a 6-18 month lead before Jan 1.
SELECT short_desc, freq_desc, reference_period_desc = 'YEAR' OR reference_period_desc LIKE 'MARKETING YEAR%' AS is_annual,
       MIN(SAFE_CAST(year AS INT64)) AS first_year,
       MAX(SAFE_CAST(year AS INT64)) AS last_year,
       COUNT(DISTINCT state_alpha) AS states,
       COUNT(DISTINCT IF(SAFE_CAST(year AS INT64) >= 2015, state_alpha, NULL)) AS states_since_2015,
       LOGICAL_OR(state_alpha = 'MN') AS has_mn,
       MAX(IF(state_alpha = 'MN', SAFE_CAST(year AS INT64), NULL)) AS mn_last_year,
       COUNT(*) AS n
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE'
  AND statisticcat_desc = 'PRICE RECEIVED'
  AND agg_level_desc = 'STATE'
  AND source_desc = 'SURVEY'
  AND domaincat_desc = 'NOT SPECIFIED'
GROUP BY 1, 2, 3
ORDER BY is_annual DESC, last_year DESC, states DESC;

-- 13. National annual cattle price series that run to 2022 
SELECT short_desc, reference_period_desc,
       MIN(SAFE_CAST(year AS INT64)) AS first_year,
       MAX(SAFE_CAST(year AS INT64)) AS last_year,
       COUNT(*) AS n
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE'
  AND statisticcat_desc = 'PRICE RECEIVED'
  AND agg_level_desc = 'NATIONAL'
  AND source_desc = 'SURVEY'
  AND domaincat_desc = 'NOT SPECIFIED'
  AND freq_desc = 'ANNUAL'
GROUP BY 1, 2
ORDER BY last_year DESC, short_desc;
