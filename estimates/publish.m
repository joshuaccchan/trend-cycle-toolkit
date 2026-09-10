% publish - summarize a passing run, write the staging tree, promote it.
%
%   files = publish(results, report, revs, manifest, stagedir, 'Vintage', v)
%   files = publish(results, report, revs, manifest, stagedir, 'Vintage', v, ...
%                   'Promote', true)
%
% The five positional arguments are everything a release consists of: the estimation
% output from run_estimates.m, the guardrail report from guardrails.m, the revision
% table from revisions.m, the source-vintage record from uc.data.vintage_stamp, and
% the staging directory run_release.m created for this run. All five are required.
%
% NAME-VALUE OPTIONS
%   'Vintage'  'YYYYQq', required. It names the frozen folder under vintages/ and it
%              is stamped into metadata.json. It is passed in, never parsed back
%              out of the staging path, because a vintage read off a directory name
%              is a vintage that can be renamed.
%   'Promote'  logical, default false. False writes the staging tree and stops, which
%              is what step 8 of the release does; true copies it into the tracked
%              tree, which is what step 9 does once the guardrails are green.
%   'Mode'     'local' (default) or 'cloud-backup', from run_release.m. It changes
%              nothing about which files are written and one thing about what they
%              record: under 'cloud-backup', metadata.json states that the run came
%              off a hosted runner and is not byte-identical to a local one, so a
%              reader of the archive can tell which vintages were produced on the
%              release machine and which were not.
%
% Returns the list of files written, in the order they were written, which
% tools/run_update.ps1 prints and then commits. Nothing else in the pipeline writes
% into current/, vintages/, revisions/ or figures/ - revisions.m computes its table
% and hands it back rather than writing it, so that a release refused at step 7
% cannot have left a revision file in the tracked tree at step 6.
%
% NAME CLASH, DELIBERATE. MATLAB ships a built-in publish (code-to-HTML). This file
% shadows it whenever estimates/ is on the path, which is one of the reasons setup.m
% does not put estimates/ on the path at all; run_release.m adds it for the duration
% of one release run and removes it again. If you need the built-in in a session
% where this one is visible, qualify it or step out of the folder.
%
% THE GATE. publish refuses to promote unless report.pass is true, whatever
% 'Promote' says: the option asks, the report decides. It will still write the
% staging tree with 'Promote', false, which is how a failed release is inspected:
% the numbers are all there, they are simply not where a reader can download them.
%
% WHAT IT WILL WRITE
%
% current/  - the release a reader downloads, overwritten each quarter:
%   trend_inflation.csv        tidy: date, model, measure, value with
%                              measure in {mean, p05, p16, p84, p95, mcse}, one
%                              block each for ucsv_sw07, ar_trend_bound and
%                              biuc_lrexp
%   output_gap.csv             same shape, for uc_2m and ucur_break2
%   trend_growth.csv           same shape, for uc_2m alone - the same draws the gap
%                              comes from, annualized
%   trend_inflation_wide.csv   date down the first column and one model column
%                              beside it, ragged where the models start at
%                              different dates
%   diagnostics.csv            inefficiency factor, MCSE and Geweke Z per parameter
%   trend_cycle_estimates.xlsx a workbook holding the same three series
%   metadata.json              vintage, run time UTC, git SHA, per-series URL and
%                              fetch time and SHA-256, seed and settings per model
%                              including compute_ml, MATLAB and toolbox versions,
%                              elapsed time per model
%
% vintages/YYYYQq/ - a frozen copy of the above, written once and never touched
%                    again. This is the real-time archive; it is the only reason a
%                    revision can be measured at all.
%
% revisions/YYYYQq.csv - the table revisions.m computed, written once per release
%                    and never rewritten: the decomposition of a past quarter's
%                    revision does not change when a later quarter is published.
%                    Not written at all for the first release, which has no
%                    predecessor to be revised against and would otherwise get a
%                    file of zeros.
%
% figures/current/ and figures/vintages/YYYYQq/ - PNG and PDF straight out of
%   exportgraphics. Figures and PDFs are committed on purpose: published figures are
%   part of this repository's product, and joshuachan.org hot-links them.
%
% THE WORKBOOK. trend_cycle_estimates.xlsx is for readers who want one file they
% can open rather than three CSVs: a title in A1 naming the series and the vintage,
% one header row, quarter-start dates down column A, and one model to a column
% beside them. The columns are ragged because the models start at different dates,
% and the offsets are DERIVED from each model's configured sample start, never
% typed. A typed offset is how a column silently shifts by one quarter.
%
% The CSVs are what is published. The workbook is derived from them and is a
% convenience, so anything that needs to be exact should read the CSVs.
%
% ONE JSON, ONE SOURCE OF TRUTH. metadata.json is what the website reads to write
% "Estimates through YYYYQq - last updated - next update", what freshness.yml
% compares against to decide whether a release is late, and what a reader needs to
% reproduce the run. It is written from the results struct, not assembled by hand.
%
% Vintage tagging and the GitHub release are outside this function, in
% tools/cut_release.ps1, because they are git operations rather than MATLAB ones.

function files = publish(results, report, revs, manifest, stagedir, varargin)  %#ok<STOUT,INUSD>

error('uc:estimates:publish:notImplemented', ...
    ['publish is not implemented yet (phase 5). The output schemas it will write ' ...
     'are described in the header and in estimates/current/README.md.']);
