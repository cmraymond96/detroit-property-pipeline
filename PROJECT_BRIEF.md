# Detroit Property Values & Neighborhood Change

### A data pipeline \+ spatial analysis · Case Study (Detroit \#1)

**Repo (suggested):** `detroit-property-pipeline` **Type:** End-to-end pipeline project — *ingest → warehouse → dbt models → spatial marts → maps* **Why this project:** Demonstrates data engineering (not just analysis), spatial SQL, dimensional modeling, and the mortgage/property domain — pointed straight at the Detroit fintech target list. Tells the crumble-and-rebuild story.

---

## The questions

**Primary:** How have residential property values shifted across Detroit neighborhoods since \~2014, and which areas recovered, stagnated, or declined?

**Secondary:** What distinguishes the neighborhoods that recovered? (proximity to downtown / Midtown / Corktown, blight removal & demolitions, new building permits, income and vacancy shifts)

---

## The payoff — an interactive Detroit map

The headline deliverable: a red→green choropleth of Detroit neighborhoods with a metric selector. Red \= decline, green \= gain. Two audiences, one map:

- **Investor lens:** where value is climbing — where to buy.  
- **First-home lens:** where value is affordable *and* trending up — where someone like me should look.

**Selectable metrics** (dropdown):

- Avg YoY sale-price change  
- Assessed home value  
- **Land value** ← distinctive: Detroit's assessor splits land from building value per parcel; few cities publish this cleanly, and it ties directly to Detroit's real land-value-tax debate  
- Population change  
- *(optional)* sales volume · vacancy · new-permit activity

**Tools:** Kepler.gl, or a Leaflet/Mapbox web map (the latter embeds on the portfolio site — the Google Maps itch, scratched).

**Honest framing:** the map answers *"where is value heading, and what's affordable"* — not *"best place to live."* Schools, safety, commute, and amenities aren't in this data. Naming that limit in the writeup reads as credibility, not weakness.

> The map is the **payoff**. The pipeline underneath (ingest → warehouse → dbt → spatial marts) is what makes this *data engineering*, not a viz. Build the pipe first.

---

## Decisions (locked)

- **Value metric:** **Assessed value** as the spine (**land value \= headline metric** — it's locational, so it reads as neighborhood desirability). Sale price kept as a secondary cross-check. *Not versus — assessed is the primary, sales validate it.*  
- **Time window:** 2014 \= narrative frame ("since the bankruptcy era"), but **2017 → present \= the clean assessed-value comparison window.** Pre-2017 assessed values are documented as unreliable (state investigation \+ city audit couldn't support 2010–2016 values); the 2017 citywide reappraisal is a methodology break. *Open sub-choice: analyze 2017→present clean (recommended) vs. show full 2014→present with the 2017 break annotated.*  
- **Geographic unit:** **Detroit neighborhoods** (historic communities — the headline story). Note: Census data comes at tract level → needs a tract→neighborhood crosswalk if layered in.  
- **Warehouse:** **Postgres \+ PostGIS.** Spatial is the differentiator, PostGIS is the industry standard, pairs with dbt, and models port to a cloud warehouse later for the résumé keyword.

>   
> **Data caveat to document in the writeup:** Detroit's first parcel-by-parcel reappraisal in \~60 years was initiated in 2014 and took effect in 2017; pre-2017 assessments were subject to a state-investigated over-assessment problem. Treating this as an explicit analytical decision (why the clean window starts 2017\) is a credibility win, not a weakness.

---

## Data sources (all public, confirmed)

| Source | What you get |
| :---- | :---- |
| **Detroit Open Data Portal** — Property Sales | Transaction prices over time (Assessor sales study) |
| **Detroit Open Data Portal** — Parcels (Current) | Assessed values (**land \+ building split**), last sale, physical attributes, **geometry** |
| **Detroit Open Data Portal** — Blight Violations / Demolitions / Permits | Explanatory features for neighborhood change |
| **Detroit Open Data Portal** — Neighborhood boundaries | Spatial join target |
| **U.S. Census / ACS API** | Median income, homeownership, vacancy, population by tract |
| **Zillow ZHVI** *(optional)* | Clean neighborhood home-value time series \+ cross-validation |

Portal serves data via ArcGIS/Socrata APIs and GeoJSON/CSV downloads — pullable with Python `requests` / `geopandas`.

---

## Architecture

  Detroit Open Data API ─┐

  Census / ACS API       ├─►  \[ Python ingest \]  ─►  raw schema  (Postgres/PostGIS)

  Zillow CSV (optional) ─┘                                  │

                                                            ▼

                                              \[ dbt \]  staging → dimensional models

                                                            │

                                        fact\_sales · dim\_parcel · dim\_neighborhood · dim\_date

                                                            │

                                              \[ PostGIS spatial joins \]

                                                            │

                                                 neighborhood-year value marts

                                                            │

                                          \[ GeoPandas / Folium / Kepler \+ plots \]

                                                            ▼

                                             maps \+ trend charts \+ written narrative

## Stack → what it teaches

- **Python** (ingestion) — you have this  
- **PostgreSQL \+ PostGIS** — spatial SQL, your differentiator *(learning goal)*  
- **dbt** — modular SQL, tests, transforms *(learning goal)*  
- **Dimensional modeling** — star schema: `fact_sales`, `dim_*` *(learning goal)*  
- **GeoPandas / Folium / Kepler.gl** — maps  
- **Git/GitHub** — you have this  
- **Airflow** — *stretch / Phase 2 only*

---

## Build sequence (MVP first — don't boil the ocean)

**MVP \= Steps 1–3. That alone is a complete, portfolio-worthy pipeline.**

0. **Setup** — new repo, env (dbt \+ Postgres/PostGIS \+ geopandas), `.gitignore`, README skeleton  
1. **Prove the pipe** — ingest *one* dataset (Property Sales) end-to-end into Postgres  
2. **First spatial win** — add Parcels (with geometry), spatial-join sales to neighborhoods  
3. **Model it** — dbt: staging → star schema → `neighborhood_year_values` mart  
4. **Enrich** — add Census \+ blight/demolition/permit features  
5. **Analyze & map** — the selectable red→green neighborhood choropleth (metric dropdown), trend charts, written findings  
6. **Ship** — README as a DE project (architecture, stack, how-to-run) \+ portfolio site card

**Stretch:** orchestrate with Airflow · target a cloud warehouse · small interactive map embedded on the portfolio site.

---

## Deliverables

- Working pipeline (ingest → warehouse → dbt → spatial marts)  
- Interactive metric-selectable map (Kepler.gl / Leaflet-Mapbox), red→green by neighborhood  
- Analysis notebook / writeup with maps \+ narrative  
- README framing it as data engineering (architecture diagram \+ run instructions)  
- Portfolio site case study card  
- `NEXT_SESSION.md` warm-start file (living task queue)

---

## Scope discipline

Steps 1–3 \= done-and-shippable. Steps 4–5 \= rich. Everything else \= stretch, only if time allows in Stage 1 (Aug–Sep). One real end-to-end build beats five half-finished notebooks.  
