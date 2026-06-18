-- =============================================================================
-- NEXUS Vertical Pack — Retail & Consumer
-- Demand forecast, inventory intelligence, promotion analytics
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

-- ─── Schema dedicado ao vertical de varejo ───────────────────────────────────

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.VERTICAL_RETAIL
    COMMENT = 'NEXUS Vertical Pack — Retail: demand forecast, inventory, promotions';


-- ─── Tabela: previsão de demanda por SKU / localização ───────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_RETAIL.DEMAND_FORECAST (
    forecast_id         VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    sku_id              VARCHAR(100)    NOT NULL,
    location_id         VARCHAR(100),
    forecast_date       DATE            NOT NULL,
    forecast_qty        NUMBER(12,2),
    lower_bound_qty     NUMBER(12,2),
    upper_bound_qty     NUMBER(12,2),
    actual_qty          NUMBER(12,2),
    mape                NUMBER(5,2),    -- Mean Absolute Percentage Error
    model_version       VARCHAR(20)     DEFAULT '1.0.0',
    generated_at        TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (forecast_id),
    UNIQUE (org_id, sku_id, location_id, forecast_date)
);


-- ─── Tabela: alertas de inventário ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_RETAIL.INVENTORY_ALERTS (
    alert_id            VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    sku_id              VARCHAR(100)    NOT NULL,
    location_id         VARCHAR(100),
    alert_type          VARCHAR(50),    -- STOCKOUT_RISK | OVERSTOCK | SLOW_MOVER | EXPIRY_RISK
    alert_severity      VARCHAR(20),    -- LOW | MEDIUM | HIGH | CRITICAL
    current_stock       NUMBER(12,2),
    reorder_point       NUMBER(12,2),
    days_of_cover       NUMBER(5,1),
    recommended_qty     NUMBER(12,2),
    alert_message       VARCHAR(1000),
    status              VARCHAR(20)     DEFAULT 'open',
    created_at          TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (alert_id)
);


-- ─── SP: Gerar previsão de demanda com Cortex AI ─────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_RETAIL.SP_GENERATE_DEMAND_FORECAST(
    org_id      VARCHAR,
    horizon_days INTEGER DEFAULT 30
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_count INTEGER;
    v_horizon_end DATE;
BEGIN
    v_horizon_end := DATEADD('day', :horizon_days, CURRENT_DATE());

    -- Usa SNOWFLAKE.ML.FORECAST via UDF ou fallback para média móvel
    -- Em produção: substituir pelo Snowflake ML Forecast function
    INSERT INTO VERTICAL_RETAIL.DEMAND_FORECAST
        (org_id, sku_id, location_id, forecast_date, forecast_qty, lower_bound_qty, upper_bound_qty)
    SELECT
        s.org_id,
        s.sku_id,
        s.location_id,
        d.date_value                             AS forecast_date,
        -- Média móvel 7d como proxy (substituir por Snowflake ML Forecast)
        ROUND(AVG(s.qty_sold) OVER (
            PARTITION BY s.org_id, s.sku_id, s.location_id
            ORDER BY s.sale_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) * (1 + 0.05 * UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())), 0) AS forecast_qty,
        ROUND(AVG(s.qty_sold) OVER (
            PARTITION BY s.org_id, s.sku_id, s.location_id
            ORDER BY s.sale_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) * 0.85, 0)                            AS lower_bound_qty,
        ROUND(AVG(s.qty_sold) OVER (
            PARTITION BY s.org_id, s.sku_id, s.location_id
            ORDER BY s.sale_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) * 1.15, 0)                            AS upper_bound_qty
    FROM NEXUS_APP.CORE.SALES_HISTORY s
    CROSS JOIN (
        SELECT DATEADD('day', SEQ4(), CURRENT_DATE()) AS date_value
        FROM TABLE(GENERATOR(ROWCOUNT => :horizon_days))
    ) d
    WHERE s.org_id   = :org_id
      AND s.sale_date >= DATEADD('day', -90, CURRENT_DATE())
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY s.org_id, s.sku_id, s.location_id, d.date_value
        ORDER BY s.sale_date DESC
    ) = 1;

    SELECT COUNT(*) INTO v_count
    FROM VERTICAL_RETAIL.DEMAND_FORECAST
    WHERE org_id = :org_id AND forecast_date >= CURRENT_DATE();

    RETURN 'Generated ' || v_count::VARCHAR || ' forecast records.';
END;
$$;


-- ─── SP: Gerar alertas de inventário via AI ───────────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_RETAIL.SP_INVENTORY_ALERTS(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_count INTEGER;
BEGIN
    -- Limpar alertas abertos antigos
    UPDATE VERTICAL_RETAIL.INVENTORY_ALERTS
    SET status = 'auto_closed'
    WHERE org_id = :org_id AND status = 'open'
      AND created_at < DATEADD('day', -2, CURRENT_TIMESTAMP());

    -- Gerar novos alertas baseado em estoque vs. forecast
    INSERT INTO VERTICAL_RETAIL.INVENTORY_ALERTS
        (org_id, sku_id, location_id, alert_type, alert_severity,
         current_stock, reorder_point, days_of_cover, recommended_qty, alert_message)
    SELECT
        i.org_id,
        i.sku_id,
        i.location_id,

        CASE
            WHEN i.current_stock = 0                              THEN 'STOCKOUT_RISK'
            WHEN i.current_stock / NULLIF(avg_daily_demand, 0) < 7 THEN 'STOCKOUT_RISK'
            WHEN i.current_stock / NULLIF(avg_daily_demand, 0) > 90 THEN 'OVERSTOCK'
            ELSE 'SLOW_MOVER'
        END                                                        AS alert_type,

        CASE
            WHEN i.current_stock = 0                              THEN 'CRITICAL'
            WHEN i.current_stock / NULLIF(avg_daily_demand, 0) < 3 THEN 'HIGH'
            WHEN i.current_stock / NULLIF(avg_daily_demand, 0) < 7 THEN 'MEDIUM'
            ELSE 'LOW'
        END                                                        AS alert_severity,

        i.current_stock,
        avg_daily_demand * 14                                      AS reorder_point,
        ROUND(i.current_stock / NULLIF(avg_daily_demand, 0), 1)   AS days_of_cover,
        GREATEST(0, avg_daily_demand * 30 - i.current_stock)      AS recommended_qty,

        'SKU ' || i.sku_id || ' em ' || COALESCE(i.location_id, 'all') ||
        ': ' || ROUND(i.current_stock / NULLIF(avg_daily_demand, 0), 1)::VARCHAR ||
        ' dias de cobertura. Ponto de reposição: ' ||
        ROUND(avg_daily_demand * 14, 0)::VARCHAR || ' unidades.'  AS alert_message

    FROM NEXUS_APP.CORE.INVENTORY i
    JOIN (
        SELECT sku_id, location_id, org_id,
               ROUND(AVG(forecast_qty), 0) AS avg_daily_demand
        FROM VERTICAL_RETAIL.DEMAND_FORECAST
        WHERE forecast_date BETWEEN CURRENT_DATE() AND DATEADD('day', 30, CURRENT_DATE())
        GROUP BY 1, 2, 3
    ) f ON i.sku_id = f.sku_id AND i.location_id = f.location_id AND i.org_id = f.org_id
    WHERE i.org_id = :org_id
      AND (
          i.current_stock / NULLIF(f.avg_daily_demand, 0) < 14
          OR i.current_stock / NULLIF(f.avg_daily_demand, 0) > 90
      );

    SELECT COUNT(*) INTO v_count
    FROM VERTICAL_RETAIL.INVENTORY_ALERTS
    WHERE org_id = :org_id AND status = 'open';

    RETURN v_count::VARCHAR || ' active inventory alerts.';
END;
$$;


-- ─── View: dashboard de inventário ───────────────────────────────────────────

CREATE OR REPLACE VIEW VERTICAL_RETAIL.V_INVENTORY_DASHBOARD AS
SELECT
    a.org_id,
    a.alert_type,
    a.alert_severity,
    COUNT(*)                             AS alert_count,
    SUM(a.recommended_qty)               AS total_recommended_qty,
    ROUND(AVG(a.days_of_cover), 1)       AS avg_days_of_cover,
    MAX(a.created_at)                    AS latest_alert
FROM VERTICAL_RETAIL.INVENTORY_ALERTS a
WHERE a.status = 'open'
GROUP BY 1, 2, 3
ORDER BY
    CASE a.alert_severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
    alert_count DESC;


-- ─── SP: Análise de promoção com LLM ─────────────────────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_RETAIL.SP_PROMOTION_ANALYSIS(
    org_id      VARCHAR,
    promotion_id VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_context VARCHAR;
    v_analysis VARCHAR;
BEGIN
    -- Busca métricas da promoção
    SELECT
        'Promoção: ' || p.name ||
        '\nPeríodo: ' || TO_CHAR(p.start_date) || ' a ' || TO_CHAR(p.end_date) ||
        '\nDesconto: ' || p.discount_pct::VARCHAR || '%' ||
        '\nVendas durante promoção: $' || COALESCE(SUM(s.revenue_usd), 0)::VARCHAR ||
        '\nUnidades vendidas: ' || COALESCE(SUM(s.qty_sold), 0)::VARCHAR ||
        '\nCusto da promoção: $' || COALESCE(p.cost_usd, 0)::VARCHAR
    INTO v_context
    FROM NEXUS_APP.CORE.PROMOTIONS p
    LEFT JOIN NEXUS_APP.CORE.SALES_HISTORY s
           ON s.promotion_id = p.promotion_id AND s.org_id = p.org_id
    WHERE p.promotion_id = :promotion_id AND p.org_id = :org_id
    GROUP BY p.name, p.start_date, p.end_date, p.discount_pct, p.cost_usd;

    IF (v_context IS NULL) THEN
        RETURN 'Promoção não encontrada.';
    END IF;

    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
            'role', 'user',
            'content', 'Analise o desempenho desta promoção de varejo e forneça: 1) ROI estimado, 2) se foi bem-sucedida, 3) recomendação para próximas promoções. Contexto:\n' || :v_context
        ))
    ) INTO v_analysis;

    RETURN v_analysis;
END;
$$;


-- ─── Task: atualizar forecasts e alertas diariamente ─────────────────────────

CREATE OR REPLACE TASK VERTICAL_RETAIL.TASK_DAILY_RETAIL_INTELLIGENCE
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 4 * * * UTC'
    COMMENT   = 'Daily demand forecast + inventory alerts for retail orgs'
AS
DECLARE v_org VARCHAR;
BEGIN
    FOR rec IN (SELECT DISTINCT org_id FROM NEXUS_APP.CORE.ORGANIZATIONS WHERE is_active = TRUE AND vertical = 'retail') DO
        v_org := rec.org_id;
        CALL VERTICAL_RETAIL.SP_GENERATE_DEMAND_FORECAST(:v_org, 30);
        CALL VERTICAL_RETAIL.SP_INVENTORY_ALERTS(:v_org);
    END FOR;
END;

ALTER TASK VERTICAL_RETAIL.TASK_DAILY_RETAIL_INTELLIGENCE RESUME;
