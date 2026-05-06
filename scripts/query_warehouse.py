import os
import duckdb
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAREHOUSE = os.path.join(PROJECT_ROOT, "warehouse", "football.duckdb")

con = duckdb.connect(WAREHOUSE, read_only=True)

print("=== Tables and views in warehouse ===")
print(con.execute("SHOW ALL TABLES").fetchdf())

if len(sys.argv) > 1:
    table = sys.argv[1]
    print(f"\n=== Sample from {table} ===")
    print(con.execute(f"SELECT * FROM {table} LIMIT 5").fetchdf())
    rows = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"\nTotal rows: {rows}")

con.close()