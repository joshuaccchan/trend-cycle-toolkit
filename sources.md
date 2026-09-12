# Data sources

Every input a release fetches, where it comes from, and what is done to it. When a published
number looks wrong the first question is which input moved, and the answer has to be on paper.

The fetchers are in `core/+uc/+data/`. Every endpoint below was verified live on **2026-09-11**.

## Input series

| Series | Source | Endpoint | Transform | Used by |
|---|---|---|---|---|
| `DPCERD3Q086SBEA` — PCE chain-type price index | FRED (BEA) | `fredgraph.csv?id=DPCERD3Q086SBEA&fq=Quarterly` — natively quarterly | `400*log` difference, giving annualized percent | the three trend inflation models |
| `GDPC1` — real GDP, chained dollars | FRED (BEA) | `fredgraph.csv?id=GDPC1` — natively quarterly | `100*log` of the level | `uc_2m`, `ucur_break2` |
| `PTR` — FRB/US 10-year expected PCE inflation | Federal Reserve Board | `federalreserve.gov/econres/files/data_only_package.zip`, `HISTDATA.TXT` | flat backfill over 1960Q1–1967Q4 | `biuc_lrexp` |

Data is fetched and archived as **levels**. What a release stores under `estimates/sources/` is
what the source published, so a later run can attribute a revision to the data rather than to the
sample or to Monte Carlo error.

Inflation is PCE. `DPCERD3Q086SBEA` is the NIPA quarterly series and reaches back to 1947Q1;
FRED's `PCEPI` is the same concept and begins in 1959Q1. Differenced, it reproduces the `PCEINFL`
column of `trend_IE_code.zip/cck1_data.xlsx` from 1947Q2 at a correlation of 0.99901 with a mean
difference of 0.002. `PTR` is published in PCE terms, and `cck1_data.xlsx` columns B and C — what
that package's own `M1.m` reads — are PCE inflation and `PTR`.

## The backfill

`HISTDATA.TXT` starts `PTR` at **1968Q1** with a first value of **1.6827**, and `biuc_lrexp`
starts in 1960Q1, so `uc.data.build_ptr` holds the series flat at that first value over the 32
quarters between. The reconstruction agrees with `cck1_data.xlsx` column C to 0.005 over all 225
quarters it ships. The `parts` output marks which quarters are backfilled and which are observed.

No wedge and no splice: `PTR` and the inflation series are both in PCE terms.

`PTR` sets `biuc_lrexp`'s sample end. It is the whole expectations series, so a release runs that
model only as far as the last quarter in the FRB/US package, and when the Board has not refreshed
it that model ends a quarter behind the other four.

## Fetch traps

Each of these was reproduced against the live source. Each is a silent wrong answer, not an
error, which is why they are written down.

1. **FRED returns the running quarter as a present row with an empty value.** Parsed naively it
   becomes `NaN` and a log difference spreads it. `uc.data.drop_incomplete_tail` removes it, and
   which series carry one varies from quarter to quarter.
2. **The FRB/US package contains two data files.** `LONGBASE.TXT` runs to **2176Q2**: it appends
   a projection to history. Read `HISTDATA.TXT` only, and assert its last `OBS` is not in the
   future. `PTR` is column 183 of 366, and that layout is reorganized from time to time, so it is
   located by name.
3. **MATLAB's HTTP stack hangs on `fredgraph.csv` without a User-Agent**, for sixty seconds and
   then a timeout that reads like a network fault. Every fetcher sets one.
4. **`fredgraph.csv` silently ignores a `vintage_date` parameter**, returning the current vintage
   byte-identically. There is no real-time vintage without the FRED API, which is why each
   release archives its own raw fetch.

## Off the release path

`uc.data.fetch_spf_cpi10` fetches the Philadelphia Fed's median 10-year-ahead CPI forecast. No
release fetches it. It is the only public long-run CPI expectation, and it begins in 1991Q4.
