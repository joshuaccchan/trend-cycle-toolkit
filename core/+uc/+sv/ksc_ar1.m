% uc.sv.ksc_ar1 - KSC sampler for a stationary AR(1) log-volatility path.
%
%   [h, S] = uc.sv.ksc_ar1(Ystar, h, phi, sig, mu)
%
% One sweep of the auxiliary-mixture sampler for
%
%   Ystar_t = h_t + log(chi^2_1),   h_t = mu + phi (h_{t-1} - mu) + N(0, sig),
%   h_1 ~ N(mu, sig/(1 - phi^2))
%
% drawing the mixture indicators S, then the whole path in one block. sig is a
% variance.
%
% joshuaccchan/bvar-toolkit's bvar.sv.ksc_ar1_mean samples the same state equation
% and takes its arguments in the order (ystar, h, mu, rho, sig2).

function [h S] = ksc_ar1(Ystar,h,phi,sig,mu)

T = length(h);
%% normal mixture
pi = [0.0073 .10556 .00002 .04395 .34001 .24566 .2575];
mi = [-10.12999 -3.97281 -8.56686 2.77786 .61942 1.79518 -1.08819] - 1.2704;  %% means already adjusted!! %%
sigi = [5.79596 2.61369 5.17950 .16735 .64009 .34023 1.26261];
sqrtsigi = sqrt(sigi);

%% sample S from a 7-point distrete distribution
temprand = rand(T,1);
q = repmat(pi,T,1).*normpdf(repmat(Ystar,1,7),repmat(h,1,7)+repmat(mi,T,1), repmat(sqrtsigi,T,1));
q = q./repmat(sum(q,2),1,7);
S = 7 - sum(repmat(temprand,1,7)<cumsum(q,2),2)+1;
    
%% sample h using the precision-based algorithm
% y^* = h + d + \epsilon, \epsilon \sim N(0,\Omega),
% Hpsi h = \alpha + \nu, \nu \ sim N(0,S),
% where d_t = Ez_t, \Omega = diag(\omega_1,\ldots,\omega_n), 
% \omega_t = var z_t, S = diag(sig/(1-\phi^2), sig, \ldots, sig)
Hphi = speye(T)-sparse(2:T,1:(T-1),phi*ones(1,T-1),T,T);    
invSh = sparse(1:T,1:T,[(1-phi^2)/sig; 1/sig*ones(T-1,1)]);
dconst = mi(S)'; invOmega = spdiags(1./sigi(S)',0,T,T);
h0 = Hphi\[mu; ((1-phi)*mu)*ones(T-1,1)];
Kh = Hphi'*invSh*Hphi;
Ph = Kh + invOmega;
Ch = chol(Ph,'lower');
hhat = Ph\(Kh*h0 + invOmega*(Ystar-dconst));
h = hhat + Ch'\randn(T,1);

end
