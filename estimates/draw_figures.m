% draw_figures - one figure per published series, drawn from the published CSVs.
%
%   files = draw_figures(csvdir, vintage, outdir)
%
% Reads trend_inflation.csv, output_gap.csv and trend_growth.csv from csvdir and
% writes a PNG and a PDF of each to outdir. Returns the files written.
%
% Each figure shows the posterior mean of every model that produces the series, with
% its 90 percent credible interval as a band in the same color. The figures are
% drawn from the CSVs rather than from the draws, so a figure can only show numbers
% that were published, and a figure can be redrawn from any vintage without
% re-estimating anything.
%
% A model keeps its color in every figure and every vintage: the color is fixed by
% its place in the model list below, whichever models a CSV holds. The colors are
% the first four slots of the reference categorical palette, in its fixed order,
% which pass its colorblind and normal-vision separation checks for line charts.

function files = draw_figures(csvdir, vintage, outdir)

arguments
    csvdir {mustBeTextScalar}
    vintage {mustBeTextScalar}
    outdir {mustBeTextScalar}
end

if ~isfolder(outdir), mkdir(outdir); end

SERIES = {
    'trend_inflation', 'Trend inflation, PCE', 'percent, annualized', ...
        {'ucsv_sw07', 'ar_trend_bound', 'biuc_lrexp', 'uc_ma'}
    'output_gap',      'Output gap',           'percent of trend output', ...
        {'uc_2m', 'ucur_break2'}
    'trend_growth',    'Trend output growth',  'percent, annualized', ...
        {'uc_2m'}
    };

NAMES = containers.Map( ...
    {'ucsv_sw07', 'ar_trend_bound', 'biuc_lrexp', 'uc_ma', 'uc_2m', 'ucur_break2'}, ...
    {'Stock and Watson (2007)', 'Chan, Koop and Potter (2013)', ...
     'Chan, Clark and Koop (2018)', 'Chan (2013)', 'Grant and Chan (2017, JEDC)', ...
     'Grant and Chan (2017, JMCB)'});

COLORS = hex2rgb({'#2a78d6', '#eb6834', '#1baf7a', '#eda100'});
INK = hex2rgb({'#0b0b0b'});   SECONDARY = hex2rgb({'#52514e'});
MUTED = hex2rgb({'#898781'}); GRID = hex2rgb({'#e1e0d9'});
BASELINE = hex2rgb({'#c3c2b7'});

files = {};
for s = 1:size(SERIES, 1)
    name = SERIES{s, 1};
    f = fullfile(csvdir, [name '.csv']);
    if ~isfile(f), continue, end
    t = readtable(f, 'TextType', 'string');
    if ~isdatetime(t.date), t.date = datetime(t.date); end

    order = SERIES{s, 4};
    slot = find(ismember(order, unique(t.model)));
    order = order(slot);
    if isempty(order), continue, end

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 960 480]);
    ax = axes(fig, 'Color', 'w'); hold(ax, 'on');

    % Bands first, so no line is drawn under another model's band.
    for k = 1:numel(order)
        [d, ~, lo, hi] = series_of(t, order{k});
        fill(ax, [d; flipud(d)], [lo; flipud(hi)], COLORS(slot(k), :), ...
            'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    yline(ax, 0, '-', 'Color', BASELINE, 'LineWidth', 0.75, 'HandleVisibility', 'off');
    h = gobjects(numel(order), 1);
    for k = 1:numel(order)
        [d, m] = series_of(t, order{k});
        h(k) = plot(ax, d, m, 'Color', COLORS(slot(k), :), 'LineWidth', 1.25, ...
            'DisplayName', NAMES(order{k}));
    end

    set(ax, 'Box', 'off', 'TickDir', 'out', 'LineWidth', 0.75, ...
        'XColor', MUTED, 'YColor', MUTED, 'FontSize', 10, ...
        'XGrid', 'off', 'YGrid', 'on', 'GridColor', GRID, 'GridAlpha', 1, ...
        'GridLineStyle', '-');
    ax.XAxis.TickLabelColor = SECONDARY;
    ax.YAxis.TickLabelColor = SECONDARY;
    xlim(ax, [min(t.date) max(t.date)]);
    ylabel(ax, SERIES{s, 3}, 'Color', SECONDARY);

    % The axes lay out the title block themselves; positioning it by hand collides
    % with the legend and clips at the top edge.
    ax.TitleHorizontalAlignment = 'left';
    title(ax, SERIES{s, 2}, 'Color', INK, 'FontWeight', 'bold', 'FontSize', 13);
    if isscalar(order)
        sub = sprintf('%s. Posterior mean and 90%% credible interval, vintage %s.', ...
            NAMES(order{1}), vintage);
    else
        sub = sprintf('Posterior means and 90%% credible intervals, vintage %s.', vintage);
    end
    subtitle(ax, sub, 'Color', SECONDARY, 'FontSize', 10);

    % A lone series is named by the subtitle, so it gets no legend box. Otherwise
    % the legend goes below the plot, clear of the title block.
    if ~isscalar(order)
        lg = legend(ax, h, 'Location', 'southoutside', 'Orientation', 'horizontal', ...
            'Box', 'off', 'TextColor', INK, 'FontSize', 10);
        lg.ItemTokenSize = [18 18];
    end

    for ext = {'png', 'pdf'}
        p = fullfile(outdir, [name '.' ext{1}]);
        if strcmp(ext{1}, 'png')
            exportgraphics(fig, p, 'Resolution', 150, 'BackgroundColor', 'white');
        else
            exportgraphics(fig, p, 'ContentType', 'vector', 'BackgroundColor', 'white');
        end
        files{end+1} = p; %#ok<AGROW>
    end
    close(fig);
end
files = files(:);
end


% ---------------------------------------------------------------------------
function [d, m, lo, hi] = series_of(t, model)
% The mean and the 5th and 95th percentiles for one model, on a common date axis.
sel = t.model == string(model);
u = t(sel, :);
d = unique(u.date);
pick = @(meas) lookup(u(u.measure == meas, :), d);
m  = pick("mean");
lo = pick("p05");
hi = pick("p95");
end


function v = lookup(u, d)
v = nan(numel(d), 1);
[tf, loc] = ismember(d, u.date);
v(tf) = u.value(loc(tf));
end


function rgb = hex2rgb(h)
rgb = zeros(numel(h), 3);
for k = 1:numel(h)
    s = char(h{k});
    s = s(end-5:end);
    rgb(k, :) = [hex2dec(s(1:2)) hex2dec(s(3:4)) hex2dec(s(5:6))] / 255;
end
end
