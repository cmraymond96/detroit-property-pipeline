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
-- Run date: 2026-08-28 (sections 1.1-1.3)
--           2026-08-31 (sections 1.4-1.5) -- FILE NOW COMPLETE
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
--
--      >>> RESOLVED 2026-08-31 in S1.5 -- explanation (a), PROVENANCE. <<<
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
--      RESULT (2026-08-31):
--        rows_beyond_vintage   1
--
--      [PASS] Exactly 1, and it is the already-known row: sale_date 2026-12-17,
--      roughly 3.5 months ahead of the run date. Recorded sales are backward-
--      looking -- a deed is recorded AFTER the transaction, never before -- so
--      a future record date is a data-entry error, not a scheduled sale.
--      Already nulled by the build's CASE, which is why 1.1 shows null_dates = 1.
--      No NEW impossible dates have appeared. Bound does not need review.
--
--      NOTE ON SAFETY -- this cast is unguarded (TRIM(sale_date)::date against
--      raw, where the column is still text). It is safe only because file 10
--      already cast every row in the table without error, which empirically
--      proves every value is castable. Worth knowing that the CASE in file 10
--      does NOT provide that protection: both of its branches cast, so it
--      decides whether to KEEP a result, never whether to ATTEMPT one. It is a
--      future-date filter, not a bad-value guard. If the source ever ships a
--      non-castable value, THIS query is where it will surface -- as a hard
--      error, not a wrong number.
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
--      RESULT (2026-08-31):
--        exact_zero_all      1,137
--        trimmed_zero_all    1,137
--        exact_zero_code13      25
--
--      [RESOLVED -- explanation (a), PROVENANCE.] Two independent reads, same
--      answer:
--        - exact = trimmed = 1,137. TRIM changed NOTHING for these rows, so
--          there is no hidden whitespace. Explanation (b) is dead.
--        - Reproducing file 05's exact conditions (grantor = '0' AND code 13)
--          returns exactly 25. The old figure was never a citywide count. It
--          was 25 WITHIN the government bucket, written into the dirt pile
--          without its scope tag attached.
--
--      The 1,137 was always there. It had simply never been looked at outside
--      code 13.
--
--      [COROLLARY for the 8/15 note] The ~1,200 rows that TRIM(UPPER()) moved in
--      the grantor head on 8/15 were REAL grantor names carrying stray
--      whitespace -- not these '0' placeholders. Two separate phenomena that
--      happened to sit at a similar magnitude. Do not merge them in the writeup.
--
--      [SECOND INSTANCE OF THE SAME TRAP] This is now twice in one file that a
--      figure from file 05/06 read as a mismatch purely because it was lifted
--      out of a WHERE clause (the 15 NULL parcel_ids in 1.1, the 25 grantors
--      here). Both times the data was fine and the EXPECTATION was wrong.
--      Going forward: record the scope alongside any number carried between
--      files. A count without its WHERE clause is not a fact.
--
--      [OPEN -- low priority] If only 25 of the 1,137 sit in code 13, the other
--      ~1,112 are concentrated somewhere else. Code 13 has real named grantors
--      (Land Bank, Treasurer); the 205,909-row code 21 grab-bag is the likely
--      home. Not blocking -- but worth a one-line GROUP BY before the grantor
--      field is used analytically.
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE grantor = '0')                                   AS exact_zero_all,
    COUNT(*) FILTER (WHERE TRIM(grantor) = '0')                             AS trimmed_zero_all,
    COUNT(*) FILTER (WHERE grantor = '0'
                       AND LEFT(term_of_sale, 2) = '13')                    AS exact_zero_code13
FROM raw.property_sales;


-- =============================================================================
-- VALIDATION VERDICT
-- =============================================================================
-- stg.property_sales PASSES. 514,384 rows in, 514,384 out, sale_date typed as
-- date, all five checks green. Three known data-quality items remain, all
-- characterized and none blocking:
--     1,238 NULL parcel_id  -- self-enforcing, drops out of joins and DISTINCT
--     1,308 NULL grantor    -- 171 already null + 1,137 '0' placeholders
--         1 NULL sale_date  -- the 2026-12-17 transposition
-- Downstream layers may build on this table.
-- =============================================================================
