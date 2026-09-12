function tbl = annualized_log_diff(tbl)
% uc.data.annualized_log_diff - a price index to annualized percent inflation.
%
%   infl = uc.data.annualized_log_diff(pce)
%
% Takes a table of quarterly index levels from uc.data.fetch_fred and returns the
% same table one row shorter, with
%
%   value_t = 400 * log( level_t / level_{t-1} )
%
% The first row has no predecessor and is dropped, which is why the three trend
% inflation models start at 1947Q2 while DPCERD3Q086SBEA begins at 1947Q1.
%
% The factor is 4 for annualization and 100 for percent. Annualized percentage
% points are the units the published models are written against - ar_trend_bound
% bounds its trend on (0,5) - so a proportional change fed in instead would put the
% whole sample outside that support and the sampler would reject forever without
% saying why.
%
% Verified against both published packages: applied to DPCERD3Q086SBEA it
% reproduces cck1_data.xlsx's PCEINFL column from 1947Q2 at correlation 0.99901,
% and applied to the quarterly average of CPIAUCSL it reproduces ARtrendbound.zip's
% USCPI_Q.csv to 2e-10 over the quarters BLS has not since revised.
%
% This runs on the way into a model, so what a release archives stays levels.

arguments
    tbl table
end

if ~all(ismember({'date', 'value'}, tbl.Properties.VariableNames))
    error('uc:data:badTable', ...
        'expected a table with date and value columns, from uc.data.fetch_fred.');
end

if height(tbl) < 2
    error('uc:data:tooShort', ...
        ['a log difference needs at least two observations and this series has ' ...
         '%d.'], height(tbl));
end

if any(tbl.value <= 0)
    bad = find(tbl.value <= 0, 1);
    error('uc:data:nonPositive', ...
        ['the level at %s is %g. A price index is strictly positive, so this is ' ...
         'a parse failure or the wrong series, and log() would return complex.'], ...
        string(tbl.date(bad), 'yyyy-MM-dd'), tbl.value(bad));
end

v = 400 * diff(log(tbl.value));

tbl = table(tbl.date(2:end), v, 'VariableNames', {'date', 'value'});
tbl.Properties.UserData = struct('transform', '400*log-diff of the quarterly level');
end
