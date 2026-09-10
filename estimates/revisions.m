% revisions - split each quarter's revision into its three causes.
%
%   revs = revisions(results, previous, data)
%   revs = revisions(results, previous, data, 'Components', {'sample'})
%
% Returns the table behind estimates/revisions/YYYYQq.csv: for every model and every
% date, the change since the previous release decomposed into columns that sum to
% the total. results is the struct array from run_estimates.m, previous is the
% struct from load_previous_vintage.m, and data is the aligned struct the new run
% was estimated on - the second chain re-estimates the previous sample on it.
%
% It returns the table and writes nothing. publish.m writes it, into the staging
% tree first and into estimates/revisions/ only once the guardrails are green,
% because this function runs at step 6 and the guardrails are step 7: a revision
% table written here would be a file in the tracked tree from a release that was
% then refused.
%
% ON THE FIRST RELEASE previous is empty, because the archive under
% estimates/vintages/ begins with that release and there is nothing before it to
% revise. This function returns an empty table with the right variable names, and
% publish.m writes no estimates/revisions/YYYYQq.csv for that vintage. A file of
% zeros would report a measurement that was never made. The first revision file is
% the second release's.
%
% NAME-VALUE OPTIONS
%   'Components'  which chains to run, as a cellstr. Default {'sample'}, the
%                 sample-extension chain that guardrail G8 needs and the only one
%                 phase 5 ships. Phase 7 adds 'data' and 'montecarlo', and each one
%                 named is another full chain per model - run_release.m therefore
%                 asks for what it needs by name rather than taking the default.
%
% WHY. A smoothed estimate of trend inflation for 1998Q3 is not a fact that was
% settled in 1998. It moves at every release, and it moves for three quite different
% reasons that nothing published anywhere separates:
%
%   data revision      the statistical agency revised the input series
%   sample extension   the smoother now conditions on more data after that date
%   Monte Carlo        the sampler is stochastic and this is its own noise
%
% The ADS business conditions index popularized the tentacle plot, which shows THAT
% estimates revise. This says WHY, quarter by quarter, and it is the one thing in
% this repository that has no published counterpart.
%
% HOW. Three runs per model with the seed held fixed, differenced pairwise:
%
%   A  previous sample, previous data   (the previous release, re-run)
%   B  previous sample, new data
%   C  new sample,      new data        (this release)
%
%   data revision    = B - A
%   sample extension = C - B
%   Monte Carlo      = A - (the previous release as published)
%
% Holding the seed fixed across A, B and C is what makes the first two differences
% clean; the third is what is left over, and it is the honest measure of how much of
% a "revision" is nothing at all. Running A at all requires every sampler to accept
% an arbitrary sample end rather than reading to the end of its array, which is the
% refactor this function waits on.
%
% ORDER OF ARRIVAL. Chain B - previous sample on new data, giving the sample
% extension component - ships with the guardrails in phase 5, ahead of the rest. It
% is the cheapest of the three and it is the one guardrail G8 needs: without it, the
% revision tolerance flags the expected movement near the sample end every single
% quarter and there is nothing to subtract. The full three-chain decomposition
% follows in phase 7.
%
% COST. Three chains per model instead of one, so roughly three times the release
% runtime. That is the reason it is a separate function with its own switch rather
% than part of run_estimates: a release must be able to publish without it.
%
% The tentacle plot over the archived vintages is uc.plot.tentacle, drawn from
% estimates/vintages/ rather than from this table - the table explains the movement,
% the plot shows it.

function revs = revisions(results, previous, data, varargin)                %#ok<STOUT,INUSD>

error('uc:estimates:revisions:notImplemented', ...
    ['revisions is not implemented yet (phase 7; the sample-extension chain in ' ...
     'phase 5). It needs every sampler to accept an arbitrary sample end, which ' ...
     'is part of the phase 5 re-basing.']);
