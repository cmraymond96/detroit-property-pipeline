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

### Next session
1. Cast sale_date text -> date
2. Retention-rate-by-neighborhood check (the clustering diagnostic)
3. Then join sales to parcels and start the spatial work