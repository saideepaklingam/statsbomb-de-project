{{ config(materialized='table') }}

/* Gold mart 5: Player Impact.
        Grain: (player_id, team, competition, season).
        Per-90 rates across offensive, defensive, and creative metrics, gated by minutes played.
        Minutes computation: stg_lineups.positions is a nested list of segments per (player, match).
        Each segment is {from, to, from_period, to_period}.
        UNNEST it, convert 'MM:SS' to seconds, take (to - from) per segment,
        sum across segments per player-match, roll up to (player, comp, season).
*/

/*  Decisions and trade-offs:
        Null `to` falls back to '120:00'. Slight over-count for stoppage-time subs,
        but bounded. Did not feel worth a more involved fix.
        Goalkeepers stay in the mart. Dashboard filters by primary_position.
        Filtering them in SQL would be opinionated and lose data unnecessarily.
        Penalty shots and goals excluded. Same call as Mart 1 and Mart 4.
        Penalty xG is standardised setup, not attacking skill.
        Minimum 270 minutes for inclusion. Three matches' worth of play.
        Below that, per-90 rates are noise. Argued with myself between 180 and 360.
        270 was the middle that felt right.
*/

-- Stage A: minutes per (player, match)

with lineup_segments as (
    select
        l.match_id,
        l.player_id,
        l.team_name as team,
        l.competition_folder_name as competition,
        l.season_year as season,
        seg.from_period as from_period,
        seg.to_period as to_period,
        seg."from" as from_ts,
        coalesce(seg.to, '120:00') as to_ts
    from {{ ref('stg_lineups') }} l,
    unnest(l.positions) as t(seg)
    -- l.positions is a list of structs; UNNEST yields one row per segment.
),

lineup_minutes as (
    -- Convert 'MM:SS' to seconds, diff, sum across segments per (player, match).
    -- SPLIT_PART returns strings; CAST to INTEGER.
    select
        match_id,
        player_id,
        team,
        competition,
        season,
        sum(
            (cast(split_part(to_ts, ':', 1) as integer) * 60
             + cast(split_part(to_ts, ':', 2) as integer))
          - (cast(split_part(from_ts, ':', 1) as integer) * 60
             + cast(split_part(from_ts, ':', 2) as integer))
        ) / 60.0 as minutes_in_match
    from lineup_segments
    group by match_id, player_id, team, competition, season
),

player_minutes as (
    -- Aggregate minutes and matches per player per competition.
    select
        player_id,
        team,
        competition,
        season,
        count(distinct match_id) as matches_played,
        sum(minutes_in_match) as total_minutes
    from lineup_minutes
    group by player_id, team, competition, season
),

-- Stage B: player metadata (name, primary position)

player_meta as (
    select
        player_id,
        team,
        competition,
        season,
        any_value(player_name) as player_name,
        mode(player_position) as primary_position
    from {{ ref('stg_events') }}
    where player_id is not null
    group by player_id, team, competition, season
),

-- Stage C: event-based aggregations per player

/*  xA = sum of xG on the shot that each player's pass assisted.
    StatsBomb tags assisted shots: pass_shot_assist = true, and pass_assisted_shot_id
    references the shot's event_id. We'll compute xA via self-join.
*/

assisted_shots as (
    -- Each row: a shot that was assisted, joined to the assisting pass.
    select
        p.player_id as assisting_player_id,
        p.team as team,
        p.competition as competition,
        p.season as season,
        s.xg as assisted_xg
    from {{ ref('stg_events') }} p
    join {{ ref('stg_events') }} s
        on  p.pass_assisted_shot_id = s.event_id
        and p.match_id = s.match_id
    where p.event_type = 'Pass'
      and p.pass_shot_assist = true
      and p.player_id is not null
      and s.shot_type != 'Penalty'
),

xa_per_player as (
    select
        assisting_player_id as player_id,
        team,
        competition,
        season,
        sum(assisted_xg) as total_xa
    from assisted_shots
    group by assisting_player_id, team, competition, season
),

player_events as (
    select
        player_id,
        team,
        competition,
        season,

        -- Offensive (penalties excluded)
        sum(case when event_type = 'Shot' and shot_type != 'Penalty' and shot_outcome = 'Goal'
                 then 1 else 0 end) as np_goals,
        sum(case when event_type = 'Shot' and shot_type != 'Penalty'
                 then xg else 0 end) as np_xg,

        -- Progression
        sum(case when event_type = 'Carry'
                 and carry_end_location_x - location[1] >= 10
                 and carry_end_location_x >= 80
                 then 1 else 0 end) as progressive_carries,

        -- Dribbles (take-ons)
        sum(case when event_type = 'Dribble' and dribble_outcome = 'Complete'
                 then 1 else 0 end) as successful_dribbles,

        -- Defensive
        sum(case when event_type = 'Pressure' then 1 else 0 end) as pressures,
        sum(case when event_type = 'Ball Recovery' then 1 else 0 end) as ball_recoveries

    from {{ ref('stg_events') }}
    where player_id is not null
    group by player_id, team, competition, season
)

-- Stage D: final join + per-90 rates + minutes filter

select
    pm.team || '|' || c.competition_folder_name || '|' || cast(c.season_year as varchar) as team_comp_key,
    pm.player_id,
    meta.player_name,
    meta.primary_position,
    pm.team as team_name,
    c.competition_name,
    c.competition_folder_name,
    c.season_year,

    pm.matches_played,
    round(pm.total_minutes, 0) as minutes_played,

    -- Per-90 rates (metric * 90 / minutes)
    round(pe.np_goals * 90.0 / pm.total_minutes, 2) as np_goals_per_90,
    round(pe.np_xg * 90.0 / pm.total_minutes, 2) as np_xg_per_90,
    round(coalesce(xa.total_xa, 0) * 90.0 / pm.total_minutes, 2) as xa_per_90,
    round(pe.progressive_carries * 90.0 / pm.total_minutes, 2) as prog_carries_per_90,
    round(pe.successful_dribbles * 90.0 / pm.total_minutes, 2) as successful_dribbles_per_90,
    round(pe.pressures * 90.0 / pm.total_minutes, 2) as pressures_per_90,
    round(pe.ball_recoveries * 90.0 / pm.total_minutes, 2) as ball_recoveries_per_90,

    -- Raw totals for transparency
    pe.np_goals,
    round(pe.np_xg, 2) as np_xg_total,
    round(coalesce(xa.total_xa, 0), 2) as xa_total,
    pe.progressive_carries,
    pe.successful_dribbles,
    pe.pressures,
    pe.ball_recoveries

from player_minutes pm
join player_meta meta
    on  pm.player_id  = meta.player_id
    and pm.team = meta.team
    and pm.competition = meta.competition
    and pm.season = meta.season
join player_events pe
    on  pm.player_id  = pe.player_id
    and pm.team = pe.team
    and pm.competition = pe.competition
    and pm.season = pe.season
left join xa_per_player xa
    on  pm.player_id  = xa.player_id
    and pm.team = xa.team
    and pm.competition = xa.competition
    and pm.season = xa.season
join {{ ref('stg_competitions') }} c
    on  pm.competition = c.competition_folder_name
    and pm.season = c.season_year

where pm.total_minutes >= 270
order by c.competition_name, np_xg_per_90 + coalesce(xa.total_xa, 0) * 90.0 / pm.total_minutes desc