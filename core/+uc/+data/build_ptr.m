function [tbl, parts] = build_ptr(ptr, varargin)
% uc.data.build_ptr - long-run PCE inflation expectations, backfilled to 1960Q1.
%
%   tbl          = uc.data.build_ptr(ptr)
%   [tbl, parts] = uc.data.build_ptr(ptr, 'Start', '1960Q1')
%
% ptr is the table from uc.data.fetch_frbus_ptr. Returns one quarterly series from
% the requested start, and parts records which quarters are observed and which are
% backfilled.
%
% HISTDATA.TXT starts PTR at 1968Q1 and biuc_lrexp starts in 1960Q1, so the head is
% held flat at PTR's own first value. Both the span and the value are computed from
% the data, so neither can drift. This reproduces what the published package does:
% the two agree to 0.005 over all 225 quarters cck1_data.xlsx ships.
%
% A flat backfill is a strong assumption - it asserts that long-run expectations
% were constant through the 1960s, across the years they were beginning to move.
% parts makes those quarters identifiable for anyone who wants to start in 1968Q1.
%
% No wedge and no splice: PTR is already in PCE terms and biuc_lrexp is estimated
% on PCE inflation. sources.md says why.

opts = struct('Start', '1960Q1');
for k = 1:2:numel(varargin)
    name = validatestring(varargin{k}, fieldnames(opts), 'build_ptr');
    opts.(name) = varargin{k+1};
end

if ~istable(ptr) || ~all(ismember({'date', 'value'}, ptr.Properties.VariableNames))
    error('uc:data:build_ptr:badInput', ...
        'ptr must be the table from uc.data.fetch_frbus_ptr, with date and value columns.');
end

start = quarter_start(opts.Start);
first = ptr.date(1);

if start > first
    error('uc:data:build_ptr:startAfterPtr', ...
        ['Start %s is after PTR''s own first quarter %s. This function backfills ' ...
         'the head; it does not trim it.'], opts.Start, label(first));
end

pad = (start:calquarters(1):first - calquarters(1))';
tbl = table([pad; ptr.date], [repmat(ptr.value(1), numel(pad), 1); ptr.value], ...
    'VariableNames', {'date', 'value'});
parts = table(tbl.date, [repmat("backfill", numel(pad), 1); ...
                         repmat("PTR", height(ptr), 1)], ...
    'VariableNames', {'date', 'source'});

tbl.Properties.UserData = struct( ...
    'backfill_quarters', numel(pad), ...
    'backfill_value', ptr.value(1), ...
    'ptr_first', label(first), ...
    'ptr_last', label(ptr.date(end)));
end


% ---------------------------------------------------------------------------
function d = quarter_start(s)
s = char(s);
if isempty(regexp(s, '^\d{4}Q[1-4]$', 'once'))
    error('uc:data:build_ptr:badQuarter', '"%s" is not a quarter of the form YYYYQq.', s);
end
d = datetime(str2double(s(1:4)), 3*(str2double(s(6)) - 1) + 1, 1);
end


function s = label(d)
s = sprintf('%dQ%d', year(d), quarter(d));
end
