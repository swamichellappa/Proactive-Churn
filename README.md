# Proactive Churn

Churn-risk model for brightwheel SaaS schools.

## Setup

```bash
bash setup.sh          # creates .venv, installs pinned deps, registers Jupyter kernel
cp .env.example .env   # then paste your REDSHIFT_PASSWORD
```

Then connect to VPN and:

```bash
source .venv/bin/activate
jupyter notebook
```

Open `data/dataset_creation.ipynb` and select the **Python (Proactive Churn)** kernel.

## Layout

```
.
├── .env                          # credentials — gitignored, never commit
├── .env.example                  # template
├── requirements.txt              # pinned; read the comments before bumping
├── setup.sh
└── data/
    ├── dataset_creation.ipynb    # connection + v1 extract (spec-faithful)
    └── raw/                      # extracts — gitignored
```

## Redshift

Analytics cluster, database `bw_analytics`. **VPN required** — off-VPN you get a
connection timeout, not an auth error. Credentials issued by Data Eng (Shana Luo).

Project tables, all in `analytics_mart_customer`:

| Table | Grain | Role |
| --- | --- | --- |
| `mart_school_customers` | school | attributes |
| `rpt_monthly_school_usage_trends` | school × month | features |
| `rpt_school_churn_cases` | cancellation case | labels |

## Environment pins

`requirements.txt` has upper bounds on `numpy`, `scipy`, and `xgboost`. They exist
because **BorutaShap 1.0.17 is unmaintained** (last release Dec 2023) and breaks
three ways against a current stack:

- `numpy >= 2.0` — BorutaShap uses `np.NaN`, removed in numpy 2.0
- `scipy >= 1.12` — BorutaShap imports `scipy.stats.binom_test`, removed in 1.12
  (the notebook installs a shim, but scipy is pinned as well)
- `xgboost >= 3.0` — `shap`'s XGBoost tree loader can't parse the new
  `base_score` serialization

Verified working: numpy 1.26.4 · scipy 1.13.1 · pandas 2.3.3 · xgboost 2.1.4 ·
shap 0.49.1 · scikit-learn 1.7.2 · BorutaShap 1.0.17.

If BorutaSHAP becomes a maintenance problem, the Boruta-with-SHAP loop is ~50
lines against `shap` + `xgboost` directly and drops the dependency entirely.

## macOS: xgboost and libomp

xgboost's macOS wheel does not bundle the OpenMP runtime, so importing it fails with
`Library not loaded: @rpath/libomp.dylib` unless `libomp.dylib` is somewhere on its
search path. The usual fix is `brew install libomp`.

Without Homebrew, `setup.sh` handles it automatically: scikit-learn's macOS wheel
*does* vendor a copy of `libomp.dylib`, and the script copies that into
`sys.base_prefix/lib`, which is on `libxgboost.dylib`'s `@rpath` list.

If that copy isn't found, two fallbacks:

1. Pull `lib/libomp.dylib` out of a conda-forge `llvm-openmp` package (no admin needed).
2. Use `sklearn.ensemble.HistGradientBoostingClassifier` instead of xgboost — its
   OpenMP is vendored and working, and both `shap` and BorutaSHAP accept it.

## Handling rules

- Secrets live in `.env` only
- School-level customer data stays out of git (`data/` extracts are gitignored).
