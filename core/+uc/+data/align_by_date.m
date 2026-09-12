function [out, span] = align_by_date(src, varargin)
% uc.data.align_by_date - put several series on one gapless quarterly axis.
%
%   [out, span] = uc.data.align_by_date(src)
%   [out, span] = uc.data.align_by_date(src, 'Start', '1960Q1')
%
% src is a struct whose fields are series tables, each with date and value columns.
% out has the same field names, each a column vector, all the same length and all
% on the axis span.date. span also carries first and last as 'YYYYQq'.
%
% The default span is the INTERSECTION of the inputs, so every returned column is
% complete and no model is handed a NaN. 'Start' asks for a later start and errors
% when the data cannot reach it, which is how run_estimates asserts each model's
% configured sample start.
%
% The axis is checked here to be gapless and running forward. Two things depend on
% that: resolve_break_dates turns break quarters into ROW INDICES, so a missing
% quarter moves every break after it, and uc.data.annualized_log_diff differences
% adjacent rows, which is a quarterly rate only when the rows are adjacent quarters.

p = inputParser;
p.addParameter('Start', '', @(x) ischar(x) || isstring(x) || isdatetime(x));
p.parse(varargin{:});
startReq = p.Results.Start;

names = fieldnames(src);
if isempty(names)
    error('uc:data:noSeries', 'src has no fields, so there is nothing to align.');
end

first = NaT; last = NaT;
for k = 1:numel(names)
    t = src.(names{k});
    if ~istable(t) || ~all(ismember({'date', 'value'}, t.Properties.VariableNames))
        error('uc:data:badTable', ...
            'src.%s is not a table with date and value columns.', names{k});
    end
    check_axis(t.date, names{k});
    if isnat(first) || t.date(1) > first
        first = t.date(1);
    end
    if isnat(last) || t.date(end) < last
        last = t.date(end);
    end
end

if ~isempty(startReq)
    req = to_quarter_start(startReq);
    if req < first
        error('uc:data:startTooEarly', ...
            ['a start of %s was asked for, but the series that begins latest ' ...
             'begins at %s.'], label(req), label(first));
    end
    first = req;
end

if first > last
    error('uc:data:emptyIntersection', ...
        ['these series do not overlap: the latest start is %s and the earliest ' ...
         'end is %s.'], label(first), label(last));
end

axis_ = (first:calquarters(1):last)';
out = struct();
for k = 1:numel(names)
    t = src.(names{k});
    [tf, loc] = ismember(axis_, t.date);
    if ~all(tf)
        error('uc:data:cannotAlign', ...
            ['%s does not cover every quarter of the common span %s to %s, even ' ...
             'though its own axis is gapless. That means two series disagree ' ...
             'about which day labels a quarter.'], names{k}, label(first), label(last));
    end
    out.(names{k}) = t.value(loc);
end

span = struct('date', axis_, 'first', label(first), 'last', label(last), ...
              'n', numel(axis_));
end

% -------------------------------------------------------------------------

function check_axis(d, name)
if numel(d) < 2
    return
end
if any(diff(d) <= 0)
    error('uc:data:notSorted', '%s is not sorted forward in time.', name);
end
expected = (d(1):calquarters(1):d(end))';
if numel(expected) ~= numel(d) || any(expected ~= d)
    error('uc:data:notGapless', ...
        ['%s is not a gapless quarterly axis: it runs %s to %s, which is %d ' ...
         'quarters, in %d rows.'], name, label(d(1)), label(d(end)), ...
        numel(expected), numel(d));
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
