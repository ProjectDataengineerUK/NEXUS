# DESIGN — NEXUS Sprint 5: Feature Store & AI.MODEL_OUTPUTS

**Feature:** NEXUS_SPRINT5_FEATURE_STORE
**Phase:** 2 — Design
**Date:** 2026-07-06
**Status:** Approved
**Based on:** DEFINE_NEXUS_SPRINT5_FEATURE_STORE.md

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Snapshot diário (novo — Decision 1)                                    │
│                                                                          │
│  TASK_SNAPSHOT_REVENUE_DAILY      TASK_SNAPSHOT_EXECUTIVE_KPIS           │
│  (agrega CORE.TRANSACTIONS        (fotografa MART.DT_EXECUTIVE_KPIS     │
│   do dia anterior)                  do dia — histórico, não estado)     │
│         │                                    │                          │
│         ▼                                    ▼                          │
│  MART.REVENUE_DAILY              MART.EXECUTIVE_KPIS_HISTORY            │
│  (org_id, revenue_date,          (org_id, snapshot_date,                │
│   total_revenue_booked,           avg_health_score, arr_at_risk)        │
│   net_new_mrr)                                                          │
└──────────────┬────────────────────────────┬────────────────────────────┘
               │                             │
               ▼                             ▼
     TASK_RUN_FORECAST              TASK_RUN_ANOMALY_DETECTION
     (Cortex ML Forecaster)         (Cortex ML AnomalyDetector)
               │                             │
               ▼                             ▼
     AI.REVENUE_FORECAST             AI.ANOMALY_ALERTS
               │                             │
               └──────────┬──────────────────┘
                          ▼ (dual-write, junto com CHURN_SCORES/RECOMMENDATIONS)
                   AI.MODEL_OUTPUTS  ◄── consulta cross-model unificada


┌─────────────────────────────────────────────────────────────────────────┐
│  Feature Store consolidado (P1)                                        │
│                                                                          │
│  MART.DT_FEATURE_STORE (Dynamic Table, org-level)                       │
│  ├── revenue_7d_avg, revenue_30d_avg (de MART.REVENUE_DAILY)            │
│  ├── ticket_count_open, ticket_severity_avg (de CORE.TICKETS)           │
│  ├── avg_health_score, churn_risk_avg (de MART.DT_CUSTOMER_HEALTH)      │
│  └── consumido por: SP_RUN_FORECAST, SP_RUN_ANOMALY_DETECTION (futuro)  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Architecture Decisions

### Decision 1 — Criar tabelas de histórico diário antes de conectar os modelos órfãos

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted — corrige premissa implícita do DEFINE |

**Contexto:** `anomaly_model.py` e `forecast_model.py` esperam `MART.REVENUE_DAILY` (série temporal diária) e `MART.EXECUTIVE_KPIS` com coluna `SNAPSHOT_DATE` (série temporal de KPIs). Nenhuma das duas existe no Native App — só `MART.DT_EXECUTIVE_KPIS`, uma Dynamic Table que reflete **estado atual**, sem histórico. Dynamic Tables não retêm séries temporais por natureza (são recalculadas, não acumulam linhas por data). Sem histórico, `AnomalyDetector`/`Forecaster` não têm o que treinar.

**Decisão:** adicionar duas Tasks diárias de snapshot que **acumulam** histórico (INSERT, não Dynamic Table):
- `TASK_SNAPSHOT_REVENUE_DAILY` — agrega `CORE.TRANSACTIONS` do dia anterior em `MART.REVENUE_DAILY` (org_id, revenue_date, total_revenue_booked, net_new_mrr)
- `TASK_SNAPSHOT_EXECUTIVE_KPIS` — fotografa os valores atuais de `MART.DT_EXECUTIVE_KPIS` em `MART.EXECUTIVE_KPIS_HISTORY` (org_id, snapshot_date, avg_health_score, arr_at_risk), rodando uma vez por dia

**Alternativas rejeitadas:**
- Fazer forecast/anomaly lerem direto de `CORE.TRANSACTIONS`/`DT_EXECUTIVE_KPIS` sem tabela intermediária — rejeitado porque `DT_EXECUTIVE_KPIS` não tem múltiplas linhas por data (é sempre o valor atual); não dá pra montar série temporal a partir de uma única linha "current state"

**Consequências:** os modelos só terão histórico suficiente (`MIN_HISTORY = 7` dias para anomaly, `14` para forecast) depois de rodarem os snapshots por esse período — nas primeiras semanas após o deploy, `SP_RUN_ANOMALY_DETECTION`/`SP_RUN_FORECAST` vão retornar "0 anomalias" / usar fallback de média móvel, o que é esperado e correto (não é bug).

### Decision 2 — `AI.MODEL_OUTPUTS` schema

```sql
CREATE TABLE IF NOT EXISTS AI.MODEL_OUTPUTS (
    output_id        VARCHAR(36)   DEFAULT UUID_STRING() PRIMARY KEY,
    org_id            VARCHAR(50)   NOT NULL,
    model_name        VARCHAR(100)  NOT NULL,   -- 'churn', 'forecast', 'anomaly', 'recommendation'
    model_version     VARCHAR(50),
    entity_id         VARCHAR(36),               -- customer_id, ou NULL para outputs org-level
    entity_type       VARCHAR(50),                -- 'customer', 'org'
    output_type       VARCHAR(100),               -- 'churn_score', 'revenue_forecast', 'anomaly_alert', 'recommendation'
    output_value      VARIANT,                    -- payload específico do modelo
    confidence_score   DECIMAL(5,4),
    generated_at       TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP()
);
```

**Consequências:** consultas cross-model (“o que a IA já disse sobre o cliente X”) viram `SELECT * FROM AI.MODEL_OUTPUTS WHERE entity_id = ?`, sem saber de antemão qual tabela específica olhar.

### Decision 3 — Dual-write, não migração

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |

Cada procedure (`SP_RUN_CHURN_PIPELINE`, `SP_RUN_FORECAST`, `SP_RUN_ANOMALY_DETECTION`, `generate_recommendations` dentro de `SP_RUN_CHURN_PIPELINE`) grava um segundo INSERT em `AI.MODEL_OUTPUTS` logo após gravar na tabela específica — nunca substitui. Streamlit pages e Cortex Agents que já fazem join direto com `AI.CHURN_SCORES` etc. continuam funcionando sem alteração.

### Decision 4 — Feature Store (P1) fica org-level, alimentado por fontes já existentes

`MART.DT_FEATURE_STORE` é uma Dynamic Table (refresh automático, sem necessidade de Task) que agrega `MART.REVENUE_DAILY`, `CORE.TICKETS` e `MART.DT_CUSTOMER_HEALTH` por org — não introduz fontes novas, só consolida o que já existe (incluindo a tabela nova de Decision 1) num único lugar que `SP_RUN_FORECAST`/`SP_RUN_ANOMALY_DETECTION` poderiam eventualmente ler em vez de recalcular inline. Sprint 5 cria a DT; a migração dos SPs para lê-la fica como possível work futuro (não bloqueia o Feature Store existir).

---

## Code Patterns

### Pattern 1 — Snapshot diário (Decision 1)

```sql
CREATE TABLE IF NOT EXISTS MART.REVENUE_DAILY (
    org_id                VARCHAR(50)  NOT NULL,
    revenue_date          DATE         NOT NULL,
    total_revenue_booked  DECIMAL(18,2),
    net_new_mrr           DECIMAL(18,2),
    snapshotted_at        TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (org_id, revenue_date)
);

CREATE TABLE IF NOT EXISTS MART.EXECUTIVE_KPIS_HISTORY (
    org_id            VARCHAR(50)  NOT NULL,
    snapshot_date     DATE         NOT NULL,
    avg_health_score  DECIMAL(8,4),
    arr_at_risk       DECIMAL(18,2),
    snapshotted_at    TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (org_id, snapshot_date)
);

CREATE OR REPLACE TASK CORE.TASK_SNAPSHOT_REVENUE_DAILY
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 1 * * * UTC'
AS
MERGE INTO MART.REVENUE_DAILY tgt
USING (
    SELECT
        org_id,
        DATEADD('day', -1, CURRENT_DATE())                                   AS revenue_date,
        SUM(amount)                                                          AS total_revenue_booked,
        SUM(CASE WHEN transaction_type IN ('new_business','expansion','order','deal','invoice')
                 THEN amount ELSE 0 END)                                     AS net_new_mrr
    FROM CORE.TRANSACTIONS
    WHERE transaction_date = DATEADD('day', -1, CURRENT_DATE())
    GROUP BY org_id
) src
ON tgt.org_id = src.org_id AND tgt.revenue_date = src.revenue_date
WHEN MATCHED THEN UPDATE SET
    total_revenue_booked = src.total_revenue_booked, net_new_mrr = src.net_new_mrr
WHEN NOT MATCHED THEN INSERT (org_id, revenue_date, total_revenue_booked, net_new_mrr)
    VALUES (src.org_id, src.revenue_date, src.total_revenue_booked, src.net_new_mrr);

CREATE OR REPLACE TASK CORE.TASK_SNAPSHOT_EXECUTIVE_KPIS
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 1 * * * UTC'
AS
MERGE INTO MART.EXECUTIVE_KPIS_HISTORY tgt
USING (
    SELECT
        org_id,
        DATEADD('day', -1, CURRENT_DATE()) AS snapshot_date,
        avg_nps                            AS avg_health_score,  -- proxy disponível hoje
        arr_at_risk
    FROM MART.DT_EXECUTIVE_KPIS
) src
ON tgt.org_id = src.org_id AND tgt.snapshot_date = src.snapshot_date
WHEN MATCHED THEN UPDATE SET
    avg_health_score = src.avg_health_score, arr_at_risk = src.arr_at_risk
WHEN NOT MATCHED THEN INSERT (org_id, snapshot_date, avg_health_score, arr_at_risk)
    VALUES (src.org_id, src.snapshot_date, src.avg_health_score, src.arr_at_risk);
```

> Nota: `DT_EXECUTIVE_KPIS` não tem uma coluna "health score" per se — usa `avg_nps` como proxy disponível hoje (NPS médio). Se um `avg_health_score` real for necessário no futuro, seria calculado a partir de `MART.DT_CUSTOMER_HEALTH.health_segment`/`churn_risk_score` agregado por org — fora do escopo mínimo deste sprint.

### Pattern 2 — Procedure inline (anomaly, espelha o padrão do SP_RUN_CHURN_PIPELINE do Sprint 3)

```sql
CREATE OR REPLACE PROCEDURE CORE.SP_RUN_ANOMALY_DETECTION(ORG_ID VARCHAR DEFAULT NULL)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python')
HANDLER = 'run_anomaly_detection'
AS
$$
from snowflake.ml.modeling.anomaly_detection import AnomalyDetector

MODEL_VERSION = "1.0.0-anomaly"
MIN_HISTORY   = 7

METRICS = [
    {"name": "daily_revenue",     "table": "MART.REVENUE_DAILY",           "ts_col": "REVENUE_DATE",   "val_col": "TOTAL_REVENUE_BOOKED"},
    {"name": "daily_new_mrr",     "table": "MART.REVENUE_DAILY",           "ts_col": "REVENUE_DATE",   "val_col": "NET_NEW_MRR"},
    {"name": "avg_health_score",  "table": "MART.EXECUTIVE_KPIS_HISTORY",  "ts_col": "SNAPSHOT_DATE",  "val_col": "AVG_HEALTH_SCORE"},
    {"name": "arr_at_risk",       "table": "MART.EXECUTIVE_KPIS_HISTORY",  "ts_col": "SNAPSHOT_DATE",  "val_col": "ARR_AT_RISK"},
]

def _severity(deviation_pct):
    abs_dev = abs(deviation_pct)
    if abs_dev >= 50: return "HIGH"
    if abs_dev >= 25: return "MEDIUM"
    return "LOW"

def _detect_metric(session, org_id, metric):
    # ... idêntico a snowflake/models/anomaly_model.py::_detect_metric,
    # com um INSERT adicional em AI.MODEL_OUTPUTS (Decision 3)
    ...

def run_anomaly_detection(session, org_id=None):
    orgs = [org_id] if org_id else [
        r["ORG_ID"] for r in session.sql(
            "SELECT DISTINCT org_id FROM CORE.CUSTOMERS WHERE lifecycle_stage != 'churned'"
        ).collect()
    ]
    total = 0
    for oid in orgs:
        session.sql(
            "DELETE FROM AI.ANOMALY_ALERTS WHERE org_id = ? AND metric_date < DATEADD('day', -7, CURRENT_DATE())",
            params=[oid]
        ).collect()
        for metric in METRICS:
            total += _detect_metric(session, oid, metric)
    return f"OK: {total} anomalias detectadas"
$$;
```

> `SP_RUN_FORECAST` segue o mesmo padrão, espelhando `forecast_model.py::run()` (incluindo o fallback de média móvel quando `MIN_HISTORY` não é atingido).

---

## Build Order

1. `setup_script.sql` — `MART.REVENUE_DAILY`, `MART.EXECUTIVE_KPIS_HISTORY` + Tasks de snapshot (Decision 1) — pré-requisito de tudo mais
2. `setup_script.sql` — `AI.MODEL_OUTPUTS` (Decision 2)
3. `setup_script.sql` — `CORE.SP_RUN_ANOMALY_DETECTION` + `TASK_RUN_ANOMALY_DETECTION`
4. `setup_script.sql` — `CORE.SP_RUN_FORECAST` + `TASK_RUN_FORECAST`
5. `setup_script.sql` — dual-write em `SP_RUN_CHURN_PIPELINE` existente (churn scores + recommendations → `AI.MODEL_OUTPUTS`)
6. `setup_script.sql` — `MART.DT_FEATURE_STORE` (Decision 4, P1)
7. `tests/python/test_model_outputs.py` + `tests/sql/test_model_outputs.sql`

---

## Risks

| Risco | Mitigação |
|-------|-----------|
| Modelos ficam sem histórico suficiente logo após o deploy (semanas 1-2) | Esperado e documentado — `AnomalyDetector`/`Forecaster` retornam "0 anomalias"/fallback até acumular `MIN_HISTORY` dias, não é erro |
| `AnomalyDetector.fit()` pode falhar silenciosamente com poucos dados | Já tratado no código original (`try/except` retorna 0) — mantido igual no inline |
| Dual-write duplica volume de INSERT por execução de modelo | Aceitável — `AI.MODEL_OUTPUTS` é append-only e pequeno comparado às tabelas de origem |
