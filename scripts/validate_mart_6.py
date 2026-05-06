import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

con = duckdb.connect(WAREHOUSE, read_only=True)

print("=== Row count ===")
print(con.execute("SELECT COUNT(*) FROM main.mart_team_gamestate_behavior").fetchone()[0])

print("\n=== State distribution ===")
print(con.execute("""
    SELECT game_state, COUNT(*) as n_team_matches,
           ROUND(AVG(minutes_in_state), 1) as avg_minutes,
           ROUND(AVG(xg_per_minute), 4) as avg_xg_per_min
    FROM main.mart_team_gamestate_behavior
    GROUP BY game_state
""").fetchdf())

print("\n=== Teams attack more when losing? (compare xG/min by state) ===")
print(con.execute("""
    SELECT team_name, competition_name,
           game_state, ROUND(SUM(xg_raw), 2) as total_xg,
           ROUND(SUM(minutes_in_state), 0) as total_min,
           ROUND(SUM(xg_raw) / NULLIF(SUM(minutes_in_state), 0), 4) as xg_per_min
    FROM main.mart_team_gamestate_behavior
    WHERE team_name IN ('Argentina', 'France', 'Spain', 'Germany')
    GROUP BY team_name, competition_name, game_state
    ORDER BY team_name, competition_name, game_state
""").fetchdf())

print("\n=== Teams sit deeper when winning? (avg field position by state) ===")
print(con.execute("""
    SELECT game_state,
           ROUND(AVG(avg_field_position_x), 1) as mean_x,
           COUNT(*) as n
    FROM main.mart_team_gamestate_behavior
    GROUP BY game_state
""").fetchdf())

print("\n=== Biggest score-state contrast: teams that drastically changed behavior ===")
print(con.execute("""
    -- For teams with all 3 states, show delta in xG/min between losing and winning
    WITH t AS (
      SELECT team_name, competition_name, game_state, xg_per_minute
      FROM main.mart_team_gamestate_behavior
      WHERE game_state IN ('Winning', 'Losing')
    )
    SELECT
      team_name, competition_name,
      MAX(CASE WHEN game_state='Losing'  THEN xg_per_minute END) as xg_per_min_losing,
      MAX(CASE WHEN game_state='Winning' THEN xg_per_minute END) as xg_per_min_winning,
      ROUND(
        MAX(CASE WHEN game_state='Losing'  THEN xg_per_minute END) -
        MAX(CASE WHEN game_state='Winning' THEN xg_per_minute END), 4) as delta
    FROM t
    GROUP BY team_name, competition_name
    HAVING MAX(CASE WHEN game_state='Losing' THEN xg_per_minute END) IS NOT NULL
       AND MAX(CASE WHEN game_state='Winning' THEN xg_per_minute END) IS NOT NULL
    ORDER BY delta DESC
    LIMIT 10
""").fetchdf())