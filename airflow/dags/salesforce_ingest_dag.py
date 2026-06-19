"""
NEXUS AI DataOps — Salesforce → Snowflake ingestion DAG
Sprint 2 — P1: provider-side Airflow pipeline (não vai no Native App)
Roda no Airflow do provider, não no ambiente do consumer.
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

SALESFORCE_OBJECTS = ["Account", "Contact", "Opportunity", "Lead"]
BATCH_SIZE = 2000


@dag(
    dag_id="nexus_salesforce_ingest",
    description="Ingere objetos Salesforce (Account, Contact, Opportunity, Lead) no Snowflake",
    schedule="0 1 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["nexus", "salesforce", "ingestion", "p1"],
)
def salesforce_ingest_dag():

    @task
    def get_salesforce_token() -> dict:
        client_id     = Variable.get("SALESFORCE_CLIENT_ID")
        client_secret = Variable.get("SALESFORCE_CLIENT_SECRET")
        username      = Variable.get("SALESFORCE_USERNAME")
        password      = Variable.get("SALESFORCE_PASSWORD")
        domain        = Variable.get("SALESFORCE_DOMAIN", default_var="login")

        resp = requests.post(
            f"https://{domain}.salesforce.com/services/oauth2/token",
            data={
                "grant_type":    "password",
                "client_id":     client_id,
                "client_secret": client_secret,
                "username":      username,
                "password":      password,
            },
            timeout=30,
        )
        resp.raise_for_status()
        token_data = resp.json()
        return {"access_token": token_data["access_token"], "instance_url": token_data["instance_url"]}

    @task
    def extract_salesforce_object(token_data: dict, sf_object: str) -> list[dict]:
        headers = {"Authorization": f"Bearer {token_data['access_token']}"}
        instance_url = token_data["instance_url"]
        records: list[dict] = []
        url = f"{instance_url}/services/data/v59.0/sobjects/{sf_object}/describe"

        fields_resp = requests.get(url, headers=headers, timeout=30)
        fields_resp.raise_for_status()
        all_fields = [f["name"] for f in fields_resp.json()["fields"] if f["type"] != "base64"]
        soql = f"SELECT {', '.join(all_fields[:50])} FROM {sf_object} LIMIT {BATCH_SIZE}"

        query_url = f"{instance_url}/services/data/v59.0/query?q={requests.utils.quote(soql)}"
        while query_url:
            resp = requests.get(query_url, headers=headers, timeout=60)
            resp.raise_for_status()
            data = resp.json()
            records.extend(data.get("records", []))
            next_url = data.get("nextRecordsUrl")
            query_url = f"{instance_url}{next_url}" if next_url else None

        logger.info("Extraídos %d registros de %s", len(records), sf_object)
        return records

    @task
    def load_to_snowflake(records: list[dict], sf_object: str, org_id: str) -> int:
        if not records:
            return 0

        hook = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        table_map = {
            "Account":     "CORE.ACCOUNTS",
            "Contact":     "CORE.CUSTOMERS",
            "Opportunity": "CORE.TRANSACTIONS",
            "Lead":        "CORE.INTERACTIONS",
        }
        target_table = table_map.get(sf_object, f"STAGING.SF_{sf_object.upper()}")

        rows = [(org_id, json.dumps(rec)) for rec in records]
        stage_table = f"STAGING.SF_{sf_object.upper()}_RAW"

        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute(f"""
                CREATE TABLE IF NOT EXISTS {stage_table} (
                    org_id    VARCHAR(50),
                    raw_data  VARIANT,
                    loaded_at TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
                )
            """)
            cur.executemany(
                f"INSERT INTO {stage_table} (org_id, raw_data) SELECT %s, PARSE_JSON(%s)",
                rows,
            )
            conn.commit()
            inserted = cur.rowcount
            logger.info("Inseridos %d registros em %s", inserted, stage_table)
            return inserted

    @task
    def log_pipeline_run(counts: list[int], org_id: str) -> None:
        hook = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        total = sum(counts)
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO AUDIT.ACTION_LOG (org_id, action_type, details, created_at)
                VALUES (%s, 'SALESFORCE_INGEST', %s, CURRENT_TIMESTAMP())
            """, (org_id, json.dumps({"total_records": total, "objects": SALESFORCE_OBJECTS})))
            conn.commit()
        logger.info("Pipeline Salesforce concluído: %d registros totais para org %s", total, org_id)

    org_id     = Variable.get("NEXUS_DEFAULT_ORG_ID", default_var="demo_org")
    token_data = get_salesforce_token()
    counts     = []
    for sf_obj in SALESFORCE_OBJECTS:
        records = extract_salesforce_object(token_data, sf_obj)
        count   = load_to_snowflake(records, sf_obj, org_id)
        counts.append(count)

    log_pipeline_run(counts, org_id)


salesforce_ingest_dag()
