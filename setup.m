% setup.m - put trend-cycle-toolkit on the MATLAB path for this session.
%
%   run setup.m          (from anywhere; the script locates the repo itself)
%
% Adds the repo root and core/ to the path, and checks the three toolboxes. core/
% holds the package folder +uc, so everything is called with the prefix:
%
%   out = uc.models.ucsv_sw07(y);
%   raw = uc.data.fetch_fred('CPIAUCSL', 'Quarterly');
%
% The root goes on as well, because run_release.m sits there and should resolve as
% a command from any folder. The path change lasts for the session only.
%
% NOT put on the path: estimates/. Its files carry generic names - preset.m,
% publish.m, revisions.m - and publish.m shadows a MATLAB built-in for as long as
% the folder is visible. run_release.m adds it for one run and removes it again.

uc_root = fileparts(mfilename('fullpath'));

% The root first, so that run_release resolves. There is no existence check and
% no warning here, unlike core/ below: the root is the folder this script is
% read from, so it is always present.
addpath(uc_root);

% core/ is the only folder added beside the root. It is checked, not
% assumed, because a path silently missing its library is how a session ends up
% calling something else that happens to answer to the same name.
uc_core = fullfile(uc_root, 'core');
if isfolder(uc_core)
    addpath(uc_core);
else
    warning('uc:setup:missingFolder', ...
        'core/ does not exist and was not added to the path, so nothing under uc.* resolves.');
end
clear uc_core

% Release floors. The samplers themselves are undemanding, but the publication
% half of the pipeline is not: publish.m writes figures with exportgraphics,
% which arrived in R2020a, and the data layer reads and writes with the
% readmatrix/writematrix family rather than xlsread. Development and CI are both
% on R2025b, so that is the only release the numbers are actually produced on.
if verLessThan('matlab', '9.1')      % R2016b
    warning('uc:setup:oldMATLAB', ...
        ['This toolkit is tested on R2025b. Releases before R2016b lack ' ...
         'features used throughout the library (implicit expansion, string ' ...
         'handling).']);
elseif verLessThan('matlab', '9.8')  % R2020a
    warning('uc:setup:noExportgraphics', ...
        ['This release predates R2020a, so exportgraphics is unavailable. ' ...
         'The uc.* library and the samplers still run; the figure and ' ...
         'workbook stage of a quarterly release (estimates/publish.m) does ' ...
         'not.']);
end

% Toolbox checks. Only what this repository genuinely uses is checked, and each
% message names what a missing toolbox costs you rather than reporting an
% absence. There is deliberately no Econometrics Toolbox check: uc.diag.ineff,
% geweke and mcse compute their own autocovariances precisely so that the
% convergence diagnostics published in diagnostics.csv do not depend on a
% toolbox a reader may not have.
if isempty(ver('stats'))
    warning('uc:setup:noStats', ...
        ['The Statistics and Machine Learning Toolbox is not available. ' ...
         'The three trend inflation models need it, through gamrnd and ' ...
         'normcdf, as do both auxiliary-mixture samplers in uc.sv, through ' ...
         'normpdf. The two output-gap models, uc_2m and ucur_break2, run on ' ...
         'base MATLAB, so a release without this toolbox still produces the ' ...
         'output gap and trend growth.']);
end
if isempty(ver('optim'))
    warning('uc:setup:noOptim', ...
        ['The Optimization Toolbox is not available. The psi block of the ' ...
         'Chan, Clark and Koop (2018) bivariate model (uc.models.biuc_lrexp) ' ...
         'maximizes its conditional with fminsearch and then fminunc, and ' ...
         'fminunc is the toolbox function. It is the only one of the five ' ...
         'models that needs this toolbox, so what a release loses without it ' ...
         'is one of the three trend inflation columns; the other four models ' ...
         'run unaffected.']);
end

if isfolder(fullfile(uc_root, 'core'))
    fprintf('trend-cycle-toolkit: repo root and core/ added to the path (%s).\n', uc_root);
else
    fprintf('trend-cycle-toolkit: repo root added to the path (%s). core/ is missing.\n', uc_root);
end

% Offer only commands that exist: a quick-start line pointing at a file that is
% not there is worse than no line at all.
if isfile(fullfile(uc_root, 'tests', 'unit', 'run_unit_tests.m'))
    fprintf('  run tests:    run(fullfile(''%s'',''tests'',''unit'',''run_unit_tests.m''))\n', uc_root);
else
    fprintf('  run tests:    tests/unit/run_unit_tests.m is missing.\n');
end

if isfile(fullfile(uc_root, 'run_release.m'))
    fprintf(['  release run:  run_release      (three series from five ' ...
             'models, quarterly)\n']);
else
    fprintf('  release run:  run_release.m is missing.\n');
end

% One absence worth reporting, which breaks nothing, so it is a note rather
% than a warning and it comes after the summary.
%
% The Parallel Computing Toolbox is optional: parfor degrades to an ordinary
% serial loop when no pool is available, and a serial release produces identical
% numbers, because estimates/run_estimates.m seeds each model separately inside
% the loop body rather than relying on one stream shared across workers. All it
% costs is wall time.
if isempty(ver('parallel'))
    fprintf(['  note: no Parallel Computing Toolbox. run_release still runs, ' ...
             'serially - the\n        results are identical, the quarterly ' ...
             'release simply takes longer.\n']);
end

clear uc_root uc_ex
