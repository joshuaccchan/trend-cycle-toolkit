function out = uc_ma(y, opts)
% uc.models.uc_ma - trend inflation with moving average errors and SV.
%
%   out = uc.models.uc_ma(y)
%   out = uc.models.uc_ma(y, 'NSim', 11000, 'Burnin', 1000)
%
% The UC-MA model of Chan, J.C.C. (2013), "Moving Average Stochastic Volatility
% Models with Application to Inflation Forecast", Journal of Econometrics, 176(2),
% 162-172:
%
%   y_t   = tau_t + u_t + psi u_{t-1},   u_t ~ N(0, exp(h_t)),   |psi| < 1
%   tau_t = tau_{t-1} + N(0, sigtau2)
%   h_t   = muh + phih (h_{t-1} - muh) + N(0, sigh2),   |phih| < 1
%
% y is annualized percent inflation from uc.data.annualized_log_diff.
%
% Returns a struct: thinned draws of tau and h, the parameters muh, phih, sigh2,
% sigtau2 and psi, the acceptance rates of the psi and phih steps, and the settings
% used.
%
% Requires the Optimization Toolbox, for the fminsearch and fminunc in the psi step.
%
% OPTIONS
%   'NSim'    TOTAL sweeps, burn-in included   (default 11000)
%   'Burnin'  sweeps discarded                 (default  1000)
%   'Thin'    keep every Thin-th retained draw (default 10)
%   'Seed'    rng seed                         (default 1)
%
% Lines that differ from the published code are marked [uc].

arguments
    y (:,1) double
    opts.NSim (1,1) double = 11000
    opts.Burnin (1,1) double = 1000
    opts.Thin (1,1) double = 10
    opts.Seed (1,1) double = 1
end

T = numel(y);                          % [uc] main_UCMA.m reads y from USCPI_Q.csv
nloop = opts.NSim;                     % [uc] main_UCMA.m: nloop = 11000;
burnin = opts.Burnin;                  % [uc] main_UCMA.m: burnin = 1000;
options = optimset('Display', 'off');  % [uc] set in main_UCMA.m

if nloop <= burnin
    error('uc:models:badSettings', ...
        'NSim (%d) must exceed Burnin (%d).', opts.NSim, burnin);
end
if T < 20
    error('uc:models:tooShort', ...
        'the sample has %d observations, which is too few for this model.', T);
end
if isempty(ver('optim'))
    error('uc:models:noOptim', ...
        'this model needs the Optimization Toolbox: its psi step calls fminunc.');
end

rng(opts.Seed, 'threefry');

%% prior
tau0 = 0; invVtau = 1/5;
phih0 = .9; invVphih = 1;
muh0 = 0; invVmuh = 1/5;
invVpsi = 1; 
nutau = 10; Stau = .02*(nutau-1);
nuh = 10; Sh = .05*(nuh-1);

% initialize the Markov chain
sigtau2 = .05;
sigh2 = .05;
phih = .9;
muh = 1;
invsigtau2 = 1/sigtau2;
invDpsic = .01;
h = log(var(y)*.8)*ones(T,1);
H = speye(T) - sparse(2:T,1:(T-1),ones(1,T-1),T,T);
psi = 0;
psihat = psi; 
Hpsi = speye(T) + sparse(2:T,1:(T-1),psi*ones(1,T-1),T,T); 
countpsi = 0;
countphih = 0;

% initialize for storage
stheta = zeros(nloop - burnin,4); % [muh phih sigh2 sigtau2]
spsi = zeros(nloop - burnin,1); 
stau = zeros(nloop - burnin,T); 
sh = zeros(nloop - burnin,T);

%% compute a few things outside the loop
newnutau = (T-1)/2 + nutau;
newnuh = T/2 + nuh;
psipri = @(x) -log(normpdf(x,0,sqrt(1/invVpsi))/(normcdf(sqrt(invVpsi))-normcdf(-sqrt(invVpsi))));

% [uc] The published line here was
%     rand('state', sum(100*clock) ); randn('state', sum(200*clock) );
% which seeds from the clock and selects MATLAB's legacy generators. The stream is
% set once at the top of this function instead, from opts.Seed.

for loop = 1:nloop

    %% sample tau    
    invS_tau = sparse(1:T,1:T,[invVtau invsigtau2*ones(1,T-1)],T,T);
    invOmega_tau = H'*invS_tau*H;  
    invS_y = sparse(1:T,1:T,exp(-h));
    invD_tautilde = invS_y + Hpsi'*invOmega_tau*Hpsi;
    C_tautilde = chol(invD_tautilde,'lower');
    tauhat = C_tautilde'\(C_tautilde\(invS_y*(Hpsi\y)));
    tautilde = tauhat + C_tautilde'\randn(T,1);
    tau = Hpsi*tautilde; 
    
    %% sample h
    Ystar = log((Hpsi\(y-tau)).^2 + .0001);
    h = uc.sv.ksc_ar1(Ystar,h,phih,sigh2,muh);
   
    %% sample sigtau2
    newStau = Stau + sum((tau(2:end)-tau(1:end-1)).^2)/2;
    invsigtau2 = gamrnd(newnutau, 1/newStau);
    sigtau2 = 1/invsigtau2;   
    
    %% sample sigh2
    newSh = Sh + sum([(h(1)-muh)*sqrt(1-phih^2); h(2:end)-phih*h(1:end-1)-muh*(1-phih)].^2)/2;
    invsigh2 = gamrnd(newnuh, 1/newSh);
    sigh2 = 1/invsigh2;
    
    %% sample phih
    Xphih = h(1:end-1)-muh;
    yphih = h(2:end) - muh;
    Dphih = 1/(invVphih + Xphih'*Xphih/sigh2);
    phihhat = Dphih*(invVphih*phih0 + Xphih'*yphih/sigh2);
    phihc = phihhat + sqrt(Dphih)*randn;
    g = @(x) -.5*log(sigh2./(1-x.^2))-.5*(1-x.^2)/sigh2*(h(1)-muh)^2;
    if abs(phihc)<.9999
        alp = exp(g(phihc)-g(phih));
        if alp>rand
            phih = phihc;
            countphih = countphih+1;
        end
    end 
    
    %% sample muh    
    Dmuh = 1/(invVmuh + ((T-1)*(1-phih)^2 + (1-phih^2))/sigh2);
    muhhat = Dmuh*(invVmuh*muh0 + (1-phih^2)/sigh2*h(1) + (1-phih)/sigh2*sum(h(2:end)-phih*h(1:end-1)));
    muh = muhhat + sqrt(Dmuh)*randn;    
     
    %% sample psi
    fpsi = @(x) uc.util.nllike_ma1_sv(x,y-tau,h) + psipri(x);
    [psi flag psihat invDpsic] = uc.util.sample_psi(psi,fpsi,loop,invDpsic,options);
    Hpsi = speye(T) + sparse(2:T,1:(T-1),psi*ones(1,T-1),T,T); 
    countpsi = countpsi + flag;
    
    if loop>burnin
        i = loop-burnin;
        stau(i,:) = tau';
        spsi(i,:) = psi;
        sh(i,:) = h'; 
        stheta(i,:) = [muh phih sigh2 sigtau2];
    end    
end

% ---- thin and package -----------------------------------------------------
% [uc] The published script summarizes and plots at this point. Here the retained
% draws are thinned and returned, and every published summary is computed downstream.
keep = opts.Thin:opts.Thin:(nloop - burnin);

out = struct();
out.model    = 'uc_ma';
out.tau      = stau(keep, :);
out.h        = sh(keep, :);
out.theta    = [stheta(keep, :) spsi(keep, :)];
out.theta_names = {'muh', 'phih', 'sigh2', 'sigtau2', 'psi'};
out.accept   = struct('psi', countpsi / nloop, 'phih', countphih / nloop);
out.settings = struct('nsim', opts.NSim, 'burnin', burnin, 'thin', opts.Thin, ...
                      'seed', opts.Seed, 'T', T);
out.ndraws   = numel(keep);
end
