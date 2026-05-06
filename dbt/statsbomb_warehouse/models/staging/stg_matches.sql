{{ config(materialized='table') }}

-- Silver stg_matches: one row per match.
-- Grain: match_id. Keeps all 55 metadata columns with renaming and light casting.
-- No filtering, no joining - that is Gold's job.

with bronze as (
    select *
    from read_parquet(
        '{{ var("bronze_path") }}/competition=*/season=*/match_id=*/match_metadata.parquet',
        hive_partitioning = true,
        union_by_name = true
    )
)

select
    -- ===== Identity =====
    match_id,
    competition_id,
    season_id,
    competition                         as competition_folder_name,
    season                              as season_year,

    -- ===== Match timing =====
    cast(match_date as date)            as match_date,
    kick_off                            as kick_off_time,
    match_week,
    competition_stage_id,
    competition_stage                   as competition_stage_name,

    -- ===== Competition metadata =====
    competition_name,
    competition_country_name,

    -- ===== Score =====
    home_score,
    away_score,

    -- ===== Home team =====
    home_team_id,
    home_team                           as home_team_name,
    home_team_gender,
    home_team_group,
    home_team_country_id,
    home_team_country_name,

    -- ===== Away team =====
    away_team_id,
    away_team                           as away_team_name,
    away_team_gender,
    away_team_group,
    away_team_country_id,
    away_team_country_name,

    -- ===== Stadium =====
    stadium_id,
    stadium                             as stadium_name,
    stadium_country_id,
    stadium_country_name,

    -- ===== Referee =====
    cast(referee_id as bigint)          as referee_id,
    referee                             as referee_name,
    cast(referee_country_id as bigint)  as referee_country_id,
    referee_country_name,

    -- ===== Managers =====
    home_manager_id,
    home_manager_name,
    nullif(home_manager_nickname, 'nan') as home_manager_nickname,
    cast(home_manager_dob as date)      as home_manager_dob,
    home_manager_country_id,
    home_manager_country_name,

    away_manager_id,
    away_manager_name,
    nullif(away_manager_nickname, 'nan') as away_manager_nickname,
    cast(away_manager_dob as date)      as away_manager_dob,
    away_manager_country_id,
    away_manager_country_name,

    -- ===== Status / versions =====
    match_status,
    match_status_360,
    cast(last_updated as timestamp)     as last_updated_at,
    data_version,
    shot_fidelity_version,
    xy_fidelity_version

from bronze