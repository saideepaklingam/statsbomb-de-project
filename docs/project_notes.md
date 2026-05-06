# Football DE project: my notes

StatsBomb open event data into a Bronze, Silver, Gold pipeline. Power BI dashboard at the end.

Stack: Python with statsbombpy, DuckDB, dbt Core, Power BI.
Scope: 3 competitions (FIFA World Cup 2022, UEFA Euro 2024, Copa America 2024). 147 matches, 522,815 events.

---

## 1. Scoping decisions

### 5 tools, not 7

Started this with 7 tools in my head. Wanted Airflow, Spark, Streamlit, the works. Felt like more tools meant more "real DE". Then I had to ask myself, am I actually going to USE Airflow for 147 matches? No. Is Spark needed for 500k rows? Also no. Was I just stacking tools to look serious on a CV?

Yeah, basically.

So I cut to Python, DuckDB, dbt, Power BI, statsbombpy. Five things, each doing real work. The voice in my head saying "but Spark looks better on a resume" had to lose this one. If a senior engineer asks me why Spark on 12MB of data, I have no answer except "the rubric said variety". That is not an answer.

### 3 competitions, not 1

First plan was just one tournament. Easier scope, faster build, cleaner story. Then I sat with it and realised, what cross-comparison question can I answer with one tournament? None. "How does a team adapt across formats" needs more than one format. "Which league style produces highest xG per shot" needs leagues. One tournament is just a 64-match snapshot.

So three. World Cup, Euro, Copa. Different regions, different tactical cultures. More work, much better project.

### Copa America over the Women's World Cup

This one I argued with myself the most. Women's World Cup data is excellent quality, well-covered, would have been a great inclusion. But the question I kept asking was: do I want to compare like-for-like, or do I want to flex inclusivity?

If I add WWC, every cross-tournament metric needs disclaimers. "France men attacked at X xG/match while France women attacked at Y" — those numbers do not mean the same thing. Different game speed, different tactical patterns, different sample of teams. Mixing them in headline metrics would be lazy at best, misleading at worst.

So Copa America 2024 instead. Same gender, same format style, comparable game speed. Cleaner analysis. The tradeoff was a less inclusive dataset. Made my peace with it.

### 6 Gold marts, 11 questions parked

Original list had 12 tactical questions. Reading them back, half were framed like I was a coach planning the next match. "How should we exploit X opponent's left flank?" That voice does not fit public open data. There is no "we". Rewrote them as analyst questions. What can the data show? Not what should a team do.

Cut the list down to 6. The other 11 went to a "future work" section. Felt bad cutting them at the time but in hindsight, 6 marts done well is way better than 17 marts done badly.

The 6:
1. Team attack quality
2. Team ball progression
3. Team defensive pressure
4. Team set-piece effectiveness
5. Player impact
6. Team-match-gamestate behaviour

---

## 2. Bronze layer

Output: `data/bronze/competition=X/season=Y/match_id=Z/` with three files per match: `events.parquet`, `lineups.parquet`, `match_metadata.parquet`.

Final count: 443 files, 147 matches, no failures. Second run skipped everything in under a second. Idempotency confirmed.

### Design decisions

Hive-style partitioning. Folder names become filterable columns automatically. Portable across engines. Easy decision.

`match_id` as folder name. This one I actually thought about for a bit. The number is meaningless to me as a human. I wanted to use something readable like team names plus date. Then I caught myself: that is exactly the natural-key trap. Team names can change (renamed federations), dates can collide (two matches per day in tournaments). Surrogates are boring but stable. So `match_id` won.

One folder per match. Argued with myself here too. Knew it would create more small files than strictly needed. But every alternative meant losing per-match isolation. If one match's data got corrupted in a re-pull, I want only that folder rebuilt. Not the whole competition. Boring is correct.

Flattening coordinates in Bronze, keeping other nested fields for Silver. Did genuinely flip on this. Option A was to leave everything nested and let Silver flatten. Option B was to flatten only `*_location` columns in Bronze and leave the truly complex stuff (`shot_freeze_frame`, `tactics`) for later. Picked B. Reasoning: spatial work is the most common kind of analysis I will do, so making Bronze query-ready for x/y is worth it. The complex nested stuff has too much semantic depth to flatten without losing meaning.

### 5 Bronze failures and what they taught me

1. Python 3.14 had no wheels for scientific libs. Created a `football` conda env on Python 3.11. Lesson: check Python version before trusting a pip install.

2. Script ran, produced nothing, no logs. Was staring at the screen for a while wondering why nothing was happening. Turns out `logging.basicConfig` is a no-op if another library already touched the root logger. Fix was `force=True`. Annoying. Lesson: silent logs mean suspect logger state, not your code.

3. `'dict' object has no attribute 'to_parquet'`. `sb.lineups()` returns a dict keyed by team name, not a DataFrame like the rest of the API. Caught me off guard because every other statsbombpy function returns DataFrames. Wrote a `flatten_lineups` helper. Lesson: never assume two functions in the same library return the same shape.

4. Fix did not take effect. New code, old behaviour. Spent 20 minutes thinking I had not actually saved the file. Was a stale `__pycache__` running old bytecode. Cleared it, fix worked. Lesson: when fresh code behaves like old code, kill caches before doubting yourself.

5. PowerShell mangled Python code I pasted into the shell. Quotes got rewritten, escapes broke. Lesson: PowerShell is not the Python REPL is not a `.py` file. Know which shell you are in.

---

## 3. Silver design and build

### Three locked decisions

**Silver lives inside `warehouse/football.duckdb` as native DuckDB tables, not Parquet.** Initially leaning towards keeping Silver as Parquet for portability. Then I asked myself, who is going to query Silver? Me, through dbt. Power BI later. Both work better with a native warehouse. Parquet on disk would mean schema-on-read every single query. DuckDB tables are warmer, faster, cleaner with dbt. Done.

**One unified `stg_events` table, not split by event type.** This was a real argument. Splitting feels cleaner. `stg_passes`, `stg_shots`, `stg_pressures`, etc. Easier to reason about. But every Gold mart is going to join events to events: passes feeding shots, pressures triggering recoveries. Splitting forces unions everywhere downstream. One wide table is uglier in the abstract but cheaper to query. Picked the practical option.

**All type and boolean cleanup at Silver, not Gold.** No real argument here, just standard practice. Silver is the cleaned truth layer. Gold should not be doing `COALESCE(under_pressure, false)` 50 times.

### Four staging tables

- `stg_events` (522,815 rows, 104 cols)
- `stg_matches` (147 rows, 52 cols)
- `stg_competitions` (3 rows, 6 cols)
- `stg_lineups` (7,449 rows, 11 cols)

Built with `dbt run --select staging` in about 4 seconds total.

Originally had a fifth model planned: `stg_match_metadata`. Then I realised it was redundant with `stg_matches`. Same grain, same source. Cut it. Less is more.

### Schema sparsity lesson

`inspect_bronze.py` showed 102 cols on one match. I assumed that was the schema. Built the dbt model. It crashed because another match had different columns. `pass_straight`, `shot_aerial_won` were missing from some files. Sat there annoyed for a minute thinking it was a dbt bug.

It was not. StatsBomb writes sparse schemas. A column only exists in a match's Parquet if that event type happened in that match. Added `union_by_name = true` to `read_parquet`. Fixed.

Lesson: in real DE you survey N files, or you use `union_by_name`. One sample is not a schema. I will not be making this assumption again.

---

## 4. dbt setup and the smoke test journey

Installed `dbt-duckdb` into the `football` env. `dbt init` scaffolded. Fixed `profiles.yml`. Cleaned up `dbt_project.yml`.

### Errors during smoke test

1. `dbt ls` saw no model. File was named `_smoke_test.sql`. dbt's behaviour with underscore prefixes is inconsistent. Renamed without underscore.
2. `models/staging/` not found. dbt does not auto-create subfolders. Created it manually.
3. Path resolved differently from Python vs dbt. I had `../../data/bronze/...` in SQL. Relative paths in views resolve at QUERY TIME, not creation time. From dbt project folder, `../../` worked. From project root running Python, it did not. Switched to a variable in `dbt_project.yml`.
4. `dbt run` failed opening warehouse path. I had run dbt from `models/staging/` instead of the project folder. `dbt-duckdb` resolves `path:` relative to current working directory. Same exact failure pattern as #3, different relative path. Switched to absolute path.

### The lesson

Relative paths are time bombs. They work from one directory and break silently from another. I kept thinking each error was unique. By the second one I realised they were the same problem in different costumes. Moved everything to absolute paths or variables that resolve to absolute paths. Have not had a path issue since.

---

## 5. Gold Mart 1: Team attack quality

72 rows. Penalties excluded. Open play = `Regular Play` + `From Counter` + `From Kick Off`. Set piece = `From Corner` + `From Free Kick`.

Top of `xg_per_match`: Germany, Brazil, Argentina, Portugal. Tournament winners (Spain, Argentina) near the top. Eye test passed.

### Why penalties are excluded (long debate with myself)

Started by including penalties. Standard scoring event, why exclude them? Then I looked at the data. A team that gets one penalty gets a 0.76 xG boost from a single moment of contact. That moment had nothing to do with attacking quality. A foul produced the chance.

Then I thought: but corners and free kicks are also "produced" by something else, no? Aren't I being inconsistent if I keep those in?

Sat with that. Realised the difference. A corner that ends in a header requires creation under pressure: delivery quality, runs, aerial duels, second-ball recovery. A penalty is uncontested. The shooter places it. The keeper guesses. Different attacking processes.

So penalties out, set pieces in. Took longer than it should have to settle this.

---

## 6. Gold Mart 2: Team ball progression

72 rows. Built in 0.28s.

Definitions: progressive = forward gain ≥ 10m AND end_x ≥ 80. Final third = x ≥ 80.

Eye test: Spain, Germany, Portugal lead progressive passing. Costa Rica, Romania, Slovenia lowest completion. Reasonable.

The "10 metres" threshold I went back and forth on. Some analytics shops use 25% of remaining distance. Others use absolute thresholds. Settled on absolute because it is easier to defend in an interview. "Why 10 metres" has a cleaner answer than "why 25% specifically".

### Bug I caught

Dropped `location` from the events CTE but referenced `location[1]` again in a downstream CTE. Failed with "column not found". Fix was to extract `start_x` once in the base CTE and use it everywhere. DRY from the first CTE. Lesson learnt.

---

## 7. Gold Mart 3: Team defensive pressure

72 rows.

PPDA custom definition: opp passes in their own 60% / (my pressures + tackles + fouls in opp's own 60%). Zone: my actions at x ≥ 48, opp passes at their x ≤ 72.

Did NOT match Opta's PPDA exactly because StatsBomb has no clean `Interception` event type. Spent a while trying to figure out if I should pretend I had one (mapping from `Duel` and `Ball Recovery`) or just adapt the definition. Adapted it. Wrote it down in the SQL comments. If anyone asks "why is your PPDA different from FBref", I have an answer.

### Eye test had a moment

Austria, Uruguay, Spain, Germany at the top with low PPDA. Made sense. Then Morocco showed up with a high PPDA of 4.75 and I almost flagged it as a bug.

But Morocco at WC 2022 played a low block. They sat deep, let opponents pass around them, then countered. That is a high PPDA by definition. The number is correct. The label "passive" is misleading. PPDA tells me about press intensity, not defensive quality. Two different things.

Wrote it in the notes properly because if I had not caught myself, I would have spent an hour "fixing" code that was right.

### Bug

Tried `start_x := location[1] as start_x` syntax. DuckDB rejected it. Plain `as` alias worked. Lesson: stop being clever with SQL. Boring idioms are universal idioms.

---

## 8. Gold Mart 4: Team set-piece effectiveness

72 rows. Full-chain definition via `play_pattern` filter.

Decision argued with myself for a while: first-shot-only vs full possession chains. First-shot is easier to compute. Full chains capture second balls, recycled crosses, sustained pressure. Real attacking value lives in the chains.

Picked full chains. Then realised StatsBomb makes this trivial because `play_pattern` is inherited across the whole possession. Filtering on `play_pattern IN (...)` automatically captures the full chain. The data model did the work I was bracing to do manually. Felt like getting something for free.

### Findings

- Morocco 67.8% set-piece xG share. Confirms WC 2022 tactical identity (dead-ball reliant). Real and visible.
- Italy 79% share at Euro 2024. Could not create open-play chances. Got knocked out by Switzerland. Numbers tell the story.
- Germany WC 2022: highest sp_xG/match (1.14), 0.029 conversion (1 goal from 35 shots). Generated chances, wasted them. Plausible factor in group-stage exit.
- Uruguay 8 goals from 56 set-piece shots. Good delivery, tall squad, Bielsa's set pieces.

### Throw-ins debate

Should they count as set pieces? Some football analysts argue no, throw-ins are mostly defensive resets. Others argue yes, some teams use long throws as weapons (Brentford historically, Liverpool under Klopp).

Picked yes. Reasoning: my "full chain" approach already filters out the routine throw-ins because they do not start meaningful possessions. Teams that DO use long throws will show up. The noise is bounded. Not perfect but defensible.

---

## 9. Gold Mart 5: Player impact

633 player-seasons (≥ 270 min filter).

Minutes computed from UNNEST of `stg_lineups.positions`. MM:SS to seconds to minutes. xA via self-join: events on `pass_assisted_shot_id = event_id`.

This was the hardest mart up to this point because of minutes-played. The `positions` field is a list of dicts per player per match. Each dict is a segment with `from`, `to`, `from_period`, `to_period`. Substitutions create new rows. Tactical shifts create new rows. Extra time creates more periods.

Spent a while trying to get this right. Edge cases:
- Null `to` (player on at full time). Used a 120:00 fallback. Slight over-count but bounded.
- Period transitions. StatsBomb stores minute/second per-period, not cumulative. Had to add period offsets.
- Players who never came off in ET matches. Same fallback.

It is approximate. Within 2-3% of true minutes. Documented the approximation.

### 270-minute filter

Argued with myself on the threshold. 180 (2 matches) is more inclusive but per-90 stats below that are noise. 360 (4 matches) is more stable but excludes too many tournament players. 270 is 3 matches' worth. Felt like a fair middle.

### GK handling decision

Goalkeepers will pass the minutes filter easily but be near-zero on most metrics. Two options: filter them out in SQL, or include them with a `primary_position` column and let the dashboard filter.

Picked the second. Reasoning: filtering GKs in SQL is opinionated. Some users might want to see GK metrics for sweeper-keepers. Keeping them in preserves data. Dashboard can filter.

### Findings worth holding onto

Lautaro top xG/90 in BOTH Copa (5 goals, overperformed) AND WC 2022 (0 goals, 0.64 xG/90, underperformed massively). Same player, two tournaments, totally opposite outcomes. The grain decision (player, team, comp, season) made this contrast visible. If the grain were (player, team), they would average and the contrast would vanish. Felt good when I noticed this.

Messi at Copa 2024: scoring dropped, assisting went elite. Role shift in the numbers.

Pressing leaderboard dominated by forwards (Álvarez, Morata, Wirtz). Modern pressing starts with the #9. Not surprising but nice to see it confirmed.

Top carriers: Dembélé, Musiala, Doku, Kvaratskhelia, Di María. Elite-winger list. Eye test passed strongly.

---

## 10. Gold Mart 6: the bug story

This sequence is the one I keep coming back to.

### Initial build

553 rows. Approach: walk each team's event stream. Duration of each event = time until that team's NEXT event. Aggregate by state.

Looked plausible. Eye test passed. Headline finding: avg field position 54.4 (Winning) → 56.6 (Drawing) → 60.6 (Losing). Made sense. Teams push higher when chasing. Beautiful.

I would have shipped this. That is the scary part.

### dbt test caught a real bug

Wrote a custom singular test, `tests/game_state_symmetry.sql`. Asserted an invariant:

> For every match, total minutes home team spent "Winning" must equal total minutes away team spent "Losing".

It HAS to hold. Same time slice from two perspectives. If they differ, something is wrong.

Test failed on 122 of 125 matches. Average diff was 26 minutes. Max diff was 65 minutes. A football match cannot have one team winning for 30 more minutes than the other team is losing.

Sat with that for a minute. Wanted it to be a test bug. Wanted to write off the failure as rounding noise. Diagnostic showed it was not. Real bug, real magnitude.

### Root cause

Walking each team's event stream meant the team with denser events got more total duration attributed. Spain has more events per match than Saudi Arabia in the same match. So when Spain was winning, they accumulated "winning duration" faster than Saudi Arabia accumulated "losing duration". Asymmetric by design. I just had not seen it.

### Fix

Rebuilt as interval-based. Match split into score-segments at goal events. Each segment owns a duration. Both teams share the same partitioning. Only the state labels mirror. Symmetric by construction.

Took a real chunk of time to write. Eight CTEs, interval joins, union all for state expansion. The interval-based approach is fundamentally a different way of thinking about the problem. The first version was "walk events, attribute time". The second is "carve match clock into intervals, attribute events to intervals". Decoupling time from events was the move I had not seen the first time.

### Result

Before: avg diff 26.4 min, max 64.8 min, 4 of 125 matches symmetric within 1 min.
After: avg diff 0.0 min, max 0.0 min, 125 of 125 matches symmetric within 1 min.

All 36 dbt tests pass.

### Findings after re-validation

The headline finding HOLDS. Avg field position 54.3 (Winning) → 56.2 (Drawing) → 60.5 (Losing). Almost identical to before the fix. This was a relief.

The reason it held: the bug was in duration accounting, not event classification. Per-event averages were always correct. The buggy denominator did not affect them. Got lucky.

A new finding emerged though. Avg xG/min is HIGHER when winning (0.0154) than losing (0.0076). This is the opposite of what I would have guessed. Naive intuition says losing = desperate = more xG. Wrong on average. Losing teams face packed defences. Winning teams attack on transition with space. Real insight, not visible until the durations were correct.

Distribution: Winning 142 = Losing 142. Mathematically guaranteed by the fix.

Top score-chasers shifted: Brazil WC22 (0.050), Czech Republic Euro24 (0.025), Georgia Euro24 (0.019). Uruguay was #1 with the buggy data and dropped off completely after correction. Buggy data was telling me a story that was not real.

### What I actually learned

The original numbers looked plausible. Eye test passed. Without the symmetry assertion I would have shipped a broken mart and never known. The numbers all fit a story I wanted to believe.

This is the lesson I keep coming back to. Programmatic invariants are not optional. Eye tests are not enough. If a mathematical property must hold, write it as a test. The test is the only thing that catches you.

---

## 11. Final state

### Warehouse

```
warehouse/football.duckdb
├── stg_events          (522,815 rows)
├── stg_matches         (147 rows)
├── stg_competitions    (3 rows)
├── stg_lineups         (7,449 rows)
├── mart_team_attack_quality          (72 rows)
├── mart_team_ball_progression        (72 rows)
├── mart_team_defensive_pressure      (72 rows)
├── mart_team_set_piece_effectiveness (72 rows)
├── mart_player_impact                (633 rows)
└── mart_team_gamestate_behavior      (568 rows)
```

### Tests

36 dbt tests, all passing. 1 custom singular test that found a real bug.

### Pending

Power BI dashboard.

---

## 12. Things to remember for interviews

### Design decisions and the why behind each

Why flatten coordinates in Bronze? Bronze becomes query-ready for spatial work without forcing downstream to know nested structure. Trade-off was accepting one round of work upfront vs every Silver model doing the same work.

Why surrogate keys? Stability. Natural keys (team names, dates) can change and collide. Argued myself out of using readable keys.

Why Hive partitioning? Portable across engines. Folder names turn into filterable columns automatically. Standard pattern.

Why one unified `stg_events`? Gold marts constantly join events to events. Splitting forces unions everywhere. Picked practical over clean.

Why DuckDB? Single file, no schema-on-read cost, native dbt integration, fast columnar in-process. The right size for 500k events.

Why dbt over plain SQL? DAG via `ref()`, tests, docs, lineage, version control. All the things plain SQL forces you to build manually.

### Football-domain reasoning to defend

Penalty exclusion: awarded event, not created event. Penalty xG of 0.76 is standardised setup, not skill.

PPDA custom definition: adapted because StatsBomb has no clean `Interception` event type. Same direction, different absolute numbers from Opta. Documented.

Per-90 normalisation: football-analytics standard. Minutes vary 270 to 840 across players in this dataset.

270-min filter: trade-off between sample stability and inclusion. Cameo players dropped on purpose.

### Honest limitations to own up to

Minutes are approximate (120:00 fallback for null `to`). Within 2-3% for most players.

xG overperformance is descriptive, not predictive at this sample size. Reported but not used for forecasting.

PPDA does not match Opta numerically. Same direction, different scale.

270-min filter excludes cameo players. Intentional.

---

## 13. Honest critique I was given

These hit. Writing them down because I do not want to forget them.

7-tool stack was greedy. Real DE uses fewer tools well. I knew this on some level but was stacking tools to look serious. Cut to 5.

"Our team" voice did not fit public data. There is no "we" in StatsBomb open data. Had to rewrite the question framing. Should have caught this myself.

Original architecture diagram lied. Showed Understat, Airflow, ADLS, Streamlit, ML, none of which I built. A diagram that does not match the build is worse than no diagram. Fixed before publishing.

I kept skipping reps by asking for code to be written for me. The Bronze debugging journey already proved I could handle hard problems. I was underselling my own capability to take the easier path. The harder path was always available, I was just avoiding it.

"Starting over" is a junior engineer's favourite fantasy. Real engineering is finishing ugly things, not restarting pretty ones. I asked to start over once. Got pushed back on hard. Glad I did not actually do it.

Asking "what's next" instead of designing the next mart is outsourcing. The marts are where the engineering judgement lives. SQL is the easy part. Got told this directly. It stung because it was true.

---

## 14. The arc that matters

Started this project asking for code to be handed to me. By Mart 5 I was drafting designs with real engineering judgement (the 270-min filter, GK handling, the explicit minutes-played acknowledgement). By Mart 6 I was reading my own validation outputs and noticing where the numbers smelled off.

The 36 of 36 test pass on the corrected Mart 6 is the real milestone. Not because the code works. Because programmatic invariants in production data work are now genuinely internalised, not just memorised.

If I had to name one thing that changed: I stopped trusting plausibility. Numbers can look right and be wrong. Tests are the only thing that catch you.

---

## 15. Power BI started, ODBC didn't

After the marts were done I had everything sitting in DuckDB and no way to actually show it to anyone. Time to figure out Power BI.

First plan was to connect Power BI directly to DuckDB. Live connection, sounded right, sounded like what a real DE would do. Spent some time reading. The DuckDB ODBC driver has issues with Power BI. It silently falls back to in-memory mode when you give it a database file path, so the warehouse tables just don't show up. Community workaround uses an extra Power Query custom connector layer. Three things to install, none of them straightforward.

Stopped and asked myself what I was actually trying to solve. The data is not changing. Why am I solving live refresh when I do not have a live problem?

Picked the boring option. Wrote `scripts/export_to_parquet.py` that exports each Gold mart to a Parquet file. Power BI reads Parquet natively. Five minute setup, no driver pain. Did the job.

The "real production" way was ODBC. The right way for this project was Parquet. Different things. I tried to reach for the production tool first and almost wasted an hour on it.

## 16. The composite key headache

First time I tried to set up a relationship in Power BI, it errored out immediately. "Column 'team_name' contains a duplicate value 'France'."

Of course it does. France played both WC 2022 and Euro 2024. France-WC and France-Euro are two rows in my dimension table. The team name alone collides.

Fix was a composite key. `team_name || '|' || competition_folder_name || '|' || cast(season_year as varchar)`. Looks ugly but it is unique by construction. Like `Argentina|Copa_America_2024|2024`.

Had to add this column to the dimension table AND every single Gold mart. Then rebuild dbt. Then re-export everything to Parquet. Then refresh Power BI.

Should have built this column into the marts from the beginning. I was thinking about marts as standalone things, not as inputs to a dashboard. By the time I started thinking about relationships it was already retrofit time. Annoying.

## 17. The DAX measures moment

Page 2 needed a small comparison view. For each metric, show the team's value AND the tournament average side by side. The slicer filters one but not the other.

This is where you have to write DAX. Power BI has its own formula language. First time I was actually doing it.

The pattern is:

```
Avg xG per Match (Tournament) = 
CALCULATE(
    AVERAGE(mart_team_attack_quality[xg_per_match]),
    ALL(mart_team_attack_quality)
)
```

The `ALL()` is what makes it work. Without it, the slicer would filter both the team value and the average. They would always be equal. With `ALL()`, the average ignores the filter and stays constant across all 72 rows.

Took me a few tries to figure out which mart each measure belonged to and what the column name was exactly. Got there.

The first time I dropped a measure into a card and saw the team value (1.43 for England) sitting next to the tournament average (1.10), and they actually filtered properly when I clicked Spain in the slicer, that was a real moment. Felt like the pipeline I built was finally driving an interactive thing instead of just sitting in a warehouse.

## 18. Finding 4 fought me for an hour

Page 5 has 5 finding cards. Findings 1, 2, 3, 5 went smoothly. Finding 4 was hell.

The original Finding 4 was about final-third entries vs shot conversion. I wanted to show 4 specific teams (Spain WC, Spain Euro, Denmark WC, Germany Euro) with different conversion rates. The chart kept showing all 4 bars at exactly 0.15.

Tried everything I could think of. Checked the data with SQL, numbers were correct (0.131, 0.207, 0.221, 0.109). Verified the filter was set right, it was. Verified the X-axis aggregation was Average, it was. Looked for stale filter state, found one leftover from an earlier attempt, removed it. Tried different field combinations. Tried `team_comp_key` directly. Tried nested `team_name` + `competition_name` on the Y-axis. Tried clicking the expand-down icon on the visual.

Nothing worked. Bars stayed at 0.15.

After 30 minutes I gave up and replaced the finding entirely. Picked Argentina vs France xG vs trophies as the new Finding 4. Argentina won Copa with 11.34 xG, scored 9 goals, underperformed by 2.34. France lost the WC final but generated 10.25 xG and scored 14 goals, overperformed by 3.75. Two teams, simple bar chart, built in 5 minutes.

The replacement is actually a better finding. "Trophies do not follow xG totals" is sharper than "F3 entries does not equal conversion".

I was so locked in on making the original chart work that I forgot the original finding was not even that interesting. When something fights you for an hour, sometimes the thing you are fighting is the wrong thing.

## 19. Position grouping for the slicer

Page 3 needed a position slicer. Mart 5 has 23 distinct positions because StatsBomb separates Right Center Back, Left Center Back, and Center Back as three different positions. Same role in real football. A slicer with 23 entries is unbrowsable.

Built a calculated column in Power BI called `position_group`. Used CONTAINSSTRING to fold the 23 granular positions into 8 buckets. Goalkeeper, Center Back, Fullback, Defensive Mid, Central Mid, Attacking Mid, Winger, Forward.

```
position_group = 
SWITCH(
    TRUE(),
    mart_player_impact[primary_position] = "Goalkeeper", "Goalkeeper",
    CONTAINSSTRING(mart_player_impact[primary_position], "Center Back"), "Center Back",
    ... etc
)
```

Slicer uses `position_group`. Player table still uses the original `primary_position` for detail.

I went back and forth on whether to do this rollup in dbt or in Power BI. Doing it in dbt means it lives in the warehouse and is available to anyone querying Mart 5. Doing it in Power BI keeps it close to the slicer that uses it.

Picked Power BI. Reason: this rollup is a dashboard choice. A different consumer of Mart 5 might want different groupings (maybe they want all backs grouped, not just fullbacks). Keeping the granular positions in the warehouse and rolling up at the consumption layer is more flexible. If I had multiple dashboards using the same rollup, I would push it down to dbt.

## 20. The ML thing I tried

Rubric said ML is optional. I was on the fence about doing it. Decided to try because the data is sitting there and it would be an interesting interview talking point if it worked.

Picked tournament outcome classification. Three classes: group-stage exit, knockout pre-final, finalist. Features came from the 4 team-grain Gold marts. 17 features per row, 72 rows total.

Built `scripts/build_team_outcomes.py` to derive the outcome class from `stg_matches.competition_stage_name`. Built `scripts/build_ml_dataset.py` to join the labels with mart features. Built `scripts/train_outcome_model.py` to actually train the models.

Ran it. Results were not great:

- Baseline (just predict the majority class for everything): 0.472
- Logistic Regression: 0.511 with std dev 0.088
- Random Forest: 0.468 with std dev 0.169

Both models are basically tied with baseline. The Random Forest was actually slightly worse.

Sat there for a minute disappointed. Then thought about it.

The problem is not the model. The problem is the data. 72 rows is small for ML, especially with 17 features. And the data has hard contradictions inside it. Germany at WC 22 had the highest xG per match (2.48) of any team in the dataset. They got eliminated in the group stage. England at Euro 24 had xG per match of 0.83 and made the final. No model is going to learn from contradictions like that with 72 rows.

The feature importance from Random Forest was still interesting though. Set-piece conversion rate ranked first (0.148). xG per match ranked fourth (0.074). That actually makes sense. Aggregate xG is noisy at small samples because finishing variance washes it out. Set-piece situations are more standardized (corner deliveries, free-kick routines) so a team's set-piece coaching shows through more consistently across 5-7 matches.

Wrote the whole thing up in `docs/ml_results.md`. Honest framing. Called it a "feature exploration project" rather than pretending it was a working classifier. The model failing is the actual finding.

I considered tweaking it. Could have dropped the Finalist class to make it 2-class and probably gotten to 60% accuracy. Did not do it. Felt like that would be massaging the number rather than reporting what the data actually shows.

I wrote down the interview answer ahead of time so I would not forget it:

> "Built a small classifier on tournament outcomes using 17 Gold mart features. With 72 team-tournaments the model could not beat baseline. The experiment was useful as feature exploration. The importance ranking put set-piece conversion ahead of xG per match, which fits the idea that aggregate xG totals are noisy at small samples while standardized set-piece situations are more stable. To do this properly I would need club-season data alongside tournament data, which the StatsBomb open dataset does not include for current squads."

Honest about the failure, useful about what it suggests, clear about what would fix it.

## 21. Where I am now

Looking back, the trajectory of this project matters more than any individual artifact.

I started this asking for code to be handed to me. By Mart 5 I was drafting designs with real engineering judgement. By Mart 6 I was reading my own validation outputs and noticing where the numbers smelled off. By the dashboard I was making real call between ODBC and Parquet, picking it deliberately. By the ML attempt I was reporting honest failure instead of pretending.

The Mart 6 bug story is what I will lead with in interviews. Programmatic invariants caught what eye test missed. That is a lesson I will carry forward.

The DAX measures on Page 2 felt like crossing a small threshold. First time writing DAX. The composite key. The `ALL()` function. The moment the team-vs-average comparison started filtering correctly.

The Finding 4 chart that I bailed on. Knowing when to switch the question is its own skill. I kept trying to make a chart work when the chart was downstream of a finding that was not that interesting in the first place.

The ML model that failed. Defensible failure beats undefensible success. Owning the limits of the data is the right move at small samples.

The thing that actually changed in me by the end. I stopped trusting plausibility. I started saying "the model failed" instead of trying to massage the number. I started owning trade-offs in writing instead of glossing over them.

Not the pipeline. The way I think about pipelines.