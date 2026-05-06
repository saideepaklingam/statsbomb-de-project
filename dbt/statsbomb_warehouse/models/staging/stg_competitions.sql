{{ config(materialized='table') }}

-- Silver stg_competitions: one row per competition+season.
-- Derived from match_metadata since StatsBomb does not ship a separate competitions file.
-- Grain: (competition_id, season_id).

with bronze as (
    select *
    from read_parquet(
        '{{ var("bronze_path") }}/competition=*/season=*/match_id=*/match_metadata.parquet',
        hive_partitioning = true,
        union_by_name = true
    )
)

select distinct
    competition_id,
    competition_name,
    competition                 as competition_folder_name,  -- Hive partition key (e.g. 'FIFA_World_Cup_2022')
    competition_country_name,
    season_id,
    season                      as season_year
from bronze
order by competition_id, season_id