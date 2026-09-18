# trend-cycle-toolkit

Bayesian unobserved components models for US trend inflation, the output gap and trend output
growth, by [Joshua Chan](https://joshuachan.org). Three series from six models, re-estimated
every quarter from public data.

## Status

The current vintage is **2026Q2**, released 2026-09-12 and tagged `v2026Q2`. It covers 1947Q1
onward, except `biuc_lrexp`, which begins in 1960Q2 and ends where FRB/US `PTR` ends. A release is
promoted only when every check in `estimates/guardrails.m` passes, and this one did.
`RELEASE_CALENDAR.md` carries the release history.

## The Three Series

| Series | Written to | Produced by |
|---|---|---|
| Trend inflation | `estimates/current/trend_inflation.csv` | `ucsv_sw07`, `ar_trend_bound`, `biuc_lrexp`, `uc_ma` |
| Output gap | `estimates/current/output_gap.csv` | `uc_2m`, `ucur_break2` |
| Trend output growth | `estimates/current/trend_growth.csv` | `uc_2m`, from the same draws as its gap |

Each release also writes `diagnostics.csv`, holding inefficiency factors and Monte Carlo standard
errors for every published parameter and date with Geweke statistics on the scalar parameters;
`trend_cycle_estimates.xlsx`, holding the three series in one workbook; and `metadata.json`,
recording the vintage, the git SHA, the seed and settings of each model, and the URL, fetch time
and SHA-256 of every input.

Every release is frozen under `estimates/vintages/YYYYQq/` and tagged, with the source data it was
estimated on beside it, so a paper can cite a fixed vintage.

## The Six Models

| Model | Series | Method source | Data | Sample |
|---|---|---|---|---|
| `uc.models.ucsv_sw07` | Trend inflation | Stock and Watson (2007, JMCB 39(s1): 3–33) | `DPCERD3Q086SBEA` | 1947Q2– |
| `uc.models.ar_trend_bound` | Trend inflation | Chan, Koop and Potter (2013, JBES 31(1): 94–106) | `DPCERD3Q086SBEA` | 1947Q2– |
| `uc.models.biuc_lrexp` | Trend inflation | Chan, Clark and Koop (2018, JMCB 50(1): 5–53) | `DPCERD3Q086SBEA` + `PTR` | 1960Q2– |
| `uc.models.uc_ma` | Trend inflation | Chan (2013, JoE 176(2): 162–172) | `DPCERD3Q086SBEA` | 1947Q2– |
| `uc.models.uc_2m` | Output gap **and** trend growth | Grant and Chan (2017, JEDC 75: 114–121) | `GDPC1` | 1947Q1– |
| `uc.models.ucur_break2` | Output gap | Grant and Chan (2017, JMCB 49(2-3): 525–552) | `GDPC1` | 1947Q1– |

The five Chan papers have replication packages at
[joshuachan.org/code.html](https://joshuachan.org/code.html): `ARtrendbound.zip`,
`trend_IE_code.zip`, `MASV_matlab.zip`, `output_gap_2M_code.zip` and `output_gap_code.zip`.
`ucsv_sw07` follows `chapter10/UCSV.m` in the book repository,
[bayesian-macroeconometrics](https://github.com/joshuaccchan/bayesian-macroeconometrics).

**Trend inflation here is PCE inflation.** `biuc_lrexp` pairs inflation with FRB/US `PTR`, which
is published in PCE terms, and that is the combination reaching back to 1960 that Chan, Clark and
Koop report and that their `M1.m` reads. The other three models follow PCE so the four columns
share one price index.

Every model runs on all available data, beginning at the first quarter its inputs support, so a
release extends the sample at the end. `biuc_lrexp` begins in 1960Q2, where `uc.data.build_ptr`
holds `PTR` flat back from its 1968Q1 start as the published package does, and ends where `PTR`
ends, so when the Board has not refreshed the FRB/US package that column runs a quarter behind
the others.

`uc_ma` has a random-walk trend with a constant variance and MA(1) transitory errors with
stochastic volatility, which in Chan (2013) makes the trend much smoother than the same model
without the MA(1) term, and smoother than `ucsv_sw07`, whose trend variance is itself stochastic.

`uc_2m` puts a second-order Markov process on the trend, the trend the Hodrick-Prescott filter
implies, and lets the cycle be serially correlated, which the filter does not allow; its trend
growth varies smoothly from quarter to quarter and is computed from the same draws as the gap.
`ucur_break2` correlates the trend and cycle errors and breaks trend growth at 1973Q1 and 2007Q1,
estimating a drift for each of the three regimes, so its trend growth is a step function. The two
run on the same series, so the distance between their gap estimates is what the specification
contributes.

These are re-implementations. Each takes its data and settings as arguments where the published
driver hard-coded them, seeds from `rng(seed,'threefry')` where the driver seeded from the clock,
and drops the plotting and the marginal-likelihood step. Nothing in the samplers themselves is
touched, and lines that differ from the published driver are marked `[uc]`. Three models run
longer chains than their drivers did, because on current data the published lengths leave too
small an effective sample; `estimates/preset.m` carries both lengths and `estimates/README.md`
the measurements.

## How the Estimates Update

A scheduled task runs `tools/run_update.ps1 -IfNewData` every Monday, which checks FRED for a new
quarter and, when there is one, estimates, commits, tags and pushes what the run promoted. That
falls shortly after BEA's advance estimate of GDP, about a month after the quarter ends. A refused
release leaves the tracked tree untouched and its report under `build/`. GitHub Actions runs a
weekly freshness check and the unit suite. `RELEASE_CALENDAR.md` lists the dates, the inputs each
release requires, and the revision policy.

## The Code

```
core/+uc/          the library
  +data            fetchers, the PTR backfill, alignment and transforms, the
                   incomplete-quarter guard, the vintage stamp
  +models          the six models
  +sv              ksc_rw_h0, ksc_rw_h0_Vh, ksc_ar1, rw_gaussian_approx
  +diag            inefficiency factors, MCSE, Geweke Z
  +util            surform, build_hpsi, llike_maq, nllike_ma1_sv, sample_psi
estimates/         the release pipeline — see estimates/README.md
run_release.m      the driver
tools/             run_update.ps1, the scheduled entry point
tests/unit/        the unit suite, run by CI and before every release
tests/equivalence/ each model against its published code, draw for draw
setup.m            puts the repository root and core/ on the path
```

`tests/equivalence/run_equivalence.m` runs each published sampler and the function here from one
seed on the package's own data, and requires identical draws. All six match. It downloads the
packages from [joshuachan.org/code.html](https://joshuachan.org/code.html), so it needs the
network and is run by hand after any change to a model.

## Requirements

MATLAB R2020a or later, for `exportgraphics` in the publication step. The Statistics and Machine
Learning Toolbox is needed by the four trend inflation models and by the samplers in `uc.sv`; the
Optimization Toolbox by `biuc_lrexp` and `uc_ma`, whose psi steps run `fminsearch` and then
`fminunc`. The two output-gap models run on base MATLAB, and Parallel Computing is optional.
`setup.m` checks all three and reports which models a missing toolbox removes from the release.

## Sibling Repositories

[bvar-toolkit](https://github.com/joshuaccchan/bvar-toolkit), a library for large Bayesian VARs,
archives the replication package for the precision sampler of Chan and Jeliazkov (2009), with
which every model here draws its state paths, and
[chan-jeliazkov-2009](https://github.com/joshuaccchan/chan-jeliazkov-2009) holds worked examples
of it. [bayesian-macroeconometrics](https://github.com/joshuaccchan/bayesian-macroeconometrics)
has MATLAB, Python and R code for the book's fourteen chapters, and is the source of `ucsv_sw07`
and `uc.sv.ksc_rw_h0`.

## Citation

`CITATION.cff` is the machine-readable record behind GitHub's "Cite this repository" button. Cite
the paper whose model you use, from the table above, together with the vintage you took the
numbers from.

## License

MIT covers all code here: `core/` and the drivers and helpers in `estimates/`. `LICENSE` gives
the full text.

The published series are a dataset and carry CC-BY-4.0. That covers the CSV, XLSX, JSON, PNG and
PDF files under `estimates/current/`, `estimates/vintages/`, `estimates/revisions/` and
`estimates/figures/`. Use them anywhere, including commercially, with attribution: cite this
repository, the vintage you took the numbers from, and the paper behind the series you use.
