% uc.util.surform - stack a matrix into seemingly-unrelated-regression form.
%
%   Xout = uc.util.surform(X)
%
% Takes a T-by-k matrix and returns the sparse T-by-Tk expansion whose t-th row
% holds row t of X in columns (t-1)k+1 : tk, which turns a regression with
% time-varying coefficients into one linear system.
%
% Lifted verbatim from SURform.m in trend_IE_code.zip, renamed to lower case.

function Xout = surform( X )
[r,c] = size( X );
idi = kron((1:r)',ones(c,1));
idj = (1:r*c)';
Xout = sparse(idi,idj,reshape(X',r*c,1));
end
