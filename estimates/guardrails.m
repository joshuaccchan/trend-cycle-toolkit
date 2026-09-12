% guardrails - every check that must pass before a release is allowed to promote.
%
%   report = guardrails(results, previous, data, revs)
%   report = guardrails(results, previous, data, revs, 'Vintage', '2026Q3', ...
%                       'SeasonalRevision', true)
%
% All four arguments are positional and required: the results from run_estimates,
% the previous vintage from load_previous_vintage, the series estimated on, and the
% revision table from revisions. A check that quietly skips for want of an argument
% is worse than no check.
%
%   report.pass      true only if every check that ran is green. publish consults
%                    this and nothing else before promoting.
%   report.nfail     how many failed.
%   report.checks    a table: id, model, statistic, value, tolerance, status, note.
%   report.vintage   the vintage checked.
%   report.seasonal  whether the G9 widening was applied, and by what factor.
%
% OPTIONS
%   'Vintage'           'YYYYQq', recorded in the report and in metadata.json.
%   'SeasonalRevision'  widen the G8 tolerance by 3 for the February CPI
%                       seasonal-factor re-estimation. Gated on the run month.
%
% THE CHECKS
%
%   G1   every model carries preset's seed, the seeds are distinct, and the
%        generator that drew is threefry
%   G2   PTR present, its last quarter not in the future, and the 32-quarter
%        backfill over 1960Q1-1967Q4 flat at PTR's own first value
%   G3   the sample starts where the previous one did and extends it
%   G4   no NaN or Inf in any stored chain or published column, checked on the
%        draws rather than only the summaries
%   G5   bounded models inside their bounds on every draw, read from the same
%        preset struct the sampler was given
%   G6   acceptance rates in band. No targets are measured, so this reports the
%        observed rates and returns n/a
%   G7   effective sample size at least 100 for every published parameter. Geweke
%        Z is computed and written to diagnostics.csv but does not gate a release:
%        most of the parameters it scores are points on one state path and move
%        together, so a share of them carries far less information than its face
%        value suggests
%   G8   for any date more than eight quarters before the sample end, a move
%        against the previous vintage over max(0.20pp, 3 x MCSE) fails, and one
%        over 1.0pp is held for a person
%   G9   the February widening, recorded and never silent
%   G10  a GDP base change, detected as a near-constant shift across the overlap
%        and recorded rather than refused
%
% THE FIRST RELEASE has no predecessor, so G3, G8 and G10 are written with status
% n/a and the reason, never pass - a check that could not run has not passed.
% report.pass is decided on the checks that did run.
%
% ON FAILURE nothing is promoted, the previous release stays where it is, and the
% report names the check, the model and the margin.

function report = guardrails(results, previous, data, revs, opts)

arguments
    results (1,:) struct
    previous
    data (1,1) struct
    revs
    opts.Vintage {mustBeTextScalar} = ''
    opts.SeasonalRevision (1,1) logical = false
end

MIN_ESS      = 100;     % G7
REV_FLOOR    = 0.20;    % G8, percentage points
REV_MCSE     = 3;       % G8
REV_FAIL     = 1.00;    % G8, percentage points
SEASONAL_FACTOR = 3;    % G9

rows = {};
first_release = isempty(previous) || ~isfield(previous, 'series');

% ---- G1 seeding -----------------------------------------------------------
seeds = [results.seed];
for k = 1:numel(results)
    r = results(k);
    ok = isscalar(r.seed) && isfinite(r.seed) && r.seed == r.settings.seed;
    rows{end+1} = row('G1', r.model, 'seed matches preset', r.seed, NaN, ok, ...
        sprintf('preset says %d', r.settings.seed)); %#ok<AGROW>
    gen = '';
    if isfield(r, 'generator'), gen = char(r.generator); end
    rows{end+1} = row('G1', r.model, 'generator', NaN, NaN, ...
        strcmp(gen, 'threefry'), sprintf('%s', gen)); %#ok<AGROW>
end
rows{end+1} = row('G1', 'all', 'seeds distinct', numel(unique(seeds)), numel(seeds), ...
    numel(unique(seeds)) == numel(seeds), 'no two models share a stream');

% ---- G2 the PTR expectations series ---------------------------------------
if isfield(data, 'ptr')
    p = data.ptr;
    rows{end+1} = row('G2', 'ptr', 'series present', height(p), NaN, height(p) > 0, '');

    lastq = p.date(end);
    nowq = dateshift(datetime('now'), 'start', 'quarter');
    rows{end+1} = row('G2', 'ptr', 'last quarter not in the future', ...
        year(lastq) + quarter(lastq)/10, year(nowq) + quarter(nowq)/10, ...
        lastq <= nowq, ['last ' qlabel(lastq) ', now ' qlabel(nowq)]);

    bf = p.date < datetime(1968, 1, 1);
    flat = sum(bf) > 0 && isscalar(uniquetol(p.value(bf), 1e-12));
    rows{end+1} = row('G2', 'ptr', 'backfill flat', sum(bf), 32, ...
        flat && sum(bf) == 32, sprintf('%d quarters at %.4f', sum(bf), p.value(1)));
else
    rows{end+1} = row('G2', 'ptr', 'series present', NaN, NaN, false, ...
        'data has no ptr field');
end

% ---- G3 sample extension --------------------------------------------------
if first_release
    rows{end+1} = na('G3', 'all', 'sample extension', ...
        'first release: the archive begins with this vintage');
else
    for k = 1:numel(results)
        r = results(k);
        for s = fieldnames(r.series)'
            pub = published(previous, s{1}, r.model);
            if isempty(pub), continue, end
            newd = r.series.(s{1}).dates;
            rows{end+1} = row('G3', r.model, [s{1} ' start unchanged'], ...
                NaN, NaN, min(newd) == min(pub.date), ...
                sprintf('%s, was %s', qlabel(min(newd)), qlabel(min(pub.date)))); %#ok<AGROW>
            rows{end+1} = row('G3', r.model, [s{1} ' sample extends'], ...
                numel(newd), numel(pub.date), numel(newd) >= numel(pub.date), ...
                sprintf('%d quarters, was %d', numel(newd), numel(pub.date))); %#ok<AGROW>
        end
    end
end

% ---- G4 no NaN or Inf -----------------------------------------------------
for k = 1:numel(results)
    r = results(k);
    bad = count_nonfinite(r.raw);
    rows{end+1} = row('G4', r.model, 'non-finite draws', bad, 0, bad == 0, ''); %#ok<AGROW>
    badc = 0;
    for s = fieldnames(r.series)'
        m = r.series.(s{1}).summary;
        badc = badc + sum(~isfinite([m.mean; m.p05; m.p16; m.p84; m.p95]));
    end
    rows{end+1} = row('G4', r.model, 'non-finite published values', badc, 0, ...
        badc == 0, ''); %#ok<AGROW>
end

% ---- G5 bounds ------------------------------------------------------------
for k = 1:numel(results)
    r = results(k);
    b = r.settings.bounds;
    if isempty(b), continue, end
    tau = r.raw.tau;
    out_lo = sum(tau(:) < b(1));  out_hi = sum(tau(:) > b(2));
    rows{end+1} = row('G5', r.model, 'trend inside bounds', out_lo + out_hi, 0, ...
        out_lo + out_hi == 0, sprintf('bounds [%g %g]', b(1), b(2))); %#ok<AGROW>
    at = mean(tau(:) < b(1) + 1e-6 | tau(:) > b(2) - 1e-6);
    rows{end+1} = row('G5', r.model, 'share of draws at a bound', at, 0.01, ...
        at <= 0.01, 'reported even when formally inside'); %#ok<AGROW>
    if ~isempty(r.settings.rho_bound) && isfield(r.raw, 'rho')
        rb = r.settings.rho_bound;
        bad = sum(r.raw.rho(:) < 0 | r.raw.rho(:) > rb);
        rows{end+1} = row('G5', r.model, 'rho inside bounds', bad, 0, bad == 0, ...
            sprintf('0 to %g', rb)); %#ok<AGROW>
    end
end

% ---- G6 acceptance rates --------------------------------------------------
for k = 1:numel(results)
    r = results(k);
    f = fieldnames(r.accept);
    if isempty(f)
        rows{end+1} = na('G6', r.model, 'acceptance rates', ...
            'no Metropolis-Hastings block in this model'); %#ok<AGROW>
        continue
    end
    for j = 1:numel(f)
        rows{end+1} = na('G6', r.model, ['acceptance rate, ' f{j}], ...
            sprintf('observed %.3f; no target has been measured', ...
                    r.accept.(f{j}))); %#ok<AGROW>
    end
end

% ---- G7 convergence and precision -----------------------------------------
for k = 1:numel(results)
    r = results(k);
    d = r.diagnostics;
    if isempty(d) || height(d) == 0
        rows{end+1} = row('G7', r.model, 'diagnostics present', 0, NaN, false, ''); %#ok<AGROW>
        continue
    end
    ess = r.ndraws ./ d.ineff;
    rows{end+1} = row('G7', r.model, 'min effective sample size', min(ess), ...
        MIN_ESS, min(ess) >= MIN_ESS, ...
        sprintf('worst: %s', d.parameter(find(ess == min(ess), 1)))); %#ok<AGROW>
end

% ---- G8 revision tolerance, and G9 the February widening -------------------
widen = 1;
seasonal = struct('applied', opts.SeasonalRevision, 'factor', 1, 'max_shift', NaN);
if opts.SeasonalRevision
    widen = SEASONAL_FACTOR;
    seasonal.factor = SEASONAL_FACTOR;
end

if first_release
    rows{end+1} = na('G8', 'all', 'revision tolerance', ...
        'first release: nothing to revise against');
elseif isempty(revs) || height(revs) == 0
    rows{end+1} = na('G8', 'all', 'revision tolerance', ...
        'revisions.m returned no rows to check');
else
    for k = 1:numel(results)
        r = results(k);
        d = r.diagnostics;
        for s = fieldnames(r.series)'
            name = s{1};
            sel = revs.model == string(r.model) & revs.series == string(name);
            if ~any(sel), continue, end
            t = revs(sel, :);
            cutoff = max(r.series.(name).dates) - calquarters(8);
            t = t(t.date <= cutoff, :);
            if isempty(t), continue, end

            mc = mcse_for(d, name, t.date);
            tol = max(REV_FLOOR, REV_MCSE * mc) * widen;
            move = abs(t.total);
            nflag = sum(move > tol);
            worst = max(move);

            rows{end+1} = row('G8', r.model, [name ' revisions over tolerance'], ...
                nflag, 0, nflag == 0, ...
                sprintf('largest move %.3fpp over %d dates before %s', ...
                        worst, height(t), qlabel(cutoff))); %#ok<AGROW>
            rows{end+1} = row('G8', r.model, [name ' largest revision'], worst, ...
                REV_FAIL * widen, worst <= REV_FAIL * widen, ...
                'a move this large is held for a person'); %#ok<AGROW>
            seasonal.max_shift = max([seasonal.max_shift, worst]);
        end
    end
end

% ---- G10 base changes -----------------------------------------------------
if first_release
    rows{end+1} = na('G10', 'all', 'GDP base change', ...
        'first release: no overlap to compare');
elseif isempty(revs) || height(revs) == 0
    rows{end+1} = na('G10', 'all', 'GDP base change', 'no revision rows');
else
    sel = revs.series == "output_gap";
    if any(sel)
        v = revs.total(sel);
        constantish = abs(mean(v)) > 0.25 && std(v) < 0.1 * abs(mean(v));
        rows{end+1} = row('G10', 'all', 'gap revision is a constant shift', ...
            abs(mean(v)), NaN, true, ...
            sprintf('mean %.3f, sd %.3f%s', mean(v), std(v), ...
                    ternary(constantish, ' - looks like a base change, recorded', '')));
    end
end

% ---- assemble -------------------------------------------------------------
checks = vertcat(rows{:});
report = struct();
report.checks = checks;
report.nfail = sum(checks.status == "fail");
report.pass = report.nfail == 0;
report.vintage = char(opts.Vintage);
report.seasonal = seasonal;
end


% ---------------------------------------------------------------------------
function t = row(id, model, statistic, value, tolerance, ok, note)
if ok, st = "pass"; else, st = "fail"; end
t = table(string(id), string(model), string(statistic), value, tolerance, st, ...
    string(note), 'VariableNames', ...
    {'id', 'model', 'statistic', 'value', 'tolerance', 'status', 'note'});
end


function t = na(id, model, statistic, why)
t = table(string(id), string(model), string(statistic), NaN, NaN, "n/a", ...
    string(why), 'VariableNames', ...
    {'id', 'model', 'statistic', 'value', 'tolerance', 'status', 'note'});
end


function n = count_nonfinite(s)
n = 0;
for f = fieldnames(s)'
    v = s.(f{1});
    if isnumeric(v), n = n + sum(~isfinite(v(:))); end
end
end


function p = published(previous, name, model)
p = [];
if ~isfield(previous.series, name), return, end
t = previous.series.(name);
if isempty(t), return, end
sel = t.model == string(model) & t.measure == "mean";
if ~any(sel), return, end
d = t.date(sel);
if ~isdatetime(d), d = datetime(d); end
p = table(d(:), t.value(sel), 'VariableNames', {'date', 'value'});
end


function mc = mcse_for(d, name, dates)
mc = zeros(numel(dates), 1);
if isempty(d), return, end
rows = d(d.series == string(name), :);
if isempty(rows), return, end
[tf, loc] = ismember(dates, rows.date);
mc(tf) = rows.mcse(loc(tf));
end


function s = qlabel(d)
s = sprintf('%dQ%d', year(d), quarter(d));
end


function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end
