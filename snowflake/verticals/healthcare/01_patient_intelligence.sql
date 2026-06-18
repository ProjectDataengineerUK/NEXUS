-- =============================================================================
-- NEXUS Vertical Pack — Healthcare & Pharma
-- Patient engagement, care gap detection, population health, compliance LGPD/HIPAA
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.VERTICAL_HEALTH
    COMMENT = 'NEXUS Vertical Pack — Healthcare: patient intelligence, care gaps, compliance';


-- ─── Perfil de saúde do paciente / conta ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_HEALTH.PATIENT_ENGAGEMENT_PROFILE (
    profile_id              VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id                  VARCHAR(50)     NOT NULL,
    patient_id              VARCHAR(50)     NOT NULL,  -- entity_id no NEXUS (anonimizado)
    engagement_score        NUMBER(5,2),    -- 0-100: frequência de uso + adesão
    appointment_adherence   NUMBER(5,2),    -- % consultas realizadas vs. agendadas
    medication_adherence    NUMBER(5,2),    -- % doses tomadas (se disponível)
    care_gap_count          INTEGER         DEFAULT 0,
    care_gap_details        VARIANT,        -- ARRAY de gaps identificados
    readmission_risk        NUMBER(5,4),    -- 0-1: prob. readmissão em 30d
    population_segment      VARCHAR(50),    -- WELL | CHRONIC | HIGH_RISK | COMPLEX
    last_interaction_date   DATE,
    hipaa_consent           BOOLEAN         DEFAULT TRUE,
    lgpd_consent            BOOLEAN         DEFAULT TRUE,
    profile_date            DATE            DEFAULT CURRENT_DATE(),
    created_at              TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (profile_id),
    UNIQUE (org_id, patient_id, profile_date)
)
COMMENT = 'PHI — acesso restrito a NEXUS_HEALTH_ANALYST e NEXUS_ADMIN';


-- ─── Masking policy para PHI ──────────────────────────────────────────────────
-- patient_id é pseudonimizado por padrão; revelar só para NEXUS_ADMIN

CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_PATIENT_ID AS (val VARCHAR)
RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('NEXUS_ADMIN', 'NEXUS_HEALTH_ANALYST') THEN val
        ELSE '***-PHI-MASKED-***'
    END;

ALTER TABLE VERTICAL_HEALTH.PATIENT_ENGAGEMENT_PROFILE
    MODIFY COLUMN patient_id
        SET MASKING POLICY GOVERNANCE.MASK_PATIENT_ID;


-- ─── SP: Score de engajamento e gaps de cuidado ───────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_HEALTH.SP_COMPUTE_PATIENT_SCORES(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_count INTEGER;
BEGIN
    MERGE INTO VERTICAL_HEALTH.PATIENT_ENGAGEMENT_PROFILE tgt
    USING (
        SELECT
            c.customer_id                                       AS patient_id,
            :org_id                                             AS org_id,

            -- Engagement: health_score como proxy de adesão
            c.health_score                                      AS engagement_score,

            -- Appointment adherence: inverso do churn risk
            CASE c.churn_risk_level
                WHEN 'LOW'    THEN 85.0
                WHEN 'MEDIUM' THEN 60.0
                WHEN 'HIGH'   THEN 35.0
                ELSE 50.0
            END                                                 AS appointment_adherence,

            -- Care gaps: baseado em tickets de suporte abertos
            (SELECT COUNT(*) FROM NEXUS_APP.CORE.TICKETS t
             WHERE t.customer_id = c.customer_id AND t.org_id = c.org_id
               AND t.status = 'open'
               AND t.created_at >= DATEADD('day', -90, CURRENT_DATE()))
                                                                AS care_gap_count,

            -- Readmission risk: alta quando saúde cai rápido
            LEAST(0.99, GREATEST(0,
                (100 - c.health_score) / 100.0 * 0.6
                + CASE c.churn_risk_level WHEN 'HIGH' THEN 0.3 ELSE 0 END
            ))                                                  AS readmission_risk,

            CASE
                WHEN c.health_score >= 80 THEN 'WELL'
                WHEN c.health_score >= 60 THEN 'CHRONIC'
                WHEN c.health_score >= 40 THEN 'HIGH_RISK'
                ELSE 'COMPLEX'
            END                                                 AS population_segment,

            c.last_updated::DATE                                AS last_interaction_date

        FROM NEXUS_APP.MART.CUSTOMER_360 c
        WHERE c.org_id = :org_id
    ) src
    ON tgt.patient_id = src.patient_id AND tgt.org_id = src.org_id
       AND tgt.profile_date = CURRENT_DATE()
    WHEN MATCHED THEN UPDATE SET
        engagement_score     = src.engagement_score,
        appointment_adherence= src.appointment_adherence,
        care_gap_count       = src.care_gap_count,
        readmission_risk     = src.readmission_risk,
        population_segment   = src.population_segment,
        last_interaction_date= src.last_interaction_date,
        created_at           = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (org_id, patient_id, engagement_score, appointment_adherence,
         care_gap_count, readmission_risk, population_segment, last_interaction_date)
    VALUES
        (src.org_id, src.patient_id, src.engagement_score, src.appointment_adherence,
         src.care_gap_count, src.readmission_risk, src.population_segment,
         src.last_interaction_date);

    SELECT COUNT(*) INTO v_count
    FROM VERTICAL_HEALTH.PATIENT_ENGAGEMENT_PROFILE
    WHERE org_id = :org_id AND profile_date = CURRENT_DATE();

    RETURN 'Scored ' || v_count::VARCHAR || ' patients.';
END;
$$;


-- ─── SP: Gerar plano de cuidado via LLM (sem PHI direto) ─────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_HEALTH.SP_CARE_PLAN_SUGGESTION(
    patient_id  VARCHAR,
    org_id      VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_context VARCHAR; v_plan VARCHAR;
BEGIN
    -- Contexto sem PHI identificável
    SELECT
        'Segmento: '        || p.population_segment ||
        '\nEngajamento: '   || p.engagement_score::VARCHAR || '/100' ||
        '\nAdesão a consultas: ' || p.appointment_adherence::VARCHAR || '%' ||
        '\nGaps de cuidado: ' || p.care_gap_count::VARCHAR ||
        '\nRisco readmissão 30d: ' || ROUND(p.readmission_risk * 100, 1)::VARCHAR || '%'
    INTO v_context
    FROM VERTICAL_HEALTH.PATIENT_ENGAGEMENT_PROFILE p
    WHERE p.patient_id = :patient_id AND p.org_id = :org_id
    ORDER BY p.profile_date DESC LIMIT 1;

    IF (v_context IS NULL) THEN RETURN 'Perfil não encontrado.'; END IF;

    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
            'role', 'system',
            'content', 'Você é um assistente de gestão de saúde populacional. Não processa PHI direto. Sugira intervenções com base em métricas agregadas anônimas. Seja objetivo e baseado em evidências. Máximo 200 palavras.'
        ), OBJECT_CONSTRUCT(
            'role', 'user',
            'content', 'Sugira um plano de engajamento para este perfil de paciente (anônimo):\n' || :v_context
        ))
    ) INTO v_plan;

    RETURN v_plan;
END;
$$;


-- ─── View: população por segmento de risco ───────────────────────────────────

CREATE OR REPLACE VIEW VERTICAL_HEALTH.V_POPULATION_HEALTH AS
SELECT
    org_id,
    population_segment,
    COUNT(*)                                AS patient_count,
    ROUND(AVG(engagement_score), 1)         AS avg_engagement,
    ROUND(AVG(appointment_adherence), 1)    AS avg_adherence_pct,
    ROUND(AVG(readmission_risk) * 100, 1)   AS avg_readmission_risk_pct,
    SUM(care_gap_count)                     AS total_care_gaps,
    profile_date
FROM VERTICAL_HEALTH.PATIENT_ENGAGEMENT_PROFILE
WHERE profile_date = CURRENT_DATE()
GROUP BY 1, 2, 6
ORDER BY CASE population_segment WHEN 'COMPLEX' THEN 1 WHEN 'HIGH_RISK' THEN 2
         WHEN 'CHRONIC' THEN 3 ELSE 4 END;


-- ─── Task diária ──────────────────────────────────────────────────────────────

CREATE OR REPLACE TASK VERTICAL_HEALTH.TASK_HEALTH_INTELLIGENCE
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 5 * * * UTC'
AS
DECLARE v_org VARCHAR;
BEGIN
    FOR rec IN (SELECT DISTINCT org_id FROM NEXUS_APP.CORE.ORGANIZATIONS WHERE is_active = TRUE AND vertical = 'healthcare') DO
        v_org := rec.org_id;
        CALL VERTICAL_HEALTH.SP_COMPUTE_PATIENT_SCORES(:v_org);
    END FOR;
END;

ALTER TASK VERTICAL_HEALTH.TASK_HEALTH_INTELLIGENCE RESUME;
