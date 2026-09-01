-- =============================================================================
-- 13_profile_neighborhood_composition.sql
-- Detroit Property Pipeline
--
-- TODO(caden): rewrite this header in my own words before this goes in the
-- portfolio. Drafted by Claude on 8/31 under time pressure; headers are mine
-- from file 10 onward. This one especially -- it is the closest thing to a
-- findings document in the repo so far.
--
-- PURPOSE
--   Break every property transfer since 2017 into code families, one row per
--   neighborhood. This is THE query that has been deferred three times (8/13,
--   8/20, 8/28) and it is the first direct input to the Neighborhood Health
--   Index.
--
--   WHY IT MATTERS -- established 8/13: retention rate alone does NOT measure
--   market health. Two neighborhoods with identical low arms-length retention
--   can be telling opposite stories. Development-driven low retention shows up
--   as 13-government plus 19/20 multi-parcel land assembly. Distress-driven low
--   retention shows up as the 10/11/17/30 foreclosure family plus 21 quit-claims.
--   Retention tells you HOW THIN the arms-length market is. COMPOSITION tells
--   you WHY. The Index needs both.
--
--   WHY COUNTS AND NOT PERCENTAGES (yet). Percentages alone let a neighborhood
--   with 40 total transfers and 82% arms-length outrank one with 4,000 transfers
--   and the same share. Raw counts alone let big neighborhoods dominate every
--   column purely by being big. Keeping total_transfers in the same row makes
--   the difference visible immediately and sets up a minimum-n threshold before
--   any ranking happens. Percentages are the NEXT pass, not this one.
--
-- Run date: 2026-08-31
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- COMPOSITION BY NEIGHBORHOOD, 2017+
-- =============================================================================
--
-- FAMILY DEFINITIONS -- from docs/terms_of_sale_legend.md (MI STC CAMA Data
-- Standards, Aug 2025). The assessor's "Recommended L-4015 Type" column is the
-- boundary; these buckets were not invented here.
--     arms_length   03          Conventional. Genuine market evidence.
--     government    13          The two-faced channel -- Land Bank giveaway
--                               (distress) AND city/DEGC assembly (development).
--                               Composition context decides which.
--     foreclosure   10 11 17 30 34   The distress family.
--     multi_parcel  19 20       Join-breakers. One price, several parcels.
--     other         everything else, dominated by 21-NOT USED/OTHER.
--
-- THE BUG THAT ALMOST SHIPPED -- worth the space, this is a portfolio anecdote
--
--   First draft wrote the residual branch as:
--       COUNT(*) FILTER (WHERE sale_type_code NOT IN ('03','13',...))
--
--   In SQL, NOT IN against a NULL does not return FALSE -- it returns NULL. And
--   FILTER treats NULL as "does not match." So every row with a NULL
--   sale_type_code fell through EVERY branch and landed in no bucket at all.
--   These rows are known to exist: the 15 blank term_of_sale values that staging
--   converted to NULL, which makes the derived sale_type_code NULL too
--   (file 11 S1.1, null_terms = 15).
--
--   The fix adds the NULL case explicitly:
--       WHERE sale_type_code IS NULL OR sale_type_code NOT IN (...)
--
--   THE DANGEROUS PART -- the fix moved exactly 15 rows across the entire city,
--   out of 307,973. Nothing about the broken output looked wrong. It was caught
--   only by adding the branches back up and comparing to total_transfers.
--   Same shape as the LIKE 'HUD %' gotcha from 8/15: a bucket coming out SMALLER
--   than it should is nearly invisible, where a bucket coming out too big
--   announces itself.
--
--   And the 15 recovered rows match the 15 blank term_of_sale rows EXACTLY --
--   a clean reconciliation back to file 05 and file 11 S1.1.
--
--   RULE GOING FORWARD: any query that splits a total into branches gets a sum
--   check written at the same time as the query, not after the results look
--   interesting. Section 2 is that check.
--
-- CITYWIDE TOTALS (2026-08-31, 204 neighborhoods)
--     total_transfers   307,973
--     arms_length        72,493   23.5%
--     government         70,275   22.8%
--     foreclosure         6,324    2.1%
--     multi_parcel       19,853    6.4%
--     other             139,028   45.1%
--
--   [CROSS-CHECK PASSES] arms_length and government sum to exactly the row
--   counts in file 12 S1.1 and S1.2, computed independently at a different
--   grain. Two queries, same answer.
--
--   [COVERAGE CAVEAT, QUANTIFIED] The blank-neighborhood row is 14,600 transfers
--   = 4.74% of the total, in line with the ~5% estimated on 8/13. Surfaced as
--   its own row, NOT suppressed. Note its multi_parcel count (5,007) is a
--   quarter of the citywide multi-parcel total -- large industrial and assembly
--   transactions appear to be disproportionately unlabeled. Worth a look before
--   the Index is built, because dropping this row would silently drop a quarter
--   of the assembly signal.
--
-- FINDINGS
--
--   [1 -- THE DIVERGENCE IS SEVERE, AND IT IS THE REAL HEADLINE]
--   File 12's citywide 1.13x government-to-arms-length parcel ratio is an
--   average concealing neighborhoods running roughly 10:1 in OPPOSITE
--   directions. Arms-length dominant:
--       Rosedale Park            493 arms / 25 gov    ~19.7 : 1
--       Bagley                 1,957 arms / 199 gov    ~9.8 : 1
--       East English Village     774 arms / 80 gov     ~9.7 : 1
--       Warrendale             3,236 arms / 1,607 gov  ~2.0 : 1
--   Government dominant:
--       Delray                    87 arms / 807 gov    ~9.3 : 1
--       McDougall-Hunt           112 arms / 947 gov    ~8.5 : 1
--       Airport Sub              309 arms / 1,928 gov  ~6.2 : 1
--       Poletown East             67 arms / 833 gov   ~12.4 : 1
--       Midwest                  907 arms / 3,308 gov  ~3.6 : 1
--   The citywide figure should probably NOT be the headline. The spread is.
--
--   [2 -- THE 8/10 MIDTOWN ASSUMPTION NEEDS REVISITING]
--   The working model on 8/10 was "small gap = healthy functioning market
--   (Midtown); huge gap = collapsed into distressed turnover (Core City)."
--   Direction holds -- Midtown 17.3% arms-length vs Core City 7.5% -- but
--   Midtown is far weaker than assumed and only 998 transfers total. Its
--   multi_parcel share is 313 of 998 (31.4%), the highest of any large
--   neighborhood, which reads as DEVELOPMENT ASSEMBLY rather than a healthy
--   resale market. Same for Rivertown (273 of 644) and Brush Park (206 of 680).
--   That is a distinct third pattern the two-way distress/development framing
--   does not capture: a neighborhood where the dominant activity is neither
--   households buying homes nor the city absorbing abandonment, but developers
--   assembling land. Worth naming before the Index is scored.
--
--   [3 -- 'OTHER' IS THE LARGEST BUCKET IN ALMOST EVERY ROW, AND IT IS OPAQUE]
--   139,028 rows, 45.1% citywide, and it is the top bucket in most
--   neighborhoods (Warrendale 4,687 of 10,104 -- larger than every other bucket
--   combined). It is overwhelmingly code 21-NOT USED/OTHER: quit-claims, $1
--   transfers, deed restrictions, partial interests. File 05 established that
--   ~56% of code 21 is nominal and another ~21% under $1k -- a distressed
--   low-value market, not mislabeled arms-length sales.
--   BUT: until it is known whether 21 behaves the SAME WAY in every
--   neighborhood, this is a large unexplained mass inside every row of the
--   table, and any Index scored on the other four buckets is scored on 55% of
--   the data while ignoring the largest slice. THIS IS THE NEXT PRIORITY.
--
--   [4 -- FORECLOSURE FAMILY IS SMALL INSIDE THE WINDOW]
--   Only 6,324 rows, 2.1% citywide. Expected -- the foreclosure wave peaked
--   2013-2016 and file 12 confirmed the pre-2017 cut removes it. Consequence
--   for the wide tier: the IAAO 20% rule (foreclosure-related sales become
--   valid ratio inputs when they exceed 20% of a market area) is almost
--   certainly NOT triggered anywhere in the 2017+ window. The citable spine for
--   the wide tier documented on 8/13 may not apply to the locked window at all.
--   CHECK THIS PER NEIGHBORHOOD BEFORE BUILDING THE WIDE TIER -- if the rule
--   never fires, the two-tier design needs rethinking or the window does.
-- =============================================================================
SELECT
    neighborhood,
    COUNT(*)                                                       AS total_transfers,
    COUNT(*) FILTER (WHERE sale_type_code = '03')                  AS arms_length,
    COUNT(*) FILTER (WHERE sale_type_code = '13')                  AS government,
    COUNT(*) FILTER (WHERE sale_type_code IN
                          ('10','11','17','30','34'))              AS foreclosure,
    COUNT(*) FILTER (WHERE sale_type_code IN ('19','20'))          AS multi_parcel,
    -- NULL branch is load-bearing, not defensive padding. See header.
    COUNT(*) FILTER (WHERE sale_type_code IS NULL
                        OR sale_type_code NOT IN
                          ('03','13','10','11','17','30','34','19','20'))
                                                                   AS other
FROM stg.property_sales
WHERE sale_date >= DATE '2017-01-01'
GROUP BY neighborhood
ORDER BY total_transfers DESC;


-- =============================================================================
-- SECTION 2 -- SUM CHECK (this is the query that caught the NULL bug)
-- =============================================================================
--
--      Every branch is mutually exclusive and the five together must be
--      exhaustive, so they have to add back to total_transfers on EVERY row.
--      Any neighborhood where they do not means rows are escaping the CASE
--      coverage entirely.
--
--      EXPECT: 0
--      RESULT (2026-08-31): 0  [PASS] -- 204 neighborhoods, zero failures.
--
--      Before the NULL fix this returned 13 failing neighborhoods (15 rows).
--      Keep this query. It is cheap, it is re-runnable by a reviewer, and it is
--      the only thing that would catch a new code family being added upstream
--      and quietly falling into no bucket.
-- =============================================================================
WITH composition AS (
    SELECT
        neighborhood,
        COUNT(*)                                                   AS total_transfers,
        COUNT(*) FILTER (WHERE sale_type_code = '03')              AS arms_length,
        COUNT(*) FILTER (WHERE sale_type_code = '13')              AS government,
        COUNT(*) FILTER (WHERE sale_type_code IN
                              ('10','11','17','30','34'))          AS foreclosure,
        COUNT(*) FILTER (WHERE sale_type_code IN ('19','20'))      AS multi_parcel,
        COUNT(*) FILTER (WHERE sale_type_code IS NULL
                            OR sale_type_code NOT IN
                              ('03','13','10','11','17','30','34','19','20'))
                                                                   AS other
    FROM stg.property_sales
    WHERE sale_date >= DATE '2017-01-01'
    GROUP BY neighborhood
)
SELECT COUNT(*) AS neighborhoods_failing_sum
FROM composition
WHERE arms_length + government + foreclosure + multi_parcel + other
      <> total_transfers;


-- =============================================================================
-- OPEN QUESTIONS -- NEXT
-- =============================================================================
-- 1. DECOMPOSE 'OTHER'. 45% of the data in an undifferentiated bucket. Split
--    code 21 out from the rest, then profile 21 by neighborhood the same way.
--    Finding 3 above cannot be resolved without it and the Index is not
--    trustworthy until it is.
--
-- 2. PERCENTAGES + MINIMUM-N THRESHOLD. Shares of total_transfers per
--    neighborhood, with a floor on total_transfers before anything is ranked.
--    Decide the floor deliberately -- there are 204 neighborhoods and the
--    smallest (Waterworks Park) has 1 transfer.
--
-- 3. CHECK THE IAAO 20% RULE PER NEIGHBORHOOD. Finding 4 -- if foreclosure
--    never reaches 20% of a market area inside the window, the wide tier loses
--    its citable basis.
--
-- 4. THE BLANK-NEIGHBORHOOD ROW holds 25% of citywide multi-parcel volume.
--    Understand what those 14,600 transfers are before deciding how to handle
--    them in the Index.
--
-- 5. JOIN TO raw.parcels for the denominator -- arms-length parcels as a share
--    of parcels that EXIST in each neighborhood, not as a share of transfers.
--    That is the true retention rate and it is what file 03 started.
-- =============================================================================
