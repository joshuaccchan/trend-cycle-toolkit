function manifest = vintage_stamp(src, stagedir, vintage)
% uc.data.vintage_stamp - archive the fetched inputs and record what they were.
%
%   manifest = uc.data.vintage_stamp(src, stagedir, vintage)
%
% src is the struct of fetched series tables. Each is written to
% stagedir/sources/<name>.csv and hashed, and manifest comes back as a struct array
% with one entry per series: name, file, url, fetched, rows, first, last and sha256.
% publish copies both into the vintage and folds the manifest into metadata.json.
%
% There is no vintage service behind these series, so a later run cannot ask what
% the data looked like at an earlier release. Without the archived input a release
% can see that an estimate moved and cannot say whether the data moved, the sample
% grew, or the sampler wandered.
%
% The hash is over the CSV this function writes, so it is a hash of what is
% archived. Hashing the raw download would tie the record to transport details.

arguments
    src (1,1) struct
    stagedir (1,:) char
    vintage (1,:) char
end

outdir = fullfile(stagedir, 'sources');
if ~isfolder(outdir)
    mkdir(outdir);
end

names = fieldnames(src);
manifest = struct('name', {}, 'file', {}, 'url', {}, 'fetched', {}, ...
                  'rows', {}, 'first', {}, 'last', {}, 'sha256', {});

for k = 1:numel(names)
    name = names{k};
    t = src.(name);
    if ~istable(t) || ~all(ismember({'date', 'value'}, t.Properties.VariableNames))
        error('uc:data:badTable', ...
            'src.%s is not a table with date and value columns.', name);
    end

    file = fullfile(outdir, [name, '.csv']);
    out = table(cellstr(string(t.date, 'yyyy-MM-dd')), t.value, ...
                'VariableNames', {'date', 'value'});
    writetable(out, file);

    ud = t.Properties.UserData;
    manifest(end + 1) = struct( ...
        'name',    name, ...
        'file',    ['sources/', name, '.csv'], ...
        'url',     field_or(ud, 'url', ''), ...
        'fetched', field_or(ud, 'fetched', NaT), ...
        'rows',    height(t), ...
        'first',   sprintf('%dQ%d', year(t.date(1)), quarter(t.date(1))), ...
        'last',    sprintf('%dQ%d', year(t.date(end)), quarter(t.date(end))), ...
        'sha256',  sha256_of(file));  %#ok<AGROW>
end

% struct2table reads a scalar struct as one column per field, and an absent url is
% a 0-row char where the others have 1, so a single-series manifest needs AsArray.
% The option cannot be passed as false for an array, so the two cases are separate
% calls rather than one with a computed flag.
if isscalar(manifest)
    tbl = struct2table(manifest, 'AsArray', true);
else
    tbl = struct2table(manifest);
end
writetable(tbl, fullfile(outdir, 'manifest.csv'));

fid = fopen(fullfile(outdir, 'VINTAGE'), 'w');
fprintf(fid, '%s\n', vintage);
fclose(fid);
end

% -------------------------------------------------------------------------

function v = field_or(s, name, default)
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    v = default;
end
end

function h = sha256_of(file)
% Base MATLAB has no hash function, and the Java one is always present.
fid = fopen(file, 'r');
if fid < 0
    error('uc:data:unreadable', 'could not reopen %s to hash it.', file);
end
bytes = fread(fid, Inf, '*uint8');
fclose(fid);

md = java.security.MessageDigest.getInstance('SHA-256');
md.update(bytes);
digest = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(digest)', 1, []));
end
