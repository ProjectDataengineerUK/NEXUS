"""
NEXUS AI DataOps — Tests: recommendation_model + forecast_model
Covers session-based functions via MagicMock injection.
"""

import pytest
from unittest.mock import MagicMock, patch


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _sql_mock(session, return_value):
    """Make session.sql(...).collect() return return_value."""
    session.sql.return_value.collect.return_value = return_value
    return session


def _make_row(**kwargs):
    row = MagicMock()
    row.__getitem__ = lambda self, k: kwargs[k]
    row.get = lambda k, d=None: kwargs.get(k, d)
    row.as_dict.return_value = kwargs
    for k, v in kwargs.items():
        setattr(row, k, v)
    return row


# ─────────────────────────────────────────────────────────────────────────────
# recommendation_model
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def rec_session():
    return MagicMock()


def test_generate_recommendations_no_rows(rec_session):
    from snowflake.models.recommendation_model import generate_recommendations
    rec_session.sql.return_value.collect.return_value = []
    result = generate_recommendations(rec_session, "ORG-001")
    assert "sem novos" in result


def test_generate_recommendations_returns_ok(rec_session):
    from snowflake.models.recommendation_model import generate_recommendations

    customer_row = _make_row(
        CUSTOMER_ID="cust-1",
        ORG_ID="ORG-001",
        CUSTOMER_NAME="Acme",
        RISK_LEVEL="HIGH",
        CHURN_PROBABILITY=0.80,
        RECOMMENDED_ACTION="Call customer",
        TOP_DRIVERS='["baixo_engajamento", "sla_breach"]',
        EXPECTED_REVENUE_AT_RISK=5000.0,
        HEALTH_SCORE=30.0,
        NPS_SCORE=-20.0,
        ARR=60000.0,
        SEGMENT="enterprise",
        NEAREST_RENEWAL_DATE="2026-09-01",
    )
    cortex_row = _make_row(REC="Agende uma reunião executiva imediatamente.")

    call_count = [0]

    def side_effect(*args, **kwargs):
        m = MagicMock()
        if call_count[0] == 0:
            m.collect.return_value = [customer_row]
        elif call_count[0] == 1:
            m.collect.return_value = [cortex_row]
        else:
            m.collect.return_value = []
        call_count[0] += 1
        return m

    rec_session.sql.side_effect = side_effect
    result = generate_recommendations(rec_session, "ORG-001")
    assert "OK" in result
    assert "1" in result


def test_generate_recommendations_json_drivers(rec_session):
    from snowflake.models.recommendation_model import generate_recommendations

    row = _make_row(
        CUSTOMER_ID="c2", ORG_ID="ORG-002", CUSTOMER_NAME="Beta",
        RISK_LEVEL="MEDIUM", CHURN_PROBABILITY=0.45,
        RECOMMENDED_ACTION="Monitor", TOP_DRIVERS=["item1", "item2"],
        EXPECTED_REVENUE_AT_RISK=1000.0, HEALTH_SCORE=55.0,
        NPS_SCORE=5.0, ARR=12000.0, SEGMENT="smb",
        NEAREST_RENEWAL_DATE="2026-12-01",
    )
    cortex_row = _make_row(REC="Envie pesquisa de satisfação.")
    calls = [0]

    def side(sql, *a, **kw):
        m = MagicMock()
        if calls[0] == 0:
            m.collect.return_value = [row]
        elif calls[0] == 1:
            m.collect.return_value = [cortex_row]
        else:
            m.collect.return_value = []
        calls[0] += 1
        return m

    rec_session.sql.side_effect = side
    result = generate_recommendations(rec_session, "ORG-002")
    assert "OK" in result


def test_run_all_orgs_no_orgs(rec_session):
    from snowflake.models.recommendation_model import run_all_orgs
    rec_session.sql.return_value.collect.return_value = []
    result = run_all_orgs(rec_session)
    assert "nenhum org ativo" in result


def test_run_all_orgs_with_orgs(rec_session):
    from snowflake.models.recommendation_model import run_all_orgs

    org_row = _make_row(ORG_ID="ORG-001")
    calls = [0]

    def side(sql, *a, **kw):
        m = MagicMock()
        if calls[0] == 0:
            m.collect.return_value = [org_row]
        else:
            m.collect.return_value = []
        calls[0] += 1
        return m

    rec_session.sql.side_effect = side
    result = run_all_orgs(rec_session)
    assert isinstance(result, str)
    assert len(result) > 0


# ─────────────────────────────────────────────────────────────────────────────
# forecast_model
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def fc_session():
    return MagicMock()


def test_forecast_constants():
    from snowflake.models.forecast_model import FORECAST_DAYS, MIN_HISTORY, MODEL_VERSION
    assert FORECAST_DAYS == 30
    assert MIN_HISTORY == 14
    assert "1.0.0" in MODEL_VERSION


def test_moving_average_fallback_with_data(fc_session):
    from snowflake.models.forecast_model import _moving_average_fallback, FORECAST_DAYS
    avg_row = _make_row(AVG_REV=1000.0)
    fc_session.sql.return_value.collect.return_value = [avg_row]
    result = _moving_average_fallback(fc_session, "ORG-001")
    assert len(result) == FORECAST_DAYS
    assert result[0]["forecast_value"] == 1000.0
    assert result[0]["lower_bound"] == round(1000.0 * 0.80, 2)
    assert result[0]["upper_bound"] == round(1000.0 * 1.20, 2)
    assert result[0]["org_id"] == "ORG-001"
    assert "fallback" in result[0]["model_version"]


def test_moving_average_fallback_empty_session(fc_session):
    from snowflake.models.forecast_model import _moving_average_fallback, FORECAST_DAYS
    fc_session.sql.return_value.collect.return_value = []
    result = _moving_average_fallback(fc_session, "ORG-002")
    assert len(result) == FORECAST_DAYS
    assert result[0]["forecast_value"] == 0.0


def test_moving_average_fallback_null_avg(fc_session):
    from snowflake.models.forecast_model import _moving_average_fallback
    avg_row = _make_row(AVG_REV=None)
    fc_session.sql.return_value.collect.return_value = [avg_row]
    result = _moving_average_fallback(fc_session, "ORG-003")
    assert result[0]["forecast_value"] == 0.0


def test_run_uses_fallback_when_insufficient_history(fc_session):
    from snowflake.models.forecast_model import run, MIN_HISTORY
    count_row = _make_row(N=MIN_HISTORY - 1)
    avg_row   = _make_row(AVG_REV=500.0)
    calls = [0]

    def side(sql, *a, **kw):
        m = MagicMock()
        if calls[0] == 0:
            m.collect.return_value = [count_row]
        elif calls[0] == 1:
            m.collect.return_value = [avg_row]
        else:
            m.collect.return_value = []
        calls[0] += 1
        return m

    fc_session.sql.side_effect = side
    result = run(fc_session, "ORG-001")
    assert "fallback" in result
    assert "ORG-001" in result


def test_run_uses_forecaster_when_enough_history(fc_session):
    from snowflake.models.forecast_model import run, MIN_HISTORY

    count_row = _make_row(N=MIN_HISTORY + 5)
    pred_row  = _make_row(DS="2026-07-01", FORECAST=1200.0, LOWER_BOUND=960.0, UPPER_BOUND=1440.0)
    calls = [0]

    def side(sql, *a, **kw):
        m = MagicMock()
        if calls[0] == 0:        # COUNT query
            m.collect.return_value = [count_row]
        elif calls[0] == 1:      # training_df (just returned as DF)
            m.collect.return_value = []
        elif calls[0] == 2:      # future_df
            m.collect.return_value = []
        elif calls[0] == 3:      # DELETE
            m.collect.return_value = []
        else:                    # INSERT per row
            m.collect.return_value = []
        calls[0] += 1
        return m

    forecaster_instance = MagicMock()
    pred_df = MagicMock()
    pred_df.collect.return_value = [pred_row]
    forecaster_instance.predict.return_value = pred_df

    fc_session.sql.side_effect = side

    with patch("snowflake.models.forecast_model.Forecaster", return_value=forecaster_instance):
        result = run(fc_session, "ORG-001")

    assert "OK" in result
