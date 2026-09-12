function tests = test_diag()
% test_diag - uc.diag against answers that are known in advance.
%
% An AR(1) chain has an integrated autocorrelation time of (1+phi)/(1-phi), and an
% independent one has 1. Those two are what make these tests worth running: they
% check the estimator against arithmetic rather than against its own past output.
tests = functiontests(localfunctions);
end


function setupOnce(t)
t.TestData.rng = rng(11, 'threefry');
end

function teardownOnce(t)
rng(t.TestData.rng);
end


function testIneffMatchesAR1Theory(t)
% The truncation lag has to cover the chain's own autocorrelation. At phi = 0.9
% the integration time is 19, so 200 lags is generous and 5 is far too few.
n = 200000;
for phi = [0.5 0.8 0.9]
    x = ar1(phi, n);
    theory = (1 + phi) / (1 - phi);
    got = uc.diag.ineff(x, 200);
    verifyEqual(t, got, theory, 'RelTol', 0.15, ...
        sprintf('AR(1) phi=%.2f: IF %.2f against a theoretical %.2f', phi, got, theory));
end
end


function testIneffOfIndependentDrawsIsOne(t)
verifyEqual(t, uc.diag.ineff(randn(100000, 1), 100), 1, 'AbsTol', 0.1);
end


function testTooShortALagUnderstatesIneff(t)
% Why trunc_lag is set from the chain rather than left at a default: a lag well
% inside the integration time misses most of the dependence.
x = ar1(0.95, 100000);
verifyLessThan(t, uc.diag.ineff(x, 5), 0.5 * uc.diag.ineff(x, 500));
end


function testMcseIsRootSpecvar0(t)
x = ar1(0.7, 20000);
verifyEqual(t, uc.diag.mcse(x, 200), sqrt(uc.diag.specvar0(x, 200)), 'RelTol', 1e-12);
end


function testMcseShrinksWithChainLength(t)
% Four times the draws, half the Monte Carlo standard error.
long = uc.diag.mcse(ar1(0.6, 80000), 200);
short = uc.diag.mcse(ar1(0.6, 20000), 200);
verifyEqual(t, long / short, 0.5, 'RelTol', 0.25);
end


function testSpecvar0AtZeroLagIsTheSampleVariance(t)
x = randn(5000, 1);
verifyEqual(t, uc.diag.specvar0(x, 0), var(x, 1) / numel(x), 'RelTol', 1e-12);
end


function testColumnsAreHandledIndependently(t)
X = [ar1(0.9, 20000), randn(20000, 1)];
IF = uc.diag.ineff(X, 200);
verifyEqual(t, numel(IF), 2);
verifyGreaterThan(t, IF(1), 5);
verifyEqual(t, IF(2), 1, 'AbsTol', 0.2);
end


function testGewekePassesAStationaryChain(t)
[Z, p] = uc.diag.geweke(ar1(0.5, 40000), 0.10, 0.50, 100);
verifyLessThan(t, abs(Z), 3.29);
verifyGreaterThan(t, p, 0.001);
end


function testGewekeCatchesADriftingChain(t)
n = 40000;
x = ar1(0.5, n) + linspace(0, 10, n)';
verifyGreaterThan(t, abs(uc.diag.geweke(x, 0.10, 0.50, 100)), 3.29);
end


function testThePvalueFormSurvivesTheFarTail(t)
% uc.diag.geweke reports erfc(|Z|/sqrt(2)) where the published file wrote
% 2*(1-normcdf(|Z|)). The two agree wherever the second is accurate, and the
% second reaches exactly zero from |Z| around 8 while the first keeps going.
z = [0.5 1 2 3 5];
verifyEqual(t, erfc(abs(z)/sqrt(2)), 2*(1 - normcdf(abs(z))), 'AbsTol', 1e-15);
verifyEqual(t, 2*(1 - normcdf(10)), 0, ...
    'the published form underflows here, which is what motivated the change');
verifyGreaterThan(t, erfc(10/sqrt(2)), 0);
verifyLessThan(t, erfc(10/sqrt(2)), 1e-20);
end


function testGewekeAutoLagUnderstatesOnAPersistentChain(t)
% The reason run_estimates passes an explicit lag: the built-in rule is
% 4*(n/100)^(2/9), which is 9 lags on 40,000 draws whose integration time is far
% larger, so the long-run variance is understated and |Z| is inflated.
x = ar1(0.98, 40000);
auto = abs(uc.diag.geweke(x));
proper = abs(uc.diag.geweke(x, 0.10, 0.50, 1000));
verifyGreaterThan(t, auto, proper);
end


function testGewekeRejectsABadSplit(t)
% The lifted file raises without an identifier, so this checks only that the
% segments must not overlap.
verifyError(t, @() uc.diag.geweke(randn(1000, 1), 0.6, 0.5), ?MException);
end


% ---------------------------------------------------------------------------
function x = ar1(phi, n)
x = zeros(n, 1);
e = randn(n, 1);
for k = 2:n
    x(k) = phi * x(k-1) + e(k);
end
end
