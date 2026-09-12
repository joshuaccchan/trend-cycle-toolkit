% run_estimates - estimate every scheduled model on one data vintage.
%
%   results = run_estimates(cfg, data)
%   results = run_estimates(cfg, data, 'Parallel', false)
%   results = run_estimates(cfg, data, 'SampleEnd', '2026Q2', 'StageDir', d)
%
% cfg is the struct array from preset. data is a struct of model-ready series, each
% a table of date and value:
%
%   infl    400*log difference of DPCERD3Q086SBEA, from uc.data.annualized_log_diff
%   lgdp    100*log(GDPC1)
%   ptr     long-run PCE expectations, from uc.data.build_ptr
%
% This function fetches nothing, writes nothing outside the staging path, and
% decides nothing about whether a result is fit to publish - guardrails does that.
%
% OPTIONS
%   'SampleEnd'   quarter string, default each model's last available quarter. A
%                 past quarter reproduces an old vintage, which is what revisions
%                 does for its sample-extension chain.
%   'Parallel'    logical, default true. parfor across models, never within a
%                 sampler. Falls back to a serial loop when no pool starts.
%   'StageDir'    each model's raw output is saved there as it finishes, so a crash
%                 in the last does not cost the earlier ones. Default: no saving.
%
% RETURNS a 1 x numel(cfg) struct array in cfg's order, each with model, series
% (one field per published series, holding draws, dates and a summary table),
% diagnostics, accept, seed, settings, sample_start, sample_end, ndraws, elapsed,
% generator and versions.
%
% DIAGNOSTICS. Inefficiency factor and MCSE are reported for every published date,
% because G8 needs a per-date MCSE. Geweke Z is reported for every scalar parameter
% and for selected dates only - the two ends of each path, where the smoother has
% data on one side alone, and every fortieth quarter between. A whole state path is
% several hundred numbers that move together, so scoring all of them reports one
% thing many times. Unreported dates carry NaN in the geweke columns.
%
% ALIGNMENT IS PER MODEL, over that model's own inputs. uc.data.align_by_date
% intersects what it is given, so aligning all three series at once would start
% every model where PTR does and throw away thirteen years from the four that never
% read it. Models can also end at different quarters.
%
% THE PRESAMPLE QUARTER. ar_trend_bound and biuc_lrexp each spend their first
% quarter as the presample observation their published drivers expect, so the path
% they return starts one quarter after cfg.sample_start. uc_2m's trend growth is a
% first difference and does the same. Every series carries its own dates.

function results = run_estimates(cfg, data, opts)

arguments
    cfg (1,:) struct
    data (1,1) struct
    opts.SampleEnd {mustBeTextScalar} = ''
    opts.Parallel (1,1) logical = true
    opts.StageDir {mustBeTextScalar} = ''
end

if ~isempty(opts.StageDir) && ~isfolder(opts.StageDir)
    mkdir(opts.StageDir);
end

n = numel(cfg);
results = cell(1, n);
stagedir = opts.StageDir;
sample_end = opts.SampleEnd;

if opts.Parallel && n > 1 && can_parallel()
    parfor k = 1:n
        results{k} = estimate_one(cfg(k), data, sample_end, stagedir);
    end
else
    for k = 1:n
        results{k} = estimate_one(cfg(k), data, sample_end, stagedir);
    end
end

results = [results{:}];
end


% ---------------------------------------------------------------------------
function r = estimate_one(c, data, sample_end, stagedir)
% One model, start to finish: window, draws, summaries, diagnostics.

t0 = tic;

sub = struct();
for f = needs(c.model)
    if ~isfield(data, f{1})
        error('uc:estimates:run_estimates:missingSeries', ...
            '%s needs data.%s, which is not present. It reads %s.', ...
            c.model, f{1}, strjoin(c.inputs, ', '));
    end
    sub.(f{1}) = data.(f{1});
end

% align_by_date intersects the model's own inputs and errors when they cannot
% reach the configured start, which is the assertion preset.m asks for.
try
    [s, span] = uc.data.align_by_date(sub, 'Start', c.sample_start);
catch err
    error('uc:estimates:run_estimates:startMissing', ...
        ['%s is configured to start at %s and its inputs (%s) cannot reach it. ' ...
         'preset.m records each start as a fact about the data, so this means a ' ...
         'series no longer begins where it did. The alignment said: %s'], ...
        c.model, c.sample_start, strjoin(needs(c.model), ', '), err.message);
end

wdates = span.date(:);
if ~isempty(sample_end)
    stop = find(wdates == quarter_to_datetime(sample_end), 1);
    if isempty(stop)
        error('uc:estimates:run_estimates:sampleEndOutside', ...
            '%s: SampleEnd %s is not in its aligned sample, which runs %s to %s.', ...
            c.model, sample_end, label(wdates(1)), label(wdates(end)));
    end
    wdates = wdates(1:stop);
    for f = needs(c.model)
        s.(f{1}) = s.(f{1})(1:stop);
    end
end

if numel(wdates) < 8
    error('uc:estimates:run_estimates:emptySample', ...
        '%s: the sample is %d quarters, which is too short to estimate.', ...
        c.model, numel(wdates));
end

for f = needs(c.model)
    if any(~isfinite(s.(f{1})))
        error('uc:estimates:run_estimates:nonFiniteInput', ...
            '%s: %s has %d non-finite values inside the sample.', ...
            c.model, f{1}, sum(~isfinite(s.(f{1}))));
    end
end

rng(c.seed, 'threefry');

switch c.model
    case 'ucsv_sw07'
        y   = s.infl;
        out = uc.models.ucsv_sw07(y, 'NSim', c.nsim, 'Burnin', c.burnin, ...
                                  'Thin', c.thin, 'Seed', c.seed);
        pub = pack('trend_inflation', out.tau, wdates);

    case 'ar_trend_bound'
        y = s.infl;
        out = uc.models.ar_trend_bound(y(2:end), y(1), 'NSim', c.nsim, ...
                  'Burnin', c.burnin, 'Thin', c.thin, 'Seed', c.seed, ...
                  'Bounds', c.bounds, 'RhoBound', c.rho_bound);
        pub = pack('trend_inflation', out.tau, wdates(2:end));

    case 'biuc_lrexp'
        y = s.infl;
        z = s.ptr;
        out = uc.models.biuc_lrexp(y, z, 'NSim', c.nsim, 'Burnin', c.burnin, ...
                                   'Thin', c.thin, 'Seed', c.seed);
        pub = pack('trend_inflation', out.pistar, wdates(2:end));

    case 'uc_2m'
        y   = s.lgdp;
        out = uc.models.uc_2m(y, 'NSim', c.nsim, 'Burnin', c.burnin, ...
                              'Thin', c.thin, 'Seed', c.seed);
        pub = pack('output_gap', out.gap, wdates);
        pub.trend_growth = one_series(out.mu, wdates(2:end));

    case 'ucur_break2'
        y = s.lgdp;
        brk = resolve_break_dates(c.break_dates, wdates);
        out = uc.models.ucur_break2(y, brk, 'NSim', c.nsim, 'Burnin', c.burnin, ...
                                    'Thin', c.thin, 'Seed', c.seed);
        pub = pack('output_gap', out.gap, wdates);

    otherwise
        error('uc:estimates:run_estimates:unknownModel', ...
            '%s has no call site in run_estimates.', c.model);
end

r = struct();
r.model        = c.model;
r.series       = pub;
r.diagnostics  = diagnose(c, pub, out);
r.accept       = accept_of(out);
r.seed         = c.seed;
r.settings     = c;
r.sample_start = label(wdates(1));
r.sample_end   = label(wdates(end));
r.ndraws       = out.ndraws;
r.raw          = out;
g = rng;
r.generator    = g.Type;   % what actually drew, for guardrail G1
r.elapsed      = toc(t0);
r.versions     = version_stamp();

if ~isempty(stagedir)
    % -v7.3 is what carries a variable past 2GB, and it is also the one format a
    % thread-based parfor worker cannot write. The thinned output is far below
    % that ceiling today, so fall back rather than lose the staged copy.
    f = fullfile(stagedir, ['raw_' c.model '.mat']);
    try
        save(f, '-struct', 'r', '-v7.3');
    catch
        save(f, '-struct', 'r');
    end
end
end


% ---------------------------------------------------------------------------
function f = needs(model)
% The model-ready fields each model reads.
switch model
    case {'ucsv_sw07', 'ar_trend_bound'}, f = {'infl'};
    case 'biuc_lrexp',                    f = {'infl', 'ptr'};
    case {'uc_2m', 'ucur_break2'},        f = {'lgdp'};
    otherwise, f = {};
end
end


function s = pack(name, draws, dates)
s = struct();
s.(name) = one_series(draws, dates);
end


function s = one_series(draws, dates)
% Draws plus the summary publish.m writes: the posterior mean and the four
% quantiles that make the 68 and 90 per cent bands.
dates = dates(:);
if size(draws, 2) ~= numel(dates)
    error('uc:estimates:run_estimates:dateMismatch', ...
        'a series has %d columns of draws against %d dates.', ...
        size(draws, 2), numel(dates));
end
s = struct();
s.draws = draws;
s.dates = dates;
q = quantile_cols(draws, [0.05 0.16 0.84 0.95]);
s.summary = table(dates, mean(draws, 1)', q(:,1), q(:,2), q(:,3), q(:,4), ...
    'VariableNames', {'date', 'mean', 'p05', 'p16', 'p84', 'p95'});
end


function d = diagnose(c, series, out)
% Inefficiency factor and MCSE for every published date and scalar parameter, on
% the thinned chain; Geweke Z for the parameters and a selection of the dates.
L = c.trunc_lag;
rows = {};

names = fieldnames(series);
for i = 1:numel(names)
    s = series.(names{i});
    rows{end+1} = diag_block(names{i}, s.dates, ...
        compose_names(names{i}, numel(s.dates)), s.draws, L, ...
        reported_dates(numel(s.dates))); %#ok<AGROW>
end

if isfield(out, 'theta') && isfield(out, 'theta_names')
    rows{end+1} = diag_block('parameters', NaT(numel(out.theta_names), 1), ...
        out.theta_names(:), out.theta, L, true(1, numel(out.theta_names)));
end
if isfield(out, 'sig') && isfield(out, 'sig_names')
    rows{end+1} = diag_block('parameters', NaT(numel(out.sig_names), 1), ...
        out.sig_names(:), out.sig, L, true(1, numel(out.sig_names)));
end

d = vertcat(rows{:});
end


function t = diag_block(seriesname, dates, parnames, draws, L, report)
IF = uc.diag.ineff(draws, L);
MC = uc.diag.mcse(draws, L);
k = size(draws, 2);

% Geweke gets the same truncation lag as the other two, capped against the segment
% it tests rather than the whole chain. Its own 'auto' rule is 4*(n/100)^(2/9),
% built for weakly dependent data: on a 40,000-draw chain it picks 9 lags where the
% integration time is nearly 300, understates the long-run variance, and inflates Z
% for every state path at once.
Z = nan(1, k);
p = nan(1, k);
if any(report)
    [Z(report), p(report)] = uc.diag.geweke(draws(:, report), 0.10, 0.50, ...
        geweke_lag(L, size(draws, 1)));
end
t = table(repmat(string(seriesname), k, 1), dates(:), string(parnames(:)), ...
    IF(:), MC(:), Z(:), p(:), ...
    'VariableNames', {'series', 'date', 'parameter', 'ineff', 'mcse', ...
                      'geweke_z', 'geweke_p'});
end


function sel = reported_dates(n)
% Which dates on a state path carry a Geweke statistic: both ends, and every
% fortieth quarter between.
sel = false(1, n);
sel([1, n]) = true;
sel(1:40:n) = true;
end


function L = geweke_lag(trunc, n)
% The first segment is a tenth of the chain, and a Bartlett estimate needs a lag
% well inside the segment it is computed on.
L = max(1, min(trunc, floor(0.10 * n / 10)));
end


function n = compose_names(seriesname, k)
n = arrayfun(@(i) sprintf('%s[%d]', seriesname, i), (1:k)', 'UniformOutput', false);
end


function a = accept_of(out)
if isfield(out, 'accept'), a = out.accept; else, a = struct(); end
end


function q = quantile_cols(X, probs)
% Column-wise quantiles without the Statistics Toolbox, by linear interpolation
% on the order statistics - the same definition quantile() uses by default.
X = sort(X, 1);
n = size(X, 1);
pos = probs(:)' * n + 0.5;
lo = max(1, floor(pos));  hi = min(n, ceil(pos));  w = pos - floor(pos);
q = zeros(size(X, 2), numel(probs));
for j = 1:numel(probs)
    q(:, j) = (1 - w(j)) * X(lo(j), :)' + w(j) * X(hi(j), :)';
end
end


function v = version_stamp()
v = struct('matlab', version, 'release', version('-release'));
end


function tf = can_parallel()
tf = ~isempty(ver('parallel'));
if tf
    try
        p = gcp('nocreate');
        if isempty(p), p = parpool('threads'); end
        tf = ~isempty(p);
    catch
        tf = false;
    end
end
end



function d = quarter_to_datetime(s)
s = char(s);
y = str2double(s(1:4));
q = str2double(s(6));
if isnan(y) || isnan(q) || q < 1 || q > 4
    error('uc:estimates:run_estimates:badQuarter', ...
        '"%s" is not a quarter of the form YYYYQq.', s);
end
d = datetime(y, 3*(q-1) + 1, 1);
end


function s = label(d)
s = sprintf('%dQ%d', year(d), quarter(d));
end
