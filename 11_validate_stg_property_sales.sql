-- =============================================================================
-- 11_validate_stg_property_sales.sql
-- Detroit Property Pipeline
--
-- PURPOSE
--   Prove that 10_build_stg_property_sales.sql did what it claims. A build that
--   has not been verified is a build being trusted on vibes. Kept SEPARATE from
--   the build script so verification can be re-run without rebuilding, and so
--   the build stays a build.
--
-- Run date: 2026-08-28
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1.1  ROW COUNT AND NULL PROFILE
--
--      RESULT (2026-08-28):
--        total_rows      514,384
--        null_dates            1
--        null_terms           15
--        null_grantors     1,308
--        null_parcels      1,238
--
--      [PASS] total_rows matches raw.property_sales exactly. No rows dropped.
--      [PASS] null_dates = 1. The vintage bound caught the single 2026-12-17
--             transposition and nothing else -- confirms it is not over-reaching.
--      [PASS] null_terms = 15, matching the blank count profiled in file 05.
--
--      [RECONCILED] null_grantors and null_parcels came in far above the
--      expected 25 and 15. Neither is a build defect -- both expectations were
--      drawn from the wrong context:
--        - The 15 NULL parcel_ids in file 06 S1.1 were counted under
--          WHERE LEFT(term_of_sale, 2) = '13'. That was the GOVERNMENT-BUCKET
--          count, not the citywide count.
--        - The 25 grantor rows were those equal to '0' specifically. That figure
--          never included rows already NULL in raw. NULLIF adds 25 to a
--          pre-existing pool.
--      Section 1.2 confirms the arithmetic against raw.
--
--      METHOD LESSON -- a validation check is only as good as the PROVENANCE of
--      the number being checked against. A figure lifted out of its WHERE-clause
--      context reads as a mismatch when nothing is actually wrong.
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                       AS total_rows,
    COUNT(*) FILTER (WHERE sale_date    IS NULL)   AS null_dates,
    COUNT(*) FILTER (WHERE term_of_sale IS NULL)   AS null_terms,
    COUNT(*) FILTER (WHERE grantor      IS NULL)   AS null_grantors,
    COUNT(*) FILTER (WHERE parcel_id    IS NULL)   AS null_parcels
FROM stg.property_sales;


-- -----------------------------------------------------------------------------
-- 1.2  RECONCILE THE TWO UNEXPECTED COUNTS AGAINST RAW
--
--      EXPECT: raw_null_grantor + raw_zero_grantor = 1,308
--              raw_null_parcel                     = 1,238
--
--      RESULT (2026-08-28):
--        raw_null_grantor    171
--        raw_zero_grantor  1,137
--        raw_null_parcel   1,238
--
--      [PASS] 171 + 1,137 = 1,308 exactly. [PASS] 1,238 = 1,238 exactly.
--      Zero unexplained rows. Both staging counts are fully accounted for and
--      the "unexpected" figures in 1.1 were expectation errors, not defects.
--
--      [OPEN QUESTION -- 45x gap worth closing] File 05 recorded 25 rows with
--      grantor = '0'. This returns 1,137. Two candidate explanations:
--        (a) PROVENANCE -- file 05 ran under WHERE LEFT(term_of_sale, 2) = '13'.
--            If 25 was the code-13-only count, 1,137 is simply citywide.
--        (b) WHITESPACE -- file 05 tested grantor = '0' EXACTLY; this tests
--            TRIM(grantor) = '0'. If so, ~1,112 rows carry whitespace-padded
--            placeholders that were invisible to every pre-staging query.
--      Section 1.5 disambiguates. Answer matters: (b) would mean the blanket
--      TRIM rule is load-bearing rather than cosmetic.
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE grantor IS NULL)        AS raw_null_grantor,
    COUNT(*) FILTER (WHERE TRIM(grantor) = '0')    AS raw_zero_grantor,
    COUNT(*) FILTER (WHERE parcel_id IS NULL)      AS raw_null_parcel
FROM raw.property_sales;


-- -----------------------------------------------------------------------------
-- 1.3  TYPE CHECK -- THE WHOLE POINT OF THE LAYER
--
--      CTAS derives column types from the SELECT, so the cast IS the schema
--      definition. There is no type declaration to check it against and no error
--      if it is omitted -- an uncast sale_date would come out as text, silently
--      identical to raw. This query is the only thing standing between that
--      failure and a downstream layer built on a lie.
--
--      RESULT (2026-08-28):
--        objectid         bigint
--        sale_date        date     <-- [PASS] the blocker is cleared
--        sale_type_code   text
-- -----------------------------------------------------------------------------
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'stg'
  AND table_name   = 'property_sales'
  AND column_name IN ('sale_date', 'sale_type_code', 'objectid');


-- -----------------------------------------------------------------------------
-- 1.4  DRIFT DETECTION -- the dynamic counterpart to the static bound
--
--      Item 2 in the build header hardcodes the vintage bound for determinism.
--      The cost is that it will not catch NEW bad rows on re-ingest. This is
--      where that gap is covered: if this returns more than 1, the source has
--      published additional impossible dates and the bound needs review.
--
--      RESULT: [ TO RUN -- record here ]
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS rows_beyond_vintage
FROM raw.property_sales
WHERE TRIM(sale_date)::date > DATE '2026-08-01';


-- -----------------------------------------------------------------------------
-- 1.5  DISAMBIGUATE THE 25-vs-1,137 GRANTOR GAP
--
--      READ IT LIKE THIS:
--        exact_zero_all = 1,137  -> explanation (a), PROVENANCE. The file 05
--                                   figure was scoped to code 13.
--        exact_zero_all =    25  -> explanation (b), WHITESPACE. TRIM is
--                                   catching ~1,112 padded placeholders that
--                                   were invisible to every earlier query.
--
--      RESULT: [ TO RUN -- record here ]
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE grantor = '0')                                   AS exact_zero_all,
    COUNT(*) FILTER (WHERE TRIM(grantor) = '0')                             AS trimmed_zero_all,
    COUNT(*) FILTER (WHERE grantor = '0'
                       AND LEFT(term_of_sale, 2) = '13')                    AS exact_zero_code13
FROM raw.property_sales;
