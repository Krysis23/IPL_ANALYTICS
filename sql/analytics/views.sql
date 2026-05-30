-- ============================================================
-- VIEWS — Pre-built for Metabase / Tableau / Grafana
-- ============================================================
SET search_path TO cricket_dw;

-- vw_batting_leaderboard: ready for a live BI dashboard
CREATE OR REPLACE VIEW vw_batting_leaderboard AS
SELECT
    dp.player_name,
    dm.season,
    COUNT(DISTINCT fd.match_key)                                AS innings,
    SUM(fd.batsman_runs)                                        AS runs,
    ROUND(SUM(fd.batsman_runs)::NUMERIC /
          NULLIF(SUM(fd.is_wicket::INT), 0), 2)                AS average,
    ROUND(100.0 * SUM(fd.batsman_runs) / NULLIF(COUNT(*), 0), 2) AS strike_rate,
    SUM(fd.is_boundary_six::INT)                               AS sixes,
    SUM(fd.is_boundary_four::INT)                              AS fours,
    RANK() OVER (
        PARTITION BY dm.season
        ORDER BY SUM(fd.batsman_runs) DESC
    )                                                           AS season_rank
FROM fact_deliveries fd
JOIN dim_player dp ON fd.batter_key = dp.player_key
JOIN dim_match  dm ON fd.match_key  = dm.match_key
WHERE dp.is_current = TRUE
GROUP BY dp.player_name, dm.season;


-- vw_bowling_leaderboard
CREATE OR REPLACE VIEW vw_bowling_leaderboard AS
SELECT
    dp.player_name,
    dm.season,
    COUNT(DISTINCT fd.match_key)                                AS matches,
    SUM(fd.is_wicket::INT)                                     AS wickets,
    ROUND(6.0 * SUM(fd.total_runs) / NULLIF(COUNT(*), 0), 2)  AS economy,
    ROUND(COUNT(*)::NUMERIC /
          NULLIF(SUM(fd.is_wicket::INT), 0), 2)                AS bowling_average,
    RANK() OVER (
        PARTITION BY dm.season
        ORDER BY SUM(fd.is_wicket::INT) DESC
    )                                                           AS season_rank
FROM fact_deliveries fd
JOIN dim_player dp ON fd.bowler_key = dp.player_key
JOIN dim_match  dm ON fd.match_key  = dm.match_key
WHERE fd.is_wide = FALSE AND fd.is_no_ball = FALSE
  AND dp.is_current = TRUE
GROUP BY dp.player_name, dm.season;


-- vw_team_performance: win/loss record per season
CREATE OR REPLACE VIEW vw_team_performance AS
SELECT
    dt.team_name,
    dm.season,
    COUNT(*)                                                    AS matches_played,
    SUM(CASE WHEN dm.winner_key = dt.team_key THEN 1 ELSE 0 END) AS wins,
    SUM(CASE WHEN dm.winner_key != dt.team_key THEN 1 ELSE 0 END) AS losses,
    ROUND(
        100.0 * SUM(CASE WHEN dm.winner_key = dt.team_key THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 1
    )                                                           AS win_pct
FROM dim_match dm
JOIN dim_team dt
    ON dt.team_key IN (dm.team1_key, dm.team2_key)
WHERE dm.winner_key IS NOT NULL
GROUP BY dt.team_name, dm.season
ORDER BY dm.season DESC, win_pct DESC;


-- vw_head_to_head: rivalry stats between any two teams
CREATE OR REPLACE VIEW vw_head_to_head AS
SELECT
    t1.team_name                                                AS team_a,
    t2.team_name                                                AS team_b,
    COUNT(*)                                                    AS total_matches,
    SUM(CASE WHEN dm.winner_key = t1.team_key THEN 1 ELSE 0 END) AS team_a_wins,
    SUM(CASE WHEN dm.winner_key = t2.team_key THEN 1 ELSE 0 END) AS team_b_wins,
    SUM(CASE WHEN dm.winner_key IS NULL THEN 1 ELSE 0 END)     AS no_result
FROM dim_match dm
JOIN dim_team t1 ON dm.team1_key = t1.team_key
JOIN dim_team t2 ON dm.team2_key = t2.team_key
GROUP BY t1.team_name, t2.team_name;
