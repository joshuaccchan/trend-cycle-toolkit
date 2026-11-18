# trend-cycle-toolkit <img src=".github/logo.png" align="right" height="139" alt="trend-cycle-toolkit logo" />

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24329515.svg)](https://doi.org/10.5281/zenodo.24329515)

Quarterly estimates of **US trend inflation, the output gap and trend output growth** from six
Bayesian unobserved components models. The repository includes the estimates, archived input
data and MATLAB code.

[Explore the estimates](https://joshuachan.org/estimates.html) ·
[Download the Excel workbook](estimates/current/trend_cycle_estimates.xlsx) ·
[Browse past vintages](estimates/vintages/)

## Download the Estimates

| Series | Latest CSV | Units |
|---|---|---|
| Trend inflation | [trend_inflation.csv](estimates/current/trend_inflation.csv) | Annualized percent, based on PCE inflation |
| Output gap | [output_gap.csv](estimates/current/output_gap.csv) | Percent of trend output |
| Trend output growth | [trend_growth.csv](estimates/current/trend_growth.csv) | Annualized percent |

Each CSV has one row per date, model and measure. The measures are the posterior mean, the bounds
of the 68 and 90 percent credible intervals, and the Monte Carlo standard error of the mean.
[trend_inflation_wide.csv](estimates/current/trend_inflation_wide.csv) holds the posterior means
of trend inflation, one column per model. See the [figures](estimates/figures/current/),
[diagnostics](estimates/current/diagnostics.csv) and [release metadata](estimates/current/metadata.json)
for the latest vintage.

A new release follows BEA's advance estimate of GDP, about a month after each quarter ends. It is
published only when every check in [`estimates/guardrails.m`](estimates/guardrails.m) passes. To be
notified of new releases, choose Watch, then Custom, then Releases.

Each release re-estimates the full sample. These are smoothed estimates: a value for a past quarter
uses the data available through the end of that vintage. Historical estimates can change between
releases, because new quarters are added, source data are revised and the sampler is stochastic.
For reproducible work, use a [release](https://github.com/joshuaccchan/trend-cycle-toolkit/releases).
Each is archived on Zenodo with its own DOI and holds the inputs it was estimated on. See the
[release calendar](RELEASE_CALENDAR.md) and [data sources](sources.md).

## Choose a Model

Four models estimate trend inflation and two estimate the output gap. The `uc_2m` model also
reports trend output growth from the same draws as its output gap.

| Model | Estimates | Method paper |
|---|---|---|
| `ucsv_sw07` | Trend inflation | Stock and Watson (2007, JMCB) |
| `ar_trend_bound` | Trend inflation | Chan, Koop and Potter (2013, JBES) |
| `biuc_lrexp` | Trend inflation | Chan, Clark and Koop (2018, JMCB) |
| `uc_ma` | Trend inflation | Chan (2013, JoE) |
| `uc_2m` | Output gap and trend output growth | Grant and Chan (2017, JEDC) |
| `ucur_break2` | Output gap | Grant and Chan (2017, JMCB) |

[Which estimate should I use?](MODELS.md) compares the assumptions, sample coverage and estimates.
The `biuc_lrexp` model uses long-run inflation expectations from FRB/US and may end earlier than
the other models.

## Run the MATLAB Code

From the repository root, fit the Stock–Watson model to the PCE data archived with
the `v2026Q3` release:

```matlab
run('setup.m')
pce = readtable('estimates/vintages/2026Q3/sources/PCE.csv');
infl = uc.data.annualized_log_diff(pce);
fit = uc.models.ucsv_sw07(infl.value);
mean(fit.tau(:, end))   % posterior mean of trend inflation in the last quarter
```

This example uses the model's default settings, which run a shorter chain than the release. With
the release settings, `uc.models.ucsv_sw07(infl.value, 'NSim', 110000, 'Burnin', 10000)` reproduces
the published series, 2.77 percent in 2026Q3. [`estimates/preset.m`](estimates/preset.m) holds
the settings of every model, and [`estimates/README.md`](estimates/README.md) documents the release
pipeline. The [model code](core/+uc/+models/) has draw-for-draw
[checks against the source implementations](tests/equivalence/run_equivalence.m).

The full release pipeline requires MATLAB R2020a or later and is tested on R2025b. The inflation
models need the Statistics and Machine Learning Toolbox; `biuc_lrexp` and `uc_ma` also need the
Optimization Toolbox. The two output gap models run on base MATLAB.

## Cite the Work

If you use the estimates, cite the toolkit with the vintage you used, and the paper behind the
model:

> Chan, J. C. C. (2026). *trend-cycle-toolkit: US trend inflation, the output gap and trend output growth, re-estimated quarterly*. Zenodo. https://doi.org/10.5281/zenodo.24329515

The DOI resolves to the latest release. Each release also has its own DOI, listed on its Zenodo
record, for citing a fixed vintage.
[CITATION.cff](CITATION.cff) has the software citation and the six papers' full references.

## License

The code is [MIT licensed](LICENSE). The published dataset and its figures, diagnostics, release
metadata and revision files are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
