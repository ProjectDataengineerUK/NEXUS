"""
NEXUS AI DataOps — Oracle → Snowflake ingestion DAG
Sprint 4 — P0: provider-side Airflow pipeline (não vai no Native App)

Usa o driver oracledb em modo thin (puro Python, sem Oracle Instant Client
instalado no worker do Airflow). O MERGE de STAGING para CORE é feito por
uma Task no Snowflake que consome um Stream sobre a staging (ver
setup_script.sql, seção Sprint 4) — este DAG só extrai e carrega STAGING.*.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta

import oracledb
from airflow.decorators import dag, task
from airflow.models import Variable
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

logger = logging.getLogger(__name__)

DEFAULT_ARGS = {
    "owner": "nexus-platform",
    "depends_on_past": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
}

ORACLE_QUERIES = {
    "customers": "SELECT * FROM CUSTOMERS",
    "orders":    "SELECT * FROM ORDERS",
    "invoices":  "SELECT * FROM INVOICES",
}


@dag(
    dag_id="nexus_oracle_ingest",
    description="Ingere Customers/Orders/Invoices de um Oracle DB no Snowflake",
    schedule="0 2 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["nexus", "oracle", "ingestion", "p0"],
)
def oracle_ingest_dag():

    @task
    def extract_oracle_table(resource: str) -> list[dict]:
        dsn      = Variable.get("ORACLE_DSN")
        user     = Variable.get("ORACLE_USER")
        password = Variable.get("ORACLE_PASSWORD")

        conn = oracledb.connect(user=user, password=password, dsn=dsn)
        try:
            cursor = conn.cursor()
            cursor.execute(ORACLE_QUERIES[resource])
            columns = [col[0] for col in cursor.description]
            rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
        finally:
            conn.close()

        logger.info("Extraídos %d registros de Oracle/%s", len(rows), resource)
        return rows

    @task
    def load_to_staging(records: list[dict], resource: str, org_id: str) -> int:
        if not records:
            return 0
        hook  = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        table = f"STAGING.ORACLE_{resource.upper()}"
        rows  = [(org_id, json.dumps(r, default=str)) for r in records]
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.executemany(
                f"INSERT INTO {table} (org_id, raw_data) SELECT %s, PARSE_JSON(%s)",
                rows,
            )
            conn.commit()
            return cur.rowcount

    org_id = Variable.get("NEXUS_DEFAULT_ORG_ID", default_var="demo_org")

    for resource in ORACLE_QUERIES:
        records = extract_oracle_table(resource)
        load_to_staging(records, resource, org_id)


oracle_ingest_dag()
