-- =============================================================================
-- 02_profile_sale_types.sql
-- Detroit Property Pipeline
--
-- PURPOSE
--   Determine which recorded property transfers represent genuine market value
--   and can therefore be used in neighborhood-level price analysis.
--
--   Not every deed filed is a "sale." Quit-claims between family, land bank
--   transfers, foreclosures, and estate settlements all appear in
--   raw.property_sales with a price attached, but that price is not evidence
--   of what the property is worth. Aggregating without excluding them produces
--   meaningless neighborhood figures.
--
-- HEADLINE RESULT
--   Filter column:  term_of_sale (NOT sale_verification -- see Section 1)
--   Filter key:     LEFT(term_of_sale, 2) -- the numeric code, not the label
--   Clean subset:   03-ARM'S LENGTH = 96,752 rows (18.8% of 514,384)
--
-- Run date: 2026-08-10
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- RULING OUT sale_verification
-- =============================================================================

-- 1.1  The obvious first candidate for a filter column, checked and rejected.
--      RESULT: PROPERTY TRANSFER AFFIDAVIT 305,012 | OTHER 133,976 |
--              DEED 64,905 | TITLE COMPANY 7,008 | (blank) 3,406 | ...
--
--      FINDING: this column records the SOURCE DOCUMENT the assessor used to
--      verify the transfer occurred -- not whether the price means anything.
--      A $1 quit-claim between siblings still has a property transfer
--      affidavit behind it. Wrong instrument for this job. Documented here
--      rather than silently skipped, so the reasoning is visible.
SELECT sale_verification, COUNT(*)
FROM raw.property_sales
GROUP BY 1
ORDER BY 2 DESC;


-- =============================================================================
-- SECTION 2 -- PROFILING term_of_sale
-- =============================================================================

-- 2.1  Breakdown of how properties actually changed hands. This is the
--      Michigan assessor's terms-of-sale code set, which classifies WHY each
--      transfer happened -- exactly the judgment this analysis needs.
--
--      RESULT (top buckets):
--        21-NOT USED/OTHER              205,909
--        13-GOVERNMENT                  104,443
--        03-ARM'S LENGTH                 96,752
--        20-MULTI PARCEL SALE REF        37,991
--        10-FORECLOSURE                  19,430
--        19-MULTI PARCEL ARM'S LENGTH    12,091
--
--      FINDING: a large majority of recorded transfers do not qualify as
--      traditional market sales. Only 03-ARM'S LENGTH is unimpeachable
--      evidence of value.
--
--      IMPORTANT -- 19 and 20 ARE EXCLUDED despite "ARM'S LENGTH" in the
--      label. On a multi-parcel sale one dollar figure covers several
--      parcels. Joined to a single parcel_id, the full aggregate price is
--      attributed to one property, fabricating a high-end outlier. This
--      contaminates in the opposite direction from the $1 sales and clusters
--      in the same distressed areas where land assembly happens.
--
--      FINDING -- LABEL DRIFT. The text descriptions are not stable:
--        "09-FAMILY"                           vs "09-FAMILY/RELATED ENTITY"
--        "11-FROM LENDING INSTITUTION EXPOSED" vs "11-FROM LANDING ..." (typo)
--        "20-MULTI PARCEL SALE REF"            vs "20-MULTIPARCEL SALE REF"
--      Same numeric code, different string. Filtering on the full label would
--      silently miss variants. Filter on LEFT(term_of_sale, 2) instead -- the
--      number is the stable key. (Same lesson as the parcel_id trailing
--      period in 01_profile_parcel_ids.sql: identify the stable key before
--      filtering or joining on it.)
SELECT term_of_sale, COUNT(*)
FROM raw.property_sales
GROUP BY 1
ORDER BY 2 DESC;


-- 2.2  Do the codes behave the way their labels claim? Price behavior by code.
--
--      "dollar_sales" counts transfers at <= $1. These are nominal-
--      consideration transfers -- not data errors, but a legal convention.
--      Contracts historically required consideration to be valid, so $1 (or
--      $0) is recorded where no money actually changed hands. They are real
--      records of real events; they are simply not evidence of value.
--
--      RESULT (selected):
--        03-ARM'S LENGTH   n=96,752   median $45,162   nominal:    319
--        18-LIFE ESTATE    n= 2,738   median $0        nominal:  2,667
--        09-FAMILY         n=10,252   median $0        nominal:  9,256
--        21-NOT USED/OTHER n=205,909  median $1        nominal: 114,730
--
--      FINDING: the codes are trustworthy. Life estate and family transfers
--      are ~97% and ~90% nominal, exactly as their labels imply, while
--      arms-length is 0.3% nominal with a plausible median. The field is
--      doing its job, which validates using it as the gate.
--
--      NOTE: min_price = 0 across every code is expected -- $0 and $1 are both
--      used for nominal consideration. The <= 1 threshold captures both.
--
--      NOTE: a $700,000,000 max appears under three separate codes -- almost
--      certainly one bundled portfolio transaction repeated across rows.
--      Flagged, not yet investigated.
SELECT
    term_of_sale,
    COUNT(*)                            AS n,
    MIN(amt_sale_price::numeric)        AS min_price,
    ROUND(AVG(amt_sale_price::numeric)) AS avg_price,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amt_sale_price::numeric)
                                        AS median_price,
    MAX(amt_sale_price::numeric)        AS max_price,
    SUM(CASE WHEN amt_sale_price::numeric <= 1 THEN 1 ELSE 0 END) AS dollar_sales
FROM raw.property_sales
GROUP BY 1
ORDER BY 2 DESC
LIMIT 15;


-- 2.3  Is the largest bucket (21) recoverable? Price distribution within it.
--
--      The question: 21-NOT USED/OTHER is 205,909 rows -- 40% of the dataset.
--      Excluding it is a large loss. Are there genuine sales buried in there
--      that were simply never classified?
--
--      RESULT:
--        a. nominal (<=1)  114,730   56%
--        b. under 1k        19,480   21% of the non-nominal remainder
--        c. 1k-10k          27,335   30%   <- peak
--        d. 10k-50k         24,310   27%
--        e. 50k-200k        14,963   16%
--        f. 200k+            5,091    6%
--
--      FINDING: not recoverable as arms-length sales. Setting the nominal
--      spike aside, the distribution peaks at $1k-$10k and declines from
--      there -- an order of magnitude BELOW the $45,162 arms-length median.
--      Roughly three quarters of the bucket is nominal or sub-$1,000.
--
--      INTERPRETATION: this is not a pile of mislabeled market sales. It is a
--      distressed low-value market -- auction-adjacent, land transfer, cash
--      scrape. Including it would not "recover lost data"; it would REDEFINE
--      the research question from "what is a home worth here" to "how does
--      property move here at all." Both are legitimate. See the two-tier
--      design below.
SELECT
    CASE
        WHEN amt_sale_price::numeric <= 1     THEN 'a. nominal (<=1)'
        WHEN amt_sale_price::numeric < 1000   THEN 'b. under 1k'
        WHEN amt_sale_price::numeric < 10000  THEN 'c. 1k-10k'
        WHEN amt_sale_price::numeric < 50000  THEN 'd. 10k-50k'
        WHEN amt_sale_price::numeric < 200000 THEN 'e. 50k-200k'
        ELSE 'f. 200k+'
    END AS price_band,
    COUNT(*) AS n
FROM raw.property_sales
WHERE term_of_sale = '21-NOT USED/OTHER'
GROUP BY 1
ORDER BY 1;


-- =============================================================================
-- DESIGN DECISION -- TWO-TIER ANALYSIS
-- =============================================================================
-- Filtering to 03-ARM'S LENGTH alone discards 81% of the dataset. That is
-- defensible, but it carries a hidden risk: the excluded transfers are almost
-- certainly NOT uniformly distributed. Land bank activity, tax foreclosure,
-- and $1 transfers concentrate in high-vacancy neighborhoods. A strong
-- neighborhood might retain 40% of its records after filtering while a
-- distressed one retains 6% -- and the few survivors there are the atypical
-- ones. The strict filter would therefore bias distressed neighborhoods
-- UPWARD, the opposite direction from the unfiltered bias.
--
-- Rather than choose, run both and compare:
--   STRICT TIER  -- code 03 only. "What is a home worth here?"
--   WIDE TIER    -- add 11-EXPOSED and price-floored 21. "How does property
--                   move here at all?"
--
-- Where the two tiers AGREE, the local market functions. Where they DIVERGE
-- sharply, the market has collapsed into distressed turnover. That divergence
-- is the finding, and it is invisible to a standard arms-length-only analysis.
--
-- DELIVERABLE: neighborhood health index driven by tier divergence, retention
-- rate, and arms-length sample size. Static choropleth comparison first;
-- interactive version deferred to the Flask phase.
-- =============================================================================


-- =============================================================================
-- OPEN QUESTIONS -- NEXT SESSION
-- =============================================================================
-- 1. Retention rate by neighborhood. Is the 81% exclusion uniform? This must
--    be answered before the strict tier can be trusted. THE priority.
-- 2. sale_date is stored as text and needs casting before temporal analysis.
-- 3. Define the wide tier precisely -- which codes, what price floor on 21.
-- 4. Investigate the $700M transaction appearing across three codes.
-- =============================================================================
