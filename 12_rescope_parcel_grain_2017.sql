-- =============================================================================
-- 12_rescope_parcel_grain_2017.sql
-- Detroit Property Pipeline
--
-- TODO(caden): rewrite this header in my own words before this goes in the
-- portfolio. Drafted by Claude on 8/31 under time pressure; the arrangement
-- from file 10 onward is that I write headers and Claude reviews. The reason
-- still holds -- an interviewer asks you to explain the decision live, not to
-- recite the comment.
--
-- PURPOSE
--   Re-run file 06 Section 2 inside the LOCKED ANALYSIS WINDOW (2017 -> present)
--   and find out whether the 1.30x government-over-arms-length parcel gap
--   survives. File 06 flagged itself as directional only: both of its queries
--   were unfiltered by date because sale_date was still text. File 11 cleared
--   that blocker. This is the first analytical payoff of the staging layer.
--
--   WHY A NEW FILE AND NOT AN EDIT TO 06. File 06 is the dated record of a run
--   against raw, and it is the provenance for the 1.30x figure. This project has
--   now been bitten twice by numbers that lost their WHERE-clause context
--   (file 11 S1.1 and S1.5). Overwriting the file that HOLDS that context would
--   be an odd move. 06 stands as the full-history baseline; 12 is the scoped
--   comparison.
--
--   WHAT THE STAGING LAYER BOUGHT. Compare the WHERE clauses:
--       file 06:  WHERE LEFT(term_of_sale, 2) = '13'          (raw, text date,
--                                                              no window possible)
--       file 12:  WHERE sale_type_code = '13'
--                   AND sale_date >= DATE '2017-01-01'         (stg)
--   No LEFT() parse, no cast, and the date filter is now expressible at all.
--   That is the layer earning its keep.
--
-- PREDICTION MADE BEFORE RUNNING (recorded because a confirmed prediction is a
-- better story than a number that just appeared)
--   The gap should NARROW. Detroit's bankruptcy (2013) and the tax-foreclosure
--   wave that followed pushed enormous volume through government channels in
--   2013-2016. Arms-length sales, by contrast, tick along steadily -- a burst
--   would imply a booming market, which Detroit was not. Cutting pre-2017
--   therefore cuts disproportionately from the government side. Numerator
--   shrinks faster than denominator; ratio falls.
--
-- HEADLINE RESULTS (2026-08-31)
--                          ROWS                    DISTINCT PARCELS
--   Government (13)       70,275                        60,180
--   Arms-length (03)      72,493                        53,252
--
--   Parcel-grain ratio:  60,180 / 53,252 = 1.13x   (was 1.30x full history)
--   Row-grain ratio:     70,275 / 72,493 = 0.97x   (was 1.08x full history)
--
--   Rows per parcel:     government 1.17 (was 1.21)
--                        arms-length 1.36 (was 1.46)
--
--   [PREDICTION CONFIRMED] Government lost 32.7% of its rows to the filter
--   (104,443 -> 70,275). Arms-length lost 25.1% (96,752 -> 72,493). The
--   bankruptcy-era distress volume shows up exactly where it was expected to,
--   and it is the mechanism behind the narrowing.
--
--   [THE CLAIM FROM FILE 06 MUST BE REWORDED] File 06 closes with:
--       "...a 1.30x gap that holds whether measured in transactions or in
--        properties."
--   That is FALSE inside the locked window. At row grain, arms-length now leads
--   (72,493 vs 70,275). The finding splits:
--       PARCEL GRAIN -- survives. More Detroit properties have moved through a
--         government channel (60,180) than have sold on the open market
--         (53,252) since 2017. A 1.13x gap.
--       ROW GRAIN -- reverses. There are slightly MORE arms-length transactions
--         than government transfers in the window.
--   Both are true and they are not in conflict. Arms-length is the more
--   duplicated side (1.36 vs 1.17), so more transactions spread across fewer
--   properties. A functioning market re-trades the same houses; the government
--   channel touches more distinct properties once each. The split is a sharper
--   finding than the original, not a weaker one -- it says the government
--   channel is BROADER while the private market is DEEPER.
--
--   [THE GRAIN LESSON, THIRD TIME] File 06's near-miss was comparing a
--   deduplicated count on one side against a raw count on the other. Same trap
--   here in a new costume: quoting 1.13x as "the ratio" without saying which
--   grain it is measured at would be the same error. State the grain every time.
--
-- SCOPE NOTE
--   sale_date >= '2017-01-01' silently excludes the 1 NULL-date row (file 11
--   S1.4). Correct behavior -- a row with no date cannot be placed in a window --
--   but recorded here so it is not rediscovered as a discrepancy later.
--
-- Run date: 2026-08-31
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- ROW GRAIN VS PARCEL GRAIN, BOTH SIDES, 2017+
-- =============================================================================

-- 1.1  GOVERNMENT (13), scoped.
--
--      RESULT:  all_rows = 70,275 | distinct_parcels = 60,180
--
--      10,095 excess rows -- 1.17 rows per parcel, down from 1.21 unscoped.
--      A shorter window gives a parcel fewer chances to repeat, so some decay
--      is expected. Chain of custody is still a systematic feature, just a
--      slightly shallower one inside the window.
--
--      NOTE ON RTRIM: retained from file 06. The second argument is a CHARACTER
--      SET, not a length -- it peels trailing periods off split-parcel IDs.
--      Staging did NOT normalize parcel_id, so this is still required here.
--      Hyphenated IDs (consolidated ranges) are deliberately left alone.
SELECT
    COUNT(*)                                 AS all_rows,
    COUNT(DISTINCT RTRIM(parcel_id, '.'))    AS distinct_parcels
FROM stg.property_sales
WHERE sale_type_code = '13'
  AND sale_date >= DATE '2017-01-01';


-- 1.2  ARMS-LENGTH (03), the SAME measurement, scoped identically.
--
--      RESULT:  all_rows = 72,493 | distinct_parcels = 53,252
--
--      1.36 rows per parcel -- still HIGHER than government's 1.17, so file 06's
--      interpretive point holds inside the window: the two multiples are not the
--      same phenomenon. Repeat arms-length sales are a house changing hands over
--      time (a functioning market). Repeat government transfers are one property
--      passed between agencies (chain of custody). Only the second is
--      double-counting.
--
--      [EVER-TRANSACTED HEADLINE, NOW SCOPED] 53,252 parcels against the 377,863
--      in raw.parcels = 14.1%. File 06 carried this as "under 18%, unfiltered by
--      date, directional only."
--
--      The scoped version is the DEFENSIBLE one even though the number is
--      smaller. "Ever" could not survive the obvious follow-up -- ever since
--      when? -- because the sales data is left-censored at 2011. It never meant
--      "ever"; it only sounded like it did. The scoped claim is checkable in
--      every word:
--
--          "Since 2017, roughly one in seven Detroit parcels has recorded an
--           arms-length sale."
--
--      REMAINING CAVEAT before this is published: raw.parcels is a CURRENT
--      snapshot (noted 8/9), so historical splits and merges are not captured.
--      The denominator is today's parcel count measured against nine years of
--      sales. Directionally sound, not exact. Cut it by neighborhood before it
--      goes on a slide -- see file 13.
SELECT
    COUNT(*)                                 AS all_rows,
    COUNT(DISTINCT RTRIM(parcel_id, '.'))    AS distinct_parcels
FROM stg.property_sales
WHERE sale_type_code = '03'
  AND sale_date >= DATE '2017-01-01';


-- =============================================================================
-- CROSS-CHECK
-- =============================================================================
-- File 13's composition query, run independently at neighborhood grain, sums to
-- arms_length = 72,493 and government = 70,275 citywide -- matching 1.1 and 1.2
-- exactly. Two different queries, two different groupings, same totals.
-- =============================================================================


-- =============================================================================
-- OPEN QUESTIONS -- NEXT
-- =============================================================================
-- 1. The 1.13x is a CITYWIDE AVERAGE and file 13 shows it is masking
--    neighborhoods running roughly 10:1 in opposite directions. The citywide
--    figure should probably not be the headline at all -- the divergence is.
--
-- 2. SHAPE of the duplication, still not done. 1.17 could be near-universal
--    double-counting or a light majority with a heavy 5-7 hop tail. Per-parcel
--    COUNT(*) wrapped in an outer frequency count. Matters for the Land Bank
--    split: if many DLBA rows are mid-chain legs rather than terminal
--    dispositions, the grantee classification has to account for it.
--
-- 3. SPLIT THE LAND BANK (57,993 rows unscoped) by GRANTEE -- outcome, not
--    channel. DLBA -> individual = side lot / giveaway (DISTRESS);
--    DLBA -> LLC / INC / nonprofit = redevelopment (GROWTH). Carried since 8/15.
--
-- 4. DECIDE: fold Mortgage Foreclosure (193) into Tax Foreclosure, or keep
--    separate? Outstanding since 8/15. Just make the call.
-- =============================================================================
