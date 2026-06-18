"""
NEXUS AI DataOps — Tests: Churn Model
pytest tests for snowflake/models/churn_model.py
Run: pytest tests/python/test_churn_model.py -v
"""

import pytest
from unittest.mock import MagicMock, patch, call


# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def mock_session():
    session = MagicMock()
    session.sql.return_value.collect.return_value = []
    return session


@pytest.fixture
def sample_row():
    return {
        "CUSTOMER_ID":            "cust-001",
        "ORG_ID":                 "ORG-DEMO-001",
        "HEALTH_SCORE":           35.0,
        "NPS_SCORE":              -30.0,
        "CHURN_PROBABILITY":      0.0,
        "EVENTS_30D":             2.0,
        "ACTIVE_DAYS_30D":        3.0,
        "DAYS_SINCE_LAST_ACTIVITY": 20.0,
        "OPEN_TICKETS":           5.0,
        "SLA_BREACHES":           3.0,
        "MRR":                    500.0,
        "ML_CHURN_PROBABILITY":   0.78,
        "LIFECYCLE_STAGE":        "active",
    }


# ─────────────────────────────────────────────────────────────────────────────
# Unit tests: _risk_level
# ─────────────────────────────────────────────────────────────────────────────

def test_risk_level_high():
    from snowflake.models.churn_model import _risk_level
    assert _risk_level(0.70) == "HIGH"
    assert _risk_level(0.99) == "HIGH"
    assert _risk_level(0.65) == "HIGH"


def test_risk_level_medium():
    from snowflake.models.churn_model import _risk_level
    assert _risk_level(0.50) == "MEDIUM"
    assert _risk_level(0.35) == "MEDIUM"


def test_risk_level_low():
    from snowflake.models.churn_model import _risk_level
    assert _risk_level(0.34) == "LOW"
    assert _risk_level(0.0)  == "LOW"


# ─────────────────────────────────────────────────────────────────────────────
# Unit tests: _top_drivers
# ─────────────────────────────────────────────────────────────────────────────

def test_top_drivers_critical_health(sample_row):
    from snowflake.models.churn_model import _top_drivers
    drivers = _top_drivers(sample_row)
    assert "health_score_crítico" in drivers


def test_top_drivers_low_nps(sample_row):
    from snowflake.models.churn_model import _top_drivers
    drivers = _top_drivers(sample_row)
    assert "nps_muito_baixo" in drivers


def test_top_drivers_max_three(sample_row):
    from snowflake.models.churn_model import _top_drivers
    drivers = _top_drivers(sample_row)
    assert len(drivers) <= 3


def test_top_drivers_empty_row():
    from snowflake.models.churn_model import _top_drivers
    drivers = _top_drivers({})
    assert len(drivers) > 0  # fallback sempre retorna algo


# ─────────────────────────────────────────────────────────────────────────────
# Unit tests: _recommended_action
# ─────────────────────────────────────────────────────────────────────────────

def test_recommended_action_high_engagement():
    from snowflake.models.churn_model import _recommended_action
    action = _recommended_action("HIGH", ["baixo_engajamento"])
    assert "QBR" in action or "onboarding" in action


def test_recommended_action_high_sla():
    from snowflake.models.churn_model import _recommended_action
    action = _recommended_action("HIGH", ["multiplas_violacoes_sla"])
    assert "SLA" in action or "CS" in action


def test_recommended_action_medium_nps():
    from snowflake.models.churn_model import _recommended_action
    action = _recommended_action("MEDIUM", ["nps_muito_baixo"])
    assert "NPS" in action or "feedback" in action


def test_recommended_action_low_risk():
    from snowflake.models.churn_model import _recommended_action
    action = _recommended_action("LOW", ["perfil_de_risco_moderado"])
    assert len(action) > 0


# ─────────────────────────────────────────────────────────────────────────────
# Integration smoke tests (mocked session)
# ─────────────────────────────────────────────────────────────────────────────

def test_train_and_score_empty_dataset(mock_session):
    """Deve retornar erro quando não há dados."""
    from snowflake.models.churn_model import train_and_score

    mock_df = MagicMock()
    mock_df.with_column.return_value = mock_df
    mock_df.fill_na.return_value = mock_df
    mock_df.filter.return_value = mock_df

    pipeline_mock = MagicMock()
    pipeline_mock.predict.return_value = MagicMock()
    pipeline_mock.predict.return_value.select.return_value.collect.return_value = []

    mock_session.table.return_value = mock_df

    with patch("snowflake.models.churn_model.Pipeline", return_value=pipeline_mock):
        result = train_and_score(mock_session)

    assert "ERROR" in result or "OK" in result


def test_feature_cols_completeness():
    """FEATURE_COLS deve conter todas as colunas esperadas pelo modelo."""
    from snowflake.models.churn_model import FEATURE_COLS
    required = [
        "HEALTH_SCORE", "NPS_SCORE", "CHURN_PROBABILITY",
        "EVENTS_30D", "ACTIVE_DAYS_30D", "DAYS_SINCE_LAST_ACTIVITY",
        "OPEN_TICKETS", "SLA_BREACHES", "MRR",
    ]
    for col in required:
        assert col in FEATURE_COLS, f"Missing feature column: {col}"


def test_label_col_defined():
    from snowflake.models.churn_model import LABEL_COL
    assert LABEL_COL == "IS_CHURNED"
