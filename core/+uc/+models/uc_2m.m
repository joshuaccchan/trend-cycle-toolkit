function out = uc_2m(y, opts)
% uc.models.uc_2m - output gap and trend growth, second-order Markov trend.
%
%   out = uc.models.uc_2m(y)
%   out = uc.models.uc_2m(y, 'NSim', 110000, 'Burnin', 10000)
%
% The model of Grant and Chan (2017), "Reconciling Output Gaps: Unobserved
% Components Model and Hodrick-Prescott Filter", Journal of Economic Dynamics and
% Control, 75, 114-121. The trend follows a second-order Markov process, which is
% what the Hodrick-Prescott filter implies, and the cycle is allowed to be serially
% correlated, which the filter does not allow.
%
% y is 100*log of real output, from uc.data.fetch_fred('GDPC1') passed through the
% log transform. Univariate: nothing else enters. Two of the three published series
% come out of one set of draws:
%
%   out.gap    y_t - tau_t, the output gap
%   out.mu     4*(tau_t - tau_{t-1}), annualized trend output growth
%
% OPTIONS
%   'NSim'    TOTAL sweeps, burn-in included   (default 110000)
%   'Burnin'  sweeps discarded                 (default  10000)
%   'Thin'    keep every Thin-th retained draw (default 10)
%   'Seed'    rng seed                         (default 1)
%
% NSim is the TOTAL everywhere in this repository, which the published drivers do
% not agree on: this package's nsims = 100000 is the RETAINED count and it loops
% 1:nsims+burnin, while ARtrend_bound.m's nloop = 35000 is the total. The published
% settings for this model are NSim = 110000 with Burnin = 10000.
%
% The body is UCUR_2M.m unchanged except that data and settings arrive as arguments
% instead of from main_script.m, the legacy rand('state',...) seed becomes
% rng(opts.Seed,'threefry'), the marginal likelihood is out, and there is no
% plotting, printing or timing. Dropping the ML removes 50000 importance
% replications, the expensive part of the published run.
%
% The prior normalization is kept: the 50000 draws below estimate phi_const, the
% mass of the stationarity region, which only the marginal likelihood ever reads.
% Dropping it would use 100000 fewer normals and change every draw that follows.
%
% Verified 2026-09-09 against the published script on the data
% output_gap_2M_code.zip ships, 600 sweeps under seed 7: bitwise identical draws,
% and the gap matches y - tau exactly.

arguments
    y (:,1) double
    opts.NSim (1,1) double = 110000
    opts.Burnin (1,1) double = 10000
    opts.Thin (1,1) double = 10
    opts.Seed (1,1) double = 1
end

T = numel(y);
burnin = opts.Burnin;
nsims = opts.NSim - burnin;          % [uc] this package's nsims is the retained count

if nsims <= 0
    error('uc:models:badSettings', ...
        'NSim (%d) must exceed Burnin (%d).', opts.NSim, burnin);
end
if T < 20
    error('uc:models:tooShort', ...
        'the sample has %d observations, which is too few for this model.', T);
end

rng(opts.Seed, 'threefry');

%% prior
tau00 = 750; Vtau0 = 100;
phi0 = [1.3 -.7]'; invVphi = speye(2);
sigc2_ub = 3;
sigtau2_ub = .01;
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
prior = @(ph,sy,st,r,t0) -log(2*pi)+.5*log(det(invVphi))+log(phi_const)-.5*(ph-phi0)'*invVphi*(ph-phi0)...
    + pri_sigc2(sy) + pri_sigtau2(st) + pri_rho(r) ...    
    -log(2*pi*Vtau0) - .5*sum((t0-tau00).^2)/Vtau0;


% initialize the Markov chain
phi = [1.34 -.7]';
H2 = speye(T) - 2*sparse(2:T,1:(T-1),ones(1,T-1),T,T) ...
    + sparse(3:T,1:(T-2),ones(1,T-2),T,T);
H2H2 = H2'*H2;
Hphi = speye(T) - phi(1)*sparse(2:T,1:(T-1),ones(1,T-1),T,T) + ...
    - phi(2)*sparse(3:T,1:(T-2),ones(1,T-2),T,T);
tau0 = [y(1) y(1)]';
sigc2 = .5;
sigtau2 = .001;
rho = -.9;
ngrid = 500;
Xdel = [(2:T+1)' -(1:T)'];
 
%% initialize for storeage
store_theta = zeros(nsims,7); % [phi, sigc2, sigtau2, rho, tau0]
store_tau = zeros(nsims,T); 
store_mu = zeros(nsims,T-1); 
countphi = 0;
% [uc] The published line here was
%     rand('state', sum(100*clock) ); randn('state', sum(200*clock) );
% Clock-seeded, and the 'state' form selects a legacy generator. The stream
% is set once at the top of this function from opts.Seed instead.
    
for isim = 1:nsims+burnin
     
    %% sample tau  
    alp = H2\[2*tau0(1)-tau0(2);-tau0(1);sparse(T-2,1)];
    a = -rho*sqrt(sigc2/sigtau2)*(H2*alp);
    B = Hphi + rho*sqrt(sigc2/sigtau2)*H2;
    tmpc = 1/((1-rho^2)*sigc2);
    Ktau = H2H2/sigtau2 + tmpc*(B'*B);
    tauhat = Ktau\(H2H2*alp/sigtau2 + tmpc*B'*(Hphi*y-a));
    tau = tauhat + chol(Ktau,'lower')'\randn(T,1);

    %% sample phi
    c = y-tau;
    Xphi = [[0;c(1:T-1)] [0;0;c(1:T-2)]];
    tmpc = 1/((1-rho^2)*sigc2);
    Kphi = invVphi + tmpc*(Xphi'*Xphi);
    phihat = Kphi\(invVphi*phi0 ... 
        + tmpc*Xphi'*(c-rho*sqrt(sigc2/sigtau2)*H2*(tau-alp)));
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
    u = [Hphi*(y-tau) H2*(tau-alp)];
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
    sigtau2grid = linspace(rand/10000,sigtau2_ub-rand/10000,ngrid);
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
    
    %% sample tau0
    uy = Hphi*(y-tau);   
    Kdel = diag([1/Vtau0  1/Vtau0]) + Xdel'*H2H2*Xdel/((1-rho^2)*sigtau2);
    delhat = Kdel\([tau00/Vtau0; tau00/Vtau0] + 1/((1-rho^2)*sigtau2)*Xdel'*H2H2*...
        (tau - rho*sqrt(sigtau2/sigc2)*(H2\uy)));
    del = delhat + chol(Kdel,'lower')'\randn(2,1);
    tau0 = del;

    if (mod(isim, 10000) == 0)
    end     
    
    if isim > burnin
        i = isim-burnin;
        store_tau(i,:) = tau';
        store_theta(i,:) = [phi' sigc2 sigtau2 rho tau0'];
        store_mu(i,:) = 4*(tau(2:end)-tau(1:end-1))';
    end    
end

% ---- thin and package -----------------------------------------------------
keep = opts.Thin:opts.Thin:nsims;

out = struct();
out.model  = 'uc_2m';
out.tau    = store_tau(keep, :);
out.gap    = y(:)' - store_tau(keep, :);   % c = y - tau, the published gap
out.mu     = store_mu(keep, :);            % 4*diff(tau), annualized trend growth
out.theta  = store_theta(keep, :);
out.theta_names = {'phi1', 'phi2', 'sigc2', 'sigtau2', 'rho', 'tau0_1', 'tau0_2'};
out.accept = struct('phi', countphi / (nsims + burnin));
out.settings = struct('nsim', opts.NSim, 'burnin', burnin, 'thin', opts.Thin, ...
                      'seed', opts.Seed, 'T', T);
out.ndraws = numel(keep);
end
