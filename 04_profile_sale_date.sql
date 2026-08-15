-- =============================================================================
-- 04_profile_sale_date.sql
-- Detroit Property Pipeline
--
-- PURPOSE
--   Profile raw.property_sales.sale_date before casting it from text to a real
--   date type. Establish that every value is castable, find the true temporal
--   boundaries of the dataset, and decide WHERE the cast should live.
--
--   sale_date arrives from the source as text. Nothing temporal -- year-over-year
--   trends, "is this redevelopment sustained or one bulk transaction",
--   pre/post-bankruptcy comparison -- can be trusted until the column is a real
--   date and its edges are understood.
--
-- HEADLINE RESULTS
--   Type / format:  text, uniformly 10 chars, ISO 8601 (YYYY-MM-DD).
--   Cast safety:    all 514,384 rows cast cleanly. No cleanup required.
--   NULLs:          zero.
--   Range:          2011-01-01 through 2026-12-17.
--   Caveat 1:       exactly ONE row carries an impossible future date
--                   (2026-12-17). Single-row data entry error, not systematic.
--   Caveat 2:       the dataset is LEFT-CENSORED at 2011-01-01 -- a source
--                   extraction boundary, not a market event. See Section 4.
--
-- Run date: 2026-08-14
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- IS EVERY VALUE THE SHAPE WE THINK IT IS?
-- =============================================================================

-- 1.1  Three questions in one pass: how many rows, how many are populated, and
--      how many fail the expected ISO shape.
--
--      WHY COUNT(*) AND COUNT(sale_date) TOGETHER. COUNT(*) counts rows;
--      COUNT(column) counts NON-NULL values. The GAP between them IS the null
--      count. Same NULL behavior that made COUNT(CASE ... ELSE 0 END) wrong in
--      file 03 -- here it is used deliberately instead of tripped over.
--
--      WHY THE UNDERSCORE PATTERN. In LIKE, `_` matches exactly one character.
--      '____-__-__' therefore enforces the full SHAPE (4 chars, dash, 2, dash,
--      2), not just a prefix. A looser test like '20%' would happily pass
--      '2019-13-45' or '20xx-ab-cd'.
--
--      WHY LIKE IS AN END-TO-END MATCH. LIKE compares the WHOLE string. A value
--      of '2019-03-04 00:00:00' FAILS this pattern even though its first ten
--      characters are perfect -- the pattern runs out at char 10 while the value
--      continues. That property is what makes it a useful hidden-timestamp
--      detector (see 2.1).
--
--      RESULT:  total = 514,384 | non_null = 514,384 | bad_shape = 0
--      FINDING: no NULLs, and every value matches ISO YYYY-MM-DD.
--
--      DEBUGGING NOTE (worth keeping -- the lesson is the point). The first run
--      of this query returned bad_shape = 514,384: a 100% failure rate. The
--      cause was a typo in the pattern -- THREE underscores instead of four, so
--      a 9-character mask was being tested against 10-character values, and
--      every row failed. The data was fine; the TEST was broken.
--
--      HEURISTIC: when a check returns EXACTLY 100% or EXACTLY 0%, suspect the
--      check before the data. Real-world data is messy and returns 99.2% or
--      0.03%. Perfectly clean extremes are usually an artifact of the query.
SELECT
    COUNT(*)                                                            AS total,
    COUNT(sale_date)                                                    AS non_null,
    SUM(CASE WHEN sale_date NOT LIKE '____-__-__' THEN 1 ELSE 0 END)    AS bad_shape
FROM raw.property_sales;


-- =============================================================================
-- SECTION 2 -- CONFIRM LENGTH AND DECLARED TYPE
-- =============================================================================

-- 2.1  Measure actual string length rather than trusting a results-grid preview.
--      A grid will render '2019-03-04 00:00:00' in ways that do not draw the eye
--      to the trailing time component; LENGTH does not have an opinion.
--
--      Grouping (rather than taking MIN/MAX) also reveals MIXED formatting --
--      several distinct lengths would mean inconsistent source formats and a
--      real cleanup job.
--
--      RESULT:  len = 10 -> 514,384 rows (single bucket)
--      FINDING: uniform 10 characters. No hidden timestamp, no ragged formats.
SELECT
    LENGTH(sale_date) AS len,
    COUNT(*)          AS n
FROM raw.property_sales
GROUP BY 1
ORDER BY 2 DESC;


-- 2.2  Confirm the declared column type from the catalog. Cheap, and rules out
--      the possibility that the column is already a date/timestamp and the text
--      appearance is just display formatting.
--
--      RESULT:  sale_date | text
--      FINDING: genuinely stored as text. The cast is real work, not a no-op.
SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'raw'
  AND table_name   = 'property_sales'
  AND column_name  = 'sale_date';


-- =============================================================================
-- SECTION 3 -- THE CAST IS ITS OWN TEST
-- =============================================================================

-- 3.1  Postgres has no TRY_CAST. The idiomatic validation is simply to ATTEMPT
--      the cast inside a read-only SELECT: nothing is modified, no data is
--      touched. If it completes, every value is a valid date. If even one value
--      is malformed, Postgres raises an error AND NAMES the offending value --
--      better diagnostics than any hand-written pattern.
--
--      Bundling MIN/MAX into the same statement means the validation also
--      returns the temporal boundaries, which are needed regardless.
--
--      WHY ISO FORMAT MATTERS HERE. YYYY-MM-DD is the one format Postgres parses
--      unambiguously regardless of the DateStyle setting. Had the source used
--      MM/DD/YYYY, a server configured DMY would silently read '03/04/2019' as
--      3 April rather than 4 March -- no error, just wrong. Format luck, but
--      worth knowing it was luck.
--
--      RESULT:  earliest = 2011-01-01 | latest = 2026-12-17 | rows_cast = 514,384
--      FINDING: all 514,384 values cast cleanly -- but BOTH boundaries are
--               suspicious and are interrogated in Section 4.
SELECT
    MIN(sale_date::date) AS earliest,
    MAX(sale_date::date) AS latest,
    COUNT(*)             AS rows_cast
FROM raw.property_sales;


-- =============================================================================
-- SECTION 4 -- INTERROGATE THE BOUNDARIES
-- =============================================================================

-- 4.1  UPPER BOUND: a sale dated 2026-12-17 has not happened yet.
--
--      HYPOTHESIS TESTED: could future dates be pending/unsettled sales? No --
--      this data derives from RECORDED DEEDS (Wayne County Register of Deeds).
--      A deed is recorded AFTER a transfer completes; that is the entire purpose
--      of recording. Pending sales live in an MLS, not in the county record of
--      completed transfers. A future date on a recorded deed is therefore far
--      more likely to be a keystroke error (2026 for 2016) than a real event.
--
--      WHY GROUP BY DATE RATHER THAN JUST COUNT. The SHAPE of the distribution
--      distinguishes the two explanations:
--        scattered handful across many dates -> data entry typos
--        tight cluster on one date / all 1st-of-month -> systematic placeholder
--                                                        or load bug
--
--      RESULT:  2026-12-17 -> 1 row. That is the entire set.
--      FINDING: a single fat-fingered year out of 514,384. Not systematic.
--
--      HANDLING: do NOT delete it -- raw stays raw (see Section 5). Apply
--      `WHERE sale_date::date <= CURRENT_DATE` in the staging layer so it cannot
--      silently create a lone 2026 bucket in any year-over-year grouping.
SELECT
    sale_date::date AS sale_dt,
    COUNT(*)        AS n
FROM raw.property_sales
WHERE sale_date::date > CURRENT_DATE
GROUP BY 1
ORDER BY 1;


-- 4.2  LOWER BOUND: is 2011-01-01 a real collection start, or a placeholder
--      standing in for "date unknown"? A suspiciously round boundary is unearned
--      until checked. Inspect the first few days of volume.
--
--      RESULT:
--        2011-01-01    20
--        2011-01-02     6
--        2011-01-03    48
--        2011-01-04    40
--
--      READING IT VIA DAY-OF-WEEK: 2011-01-01 was a Saturday AND a federal
--      holiday; 01-02 a Sunday; 01-03 and 01-04 the Monday and Tuesday offices
--      reopened. So working days sit near 40-50 and the weekend/holiday sits at
--      6-20 -- exactly the rhythm real transaction data should show.
--
--      FINDING: 20 rows on a holiday Saturday is mildly elevated but nowhere
--      near placeholder territory. A true "unknown date" default would pile up
--      hundreds or thousands of rows on a single value. Note it; do not chase it.
--
--      TECHNIQUE WORTH REUSING: real transaction data has a HEARTBEAT --
--      weekday-heavy, weekend-light, holiday-dead. When a date column lacks that
--      rhythm, or spikes without explanation, something is synthetic or
--      defaulted. Cheap integrity check for any dated dataset.
--
--      [LEFT-CENSORING CAVEAT -- carry into the writeup] Nothing exists before
--      2011-01-01, so this is a SOURCE EXTRACTION boundary, not a market event.
--      Consequence: every long-run claim is a claim about 2011-onward only. In
--      Detroit that means the series begins MID-COLLAPSE -- the bankruptcy is
--      2013 -- so there is effectively NO pre-crisis baseline in this dataset.
--      Any "recovery" narrative must be stated relative to a 2011 floor, not to
--      a healthy market.
SELECT
    sale_date::date AS sale_dt,
    COUNT(*)        AS n
FROM raw.property_sales
WHERE sale_date::date <= '2011-01-04'
GROUP BY 1
ORDER BY 1;


-- =============================================================================
-- SECTION 5 -- DECISION: WHERE DOES THE CAST LIVE?
-- =============================================================================
-- Three options were considered:
--
--   (a) Cast inline in every query (`sale_date::date` each time)
--       REJECTED. The cast has to be repeated in SELECT, WHERE, GROUP BY and
--       ORDER BY. Every repetition is a place it can be written differently,
--       and a filter that casts one way while the GROUP BY casts another is a
--       genuinely difficult bug to find.
--
--   (b) Add a derived date column to raw.property_sales
--       REJECTED, deliberately. It works and it is one command -- but it places
--       a DERIVED value inside the immutable layer, after which the raw boundary
--       stops meaning anything. Raw is the audit trail: whatever was ingested
--       stays exactly as ingested. If transformation logic later proves wrong,
--       a separate layer can be rebuilt; a mutated raw cannot be recovered
--       without re-ingesting.
--
--   (c) Build a cleaned staging layer  <-- CHOSEN
--       stg.property_sales holds the parsed/cleaned columns; raw is untouched.
--       This is medallion architecture (raw -> staging -> marts), and the
--       property that matters is REPRODUCIBILITY: anyone can re-run the
--       transforms against raw and get identical output.
--
-- TABLE, NOT VIEW. Reasoning: this layer will be read repeatedly -- composition
-- query, temporal queries, spatial join, and every exploration after that. A
-- view re-runs the cast and the RTRIM across 514,384 rows on EVERY query; a
-- table pays that cost once.
--   TRADEOFF ACCEPTED: staleness. If raw is ever re-ingested, the table is
--   silently outdated until rebuilt. Acceptable here because the source is a
--   static download -- but naming the tradeoff is what makes this a decision
--   rather than a default.
--   (Note: views are not "less serious" engineering -- dbt defaults to views and
--   makes materialization a deliberate choice. The argument here is repeated
--   reads, nothing else.)
--
-- BUILD IT IDEMPOTENTLY. Write the build as a re-runnable script in the repo --
-- DROP TABLE IF EXISTS then CREATE TABLE AS SELECT -- so it can be rebuilt from
-- scratch at any moment with identical output. Idempotence is what separates a
-- pipeline from a pile of SQL somebody ran once, and it is also the insurance
-- against the staleness tradeoff above: rebuilding costs one command.
-- =============================================================================


-- =============================================================================
-- OPEN QUESTIONS -- NEXT SESSION
-- =============================================================================
-- 1. BUILD stg.property_sales (05_build_staging.sql). Scope in one pass rather
--    than adding columns piecemeal:
--      - sale_date cast to a real `date`
--      - RTRIM(parcel_id, '.') materialized as a clean join key (validated at
--        94.22% in file 01 -- currently re-typed in every query, same divergence
--        risk as the date cast)
--      - LEFT(term_of_sale, 2) as sale_type_code (repeated in every query so far)
--      - WHERE sale_date::date <= CURRENT_DATE to drop the single bad future row
--
-- 2. UNRESOLVED -- where does the CODE FAMILY classification live?
--      Option A: a sale_type_family column in stg (simple, one CASE).
--      Option C: a ref.sale_type_codes lookup table (~35 rows: code, label,
--                family, L-4015 type), joined in.
--      The principle: STAGING IS FOR CLEANING, MARTS ARE FOR MEANING. Casting
--      text to date is objectively correct regardless of the question -- that is
--      cleaning. Deciding that short sales count as market evidence above the
--      IAAO 20% distress threshold is an analytical STANCE -- that is meaning.
--      The specific pressure on Option A: this project rests on a TWO-TIER
--      comparison (strict excludes code 11, wide includes it). A single family
--      column cannot express a code that is excludable under one tier and
--      includable under the other. A lookup table handles that as ROWS AND
--      COLUMNS rather than schema changes, and is the queryable counterpart to
--      docs/terms_of_sale_legend.md. DECIDE BEFORE BUILDING 05.
--
-- 3. Composition by neighborhood (the headline query) -- now renumbered to 06.
--    One SUM(CASE...) branch per code family, grouped by neighborhood, producing
--    the distress-vs-development split. NOTE: file 03 currently points at this
--    as "04" -- update that pointer when committing.
--
-- 4. Set the minimum-n floor for the index (candidate n_total >= 30). Remember a
--    threshold is a FLOOR, not a certification: 90% of n=40 still deserves a
--    squint, and should also be checked for TEMPORAL CONCENTRATION -- transfers
--    all landing in one quarter suggest a single bulk administrative action
--    rather than a sustained market pattern. That check needs this cast.
--
-- 5. THEN join sales to parcels and begin the spatial work.
-- =============================================================================
