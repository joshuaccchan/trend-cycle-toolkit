# Data sources

Every input a release fetches, where it comes from, and what is done to it. When a published
number looks wrong the first question is which input moved, and the answer has to be on paper.

The fetchers are in `core/+uc/+data/`. Every endpoint below was verified live on
**2026-09-09**, and the values quoted are what those requests returned.

## Input series

| Series | Source | Endpoint | Transform | Used by |
|---|---|---|---|---|
| `CPIAUCSL` — CPI, all items, seasonally adjusted | FRED (BLS) | `fredgraph.csv?id=CPIAUCSL&fq=Quarterly&fam=avg` | `400*log` difference of the quarterly average, giving annualized percent | the three trend inflation models |
| `GDPC1` — real GDP, chained dollars | FRED (BEA) | `fredgraph.csv?id=GDPC1` — natively quarterly | `100*log` of the level | `uc_2m`, `ucur_break2` |
| SPF median CPI10 — median 10-year-ahead CPI forecast | Philadelphia Fed | `philadelphiafed.org/-/media/frbp/.../median_cpi10_level.xlsx`, sheet `Median_Level` | none | `PTRCPI` |
| `PTR` — FRB/US 10-year expected PCE inflation | Federal Reserve Board | `federalreserve.gov/econres/files/data_only_package.zip`, `HISTDATA.TXT` | `+0.4`, the long-run CPI–PCE wedge | `PTRCPI` |
| `PTRCPI` — long-run CPI inflation expectations | Derived, not fetched | — | see below | `biuc_lrexp` |

`fq=Quarterly&fam=avg` puts the monthly-to-quarterly aggregation on FRED's side, which is the
construction the published inflation series is defined by: `400*log`-differencing that request's
output reproduces `ARtrendbound`'s shipped `USCPI_Q.csv` to 2e-10 over quarters BLS has not since
revised. The response opens at `CPIAUCSL` 1947Q1 = 21.700, and that value is the fetch check on
every release.

Data is fetched and archived as **levels**. What a release stores under `estimates/sources/` is
what the source published, so a later run can attribute a revision to the data rather than to the
sample or to Monte Carlo error.

## `PTRCPI`, the one derived series

`biuc_lrexp` needs a long-run CPI expectation running back to 1960 and no single published series
covers that span, so three pieces are spliced:

| Span | Source |
|---|---|
| 1960Q1 – 1967Q4 | flat backfill at `PTR`'s own first value, 1.6827, plus 0.4 |
| 1968Q1 – 2005Q4 | FRB/US `PTR` + 0.4 |
| 2006Q1 onward | SPF median CPI10, directly |

`HISTDATA.TXT` starts `PTR` at **1968Q1**, not 1962, which is what fixes the backfill at 32
quarters. The SPF cannot cover the early span instead: it is `#N/A` before 1991Q4.

`estimates/guardrails.m` checks the result — `PTR` present, its last observation not in the
future, and the 2006Q1 splice continuous. Those are structural checks, not a value-by-value
comparison: a fault shifting every value by the same amount would pass all three.

## Fetch traps

Each of these was reproduced against the live source. Each is a silent wrong answer, not an
error, which is why they are written down.

1. **FRED returns the running quarter as a present row with an empty value.** Today that is
   `2026-07-01,` for `CPIAUCSL`. Parsed naively it becomes `NaN` and a log difference spreads it.
   It affects `CPIAUCSL` but not `GDPC1`.
2. **The Philadelphia Fed answers HTTP 200 with an HTML error page** for an unknown media path.
   Status is not evidence — validate magic bytes (`50 4b 03 04` for the xlsx).
3. **The FRB/US package contains two data files.** `LONGBASE.TXT` runs to **2176Q2**: it appends a
   projection to history. Read `HISTDATA.TXT` only, and assert its last `OBS` is not in the future.
   `PTR` is column 183 of 366, and that layout is reorganized from time to time.
4. **SPF CPI10 is the literal string `#N/A` before 1991Q4** — 92 such rows against 140 numeric.
   Read as a number it is `NaN`; read as text it is a string in a numeric column.

One more thing that is not a trap but is worth knowing: `fredgraph.csv` **silently ignores** a
`vintage_date` parameter, returning the current vintage byte-identically. There is no real-time
vintage without the FRED API, which is why each release archives its own raw fetch.
