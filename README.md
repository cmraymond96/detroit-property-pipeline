# Detroit Property Values & Neighborhood Change

An end-to-end **data pipeline** analyzing how residential property values — especially **land value** — have shifted across Detroit neighborhoods since the city's bankruptcy era, surfaced as an interactive **red → green neighborhood map**.

**Status:** 🚧 Scoping complete — pipeline build in progress

---

## Why this project

A data-engineering portfolio piece demonstrating spatial SQL, dbt, dimensional modeling, and the mortgage/property domain. Not just analysis — a real pipeline that ingests, models, and serves data.

## Architecture

```
Detroit Open Data API ─┐
Census / ACS API       ├─► [Python ingest] ─► raw (Postgres/PostGIS)
Zillow (optional)     ─┘                            │
                                    [dbt] staging → dimensional models
                                                    │
                                     [PostGIS spatial joins]
                                                    │
                                       neighborhood-year value marts
                                                    │
                                  [Kepler.gl / Leaflet map + charts]
```

## Stack

- **Python** — ingestion
- **Postgres + PostGIS** — spatial warehouse
- **dbt** — transforms → dimensional models
- **GeoPandas / Kepler.gl / Leaflet** — maps
- **Git/GitHub** — version control

## Data sources

- Detroit Open Data Portal — Property Sales, Parcels (assessed values + geometry), Blight/Demolitions/Permits, Neighborhood boundaries
- U.S. Census / ACS API — income, vacancy, population by tract
- Zillow ZHVI *(optional cross-check)*

## How to run

_TBD — pipeline in progress. See `NEXT_SESSION.md`._

## Project docs

- `PROJECT_BRIEF.md` — full scope, locked decisions, build sequence
- `NEXT_SESSION.md` — warm-start note / task queue
