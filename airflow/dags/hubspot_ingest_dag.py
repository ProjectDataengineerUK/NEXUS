"""
NEXUS AI DataOps — HubSpot → Snowflake ingestion DAG
Sprint 4 — P1: provider-side Airflow pipeline (não vai no Native App)

O MERGE de STAGING para CORE é feito por uma Task no Snowflake que consome
um Stream sobre a staging (ver setup_script.sql, seção Sprint 4) — este DAG
só extrai da API v3 do HubSpot e carrega STAGING.*.
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

HUBSPOT_OBJECTS = ["contacts", "deals", "companies"]
HUBSPOT_BASE = "https://api.hubapi.com"
PAGE_SIZE = 100


@dag(
    dag_id="nexus_hubspot_ingest",
    description="Ingere contacts/deals/companies do HubSpot (API v3) no Snowflake",
    schedule="0 4 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["nexus", "hubspot", "ingestion", "p1"],
)
def hubspot_ingest_dag():

    @task
    def get_hubspot_token() -> str:
        return Variable.get("HUBSPOT_ACCESS_TOKEN")

    @task
    def extract_hubspot_object(token: str, object_type: str) -> list[dict]:
        headers = {"Authorization": f"Bearer {token}"}
        records: list[dict] = []
        after = None

        while True:
            params = {"limit": PAGE_SIZE}
            if after:
                params["after"] = after
            resp = requests.get(
                f"{HUBSPOT_BASE}/crm/v3/objects/{object_type}",
                headers=headers,
                params=params,
                timeout=60,
            )
            resp.raise_for_status()
            data = resp.json()
            records.extend(data.get("results", []))
            after = data.get("paging", {}).get("next", {}).get("after")
            if not after:
                break

        logger.info("Extraídos %d registros de HubSpot/%s", len(records), object_type)
        return records

    @task
    def load_to_staging(records: list[dict], object_type: str, org_id: str) -> int:
        if not records:
            return 0
        hook  = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        table = f"STAGING.HUBSPOT_{object_type.upper()}"
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
    token  = get_hubspot_token()

    for object_type in HUBSPOT_OBJECTS:
        records = extract_hubspot_object(token, object_type)
        load_to_staging(records, object_type, org_id)


hubspot_ingest_dag()
