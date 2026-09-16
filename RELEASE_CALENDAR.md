# Release calendar

The series in `estimates/current/` are re-estimated four times a year and frozen as a vintage
each time.

## The dates

**A release follows BEA's advance estimate of GDP**, which completes a quarter about a month after
it ends. Both inputs the five models read come from that release: real GDP and the PCE price
index. A scheduled task on the release machine runs `tools\run_update.ps1 -IfNewData` every Monday;
it asks FRED for the newest quarter complete in both series and releases when that quarter is
newer than the published vintage, so a release follows the advance estimate within a week. The vintage is taken from the data, so a BEA release that
slips cannot be labelled with a quarter the data do not reach.

| Estimates through | Released after BEA's advance estimate, around | Vintage tag |
|---|---|---|
| 2026Q2 | released 2026-09-12 | `v2026Q2` |
| 2026Q3 | late October 2026 | `v2026Q3` |
| 2026Q4 | late January 2027 | `v2026Q4` |
| 2027Q1 | late April 2027 | `v2027Q1` |
| 2027Q2 | late July 2027 | `v2027Q2` |

BEA publishes its schedule in advance, and it can change: in 2025 the advance estimate for the
third quarter was cancelled during the government shutdown and replaced by a combined estimate on
23 December. Triggering on the data rather than on a date is what makes that harmless.

BEA revises each quarter twice more, about a month apart, and revises several years of history in
its annual update. A release does not wait for those. The next release re-estimates the whole
sample on the revised data, and guardrail G8 judges only dates more than eight quarters before
the sample end, so revisions to recent quarters cannot fail it.

`PTR` is the input a release now waits for. It is the whole of `biuc_lrexp`'s expectations
series rather than its early half, so when the Board has not refreshed the FRB/US package
that model runs a quarter behind the other four. The release does not stall for it: the other
four publish on time and `biuc_lrexp` catches up at the next vintage.

Exact agency dates are not tabulated here; BEA's release schedule has them.

## What a release checks before it publishes

- **The reference quarter must match.** FRED returns the running quarter as a present row with an
  empty value. That row is dropped, and the run then asserts the data reach the vintage being
  released. A mismatch stops the release rather than publishing a quarter short.
- **Every fetch is validated by magic bytes, not HTTP status.** The Philadelphia Fed answers
  HTTP 200 with an HTML error page for an unknown path, so a status check passes a document that
  is not a spreadsheet. A failed validation reuses the last archived source vintage and opens an
  issue; it does not cancel the release.
- **The guardrails gate promotion.** Estimates are written to a staging path and copied into
  `estimates/` only once every check passes. `matlab -batch` exits 0 on a NaN posterior, so
  failure has to be an explicit error rather than an absent complaint. The full list is in
  `estimates/guardrails.m`.

## Revisions

Every vintage is a full two-sided re-estimation on the whole sample. A smoothed estimate at any
date uses the whole sample, so extending it by a quarter moves the entire path; holding old
values fixed would publish a series no model produced.

Vintages are frozen and never overwritten, which is what makes the archive a real-time record.

**Tolerances are anchored to Monte Carlo error.** A value more than eight quarters before the
sample end that moves by more than `max(0.20pp, 3 x MCSE)` is flagged; more than 1.0pp fails the
run pending a human.

Two breakages are expected rather than accidental:

- **BEA's annual update, every year.** It revises several years of PCE and GDP history, which moves
  the smoothed estimates at dates G8 judges; in 2026 it is on 30 September. The release after it is
  not told this. Guardrail G9 compares PCE inflation and GDP growth as the models read them now
  against the same rates rebuilt from the previous vintage's archived inputs, over quarters more
  than eight before its sample end. When either moved by more than 0.02pp, the history was
  revised, and G8's tolerance is widened threefold. The comparison, the widening and the size of
  the largest move are recorded in that vintage's `metadata.json`.
- **The next GDP comprehensive revision.** Rebasing shifts `100*log(GDPC1)` by a constant at every
  date. Tolerances apply to the gap and to growth rates, never to the level, and a base change is
  detected as a mean shift over an overlapping window and triggers a re-baseline rather than a
  failure.

One model-specific note: `ucur_break2`'s third regime runs from 2007Q1 to the present and keeps
lengthening, so `mu(3)` is estimated on a longer span at every release. That is the model
behaving as specified, and the first thing to look at if its gap starts to diverge from `uc_2m`'s.

## Runtime

**A model with no measured runtime does not go on the schedule.** Measured on the release machine
during the `v2026Q2` run, at the settings in `estimates/preset.m` and so with the marginal
likelihood off:

| model | minutes |
|---|---|
| `ucsv_sw07` | 0.6 |
| `ucur_break2` | 0.7 |
| `ar_trend_bound` | 0.8 |
| `uc_2m` | 2.9 |
| `biuc_lrexp` | 35.4 |

About 41 minutes in series and 37 with two workers, so a quarterly run is not constrained by
time. `biuc_lrexp` is almost all of it: its chain is 400,000 sweeps because shorter ones leave an
effective sample below what G7 requires. All five are listed as measured in `model_lists`, which
is what lets a scheduled run proceed without `AllowUnmeasured`.

A model whose settings change needs re-measuring, because the figure that opened the schedule was
taken at the old ones.

## If a release slips

The previous vintage stays current and correctly labeled — every published file carries its
vintage. A slipped release does not become a skipped one: the trigger checks again every Monday.

**A release the guardrails refuse is not retried automatically**, since that would re-run forty
minutes of estimation every week. The trigger leaves `build\release_failed_<vintage>.txt` naming the
staged output to inspect, and does not try that vintage again until the file is deleted.

**The freshness watchdog notices a trigger that has not fired.** Every Monday it compares FRED
with the published vintage, and when the data have been ahead of the estimates at two consecutive
checks it opens an issue. The usual causes are a refused release and the release machine being
off.

There is no cloud fallback and the cloud never estimates; deleting both workflows changes nothing
that is published.

## Release history

| Vintage | Released | Estimates through | Notes |
|---|---|---|---|
| `v2026Q2` | 2026-09-12 | 2026Q2 | First release. Out of cycle: 2026Q2 was due 1 September. `biuc_lrexp` ends 2026Q1, where `PTR` ends. |
