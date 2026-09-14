-- ==================================================================
-- 16_profile_residual_channel_behaviour.sql
--
-- Detroit Property Pipeline  |  staging-layer profiling
-- Author: Caden Raymond
-- Written: 2026-09-14
--
-- Opens file 14, open question G.
--
-- ------------------------------------------------------------------
-- WHAT A RESIDUAL IS, AND WHY THIS FILE EXISTS
-- ------------------------------------------------------------------
-- Finding 5 established that two neighborhood-level measures move
-- together across the city: arms-length share (how much property
-- movement is genuine market sale rather than government transfer)
-- and pct_of_21_real (how much of the code 21 bucket is real money
-- rather than nominal paperwork). r = 0.635, r-squared = 0.403.
--
-- r-squared = 0.403 means the fit explains about 40% of why
-- neighborhoods differ from one another. The other ~60% is
-- DISAGREEMENT between the two measures.
--
-- A residual is that disagreement, per neighborhood. Fit a line
-- through the 117 points; the line predicts what a neighborhood's
-- code 21 composition should be, given its arms-length share. The
-- residual is actual minus predicted:
--
--   POSITIVE -> more real money in code 21 than the market share
--               predicted. The line under-shot this neighborhood.
--   NEGATIVE -> less than predicted. The line over-shot.
--
-- HYPOTHESIS (from file 14, NOT established): the residual is not
-- noise. It measures CHANNEL BEHAVIOUR -- how property moves --
-- rather than health. Neighborhoods in transition route real
-- transactions through the code 21 catch-all; stable conventional
-- markets route everything real through code 03.
--
-- ------------------------------------------------------------------
-- WHY THE RESIDUALS HAD TO BE RECOMPUTED
-- ------------------------------------------------------------------
-- File 14 listed residuals, but they were fit against the ORIGINAL
-- proxy, n_03 / (n_21 + n_03) -- the one file 15 replaced for
-- sharing a denominator with the signal. A new proxy means a new
-- line, which means every residual changes. The file 14 list was
-- stale and could not be read from.
--
-- ------------------------------------------------------------------
-- DECISIONS
-- ------------------------------------------------------------------
-- [DECISION] Fit against proxy 1, n03_rm / (n03_rm + n_13).
--   Reason: the real-money concept stays consistent with downstream
--   work in the mart layer.
--   COUNTERARGUMENT ON RECORD: proxy 1 shares a $10,000 price
--   threshold with the signal. For the CORRELATION that was worth
--   0.004 (file 15, proxy 2). A residual analysis studies
--   disagreement rather than agreement, so the threshold could
--   plausibly matter more here than it did there. Refitting against
--   proxy 2 and comparing membership is cheap and not yet done.
--   TODO(caden).
--
-- [DECISION] Cut at +/- 1 standard deviation of the residuals,
--   rather than a top-N.
--   Reason: a top-N is chosen by how many rows fit comfortably in a
--   comment block. A standard deviation is defined by the data's own
--   spread. File 14 read its pattern off seven names per side and
--   flagged that thinness itself as a problem.
--   Returned 35 of 117 neighborhoods (30%) -- 19 positive, 16
--   negative. Close to the ~32% a normal distribution puts beyond
--   +/- 1 SD, so the spread is behaving.
--
-- NOTE ON THE QUERY: the SD of the residuals cannot be computed in
-- the same aggregate as the slope and intercept -- residuals do not
-- exist until the line has been fit and applied per row. Hence two
-- passes. Both CROSS JOINs attach a single-row aggregate to all 117
-- rows, which is the intended use here, not an accident.
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
        100.0 * n_03   / NULLIF(n_03 + n_13, 0)  AS arms_share,      -- the ruler
        100.0 * n21_rm / NULLIF(n_21, 0)         AS pct_of_21_real   -- the signal
    FROM by_hood
    WHERE n_21 >= 300                                                -- same population as files 14, 15
),
fit AS (
    SELECT
        REGR_SLOPE(pct_of_21_real, arms_share)     AS slope,         -- dependent variable first
        REGR_INTERCEPT(pct_of_21_real, arms_share) AS intercept
    FROM metrics
),
resid AS (
    SELECT
        m.neighborhood,
        m.arms_share,
        m.pct_of_21_real,
        f.slope * m.arms_share + f.intercept                      AS predicted,
        m.pct_of_21_real - (f.slope * m.arms_share + f.intercept) AS residual
    FROM metrics m
    CROSS JOIN fit f
)
SELECT
    neighborhood,
    ROUND(arms_share::numeric, 1)      AS arms_share,
    ROUND(pct_of_21_real::numeric, 1)  AS pct_of_21_real,
    ROUND(residual::numeric, 1)        AS residual
FROM resid
CROSS JOIN (SELECT STDDEV(residual) AS sd FROM resid) s
WHERE ABS(residual) >= s.sd
ORDER BY residual DESC;


-- ==================================================================
-- RESULT (2026-09-14) -- 35 of 117 neighborhoods beyond +/- 1 SD
-- ==================================================================
--
-- POSITIVE RESIDUAL -- more real money in code 21 than predicted:
--   neighborhood                arms_share   pct_21_real   resid
--   [blank]                          48.3         37.5      17.2
--   East English Village             90.6         43.4      15.8
--   Woodbridge                       62.7         38.1      15.2
--   Midtown                          77.6         37.4      12.0
--   Martin Park                      74.2         36.2      11.4
--   East Village                     26.5         26.4       9.8
--   Corktown                         81.4         35.3       9.3
--   Boston Edison                    86.8         35.9       8.9
--   North End                        35.6         26.4       8.3
--   Virginia Park Community          46.7         28.3       8.3
--   Campau/Banglatown                37.0         25.8       7.4
--   Morningside                      59.2         28.6       6.4
--   Russell Woods                    65.1         29.4       6.2
--   Denby                            75.0         30.9       6.0
--   Islandview                       43.2         25.2       5.8
--   Buffalo Charles                  63.4         28.5       5.6
--   LaSalle Gardens                  55.7         27.2       5.6
--   Moross-Morang                    81.0         31.4       5.5
--   Jefferson Chalmers               49.1         25.8       5.3
--
-- NEGATIVE RESIDUAL -- less real money in code 21 than predicted:
--   The Eye                          85.8         21.6      -5.3
--   Mount Olivet                     53.3         15.9      -5.3
--   University District              96.0         23.2      -5.4
--   Warren Ave Community             69.5         18.5      -5.5
--   Airport Sub                      13.8          8.8      -5.6
--   Northeast Central District       43.5         13.8      -5.7
--   Evergreen-Outer Drive            81.5         20.0      -6.1
--   Schulze                          86.3         20.8      -6.1
--   Evergreen Lahser 7/8             78.1         19.1      -6.3
--   Cadillac Heights                 20.2          9.0      -6.5
--   Weatherby                        59.5         15.2      -7.1
--   Riverbend                        17.1          7.6      -7.3
--   McDowell                         88.2         19.8      -7.5
--   Berg-Lahser                      80.8         17.7      -8.3
--   Aviation Sub                     86.7         16.5     -10.5
--   Schaefer 7/8 Lodge               90.0         16.3     -11.2
--
--
-- ==================================================================
-- [FINDING] THE PATTERN SURVIVED THE PROXY SWAP
-- ==================================================================
-- All seven file 14 positive names are still positive: [blank],
-- East English Village, Woodbridge, Midtown, Martin Park, Corktown,
-- Boston Edison. On the negative side Schaefer 7/8 Lodge, Aviation
-- Sub, Riverbend, Cadillac Heights, Mount Olivet and Airport Sub all
-- held. Franklin dropped off entirely.
--
-- Magnitudes moved; membership largely did not. The residual
-- structure is a property of the data, not of the discarded proxy.
--
--
-- ==================================================================
-- [FINDING] CORKTOWN WAS MIS-RANKED BY THE OLD PROXY
-- ==================================================================
-- File 14 calls Corktown "the sharpest case: arms_share 23.8% (near
-- the bottom of the city) but pct_of_21_real 35.3% (near the top).
-- The two signals point in opposite directions."
--
-- THAT IS NOW FALSE. Under the new proxy Corktown's arms_share is
-- 81.4% -- near the TOP of the city, the opposite end of the
-- distribution. It is high on both measures, and its residual halved
-- from +18.6 to +9.3, dropping it from first to seventh.
--
-- Cause: Corktown carries enormous code 21 volume. The old proxy,
-- n_03 / (n_21 + n_03), put that volume in its denominator, which
-- pushed Corktown's apparent market share down. The new proxy
-- measures arms-length against the government channel instead, and
-- Corktown's market reads as strong.
--
-- [DECISION] Strike the Corktown claim from file 14 Section 5.
--
-- Broader lesson, and the reason this matters beyond one
-- neighborhood: the shared denominator was not merely inflating r by
-- a few hundredths. It was actively MIS-RANKING individual
-- neighborhoods -- and doing it worst precisely where code 21 volume
-- was highest, which is where the whole analysis is aimed. A
-- correlation can be nearly right while the rows underneath it are
-- badly wrong.
--
--
-- ==================================================================
-- [OBSERVATION -- NOT YET A FINDING]
-- THE NEGATIVE SIDE IS NOT ONE THING
-- ==================================================================
-- File 14's hypothesis assumed a single axis: positive residual =
-- transition, negative residual = stable conventional market. The
-- positive side supports that reading. The negative side does not.
--
-- Sort the negative list by arms_share and it splits in two:
--
--   HIGH arms_share -- University District 96.0, Schaefer 7/8 Lodge
--   90.0, McDowell 88.2, Aviation Sub 86.7, Schulze 86.3, The Eye
--   85.8, Evergreen-Outer Drive 81.5, Berg-Lahser 80.8, Evergreen
--   Lahser 7/8 78.1. Stable northwest-side residential. Reads as:
--   the conventional market works, so nothing real needs the
--   catch-all.
--
--   LOW arms_share -- Airport Sub 13.8, Riverbend 17.1, Cadillac
--   Heights 20.2, Northeast Central District 43.5. Bottom of the
--   city. Reads as: there is little real money moving through ANY
--   channel.
--
-- Same residual sign, opposite causes -- which is the project's
-- through-line appearing a fourth time. A LABEL IN THIS DATA IS NOT
-- A FACT, and now: A RESIDUAL SIGN IS NOT A FACT EITHER.
--
-- The positive side is more coherent: Woodbridge, Midtown, Corktown,
-- Islandview, East Village, North End, Boston Edison,
-- Campau/Banglatown -- largely the greater-downtown ring.
--
-- DO NOT CLAIM THIS YET. It is a pattern read off a sorted column,
-- which is the same thin inference flagged in file 14 finding 4. It
-- needs a test, not a reading.
--
--
-- ==================================================================
-- NEXT
-- ==================================================================
--
-- 1. STRIKE the Corktown claim in file 14 Section 5. It is now
--    known-false, not merely stale.
--
-- 2. TEST THE ASYMMETRY. The negative side appears to be two
--    populations. A third variable is needed to separate
--    "conventional market works" from "no market at all" --
--    candidates: total transfer volume per parcel, the code 13
--    government share on its own, or median code 03 price. If a
--    clean split exists, the channel-behaviour hypothesis survives
--    on the positive side only, and the negative side needs its own
--    account.
--
-- 3. REFIT AGAINST PROXY 2 and compare membership beyond +/- 1 SD.
--    If the lists largely overlap, the $10k threshold is not doing
--    work here and one line says so. If they diverge, that is
--    itself a finding.
--
-- 4. THE [blank] NEIGHBORHOOD is the largest positive residual in
--    the city at +17.2, on 14,600 transfers. Still unexplained,
--    carried since file 13. It is now distorting a named result and
--    should stop being deferred.
-- ==================================================================
