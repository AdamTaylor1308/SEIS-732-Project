# P1 Plan

## 1. Establish the question and check the source

### Audience, need and questions
- **Audience:** Minnesota cow-calf producers.
- **Need:** Each fall and winter, ranchers ask, "Should I hold on to heifers to grow my herd, or sell them?" They need evidence of where the cattle cycle is heading.
- **Primary question:** Which states' beef cow herd changes run 1–3 years ahead of Minnesota's, so Minnesota producers can watch them as an early signal?
- **Supporting question:** How has the ratio of beef replacement heifers to beef cows changed by year in Minnesota and nationally?

### Changes from P0
- **Audience:** P0 targeted extension specialists in any state. P1 targets Minnesota cow-calf producers directly, because the newly chosen primary question is about Minnesota and producers are the ones making the keep-or-sell decision.
- **Questions:** P0 had four questions. P1 keeps one primary and one supporting question that the same model answers. The neighbor lookup (P0 Q4) is dropped, because the lead-lag test compares Minnesota with every state.
- **Lead time:** I first wanted a 6–18 month lead. The source cannot support it for Minnesota:
  - Beef cow inventory is published only on Jan 1 and Jul 1, and Minnesota's Jul 1 data covers only 1971–1981 (Query 11).
  - No other beef-relevant series runs monthly or weekly to 2022 with Minnesota included (Query 10), so leads are measured in whole years.

### Response to P0 feedback
- **"As of 2022" label:** Query 1 confirms the latest Jan 1 inventory is Jan 1, 2022. Every latest value in the dashboard will be labeled "As of Jan 1, 2022," and Risk 2's check confirms the label is present.
- **Annual state-level price series:** I checked every state-level cattle PRICE RECEIVED series (Query 12). All beef cattle price series end in 2010. The only state series that runs to 2021–2022 is milk cows, which is not comparable. Because of this, I will use national prices as context only:
  - Series: `CATTLE, CALVES - PRICE RECEIVED, MEASURED IN $ / CWT`, reference period `YEAR`, national, 1996–2021 (Query 13).
  - I chose calves because that is the price cow-calf producers receive.
  - Prices do not enter the primary question. They are labeled "through 2021" because the series ends a year before inventory.
  - The P0 series `CATTLE, INCL CALVES - PRICE RECEIVED` has no national annual version, so it is replaced.

### Source profile
- **Source:** `bigquery-public-data.usda_nass_agriculture.animals_products` (all columns STRING).
- **Series:** `CATTLE, COWS, BEEF - INVENTORY` and `CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY`.
- **Filters:** `reference_period_desc = 'FIRST OF JAN'`, `source_desc = 'SURVEY'`, `domaincat_desc = 'NOT SPECIFIED'`, `agg_level_desc IN ('STATE', 'NATIONAL')`.
- **Row meaning:** one NASS Jan 1 head count for one cattle class, one state or national level, and one year.
- **Size and dates:**
  - 10,143 rows (beef cows 5,126; heifers 5,017), out of 3,410,541 cattle rows.
  - Coverage is Jan 1, 1920 – Jan 1, 2022, for 50 states plus the U.S. total.
  - Minnesota is complete for both series.
- **Candidate identifier:** `agg_level_desc` + `state_alpha` + `short_desc` + `year`. The other P0 key parts are fixed by the filters.
- **Values:** `value` is text with commas. All 10,143 values convert to whole numbers (Query 4).
- **Data issue:** 109 state-years have beef cows but no heifer count, so the heifer ratio is undefined there. All 109 are in CT, MA, NJ, RI and DE, mostly 1920–1952 (Query 9). They do not affect Minnesota or the U.S. ratio.
- **P0 duplicates resolved:** The 14 repeated keys from P0 are all in the death-loss series, outside this scope. They are two loads of the same estimate with different values (Query 3).

### Grain check
Query 2 in [sql/01_source_profile.sql](../sql/01_source_profile.sql) groups the in-scope rows by `agg_level_desc, state_alpha, short_desc, year`.

| Measure | Expected | Observed |
|---|---|---|
| Source rows | ≤ 10,506 (51 geographies × 103 years × 2 series) | 10,143 |
| Rows missing `state_alpha` | 0 | 0 |
| Rows missing or with an unparseable `year` | 0 | 0 |
| Rows missing `short_desc` | 0 | 0 |
| Repeated key groups | 0 | 0 |
| Max rows per key | 1 | 1 |

**Conclusion:** The grain holds: one row per state or national level, cattle class and year, with no missing or repeated keys. The 363-row shortfall from a full grid is missing rows, not duplicates (127 beef cow and 236 heifer state-years), so no selection rule is needed. A year-over-year change must still never span a missing year (Risk 2).

**Boundary case:** The published U.S. total equals the sum of the states in all 103 years for both series (Query 6). The U.S. row can be used for the national ratio and for removing the national trend, without disagreeing with the states.

## 2. Define the model and predict a history consequence

- **Business process:** NASS's annual January 1 cattle inventory estimate.
- **Fact table:** `fact_cattle_inventory_jan1`, a periodic snapshot.
- **Grain:** One row represents the NASS SURVEY estimate of the January 1 head count for one cattle class (beef cows or beef replacement heifers) in one state or at the national level, in one year.
- **Measure:** `head_count`. It is semi-additive: it can be summed across states for the same class and year, but not across years or classes.

### Modeling choice: one row per cattle class
I store one row per cattle class rather than separate `beef_cows` and `repl_heifers` columns.
- **Benefit:** The fact matches the source grain exactly, so the Query 2 check carries straight into the warehouse.
- **Cost:** The heifer ratio needs a pivot in Serving, and a missing heifer count must give a NULL ratio, not 0.

### Model
See [model.md](model.md).
- **`fact_cattle_inventory_jan1`:** `state_key`, `cattle_class_key`, `date_key`, `head_count`, `source_load_ts`, `is_current`.
- **`dim_state`:** surrogate `state_key`, plus `state_fips_code`, `state_alpha`, `state_name` and `geo_level` (state or national). It includes one U.S. row.
- **`dim_cattle_class`:** surrogate `cattle_class_key`, plus `source_short_desc`, `class_name` and `nass_definition`.
- **`dim_date`:** `date_key` (YYYY0101), `inventory_date` and `year`.
- **Roles in the lead-lag mart:** `dim_state` and year each play two roles there:
  - the leader state in year *t*
  - Minnesota in year *t + k*

### Question trace
**Primary:**
1. Start from `fact_cattle_inventory_jan1`, filtered to beef cows and `is_current`.
2. Compute each state's year-over-year % change, using consecutive years only, and subtract the U.S. change that year to remove the national cycle.
3. Correlate each state's change in year *t* with Minnesota's change in year *t + k*, for k = 1, 2 and 3 years. k = 0 is the same-year baseline.
4. To check the result holds over time, calculate it separately for years up to 1990 and after 1990.

**Supporting:** The same fact, for Minnesota and the U.S. Divide heifers by beef cows for each year.

**P1 result (Query 8):**
- **1 year ahead:** No state is meaningful. No state reaches r ≥ 0.2 in both periods.
- **2–3 years ahead:** Three states hold in both periods:
  - Tennessee, 2 years (r = 0.36 before 1990, 0.21 after)
  - Nebraska, 2 years (0.20, 0.23)
  - Oklahoma, 3 years (0.24, 0.22)
- **Caution:** I ran 147 tests (49 states × 3 leads), so a few could pass by chance. These are candidate signals, not forecasts.

### History and shared meaning
**What changes: NASS revises its estimates.**
- Query 7 shows national beef cow values reloaded in batches: 2009–2013 after the 2012 Census of Agriculture, and 2014–2018 after the 2017 Census.
- Each January report also revises the prior year (2021 and 2022 were loaded together on 2022-01-31).
- The source keeps only the latest value per key, so earlier published values are lost.

**Options:**
- **Overwrite (Type 1):** Keep only the latest estimate. This is simpler, but a number the dashboard showed last year can change with no trace.
- **Keep versions (chosen):** Store `source_load_ts` and `is_current`. A new load adds the revised row and retires the old one. Reports read the current rows, and an "as first published" view is still possible.

**Keys:**
- The source identifiers are `state_fips_code`/`state_alpha`, `short_desc` and `year`.
- The warehouse uses surrogate `state_key` and `cattle_class_key`, so the fact does not depend on NASS label text.
- With versions, only one row per state, class and date may be current.

**Dimensions:** `dim_state` and `dim_cattle_class` are Type 1. Names and FIPS codes do not change in this data.

**Dates:** The inventory date (Jan 1) and the load date are separate. "As of Jan 1, 2022" refers to the inventory date.

**Shared definitions:**
- **"Beef cows":** NASS's beef cows that have calved.
- **"Expanding":** Heifer ratio: beef replacement heifers / beef cows, both on Jan 1st for the same state and year. If either are missing: null
- **"National":** the published U.S. row, which equals the sum of the states.

**Predicted consequence:**
- Revising Minnesota's 2022 beef cow count would change roughly 1% of year-over-year values so the lead/lag correlation shouldn't move much, and the leader list stays the same.
- The supporting answer is more fragile. A revision to 2022 can flip Minnesota's latest "expanding / contracting" label.

**Behavior to test by P3:** Load a simulated revision of Minnesota's 2021 beef cow count (−3%). Show that:
1. Only one current row remains for that key.
2. Minnesota's Jan 1, 2022 heifer ratio is recalculated, and the before and after values are recorded.
3. The lead-lag correlations change by less than 0.01.

## 3. Plan the build and its checks

### Layers
- **Raw:**
  - `raw.nass_cattle_jan1`: the in-scope inventory rows copied unchanged, plus `extracted_at`.
  - `raw.nass_calf_price_us`: the national annual calf price rows, copied unchanged.
- **Curated:**
  - `cur.dim_state`, `cur.dim_cattle_class` and `cur.dim_date`, with surrogate keys.
  - `cur.fact_cattle_inventory_jan1`, which converts values to numbers, looks up keys and manages `is_current`.
  - `cur.us_calf_price_annual`: one row per year, 1996–2021, as price context.
- **Serving:**
  - `srv.v_state_inventory_annual`: one row per state or national level and year, with beef cows, heifers, the ratio, the year-over-year change and the change relative to the U.S.
  - `srv.mart_mn_lead_lag`: one row per state and lead (k = 0–3), with correlations for all years, up to 1990 and after 1990.

**Run order:** Raw tables → dimensions → inventory fact and price table → Curated checks → `v_state_inventory_annual` → `mart_mn_lead_lag` → Serving checks.

### Field trace: `value` → leader list
1. **Source:** `animals_products.value` is text, e.g. "2,345,000".
2. **Raw:** copied unchanged.
3. **Curated:** `head_count = SAFE_CAST(REPLACE(TRIM(value), ',', '') AS INT64)`.
4. **Serving:** `rel_yoy_chg` = the state's year-over-year % change minus the U.S. change. It is NULL if the prior year is missing.
5. **Serving:** `mart_mn_lead_lag` correlates each state's `rel_yoy_chg` in year *t* with Minnesota's in year *t + k*.
6. **Dashboard:** a short list of candidate leader states, each with its lead in years and the before/after-1990 results, labeled "candidate signal, not a forecast."

### Risks and checks
**Risk 1 (grain):** A reload or versioning error leaves two current rows for one key, or a fact row fails to match `dim_state` (for example, the U.S. row is missing). Either one would inflate or drop cattle counts.
- **Check:** Count keys with more than one current row, and fact rows with a missing dimension key. Compare the current row count with raw after loading `cur.fact_cattle_inventory_jan1`
- **Expected:** 0, 0, and 10,143 = 10,143.

**Risk 2 (meaning of the audience result):** A state looks like a leader when it isn't. That could happen because a year-over-year change spans a missing year or the national trend wasn't removed. Producers could also over-trust a weak signal.
- **Check:**
  - Use `srv.v_state_inventory_annual` and `srv.mart_mn_lead_lag` to count year-over-year values whose prior row is not exactly one year earlier.
  - Rerun the U.S. = sum-of-states test on Curated.
  - Confirm the mart reproduces the P1 result.
  - Confirm the output carries the "candidate signal, not a forecast" and "As of Jan 1, 2022" labels.
- **Expected:**
  - 0 changes spanning gaps.
  - 103 of 103 years match.
  - TN, NE and OK reappear.
  - Both labels are present.

### Access
The traced field is public, aggregate USDA NASS data released under CC0, with no personal or restricted information, so no access control is needed. It appears directly in the dashboard.
- **Intended user:** Minnesota cow-calf producers.
- **Owner:** I own the warehouse objects. USDA NASS is the source steward.

### Largest limitations
  - The data is not current (cow data ends in 2022, prices end in 2021) and is annual.
  - The lead signals are weak (r ≈ 0.2–0.36) so the product can point ranchers to a few states to watch albeit unreliably
- **First P2 step:** Create `raw.nass_cattle_jan1` in the course project using the Query 2 filters, and confirm it holds 10,143 rows.

## 4. Diagnose and revise the plan
 - Meeting with Brian during class helped me to understand which primary question I want to dig into with this dataset, which is the primary question chosen in this P1 submission. The topic of wrangling the complex raw data came up, as this dataset is not particularly clean, which prompted me to going with a question that presumably would be more direct and allow me to filter out all the noise. Brian noted that the multitude of descriptions (0-50 head, 50-200 head, etc. / slaughter, dairy, beef, etc.) might make the data hard to work with, and thought it would be easier to handle data pertaining to a select few descriptors: (`repl_heifers` & `beef_cows` were chosen). I'm still uncertain of whether or not this dataset will be able to provide meaningful results given it's limited range (4 year gap between present and latest data). 

### AI/tool accountability
- I used Claude to draft profiling queries 1–13, formatting the markdown documents, and help with interpreting results due to the nature of the raw dataset. I also prompted Claude to provide the Mermaid code necessary to make the model 
- I checked the claims against the outputs:
  - The grain count (10,143) equals the per-series counts in Query 4 (5,126 + 5,017).
  - The 109 heifer gaps in Query 9 add up to the Query 5 count.
- All queries were ran in BigQuery by myself after checking estimated bytes processed. 
