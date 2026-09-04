-- ==================================================================
-- 15_retest_finding5_independent_proxy.sql
--
-- Detroit Property Pipeline  |  staging-layer profiling
-- Author: Caden Raymond
-- Written: 2026-09-04
--
-- Closes file 14, open question F.
--
-- ------------------------------------------------------------------
-- WHAT THIS FILE TESTS
-- ------------------------------------------------------------------
-- File 14, finding 5: neighborhoods with a higher proportion of
-- arms-length transfers also see a higher proportion of non-nominal
-- transfers within the code 21 bucket. Evidence was r = 0.508.
--
-- That number could not be trusted. The health proxy used to produce
-- it was n_03 / (n_21 + n_03), and the signal it was tested against
-- was n21_rm / n_21. Both contain n_21.
--
-- Why that matters: a neighborhood flooded with code 21 paperwork
-- gets a large n_21. That pushes the proxy DOWN (bigger denominator)
-- and pushes the signal DOWN (more nominal rows diluting n21_rm).
-- Both fall together -- and they would fall together even with no
-- real relationship, purely because the same quantity sits in both
-- denominators. That is what a statistical artifact looks like.
--
-- This file rebuilds the health proxy with NO code 21 in it and
-- re-runs the correlation. If the relationship survives, finding 5
-- is real. If it collapses, finding 5 was arithmetic.
--
-- ------------------------------------------------------------------
-- PROXY CHOICE: ROW GRAIN
-- ------------------------------------------------------------------
-- Selected: n03_rm / (n03_rm + n_13) -- arms-length measured against
-- the government channel rather than against code 21.
--
-- Grain reasoning: in a city like Detroit where roughly a third of
-- the land is vacant, parcel grain scores every neighborhood by its
-- vacancy rate rather than by its market activity. Since every
-- Detroit neighborhood carries some level of vacant land, a
-- parcel-grain health metric would be skewed by a legacy of the
-- 2008-2013 collapse rather than measuring what is happening now.
-- Row grain counts events, so it captures a market that is active
-- on comparatively few properties.
--
-- NOTE ON THE ALTERNATIVE: parcel grain (file 12's arms:gov ratio)
-- is defensible on the opposite argument -- a neighborhood where
-- twenty houses trade repeatedly while four hundred sit dead is not
-- healthy, and row grain hides that. The choice above is a judgment
-- call, not a settled question. Revisit when the mart layer is
-- specified.
--
-- ------------------------------------------------------------------
-- INTERPRETATION BANDS -- FIXED BEFORE THE QUERY WAS RUN
-- ------------------------------------------------------------------
-- These bands were written down before any query executed, so that
-- the result could not be read to fit the finding. A number like
-- 0.31 supports either "survived but weaker" or "mostly evaporated"
-- depending on which reading is preferred, and the preference is
-- unavoidable once the number is visible.
--
--   r < 0.30           -> original was an artifact; WITHDRAW finding 5
--   0.30 <= r < 0.45   -> real but inflated; REWORD finding 5 weaker
--   r >= 0.45          -> finding 5 STANDS as written
--
-- ------------------------------------------------------------------
-- PREDICTION ON RECORD -- AND IT FAILED
-- ------------------------------------------------------------------
-- Predicted before running: r would drop into the 0.30-0.40 range.
-- Reasoning: some of the 0.508 was expected to be real (a functioning
-- market should show up in every code), but the shared denominator
-- was expected to have been inflating it meaningfully. Anything above
-- 0.45 was called surprising.
--
-- ACTUAL: 0.635. The prediction was wrong in both magnitude and
-- direction -- r went UP, not down. Logged here for the same reason
-- file 12's confirmed prediction was logged. A prediction log that
-- only records the hits is not a log.
-- ==================================================================


-- ==================================================================
-- PROXY 1 -- price-filtered arms-length vs government
-- ==================================================================

WITH by_hood AS (
    SELECT
        neighborhood,
        COUNT(*) FILTER (WHERE sale_type_code = '21')                 AS n_21,
        COUNT(*) FILTER (WHERE sale_type_code = '21'
                           AND amt_sale_price >= 10000)               AS n21_rm,
        COUNT(*) FILTER (WHERE sale_type_code = '03'
                           AND amt_sale_price >= 10000)               AS n03_rm,
        COUNT(*) FILTER (WHERE sale_type_code = '13')                 AS n_13
    FROM stg.property_sales
    WHERE sale_date >= DATE '2017-01-01'
      AND sale_type_code IN ('21','03','13')
    GROUP BY neighborhood
),
metrics AS (
    SELECT
        neighborhood,
        100.0 * n03_rm / NULLIF(n03_rm + n_13, 0)   AS arms_share,      -- proxy: NO code 21
        100.0 * n21_rm / NULLIF(n_21, 0)            AS pct_of_21_real   -- the signal
    FROM by_hood
    WHERE n_21 >= 300                                                   -- same population as file 14
)
SELECT
    COUNT(*)                                                 AS n_neighborhoods,
    ROUND(CORR(arms_share, pct_of_21_real)::numeric, 3)      AS pearson_r,
    ROUND((CORR(arms_share, pct_of_21_real)^2)::numeric, 3)  AS r_squared
FROM metrics;

-- RESULT (2026-09-04):
--   n_neighborhoods  117
--   pearson_r        0.635
--   r_squared        0.403


-- ==================================================================
-- PROXY 2 -- unfiltered arms-length vs government
-- ------------------------------------------------------------------
-- SECOND CONCERN, RAISED AFTER SEEING PROXY 1's RESULT:
--
-- Proxy 1 removed the shared COUNT (n_21) but introduced a shared
-- PRICE THRESHOLD. Both variables now asked "what fraction of things
-- here clear $10,000." In a neighborhood where property is simply
-- worth more, more of everything clears $10k, in every code -- so
-- the correlation might have been reporting property VALUES rather
-- than market HEALTH. Those are different claims and only the second
-- one supports the thesis.
--
-- Proxy 2 drops the price filter from the health proxy only. The
-- $10k threshold now exists solely on the signal side.
--
-- HONESTY NOTE: this concern was raised AFTER the Proxy 1 result was
-- visible, which is a weaker basis for doubt than a pre-registered
-- one. Recorded as such rather than presented as part of the plan.
-- ==================================================================

WITH by_hood AS (
    SELECT
        neighborhood,
        COUNT(*) FILTER (WHERE sale_type_code = '21')                 AS n_21,
        COUNT(*) FILTER (WHERE sale_type_code = '21'
                           AND amt_sale_price >= 10000)               AS n21_rm,
        COUNT(*) FILTER (WHERE sale_type_code = '03')                 AS n_03,
        COUNT(*) FILTER (WHERE sale_type_code = '13')                 AS n_13
    FROM stg.property_sales
    WHERE sale_date >= DATE '2017-01-01'
      AND sale_type_code IN ('21','03','13')
    GROUP BY neighborhood
),
metrics AS (
    SELECT
        neighborhood,
        100.0 * n_03 / NULLIF(n_03 + n_13, 0)   AS arms_share,          -- no price filter
        100.0 * n21_rm / NULLIF(n_21, 0)        AS pct_of_21_real
    FROM by_hood
    WHERE n_21 >= 300
)
SELECT
    COUNT(*)                                                 AS n_neighborhoods,
    ROUND(CORR(arms_share, pct_of_21_real)::numeric, 3)      AS pearson_r,
    ROUND((CORR(arms_share, pct_of_21_real)^2)::numeric, 3)  AS r_squared
FROM metrics;

-- RESULT (2026-09-04):
--   n_neighborhoods  117
--   pearson_r        0.631
--   r_squared        0.399


-- ==================================================================
-- VERDICT
-- ==================================================================
--
-- FINDING 5 HOLDS. It clears the pre-set 0.45 band with room to
-- spare, on a proxy containing no code 21 at all.
--
--   proxy                                    r        independent of 21?
--   n_03 / (n_21 + n_03)      [file 14]     0.508     NO
--   n03_rm / (n03_rm + n_13)  [proxy 1]     0.635     yes
--   n_03 / (n_03 + n_13)      [proxy 2]     0.631     yes
--
-- The two independent proxies agree to within 0.004. Population held
-- at n = 117 across all three, so the numbers are comparable.
--
-- BOTH CONCERNS RESOLVED:
--   - Shared denominator: dead. Removing n_21 from the proxy did not
--     weaken the relationship -- it strengthened it.
--   - Shared price threshold: dead. Removing the $10k filter from the
--     proxy moved r by 0.004.
--
-- WHAT THE CORRELATION SAYS, PLAINLY:
-- Take two neighborhoods. In the first, most property movement is
-- genuine arms-length sale rather than government transfer. In the
-- second, government transfers dominate. The first kind of
-- neighborhood ALSO carries more real money inside its code 21
-- bucket. Where a market functions, it shows up in every code --
-- including the catch-all. Where it does not, code 21 is nearly all
-- paperwork.
--
-- WHAT r-SQUARED ADDS:
-- r = 0.635 says the two measures travel together reliably.
-- r-squared = 0.403 says arms-length share accounts for about 40% of
-- why neighborhoods differ in code 21 composition. The remaining 60%
-- is neighborhoods that do not fit the line -- and that residual is
-- the next question (see below).
--
-- WHAT THIS DOES NOT ESTABLISH:
-- File 14 open question A still stands unchanged. Price above
-- $10,000 remains a PROXY for a genuine transaction, not proof of
-- one. This is why finding 5 is framed as a second MEASUREMENT read
-- alongside arms-length share, not as an argument for adding code 21
-- rows to the sales pool. The measurement survives (A); inclusion
-- does not.
--
--
-- ==================================================================
-- NEXT
-- ==================================================================
--
-- 1. UPDATE FILE 14. Mark open question F CLOSED and point it here.
--    Update finding 5 to cite r = 0.631/0.635 rather than 0.508.
--    Section 5's caveat about the shared denominator is now resolved
--    and should say so.
--
-- 2. NUMBERING. File 14 flagged the residual/channel-behaviour
--    question as "file 15." That slot is now taken by this re-test.
--    The residual question becomes file 16.
--
-- 3. THE RESIDUAL QUESTION (file 16). Roughly 60% of the variance is
--    disagreement between the two signals. Corktown: arms_share near
--    the bottom of the city, pct_of_21_real near the top. The
--    positive-residual neighborhoods read as transition; the
--    negative-residual ones read as stable conventional markets. If
--    that holds, the residual measures CHANNEL BEHAVIOUR rather than
--    health -- a third signal. Currently seven neighborhoods per
--    side, which is not enough. Recompute residuals against the NEW
--    proxy before drawing anything from them; the file 14 residual
--    list was built on the old one.
--
-- 4. STILL OPEN FROM FILE 14: legend gaps (codes 22, 14 missing;
--    code 33 misfiled), the IAAO 20% rule almost certainly never
--    firing in-window, the arbitrary n_21 >= 300 threshold, and the
--    14,600 blank-neighborhood transfers.
-- ==================================================================
