"""
NEXUS AI DataOps — KBS Weekly Refresh DAG
Sprint 2 — P1: re-indexa Snowflake Core e Cortex AI docs semanalmente
Roda no Airflow do provider.
"""

from __future__ import annotations

import importlib.util
import logging
import sys
from datetime import datetime, timedelta
from pathlib import Path

from airflow.decorators import dag, task
from airflow.models import Variable
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

logger = logging.getLogger(__name__)

DEFAULT_ARGS = {
    "owner": "nexus-platform",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=10),
}

KBS_DIR = Path(__file__).parent.parent.parent / "pipelines" / "kbs"


def _import_loader(module_name: str):
    path = KBS_DIR / f"{module_name}.py"
    spec = importlib.util.spec_from_file_location(module_name, path)
    mod  = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(KBS_DIR))
    spec.loader.exec_module(mod)
    return mod


@dag(
    dag_id="nexus_kbs_refresh",
    description="Atualiza Knowledge Base semanal — Snowflake Core e Cortex AI docs",
    schedule="0 4 * * 0",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["nexus", "kbs", "cortex_search", "p1"],
)
def kbs_refresh_dag():

    @task
    def truncate_stale_documents() -> None:
        hook = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute("""
                DELETE FROM NEXUS_APP.KBS.DOCUMENTS
                WHERE updated_at < DATEADD('day', -8, CURRENT_TIMESTAMP())
                  AND kb_name IN ('snowflake_core', 'cortex_ai')
            """)
            conn.commit()
            logger.info("Removidos %d documentos desatualizados", cur.rowcount)

    @task
    def load_snowflake_docs(conn_str: str) -> int:
        mod    = _import_loader("load_kb_snowflake")
        loader = mod.KBSLoader(snowflake_conn_str=conn_str)
        return loader.run()

    @task
    def load_cortex_docs(conn_str: str) -> int:
        mod    = _import_loader("load_kb_cortex")
        loader = mod.CortexKBSLoader(snowflake_conn_str=conn_str)
        return loader.run()

    @task
    def log_refresh_summary(sf_count: int, cortex_count: int) -> None:
        import json
        hook = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        total = sf_count + cortex_count
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO NEXUS_APP.AUDIT.ACTION_LOG (org_id, action_type, details, created_at)
                VALUES ('_system', 'KBS_REFRESH', PARSE_JSON(%s), CURRENT_TIMESTAMP())
            """, (json.dumps({"snowflake_chunks": sf_count, "cortex_chunks": cortex_count, "total": total}),))
            conn.commit()
        logger.info("KBS refresh concluído: %d chunks totais", total)

    conn_str = Variable.get("SNOWFLAKE_CONNECTION_STRING")

    truncate_stale_documents()
    sf_count     = load_snowflake_docs(conn_str)
    cortex_count = load_cortex_docs(conn_str)
    log_refresh_summary(sf_count, cortex_count)


kbs_refresh_dag()
