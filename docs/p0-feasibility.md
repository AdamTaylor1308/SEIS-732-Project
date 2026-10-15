# P0 Feasibility

## 1. Working Title
Cattle Cycle Tracking to Facilitate Data-Informed Herd Decision Making

## 2. Audience & Need
- State beef extension specialists (e.g., at a land-grant university extension service) who advise **cow-calf producers** on herd expansion decisions. The product tracks the U.S. beef cattle cycle (inventory, prices, slaughter) using USDA NASS data in BigQuery.
- Each fall and winter, ranchers ask, “Should I hold on to heifers to grow my herd, or sell them?” The specialist has to answer with evidence about where the state and the country are in the cattle cycle.

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

