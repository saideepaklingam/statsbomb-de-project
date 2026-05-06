{{ config(materialized='table') }}

/* Gold mart 6: Team Behavior by Game State.
    Grain: (team, match, game_state).
    How teams adapt tactically to the scoreline. Hidden in season-level marts.
*/

/* This is the rebuilt version. The first one was wrong (see notes below).
    Approach:
        1. Compute abs_seconds per event, period-aware. StatsBomb stores minute/second per-period, not cumulative. 
           Add period offsets.
        2. Find all goal events per match. Each gives (abs_seconds, scoring_team).
        3. Build score-state intervals per match. Each interval has a constant score.
            Per team, label each interval Winning, Drawing, or Losing.
            Match clock gets sliced at goal events. Both teams share the same partition.
        4. Match length = max(abs_seconds) per match. End boundary uses that.
        5. Duration in state = sum of interval lengths with that state label.
        6. Metrics = events falling inside an interval of that state.
            Interval containment join, not "events the team performed in this state".
            This decoupling is the whole point of the rebuild.
*/

/* Invariant guaranteed by construction:
    For any match, Team A's "Winning" minutes == Team B's "Losing" minutes.
    Same time slice from two perspectives. Tested in tests/game_state_symmetry.sql.
*/    

/* Why the first version was wrong (worth keeping the lesson in the file):
    Original walked each team's event stream and computed durations between
    consecutive events of the same team. The team with denser events got more
    total duration attributed. Asymmetric by design, not by accident.
    122 of 125 matches failed the symmetry test. Avg diff 26 min, max 65.
    Looked plausible. Eye test passed. Only the test caught it.
*/

with events_timed as (
    select
        e.event_id,
        e.match_id,
        e.competition,
        e.season,
        e.team,
        e.period,
        e.minute,
        e.second,
        e.event_type,
        e.xg,
        e.shot_outcome,
        e.shot_type,
        e.pass_outcome,
        e.location[1] as start_x,
        e.pass_end_location_x,
        e.carry_end_location_x,
        m.home_team_name as home_team,
        m.away_team_name as away_team,
        (case e.period
            when 1 then 0
            when 2 then 45 * 60
            when 3 then 90 * 60
            when 4 then 105 * 60
         end) + e.minute * 60 + e.second as abs_seconds
    from {{ ref('stg_events') }} e
    join {{ ref('stg_matches') }} m on e.match_id = m.match_id
    where e.period between 1 and 4
      and e.minute is not null
      and e.second is not null
),

-- Step 1: Match length = last event's abs_seconds per match.

match_length as (
    select
        match_id,
        max(abs_seconds) as match_end_seconds,
        any_value(home_team) as home_team,
        any_value(away_team) as away_team
    from events_timed
    group by match_id
),

-- Step 2: Goals as score-state change points.

goals as (
    select
        match_id,
        abs_seconds as goal_seconds,
        team as scoring_team,
        home_team,
        away_team
    from events_timed
    where event_type = 'Shot' and shot_outcome = 'Goal'
),

-- Step 3: Build score timeline. For each goal, compute cumulative (home, away)
    -- AFTER this goal. Plus an artificial 0-0 at match start.

score_changes as (
    select
        g.match_id,
        g.home_team,
        g.away_team,
        g.goal_seconds,
        sum(case when g2.scoring_team = g.home_team then 1 else 0 end) as home_goals_after,
        sum(case when g2.scoring_team = g.away_team then 1 else 0 end) as away_goals_after
    from goals g
    join goals g2
        on g.match_id = g2.match_id
       and g2.goal_seconds <= g.goal_seconds
    group by g.match_id, g.home_team, g.away_team, g.goal_seconds
),


-- Step 4: Build segments. Each segment = [start_t, end_t] with constant score.
    -- Start at 0 (score 0-0). After each goal, new segment begins.
    -- After last goal, segment ends at match_end_seconds.

segments_raw as (
    -- Starting segment: from 0 to first goal (or match end if no goals)
    select
        m.match_id,
        ml.match_end_seconds,
        0::double as seg_start,
        coalesce(min(s.goal_seconds), ml.match_end_seconds) as seg_end,
        0 as home_score,
        0 as away_score,
        ml.home_team,
        ml.away_team
    from (select distinct match_id from events_timed) m
    join match_length ml on m.match_id = ml.match_id
    left join (
        select g.match_id, g.goal_seconds,
               first_value(g.home_team) over (partition by g.match_id) as home_team,
               first_value(g.away_team) over (partition by g.match_id) as away_team
        from goals g
    ) s on m.match_id = s.match_id
    group by m.match_id, ml.match_end_seconds, ml.home_team, ml.away_team

    union all

    -- After each goal: from goal_seconds to next_goal_seconds (or match end)
    select
        sc.match_id,
        ml.match_end_seconds,
        sc.goal_seconds as seg_start,
        coalesce(
            min(sc_next.goal_seconds),
            ml.match_end_seconds
        ) as seg_end,
        sc.home_goals_after as home_score,
        sc.away_goals_after as away_score,
        sc.home_team,
        sc.away_team
    from score_changes sc
    join match_length ml on sc.match_id = ml.match_id
    left join score_changes sc_next
        on sc.match_id = sc_next.match_id
       and sc_next.goal_seconds > sc.goal_seconds
    group by sc.match_id, ml.match_end_seconds, sc.goal_seconds,
             sc.home_goals_after, sc.away_goals_after, sc.home_team, sc.away_team
),


-- Step 5: Expand to per-team rows. Each segment yields 2 rows (home and away perspective).

match_length_helper as (
    -- Need home/away team per match for the no-goal-yet starting segment.
    -- We pull them from any event in that match.
    select distinct match_id, home_team, away_team
    from events_timed
),

segments_per_team as (
    select
        s.match_id,
        s.seg_start,
        s.seg_end,
        (s.seg_end - s.seg_start) / 60.0 as duration_minutes,
        h.home_team as team,
        case
            when s.home_score > s.away_score then 'Winning'
            when s.home_score < s.away_score then 'Losing'
            else 'Drawing'
        end as game_state
    from segments_raw s
    join match_length_helper h on s.match_id = h.match_id

    union all

    select
        s.match_id,
        s.seg_start,
        s.seg_end,
        (s.seg_end - s.seg_start) / 60.0 as duration_minutes,
        h.away_team as team,
        case
            when s.away_score > s.home_score then 'Winning'
            when s.away_score < s.home_score then 'Losing'
            else 'Drawing'
        end as game_state
    from segments_raw s
    join match_length_helper h on s.match_id = h.match_id
),

-- Step 6: Aggregate duration per (match, team, game_state).

state_durations as (
    select
        match_id,
        team,
        game_state,
        sum(duration_minutes) as minutes_in_state
    from segments_per_team
    group by match_id, team, game_state
),

-- Step 7: For metrics, classify each event into a state by interval lookup.
    -- An event belongs to whatever segment_per_team contains its abs_seconds AND matches its team.

events_classified as (
    select
        e.match_id,
        e.competition,
        e.season,
        e.team,
        e.event_type,
        e.xg,
        e.shot_outcome,
        e.shot_type,
        e.pass_outcome,
        e.start_x,
        e.pass_end_location_x,
        e.carry_end_location_x,
        spt.game_state
    from events_timed e
    join segments_per_team spt
        on  e.match_id = spt.match_id
        and e.team = spt.team
        and e.abs_seconds >= spt.seg_start
        and e.abs_seconds <  spt.seg_end
),

-- Step 8: Aggregate metrics per (team, match, game_state).

event_agg as (
    select
        team,
        competition,
        season,
        match_id,
        game_state,
        sum(case when event_type = 'Shot' and shot_type != 'Penalty' then xg else 0 end) as xg_generated,
        sum(case when event_type = 'Pressure' then 1 else 0 end) as pressures,
        sum(case when event_type = 'Pass' then 1 else 0 end) as passes_attempted,
        sum(case when event_type = 'Pass' and pass_outcome is null then 1 else 0 end) as passes_completed,
        avg(start_x) as avg_field_position_x,
        sum(case when event_type in ('Pass', 'Carry')
                  and start_x < 80
                  and (coalesce(pass_end_location_x, carry_end_location_x) >= 80)
                 then 1 else 0 end) as final_third_entries
    from events_classified
    group by team, competition, season, match_id, game_state
)

-- Final assembly

select
    sd.team || '|' || c.competition_folder_name || '|' || cast(c.season_year as varchar) as team_comp_key,
    sd.team as team_name,
    c.competition_name,
    c.competition_folder_name,
    c.season_year,
    sd.match_id,
    sd.game_state,
    round(sd.minutes_in_state, 1) as minutes_in_state,
    round(coalesce(ea.xg_generated, 0) / nullif(sd.minutes_in_state, 0), 4)  as xg_per_minute,
    round(coalesce(ea.pressures, 0) / nullif(sd.minutes_in_state, 0), 3) as pressures_per_minute,
    round(coalesce(ea.final_third_entries, 0) / nullif(sd.minutes_in_state, 0), 3) as f3_entries_per_minute,
    round(coalesce(ea.passes_completed, 0) * 1.0
          / nullif(coalesce(ea.passes_attempted, 0), 0), 3) as pass_completion_rate,
    round(ea.avg_field_position_x, 1) as avg_field_position_x,
    coalesce(ea.xg_generated, 0) as xg_raw,
    coalesce(ea.pressures, 0) as pressures_raw,
    coalesce(ea.passes_attempted, 0) as passes_attempted,
    coalesce(ea.passes_completed, 0) as passes_completed,
    coalesce(ea.final_third_entries, 0) as f3_entries_raw

from state_durations sd
left join event_agg ea
    on  sd.match_id = ea.match_id
    and sd.team = ea.team
    and sd.game_state = ea.game_state
left join {{ ref('stg_competitions') }} c
    on  ea.competition = c.competition_folder_name
    and ea.season = c.season_year

where sd.minutes_in_state >= 3.0
order by sd.match_id, sd.team, sd.game_state