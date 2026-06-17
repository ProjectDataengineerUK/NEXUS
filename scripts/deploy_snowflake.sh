#!/usr/bin/env bash
# Script de deploy manual — equivalente ao workflow 02
# Uso: ./scripts/deploy_snowflake.sh [dev|prod]
set -euo pipefail

ENV="${1:-dev}"
echo "==> Deploy NEXUS → $ENV"

# Validar variáveis de ambiente obrigatórias
: "${SNOWFLAKE_ACCOUNT:?Defina SNOWFLAKE_ACCOUNT}"
: "${SNOWFLAKE_USER:?Defina SNOWFLAKE_USER}"
: "${SNOWFLAKE_PASSWORD:?Defina SNOWFLAKE_PASSWORD}"

SNOWFLAKE_DATABASE="${SNOWFLAKE_DATABASE:-NEXUS_APP}"
SNOWFLAKE_ROLE="${SNOWFLAKE_ROLE:-SYSADMIN}"
SNOWFLAKE_WAREHOUSE="${SNOWFLAKE_WAREHOUSE:-NEXUS_COMPUTE_WH}"

# ── Helper: executar SQL ──────────────────────────────────────────────────────
run_sql() {
  python3 - "$1" <<'PYEOF'
import sys, snowflake.connector, os

sql = open(sys.argv[1]).read()
conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    database=os.environ.get("SNOWFLAKE_DATABASE", "NEXUS_APP"),
    role=os.environ.get("SNOWFLAKE_ROLE", "SYSADMIN"),
    warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "NEXUS_COMPUTE_WH"),
)
cs = conn.cursor()
for stmt in sql.split(";"):
    stmt = stmt.strip()
    if stmt and not stmt.startswith("--"):
        try:
            cs.execute(stmt)
        except Exception as e:
            if "already exists" not in str(e).lower():
                raise
cs.close()
conn.close()
PYEOF
}

# ── Helper: PUT file em stage ─────────────────────────────────────────────────
put_file() {
  local local_file="$1"
  local stage_path="$2"
  python3 - "$local_file" "$stage_path" <<'PYEOF'
import sys, snowflake.connector, os

local_file, stage_path = sys.argv[1], sys.argv[2]
conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    database=os.environ.get("SNOWFLAKE_DATABASE", "NEXUS_APP"),
    role=os.environ.get("SNOWFLAKE_ROLE", "SYSADMIN"),
    warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "NEXUS_COMPUTE_WH"),
)
cs = conn.cursor()
cs.execute(f"PUT file://{local_file} {stage_path} OVERWRITE=TRUE AUTO_COMPRESS=FALSE")
cs.close()
conn.close()
PYEOF
}

# ── 1. Scripts SQL de setup ───────────────────────────────────────────────────
echo "==> [1/5] Executando scripts SQL de setup..."
for script in snowflake/setup/*.sql; do
  echo "    $script"
  run_sql "$script"
done

# ── 2. YAML configs ───────────────────────────────────────────────────────────
echo "==> [2/5] Fazendo upload de YAML configs..."
for f in snowflake/config/*.yaml; do
  echo "    $f"
  put_file "$(pwd)/$f" "@NEXUS_APP.CORE.SEMANTIC_STAGE"
done

# ── 3. Modelo de churn ────────────────────────────────────────────────────────
echo "==> [3/5] Fazendo upload do churn_model.py..."
put_file "$(pwd)/snowflake/models/churn_model.py" "@NEXUS_APP.CORE.ML_STAGE"

# ── 4. Páginas Streamlit ──────────────────────────────────────────────────────
echo "==> [4/5] Fazendo upload das páginas Streamlit..."
for f in app/streamlit/Home.py app/streamlit/pages/*.py; do
  echo "    $f"
  put_file "$(pwd)/$f" "@NEXUS_APP.CORE.APP_STAGE/streamlit/pages/"
done

# ── 5. Churn pipeline inicial ─────────────────────────────────────────────────
echo "==> [5/5] Executando churn pipeline inicial..."
python3 - <<'PYEOF'
import snowflake.connector, os
conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    database="NEXUS_APP", role="SYSADMIN", warehouse="NEXUS_ML_WH",
)
cs = conn.cursor()
cs.execute("CALL NEXUS_APP.CORE.SP_RUN_CHURN_PIPELINE('full')")
print(cs.fetchone())
cs.close()
conn.close()
PYEOF

echo ""
echo "Deploy concluído com sucesso!"
echo "Acesse o Streamlit em: https://app.snowflake.com → Streamlit → NEXUS_DASHBOARD"
