import duckdb
import os

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")
EXPORT_DIR = os.path.join(PROJECT_ROOT, "data", "exports").replace("\\", "/")

os.makedirs(EXPORT_DIR, exist_ok=True)

con = duckdb.connect(WAREHOUSE, read_only=True)

marts = [
    "mart_team_attack_quality",
    "mart_team_ball_progression",
    "mart_team_defensive_pressure",
    "mart_team_set_piece_effectiveness",
    "mart_player_impact",
    "mart_team_gamestate_behavior",
]

for m in marts:
    out_path = f"{EXPORT_DIR}/{m}.parquet"
    con.execute(f"COPY (SELECT * FROM main.{m}) TO '{out_path}' (FORMAT parquet)")
    rows = con.execute(f"SELECT COUNT(*) FROM main.{m}").fetchone()[0]
    print(f"Exported {m:<45} {rows:>6} rows -> {out_path}")

# Build a unique dimension of teams across all marts
dim_path = f"{EXPORT_DIR}/dim_team_competition.parquet"
con.execute(f"""
    COPY (
        SELECT DISTINCT 
            team_name || '|' || competition_folder_name || '|' || CAST(season_year AS VARCHAR) as team_comp_key,
            team_name,
            competition_name,
            competition_folder_name,
            season_year
        FROM main.mart_team_attack_quality
    ) TO '{dim_path}' (FORMAT parquet)
""")
con.close()
print(f"\nDone. Files in {EXPORT_DIR}")