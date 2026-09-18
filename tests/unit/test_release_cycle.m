function tests = test_release_cycle()
% test_release_cycle - a release that has a predecessor.
%
% Two releases over a scratch archive: one estimated and promoted, a second
% estimated on the same inputs with a quarter added. G3, G8, G9 and G10 and the
% sample-extension chain run here against a vintage the pipeline wrote.
%
% The inputs are the levels under estimates/sources/: a model that mixed badly on
% generated data would fail G7 for a reason of the fixture's own making. The chains
% are short, so their inefficiency factors are capped. MCSE is left as measured,
% since G8's tolerance is built from it.
%
% total - sample comes out at zero. The data did not move over the previous sample
% and the seed is fixed, so chain B is the first release's chain.
tests = functiontests(localfunctions);
end


function setupOnce(t)
% Both releases run before any test does: the samplers are the expensive part.
repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
root = tempname;
mkdir(root);
dest = fullfile(root, 'estimates');
mkdir(dest);

pce = upto(readtable(fullfile(repo, 'estimates', 'sources', 'PCE.csv')));
gdp = upto(readtable(fullfile(repo, 'estimates', 'sources', 'GDPC1.csv')));
ptr = uc.data.build_ptr(readtable(fullfile(repo, 'estimates', 'sources', 'PTR.csv')));

first  = datetime(2014, 10, 1);   % 2014Q4, promoted into the archive
second = datetime(2015,  1, 1);   % 2015Q1, checked against it

data1 = model_ready(pce, gdp, ptr, first);
data2 = model_ready(pce, gdp, ptr, second);
src1 = struct('PCE', upto(pce, first),  'GDPC1', upto(gdp, first));
src2 = struct('PCE', upto(pce, second), 'GDPC1', upto(gdp, second));

% uc_2m as well, because G10 reads output gap revisions.
cfg = preset({'ucsv_sw07', 'uc_2m'}, 'NSim', 2000, 'Burnin', 200, 'Thin', 2, ...
    'SampleStart', '1995Q1');

res1 = mixes_well_enough(run_estimates(cfg, data1, 'Parallel', false));
rep1 = guardrails(res1, struct([]), data1, revisions(res1, struct([]), data1), ...
    'Vintage', '2014Q4');
stage1 = fullfile(root, 'stage2014Q4');
mkdir(stage1);
publish(res1, rep1, table(), uc.data.vintage_stamp(src1, stage1, '2014Q4'), ...
    stage1, 'Vintage', '2014Q4', 'Promote', true, 'Dest', dest);

previous = load_previous_vintage(root, '2015Q1');
res2 = mixes_well_enough(run_estimates(cfg, data2, 'Parallel', false));
revs = revisions(res2, previous, data2);
rep2 = guardrails(res2, previous, data2, revs, 'Vintage', '2015Q1');

% Field by field: struct() would read a struct array as a shape to replicate.
t.TestData.root = root;
t.TestData.dest = dest;
t.TestData.stage = fullfile(root, 'stage2015Q1');
t.TestData.first_report = rep1;
t.TestData.previous = previous;
t.TestData.results = res2;
t.TestData.revisions = revs;
t.TestData.report = rep2;
t.TestData.sources = src2;
mkdir(t.TestData.stage);
end


function teardownOnce(t)
rmdir(t.TestData.root, 's');
end


% ---- the archive round trip -----------------------------------------------
function testThePreviousVintageIsTheReleaseThePipelineWrote(t)
p = t.TestData.previous;
verifyEqual(t, p.vintage, '2014Q4');
verifyEqual(t, sort(fieldnames(p.series)), ...
    sort({'trend_inflation'; 'output_gap'; 'trend_growth'}));
verifyEqual(t, sort(fieldnames(p.sources)), sort({'PCE'; 'GDPC1'}));
verifyEqual(t, p.metadata.vintage, '2014Q4');
verifyGreaterThan(t, height(p.series.trend_inflation), 0);
end


% ---- the checks that needed a predecessor ---------------------------------
function testEveryCheckThatCouldNotRunOnTheFirstReleaseRanOnThisOne(t)
% A check still marked n/a here would leave a complete-looking report over
% unchecked numbers.
c = t.TestData.report.checks;
for id = {'G3', 'G8', 'G9', 'G10'}
    rows = c(c.id == string(id{1}), :);
    verifyGreaterThan(t, height(rows), 0, sprintf('%s wrote no row', id{1}));
    verifyEmpty(t, rows.note(rows.status == "n/a"), ...
        sprintf('%s is still n/a on a release that has a predecessor', id{1}));
end
verifyTrue(t, all(t.TestData.first_report.checks.status(...
    ismember(t.TestData.first_report.checks.id, ["G3" "G8" "G9" "G10"])) == "n/a"));
end


function testG3SeesOneMoreQuarterThanThePreviousRelease(t)
c = t.TestData.report.checks;
ext = c(c.id == "G3" & endsWith(c.statistic, 'sample extends'), :);
verifyGreaterThan(t, height(ext), 0);
verifyEqual(t, ext.value, ext.tolerance + 1, ...
    'a release one quarter longer must publish one more quarter per series');
verifyTrue(t, all(c.status(c.id == "G3") == "pass"));
end


function testAnUnrevisedInputHistoryLeavesG8sToleranceAlone(t)
% The widened case is covered on a fixture in test_estimates.
r = t.TestData.report.revision;
verifyFalse(t, r.detected);
verifyEqual(t, r.factor, 1);
c = t.TestData.report.checks;
verifyEqual(t, c.value(c.id == "G9" & c.statistic == "G8 tolerance factor"), 1);
end


% ---- the revision table ---------------------------------------------------
function testTheRevisionTableCoversEveryModelAndSeries(t)
revs = t.TestData.revisions;
verifyEqual(t, revs.Properties.VariableNames, ...
    {'date', 'model', 'series', 'total', 'sample'});
verifyEqual(t, sort(unique(revs.model)), sort(["ucsv_sw07"; "uc_2m"]));
verifyEqual(t, sort(unique(revs.series)), ...
    sort(["trend_inflation"; "output_gap"; "trend_growth"]));
verifyTrue(t, all(isfinite(revs.total)) && all(isfinite(revs.sample)));
end


function testChainBReproducesThePreviousReleaseDrawForDraw(t)
% total - sample is chain B against what was published, which is what G8 judges.
% All that is left between them here is the CSV round trip.
revs = t.TestData.revisions;
worst = max(abs(revs.total - revs.sample));
verifyLessThan(t, worst, 1e-8, sprintf(...
    ['chain B moved %.3gpp against the published estimate on unrevised data. ' ...
     'Either SampleEnd cut a different window than the previous release ran, ' ...
     'or the chains are no longer seeded alike.'], worst));
end


% ---- publishing it --------------------------------------------------------
function testTheSecondReleaseIsFitToPublishAndPublishes(t)
d = t.TestData;
verifyTrue(t, d.report.pass, sprintf('%d check(s) failed: %s', d.report.nfail, ...
    strjoin(cellstr(d.report.checks.statistic(d.report.checks.status == "fail")), ', ')));

manifest = uc.data.vintage_stamp(d.sources, d.stage, '2015Q1');
publish(d.results, d.report, d.revisions, manifest, d.stage, ...
    'Vintage', '2015Q1', 'Promote', true, 'Dest', d.dest);

% revisions/ is the one the first release never writes.
for f = {fullfile('vintages', '2015Q1', 'trend_inflation.csv'), ...
         fullfile('vintages', '2015Q1', 'sources', 'PCE.csv'), ...
         fullfile('current', 'output_gap.csv'), ...
         fullfile('revisions', '2015Q1.csv')}
    verifyTrue(t, isfile(fullfile(d.dest, f{1})), ...
        sprintf('a second release must write %s', f{1}));
end

published = readtable(fullfile(d.dest, 'revisions', '2015Q1.csv'), 'TextType', 'string');
verifyEqual(t, height(published), height(d.revisions));
end


% ---------------------------------------------------------------------------
function tbl = upto(tbl, last)
% The levels as they stood at a release. CSV dates may come back as text.
if ~isdatetime(tbl.date), tbl.date = datetime(tbl.date); end
if nargin > 1
    tbl = tbl(tbl.date <= last, :);
end
end


function d = model_ready(pce, gdp, ptr, last)
% What run_estimates reads, through the transforms a release uses.
d = struct();
d.infl = uc.data.annualized_log_diff(upto(pce, last));
lgdp = upto(gdp, last);
d.lgdp = table(lgdp.date, 100 * log(lgdp.value), 'VariableNames', {'date', 'value'});
d.ptr = upto(ptr, last);
end


function r = mixes_well_enough(r)
% Capping the inefficiency factor at ndraws/200 puts every parameter at twice
% G7's floor, so the check runs on a fixture too short to clear it on its own.
for k = 1:numel(r)
    r(k).diagnostics.ineff = min(r(k).diagnostics.ineff, r(k).ndraws / 200);
end
end
