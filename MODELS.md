# Which Estimate Should I Use?

The six models estimate three different objects: four produce trend inflation, two produce the
output gap, and one of those two also produces trend output growth. Within trend inflation the
four models estimate the same object under different assumptions, and they disagree materially.
The spread in the current release is in [Estimates as of the Current Vintage](#estimates-as-of-the-current-vintage).

Each model also reports a credible interval, which describes uncertainty conditional on that
model's assumptions. The two are different quantities: reporting several specifications
demonstrates how far the estimate depends on assumptions, and it does not quantify model
uncertainty. Where the choice of model is not clear, report more than one and say why.

| If you want | Use | The assumption you are accepting |
|---|---|---|
| The standard forecasting benchmark for inflation | `ucsv_sw07` | Permanent and transitory innovations both carry stochastic volatility, and nothing restricts the trend |
| A trend restricted to a plausible range | `ar_trend_bound` | Trend inflation lies between 0 and 5 percent, and the inflation gap is persistent |
| A trend estimated jointly with measured expectations | `biuc_lrexp` | A survey measure of long-run expectations is informative about the trend, through a link that drifts over time |
| Short-run dependence held in the transitory component | `uc_ma` | Transitory errors follow an MA(1), and the trend innovation variance is constant |
| An output gap with a smooth trend and large cycles | `uc_2m` | Shocks reach the trend only through its growth rate, whose variance the prior bounds tightly, as the Hodrick-Prescott filter implies |
| An output gap whose trend follows output closely | `ucur_break2` | The trend level takes shocks directly, around a drift that is constant between the breaks at 1973Q1 and 2007Q1 |
| Trend output growth | `uc_2m` | As above; it is the only published trend growth series |

## Trend Inflation

The four models decompose annualized quarterly PCE inflation into a trend and a transitory
component. They differ in what the trend is permitted to do and in what the transitory component
can account for, and these two choices explain the differences between the published series.

### Stock and Watson (2007): `ucsv_sw07`

Unobserved components with stochastic volatility in both the transitory and the permanent
innovation:

    y_t   = tau_t + exp(h_t/2) e_t
    tau_t = tau_{t-1} + exp(g_t/2) u_t

where `tau_t` is trend inflation and the log-volatilities `h_t` and `g_t` are random walks. No
restriction is placed on the level of the trend, and the relative size of the two volatilities
governs how much of a movement in inflation is attributed to the trend. The estimated trend is
the most variable of the four.

This model is the standard benchmark in the inflation forecasting literature, which makes it the
natural choice for comparison with published forecasting results. The sample begins in 1947Q2.

### Chan, Koop and Potter (2013): `ar_trend_bound`

The inflation gap follows a time-varying AR(1), and the trend is bounded:

    y_t - tau_t = rho_t (y_{t-1} - tau_{t-1}) + u_t,   u_t ~ N(0, exp(h_t))
    tau_t = tau_{t-1} + v_t,    0 < tau_t < 5
    rho_t = rho_{t-1} + w_t,    0 < rho_t < 1

where the bounds on `tau_t` are in annualized percent, and `rho_t` and the log-volatility `h_t`
are themselves random walks. A persistent inflation gap accounts for movements that would
otherwise be attributed to the trend, and the bounds restrict the trend further. The estimate is
the least variable of the four.

The bounds and the persistent gap are the assumptions to weigh before using this series. The
bounds encode a view about the monetary regime over the whole sample, including the 1970s, and a
study that uses the series should state it. The sample begins in 1947Q2.

### Chan, Clark and Koop (2018): `biuc_lrexp`

Inflation and a survey-based measure of long-run inflation expectations are modeled jointly. The
survey enters a second measurement equation whose intercept and loading on the trend are
time-varying, so the link between the two is estimated and allowed to drift. The survey measure
is `PTR` from the Federal Reserve Board's FRB/US model.

The second observable is itself informative about the trend, which is why the credible interval is
much narrower than the others. The series is not independent evidence that expectations are
anchored: the link between expectations and the trend is imposed by the specification, and what
the model estimates is its strength.

The sample begins in 1960Q2 and ends where `PTR` ends, which is 2026Q1 in the current vintage.

### Chan (2013): `uc_ma`

Unobserved components with an MA(1) transitory component and stochastic volatility:

    y_t   = tau_t + u_t + psi u_{t-1},   u_t ~ N(0, exp(h_t)),   |psi| < 1
    tau_t = tau_{t-1} + v_t,             v_t ~ N(0, sigma_tau^2)

where the log-volatility `h_t` is a stationary AR(1). Two assumptions separate this model from
`ucsv_sw07`: short-run dependence is held in the transitory component through the MA(1) term,
and the trend innovation variance is constant where UCSV makes it stochastic. Both contribute to
the difference between the two estimated trends.

Use this model where short-run dependence in inflation is better treated as transitory than as
movement in the trend. The sample begins in 1947Q2.

## The Output Gap

Both models decompose 100 log real GDP into a trend and a cycle, both estimate a correlation
between the trend and cycle innovations, and both allow the cycle to be serially correlated. They
differ in the trend equation, and that difference drives the difference between their gaps.

| Model | Trend | What the innovation hits | Prior bound on its variance |
|---|---|---|---|
| `uc_2m` | second-order Markov, `tau_t - tau_{t-1} = tau_{t-1} - tau_{t-2} + eta_t` | the growth rate | 0.01 |
| `ucur_break2` | random walk with regime drift, `tau_t - tau_{t-1} = mu_s(t) + eta_t` | the level | 3 |

In `ucur_break2` the level of the trend takes each shock directly, and the prior admits a large
innovation variance, so the trend follows a sharp movement in output and leaves little of it in
the cycle. In `uc_2m` only the growth rate takes the shock, under a prior that bounds its variance
at 0.01, so the trend turns slowly and a sharp movement stays in the cycle. The 2020Q2 column of
the table below shows the size of the difference, and the deepest gap each model estimates shows
that the same mechanism operates over the whole sample.

### Choosing Between the Two

The question to ask is how potential output behaves over the sample being studied. An analysis in
which potential output is smooth, and recessions are large deviations from it, matches `uc_2m`. An
analysis in which potential output itself moves with the economy, so that recessions leave smaller
gaps, matches `ucur_break2`. The break dates belong to the second assumption: they are set at
1973Q1 and 2007Q1 and are not estimated.

The choice determines the scale of the estimated gap as well as its shape, as the table below
shows. Both models are uncertain about the present to a degree worth reporting, and their credible
intervals at the end of the sample are wide.

## Trend Output Growth

Annualized trend growth, `4 (tau_t - tau_{t-1})`, is published from `uc_2m` and computed from the
same draws as its output gap. The model `ucur_break2` implies a trend growth rate as well. Its
drift `mu_s(t)` is a step function with three levels, while its realized trend growth is not,
since that carries the trend innovation `eta_t`. Only the `uc_2m` series is published.

## Estimates as of the Current Vintage

Everything above describes the models and holds from release to release. Everything between the
markers below is written by `estimates/model_summary.m` from the published CSVs, at every release.

<!-- BEGIN generated by estimates/model_summary.m -->

These numbers are from vintage 2026Q2, released 2026-09-12.

At 2026Q1, the most recent quarter every trend inflation model covers, the estimates run from 1.99 to 4.23 percent.

Trend inflation, in annualized percent. The band is the width of the 90 percent credible
interval at the model's last quarter, and the last column is the standard deviation of the
quarterly changes in the posterior mean over the whole sample.

| Model | Last quarter | Posterior mean | Band width | SD of quarterly changes |
|---|---|---|---|---|
| `ucsv_sw07` | 2026Q2 | 4.76 | 2.00 | 0.74 |
| `uc_ma` | 2026Q2 | 3.41 | 2.06 | 0.09 |
| `ar_trend_bound` | 2026Q2 | 2.76 | 2.63 | 0.03 |
| `biuc_lrexp` | 2026Q1 | 1.99 | 0.77 | 0.10 |

The output gap, in percent of trend output. The last column is the deepest gap each model
estimates anywhere in the sample.

| Model | Last quarter | Posterior mean | Band width | 2020Q2 | Deepest |
|---|---|---|---|---|---|
| `ucur_break2` | 2026Q2 | 0.16 | 5.03 | -1.95 | -2.36 (1949Q4) |
| `uc_2m` | 2026Q2 | 0.14 | 10.75 | -10.08 | -10.08 (2020Q2) |
<!-- END generated -->

Where two models agree about the level of the current gap, that carries no implication of
agreement about the past.

## Reading the Published Series

Every value is smoothed with the whole sample. The estimate reported for 1998Q3 uses data through
the end of the vintage, and it differs from the estimate that would have been produced in 1998.
These are not real-time series. The frozen vintages under `estimates/vintages/` record what each
release reported at the time.

The ends of the sample are the least precisely estimated part. A smoother conditions on data on
both sides of a date, and at the last observation there is data on one side only.

Estimates for past quarters change between releases, for three reasons: the source data were
revised, the sample grew, or the sampler is stochastic. The revision table in
`estimates/revisions/` reports the total change and the part of it attributable to the longer
sample. Separating the other two components requires re-estimating on the previous release's
archived data, which the pipeline does not do.

Models end at different quarters, since `biuc_lrexp` depends on the FRB/US package. Read each
model's last observation off the `date` column.

## Citing

Cite the paper whose model is used, from the table in [README.md](README.md), together with the
vintage the numbers were taken from. The current release tag is `v2026Q2.1`. All six references
are in `CITATION.cff` in machine-readable form.
