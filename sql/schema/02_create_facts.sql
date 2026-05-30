-- ============================================================
-- CRICKET ANALYTICS DW — FACT TABLES
-- ============================================================
SET search_path TO cricket_dw;

-- ── fact_deliveries (grain: one row per ball bowled) ────────
CREATE TABLE IF NOT EXISTS fact_deliveries (
    delivery_key        BIGSERIAL PRIMARY KEY,
    match_key           INT     NOT NULL REFERENCES dim_match(match_key),
    date_key            INT     NOT NULL REFERENCES dim_date(date_key),
    inning              SMALLINT NOT NULL,          -- 1 or 2
    over_num            SMALLINT NOT NULL,          -- 0-indexed
    ball_num            SMALLINT NOT NULL,
    batter_key          INT     NOT NULL REFERENCES dim_player(player_key),
    bowler_key          INT     NOT NULL REFERENCES dim_player(player_key),
    non_striker_key     INT     REFERENCES dim_player(player_key),
    batting_team_key    INT     REFERENCES dim_team(team_key),
    bowling_team_key    INT     REFERENCES dim_team(team_key),
    venue_key           INT     REFERENCES dim_venue(venue_key),

    -- scoring
    batsman_runs        SMALLINT NOT NULL DEFAULT 0,
    extra_runs          SMALLINT NOT NULL DEFAULT 0,
    total_runs          SMALLINT NOT NULL DEFAULT 0,
    is_wide             BOOLEAN  NOT NULL DEFAULT FALSE,
    is_no_ball          BOOLEAN  NOT NULL DEFAULT FALSE,
    is_bye              BOOLEAN  NOT NULL DEFAULT FALSE,
    is_leg_bye          BOOLEAN  NOT NULL DEFAULT FALSE,
    is_boundary_four    BOOLEAN  NOT NULL DEFAULT FALSE,
    is_boundary_six     BOOLEAN  NOT NULL DEFAULT FALSE,

    -- wicket
    is_wicket           BOOLEAN  NOT NULL DEFAULT FALSE,
    dismissal_kind      VARCHAR(40),
    player_dismissed_key INT     REFERENCES dim_player(player_key),
    fielder_key         INT     REFERENCES dim_player(player_key),

    -- derived helpers
    phase               VARCHAR(15) GENERATED ALWAYS AS (
                            CASE
                                WHEN over_num < 6  THEN 'Powerplay'
                                WHEN over_num < 15 THEN 'Middle'
                                ELSE 'Death'
                            END
                        ) STORED
);

-- ── fact_match_innings (grain: one row per innings per match)
CREATE TABLE IF NOT EXISTS fact_match_innings (
    innings_key         SERIAL PRIMARY KEY,
    match_key           INT     NOT NULL REFERENCES dim_match(match_key),
    date_key            INT     NOT NULL REFERENCES dim_date(date_key),
    inning              SMALLINT NOT NULL,
    batting_team_key    INT     REFERENCES dim_team(team_key),
    bowling_team_key    INT     REFERENCES dim_team(team_key),
    total_runs          INT,
    total_wickets       SMALLINT,
    total_overs         NUMERIC(4,1),
    powerplay_runs      INT,
    middle_runs         INT,
    death_runs          INT,
    extras              INT,
    run_rate            NUMERIC(5,2)
);

-- ============================================================
-- INDEXES for query performance
-- ============================================================

-- deliveries — most analytics filter on these
CREATE INDEX idx_del_match     ON fact_deliveries(match_key);
CREATE INDEX idx_del_batter    ON fact_deliveries(batter_key);
CREATE INDEX idx_del_bowler    ON fact_deliveries(bowler_key);
CREATE INDEX idx_del_date      ON fact_deliveries(date_key);
CREATE INDEX idx_del_phase     ON fact_deliveries(phase);
CREATE INDEX idx_del_venue     ON fact_deliveries(venue_key);

-- covering index for batting leaderboard query
CREATE INDEX idx_del_batting_cover
    ON fact_deliveries(batter_key, date_key)
    INCLUDE (batsman_runs, is_boundary_four, is_boundary_six, is_wicket);

-- covering index for bowling economy query
CREATE INDEX idx_del_bowling_cover
    ON fact_deliveries(bowler_key, phase)
    INCLUDE (total_runs, is_wide, is_no_ball, is_wicket);

-- match-level
CREATE INDEX idx_match_season  ON dim_match(season);
CREATE INDEX idx_match_venue   ON dim_match(venue_key);
CREATE INDEX idx_match_winner  ON dim_match(winner_key);
