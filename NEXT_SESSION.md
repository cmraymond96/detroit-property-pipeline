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
