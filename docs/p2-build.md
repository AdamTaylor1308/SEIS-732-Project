# P2 Build

## 1. Establish the input and run ingestion

### Audience and primary analytical question
  - **Audience:** Minnesota cow-calf producers.
  - **Primary Question:** Which states' beef cow herd changes run 1–3 years ahead of Minnesota's, so Minnesota producers can watch them as an early signal?

### What P2 builds
  - **Raw:** `ccr_raw.nass_cattle_jan1`, the in-scope source rows copied unchanged, plus an `extracted_at` column
  - **Curated:**
    - `ccr_curated.dim_state`, `ccr_curated.dim_cattle_class` and `ccr_curated.dim_date`, with surrogate keys.
    - `ccr_curated.fact_cattle_inventory_jan1`, one row per state or national level, cattle class and year, with `value` converted to a whole-number `head_count`
  - **Supports P3:** the year-over-year changes and Minnesota lead-lag correlations built in Serving

**Deferred to P3:**
- The national calf price table (`nass_calf_price_us`). Prices are context for producers, not an input to the lead-lag analysis, and the series is national only and ends in 2021.
- The Serving view and lead-lag mart.
- The simulated-revision history test.

### Changes from P1
#### Layers
  - Adding "ccr_" (cattle cycle review) in front of P1 dataset names to improve readability
    - `ust-seis732.raw.nass_cattle_jan1` -> `ust-seis732.ccr_raw.nass_cattle_jan1`
    - `ust-seis732.cur.dim_state` -> `ust-seis732.ccr_curated.dim_state`
    - `ust-seis732.cur.dim_cattle_class` -> `ust-seis732.ccr_curated.dim_cattle_class`
    - `ust-seis732.cur.dim_date` -> `ust-seis732.ccr_curated.dim_date`
    - `ust-seis732.cur.fact_cattle_inventory_jan1` -> `ust-seis732.ccr_curated.fact_cattle_inventory_jan1`
    - `ust-seis732.srv.v_state_inventory_annual` -> `ust-seis732.ccr_serving.v_state_inventory_annual`
    - `ust-seis732.srv.mart_mn_lead_lag` -> `ust-seis732.ccr_serving.mart_mn_lead_lag`

### Source, objects/files, subsets
  - **Source table:** `bigquery-public-data.usda_nass_agriculture.animals_products` (all columns STRING).
  - **Series:** `CATTLE, COWS, BEEF - INVENTORY` and `CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY`
  - **Filters:** `reference_period_desc = 'FIRST OF JAN'`, `source_desc = 'SURVEY'`, `domaincat_desc = 'NOT SPECIFIED'`, `agg_level_desc IN ('STATE', 'NATIONAL')`, `commodity_desc = 'CATTLE'`
  - **Usable Years:** 1920-2022
  - **Google Cloud Project:** ust-seis732
  - **Location:** US
  - **Raw table name:** `ust-seis732.ccr_raw.nass_cattle_jan1`

### ccr_raw
- [02-ingest.sql](../sql/02-ingest.sql) shows the creation of the `ccr_raw` dataset, and `ccr_raw.nass_cattle_jan1` table
  - **One row represents:** one NASS Jan 1 head count for one cattle class, one state or national level, and one year.
    - Source datatypes are kept as string, 
    - This is the raw table, so even if rows have missing or incomplete data, they're still kept
    - The raw table is subject to being replaced by reruns, so versioning will be handled at the curated level

### [02-ingest.sql](../sql/02-ingest.sql) Run Results
  - Ran on 2026-11-20 in `ust-seis732`, processing location US

| Series | Expected rows (P1) | Observed rows | First year | Last year | Geographies |
|---|---|---|---|---|---|
| `CATTLE, COWS, BEEF - INVENTORY` | 5,126 | 5,126 | 1920 | 2022 | 51 |
| `CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY` | 5,017 | 5,017 | 1920 | 2022 | 51 |
| **Total** | **10,143** | **10,143** | 1920 | 2022 | 51 |

| Reproducibility detail | Value |
|---|---|
| Source dataset "Data Updated On" | 2023-03-18 |
| Newest source `load_time` in the copied rows | 2022-01-31 15:05:53 |
| `extracted_at` (this run) | 2026-11-20 19:22:28 UTC |

- If the total row count is not **10,143** or `load_time` is not 2022-01-31 15:05:53: Google has refreshed the source
- The public table can't be pinned to a version, so these two values are how a later run detects a change

## 2. Build Curated at the intended grain
  - [03-curate.sql](../sql/03-curate.sql) shows the creation of `ccr_curated.dim_state`, `ccr_curated.dim_cattle_class`, `ccr_curated.dim_date`, and `ccr_curated.fact_cattle_inventory_jan1`
  - **One row represents:** one January 1 head count for one cattle class, one state or the national level, and one year
  - **Composite key:** `state_key` + `cattle_class_key` + `date_key` + `source_load_ts`. Only one row per state, class and date may be current. P2 has one load, so the first three are unique.

### Rules for types, missing values, repeats and relationships
  - **Type conversion:** `value` is text with commas (e.g. "360,000"). It is converted with `SAFE_CAST(REPLACE(TRIM(value), ',', '') AS INT64)`. [P1 Query 4](../sql/01_source_profile.sql) showed all 10,143 values convert, and the Curated build has 0 NULL head counts
  - **Repeated Rows:** No dedup rule is applied, because Query 2 found no repeated keys. Acceptance check 1 confirms this in Curated
  - **Missing values:** The 109 state-years with beef cows but no heifers are absent rows, not NULL values, so nothing is removed. The heifer ratio handles the gap later at the `ccr_serving` level
  - **Relationships:** Each fact row finds `state_key`, `cattle_class_key` and `date_key` from the dimensions. The national row needs a matching `dim_state` row

### [03-curate.sql](../sql/03-curate.sql) Run Results
  - Ran on 2026-11-20 in `ust-seis732`, processing location US

| Object | Expected | Observed |
|---|---|---|
| `dim_state` | 51 (50 states + US) | 51 |
| `dim_cattle_class` | 2 | 2 |
| `dim_date` | 103 (1920–2022) | 103 |
| `fact_cattle_inventory_jan1` | 10,143 (= Raw) | 10,143 |
| NULL `head_count` | 0 | 0 |

The joins to the dimensions neither dropped nor duplicated rows: fact rows = Raw rows.

### Field trace: `value` → `head_count`
| Step | Field / rule | Minnesota beef cows, Jan 1 2022 |
|---|---|---|
| Source | `animals_products.value` (STRING) | "360,000" |
| Raw | `nass_cattle_jan1.value`, copied unchanged | "360,000" |
| Curated | `head_count = SAFE_CAST(REPLACE(TRIM(value), ',', '') AS INT64)` | 360000 |
| Serving (*planned, P3*) | `rel_yoy_chg` in `v_state_inventory_annual` → `mart_mn_lead_lag` | — |
| Audience output (*planned*) | Candidate leader states for Minnesota producers | — |

Trace query: bottom of [03-curate.sql](../sql/03-curate.sql)

## 3. Run and interpret two acceptance checks

Checks: [04-acceptance.sql](../sql/04-acceptance.sql). Run on 2026-11-20 after [03-curate.sql](../sql/03-curate.sql).

| Risk and affected result | Check code | Expected result and why | Observed result | Interpretation or action |
|---|---|---|---|---|
| **Grain and relationships:** two current rows for one key, a fact row with no dimension match, or a Raw row lost in the join would inflate or drop head counts in every downstream result. | `04-acceptance.sql`, Check 1 | 0 duplicate current keys; 0 fact rows missing a dimension; current fact rows = Raw rows = 10,143; 0 Raw rows missing from Curated; 0 head-count mismatches. Raw is the independent reference: every Raw row should reach Curated once, with the same value. | 0; 0; 10,143 = 10,143; 0; 0 | Pass. Every Raw row reached Curated exactly once, attached to the correct state, class and year, with the same head count. No action needed. |
| **Meaning of the national row:** the lead-lag analysis subtracts the U.S. change. If the Curated U.S. row ≠ the sum of the states, relative changes shift and the wrong states could look like leaders. | `04-acceptance.sql`, Check 2 | 103 of 103 years match for each class, 0 mismatches, max difference 0. P1 Query 6 found an exact match in the source, so Curated should preserve it. | Beef cows: 103 / 103, max diff 0. Heifers: 103 / 103, max diff 0. | Pass. Curated preserves the source's national reconciliation, so the U.S. row can be used to remove the national trend in P3. No action needed. |

**Revision from P1:** P1's Risk 2 check relied on Serving objects (year-over-year gaps, reproducing TN/NE/OK, output labels), which are built in P3. In P2, the U.S. = sum-of-states part is tested on Curated; the remaining Risk 2 checks stay planned for P3.

## 4. Make the run reproducible and record the next step

### Execution order
Run in processing location **US**, in project `ust-seis732` (given permissions are granted, replace `ust-seis732` with your own BigQuery project ID). Check the bytes estimate before each run.

| Step | File | What it does | Requires | Changes |
|---|---|---|---|---|
| 1 | [02-ingest.sql](../sql/02-ingest.sql) | Creates `ccr_raw` and copies the filtered source rows into `ccr_raw.nass_cattle_jan1`, then verifies the load | Read access to `bigquery-public-data.usda_nass_agriculture` (publicly available) | `CREATE SCHEMA IF NOT EXISTS` (no change if present); `CREATE OR REPLACE TABLE` **replaces** Raw and resets `extracted_at` |
| 2 | [03-curate.sql](../sql/03-curate.sql) | Creates `ccr_curated`, the three dimensions and the fact table, then verifies the build | `ccr_raw.nass_cattle_jan1` from step 1 | Every table uses `CREATE OR REPLACE`, so Curated is **rebuilt from Raw** each run. The trace query at the bottom is read-only and scans the public source (~940 MB), so run it separately. |
| 3 | [04-acceptance.sql](../sql/04-acceptance.sql) | Runs Check 1 (grain and relationships) and Check 2 (U.S. = sum of states) | All four Curated tables from step 2 | Read-only; changes nothing. Run each check separately. |

**Comparing a rerun with this build:** the expected and observed values are in the run-results tables in sections 1–3 (Raw 10,143; dimensions 51 / 2 / 103; fact 10,143; both checks pass). A different Raw count or `MAX(load_time)` means the source changed before anything else is compared.

### Results to save before a rerun
- Steps 1 and 2 replace their tables, so this build's `extracted_at` (2026-11-20 19:22:28 UTC) and row counts are overwritten on the next run. They are recorded above, and screenshots of each verification and check output are saved.
- P3's same-input rerun and changed-input demonstrations compare against these saved results.

### Main limitation of this P2 path
- **No version history yet.** Raw and Curated are both replaced on each run, and every fact row is `is_current = TRUE`. If NASS revised an estimate, a rerun would overwrite the old value instead of keeping it as a retired version. The P1 history plan (keep versions with `source_load_ts` and `is_current`) is designed but not yet implemented.
- The source itself ends at Jan 1, 2022 and is annual, so leads are measured in whole years.

### Next P3 build step
Build `ccr_serving.v_state_inventory_annual` from the Curated fact: beef cows, heifers, the heifer ratio (NULL when either is missing), the year-over-year change using consecutive years only, and the change relative to the U.S. Then build `ccr_serving.mart_mn_lead_lag` and confirm it reproduces the P1 result (TN 2 yrs, NE 2 yrs, OK 3 yrs).

### Update from P1 feedback: history test
P1's planned test said a −3% revision to Minnesota's **2021** beef cows would recalculate the **2022** heifer ratio. That was incorrect: the ratio uses same-year counts. The revised P3 test:
1. Only one current row remains for Minnesota's 2021 beef cow key.
2. Minnesota's **2021** heifer ratio and its **2021 and 2022** year-over-year changes are recalculated, with before and after values recorded.
3. The lead-lag correlations are recalculated and the **size of the change is reported**, rather than held to a fixed threshold.

The model ([model.md](model.md)) is unchanged by this build: the tables and columns match the P1 design, with the `ccr_` dataset names noted in section 1.

### AI and tool use
- I used Claude to draft 02-ingest.sql, 03-curate.sql and 04-acceptance.sql, and to help structure this MD file
  - Every query was run by myself in BigQuery after checking the bytes estimate.
  - Compared each result with independent numbers from P1: Raw rows 10,143 = P1 Query 2; per-series counts 5,126 / 5,017 = P1 Query 4; U.S. = sum of states 103 / 103 = P1 Query 6.
  - Confirmed the geography list (51 rows, national row FIPS 99) before building `dim_state`, which led to sorting FIPS codes numerically.
  - Traced one value (Minnesota beef cows, 2022: "360,000" → 360000) through every layer.

