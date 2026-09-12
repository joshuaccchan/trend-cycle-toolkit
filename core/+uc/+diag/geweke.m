% uc.diag.geweke - Geweke's convergence diagnostic.
%
%   [Z, pval] = uc.diag.geweke(draws)
%   [Z, pval, info] = uc.diag.geweke(draws, 0.10, 0.50, 'auto')
%
% Compares the mean of each column's first tenth against its last half, scaled by
% the long-run variances of the two segment means. Under stationarity Z is
% approximately standard normal, so a large |Z| is evidence against convergence
% for that summary.
%
% The p-value is erfc(|Z|/sqrt(2)). It needs no Statistics Toolbox, which keeps the
% two output-gap models and their diagnostics on base MATLAB, and it stays accurate
% past |Z| = 8, where 2*(1-normcdf(|Z|)) underflows to exactly zero.
%
% THE 'auto' LAG IS TOO SHORT FOR MCMC OUTPUT. It is 4*(n/100)^(2/9), built for
% weakly dependent data: on a 40,000-draw chain it picks 9 lags, so a chain with an
% integration time in the hundreds has its long-run variance understated and every
% |Z| inflated. Pass an explicit lag.
%
% From chapter06/geweke_diag.m in joshuaccchan/bayesian-macroeconometrics.

function [Z, pval, info] = geweke(draws, a, b, Lrule)
% geweke_diag.m
% Computes Geweke's convergence diagnostic for MCMC output. For each
% column of draws, the chain is split into an early segment A (first
% fraction a) and a late segment B (last fraction 1-b), the segment
% means are compared, and the Z-statistic
%       Z = (mean_A - mean_B) / sqrt(S_A + S_B)
% is computed, where S_A and S_B are spectral-variance estimates of the
% long-run variances of the two segment means. Under stationarity, Z is
% approximately standard normal; large |Z| provides evidence against
% convergence for the chosen summary. Requires specvar0.m.
%
% Inputs:
%   draws : R-by-k matrix of posterior draws (each column is a scalar
%           summary computed from MCMC output)
%   a     : fraction for early segment (default 0.10)
%   b     : fraction defining late segment, B = floor(b*R):R
%           (default 0.50)
%   Lrule : truncation-lag rule for the spectral variance estimator,
%           either 'auto' (default) or a nonnegative integer L
%
% Outputs:
%   Z     : 1-by-k vector of Geweke Z-statistics
%   pval  : 1-by-k vector of two-sided p-values (normal approximation)
%   info  : struct with fields A, B, LA, LB, a, b giving the segment
%           indices and chosen truncation lags
if nargin < 2 || isempty(a), a = 0.10; end
if nargin < 3 || isempty(b), b = 0.50; end
if nargin < 4 || isempty(Lrule), Lrule = 'auto'; end

[R, k] = size(draws);
if ~(0 < a && a < b && b < 1)
    error('Require 0 < a < b < 1.');
end

A = 1:floor(a*R);
B = floor(b*R):R;

nA = length(A);
nB = length(B);

% Choose truncation lags
if ischar(Lrule) || isstring(Lrule)
    if strcmpi(Lrule,'auto')
        LA = max(0, floor(4*(nA/100)^(2/9)));
        LB = max(0, floor(4*(nB/100)^(2/9)));
    else
        error('Unknown Lrule. Use ''auto'' or an integer.');
    end
else
    LA = max(0, floor(Lrule));
    LB = LA;
end

Z = nan(1,k);
pval = nan(1,k);

for j = 1:k
    xA = draws(A,j);
    xB = draws(B,j);

    mA = mean(xA);
    mB = mean(xB);

    SA = uc.diag.specvar0(xA, LA);  % long-run variance of mean for segment A
    SB = uc.diag.specvar0(xB, LB);  % long-run variance of mean for segment B

    Z(j) = (mA - mB) / sqrt(SA + SB);

    % Two-sided p-value under N(0,1)
    pval(j) = erfc(abs(Z(j))/sqrt(2));
end

info.A = A;
info.B = B;
info.LA = LA;
info.LB = LB;
info.a = a;
info.b = b;
end
