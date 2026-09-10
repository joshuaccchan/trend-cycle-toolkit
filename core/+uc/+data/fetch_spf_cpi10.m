function tbl = fetch_spf_cpi10(opts)
% uc.data.fetch_spf_cpi10 - the SPF median 10-year-ahead CPI inflation forecast.
%
%   tbl = uc.data.fetch_spf_cpi10()
%   tbl = uc.data.fetch_spf_cpi10('File', 'median_cpi10_level.xlsx')
%
% Returns a table with date (quarter start) and value (percent per year), covering
% the quarters the survey reports a number for. It is one of the two pieces
% uc.data.build_ptrcpi splices, and through PTRCPI it is what biuc_lrexp reads.
%
% The Philadelphia Fed publishes one workbook per SPF variable, this one holding a
% single sheet named Median_Level with columns YEAR, QUARTER and CPI10:
%
%   https://www.philadelphiafed.org/-/media/frbp/assets/surveys-and-data/
%     survey-of-professional-forecasters/data-files/files/median_cpi10_level.xlsx
%
% TWO FAILURES THIS GUARDS AGAINST, both observed on the live source:
%
%   1. HTTP 200 WITH AN HTML ERROR PAGE. The site answers an unknown media path
%      with a styled error page and a success status, so a status check passes a
%      document that is not a spreadsheet. The download is checked for the ZIP
%      magic bytes 50 4B 03 04, which every xlsx begins with, before anything
%      reads it.
%
%   2. THE LITERAL STRING #N/A BEFORE 1991Q4. The survey did not ask this question
%      before then, and the workbook fills those cells with #N/A: 92 such rows
%      against 140 numeric on 2026-09-09. Read as numbers they are NaN, read as
%      text they are a string sitting in a numeric column. They are dropped here,
%      and the first numeric quarter is reported back through UserData so a caller
%      can assert on it.
%
% Those dropped rows are why PTRCPI cannot be built from the SPF alone.

arguments
    opts.File (1,:) char = ''
end

url = ['https://www.philadelphiafed.org/-/media/frbp/assets/surveys-and-data/' ...
       'survey-of-professional-forecasters/data-files/files/median_cpi10_level.xlsx'];

if isempty(opts.File)
    tmp = [tempname, '.xlsx'];
    cleanup = onCleanup(@() delete_if_present(tmp));
    try
        websave(tmp, url, weboptions('Timeout', 90, ...
            'UserAgent', 'trend-cycle-toolkit (https://github.com/joshuaccchan/trend-cycle-toolkit)'));
    catch err
        error('uc:data:fetchFailed', ...
            'downloading the SPF CPI10 workbook failed: %s', err.message);
    end
else
    tmp = opts.File;
    url = opts.File;
end

assert_zip_magic(tmp, 'the SPF CPI10 workbook');

impopts = detectImportOptions(tmp, 'Sheet', 'Median_Level');
impopts = setvartype(impopts, impopts.VariableNames, 'char');
raw = readtable(tmp, impopts);

need = {'YEAR', 'QUARTER', 'CPI10'};
have = upper(raw.Properties.VariableNames);
if ~all(ismember(need, have))
    error('uc:data:unexpectedLayout', ...
        ['the Median_Level sheet has columns %s. Expected YEAR, QUARTER and ' ...
         'CPI10, so the workbook has been reorganized.'], strjoin(have, ', '));
end

yr = str2double(strtrim(raw.(raw.Properties.VariableNames{find(strcmp(have, 'YEAR'), 1)})));
qt = str2double(strtrim(raw.(raw.Properties.VariableNames{find(strcmp(have, 'QUARTER'), 1)})));
vs = strtrim(string(raw.(raw.Properties.VariableNames{find(strcmp(have, 'CPI10'), 1)})));

keep = ~ismissing(vs) & vs ~= "" & vs ~= "#N/A";
v = nan(size(vs));
v(keep) = str2double(vs(keep));
keep = keep & ~isnan(v);

if ~any(keep)
    error('uc:data:noNumericRows', ...
        ['no row of the CPI10 column parsed as a number. Every one was #N/A, ' ...
         'empty, or text, which means the layout changed.']);
end

date = datetime(yr(keep), 3 * qt(keep) - 2, 1);
value = v(keep);

[date, ord] = sort(date);
value = value(ord);

tbl = table(date, value, 'VariableNames', {'date', 'value'});
tbl.Properties.UserData = struct( ...
    'series',       'SPF median CPI10', ...
    'url',          url, ...
    'fetched',      datetime('now', 'TimeZone', 'UTC'), ...
    'rows_total',   height(raw), ...
    'rows_dropped', height(raw) - sum(keep));
end

% -------------------------------------------------------------------------

function assert_zip_magic(file, what)
fid = fopen(file, 'r');
if fid < 0
    error('uc:data:unreadable', 'could not open the download of %s.', what);
end
magic = fread(fid, 4, 'uint8')';
fclose(fid);
if numel(magic) < 4 || ~isequal(magic, [80 75 3 4])
    error('uc:data:notAZip', ...
        ['the download of %s does not begin with the ZIP magic bytes every xlsx ' ...
         'starts with. It begins %s, which is what an HTML error page served ' ...
         'with HTTP 200 looks like. The status was not the problem.'], ...
        what, sprintf('%02X ', magic));
end
end

function delete_if_present(f)
if isfile(f)
    delete(f);
end
end
