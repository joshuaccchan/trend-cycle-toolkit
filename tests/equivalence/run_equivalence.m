function results = run_equivalence(models)
% run_equivalence - each model against the published code it was taken from.
%
%   run_equivalence                        % all six models
%   run_equivalence({'uc_ma', 'uc_2m'})
%   results = run_equivalence(...)
%
% Downloads each model's package from joshuachan.org/code.html, and for ucsv_sw07
% chapter10/UCSV.m from joshuaccchan/bayesian-macroeconometrics, into a temporary
% folder. The published sampler and the function in core/+uc/+models then run on
% the package's own data from one seed, and every stored block of draws must be
% identical. The published script is changed only where a comparison needs it: its
% chain length and data are set here, its seed is set once at the top, and its
% screen output is dropped.
%
% Errors if any model differs. Needs the network, so it is run by hand and is not
% part of the unit suite.

arguments
    models = {'ucsv_sw07', 'ar_trend_bound', 'biuc_lrexp', 'uc_ma', 'uc_2m', 'ucur_break2'}
end
models = cellstr(models);

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
run(fullfile(root, 'setup.m'));

work = tempname;
mkdir(work);
cleanup = onCleanup(@() rmdir(work, 's'));

results = struct('model', {}, 'identical', {}, 'blocks', {});
for k = 1:numel(models)
    folder = fullfile(work, models{k});
    mkdir(folder);
    switch models{k}
        case 'ucsv_sw07',      [same, blocks] = check_ucsv_sw07(folder);
        case 'ar_trend_bound', [same, blocks] = check_ar_trend_bound(folder);
        case 'biuc_lrexp',     [same, blocks] = check_biuc_lrexp(folder);
        case 'uc_ma',          [same, blocks] = check_uc_ma(folder);
        case 'uc_2m',          [same, blocks] = check_uc_2m(folder);
        case 'ucur_break2',    [same, blocks] = check_ucur_break2(folder);
        otherwise
            error('uc:equivalence:unknownModel', '"%s" has no check.', models{k});
    end
    results(end+1) = struct('model', models{k}, 'identical', same, 'blocks', blocks); %#ok<AGROW>
    fprintf('%-15s %s\n', models{k}, verdict(same, blocks));
end

if ~all([results.identical])
    error('uc:equivalence:differs', '%s: draws differ from the published code.', ...
        strjoin({results(~[results.identical]).model}, ', '));
end
end


% ---- the six checks ----------------------------------------------------------------
function [same, blocks] = check_ucsv_sw07(work)
NSIM = 600; BURN = 100; SEED = 1;
book = 'https://raw.githubusercontent.com/joshuaccchan/bayesian-macroeconometrics/main/code/matlab/chapter10/';
pkg = fullfile(work, 'chapter10');
for f = {'UCSV.m', 'SVRW.m', 'SV_RW_gaussian_approx.m', 'USPCE.csv'}
    fetch([book f{1}], fullfile(pkg, f{1}));
end
y = readmatrix(fullfile(pkg, 'USPCE.csv'), 'Range', 'B2:B261');   % as UCSV.m reads it

new = uc.models.ucsv_sw07(y, 'NSim', NSIM, 'Burnin', BURN, 'Thin', 1, 'Seed', SEED);
old = run_published(fullfile(pkg, 'UCSV.m'), '% prior hyperparameters', 'for isim', work, ...
    struct('y', y, 'T', numel(y)), ...
    {sprintf('nsim = %d; burnin = %d;', NSIM - BURN, BURN)}, SEED, ...
    {'store_tau', 'store_h', 'store_g', 'store_theta'});
[same, blocks] = compare({'tau', old.store_tau, new.tau; 'h', old.store_h, new.h; ...
    'g', old.store_g, new.g; 'theta', old.store_theta, new.theta});
end


function [same, blocks] = check_ar_trend_bound(work)
NSIM = 600; BURN = 100; SEED = 2;
pkg = package('ARtrendbound', 'ARtrend_bound.m', work);
d = readmatrix(fullfile(pkg, 'USCPI_Q.csv'));
d = d(~isnan(d(:, 1)), 1);
y0 = d(1);  y = d(2:end);

new = uc.models.ar_trend_bound(y, y0, 'NSim', NSIM, 'Burnin', BURN, 'Thin', 1, 'Seed', SEED);
old = run_published(fullfile(pkg, 'ARtrend_bound.m'), '%% prior', 'for loop', work, ...
    struct('y0', y0, 'y', y, 'T', numel(y)), ...
    {sprintf('nloop = %d; burnin = %d;', NSIM, BURN)}, SEED, ...
    {'store_tau', 'store_rho', 'store_h', 'store_sig'});
[same, blocks] = compare({'tau', old.store_tau, new.tau; 'rho', old.store_rho, new.rho; ...
    'h', old.store_h, new.h; 'sig', old.store_sig, new.sig});
end


function [same, blocks] = check_biuc_lrexp(work)
NSIM = 300; BURN = 50; SEED = 3;
pkg = package('trend_IE_code', 'M1.m', work);
xl = fullfile(pkg, 'cck1_data.xlsx');
data1 = readmatrix(xl, 'Range', 'B54:B278');   % PCE inflation, as main_estimation.m reads it
data2 = readmatrix(xl, 'Range', 'C54:C278');   % PTR

new = uc.models.biuc_lrexp(data1, data2, 'NSim', NSIM, 'Burnin', BURN, 'Thin', 1, ...
    'Seed', SEED, 'Q', 1);
old = run_published(fullfile(pkg, 'M1.m'), '% prior', 'for isim', work, ...
    struct('pi0', data1(1), 'pi', data1(2:end), 'z0', data2(1), 'z', data2(2:end), ...
           'T', numel(data1) - 1, 'q', 1), ...
    {sprintf('nsim = %d; burnin = %d;', NSIM - BURN, BURN)}, SEED, ...
    {'store_pistar', 'store_b', 'store_d', 'store_lamv', 'store_lamn', 'store_theta'});
[same, blocks] = compare({'pistar', old.store_pistar, new.pistar; 'b', old.store_b, new.b; ...
    'd', old.store_d, new.d; 'lamv', old.store_lamv, new.lamv; ...
    'lamn', old.store_lamn, new.lamn; 'theta', old.store_theta, new.theta});
end


function [same, blocks] = check_uc_ma(work)
NSIM = 700; BURN = 100; SEED = 6;
pkg = package('MASV_matlab', 'UC_MA.m', work);
d = readmatrix(fullfile(pkg, 'USCPI_Q.csv'));
d = d(~isnan(d(:, 1)), 1);
y = d(2:end);   % as main_UCMA.m sets it

new = uc.models.uc_ma(y, 'NSim', NSIM, 'Burnin', BURN, 'Thin', 1, 'Seed', SEED);
old = run_published(fullfile(pkg, 'UC_MA.m'), '%% prior', 'for loop', work, ...
    struct('y', y, 'T', numel(y)), ...
    {sprintf('nloop = %d; burnin = %d;', NSIM, BURN), 'options = optimset(''Display'', ''off'');'}, ...
    SEED, {'stau', 'sh', 'stheta', 'spsi'});
[same, blocks] = compare({'tau', old.stau, new.tau; 'h', old.sh, new.h; ...
    'theta', old.stheta, new.theta(:, 1:4); 'psi', old.spsi, new.theta(:, 5)});
end


function [same, blocks] = check_uc_2m(work)
NSIM = 600; BURN = 100; SEED = 4;
pkg = package('output_gap_2M_code', 'UCUR_2M.m', work);
y = 100 * log(readmatrix(fullfile(pkg, 'USGDP.csv')));   % as main_script.m sets it

new = uc.models.uc_2m(y, 'NSim', NSIM, 'Burnin', BURN, 'Thin', 1, 'Seed', SEED);
old = run_published(fullfile(pkg, 'UCUR_2M.m'), '%% prior', 'for isim', work, ...
    struct('y', y, 'T', numel(y)), ...
    {sprintf('nsims = %d; burnin = %d;', NSIM - BURN, BURN)}, SEED, ...
    {'store_tau', 'store_theta', 'store_mu'});
[same, blocks] = compare({'tau', old.store_tau, new.tau; 'theta', old.store_theta, new.theta; ...
    'mu', old.store_mu, new.mu});
end


function [same, blocks] = check_ucur_break2(work)
NSIM = 600; BURN = 100; SEED = 5;
pkg = package('output_gap_code', 'UCUR_break2.m', work);
y = 100 * log(readmatrix(fullfile(pkg, 'USGDP.csv')));   % as main_UC.m sets it
t0 = 105;  t1 = 241;                                     % 1973Q1 and 2007Q1, as main_UC.m sets them

new = uc.models.ucur_break2(y, [t0 t1], 'NSim', NSIM, 'Burnin', BURN, 'Thin', 1, 'Seed', SEED);
old = run_published(fullfile(pkg, 'UCUR_break2.m'), '%% prior', 'for isim', work, ...
    struct('y', y, 'T', numel(y), 't0', t0, 't1', t1), ...
    {sprintf('nsims = %d; burnin = %d;', NSIM - BURN, BURN)}, SEED, ...
    {'store_tau', 'store_theta'});
[same, blocks] = compare({'tau', old.store_tau, new.tau; 'theta', old.store_theta, new.theta});
end


% ---- running the published code ---------------------------------------------------
function out = run_published(driver, first, loop, work, inputs, settings, seed, outputs)
% The published sampler from the line starting with first to the unindented end of
% the loop starting with loop, without its seed line, screen output or timing. It
% runs behind the inputs and settings, from rng(seed, 'threefry'), in a workspace of
% its own, and returns the named variables.
L = splitlines(string(strrep(fileread(driver), char(13), '')));
i = find(startsWith(strtrim(L), first), 1);
f = find(startsWith(L, loop), 1);
j = find(L == "end" & (1:numel(L))' > f, 1);
if isempty(i) || isempty(f) || isempty(j) || i > f
    error('uc:equivalence:layout', '%s: the prior block or the sampling loop was not found.', driver);
end
body = L(i:j);
seeding = contains(body, ["rand('state'", "randn('state'", "rand('seed'", "randn('seed'", "rng("]);
body = body(~seeding & ~startsWith(strtrim(body), "disp(") & ~contains(body, "start_time"));
if any(startsWith(strtrim(body), "clear"))
    error('uc:equivalence:layout', '%s: the sampler clears its workspace.', driver);
end

[~, name] = fileparts(driver);
infile = fullfile(work, [name '_in.mat']);
outfile = fullfile(work, [name '_out.mat']);
script = fullfile(work, ['published_' name '.m']);
save(infile, '-struct', 'inputs');
writelines([sprintf("load('%s');", infile); string(settings(:)); ...
            sprintf("rng(%d, 'threefry');", seed); body; ...
            sprintf("save('%s', %s);", outfile, strjoin("'" + string(outputs) + "'", ', '))], script);

addpath(fileparts(driver));
restore = onCleanup(@() rmpath(fileparts(driver)));
out = execute(script, outfile);
end


function out = execute(published_script__, published_outputs__)
% A workspace holding nothing but these two names, so the published script's own
% variables - several scripts assign uc, or pi - shadow nothing the checks use.
run(published_script__);
out = load(published_outputs__);
end


% ---- downloads and comparison ------------------------------------------------------
function folder = package(name, driver, work)
% A package from joshuachan.org/code.html, unzipped; the folder holding driver.
zipfile = fetch(sprintf('https://joshuachan.org/code/%s.zip', name), fullfile(work, [name '.zip']));
unzip(zipfile, fullfile(work, name));
hit = dir(fullfile(work, name, '**', driver));
if ~isscalar(hit)
    error('uc:equivalence:package', '%s.zip holds %d copies of %s.', name, numel(hit), driver);
end
folder = hit.folder;
end


function file = fetch(url, file)
if ~isfolder(fileparts(file)), mkdir(fileparts(file)); end
opts = weboptions('UserAgent', 'trend-cycle-toolkit (https://github.com/joshuaccchan/trend-cycle-toolkit)', ...
    'Timeout', 60);
file = websave(file, url, opts);
end


function [same, blocks] = compare(pairs)
% Every block must be bitwise identical; the largest absolute difference is
% reported for any that is not.
n = size(pairs, 1);
blocks = table(strings(n, 1), strings(n, 1), nan(n, 1), false(n, 1), ...
    'VariableNames', {'block', 'size', 'max_abs_diff', 'identical'});
for k = 1:n
    a = pairs{k, 2};  b = pairs{k, 3};
    blocks.block(k) = pairs{k, 1};
    blocks.size(k) = strjoin(string(size(a)), 'x');
    blocks.identical(k) = ~isempty(a) && isequal(size(a), size(b)) && isequal(a, b);
    if isequal(size(a), size(b)) && ~isempty(a)
        blocks.max_abs_diff(k) = max(abs(a(:) - b(:)));
    end
end
same = all(blocks.identical);
end


function s = verdict(same, blocks)
if same
    s = "identical draw for draw: " + strjoin(blocks.block + " " + blocks.size, ", ");
else
    bad = blocks(~blocks.identical, :);
    s = "DIFFERS: " + strjoin(compose("%s (max |diff| %.3g)", bad.block, bad.max_abs_diff), ", ");
end
end
