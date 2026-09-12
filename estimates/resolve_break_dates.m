function idx = resolve_break_dates(break_dates, sample_dates)
% resolve_break_dates - turn configured break quarters into row indices.
%
%   idx = resolve_break_dates({'1973Q1','2007Q1'}, dates)
%
% break_dates is one 'YYYYQq' string or a list of them, as preset carries them;
% dates is the axis of the sample being estimated, either a datetime vector of
% quarters or a list of 'YYYYQq' strings. Returns one row index per break date.
%
% The published driver behind ucur_break2 builds its regime dummies from t0 = 105
% and t1 = 241, which are 1973Q1 and 2007Q1 only against its own 1947Q1 start.
% Appending quarters does not move them, but a different start, or a revision that
% changes which quarter the series begins at, moves both breaks with nothing to
% announce it. So the configuration carries dates and this resolves them against
% the sample in front of it.
%
% Four assertions, each an error rather than a warning: the axis is quarterly and
% gapless, every break is inside the sample, no break falls on the first or last
% quarter, and the resolved indices strictly increase.

[brk, brk_label] = quarter_number(break_dates, 'break_dates');
[smp, smp_label] = quarter_number(sample_dates, 'sample_dates');

if isempty(smp)
    error('uc:estimates:resolve_break_dates:emptySample', ...
        'sample_dates is empty, so there is no sample to resolve a break in.');
end
if any(diff(smp) ~= 1)
    error('uc:estimates:resolve_break_dates:sampleGap', ...
        ['sample_dates is not a gapless quarterly axis running forward, so ' ...
         'a row index into it would not be the quarter it names. It runs ' ...
         '%s to %s in %d rows, which is %d quarters.'], ...
        smp_label{1}, smp_label{end}, numel(smp), smp(end) - smp(1) + 1);
end

idx = zeros(size(brk));
for k = 1:numel(brk)
    hit = find(smp == brk(k), 1);
    if isempty(hit)
        error('uc:estimates:resolve_break_dates:outOfRange', ...
            ['Break date %s is not in the sample, which runs %s to %s. A break ' ...
             'outside the sample would leave one of its regimes empty.'], ...
            brk_label{k}, smp_label{1}, smp_label{end});
    end
    if hit == 1 || hit == numel(smp)
        error('uc:estimates:resolve_break_dates:emptyRegime', ...
            ['Break date %s is the %s quarter of the sample (%s to %s), so one ' ...
             'regime either side of it holds no observations.'], ...
            brk_label{k}, char_first_or_last(hit), smp_label{1}, smp_label{end});
    end
    idx(k) = hit;
end

if any(diff(idx) <= 0)
    error('uc:estimates:resolve_break_dates:notOrdered', ...
        ['Break dates must be given in strictly increasing order and must not ' ...
         'repeat. %s resolved to indices %s.'], ...
        strjoin(brk_label, ', '), mat2str(idx(:)'));
end
end


% =========================================================================
function [q, label] = quarter_number(dates, argname)
% quarter_number - map quarters to consecutive integers, so that comparison and
% differencing are integer arithmetic rather than date arithmetic. The label is
% carried alongside because every error message above names the quarter a reader
% configured, not the integer this function turned it into.

if isdatetime(dates)
    dates = dates(:);
    q     = 4 * year(dates) + ceil(month(dates) / 3);
    label = cellstr(datestr_quarter(dates));
    return
end

if ischar(dates)
    dates = {dates};
elseif isstring(dates)
    dates = cellstr(dates);
end
if ~iscellstr(dates)
    error('uc:estimates:resolve_break_dates:badType', ...
        ['%s must be a datetime vector, a ''YYYYQq'' string, or a list of them. ' ...
         'It arrived as %s.'], argname, class(dates));
end

dates = dates(:);
q     = zeros(numel(dates), 1);
label = cell(numel(dates), 1);
for k = 1:numel(dates)
    tok = regexp(strtrim(dates{k}), '^(\d{4})[Qq]([1-4])$', 'tokens', 'once');
    if isempty(tok)
        error('uc:estimates:resolve_break_dates:badFormat', ...
            ['%s{%d} is ''%s''; the format is ''YYYYQq'', for example ' ...
             '''1973Q1''.'], argname, k, dates{k});
    end
    q(k)     = 4 * str2double(tok{1}) + str2double(tok{2});
    label{k} = sprintf('%sQ%s', tok{1}, tok{2});
end
end


% =========================================================================
function s = datestr_quarter(d)
% datestr_quarter - 'YYYYQq' for a datetime vector, for the error messages.

s = string(year(d)) + "Q" + string(ceil(month(d) / 3));
end


% =========================================================================
function s = char_first_or_last(hit)
if hit == 1
    s = 'first';
else
    s = 'last';
end
end
