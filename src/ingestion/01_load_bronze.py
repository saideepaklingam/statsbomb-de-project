from pathlib import Path
import logging
import pandas as pd
from statsbombpy import sb

# Logging setup
LOG_DIR = Path("logs")
LOG_DIR.mkdir(exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(LOG_DIR / "bronze_ingestion.log", mode="w")
    ],
    force=True
)
logger = logging.getLogger(__name__)

# Config
BRONZE_DIR = Path("data/bronze")
COMPETITIONS = [
    {"competition_id": 43, "season_id": 106, "name": "FIFA_World_Cup_2022", "season_name": "2022"},
    {"competition_id": 55, "season_id": 282, "name": "UEFA_Euro_2024", "season_name": "2024"},
    {"competition_id": 223, "season_id": 282, "name": "Copa_America_2024", "season_name": "2024"},
]

# Only shot_end_location has 3 elements
COLS_WITH_Z = {"shot_end_location"}

# Helpers
def parquet_exists(match_dir: Path) -> bool:
    """Check if events.parquet already exists for idempotency."""
    return (match_dir / "events.parquet").exists()

def save_parquet(df: pd.DataFrame, path: Path):
    """Save DataFrame to Parquet with overwrite."""
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(path, index=False)

def flatten_location_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Flatten *_location columns into _x/_y/(_z if applicable)."""
    location_cols = [col for col in df.columns if col.endswith("_location")]
    for col in location_cols:
        expanded = pd.DataFrame(
            df[col].apply(
                lambda v: v if isinstance(v, (list, tuple)) else [None, None, None]
            ).tolist(),
            index=df.index,
            columns=[f"{col}_x", f"{col}_y", f"{col}_z"]
        )
        if col not in COLS_WITH_Z:
            expanded.drop(columns=[f"{col}_z"], inplace=True)
        df = pd.concat([df.drop(columns=[col]), expanded], axis=1)
    return df

def flatten_lineups(lineups_dict: dict) -> pd.DataFrame:
    """Flatten dict of team_name -> DataFrame into one DataFrame with team_name column."""
    dfs = [df.assign(team_name=team) for team, df in lineups_dict.items()]
    return pd.concat(dfs, ignore_index=True)

# Main ingestion
def ingest_bronze():
    meta_dir = BRONZE_DIR / "_meta"
    meta_dir.mkdir(parents=True, exist_ok=True)

    comps_path = meta_dir / "competitions.parquet"
    if not comps_path.exists():
        save_parquet(sb.competitions(), comps_path)

    all_matches = []

    for comp in COMPETITIONS:
        try:
            matches_df = sb.matches(competition_id=comp["competition_id"], season_id=comp["season_id"])
            all_matches.append(matches_df)

            for row in matches_df.itertuples(index=False):
                match_id = row.match_id
                match_dir = BRONZE_DIR / f"competition={comp['name']}" / f"season={comp['season_name']}" / f"match_id={match_id}"

                if parquet_exists(match_dir):
                    logger.info(f"Skip match_id={match_id} (already ingested)")
                    continue

                try:
                    # Events
                    events_df = sb.events(match_id=match_id)
                    print("EVENTS TYPE:", type(events_df)) 
                    events_df = flatten_location_columns(events_df)
                    save_parquet(events_df, match_dir / "events.parquet")

                    # Lineups
                    lineups_dict = sb.lineups(match_id=match_id)
                    lineups_df = flatten_lineups(lineups_dict)
                    print("LINEUPS TYPE:", type(lineups_df))
                    save_parquet(lineups_df, match_dir / "lineups.parquet")

                    # Match metadata (single row DataFrame)
                    match_row = matches_df[matches_df["match_id"] == match_id].iloc[0]
                    metadata_df = pd.DataFrame([match_row.to_dict()])
                    save_parquet(metadata_df, match_dir / "match_metadata.parquet")

                    logger.info(f"Ingested match_id={match_id} successfully")

                except Exception:
                    logger.exception(f"Failed to ingest match_id={match_id}")
                    continue

        except Exception:
            logger.exception(f"Failed to process competition={comp['name']}")
            continue
    if all_matches:
        combined_matches = pd.concat(all_matches, ignore_index=True)
        save_parquet(combined_matches, meta_dir / "matches.parquet")

if __name__ == "__main__":
    ingest_bronze()
