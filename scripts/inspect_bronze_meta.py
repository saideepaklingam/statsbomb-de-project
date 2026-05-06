import os
import duckdb

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRONZE_BASE = os.path.join(
    PROJECT_ROOT, "data", "bronze",
    "competition=*", "season=*", "match_id=*"
).replace("\\", "/")

con = duckdb.connect(":memory:")

for source in ["match_metadata", "lineups"]:
    print(f"\n{'='*60}\n{source.upper()}\n{'='*60}")
    parquet_glob = f"{BRONZE_BASE}/{source}.parquet"
    df = con.execute(f"""
        SELECT * FROM read_parquet(
            '{parquet_glob}',
            hive_partitioning = true,
            union_by_name = true
        ) LIMIT 3
    """).fetchdf()
    print(f"Columns: {len(df.columns)}")
    for col in df.columns:
        dtype = str(df[col].dtype)
        sample = df[col].iloc[0]
        sample_str = str(sample)[:100] if sample is not None else "NULL"
        print(f"  {col:<40} {dtype:<15} sample: {sample_str}")