\# Tournament outcome classifier: results



A small ML experiment using Gold mart features to predict how far a team gets in a tournament. Three classes: group-stage exit, knockout pre-final, finalist.



The model did not work. That is the actual finding.



\---



\## The setup



Each row in the dataset is one team in one tournament. Features come from the 4 team-grain Gold marts (attack, ball progression, defensive pressure, set pieces). 17 features per row.



72 rows, split across 3 classes:

\- 32 group-stage exits

\- 34 knockout pre-final

\- 6 finalists (3 finals × 2 teams = Argentina, France, Spain, England, Argentina again, Colombia)



I derived the outcome label from `stg\_matches.competition\_stage\_name`, taking each team's deepest stage reached per tournament.



\---



\## The models



I tried two classifiers with 5-fold stratified cross-validation:



| Model | CV Accuracy | Std Dev |

|---|---|---|

| Majority-class baseline | 0.472 | — |

| Logistic Regression | 0.511 | ±0.088 |

| Random Forest | 0.468 | ±0.169 |



Random Forest was actually worse than baseline. Logistic Regression beat baseline by 0.039, but the standard deviation of 0.088 is wider than that gap. Statistically the model was no better than guessing the majority class.



Sat there for a minute disappointed. Then thought about it.



\---



\## Why the model failed



Two reasons.



The first is sample size. 72 rows is small for ML. With 17 features the model has too much room to overfit and too little data to learn from. Rough rule of thumb says you want 10x more samples than features. I had 4x.



The second is the data itself. Germany at WC 22 had the highest xG per match (2.48) of any team in the dataset. They got eliminated in the group stage. England at Euro 24 had xG per match of 0.83 and made the final. Two rows like that confuse any classifier that uses xG as a feature.



Tournament football at this sample size is mostly luck. Bracket placement, finishing variance, one or two refereeing calls. Not aggregate team profiles. The model cannot learn signal that does not exist. No amount of feature engineering fixes "you have 72 rows".



I considered tweaking it. Could have dropped the Finalist bucket and made it a 2-class problem (group-stage exit vs progressed past groups). Probably would have got to 60% accuracy. Did not do it. Felt like that would be massaging the number rather than reporting what the data actually shows.



\---



\## What the feature importance still tells us



Random Forest did not predict well, but its feature importance ranking was interesting on its own.



| Feature | Importance |

|---|---|

| sp\_conversion\_rate | 0.148 |

| progressive\_pass\_completion\_rate | 0.097 |

| progressive\_carries\_per\_match | 0.097 |

| xg\_per\_match | 0.074 |

| final\_third\_to\_shot\_rate | 0.062 |



Set-piece conversion rate ranked first. xG per match ranked fourth.



My read on this: aggregate xG is noisy at small samples because finishing variance washes it out. Set-piece situations are more standardized (corner deliveries, free-kick routines) so a team's set-piece coaching shows through more consistently across 5-7 matches. The model could not learn enough from the data to predict outcomes, but the importance ranking still surfaced something useful.



Progressive pass completion rate ranking second points the same direction. Doing things accurately mattered more in the model than doing things often.



\---



\## The interview answer I rehearsed



> "I built a small classifier on tournament outcomes using 17 Gold mart features. With 72 team-tournaments the model could not beat baseline. The experiment was still useful as feature exploration. The importance ranking put set-piece conversion ahead of xG per match, which fits the idea that aggregate xG totals are noisy at small samples while standardized set-piece situations are more stable. To do this properly I would need club-season data alongside tournament data, which the StatsBomb open dataset does not include for current squads."



Honest about what failed, useful about what it suggests, clear about what would fix it.



\---



\## What I would do differently with more data



The cheapest fix is more tournaments. WC 2018 has 64 matches. AFCON 2023 has 52. Adding both would push the sample to roughly 250+ team-tournaments. The marts and dbt models would not need to change because the schema is the same. This is the v2 I would actually do.



The most useful but most expensive fix is club-season data. Player form is mostly visible in club seasons rather than 5-7 international matches. With club data I could build features at the player level and aggregate to team level. StatsBomb open data does not include comprehensive club coverage, so this would mean either a paid API or scraping FBref-style aggregations. Real work.



The 2-class version (group-stage exit vs progressed) is the cheapest experiment for a v2. Did not try it here because the goal was specifically the 3-class outcome.



\---



\## Files



\- `scripts/build\_team\_outcomes.py` — derives outcome class for each team-tournament from `stg\_matches`

\- `scripts/build\_ml\_dataset.py` — joins outcome labels with Gold mart features, exports to `ml\_dataset.parquet`

\- `scripts/train\_outcome\_model.py` — trains LR and RF, runs 5-fold CV, exports feature importance

\- `data/exports/ml\_dataset.parquet` — the 72-row feature matrix

\- `data/exports/feature\_importance.csv` — Random Forest importance scores

