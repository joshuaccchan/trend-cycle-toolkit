% setup.m - put trend-cycle-toolkit on the MATLAB path for this session.
%
%   run setup.m          (from anywhere; the script locates the repo itself)
%
% Adds the repo root and core/ to the path. core/ holds the MATLAB package
% folder +uc, so everything in the library is called with the package prefix
% once core/ is on the path:
%
%   out = uc.models.ucsv_sw07(y, nsim, burnin);
%   h   = uc.sv.ksc_rw_h0(ystar, h, sig, h0);
%   raw = uc.data.fetch_fred('CPIAUCSL', 'Quarterly');
%
% The prefix is 'uc' for unobserved components, the class of model this library
% implements. The repository is named for what it publishes - trend inflation,
% the output gap and trend output growth - and the package for how those series
% are produced. The two names differ on purpose; it is not an inconsistency to
% be tidied away later.
%
% Nothing is added permanently - the path change lasts for the session. Add this
% line to your own startup.m if you want it every time:
%
%   run('<path-to-repo>/setup.m')
%
% The repo root goes on the path as well, because the release driver sits there.
% run_release.m is a top-level file, so adding the root is what makes the closing
% quick-start line below true: run_release resolves as a command from whatever
% folder you happen to be in. The root holds exactly two .m files, setup.m and
% run_release.m, so this adds two unambiguous names and no generic ones.
%
% NOT put on the path: estimates/. Its files carry deliberately generic names -
% preset.m, publish.m, revisions.m - and publish.m shadows a MATLAB built-in of
% the same name for as long as the folder is visible. run_release.m adds
% estimates/ to the path for the duration of one release run and removes it
% again, which is the only time those names need to resolve.
%
% STATUS: this repository is a skeleton - the library and the estimates pipeline
% are imported over later phases (see README.md). This script is written to be
% honest about that: folders that do not exist yet are reported rather than
% silently added, and the closing lines offer only commands that exist on disk
% at the time you run it.

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
        ['core/ does not exist and was not added to the path. The library is ' ...
         'extracted into it in phase 4; until then nothing under uc.* ' ...
         'resolves.']);
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
    fprintf('trend-cycle-toolkit: repo root added to the path (%s). core/ arrives in phase 4.\n', uc_root);
end

% Offer only commands that exist. Everything here is imported over several
% phases, and a quick-start line pointing at a file that is not there yet is
% worse than no line at all.
if isfile(fullfile(uc_root, 'tests', 'unit', 'run_unit_tests.m'))
    fprintf('  run tests:    run(fullfile(''%s'',''tests'',''unit'',''run_unit_tests.m''))\n', uc_root);
else
    fprintf('  run tests:    tests/unit/run_unit_tests.m not written yet (phase 4).\n');
end

if isfile(fullfile(uc_root, 'run_release.m'))
    fprintf(['  release run:  run_release      (three series from five models, ' ...
             'quarterly; a skeleton\n                               until ' ...
             'phase 5 - read its header)\n']);
else
    fprintf('  release run:  run_release.m not written yet (phase 5).\n');
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
