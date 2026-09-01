-- ==================================================================
-- 14_profile_code21_signal.sql
--
-- Detroit Property Pipeline  |  staging-layer profiling
-- Author: Caden Raymond
-- Written: 2026-09-01
--
-- ------------------------------------------------------------------
-- THESIS
-- ------------------------------------------------------------------
-- Building a neighborhood health index for Detroit requires deciding
-- which property transfers count as market evidence. The Michigan
-- State Tax Commission's CAMA Data Standards answer that question by
-- code, and classify code 21 ("Not Used/Other") as Reference --
-- excluded from sales-ratio studies. In Detroit 2017+, that single
-- exclusion removes 24,978 transfers priced above $10,000: roughly
-- one in four of every real-money transfer in the city.
--
-- Those transfers are not distributed evenly, and neither is what
-- they contain.
--
-- Neighborhoods with a higher proportion of arms-length transfers
-- (code 03) also see a higher proportion of non-nominal transfers
-- within the code 21 bucket. The ratio of real-money code 21
-- provides additional evidence of a neighborhood's health that
-- corroborates the proportion of arms-length sales we see for a
-- particular neighborhood. A neighborhood could have a healthy
-- number of arms-length transfers that is further bolstered by its
-- proportion of real-money transfers filed under code 21.
--
-- TODO(caden): the last clause of the final sentence originally read
-- "increasing the overall health index of that neighborhood." That
-- phrasing implies code 21 transfers get ADDED to the index as
-- sales. That is not what this file supports -- see open question A.
-- The defensible claim is that the code 21 ratio is a SECOND
-- MEASUREMENT, read alongside arms-length share, not added to it.
-- Decide which you mean and make the sentence say it.
--
-- The relationship is moderate, not deterministic (r = 0.508,
-- r-squared = 0.258, n = 117), and the health proxy used to test it
-- shares a term with the variable being tested. It needs an
-- independent re-test before it is load-bearing. See Section 5 and
-- open question F.
--
-- ------------------------------------------------------------------
-- WHY THIS QUESTION
-- ------------------------------------------------------------------
-- File 13 established the citywide composition of Detroit transfers
-- 2017+. Code 21 came back at 115,121 rows -- 37% of all transfers
-- and 83% of the residual "other" bucket. It was the single largest
-- unexamined population in the dataset, and it was being discarded
-- on the strength of its label alone.
--
-- This file opens it.
--
-- ------------------------------------------------------------------
-- METHOD, AND WHY CODE 03 IS IN HERE
-- ------------------------------------------------------------------
-- Price is used as a proxy for whether money genuinely changed hands.
-- That proxy needs a control, or the bucket boundaries are arbitrary.
--
-- Code 03 (Arm's Length) is the control. It is a population already
-- known to be genuine market activity. If the bucket cuts are drawn
-- sensibly, code 03 should pile up in the top bucket. It does, at
-- 94.8%. That result is what licenses reading the code 21 numbers.
--
-- Section 1 inventories the residual bucket. Section 2 runs the
-- nominal-value check that motivated the $100 boundary. Section 3
-- splits both codes into four price buckets by neighborhood.
-- Section 4 measures what the exclusion costs. Section 5 tests
-- whether code 21 composition tracks neighborhood market strength.
--
-- ------------------------------------------------------------------
-- DEFINITIONS AND THRESHOLDS (stated, not assumed)
-- ------------------------------------------------------------------
--   nominal          = amt_sale_price <= 100
--                      NOTE: file 05 used $0/$1 only (~56%). This
--                      file widens it to <= $100 and says so out
--                      loud rather than quietly reusing the old word.
--   real money       = amt_sale_price >= 10000
--   window           = sale_date >= 2017-01-01 (see file 12)
--   neighborhood min = n_21 >= 300 for the spread statistics
--                      TODO(caden): this threshold is currently
--                      arbitrary. Decide and defend it, or move to a
--                      percentage-based cut. 204 neighborhoods exist;
--                      the smallest has 1 transfer.
--
-- ------------------------------------------------------------------
-- PROVENANCE
-- ------------------------------------------------------------------
-- Sections 1-4 were run against the database on 2026-09-01. Figures
-- below those sections are query output.
--
-- Section 5 has NOT been run against the database. Its figures were
-- computed outside Postgres from an export of the Section 4 result
-- set. The SQL is written; run and verify before citing.
-- (Rule adopted 2026-08-31: a count without its WHERE clause is not
-- a fact. A count without a run is not a count.)
--
-- ------------------------------------------------------------------
-- FILE NAMING
-- ------------------------------------------------------------------
-- Originally drafted as 14_profile_code21_exclusion_cost.sql. Renamed
-- because the finding moved: the exclusion cost (Section 4) is real
-- but the more useful result is that code 21's composition is itself
-- a signal (Section 5). If the old name is already committed,
-- git mv rather than deleting -- keep the history.
-- ==================================================================


-- ==================================================================
-- SECTION 1 -- What is actually inside the "other" bucket?
-- ------------------------------------------------------------------
-- Residual = everything not already bucketed by file 13's families.
-- The NULL branch is deliberate: sale_type_code NOT IN (...) evaluates
-- to NULL for NULL input, which silently drops rows. This bit us in
-- file 13 and cost 15 rows. Do not remove the IS NULL clause.
-- ==================================================================

SELECT
    sale_type_code,
    COUNT(*) AS n
FROM stg.property_sales
WHERE sale_date >= DATE '2017-01-01'
  AND (sale_type_code IS NULL
       OR sale_type_code NOT IN
           ('03','13','10','11','17','30','34','19','20'))
GROUP BY sale_type_code
ORDER BY n DESC;

-- RESULT (2026-09-01), 139,028 rows total:
--   21 -> 115,121   09 -> 11,438    22 -> 3,082    18 -> 2,733
--   33 ->   2,184   14 ->  1,402    06 -> 1,050    12 ->   706
--   08 ->     484   24 ->    362    15 ->   146    16 ->   142
--   35 ->      97   NULL ->    15   remainder < 15 each
--
-- [FINDING] "Other" is not a mixture. It is code 21 (83% of the
-- bucket, 37% of all transfers) with a tail.
--
-- [OPEN] Codes 22 (3,082) and 14 (1,402) are absent from
-- docs/terms_of_sale_legend.md. Look them up in the CAMA Resource
-- Guide PDF in the repo. If either is a land contract, it is
-- arguably market evidence and belongs in this analysis.
--
-- [OPEN] Code 33 is MISFILED. The legend places 33 in the strict
-- tier (Conventional, "To Be Determined") but it is falling into the
-- residual. The legend's "negligible volume -- ignore" note was
-- written against full-history counts and does not hold at 2,184
-- rows in-window. Reclassify.


-- ==================================================================
-- SECTION 2 -- Nominal-value check on code 21
-- ------------------------------------------------------------------
-- Before splitting into buckets, confirm the price column is usable
-- and find out where the mass sits. amt_sale_price is bigint, carried
-- unmodified from raw to stg.
--
-- "Nominal" here means a placeholder rather than a price: the paper-
-- work has a price field and someone had to type something into it,
-- but money did not change hands the way the form assumes.
-- ==================================================================

SELECT
    COUNT(*)                                            AS total_21,
    COUNT(*) FILTER (WHERE amt_sale_price IS NULL)      AS price_null,
    COUNT(*) FILTER (WHERE amt_sale_price = 0)          AS price_zero,
    COUNT(*) FILTER (WHERE amt_sale_price = 1)          AS price_one,
    COUNT(*) FILTER (WHERE amt_sale_price = 10)         AS price_ten,
    COUNT(*) FILTER (WHERE amt_sale_price = 100)        AS price_hundred,
    COUNT(*) FILTER (WHERE amt_sale_price < 0)          AS price_negative
FROM stg.property_sales
WHERE sale_date >= DATE '2017-01-01'
  AND sale_type_code = '21';

-- RESULT (2026-09-01):
--   total_21       115,121
--   price_null           0      <- column fully populated
--   price_zero      47,857
--   price_one       20,569
--   price_ten        1,494
--   price_hundred    5,753
--   price_negative       0
--
-- [FINDING] 75,673 rows (65.7%) sit on exactly four placeholder
-- values. A further 410 rows fall at other values <= $100, giving
-- 76,083 (66.1%) nominal under this file's definition.
--
-- Two-thirds of code 21 is paperwork. The question this file exists
-- to answer is what the other third is.


-- ==================================================================
-- SECTION 3 -- Four-bucket price split, code 21 vs code 03,
--              by neighborhood
-- ==================================================================

SELECT
    neighborhood,
    -- CODE 21 -- the 115,121-row question
    COUNT(*) FILTER (WHERE sale_type_code = '21')                   AS n_21,
    COUNT(*) FILTER (WHERE sale_type_code = '21'
                       AND amt_sale_price <= 100)                   AS n21_nominal,
    COUNT(*) FILTER (WHERE sale_type_code = '21'
                       AND amt_sale_price BETWEEN 101 AND 999)      AS n21_under_1k,
    COUNT(*) FILTER (WHERE sale_type_code = '21'
                       AND amt_sale_price BETWEEN 1000 AND 9999)    AS n21_1k_10k,
    COUNT(*) FILTER (WHERE sale_type_code = '21'
                       AND amt_sale_price >= 10000)                 AS n21_over_10k,
    -- CODE 03 -- the reference shape. Same four cuts.
    COUNT(*) FILTER (WHERE sale_type_code = '03')                   AS n_03,
    COUNT(*) FILTER (WHERE sale_type_code = '03'
                       AND amt_sale_price <= 100)                   AS n03_nominal,
    COUNT(*) FILTER (WHERE sale_type_code = '03'
                       AND amt_sale_price BETWEEN 101 AND 999)      AS n03_under_1k,
    COUNT(*) FILTER (WHERE sale_type_code = '03'
                       AND amt_sale_price BETWEEN 1000 AND 9999)    AS n03_1k_10k,
    COUNT(*) FILTER (WHERE sale_type_code = '03'
                       AND amt_sale_price >= 10000)                 AS n03_over_10k
FROM stg.property_sales
WHERE sale_date >= DATE '2017-01-01'
  AND sale_type_code IN ('21','03')
GROUP BY neighborhood
ORDER BY n_21 DESC;

-- RESULT (2026-09-01), 203 neighborhoods.
--
-- CITYWIDE:
--   bucket           code 21              code 03
--   <= $100 nominal   76,083  66.1%          285   0.4%
--   $101 - $999        2,742   2.4%          258   0.4%
--   $1k - $10k        11,318   9.8%        3,244   4.5%
--   >= $10k           24,978  21.7%       68,706  94.8%
--   total            115,121             72,493
--
-- SUM CHECK: buckets sum to the total on all 203 rows for both
-- codes, 0 failures. Totals reconcile independently to file 12
-- (115,121 and 72,493), computed there at a different grain.
--
-- [FINDING -- THE CONTROL HELD] Code 03 lands 94.8% in the top
-- bucket and 0.4% nominal. That is the shape a known-genuine market
-- population should have, and it is what makes the bucket cuts
-- defensible rather than arbitrary.
--
-- [FINDING -- THE MAIN RESULT] Code 21 contains 24,978 transfers
-- above $10,000. That is 34% the size of the entire arms-length
-- population, currently discarded on the strength of a label.


-- ==================================================================
-- SECTION 4 -- What does the exclusion actually cost?
-- ------------------------------------------------------------------
-- Two different ratios, easily confused. Both are computed here
-- because they answer different questions and rank neighborhoods
-- differently:
--
--   (a) pct_of_21_real  = n21_rm / n_21
--       "What is code 21 made of in this neighborhood?"
--       A statement about the COMPOSITION of code 21.
--
--   (b) pct_market_lost = n21_rm / (n21_rm + n03_rm)
--       "What fraction of this neighborhood's real-money transfers
--        disappears when code 21 is excluded?"
--       A statement about the COST TO THE ANALYSIS.
--
-- (b) is the exclusion-cost measure. (a) was mistakenly used for it
-- first, which produced a wrong ranking -- a thin arms-length base
-- makes a small absolute loss enormous in relative terms.
--
-- But (a) is not junk. It turns out to be the health signal, and
-- Section 5 tests it. The lesson is not that (a) was wrong; it is
-- that (a) and (b) are different measurements and each has to be
-- matched to its own question.
-- ==================================================================

WITH by_hood AS (
    SELECT
        neighborhood,
        COUNT(*) FILTER (WHERE sale_type_code = '21')                AS n_21,
        COUNT(*) FILTER (WHERE sale_type_code = '21'
                           AND amt_sale_price >= 10000)              AS n21_rm,
        COUNT(*) FILTER (WHERE sale_type_code = '03')                AS n_03,
        COUNT(*) FILTER (WHERE sale_type_code = '03'
                           AND amt_sale_price >= 10000)              AS n03_rm
    FROM stg.property_sales
    WHERE sale_date >= DATE '2017-01-01'
      AND sale_type_code IN ('21','03')
    GROUP BY neighborhood
)
SELECT
    neighborhood,
    n_21,
    n21_rm,
    n03_rm,
    n21_rm + n03_rm                                                  AS real_money_total,
    ROUND(100.0 * n21_rm / NULLIF(n_21, 0), 1)                       AS pct_of_21_real,
    ROUND(100.0 * n21_rm / NULLIF(n21_rm + n03_rm, 0), 1)            AS pct_market_lost
FROM by_hood
WHERE n_21 >= 300
  AND n21_rm + n03_rm >= 50
ORDER BY pct_market_lost DESC;

-- RESULT (2026-09-01), 117 neighborhoods. VERIFIED: DB output matched
-- an independently derived calculation from the Section 3 export to
-- within rounding on every row.
--
-- CITYWIDE: 24,978 / (24,978 + 68,706) = 26.7% of all real-money
-- transfers sit in code 21.
--
-- SPREAD of pct_market_lost:  16.8% to 57.7%, median 26.5%
-- SPREAD of pct_of_21_real:    7.6% to 43.4%, median 20.8%
--
-- MOST LOST                          LEAST LOST
--   Poletown East          57.7%       Schaefer 7/8 Lodge     16.8%
--   Corktown               53.8%       Evergreen Lahser 7/8   17.5%
--   Gratiot Town/Kettering 50.8%       Schulze                17.5%
--   East Village           50.5%       Aviation Sub           18.0%
--   Woodbridge             50.4%       Berg-Lahser            18.3%
--   North End              46.9%       Evergreen-Outer Drive  18.3%
--   Chadsey Condon         46.9%       University District    18.7%
--   McDougall-Hunt         45.2%       The Eye                19.0%
--
-- THE TWO METRICS DISAGREE:
--   East English Village   43.4% of 21 is real money -> 30.7% lost
--   McDougall-Hunt         11.8% of 21 is real money -> 45.2% lost
--
-- McDougall-Hunt has the lowest real-money rate inside code 21 and
-- loses the most of its actual market, because its arms-length base
-- is only 86 transfers.


-- ==================================================================
-- SECTION 5 -- Does code 21 composition track market strength?
-- ------------------------------------------------------------------
-- !! NOT YET RUN AGAINST THE DATABASE. Figures below were computed
-- !! outside Postgres from the Section 4 export. Run and verify.
--
-- Hypothesis: pct_of_21_real is higher where the arms-length market
-- is stronger -- i.e. code 21's internal composition is itself a
-- health signal, independent of whether any individual code 21 sale
-- is admissible as market evidence.
--
-- Health proxy used: arms_share = n_03 / (n_21 + n_03).
--
-- !! CAVEAT -- this proxy contains n_21, and so does the variable
-- !! being tested (n21_rm / n_21). A shared term can manufacture
-- !! correlation. See open question F. This must be re-run against
-- !! a proxy with no code 21 in it before the result is trusted.
-- ==================================================================

WITH by_hood AS (
    SELECT
        neighborhood,
        COUNT(*) FILTER (WHERE sale_type_code = '21')                AS n_21,
        COUNT(*) FILTER (WHERE sale_type_code = '21'
                           AND amt_sale_price >= 10000)              AS n21_rm,
        COUNT(*) FILTER (WHERE sale_type_code = '03')                AS n_03
    FROM stg.property_sales
    WHERE sale_date >= DATE '2017-01-01'
      AND sale_type_code IN ('21','03')
    GROUP BY neighborhood
),
metrics AS (
    SELECT
        neighborhood,
        100.0 * n_03   / NULLIF(n_21 + n_03, 0)  AS arms_share,
        100.0 * n21_rm / NULLIF(n_21, 0)         AS pct_of_21_real
    FROM by_hood
    WHERE n_21 >= 300
)
SELECT
    COUNT(*)                                        AS n_neighborhoods,
    ROUND(CORR(arms_share, pct_of_21_real)::numeric, 3)         AS pearson_r,
    ROUND((CORR(arms_share, pct_of_21_real)^2)::numeric, 3)     AS r_squared
FROM metrics;

-- DERIVED RESULT (117 neighborhoods, PENDING DB VERIFICATION):
--   pearson_r = 0.508
--   r_squared = 0.258
--
-- QUINTILES of arms_share vs mean pct_of_21_real -- monotonic, no
-- reversals:
--   arms-share 13.3-27.7%  ->  mean code-21 real-money  16.2%  (n=24)
--   arms-share 27.9-34.9%  ->  mean code-21 real-money  19.2%  (n=23)
--   arms-share 35.1-41.3%  ->  mean code-21 real-money  21.7%  (n=24)
--   arms-share 41.4-45.2%  ->  mean code-21 real-money  22.9%  (n=23)
--   arms-share 45.5-53.5%  ->  mean code-21 real-money  26.2%  (n=23)
--
-- [FINDING] The relationship holds and is monotonic across quintiles.
-- Moderate strength: comparable to the r = 0.521 payroll-efficiency
-- correlation in the MLB case study. "Tracks with," not "determines."
--
-- [OBSERVATION -- NOT YET A FINDING] r-squared = 0.258 means roughly
-- three quarters of the variance is DISAGREEMENT between the two
-- signals, and the disagreement may carry more information than the
-- agreement. Residuals from the fit:
--
--   CODE 21 STRONGER THAN ARMS-LENGTH PREDICTS (positive residual):
--     Woodbridge +19.9, Corktown +18.6, Midtown +17.7,
--     East English Village +17.7, [blank] +16.8, Martin Park +13.3,
--     Boston Edison +12.2
--
--   CODE 21 WEAKER THAN ARMS-LENGTH PREDICTS (negative residual):
--     Riverbend -8.2, Schaefer 7/8 Lodge -7.8, Cadillac Heights -7.6,
--     Aviation Sub -7.0, Franklin -7.0, Mount Olivet -6.9,
--     Airport Sub -6.8
--
-- Corktown is the sharpest case: arms_share 23.8% (near the bottom of
-- the city, alongside McDougall-Hunt) but pct_of_21_real 35.3% (near
-- the top). The two signals point in opposite directions.
--
-- The positive-residual list reads as neighborhoods in transition;
-- the negative-residual list reads as stable conventional markets
-- where everything real moves through code 03. If that holds, the
-- residual is measuring CHANNEL BEHAVIOUR, not health -- a third
-- signal.
--
-- DO NOT claim this yet. It is seven neighborhoods per side and the
-- pattern is being read off a list, which is the same thin inference
-- flagged in finding 4 below. This is the file 15 question.


-- ==================================================================
-- FINDINGS
-- ==================================================================
--
-- 1. THE EXCLUDED POPULATION IS LARGE AND REAL.
--    24,978 code-21 transfers priced above $10,000, against 68,706
--    arms-length transfers. Roughly one in four real-money transfers
--    in Detroit 2017+ is discarded by label.
--
-- 2. THE BUCKET CUTS ARE VALIDATED, NOT ASSUMED.
--    Code 03 lands 94.8% above $10k. The control behaved.
--
-- 3. THE EXCLUSION IS NOT UNIFORM.
--    16.8% to 57.7% across 117 neighborhoods. A method described as
--    a single standard is in practice 117 different standards.
--
-- 4. IT BITES HARDEST WHERE THE ARMS-LENGTH MARKET IS THINNEST.
--    The top of the loss list mixes collapse (Poletown East,
--    McDougall-Hunt) with transition (Corktown, Woodbridge). The
--    bottom is uniformly stable northwest-side residential with deep
--    conventional markets.
--    TODO(caden): pressure-test this. It is a pattern read off two
--    lists of eight. The direction is probably right; the confidence
--    is not yet earned. A neighborhood-level classification would
--    settle it.
--
-- 5. CODE 21 COMPOSITION IS ITSELF A SIGNAL.
--    pct_of_21_real correlates with arms-length share at r = 0.508
--    across 117 neighborhoods, monotonic across quintiles. This is
--    the finding the thesis rests on, and the one that does not
--    depend on any individual code 21 sale being admissible --
--    a $45,000 transfer of any kind does not occur in a neighborhood
--    where nothing is worth $45,000.
--    Pending the independent re-test in open question F.
--
-- 6. CODE 21 REPEATS THE CODE 13 PATTERN.
--    One label covering two opposite phenomena: genuine transactions
--    filed under a catch-all where the market functions, and
--    abandonment paperwork where it does not. Third instance of the
--    project's through-line -- A LABEL IN THIS DATA IS NOT A FACT.
--    (First: code 13, Land Bank giveaway vs city land assembly.
--     Second: retention rate, same number opposite stories.)
--
--    This is the spine of the case study. The argument is not
--    "here is a Detroit health index." It is: a neighborhood health
--    index cannot be built by applying the standard filter, because
--    in a distressed city the standard's own categories stop meaning
--    one thing. The labels have to be decomposed first.
--
--
-- ==================================================================
-- OPEN QUESTIONS -- what this file does NOT establish
-- ==================================================================
--
-- A. Price above $10,000 is a PROXY for a genuine transaction, not
--    proof of one. A code-21 row at $45,000 could still be an
--    intra-family sale at a real but non-market price. This file
--    cannot distinguish those. Sampling actual deeds, or checking
--    price against assessed value, would.
--
--    This is why finding 5 is framed as a second MEASUREMENT rather
--    than an argument for adding code 21 rows to the sales pool.
--    The measurement survives (A); inclusion does not.
--
-- B. Should the wide tier be redefined to admit code 21 above a
--    price floor? Premature -- see (A).
--
-- C. File 13 finding 4 still stands: the foreclosure family is only
--    2.1% of transfers in-window, so the IAAO 20% rule almost
--    certainly never fires in 2017+. That rule is the citable spine
--    of the two-tier design. If it never fires, the tier structure
--    or the window needs rethinking, independent of code 21.
--
-- D. Minimum-n threshold unresolved (see header). 117 of 204
--    neighborhoods clear n_21 >= 300; the excluded 87 are not
--    necessarily uninteresting.
--
-- E. The blank-neighborhood row (14,600 transfers, 4.74%) is
--    included in Section 3 totals and sits at 37.5% real-money 21,
--    a large positive residual. Still not understood. From file 13.
--
-- F. *** NEXT SESSION, HIGHEST PRIORITY ***
--    Re-run Section 5 against a health proxy that contains no code 21
--    term. File 13 already has government-family (code 13) counts per
--    neighborhood, which are fully independent of both variables.
--    Suggested proxy: n03_rm / (n03_rm + n_13), or the arms:gov
--    parcel ratio from file 12.
--    If r holds near 0.5, finding 5 is solid and the thesis stands.
--    If r collapses, the correlation was an artifact of the shared
--    denominator and finding 5 must be withdrawn.
--
-- G. Is the Section 5 residual measuring channel behaviour
--    (transition vs stable) rather than health? File 15.
--
--
-- ==================================================================
-- HOUSEKEEPING
-- ==================================================================
-- Numbering convention: 01-09 profiling, 10+ builds. Files 13 and 14
-- are both profiling in the build range. Settle before file 20.
--
-- docs/terms_of_sale_legend.md needs a pass with the CAMA Resource
-- Guide open: codes 22 and 14 are missing entirely, and code 33 is
-- filed in the strict tier while landing in the residual.
-- ==================================================================
