import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

con = duckdb.connect(WAREHOUSE, read_only=True)

print("=== Row count ===")
print(con.execute("SELECT COUNT(*) FROM main.mart_player_impact").fetchone()[0])

print("\n=== Top 10 non-penalty xG + xA per 90 (min 270 min) ===")
print(con.execute("""
    SELECT player_name, primary_position, team_name, competition_name,
           minutes_played, np_goals, np_xg_per_90, xa_per_90,
           (np_xg_per_90 + xa_per_90) as xg_plus_xa_per_90
    FROM main.mart_player_impact
    ORDER BY xg_plus_xa_per_90 DESC LIMIT 10
""").fetchdf())

print("\n=== Top 10 pressures per 90 ===")
print(con.execute("""
    SELECT player_name, primary_position, team_name, competition_name,
           minutes_played, pressures_per_90
    FROM main.mart_player_impact
    WHERE primary_position NOT LIKE 'Goalkeeper%'
    ORDER BY pressures_per_90 DESC LIMIT 10
""").fetchdf())

print("\n=== Top 10 progressive carries + dribbles per 90 ===")
print(con.execute("""
    SELECT player_name, primary_position, team_name, competition_name,
           prog_carries_per_90, successful_dribbles_per_90,
           (prog_carries_per_90 + successful_dribbles_per_90) as ball_carrier_score
    FROM main.mart_player_impact
    WHERE primary_position NOT LIKE 'Goalkeeper%'
    ORDER BY ball_carrier_score DESC LIMIT 10
""").fetchdf())

print("\n=== Distribution: minutes played ===")
print(con.execute("""
    SELECT 
        MIN(minutes_played) as min_min,
        MAX(minutes_played) as max_min,
        AVG(minutes_played) as avg_min,
        COUNT(*) as player_seasons
    FROM main.mart_player_impact
""").fetchdf())