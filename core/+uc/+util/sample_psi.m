% uc.util.sample_psi - one Metropolis-Hastings step for MA coefficients.
%
%   [psi, flag, psihat, invDpsic] = uc.util.sample_psi(psi, fpsi, loop, invDpsic, options)
%
% fpsi is the negative log posterior of psi. The candidate is drawn from a normal
% centered at the mode fminsearch finds, with the Hessian from fminunc as its
% precision. That Hessian is recomputed at loop 1 and every hundredth loop, so loop
% must count every sweep, burn-in included. A candidate with an inverse root of
% modulus 0.99 or more is rejected. flag is true when the candidate is accepted.

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
