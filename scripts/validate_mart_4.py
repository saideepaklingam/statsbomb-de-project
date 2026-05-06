import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

con = duckdb.connect(WAREHOUSE, read_only=True)

print("=== Row count ===")
print(con.execute("SELECT COUNT(*) FROM main.mart_team_set_piece_effectiveness").fetchone()[0])

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

print("\n=== Top 10 set-piece xG per match ===")
print(con.execute("""
    SELECT team_name, competition_name, matches_played,
           sp_xg_per_match, sp_shots_per_match, sp_xg_per_shot,
           sp_goals, sp_conversion_rate
    FROM main.mart_team_set_piece_effectiveness
    WHERE matches_played >= 3
    ORDER BY sp_xg_per_match DESC LIMIT 10
""").fetchdf())

print("\n=== Most set-piece-dependent teams (highest % of xG from set pieces) ===")
print(con.execute("""
    SELECT team_name, competition_name, total_xg, sp_xg_total, sp_xg_share_of_total
    FROM main.mart_team_set_piece_effectiveness
    WHERE matches_played >= 3 AND total_xg >= 3.0
    ORDER BY sp_xg_share_of_total DESC LIMIT 10
""").fetchdf())

print("\n=== Best finishers from set pieces (min 8 shots) ===")
print(con.execute("""
    SELECT team_name, competition_name,
           sp_shots_total, sp_goals, sp_conversion_rate, sp_xg_per_shot
    FROM main.mart_team_set_piece_effectiveness
    WHERE sp_shots_total >= 8
    ORDER BY sp_conversion_rate DESC LIMIT 10
""").fetchdf())