{{ config(materialized='table') }}

/* Gold mart 4: Team Set-Piece Effectiveness.
    Grain: (team, competition, season).
    Measures which teams convert dead-ball situations into sustained attacking value,
    not just first-contact deliveries.
*/

/* Set-piece possession definition:
    Any event where play_pattern is 'From Corner', 'From Free Kick', or 'From Throw In'.
    StatsBomb tags play_pattern on every event in a possession, inherited from how
    the possession started. So filtering on play_pattern automatically captures
    second balls, recycled crosses, and sustained pressure. The data model does
    the chain-tracking work I was bracing to do manually.
*/    

/* Decisions:
   Penalties excluded (shot_type != 'Penalty').
    Same call as Mart 1 and Mart 5. Penalty xG of 0.76 reflects standardised setup,
    not attacking skill. A team that gets fouled more should not look better at "set pieces".
*/

/* Throw-ins included.
    Argued with myself on this one. Some analysts cut throw-ins because most are
    defensive resets. But Brentford and Klopp's Liverpool turned long throws into real attacking weapons.
    The full-chain filter naturally excludes routine throw-ins (no possession develops) and surfaces teams that actually use them.
    Trade-off is some noise from teams that just throw long without intent.
*/    

/* Full chain over first-shot-only.
    First-shot is easier to compute. Full chains capture second balls, recycled crosses, sustained pressure. 
    Real attacking value lives in the chains.
    Made easy by StatsBomb's play_pattern inheritance.
*/

with shots as (
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
    select
        team,
        competition,
        season,
        count(distinct match_id) as matches_played
    from {{ ref('stg_events') }}
    group by team, competition, season
),

-- Set-piece-chain shot aggregation

sp_shots as (
    select
        team,
        competition,
        season,
        count(*) as sp_shots_total,
        sum(xg) as sp_xg_total,
        sum(case when shot_outcome = 'Goal' then 1 else 0 end) as sp_goals
    from shots
    where play_pattern in ('From Corner', 'From Free Kick', 'From Throw In')
    group by team, competition, season
),

-- All-shot aggregation (for set-piece SHARE of total xG)

all_shots as (
    select
        team,
        competition,
        season,
        sum(xg) as total_xg
    from shots
    group by team, competition, season
)

-- Final assembly

select
    sp.team || '|' || c.competition_folder_name || '|' || cast(c.season_year as varchar) as team_comp_key,
    sp.team as team_name,
    c.competition_name,
    c.competition_folder_name,
    c.season_year,

    m.matches_played,

    -- 1. Set-piece xG per match
    round(sp.sp_xg_total / m.matches_played, 2) as sp_xg_per_match,

    -- 2. Set-piece goals per match
    round(sp.sp_goals * 1.0 / m.matches_played, 2) as sp_goals_per_match,

    -- 3. Set-piece shot volume per match
    round(sp.sp_shots_total * 1.0 / m.matches_played, 2) as sp_shots_per_match,

    -- 4. Set-piece xG per shot (chance quality)
    round(sp.sp_xg_total / nullif(sp.sp_shots_total, 0), 3) as sp_xg_per_shot,

    -- 5. Set-piece conversion rate (finishing)
    round(sp.sp_goals * 1.0 / nullif(sp.sp_shots_total, 0), 3) as sp_conversion_rate,

    -- 6. Set-piece share of total xG (dependency indicator)
    round(sp.sp_xg_total / nullif(a.total_xg, 0), 3) as sp_xg_share_of_total,

    -- Raw totals for transparency
    sp.sp_shots_total,
    round(sp.sp_xg_total, 2) as sp_xg_total,
    sp.sp_goals,
    round(a.total_xg, 2) as total_xg

from sp_shots sp
join matches_played m
    on  sp.team = m.team
    and sp.competition = m.competition
    and sp.season = m.season
join all_shots a
    on  sp.team = a.team
    and sp.competition = a.competition
    and sp.season = a.season
join {{ ref('stg_competitions') }} c
    on  sp.competition = c.competition_folder_name
    and sp.season = c.season_year

order by c.competition_name, sp_xg_per_match desc