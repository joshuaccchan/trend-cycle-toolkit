% run_release - produce one quarterly release of the published estimates.
%
%   run_release                          % the scheduled call, via matlab -batch
%   run_release('Vintage','2026Q3')      % re-run a named vintage
%   run_release('DryRun',true)           % fetch, estimate, check - promote nothing
%   run_release('Models',{'ar_trend_bound'})
%   run_release('Mode','cloud-backup')   % the workflow_dispatch backup run
%
% STATUS - READ THIS FIRST. This file is a documented skeleton. The sequence
% below is the real one, but every stage is a call to a function that has not
% been written yet, each marked with the phase of the plan that delivers it. A
% preflight check runs before anything else, prints exactly which stages are
% missing, and then errors. So running this today fetches nothing, writes
% nothing and promotes nothing: it tells you which phase has to land first. It
% cannot half-run, which matters more here than anywhere else in the repository,
% because a release that stops halfway would leave the published estimates and
% the source vintages that produced them describing different quarters.
%
% WHAT A RELEASE IS
%
% Four times a year the trend inflation, output gap and trend output growth
% series are re-estimated from scratch on the current data vintage - not
% extended, re-estimated, because these are two-sided smoothed estimates and
% every historical value moves when the sample grows (RELEASE_CALENDAR.md explains the
% policy and why it is the honest one). The run produces a new frozen vintage
% under estimates/vintages/, replaces estimates/current/, and leaves a revision
% decomposition saying how much of the change came from data revision, how much
% from sample extension and how much is Monte Carlo noise.
%
% THE SEQUENCE
%
%   0. preflight        check every stage exists; error listing what does not
%   1. fetch            FRED, SPF and FRB/US, each validating its own payload
%   2. archive + hash   write the source vintage and its SHA-256 to staging
%   3. validate         alignment, tail completeness, the PTRCPI rebuild checks
%   4. unit tests       the local suite, before a single draw is taken
%   5. estimate         one call; the parfor over models lives inside it
%   6. revisions        load the previous vintage, then the sample-extension
%                       chain the tolerance needs
%   7. guardrails       every check that stands between a bad fetch and a bad series
%   8. stage            write CSV and diagnostics under build/staging/<vintage>
%   9. promote          only on all-green; then figures, workbook, metadata.json
%
% WHY PROMOTION IS GATED, AND STAGED
%
% matlab -batch exits 0 whenever the script finishes without throwing. A chain
% that filled with NaN, a fetch that returned an HTML error page with a 200
% status, a sampler that wandered outside its bounds - none of those throw, and
% all of them exit 0. The scheduled task would then commit and push the result.
% The only thing standing between that and a published bad series is
% guardrails.m, so this driver is built around one rule with no exceptions:
% nothing enters the tracked tree until every guardrail is green.
%
% Everything a run produces is therefore written first to build/staging/<vintage>
% and copied into estimates/ afterwards. build/ is git-ignored, so a failed run
% leaves the working tree exactly as it found it while keeping the fetched
% inputs and the failed output on disk for diagnosis. The source vintages are
% staged and promoted with the estimates, never committed on arrival, so
% estimates/sources/ and estimates/current/ can never describe different data.
%
% Failure is an error(), never a warning, so that matlab -batch exits nonzero
% and tools/run_update.ps1 stops before its git push.
%
% THE CALENDAR
%
% Releases run on 1 March, 1 June, 1 September and 1 December (RELEASE_CALENDAR.md
% carries the dates four quarters out). The month matters: the quarter's third
% CPI month is posted mid-month-prior, SPF CPI10 is weeks old, the FRB/US package
% has been refreshed, and - the binding constraint - the BEA second estimate of
% GDP lands in the last week of the preceding month. An earlier run in the month
% would build the output gap on the advance estimate and revise it out at the
% next release for no reason but impatience.
%
% One consequence of the calendar is handled here, not left to a note in
% a document: BLS re-estimates CPI seasonal factors every February, which shifts
% the whole seasonally adjusted history and therefore moves trend inflation at
% dates far behind the sample end. The March release, and only the March
% release, widens the revision tolerance for that reason and records it. See the
% SeasonalRevision option below.
%
% THE FIVE MODELS, AND THE THREE SERIES THEY PRODUCE
%
%   model            series it produces            input series
%   ---------------  ---------------------------   -------------------
%   ucsv_sw07        trend inflation               CPIAUCSL
%   ar_trend_bound   trend inflation               CPIAUCSL
%   biuc_lrexp       trend inflation               CPIAUCSL, PTRCPI
%   uc_2m            output gap and trend growth   GDPC1
%   ucur_break2      output gap                    GDPC1
%
% uc_2m is the only model that produces two of the three published series, and
% both come out of one set of draws, not two runs that would have
% to agree with each other. estimates/README.md carries the method source for
% each model; preset.m carries its settings and the published file each setting
% was read from.
%
% RUNTIME, AND WHY NOTHING IS SCHEDULED YET
%
% Two of the five have a runtime figure at all, and both figures are indicative.
% They were taken on the release machine from working copies, not from the
% published drivers, and on data those packages do not ship, so they give the
% order of magnitude and nothing finer:
%
%   core model         product                       indicative runtime
%   ---------------------------------------------------------------------------
%   ar_trend_bound     trend inflation (bounded)       2.6 min
%   biuc_lrexp         trend inflation, LR expect.     5.7 min
%
% The figures sit against the models and not against the published drivers,
% because a runtime measured on a working copy is not a property of the file in
% the package. preset.m names the published driver behind each model.
%
% ucsv_sw07, uc_2m and ucur_break2 have no figure whatsoever. Both output-gap
% drivers ship at 100,000 draws after a 10,000 burn-in with a 50,000-replication
% importance step for the marginal likelihood; preset.m turns that step off for
% the quarterly job, so what matters is the runtime without it, and that has not
% been measured either.
%
% Phase 1 supplies every figure, by running each published driver as distributed
% on the data its own package ships, downloaded from https://joshuachan.org/code.html
% at the time of the run. Those figures are reproducible by anyone, because both
% the code and the data are public.
%
% Until then no model has a runtime measured on the code it was taken from, and a
% model in that state is not put on an unattended quarterly schedule - a job that
% overruns is how a release goes missing. So a run today has to pass
% 'AllowUnmeasured', whichever models it asks for. The gate lifts model by model
% as phase 1 times them.
%
% SEEDS
%
% The published drivers re-seed from the wall clock, which makes a published number
% unreproducible even by the person who published it. Every model here is seeded
% with rng(seed,'threefry') from preset.m, inside the parfor body in
% run_estimates.m - inside the body, so that the seed a model gets does not
% depend on how many workers the pool happened to have or the order the
% scheduler assigned them - and the seed is recorded in metadata.json beside the
% estimates it produced.
%
% OPTIONS
%
%   'Vintage'           'YYYYQq'. Default: the calendar quarter that ended
%                       before today, which is the quarter the release is due
%                       for. Guardrail G3 then checks that the data actually
%                       reaches it, so a quarter the agency has not published
%                       yet fails a named check instead of quietly producing a
%                       release one quarter behind the one that was due.
%   'Models'            cellstr of uc.models function names, or one
%                       comma-separated string, which is the only shape a
%                       workflow_dispatch input can carry. Empty means the
%                       default: the five models above, which is the whole
%                       product. A group label such as 'scheduled' is not a model
%                       name and is not accepted - the default already is every
%                       model the repository publishes.
%   'AllowUnmeasured'   run a model whose runtime has not been measured on the
%                       published driver (default false). That is all five today,
%                       so nothing runs without it until phase 1 lands.
%   'RunTests'          run the local unit suite first (default true). The
%                       the one-off comparison against the published code is not part of this: it
%                       one downloads a published package from
%                       https://joshuachan.org/code.html and runs the original driver
%                       against the new implementation, so they need the network
%                       and are run by hand, off the release path.
%   'SeasonalRevision'  widen the revision tolerance for the February CPI
%                       seasonal-factor re-estimation. Default: decided from the
%                       run month, true in March.
%   'DryRun'            do everything except promote (default false).
%   'Mode'              'local' (default) or 'cloud-backup'. No workflow in this
%                       repository invokes the backup mode; it exists so that a
%                       run on a hosted runner is possible without editing this
%                       file. It estimates the models serially, because a hosted
%                       runner has two cores and no pool worth its setup cost,
%                       and metadata.json records that the numbers came off a
%                       runner and are not byte-identical to a local run. It
%                       changes nothing else: the same guardrails gate the same
%                       promotion.
%
% Those seven names are the whole option interface. validatestring matches
% case-insensitively, so a caller that types 'vintage' or 'dryRun' still
% resolves, but nothing in this repository relies on that.
% The seven functions under estimates/ that this driver calls, directly or
% through run_estimates, are documented as one interface, argument for argument,
% in estimates/README.md.
%
% See also: setup.m, estimates/README.md, estimates/guardrails.m,
% estimates/publish.m, RELEASE_CALENDAR.md.

function run_release(varargin)

opt  = parse_options(varargin{:});
root = fileparts(mfilename('fullpath'));

% ---- 0. preflight --------------------------------------------------------
% Before a single byte is fetched. Everything this run will call is resolved
% from disk, and if anything is missing the run stops here having done nothing.
% The schedule-safety check follows it, so that a caller
% who is missing a whole phase is told that first: a runtime that has not been
% measured is not the interesting problem when the model file it would time is
% not there either.
preflight(root, opt);
check_schedulable(opt);

run(fullfile(root, 'setup.m'));

% estimates/ goes on the path for the duration of this run only. It is kept off
% the permanent path because the names in it are generic and one of them,
% publish.m, shadows a MATLAB built-in whenever the folder is visible (see
% setup.m); parfor propagates the client path to the workers, so this reaches
% them too.
addpath(fullfile(root, 'estimates'));
pathguard = onCleanup(@() rmpath(fullfile(root, 'estimates')));

t_release = tic;

% ---- 1. fetch ------------------------------------------------------------
vintage = opt.Vintage;
if isempty(vintage)
    vintage = default_vintage();
end
fprintf('run_release: vintage %s, %d model(s), %s mode\n', ...
    vintage, numel(opt.Models), opt.Mode);

% Each fetcher validates its own payload and errors on failure. Three
% traps are known and each has cost someone a bad number before: FRED returns
% the running quarter as a present row with an empty value, which becomes NaN
% under 400*log differencing; the Philadelphia Fed answers 200 with an HTML
% error page for an unknown media path, so magic bytes are checked and never
% the status code; and the FRB/US package contains LONGBASE.TXT as well as
% HISTDATA.TXT, the former carrying a projection to 2176 that would be
% published as history. sources.md is the ledger of what is fetched from where.
%
% The second argument to fetch_fred is FRED's own fq= value, spelled exactly as
% the endpoint takes it, and it is required: no fetcher in this repository has a
% default frequency, because a series fetched monthly and then differenced as if
% it were quarterly is a mistake that nothing downstream can see.
% core/+uc/+data/README.md records the endpoint it becomes, fq=Quarterly&fam=avg.
%
% Four series are fetched, because the five models read four inputs between
% them: CPIAUCSL for the three trend inflation models, GDPC1 for the two
% output-gap models, and PTR with the SPF median CPI10 for the derived PTRCPI
% that biuc_lrexp adds to its inflation data. Nothing else is fetched. A series
% no scheduled model reads would be archived every quarter, hashed, and never
% used, which is a maintenance cost with no product behind it.
src          = struct();
src.CPIAUCSL = uc.data.fetch_fred('CPIAUCSL', 'Quarterly');   % TODO (phase 2)
src.GDPC1    = uc.data.fetch_fred('GDPC1',    'Quarterly');   % TODO (phase 2)
src.SPFCPI10 = uc.data.fetch_spf();                           % TODO (phase 2)
src.PTR      = uc.data.fetch_frbus_ptr();                     % TODO (phase 2)

% PTRCPI is not a series anyone publishes - it is PTR plus 0.4 before 2006Q1 and
% the SPF median CPI10 after, backfilled at the head. It is rebuilt every
% release and is not carried forward, and step 3 checks the rebuild against the
% public sources it was built from.
src.PTRCPI   = uc.data.build_ptrcpi(src.PTR, src.SPFCPI10);   % TODO (phase 2)

% ---- 2. archive and hash the source vintage ------------------------------
stagedir = fullfile(root, 'build', 'staging', vintage);
if ~isfolder(stagedir)
    mkdir(stagedir);
end
manifest = uc.data.vintage_stamp(src, stagedir, vintage);     % TODO (phase 2)

% ---- 3. validate ---------------------------------------------------------
% Structural checks on the data, before any estimation: drop the incomplete
% running quarter, put everything on a common quarterly date axis, and check the
% rebuilt PTRCPI three ways - PTR present with a last OBS that is not in the
% future, a continuous splice at 2006Q1, and a flat backfill over 1960Q1-1967Q4
% at PTR's own first value of 1.6827. That last group is the canary for a FRB/US
% layout change - HISTDATA.TXT is 366 quoted columns parsed by name and the Board
% reorganizes it - and it is a hard failure, not a warning. G2 in
% estimates/guardrails.m states each assertion and its tolerance.
data = uc.data.align_by_date(uc.data.drop_incomplete_tail(src));  % TODO (phase 2)

% ---- 4. unit tests, locally ----------------------------------------------
% The suite runs here and not only in CI, because the published numbers are
% produced on this machine and never in the cloud. It errors on any failure.
if opt.RunTests
    run(fullfile(root, 'tests', 'unit', 'run_unit_tests.m'));      % TODO (phase 4)
end

% ---- 5. estimate ---------------------------------------------------------
% preset.m carries nsim, burnin, thin, seed, sample start and compute_ml per
% model, each published value citing the file it was read from. Two of its
% settings decide what a quarterly run costs. compute_ml is false, so neither
% output-gap model runs the 50,000-replication importance step its published
% driver ships - a data product does not need a marginal likelihood every
% quarter, and that step is the expensive part of the run. Thinning is not
% cosmetic either: both output-gap models store a whole trend path per draw at
% 100,000 draws, which is about a quarter of a gigabyte each in doubles before a
% pool holds several of them at once, so the stores are thinned inside the
% sampler, not on the way out.
%
% run_estimates also resolves configured break dates against the sample it is
% about to estimate, through estimates/resolve_break_dates.m, and hands the model
% row indices, not dates. Only ucur_break2 has breaks; its published
% driver hard-codes them as row indices that are the right quarters only for its
% own sample start.
%
% run_estimates owns the loop over models, and with it the parfor and the
% per-model seeding described under SEEDS above. It owns them because it writes
% each model's output to the staging path as that model finishes, so that a
% crash in the fifth model does not cost the first four, and that bookkeeping
% belongs beside the loop, not in this driver. 'Parallel' is false in
% cloud-backup mode and the same loop runs serially.
cfg     = preset(opt.Models);                                      % TODO (phase 5)
results = run_estimates(cfg, data, ...
              'StageDir', stagedir, ...
              'Parallel', strcmp(opt.Mode, 'local'));              % TODO (phase 5)

% ---- 6. revisions --------------------------------------------------------
% Re-running the previous sample on the new data, with the seed held fixed,
% separates the part of this quarter's revision that is data revision from the
% part that is just the sample growing. The guardrail in step 7 subtracts the
% sample-extension component before it applies its tolerance, which is why this
% chain ships with the pipeline and not with the full three-way decomposition
% later; without it the guardrail flags the whole smoothed path every quarter
% and means nothing.
%
% 'Components' is named explicitly, never left to its default, so that
% adding the data-revision and Monte Carlo chains in phase 7 cannot quietly
% triple the runtime of a release that only needs the one.
%
% The first release is the exception, and it happens once. The archive under
% estimates/vintages/ begins with it, so load_previous_vintage returns empty,
% revisions returns an empty table, no revisions/YYYYQq.csv is written, and the
% two guardrails that compare against a previous vintage are recorded as not
% applicable, not as passed. Every release after it takes the normal path,
% and an empty previous vintage is an error from then on.
previous = load_previous_vintage(root, vintage);                   % TODO (phase 5)
revs     = revisions(results, previous, data, ...
               'Components', {'sample'});                          % TODO (phase 5)

% ---- 7. guardrails -------------------------------------------------------
% Every check that runs must pass, and on the first release the two that compare
% against a previous vintage do not run and are recorded as such. Bounded models
% inside their bounds, acceptance rates in band against the reference run,
% inefficiency factors, MCSE and Geweke Z computed and asserted, the new sample
% extending the previous one, no NaN anywhere, and the revision tolerance
% anchored to max(0.20pp, 3*MCSE) with a hard stop above 1.0pp. The
% acceptance-rate targets are TBD until phase 4 names the blocks and phase 1
% measures them on the published drivers: see G6 in estimates/guardrails.m, where
% each carries the run it came from the way every published setting carries its
% citation. Tolerances
% apply to the gap and to growth rates, never to the log level of GDP: the next
% comprehensive revision will shift 100*log(GDPC1) by a constant at every date,
% and a level-based check would fail catastrophically for a rebasing that
% changes nothing economically.
report = guardrails(results, previous, data, revs, ...
             'Vintage', vintage, ...
             'SeasonalRevision', opt.SeasonalRevision);            % TODO (phase 5)

% ---- 8. stage ------------------------------------------------------------
% The tidy and wide CSVs, diagnostics.csv and the revision table, written under
% build/staging/<vintage> where git cannot see them. This call runs whether or
% not the guardrails passed, so that a refused release leaves its numbers on
% disk for someone to read; 'Promote' is the only thing that decides whether
% anything reaches the tracked tree.
publish(results, report, revs, manifest, stagedir, ...
    'Vintage', vintage, 'Promote', false, 'Mode', opt.Mode);       % TODO (phase 5)

% ---- 9. promote, then derive -------------------------------------------
if ~report.pass
    error('uc:run_release:guardrail', ...
        ['%d guardrail(s) failed for vintage %s; nothing was promoted. The ' ...
         'staged output is at %s and report.checks names each failure.'], ...
        report.nfail, vintage, stagedir);
end
if opt.DryRun
    fprintf('run_release: dry run, all guardrails green. Staged at %s\n', stagedir);
    return
end

% Figures, the workbook and metadata.json are derived after promotion, from the
% promoted CSVs, so that no published figure can ever depict numbers that were
% not themselves published. metadata.json describes the promoted vintage - run
% time, git SHA, per-series URL, fetch time and SHA-256, seeds, sampler
% settings, MATLAB and toolbox versions, runtime - and is what the freshness
% workflow and the website read.
files = publish(results, report, revs, manifest, stagedir, ...
            'Vintage', vintage, 'Promote', true, 'Mode', opt.Mode);  % TODO (phase 5)

fprintf('run_release: promoted %s in %.1f min. Files written:\n', ...
    vintage, toc(t_release)/60);
fprintf('  %s\n', files{:});
fprintf(['run_release: commit and push with tools\\run_update.ps1 - this ' ...
         'driver never touches git itself.\n']);
end


% =========================================================================
function preflight(root, opt)
% preflight - resolve every stage this run needs, and stop before doing
% anything if one is missing. Each row is {phase, what it is, path}.
%
% This is the whole reason the file can be committed as a skeleton: the
% sequence above reads as the finished design, and the run still refuses to
% start, without failing somewhere in the middle of it.
%
% Every function the sequence calls has a row, including the seven under
% estimates/, six of which exist today as documented stubs. Those rows pass,
% because the files are there; the stubs then error on their first call with the
% phase that delivers them. The check is on the file, so the rule for adding a stage
% is simple: a new call in the sequence above gets a row here in the same edit,
% or the run finds out about it halfway through.

stages = { ...
    2, 'fetch a quarterly FRED series',        'core/+uc/+data/fetch_fred.m'
    2, 'fetch SPF median CPI10',               'core/+uc/+data/fetch_spf.m'
    2, 'fetch FRB/US HISTDATA and PTR',        'core/+uc/+data/fetch_frbus_ptr.m'
    2, 'rebuild PTRCPI',                       'core/+uc/+data/build_ptrcpi.m'
    2, 'drop the incomplete running quarter',  'core/+uc/+data/drop_incomplete_tail.m'
    2, 'align series on one date axis',        'core/+uc/+data/align_by_date.m'
    2, 'stamp and hash the source vintage',    'core/+uc/+data/vintage_stamp.m'
    4, 'local unit suite',                     'tests/unit/run_unit_tests.m'
    5, 'per-model sampler settings',           'estimates/preset.m'
    5, 'resolve break dates to row indices',   'estimates/resolve_break_dates.m'
    5, 'estimate the scheduled models',        'estimates/run_estimates.m'
    5, 'load the previous published vintage',  'estimates/load_previous_vintage.m'
    5, 'sample-extension revision chain',      'estimates/revisions.m'
    5, 'guardrails',                           'estimates/guardrails.m'
    5, 'stage, promote, figures, metadata',    'estimates/publish.m'
    };

for k = 1:numel(opt.Models)
    stages(end+1, :) = {5, sprintf('model %s', opt.Models{k}), ...
        sprintf('core/+uc/+models/%s.m', opt.Models{k})};  %#ok<AGROW>
end

present = cellfun(@(p) isfile(fullfile(root, strrep(p, '/', filesep))), stages(:, 3));
if all(present)
    return
end

missing = stages(~present, :);
phases  = cell2mat(missing(:, 1));
fprintf('\nrun_release: %d of %d stages are not written yet.\n\n', ...
    size(missing, 1), size(stages, 1));
fprintf('  phase  stage                                 file\n');
fprintf('  -----  ------------------------------------  --------------------------------\n');
for k = 1:size(missing, 1)
    fprintf('  %5d  %-36s  %s\n', missing{k, 1}, missing{k, 2}, missing{k, 3});
end
fprintf('\n');

first = min(phases);
error('uc:run_release:phaseMissing', ...
    ['run_release is a documented skeleton: %d of %d stages are missing and ' ...
     'the earliest is phase %d. Land phase %d first (see the phase table in ' ...
     'README.md). Nothing was fetched, written or promoted.'], ...
    size(missing, 1), size(stages, 1), first, first);
end


% =========================================================================
function opt = parse_options(varargin)
% parse_options - name/value options, normalized into the shapes the rest of the
% driver reads. The schedule-safety rule is applied by check_schedulable, after
% preflight.

product = model_lists();

% The braces around product are what keep this a scalar struct: struct() spreads
% a bare cell array into a struct array, one element per model.
opt = struct( ...
    'Vintage',          '', ...
    'Models',           {product}, ...
    'AllowUnmeasured',  false, ...
    'RunTests',         true, ...
    'SeasonalRevision', [], ...
    'DryRun',           false, ...
    'Mode',             'local');

if mod(numel(varargin), 2) ~= 0
    error('uc:run_release:badOptions', 'Options come in name/value pairs.');
end
known = fieldnames(opt);
for k = 1:2:numel(varargin)
    name = validatestring(varargin{k}, known, 'run_release');
    opt.(name) = varargin{k+1};
end

opt.Mode = validatestring(opt.Mode, {'local', 'cloud-backup'}, 'run_release', 'Mode');

% Models has to survive arriving as a string from a workflow_dispatch input,
% which is why a comma-separated list is split and an empty one falls back to
% the default. It is a list of model names and never a group label: 'scheduled'
% is not a model, and the default already is every model the repository
% publishes.
if isstring(opt.Models) && ~isscalar(opt.Models)
    opt.Models = cellstr(opt.Models);
elseif ischar(opt.Models) || isstring(opt.Models)
    opt.Models = strtrim(strsplit(char(opt.Models), ','));
end
opt.Models = opt.Models(~cellfun(@isempty, opt.Models));
if isempty(opt.Models)
    opt.Models = product;
end

% The March release is the one that follows February's CPI seasonal-factor
% re-estimation, which moves the whole seasonally adjusted history and with it
% every trend inflation estimate far behind the sample end. Widening the
% tolerance is expected, once a year, and is recorded in metadata.json by
% guardrails.m, not explained after the fact by whoever is on duty.
if isempty(opt.SeasonalRevision)
    opt.SeasonalRevision = (month(datetime('now')) == 3);
end
end


% =========================================================================
function [product, measured] = model_lists()
% model_lists - the two lists of model names, in one place because they are two
% different statements and are read from two different functions.
%
% product   the five models that produce the three published series, and the
%           default model list, because a release estimates the whole product
%           and not a subset of it.
% measured  the models whose runtime has been measured on the published driver,
%           which is what decides whether a model may run unattended. Empty
%           today. Phase 1 fills it one model at a time, each entry carrying the
%           run behind it, so the schedule opens model by model and nobody has
%           to edit the product to open it.
%
% The two indicative figures under RUNTIME in the header were taken on working
% copies and on other data, so they are not measurements of what a schedule would
% run and no model is listed as measured on the strength of them.

product  = {'ucsv_sw07', 'ar_trend_bound', 'biuc_lrexp', 'uc_2m', 'ucur_break2'};
measured = {};
end


% =========================================================================
function check_schedulable(opt)
% check_schedulable - refuse a model whose runtime has not been measured on the
% code it was taken from, unless the caller has asked for it by name.
%
% Enforced in code, because an unattended job that overruns is how
% a release quietly goes missing.

[~, measured] = model_lists();
unmeasured    = setdiff(opt.Models, measured);
if isempty(unmeasured) || opt.AllowUnmeasured
    return
end

if isempty(measured)
    error('uc:run_release:unmeasured', ...
        ['Runtime has not been measured on the published driver for any model ' ...
         'yet, so no model is on the quarterly schedule and %s cannot run ' ...
         'unattended. Phase 1 measures them one at a time; until it has, pass ' ...
         '''AllowUnmeasured'',true for a run by hand.'], ...
        strjoin(unmeasured, ', '));
else
    error('uc:run_release:unmeasured', ...
        ['Runtime has never been measured for: %s. Only %s have a measured ' ...
         'runtime, so only those are scheduled. Measure the rest in phase 1, or ' ...
         'pass ''AllowUnmeasured'',true for a one-off run by hand.'], ...
        strjoin(unmeasured, ', '), strjoin(measured, ', '));
end
end


% =========================================================================
function v = default_vintage()
% default_vintage - the quarter a run produces when no vintage was named.
%
% The calendar quarter that ended before today: a release on 1 March 2027 is
% 2026Q4. It is read off the calendar, never off the fetched data, on
% purpose. The vintage names the quarter this run intends to produce, and
% guardrail G3 then checks that the data reaches it - so a quarter the agency
% has not published yet fails a check that says so, and does not silently
% producing a release one quarter behind the one that was due.

qend = dateshift(datetime('now'), 'start', 'quarter') - caldays(1);
v    = sprintf('%dQ%d', year(qend), ceil(month(qend)/3));
end
