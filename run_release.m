% run_release - produce one quarterly release of the published estimates.
%
%   run_release                          % the scheduled call, via matlab -batch
%   run_release('Vintage','2026Q3')      % re-run a named vintage
%   run_release('DryRun',true)           % fetch, estimate, check - promote nothing
%   run_release('Models',{'ar_trend_bound'})
%
% Four times a year the three series are re-estimated from scratch on the current
% data vintage. Re-estimated, not extended: these are two-sided smoothed estimates
% and every historical value moves when the sample grows. The run writes a new
% frozen vintage under estimates/vintages/, replaces estimates/current/, and leaves
% a revision decomposition. RELEASE_CALENDAR.md carries the policy.
%
% THE SEQUENCE
%
%   0. preflight        check every stage exists; error listing what does not
%   1. fetch            FRED and FRB/US, each validating its own payload
%   2. archive + hash   write the source vintage and its SHA-256 to staging
%   3. transform        PCE inflation, log GDP, the backfilled PTR expectation
%   4. unit tests       the local suite, before a single draw is taken
%   5. estimate         one call; the parfor over models lives inside it
%   6. revisions        load the previous vintage, then the sample-extension chain
%   7. guardrails       every check between a bad fetch and a bad series
%   8. stage            write everything under build/staging/<vintage>
%   9. promote          only on all-green
%
% PROMOTION IS GATED AND STAGED. matlab -batch exits 0 whenever the script finishes
% without throwing, and a NaN chain, an HTML error page served with a 200 status
% and a sampler outside its bounds all finish without throwing. So nothing enters
% the tracked tree until every guardrail is green, and everything is written first
% to build/staging/<vintage>, which is git-ignored. A failed run leaves the working
% tree as it found it and the fetched inputs on disk for diagnosis.
%
% OPTIONS
%   'Vintage'           'YYYYQq'. Default: the quarter that ended before today.
%                       G3 then checks the data reaches it, so a quarter the agency
%                       has not published fails a named check.
%   'Models'            cellstr of uc.models names, or one comma-separated string,
%                       which is the only shape a workflow_dispatch input carries.
%                       Empty means all five.
%   'AllowUnmeasured'   run a model whose runtime has not been measured (default
%                       false), which is all five today.
%   'RunTests'          run the local unit suite first (default true).
%   'SeasonalRevision'  widen the revision tolerance for February's CPI
%                       seasonal-factor re-estimation. Default: true in March.
%   'DryRun'            do everything except promote (default false).
%   'Mode'              'local' (default) or 'cloud-backup'. The latter estimates
%                       serially and records in metadata.json that the numbers came
%                       off a hosted runner. The same guardrails gate the same
%                       promotion.
%
% estimates/README.md documents the seven stage functions, argument for argument.

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
% Three series are fetched, because the five models read three inputs between
% them: PCE inflation for the three trend inflation models, GDPC1 for the two
% output-gap models, and FRB/US PTR, the long-run expectation biuc_lrexp adds to
% its inflation data. Nothing else is fetched. A series no scheduled model reads
% would be archived every quarter, hashed, and never used.
%
% DPCERD3Q086SBEA is the NIPA quarterly PCE chain-type price index. FRED's PCEPI
% is the same concept and begins in 1959Q1, which would cost twelve years.
src       = struct();
src.PCE   = uc.data.drop_incomplete_tail(uc.data.fetch_fred('DPCERD3Q086SBEA', 'Quarterly'));
src.GDPC1 = uc.data.drop_incomplete_tail(uc.data.fetch_fred('GDPC1'));
src.PTR   = uc.data.fetch_frbus_ptr();

% FRED publishes the quarter in progress as a present row with an empty value,
% so the two FRED series are trimmed as they arrive. PTR comes out of a zip and
% carries no such row.

% PTR begins in 1968Q1 and biuc_lrexp starts in 1960Q1, so the head is held flat
% at PTR's own first value, which is what the published package does. No wedge
% and no splice: PTR is already in PCE terms and the model is estimated on PCE
% inflation. G2 checks the backfill at step 7.
src.PTR_EXPECT = uc.data.build_ptr(src.PTR);

% ---- 2. archive and hash the source vintage ------------------------------
stagedir = fullfile(root, 'build', 'staging', vintage);
if ~isfolder(stagedir)
    mkdir(stagedir);
end
manifest = uc.data.vintage_stamp(src, stagedir, vintage);

% ---- 3. transform into what the samplers read ----------------------------
% Levels are what step 2 archived. The samplers read transforms of them, and the
% transform happens here so that what sits under estimates/sources/ stays the
% thing the source published.
%
% The three series are NOT put on a common axis here. uc.data.align_by_date
% intersects what it is given, and the backfilled PTR begins in 1960Q1 while the
% price index and GDPC1 begin in 1947 - aligning all three at once would start
% every model in 1960 and throw away thirteen years from the four that never read
% PTR.
% run_estimates aligns each model over its own inputs instead, and asserts the
% sample start preset.m records for it.
%
% PTR is checked by G2 in estimates/guardrails.m at step 7: present, with a last
% OBS that is not in the future, and a flat 32-quarter backfill over
% 1960Q1-1967Q4. That group is the canary for a FRB/US layout change -
% HISTDATA.TXT is 366 quoted columns parsed by name and the Board reorganizes it -
% and it is a hard failure, never a warning.
data      = struct();
data.infl = uc.data.annualized_log_diff(src.PCE);
data.lgdp = src.GDPC1;
data.lgdp.value = 100 * log(src.GDPC1.value);
data.ptr  = src.PTR_EXPECT;

% ---- 4. unit tests, locally ----------------------------------------------
% The suite runs here and not only in CI, because the published numbers are
% produced on this machine and never in the cloud. It errors on any failure.
if opt.RunTests
    run(fullfile(root, 'tests', 'unit', 'run_unit_tests.m'));
end

% ---- 5. estimate ---------------------------------------------------------
% preset.m carries nsim, burnin, thin, seed, sample start and compute_ml per
% model, each published value citing the file it was read from. Two of its
% settings decide what a quarterly run costs. compute_ml is false, so neither
% output-gap model runs the 50,000-replication importance step its published
% driver ships - a data product does not need a marginal likelihood every
% quarter, and that step is the expensive part of the run. Thinning matters for the
% same reason: both output-gap models store a whole trend path per draw at
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
cfg     = preset(opt.Models);
results = run_estimates(cfg, data, ...
              'StageDir', stagedir, ...
              'Parallel', strcmp(opt.Mode, 'local'));

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
% adding the data-revision and Monte Carlo chains later cannot quietly
% triple the runtime of a release that only needs the one.
%
% The first release is the exception, and it happens once. The archive under
% estimates/vintages/ begins with it, so load_previous_vintage returns empty,
% revisions returns an empty table, no revisions/YYYYQq.csv is written, and the
% two guardrails that compare against a previous vintage are recorded as not
% applicable, not as passed. Every release after it takes the normal path,
% and an empty previous vintage is an error from then on.
previous = load_previous_vintage(root, vintage);
revs     = revisions(results, previous, data, ...
               'Components', {'sample'});

% ---- 7. guardrails -------------------------------------------------------
% Every check that runs must pass, and on the first release the two that compare
% against a previous vintage do not run and are recorded as such. Bounded models
% inside their bounds, acceptance rates in band against the reference run,
% inefficiency factors and MCSE computed and asserted, the new sample
% extending the previous one, no NaN anywhere, and the revision tolerance
% anchored to max(0.20pp, 3*MCSE) with a hard stop above 1.0pp. The
% acceptance-rate targets have not been measured, so G6 reports the observed rates
% and returns n/a. Tolerances
% apply to the gap and to growth rates, never to the log level of GDP: the next
% comprehensive revision will shift 100*log(GDPC1) by a constant at every date,
% and a level-based check would fail catastrophically for a rebasing that
% changes nothing economically.
report = guardrails(results, previous, data, revs, ...
             'Vintage', vintage, ...
             'SeasonalRevision', opt.SeasonalRevision);

% ---- 8. stage ------------------------------------------------------------
% The tidy and wide CSVs, diagnostics.csv and the revision table, written under
% build/staging/<vintage> where git cannot see them. This call runs whether or
% not the guardrails passed, so that a refused release leaves its numbers on
% disk for someone to read; 'Promote' is the only thing that decides whether
% anything reaches the tracked tree.
publish(results, report, revs, manifest, stagedir, ...
    'Vintage', vintage, 'Promote', false, 'Mode', opt.Mode);

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
            'Vintage', vintage, 'Promote', true, 'Mode', opt.Mode);

fprintf('run_release: promoted %s in %.1f min. Files written:\n', ...
    vintage, toc(t_release)/60);
fprintf('  %s\n', files{:});
fprintf(['run_release: commit and push with tools\\run_update.ps1 - this ' ...
         'driver never touches git itself.\n']);
end


% =========================================================================
function preflight(root, opt)
% preflight - resolve every stage this run needs, and stop before doing
% anything if one is missing. Each row is {what it is, path}.
%
% This is the whole reason the file can be committed as a skeleton: the
% sequence above reads as the finished design, and the run still refuses to
% start, without failing somewhere in the middle of it.
%
% Every function the sequence calls has a row. The check is on the file, so the
% rule for adding a stage is simple: a new call in the sequence above gets a row
% here in the same edit, or the run finds out about it halfway through.

stages = { ...
    'fetch a quarterly FRED series',        'core/+uc/+data/fetch_fred.m'
    'fetch FRB/US HISTDATA and PTR',        'core/+uc/+data/fetch_frbus_ptr.m'
    'backfill PTR to the sample start',     'core/+uc/+data/build_ptr.m'
    'drop the incomplete running quarter',  'core/+uc/+data/drop_incomplete_tail.m'
    'align series on one date axis',        'core/+uc/+data/align_by_date.m'
    'stamp and hash the source vintage',    'core/+uc/+data/vintage_stamp.m'
    'inefficiency factors',                 'core/+uc/+diag/ineff.m'
    'Monte Carlo standard errors',          'core/+uc/+diag/mcse.m'
    'Geweke convergence diagnostic',        'core/+uc/+diag/geweke.m'
    'per-model sampler settings',           'estimates/preset.m'
    'resolve break dates to row indices',   'estimates/resolve_break_dates.m'
    'estimate the scheduled models',        'estimates/run_estimates.m'
    'load the previous published vintage',  'estimates/load_previous_vintage.m'
    'sample-extension revision chain',      'estimates/revisions.m'
    'guardrails',                           'estimates/guardrails.m'
    'stage, promote, figures, metadata',    'estimates/publish.m'
    };

% The suite is only a stage when the run is going to call it.
if opt.RunTests
    stages(end+1, :) = {'local unit suite', 'tests/unit/run_unit_tests.m'};
end

for k = 1:numel(opt.Models)
    stages(end+1, :) = {sprintf('model %s', opt.Models{k}), ...
        sprintf('core/+uc/+models/%s.m', opt.Models{k})};  %#ok<AGROW>
end

present = cellfun(@(p) isfile(fullfile(root, strrep(p, '/', filesep))), stages(:, 2));
if all(present)
    return
end

missing = stages(~present, :);
fprintf('\nrun_release: %d of %d stages are missing.\n\n', ...
    size(missing, 1), size(stages, 1));
fprintf('  stage                                 file\n');
fprintf('  ------------------------------------  --------------------------------\n');
for k = 1:size(missing, 1)
    fprintf('  %-36s  %s\n', missing{k, 1}, missing{k, 2});
end
fprintf('\n');

error('uc:run_release:stageMissing', ...
    ['%d of %d stages are missing, listed above. Nothing was fetched, written ' ...
     'or promoted.'], size(missing, 1), size(stages, 1));
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
% measured  the models whose runtime has been measured as this repository runs
%           them - at the settings in estimates/preset.m, on current data, with
%           the marginal likelihood off - which is what decides whether a model
%           may run unattended. The published driver's own runtime is a different
%           quantity and is not what a schedule needs.
%
% Measured 2026-09-12 on the release machine, in one run of all five:
%
%   ucsv_sw07 0.7, ucur_break2 0.7, ar_trend_bound 1.0, uc_2m 3.1,
%   biuc_lrexp 37.4 minutes; 38.7 wall clock with two workers.
%
% A model whose settings change needs re-measuring, because the figure that
% opened the schedule was taken at the old ones.

product  = {'ucsv_sw07', 'ar_trend_bound', 'biuc_lrexp', 'uc_2m', 'ucur_break2'};
measured = {'ucsv_sw07', 'ar_trend_bound', 'biuc_lrexp', 'uc_2m', 'ucur_break2'};
end


% =========================================================================
function check_schedulable(opt)
% check_schedulable - refuse a model whose runtime has not been measured, unless
% the caller has asked for it by name.
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
        ['Runtime has not been measured for any model, so none is on the ' ...
         'quarterly schedule and %s cannot run unattended. Measure them, or ' ...
         'pass ''AllowUnmeasured'',true for a run by hand.'], ...
        strjoin(unmeasured, ', '));
else
    error('uc:run_release:unmeasured', ...
        ['Runtime has never been measured for: %s. Only %s have a measured ' ...
         'runtime, so only those are scheduled. Measure the rest, or pass ' ...
         '''AllowUnmeasured'',true for a one-off run by hand.'], ...
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
