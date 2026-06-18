"""
NEXUS AI DataOps — Salesforce CRM Ingestion Pipeline
Extrai Accounts, Opportunities e Contacts via Salesforce REST API
e carrega em NEXUS_APP.CORE via COPY INTO / INSERT.
"""

import logging
import os
from datetime import datetime, timedelta, timezone

import requests
from snowflake.snowpark import Session

logger = logging.getLogger(__name__)

ORG_ID     = os.getenv("NEXUS_ORG_ID", "ORG-DEMO-001")
BATCH_SIZE = 200


class SalesforceClient:
    def __init__(self, instance_url: str, access_token: str):
        self.base   = instance_url.rstrip("/")
        self.token  = access_token
        self.headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}

    @classmethod
    def from_env(cls) -> "SalesforceClient":
        resp = requests.post(
            f"{os.environ['SF_INSTANCE_URL']}/services/oauth2/token",
            data={
                "grant_type":    "password",
                "client_id":     os.environ["SF_CLIENT_ID"],
                "client_secret": os.environ["SF_CLIENT_SECRET"],
                "username":      os.environ["SF_USERNAME"],
                "password":      os.environ["SF_PASSWORD"] + os.environ.get("SF_SECURITY_TOKEN", ""),
            },
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        return cls(data["instance_url"], data["access_token"])

    def query(self, soql: str) -> list[dict]:
        records, url = [], f"{self.base}/services/data/v58.0/query?q={requests.utils.quote(soql)}"
        while url:
            r = requests.get(url, headers=self.headers, timeout=30)
            r.raise_for_status()
            body = r.json()
            records.extend(body.get("records", []))
            url = self.base + body["nextRecordsUrl"] if not body.get("done") else None
        return records


def _upsert_customers(session: Session, accounts: list[dict], org_id: str) -> int:
    inserted = 0
    for a in accounts:
        try:
            session.sql("""
                MERGE INTO NEXUS_APP.CORE.CUSTOMERS t
                USING (SELECT ? AS customer_id) s ON t.customer_id = s.customer_id
                WHEN MATCHED THEN UPDATE SET
                    name = ?, email = ?, segment = ?, region = ?,
                    industry = ?, source_system = 'salesforce', updated_at = CURRENT_TIMESTAMP()
                WHEN NOT MATCHED THEN INSERT
                    (customer_id, org_id, name, email, segment, region, industry,
                     lifecycle_stage, source_system)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'active', 'salesforce')
            """, params=[
                a["Id"],
                a.get("Name", ""), a.get("BillingEmail", ""),
                a.get("Industry", "SMB"), a.get("BillingCountry", ""),
                a.get("Industry", ""),
                a["Id"], org_id, a.get("Name", ""), a.get("BillingEmail", ""),
                a.get("Industry", "SMB"), a.get("BillingCountry", ""), a.get("Industry", ""),
            ]).collect()
            inserted += 1
        except Exception as e:
            logger.warning("Failed to upsert account %s: %s", a.get("Id"), e)
    return inserted


def run(session: Session, org_id: str = ORG_ID, since_days: int = 1) -> str:
    sf   = SalesforceClient.from_env()
    since = (datetime.now(timezone.utc) - timedelta(days=since_days)).strftime("%Y-%m-%dT%H:%M:%SZ")

    accounts = sf.query(
        f"SELECT Id,Name,BillingEmail,Industry,BillingCountry,AnnualRevenue "
        f"FROM Account WHERE LastModifiedDate >= {since} LIMIT 10000"
    )

    n = _upsert_customers(session, accounts, org_id)
    return f"OK: {n}/{len(accounts)} accounts sincronizados do Salesforce para {org_id}"


if __name__ == "__main__":
    session = Session.builder.config("connection_name", "nexus_dev").create()
    print(run(session))
    session.close()
