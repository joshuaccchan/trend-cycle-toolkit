# Release calendar

The series in `estimates/current/` are re-estimated four times a year and frozen as a vintage
each time. Nothing is in place yet: the pipeline arrives in phase 5 and the first release below
is contingent on it.

## The dates

Releases go out on the **1st of March, June, September and December**, covering the quarter that
ended two months earlier.

| Release | Estimates through | Vintage tag |
|---|---|---|
| 2026-12-01 | 2026Q3 | `v2026Q3` |
| 2027-03-01 | 2026Q4 | `v2026Q4` |
| 2027-06-01 | 2027Q1 | `v2027Q1` |
| 2027-09-01 | 2027Q2 | `v2027Q2` |

**Why the 1st and not earlier.** BEA publishes three estimates of each quarter's real GDP about a
month apart. On the 20th of the month only the *advance* estimate exists; the second lands in the
last week. Releasing before then would build every gap and every trend-growth path on a number
BEA revises a week later. GDP is the binding input and the only reason for the date — CPI is
final about six weeks ahead, and the SPF median CPI10 arrives mid-February, May, August and
November.

The FRB/US package is the one input a release does **not** wait for. `PTRCPI` uses `PTR` only
before 2006Q1 and the SPF median after, so a stale package affects frozen history only. It is
still fetched and validated every run, because the Board occasionally revises that history and
reorganizes `HISTDATA.TXT`'s 366-column layout.

Agency release dates are deliberately not tabulated here — check the BLS, BEA and Philadelphia
Fed calendars in the week before a release. A plausible-looking date invented here would be worse
than none.

## What a release checks before it publishes

- **The reference quarter must match.** FRED returns the running quarter as a present row with an
  empty value. That row is dropped, and the run then asserts the last complete quarter is the one
  this calendar names. A mismatch stops the release rather than publishing a quarter short.
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

Two breakages are scheduled rather than accidental:

- **February, every year.** BLS re-estimates five years of CPI seasonal factors, which moves the
  seasonally adjusted history itself. The scale is not small: recomputing a 2013-vintage inflation
  series from today's `CPIAUCSL` gives differences under 0.011pp before 2000 but up to 0.84pp in
  2010-2011. The 1 March release therefore runs with `'SeasonalRevision', true`, which widens the
  tolerance and records the widening in that vintage's `metadata.json`.
- **The next GDP comprehensive revision.** Rebasing shifts `100*log(GDPC1)` by a constant at every
  date. Tolerances apply to the gap and to growth rates, never to the level, and a base change is
  detected as a mean shift over an overlapping window and triggers a re-baseline rather than a
  failure.

One model-specific note: `ucur_break2`'s third regime runs from 2007Q1 to the present and keeps
lengthening, so `mu(3)` is estimated on a longer span at every release. That is the model
behaving as specified, and the first thing to look at if its gap starts to diverge from `uc_2m`'s.

## Runtime

None of the five models has a measured runtime. **A model with no measured runtime does not go on
the schedule**, which today means none of them. Phase 1 times each one as this repository
implements it, at the settings in `estimates/preset.m` and so with the marginal likelihood off,
and records the figures here.

## If a release slips

The previous vintage stays current and correctly labeled — every published file carries its
vintage — and the table above is amended with the new date. A slipped release does not become a
skipped one. There is no cloud fallback and the cloud never estimates; the whole system needs no
cloud at all, and deleting both workflows changes nothing that is published.

## Release history

None yet. The first entry will be `v2026Q3`.
