-- =============================================================================
-- 06_profile_parcel_id_duplicates.sql
-- Detroit Property Pipeline
--
-- PURPOSE
--   Test whether the "government transfers outnumber arms-length sales"
--   finding from file 05 survives deduplication to the PARCEL grain.
--
--   WHY THIS QUERY EXISTS. File 05 compared 104,443 government rows to 96,752
--   arms-length rows. The Richton chain-of-custody caveat showed a single
--   parcel generating three government "sales" as it moved Treasurer -> state
--   land bank -> city land bank -> nonprofit. If that pattern is widespread,
--   the comparison counts LEGS OF A JOURNEY on one side and PROPERTIES on the
--   other, and the headline collapses. Both sides must be measured the same
--   way before the claim can be published.
--
-- HEADLINE RESULTS
--   Government (13):   104,443 rows / 86,624 parcels = 1.21 rows per parcel
--   Arms-length (03):   96,752 rows / 66,461 parcels = 1.46 rows per parcel
--
--   [FINDING -- the claim SURVIVES and STRENGTHENS] Arms-length is the MORE
--   duplicated side. Deduplicating both sides widened the ratio from 1.08x
--   (raw rows) to 1.30x (distinct parcels). More Detroit properties have moved
--   through a government channel than have ever sold on the open market --
--   true whether you count transactions or properties.
--
--   [INTERPRETATION -- the two multiples are NOT the same phenomenon]
--   Repeat arms-length sales = a house changing hands over time = a
--   FUNCTIONING market doing exactly what it should.
--   Repeat government transfers = ONE property passed between agencies =
--   chain of custody.
--   Only the second is double-counting. The file 05 caveat assumed repetition
--   was a defect; it is only a defect on the government side.
--
--   [SCOPE CAVEAT] Both queries are UNFILTERED BY DATE. The locked analysis
--   window is 2017 -> present. Treat these figures as directional until the
--   window is applied (sale_date is still text -- cast outstanding).
--
-- Run date: 2026-08-20
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- DOES DUPLICATION EXIST, AND HOW BAD IS THE TAIL?
-- =============================================================================

-- 1.1  Confirm that duplicate parcel_ids exist within the government bucket,
--      and inspect the worst offenders.
--
--      NOTE ON RTRIM: the second argument is a CHARACTER SET, not a length --
--      RTRIM(parcel_id, '.') peels periods off the right edge. Rows without a
--      trailing period pass through untouched, so no CASE is needed. Passing an
--      integer (RTRIM(parcel_id, 1)) fails: there is no rtrim(varchar, integer).
--      Same normalization resolved on 8/9 for the parcels join.
--
--      RESULT (top rows):
--        (null)        15
--        22085947       7
--        22008634-5     7
--        21012219       7
--        21038641       7
--        17006301       7
--        21023369       7
--        01005578       6
--
--      [FINDING] Duplication is real and the tail runs to 7 hops on a single
--      parcel. This is the Richton pattern generalized -- a property cycling
--      through Treasurer -> land bank -> land bank -> disposition, with each
--      leg landing in a DIFFERENT channel under the file 05 CASE. The channel
--      counts in 05 are therefore counting legs, not properties.
--
--      [DATA QUALITY] 15 rows carry a NULL parcel_id. These are visible in
--      COUNT(*) but INVISIBLE to COUNT(DISTINCT), which ignores nulls. That
--      means Section 2 slightly understates the true row-to-parcel ratio.
--      Negligible at this volume -- handle explicitly in staging alongside the
--      15 blank term_of_sale rows and the 25 grantor = '0' rows from file 05.
--
--      [NOT A DEFECT] '22008634-5' is a HYPHENATED CONSOLIDATED PARCEL RANGE,
--      documented 8/9. Hyphenated = consolidated range; dotted = genuine split
--      parcel. Both are meaningful. Do NOT strip the hyphen the way the period
--      is stripped.
SELECT
    RTRIM(ps.parcel_id, '.') AS parcel_id_trimmed,
    COUNT(*)                 AS n
FROM raw.property_sales ps
WHERE LEFT(term_of_sale, 2) = '13'
GROUP BY 1
ORDER BY n DESC
LIMIT 30;


-- =============================================================================
-- SECTION 2 -- ROW GRAIN VS PARCEL GRAIN, BOTH SIDES
-- =============================================================================

-- 2.1  GOVERNMENT (13): how many distinct properties do the 104,443 rows
--      actually describe?
--
--      RESULT:  all_rows = 104,443 | distinct_parcels = 86,624
--
--      17,819 excess rows -- ~17% inflation, 1.21 rows per parcel. Chain of
--      custody is a systematic feature of how property moves through Detroit's
--      government channels, not an oddity of one block on Richton.
SELECT
    COUNT(*)                                   AS all_rows,
    COUNT(DISTINCT RTRIM(ps.parcel_id, '.'))   AS distinct_parcels
FROM raw.property_sales ps
WHERE LEFT(term_of_sale, 2) = '13';


-- 2.2  ARMS-LENGTH (03): the SAME measurement on the other side.
--
--      *** THIS QUERY IS THE POINT OF THE FILE ***
--      The tempting shortcut after 2.1 is to compare 86,624 deduplicated
--      government parcels against 96,752 raw arms-length rows and conclude the
--      thesis reverses. That repeats the original error in the opposite
--      direction -- deduplicated on one side, raw on the other. A house that
--      sold in 2015 and again in 2021 is two legitimate arms-length events on
--      one parcel, so this side shrinks too. Neither number means anything
--      until both are measured the same way.
--
--      RESULT:  all_rows = 96,752 | distinct_parcels = 66,461
--
--      1.46 rows per parcel -- HIGHER than government's 1.21.
--
--      [OPEN QUESTION -- worth its own file] 66,461 parcels have EVER had an
--      arms-length sale, against 377,863 parcels in raw.parcels. Under 18% of
--      Detroit property has ever transacted on the open market in this window.
--      That is a Neighborhood Health Index headline sitting in plain sight --
--      scope it to 2017+ and cut it by neighborhood before claiming it.
SELECT
    COUNT(*)                                   AS all_rows,
    COUNT(DISTINCT RTRIM(ps.parcel_id, '.'))   AS distinct_parcels
FROM raw.property_sales ps
WHERE LEFT(term_of_sale, 2) = '03';


-- =============================================================================
-- CONSEQUENCE FOR FILE 05
-- =============================================================================
-- The Richton caveat is now QUANTIFIED and CLOSED. File 05's open question 2 is
-- answered: duplication exists, it is ~17% on the government side, and it does
-- NOT overturn the headline because arms-length carries more of it.
--
-- The claim should be worded at the PARCEL grain from here on:
--   "More Detroit properties have moved through a government channel (86,624)
--    than have ever sold on the open market (66,461) -- a 1.30x gap that holds
--    whether measured in transactions or in properties."
-- =============================================================================


-- =============================================================================
-- OPEN QUESTIONS -- NEXT SESSION
-- =============================================================================
-- 1. SHAPE OF THE DUPLICATION, not just its volume. 1.21 could be nearly every
--    parcel appearing twice, or most appearing once with a few thousand
--    cycling through 5-7 agency hops. Section 1.1 shows the tail reaches 7,
--    but not how heavy it is. Wrap a per-parcel COUNT(*) in an outer frequency
--    count (how many parcels appear exactly once, twice, three times...).
--    This MATTERS for the Land Bank split: if a large share of DLBA rows are
--    mid-chain legs rather than terminal dispositions, the grantee
--    classification has to account for it.
--
-- 2. SPLIT THE LAND BANK (57,993 rows) -- carried over from file 05. Grantor
--    gives the channel; GRANTEE gives the outcome. DLBA -> individual = side
--    lot / giveaway (DISTRESS); DLBA -> LLC / INC / nonprofit developer =
--    redevelopment (GROWTH). The corporate-suffix pattern from 05 Section 3
--    transfers directly. Watch for the same two traps: branch order is
--    load-bearing, and a bucket coming out SMALLER than expected is nearly
--    invisible (the LIKE 'HUD %' gotcha). Validate that channels sum to 57,993.
--
-- 3. DECIDE: fold Mortgage Foreclosure (193 rows) into Tax Foreclosure, or keep
--    separate? Still outstanding from file 05.
--
-- 4. Cast sale_date text -> date, then re-run Section 2 scoped to 2017+ to
--    confirm the ratio holds inside the locked analysis window.
--
-- 5. THEN the composition query (per neighborhood, one branch per code family),
--    which has been deferred twice now.
-- =============================================================================
