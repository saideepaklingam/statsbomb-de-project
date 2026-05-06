"""Train a classifier on tournament outcomes from Gold mart features."""
import os
import pandas as pd
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score, StratifiedKFold
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
import warnings
warnings.filterwarnings("ignore")

# Paths
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPORTS = os.path.join(PROJECT_ROOT, "data", "exports")
ML_DATASET = os.path.join(EXPORTS, "ml_dataset.parquet")
FEATURE_IMPORTANCE = os.path.join(EXPORTS, "feature_importance.csv")

# Load data
df = pd.read_parquet(ML_DATASET)

# Features and target
feature_cols = [
    'shots_per_match', 'xg_per_match', 'xg_per_shot',
    'open_play_xg_share', 'set_piece_xg_share',
    'progressive_passes_per_match', 'progressive_carries_per_match',
    'final_third_entries_per_match', 'progressive_pass_completion_rate',
    'final_third_to_shot_rate',
    'pressures_per_match', 'high_press_share', 'counterpress_share',
    'ppda', 'high_press_regain_rate',
    'sp_xg_per_match', 'sp_conversion_rate'
]

X = df[feature_cols].astype('float64').to_numpy()
y = df['outcome_class'].astype(str).to_numpy()

print(f"Features: {len(feature_cols)}")
print(f"Samples: {len(X)}")
print(f"Class distribution: {pd.Series(y).value_counts().to_dict()}")
print()

# Stratified 5-fold cross-validation (small sample, so we use CV not holdout)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

# Baseline: always predict majority class
majority_class_acc = pd.Series(y).value_counts().max() / len(y)
print(f"Majority-class baseline accuracy: {majority_class_acc:.3f}")
print()

# Model 1: Logistic regression with scaling
lr_pipeline = Pipeline([
    ('scaler', StandardScaler()),
    ('clf', LogisticRegression(max_iter=1000, random_state=42))
])
lr_scores = cross_val_score(lr_pipeline, X, y, cv=cv, scoring='accuracy')
print(f"Logistic Regression CV accuracy: {lr_scores.mean():.3f} (+/- {lr_scores.std():.3f})")

# Model 2: Random Forest
rf = RandomForestClassifier(n_estimators=100, max_depth=4, random_state=42)
rf_scores = cross_val_score(rf, X, y, cv=cv, scoring='accuracy')
print(f"Random Forest CV accuracy: {rf_scores.mean():.3f} (+/- {rf_scores.std():.3f})")

# Train Random Forest on full data for feature importance
rf.fit(X, y)
importance_df = pd.DataFrame({
    'feature': feature_cols,
    'importance': rf.feature_importances_
}).sort_values('importance', ascending=False)

print()
print("=== Top 10 features by Random Forest importance ===")
print(importance_df.head(10).to_string(index=False))

# Save importance for later
importance_df.to_csv(FEATURE_IMPORTANCE, index=False)
print(f"\nSaved feature importance to {FEATURE_IMPORTANCE}")