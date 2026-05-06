{{ config(materialized='table') }}

/* Gold mart 2: Team Ball Progression.
        Grain: (team, competition, season).
        Measures which teams reliably move the ball from deeper zones into threatening areas.
*/

-- Pitch geometry: x = 0 (own goal) to 120 (opponent goal). Final third starts at x = 80.

/* Definitions:
        Progressive pass: forward gain >= 10m AND ending in final third (x >= 80).
        Some analytics shops use "25% of remaining distance" instead.
        Picked an absolute threshold because it is easier to defend in an interview.
        "Why 10 metres" has a cleaner answer than "why 25% specifically".
*/

/* Progressive carry: same threshold, applied to carries.
   Final third entry: pass or carry crossing the x = 80 line.
   start_x < 80 AND end_x >= 80. Counts entries, not sustained presence.
*/

/* Completion: StatsBomb sets pass_outcome to NULL on a completed pass.
        Anything else (Incomplete, Out, Pass Offside, etc.) is a failure.
        This convention is a StatsBomb quirk, not a SQL convention.
        Worth flagging because it is the kind of thing that bites people once.
*/        

with events as (
    -- Extract start_x from the nested `location` field.
    -- location[1] in DuckDB = first element of the array (x-coordinate).
    select
        event_id,
        team,
        competition,
        season,
        match_id,
        possession_sequence,
        event_type,
        location[1] as start_x,
        location[2] as start_y,
        pass_length,
        pass_outcome,
        pass_end_location_x,
        carry_end_location_x,
        shot_outcome
    from {{ ref('stg_events') }}
),

-- Step 1: classify each pass and carry

progression_actions as (
    select
        team,
        competition,
        season,
        match_id,
        event_type,

        -- Start / end x for this action
        start_x,
        case
            when event_type = 'Pass' then pass_end_location_x
            when event_type = 'Carry' then carry_end_location_x
        end as end_x,

        -- Was it progressive? forward >= 10m AND end_x >= 80
        case
            when event_type = 'Pass'
                 and pass_end_location_x - start_x >= 10
                 and pass_end_location_x >= 80
                then 1
            when event_type = 'Carry'
                 and carry_end_location_x - start_x >= 10
                 and carry_end_location_x >= 80
                then 1
            else 0
        end as is_progressive,

        -- Did it cross the x = 80 line? (final-third entry)
        case
            when event_type = 'Pass'
                 and start_x < 80 and pass_end_location_x >= 80
                then 1
            when event_type = 'Carry'
                 and start_x < 80 and carry_end_location_x >= 80
                then 1
            else 0
        end as is_final_third_entry,

        -- Was the pass completed? (only meaningful for passes)
        case
            when event_type = 'Pass' and pass_outcome is null then 1
            when event_type = 'Pass' and pass_outcome is not null then 0
            else null
        end as is_completed_pass

    from events
    where event_type in ('Pass', 'Carry')
      and start_x is not null
),

-- Step 2: possession-level flags for metric #6

possessions as (
    -- For each possession sequence, did it reach the final third?
    -- did it end with a shot? One row per possession.
    select
        team,
        competition,
        season,
        match_id,
        possession_sequence,
        max(case when start_x >= 80 then 1 else 0 end) as reached_final_third,
        max(case when event_type = 'Shot' then 1 else 0 end) as ended_with_shot
    from events
    group by team, competition, season, match_id, possession_sequence
),

-- Step 3: aggregate to team level

progression_agg as (
    select
        team,
        competition,
        season,
        count(distinct match_id) as matches_played,
        sum(case when event_type = 'Pass'  then is_progressive else 0 end) as progressive_passes,
        sum(case when event_type = 'Carry' then is_progressive else 0 end) as progressive_carries,
        sum(is_final_third_entry) as final_third_entries,

        -- For completion rate: only over progressive passes
        sum(case when event_type = 'Pass' and is_progressive = 1
                 then is_completed_pass else 0 end) as prog_passes_completed,
        sum(case when event_type = 'Pass' and is_progressive = 1 then 1 else 0 end) as prog_passes_attempted
    from progression_actions
    group by team, competition, season
),

possession_agg as (
    -- Team-level rollup of possessions
    select
        team,
        competition,
        season,
        sum(reached_final_third) as possessions_reaching_f3,
        sum(case when reached_final_third = 1 and ended_with_shot = 1
                 then 1 else 0 end) as possessions_f3_with_shot
    from possessions
    group by team, competition, season
)

-- Final assembly

select
    p.team || '|' || c.competition_folder_name || '|' || cast(c.season_year as varchar) as team_comp_key,
    p.team as team_name,
    c.competition_name,
    c.competition_folder_name,
    c.season_year,
    p.matches_played,

    -- Volume metrics (per match rates)
    round(p.progressive_passes * 1.0 / p.matches_played, 2) as progressive_passes_per_match,
    round(p.progressive_carries * 1.0 / p.matches_played, 2) as progressive_carries_per_match,
    round(p.final_third_entries * 1.0 / p.matches_played, 2) as final_third_entries_per_match,

    -- Efficiency metrics
    round(p.prog_passes_completed * 1.0 / nullif(p.prog_passes_attempted, 0), 3) as progressive_pass_completion_rate,

    -- Possession-level conversion (the hard one)
    round(pos.possessions_f3_with_shot * 1.0 / nullif(pos.possessions_reaching_f3, 0), 3) as final_third_to_shot_rate,

    -- Raw totals kept for transparency / Power BI drill-down
    p.progressive_passes,
    p.progressive_carries,
    p.final_third_entries,
    pos.possessions_reaching_f3,
    pos.possessions_f3_with_shot

from progression_agg p
join possession_agg pos
    on  p.team = pos.team
    and p.competition = pos.competition
    and p.season = pos.season
join {{ ref('stg_competitions') }} c
    on  p.competition = c.competition_folder_name
    and p.season = c.season_year

order by c.competition_name, progressive_passes_per_match desc