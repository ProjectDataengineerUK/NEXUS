-- =============================================================================
-- NEXUS Vertical Pack — Hospitality & Aviation
-- Guest intelligence, RevPAR, loyalty, ancillary revenue, flight disruption
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.VERTICAL_HOSPITALITY
    COMMENT = 'NEXUS Vertical Pack — Hospitality & Aviation: RevPAR, loyalty, guest intelligence';


-- ─── Perfil do hóspede / passageiro ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_HOSPITALITY.GUEST_PROFILE (
    profile_id          VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    guest_id            VARCHAR(50)     NOT NULL,
    loyalty_tier        VARCHAR(30),    -- BRONZE | SILVER | GOLD | PLATINUM | ELITE
    loyalty_points      INTEGER         DEFAULT 0,
    lifetime_value_usd  NUMBER(12,2),
    stays_count         INTEGER         DEFAULT 0,
    avg_daily_rate_usd  NUMBER(8,2),
    last_stay_date      DATE,
    preferred_room_type VARCHAR(50),
    preferred_amenities VARIANT,        -- ARRAY of strings
    nps_score           INTEGER,
    churn_risk          VARCHAR(20),    -- LOW | MEDIUM | HIGH
    upsell_propensity   NUMBER(5,4),    -- 0-1 probability
    ai_persona          VARCHAR(200),   -- LLM-generated persona (ex: "Business traveler, prefers suites")
    profile_date        DATE            DEFAULT CURRENT_DATE(),
    created_at          TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (profile_id),
    UNIQUE (org_id, guest_id, profile_date)
);


-- ─── Métricas de propriedade / voo ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_HOSPITALITY.PROPERTY_PERFORMANCE (
    perf_id             VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    property_id         VARCHAR(100)    NOT NULL,
    performance_date    DATE            NOT NULL,
    occupancy_rate      NUMBER(5,2),    -- %
    adr_usd             NUMBER(8,2),    -- Average Daily Rate
    revpar_usd          NUMBER(8,2),    -- Revenue Per Available Room = occ * ADR
    trevpar_usd         NUMBER(8,2),    -- Total Revenue Per Available Room (incl. F&B, spa)
    ancillary_revenue   NUMBER(12,2),   -- F&B, spa, parking, extras
    cancellation_rate   NUMBER(5,2),    -- %
    no_show_rate        NUMBER(5,2),    -- %
    avg_los_nights      NUMBER(5,2),    -- Average Length of Stay
    created_at          TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (perf_id),
    UNIQUE (org_id, property_id, performance_date)
);


-- ─── SP: Score de hóspedes e risco de churn ──────────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_HOSPITALITY.SP_COMPUTE_GUEST_SCORES(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_count INTEGER;
BEGIN
    MERGE INTO VERTICAL_HOSPITALITY.GUEST_PROFILE tgt
    USING (
        SELECT
            c.customer_id                                       AS guest_id,
            :org_id                                             AS org_id,
            c.arr_usd                                          AS lifetime_value_usd,

            -- Tier de fidelidade por LTV
            CASE
                WHEN c.arr_usd >= 50000 THEN 'ELITE'
                WHEN c.arr_usd >= 20000 THEN 'PLATINUM'
                WHEN c.arr_usd >= 10000 THEN 'GOLD'
                WHEN c.arr_usd >= 5000  THEN 'SILVER'
                ELSE 'BRONZE'
            END                                                AS loyalty_tier,

            -- Estimativa de número de estadias (ARR / ADR médio de 200)
            GREATEST(1, ROUND(c.arr_usd / 200))               AS stays_count,

            -- ADR estimado
            CASE
                WHEN c.arr_usd >= 20000 THEN 300
                WHEN c.arr_usd >= 10000 THEN 200
                ELSE 120
            END                                                AS avg_daily_rate_usd,

            c.churn_risk_level                                 AS churn_risk,

            -- Upsell propensity (hóspedes de alto LTV + baixo churn)
            ROUND(LEAST(0.95, GREATEST(0,
                (c.health_score / 100.0) * 0.6
                + CASE c.churn_risk_level WHEN 'LOW' THEN 0.3 ELSE 0 END
                + CASE WHEN c.arr_usd > 10000 THEN 0.1 ELSE 0 END
            )), 4)                                             AS upsell_propensity,

            c.nps_score

        FROM NEXUS_APP.MART.CUSTOMER_360 c
        WHERE c.org_id = :org_id
    ) src
    ON tgt.guest_id = src.guest_id AND tgt.org_id = src.org_id
       AND tgt.profile_date = CURRENT_DATE()
    WHEN MATCHED THEN UPDATE SET
        lifetime_value_usd = src.lifetime_value_usd,
        loyalty_tier       = src.loyalty_tier,
        stays_count        = src.stays_count,
        avg_daily_rate_usd = src.avg_daily_rate_usd,
        churn_risk         = src.churn_risk,
        upsell_propensity  = src.upsell_propensity,
        nps_score          = src.nps_score,
        created_at         = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (org_id, guest_id, loyalty_tier, lifetime_value_usd, stays_count,
         avg_daily_rate_usd, churn_risk, upsell_propensity, nps_score)
    VALUES (src.org_id, src.guest_id, src.loyalty_tier, src.lifetime_value_usd,
            src.stays_count, src.avg_daily_rate_usd, src.churn_risk,
            src.upsell_propensity, src.nps_score);

    SELECT COUNT(*) INTO v_count
    FROM VERTICAL_HOSPITALITY.GUEST_PROFILE
    WHERE org_id = :org_id AND profile_date = CURRENT_DATE();

    RETURN 'Profiled ' || v_count::VARCHAR || ' guests.';
END;
$$;


-- ─── SP: Gerar oferta personalizada via LLM ──────────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_HOSPITALITY.SP_PERSONALIZED_OFFER(
    guest_id VARCHAR,
    org_id   VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_context VARCHAR; v_offer VARCHAR;
BEGIN
    SELECT
        'Tier: '          || g.loyalty_tier ||
        '\nLTV: $'        || ROUND(g.lifetime_value_usd, 0)::VARCHAR ||
        '\nEstadias: '    || g.stays_count::VARCHAR ||
        '\nADR médio: $'  || g.avg_daily_rate_usd::VARCHAR ||
        '\nNPS: '         || COALESCE(g.nps_score::VARCHAR, 'N/A') ||
        '\nRisco churn: ' || g.churn_risk ||
        '\nPropensão upsell: ' || ROUND(g.upsell_propensity * 100, 0)::VARCHAR || '%' ||
        '\nQuarto preferido: ' || COALESCE(g.preferred_room_type, 'não registrado')
    INTO v_context
    FROM VERTICAL_HOSPITALITY.GUEST_PROFILE g
    WHERE g.guest_id = :guest_id AND g.org_id = :org_id
    ORDER BY g.profile_date DESC LIMIT 1;

    IF (v_context IS NULL) THEN RETURN 'Perfil não encontrado.'; END IF;

    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
            'role', 'user',
            'content', 'Você é um especialista em hospitalidade e revenue management. ' ||
                'Com base no perfil do hóspede abaixo, crie uma oferta personalizada que: ' ||
                '1) retenha o hóspede se há risco de churn, ' ||
                '2) faça upsell de quarto ou pacote se propensão for alta, ' ||
                '3) ofereça benefício de fidelidade proporcional ao tier. ' ||
                'Tom: caloroso, exclusivo e pessoal. Máximo 150 palavras em português.\n\n' || :v_context
        ))
    ) INTO v_offer;

    RETURN v_offer;
END;
$$;


-- ─── View: RevPAR por propriedade (últimos 30d) ───────────────────────────────

CREATE OR REPLACE VIEW VERTICAL_HOSPITALITY.V_PROPERTY_REVPAR AS
SELECT
    org_id,
    property_id,
    ROUND(AVG(occupancy_rate), 1)   AS avg_occupancy_pct,
    ROUND(AVG(adr_usd), 2)          AS avg_adr_usd,
    ROUND(AVG(revpar_usd), 2)       AS avg_revpar_usd,
    ROUND(AVG(trevpar_usd), 2)      AS avg_trevpar_usd,
    ROUND(AVG(cancellation_rate), 1)AS avg_cancellation_pct,
    ROUND(AVG(avg_los_nights), 1)   AS avg_los_nights,
    SUM(ancillary_revenue)          AS total_ancillary_revenue,
    MAX(performance_date)           AS last_updated
FROM VERTICAL_HOSPITALITY.PROPERTY_PERFORMANCE
WHERE performance_date >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY avg_revpar_usd DESC NULLS LAST;


-- ─── View: hóspedes VVIP em risco de churn ───────────────────────────────────

CREATE OR REPLACE VIEW VERTICAL_HOSPITALITY.V_VVIP_AT_RISK AS
SELECT
    g.org_id,
    g.guest_id,
    c.customer_name                     AS guest_name,
    g.loyalty_tier,
    g.lifetime_value_usd,
    g.stays_count,
    g.churn_risk,
    g.upsell_propensity,
    g.nps_score,
    ROUND(g.lifetime_value_usd * 0.3, 0) AS estimated_loss_if_churned
FROM VERTICAL_HOSPITALITY.GUEST_PROFILE g
JOIN NEXUS_APP.MART.CUSTOMER_360 c
     ON g.guest_id = c.customer_id AND g.org_id = c.org_id
WHERE g.profile_date = CURRENT_DATE()
  AND g.loyalty_tier IN ('PLATINUM', 'ELITE', 'GOLD')
  AND g.churn_risk IN ('HIGH', 'MEDIUM')
ORDER BY g.lifetime_value_usd DESC NULLS LAST;


-- ─── Task diária ──────────────────────────────────────────────────────────────

CREATE OR REPLACE TASK VERTICAL_HOSPITALITY.TASK_HOSPITALITY_INTELLIGENCE
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 4 * * * UTC'
AS
DECLARE v_org VARCHAR;
BEGIN
    FOR rec IN (SELECT DISTINCT org_id FROM NEXUS_APP.CORE.ORGANIZATIONS WHERE is_active = TRUE AND vertical IN ('hospitality', 'aviation')) DO
        v_org := rec.org_id;
        CALL VERTICAL_HOSPITALITY.SP_COMPUTE_GUEST_SCORES(:v_org);
    END FOR;
END;

ALTER TASK VERTICAL_HOSPITALITY.TASK_HOSPITALITY_INTELLIGENCE RESUME;
