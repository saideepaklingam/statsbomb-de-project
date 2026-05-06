-- Singular test: for every match, a team 'Winning' should correspond to
-- its opponent 'Losing' with equal minutes. Symmetry check on Mart 6.
-- Returns rows where symmetry breaks (test fails if any rows returned).

with winning_minutes as (
    select match_id, team_name, minutes_in_state
    from {{ ref('mart_team_gamestate_behavior') }}
    where game_state = 'Winning'
),
losing_minutes as (
    select match_id, team_name, minutes_in_state
    from {{ ref('mart_team_gamestate_behavior') }}
    where game_state = 'Losing'
)
-- For each match, sum minutes in Winning across all teams and sum minutes in Losing.
-- They must be equal (within 1 minute of rounding tolerance).
select
    coalesce(w.match_id, l.match_id) as match_id,
    coalesce(sum(w.minutes_in_state), 0) as total_winning_minutes,
    coalesce(sum(l.minutes_in_state), 0) as total_losing_minutes,
    abs(coalesce(sum(w.minutes_in_state), 0) - coalesce(sum(l.minutes_in_state), 0)) as diff
from winning_minutes w
full outer join losing_minutes l
    on w.match_id = l.match_id
group by 1
having abs(coalesce(sum(w.minutes_in_state), 0) - coalesce(sum(l.minutes_in_state), 0)) > 1