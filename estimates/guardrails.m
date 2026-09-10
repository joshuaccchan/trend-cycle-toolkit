% guardrails - every check that must pass before a release is allowed to promote.
%
%   report = guardrails(results, previous, data, revs)
%   report = guardrails(results, previous, data, revs, 'Vintage', '2026Q4', ...
%                       'SeasonalRevision', true)
%
% Takes the four things a release has to be judged against - the results from
% run_estimates.m, the previous published vintage from load_previous_vintage.m, the
% aligned data from uc.data, and the revision decomposition from revisions.m - and
% returns one report struct. All four are required and positional, because a check
% that quietly skips for want of an argument is worse than no check.
%
%   report.pass       logical. True only if every check below is green, and the one
%                     thing publish.m consults before it promotes anything.
%   report.nfail      how many checks failed.
%   report.checks     a table, one row per check: id (G1-G10), model, statistic,
%                     tolerance, margin and status, where status is pass, fail or
%                     n/a with a reason. This is what gets written to the staging
%                     path and what a person reads.
%   report.vintage    the vintage that was checked.
%   report.seasonal   the G9 widening: whether it was applied, and the factor the
%                     G8 tolerance was widened by when it was.
%
% NAME-VALUE OPTIONS
%   'Vintage'           'YYYYQq', recorded in the report and in metadata.json
%                       G9 appends.
%   'SeasonalRevision'  widen the G8 tolerance for the February CPI seasonal-factor
%                       re-estimation. See G9.
%
% publish.m promotes the staging tree only when report.pass is true; run_release.m
% prints the report either way and writes it to the staging path even on failure, so
% a refused release leaves behind the evidence for why.
%
% This is the file the whole design rests on. matlab -batch exits 0 on a NaN
% posterior. A fetch that returned an HTML error page with a 200 status, a sampler
% stuck against a bound, a series that quietly lost its last four quarters - none of
% them raise, and every one of them produces a file that looks like a release. The
% only thing standing between that and a published wrong number is an explicit
% refusal, in one place, that a person reads.
%
% THE CHECKS
%
% G1  Seeding. Every model ran under rng(seed,'threefry') with the seed from
%     preset.m, the seed is recorded in the results struct, and no clock-seeded call
%     survives anywhere in the path that was executed.
%
% G2  The PTRCPI rebuild, checked against public material only. PTRCPI is not a
%     series anyone publishes: build_ptrcpi assembles it from PTR out of the FRB/US
%     package, the SPF median CPI10, and a flat backfill at the head. That assembly
%     is where a silent FRB/US layout change shows up first, because HISTDATA.TXT
%     is 366 quoted columns parsed by name and the Board reorganizes it
%     periodically. Three assertions, each on material the release fetches anyway:
%
%       - PTR is present in the fetched package, and its last OBS is not in the
%         future. The package also ships LONGBASE.TXT, whose projection runs to
%         2176Q2; reading that column instead would publish a projection as
%         history, and a date in the future is how it announces itself.
%       - The splice at 2006Q1, where the series stops reading PTR and starts
%         reading the SPF median CPI10, is continuous across the join to within the
%         tolerance below. A column shift on either side opens a step there.
%       - The flat backfill covers 1960Q1 through 1967Q4 - 32 quarters - and holds
%         PTR's own first value, 1.6827, at every one of them. A backfill that has
%         moved off that value, or that is no longer flat, means PTR's first
%         observation is not where the rebuild believes it is.
%
%       check                  tolerance
%       ---------------------  -----------------------------------
%       PTR present            exact
%       last OBS not future    exact, against the release vintage
%       2006Q1 splice          TBD (phase 2)
%       1960Q1-1967Q4 flat     exact, at 1.6827
%
%     The splice tolerance is TBD because it is read off the first assembly in
%     phase 2 and then held fixed. A tolerance set afterwards, once a run has
%     failed against it, is not a tolerance.
%
%     WHAT THESE DO AND DO NOT CATCH. There is no archived copy of PTRCPI to
%     regress against, so these are structural checks rather than a value-by-value
%     comparison: a fault that shifted every value by the same small amount would
%     pass all three. What they do catch is a column shift, a projection read as
%     history, and a broken splice. They need only public sources, so any reader
%     can run them. Hard failure, never a warning.
%
% G3  Sample extension. The new sample extends the previous one: same start date,
%     same quarters in the overlap, date axis aligned, no gaps, and an end date that
%     is the last complete quarter and not one beyond it. The parts that read the
%     previous vintage do not run on the first release - see THE FIRST RELEASE
%     below - and the parts that read only the new data always do.
%
% G4  No NaN or Inf, in any stored chain, any posterior summary, or any published
%     column. Checked on the draws, not only on the summaries, because a handful of
%     bad draws can average into a plausible-looking mean.
%
% G5  Bounded models inside their bounds, on every draw. ar_trend_bound is bounded
%     by construction and is the one model of the five whose name says so; whether
%     any other carries a bound of its own is read from its published driver in
%     phase 1, along with the values. Bounds are read from preset.m, the same struct
%     the sampler was given, so the check and the model cannot drift apart. A chain
%     pinned against a bound for a long run is reported even when it is formally
%     inside it.
%
% G6  Acceptance rates in band, against the reference run. A drifted acceptance rate
%     is the earliest sign that a proposal has stopped matching the posterior it is
%     proposing into, which is why this check exists at all. The targets are
%     measured in phase 1, one row per Metropolis-Hastings block in the five models,
%     each recorded with the run it came from: the published driver, the data its
%     own package ships, and the date. preset.m's rule holds here too, so a rate
%     with nothing behind it is not a measured rate and does not belong in this
%     table.
%
%       model            block  target rate  band  from (phase 1 run)
%       ---------------  -----  -----------  ----  ------------------
%       TBD (phase 4)    TBD    TBD          TBD   TBD (phase 1)
%
%     The blocks cannot be listed before the models are extracted in phase 4, and
%     the rates cannot be filled before phase 1 runs the drivers, so the table
%     carries neither and this check has nothing to compare against until both have
%     landed. It reports that rather than passing. The phase 1 runs are the same
%     the one-off comparison against the published driver performs, so a rate
%     recorded here is one a reader can reproduce from the published package.
%
% G7  Convergence and precision. Inefficiency factors, MCSE and Geweke Z are computed
%     through uc.diag for every published parameter, written to diagnostics.csv, and
%     asserted: an effective sample too small to support the published credible band
%     blocks the release rather than appearing in a footnote.
%
% G8  Revision tolerance, anchored to the MCSE rather than to a bare number. For any
%     date more than eight quarters before the sample end, compare the new estimate
%     with the previous vintage:
%       flag  if the move exceeds max(0.20pp, 3 x MCSE)
%       fail  if the move exceeds 1.0pp, pending a human
%     Three times the MCSE is what distinguishes a real revision from the sampler's
%     own noise, and it is why G7 has to run first. The eight-quarter window exists
%     because the smoothed estimate near the sample end moves every quarter from
%     sample extension alone - which is a revision component, not an error, and
%     revisions.m is what subtracts it. That is why the sample-extension chain lands
%     in phase 5 with the guardrails and not in phase 7 with the rest of the
%     decomposition: without it, this check flags the expected every quarter. There
%     is no previous vintage on the first release and this check does not run then.
%
% G9  February. BLS re-estimates CPI seasonal factors every February, which shifts
%     the whole seasonally adjusted history and fires G8 across the board. That is
%     expected, and expected things get a code path rather than a prose note:
%     'SeasonalRevision' widens the G8 tolerance, records the widening and the
%     realized shift in the report, and records it in the vintage's metadata.json
%     automatically. Gated on the run month, and never silent.
%
% G10 Base changes. A GDP comprehensive revision shifts 100*log(GDPC1) by a constant
%     at every date. Applied to the level, G3 and G8 would both fail catastrophically
%     for the gap and for trend growth, and the failure would mean nothing. So
%     tolerances apply to the gap and to growth rates, never to the log level; a base
%     change is detected as a mean shift over an overlapping window, and the response
%     is to re-baseline and record it in the vintage's metadata.json, not to refuse.
%
% THE FIRST RELEASE. G3 and G8 read the previous vintage, and the first release has
% none: the archive under estimates/vintages/ begins with it, for the reason given
% in that folder's README. On that one run load_previous_vintage returns empty, and
% those two checks are written into report.checks with status 'n/a' and the reason,
% never with status pass - a check that could not run has not passed, and a reader
% of the first vintage's report is entitled to see which checks stood behind it.
% report.pass is decided on the checks that did run. From the second release onward
% there is no special case, and an empty previous vintage is an error.
%
% ON FAILURE. Nothing is promoted, the previous release stays exactly where it is,
% and the report names the check, the model, the date and the margin by which it
% failed. Publishing a stale quarter is recoverable. Publishing a wrong number is
% not.

function report = guardrails(results, previous, data, revs, varargin)       %#ok<STOUT,INUSD>

error('uc:estimates:guardrails:notImplemented', ...
    ['guardrails is not implemented yet (phase 5). The checks it will run are ' ...
     'enumerated G1-G10 in the header. G2 needs the PTRCPI rebuild from phase 2, ' ...
     'and G6 needs the blocks the phase 4 extraction names and the acceptance ' ...
     'rates the phase 1 runs measure.']);
