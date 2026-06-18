"""
NEXUS AI DataOps — External API Layer (FastAPI)
Exposição controlada de dados e ações para integrações bidirecionais:
CRM (Salesforce/HubSpot), Jira, ServiceNow, Slack, Webhooks externos.
"""

from __future__ import annotations

import os
import hashlib
import hmac
import time
from contextlib import asynccontextmanager
from typing import Any

import snowflake.connector
from fastapi import Depends, FastAPI, HTTPException, Header, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field


# ─── Snowflake connection pool ────────────────────────────────────────────────

def get_snowflake():
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role="NEXUS_API_ROLE",
        warehouse="NEXUS_COMPUTE_WH",
        database="NEXUS_APP",
        schema="CORE",
    )
    try:
        yield conn
    finally:
        conn.close()


# ─── Auth: API key validation ─────────────────────────────────────────────────

API_KEYS: dict[str, str] = {}  # key_hash -> org_id; loaded from env / secrets

def _load_api_keys() -> None:
    raw = os.environ.get("NEXUS_API_KEYS", "")
    for pair in raw.split(","):
        if ":" in pair:
            key, org = pair.strip().split(":", 1)
            API_KEYS[hashlib.sha256(key.encode()).hexdigest()] = org.strip()

def verify_api_key(x_api_key: str = Header(...)) -> str:
    key_hash = hashlib.sha256(x_api_key.encode()).hexdigest()
    org_id = API_KEYS.get(key_hash)
    if not org_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")
    return org_id

def verify_webhook_signature(request: Request, x_signature: str = Header("")) -> None:
    secret = os.environ.get("NEXUS_WEBHOOK_SECRET", "")
    body = request.state.body if hasattr(request.state, "body") else b""
    expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, x_signature):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid webhook signature")


# ─── App setup ────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    _load_api_keys()
    yield

app = FastAPI(
    title="NEXUS AI DataOps API",
    version="1.0.0",
    description="External integration layer for CRM, Jira, ServiceNow, and webhooks.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get("ALLOWED_ORIGINS", "*").split(","),
    allow_methods=["GET", "POST", "PATCH"],
    allow_headers=["*"],
)


# ─── Models ───────────────────────────────────────────────────────────────────

class CustomerSummary(BaseModel):
    customer_id:      str
    customer_name:    str
    health_score:     float | None
    churn_risk_level: str | None
    arr_usd:          float | None
    segment:          str | None
    renewal_date:     str | None

class RecommendationOut(BaseModel):
    recommendation_id:  str
    customer_id:        str
    recommendation_type:str
    priority:           str
    description:        str
    expected_impact_usd:float | None
    status:             str

class ActionRequest(BaseModel):
    recommendation_id: str = Field(..., description="ID da recomendação a executar")
    executed_by:       str = Field(..., description="Email ou ID do usuário executor")
    notes:             str | None = None

class ApprovalRequest(BaseModel):
    approval_id: str
    decision:    str  # approved | rejected
    decided_by:  str
    reason:      str | None = None

class WebhookEvent(BaseModel):
    event_type:  str
    org_id:      str
    payload:     dict[str, Any]
    timestamp:   float = Field(default_factory=time.time)


# ─── Health check ─────────────────────────────────────────────────────────────

@app.get("/health", tags=["system"])
def health():
    return {"status": "ok", "version": "1.0.0"}


# ─── Customer endpoints ───────────────────────────────────────────────────────

@app.get("/customers", response_model=list[CustomerSummary], tags=["customers"])
def list_customers(
    org_id: str = Depends(verify_api_key),
    risk_level: str | None = None,
    limit: int = 50,
    conn = Depends(get_snowflake),
):
    where = f"WHERE org_id = '{org_id}'"
    if risk_level:
        where += f" AND churn_risk_level = '{risk_level.upper()}'"
    cs = conn.cursor()
    cs.execute(f"""
        SELECT customer_id, customer_name, health_score, churn_risk_level,
               arr_usd, segment, TO_CHAR(renewal_date, 'YYYY-MM-DD') AS renewal_date
        FROM NEXUS_APP.MART.CUSTOMER_360
        {where}
        ORDER BY arr_usd DESC NULLS LAST
        LIMIT {min(limit, 200)}
    """)
    cols = [d[0].lower() for d in cs.description]
    return [dict(zip(cols, row)) for row in cs.fetchall()]


@app.get("/customers/{customer_id}", response_model=CustomerSummary, tags=["customers"])
def get_customer(
    customer_id: str,
    org_id: str = Depends(verify_api_key),
    conn = Depends(get_snowflake),
):
    cs = conn.cursor()
    cs.execute(f"""
        SELECT customer_id, customer_name, health_score, churn_risk_level,
               arr_usd, segment, TO_CHAR(renewal_date, 'YYYY-MM-DD') AS renewal_date
        FROM NEXUS_APP.MART.CUSTOMER_360
        WHERE org_id = '{org_id}' AND customer_id = '{customer_id}'
        LIMIT 1
    """)
    row = cs.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Customer not found")
    cols = [d[0].lower() for d in cs.description]
    return dict(zip(cols, row))


# ─── Recommendations endpoints ────────────────────────────────────────────────

@app.get("/recommendations", response_model=list[RecommendationOut], tags=["recommendations"])
def list_recommendations(
    org_id: str = Depends(verify_api_key),
    status: str = "pending",
    priority: str | None = None,
    limit: int = 50,
    conn = Depends(get_snowflake),
):
    where = f"WHERE org_id = '{org_id}' AND r.status = '{status}'"
    if priority:
        where += f" AND r.priority = '{priority.upper()}'"
    cs = conn.cursor()
    cs.execute(f"""
        SELECT recommendation_id, entity_id AS customer_id,
               recommendation_type, priority, description,
               expected_impact_usd, status
        FROM NEXUS_APP.AI.RECOMMENDATIONS r
        {where}
        ORDER BY CASE priority WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
                 expected_impact_usd DESC NULLS LAST
        LIMIT {min(limit, 200)}
    """)
    cols = [d[0].lower() for d in cs.description]
    return [dict(zip(cols, row)) for row in cs.fetchall()]


@app.patch("/recommendations/{recommendation_id}/execute", tags=["recommendations"])
def execute_recommendation(
    recommendation_id: str,
    body: ActionRequest,
    org_id: str = Depends(verify_api_key),
    conn = Depends(get_snowflake),
):
    cs = conn.cursor()
    cs.execute(f"""
        UPDATE NEXUS_APP.AI.RECOMMENDATIONS
        SET status = 'accepted', updated_at = CURRENT_TIMESTAMP()
        WHERE recommendation_id = '{recommendation_id}' AND org_id = '{org_id}'
          AND status = 'pending'
    """)
    if cs.rowcount == 0:
        raise HTTPException(status_code=404, detail="Recommendation not found or already actioned")
    cs.execute(f"""
        INSERT INTO NEXUS_APP.CORE.AUDIT_LOG
            (org_id, action, resource_type, resource_id, user_name, details)
        VALUES
            ('{org_id}', 'EXECUTE_VIA_API', 'RECOMMENDATION', '{recommendation_id}',
             '{body.executed_by}', PARSE_JSON('{{"notes": "{body.notes or ""}"}}'))
    """)
    return {"status": "accepted", "recommendation_id": recommendation_id}


# ─── Approval queue endpoints ─────────────────────────────────────────────────

@app.get("/approvals", tags=["approvals"])
def list_approvals(
    org_id: str = Depends(verify_api_key),
    conn = Depends(get_snowflake),
):
    cs = conn.cursor()
    cs.execute(f"""
        SELECT approval_id, action_type, risk_level, requested_by,
               status, hours_remaining
        FROM NEXUS_APP.CORE.V_APPROVAL_QUEUE
        WHERE org_id = '{org_id}' AND status = 'pending'
        LIMIT 100
    """)
    cols = [d[0].lower() for d in cs.description]
    return [dict(zip(cols, row)) for row in cs.fetchall()]


@app.patch("/approvals/{approval_id}", tags=["approvals"])
def decide_approval(
    approval_id: str,
    body: ApprovalRequest,
    org_id: str = Depends(verify_api_key),
    conn = Depends(get_snowflake),
):
    cs = conn.cursor()
    if body.decision == "approved":
        cs.execute(f"CALL NEXUS_APP.CORE.APPROVE_ACTION('{approval_id}', '{body.decided_by}')")
    elif body.decision == "rejected":
        reason = (body.reason or "").replace("'", "''")
        cs.execute(f"CALL NEXUS_APP.CORE.REJECT_ACTION('{approval_id}', '{body.decided_by}', '{reason}')")
    else:
        raise HTTPException(status_code=400, detail="decision must be 'approved' or 'rejected'")
    return {"status": body.decision, "approval_id": approval_id}


# ─── Webhook inbound (Salesforce, HubSpot, Jira) ─────────────────────────────

@app.post("/webhooks/inbound", tags=["webhooks"])
async def inbound_webhook(request: Request, event: WebhookEvent):
    cs_conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role="NEXUS_API_ROLE",
        warehouse="NEXUS_COMPUTE_WH",
        database="NEXUS_APP",
    )
    cs = cs_conn.cursor()
    import json
    payload_str = json.dumps(event.payload).replace("'", "''")
    cs.execute(f"""
        INSERT INTO NEXUS_APP.CORE.AUDIT_LOG
            (org_id, action, resource_type, resource_id, user_name, details)
        VALUES
            ('{event.org_id}', 'WEBHOOK_INBOUND', '{event.event_type}',
             NULL, 'webhook_service',
             PARSE_JSON('{payload_str}'))
    """)
    cs_conn.close()
    return {"received": True, "event_type": event.event_type}


# ─── Provider analytics (provider account only) ───────────────────────────────

@app.get("/provider/tenants", tags=["provider"])
def provider_tenant_overview(
    org_id: str = Depends(verify_api_key),
    conn = Depends(get_snowflake),
):
    if org_id != "NEXUS_PROVIDER":
        raise HTTPException(status_code=403, detail="Provider-only endpoint")
    cs = conn.cursor()
    cs.execute("""
        SELECT org_id, org_name, plan_tier, last_active,
               streamlit_dau, cortex_calls, agent_sessions,
               features_adopted, engagement_tier
        FROM NEXUS_APP.PROVIDER_ANALYTICS.V_TENANT_HEALTH_DASHBOARD
        ORDER BY cortex_calls DESC
        LIMIT 100
    """)
    cols = [d[0].lower() for d in cs.description]
    return [dict(zip(cols, row)) for row in cs.fetchall()]
