#!/usr/bin/env bash
# Upload all semantic model YAMLs to @NEXUS_APP.CORE.SEMANTIC_STAGE
# Run this AFTER 'snow app run' or 'snowsql -f setup_script.sql'
# Required env vars: SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD
# Optional:         SNOWFLAKE_ROLE (default: NEXUS_SYSADMIN)
#                   SNOWFLAKE_WAREHOUSE (default: NEXUS_APP_WH)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/../snowflake/cortex/semantic_models"
STAGE="@NEXUS_APP.CORE.SEMANTIC_STAGE"

: "${SNOWFLAKE_ACCOUNT:?SNOWFLAKE_ACCOUNT is required}"
: "${SNOWFLAKE_USER:?SNOWFLAKE_USER is required}"
: "${SNOWFLAKE_PASSWORD:?SNOWFLAKE_PASSWORD is required}"

ROLE="${SNOWFLAKE_ROLE:-NEXUS_SYSADMIN}"
WAREHOUSE="${SNOWFLAKE_WAREHOUSE:-NEXUS_APP_WH}"

echo "Uploading semantic models to ${STAGE}"
echo "  Account:   ${SNOWFLAKE_ACCOUNT}"
echo "  Role:      ${ROLE}"
echo "  Warehouse: ${WAREHOUSE}"
echo ""

python3 - <<PYEOF
import glob, os, sys
import snowflake.connector

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    database="NEXUS_APP",
    role=os.environ.get("SNOWFLAKE_ROLE", "NEXUS_SYSADMIN"),
    warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "NEXUS_APP_WH"),
)
cur = conn.cursor()
stage = "${STAGE}"
models_dir = "${MODELS_DIR}"

yaml_files = sorted(glob.glob(f"{models_dir}/*.yaml"))
if not yaml_files:
    print(f"ERROR: no YAML files found in {models_dir}", file=sys.stderr)
    sys.exit(1)

uploaded = 0
for path in yaml_files:
    fname = os.path.basename(path)
    cur.execute(
        f"PUT file://{path} {stage}/{fname} OVERWRITE = TRUE AUTO_COMPRESS = FALSE"
    )
    result = cur.fetchone()
    status = result[6] if result else "unknown"
    print(f"  {'✓' if status == 'UPLOADED' else '!'} {fname} → {stage}/{fname}  [{status}]")
    uploaded += 1

print(f"\nUploaded {uploaded} file(s). Verifying stage contents...")
cur.execute(f"LIST {stage}")
rows = cur.fetchall()
for r in rows:
    print(f"  {r[0]}  ({r[1]} bytes)")

conn.close()
print("\nDone.")
PYEOF
