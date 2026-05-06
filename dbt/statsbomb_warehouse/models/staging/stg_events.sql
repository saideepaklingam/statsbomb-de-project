{{ config(materialized='table') }}

-- Silver stg_events: thin cleanup of Bronze event data.
-- Grain: one row per event (~500k rows across 147 matches).
-- Transformations: rename reserved/invalid names, COALESCE NaN booleans → FALSE,
-- cast nullable float IDs to BIGINT. No joins, no business logic.

with bronze as (
    select *
    from read_parquet(
        '{{ var("bronze_path") }}/competition=*/season=*/match_id=*/events.parquet',
        hive_partitioning = true,
        union_by_name = true
    )
)

select
    -- ===== Identity & partition =====
    id                                                  as event_id,
    index                                               as event_index,
    competition,
    season,
    match_id,

    -- ===== Time =====
    period,
    minute,
    second,
    timestamp                                           as match_time,
    duration,

    -- ===== Event type / context =====
    type                                                as event_type,
    play_pattern,
    possession                                          as possession_sequence,
    possession_team,
    possession_team_id,

    -- ===== Team & player doing the action =====
    team,
    team_id,
    player                                              as player_name,
    cast(player_id as bigint)                           as player_id,
    position                                            as player_position,

    -- ===== Universal booleans (NaN → FALSE) =====
    coalesce(under_pressure, false)                     as under_pressure,
    coalesce(counterpress, false)                       as counterpress,
    coalesce(off_camera, false)                         as off_camera,
    coalesce(out, false)                                as is_out,
    coalesce(injury_stoppage_in_chain, false)           as injury_stoppage_in_chain,

    -- ===== 50/50 (invalid SQL name) =====
    "50_50"                                             as fifty_fifty,

    -- ===== Pass =====
    pass_length,
    pass_angle,
    pass_height,
    pass_body_part,
    pass_type,
    pass_technique,
    pass_outcome,
    pass_recipient                                      as pass_recipient_name,
    cast(pass_recipient_id as bigint)                   as pass_recipient_id,
    pass_end_location_x,
    pass_end_location_y,
    pass_assisted_shot_id,
    coalesce(pass_cross, false)                         as pass_cross,
    coalesce(pass_cut_back, false)                      as pass_cut_back,
    coalesce(pass_switch, false)                        as pass_switch,
    coalesce(pass_through_ball, false)                  as pass_through_ball,
    coalesce(pass_goal_assist, false)                   as pass_goal_assist,
    coalesce(pass_shot_assist, false)                   as pass_shot_assist,
    coalesce(pass_aerial_won, false)                    as pass_aerial_won,
    coalesce(pass_deflected, false)                     as pass_deflected,
    coalesce(pass_inswinging, false)                    as pass_inswinging,
    coalesce(pass_outswinging, false)                   as pass_outswinging,
    coalesce(pass_miscommunication, false)              as pass_miscommunication,
    coalesce(pass_no_touch, false)                      as pass_no_touch,
    coalesce(pass_straight, false)                      as pass_straight,

    -- ===== Shot =====
    shot_statsbomb_xg                                   as xg,
    shot_body_part,
    shot_type,
    shot_technique,
    shot_outcome,
    shot_end_location_x,
    shot_end_location_y,
    shot_end_location_z,
    shot_key_pass_id,
    coalesce(shot_first_time, false)                    as shot_first_time,
    coalesce(shot_one_on_one, false)                    as shot_one_on_one,
    coalesce(shot_deflected, false)                     as shot_deflected,
    coalesce(shot_aerial_won, false)                    as shot_aerial_won,

    -- ===== Carry =====
    carry_end_location_x,
    carry_end_location_y,

    -- ===== Dribble =====
    dribble_outcome,
    coalesce(dribble_nutmeg, false)                     as dribble_nutmeg,
    coalesce(dribble_overrun, false)                    as dribble_overrun,

    -- ===== Duel =====
    duel_type,
    duel_outcome,

    -- ===== Defensive actions =====
    interception_outcome,
    ball_receipt_outcome,
    coalesce(ball_recovery_recovery_failure, false)     as ball_recovery_failure,
    coalesce(block_deflection, false)                   as block_deflection,
    coalesce(block_offensive, false)                    as block_offensive,
    coalesce(block_save_block, false)                   as block_save_block,
    clearance_body_part,
    coalesce(clearance_aerial_won, false)               as clearance_aerial_won,
    coalesce(clearance_head, false)                     as clearance_head,
    coalesce(clearance_left_foot, false)                as clearance_left_foot,
    coalesce(clearance_right_foot, false)               as clearance_right_foot,
    coalesce(clearance_other, false)                    as clearance_other,

    -- ===== Goalkeeper =====
    goalkeeper_type,
    goalkeeper_outcome,
    goalkeeper_body_part,
    goalkeeper_position,
    goalkeeper_technique,
    goalkeeper_end_location_x,
    goalkeeper_end_location_y,

    -- ===== Foul =====
    foul_committed_type,
    foul_committed_card,
    coalesce(foul_committed_advantage, false)           as foul_committed_advantage,
    coalesce(foul_won_advantage, false)                 as foul_won_advantage,
    coalesce(foul_won_defensive, false)                 as foul_won_defensive,

    -- ===== Miscontrol =====
    coalesce(miscontrol_aerial_won, false)              as miscontrol_aerial_won,

    -- ===== Substitution =====
    substitution_outcome,
    cast(substitution_outcome_id as bigint)             as substitution_outcome_id,
    substitution_replacement                            as substitution_replacement_name,
    cast(substitution_replacement_id as bigint)         as substitution_replacement_id,

    -- ===== Nested, left as-is for Gold =====
    location,
    related_events,
    shot_freeze_frame,
    tactics

from bronze
order by match_id, period, minute, second, event_index