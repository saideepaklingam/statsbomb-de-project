\# Dashboard walkthrough



The dashboard sits on top of the StatsBomb pipeline. 5 pages, 3 tournaments, 147 matches, 522,815 events.



This file explains what each page shows and why it shows it that way. If you only have a minute, jump to Page 4. That one carries the strongest finding in the project.



\---



\## How the dashboard is built



Power BI Desktop is the front-end. The data sits in 6 Parquet files exported from the DuckDB warehouse. One Parquet per Gold mart, plus one small dimension table holding team and competition info.



The dimension table has a column called `team\_comp\_key`. It looks like `Argentina|Copa\_America\_2024|2024`. Every Gold mart also has this column. Power BI uses it to link tables. Without this key, France appearing in both World Cup 2022 and Euro 2024 would confuse the relationship logic, because France-WC and France-Euro are not the same row.



Two slicers are synced across all pages: tournament and team. Page 3 has a third slicer for player position. Page 5 has no slicers because the findings are fixed.



\---



\## Page 1: Tournament Overview



Title on the page: \*Who attacks well, who presses hard, who relies on set pieces?\*



The first page someone sees, so the goal here is breadth. All 3 tournaments visible. No drilling yet.



Four visuals in a 2x2 grid.



The xG vs Goals scatter at the top-left. Each dot is one team in one tournament, colored by tournament. Hover any dot to see the team. Teams above the diagonal scored more goals than their xG suggested. Teams below underperformed.



The set-piece xG share bar chart at the top-right. Top 12 teams shown. Italy at Euro 24 sits at the top with 0.79. That means 79% of Italy's expected goals came from set pieces. They could not create from open play.



The final-third entries chart at the bottom-left. Top 12 again. Spain at Euro 24 leads with 94 entries per match.



The PPDA leaderboard at the bottom-right. Top 15 by lowest PPDA. Lower means more intense press. Uruguay at Copa is at the top with 2.29.



One thing about PPDA worth flagging. PPDA tells you how often a team presses. It does not tell you if their defense is good. Morocco at WC 22 had a high PPDA, which usually reads as "passive". They were not passive. They were sitting in a low block on purpose. Same number, different meaning depending on the team's tactical setup.



\---



\## Page 2: Team Profile



Title on the page: \*How does this team actually play?\*



Page 1 was for browsing. This page is for drilling. Pick one team in the slicer and the entire page updates to that team.



Top of the page has 4 KPI cards. Matches played, xG per match, PPDA, set-piece xG share. The big numbers a hiring manager scans first.



Below that on the left, a grid of 6 small comparison cards. Each card shows one metric, two numbers stacked. The team's value, then the tournament average. So you can tell at a glance whether the team is above or below average on each metric.



The 6 metrics are xG per match, progressive passes per match, final-third entries per match, PPDA, counterpress share, and set-piece xG share.



The comparison logic uses DAX measures. Each measure ignores the team filter on the dashboard so the average is calculated across all 72 team-tournament rows, while the team value uses the filter. Built like this:



```

Avg xG per Match (Tournament) = 

CALCULATE(

&#x20;   AVERAGE(mart\_team\_attack\_quality\[xg\_per\_match]),

&#x20;   ALL(mart\_team\_attack\_quality)

)

```



The `ALL()` part is what makes it work. Without it, the slicer would filter both numbers and they would always match.



On the right of that section, a matrix table. Rows are tournaments, columns are key metrics. So if you select Spain, you see Spain at WC 22 and Spain at Euro 24 side by side. Useful for teams that played in 2 tournaments.



This matrix gave me one of my favorite findings in the project. Spain at WC 22 had 107 final-third entries per match. Spain at Euro 24 had only 81. But Spain converted at Euro 24 (xG/match 1.51) much better than at WC 22 (xG/match 0.99). Same team, different tournaments, very different output. Without the matrix, this would have been hidden behind averaged numbers.



I started Page 2 with a radar chart. Switched to small bar grids halfway through. Radar charts look fancy but the area enclosed depends on the order of metrics, so different orderings give different shapes for the same player. Senior reviewers know this. Small bars are honest.



\---



\## Page 3: Player Impact



Title on the page: \*Which players drive their teams?\*



The grain shifts here, from team to player. 633 players total after filtering anyone with under 270 minutes. Below 270 minutes, per-90 stats are noise.



On the left, a scatter of npxG/90 vs xA/90. Each dot is one player-tournament. Color by position group. The top-right corner is where the best contributors sit (high goal threat AND high creativity).



On the right, a position breakdown bar chart. Count of players in each position group.



At the bottom, the top 30 players table. Sortable. Shows per-90 metrics, total minutes, position.



The position slicer needs explaining. The mart had 23 distinct positions because StatsBomb tags Right Center Back, Left Center Back, and Center Back as 3 different things, even though they are the same role. I built a calculated column called `position\_group` that rolls these into 8 buckets: Goalkeeper, Center Back, Fullback, Defensive Mid, Central Mid, Attacking Mid, Winger, Forward. The slicer uses this. The detail table still shows the original granular position because someone might want to see "Right Wing Back" specifically.



The page hides goalkeepers in plain sight. They pass the 270-minute filter easily because they play full matches, but they score zero on most attacking metrics. So they cluster near the origin of the scatter. I kept them in the data on purpose. Filtering them out at the SQL layer would have been opinionated. Some users might want to see GK metrics for sweeper-keepers.



The single best player by npxG+xA/90 is Lautaro Martinez at Copa 2024. 0.81 npxG/90, 0.00 xA/90. Pure poacher. The same player at WC 22 had 0.64 npxG/90 and underperformed massively (5 shots, 0 goals). Two tournaments, opposite outcomes for the same player.



Messi at Copa 2024 sits second-row in the scatter. npxG/90 of 0.34, xA/90 of 0.29. Modest as a finisher, elite as a creator. Different role from his peak years.



\---



\## Page 4: Game State Analysis



Title on the page: \*How does the scoreline reshape behaviour?\*



This is the hero page. The strongest analytical work in the project sits here.



The hero chart at the top. 3 bars showing average field position when winning, drawing, losing. The numbers are 54.3, 56.2, 60.5. When teams are losing, they push 6 metres higher up the pitch on average. The Y-axis starts at 50 instead of 0 so the gap between the bars is visible. If the axis started at 0 the bars would all look about the same height and the finding would be invisible.



Below the hero, two supporting charts. On the left, a line chart with 6 teams (the deepest tournament runs). One line per team showing how their field position changes across the 3 game states. Every line slopes up and to the right. Same effect, visible at the team level.



On the right, the top score-chasers bar. Brazil at WC 22 at the top with 0.080 xG/min when losing. Highest in the dataset. Brazil 2022 was lethal in transition.



At the bottom of the page, a small box of text. The counter-finding. Teams push higher when losing, but they do not necessarily generate more xG when losing. Naive intuition says losing equals desperate equals more xG. The data says otherwise. xG/min is actually higher when winning. Why? Losing teams face packed defenses. Winning teams attack with space on transitions.



The mart that powers this page (mart\_team\_gamestate\_behavior) almost shipped with a serious bug. The original version walked each team's event stream and computed durations between consecutive events. The team with denser events got more total duration attributed. So when Spain was winning, they accumulated "winning duration" faster than Saudi Arabia accumulated "losing duration". Asymmetric by design, even though I did not see it.



A custom dbt test caught it. The test asserted that for any match, Team A's "Winning" minutes must equal Team B's "Losing" minutes. Same time slice from two perspectives. The test failed on 122 of 125 matches. Average gap was 26 minutes.



I rebuilt the duration logic to slice the match clock at goal events instead. Both teams share the same partition. The test now passes on 125 of 125 matches. The headline finding (54.3, 56.2, 60.5) held after the fix because the bug was in duration accounting, not in event classification.



If anyone asks me about the project in an interview, this is the story I lead with. The original output looked plausible. Eye test passed. Only the symmetry test caught it.



\---



\## Page 5: Key Findings



Title on the page: \*Recap: five things this dashboard answered\*



The closing page. Five findings stacked top to bottom. Each row has text on the left and a small chart on the right. No slicers, because the findings are fixed and tied to specific teams or players. Filtering would break the visuals.



Finding 1 covers the game state arc. Same chart as Page 4's hero, smaller version, restating the headline.



Finding 2 covers Germany at WC 22 wasting set pieces. Highest sp\_xG per match (1.14) of any team in the dataset. Scored only 1 goal from 35 shots. Three KPI numbers on a multi-row card.



Finding 3 covers Morocco's PPDA reading. The chart compares Spain (high press), Argentina (mid-press), Morocco (low block). Visual proof that high PPDA does not mean weak defense.



Finding 4 covers trophy outcomes vs xG. Argentina won Copa America with 11.34 xG and scored only 9 goals (underperformed by 2.34). France lost the WC 22 final but generated 10.25 xG and scored 14 goals (overperformed by 3.75). Outcomes do not follow chance creation totals.



Finding 5 covers Messi at Copa 24 as a creator. xA/90 of 0.29. npxG/90 dropped to 0.34.



Page 5 took 3 attempts on Finding 4 alone. The first chart kept showing 0.15 on all bars because of stuck filter state in Power BI. After 30 minutes of trying to fix it, I bailed and switched to the trophy-vs-xG comparison instead. Better finding anyway. Lesson learned: when a chart fights you for too long, consider that maybe the finding itself is the wrong one.



\---



\## What the dashboard does not show



A few things were scoped out.



No formation-adjusted metrics. Comparing 4-3-3 teams to 3-5-2 teams without adjusting for shape is a known weakness.



No opponent-strength adjustment. xG against Saudi Arabia is not the same as xG against France, but the dashboard treats them the same.



No streaming data layer. The pipeline ingests once, processes batch, ships static Parquet to Power BI. A real production system would refresh.



No ML predictions. A shot-outcome classifier or match-outcome predictor using Gold marts as features was on the wishlist. Parked for v2.



No live publishing yet. The dashboard runs in Power BI Desktop. Publishing to Power BI Service requires an account I haven't set up.



\---



\## If you only have 60 seconds



Land on Page 1, glance at the 4 visuals to get the breadth. Then skip to Page 4 and look at the hero chart. 54.3 → 56.2 → 60.5. Read the box of text below. That is the dashboard's main argument.



The other pages are for the curious. Page 4 alone justifies the project.

