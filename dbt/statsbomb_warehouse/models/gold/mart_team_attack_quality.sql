{{ config(materialized='table') }}

/* Gold mart 1: Team Attack Quality.
        Grain: (team, competition, season). Around 72 rows across 3 tournaments.
        Describes which teams create the best attacking chances and how.
*/   

-- Sources: stg_events (shots + play_pattern), stg_competitions (labels).

/* Decisions:
        Open play = Regular Play + From Counter + From Kick Off.
        Set pieces = From Corner + From Free Kick.
        Throw-ins, goal kicks, and From Keeper sit in neither bucket.
        Conscious choice, not an oversight.
*/

/* Penalties excluded from xG totals (shot_type != 'Penalty').
        Penalty xG of 0.76 reflects a standardised setup, not attacking skill.
        A team that gets fouled more should not look better at "attacking".
*/

/* xG overperformance (goals - xG) is reported but flagged.
        Descriptive at this sample size, not predictive.
        At 3-7 matches per team, regression-to-mean signal is poor.
        Used for narrative, not for forecasting.
*/

with shots as (
    -- One row per shot.
    -- excluding shot_type = 'Penalty' because penalties inflate xG and are not open-play skill.
    select
        team,
        competition,
        season,
        match_id,
        xg,
        shot_outcome,
        play_pattern,
        shot_type
    from {{ ref('stg_events') }}
    where event_type = 'Shot'
      and shot_type != 'Penalty'
),

matches_played as (
    -- How many matches did each team play in each competition?
    -- Using events, not stg_matches, because events tag the acting team directly.
    select
        team,
        competition,
        season,
        count(distinct match_id) as matches_played
    from {{ ref('stg_events') }}
    group by team, competition, season
),

team_shot_agg as (
    select
        team,
        competition,
        season,

        -- Totals
        count(*) as shots_total,
        sum(xg) as xg_total,
        sum(case when shot_outcome = 'Goal' then 1 else 0 end) as goals,

        -- Open play vs set piece split
        sum(case when play_pattern in ('Regular Play', 'From Counter', 'From Kick Off')
                 then xg else 0 end) as xg_open_play,
        sum(case when play_pattern in ('From Corner', 'From Free Kick')
                 then xg else 0 end) as xg_set_piece

    from shots
    group by team, competition, season
)

select
    -- Identity
    a.team || '|' || c.competition_folder_name || '|' || cast(c.season_year as varchar) as team_comp_key,
    a.team as team_name,
    c.competition_name,
    c.competition_folder_name,
    c.season_year,

    -- Volume
    m.matches_played,
    a.shots_total,
    round(a.shots_total * 1.0 / m.matches_played, 2) as shots_per_match,

    -- Core xG metrics
    round(a.xg_total, 2) as xg_total,
    round(a.xg_total / m.matches_played, 2) as xg_per_match,
    round(a.xg_total / nullif(a.shots_total, 0), 3) as xg_per_shot,

    -- Outcome
    a.goals,
    round(a.goals - a.xg_total, 2) as xg_overperformance,

    -- Shape of attack
    round(a.xg_open_play / nullif(a.xg_total, 0), 3) as open_play_xg_share,
    round(a.xg_set_piece / nullif(a.xg_total, 0), 3) as set_piece_xg_share

from team_shot_agg a
join matches_played m
    on  a.team = m.team
    and a.competition = m.competition
    and a.season = m.season
join {{ ref('stg_competitions') }} c
    on  a.competition = c.competition_folder_name
    and a.season = c.season_year

order by c.competition_name, xg_per_match desc