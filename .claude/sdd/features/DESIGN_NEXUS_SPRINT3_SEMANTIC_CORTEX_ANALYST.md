# DESIGN — NEXUS Sprint 3: Semantic Models, Cortex Analyst & Multi-org

**Feature:** NEXUS_SPRINT3_SEMANTIC_CORTEX_ANALYST  
**Phase:** 2 — Design  
**Date:** 2026-06-19  
**Status:** Approved  
**Based on:** DEFINE_NEXUS_SPRINT3_SEMANTIC_CORTEX_ANALYST.md  

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  STREAMLIT (consumer)                                                   │
│                                                                         │
│  3_AI_Chat.py           11_Sales_Intelligence.py  12_Operations_...py  │
│  ┌─────────────────┐    ┌──────────────────────┐  ┌──────────────────┐ │
│  │ domain selector │    │  NL→SQL widget       │  │  NL→SQL widget   │ │
│  │ executive       │    │  revenue_opportunity  │  │  operations      │ │
│  │ revenue         │    │  _model.yaml         │  │  _model.yaml     │ │
│  │ operations ◄─── │    └──────┬───────────────┘  └──────┬───────────┘ │
│  │ customer        │           │                          │             │
│  └────────┬────────┘           └──────────┬──────────────┘             │
│           │                               │                             │
│           └──────────── utils/cortex_analyst.py ──────────────────────►│
│                         ask_analyst(question, model_file)               │
└──────────────────────────────────────────────────────────────────────┬──┘
                                                                       │
          ┌────────────────────────────────────────────────────────────▼──┐
          │  SNOWFLAKE — NEXUS_APP                                        │
          │                                                               │
          │  @CORE.SEMANTIC_STAGE/                                        │
          │  ├── nexus_revenue.yaml         (existente)                   │
          │  ├── executive_kpis.yaml        (existente)                   │
          │  ├── customer_360.yaml          (atualizado + INTERACTIONS)   │
          │  ├── operations_model.yaml      ← NOVO Sprint 3               │
          │  └── revenue_opportunity_model.yaml ← NOVO Sprint 3           │
          │                                                               │
          │  Cortex Analyst API ─────────────► NL→SQL → executa          │
          │                                                               │
          │  CORE.TICKETS   CORE.INTERACTIONS   MART.DT_CUSTOMER_HEALTH  │
          │  MART.REVENUE_OPPORTUNITY_SCORE     MART.DT_REVENUE_MOVEMENT  │
          │  CORE.PRODUCTS                                                │
          │                                                               │
          │  STAGING schema (novo) — tables criadas pelos Airflow DAGs    │
          │                                                               │
          │  Demo data: ORG-DEMO-001 (existente) + ORG-DEMO-002 (novo)   │
          └───────────────────────────────────────────────────────────────┘
                          ▲
          scripts/upload_semantic_models.sh (provider-side, pré-deploy)
          PUT file://snowflake/cortex/semantic_models/*.yaml
          @NEXUS_APP.CORE.SEMANTIC_STAGE/
```

---

## Architecture Decisions

### Decision 1 — Stage canônico `@CORE.SEMANTIC_STAGE/` para todos os modelos

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |
| **Data** | 2026-06-19 |

**Contexto:** `operations_agent.yaml` foi gerado no Sprint 2 com path errado (`CONFIG.NEXUS_STAGE`). Os outros 4 agents usam `CORE.SEMANTIC_STAGE`.

**Decisão:** Todos os semantic model YAMLs ficam em `@NEXUS_APP.CORE.SEMANTIC_STAGE/` (raiz, sem subpasta). Corrigir `operations_agent.yaml`.

**Alternativas rejeitadas:**
- Subpasta `semantic_models/` no stage — desnecessária, cria inconsistência com agentes existentes

**Consequências:** Um único stage, um único `LIST` para verificar todos os modelos.

---

### Decision 2 — Upload via Python script, não via setup_script

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |
| **Data** | 2026-06-19 |

**Contexto:** `PUT file://` não é suportado no contexto do Native App setup_script. Os YAMLs precisam estar no stage antes do Cortex Analyst ser chamado.

**Decisão:** `scripts/upload_semantic_models.sh` usa `snowflake.connector` Python (mesmo padrão do `deploy_snowflake.sh`) para fazer PUT dos 5 YAMLs. Executado pelo provider como passo de bootstrap após `snow app run`.

**Alternativas rejeitadas:**
- `snowsql -q "PUT ..."` — requer snowsql instalado; Python já é dependência do projeto
- Embutir YAMLs como strings no setup_script — inviável, ilegível, viola separação de concerns

**Consequências:** Deploy de semantic models requer step manual do provider; documentar em DEPLOYMENT.md.

---

### Decision 3 — `cortex_analyst.py` helper compartilhado

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |
| **Data** | 2026-06-19 |

**Contexto:** Três páginas Streamlit (`3_AI_Chat`, `11_Sales_Intelligence`, `12_Operations_Intelligence`) precisam chamar Cortex Analyst com modelos diferentes. Duplicar o código viola DRY.

**Decisão:** `app/streamlit/utils/cortex_analyst.py` com:
- `ask_analyst(question: str, model_file: str, session) -> AnalystResult` — chamada pura ao Cortex Analyst REST
- `render_analyst_widget(model_file: str, suggestions: list[str], key_prefix: str)` — widget completo reutilizável (input + resultado + SQL expandível + auto chart)

**Alternativas rejeitadas:**
- Só helper de chamada sem widget — páginas ainda duplicariam o render
- Mover lógica para `snowflake_client.py` — já está suficientemente carregado

---

### Decision 4 — Multi-domain routing por `st.selectbox` na sidebar de AI Chat

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |
| **Data** | 2026-06-19 |

**Contexto:** `3_AI_Chat.py` tem semantic model hardcoded como `nexus_revenue.yaml`. Com 5 modelos disponíveis, o usuário deve poder escolher o domínio de interesse.

**Decisão:** Adicionar `st.selectbox("Domínio de dados", DOMAIN_MODELS.keys())` na sidebar. `DOMAIN_MODELS` é um dict constante no topo do arquivo.

```python
DOMAIN_MODELS = {
    "Revenue & Customers":  "@CORE.SEMANTIC_STAGE/nexus_revenue.yaml",
    "Executive KPIs":       "@CORE.SEMANTIC_STAGE/executive_kpis.yaml",
    "Customer 360":         "@CORE.SEMANTIC_STAGE/customer_360.yaml",
    "Operations & Tickets": "@CORE.SEMANTIC_STAGE/operations_model.yaml",
    "Sales Opportunity":    "@CORE.SEMANTIC_STAGE/revenue_opportunity_model.yaml",
}
```

**Alternativas rejeitadas:**
- Páginas separadas por domínio — fragmenta a experiência de chat; usuário perde contexto
- Detecção automática por palavras-chave na pergunta — NLP superficial, erros frequentes

---

### Decision 5 — Demo ORG-DEMO-002 com perfil contrastante (SMB high-risk)

| Atributo | Valor |
|----------|-------|
| **Status** | Accepted |
| **Data** | 2026-06-19 |

**Contexto:** Todos os 10 clientes atuais são `ORG-DEMO-001`. RAP isolation não é demonstrável.

**Decisão:** Adicionar 3 clientes SMB LATAM de `ORG-DEMO-002` com `churn_risk HIGH` + 1 entry em `CONFIG.ORG_USER_MAP` para `NEXUS_ANALYST_2`. Todos os dados relacionados (tickets, interactions, churn_scores) seguem o mesmo padrão MERGE INTO.

---

## File Manifest

| # | File | Action | Purpose | Depends on |
|---|------|--------|---------|-----------|
| 1 | `snowflake/cortex/semantic_models/operations_model.yaml` | Create | Semantic model de Operações (TICKETS + INTERACTIONS + DT_CUSTOMER_HEALTH) | — |
| 2 | `snowflake/cortex/semantic_models/revenue_opportunity_model.yaml` | Create | Semantic model de Sales (REVENUE_OPPORTUNITY_SCORE + DT_REVENUE_MOVEMENT + PRODUCTS) | — |
| 3 | `snowflake/cortex/agents/operations_agent.yaml` | Modify | Corrigir path `CONFIG.NEXUS_STAGE` → `CORE.SEMANTIC_STAGE` | 1 |
| 4 | `scripts/upload_semantic_models.sh` | Create | PUT dos 5 YAMLs ao stage via Python snowflake-connector | 1, 2 |
| 5 | `snowflake/native_app/setup_script.sql` | Modify | `CREATE SCHEMA IF NOT EXISTS STAGING` + ORG-DEMO-002 demo data | — |
| 6 | `app/streamlit/utils/cortex_analyst.py` | Create | Helper: `ask_analyst()` + `render_analyst_widget()` | — |
| 7 | `app/streamlit/pages/3_AI_Chat.py` | Modify | Seletor de domínio + routing multi-modelo | 6 |
| 8 | `app/streamlit/pages/11_Sales_Intelligence.py` | Modify | Adicionar NL→SQL widget (revenue_opportunity_model) | 6 |
| 9 | `app/streamlit/pages/12_Operations_Intelligence.py` | Modify | Adicionar NL→SQL widget (operations_model) | 6 |
| 10 | `snowflake/cortex/semantic_models/customer_360.yaml` | Modify | Adicionar tabela CORE.INTERACTIONS + dimensions/measures | — |
| 11 | `tests/sql/test_semantic_models.sql` | Create | AT-110/112/113/114 — stages, schemas, demo data | 5 |
| 12 | `tests/python/test_cortex_analyst.py` | Create | Validação estrutural dos 5 YAMLs + helper | 1, 2, 6 |
| 13 | `snowflake/native_app/setup_script.sql` | Modify (P2) | AI.AGENT_MEMORY + AI.EMBEDDINGS tables | — |

---

## Code Patterns

### Pattern 1 — Semantic Model YAML (operations_model)

```yaml
name: nexus_operations_model
description: >
  Modelo semântico NEXUS — Operations Intelligence.
  Cobre tickets de suporte, interações com clientes e saúde operacional.
  Use para perguntas sobre volume de tickets, SLA, canais de atendimento e tendências.

tables:
  - name: tickets
    description: Tickets de suporte abertos e fechados.
    base_table:
      database: NEXUS_APP
      schema: CORE
      table: TICKETS
    primary_key:
      columns: [ticket_id]
    dimensions:
      - name: status
        synonyms: ["situação", "estado do ticket"]
        expr: status
        data_type: VARCHAR
      - name: priority
        synonyms: ["prioridade", "urgência", "severidade"]
        expr: priority
        data_type: VARCHAR
      - name: ticket_type
        synonyms: ["tipo de ticket", "categoria"]
        expr: ticket_type
        data_type: VARCHAR
      - name: created_at
        synonyms: ["data de abertura", "criado em"]
        expr: created_at
        data_type: TIMESTAMP_TZ
    measures:
      - name: ticket_count
        synonyms: ["número de tickets", "quantidade de chamados", "total de tickets"]
        expr: "1"
        data_type: NUMBER
        agg: count
        agg_time_dimension: created_at
      - name: avg_resolution_hours
        synonyms: ["tempo médio de resolução", "TTR", "tempo de atendimento"]
        expr: "DATEDIFF('hour', created_at, COALESCE(updated_at, CURRENT_TIMESTAMP()))"
        data_type: NUMBER
        agg: avg

  - name: interactions
    description: Interações com clientes via email, call, chat, meeting, SMS.
    base_table:
      database: NEXUS_APP
      schema: CORE
      table: INTERACTIONS
    # ... dimensions + measures

relationships:
  - name: ticket_customer
    left_table: tickets
    right_table: customer_health
    join_type: LEFT_OUTER
    relationship_columns:
      - left_column: customer_id
        right_column: customer_id

verified_queries:
  - name: tickets_abertos_urgentes
    question: "Quantos tickets urgentes estão abertos?"
    sql: |
      SELECT COUNT(*) AS urgent_open_tickets
      FROM NEXUS_APP.CORE.TICKETS
      WHERE status = 'open' AND priority = 'urgent'
```

### Pattern 2 — `ask_analyst()` helper

```python
# app/streamlit/utils/cortex_analyst.py
from dataclasses import dataclass
import time
import streamlit as st
from snowflake.snowpark.context import get_active_session

@dataclass
class AnalystResult:
    text: str
    sql: str | None
    latency_ms: int
    error: str | None

def ask_analyst(question: str, model_file: str) -> AnalystResult:
    session = get_active_session()
    t0 = time.monotonic()
    try:
        resp = session.sql("""
            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                'mistral-large2',
                ARRAY_CONSTRUCT(
                    OBJECT_CONSTRUCT('role','system','content',
                        'You are a data analyst. Generate SQL for the question.'),
                    OBJECT_CONSTRUCT('role','user','content', ?)
                )
            )
        """, [question]).collect()
        # Na prática usa REST API Cortex Analyst — ver snowflake_client.call_cortex_analyst
        ...
    except Exception as e:
        return AnalystResult("", None, int((time.monotonic()-t0)*1000), str(e))
```

> **Nota:** `ask_analyst` chama `utils.snowflake_client.call_cortex_analyst(question, model_file)` já existente — o helper apenas encapsula o `model_file` e expõe o widget.

### Pattern 3 — `render_analyst_widget()` reutilizável

```python
def render_analyst_widget(
    model_file: str,
    suggestions: list[str],
    key_prefix: str = "analyst",
    placeholder: str = "Faça uma pergunta sobre seus dados…",
) -> None:
    """Widget completo: sugestões → input → resultado → SQL → chart."""
    from utils.snowflake_client import call_cortex_analyst, run_query
    import pandas as pd

    history_key = f"{key_prefix}_history"
    if history_key not in st.session_state:
        st.session_state[history_key] = []

    # Sugestões como botões
    if suggestions and not st.session_state[history_key]:
        cols = st.columns(min(len(suggestions), 3))
        for i, sug in enumerate(suggestions):
            if cols[i % 3].button(sug, key=f"{key_prefix}_sug_{i}"):
                st.session_state[history_key].append({"role": "user", "content": sug})
                st.rerun()

    # Histórico
    for msg in st.session_state[history_key]:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            if msg.get("sql"):
                with st.expander("🔍 SQL gerado"):
                    st.code(msg["sql"], language="sql")
            if msg.get("df") is not None:
                st.dataframe(msg["df"], use_container_width=True, hide_index=True)

    # Input
    if question := st.chat_input(placeholder, key=f"{key_prefix}_input"):
        st.session_state[history_key].append({"role": "user", "content": question})
        with st.spinner("Consultando dados…"):
            result = call_cortex_analyst(question, model_file)
        df = pd.DataFrame()
        if result["sql"]:
            try:
                df = run_query(result["sql"])
            except Exception:
                pass
        entry = {
            "role": "assistant",
            "content": result["text"] or f"{len(df)} resultados.",
            "sql": result["sql"],
            "df": df if not df.empty else None,
        }
        st.session_state[history_key].append(entry)
        st.rerun()
```

### Pattern 4 — Multi-domain routing em AI Chat

```python
# Em 3_AI_Chat.py — adicionar na sidebar, ANTES do chat_mode radio
DOMAIN_MODELS = {
    "Revenue & Customers":  "@CORE.SEMANTIC_STAGE/nexus_revenue.yaml",
    "Executive KPIs":       "@CORE.SEMANTIC_STAGE/executive_kpis.yaml",
    "Customer 360":         "@CORE.SEMANTIC_STAGE/customer_360.yaml",
    "Operations & Tickets": "@CORE.SEMANTIC_STAGE/operations_model.yaml",
    "Sales Opportunity":    "@CORE.SEMANTIC_STAGE/revenue_opportunity_model.yaml",
}

with st.sidebar:
    selected_domain = st.selectbox(
        "Domínio de dados",
        list(DOMAIN_MODELS.keys()),
        index=0,
        help="Selecione o contexto de dados para o Cortex Analyst",
    )
    SEMANTIC_MODEL = DOMAIN_MODELS[selected_domain]  # substitui a constante hardcoded
```

### Pattern 5 — upload_semantic_models.sh via Python connector

```bash
#!/usr/bin/env bash
# scripts/upload_semantic_models.sh
set -euo pipefail

MODELS_DIR="$(dirname "$0")/../snowflake/cortex/semantic_models"
STAGE="@NEXUS_APP.CORE.SEMANTIC_STAGE"

python3 - <<PYEOF
import os, glob, snowflake.connector

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    database="NEXUS_APP",
    role=os.environ.get("SNOWFLAKE_ROLE", "NEXUS_SYSADMIN"),
    warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "NEXUS_APP_WH"),
)
cur = conn.cursor()
stage = "${STAGE}"
models_dir = "${MODELS_DIR}"

for yaml_path in glob.glob(f"{models_dir}/*.yaml"):
    fname = os.path.basename(yaml_path)
    cur.execute(f"PUT file://{yaml_path} {stage}/{fname} OVERWRITE = TRUE AUTO_COMPRESS = FALSE")
    print(f"  ✓ {fname} → {stage}/{fname}")

cur.execute(f"LIST {stage}")
rows = cur.fetchall()
print(f"\nStage content: {len(rows)} files")
conn.close()
PYEOF
```

### Pattern 6 — Demo data ORG-DEMO-002 (setup_script)

```sql
-- Schema STAGING (novo P0)
CREATE SCHEMA IF NOT EXISTS STAGING;
GRANT USAGE ON SCHEMA STAGING TO APPLICATION ROLE NEXUS_ADMIN;

-- ORG-DEMO-002 em CONFIG.ORG_USER_MAP
MERGE INTO CONFIG.ORG_USER_MAP t
USING (
    SELECT 'ORG-DEMO-002' AS org_id, 'NEXUS_ANALYST_2' AS user_name, 'analyst' AS role
) s ON t.org_id = s.org_id AND t.user_name = s.user_name
WHEN NOT MATCHED THEN INSERT (org_id, user_name, role) VALUES (s.org_id, s.user_name, s.role);

-- Clientes ORG-DEMO-002 (3 SMB, high churn)
MERGE INTO CORE.CUSTOMERS t
USING (
    SELECT 'CUST-DEMO-011' AS customer_id, 'ORG-DEMO-002' AS org_id, 'Kappa Varejo' AS name,
           'admin@kappa.com' AS email, 'SMB' AS segment, 'LATAM' AS region,
           'Retail' AS industry, 'at_risk' AS lifecycle_stage,
           12000.00 AS arr, 1000.00 AS mrr, 8 AS nps_score,
           '2026-07-31'::DATE AS contract_end_date UNION ALL
    SELECT 'CUST-DEMO-012', 'ORG-DEMO-002', 'Lambda Serviços', 'admin@lambda.com',
           'SMB', 'LATAM', 'Services', 'at_risk', 9600.00, 800.00, 15, '2026-08-31'::DATE UNION ALL
    SELECT 'CUST-DEMO-013', 'ORG-DEMO-002', 'Mu Construção', 'admin@mu.com',
           'SMB', 'LATAM', 'Construction', 'active', 14400.00, 1200.00, 32, '2027-02-28'::DATE
) s ON t.customer_id = s.customer_id
WHEN NOT MATCHED THEN INSERT
    (customer_id, org_id, name, email, segment, region, industry, lifecycle_stage, arr, mrr, nps_score, contract_end_date)
    VALUES (s.customer_id, s.org_id, s.name, s.email, s.segment, s.region, s.industry,
            s.lifecycle_stage, s.arr, s.mrr, s.nps_score, s.contract_end_date);
```

### Pattern 7 — Estrutura customer_360.yaml update (adicionar INTERACTIONS)

```yaml
  - name: interactions
    description: Histórico de interações com clientes — emails, calls, meetings, chat.
    base_table:
      database: NEXUS_APP
      schema: CORE
      table: INTERACTIONS
    primary_key:
      columns: [interaction_id]
    dimensions:
      - name: channel
        synonyms: ["canal", "meio de contato", "forma de atendimento"]
        description: Canal da interação — email, call, chat, meeting, sms, social.
        expr: channel
        data_type: VARCHAR
      - name: direction
        synonyms: ["direção", "iniciativa"]
        description: inbound (cliente iniciou) ou outbound (nós iniciamos).
        expr: direction
        data_type: VARCHAR
      - name: occurred_at
        synonyms: ["data da interação", "quando ocorreu"]
        expr: occurred_at
        data_type: TIMESTAMP_TZ
    measures:
      - name: interaction_count
        synonyms: ["número de interações", "contato", "atividade"]
        expr: "1"
        data_type: NUMBER
        agg: count
        agg_time_dimension: occurred_at
      - name: avg_sentiment
        synonyms: ["sentimento médio", "tom das interações"]
        expr: sentiment_score
        data_type: NUMBER
        agg: avg

# Relationship: customer_360 ↔ interactions
relationships:
  - name: customer_interactions
    left_table: customer_360
    right_table: interactions
    join_type: LEFT_OUTER
    relationship_columns:
      - left_column: customer_id
        right_column: customer_id
```

### Pattern 8 — NL→SQL widget em Sales Intelligence

```python
# Em 11_Sales_Intelligence.py — adicionar nova tab
tab1, tab2, tab3, tab4 = st.tabs([
    "Pipeline de Oportunidades", "Movimento de Receita", "Análise por Tipo",
    "💬 Perguntar em Linguagem Natural"  # ← nova
])

with tab4:
    st.markdown("### Consulta livre — Sales Intelligence")
    st.caption("Perguntas sobre pipeline, oportunidades e receita usando Cortex Analyst.")
    from utils.cortex_analyst import render_analyst_widget
    render_analyst_widget(
        model_file="@CORE.SEMANTIC_STAGE/revenue_opportunity_model.yaml",
        suggestions=[
            "Qual cliente tem maior oportunidade de upsell?",
            "Quais renovações vencem nos próximos 60 dias?",
            "Qual é o pipeline total estimado em USD?",
            "Mostre os 5 maiores scores de oportunidade.",
        ],
        key_prefix="sales_analyst",
    )
```

---

## Testing Strategy

| Tipo | Arquivo | Cobertura |
|------|---------|-----------|
| SQL — estrutura | `tests/sql/test_semantic_models.sql` | AT-110 (stage), AT-112 (multi-org), AT-113 (STAGING schema), AT-114 (YAMLs no stage) |
| Python — YAML válido | `tests/python/test_cortex_analyst.py` | Estrutura dos 5 YAMLs: name, tables, dimensions, measures, verified_queries |
| Python — helper | `tests/python/test_cortex_analyst.py` | `ask_analyst` importa; `render_analyst_widget` aceita argumentos corretos |
| Manual — AT-111 | 3_AI_Chat.py domínio Operations | SQL gerado refere-se a CORE.TICKETS |
| Manual — AT-115 | 3_AI_Chat.py domain switching | Switching muda model_file na chamada |

### test_semantic_models.sql — estrutura

```sql
-- AT-112: 2 org_ids no demo data
SELECT 'AT-112' AS test_id,
    CASE WHEN COUNT(DISTINCT org_id) >= 2 THEN 'PASS'
         ELSE 'FAIL: apenas ' || COUNT(DISTINCT org_id)::VARCHAR || ' org(s)'
    END AS result
FROM CORE.CUSTOMERS;

-- AT-113: STAGING schema existe
SELECT 'AT-113' AS test_id,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME = 'STAGING';

-- AT-110: SEMANTIC_STAGE existe
SELECT 'AT-110' AS test_id,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA = 'CORE' AND STAGE_NAME = 'SEMANTIC_STAGE';
```

### test_cortex_analyst.py — estrutura YAML

```python
import yaml
from pathlib import Path

MODELS_DIR = Path(__file__).parent.parent.parent / "snowflake/cortex/semantic_models"
REQUIRED_MODELS = [
    "executive_kpis.yaml",
    "nexus_revenue.yaml",
    "customer_360.yaml",
    "operations_model.yaml",
    "revenue_opportunity_model.yaml",
]

class TestSemanticModelStructure:
    def test_all_models_exist(self):
        for fname in REQUIRED_MODELS:
            assert (MODELS_DIR / fname).exists(), f"{fname} não encontrado"

    def test_operations_model_valid_yaml(self):
        model = yaml.safe_load((MODELS_DIR / "operations_model.yaml").read_text())
        assert "name" in model
        assert "tables" in model
        assert len(model["tables"]) >= 2  # tickets + interactions mínimo
        for table in model["tables"]:
            assert "dimensions" in table
            assert "measures" in table

    def test_operations_model_covers_tickets(self):
        model = yaml.safe_load((MODELS_DIR / "operations_model.yaml").read_text())
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "TICKETS" in table_names

    def test_revenue_opportunity_model_valid(self):
        model = yaml.safe_load((MODELS_DIR / "revenue_opportunity_model.yaml").read_text())
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "REVENUE_OPPORTUNITY_SCORE" in table_names or "DT_REVENUE_OPPORTUNITY_SCORE" in table_names

    def test_all_models_have_verified_queries(self):
        for fname in REQUIRED_MODELS:
            model = yaml.safe_load((MODELS_DIR / fname).read_text())
            assert "verified_queries" in model, f"{fname} sem verified_queries"
            assert len(model["verified_queries"]) >= 2, f"{fname} tem menos de 2 verified_queries"
```

---

## Dependency Order for Build

```
1. Semantic models novos (files #1, #2) — sem dependências
2. operations_agent.yaml fix (file #3) — depende de #1
3. upload_semantic_models.sh (file #4) — depende de #1, #2
4. setup_script.sql STAGING + ORG-DEMO-002 (file #5) — sem dependências
5. cortex_analyst.py helper (file #6) — sem dependências
6. 3_AI_Chat.py domain routing (file #7) — depende de #6
7. 11_Sales_Intelligence.py widget (file #8) — depende de #6
8. 12_Operations_Intelligence.py widget (file #9) — depende de #6
9. customer_360.yaml update (file #10) — sem dependências (paralelo com #1, #2)
10. Tests SQL (file #11) — depende de #5
11. Tests Python (file #12) — depende de #1, #2, #6
12. setup_script P2: AI.AGENT_MEMORY, AI.EMBEDDINGS (file #13) — independente
```

---

## Estimated Scope

| Categoria | Arquivos | Estimativa |
|-----------|---------|-----------|
| Semantic Models (novos) | 2 | ~150 linhas cada |
| Agent YAML fix | 1 | 2 linhas |
| Upload script | 1 | ~50 linhas |
| setup_script modificações | 1 | ~80 linhas (STAGING + ORG-002 + P2) |
| Streamlit (novo helper + 3 páginas) | 4 | ~200 linhas total |
| customer_360.yaml update | 1 | ~60 linhas |
| Testes | 2 | ~100 linhas |
| **Total** | **12** | **~800 linhas** |
