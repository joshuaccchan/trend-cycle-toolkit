function tests = test_data()
% test_data - uc.data, on fixtures rather than on the live sources.
%
% Every fetcher here is driven through its 'File' option against a file this
% suite writes, so the parser and its guards run without a network. Each guard
% has a test because each one stands between a silent wrong answer and a
% published series.
tests = functiontests(localfunctions);
end


function setupOnce(t)
t.TestData.dir = fullfile(tempdir, 'uc_test_data');
if ~isfolder(t.TestData.dir), mkdir(t.TestData.dir); end
end

function teardownOnce(t)
if isfolder(t.TestData.dir), rmdir(t.TestData.dir, 's'); end
end


% ---- fetch_fred -----------------------------------------------------------
function testFetchFredParsesACsv(t)
f = write_csv(t, 'good.csv', [
    "observation_date,CPIAUCSL"
    "1947-01-01,21.700"
    "1947-04-01,22.000"
    "1947-07-01,22.400"]);
tbl = uc.data.fetch_fred('CPIAUCSL', 'Quarterly', 'File', f);
verifyEqual(t, height(tbl), 3);
verifyEqual(t, tbl.date(1), datetime(1947, 1, 1));
verifyEqual(t, tbl.value(1), 21.700, 'AbsTol', 1e-12);
end


function testFetchFredReturnsTheEmptyRunningQuarter(t)
% FRED publishes the quarter in progress as a present row with no value.
% fetch_fred returns it; dropping it is drop_incomplete_tail's decision.
f = write_csv(t, 'running.csv', [
    "observation_date,CPIAUCSL"
    "2026-04-01,332.985"
    "2026-07-01,"]);
tbl = uc.data.fetch_fred('CPIAUCSL', 'Quarterly', 'File', f);
verifyEqual(t, height(tbl), 2);
verifyTrue(t, isnan(tbl.value(end)));
end


function testFetchFredRejectsAnErrorPageServedAsData(t)
% A status of 200 is not evidence that the body is a CSV.
f = write_csv(t, 'html.csv', [
    "<!DOCTYPE html><html><head><title>Error</title></head>"
    "<body>Something went wrong.</body></html>"]);
verifyError(t, @() uc.data.fetch_fred('CPIAUCSL', 'Quarterly', 'File', f), ...
    'uc:data:notACsv');
end


% ---- drop_incomplete_tail -------------------------------------------------
function testDropIncompleteTailRemovesOnlyTrailingGaps(t)
tbl = quarterly([1 2 NaN 4 NaN NaN]);
[out, dropped] = uc.data.drop_incomplete_tail(tbl);
verifyEqual(t, dropped, 2);
verifyEqual(t, height(out), 4);
verifyTrue(t, isnan(out.value(3)), ...
    'an interior NaN must survive, to be caught downstream rather than papered over');
end


function testDropIncompleteTailLeavesACompleteSeriesAlone(t)
tbl = quarterly([1 2 3]);
[out, dropped] = uc.data.drop_incomplete_tail(tbl);
verifyEqual(t, dropped, 0);
verifyEqual(t, height(out), 3);
end


% ---- annualized_log_diff --------------------------------------------------
function testAnnualizedLogDiffIsFourHundredLogRatio(t)
tbl = quarterly([100 101 103]);
out = uc.data.annualized_log_diff(tbl);
verifyEqual(t, height(out), 2, 'the first row has no predecessor and is dropped');
verifyEqual(t, out.value(1), 400 * log(101/100), 'RelTol', 1e-12);
verifyEqual(t, out.date(1), tbl.date(2), 'the rate is dated to the later quarter');
end


% ---- build_ptr ------------------------------------------------------------
function testBuildPtrBackfillsFlatToTheStart(t)
ptr = quarterly_from(1968, [1.6827 1.70 1.75]);
[out, parts] = uc.data.build_ptr(ptr, 'Start', '1960Q1');
verifyEqual(t, out.date(1), datetime(1960, 1, 1));
verifyEqual(t, sum(parts.source == "backfill"), 32, ...
    '1960Q1 through 1967Q4 is 32 quarters');
verifyEqual(t, unique(out.value(parts.source == "backfill")), 1.6827, 'AbsTol', 1e-12);
verifyEqual(t, out.value(end), 1.75, 'AbsTol', 1e-12);
end


function testBuildPtrRecordsWhatItDid(t)
ptr = quarterly_from(1968, [1.6827 1.70]);
out = uc.data.build_ptr(ptr);
u = out.Properties.UserData;
verifyEqual(t, u.backfill_quarters, 32);
verifyEqual(t, u.backfill_value, 1.6827, 'AbsTol', 1e-12);
verifyEqual(t, u.ptr_first, '1968Q1');
end


function testBuildPtrRefusesToTrim(t)
ptr = quarterly_from(1968, [1.6827 1.70]);
verifyError(t, @() uc.data.build_ptr(ptr, 'Start', '1975Q1'), ...
    'uc:data:build_ptr:startAfterPtr');
end


% ---- align_by_date --------------------------------------------------------
function testAlignByDateIntersects(t)
src.a = quarterly_from(1960, 1:8);      % 1960Q1 - 1961Q4
src.b = quarterly_from(1961, [9 9 9]);  % 1961Q1 - 1961Q3
[out, span] = uc.data.align_by_date(src);
verifyEqual(t, span.first, '1961Q1', 'the span starts at the latest first quarter');
verifyEqual(t, span.last, '1961Q3', 'and ends at the earliest last one');
verifyEqual(t, numel(out.a), 3);
verifyEqual(t, out.a, [5; 6; 7], 'AbsTol', 1e-12, ...
    'the longer series is cut to the overlap, not padded');
end


function testAlignByDateHonoursALaterStart(t)
src.a = quarterly_from(1960, 1:8);
[~, span] = uc.data.align_by_date(src, 'Start', '1961Q1');
verifyEqual(t, span.first, '1961Q1');
end


function testAlignByDateRefusesAStartItCannotReach(t)
src.a = quarterly_from(1960, 1:4);
verifyError(t, @() uc.data.align_by_date(src, 'Start', '1975Q1'), ...
    'uc:data:emptyIntersection');
end


function testAlignByDateCatchesAGap(t)
% resolve_break_dates turns quarters into row indices, so a missing quarter
% moves every break after it with nothing to announce it.
tbl = quarterly_from(1960, [1 2 3 4]);
tbl(3, :) = [];
src.a = tbl;
verifyError(t, @() uc.data.align_by_date(src), 'uc:data:notGapless');
end


% ---- vintage_stamp --------------------------------------------------------
function testVintageStampWritesAndHashes(t)
src.CPI = quarterly([100 101 102]);
d = fullfile(t.TestData.dir, 'stage');
m = uc.data.vintage_stamp(src, d, '2026Q2');
verifyEqual(t, numel(m), 1);
verifyTrue(t, isfile(fullfile(d, 'sources', 'CPI.csv')));
verifyEqual(t, numel(m(1).sha256), 64);
verifyEqual(t, m(1).rows, 3);
end


function testVintageStampHandlesSeveralSeries(t)
% A release stamps four series at once. The single-series path needs struct2table's
% AsArray and the multi-series path refuses it, so both are exercised.
src.CPI = quarterly([100 101 102]);
src.GDP = quarterly([200 201 202 203]);
src.PTR = quarterly([2 2 2]);
d = fullfile(t.TestData.dir, 'stage_multi');
m = uc.data.vintage_stamp(src, d, '2026Q2');
verifyEqual(t, numel(m), 3);
verifyTrue(t, isfile(fullfile(d, 'sources', 'manifest.csv')));
% Every column is read as text: a fixture table carries no fetch time, so the
% fetched column is empty and guessing a datetime format on it only warns.
opts = detectImportOptions(fullfile(d, 'sources', 'manifest.csv'));
opts = setvartype(opts, 'string');
mf = readtable(fullfile(d, 'sources', 'manifest.csv'), opts);
verifyEqual(t, height(mf), 3);
verifyEqual(t, sort(mf.name)', ["CPI" "GDP" "PTR"]);
end


% ---------------------------------------------------------------------------
function f = write_csv(t, name, lines)
f = fullfile(t.TestData.dir, name);
fid = fopen(f, 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end


function tbl = quarterly(v)
tbl = quarterly_from(2000, v);
end


function tbl = quarterly_from(y0, v)
v = v(:);
d = (datetime(y0, 1, 1) + calquarters(0:numel(v)-1))';
tbl = table(d, v, 'VariableNames', {'date', 'value'});
end
