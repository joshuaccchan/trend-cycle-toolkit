% uc.diag.specvar0 - long-run variance of a sample mean, at frequency zero.
%
%   S = uc.diag.specvar0(x, L)
%
% The Bartlett-window spectral-variance estimator every other function in this
% package is built on. x is a draw sequence, L the truncation lag, and S the
% long-run variance of mean(x), so sqrt(S) is that mean's Monte Carlo standard
% error.
%
% From chapter06/specvar0.m in joshuaccchan/bayesian-macroeconometrics.

function S = specvar0(x, L)
% specvar0.m
% Estimates the long-run variance of the sample mean of x using a
% Bartlett-window spectral-variance estimator at frequency zero:
%       S = (gamma_0 + 2 * sum_{ell=1}^{L} w_ell * gamma_ell) / T,
% where gamma_ell is the lag-ell sample autocovariance and the weights
% w_ell = 1 - ell/(L+1) are Bartlett (Newey-West) weights.
%
% Inputs:
%   x : T-by-1 vector (demeaned internally)
%   L : truncation lag (nonnegative integer)
%
% Output:
%   S : long-run variance of the sample mean of x
x = x(:);
T = length(x);
x = x - mean(x);

% autocovariances up to lag L
gamma0 = (x' * x) / T;
Sx = gamma0;

for ell = 1:L
    w = 1 - ell/(L+1);  % Bartlett weight
    gamma = (x(1+ell:end)' * x(1:end-ell)) / T;
    Sx = Sx + 2 * w * gamma;
end

% long-run variance of the mean
S = Sx / T;
end
