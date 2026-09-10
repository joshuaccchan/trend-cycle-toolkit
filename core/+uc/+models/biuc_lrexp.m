function out = biuc_lrexp(infl, expect, opts)
% uc.models.biuc_lrexp - trend inflation with long-run inflation expectations.
%
%   out = uc.models.biuc_lrexp(infl, expect)
%   out = uc.models.biuc_lrexp(infl, expect, 'NSim', 31000, 'Burnin', 1000)
%
% Model M1 of Chan, J.C.C., Clark, T.E. and Koop, G. (2018), "A New Model of
% Inflation, Trend Inflation, and Long-Run Inflation Expectations", Journal of
% Money, Credit and Banking, 50(1), 5-53. Inflation and a survey measure of
% long-run expectations are modelled jointly, so the expectations series informs
% the trend directly.
%
% infl    annualized percent inflation, from uc.data.annualized_log_diff
% expect  long-run CPI inflation expectations, from uc.data.build_ptrcpi
%
% Both must be the same length and on the same quarterly axis, and the first
% observation of each is a presample value, as in the published driver, so the
% estimation sample is one quarter shorter than the input. PTRCPI begins in 1960Q1,
% which is where this model's sample starts; the other four run from 1947.
%
% Requires the Optimization Toolbox, for the fminunc in the psi block. It is the
% only one of the five models that does.
%
% OPTIONS
%   'NSim'    TOTAL sweeps, burn-in included   (default 31000)
%   'Burnin'  sweeps discarded                 (default  1000)
%   'Thin'    keep every Thin-th retained draw (default 10)
%   'Seed'    rng seed                         (default 1)
%   'Q'       MA order of the inflation error  (default 1, the published value)
%
% The published driver sets nsim = 30000 with burnin = 1000 and loops
% 1:nsim+burnin, so its nsim is the retained count and NSim here is 31000.
%
% The body is M1.m unchanged except that data and settings arrive as arguments, the
% clock seed becomes rng(opts.Seed,'threefry'), there is no plotting or timing, and
% the helper calls are repointed:
%
%   SURform     -> uc.util.surform
%   buildHpsi   -> uc.util.build_hpsi
%   llike_MAq   -> uc.util.llike_maq
%   SVRW        -> uc.sv.ksc_rw_h0_Vh
%   sample_b, sample_psi, sample_sig2  -> local functions at the bottom of this file
%
% Those three stay local because sample_sig2 and sample_psi are names unrelated
% packages use for different computations of the same arity.
%
% Verified 2026-09-10 against the published script on the data trend_IE_code.zip
% ships (cck1_data.xlsx, B54:B278 and C54:C278), 300 sweeps under seed 4: bitwise
% identical draws.
%
% The published body uses pi as a variable name, shadowing MATLAB's built-in pi for
% the rest of the scope. Nothing here reads the constant.

arguments
    infl (:,1) double
    expect (:,1) double
    opts.NSim (1,1) double = 31000
    opts.Burnin (1,1) double = 1000
    opts.Thin (1,1) double = 10
    opts.Seed (1,1) double = 1
    opts.Q (1,1) double = 1
end

if numel(infl) ~= numel(expect)
    error('uc:models:lengthMismatch', ...
        ['inflation has %d observations and expectations %d. They must be on the ' ...
         'same quarterly axis; align them with uc.data.align_by_date first.'], ...
        numel(infl), numel(expect));
end

burnin = opts.Burnin;
nsim = opts.NSim - burnin;
q = opts.Q;

pi0 = infl(1);   pi = infl(2:end);     % [uc] published: pi0 = data1(1,1); pi = data1(2:end,1)
z0 = expect(1);  z = expect(2:end);    % [uc] published: z0 = Einf(1); z = Einf(2:end)
T = numel(pi);

if nsim <= 0
    error('uc:models:badSettings', ...
        'NSim (%d) must exceed Burnin (%d).', opts.NSim, burnin);
end
if T < 20
    error('uc:models:tooShort', ...
        'the estimation sample has %d observations after the presample value.', T);
end
if isempty(ver('optim'))
    error('uc:models:noOptim', ...
        ['this model needs the Optimization Toolbox: its psi block calls fminunc. ' ...
         'It is the only one of the five that does.']);
end

rng(opts.Seed, 'threefry');

    % prior
Vpistar = 100;  % implicitly pistar0 = 0;
Vb = 100;       % implicitly b0 = 0;
psi0 = zeros(q,1); Vpsi = .25^2*speye(q);
mud0 = [0 1]'; Vmud = [.1^2 .1^2]';
rhod0 = [.95 .95]'; Vrhod = [.1^2 .1^2]';
nud0 = 5*ones(2,1); Sd0 = [.01 .001]'.*(nud0-1);
nub0 = 5; Sb0 = .001*(nub0-1);
nuw0 = 5; Sw0 = .01*(nuw0-1);
nuv0 = 5; Sv0 = .01*(nuv0-1);
nun0 = 5; Sn0 = .01*(nun0-1);
lamv0 = log(1); Vlamv = 100;
lamn0 = log(1); Vlamn = 100;
c_psi = 1/(normcdf((1-psi0)/sqrt(Vpsi))-normcdf((-1-psi0)/sqrt(Vpsi)));
lpsipri = @(x) log(c_psi) -.5*log(2*3.14159*Vpsi) -.5*(x-psi0).^2/Vpsi;

    % initialize for storage
store_theta = zeros(nsim,10+q); % [psi' mud' rhod' sigd2' sigb2 sigw2 phiv phin]
store_pistar = zeros(nsim,T); 
store_d = zeros(nsim,2*T);
store_b = zeros(nsim,T); 
store_lamv = zeros(nsim,T);
store_lamn = zeros(nsim,T);
countpsi = 0; countb = 0; countsigb2 = 0; countrhod = zeros(2,1);

    % initialize the Markov chain
sigd2 = .001*ones(2,1);
sigb2 = .01;
sigb = sqrt(sigb2);
sigw2 = .2;
phiv = .1;
phin = .1;
lamv = var(pi)/2*ones(T,1);
lamw = var(z)*ones(T,1);
invLamw = sparse(1:T,1:T,1./lamw);
lamn = var(pi)/2*ones(T,1);
mud = [0 1]';
rhod = [.98 .98]';
shortd = repmat(mud',T,1);
d = reshape(shortd',T*2,1);
b = .3 + .05*rand(T,1);
psi = zeros(q,1);
phihat = psi;
invDpsic = .0001*eye(q);
H =  speye(T) - sparse(2:T,1:(T-1),ones(1,T-1),T,T);
Hrhod =  speye(2*T) - sparse(2+1:T*2,1:(T-1)*2,repmat(rhod,T-1,1),2*T,2*T);
Hpsi = uc.util.build_hpsi(psi,T);
options = optimset('Display', 'off') ;
warning off all;

    % MCMC starts here
% [uc] the published line here seeded from the clock with
%     randn('seed',sum(clock*100)); rand('seed',sum(clock*1000));
% The stream is set once at the top of this function instead.

for isim = 1:nsim + burnin
  
        % sample pistar     
    Hb = speye(T) - sparse(2:T,1:(T-1),b(2:T),T,T); 
    alppi = Hb\[b(1)*pi0; sparse(T-1,1)];
    HbiLamvHb = Hb'*sparse(1:T,1:T,1./lamv)*Hb;       
    HiLamnH = H'*sparse(1:T,1:T,[1/(Vpistar*lamn(1)); 1./lamn(2:end)])*H;
    ztilde = Hpsi\(z-shortd(:,1));
    tmpXpi = Hpsi\sparse(1:T,1:T,shortd(:,2));
    Xtilde_pi = tmpXpi.*(abs(tmpXpi)>1e-6);
    Kpistar = HbiLamvHb + Xtilde_pi'*Xtilde_pi/sigw2 + HiLamnH;
    pistarhat = Kpistar\(HbiLamvHb*(pi-alppi) + Xtilde_pi'*ztilde/sigw2); % pi*_0 = 0
    pistar = pistarhat + chol(Kpistar,'lower')'\randn(T,1);
    
        % sample b
    [b,flag] = sample_b(b,pi,pistar,lamv,pi0,Vb,sigb2);
    countb = countb + flag;
    
        % sample d    
    Xd = uc.util.surform([ones(T,1) pistar]);     
    tmpXd = Hpsi\Xd;    
    Xtilde_d = tmpXd.*(abs(tmpXd)>1e-6);       
    HdiSigdHd = Hrhod'*sparse(1:2*T,1:2*T,[(1-rhod)./sigd2; repmat(1./sigd2,T-1,1)])*Hrhod;
    Kd = HdiSigdHd + Xtilde_d'*Xtilde_d/sigw2;
    deld = Hrhod\[mud; repmat((1-rhod).*mud,T-1,1)];
    CKd = chol(Kd,'lower');    
    dhat = CKd'\(CKd\(HdiSigdHd*deld + Xtilde_d'*(Hpsi\z)/sigw2));
    d = dhat + CKd'\randn(2*T,1); 
    shortd = reshape(d,2,T)';
    
        % sample psi    
    fpsi = @(x) -uc.util.llike_maq(x,z-Xd*d,sigw2) - lpsipri(x);
    [psi,flag,psihat,invDpsic] = sample_psi(psi,fpsi,isim,invDpsic,options);
    Hpsi = uc.util.build_hpsi(psi,T);    
    countpsi = countpsi + flag; 
    
        % sample mud
    for i=1:2
        Dmud = 1/(1/Vmud(i) + ((T-1)*(1-rhod(i))^2 + (1-rhod(i)^2))/sigd2(i));
        mudhat = Dmud*(mud0(i)/Vmud(i) + (1-rhod(i)^2)/sigd2(i)*shortd(1,i) ...
            + (1-rhod(i))/sigd2(i)*sum(shortd(2:end,i)-rhod(i)*shortd(1:end-1,i)));
        mud(i) = mudhat + sqrt(Dmud)*randn;
    end
    
    %% sample rhod
    for i=1:2
        Xrhod = shortd(1:end-1,i)-mud(i);
        yrhod = shortd(2:end,i) - mud(i);
        Drhod = 1/(1/Vrhod(i) + Xrhod'*Xrhod/sigd2(i));
        rhodhat = Drhod*(rhod0(i)/Vrhod(i) + Xrhod'*yrhod/sigd2(i));  
        rhodc = rhodhat + sqrt(Drhod)*randn;
        g = @(x) -.5*log(sigd2(i)./(1-x.^2)) ...
            -.5*(1-x.^2)/sigd2(i)*(shortd(1,i)-mud(i))^2;
        if abs(rhodc) < .98
            alpMH = exp(g(rhodc)-g(rhod(i)));
            if alpMH>rand
                rhod(i) = rhodc;
                countrhod(i) = countrhod(i)+1;                
             end
        end    
    end
    Hrhod =  speye(2*T) - sparse(2+1:T*2,1:(T-1)*2,repmat(rhod,T-1,1),2*T,2*T);
    
        % sample lamv
    Ystar = log((pi-pistar-b.*[pi0; pi(1:T-1)-pistar(1:T-1)]).^2 + .0001);
    loglamv = uc.sv.ksc_rw_h0_Vh(Ystar,log(lamv),phiv,lamv0,Vlamv);    
    lamv = exp(loglamv);    
    
        % sample lamn
    Ystar = log(([pistar(1)/sqrt(Vpistar); pistar(2:end)-pistar(1:end-1)]).^2 + .0001);
    loglamn = uc.sv.ksc_rw_h0_Vh(Ystar,log(lamn),phin,lamn0,Vlamn);
    lamn = exp(loglamn); 

        % sample sigb2
    e2 = (b(2:end) - b(1:end-1)).^2;
    sigb2c = sample_sig2(e2,nub0,Sb0);    
    sigbc = sqrt(sigb2c);
    sigb = sqrt(sigb2);
    alpMH = -sum(log(normcdf((1-b(1:T))/sigbc)-normcdf(-b(1:T)/sigbc))) + ...
        sum(log(normcdf((1-b(1:T))/sigb)-normcdf(-b(1:T)/sigb)));    
    if alpMH > log(rand)
        sigb2 = sigb2c;         
        sigb = sigbc;
        countsigb2 = countsigb2 + 1;
    end
    
        % sample sigd2
    for i=1:2       
        e2 = [(shortd(1,i)-mud(i))*sqrt(1-rhod(i)^2); ...
            shortd(2:end,i)-rhod(i)*shortd(1:end-1,i)-mud(i)*(1-rhod(i))].^2;        
        sigd2(i) = sample_sig2(e2,nud0(i),Sd0(i));
    end   
    
        % sample sigw2
    e2 = (Hpsi\(z - Xd*d)).^2;
    sigw2 = sample_sig2(e2,nuw0,Sw0);    
    
        % sample phiv
    e2 = (loglamv(2:end) - loglamv(1:end-1)).^2;
    phiv = sample_sig2(e2,nuv0,Sv0);   
    
        % sample phin
    e2 = (loglamn(2:end) - loglamn(1:end-1)).^2;
    phin = sample_sig2(e2,nun0,Sn0);    
        
    if isim > burnin
        isave = isim - burnin;
        store_pistar(isave,:) = pistar';
        store_b(isave,:) = b';
        store_d(isave,:) = d';
        store_lamv(isave,:) = lamv';         
        store_lamn(isave,:) = lamn';        
        store_theta(isave,:) = [psi' mud' rhod' sigd2' sigb2 sigw2 phiv phin];
    end
    
    if (mod(isim, 5000) == 0)
    end 
    
end

% ---- thin and package -----------------------------------------------------
keep = opts.Thin:opts.Thin:nsim;

out = struct();
out.model    = 'biuc_lrexp';
out.pistar   = store_pistar(keep, :);     % trend inflation, the published series
out.b        = store_b(keep, :);
out.d        = store_d(keep, :);
out.lamv     = store_lamv(keep, :);
out.lamn     = store_lamn(keep, :);
out.theta    = store_theta(keep, :);
out.settings = struct('nsim', opts.NSim, 'burnin', burnin, 'thin', opts.Thin, ...
                      'seed', opts.Seed, 'q', q, 'T', T);
out.ndraws   = numel(keep);
end

% ===========================================================================
% Local functions, lifted verbatim from sample_b.m, sample_psi.m and
% sample_sig2.m in trend_IE_code.zip. They are local so that their generic
% names cannot collide with anything else.
% ===========================================================================

function [b,accept] = sample_b(b,pi,pistar,lamv,pi0,Vb,sigb2)
accept = 0;
T = size(pi,1);
H =  speye(T) - sparse(2:T,1:(T-1),ones(1,T-1),T,T);
pitilde = pi - pistar;
Xb = sparse(1:T,1:T,[pi0; pitilde(1:T-1)]);
iLamv = sparse(1:T,1:T,1./lamv);  
HiSbH = H'*sparse(1:T,1:T,[1/Vb repmat(1/sigb2,1,T-1)])*H;
Kb = Xb'*iLamv*Xb + HiSbH;
bhat = Kb\(Xb'*iLamv*pitilde);
cholKb = chol(Kb,'lower'); 
    % AR step        
sigb = sqrt(sigb2);
gb = @(x) -sum(log(normcdf((1-x(1:end-1))/sigb) - normcdf(-x(1:end-1)/sigb)));    
bstar = bhat;
u = pitilde-Xb*bstar; v = bhat-bstar;
logc = -.5*(u./lamv)'*u -.5*bstar(1)^2/Vb ...
    -.5*sum((bstar(2:end)-bstar(1:end-1)).^2)/sigb2 + gb(bstar) ...
    + .5*v'*Kb*v + log(3); 
flag = 0; count = 0;
while flag == 0 && count < 100 % give up when count >= 100
    bc = bhat + cholKb'\randn(T,1);
    if  max(bc)<= .995 && min(bc)>= .005
        uc =  pitilde-Xb*bc; vc = bhat-bc;
        alpARc =  -.5*(uc./lamv)'*uc -.5*bc(1)^2/Vb +...
            -.5*sum((bc(2:end)- bc(1:end-1)).^2)/sigb2 + gb(bc) ...
            + .5*vc'*Kb*vc - logc;
        if alpARc > log(rand)
            flag = 1;
        end
    end
    count = count + 1;
end      
if flag == 1
    u = pitilde-Xb*b; v = bhat-b;
    alpAR = -.5*(u./lamv)'*u -.5*b(1)^2/Vb +...
            -.5*sum((b(2:end)- b(1:end-1)).^2)/sigb2 + gb(b) ... 
            + .5*v'*Kb*v - logc; 
    if alpAR < 0 
        alpMH = 1;
    elseif alpARc < 0
        alpMH = - alpAR;
    else
        alpMH = alpARc - alpAR;
    end        
    if alpMH > log(rand)
        b = bc;
        accept = 1;
    end
end

end
function [psi,flag,psihat,invDpsic] = sample_psi(psi,fpsi,loop,invDpsic,options)
q = length(psi);
psihat = fminsearch(fpsi,psi);
Cpsi = chol(invDpsic,'lower');
if (mod(loop,100)==0) || loop == 1 %% get the Hessian every 100 iterations
    [psihat,fval,exitflag,output,grad,hess] = fminunc(fpsi,psihat,options); 
    [tmpCpsi,p] = chol(hess,'lower');
    if p == 0
        invDpsic = hess;
        Cpsi = tmpCpsi;
    end        
end
psic = psihat + Cpsi'\randn(q,1); 
if sum(abs(1./roots([flipud(psic);1]))<.99) == q
    alpMH = -fpsi(psic) + fpsi(psi) ...
        - .5*(psi-psihat)'*invDpsic*(psi-psihat) ...
        + .5*(psic-psihat)'*invDpsic*(psic-psihat);
else
    alpMH = -inf;
end
flag = alpMH>log(rand);
if flag
    psi = psic;
end

end
function sig2 = sample_sig2(e2,nu0,S0)
n = size(e2,1);
sig2 = 1./gamrnd(nu0+n/2, 1./(S0+sum(e2)'/2)); 
end
