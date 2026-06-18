"""
NEXUS AI DataOps — Demo Data Generator (Python)
Gera dados sintéticos realistas para demonstração e testes.
Complementa 11_sample_data.sql com dados atualizados (timestamps recentes).
"""

import os
import random
import uuid
from datetime import datetime, timedelta, timezone

from snowflake.snowpark import Session

ORG_ID   = os.getenv("NEXUS_ORG_ID", "ORG-DEMO-001")
N_CUSTOMERS = int(os.getenv("DEMO_CUSTOMERS", "50"))

SEGMENTS   = ["ENTERPRISE", "MID_MARKET", "SMB", "STARTUP"]
REGIONS    = ["North America", "LATAM", "Europe", "APAC"]
INDUSTRIES = ["technology", "financial_services", "healthcare", "retail", "manufacturing"]
STAGES     = ["active", "active", "active", "at_risk", "onboarding", "churned"]
PRIORITIES = ["low", "medium", "high", "critical"]
TX_TYPES   = ["new_contract", "renewal", "upsell", "downgrade", "churn"]

random.seed(42)


def _rand_date(days_back: int = 365) -> str:
    d = datetime.now(timezone.utc) - timedelta(days=random.randint(0, days_back))
    return d.strftime("%Y-%m-%d")


def _recent_ts() -> str:
    d = datetime.now(timezone.utc) - timedelta(hours=random.randint(0, 48))
    return d.isoformat()


def generate_customers(session: Session, org_id: str, n: int) -> list[str]:
    ids = []
    for _ in range(n):
        cid   = str(uuid.uuid4())
        stage = random.choice(STAGES)
        mrr   = round(random.uniform(500, 50000), 2)
        session.sql("""
            INSERT INTO NEXUS_APP.CORE.CUSTOMERS
                (customer_id, org_id, name, email, segment, region, industry,
                 lifecycle_stage, arr, mrr, nps_score, source_system,
                 created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'demo', ?, ?)
        """, params=[
            cid, org_id,
            f"Demo Corp {random.randint(1000, 9999)}",
            f"contact-{cid[:8]}@democorp.com",
            random.choice(SEGMENTS), random.choice(REGIONS), random.choice(INDUSTRIES),
            stage, mrr * 12, mrr,
            random.randint(-20, 80),
            _recent_ts(), _recent_ts(),
        ]).collect()
        ids.append(cid)
    return ids


def generate_tickets(session: Session, org_id: str, customer_ids: list[str], n_per_customer: int = 3) -> int:
    total = 0
    for cid in customer_ids:
        for _ in range(random.randint(0, n_per_customer)):
            session.sql("""
                INSERT INTO NEXUS_APP.CORE.TICKETS
                    (org_id, customer_id, subject, status, priority,
                     sla_breached, source_system, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, 'demo', ?, ?)
            """, params=[
                org_id, cid,
                f"Issue #{random.randint(1000, 9999)}: {random.choice(['Login', 'Performance', 'Data', 'API'])} problem",
                random.choice(["open", "open", "resolved"]),
                random.choice(PRIORITIES),
                random.random() < 0.15,
                _recent_ts(), _recent_ts(),
            ]).collect()
            total += 1
    return total


def generate_transactions(session: Session, org_id: str, customer_ids: list[str]) -> int:
    total = 0
    for cid in customer_ids:
        for _ in range(random.randint(1, 4)):
            amount = round(random.uniform(1000, 120000), 2)
            session.sql("""
                INSERT INTO NEXUS_APP.CORE.TRANSACTIONS
                    (transaction_id, org_id, customer_id, amount, currency,
                     transaction_type, status, transaction_date, source_system, created_at)
                VALUES (?, ?, ?, ?, 'USD', ?, 'completed', ?, 'demo', ?)
            """, params=[
                str(uuid.uuid4()), org_id, cid, amount,
                random.choice(TX_TYPES),
                _rand_date(180),
                _recent_ts(),
            ]).collect()
            total += 1
    return total


def run(session: Session, org_id: str = ORG_ID, n_customers: int = N_CUSTOMERS) -> str:
    # Limpa dados demo anteriores para evitar duplicatas
    session.sql(
        "DELETE FROM NEXUS_APP.CORE.CUSTOMERS WHERE org_id = ? AND source_system = 'demo'",
        params=[org_id]
    ).collect()

    ids    = generate_customers(session, org_id, n_customers)
    tix    = generate_tickets(session, org_id, ids)
    txs    = generate_transactions(session, org_id, ids)

    return (
        f"OK: {len(ids)} customers, {tix} tickets, {txs} transactions "
        f"gerados para {org_id}"
    )


if __name__ == "__main__":
    session = Session.builder.config("connection_name", "nexus_dev").create()
    print(run(session))
    session.close()
