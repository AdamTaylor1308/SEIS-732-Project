# P0-feasibility-results

**Source:** `bigquery-public-data.usda_nass_agriculture.animals_products` (region: US)
**Queries:** [sql/00_feasibility.sql](../sql/00_feasibility.sql) · **Run:** [date] from course project UST-SEIS732
**Note:** Aggregate results only; no source rows are included.

---

## Query 1. Schema
- Query ran successfully from the course project, confirming access.
- Tables in dataset: `animals_products`, `crops`, `demographics`, `economics`, `environmental`, and census tables (`census2002/2007/2012`, `census_2002/2007/2012`).
- `animals_products` has 39 columns, **all STRING**, including `year`, `value`, and state/county codes. The `crops`, `environmental`, and `census_*` tables use typed columns (INT64, FLOAT64, DATE).
- **Interpretation:** numeric and date fields in `animals_products` must be cast before analysis.

## Query 2. Cattle coverage by statistic and geography (selected rows)
| Statistic | Level | Years | Rows |
|---|---|---|---|
| INVENTORY | STATE | 1867–2022 | 284,393 |
| INVENTORY | NATIONAL | 1867–2022 | 8,225 |
| INVENTORY | COUNTY | 1920–2022 | 1,213,238 |
| PRICE RECEIVED | STATE | 1909–2022 | 107,761 |
| PRICE RECEIVED | NATIONAL | 1909–2022 | 5,507 |
| SLAUGHTERED | STATE | 1944–2022 | 349,185 |
| CALF CROP | STATE | 1927–2021 | 2,317 |
- **Interpretation:** inventory and prices overlap at state and national level through 2022, supporting Q1–Q4. Some county statistics end in 2006–2009, so county analysis is likely to not be included

## Query 3. Missing values in key columns (cattle)
- 3,410,541 cattle rows.
- 0 missing values in `short_desc`, `agg_level_desc`, `state_alpha` (state rows), `year`, `reference_period_desc`, `source_desc`, `domaincat_desc`.
- **Interpretation:** the composite key fields are complete

## Query 4. Composite key uniqueness (state level)
- Key: `state_alpha` + `short_desc` + `domaincat_desc` + `year` + `reference_period_desc` + `source_desc`
- 1,003,209 distinct keys; 14 duplicated 
- **Interpretation:** near-unique. The cause of the 14 duplicates will be identified in P1

## Query 5. Cardinality (state level, cattle)
| Component | Distinct values |
|---|---|
| `state_alpha` | 51 (50 states + "OTHER STATES" aggregate) |
| `short_desc` | 187 series |
| `year` | 157 (1867–2023) |
| `reference_period_desc` | 84 |
| `source_desc` | 2 (SURVEY, CENSUS) |
- **Interpretation:** each measure must be filtered to one series, one reference period, and one source to avoid double counting. "OTHER STATES" will be excluded

## Query 6. Row counts
- Total rows: 8,614,897 · Cattle rows: 3,410,541 (matches Q3).

## Query 7. Heifer series (state level)
- `CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY`: FIRST OF JAN, 1920–2022, 50 states. The FIRST OF JUL version covers only 1973–1981.
- `CATTLE, STEERS & HEIFERS, GE 500 LBS - PRICE RECEIVED`: monthly, 1953–2010, 38 states; marketing year 2003–2010.
- **Interpretation:** Q2's heifer-to-cow ratio is supported using January 1 data. The steer-and-heifer price ends in 2010, so Q3 needs a different annual price series or national prices.

