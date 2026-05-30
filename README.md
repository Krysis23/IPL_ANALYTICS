# 🏏 Cricket Analytics Data Warehouse

A production-style DW/BI project built on PostgreSQL — designed to showcase
advanced SQL, schema design, ETL pipelines, and BI dashboards.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Database | PostgreSQL 15+ |
| Schema | Star Schema (4 dims + 2 facts) |
| ETL | Python (pandas + psycopg2) |
| Dashboard | Flask + Chart.js |
| BI Tool | Metabase / Tableau (optional) |

---

## Folder Structure

```
cricket_dw/
├── data/                        ← Drop Kaggle CSVs here
│   ├── matches.csv
│   └── deliveries.csv
│
├── etl/
│   └── load_data.py             ← Full ETL pipeline
│
├── sql/
│   ├── schema/
│   │   ├── 01_create_dims.sql   ← dim_date, team, venue, player, match
│   │   └── 02_create_facts.sql  ← fact_deliveries, fact_match_innings + indexes
│   ├── stored_procs/
│   │   └── sp_player_and_match.sql  ← sp_player_scorecard, sp_match_summary
│   └── analytics/
│       ├── resume_queries.sql   ← 5 advanced showcase queries
│       └── views.sql            ← BI-ready views
│
├── dashboard/
│   ├── app.py                   ← Flask API + routes
│   └── templates/
│       └── dashboard.html       ← Full analytics UI
│
├── requirements.txt
├── .env.example
└── README.md
```

---

## Setup — Step by Step

### 1. Get the data

Download from Kaggle (free):
https://www.kaggle.com/datasets/patrickb1912/ipl-complete-dataset-20082020

Place `matches.csv` and `deliveries.csv` inside the `data/` folder.

### 2. Create the database

```bash
psql -U postgres
CREATE DATABASE cricket_dw;
\q
```

### 3. Configure environment

```bash
cp .env.example .env
# Edit .env with your PostgreSQL credentials
```

### 4. Install Python dependencies

```bash
python -m venv venv
source venv/bin/activate      # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 5. Run the ETL

```bash
python etl/load_data.py
```

This will:
- Create schema + all tables + indexes
- Load dim_date, dim_venue, dim_team, dim_player, dim_match
- Load fact_deliveries (~185,000 rows)
- Refresh fact_match_innings aggregation

### 6. Launch the dashboard

```bash
cd dashboard
python app.py
```

Open http://localhost:5000

---

## What's Inside

### Star Schema

```
dim_date ──────────────┐
dim_player (batter) ───┤
dim_player (bowler) ───┤──► fact_deliveries (grain: 1 row per ball)
dim_team (batting) ────┤
dim_team (bowling) ────┤
dim_match ─────────────┘
dim_venue ─────────────┘

dim_match ─────────────► fact_match_innings (grain: 1 row per innings)
```

### Key SQL Skills Demonstrated

| Query | Technique |
|---|---|
| Batting leaderboard | RANK(), SUM OVER, running totals |
| Bowling by phase | FILTER clause, conditional aggregation |
| Toss win analysis | Multi-level GROUP BY, percentage calc |
| Player form index | CTE, self-join, ROW_NUMBER |
| Venue pitch report | Multi-join aggregation, CASE labels |

### Stored Procedures

```sql
-- Full player scorecard
CALL cricket_dw.sp_player_scorecard('Virat Kohli', 2016);

-- Full match summary
CALL cricket_dw.sp_match_summary(335982);

-- Refresh innings aggregate table
CALL cricket_dw.sp_refresh_innings_agg();
```

### BI Views

```sql
SELECT * FROM cricket_dw.vw_batting_leaderboard WHERE season = 2023;
SELECT * FROM cricket_dw.vw_bowling_leaderboard WHERE season = 2023;
SELECT * FROM cricket_dw.vw_team_performance WHERE season = 2023;
SELECT * FROM cricket_dw.vw_head_to_head;
```

---

## Dashboard Tabs

| Tab | What it shows |
|---|---|
| Batting | Top scorers, avg, SR, 4s/6s |
| Bowling | Top wicket takers, economy by phase |
| Teams | Win % per season, league table |
| Venues | Pitch report, avg scores, RR |
| Player Form | Last 5 vs career average |
| Toss Analysis | Toss decision → win % by venue |

---

## Resume Talking Points

- Designed a **star schema** with SCD Type 2 support for player/team dimensions
- Built a **Python ETL pipeline** processing 185,000+ delivery-level records
- Wrote **window functions** (RANK, SUM OVER, ROW_NUMBER) for leaderboards and form tracking
- Used **FILTER clause** for phase-based bowling analysis (Powerplay / Middle / Death)
- Created **stored procedures** for reusable scorecards and data refresh
- Built a **Flask + Chart.js dashboard** with live SQL-backed API endpoints
- Implemented **covering indexes** for query optimization on the deliveries fact table
- Modelled a **generated column** (`phase`) for computed over phases
