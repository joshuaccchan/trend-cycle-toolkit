# trend-cycle-toolkit

Bayesian unobserved components models for US trend inflation, the output gap and trend output
growth, by [Joshua Chan](https://joshuachan.org). Three series from five models, re-estimated
every quarter from public data.

## Status

The data layer and all five models are written. Each model reproduces the published driver it
was taken from, draw for draw: four against the data that driver's own package ships, and
`ucsv_sw07` against the book's `chapter10/UCSV.m` on CPI inflation fetched by `uc.data`. The
seed and chain length of each check are in the model's file header. Six of the seven functions
under `estimates/` are documented stubs that error when called, and phase 5 builds them;
`resolve_break_dates.m` is working code. No estimate has been produced yet.

## The Three Series

| Series | Written to | Produced by |
|---|---|---|
| Trend inflation | `estimates/current/trend_inflation.csv` | `ucsv_sw07`, `ar_trend_bound`, `biuc_lrexp` |
| Output gap | `estimates/current/output_gap.csv` | `uc_2m`, `ucur_break2` |
| Trend output growth | `estimates/current/trend_growth.csv` | `uc_2m`, from the same draws as its gap |

Each release also writes `diagnostics.csv`, holding inefficiency factors, Monte Carlo standard
errors and Geweke statistics for every published parameter; `trend_cycle_estimates.xlsx`, holding
the same three series in one workbook; and `metadata.json`, recording the vintage, the git SHA,
the seed and settings of each model, and the URL, fetch time and SHA-256 of every input. The
revision tolerance is `max(0.20pp, 3 x MCSE)`, which separates a revision from the sampler's own
noise.

Every release is frozen under `estimates/vintages/YYYYQq/` and tagged, so a paper can cite a
fixed vintage. The first release creates those directories.

## The Five Models

| Model | Series | Method source | Data | Sample |
|---|---|---|---|---|
| `uc.models.ucsv_sw07` | Trend inflation | Stock and Watson (2007, JMCB 39(s1): 3–33) | `CPIAUCSL` | 1947Q2– |
| `uc.models.ar_trend_bound` | Trend inflation | Chan, Koop and Potter (2013, JBES 31(1): 94–106) | `CPIAUCSL` | 1947Q2– |
| `uc.models.biuc_lrexp` | Trend inflation | Chan, Clark and Koop (2018, JMCB 50(1): 5–53) | `CPIAUCSL` + `PTRCPI` | 1960Q1– |
| `uc.models.uc_2m` | Output gap **and** trend growth | Grant and Chan (2017, JEDC 75: 114–121) | `GDPC1` | 1947Q1– |
| `uc.models.ucur_break2` | Output gap | Grant and Chan (2017, JMCB 49(2-3): 525–552) | `GDPC1` | 1947Q1– |

The four Chan papers have replication packages at
[joshuachan.org/code.html](https://joshuachan.org/code.html): `ARtrendbound.zip`,
`trend_IE_code.zip`, `output_gap_2M_code.zip` and `output_gap_code.zip`. `ucsv_sw07` follows
`chapter10/UCSV.m` in the book repository,
[bayesian-macroeconometrics](https://github.com/joshuaccchan/bayesian-macroeconometrics).

Every model runs on all available data. Each sample begins at the first quarter its inputs
support, so a release extends the sample at the end. `biuc_lrexp` begins in 1960Q1, where
`PTRCPI` begins: FRB/US `PTR` starts in 1968Q1, and `uc.data.build_ptrcpi` backfills 1960Q1
through 1967Q4 flat at its first value.

`uc_2m` puts a second-order Markov process on the trend, the trend the Hodrick-Prescott filter
implies, and lets the cycle be serially correlated, which the filter does not allow; its implied
trend growth varies smoothly from quarter to quarter. Trend growth is a main output of that paper
and is computed from the same draws as the gap. `ucur_break2` correlates the trend and cycle
errors and places two breaks in trend growth, at 1973Q1 and 2007Q1, estimating a drift for each
of the three regimes, so its implied trend growth is a step function. The two models run on the
same series, so the distance between their gap estimates is what the specification contributes.

These are re-implementations, and each differs from the driver it was taken from in recorded
ways: data arrives as an argument, the seed is set from one, and the plotting and the
marginal-likelihood step are out. Every model's file header lists its own divergences, and each
changed line is marked in the body.

## How the Estimates Update

Estimation runs on one machine, on the 1st of March, June, September and December, driven by
`tools/run_update.ps1` (phase 5), which commits and pushes what it wrote. GitHub Actions runs a
weekly freshness check and the unit suite. `RELEASE_CALENDAR.md` lists the dates, the inputs each
release requires, and the revision policy.

## The Code

```
core/+uc/          the library
  +data            fetchers, the PTRCPI splice, alignment and transforms, the
                   incomplete-quarter guard, the vintage stamp
  +models          the five models
  +sv              ksc_rw_h0, ksc_rw_h0_Vh, rw_gaussian_approx
  +util            surform, build_hpsi, llike_maq
estimates/         the release pipeline — see estimates/README.md   (phase 5)
run_release.m      the driver                                       (phase 5)
setup.m            puts the repository root and core/ on the path
```

Each model is checked once, as it is written, against the driver it was taken from. Download that
package from [joshuachan.org/code.html](https://joshuachan.org/code.html) into a scratch
directory outside the repository, or take `chapter10/UCSV.m` from
[bayesian-macroeconometrics](https://github.com/joshuaccchan/bayesian-macroeconometrics) for
`ucsv_sw07`, run it on the data the check uses, run the implementation here on the same data
under the same seed, and require the same draws. The model's file header records what changed in
the lift and which draws matched. The check confirms the implementation against the published
driver before any number is published.

## Requirements

MATLAB R2020a or later, for `exportgraphics` in the publication step. The Statistics and Machine
Learning Toolbox is needed by the three trend inflation models and by both samplers in `uc.sv`,
which call `gamrnd`, `normcdf` and `normpdf`; the two output-gap models run on base MATLAB. The
Optimization Toolbox is needed by `biuc_lrexp`, whose psi block runs `fminsearch` and then
`fminunc`; a release without it contains two of the three trend inflation columns. Parallel
Computing is optional and shortens a release run. `setup.m` checks all three and reports which
models a missing toolbox removes from the release.

## Sibling Repositories

[bvar-toolkit](https://github.com/joshuaccchan/bvar-toolkit) is a library for large Bayesian
VARs, and archives the replication package for the precision sampler of Chan and Jeliazkov
(2009), with which every model here draws its state paths;
[chan-jeliazkov-2009](https://github.com/joshuaccchan/chan-jeliazkov-2009) holds worked MATLAB
examples of that sampler. [bayesian-macroeconometrics](https://github.com/joshuaccchan/bayesian-macroeconometrics)
has MATLAB, Python and R code for all fourteen chapters of the book, and is the source of
`ucsv_sw07` and `uc.sv.ksc_rw_h0`.

## Citation

`CITATION.cff` is the machine-readable record that GitHub's "Cite this repository" button reads. Cite the paper whose model you use, listed in the table above, together with the vintage
of the series you used.

## License

MIT covers all code here: `core/` and the drivers and helpers in `estimates/`. `LICENSE` gives
the full text.

The published series are a dataset and carry CC-BY-4.0. That covers the CSV, XLSX, JSON, PNG and
PDF files under `estimates/current/`, `estimates/vintages/`, `estimates/revisions/` and
`estimates/figures/`. Use them anywhere, including commercially, with attribution: cite this
repository, the vintage you took the numbers from, and the paper behind the series you use.

Four of the five models are joint work — with Gary Koop and Simon M. Potter, with Todd E. Clark
and Gary Koop, and two with Angelia L. Grant — and the fifth is by James H. Stock and Mark W.
Watson. Cite the paper whose model you use. Where a function body in `core/+uc/` derives from a
published package, that file's header names the package and the file it came from. Those packages
are at [joshuachan.org/code.html](https://joshuachan.org/code.html).
