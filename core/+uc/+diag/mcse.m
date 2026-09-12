% uc.diag.mcse - Monte Carlo standard errors of posterior means.
%
%   MCSE = uc.diag.mcse(draws, L)
%
% One MCSE per column of draws: the standard error of that column's posterior
% mean, accounting for the chain's autocorrelation through the spectral variance
% at zero. Guardrail G8 anchors its revision tolerance to these, at 3 x MCSE, so
% a move smaller than the sampler's own noise is not reported as a revision.
%
% uc.diag.specvar0.
%
% From chapter06/mcse.m in joshuaccchan/bayesian-macroeconometrics.

function MCSE = mcse(draws, L)
% mcse.m
% Computes Monte Carlo standard errors (MCSEs) for posterior means
% obtained from MCMC output. For each column of draws, MCSE(j) is
% sqrt(Omega_j / R), where Omega_j is the long-run variance estimated
% by the spectral variance at zero. Requires specvar0.m.
%
% Inputs:
%   draws : R-by-k matrix of MCMC draws
%   L     : truncation lag for the spectral variance estimator
%
% Output:
%   MCSE  : 1-by-k vector of Monte Carlo standard errors
[R, k] = size(draws);
MCSE = zeros(1, k);
for j = 1:k
    x = draws(:, j);
    Omega = uc.diag.specvar0(x, L) * R; % long-run variance of x^{(r)}
    MCSE(j) = sqrt(Omega / R);
end
end
