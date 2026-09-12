% revisions - why each quarter's estimate moved since the last release.
%
%   revs = revisions(results, previous, data)
%   revs = revisions(results, previous, data, 'Components', {'sample'})
%
% Returns the table behind estimates/revisions/YYYYQq.csv: for every model, series
% and date, the change since the previous release split into columns that sum to
% the total. It writes nothing - publish writes it, once the guardrails are green.
%
% OPTIONS
%   'Components'  which chains to run. Default {'sample'}, the sample-extension
%                 chain guardrail G8 needs and the only one implemented. 'data' and
%                 'montecarlo' need the previous release's archived source data.
%
% A smoothed estimate for 1998Q3 is not a fact settled in 1998. It moves at every
% release, for three reasons nothing published separates: the agency revised the
% input, the smoother now conditions on more data after that date, or the sampler
% is stochastic. Three runs per model with the seed held fixed give all three:
%
%   A  previous sample, previous data     data revision    = B - A
%   B  previous sample, new data          sample extension = C - B
%   C  new sample,      new data          Monte Carlo      = A - as published
%
% Chain B ships here because G8 needs it: without it the revision tolerance flags
% the expected movement near the sample end every quarter. It costs one extra chain
% per model, which is why this is a separate function with its own switch.
%
% ON THE FIRST RELEASE previous is empty and this returns an empty table with the
% right variable names. A file of zeros would report a measurement never made.

function revs = revisions(results, previous, data, opts)

arguments
    results (1,:) struct
    previous
    data (1,1) struct
    opts.Components (1,:) cell = {'sample'}
end

revs = empty_table();

% Components is checked before anything else: a name that cannot be computed is a
% configuration error whether or not there is a predecessor to compute it against.
unknown = setdiff(opts.Components, {'sample', 'data', 'montecarlo'});
if ~isempty(unknown)
    error('uc:estimates:revisions:unknownComponent', ...
        'unknown component(s): %s. Known: sample, data, montecarlo.', ...
        strjoin(unknown, ', '));
end
for c = intersect(opts.Components, {'data', 'montecarlo'})
    error('uc:estimates:revisions:notImplemented', ...
        ['the "%s" component needs the previous release''s archived source ' ...
         'data, which this pipeline does not re-estimate on.'], c{1});
end

if isempty(previous) || ~isfield(previous, 'series')
    return
end

% Chain B: this release's models, held at the previous release's sample end.
prev_end = previous_sample_end(previous);
cfg = [results.settings];
B = run_estimates(cfg, data, 'SampleEnd', prev_end, 'Parallel', false);

blocks = {};
for k = 1:numel(results)
    r = results(k);
    b = B(strcmp({B.model}, r.model));
    for s = fieldnames(r.series)'
        name = s{1};
        if ~isfield(b.series, name), continue, end

        cnew = r.series.(name);
        cB   = b.series.(name);
        pub  = published_mean(previous, name, r.model);
        if isempty(pub), continue, end

        % Every column is matched on dates, never on position: the three chains
        % end at different quarters and the published file may start elsewhere.
        d = intersect(intersect(cnew.dates, cB.dates), pub.date);
        if isempty(d), continue, end

        vnew = pick(cnew.dates, cnew.summary.mean, d);
        vB   = pick(cB.dates,   cB.summary.mean,   d);
        vpub = pick(pub.date,   pub.value,         d);

        n = numel(d);
        blocks{end+1} = table(d, repmat(string(r.model), n, 1), ...
            repmat(string(name), n, 1), vnew - vpub, vnew - vB, ...
            'VariableNames', {'date', 'model', 'series', 'total', 'sample'}); %#ok<AGROW>
    end
end

if ~isempty(blocks)
    revs = sortrows(vertcat(blocks{:}), {'model', 'series', 'date'});
end
end


% ---------------------------------------------------------------------------
function t = empty_table()
t = table(datetime.empty(0, 1), string.empty(0, 1), string.empty(0, 1), ...
    zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'date', 'model', 'series', 'total', 'sample'});
end


function e = previous_sample_end(previous)
% The last quarter the previous release published, read from its own series
% rather than from its folder name: the folder is the vintage label, and a
% release can publish a sample that ends before the quarter it is labelled with.
last = NaT;
for s = fieldnames(previous.series)'
    t = previous.series.(s{1});
    if isempty(t) || ~ismember('date', t.Properties.VariableNames), continue, end
    last = max([last; max(to_datetime(t.date))]);
end
if isnat(last)
    error('uc:estimates:revisions:noPreviousDates', ...
        'the previous vintage at %s has no dated series to take a sample end from.', ...
        previous.path);
end
e = sprintf('%dQ%d', year(last), quarter(last));
end


function p = published_mean(previous, name, model)
% The posterior mean column for one model and series out of the tidy CSV.
p = [];
if ~isfield(previous.series, name), return, end
t = previous.series.(name);
if isempty(t), return, end
sel = t.model == string(model) & t.measure == "mean";
if ~any(sel), return, end
p = table(to_datetime(t.date(sel)), t.value(sel), 'VariableNames', {'date', 'value'});
end


function v = pick(dates, values, want)
[~, loc] = ismember(want, dates);
v = values(loc);
end


function d = to_datetime(x)
if isdatetime(x), d = x(:); else, d = datetime(x); end
end
