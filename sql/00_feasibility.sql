-- 1. Dataset's tables and inspect their column definitions.
SELECT table_name, column_name, data_type
FROM `bigquery-public-data.usda_nass_agriculture.INFORMATION_SCHEMA.COLUMNS`
ORDER BY table_name, ordinal_position;


-- 2. Cattle coverage: which statistics exist, at what level of geography, and for which years.
SELECT commodity_desc, statisticcat_desc, agg_level_desc,
       MIN(year) AS first_year, MAX(year) AS last_year, COUNT(*) AS n
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE'
GROUP BY 1, 2, 3
ORDER BY n DESC;


-- 3. Scale and missing values: cattle row count and blanks in each composite key column.
SELECT
    COUNT(*) AS cattle_rows,
    COUNTIF(short_desc IS NULL OR TRIM(short_desc) IN ('', 'null')) AS missing_short_desc,
    COUNTIF(agg_level_desc IS NULL OR TRIM(agg_level_desc) IN ('', 'null')) AS missing_agg_level,
    COUNTIF(agg_level_desc = 'STATE' AND (state_alpha IS NULL OR TRIM(state_alpha) IN ('', 'null'))) AS missing_state_on_state_rows,
    COUNTIF(year IS NULL OR SAFE_CAST(year AS INT64) IS NULL) AS missing_or_bad_year,
    COUNTIF(reference_period_desc IS NULL OR TRIM(reference_period_desc) IN ('', 'null')) AS missing_ref_period,
    COUNTIF(source_desc IS NULL OR TRIM(source_desc) IN ('', 'null')) AS missing_source,
    COUNTIF(domaincat_desc IS NULL OR TRIM(domaincat_desc) IN ('', 'null')) AS missing_domaincat
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE';


-- 4. Candidate key test: is state + series + breakdown + year + reference period + source unique?
SELECT
    COUNT(*) AS distinct_keys,
    COUNTIF(n > 1) AS duplicate_keys,
    MAX(n) AS max_rows_per_key
FROM (
    SELECT COUNT(*) AS n
    FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
    WHERE commodity_desc = 'CATTLE' AND agg_level_desc = 'STATE'
    GROUP BY state_alpha, short_desc, domaincat_desc, year, reference_period_desc, source_desc
);


-- 5. Cardinality: how many distinct values each key component has at state level.
SELECT
    COUNT(DISTINCT state_alpha) AS states,
    COUNT(DISTINCT short_desc) AS series,
    COUNT(DISTINCT year) AS years,
    COUNT(DISTINCT reference_period_desc) AS ref_periods,
    COUNT(DISTINCT source_desc) AS sources
FROM `bigquery-public-data.usda_nass_agriculture.animals_products`
WHERE commodity_desc = 'CATTLE' AND agg_level_desc = 'STATE';
