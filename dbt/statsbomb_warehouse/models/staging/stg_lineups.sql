{{ config(materialized='table') }}

-- Silver stg_lineups: one row per player per match.
-- Grain: (match_id, player_id).
-- 'positions' left as nested array - Gold unpacks if needed.

with bronze as (
    select *
    from read_parquet(
        '{{ var("bronze_path") }}/competition=*/season=*/match_id=*/lineups.parquet',
        hive_partitioning = true,
        union_by_name = true
    )
)

select
    -- ===== Identity =====
    match_id,
    player_id,
    team_name,
    competition                 as competition_folder_name,
    season                      as season_year,

    -- ===== Player =====
    player_name,
    nullif(player_nickname, 'nan')  as player_nickname,
    jersey_number,
    country                     as player_country,

    -- ===== Nested, left for Gold =====
    cards,
    positions

from bronze