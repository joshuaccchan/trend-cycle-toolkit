function tbl = fetch_frbus_ptr(opts)
% uc.data.fetch_frbus_ptr - PTR, the FRB/US 10-year expected PCE inflation series.
%
%   tbl = uc.data.fetch_frbus_ptr()
%   tbl = uc.data.fetch_frbus_ptr('File', 'data_only_package.zip')
%
% Returns a table of date (quarter start) and value (percent per year), read out of
% the Board's FRB/US package:
%
%   https://www.federalreserve.gov/econres/files/data_only_package.zip
%
% It is the whole of the long-run expectations series biuc_lrexp reads, backfilled
% at the head by uc.data.build_ptr, and it sets that model's sample end: when the
% Board has not refreshed the package, biuc_lrexp ends a quarter behind the others.
%
% THE TRAP. The package holds two data files and only one is history:
%
%   HISTDATA.TXT   historical data. Last OBS 2026Q1.
%   LONGBASE.TXT   the same variables with a projection appended. Last OBS 2176Q2.
%
% Reading LONGBASE would hand the model a hundred and fifty years of forecast as
% though it were observed, and nothing downstream would object: the series is
% smooth, plausibly scaled, and simply keeps going. This reads HISTDATA only and
% asserts its last observation is not in the future.
%
% PTR sits in column 183 of 366 and that layout is reorganized from time to time,
% so it is located BY NAME and its absence is an error.

arguments
    opts.File (1,:) char = ''
end

url = 'https://www.federalreserve.gov/econres/files/data_only_package.zip';
tmpdir = tempname;

if isempty(opts.File)
    tmpzip = [tempname, '.zip'];
    cleanup = onCleanup(@() cleanup_paths(tmpzip, tmpdir));
    try
        websave(tmpzip, url, weboptions('Timeout', 300, ...
            'UserAgent', 'trend-cycle-toolkit (https://github.com/joshuaccchan/trend-cycle-toolkit)'));
    catch err
        error('uc:data:fetchFailed', ...
            'downloading the FRB/US data package failed: %s', err.message);
    end
else
    tmpzip = opts.File;
    url = opts.File;
    cleanup = onCleanup(@() cleanup_paths('', tmpdir));
end

fid = fopen(tmpzip, 'r');
magic = fread(fid, 4, 'uint8')';
fclose(fid);
if ~isequal(magic, [80 75 3 4])
    error('uc:data:notAZip', ...
        ['the FRB/US download does not begin with the ZIP magic bytes. It begins ' ...
         '%s, so it is not the package, whatever status came back with it.'], ...
        sprintf('%02X ', magic));
end

mkdir(tmpdir);
files = unzip(tmpzip, tmpdir);

hist = files(endsWith(files, 'HISTDATA.TXT', 'IgnoreCase', true));
if isempty(hist)
    error('uc:data:noHistdata', ...
        ['the FRB/US package contains no HISTDATA.TXT. It holds: %s. LONGBASE.TXT ' ...
         'is not a substitute: it appends a projection to history.'], ...
        strjoin(cellfun(@(f) string(extractAfter(f, tmpdir)), files, ...
                        'UniformOutput', false), ', '));
end

impopts = detectImportOptions(hist{1}, 'FileType', 'text', 'Delimiter', ',');
impopts = setvartype(impopts, impopts.VariableNames, 'char');
raw = readtable(hist{1}, impopts);

vars = raw.Properties.VariableNames;
col = find(strcmpi(vars, 'PTR'), 1);
if isempty(col)
    error('uc:data:noPTR', ...
        ['HISTDATA.TXT has %d columns and none of them is PTR. The Board ' ...
         'reorganizes this file, so this is a layout change and not a bad ' ...
         'download.'], numel(vars));
end

obs = strtrim(string(raw.(vars{1})));
val = str2double(strtrim(string(raw.(vars{col}))));

date = NaT(numel(obs), 1);
for k = 1:numel(obs)
    tok = regexp(obs(k), '^(\d{4})[Qq]([1-4])$', 'tokens', 'once');
    if ~isempty(tok)
        date(k) = datetime(str2double(tok(1)), 3 * str2double(tok(2)) - 2, 1);
    end
end

keep = ~isnat(date) & ~isnan(val);
if ~any(keep)
    error('uc:data:noObservations', ...
        'no row of HISTDATA.TXT parsed into a quarter with a numeric PTR.');
end

date = date(keep);
val = val(keep);
[date, ord] = sort(date);
val = val(ord);

% LONGBASE read as history is the failure this catches. A projection reaches
% decades past the present; observed history never does.
now_q = dateshift(datetime('now'), 'start', 'quarter');
if date(end) > now_q
    error('uc:data:futureObservation', ...
        ['PTR''s last observation is %dQ%d, which is in the future. That is the ' ...
         'signature of LONGBASE.TXT, which appends a projection running to 2176. ' ...
         'History is being read from the wrong file.'], ...
        year(date(end)), quarter(date(end)));
end

tbl = table(date, val, 'VariableNames', {'date', 'value'});
tbl.Properties.UserData = struct( ...
    'series',  'FRB/US PTR', ...
    'url',     url, ...
    'file',    'HISTDATA.TXT', ...
    'column',  col, ...
    'ncols',   numel(vars), ...
    'fetched', datetime('now', 'TimeZone', 'UTC'));
end

% -------------------------------------------------------------------------

function cleanup_paths(z, d)
if ~isempty(z) && isfile(z)
    delete(z);
end
if isfolder(d)
    rmdir(d, 's');
end
end
