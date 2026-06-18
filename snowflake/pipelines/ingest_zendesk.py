"""
NEXUS AI DataOps — Zendesk Support Ingestion Pipeline
Extrai tickets e comentários via Zendesk Incremental API
e carrega em NEXUS_APP.CORE.TICKETS.
"""

import logging
import os
from datetime import datetime, timedelta, timezone

import requests
from snowflake.snowpark import Session

logger = logging.getLogger(__name__)

ORG_ID     = os.getenv("NEXUS_ORG_ID", "ORG-DEMO-001")
BATCH_SIZE = 100

PRIORITY_MAP = {"low": "low", "normal": "medium", "high": "high", "urgent": "critical"}
STATUS_MAP   = {"new": "open", "open": "open", "pending": "open",
                "hold": "open", "solved": "resolved", "closed": "resolved"}


class ZendeskClient:
    def __init__(self, subdomain: str, email: str, token: str):
        self.base    = f"https://{subdomain}.zendesk.com/api/v2"
        self.auth    = (f"{email}/token", token)

    @classmethod
    def from_env(cls) -> "ZendeskClient":
        return cls(
            os.environ["ZENDESK_SUBDOMAIN"],
            os.environ["ZENDESK_EMAIL"],
            os.environ["ZENDESK_TOKEN"],
        )

    def incremental_tickets(self, start_time: int) -> list[dict]:
        tickets, url = [], f"{self.base}/incremental/tickets.json?start_time={start_time}&include=metric_sets"
        while url:
            r = requests.get(url, auth=self.auth, timeout=30)
            r.raise_for_status()
            body = r.json()
            tickets.extend(body.get("tickets", []))
            url = body.get("next_page") if not body.get("end_of_stream") else None
        return tickets


def _upsert_tickets(session: Session, tickets: list[dict], org_id: str) -> int:
    inserted = 0
    for t in tickets:
        try:
            sla_breached = bool(
                t.get("metric_set", {}).get("first_reply_time_in_minutes", {}).get("breached")
            )
            session.sql("""
                MERGE INTO NEXUS_APP.CORE.TICKETS tgt
                USING (SELECT ? AS ticket_id) src ON tgt.ticket_id = src.ticket_id
                WHEN MATCHED THEN UPDATE SET
                    status = ?, priority = ?, sla_breached = ?,
                    resolved_at = ?, updated_at = CURRENT_TIMESTAMP()
                WHEN NOT MATCHED THEN INSERT
                    (ticket_id, org_id, customer_id, subject, status,
                     priority, sla_breached, source_system, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'zendesk', ?)
            """, params=[
                str(t["id"]),
                STATUS_MAP.get(t.get("status", "open"), "open"),
                PRIORITY_MAP.get(t.get("priority", "normal"), "medium"),
                sla_breached,
                t.get("solved_at"),
                str(t["id"]), org_id,
                str(t.get("requester_id", "")),
                t.get("subject", "")[:500],
                STATUS_MAP.get(t.get("status", "open"), "open"),
                PRIORITY_MAP.get(t.get("priority", "normal"), "medium"),
                sla_breached,
                t.get("created_at"),
            ]).collect()
            inserted += 1
        except Exception as e:
            logger.warning("Failed to upsert ticket %s: %s", t.get("id"), e)
    return inserted


def run(session: Session, org_id: str = ORG_ID, since_days: int = 1) -> str:
    zd    = ZendeskClient.from_env()
    since = int((datetime.now(timezone.utc) - timedelta(days=since_days)).timestamp())

    tickets = zd.incremental_tickets(since)
    n = _upsert_tickets(session, tickets, org_id)
    return f"OK: {n}/{len(tickets)} tickets sincronizados do Zendesk para {org_id}"


if __name__ == "__main__":
    session = Session.builder.config("connection_name", "nexus_dev").create()
    print(run(session))
    session.close()
