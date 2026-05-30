-- ============================================================
-- STORED PROCEDURES — Cricket Analytics DW
-- ============================================================
SET search_path TO cricket_dw;

-- ────────────────────────────────────────────────────────────
-- sp_player_scorecard
-- Full batting + bowling card for a player in a given season
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE sp_player_scorecard(
    p_player_name VARCHAR,
    p_season      SMALLINT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_player_key INT;
BEGIN
    SELECT player_key INTO v_player_key
    FROM cricket_dw.dim_player
    WHERE player_name ILIKE p_player_name
      AND is_current = TRUE
    LIMIT 1;

    IF v_player_key IS NULL THEN
        RAISE NOTICE 'Player "%" not found.', p_player_name;
        RETURN;
    END IF;

    -- ── BATTING ─────────────────────────────────────────────
    RAISE NOTICE '=== BATTING CARD: % (Season: %) ===',
        p_player_name, COALESCE(p_season::TEXT, 'All');

    SELECT
        dm.season,
        COUNT(DISTINCT fd.match_key)                            AS innings,
        SUM(fd.batsman_runs)                                    AS total_runs,
        MAX(fd.batsman_runs)                                    AS high_score,
        ROUND(AVG(fd.batsman_runs)::NUMERIC, 2)                AS avg_per_ball,
        SUM(fd.is_boundary_four::INT)                          AS fours,
        SUM(fd.is_boundary_six::INT)                           AS sixes,
        ROUND(
            100.0 * SUM(fd.batsman_runs)
            / NULLIF(COUNT(*), 0), 2
        )                                                       AS strike_rate
    FROM fact_deliveries fd
    JOIN dim_match dm ON fd.match_key = dm.match_key
    WHERE fd.batter_key = v_player_key
      AND (p_season IS NULL OR dm.season = p_season)
    GROUP BY dm.season
    ORDER BY dm.season;

    -- ── BOWLING ─────────────────────────────────────────────
    RAISE NOTICE '=== BOWLING CARD: % (Season: %) ===',
        p_player_name, COALESCE(p_season::TEXT, 'All');

    SELECT
        dm.season,
        COUNT(DISTINCT fd.match_key)                            AS matches,
        COUNT(*)                                                AS balls_bowled,
        SUM(fd.total_runs)                                      AS runs_given,
        SUM(fd.is_wicket::INT)                                  AS wickets,
        ROUND(
            6.0 * SUM(fd.total_runs)
            / NULLIF(COUNT(*), 0), 2
        )                                                       AS economy,
        ROUND(
            1.0 * COUNT(*)
            / NULLIF(SUM(fd.is_wicket::INT), 0), 2
        )                                                       AS strike_rate
    FROM fact_deliveries fd
    JOIN dim_match dm ON fd.match_key = dm.match_key
    WHERE fd.bowler_key = v_player_key
      AND fd.is_wide = FALSE
      AND fd.is_no_ball = FALSE
      AND (p_season IS NULL OR dm.season = p_season)
    GROUP BY dm.season
    ORDER BY dm.season;
END;
$$;


-- ────────────────────────────────────────────────────────────
-- sp_match_summary
-- Full summary of a specific match
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE sp_match_summary(p_match_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE '=== MATCH SUMMARY: Match ID % ===', p_match_id;

    -- Match info
    SELECT
        dd.full_date,
        dm.season,
        dv.venue_name,
        dv.city,
        t1.team_name                    AS team_1,
        t2.team_name                    AS team_2,
        tw.team_name                    AS toss_winner,
        dm.toss_decision,
        wt.team_name                    AS winner,
        dm.win_by_runs,
        dm.win_by_wickets,
        dp.player_name                  AS player_of_match
    FROM dim_match dm
    JOIN dim_date dd      ON dm.date_key           = dd.date_key
    JOIN dim_venue dv     ON dm.venue_key           = dv.venue_key
    JOIN dim_team t1      ON dm.team1_key           = t1.team_key
    JOIN dim_team t2      ON dm.team2_key           = t2.team_key
    JOIN dim_team tw      ON dm.toss_winner_key     = tw.team_key
    JOIN dim_team wt      ON dm.winner_key          = wt.team_key
    LEFT JOIN dim_player dp ON dm.player_of_match_key = dp.player_key
    WHERE dm.match_id = p_match_id;

    -- Innings summary
    SELECT
        fmi.inning,
        bt.team_name        AS batting_team,
        fmi.total_runs,
        fmi.total_wickets,
        fmi.total_overs,
        fmi.run_rate,
        fmi.powerplay_runs,
        fmi.middle_runs,
        fmi.death_runs
    FROM fact_match_innings fmi
    JOIN dim_match dm ON fmi.match_key = dm.match_key
    JOIN dim_team bt  ON fmi.batting_team_key = bt.team_key
    WHERE dm.match_id = p_match_id
    ORDER BY fmi.inning;
END;
$$;


-- ────────────────────────────────────────────────────────────
-- sp_refresh_innings_agg
-- Rebuilds fact_match_innings from fact_deliveries
-- Run after each ETL load
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE sp_refresh_innings_agg()
LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE TABLE cricket_dw.fact_match_innings;

    INSERT INTO cricket_dw.fact_match_innings (
        match_key, date_key, inning,
        batting_team_key, bowling_team_key,
        total_runs, total_wickets, total_overs,
        powerplay_runs, middle_runs, death_runs,
        extras, run_rate
    )
    SELECT
        fd.match_key,
        fd.date_key,
        fd.inning,
        fd.batting_team_key,
        fd.bowling_team_key,
        SUM(fd.total_runs)                                  AS total_runs,
        SUM(fd.is_wicket::INT)                              AS total_wickets,
        ROUND(COUNT(*) / 6.0, 1)                            AS total_overs,
        SUM(fd.total_runs) FILTER (WHERE fd.phase='Powerplay') AS powerplay_runs,
        SUM(fd.total_runs) FILTER (WHERE fd.phase='Middle')    AS middle_runs,
        SUM(fd.total_runs) FILTER (WHERE fd.phase='Death')     AS death_runs,
        SUM(fd.extra_runs)                                  AS extras,
        ROUND(6.0 * SUM(fd.total_runs) / NULLIF(COUNT(*),0), 2) AS run_rate
    FROM fact_deliveries fd
    GROUP BY fd.match_key, fd.date_key, fd.inning,
             fd.batting_team_key, fd.bowling_team_key;

    RAISE NOTICE 'fact_match_innings refreshed: % rows', (SELECT COUNT(*) FROM cricket_dw.fact_match_innings);
END;
$$;
