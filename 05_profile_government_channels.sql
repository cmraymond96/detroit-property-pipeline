-- =============================================================================
-- 05_profile_government_channels.sql
-- Detroit Property Pipeline
--
-- PURPOSE
--   Decompose term_of_sale code 13 (GOVERNMENT) into interpretable CHANNELS
--   using the grantor field.
--
--   WHY THIS QUERY EXISTS. The distress-vs-development thesis rests on reading
--   non-arms-length transfers as either market collapse or redevelopment. Code
--   13 is two-faced: the Land Bank conveying a distressed parcel to a
--   neighbor is DISTRESS, while the city assembling parcels for a development
--   deal is GROWTH. Same code, opposite meanings.
--
--   That ambiguity was tolerable when 13 was assumed to be a modest slice. The
--   code inventory (Section 1) showed it is 104,443 rows -- the SECOND-LARGEST
--   transfer type in Detroit, larger than arms-length sales. At that volume the
--   ambiguity is not a caveat, it is the central problem: grouping all 104k as
--   "government" would render Land Bank giveaway neighborhoods and development
--   corridors identical on the map.
--
-- HEADLINE RESULTS
--   Code 13 total:        104,443 (vs 96,752 arms-length -- government transfers
--                         OUTNUMBER open-market sales in Detroit)
--   Channels resolved:    ~33,200 unambiguously DISTRESS (tax + mortgage
--                         foreclosure); ~6,200 unambiguously GROWTH (city
--                         development + private entity)
--   Remaining ambiguity:  57,993 Land Bank rows -- a NAMED, BOUNDED problem
--                         requiring grantee analysis (see OPEN QUESTIONS)
--   Unclassified:         5,774 (5.5%) -- documented limitation, not chased
--
-- Run date: 2026-08-15
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- FULL CODE INVENTORY (what is actually IN the data)
-- =============================================================================

-- 1.1  Before building any classification, inventory the codes that EXIST in
--      the data -- not the codes the Michigan CAMA standard says should exist.
--      Those are different sets. A reference mapping that misses a present code
--      causes rows to be silently dropped or misfiled downstream.
--
--      NOTE: DISTINCT is redundant alongside GROUP BY -- GROUP BY already
--      collapses to one row per value. Dropped here.
--
--      RESULT (selected, by volume):
--        21-NOT USED/OTHER                        205,909
--        13-GOVERNMENT                            104,443
--        03-ARM'S LENGTH                           96,752
--        20-MULTI PARCEL SALE REF                  37,991
--        10-FORECLOSURE                            19,430
--        19-MULTI PARCEL ARM'S LENGTH              12,091
--        12-FROM LENDING INSTITUTION NOT EXPOSED   11,175
--        09-FAMILY                                 10,252
--        ...
--        (blank)                                       15
--
--      [FINDING -- reframes the thesis] Government transfers (104,443)
--      OUTNUMBER arms-length sales (96,752). Code 13 was assumed to be a minor
--      signal to dig for; it is the second-largest category in the dataset.
--      Everything in Section 2 follows from this.
--
--      [FINDING -- label drift, and vindication of the LEFT(...,2) key] Three
--      codes carry MULTIPLE label spellings for the same numeric code:
--        09  FAMILY  /  FAMILY-RELATED ENTITY
--        11  FROM LENDING INSTITUTION EXPOSED (2,513)
--            FROM *LANDING* INSTITUTION EXPOSED (6)   <- typo in the SOURCE data
--        20  MULTI PARCEL SALE REF  /  MULTIPARCEL SALE REF
--      Keying on LEFT(term_of_sale, 2) collapses these correctly. Had the
--      grouping been on the full string, code 11 would have SPLIT into two
--      categories and 6 rows would have vanished into a phantom bucket. This is
--      concrete evidence the numeric-key decision in file 02 was right.
--
--      [DATA QUALITY] 15 rows have a BLANK term_of_sale. LEFT('', 2) returns an
--      empty string, which will silently land in any ELSE bucket. Handle
--      explicitly in staging rather than letting it default.
SELECT
    term_of_sale,
    COUNT(*) AS n
FROM raw.property_sales
GROUP BY 1
ORDER BY n DESC;


-- =============================================================================
-- SECTION 2 -- GRANTOR PROFILE WITHIN CODE 13
-- =============================================================================

-- 2.1  Who is conveying property in government-coded transfers?
--
--      NOTE ON THE WHERE CLAUSE: a WHERE is CORRECT here. Files 03 and 04
--      warned against pre-filtering because those queries measured what a
--      filter EXCLUDES (retention needs its denominator). This query DESCRIBES
--      a subset, so restricting to code 13 is the point. The rule is not "avoid
--      WHERE" -- it is "know whether the filter destroys the evidence."
--
--      RESULT (raw grantor, top rows):
--        DETROIT LAND BANK AUTHORITY     56,437
--        WAYNE COUNTY TREASURER          31,250
--        CITY OF DETROIT                  1,693
--        CITY OF DETROIT - P&DD           1,430
--        City of Detroit P&DD, Care of DBA  877
--        WAYNE COUNTY TREASURER (trailing space)  745
--        WAYNE COUNTY                       570
--        HUD                                494
--        MI LAND BANK FAST TRACK AUTH       407
--        ...
--
--      FINDING: ~92% of code 13 sits in the top ~20 grantors despite 5,533
--      distinct values. Short head, long junk tail -> pattern classification is
--      viable.
--
--      [DATA QUALITY] Trailing whitespace splits the head (WAYNE COUNTY
--      TREASURER 31,250 + 745; DETROIT LAND BANK AUTHORITY 56,437 + 246; CITY
--      OF DETROIT 1,693 + 168). Same defect class as the trailing periods on
--      Wayne County parcel IDs documented in file 01.
SELECT
    grantor,
    COUNT(*) AS n
FROM raw.property_sales
WHERE LEFT(term_of_sale, 2) = '13'
GROUP BY 1
ORDER BY n DESC;


-- 2.2  Quantify how much of the cardinality is a normalization artifact vs.
--      genuinely distinct entities.
--
--      RESULT:  raw_distinct = 5,533 | clean_distinct = 5,479
--
--      [KEY LESSON -- CARDINALITY AND VOLUME ARE DIFFERENT PROBLEMS]
--      TRIM(UPPER()) collapsed only 54 distinct values (~1% of cardinality) but
--      moved ~1,200 ROWS in the head (Wayne County Treasurer +747, DLBA +247).
--      The long tail is NOT whitespace variants of agencies -- it is ~5,400
--      genuinely distinct private names, mostly individuals and small LLCs.
--      Those cannot be normalized away and should not be chased. Normalization
--      mattered exactly where the volume was, which is the only place it needed
--      to.
SELECT
    COUNT(DISTINCT grantor)              AS raw_distinct,
    COUNT(DISTINCT TRIM(UPPER(grantor))) AS clean_distinct
FROM raw.property_sales
WHERE LEFT(term_of_sale, 2) = '13';


-- 2.3  Inspect the unclassified remainder to find missed patterns.
--      (Re-run this after any change to the CASE in Section 3 -- it is the
--      feedback loop that tells you whether new branches are worth adding.)
--
--      RESULT (first pass, top rows of 11,039 unmatched):
--        CITY OF DETROIT                     1,861
--        WAYNE COUNTY                          940
--        HUD                                   497
--        WAYNE COUNTY TREASURY                 193
--        DETROIT PUBLIC SCHOOLS                126
--        TREASURER OF THE CHARTER OF WAYNE      97
--        WAYNE COUNTY SHERIFF                   68
--        FANNIE MAE                             65
--        COD - BROWNFIELD RE-DEVLP AUTH         49
--        CROWN ENTERPRISES, LLC                 39
--        PERFECTING CHURCH                      38
--        FITZ FORWARD, LLC                      34
--        CONSOLIDATED RAIL CORPORATION          31
--        DLBA                                   28
--        WAYNE COUNTY TREASUER                  26   <- misspelled
--        "0"                                    25   <- junk value
--
--      [FINDING -- private entities inside code 13] Churches, LLCs, a railroad,
--      and a tunnel partnership appear as GRANTORS in government-coded
--      transfers. These are not misspelled agencies -- they are genuinely
--      private parties. Most plausible reading: code 13 marks a transaction
--      involving a public PROGRAM (subsidy, land assembly, public financing)
--      rather than a public GRANTOR. If so this is a DEVELOPMENT signal hiding
--      inside the government bucket, not noise. Given its own channel in
--      Section 3; worth a targeted spot-check of grantee/price/date later.
--
--      [DATA QUALITY] grantor = '0' on 25 rows. Junk, alongside the 15 blank
--      term_of_sale rows from 1.1.
SELECT
    TRIM(UPPER(grantor)) AS grantor_clean,
    COUNT(*)             AS n
FROM raw.property_sales
WHERE LEFT(term_of_sale, 2) = '13'
  AND TRIM(UPPER(grantor)) NOT LIKE '%LAND BANK%'
  AND TRIM(UPPER(grantor)) NOT LIKE '%P&DD%'
  AND TRIM(UPPER(grantor)) NOT LIKE '%WAYNE%TREASURER%'
GROUP BY 1
ORDER BY n DESC
LIMIT 30;


-- =============================================================================
-- SECTION 3 -- CHANNEL CLASSIFICATION
-- =============================================================================

-- 3.1  Bucket code-13 grantors into interpretable channels.
--
--      DESIGN NOTE -- WHY PATTERNS, NOT A LOOKUP JOIN. sale_type_code is a
--      CLEAN KEY (two chars, ~35 values) and will join to ref.sale_type_codes.
--      grantor is DIRTY TEXT: abbreviations (DLBA), punctuation variants
--      (CITY OF DETROIT - P&DD / CITY OF DETROIT-P&DD), reworded titles
--      (TREASURER OF THE CHARTER OF WAYNE), and outright misspellings
--      (TREASUER). No amount of trimming makes these join on equality. Dirty
--      text needs pattern matching; clean keys get joins.
--
--      STRATEGY -- COVER VOLUME, NOT VARIETY. ~5,400 distinct private names
--      cannot be enumerated and should not be. Patterns were added until the
--      unclassified remainder fell below ~5%, then stopped. The remainder is
--      REPORTED as a limitation rather than hidden. Corporate suffixes (LLC,
--      INC, CORPORATION, PARTNERSHIP) do the heavy lifting for private parties:
--      matching on entity TYPE scales to thousands of names that could never be
--      listed individually.
--
--      *** BRANCH ORDER IS LOAD-BEARING -- DO NOT REORDER CASUALLY ***
--      CASE evaluates top-down and stops at the first match, so SPECIFIC
--      patterns must precede GENERAL ones:
--        - '%P&DD%' MUST precede '%CITY%OF%DETROIT%'. The 928 rows reading
--          'CITY OF DETROIT P&DD, CARE OF DBA' match BOTH; if the general city
--          branch ran first they would be swallowed as generic city and never
--          reach City Development.
--        - '%TREAS%' MUST precede '%WAYNE%COUNTY%'. All Treasurer variants
--          (including the TREASUER misspelling and the reversed-word-order
--          'TREASURER OF THE CHARTER OF WAYNE') are intended for Tax
--          Foreclosure regardless of which agency string surrounds them.
--        - '%SHERIFF%' precedes the generic county branch so mortgage
--          foreclosure stays distinguishable from tax foreclosure.
--
--      GOTCHAS ENCOUNTERED (both cost real rows):
--        - LIKE 'HUD %' matched NOTHING. After TRIM the value is exactly 'HUD'
--          with no trailing space. This silently DROPPED 497 rows from Tax
--          Foreclosure -- and a bucket getting SMALLER is far harder to notice
--          than an error. Fixed to 'HUD%'.
--        - LIKE '%CO$' matches nothing useful. `$` is a REGEX anchor; LIKE
--          only understands % and _, so this looks for a literal dollar sign.
--          Left in place but inert -- for true anchoring use ~ or SIMILAR TO.
--
--      VALIDATION: channel counts must sum to the code-13 total (104,443).
--      Confirmed each run -- this is the cheapest possible check that no row is
--      double-counted or lost, and it should be re-run after every edit.
--
--      RESULT:
--        Land Bank              57,993     ambiguous -- see OPEN QUESTIONS
--        Tax Foreclosure        33,011     DISTRESS
--        Other                   5,774     5.5% unclassified (documented)
--        City Development        4,852     GROWTH
--        Private Entity          1,348     likely GROWTH
--        Government              1,272     neutral (schools, MDOT, state)
--        Mortgage Foreclosure      193     DISTRESS
--        ------------------------------
--        TOTAL                 104,443     [OK] matches Section 1
--
--      [HEADLINE FINDING] Code 13 SPLITS. ~33,200 rows are unambiguously
--      distress and ~6,200 unambiguously growth. What was a single
--      uninterpretable 104k blob is now a decomposition with one named,
--      bounded remaining problem.
--
--      OPEN DECISION: Mortgage Foreclosure is thin at 193 rows. Keep separate
--      for precision, or fold into Tax Foreclosure as a single distress
--      channel? Either is defensible -- decide deliberately before the
--      composition query.
SELECT
    CASE
        -- Land Bank (all levels: Detroit, Michigan Fast Track, Wayne County)
        WHEN TRIM(UPPER(grantor)) LIKE '%LAND BANK%'        THEN 'Land Bank'
        WHEN TRIM(UPPER(grantor)) LIKE '%DLBA%'             THEN 'Land Bank'

        -- City development arm -- MUST precede the generic city branch
        WHEN TRIM(UPPER(grantor)) LIKE '%P&DD%'             THEN 'City Development'

        -- Distress channels -- TREAS pattern is deliberately loose to absorb
        -- misspellings and reversed word order
        WHEN TRIM(UPPER(grantor)) LIKE '%WAYNE%TREASURER%'  THEN 'Tax Foreclosure'
        WHEN TRIM(UPPER(grantor)) LIKE '%TREAS%'            THEN 'Tax Foreclosure'
        WHEN TRIM(UPPER(grantor)) LIKE '%SHERIFF%'          THEN 'Mortgage Foreclosure'
        WHEN TRIM(UPPER(grantor)) LIKE 'HUD%'               THEN 'Tax Foreclosure'
        WHEN TRIM(UPPER(grantor)) LIKE '%FANNIE%MAE%'       THEN 'Tax Foreclosure'

        -- Generic city -- AFTER P&DD
        WHEN TRIM(UPPER(grantor)) LIKE '%CITY%OF%DETROIT%'  THEN 'City Development'

        -- Private entities, matched on corporate suffix rather than by name
        WHEN TRIM(UPPER(grantor)) LIKE '% LLC%'             THEN 'Private Entity'
        WHEN TRIM(UPPER(grantor)) LIKE '%CHURCH%'           THEN 'Private Entity'
        WHEN TRIM(UPPER(grantor)) LIKE '%INC'               THEN 'Private Entity'
        WHEN TRIM(UPPER(grantor)) LIKE '%CORPORATION%'      THEN 'Private Entity'
        WHEN TRIM(UPPER(grantor)) LIKE '%PARTNERSHIP%'      THEN 'Private Entity'
        WHEN TRIM(UPPER(grantor)) LIKE '%CO$'               THEN 'Private Entity'  -- inert, see gotchas

        -- Other public bodies: neutral, neither distress nor development
        WHEN TRIM(UPPER(grantor)) LIKE '%PUBLIC%SCHOOL%'      THEN 'Government'
        WHEN TRIM(UPPER(grantor)) LIKE '%WAYNE%COUNTY%'       THEN 'Government'
        WHEN TRIM(UPPER(grantor)) LIKE '%MDOT%'               THEN 'Government'
        WHEN TRIM(UPPER(grantor)) LIKE '%STATE%OF%MICHIGAN%'  THEN 'Government'
        WHEN TRIM(UPPER(grantor)) LIKE '%HOUSING%COMMISSION%' THEN 'Government'

        ELSE 'Other'
    END          AS channel,
    COUNT(*)     AS n
FROM raw.property_sales
WHERE LEFT(term_of_sale, 2) = '13'
GROUP BY 1
ORDER BY n DESC;


-- =============================================================================
-- CHAIN-OF-CUSTODY CAVEAT (spotted while reading raw rows -- affects counts)
-- =============================================================================
-- Parcel 06003365 (1566 RICHTON) appears as THREE separate "sales":
--   2012-10-05  WAYNE COUNTY TREASURER   -> MI LAND BANK FAST TRACK   $0
--   2015-02-25  MI LAND BANK FAST TRACK  -> DETROIT LAND BANK         $0
--   2016-08-25  DETROIT LAND BANK        -> CASS COMMUNITY SOCIAL SVCS $100
--
-- That is not three market events. It is ONE property moving down a chain of
-- custody: tax foreclosure -> state land bank -> city land bank -> nonprofit.
-- Neighbouring parcels (1558 and 1562 RICHTON) show the same pattern on the
-- same block.
--
-- CONSEQUENCE: some share of the 104,443 government transfers are the SAME
-- PARCELS counted repeatedly as they move between agencies. Government
-- transfers may still outnumber arms-length sales, but by LESS than the raw
-- count implies. Quantify before making that claim in the writeup:
-- count distinct parcels vs. count of rows within code 13, and check how often
-- a single parcel appears more than once.
-- =============================================================================


-- =============================================================================
-- OPEN QUESTIONS -- NEXT SESSION
-- =============================================================================
-- 1. SPLIT THE LAND BANK (57,993 rows -- the largest remaining ambiguity).
--    Grantor identifies the CHANNEL; grantee identifies the OUTCOME. Expect
--    roughly: DLBA -> individual person = side-lot / giveaway (DISTRESS);
--    DLBA -> LLC / INC / nonprofit developer = redevelopment (GROWTH). The same
--    corporate-suffix pattern used in Section 3 applies directly.
--
-- 2. Quantify the chain-of-custody duplication (see caveat above) before
--    claiming government transfers outnumber arms-length sales.
--
-- 3. Spot-check the Private Entity rows -- pull grantee, price, date, address
--    for CROWN ENTERPRISES, FITZ FORWARD, PERFECTING CHURCH -- to confirm the
--    "public program, private grantor" reading.
--
-- 4. Decide: fold Mortgage Foreclosure (193) into Tax Foreclosure, or keep
--    separate?
--
-- 5. Handle the junk values in staging: 15 blank term_of_sale rows, grantor = '0'
--    (25 rows).
--
-- 6. THEN build stg.property_sales and ref.sale_type_codes (see file 04
--    Section 5 for the architecture decision), and only then the composition
--    query.
-- =============================================================================
