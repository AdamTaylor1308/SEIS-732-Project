# A Cattle Cycle Review
U.S. and Minnesota beef cattle inventory, 1920–2022 (USDA NASS data as of Jan 1, 2022)
---
**Author:** Adam Taylor  ·  **Course:** SEIS 732 Data Warehousing  ·  **Status:** P0 – Feasibility
---

## Purpose
This repository currently contains the **P0 feasibility check**. It covers who the product is for, the questions it should answer, the source dataset, and the small reproducible queries used to confirm that the source can support those questions.

## The Cattle Cycle
Beef cattle numbers rise and fall in a cycle of roughly 8–12 years:
- When prices are high, ranchers keep young female cattle (heifers) to grow their herds.
- A heifer takes about 2 years to produce a calf, and that calf takes another 1–2 years to reach market. So extra supply arrives years later, and prices drop.
- When prices are low, ranchers sell off cows and the herd shrinks. That eventually tightens supply, prices rise again, and the cycle repeats.
---

## P1 files

| File | What it contains |
|---|---|
| [docs/p1_plan.md](docs/p1_plan.md) | Question, source check and grain test, model and history plan, build plan with checks, change memo |
| [docs/model.md](model.md) | Planned dimensional model of the data warehouse using Mermaid |
| [sql/01_source_profile.sql](sql/01_source_profile.sql) | Reproducible grain, coverage, revision, lead-lag and price-series queries (1–13) |

## P0 files

| File | What it contains |
|---|---|
| [docs/p0-feasibility.md](docs/p0-feasibility.md) | Audience, questions, source, profile, need-to-source fit, risks, first P1 decision, AI/tool use |
| [sql/00_feasibility.sql](sql/00_feasibility.sql) | Reproducible schema, row-count, coverage and data-quality queries |
| [evidence/p0-feasibility-results.md](evidence/p0-feasibility-results.md) | Summarized results of those queries (counts, ranges, constraints only, no source rows) |

## Audience
State beef extension specialists (e.g., at a land-grant university extension service) who advise **cow-calf producers** on herd expansion decisions. The product tracks the U.S. beef cattle cycle (inventory, prices, slaughter) using USDA NASS data in BigQuery.

## Need
Each fall and winter, ranchers ask, “Should I hold on to heifers to grow my herd, or sell them?” The specialist has to answer with evidence about where the state and the country are in the cattle cycle.

## Data source

- **Dataset:** USDA National Agricultural Statistics Service (NASS) Quick Stats
- **BigQuery location:** `bigquery-public-data.usda_nass_agriculture`
- **Primary table:** `animals_products` (filtered to `commodity_desc = 'CATTLE'`)
- **Other candidate tables:** None for now. Census tables may later be considered to analyze county-level data
- **Coverage observed:** state inventory 1867–2022; prices received 1909–2022; county inventory 1920–2022 (see evidence file for details)
- **Region:** US
- **Refresh:** Static snapshot; dataset description reads "Data Updated On: 2023-03-18".
- **Links:** https://console.cloud.google.com/bigquery?p=bigquery-public-data&d=usda_nass_agriculture&page=dataset · https://quickstats.nass.usda.gov/ · https://quickstats.nass.usda.gov/src/glossary.pdf
- **Use and attribution:** Source data are USDA NASS Quick Stats, listed on Data.gov as public under a [Creative Commons CC0](http://creativecommons.org/publicdomain/zero/1.0/) license ([Data.gov entry](https://catalog.data.gov/dataset/quick-stats-agricultural-database-api)). Accessed through Google Cloud's BigQuery public datasets. Credit: *USDA National Agricultural Statistics Service, Quick Stats.*

## Reproducing the P0 checks

1. Open the [BigQuery console](https://console.cloud.google.com/bigquery) in the course Google Cloud project.
2. Open `sql/00_feasibility.sql` and run each query separately. **Check the estimated bytes processed** before running.
3. Compare the output with `evidence/p0-feasibility-results.md`.

No credentials, service-account keys or local data files are needed or stored in this repository.

## Repository structure

```
README.md
.gitignore
docs/
  p0-feasibility.md
  p1-plan.md
  model.md
evidence/
  p0-feasibiliity-results.md
sql/
  00_feasibility.sql
  01_source_profile.sql
```

## Data handling

- This repository contains **SQL and summarized results only**. It holds no source rows, extracts or downloads.
- Secrets, credentials and data files are excluded in [.gitignore](.gitignore).

## Milestones

| Milestone | Tag / commit | Notes |
|---|---|---|
| P0 – Need, audience, dataset & feasibility | p0-submission | complete 10/14 |
| P1 | | |
| P2 | | |
| P3 | | |
| P4 | | |
