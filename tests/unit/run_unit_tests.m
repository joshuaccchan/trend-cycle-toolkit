% run_unit_tests - the local unit suite, and the one CI runs on every push.
%
%   run('tests/unit/run_unit_tests.m')
%
% Runs every test_*.m in this folder and errors if any test fails, because
% run_release calls this at step 4 and a suite that returned quietly would let a
% release proceed on broken code.
%
% NOTHING HERE TOUCHES THE NETWORK. The fetchers are exercised through their
% 'File' option on fixtures written to a temporary folder, so the suite runs the
% parser and its guards without a live source. The draw-for-draw comparison
% against the published drivers does need the network and is not part of this
% suite; it is run by hand before a release.
%
% UC_SKIP_TESTS takes a comma-separated list of test function names. A name in it
% that matches no test is an error, so a skip cannot quietly stop skipping when a
% test is renamed.

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));

run(fullfile(root, 'setup.m'));
% run_release has estimates/ on the path already and keeps needing it after this
% suite returns. Only remove what this file added.
est = fullfile(root, 'estimates');
added_est = ~ismember(est, strsplit(path, pathsep));
if added_est
    addpath(est);
    cleanup = onCleanup(@() rmpath(est)); %#ok<NASGU>
end

suite = matlab.unittest.TestSuite.fromFolder(here);

skip = strtrim(strsplit(getenv('UC_SKIP_TESTS'), ','));
skip = skip(~cellfun(@isempty, skip));
if ~isempty(skip)
    names = arrayfun(@(t) last_part(t.Name), suite, 'UniformOutput', false);
    unknown = setdiff(skip, names);
    if ~isempty(unknown)
        error('uc:tests:unknownSkip', ...
            ['UC_SKIP_TESTS names %s, which match no test in %s. A skip that ' ...
             'matches nothing is a skip that stopped working.'], ...
            strjoin(unknown, ', '), here);
    end
    suite = suite(~ismember(names, skip));
    fprintf('skipping %d test(s): %s\n', numel(skip), strjoin(skip, ', '));
end

runner = matlab.unittest.TestRunner.withTextOutput;
result = runner.run(suite);

fprintf('\n%d passed, %d failed, %d incomplete, %.1fs\n', ...
    sum([result.Passed]), sum([result.Failed]), sum([result.Incomplete]), ...
    sum([result.Duration]));

if any([result.Failed])
    error('uc:tests:failed', '%d unit test(s) failed.', sum([result.Failed]));
end


function s = last_part(name)
parts = strsplit(name, '/');
s = parts{end};
end
