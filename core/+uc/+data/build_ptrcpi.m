function [tbl, parts] = build_ptrcpi(ptr, spf, varargin)
% uc.data.build_ptrcpi - long-run CPI inflation expectations, 1960Q1 onward.
%
%   tbl           = uc.data.build_ptrcpi(ptr, spf)
%   [tbl, parts]  = uc.data.build_ptrcpi(ptr, spf, 'Start', '1960Q1')
%
% ptr is the table from uc.data.fetch_frbus_ptr, spf the table from
% uc.data.fetch_spf_cpi10. Returns one quarterly series, and parts records which
% source each quarter came from so a release can archive the decomposition.
%
% biuc_lrexp needs a long-run CPI expectation running back to 1960 and no published
% series covers that span, so three pieces are joined:
%
%   1960Q1 - 1967Q4   flat at PTR's own first value, plus the wedge
%   1968Q1 - 2005Q4   FRB/US PTR, plus the wedge
%   2006Q1 onward     SPF median CPI10, directly
%
% PTR is an expectation of PCE inflation and this series is about CPI inflation,
% which runs persistently higher. WEDGE, default 0.4, is the long-run gap: a
% constant, as in the published construction.
%
% The backfill length is computed from the data. HISTDATA.TXT starts PTR at 1968Q1,
% so the flat span is 1960Q1 through 1967Q4, and the SPF cannot supply those
% quarters instead - it did not ask the ten-year CPI question before 1991Q4.
%
% The splice is continuous by construction: the Board builds PTR from the same
% survey over the overlap, and PTR + 0.4 matches the SPF median CPI10 to the
% printed precision from 2003Q2 through 2006Q4, so the choice of 2006Q1 is not
% delicate and a step there is worth checking for.
%
% The flat backfill is a strong assumption: it asserts that long-run expectations
% were constant through the 1960s, across the years they were in fact beginning to
% move. It is what the published construction does, and parts makes those quarters
% identifiable for anyone who wants to start the model in 1968Q1.

p = inputParser;
p.addParameter('Start', '1960Q1');
p.addParameter('Wedge', 0.4, @(x) isnumeric(x) && isscalar(x));
p.addParameter('SpliceDate', '2006Q1');
p.parse(varargin{:});

wedge = p.Results.Wedge;
first = to_quarter_start(p.Results.Start);
splice = to_quarter_start(p.Results.SpliceDate);

check_table(ptr, 'ptr');
check_table(spf, 'spf');

if ptr.date(1) > first
    % Expected: this is what the backfill exists for.
elseif ptr.date(1) < first
    ptr = ptr(ptr.date >= first, :);
end

if splice <= ptr.date(1)
    error('uc:data:spliceBeforePTR', ...
        ['the splice date %s is at or before PTR''s first quarter %s, which ' ...
         'leaves PTR contributing nothing.'], label(splice), label(ptr.date(1)));
end

early = spf.date(spf.date >= splice);
if isempty(early)
    error('uc:data:spfTooShort', ...
        ['the SPF series ends at %s, before the splice date %s, so nothing ' ...
         'covers the recent span.'], label(spf.date(end)), label(splice));
end

last = max(ptr.date(end), spf.date(end));
axis_ = (first:calquarters(1):last)';
value = nan(size(axis_));
source = strings(size(axis_));

% 1. PTR + wedge, through the quarter before the splice.
[tf, loc] = ismember(axis_, ptr.date);
use = tf & axis_ < splice;
value(use) = ptr.value(loc(use)) + wedge;
source(use) = "PTR+wedge";

% 2. SPF from the splice onward.
[tf, loc] = ismember(axis_, spf.date);
use = tf & axis_ >= splice;
value(use) = spf.value(loc(use));
source(use) = "SPF";

% 3. Flat backfill over the quarters before PTR begins, at PTR's own first value.
pre = axis_ < ptr.date(1);
if any(pre)
    value(pre) = ptr.value(1) + wedge;
    source(pre) = "backfill";
end

if any(isnan(value))
    gap = find(isnan(value), 1);
    error('uc:data:gapInSplice', ...
        ['no source covers %s. The pieces do not meet: PTR runs %s to %s and ' ...
         'the SPF runs %s to %s.'], label(axis_(gap)), ...
        label(ptr.date(1)), label(ptr.date(end)), ...
        label(spf.date(1)), label(spf.date(end)));
end

tbl = table(axis_, value, 'VariableNames', {'date', 'value'});
tbl.Properties.UserData = struct( ...
    'series',       'PTRCPI', ...
    'wedge',        wedge, ...
    'splice',       label(splice), ...
    'backfill_n',   sum(pre), ...
    'backfill_to',  label(ptr.date(1) - calquarters(1)), ...
    'ptr_first',    ptr.value(1), ...
    'built',        datetime('now', 'TimeZone', 'UTC'));

parts = table(axis_, source, 'VariableNames', {'date', 'source'});
end

% -------------------------------------------------------------------------

function check_table(t, name)
if ~istable(t) || ~all(ismember({'date', 'value'}, t.Properties.VariableNames))
    error('uc:data:badTable', '%s must be a table with date and value columns.', name);
end
if height(t) < 2
    error('uc:data:tooShort', '%s has %d rows.', name, height(t));
end
end

function d = to_quarter_start(x)
if isdatetime(x)
    d = dateshift(x(1), 'start', 'quarter');
    return
end
tok = regexp(strtrim(char(x)), '^(\d{4})[Qq]([1-4])$', 'tokens', 'once');
if isempty(tok)
    error('uc:data:badQuarter', ...
        '''%s'' is not a quarter. Write it as YYYYQq, for example 1960Q1.', char(x));
end
d = datetime(str2double(tok{1}), 3 * str2double(tok{2}) - 2, 1);
end

function s = label(d)
s = sprintf('%dQ%d', year(d), quarter(d));
end
