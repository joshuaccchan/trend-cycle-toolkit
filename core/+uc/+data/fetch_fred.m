function tbl = fetch_fred(seriesId, freq, opts)
% uc.data.fetch_fred - one FRED series as a quarterly table of levels.
%
%   tbl = uc.data.fetch_fred('CPIAUCSL', 'Quarterly')
%   tbl = uc.data.fetch_fred('GDPC1')            % already quarterly at source
%
% Returns a table of date (datetime, quarter start as FRED labels it) and value
% (double, the published level, untransformed). Levels are what a release archives,
% and what a later run diffs against to attribute a revision to the data rather
% than to the sample.
%
% freq is spelled as FRED spells it - 'Quarterly' - and passed through verbatim;
% fam=avg averages the months within the quarter. Omit freq for a series FRED
% already publishes quarterly. The endpoint needs no API key:
%
%   https://fred.stlouisfed.org/graph/fredgraph.csv?id=<ID>&fq=<FREQ>&fam=avg
%
% 'File' parses a CSV already on disk instead of fetching, so the parser and its
% guards can be exercised without a network and an archived vintage re-read.
%
% NO VINTAGE ACCESS. fredgraph.csv silently IGNORES a vintage_date parameter, so
% archiving each release's raw fetch is the only vintage record there is.
%
% THREE FAILURES THIS GUARDS AGAINST, all observed:
%   1. The running quarter comes back as a PRESENT row with an EMPTY value. Parsed
%      naively it becomes NaN and a log difference propagates it. This returns the
%      row; uc.data.drop_incomplete_tail removes it.
%   2. An error page served with HTTP 200. Status is not evidence, so the response
%      must begin with the observation_date header FRED actually sends.
%   3. MATLAB's HTTP stack hangs without a User-Agent, for sixty seconds and then a
%      timeout that reads like a network fault. One is always set.

arguments
    seriesId (1,:) char
    freq (1,:) char = ''
    opts.File (1,:) char = ''
end

url = sprintf('https://fred.stlouisfed.org/graph/fredgraph.csv?id=%s', seriesId);
if ~isempty(freq)
    url = sprintf('%s&fq=%s&fam=avg', url, freq);
end

if isempty(opts.File)
    try
        raw = webread(url, weboptions('Timeout', 60, 'ContentType', 'text', ...
            'UserAgent', 'trend-cycle-toolkit (https://github.com/joshuaccchan/trend-cycle-toolkit)'));
    catch err
        error('uc:data:fetchFailed', ...
            'fetching %s from FRED failed: %s', seriesId, err.message);
    end
else
    raw = fileread(opts.File);
    url = opts.File;
end

% Content check before parsing. An HTML error page served with HTTP 200 parses
% into a table of nonsense rather than failing, which is the worse outcome.
if ~startsWith(strtrim(raw), 'observation_date')
    error('uc:data:notACsv', ...
        ['the response for %s does not begin with the observation_date header ' ...
         'FRED sends. The first 80 characters were:\n  %s'], ...
        seriesId, strtrim(extractBefore(raw, min(81, strlength(raw) + 1))));
end

lines = splitlines(strtrim(raw));
n = numel(lines) - 1;
date = NaT(n, 1);
value = nan(n, 1);

for i = 1:n
    parts = split(string(lines{i + 1}), ',');
    date(i) = datetime(parts(1), 'InputFormat', 'yyyy-MM-dd');
    v = strtrim(parts(2));
    if strlength(v) > 0          % empty = the running quarter, kept as NaN
        value(i) = str2double(v);
    end
end

if any(isnan(value(1:max(0, n - 1))))
    bad = find(isnan(value(1:n - 1)), 1);
    error('uc:data:interiorGap', ...
        ['%s has an empty value at %s, which is inside the sample rather than ' ...
         'at its end. A gap in the middle is a source problem, not a running ' ...
         'quarter, and it is not this function''s to paper over.'], ...
        seriesId, string(date(bad), 'yyyy-MM-dd'));
end

tbl = table(date, value, 'VariableNames', {'date', 'value'});
tbl.Properties.UserData = struct( ...
    'series',  seriesId, ...
    'url',     url, ...
    'fetched', datetime('now', 'TimeZone', 'UTC'));
end
