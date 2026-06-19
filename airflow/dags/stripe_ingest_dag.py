"""
NEXUS AI DataOps — Stripe → Snowflake ingestion DAG
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

STRIPE_RESOURCES = {
    "customers":      "/v1/customers?limit=100",
    "subscriptions":  "/v1/subscriptions?limit=100&status=all",
    "invoices":       "/v1/invoices?limit=100",
    "charges":        "/v1/charges?limit=100",
}
STRIPE_BASE = "https://api.stripe.com"


@dag(
    dag_id="nexus_stripe_ingest",
    description="Ingere customers, subscriptions, invoices e charges do Stripe no Snowflake",
    schedule="0 3 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["nexus", "stripe", "ingestion", "p1"],
)
def stripe_ingest_dag():

    @task
    def get_stripe_api_key() -> str:
        return Variable.get("STRIPE_SECRET_KEY")

    @task
    def extract_stripe_resource(api_key: str, resource: str, endpoint: str) -> list[dict]:
        headers = {"Authorization": f"Bearer {api_key}"}
        records: list[dict] = []
        url = f"{STRIPE_BASE}{endpoint}"

        while url:
            resp = requests.get(url, headers=headers, timeout=60)
            resp.raise_for_status()
            data = resp.json()
            records.extend(data.get("data", []))
            if data.get("has_more"):
                last_id = records[-1]["id"]
                base_endpoint = endpoint.split("?")[0]
                params = endpoint.split("?")[1] if "?" in endpoint else "limit=100"
                url = f"{STRIPE_BASE}{base_endpoint}?{params}&starting_after={last_id}"
            else:
                url = None

        logger.info("Extraídos %d registros de Stripe/%s", len(records), resource)
        return records

    @task
    def load_to_staging(records: list[dict], resource: str, org_id: str) -> int:
        if not records:
            return 0
        hook  = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        table = f"STAGING.STRIPE_{resource.upper()}_RAW"
        rows  = [(org_id, r["id"], json.dumps(r)) for r in records]
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute(f"""
                CREATE TABLE IF NOT EXISTS {table} (
                    org_id      VARCHAR(50),
                    stripe_id   VARCHAR(255),
                    raw_data    VARIANT,
                    loaded_at   TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
                )
            """)
            cur.executemany(
                f"INSERT INTO {table} (org_id, stripe_id, raw_data) SELECT %s, %s, PARSE_JSON(%s)",
                rows,
            )
            conn.commit()
            return cur.rowcount

    @task
    def merge_subscriptions_to_core(org_id: str) -> None:
        hook = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute("""
                MERGE INTO CORE.SUBSCRIPTIONS sub
                USING (
                    SELECT
                        UUID_STRING()                          AS subscription_id,
                        %(org_id)s                            AS org_id,
                        raw_data:id::VARCHAR                  AS external_id,
                        raw_data:customer::VARCHAR            AS customer_stripe_id,
                        raw_data:status::VARCHAR              AS status,
                        raw_data:plan:amount::NUMBER / 100.0  AS mrr,
                        raw_data:plan:interval::VARCHAR       AS billing_interval,
                        TO_TIMESTAMP_TZ(raw_data:current_period_start::INTEGER) AS current_period_start,
                        TO_TIMESTAMP_TZ(raw_data:current_period_end::INTEGER)   AS current_period_end,
                        TO_TIMESTAMP_TZ(raw_data:created::INTEGER)              AS created_at
                    FROM STAGING.STRIPE_SUBSCRIPTIONS_RAW
                    WHERE org_id = %(org_id)s
                      AND loaded_at >= DATEADD('hour', -25, CURRENT_TIMESTAMP())
                ) s ON sub.org_id = s.org_id AND sub.external_id = s.external_id
                WHEN MATCHED THEN UPDATE SET
                    status     = s.status,
                    mrr        = s.mrr,
                    updated_at = CURRENT_TIMESTAMP()
                WHEN NOT MATCHED THEN INSERT
                    (subscription_id, org_id, external_id, status, mrr, billing_interval,
                     current_period_start, current_period_end, created_at)
                    VALUES (s.subscription_id, s.org_id, s.external_id, s.status, s.mrr, s.billing_interval,
                            s.current_period_start, s.current_period_end, s.created_at)
            """, {"org_id": org_id})
            conn.commit()

    @task
    def merge_invoices_to_transactions(org_id: str) -> None:
        hook = SnowflakeHook(snowflake_conn_id="snowflake_nexus")
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute("""
                MERGE INTO CORE.TRANSACTIONS t
                USING (
                    SELECT
                        UUID_STRING()                          AS transaction_id,
                        %(org_id)s                            AS org_id,
                        raw_data:id::VARCHAR                  AS external_id,
                        raw_data:customer::VARCHAR            AS customer_stripe_id,
                        raw_data:amount_paid::NUMBER / 100.0  AS amount,
                        raw_data:currency::VARCHAR            AS currency,
                        raw_data:status::VARCHAR              AS status,
                        CASE raw_data:billing_reason::VARCHAR
                            WHEN 'subscription_create' THEN 'new_business'
                            WHEN 'subscription_cycle'  THEN 'renewal'
                            WHEN 'subscription_update' THEN 'expansion'
                            ELSE 'other'
                        END                                    AS transaction_type,
                        TO_TIMESTAMP_TZ(raw_data:created::INTEGER) AS transaction_date
                    FROM STAGING.STRIPE_INVOICES_RAW
                    WHERE org_id = %(org_id)s
                      AND raw_data:status::VARCHAR = 'paid'
                      AND loaded_at >= DATEADD('hour', -25, CURRENT_TIMESTAMP())
                ) s ON t.org_id = s.org_id AND t.external_id = s.external_id
                WHEN NOT MATCHED THEN INSERT
                    (transaction_id, org_id, external_id, amount, currency, status, transaction_type, transaction_date)
                    VALUES (s.transaction_id, s.org_id, s.external_id, s.amount, s.currency, s.status, s.transaction_type, s.transaction_date)
            """, {"org_id": org_id})
            conn.commit()

    org_id  = Variable.get("NEXUS_DEFAULT_ORG_ID", default_var="demo_org")
    api_key = get_stripe_api_key()

    for resource, endpoint in STRIPE_RESOURCES.items():
        records = extract_stripe_resource(api_key, resource, endpoint)
        load_to_staging(records, resource, org_id)

    merge_subscriptions_to_core(org_id)
    merge_invoices_to_transactions(org_id)


stripe_ingest_dag()
