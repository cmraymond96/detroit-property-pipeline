-- =============================================================================
-- 03_retention_by_neighborhood.sql
-- Detroit Property Pipeline
--
-- PURPOSE
--   Measure the arms-length RETENTION RATE for each neighborhood: what share of
--   all recorded transfers survive the strict-tier filter (term_of_sale 03).
--
--   This is the clustering diagnostic that must run BEFORE the strict tier can
--   be trusted. Filtering to 03-ARM'S LENGTH discards ~81% of the dataset, and
--   that exclusion is almost certainly NOT uniform across the city -- distress
--   (foreclosure, land bank, $1 quit-claims) concentrates in high-vacancy
--   neighborhoods. If retention varies sharply by neighborhood, the strict
--   filter silently biases distressed areas, and every downstream median
--   inherits that bias. This query quantifies the variation.
--
-- HEADLINE RESULT
--   Grain:        neighborhood (named) -- lives directly on raw.property_sales;
--                 no parcels join required for this step.
--   Spread:       retention ranges from ~6% (Core City) to ~32% (Bagley) across
--                 ~190 named neighborhoods. Exclusion is decisively NOT uniform.
--   Coverage gap: 30,237 sales (5.9%) carry a BLANK neighborhood -- surfaced as
--                 its own row, not suppressed.
--   CAUTION:      retention rate alone does NOT measure market health. See the
--                 interpretive note at the foot of this file.
--
-- Run date: 2026-08-13
-- =============================================================================


-- =============================================================================
-- SECTION 1 -- CHOOSE THE GEOGRAPHY GRAIN
-- =============================================================================

-- 1.1  Eyeball the sales table to confirm which geography fields exist and at
--      what grain, before committing to a GROUP BY key.
--
--      FINDING: three candidate geography columns live directly on
--      raw.property_sales -- no join to raw.parcels is needed to bucket sales
--      by area:
--        neighborhood       named areas (Islandview, Midtown, Core City ...)
--        ecf_neighborhood   assessor Economic Condition Factor micro-zone (coded)
--        council_district   coarse, a handful citywide
--
--      DECISION: use `neighborhood`. It is the exact grain of the research
--      question ("how does the market function block-of-the-city by block"),
--      and its coarser buckets give larger per-area denominators, so retention
--      percentages are stable rather than jumpy. ecf_neighborhood is a good
--      FINER diagnostic to layer in later, but leading with it would produce
--      thin, noisy denominators.
--
--      ALSO OBSERVED (parked for the spatial phase): longitude / latitude are
--      populated on SOME sale rows but not all. May soften the parcel-geometry
--      dependency for distance-to-hub work -- but a choropleth still needs
--      neighborhood BOUNDARY polygons, which is a separate layer. Revisit; do
--      not act on it here.
SELECT *
FROM raw.property_sales
LIMIT 10;


-- =============================================================================
-- SECTION 2 -- RETENTION BY NEIGHBORHOOD
-- =============================================================================

-- 2.1  Count the strict-tier subset and the total in a SINGLE pass.
--
--      WHY NO WHERE CLAUSE. The instinct is to write
--        WHERE LEFT(term_of_sale, 2) = '03'
--      but that pre-filters the denominator out of existence: it deletes every
--      non-arms-length row BEFORE the count, leaving a numerator with nothing
--      to divide by. Retention is clean-over-TOTAL, so total turnover must stay
--      in scope. Same failure mode as the INNER-join trap in 01 -- a filter
--      that destroys the evidence of its own exclusion.
--
--      WHY SUM(CASE...1/0), NOT COUNT(CASE...). COUNT counts every non-NULL
--      value, and 0 is not NULL -- so COUNT(CASE ... ELSE 0 END) would count
--      the non-matches too and every neighborhood would read 100%. SUM adds the
--      zeros (contributing nothing) and the ones (contributing 1), yielding the
--      subset count. This is the exact dollar_sales pattern from 02.
--
--      WHY 100.0, NOT 100. n_arm and n_total are both bigint; bigint / bigint
--      is INTEGER division and truncates every sub-100% ratio to 0. Leading
--      with 100.0 promotes the expression to numeric before the divide.
--
--      WHY REPEAT THE EXPRESSION IN pct_arm. Postgres does not allow a SELECT
--      alias (n_arm, n_total) to be referenced elsewhere in the same SELECT
--      list, so the CASE and COUNT(*) are spelled out again. (Wrapping this in
--      a subquery/CTE to reference the aliases is the tidier alternative -- fine
--      to refactor later; left explicit here so the arithmetic is visible.)
--
--      WHY ORDER BY n_total DESC. Retention must be read next to its sample
--      size. A neighborhood at "0% retention" on n=2 is noise, not a finding;
--      putting n beside the rate makes that obvious at a glance.
--
--      RESULT (selected, largest samples first):
--        neighborhood        n_arm   n_total   pct_arm
--        (blank)              3,108    30,237    10.28   <- coverage gap, see 2.2
--        Warrendale           4,294    17,814    24.11
--        Midwest              1,060    10,530    10.07
--        Morningside          2,229    10,134    22.00
--        Claytown             1,568     9,754    16.08
--        Bethune Community    1,886     8,779    21.48
--        Bagley               2,723     8,418    32.35   <- high end
--        Brightmoor           1,146     8,401    13.64
--        ...
--        Midtown                316     1,729    18.28
--        Core City               55       852     6.46   <- low end
--        Douglass                 0        49     0.00   <- tiny n, see NOTE
--
--      FINDING: retention is emphatically NOT uniform -- a ~5x spread from Core
--      City (6.5%) to Bagley (32%). The strict-tier bias the design feared is
--      real and unevenly distributed. This is exactly why the two-tier
--      comparison exists.
--
--      NOTE ON TINY DENOMINATORS: several neighborhoods have n_total in the
--      single/double digits (Waterworks Park 0/2, Garden View 1/8,
--      Medical Center 1/12, Douglass 0/49). Their percentages are statistically
--      meaningless and will render as visual outliers on a choropleth. Apply a
--      minimum-n threshold (candidate: n_total >= 30) before trusting or
--      mapping a neighborhood's retention. Decide the floor when building the
--      index, not here.
SELECT
    neighborhood,
    SUM(CASE WHEN LEFT(term_of_sale, 2) = '03' THEN 1 ELSE 0 END) AS n_arm,
    COUNT(*)                                                       AS n_total,
    ROUND(
        100.0 * SUM(CASE WHEN LEFT(term_of_sale, 2) = '03' THEN 1 ELSE 0 END)
        / COUNT(*), 2
    )                                                             AS pct_arm
FROM raw.property_sales
GROUP BY neighborhood
ORDER BY n_total DESC;


-- =============================================================================
-- SECTION 2.2 -- COVERAGE CAVEAT (the blank-neighborhood bucket)
-- =============================================================================

-- 2.2  Quantify the unlabeled bucket explicitly so it is a documented limit,
--      not a surprise later.
--      RESULT: 30,237 sales (5.9% of 514,384) have no neighborhood assigned.
--      These are dropped from any per-neighborhood map by necessity, but the
--      loss is bounded and known. Carry into the writeup.
SELECT
    COUNT(*)                                                   AS blank_rows,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM raw.property_sales), 2)
                                                               AS pct_of_all
FROM raw.property_sales
WHERE neighborhood IS NULL
   OR TRIM(neighborhood) = '';


-- =============================================================================
-- INTERPRETIVE NOTE -- RETENTION RATE IS NOT MARKET HEALTH
-- =============================================================================
-- The temptation is to read low retention as "distressed." It is not that
-- simple. Two neighborhoods at the same low retention can be telling OPPOSITE
-- stories, and the retention number alone cannot distinguish them:
--
--   Development-driven low retention  -> the non-03 transfers are dominated by
--     13-GOVERNMENT and 19/20 multi-parcel (city/DEGC land assembly). Property
--     isn't selling arms-length because it's being ASSEMBLED and built.
--
--   Distress-driven low retention     -> the non-03 transfers are dominated by
--     the foreclosure family (10/11/17/30) and 21 quit-claims. Property isn't
--     selling arms-length because the market has COLLAPSED.
--
-- Retention tells you HOW THIN the arms-length market is.
-- The COMPOSITION of the non-03 transfers tells you WHY.
-- The Neighborhood Health Index needs both axes. See docs/terms_of_sale_legend.md
-- for the code families and the IAAO >20% rule underpinning the wide tier.
-- =============================================================================


-- =============================================================================
-- OPEN QUESTIONS -- NEXT SESSION
-- =============================================================================
-- 1. 04_composition_by_neighborhood.sql -- one SUM(CASE...) branch per code
--    family (arms-length / foreclosure-family / government / multi-parcel /
--    other), grouped by neighborhood. THIS produces the distress-vs-development
--    split and is the headline query.
-- 2. sale_date is still stored as text -- cast to date before any temporal work.
-- 3. Set the minimum-n floor for the index (candidate n_total >= 30).
-- 4. THEN join sales to parcels (RTRIM key, validated 94.22%) and begin the
--    spatial work.
-- =============================================================================