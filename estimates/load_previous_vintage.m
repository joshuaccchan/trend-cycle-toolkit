% load_previous_vintage - read the last published release back off disk.
%
%   previous = load_previous_vintage(root, vintage)
%
% Returns the most recent frozen release under estimates/vintages/ that is
% strictly older than the vintage being produced: its published series, its
% diagnostics and the metadata that came with them. guardrails.m checks the
% candidate release against it (G3 sample extension, G8 revision tolerance) and
% revisions.m re-runs its sample on the new data, so from the second release
% onward neither of those can be done without it. run_release.m loads it once, at
% step 6, and passes it to both, rather than each of them reading the same folder
% for itself.
%
% ARGUMENTS
%   root     the repository root. Passed in rather than computed here, so that
%            a test can point this at a fixture tree of its own.
%   vintage  'YYYYQq', the vintage being produced. What comes back is the newest
%            archived vintage strictly below it, which is the previous release
%            even when a quarter was skipped, or when an old vintage is being
%            re-run years later to reproduce it.
%
% RETURNS a struct with these fields, which are the names guardrails.m and
% revisions.m read, or an empty struct on the first release - see THE FIRST
% RELEASE HAS NO PREDECESSOR below:
%
%   vintage      'YYYYQq' of the folder that was read
%   path         the folder it was read from
%   series       one field per published series - trend_inflation, output_gap,
%                trend_growth - each the tidy table of date, model, measure and
%                value that current/ ships
%   diagnostics  the diagnostics table: inefficiency factor, MCSE and Geweke Z
%                per parameter, which is what G8 anchors its tolerance to
%   metadata     metadata.json decoded, including the seed and sampler settings
%                each model ran under - the settings revisions.m holds fixed
%                across its chains, and the reason a revision can be attributed
%                to anything at all
%
% IT READS THE CSVs, ALWAYS. An archived vintage holds the tidy CSVs,
% diagnostics.csv and metadata.json that publish.m wrote, and beside them
% trend_cycle_estimates.xlsx. This function reads the
% CSVs and the JSON, on every platform and in every mode, and never the
% workbook. The CSVs are what was published and the workbook is derived from
% them, so a comparison made against the workbook would be a comparison against
% a copy. The practical half of the same point: addressing a workbook by cell
% range needs Excel, which a GitHub-hosted runner does not have, and a cloud
% backup run that could not load the previous vintage could not be compared
% against anything - which is exactly the run where an unchecked number is most
% likely to reach a pull request.
%
% THE FIRST RELEASE HAS NO PREDECESSOR, and the two cases are told apart rather
% than merged. estimates/vintages/ begins at the first release this pipeline
% produces, so on that one run there is nothing below the vintage being made and
% nothing to compare it with:
%
%   the archive is empty                    return an empty struct. This is the
%                                           first release. guardrails.m records
%                                           G3 and G8 as n/a and names the
%                                           reason; it does not mark them pass
%   the archive holds vintages, but none    error, naming the folder searched and
%   below the vintage being produced        the vintage searched below
%
% The second case is what a renamed or half-restored archive looks like, and
% returning quietly from it would let a release publish numbers that no guardrail
% had compared against anything. The first case cannot be told apart from an
% archive deleted wholesale, and two things make that acceptable rather than a
% hole: the archive is tracked, so a wholesale deletion shows up in the diff of
% the commit that carries the release, and a run that took the first-release path
% says so in a published report through G3 and G8 rather than passing silently.
%
% See also: estimates/vintages/README.md, estimates/guardrails.m,
% estimates/revisions.m, run_release.m.

function previous = load_previous_vintage(root, vintage)                    %#ok<STOUT,INUSD>

error('uc:estimates:load_previous_vintage:notImplemented', ...
    ['load_previous_vintage is not implemented yet (phase 5). It reads ' ...
     'estimates/vintages/, which is empty until the first release writes the ' ...
     'first entry of the archive.']);
