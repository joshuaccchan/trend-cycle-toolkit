% publish - write a release into the staging tree, and promote it if it passed.
%
%   files = publish(results, report, revs, manifest, stagedir, 'Vintage', v)
%   files = publish(results, report, revs, manifest, stagedir, 'Vintage', v, ...
%                   'Promote', true)
%
% The five positional arguments are everything a release consists of: the output of
% run_estimates, guardrails, revisions, uc.data.vintage_stamp, and the staging
% directory run_release made. All five are required. Returns the files written, in
% write order.
%
% OPTIONS
%   'Vintage'  'YYYYQq', required. Passed in, never parsed out of the staging path.
%   'Promote'  logical, default false. False writes the staging tree and stops;
%              true copies it into the tracked tree.
%   'Mode'     'local' (default) or 'cloud-backup'. Changes nothing about which
%              files are written, and records in metadata.json that a cloud run
%              came off a hosted runner.
%   'Dest'     where a promoted release lands. Default: this repository's
%              estimates/. A test points it at a scratch directory; a release
%              never passes it.
%
% THE GATE. publish refuses to promote unless report.pass is true, whatever
% 'Promote' says. It still writes the staging tree, which is how a refused release
% is inspected.
%
% WHAT IT WRITES, under current/ and frozen into vintages/YYYYQq/:
%
%   trend_inflation.csv        tidy: date, model, measure, value, with measure in
%   output_gap.csv             {mean, p05, p16, p84, p95, mcse}
%   trend_growth.csv
%   trend_inflation_wide.csv   date, then one model to a column, ragged at the head
%   diagnostics.csv            inefficiency factor and MCSE per parameter and date,
%                              with Geweke Z on the scalar parameters and selected dates
%   guardrails.csv             the check table, written pass or fail
%   trend_cycle_estimates.xlsx the three series in one workbook
%   metadata.json              vintage, run time, git SHA, per-series URL, fetch
%                              time and SHA-256, seed and settings per model
%
% The fetched inputs go to sources/, with a copy frozen inside the vintage, so a
% vintage folder holds both the numbers and the data they came from.
%
% revisions/YYYYQq.csv is written once and never rewritten, and not at all for the
% first release. figures/ holds a PNG and a PDF per series, committed on purpose.
%
% Workbook columns are ragged because models start at different dates, and every
% offset is derived from the series' own dates. The CSVs are what is published.
%
% NAME CLASH, DELIBERATE. MATLAB ships a built-in publish. setup.m leaves
% estimates/ off the path; run_release adds it for one run.

function files = publish(results, report, revs, manifest, stagedir, opts)

arguments
    results (1,:) struct
    report (1,1) struct
    revs
    manifest
    stagedir {mustBeTextScalar}
    opts.Vintage {mustBeTextScalar} = ''
    opts.Promote (1,1) logical = false
    opts.Mode {mustBeTextScalar} = 'local'
    opts.Dest {mustBeTextScalar} = ''
end

if isempty(opts.Vintage)
    error('uc:estimates:publish:noVintage', ...
        'Vintage is required. It names the frozen folder and is stamped into metadata.json.');
end
vintage = char(opts.Vintage);
stagedir = char(stagedir);

cur = fullfile(stagedir, 'current');
vin = fullfile(stagedir, 'vintages', vintage);
fig = fullfile(stagedir, 'figures', 'current');
figv = fullfile(stagedir, 'figures', 'vintages', vintage);
for d = {cur, vin, fig, figv, fullfile(stagedir, 'revisions')}
    if ~isfolder(d{1}), mkdir(d{1}); end
end

files = {};

% ---- the three published series, tidy -------------------------------------
for s = {'trend_inflation', 'output_gap', 'trend_growth'}
    t = tidy_series(results, s{1});
    if isempty(t), continue, end
    files{end+1} = write_csv(t, fullfile(cur, [s{1} '.csv'])); %#ok<AGROW>
end

% ---- one wide file, for the series with three models ----------------------
w = wide_series(results, 'trend_inflation');
if ~isempty(w)
    files{end+1} = write_csv(w, fullfile(cur, 'trend_inflation_wide.csv'));
end

% ---- diagnostics and the guardrail report --------------------------------
diagnostics = vertcat(results.diagnostics);
files{end+1} = write_csv(diagnostics, fullfile(cur, 'diagnostics.csv'));
files{end+1} = write_csv(report.checks, fullfile(cur, 'guardrails.csv'));

% ---- the workbook ---------------------------------------------------------
files{end+1} = write_workbook(results, vintage, fullfile(cur, 'trend_cycle_estimates.xlsx'));

% ---- metadata -------------------------------------------------------------
files{end+1} = write_metadata(results, report, manifest, vintage, opts.Mode, ...
                              fullfile(cur, 'metadata.json'));

% ---- figures --------------------------------------------------------------
files = [files, draw_figures(results, vintage, fig)];

% ---- the revision table, from the second release onward -------------------
if ~isempty(revs) && height(revs) > 0
    files{end+1} = write_csv(revs, fullfile(stagedir, 'revisions', [vintage '.csv']));
end

% ---- freeze ---------------------------------------------------------------
copyfile(fullfile(cur, '*'), vin);
copyfile(fullfile(fig, '*'), figv);
files{end+1} = vin;
files{end+1} = figv;

% ---- the gate -------------------------------------------------------------
if opts.Promote
    if ~report.pass
        error('uc:estimates:publish:refused', ...
            ['refusing to promote %s: %d guardrail check(s) failed. The staging ' ...
             'tree is at %s and holds the numbers and the report; nothing was ' ...
             'copied into estimates/.'], vintage, report.nfail, stagedir);
    end
    dest = char(opts.Dest);
    if isempty(dest)
        dest = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'estimates');
    end
    promote(stagedir, dest, vintage);
    files{end+1} = dest;
end

files = files(:);
end


% ---------------------------------------------------------------------------
function t = tidy_series(results, name)
% date, model, measure, value - one block per model that produces this series.
blocks = {};
for k = 1:numel(results)
    r = results(k);
    if ~isfield(r.series, name), continue, end
    s = r.series.(name);
    m = s.summary;
    mc = mcse_for(r.diagnostics, name, s.dates);
    nd = numel(s.dates);
    measures = {'mean', 'p05', 'p16', 'p84', 'p95', 'mcse'};
    vals = [m.mean, m.p05, m.p16, m.p84, m.p95, mc];
    for j = 1:numel(measures)
        blocks{end+1} = table(s.dates, repmat(string(r.model), nd, 1), ...
            repmat(string(measures{j}), nd, 1), vals(:, j), ...
            'VariableNames', {'date', 'model', 'measure', 'value'}); %#ok<AGROW>
    end
end
if isempty(blocks), t = table(); return, end
t = sortrows(vertcat(blocks{:}), {'model', 'measure', 'date'});
end


function w = wide_series(results, name)
% date down the first column, one model beside it, ragged at the head.
cols = {}; names = {}; alldates = NaT(0, 1);
for k = 1:numel(results)
    if ~isfield(results(k).series, name), continue, end
    s = results(k).series.(name);
    cols{end+1} = s; names{end+1} = results(k).model; %#ok<AGROW>
    alldates = union(alldates, s.dates);
end
if isempty(cols), w = table(); return, end
alldates = sort(alldates(:));
w = table(alldates, 'VariableNames', {'date'});
for k = 1:numel(cols)
    v = nan(numel(alldates), 1);
    [tf, loc] = ismember(cols{k}.dates, alldates);
    v(loc(tf)) = cols{k}.summary.mean(tf);
    w.(names{k}) = v;
end
end


function mc = mcse_for(diagnostics, name, dates)
% The MCSE column for one series, matched date by date rather than by position.
mc = nan(numel(dates), 1);
if isempty(diagnostics), return, end
rows = diagnostics(diagnostics.series == string(name), :);
if isempty(rows), return, end
[tf, loc] = ismember(dates, rows.date);
mc(tf) = rows.mcse(loc(tf));
end


function p = write_csv(t, p)
if isempty(t) || height(t) == 0, return, end
writetable(t, p);
end


function p = write_workbook(results, vintage, p)
% One sheet per series, a title row, then dates and one model to a column.
if isfile(p), delete(p); end
for s = {'trend_inflation', 'output_gap', 'trend_growth'}
    w = wide_series(results, s{1});
    if isempty(w), continue, end
    title = sprintf('%s, posterior mean, vintage %s', strrep(s{1}, '_', ' '), vintage);
    writecell({title}, p, 'Sheet', s{1}, 'Range', 'A1');
    writetable(w, p, 'Sheet', s{1}, 'Range', 'A2');
end
end


function p = write_metadata(results, report, manifest, vintage, mode, p)
meta = struct();
meta.vintage = vintage;
meta.generated_utc = char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
meta.git_sha = git_sha();
meta.mode = mode;
if strcmp(mode, 'cloud-backup')
    meta.mode_note = ['produced on a hosted runner, not the release machine; ' ...
                      'not byte-identical to a local run'];
end
meta.guardrails = struct('pass', report.pass, 'nfail', report.nfail, ...
                         'seasonal', report.seasonal);

m = struct([]);
for k = 1:numel(results)
    r = results(k);
    e = struct();
    e.model = r.model;
    e.seed = r.seed;
    e.sample_start = r.sample_start;
    e.sample_end = r.sample_end;
    e.ndraws = r.ndraws;
    e.elapsed_seconds = r.elapsed;
    e.series = fieldnames(r.series)';
    e.settings = rmfield(r.settings, intersect({'cites'}, fieldnames(r.settings)));
    e.cites = r.settings.cites;
    e.accept = r.accept;
    e.versions = r.versions;
    m = [m, e]; %#ok<AGROW>
end
meta.models = m;
meta.sources = manifest;

fid = fopen(p, 'w');
fprintf(fid, '%s\n', jsonencode(meta, 'PrettyPrint', true));
fclose(fid);
end


function out = draw_figures(results, vintage, dir)
% One figure per series: the posterior mean and the 90 per cent band per model.
out = {};
for s = {'trend_inflation', 'output_gap', 'trend_growth'}
    name = s{1};
    have = arrayfun(@(r) isfield(r.series, name), results);
    if ~any(have), continue, end
    f = figure('Visible', 'off', 'Position', [100 100 900 450]);
    ax = axes(f); hold(ax, 'on'); %#ok<LAXES>
    for k = find(have)
        ser = results(k).series.(name);
        m = ser.summary;
        fill(ax, [m.date; flipud(m.date)], [m.p05; flipud(m.p95)], [0.6 0.7 0.85], ...
            'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        plot(ax, m.date, m.mean, 'LineWidth', 1.2, 'DisplayName', ...
            strrep(results(k).model, '_', '\_'));
    end
    yline(ax, 0, ':', 'HandleVisibility', 'off');
    title(ax, sprintf('%s, vintage %s', strrep(name, '_', ' '), vintage));
    ylabel(ax, 'per cent, annualized'); legend(ax, 'Location', 'best'); box(ax, 'on');
    for ext = {'png', 'pdf'}
        p = fullfile(dir, [name '.' ext{1}]);
        exportgraphics(ax, p, 'Resolution', 150);
        out{end+1} = p; %#ok<AGROW>
    end
    close(f);
end
end


function promote(stagedir, dest, vintage)
% Copy the staging tree into the tracked tree. current/ and figures/current/ are
% overwritten each quarter; the frozen vintage is written once.
copyfile(fullfile(stagedir, 'current'), fullfile(dest, 'current'));
copyfile(fullfile(stagedir, 'figures', 'current'), fullfile(dest, 'figures', 'current'));

% The fetched inputs travel with the estimates. metadata.json records a SHA-256
% per series, and without the files beside it that hash refers to nothing: the
% staging tree is git-ignored and the next run deletes it.
copyfile(fullfile(stagedir, 'sources'), fullfile(dest, 'sources'));

v = fullfile(dest, 'vintages', vintage);
if isfolder(v)
    error('uc:estimates:publish:vintageExists', ...
        ['%s already exists. A frozen vintage is written once and never ' ...
         'touched again; re-running a published quarter would rewrite the ' ...
         'archive a revision is measured against.'], v);
end
copyfile(fullfile(stagedir, 'vintages', vintage), v);
copyfile(fullfile(stagedir, 'sources'), fullfile(v, 'sources'));
copyfile(fullfile(stagedir, 'figures', 'vintages', vintage), ...
         fullfile(dest, 'figures', 'vintages', vintage));

rf = fullfile(stagedir, 'revisions', [vintage '.csv']);
if isfile(rf)
    if ~isfolder(fullfile(dest, 'revisions')), mkdir(fullfile(dest, 'revisions')); end
    copyfile(rf, fullfile(dest, 'revisions', [vintage '.csv']));
end
end


function sha = git_sha()
% Run git against the repository, never against whatever directory the caller
% happens to be sitting in.
root = fileparts(fileparts(mfilename('fullpath')));
[st, out] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st == 0
    sha = strtrim(out);
else
    sha = 'unknown';
end
end
