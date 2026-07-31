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
