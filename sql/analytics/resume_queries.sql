-- ============================================================
-- ANALYTICS QUERIES — Cricket Analytics DW
-- These are the resume-worthy SQL showcase queries
-- ============================================================
SET search_path TO cricket_dw;


-- ────────────────────────────────────────────────────────────
-- Q1: Batting Leaderboard with running totals
--     Window functions: RANK, SUM OVER, running cumulative
-- ────────────────────────────────────────────────────────────
WITH batting_stats AS (
    SELECT
        dp.player_name,
        dm.season,
        COUNT(DISTINCT fd.match_key)                            AS innings,
        SUM(fd.batsman_runs)                                    AS runs,
        MAX(fd.batsman_runs)                                    AS high_score,
        SUM(fd.is_boundary_four::INT)                          AS fours,
        SUM(fd.is_boundary_six::INT)                           AS sixes,
        ROUND(
            100.0 * SUM(fd.batsman_runs)
            / NULLIF(COUNT(*), 0), 2
        )                                                       AS strike_rate,
        ROUND(
            SUM(fd.batsman_runs)::NUMERIC
            / NULLIF(SUM(fd.is_wicket::INT), 0), 2
        )                                                       AS avg_runs
    FROM fact_deliveries fd
    JOIN dim_player dp ON fd.batter_key = dp.player_key
    JOIN dim_match  dm ON fd.match_key  = dm.match_key
    WHERE dp.is_current = TRUE
    GROUP BY dp.player_name, dm.season
),
ranked AS (
    SELECT *,
        RANK() OVER (PARTITION BY season ORDER BY runs DESC)    AS season_rank,
        SUM(runs) OVER (
            PARTITION BY player_name
            ORDER BY season
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                                       AS career_runs_to_date
    FROM batting_stats
)
SELECT *
FROM ranked
WHERE season_rank <= 10
ORDER BY season DESC, season_rank;


-- ────────────────────────────────────────────────────────────
-- Q2: Bowling Economy by Phase — Powerplay vs Death
--     Conditional aggregation + FILTER clause
-- ────────────────────────────────────────────────────────────
SELECT
    dp.player_name,
    dm.season,
    COUNT(DISTINCT fd.match_key)                                AS matches,
    -- Overall
    SUM(fd.is_wicket::INT)                                     AS wickets,
    ROUND(6.0 * SUM(fd.total_runs) / NULLIF(COUNT(*),0), 2)   AS overall_economy,
    -- Powerplay
    ROUND(6.0 *
        SUM(fd.total_runs)    FILTER (WHERE fd.phase = 'Powerplay')
        / NULLIF(COUNT(*)     FILTER (WHERE fd.phase = 'Powerplay'), 0)
    , 2)                                                        AS pp_economy,
    -- Death overs
    ROUND(6.0 *
        SUM(fd.total_runs)    FILTER (WHERE fd.phase = 'Death')
        / NULLIF(COUNT(*)     FILTER (WHERE fd.phase = 'Death'), 0)
    , 2)                                                        AS death_economy,
    -- Strike rate
    ROUND(
        COUNT(*)::NUMERIC
        / NULLIF(SUM(fd.is_wicket::INT), 0), 2
    )                                                           AS bowling_sr
FROM fact_deliveries fd
JOIN dim_player dp ON fd.bowler_key = dp.player_key
JOIN dim_match  dm ON fd.match_key  = dm.match_key
WHERE fd.is_wide = FALSE
  AND fd.is_no_ball = FALSE
  AND dp.is_current = TRUE
GROUP BY dp.player_name, dm.season
HAVING COUNT(*) >= 120   -- min 20 overs bowled in season
ORDER BY overall_economy ASC
LIMIT 20;


-- ────────────────────────────────────────────────────────────
-- Q3: Win Probability by Toss Decision per Venue
--     Conditional aggregation + percentage calc
-- ────────────────────────────────────────────────────────────
SELECT
    dv.venue_name,
    dv.city,
    dm.toss_decision,
    COUNT(*)                                                    AS total_matches,
    SUM(
        CASE WHEN dm.toss_winner_key = dm.winner_key THEN 1 ELSE 0 END
    )                                                           AS toss_wins,
    ROUND(
        100.0 * SUM(
            CASE WHEN dm.toss_winner_key = dm.winner_key THEN 1 ELSE 0 END
        ) / COUNT(*), 1
    )                                                           AS win_pct_after_toss,
    -- avg winning margin
    ROUND(AVG(dm.win_by_runs) FILTER (WHERE dm.win_by_runs > 0), 1) AS avg_win_by_runs,
    ROUND(AVG(dm.win_by_wickets) FILTER (WHERE dm.win_by_wickets > 0), 1) AS avg_win_by_wickets
FROM dim_match dm
JOIN dim_venue dv ON dm.venue_key = dv.venue_key
WHERE dm.winner_key IS NOT NULL
GROUP BY dv.venue_name, dv.city, dm.toss_decision
HAVING COUNT(*) >= 10
ORDER BY win_pct_after_toss DESC;


-- ────────────────────────────────────────────────────────────
-- Q4: Player Form Index — Last 5 matches vs Career Average
--     Self-join, CTE, LAG, row_number
-- ────────────────────────────────────────────────────────────
WITH match_scores AS (
    SELECT
        fd.batter_key,
        fd.match_key,
        dm.season,
        dd.full_date,
        SUM(fd.batsman_runs)                                    AS match_runs,
        ROUND(
            100.0 * SUM(fd.batsman_runs) / NULLIF(COUNT(*), 0), 2
        )                                                       AS match_sr,
        ROW_NUMBER() OVER (
            PARTITION BY fd.batter_key
            ORDER BY dd.full_date DESC
        )                                                       AS recency_rank
    FROM fact_deliveries fd
    JOIN dim_match dm ON fd.match_key = dm.match_key
    JOIN dim_date  dd ON fd.date_key  = dd.date_key
    GROUP BY fd.batter_key, fd.match_key, dm.season, dd.full_date
),
recent_5 AS (
    SELECT
        batter_key,
        ROUND(AVG(match_runs), 2)   AS avg_last_5,
        ROUND(AVG(match_sr), 2)     AS sr_last_5
    FROM match_scores
    WHERE recency_rank <= 5
    GROUP BY batter_key
),
career AS (
    SELECT
        batter_key,
        ROUND(AVG(match_runs), 2)   AS career_avg,
        ROUND(AVG(match_sr), 2)     AS career_sr
    FROM match_scores
    GROUP BY batter_key
)
SELECT
    dp.player_name,
    r.avg_last_5,
    c.career_avg,
    ROUND(r.avg_last_5 - c.career_avg, 2)                      AS form_delta,
    r.sr_last_5,
    c.career_sr,
    CASE
        WHEN r.avg_last_5 > c.career_avg * 1.2 THEN '🔥 In Form'
        WHEN r.avg_last_5 < c.career_avg * 0.8 THEN '❄️  Out of Form'
        ELSE '➡️  Average'
    END                                                         AS form_status
FROM recent_5 r
JOIN career     c  ON r.batter_key  = c.batter_key
JOIN dim_player dp ON r.batter_key  = dp.player_key
WHERE dp.is_current = TRUE
ORDER BY form_delta DESC
LIMIT 20;


-- ────────────────────────────────────────────────────────────
-- Q5: Venue Pitch Report — Avg innings scores + pitch behaviour
--     Multi-level aggregation used in BI dashboard
-- ────────────────────────────────────────────────────────────
WITH venue_innings AS (
    SELECT
        fmi.venue_key,
        fmi.match_key,
        fmi.inning,
        fmi.total_runs,
        fmi.total_wickets,
        fmi.powerplay_runs,
        fmi.death_runs,
        fmi.run_rate
    FROM fact_match_innings fmi
),
venue_agg AS (
    SELECT
        venue_key,
        COUNT(DISTINCT match_key)                               AS total_matches,
        ROUND(AVG(total_runs) FILTER (WHERE inning=1), 1)      AS avg_1st_innings,
        ROUND(AVG(total_runs) FILTER (WHERE inning=2), 1)      AS avg_2nd_innings,
        ROUND(AVG(powerplay_runs), 1)                          AS avg_pp_runs,
        ROUND(AVG(death_runs), 1)                              AS avg_death_runs,
        ROUND(AVG(run_rate), 2)                                AS avg_run_rate,
        -- How often does team batting first win?
        SUM(CASE
            WHEN inning = 1 THEN 1 ELSE 0
        END)                                                    AS first_bat_matches
    FROM venue_innings
    GROUP BY venue_key
)
SELECT
    dv.venue_name,
    dv.city,
    va.total_matches,
    va.avg_1st_innings,
    va.avg_2nd_innings,
    va.avg_1st_innings - va.avg_2nd_innings                    AS scoring_diff,
    va.avg_pp_runs,
    va.avg_death_runs,
    va.avg_run_rate,
    CASE
        WHEN va.avg_1st_innings > 175 THEN 'Batting Paradise'
        WHEN va.avg_1st_innings < 145 THEN 'Bowling Friendly'
        ELSE 'Balanced'
    END                                                         AS pitch_type_label
FROM venue_agg va
JOIN dim_venue dv ON va.venue_key = dv.venue_key
WHERE va.total_matches >= 5
ORDER BY va.avg_1st_innings DESC;
