-- =============================================================================
-- NEXUS AI DataOps — Workflow Automation & Slack Notifications
-- Notification Integration + alert procedures + daily risk notification task
-- =============================================================================

USE SCHEMA NEXUS_APP.CORE;

-- ─── Notification Integration (Slack webhook via secret) ─────────────────────

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS NEXUS_SLACK_INTEGRATION
    TYPE = WEBHOOK
    ENABLED = TRUE
    WEBHOOK_URL = 'https://hooks.slack.com/services/PLACEHOLDER'
    WEBHOOK_SECRET = 'NEXUS_SLACK_SECRET'
    COMMENT = 'NEXUS AI DataOps — Slack alerts for high-risk customers and SLA breaches';

-- ─── SP: Send Slack alert ─────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.SEND_SLACK_ALERT(
    channel     VARCHAR,
    title       VARCHAR,
    message     VARCHAR,
    severity    VARCHAR  -- INFO | WARNING | CRITICAL
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'send_alert'
AS $$
import requests
import json

def send_alert(session, channel: str, title: str, message: str, severity: str) -> str:
    colour = {"INFO": "#36a64f", "WARNING": "#ff9900", "CRITICAL": "#cc0000"}.get(severity, "#36a64f")
    icon   = {"INFO": ":information_source:", "WARNING": ":warning:", "CRITICAL": ":rotating_light:"}.get(severity, ":bell:")

    payload = {
        "channel": channel,
        "attachments": [{
            "color": colour,
            "title": f"{icon} {title}",
            "text": message,
            "footer": "NEXUS AI DataOps",
            "ts": __import__("time").time(),
        }]
    }

    # Retrieve webhook URL from Snowflake secret
    row = session.sql(
        "SELECT SYSTEM$GET_SECRET_VALUE('NEXUS_SLACK_SECRET') AS url"
    ).collect()
    webhook_url = row[0]["URL"] if row else None

    if not webhook_url:
        return "ERROR: secret not configured"

    resp = requests.post(webhook_url, json=payload, timeout=10)
    return f"OK:{resp.status_code}" if resp.ok else f"ERROR:{resp.status_code}:{resp.text}"
$$;


-- ─── SP: Notify high-risk customers ──────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.NOTIFY_HIGH_RISK_CUSTOMERS(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_count INTEGER;
    v_msg   VARCHAR;
    v_title VARCHAR;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM NEXUS_APP.MART.CUSTOMER_360
    WHERE NEXUS_APP.MART.CUSTOMER_360.org_id = :org_id
      AND churn_risk_level = 'HIGH'
      AND health_score < 40;

    IF (v_count = 0) THEN
        RETURN 'No high-risk customers to notify.';
    END IF;

    -- Build summary of top 5 at-risk customers
    LET cur CURSOR FOR
        SELECT customer_name, health_score, arr_usd
        FROM NEXUS_APP.MART.CUSTOMER_360
        WHERE NEXUS_APP.MART.CUSTOMER_360.org_id = :org_id
          AND churn_risk_level = 'HIGH'
          AND health_score < 40
        ORDER BY arr_usd DESC NULLS LAST
        LIMIT 5;

    v_msg   := 'Top at-risk accounts:\n';
    v_title := '⚠️ ' || v_count::VARCHAR || ' High-Risk Customers Detected';

    FOR cur_row IN cur DO
        v_msg := v_msg || '• ' || cur_row.customer_name
                       || ' (Health: ' || cur_row.health_score::VARCHAR
                       || ' | ARR: $' || TO_CHAR(cur_row.arr_usd, '999,999,999') || ')\n';
    END FOR;

    CALL CORE.SEND_SLACK_ALERT(
        '#nexus-alerts',
        :v_title,
        :v_msg,
        'WARNING'
    );

    RETURN 'Notified: ' || v_count::VARCHAR || ' high-risk customers.';
END;
$$;


-- ─── SP: Notify SLA breaches ──────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.NOTIFY_SLA_BREACHES(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_count    INTEGER;
    v_critical INTEGER;
BEGIN
    SELECT
        COUNT(*),
        COUNT_IF(priority = 'CRITICAL')
    INTO v_count, v_critical
    FROM NEXUS_APP.MART.SUPPORT_TICKETS
    WHERE NEXUS_APP.MART.SUPPORT_TICKETS.org_id = :org_id
      AND sla_breached = TRUE
      AND status NOT IN ('resolved', 'closed')
      AND created_at >= DATEADD('day', -1, CURRENT_TIMESTAMP());

    IF (v_count = 0) THEN
        RETURN 'No SLA breaches.';
    END IF;

    CALL CORE.SEND_SLACK_ALERT(
        '#nexus-alerts',
        ':alarm_clock: SLA Breach Alert',
        v_count::VARCHAR || ' open SLA breaches (' || v_critical::VARCHAR || ' critical) in the last 24h.',
        CASE WHEN v_critical > 0 THEN 'CRITICAL' ELSE 'WARNING' END
    );

    RETURN 'SLA breach notification sent: ' || v_count::VARCHAR;
END;
$$;


-- ─── Task: daily alert digest (06:00 UTC) ────────────────────────────────────

CREATE OR REPLACE TASK CORE.TASK_DAILY_ALERTS
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 6 * * * UTC'
    COMMENT   = 'Daily Slack digest for high-risk customers and SLA breaches'
AS
DECLARE
    v_org VARCHAR;
BEGIN
    FOR rec IN (SELECT DISTINCT org_id FROM NEXUS_APP.CORE.ORGANIZATIONS WHERE is_active = TRUE) DO
        v_org := rec.org_id;
        CALL CORE.NOTIFY_HIGH_RISK_CUSTOMERS(:v_org);
        CALL CORE.NOTIFY_SLA_BREACHES(:v_org);
    END FOR;
END;

ALTER TASK CORE.TASK_DAILY_ALERTS RESUME;
