% uc.sv.ksc_rw_h0_Vh - KSC sampler with a separate initial variance.
%
%   h = uc.sv.ksc_rw_h0_Vh(Ystar, h, sig, h0, Vh)
%
% The auxiliary-mixture sampler for a random-walk log-volatility path whose first
% period carries its own variance:
%
%   h_1 ~ N(h0, Vh),   h_t = h_{t-1} + N(0, sig)
%
% uc.sv.ksc_rw_h0 is a different model: it has no Vh, so its precision diagonal is
% flat at 1/sig throughout, while here the first entry is 1/Vh.
%
% Lifted verbatim from SVRW.m in trend_IE_code.zip, renamed; uc.models.biuc_lrexp
% is its only caller. Three of the packages this repository draws on ship a
% different sampler under the name SVRW.m, with different arities and different
% meanings for the same argument positions, which is why nothing here carries that
% name.

function h = ksc_rw_h0_Vh(Ystar,h,sig,h0,Vh)

T = length(h);
    % normal mixture
pi = [0.0073 .10556 .00002 .04395 .34001 .24566 .2575];
mi = [-10.12999 -3.97281 -8.56686 2.77786 .61942 1.79518 -1.08819] - 1.2704;  %% means already adjusted!! %%
sigi = [5.79596 2.61369 5.17950 .16735 .64009 .34023 1.26261];
sqrtsigi = sqrt(sigi);
    % sample S from a 7-point distrete distribution
tmprand = rand(T,1);
q = repmat(pi,T,1).*normpdf(repmat(Ystar,1,7),repmat(h,1,7)+repmat(mi,T,1), repmat(sqrtsigi,T,1));
q = q./repmat(sum(q,2),1,7);
S = 7 - sum(repmat(tmprand,1,7)<cumsum(q,2),2)+1;
    
    % sample h
Hh =  speye(T) - spdiags(ones(T-1,1),-1,T,T);
alph = Hh\[h0; sparse(T-1,1)];
iSh = sparse(1:T,1:T,[1/Vh; 1/sig*ones(T-1,1)]);
dconst = mi(S)'; iOmega = sparse(1:T,1:T,1./sigi(S)');
HiSH_h = Hh'*iSh*Hh;
Kh = HiSH_h + iOmega;
h_hat = Kh\(HiSH_h*alph + iOmega*(Ystar-dconst));
h = h_hat + chol(Kh,'lower')'\randn(T,1);
end
