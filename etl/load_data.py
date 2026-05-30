"""
ETL Pipeline — Cricket Analytics DW
Loads Kaggle IPL CSVs into the PostgreSQL star schema.

Data source: https://www.kaggle.com/datasets/patrickb1912/ipl-complete-dataset-20082020
Download and place in the /data folder:
  - matches.csv
  - deliveries.csv
"""

import os
import psycopg2
import pandas as pd
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

DB = dict(
    host=os.getenv("DB_HOST", "localhost"),
    port=os.getenv("DB_PORT", 5432),
    dbname=os.getenv("DB_NAME", "cricket_dw"),
    user=os.getenv("DB_USER", "postgres"),
    password=os.getenv("DB_PASSWORD", ""),
)

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")


# ── helpers ──────────────────────────────────────────────────

def get_conn():
    return psycopg2.connect(**DB)


def execute_sql_file(conn, path):
    with open(path) as f:
        sql = f.read()
    with conn.cursor() as cur:
        cur.execute(sql)
    conn.commit()
    print(f"  ✔ executed {os.path.basename(path)}")


def upsert_one(cur, table, lookup_col, lookup_val, insert_data: dict) -> int:
    """Insert if not exists, return the key."""
    cur.execute(
        f"SELECT {table.split('.')[-1].replace('dim_','')}_key "
        f"FROM {table} WHERE {lookup_col} = %s LIMIT 1",
        (lookup_val,)
    )
    row = cur.fetchone()
    if row:
        return row[0]
    cols = ", ".join(insert_data.keys())
    vals = ", ".join(["%s"] * len(insert_data))
    cur.execute(
        f"INSERT INTO {table} ({cols}) VALUES ({vals}) RETURNING "
        f"{table.split('.')[-1].replace('dim_','')}_key",
        list(insert_data.values())
    )
    return cur.fetchone()[0]


# ── stage 1: dim_date ─────────────────────────────────────────

def load_dim_date(conn, dates):
    print("Loading dim_date...")
    with conn.cursor() as cur:
        for d in dates:
            dt = pd.to_datetime(d)
            cur.execute("""
                INSERT INTO cricket_dw.dim_date
                    (full_date, day_of_week, day_name, day_of_month,
                     month_num, month_name, quarter, year, ipl_season, is_weekend)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (full_date) DO NOTHING
            """, (
                dt.date(), dt.dayofweek, dt.day_name(),
                dt.day, dt.month, dt.month_name(),
                dt.quarter, dt.year, dt.year,
                dt.dayofweek >= 5
            ))
    conn.commit()
    print(f"  ✔ {len(dates)} dates loaded")


# ── stage 2: dim_venue ────────────────────────────────────────

def load_dim_venue(conn, df):
    print("Loading dim_venue...")
    venues = df[["venue", "city"]].drop_duplicates()
    with conn.cursor() as cur:
        for _, row in venues.iterrows():
            cur.execute("""
                INSERT INTO cricket_dw.dim_venue (venue_name, city)
                VALUES (%s, %s)
                ON CONFLICT DO NOTHING
            """, (row["venue"], row.get("city", None)))
    conn.commit()
    print(f"  ✔ {len(venues)} venues loaded")


# ── stage 3: dim_team ─────────────────────────────────────────

def load_dim_team(conn, df):
    print("Loading dim_team...")
    teams = set(df["team1"].tolist() + df["team2"].tolist())
    with conn.cursor() as cur:
        for team in teams:
            cur.execute("""
                INSERT INTO cricket_dw.dim_team (team_name)
                VALUES (%s)
                ON CONFLICT (team_name) DO NOTHING
            """, (team,))
    conn.commit()
    print(f"  ✔ {len(teams)} teams loaded")


# ── stage 4: dim_player ───────────────────────────────────────

def load_dim_player(conn, deliveries_df):
    print("Loading dim_player...")
    players = set(
        deliveries_df["batter"].tolist() +
        deliveries_df["bowler"].tolist() +
        deliveries_df["non_striker"].tolist()
    )
    with conn.cursor() as cur:
        for player in players:
            if pd.isna(player) or not player:
                continue
            cur.execute("""
                INSERT INTO cricket_dw.dim_player (player_name)
                VALUES (%s)
                ON CONFLICT DO NOTHING
            """, (player,))
    conn.commit()
    print(f"  ✔ {len(players)} players loaded")


# ── stage 5: dim_match ────────────────────────────────────────

def load_dim_match(conn, matches_df):
    print("Loading dim_match...")
    with conn.cursor() as cur:

        def get_key(table, col, val):
            if pd.isna(val) or not val:
                return None
            cur.execute(
                f"SELECT {col} FROM cricket_dw.{table} "
                f"WHERE {'venue_name' if 'venue' in table else 'team_name' if 'team' in table else 'player_name' if 'player' in table else 'full_date'} = %s LIMIT 1",
                (val,)
            )
            row = cur.fetchone()
            return row[0] if row else None

        def parse_season(val):
            """Convert '2007/08' or '2008' or 2008 → int year (e.g. 2007)."""
            if pd.isna(val):
                return None
            s = str(val).strip()
            # "2007/08" → take the first part
            return int(s.split("/")[0])

        for _, row in matches_df.iterrows():
            date_key    = get_key("dim_date",   "date_key",   row.get("date"))
            venue_key   = get_key("dim_venue",  "venue_key",  row.get("venue"))
            team1_key   = get_key("dim_team",   "team_key",   row.get("team1"))
            team2_key   = get_key("dim_team",   "team_key",   row.get("team2"))
            toss_key    = get_key("dim_team",   "team_key",   row.get("toss_winner"))
            winner_key  = get_key("dim_team",   "team_key",   row.get("winner"))
            pom_key     = get_key("dim_player", "player_key", row.get("player_of_match"))

            cur.execute("""
                INSERT INTO cricket_dw.dim_match (
                    match_id, date_key, season,
                    venue_key, team1_key, team2_key,
                    toss_winner_key, toss_decision,
                    winner_key, win_by_runs, win_by_wickets,
                    player_of_match_key
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (match_id) DO NOTHING
            """, (
                row.get("id") or row.get("match_id"),
                date_key, parse_season(row.get("season")),
                venue_key, team1_key, team2_key,
                toss_key, row.get("toss_decision"),
                winner_key,
                row.get("win_by_runs") if not pd.isna(row.get("win_by_runs", float("nan"))) else 0,
                row.get("win_by_wickets") if not pd.isna(row.get("win_by_wickets", float("nan"))) else 0,
                pom_key
            ))
    conn.commit()
    print(f"  ✔ {len(matches_df)} matches loaded")


# ── stage 6: fact_deliveries ─────────────────────────────────

def load_fact_deliveries(conn, deliveries_df, batch_size=5000):
    print("Loading fact_deliveries (this may take a minute)...")
    with conn.cursor() as cur:
        # Build lookup caches for speed
        cur.execute("SELECT player_name, player_key FROM cricket_dw.dim_player")
        player_map = {r[0]: r[1] for r in cur.fetchall()}

        cur.execute("SELECT team_name, team_key FROM cricket_dw.dim_team")
        team_map = {r[0]: r[1] for r in cur.fetchall()}

        cur.execute("SELECT match_id, match_key, date_key, venue_key FROM cricket_dw.dim_match")
        match_map = {r[0]: (r[1], r[2], r[3]) for r in cur.fetchall()}

        rows = []
        for _, d in deliveries_df.iterrows():
            mid = d.get("match_id") or d.get("id")
            if mid not in match_map:
                continue
            match_key, date_key, venue_key = match_map[mid]

            rows.append((
                match_key, date_key,
                d.get("inning", 1),
                d.get("over", 0),
                d.get("ball", 1),
                player_map.get(d.get("batter") or d.get("batsman")),
                player_map.get(d.get("bowler")),
                player_map.get(d.get("non_striker")),
                team_map.get(d.get("batting_team")),
                team_map.get(d.get("bowling_team")),
                venue_key,
                int(d.get("batsman_runs", d.get("batter_runs", 0)) or 0),
                int(d.get("extra_runs", d.get("extras", 0)) or 0),
                int(d.get("total_runs", 0) or 0),
                bool(d.get("wides", 0) or d.get("wide_runs", 0)),
                bool(d.get("noballs", 0) or d.get("noball_runs", 0)),
                bool(d.get("byes", 0) or d.get("bye_runs", 0)),
                bool(d.get("legbyes", 0) or d.get("legbye_runs", 0)),
                int(d.get("batsman_runs", d.get("batter_runs", 0)) or 0) == 4,
                int(d.get("batsman_runs", d.get("batter_runs", 0)) or 0) == 6,
                bool(d.get("is_wicket", 0) or d.get("player_dismissed")),
                d.get("dismissal_kind") or None,
                player_map.get(d.get("player_dismissed")),
                player_map.get(d.get("fielder")),
            ))

            if len(rows) >= batch_size:
                _insert_delivery_batch(cur, rows)
                rows = []

        if rows:
            _insert_delivery_batch(cur, rows)

    conn.commit()
    print(f"  ✔ {len(deliveries_df)} deliveries loaded")


def _insert_delivery_batch(cur, rows):
    cur.executemany("""
        INSERT INTO cricket_dw.fact_deliveries (
            match_key, date_key, inning, over_num, ball_num,
            batter_key, bowler_key, non_striker_key,
            batting_team_key, bowling_team_key, venue_key,
            batsman_runs, extra_runs, total_runs,
            is_wide, is_no_ball, is_bye, is_leg_bye,
            is_boundary_four, is_boundary_six,
            is_wicket, dismissal_kind,
            player_dismissed_key, fielder_key
        ) VALUES (
            %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
            %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
        )
    """, rows)


# ── main ──────────────────────────────────────────────────────

def run_etl():
    print("\n🏏 Cricket Analytics ETL starting...\n")
    t0 = datetime.now()

    # 1. Load CSVs
    matches_path    = os.path.join(DATA_DIR, "matches.csv")
    deliveries_path = os.path.join(DATA_DIR, "deliveries.csv")

    if not os.path.exists(matches_path):
        raise FileNotFoundError(
            f"Missing {matches_path}. "
            "Download from https://www.kaggle.com/datasets/patrickb1912/ipl-complete-dataset-20082020"
        )

    matches_df    = pd.read_csv(matches_path)
    deliveries_df = pd.read_csv(deliveries_path)
    print(f"  Loaded {len(matches_df)} matches, {len(deliveries_df)} deliveries from CSV\n")

    conn = get_conn()

    base = os.path.join(os.path.dirname(__file__), "..", "sql")

    # 2. Run schema SQL
    execute_sql_file(conn, os.path.join(base, "schema", "01_create_dims.sql"))
    execute_sql_file(conn, os.path.join(base, "schema", "02_create_facts.sql"))

    # 3. Load stored procedures + views BEFORE calling them
    execute_sql_file(conn, os.path.join(base, "stored_procs", "sp_player_and_match.sql"))
    execute_sql_file(conn, os.path.join(base, "analytics", "views.sql"))

    # 4. Load dimensions in order
    load_dim_date(conn, matches_df["date"].dropna().unique())
    load_dim_venue(conn, matches_df)
    load_dim_team(conn, matches_df)
    load_dim_player(conn, deliveries_df)
    load_dim_match(conn, matches_df)

    # 5. Load fact table
    load_fact_deliveries(conn, deliveries_df)

    # 6. Refresh innings aggregation
    print("Refreshing innings aggregates...")
    with conn.cursor() as cur:
        cur.execute("CALL cricket_dw.sp_refresh_innings_agg()")
    conn.commit()

    conn.close()
    elapsed = (datetime.now() - t0).seconds
    print(f"\n✅ ETL complete in {elapsed}s\n")


if __name__ == "__main__":
    run_etl()