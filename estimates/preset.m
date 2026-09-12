% preset - the sampler settings each model is run with, in one place.
%
%   cfg = preset('ucsv_sw07')                                % 1x1 struct
%   cfg = preset({'ucsv_sw07','ucur_break2'})                % 1x2 struct array
%   cfg = preset('ucsv_sw07', 'NSim', 2000, 'Burnin', 500)   % for a smoke run
%
% One struct per model, in the order asked for, with fields nsim, burnin, thin,
% seed, sample_start, compute_ml, ml_reps, trunc_lag, inputs, and the settings a
% particular model needs: bounds, break_dates. run_estimates walks the array;
% publish copies each element into metadata.json.
%
% The name-value overrides - NSim, Burnin, Thin, Seed, SampleStart - set the
% like-named field on every model in the list. A release never passes them.
%
%   model            nsim    burnin  seed  start   inputs
%   ---------------  ------  ------  ----  ------  -----------------------------
%   ucsv_sw07        110000   10000     1  1947Q2  DPCERD3Q086SBEA
%   ar_trend_bound    35000    5000     2  1947Q2  DPCERD3Q086SBEA
%   biuc_lrexp       400000   40000     3  1960Q1  DPCERD3Q086SBEA, PTR
%   uc_2m            430000   30000     4  1947Q1  GDPC1
%   ucur_break2      110000   10000     5  1947Q1  GDPC1
%
% nsim is the TOTAL sweeps including burn-in, everywhere in this repository. thin
% is 10 throughout, applied as draws are stored.
%
% WHERE EACH SETTING COMES FROM. ar_trend_bound and ucur_break2 run their published
% drivers' own lengths, converted to a total. The other three are longer - published
% 51000/1000 for ucsv_sw07, 31000/1000 for biuc_lrexp and 110000/10000 for uc_2m -
% because at those lengths, on data running eleven years past the papers' samples,
% the effective sample falls below what guardrail G7 requires. estimates/README.md
% carries the measurements. Seeds have no published source and are fixed here, never
% changed once a series has been published under one.
%
% Sample starts are facts about the data, not settings: each is the first quarter
% its inputs support, and run_estimates asserts it. Inflation is PCE - sources.md
% says why.
%
% Break dates are calendar quarters, never row indices. resolve_break_dates
% converts them against the sample actually being estimated.
%
% compute_ml is false for all five and ml_reps carries the two output-gap drivers'
% published 50000 inert beside it, so a reader of a vintage can see the marginal
% likelihood was not computed.
%
% trunc_lag is the Bartlett truncation lag uc.diag uses: min(500, floor(n/20)) on
% the stored chain.

function cfg = preset(models, opts)

arguments
    models
    opts.NSim {mustBeScalarOrEmpty, mustBePositive} = []
    opts.Burnin {mustBeScalarOrEmpty, mustBeNonnegative} = []
    opts.Thin {mustBeScalarOrEmpty, mustBePositive} = []
    opts.Seed {mustBeScalarOrEmpty, mustBeNonnegative} = []
    opts.SampleStart {mustBeTextScalar} = ''
end

if ischar(models) || isstring(models)
    models = cellstr(models);
end
if ~iscellstr(models)
    error('uc:estimates:preset:badModels', ...
        'models must be a model name or a cell array of them.');
end

known = catalogue();
cfg = repmat(blank(), 1, numel(models));

for k = 1:numel(models)
    name = models{k};
    if ~isfield(known, name)
        error('uc:estimates:preset:unknownModel', ...
            '"%s" is not one of the five models. They are: %s.', ...
            name, strjoin(fieldnames(known)', ', '));
    end
    c = known.(name);

    if ~isempty(opts.NSim),   c.nsim   = opts.NSim;   end
    if ~isempty(opts.Burnin), c.burnin = opts.Burnin; end
    if ~isempty(opts.Thin),   c.thin   = opts.Thin;   end
    if ~isempty(opts.Seed),   c.seed   = opts.Seed;   end
    if ~isempty(opts.SampleStart), c.sample_start = char(opts.SampleStart); end

    % The truncation lag follows the stored chain, so an override that shortens
    % the chain shortens it too.
    c.trunc_lag = min(500, floor(floor((c.nsim - c.burnin) / c.thin) / 20));

    if c.burnin >= c.nsim
        error('uc:estimates:preset:burninTooLong', ...
            ['%s: burnin (%d) must be below nsim (%d). nsim is the TOTAL sweeps ' ...
             'including burn-in.'], name, c.burnin, c.nsim);
    end

    cfg(k) = c;
end
end


% ---------------------------------------------------------------------------
function s = blank()
% The field order every element shares, so the struct array concatenates and
% metadata.json publishes the same keys for every model.
s = struct('model', '', 'nsim', 0, 'burnin', 0, 'thin', 0, 'seed', 0, ...
           'sample_start', '', 'compute_ml', false, 'ml_reps', 0, ...
           'trunc_lag', [], 'inputs', {{}}, 'bounds', [], 'rho_bound', [], ...
           'break_dates', {{}}, 'cites', '');
end


function known = catalogue()
% The published settings, one entry per model, each naming where it was read.
known = struct();

c = blank();
c.model = 'ucsv_sw07';       c.nsim = 110000; c.burnin = 10000; c.thin = 10;
c.seed = 1;  c.sample_start = '1947Q2';  c.inputs = {'DPCERD3Q086SBEA'};
c.cites = 'bayesian-macroeconometrics chapter10/UCSV.m (chain length is this repository''s)';
known.ucsv_sw07 = c;

c = blank();
c.model = 'ar_trend_bound';  c.nsim = 35000;  c.burnin = 5000;  c.thin = 10;
c.seed = 2;  c.sample_start = '1947Q2';  c.inputs = {'DPCERD3Q086SBEA'};
c.bounds = [0 5];  c.rho_bound = 1;
c.cites = 'ARtrendbound.zip/ARtrend_bound.m';
known.ar_trend_bound = c;

c = blank();
c.model = 'biuc_lrexp';      c.nsim = 400000; c.burnin = 40000; c.thin = 10;
c.seed = 3;  c.sample_start = '1960Q1';  c.inputs = {'DPCERD3Q086SBEA', 'PTR'};
c.cites = 'trend_IE_code.zip/M1.m (chain length is this repository''s)';
known.biuc_lrexp = c;

c = blank();
c.model = 'uc_2m';           c.nsim = 430000; c.burnin = 30000; c.thin = 10;
c.seed = 4;  c.sample_start = '1947Q1';  c.inputs = {'GDPC1'};
c.ml_reps = 50000;
c.cites = 'output_gap_2M_code.zip/UCUR_2M.m (chain length is this repository''s)';
known.uc_2m = c;

c = blank();
c.model = 'ucur_break2';     c.nsim = 110000; c.burnin = 10000; c.thin = 10;
c.seed = 5;  c.sample_start = '1947Q1';  c.inputs = {'GDPC1'};
c.ml_reps = 50000;  c.break_dates = {'1973Q1', '2007Q1'};
c.cites = 'output_gap_code.zip/UCUR_break2.m';
known.ucur_break2 = c;
end
