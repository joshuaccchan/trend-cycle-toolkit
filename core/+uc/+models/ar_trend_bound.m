function out = ar_trend_bound(y, y0, opts)
% uc.models.ar_trend_bound - trend inflation with a bounded trend and SV.
%
%   out = uc.models.ar_trend_bound(y, y0)
%   out = uc.models.ar_trend_bound(y, y0, 'NSim', 35000, 'Burnin', 5000)
%
% The model of Chan, Koop and Potter (2013), "A New Model of Trend Inflation",
% Journal of Business and Economic Statistics, 31(1), 94-106:
%
%   y_t   = tau_t + rho_t (tau_t - tau_{t-1}) + u_t,   u_t ~ N(0, exp(h_t))
%   tau_t = tau_{t-1} + v_t,        a < tau_t < b
%   rho_t                            0 < rho_t < rhob
%
% y is annualized percent inflation over the estimation sample and y0 the one
% presample observation the measurement equation needs, both from
% uc.data.annualized_log_diff. The bounds are in those same units, so inflation
% expressed as a proportion sits outside the trend's support and the sampler
% rejects forever without saying why.
%
% Returns a struct: thinned draws of tau, rho and h, the three state-innovation
% variances, acceptance counts, the seed, and the settings used.
%
% OPTIONS
%   'NSim'    total sweeps including burn-in   (default 35000, the published value)
%   'Burnin'  sweeps discarded                 (default  5000, the published value)
%   'Thin'    keep every Thin-th retained draw (default 10)
%   'Seed'    rng seed                         (default 1)
%   'Bounds'  [a b] on the trend               (default [0 5], the published value)
%   'RhoBound' upper bound on rho              (default 1, the published value)
%
% The body is ARtrend_bound.m from ARtrendbound.zip with the sampler untouched.
% Four things changed, each marked [uc] where it occurs: data and settings arrive
% as arguments, the clock seed becomes rng(opts.Seed,'threefry'), the chain is
% thinned on the way out, and the plotting, printing and timing are gone. Verified
% 2026-09-09 against the published script on the data that package ships, 600
% sweeps under seed 1: bitwise identical draws.
%
% The published sampler assigns a variable named `uc` in the tau block, shadowing
% the uc package for the rest of the scope. This model calls no helper.

arguments
    y (:,1) double
    y0 (1,1) double
    opts.NSim (1,1) double = 35000
    opts.Burnin (1,1) double = 5000
    opts.Thin (1,1) double = 10
    opts.Seed (1,1) double = 1
    opts.Bounds (1,2) double = [0 5]
    opts.RhoBound (1,1) double = 1
end

burnin = opts.Burnin;
nsims = opts.NSim - burnin;   % [uc] retained draws, as in the other models
T = numel(y);

if nsims <= 0
    error('uc:models:badSettings', ...
        'NSim (%d) must exceed Burnin (%d).', opts.NSim, burnin);
end
if T < 20
    error('uc:models:tooShort', ...
        'the sample has %d observations, which is too few to estimate this model.', T);
end

rng(opts.Seed, 'threefry');

%% prior
tau0 = 0; invVtau = 1/5;
invVrho = 1; 
invVh = 1/5;
nutau0 = 10; Stau0 = .02*(nutau0-1);
nurho0 = 10; Srho0 = .001*(nurho0-1);
nuh0 = 10; Sh0 = .05*(nuh0-1);
a = opts.Bounds(1); b = opts.Bounds(2);  % [uc] was: a = 0; b = 5;
rhob = opts.RhoBound;  % [uc] was: rhob = 1;

%% compute and define a few things
id1 = (1:T)';
id2 = (2:T)';
id3 = (1:T-1)';
Kh =  speye(T,T) - spdiags(ones(T-1,1),-1,T,T);
cH = zeros(2,2);
newnutau = (T-1)/2 + nutau0;
newnurho = (T-1)/2 + nurho0;
newnuh = (T-1)/2 + nuh0;

%% initialize for storage
store_sig = zeros(nsims,3);   % [uc] was zeros(nloop - burnin,3)
store_tau = zeros(nsims,T);   % [uc] was zeros(nloop - burnin,T)
store_rho = zeros(nsims,T);   % [uc] was zeros(nloop - burnin,T)
store_h = zeros(nsims,T);     % [uc] was zeros(nloop - burnin,T)
counttau = 0; counth = 0; countrho = 0; countsigrho = 0; countsigtau = 0;

%% initialize the Markov chain
sigtau = .01;
sigrho = .001;
sigh = .1;
h = log(var(y))*ones(T,1);
rho = max(abs(y)./max(y)-.1,.5);
expinvh = exp(-h);
S = sparse(1:T,1:T,[invVtau repmat(1/sigtau,1,T-1)],T,T);
Krho = speye(T) - sparse(2:T,1:(T-1),rho(2:T),T,T); 
mu0 = Krho\[rho(1)*y0; sparse(T-1,1)];
Sy = Krho'*sparse(id1,id1, expinvh,T,T)*Krho;
H =  Sy + Kh'*S*Kh;
cholH = chol(H,'lower');
taut = H\(Sy*(y-mu0));
taut = min(taut,b-.1);    taut = max(taut,a+.1);
flag = 0;
while flag == 0
    tau = taut + cholH'\randn(T,1);
    if  max(tau)<=b && min(tau)>=a
        flag = 1;
    end   
end
sqrtsigtau = sqrt(sigtau);
ystar = y - tau;
Sh = spdiags([invVh; 1/sigh*ones(T-1,1)],0,T,T);
KSKh = Kh'*Sh*Kh;    
s2 = (ystar-rho.*[y0; ystar(1:T-1)]).^2;
errh = 1; ht = h;
while errh> 10^(-3);
    expht = exp(ht);
    sexpht = s2./expht;
    fh = -.5 + .5*sexpht;
    Gh = .5*sexpht;
    Hh = KSKh + spdiags(Gh,0,T,T);
    newht = Hh\(fh+Gh.*ht);
    errh = max(abs(newht-ht));
    ht = newht;          
end 
h = ht + chol(Hh,'lower')'\randn(T,1);

%% MCMC starts here
% [uc] The published line here was
%     randn('seed',sum(clock*100)); rand('seed',sum(clock*1000));
% which seeds from the clock and selects MATLAB's pre-Mersenne generators.
% The stream is set once at the top of this function instead, from opts.Seed.

for loop = 1:nsims+burnin    % [uc] was 1:nloop, the same count re-based
  
    %% sample tau
    Krho = speye(T) - sparse(2:T,1:(T-1),rho(2:T),T,T); 
    mu0 = Krho\[rho(1)*y0; sparse(T-1,1)];
    expinvh = exp(-h);    
    S = sparse(1:T,1:T,[invVtau repmat(1/sigtau,1,T-1)],T,T);
    Sy = Krho'*sparse(id1,id1, expinvh,T,T)*Krho;
    H =  Sy + Kh'*S*Kh;
    taut = H\(Sy*(y-mu0));   %% expand around the mode of the linear model
    taut = min(taut,b-.05);    taut = max(taut,a+.05); 
    cholH = chol(H,'lower'); 
        % AR step
            % compute the constant c
    taustar = taut;    
    u = y-taustar-mu0; v = taut-taustar;
    logc =  -.5*u'*Sy*u -.5*(taustar(1)-tau0)^2*invVtau + ...
        -.5*sum((taustar(2:end)- taustar(1:end-1)).^2)/sigtau + ...
        -sum(log(normcdf((b-taustar(1:end-1))/sqrtsigtau) + ...
        -normcdf((a-taustar(1:end-1))/sqrtsigtau))) + .5*v'*H*v + log(3);
    flag = 0; count = 0;
    while flag == 0 && count < 1000 % give up when count >= 1000
        tauc = taut + cholH'\randn(T,1);
        if  max(tauc) <= b - .01 && min(tauc) >= a + .01
            vc = tauc-taut; uc = y-tauc-mu0;
            alpARc =  -.5*uc'*Sy*uc -.5*(tauc(1)-tau0)^2*invVtau +...
                -.5*sum((tauc(2:end)- tauc(1:end-1)).^2)/sigtau + ...
                -sum(log(normcdf((b-tauc(1:end-1))/sqrtsigtau) + ...
                -normcdf((a-tauc(1:end-1))/sqrtsigtau))) + .5*vc'*H*vc - logc;            
            if alpARc > log(rand)
                flag = 1;
            end
        end
        count = count + 1;
    end      
    if flag == 1;
        v = tau-taut;   u = y-tau-mu0;
        alpAR =  -.5*u'*Sy*u -.5*(tau(1)-tau0)^2*invVtau + ...
            -.5*sum((tau(2:end)- tau(1:end-1)).^2)/sigtau + ...
            - sum(log(normcdf((b-tau(1:end-1))/sqrtsigtau) + ...
            -normcdf((a-tau(1:end-1))/sqrtsigtau))) + .5*v'*H*v - logc;
        if alpAR < 0 
            alpMH = 1;
        elseif alpARc < 0
            alpMH = - alpAR;
        else
            alpMH = alpARc - alpAR;
        end        
        if alpMH > log(rand)
            tau = tauc;
            counttau = counttau + 1;
        end     
    end
    
    %% sample rho
    ystar = y - tau;
    XinvSy = [y0; ystar(id3)].*expinvh;
    XinvSyX = XinvSy.*[y0; ystar(id3)]; 
    Hrho = sparse(id1,id1,XinvSyX) + Kh'*sparse(id1,id1,[invVrho repmat(1/sigrho,1,T-1)])*Kh;
    rhot = Hrho\(XinvSy.*ystar);    
    rhot = min(rhot,rhob-.05);    rhot = max(rhot,.05);
    cholHrho = chol(Hrho,'lower'); 
        % AR step
            % compute the constant c
    sqrtsigrho = sqrt(sigrho);
    rhostar = rhot;
    u = ystar - [y0; ystar(id3)].*rhostar; v = rhot-rhostar;
    logc = -.5*(u.*expinvh)'*u -.5*rhostar(1)^2*invVrho + ...
        -.5*sum((rhostar(2:end)-rhostar(1:end-1)).^2)/sigrho + ...
        -sum(log(normcdf((rhob-rhostar(1:end-1))/sqrtsigrho) + ...
        -normcdf(-rhostar(1:end-1)/sqrtsigrho))) + .5*v'*Hrho*v + log(3);    
    flag = 0; count = 0;
    while flag == 0 && count < 1000 % give up when count >= 1000
        rhoc = rhot + cholHrho'\randn(T,1);
        if  max(rhoc)<= rhob -.005 && min(rhoc)>= .005
            vc = rhoc-rhot; uc =  ystar - [y0; ystar(id3)].*rhoc;
            alpARc =  -.5*(uc.*expinvh)'*uc -.5*rhoc(1)^2*invVrho +...
                -.5*sum((rhoc(2:end)- rhoc(1:end-1)).^2)/sigrho + ...
                -sum(log(normcdf((rhob-rhoc(1:end-1))/sqrtsigrho) + ...
                -normcdf(-rhoc(1:end-1)/sqrtsigrho))) + .5*vc'*Hrho*vc - logc;            
            if alpARc > log(rand)
                flag = 1;
            end
        end
        count = count + 1;
    end      
    if flag == 1;
        v = rho-rhot;   u = ystar - [y0; ystar(id3)].*rho;
        alpAR = -.5*(u.*expinvh)'*u -.5*rho(1)^2*invVrho +...
                -.5*sum((rho(2:end)- rho(1:end-1)).^2)/sigrho + ...
                -sum(log(normcdf((rhob-rho(1:end-1))/sqrtsigrho) + ...
                -normcdf(-rho(1:end-1)/sqrtsigrho))) + .5*v'*Hrho*v - logc; 
        if alpAR < 0 
            alpMH = 1;
        elseif alpARc < 0
            alpMH = - alpAR;
        else
            alpMH = alpARc - alpAR;
        end        
        if alpMH > log(rand)
            rho = rhoc;
            countrho = countrho + 1;
        end
    end
    
    %% sample h    
    Sh = spdiags([invVh; 1/sigh*ones(T-1,1)],0,T,T);
    KSKh = Kh'*Sh*Kh;    
    s2 = (ystar-rho.*[y0; ystar(1:T-1)]).^2;
    errh = 1; ht = h;
    while errh> 10^(-3);
        expht = exp(ht);
        sexpht = s2./expht;
        fh = -.5 + .5*sexpht;
        Gh = .5*sexpht;
        Hh = KSKh + spdiags(Gh,0,T,T);
        newht = Hh\(fh+Gh.*ht);
        errh = max(abs(newht-ht));
        ht = newht;          
    end 
    cholHh = chol(Hh,'lower');    
    % AR-step:     
    hstar = ht;
    logc = -.5*hstar'*KSKh*hstar -.5*sum(hstar) - .5*exp(-hstar)'*s2 + log(3);
    flag = 0;
    while flag == 0
        hc = ht + cholHh'\randn(T,1);
        vhc = hc-ht;        
        alpARc = -.5*hc'*KSKh*hc -.5*sum(hc) -.5*exp(-hc)'*s2 + ...
            + .5*vhc'*Hh*vhc - logc;            
        if alpARc > log(rand)
            flag = 1;
        end
    end        
    % MH-step
    vh = h-ht;
    alpAR = -.5*h'*KSKh*h -.5*sum(h) -.5*exp(-h)'*s2 + .5*vh'*Hh*vh - logc;
    if alpAR < 0 
        alpMH = 1;
    elseif alpARc < 0
        alpMH = - alpAR;
    else
        alpMH = alpARc - alpAR;
    end        
    if alpMH > log(rand)
        h = hc;
        counth = counth + 1;
    end 
    
    %% sample sigtau    
    errsigtau = tau(2:end) - tau(1:end-1);
    newStau = Stau0 + sum(errsigtau.^2)/2;
    sigtauc = 1/gamrnd(newnutau, 1./newStau);    
    sqrtsigtauc = sqrt(sigtauc);
    sqrtsigtau = sqrt(sigtau);
    siga = a - tau(1:end-1); 
    sigb = b - tau(1:end-1);    
    alpMH = -sum(log(normcdf(sigb/sqrtsigtauc)-normcdf(siga/sqrtsigtauc))) + ...
        sum(log(normcdf(sigb/sqrtsigtau)-normcdf(siga/sqrtsigtau)));
    if alpMH > log(rand)
        sigtau = sigtauc;         
        sqrtsigtau = sqrtsigtauc;
        countsigtau = countsigtau + 1;
    end
    
    %% sample sigrho    
    errsigrho = rho(2:end) - rho(1:end-1);
    newSrho = Srho0 + sum(errsigrho.^2)/2;
    sigrhoc = 1/gamrnd(newnurho, 1./newSrho);    
    sqrtsigrhoc = sqrt(sigrhoc);
    sqrtsigrho = sqrt(sigrho);    
    alpMH = -sum(log(normcdf((1-rho(id1))/sqrtsigrhoc)-normcdf(-rho(id1)/sqrtsigrhoc))) + ...
        sum(log(normcdf((1-rho(id1))/sqrtsigrho)-normcdf(-rho(id1)/sqrtsigrho)));
    if alpMH > log(rand)
        sigrho = sigrhoc;         
        sqrtsigrho = sqrtsigrhoc;
        countsigrho = countsigrho + 1;
    end
    
    %% sample sigh
    errh = h(2:end) - h(1:end-1);
    newS = Sh0 + sum(errh.^2)/2;
    sigh = 1/gamrnd(newnuh,1./newS);    
        
    if loop>burnin
        i = loop-burnin;
        store_tau(i,:) = tau';
        store_rho(i,:) = rho';
        store_h(i,:) = h'; 
        store_sig(i,:) = [sigtau sigrho sigh];         
    end
    
    if ( mod( loop, 2000 ) ==0 )
    end 
    
end

% ---- thin and package -----------------------------------------------------
% [uc] The published script plots at this point. Here the retained draws are
% thinned and returned; every summary a release publishes is computed downstream
% from these, so the model itself decides nothing about presentation.
keep = opts.Thin:opts.Thin:nsims;

out = struct();
out.model    = 'ar_trend_bound';
out.tau      = store_tau(keep, :);
out.rho      = store_rho(keep, :);
out.h        = store_h(keep, :);
out.sig      = store_sig(keep, :);
out.sig_names = {'sigtau', 'sigrho', 'sigh'};
ntot = nsims + burnin;
out.accept   = struct('tau', counttau / ntot, 'h', counth / ntot, ...
                      'rho', countrho / ntot, 'sigrho', countsigrho / ntot, ...
                      'sigtau', countsigtau / ntot);
out.settings = struct('nsim', opts.NSim, 'burnin', burnin, 'thin', opts.Thin, ...
                      'seed', opts.Seed, 'bounds', opts.Bounds, ...
                      'rhobound', opts.RhoBound, 'T', T);
out.ndraws   = numel(keep);
end
