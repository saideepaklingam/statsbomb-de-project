import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

con = duckdb.connect(WAREHOUSE, read_only=True)

print("=== Row count ===")
print(con.execute("SELECT COUNT(*) FROM main.mart_team_defensive_pressure").fetchone()[0])

print("\n=== Top 10 most intense presses (lowest PPDA) ===")
print(con.execute("""
    SELECT team_name, competition_name, matches_played,
           pressures_per_match, high_press_share, counterpress_share,
           ppda, high_press_regain_rate
    FROM main.mart_team_defensive_pressure
    WHERE matches_played >= 3
    ORDER BY ppda ASC LIMIT 10
""").fetchdf())

print("\n=== Bottom 10 (passive teams, highest PPDA) ===")
print(con.execute("""
    SELECT team_name, competition_name, matches_played,
           pressures_per_match, ppda, defensive_actions_per_match
    FROM main.mart_team_defensive_pressure
    WHERE matches_played >= 3
    ORDER BY ppda DESC LIMIT 10
""").fetchdf())

print("\n=== High press share vs counterpress share ===")
print(con.execute("""
    SELECT team_name, competition_name,
           high_press_share, counterpress_share, high_press_regain_rate
    FROM main.mart_team_defensive_pressure
    ORDER BY high_press_share DESC LIMIT 10
""").fetchdf())