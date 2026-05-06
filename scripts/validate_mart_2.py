import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

con = duckdb.connect(WAREHOUSE, read_only=True)

print("=== Row count ===")
print(con.execute("SELECT COUNT(*) FROM main.mart_team_ball_progression").fetchone()[0])

print("\n=== Top 10 by progressive passes per match ===")
print(con.execute("""
    SELECT team_name, competition_name, matches_played,
           progressive_passes_per_match, progressive_carries_per_match,
           final_third_entries_per_match, progressive_pass_completion_rate
    FROM main.mart_team_ball_progression
    ORDER BY progressive_passes_per_match DESC LIMIT 10
""").fetchdf())

print("\n=== Top 10 by final-third-to-shot rate (min 20 possessions in F3) ===")
print(con.execute("""
    SELECT team_name, competition_name, possessions_reaching_f3,
           possessions_f3_with_shot, final_third_to_shot_rate
    FROM main.mart_team_ball_progression
    WHERE possessions_reaching_f3 >= 20
    ORDER BY final_third_to_shot_rate DESC LIMIT 10
""").fetchdf())

print("\n=== Bottom 5 progressive pass completion (min 20 attempts) ===")
print(con.execute("""
    SELECT team_name, competition_name,
           progressive_pass_completion_rate,
           progressive_passes
    FROM main.mart_team_ball_progression
    WHERE progressive_passes >= 20
    ORDER BY progressive_pass_completion_rate ASC LIMIT 5
""").fetchdf())