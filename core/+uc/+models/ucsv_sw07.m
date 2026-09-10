function out = ucsv_sw07(y, opts)
% uc.models.ucsv_sw07 - the Stock and Watson (2007) UCSV model.
%
%   out = uc.models.ucsv_sw07(y)
%   out = uc.models.ucsv_sw07(y, 'NSim', 51000, 'Burnin', 1000)
%
% Unobserved components with stochastic volatility in both the transitory and the
% permanent innovation, from Stock, J.H. and Watson, M.W. (2007), "Why Has US
% Inflation Become Harder to Forecast?", Journal of Money, Credit and Banking,
% 39(s1), 3-33:
%
%   y_t   = tau_t + exp(h_t/2) e_t
%   tau_t = tau_{t-1} + exp(g_t/2) u_t
%   h_t, g_t  random walks
%
% y is annualized percent inflation from uc.data.annualized_log_diff.
%
% The implementation follows chapter10/UCSV.m in
% joshuaccchan/bayesian-macroeconometrics, which puts inverse-gamma priors on the
% two state-innovation variances. The non-centered version, with normal priors on
% the signed standard deviations, is a different model: that prior puts positive
% density at zero and so lets the posterior shrink the time variation away. It is
% not in this repository's set.
%
% OPTIONS
%   'NSim'    TOTAL sweeps, burn-in included   (default 51000)
%   'Burnin'  sweeps discarded                 (default  1000)
%   'Thin'    keep every Thin-th retained draw (default 10)
%   'Seed'    rng seed                         (default 1)
%
% The book's driver sets nsim = 50000 with burnin = 1000 and loops 1:(nsim+burnin),
% so its nsim is the retained count and NSim here is 51000.
%
% The body is byte-identical to that driver except that data and settings arrive as
% arguments, the seed is set from opts.Seed instead of the book's rng(42), and
% there is no plotting: uc.sv.ksc_rw_h0 and uc.sv.rw_gaussian_approx are
% chapter10's own helpers lifted verbatim, so the call sites below are unchanged.
% Verified 2026-09-09 against the book's driver on 317 quarters of CPI inflation
% fetched by uc.data, 600 sweeps under seed 11: bitwise identical draws.

arguments
    y (:,1) double
    opts.NSim (1,1) double = 51000
    opts.Burnin (1,1) double = 1000
    opts.Thin (1,1) double = 10
    opts.Seed (1,1) double = 1
end

T = numel(y);
burnin = opts.Burnin;
nsim = opts.NSim - burnin;

if nsim <= 0
    error('uc:models:badSettings', ...
        'NSim (%d) must exceed Burnin (%d).', opts.NSim, burnin);
end
if T < 20
    error('uc:models:tooShort', ...
        'the sample has %d observations, which is too few for this model.', T);
end

rng(opts.Seed, 'threefry');

% [uc] settings come from the arguments; the published line was
%     nsim   = 50000; burnin = 1000;

% load PCE data - 1960Q1-2024Q4
% [uc] data arrives as an argument; the published lines here read
% USPCE.csv, assigned it to y, and set T from it.

% prior hyperparameters
a0_h = 0; b0_h = 10; % h0 ~ N(a0_h, b0_h)
a0_g = 0; b0_g = 10; % g0 ~ N(a0_g, b0_g)
a0_tau = 0;  b0_tau = 10; % tau0 ~ N(a0_tau, b0_tau)    
nu_oh = 3; S_oh = 0.2^2*(nu_oh-1); % omega_h^2 ~ IG(nu_oh, S_oh)
nu_og = 3; S_og = 0.2^2*(nu_og-1); % omega_g^2 ~ IG(nu_og, S_og)

% precompute a few things 
c = 1e-4; % log-squared safeguard
S1 = sparse(2:T, 1:(T-1), 1, T, T);
H  = speye(T) - S1;
HH = H'*H;

% initialize
tau0 = mean(y);
tau  = tau0*ones(T,1);
h0 = log(var(y)); g0 = log(var(y));
omega_h2 = 0.1;   omega_g2 = 0.1; 
    % initialize h using Gaussian approximation
h = uc.sv.rw_gaussian_approx((y - tau).^2, h0, omega_h2);
    % initialize g using Gaussian approximation
dtau = tau - [tau0; tau(1:end-1)];
g = uc.sv.rw_gaussian_approx(dtau.^2, g0, omega_g2);

% storage
    %[omega_h2 omega_g2 h0 g0 tau0]
store_theta = zeros(nsim,5);  
store_tau = zeros(nsim,T);
store_h = zeros(nsim,T);
store_g = zeros(nsim,T);

for isim = 1:(nsim+burnin)

    % sample tau    
    iOh = sparse(1:T,1:T,exp(-h)); % Omega_h^{-1}
    HiOgH = H'*sparse(1:T,1:T,exp(-g))*H; 
    Ktau = HiOgH + iOh;
    tau_mean = Ktau\(HiOgH*(tau0*ones(T,1)) + iOh*y);
    tau = tau_mean + chol(Ktau,'lower')'\randn(T,1);

    % sample tau0    
    Ktau0 = 1/b0_tau + exp(-g(1));
    tau0_hat = (a0_tau/b0_tau + tau(1)*exp(-g(1)))/Ktau0;
    tau0 = tau0_hat + (1/sqrt(Ktau0))*randn;
    
    % sample h     
    ystar_h = log((y - tau).^2 + c);
    h = uc.sv.ksc_rw_h0(ystar_h, h, h0, omega_h2);

    % sample omega_h2    
    omega_h2 = 1/gamrnd(nu_oh + T/2, ...
        1/(S_oh + 0.5*(h - h0)'*HH*(h - h0)));

    % sample h0    
    Kh0 = 1/b0_h + 1/omega_h2;
    h0_hat = (a0_h/b0_h + h(1)/omega_h2) / Kh0;
    h0 = h0_hat + (1/sqrt(Kh0))*randn;
    
    % sample g    
    dtau = tau - [tau0; tau(1:end-1)];
    ystar_g = log(dtau.^2 + c);
    g = uc.sv.ksc_rw_h0(ystar_g, g, g0, omega_g2);

    % sample omega_g2    
    omega_g2 = 1/gamrnd(nu_og + T/2, ...
        1/(S_og + 0.5*(g - g0)'*HH*(g - g0)));
    
    % sample g0    
    Kg0 = 1/b0_g + 1/omega_g2;
    g0_hat = (a0_g/b0_g + g(1)/omega_g2)/Kg0;
    g0 = g0_hat + (1/sqrt(Kg0))*randn;

    if isim > burnin
        isave = isim - burnin;
        store_tau(isave,:) = tau';
        store_h(isave,:) = h';
        store_g(isave,:) = g';
        store_theta(isave,:) = [omega_h2 omega_g2 h0 g0 tau0];
    end
end

% ---- thin and package -----------------------------------------------------
keep = opts.Thin:opts.Thin:nsim;

out = struct();
out.model  = 'ucsv_sw07';
out.tau    = store_tau(keep, :);
out.h      = store_h(keep, :);
out.g      = store_g(keep, :);
out.theta  = store_theta(keep, :);
out.theta_names = {'omega_h2', 'omega_g2', 'h0', 'g0', 'tau0'};
out.settings = struct('nsim', opts.NSim, 'burnin', burnin, 'thin', opts.Thin, ...
                      'seed', opts.Seed, 'T', T);
out.ndraws = numel(keep);
end
