"""
NEXUS AI DataOps — Zendesk → Snowflake ingestion DAG
Sprint 2 — P1: provider-side Airflow pipeline
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
}

ZENDESK_ENDPOINTS = {
    "tickets":       "/api/v2/tickets.json?per_page=100",
    "users":         "/api/v2/users.json?per_page=100&role=end-user",
    "organizations": "/api/v2/organizations.json?per_page=100",
}


@dag(
    dag_id="nexus_zendesk_ingest",
    description="Ingere tickets, usuários e orgs Zendesk no Snowflake",
    schedule="0 2 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["nexus", "zendesk", "ingestion", "p1"],
)
def zendesk_ingest_dag():

    @task
    def get_zendesk_config() -> dict:
        return {
            "subdomain": Variable.get("ZENDESK_SUBDOMAIN"),
            "email":     Variable.get("ZENDESK_EMAIL"),
            "api_token": Variable.get("ZENDESK_API_TOKEN"),
        }

    @task
    def extract_zendesk_resource(config: dict, resource: str, endpoint: str) -> list[dict]:
        base_url = f"https://{config['subdomain']}.zendesk.com"
        auth     = (f"{config['email']}/token", config["api_token"])
        records: list[dict] = []
        url = f"{base_url}{endpoint}"

        while url:
            resp = requests.get(url, auth=auth, timeout=60)
            resp.raise_for_status()
            data = resp.json()
            records.extend(data.get(resource, []))
            links  = data.get("links", {})
            meta   = data.get("meta", {})
            if meta.get("has_more"):
                cursor = meta.get("after_cursor")
                url = f"{base_url}/api/v2/{resource}.json?page[after]={cursor}&page[size]=100" if cursor else None
            else:
                url = links.get("next")

        logger.info("Extraídos %d registros de Zendesk/%s", len(records), resource)
        return records

    @task
    def load_tickets_to_snowflake(records: list[dict], org_id: str) -> int:
        if not records:
            return 0
        hook = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        rows = [
            (
                org_id,
                str(r.get("id", "")),
                r.get("subject", ""),
                r.get("status", "open"),
                r.get("priority", "normal"),
                r.get("requester_id"),
                r.get("assignee_id"),
                r.get("created_at"),
                r.get("updated_at"),
                json.dumps(r),
            )
            for r in records
        ]
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS STAGING.ZD_TICKETS_RAW (
                    org_id       VARCHAR(50),
                    ticket_id    VARCHAR(50),
                    subject      TEXT,
                    status       VARCHAR(50),
                    priority     VARCHAR(50),
                    requester_id BIGINT,
                    assignee_id  BIGINT,
                    created_at   VARCHAR(50),
                    updated_at   VARCHAR(50),
                    raw_data     VARIANT,
                    loaded_at    TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
                )
            """)
            cur.executemany(
                "INSERT INTO STAGING.ZD_TICKETS_RAW "
                "(org_id, ticket_id, subject, status, priority, requester_id, assignee_id, created_at, updated_at, raw_data) "
                "SELECT %s, %s, %s, %s, %s, %s, %s, %s::TIMESTAMP_TZ, %s::TIMESTAMP_TZ, PARSE_JSON(%s)",
                rows,
            )
            conn.commit()
            return cur.rowcount

    @task
    def merge_tickets_to_core(org_id: str) -> None:
        hook = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute("""
                MERGE INTO CORE.TICKETS t
                USING (
                    SELECT DISTINCT ON (ticket_id)
                        UUID_STRING()  AS ticket_id_new,
                        org_id,
                        ticket_id      AS external_id,
                        subject,
                        status,
                        priority,
                        loaded_at      AS created_at,
                        loaded_at      AS updated_at
                    FROM STAGING.ZD_TICKETS_RAW
                    WHERE org_id = %(org_id)s
                    ORDER BY ticket_id, loaded_at DESC
                ) s ON t.org_id = s.org_id AND t.external_id = s.external_id
                WHEN MATCHED THEN UPDATE SET
                    status     = s.status,
                    priority   = s.priority,
                    updated_at = s.updated_at
                WHEN NOT MATCHED THEN INSERT
                    (ticket_id, org_id, external_id, subject, status, priority, created_at, updated_at)
                    VALUES (s.ticket_id_new, s.org_id, s.external_id, s.subject, s.status, s.priority, s.created_at, s.updated_at)
            """, {"org_id": org_id})
            conn.commit()
            logger.info("Tickets mesclados no CORE.TICKETS para org %s", org_id)

    org_id  = Variable.get("NEXUS_DEFAULT_ORG_ID", default_var="demo_org")
    config  = get_zendesk_config()

    for resource, endpoint in ZENDESK_ENDPOINTS.items():
        records = extract_zendesk_resource(config, resource, endpoint)
        if resource == "tickets":
            count = load_tickets_to_snowflake(records, org_id)
            merge_tickets_to_core(org_id)


zendesk_ingest_dag()
