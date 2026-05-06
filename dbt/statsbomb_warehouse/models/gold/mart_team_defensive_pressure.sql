{{ config(materialized='table') }}

/* Gold mart 3: Team Defensive Pressure.
    Grain: (team, competition, season).
    Measures how intensely and how high up the pitch each team presses.
*/

/* StatsBomb coordinate note: x = 0 to 120, normalised so attacking direction is toward x = 120 for the team performing the action.
   So "x >= 60" means opponent's half from the pressing team's perspective. No coordinate flipping needed.
*/

/* Definitions:
    Pressure: event_type = 'Pressure'.
    StatsBomb has an explicit pressing event. No need to infer from proximity.
*/

/*  High press: pressure at x >= 60 (opponent's half). Picked the halfway line over the final third (x >= 80) 
    because final third pressing is rare for most teams and would collapse the metric. Halfway gives a usable signal across the dataset.
*/

/* Counterpress: StatsBomb's counterpress = true. Tagged when pressure occurs within 5 seconds of losing the ball.
   Used this instead of computing "turnover within Ns" myself. The flag already captures the right intent and avoids brittle 
   temporal joins.
*/

/* PPDA: (opponent passes in zone) / (my pressures + tackles + fouls in zone).
    Lower = more intense press. Classic Opta metric. Zones below.
    PPDA zone, mine: x >= 48 (opponent's own 60% from my POV).
    PPDA zone, opponent's: their x <= 72 (their own 60% from their POV).
    Opta's standard zone. The 60% threshold is a convention worth keeping
    because it makes the metric comparable to public PPDA tables.
*/

/* Adaptation note (worth flagging in interviews):
    Classic Opta PPDA = passes / (tackles + interceptions + fouls).
    StatsBomb has no clean "Interception" event type. Defensive actions scatter
    across Pressure, Duel, and Ball Recovery. Used pressures + duels of type
    'Tackle' + fouls instead. Same direction (lower = more intense), different
    absolute numbers from FBref or Opta. If anyone asks "why does your PPDA
    not match FBref", that is the answer.
*/

/* Reading note (also worth flagging):
    PPDA measures press intensity, not defensive quality.
    A team with high PPDA might be a low block by design, not a bad defence.
    Morocco at WC 2022 will have high PPDA. They were not passive, they were
    sitting deep on purpose. Same number, different interpretation.
*/

with events as (
    select
        team,
        competition,
        season,
        match_id,
        event_type,
        location[1]          as start_x,
        duel_type,
        counterpress,
        pass_outcome
    from {{ ref('stg_events') }}
),

-- Step 1: Per-team defensive and pressing counts

team_defense as (
    select
        team,
        competition,
        season,
        count(distinct match_id) as matches_played,

        -- Pressures
        sum(case when event_type = 'Pressure' then 1 else 0 end) as pressures_total,
        sum(case when event_type = 'Pressure' and start_x >= 60 then 1 else 0 end) as pressures_high,
        sum(case when event_type = 'Pressure' and counterpress = true then 1 else 0 end) as counterpresses_total,
        sum(case when event_type = 'Pressure' and counterpress = true and start_x >= 60 then 1 else 0 end) as counterpresses_high,

        -- Other defensive actions (for defensive_actions_per_match)
        sum(case when event_type = 'Duel' then 1 else 0 end) as duels_total,
        sum(case when event_type = 'Foul Committed' then 1 else 0 end) as fouls_total,
        sum(case when event_type = 'Ball Recovery' then 1 else 0 end) as recoveries_total,

        -- PPDA denominator: defensive actions in x >= 48
        sum(case when event_type = 'Pressure' and start_x >= 48 then 1 else 0 end) as ppda_pressures,
        sum(case when event_type = 'Duel' and duel_type = 'Tackle' and start_x >= 48 then 1 else 0 end) as ppda_tackles,
        sum(case when event_type = 'Foul Committed' and start_x >= 48 then 1 else 0 end) as ppda_fouls

    from events
    where start_x is not null
    group by team, competition, season
),


-- Step 2: Opponent-passes-per-team, from the opponent's POV.
    -- For team X, we want passes by their opponents, filtered to
    -- opponent's own 60% (opponent's x <= 72 in opponent's POV).

match_pairs as (
    -- Every (match_id, team, opponent) row from stg_matches
    select
        match_id,
        competition_folder_name as competition,
        season_year as season,
        home_team_name as team,
        away_team_name as opponent
    from {{ ref('stg_matches') }}
    union all
    select
        match_id,
        competition_folder_name as competition,
        season_year as season,
        away_team_name as team,
        home_team_name as opponent
    from {{ ref('stg_matches') }}
),

opponent_passes as (
    -- Count passes by each opponent in opponent's own 60% (their x <= 72)
    select
        mp.team,
        mp.competition,
        mp.season,
        count(*) as opp_passes_in_zone
    from match_pairs mp
    join events e
        on  e.match_id = mp.match_id
        and e.team = mp.opponent
        and e.competition = mp.competition
        and e.season = mp.season
    where e.event_type = 'Pass'
      and e.start_x <= 72
      and e.start_x is not null
    group by mp.team, mp.competition, mp.season
)

-- Final assembly

select
    td.team || '|' || c.competition_folder_name || '|' || cast(c.season_year as varchar) as team_comp_key,
    td.team as team_name,
    c.competition_name,
    c.competition_folder_name,
    c.season_year,
    td.matches_played,

    -- 1. Pressures per match
    round(td.pressures_total * 1.0 / td.matches_played, 2) as pressures_per_match,

    -- 2. High press share
    round(td.pressures_high * 1.0 / nullif(td.pressures_total, 0), 3) as high_press_share,

    -- 3. Counterpress share
    round(td.counterpresses_total * 1.0 / nullif(td.pressures_total, 0), 3) as counterpress_share,

    -- 4. PPDA — lower = more intense press
    round(
        op.opp_passes_in_zone * 1.0
        / nullif(td.ppda_pressures + td.ppda_tackles + td.ppda_fouls, 0),
        2
    ) as ppda,

    -- 5. Defensive actions per match (volume context)
    round(
        (td.pressures_total + td.duels_total + td.fouls_total + td.recoveries_total) * 1.0
        / td.matches_played,
        2
    ) as defensive_actions_per_match,

    -- 6. High press regain rate
    round(td.counterpresses_high * 1.0 / nullif(td.pressures_high, 0), 3) as high_press_regain_rate,

    -- Raw totals for transparency
    td.pressures_total,
    td.pressures_high,
    td.counterpresses_total,
    td.counterpresses_high,
    op.opp_passes_in_zone as opp_passes_in_zone_raw,
    (td.ppda_pressures + td.ppda_tackles + td.ppda_fouls) as ppda_denom_raw

from team_defense td
join opponent_passes op
    on  td.team = op.team
    and td.competition = op.competition
    and td.season = op.season
join {{ ref('stg_competitions') }} c
    on  td.competition = c.competition_folder_name
    and td.season = c.season_year

order by c.competition_name, ppda asc