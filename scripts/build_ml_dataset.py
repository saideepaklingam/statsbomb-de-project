"""Build the ML feature matrix by joining outcome labels with Gold mart features."""
import os
import duckdb
import pandas as pd

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")
EXPORT_DIR = os.path.join(PROJECT_ROOT, "data", "exports").replace("\\", "/")
ML_DATASET_PATH = f"{EXPORT_DIR}/ml_dataset.parquet"

os.makedirs(EXPORT_DIR, exist_ok=True)

con = duckdb.connect(WAREHOUSE, read_only=False)

# Join all 4 team-grain marts on team_comp_key, plus the outcome labels.
con.execute("""
CREATE OR REPLACE TABLE ml_dataset AS
SELECT 
    o.team_comp_key,
    o.team_name,
    o.competition_folder_name,
    o.season_year,
    o.outcome_class,
    
    -- Mart 1: Attack
    a.matches_played,
    a.shots_per_match,
    a.xg_per_match,
    a.xg_per_shot,
    a.open_play_xg_share,
    a.set_piece_xg_share,
    
    -- Mart 2: Ball Progression
    p.progressive_passes_per_match,
    p.progressive_carries_per_match,
    p.final_third_entries_per_match,
    p.progressive_pass_completion_rate,
    p.final_third_to_shot_rate,
    
    -- Mart 3: Defensive Pressure
    d.pressures_per_match,
    d.high_press_share,
    d.counterpress_share,
    d.ppda,
    d.high_press_regain_rate,
    
    -- Mart 4: Set Pieces
    sp.sp_xg_per_match,
    sp.sp_conversion_rate
    
FROM team_outcomes o
LEFT JOIN main.mart_team_attack_quality a ON o.team_comp_key = a.team_comp_key
LEFT JOIN main.mart_team_ball_progression p ON o.team_comp_key = p.team_comp_key
LEFT JOIN main.mart_team_defensive_pressure d ON o.team_comp_key = d.team_comp_key
LEFT JOIN main.mart_team_set_piece_effectiveness sp ON o.team_comp_key = sp.team_comp_key
""")

# Sanity check
print("=== row counts ===")
print(con.execute("SELECT COUNT(*) as total_rows FROM ml_dataset").fetchdf())

print("\n=== sample rows ===")
print(con.execute("""
    SELECT team_name, competition_folder_name, outcome_class, 
           ROUND(xg_per_match, 2) as xg_pm, 
           ROUND(ppda, 2) as ppda,
           ROUND(set_piece_xg_share, 2) as sp_share
    FROM ml_dataset 
    ORDER BY outcome_class, xg_per_match DESC
    LIMIT 10
""").fetchdf())

print("\n=== nulls per column (should all be 0) ===")
print(con.execute("""
    SELECT
        SUM(CASE WHEN matches_played IS NULL THEN 1 ELSE 0 END) as missing_matches,
        SUM(CASE WHEN xg_per_match IS NULL THEN 1 ELSE 0 END) as missing_xg,
        SUM(CASE WHEN ppda IS NULL THEN 1 ELSE 0 END) as missing_ppda,
        SUM(CASE WHEN sp_xg_per_match IS NULL THEN 1 ELSE 0 END) as missing_sp_xg
    FROM ml_dataset
""").fetchdf())

# Save to Parquet for ML consumption
con.execute(f"""
    COPY ml_dataset TO '{ML_DATASET_PATH}' (FORMAT parquet)
""")
print(f"\nSaved to {ML_DATASET_PATH}")

con.close()