-- ============================================================
-- CRICKET ANALYTICS DW — DIMENSION TABLES
-- ============================================================

CREATE SCHEMA IF NOT EXISTS cricket_dw;
SET search_path TO cricket_dw;

-- ── dim_date ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_date (
    date_key        SERIAL PRIMARY KEY,
    full_date       DATE        NOT NULL UNIQUE,
    day_of_week     SMALLINT,
    day_name        VARCHAR(10),
    day_of_month    SMALLINT,
    month_num       SMALLINT,
    month_name      VARCHAR(10),
    quarter         SMALLINT,
    year            SMALLINT,
    ipl_season      SMALLINT,   -- e.g. 2023
    is_weekend      BOOLEAN
);

-- ── dim_team ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_team (
    team_key        SERIAL PRIMARY KEY,
    team_name       VARCHAR(100) NOT NULL UNIQUE,
    short_name      VARCHAR(10),
    home_city       VARCHAR(60),
    home_ground     VARCHAR(100),
    founded_year    SMALLINT,
    -- SCD Type 2 columns
    valid_from      DATE         NOT NULL DEFAULT CURRENT_DATE,
    valid_to        DATE,
    is_current      BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ── dim_venue ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_venue (
    venue_key       SERIAL PRIMARY KEY,
    venue_name      VARCHAR(150) NOT NULL,
    city            VARCHAR(80),
    country         VARCHAR(60)  DEFAULT 'India',
    capacity        INT,
    pitch_type      VARCHAR(30)  -- Batting / Bowling / Balanced
);

-- ── dim_player ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_player (
    player_key      SERIAL PRIMARY KEY,
    player_name     VARCHAR(100) NOT NULL,
    country         VARCHAR(60),
    batting_style   VARCHAR(30), -- Right / Left hand
    bowling_style   VARCHAR(60), -- Fast / Spin etc.
    player_role     VARCHAR(30), -- Batsman / Bowler / All-rounder / WK
    dob             DATE,
    -- SCD Type 2
    valid_from      DATE         NOT NULL DEFAULT CURRENT_DATE,
    valid_to        DATE,
    is_current      BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ── dim_match ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dim_match (
    match_key       SERIAL PRIMARY KEY,
    match_id        INT          NOT NULL UNIQUE,  -- source system ID
    date_key        INT          REFERENCES dim_date(date_key),
    season          SMALLINT,
    match_type      VARCHAR(30)  DEFAULT 'League',  -- League / Qualifier / Final
    venue_key       INT          REFERENCES dim_venue(venue_key),
    team1_key       INT          REFERENCES dim_team(team_key),
    team2_key       INT          REFERENCES dim_team(team_key),
    toss_winner_key INT          REFERENCES dim_team(team_key),
    toss_decision   VARCHAR(10), -- bat / field
    winner_key      INT          REFERENCES dim_team(team_key),
    win_by_runs     INT,
    win_by_wickets  INT,
    player_of_match_key INT      REFERENCES dim_player(player_key),
    dl_applied      BOOLEAN      DEFAULT FALSE
);
