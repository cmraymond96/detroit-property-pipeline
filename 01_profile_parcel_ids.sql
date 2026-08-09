-- =============================================================================
-- 01_profile_parcel_ids.sql
-- Detroit Property Pipeline — Step 3 prerequisite
--
-- PURPOSE
--   Profile the parcel_id column on both raw.parcels and raw.property_sales
--   to determine whether the two tables can be joined, what normalization the
--   join requires, and how many records are lost in the process.
--
--   Nothing downstream is trustworthy until this is answered. A malformed join
--   on parcel_id does not raise an error — it silently associates sales with
--   the wrong parcels, or drops records without warning.
--
-- HEADLINE RESULT
--   Join key:    RTRIM(parcel_id, '.') on both sides
--   Match rate:  94.22% (484,628 of 514,384 sales)
--   Fan-out:     none — parcels is unique on the normalized key
--
-- Run date: 2026-08-09
-- =============================================================================


-- =============================================================================
-- SECTION 1 — PROFILE raw.parcels
-- =============================================================================

-- 1.1  Eyeball the raw structure. Twenty rows is enough to generate hypotheses
--      about formatting; it is NOT enough to confirm them. Confirmation is
--      Section 1.3 onward.
SELECT *
FROM raw.parcels
LIMIT 20;


-- 1.2  Confirm data types.
--      parcel_id is text — correct. Parcel IDs must never be cast to a numeric
--      type: leading zeros are significant (e.g. '02000184') and would be
--      silently destroyed. The join also requires text-to-text on both sides;
--      a text/numeric mismatch is a common cause of total join failure.
--      Also noted here: geometry is USER-DEFINED (PostGIS type), as expected.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw'
  AND table_name   = 'parcels';


-- 1.3  Quantify the format variance observed in 1.1.
--      NOTE ON CASE: branches are evaluated top-to-bottom and stop at the first
--      match, so buckets are mutually exclusive by construction, not by nature.
--      A row matching two conditions is only counted once, in the earlier
--      branch. See 1.6 for the overlap check this necessitates.
--
--      NOTE ON PATTERNS: '%.' means ENDS WITH a period. This is deliberate and
--      not interchangeable with '%.%' (CONTAINS a period). Using the latter
--      would have swept the ~25k split parcels (e.g. '16014281.001') into the
--      'trailing period' bucket and hidden them entirely.
--
--      RESULT:  trailing period  319,092
--               contains hyphen   33,925
--               other             24,846   <- investigated in 1.5
SELECT
    CASE
        WHEN parcel_id LIKE '%.'  THEN 'trailing period'
        WHEN parcel_id LIKE '%-%' THEN 'contains hyphen'
        WHEN parcel_id LIKE '%.%' THEN 'dotted suffix'
        ELSE 'other'
    END AS pattern,
    COUNT(*)
FROM raw.parcels
GROUP BY 1
ORDER BY 2 DESC;


-- 1.4  Length distribution — cross-check on 1.3.
--      RESULT:  len 9 = 319,091, which reconciles to within one row against the
--      319,092 trailing-period count. This confirms the dominant format is an
--      8-digit ID plus a trailing period. Lengths 10-13 sum to 58,771, exactly
--      matching hyphen + other from 1.3. Every row is accounted for across
--      three formats with no unexplained residue — profiling is complete, not
--      merely started.
SELECT LENGTH(parcel_id) AS len, COUNT(*)
FROM raw.parcels
GROUP BY 1
ORDER BY 1;


-- 1.5  Inspect the hyphenated records.
--      FINDING: these are CONSOLIDATED PARCEL RANGES, not condo units.
--      The suffix is the end of a range with the shared prefix dropped:
--        '16001201-5'    = parcels 16001201 through 16001205
--        '18010299-300'  = parcels 18010299 through 18010300
--        '18007054-62'   = nine adjacent lots assembled into one record
--      Several adjacent lots merged under one record, typically for industrial
--      or commercial land assembly — consistent with the property classes seen.
--      The suffix carries meaning and MUST NOT be stripped.
SELECT parcel_id, address, property_class_description
FROM raw.parcels
WHERE parcel_id LIKE '%-%'
ORDER BY parcel_id
LIMIT 20;


-- 1.6  Inspect the 'other' records.
--      FINDING: these are SPLIT PARCELS — genuinely distinct properties sharing
--      a base parcel number, distinguished by a dotted suffix:
--        '16014281.001'  = 2408 CAMPBELL  (residential-vacant)
--        '16014281.002L' = 2410 CAMPBELL  (residential-vacant)
--        '02001528.001'  = 140 GLYNN CT   (commercial-vacant)
--        '02001528.002L' = 130 GLYNN CT   (residential-improved)
--      Different addresses, and in some cases different property classes.
--      Stripping the suffix would merge unrelated properties into one record
--      and produce fan-out on the join. The suffix carries meaning and MUST
--      NOT be stripped.
SELECT parcel_id, address, property_class_description
FROM raw.parcels
WHERE parcel_id NOT LIKE '%.'
  AND parcel_id NOT LIKE '%-%'
LIMIT 20;


-- 1.7  Overlap check for the CASE-ordering caveat noted in 1.3.
--      Counts rows carrying BOTH a hyphen and a trailing period, which would
--      have been absorbed into the 'trailing period' bucket and undercounted
--      the hyphen category.
--      RESULT: 2. Negligible — the 1.3 counts stand.
SELECT COUNT(*)
FROM raw.parcels
WHERE parcel_id LIKE '%-%'
  AND parcel_id LIKE '%.';


-- 1.8  Uniqueness check on the normalized key. CRITICAL PRE-JOIN GATE.
--      If the parcels side is not unique on the join key, each sale matches
--      multiple parcel rows and the join fans out — inflating row counts and
--      corrupting any aggregate built on top of it.
--      RESULT: 0. Parcels is unique on RTRIM(parcel_id, '.'). Safe to join.
SELECT COUNT(*) - COUNT(DISTINCT RTRIM(parcel_id, '.')) AS dupe_parcels
FROM raw.parcels;


-- =============================================================================
-- SECTION 2 — PROFILE raw.property_sales
-- =============================================================================

-- 2.1  Confirm data types.
--      parcel_id is text on this side as well — the join is text-to-text.
--      FLAGGED FOR LATER: sale_date is stored as text and will require casting
--      to date before any time-series or temporal filtering.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw'
  AND table_name   = 'property_sales';


-- 2.2  Eyeball parcel_id alongside price and date.
--      FLAGGED FOR LATER — the single most important analytical decision in
--      this study: multiple sales appear at $1. These are quit-claim deeds,
--      family transfers, and foreclosure conveyances, not market transactions.
--      Averaging sale price without excluding them produces meaningless
--      neighborhood figures. The assessor provides sale_verification and
--      term_of_sale specifically to identify arms-length sales — that filter
--      is the next analytical step.
--
--      Also observed: parcel IDs repeat across rows (e.g. '27090609.',
--      '27070842.'). One parcel, many sales over time. The sales-to-parcels
--      relationship is many-to-one, which is why 1.8 mattered.
SELECT parcel_id, amt_sale_price, sale_date
FROM raw.property_sales
LIMIT 20;


-- 2.3  Format distribution — the direct comparison against 1.3.
--      RESULT:  trailing period  433,325  (84.2%)   vs parcels 84.4%
--               contains hyphen   41,539   (8.1%)   vs parcels  9.0%
--               dotted suffix     38,198   (7.4%)   vs parcels  6.6%
--               other              1,322   (0.3%)
--               total            514,384  — reconciles to the ingested row count
--
--      CONCLUSION: both tables use the same three formats in nearly identical
--      proportions — same source system, same assessor convention. Normalization
--      is therefore a single rule: strip the trailing period. Hyphenated ranges
--      and dotted suffixes are meaningful on BOTH sides and match each other
--      as-is.
SELECT
    CASE
        WHEN parcel_id LIKE '%.'  THEN 'trailing period'
        WHEN parcel_id LIKE '%-%' THEN 'contains hyphen'
        WHEN parcel_id LIKE '%.%' THEN 'dotted suffix'
        ELSE 'other'
    END AS pattern,
    COUNT(*)
FROM raw.property_sales
GROUP BY 1
ORDER BY 2 DESC;


-- =============================================================================
-- SECTION 3 — JOIN VALIDATION
-- =============================================================================

-- 3.1  Measure the match rate.
--      LEFT JOIN is used deliberately. An INNER JOIN here would return 484,628
--      rows and look flawless — the 29,756 failures would silently vanish with
--      no error and no warning, leaving no way to know whether the true match
--      rate was 94% or 60%. An inner join destroys the evidence of its own
--      failure. LEFT JOIN retains every sale row so failures can be counted.
--
--      COUNT(p.parcel_id) ignores NULLs and therefore counts only successful
--      matches; COUNT(*) counts every row. The difference is the failure count.
--
--      PRINCIPLE: join LEFT when validating, INNER when analyzing. Measure what
--      you are discarding before you discard it.
--
--      RESULT:  total 514,384 | matched 484,628 | unmatched 29,756 | 94.22%
--      Within the pre-registered acceptable range (<10% unmatched).
SELECT
    COUNT(*)                                                AS total_sales,
    COUNT(p.parcel_id)                                      AS matched,
    COUNT(*) - COUNT(p.parcel_id)                           AS unmatched,
    ROUND(100.0 * COUNT(p.parcel_id) / COUNT(*), 2)         AS pct_matched
FROM raw.property_sales s
LEFT JOIN raw.parcels p
    ON RTRIM(s.parcel_id, '.') = RTRIM(p.parcel_id, '.');


-- 3.2  Diagnose the failures by format.
--      Raw counts mislead here — converted to failure rates against the 2.3
--      denominators:
--        trailing period  20,403 / 433,325  =  4.7%
--        contains hyphen   1,725 /  41,539  =  4.2%
--        dotted suffix     6,317 /  38,198  = 16.5%   <- ~3.5x baseline
--        other             1,311 /   1,322  = 99.2%   <- near-total failure
--
--      INTERPRETATION: ~4-5% is the baseline historical drift rate — parcels
--      renumbered since the sale was recorded. Dotted suffixes failing at 16.5%
--      is consistent with split parcels churning more than whole ones
--      (hypothesis, not confirmed). The 'other' bucket is a different problem
--      entirely — see 3.3.
SELECT
    CASE
        WHEN s.parcel_id LIKE '%.'  THEN 'trailing period'
        WHEN s.parcel_id LIKE '%-%' THEN 'contains hyphen'
        WHEN s.parcel_id LIKE '%.%' THEN 'dotted suffix'
        ELSE 'other'
    END AS pattern,
    COUNT(*) AS unmatched_count
FROM raw.property_sales s
LEFT JOIN raw.parcels p
    ON RTRIM(s.parcel_id, '.') = RTRIM(p.parcel_id, '.')
WHERE p.parcel_id IS NULL
GROUP BY 1
ORDER BY 2 DESC;


-- 3.3  Inspect the 'other' bucket.
--      FINDING: two structurally distinct groups sharing one bucket.
--
--      GROUP A — space-delimited IDs, blank address:
--        '79 049 01 0119 004', '32 09 263 14 031 00', '46 113 99 0001 006'
--        Not Detroit's numbering scheme. These are other Michigan
--        jurisdictions' parcel formats. Blank address on every row. Out of
--        scope — will never match and should not.
--
--      GROUP B — 8-digit Detroit-format IDs missing the trailing period:
--        '27180090', '16025233', '22018486'
--        These SHOULD match after RTRIM, since '27180090' and '27180090.'
--        normalize identically. Their failure requires explanation. Candidate
--        causes, in order of testability:
--          (a) Trailing/leading whitespace. RTRIM(x, '.') strips ONLY periods —
--              a trailing space survives and silently breaks equality.
--          (b) Condo units. Many carry unit numbers in the address
--              ('8200 E JEFFERSON 110', '63 ADELAIDE ST 39/5'). Condo units
--              often have sale records but no individual parcel polygon.
--          (c) Genuine absence from the current snapshot.
--
--      DATA ENTRY ERRORS observed: '27200122,' (trailing comma),
--      '2718101' (seven digits, not eight).
--
--      Total impact: 1,322 rows = 0.26% of sales. Does not affect any
--      conclusion, but documented rather than assumed.
SELECT parcel_id, address, sale_date
FROM raw.property_sales
WHERE parcel_id NOT LIKE '%.'
  AND parcel_id NOT LIKE '%-%'
  AND parcel_id NOT LIKE '%.%'
LIMIT 100;


-- 3.4  TODO — whitespace test for hypothesis 3.3(a). Run next session.
--      If non-zero, the normalization rule must become
--      TRIM(BOTH '.' FROM TRIM(parcel_id)) on both sides.
SELECT COUNT(*)
FROM raw.property_sales
WHERE parcel_id <> TRIM(parcel_id);


-- =============================================================================
-- KNOWN LIMITATIONS — carry into the writeup
-- =============================================================================
-- 1. raw.parcels is a single current snapshot pulled from the ArcGIS
--    FeatureServer. It contains no history of parcel splits, merges, or
--    renumbering. Sales are therefore joined to PRESENT-DAY parcel geometry,
--    not to the parcel as it existed at the time of sale. This is the primary
--    driver of the ~5% baseline non-match rate. The data required to resolve
--    it does not exist in this source.
--
-- 2. sale_date is stored as text and requires casting before temporal analysis.
--
-- 3. Sale prices include non-arms-length transactions ($1 quit-claim deeds,
--    family transfers, foreclosure conveyances). These MUST be filtered using
--    sale_verification / term_of_sale before any price aggregation.
-- =============================================================================
