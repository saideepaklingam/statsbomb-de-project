import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRONZE_GLOB = os.path.join(
    PROJECT_ROOT, "data", "bronze",
    "competition=*", "season=*", "match_id=*", "events.parquet"
).replace("\\", "/")

con = duckdb.connect(":memory:")
df = con.execute(f"""
    SELECT * FROM read_parquet(
        '{BRONZE_GLOB}',
        hive_partitioning = true
    ) LIMIT 1
""").fetchdf()

print(f"Total columns: {len(df.columns)}\n")
for col in df.columns:
    dtype = str(df[col].dtype)
    sample = df[col].iloc[0]
    sample_str = str(sample)[:80] if sample is not None else "NULL"
    print(f"  {col:<40} {dtype:<15} sample: {sample_str}")