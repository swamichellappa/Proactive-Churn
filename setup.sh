#!/usr/bin/env bash
# Proactive Churn — one-time environment setup (macOS).
# Run from the project root:  bash setup.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

PY="${PYTHON:-python3}"

echo "==> Python: $("$PY" --version)"
"$PY" - <<'EOF'
import sys
if sys.version_info < (3, 10) or sys.version_info >= (3, 13):
    sys.exit(
        f"Need Python 3.10-3.12 (found {sys.version.split()[0]}).\n"
        "\n"
        "Why: requirements.txt pins numpy<2 and scipy<1.14 (BorutaShap needs\n"
        "them). Neither has a cp313 wheel -- numpy added 3.13 support in 2.1,\n"
        "scipy in 1.14 -- so on 3.13 pip falls back to a source build and fails.\n"
        "\n"
        "Fix:  brew install python@3.12\n"
        "      PYTHON=python3.12 bash setup.sh\n"
    )
EOF

echo "==> Creating virtual environment at .venv"
if [ -d .venv ]; then
  echo "    .venv already exists — reusing it"
else
  "$PY" -m venv .venv
fi

echo "==> Upgrading pip"
./.venv/bin/python -m pip install --quiet --upgrade pip setuptools wheel

echo "==> Installing pinned requirements (this takes a few minutes)"
./.venv/bin/python -m pip install -r requirements.txt

if [ "$(uname -s)" = "Darwin" ]; then
  echo "==> Checking OpenMP runtime for xgboost (macOS)"
  if ./.venv/bin/python -c "import xgboost" 2>/dev/null; then
    echo "    xgboost loads fine"
  else
    # xgboost's macOS wheel does not bundle libomp, but scikit-learn's does.
    # Reuse that copy rather than requiring Homebrew. The destination is on
    # libxgboost.dylib's @rpath search list.
    SRC="$(find ./.venv -name 'libomp.dylib' -print -quit 2>/dev/null || true)"
    DEST="$(./.venv/bin/python -c 'import sys; print(sys.base_prefix)')/lib"
    if [ -n "$SRC" ] && [ -d "$DEST" ]; then
      echo "    linking $SRC -> $DEST/"
      cp -n "$SRC" "$DEST"/ || true
      if ./.venv/bin/python -c "import xgboost" 2>/dev/null; then
        echo "    xgboost loads now"
      else
        echo "    STILL FAILING — see the libomp notes in README.md" >&2
        exit 1
      fi
    else
      echo "    No vendored libomp.dylib found — see README.md" >&2
      exit 1
    fi
  fi
fi

echo "==> Registering Jupyter kernel 'proactive-churn'"
./.venv/bin/python -m ipykernel install --user \
  --name proactive-churn \
  --display-name "Python (Proactive Churn)"

echo "==> Creating .env from template (if missing)"
if [ ! -f .env ]; then
  cp .env.example .env
  echo "    Created .env — open it and paste your REDSHIFT_PASSWORD"
else
  echo "    .env already exists — left untouched"
fi

echo "==> Verifying the stack"
./.venv/bin/python - <<'EOF'
import scipy.stats as st
if not hasattr(st, "binom_test"):
    st.binom_test = lambda x, n=None, p=0.5, alternative="two-sided": st.binomtest(
        int(x), int(n), p, alternative=alternative
    ).pvalue

import numpy, pandas, redshift_connector, sqlalchemy, sklearn, xgboost, shap
from BorutaShap import BorutaShap  # noqa: F401

print(f"    numpy              {numpy.__version__}")
print(f"    scipy              {st.__name__.split('.')[0]} ok")
print(f"    pandas             {pandas.__version__}")
print(f"    redshift_connector {redshift_connector.__version__}")
print(f"    sqlalchemy         {sqlalchemy.__version__}")
print(f"    scikit-learn       {sklearn.__version__}")
print(f"    xgboost            {xgboost.__version__}")
print(f"    shap               {shap.__version__}")
print("    BorutaShap         import OK")
EOF

cat <<'MSG'

==> Done.

Next:
  1. Connect to VPN (required — the cluster is not reachable off-VPN).
     Setup guide: https://docs.google.com/document/d/1kNqdf4H1voZC0ne0UI1oH-K66tn8EBZ0OfC-Ivh-wUc/edit
  2. Open .env and paste your REDSHIFT_PASSWORD.
  3. Start Jupyter:
       source .venv/bin/activate
       jupyter notebook
  4. Open data/00_redshift_connection.ipynb and pick the
     "Python (Proactive Churn)" kernel.
MSG
