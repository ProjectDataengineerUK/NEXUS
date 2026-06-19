# DESIGN: NEXUS Sprint 2 — Data Onboarding, Multi-tenancy & KBS

> Especificação técnica completa para implementação do Sprint 2. Endereça os 3 blockers P0 (references, RAP, ingestão automática) e a camada KBS, transformando o NEXUS em um Native App instalável por clientes reais.

## Metadata

| Attribute | Value |
|-----------|-------|
| **Feature** | NEXUS_SPRINT2_DATA_ONBOARDING |
| **Date** | 2026-06-19 |
| **Author** | design-agent |
| **DEFINE** | [DEFINE_NEXUS_SPRINT2_DATA_ONBOARDING.md](./DEFINE_NEXUS_SPRINT2_DATA_ONBOARDING.md) |
| **Gap Analysis** | [GAP_ANALYSIS_2026-06-19.md](../reports/GAP_ANALYSIS_2026-06-19.md) |
| **Build v1 (archived)** | [BUILD_NEXUS_AI_DATAOPS_v1.md](../archive/BUILD_NEXUS_AI_DATAOPS_v1.md) |
| **Status** | Ready for Build |

---

## Architecture Overview

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                     NEXUS AI DataOps — Sprint 2 Architecture                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  PROVIDER SIDE (NEXUS team infra — AWS)                                       │
│  ──────────────────────────────────────────────────────────────────────────   │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │  Airflow (MWAA / local)                                                  │  │
│  │  ─────────────────────────────────────────────────────────────────────  │  │
│  │  salesforce_ingest_dag.py ──┐                                            │  │
│  │  zendesk_ingest_dag.py    ──┤──→ UPSERT via External Access Integration  │  │
│  │  stripe_ingest_dag.py     ──┘          ↓                                 │  │
│  │  kbs_refresh_dag.py          NEXUS_APP.CORE.* (consumer's Snowflake)    │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                │
│  CONSUMER SIDE (instala Native App via Marketplace)                           │
│  ──────────────────────────────────────────────────────────────────────────   │
│                                                                                │
│  ┌──────────────────┐   references:   ┌──────────────────────────────────┐   │
│  │  Consumer's DB   │ ←────────────── │  manifest.yml                    │   │
│  │  MY_DB.MY_SCHEMA │                 │  + CORE.REGISTER_REFERENCE SP    │   │
│  │  .CUSTOMERS      │                 └──────────────┬───────────────────┘   │
│  │  .INVOICES       │                                │                        │
│  │  .EVENTS         │                                ↓                        │
│  └──────────────────┘     ┌───────────────────────────────────────────────┐  │
│          │                │  NEXUS Native App (setup_script.sql)           │  │
│          │ SYSTEM$REF     │  ────────────────────────────────────────────  │  │
│          └──────────────→ │  Tasks → CORE.CUSTOMERS / TRANSACTIONS / etc   │  │
│                           │  Dynamic Tables → MART.DT_*                    │  │
│                           │  RAP (org_id isolation via USER_ORG_MAPPING)   │  │
│                           │  External Access Integration (Salesforce API)   │  │
│                           │                                                 │  │
│                           │  KBS schema:                                    │  │
│                           │    KBS.DOCUMENTS / CHUNKS / SOURCES             │  │
│                           │    Cortex Search: KB_SEARCH_SERVICE             │  │
│                           │                                                 │  │
│                           │  Streamlit UI:                                  │  │
│                           │    0_Setup.py (onboarding wizard)  ← NEW       │  │
│                           │    1_Executive_Command.py                       │  │
│                           │    2_Customer_360.py                            │  │
│                           │    3_AI_Chat.py (+ Operations Agent)  ← NEW    │  │
│                           │    11_Sales_Intelligence.py  ← NEW (P2)        │  │
│                           │    12_Operations_Intelligence.py ← NEW (P2)    │  │
│                           └───────────────────────────────────────────────┘  │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

| Component | Purpose | Technology | Priority |
|-----------|---------|------------|----------|
| `manifest.yml` com `references:` | Binding de tabelas do consumer no install | Native App Framework | P0 |
| `CORE.REGISTER_REFERENCE` SP | Callback chamado pelo Snowflake ao mapear tabela | Snowflake SQL | P0 |
| `CONFIG.USER_ORG_MAPPING` | Mapeamento user → org_id para RAP | Snowflake Table | P0 |
| `CORE.RAP_ORG_ISOLATION` | Row Access Policy por org_id | Snowflake RAP | P0 |
| `External Access Integration` | Permitir chamadas HTTP externas (Salesforce, Zendesk, Stripe) | Native App privilege | P0 |
| `0_Setup.py` | Onboarding wizard Streamlit (mapeamento de tabelas) | Streamlit in Snowflake | P0 |
| Snowflake Tasks | Execução automática de ingestão e refresh | Native App Tasks | P0 |
| `CORE.ACCOUNTS / PRODUCTS / INTERACTIONS` | 3 tabelas canônicas ausentes | Snowflake DDL | P1 |
| `MART.DT_*` no setup_script | Dynamic Tables que chegam ao consumer | Snowflake Dynamic Tables | P1 |
| `KBS` schema completo | Knowledge Base Systems (documentação técnica para agentes) | Cortex Search + Tables | P1 |
| `operations_agent.yaml` | 6º agente: inteligência operacional | Cortex Agents | P1 |
| External Stages (S3/Azure/GCS) | Ingestão de dados de cloud storage do consumer | Snowflake External Stage | P1 |
| Revenue Opportunity Score | DT com scoring de oportunidade por cliente | Dynamic Table + model | P1 |
| Airflow DAGs (3) | Orquestração de ingestão Salesforce/Zendesk/Stripe | Airflow TaskFlow API 3.0 | P1 |
| Agent-specific roles | RBAC por agente no setup_script | Snowflake RBAC | P1 |
| Sales Intelligence page | Página Streamlit de inteligência de vendas | Streamlit | P2 |
| Operations Intelligence page | Página Streamlit de inteligência operacional | Streamlit | P2 |

---

## Key Decisions

### Decision 1: `references:` no manifest.yml como mecanismo de binding

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-19 |

**Context:** O consumer precisa mapear suas tabelas próprias (customers, transactions, events) ao NEXUS durante o install. O `CORE.REGISTER_REFERENCE` SP já existe mas não tem UI nem declaração no manifest.

**Choice:** Adicionar bloco `references:` nativo do Snowflake Native App Framework ao `manifest.yml`, com `register_callback: CORE.REGISTER_REFERENCE` apontando para o SP existente.

**Rationale:** É o mecanismo oficial do framework — o Snowflake UI do Marketplace exibe automaticamente o formulário de mapeamento ao consumer durante o install, sem precisar de código custom. O SP de callback já existe e só precisa ser conectado.

**Alternatives Rejected:**
1. UI custom na própria Streamlit que pede o nome da tabela como string — frágil, sem validação de schema, consumer pode digitar qualquer coisa
2. Exigir que consumer faça GRANT da tabela diretamente para o app DB — viola princípio de dados no lugar do consumer, cria acoplamento

**Consequences:**
- `required: false` em todas as 3 referências → consumer pode instalar sem mapear (usa demo data via fallback)
- O SP `CORE.REGISTER_REFERENCE` precisa ser atualizado para armazenar o SYSTEM$REFERENCE token em `CONFIG.DATA_SOURCES`

---

### Decision 2: Row Access Policy com CONFIG.USER_ORG_MAPPING

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-19 |

**Context:** `org_id` está em todas as 22 tabelas mas nenhuma RAP foi criada no `setup_script.sql`. No contexto de Native App, a RAP precisa filtrar dados do consumer por tenant (org_id) usando informações disponíveis em runtime.

**Choice:** Criar `CONFIG.USER_ORG_MAPPING (user_login_name VARCHAR, org_id VARCHAR, role VARCHAR)` no setup_script. A RAP usa `CURRENT_USER()` para lookup nesta tabela. O onboarding wizard popula o mapeamento durante o setup.

**Rationale:** `CURRENT_USER()` é disponível em RAP dentro de Native App. É o padrão documentado pelo Snowflake para isolamento multi-tenant em Native Apps. Alternativas que usam `SYSTEM$REFERENCE()` na RAP não são suportadas — SYSTEM$REFERENCE é para DML, não DDL policies.

**Alternatives Rejected:**
1. `SYSTEM$REFERENCE()` na RAP — não é sintaxe suportada em Row Access Policies
2. Hard-coded `org_id` na RAP — não permite múltiplos tenants na mesma conta consumer
3. Uma RAP por org_id — explode em N policies conforme crescem os tenants

**Consequences:**
- CONFIG.USER_ORG_MAPPING precisa ser populada durante o onboarding wizard (0_Setup.py)
- Para o usuário NEXUS_ADMIN (provider), o mapeamento deve existir com acesso a todos os org_ids
- Demo data usa org_id = 'ORG-DEMO-001' por default

---

### Decision 3: KBS com Cortex Search unificado + filtro por kb_name

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-19 |

**Context:** CONTEXT.md planeja 8 knowledge bases separadas. Cortex Search cria serviços independentes. A questão é: 1 serviço por KB ou 1 serviço unificado com filtro?

**Choice:** 1 único `CORTEX SEARCH SERVICE` chamado `KBS.KB_SEARCH_SERVICE` sobre `KBS.DOCUMENTS`, com filtro `kb_name` em todas as queries. Para Sprint 2: apenas 2 KBs populadas (Snowflake Core + Cortex AI).

**Rationale:** 
- Cortex Search cobra por token indexado + query; 1 serviço = menor overhead de administração
- Filtro por `kb_name` é suportado nativamente no `SEARCH` function como `FILTER` clause
- Futuro: se uma KB crescer muito (>10M chunks), pode ser migrada para serviço dedicado

**Alternatives Rejected:**
1. Um serviço por KB — 8 serviços para gerenciar, custo de manutenção alto, cada agente precisa saber qual serviço chamar
2. Vector store customizado com embeddings em `AI.EMBEDDINGS` — mais controle mas mais manutenção, e Cortex Search é otimizado para o Snowflake

**Consequences:**
- Sprint 2c popula apenas KB_SNOWFLAKE_CORE e KB_CORTEX_AI; os 6 restantes ficam para Sprint 3+
- A coluna `kb_name` em `KBS.DOCUMENTS` é o discriminador; deve ter índice/cluster key

---

### Decision 4: External Access Integration ativado via setup_script + manifest privilege

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-19 |

**Context:** `09_network_rules.sql` tem o EAI definido mas comentado. Os pipelines de ingestão (ingest_salesforce.py etc.) precisam de acesso HTTP externo para funcionar no contexto do Native App.

**Choice:** Descomentar o `CREATE EXTERNAL ACCESS INTEGRATION NEXUS_EXTERNAL_ACCESS` no `09_network_rules.sql` E incluir sua execução no `setup_script.sql`. Adicionar `EXTERNAL_ACCESS_INTEGRATION` à lista de privileges no `manifest.yml`.

**Rationale:** O consumer deve aprovar explicitamente a integração de acesso externo durante o install — isso é o comportamento correto do Marketplace. A aprovação explícita do consumer é uma feature, não um bug: dá transparência sobre o que o app faz.

**Alternatives Rejected:**
1. Usar AWS Lambda como proxy (chama a API, grava no S3, Snowpipe ingere) — funciona mas adiciona infra, latência e custo fora do Snowflake
2. Manter EAI desativado e usar só Tasks para COPY INTO stages — não resolve ingestão de APIs em tempo real

**Consequences:**
- Consumer vê "Este app solicita acesso à internet para APIs: api.salesforce.com, api.zendesk.com, api.stripe.com" no install
- Na configuração de credenciais (0_Setup.py), consumer fornece tokens que ficam em `CONFIG.API_CREDENTIALS`

---

### Decision 5: Snowflake Tasks para MVP; Airflow como complemento provider-side

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-19 |

**Context:** O DEFINE tem Open Question sobre Tasks vs Airflow. Tasks no setup_script chegam ao consumer; DAGs Airflow só rodam na infra do provider.

**Choice:** Dual-track:
- **Tasks no setup_script**: Executam refresh de DTs e chamadas internas (churn pipeline, executive briefings) — chegam ao consumer
- **Airflow DAGs**: Orquestram chamadas a APIs externas (Salesforce, Zendesk, Stripe) via External Access do lado do provider — ficam no repo mas rodam em MWAA/Airflow local

**Rationale:** Tasks são mais simples para o consumer (não precisam de infra separada). Mas Airflow tem retry, monitoring, backfill e observabilidade superiores para pipelines críticos de negócio. A separação de responsabilidades é clara: Tasks para o que é dentro do Snowflake, Airflow para o que precisa de orquestração externa.

**Alternatives Rejected:**
1. Apenas Tasks — sem retry sofisticado, sem UI de monitoring DAG, difícil depurar falhas de API
2. Apenas Airflow — DAGs não chegam ao consumer via Native App; consumer precisaria de infra Airflow própria

**Consequences:**
- Airflow DAGs ficam em `airflow/dags/` no repo NEXUS (infra do provider)
- Tasks ficam em `setup_script.sql` (chegam ao consumer)
- `ingest_salesforce.py` é chamado tanto pelas Tasks (via Snowpark) quanto pelos DAGs Airflow

---

## Data Flow

```text
FLUXO P0 — Onboarding de um novo consumer:

1. Consumer instala Native App pelo Snowflake Marketplace
   │
   ▼
2. manifest.yml exibe form: "Conectar fontes de dados"
   │  consumer seleciona MY_DB.MY_SCHEMA.CUSTOMERS → Snowflake chama
   │  NEXUS_APP.CORE.REGISTER_REFERENCE('customer_table', SYSTEM$REFERENCE(...))
   ▼
3. REGISTER_REFERENCE SP armazena o token em CONFIG.DATA_SOURCES
   │  e popula CONFIG.USER_ORG_MAPPING com o usuário admin do consumer
   ▼
4. 0_Setup.py (wizard Streamlit) — consumer configura:
   │  - Credenciais de API (Salesforce token, Zendesk API key, Stripe key)
   │  - org_id da organização
   │  - Usuários e seus org_ids (USER_ORG_MAPPING)
   ▼
5. Task NEXUS_INGEST_CUSTOMERS_TASK executa (schedule: 1h):
   │  CORE.INGEST_FROM_REFERENCE() → usa SYSTEM$REFERENCE('CUSTOMER_TABLE')
   │  INSERT INTO CORE.CUSTOMERS SELECT ... FROM SYSTEM$REFERENCE(...)
   ▼
6. Dynamic Tables atualizam automaticamente:
   │  DT_EXECUTIVE_KPIS ← CORE.CUSTOMERS + CORE.TRANSACTIONS
   │  DT_CUSTOMER_HEALTH ← CORE.CUSTOMERS + AI.CHURN_SCORES
   │  DT_REVENUE_MOVEMENT ← CORE.TRANSACTIONS
   ▼
7. RAP filtra todos os SELECTs por org_id do usuário corrente:
   │  CORE.RAP_ORG_ISOLATION → CURRENT_USER() lookup em CONFIG.USER_ORG_MAPPING
   ▼
8. UI Streamlit mostra dados reais do consumer (não demo data)

──────────────────────────────────────────────────────────────

FLUXO P1 — Agente de IA consultando KBS:

1. Usuário no Chat: "Qual é a diferença entre Dynamic Table e Stream no Snowflake?"
   │
   ▼
2. 3_AI_Chat.py roteia para agent_mode = 'kbs_agent' (novo) ou executive_agent
   │
   ▼
3. Cortex Agent usa tool: SEARCH(KBS.KB_SEARCH_SERVICE, query, filter={kb_name: 'KB_SNOWFLAKE_CORE'})
   │
   ▼
4. Cortex Search retorna top-k chunks de KBS.DOCUMENTS com source_url
   │
   ▼
5. LLM (claude-sonnet-4-6) gera resposta citando chunks recuperados
   │
   ▼
6. KBS.SEARCH_LOGS registra query, kb_name, tokens usados, feedback
```

---

## File Manifest

### Sprint 2a — P0 (2 semanas)

| # | File | Action | Purpose | Agent | Dependencies |
|---|------|--------|---------|-------|--------------|
| 1 | `native_app/manifest.yml` | Modify | Adicionar `references:` block + `EXTERNAL_ACCESS_INTEGRATION` privilege | @snowflake-governance-expert | None |
| 2 | `native_app/setup_script.sql` | Modify | Adicionar: RAP org_id, CONFIG.USER_ORG_MAPPING, External Access, Tasks de ingestão | @snowflake-data-engineer | 1 |
| 3 | `snowflake/stored_procedures/register_reference.sql` | Modify | Atualizar REGISTER_REFERENCE SP para armazenar token + mapeamento | @snowflake-sql-expert | 2 |
| 4 | `app/streamlit/pages/0_Setup.py` | Create | Onboarding wizard: mapear tabelas, configurar credenciais, org_id, usuários | @python-developer | 2, 3 |
| 5 | `app/streamlit/utils/onboarding.py` | Create | Funções auxiliares do wizard: validar schema de tabela, status de onboarding | @python-developer | 4 |
| 6 | `tests/sql/test_references.sql` | Create | Testes de AT-101 (binding de referências) e AT-102 (isolamento RAP) | @snowflake-sql-expert | 2 |

**Total Sprint 2a: 6 arquivos (2 modify, 4 create)**

---

### Sprint 2b — P1 Pipeline + Tabelas (4 semanas)

| # | File | Action | Purpose | Agent | Dependencies |
|---|------|--------|---------|-------|--------------|
| 7 | `native_app/setup_script.sql` | Modify (cont.) | Adicionar CORE.ACCOUNTS, CORE.PRODUCTS, CORE.INTERACTIONS + demo data MERGE INTO | @snowflake-data-engineer | 2 |
| 8 | `native_app/setup_script.sql` | Modify (cont.) | Incluir Dynamic Tables no setup_script (DT_EXECUTIVE_KPIS, DT_CUSTOMER_HEALTH, DT_REVENUE_MOVEMENT) | @snowflake-data-engineer | 7 |
| 9 | `snowflake/setup/11_canonical_tables.sql` | Create | DDL standalone de CORE.ACCOUNTS, PRODUCTS, INTERACTIONS (para deploy direto) | @snowflake-sql-expert | None |
| 10 | `snowflake/setup/12_dynamic_tables_native.sql` | Create | Dynamic Tables para setup_script (com WAREHOUSE = NEXUS_APP_WH) | @snowflake-data-engineer | 9 |
| 11 | `snowflake/setup/13_revenue_score.sql` | Create | DT_REVENUE_OPPORTUNITY_SCORE + Revenue Score stored procedure | @snowflake-data-engineer | 9 |
| 12 | `snowflake/setup/14_external_stages.sql` | Create | Storage Integrations + External Stages para S3, Azure Blob, GCS | @snowflake-data-engineer | None |
| 13 | `snowflake/setup/15_agent_roles.sql` | Create | Roles por agente: AGENT_EXECUTIVE_READONLY, AGENT_REVENUE_READONLY, etc. + GRANTs | @snowflake-governance-expert | 2 |
| 14 | `airflow/dags/salesforce_ingest_dag.py` | Create | Airflow TaskFlow API 3.0 DAG: pull Salesforce → CORE.CUSTOMERS | @airflow-specialist | None |
| 15 | `airflow/dags/zendesk_ingest_dag.py` | Create | Airflow TaskFlow API 3.0 DAG: pull Zendesk → CORE.TICKETS | @airflow-specialist | None |
| 16 | `airflow/dags/stripe_ingest_dag.py` | Create | Airflow TaskFlow API 3.0 DAG: pull Stripe → CORE.TRANSACTIONS | @airflow-specialist | None |
| 17 | `airflow/connections/snowflake_default.json` | Create | Template de conexão Airflow → Snowflake | @airflow-specialist | None |
| 18 | `airflow/requirements.txt` | Create | Dependências Airflow: apache-airflow, snowflake-connector-python, simple-salesforce | @airflow-specialist | None |
| 19 | `tests/sql/test_dynamic_tables.sql` | Create | Teste AT-105 (DTs no consumer) e AT-107 (Revenue Score) | @snowflake-sql-expert | 8, 11 |
| 20 | `tests/python/test_pipelines.py` | Create | Testes dos 3 pipelines de ingestão (era gap do Sprint 1) | @python-developer | 14, 15, 16 |

**Total Sprint 2b: 14 arquivos (2 modify, 12 create)**

---

### Sprint 2c — P1 KBS + Operations Agent (4 semanas)

| # | File | Action | Purpose | Agent | Dependencies |
|---|------|--------|---------|-------|--------------|
| 21 | `native_app/setup_script.sql` | Modify (cont.) | Adicionar schema KBS, tabelas KBS.*, Cortex Search service KB_SEARCH_SERVICE | @snowflake-cortex-expert | 2 |
| 22 | `snowflake/setup/16_kbs_schema.sql` | Create | DDL standalone: KBS.DOCUMENTS, KBS.CHUNKS, KBS.SOURCES, KBS.SEARCH_LOGS | @snowflake-sql-expert | None |
| 23 | `snowflake/cortex/search_services/kbs_search.sql` | Create | CREATE CORTEX SEARCH SERVICE KB_SEARCH_SERVICE sobre KBS.DOCUMENTS | @snowflake-cortex-expert | 22 |
| 24 | `snowflake/agents/operations_agent.yaml` | Create | 6º agente Cortex: Operations Agent com tools DMF + AUDIT + TICKETS + HEALTH | @snowflake-cortex-expert | 8 |
| 25 | `pipelines/kbs/load_kb_snowflake.py` | Create | Loader: crawl docs.snowflake.com → chunk → KBS.DOCUMENTS (kb_name=KB_SNOWFLAKE_CORE) | @python-developer | 22 |
| 26 | `pipelines/kbs/load_kb_cortex.py` | Create | Loader: crawl docs.snowflake.com/cortex → chunk → KBS.DOCUMENTS (kb_name=KB_CORTEX_AI) | @python-developer | 22 |
| 27 | `pipelines/kbs/chunker.py` | Create | Módulo de chunking: split por seção, overlap 100 tokens, metadados preservados | @python-developer | None |
| 28 | `airflow/dags/kbs_refresh_dag.py` | Create | Airflow DAG: atualizar KBs semanalmente (re-crawl + re-index) | @airflow-specialist | 25, 26 |
| 29 | `tests/python/test_kbs.py` | Create | Testes do KBS loader, chunker e busca AT-104 | @python-developer | 25, 26, 27 |
| 30 | `tests/python/test_audit_logger.py` | Create | Testes do audit_logger.py (era gap do Sprint 1) | @python-developer | None |

**Total Sprint 2c: 10 arquivos (1 modify, 9 create)**

---

### Sprint 2 — P2 (paralelo, menor prioridade)

| # | File | Action | Purpose | Agent | Dependencies |
|---|------|--------|---------|-------|--------------|
| 31 | `app/streamlit/pages/11_Sales_Intelligence.py` | Create | Página: pipeline por rep, deal forecast, win rate por segmento | @python-developer | 7, 8 |
| 32 | `app/streamlit/pages/12_Operations_Intelligence.py` | Create | Página: SLA compliance, ticket volume, anomalias operacionais | @python-developer | 24 |
| 33 | `terraform/modules/security/main.tf` | Create | Módulo Terraform: IAM roles, secrets, network policies | @ci-cd-specialist | None |
| 34 | `terraform/modules/monitoring/main.tf` | Create | Módulo Terraform: alertas, dashboards, budget alerts | @ci-cd-specialist | None |

**Total P2: 4 arquivos (4 create)**

---

**TOTAL Sprint 2: 34 arquivos | 5 modify | 29 create**

---

## Agent Assignment Rationale

| Agent | Files # | Why This Agent |
|-------|---------|----------------|
| @snowflake-governance-expert | 1, 13 | manifest.yml references syntax + RBAC agent roles patterns |
| @snowflake-data-engineer | 2, 7, 8, 10, 11, 12, 14 | Dynamic Tables, Tasks, External Stages, Snowpipe — especialidade core |
| @snowflake-sql-expert | 3, 6, 9, 19, 22 | DDL SQL, stored procedures, testes SQL |
| @snowflake-cortex-expert | 21, 23, 24 | Cortex Search service + Cortex Agents YAML |
| @python-developer | 4, 5, 20, 25, 26, 27, 29, 30, 31, 32 | Streamlit, pipelines Python, loaders, testes pytest |
| @airflow-specialist | 14, 15, 16, 17, 18, 28 | DAGs TaskFlow API 3.0, conexões Airflow |
| @ci-cd-specialist | 33, 34 | Terraform modules |

---

## Code Patterns

### Pattern 1: manifest.yml — bloco `references:` completo

```yaml
# native_app/manifest.yml — ADICIONAR após o bloco privileges:
references:
  - name: customer_table
    label: "Tabela de Clientes (obrigatório campos: customer_id, email, created_at)"
    description: >
      Mapeie sua tabela principal de clientes. O NEXUS usa esta tabela para
      calcular churn score, health score e revenue metrics.
    object_type: TABLE
    register_callback: CORE.REGISTER_REFERENCE
    required: false

  - name: transactions_table
    label: "Tabela de Transações (obrigatório campos: transaction_id, customer_id, amount, created_at)"
    description: >
      Mapeie sua tabela de transações/faturamento para análise de receita.
    object_type: TABLE
    register_callback: CORE.REGISTER_REFERENCE
    required: false

  - name: events_table
    label: "Tabela de Eventos de Produto (obrigatório campos: user_id, event_name, occurred_at)"
    description: >
      Mapeie eventos de uso do produto para análise de engajamento e feature usage.
    object_type: TABLE
    register_callback: CORE.REGISTER_REFERENCE
    required: false

# Adicionar também no bloco privileges:
privileges:
  - EXECUTE TASK
  - EXECUTE MANAGED TASK
  - CREATE DATABASE
  - EXTERNAL_ACCESS_INTEGRATION   # ← NOVO: para Salesforce/Zendesk/Stripe APIs
```

---

### Pattern 2: RAP por org_id no setup_script.sql

```sql
-- Em setup_script.sql — ADICIONAR antes dos GRANTs

-- Tabela de mapeamento user → org_id
CREATE TABLE IF NOT EXISTS NEXUS_APP.CONFIG.USER_ORG_MAPPING (
    user_login_name  VARCHAR(255) NOT NULL,
    org_id           VARCHAR(50)  NOT NULL,
    role             VARCHAR(50)  DEFAULT 'analyst',   -- admin | analyst | readonly
    created_at       TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_user_org_mapping PRIMARY KEY (user_login_name, org_id)
);

-- Inserir admin padrão (consumer muda no wizard)
INSERT INTO NEXUS_APP.CONFIG.USER_ORG_MAPPING VALUES
    ('NEXUS_ADMIN', 'ORG-DEMO-001', 'admin', CURRENT_TIMESTAMP()),
    ('NEXUS_ANALYST', 'ORG-DEMO-001', 'analyst', CURRENT_TIMESTAMP());

-- Row Access Policy por org_id
CREATE OR REPLACE ROW ACCESS POLICY NEXUS_APP.CORE.RAP_ORG_ISOLATION
  AS (row_org_id VARCHAR) RETURNS BOOLEAN ->
  EXISTS (
    SELECT 1
    FROM NEXUS_APP.CONFIG.USER_ORG_MAPPING m
    WHERE m.user_login_name = CURRENT_USER()
      AND m.org_id = row_org_id
  );

-- Aplicar RAP nas tabelas core (exemplo CUSTOMERS — repetir para todas)
ALTER TABLE NEXUS_APP.CORE.CUSTOMERS
  ADD ROW ACCESS POLICY NEXUS_APP.CORE.RAP_ORG_ISOLATION ON (org_id);

ALTER TABLE NEXUS_APP.CORE.TRANSACTIONS
  ADD ROW ACCESS POLICY NEXUS_APP.CORE.RAP_ORG_ISOLATION ON (org_id);

ALTER TABLE NEXUS_APP.CORE.ACCOUNTS
  ADD ROW ACCESS POLICY NEXUS_APP.CORE.RAP_ORG_ISOLATION ON (org_id);

ALTER TABLE NEXUS_APP.CORE.PRODUCTS
  ADD ROW ACCESS POLICY NEXUS_APP.CORE.RAP_ORG_ISOLATION ON (org_id);

ALTER TABLE NEXUS_APP.CORE.INTERACTIONS
  ADD ROW ACCESS POLICY NEXUS_APP.CORE.RAP_ORG_ISOLATION ON (org_id);
```

---

### Pattern 3: REGISTER_REFERENCE SP atualizado

```sql
-- snowflake/stored_procedures/register_reference.sql
CREATE OR REPLACE PROCEDURE NEXUS_APP.CORE.REGISTER_REFERENCE(
    ref_name    VARCHAR,
    operation   VARCHAR,
    ref_or_alias VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS $$
BEGIN
    -- operation = 'ADD' quando consumer mapeia a tabela
    -- operation = 'REMOVE' quando consumer desmapeia
    -- ref_or_alias = o token SYSTEM$REFERENCE gerado pelo Snowflake

    IF (operation = 'ADD') THEN
        MERGE INTO NEXUS_APP.CONFIG.DATA_SOURCES AS tgt
        USING (SELECT :ref_name AS source_name, :ref_or_alias AS ref_token,
                      CURRENT_TIMESTAMP() AS mapped_at) AS src
        ON tgt.source_name = src.source_name
        WHEN MATCHED THEN
            UPDATE SET ref_token = src.ref_token, mapped_at = src.mapped_at,
                       is_active = TRUE
        WHEN NOT MATCHED THEN
            INSERT (source_name, ref_token, mapped_at, is_active)
            VALUES (src.source_name, src.ref_token, src.mapped_at, TRUE);

    ELSEIF (operation = 'REMOVE') THEN
        UPDATE NEXUS_APP.CONFIG.DATA_SOURCES
        SET is_active = FALSE, ref_token = NULL
        WHERE source_name = :ref_name;
    END IF;

    RETURN 'SUCCESS: ' || :operation || ' ' || :ref_name;
END;
$$;
```

---

### Pattern 4: Snowflake Task de ingestão no setup_script.sql

```sql
-- Em setup_script.sql — Tasks de ingestão (chegam ao consumer)
-- Task 1: Ingestão de clientes a partir da referência mapeada
CREATE OR REPLACE TASK NEXUS_APP.CORE.TASK_INGEST_CUSTOMERS
  WAREHOUSE = NEXUS_APP_WH
  SCHEDULE = 'USING CRON 0 */1 * * * UTC'   -- a cada 1 hora
  COMMENT = 'Ingere dados do customer_table mapeado pelo consumer'
AS
INSERT INTO NEXUS_APP.CORE.CUSTOMERS (
    customer_id, org_id, name, email, health_score, created_at
)
SELECT
    c.customer_id::VARCHAR(36),
    (SELECT COALESCE(MAX(ref_token), 'ORG-DEMO-001')
     FROM NEXUS_APP.CONFIG.DATA_SOURCES WHERE source_name = 'customer_table'),
    c.name::VARCHAR(255),
    c.email::VARCHAR(255),
    0.5::DECIMAL(4,2),   -- score calculado pelo churn model
    COALESCE(c.created_at, CURRENT_TIMESTAMP())::TIMESTAMP_TZ
FROM TABLE(NEXUS_APP.CORE.GET_REFERENCE_DATA('customer_table')) c
WHERE NOT EXISTS (
    SELECT 1 FROM NEXUS_APP.CORE.CUSTOMERS tgt
    WHERE tgt.customer_id = c.customer_id::VARCHAR(36)
);

-- Task 2: Atualizar briefing executivo (corrige AT-010 que estava falhando)
CREATE OR REPLACE TASK NEXUS_APP.CORE.TASK_EXECUTIVE_BRIEFING
  WAREHOUSE = NEXUS_APP_WH
  SCHEDULE = 'USING CRON 0 7 * * * UTC'   -- todo dia às 7h UTC
  COMMENT = 'Gera AI briefing executivo diário'
AS
CALL NEXUS_APP.CORE.SP_GENERATE_EXECUTIVE_BRIEFING();

-- Ativar tasks (setup_script deve finalizar com RESUME)
ALTER TASK NEXUS_APP.CORE.TASK_INGEST_CUSTOMERS RESUME;
ALTER TASK NEXUS_APP.CORE.TASK_EXECUTIVE_BRIEFING RESUME;
```

---

### Pattern 5: Dynamic Tables no setup_script (chegam ao consumer)

```sql
-- Em setup_script.sql — Dynamic Tables que o consumer recebe
CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.MART.DT_EXECUTIVE_KPIS
  TARGET_LAG = '1 hour'
  WAREHOUSE = NEXUS_APP_WH
  COMMENT = 'KPIs executivos — atualiza automaticamente a cada 1h'
AS
SELECT
    c.org_id,
    COUNT(DISTINCT c.customer_id)                           AS total_customers,
    ROUND(AVG(c.health_score) * 100, 1)                    AS avg_health_score,
    COUNT(CASE WHEN c.churn_risk_score > 0.7 THEN 1 END)   AS at_risk_count,
    SUM(t.amount)                                           AS total_revenue_mtd,
    CURRENT_TIMESTAMP()                                     AS refreshed_at
FROM NEXUS_APP.CORE.CUSTOMERS c
LEFT JOIN NEXUS_APP.CORE.TRANSACTIONS t
    ON c.customer_id = t.customer_id
    AND MONTH(t.created_at) = MONTH(CURRENT_DATE())
    AND YEAR(t.created_at) = YEAR(CURRENT_DATE())
GROUP BY c.org_id;

-- DT Customer Health
CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.MART.DT_CUSTOMER_HEALTH
  TARGET_LAG = '1 hour'
  WAREHOUSE = NEXUS_APP_WH
AS
SELECT
    c.customer_id,
    c.org_id,
    c.name,
    c.health_score,
    c.churn_risk_score,
    CASE
        WHEN c.churn_risk_score >= 0.7 THEN 'CRITICAL'
        WHEN c.churn_risk_score >= 0.5 THEN 'AT_RISK'
        WHEN c.churn_risk_score >= 0.3 THEN 'HEALTHY'
        ELSE 'CHAMPION'
    END                                                     AS health_segment,
    COUNT(t.transaction_id)                                 AS total_transactions,
    SUM(t.amount)                                           AS total_revenue,
    CURRENT_TIMESTAMP()                                     AS refreshed_at
FROM NEXUS_APP.CORE.CUSTOMERS c
LEFT JOIN NEXUS_APP.CORE.TRANSACTIONS t USING (customer_id)
GROUP BY c.customer_id, c.org_id, c.name, c.health_score, c.churn_risk_score;
```

---

### Pattern 6: KBS — DDL das tabelas

```sql
-- snowflake/setup/16_kbs_schema.sql + em setup_script.sql
CREATE SCHEMA IF NOT EXISTS NEXUS_APP.KBS;

CREATE TABLE IF NOT EXISTS NEXUS_APP.KBS.DOCUMENTS (
    doc_id      VARCHAR(36)    NOT NULL DEFAULT UUID_STRING(),
    kb_name     VARCHAR(100)   NOT NULL,   -- KB_SNOWFLAKE_CORE | KB_CORTEX_AI | etc.
    title       VARCHAR(500)   NOT NULL,
    content     TEXT           NOT NULL,   -- chunk de texto (400-600 tokens)
    source_url  VARCHAR(1000),
    doc_type    VARCHAR(50),               -- official_doc | tutorial | best_practice | faq
    version     VARCHAR(20),
    chunk_index INTEGER        DEFAULT 0,  -- posição do chunk no documento original
    total_chunks INTEGER       DEFAULT 1,
    indexed_at  TIMESTAMP_TZ   DEFAULT CURRENT_TIMESTAMP(),
    is_active   BOOLEAN        DEFAULT TRUE,
    CONSTRAINT pk_kbs_documents PRIMARY KEY (doc_id)
);

-- Cluster key por kb_name para filtros eficientes no Cortex Search
ALTER TABLE NEXUS_APP.KBS.DOCUMENTS CLUSTER BY (kb_name);

CREATE TABLE IF NOT EXISTS NEXUS_APP.KBS.SOURCES (
    source_id   VARCHAR(36)    NOT NULL DEFAULT UUID_STRING(),
    kb_name     VARCHAR(100)   NOT NULL,
    source_url  VARCHAR(1000)  NOT NULL,
    title       VARCHAR(500),
    last_crawled TIMESTAMP_TZ,
    doc_count   INTEGER        DEFAULT 0,
    is_active   BOOLEAN        DEFAULT TRUE,
    CONSTRAINT pk_kbs_sources PRIMARY KEY (source_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.KBS.SEARCH_LOGS (
    log_id      VARCHAR(36)    NOT NULL DEFAULT UUID_STRING(),
    kb_name     VARCHAR(100),
    query_text  TEXT,
    result_count INTEGER,
    top_doc_id  VARCHAR(36),
    user_feedback VARCHAR(20),   -- thumbs_up | thumbs_down | null
    latency_ms  INTEGER,
    created_at  TIMESTAMP_TZ   DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_kbs_search_logs PRIMARY KEY (log_id)
);

-- Cortex Search Service (KB unificado com filtro por kb_name)
CREATE OR REPLACE CORTEX SEARCH SERVICE NEXUS_APP.KBS.KB_SEARCH_SERVICE
  ON content
  ATTRIBUTES kb_name, doc_type, source_url, title
  WAREHOUSE = NEXUS_APP_WH
  TARGET_LAG = '7 days'     -- Atualiza semanalmente (custo controlado)
AS (
    SELECT content, kb_name, doc_type, source_url, title, doc_id
    FROM NEXUS_APP.KBS.DOCUMENTS
    WHERE is_active = TRUE
);
```

---

### Pattern 7: Operations Agent YAML

```yaml
# snowflake/agents/operations_agent.yaml
name: operations_agent
model: claude-sonnet-4-6
description: "Agente de Inteligência Operacional — analisa SLA, tickets, anomalias e saúde dos sistemas"

system_prompt: |
  Você é o Agente de Operações do NEXUS AI DataOps. Seu papel é monitorar e analisar
  a saúde operacional do negócio, incluindo:
  - Cumprimento de SLAs de suporte
  - Volume e tendência de tickets
  - Anomalias em métricas operacionais
  - Alertas proativos de degradação
  
  Sempre filtre dados pelo org_id do usuário atual. Seja preciso com números.
  Quando identificar problemas, sugira ações corretivas.

tools:
  - name: query_tickets
    type: snowflake_sql
    sql: |
      SELECT status, priority, category, COUNT(*) as count,
             AVG(DATEDIFF('hour', created_at, COALESCE(resolved_at, CURRENT_TIMESTAMP()))) as avg_resolution_hours
      FROM NEXUS_APP.CORE.TICKETS
      WHERE org_id = :org_id
        AND created_at >= DATEADD('day', -30, CURRENT_DATE())
      GROUP BY status, priority, category
      ORDER BY count DESC
    parameters: [org_id]

  - name: query_sla_compliance
    type: snowflake_sql
    sql: |
      SELECT
        CASE WHEN resolution_hours <= 24 THEN 'SLA_MET' ELSE 'SLA_BREACH' END as sla_status,
        priority,
        COUNT(*) as ticket_count
      FROM (
        SELECT priority,
               DATEDIFF('hour', created_at, COALESCE(resolved_at, CURRENT_TIMESTAMP())) as resolution_hours
        FROM NEXUS_APP.CORE.TICKETS
        WHERE org_id = :org_id
          AND created_at >= DATEADD('day', -30, CURRENT_DATE())
      ) t
      GROUP BY sla_status, priority
    parameters: [org_id]

  - name: query_customer_health_anomalies
    type: snowflake_sql
    sql: |
      SELECT customer_id, name, health_score,
             churn_risk_score, health_segment
      FROM NEXUS_APP.MART.DT_CUSTOMER_HEALTH
      WHERE org_id = :org_id
        AND health_segment IN ('CRITICAL', 'AT_RISK')
      ORDER BY churn_risk_score DESC
      LIMIT 20
    parameters: [org_id]

  - name: search_operations_knowledge
    type: cortex_search
    service: NEXUS_APP.KBS.KB_SEARCH_SERVICE
    filter_columns: {kb_name: "KB_SNOWFLAKE_CORE"}
    top_k: 3

guardrails:
  - block_pii_in_response: true
  - max_response_tokens: 2000
  - org_id_required: true

example_questions:
  - "Como estão nossos SLAs de suporte este mês?"
  - "Quais clientes têm risco crítico de churn?"
  - "Há anomalias nos tickets das últimas 48 horas?"
  - "Qual é o tempo médio de resolução por prioridade?"
```

---

### Pattern 8: Onboarding Wizard — 0_Setup.py

```python
# app/streamlit/pages/0_Setup.py
import streamlit as st
from utils.onboarding import (
    get_onboarding_status,
    map_reference_table,
    save_api_credential,
    save_user_org_mapping,
    validate_table_schema,
)
from utils.auth import get_org_id

st.set_page_config(page_title="NEXUS — Setup", layout="wide")
st.title("Configuracao Inicial — NEXUS AI DataOps")

org_id = get_org_id()
status = get_onboarding_status(org_id)

# Step 1: Mapeamento de tabelas
with st.expander("Passo 1: Conectar suas fontes de dados", expanded=not status["tables_mapped"]):
    st.info(
        "Mapeie suas tabelas Snowflake para que o NEXUS use seus dados reais. "
        "Se nao mapear, o NEXUS usa dados demonstracao."
    )

    col1, col2 = st.columns(2)
    with col1:
        customer_table = st.text_input(
            "Tabela de Clientes (DATABASE.SCHEMA.TABLE)",
            value=status.get("customer_table", ""),
            placeholder="MY_DB.MY_SCHEMA.CUSTOMERS",
        )
        if st.button("Validar e Mapear Clientes"):
            validation = validate_table_schema(
                customer_table,
                required_columns=["customer_id", "email", "created_at"],
            )
            if validation["valid"]:
                map_reference_table("customer_table", customer_table)
                st.success(f"Tabela mapeada! {validation['row_count']:,} clientes encontrados.")
            else:
                st.error(f"Schema invalido: colunas faltando: {validation['missing_columns']}")

    with col2:
        transactions_table = st.text_input(
            "Tabela de Transacoes",
            value=status.get("transactions_table", ""),
            placeholder="BILLING.PUBLIC.INVOICES",
        )
        if st.button("Validar e Mapear Transacoes"):
            validation = validate_table_schema(
                transactions_table,
                required_columns=["transaction_id", "customer_id", "amount", "created_at"],
            )
            if validation["valid"]:
                map_reference_table("transactions_table", transactions_table)
                st.success("Tabela de transacoes mapeada!")
            else:
                st.error(f"Schema invalido: {validation['missing_columns']}")

    if st.button("Usar apenas dados demonstracao", type="secondary"):
        st.info("OK! O NEXUS usara os dados de demonstracao pre-carregados.")

# Step 2: Multi-tenancy
with st.expander("Passo 2: Configurar Organizacao e Usuarios", expanded=not status["org_configured"]):
    st.write("Configure o isolamento multi-tenant para sua organizacao.")

    new_org_id = st.text_input("ID da Organizacao", value=org_id, placeholder="ACME-CORP-001")
    
    st.subheader("Mapeamento de Usuarios")
    users_df = status.get("users", [])
    
    new_user = st.text_input("Login do Usuario Snowflake")
    new_role = st.selectbox("Role", ["analyst", "admin", "readonly"])
    
    if st.button("Adicionar Usuario"):
        save_user_org_mapping(new_user, new_org_id, new_role)
        st.success(f"Usuario {new_user} mapeado para org {new_org_id} com role {new_role}")

# Step 3: Credenciais de API
with st.expander("Passo 3: Credenciais de API (opcional)", expanded=False):
    st.info("Configure credenciais para sincronizacao automatica de Salesforce, Zendesk e Stripe.")

    salesforce_token = st.text_input("Salesforce API Token", type="password")
    salesforce_instance = st.text_input("Salesforce Instance URL", placeholder="https://mycompany.salesforce.com")
    if st.button("Salvar Salesforce"):
        save_api_credential(org_id, "salesforce", {"token": salesforce_token, "instance_url": salesforce_instance})
        st.success("Credenciais Salesforce salvas com seguranca!")

    st.divider()
    zendesk_token = st.text_input("Zendesk API Token", type="password")
    zendesk_subdomain = st.text_input("Zendesk Subdomain", placeholder="mycompany")
    if st.button("Salvar Zendesk"):
        save_api_credential(org_id, "zendesk", {"token": zendesk_token, "subdomain": zendesk_subdomain})
        st.success("Credenciais Zendesk salvas!")

# Status final
st.divider()
st.subheader("Status do Onboarding")
cols = st.columns(4)
cols[0].metric("Tabelas Mapeadas", "3/3" if status["tables_mapped"] else "0/3")
cols[1].metric("Usuarios Configurados", len(status.get("users", [])))
cols[2].metric("APIs Conectadas", status.get("api_count", 0))
cols[3].metric("Dados", "Reais" if status["tables_mapped"] else "Demo")

if status["tables_mapped"] and status["org_configured"]:
    st.success("Setup completo! Acesse o Dashboard Executivo para ver seus dados.")
    if st.button("Ir para o Dashboard", type="primary"):
        st.switch_page("pages/1_Executive_Command.py")
```

---

### Pattern 9: Airflow DAG — Salesforce (TaskFlow API 3.0)

```python
# airflow/dags/salesforce_ingest_dag.py
from datetime import datetime, timedelta
from airflow.decorators import dag, task
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook


@dag(
    dag_id="nexus_salesforce_ingest",
    description="Pull Salesforce CRM data → NEXUS CORE.CUSTOMERS",
    schedule="0 */1 * * *",   # hourly
    start_date=datetime(2026, 6, 19),
    catchup=False,
    default_args={
        "owner": "nexus-team",
        "retries": 3,
        "retry_delay": timedelta(minutes=5),
        "email_on_failure": True,
        "email": ["ops@nexus.ai"],
    },
    tags=["nexus", "salesforce", "ingestion"],
)
def salesforce_ingest():

    @task()
    def extract_salesforce(**context) -> dict:
        """Pull updated contacts from Salesforce using simple_salesforce."""
        from simple_salesforce import Salesforce
        import os

        sf = Salesforce(
            instance_url=os.environ["SALESFORCE_INSTANCE_URL"],
            session_id=os.environ["SALESFORCE_TOKEN"],
        )

        # Pull contacts updated in the last 2 hours (overlap for safety)
        since = context["data_interval_start"].isoformat()
        query = f"""
            SELECT Id, Name, Email, AccountId, CreatedDate, LastModifiedDate
            FROM Contact
            WHERE LastModifiedDate >= {since}
            ORDER BY LastModifiedDate ASC
            LIMIT 10000
        """
        result = sf.query_all(query)
        return {
            "records": result["records"],
            "total": result["totalSize"],
            "org_id": os.environ.get("NEXUS_ORG_ID", "ORG-DEMO-001"),
        }

    @task()
    def load_to_snowflake(payload: dict) -> str:
        """MERGE extracted records into NEXUS_APP.CORE.CUSTOMERS."""
        hook = SnowflakeHook(snowflake_conn_id="snowflake_default")

        if not payload["records"]:
            return f"No records to load. Total from Salesforce: {payload['total']}"

        rows = [
            (
                r["Id"],
                payload["org_id"],
                r.get("Name", ""),
                r.get("Email", ""),
                0.5,   # churn score calculated separately by ML task
                r["CreatedDate"],
            )
            for r in payload["records"]
        ]

        merge_sql = """
            MERGE INTO NEXUS_APP.CORE.CUSTOMERS AS tgt
            USING (SELECT %s AS customer_id, %s AS org_id, %s AS name,
                          %s AS email, %s::DECIMAL(4,2) AS churn_risk_score,
                          %s::TIMESTAMP_TZ AS created_at) AS src
            ON tgt.customer_id = src.customer_id
            WHEN MATCHED THEN
                UPDATE SET name = src.name, email = src.email
            WHEN NOT MATCHED THEN
                INSERT (customer_id, org_id, name, email, churn_risk_score, created_at)
                VALUES (src.customer_id, src.org_id, src.name, src.email,
                        src.churn_risk_score, src.created_at)
        """
        hook.run(merge_sql, parameters=rows[0])   # executemany pattern

        return f"Loaded {len(rows)} records for org {payload['org_id']}"

    payload = extract_salesforce()
    load_to_snowflake(payload)


salesforce_ingest()
```

---

### Pattern 10: KBS Loader — load_kb_snowflake.py

```python
# pipelines/kbs/load_kb_snowflake.py
from dataclasses import dataclass
from typing import Generator
import requests
from bs4 import BeautifulSoup
from pipelines.kbs.chunker import Chunker
from snowflake.connector import connect


@dataclass
class KBDocument:
    title: str
    content: str
    source_url: str
    doc_type: str
    kb_name: str = "KB_SNOWFLAKE_CORE"


SNOWFLAKE_DOCS_URLS = [
    ("https://docs.snowflake.com/en/developer-guide/native-apps/native-apps-about", "official_doc"),
    ("https://docs.snowflake.com/en/user-guide/dynamic-tables-intro", "official_doc"),
    ("https://docs.snowflake.com/en/user-guide/tasks-intro", "official_doc"),
    ("https://docs.snowflake.com/en/user-guide/streams-intro", "official_doc"),
    ("https://docs.snowflake.com/en/user-guide/cortex-search/cortex-search-overview", "official_doc"),
]


def crawl_page(url: str, doc_type: str) -> KBDocument | None:
    resp = requests.get(url, timeout=10)
    if resp.status_code != 200:
        return None

    soup = BeautifulSoup(resp.text, "html.parser")
    title = soup.find("h1").get_text(strip=True) if soup.find("h1") else url
    body = soup.find("main") or soup.find("article") or soup.find("body")
    content = body.get_text(separator="\n", strip=True) if body else ""

    return KBDocument(title=title, content=content, source_url=url, doc_type=doc_type)


def load_kb(conn_params: dict, kb_name: str = "KB_SNOWFLAKE_CORE") -> int:
    """Load all Snowflake Core docs into KBS.DOCUMENTS. Returns count of chunks inserted."""
    chunker = Chunker(chunk_size=500, overlap=50)
    conn = connect(**conn_params)
    cursor = conn.cursor()

    total = 0
    for url, doc_type in SNOWFLAKE_DOCS_URLS:
        doc = crawl_page(url, doc_type)
        if not doc:
            continue

        chunks = list(chunker.split(doc.content))
        for idx, chunk in enumerate(chunks):
            cursor.execute(
                """
                INSERT INTO NEXUS_APP.KBS.DOCUMENTS
                    (kb_name, title, content, source_url, doc_type, chunk_index, total_chunks)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (kb_name, doc.title, chunk, url, doc_type, idx, len(chunks)),
            )
            total += 1

    conn.commit()
    cursor.close()
    conn.close()
    return total


if __name__ == "__main__":
    import os
    params = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "password": os.environ["SNOWFLAKE_PASSWORD"],
        "database": "NEXUS_APP",
        "schema": "KBS",
        "warehouse": "NEXUS_APP_WH",
    }
    count = load_kb(params)
    print(f"Loaded {count} chunks into KB_SNOWFLAKE_CORE")
```

---

## Integration Points

| External System | Integration Type | Authentication | Sprint |
|-----------------|-----------------|----------------|--------|
| Salesforce CRM | REST API via External Access Integration | API Token em CONFIG.API_CREDENTIALS | P0/P1 |
| Zendesk Support | REST API via External Access Integration | API Key em CONFIG.API_CREDENTIALS | P0/P1 |
| Stripe Billing | REST API via External Access Integration | API Key em CONFIG.API_CREDENTIALS | P0/P1 |
| docs.snowflake.com | HTTP GET via Airflow (provider-side) | Sem autenticação | P1 |
| S3 (consumer's bucket) | External Stage | Storage Integration + IAM Role | P1 |
| Azure Blob (consumer's) | External Stage | Storage Integration + Service Principal | P1 |
| GCS (consumer's bucket) | External Stage | Storage Integration + Service Account | P1 |

---

## Pipeline Architecture

### DAG Diagram (Airflow — provider-side)

```text
[Salesforce API] ──extract──→ [payload dict] ──load──→ [NEXUS_APP.CORE.CUSTOMERS]
[Zendesk API]    ──extract──→ [payload dict] ──load──→ [NEXUS_APP.CORE.TICKETS]
[Stripe API]     ──extract──→ [payload dict] ──load──→ [NEXUS_APP.CORE.TRANSACTIONS]

[docs.snowflake.com] ──crawl──→ [chunks] ──insert──→ [NEXUS_APP.KBS.DOCUMENTS]
                                                              ↓
                                              [KB_SEARCH_SERVICE re-index]
```

### Partition / Cluster Strategy

| Table | Cluster Key | Rationale |
|-------|-------------|-----------|
| `CORE.CUSTOMERS` | `(org_id)` | RAP filtra por org_id; cluster melhora pruning |
| `CORE.TRANSACTIONS` | `(org_id, created_at::DATE)` | Query de revenue sempre tem filtro temporal |
| `KBS.DOCUMENTS` | `(kb_name)` | Cortex Search filtra por kb_name em todas as queries |
| `AUDIT.ACTION_LOG` | `(created_at::DATE)` | Queries de auditoria são sempre por período |

### Incremental Strategy

| Model | Strategy | Key Column | Lookback |
|-------|----------|------------|----------|
| CORE.CUSTOMERS (Task) | MERGE on customer_id | `customer_id` | N/A (full MERGE) |
| CORE.TRANSACTIONS (Task) | INSERT where not exists | `transaction_id` | 2h overlap |
| KBS.DOCUMENTS (DAG) | TRUNCATE + full reload | `source_url` | Weekly |
| MART.DT_* | Dynamic Table (automatic) | N/A | Managed by Snowflake |

---

## Testing Strategy

| Test Type | AT # | Arquivo | Tools | Como executar |
|-----------|------|---------|-------|---------------|
| SQL Integration | AT-101 | `tests/sql/test_references.sql` | Snowflake SQL | `snowsql -f tests/sql/test_references.sql` |
| SQL Integration | AT-102 | `tests/sql/test_multitenancy.sql` | Snowflake SQL | `snowsql -f tests/sql/test_multitenancy.sql` |
| End-to-End Manual | AT-103 | — | Manual | Aguardar 1h Task execução |
| Unit + Integration | AT-104 | `tests/python/test_kbs.py` | pytest | `pytest tests/python/test_kbs.py -v` |
| SQL Integration | AT-105 | `tests/sql/test_dynamic_tables.sql` | Snowflake SQL | `SHOW DYNAMIC TABLES` + query |
| Manual | AT-106 | — | Manual | Upload CSV → External Stage → verificar COPY INTO |
| SQL Integration | AT-107 | `tests/sql/test_dynamic_tables.sql` | Snowflake SQL | `SELECT COUNT(*) FROM MART.DT_REVENUE_OPPORTUNITY_SCORE` |
| Chat Manual | AT-108 | — | Manual | Chat com Operations Agent no 3_AI_Chat.py |

### Testes SQL de aceitação críticos

```sql
-- tests/sql/test_references.sql
-- AT-101: Verificar que REGISTER_REFERENCE funciona após mapeamento
SELECT source_name, is_active, mapped_at
FROM NEXUS_APP.CONFIG.DATA_SOURCES
WHERE source_name = 'customer_table';
-- Expected: 1 row, is_active = TRUE, mapped_at recente

-- AT-102: Isolamento multi-tenant
-- Setup: garantir 2 orgs na USER_ORG_MAPPING
-- Executar como usuário de ORG-A
SET ROLE NEXUS_ANALYST;
SELECT DISTINCT org_id FROM NEXUS_APP.CORE.CUSTOMERS;
-- Expected: apenas 'ORG-DEMO-001' (ou o org_id mapeado para o usuário atual)
```

---

## Error Handling

| Error Type | Handling Strategy | Retry? |
|------------|-------------------|--------|
| consumer table não mapeada | Fallback para demo data (CORE.CUSTOMERS já tem MERGE INTO) | N/A |
| Salesforce API timeout | Airflow retry 3x com backoff exponencial; logar em AUDIT.ACTION_LOG | Sim (3x) |
| Cortex Search service indisponível | Fallback para `AI_COMPLETE` sem RAG; log warning | Não |
| RAP sem mapeamento de usuário | SELECT retorna 0 linhas; UI exibe "Configure seu org_id em 0_Setup" | Não |
| External Stage sem permissão | Erro capturado em Task; notificação via NOTIFICATION_INTEGRATION | Não |
| KBS chunk vazio | Skip em `chunker.py`; log de warning com source_url | N/A |
| Task falha | Snowflake notifica via NOTIFICATION_INTEGRATION (Slack webhook) | Sim (1x) |

---

## Configuration

| Config Key | Where | Default | Description |
|------------|-------|---------|-------------|
| `NEXUS_ORG_ID` | env var (Airflow) | `ORG-DEMO-001` | Org do consumer no Airflow provider-side |
| `SALESFORCE_TOKEN` | Airflow Connection | — | API token Salesforce |
| `SALESFORCE_INSTANCE_URL` | Airflow Connection | — | URL da instância Salesforce |
| `ZENDESK_TOKEN` | Airflow Connection | — | API key Zendesk |
| `STRIPE_API_KEY` | Airflow Connection | — | API key Stripe |
| `SNOWFLAKE_ACCOUNT` | Airflow Connection | — | Account Snowflake do consumer |
| `KBS_CHUNK_SIZE` | `chunker.py` | 500 | Tokens por chunk |
| `KBS_OVERLAP` | `chunker.py` | 50 | Tokens de overlap entre chunks |
| `TASK_SCHEDULE` | `setup_script.sql` | `USING CRON 0 */1 * * * UTC` | Schedule das Tasks de ingestão |
| `DT_TARGET_LAG` | `setup_script.sql` | `1 hour` | Lag das Dynamic Tables |

---

## Security Considerations

- **Credenciais de API**: nunca em código — armazenadas em `CONFIG.API_CREDENTIALS` (VARIANT criptografado) ou Airflow Connections com Fernet encryption. Migrar para Snowflake Secrets Manager no Sprint 3.
- **SYSTEM$REFERENCE tokens**: efêmeros — o token é gerado pelo Snowflake e armazenado em `CONFIG.DATA_SOURCES`. Nunca logar o token.
- **RAP garante que dados de ORG-A nunca vazem para ORG-B** — verificar com AT-102 antes de qualquer deploy em produção com múltiplos tenants.
- **External Access Integration**: consumer aprova explicitamente no install; lista de domínios permitidos deve ser restrita (api.salesforce.com, api.zendesk.com, api.stripe.com, docs.snowflake.com).
- **KBS.DOCUMENTS**: não armazenar PII — o conteúdo deve ser documentação técnica pública. Verificar antes de carregar qualquer conteúdo privado.
- **Airflow connections**: usar Airflow Secret Backend (AWS Secrets Manager ou GCP Secret Manager) em produção, não variáveis de ambiente plain-text.

---

## Observability

| Aspect | Implementation |
|--------|----------------|
| Task failures | `NOTIFICATION_INTEGRATION` → Slack webhook em `#nexus-alerts` |
| KBS search quality | `KBS.SEARCH_LOGS` com latência, result count, feedback do usuário |
| Ingest volume | `AUDIT.ACTION_LOG` registra cada execução de pipeline com row count |
| DT freshness | `SHOW DYNAMIC TABLES` → `data_timestamp` < NOW() - INTERVAL '2 hours' = alert |
| RAP violations | Snowflake Account Usage `QUERY_HISTORY` → queries que retornam 0 rows inesperadamente |
| Airflow | DAG success/failure rate no Airflow UI; email on failure para ops@nexus.ai |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-06-19 | design-agent | Versão inicial — 34 arquivos, 5 decisões arquiteturais, 10 code patterns |

---

## Next Step

**Ready for:** `/build .claude/sdd/features/DESIGN_NEXUS_SPRINT2_DATA_ONBOARDING.md`

> Build order obrigatório (dependências):
> 1. `manifest.yml` (file #1) — base para tudo
> 2. `setup_script.sql` — RAP + CONFIG.USER_ORG_MAPPING (file #2)
> 3. `register_reference.sql` (file #3) — depende de DATA_SOURCES no setup
> 4. `0_Setup.py` + `utils/onboarding.py` (files #4, #5) — depende de #2 e #3
> 5. Tests AT-101/AT-102 (file #6) — validam P0
> 6. Canonical tables DDL (file #9) → setup_script additions (files #7, #8)
> 7. Dynamic Tables (file #10, #11) → depende de #9
> 8. External Stages (file #12), Agent Roles (file #13)
> 9. Airflow DAGs (files #14-#18) — independentes, paralelos
> 10. KBS DDL (file #22) → Cortex Search (file #23) → Operations Agent (file #24)
> 11. KBS Loaders (files #25-#27) → Airflow DAG refresh (file #28)
> 12. P2 pages (files #31-#32) — após #7 e #24 completos
