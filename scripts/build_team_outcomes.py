"""Derive tournament outcome class for each (team, comp, season)."""
import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

con = duckdb.connect(WAREHOUSE, read_only=False)

# Stage rank: higher = deeper
con.execute("""
CREATE OR REPLACE TABLE team_outcomes AS
WITH all_team_matches AS (
    -- Home team perspective
    SELECT 
        home_team_name as team_name,
        competition_folder_name,
        season_year,
        competition_stage_name
    FROM main.stg_matches
    UNION ALL
    -- Away team perspective
    SELECT 
        away_team_name as team_name,
        competition_folder_name,
        season_year,
        competition_stage_name
    FROM main.stg_matches
),
stage_ranked AS (
    SELECT 
        team_name,
        competition_folder_name,
        season_year,
        competition_stage_name,
        CASE competition_stage_name
            WHEN 'Group Stage' THEN 1
            WHEN 'Round of 16' THEN 2
            WHEN 'Quarter-finals' THEN 3
            WHEN 'Semi-finals' THEN 4
            WHEN '3rd Place Final' THEN 5
            WHEN 'Final' THEN 6
            ELSE 0
        END as stage_rank
    FROM all_team_matches
),
deepest AS (
    SELECT 
        team_name,
        competition_folder_name,
        season_year,
        MAX(stage_rank) as max_stage_rank
    FROM stage_ranked
    GROUP BY team_name, competition_folder_name, season_year
)
SELECT 
    team_name || '|' || competition_folder_name || '|' || cast(season_year as varchar) as team_comp_key,
    team_name,
    competition_folder_name,
    season_year,
    max_stage_rank,
    CASE 
        WHEN max_stage_rank = 1 THEN 'Group-stage exit'
        WHEN max_stage_rank BETWEEN 2 AND 5 THEN 'Knockout pre-final'
        WHEN max_stage_rank = 6 THEN 'Finalist'
    END as outcome_class
FROM deepest
ORDER BY max_stage_rank DESC, team_name
""")

# Sanity check
print("=== outcome class distribution ===")
print(con.execute("""
    SELECT outcome_class, COUNT(*) as teams
    FROM team_outcomes
    GROUP BY outcome_class
    ORDER BY teams DESC
""").fetchdf())

print("\n=== sample of finalists (verify) ===")
print(con.execute("""
    SELECT team_name, competition_folder_name, season_year, outcome_class
    FROM team_outcomes
    WHERE outcome_class = 'Finalist'
    ORDER BY competition_folder_name
""").fetchdf())

con.close()
print("\nDone. Created table 'team_outcomes' in warehouse.")