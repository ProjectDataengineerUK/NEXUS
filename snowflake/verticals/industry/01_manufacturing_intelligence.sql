-- =============================================================================
-- NEXUS Vertical Pack — Industry & Manufacturing
-- OEE (Overall Equipment Effectiveness), predictive maintenance, supply chain
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.VERTICAL_INDUSTRY
    COMMENT = 'NEXUS Vertical Pack — Manufacturing: OEE, predictive maintenance, supply chain';


-- ─── OEE e métricas de equipamento ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_INDUSTRY.EQUIPMENT_PERFORMANCE (
    perf_id             VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    equipment_id        VARCHAR(100)    NOT NULL,
    plant_id            VARCHAR(100),
    measurement_date    DATE            NOT NULL,
    availability_pct    NUMBER(5,2),    -- uptime / planned_time
    performance_pct     NUMBER(5,2),    -- actual_rate / ideal_rate
    quality_pct         NUMBER(5,2),    -- good_units / total_units
    oee_score           NUMBER(5,2),    -- availability * performance * quality
    mtbf_hours          NUMBER(10,2),   -- mean time between failures
    mttr_hours          NUMBER(8,2),    -- mean time to repair
    maintenance_due     DATE,
    failure_risk_score  NUMBER(5,4),    -- 0-1 predicted failure probability
    created_at          TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (perf_id),
    UNIQUE (org_id, equipment_id, measurement_date)
);


-- ─── Alertas de manutenção preditiva ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_INDUSTRY.MAINTENANCE_ALERTS (
    alert_id            VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    equipment_id        VARCHAR(100)    NOT NULL,
    plant_id            VARCHAR(100),
    alert_type          VARCHAR(50),    -- PREVENTIVE | PREDICTIVE | CORRECTIVE | URGENT
    severity            VARCHAR(20),
    description         VARCHAR(1000),
    recommended_action  VARCHAR(2000),
    estimated_downtime_hours NUMBER(6,1),
    cost_if_ignored_usd NUMBER(12,2),
    status              VARCHAR(20)     DEFAULT 'open',
    created_at          TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (alert_id)
);


-- ─── SP: Calcular OEE e risco de falha ───────────────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_INDUSTRY.SP_COMPUTE_OEE(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_count INTEGER;
BEGIN
    MERGE INTO VERTICAL_INDUSTRY.EQUIPMENT_PERFORMANCE tgt
    USING (
        SELECT
            e.equipment_id,
            :org_id                                                 AS org_id,
            e.plant_id,
            CURRENT_DATE()                                          AS measurement_date,

            -- Availability: baseado em uptime reportado
            COALESCE(e.uptime_hours / NULLIF(e.planned_hours, 0) * 100, 95) AS availability_pct,

            -- Performance: taxa real vs. ideal
            COALESCE(e.actual_units / NULLIF(e.ideal_units, 0) * 100, 90) AS performance_pct,

            -- Quality: unidades boas vs. total
            COALESCE(e.good_units / NULLIF(e.total_units, 0) * 100, 98) AS quality_pct,

            -- OEE = A * P * Q / 10000
            ROUND(
                COALESCE(e.uptime_hours / NULLIF(e.planned_hours, 0) * 100, 95) *
                COALESCE(e.actual_units / NULLIF(e.ideal_units, 0) * 100, 90) *
                COALESCE(e.good_units / NULLIF(e.total_units, 0) * 100, 98) / 10000,
                2
            )                                                       AS oee_score,

            e.mtbf_hours,
            e.mttr_hours,

            -- Próxima manutenção
            DATEADD('day', COALESCE(e.maintenance_interval_days, 90), e.last_maintenance_date) AS maintenance_due,

            -- Risco de falha: baixo MTBF + alta taxa de defeitos + OEE caindo
            LEAST(0.99, GREATEST(0,
                CASE WHEN e.mtbf_hours < 100 THEN 0.4 ELSE 0 END +
                CASE WHEN COALESCE(e.good_units / NULLIF(e.total_units, 0), 1) < 0.95 THEN 0.3 ELSE 0 END +
                CASE WHEN DATEADD('day', COALESCE(e.maintenance_interval_days, 90), e.last_maintenance_date) < CURRENT_DATE() THEN 0.4 ELSE 0 END
            ))                                                      AS failure_risk_score

        FROM NEXUS_APP.CORE.EQUIPMENT e
        WHERE e.org_id = :org_id AND e.is_active = TRUE
    ) src
    ON tgt.equipment_id = src.equipment_id AND tgt.org_id = src.org_id
       AND tgt.measurement_date = CURRENT_DATE()
    WHEN MATCHED THEN UPDATE SET
        availability_pct  = src.availability_pct,
        performance_pct   = src.performance_pct,
        quality_pct       = src.quality_pct,
        oee_score         = src.oee_score,
        mtbf_hours        = src.mtbf_hours,
        mttr_hours        = src.mttr_hours,
        maintenance_due   = src.maintenance_due,
        failure_risk_score= src.failure_risk_score,
        created_at        = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (org_id, equipment_id, plant_id, measurement_date, availability_pct,
         performance_pct, quality_pct, oee_score, mtbf_hours, mttr_hours,
         maintenance_due, failure_risk_score)
    VALUES (src.org_id, src.equipment_id, src.plant_id, src.measurement_date,
            src.availability_pct, src.performance_pct, src.quality_pct, src.oee_score,
            src.mtbf_hours, src.mttr_hours, src.maintenance_due, src.failure_risk_score);

    -- Gerar alertas para equipamentos de alto risco
    INSERT INTO VERTICAL_INDUSTRY.MAINTENANCE_ALERTS
        (org_id, equipment_id, plant_id, alert_type, severity, description,
         estimated_downtime_hours, cost_if_ignored_usd)
    SELECT
        p.org_id,
        p.equipment_id,
        p.plant_id,
        CASE
            WHEN p.maintenance_due <= CURRENT_DATE() THEN 'CORRECTIVE'
            WHEN p.failure_risk_score >= 0.7          THEN 'PREDICTIVE'
            WHEN p.oee_score < 65                     THEN 'PREVENTIVE'
            ELSE 'PREVENTIVE'
        END,
        CASE
            WHEN p.failure_risk_score >= 0.8 OR p.maintenance_due < CURRENT_DATE() THEN 'CRITICAL'
            WHEN p.failure_risk_score >= 0.5 THEN 'HIGH'
            ELSE 'MEDIUM'
        END,
        'OEE: ' || p.oee_score::VARCHAR || '% | Risco falha: ' ||
        ROUND(p.failure_risk_score * 100, 0)::VARCHAR || '% | Manutenção: ' ||
        TO_CHAR(p.maintenance_due),
        COALESCE(p.mttr_hours, 8),
        COALESCE(p.mttr_hours, 8) * 5000  -- custo estimado de downtime por hora
    FROM VERTICAL_INDUSTRY.EQUIPMENT_PERFORMANCE p
    WHERE p.org_id = :org_id
      AND p.measurement_date = CURRENT_DATE()
      AND (p.failure_risk_score >= 0.5 OR p.oee_score < 65 OR p.maintenance_due <= CURRENT_DATE());

    SELECT COUNT(*) INTO v_count
    FROM VERTICAL_INDUSTRY.EQUIPMENT_PERFORMANCE
    WHERE org_id = :org_id AND measurement_date = CURRENT_DATE();

    RETURN 'Processed ' || v_count::VARCHAR || ' equipment records.';
END;
$$;


-- ─── SP: Diagnóstico de manutenção via LLM ────────────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_INDUSTRY.SP_MAINTENANCE_DIAGNOSIS(
    equipment_id VARCHAR,
    org_id       VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_context VARCHAR; v_diagnosis VARCHAR;
BEGIN
    SELECT
        'Equipamento: '    || p.equipment_id ||
        '\nPlanta: '       || COALESCE(p.plant_id, 'N/A') ||
        '\nOEE: '          || p.oee_score::VARCHAR || '%' ||
        '\nDisponibilidade: ' || p.availability_pct::VARCHAR || '%' ||
        '\nPerformance: '  || p.performance_pct::VARCHAR || '%' ||
        '\nQualidade: '    || p.quality_pct::VARCHAR || '%' ||
        '\nMTBF: '         || COALESCE(p.mtbf_hours::VARCHAR, 'N/A') || 'h' ||
        '\nMTTR: '         || COALESCE(p.mttr_hours::VARCHAR, 'N/A') || 'h' ||
        '\nRisco falha: '  || ROUND(p.failure_risk_score * 100, 1)::VARCHAR || '%' ||
        '\nManutenção prevista: ' || TO_CHAR(p.maintenance_due)
    INTO v_context
    FROM VERTICAL_INDUSTRY.EQUIPMENT_PERFORMANCE p
    WHERE p.equipment_id = :equipment_id AND p.org_id = :org_id
    ORDER BY p.measurement_date DESC LIMIT 1;

    IF (v_context IS NULL) THEN RETURN 'Dados insuficientes.'; END IF;

    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
            'role', 'user',
            'content', 'Você é um especialista em manutenção industrial e OEE. ' ||
                'Analise os dados e forneça: 1) diagnóstico do estado do equipamento, ' ||
                '2) causa-raiz provável do baixo desempenho, ' ||
                '3) recomendação de manutenção com urgência, ' ||
                '4) impacto estimado no OEE se não houver intervenção. Máximo 250 palavras.\n\n' || :v_context
        ))
    ) INTO v_diagnosis;

    RETURN v_diagnosis;
END;
$$;


-- ─── View: ranking de equipamentos por OEE e risco ───────────────────────────

CREATE OR REPLACE VIEW VERTICAL_INDUSTRY.V_OEE_DASHBOARD AS
SELECT
    p.org_id,
    p.equipment_id,
    p.plant_id,
    p.oee_score,
    p.availability_pct,
    p.performance_pct,
    p.quality_pct,
    p.failure_risk_score,
    p.maintenance_due,
    DATEDIFF('day', p.maintenance_due, CURRENT_DATE()) AS days_overdue,
    COUNT(a.alert_id)   AS open_alerts,
    CASE
        WHEN p.oee_score >= 85  THEN 'WORLD_CLASS'
        WHEN p.oee_score >= 70  THEN 'GOOD'
        WHEN p.oee_score >= 60  THEN 'ACCEPTABLE'
        ELSE 'POOR'
    END AS oee_tier
FROM VERTICAL_INDUSTRY.EQUIPMENT_PERFORMANCE p
LEFT JOIN VERTICAL_INDUSTRY.MAINTENANCE_ALERTS a
       ON p.equipment_id = a.equipment_id AND p.org_id = a.org_id AND a.status = 'open'
WHERE p.measurement_date = CURRENT_DATE()
GROUP BY 1,2,3,4,5,6,7,8,9,10
ORDER BY p.failure_risk_score DESC NULLS LAST, p.oee_score ASC;


-- ─── Task diária ──────────────────────────────────────────────────────────────

CREATE OR REPLACE TASK VERTICAL_INDUSTRY.TASK_MANUFACTURING_INTELLIGENCE
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 2 * * * UTC'
AS
DECLARE v_org VARCHAR;
BEGIN
    FOR rec IN (SELECT DISTINCT org_id FROM NEXUS_APP.CORE.ORGANIZATIONS WHERE is_active = TRUE AND vertical = 'manufacturing') DO
        v_org := rec.org_id;
        CALL VERTICAL_INDUSTRY.SP_COMPUTE_OEE(:v_org);
    END FOR;
END;

ALTER TASK VERTICAL_INDUSTRY.TASK_MANUFACTURING_INTELLIGENCE RESUME;
