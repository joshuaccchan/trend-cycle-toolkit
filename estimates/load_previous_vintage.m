% load_previous_vintage - read the last published release back off disk.
%
%   previous = load_previous_vintage(root, vintage)
%
% Returns the newest frozen release under estimates/vintages/ strictly older than
% the vintage being produced, as a struct with vintage, path, series (one field per
% published series, each the tidy table current/ ships), diagnostics and metadata.
% guardrails checks against it and revisions re-runs its sample on the new data.
%
% root is passed in rather than computed here so a test can point this at a fixture
% tree. vintage is 'YYYYQq'; what comes back is the newest below it, which is the
% previous release even when a quarter was skipped.
%
% IT READS THE CSVs, ALWAYS, and never trend_cycle_estimates.xlsx: the CSVs are
% what was published, the workbook is derived, and addressing a workbook by cell
% range needs Excel, which a hosted runner does not have.
%
% THE FIRST RELEASE HAS NO PREDECESSOR, and the two cases are told apart:
%
%   the archive is empty                 return an empty struct
%   it holds vintages, none below the    error, naming the folder and the vintage
%   one being produced                   searched below
%
% The second is what a renamed or half-restored archive looks like, and returning
% quietly from it would let a release publish numbers no guardrail had compared
% against anything.

function previous = load_previous_vintage(root, vintage)

arguments
    root {mustBeTextScalar}
    vintage {mustBeTextScalar}
end

previous = struct([]);
archive = fullfile(char(root), 'estimates', 'vintages');

if ~isfolder(archive)
    return
end

d = dir(fullfile(archive, '*Q*'));
d = d([d.isdir]);
names = {d.name};
names = names(cellfun(@is_quarter, names));

if isempty(names)
    return
end

target = quarter_index(vintage);
idx = cellfun(@quarter_index, names);
older = idx < target;

if ~any(older)
    error('uc:estimates:load_previous_vintage:noneBelow', ...
        ['%s holds %d archived vintage(s) - %s - and none of them is below %s. ' ...
         'An archive that exists but cannot supply a predecessor is a renamed or ' ...
         'half-restored one, and a release checked against nothing is worse than ' ...
         'a late release.'], archive, numel(names), strjoin(sort(names), ', '), vintage);
end

names = names(older);
idx = idx(older);
[~, pick] = max(idx);
name = names{pick};
p = fullfile(archive, name);

previous = struct();
previous.vintage = name;
previous.path = p;
previous.series = struct();
for s = {'trend_inflation', 'output_gap', 'trend_growth'}
    f = fullfile(p, [s{1} '.csv']);
    if isfile(f)
        previous.series.(s{1}) = readtable(f, 'TextType', 'string');
    end
end

f = fullfile(p, 'diagnostics.csv');
if isfile(f)
    previous.diagnostics = readtable(f, 'TextType', 'string');
else
    previous.diagnostics = table();
end

f = fullfile(p, 'metadata.json');
if isfile(f)
    previous.metadata = jsondecode(fileread(f));
else
    error('uc:estimates:load_previous_vintage:noMetadata', ...
        ['%s has no metadata.json. Without it the settings the previous release ' ...
         'ran under are unknown, and revisions.m holds those fixed across its ' ...
         'chains - a revision measured against unknown settings is not a ' ...
         'revision.'], p);
end
end


% ---------------------------------------------------------------------------
function tf = is_quarter(s)
tf = ~isempty(regexp(s, '^\d{4}Q[1-4]$', 'once'));
end


function n = quarter_index(s)
% A quarter as a single increasing integer, so "newest below" is a comparison.
s = char(s);
if ~is_quarter(s)
    error('uc:estimates:load_previous_vintage:badVintage', ...
        '"%s" is not a vintage of the form YYYYQq.', s);
end
n = 4 * str2double(s(1:4)) + str2double(s(6));
end
