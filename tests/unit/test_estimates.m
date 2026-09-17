function tests = test_estimates()
% test_estimates - the release pipeline, on fixtures built to break it.
%
% guardrails is the only thing between a bad chain and a published series, so most
% of what is here hands it a result that ought to be refused and checks that it is.
% A guardrail that has never been seen to fail is a guardrail nobody has tested.
tests = functiontests(localfunctions);
end


% ---- preset ---------------------------------------------------------------
function testPresetReturnsOnePerModelInOrder(t)
cfg = preset({'uc_2m', 'ucsv_sw07'});
verifyEqual(t, numel(cfg), 2);
verifyEqual(t, {cfg.model}, {'uc_2m', 'ucsv_sw07'});
end


function testPresetOverridesApplyToEveryModel(t)
cfg = preset({'uc_2m', 'ucsv_sw07'}, 'NSim', 500, 'Burnin', 100, 'Thin', 1);
verifyEqual(t, [cfg.nsim], [500 500]);
verifyEqual(t, [cfg.burnin], [100 100]);
end


function testPresetTruncationLagFollowsTheStoredChain(t)
cfg = preset('uc_2m', 'NSim', 2200, 'Burnin', 200, 'Thin', 1);
verifyEqual(t, cfg.trunc_lag, floor(2000 / 20));
end


function testPresetRejectsAnUnknownModel(t)
verifyError(t, @() preset('nosuch'), 'uc:estimates:preset:unknownModel');
end


function testPresetRejectsABurninAtLeastAsLongAsTheChain(t)
% nsim is the TOTAL, so a burn-in equal to it would retain nothing.
verifyError(t, @() preset('uc_2m', 'NSim', 100, 'Burnin', 100), ...
    'uc:estimates:preset:burninTooLong');
end


function testEveryModelCarriesASeedAndTheyDiffer(t)
cfg = preset({'ucsv_sw07','ar_trend_bound','biuc_lrexp','uc_ma','uc_2m','ucur_break2'});
seeds = [cfg.seed];
verifyTrue(t, all(isfinite(seeds)));
verifyEqual(t, numel(unique(seeds)), 6, 'no two models may share a stream');
end


function testMarginalLikelihoodIsOffEverywhere(t)
cfg = preset({'ucsv_sw07','ar_trend_bound','biuc_lrexp','uc_ma','uc_2m','ucur_break2'});
verifyFalse(t, any([cfg.compute_ml]));
end


% ---- resolve_break_dates --------------------------------------------------
function testBreakDatesResolveToThePublishedIndices(t)
% t0 = 105 and t1 = 241 are what UCUR_break2.m hard-codes, and they are 1973Q1
% and 2007Q1 only against a 1947Q1 start.
dates = (datetime(1947,1,1) + calquarters(0:317))';
verifyEqual(t, resolve_break_dates({'1973Q1','2007Q1'}, dates), [105; 241]);
end


function testBreakOutsideTheSampleIsRefused(t)
dates = (datetime(1960,1,1) + calquarters(0:39))';
verifyError(t, @() resolve_break_dates({'1955Q1'}, dates), ...
    'uc:estimates:resolve_break_dates:outOfRange');
end


function testBreaksOutOfOrderAreRefused(t)
dates = (datetime(1947,1,1) + calquarters(0:317))';
verifyError(t, @() resolve_break_dates({'2007Q1','1973Q1'}, dates), ...
    'uc:estimates:resolve_break_dates:notOrdered');
end


function testABreakOnTheLastQuarterIsRefused(t)
% It would define a regime with no observations in it.
dates = (datetime(1960,1,1) + calquarters(0:39))';
verifyError(t, @() resolve_break_dates({'1969Q4'}, dates), ...
    'uc:estimates:resolve_break_dates:emptyRegime');
end


% ---- guardrails -----------------------------------------------------------
function testACleanResultPasses(t)
r = fake_result();
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
verifyTrue(t, rep.pass, 'a clean fixture must pass every check that can run');
verifyEqual(t, rep.nfail, 0);
end


function testANaNInTheChainFailsG4(t)
% The check is on the draws, not the summaries: a handful of bad draws average
% into a plausible-looking mean.
r = fake_result();
r.raw.tau(3, 5) = NaN;
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
verifyFalse(t, rep.pass);
verifyTrue(t, any(rep.checks.id == "G4" & rep.checks.status == "fail"));
end


function testADrawOutsideItsBoundsFailsG5(t)
r = fake_result();
r.settings.bounds = [0 5];
r.raw.tau(1, 1) = 7;
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
verifyFalse(t, rep.pass);
verifyTrue(t, any(rep.checks.id == "G5" & rep.checks.status == "fail"));
end


function testAWrongGeneratorFailsG1(t)
r = fake_result();
r.generator = 'twister';
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
verifyFalse(t, rep.pass);
verifyTrue(t, any(rep.checks.id == "G1" & rep.checks.status == "fail"));
end


function testTooSmallAnEffectiveSampleFailsG7(t)
r = fake_result();
r.diagnostics.ineff(:) = r.ndraws / 10;   % effective sample of 10
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
verifyFalse(t, rep.pass);
verifyTrue(t, any(rep.checks.id == "G7" & rep.checks.status == "fail"));
end


function testTheFirstReleaseMarksG3AndG8NotApplicableRatherThanPassed(t)
% A check that could not run has not passed, and a reader of the first vintage
% is entitled to see which checks stood behind it.
rep = guardrails(fake_result(), struct([]), fake_data(), table(), 'Vintage', '2026Q2');
for id = ["G3", "G8", "G9"]
    rows = rep.checks(rep.checks.id == id, :);
    verifyNotEmpty(t, rows);
    verifyTrue(t, all(rows.status == "n/a"));
    verifyFalse(t, any(rows.status == "pass"));
end
end


function testAMissingExpectationsSeriesFailsG2(t)
d = fake_data();
d = rmfield(d, 'ptr');
rep = guardrails(fake_result(), struct([]), d, table(), 'Vintage', '2026Q2');
verifyFalse(t, rep.pass);
verifyTrue(t, any(rep.checks.id == "G2" & rep.checks.status == "fail"));
end


function testABackfillOffItsValueFailsG2(t)
d = fake_data();
d.ptr.value(5) = d.ptr.value(5) + 1;   % no longer flat
rep = guardrails(fake_result(), struct([]), d, table(), 'Vintage', '2026Q2');
verifyFalse(t, rep.pass);
verifyTrue(t, any(rep.checks.id == "G2" & rep.checks.status == "fail"));
end


% ---- G9 revised input history ---------------------------------------------
function testARevisedInputHistoryWidensG8(t)
% A 0.5pp move in an old trend inflation estimate fails G8 at the ordinary 0.20pp
% tolerance. When the input history was revised underneath it - as BEA's annual
% update does - the same move is expected, and G8 passes at three times the
% tolerance.
revs = one_revision(0.5);

[prev, data] = g9_fixture(false, 1);
rep = guardrails(fake_result(), prev, data, revs, 'Vintage', '2015Q1');
verifyFalse(t, rep.revision.detected);
verifyEqual(t, rep.revision.factor, 1);
verifyTrue(t, any(rep.checks.id == "G8" & rep.checks.status == "fail"), ...
    'with unrevised inputs, a 0.5pp move must fail G8');

[prev, data] = g9_fixture(true, 1);
rep = guardrails(fake_result(), prev, data, revs, 'Vintage', '2015Q1');
verifyTrue(t, rep.revision.detected);
verifyEqual(t, rep.revision.factor, 3);
verifyEqual(t, rep.revision.pce_inflation_max, 0.5, 'AbsTol', 1e-9);
verifyFalse(t, any(rep.checks.id == "G8" & rep.checks.status == "fail"), ...
    'with revised inputs, the same move must pass the widened tolerance');
end


function testARebaseIsNotARevision(t)
% A new base year rescales every level and leaves every growth rate alone.
[prev, data] = g9_fixture(false, 1.1);
rep = guardrails(fake_result(), prev, data, one_revision(0.05), 'Vintage', '2015Q1');
verifyFalse(t, rep.revision.detected);
verifyEqual(t, rep.revision.pce_inflation_max, 0, 'AbsTol', 1e-9);
verifyEqual(t, rep.revision.gdp_growth_max, 0, 'AbsTol', 1e-9);
end


function testAVintageWithoutSourcesLeavesG9NotApplicable(t)
[prev, data] = g9_fixture(false, 1);
prev.sources = struct();
rep = guardrails(fake_result(), prev, data, one_revision(0.05), 'Vintage', '2015Q1');
rows = rep.checks(rep.checks.id == "G9", :);
verifyTrue(t, all(rows.status == "n/a"));
verifyEqual(t, rep.revision.factor, 1);
end


% ---- publish --------------------------------------------------------------
function testPublishRefusesToPromoteAFailingRelease(t)
% The option asks; the report decides.
r = fake_result();
r.raw.tau(1, 1) = NaN;
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
d = tempname; mkdir(d);
c = onCleanup(@() rmdir(d, 's'));
verifyError(t, @() publish(r, rep, table(), struct([]), d, ...
    'Vintage', '2026Q2', 'Promote', true), 'uc:estimates:publish:refused');
end


function testPublishStillStagesARefusedRelease(t)
% The numbers are all there; they are simply not where a reader can download them.
r = fake_result();
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
d = tempname; mkdir(d);
c = onCleanup(@() rmdir(d, 's'));
files = publish(r, rep, table(), struct([]), d, 'Vintage', '2026Q2', 'Promote', false);
verifyNotEmpty(t, files);
verifyTrue(t, isfile(fullfile(d, 'current', 'trend_inflation.csv')));
verifyTrue(t, isfile(fullfile(d, 'current', 'metadata.json')));
end


function testDiagnosticsNameTheirModel(t)
% Two models over the same dates write rows that differ only in their model column.
a = fake_result();
b = fake_result();
b.model = 'uc_ma';
b.seed = 6;
b.settings = preset('uc_ma');
r = [a, b];
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
d = tempname; mkdir(d);
c = onCleanup(@() rmdir(d, 's'));
publish(r, rep, table(), struct([]), d, 'Vintage', '2026Q2', 'Promote', false);
diag = readtable(fullfile(d, 'current', 'diagnostics.csv'), 'TextType', 'string');
verifyEqual(t, diag.Properties.VariableNames{1}, 'model');
verifyEqual(t, sum(diag.model == "ucsv_sw07"), height(a.diagnostics));
verifyEqual(t, sum(diag.model == "uc_ma"), height(b.diagnostics));
end


function testPromoteWritesTheWholeRelease(t)
% The promote path, driven through publish rather than reimplemented here.
% metadata.json records a SHA-256 per series, so without the source files beside
% it that hash refers to nothing: the staging tree is git-ignored.
r = fake_result();
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
stage = tempname; mkdir(stage);
dest = tempname; mkdir(dest);
c1 = onCleanup(@() rmdir(stage, 's'));
c2 = onCleanup(@() rmdir(dest, 's')); 

src.PCE = table((datetime(2000,1,1) + calquarters(0:2))', [100;101;102], ...
    'VariableNames', {'date','value'});
manifest = uc.data.vintage_stamp(src, stage, '2026Q2');
publish(r, rep, table(), manifest, stage, 'Vintage', '2026Q2', ...
    'Promote', true, 'Dest', dest);

for f = {fullfile('current','trend_inflation.csv'), ...
         fullfile('current','metadata.json'), ...
         fullfile('sources','PCE.csv'), ...
         fullfile('vintages','2026Q2','trend_inflation.csv'), ...
         fullfile('vintages','2026Q2','sources','PCE.csv'), ...
         fullfile('figures','current','trend_inflation.png')}
    verifyTrue(t, isfile(fullfile(dest, f{1})), ...
        sprintf('a promoted release must contain %s', f{1}));
end
end


function testPromotingAVintageTwiceIsRefused(t)
% A frozen vintage is written once: rewriting it would move the archive a
% revision is measured against.
r = fake_result();
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
stage = tempname; mkdir(stage);
dest = tempname; mkdir(dest);
c1 = onCleanup(@() rmdir(stage, 's'));
c2 = onCleanup(@() rmdir(dest, 's')); 
src.PCE = table((datetime(2000,1,1) + calquarters(0:2))', [100;101;102], ...
    'VariableNames', {'date','value'});
manifest = uc.data.vintage_stamp(src, stage, '2026Q2');
publish(r, rep, table(), manifest, stage, 'Vintage', '2026Q2', ...
    'Promote', true, 'Dest', dest);
verifyError(t, @() publish(r, rep, table(), manifest, stage, 'Vintage', '2026Q2', ...
    'Promote', true, 'Dest', dest), 'uc:estimates:publish:vintageExists');
end


function testPublishRequiresAVintage(t)
r = fake_result();
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
d = tempname; mkdir(d);
c = onCleanup(@() rmdir(d, 's'));
verifyError(t, @() publish(r, rep, table(), struct([]), d), ...
    'uc:estimates:publish:noVintage');
end


% ---- load_previous_vintage ------------------------------------------------
function testAnEmptyArchiveGivesAnEmptyStruct(t)
d = tempname; mkdir(d);
c = onCleanup(@() rmdir(d, 's'));
verifyTrue(t, isempty(load_previous_vintage(d, '2026Q2')));
end


function testAnArchiveWithNothingBelowIsAnError(t)
% A renamed or half-restored archive, which must not return quietly.
d = tempname;
mkdir(fullfile(d, 'estimates', 'vintages', '2030Q1'));
c = onCleanup(@() rmdir(d, 's'));
verifyError(t, @() load_previous_vintage(d, '2026Q2'), ...
    'uc:estimates:load_previous_vintage:noneBelow');
end


% ---- revisions ------------------------------------------------------------
function testRevisionsOnTheFirstReleaseIsEmptyWithTheRightColumns(t)
% A file of zeros would report a measurement that was never made.
revs = revisions(fake_result(), struct([]), fake_data());
verifyEqual(t, height(revs), 0);
verifyEqual(t, revs.Properties.VariableNames, ...
    {'date', 'model', 'series', 'total', 'sample'});
end


function testRevisionsRefusesAComponentItCannotCompute(t)
verifyError(t, @() revisions(fake_result(), struct([]), fake_data(), ...
    'Components', {'nosuch'}), 'uc:estimates:revisions:unknownComponent');
end


% ---------------------------------------------------------------------------
function revs = one_revision(move)
% One revision to an old trend inflation estimate, well inside G8's window.
revs = table(datetime(2005, 1, 1), "ucsv_sw07", "trend_inflation", move, 0, ...
    'VariableNames', {'date', 'model', 'series', 'total', 'sample'});
end


function [prev, data] = g9_fixture(revised, rebase)
% A previous vintage's archived input levels and this release's model-ready
% inputs, 1960Q1 to 2014Q4. revised adds 0.5pp to 1990-1995 inflation in the
% previous vintage; rebase multiplies the previous vintage's levels by a constant.
dates = (datetime(1960, 1, 1) + calquarters(0:219))';
n = numel(dates);
infl_new = 3 + sin((1:n-1)' / 6);
gdp_growth = 3 + cos((1:n-1)' / 9);

infl_old = infl_new;
if revised
    old = dates(2:end) >= datetime(1990, 1, 1) & dates(2:end) <= datetime(1995, 10, 1);
    infl_old(old) = infl_old(old) + 0.5;
end

pce_old = 100 * exp(cumsum([0; infl_old]) / 400) * rebase;
gdp = 1000 * exp(cumsum([0; gdp_growth]) / 400);

prev = struct();
prev.vintage = '2014Q4';
prev.path = '';
prev.series = struct();
prev.metadata = struct();
prev.sources = struct( ...
    'PCE',   table(dates, pce_old,     'VariableNames', {'date', 'value'}), ...
    'GDPC1', table(dates, gdp * rebase, 'VariableNames', {'date', 'value'}));

data = fake_data();
data.infl = table(dates(2:end), infl_new, 'VariableNames', {'date', 'value'});
data.lgdp = table(dates, 100 * log(gdp), 'VariableNames', {'date', 'value'});
end


function r = fake_result()
% One model's worth of output, shaped exactly as run_estimates returns it.
nd = 400;
n  = 60;
dates = (datetime(2000,1,1) + calquarters(0:n-1))';
draws = 2 + 0.1 * randn(nd, n);

r = struct();
r.model = 'ucsv_sw07';
q = quantile_cols(draws, [0.05 0.16 0.84 0.95]);
r.series.trend_inflation = struct('draws', draws, 'dates', dates, ...
    'summary', table(dates, mean(draws,1)', q(:,1), q(:,2), q(:,3), q(:,4), ...
        'VariableNames', {'date','mean','p05','p16','p84','p95'}));
r.diagnostics = table(repmat("trend_inflation", n, 1), dates, ...
    string(compose("trend_inflation[%d]", (1:n)')), ...
    repmat(2.0, n, 1), repmat(0.01, n, 1), zeros(n,1), ones(n,1), ...
    'VariableNames', {'series','date','parameter','ineff','mcse','geweke_z','geweke_p'});
r.accept = struct();
r.seed = 1;
r.settings = preset('ucsv_sw07');
r.sample_start = '2000Q1';
r.sample_end = '2014Q4';
r.ndraws = nd;
r.raw = struct('tau', draws, 'ndraws', nd);
r.generator = 'threefry';
r.elapsed = 1;
r.versions = struct('matlab', version, 'release', version('-release'));
end


function d = fake_data()
% PTR as build_ptr returns it: 32 flat quarters from 1960Q1, then observations.
n = 240;
dates = (datetime(1960,1,1) + calquarters(0:n-1))';
v = [repmat(1.6827, 32, 1); 2 + 0.01*(1:n-32)'];
d.ptr = table(dates, v, 'VariableNames', {'date','value'});
d.infl = table(dates, 2 + randn(n,1), 'VariableNames', {'date','value'});
d.lgdp = table(dates, cumsum(ones(n,1)), 'VariableNames', {'date','value'});
end


function q = quantile_cols(X, probs)
X = sort(X, 1);
n = size(X, 1);
pos = probs(:)' * n + 0.5;
lo = max(1, floor(pos));  hi = min(n, ceil(pos));  w = pos - floor(pos);
q = zeros(size(X, 2), numel(probs));
for j = 1:numel(probs)
    q(:, j) = (1 - w(j)) * X(lo(j), :)' + w(j) * X(hi(j), :)';
end
end
