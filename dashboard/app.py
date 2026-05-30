"""
Cricket Analytics Dashboard — Flask app
Connects to the PostgreSQL DW and serves analytics via a web UI.
"""

import os
import psycopg2
import psycopg2.extras
from flask import Flask, render_template, request, jsonify
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

DB = dict(
    host=os.getenv("DB_HOST", "localhost"),
    port=os.getenv("DB_PORT", 5432),
    dbname=os.getenv("DB_NAME", "cricket_dw"),
    user=os.getenv("DB_USER", "postgres"),
    password=os.getenv("DB_PASSWORD", ""),
)


def query(sql, params=None):
    with psycopg2.connect(**DB) as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            return cur.fetchall()


# ── Routes ────────────────────────────────────────────────────

@app.route("/")
def index():
    seasons = query(
        "SELECT DISTINCT season FROM cricket_dw.dim_match "
        "ORDER BY season DESC"
    )
    return render_template("dashboard.html",
                           seasons=[r["season"] for r in seasons])


@app.route("/api/batting-leaderboard")
def batting_leaderboard():
    season = request.args.get("season", type=int)
    rows = query("""
        SELECT player_name, season, innings, runs, average,
               strike_rate, sixes, fours, season_rank
        FROM cricket_dw.vw_batting_leaderboard
        WHERE (%s IS NULL OR season = %s)
          AND season_rank <= 15
        ORDER BY season DESC, season_rank
    """, (season, season))
    return jsonify([dict(r) for r in rows])


@app.route("/api/bowling-leaderboard")
def bowling_leaderboard():
    season = request.args.get("season", type=int)
    rows = query("""
        SELECT player_name, season, matches, wickets,
               economy, bowling_average, season_rank
        FROM cricket_dw.vw_bowling_leaderboard
        WHERE (%s IS NULL OR season = %s)
          AND season_rank <= 15
        ORDER BY season DESC, season_rank
    """, (season, season))
    return jsonify([dict(r) for r in rows])


@app.route("/api/team-performance")
def team_performance():
    season = request.args.get("season", type=int)
    rows = query("""
        SELECT team_name, season, matches_played, wins, losses, win_pct
        FROM cricket_dw.vw_team_performance
        WHERE (%s IS NULL OR season = %s)
        ORDER BY season DESC, win_pct DESC
    """, (season, season))
    return jsonify([dict(r) for r in rows])


@app.route("/api/venue-report")
def venue_report():
    season = request.args.get("season", type=int)
    rows = query("""
        SELECT dv.venue_name, dv.city,
               COUNT(DISTINCT dm.match_key)         AS total_matches,
               ROUND(AVG(fmi.total_runs), 1)        AS avg_score,
               ROUND(AVG(fmi.run_rate), 2)          AS avg_rr,
               ROUND(AVG(fmi.powerplay_runs), 1)    AS avg_pp
        FROM cricket_dw.fact_match_innings fmi
        JOIN cricket_dw.dim_match dm  ON fmi.match_key  = dm.match_key
        JOIN cricket_dw.dim_venue dv  ON dm.venue_key   = dv.venue_key
        WHERE (%s IS NULL OR dm.season = %s)
        GROUP BY dv.venue_name, dv.city
        HAVING COUNT(DISTINCT dm.match_key) >= 2
        ORDER BY avg_score DESC
        LIMIT 15
    """, (season, season))
    return jsonify([dict(r) for r in rows])


@app.route("/api/player-form")
def player_form():
    season = request.args.get("season", type=int)
    rows = query("""
        WITH match_scores AS (
            SELECT fd.batter_key, fd.match_key,
                   dd.full_date, dm.season,
                   SUM(fd.batsman_runs)              AS match_runs,
                   ROW_NUMBER() OVER (
                       PARTITION BY fd.batter_key
                       ORDER BY dd.full_date DESC
                   )                                 AS recency_rank
            FROM cricket_dw.fact_deliveries fd
            JOIN cricket_dw.dim_date dd  ON fd.date_key  = dd.date_key
            JOIN cricket_dw.dim_match dm ON fd.match_key = dm.match_key
            WHERE (%s IS NULL OR dm.season = %s)
            GROUP BY fd.batter_key, fd.match_key, dd.full_date, dm.season
        ),
        recent AS (
            SELECT batter_key, ROUND(AVG(match_runs),2) AS avg_last_5
            FROM match_scores WHERE recency_rank <= 5
            GROUP BY batter_key
        ),
        career AS (
            SELECT batter_key, ROUND(AVG(match_runs),2) AS career_avg
            FROM match_scores GROUP BY batter_key
        )
        SELECT dp.player_name,
               r.avg_last_5, c.career_avg,
               ROUND(r.avg_last_5 - c.career_avg, 2) AS form_delta
        FROM recent r
        JOIN career     c  ON r.batter_key = c.batter_key
        JOIN cricket_dw.dim_player dp ON r.batter_key = dp.player_key
        WHERE dp.is_current = TRUE
          AND c.career_avg > 5
        ORDER BY form_delta DESC
        LIMIT 20
    """, (season, season))
    return jsonify([dict(r) for r in rows])


@app.route("/api/toss-analysis")
def toss_analysis():
    season = request.args.get("season", type=int)
    rows = query("""
        SELECT dv.venue_name, dm.toss_decision,
               COUNT(*)                             AS total,
               SUM(CASE WHEN dm.toss_winner_key = dm.winner_key
                        THEN 1 ELSE 0 END)         AS toss_wins,
               ROUND(100.0 * SUM(
                   CASE WHEN dm.toss_winner_key = dm.winner_key
                        THEN 1 ELSE 0 END
               ) / NULLIF(COUNT(*),0), 1)          AS win_pct
        FROM cricket_dw.dim_match dm
        JOIN cricket_dw.dim_venue dv ON dm.venue_key = dv.venue_key
        WHERE dm.winner_key IS NOT NULL
          AND (%s IS NULL OR dm.season = %s)
        GROUP BY dv.venue_name, dm.toss_decision
        HAVING COUNT(*) >= 3
        ORDER BY win_pct DESC
        LIMIT 20
    """, (season, season))
    return jsonify([dict(r) for r in rows])


if __name__ == "__main__":
    app.run(debug=True, port=5000)