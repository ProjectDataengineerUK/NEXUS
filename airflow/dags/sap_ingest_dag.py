"""
NEXUS AI DataOps — SAP → Snowflake ingestion DAG
Sprint 4 — P0: provider-side Airflow pipeline (não vai no Native App)

Diferente dos conectores do Sprint 2 (Salesforce/Zendesk/Stripe), o MERGE de
STAGING para CORE não é feito aqui em Python — uma Task no Snowflake consome
um Stream sobre a staging e faz o MERGE incremental (ver setup_script.sql,
seção Sprint 4). Este DAG só extrai da fonte e carrega STAGING.*.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta

import requests
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

SAP_ENTITIES = {
    "customers": "Customers",
    "invoices":  "Invoices",
    "orders":    "Orders",
}
BATCH_SIZE = 2000


@dag(
    dag_id="nexus_sap_ingest",
    description="Ingere Customers/Invoices/Orders do SAP (OData) no Snowflake",
    schedule="0 2 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["nexus", "sap", "ingestion", "p0"],
)
def sap_ingest_dag():

    @task
    def get_sap_config() -> dict:
        return {
            "base_url": Variable.get("SAP_ODATA_BASE_URL"),
            "user":     Variable.get("SAP_USER"),
            "password": Variable.get("SAP_PASSWORD"),
        }

    @task
    def extract_sap_entity(config: dict, entity_key: str) -> list[dict]:
        entity = SAP_ENTITIES[entity_key]
        auth   = (config["user"], config["password"])
        rows: list[dict] = []
        skip = 0

        while True:
            resp = requests.get(
                f"{config['base_url']}/{entity}",
                params={"$format": "json", "$top": BATCH_SIZE, "$skip": skip},
                auth=auth,
                timeout=60,
            )
            resp.raise_for_status()
            batch = resp.json().get("d", {}).get("results", [])
            if not batch:
                break
            rows.extend(batch)
            skip += BATCH_SIZE
            if len(batch) < BATCH_SIZE:
                break

        logger.info("Extraídos %d registros de SAP/%s", len(rows), entity)
        return rows

    @task
    def load_to_staging(records: list[dict], resource: str, org_id: str) -> int:
        if not records:
            return 0
        hook  = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        table = f"STAGING.SAP_{resource.upper()}"
        rows  = [(org_id, json.dumps(r)) for r in records]
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.executemany(
                f"INSERT INTO {table} (org_id, raw_data) SELECT %s, PARSE_JSON(%s)",
                rows,
            )
            conn.commit()
            return cur.rowcount

    org_id = Variable.get("NEXUS_DEFAULT_ORG_ID", default_var="demo_org")
    config = get_sap_config()

    for resource in SAP_ENTITIES:
        records = extract_sap_entity(config, resource)
        load_to_staging(records, resource, org_id)


sap_ingest_dag()
