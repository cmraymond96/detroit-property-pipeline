# NEXT SESSION — warm start

## Where we are
Scoping complete. Decisions locked (see `PROJECT_BRIEF.md`). Repo initialized with brief + README.

## Next up — STEP 0: Setup + prove the pipe
1. **Environment** — conda env; install: `postgresql` + `postgis`, `dbt-postgres`, `geopandas`, `requests`, `pandas`
2. **Stand up Postgres** locally; create the db; `CREATE EXTENSION postgis;`
3. **Ingest ONE dataset** end-to-end (Property Sales *or* Parcels assessment data) → `raw` schema. Goal is just to prove data flows in — not to model it yet.
4. **Commit + push**

## Locked decisions (quick ref)
- **Metric:** assessed value (land value = headline); sales = cross-check
- **Window:** clean **2017 → present** (2014 = story frame; 2017 reappraisal = methodology break)
- **Geo unit:** Detroit neighborhoods
- **Warehouse:** Postgres + PostGIS

## Open sub-choice to settle
- Pre-2017 handling: analyze 2017→present clean *(recommended)* vs. full 2014→present with the break annotated

## Reminders
- `git pull` before starting on either machine; `git push` before closing
- Restart Kernel & Run All before committing any notebook
- Run `git diff --stat` before `git add .` if diffs look weird

# NEXT SESSION — warm start

## Where we are (7/30/2026)
Step 0 COMPLETE ✅ — ingested raw.property_sales (514,384 rows) from the
Detroit ArcGIS API into Postgres. Pipeline handles pagination + retries + is idempotent.

## Homework before next session (at work / lunch)
- Read STEP0_CHEATSHEET.md
- Open step0_ingest.ipynb and write a plain-English comment above each line
of the ingestion loop cell — in my own words. Goal: turn "Claude did it"
into "I understand it."

## Next up — STEP 2: Parcels (assessed values + GEOMETRY)
1. Find the Parcels dataset endpoint on the Detroit portal (same method as sales)
2. Smoke-test 5 rows — confirm assessed value fields + land value + geometry
3. This time returnGeometry=TRUE — pull the actual parcel shapes
4. Land into raw.parcels using geopandas → PostGIS (first real spatial data!)

## Locked decisions (quick ref)
- Metric: assessed value (land value = headline); sales = cross-check
- Window: clean 2017 → present
- Geo unit: Detroit neighborhoods
- Warehouse: Postgres + PostGIS, port 5433, db detroit_property

## Reminders
- git pull first thing; git push before closing
- conda activate detroit-property
- Kernel = detroit-property (top-right in VS Code)


## Step 2 progress (Fri - 7/31/2026)
- Found Parcels (current) dataset — GeoService endpoint saved in step2_parcels.ipynb
- Smoke test PASSED (5 rows, 52 cols). Confirmed we have:
  - amt_assessed_value + amt_assessed_value_previous (the spine + built-in prior year!)
  - amt_taxable_value + _previous
  - neighborhood column (no spatial join needed just to group!)
  - property_class (for residential filter — downstream)
  - real geometry (Shape__Area/Length present)

## OPEN DECISION to revisit
- No land-value / building-value split in this dataset — just one amt_assessed_value.
  Brief had LAND value as headline metric. Decide: hunt for a land-value source,
  or make total assessed value the spine + land value a stretch goal.

## Next up — STEP 2 back half (needs full 2hr)
- Flip returnGeometry=TRUE, switch to geopandas, pull parcels WITH shapes into raw.parcels (PostGIS)


## Session update (Mon 8/3/2026)
- Step 0 notebook was committed EMPTY on GitHub — recovered from an unsaved
VS Code tab and committed for real. Lesson: Ctrl+S + read `git status` before every commit.
- PROJ bug fixed — PROJ_LIB pointed at PostGIS's old proj.db. Fix now lives at
top of step2_parcels.ipynb (must run before imports).
- Parcels geometry PROBED and confirmed: Polygons, maxRecordCount 1000,
stored EPSG:3857, requested as 4326. Shape__Area is NOT trustworthy sq ft.
- parcel_id has a trailing period (e.g. 02000184.) — clean before Assessment Roll join.

## Warm-start task (needs a fresh full session)
Write the geometry loop: f=geojson, orderByFields=OBJECTID, page=1000.
Write each chunk to raw.parcels (geopandas -> PostGIS) as it arrives.
Resume marker = SELECT COUNT(*) FROM raw.parcels, NOT a Python variable.
Let it run, confirm final count ~377,863.


## Session update (Thu 8/6/2026) — STEP 2 GEOMETRY PULL COMPLETE ✅
- Full parcel geometry landed: raw.parcels = 377,863 rows, WITH shapes, in PostGIS.
Confirmed via SELECT COUNT(*) — matches target. Ran ~10 min.
- BUG HIT + FIXED: schema drift across chunks. First chunk typed property_class as
bigint; a later chunk had a null → pandas promoted the column to float → Postgres
rejected "401.0" into a bigint column. Fix: cast all numeric cols to float64 before
to_postgis, so the table is double precision everywhere and nulls are legal.
LESSON: the first chunk silently writes the type contract for all 378 chunks.
- Had to DROP the bad 63k-row table once before re-running. DROP is NOT in the loop
cell (it would kill the resume marker) — kept it deliberate.

## HOMEWORK (do on laptop tomorrow — this is the learning, not the pull)
- Write my OWN comments above each block of the Step 2 loop cell, in plain English,
explaining WHY not WHAT. Four jobs: connect+resume marker / request / clean / write.

## NEXT UP — STEP 3: Assessment Roll (land vs building value split)
- Smoke-test the Assessment Roll FeatureServer endpoint (returnGeometry=false, 5 rows).
- Confirm land-value + improvement-value fields + the parcel_id join key.
- Remember: parcel_id has a TRAILING PERIOD (e.g. "02000184.") — clean before joining.
- Reminder: laptop CANNOT reach local Postgres — Step 3 DB work waits for desktop.


## Session update (Sun 8/9/2026) 
- Join key resolved: RTRIM(parcel_id, '.') on both sides, 94.22% match rate
- Parcels side confirmed unique on normalized ID — no fan-out risk
- Hyphenated = consolidated parcel ranges; dotted = genuine split parcels. Both meaningful, neither gets stripped
- Next up: the arms-length sales filter using sale_verification and term_of_sale — the $1 sales have to come out before any price analysis
- sale_date is text, needs casting
- Known limitation to document: parcels are a current snapshot, so historical splits/merges aren't captured


## Session update (Mon 8/10/2026)
- sale_verification is the WRONG column — it records the source document
  (affidavit/deed/title co), not whether the price is market evidence. Ruled out.
- term_of_sale is the instrument. Michigan assessor code set classifying WHY
  each transfer happened.
- Filter on LEFT(term_of_sale, 2), not the full string — labels drift
  ("09-FAMILY" vs "09-FAMILY/RELATED ENTITY", "LENDING" vs "LANDING" typo,
  two spellings of "20"). Number is the stable key. Same lesson as parcel_id.
- Codes 19 and 20 (multi-parcel) must be excluded: one price covers several
  parcels, so joining to a single parcel_id fabricates high outliers.
- 03-ARM'S LENGTH = 96,752 rows (18.8%), median $45,162, only 319 nominal.
  Clean.
- 21-NOT USED/OTHER = 205,909 rows. ~56% nominal, another ~21% under $1k.
  Real-money rows peak at $1k-10k — a distressed low-value market, NOT
  mislabeled arms-length sales.
- DECISION CARRIED FORWARD: two-tier design. Strict tier (03 only) vs wide
  tier (add 11-EXPOSED, possibly price-floored 21). Run neighborhood medians
  both ways; where the tiers DIVERGE is the finding.
- Open question: is the 81% exclusion uniform across neighborhoods? Need
  retention rate per neighborhood before trusting the strict tier.
- Deliverable scoped: static choropleth comparison, NOT the interactive map.
  Interactive version deferred to the Flask phase.
  
- NORTH STAR (deliverable shape): Neighborhood Health Index. Score driven by
  the DIVERGENCE between strict tier (03) and wide tier (all turnover), plus
  arms-length retention rate + sample size per neighborhood. Small gap = healthy
  functioning market (Midtown); huge gap = collapsed into distressed turnover
  (Core City). Map the gap across the city.
- Build the underlying numbers FIRST (divergence ratio, retention, n).
  Letter-grade / A-F scale is a presentation layer applied LAST, not first.


  ## Session update (Thu 8/13/2026)
Notes:
1. Looking at raw.property_sales, we can see that the sales data provides us a longitude/latitude value. That's potentially a big deal for the spatial phase, because distance-to-commercial-hub is computed from a point, and if sales already carry points, part of the reason we were pulling parcel geometry softens. I don't want to overclaim it, though, the choropleth still needs neighborhood boundary polygons to draw regions, which is a different layer from both sales points and parcels, and row 2 shows the coordinates aren't always populated. So it reshapes the spatial dependency, doesn't erase it.

- Terms-of-sale legend built and committed (docs/terms_of_sale_legend.md),
  derived from MI STC CAMA Data Standards Aug 2025.
- KEY: assessor's "Recommended L-4015 Type" column = the strict/wide boundary.
  Conventional = strict tier. Reference = excluded from ratio studies.
- WIDE TIER NOW HAS A CITABLE SPINE: IAAO 20% rule. Foreclosure-related codes
  (10/11/17/30/34) become valid ratio inputs when they exceed 20% of a market
  area — i.e. when distress IS the market. Not a hack; it's the standard.
- HEADLINE FOUND: retention rate alone does NOT measure market health. Same low
  retention = opposite stories. Development-driven (13-govt + 19/20 assembly)
  vs distress-driven (10/11/17/30 foreclosure family + 21 quit-claims).
  Retention = how thin the arms-length market is. COMPOSITION = why.
- Confirmed: neighborhood, ecf_neighborhood, council_district all live ON
  raw.property_sales. Retention is pure sales-side — does NOT depend on the
  parcels join. Run retention at named `neighborhood` grain (stable denominators).
- Coverage caveat quantified: ~30,237 sales (blank neighborhood) = ~5% of data.
  Surface as its own row, don't suppress.
- PARK for spatial phase: raw.property_sales carries longitude/latitude on SOME
  rows (populated row 1, blank row 2). May soften the parcel-geometry dependency
  for distance-to-hub — but choropleth still needs boundary polygons. Revisit.

### Next session
1. Composition query: per neighborhood, SUM(CASE...) one branch per code family
   (arms-length / foreclosure-family / government / multi-parcel / other),
   grouped by neighborhood. This produces the distress-vs-development split.
2. Cast sale_date text -> date (still outstanding).
3. THEN join sales to parcels, start spatial.


## Session update (Sat 8/15/2026) — GOVERNMENT CHANNEL DECOMPOSITION ✅
*(logged retroactively — this session was never written up)*
 
- Built `sql/05_profile_government_channels.sql`. Went sideways from the planned
  composition query on purpose: you can't write a composition query that treats
  code 13 as ONE bucket when it's 104k rows pointing in opposite directions.
- FULL CODE INVENTORY run first (what's actually IN the data, not what the CAMA
  standard says should be). Headline: **13-GOVERNMENT = 104,443 rows, the
  SECOND-LARGEST transfer type, outnumbering 03-ARM'S LENGTH (96,752).**
  Code 13 was assumed to be a minor signal; it's the second-biggest category.
- Label drift VINDICATED the `LEFT(term_of_sale, 2)` decision: codes 09, 11, 20
  each carry multiple spellings (incl. a "LANDING INSTITUTION" typo in the
  source data, 6 rows). Grouping on the full string would have split code 11
  and vanished 6 rows into a phantom bucket.
- Grantor profile: ~92% of code 13 sits in the top ~20 grantors despite 5,533
  distinct values. Short head, long junk tail → pattern classification viable.
- KEY LESSON — cardinality ≠ volume. `TRIM(UPPER())` collapsed only 54 distinct
  values (~1% of cardinality) but moved ~1,200 ROWS in the head. The long tail
  is ~5,400 genuinely distinct private names, not whitespace variants. Don't
  chase them.
- CHANNEL CLASSIFICATION built (patterns, not a lookup join — grantor is dirty
  text; dirty text needs LIKE, clean keys get joins):
    Land Bank 57,993 / Tax Foreclosure 33,011 / Other 5,774 (5.5%) /
    City Development 4,852 / Private Entity 1,348 / Government 1,272 /
    Mortgage Foreclosure 193 → **sums to 104,443 ✅**
- BRANCH ORDER IS LOAD-BEARING. `%P&DD%` must precede `%CITY%OF%DETROIT%`;
  `%TREAS%` must precede `%WAYNE%COUNTY%`; `%SHERIFF%` before generic county.
- GOTCHA THAT COST ROWS: `LIKE 'HUD %'` matched NOTHING (after TRIM the value is
  exactly `HUD`). Silently dropped 497 rows — and a bucket getting SMALLER is
  far harder to notice than an error. Fixed to `'HUD%'`.
- Also inert: `LIKE '%CO$'` — `$` is a regex anchor, LIKE only knows `%` and `_`.
- FINDING: private entities (churches, LLCs, a railroad) appear as GRANTORS in
  code 13. Reading: code 13 marks a public PROGRAM, not a public GRANTOR. That's
  a development signal hiding inside the government bucket.
- CAVEAT RAISED: parcel 06003365 (1566 RICHTON) appears as THREE "sales" —
  Treasurer → MI Land Bank → Detroit Land Bank → nonprofit. Not three market
  events; one chain of custody. Threatened the headline. → answered 8/20.
## Session update (Thu 8/20/2026) — CHAIN-OF-CUSTODY QUANTIFIED ✅
 
- Built `sql/06_profile_parcel_id_duplicates.sql`. Closes file 05's open
  question 2 (the Richton caveat).
- **RESULT — the headline SURVIVES and STRENGTHENS:**
    Government (13):  104,443 rows / 86,624 parcels = 1.21 rows/parcel
    Arms-length (03):  96,752 rows / 66,461 parcels = 1.46 rows/parcel
  Arms-length is the MORE duplicated side, so deduplicating both sides WIDENED
  the ratio from 1.08x (raw rows) to **1.30x (distinct parcels)**.
- INTERPRETATION — same arithmetic, opposite meanings. Repeat arms-length sales
  = a house changing hands over time = a functioning market. Repeat government
  transfers = one property passed between agencies. Only the second is
  double-counting. The 8/15 caveat assumed repetition was a defect; it's only a
  defect on one side.
- METHOD LESSON — the near-miss was concluding the thesis reversed by comparing
  86,624 *deduplicated* government parcels against 96,752 *raw* arms-length
  rows. Same error as the original, opposite direction. **Both sides must be
  measured at the same grain before either number means anything.**
- SQL GOTCHA — `RTRIM`'s second argument is a CHARACTER SET, not a length.
  `RTRIM(parcel_id, '.')` peels periods; `RTRIM(parcel_id, 1)` fails (no
  `rtrim(varchar, integer)` overload). Safe on rows without a period.
- Also: can't mix a bare column with `COUNT(*)` without `GROUP BY`, and `LIMIT`
  won't rescue it — LIMIT trims AFTER aggregation.
- DATA QUALITY — 15 rows have a NULL parcel_id. Visible to `COUNT(*)`, invisible
  to `COUNT(DISTINCT)`. Slightly understates the true ratio. Handle in staging
  with the 15 blank term_of_sale rows and 25 `grantor = '0'` rows.
- Duplication tail reaches **7 hops** on a single parcel.
- **BIG ONE PARKED:** 66,461 parcels have EVER had an arms-length sale, against
  377,863 parcels in `raw.parcels` — **under 18% of Detroit property has ever
  transacted on the open market.** Unfiltered by date, so directional only.
  Scope to 2017+ and cut by neighborhood before claiming it. This may be the
  Neighborhood Health Index headline.
- SCOPE CAVEAT — both queries unfiltered by date; locked window is 2017→present.
### Next session
1. **Shape of the duplication**, not just volume. 1.21 could be near-universal
   double-counting or a heavy 5-7 hop tail. Per-parcel `COUNT(*)` wrapped in an
   outer frequency count. Matters for the Land Bank split — if many DLBA rows
   are mid-chain legs rather than terminal dispositions, the grantee
   classification has to account for it.
2. **Split the Land Bank** (57,993 rows, the last big undecomposed blob).
   Grantor = channel; GRANTEE = outcome. DLBA → individual = side-lot giveaway
   (DISTRESS); DLBA → LLC / INC / nonprofit developer = redevelopment (GROWTH).
   Corporate-suffix pattern from 05 §3 transfers directly. Watch branch order.
   Validate channels sum to 57,993.
3. Decide: fold Mortgage Foreclosure (193) into Tax Foreclosure, or keep
   separate? **Outstanding since 8/15 — just make the call.**
4. Cast `sale_date` text → date, then re-run file 06 §2 scoped to 2017+.
5. THEN the composition query (per neighborhood, one branch per code family).
   Deferred twice now.
### Housekeeping
- Portfolio site: Work section + intro copy shipped 8/17. About / Skills /
  Contact still placeholder. Diamond cursor still unresolved from July.
- Sporting KC Data Analyst posting (TeamWork Online, posted 8/17) — cover letter
  not started. Stretch role; the BIS event-data angle is the hook.

