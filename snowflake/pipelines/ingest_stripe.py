"""
NEXUS AI DataOps — Stripe Billing Ingestion Pipeline
Extrai invoices e subscriptions via Stripe API
e carrega em NEXUS_APP.CORE.TRANSACTIONS e CORE.SUBSCRIPTIONS.
"""

import os
import logging
import stripe
from datetime import datetime, timezone, timedelta
from snowflake.snowpark import Session

logger = logging.getLogger(__name__)

ORG_ID = os.getenv("NEXUS_ORG_ID", "ORG-DEMO-001")

STATUS_MAP = {
    "active": "active", "trialing": "trial",
    "past_due": "active", "canceled": "cancelled", "unpaid": "cancelled",
}


def _upsert_subscription(session: Session, sub: stripe.Subscription, org_id: str) -> None:
    mrr = sum(i["plan"]["amount"] for i in sub["items"]["data"]) / 100.0
    session.sql("""
        MERGE INTO NEXUS_APP.CORE.SUBSCRIPTIONS t
        USING (SELECT ? AS subscription_id) s ON t.subscription_id = s.subscription_id
        WHEN MATCHED THEN UPDATE SET
            status = ?, mrr = ?, arr = ?, renewal_date = ?, updated_at = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN INSERT
            (subscription_id, org_id, customer_id, plan_name, status,
             mrr, arr, renewal_date, source_system)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'stripe')
    """, params=[
        sub["id"],
        STATUS_MAP.get(sub["status"], "active"), mrr, mrr * 12,
        datetime.fromtimestamp(sub["current_period_end"]).date().isoformat(),
        sub["id"], org_id, sub["customer"],
        sub["items"]["data"][0]["plan"].get("nickname", "unknown"),
        STATUS_MAP.get(sub["status"], "active"), mrr, mrr * 12,
        datetime.fromtimestamp(sub["current_period_end"]).date().isoformat(),
    ]).collect()


def _upsert_invoice(session: Session, inv: stripe.Invoice, org_id: str) -> None:
    if inv["status"] != "paid":
        return
    t_type = "renewal"
    if inv.get("billing_reason") == "subscription_create":
        t_type = "new_contract"
    elif inv.get("billing_reason") == "subscription_update":
        t_type = "upsell"

    session.sql("""
        MERGE INTO NEXUS_APP.CORE.TRANSACTIONS t
        USING (SELECT ? AS transaction_id) s ON t.transaction_id = s.transaction_id
        WHEN NOT MATCHED THEN INSERT
            (transaction_id, org_id, customer_id, amount, currency,
             transaction_type, status, transaction_date, source_system)
        VALUES (?, ?, ?, ?, ?, ?, 'completed', ?, 'stripe')
    """, params=[
        inv["id"], inv["id"], org_id, inv["customer"],
        inv["amount_paid"] / 100.0,
        inv.get("currency", "usd").upper(),
        t_type,
        datetime.fromtimestamp(inv["created"]).date().isoformat(),
    ]).collect()


def run(session: Session, org_id: str = ORG_ID, since_days: int = 1) -> str:
    stripe.api_key = os.environ["STRIPE_SECRET_KEY"]
    since = int((datetime.now(timezone.utc) - timedelta(days=since_days)).timestamp())

    subs = stripe.Subscription.list(created={"gte": since}, limit=100, expand=["data.items"])
    sub_count = 0
    for sub in subs.auto_paging_iter():
        try:
            _upsert_subscription(session, sub, org_id)
            sub_count += 1
        except Exception as e:
            logger.warning("Failed sub %s: %s", sub.get("id"), e)

    invs = stripe.Invoice.list(created={"gte": since}, limit=100)
    inv_count = 0
    for inv in invs.auto_paging_iter():
        try:
            _upsert_invoice(session, inv, org_id)
            inv_count += 1
        except Exception as e:
            logger.warning("Failed invoice %s: %s", inv.get("id"), e)

    return f"OK: {sub_count} subscriptions + {inv_count} invoices sincronizados do Stripe para {org_id}"


if __name__ == "__main__":
    session = Session.builder.config("connection_name", "nexus_dev").create()
    print(run(session))
    session.close()
