# DESIGN — NEXUS Sprint 4: Conectores Adicionais + CDC via Streams

**Feature:** NEXUS_SPRINT4_CONNECTORS_CDC
**Phase:** 2 — Design
**Date:** 2026-07-06
**Status:** Approved
**Based on:** DEFINE_NEXUS_SPRINT4_CONNECTORS_CDC.md

---

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│  AIRFLOW (provider-side)                                                  │
│                                                                            │
│  sap_ingest_dag.py       oracle_ingest_dag.py     hubspot_ingest_dag.py   │
│  (OData, diário)         (oracledb thin, diário)  (API v3, diário)        │
│       │                        │                         │               │
│       ▼                        ▼                         ▼               │
│  STAGING.SAP_*            STAGING.ORACLE_*          STAGING.HUBSPOT_*     │
└───────┼────────────────────────┼─────────────────────────┼───────────────┘
        │                        │                         │
        │         CREATE STREAM em cada STAGING.<fonte>_*  │
        │         (consumer-side, setup_script.sql)        │
        ▼                        ▼                         ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  SNOWFLAKE — NEXUS_APP (consumer)                                         │
│                                                                            │
│  TASK_MERGE_SAP_CUSTOMERS      TASK_MERGE_ORACLE_*      TASK_MERGE_HUBSPOT_*│
│  (WHEN SYSTEM$STREAM_HAS_DATA) │                         │                │
│       │                        │                         │                │
│       ▼                        ▼                         ▼                │
│  CORE.CUSTOMERS  CORE.TRANSACTIONS  CORE.SUBSCRIPTIONS  (MERGE incremental)│
│       │                                                                    │
│       ▼ (mecanismo NATIVO do Snowflake, não Stream/Task)                  │
│  MART.DT_REVENUE_MOVEMENT, DT_CUSTOMER_HEALTH, DT_EXECUTIVE_KPIS          │
│  (Dynamic Tables — refresh incremental automático, TARGET_LAG)           │
└───────────────────────────────────────────────────────────────────────────┘
```

**Nota de escopo:** o DEFINE original previa Streams entre `CORE.TRANSACTIONS` e os marts. Esse desenho foi corrigido aqui — ver Decision 4.

---

## Architecture Decisions

### Decision 1 — Conector SAP via OData, não RFC/BAPI

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |

**Contexto:** SAP expõe dados via OData (REST, HTTP) ou RFC/BAPI (protocolo proprietário, exige `pyrfc` + SAP NW RFC SDK instalado no worker do Airflow).

**Decisão:** usar OData (`requests`, autenticação Basic ou OAuth2 conforme client). Escopo: `Customers`, `Invoices`, `Orders` (entidades OData padrão do módulo SD/FI).

**Alternativas rejeitadas:** RFC/BAPI — exige binário proprietário licenciado no ambiente do Airflow, inviável para instalação genérica em qualquer cliente.

**Consequências:** Nem todo SAP expõe OData por padrão (depende de módulo SAP Gateway ativado) — o conector assume que o endpoint OData já está disponível; ativação é responsabilidade do cliente/implementação.

---

### Decision 2 — Conector Oracle via `oracledb` (thin mode)

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |

**Contexto:** o driver `oracledb` da Oracle roda em modo thin (puro Python) sem precisar do Oracle Instant Client instalado — evita dependência de binário nativo no worker do Airflow (mesmo racional da Decision 1).

**Decisão:** `oracledb.connect()` em modo thin, extraindo `CUSTOMERS`, `ORDERS`, `INVOICES` (nomenclatura genérica — ajustável por cliente via `Variable`).

**Consequências:** modo thin não suporta todos os recursos avançados do Oracle (ex: Advanced Queuing) — irrelevante para extração batch simples via `SELECT`.

---

### Decision 3 — Conector HubSpot via API v3

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |

**Decisão:** `requests` contra `api.hubapi.com`, endpoints `/crm/v3/objects/{contacts,deals,companies}`, paginação via `after` cursor (padrão v3), autenticação via Private App token (`Variable.get("HUBSPOT_ACCESS_TOKEN")`).

**Consequências:** segue exatamente o padrão dos 3 DAGs existentes (TaskFlow API, retry, `SnowflakeHook`).

---

### Decision 4 — CDC via Streams entre STAGING e CORE, não entre CORE e MART

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted — corrige o DEFINE |

**Contexto:** o DEFINE (AT-123/AT-124) previa `CREATE STREAM` sobre `CORE.TRANSACTIONS` consumido por uma Task que atualizaria `MART.DT_REVENUE_MOVEMENT` incrementalmente. Isso está tecnicamente incorreto: **Dynamic Tables já fazem refresh incremental nativamente** — o Snowflake rastreia mudanças nas tabelas base e recalcula apenas as linhas afetadas dentro do `TARGET_LAG`, sem precisar de Stream/Task explícitos. Criar um Stream+Task escrevendo em `DT_REVENUE_MOVEMENT` além do próprio motor de DT geraria conflito de escrita (uma Dynamic Table não aceita INSERT/MERGE externo).

**Decisão:** mover o CDC para onde ele genuinamente agrega valor — entre `STAGING.<fonte>_*` (dados brutos, recém-carregados pelos DAGs) e `CORE.*` (tabelas canônicas). Cada tabela `STAGING.<fonte>_<objeto>` ganha um `CREATE STREAM`, consumido por uma Task (`TASK_MERGE_<FONTE>_<OBJETO>`) que roda `WHEN SYSTEM$STREAM_HAS_DATA(...)` e faz MERGE incremental em `CORE.*` — processando só as linhas que mudaram desde o último consumo, em vez de reprocessar a staging inteira a cada run do DAG.

**Alternativas rejeitadas:**
- Stream em `CORE.TRANSACTIONS` alimentando o mart — rejeitado por conflitar com o motor de Dynamic Tables (ver contexto acima)
- Full MERGE de STAGING para CORE a cada DAG run (comportamento atual dos 3 conectores existentes) — mantido como está para Salesforce/Zendesk/Stripe (fora de escopo, D3 do DEFINE), mas os 3 conectores NOVOS deste sprint já nascem com o padrão Stream+Task, servindo de referência para uma futura migração dos conectores antigos

**Consequências:**
- AT-123 passa a validar: `SELECT SYSTEM$STREAM_HAS_DATA('STAGING.SAP_CUSTOMERS_STREAM')` retorna `TRUE` após INSERT na staging
- AT-124 passa a validar: linhas em `CORE.CUSTOMERS`/`CORE.TRANSACTIONS` refletem o conteúdo da staging sem reprocessar a tabela inteira (Task usa `MERGE ... USING (SELECT * FROM STREAM)`)
- `MART.DT_REVENUE_MOVEMENT` continua se beneficiando automaticamente — mudanças chegam mais rápido em `CORE.TRANSACTIONS` via Task incremental, e o Dynamic Table já propaga isso dentro do seu próprio `TARGET_LAG`, sem qualquer código adicional

---

### Decision 5 — Staging por fonte, schema único

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |

**Decisão:** `STAGING.SAP_CUSTOMERS`, `STAGING.SAP_INVOICES`, `STAGING.SAP_ORDERS`, `STAGING.ORACLE_CUSTOMERS` etc. — prefixo de fonte no nome da tabela, todas no schema `STAGING` já existente (Sprint 3), em vez de sub-schemas por fonte (`STAGING.SAP.*` exigiria multi-level namespacing não suportado nativamente da mesma forma).

---

## Code Patterns

### Pattern 1 — DAG de conector (SAP, exemplo — Oracle e HubSpot seguem o mesmo esqueleto)

```python
"""
NEXUS AI DataOps — SAP → Snowflake ingestion DAG
Sprint 4 — P0: provider-side Airflow pipeline (não vai no Native App)
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta

import requests
from airflow.decorators import dag, task
from airflow.models import Variable
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

logger = logging.getLogger(__name__)

DEFAULT_ARGS = {
    "owner": "nexus-platform",
    "depends_on_past": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
}

SAP_ENTITIES = {
    "customers": "Customers",
    "invoices":  "Invoices",
    "orders":    "Orders",
}
BATCH_SIZE = 2000


@dag(
    dag_id="nexus_sap_ingest",
    description="Ingere Customers/Invoices/Orders do SAP (OData) no Snowflake",
    schedule="0 2 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["nexus", "sap", "ingestion", "p0"],
)
def sap_ingest_dag():

    @task
    def fetch_sap_entity(entity_key: str) -> list[dict]:
        base_url = Variable.get("SAP_ODATA_BASE_URL")
        user     = Variable.get("SAP_USER")
        password = Variable.get("SAP_PASSWORD")
        entity   = SAP_ENTITIES[entity_key]

        rows, skip = [], 0
        while True:
            resp = requests.get(
                f"{base_url}/{entity}",
                params={"$format": "json", "$top": BATCH_SIZE, "$skip": skip},
                auth=(user, password),
                timeout=60,
            )
            resp.raise_for_status()
            batch = resp.json().get("d", {}).get("results", [])
            if not batch:
                break
            rows.extend(batch)
            skip += BATCH_SIZE
            if len(batch) < BATCH_SIZE:
                break
        logger.info("SAP %s: %d linhas extraídas", entity, len(rows))
        return rows

    @task
    def load_to_staging(rows: list[dict], table: str) -> str:
        if not rows:
            return f"OK: 0 linhas para {table}"
        hook = SnowflakeHook(snowflake_conn_id="nexus_snowflake")
        conn = hook.get_conn()
        cs = conn.cursor()
        cs.execute(
            f"CREATE TABLE IF NOT EXISTS {table} "
            f"(raw_data VARIANT, loaded_at TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP())"
        )
        cs.executemany(
            f"INSERT INTO {table} (raw_data) SELECT PARSE_JSON(%s)",
            [(json.dumps(r),) for r in rows],
        )
        cs.close()
        conn.close()
        return f"OK: {len(rows)} linhas carregadas em {table}"

    customers = load_to_staging(fetch_sap_entity("customers"), "STAGING.SAP_CUSTOMERS")
    invoices  = load_to_staging(fetch_sap_entity("invoices"),  "STAGING.SAP_INVOICES")
    orders    = load_to_staging(fetch_sap_entity("orders"),    "STAGING.SAP_ORDERS")


sap_ingest_dag()
```

> Oracle segue o mesmo esqueleto trocando `fetch_sap_entity` por uma função que usa `oracledb.connect(user=..., password=..., dsn=...)` + `cursor.execute("SELECT * FROM ...")`. HubSpot troca por paginação `after` cursor da API v3.

### Pattern 2 — Stream + Task de CDC (setup_script.sql, consumer-side)

```sql
-- Stream sobre staging recém-carregada pelo conector SAP
CREATE STREAM IF NOT EXISTS STAGING.SAP_CUSTOMERS_STREAM
    ON TABLE STAGING.SAP_CUSTOMERS
    APPEND_ONLY = TRUE;

-- Task que consome o Stream e faz MERGE incremental em CORE.CUSTOMERS
CREATE OR REPLACE TASK CORE.TASK_MERGE_SAP_CUSTOMERS
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = '15 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('STAGING.SAP_CUSTOMERS_STREAM')
AS
MERGE INTO CORE.CUSTOMERS tgt
USING (
    SELECT
        raw_data:CustomerID::VARCHAR       AS customer_id,
        raw_data:OrgId::VARCHAR            AS org_id,
        raw_data:Name::VARCHAR             AS name,
        raw_data:Email::VARCHAR            AS email
    FROM STAGING.SAP_CUSTOMERS_STREAM
) src
ON tgt.customer_id = src.customer_id
WHEN MATCHED THEN UPDATE SET
    name = src.name, email = src.email, updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (customer_id, org_id, name, email)
    VALUES (src.customer_id, src.org_id, src.name, src.email);

-- Mesmo padrão wrapping tolerante usado nos Sprints anteriores para o RESUME
-- (privilégio EXECUTE TASK só é concedido após o upgrade que o declara)
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TASK CORE.TASK_MERGE_SAP_CUSTOMERS RESUME;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
```

---

## Build Order

1. `snowflake/native_app/setup_script.sql` — `CREATE TABLE STAGING.SAP_*/ORACLE_*/HUBSPOT_*` + `CREATE STREAM` + `CREATE TASK` (P0, tabelas SAP primeiro)
2. `airflow/dags/sap_ingest_dag.py` (P0)
3. `airflow/dags/oracle_ingest_dag.py` (P0)
4. `airflow/dags/hubspot_ingest_dag.py` (P1)
5. `tests/python/test_pipelines.py` — extensão com `TestSAPDAG`, `TestOracleDAG`, `TestHubSpotDAG` (seguindo as classes já existentes `TestSalesforceDAG` etc.)
6. `tests/sql/test_semantic_models.sql` ou novo `tests/sql/test_cdc_streams.sql` — valida Stream + Task existem e a Task está `started`

---

## Risks

| Risco | Mitigação |
|-------|-----------|
| Cliente não tem SAP Gateway/OData habilitado | Documentar pré-requisito; DAG falha com erro claro (`raise_for_status()`) em vez de silenciar |
| `APPEND_ONLY = TRUE` no Stream perde updates/deletes da staging | Aceitável — staging é append-only por natureza (cada load do DAG insere novas linhas raw, nunca edita in-place); o MERGE em CORE é quem resolve dedupe/upsert |
| Task com `SCHEDULE = '15 MINUTE'` pode rodar mesmo sem necessidade | `WHEN SYSTEM$STREAM_HAS_DATA(...)` já evita execução (e custo de warehouse) quando não há linhas novas |
