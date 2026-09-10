function [tbl, dropped] = drop_incomplete_tail(tbl)
% uc.data.drop_incomplete_tail - remove the running quarter from a fetched series.
%
%   tbl            = uc.data.drop_incomplete_tail(tbl)
%   [tbl, dropped] = uc.data.drop_incomplete_tail(tbl)
%
% Takes a table from uc.data.fetch_fred and returns it without any trailing rows
% whose value is missing. dropped is the number removed, 0 or more.
%
% FRED publishes the quarter in progress as a PRESENT row with an EMPTY value.
% Verified 2026-09-09: the quarterly CPIAUCSL response ends
%
%   2026-04-01,332.985
%   2026-07-01,
%
% Read without care that becomes NaN, and one NaN in a price index propagates
% through every log difference after it and into the whole state path. The
% published drivers guard it by hard-coding a spreadsheet range, which is correct
% for one vintage and wrong for the next. Series differ: CPIAUCSL had an empty
% running quarter on 2026-09-09 and GDPC1 did not.
%
% Only TRAILING missing values are removed. uc.data.fetch_fred already errors on a
% gap inside the sample, and an interior NaN survives here to be caught downstream.

arguments
    tbl table
end

if ~all(ismember({'date', 'value'}, tbl.Properties.VariableNames))
    error('uc:data:badTable', ...
        'expected a table with date and value columns, from uc.data.fetch_fred.');
end

n = height(tbl);
last = n;
while last >= 1 && ismissing(tbl.value(last))
    last = last - 1;
end

dropped = n - last;

if last == 0
    error('uc:data:allMissing', ...
        ['every value in this series is missing, so there is no complete quarter ' ...
         'to publish from. That is a fetch failure wearing the shape of a series.']);
end

tbl = tbl(1:last, :);
end
