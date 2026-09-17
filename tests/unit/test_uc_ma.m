function tests = test_uc_ma()
% test_uc_ma - uc.models.uc_ma and the likelihood its psi step minimizes.
%
% The likelihood is checked against the dense Gaussian density it evaluates through
% a banded covariance, and the model, on a short chain, against the shapes and
% supports run_estimates and guardrails read.
tests = functiontests(localfunctions);
end


function setupOnce(t)
t.TestData.rng = rng(12, 'threefry');
end

function teardownOnce(t)
rng(t.TestData.rng);
end


function testMa1LikelihoodMatchesTheDenseDensity(t)
T = 60;
h = 0.3 * randn(T, 1);
y = randn(T, 1);
for psi = [-0.6 0 0.45]
    H = eye(T) + diag(psi * ones(T - 1, 1), -1);
    Omega = H * diag(exp(h)) * H';
    logdet = 2 * sum(log(diag(chol(Omega))));
    dense = -T/2*log(2*pi) - 0.5*logdet - 0.5*y'*(Omega\y);
    verifyEqual(t, uc.util.nllike_ma1_sv(psi, y, h), -dense, 'RelTol', 1e-10, ...
        sprintf('psi = %.2f', psi));
end
end


function testUcMaReturnsWhatThePipelineReads(t)
% Simulated inflation: a random-walk trend plus MA(1) errors with volatility that
% varies over time.
T = 120;
tau = 2 + cumsum(0.2 * randn(T, 1));
u = exp(0.15 * randn(T, 1)) .* randn(T, 1);
y = tau + u + 0.4 * [0; u(1:end-1)];

out = uc.models.uc_ma(y, 'NSim', 60, 'Burnin', 20, 'Thin', 2, 'Seed', 3);
verifyEqual(t, out.model, 'uc_ma');
verifyEqual(t, out.ndraws, 20);
verifySize(t, out.tau, [20 T]);
verifySize(t, out.h, [20 T]);
verifyEqual(t, out.theta_names, {'muh', 'phih', 'sigh2', 'sigtau2', 'psi'});
verifySize(t, out.theta, [20 5]);
verifyTrue(t, all(isfinite([out.tau(:); out.h(:); out.theta(:)])));
verifyLessThan(t, max(abs(out.theta(:, 5))), 1, 'psi must stay invertible');
verifyLessThan(t, max(abs(out.theta(:, 2))), 1, 'phih must stay stationary');
verifyGreaterThan(t, min(out.theta(:, 3:4), [], 'all'), 0, 'variances must be positive');
end


function testUcMaIsReproducibleFromItsSeed(t)
y = 2 + randn(80, 1);
a = uc.models.uc_ma(y, 'NSim', 30, 'Burnin', 10, 'Thin', 1, 'Seed', 5);
b = uc.models.uc_ma(y, 'NSim', 30, 'Burnin', 10, 'Thin', 1, 'Seed', 5);
verifyEqual(t, a.tau, b.tau);
verifyEqual(t, a.theta, b.theta);
end
