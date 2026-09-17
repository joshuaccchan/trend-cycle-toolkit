% uc.util.nllike_ma1_sv - negative log likelihood of MA(1) errors with SV.
%
%   ell = uc.util.nllike_ma1_sv(psi, y, h)
%
% For y_t = u_t + psi u_{t-1}, u_t ~ N(0, exp(h_t)) and u_0 = 0, minus the log
% density of y, computed through the banded covariance Hpsi diag(exp(h)) Hpsi'.

function ell = nllike_ma1_sv(psi,y,h)
T = length(y);
Hpsi = speye(T) + sparse(2:T,1:(T-1),psi*ones(1,T-1),T,T); 
Omega_y = Hpsi*sparse(1:T,1:T,exp(h))*Hpsi';
ell = -T/2*log(2*pi) -.5*sum(h) - .5*y'*(Omega_y\y);
ell = -ell;
end
