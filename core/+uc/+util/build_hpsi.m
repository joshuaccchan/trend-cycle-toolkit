% uc.util.build_hpsi - the MA(q) difference matrix for a given psi.
%
%   Hpsi = uc.util.build_hpsi(psi, T)
%
% Returns the T-by-T banded lower-triangular matrix with ones on the diagonal and
% -psi(j) on the j-th subdiagonal, so that Hpsi*e applies the MA(q) filter.
%
% Lifted verbatim from buildHpsi.m in trend_IE_code.zip, renamed.

function Hpsi = build_hpsi(psi,T)
q = length(psi);
Hpsi = speye(T);
for j=1:q
    Hpsi = Hpsi + psi(j)*sparse(j+1:T,1:T-j,ones(1,T-j),T,T);
end
end
