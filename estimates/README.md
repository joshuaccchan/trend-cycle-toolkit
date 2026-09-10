# The release pipeline

Everything that turns fetched data into a published vintage. `run_release.m` at the repository
root is the driver; these seven functions are the stages it calls.

Almost none of it is implemented. Six of the seven are documented stubs whose bodies error and
whose headers say what they will do and which phase builds them. `resolve_break_dates.m` is
working code. `setup.m` keeps `estimates/` off the path — `run_release` adds it for the run — so
calling one of these by hand needs `addpath estimates` first.

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

No model has a measured runtime, and a model without one does not go on the schedule. Phase 1
measures all five as this repository implements them, at these settings and so with the marginal
likelihood off, and records the figures in `RELEASE_CALENDAR.md`.
