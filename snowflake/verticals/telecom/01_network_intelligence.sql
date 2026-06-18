-- =============================================================================
-- NEXUS Vertical Pack — Telecom
-- Network intelligence, churn por ARPU, análise de qualidade de serviço (QoS)
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.VERTICAL_TELECOM
    COMMENT = 'NEXUS Vertical Pack — Telecom: network intelligence, QoS, ARPU churn';


-- ─── Perfil de rede e qualidade por cliente ───────────────────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_TELECOM.NETWORK_QUALITY_PROFILE (
    profile_id          VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    customer_id         VARCHAR(50)     NOT NULL,
    plan_type           VARCHAR(50),    -- prepaid | postpaid | enterprise | iot
    arpu_usd            NUMBER(10,2),   -- average revenue per user (monthly)
    avg_latency_ms      NUMBER(8,2),
    avg_packet_loss_pct NUMBER(5,2),
    avg_downtime_hours  NUMBER(8,2),
    complaints_30d      INTEGER         DEFAULT 0,
    nps_score           INTEGER,
    churn_probability   NUMBER(5,4),
    qos_score           NUMBER(5,2),    -- 0-100
    profile_date        DATE            DEFAULT CURRENT_DATE(),
    created_at          TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (profile_id),
    UNIQUE (org_id, customer_id, profile_date)
);


-- ─── SP: Calcular QoS score e risco de churn telco ───────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_TELECOM.SP_COMPUTE_TELECOM_SCORES(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_count INTEGER;
BEGIN
    MERGE INTO VERTICAL_TELECOM.NETWORK_QUALITY_PROFILE tgt
    USING (
        SELECT
            c.customer_id,
            :org_id                                         AS org_id,
            c.arr_usd / 12                                 AS arpu_usd,

            -- QoS score: penaliza latência alta, packet loss e downtime
            GREATEST(0, LEAST(100,
                100
                - GREATEST(0, (COALESCE(ne.avg_latency_ms, 20) - 20) * 0.5)
                - (COALESCE(ne.avg_packet_loss_pct, 0) * 10)
                - (COALESCE(ne.avg_downtime_hours, 0) * 5)
                - (COALESCE(ne.complaints_30d, 0) * 3)
            ))                                             AS qos_score,

            COALESCE(ne.avg_latency_ms, 20)                AS avg_latency_ms,
            COALESCE(ne.avg_packet_loss_pct, 0)            AS avg_packet_loss_pct,
            COALESCE(ne.avg_downtime_hours, 0)             AS avg_downtime_hours,
            COALESCE(ne.complaints_30d, 0)                 AS complaints_30d,

            -- Churn probability: QoS ruim + muitas reclamações + health baixo
            ROUND(LEAST(0.99,
                (1 - c.health_score / 100.0) * 0.5
                + (COALESCE(ne.complaints_30d, 0) / 10.0) * 0.3
                + CASE c.churn_risk_level WHEN 'HIGH' THEN 0.3 WHEN 'MEDIUM' THEN 0.15 ELSE 0 END
            ), 4)                                          AS churn_probability

        FROM NEXUS_APP.MART.CUSTOMER_360 c
        LEFT JOIN NEXUS_APP.CORE.NETWORK_EVENTS ne
               ON ne.customer_id = c.customer_id AND ne.org_id = c.org_id
              AND ne.event_date >= DATEADD('day', -30, CURRENT_DATE())
        WHERE c.org_id = :org_id
    ) src
    ON tgt.customer_id = src.customer_id AND tgt.org_id = src.org_id
       AND tgt.profile_date = CURRENT_DATE()
    WHEN MATCHED THEN UPDATE SET
        arpu_usd          = src.arpu_usd,
        avg_latency_ms    = src.avg_latency_ms,
        avg_packet_loss_pct = src.avg_packet_loss_pct,
        avg_downtime_hours= src.avg_downtime_hours,
        complaints_30d    = src.complaints_30d,
        qos_score         = src.qos_score,
        churn_probability = src.churn_probability,
        created_at        = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (org_id, customer_id, arpu_usd, avg_latency_ms, avg_packet_loss_pct,
         avg_downtime_hours, complaints_30d, qos_score, churn_probability)
    VALUES
        (src.org_id, src.customer_id, src.arpu_usd, src.avg_latency_ms,
         src.avg_packet_loss_pct, src.avg_downtime_hours, src.complaints_30d,
         src.qos_score, src.churn_probability);

    SELECT COUNT(*) INTO v_count
    FROM VERTICAL_TELECOM.NETWORK_QUALITY_PROFILE
    WHERE org_id = :org_id AND profile_date = CURRENT_DATE();

    RETURN 'Scored ' || v_count::VARCHAR || ' telecom customers.';
END;
$$;


-- ─── SP: Diagnóstico de rede via LLM ─────────────────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_TELECOM.SP_NETWORK_DIAGNOSIS(customer_id VARCHAR, org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_context VARCHAR; v_diagnosis VARCHAR;
BEGIN
    SELECT
        'Cliente: '    || c.customer_name ||
        '\nARPU: $'    || ROUND(t.arpu_usd, 2)::VARCHAR ||
        '\nQoS: '      || t.qos_score::VARCHAR || '/100' ||
        '\nLatência: ' || t.avg_latency_ms::VARCHAR || 'ms' ||
        '\nPacket loss: ' || t.avg_packet_loss_pct::VARCHAR || '%' ||
        '\nDowntime (30d): ' || t.avg_downtime_hours::VARCHAR || 'h' ||
        '\nReclamações (30d): ' || t.complaints_30d::VARCHAR ||
        '\nRisco de churn: ' || ROUND(t.churn_probability * 100, 1)::VARCHAR || '%'
    INTO v_context
    FROM VERTICAL_TELECOM.NETWORK_QUALITY_PROFILE t
    JOIN NEXUS_APP.MART.CUSTOMER_360 c
         ON t.customer_id = c.customer_id AND t.org_id = c.org_id
    WHERE t.customer_id = :customer_id AND t.org_id = :org_id
    ORDER BY t.profile_date DESC LIMIT 1;

    IF (v_context IS NULL) THEN RETURN 'Dados insuficientes.'; END IF;

    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
            'role', 'user',
            'content', 'Você é um especialista em qualidade de rede e retenção de clientes de telecom. ' ||
                'Analise os dados abaixo e forneça: 1) diagnóstico do problema, 2) causa-raiz provável, ' ||
                '3) ação imediata recomendada, 4) risco financeiro se não agir. Máximo 200 palavras.\n\n' || :v_context
        ))
    ) INTO v_diagnosis;

    RETURN v_diagnosis;
END;
$$;


-- ─── View: ranking de clientes por risco de churn * ARPU ─────────────────────

CREATE OR REPLACE VIEW VERTICAL_TELECOM.V_CHURN_ARPU_MATRIX AS
SELECT
    t.org_id,
    c.customer_name,
    c.segment,
    t.arpu_usd,
    t.qos_score,
    t.churn_probability,
    ROUND(t.arpu_usd * 12 * t.churn_probability, 0) AS arr_at_risk_usd,
    t.complaints_30d,
    t.avg_downtime_hours,
    CASE
        WHEN t.churn_probability >= 0.7 AND t.arpu_usd >= 1000 THEN 'CRITICAL'
        WHEN t.churn_probability >= 0.5                          THEN 'HIGH'
        WHEN t.churn_probability >= 0.3                          THEN 'MEDIUM'
        ELSE 'LOW'
    END AS intervention_priority,
    t.profile_date
FROM VERTICAL_TELECOM.NETWORK_QUALITY_PROFILE t
JOIN NEXUS_APP.MART.CUSTOMER_360 c
     ON t.customer_id = c.customer_id AND t.org_id = c.org_id
WHERE t.profile_date = CURRENT_DATE()
ORDER BY arr_at_risk_usd DESC NULLS LAST;


-- ─── Task diária ──────────────────────────────────────────────────────────────

CREATE OR REPLACE TASK VERTICAL_TELECOM.TASK_TELECOM_INTELLIGENCE
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 3 * * * UTC'
AS
DECLARE v_org VARCHAR;
BEGIN
    FOR rec IN (SELECT DISTINCT org_id FROM NEXUS_APP.CORE.ORGANIZATIONS WHERE is_active = TRUE AND vertical = 'telecom') DO
        v_org := rec.org_id;
        CALL VERTICAL_TELECOM.SP_COMPUTE_TELECOM_SCORES(:v_org);
    END FOR;
END;

ALTER TASK VERTICAL_TELECOM.TASK_TELECOM_INTELLIGENCE RESUME;
