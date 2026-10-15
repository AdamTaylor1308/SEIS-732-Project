# P0 Feasibility

## 1. Working Title
Cattle Cycle Tracking to Facilitate Data-Informed Herd Decision Making

## 2. Audience & Need
- State beef extension specialists (e.g., at a land-grant university extension service) who advise **cow-calf producers** on herd expansion decisions. The product tracks the U.S. beef cattle cycle (inventory, prices, slaughter) using USDA NASS data in BigQuery.
- Each fall and winter, ranchers ask, “Should I hold on to heifers to grow my herd, or sell them?” The specialist has to answer with evidence about where the state and the country are in the cattle cycle.

- Why a data product helps:
   - The evidence exists in NASS Quick Stats but is split across hundreds of series names, reference dates and geography levels. A dashboard puts inventory, heifer retention and prices on one timeline by state.

## 3. Proposed Analytical Product & Questions
Consumption artifact: An interactive dashboard that shows where the nation-wide, or a selected state's cattle herd sits in the cattle cycle. It would place the annual beef cow inventory and cattle prices on one timeline, with comparisons to the national total and other selectable states.
Questions: 
- Where is the cycle now? For a selected state, is the herd count expanding or contracting?
- Are ranchers keeping heifers? How has the ratio of beef replacement heifers to beef cows changed year to year in the selected state and nationally? Does a rising ratio come before herd growth in later years?
- How do prices relate to herd size? How closely do changes in the annual cattle price line relate to beef cow inventory?
- How does this state compare with its neighbors? Do the expansions and contractions of a selected state's beef cow inventory correspond with it's neighboring state's?

## 4. Source Identification & Access 
- Source dataset name: usda_nass_agriculture
- Source dataset provider: USDA National Agricultural Statistics Service (NASS) Quick Stats
- BigQuery Location: `bigquery-public-data.usda_nass_agriculture`
- Candidate table: `animals_products` (filtered to `commodity_desc = 'CATTLE'`)
- Location: US
- Links: https://console.cloud.google.com/bigquery?p=bigquery-public-data&d=usda_nass_agriculture&page=dataset · https://quickstats.nass.usda.gov/ · https://quickstats.nass.usda.gov/src/glossary.pdf
- Use and attribution: Source data are USDA NASS Quick Stats, listed on Data.gov as public under a [Creative Commons CC0](http://creativecommons.org/publicdomain/zero/1.0/) license ([Data.gov entry](https://catalog.data.gov/dataset/quick-stats-agricultural-database-api)). Accessed through Google Cloud's BigQuery public datasets. Credit: *USDA National Agricultural Statistics Service, Quick Stats.*

## 5. Quick Source Profile
- Apparent meaning of one row:
   - One row in animals_products is one published NASS aggregate statistic for one state and year
- Row count:
  - Total: 8,614,897
  - Cattle - 3,410,541
- Time Coverage:
  - state inventory 1867–2022
  - prices received 1909–2022
  - county inventory 1920–2022
- Possible IDs or keys:
  - There is no single unique identifier in the table. No single ID column exists. At state level, a row is identified by state_alpha (geography) + short_desc (measured series) + domaincat_desc (breakdown) + year + reference_period_desc (time) + source_desc (SURVEY/CENSUS)
- Fields likely to support the proposed questions:
  - short_desc: identifies the measure
    - CATTLE, COWS, BEEF - INVENTORY (questions 1, 2, 3, 4)
    - CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY (question 2)
    - CATTLE, INCL CALVES - PRICE RECEIVED, MEASURED IN $ / CWT (question 3)
  - value: the numeric estimate (text with commas; needs converting)
  - unit_desc: unit of measure (head, $ / CWT)
  - year: the time period
  - reference_period_desc: point in time within the year (e.g. FIRST OF JAN, YEAR)
  - agg_level_desc: level of geography (STATE, NATIONAL)
  - state_alpha / state_name: state, used for selecting and comparing neighbors (questions 1, 4)
  - source_desc: SURVEY or CENSUS (filter to one for consistent annual series)
  - domaincat_desc: breakdown category (filter to NOT SPECIFIED for totals)
- Important null, duplicate, type, or semi-structured characteristics:
  - `value` contains commas, so it will need REPLACE and SAFE_CAST
  - none of the key columns are missing across 3,000,000+ rows
  - 14 duplicated composite keys out of 1,003,209 at state level
  - short_desc packs commodity, class, statistic and unit into one text string, so each measure has to be selected by exact text match
  - SURVEY and CENSUS rows sit in the same table and can report the same measure for the same state and year
- Refresh behavior: unknown, dataset description reads “Data Updated On: 2023-03-18”

See [sql/00_feasibility.sql](sql/00_feasibility.sql) for queries

## 6. Need-to-source fit 

| Proposed question | Needed fields or concepts | Candidate source object(s) | Why the source appears sufficient| Gap or assumption to test in P1 |
|---|---|---|---|---|
| Q1. Where is the cycle now? For a selected state, is the herd count expanding or contracting? | Beef cow inventory (short_desc), state_alpha, year, reference_period_desc (FIRST OF JAN), value | animals_products | State-level cattle inventory covers 1867–2022. None of the key columns are missing across 3,410,541 cattle rows | Confirm the exact beef cow short_desc and that it has a January 1 value for each state and year. Define “expanding or contracting” (e.g. change from the previous year). “Now” means 2022, the last year in the data | 
| Q2. Are ranchers keeping heifers? How has the ratio of beef replacement heifers to beef cows changed year to year, in the selected state and nationally? Does a rising ratio come before herd growth? | Replacement heifer inventory, beef cow inventory, state_alpha, year, reference_period_desc, agg_level_desc (STATE, NATIONAL) | animals_products | CATTLE, HEIFERS, GE 500 LBS, BEEF REPLACEMENT - INVENTORY exists as of January 1 for 1920–2022 across 50 states. Inventory is also available at national level | Confirm beef cow inventory has matching January 1 coverage so the ratio can be calculated. Use January 1 only (July 1 covers only 1973–1981). Check suppressed values | 
| Q3. How do prices relate to herd size? How closely do changes in the annual cattle price relate to beef cow inventory? | Annual price received (statisticcat_desc = PRICE RECEIVED, unit_desc), beef cow inventory, state_alpha, year, reference_period_desc | animals_products | Price received exists at state level (1909–2022) and national level (1909–2022) | The state-level steer and heifer price ends in 2010 and is monthly, so find an annual series that runs to 2022 or use national prices. Prices are nominal. The comparison shows association, not cause |
| Q4. How does this state compare with its neighbors? Do expansions and contractions in a selected state’s beef cow inventory correspond with those of neighboring states? | Beef cow inventory, state_alpha, year, a list of neighboring states | animals_products | All states are covered at state level (51 values) with annual inventory up to 2022 | Neighbor relationships aren’t in the source, so a small lookup table is needed. Identify the 51st state value | 

## 7. Feasibility risks and responses
- Risk 1: Static data
   - The dataset description reads “Data Updated On: 2023-03-18”, and the latest inventory year is 2022. In response, specifically to the question "Where is the cycle now?", I would clearly label "as of 2022" in the data product so that users don't take the data/information as current.
- Risk 2: Selecting the right series and grain
   - Each measure is stored as text in `short_desc` (187 cattle series), with 84 reference periods, SURVEY and CENSUS rows mixed together, and every column (including `value`) stored as a string. Mixing these could double count or combine values that don't belong together. In response I will filter each measure down to exactly one row per state per year, then double check that the filter worked. If I cannot, then I will use the national average instead. 

- Fallback: Narrow the product to beef cow and replacement-heifer inventory for one selected state and its neighbors (heifer series verified for Jan 1, 1920–2022, 50 states), using national prices only as context.

## 8. First P1 decision
The first issues I plan to resolve in P1 is identifying the correct grain, and similarly verifying that I can convert string series into numeric values. 

## 9. AI/tool accountability
- I used Claude to find the source, after prompting it "are there any public datasets on BigQuery regarding cattle?", and it suggested usda_nass_agriculture; but I could not find it in the Google Cloud Marketplace. I verified that the dataset has a [Creative Commons CC0](http://creativecommons.org/publicdomain/zero/1.0/), which allows me to use, copy, modify and analyze the data. I then confirmed the data was accessible by running a Claude-drafted INFORMATION_SCHEMA.COLUMNS query. Claude also drafted all of the profiling queries which I ran after checking estimated bytes processed. 
