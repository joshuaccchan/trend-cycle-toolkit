% preset - the sampler settings each model is run with, in one place.
%
%   cfg = preset('ucsv_sw07')                      % one model, a 1x1 struct
%   cfg = preset({'ucsv_sw07','ucur_break2'})      % two, a 1x2 struct array
%   cfg = preset('ucsv_sw07', 'NSim', 2000, 'Burnin', 500)   % for a smoke run
%
% Takes one model name or a list of them and returns one struct per model, in the
% order they were asked for, with fields nsim, burnin, thin, seed, sample_start,
% compute_ml, and any model-specific settings: the bounds of a bounded model, the
% break dates of a model with breaks, and which input series enter. run_release.m
% passes the list straight from its 'Models' option and hands the struct array on
% to run_estimates.m, which walks it; publish.m copies each element verbatim into
% metadata.json, so a published series always carries the settings that produced
% it.
%
% The name-value overrides set the like-named field on every model in the list:
% 'NSim' sets nsim, and 'Burnin', 'Thin', 'Seed' and 'SampleStart' set the rest.
% They are there for smoke runs and tests, and a release never uses them. The
% fields are lower case because metadata.json publishes them under those names;
% the options are capitalized because every option in this pipeline is.
%
% THE FIVE MODELS, AND WHAT EACH PRODUCES
%
%   model            series it produces            input series
%   ---------------  ---------------------------   -------------------
%   ucsv_sw07        trend inflation               CPIAUCSL
%   ar_trend_bound   trend inflation               CPIAUCSL
%   biuc_lrexp       trend inflation               CPIAUCSL, PTRCPI
%   uc_2m            output gap and trend growth   GDPC1
%   ucur_break2      output gap                    GDPC1
%
% uc_2m is the only model that produces two of the three published series, and it
% produces both from one set of draws: the trend is stored, the annualized trend
% growth is stored as its scaled first difference, and the gap is the observed
% series minus the trend.
%
% WHY THIS FILE EXISTS. The published drivers hard-code their settings inline and
% seed the random number generator from the clock, in places through the legacy
% form randn('seed',...), which selects a pre-Mersenne generator. A release has to
% be reproducible, so the seed is fixed here, recorded, and never changed once a
% series has been published under it.
%
% THE CITATION RULE. Every published value below names the package and file it was
% read from. The citation is to a package at https://joshuachan.org/code.html and to a
% file inside it, or to a chapter of the book repository
% (https://github.com/joshuaccchan/bayesian-macroeconometrics), never to a working
% copy, so a reader can obtain the same file and check the value. A value with no
% citation is not a published setting, and the table says whose choice it is
% instead. The published values are read in phase 1, from the drivers as
% distributed.
%
%   model            nsim    burnin  thin  sample start
%   ---------------  ------  ------  ----  ------------
%   ucsv_sw07        TBD     TBD     10    1947Q2
%   ar_trend_bound   TBD     TBD     10    1947Q2
%   biuc_lrexp       TBD     TBD     10    1960Q1
%   uc_2m            100000  10000   10    1947Q1
%   ucur_break2      100000  10000   10    1947Q1
%
%   model            read from (package or repository, and file)
%   ---------------  -----------------------------------------------
%   ucsv_sw07        the book repository, chapter10/UCSV.m
%   ar_trend_bound   ARtrendbound.zip/ARtrend_bound.m
%   biuc_lrexp       trend_IE_code.zip/M1.m, main_estimation.m
%   uc_2m            output_gap_2M_code.zip/UCUR_2M.m
%   ucur_break2      output_gap_code.zip/UCUR_break2.m
%
% M1.m is the model in trend_IE_code.zip and main_estimation.m is the driver that
% reads its data and calls it, so a setting that lives in the driver rather than in
% the model cites main_estimation.m.
%
% Both output-gap drivers ship nsims = 100000 and burnin = 10000; the other three
% chain lengths are read off their drivers in phase 1.
%
% EVERY MODEL IS ESTIMATED ON ALL AVAILABLE DATA. No sample start is inherited
% from a paper. Each is simply the first quarter its inputs support, so the sample
% grows at the end every quarter and never at the start:
%
%   1947Q2  the three trend inflation models. CPIAUCSL begins 1947Q1 and the
%           first log difference is 1947Q2.
%   1947Q1  both output-gap models. GDPC1 begins 1947Q1 and enters in levels,
%           as 100*log(GDPC1), so no observation is lost to differencing. This is
%           also the start ucur_break2's published break positions assume, so its
%           breaks resolve to 1973Q1 and 2007Q1 exactly as published.
%   1960Q1  biuc_lrexp, which is bounded not by CPIAUCSL but by PTRCPI. That
%           series is built from FRB/US PTR, which itself begins 1968Q1, with a
%           flat backfill over 1960Q1-1967Q4. Nothing before 1960Q1 exists to
%           estimate on.
%
% A start date is therefore a fact about the data, not a setting, and it is
% asserted against the fetched series at run time: a sample that does not begin
% where this table says it does stops the release.
%
% Seeds are a column with no published source at all, because there is nothing to
% cite: the published runs were clock-seeded and their seeds are gone. Each model
% gets one seed, chosen once, recorded here and in metadata.json, and used with
% rng(seed,'threefry') at the top of every run.
%
% WHY THREEFRY. The published drivers seed with rand('seed',...) or
% rand('state',...), which select generators from MATLAB 4 and 5 that rng cannot
% reach and that nothing should use today. Threefry is counter-based, which is
% what makes independent streams cheap: a release runs the models under parfor,
% and a counter-based generator gives each worker a stream that does not overlap
% without the workers having to coordinate. Philox would do as well. The Mersenne
% Twister, MATLAB's default, would also be reproducible here, and is the weaker
% choice for parallel work.
%
%   model            seed
%   ---------------  ----
%   ucsv_sw07        TBD
%   ar_trend_bound   TBD
%   biuc_lrexp       TBD
%   uc_2m            TBD
%   ucur_break2      TBD
%
% THE MARGINAL LIKELIHOOD IS OFF FOR THE QUARTERLY JOB, AND IT IS A SETTING RATHER
% THAN A CONVENTION. Both output-gap drivers ship cp_ml = 1 and M = 50000
% importance replications, because model comparison is what both of those papers
% do. This repository publishes series rather than model comparisons, and the
% importance step is the expensive part of either run, so the quarterly job runs
% with it off:
%
%   model            compute_ml  ml_reps  the published setting it departs from
%   ---------------  ----------  -------  ---------------------------------------
%   ucsv_sw07        false       -        no importance step in the driver
%   ar_trend_bound   false       -        no importance step in the driver
%   biuc_lrexp       false       -        no importance step in the driver
%   uc_2m            false       50000    UCUR_2M.m ships cp_ml = 1, M = 50000
%   ucur_break2      false       50000    UCUR_break2.m ships cp_ml = 1, M = 50000
%
% compute_ml is a field of the struct and is written into metadata.json with
% everything else, so a reader of a published vintage can see that the marginal
% likelihood was not computed for it. ml_reps is carried at the published value for
% the two models whose drivers have the step, and is inert while compute_ml is
% false. A marginal likelihood is computed once, by hand, when a specification is
% chosen, and not on every quarterly run.
%
% BREAK DATES ARE CALENDAR DATES, NEVER ROW INDICES. ucur_break2 is the model with
% correlated trend and cycle errors and two breaks in trend output growth, entered
% as three regime dummies and estimating three drift parameters, so its trend
% growth is a step function with three levels. The published driver builds those
% dummies from the row indices t0 = 105 and t1 = 241, which are 1973Q1 and 2007Q1
% against its own 1947Q1 start. Row indices are correct only for that start:
% appending new quarters does not move them, but a different sample start, or a
% revision that changes which quarter the data begins at, relocates both breaks
% with nothing to announce it.
%
%   model            break_dates             resolved by
%   ---------------  ---------------------   -----------------------------------
%   ucur_break2      {'1973Q1', '2007Q1'}    resolve_break_dates.m, against the
%                                            date axis of the actual sample
%
% resolve_break_dates.m converts the dates to indices against the sample the run is
% actually estimating, and asserts that each one lies inside the sample and that
% they are strictly increasing. run_estimates.m calls it before the model, so a
% configuration that no longer locates both breaks inside the sample stops the run
% rather than estimating different regimes under the same name.
%
% THE THIRD REGIME IS LONGER HERE THAN IN THE PAPER. The published sample ends
% 2014Q4, so the third regime covered 2007Q1 through 2014Q4, 32 quarters. On
% current data it runs to the sample end, which is more than twice that span, so
% the third drift parameter is estimated on more than twice the data the paper had.
% That follows from publishing on current data and is not a defect, and it belongs
% in the model description that ships with the series.
%
% THIN BY 10, AND THIN AT THE SOURCE. Every stored chain is thinned as it is
% written, not afterwards. The two output-gap drivers store the whole trend path
% and, in UCUR_2M.m, the whole annualized growth path as well: at their published
% 100,000 draws and a postwar US quarterly sample of a little over 300
% observations, each of those stores is about a quarter of a gigabyte in doubles,
% and a parfor pool holding several models at once multiplies that. Thinned by 10
% they are a tenth of the size, and nothing changes statistically at these chain
% lengths.
%
% SAMPLE START, NOT SAMPLE RANGE. The published drivers address their data by
% position or by spreadsheet cell range. Here a model is given a start date and
% takes the sample to the last complete quarter that uc.data reports, so extending
% the sample is a data question rather than an edit.
%
% BOUNDS. ar_trend_bound is bounded by construction - the bound on trend inflation
% is the model - and its bounds are carried in this struct rather than inline, so
% that guardrail G5 in guardrails.m reads the same numbers the sampler was given
% and the check cannot drift away from the model. The values are read from
% ARtrend_bound.m in phase 1 and cited there, along with whether any other of the
% five carries a bound of its own.

function cfg = preset(models, varargin)                                     %#ok<STOUT,INUSD>

error('uc:estimates:preset:notImplemented', ...
    ['preset is not implemented yet (phase 5). The published settings it will ' ...
     'return are read in phase 1 from the published drivers, and every value ' ...
     'carries the package and file it came from - see the header.']);
