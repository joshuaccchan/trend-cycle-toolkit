# The release pipeline

Everything that turns fetched data into a published vintage. `run_release.m` at the repository
root is the driver; these seven functions are the stages it calls.

`setup.m` keeps `estimates/` off the path — `run_release` adds it for the run — so calling one
of these by hand needs `addpath estimates` first.

## The pipeline

Fetch and archive the source vintage, validate it, run the models, compare against the previous
vintage, check, then publish. Estimates are written to a staging path under `build/` and copied
into `estimates/` only once every guardrail passes.

That separation is the point of the design. `matlab -batch` exits 0 on a NaN posterior, so a
failed run looks exactly like a successful one to the shell. Promotion is an explicit step that
happens after the checks, and `build/` is git-ignored, so a refused release leaves nothing behind
that could be mistaken for a published number.

## The interface

These seven have almost no callers — six are called from `run_release.m` and the seventh from
`run_estimates.m` — so a header that drifts from its call site goes unnoticed until a release run
reaches it. This table, those headers and `run_release.m` agree argument for argument.

| Call | Returns |
|---|---|
| `cfg = preset(models, Name, Value)` | One settings struct per model named, in order. `models` is one name or a cellstr. Overrides: `NSim`, `Burnin`, `Thin`, `Seed`, `SampleStart` |
| `idx = resolve_break_dates(break_dates, sample_dates)` | One row index per configured break quarter, into the sample's own date axis. Errors on a break out of range, out of order, or in an empty regime |
| `results = run_estimates(cfg, data, Name, Value)` | One result struct per model: thinned draws, summaries, diagnostics, acceptance rates, seed, settings, elapsed time. Options `SampleEnd`, `Parallel`, `StageDir` |
| `previous = load_previous_vintage(root, vintage)` | The newest archived vintage strictly older than `vintage`. Empty on the first release |
| `revs = revisions(results, previous, data, Name, Value)` | The revision table, decomposed into the components asked for. Option `Components`, default `{'sample'}` |
| `report = guardrails(results, previous, data, revs, Name, Value)` | One report struct: `pass`, `nfail`, `checks`, `vintage`, `seasonal`. Options `Vintage`, `SeasonalRevision` |
| `files = publish(results, report, revs, manifest, stagedir, Name, Value)` | The files written, in write order. Options `Vintage`, `Promote`, `Mode`. The only function here that writes into `estimates/` |

Two conventions hold across all seven: positional arguments are the things a call cannot do
without, so a missing one errors instead of silently skipping a check; and every option name is
capitalized, matching the seven `run_release.m` itself takes.

`revisions` computes the revision table and returns it. `publish` writes it, once the guardrails
are green — a table written before that gate would leave a file in the tracked tree from a
release that was refused.

## Settings and runtimes

`preset.m` holds each model's chain length, thinning, seed and sample start, with the published
driver each setting comes from named beside it. Sample starts are settled: every model runs on
all available data, so each start is the first quarter its inputs support.

A model without a measured runtime does not go on the schedule. Measured 2026-09-11 on the
release machine, at the settings above and so with the marginal likelihood off:

| model | minutes |
|---|---|
| `ucsv_sw07` | 0.4 |
| `ucur_break2` | 0.8 |
| `uc_2m` | 0.9 |
| `ar_trend_bound` | 1.1 |
| `biuc_lrexp` | 3.4 |

Six and a half minutes in series, four with two workers. `model_lists` in `run_release.m` is what
actually opens the schedule, and it still lists none of them — that is a decision to take once
G7 is settled, not a consequence of the timing.

## Chain Lengths

Three models run longer chains than their published drivers, each because the effective sample at
the published length falls below the 100 G7 requires: `ucsv_sw07` measured 61, `biuc_lrexp` 40 and
`uc_2m` 40, on data running eleven years past the samples those papers used. Measured 2026-09-12
at the settings in `preset.m`:

| model | nsim / burnin | published | stored | minutes |
|---|---|---|---|---|
| `ucsv_sw07` | 110,000 / 10,000 | 51,000 / 1,000 | 10,000 | 0.7 |
| `ar_trend_bound` | 35,000 / 5,000 | as published | 3,000 | 0.9 |
| `biuc_lrexp` | 400,000 / 40,000 | 31,000 / 1,000 | 36,000 | ~37 |
| `uc_2m` | 430,000 / 30,000 | 110,000 / 10,000 | 40,000 | 3.3 |
| `ucur_break2` | 110,000 / 10,000 | as published | 10,000 | 0.8 |

G7 gates on effective sample size alone. Geweke Z is computed and written to `diagnostics.csv`,
and it is not a release gate: most of what it scores are points on one state path, which move
together, so a share of them carries much less information than its face value suggests. It is
also sensitive to the truncation lag used for the long-run variance — `uc.diag.geweke`'s own
`'auto'` rule picks 9 lags on a 40,000-draw chain whose integration time is nearly 300, which
inflates every Z on a persistent path at once. `run_estimates` passes it the same lag `ineff` and
`mcse` use, capped against the segment being tested.
