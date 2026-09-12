% uc.util.llike_maq - log likelihood of an MA(q) error model given psi.
%
%   lden = uc.util.llike_maq(psi, y, sig2)
%
% The objective the psi block of uc.models.biuc_lrexp maximizes before its
% accept-reject step.
%
% From llike_MAq.m in trend_IE_code.zip.

function lden = llike_maq(psi,y,sig2)
T = length(y);
Hpsi = uc.util.build_hpsi(psi,T);
L = sig2*(Hpsi*Hpsi');
lden = -T/2*log(2*pi*sig2) - .5*y'*(L\y);
end
