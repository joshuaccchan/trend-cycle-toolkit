function out = ucur_break2(y, breaks, opts)
% uc.models.ucur_break2 - output gap, correlated trend and cycle, two breaks.
%
%   out = uc.models.ucur_break2(y, [105 241])
%   out = uc.models.ucur_break2(y, breaks, 'NSim', 110000, 'Burnin', 10000)
%
% The two-break model of Grant and Chan (2017), "A Bayesian Model Comparison for
% Trend-Cycle Decompositions of Output", Journal of Money, Credit and Banking,
% 49(2-3), 525-552 - model 6 of the eight that package compares. The trend and
% cycle innovations are correlated, and trend output growth takes a different
% constant value in each of the three regimes the breaks define, so its trend
% growth is a step function where uc_2m's varies smoothly.
%
% y is 100*log of real output. breaks is a two-element vector of ROW INDICES into
% y, in increasing order, which is what the sampler needs; resolve them from
% calendar quarters with estimates/resolve_break_dates.m. 105 and 241 are 1973Q1
% and 2007Q1 only while the sample starts at 1947Q1.
%
% OPTIONS
%   'NSim'    TOTAL sweeps, burn-in included   (default 110000)
%   'Burnin'  sweeps discarded                 (default  10000)
%   'Thin'    keep every Thin-th retained draw (default 10)
%   'Seed'    rng seed                         (default 1)
%
% As in uc_2m, this package's own nsims is the RETAINED count.
%
% From output_gap_code.zip/UCUR_break2.m.
%
% The body assigns a variable named `uc`, which shadows the uc package for the
% rest of the scope. This model calls no helper.

arguments
    y (:,1) double
    breaks (1,2) double
    opts.NSim (1,1) double = 110000
    opts.Burnin (1,1) double = 10000
    opts.Thin (1,1) double = 10
    opts.Seed (1,1) double = 1
end

T = numel(y);
burnin = opts.Burnin;
nsims = opts.NSim - burnin;
t0 = breaks(1);
t1 = breaks(2);

if nsims <= 0
    error('uc:models:badSettings', ...
        'NSim (%d) must exceed Burnin (%d).', opts.NSim, burnin);
end
if ~(t0 > 1 && t0 < t1 && t1 < T)
    error('uc:models:badBreaks', ...
        ['breaks must satisfy 1 < t0 < t1 < T. Got t0 = %g, t1 = %g, T = %d, ' ...
         'which would leave a regime empty.'], t0, t1, T);
end
if any(mod(breaks, 1) ~= 0)
    error('uc:models:badBreaks', ...
        'breaks are row indices and must be whole numbers. Got [%g %g].', t0, t1);
end

rng(opts.Seed, 'threefry');

%% prior
mu0 = .75; Vmu = 1^2;
tau00 = 750; Vtau0 = 100;
phi0 = [1.3 -.7]'; invVphi = speye(2);
sigc2_ub = 3;
sigtau2_ub = 3;
pri_sigc2 = @(x) log(1/sigc2_ub);
pri_sigtau2 = @(x) log(1/sigtau2_ub);
pri_rho = @(x) log(1/2);
R = 50000;
count = 0;
tempphi = repmat(phi0',R,1) + (chol(invVphi\speye(2),'lower')*randn(2,R))';
for i=1:R
    phic = tempphi(i,:)';
    if sum(phic) < .99 && phic(2) - phic(1) < .99 && phic(2) > -.99
        count = count+1;
    end    
end
phi_const = 1/(count/R);
prior = @(m,ph,sy,st,r,ta0) -3/2*log(2*pi*Vmu) -.5*sum((m-mu0).^2)/Vmu ...
    -log(2*pi)+.5*log(det(invVphi))+log(phi_const)-.5*(ph-phi0)'*invVphi*(ph-phi0)...
    + pri_sigc2(sy) + pri_sigtau2(st) + pri_rho(r) ...    
    -.5*log(2*pi*Vtau0) - .5*(ta0-tau00)^2/Vtau0;


% initialize the Markov chain
mu = [.9 .8 .4]';
phi = [1.34 -.7]';
H = speye(T) - sparse(2:T,1:(T-1),ones(1,T-1),T,T);
HH = H'*H;
Hphi = speye(T) - phi(1)*sparse(2:T,1:(T-1),ones(1,T-1),T,T) + ...
    - phi(2)*sparse(3:T,1:(T-2),ones(1,T-2),T,T);
tau0 = y(1);
sigc2 = .5;
sigtau2 = 1.5;
rho = -.9;
ngrid = 500;

%% compute a few things
Xbeta = [[1;sparse(T-1,1)] ones(T,1)];
XbetaXbeta = Xbeta'*Xbeta;
d0 = ((1:T)'<t0);
d1 = ((1:T)'>=t0)&((1:T)'<t1);
d2 = ((1:T)'>=t1);

%% initialize for storeage
store_theta = zeros(nsims,9); % [mu, phi, sigc2, sigtau2, rho, tau0]
store_tau = zeros(nsims,T); 
countphi = 0;

% [uc] The published line here was
%     rand('state', sum(100*clock) ); randn('state', sum(200*clock) );
% The stream is set once at the top of this function from opts.Seed instead.
    
for isim = 1:nsims+burnin
     
    %% sample tau  
    alp = H\(mu(1)*d0 + mu(2)*d1 + mu(3)*d2 + [tau0;sparse(T-1,1)]);
    a = -rho*sqrt(sigc2/sigtau2)*(H*alp);
    B = Hphi + rho*sqrt(sigc2/sigtau2)*H;
    tmpc = 1/((1-rho^2)*sigc2);
    Ktau = HH/sigtau2 + tmpc*(B'*B);
    tauhat = Ktau\(HH*alp/sigtau2 + tmpc*B'*(Hphi*y-a));
    tau = tauhat + chol(Ktau,'lower')'\randn(T,1);

    %% sample phi
    e = y-tau;
    Xphi = [[0;e(1:T-1)] [0;0;e(1:T-2)]];
    tmpc = 1/((1-rho^2)*sigc2);
    Kphi = invVphi + tmpc*(Xphi'*Xphi);
    phihat = Kphi\(invVphi*phi0 ... 
        + tmpc*Xphi'*(e-rho*sqrt(sigc2/sigtau2)*H*(tau-alp)));
    flag = 0; count = 0;
    while flag == 0 && count < 100
        phic = phihat + chol(Kphi,'lower')'\randn(2,1);
        if sum(phic) < .99 && phic(2) - phic(1) < .99 && phic(2) > -.99
            phi = phic;
            flag = 1;
            countphi = countphi + 1;
        end
        count = count + 1;
    end
    Hphi = speye(T) - phi(1)*sparse(2:T,1:(T-1),ones(1,T-1),T,T) + ...
        - phi(2)*sparse(3:T,1:(T-2),ones(1,T-2),T,T);    
         
    %% sample sigc2
    u = [Hphi*(y-tau) (tau-[tau0; tau(1:end-1)])-mu(1)*d0-mu(2)*d1-mu(3)*d2];
    c1 = sum(u(:,1).^2);
    c2 = u(:,1)'*u(:,2); 
    c3 = sum(u(:,2).^2);
    gy = @(x) -T/2*log(x) - 1./(2*(1-rho^2)*x).*(c1-2*rho*sqrt(x/sigtau2)*c2...
        + rho^2*x/sigtau2*c3);
    sigc2grid = linspace(rand/100,sigc2_ub-rand/100,ngrid);
    logpsigc2 = gy(sigc2grid) + pri_sigc2(sigc2grid);    
    psigc2 = exp(logpsigc2-max(logpsigc2));
    psigc2 = psigc2/sum(psigc2);
    cumsumy = cumsum(psigc2);
    sigc2 = sigc2grid(find(rand<cumsumy, 1 ));
    
    %% sample sigtau2    
    gtau = @(x) -T/2*log(x) - c3./(2*x) ...
        - 1/(2*(1-rho^2)*sigc2)*(c1-2*rho*sqrt(sigc2./x)*c2 + rho^2*sigc2./x*c3);
    sigtau2grid = linspace(+rand/100,sigtau2_ub-rand/100,ngrid);
    logpsigtau2 = gtau(sigtau2grid) + pri_sigtau2(sigtau2grid);
    psigtau2 = exp(logpsigtau2-max(logpsigtau2));
    psigtau2 = psigtau2/sum(psigtau2);
    cumsumtau = cumsum(psigtau2);
    sigtau2 = sigtau2grid(find(rand<cumsumtau, 1 ));
    
    %% sample rho    
    grho = @(x) -T/2*log(1-x.^2) + ...
        - 1./(2*sigc2*(1-x.^2)).*(c1-2*x*sqrt(sigc2/sigtau2)*c2 ...
        + x.^2*sigc2/sigtau2*c3);
    rhogrid = linspace(-.98-rand/100,.98+rand/100,ngrid);
    logprho = pri_rho(rhogrid) + grho(rhogrid);
    prho = exp(logprho-max(logprho));
    prho = prho/sum(prho);
    cumsumrho = cumsum(prho);
    rho = rhogrid(find(rand<cumsumrho, 1)); 
    
    %% sample mu and tau0
    uc = Hphi*(y-tau);
    Xdel = [ones(T,1) H\d0 H\d1 H\d2]; 
    Kdel = diag([1/Vtau0  1/Vmu 1/Vmu 1/Vmu]) + Xdel'*HH*Xdel/((1-rho^2)*sigtau2);
    delhat = Kdel\([tau00/Vtau0; mu0/Vmu; mu0/Vmu; mu0/Vmu] + 1/((1-rho^2)*sigtau2)*Xdel'*HH*...
        (tau - rho*sqrt(sigtau2/sigc2)*(H\uc)));
    del = delhat + chol(Kdel,'lower')'\randn(4,1);
    tau0 = del(1);
    mu = del(2:end);    

    if ( mod( isim, 5000 ) ==0 )
    end     
    
    if isim > burnin
        isave = isim - burnin;
        store_tau(isave,:) = tau';
        store_theta(isave,:) = [mu' phi' sigc2 sigtau2 rho tau0];
    end    
end

% ---- thin and package -----------------------------------------------------
keep = opts.Thin:opts.Thin:nsims;

out = struct();
out.model  = 'ucur_break2';
out.tau    = store_tau(keep, :);
out.gap    = y(:)' - store_tau(keep, :);
out.theta  = store_theta(keep, :);
out.theta_names = {'mu1', 'mu2', 'mu3', 'phi1', 'phi2', 'sigc2', 'sigtau2', ...
                   'rho', 'tau0'};
out.accept = struct('phi', countphi / (nsims + burnin));   % [uc]
out.breaks = breaks;
out.settings = struct('nsim', opts.NSim, 'burnin', burnin, 'thin', opts.Thin, ...
                      'seed', opts.Seed, 'T', T, 'breaks', breaks);
out.ndraws = numel(keep);
end
