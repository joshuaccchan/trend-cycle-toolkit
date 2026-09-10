% run_estimates - estimate every scheduled model on one data vintage.
%
%   results = run_estimates(cfg, data)
%   results = run_estimates(cfg, data, 'Parallel', false)
%   results = run_estimates(cfg, data, 'SampleEnd', '2026Q3', 'StageDir', d)
%
% Settings in, data in, stored draws out. cfg is the struct array from preset.m,
% one element per model and in the order they will be run; data is the aligned
% struct from uc.data. This function fetches nothing, writes nothing outside the
% staging path, and makes no decision about whether a result is fit to publish.
% run_release.m calls it between uc.data and guardrails.m; keeping those three apart
% is what makes it possible to re-run the estimation on an archived vintage without
% touching the network, and to test the guardrails on results that were never
% estimated at all.
%
% Neither argument is optional and neither has a default: a driver that could reach
% for the current vintage by itself is a driver that can silently estimate the wrong
% quarter, and preset.m is the only place settings come from.
%
% NAME-VALUE OPTIONS
%   'SampleEnd'   quarter string, default the last complete quarter in data. Set it
%                 to a past quarter to reproduce an old vintage, which is what
%                 revisions.m does.
%   'Parallel'    logical, default true. parfor across models, not within one.
%                 run_release.m passes false in cloud-backup mode, where the runner
%                 has two cores and the pool costs more than it returns.
%   'StageDir'    staging directory, default build/ at the repository root, which
%                 .gitignore excludes. Nothing under it is ever a release.
%
% RETURNS
%   results  1 x numel(cfg) struct array, in the order cfg came in: the thinned
%            draws, the posterior summaries, the diagnostics from uc.diag, the
%            acceptance rates, the seed and settings from preset.m, the elapsed time,
%            and the MATLAB and toolbox versions. Everything guardrails.m and
%            publish.m need, and nothing that has to be recomputed later from a chain
%            that is no longer in memory.
%
% WHAT IT WILL DO
%   1. rng(seed,'threefry') per model, from cfg, inside the loop body and before
%      anything stochastic.
%   2. Assert the data covers the model's configured sample start and has no gaps,
%      and that every series the model needs is present: CPIAUCSL for the three
%      trend inflation models, PTRCPI as well for biuc_lrexp, GDPC1 for the two
%      output-gap models.
%   3. Resolve any configured break dates against that sample through
%      resolve_break_dates.m, and pass the resulting row indices to the model. Only
%      ucur_break2 has breaks; it is the reason a model never sees a date.
%   4. Run each model through uc.models, thinning by 10 as draws are stored, with
%      cfg.compute_ml passed through - false on the quarterly job, so neither
%      output-gap model runs its importance step.
%   5. Compute inefficiency factors, MCSE and Geweke Z per stored parameter through
%      uc.diag, on the thinned chain, and record acceptance rates for every
%      Metropolis-Hastings block.
%   6. Write each model's raw output to the staging path as it finishes, so that a
%      crash in the last model does not cost the ones that already ran. That is the
%      reason the loop over models lives here rather than in run_release.m: the
%      driver would otherwise own the loop and this function would own the
%      bookkeeping that has to happen inside it.
%
% It does NOT decide anything. A NaN posterior, a chain stuck against a bound, a
% series that lost its last four quarters - all of those come back in the results
% struct as numbers, and guardrails.m is what refuses them. matlab -batch exits 0 on
% every one of them, so the refusal has to be explicit and it has to live in one
% place.
%
% PARALLELISM. parfor runs across models, never within a sampler: the samplers are
% sequential by construction and the models are independent. Memory is the binding
% constraint, not cores - see the thinning note in preset.m.

function results = run_estimates(cfg, data, varargin)                       %#ok<STOUT,INUSD>

error('uc:estimates:run_estimates:notImplemented', ...
    ['run_estimates is not implemented yet (phase 5). Until the models are ' ...
     'extracted into core/+uc/+models, there is nothing for it to call.']);
