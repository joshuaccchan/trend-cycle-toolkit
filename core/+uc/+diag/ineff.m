% uc.diag.ineff - inefficiency factors for MCMC output.
%
%   IF = uc.diag.ineff(draws, L)
%
% One inefficiency factor per column of draws: the ratio of the chain's long-run
% variance to its marginal variance, so IF = 10 means ten correlated draws carry
% the information of one independent draw. A column's effective sample size is
% its draw count divided by its IF.
%
% From chapter06/inefficiency_factor.m in joshuaccchan/bayesian-macroeconometrics.

function IF = ineff(draws, L)
% inefficiency_factor.m
% Computes inefficiency factors (integrated autocorrelation times) for
% MCMC output. For each column of draws, IF(j) = Omega_j / sigma2_j,
% where sigma2_j is the marginal variance and Omega_j is the long-run
% variance estimated by the spectral variance at zero (Bartlett window).
% Requires specvar0.m.
%
% Inputs:
%   draws : R-by-k matrix of MCMC draws (each column is a scalar sequence)
%   L     : truncation lag for the spectral variance estimator
%
% Output:
%   IF    : 1-by-k vector of inefficiency factors
[R, k] = size(draws);
IF = zeros(1, k);
for j = 1:k
    x = draws(:, j);
    sigma2 = var(x, 1);          % marginal variance (population version)
    Omega  = uc.diag.specvar0(x, L) * R; % long-run variance of x^{(r)}
    IF(j) = Omega / sigma2;
end
end
