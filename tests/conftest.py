"""
NEXUS AI DataOps — pytest conftest.py
Shared fixtures for all test suites (unit + integration + agent eval).
Run: pytest tests/ -v
"""

import pathlib
import sys
import types

# ── make project root importable so 'snowflake.models.*' resolves locally ──
_ROOT = pathlib.Path(__file__).parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

# ── snowflake/models/*.py also import each other as bare top-level modules
# (e.g. `from recommendation_model import ...`), matching how the Native App
# package stages them flat in the same IMPORTS directory at runtime. Add that
# directory to sys.path so those sibling imports resolve locally too. ──
_MODELS_DIR = _ROOT / "snowflake" / "models"
if str(_MODELS_DIR) not in sys.path:
    sys.path.insert(0, str(_MODELS_DIR))

# ── stub snowflake.ml and snowflake.snowpark (not installed in CI) ──────────
from unittest.mock import MagicMock  # noqa: E402


def _stub(name: str, **attrs):
    """Register a lightweight stub module so top-level imports don't fail."""
    if name not in sys.modules:
        mod = types.ModuleType(name)
        mod.__path__ = []  # makes Python treat it as a package
        for k, v in attrs.items():
            setattr(mod, k, v)
        sys.modules[name] = mod
    return sys.modules[name]


_stub("snowflake.ml")
_stub("snowflake.ml.modeling")
_stub("snowflake.ml.modeling.linear_model",  LogisticRegression=MagicMock)
_stub("snowflake.ml.modeling.pipeline",      Pipeline=MagicMock)
_stub("snowflake.ml.modeling.preprocessing", StandardScaler=MagicMock)
_stub("snowflake.ml.modeling.forecast",      Forecaster=MagicMock)
_stub("snowflake.snowpark",                  Session=MagicMock)
_stub("snowflake.snowpark.functions",        col=MagicMock(), lit=MagicMock(), when=MagicMock())

# ────────────────────────────────────────────────────────────────────────────

import json
import pytest


# ─────────────────────────────────────────────────────────────────────────────
# Snowflake Session mock
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def mock_session():
    """Minimal Snowpark session mock — SQL returns empty list by default."""
    session = MagicMock()
    session.sql.return_value.collect.return_value = []
    session.sql.return_value.to_pandas.return_value = MagicMock()
    session.get_current_user.return_value = "TEST_USER"
    session.connection.host = "account.snowflakecomputing.com"
    session.connection.rest.token = "mock-token-001"
    return session


@pytest.fixture
def mock_session_with_customers(mock_session):
    """Session that returns sample customer rows from CORE.CUSTOMERS."""
    row = MagicMock()
    row.as_dict.return_value = {
        "CUSTOMER_ID": "cust-001",
        "ORG_ID": "ORG-DEMO-001",
        "COMPANY_NAME": "Acme Corp",
        "HEALTH_SCORE": 72.0,
        "NPS_SCORE": 30.0,
        "ARR": 120000.0,
        "MRR": 10000.0,
        "LIFECYCLE_STAGE": "active",
        "RISK_LEVEL": "LOW",
    }
    mock_session.sql.return_value.collect.return_value = [row]
    return mock_session


# ─────────────────────────────────────────────────────────────────────────────
# Sample domain objects
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def sample_customer_row():
    """Representative CUSTOMER_360 mart row for unit tests."""
    return {
        "CUSTOMER_ID":              "cust-001",
        "ORG_ID":                   "ORG-DEMO-001",
        "COMPANY_NAME":             "Acme Corp",
        "HEALTH_SCORE":             35.0,
        "NPS_SCORE":                -30.0,
        "CHURN_PROBABILITY":        0.0,
        "ML_CHURN_PROBABILITY":     0.78,
        "EVENTS_30D":               2.0,
        "ACTIVE_DAYS_30D":          3.0,
        "DAYS_SINCE_LAST_ACTIVITY": 20.0,
        "OPEN_TICKETS":             5.0,
        "SLA_BREACHES":             3.0,
        "MRR":                      500.0,
        "ARR":                      6000.0,
        "LIFECYCLE_STAGE":          "active",
        "RISK_LEVEL":               "HIGH",
    }


@pytest.fixture
def sample_agent_response():
    """Typical Cortex Agent REST response payload."""
    return {
        "content": "Acme Corp está em alto risco de churn. Recomenda-se ação imediata.",
        "usage": {"total_tokens": 412, "prompt_tokens": 320, "completion_tokens": 92},
        "latency_ms": 1850,
        "tool_uses": [
            {"tool": "cortex_analyst", "query": "SELECT churn_probability FROM ..."},
        ],
    }


@pytest.fixture
def sample_executive_kpis():
    """Row from MART.EXECUTIVE_KPIS for executive briefing tests."""
    return {
        "ORG_ID":               "ORG-DEMO-001",
        "SNAPSHOT_DATE":        "2026-06-17",
        "TOTAL_CUSTOMERS":      250,
        "HIGH_RISK_CUSTOMERS":  18,
        "MEDIUM_RISK_CUSTOMERS": 42,
        "TOTAL_ARR":            4_500_000.0,
        "ARR_AT_RISK":          320_000.0,
        "TOTAL_MRR":            375_000.0,
        "NET_REVENUE_RETENTION": 108.5,
        "AVG_HEALTH_SCORE":     71.3,
        "CHURN_RATE_30D":       1.2,
        "NEW_CUSTOMERS_30D":    7,
        "CHURNED_CUSTOMERS_30D": 3,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Cortex AI mocks
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def mock_cortex_complete():
    """Patch SNOWFLAKE.CORTEX.COMPLETE SQL function response."""
    with patch(
        "snowflake.models.churn_model.SNOWFLAKE.CORTEX.COMPLETE",
        return_value="Análise gerada pelo Cortex.",
    ) as m:
        yield m


@pytest.fixture
def mock_cortex_analyst_response():
    """Typical call_cortex_analyst return dict."""
    return {
        "sql": "SELECT customer_id, mrr FROM MART.CUSTOMER_360 ORDER BY mrr DESC LIMIT 10",
        "text": "Aqui estão os 10 maiores clientes por MRR.",
        "error": None,
        "latency_ms": 920,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Audit / logger helpers
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def mock_audit_logger(mock_session):
    """Returns a pre-configured audit_logger with injected mock session."""
    from app.streamlit.utils import audit_logger  # noqa: F401 — imported for side effects
    return mock_session


# ─────────────────────────────────────────────────────────────────────────────
# Auth fixtures
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def org_id():
    return "ORG-DEMO-001"


@pytest.fixture
def demo_user():
    return {"name": "TEST_USER", "role": "NEXUS_VIEWER", "org_id": "ORG-DEMO-001"}
