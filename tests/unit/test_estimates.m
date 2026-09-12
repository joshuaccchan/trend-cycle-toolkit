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
cfg = preset({'ucsv_sw07','ar_trend_bound','biuc_lrexp','uc_2m','ucur_break2'});
seeds = [cfg.seed];
verifyTrue(t, all(isfinite(seeds)));
verifyEqual(t, numel(unique(seeds)), 5, 'no two models may share a stream');
end


function testMarginalLikelihoodIsOffEverywhere(t)
cfg = preset({'ucsv_sw07','ar_trend_bound','biuc_lrexp','uc_2m','ucur_break2'});
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
for id = ["G3", "G8"]
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


function testPromoteWritesTheWholeRelease(t)
% The promote path, driven through publish rather than reimplemented here.
% metadata.json records a SHA-256 per series, so without the source files beside
% it that hash refers to nothing: the staging tree is git-ignored.
r = fake_result();
rep = guardrails(r, struct([]), fake_data(), table(), 'Vintage', '2026Q2');
stage = tempname; mkdir(stage);
dest = tempname; mkdir(dest);
c1 = onCleanup(@() rmdir(stage, 's')); %#ok<NASGU>
c2 = onCleanup(@() rmdir(dest, 's'));  %#ok<NASGU>

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
c1 = onCleanup(@() rmdir(stage, 's')); %#ok<NASGU>
c2 = onCleanup(@() rmdir(dest, 's'));  %#ok<NASGU>
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
