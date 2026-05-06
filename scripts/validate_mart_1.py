import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

con = duckdb.connect(WAREHOUSE, read_only=True)

print("=== Row count ===")
print(con.execute("SELECT COUNT(*) FROM main.mart_team_attack_quality").fetchone()[0])

print("\n=== Top 10 by xG per match ===")
print(con.execute("""
    SELECT team_name, competition_name, matches_played, xg_per_match, xg_per_shot, goals
    FROM main.mart_team_attack_quality
    ORDER BY xg_per_match DESC LIMIT 10
""").fetchdf())

print("\n=== Sanity: set_piece_share + open_play_share should be close to 1 ===")
print(con.execute("""
    SELECT team_name, open_play_xg_share, set_piece_xg_share,
           (open_play_xg_share + set_piece_xg_share) as share_sum
    FROM main.mart_team_attack_quality
    ORDER BY share_sum LIMIT 5
""").fetchdf())