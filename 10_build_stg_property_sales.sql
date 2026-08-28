-- =============================================================================
-- 10_build_stg_property_sales.sql
-- Detroit Property Pipeline
--
-- PURPOSE
--   Build the staging layer for property sales. Files 01-06 profiled
--   raw.property_sales and established what is wrong with it. Those findings
--   currently live only in SQL comments, which means every downstream query has
--   to re-apply them by hand -- RTRIM on parcel_id has already been retyped in
--   six separate files. This script encodes each rule ONCE so every downstream
--   consumer inherits it.
--
--   The blocking problem it solves: sale_date is stored as text, so the 2017+
--   analysis window cannot be applied. Two headline findings (the 1.30x
--   government-vs-arms-length gap, and under 18% of parcels ever transacting on
--   the open market) are stamped "directional only" until that cast exists.
--
-- MEDALLION POSITION
--   raw = immutable audit trail. staging = cleaning. marts = meaning.
--   Staging CLEANS but does not DECIDE. Notably, this table is NOT filtered to
--   2017+. Date scoping is a modeling decision and belongs in the mart layer --
--   the dataset is left-censored at 2011, so the pre-2017 rows are the only
--   baseline that will ever exist and must not be discarded here.
--
-- IDEMPOTENCY
--   DROP-and-recreate. Running this script twice produces the same table rather
--   than an error or a duplicate.
--
-- Run date: 2026-08-28
-- =============================================================================


-- =============================================================================
-- TRANSFORMATIONS
-- =============================================================================
--
-- 1. parcel_id -- RTRIM(TRIM(parcel_id), '.')
--    Wayne County parcel IDs carry trailing periods, documented 8/9.
--    NOTE ON RTRIM: the second argument is a CHARACTER SET, not a length. It
--    peels period characters off the right edge and stops at the first
--    non-period. Nothing else is touched. Passing an integer fails -- there is
--    no rtrim(varchar, integer) overload.
--    ORDER IS LOAD-BEARING: TRIM first, then RTRIM. Reversed, a value like
--    '22085947. ' keeps its period because whitespace blocks the peel.
--    [NOT A DEFECT] Hyphenated IDs ('22008634-5') are CONSOLIDATED PARCEL
--    RANGES. Dotted = split parcel; hyphenated = range. Do NOT strip hyphens.
--
-- 2. sale_date -- CASE ... > DATE '2026-08-01' THEN NULL ELSE ::date
--    Stored as text in ISO 8601. Cast so DOWNSTREAM layers can apply the 2017+
--    window; the filter itself is deliberately not applied here.
--    One row is dated 2026-12-17 -- a keystroke transposition, not a planned
--    sale. It is the only defect in the file that SURVIVES a `>= 2017` filter,
--    which makes it the only one capable of producing a wrong answer rather
--    than a missing one. It would also become MAX(sale_date), silently
--    corrupting any "most recent sale" or time-series upper bound.
--    Only the date field is bad -- parcel, price, grantor, grantee are all
--    sound -- so the field is nulled and the row is KEPT. NULL fails every
--    comparison, so it excludes itself from both `>= 2017` and `< 2017`.
--    WHY A HARDCODED BOUND, NOT CURRENT_DATE: the real question is not "is this
--    in the future" but "is this after the data could possibly describe." The
--    extract has a vintage; nothing in it can legitimately postdate the pull.
--    CURRENT_DATE would make the build non-deterministic -- after 2026-12-17
--    the bad row would silently start flowing through.
--    THE TRADEOFF: a static bound will not catch NEW bad rows on re-ingest.
--    That is correct division of labor. Transformation logic stays
--    deterministic; DETECTION belongs in a separate validation query that
--    counts rows exceeding the bound and reports when the count changes.
--
-- 3. grantor -- NULLIF(TRIM(grantor), '0')
--    25 rows carry '0' as a placeholder. Empty string and '0' are VALUES; NULL
--    is an ABSENCE. A placeholder left in place forms its own GROUP BY bucket
--    and survives `<> '03'`-style exclusions, because it genuinely is not '03'.
--
-- 4. term_of_sale -- NULLIF(TRIM(term_of_sale), '')
--    Same reasoning as 3. 15 rows are blank.
--
-- 5. sale_type_code -- NULLIF(LEFT(TRIM(term_of_sale), 2), '')  [DERIVED]
--    Per the CAMA legend, the two-digit numeric code is the STABLE key; the
--    text labels drift between publications. This parse has been retyped by
--    hand in every file since 02. Materializing it is CLEANING, not modeling --
--    it extracts the reliable component of a compound field, the same category
--    as casting a date. GROUPING these codes into distress/development families
--    is the modeling decision, and that stays downstream in ref.sale_type_codes.
--    The NULLIF matters: LEFT('', 2) returns '', which would reintroduce
--    exactly the placeholder that item 4 removes.
--    term_of_sale is retained alongside it -- the label is still useful for
--    eyeballing results.
--
-- 6. All remaining text fields -- TRIM()
--    File 05 showed TRIM(UPPER()) collapsed 54 of 5,533 distinct grantor values,
--    so whitespace variants are real in this source, just uncommon. Whitespace
--    is never semantically meaningful in these fields, so removing it is
--    cleaning by definition. Applied as a blanket rule so no downstream query
--    ever has to wonder whether a given column was covered.
--
-- 7. "ObjectId" -- aliased to objectid
--    An ArcGIS export artifact (source-system cursor row number), preserved
--    verbatim by the ingest. Postgres folds unquoted identifiers to lowercase,
--    so a mixed-case column can ONLY be referenced with double quotes, forever.
--    The alias kills that requirement at the staging boundary -- quoted once
--    here, never again downstream.
--
-- ROWS DROPPED: none. 15 NULL parcel_ids are retained -- they are unusable for
--    joins and parcel-grain dedup, but perfectly usable for citywide counts,
--    sale-type distributions and date histograms. Dropping a row in staging is
--    a decision made on behalf of queries that have not been written yet. The
--    defect is self-enforcing: inner joins exclude them, COUNT(DISTINCT)
--    ignores them.
-- =============================================================================


CREATE SCHEMA IF NOT EXISTS stg;

DROP TABLE IF EXISTS stg.property_sales;

CREATE TABLE stg.property_sales AS
SELECT
    sale_id,
    RTRIM(TRIM(parcel_id), '.')                     AS parcel_id,
    TRIM(address)                                   AS address,
    CASE
        WHEN TRIM(sale_date)::date > DATE '2026-08-01' THEN NULL
        ELSE TRIM(sale_date)::date
    END                                             AS sale_date,
    amt_sale_price,
    NULLIF(TRIM(grantor), '0')                      AS grantor,
    TRIM(grantee)                                   AS grantee,
    TRIM(liber_page)                                AS liber_page,
    NULLIF(TRIM(term_of_sale), '')                  AS term_of_sale,
    NULLIF(LEFT(TRIM(term_of_sale), 2), '')         AS sale_type_code,
    TRIM(sale_verification)                         AS sale_verification,
    TRIM(sale_instrument)                           AS sale_instrument,
    sale_number,
    pct_property_transferred,
    TRIM(is_multi_parcel_sale)                      AS is_multi_parcel_sale,
    TRIM(property_class_code)                       AS property_class_code,
    TRIM(property_class_description)                AS property_class_description,
    TRIM(ecf_neighborhood)                          AS ecf_neighborhood,
    TRIM(neighborhood)                              AS neighborhood,
    TRIM(council_district)                          AS council_district,
    TRIM(zip_code)                                  AS zip_code,
    street_number,
    TRIM(street_prefix)                             AS street_prefix,
    TRIM(street_name)                               AS street_name,
    TRIM(street_type)                               AS street_type,
    TRIM(unit_number)                               AS unit_number,
    longitude,
    latitude,
    "ObjectId"                                      AS objectid
FROM raw.property_sales;


-- =============================================================================
-- NOTE
--   No ad-hoc SELECT below this line. A build script builds. Verification lives
--   in 11_validate_stg_property_sales.sql so the two can be run independently.
-- =============================================================================
